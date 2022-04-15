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
-- Name: create_foreign_servers(integer, character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_foreign_servers(amount integer, domain character varying DEFAULT 'perf.taler'::character varying) RETURNS void
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
     ,'taler'
     ,'taler'
     ,'taler-exchange'
     ,'5432'
     ,'taler-exchange-httpd'
    );
  END LOOP;

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
exchange-0001	2022-04-15 11:21:47.805213+02	grothoff	{}	{}
merchant-0001	2022-04-15 11:21:48.756437+02	grothoff	{}	{}
auditor-0001	2022-04-15 11:21:49.292224+02	grothoff	{}	{}
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
1	TESTKUDOS:100	Joining bonus	2022-04-15 11:21:58.260383+02	f	9b863d09-a647-41c6-a4dd-ffefb143e0b5	12	1
2	TESTKUDOS:10	TVD7DWZSRNFE1Q49QTT5X81J0ATBD4N3M132YGH2BDRESZ8Z0QDG	2022-04-15 11:22:01.96402+02	f	2b48ae27-bc17-40be-93ce-34b1e75645ac	2	12
3	TESTKUDOS:100	Joining bonus	2022-04-15 11:22:08.804129+02	f	87b890a9-112d-4fc4-a549-fb5165361b06	13	1
4	TESTKUDOS:18	G5S2W4R81Q8QEPMSEYP2HYC1T23JWTQQJM7DQWZ1A7F0E8P20E60	2022-04-15 11:22:09.403794+02	f	8d616a8e-4e9b-45f2-9173-85700d0a7619	2	13
\.


--
-- Data for Name: app_talerwithdrawoperation; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_talerwithdrawoperation (withdraw_id, amount, selection_done, confirmation_done, aborted, selected_reserve_pub, selected_exchange_account_id, withdraw_account_id) FROM stdin;
85c173a9-7e67-4376-bc56-396e16880d61	TESTKUDOS:10	t	t	f	TVD7DWZSRNFE1Q49QTT5X81J0ATBD4N3M132YGH2BDRESZ8Z0QDG	2	12
3f5201b3-d4e2-478e-a21f-e03742e25956	TESTKUDOS:18	t	t	f	G5S2W4R81Q8QEPMSEYP2HYC1T23JWTQQJM7DQWZ1A7F0E8P20E60	2	13
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
1	1	93	\\x58839049ab981d75aba1e007760786735b1ebef97fdcc50adb713b0a9767557a23ee57389b194ccfe56fcb2244caf524e8217916516da13aed507a50b35efd05
2	1	280	\\x56a95c8ef71ab210e59f1ccab804269ade31d3e2e93b2cb710e91b91531674bd864e2bf303cf20df363482147f8bcbdfa686777a245dc79e4df758af0883290a
3	1	146	\\x0bdd9aee7242fa019e3411134dfc9d3996f6b6f7a560c549d17da41c182523ff6067fb5432dec5e52ece5ece39c34cca33cedb51295ef48674e298786d7eb80b
4	1	308	\\x17003ca3f9622c209e48bdcabff3844cd600fa8387e1748acf99bf4a1b4ea6239b86933ac21c006273c15f01e93c25340972d27880e17117bd67d19a3e64d907
5	1	149	\\xb7c8b883bb104f40131fd0e7c71079781076fdcd53f4ad47c87c4b631b99c160e2c812d1f0a95cc2bf3f5de265cb4a68cdedfc8e798634d6877ab1f4fed16309
6	1	183	\\xf6cb9041f6c9cd7dc9e7535afb1ebee040a5d18d36b473b71cb795daa753406dd277a77b239b9b0ba7bc2283656952696d38218830b796dbc3c4df33da04c702
7	1	299	\\xf3ef15c7773cfb13c567372bdfe312deeebf9a6c0851193466dd49fa6dbc71ad98736c23936cbbf75e80ebbb0fa61bfecef1daefffda230e2f7a2e8ecbd9520c
8	1	288	\\xc98490227b5039539b9a70fd7bec3a23d095cd4aa2b03ed0fcfe3127624286269079be74c0490d8059907d292d5ccd126ae4660e43ef0b05f3635aee21bd7801
9	1	184	\\x21e4f8d5d5bff927a52d3e62e578b5e88af3bf59cbf947d8e31affe18e18dd6968d2724bc965cc0f393a524ec039d409abdaa04453d54a9391bfdc36e8a6ca03
10	1	131	\\x333132c8dbc3c7530db9931e55f6fd5c15f6f01464c31fdd7346efc253db4b02e31f89c0bb0375111b7b206621949924515a6d91399eb9dfc8ee2b3ed391200e
11	1	76	\\x8c6efef482745cd630d4d26a43cb7d1f441187bdb07797348b00d06a56d62219ef35e7a89971ea2e3fc51dfeaa40a524a638c8ca01e0555fcc3e85ce79803905
12	1	298	\\xb0742f1c326dff214cba206034e81cf20c093b27f0a740cb90e6ecf0e66c7cbb3935d41220f9ceac155d05199a3c62d6bf7783df9d6cefcec498c0db001f7100
13	1	354	\\x60eea71af170972da4cba44e1f52d9a311211bc5b3a670dcaecafca456cb9b5cb6194de442d59891ddb1cdbc007abd981eef66258f814a2e2572e6964d8e6401
14	1	374	\\x980b19900752809ffc8f2aad245d314bb559ae8bb88a627d5bbd59d2fb538b40727e6449147133577eab68619079b2bec6f1904ff80e6fadf6921053a7aef105
15	1	371	\\xd08fce015ec64df7c917b5de9fc2d63922beb3204e82963bdf59c0d246e5d6dc81575acafa43473553fe37ef63fd4fe9ac4140da984cf967e9d96300f0f8820c
16	1	397	\\x79b4782cdc16103be277f7b9bdd29d2df89d361fe6a135b74b446b4dc11cf550078535b4c65a153d5039b7d8cd4704a247bdd383e278775b3df84bd83b544204
17	1	403	\\x629d20d9f168cc25873e12d2c09f611af4c3ad0bf1f1877032a13025fa1f766fd14afdc2f34b07e9425c34af2b11ec0701e336fe0d7a2887a21330de5992ae0d
18	1	319	\\xde4007880769fe5c436f88191b0fed0676b1d1a42e6d928e4c69926751a6a0017d4fdbab47317c40984ecb69572a3ef98f2c232ff7a4cf34a048efbafdf62d07
19	1	66	\\x7c461fa136d9a4e443a6547e7f27119ac7eadd601f068a2242fb674b5a1c5d4bcd203f088b304d631eb495d6e4621e93cf407683d7abbbfd828fcd64147f7707
20	1	83	\\xaa4d48cc70114237c9b869d02b05c5bbd7a9268c8774f3174cfa480f1297259154ee48cd7f521dd236e6524aabc1b870cc4fbe98ae54f3331d7e667a865cbb06
21	1	244	\\x8954509c255aaafe84a30d058f51c0e45de0672496ced079755699d5ce851a95942032f9d9efc557a32c3b39562d606f56656b8817beabb01a97b65d2d877803
22	1	96	\\x68c7b10304d3fce53e429cacd9fa1dee01958defcf8df4c748cd0efd3f35396e6160f07baf9b80e5043ba41c38079579c787bd7ca5a1ba39ffb7ea40092d0007
23	1	116	\\x9e459b6bb80627fc937465a3ed599ef5aba71e1325a627c0c551386cb79df9508ffe1aaf26117bbc7f1e90109be5dbc856d7155a06b53e27f729408f7764bc02
24	1	119	\\x839fa03b97e4763d6db1adb3fa8ef3af1fe002f42f207d74a9984890ae9dd4e1fd7364c52a93160b28dfa03d5caa91716845b523e55d8ce6c388b51232981d05
25	1	109	\\xb04c0c5a66c2fca9f1b7e4a94d6516ebffbff489307c3fd5d59f3766f4822f939221c59e1e4a95769583e27c21d346357285ef5ecc2828c92d8494765a836107
26	1	104	\\xd0b1924a175b55ef882b006fac23c60dde4d731869dcc8e1e24dd836c282e7a5344cff544d07d58503be5ec8c98c44d6e55b2722004ab1c50e12d1336999a60d
27	1	79	\\xa8db5a924a523574ad00d16d422ec80f816d5cbf1621e3e17cd2b48bbb203eb6d5902e08d0e06df651dd5138827b8e9993deefdfe8fc87a834b694ef4faa0f01
28	1	159	\\x2ac9c94d85c0d30abfa9bf5fb23e783fece9f6ea6cf94bf9bbbc40f03de8f46c0599996cc6bc81dd03a1c73658a102cf230f381e7a244ffc57e4ed3caa2d140b
29	1	259	\\x28b48949737c9777a17ce8f82a3bfb487c72b241fe56157dbf96162ff1470f4411239eaf51d1364d22389485c4bd8869b1a8c0bcaab1fdd94992c7fd6eaf4201
30	1	302	\\xe7a613df696422939c91360332b809942a6bed28bb6490d8c24875f7b08f0962b6b46e47138d2f5c4dfbffe0a6ab4ddaf6ee9c9df21bfb0d847009c943eb2c06
31	1	4	\\xffca4bc30c1a0e28c67d3512a10b80f94610572870db5ca2267aa34e3308f6e6960c65b461472f0caaf404ca1dfada68d9788203e536f365dee9f9bd9acd1805
32	1	337	\\xc9a675bb2f81c825dbd775aa4564dbea38dee569f75d2a326370ef0560180ce66b22d618f7dda56b4321da00888a4176c0796a29e325d044ec7170e6ed31510c
33	1	311	\\x7a04e33453a14fe2bad0ce3f0378500c3cdd2d5b97e50c42b9ae9bc67be8e977642ed379cfd95e0e20c82b09201339101c1289af8efd708ac72e732317fecd07
34	1	167	\\x63c6d3818570ba03e3e8f16b53834d859b66e44a72afa52d1c49b2c61b45742a6af35f3cf9b8e1eabaa202320ad4bcd7e726e1e140fbb1f1bcb72c9e7918e802
35	1	368	\\x25e5bd6b8dd127153465d3d897138915bb77781a0d9b4661c3f2c0162ca55a673ddbb040cb76bf9794e3a312299664095fa1d1f22fd321a6b7ff0ec8847d3900
36	1	25	\\x94ba2c472d41c2e7eea966c11517797967b4a3dc44dc14f15155dc47da46068a03baf8d620c8ee84188a55f908433e6c4681eeefbc3b5803ed63c9d35ac9ad00
37	1	55	\\xbca1ca798d219b3d30a9709cd886886faf0b27f8f42aef7e10048f19994f55e2328849c44437a9262b496cdb9d3176d273fdfcbb8f0713045f2c61ab31ec3107
38	1	380	\\xe1bc67dd041087f615176627253fd06cebf236521b08a5259c4cf6baf6677093bfe1190ff09fed59e2503af90128d025f612bc2c955f22166fcb9b24815a360f
39	1	135	\\x1f143295130a8e558468e981f927ff15503fe07136c041ec7bb8e4ecbd6a79a401d4198f49d0df0fb0ec113c50e2222c6bc277ad7a968c629bf21922de434e01
40	1	262	\\xece7e7c348ce10a5c4bb0fce7d0e0d989a0edeb8cc2f5396c8e21ed3cab639a4fb5f1aad48802d565675c917ee616308a5b4c06e49a0420bb2a5461b42bb420c
41	1	134	\\x24ceb0f112ce8c08ef3675b4c8482fcaa68887897520693aff12d14b4f2dc26e7fe10bf05e10408af7e834bdb19b21e6c02af71781d5e6ea8a172605d98ca500
42	1	316	\\x327cbfe9b054a2cf4d04d7c04629ae50edf43382b4b4c59e86c0b0507772afe51e4d1d1a866e4696aa990103b57c28e3a5d7db9f01d1fb7dba0c2fe14ef63c0d
43	1	232	\\xb9eb601d2392bc0f34a85dbccbb814a822a06ed38722bc5e433f0d3c74d6a7e9f83713ce18f612286dd02d3d3788e8ea7d1f0a7db23a551fd4e3739d68626f0f
44	1	5	\\xa6d21f92eb53cb9dbe2cc2876e938573079ab77316ea42f555cc4dfa2ed3ab63f6fbd84732a93693f55e59e39ffabae1d3c57983276882d095f1bbb6d0baba08
45	1	333	\\xf869ed55f8bf7340bdcb76b56c33e614df24a7ed7576ba6fb68b27425b6407d8b41dae696bb8e4296c06f01a75edfb0425aa53c214e059780f80479da795c10a
46	1	22	\\xa8f991fbaea2c8405fc04ba96cfcc0229ba05d15adee8f398b1d2d465ebde4cd67249b36f2a08a4d8f9c82244080bef1578df6dff508962af03dcc4a3a4cff0c
47	1	45	\\x351f643775b308e4e1a0b0e4012ab2061033232075e3fd72fd5c528eab3f529440d70c8b9f3fd2c04554dfe2808893b2736273a9e3a366628f327931c975fc09
48	1	275	\\x637f85c166cbfc2e5f7f1f0bc7c9a73c551680e1aea294ef41de23fe1608f3967ed9a9335fe884ffd1fba0f00798d4d3a2289965fc9e4c609c9885fca9fe2b0c
49	1	10	\\x82854572c9c0ae68c4b0efec65d6e7e8e22c33bf667229fe5196dec3ccde109a9390d0d88efe07c7769dc6cfd1e2e91da19ea141455bda5132d9d445258cef09
50	1	21	\\x3c0bbb7711d9b85a079f4475064c37fc5063cb42bc81acfa52133f32655e0558bbf05dfdf08491896779cd94962dcba895766dc6520d1cc7bc3221bbb68c4c09
51	1	41	\\x0accd45351a65742bd955609ae36618fa562de90dab42f20bb30aa063406773d0ca939362732d1cd18007f25b01ad7cad7d606cda79214f1b5153862a8744406
52	1	144	\\x95aa1754abd6a3d6f2cbcd88c24440a5fbfd45ce8e7ad4e7af3fedfc12fc128ac1236f32092c3d97f4a8e9e0a28493ec468088d7cb5213aa06c13c701c1fb401
53	1	312	\\x71cbafe5d2653768dff319fc10e6ead07425366c0c699dc8fa807fe0119427068cdf49f15f0ae2ba013d9cd85d552402d22eab90752da8f1ecfd20f5d6ca490f
54	1	94	\\x73d2c89d4ecc363f267ae55139d750ab3e83959aed5d74c4fa3e2411ef2c859f35ae766aeadf0d8860cd1446c6a1bd6f93764714dd4d1dd743bb8feddd2b1d05
55	1	209	\\x0c65db906e1ec9c18d59d18a44c33161fc6945f83262fa121753596519b1206ea4c12dadea5d1cf1b1ffb574c4ddd8f56f05ed1ecba481331e6ea35b4b050605
56	1	147	\\x9bbb8a14f0ebd0bf264319560e99de23c929d782fb73729968ea39e3bd8a86f8d164f19431ec31d2209c0b86c563a1f28a4ea2d578c2c883df66afa46e7e5505
57	1	394	\\x9d2678378fe13124970c82923162b39e5d7ec026e6d05297e437c0353a9b3277e713ff7d74a1e32a3296566245699d9a828d776e69d1881084fb0141b4251a07
58	1	283	\\x3a6fa00fbafe4cd01e222584ec478668b55d206598e3beea5c2694cec8cced536b167d7624335985b2f3067547aaa3162dc7b4b425d24b95647d09a996d5de0e
59	1	297	\\xec45fd3a316c957a471073f445f1b6b8c3a7413db67dc5690220c994bef86566dc58a3c9a69928b68978d2c85f68d73ebf94c14fec9da4634c9f63353ff8840c
60	1	286	\\xf8da8973860ea3e0cae0e9f3772b5c31a582f16b64e7103befe9429db66f0fce41f2e5bd471383d69cf1e945d4d35bae5bd51318b797771fadba5c7d6dec6901
61	1	201	\\x1c575cb8dffd008640144cd8ac35e839b36dd41066d72cbd930aa00b0bf2185172ed379dab5c91f890cd96085a302e745a3d6fce3419ec2e4d8088d696f0a20e
62	1	285	\\xcd96c058af9bdec140af80eb4150a2c631efc02489027d3cb1a895b9bce0f3e24d4c3f972cdc8990e315abd7594067231c0a9fa514dcaeba7581dd3531c3a706
63	1	176	\\x1a4067cb9cc20a2c9918fc815b8898b3fd7815be818c7549abdd264ab7ab600b97583036b0a0db53631380075e994d15821450048c7c01192b1f1f8138fcc40f
64	1	181	\\x1b1e9a54dbf61d460d997c5376b12f62d9df0ec0b2a1b9520ae87ff37fe6b1215e88699dadd90a1c3ecefa476d417b6af4e859eb266a6ad5c3e51b6a2a4d9d08
65	1	60	\\x62378b6982b7864107fa53d63d522352c9cf6b0637f3e42e653f9e314f02207363d12b743568294fd9831fcb65090ad277fc248578555ab37c1c05194bbcb60f
66	1	257	\\xb46574e5062a4b0d8fd27ded1d89d4366533a375e857cfea4b94baa597ac737301937a91286101eba01c030c93e00cd25e4affa237b363f3385c2ad52b721c04
67	1	154	\\xaa5a9ddd7f18b85260b136a6738845d8bc71796db5fb99818d3dac30f491fc291107cc36942e225253238a809af40825ed3acfcdbe3088213337cb54ab227304
68	1	26	\\xc1fcedd110445c37b0fb4c986daa328707f8910d0c7d666f59a24c1ac4207e8a2e2bf5351647d278085fae1a39403d4f6dbbc3996704a794502a4b39f7870501
69	1	322	\\xb5c8b1edba1f98de1145b4ecb1aa231413dfb8c5757a1bcb889626119ecbc8a506c0dd4a3411d092ab745e60b52dc523154e9a3317b1505c0b53e66116c3950a
70	1	219	\\x49ddd40bdbe89f691ced384e8a81c374da1779b7340651cccb982315e5548acb357894f075463704aab888a270d8f8678ad265bb947a3fd9f1f9c1f7216e9002
71	1	193	\\xa7335959a0151b083081d8c974fb46d7a2bccee2cae1f468cd3bdb517ee3d6ffdff6a508b0eb2c89f1d8db31bc799dea25a34736eb7537d4b977ab7e0031e90a
72	1	214	\\x2838e367a30b8ff29604465422c79b7b266afcc892e7c1d773274344414b1eb609c7c4e1bff09e06c683c5ea1f2fe6f3cf1468351919b86cd1f4eea474635405
73	1	351	\\xe9a92b810b1bae0691e4114361174974d1227441d8e08b4d784917f2f57f810becb1d4b9e5e5708d295459c5119ab50a8f57314745512214419a10c15e5b580e
74	1	95	\\xa0a5899db87039fc6d99d2072efa1d433bf2f89e8da327e02a3c4bfd17833ac7c53f2208c0b22aec6a586e089044a48410e1a236dc807fb79b05ea545bf9e704
75	1	225	\\xeaf962b02188d2072835f05701cdb518f87b394e50876decad85701ac73e18ad47d8012169b00d25a0300b6a93c3b0e221a9cb696791ce860680084cfc92480b
76	1	187	\\x7590dc3810552aa4da73fcd8329e89d57e83556b59c4be00930deb15f041f53e3d9c515a90c993d159104c26e479fb51e374c14bb939595d11b6bdf6d6109607
77	1	118	\\x058a7175fc821d019719b04145dae9f19727eafca6ba57d4ba78e51a558006e672af4d440898f0e89e64531f6a018ffb362fdc61be6ef128346549f0485a5f0b
78	1	255	\\xc38bacb1b6135b70b69579a810846483262b771b6d4e777ed2a4631958a52cf8fe8d864256db44ff9d33e17308541a924edaad48b8b0d5e8e5e19503bddbc302
79	1	124	\\xa64e3b82ce8f70108c0f676c2a7f500ad51d016956acd0df6ed8f837e89457b0b60e1a3203ce5d517d9be7ab4889f3a3d5de89eb65fb21db7f0ca318148cc20b
80	1	277	\\xbef26f2c09216d744c7e164a1c8fefaa354cb592c5dcd28d52bed4d98728727e3d9db5e5375ce719bd56922ed1dfd1188091bc977d93acdf7e5c7b693d3a1b0f
81	1	330	\\x4477def9236d2082d45e1f2b43cfdd17a1fdb7e4d9cc75637b98fd825cb18f63870423205a3c2101e2dff33d5355966ed00f40c8d2eba55cf28289f7709fc504
82	1	382	\\xdc9b260b7d80cf7bba897e4f084bdc7eb71c055d7e8efe308a4136b990db6aaf0cdef5cc8a2d93568e99082ddfda4c77afbf81019b74f4555c28717a69c01401
83	1	40	\\xe3208873ef1be3845dfdb999f2d7c4b13338fd1dbc2e4c7e423ba95687e4d10d571432284545b2bb3b6ddd61d297d81399a467366053d5ae2357dbf4ee22d301
84	1	213	\\xc2f871fc70188bde481becedbadaaf7d1e048ecab8c2de165e31045461727123d4d0629e86f22e8dd5c41c2178391ddd852da017ef2386126b53a57d3a47820c
85	1	220	\\x8dbc5c691337d0f248920e4aaa5df410bb1e8034cf0b1bec0cfe7e49ced3e129f87409acbb20ed791a7b38d7587b49905514dd0b1e0c19f62ca425a854cb660b
86	1	372	\\xfa84e68d54160e08372b2efe3a747270e3cedc32803f9b080e83444cc00c5b44f04366fb0d52fb86f0de8f0b34245385d4818f2a9d51fe7fc75b29471f6fde08
87	1	238	\\xe95af4a00ed1cd2cf514c04f50d71d549a745b223eafc933918e4074f67de44d3fd27ef0d7df255048f76cde7cc6b16843e6b80887a744ccac2e86ee913f2a08
88	1	19	\\x8c7635edc67fba99f01d2db48c70ba8b4a9e974f6ffac458e012fb9bb9c4c6d90037119a741e6851e4b234081924d31ddb85b2c198ae2296a26c80ff5d52c501
89	1	379	\\x0b4e127dbb69e63891715ea4cbff8ba7a0bf4f5ee1e8e089ef0642294cfc4b4960b4d5b71d0aae764835d2711db4052fe53fb9b7d60d4aecc8a62c6ff218b209
90	1	86	\\x5829ac736fc0bbeea6077ceb9fe6da9e403400f5a96dae7b6bb6f3b02714aec301117528afbc40abdcb6526aafe59fa8fff2ea3109483f2720c943374dbc100b
91	1	420	\\x2f96fa06d992e9340d50a5c69baaf6a5d1ce7c10e2b799ff43c7a1026b17c5157f631081c3d5c0587104dacccff90660b84dcba1fe003e37a9644546ea908508
92	1	239	\\x8709930e2eb6bb17bba89713b8e954294f2c46b19863d3da3fc22ef30fb6260a5514c6aab8d3b1c40bcf77b6621dcff1030f1ec9181b520c2a90fa4a87b6a40c
93	1	151	\\xd518924005471dbab565b1cb9e4af29c6feba8ddb367d88a005db1bdfa207ca847e239bfcbbc6e354922f88bd8f786eee6d0cd18b893e25e6afd13d4d4c23202
94	1	377	\\xa352363cf645645596dd68cc199006e94dd5fc91733368ea60b33c7e96ed3726d6180fa90770050dd8de85f2431810b52ba20799bc5f8e6d51c6a2373774270f
95	1	418	\\x12aa04a02edab717c668aa918e8d01122b116f25ee7c418af336ca3f0f4b5c50a1d23cad1d1878d3144a33018b418cbac91cc855351d00b595969ab7971e5a0c
96	1	180	\\xa0efd2535192bf6ee972e2210351f3beb625e6803334e639c2d95b85fbd2a57ea544b48e824cde21975536d2452ed8be3e2fa685ffe46714277a14a62c5aeb0b
97	1	122	\\x4e539fe8115b38b8a0bb916c85647667df38302b4bfff500e09b8f643f7e53c7051ccf578362f417c6a9344157a3c59749d800acc352fe7adc3a19acd4509d0e
98	1	65	\\x000b5c299dbefaa398f311203cd40486a75e868d3138da29e3a5b293ed78aab87c27bbef78f84dce11d212f4407a28a5f1297f62686d2769e759432142a50c07
99	1	392	\\x58fcebd3b3915bd31019e1abb15c5e5c984f659fae35ba268eacffd6e728505ccb06bd6c637d00048a8dd422fe879cb7f910b114da4ddb0d0750351dda63a103
100	1	43	\\x5d06dba4a8d11ebd01a668b6e215f560ccdc085b56cf03e9ed376223ab5c557d2fd0b2bd19bc528218c8838110f260ac866e2d147042c3ccbc867ebcf6f7d105
101	1	156	\\x3116efc87336e16c3f6956208516e01bb3c187146e1c619d6ffb9a837794d0e0220f1d7cd322bce32034bd1526a64771cefaefdb8316e1e5a83335f476e1cc05
102	1	406	\\xaa19080b34742d2d3fd50e4d4fe58f43f27b616de920b35aeb2b2cee595d3fd01aec54dc57100f029ede27d0ba65f4864a579b49c76105fc714bab7e2bd1ed02
103	1	248	\\xb549ca876135925c19b107039d7303b277c7edac24ac29bb42fdf1a4d553bf04281f7a5b7582acb695356c2ce6783f65e27988ef1359b2362b2f3563422bdb03
104	1	396	\\x9f6d2a0d7d2f668a6c963b482f02317436b25a47c1ec56bdd695817e3d3158fc9e06c10f6daec5bf2df324e4263e34cd0b9a4adb526de2477b70a0112b5bb006
105	1	240	\\x489e2cef6ba3f6a6a9cd564fd98def1ec06a6471d81bd6a10fb117ae52551fa0f0f5e76f9dbf4b5d35c17fdd7f05e59d4e60884d3f0d12a1360167050673370e
106	1	99	\\xfe25cf07cf3ed62f969098ea21fad596bc8db8b5cf769191ee865803c53d735ee30883fb7673573b9a3a56d7e8674e97167df7b9734fe807ad4a96fe123ed809
107	1	249	\\x89be0c262915c244e2f54177a824ee16eefe31eda193542599991192de5cdf471dc9412b26855a204e6180af988b5dac407f6fd6d1b1a5ae0f53a5773c282405
108	1	72	\\xd08b03f7fd328d32ec43036cc9cb4ff94f82ed00942c8c0fd4dce9b1cd47b1a35c82ebc89f8490970c6995dafb81bcbe43afa58f2db64897ff336618b77eaf08
109	1	315	\\x1a7c3c0675fd5e05b25c17ab42f9c18e5394ecea5e6a03375fd234807a8c7c4ab7ea1359f62d0295de4b43c86f45d7d4d33601fcdca5f646d2d0f7ad19b93a07
110	1	9	\\x44b6447ce0de3af37541b15e605601c4b9b85502d5b244c7f198d07a4f2568f96632502de4a02f1228f365a455faa2e56d045389203c95d179c9df1ef9b36b09
111	1	388	\\xcebe1b4315762543ebba442b9810d3b54fed777ae70dae3b1c4afa6e713a06389efb4350c180921fb6ecf006fca75901e19a9b490713b196d4871bc485fc8500
112	1	401	\\x38b256f1313d3b494b19bf01705fd95ec1886a9c8609b064d7b216701a640d903b09334a9e449498a13ff4bae848c053d0854bfa6b8b8f345898dc88e86a5a0e
113	1	188	\\x20733d439c84fa68505952529430a9382cad0f1ac9260f302011cdf99fdb6d0a7268f55c7706c997ae5c17cf220b57ce19493fc26ccbefc9d8724cfefa1af502
114	1	164	\\x826e74a1663e7756130a320043fd3028daf5aab4547d1407a4950f7c1c70723d6dd7567f7aaaaa500a9aab4e98b47fe05f4348346c88f27781fb35ab8371020d
115	1	177	\\xf222238e165af5c58a940f53c9833f3a8a4ed0a5f02bc3b9fb9e017fbe4366a04559df2beae793e88948a4c4e0c32f0bbf6095abba4f1b4a0fab1394df539b0f
116	1	290	\\x7cc61fc00b48db35addd37fe0b531f45f3499ae6c197711c130d8b0d8d16da99ff4cf6e8edab87aaf25fce7096a7cc6c58cae5e717592892cf48249f8d8c5e06
117	1	325	\\xe9a5d5a46eb8e6968eb538fccb3052e94429ebb818c8916e3dd131d67e5f2a4fcb9af29e0414a36566eff5d4ec3b644d55ee1b3ef1c24ce9df7161ac05507008
118	1	323	\\xca9f3d2c9ba9b1f9c181ee68c1b9df94e29ffb95a8c663c5fbfbd9bc18fe85ac8355ba7620cd121bf9c8939973a2ea0e21628bdf74c95096c5d780aabaeb9f0b
119	1	242	\\x3022fb28afcb8b18beb42f5bd8576744bebe9a43ad6ef0ae53eae4d635b69d60958d260d6e7a4775627e153dcd9790117198bcdd054502a4297062a02c8ece00
120	1	28	\\xb00196801986a92e520264a1057b7daf0cf5dcc44364904e0c4fa66805edbfe66bd2bfe9c65cdfa0de5ed1446b7c5a0afc05cad42085ff32ba13033050e69808
121	1	210	\\x486324dbbb275c2f6f25af8465953a3c89e7902676d09a6e61e436da75f6d6bfbdf8ef8e32ff71ca3a475fd6b576e3f785c6c7397ab7bdaca75d70199d4d410d
122	1	310	\\xa032f789675227ffc5443e7c469f151dfd236565ead0d5eb7bd81491c36c4d510f430fed21b01bdb058c948d6e8d70f4fb22a48cdc2e07431f4c058ca5c8fb06
123	1	253	\\x609e46964ee3ca852da116bc80b49345cff35685f26bc73b883a8329c00f3b7236a765b9dd8b2af86870e71db3891ec80888f1ec48f12609328eb2054eb92801
124	1	327	\\x06b328d9352b2a1df80bf51436147c13384e49f887b5b79163bf1597003022ab2b342eadf04f14e7e32d2a6d311f6247f7b608519b21eb584e5a5f7698ff6207
125	1	69	\\xfdbe9d31915a7bc5f720b00596f9e5cd1f0dbb64ce69442f628a4ad02dc64ef3a39adc60d76a21a47327063a50966ba81bb36ae4bc817ce7b8b3f601aafb9f08
126	1	369	\\x2b16ac208644af108f6aba18d9f9f5fc9744399a31ed548966331b4432375f3ca80030a3afa42cc7b76dc00c4d595d84f5e85ed005e8eab45796bef00d214c06
127	1	123	\\x668a1e07a423829c28b88ac9c27aaf9224e00507ff1c5afcd427d8be4d02d315c2f275afbd27838bd6eba2cc479d6b9d38bfc93fc93d52818141b169bab0610d
128	1	364	\\x24f49a4ea4ee7dfc99203378c853805c218c1e4dbae742641c854d95ab07ce405c1c231408a699ad09101f0c3788c83abcc6be565849209eb8eeffa3fd49d50a
129	1	8	\\xc6ede146edf60dac538b74c9a955a1321724bcc6f5bcf8e2608128477025067c27f52a44ec1c35740fd8bead504d9734fc40b31c47c5e19a2b0d54f9fc264b06
130	1	347	\\xbb90e4436155e672faa26d3aeb02b1e5bd9696a585df60537cd0feb9aa25c4db775b590e5cc6b37b172c873d0d40b535a9fd04c0f7d035544846079aed4b7b0b
131	1	24	\\x7e5fec2909ecd495ebcbe81c350edf64f351b9c542f2cc399bcd8ad54da499fe2dc49df184cba9333daa7d629060592db8a373fc5a90ad45857544040e645804
132	1	3	\\xc6be72b0760088a17d1b10469fe55fcb039414389424345efd751c934b4b1deb73f59f451584bac5160301400c3a797d319783437aa194f93bef6af85abe880f
133	1	375	\\xc98e30d864ea1a5d941b9d3fd82ac80d7d575d2885b0e4b4afde13f10169c8744e815227df7a3e39a4ad6366e75ef83962e0d10ffb7d1e3f2847653f2c1ab408
134	1	127	\\x27904929607d6f047c5dae058b23c2e1e8b7b10c5d27634fb3a4a56184ae6f94bd429a8e928fad48d03acde16bacda7d65a034af4936b56eabc7c1e4be4b6804
135	1	199	\\xde5ad70c4772d0c486a7f2aeb681bcd2b871faa230597fcfe5d4fcc3583754746914ae0d06ea7d5cf4f39dc30c688130f4711ec37f5f7be362caf401a8223409
136	1	207	\\x93d23aa62c69b0891e474f9c56276086dee904efbd48d3475259ea502cac77f7340244a4ea641c78206c5d632a6137291eeb5bbb9ecfda12bf9e39737131800f
137	1	110	\\xd4690ba7ad5319306233813b02d356748a8c7e86f7402f015f441835fd07eb86815bcf4bbd5f460f98a6b4c8232cb1fc10a4492996d2ac3d5eb8533153b68c07
138	1	267	\\x688b492f8957c150917c84b520ee0b1856d3b0f98c7995e951dfaa55f8c045c67d37dbfd8c967c94eb31c9bc8aaf4fa1e18bef6f8ff577b89ed6243e4fc1f402
139	1	414	\\xd2268c0aff1e51d9112fd19daa57b999395dae93d081c196b17763db748f3cf8e208c658565462526805638e43138e8bf459b65871a10e2b4e6e4e2900c49c06
140	1	215	\\x0480401c0497268b198c1d7c61acb95f50df92aecb92ecace4cbfc95a49322bf7f69dd2c292a37124315fd94445ab73516be53a59aabd6c0b5105a8ec0f7b40e
141	1	186	\\xe9a76b4b88176e8d5ead683d9dcb790deb28e59e99d388f7b048d4850625c41ac12af03e2cab3f5f2ca9ab8679b53b303e382578871245ae1a08be8a28f2eb00
142	1	296	\\x014ca4189622777e3f2a50e24bad871b6d9589d36923532ecb78063153edb67bdcef7f497d2c52fd149d76c98503e53327024eafa42b863c20c4f231dab22f0a
143	1	168	\\x8a563d94ce0005a9fe75b237a6024ae01f63a78d60b5a6124c3b7ccc36968c8eaacbd9e91ec0327788f68649ab35e1a273b335784885638f93fdd1afea81d707
144	1	344	\\xecd4caabfe38d649c0ac510bf05dfa8bc4583e0d592866f516fc3ded6dfdce291b146a3b2ca8873ad3287128a4f22e4e50b688dd4cbbe505ae15436175f96703
145	1	236	\\x50d1238c8cb5432590fbb8d4bfece3bdb9e147060f267c7e2941bb12cb45b36d77f26e150bd7314e47a5d0657e8c0a10576001daab3ac71e10b7552d6390880f
146	1	278	\\x43237d9bfaa124c11110d5c26839e028aad49e3a49325c99ab77a5e9186ee205e43137f80c7b87ae4815b0d9203090fefd6b66f42ed2b76d9f8183b49ba1d70f
147	1	373	\\xd1e7e847718090a5e575c4bab1a2b8e3514fc8dfb3112d6cb471cc12500c5d8b4625771e8654a7cb5102f6b89c27a65acc2a3dc736de8aca0c6baf5e808f9408
148	1	16	\\x4720cfa8a1477b3aca99e317b71c1592b75b63b8002b737313117717d6c46ad8ff776310d40a1cdb68be6f5eea8b17f3b411e2ede72985da630ce8574df8370f
149	1	412	\\xd2fe680180bfc812a455ffca9839a55e29b828468cd6162f2dbfedb7d51fd52ade0cc3ed1a7cd52fdc2d93c5577124962fadc9d1d2c7b5445e0e70df7325900b
150	1	145	\\x6bb2d44783a5916f1c9e8caa2d1b5ea99c5c37cf2d6e566c338c234693259765ea6639c6fe25f54b19f30330755a055bc9f655eac8878237467993115a68b705
151	1	331	\\x3ee5b7b89556a860162bd4e6db2c9ee9ddda36beb3b9c2f6036c7485fbc03bb74b395f8293ad7347c0da8fad9d82234b5bebb8b3628158f6a7a401e56857450c
152	1	343	\\xdc74bc8b2f8a1e90698bc2db3d95c95dfcb3bb98525e490279cd52b9814b7e2ba4cbaddcf4e653291a971021e84239495521e39afe61594e385e38bfb5616605
153	1	58	\\x3937466af482a9f936c43206eaa1292b2bc03dbe990dda501f168573917a171ad46ef06d51a3fa44027bd2ccf75e2cf4b201c48c0d766d956f322a7aa26ade0a
154	1	265	\\x43c9680e25906862507cf36711e9f626b65f2871c16a2827bd8d8cbe51dcd967f2883eb710d3cfa339f6fa0e56b1ce77b800cfda0c64bb60cd116b3420fe940d
155	1	6	\\x43bd0c03419049e8bc936526317bb826b829829ba520eec367dad06175429fe2f4a7bd12b116e5eb4869dd93fa6da2d0eb056ea0a16112116fec2622bf650a03
156	1	108	\\x20ba989c907c0496965736e35c18fd9f3eb2580212ba1319a7e0b10753eaf2c61649034d71ada5df452199de252a47d6cee5e70870795b8f3edafb8fd9d33f06
157	1	421	\\xc87b24e166d1aa914bad46ac2e5061c84f581d1224c2dd3082002d21c36a4d27365e5b24161760313cb178bc3d97f5f82bd8d71315b9f4890d9da99831488b03
158	1	14	\\xda342fe7b10833cc8645eb147dffe62d6ebc48f416c082223e4f46581e19326e260d490feb80e6c12f1e473499f64ee727aba6f3ef2351abfd551b3b81cf6307
159	1	34	\\x375756839a601b52ca215e1087b0152514974375ae85d7b58b9dd9cbba82a6a1f886de955ceccf84ed1ba0ec949aa60cbdd6d66b3dad6e14d9f32479092fe906
160	1	281	\\xb63a792327d976d011d4356d18531b27316671850b7646bec32d2e550da0cbc8196c2923127c6f881d4aacae25878fec67b49d6044ce5dd27a53250e82c3cd0b
161	1	133	\\xf5ab34be0455f273fd1f7de0d194f43671f3aa35b33649774fa6fe92da480047c172847b802d873c0def4af01ef59277f7de4346013bace3329b173801046d0c
162	1	29	\\x2ee2d5ce3d6452078a9cfad9b7efae4c9c91b3ff81ffa57fe10c4240da8c4222a18e2da88e1bef78b3641c7e3a0b2a9bad8d1d1dd3d2b4a5032ad976247c6f05
163	1	363	\\x6eb5fe5755eafbd74556007287933c54a0d8122a495773355ccf8c321ae88a563dd0d5dfb5219a3872a7d708a823059c9a233fd5df2885f427187069ad1f9a0b
164	1	269	\\xf7bd1406a4f2b270e45af160fca0e04a7808003166a2327544511117d3124070137567edf0f2adb1f00f68e39addc3dec3229055678b55fe95b28caf0c72fd0d
165	1	98	\\xa2e94f993cdab8c3b788599bd863fb4ffae0d3d3b31dcfa67ff2d9b31e02630e91944769ed27216d7f82ce2f651183f6354bd8a0aa388d1cbec6b2ed8f334f0c
166	1	314	\\x7f727ce5b3faa738ab81e46499a69259560bc12471186c843363afb911ef01337f3d700cd6ec170b4e20507b006b01fe3b0524df68f467b2523a552289f30d00
167	1	73	\\x2ece509f1f4e290e263bff46a79f5b45e9f4d2e404ccdb774a983845adcfb9b432858796c3ec3596a75bfeb59dd5f07dc9cefb868d773ae1db2596837c8cda0c
168	1	141	\\x9dca5dc728772c8d0124417db4860e3ecf899fcc1c53faee6668246887b3d167c7b74474bfe111a89e2262c941bace74b85797978c68da70642376849842820e
169	1	90	\\x1258270ba053ff38cfa88eb972198ee4628fbd4b5c9e56be571e48e4f4115d6d3465ee1dcb43273563bad02e135ec0782bd67663929d8551e81c9f81dc58af03
170	1	81	\\x258f29d58510abdd16febb56513c2880512159bc81b8529d0e78a693578e668d9e9340ea2efe462d7557513626ccdb6df234fc38a248c649d9c2ee26ec55960f
171	1	329	\\x229a95ebbe953c5e84497b53538752dc0d359d0f5f1b9f76c8525d3ce4b053ef2aa2615fb0546036abc08280e27db7ff53ebb9580120a93ed14e954bd62edd09
172	1	165	\\x32229e8b9a596f2430b4cf715ee0ead4e02c0ce9459ade31cc273ca6f161629e78d027656d3769fcf88c90f06500a9a9923a801eeeecb41f3483d3c6c0449608
173	1	31	\\xd04315f6d6036052e3fd3fd7134ebd1cbf55c51aed7f55379d3bb976f14194b7293353f9e6c7d77429a895a8e16c33f20b862815f2688be1cd8b4e31322db40b
174	1	332	\\x0e1e77df4be6754c7b978e1352e443145781cd86747dd3625389e183be9bf3283cf899b2e8012da7d04af21638614ea118d3e4f7be73c3ef274e8a2e6bcd6704
175	1	11	\\xbde3337d9284a302d34d224732fbbd75fcc9a4e842819e68ad23c2375d85e9c5e6314580238868378742e80bab2de8aa6cadff9e625b2090ec3a913dcfccfd0b
176	1	198	\\xfa71db6bdf9d21227bd1cabedf7e2c79c3168323ef1f6ca16bf281123568e1b900e88f2e43e03d0155fba4d38e68718625ceaf3fb689eba8f74fb16ee0dd2801
177	1	346	\\x33f0891a58a2fa5b41b1b4ec087e966be53c86d7cd65505e4ed1953b77ef79bc9b7fb16ad8e9eb648ea7f38a75752a4dbfcd8eb517faf126aead79fb5a796c0e
178	1	339	\\x85f20a9634611a7588af1d3124f96be72585ae78fd20c9e472887b608ace77d90510fefd7c8686b511d368864df99600d77b98d6e17e54f06eddbfbe468b8a0c
179	1	301	\\xad0dfd5e9ee5a25e379ce16015da54cdd675cfa8bae3445542d7805727d10f394f62ec352b10964f0a2e8960f20f2e2e7b6f3b5b37997451cccd64397deb530e
180	1	279	\\x19840990c351142e11d038f7043186b82010bd2282657b82449aad3af63c7bd3c59fa33b88523a73b4daf90e09108290557bfe2c7954cffe087c81dddd561303
181	1	361	\\x1cd81434d8b23e95e994163a5924d778c578de4ba2d68bc1d5dd8c8acd27cf27855c43905c2e872bd101c87ad841d977e2a08d8aa5a8172b6cbda49626fa240a
182	1	404	\\x6e63a8c28b0cffd334fbbedbbf4c4273dd249918681f92ddeaa3521bd5d49acb7435823b24455d21e05f8de349613db285dd6ce061147b636c6f40aef2976600
183	1	419	\\x3484c7e748a0d33f365bbb4eb078d3afcd0706a1fc8b3f2d9d4fd400db44501adf25cf7395018fc9546c47b7cb098742754d3db0d66ba7b89b89473f78d7f108
184	1	282	\\xc27cac4401d0f86ccaebed314ce9c399ba344e04747e44166c8e8956f18000ab014f2f641cf975f5dd2aaf77ee57385ceb44b1b99031df61c5a15afe10f6070d
185	1	393	\\xd0a794cb262ea15cd83f27112f5279ec803dbb101d3173df93541ec298f172ecf63553bcdf433b2aa3feb693800b508360174cf8e3471d7889c0a241196bcb07
186	1	15	\\x134c928c82c85e66fb3d154835c9cc3171be1d52dea0bc64018eb17e6480c92560c48d3ed378306f60577e604918fc7e2802304ddb8a1949b4f91d1cbc4cb908
187	1	107	\\x78730cc9b16370f8dc4a7ae48d22d520d6d74d6a3f8346a8724f447c3d5c3e00a18f545d4dd030d4b5ee5daa60521043ebfd33d7caeccd4d79477f95a8df7701
188	1	305	\\x56e1fd127f22e2d16ba91e54f6eba2f2443d5de5e870099da5a534cdb9857a081e3b43c99ddd5732e04184144143253be7425e006ca11bf14aebdf61c5ef6c02
189	1	340	\\x2fa8527ecc64b9891d8c77800fc379eb42c2eab060dca21493a809cf8175ce99a2296dbedb3fb55876031ff7a9e1835c0418ac73e9b5d8fa8026d07a3467250c
190	1	216	\\xfc081051513cd997d23716d70f80558a1af7c4200c0b1a42ffc3971d964bf73f5275ff749fb1629fbccb41f717c6fb7b129444688b0aa4f5f8dbb9e33e5eed07
191	1	416	\\x97c677045293fa9deb4b264f6ab1a09878b7709baea941c618b4003c37d8a62de4bfac0e3ab716885e0625f6e47468f3dc8a472f85e842993b78c75bef39250a
192	1	63	\\x1e511357bc210faceb07983020818e048b9403d9e223fa851d61f3702c3c09e43242b16f055a1bafd933404a0547524c6aee24e4eddc984431d241a17df4a006
193	1	399	\\x6de92297e57f96643e6c2b49fbcb81c95eac302e7085ce4a19412a53f462c3c1a62b62ef12931ccd79ba155ccf64fad4e7648d1d006d2de5d626fef833e92304
194	1	229	\\x7443e573f7ebe8f34ac21cb7e7238b5bfe4b1bb1846a4955c4fd769afc082f37290e013ac4267c7ff513ada52db7f41e8d06928334b5adfdc51fc08b6a78440f
195	1	370	\\x8e065ce0f5d91233c02ee218237dcf226f4045f35abad9163b365c2e5927a0bb6250ec2500adbb3ea946f9d91dddc66c2a2fe04fd9a9e31203c02df1edbf480a
196	1	50	\\x8f5f190c91eadb1cc169b3b75acaf7f59f76dd450cd0fb35009391f89a4ef0761b318b344cf1eed759155493d50ebd08d12936092161a45bdfe3ce1247fc4206
197	1	408	\\xd4abb10a65a87b401602d801c63d6f80b68de30351c8dd6e9316c4c20a853c6518c5cea9838a46fc7087787c3dd192983b8866c7d481ebd7854cae4ff3e7930f
198	1	129	\\xe5107dffedfa31a623a115b9c5fff23d693be81a57b283ddf02efa859911bbb82aaf4814095d6c878ffb1c18445a77e6a9e512648bb362065f98b86f356a830b
199	1	360	\\xb383fde0541b78d8bddfa7a0ae86d216b0ed899dd998da1978ecad950d8ad8063f7bf524e76775c828047f975a9c6b5ec9b296ac38e30f790265f1f7bb62f900
200	1	68	\\x98b739338c0bcf1fefac6ca4d9705281772cd3fadbe1496b252d6ec794b2715c692168fb907b9fadb957908273f7ea27ade4ea0840368ec96c145b79ae37db0f
201	1	352	\\x3d876f7d1af8b2c8793a3a7cdf9a8d1710acf6ee197f9696ea9c25db61b575181e0e98edd8400693941ebb9bc3bf01cd4f659bf332f71dc2fd9fe934749e5604
202	1	139	\\xf8762c781321ab5d95f08e5a44d07a127007896ead54602597b09c5b38e562efb6629962ee7d419653978f8e2549b55620144c76b8d76cd664d8584ebbdd4f0d
203	1	53	\\x88e65b033c6b5ec080f268eafc3400666b00501de813236d22326c3cfcc786da08be0df2d73d9a6c20cec09ed57c18b355a4f9b3c96479218d0dd59a6bd5ea0f
204	1	191	\\xeb64642a6ff583fa8f51264ea9ef2cc7c85bf22432e8cbcb1f2b779b9ee53757330986317ecf3965301e40d3dcdbc18fc73a6286ec80971863eb7dc833d55601
205	1	62	\\xd8657aff007e01ff2d9d4fcaac96d4e1a1700fe159033481950057155afe5447adc794b4f3ee036e1c600433aa41110064d0577bf6c7b0d300fa554b40dc0905
206	1	254	\\xecfa93b5fbebe3476839a3a3552eea0c119c0fe734afa0a4991699d0b1bb301c77f169d83986e80048d2ca2d6ad696b4b15efd7eded75a1c3c34426004135608
207	1	276	\\xf02e090e3d769bba623461812f1abbb34feb559e5656ce778b0fec94aad40738a8de0186cbf866ec24bd3fc16c01db108b561be8e5d07fa48ef336631e4e8d06
208	1	287	\\xb8207df7b28eda5440e9c25598182e054ce2985e56f21667e14e09f88db496300589d60ec016e36afcfd3f085235c43031d03275adaa5164997b7c0858e32704
209	1	300	\\x651b89b9d890c65c1d7dd8f415dde2f5d9050e37ee93260b7d2e44182a65417eee70b6bc52326876075f3a2c87ea0976f12bdc442e09cab7db2bd70e33033b06
210	1	128	\\x2e8bf386ad9d6b45c3aea003c417c75dfb134504f245cc5afb6bfbf8e9457440f32f3742e2c551790485cd76bd7eecda01da39960b2a5d460a8e0d8f5a722b0b
211	1	91	\\x01e6430e1304ad7519623b57cfbd4a80917c5c11477cd3a637b4de624c4dd453cba6199896cead6314b1c110372a4e4dfe90bb6177344ef3e740bb17c833cd0f
212	1	30	\\xe082729ef605d63ab1d860a0d313ed8a02fff4f3f8b6db04c8128ac26f1fdd3c8868e64332ecb2a705ebbdeea14bca1659246f8e1f56416c529205b86e3edb07
213	1	67	\\xa332d56d65a1cf64e3f808e2e1b7444d0609627de0e410cbc84821ed5fe046c453831918b30ddf57faf11b5bf298ba74dce61fdeb085dc8b2e01e3b9c37c1c0a
214	1	317	\\x67508c2af13ae0233f83ae2e24a1a8c4918fa50730cb609ec338d491454c29098b4756519351f0e1f3a8ee1216cef24171b8a412c72724c3b4d2302b6b64a603
215	1	252	\\x9f13e2689012f847bc8ba74720dbc1f7a415846c0f3e8eb94735389da78572ee0b2edb723753318552f50c8c1941465a807fdcbb97cafd8f0a782e030e448001
216	1	162	\\x80ef5162f54ac1ec586a45a7b273590c72076df1211e0a7840c0b84c12c89fdae5e5899266ab261f6d6906ebe1abf238bc6d89e25981f523f3d32218e70f4807
217	1	150	\\x72f090a95d273f4c9770bc5f574a9edaa04c695ebfbc5ce496bf86db9722987328f613be5ce9c52cf3d5d6d2fa4163ae34115507ce5294298f86c717f3d9e400
218	1	345	\\x6e338864d23cddacd276a5279d7710d93abd6f4ea7ab37e460d046fc95960b76ee183dc47fdd4de44cdc508065c2eeca488f490518f3f05d330c1319563d180f
219	1	80	\\x0ce9898453ee752a27225fe4023fc6572eca1bc531383578de0c57697e58425c03e632770babcd1236fbd3e27024a1a150440f2a7177a33cb6619d1ad855d50e
220	1	35	\\x018a020b868ca79e43c93c63390f957479fecf65a8cb94616596d68c830cff4a7f5af16e09da3a823ded0cd3d00437dc01a1428ebf8121848529969dc2dbe20d
221	1	303	\\x0a8d5551f291330811a0a3dee80e2db8d199f31f7d7e6101bdfde61e13dddf5ec8d5ef8e8f07fd64fc47e7a60f6a8da37d1469bcda0ff73a28373f07b9bb0806
222	1	349	\\x7f9d000a7dad336ba29c86efe6943d9b20ddddb62654aea48e30b315dbdbe1831ad44010486b63cf744887c73457fcbf735a46e6c45bfb9c7631d7ccb7160f06
223	1	161	\\x9b502035cb99dd7c762dcc75cc44eefe6f7360ac3f995d149c7ebd83ef95ea22f035e3898cebf26dcc00e5dad844ffc03786f99b691ff9cc621e028743c17900
224	1	102	\\x71eefd9b068a4f4f23854a106ac76e5a69c6d1d2336d20754124fe622b84a95fc0e740036461caebeaea778327a09ddced1635d356924b9f9ea9d7f75650f206
225	1	192	\\x47cc49fb7f6c0bedc520be8cb46ee67be54ca2d34ee0463e830b40bffd63fe03e01a9a64a923bd629a9c54ebdb86aca4f823b555de9f9ff62356a0d9cfb05602
226	1	70	\\x9d9e493ee2495708c2363b406e2ba82cfdd21dcf585cd1d4c6deed76c644013594571960c764e5b132e62eb38048537916c1acfcbc929f55b2ba3ba33965db0f
227	1	270	\\xda7a4025167645292ef5304c8212c1043bd21943b16aea773ba4d6d2e99ce9873b20f272b2b3779388ba14d568117c73705829cf1b8f8fb8b9ade88deda3810c
228	1	51	\\x9eaecc74ead002a5d552003d96e7a379b66fa0e84cc185df89b6cdaf79fc71d9aac29ef2f0e0cdc8cb23add25d5305db1811ce93911c2993b1c70081315b030e
229	1	111	\\x08de82fdd0636414523b1d41ec3f1c972da07b3b3ff9b6f2e3c1040d4f26b163e55bba8b150b74f1825ad0ae077161d1fc1cb7c63c8177af842f0200cfcd8102
230	1	413	\\x4e6e5a2198f257fe20f458009783937c03b1cf53f5971c3814ac25602fe9e9a58abec785efc3eb91deda81f986f32d78cb1f3e2276eae48b3c4d6858f169ca0b
231	1	132	\\x0b8c4491efddc9a7f18af3d45662ab397b95ce37d6f2a359f4f7053c673fe2d9c5cc040ad62cda47ce8af08d32c08276ab14c13920a88bea46c4c351af184c09
232	1	47	\\x19b31cb895679476fe3542589cc8c74064cbe34ea4918ba1b35d91bec4d76b8fa4d32264f2adc71621aa218504e3829cdcfe598461ffefd777ba3f25d364490c
233	1	71	\\x4b198fe37aa9489be21e7061c31fe27dcb03ee8ff73081252e34f7ff450e17d46febee6039ea2198cc327b765695d0dae09279fe847fbaec0124928aa7396e0b
234	1	174	\\x435e53e009292483b167d860be267ed6bc8f140a780f4880a711f543fa3e9550e5905040af705ca540c9dadc907b4a1840fa6f09afda3c50fb8112eb8a2a2409
235	1	293	\\x129d9a2834fa737c46c2526bd2c91e6eecc2a1dad672fb1eb4b0cc08d738b1c0572b559bff13cd60238932d75219c9e072375e89a9f485657a779b68bf0c500b
236	1	246	\\x26da2f4efade2dd675536aa58c3482ffba148360ab44d57922c3165ff53cdab6a27b2acaa28b1b1ba796e571cf100ebc6bc1bad5dca4df7b3b8f649d21b34d04
237	1	235	\\x13203d6c3dd21c69f8e266e52adb73264a550c6074fa0643b0228a2c5287999737ef350b714aa678a8d5c62438b1008dc189acc058947f47c49b168b5461f207
238	1	261	\\xf6b69774364e2d185c27d2dbefddd55c0deb9bd76d4ff4a398d775ca8d02d4de8f28a2db0172893ac81b35ab3e3a7b4e58f7e8dd871b2c576ecfa33c8931060d
239	1	33	\\x1ab3222ae8ed4ed0ce3b9412ce283778b69e55185bec496136c110847806f1e686dd882b37fd5f342ffb6501a3a9dc0d6530b7e37de8dedee2f08feefb21c30d
240	1	424	\\xc3840d5509031d27e6a7cee99f08c8b616dcadd587daad5b5fb8dbad6965639a589bfe7e71442bb569873512f391e0ba652efe9c0bb399fc1a079937de88060f
241	1	228	\\xcbb313a5db34247c65114706f7d536f56bb5a32f87961d639642e7225bc9fa2b453f9305573a9f8225dcb50f0765642ef04f495f81c7498030b951a722efab02
242	1	224	\\x770aa5768111575b75c615c644f660388b0073a0ccac35ad48da06b7fb546778765f5969e84f59c5824cf7b794cf368f62322c6304bc1522f61b4a678b330008
243	1	230	\\x440909a39a7fc8734bd3593ed9dab36393babe6e58407a1177f389fb19245af1b3d2761449604c4d9b23d610845c08047b9b0552efb74a4bfacf987d46121309
244	1	407	\\xc4ae5d2401542a187efb0770b43c527fa9a0ba6fd1ea8d5da286fe561fe0ff001523524734098ba5fae05f3891f61172370203454b81044c9c9750d73e72dc09
245	1	376	\\x874c05c31a803a51b27973d9900688519f2bac35756f6106c522f19a59c1d081c2dfeae9887e303a30404f5cdea4ea821c378c6496da2bbff4d93cb6327b4c02
246	1	48	\\x56186c6ae727f4b8f582f59720ac3a67214dcc56dea1b4e7580c9432e83aeafcd965d42b590796c8abc28a466d7e5cf3ab3d765507717fb0f8491180d0c2d90a
247	1	341	\\x2baa336265ac99878ae7e6b3066f846d3cab830fa01f5827a35f6daab02bd494d8c36cc2eac3cd01fc5be8050c18c989a739473de3d8b81ebd80b193da406f0d
248	1	1	\\xe9f0a893559e0603e8dbd4f600cf441f2de741353a244c9fd13ddb2036713d014f510062dfbe7b1d2ebf42f1319f25dd6e47edae7d1a725410cc43e3c334090f
249	1	7	\\x5e3c5c779a92baf266c1a2f0397286b76ae37c33dc88b3e24118c6b842ff8b4e34b66ffc0f1428d3df565a8ded028c88566e6789551c26a4ea00cd050028fd0d
250	1	223	\\xef7d511996c8e26abc855944a802db7fd944d60f6713f4d63638097363246c214b70ae1ac1c16bea00be25e253f4cb62364959ee5f44bf177b566a9cbe716901
251	1	231	\\x024c8c1bae1ff514c70b33453f6c426c5d3fcb51eca8cdc371f2305d15a1c9e942c2f16db41febd4597c25ea1011bd855354013fca78c47c002401bbe8617c08
252	1	126	\\x45dc67a375e748c3381c39010051382fc59cfc30d51ac1700680a156f7d3fc67a452af1a2712a1a3f962cc357be3774cc2b0e7519dd27683ba49424c318b8604
253	1	410	\\xac35c508542559583f50d64f88af33304ea6a797aca6e503866803b9e852b458e1268631d3fd9c5b7296444d6a3b5ab5ed20475f8826e3ab5dcafec472bdaf0c
254	1	121	\\x41dfbee7a6d9fa4211f35d38065183b18c9372df8ac69b45a9357b82a6207fc2e0963b9df0ba2665b80e2e3848a7ed5aeb94237525d5daea5bd2471b10f7aa05
255	1	258	\\x5a03074a19a39d34bbbb5ddbb42912d5dd16e786635a0246f1da8bd382fadd00d510efdadbddd35905b37a8683bfc3f13382f7e2301c569da1f11599ced1460f
256	1	46	\\x5c293f16a61ba9b1e93f474a114a1cb595ccae47ee8a23cbf6fbf3d3eebf0b9cb8941346f27fe3d9b760e7ca961a67896d1a284677b7bbc96719ce618748a405
257	1	365	\\xe5623ed4fce48759efbfd842c7163c58d02637bdc4e66122f23e5489c3db8a76966979a22a186f8cfaf5bf0fe253675e5703dc2f255a93b9819c0f844049550f
258	1	12	\\x6cef5c7e697d7faf7e65e8fdcf458e19519e601af4c38f2735802cc2ce8fb371b0e6e1ef63c83d4d2426f03b56e42acf23c9c23dd8d78d76f2a96431a0563a05
259	1	260	\\x4858cb993b87a251dfeb83bdab620b15820a1d42d497d5a394aee24d27995020d98803a70578a8f826aa0d6bed61630db1d0eb0da01494fdf3bed55e3fe1610f
260	1	78	\\xaca990ba980a8446524c2a0e1d972e6430f894d76f89868c32bda90395b7800b51b492931ad84cd9682c16a0b76694a75790e90b2cdb913e0725accdf0ff0d08
261	1	384	\\xc59dd8073b75a888ceb3d06ba2c171a6d958329672899e1e558e71f36c9663290ec486722c22562d3694d157cd8d068c6d6f5a55ed8d18ca4f51396e4dd02d0e
262	1	266	\\x16e8e10cc9c583e2b38b48fd6e30caec2d0e4502ee72434b609cc5d380574ebc7eba70de46e3b3b8e9fc5d8e4347599898792677c1e56cce691343578b526206
263	1	211	\\xb12652f2e79721066cd646824d6028b83be3f4e3e195219e11ffb81dcf2a55daa1ef7929d8594451efb1d78184d37d4c4acc8bd4ae1cb7436b9799a7c32a8408
264	1	218	\\x3e86afa2367e5a59990b333ff939097b1c46269f7b51803945fadf9c37f27bfda818e4799297e3f396071e8cb964363ed6a89b96bfb5fac992dd71d68757d800
265	1	169	\\xeb8e03a41e8b128412e9f84e460a441fe8eec55472601c9b9275c35b530ae40361faff7972bc1c11cc4adacb24c423bfe595c93790ce4141f6e55a878c7c2d0d
266	1	88	\\x1997cf45b8d28417a2d60693e7d9dd5a92587d0d4d1a11d3fb38512988784d7dd693e8b2e0ed40e56e7a3a0b9b378958c58214ece92671a96b5ec1f12205b801
267	1	36	\\xa8e3b4275a73e6c24e3212e68aa41b88caf736812c5e237256417a9cf8168d85b29c949da8950c2aa6433f03a34f6077d00edbc6b3409f8f07d495533f8b1009
268	1	179	\\x2b70605464f25ed8feaccc5aaef067e2d2a5c400ec29d26ba07316bc9973bc27c2e807179acfde6d3698dcc8a5e0a74042cf68f9d4b4b1836f2bd63394eeeb06
269	1	284	\\x22dfe80bd108629f3113056fb0f39c50ef04390e8947827c5b82679cac39e42adcea62c031919ba8b9848a3506411cd5320fcb3c395f5414162af4c23554b20f
270	1	381	\\x6b3a22801688cb7ddb02635db0140f9b7e5c3f0cc5d86da7f92b5ea96e6653688e71047a901af4a833a9313be722a6502a19e967738e109468617620d1af7b07
271	1	103	\\x5b42cddfb4d90b5b235c4a3c1bf04cf51de69b212f8be51c90b27f49bef4dfa0b5a0bbdc0502a4018c706ef6ec996f033600620168750955090baf42f8755606
272	1	49	\\x65d5439cf9c3fc3c676d2a9243f145354f8b24b8c13da970c2416a0e4323898f921bbe3835082d41847536f11e2eff5f1ffaa70cdd30ec3dae52ccc4eac31f01
273	1	402	\\x9af7f5bb7c28e051d12d516fd3cbcf96f88734a66a85bf9f6c130761245b7b4382ce45a46f61686df6fc28b83b53d0ce7eb603d57c0a3f89450082128dbf230b
274	1	320	\\x9fb3aef52ffe92ebd4a918e7ceaa998e169cb94c6add29a8c72c22bcc4bd345b4a69d3e03a5e9b973428f152f886b90fdc2603522238cac83e4903fec7e04e02
275	1	153	\\x0b4156feaed6536f90bdeeb338e8823f566496dc6cd338ced37b6920d5e4e330ee0ea01603208005fbcc03280b5c397e8d0b6e7073370bbfc41f9eee5e773c0c
276	1	291	\\xc2d61c002aaa48925b62b3beea6b29bd96580c33dfef1c0facf635208ebe678aabbca07f9ab413de15da896fb793dd7efdbf32a60fff60d4644a55aaa49d690b
277	1	355	\\x2b5cf57bd7374ad411809c1f5f7f663a39898c6394d904ef2f37c7e4e2f41ccac94592cef70852b9a81b384b9c0cd3f75926aef2fb6bb17923438890bedca101
278	1	241	\\xbcbf74181ec82c9019aac5165d4c033dcbd66698a15de9c6975c75645ba8837adf1eef3e66c341456f47275d98559542d68b1d50a1666ae09bc866b8eedaee04
279	1	195	\\x242998de623b168d77e70359da8fa159ca7d9ddda91592ff6a58dbdfd1ec5ee0a46ddd00d7a4e9112c2b2e5bf8aa5f799bae1602e1c6d0584eb8868fcce0b501
280	1	61	\\x7167e05d78c37aac80dd2ddb77c78074943d3069935d4ed736ac389ffd841563651cc8101a84b563498915543964b346ff9835f47c0208d32f18759bd2177601
281	1	226	\\x4ae002a7b2a97fd979ba6fa35bc7a279192b5732d8a9b758809a124659fafdd30fd03c0b2a6da81a26c5e1a37674c85310db90458468f95c9b24daf1a9f0500d
282	1	324	\\x794cd0e4dffb8067c435463e9b352b5e35750bc72f2774527a36c9663539c817bdfd1b3d9308cdc73f3b6f7d8752e5a26230d2bd3cbc76227fe3bec81f5afd08
283	1	125	\\x7d43c48886686ca4d26068ac21e44dab8a016910317df285a6ead4e5e4b5a5f6ca8d7671557acd127a71b80fec8db257018a5e76cfce568b088f201d43252d00
284	1	92	\\x5b0b3cd5fe246a33e589ed37c0472afb1f70cdd3a2682d655b84238874f8b679e3c7cc049470e53b92b83015eb95d28cf504ec37bf5f7b712f97bd3eba09fa05
285	1	208	\\x8ea0ebce7801f206ec0ef39423303db6c0a82637987f6cdc6400c0e40d17a524838172a3c200a24a59b88866756a4fae464ca2552162d0d442b5105be9ba8101
286	1	56	\\x8660dab3bfcaadc7a6f9e799be530c6e892cd52e8609ddc2d722fbef69c581c609595952c5b75f5ca4b9d9b5befa2403dab0134d38d6ff798dd6df45635cdd05
287	1	409	\\x3b7ba19e61819a6b6c9010344930df1353d209d1c80fe7e818f56c7ecb03b18cd57586f5c4957e00e6949c692a462ff45ae578df264304ef6c8b88ffef7cac04
288	1	189	\\xb2998150feb9ac7cf010f69eb86112f1daf2d45271a1a602a74feb55a7f276b8bb4aaca6c9d76cc841a5e039f3d3b40e6d089504d6bec91fc4aeda9e390d2d06
289	1	17	\\x9e5eb191bd83f541e0f9c036c069f0dfe0e7dfc1f4d9fa6c1c8c06ff204e32e648d529c3ccb2a98f4578edcc28f0288d707e56c37ade9f00b969f20d1c34c10a
290	1	82	\\x8ef2ba26453b96ac3e973d670c436f53d223317047f26f26f675bbb539826c8407f85d056c9730487cbe013b6b4919c48d78714cf792d17a62e3c883f108c304
291	1	148	\\xe5fa13e51dc096c3ab1c3bf8deaa1d530abd19f3ae71dfd4576320358616a4206f872913a06131706797526a496189b1b06d5a64a7d46c246509a91bdf9eb800
292	1	321	\\x80302fd365783d0e68cd62ecc85dd943cad0e542c09a357ec42cc7564bc5ef242ab75c77ffbbb5057927d457e95ad202e4fb9708fb2fe6b33a380bc4714d0a08
293	1	274	\\x3a679cdda9a9bb4fec85385b0e90d9639ef47792c890e7ee7e671f16a7ddc6b78704c22a5def36938f4691ca4f3e47df0ff4d5b6b6944cd8a5ccc119d112bf09
294	1	350	\\xf5d9f63e37bd691d9bd9c8be6aaa6207e27f9efb8eb6e8c785fba76878b6c3d9b9071593f760d11bd58f613a5664753d2ffa6f63edf997792f1741a904142b01
295	1	202	\\xadda7670bbed113441a8e55f16c6ef3495ec76a9a68d7e839d258fe38803404b9dd6cebcd1542c516002915f25ca2728b2bdcc956688a264610779377eeb940d
296	1	243	\\xa73a13dde2c18537c08d823294954a986a4930df938355a879b05e826e5fa950f40015cd9ab3212e09f38d55b78ce92bb1cf799ce335794825f0dd51071a8b0f
297	1	120	\\x1658f0ae42c072b94f0cc4265cd4de9ba53831f1dbebbaa485f573195c27df1523597da7467682b212daeb2bede2f8d06212af7160c94aa51cea0f8e35268d0f
298	1	251	\\x55b09098bd676e86c850ae83e32f1220bfa88a5eb529be1266e38164b1d6355bef94a829c1102aa01a569711c750a3ec5661a4087c97325b8be7a785593b7001
299	1	383	\\x77400f101996df0d4ba59029b568b9863b977e82ebc7a2ed88e54c7366e65f99507499310b76451568d468d5351c59033f47faa3ca1a937b2b025fd27edfdd0a
300	1	52	\\x9adffa9f03eda0b204d1ffef1fc5fb7569373606e7cc5e111555df378e5bcc8324ecab6e41e3df9d518f6f205661d56eb210cce8b5f4c8f64e4d6f7642680109
301	1	386	\\xb438c5d191230a6558fa99f3f7abbf09c7b8589cc8e0eec4896988c67965e5d5f845364251669205ba9c9a1198958722cf7f893cb5f730ff22a217dc9fa87f0a
302	1	182	\\x8536074fcda3d2c61668356d8c5b317e12d0a82e8c465a79ed0b3a6493d4b09444b530568d2d503c1b84abe995fc3560c3d1f10af812f26c7054bdf7beb6be0b
303	1	196	\\x609c6ad7e82a35a10202d11985cb58da29ebb89b14857f7aa58cdcfedaa84cafecbeb75098e7733d23d7662f2e168e187bbb4f9a3814e848d17de82cdcf84e04
304	1	64	\\x67324ec872ef513c3ac7f0299c0c0afdb65950b4ca093809fe5822582bc39ef3deb4c91292e4f5aa436a2f975ead2e52c98bdbc69547ebc829f801f27c989705
305	1	138	\\x8037950e1ff67c45e879b84fac1253089ea09687b6c67df3d30f7e01b6a5d6c4f7398d1c523c4aa615a4b6de6b14ad2f0c2e70ee98366bec614155e4c4a3cc06
306	1	268	\\xaf0663cbe996bc057b4ffa2b69933eeb12355b622e88acad40d4c5f30f601955ee225c2339abbd14f6920750abe6fcc542ac7fca65e5e09d8e6d6af738e9c708
307	1	44	\\x7d179b5dac17576fb569645a16c9acf184072d6b76dd06e23ff57d20b22faa44678d4ac64f0935da8b0cc1d7a348d0fa8eb60283f48ded1a3dc371054d44960f
308	1	84	\\x445aed32674f9d77bd2c9b8e719f8e1f5c4619fd56223e1fe3d52e418660a7aaeb422ee4120f59e92866679b45c4f03498a7cb423bfab16ab6fc41b67746e000
309	1	362	\\x34125e931927dd9972663b1b185413c2dbd2b33fef5e3f3d76c1dc7eb83ff3a577df2e3bed9dbf2152df6defee9e9f40d9bac4d9abc85e87fe409fabc01f580c
310	1	289	\\xf75fb1d103fb6230a79c72e4d067decceff44870d17b2b8ee4f302aaf145e3ebd252f09f46afaf02008066a5a967d1573e701d085ef3922d7010b1a220b98400
311	1	166	\\x32599ed0471376e0c50c61d7ea88da8c8709a5addf4b468f8977c8e7b7e3150fd6e99288dd5bb0aa3c135f978d98970fe1099fc54c2bcb961473d5adac7fbb04
312	1	356	\\xcd147952f055a40a1f30cc861c0ad19683f89d844d7e041c4c3c41e6052c3889c1c24afa184a0a0c1148685ec76a734069586208c3db3729b7f7aaa1d069d102
313	1	42	\\x2cc1496a41fb9146e43aabc59843351e07295b979882a654304ab40e402c07e797c3f852210398ae15a3f007d6ffd4a21d8c8a6a2abef909397d28f9053f0403
314	1	77	\\xa7cae131ea8458eb47f863ea13329bf6f052e175da6b199777aba85d63310c8a502100506c400b9a10c14ab2faed260d151e06f66750b3bf043275cb2852f207
315	1	205	\\x67f64500e4616a68458ca1f4dd8e23f698bbfaaf5f7dacef7306ee78381fb9af1478a10a085def2148b5a51a1e749962322926ae81f951949b12367e897f2406
316	1	117	\\x7990eaa786fd30d07ea18535be2114efde42bc09f948451c4a3eed064126ffb0daae58e797d709892a974534fcbe8dcb15348b9fee343220406b1ab14c369a0e
317	1	106	\\x7f2b84b12e51ae3b8606fc6358f86576e9b452c427a5bc8b1ded3ec76fe5f52b5d7c2dfcf98b6ca17d30abee59a1c4faba209a1d5f9fea626ff48c38b7ae4a06
318	1	152	\\x8eea2b14a41817f61a9b600ab4ec9edc68c8a00174d6ee335c7e69fdd09f655962db9658823742e0e9266a509213664406ccbb6b4bc17cd60e0242247767280d
319	1	307	\\xae114ccadd7549c49cdcf38b0383ed1eec8618710d22396923c56e8b20ea0760831e706988ded3f46ab7ccdbe920a6c3a7203e932a0236b8fe0e400057948504
320	1	160	\\x1868160eb68b8afd9e5879ce2bb5a9e28d9b2cd4480fd026e384a23fe50af737d0c1cc7fd0235b95859d27e8e5fbbde386a696c0243ea8d7d4d22a115ce95003
321	1	304	\\xcda14a5124f697b2543c81e065868935c05c1a07c18dbc356a89c84ddc58c2e17c94f3e5892692aaf128212d58be71bd85fe90b840a59cd40d3d673f1892cb05
322	1	318	\\x63db8ff43d31375dae34de6b279172f02871433ba80d8b05a6672ab4bf2e8228f31c509cdef4dd08c0b3e6df2ff638f8d3a646a7310987722ea6974099b35408
323	1	295	\\xe6692e9fdb86d952b281fe245b9612cd715f8fd88694746de0dee69e3e15553834a28591dabd85ac7da74348ac65dd72e2bd17fdca44d889ef0340e4d38d740b
324	1	37	\\xb1471120231769e0f7e9449f72c2840c9826a3901cfeda5863e22773d2395ffeee4163a22d78763f87ea2ae4a001f956befdd62116508da0a365fbf8aaf63f06
325	1	190	\\x157b67c4efdc5fe3ea207464c1c4cacbe39d4d398031728037c6078741d6bfff523cba5b69b71367a2a3559034d6508cc80ce715576bcbb647a86f3e230a630a
326	1	415	\\xd54f6e24b06619bdf7f292adee4e6a5c6856a2e43ce261e8ca8549aceb6cf6dd98996968cb4a2d208c8b9fd03671709293d93de57f55929cb921279590c69700
327	1	222	\\xde9ab28e07d11a1676ee40d761fc971ff63e7a5c26f3206b3adf76f6e12394d3cac85ae7fa451db26b793849597d93861026418a3187cd3f7b521bae63271805
328	1	115	\\xc74e62d56ae1847027b5344e5b7e291e3bac8bf74e65dd4055111e3de7377b6ef27ff7965a5e6ca9a8f89a734ac37e4401b2f1343f556cd0d8b350a54ff3270f
329	1	185	\\x644ce9532e5651fe2cce539d50ebc2ba21bac9d6c5156000a17e238dd371549aaf13eff671565dde65fa253c5d2e6ab3926517490c542b5a1f024fa40c744f09
330	1	378	\\x74c3f8c86513d4909c889ab85e7b360d1fe4b9715d00b6442341238c4f70679284e7f5cfbb4dec5d01247b7d661835ff51df5919e845a0aa79857176441ec709
331	1	178	\\x8c425f62988003c114c1e5c8003c16baad5352da5fe8a8435676f3c3ed22a9ffa5d7cf13c0657b7dd4c25c2420b6aeddc14eb4d352b2552503209ea0dbf8c20a
332	1	217	\\xb2d4b8fc67ee7bdb6533a7655d160691dd5ddeafcf1d73db084313994c24d8e86f6c2951b923c3ee26656a2e235cde7dd0b07a005d67cad0dd5d90ddaf576209
333	1	89	\\x1a6b470ac8e547fb316d9d1ea880877267a8b493acb748649e35a65ea7e2c4bf157a949a1cd6c5a0f50af0c33a9b0c86845e77e499d444d6b4eea5b84d5f4e02
334	1	39	\\xb9d0198f0659c265287ade5f2fa10ea56cbb081b2b283990ed320fc621789675a7c3ea9f62f3c99a3359b1fa1325f6d7b9e8485fd6373a68e94755ab593c4e0b
335	1	387	\\x3518aa225768ae0f98cd94d18b1a013b858fa9aec2a124eb058cbb373f1a8c0a3cf8c3ca1167c14b53ffe2bdd1be8fc7755594f3ab6e92fd25686fb5c8b6e801
336	1	172	\\xf4449b7d33938011462853c84def9bb82b079e3736cd7376ce67a14fbbdd64f549991a18241b5124c92acfbca5bb68b021df7375e864e3f710160d3a3f4f300c
337	1	204	\\x7d64bcf19e8f2ad204fd79e06ee14cb8e967b7eefee8bbb4b9a4969c1026c67b5562ff00f56b994ebb62b688524b31fc53f672e7e2e14acf973af4e545540408
338	1	271	\\xb7c601db5c6dfcc50fc032d458491a043ac0c140ed6693438fb356cd7247b83f8accda84087c60039372b1f154fcccde6856d16608266eb61a0456d587ff5d0e
339	1	294	\\x003ad723d33e3ec9151c2d5de0c8a46a1b1253da4b151d44006ec00176d4da3a30303dc3162d95153cf3be8a78ec08a702ed18797bf04b94eb451341bc4c0b00
340	1	348	\\xc6c9b1461f13ce4e646f34030bcc8284caa59d8b95d3480b92e2fdf7c9623386f947e3bb6b8298cae3df50f79c6298e7f39aed432bfa982df70378fc51785103
341	1	206	\\xf618030a1bc832c13accb1865f5d099c6cd3837d9f2dd67afe7e8a9715c9b1aba840953475dec43fd1c57a884b616a9e628c8a9c1da9a15147dc2db3baf5b10d
342	1	233	\\xe1c77b61252f89be436423507c049d9dd8fb9f29d18cb2f5fe2f55d349845a53efbe96bbac57d37ebfedcfaf0dbec58da5d6ce966010ff38db75fe693c789104
343	1	101	\\x9ad3fad59dea6342a63d63ade8eb01bed04a584fe188f14472a5413936d5e1638f05b73742df8e41a9396a9df1d8d4aa14ab18eeae1778f6ebf643bb86301f0b
344	1	326	\\xd07ada5198761eb8d581ef5de4db190d76007de8e2210fb162543e0a7b2bc5f99d28c2c4d25a071364cf42b5441c8ea003f2195c902fd1a484a8b005f9958707
345	1	200	\\xf4c22c84d1a1fd5e18b711eca463a159ce3fbedd9a4332c255f10f402155ff7b3cff6eb772e9282fcd4bbe2756cf261790fda02060436eeca2704e3f7d377307
346	1	338	\\x7083fbf3f58e8da80db9589a3335779af23dcc12a1d1bbbe2bbc0927acd4b54343219bad7f8b80fe7ba21c3198b9343aadedbcf0a9fae8443673180f9edc8807
347	1	385	\\xc55b82af7fb43a1629729f6c7b50d1ac33772cd7eb4bbdcd395d6f3af69141099c20e516413bb3b01cffc2cef7cebcb91fd77a99d9487e7b1b376b810ca29204
348	1	423	\\xed0e0989e8b43ca70edd9706150ee7a2b842b5b8fb313184a014d4549e4c0182ebe49bfb82889ab060258b8b5ce8bce28eda35c7d0a712c956c0091f4f216805
349	1	234	\\x28ee059b8629ee49455ae5090df096459d2caf5f863e10bafa5924381f8c280aa2b27dea19b300143701a638a60e3a265def6f56410e64779648679bf024f00f
350	1	417	\\x6ffd7c2efd7dd1b385157f49db5c321fcaf5bfc4bdf674d6496790c56bebf5f5d75b71590aae20d4ffc9e599ecdb8aaf0ce45bd73a6106778ade32ed5b478304
351	1	105	\\x226c86c597fe20759526a9da39709082ecb451c66f09468a89e7fdd86008d1822e013aafdcbe92e118aaa3286bdcdb863d0b16ac54653540f5c88db3ec21fc09
352	1	263	\\xac3cf24973355ffcdbd8e9b4f7a3819f9bb7c67f27ef3029b401fac0abb3474c54d8ae91d4b074dcaf3026960d3ee07f77622e72fd809714ef4b3249c591d709
353	1	245	\\x0235ebc7691cd65d3df9f9cb96637a9a961036a9ec3264ed29a9e09570ed42511deb9468bc9412e2ababeb6fdf7b50c51f6f0d6346c83536314341048e8bc40a
354	1	23	\\xda832fa18c9f3622ef527fc047f5293e45f2c267c39b02444460ff67c0b53231732dea887b3b519961704c56a861a1229d69148ff0eff10ed751a1dd4a576a0c
355	1	155	\\xdc17cdfd0dd55ff10ff8f7d3bf03ab525a184f338d56cf29b68c684b7dcf6c23885cc6239d4026ba6c7271f8f67abacd2fa8991619c4c0c3af5af33e8e2f8604
356	1	18	\\x381201d697fbb431ccb035f03529501bd1ae5efb2e7904046575b616d71acc3352d0c66fddfe2927c51edda171de6c960467bf5d4c920a5180d9b1de65102c02
357	1	197	\\x1e6e06d00561c358800761e3895b4d19aeca2c3fc5102105886408f2a4ced4d4de291519d8f094cbb57dcf79102ed39952d6cacb0700d17cac652331df250e05
358	1	97	\\x104f462120c6fcf261eec429faed28302fc3b907b4242609abfa1b1758629894a28ab85cfb51feaa68ad34ab659a9f5ecbbb4f20ec66d87f42ef2ace766f720f
359	1	405	\\x0e7a981fba78e91db8cdd211fafb098ee4cc63e8a2552623f3447e301a2ed0ac8e1c7ce62c0db7bf93e9f14754bc1ffbb139415c975f71614daa4a5394a6a10d
360	1	54	\\x6461aefdfd9f63d9da4ea189884eb7f8ad7063d9b2e22019d9b760ee86010bd56b1cee6f95c39cbb3e034d781ec1beacdc1288fdae00cc6b47ae9a85627c6107
361	1	306	\\x9c8f8f162516c69b9674b42440f73540462a88b2f3d2b859bd13f9fd18b4fb979e8dbe3b185b74684b6d73b83bbe030b9b0d0239445725daf68f3fce4617cd04
362	1	342	\\x36584c4e139f45025f18c897e476961f0e66db9eecf8ade19e18ca17c0bfd11ab3e55034ad139c18b979dad50fac870005a10dcb26f61de68d54d9284c2ba40f
363	1	157	\\x13f68cdbaacbe6fdc69806d8fc3a994b660be652c82a6ff36a500c92d5bf8d54be7cdd39c904ffb735f6a65d0cbebab489d004ff69009b1adb7bac3f27c9da01
364	1	227	\\x70512cd952c7528fcf6027b8f1f30392ae8d3baaf42489004ab2d6b3dad86f8986f5c0b6e925298560c21cf594e7f637b869d0fbffa6bcca50bff86decf7670f
365	1	367	\\xa727eb4f68791e3647dba8b82b3654f13629b3f6900c8dbcd74f4fa05ebb764cc7aa951f8730078252dc39c2b7064c44b1bdfff9818e979c6417d6d4f89f360a
366	1	422	\\x9e2ec13aaa03d76f36987b4d9176bb7982a6fd4ebd0d0ef726cec4404a73aa0fa57b621adcc8911dea40d92663b41721eacfcdff41a76922f395cf40ec408207
367	1	143	\\xf3b76f60c4e5cc7f6aa9879ef8e126a0ae883201a02beb7537428ab0c14dfa36134321b3e188bbe0f3f481721fafbefdc18fe6e3a46f86769a030f796fd42104
368	1	389	\\x2c8c3b019806a7042c205a9d0a458e3bd8a0ea1ec3c01094d93a22ea51f5cc1890be32ccc44e0c4f77625f3741b34d2e4488683b66c9928cbb803854d8b00700
369	1	20	\\x1a036fe78668faa2a5b927d0ab55d5278c414a53b82d40d94e0098d030858ae7b1ec72b3a1fe9925f11405fff1277553b3ecbfcf1e6656c1a441a371ca24910e
370	1	334	\\xfd8c476f8d434e55013953ad7e5fafa9a20d7941769166bc80850d72876f6413bd28448979f9321ac0ea31fc17840d86074ab70a6b39e74e0a4d3ad56082fb00
371	1	136	\\x2ccd74d87f2188341e81c75d34f73f4421b05017697663ed74087ee7a6ddbb64f2fc2369aa9ad85d8687d1b4ed5d684982ac2662dc8e3e7a5eae9923ada5320b
372	1	13	\\x94a58d3a1ac871e5edcac99a965e27e15576d0e1f69ba367e21b1181fa84c0d3dfd913ca85840ed098d0f2beb6a2da0d85d17c2ea16bf8753e3243f5abcf4c01
373	1	357	\\x70c79ee523345b1bb0ece36a88313ca9be2c899608e74a30bf88898e97aa4a982091c7c96d538294a7a216c50e490e49062343cc05ee8ca8fed7f3ad38d3710d
374	1	113	\\xa553d846ad2291048fcedfcbaa40af85148477e92a3fecbf5e6fb086e7a182cc56f235be5ddc757575a600721b036150d1d8af52ca67d465296387a1fd5b0807
375	1	366	\\xbdfbf2acd1b1dc3157760b6683dedddc12db07e8a28a7249909828c000d99dfb393a8e94224e9e0d0ba3ac9c31fbd0f1d0149babeaef9b864cd08b4147236700
376	1	130	\\x2bf5ef01186803fbbf64e9d9e22c0b05263d4ed6f12cda9010f2d45ced3fb54bb904cd5958bb8ae862b883d91cd5437cd651b15fa925cacf4debe15d23974e02
377	1	390	\\x998dfa230408ae7cf3e48c811aaca437d441eeeb90233084d66422515e4702724c6d1559d9973611f8ee4dcd0f64398cdf20d07414bba0845dd914faee9fa108
378	1	358	\\x584da5c1a35bebcb0d0ceef57abf5d000e32545a747a9e7cfb86ceb87ada654e573fea41b418cf33d3aa9cd36feef06a4ada4fe4cb97f027e3ed1a3ffd25ad04
379	1	32	\\xabaa77d4a8e0887c63352fb5c774fb1b1faa68b6088b0d3a2164755c1a6ed773fc66da2be6ebf32af2f291c20bc2db5d8d37cdeef2729d2ed0ec862a4e43e404
380	1	272	\\xb3cc209fec499ce55680a593e4a97fb704d1928993c5a1fdaf6a3dd8e288b4422bada2d6b50a948ea04443a6d1a110214b4c45cc56a3439e1ee159a4f21b5203
381	1	158	\\xb181299aab1ecb55718f39baf1cfc6f719087d1053337410e758fd3b0911ee103f5772d67823d86fc7d28a6967b55d7635d38c12e0fec6d3755e85b34a2f830f
382	1	395	\\x17dbfe215c20ec178010c946808db47f1348d89af1d6e6478ad195ac71750d487b13b19717527e79f0391d95d33ba7dace56fdd6cc30dccc23c87b7d5319250e
383	1	38	\\x354b9ff99a65e0f50af61e7f24ba48764c9d1b4aa273a68eb93577fcfd85ab5aaf7d3b0dc941e2ee50e354d73f6519326ba44b3e1a42f514251bf356288f160a
384	1	112	\\x9cbf988536fe1325cd9501598645ad226975c8618ae11c622695787b6f43905e61c0eb65a8839a9248f12bc75f05597831dc32be6b23863bdb5e8730b5d1b509
385	1	273	\\x914b9e31b64af66253b2643e92de6c0ec4d16552d7f97ca27608ca674ee1e14efaf7d6b44810108cb3bac228dd649b12ce13dc3ee522e702db3ca49a9c4a5d0a
386	1	74	\\x6a14e8d00baf9b1172cf18d89f623ccc14fa3f7de5b967028620aca19d13ae70a69363664f1c820b2e9bbdc0276ae3dbafb7ed68d337641898df4f0f52c41d0f
387	1	250	\\x92b3d0892a660236d70229e0ce73476bbda067f337c7672068c0fabf351192d254395b8578aedc27e4ab0e379677b7521a312fe9fe7e0ec637fd81edb95cc300
388	1	264	\\x8409965e80e52ac583c1c6ffd1ef0d247a8f16ad76ab321e306deac8cb4fb7be812995a54abbd9821a00539f87fb75490d877fd3fae81f700485af259339bc06
389	1	353	\\x8ec768e62ec8eac5181b4c5a487aa15437921e791cc35344b0ed1ffd74c6bb8b4efd7a7bf9e7f6b33ea5f5d45b72594a02b268929099dfda511908e3c9499f08
390	1	292	\\xd34323273aed6a135bab333768dde19c69f958c3c706d003df3237e9cfaf59a6f7c9f308237346d1a5b85c91c1c57c030c4738cb1b4c0e4f85efe00126f5ad01
391	1	2	\\x1bac97d6dc2366ec2a345f6a0266c337eb26a5d07d2c09b9c9ca0fd76b6376c49cad7cfdde430490fa0a3faff55f61fd14260754747056ad705a3c9ce180ce02
392	1	175	\\xf0b71bdb696571c5ae009742b2baae9e2831ac4b35786d084f9a50326bfccf53d987f315f0cac5a2655813a749148d2bb5396c92907504800411ef9cf7960703
393	1	309	\\xc651cc50e09fd7be6dc1c1473a8c275367be155b6765cc8f38614dce61d9805e99b8ee1be6fd30054c4bbfc451d4b8fed47dea68498c2ebe02a8e69e6c97c90c
394	1	212	\\x87c2b09a9ec4cacb1c932298988a9ad1d7cb95ddd6cc0946387475514c38eca4533ae746bf08870114ccc3d70cee122ec9394df352e2980257a3b52560024d09
395	1	27	\\xff9e0deaec1fabc5f8e02321b1c8161a29ef60936f02bd5c4d22b4064754798270150eeb465ae0a31a0745188ca7ac00429026453988af25b31ea132fde27a01
396	1	221	\\x4a429f62c8448c9c5a07ef53c5be0e1027bae01683e99084211898bfb4f54a34456ee04271a09f1dfb7524710a0964b3b57099f5c6258bac34277fdfbaa96b06
397	1	391	\\x2a46e1c05d4ed45af3b5161c3dde489e43f9252f4f1bc441233e909feb97be5cfbcf6a8304c9ff9299106375f91a00cb7511aac178c1f304b9c63a18cdbef507
398	1	336	\\x85d665f8bbff7039fc9c06d8834201cb2e6bc42af4850cb66bc94469df6ab15f514b962ba541d1d484339cd6915faff73faae3d8be29e69859a3a424726ed509
399	1	335	\\x0e7dff6bb809f1d49d00902390807eda7397d1ce357bff0342b21ad5cbc9116ef4f2eff41f197d585d32ff86b48d05c793dff64aa6b67d32ea840bf2ea501e0d
400	1	247	\\xab115f19aaae44d062290706896306719860ac07b7d871b447ba9b98db5f6f74e18fb39b1cb95890d53da9c240c9011ce660c8c01794df47d4f07dc0f1176000
401	1	203	\\x020102f62aae996b60d14f34b3d6a9573f6231b807031b04b98766d50ba29a0fa99c935e4e7ba11c3d71f0b21b2223780b399b19970842dda08b2978e7c1170e
402	1	237	\\x8ee62438837356773ce07e4a9969737b8c9064aa4d9271ecff44b664bb60167c2fd9919dcd656fc1785dd0c37cb6552ddd95a33445a3af1cb891d045d764d30b
403	1	142	\\xad14905cc309043becc201920e310bd6be141380640284e6746abc69d57d65eb8ef021d3f361ffd46786a004da366844d3a2821008b0894b2c07b66359ca2905
404	1	194	\\xeb1d7eebbbfabe4d29dcbf44f09327b00c97ab05b8d75842051715555c5e582713076241c8b5d8f878fac6bc485cf454d0744f08fbbd0e72603762801165cb04
405	1	328	\\x90512415d5bd37321938aa03e661c22e98ef7a082d44ed16b041c68ef99737f6372dd83fbb5de00650d2d35da15dd5f22466f7e1e640990ce9bf459eb2ea1b03
406	1	173	\\xe6b4ca11a8c5247bb94170360e08555ccb52d7f1a545e0f671ce6e0dc7073090e9863019c603c73715e9baba16df17fab3288d2c9e624831808c578512317b05
407	1	163	\\x3cac5f522f451c43fc942282b7dffdb7435c58b2e3d4aaf5c8791fd35e678fc4ef08d77522504553a31aa24eb1d20228a44d52492c6d5d896e5d9746a6fb0609
408	1	171	\\x17ce0adda0d6a653c64e7a3953c5006d17cc6f356f3985f8fb362035315fd7d56ebaf5735298a5f705b4919aaeaf670894586de48b36de25e51111b524edb20e
409	1	411	\\xfbd57c080cf0379151c91b87b4779fd8fae58618a75e3f1d93f7ddfb6072ed044be764456960eb91dae7215927cc2559d87935c30d23ab38eb643f1d4c4b550b
410	1	57	\\xd27084546312bb969ac4026dc98ce73786a01bf1359a6f60732ab255edb11f29abff828e05f362187681d4820b02317f84fd10d9549e1682a64f8b305b3c3f0d
411	1	400	\\x9bda45e322222ce8a5bdcbbbe730b91956f188de8284b8c6bdc29c384008cbabec28888d75de6a6380c0061f7e59611313f257caeab0e9688fd8f303713f380a
412	1	313	\\xc8fcd2835c01527b0d380bad8fc6e9f84019f3b3e7f7058d415387c7f1a1208ad51fa51c271c37f0df7e127b70a3589c5384b5ceb8a845bd28b1910ee79bab0d
413	1	59	\\x2b462d1e98fdbd80683c59589f676fae1ef6cbbc9b31373fd906061bfc7af6f9ea9a76a38593a26178cb80a688464622900598b3b4067dcd3727fe78d508540f
414	1	114	\\x0603bf4a37f718aec3d210d70658cdc0b9b71ba6f1bf03775e9d9425e6a4ec2121eacdca639543bf3b3fdc693235e40605ad7210665113461c7263a962013f08
415	1	398	\\xf12fcd13190c1c1873466be9b361328bf8f2b42730d7052dab032b892a87078c23d2384c224011bb29be0de91c1c8ae98bf76bbbb1fdad6513508013f9df600d
416	1	170	\\xad9b3892c75b0363b2d75fa51c0b305fe77a7da1ccb8199592a9fcfc863bce2484158ccffe4f90d4cb8098c03b3b675db8babb0e9b0244f556b9620d0772200b
417	1	100	\\x2321af780a077de116bdccd04ca1303434d7aa59e4f9f52cae78843060d786707edbb7d9845fe78409c57ba11060d3092c7930d2d1b5322219b844a4eed9c908
418	1	256	\\x40049d77982614cf7220a540ac5bf89ab8e75192b24b91d1c319961e905be3dde6d22f40bc08fbd8d2e7d3018a250b4648f6055de7a92225b59b4c444bdf840e
419	1	359	\\x4ed87c161d79512de0273eec442c1fab7a9b088dbc8300ad1e96d54a4345634e0140416c91813e90dff022141d592d2f135a24d86d1a9a1f383ef53b27c33e07
420	1	87	\\x0eb576a5a947cf5c3a701f1d2374da558766b41303100946a8257099869793fc4fedf205292c265cecfa4ade75fed3277a9a07e5cf2bb93feba32d4531ba460b
421	1	75	\\x71dc5341510ede3078308ba4efd406ef10d21e15857b4be4184b14491ddf392df26b27501c5aeeded6a5b5888285f29670f933415732e2599c1c0b07f796c408
422	1	140	\\xbf77f5835ec83004efe8e666bc5a5dcb8ed361c876e638ea3cacdba1d1b4cbc99d0ea39fd6658bda08c90b13d9f0750863c5257940a0513b62c7cd6e661c8a09
423	1	137	\\x837416745181786e470b1871f6b5ab5e04f80a1b5d4187537af87e6a78342d853563c4d3cefe866a5c5f0d51a05d76b68669287e932473d6fd90dba5181c6102
424	1	85	\\x633047bf4d7258a47743c013c23106a91c2c20f2905e758ce99ed7462dc89d32bf1e349a17b5d3b163fd35a7b7de7941b4d459c8c8808284325a10e1a1cf4c02
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
\\xcb7ad24538f33a8856df81c73588325a6f4cf233320a7cfeb4d70130953c7eb1	1650014509000000	1657272109000000	1659691309000000	\\x76065cc662a91208ef11d575ea56ccec98001b70b51b1b1d7f6dab78a9b15ef6	\\xf9448a76182e24366dd22854b3878ce425ba67eaa44f1f727c72a80eb8dc7851622e7127be1e42e03dbd6895e7b10631aa97855a652999446cb9cfa18ced770e
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\xcb7ad24538f33a8856df81c73588325a6f4cf233320a7cfeb4d70130953c7eb1	http://localhost:8081/
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
1	\\x3fc8c1932382113ab72e8262f3c6a662a258566ec927b43c529fb6262edb22a0	TESTKUDOS Auditor	http://localhost:8083/	t	1650014515000000
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
1	pbkdf2_sha256$260000$Ea1Qb3q8j0eaEytT2VPTv4$hrKH5HSQH8sgfaN0OoDXad3Gee2CEi+JCedSuy2IBhY=	\N	f	Bank				f	t	2022-04-15 11:21:50.338221+02
3	pbkdf2_sha256$260000$g5WxNS2pi8WgdQ290NGfju$dQRaZq2IwkI0L/xxSJwxGWTdChrcnwAhWJ+ifki+K0A=	\N	f	blog				f	t	2022-04-15 11:21:50.52303+02
4	pbkdf2_sha256$260000$9ouBUBd2xFEhz57xZIaOGf$Wn3uKUkU8VkoEWPVPjFLrpK5I0Scc/h26cEEYmEiiuE=	\N	f	Tor				f	t	2022-04-15 11:21:50.617625+02
5	pbkdf2_sha256$260000$kaffGgy9Hx6s7aNoPvdLxF$+/fEj3PFmVc6hOcOeFhnhrbkeK6T+hbO4S7QALvFKLQ=	\N	f	GNUnet				f	t	2022-04-15 11:21:50.708107+02
6	pbkdf2_sha256$260000$ArN0Ru9xTGyRnoWj9dLjNF$F+sqwp4ERiCDFwmGNIUdRNxPjIhWNpBsJz0Pwr+DaoI=	\N	f	Taler				f	t	2022-04-15 11:21:50.798913+02
7	pbkdf2_sha256$260000$TjlEUlceeq2QiTKDGkGuQZ$jIKPkxZLsH300E75kD2qwWpLGes4TOdRv91UcABx8W0=	\N	f	FSF				f	t	2022-04-15 11:21:50.891866+02
8	pbkdf2_sha256$260000$LcYEbyoVkgJOM0vWxmlh4S$bcioMJWccdzulKsKvod2i46vIKt85BzybI8br6DlnZw=	\N	f	Tutorial				f	t	2022-04-15 11:21:50.983872+02
9	pbkdf2_sha256$260000$3Uz6sVwkumVIuQMTEOr37m$xG8XHaohi93X7ViicMgM9pnwGATCqV+tpHbz1jlEHDg=	\N	f	Survey				f	t	2022-04-15 11:21:51.072734+02
10	pbkdf2_sha256$260000$CODIw3d2VWc68mH8prytSN$0Qht5X8vuft4zsc09GHs64NrX+LjuBjrahZXsJBs+So=	\N	f	42				f	t	2022-04-15 11:21:51.52351+02
11	pbkdf2_sha256$260000$bwKVwuYv3vP9o1Dlc7nnFI$LvU0pfdR4axUhr/2t7sT5BJQlmybUdTD+RBB+yLIC38=	\N	f	43				f	t	2022-04-15 11:21:51.966716+02
2	pbkdf2_sha256$260000$y7FsEiY4uF5omhoFAtW6BJ$2kIj56aCyRchKWb83k5mcB0ruXmts/7CI7x0HtJvkkc=	\N	f	Exchange				f	t	2022-04-15 11:21:50.430608+02
12	pbkdf2_sha256$260000$MZkYPYTjH0feOZ0VryKZCG$P8WFGA77J7vFZaZRjLpCExRo7wwHOfWWSFbm/zfNCsY=	\N	f	testuser-kk2uckk6				f	t	2022-04-15 11:21:58.136861+02
13	pbkdf2_sha256$260000$DOlnPgeDbfqVX4e8tmxPOd$NYdAgnH3q29QywYuOXkFDBqEBIuoIWVwHWTF2S2iZn4=	\N	f	testuser-hkqg1f33				f	t	2022-04-15 11:22:08.688763+02
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
1	\\x00e4d751db2d416d444b2705d7ffc57557402ec7d29d5e685e44c37b7593ae9cb77fa5ec737bdc7bbe959f9e619048b97d31b2f63b8721b78bc2e38142fca536	1	0	\\x000000010000000000800003a371231106ebe1ac0c3e08ce3b046a57e4341b96568f9eb06f5f1f027b7845b7060efd4ad10ad914e3d2b342957bf8c74ae3e9cfdb6530e33366ae159cec0db0f78e42e7fbdd75e0b8fc25e216cf6398505d93c4f1aec2f42c2cd998e2ce9688432eb9b28b5f1250bd822953a8190c8e81c10fa9c5f93cb785505329ab8f1167010001	\\xdea481fa7765e2ee0a3a2eb60b61d8837ef7e5bd28a5d74c912c022fc09bc945d1a2f0471c75a225af25b85de7c702adaaa4d47a8bfabbf4cbd8a9cf7586110e	1663313509000000	1663918309000000	1726990309000000	1821598309000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
2	\\x00bcf2f4aac65b9f4ea67bd8a123fe65d8405fffd92fa1c1884817f860354c9651623a6261e6fa85ed0c4a62fce93d3f07487f4d33085f224ad4909bb60bd229	1	0	\\x000000010000000000800003aafcdaa404052d9f25ec3cad406acb58ca74244b572500f2bb4d91ee4222373f5cac6f5990ccc88455588466fe66a6fe038677c16495dd00740378fcb6615c1745c045d34af860d26b9a4f4145b165c45b7a0b3e9011e2a268d96060eb4be8d2f130d6581cf23c6c2b86600c5675d3ab03a2b055c0259694879767104da76f07010001	\\x7eef2fa0caae1a1efc1c5c7213e1cbab9f4914e1385daee36089296759f9ebee271db8a8e95f2a44d83ac979787aa8a55884e67e4e353ca4e22dfb4e412dbb01	1652432509000000	1653037309000000	1716109309000000	1810717309000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
3	\\x01a027bff4188b6280bd74a69c65ef5bc820c121ba8afd362b0bd0e8e529c0d4c1c5573f95a5d7ff64cf435b616f656b06dcfb8e882ada5b3385d1083d279177	1	0	\\x000000010000000000800003a2a97b1cf5060699ea8ac555164b79bc953ca7254f59e485d14394c74de84d089475645a596d8ac8afaf2f033a74340f20c27d0ed790978c8bc9e8555b26f02d6e036f9389d6fdacc428c77aba7504098f78596245866290b6b78c80c018b7cde4f48a900801f907762dca2f8d10e6535536d3f754e50582354a8d2875194ba1010001	\\xb4092d91f06de26b319ba2f4773192c754bc4f8cb7ab3c776a039bebfaee168bba5da4ccfee1c26df87af54c85cc021bd87de81645c7a5a5b365230b0e368a00	1671776509000000	1672381309000000	1735453309000000	1830061309000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
4	\\x0364f1b7d08637720f2dc1c137f9b867b4815d8ca87de4db153dd4e63afc8a61cba1e628b205c3a46c5492e440f15b7b6d29a457a61be6f3ab166489402382f8	1	0	\\x000000010000000000800003c5a079fd84d15eb9d4c9c9281b449906f35a1b3796cd2a851021d139e01a602da685d92d20df88f2e512762bd9c2ee2a155b9eea02c5b970406f37d8cc1cb72c53dd16a131fc0f7953702737d2b60719265a013fbd6093d4a9c4e805008d248e947ce43660da9658a7120a01361bc070883f6af02b535f727b552cbaf36392f9010001	\\xb152ffc5b7756f1db53c4f9e3cfd9bd686c787644c8458734b95345e8fe0023b59a7f512b916a8f2563065b127149e3f4af7f27e7a22c1c36d97144c56db610e	1679635009000000	1680239809000000	1743311809000000	1837919809000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
5	\\x058067e26a7df4b3d156a72f0877513afd968e918d3938dd1f629329fca7fc9ed9c9c940c08aebfdc04766a22d4991aaf625f5fb3432818f9e548a7c2e38221c	1	0	\\x000000010000000000800003c64f00285dfc0f7477f6f50bbaa4ce3d6eca92477dbde7ddc58be39c3d9ab9ee6a53b19ae28774d767364fdf6c310a646c7a525f2e0aef43ff044c36cec2d7f951aa2220276a6e9d528b3c3ad1b4f5f307ad08a7b2a63e3bd6af6911bdd2d1f3aa0b8e3d254ed40c395a3b2242511f08fbee4d97c73609a54d747080cf946bc1010001	\\x443d67534fdb8cbce2b598ffcd9b2bbad5286aa538f65c66cddf4306f7579f43916259472687373b09c82d050a1b845b0e7d71e009d45688fc4a1842b6c0d006	1678426009000000	1679030809000000	1742102809000000	1836710809000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
6	\\x064888651862456c852acbe687354b091336838b32a2ac1f449a80c6e7a0ead3cc08ba46b8dbe0c537c9f033091e6a5c3adc7814597d2b39862ddf0a3826faae	1	0	\\x000000010000000000800003b7fcfac4ddd968c000831ab0cf3f5942d5adac100635675ad38a64c8e5f53f571e8bbb60093776cec0c8133fc13629e932bdd2f37be6cf17d659784a6698b75cb0a4631e71addc52d876c4b939f9a6ce62a16e3133156622bac53e44f11337d5fb0f23c7b4d94182d238d4f629f78be6fddb6ce2ef68b422cbf602dca5d67f29010001	\\xc3557b2497c551112365f820380a95f4901cc0427a3275123716610508d043bebb31dd2c9e45c68a5cc825ddfc51b2bf6dc3ef7335af88bd19fdb4db86c07508	1669963009000000	1670567809000000	1733639809000000	1828247809000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
7	\\x0900dee1194d7ac11610cd8ccdece2ccb703af5dddb83c321b73045874b8f4440ba11450560c125c31a45680a6f79677685be3e1b8b957ae41a46a7c65afad85	1	0	\\x000000010000000000800003db69b6d386655f890311f4154b50079933d3b4edfe3b55440852e727fd5ce5da43f72f3ba047b5e8b7f59b106b765beab22d6cf16c2ea41b3021a10da11614ff7a8e08f6c33268b4a90472b6be3826b42bb1eabe6afc74147afec5c4a583f95e79bcc90ef2c1dddac01d2fda1cdb592f257cf2bc3ed50b12cc96b0ab4347e259010001	\\xac2cd87da1b02b4dbbb538d8ea999ebd49628914f63fa42d51c9ddc83990351dbc3a64548b7aac9a60a2b20510e78294103fb6643e20f2c3b79edfa2e8b8ea01	1662709009000000	1663313809000000	1726385809000000	1820993809000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
8	\\x0a2cd3d03b580f732f2a1f4fe8b84425df207e73d98bf780382590545462c75d55ad775e90cde7cf5d32fb22fcad9132392e1ac41dafeae7f4c54062616d5859	1	0	\\x000000010000000000800003de532d480b7fe63c15d38ded31ab908813601d829460ce921b63483d5a51ee80ccb33317385602f7174132e2771b995c45f0d26d52ef6fff6670708e30fc81740e0789f4580d95ebd9f1607094ee2b5f9be1b9a6b469dee2293884421cd0fa1e0c5a013b3c05fd12338c2005f2a5fb0f4c248454b77772836b75a26ad8b71bb9010001	\\xfdcf4aa97fca3e9e2495cc3dbfcef258e1a3a2700010c0f7bb4a46b2039f1420a835835393a54a2da9c7cd17dd2d1abe0f8039521a58e467561225fd2daba10e	1671776509000000	1672381309000000	1735453309000000	1830061309000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
9	\\x0bb8a16f92db0b1381d1972ab5edfc5e900d0e3be9bb6a542f3ab354b9c0e40a810ae218e9d5385e0df8dcb8a5ced0814f7ca9f1f952d4e1b8232b24453eec74	1	0	\\x000000010000000000800003cf4bbc29cf39becc043a8739a3ac502817463f2935619869a2d297b9dd1ac548e19480b77a42e13af4e704f39d0bc35f0aeea2453c87f200d1dfb906cb41dfc7e4abd06bbe639b6e0589e19f608087b7a9ec3368debe5f1754dae565c965a767df0ead692e31fe3bb55a093285233c90951cdd5fe5428e4be3319a22b280c0cd010001	\\xf001d041187f957c8f7b3304077178caa6d41dd60115bd4a4c09a3aef4202102cab2d07f8ed9b306bd05dcbb817b60421a43a1bbbf5c6a80f337bca98be1ea0c	1673590009000000	1674194809000000	1737266809000000	1831874809000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
10	\\x0cd471d804d938e1c84340697bd7bf51ebe2b5acb9919ac67bd4efe8a970415d8efa2e00f6967f1128c13cf4093f1e157b3c504f4e8c7c9ba24de8c64f3d611b	1	0	\\x000000010000000000800003ed4a400a43b688ed561f2d2fd22a4b8c597b003201a69def0344c162490391ce95c8a15df2f8a03adf533f7c01404ba6e8780be7ac246ccabd183b2c140cd66b7bae2ae5b5fbcc4edcb528311ab2d1c13ca7bccbfd38d127b26d7651f6658999efdb1cdbb699765cc3a7663b4a885301251b71a3aa4625c3929274fc8d99c729010001	\\x889f418c29bef1f5f6121c6adec3a9f94f57243f0cdb30e877959b4d38538e67c2b5d516667e3b6e7d60544d51064a2d877b89b47a1526e038b6752916e3ad0f	1677821509000000	1678426309000000	1741498309000000	1836106309000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
11	\\x0c18da7b0af88e49ad0c57928cf3330388652c066c2017b2ff0cfd685022e7d76980f38d259d54351cc147af970c68f5a22aa1efee7c0de784ab906192d357ae	1	0	\\x000000010000000000800003c87aa601fb32b853b7e6133b291d1ca4a38c2972f4b8a9f4d9a349a65e8f3cb6975af564baa7a9429c65e1324497e791e0a0342d894b20509622a3fd354ae6deec1fa4378a998b2bbad56fd5375b7edbe6004aad59993fbc5c1c9d5ae6115379690d85a07616d159ac2e5982c33303e9dcd33c3ac2a0e6bc160e214518fd669d010001	\\xc376872fd69a06d90e6b7d03dae5da02eb0aebd3869db78b4a2839b22e5edadd5e642d53a045538522419c96bbfe34582aa1df92a0173d7a911f0641fbf16d01	1668754009000000	1669358809000000	1732430809000000	1827038809000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
12	\\x0d28c1d0cb69f8a670e326a981f380ddbd5e9a3722d7f42638743a6e5bba9e6b2b8de0d8df9b5cf86a6e0d8ab5246ebbdec86ca42eb309031ab37dd8953f324c	1	0	\\x0000000100000000008000039f1992e6180dadd1c4a8d9350f997f4cd3eb669b259edc54ce553e8b89c81b36a81a64e6dc958a7393271b68cb6dba68b986bb1b11d2a397fceef51e48fb15b17cea3e6f078540526da4c4592e8d564bbf41f192ee7a5e9f10e24c890546aec1af677f2431e57f7ccc6be59120f359c520e91d953fc1e3ab6cad76ebebb20465010001	\\x7aafb4170c5c89f2eea728357fb8e0accce303309e3a753419c7cb39af40471020fbb520997c9626d4d71613c0fae2a532e2a2f374414ca1bc614f93a3eadb0e	1662104509000000	1662709309000000	1725781309000000	1820389309000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
13	\\x0d4ca226a53bd0e9a3f70574878f13d53617e09c3b6e1a8d0724b8dd00083ac4a2fe05ad08a1c26ef4a1cbde2eda1fb6c6941c2b5a91c6fdedb38f2e487af4cc	1	0	\\x0000000100000000008000039d0248122fe651b65547295daf1115613125b4c11d484a8ea5a3f641761085dce1838dc279de0065708236be15ec1451dbe64874a3079916458e582becaae67d332a767d81776c140f8f6f83cb2f32bc863832939a641cd4ae033c89d09a4540cc1dcf961c5340bb719f9d00ce02da1ee2cb5c8eddb93eeebc97a3c9733ef2cb010001	\\xdfb4ee21416978fafb90553501bc49a2ac20e65c04c1d28d8f9723c67153c02366e2c184bd87877824810c8f7ec1b6ef3e46fb204d7549f5dcebd50be278620c	1653641509000000	1654246309000000	1717318309000000	1811926309000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
14	\\x0d2c77c5be1a862bc4e379b41893a1cb9a4fae99ade68ae6a6cb137f11955fd85d0cf77d7887ad186c85122896d8bfc2ddbad0cae4532e0351806db3c638187e	1	0	\\x000000010000000000800003b6a9780434f897fc5bd54f4b3c888af1d5e84185fce2410287ce1df26504e0328338842ae40d85b4b9d78150bd4b150d34c412b91681d3f54d99042e1fd71864ef000dfa3164e7df1987af2ea7ddf70694c990aac8359365f6244dfcf5f4d87af6998d8160511bc96a97c26d09292bc1ae2abc6a01bf55930284d7579dbc31c1010001	\\x2b3a6c7860d5ca148bd83b5b492f88c3f848a5aaf43629c28ea118c75a3f243babe097246c2c05a07e43232e14a0031ebe10e231e823cb9f29f9194fc0fe9603	1669963009000000	1670567809000000	1733639809000000	1828247809000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
15	\\x0e48f1d3571b2b9b7729cd83135875e7f1562d8c3255ecd6941dc398a25c26b8f93b830e698ecf8a4bc4136bc8d747f8ed6ce8299e0bf0253c50e9ec2e48ac60	1	0	\\x000000010000000000800003c9b35672bc3d52447e9ad264d1822c13f384099e5c5f1ae6aa954f149f4ef00b7b8e8275bdb380e50359f360695f6fa48613ef027eab1fe4d89ffd7a86c6758484b5c7e01bd701f20af897c6a4cad4bc8e05d4fa063b12e75b3e7df115981b4cd2fb5f3fbd9dfb7685036d5987fd1283f029e9dad4c4112d7c0123d9f7c337f9010001	\\x043ef52c8b1b87c61e8c2baf2f0a710450cf1bb7c772d5afe8cd3ac73b52ae5c21591a4c6fc3276c1e3eb2539c3384ed63028fd6951a8c65625fb3564144f303	1667545009000000	1668149809000000	1731221809000000	1825829809000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
16	\\x0f88f563f2b2f4464df6fbc97b57042ccb56a0192e467435e777b9f5464724908356119b09e13024bf4fa1577bf99672e2476f76e0ee4014063d7e3d778ec0e1	1	0	\\x000000010000000000800003a7b02c8dcc1dc932c15a226e6149f203b18930662bc64bb2548323735e4e703ae801dfe1b3b2550077e8587bfde961eea6658c3791b76b3bb81b4436e0fc007446cd81284a54f66b1b288848d16ee51af74fbe837805e32e9d6da9b90a865b1cdc0471788b5976556e7dfc09962f438b7bd127f91c1e2437a3cfce58be329407010001	\\x7c39be4c291aeb91f07bcd9ece1d68fac188c6e221e7beb4b9fe1a11bbcd6da0c554057eb0c274ab77eca8713cfdf714c0239df45ed00606598ed41f765b7c0b	1670567509000000	1671172309000000	1734244309000000	1828852309000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
17	\\x11343c7160a9936e7e12c0aaf5faa78566d348a15d2760ecd35dab21087746fb0f319f7fdd93efae23c599187f3f103c944ee6a3c5df012c98a8c956f1b8c24f	1	0	\\x000000010000000000800003d3d0819ca0db97d8afbcdd0cb2c617baf2576f46bcbbd10b2c8bd4857cec3e15dbf482c1be684e46e71229c3d47aa1e38048802510346770f04eac9923bc31b938f1a3b4aba0b21228a2f9aa8391e8bf393a849cfdf88675e11055795d7b00aa1bf2b83fd8724ed454fb3b9892a3f9e8168541b4b21fddf060f2ed1c1739f031010001	\\xcf1b6c3d4e7e46fa51140821cda823bfb451c2d14914663818f46dd1b29d7da0fce2f0bc5b5dc6d1c80aeaf9860661f976b55e09767c4e449aedeed58cb13c0c	1659686509000000	1660291309000000	1723363309000000	1817971309000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
18	\\x112ce0066ae95756c3796015d0cf5f0a8eb013f15e504cfaeafb0ba093867861a066983de0db3f8bbac2504c0e18c70c4359b5b5cd035355ed65926d150c1990	1	0	\\x000000010000000000800003c74894011edae91d755e44de148637f5515248a644dec97f87e56e5c4b2b3bd75064d360ab618bc9bbc5793bbbbef8b446e8b390958fc1bd62a61955e084eb1d5e38afece9b3934cb907344d4c878eb6add81644cc3cf196b5aca4ce121a676fb644ebfec70616116aaebe7048e39546f6d4a7b6e7f6a7db21b7abe5e80a3a31010001	\\x0f35b0d16ed6514e8a57c63decf50377bdf279f42dda5e2c4ed616bd9c4e08d51140aca62a2c06e47f255dffa7482752dbb42ca9de2e67c6201ecde30a432402	1654850509000000	1655455309000000	1718527309000000	1813135309000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
19	\\x136cbae42ef5dd2430b47ae98d0037656c7e6580c40d95a947e7ce57ec386c2617ce392be7e1cd562c63903dedf346a5818dfeea92cb5e0b71517e725478102b	1	0	\\x000000010000000000800003c67d474e0d8a0942c88e0e39d21a542f5ae7c22a8d95a031cf96e783153d00cdc23084cb40972ab230a8acdbfbbac96f983d9eb790efed1c1d85ebf69702cabf8070ee1da7fb3288fe6c9a62afbb4584c29c3f8c484d982460a4da422ed40e2166b4a8961edd99402ed006c658ed50e67117dc3f09ed314ad8894269998d6ea9010001	\\x9ae487fff0dd679188541eb49036c9449fc8cca53d346efabe1909be75d0943b7acf5ddd1b842b49b1e07e065623da421a6f82c58e18008b1664f74d79ccaa08	1675403509000000	1676008309000000	1739080309000000	1833688309000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
20	\\x163c4ca8465a7a2597c34f89916de57c3b60cb5dcb7c629ad65a94e29d4cb6cc6245afb9285907a79f1e43fb5d9e0c7c5a873f2614a19918e97956606453a4cc	1	0	\\x000000010000000000800003e7a7c72176ee6b6c2abcd0bc70f5695c52e96f5df7b40392912c974050e3b4a1d787dc77c6db09b031f06fc78b0e418b129f04808976d8e63ec45cf178ad26923f17cf2adb646016f603d265d79ca55e3acbaca66c484305fe0537200a272a9405fb156120280e07e9bde6209610fad7017c2787dd5c565a708fd4926cc3ad21010001	\\xb4ddf376cb7ace54481c4ccaa0168171b3694e846cb08ea096362732a7ef79fc717cba05b3051eaa24648b272a4e6c0c4f4e42896100aea807c323055063a00b	1653641509000000	1654246309000000	1717318309000000	1811926309000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
21	\\x246cb0fbcde5451c1d12e9591532ba2944f9eb00dc85a3a820f94c954051579f544f9bb670a480976a60f77e05791c4b1de404a8d566d6925a68a4b99ceec33b	1	0	\\x000000010000000000800003c43cf629b29da32a71b0ffee4d12e7d29950b4a82f0bbd298af09a8fc0d84af8a3f6ff634f4fce17be25ac7153170ec29bfd6ad45a7773426039e737de5af78f86eff2b752ff5196dd658b78194d1c9888c081fcdd4242444208eb04b42e55bda2121e7e27fa3e51f4379fd5de1e37e110debd04839d8ed38174b77dbfb535c9010001	\\xf432a5d5a3056d1c17b755de73d536b87f8c96c33fddf4b404ca6fe67dfabe49a9db775aff5bea68ddf69e34b1d8fc8daacf6803fc0cbc97e7f2686916d82e0d	1677821509000000	1678426309000000	1741498309000000	1836106309000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
22	\\x25bc9de520226eb46ccc30833c82c9aec711ffa90a82c398416fe85327b49aa020514c7eafe9455dc97cde21a7bb36116fdbb0ad685e950fdd21c9b5dbdb396f	1	0	\\x000000010000000000800003ca82f3013aa77c7037bb0c0ac999df120fd3aad6328bdea794e34f3d3892bfa49769dc411b89051cf28b6cfbc724b0d70c990712b6f768fa77f9295dba117451449e96bc927aad7e0cb427a317d2f335ed22f41a2c94bbaa41ffc8569825a1cf1470e797bfd5ee94420b5ca4310d494ca5959339a697c85e80fc3b5054c09933010001	\\x8246920cfa9e1ee4e9caa36386b93d827a8502b7eed11e3c1dc14db801bfb6b09a67b8f397858b6a45e55424f996fc52139878290ecd35f2b091f5ef74014f01	1678426009000000	1679030809000000	1742102809000000	1836710809000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
23	\\x25e8da2d8ff17fa19a306d73463ef65ff2e9eb34187a88a064ce1d75acee1807f57dde8fc671c1ccb6d9ce75cf8fba097b84c0a5d94e010abc7a486cd57eb209	1	0	\\x000000010000000000800003bbde008d18dac564c9802ffb1959d22c4407a9ad94508b8ae433775b5d13d667e115b0133d536d632ddde216fa1aff6b20e5831d64c36552f367e1b28b1cf795cd39000811442b03b8a5310d74a2181d9ac1aaa0241bb74da2c7094f973837f11517a40d11fb543b1a04cdee935f9e7fb57e0f331ea5ba3e057907a759d91a6f010001	\\xbc407e73c609ca9964d9ca7a5e8ece3381f809df3691e56288bdd735b03920880581c78ec809a3b0450a594fc3ab82b78e276bb39cc1ba40d610c06c3499a007	1654850509000000	1655455309000000	1718527309000000	1813135309000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
24	\\x266ca880713b1f6961dea852dcfd73c3316a9c93fe31f1d9e06a23961714655f3753d1de7c52aa4a281ee47c4fe4499546e8bb641c78a230fae8bb63f15d0cd6	1	0	\\x000000010000000000800003cc2f96d9377fa6f3de228fb86a67dcd0fdc59a1ff3f363b39b9f9fb95e1f301ee614bb254254755368cb1eaf26d0ed3511ddf7676cb910d9050dce985e9272ffda70b0ebbaac17d824021263e303b7a06ab35e14944d6e44efe4b3a1c05283e0c167aaf11f302c062ee0ee120d76e9487b47409ac9afef23c6ee1ce052425673010001	\\x1b6b410fa7df7cbaa812bc634cfe05a68f868de124f3d05b1056fe1659b4eb711a81f4c5ea570e12c7326ad5e438b2677d9b066d2dfc4185019c3ed37c1cd203	1671776509000000	1672381309000000	1735453309000000	1830061309000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
25	\\x2970b8c8ca4fc7bd8de470293c4e011971076dc4815a3966348fc9ac7577bd681e4d0943a6610c16410a286d565228c3daea47f58f859124ff10d0930baffe62	1	0	\\x000000010000000000800003ce0cba58844fe543ff5d542babda616ed8d6af90db671cee1973e1a354e8af5ee96e69c59c0986cf791de956dd1a1eb0d0b32f694a48169eda2de179a84b3a4146964690ac3b1b605ff16853bd363dd4c8b80357bb94fcbe6529aae0a9c3c399b2032e25a30f291e087dfe0bc06a79eeae8b438f5c49287b7433cb5d3c96d901010001	\\xe72bb4bff6878dd4eb8d5f4a81f8a1329ce0f3f307fbbc74c71ff75ec0a6aa44fd5f0049f6b762661a56a522d78f3765cffcd2e1f0d2cdf8bec17c516c707204	1679030509000000	1679635309000000	1742707309000000	1837315309000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
26	\\x2938295b2eccd8b18a80c62581e2abfb283087fbcb08d7053feea23a9b417df90705d3a5a5735fdf240eab560934792f63f8c71242400cf5a689418f970a3720	1	0	\\x000000010000000000800003d160417807e8b87bcfa9b04062e15aefbe0b994693198cefd671b8653c30bd6b09c8fd53bb925e207a783e5005952ad9236e5fa64a81cd402fa7f2214d70d549111ec095dc36f168b954fb59b6ca22032d8293482a17410bcbf31749a10968f8d759ebbce4baac930cb58b5729c7ebd2fd4f73d7deff25b391447c1f2d76883f010001	\\x608a0682940b7060cbb28d014dfc480d1292798e299fb347c5a274ec934ae3a963d7154c530acc76b7cbce411d2fd09428c356286206ad82c149f1237c1fc20d	1676612509000000	1677217309000000	1740289309000000	1834897309000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
27	\\x2a600975de78cae3892f36f7f92247a33edc673012d126f63ba0bf4334faa6632f69da08efab79b591eb1a0e73938e2fcd7f1e2021652076ea2ffb65f40bfa75	1	0	\\x000000010000000000800003b332e67307cb343c196d56948a5198f2cbc183fc2da56dc523ed91293673f13873d1800596187f572084684c175148861e7dbc38a999cd1936a136d67dd3bbcf3b959e7e312f1e7edb5ba8a8040e5bdc17a42cf1605fbf14ff32a25c492b158f93406d54ae192bd4fd0c53df3cefb5c2bc9ac540d948df838f40366d84890503010001	\\x841d53811132dc11882fdd5902e27262eecfc4e429f1cb38b032d6f100a566e7fde91a8b8133e51537a214e4a21bcff6f87f0b5a69fe8aac33a5082f88aeca00	1651828009000000	1652432809000000	1715504809000000	1810112809000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
28	\\x2ee04eb6323c64f29fb318d63f82a4e8fc602c7ab77589f3133a19e417858f92e56d347480f2c883f0d6c132accc71971286898c2ad7bc4992fcaae3a0b72912	1	0	\\x000000010000000000800003c6d4d3c3201221bf28535109765c115c8c90669e3d8043f97fde08b7b944ad0927d7c1f20aa4ebe7f2ee879a8e9bdb066c179f30b5e873c1c313b8c13131ffe7e268ba40ba2bf00da4f38ece7c1ab0da8bb277e3eb9b48acc78956f6e857d2c415a429a5e04ed10b1e2e75293323c1c7beee464e71245ea021abaad057056cdd010001	\\x3b47c2cca302fee2f2022300881369b76f985e7dac6113fab053290ffe9380beb895527220a2555f5154817362ae5043ce0433ef62a97c3c0f9079688da87506	1672985509000000	1673590309000000	1736662309000000	1831270309000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
29	\\x31249ed95620fc9640869b26087c3ad63391ea0dc5b1e75a3377940be3c096a9e4a27b422bd7b64c292682b180925d15ca84b8c77af6e09305da2e97f5cf9a20	1	0	\\x000000010000000000800003d377c5077768481976575e6031308735e8b81b74220fda141c189fa23d62b94974ff7cd17662a40f8cf8cb371916eea4fe2ea3dc6ccd5ea35950f419b967f5f8bd516e6a7501ba19ce8b0982a738644dee77337f003f8d7fa7f19bbb2591f6eb77d7326170dd9099ad7e3b43b273e385a2f3d4242732de81568d48029169b62b010001	\\xa219a208e68b83ea170108eb10b551bc5b59f2e1807af2d3a53705564f8b93b670d5bf9c1e7b9219305a00b19e0f3c299ebc42821c21ef2de496bc2feee5e306	1669358509000000	1669963309000000	1733035309000000	1827643309000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
30	\\x33c82cadfbf2feab694a8fb50487a260a8f3a22456cec88f6c5cee620fd240734845ee8cc859cc97407c97f80043776c77cf96d059bcb7da60632c3226d403c3	1	0	\\x000000010000000000800003c26406e391f241d573b7eb541ee4b23001c18bae2b24debf503d984c1243431b5ae1569a6a9ad6a48ad13a78b7a19387c1db363b88b9c48b61687279719ea89e7c5479ac68e9b7dc7d76d8a1464120e5c69371618dafddc0e145f4fe167f1db5656bf2a90677990bbe415b3418c5489859b6eac2a388b46cb3ee3b8f0923f909010001	\\x20de6327f4b293e94c91db41a2ee2c29b9f6b8b48b7842987e84f3424883568217bb7717d14606e23d07ae49011086619698ca495d2603ba1b5b7010370f410f	1665731509000000	1666336309000000	1729408309000000	1824016309000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
31	\\x37986c2440dd7a42e24425ca08b08bb49209724a803ceba69a979d54ee8447088750a9f895f7a05f401d229fbb4dbda4dcfe034a2942bab028681adf5eab2722	1	0	\\x000000010000000000800003d04d29b94aa6411bbf3ccd1b5dc0bf24d9bf191ba0fa40ad3e09ad7a8b5cffb51febd693b9f796da5aee7d771bb0a7d1bcf0e8e4b57a72f19cfe2dedf01122015eb7f0d3f8326c988966e6196d64b8e5c365cfcdddf624afa32e72e0575c3377c231a65de5309cccfe96b57c448bef7b1266b852c583855dc5512f9f7650f11d010001	\\x6adefc7b4714b611803b272c472949ec85aadc81c8215e3d7d6d6567bfd2b5d6c33d931735556f7b58ff2405c308c43eaf35cd83242357f36863308d9d2b7405	1668754009000000	1669358809000000	1732430809000000	1827038809000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
32	\\x38a8d49625d69bc36f96deb67465d2b7f7d6f96680d349752fdc51cdd7cf678e3d404e0e36d5d54321d748b74c9b5738c4478d1a797448af60040de08d290910	1	0	\\x000000010000000000800003b43ff5e0091417dbb6b75d6484f42f596e11be110076725a79c6c3aac86591d0fb07205081279a0dd92a822d3d7f899752917a7f587a7002e3b275354b7e95512b9ca014603423e03af688702fc7be7759528bb127b455103fff3f44702530c5a6211867ff3f54196f185f1c2053df3cd02cb0bc7a2f738194cb02b96090ad4f010001	\\x5a37e3f7de0212db93a09c0691a3c4b2440c693093ba5b316620756714af99b7ba08c872803c3b0fdf98b720d2f7bff1e5f52ab1d5e35b6656e7ac261023cd0e	1653037009000000	1653641809000000	1716713809000000	1811321809000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
33	\\x3cb4cd8dc72744a80f2a14b4233ee6c52b5b348a2790b85fcfc3a05cac56dc704c80165ec79ac304b202127dc814102362f69ac2323548dd1bc814d1e53736c0	1	0	\\x000000010000000000800003eeae32fecff4a5f4d12744f91537524b57a24790bd6cfa2ff90466cce242efe156beeb3ebdba33b15fafd727bc32636b1b5fc95fd8a6db01f7ab48972601dee27310ae2d49b834701d97d2badfd75142d64005eac5d0243bd515a6146794ed7628e0d866139afc6a4ddcb15d1cbb171795c0bfe3e857833157b4f16291835169010001	\\x4f5c2fd70590daeed0d3826edfdbf7299df90007c572feb56aa83cc7a2b4d0173fc20b94a4b40bd3b1ea17405258a6f5860979a162639f2aefd026986feb5a08	1663918009000000	1664522809000000	1727594809000000	1822202809000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
34	\\x3f14d71c8cc3d0e3eb1a35cf158e7487096f20c76eb12a98613d4062c301dd03570127e467d7e01304fd37a87264274538c1a84fde8070a3f8bb65045c6813a7	1	0	\\x000000010000000000800003c2a4585604a51559edc4aa4941ba95b68ff3ce18f1236b109fbb8fc950bd23c5a350d4fd7ee7dadd5fbcf25c13fac5580dc386d39a3836b80fd50d646ae883002282f220eb852953f974e1028ffd38eb9c64cf0472945bf029aeab8c52ac0139fc0e72e629518cd5c398d8343f95651d2929dda8cf6d09c504aab8558c66f69f010001	\\x7cf21402fc1d0037460bca9281fb351a05ee8c5cf5e64e4835d557e293ae4587df594d4173773c80ed674a6c724e25b30e760e78676a93ad229fcba39d476501	1669963009000000	1670567809000000	1733639809000000	1828247809000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
35	\\x3fa0891dc0761b2d19c2cefd15ca7b0e265be3086cf0d1c8f5dee5baeb3175cbe7db1b77fa4bb7f579fd56715e53acb0917dde59e04ce5ec4870597ce25efdb9	1	0	\\x000000010000000000800003b5e4b7bf9d16261e5671c4a44833031728e74234acf4e60414c45d4ba13752f438c29b6ed52e9d77e1d0f66726dd4338b056746e9eb869f69c2ee55d87da0d58490f6d0258b67b7d54ed828386ce8b1f6046b350455539924b1e4caad111041986b172d0819aad682d69aa5c83f004950579e46e250a53c0bf17eeff96819035010001	\\x7ae5db5a1cf522801f5c5872edef4758fe77f5be362a64ef1bf44f7d23d0d48c658d6aec53383ac8a45387b2ab714fdb462e3a638ca2968a49bc152e60083f01	1665127009000000	1665731809000000	1728803809000000	1823411809000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
36	\\x41203cd97770620bc1880589c5269f0cfa81d0d7e5015aece03b12113c83f9eae7960330633e8919c6bc854ff0ee6a644e90e7e0bf5ca6f04096271456bbe5b0	1	0	\\x000000010000000000800003b66e952796113d5523b0a3473e3c9f6dc1a0f3187cc563797b33e8cd2a9043b5973845e982295d35b3584e799a71989bba23f7808bf5654f41588560b00665f9ecd97e676e26c066c4a74b8fe852484f3739fbbfc117e7dd87f45f841caa7281403d9698d1f1bd3924b711429c1d209b1b313426e689da7090bfe8cc0019959f010001	\\xee5bd39e7d7e2c8b1cfc69f28083654031e3dce9920e760a6f1adafc3193185d8291015d67f9598bd15b966aa5872a7ddaf7d5f3cc1bd0bbcec054927a0e7e08	1661500009000000	1662104809000000	1725176809000000	1819784809000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
37	\\x4710546b7e81bab6fb2489c8d6ea0cbb7e1656fec948fb2b3dcde54cd4873417d319662098792eee82afc8742b9c01f9b8efb239a4430d2f7ecb9a807775da40	1	0	\\x000000010000000000800003b4003015a68ca91c213ec4d4262fbb15f8a3bca68b230b0054d29946bf678aecc44395d980060414ef60dc3c626d275891f452f17140a88c15c29f9a3b5b83d3b089b565564dcd9e0119c152c6138a84284f09591d575eb06911ff39fb1fdcbaca44bf04ad999352d10a551c5881d7d18805b0198ee6109f7088bfe18876b427010001	\\x8a23fb781b86c6f48dae2e9402c7ea82467acb1580409a7fd415fb55b3aa06f52e4f71e85078b2d334aa75f287d972147623bdcfc57f962dffeb89f2a6440c0d	1657268509000000	1657873309000000	1720945309000000	1815553309000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
38	\\x4ad4b36f29053980ab604fbcf7aef3f7fb7a2bfcdfa2d588a180ff48114b5650eb77a187b6bdbe8dcbfc3cfb3b81f4824ab2eecc051a86806db181e9f56b5199	1	0	\\x000000010000000000800003a63816450a84c63e634ba7a9e84b09bb3dc13cc3c75e97650a8f3d7ab24b5b4ab47b4deef149c44b0f2e53e07dee6f5d17790652ea5eb139090f17bac9914435d4e6b1d10ac7b6435dae3eff978e26070f7f0059de5a79b0c34dd29e35c9cef0215c3a57d1964a44a5fd5bdbf7a0464712ebc84851b221411e4b2139ec7cb8f3010001	\\xb6077151302a57226ade8357c18e386c1ad9151b969fbb5f7dfab344cdcdf8d62420e9f3403c5dd782adedb45f8522c751a8f3c4818c9a1c114a0132b4d8a805	1653037009000000	1653641809000000	1716713809000000	1811321809000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
39	\\x53e4dee66773c4b30936f2fa1cddd32a77bc9a42cad679b88a4c5c8beced989e4e2b1d1adeeb2b71866c0ab6c14e662dd785b14a92d7b0f82716e401e6e22a46	1	0	\\x000000010000000000800003a1fd378c27f65065f18cd2c0480d9b1146203cfa7f42d300cd63b563724be6ae439066a0e0399feed79a448c19dac0b55cc3a8c20edde1786f8b56100c5a7d5adbd23752b2d7db6a5a0f0df744321e84c09e07159be26c01bd80fa9d20751076315c57db0e77cba1b725c06a4b4ce5c3e9b1fc090be0ac6bead6afed9bbd095d010001	\\x6ee5faabbac63b55c64409b44524a95b49458b2d3c38b248f60e63527831476ec8842888b41b22b28d98fbfa2ef2fff03da2039d3710df2a8de4c1357226ec0d	1656664009000000	1657268809000000	1720340809000000	1814948809000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
40	\\x56c4276041329485c5c7570d2bdfb048de885799033460dfae9d0470c6f6cff17ba40c793eb3cd8434b1a2caa06a65d55ebcf748adf8035b9c032f58ae78f1fd	1	0	\\x000000010000000000800003c7e7afc93e26786473f72915ba11a22d768d8653f6b3f74b1d8d04cb22c929c23c327a5c73ea1d21db853723a2f645ebdd92f16c1a3b2be2bd4c4b4573cf5a5946d380a09dca3ddab01cce22fb9de285af259e4444e9cfbea1c27fcd63ea542dd018cba2fb18b79441d5ed316382030ed69a74d7cea845072290ac40de384a07010001	\\xa932f034c40f4ae3eeeafa4db35c1849bbfbbf8e7de5ca7102899af90227fc53caf40a6e7e221947f6a2f1e3529b807bbae6301c9c155cda55c904c2a3c93a05	1675403509000000	1676008309000000	1739080309000000	1833688309000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
41	\\x5610b6e6717c8222f8507421a594670af124abcdc110feb5085ddd58d795acff79e91569ed09dcdd110e35d9b18366f590dcadf81614ff0bbefbdcb0466424bb	1	0	\\x000000010000000000800003a94b8d7a5a820ff912dc867c57b8d1ccd610f80b9628e9b2662a4e6f38fa0d485f3e8950c2f5fc9119baca7635fc45de9adfe5bd52c8bc64e4f6f273db0658e316060d2ae1428861e6a4b9961cd7c72661df208f2c21cdda3c524493bda3ced730fc7ecba3c35d6a44a09077d38f65dbb08ac84be2a190161d19dc98caa1feef010001	\\x12cd566e256f7059deb2c8f0fe17642e8bd82b6aa29b8cbdf18f7906ab4982cf242f08cab3dedcd7c5c0abdb1e98db09328685ef375f530574dbc479bded2d0d	1677821509000000	1678426309000000	1741498309000000	1836106309000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
42	\\x585cda2b18f100d36be396ce7eb83b20e3a04852a04e23798d80c3f56d8abc1dd59f500ad61525f63e87dc9fee8a8207201f404ad59a5b8aa96f779fcb25c58c	1	0	\\x000000010000000000800003abcd4375c5fc50070799b10a77fa789d857f8e50212aec834e9a5f6a7370f98eccbe49eb3dc8e7972d5227d812edac54ff20cd61e91bde998de6255c533e6c4adb3de7d79d8b04d8ec09c5259a55356a95a18d21ee99fdf8f5c5d73474ef450c7bffb297cc454278a5e819ee325d52a57d40edb4ce6262b39876a17acfa18f1d010001	\\xc2cf31d7023e01f96b653bb78a02535febe76bf43db2d901f858ce5ec735693832268e555841322195378b623b191dbf6a90c63d091eb41b0713676df485d908	1657873009000000	1658477809000000	1721549809000000	1816157809000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
43	\\x5fe857d68eca05aac254f27da9ed2c86a3e18758b64198e5088a2c37e420d47ed375ad15253ba450cbb5c1312cb1980a018c97abb6fe0e8e381f4316538386f4	1	0	\\x000000010000000000800003e94294fbc8a3429ff39ffb971899f1de40f0a5c7c7bf152eb448710d2a30417961607798e48390a93677ef9326070eb571858ef6f4560a0b9772680c0e99b70adf20b78eb858c63354fa836468cfe361bca808ebd30e03e7c1628eaa66cea6119e06142eff7af931f6fa3415b35e3f1ec82ba4484c56ade61488670ed8d2cbd7010001	\\x11977b610cdc394d27b51c77037f37f526b65d411c3ab611cf15b316d00351d476bd0606b9be6618dd323e52a2b29d8d560f0337a2c7bba248a1e7e8e3792404	1674194509000000	1674799309000000	1737871309000000	1832479309000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
44	\\x62041150c3fdcbdb16950a4d4a247036ae755286b1744420d370cf3159cc23ca8eede79047f5ff0a95111fd28b15beed5fbabb8654477598d1dee5fcd8b7acac	1	0	\\x000000010000000000800003d373fe341fbe890fbfa71c7942b8f29ddca5e345dc65a901852cf2c71558d95c70d705099db3f1675ead8d9a9823ecc9668f6e46e86a9060bc04f2a09a3dbb8c4daa60de981648b62f6796bf27a93aaa481fbcd62b3025ac7b518dc0ef51673c3aed8ec9a47f2038f92210d87cdbd81c773b204dfab1e71feea12aa235ca475d010001	\\x47b9fac95e1c46eef147caf3dcb928f297a353da68903e5be367dd1224df270e99eddb66a5616d194f9d29843f71c1b67f43cf17136b7e746bf6914d29c2a003	1658477509000000	1659082309000000	1722154309000000	1816762309000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
45	\\x63f4028741b97ddcff633a37245a92742f5b5d236d5f3b4d4ef683c4137c1d6fa50a26df72daa4ae50a585ad3fb4dd522671080db897684b3f8d2d6cac741f6b	1	0	\\x00000001000000000080000398f4c845b856196dd354cf689fcda676b132318d899c12aace24a468cbe50bff89b152c7a21aba18f97ace1ba073fbb63ae437245b9a8429124013be7d8dee47fe2e686a23d0871aa5a786e3dece51297d87645f8fce99aa27e716abe320e19b7297c42d5370f6d0b6f7a4da9d3da3c89e4555249ae4f1d9d719e5251540ba0f010001	\\x7733e7aeb52a5c2807a7bea37789b873d244ee81dbcb6c66165742dbf215eec5f823e5c5992b757684ca35d9b50a8710a08e72d227999adcc62647820019ad0e	1678426009000000	1679030809000000	1742102809000000	1836710809000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
46	\\x6518da7954983649ed4dbf3a4a0b7f3c6d2839ca7c248fab47998ced812dc24955d3c370a981b405de474e1659eac2f38b305147a245f212191e97a893c0a9b8	1	0	\\x000000010000000000800003dd0362bb3be1f4378211c8317e00d16d1e7c73be7b2a571e0a92126d9a00e22145bbcd8c61e6a9dbbc4ef77487865d9db2cf8c253f96ceaefdd5a9a27babff2688be76e939ffca2007bd93433c69d18e0955ce9fbd522f5cd0546e541bbb8d832236bb05b2cb9e18a56a71236c050584ca3dd90247710b6e8ec3e5623d909729010001	\\xaecb3c9762d551adb6995ac2b4dc6b35f8fbbff40c10e096294764abe914c68baf8d891d6dd68a383c5db1518a2d650a2a4fb41e16ebf00de94dc7160bbbf20e	1662709009000000	1663313809000000	1726385809000000	1820993809000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
47	\\x67b8d743c56aa894e4b120ffb3995d9e003e1803018b8a5c317f715a84b4c4b2539f2028eb6772e0ee12873dc9c1e22af05d0a629c9f34b2589fff3ff3fd1d80	1	0	\\x000000010000000000800003b9e31551fd961696d4e4a71081cd73695464da4bfe0880fba5485cce2ff3cf9f1973a457f5e5f5200833ebf9e12d958cc1a73c2c8d2a90119bc9247b60d5f2e641b665483c49bfe81771cd6fc1139801399481fde9adfb4183502e54b340c86f72169b565aa7d74caed9b9805c246a95aa1ca927d67dc9725eb8274b73e2ff49010001	\\xa4eb23f70c67a426eeeb0e219666bfb8a25fd50e76daf6d58e5e022f3c22e64a96899159d9a26f924d10c4a98ae2ad757428c2f34e3e757982dd3e5c5c24fb0e	1664522509000000	1665127309000000	1728199309000000	1822807309000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
48	\\x67cc1ce736473f81dd472f2eff803f7cbf5791d58ca9a8f0541a9a4b72307c6d1e79101098c4d404a066d6bf749e4206b311cdd5485ba0f70d295d10a2e9c10c	1	0	\\x000000010000000000800003bfdcc3176143d4125c348190b9b76822fb51d4b9476aacfaccaf7e2a15f07b1b8ceb32f3ae6c00483910e38ec6ddb927394a052f3b9bebf31b7ec53f476f80a66dd1c6be850fee4132a8bdf50a0c26d6e843a2269454ebeef41e56ff5d60d2f2f431c5f9de223d123cdab34f77a7483f7c891e0b973422cc84b23a03982baf29010001	\\x855342723d9c520c26c64a528b30b0c5e0f3233e029738cf508e7386a30040e7c44f629aff2a1279b42e4438334a990cfb7c4f366aa394e2b36ec1c805ad770e	1663313509000000	1663918309000000	1726990309000000	1821598309000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
49	\\x6840a911fcc8bca8fe7057218a4988c7084aa40bd1535b735241537effa47a1768504ad83de9ad076ad44d6b2f8621287d33b28555bcf4c3e036a4e79231a5fb	1	0	\\x000000010000000000800003ac64314bbf41de16c0480c77cbf7325c440f22043faad874fe1d5929826e0dea676b5cb8843e7a9b4320e250d8e5ba5c94d3801e29c4e4c50d88fc0b6e661cd7d6eb45f92a046be8c9c08865605ab8c3b9109ee113eaf820f50e4a1e14dae2b1bfda572b4612887a7c276e1206fa7ae5938b4c606d4114a6a07361937cbdd3a9010001	\\x353a628561d69dac78675a514839d942c166a44b48bb5251bbfcadac86da0a544469bd7bb9d62011fdb8f1f6ccd7d32425db024f41aabeb71cee730cccb9cf08	1661500009000000	1662104809000000	1725176809000000	1819784809000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
50	\\x6960be3e003b44f096d4b1b713bc7bc4c524bc263ec862b7bc54d79894ef4215edb00bcb19ba95cda40e1046a37311d3f5c7cd0fa3f2b5735e0b9eb913414dcf	1	0	\\x000000010000000000800003c114befa63c7e7015e07e539adf92dc664f82d05e13daf9e59367e39dd847d5d1c98150e05db6156dc64ee54766bec80aa8081b5f09d12ab37fd5dd0980d51bf3c828b38812f1ce491e6d502c97734143a7cb869048d777db38adbc02628126ed9ca3043a5823dc362f6479ea699ead9b956cedcc82a363a0ceaf636e68c2507010001	\\x0358cbe1ded178cab1c9c97e0966e90f996fe29fe7e19bee88e0ce40eb736c6f7551d4f964ea2b5433c15e862b4bba97b7c9b884d764656cdb44362d53f2e90e	1666940509000000	1667545309000000	1730617309000000	1825225309000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
51	\\x6ea0c4c21502439390c5b9eaf6950c866766902f3ff7ae9a0638bdc80c814634c36aa4255611792f40cd82195ad81a1d71343ff0523946cd2048052e5c4caa2c	1	0	\\x000000010000000000800003aabdb9b2397631cf56c81fd9afafc9c371a401a981c8d35f312d1313b5a7206fb68781ceef20dee5b4d2f67fd47296aefd52903fdc7ff0b35873e9a1749ab1b0fd4e81ce102710ed7730739b13c0b47eef987994da268dd1089a98c7710bbb1686ae93484aeaa7a4d41e389431ec22f2d713730caf03cafaa26e77f7af9d7ddb010001	\\xddee85f34284543b997d638068fa0e150db82d28854443421885f7692af62ae498995f98baac6ec222e729e543ed5551fbb150a541204ddd01b5c65afd2bae0d	1664522509000000	1665127309000000	1728199309000000	1822807309000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
52	\\x79dc3e7ec03e4ba787f47de87861b8966c66f9c616ef2d0afea8065994665a314341ff712fde4fd25d04938650889c5dab7d384879787ec57ab54eff509b2885	1	0	\\x000000010000000000800003be2eb18d94ce5437e1fec7deb17c457ddd8a16292680a2a4107f55adfc1d3de7365c562abf13855a6c791ae0eb921fb59c9563f23778ad9cf97e8f6e01f64f7e272bc94e274723f240bda9fbbbf31273c505db8dc33d1116c83bed092d68a16a62ec818bc5043c2a3b9585183148aa5237e1d7746c94f62ed3826a19e47f0f2b010001	\\x13203f509a29336e38fe34f7fa40a33d83c374451aed04b5e0fa5d910ae96946d60f6b50a00331622bf9682d2d5f2b962cd26643a1ebe08f106615779b2a2104	1659082009000000	1659686809000000	1722758809000000	1817366809000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
53	\\x7c50c8f5bd9fcfe87437fd426db73ce9b69f4ac93d6b7c1875280290987021482244a11fd8188a1a774e644c510e7d34c45ae8fadd7894e0ce381cf132ab457f	1	0	\\x000000010000000000800003cfcd8932a63c591d0b2e97615a821cd3442aeb8e4fabb53d09253faa0c80b0e88ba07f26766fa098f138bd85d8f7869e3e8ff43891c9fe353aedf24c5a5a6e404be20cf46be0ae044c87c75d73b47ff17ec15bf5fec0a7b10e2b8d77f064999b52d82cd61549be622550216b012b727c8f055d2a0945bc27794afff37ef40f09010001	\\xe57438b86df3f668f5adddb276015184ccda095f74545a4de7b4f1beab0ea987c32a39e957bb45294f1ed744b66333a9ffbd11b5653c58ead5e454847d2bc601	1666336009000000	1666940809000000	1730012809000000	1824620809000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
54	\\x81483bef2af7b37211d535a8477f5a84dda84f6b87f4a7c4061aa9826999fb01cc0d6db74e8b3ae429328616111ac91b4bef3cb29c5d44e048833720185d2688	1	0	\\x000000010000000000800003c6bf75668332637f5082840fff149f55e6b54f7a0823e8c6e56273df0032c9702fbef779096f745343c42f6dd8df54a3b4a42a2c8228d47baacebd449320b4bedc072a50593a9fdac113e94b9cf8d15bc417022aee5ddfd660ba78e6fcfecdf9c40860d92b970b366d5def5e9c98bddc705125dd09dbc34f8f8865629cd4cc33010001	\\xdd8395cab1c512ba5c83899a2c2975ee4ddc298f126c65eac8a41d2e3bd06ef808ac81eb725c7e498e2cf53b7a5650ddf62e985bbb5d11f46d9d26e17b375a01	1654850509000000	1655455309000000	1718527309000000	1813135309000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
55	\\x8440038cff4baab3a6b50d7e8edbd7dc579dfc44023d518e57545e9c446f50a1bb05e1cac281e9b1f8a2b6e1240586d6130a1d814477276dcd2725daca1d5849	1	0	\\x000000010000000000800003b41f997e220358c40ff94ca21d6c5898698a3afaefaaeec1be9a004cb8e2e2c7b6a29319b4dd1a249a47860dd9d04b5bf3b8ff8f44604f29d12c0fe2b5e5da348e3204ba469c5a1d2515ca812801624c3962b70a2481a9010f2f5c6a4edbff5918b233865853c8a16866a1386087a8b13e9f09d1a1907caa79084b879c8fd893010001	\\x114617844a7d858a3ca7865a88a7148e6ea5907aaa2022d0f02efb5b895b002d12ddf06dc996d9006e3cba3b996a6ef1e2cc0f8ceb68825718a34be0033cf207	1679030509000000	1679635309000000	1742707309000000	1837315309000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
56	\\x8494e2d29078c8cbe714a9a6284d0ff4f4e9e9708de86bbafd7599b9af25dbbeceb0030ef51597247fbee849a5b55003a23ce2e3060ace36f5c1b1b4f59f6b4e	1	0	\\x000000010000000000800003d16f654e6663ca221c71dbc173d81102d857e190a856d62b38aa5511a677608d24c05c9399175ea2ec7248cb22ffeb89eb5a82c0c0c365ca71d0cca19809fd9b11ea4644b37385a3678519d07cd7e5dd9ce39905690815a504a0d30d72bad892be5e09fbb5dd2d1e38a613559d1f161f3eb41dcc5168ccb0422dd2286ff96b39010001	\\x92c9170bbcbfed8d240ee5257523caacc1ad28f8f66b204da4a649d926bdc3f258cb64a4c2874730d63a1f15332c924bca77a9e723b42aeb50cfe4c9fd0dd40d	1660291009000000	1660895809000000	1723967809000000	1818575809000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
57	\\x862872d383b3f1d8098e0a6f64162028e3433d5937c06deacf2f1755c5babfd122a98a0c314f666ee75f5690b1e86b2bdd89dc02c607837a2d0a8469e4821aac	1	0	\\x000000010000000000800003c71e9807c35ea080a02e8ed3007c3ed54d60439d07ff9295a7e6ed15e77f75fb81da6d0f4532cf950dddb1ac09ee58acad0da55d95d3748dc9009df6cd2502dcfa84c94ce5c3cbabdf79e538bd41047a94ebcf27fbbdd3e0aeba6d092dee79155b978ac7bdef92fbc1d9895cc9303f6360521bf4a5d3cd710e96c229187a99cb010001	\\xd469abb7afb062f4ec39681273cade8622bef7a590e964d69eee4304345fc3d0f4dfb186e2171b3211d4224dad390f146c86c861d0a269607ee67521ed6f9806	1650619009000000	1651223809000000	1714295809000000	1808903809000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
58	\\x885cca55f319a84e48d147cd788e1056c4a761dbb21ec64da60dfd16dc88d2051ee26ae308793b49e196d92807d679c2a095f3049cdde064b671b9d8e902bd1a	1	0	\\x0000000100000000008000039f77f19ffdf0c66804bf6bcbce8f6df85e54675205624b665703c1e5f4c579c73ab3472da60a8388c94bf5356153ac986f813651c80fec0c451acabb95240ada8b0207687886ad486f3e55960362229af510558122d3fdb6d1210ea135edb54c555a21550f24e62d73affb53010d23fde8740b44b4ebfc933eaa58b4434443cb010001	\\x85d29af5e74b01b524234c54c14ed463bb140a45a56250c7d847180be6adc823e949fc87241dd871294e133365d89abf80e12afa25d734af277eb9d5e3018d05	1669963009000000	1670567809000000	1733639809000000	1828247809000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
59	\\x8bb4b16154d3b42436b2f66cd27fe83759f8b608dd7e48e06d3e8d22eb14b0bfaaacc8334faf0d51474c9d1268621a48800dc2fec471622a87064e8e61bd2b2c	1	0	\\x000000010000000000800003a325789d15a8e7f62bf53964f829e59aed6ccb9e02adae488a9a87524e63c448ebf3de7af2c47f3b1a2bd5d756f37eb6f7d28245619c6bde1541a2f2474551f9a25c34169c21d25bce77c13acffb2794f765a897f719b1d9dde51a30eaae4165d47289cd9eb020a8aa007124e0c9cdee9c264e85dbd42796dc566365723822af010001	\\xb9cddaf446ab0ecb633d3a0d25dad66fb869a2b6c9a5da0001aed08d79676279a231511300a415897801b67994cd7394ba2b78bcfdfbc48eaff4815f42ef3906	1650619009000000	1651223809000000	1714295809000000	1808903809000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
60	\\x93c03d296e3842e6fcb357ca91a278708f6fbdd1afa0f4d31e66723b3c022f88ba653af81050a74f1b846bd600f121643010e31012e90a9c1e1823d9dbc6ee61	1	0	\\x000000010000000000800003c2c38a6ef0c70cbbc290f1b798ad962c0b3bf969a5cfdf23ad22fc1e1e7cd9061b0cb264611b130bba2a8b104539b2b27338bd7573f811b349fd64aa5d766c05322ff38ce60bd94c67fb8d743f2ec6b5115eb951b6a8465627beec408cd344fce17b50efeeda92ce39887a6ae0524c63ef60f1926ab6dabdfc0e20071e8607ed010001	\\x76cb5104a078d0c261b01e9ff96e3aa46397a2929edf82e81a7b26f45f9f155b2fc5206cf2af5ed14b7fa5ce47487a70a419449a5610bee84fb6816f61119d06	1676612509000000	1677217309000000	1740289309000000	1834897309000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
61	\\x9588d0fd8304c388e630ce991e4cc200eff8e674cccf027a724861558da84dec54ea9bd233a42286e4c57c19e9a88600dce32486ce04d9973f72a12ebf6bbb14	1	0	\\x000000010000000000800003c9512f374327e4a861b6b4de7a3ae7de3a6e626e7352c3e0ac5a50bd4bbceaa7b9191d515c1a9d15b5c0607da35df3057fa83f0d88bd44cb7e5514b553dd7284a4de1aac710788565434c0b5642d8577c6e0f770f4dec0b07d554eb31fcab4f01bc009d941c87fe78ea23803a355f9eeacdefff719fa4117149ab7a84c43457b010001	\\x2132302c7c1e7fe42be78dfa50d222109f478466934d6d42c2c5697fd65e4eff4f43d3226efdb85017433b8ccbc2dcea1af25dbbdfc517912043ab2ee450e601	1660895509000000	1661500309000000	1724572309000000	1819180309000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
62	\\x95d05b0814c381135dfbdbbf39a28f096a9ae7a5e9d8aa2577083f4fe69c4fc949fd56bc57209ad5f27bae067ac92bf7bf15dadaf719a7c1ea171a40ac813c8d	1	0	\\x000000010000000000800003ce6208d2373010f8fb0fbc951cf8ec2b5a11d978a88268a2db8f73933ee1f4aac13743ca83a16706e666388ae24ca380d89d00883a16cf864b3d9f2fe69445f5f9ccdb82c025e56214f67f64f8f77eb4e917127700189ab292583d528c1548c36b70db9c1ca9e3d082511f8c49e98f86044b8052f7815e0dd5b2708b964fdcb5010001	\\xa607259985754f48198b834e285cfd4aba2d74b7ccd7acad12ed5900cd123db2503286ebc62b4bbaddc5b70103fa6005ae0ad01c58209ef49ab79706263eb003	1666336009000000	1666940809000000	1730012809000000	1824620809000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
63	\\x963ceca42e0be4a9c4dd6e255bf3d5cfa000d29faa1caf42a4d9341ee8630e620460f6b4c9419d988902cd15a5ef9025268240af29f84543854a228342c18597	1	0	\\x000000010000000000800003c79499c9d61a4ed60a24a2d286fe206b209ac6db566012d6100aaac351c660d0a7c7339603edc13288759f6ac52c4754944a9dc7b6cecc6b2d7e174049bcf93c14fe08749c847cd4acf8c1cb63dea02a77ef6b64ff02553277d355e827fdf28873f427d3906be322702713911fd06766509d1106e835b4537a148a0863e2e383010001	\\xc96fec77bcccc07fb6547255bb8bb122dd881e25dd5e2d09cf6b53f0c9eaf5cf685cee5674564cb1cfdc30b253ff92c76b2f89dc45be78a3d3886aa7dc1ea907	1667545009000000	1668149809000000	1731221809000000	1825829809000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
64	\\x996c24d254339074815b8f396242b5d92a98d3b95879fde115416e5e3f01d32895edb5c0480fd1abe18293636ca0cc68d9728a9608f97fa3766fd95cfe9afe56	1	0	\\x000000010000000000800003be700336b30f2189bcd4081aae7d258131737e1dc8314114902f3ed8f8743aef7a87c12585cc80537eb2d3888e7f3bed57569b0a2b530596778dff6e932f218db4862deaa1bca0c7990c0de5960fdcaa75fa391d56d4da97460844a9165f2605b53a172e2b408976782a6d2e2e5a0f3103e4f26af6b1d6f975026746117a716d010001	\\x2f1578f2850824b9d6be5c7e01cfff3693b5fd2f0ede26d2c64488249fac6dcd914083308bc32c08de2e4b0990492e436ecafaab389e1fefe756bcc26aa61400	1659082009000000	1659686809000000	1722758809000000	1817366809000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
65	\\x9bd037a54600819fb86b489bda0fda7a96ee4c9638db99fe8bb3db084d8b3b7e3a3fd49cbfb3c447d61905f7ee950209ef83ef98486ad1222545fe638f3696cc	1	0	\\x000000010000000000800003cca203e7465369eef867bf695ff8198a44996213113519645f56b7ba5ba1e799de4c769f428a8d1fd8d5713e0e26d54ca1f4d909d5d8fe75af923e2da6456d1ad3b2834b7a9cb0558cf98481f3ad2f79876c7d09d32f4a796672ae4d9664a3f32a63c6787d8ca424734a259a0f4f604090a7324d0b51941bf9003e58677836f9010001	\\x434917f2a0e88d8a8848d75b473e173530fa45137fbd9e3247bac355c2b77b0d0a09f02b508535383bf52ce9d9823cfa825403ce42bc63babda82c524c58a405	1674194509000000	1674799309000000	1737871309000000	1832479309000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
66	\\x9b0c1a1c94cafb92330fa16a4eb1e594dc3c35356139376b0e1129de1ff670628fa8e12b8313d8505b0123e7432846202dafd971cf2e21f283b46fb530bcfda1	1	0	\\x000000010000000000800003d42dd37a16f6f3d332168f73df07001946e167717acf762c76fb7f85266c6fae69aab9b61392fb5afb1b671ccb5831c631ef85e86fe5c0c9f9931d4c6a965902feefada852f390d3ddbf782817b6afa63901dea70c9f85f2589155758daaf0e5f0ec126d0eec333a55bef177e9242bb14403c7b2fd5b2435ebed7f614df888db010001	\\xd5b20aedb0b212bdbc3804da1f29bdd9d1a35688a7262ba554e0e1bb81b6f6e34c4df290953194d9c1cecefe4219df4c6d6e91e29dc506de7eb3fc8fa0f84609	1680239509000000	1680844309000000	1743916309000000	1838524309000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
67	\\x9b8c3581a49759a38223eaeecc4e619c83ec2ac1d90c68bfa72c54051a9a679b1093fd882910c7090f5b12355c8d2ade6b4f33e4e07d87ca14904562ebd6eb47	1	0	\\x000000010000000000800003e9e2bc6613d3a7e57d10bacff34ecef66a76a99bb08326c92cceb4690dfac2f8bb1779c59679e49674651ea9a1de4aeaab515491b83e6642ef93e74bedfca018084d6705cd0b0e6c04caaedf07ad8a6b94d796a1714ea06e7c6f1022f90c1ab3751b35a59abb7a294bb19e7495959b5a2321bc8a15dbcc37495ff415f648f8b1010001	\\xe555c6a3d0d276226ed38db22355a9b2cd8e4a880f47880f01ac38f20324750829816872826d82d360de09eaae8b21707b7913ca2acba1f9380f1d1cad906008	1665731509000000	1666336309000000	1729408309000000	1824016309000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
68	\\x9c580b118ad486a2bc0d233e1599e189d5d7d14b384d6690fde98bcb3de2ac4b01ebfc9f06ba43b487d7c53b09356c57551ff62591f2f5eab74191c30bcaa1e0	1	0	\\x000000010000000000800003a28932a5c4d22a9af173aacdbd0c0b9c3b198dfdec141c74ebab7a671978d59af9e284b8d1be6260ab53a47b624bcd7e0c08df8bbf6a5eb7453ad284e49ed26ade958228a1b338585f4803abe90b7628c371c847acd9cf90732be22d091b2d6c3a4b53d56d51b309639a0213604832051825be8cbe923a739a602bc551a79a47010001	\\x9abac114649283933661d734cbcba85ce087fd59b13dada1fb5dfb8584ffe89280fc8df0ff0abf8ab7802885c69c2e531e0e4e92f3ea9f946c151ec7cae37d08	1666940509000000	1667545309000000	1730617309000000	1825225309000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
69	\\x9e649cb0498436573c29bc9b0e5fa5dedaa5c5d9ed0fa60bcbac03b216a43861103cb5cf68ce445feef4842d1de7f0642d44503be44699ab29241c638f134a69	1	0	\\x000000010000000000800003e62b7c19b171a910d7d73f0a1f70cbbb911bfab169047044e740b2690f4b18c5d00afd1f3e755ec7fad75d94ef46311aafe4fe429f1c762ddc9ed2d164a2425fb0e92e4f9d2072011307aa0d4a013089f08d2ca46acc0d73b7504f276bf8170e67b5ba2de9a8c0b741a6019de3d20da811941bbb6eec6a38653641e2154ca6dd010001	\\x17039528bd2b8c70746e14f5f858a43bec95c0f1e2d203cfdc2cbcf81bde26dcdfac7ff832031d43e7a0bcba53b100a5dc4550573639b099bca8003e1947cd02	1672381009000000	1672985809000000	1736057809000000	1830665809000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
70	\\xa0700063357e55acac8e684567dace7d7b79890c24231bd1814d3ef0e429477dc57e54a08d91126be412f8f726e5314e4056625063f7623c0cc534beb4cb3c72	1	0	\\x000000010000000000800003d45069eb4d2208b11b519d672e172c9188b31ce2c5cba6aef3e369425e7cc9f585e28b4c558d75185535adfda65f6b260b2156982f0c0226d2956f69025c5347cbd9f836ad33f6f4eb54a7f4390b33ce5d02f42add8ccfee865f06b925a0e60ead92eae161f76c1f652241a23baa1693de58bfbc4abcdc50bbab8cd3d256e4b5010001	\\x44d335192c49d23284c384ab54c676b050e7425bea0d74916236838df528733855f8f7c23563bb567f400f9f4617a0cee9bc301c60c84e18b23daf35d7cc210d	1664522509000000	1665127309000000	1728199309000000	1822807309000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
71	\\xa38cfd616725e5487abec9a01e5f3baf935c215eaf7e30478b086f97ff4399d96ecbdf42ad885d4b24dd9ef0f2e4038abe731eaca0612a19b195a9d2253bd20f	1	0	\\x000000010000000000800003abb77f3b3d4f25470298667cd13f2c75bcb81002f36fdcf8e63caf299ed4d41607e19be09345bc7b8220181e46452fc48d20a78d91479e45f67c8fab245064ddbde198125929cc66d17eeb48eeab1d20b75ff0a2c29825607251096a589f445dd9a991ec57eb05bf01ee0dcd6acf9c35e8344f005f0cc9eee0c5487d1eb4d9b7010001	\\x0ec0b475fef0a87733e339f0baacb75ebf57d1b05b025590fe557ec2daf0d86ee9158e847abdf2a5a86edbfaf7280a06eb996bb8c74a6d56a8999bd90aa89b09	1663918009000000	1664522809000000	1727594809000000	1822202809000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
72	\\xa4f4ac6c69bc18b3c25adf293df12b3155ed8cae941ae61ec902d5ffabec3ddf78f4d348a5f70adff279de6fc293a69292eeca0467f0945e7a1ccae7f8dca459	1	0	\\x000000010000000000800003b6a6b2af936fe742beca47096f7c1fb32fc5848cc15b3222504e72bd58f200969c86ac14ecd20cfe87e2a8ffae2e2fbea1f845a2a16d533bb8f6ed87c34de86d4b72d363275e7515f7d1d3cb1cfa6e111896f59678650262e9c6037b0bd2d3e66b9cd87a1983855745a4c3bf8bf305150512bddd2668e5bf12c482b939927b19010001	\\x7f9d8a44f34beb10fe03929c06d2a12c4c7e57c19e328533e07a4c3ab2a2d6240b16bfc530e8876b26e2f573c3b7ddedbc82fa812dc18cd45cbeb32315c02508	1673590009000000	1674194809000000	1737266809000000	1831874809000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
73	\\xaa44cf9a26bca2a8a82c8f4d565f538ecc804115d35610e71d3abe8a2fe0157f24f75b8a384593cbf9ee38f8f09e7991a13d7950cf741edf2eb8d04f39f37560	1	0	\\x0000000100000000008000039aa7ca2121bcc2eee40fd4880660c5dbf0c2f32875b30542b96f96be2da6116c0a2fcdded384a2312abf1c21894b7c120754135be2bf34b2a75a1c4251594f82c33dfc03198f37fffce54a8c6b7ff56bcd1c3fa18d32f4d5718bc34bce58ec66d3ee6ba8f21b9bb17bc1b216b1cb9057f97bbff93b10e0e0e63afa09fc40f15b010001	\\x4ea2bfc41c2c77cc8a9e34868e9c780ce1e4300c6a6ff76705d80f7efb18064735d869316ab8632e474c28eda796160c185476975ddfc91c27d053ad631da90c	1669358509000000	1669963309000000	1733035309000000	1827643309000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
74	\\xaa28abf6b18e3244491b44934b3f497bcb897c7f456868f544639af38c5007d9db13446f0846f893b2f4a0b5b5032bb5a0ed9220b5337872afabad35457f33ae	1	0	\\x0000000100000000008000039d5457b7653d92ec736ee750ab54aa10985616b35841ecbc9ac32b5b6f2759ec27641f6c8378d2131bd8f41930bb065be10483084bd93466c2c4afc20682042a97ea7aa6fc4a22556a331f1c52b8ca266393db6004919690df969a40a515a8a942544103b2dad603483f0851a186ef16eace98dba562d863d92ce7d4e25d7f83010001	\\x8b6db09898cb9d258f98038be9019408de455a04d56c607497198dc1b2302fda7e8315e339aa618928164f0fa7838342d61cf8dbd41824fe7ae60b9bd566df03	1652432509000000	1653037309000000	1716109309000000	1810717309000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
75	\\xaac04a1a66783021a4065f990781f8d52da2952c64895d5317a652667ac42abe89d2b2b70ce0d2756246521a4aebf945b4d1b1e5fdc00a499ee9be31f2e7e2fa	1	0	\\x000000010000000000800003a497ee2cfe1871ed53a15b98e1ccc65d610c4194604af3bcbb0fa8be75ebdd6a1a7b765b24f48649a1d484e05558470534addc228440fa4996de9c49559cfc7022e04dba7f7fbd3a0272c6f8af3ccf68ea6caf667fdb31f931970d1e5bd5b568876c12cdcdfb9b5016894233e3e2840a1f6244c68c1a3bc5f1e5af2aaae2f95d010001	\\x853661e77496d79cdbed8ea3ac80765bdeea4b0b54d297ecbda74f747c47ad5933496a9b399df12cc57253e3b767a1cb0d5f24234baf13927d7950a7e61deb0c	1650014509000000	1650619309000000	1713691309000000	1808299309000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
76	\\xaef89aa16806faa79655e88606fed70cc91a94270efe6cf656e22f86651a5b916e5de941388648465a9da2364a617343cae6c31ce302b4252adca6d57e2323bc	1	0	\\x000000010000000000800003cbb1186b54541f83fdb46466305eb6b699dec54c2f21112c8076c0430d0b8232743eb745a219c3d71ee5c5282f386f334475b1eccad4559e9f8ee7e70539990b04dbb8986965f9f76a38fecab1fd3c9d032e85ab01b5193bbdfd751afeb00853033c250c2135b56f1212924afbd028298859d7e063dc89ffb9639f4143880581010001	\\x7bfadd0cc9f3cab03241b25015f2490100c9781ebd048d91c1a389545cf86ea5431edfa95f0358c21cd84770d413ce5f58a0d10670fa530953ff1b9a89aa9302	1680844009000000	1681448809000000	1744520809000000	1839128809000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
77	\\xb0345c28ef1a9ed55d2442211b0550eecb6cc7b480def5e7460647e08e7c8fc88828c598c573a9d49b8fb5f17ad3cdf6b11eaad2915e59c8700fbebef7f17c04	1	0	\\x000000010000000000800003c031bfb1a8f4c11ce3636876f718bcf7889edc8f283d62479b44895aa9334067760b54d707d101241bf04da77209197877ea9d1e8c597cb60d86724d12cd056f2152fda4e4dc3d308c7e2c2509bc91651cad40e7dd89da11ada048d63a986482a9cc485d16c8230338a5df9e63d2a578e59b5bdb4fbd98ff6825b182bc7ee56f010001	\\x108867405670f1b5e9fd8839ec97e1d9834cc668e87039ab35e11e16fa7ad6ae450312f8dffa3daa3e428f23f06dbdee1d15ef8654b637e1f036de736f14d408	1657873009000000	1658477809000000	1721549809000000	1816157809000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
78	\\xb20c81e8ab07f0e7e707827b3b140eb56ff0a24a5dabcb13250f4a41a6cb03df969e1b6f28cf88e75eb297241868ac07a611983c87c14d2fd162ab3d078c7b09	1	0	\\x000000010000000000800003c1dd02d003cc284e62f87f615c7dadf84793b0f2525a699f9fb4459d1698b299e2767a861943754be1065e23e61e552caeacad86565bfa992ef89678fff871916c917497bc9b48b8bdf8473d75b8dc638c94c05d8d9c4a55db9e59f1a0952e5ab91062046192d4288cce145589fb127044177a5f044e5345d4f4404af8cc51dd010001	\\x6ccf3a6bf56573746e507ce55bb8a792f19601b67e2f20906854fed4ea6eb1b3a2b79125d66baeb79007981cccd41545f0e19e7feb34c9abbaad46dc303ddf0d	1662104509000000	1662709309000000	1725781309000000	1820389309000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
79	\\xb60c2dbb24f2d4e26123ed99d9fe3044e2d713ed023fce2d94e5b5f21500e3b253c6064f6702b154debbd73f03d91ac7bbf3b40ac6ec5aa2fb4911f574337a8c	1	0	\\x000000010000000000800003c2a34c39b7230deb6a0a9abc8267e6f099938d2376be87dc145e8fce1a74e851707d3d26d9f91ea143d1091d95249d231c50c4615fffd02444c2986b7126c70b85f29b34370761ade83df2842864715cf6a3fc5f52ac94d42fab14c11abe08bab6344bec31aeb1be4c8a4d09b2a9c830f1b83972ce99b3bbc2eb516dce4efbcd010001	\\x5290485fd4965560c6d2fc8180f4b61e1a541b2ba769229477dac513111bb6f8c423b83d2e1b1fd2eac31237467acbbcf13da43d4cd61c349955edb2ebbf2a0a	1679635009000000	1680239809000000	1743311809000000	1837919809000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
80	\\xba985810d4d1a8c27cf87e6eacbdc3fdfb4f879c40566bb6f45da35d67692789a75401b6e0228667b270859f196acdaeddee7276253908faf69622d44a6cff10	1	0	\\x000000010000000000800003c2c8fbffe0e88aef24a991e30686909f80971c8075eb054d226979db93c5dfe8ac88736cbd5187085bc959cd62ab6524bb3511a30c384f064c7e6d8c22fff75e2a1366b41350ac006e6ce645af7e4da1c9b3a51ac6113951df04436fc5108bd6c04802b579cff73e6ca08a19c1ffe8e890cbbff0e5fc32dfb6c210ee9632f837010001	\\xf1ad7ba0722c87517d84e4f07191db3a21217ebb688da23deb90f229c756c2bc90d0d4c45ac8ba9c5eb249bef7d33f0f94afa35bf7207d3a88e021a85825b808	1665127009000000	1665731809000000	1728803809000000	1823411809000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
81	\\xbaa8c8b7e55ec204fb108bc66ecb52509f487f663bca8680583ba61c2d0c2fcaa7c7932ca76921e2e611a2c529c3ed3964533087d466beb209bb509c13ffd0aa	1	0	\\x000000010000000000800003efb9d8379e77e6424be3e5a76adbc4a1215f7e8277c7a6ec5f18ed56ec3d6ecfacb15b405bc4dbd6d1725a7cc0a8c519df563004f8feb4133ba6fb1c4afa8d8c6c60ab92053120092f05a2e8c81175bf2977f0b6b7055d417a038b453987beb27c5fb5accfda55232b7f67c06d02d7f0a362fdd860bddb0e0cba2bea61494ec1010001	\\xb2566381bd661b0bf0f011b4a2d1531e744fae499b395f4e8280cbb998cd9f5c37b5631a6c29ff70744626bf561033eaa53f9015ba5a63b6424b85a0bc535602	1668754009000000	1669358809000000	1732430809000000	1827038809000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
82	\\xba6c8b119fbe8350d47c9d6e6a5d3830a94fb00d2d42b008b79e5a91adeb27c99d058aa6d3ddd97b44d2a24a8330a32d4ff59de905ed62050ce7775ffa9fa1c6	1	0	\\x000000010000000000800003c934793bad0f044e54aaedc8fc902593de123156aa82f92bc770573678518ed59155126bcdda260cbf4f79847ccca3e0b6601d466beb0bfc43524db1101d1fd4f9a02002786d3089e8078dc1340e028c353d0d5a805907c10d026c4ddec3aa9857f315f87c27dd50944c1bc7a028214405528ae17938fccdb245adb1e44f2097010001	\\x6654239bda8d314a91ad7a89829e337baff0befaee945eb96f9f8184a503fcbef7cc9907efb12a72d2a9a68ecd32c8f254ba25bbbd35ec93bdc497b1ccb74c0a	1659686509000000	1660291309000000	1723363309000000	1817971309000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
83	\\xbdc87be68df645cf28c2482fecc5db5de5ed7708acd21f963071cb6efc76c27ecd263f09d7c9adf9197d39db11f4948875e1aab96cf89d351e0dff1347c03828	1	0	\\x000000010000000000800003ce7daed9378317b8683f4de5aa06dbe85fc88c9eacf7e046a2266bac707856b022d01dee67b7464184133602e69b7e46f19fd379e528f00a1614edda59ca7e8e4f2fcbf71a06fb3a114b7fecc1f5d3403e81704826952fb6e46ab471e29d9065ec7e2ee2f9ca55e72afdec8429f3cd99cf246513b2c0e9190b5c1fadced9e16f010001	\\x3249f3439c982ed607cabd944db3bc6bd38c1322c3b4ec8b9faa7d7e3321d480d90e18c666717432aa46909e488fff714d9732ceb64d5d912d07cf4f8b4d9d07	1680239509000000	1680844309000000	1743916309000000	1838524309000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
84	\\xbeb0c1aba772b52d924dafb36ba5c660c6b4a4062fc2b6d61c3a45b119356fbf8f39bbc4b2d1dc5fa109cea6c21c23ac2cc8fd56ff5422b46018f191ba019b54	1	0	\\x000000010000000000800003e7544c8c06562f550462337b0bc033363be501b3f829668a6db793e8eaa0c425597f2ac348b69063346051f0f8dc8c5a1afdc73dffbd433787ce070e64c413b20988c2728b5ded163a9bbd4c02ef4c7417f1d4b58cab297c2321e766df7fa50b2b8a0ce99e88fd971e1ab5287d18d8fe8e5933770fd94c0c0289cd1c5078b715010001	\\x713e6166b2dc242a5e09eab69396f6aeb27bfa7777a12a2af83dcac9fb2c10b58fc36dcf56ce29a7dd21133dfb7d4709ff782ee1e7b064d8b327455f01bdb208	1658477509000000	1659082309000000	1722154309000000	1816762309000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
85	\\xbef41aad5dc944a7b3888c4b8002bb8c95be29dae9a0837c7cd652ae68b70abf9bdc7ef2668b901b6d38c711e50fab68623e1c56b22a51148de45bd9166c2955	1	0	\\x000000010000000000800003c2a6ea07485f0bf79288f4840254b939690bea89c0c0ad618897608b8ac98d0be750dea8fb4a9df99bce2a2a69da7c804092b0d9ab225355b37f361bd54446a8e5b4924e7723abc0cd876dc14401221d8a8b6794c0802712055337561ed545bdfeb976eaa46f46fd2dd6eb30a0fa67d7cbf68bbc19d47cc675e89a9412542cad010001	\\xe86f88716229bddb13d1fb2096f761395421bbc52684b0ecc13987ebbbe65903be9cb1cb5d4e9a80025ebb066bec15c3e9aa7b1e4b8c557304edf06b2e26bf03	1650014509000000	1650619309000000	1713691309000000	1808299309000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
86	\\xbfbc9146542219596a300959d01325758bd086749b9ecaf9f1cd7c9d831800c0b130c450a39e22bda90f0aea3150091904cd6c7d73d7ef791c67f4f341de8381	1	0	\\x000000010000000000800003c6d39591f311ac4130cb4b232d887f023e88380b1d1340c99cc8f97691aeb5de3aa9f89a047db0c7151471d76d706da5c222eb533097af0d817f1ea1cea1abca2a85eb9409d5ef488e31fef7a43f321476856173beaf37f574c5e1265aa984e4f050454f8bca70bf1c442b7827cf683495b8065f79c8cbb1ae134ed88867a6ff010001	\\xb3536a8e81046dcc8a4704aa98f4dcde5e2c45f528e585a56d3a7f471c327172423658fe6798493c703e2704e1e4f86064582b5be38617e75595785d92f37707	1674799009000000	1675403809000000	1738475809000000	1833083809000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
87	\\xc728577b4557d6fa738b98662d8bbc9e51495561208fe57f5016b6eb654ff98deb57cc81fb9b84b8ba4b0d5bbc10bf22ccfb3f91f46da638bcca47e0e996f8cd	1	0	\\x000000010000000000800003de68133c8fd54b5dcc7b374df0d76292a8c4338aa4c0eb10667358c2223e76e0836a6e89b0d20dbc90b4bf6b75e6961ee8af033771687cf695d18eed69df78064ba7d0d3ccb2bec6d51b18b047e989019cf5fbaabe74c3d249859916388819f25c6680d9612eb539548361af5fe7bca1873229e591405120a350b1cca801ec3d010001	\\x6cc73da0f9a66c757ea3726913b6e3429a044f4879d31288feb885ba6e0f1e2124befcb04748b3d3839d6a5c03d4c4f5a539131eb4dc32430db3b2bba55d5e09	1650014509000000	1650619309000000	1713691309000000	1808299309000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
88	\\xca00126ddffd0f38b4e2da43f46108f298042e86f04a0502a4a1d0c43576353db215d8d4bfcdafde1599f71ed846157dcf30b23166763dcd780fb6b41df302c1	1	0	\\x000000010000000000800003d2ca65bc6f613a012f5da70664a6f3aee71c9eff8bd9ea53c8865a68ce7af04f636c2f5095eea8c9a8f668ee905590331f190c315fd91963a14e269c3763dc8936e860d482df0d3bae722c4c2232d8f04bff701dd6fb61c9df228a66683ba5f8acf26a19ac2cc186603008e3d13905a54f3eb33bfa5dc85086817499b8786e4d010001	\\x7894b5fdb4001b1b07d7dcdf408ddc4eb0c4f8bb03405ebdd188033ba0bce5790dd424d5a8003970a09a6c8152069c62b69c10817412a8b99be1f9ecaf503404	1661500009000000	1662104809000000	1725176809000000	1819784809000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
89	\\xcc2043c55d9bc14c482d06204e4c25ab1becb435d32391b566919b919509a5599be7df39d7d38bcc2ad4c052e2b861e4758fbe9235bd27eb29d342be983e009d	1	0	\\x000000010000000000800003b1a4d55eb7f7c4f44374779efea533db211ee03444ec505760847cf1c297422fbfd136903820d405dfd3b8772ce31c21be21227011139143d50b0f2a73aed5c2ff0b59effb2f6e348b55eddd94df6e2ef53deda669ef36d7566da05503c19a5d88063a38a6247e803486239fbbc42511b49059aa0a5e3375cc218fe23013fda5010001	\\x9d06b5095e8ddafecc7d4decf9775efad4d907d534a63e3e8ddbc8d3a364e4e7acbcbd8c052db27ae1d8cbd4ca367b7b537fab997c687741575f147a83edd103	1656664009000000	1657268809000000	1720340809000000	1814948809000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
90	\\xd190e0f41a00911c82027b86d3421f7e2d4d5606f1da47df7dbe238a3eb43fac728bd145c396a46c46625c0351bf2a6c5a6803a3892a987c7aab607f0eb0a3c1	1	0	\\x000000010000000000800003cfeae01b697c0594106ec626451728ac7173e74c43b8d59046e2f32fbb1269feaf62ab3b3bb4c8289c283b0c4f0bf9c6379e5092396d69b9a5d4822a8e3f2cbbe301832bd6f18445dcf1be68a2f2dfeb2951caee5eacddfb6f7fe657bd7e422111d2ce47e331d30b8b257c874a9ddc554ff537ba9be341b9776d0076ca02107b010001	\\x100df3c7f3e1c11a71b1b4fccc091c77052104a0f12d25c1ae98c50f9fc4334d4973dd74cb01e4dedb409b059fd586708d51473ca143c3ce0e3dd6726d4d8802	1668754009000000	1669358809000000	1732430809000000	1827038809000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
91	\\xd210ccb9ed7c0e0a81ceffef39c55bee34a860282a7fab5a98a2708b699e504539f4d11061a08ed024096b51e1f730f535b25aad14d20dd4920ad813851063b7	1	0	\\x000000010000000000800003da7acf01ccc39ed7ebdd9ec423186fe40ab205075585461489c6dc762d7dbd7145d3ab9d06b0f4904cab9618c3213832fae59a8c6011865003c080a3343ba5a99fbcee0c949286ef2373c7a6e5c70409a43083242051cadb08978c3948823fa3ffa8b678d838abbb454bdd8974eb33f04e011b52910ffbe82422ca990e5eefc1010001	\\xe16d66764dd9444e8fb25d618451c4aac409ba958cd186f2cf761afdbac883ee0495425d0d766ea952747f6e13a6db5cd87c2215d6df25234ce1edd5f987ce02	1665731509000000	1666336309000000	1729408309000000	1824016309000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
92	\\xd6dc54224a11f888150d7ea295f489b08939a85d7a43bd064f8e232132f0b7a476678ba03f8f79b3c36a4cc5ea586655d42c2b2c0e7e59b4791a31627fd35405	1	0	\\x000000010000000000800003b5887336dfa8091cc1396eb910fec6bb881538fbb17df07d4f865a717d6342c5723b8f8f1767e635ba494641bad6acb286c5f45a31019260a7395b3400c59af6653237ed99a45b312a4adf7b33b17c0e9b9aa55b4e12a9c981eea54a8f31b2fde5943b1a8a12fb6df8d4371cd88cb9d52244e82315ab5da230db80203a416819010001	\\x5b505c02ff456b72438311f184a2170d636f87153b2ca4dc2a4a47a275fc49d91638d120a8d1cc71e362acfcbc7b8d22f49f4c2c958a2a869b7a13adfda7a008	1660291009000000	1660895809000000	1723967809000000	1818575809000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
93	\\xd9505cb25f4cbf7531dd2bb0b9070f5e540941340f9cfb94370ffe7eafd4d20df86ecf49189e54a2d4e7cbabc2007af805687aacff58454a71bcb69fff81ccdf	1	0	\\x000000010000000000800003e5306e5cc4b1900fc1eb15d076c01716d2e92517d3e8c3d0ac8a5a4f7ff5e18d6caca88bfa38b4eff07b0463898bd4467045bab4a35efd6c33b14763c130c784f31fc3853af961dedacc3c4b3ef6353f95d0995346e299a7333c030f45a288e4dea0e6987eeadf196e4250d0cbffbaf1dfcd8fbb7fd6649511005608de1169d5010001	\\x3b830742a0ab83b91d45923111dfc40eb4de6ce995eb734b7601ba77609dffe076e8d353551220354d87bf8b026527389792f39f5c51da7c4599e282bc9fd503	1681448509000000	1682053309000000	1745125309000000	1839733309000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
94	\\xdaecfe61720ae275058c8fdff03d31811e8fb127d502c32902fec77bf3efaf82799f02cd1faf3080ff4dd0edc13cf61e594751bb9252b6f1de84d6b662f92b5e	1	0	\\x000000010000000000800003c1c64e3204c60a438e89529651dbecf02b5ffb6000ecf533d50240ec11b3d6c4718e0522b5fe3c2b9d08d2a38eac77af86251ebdde4261f8f80b38e100b6fb9b8617c1673fdcb607d0cb2179c0b6cf9b7d19c550364cdc9ee774daac98fa620818030b14849d5a85bb0d020f40ade44e11cfcb3dbe1fcfc46c844c18d769a5f9010001	\\xdfa91f9730e3f467a4b3956b5d8c0f58cd781326ba3c7bbb5e1b126786eb8262fc75a2ae0b532f8a815bf1a596bb9447b0b43ea2b840ff31c457e8e39b20e007	1677821509000000	1678426309000000	1741498309000000	1836106309000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
95	\\xdd888ad2d63243abdc75688c349249700a11712284e363dfbcc12defd48e04d0954e16ce06efaed9719f9f8936854a6af91166e1e6a68a9a3b162b179acf844e	1	0	\\x000000010000000000800003c032d853e202adb17f831422827698794e7f6850c36297020dc6eb54d45da0962ea7e2c0e2f2aac12443038f8a4629341123acd0ec5e383c3e215bb5265b0a1ce04eaaafc512a440fdddc12b047216d099632fa47b4f63912470a554f735da127d259f07524536fecdda68fc1928f0c00d3ef3b75f61f579d8cf8ba6c02a7c05010001	\\x4ca088c07605181d7e125d418a661bee3766b37b07387a2a1cd7ed421dc5284c535f503850bb4cecfcdb69f09bee0aba0d472a8518276e853674af7e143fca0a	1676008009000000	1676612809000000	1739684809000000	1834292809000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
96	\\xe11cc233ed0bdb04a0c2151fee863c8bb460e0eecb16e4d59afe0dbf0020e928b62a6bcd6783cdad5ca5c07825380c95c3c429cda0f4ebaa5a1f0c35415134de	1	0	\\x000000010000000000800003c8f3b566729763f8ec46b1d3c6470a82e1d61d7d1c6bac2313ab6d86e1aa37aec8da28ab647d2143fd4125a8329cf0da3a01d1f51f1e18c821575633cd4978723a42cf4d4e82991e583dac1ce7c26b2ffe19db0e32420e53d5a89721a04817c4731df49583339612f456403ddf14d74d5501afd336baf8a94342608581313585010001	\\xc42bded8736ac2ff073d147bb238b74bd906e2afceb4fd2bd2c5cccb44e21f51eec6cfe779ca9c428b0672865f8519d7a5b0b5fca35ceb5855d72d0754264603	1680239509000000	1680844309000000	1743916309000000	1838524309000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
97	\\xe2289408ef55db1c04dbd3149c8e93037f442f4a0b37c62cbc9462f62035865da2cd5e65328d9dc2c9ddd0fd40dcd94a5220617e83a63f3cc6e3072e463fad13	1	0	\\x000000010000000000800003d3a9544185070868dcd3f6655805b1049770c2c664e7d489dd12cf64b7438217b72d48a3c648af4d00833618b0c1df4e74c3fd2b45279a271b31a24a93fffa58b96cf448681d3d307c25209d01795e09504608986a31f330e7730177cf3cca907fbdf93478b3fc2c64a7b75567d292aa82feafc0abd653faf7f6b81799bdca49010001	\\xcf79818611a2d310de4a32c4de45c7221f47a82e005843173abc1b025902fab189d0553744aac11b001ee84bc11047c8dd28adb2c917519a427ce1e07341f70c	1654850509000000	1655455309000000	1718527309000000	1813135309000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
98	\\xf0f045874e2f62b8cec352aded25bce6653b25b4f464a367e111a98f95b4dfb638a1a8d82b70d6d35e73d4f03aeaf4fba1624e85e0fecb83352150444ce47c84	1	0	\\x000000010000000000800003bc2f2b86690256d58192b1732e4755a285d986ea7b6e77fe08dcb0169d9aae44b00b8af1b3c00878d0b3b1666b2a977b36d2d1bba0eff0d9078c374e012a50914d6ab3ed51320062a3d6a00e6ca6ff094d9b3cb398ac85e9c7862b8560698ec3e26e58bf357eb89dccab6e5dbe26e259f037e2c0cb40c8ec4c6444c19d5c0bf5010001	\\xbf8b91b876e1dbf78291100d256ca18fe9ac652d1f09cc146316045898879cde2d9a0de84af430bb83e9781537ac2912aa2b4a52c3649d80a9f45affeb004006	1669358509000000	1669963309000000	1733035309000000	1827643309000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
99	\\xf23cc237a8a5ca51d0078226a6862e4675f51b8baa26dafe035fa897633eb75cf4be9f7bb8fe189512de00d9573e861f52cbd4c73369245fbeeca8310599118e	1	0	\\x000000010000000000800003ad806a3c439ed331ac95da6df7718bf3514cfad8b14e275a69c0993f2c0e3ffc882a1026c4900f945b8d35996ad9cde0df770fdb69d0689796e116ff5e1dfa79ce3eeefee0a4cb58d03a6e763baf9e46cbdea8c396cf58d59a9598d48eb2356823079493a905f5561da8ce6349cba34e28eb0eaf20439aa905e558d69a2ba503010001	\\x59c0c261d7a31f72c827b6635deec1fb50826ca0ed1df5a859b69d46765295d34b400cafdb5388bbd64e83dee139a268ac8f233064adbf8b00ac11ecd8188b0e	1673590009000000	1674194809000000	1737266809000000	1831874809000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
100	\\xf8b4eafcb7b80f263044358ff983cedd6adab4096e6100203dc98c34b786b7d27e4892b4e0cb7992ede744b0bd780f82ec71bf9b5ef572cd6c3ad811bb7fc5e5	1	0	\\x000000010000000000800003bd049b16470e8c6b6b0a90e4d0930bce7a7a652ead539cd3c141c9cb7f45c9367b1d6433e8e57d2dc67e1b198cb2c3bc28dcfc1cac85f39dcac5bffdba0dcd5e2983e30f3ddf56d5aeca1889b4b518100e626ffe8da539cdbd5eae047915c361cdb561d8ca00bd67acfa1bca21f5960fcf1887636531ae18458ee8f8a76465e9010001	\\x5de4ca7afc4b4da766c318bc31b0c364ad0e0f7c7278d582e73dbc960baddcc52d66de2527db1bdbe2448b8ac605de569fbb50807c71373753cfe0013d84ed0e	1650014509000000	1650619309000000	1713691309000000	1808299309000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
101	\\x06717ecd8c8241f506dab473c1f286f2be700a31ab08155da11cc4b7c5a265054437de79ac96794a96f87f53ac7d9ac65c04f2dbbad8fd9f4456d09b3b0660d2	1	0	\\x000000010000000000800003a225a3dd9da4489b6c0843eff53df36e19d54d34c2ee88314fe543b7ea6110adda56042fc3a5dafbf0e4aa05fe2dca4d9241d2300c84ea1fb3b0074fb8efc8da7792aa97684d3c8007c9bc611122fd9112a9d54c8232f05ea0b883b308c33a1ae68e186d736b88f59fe1b1bedd7a0207d7bd2c552cbcd661f0bf4ef85a5e9809010001	\\x6e14da74ff87b03fde193210e9d029fce407510df2e593b7b29522c405f99d1943840400690ba657b8a8da0b5eda81f9aa1d4c8b94e0d09290350232609e8003	1656059509000000	1656664309000000	1719736309000000	1814344309000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
102	\\x08715cced8a5116a65bacee546a6e1102f3dec647cc5ac88ce43c911e225dc5accb65b3ce9c25b409e0ad9821c39a8494922e1830aa3f116bb819240b027c8ea	1	0	\\x000000010000000000800003e25059904620b2d5101964779236a798377d07f9b9b45c29450ac56b10b2b77b05d9d38f7f6fa3467b4a2072f65c7de76105b0742ed749e5377bd6614a99d70f7ae9981f4303f3577af84254c60a39a1c0fa1035dc78c65e1bb53b8fa9fa87d322c30d9cb645089d10c67d25203b8835e31b0637e437c37268e7901412a86f3b010001	\\x9c9e6db6bd3646b0bbf7871f38a3c135b1428bb9b1d8a39a9d04cedc2ed85093f969e85a72ecb0fe8a2008e417fc77efa58ebdba75dbecefc991666936112404	1665127009000000	1665731809000000	1728803809000000	1823411809000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
103	\\x0c69bb0fa49fa3f930e21b14fdd6b02a132b247375f8223ec4c5ba8f9fdff24c2eba1af309707f51682009d73d6f64cb234426900b231b42f83a1db3dbe2ca22	1	0	\\x000000010000000000800003c228bb2016e3b6ae65730c1491d143467a299fee17c86f506877df09ef780fd6f19ea8d5125c047101e1bd440deec67175a1fccbba2ebfad2380becb50382ce28b3b9e78599415b2e59618b3a815b4a765665f7244ecf76ec59eaaa058fb29901b4b0f54d4c3d1ea0214f41e304d790a6b5fdf56429e92aadf1c8c1d258d258d010001	\\x7b89897402e0e49a7541a18cdce4b2b0ff8d3e5364c633c8acb299ce4b7bb62cc1678c08434847e49c264925512107ee294eaaabb9ac8759cdbe18e25881b90e	1661500009000000	1662104809000000	1725176809000000	1819784809000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
104	\\x0eed24b51b275df34c4d6732694ed621fd55406759ba3dd6f9788d6e9693050f05bb16f451f363856790cdcef9e55283286a8f974f7f256816d73c2b871344c2	1	0	\\x000000010000000000800003e151f6ecaa9cc88709f14c4a6cd586d4ca60aa2c12bbaff70a15aa5f336c3073a5f2fd51110e8d84dae5321aed074e34c659aaa5a7b005c26123df62ed172423b130f28e6db2f40dae5a87cfe3774604ccb62a85e7e02a81ccd75c1c0912f278991344820ce680adc371127a23a14840afb2abac47beea8722e4e9cc34658237010001	\\xafef55daeaa47f2d3a4c6ba3d51a360b1b04c601f1866100e900c0cce88ff3b092466cfc833f4eb4d158cc1c0241bc1735431c5599bd78bb8fb6b31ebe4eac02	1679635009000000	1680239809000000	1743311809000000	1837919809000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
105	\\x0f892dcbd096ca24b95bd9f799c09a2aecfef1ceb0b5797f80c4e664204c30f3b2f79b0322a4e2d26e69a25c32e838cb350d4d0de938bb332894019413f56410	1	0	\\x000000010000000000800003d8cbb4199ab6123bb36d26a93a0752af70d6060f8ceb77cf74669c9c826a510ff83c1a190cdf7d537c5c1548744cf44c02d62a0c6299f32798b14d0b0b4430aac30a260544387e54e5857c3bac02288d10ea643b451c35d5ef467d110551ca4d1ed2d6d7502f35165c6d2cd132a87c231901713117bd467022d45d37ba175659010001	\\x08d6d2130cac2609b0808637f0317cc3444658eb907578d64ce49b1f23a4858022cc8dfa06310f6cdd04517c67fc1599dfec569f7e62f625302550754f633508	1655455009000000	1656059809000000	1719131809000000	1813739809000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
106	\\x10f5327a1c7d9a669840181ac51dadb64fcc0bb1831bfc0c3d352b724ca7c7d9badc45b9c40135fd1309e6486a2d0c116400c0ec532581e3616fc73fecec5d6b	1	0	\\x0000000100000000008000039c96a961bd464419088c3116cbbc657d3b2c88cf98fd9e79d6861c67b1bcab5af427b778d0bbd8d4a2b61258ed882a64f60dcd24f0f847f2bbcfb8bc05a67e7d036c6c9fb09006cd9c8a404257dfb6d0e55fb9edcf98472f4bcd1e3dadd7e687e8793b6472d66688d7398f81d7482482c1febbdf9e991e83a96726d6211cf105010001	\\x842420de093c6062e8dca116bef2fa5e28c45e564e33e6619c908ea3134c8fa2f9641cd1e3e90ba5d41f5e520d02b5be812f01c3849aff4b7554ffc56f6b450e	1657873009000000	1658477809000000	1721549809000000	1816157809000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
107	\\x11d53448ed0f5883664abd3463294130f0c12206c221b4e36b26d7cfbff76860cc5f44eb89dacca6daac1f467b8968ab2cb0b8f1df1c3495736398673f002556	1	0	\\x000000010000000000800003b5a86ca20af0bb6854345437b518fc34430076e6903361046a0fc10bf723fd3d89d22fb43de43c50a2e86d24699056697e260c8650d88510ab86832da7030bab5da4aad9489d64eaa815ac81eca96d68c4c14718bf81fc4773d6000a794371a9b28b563d49232841adfb2a1186d67d42d4a87a24c04e2082c144bce330a4a2b1010001	\\x61b1d15c9e77d6ec13744e6dbd7bcc0f0a5826bac2d92d4abfe61016bc22421794ff8b03f8fa26220127e750905344cfcc22074810f6ec5076ae06d98168d206	1667545009000000	1668149809000000	1731221809000000	1825829809000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
108	\\x129596816cad43cb7b6589f44b90c6f69aa2d0e70d64460b7159a5ed9295b46f7baa1bcb435a4a5f08239341e2a15d15c17ad27affbf6a7c136d6b2167c6f09e	1	0	\\x000000010000000000800003c4d1280bd078cbdd426f41ed3006c63e2addbb348cf0944af0ad575a987c6f4dd5052cd54a7ff0489877ebfe9133e8b4efb05c77ac79609b6e8f0ce9012f87d23a4a39eb5a4457f0ac1afdb37b34a2761c7b1545b739212e28ecf1e37ffa7019fc4888bff64e76343efd5ccc89d3f359dc6d153786d28cc16a8e29c53f10cf3f010001	\\xaf00a3c6077b494422551ba89ba514d3ba3c31e22348f90ca4810bea8405e8485ff16684cf72e8eca8115c142cd4be7e4f28ede2fedd48d5c2e29b4910321706	1669963009000000	1670567809000000	1733639809000000	1828247809000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
109	\\x1741ffb19cb87e7a4aed9c94dc56b32cb09e0555c043e5ec09252147b942784ebe4b3ca7ef0a9e049ea6eb8700617baf5107b954fced0e9da2861343793ceed3	1	0	\\x000000010000000000800003b8a6d8102f79d6862167cabf3be7c1410dc16e21ceaaa23336a4883104ed5ca8b7514e7558903b055ad83a1705c6f5f2062671ebe3b1b29ad7e74374d3316e3b665b8a83a29e6b78b46be0f5a0a1658f3e81e1699a07740b8141cd09ae96237238036a77d4b625d23b16052d0bb327f6746b72e8a2a113f1b5ba64d20eb87dcb010001	\\x20e9be37692465641606ddd7f9c9e4b141396d3e2059fc9b798735b692edd0cef898f0cb6b64321351e478d560f314bf02a16469116d40a855b4e69421b8f407	1679635009000000	1680239809000000	1743311809000000	1837919809000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
110	\\x2059a92aa7237f871b9e81cc2088ba3a6cccac009870bc5b0c19459d2454301bbc8531616bf69df47642a4a14007f5f96b6e7548bc18a47e4174d4fbcfcedf6e	1	0	\\x000000010000000000800003c9962929bfb2127b3161b83334cdc85b318c298951c6a53bd748d9a0f75d51e39757d726e32ae78c60be479e0870b49ebb9b886ca395695b72666bc05ff0618f262f9639fbe5474be10313fa8effbf6acd1584835c0bbd5e1413e5aef2a651ec2827a3cab5e0cc34a597dee1d6331f4c514936bc46e9f7586873712546e39f65010001	\\x0f9ab0325ee6198cb4da2c9ccb1bcdb71f606123bfa194491680db2d371edb0584bc1bdf2741ae81bd3eefbdaa3bfd8f9f37361eb9dfdedfa476dc61c4667403	1671172009000000	1671776809000000	1734848809000000	1829456809000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
111	\\x21e509a9398193616292e215125907a35f79da3f58258b706dd0905e7544eafda01b57e5f31ca3d8ff5dccd6a301ad52a1678ced72f5264d18d5ff0fffbf100a	1	0	\\x000000010000000000800003cf77e787cbfbbf9680c16a3b076027a46d0b49ed905acb8029c17d3b57ebb6dc0d0881c9c36f9948bee88675cb7e89b23abbc69dbf2eb3e6793b7f0af15682708f179161a8cde9bd556b3ad70372a4f99d4a6be6e92f30f8a403214ce81c159bb834181d985c4574a967c0d2c94ea8d01b7f8030e8d2ea142451cb3db6582c19010001	\\xaf01b4b768315af45c7db0afea1fb86b7e513bc4c87ead20d660d6218cd3a71eb52c0fb287ce20a97050374c1c719a38f0b44461a7de4e438ff2f4408e4d8d0f	1664522509000000	1665127309000000	1728199309000000	1822807309000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
112	\\x23d9dba2da5d63b4de74a46095ce549d5744a687b4e7d09df06fb2e847a607068a25d45fa6694846ba01f7d1a8a4c6978407ec8229a2a22b892a54564784ee4d	1	0	\\x000000010000000000800003a09aabd2330b7a60d939cbd8f46edc54bb36fe4b4dcaffb731356e8adee43da0a43c98799f51088bd63bc0ca21cc1a9258117065ba0a5c9620b2e819c6e84ddb4971289adda9570afc9e464b285c0a2e05de9c9746e59d40e6fc02c2524cde94c8f190af801c59d1ac8c9e33eedca05e93c88d8cba9595f4ab5abbf12e93f117010001	\\xa8010a54b679c947c9be5ff80661f554454fe74fbde4be59cf8a55d84b2a98ed6b7538f31cfb51a26b2b54a6e9b6aa2af20b78914ffbd245f485542b29a83d01	1653037009000000	1653641809000000	1716713809000000	1811321809000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
113	\\x23a1ce0cfb02092dbde85ab0d889747093c1d6b381934c9d3f802d236013da01424e64d56d8a14c3b6a68a7fdd071be0f9a60dcb14091e98573b15056f5bb8d1	1	0	\\x000000010000000000800003d1d7fae713a3539aa6d5840af44a794b41bc969d40a0e502a8bfdc6eb0492991eb4bfd107725725cacc4850c497d9e998b04fc3d0d9023b0c2e3a15f80fd9f1d904f9f1d325d4a1dac2baf7ff72e19abaf259956e2eab9c8fee7378b0ada9092b6468496cda9694b4071a76d5eb2e227ffb2f10782071e0d36e61c0c4ba2b267010001	\\xe4cd02bee4f70c27f33682c2698911676e7d9f3b92831a4b451abb815dbf8329d1a2c1575f063fbd435434cfaf7885c45bac15b117dd0fc3ebe953735d141505	1653641509000000	1654246309000000	1717318309000000	1811926309000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
114	\\x233dfd4883f02a0c47ee70b8d0f501f2c1715efe89c727b2c8c8f3cf997f1d136039cef4036b6ba6f563af7d9c6a8b429402ae37314c6f3e33057fc6ee0639d0	1	0	\\x000000010000000000800003b8de65e564f6f0fac38f610f92cd09a8db3a5986a04a5462299f93ed134297549633f2a67bb6a2274ed8c81d758e680d6aa6bf9b3be5fe4125461ff821b017721a4d268815bcea7297c71a7d01415b97546a75d47ff4299888b9e1995f5fd35c2edcd30b714bc468d6a69d316eebc36ecef6154f71562ee09219c5431cfa4355010001	\\xcfcf10b1f2bd5039e75be25b4f0c29b7f2c09190538129222b9ae84452dea3f5be00b78f2a6506971beb08ab5bf30b5d1ddc22729f296cf0f0d00b9a25586507	1650619009000000	1651223809000000	1714295809000000	1808903809000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
115	\\x23d145a902a560b243444bda4a9beb8f7285a9a873e2a49d64d66b25b5ff08f5511c33e47000825b0dfea40bd9c2c731ea199626de0ae6206dc266eb54ceaa19	1	0	\\x000000010000000000800003e6172a95a260dd7acf82d1922d681f8c6f1b87b499109b13ed5755a11ff01e52ffbcbf15fb7f4ec93926a6501ccd4ac55d10d2b83487f27d9f19a97c212adc00d5a489205eb3a4a103719773d1937cf0560d642d6a3387373563170a28ccb61f77519b079b3b0468834a51aebb1d4c49674d144dd61b47abb166a149c29dda79010001	\\x0b71eae23df3972fa6e9f2e4d83c7dd4457730c377858389f96760940a40142b84c0a77cb37d45fb3bb0b2e8eda613476dc4352eb71df9a657f3751616fc5805	1657268509000000	1657873309000000	1720945309000000	1815553309000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
116	\\x2fd19fc095df31a0191fc67641403c0c17c1dafee00aad8b199f1cb3b087f5bb74efcfde27b0f18e9ef91796ae676abe2b0f214355412c3cb74f98dae044f83d	1	0	\\x000000010000000000800003e098a40553b5909a674edb39ae41bc394bc8eb4597d7fc1dd0b901d309df38ee297e97168e8b7feae40de963d138ce93ae71054966f7b420e1b14647353cbcbbbab61c496f7c543d883fcc869a8c321ad3396447bfcbc9f95eb4506e23426ce4c207798fee824616d87f38ed01487a57558ef25fa3936f587a468d288b6b0033010001	\\xd04ea455b87285e9a2dafe67e2f02db182475d927bcb8e58f1c6660d93ec86e8905453126bfdb6df827f38dc40e11a42d1ab59252c2b34e1f753c2eb1b14bc02	1680239509000000	1680844309000000	1743916309000000	1838524309000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
117	\\x2fd55c2df1102d38d3a8f4b2703e5722f9d72628284df1f9cf9e2f42dce84e6dda0547b8b9b176ef8a5101f357eaebc2164dda53fb216e1e572953dfb5d38992	1	0	\\x000000010000000000800003c5aa4d83f147168b1d00f849de6025322865ad1841cdf46addb748177062782866998581f58a7fa17283a57c031e4620816c0e16d8182897aed6acdd278bf4d4099b4080b25399a4fa4f7517de018efd19840b69587bae94e8f673e8a54df883acdd31028579cf568be15ecedf157069d58c8a2a75a4dfd9e2d2519dcbf1a88f010001	\\x8028184af1cdea2e96d7e9b3afae662c48a2956902c2c964a3e66b5f4265715b08e129a3444234ef509ef1d05611269d7fbcf98fb084ee5895e97d911282070f	1657873009000000	1658477809000000	1721549809000000	1816157809000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
118	\\x3addcf60fa1a24c31415499337d9f510d94cb36c9977906fd66806f1bc739e4177b5994ece43f17caa8d0f71bafbce34bc41af97d34aa1148fb29a4807113002	1	0	\\x000000010000000000800003e1f4343321e1d537296a6def34f8d3dfa43ae82ff10c5fef42a966a77b6d6bc70324719efe4442e7bab516b1be3796f430d70cef177e24ef6557706fefa09417bc58ecd95ccd79978410e0b65be1f6513d392b772e1a73f9e6260e1649e2e972571af70957b14dce6d4d08c0e6bf1ca70815ae675f1f5d19eccbbe4fdfa6cfef010001	\\x1a5f081248f9776c29b1f7b9f06fe3a3b071adce2644e0a324a43df7ff140d7c6ef0f27f415d93d092c6b73a426705871444bf8de632b17d852100828d9ce002	1676008009000000	1676612809000000	1739684809000000	1834292809000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
119	\\x3fe11a0b0a8268aaa076911da3d6e95a15255c87cf15b91af9e844334b64deafd16c385ecfa89e60f552f3fdcdbbb626ea8b7ea9d1860d3047a94d51fa8e2558	1	0	\\x000000010000000000800003b0ee0ae6c81c3b05fed71c6c3ad82f95275b43f392db93f98296270d631c9e0e5001ef37f4a143b7ce853d2297c2cdb8bb2887aa05cd81e9a828b71eece17eb5caf85a675da25559044d6267c9bb7ead5f994c67e7c55784a3982e741f3248c6c96c15320718a18655768656d227e7ba3c2be3d99a05dce47a465e63e57da9fd010001	\\x9bdfedae78bf6466f6449097aec99db2620395ddbdd72b71755481f243b400c052c81eca7d57a35222611e040c1aba44014b2f48419f70f4f15270102bca9e01	1680239509000000	1680844309000000	1743916309000000	1838524309000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
120	\\x426179d244da7ed35a18ba966fe7bccf35094f2615c4c8a66a00d3ab824c37b8800c8cc84bab63c8cbe5b855c91dd992608aa9cb480119d0a450e117ff9a9cf6	1	0	\\x000000010000000000800003c8175bf384f19a8ab6eacb01e087c38182d95182501c5bb15eae17a5f4c441ee74c7db708902875730455a370485423cece7bf498214df80142c9484d3324cee941c1f1e100bfadee853b1126783f8dcbffebf2a4833a21c0f9c040a59283b9b0bccd742048c4ec10bbd7a33cb419cd350b2f10aac9814159b468a26abf83a05010001	\\xf10e8a5bc78d24dc2b5cfd7b66f217c1b39a56e3f3e02fb2e42748e9224b6977102b8f487e35239c0dca01c51330d14eed7144a4af4561003034961c04a8a701	1659082009000000	1659686809000000	1722758809000000	1817366809000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
121	\\x45397100dd52f647e90f6b843ed7ec40eaacc8b49ba91db440d7cb2d54f3a4994fddc9b31286bb116290584327710e6b95f61f38d4da0a03b13a287dda01bf0f	1	0	\\x000000010000000000800003b7e86e361e825598ad768392b567a49e45d26b34ed159a70b0a7701d797fa115f45c6adc3cc0b051031d072b3ba73fea864da6dce2102e0a48c1b5e0c0ae15fafe513112cfadcbde4c595e50bf8398245c108aa55248e7fbe1bd4015e3621861e9bab14f60d74442c5c11c8b6155b4c2e1a71ebe4cf776909a5710a8e11e5f1f010001	\\x35fc31fc51d27562bf1a58cc3ba4d41d19fa26c471979671e8443f6a695c3c814ca8a13842c7064d2adb818cf753bc10c100be2657e8d6e4ee8cd71f1c20fb0e	1662709009000000	1663313809000000	1726385809000000	1820993809000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
122	\\x4689383503d6dcccd0600885c9060e9b6e85c19a85f33d39f5d4cbdc52c86987acec3d4aa5c81855adb7881d0b3dec91da514d2c0d46f1d2c9e70eee1d09d897	1	0	\\x000000010000000000800003c1dd8c44432acc1850678bf0e966e8d52372908cc4d5533a84d693a1b11a0ab3e08ec33a585152c594e0ca3f95f3d98144cf1f2a4cd9328c45336fe8efd72dcb8d5f29d35d79d6ffebd3cb028e24146144139cf6a5cb38c25bb7afd5afe3b97e9c7978c685bdd8ed3a5b405ea799d336ffbc7ed865e654d148aee148ca7141e3010001	\\xc3714fdf1aafa86cc34e1b9033e1a17de5d6879f2cb486fbc20044dd41c696cab4be31efec3c2eb33ebb2b455d09f441e3f69b358687162e21e8042ca0ee9008	1674194509000000	1674799309000000	1737871309000000	1832479309000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
123	\\x474de6f65d268657df08fdc86aed61245a21be8c46112b01a0d3394c03386d6ea8b4fbb1a2e3acbfd465a9e897580d3eefc369436a5451b77e326c1abaf24052	1	0	\\x000000010000000000800003e6e450039b48887a5849aee95afc338907a4e08de9876465cf876c45d3dbdadf0d457b4776f80be7583ef16f9d3ea5cd26590c79715a34e96dbabcc80779a77e199644a30a9f8d2f9037f725e5c83cf33da144ff03b44b6785f3b93ecfab81315416fc7b9922758503dd285b2f9feefd39b55f4b6f9496d4fd9ac2a1c62ab11b010001	\\xc62462fda80fcb68ce7bc2cfbe19654a250e59fdbb0d7dbb77a397178f2dfbaf5ce27465a09e29fb13d9ac7f36e7abbb7360f093fe9f247e996dbdc958e13907	1672381009000000	1672985809000000	1736057809000000	1830665809000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
124	\\x4b11dde705c945199a22b34ee7c79c9aedeea29a726515d439cca506666b48719319a0a927b11a854b704d023ea19e7f536634bb2d16ecb8926eb0fb72bce55c	1	0	\\x000000010000000000800003aaa866825e14b90b33e8dbf916733c86d230724f777a2bb7e315258cab6922cee7a3cdb7283151bbb4c45dc96786ec3d504e705e17f35c199596f6855f67b098dd44f427e59cacb41be2c1e8bcf2231d45584e55d8a976f49bb8f4f413df6948b423274f4903d970068245e29d21a8d4b52174b462283d48e071983b0cdbca13010001	\\x85cfca25af3eeaf5582f57097ffc21bd28d146ead4c626c754a0ee9fcbeda68d2dd2d9d21d85267aabc1441dfb37dfcc9b4c27351dd4a39ea8077a46c0945f05	1676008009000000	1676612809000000	1739684809000000	1834292809000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
125	\\x4bf5e6df39f2fe71d0a4e38328502d0e328488222e49802f2928e22f2caded41be2108528249180055dc7ee556bd031035bdb4d3b4e9561eeeee9e3f5ee7c410	1	0	\\x000000010000000000800003c65c80ae3fc706c332befa195a552f0745d030dce5cef9098f9dd50594966a20ed492d6e6e7eb41498137bb5af41f362242c8ad7e969347776f53a42b7097570600aad9d573acf42c5257d82de992dfb044f4958d0989dfd0e9d7546e32c3923e7e694d2e849f507405f5108a2f46f6b0917de82c97206330c10b82104c46a7d010001	\\xd477d2572a402b010c722d755db3525dcd02ebfa1879e983013f131340c5726015fa5767bef248765dc465507289dd3e4e618dda92a56c650aeeaaf2200ac708	1660291009000000	1660895809000000	1723967809000000	1818575809000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
126	\\x4d4d9b1f6cf90270b221a9b88c2ecb8d0d52a33d226599df976a2883dc41282ab1a7c12b15892374565d4dc3c540317d796a8e733ecf5be42a7fec9f792faf00	1	0	\\x000000010000000000800003b77f2d00c331c9349886159e9e1c634d94a1638a594b4f3c8eadafb512b784c0efb4c1f2cacd5343ef77bb4435632a7a892a65aeb6657709217fd6197650086888197c01a72719d26c81f4924eca95890a73e2d04145b392e5e2337996114ed4b3007d73382792d53c806fff192614215de75e1a60f452a69b2c169994c71ca5010001	\\xb20d090d8bdefca88a56c045ce7f7811a0762e07eabcbe15ae3b5aa33004bee208006ffd65f984922922ea6a916b26b00a0d50345e9308c483d9cb7b8d17380c	1662709009000000	1663313809000000	1726385809000000	1820993809000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
127	\\x4edd0872a0290422cfcabe809356e6e5562a370f4fa628e9562fdf426269142dd63575647b3274e4caad51b28ae55b97af649cc874cb0c803f3b2740f8e82788	1	0	\\x000000010000000000800003c40f44f4e979e395ada7a6b1dc4113cf51d2d6871bcc5bf46cc0b0442fe4102bce2bb77ad3c9af28afcc8d73e081163c96cad69e156ac3e4df9af61da7c5d3a6a8f081b6c0abebbc006cb0f26031ce2788fbfd02cda6df78034d7565fa313a46ecdc6dbb475dd674ab2ae7b374e400c37c9f3972a7ff288c281e1fe55fd520f3010001	\\x1f4103d683e63e165da8fd0a7d764496920c3af406e9f1743103aac37dca724f14b1ecee3016db6b1d9365e43872925ead001b1250c28e085287d2f4d10d110a	1671776509000000	1672381309000000	1735453309000000	1830061309000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
128	\\x518980e70df3018ec3137bf17465f3d1fedd28919de6da4a857e5b8a48294dbd8bd2a3901bbd731315ee41d2fe6e802f2a5e030b65cb762edb465be68db73e6c	1	0	\\x000000010000000000800003aed22f771e3525426a1d1f093371fbe387af3cf7159470456744cb0ebeb147e46426f99d0fae6b1908686366eb12c0f5a41dade69276c4d7a72a91a73fdfe245b3ea8ec03df47fea49950afd8366edbb84005140b694ef183afd77f2c618191b69a1b3b894bc31d1ba67c5eb7eb8cb9e1fe756efd9ed2b1c76b37da3369fec4d010001	\\x7ccb5cee3ec71b6493364f3fc33ec38868d9f980135885489b6012bd0670289787d25b6b10a7ef15bbe87ffbc2903e81819b9164ccd1c6793d5a31f3da1d4d0a	1665731509000000	1666336309000000	1729408309000000	1824016309000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
129	\\x5129a3c6bd00988fd6d22174062d856a62704fe4367b96516a7d1fe703d7f6b7c11e39ba90626953708e0269f06766dcabbecd4f58484daeec92dd49445a5065	1	0	\\x000000010000000000800003a87282bf92c55dfc70d14c7bf2bded635af9270959c30bbb9b5bd172edaa5b44c8509b3c54e95e45abfa6c8f9b5cabfb40d3298ec765ce69b0c3f0fa6e0fca178d697b64ad6ce14fb972fb7150fb87dab5f7a416f297e0a69867503e63c301dfdc27dbec3cd084f047a292cc96081323c86f6554bcd7211d2dd115a66ffd104d010001	\\x94ff96b56b576b7544b1dcd74dfea9ccc8158809e77052c06f3cb1103b3d0c8026f52a90ffbab99ccf54da131a6bfd630864f537d7f268fa407dafb00fd84401	1666940509000000	1667545309000000	1730617309000000	1825225309000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
130	\\x5189acd5b4f63c7634246de0e53028d02f0e69b11bf7c4f5605e269614836ff40c5454f05bd470b9426f6ed99d62468d341e267a25d91f25f21cfae335b9e5b3	1	0	\\x000000010000000000800003dc276929024bef2a309d9fea9e7b63f2cd5f1b80f1d0d21da525cc74932b8d6d8098d935cc1ec9b334d86ffdd0f07c395566866d6cc74bafb7ae640ce90c005e656a42fb1570f9e7d6efb3ab697d497c03c1b6c7b835b0c2884a34a6890d059d5e8447249322d169fddb068c324477e6dc6c73f4848d6cf8a29c5d23c41badd5010001	\\x69812a128be3280963eacadd7cd2cc6695b36cb04bc6a6dccc4dc29f3ebad10d728b9b927d7e9e5871e3d7cb4dbdcd3df898280fe1a68091d11d641e19fa370f	1653641509000000	1654246309000000	1717318309000000	1811926309000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
131	\\x5345befe6129a4254257c4992118681ea89364d034099d36f0f394c41c28657c38a4cccef2a1e0f0eed728e5806a5497964c4ec667140c7a952b2daaac641a72	1	0	\\x000000010000000000800003d302d9c1277f47e67ddd7223128e18a498be62969874047a8324b5af6886bc530d88c29ce070736ecbabb13ca9ccaae3b6fb9819302940733f4032789c44534d01f1fb2e03e4cf8da9ad0ff10dfaa32f93e192e4cad706461e92e8b7b835a25d41c90cb1bad1c3d3ef3f09628eed154a5ddf3312b061fae79e6ef7e5db0b8bad010001	\\x07f0c8f8714cd611e79b7058695041bc8e7576921c7c9fbfe0b287e0c1388da12b0145eb83ad6f2f4803e0886001eefd17ea888c294af6bb4d6800cf3906f10d	1680844009000000	1681448809000000	1744520809000000	1839128809000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
132	\\x552925476098018c2f6b7a7b4e7e20a13b6aa34fd7d7c3a7706103d50c542a6dc5b764307413fe973c92520d77288f6ad88ce1aefda2d7c64b647d606afb54a3	1	0	\\x000000010000000000800003dc8c0dd818e8e3167c6a876a9849cdc8e3ecd8c63759dea79a249957d7fd1c0fcab6723a929cf51e3725c5414cee5d64d2568ac6afecbe63dca991d35ed5528f6f0aae794d59b0db01da5c1df039e31b1b3666e4db462568fa07b4947ceb20a8ade68d007db631e486fdf64b458dd24b7a516cfa65bc85d6b9ae4acd2e24c7eb010001	\\xef1cfe79119c3dfda8f559ad840046af0260512be41941fe909dd613f51e84116b6a38101881982f3ef131b3171ae8170b91141cecd08cb6cc74a772a774eb0c	1664522509000000	1665127309000000	1728199309000000	1822807309000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
133	\\x5865605dcf6b279cd5e2b2058bbbe26224f0738ce925006369d79b1d18b8bc0d008844a0371f240e3ec6cabe73dbdd0a546d97f55990796689e78425b8af177e	1	0	\\x000000010000000000800003b22a1378c5f79ab0356f6c6bbd85c894423be1b7aaca4c4e1d92ff802b82e8118300ba8b207a044a2eeafcbb88629d8a3015e1bad68497645928d5c27f0d6de04bccff39612c4f3fd2297e094efde254717e3efbbf7c8c3cbbe7c9072da510ee65e3ece181a247357b76a0977731e609d9d64c4df3c937fcf6bde55cbc83fe8d010001	\\x118f379c2bef3d1bd61ec5d1483ba4ca536a5991091183f7521a4aca409567780b9eddcdb65d82a1881c4fbeda10ce129bf2e6b939aa874c5fa99f567bb0b500	1669358509000000	1669963309000000	1733035309000000	1827643309000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
134	\\x598570fdbae379362057527772c69eda76b9f46fcf6e0187ec32ad95e0c2ad50c5b6acdd8923df823be6a7ff40d61a13d266fc1df84c8f2627d6a796e309a57a	1	0	\\x000000010000000000800003ad4ea0cc5057a308cbfaa7a97cf0373ffa86b042d561bace613d6899bf295b973992732c7797a44662376771ed669ae656ba440f685cdaff6f3c6cd6eb1991772fdc3ca4e02820724eaef27e0f04024baaff856c0d4eeccaa7c7963d50ea183340b71274d87e653fbcb97894a011bb73b91b9b275eacaa20af671da108878547010001	\\x9306ff6699c6ae71e52a188203a7326af52593ff5d1a9780664eb4c5009613b07c5644887d6312dc329587131d1f61972c8540f224830fb4418569e36d2def04	1678426009000000	1679030809000000	1742102809000000	1836710809000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
135	\\x616d268ff8a84913434aa4dd52785b6053d34b9bcacb067cc1e228f1baea1d1b2130e3f10e317930acec460f7caaefceabca973275d200d02318e271236b4277	1	0	\\x000000010000000000800003cc6ace403ad2a810b731e8d915755d154e58f5773100c50dedadef7b8d6af800225c55c600ec37bc34a1e2310a473a770cda648adf8fa468bd3119f03a7fcd1d0e2572aa12ab6e3f785ae83c859da0460c871995f38addc0114fbcc96f95bed36f90891a9492898a11f53df76f097acb771ee71f3ef8e866602f1a9118bb61e7010001	\\x422cf63dd6765effacc803fc7893e78eb1688fc9b1d8478a93a3ec7743fe96db8bae2d8a0c9429f00db13e2560a94e393a09c4f715530bd8f45ff299639ecb0b	1679030509000000	1679635309000000	1742707309000000	1837315309000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
136	\\x61518e482bc9034647699ad3604477232d68bad67119ac99088605512c88631c443d688a8f16238a3eeee6b51ef4f0cde90f745b845710e8382193bdd5be13db	1	0	\\x000000010000000000800003d43679054b2855efc60b28641386cc260aff96e333ad0ed4b18d00670b5dee5735321e42a963f95dadd46a159cf3a0344644c55b8b2d5383e07567cb63d3d27503c1943878042bc994d04d54d1a1ee703129e7779a70182eec54a8b4adc16a2532aebf7a02969597769df75ebe7270bc14100ab4ca89ac665ccb83c1dbd04627010001	\\xe197eb4300998c3f4be5b005a2a2ae0f40e0483e834f84f7fed0be1a268dedcad9c884f6ba9f80be9bb4a687f34bb9a05f43305362e870d19dfcf0fb050bcb0d	1653641509000000	1654246309000000	1717318309000000	1811926309000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
137	\\x622d39b27bb73fe589a5e4fa234c73623b02b2949353428a2b36ffc30e7c23a58bc0242f75cb0da1c3f7d83b9f5631a084b17125964042b1cdc0e2f937bfcdd5	1	0	\\x000000010000000000800003ad5b68e4bdccd8b926997f6ec220918f33a206571f1eff2ddd4f718e77ba9b9abaf2e587e076d9ab44e35b818eab130c1e1cac0a2589263fdf6a7c88a1a6a322d971d079a2ddbe9e474a70324ba1b64fbf1237f49c165ee826239ba4cedeb28a7a0e30eb82eaef029bc54608e3edb5d9ac6fd9f5ee1f7ad6e02dfc943d64f4b3010001	\\x77386dc16c1246f247e3a627dfd89673fa401140192bcc15774a49a439ec39764f121bebc6b5bf8ebe917f90ceda771ab7da3a37fd060a4343622a8d5f26550b	1650014509000000	1650619309000000	1713691309000000	1808299309000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
138	\\x62791f96336b04a67b1f99ba26a7d10770735c427caf04a69120af7f229732f550ba5e46be1fda9e5be65522b39d93e86f915e2302012b10f2c2e220b053e91e	1	0	\\x000000010000000000800003bf149c1906984a0ae622ae1fd2dbd3bb01b2f2f14896603a8e7971752cce3d8e09f939cddc0ec36093f5be329273142a906a736bd435b14da01d094999719ddcede6c90fe9c7524b89636b7d9c4e1c68f5af23c0141730cc34bf96a96fe2539ef8a42298f6d2b5b3009658e385d15fcc8d40bef589e2642f06235186a01a18cd010001	\\x34ea0a066407a3bcb2516d278f6dfd0d8e857085dbad4cd6b390d19ae11ac8cd4295525d0964e8adf991c50a9348dac041bbc3b1f69a47b4765afcf3a3097404	1658477509000000	1659082309000000	1722154309000000	1816762309000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
139	\\x6219feae9e5d54414b28a5b16c6019f6159302003f75acfa996495f6b82fae1372cda130dcd00aa0cdfc4af2fa208295dbe20950240aa4f1f51565015bac1dd8	1	0	\\x000000010000000000800003a8132404908f7c87fad1d2d046211bdd3c5c279cd74bd6db21583a442cbb705feabb909167612c9a4533bec82b1d977d45d789a42e398c61ce062a02e6fa78c9ef920444361cd6dff3f2b94fa447889d1ff7bda22eb3090b9c44eee2a116ac9fc4e1a7c3cb8317df9a43ac69ce7dee86de003c36dbe4418b455ccd09e0956eb3010001	\\xb8552d2c38f225871979eff824df6c8efdff8e99fa662e5cbcbf06de8d67b96a971b15bae6cb8610b302e7da4d0d5bca255bfcf0fa1317275cfa008604424c08	1666336009000000	1666940809000000	1730012809000000	1824620809000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
140	\\x630d98ddd92fc920ef95006d746ba1bbceb69d8b21b1a2749867a04f923c955e918c80dcafc51f528d9a06234aa5e0d14ec0baf31e512024c1594cbba8a74464	1	0	\\x000000010000000000800003d343c17617dc13f661c0be9f15717359db639e6fffeb510326d400b19f1fdd68c2f30702b1f12e47b305019b720402e83f0e8e6c509cdf2a4973109bcb7ca3e4da9a449b56634024ba6f6a908ab32c030e1feb536d1712d1e681cd4110d4844ec6cc4ec1cfab78198ab1a2c9dbc5e8e66bd6121c122beb6214279ce130987561010001	\\x64e71d246abf2b47f84f70e3ff16c5e09d830caad6ac0124f862ce905b7f633096783f46291a0c354fa81c80466d90a4d2aa2564311470b358c4e06e676ed607	1650014509000000	1650619309000000	1713691309000000	1808299309000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
141	\\x6379a56a716f5f205471b0f5e0aefe21f6ae8a96c6079faeede594e527e8076342e05f7e55d65755c0d45e54f8647f9a0cb48b0a5097e3cd50d5b1c494843f1e	1	0	\\x000000010000000000800003e8eed9329c759721a31e09e01b3b938bf3557fe2a50c4228913acffcc1f3cc8038ffdc33175a07c33c47c5674028a13e156baf7066d3973c560b95fb9c4df1caa665f3a461ae0493131ae789da1ce9b0add12e9c4c0e2c539e0ccca63d43a16bf18ee2f1ea38aaf2b09b989287e2033b63330259b69ddccb06121ebb254a121b010001	\\xb125f49a041dee300f172ff0ea94fef506002dc74028b9a8d0cb70f257195485d0ef6ba8a31532ed6b4ef9583a9b972392cba238ec96f74841cd7529b7ff8c03	1669358509000000	1669963309000000	1733035309000000	1827643309000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
142	\\x64a10a6586d72d9c3ed663efc609a0cb66c1611c40eabaede44e16d45e5aa3bc1ad788de8fbea32f0f267cae4078c19147f7f5d7a6078a2ce2490cc083906d3d	1	0	\\x000000010000000000800003eaf5f6095e49ac5e10d804866c16bf0ce65bd57001f2e46785bedcd81ab688305dce8e05328a40eb8eda5c96c0f39c0896d3a69c8530f5489215923ed4bc8f47778ecdcbb5e614a8c12bec553083f7881cac916f4707af410b56780f4c0acceea600f9db25f9ff1927c779ac7b2fbcfba904ca500ae48ccdcf5b601d041b6da1010001	\\x8cfcac205de573ef04077961b7ac8af2aa8a0a642a0fb5951b7ac138136de6a6ce6efe3101a14b7177c7551c544dcbb7007589cacf4b3d4e2833844da8ad5607	1651223509000000	1651828309000000	1714900309000000	1809508309000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
143	\\x65f55e6228c69defca424eecf815776eee002794c51662bba4a4dc6271be18316860be8ae3e10af5b25920fe918c6d1300df5842042e0e01fc377360e5f12f04	1	0	\\x000000010000000000800003c9757d20a0627867409ef5d658880e1181f449936835ee67f5c4601a8f5f6b9b1b8864a31e2db9f1e684fef3da18a2a31d5622d622c75429bf80fa61af9e5275f85f2eae6b531c414554d86ec5e70ede425d23b6b019ff471890cd4851a0789561f17e9351b307914292e28410e0a83281a788ce9c98a509302b8b5fd729de53010001	\\xff3bc291e8929bb30a5756da23a21b338b2f2c9d61450c3b4b54790602e103fcadeac16ca370ff2777416512f8b3b21494142288e1c4c5a255059d055ba4ac01	1654246009000000	1654850809000000	1717922809000000	1812530809000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
144	\\x67995c30626eecf50374298155dd8dc03a3b403903319f17859fd36c538d3dd31cd1cbc2e3d38040bdc13e7879fd3e40b973dd535f3e5797989c53a37cd3a98a	1	0	\\x0000000100000000008000039c2da72e51aaabf7b3e96c14ac18c323d0d6cfe2d728baee2027c2d405184d8aa8fa394b14c49d59d42f9cf877237b6aaf0cb1cced1c002e9a9a8118bfe0cd327f91566fa61c01afe669158b014cf97a9b50ae74c3ca76c4771f61028b62d5cb0903bfdbf718f01e0c0c6ba4c334b179bf41686f6dcbd7775b9a8d1ec440cb29010001	\\xfa6a4e95cc14461645ea0d429b16f4be6df0b5aab39a585791c9af30b0f5b6efd18a54e216eb95d50560abfc89c2ae0f4f717d729b53120c3a798172b9253708	1677821509000000	1678426309000000	1741498309000000	1836106309000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
145	\\x6765a720ebfd9c1deb4effde41347cb03e2a79adee46de6cac857eaa48453083e97710f8630c32caeedf32a71427869a2a3649c37752337af96e65925ff7d2e2	1	0	\\x000000010000000000800003dccdf6f87fe682417624404bc6e382a64da41e7d84515e34883b31f7e31cae70945d73cfaf8f46240eb84b72b0c766a0a2b5c5ba08a29a4d94ab7888e63dd5bb26626364b40bd09baa562735a4bdd5aa6c49c98d5448f021f52dfadda6f4b9950b938e3303ed1264a8b2f4c94f235d42f11ddf770e2cae3fb12826df0c2ca15f010001	\\x5d554e19d539467681b8f2b4846f88a9d50e9e9779449892503c054f1d0c67fe6f5254c1fe6702c97e4f4e8d533973c3e21d492b9e87e837cbcd0672536dac03	1670567509000000	1671172309000000	1734244309000000	1828852309000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
146	\\x68e5017f3056db58abdfd4ee6bcbbd24a4575c21939ec097cbf775fea895f187ab2507d5560c17884af112076e12c037b703fd08b05c82bdd7ab7ac35ada76e6	1	0	\\x000000010000000000800003b05a959f9d0732140284323a9eb28a9e48a156fbaf4eb50cad1ac4fcd3f865cb1e0c3f298c4ee3302e3d4d018388e8f2a80b56b09d07551b196bd727ebcd6eeb019338907356cea09e4d3ccbed6ebe1fc4278fe412edad03c40d4d840dde5535b931ccee7d3f9c8bd25b76860b94a1382f8a438543de8b26208b081849c4723d010001	\\x863f688dda6e77f9eb176373bc46ed59febfc89c0d8d4ae7951de3ffb6c9c2e839683710a8948bc02f647638318615fb41868fc2f919b508c0260f573b429509	1681448509000000	1682053309000000	1745125309000000	1839733309000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
147	\\x68e5263307739993dd05a657660ac8e9f8bc71bed66d8cf1cc00c9c767e6dfda3829ce4861a532ac1d76e6ce6ba27e709ba617a0add08350eac878e984dbf456	1	0	\\x000000010000000000800003b5bcce2145d2ed3be6a98a13beec0c831a5deb308607b86e8b2dfbd824817ac29274bf897a7ddbe8cd4b5aeb33b4da5461b4a21a49459bc94a0508eef0f3c77a265e2688b2835dea0437c3d647cc461b521b74dd3b4e6beaaa88f464fdb1c430c2ac4b50dc717173e1f89b5bf24ebbbbfefdec79b97bb8f79661cb630ff4ca87010001	\\xe6914f5fb003bb369a55a6aa7aa02b36c4323fa80dd3f7b9fd493554531f54b6f2ed2d6340baf23d1efc3f887f3dbb2ec5bbb9b4bace33e612e94d5bbee6ca01	1677821509000000	1678426309000000	1741498309000000	1836106309000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
148	\\x683d99b2bf897c564d425229e53524ea34f8e2d399a727648d346b4834ae55645fd019185784753c391af21e714464965293d9e1f6363b7a471f1e56785ac9d7	1	0	\\x000000010000000000800003d36428be5c17ecf093cfde4820c5c15b1b0198a2d6aa13207f6e41fcdd9c56d38ee5eda308fbe94302ab7ee264be897f273641182d41ba8f376368422853269bc97bad0cbc5cd07ebfc9cc2e63a729fdb14b90f04e25306ae6b15c412374387f79f5a917e823cc3c0c866c122bcd47c4a1ec952919d27a2ac4d70e6fd0e68fbd010001	\\x57710e010ee21b9d3f717f552f98947b47639c1711c8cb9e3441eed762166833b052e16555fe4edefe4e2e21c71b87c704c430f71d5ec7fc2d7a907225450d02	1659686509000000	1660291309000000	1723363309000000	1817971309000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
149	\\x69dd423be4b9da9b05ed7e8564c0f897c486257bf038e86a599f51f9f873cb078c806ea20ff6be5e7216188d7136cf073940ed896210e40d71cd69992659976f	1	0	\\x000000010000000000800003c8a8b8ba6c4eb724997a0c49d1531c1bdc67b6185614bc7cb5f6937810443d3bebbf151de6bc89d8b07494dbeb75b7eb375bd4c5087689239be8d3cce505dcb49d40f4727169b4d4aab9e877eaa0d57f7e5d6f75c8d4243d95055aed38cd334087c8370f3a9bda38483060560543e82dc5e4434da483e718578d1b7bde95b725010001	\\x934bdaae6c754ec4884baee0c18620e744798ebdcc908f595d646cf839a659e87995696ce5a646556434914d92a9eff331d507807b0d96e66381fb03b81f470f	1681448509000000	1682053309000000	1745125309000000	1839733309000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
150	\\x6a5163af4563f509ca03b888e3d364b2060a852c3b634682ddfed76a7ddeb116ce9ca2f892c99d369fdd667579b5ad3da0cd9229b44fcd69f2c6b0b9829ff00b	1	0	\\x000000010000000000800003be20e32a26a0014f2223aabccfd90dfef306edbf184633f4fb910185245a2faa97ccbd205d242363c483b37d6839fb391280cfb09aab66dd619ec9f2134bf3937ba576803ec08ac49f95cacb29009e4ab6ab9d3c3cf29868b95c50d8388325f7036cc39bb99227e97c5ab2642ae3be5c9fd79c4748f627755f53c2b54affd9bd010001	\\x13b82c3b71cf14b42ef3b0f621c400bd92bf35c26d17fd0907f3355c93efdf57d8000a775a25e1d313e2617692aa069fe275dff3f38d6c409e1daaa7213c270a	1665127009000000	1665731809000000	1728803809000000	1823411809000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
151	\\x6a3d9ef26fbf29b83ae92b046036f8b78440af94c9db2790ea62d2c278569b878aae8fa4e5c4ef742a46f39ae7348c7d6d926d39795db79390c6179a1a14a847	1	0	\\x000000010000000000800003cc9988daf8cde04c2abfd939869a8988326206b4c8db382c08bba0074dad41be7496438dd9fb3044f69507038ece5d6b81872445ff7adde0b3f93a030b6bdbca4ce6d485998ef3dcfb79978d559a4a67a2eefe4d2a87ac36e4edab454a4eb47337282469d60aaed5e9be3cac9b1e82f4fc50229ff4a46e54fd9a27b1121cc915010001	\\xaf68567bb192138848b59c813627293d9a5bc26ec9bbf390a86b4333323885d8425ca885a83c25468a47920f0c9de7cd0b8ef32f150bf3e0cc2cee1616c4620b	1674799009000000	1675403809000000	1738475809000000	1833083809000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
152	\\x6dc5077bd0fa2b8d91d9db5c628be5838653fbb3fa780f9e238b772f22c6dddd13b1736324506ec38fc1109a339f1469761ccb8e719d068fa02852fba346a65f	1	0	\\x000000010000000000800003e078f44d8eb185dafddbf36ad80ce6142a28cc41a6db4f800c162c8c1a6248e04c7c4e50f266e586c6a2402db18073d9b61f3a2d0199915d7d7e5dc34ba1fcd8dab198c582b6316a414486be8ecbac0d14d1af61dcb44cfb881aa43768da2ffb697216e9b1991440aeea1abf2a218d6cd3bb5e0664b52e8afbb3e5d17b19273b010001	\\xd08b478fad87541207086af86905a768c0806916bbe86a12fdcba3ce4cbc6f4c263305862e76c7575045f6e4c8633f00dbb0dce60663d2270787d7fe58998809	1657873009000000	1658477809000000	1721549809000000	1816157809000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
153	\\x78559a69b05474d0a7b8317c578ff7ae885959840bf389342e6383399477442ecac2f8dfc370ceebba863a4cea674b3432b152cc95e4c72d8993fe428263730d	1	0	\\x000000010000000000800003bd8a40d6dc4a0ba7fe91e557772ddef8e14f5595418d9d11c8d16b590fa74afd53ef63d82f2dabe29615be7554efaddbaf29950c5c2d7fbc996cf9e9f102734c69c0f5d1e5ff70b77c70ade22b1e4ab36f25d688ac8e983c606587a0744ba14b7d40398b163336dd8f10c17d735c9520dafe3d567873eb9092040b9f07ff8ba5010001	\\x6e232dc36c335211ef8d00d36766947846d1a3eacf334a40141ad951cd9b22b370bb41b4011c0ecd63bdb8a76f20eb63999c071963e2b9b03f617ab96b7e1100	1660895509000000	1661500309000000	1724572309000000	1819180309000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
154	\\x7ac13b3213725bdd1bbf678198195b9789bbb21c70f49a8b791110d654b311df2c05b5cfcd03f0233830a89f787568362f78034bb55650fd5e0104e16d88bc49	1	0	\\x000000010000000000800003cd20d8ffb1ec344b91083579cae30572d9f4bcd68d3d44f138d4b144b0ca01de7d239366d3394332919d306dcdb474a1426012858937689322cd210fc147ba27813a9b46c3bbf5a6cb5cadf92f0c6cc09e492ea2b303119a7075d8c4543a25ee9f4d53dc6e9ddbc2693dec032278ce503aa1273c1442915af7e3aed392decaa3010001	\\xe6eda9573b70d6291e589fa89ccf2c95fe92c65a1a9026a4e6c775110e8dae7825582b2c98e76b9a24bfb26806415e73666c58e74237eb2eac35d8e986faa70f	1676612509000000	1677217309000000	1740289309000000	1834897309000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
155	\\x7d91faa4ca1d60651e322fffd9646f911216b5034e88aee485c8ded8695a89e19e3e39104bc02f34b5232217b80ffb6eb39a80e4b040d11f0fbab951c4a7a915	1	0	\\x000000010000000000800003bce7fc9f287086a237166d1e4559c0cb5f9d021b50587d62ede3ec46761cf5191e34499467c1e320bcccce637706b8881e22b7557cb803fafad66097a758aa7f200d031a49bc2a9b76f008fdf10f6c4bf89b09f96d96e68f35337eea76df57bdab16cea3a21f5cd6307feb2fce3d528b5adaa46f8de0f0e368ceab0a367c77a9010001	\\xa44ff88e7ee6e447329f164cd33bc10da121d255bc8411dc460720f5c77ef597270a6559b049b40248cc83dd98ff8b0a831b35cbfb6d312b92c36a3a5d50b705	1654850509000000	1655455309000000	1718527309000000	1813135309000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
156	\\x80f1ecb07cd8e2a4c0dde1070f4cc829533bc612450b4ae1424af12ab33ea7a62a1f8cb88f6800c0c4cdcfb543f120a7675477b09e5d7e3f12c6c21f21e4d800	1	0	\\x000000010000000000800003aae025fdbd2a2552e296b9c64ca9d7c1495c28f550b7423acd52c267337d975afecb9fb045dee8760263fb353b6f720a48e1c2db12711ca1f4dd3f668e370a6fd57c0bdfb464bc44b9f9f53e319216985c909856db7bfd5ae71c1c9a13c00a507f8f363d70607b19362ec3d4819e5510c8798490fc2f0796b5449ecfa02c60e3010001	\\x85ebecc6ea1f0e5c5fee811e504509a8357dc68ccd517539510c8e3b96c2b44f3b2f253bb8fbb1597211fe28441ed4edaccc15e76b268bd1ece6c8ddc9dfb90f	1674194509000000	1674799309000000	1737871309000000	1832479309000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
157	\\x83f99f1b39e4d5d95ee81f96c0a4eb3d099e5e4c1eb50b127f8d6d9af4aa0c8be25f0223e355196fba6f7864f311a188f80299bc784bb011cd964880265ecfa5	1	0	\\x000000010000000000800003d5547b7dc1a347c3a35b7c055157e8d0b215fae4293f8296c40ff0bb32a5121a036bd842ce1a96f6c35a45bf1580dec172feb2d137a0f6780cfe15f7560e6d533576f7a158f6d8307024402cc0c238d5e84b9fe9f9518b6079bfa565c2092219c24236675532fed4c66d62a417d87d28c8bab2f4c2682ca0623d36d4b6594967010001	\\x1e0f700c0907eef05f4dd9a6eb6a43e2a1915b1881599cb55125469f7d9cc75f4c7c575ee1a314b75cd5ce191dd3ec46e6a611dcb1505240dbf36a433913cc05	1654246009000000	1654850809000000	1717922809000000	1812530809000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
158	\\x8579eee644e07af0df50e48516c028dece6609b9d55654ccc8f2d154ee7795c6dc0438643db98262abecf4ae169480917d7b926c9cf499c20556f2a8d75a446e	1	0	\\x000000010000000000800003d1cc587ae5b83f2d83dd8dd0de3a86911b690f986d27f1d7be30b74f364a75eb0ca8dd890f1b9c020363d45b6dcbedde4a5707c8f47901685dee8407434fcc6add7fec30cb3fe46157922ffb8736e1f6337bb465840b6680d90d16ac92f0574bfe436941244cd4c3a0d6dc562b67df9792f9465ffc4be5d079f8e2d8694f6c37010001	\\xa36e1dd49191be6e8e0165c319f99a30ab61da0e0530a73bfc694d407018e2c285586b86b6ec17c553fb8c45ccb38e474141af1784f1e44538490a87f5463302	1653037009000000	1653641809000000	1716713809000000	1811321809000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
159	\\x9041b530d24c36980de98dcc88f7dd94559b13fb158ff13d546e421a4fe109493021375263980841ff852f7fc719e7d7b7e7b8c81d23537ced5c6766e8d60fa5	1	0	\\x000000010000000000800003d213b6a7e0b0180e3e2f6e4a3be8ad03207bbe4b54d1a22cea2631b2e6dd5094da9009f5303851f8a53d5efa3525d263d63760182916d25b7c6f727a2791f24344a4eff02f5618e39db966de03ee6e66c7fc0e7c8ce85aff664761a7085f1d8d9f63ea7a0bfa6ef779486472d4840f014a4065160125063409bf350dc5938027010001	\\x86f12b0eb3e6d368bee3eb089e6af306b9313606387780f6c6362163130ef092d56a612762c9d9a751a488ace619d31779b92b9e36fd3f6add0466c1c4a15c03	1679635009000000	1680239809000000	1743311809000000	1837919809000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
160	\\x965958ce4fd60d36d90aa0bd2e8f7c3fdd13ca660886e22eb02840210f503fa0696cdb4042e23d2298412e687c48f4cf3e847eae74d055997df86d5bcc17d54f	1	0	\\x000000010000000000800003b4fb39784b47bcb5b4f08c65c414c856f772abdf92591e5e89c178fbfd2fdfb0590cb04cdbff814122c7070b2ccefadd55b085a1c6a42259fe4e0ad260b1f924720d40301e94714ccec10c063f4450278031f0e5539b9c838fb1316b58893d44cf52ad06489429e6741f558ec3cf8ecd0e678ac6be03c1a960a524f1426b3cf3010001	\\x52ad9faaab057d9284226f4b41abdfe59298c7c45bba4aef9ec0436c6ff0949c868a6fe0dfb7d7a06b2359fb2341ee990631b1462c925b68e772247eb686b503	1657873009000000	1658477809000000	1721549809000000	1816157809000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
161	\\x97d995eacb8976f691ff6934fb4a349a4693c9fa0049007181386af003b82388b539c1d4d559129112ebfbe0d90f5a7b7f711ef273e04eecb2888a0249e42b98	1	0	\\x000000010000000000800003de062a939ebf930a1b423b6971b6bf98679efb7a7cce4a612c1a2523d301312d7d4fe102623a5e25f2fbf34dfd96e79f0616d185d783594fc9dee432e80daf222a2ceb5d2ec11ea9f6489c1c8e8f4a03361e3b40901660aee77938099827beddc4c56218d0a4ff18a376022e533e9340ada683ac653f019558df2b208ada0317010001	\\x8892de0d90936566f928ecb0b772937b4223b6d33a1f5240aa209bbe91248d6d087ca08044c6bf93e3a5231e21964812d9321a5b133a8812a1fc3694b6762c0f	1665127009000000	1665731809000000	1728803809000000	1823411809000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
162	\\x9ab9d51c1b938e42d2ccefb1e1eb80c022c60a3769ee265a08727e861aadc9df1b1397990a5eebb327507f30179ec09b5512ef8ec69bb2a671a733d89813ddbe	1	0	\\x000000010000000000800003cc1ea08acabea03e7d588383377540e3d664f8de9db3ba6d768f9a4f48de746036ca001fc10ed21a426e8932107753a85e1cbe1915da3a282394eecd3bd5595b0dbe145c47853966dac4c5fb91203d91485bfffbf28e9fca4915d3fd0106741397b205b006096177c51dd49a2cd2039799f8ebc854cfd25fd038e70be4d5f555010001	\\x094f7b4258b485f12ea3abe0a96c2bbf5d062f348b65f7d49eb3412a716cc380a7eb2688bc1874b6dc64a412fe3516426a8ea36adf418afd8f9335fdd10cde0d	1665731509000000	1666336309000000	1729408309000000	1824016309000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
163	\\x9cb96ec2e42a7f1aac28f4cf3439881de1b280f98320e30efd577fe3a121756ab54994eedc54be11611f629dd6ab813b2c2f6ca6965d818d584d9de3e606d2ef	1	0	\\x000000010000000000800003ce20c4966e897f034e4681cd0a246f301da1d8388dd97888dd3206fcc24ad13dbd4409803c13736ad69763eebb53bfd98d29ceff9f47808c88c538998b625e9065ef6d1c009772e35eea3967bc6059f387f442148a98b849a91fa4009116523a976a9e44b8520d4753c6b6ab322e6213387d35d3d8b2be6c4b4f8c043fa78709010001	\\x6970214d508947533bd82267b2d68e0890252a8a37409388bafdf4b3c7125eb9dec688dd9471d0ab1a410562950ec96043825cd16cd2193af8336abc3d224004	1651223509000000	1651828309000000	1714900309000000	1809508309000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
164	\\x9cadb179ceda4a795d3f250b5cf6a0d8429ab9ae061a37195684bade9e479492fc1fe2d9e31f50e4d61b3116a08d8e61a05c0038bf34cdd0f4fa39eb76ef89bf	1	0	\\x000000010000000000800003ce2c790eb3b7028ee73c0ec8176ad550bda305237aabecd8635b45e63c563e0c39ab6954f81ed099c4cccdfd4e0ae31e7754a8ff32b9f95c8430e33c6507d51080a2137062e85e193bac3762ff6b194c40b4b349df360fbb279600743ac19016d49ea022c6c947c4ee9c8bc9b7c049055bfdd436d93c45fc080f02fb315827c5010001	\\x408c979c272c191821cf630c9b0016a92711d421c3df52f0995f987cf7ce489da60ee8f95576850e15f87c2965ed7587b762ca6ddd0f7b0fd81b012a5e95b10a	1672985509000000	1673590309000000	1736662309000000	1831270309000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
165	\\x9fdd3aba0446fe1e163d7c5d784fcde982614c1f86f8b510ceedb10e36dd0d9fcb6e8b22539f551b79c6b40ddc99ac5ca452406f6897be43d9d03321d721c36e	1	0	\\x000000010000000000800003c68596df16cf021f6624e5df64b7ae08c336a6bc80f3311aeb9fe05f5d2059507237729b222f5d1a7accecf9d9d5e90ab722a071626cab5fa6d451a75cd2c797989fc5c9d28bebac3d6d4cb715308515faef41ef0d1dc4b1103c2dd6459c93bc299ba9b3111b5a8afd73abfc0b7d5ad1c1e06c3f0e0633f4ddfb0944a6b49333010001	\\x0e51dca65600f5fc57b9497677af34cb600184e7d14b0fa48c7a67dce8267e32e6f2e1a4621e338396408e2fece16e01c1ab9b7c96bfa7ba5caeb9e5f8bf020b	1668754009000000	1669358809000000	1732430809000000	1827038809000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
166	\\xa1250e07e542b11663a37bc4f323c3f6c4e4bc5165c0531a8339969cfb889eb90c2f89208846d75b409684a5b1d624923e49e04656d872a06129452ab22fafca	1	0	\\x000000010000000000800003d116acc6479cae1810d1908d25ab820c1539c2fac9392d6ab0bbbd14bf8cc651842fa7f9a7b9b9f92eb1e00a9ea4d11f7eefdcbb16b541441a34fe7927b506206e5c5731c873127d7ecdd57ca5d35a49a2be95914332da3c653a33af2ab51fba6c64febe9da9092b0ee6f279bb31c8af452ac37924134c806683a0c4212da78b010001	\\xf4e9d50bf969a925617988d5ace49f0e79568b3f953adaffd43a2ec8b0ac9fe4ba9d0741ea2ffff181ed1100a168d180fb40beeed5aeaaa9da2fa65317b24309	1658477509000000	1659082309000000	1722154309000000	1816762309000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
167	\\xa221f794dcf8793891baca449ddeb11c042071cef6fb3a58118a25284c80cb3186d990f4c5f8a5f9cd06c22b5328029a12b50366c47cf6faeed8cf34619d5c7a	1	0	\\x000000010000000000800003c2e2af7a440b994ea993fe1a00e8134ca47eac4377c7bc99031dd24669859499f64c5b1d10dfeb7ac7d4e1e10cf74dcd34b92cf1e8948ce0b1154919ebe89ee57b05c8a0d2a2ba5b99c14c3d30635773f82b9cc9d9e3fa9d92c2a8adf28d286ec708f3abba50155e036615baa17dbcd16ebf1535f3e532b5122e7d2766eece35010001	\\x5cf460bdc3e26ca80497d8696ea90fc080457a69730667c3720da3892122a87bf67ea6c1edb15875d413d42dcc12515c4801124be8681fff5efc5e4493155d04	1679030509000000	1679635309000000	1742707309000000	1837315309000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
168	\\xa2a5c36896c73247f83bb4b9711f2dd54b566648d229638c3f95a80f38212003642c9b89f4a8919917b0baa67b957e5c66609dfe17cb20ecde7d32a30e15aa7e	1	0	\\x000000010000000000800003a46206d94641ff3fc796be15f5e51549d6c852316a359016eba8040daa0fc35bc40893f1cb8e5a9b7e7cd47af9ec39e66cce95c76fb04ce34390b13627fbabbe3bfe126e21853151256c73be2f7586065d31ddc5b6bd70c9388ded0cf87f5b0d664fe20481592eb13ed55ee9c88bcc4fc4b50ecf4a1b5ef9cc917c5e26aae45f010001	\\xe0d79861005c34d675c3108f299b2181c5adb3e96f4fc71ea1b438f40b9ec6930121d417b1004fb1229934b671841ecc1aad5c0d6c5370bb4b2c5ca47ca4d802	1671172009000000	1671776809000000	1734848809000000	1829456809000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
169	\\xa541b11887a19624b1f5e3bcdb59eb75eeaa2c4c5ee5e3069a447e1ea726bee1080414552ce16bb12737ed95637f0b7e25c4eacf6e3c575f92a80d488799efcb	1	0	\\x000000010000000000800003df36dd46533cdab62ed8af3066ad679832cd780a865d84568a52e3ff0909791fbe33d793b0235cc79cf5ba9603cc5a7e8aa326337fe4290afa25654d9e513f5c08b0f2b1f9cec749db50bd0b3200438a837e8d895a730cc792af377eeb4ad393273fbf50c0e52210f87a8f57c05ba6e0a8f20d7cf5b5e85cded56885c7e3314b010001	\\xa747f9ea1221af242ab6a20a35b7364a4244c4e6b5958890d850eadc7e3a95717c5575934ce1ed28f91fd036ea172a488bbc461bc0356933ae9225fb9889e905	1661500009000000	1662104809000000	1725176809000000	1819784809000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
170	\\xa6e1ab9c4756a2242fa690998c4b26858aa9c8c1d37a22f8e3ef299b7cbf21d3623e01b09beae538b28340fc58b0c0823c9c3005c78cfabc75acb07dddbf92e0	1	0	\\x000000010000000000800003c9ba8a059427f63a072a3873d0b88fb2042a2320619677d637da235b1fb5707ff47e2ba34fb1d2881bc0474a1df12b7dd7bcd992df90cc13043ecbe7285eda3125d6060188992c2ea5328d4ac3a12f069b2d94b33f40a821de350d2a7a7ac19facfb4f1b18b52ee4f99648f9e50b1bd96c25543dbdd5a8fadfaa07e57f448603010001	\\x9ccec6ff08b272fcc8757b56485ca06ed146e6ff45cfde1b6849c4aa59b82925b1e276b33afc7f1d774a9471a2c3455b513089e06a7ca871588c6ecc2db85102	1650619009000000	1651223809000000	1714295809000000	1808903809000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
171	\\xa72d486eba2e29e78682882c1d709f20bd9c83ce3b748206602814144dfe47c2f84bc286fed6d8481dc5b4b363b1617611418b005c8768ecc557d69b01483b89	1	0	\\x000000010000000000800003f8e81b68f3859e1e9702a4835e8862d144bb6a989b7767c4bee67971f1970ebaf66a8af6821eba16a8c8829cfa30e2772288ac5e642d1c3305f358458d250af928f144b53a6a4c1db5099d1f3ea35976cdfb2c7d1607d65006eb51ca09b142630ee34f5d00b4f96e4c4d28e2303fe3580ef248c2bfad2a33164714c768049dd9010001	\\x4ae2eafbf98ab8e64ed59d136621ecbc2cfe5b5dfdccf63b956342cb963dc5f28536ac5cabc20977393acecdd7d6fc0d31fc3d9fe2e4e3eeecff30ea41206806	1651223509000000	1651828309000000	1714900309000000	1809508309000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
172	\\xa961c28cd29432165db4673831f8cfc8cc74e52d5d6ddab55308b9fcbb927f8a092d9db764823e85eb182cd5e88bb0722f171af97d2af70cf94e45d657db83c6	1	0	\\x000000010000000000800003d846b31c54398f1fc5cd5e6d95c99efd3246202a0062f9368a03974ddbeec93c871769068f7c4b4caf08086b299222198dc9fcecdf974ac8d45b15e35678fc6e1839ce903fa63013f84c82671f0d3996d3f2b195b52e9333b0000bb9084d7ba6ad1eb1889896414a7e37f2e0b888468daa8f7e1b46045f24962ccfd0bbeff8c7010001	\\xb7be84d6be5c5f386003462ba3762687bd2a4095bf8a62f299dfc1463ef036ba516bc7393a33b615b863e6e4ae6fd86d2b0d3d6f2c3415ce44a695144985ad01	1656664009000000	1657268809000000	1720340809000000	1814948809000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
173	\\xaeb95054519259b367a45077c00b2731dbe85f96b731935c16e816feacd92475bdbc31aa79b6f3854ffeb0086f465afa60a35d2777921fd5b97eccaa2396b499	1	0	\\x000000010000000000800003a2ddc518909e62ea20c0c0eac00f4d02db5f1a38e8febe1a34b67ad7a6863c577e5532db280603d02a740ae93d707842e86fe2856cf4571c27dfc8426cce96eab0a447835a20056e1a0a7b333121c1203fd2e2e9c459d84532a6d9fe57ceeec1e8423b59594d9b0a8a02fa8167512e86fb35b469ae4a849144c080692547d611010001	\\xd5f13e7dfcf190175435466787fb01c1eec20f86dcd10dcaa4856477b4e79f55fbd9ca63651707828fe6b781f310712db5de6a508a58c8c1066b9aa977adbd04	1651223509000000	1651828309000000	1714900309000000	1809508309000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
174	\\xb2e5358c855697c01e5277e837e873bd89419e65153b5d65c722686f9249df2ca6d703d2e4e209728e700dfd9016e66d2cb700a2703d4970ac0cd59997683531	1	0	\\x000000010000000000800003f8c32704efea6170c683e57e57f1a943b8f66b2321727c376ebd7df8ddc41d2b08645d7eaeba4ab306dea113d5eb8e1673d2680a4b7d37cf6d38850dfcfd5f0310c9c7c87adb9a27a42858bfe669c35d29133603c099ba14634bc5dbd4fffda2c07d7835beac03d3b8491c934bf99e39919dfc99fba05d76dc0b092396c3f3cb010001	\\x519a416a49965f074fb53ed4991f635ae5e50a8c1864718842e950158f7d2cac878261d02c08935b35a7c6172f56f2698883717ada2a8803eb96e3b7e107dd06	1663918009000000	1664522809000000	1727594809000000	1822202809000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
175	\\xb34d2dcaf0ba65d041ca93a0a5a5ce34e14f9fbe42b3b936b936aba3c9559b9183ea6959189ba9a4d206190cbb3ebf121dd1764cfdad2b63d9ce771f69589440	1	0	\\x000000010000000000800003d7f5709c82516cc5c343ccebef5cb9a97a0796c293039e2593e315ba2c61ee2d94659aa1476413c2ab39a0272fbea0e2da7c67d4ea5ab9075212db8ecf8b8855065252e6f32e97fd41e349304ba49d8253c4127c98304b1c08b603583885b1ae9bbead44c88b4dcb8196cafa2df8b8e0b570b431b9008fdb9c160b7409c1311f010001	\\x735a841b48cf81053133554c3c9ef417d0e8f8e59a7ff0b310fcc38d11f0d22b5c3ec6818ec73150179dbd911e52b2f2a80cff27f1d454e2fa4b0d37bba4c90e	1652432509000000	1653037309000000	1716109309000000	1810717309000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
176	\\xb33df90210b8f8bf9f796750e6b88e17c58daa4d1ab245358e105f9d16a659665f20183d1fee148fca688ffcbec32ee65b98e22d921853c3f641b29b64ae1a8c	1	0	\\x000000010000000000800003c2f1834e189bf843a7342dc32ee85267c9f936726f1aa69bd0c078dabab5ac0601460ba310a3bd8f03b6ce5549bd26d93e012959448457c47f8562a7871f8201c46776584c6aa96fe78496e01f5fb0af34f25689fb647a73d9e58fd33cc27577e3cc8ebdf92204c307aade163e199e8cbee4d39e941ebe5977b2bc45a41a66b3010001	\\x6345afc0356d4885fed6aff202831c0a9c8175d825a90c509ce3ae81ed6e3c1408e519d364b2b02e656c8c49690ca4342be458ddd5b3289851e6c981a37c9b02	1677217009000000	1677821809000000	1740893809000000	1835501809000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
177	\\xb5152468540d4c509aae1e6a104ee32d3549c58818215d9b276413dd669b355439e5a82b53592dec03e247cf5bd5f206d6878156b35d7e38fbdad1f80689bbac	1	0	\\x000000010000000000800003f59dad81c21ac3cfe9a1fdfbd37ec72431fe92ffbfdc84a0f2eb1457e2acfc9d10d4d739a686ff69cb288882617c63dcbf701c75a7448be1f39d9e599e232ceac22b8c00335fb1d311a207594f6ad35a25d9f95e24c23d3a8fe1b23cc0e86327a1dfe6991df7a99fad3efb2186ab093041ead08fc17b001324d7042b5a38b3b1010001	\\x6da756b1b2958d77e29293d05f626c4544fcd4c15408a18a2de94fc8c31558141bd9a05b83ddebdb29e41c3e28806cd2099f7caf9a3ab73f1303b6c64e56c306	1672985509000000	1673590309000000	1736662309000000	1831270309000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
178	\\xb8b94515f830c766a6ff2b0c803184280c069ea48890a9195d132415882891ba3f66480311045f618d15eecf3c6a8f3bfa637d24ca16f0ee5b340d13419d9f62	1	0	\\x000000010000000000800003d0aae1d3fad17cb648c26b689a69ffc4320c36030d23bf7089f2e5f18f5f396161331f7dfd51a1e6144a6ca06be4540192ee6d51c52c804fdae365b35a38ec72dc50956170e9b0085640a406d3818ae6fc3524a8a2c1a2f5c166f66e7631b9fa293b7eecfe94a55d37a971551b71d2eb3571de77353b20a2ab6fdfa34f0a6ea5010001	\\x4db8e8302147cb037a026c3cdbcd1762c7536f960544aac7dcfe594ab6219f11c2bacdbab519e459f7eebd7e2d67e6314e65fdd8b7344abc08df2615283e310a	1656664009000000	1657268809000000	1720340809000000	1814948809000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
179	\\xbd2dc270cf48c6a83e0ba651d92a4cef9ca80db4732cfb9a5cfe5bfbbe545b8cdd5b62fb9add19c64887cb9870764a697fdb38faf610669b419f5a9460425891	1	0	\\x000000010000000000800003c905bf0eaf7e75d810a90339c1547b1516281aaad4b8d18e55e8547f8bf21d3c234ff0448de45e1df36017726bc474725214fd349aa3267c69057fd357b34b207fe1b617f6404b8d989e0bc2c43a9f8a268a2cd66b29fbe11d215e72aa6541a71948d48580fa84f821e107746e6218bf0ac9ed0d66dafc6235dfd5c9a460061f010001	\\x19ab8db59e21e901fa530dedb8ba62599af9d9540d770842dbaa91d8bc78014fa01e4ef70ab845ef5f373dcebae00860305455942e8bf4f4941f10748d3f4904	1661500009000000	1662104809000000	1725176809000000	1819784809000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
180	\\xbed5680df07c02fc27319cd22d119cb41361aedf48c094e82b25929a898b231d5f89f3a5cbcfe9ce7d3bbbb35b4975a281fe107f4bce2ebf20a7f64f8594b97d	1	0	\\x000000010000000000800003b9d32ea4cd3e8adcd9755e44d21ac53863962803be776a2cfcac9473da51ffa84410e6e73f35424a7d85270060bc267884a3fdfd4eec6fa0c11d35bf61217a1f8f0966fec7a720eed71aeb42802be2e1e5c1ca73aee0ae17c555aa694d9b7e5883c0329c56954213072fa47ccade0a0f2fa44713d58b27dfbd01cb2a194b4585010001	\\x0a93718828ec1003fe8bf45799b1ebb2d635a9c869a369b847e2ee4f6da7ab4e1e78352cfa5e79336ef74717735ac70cb11dec1127f43c89c2e99c34d1f7f305	1674799009000000	1675403809000000	1738475809000000	1833083809000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
181	\\xbf35bce2ed0098c31e13c15ab21f77ebaeeaf65a73f89634ed8781f25ba947790432652fd2ab13acf2ad01f766986e97b5d2e5dd7192b9cdfe8969896cdf5a86	1	0	\\x000000010000000000800003cbf4110bd0341a86251af787c30ab7176495c26f28e70d87dc4614e456dae48ed5dcfa2de9e0512286ae368735e6ebc22b2f41c60906fe54c581b551b9b41300671391510baec7b96adaeef6e9ce80c11254cbe136e2ccbfe00df9a48c6e394a366d784adadef1660565668ec153ae70cf8a344834eb4287bb836e0dfbe1efd1010001	\\xc254e1bfc5795b2fbb0bca461b22765a436a95af4091153ec984f2d2fd3ef2859190fa225a49b5e33e890f9872949ce18a80a024bc0dd06d11526216fedb240a	1677217009000000	1677821809000000	1740893809000000	1835501809000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
182	\\xbf09e1a9c29d2c97ca50acd7468b2a887563154d7e93e50d08fc4050999789a3e7edaeaa7c815f2e6b8d36b82b3e9b3861cf2a3eee10d4db38bb45328a073a11	1	0	\\x000000010000000000800003bc13be755f9dabc95320551ab774cab4d90176a30c4360d77be3915c44731e76da5fa44409684ec267a051bbacae40014ed74fdbece99f47ce6c8650537295c42864763f08ebaf68186fd9e1198565bba0dfb4463270709e1b5f93e4960346be4e307d6b7672e594d54e778392fe1df727384e8b9a3e5c0ce63d6cc2a3eda1c9010001	\\x57545a129a5c4b455bc172a7d0645ad1d6a679304905b7431f3d05dc5391a722afd1b9f9f4aa9ea969ac7df7e303688cfdd48555ee5331c1e5efc0fac978b70d	1659082009000000	1659686809000000	1722758809000000	1817366809000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
183	\\xc0019f63fc978e1d8a82146b498ec48c28b180ce649f2829129559c2a1daf3329d5cd354a84bc64de1bc023e0f57ba8aa0d2395a511c27f97c384c118f58488c	1	0	\\x000000010000000000800003ec60b3025174cddae5e8ec257de4f124e33d67d89a757e669f28216fc51b3ed86a759604d2ad3938328cff44cfd0ea0d972d53e27bab5c756642a2d9676ecaedab4d5f4e64366c3b863bdf42c40f2593fb4a3b24303eddf280d2b4eb73fd0b4d52e6f000f1f064dee3313f4b892b8393e349e94155eec7fa84922cbf1d50b599010001	\\xea00b8a876c3b45562babf5c219c74bd02271443b2a29402013bb01908dfb385b49a2d58b0b5c40733205c04e978b56784dbb59364c9e5c1bc28b4121ecc860e	1681448509000000	1682053309000000	1745125309000000	1839733309000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
184	\\xc50d973285e1a7df6023c18fe78e67dc29ee92c6472c39337ab3f696ca7ff397da876481930880f5826bc164fcf99745aaba95641a838e844fae551c79158f3e	1	0	\\x000000010000000000800003d5d34ea78dbf933280b2017e515860983aafb0a4351ca0d0f8ad4c43925ce8d59e82f6237ce759868cfbba4ec335e791e855df4520d2f7e170fc5f0a300cbd0a827dbdeab5b6027dec063f56867db76e5579e734e23545d11a8d21443ac71765753b959c511bdcc2aa0e43b6b2e8e2066d1f503ca6d9498e9fe69b66378c718b010001	\\x7db48b1a9610ac9cfb47e4c1240e903c0908faf0a3aaa7e0b9d1dfc22d1f11be5f639e23f144af72734adeb0f040bd8f08cada81141f97607cfae9389d0ee701	1680844009000000	1681448809000000	1744520809000000	1839128809000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
185	\\xc641dc99cd588075aea49a4c95b8a3ad111bf3efbf9d507b10c078be6da58c7f006a7ac1b2c717e00af4b80f591c3ddd0198008ed74acb3fe40a729105efbf5d	1	0	\\x000000010000000000800003a146daf587ab11a93285dfcc960ad5f2bd1f1f566fce82a1626973c630cc6c6bec68f98bc84d7c325141dadbd70f7c1887c497cda4678c126e5116e3cbdd81d17ae583f621aa3d52dd2b36077018ce9164d478ea087fa890689432f85a470e714d0d9dcacfb6b96006851c228ad40695ed6d193ff990c998d47ef09ba6e88ca3010001	\\xafd8823c07d2666d41f2beb7f8fcb61b03ea8b26052e926f2f25191e5613940c5c5bb1ea36c1a83933615abf5783eb5e14be78ff9e5d31ef09c1c570a71de20e	1656664009000000	1657268809000000	1720340809000000	1814948809000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
186	\\xc7c1b8cdebcb877711e470bc9261c5a0deb8c580867a31e8305b5866b0a0cedec9fda25dbe936a6c91dd42cc438a8ce0888314ec614ff852b960d5c59c3e130a	1	0	\\x000000010000000000800003ced9fd21afcd71c6e972fbe6f4c576cca17fb0f2d930128d5c542260a788037a052d8296a2f65925d84b0096447f7b50984d9ad281f4bf8d3b07f5b85453d4e67a7fddf7722419e35339389fbac277c37f66d7f2bc5225a755c3e14d0301d27359bfadcdf4db9fd1a1e7a1565c58e687d57b5b911a3ec4095deee7310619b83d010001	\\x82b4c0b9424cc991777c111f1b373127809fa889397643e5baeb8de77ebc9bd408fe3c6bed2db705b94018d9f8752fde2708c9d5c704a27a4b0524eae0be4109	1671172009000000	1671776809000000	1734848809000000	1829456809000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
187	\\xc91978936d2a2070049999551a2211777780d826cea3d500112c94896834a6949022ea0281963dabae6b1ace60dc22041c162fae458e297e3c5059de743e453a	1	0	\\x000000010000000000800003fd755fd4c057428b4354eb1e72400c1b04d4ffec4f5cf7e3853f6021bcc2c6fa0df258e61b9620f2a90228b60a942e7afaaf78ea9778cdc9c6870f2527b982e65b8d00ea7c14f05f98cd2796c20c25375436df20a63f8790ddb24718095b3d36cda79be2fbfe7dee91174fa1d08e69c6b46bcdfa2b4a79a0569506423ec1f9ed010001	\\x63e60339fc4e50121ca02c9c8a094dc2a18a5bc441c972b67eecc3c650258f1e8086e6046e2e3bcce4e24b089acc3f50b60e63347c2df494068d5147c7296507	1676008009000000	1676612809000000	1739684809000000	1834292809000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
188	\\xd31563937a67ada9a13ede58f1845a076ac66c84ea1fe816d39170c602b4590b2e07c27f4ef7361ceb76ffcebe8373f98f0ede3241c73d45fd5f47360516583c	1	0	\\x000000010000000000800003b2561c5fa5e510685530b9bcb97baf993db963b32d5aa69d093586349f6ec770b350040a37cd99c6efa600dec57318fd8f35561cbba70131b74bdea84b2c662fc6b072cd0237aff94929ecafaf3784b1550c567d5485e7005d6d27ee1388be1b0b6b0f8c3a617d4d04abe2ec3fa2d703dd7868f129b2f82e088fb8623bb0fa9d010001	\\xa10809903ea062c9fa0b00d1740957613aa66b4c1643e413044327545599325aa2bee8a5def3622e0905266cbbc4ed53d23dd1a54f05ed0a6cc412473a61230b	1672985509000000	1673590309000000	1736662309000000	1831270309000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
189	\\xd47d0a486843845dd43dd92b62445a2bf5cf38256434fc6a3aeae4b5762a5cb8bb6820523dba73d75c2aaef0f5c476846fa1fda8d9fb19df7e1210f1f1f460a2	1	0	\\x000000010000000000800003f6726996695bca7dfaa1d4f79e215c6ae3187ce4600a22018bb24e5eabf8aba5bc49e921770234d4de13955eda295bb0ffb2c4b33efa70cd8b3d0e4697921925deb256becabeb5970feaa3bc611deab0da67053b66555b31d394622b9129604468c7688815e40544e9629a5142ae3f222810eb42496715813f297e103e59a157010001	\\xd3c44b33c1831878a376524b502f1514d481e6e65e2f8c4ec776a78bb499045c7b66e6fb35765854fd0c837a8c1662d9dda4d9f743c33161722b28d233a30d0f	1660291009000000	1660895809000000	1723967809000000	1818575809000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
190	\\xd62d2946d895199f6b53d1824b498d7314030ba3adf837e96c5867112f68b658bf98a50d2f049790867dc5b9efe1be20a70addacf3c18736adeb93308adc2d29	1	0	\\x000000010000000000800003a8a8f02cf854d214686085340e0b9621ac122f2013a441ac7370d6de3300bd74e8beddbe712bac0e4f89ca39654a7f188b395d415c311cfb02231d072036f2e07e0346ddbc02c75241c58f6f06d444b4f269c4f58f01344d0d43d9d76d87a101180c3690dbef65dd47278db22896467627e8907838498f6176e021a3a9d179bf010001	\\x785d7d0532fd026879fda538ff5abc998bc9b3e6315ea0810329a2ce7ef0064b99d1bdcca314d0365d2449960c042abae357fca0962f8b84909af6f861ea1e03	1657268509000000	1657873309000000	1720945309000000	1815553309000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
191	\\xd8b187da6476fb3d063113701de97889c2733be9a52a1a77344a90a2e8e96279b3df5f1a8054ec6930eb3022600e46b9aecc047a6ae2cc6c36f5113607308e70	1	0	\\x000000010000000000800003d421e8b3df0c4767d85304847a6f1308d2f380900a1c60515d92a767e502303fabb958e2c26d9c79dad57fcbe523a1521ad37aea3350fa20ee1cdca0fe00b1417b6ae4cd03493a566e9ebaff7fce386f8fa2d113fd730b3320f969a5845e3a71f82245012b92af4652711c4764c34d0b0182b00de6f488ca5c49e3894c4533b3010001	\\x17e0ff94116072da507e4b07a5499db4e3e8c12d149a95f6f6e847fc2d23f55738bac07e35003cde1e3ad6148ffcd80199b67ea140b9d462a3e32624cad86c0e	1666336009000000	1666940809000000	1730012809000000	1824620809000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
192	\\xda79c87bcd3a1fd917ac4e080208d05443ec7d2022558f87c31ba097fc153e30b7bed2fdc9c9957ee844019465fe1dc8cc20b15147627533652f3f394a1f0480	1	0	\\x000000010000000000800003a93babd1732bad8d235750f5d1862a16cd1590edbd8cf8b0e3508f2f240e815fee8f2762cd6f6a013e288496a15bea8e304d31e2e77a3a53d25686ecec620386b5ccb4e0aaab88f0db6124ab020295f5175212c4e87969e72830e811a96d8ca39a9f08dad1318a5607d137003be31ed57bb8ff461053f9b561126880fe6138f1010001	\\x662e5296b57fe43efdb9e8b7f3ee23131bc2eb009bd295cf3d3aa3d1cb073b6384b80ace79d6d43e90e3bfab151dbb3d2e75f529b25619ba8ec4cd74f1c3a403	1664522509000000	1665127309000000	1728199309000000	1822807309000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
193	\\xdba96baba4a2ea44cbf87838519bf7822acbf3a24ccf9bcf4b689afad4c6115814d16be83aff2eab5244ce044bfb22636d8a5ad1380afd5eeb62109ba88e3031	1	0	\\x000000010000000000800003d6bbdd00f50e60489cc46acdee675f7595cdc7904438adde1a5af338d76bede5554eea56be1a596df2eec42d4f5e48dd315a2a601360a88e3a4b0b4a476cafcfd9f42510166ca0063018ea3d8d88a0a8ff358171598a2452a45f6a208744954ee4f9c2a33e484cee6a0b3d1c5dd3ce4be7ec77902d2714e9de2d3ede66b26ac5010001	\\x0e892d5fb7de700415b02caf5a640b942f6eb20a413b039312727d7213d85f4378c1bb6b1c58db1bb7878b656ac11e38223a730b9d2cc7665c3c4b058d547302	1676612509000000	1677217309000000	1740289309000000	1834897309000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
194	\\xdb89b49ee045d25a0c7f44dfad50fb6034b6e069d05cc6c55e394dcdcec1df18afffd7aed90c4cef3a8909887a4a4b95ba0a7404c9e948a606a9af06bd26aaee	1	0	\\x000000010000000000800003c1eb74d462576bdd108cc539c0202ea5eeee567b8bae6819c4746d3c2838a5fc88be6f85238ee803be59fe8374856eee9966d1342e71173726d82bc5e9f2d52e1c7c8e3696013659799912edc47dce908e62a68345bb66a4226f5c92950ff7cbe739ac95b6bcd7c6dbf628206b6e48293b765485ae2570e3d7f9ac0046b249fb010001	\\xef4077869bf2b20fa4c83157291b7c439a7fb13f7b788e25306a130e783825002d22a86e1a91f133e7b62d45ebeba9fa5bc37837c47388318ddcc9126361ea0f	1651223509000000	1651828309000000	1714900309000000	1809508309000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
195	\\xdfa54ebef2146792b8bd78fff2e157442ab19f395423ad78b2faa42bed13f74b74a59684f2a51456b0a0a474a16829b03931b99289e6cc4e54bb434991a996c4	1	0	\\x000000010000000000800003e94286f70f0927c4913b425a32fc2e7617cc2cedcbd852ba6476630e8fa10f28c01b3665efe5db04a32f17a884ca3db0a5cf561286b37446c5f2edc28f337368788b98f2c41abb2b695ce8bc91551a16ebdec6271a03c30d51d3f66059b651d4cd142868da7e16688c4a5cd8bcf79c171c1788cee61b207347bbeeefbab1aafd010001	\\xb4c25cd974c47280e47f62a1065f77e74f649e5f4522abd5f348f7b60db0d02e6df52cc47e4beb903a79241a0d0f8a22bc042b8ba78d7ae094c8ec8df2cab70f	1660895509000000	1661500309000000	1724572309000000	1819180309000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
196	\\xe22934360c88045f6e8ca4bedb790544de1cfbe27d286011e76d34bc4ee1e5a9c744f16a8191dc05f1272dabb7a501436dc60e7bf1d50ca8076f5bee5fba315f	1	0	\\x000000010000000000800003cb64b9088b707a111578495ca0a9dba4775b91f6f85705b4ddf3e08975bd3ba670c962e91cbf70a3476acecefb8327fd4eac1ea7c13efaecf4586171a083a312e8d865a2699c66bc2bbe9cbe23316d160c626b05bc9a75109043c5ddd14bdf5c2b17626d3b05b5893d6ca4c6e308c3e5fca13c762a276cfddf7c6c378558f249010001	\\xaa41a9279bb2608d28d02f35386d448a5e46a325f70af04b280c756bfccbc47aee0903be624e82e1c17f38e74fcc6fab6acfe1aa54d5829e123c64c9ead90a0f	1659082009000000	1659686809000000	1722758809000000	1817366809000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
197	\\xe2e50efe22e581383360170cc2f237979ba199a9713a72609efcf60090afe6758bfd1c81530b7991e8218d32b6804aa06add60f0027ffd2a16b2a0ba5de08a4f	1	0	\\x000000010000000000800003efd02ed3cc264922a15639061faa45bbb485f4c29b21f75333401a536eecfe9477ec8bb5259a9abd3df8719fba401707e0bcb3fb0c90bdbe05fe1e3d5f81d9ab2a0ac77619ca5086b4387be92cbde999684e742adb9901ed5f6cf73e15781878bb7ad85293b92dee779cc0479be7e1a21148471b5c3e8490307baf5f286f8e61010001	\\x2ae22f79a3a370eb22e5b54a1249a5c76802a3d3aeddda9a7e5ba6968f80c85310addfde7a064db388900de22d7adbcbe111d3433f75346216ea9488f7f06805	1654850509000000	1655455309000000	1718527309000000	1813135309000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
198	\\xe5a524af7c963b474aea14d7a5e87c9f98b92a71494b1c3b23abad9b6550f9f2b6352c847f532fd6e226a8ead593cc3cba338654a97568996595b85ac0308ff3	1	0	\\x000000010000000000800003d3a486bc7deffea2369b2a7d34fa7ed1ffbf7f6620e6c7b2f2257080af16d3b839f03c04ecb4f469c3b9f3ba114737b652f6a1aacae70eaa863eca2df4f1b9a80bd558f43f237f9d26e310f3c50ce74f44327be8f3fda71f53fa94d03448313bb085a71aadd69486b16ef83e2b1c0cfe663b11cc9e3da3fe5a129b7e448f1a29010001	\\xd9c5b7ae5dade2596537125201eb553ed89d3dd45fbaacb9d7e6f16496cf4c2be1be87c08981221ff9dbc555170332020f52a008cef45be5729e7f5d241e4103	1668754009000000	1669358809000000	1732430809000000	1827038809000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
199	\\xeadd576926972f38f9268e5f19bb756a5e4370f1e13f9255040ef1b26827016fa9c1be828f51e25c6107b43e82a53587041cdb1dd84d2751b8904a28594280ff	1	0	\\x000000010000000000800003e776942e16216be81eece78129fe22ace05be0ddf0a108723b7d32c5214a095ed876a7261b4dc9c900ab176005307ab9d9e30974a67ee557ddc5573b5a632eedb9b6455815b4851625b78d599b984a3046190d955d3e994a7758bdee3fc9f0b9281bcba926fe7d5e8a29e5bea36f81276445e58080bbcc43255a83b687907eeb010001	\\x7cf0b1a674f24077174b45ceb5c4d600c1cd2d9f6c6791d0e0c448fe895aa334c2eb0724f2d43a501688bf0df666b9f7995e7981f33574543595e2a09dedbb0b	1671776509000000	1672381309000000	1735453309000000	1830061309000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
200	\\xeb7dd1e33ed92d8115c12278ca4b4c21ac55ec2b4c1fec1e7b0ea1de683e409391f50ff5b884f3ac94af1b3938b24d514c11fb520b012bd5a38563723170e408	1	0	\\x000000010000000000800003bcf012c91ee35e7ebad562045b863e9cdb26bd476f7f52485b71eed891fb6e77370503bc2b23fc70026a89abaf64254e39483afdb13b320bfe709b1a315c33ad49350128412e7258ecb416d3afc329510d999850ac9519bec8f906840eb9a57f1e8301b13efbb2961ed83b1fd869bc99ee93527f378b33058df4c3adfaa7d817010001	\\x37d66767f7cce60574d30e4ac2c2cbe6ea25af38252a444f489fbd6a0b0ef3b3b249ff9d42162574c2dbf496190133662527ddf752abeeadddbb219f5b24cd0a	1655455009000000	1656059809000000	1719131809000000	1813739809000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
201	\\xef91cf11b26ef97345101c23d6f0a0ac3d092e098832008e14c8728c3a10c03b857baf3a759471d5033dce98c6e076c21c0fe3766877721625b2bbd1a60e41cb	1	0	\\x000000010000000000800003c4f0ca7dd183e624874ad6b5bf10dddfd408a42a858726bf129d309f31d34f1c6430ea716c593bd4abb19f7e0f1f41ae5d693ec02c06e091a1c44424df3a26012250ddc739d7df0bb6f82991b3219e4873dc4268bbfd405227d42bd514ccad2a5e25ec07cb8d8c76dd894a47164f928ce1d5152bd81b3b6607745e95387e462f010001	\\x339a2e060d8bf4801ec263d2e5b68a3dd3885f31332624f286eb2d47435946a491ddd315eb3d246252526eec5886f63064e236c7933db28919f3b2f3badb2008	1677217009000000	1677821809000000	1740893809000000	1835501809000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
202	\\xf2c5767d2b844e9c4a299b98dab6acf45fefde5e2b20d9f052065666ea5022bf35ad92ce3fdd75584d7d141bcd9ff4ceeaf0b06da3825e7f5c1e5e1ea96d5343	1	0	\\x000000010000000000800003bde2f788cb195d06ca1cb92bb9b29ead1d3bc6f548fc8539630735c6e58bdc3c69a3e7821bca8fb2acb45444da143f67503826beb803a2adcdb20f5a59f198d7dfaa1469fcd8c587688c3325da92d32efbe3ba96b786b1436b7cd1748696edee05fa13a42de414195964cd46fdcd8a100366476c705d8aa05dbc22d7545164b5010001	\\xdc88a7f61e9d81847db1be09455daf2700742fd9522221e1e8bd03657d30b620d81856ff5d004796c08c7e77c180f018bbff8d426134732f35770787b39edc04	1659686509000000	1660291309000000	1723363309000000	1817971309000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
203	\\xf3c190d93311a35aba39824db8a288e6d00b2bdc31d762b181de87aaf2f359559a8fca673bae179390e30c309ae8af5abd9a54a7cd05b8bcd9541e15aeba926e	1	0	\\x000000010000000000800003b5f4c0bc4fcf550f2abb6927fcd4d427ce510c561246dba56b1a4f5f7fd3c4d1b8152a6a681a2d685fd3fc35808c4207df4906822495933b10845c350626b7e353ea0f2efed9c55dd75203b990ee7560cef1648e29b6987f7724e3e2c03ff4911028d779735681cabbfd481fb21aaf81dec8aed3c50f4b12d502fab9ad624d3d010001	\\xb9b97f868e9e5a937ca144501e9a5611765866e86b026f81a957620e1af06328261fb350ae6b27bc46be4c470466415674e79bcc6eca8e23ca1149f8b9c2d103	1651223509000000	1651828309000000	1714900309000000	1809508309000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
204	\\xf4c9921284612860578d8690a3833e320731f91b0e6827d934c24b3676f08d003b6d428e45eef2efbc852e65284d2c550c836c790e908fec2be01c2a05968f93	1	0	\\x000000010000000000800003bfc9b7d0927a29d0023ce6f5d9273d831b9e0d87ff74c11a17f54757284e94ced38510c8165e7229c726e1c8be5e8902585ad937ea34aed546227f3eaf4ef5d47a3911c8625953ebe2c5c5235138de0f988dd2b984ff0c1a9abf547dc9e655c30e34becab960747aad2f9aa018fc86a04ffdd01f70da2c97cd0aa5ae2ea0f8e3010001	\\x854cfb286730009ed5af54b1b9cb18f5b133850ed11894d76245aa5ac1d414f259a0349b3706d1de945c313c475f6de6a13de1f6017951e7bb19e568974e8806	1656059509000000	1656664309000000	1719736309000000	1814344309000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
205	\\xf95d7d1999665edf2906777c3f7c02015a0ba21ce1aae10b064f986f1ab2ef5810f3af1ee26f8ca8019d0e6466bb7bf4c959b08870b0d8bf1dc141ab6cecabf6	1	0	\\x000000010000000000800003f229ca4557dcb34f0c767ce96ab910bcaba4a4e21fd1f3e5c678b7d24f30385b48ee0b3d47fbddb63be8a7b863af3c6c344d5d1ceae284872bf1ef137c485cbe9c50247d8dd2e2a31c656d7c5b7d75e5df0aefc9962d24cd6d1e033a9289b4ac743156afd64a8da3482a5f4b64d385dbda0f30870e0a4fe109f7c5114e217bbb010001	\\x579ff499e6d9a16b98fd64dc3fea94d55d19b18ea8242eda13bb7dc9f7dad7ffef41ba707aa9ca00a64847a572dae8b660fd2956fa81e0c4d405b38bd2425007	1657873009000000	1658477809000000	1721549809000000	1816157809000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
206	\\xfae1e90284bedec038d982472f66838b9da6d1d93b6d3921d9404feea7db488cec404ca224ac71eda0eebaf8b9bdfdc8a4f523a0fa69622ee2f8d750642fd5bd	1	0	\\x0000000100000000008000039be130354bb0322d2579ef66e9a1322fe20a31246c25477fefe0e1ddd886738fcee1e7efbdf99d0bce7dd4ccaf736c4fdb6cb979125f4958131bdddcc15bc5e0c99e42e4251f424a50e05d94c03fc2c4e2d4acaba43e57789f7d7719e82fb9757e1cf0888ba7af922cfae015f9b2e7865be25a4b644aed8096283cc2a97b7039010001	\\xae500e714a8d6aa03645266484f69db6571a484223d275d98f674d618d3eda383a4db165681382a67da31b04ec5ca832dda2ba2aa8b6626b510314f47adc720e	1656059509000000	1656664309000000	1719736309000000	1814344309000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
207	\\xfcc9116c5591bbf2b98184c2d83a8c30113ac26632366660820d23cc04df923d5a991d2b45a8fbb3d53f54a05fdfe55aa9aac5319f9ba2575ff60640973a29a4	1	0	\\x0000000100000000008000039ef7dd4695f229d9f170d3de37491f0942b1a829db498008f868cc6290d00160798de058140b7e9daf2b9f906a35e1d17fdc84eb5c80ff2d88391d3d88dddbca7e8c003e951666b936a458f435785373e0f1608f80cbdf5ce6cc0d32363fd323b8725a5367e141598a344b974e6631fcf9ddd7d7637491ac0ee789c7ac4432e1010001	\\xca990c1cbce30efbec62b96c8cde5fc44e4f8b30e7adcb1a40c9d2b086134c6d4280821ddf7a726eb4732f7ae2ac40319b1233b935ecfce02c4e1d686f42c60d	1671776509000000	1672381309000000	1735453309000000	1830061309000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
208	\\xfd19edba5aa06317acad22100be918b8c84a0edb7741ebcf638a64a0ae12a39a543e3cf891d0ae264da29a6b3faed50e957625493064959fbd509ccd3fc85116	1	0	\\x000000010000000000800003ae9e4ccae3bc338ee771fbabfdc4fd0147ef3b20d018b4268d3366411688375cac6427f0dbcbd0ce04287bf9988d5ee131dd8c21bf1b97b9695e6befc10c37ce48742d2a983980c61729c9696e9ed728b448f2d16b16f3a4820dbcd712a13f4328d4916bb5c5c29d667cc4e50bdaa75587513ce9f47c00d2582523efc64361d1010001	\\x1d96d572613795cc505d5a556639a49f65570345b899a13103af80b2028daf0d1966354d8e17a6fb6ede56769e2e8754ba43f875f896fb61172546f4cf90ba05	1660291009000000	1660895809000000	1723967809000000	1818575809000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
209	\\xfe591f7cbd95c4af4327dbceb6f0a7baee2197663224789076f8d82114458073c56fbdcd060e18432f52c80137bb8947808509292d7bcd713e74993f4354032f	1	0	\\x000000010000000000800003a07ee0e5953795bdaa8b7569b11f17d478797765b85bf3d9bcea4f5b5c4e03b000951c5d90c630a6ed633380e5f083205c331d31830d9943b8fdba0c263771da183a9f40d405c954b752a35361b6758b436bb177015391f518a39b5d3ec4e883fb1a55d3b5b3062d14f63798ee6604c1cf2f047e100634d195a617c15a520f99010001	\\xb259ce7c19ea69afddd2c349914b34712a6d23083287889c5f52449dac2ae03efb8610caeb31e6e00d7a528bbcb78e7da803276948b2a59d2bec1365f81c1100	1677821509000000	1678426309000000	1741498309000000	1836106309000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
210	\\x004e4127b2ab5e93b420ed9e58d7da637cf47682634c1354f39e2d43e8b8ee4289d165a2b8a2752f4776f4260ec8e7c343e4c401e5b2b34e5b6a9feb1d881280	1	0	\\x000000010000000000800003b94f641880393e6833f95fece8ec688d2110c98915061801caa5cfc0e525efb4a643daadecd0d66779d75195c14ca18be2b16a9f0b471518acbf066f8693f16acd7f9172dd6ec85655802509d896fb47db580c7df069cd191fcd6de47e3ad534125662576c6ce32d5988d43b3edd74b6b9adc9c363cf2dc9e6b6ce90c335cfa5010001	\\x7b72017c5ad483640da9f8bdb4037f889380f7a48b67064617dead49793da79532e79f37574a18816dc5f0c43985218ae0c29ac9fe67e8f68e53436d7663e302	1672381009000000	1672985809000000	1736057809000000	1830665809000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
211	\\x001e43b0bdd1f3c68b45f71d78ec81e6b3bd5458298967a9f61eaffb8d03d84dbcc1a4a5efd30b0d9d5a9254b25bf9ddb98360274b3827ea471235e53266daa2	1	0	\\x000000010000000000800003c50f192fe5897bc09e8fec07eedc845d21cc0de4d6568c5135d97032d88ba278ebdf1c990377e316e8eccb5c66e59e40551dd95f2197534642a2333ec85ed824e823f561189717a793d422276e651f16796778be76fa2249ae1ac525120e9277e15a87a48d9d3a5ab7dfb2254bb1f3a39a875772099ce473ed365587929d637d010001	\\xa5d5c91dfc99d7057f8689b20d9d37ade725c813318f5a2e96d54c48cdf572db0ff0e6374b199d3dc508c7c994bbfcce23edb11b2763f4d2f310e98fdda94b07	1662104509000000	1662709309000000	1725781309000000	1820389309000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
212	\\x03caa05292252913df32c71c88736194a8c63194d5150bb34faf39b6f6f5efd607e64b07d17272ed71943c62d8cc75ffdb0079adaa562e81c62db9e02a16e6f5	1	0	\\x000000010000000000800003dd4c3045de6bab87aa9ec414c94997ce81ab3b2c703a1daf4fcb4a6422b9342c3b9a79b7f209fa938454a066150d3de842044458849b3ce33ad3bafe74c3190c09aa7da2d9c11ca7109e16213cf9501047165dc686c636d0b0ba6704bba60ab5e67ef8a658ebd4cf9f16d0c0c31e750a8be9fb329458701ce6a19d915bc830c5010001	\\x60c1124f1da90ff85faa89b26955dac8966b17d0ad5d09a7b740a7dbb7a4c04202c76ca8ffaf59f1230303702c30f3e5b27cd9e5cdf1e9020f5bd74fe05d3907	1651828009000000	1652432809000000	1715504809000000	1810112809000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
213	\\x0636629697a26d943ea313be9ed4c863d1141a2192a1917534ae33240940917f7014ba60936ef37acc866a9045cf0bf071006704f1b886fc4e54651006febd39	1	0	\\x000000010000000000800003a9929048b6a5b71fcd5549abdce4b470ac29a6fdb6c913622bf6b851238762c67872363f37f80bcfb14760fcb185aed5bb9b391384dcbeffa0ca81f6453ef4037f5b8298a07eaba2038e801efc94b1c5d194794efa561be9dbea96e4e8ab75266448a566d78d470a00dfd882cc18ba869dd683eab3adb42b2a71777a47b195ef010001	\\x75cda6b6c1b84ac76891e2b06c895a7c06a3140f7d9b9886faf9ec16dbe88b16e7c74950b3de1a5e62d2b4660a9b28bfbb5b10e8e252b4f5229b10d33324cd0e	1675403509000000	1676008309000000	1739080309000000	1833688309000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
214	\\x065aff6f3f3d1d07a44464b30c28226f102eadbc4a4ff456cb332eb91fc55fb0962f4bd79a0f244a2696672b62069b130313c87f4f4b15e36029dd6608093c22	1	0	\\x000000010000000000800003deb396e4783485c2198dbe9b11edda0627a0fa77cd2b83bb72955d9f622e47d11ce685dd814257b3b92629e0e942aeef180e8b2abed8f1610cba61ee9b1d303352cd6577ca72b2d1c8395394a362e9ecdfb6052a55bdb21876f7290134a021b80c8b29ebd4d2020259707cb19ae54e74f5616fae3073cd9f23689bcd02327bf7010001	\\xf70f07d542930588a0872758ee6f61c4b02e3035a5f3b70b751a80f8f9bcdf70450f8388fbfc86ef40ae73130669b718056f1135becdf15faed87d20feaa200c	1676612509000000	1677217309000000	1740289309000000	1834897309000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
215	\\x06f2fc21915ad7734c3ed53c26d88d648ee4f7dfde56ab48267e769ca11427819b21b015b62e73ef325309c51080d52be940849e7f311ef2e4b046717f1dbe69	1	0	\\x000000010000000000800003d0d62080ed552af7a54e27dd97db4068bf39e47b39a0543e9d52f6a9612577af4d29a1b5a0ed971c23bf1eceb3421e1f5fc5f2443c71ddf73fc8f2a1b44bc6bff63edf9eb3444e954a77afcd0ab37c722f15af5339fdd425d8f1482598bb6d216def7757cc5ba9cc8a23a98e8bf484aecfa33eb340b72d10df3fb0e6d8309d05010001	\\x2a68566783aab361546059ca6f3ed7bf6e83abb09400ed855b80fc9e5e35c5a18b92152e1c38c98a0e264b8f7521c7248c65b800bc614dac14ec5927152ddd08	1671172009000000	1671776809000000	1734848809000000	1829456809000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
216	\\x074a782c375b25cc3325c76440978642ef1561ce5ddf3b5013efc2fcb258a7c4d5b282be4bba0e02c3fa6e1400c99b57e90d2b2c0ee756d88087eed89b44e6b0	1	0	\\x000000010000000000800003f4fec4bef304a9f4aaefed6d8424c75ed71a6865a613321a3c995d064a91d25c297e3f1c6e69bb5274c9f5f461a53e03557c9fc6adabee0d628b400b161ce5d4e12d82bff83c3e165f56dd83dca8ec8b3bfb819f6686543783493475ac459564aba9a9b20cd22f4c6fe412bdc06c0aadb821dcbdb5f0dd6a18c12393feaae83f010001	\\x4f6511e3e0eaef3be891219db900a3c807770f4eabd242a50e132b700b3295443f6806b96690c8b1450944f56dcc3e6f54325081a3bf449cfcf248387b756d03	1667545009000000	1668149809000000	1731221809000000	1825829809000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
217	\\x092697b361db67bd30786bef38f7f3b7c584e347d576d9477e3ba20bb0133b424ac8616a8697074416b158ff956c097b401445827790c4d2ec9ca4aa418ee3bc	1	0	\\x000000010000000000800003c7136f3e705a83025f7660009b81091983fa544440e638b880ff4e0190202363c37886a41f77125884dea1a56b62407e1c4eed3b01f4fac4d31d05b60d690aa694669c8250d9bb97b0878e00b890ce241f181cfd6bf7e4bda41111a79ac282873c5b31c096f5cfc072ebb2a53acd403131952dafaa6c8528ac8734c84f7e32df010001	\\x9ee8dd775d1edde62db6d5d692d747a643aa163881a515db3d7968ccbc46d7e2cb3919013e5e76795d4e3792cdc7c1fa18adf76422a60e2c52b9a530a6f3810b	1656664009000000	1657268809000000	1720340809000000	1814948809000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
218	\\x0a6eb6afeb267b4f4bcb47030cd704908d84f7da5ede4c063a2f7cc3b1d555624c9f4cdd88e4af1ba84543d9ba9c113ea15262e06d8626789cfd0b73a9c8c370	1	0	\\x000000010000000000800003c2cc21d5d4300a0ad87219ad4c2b0839cbdb378f5c2097b3e2963c0304528c5b7b5c332f20885e35cde0a98ea697c43d4553fd4470da3d49e8ebf2b7b14f00afac158e6ddc1cb2146832d55d0bb0808a94e9f62f7789e4e4fd02f8b6d1abfdf750be8bd7a9afa37c3d40cba99b068674e4f43d3c48c2e45e7831d81a5ed91f9f010001	\\xe19ca76705a7fb07caba1e0d23690cdc3c4d460d7fc80ea1b7eaf5a4d13ba7d32785ee3b522cecf8f7428b18df1c473958fa9c9d0c0149f8070f8cf50ed2bb03	1662104509000000	1662709309000000	1725781309000000	1820389309000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
219	\\x0daaad9dc392413ffec1344d260c64cc7057b3074f25b886b84e2174720b4a25109d30601b57a3debae33d26a708fa8af1badd6c8956924fbd2f6fd31451f0d3	1	0	\\x000000010000000000800003c7afc41f20b36856798e79f9283f5afc2391ee6afed2dd7f411d074d76c9db45e1b9bed661c576560088a3ff46444d0a2bcb81a437b9bb3216f633b50e3cd6962b97ffd9c36f535f289c429b2fa13653f9cb6cbf4eac71f68bc02fa8f701097223500e3362a3931ea9593083af1df8b6dff40f22f2b28a2d0d9045f7bb225bf3010001	\\x69bd347f2846a94efec27153a6c202a847ac34a677fe751effdb875b763b73bd4e2b7f2d1b34aeb0406d9b209e59ab3ce0ce5507fcbe79aeb6db9bc8e9323b09	1676612509000000	1677217309000000	1740289309000000	1834897309000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
220	\\x115e537be6d1a0e03db19ae6b20118e92bc8a591f1f46baf34c0bf8e887bd02e5c0fbaea65fa5e68abebf7305934c167245e7e968b48c9223bccafca9f3600c7	1	0	\\x000000010000000000800003d96135d36f32e53060350c1106693204a16b37b9a77507a0ca27e85c33881fd13f8bf1242e91a2b761b371303ca2f54f4626b216f5a148fc1807a5e10f6deb3dbc2c5e5aac08d2adce10b57ed5534635b97c0883fb60443e2deb9605d14d7743102d32898c88f2dcdf00240d8653d335d94de97df2e8fc996c202e76699b6e21010001	\\xb87e82c66dcb5eab3088a67aa369d412f6966a7f6ab1b7e9010ebe366c5c6cb30bbdbcf62d48879d2e775028264b5c97994c5ea4e00552cc3c3c93bc8ea6860b	1675403509000000	1676008309000000	1739080309000000	1833688309000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
221	\\x14668f26cee9d6a6726d78060ca44724a0b972fa0c6cf6cdb6b514f41c5518d7e97e5cf25a246532236456886b71b7cd9ff98c7101cc33e5e4320f0f990203b7	1	0	\\x000000010000000000800003b62118fd78efd27085d5bc8c20f0d04d54adb2cc693363596a900f852e45dc2194e4e32d8a674472c93cbba56b37ed219a9e71a3b49dec8e2b0a37b62577b3a94e2412646a9dfbd7e902b9fb589eb18191ad6ea0a3cc4ed6eaf276251c4a7af1546d570d3a4fbdd31ae41908b3cf59c603de89722af38f193882d162a2549fdb010001	\\x4e48e41841057fc7a1fd9c04935c351eb63556239c4758dc13015b393e36b72c226db3deda82018fde79fc9f28557a35faa1e65b1dd4fa6d1f06c646f798f905	1651828009000000	1652432809000000	1715504809000000	1810112809000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
222	\\x166202b8aa3cdded0e9b32829a3c51c7447c242776d9c062ee497e4f080bfcbbd08f07d132825426cc4638405098614607690dea2417ee1207244b8f28431780	1	0	\\x000000010000000000800003dcfef559a017a53631ae5d2f9e09d31b566fddb7dd8900e7d57c111db954bb0ff7ed1966dfde982c2bbfe132a72c633f2d4568b501c4c9a055db96aea715fc80132f1ac5e6284855eca837c414d9e91692b5f73285f000386d741a6810a8180d29a3790d6b9f6589c12e7e8904fd11020d575bcb36e08a2e14bb8d1649eaf659010001	\\xc35cbd4ec3cb17f52551936497747ebe36811ba0da012c70214405f1dddae6fc35aac98106aa40b6cc02ab0317139467364c7d35f9c7ed944703517fd50c4102	1657268509000000	1657873309000000	1720945309000000	1815553309000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
223	\\x1d1e4ac334d6760821d75f9c975ed3a8d1520cb3d8e8860f75d1f3928dbacd02432b1f0e3e71ffbfe5f2623e38ba8a23b233099506fc426d4396c4a51e7de088	1	0	\\x000000010000000000800003cbf39931698e8416172a476734b2587b5366d7133ee4fc023dbe69885a7640268c3924497f82fd45a3a43427ee6021591d914990da37340087ce787477677231fd5d849ffdc2dd7d29f329e94fe232bf392f44c45939551d4ea4126bd3db7e021d43db295243692a7c8f9f52a5593197121505174c1afc87b244a113187d0963010001	\\xeb9e4752239bb28e7edbf04cb06a53ce80173065f5aa88c832bdeed5c226885d3214d8cc399a85442e1052ac50109c3e21071da9847914615a1091ce02afe400	1662709009000000	1663313809000000	1726385809000000	1820993809000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
224	\\x2022fce415f8c99df3e5d07b0dcb3d2e577c953a292df60478da453356b113447c4482761cce4b4f42a4bc859de8b70a7716ad59b84a3dd5b004000e8a894a61	1	0	\\x000000010000000000800003c2124cce3a7bb4abfbd6f33e2b2e9e4d663ee3bafccc856cd434745b3aa694e6d5d6b4ceae9526410031af93e0bae62a4b385ee90483d852641aa60f1f8ac2bbce36516c5502251f48c70bdf443cd3f18b6d0e0de901b1e53706ef5c83d74799f417a3dad681a2a57a7021a222b27f6dd794b08a9554948e1e9e87b990de4447010001	\\x55336aec9a7bd835a43c52d310f9c760c711670a9fc199958df43167ca15e7483b336df6ad5bc71da47640f5652522f78a584de31e9496bf6b6c9f531f7f810a	1663313509000000	1663918309000000	1726990309000000	1821598309000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
225	\\x20328635e1643a81aef9d36a1837ce8290db9ab1466348e6c5ac85ad5a3f2afe6f1e24a46a864129a952adc6b101bfbcbbfc16420785d2384c691abe9f78ab35	1	0	\\x000000010000000000800003e1fa69a5b77b4fa5a4e84d30235245c7d2d1ded9b5f90142836ed0d58143b96797a2bd03e0baf17e90d276f524471a9ad4584ca47d4a8251e0420c71124602cd958d5adc9167fba890cf6db1f859a19bcc8bbdd9ffd0065af641bc290c916e7bcc289e25477e17b84d0b9137b2125a2869a68ed2ac1466854d6b75e86c9bb231010001	\\x186d2b116a8989a090bc9ec86088077af0c6c5a1989d1569f00f758f875efaf3bf96ccd9dff4b321c854ea12a4d8980cb613a18f685ce05027ad68749725a602	1676008009000000	1676612809000000	1739684809000000	1834292809000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
226	\\x24e289b5d3b24ac34b9014ea9b93e770c968d31eb256dbdfb6cfa749c792f76a4d562bddaa440b6e3f454d24ec3115ccb794634c47943bce881594cda99350a3	1	0	\\x000000010000000000800003d94ba77c4ab38f5c93daeb53596de3d4517f2b2a8540ee7a974708d214db58e34561812e0e490ed99a7b66d44896999f9ed74d1617fa6417fc0fe2fee39c49efcfd571e8459cb1f6ac86543b86bc2d04fd6ac8ae305c374309182e0718a5f915bc0fda3ef38e3f7efe0ad25eaccedd4f6dc50c097776789f03bab378833f86a7010001	\\xba4d8f73852d9d04dd043fcec7a288944eb1f3fa5cb3ae83272ab78da044f1c66b23149e4a85e9b41bccede44f7cb5cd60dff0d3efb6c9fefecf90f27972f600	1660291009000000	1660895809000000	1723967809000000	1818575809000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
227	\\x27e6398add97475dc41749401620730a6af6032813f084c37d7b7ff4eb54a22f0114db1b2d13d6af1b1d6e7d344e774764a59afcfe2fc9e505974b92792262fa	1	0	\\x000000010000000000800003a0460338219f717dd9faab8d5d8bf492f3b5f189444357f941384000542dc5383409c02fd1a471af3332c78b44527f9f61d632d359ebfc583849d5b9cd3458e1909fc1d5ad12ba8934b7022c3f62daa74baee5f88a10007b6f664a43b3b896b259a094d1b3ac3aa2b5ef06b07e558fadc89190fa6f5be0bfd162232d0af69ab5010001	\\x28b82cf5a5c4999c3e7ecf3fae46916f303e2a32ef3fb0d4ff5d8f954bcc1897cb220af8ad7f4a7dc2cced6ca81d816d117ab8672fe34a63829c8fe072288506	1654246009000000	1654850809000000	1717922809000000	1812530809000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
228	\\x2bf2c53d762d49251663f2120df73a26c12cd5c4de2f2ecf172091f95601857d7d4d2464a380663a478b8bf7a3ab53d2e5f3b6379082c897e64445e290babe58	1	0	\\x000000010000000000800003b78af22d18af3f34e33c80bb3b4785b343377028ebbceed8a6ae86196e39010857bbb27c3e90a333be97eefb6071bebb49990a7244024b985530f3eaa02df5bfe74c32b0e7cd9cf24de5afbceb8459dfbee4e13704fda3b3184b963ce524993b2530752e93e3e692505ed3b37b83964ca0e94e95e258c691205c39b0c65740d1010001	\\xc7e3036d382277ed8e81dbaaf0b15d7a4cd6f5b704629b2f5c95b4a551710be940bf9e652fd066ffbe5dde87aaeda60f33af81d85b856b792f76cb05ac02bb0e	1663313509000000	1663918309000000	1726990309000000	1821598309000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
229	\\x2eaee43df23637577c2c06d5d15f2abdd49bd193a16a57c09b222043961e48c4e0db8cc8747f0c8d46ffdcbf09d1c5552eb0c3c7412a355d3c4dfcc508e388af	1	0	\\x000000010000000000800003d1d01d575197fb96a74f6afedaccc902d26effeaa74806c535994031b2099858d46b84ba697a0ebc57b071a13fedf57ce01f100edab02749cdfbc954b719e0c8d9744b2c9d9b9849b1fdf7608032fb62dcc0825917f65eb8780264553f6a91a2153e4e1ac1067c1644702d81caa963239c6a24af4ba439e7bf3eb106d389c1ff010001	\\xf773b56e26f358ba9b519e0513cf877246852ac59f408d7d2e650af8b2023a3d40e7f6768cdf88320ab17d543b9647ba7719df74e167c5e81749c98659fcf705	1666940509000000	1667545309000000	1730617309000000	1825225309000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
230	\\x2f1a5f583a454b1836af8332f5b0cd1151dafab3c07858664d1bb4895bf5a7c4f0b1a9344409e58e202ef06df144edc57010d9b92f8ab4debbfa79de599c715f	1	0	\\x000000010000000000800003f9e8875a9962c53b6c338ea2124c418fdc57b5f38556ca8ad6b6909246b9e5ec00741b2c8ccb00b8a2cdbc28101ef2f256854c2698772cd79a75ae37da65057fface7b499555eaa55240a8ff27434ead49ed743a21088cf34fd235e7edc53ebddfe05270b17d045465ab9ae1579d4a964c69bd921a43286b8b2cef2199e2dddd010001	\\x0aac304fd075aead90a5a4ff38389e0d4301e76ec1decfa9ffa4edddb3d02b6ee4060acb30f4f8ce7e128fa5e4b4943ee4e0bfd2e7ce96ab0f80f6c96bb74906	1663313509000000	1663918309000000	1726990309000000	1821598309000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
231	\\x3146b870caa672c06e76745df4cf85f42e7183146c1e96d6d9589d6a8926f600c9e63919ca341af2d20077cf3ceecc3adabfe49e82099eaef8195fc2744b1c9f	1	0	\\x000000010000000000800003b07ddb4afb73649998e5c1bffbde622a96a3978b22bb70e9a3b08d17ff97e5f63d9214fc651bc92855d7f37752520e0aefd8593adfbdc30a833d59065f0cb8a11a57a53ad757ec7b5ca6c021272aefdc087bb9bd3c837ddd9d4c043555d3c0ad03f2416cec395ef1bc50b47949547e2f4bb742dd42eb456575554c93f450e955010001	\\x78da353889c6d2bbf099d66053dfd4b3300147867d45349385c71ff65e33a1add167bb88d1411bab2e50ed1159fcfbaf7629660a1388e644cb3066f5f79bd20d	1662709009000000	1663313809000000	1726385809000000	1820993809000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
232	\\x3346e5370fcfe3e40e0a1c0af103684902d19a9025e3bff121991e21fb6a4a70efeab68a05cd34daa885abba927186cf36cc8d3027aa60464886856564189898	1	0	\\x000000010000000000800003d78aa1594b98e570ab848c6db2a4154859df139d8afb686785146aa10b6d441726cd6413d421da7cc5e0d00a67195b45d1d6d7dce1edc9a29f2d46f7f14e76ca0c12cf61f08705d258c55690528a84245e8921003c0f3557b007fc7e6fd03e7efeb19241e70b21bdc3bd73b15c95cb3419c467e6f4ea0299081d28f9862c357b010001	\\x01f5f0ff58c28a2a225fdcf01989c448d48dda47013e248721af00a373a5a841ae2c76d43606a6da099c1227d92a70305973416ee9bf3f64892d4e1a8a9a800e	1678426009000000	1679030809000000	1742102809000000	1836710809000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
233	\\x34ca1ebe9a117fe8e1424d8d623656d0ade5272a603342f45ac1c4091d2004fe038d97d84f5bfb76eb241d63ba335f7785d39f821cd3f7d6ba1fd95892f5063d	1	0	\\x000000010000000000800003d850db6bf7b300f84001adc54572dcca118d10c3f0c5c1fc6991f92102dc8fb6ecff17779b4dfcae2d57a1f16e7d57fc43fe4917866fea99f7e4d40f69b733083c9d1b0cabcebe469dd3b5d77ab061996d60eefd64d3a07407ea877ef0db5cac8ea24916281ed31e3b21fdc743b2fa6d3f1a413123ca4709f21ddefac6a9c5c5010001	\\xc0ac3f3fb9c92e5da9098b580a22917572137747ac7f3b5a916beb6741bc21ddfb4d082b03468ab419bef5d3637a13d9255562f8afc967bf888922108d56220a	1656059509000000	1656664309000000	1719736309000000	1814344309000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
234	\\x362e27c70c99d75a7091e91874d23a52d64e269dda1e4fd80015239bd217db75930cc96e5ce9ddb4de2c80c43b6f49ffe2ddf60587dbcd350e30572680ebfdd9	1	0	\\x000000010000000000800003eb6a250af63ca4d227562d9a25cfe37a9df9a9df2fb3e1e76f5b9941363f675ae8e17ec3d2090ff0f3deb43c1dddfa734df21c8d0a752fba8079c36b718ad5e2f452267543ea83784c9995fdae92434df10fb98e7a229290788db08b57fa92842e0b883f7f2b052c4a1dde7fbbff425e82db717c6e738f520afbdf458fe47219010001	\\x03716ab08cefe4d3f0d4c862d044869e1e8f29c5a5c4f02a366cefa038e257118e417b777e1853fb9fe4d91e0a7d53f54054b140c00cf99bfc96c3db1ac3ab07	1655455009000000	1656059809000000	1719131809000000	1813739809000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
235	\\x3bf261224f81e21bc7aef632aa4241df94e137f9c0ba24821337a8fd34fea0c45c2bbd83114b61aa44b145ef5ba32324409960d5be2a6bf2ab83603084cb75ed	1	0	\\x0000000100000000008000039b4c04f2232f0e438a0b158c61255bba84afd9e56b229b97933663ae007c38466a960ce0803fccd61aa49884a55ec430c973002bf85c8884dda82905e0496d48f58d7df8077c32501908c1184104fb20c9a926fcd14cd61d4a8203152ba09899051b20d095193aa24d5d67a10619d793f06c38d9041ee1183a5829b95eb03601010001	\\x624e25dcec93d9dec0d55e027dc28249a576904831ee93952324886d201cbc6989120b3fbab1a54fa208e83ba220228971d54a12b1a7eb155ce3891e54c00f0e	1663918009000000	1664522809000000	1727594809000000	1822202809000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
236	\\x3dc25d2dab036950340730628f167eeba29ff63597174248be0005df07b00b5fe8d5c962c7e1dc2a632bae0a993d3f9ea2a1567f678cb11af34ac40b3390615a	1	0	\\x000000010000000000800003ca25448cff9773bef58de7275796b673dacfbbe2684bf2c44be545f0862a094ead14b84cc389fe9cc026d80e79f38b6385ede2c9a2341860fda6289a2f82a364824ac7414cc1a44cae24040ca223312f1d189ac499ef604b2b9bf44378bba598b8c80e2ed037d55520e77ed07ff2f5525473c7585e2d93a6a4867f5d37fd766f010001	\\xe51d89072cdbffc08af515414403b0ddbe24a55032fd0fea1c33760078a44fc553acccb439d7fc69dd31a7295856bc3ff7a7904cdbadf875b8528a2486674f03	1670567509000000	1671172309000000	1734244309000000	1828852309000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
237	\\x40fa027f4ab50970b952464ef85f1c57ab1ed320d0235c5e76cf3a85b653c223ebf55219b2fb3ede80e25615234853dbc48dbf3aba8381e4aa34d7663f6065fb	1	0	\\x000000010000000000800003b5c1def911bc5c22d8228cd68bc7dcd1d395256fb9baec1c6119e3b47a56d81d984d142b6da443965603cf4f5b8a15a4f19c6cba153a83dd912939d4f6fefcd4fb85cf8c17a7580bf472f853a2964105d5dd8f8073a425e046c82ef6f84a330b3db41eb75d59ad1a25fced85de76d9114b58bf3bbca66eaecf6502eafaa93d75010001	\\x64649bfb0786fe88d22f4038a789dec04162b9e27937f5468326f6acba50eb29007013a255cb799ee70cbb80f0226442a37cb5add120b0e5b99a145989b76e09	1651223509000000	1651828309000000	1714900309000000	1809508309000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
238	\\x4792db3632e10b6f2e6678e60fc2fd9b5544e014a1b122c650793b5f4d80ceef0fd71152810c1ff5321b695c21027daef6c714bb9395ce446e4a1b6f5a33df8a	1	0	\\x000000010000000000800003c0dd0a8d77de99d1d5af15a9d1031dd4259f50c0d0cd04d1db8327862b184c07906fbb0faca19c7d9f2ed7b0d0df19544584877803f67e3e6299fb5b25c3480e89d1a9ee645e69fceb6610c6227da2ae928f0842b0ae52c2e129248e1b999e3b2a871ee08fd7808c9a32d9e136d56321903a0fa8207f9ce3390497a64b0a5db7010001	\\x3830146d249d56b37e2aa2f3f7092a983894d5d6cae44f39d5b8eb0d119af80488ca37417623cd1c1530c57d261e8487e15b412c14edb1e86ecd967afa600306	1675403509000000	1676008309000000	1739080309000000	1833688309000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
239	\\x4c3ed657f3b1772b8fed4ad986aa504b3322e19e647be5f034d3a9c79aa66695e2dde2c8f2de88a4e3dcfaabd06baa179e1c844660ca97d0953e78e30903991b	1	0	\\x0000000100000000008000039b6930027eef3b4eeba19c77e5e615756eb36ddfa3fe0233c6a54dce85eb0ece632978c4ad4dbd476b8d6a81e9e51da56e7b4b1d4eca4b9241f2bad0dec1ba4e40804f153a7b485e08dcbaf966ac9d482f57e247c75e1cc65495ac8f2522448b7416ce2616d5f1a3f4ea65e4e71dc000b56c7f885c43bb499df975809dcf229d010001	\\xea4037bb9e3f9b757cf18786201f388c920ecd14193600a05a3191e6578b7d0c8ab127815f85bb12cda9479931f17485e3ea8cc4bd7e89705f186eaf2ba45400	1674799009000000	1675403809000000	1738475809000000	1833083809000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
240	\\x5652c4796052b80667ab310cff64e40f9ca86b0d4a2e8ba84f75124bbbe43a2c9bb4d047c67f769434932e2adec5dd4779ffcb456d0f2256fdfd20a1dfed1ac7	1	0	\\x000000010000000000800003c25546f0c8b87e31aa4252ad1b69c77ca020a9f1a842f82b05955cdaf8c556563a1ee0b841e0b9a8e2ff2c21c3f361d40d0935ad15740a321949a4ce78690498f0300f4c583557135e5c7acdc3fe1acb24e1be32cc8e7b6a47285ffbee4137f08a68b7e9d541285742f2770c6542fab3c1ab9c6a43cc9cf9642933ed3bccdcb3010001	\\x7dbb2c60ad704a9b04e816ac089cb98d64655e6386cebf0fc970425a2d4c8697b925499307555910e25823f2e865e1ebfa7b029c71cfc479ae911d60f6ceae0c	1673590009000000	1674194809000000	1737266809000000	1831874809000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
241	\\x58f2bb59796b19140658ee2bc73e922aa797b52a5b899901cdeadc63c580d487b15dfcd0a790802cc3367623688645411ca974a15651c417368a7dac3437e414	1	0	\\x000000010000000000800003ba26a4c131638d7ab4c6f1fec9e06382421d16f6e6d6dd32f9a6a989ebdcd7fad71c7482049802c7f9ac756cb828668e81bc567301c36b6e1dde12fd520a070a654b205c55c4429451696be150bc0cd3fe5068968959e0176171f0fd04aa74a77455687d3b4e6efaa4820cfdf8b56aba99f1546a9efffdbbe785f8e31d9bb8ab010001	\\x043d68b67d16546e1a2aa45cba31c680e5646faaaccfca377ed68b61e13f7e29a11779beae7f36bffb716f4b584de7fc8fb11a9fd88c04b72aa7f21d8aea2e02	1660895509000000	1661500309000000	1724572309000000	1819180309000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
242	\\x5cbe4b95f322dad6125f90c128a53dd801adcfb2d9b89a387d933fea2d2ce7d16a4e5534fc79b4d4f591d5d8b77fb11c0acb76b75f94d92da186049cad007a92	1	0	\\x000000010000000000800003d70a058032bd66344f0b21089a6198be7004fc60632254da2fe827bb8ef0de6f703d058ccfe1e8a5c39b75e7a1e3f11900197f034c7402f370cc29ef8af54a04b994d698b98c23804d5b90233c8f5607f64aa35f4a0f403f3d0832df9dca4ee1ea0e755f6bb2eafefa0df331051718e313017ef5d48625d9e39482468e81c1ed010001	\\x05eaa3dde07ab4091d665cc8a3b66bed53428a5f3b80e3d06baf158c1281586dffb89aa7fc9278f5c94055c31463258fbeb8eb37780af6bd0bae904a19262507	1672985509000000	1673590309000000	1736662309000000	1831270309000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
243	\\x5deabeb81f533d5cc69e01fc8a96b5dce708f87df8029526c2609b48fa9dc98f6cca6816a1408a0090aadaaddb9b24aa1e160a7e65ce20e6599cc0e5528d8981	1	0	\\x000000010000000000800003e5bf398747a94634aa402684d379ac06e7a6cf8352f60d6cc19ef66f8eaad15482dea097b5e1cfe50daf894174a1f1e1de57deaaf16763b37479b8c0ed3c60bfb25c73e52ecf559941960e8cfa6fc3fd9c34aa74e8138cab7bd3ccd32f69823b8196b039f0d86f20dd264e24f846d13eb8cbdc1fc051a3cd6a88f605b3f65e01010001	\\x0b1f64c63f83b2c22f977f58135cb06fa56e73eeb2ddd29f6f1d2e0babd58c421824dccf4d7ffc57f19b302116ffa558fbf5a5ea60416c9fae5c8f139acc160b	1659686509000000	1660291309000000	1723363309000000	1817971309000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
244	\\x5daa5a94a1e25638cbf00ed246e490345e26fce2c92c4c80508f05268f0325222ccb11bd81c7335c44940144222d09e99688c790354d7c354b1cbcce0e1bd6c9	1	0	\\x0000000100000000008000039f07dd07a9232a4c539062e5e1c56df0d4e4090b9c10be69caef1a410ec200328623ced7e6e192ec62f46284cf03a3dd157a4808e43ea3f561392b7576d67add5967876cd82190fca67cf67e49afce23bbae7f832f73d2f7316161cd30a093756be950fe07970edee5696aeb7919fe810be65bc172edff10dafdee55e1e47a09010001	\\x31dcad04e9ebaf3a4096a1c4a7b0c8c035f7655e43ee8d1c50e437f4863b1f19b731ac5e2c10e30159bbaf1d41a81530ee732d694b534fec7c97a4e88cfeeb09	1680239509000000	1680844309000000	1743916309000000	1838524309000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
245	\\x63127500e655517c7959cbf3073eea642f224d4fc0d19d21d36234b19bd924190e3fe634054ab3c93ef742ab8569087784a46c86a8de95d7c60d5db6d4dafb5b	1	0	\\x000000010000000000800003d92e2f83128f8ac6d1538258281d40a46bd3ae44dcc45c7a80150515c9a8fff480411bdf69b71ebabccf6fb1f380f334214926251f5743beb8cf0e7373dc8b59891dca56949e5a829a37e2cafed38b167c75e35d2ba2afad26bea3d1d603cec1e8e6521bb8b043808acae5edfcea062db9b0d99d27dc9834b66bf977d628d28b010001	\\xa8f3f240226830c5ace167db268de2ba8c070a527b2afd3b754c0180403fa9a519892e7cc3c5401fb5740556e7be60c1ed79c44d892a42975ef607d9ccb36d04	1654850509000000	1655455309000000	1718527309000000	1813135309000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
246	\\x64cae9c24665a6fd38ba8117a234a24ac1b65d9fea696ff451db5a7f5e2ab99b5be170121bab2c208d0a37d5f001b4c3817190c8f71b53339d74b27ff02a8adc	1	0	\\x000000010000000000800003a25b2e38e30a2d6a558cd8ccfbaea7bd4bc92c76fbee3a2167af3d1bd34b320fd3ab9862dc8f24c5758fee6105cca81d2ffc6c1c0183fc2c7e69f863ccf158f0eb6db4d4639fa565a11fa9e5176be7c00a3298ac44d70fa9641647e3953eb3ff9fe05010fc94e5031df8dbf14fadefd57b695f452f93804156c57a67298c42f1010001	\\xd987da1fe24a42bf8114605b4ccf8aa967afc3cf06df68f96ed2469501a1f49a90a27562aa5f9cd3e4cf52e5595450342910086df34844ca543d41242da8c50b	1663918009000000	1664522809000000	1727594809000000	1822202809000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
247	\\x675a3206fea41f2bd0fec79a4ef30973599eb3b92a0d03008fd0b217a39af70036a417fbd889b2b2e79a8d3548457b3bd7492215a5cf3e3bc7a78761b8b9634e	1	0	\\x000000010000000000800003c6c53dc55938a0c9006152864a9af89e78a01b2bfef4dc50a687daf55115a6f00a1f581b1c3d72ebfbfb38acfe38abdce248ba1eccda3d6bd40484e7777dbcb766c65c3077a48496a27a23195793e3ee6b361c452ad752aa72bbff1ed0b6544cf176d1081ba5494278bf72546f5e9d060631cb84c287d5dee8ece04e36c495f9010001	\\xd92e30439b72ad368919880935256e5f4201d12135744689c7656b0fd070b966f01a683ff799ff1abdf31f2e58d68c219de7c338da36e3023047a89e098d0009	1651828009000000	1652432809000000	1715504809000000	1810112809000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
248	\\x678a2b001605aa6cfd305a13facf846d5ce8fb179d77cc2104494fdd3e1c3becff7f154232ece50f608604b25d656dd74f51733d69588461d6891c316a9b47c1	1	0	\\x000000010000000000800003e2a75c9f6d577544fefcd659d0c87dde7b76e0712c311bb3c3286e0e0807ee8705de2a801931f14d765c0f630344acc799d653a575af308f938c23878cc10e3c320b6396b5b36f1ac3026910b91594eaa67b8258d8d182963e723c5bd24a2ca6044f881087a797267eeb407b91d7f96a0e9241345c334195f7524861e7c1ace5010001	\\x0703a1f947377d316f6a83c80855d11deaea138797aa889c258b8019a93c29d09d10f29dc7d07c0797c527554ee6a43bb2d3cbfee8ca848a485c386124aa1f03	1674194509000000	1674799309000000	1737871309000000	1832479309000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
249	\\x688677c3a1cf9d02daa350fb3588819b9bfb9f6a58f4ddffe0ad982690e7af13128f208c573117cac750b985d26ef1d94dd219a8783b7ca804542eec4c58cf03	1	0	\\x000000010000000000800003be05c90900e7abe07f46ef7f557ae543ecc3549187341dd315796793dce6f2797206359636015f54fa7df807a7b90655a268b36960c3c18d8326e4bdbb3cd5d7a1bf02d4335b60ea552ee076b0e128ba20d5c4f686b320bb2ced4c550a03f86ff6a70e003003c4cc226b357927dc62e2e7356dc10f2276b509d39a4e25e346cd010001	\\x222524755d7a9b83b724752299f8da60ad68c095f4734d50f8967639b7f30b82894323d3eb5f614d00367fa2132a1d9208371f15e664abc2e9797fa11612e400	1673590009000000	1674194809000000	1737266809000000	1831874809000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
250	\\x6bf60bfcbd1a05648ed7e847f0c7578b86c621e274e5c1e633a3a9a72013a393942601bdb65f144fc6d0eb5d201dde0d87e8583c5a2e8f3d444ec6201d07d06d	1	0	\\x000000010000000000800003dbcee56d55cb77ccaf70669b48478680f1ed14730663535b5e15236f52b854ed001700e5ce8a1eabaa6157738441a90f110717e8c6e5fd6ff93d9a0a213d286b53338e02ddbd1ac8b549502f08b64b6f83e30cca0415624988195777ca6faaba3eeb1ebf5467cf9e26dc8d126b079aeb9380f003040bb2e771445ec8b1d41ea1010001	\\x7b4f5923f04551ca60aef3cce6d2f776b0289cf9e9850490901e5a2d8b8dcf8f6fb30e94e56a90a1522bb01cd861e2c4966f153064e1b380e1a03994c7df830e	1652432509000000	1653037309000000	1716109309000000	1810717309000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
251	\\x6d42e42282fa06ce97bb0ea27d399ec61e1e41d7b6bf2f92fee77d4f67ec400c130b89330fcee994304979a9969fab761426c7a1208a195cc7a9faf51ef7b98d	1	0	\\x000000010000000000800003b56fbb03f44064262b8acfcf2154c9ddfdf89487b9d0714fdd79211893e0e611a4b7fb0b79ba6eb295757f57f07e751a7ce3452fd42bfafa8ad9cf00d7e7207f7d72541df5c53d01db62dee9406bc26c3c2e964d2053ebf6e0df9da89a912e41da8aca5a0437fd3627ee6c2b607e41a6a2b797ad5af6983b618ff42e200f5d55010001	\\x332cf7cdc07dd491f1c14336e5906833398ba7b2f66100e3cee15d21a1ed877f6220f3d76fe4e7674ea17b6d76cccaf01079a04e47193aa042948dae9ec51801	1659082009000000	1659686809000000	1722758809000000	1817366809000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
252	\\x7192e4dd828a397187f58d69c510e712e028584561407b679904fda747e51313b239dc6373016f985983d98f1253247f9c3eda8af9dec5845e099536244adc3f	1	0	\\x000000010000000000800003b0937759af301786e133107d9054455c3944cb6e182d2d50d5c8d745d4745198907b4fbe7c531bf2f7517e6a46edf19ff56712b195946f14bba92841cb4a6fae2c79b880f8ccd9d36c7ce21662274a4fa25678008ad8fc0730d4cf819566cf30ceb66eb33ee99818f78a82fd6526ce4ad93b355bdab5b4de60543b6e72ad588f010001	\\xec75d9a9adf2ddd135f4344ed31ef0696fc33bb4549f44481f3bd4d892ae5091ee3915ddc9f22786867263fb6431d53a64b1667aef47b8c3e256749f71de1c03	1665731509000000	1666336309000000	1729408309000000	1824016309000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
253	\\x71ee7ad8f36aa7c928fc8ea87f5aa935c294c6b2c836b29b0342ef6004ba0303d476f58d8abf10c1ea07ea5e65e6b994dbf954200ae23c319a6af69d1942b965	1	0	\\x000000010000000000800003d9fd0d1bbdbde94e1a4fa3a4a2823b318af8a4eca0b1c2987d6837a1466e7a3e04ae40c9feaa3ff5e2013800d45960ec3b7a804b1387a205fd3424f0f0b9f9c0f69f9eed3425b23007b2ea6ba3993906860d334c7febc5f4d1d08d413cf79af15ce3d442fbb84d7667114d7861337a95ad82524e06ca7893b6285e0dea78762d010001	\\x063de96dd425864b246e727d09d924a8e3e6dceb3d678717c9fb62d9758d0b9ea58aaed62cab73bf7b9f852233f6934e82e00896f36f2a4ed90899caf3e1e70f	1672381009000000	1672985809000000	1736057809000000	1830665809000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
254	\\x72c27a064a32a1f530a6264d22a3e05e5aa624b370a6faf12499057155917771f338bb8be48bcf2e1bc9ada181f0d82059a42791906fb7d7936023235b26c361	1	0	\\x000000010000000000800003b94a2b6f12fffe025080d15e0e6b498908e55a195a80060cbf50fdba54001e1579079a3751e07c30172019d8c3695e1718667625385902ca43f846fc2369ddf8dbf0d361212b89b46979fe06f3fc475f0f5a39e695d1d12a38b8bd358b873d99f909a79a39724a3340b23b1457a9995745f3b6defd0b4cf99c923da83d75356f010001	\\x85f93725ffcea3fc404a569d430bb2ec1dfda6ff8766e4f00819bf688208da2e9073efb101bd6fc2bd6a86156c4291a955390d6709127eddfa9cd68071cfc103	1666336009000000	1666940809000000	1730012809000000	1824620809000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
255	\\x78ea8d833ac13b060b723fd0ba31b74ff86c11954ffcecd98a68c4cecdd15320dacce410294bb1a96632116d48e344cc9df27c2039f221e0ff19e018c4af144b	1	0	\\x000000010000000000800003ab376ef232dc94771588ee8cead627e48319096a6a57e5cc5fe4178526b1cbddca208757522dbc731ec3834571ccdae723d3ddfd89167109f58c3be12f6c31659a91bfee2ee1976d0eec3b18a1e88d49244612a4e0651710fc3567b48a394486756afd435168766b074db5f60aebaaa03d2a814a65166153d413ee71e3865e0f010001	\\x54bacd3f899fd055eadb8d919f93d40b1a75023e3323e85a3fa395a908f8e3796c40065b1c223b4f2fa976ee3d09d9e6e9d393aec8048b35187b550db833d004	1676008009000000	1676612809000000	1739684809000000	1834292809000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
256	\\x799a75340f46a2f549ee8f4a067ddc7bbb98608a7ea1914ec5cb253013c068ba80c4b2a5f5f15748a48a68e05a75649a14305d7e0c7a9a49606099b276dc2199	1	0	\\x000000010000000000800003e5d0302caa9c774c9e6806703e0ddfbc1203e6215466e7740bdcfe58c4556fc7f9091a93c49fbd15f2b8b867487d288abf76e8ac5e1b2d3556658b685320e02b74e6abe021ab80d7fabcb717cbfc8dcce514bb747926d5263d392e4dfdd5ae6866c80b8ba3e547ceb2bd1581b226b3963b1c9341ba7f055c5c70889f41cdc0eb010001	\\x976f76148044ae3d194226ad07e2014d423f6ef20dee372b1b5be0540d53515daaa791e761b34e238e45b678f6abeda7e86b04cf52472d15dbf5a851db4ff706	1650014509000000	1650619309000000	1713691309000000	1808299309000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
257	\\x7fde90e1fdefc3b9447d2184f4019cbc1e67f1614e23d3ea6f6c61ba5f7774259ab222257139c57ad0908bc2d426a07239e6a9e496443f0e9c9674a23822c1a1	1	0	\\x000000010000000000800003a6742a45b18cc124371ab0718ad6f63e7ee111d36071ea60afab1bd6bfbe1344f2499660bc78fd1ee1a78cbf6452e670049af9d676dd7b268079fccc9e689e5e9178b5e7daf9e5413424d84ea748c937810d9de8154758af6f2146b19ccd0ac34b368e8bdf1ae442bfc9dbdd87b2a10d715bda0f3ae4134f38a3454c900bb9f1010001	\\x7c0a966e1043d25ee60147017c953d4c3acafef34ad70f375b9c6f271eecb16399c5daf256d58b55c79f5f6c35a9b0d6ff30ae440d0c4531cbe7d552acc1a102	1676612509000000	1677217309000000	1740289309000000	1834897309000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
258	\\x801edc69d5dc984e67b52b438f639fe1e2614a296c46b13f1ca0510109ec802538df9e2277432e216a7270c0e22df00e2a9e8ff1dd15efb3c636b52780b2411e	1	0	\\x000000010000000000800003cf0093ea7999ec4b839ebd764f4429e78a0cb66beb22e80f0006bbb17dc02dd305ffc513f9eb80f0573a1a58124467fbf2a9ee7ebcb0101486f10b915fd31e01a01797b2d18ffb61ea56eea478dfc8998fdccce5087278ad979ee2b4a33d08c80e044b703109046ae6d380abd17ff60de1a2bbc8e11cfbde843947ca09b6798d010001	\\x9d479275f7d354f5dd8eac524c0d65bda3bd883955a6a7ac18da7982ec042555389a59a3fe96609fb1f5e56ed655905d24781f0ed515e5093870c83ed3f16e05	1662709009000000	1663313809000000	1726385809000000	1820993809000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
259	\\x83ead74a1c593791cf264619e9e0ab7a9897344e6078aee6685b80c34b7fe1fc3f37605de42e1d1d95b233150926ffb7b6cc234e4c4a26063468ad66b8af693a	1	0	\\x000000010000000000800003e870912b440206f6fac50e774f98bf7971ff2174b371dc2b3153c5496de219115351bb4d71c29d52aceaf2b7de5647746bc9d7ba4be8c163797126ed2cf0823e8f4b43fa65b6c77df0b4c886ea148b6cc42168df4977ceec3523cb9fc7e8e61f81bfef0055d255e338e6f3a73461fdaad223edc89f14ec24cd21b9b1a6801d13010001	\\x1cc37f526ee91bb99a2b65515d017b901c0d8bb3c7b673d4aaa473fc095b1c9538ddbdbe41579980ad9d7ee8fcaa0fec445b16839847ea5931afdc00a4015600	1679635009000000	1680239809000000	1743311809000000	1837919809000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
260	\\x84eaa3f572bba89b87645e9104503b045cc3af6d0ec2f2100e488df6215c05140446a506a170f0567b7e37aac542cec747bfc90bd7d2441916ab1d051ca1b947	1	0	\\x000000010000000000800003c3cda955bb5ffec15aa18acf0b4319ded53ffe7fe4abfa0ecbe105ab795c2ac9f7d2b9bfd69f1aa6ea893d5f52e6f3cd9def99c3bf0dc70af1b8227829629f075e810e0b9b401fafc4539bf5c494de8497ee2021a53a5e333c52a6814e11579214400aceee1a740df40180488a27b757428cecdfeb4bc70868d76ec4afd73047010001	\\xbf9d84aa401eca6f6a9cf427230d6ce559e749303c2562a21e35c192d44e4b328f406b75d59e35c33625bdb782cf90f4ed2a98955ff41a794a27986dbabb8900	1662104509000000	1662709309000000	1725781309000000	1820389309000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
261	\\x85da08ee8e203d9ae1037a278b286cb88e3ddb8a128f739bdb47d95a626948854b83edf30862258b5404abd0167120d8784b79756e72627bb92695a572829072	1	0	\\x000000010000000000800003a3dcd48faa971aa975b8d7d003d78f84eaff40a4ffc886ed27c341907bdf51b06e4fda01ade806b2274970a3c40974bd29c5fdf295e15093bdd8faf326beaa19777693502a4ccfb57fae42a8233b52eaaa6910a2c3d616daff83e3ec3974d906ce1b8529893ecdede3ab89a3f41b8b6746aca2b3fe77c21cbb389517622c94b5010001	\\x2e52441b27c877b7b32a35260b6c696a96176626b43afb206da5a578eb798824b2f621365423dd56464a93d21dc53cf2dc4b18cd511d9305cc3f55055319030e	1663918009000000	1664522809000000	1727594809000000	1822202809000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
262	\\x874a3caee5f355e9467a4a58b9c63104e12b87d383be93ad0dd3f88c7a942e06c8886a64a67fd0d0fbe409336011fd020eec9416a7bb944bb9cc01bda6cc3d68	1	0	\\x000000010000000000800003b7f9d75d7ca9e351393e6e6ff1ea6f18f0f55e6c84e779b924d3e69143dce8ce6d340ecdf55945b63e2ea3a3d9ce8a657b85d65d323ee3c4b342d422f860f160073c96c781618f4858b7c39930ecc3a1505adb0a6c89b8951638c81303f35afba4c1cc18a40b6314472edc76ede842e196b04a95222f67e916521ad1b2467191010001	\\x23c3f51985f573cfce11c0a0377588d8f609d9ad8ac3843aa6eafa366c302e852400dc7a97932f7e54034c182d5d9abdb761226c126203841bd6724c45c8360d	1679030509000000	1679635309000000	1742707309000000	1837315309000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
263	\\x888e2dbcdfaa66781b46111b4b1bdde6691ae294d27a6c7f14516ce74ceead2f20b22935c4b71c44cfd61acb2bc0fd739e44bfc94397d61dc62796b9ddc51bb4	1	0	\\x000000010000000000800003f7876819d042ce9f1890d071a51f498174d17d2055d9bf6cab562b2ceb543f98c6908db2ea58b44414ba9d8675c56c27572492ab174289bb019bb1b59c331b6da7a414a1fd63c38cab890000c2bde48ea06272f661f76e6bb5d60b384e9a2fc236703780da8e483891ed710475d1558dc0e542e14a3502a92dca68a991dfb4eb010001	\\x3b2fead9a9e0de154749a49d46ddf1cda583517acffc012610194c60c7865d3d77dba6703dc8f2fdfe61c1a4893f2d28460edd007d3565a8d5ade6b4de6c5a03	1655455009000000	1656059809000000	1719131809000000	1813739809000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
264	\\x8dca8afc90d0ad2a45508ca7d33ef6f2c86003684b75c80193b295b2c358674418b53c0b236fab942f02aec9d7228a348720c88c187a6718c64c49be330606d7	1	0	\\x000000010000000000800003bb9ba7adb1a711646db91535062032357515a15957acc08fc883b4811d76f6dd2a55cac182d5a6709baebc52ed5e28f550526f23af50e7a7d6fae73538375f02c7ce1095a9f7efd9c97b38f9c36ecbf50b858f51ff8e1049b7065190a39323f20217a0169837007099e40c35c8b50a4410d607d4fb4e9df478fa161035c103f3010001	\\xb50b1d19ece3f8d2d7202962f7a773b1d8510a973dbd37b34c93a4d71ab45470dd185e2808cea5adf30f7bc67f8614a0611fc67d082e056f82f81d6295f6d204	1652432509000000	1653037309000000	1716109309000000	1810717309000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
265	\\x8deefab448aa4faf4da806560a19308bcecfd487a0be6b6da4bd03ba83c8ed8f7da5b7f8f67018f3fcbb76a55996465041062c4100d908abcf562e7b29b10c45	1	0	\\x000000010000000000800003b34dc2ab99c7648a2f1b3dd82444e71329b2965dc59fe7c9a3ff7cdfeac349be2d2ec136d47643d65b144d39e3a8d06d364e67d70de43e889ce1b456acd32ccdfe4aee755f77aaeb5bf89b9df89ce90e525ae43560c0c900341063d437450ffe35441940e57005ac5369280b80b9b2675b1bd7a69fbc6368a99472cb7c835057010001	\\x2ce4b86cc6bcc492ad06ba93d29d253fb78ca80fd575cf05ddddd9cc52cfd1aed8b583c53003985fa0b03ceabdac52d229ece997047dfe90c54aeadad2773f04	1669963009000000	1670567809000000	1733639809000000	1828247809000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
266	\\x8ee6d20d5b9ebc1ea68e567e05ce1013fd89b5ac470511c1da8174b73fda45bf78e4d576ca97cecf2967f5d8a265c3516cdac0376605032b48951455c9af242b	1	0	\\x000000010000000000800003d442d63d9f8f82abef145826274aadb8d27c5f807af9c474c84fae5d44edfd38deb7c2dd79d93110663fb660b122fcae35ad1620867c42c77ced70b1799fbdf49fb391dcb6fb0cc5d0053f4f191d25cd6a45189aa2a1c72997337a2ad37dc322db0aa81b2e38463ed69593671d41249cb1045850eb3fb02b90014004beabaab3010001	\\x32f6a8388ac33aa109e798642b95ee2075743a9c6646e039b0cf2603b1070434338db146894cca62146bade15392a224fefd68f5af41942af8da2c69264a3905	1662104509000000	1662709309000000	1725781309000000	1820389309000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
267	\\x907277301feb849c3dd96bdd34384d0d0efd70e74368c1cf85c2d234cbca7ed8647dc1df931ab4d6c52c2747af77250724ac201bbeb9dbdc9cf4f3fce5121146	1	0	\\x000000010000000000800003c8301d9eb1c5e8422e5b64122dad8eba2da319f2a82e7df56354a2c71568ca0b8d69e297814537a46a63dd50a353540e7e0608f93dc61b0f8a186a7bf0566c74de32b074f026efe8c04ed1973dee7f89f3af343e45df5ca7526424aa8f446c7ad78bb899fff00213f21ee05abcfaa57f6d32cd41c1a14edc9cf440923cacac75010001	\\x37181b34d2e60b280fa297f5504cacff97473241a516f0437396e7653c0f0ed9436f7415a2fee4bb4478f0c4db1ed34afcb17cad203bff2491891d30de74af02	1671172009000000	1671776809000000	1734848809000000	1829456809000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
268	\\x963e12aa3af1998fcd91e53fb3bf86b19d4bfb1e17dbce1e2de298a92c641e300f5696a8f861c06824b314b20e15c9c4b294ce1b4cb8dfd26d896b92b86bea3a	1	0	\\x000000010000000000800003b1e9a93e06c4b61a250eee3e25c87b544c218efa3b045f12a01237d4df08b2d53cb467d284328bac588f162a18cfe23020690760d4ca1e3b1d23ab79054aa5bc1134d1b50c846d8f33f123d2d7f579771b152f1be90fa416ded31cc7c41c6bbcc062358aa8a23b81324644d2673c275d5c28455670ccd7a57f33cd4e0cd05ee3010001	\\x5e6c1cbe876b111dbe03ce1b1da6051640a6e0b4ea68101aec01711dbe174c141cd5775a9f7f880167ad02d5934d6439d0a4f9967e4a521ef558c407e7a77a06	1658477509000000	1659082309000000	1722154309000000	1816762309000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
269	\\x96d6a9a1de55f16cf7d31384c270f7a6615650af78f2e54e98b403c11232c55169f27c23eafc6ab3c13969b8a8249ec75701dea6660f79ad4c9d07168e103ebc	1	0	\\x000000010000000000800003d5f64f55281b979addb703e13614b03e8183ae7d8b44a43da7aad74f6a939bcfaf22940ed6b138cf539a3d91055d893ab2f83a2d155f63f4fc522c02f32c8477d20ec4f168080ad0e8fe007c3615289ab98128a94327c3d5c97540baaf91040460cbb9f7dca00d9d1e13b82243d12bc23db36afee9adf5c7e3b83c46dca64f63010001	\\x5b903ad096d99ae91394f449ac67c7f6e51a4bda40ac372107fc96ea0c85f5383a3a9eb9532bd5715b8a772c9f3edc2e8ab9ecb75f91981d1580600152849408	1669358509000000	1669963309000000	1733035309000000	1827643309000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
270	\\x9c5276ef8fb8eeaf0e7572badba39068b292ce518f62707f931f4001c23f26bc2e0983fcef6e14f4f41adf3129f864a92b1e19adb19f3e966d7eadac139b4404	1	0	\\x000000010000000000800003a89c2333eec4c0161b9303080439d920fb24fae9e5ff432306dfb1460ce498d416138f48666c3dccee2bca8c93ff7edd030367b68e8e6ec0ba3f9eff01ae5c1179150e8366e7aa7e4f2df7bf7f942f94045edbea2df3a865e2a64cbb9d37280ede66b79004f57819a054a13aac7704e7c19933a27fa568aad6ea964ea63ef535010001	\\xf6cadd708c20abbc3911a74f14ffd6a050b8c81c6aaaa3855001262aae83534973e66ed82f9c3f7127538d3ec15a368d1bcd9627915fc3d767466731e90dd902	1664522509000000	1665127309000000	1728199309000000	1822807309000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
271	\\x9d0a8bcdb298ecdf89fb83d6296a9600f745ba2a632167032004d83471b0d77724522537141e4dc83ae405c15d544ccd86999a013d326fcb95d1bfc835debc4c	1	0	\\x000000010000000000800003d173bbc5c846887bb80936b82acc2a42434d7d7f562ad893f4fdf33945c321a8866a341701d27ef7f7bc6a2532df8afa0dceb25958eafb1beddd1f6a3ee2ed7a0f6ef66715efee305c6ec39bbada268e7405f6e3b7172ac640ab9a64d012e31af1e29d75ec197cad1ec621508bb2bf8c17642baa5b7a0252ac520f5335a0c019010001	\\xcab86ae28fc96e967322bfd44f1d358b246a32af807c18c095ed8f580fcb337250a56d95777e5a85978aa6fd5ada4f2cc7fe883942baf6aa300bf50df47a2602	1656059509000000	1656664309000000	1719736309000000	1814344309000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
272	\\x9dbec6fdcabb625ba652ecd99f5a55a0ce14e0f9121d3b8c5aa10598f0d677f0e42ab9e864e62ccb6ec476015f302f8b3206edc02837e717a347e9ef6ed00d50	1	0	\\x000000010000000000800003b37e7bbc77ac76e05c5a8bdd2f9225b4effe48ccc46e07c70eeeb5bcec2534aaa5d7a217b7e4f13c82b64904b4be46f3697975e98bee9f8ba1877c758afa3603fd9a3c09cde5adcde320090e9e9c438c145fa2b3fdcea8e5efd976195a9d3e9d122eff965c9d19231c8babb2ab2e809872f45cde4e48de20d6c52215c92eefbb010001	\\xa4c3bbf01233f68bef37aadc838e08ebb09acaacd0c87687ef3f157995023abe300f7bb38d2a635cb79c9a70e760f54ec4b9e3fe0c5e6701888fca8ff17a4d08	1653037009000000	1653641809000000	1716713809000000	1811321809000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
273	\\xa01a37fff23ee1ec439705bd0a225ca106749db840f21f6f207a2c38e54ff241698204d83544f352ece8d780e6e0492925756b10297ae26b4473df2d7911a762	1	0	\\x000000010000000000800003db540caa65f128285e335831d090bdba11dd25d0be6f56e73ff47fc453de5c36a9a797bdb10d45ffda783e75a739a1d46864a8f3685e636bdb4cbe063f391defd901d1f62f1f5b9b1bc72223135f18d99e16af24350ca9d612a7c51275caacb270891a01c4853d63483a83dccc008635a096f45011c163f22979932c548003a7010001	\\xa3484ac678a278e9553148ace9161d6de744a7130d6160c146227cc92d12dac481d5261400183a39d23737a57e21793ea9bb0d9a30d2e39111dec43299477a09	1652432509000000	1653037309000000	1716109309000000	1810717309000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
274	\\xa2e2f6ab35a5a44b60dc004a2269f3568724e51a88381ae48450e8cac033904e7bac80dc67088fa81e4e0eef149e0fb3406021caa0ccaea93d53c190eb92e55f	1	0	\\x000000010000000000800003aeed4fe20e16c2302894e209f8cbf278e8b300311d0a8146ae606135745338ce84d2a03d77056ac7dd07b84b99f7cac11c1c31d4ce22fb3cb93b436d40bf96d3a2eb94b296548873b9ee29d5e597d72371c3c1e83953d5be97e2267b71b6b55a1fec4185e9fae0d6686cc7911bb9c8cb6d143f136de5acf34d84aa78d61d2285010001	\\x4d14384a51769e33acbfaa799b6d654679dc8f55b5335391a0145758a2931790922cf94fd3b6d55d34b1066ec402322a49c6b7db85ce7e0e42e388ad337f600e	1659686509000000	1660291309000000	1723363309000000	1817971309000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
275	\\xa582e40ea5fee3e911638eda58d77ddd4957bb9080ae4998a0644b5a08f331fede5c7eeafa5c197224cca0fba2fc3f79424813ebaa9eff3a948b3d56fe2944f9	1	0	\\x000000010000000000800003d60f1b714a417a99cf2ef9cca0092cecbdeb1e26f91ada2ead894a1604266ef149ac0d2ce4e4c41f7b30a738f511de167aee753a9cad747bbcbd18fe85e0cc10176453c733a8de561c32ac4f7816e374335b923464a3d4240ffb5e4073a67b93a6b36f25dc491404196adb15f47d2990953c59f5658d7dc31d23029a2aa2b69d010001	\\x86ee565fb3ffe4cefbc322c4bb77bb6754acf7fa7ad1d6cb94005428a8ceefe7536613f74bc92eaeabcaf865226132fcc54a1b2597f5ffa1615ecc5fccf07d0d	1678426009000000	1679030809000000	1742102809000000	1836710809000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
276	\\xa6d282b7b6cc07c1bf43ebdbb3ae1f2461251e6e105dca3baecef717bda2a338bb45371a5f7b7ffc0ac2aaf18f48445855c872368b820f23469ba8ee67a3a150	1	0	\\x000000010000000000800003af195433a2120a3513f3f53c78c461f38199084436baeb53156206f96ecce7bf1db4d33312a6feedd301d87e1381b8776ef7fd8f73c98fbcd7b4ed91619a397b9db41a781d2d41e8828d92f7bdd0b53bf3c7f40eb4eaef71ba90a41cb534e976944a5d2a60304496d94690148e4a06e0de49a784fc859a129fb69db95615da8f010001	\\xba181ad66cf4e14a0f7ce2c21d8e0972470ee71fb081f0410cc97b0727df51c9be564ae9e2271f708e5a3fb431cf2dec88559cca613672262758267a01285d01	1666336009000000	1666940809000000	1730012809000000	1824620809000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
277	\\xa762af6acafb2ef90e13b448e9f287a3abbcd743fd0d1443b0392735cd229b0bf7fd69f3240df67cee8bc4d5abf6aae80435d4faf22d1cdd1a426410a5a74ace	1	0	\\x000000010000000000800003bf3c2190efb21065335cad338694ca72c0971068e657aae64b390847c3aadc32da5456158aaf5f206866f880b2e3d0e354ee4447f8c10ce4a1424ea715a9d4eaf4140933893f197ab096b24a921254fdfd34010b8059a18f5f4b05afaae97f8b09559664eeba83a51a90a4858c3d72d0cf2bb860fa61b84fa9c44726fd69372d010001	\\xe05f6fe12dc84c000200606a9e91f193dd4695b7ad8614bdd4cd46502204de641379ac77386812a4f6050eb0370dd539576160c348df4752582c518bb4e0e50c	1676008009000000	1676612809000000	1739684809000000	1834292809000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
278	\\xa98653e13e1d7b69b80a696ab47fa0f25399a34d6ff06b5de453ca0f726bda8c842b88f0b655c43f87fedf888be4b88a32c2ccd4c2bbc5b6b6c137d16e4f6808	1	0	\\x000000010000000000800003bd0c9635e9c10c31dda9be5df9a86a1038ea2ffdab9c529c40347bcc3a603283cbcd0a242c110d6e388c928276b69f233ddeb328e0b8a01e32acc43607914f5c10404d91fa385d65cc0d5e09f2c13ad3bc9564780e9fbe27a0063c4a058d238df69105a8d4039f07612b4b873d2a11dd43086a5ebd0f6c93bd625dc0fc83bf49010001	\\xa56a117e85fbc1ce163a4086301e50281136ce221a15b985821db268ccb3ed5058f04c71cc68b7fa2f587e4073bcce2f1587424faae120e6120343e88d08d70c	1670567509000000	1671172309000000	1734244309000000	1828852309000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
279	\\xaf6a768a68f1ee43fc432259f1ddbdbfcbca003c5e8129fa84e97e7098a6b4619e4fabfb7e66d68f0e73e027fc7e2b936b7e1c2831464fb35aa3391f1429c570	1	0	\\x000000010000000000800003999c19d72d06fddab66fabc1328ac421c7545a16708cab089c8807637d14d895c7ad24fb906e2d67763504d12ef2d8cea4faf9e3ed21c6d836eb345457136e37abe9fda3570977c5d66a70f79902dca2ae32e0bb5a69518c3d97bdd766f0765a583688b5ca188a929bab5dee2bca83e317eff344e58502d4f6d2f22e871c8007010001	\\xd891297bff1881dae9de8e520389454c88a992a75cde89717afb55b3e5bd18599c02d36c4ed504661d8f1e3a49d676d57a73a394f891657c68206f78952cb20b	1668149509000000	1668754309000000	1731826309000000	1826434309000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
280	\\xaffe29c66231edf6fbc8f4924ee45b6ac3a51a1330c3ac1d9d2f1ae2f0c081ea0ceaeda1275ee409cd1ac36a59e66ccc7d50f57f08632a31bd75604aa4d9d8db	1	0	\\x000000010000000000800003c59c75da4d58714ec915aa23c01b426fa81ad0a03be0fcba48a7654ad7cba21d6597de269f385f4cf325982307e8fef2d789e2260c4138d436b4d8f8656d07cf6dcc1f101241ff16121e8e7f62cc70daa99e327863351946236298b69e891a8a89b02637164b51d488903d5baa378b6163626bd92a4e744f6ce0ed8a32786b19010001	\\x90d7632494e9c13523a4e3f9f18cb1d4e17569b46919e72a20ac246b7fdce8c65336bccd8fe48feb551f3b849cf2869dca2841d3c603262e28fca085a65f2809	1681448509000000	1682053309000000	1745125309000000	1839733309000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
281	\\xb59a5c41e4863adbfd922fb88218d212035704ee66109520931baae6f1ca04cf0031621ba73f86c7e7a01a67cf73eac56eaa6639e93e98df42c5b1b017c94673	1	0	\\x000000010000000000800003b1656cb29ae01d3ae6b4a535d66d58fcef20cbb72a1fe6af074bb527379c597441362fb442862455c38ac5630528b516f3d2c3baaa45b347537f4029082b94e5163022d5877b53f0cdaa2cdcae933c838006006e8cf65b992c337b2f2ea635f136850326eebdef79a650c2804dd4dadb2faa48b034d07b76e54da3ce1cc7af19010001	\\x51e10eddbc97d020484208481f5d4873fd058a9490f862cda4be80baf6931d7221e668e16296701537bd9543a4d55954804a08ef08e67e8eb1ee142ca1145b02	1669963009000000	1670567809000000	1733639809000000	1828247809000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
282	\\xb602e2ba29b7ed8093bd3a8acb4370a8e6483bf40b2381d255fbaa236d5edbec8e8497fbb8779c9acced1e328e3aa2aadcd3581b378817bde225ec62b2f0afbe	1	0	\\x000000010000000000800003a36340222e244a1d7e2446ac3bee1d317ee5a9df6f9d4c95a1cea72b5fa7621e51af7fca59ff70bb74dcb3191d0fafeed51729ed7f3c1b38325b6a3ed166ab3e2070cc977cba29564a6d99bd3b028294ea4ed7b1e5d6bac21b3d2a1cbf748124b507e1ad46c499aa5880442722c359d96247dc794578def86478399cabde3b05010001	\\x378ce19ecb88720d02b86d2885c32d19b85d5752253b7573c97cb46aa737b40e0715521ea79b0cd376dbb49cb2dfa0bd2f9ccfad5aeb5cfa5bcb3b16a038370e	1668149509000000	1668754309000000	1731826309000000	1826434309000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
283	\\xb9723a9de46130b9d158653cbed0ab0e05e77f75ced27a39e1d57b5e9a2f37cc0b50bfb786c826a893ac8cdf773241dc23efb44a4c4cb6ddfb86619d8a3930f1	1	0	\\x000000010000000000800003db3e3ac79f1a77d32deb46d0b4724b560483bf4c730f291ab0aec504243d9308c46c334c6d7d1d2c47e03b1d1622056e46c963bb9f55528474a4e3e43fbf18e6e186a3fb37ea1a6ff381b41f63090e039963c1b6600282d22477d4b5e65560806faec225bdb66c9221e034a3c220670b00c3541b984d6ff5df2ca7cb7738053b010001	\\xd51872fdfa449802647d6ea3ec343167264ae91c6e61fdcfd81392c7cdc51f2ed49919093b254b2b64a467417cb6acdb7b1eb6d60ff958b227adb273b21f0f01	1677217009000000	1677821809000000	1740893809000000	1835501809000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
284	\\xbb824b1743f9befd611b2345728c455c2bf0c834392704dac7b645f186b3be86f6ba1b2c7ee09d39afacc704eafd34edabcd6abf3c74e4ed1fa1a62c26d540f3	1	0	\\x000000010000000000800003cdf692aa569310edeed6c845068af79145aa93a0b1b214742fabbfccdda1943c14418c1878974605a2f2b0d657a88f5e762429c1536d3e77ba451929fc4cd207bb03166580029a5b3718dd9df9ce6eb62fff3fbc40c4e899f9c0e3adde126dde2a78d4f18b4e9a5dd1c2b20cf228d66ef205178ea01eb015d7bedafe62a15121010001	\\xc62d3ff79afd9d67bd78e0bab89133509ebe5e279d5a97bff4ac57eff88db741400e98e68e3d4652294013fbccd00b035a63617b0f7a82d40d7850b8406f940c	1661500009000000	1662104809000000	1725176809000000	1819784809000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
285	\\xbd86839e6f608c2c3c40e20bb4e627a77fdb04df35609a548d7220d630140d90db6406a6b01fc8953afde51b7f2c9bb76d0e4b53816ad6e75528f88f89eb6b8f	1	0	\\x000000010000000000800003c21995b5f90a984ab994450ec426f3551083019c92554b3a057cbd5434860c978b2ac737beadfcae8d47da7e47965a16d6b89843f8ea03c832eec1d0d7267572f5c49518f98aa2fd87d5cb7dd55cb6c9e2a534d522535a5969e025e91e349878a519ccd6586ed1d98e9d7025b164d792e900426f3e8c2065d0386650c0689cdd010001	\\xbcfb52252f9ba69b6fe48bb58bd834720527dc4c194fe946fe21cb841efd7e382b1597ba10f7449baa1a02bedde9242cc185b6d78c0b2c29e1580bb0376fd508	1677217009000000	1677821809000000	1740893809000000	1835501809000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
286	\\xbdf6f3a78df45c247ddb1785acade5b7d12a564d53a10b36b45d89d52a2427979b394a58abe230978a66699aa384fd042d88388dd3dac1c647224d897da9e374	1	0	\\x000000010000000000800003de7f0832ddaa596235071d15606f9462e239e107a2d4b0a027a972843a451fd0c34951c287c2393a124282a8cb1a7918bdb6ddcd6865eb12d3e3cd5542a9aa5daf12d3dab931f8c62581bd8ccf710bf1a07242fa7a722d4dfcc26bdf2ad39757867f58657c774bdb9788133a45c665764968408f8fdfb36f01010eeabcd9b5cf010001	\\x4471d6969113fc90b97ca30c1605cb07f4e420a1d441786eeb0ad8a0ac2faf82a52a8b80e5c5e4dd2a84cf1dfae81acd73e674123b1cfa20a34492eac105d50a	1677217009000000	1677821809000000	1740893809000000	1835501809000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
287	\\xbe427b73bbe9f6941ece366d658f87c0159e529dbe6bb8e292be8c69ff365b9644b854b21389fd48ded3600a1489043e5b325c31c3bce9e9d711a9404d2c0bdf	1	0	\\x000000010000000000800003abccae7a2265a15e980476ed848aab9e1fc970694ce576ee6639a280ae7250481ebeebd0e63a8da0d8fc10a703af83c700634c52d7489bd69dc6cffb410b6a290cbc09ac7621e6918c9d63be06c271bf472c04c6abcd056a9fab7a8141a2448e81c48266e4669c44083bf70e140b6cfe435849c78d69101c6f3e40b9506f29b3010001	\\x13df877e4c5ecdc0722ae2280a24d8c5b5a40c3464059883ab9e1db689bfaa7532c28edf261f7d57b3e1ca68271f4153ffaa5d23f501b11dc044c56e7d0ee705	1666336009000000	1666940809000000	1730012809000000	1824620809000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
288	\\xbfd62ea330d14e082ac740dd78b2579820fbb0c06af761b251bc438427764598bd6cb84880b6bdf11b4bd0fe72fba26704b287f70f145da9f024c54aca4f1947	1	0	\\x000000010000000000800003fb28b49d2b3355efc536da1d219341d2c812912febe702398030c10815a2a51ed89b9117a3496aa881508f7c7b1cc62d16a1f26bbcde75c48848688cd04d3ea0e606d10be1c8e3ff2c5f795350b32f7ba181a5fec540ce7e64e346b5c2c1d5a174af3e8a20b64e56a936420ccc668aaf83692fe386b46b90da2fdf488ebbff15010001	\\xab88a387915ea129b008fd5b24d33361e3bc30cc812cce457088ebfa1b7e14fb0c69775be43bf5778a2d9ff824f1b781240ce1e2436cea3a5f55b2baa945ef07	1681448509000000	1682053309000000	1745125309000000	1839733309000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
289	\\xc36a8f494ab146be79ef2b8f0d52b52321868fc7cdd1984ff569e649e7f145994ed0e2cba3c97a2b24ac680118f5562a903bcaf33daa288dfe7bd37abc8332e9	1	0	\\x000000010000000000800003a603ca8e952518965de1ca41b67e9d7ac27b89448b31063e3f25b171d9679f7d578a09d13d129f4b6c766586dd09a696a0adb0d49f2e0024e4086187509dbef596425951b562e1fb6b50d276ca06d97656b82439186acfd5d50051297d372892bac00ac134598c940121bc68b471377a8dd13fb5a3ad4b2b1520445c159d0ddb010001	\\x5c28f4227329335449725610f1d97aba911ed2c2fb228a5b9fc79aed22422f2e80e4501958171b220232216c407ad981dd5032567712f4aebdf833eb4b6bd905	1658477509000000	1659082309000000	1722154309000000	1816762309000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
290	\\xc8ce401584f7f9f8e2358230f412f1aead19dd5f2a2ec9b70339ca6970b9bc67254ad0a1e2f1cc8a8c4eeed3a14dcaafd68140089d2804a448fab4f99d6db6fc	1	0	\\x000000010000000000800003ed4789bfd707d81c11ee9a0dfdf93bb7cdfe272a1bceda8d1a55587ab97d9fdc3fc775646d88825e828a6ce267403a247deacc4690511f169ddf8b1bde59d8fd8f3d347943359c9666198159a97c02ff9426a8af93b53ed1697fc5f34bb1f6d5a91263d232e75225a38c03bd3a230353356ad88aad572d20cbee93939cbbb995010001	\\x0364b9cb065dbe4c543b19959ec51e3b5742646bc5eedb1693980aa0393dc3445efd8f20d989d934c3f84e10f94af781055e3afac6f7e61d2e57d62afb2d6b01	1672985509000000	1673590309000000	1736662309000000	1831270309000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
291	\\xc88e47e8b6ccd4c55423a9ff8d34d3c6ccc68db6c5dabd250333c3e455dd38ef60aec8a6649198af0b32d25f13c401860949190f0c35b9a08386ca942c4e168b	1	0	\\x000000010000000000800003c75583a4c68dbf61999ba7114821089717da11c92a6d7657ca8ae3ce6394d0a16f41ed191809f6696c48fefdd15192bac023d8ad7d3966e043fd91be96096e9f30f1aab20c77624be86a3d468e3a4ba2d24a5ed17f42e1f57ab9d477e007415c222f94e1de895bac8fd1bffcd3b6f63499eef8eeb7e1d5316586b8441261768f010001	\\xf0d35c07428cbb058ce4126a1531ecd086a73f67c1252f381906a76ed29916f28a7527c33e299cc8d63f9913f39cd28b812722639e7ed593d526b2dd44f81609	1660895509000000	1661500309000000	1724572309000000	1819180309000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
292	\\xcf6e15ac759f561e5a15c83593275339209a85cb18b8137bff70ab8efa39b6e5a425f20483c998cb8f5b2238a22f53c96d9546ae0e12614a12277c60042ed237	1	0	\\x000000010000000000800003eafe9c26bce6ef138b0e2ac56073b1c1bf47ac4a5b74caf99025cf61484772fa6e42ca7847c9f80b04c3fff34322df90374d9afbcecc6bdf626ab41dacf7e8f525a008b214e061f065b7676a6c773da9cbcba0827102a23ee30db07633fb5f31ed1fd0e0cab4648907e9b3d94b9b12718542d2f1368a3c14576ed6afa828ba87010001	\\xae256a9d34971af465741eedb8485e7cf46a1adb54f07583b8e8b044e6838da0dbda6a4b8db4e0d2bc28b9aba8735b290a4957ec282712b331e08e8a7349f707	1652432509000000	1653037309000000	1716109309000000	1810717309000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
293	\\xcfea7073eb646f9dc650e767e1e89d6384d2ade485c4bffbd7006cbf8e36fa86ddcdcd9f97976d734146446a9e796f66aa6efe799894af3f409da052a87933fc	1	0	\\x000000010000000000800003f5f05f662a92aec152905462fe88643d0df18192473c384ce47f7fadd97675c5eafe4db88c6b377f0565a7c24e279715bdb197618c52dac7f58f4f516cac120c69406fa9e15336b1bc33a13050ed6a350390975d21dbc516ede5f82522a8e3ab6520f550238c15c00106bc699d12fb9cb801a2f971fbc1aab760e597ddde6777010001	\\x9cded54b20ef0b9322167fd964510dcc2d517ebf80fc39c737764dec9dadaa705e9c0b2048deaaabe4ff901ef06e79ffb960ae6e52fd75978d235dc4290f5400	1663918009000000	1664522809000000	1727594809000000	1822202809000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
294	\\xd1cec36a5ffe06da5ed521715239f93e3b0cef4581974448e99d2d547081c0c02de28b45ebf161e40eac490220cfc8a42f4c2fb51ede36a8e8d0e17eabdc15f4	1	0	\\x000000010000000000800003b0bba8e28623be808b14b2285ada07e3030dc446738560fc6fdfa12d45c3afafdf9807c2386106650e2efcb204011ba2e531030bef45e99450879daa342ae590032f16d1e24e6801d98f5fd972a4f8488a8abd6b2af786918c5fa30044ece7fd9434f919d3d4510585fc13634ec04bf975113de2462f6272ac03b11fc674a0b5010001	\\xa479b1d74a6ef511ac53a39c5a0667d47adbdabb35934d8cd147fec7977d6cf5791deb6f640bb8320a2e5a813d76435a70ec150dc46ce4b266c561b893ee720a	1656059509000000	1656664309000000	1719736309000000	1814344309000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
295	\\xd26236844ba880183008145257d2f4584cf3ed610af512b52916dc141e3afb24d7c37c9e1ebcb316d7e8547c9c13376fb1e5d4a38efd394f9e7278e7db71147f	1	0	\\x000000010000000000800003be4fa967e739556d4f9f8b0b0dedafb455150cc8c197f4d5a13b6ae49cec2d348626c70603389e9b5fedb9bda85c988155babcc3aa502b077e0ac31289e247eaad879969e51b1b92457c124cf17ef459868cd546215c1600fe2cd17b90db4966215198cb4941c51dd3cc809771061a18671d1915a9cb1d0b53f5c6a198219871010001	\\x91a61ecc004ee1291e8d060d9e47f2e2ee247a836bebcb9760be4b9221a3945d13347096142464806a8133bc645a6d77b6d2d277f546b2052e66fa45f49f5a0c	1657268509000000	1657873309000000	1720945309000000	1815553309000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
296	\\xd2aa48dc86a700c4b10d979aa06af7d29f75e952f1294a326bcd113a7c6df1aba578c1d39ea12622515e1f7c9480badd00ea6fa40df5736546c9545f822fa8c3	1	0	\\x0000000100000000008000039f69bcf94e8b41d31fa2155e9c7655aed69dd9934b7ed968e14708cfabc4a72c84a8378378f41cbbad88796e0b93d7b207be30e730059efc419f6db0d2f12a29df25fda783583e43c530637fa1615d1fa20453a719431ee0a4627eb75de909b12201b6579b3be870d65065dc076f21b8a32c526ee3369325fd39c9f5b9f3762d010001	\\x1bf83737d2625e0c87b4455c34b027f5a897297ca4b55f327b8c11a50dc8e9a2616abaf136da90a18399b5f55cabcb47f1b9ed6af415db1b213424b7d6b78404	1671172009000000	1671776809000000	1734848809000000	1829456809000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
297	\\xd57e9987efd083d5571dc895a6401651841b62f238a6586d0ad1246b381abcb49d611accee83ea094c6db9cea0a6efa0c763b2a9b72632c55f1b7c8d61808bee	1	0	\\x000000010000000000800003bc275928fee2bdd978ac3fcc12f3b195d19734f3e708fae94c4192dfc10cc3c45da75353f243260fdcae8afd3e75b26243660ca921790b41a6e67514f1028b190017ec393537cfbe66b080f168ee7f810d2ff87d963091d22d23d226c103e0d2473eaa00555a676ec8fe0a9aa105df1e0bbc2767b7f25ac3ce4141ff93328e55010001	\\x7276c1c58aafcc9186c7a85fbc4573505ed48854766d43fb57bbbb3fd1f4172acbc3582afb81feb61d5715b8b332fdeb28b66d1bea3c4c81e5e88fc81c55e903	1677217009000000	1677821809000000	1740893809000000	1835501809000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
298	\\xda1e4e3eb90b51c9c397cda7da3e78697dafffeaf4036c21903d97c2abd330fbadd0246f81e529f34c5ff51fc8b2bd71b669c6f377585ff293df0ab47c444663	1	0	\\x000000010000000000800003b5cbc8bc1956e260f1512cbf1a0a8c9042429d4f7dbf807b54ac004d122b495a479adf67ffbd8d32b3a5c9352015b165db1862820b22546d708c2d1583b5a21414bfecfdf6f55bed941672436a68506c3766d7d8acae8c60dbf49482ab422eae6e953c3a5eed97e1224d1da1b3abda0475f83768957cd2918d3bb1ebe0def17f010001	\\xf233b303e85e56e47813476e7189a197b780b001a9f1df9ae1c7ff2f52917328f6152f27d6e49758ab444a22e728e52de89ddcea6ec64c08e6da6efab6d9e70a	1680844009000000	1681448809000000	1744520809000000	1839128809000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
299	\\xdb02903fdb5b3132caf66a3e2ebd1a2674ae88d7163b59ece6d4fd82fee81d7499926e1cbad1c163decb562ee13954411af7b1ed881ce8916466c91c7d697ecb	1	0	\\x000000010000000000800003df74ec7669dab9c9eb6c9f79b38d8cfedc9aaa4eaa7371751ed4931147773eddadc84d401725dfcdaa7d1a7b97bde7bc79ccdf9ea2f5ab601c4aa85073ffd9ac6ad87403e23343f834802a85495c1add9f730e03da0b1fecb4f754aca0ac815653f34d664deef1a60b928cc7c32e40390445747b8336bdb9551eb96b21c6bbff010001	\\x3f7d98255076d140b142cd72f3dc28ea291bf44aea6f4ce9b1dbfcac9d68de4731b62f2b5072150f61ef574cca30ec6248d858705d1d85ea9c134a71617ec501	1681448509000000	1682053309000000	1745125309000000	1839733309000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
300	\\xdb4e783376e85e81b7615bd9a191d7ba32b10aa0b842241d9fab520c136057f967b489029813bb71d91223c78d03344fe68a99d5396b89e4aae9ac79bcb44f9b	1	0	\\x000000010000000000800003c196173aa00f0f3f6690a4aea3d2dd6836cfebe413ce012c0181bfec06c223431f044821edd36f7b7b7af107ae8b046615fd8dbb66eac51fa33b4bd41e24c168d0d1e48900d636726b4117877515b174c4cb87b97be64e6b6a31135e5a4dcc4d654a18f2a617922f21d8d30dae4ef3428e165f1ee18ded53eb9edaa4c059c36f010001	\\x0fdaa84d93c1dc8cce7fafde35c2424017cf736e271136dfe3a9b9573204d1d5802e657200620a7acb01ad5a3e3d08724b4ad785f8680ac21135697102301909	1665731509000000	1666336309000000	1729408309000000	1824016309000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
301	\\xe09e85a3446fa061573252af5ca22e7729b26543e63e91b0abbbb7cd4dc3b9134e2677ff5344657b2006ca45b6aa4672542f3a5839382cfebff038f30649df6b	1	0	\\x000000010000000000800003ae930e7fda5dc877ace2ec1d89e2a441aee3377cab5138022d6dd231e3ee55cc6512429e7ffa6a354f6bac1e4e17661fe2a9176e171b0aabc924a5a0f08f3bb60d0878a069ac69b58a79a7ba6e62c9e5b21ee8e81bba82eac755806cf81f11a08b6386957eb51fc79161dad455777ea0ed3a61c87666d211ae75b223eff6889f010001	\\x21c31c97c96f9defe0b68fcea77f2401fd99ee020977636b010caa679ff994d988016ae2822c6b377c839e026948025ccd26276543de029414faf6e96c8cd10e	1668149509000000	1668754309000000	1731826309000000	1826434309000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
302	\\xe5a2f43be620f75a22297f5b2650fa558cebfba5e42e125b43b11a856a7f90ffe8eb2f9891744f2ef1fccd0c270f64cf400e1e6084c41d001028147551df608b	1	0	\\x000000010000000000800003bbd6423399f732f1a147189cf8484c05fcddebcf500ee73ccb92b3bba0cdc14e6f974fd29343da9f9c1bcb2c86fa5ced03d38bf4dc6cc6f9b91066a4f8eb44ea13ff40d630bf207656532eb70645c55bf6521c70d0f9943fc8fa1f4f7300a35462c35a2c96c40a5dbb7bafbf82aef215b00da12bd1859ae4417553fe97a0fb75010001	\\x6f7dae1c7861c550588f5e1840fc7cc507749eed81442bb5c1ae85ac06d418ff552349fc770467d9a56f597529ffc48f3d4772fb1ffa88ea27927844c75f3901	1679635009000000	1680239809000000	1743311809000000	1837919809000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
303	\\xe872e9152032eb5f90f41721125ce75e1f7d657a2c922d2908d1bb04128591eea695e9b1e8ff6aebe67f0700ff6138174362b27fe9d8be5ca6ddaa96a13f5634	1	0	\\x000000010000000000800003a4b8b7b5971fc32d2c146cb48f732278108ba7c9ced9735923965336862ea7007fd266ed58c23e03420e0c85f0a51739a082a8c62899f1e6f5accf76ba06d3ccda8f9c2b4ee20d1e60c2f0ad036a174f5c6bd6ef8ef2b712630df41c8c8342a34985cd6405e54a8a398f83504f63093bcde47548f8b8482e62fa103995deaee5010001	\\x9b52afd5fbdeefa1a342c6661764cca9a51183247528f166ec29c72f566b0e16749b587f6f3ca1ec2b12157e8630994b37b82f436d92de4dc315dd3fd1d1d903	1665127009000000	1665731809000000	1728803809000000	1823411809000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
304	\\xe8be25d417d54c4f739d1395651721b15a8d0f29b91e446030d6857c55027637a3455700457d998e6f6a6e73a35443965829a11e4a5f3cd804914b152b18f36b	1	0	\\x000000010000000000800003cab66f10f64fee4be40a063a1b8deb2ac445c39eeddfe4f8c8dcdd190dba06de7902dd39662a5dfdf61685b3fd6cb14683e023ed3d0c4077d8d518c7d7f92aac771c07035cc46e8969607f7082840550065dbd247dcf5114d66a3e83496f785094dcc6e96be745f6ba2f3ddecb7d4b47466f13b15fa7c536b7c48944ee287791010001	\\x0095667f32e113ecedcf6b38bbe55360d03efb1bd2422d808b69c714d3698977ffeabed7232dd7900238c3c8847452c3df0cef590bea69ba60e2b54b77e28200	1657268509000000	1657873309000000	1720945309000000	1815553309000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
305	\\xed9287e225ec6919c847b037e99a830203d413c4c4918b2098c7751f75ea72fc270fb83c42900ed18245bf548ca18683381364dd9cfbf7cf491d307b73a78e1d	1	0	\\x000000010000000000800003ae5b8cffe069928d08f67f1de3c9a0666d874f370e09a9c14fc9d5a029d96691caf301c2acdc8bb5efcacc6b1be15f7f71d2abef561cd306610bbce7f5d1ce2455935d496defab6fab8464d60947e93d8a0ce5377e2204d5c68c754c19cd9f4168e07aa30daafe9b8413b8db351d6b5d8debf38da7d3ed7349c1108dc3ee2975010001	\\xb76d93b4c4f2ab43932df56332de77388614380434882a913dee10bd482be0759c78ae70473bed4b233810ae5fd1f25f3a4b19f887cb090ae79129153e9de00b	1667545009000000	1668149809000000	1731221809000000	1825829809000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
306	\\xf4e2d02d93e506200c2b85e8aee2fb4e1ec668f3f116bafd5e20d96cda916b010ca268b735244241ddd96c26349e0915e801bd426e0405c56e3f52dc0cf5283a	1	0	\\x000000010000000000800003b16ece5f469099d80853135d3aa268d449dd4e40bce78d9b1e1373ccd1871fc0993ba1725ac3984b4c9033aacc8af788e9685930c94d32d1843dcec681c2a7555e62af045952ef9dcd9a4501d502ba986f46d369b05d56e133cf56db08cedb43ab7a8c10acdb6d665b4426836241e611f4bb541a8de3ed807bb8a79ab2e5181b010001	\\xcef575c56c55789ac26edbbe7ec3e63e8d9b439977409728d59f509c0b4fe23275668a3d4d7a90c9bcd018070cc0dd453cb196b2a593f73482f8798348bdf704	1654246009000000	1654850809000000	1717922809000000	1812530809000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
307	\\xf492dd9f0b8c4ac2eb9618c0d046c07bda9e236b43a4db03a47318f7137fb915769c809de01e41c231a7748667134f0ae12083aabdfe340ab902f77bc3de75ed	1	0	\\x000000010000000000800003f164af74727a7fd4cdd3bdf993ee83fc25b309c0add33a1e109e257c1902dbfe91a39cf5dbb9ddf6cb3f6ea187f8b86ad433504cb96c4eda47cdf1572afe48844b42993ba9085c1e2f44c6f2ea36363c7030129063215141b47376264b65e7df1d6a1d5d0e9ee8174d5633b1b7b927526e558482efd53a0451722dd53e7c6547010001	\\xa69c79638e2fd67619b948a2adc1e6b570a1c1a03c4d0617e37c04b07c81b30e37396f02b279739c3ad49bfbd81e49df48c7af658c587dbe6399ae09c388d309	1657873009000000	1658477809000000	1721549809000000	1816157809000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
308	\\xf4be0a55b8d38c902d797a5b151ca397a0f6cb07086144b4a34be35135fe8689eb46ad9b6b2a33560ba38036d39d809ff2e30bdd16765ec8fd12d43ba9d55b22	1	0	\\x000000010000000000800003cc58673ca456e186c50e692d428ac1e4a6cc433693c8ef570b9a59f24a2a2943c60d56e6c4b2566f04a9fb939ae2170439a75fb1d308819ef7b2922d5f45c59868a323b54508386522ed60bfdc6af8d7438d0f5a8e3c8437bddb6485f05cec230f2a61b1804013df948cd989153dbaad5456bc47f7b24af643aeaf2394fc935d010001	\\xd4d094b8b7447cd56907a053090f72a542ae3a87cda5079a866b41699e8bb259a6e3ec619022f95ce9a424f0f1d39d1210ce31781694c993fd7e0a60a737c10c	1681448509000000	1682053309000000	1745125309000000	1839733309000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
309	\\xf7ce210440892ddecb061df7cd0f48bf821c9bc93e1ded4d4220eab75935913d2adf60be0a75063ec53899dfc4af0c0d3b7c03f19719c3f26bcf722ebca142ea	1	0	\\x0000000100000000008000039b8a157b468c776727dce373cbb7a1a42ed2931a9e2c234cf209f519534b283399d1f747a93f535d560e4807ee28c297651d5ab32403f17badc53318abaeab12fb7ba0dd9b5f756f2a7ffb37367b9db7bb64f4a9b6d6af02bc04cc442f63b3652a93ac1791f3c63d8fb3babaaa108fd470b2921924d6aeb96ca636bc082e426d010001	\\x1e9f40b62b9b8b9a2c6a12e9d71aacc7b0a4b9e378cc87972c64a5c991cfd04613aed366382e6fd086a914e70a61f4f8ab307c72d653a4b4b727585345c41901	1651828009000000	1652432809000000	1715504809000000	1810112809000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
310	\\xfdd60b2a2416056da96135cb020c2c29228ae7fa241c82331ae76f3e7c4d7a7c7f797eeced5f48057ec3e08e499d93077423977bc8a4d0eaef9b446949422386	1	0	\\x000000010000000000800003b1659c3fc0a644d6d2d995162b0dbd7bab798091c8efb4e89caeb2782dc184b3410d70019b996d60776fea5e15801221f238e0f8e99dd516c0800a16f81581ee3b500281e9866a2334896b058cfbcf54bfc0b5bb56f7b33585ef28160ee11f1a307d7cfa0820bab8dfcb684a1823cd712bf09169b05b96d76f2fbb9e84a283c3010001	\\x2adb3702fa0ccf39ef930e0467b599cb7fd592fec57d2804d307454ef89c4ff3d2d1581ef12bc308093ce78b822f90f978e5b39248a953d6911583a97c76ea0b	1672381009000000	1672985809000000	1736057809000000	1830665809000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
311	\\xfe667faec0e29b4e34115f32c534a2e55d9b6c8adc21a91985f5a56fee2d52d6d00f199d3c02d982c8c8351accd2fb98c69dcfd5425c96dc9f39cd8527464d7d	1	0	\\x000000010000000000800003af5f523138004fc3f0674f5472a6af035188d62ea299c25a875b34be01544445f8c79bc456946a3bdca3010e0f68174e6b8e6248eae4f7881588b908167a76e911e48e82dc99e0147c40f14e99abfa0e92b42d7aaefd9492072b0d15c5a118d73cc017dc9621d85ecd579f89a860853d8aa248027f6d1bd649942a0642d33aaf010001	\\xb052969c8a36517755709e39fa1d627bdc4f37bc95bd5a8b3acb22dcfc13a3d2600493cecff0e4ef457bfbefa4c036912027ea5067f6d5d509f698bca2257003	1679030509000000	1679635309000000	1742707309000000	1837315309000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
312	\\x02dbc0581662c0785da85083deb5b8397d0ab310f3094cf11524801d88520902dc2cae1aedaea28f1063c76974af8fb9fc2bc54d9cf34dc748b51cb71b220681	1	0	\\x000000010000000000800003cc9df1551227a65348116f147bbccd22ed4db2ffc36456809fe849534a7a480a5c931570c023d45328b622c55fbd32d5d307ca43bbe6381501a95b7ce08344356eb642a98cadadeee35b08c37e2b495c347e7acf1e61a617465aef1a4f0d5fce79252a39059060b65c7559ca4782b1125f392de45970ede955c228543e97610d010001	\\xfb0322fa3aa57a02d72a781d2d7f619b5a76ce7a062120ee29ed84de865240f112a19b8364b159099e9a95c2db5940b1dc0dce8e0da44eddd8132132666cfd08	1677821509000000	1678426309000000	1741498309000000	1836106309000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
313	\\x04db5849dd89c5eb8d602079178e381110e1cc26a77eacec75c5f04c3111223a0211a3ce54ee867833899d40a368f9e051dcbc0c8053a6f075501bd0c18c22e1	1	0	\\x000000010000000000800003e0e089b6b90f2b6e862969a23c24a80c608e42fb08ca1065914ccacd66768cb217e3ce53cb6ad63db33301d08e1fc434cfd7805eea364edd9c687ea390c9f3b887d8975d48262a1178de38ad5a3886f0747304eafcb00af0df6d05dbfa1031f9c208e35cc8ed304be6e2fc1788f8f24a8d58696cf5fd5b30692524cc88b32497010001	\\xbe749808dbc4676fc628dfe4c91d13494bc1279d9a1186b2c31e464d25ec143ebc464bfb16baa8b705560df9491acbd026d91eaf33aa8b9caedded7d4b05dc06	1650619009000000	1651223809000000	1714295809000000	1808903809000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
314	\\x074b30b54fea8bd1f9c07b54bbb76a5e91dbbb6ab8c6978d5212d77c31212c4ba794213e398d5fdef434411b333a687e9cb27b38bc68982764abd83a3aa83f40	1	0	\\x000000010000000000800003c35a5208c130e70060686cd16aa97c68b88396032f6af6668a2b14a79a9e9015ec7b4ecef58ca73fa61ec1c92bc01512015820c0d603773dd268ef681a92c5ac65b327aa74d426f7a5f528f7a79c2b7f4aae05e236f980778afb4bf4f2fc21f2614200de01aace6eed004f2332b82197156a17195018d941f54e13e5303e7c25010001	\\xd6c93de3fe49995417d1cf46f8422a2f87c28d8e6d8d53a7913222f674f7ef5bcbe4a78ea68112538397b2348cefad18cbd5172f48883d5ccb813ba32f88a704	1669358509000000	1669963309000000	1733035309000000	1827643309000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
315	\\x08abbc095352d12dc76bdc26ddd174f0029c4da895ed7f3207175073820b6720a8673926d596c165625795da7420cbe3ab2eee20b82e3950b3cc6ac18a363ab5	1	0	\\x0000000100000000008000039d29cd99b09839e6e6be6ffc9ff67f05a3651531c02354d937371951e02b8e5da039d3acc6489516066672f56d5194a89da00d8770bb6faac523d5245b0550c83d030c5e25230eb30402b3a26253c6f9d3df1943550dac2a99c698819bb756c0d5467b3f923d15d33443d1523a0e626e27179f021a71dc3e4606fb0f52542475010001	\\x5a33b1c9ed2d115eca50e312af667f585798c98aae7d342e5621e5714dd00374601425f513a8b7986149b2f1f105dbf796c012402dd8ed6e07a150b5eb5e1206	1673590009000000	1674194809000000	1737266809000000	1831874809000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
316	\\x08679ca573c130e2f3c0e5b9aa13915ce5a347caec3c20237566e754e5ab6651865bfc82cecbf8f41b0228da7fde126f08c7b1ee697c37c2dce953d9436a9209	1	0	\\x000000010000000000800003b852bc3d506b9d8aa05ba20553f6a5a5f2ecf4d214df5f28a46cd5bdf609e2abadde4cf1a079cdbf84f5451f19ca694f2e849cd96a834136e8d883b0f3d1210d8ca86293792954b745bf0ea3c25e68a4e7876d6e3cd7710f5c2924e37b09e4125f267d8ae7075ae32728464d6d3678e527baccce25a611e12e7652423b1b00ff010001	\\x18e2850b934565d0e3068faed07c3199d2141423793fa7a26e46db96c814caf6bb6a0295a271fd15df9a3cfbdc29c4cc024f052acb3803d318ff4611ec51da01	1678426009000000	1679030809000000	1742102809000000	1836710809000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
317	\\x08df911621a7827bd63ac374eac95e6468a04ba4079c109c77fc8fb20eefad5df4f994ae610c26c736965b1ff07b4bbca684003b3a0d3dd999097cb0c78e7346	1	0	\\x000000010000000000800003b5a9df6ca07e26634626605cc33d4d6efffa42e84f909dfb16bb6314eddbbcc48f4d331cdcabc5f3144f32ccd31c7289d7e665a29e14ad26abdc67b33790640ef8973430efd0f5261c177de0ba502da5d6ab4ecdb5263cec6096f432b496e312fda166184eb38acfe6b5cdc78215ad01c9ab9b91a6ed633570f97c8a17f3ddeb010001	\\x59abeadec43b202f67f8bb8f69c8469eb16e1aed8643d6bc79123c513f4d43e5403faabe87c34e701cc31c9536a4363118d0a8fadc4565bfe128b73ef8455e0f	1665731509000000	1666336309000000	1729408309000000	1824016309000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
318	\\x0a07858aa173ad0ce11502996c8f308cb22a15a85c9c560b3d7037d44b0171fe19292fd70acc4f65a92e5587fb7a06df3bc8c30d3adc9c74dad863b6154aa7d2	1	0	\\x000000010000000000800003ee1347801a588507cb6a90bd0ac638628667e1ceefd77ae93536c165b30447579cfbb3edb300d81495bc16c7f440602c99df6764d71582cb9d8d5186d146c37707d8191034c11d391b1239140bb7b54d725cdec3827a35fa5909f33d972e62db42e553d69d9acc59e2e6d2e66f8290683e47421db019dd914113ff0199c6dc3d010001	\\xe719edd1422882c0f1d5ddce3c36895193cafa0364f0f66089f7314b6d2fa1ba7955318d41e7e17008d7f35908ad5f5a787ff61ce6b558221974f99fff1e550c	1657268509000000	1657873309000000	1720945309000000	1815553309000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
319	\\x0ccb712eb9799ca41e3266893d8f23c6d241300fc6cfc3892141cfe43b472a6853e6cc87d37aa0c642f002d9f5a8c14143de136b39ee94be5cb03c85263e9233	1	0	\\x000000010000000000800003a661a5e33852d10e3c1a1ae0b56cd449f0f11f40c8cb971bb2d2673c4db2f97c9e276edc15860b6491b1f32697bd62b689ab00f16de914485d3b3357229e4ccde0283a1d700a0e9548511acdb1e64fb07240275004e12562587dae7052f7095d19a9196774b65e6954c38d6114fe43658f480bd43ead4237df9eed638915288b010001	\\x2c29cd5a97c89b52eda2db227bd539f09988ed12701dc4c03d0d5492bd0fcc422aed1cedaf845cdfc1b9d9825953218f512460c5581a1e8f506ffaad3a370e0c	1680239509000000	1680844309000000	1743916309000000	1838524309000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
320	\\x0cbf0420fc000116fbecf5f86eb230ccaa782fc392487065a17061b261571eee6ceaf7726899ccd6e8163e5976603aff06733bb672b64f1eb1a7a969cc43d656	1	0	\\x000000010000000000800003cf932c9fb9b56f9e81d31c9b807960b2211b181c8384627986aece0f97e64a7a04c96e212c734f9f7c7b09ae9e9e4da448489d63f3a68311410b377a94553102232135eeb15ab146fb445e466216d9c4383054b02ded1980be2bc1d04954f7980df7a007b47392eb63d977ee23d73e7a66806e6f887fb27c9e57ed7f80b7924b010001	\\xb00ef6c8ae154034cead45c3f717a89659fd76f829bec75819a51d6d3775ccabc379cc305166b204054331b786138f7d2c13de8792e5b0bf9ebc45449273f30d	1660895509000000	1661500309000000	1724572309000000	1819180309000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
321	\\x1263cc981801aab11ec33a3d8b2fbf82568e2740cc0859a5f2d14b41c162e415df9a0b446ebd4ff016e943454b1d9a9f617b8a9d1536a62962368b6e73dee580	1	0	\\x000000010000000000800003a6ac1021af8d8f07e58a64e974afb91dc104e69c50e4a4e22a47d14332625f84feab99c356f20367ed3903e808b9670adcbf9ed0c81f8c1a278ca1116e7e729a3896be61fc358b254ef2957c1a0b879cbcd0d816608e5f2c617a14264190297280c0ca6cc33d3644889c5568e02b7d68a2dfb30873a707c5cfbe609048fa00df010001	\\xfcd4a2f7b9a22d4edffad6378c16793dbe7c10507ee414095a046bf574eda4f853e50231a63773e4d2ad92c0637814c03772b895e99b85bcacb678dec64d3e03	1659686509000000	1660291309000000	1723363309000000	1817971309000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
322	\\x14476d88baa29a56f4f839b33d572924b55a5e507c046946648e9499d541174b12c7ada27fe678e9345b1d8659c392b90376a577bd283bbff0b5617c27bdfad8	1	0	\\x000000010000000000800003d77368398a2936e4ba7b4e6b43f0fa9d03fd78986652ba1cb88f1222901c7326a359662469efb8a4b66e2b6ad27d140fc99b9b60ac09be22b17797c5a6d49625a2159adadc026c577bfb5d7e19f568fa8ccc6734d3627b54ff3232cec2d1d7823f18d77cae50c2364c48f9d22b101ea7dcc386b44b7dc11c4a42e176eb3d1231010001	\\x5391daeb51b2bb1c07bef8fc13d3ae21551a68e582e48703501c72078a632fd8abebadb45c1c99ab5a42f8979940fee22378fdbf93e512e747ada912a5bad507	1676612509000000	1677217309000000	1740289309000000	1834897309000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
323	\\x15e7fc534808b3cdf39773312c2e393fa97b91dcfef61450fb9bf76aef7a93d757973e72c7a278f8098a45ebb940af3c9f2de5c9dfea7f3a99d5d8ced36f48a4	1	0	\\x000000010000000000800003aa3c359c5f1f947d65c2e7cbf6c4c2dca1333a0e0a5af3709c0db71743319855bcce177d70bcf3225b7b3c2b58cad98185a49ee12ece968eddc9e26e89ea8b9a88e296ded1c71ebe568506eb2bd36bd34316556b36266966111e37c4090e5142af97d32d681ba20f081f9f788860ff3dfcfbd89161158fcf8d27c766a8072145010001	\\x7e8c951483213a7aaede3f3c1621ea341f21504e50d2d42643db70152181618da80eba71e03ae9406b73bdadf731cecda232f2e34bfcba3c03406846659b040f	1672985509000000	1673590309000000	1736662309000000	1831270309000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
324	\\x169b1ff3f56a6eacc40e60ede512bc706fd0f829d9d07e39f9d13c36a89cf1f58021a2b4a55980c53785212d78714cf09a49455c94ee386949a7eca1ea74833c	1	0	\\x000000010000000000800003bbf6fcd49c7f61fbabb42f792269ffe459534e4ba565dd47e00324f90a9a8d910ff1f93c2e32e83868cf4c782dfbe72b0704f90e28f14ad07000700966012351cd3c4b5e943b3e8826ae034c1e6bdfe1fa56f168d7e7d5bbdea65b71b68afa939ee801fccb7635aa88aa46533b132c327daec864c6cb505d3c2112b633d842bd010001	\\x6581831d30e5c923c0bec48fd309eb5332d5e6a933c92d21b42b87de9a7f5c723d153fb10fa4af9b2a67cd4f0c69a92fae8b7a56a3d3f49e5b6209d8d27dae02	1660291009000000	1660895809000000	1723967809000000	1818575809000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
325	\\x1bc79c0dc22b652d6edd48172975fa527182904da4e70ab1a93561ba3cc72e8f3f4c860f1b91dc5409e964ad423cefba35439fb1c753612d2af1cb9d5bb8a543	1	0	\\x000000010000000000800003bdfd49e72e13f069ce584e68fcaec1c41e1d0cfae6420605c3c5e16b87eb5518b914076f194271d04f62fb2278b369342bcf2983adaa5ba7c3bc0e9829c6185daed684cd440222085b289d0c788f3ac57bb0e73b8de4f14a3c4f8903e3c5937e846a721165010f69ca274c270134dec41512b29055b23f6bf4ef0fdd6ce28bed010001	\\xa52b06a0b484a50df8e1794fda7c0ffcfaec0cac146c8aaf9f401a7cf914355a10ef7920525e78eccf384ad96135bb1487b23b77db4481bd399ad16e8ade7208	1672985509000000	1673590309000000	1736662309000000	1831270309000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
326	\\x283ff63a6c903e0d65e376fb753ac3cf9cf1177ad706aa8b3ded86ab2e809c9d624ea1c214fef87d9bb56d13ca95c825668f94798f33e66ea27cc3770ab442c7	1	0	\\x000000010000000000800003c3582fdcc7c82e82b869c6b36adfc552091a06e59bf172583db511034ce172bd28c85bdb3e5c5d74b5a0a85f6667cd3632103d3bff0fd522134571d016a79ca74843ff9cd5ec0ffd7a5f919f5e7e857fec3826ac4b8ad6822c800c1a55a8dac527dff9601892a5b46c3f629edf76b3145ddc784e8d81720d951770ec7649d775010001	\\x9ac021d1c5b5c4cdf1a4c1b0cbe1f1355991b13cef1dffd978ec7c5ae140a8454704b9ca2ff13dfe64d5c67450708ce50d4bb44ee2da73369c2a7066e4aa080f	1656059509000000	1656664309000000	1719736309000000	1814344309000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
327	\\x29f30fb419424981dc30cc52ab2c58bb1b5e63059ae201bce73276b8a868f58362beb89f7f3fd3f87f5aa027156e7a388ae80cb0c98031b927c913460fbd525d	1	0	\\x000000010000000000800003d06cfd5d8c58064315c99a2f60b7ce4bed47d5fcbbd7ada3cc30538e87e5a3defe2dd4bc296825071105d1f14461dd093bf81ba146e6b35bb6ddf57a9163e9c7c03b2de1be6bd459315699ffde9e6a35d20cd62963c73b63fb68b8b2aa0efe2ac22cfe9176c450706a8185f08164addd8f39985a2f2be0a7fa99685d901bbc55010001	\\x0bb7688fd68aaa6067ecbfee148df61bdc90595d3c556503b36b17fe8521e178a8b25ecb27ed4422dd52bad31b4cb50cab203d86482d198b9ad58139f54ec600	1672381009000000	1672985809000000	1736057809000000	1830665809000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
328	\\x2dc391a71a404fc81614cbac79dede45dc6e8c545cd4eb7240b99fb8afa9f34637639f1d844a6b47dd0634aa139b203b72a4bbf9a52f78a40b7dabe441409b45	1	0	\\x000000010000000000800003e6cc868b2d57af9d3904f828d5e1a990e465fb236245ce2adb0a75912da904aecf38d637b737bde1bc174b02b13db89ac0d01fd5e691bdd86d333f7de372db87814edcc316cc55d76aa27bd465e4769cf0fa0ee92aace04c0e54271a089fc4a25639921ebd689ce8c06a4281dd6008f93f03ad03fb314b5784fc0b17001517c9010001	\\xde485a141b3cd0db5d99a0cfd695f7d14488d878c4f7ab34d2d409a399486c8e71266f4caba7cd8d853ae7a1556fd79ff8c9ceb91708a40b7e2afd4c0927bb00	1651223509000000	1651828309000000	1714900309000000	1809508309000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
329	\\x2ef335abe335da60264d367262ee9cabde5393f36397f5330894037cf49019afa541d7b04252deef331a60330fe4a767f3d8892ad910be3bf5dec5688d91a6c9	1	0	\\x000000010000000000800003bbd7675db5b4fd7148aa632467ff8701fe4c7fae844241ff7e706790590ede3a92aaba1e64a5b10265b28b13b0550c24e7838478525e6d2a77a2f1b8344d5a16f327ef9fc975baac27c8a6d7d89a649977bb4e332cdd60a07ed5931c08f106f312209e099e59adb964850ecf262c37ea1d1c0aacfbb6699a69f2d29fbfd0b9e9010001	\\xa437f42a1e39a60e7aa7d614b7d971311e71c0d895cacc3be74145244badb298b8f1db1308bd4df9e2c5bbd89026dc7c4b32c9b198d600cb7645e9d22d73cc0d	1668754009000000	1669358809000000	1732430809000000	1827038809000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
330	\\x2fcf91934d0f72afa6ba3c80ca46fb259a2e0e04d0084e5850ac5e06266cc085f6268eca24e3d83e339aa95bb273be27b355a4eed2816ddef1a1b5836a562bbe	1	0	\\x000000010000000000800003aeb042bf21973a1dcb2641772955c90845cc57f8666e68df229da1954f2450acb51ad53721e9bc1293d1a2805bdfef2af616f6955e6fd3fe8604151f8147bdccbc13bbc457ba82599282c960307540b8585fd5b4473c8af32bec9c6e2fb59bf4bbdd5217685020c5cca50db453a05fe92b7a6f7f295e5657c9bec290db0f3dcb010001	\\xa8fa596c8e067089d136e50a6bc741bd1b7435d48fe5925d89abd0936b15340ca525aaf9c4572617aee1549fce7038e12df926333e3ece9eb68d8d8b16cca700	1675403509000000	1676008309000000	1739080309000000	1833688309000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
331	\\x2fe776b9c4c0bbff38f3ba491b0885fb2244c1f988d329cb8cdb34903e11a6afa147590a7cdffa5c0833d0edd6a6cf491af46637b9f644139262654fe1d372a0	1	0	\\x000000010000000000800003ed002c4f9c22bfbd4a23ab78e8e71e978bc1437c971da28aa1d075b0fcc478b16b715c0192384190a73374a00d82cf9f363c2470da5eafffc2f097ef1000a9e8907ef95759e12563c3507654316b75b89a1415a4a5c43f0a858ba7d9fb71b4e8a2b4b3c7ce4867f9bd35577d7f5604c07f1f7009532147e5485a965706eed9f3010001	\\x9e889f003b90770181d50be35951872aa1205b9a17f788bf04255dee545510d938053dba552b7d02ffaeb1f61580344204abc97e8f3a7e13b94aaf28fec16e05	1670567509000000	1671172309000000	1734244309000000	1828852309000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
332	\\x2fc3df2ba1f16c4e5affba53c0916a565daf95da68f719cfc2eda668349ef6e4372ebaafb9cca2ad955b228e86e969a65b5b06649a6314dd8c2fdb42dd79bfed	1	0	\\x000000010000000000800003b29ecde1b7a20a876fb40dcb8fa2fe271f24288fcda0f8198a2fd581869a0ab80379402366e028ddba90211051681d721039ebc94b97a40321fb8ae0586f3eccc294543488297370ce1a91d5ceab5b65faf6e22b373d10f9a29eb20711f96a3a27829ae461d1b367119b1e09b9a57266aeb9023361bb96b171201983c0771d97010001	\\xfb7bffcac78fc52f0c995af82069334935a2dd667c3f34237f28748137d40bc9048fb41920604bb9303ef6c7e283df34b3e690cb77ca47405903b799033df903	1668754009000000	1669358809000000	1732430809000000	1827038809000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
333	\\x37938cd9109ebc056b666bbaca40fdc66ba94f54148c8eed6dfe08f5208766b3e4b89ca8ef366a6fd658c5a7c7bc3224dd16e1fe8b9f14987da7d5fb88bc2f9e	1	0	\\x000000010000000000800003b75f9f95649b476dd9357aa729c2c2a668cf1e10ef00fee8ea621c3509ddea623c27a34c4d4bb69baf013f4736d47e1670503b56e92cb1463a28601f83c6d2d81bd575d4445272a017c23d6020119bcbc062771fc89d94a435bbc44ebf0d83e7fc0b67e2029892c63494cf33ef06db541d02c75e75793626ca73a42d8bba74f3010001	\\xebf8251877df5c4518800d02d831e1b44a91ed93b785db50099dca0177c2f6ab086ed3d2a7f5e940e85eece4b47a88c5d5f121691c5dbaa8fd9bb7777cacf101	1678426009000000	1679030809000000	1742102809000000	1836710809000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
334	\\x38c317740b9d11f0e1c6056fd69cf93faeaca109701477eff6c377088fe7333d20c068ba0e03516260ea3ed8b817dac05c21254c323379d700fe43dcc05bee2c	1	0	\\x000000010000000000800003ab364c82d5acfae993f2bfcb5e4289516ab6506b0ccb2b116739c349a4e4e770fe367a0f54bcd345708abb088b3ddb5c8f0b4d4b0e421c16ea9368db37127d331833436499fd5a0cbeb0e766352d21811a6af8426cfa528c21d832cc25bb64e726a93d1b8d624e134f39840ad3cdd419deaa8c8ed1cec07d5772617db087c81b010001	\\x359bccb240f370304a2fedd1e041435acda2f2a89fb74920f9063e754ce694ab877d3badcdae31649f8870900ca4f54149d3f1b0a768f7eada68753d0595c009	1653641509000000	1654246309000000	1717318309000000	1811926309000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
335	\\x3d6b920b25ba0ff6c824ee2c1acbfc05d29908ba73bca6ec11074a1e438f9b60438a6ece57b6b7ceef2dc46b94445287d47ce936958035425697b8bdc26f0a21	1	0	\\x000000010000000000800003b0678a6b86330f44d7beeef5930d073f3c47794c9e8a8af89e1fc5ac4380cb7e14d2f19b51f740596aa4267dce44742f928873b708d65d2d7e009fa598805382231ac6c8f697f0ce3a9f79b7b44701b950cb406ff9843d167759fe82ac0cff34627a1fcada283b9e95ff4b94cf8dc71973ae76ba1d14c3cd35efdb1c41fbaccd010001	\\x6fee031b7e47905933c077d6d3746a3eb4dd40e24f7bac1a8e5936a9c7c0f910afe5130185a8d33336c4e3e704a850f8035db69667b0cf62e1f46ae2bf511701	1651828009000000	1652432809000000	1715504809000000	1810112809000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
336	\\x3e470b19a525a2f54222d9246b38d2de66f24ec4a6abe2a4a41ef734169bec86307d334e025e25df7ebfecb4f82b75b56999d5723e5fec4c480185966eb2199e	1	0	\\x000000010000000000800003d3e9a96dc5ac236591abf204b50f5ddf0a111962ea3552908b178f03e7caca6ac46d318334e86aa603147bbbb34fb0f39e6802def8f4ac3bb77771090ca4db55cb5f1726b5b9ccdee3195487deab330987e67d76718bb1b4fe428058ddc61d1b495823301fda383d21556df2d8c620c282e974b337dfe3c51261f1f2b0ddbcd1010001	\\x94494694ae8477a398e895441c0d9d6f83fc2c63a0ff3357cce3ec636ad6e73f6210012f21767030ce9e7bda2943d677d0ea8db5a16489529366d80efa0b0b0b	1651828009000000	1652432809000000	1715504809000000	1810112809000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
337	\\x4103bb66ba6a405ffdaba5cbec320eb443a5a8237ab3fa378634d99c8df0c348a8c366d1c904a03d8e7dd6a55d209125851f06e0ad932ff09ed9623cd27f0459	1	0	\\x000000010000000000800003b13d2231aec51a312b919b3e69e2ede804c3dce3f9783f15fb0da2eddb473d988dede956c6afc1caac7cf4f1f15be2d8d8503394b554c526371be297f0a831aa84b2d9897351dcd67d9cc8ad99d22d6a5660c81bc3b2db78d9bc09c3db4c64fbb2813d585e1e268436053f9c49ec9b18837e7de171e5dcb8c84ecf32aef78bb1010001	\\xb9882f01261f0dcc3daa2371da8072392b978f254b5316ad37f0210df81a116f11171f6e17b767d16f21e1ce20400db62274fb6b466791bff9f71eacc6bcb201	1679635009000000	1680239809000000	1743311809000000	1837919809000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
338	\\x448b4075dd75d6935c87e1dabc2e491fbb1143ef4f6aa4b653e9f3a5b9dd2920ad312b7b280d336fee2accc72c862653ce5e15dcff22938da28823e65e9dcdaf	1	0	\\x000000010000000000800003c7819870ad7b294c5e3f70055cfc8921789fa581507c14d2bd8d461acc69671721ac4f41e008f80a5a2809995a47c0fe7c16124321a5bc717d332fc4337f1587562e1f04af942d07a5f09f3a042abbc6cc7c3917a9b2d50a215fe7011d5dee736dbd23500a652c98c8b85e8122b8b4f4608efba3bcba52b906a5aefdea89b0dd010001	\\x8fd31278502d4f5a87857c7dacaa85ef5c7a0329731db3d7c2937b8eff585ddb2ac1cd47da758c2351b87e3212271345c2103ad392157265c223e0bded617705	1655455009000000	1656059809000000	1719131809000000	1813739809000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
339	\\x44638d217506c1d9237413b1cf887c8b7ba968a6593150f79a543507c32e580be8ac2cbed5e3cbfc245f7980ebb86a6131847d9bc8506faacda42d509b008b4c	1	0	\\x000000010000000000800003c98264b0b04d0fccde7d571797a56c786600376d492aa209cd494204f7ff21c808735972a0fadad7c1e10d58915fa34e066c180031a3e3ec917a59659c24e31b0693449610572bd7670b3599c75d2d53d2aae82d9af04d9af0841f497b05186cd70a0a873802484fd0e6b87c5a72d3cee75e6f7fc09a782c9fe16c9dd6c98769010001	\\x1ae19a2dc036411d678db09f450de59ed414123d27e86136ca5fcffd4b4aa9c7f34cebf72bb4bea8205e0821876098246f914954977707bbdec96a603a539d05	1668149509000000	1668754309000000	1731826309000000	1826434309000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
340	\\x455329f81b5d77ff4782ee221225a41183feed1a7ad84f8ac885b9c0c2d4f582a7bcc66b806b59ee08b603905a7b22a3370ce838525399c062d240ca630edf6b	1	0	\\x000000010000000000800003fd9c094a822b7f1ae7c95024dc4013e05efc758605fd3053067b8fde3455072772818a02c63c4d6e66824bbdbf5bd6ca9919f71b1f4bd4a852f7196e3eb0dc12d349f383c24f14daeea60821abaaf8998a594148ef504de3b47809978d7c1455fc9d626c578efdf59deb6054adab4bf32bb295dddb0bcabb8ddfe03445e1400b010001	\\xa452687af5c795cedb6ee36c813cf78a54ebf91d9fc243c060edc63ff3a1a7635670365dfd67bf44ac92b9256e4cfed6998ad022d1b90402db4cdcb11d06690a	1667545009000000	1668149809000000	1731221809000000	1825829809000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
341	\\x45dbba047d65ce8036363195f1c7f3f67c8d95cb2c0973d7a79da8e470a941203396aa2f1acc2cd5acc8339d588655ff5347f29cbae0ab65185baa0f4d646ee3	1	0	\\x000000010000000000800003c29d89853b50497a75653a0e834ccd28b8db7b75dc7cba2df51c16b97c28cbaa4dffc955e28524494f893cba9cd242f889d5ce6a905c229244aea414625b492a3aae16d1934d0493eaa54034cebe024c8f5d78c9e0fa46fe75bc5e6d0549a5a2b821f7c668a52fbb7af1e033b997065748dd82351dd1b11725bd2301141a451f010001	\\x15fa2aba7c0076ddd309cf4c151d4166b263d3464ee84745495f07e149e913a1b5242dd0fd6ac9834e7c749004a96f7d2cd69010bd075ec9b04fc2f9c0f38f00	1663313509000000	1663918309000000	1726990309000000	1821598309000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
342	\\x4517c65120348b696556fb50a25559ff79fde6557a9d989d86ff89ffc8071ae2217704f6181c02b802b37378b4c6c69be34eb824b4652280c8a99b10b58e8a60	1	0	\\x0000000100000000008000039b0d9b33de088e2778c59dce332f61cc7be93d0d2b67962cd105f0458cf17ccb2a148ba1489f379878a70e91d592906fffd9952c4cecd532c23e4083f98d748217a47b93ddbc0eb11f50c0d630ec54e48240b2270d5d2f47e46efe153c399846026d2b5a0a899d9ea10767bbe9f93ad8b6e090a27b36438a61b835d926161c1f010001	\\x6c8fbdcd6e676c2bdf04a3c3f48e896de2b10dac7504fcf573fa27187ff19baae68c0bf55d592d65097c7dad26001e92033993ec148a99da90debf23111b3302	1654246009000000	1654850809000000	1717922809000000	1812530809000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
343	\\x471f456ed6b77f78fb83446b1c41af33b82a8c0e002ab3116b4dd202cdece700cd8008b295e57f5d2230d8d5b58d139f9dbbf1abe2130478a2986231c2d2e147	1	0	\\x000000010000000000800003b69397b07de5881a7024d9dcec2957ebf31ac681effe96eda5f50f0f551218236b19f34d18e4be1a2f0c3e97ee486d81202a565fb9632724123c6edd06226dd95f20d0fb0d0aff7303aa1a6588197ca67d036cac151e489747fe5652b962bbd9fa96c1efd08270d8862a6d1373a11cf56d275ec5cd148807b93b4f2eab2dc61f010001	\\x4b5a78456b920a0207cbbd948c710aa364541636327d77fcbf75e02b21363c76d82cc6d3836a63b82592401f8a08f6031b90cdc9af68458e35669e0466f7100e	1670567509000000	1671172309000000	1734244309000000	1828852309000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
344	\\x48f3e8f22ccfd248999c8e9e510ea0034313838b8a09fed555cb5f4c411a9db8b4213a1b8a2eb9f88fc45684baeceee3149fd411b80e84003d0b8b014618a990	1	0	\\x000000010000000000800003c9d21e48482f7f72b297200a2b5d27bd531e1bbcf8aec3bee659578d2bb9e4efeed550ee13cd0db1961e8e508343926a7d6eb2d6c660ee1894b7dc210b6d21fbacd18b4c9d20c786b5888d36a1a62842dbcc9435e9af397f2881f31d528458961294ff4f38dcedb624c3324a2d1ec6ef76de1c46d210e0e2eed07d81af707b27010001	\\x7c5ab02cc626bbdc38cf5f68bc55b375de2997b36f98e07e16c29acbf8ac490ca7c904b6e01a5c28fe7c63a5f38127093ed8d2a035ef3f1f753802dde8abe006	1671172009000000	1671776809000000	1734848809000000	1829456809000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
345	\\x4913c027f9c9955c98f53341f0f5bfeb25dfec5060bd9f4edfe0cbe4bff9ab04e3ca4d1e21097560370e0e8b2a68cff7c8f216da3374518fbaf83a902b604dd4	1	0	\\x000000010000000000800003eadf3a49a96c6b4ea1d3442ec6892deee0c46f234c32e8c0f82a26ba9e8d9eae907eb376ed4b986a5cf97140a6c5a2da0f61de6cab2f98cc50fef1be7f9efda9c83e5214768b61a8ed908efc900f94f7023a2592280461d198d167d9492c93cf9c04b687a1889451da551f5eea81decddd91c4635a8ce0d476395030c5d85651010001	\\x779f2c7a549c73ca74bb999747d3ca642a07d2e38809b4e497949e815faeaf0b16ffc3c61a54ddc655ee56c4426f3a412468935c35ce8345528015ba6abfc809	1665127009000000	1665731809000000	1728803809000000	1823411809000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
346	\\x4ca3c7749b731b8748ae33adbe7c34cec43b9cfad12a0eb32e3395176308cfb5b936e9a55fc487100cf62f46a9684aad0f8302a8f435481455fab2f0e7d8288a	1	0	\\x000000010000000000800003b4020670a4f682bbaea7fc3e29e5e37c9785390372889f628fadb987d58eeb64b0fce86cd773b6f9720902c3e406425bdec835f3a881eb5db6e7d688fed97658772a67697ec62cc1e7805a9decff00dc1d063c8b9ab91c5518c4d85d48c6f48e2b7d36c77b9f6adfc93da0ffbc584c2e406fa4bb756ff779a3e80085803661cf010001	\\xfa6f4a21b3bd0238a77e06bbbffe8cfb7907ea32949e41dc3922a3099b9685dc4d3fb249afbe57120288b64203d13f395cfa599d2b6487724d5e70cb97c5d700	1668149509000000	1668754309000000	1731826309000000	1826434309000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
347	\\x4d03bdfdaeb35c203e7a9a1ba53ef8f370dcf3f3ae4428d06438be90d2036dec8e90af83d244ffc25a98865f8158ef9107dbbc4f7b734fe2b82599a115b4b12b	1	0	\\x000000010000000000800003b6956462a5f3d62e7a81a121e8f7ce0d20317882cc231de60584666ac1ed35031cab322c5add1b305df75828020cf6a2e2f5ade8c61b561aadbf771dc4fb9116120b5320883f8455834c62e607e2c78d48575cd0752cc38debecfa5685fca704b7b0292bd5b7bda8cae16e2f1a44b86e4a0361608a0f665703fb983e369af93b010001	\\x53d959257bb678177896f6ab06922e9ee65262fccf8a27ae97d9ba32edf96979a14b0b517f7388359b54594e16583db36726034ffef08e3634ab51811efea709	1671776509000000	1672381309000000	1735453309000000	1830061309000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
348	\\x4e13940e920f54d5637540959ddbdf8301b8818070a59b0925d065501f237c07831197bfeac89755f98632f7148a1dd822628b8d4edab8ce2d6bea430e01fa22	1	0	\\x000000010000000000800003c4c677f53220868ff4dff23024978f23b71c5bfc50397548a5e6f9d3f34320479031529d5abdfa77e1a8144e9be6f640fc428408dda2a9865722882fac1f9517db2f5de46af8c0223790b01f31ea62fed16ae4d29990892547bb4de5c65a1acc357025890c552512325014ab4d5c4596b5cc507bcc8ebeec29601c6b037af861010001	\\x67c958ce0af87123b326ad1d4e0ea89a6043cce4ee6daa7ff8dc61aef669d3bc45839c1209c3fc15e70c5646abe4aab5239b64c6eab8380a465e0a4edbd0df0b	1656059509000000	1656664309000000	1719736309000000	1814344309000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
349	\\x508b28cf92a5d71ac04c98d4b2f806fa7791a6141d6d4d9f15b44f3685d4e3d623e2f824b3f1e7f28301d0073c2448634046cad6101529baaa00eb8d2ffa6f61	1	0	\\x000000010000000000800003d5cef93e15270740e9b714c7ca7749c075144dd258e5073d808bb569367e088f482085efa965627cf7d6b75719fee9eff48d70cc00391bb5ff9c7cc73f4b59f26e1ee490a229fd625e5d6e9a57af11314ba1e25087a8e7997450418038e934ccd5ca79e646dc2cb71dd93121f8e17b3b8ce114d01d099acddc2255e05806faab010001	\\xc727f4a10f28ee64c366bd6de0411a0c00e7c272a7905fcddd24764728412a1d9d1398237efdb30813c07a746e504d1b5f42bea06140e3f8314cf33239bdbd0a	1665127009000000	1665731809000000	1728803809000000	1823411809000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
350	\\x516320bce9df02abe1781217cc8e1787acfb8468915736cafd1bcb450fa154769ef363ad3a756379fb8d321927c2b0e37916aad311dfffedbfa3c10edbae0e62	1	0	\\x000000010000000000800003cf72ad6895b60a13d28c87d4bf4716c697d5e8e0ad7a8a9b04ff1db94f726dcad004f0e0c5de2a01567bfc37f202edb09dd292ea94628701eaad2465e10b8a9b0289342d21cd4183242a2dcc5be0362a26944e96fd6833f9ff83516d98ff4c82d28ae365de55d96ea476c05b783135a67cbe8ac519ddb7af22cda5c62d6ca537010001	\\x7771444eacef6c59932206f81234e46998657451c940f33052ef140a0148f082815eb1657448e0cc3fe71c4fc0e4eca7dc3b247be3f0a58ba65d32a9710a0e00	1659686509000000	1660291309000000	1723363309000000	1817971309000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
351	\\x54e79ef1dfc9e64450d1802626a2318c562e24599033e2a5772c5450afda2d0f10d70d9f0b5ea0b7fcf9b0fec5b76b3910c4ca5e22deb9f114185fe95c3367ff	1	0	\\x000000010000000000800003cad6efb7c7a9519f830f011ce880a8c8aace8d03f3f558fc3b97a71b3e733634214b1c803de2e42f045cf02fa25bdf1c6d89e9763d58599f976e80db3bd93f1356e80202174737dea3532d19bd250e9e77e64951d31329841f4466f780b9ceca0246396f69b0a28ee5c9b11fd6a34f06b117f6ac5a7181a4bd54a782764ff67f010001	\\x5759464aabee2332a9cee04e46a5cb0bfb0c8d196f10828ece0cfc8bb214ff365a7aacc7184337c9fb7a6ff7c1f978ef94204c6aebd20f5079838d419683500b	1676008009000000	1676612809000000	1739684809000000	1834292809000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
352	\\x57c712d591aa7b2292a40c5793764886ed27f78dff3429c0cf02068303f6eadb23b414fa36ced35653c33cfc89fb351d44f02d14713c4b686e14d1e711d5f647	1	0	\\x000000010000000000800003cd155d321e09fa7fe6150f84374e92a180972d8424f192c8c25c759823ea1fad02fb9834af5cc719c43e6327a45349d7ddb53ca146f60ba16fed117e3ac34b947858bb1ffb3ba1379b1e9f16fe71d7694e86190cbef198329544186d46bc0d56a014695ee8d52b899a524c130ff83a182b907076578f1e243d2e1127ccfbe0cf010001	\\x6e378c3fb229d01718b244dd53eed10c11b398c10e69e9c556c2d6beb1976c4649fb537c148097e4305fba379430105f86afed2d6548653235f56ef540707002	1666336009000000	1666940809000000	1730012809000000	1824620809000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
353	\\x5b578eeeb95a544f889a1e187359f474e3c5d9a3d7a7defc5e3e77f1b9c4c23d0e9aa9c4beb39bb06f6fb468427d9721097320ad2811cbb87721bbe1dccc5b04	1	0	\\x000000010000000000800003d5f47ad540ee79c5ddd056c56c6665952f38b4e48bb3db7c7095638406fe8b72926865da7bef2cbd153e5da6bfd22d6d934d8f0cea8b3b14ccc8a9cfef598f8dc3fb0e1c87ea78e3bcec0a48ef23f7459a0ce61e7e715a813eee7d0ff2d7e736d29a413a464fd8278a616390677fade4464953bbec07cbed98206ce9a8235549010001	\\x9c4c1bdc40587fc23a090b6c506dd59903bdfd7ca5b796b3a25b6c73cdc682272d571df711ec850d3a0d1044f800d4d7787d3582a088cd1d9395af4ae8b7b209	1652432509000000	1653037309000000	1716109309000000	1810717309000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
354	\\x5c6f02cc2ec98d05920b1599d65efc64a328b5fc8910f50379bee9ed5f05236301569fe87555e39e53e8f1f0385bd64e77f6e1cc176d84a9f0327d82ca44f06a	1	0	\\x000000010000000000800003c4fda5ae4dbb823ed78d38ce32f4e74dddc59f6e06c6a4e58a8ce5d1e8305ed3b250c997b796af486dd9e280b601f61dd2c60a07f854f76575d78fa1775e86c55148919c7e0b6c47bfad0f2565d958c91e3dea13d0e5d5ac4c60dfd6ce81d885beee93af8bf0464a513710711f19a621d692ebf48dd2363af16c76b320e086dd010001	\\x28439df992f9f8e98d3ea183e01416c822e1e20956a02335e5ab6b5b441aff45f333d4f3badce3db4d45297fc111ed86c30609ccb583b383417c4881ba564d07	1680844009000000	1681448809000000	1744520809000000	1839128809000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
355	\\x5fab454cb37a347dcbbe72fed868e50eb6d3e2932898785a1978118ca7236d50f896e951e60389f36e333dc82b22a066d5e0a8e2ddc6b43f7b128b6800958e81	1	0	\\x000000010000000000800003afc74d09b3bbaebdcc22461b2e78f62c681541f3fa0b2d31af75d04a164d20955b5eb22f5f57094a1e8d739965260e5fe4d0b79d7811aba0a70526e3c0df7cfbe50509def5d45186d261ce2cecf86d99d855a73e964ab3a65215af65a20d7142cf769c11b8507264e733c3df058e4922562626671ccf653232176b5876f79b05010001	\\xe61e68b8133f35c481f9069867066d87117076c7a6279ae68a27739f62ea7de0f78b26be7dbc8e05173b9e1a8b9f2fb872c0c8942d814127fb30f6ff628f1902	1660895509000000	1661500309000000	1724572309000000	1819180309000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
356	\\x63c7fc724bb8b2b21349b7d96f789bbe37b67d3272dec81ebc3813728a5648d066f28ad25d716f44ffa95c91457aef795256a712fcb19407fda69d8c97352d0c	1	0	\\x000000010000000000800003bb27bd85e383741a4aca0b8f5679e16504172f429c1cfcdc6c05825b73bd891143ba586147897886c2345661f1d614c637abf0761dab5991db409e649ee46cbfbd4857d90c72da8248b52716e63be5791e6cd5deb8a44da5b9f1c95160006a996e7fbf910998d6c42abfb2761bada94c89caed1baccfb6dddf97f3b1f4104ef1010001	\\xf5eecc74f06fb690555cb327a4bbe8eabcce6b40e74a408a11ab437f3e4c8bfca8f780a9b2280845bca7c888eca0d2ce66855ef14a105c3d5c3faa6024b62008	1658477509000000	1659082309000000	1722154309000000	1816762309000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
357	\\x646f3d799e7ec10524e088908adfa75fadd8b854b587693b347ecf1d42180b2228c3dc2193f14b753f7e08a4aaf2b28d21f57b0f9d15221fade942573172ab85	1	0	\\x000000010000000000800003b6c011fdbe6f9edd313c582fadcf5e22f5750abdffdd49219ef6e726525658a081c2ced0eb7e14c998ece5fd36c2b1ed35e3ccabe58cf68ee592a855c14b8e8f4d478f263f19662c4b399e40f208aa703eb7168c4341d87fff861db2968795152a76705b7a6a44548829b80e0d83b5de14083f75b25838dc0c92d47f464497a1010001	\\x41cf881eb51efc3f374e8d1d6908889673ed76477027c6e639fcad7977c200a6ce03ae78e3e1796a4ff36a079583b515b072b2813aecfd723495149c9ea06b0b	1653641509000000	1654246309000000	1717318309000000	1811926309000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
358	\\x67a76b4da2be164df11058a1971e633bc61e4a0e13f9db681803fd6d5f1730be0466be864cd05ed881e6401a14d37b37b0aa4ccff97541c2faf4ccd6317bd52d	1	0	\\x000000010000000000800003cc4dcb24778c7cf11891d742ed8986e60b70d3ad2ae0b0ea4e180ea2f3198767f033fda36550c04474e382a4276befe56fce9e8e3304b65f9f6ca1c85b88c6cc83d03b8ae516dc7540a422e00bd9f509da1ff888fc15ff4d9d7419ea0152e408e7aa6d8125f84d0125dc811b21fa2aa3ec163b0c39fa0ca123c6f971f1c2792b010001	\\xabb6054aab85fdd2e064e25875baca7d74e03878dbe9cf0355856507f1b6914b7f769fded301471bdb703cba02b5a31ceb10097cf51c80c1ce4d4219d55e360e	1653037009000000	1653641809000000	1716713809000000	1811321809000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
359	\\x67ebcfa67cb849b8febac984565a9ab0f8a2d8edb478f92160b1502389ae1c57ba36721f315475a6794e352e151b275005313d83af8118d7ca6bca240da7f953	1	0	\\x000000010000000000800003dd23f66e59527b2c86bf4e0dd465948b9df2dc158d7f90359664e75c6a227d0c5cdcc935b13606bbb8d9f6fed0cb5d73230335dabfd9d08bc2a80ce6b9a3e77c211e77c6976bcba773bbd1aa043b41a2740eaba4eba011f92b6979003bf4040143e256f8cfcd11ddc718579e283fca4e82daa960510696d7ac1ebc67ed2e01c5010001	\\x22a251e98ae7c09a972c1bd102ac648a0ab63bd8fd9a675da494e80230284ee46bfaf5398cb7a02931864e0f84cd898b45d2d0142abf5d046c134b6d8d454205	1650014509000000	1650619309000000	1713691309000000	1808299309000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
360	\\x6843dca9c66cd9322ae4a4f53eae64462bc7b72ad626d93bd7a363d136c449ab2bdcb0cc7dd71d8e72823965564384130056dd3c25e34f21a6b70a30ec8ea995	1	0	\\x000000010000000000800003a7b1099b8a9797c377aa466cb573b28d266a379785ace5f7d294fe60c1b82a470de45f791bdbc03a5211ab702a58978f98cb546bbcfb90ff3dfbf4cb2b726d081ed6fa70303a407e7b92028a8e975be4239a3b838c52bb5f2c7943ebfd56995de8f222fbfba2f54850e379c71bb68ccc7a2bd3be53484dafc2fad8df8ba857c3010001	\\x4d4c5c4163686ccb68450b02319b23cf19520cef8620a1d6f3987f35ce63aa002fd5082946417dfda4f27db13cb16f9b7ad91a88be7e4a54719ec363ab021701	1666940509000000	1667545309000000	1730617309000000	1825225309000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
361	\\x692bb77a21858e939ae68005af9aebc2368868eb3876cb7e814ad632084132faf23d734491551bda3c7a58b7e44ab62cd3f7e0ac098ab85c6ec30a699915345c	1	0	\\x000000010000000000800003c022169c2d3d0d184b1d725daed7afc5221fe0476cb75889c3e8ad528dbd742aad71042aef5d64df3e2b622d9bf30038192549f58cf1af5914410d10d0c550c8c95924633f847249e1ab18fe85ea42086f8be9d89379bb9e1d44d2d5702778a106dcad355c6bc501cb6d64b0bf12b893ed31163714115d2cedd58d216ac1256d010001	\\x58173aa9713af265f4f52987d77b2af24c24e997d6a41faf6fd953bff9c6361e2216930dbb4a78a5136735536589be36f10cc3b3a23e0db86493a108fe3a3d04	1668149509000000	1668754309000000	1731826309000000	1826434309000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
362	\\x6cab82756def2651b3477a541b443566866c6f135eac53011316b5e05b0c2e496de17f50b6be978012ad4f70dc259d44184417757d7813708885118e79e24a02	1	0	\\x000000010000000000800003d6518afd2a4e068a86e8ee91c4b1769f741eba530e6483d2997e62f8bfb878178960a4ae830d37fc5bad82756a583c2d39dad2264259c2657605175fd9529afa3269c4148f0c07330c23547e0ef5f3c8c1e8b65c74ef777343dd7f0b515a745106e501c812116d4d7687b62de787d2809dce4a70eed929e1cfd4f17582ab954f010001	\\x46e53fbb224b3cb8b0f2510493330a491362b17bfe307f313effd2d75ce899ab68ec1b4b88860ff43667652f8921446b8f94860e303a8c427fcf33eb5c3d8400	1658477509000000	1659082309000000	1722154309000000	1816762309000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
363	\\x6f2baed022b83fae0f4e8fc51ec643c179b67d3741e61c9dd2cbef11df89d55b6e73735b62f63969f6f5154a58530f02d4c1f3f9b1c3ff2a621f70da368b03ef	1	0	\\x000000010000000000800003b99cb02ab43ee0d5307049a6489c505ce38b44ba2038461f956c1c35bb65124032ae40b3664bf708670cd9d79e205c6f3ae8ee39992b018ff3e0c2323980eec039a93247adf17559094b82074bf6dfe896f7ccc992ad00165110982e12627bfc327b5967537ab55662deac27d78110d63890a8382617cc834b022469ad1b6c0b010001	\\x150ee1f27474291b6a70ce179640cb63c13f4aed78cff3bd83b97db03d9b4b6b74616380ca3bb30ffb2ac8427f55b37d3b1f4e59c2bf2804ac3fbaf4148d170c	1669358509000000	1669963309000000	1733035309000000	1827643309000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
364	\\x768b8d51383f8b25101c85ee2d8cd64eace3550a11184d205332489d9344cbe8e9885b2c9d38a67e5cc2800dbe9d00adfdba430adbfba20a94a2680e12462b3d	1	0	\\x000000010000000000800003b38f7bc97507b8398d643c5f8cad18149d07bd4cec4560509905231d67dd48d7a8602c859f2dfce2e8083fd742ff1cbb6b4213423c9b6179c4d5dae74aff5e8a9b50e861ba7989403cbccfbfbfff7c27eddf4969b2842e9b5cf6eecd3a6286c86a403d896f536837080c8a662132d78057e9b6ac38dd14ac6eadef7421c65b15010001	\\xa5fd47b1d7980b60906077a5c4e51a18a28d63f54cc55aae086a14b86095fff298c00240f432ee9587633a17532fc5e8b655a713e00be39c23cc0daf020dd100	1672381009000000	1672985809000000	1736057809000000	1830665809000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
365	\\x763bf968a5f191709aa3dd0103b70ea73ee0c8c0415bc14b82c6918bea0dc0e18676fda9ce4569c6d212e0e51674b7aa5f16ca12fe995696abbc90779e31dccf	1	0	\\x000000010000000000800003b63cf0ce4faff443e51debfa0fa1132e647357d0331c131b127f54cad8703e3ea484f0f2a6f25ac83d3d5bbbecf487db7582b71f3a8da1db18021207910ffb0bacda56106e12dfbf7a7ac77d2e5c397322c0e79167be2a4049e9fae0b4822342f5e1aa7d5918d7a0e8993cf30b6174c219b4402a428af36906666194cd6c7dc1010001	\\x290934fb37dd5a0c8202b8f99aec029036c6e55fef5ac5d70f10e375163ef27d3a9539e476e246767fe78c3dbb604c6155d6be2686ba9eea36cd19f65982970f	1662104509000000	1662709309000000	1725781309000000	1820389309000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
366	\\x781fc0b1c4daa188ad6c4dae6d9232b52927baa7cc3f29008363006f926f8803fde8c983ca50926c9adc61c1dc203e90579af5e7aed775e49611ff793385bc4d	1	0	\\x0000000100000000008000039a7352f756df1906d99c3c01b5c04a5b47c8df5e17c72c94787d36d4d083fa6f054beae8a97eb794b20f7a3446f32e0ef519ef1ddab87e68ce4e5b85c1a5740526c77b7c0fee75e69040f388105911a4f1d4050bfb99cd271bce7d1fc55d8f6e1fcd44670e63253b28ae581beb732f9cd4d1be9436adf38357fe68c8a5272531010001	\\xa1c674ab357564dcdcf2a6c05499ef03518c8644f1714f43c897d1a5c039fc6023d3d1bd27eb15469eb343fe4f37d27ba2f6de7054aeade1b4cf44726b267f0e	1653641509000000	1654246309000000	1717318309000000	1811926309000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
367	\\x7813162cccd8ee376163445a865e1ae0698acbab6e03cb5bd4a87ed474f65be19c1691e530f44aa112fa627418cb088ebe0205239b3645aa27d6341a6afc4ba9	1	0	\\x000000010000000000800003d69ba06e2db2312cd1f2c789cb25e24c127b452cd7df6fe2e72a58ffd41437c498b972332f7bf4d4e3709040455018ed3989c7c27c9749b2848cd6632aa7e66cd49c079a040b43c76523e38f9f7ee92ec1854e3de6b8c30060c93e542668434af040e91b7f57afc951f816ccd9f22e036c02e6cd83b67cfdb50690bd138c4a37010001	\\xd2ca48aacc82e157e99982accc9e5ce101f69f980fa5fa18bfd0398dd7128fc6bc39e5887a9418b6adf5bd3d135f7ea6f8ff8ac5c0ffc7b1af38d4a79cb1bc04	1654246009000000	1654850809000000	1717922809000000	1812530809000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
368	\\x7817292a9458d6096cc066fc4b57a47aaf3fc3dc28c7ba0aace603d3309b09a096741102d3eef8e11e0c4e4d9e290086d79550d6290c6f383cd8d8965fa347cf	1	0	\\x000000010000000000800003d5960808813bd9c70e41302f56da13134378a6ef468de0148f9d428d7f35feab0f3d331b9be2554f3a128bbe8dd9ef2784097eb4a78347102796366c03e6ab604df871d465046548fa009a4db3e68485b97d091c210c609fffff83eb55101bf6374693d79aed84f23c45052babe09728e9546c046be293ab3080867c22ec0865010001	\\x73483eab8ed5934e325ca96d3758a032eac6d06886eefc8550f1611a21e03d9e8e5cb7669800b853368e9621b4199b2775b25c9141ca24bb9cb9e436ab40e40c	1679030509000000	1679635309000000	1742707309000000	1837315309000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
369	\\x7b8778aca7a1e59e08d7eca5cb7605bd6a34116969095e6c359e269cac33d2b42156f227019eda35751d4e323db2cf57f75244e62a6c88ee57cf6422606fb4a8	1	0	\\x000000010000000000800003f4867bcc4699309c2f047fb185131651c3b8cc6a7d17e4138552a29a66163b6a2d74fdddb4df46aff1324bd032aa7e14efcb36a6007861c30aaed0ccd1152206b9cd3a3df13a39852f4f66750bbdbe8a6be3ed016f186368da80bc292f941a4a5bb5ce957d5b5cc95cdb2827f4bae29f56ce14b6f914e91ab68d81d9cf9150d9010001	\\x13c3e89fa08a70a24f996dac876d2d1126a888070405604bdeabae54c4a015889846b4f7a6e6c11439f1f27bab0372e4413d489c83d3d7457eb5815711b3660e	1672381009000000	1672985809000000	1736057809000000	1830665809000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
370	\\x7bf7b0c3751d8fd0a97e071b66c81978322afb2865433fe5c6c1163f0acf6f13dc9b1e53d0ca20bf131f1c3de8cc0ea05e027ecf4eca1778491d03b8387f171c	1	0	\\x000000010000000000800003ad969bcd6c84d1d4987f48f8850a35cea42fdacc9b0c96600397055247859c3563a1b8f94c7d87cc4d8eb4554dbe689759705edfba955c9358f1b5400d4f8b634aaa56331e884b8fb7d278c9ebd53cafef851f69c0fddadef4226069739c25fda53a1bca34648c850760eda2808ecfb201dfc9cdd379204b48788ba0661f2a3b010001	\\x4ef62535136d215974bc654da65d210616ded10875c16e6893ccb7f3782f5adb077aa345da35fe196486d88e283f4579f9af7fb2f800b597636092b26246100a	1666940509000000	1667545309000000	1730617309000000	1825225309000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
371	\\x7f331e1cce1d197d91d9c3693f92dcc56c7ad87708cfdede63bc5746258e963f3f2656ee249daed196e22457c8bba095029d0d8b8eba5419cda565aff172e662	1	0	\\x000000010000000000800003e04fd550210e7bbdd6d1d3ee42a463d5642da70c6a81daa0977531c14ace499281320eb74cae762c83dc8504e6ccfce93ef31ba2d54af1acd63cca9c2da5c6bff646a62ea3f114eee3a21259f152a9cf48d1fc84e2f3742b26b3b56fc65325f92b0db8f10b379a28fdae659c3fc6b8d30800ab926ca5c5a006443d21aaa43133010001	\\xf6a505e80b480eb4ab0d383f178e2ae8fd50d18b26f58451aaba469ca7518dec3affcc6ba613b0371f75fea8494bd79d51a24abd35b65a84eff65830d3e62d07	1680844009000000	1681448809000000	1744520809000000	1839128809000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
372	\\x819336b41509532e769b5be47c4ee711b847d6cd218e697ace4c8543ed1ad8e1e62974a2e9c033ce5173eeee0918718d87c46549ac3adceb52468ad7948d977a	1	0	\\x000000010000000000800003bab54856e05869096ce5f144b9317af255740666fe895087f886a7d05baf61efe04132e0ee17318f3a010e46229397564aa9342d5ad5c4880f6f24441c897e0b222b211b5905fc92ce2681a9fd36a721736db0306fd5a1da9d2991db798937bbbae491a6b594bcc14a0bcc8d23ded0aac568c1777819e75ef41dc105d7757bfb010001	\\x15700655a6d6526e1c1c074e836c44a11ea41d9980011bffcbd196338e1f1968bf86532547e785c4bb2735beb76182a300537a05fd03168af4981e4149bf7c09	1675403509000000	1676008309000000	1739080309000000	1833688309000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
373	\\x82d70442edc32ff9d521bb559cd086ff7b0c6490f55a3a51bfaebfcd1c752b8d62593995e94f0a9685bdd2151e06de22dc4e3e9e07a3e6afa9e33187a13a5c33	1	0	\\x000000010000000000800003e7f9b1fc79ffc1ae6c3694798c230df63976577dca4a2fea8bbf4053bc3b2252eec3970d22b9b8a8599c1742a98d6e62cad9c6a8de16f5a1a928990bf452c200e6035ee36dfb5332b52251cef2e7c6da3bf60d5ea5442ae01f0b7d6eda614af08530a9d19d469cbff694bbf898bf9b72916b0e7d2a7d1929f2c0350df8ee2af7010001	\\x083dcbee6a4dd3cf949f049ca615fe1ef014776a7bb5be8b057c693b51179cb87e1144490c6bebd10b3e1a831555b4eb422d794d8de6a7274848f1c7a5f6e305	1670567509000000	1671172309000000	1734244309000000	1828852309000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
374	\\x86e77ea63d7b2cddafd38889eeab22f8e24d72ee229ce151717d28b6bb02644d37995d81ffe4df295ad7aaeb1e198f1725c95857eba48fa0eb30a78d350a6190	1	0	\\x000000010000000000800003da231873efd8de0aa1c8b9e94f3e5491018c4a2939ea5f42e4b5d8f6aeaf93e988d218b81b88224ce941f00e379d0473e246341c771a11d94683edddac4ef883b52edfc5df76efaf051cefcc823e560bfea89b5ea6ec537218f79088814ab3c7e85fe7f8912dfe163a621cb7085593a05224c24f73ec7ba715ad63f329708aed010001	\\x63c94684d49bdc9a8fefd62f078c9f6fa0090d385710a4ef6aaa146f040d352dca9435b4c4788d45c129df1ed7e8f62103f7f3b2e2e3acd75ecc2d2bb71aec07	1680844009000000	1681448809000000	1744520809000000	1839128809000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
375	\\x87bb1f021d8c9e5f2500672f9b20a024dbfb6806da8ddcb6567bd9ea594b4ec7ecb76d5df8c19ccc501f76a2ae0e7e18f92e2f0f8d6fb35b0ed06950fae07003	1	0	\\x00000001000000000080000398367aa33c4999f1bcf7693efbafb70c02e10778140fa00f9deaa6346dd07ede6f4f4fa673228ab64d8d32e4340ddef6506e1514451df4a75b3eefded5c91993be657b27fa5bd551d4b54e379884f72dc548831124ae7ce08a6491ee49fc371c5a31745a8aa12bd032b90005bdfcb11f897494cbada8c3e2877758f83ec07a81010001	\\xd399f9374ff7989a0e381f4d2dc602f6f5401cfe419a63bc441ca9fd4237dd0d3eef604acc17d61ae76da484a229da5c86fd8e918e0b4e7d5a1ea286645a1b0e	1671776509000000	1672381309000000	1735453309000000	1830061309000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
376	\\x886b349608469a8e2a821e9eb768ad8b44b0f980185ef3a92f4d7c90b2e7658a6ade17dd5823ff3deb618991cfdf19a45d631c536a1f50a8368e324d91cdb9e6	1	0	\\x000000010000000000800003cd30d180f395ff8f95e8b53f5bb3faba40ca014ec0a22d43733d2315f8100caf11b4ec4a714e589e4c71b1d40e8c768e6a948cb44a9744a89c8323caa02a429483f92b572ec7bdee1a3609fdc932ddd445423ad93c95d79a28f741bfb1c036422495be304ad5827bd1026ad8237ab26190b28e39468e6a213c3f45bb1937a0c1010001	\\xcfc46f13860a62a414fca5a6a78a0615096d74766fa38d25ca2abf7de07c691fcdfaee903e578a859d21534a7f9bcfd1b6d205d3dcd8fdc6951192f414d84902	1663313509000000	1663918309000000	1726990309000000	1821598309000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
377	\\x89d7cdfd76b9baf16d10a76e52b4c3072e7394dd412e7eb1163c4b8050b9595f3a9212adfec5c26d3ed2197b4c4bedaa4ac96ff9d08bf6798e7261c669adce81	1	0	\\x000000010000000000800003ab523d54e40eb32854013938b1ac6152cb17078a60c4f65c61accd8816bc135e20c19108a39205a2cf293bd31ef8a5a72705dadebc4916a856b20444e21e88a58cd8bc248633c245a1eb1fb1941afe338c74964509cea80d226ddeac11a0c25c00468aa98f2406971084f7486c875a2cd65578c3c42dee81aa9f027ed28ed171010001	\\xbd7f37627d1b17410582222f38312bfc5832dc22841c7daa3a35486b4d64e00c9d9be7ed13acb81f38f7e79a1b072a2b7fdbf210fb177210d9f7982dab037809	1674799009000000	1675403809000000	1738475809000000	1833083809000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
378	\\x89cfe9d1abfc5f9ea4c0d64320e230e4a1adc5b706f979a41a49efbc1998c2e201d071c9a185263287ce783e7bfa5d3570c29b52f76b6f78fd631d2bbda15360	1	0	\\x000000010000000000800003bd5120eaf38e05b5338cbd35f7afce543439093f563ef66f48b189abb30835c8236e6a506f0a74e80524f1c3bcdc2fced5f9b244eb54cba12e3cbc9177c39f83bd2ece250ec1b46a9b609f37d46c6f6961561da1c2ed56632f267350296ae8c3cb492394e30e2172e641cbf0209f6dbf42f733e4263304788363a7492af72eaf010001	\\xec44f788c918bb09a8756ab444a9e14db5a2148f0b3505b8ad4042bf0574b95b4fad9c0084f124b1b7e3a4eda16d0f1599c91482305699e37852d514c8117a0e	1656664009000000	1657268809000000	1720340809000000	1814948809000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
379	\\x8c7fa8ab8a11bfb9758d49a2c6f7eee0b6e516b46239a669c3fbb2e1abb9532403e51ad3a20cb16599deaff3211bc4436b0c0be7200f25b27f184fed839fc7db	1	0	\\x000000010000000000800003c17379a83194fc2ad4a5f4d5571d0e47fe50bc1b9117076b93ece18f7bc41f8f8d30ebe3bd67e500cf026d78c95f110ea55a4ce414e2530dbc920fbce71ceadabf57b64f2cf35355ae4d7868e68aebe8467c8185da114f936cb574c1eed2ee5273b6fdc072cf217adf24422d6a224f9c6d027cbda5bd3e6a502570a3dd978589010001	\\x441105e4f7e2f6c73e2370b7f754975f969cbd1575f9ddbc460a7db4bce9a9648bc3cf089ef366996e433eec73f24e832db305fad4e4358c58a80aba4fcb5005	1674799009000000	1675403809000000	1738475809000000	1833083809000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
380	\\x8d6382eda48e20d503bf51907e45d56bb11664749289fbd53e9e1b7059dcfe613755e229bd96ce0cac4548e121fc81052d8dcf3c2176ae91971aad1692241630	1	0	\\x000000010000000000800003f52088bb3f1d0e6b55f4ac6abdb41c8ca9a910867f92bdb4bbe9e12162a74b5a2a811717d2d56461e233524913ba1fba3c17402ec74bf7ff384150457d7d2bdeb7889b84054ed66aa2e761da1a3acd755f35cfc62d7e109c1401923f9ef2926b2f1e90f10168782e1079f95356e4a5ffde2a3969dcc0d38e91ac582681e86855010001	\\xe9ee8ced9a1471660e456a29a44f821f94bf945ea98d79381cad5935117383253260be1d54df89fc0d1206e65905eed9fb763bc27054052f49306db7eb76bc06	1679030509000000	1679635309000000	1742707309000000	1837315309000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
381	\\x8e4b93b52a330557bdb9949f785277064a1a68500064d7af0a1b925e9f5342a1017bc2b9dade96994d110800668654512982a1d1bca96da0950ceab5a42f88a4	1	0	\\x0000000100000000008000039f521933047d93bbeb3f2b343ca96c0c22810a2831f61ad03851202610e78635e8e0064c4e1afbf880051865651b376771a830de82d128bd4db1d6920dc5a0d216fdbd43275e036547e423bfcf1b2ce39fe4bfb556fce9790b82de4fb8207a42d2ccf856bbbd0334b785627dac07f76912d845ab2720d07aeb7d0d46c7c6992b010001	\\x75aed8b56f2e031d610be2f73047b971067236eacbdda39d9c5482c2112c9823a52c6633a3b41cb0ed791b48d3723342681b40ceb56f6a631b9e040773a2ef0f	1661500009000000	1662104809000000	1725176809000000	1819784809000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
382	\\x9177c57e61c07ddb5efb7b9c617a6facd48522f7c5632e1accbe66a3ed44eca92467f93394c0e017e5cff6326d6da2c2f5cad0a3daab37cdc7aecb84db655a3e	1	0	\\x000000010000000000800003b9df302884e511734d1a4a4929a6374ce4e186453c48d617b2fcd9e08701ad7d029c420a161cde1aae6aa38da64e87886dffe1dbb7da55883f5373deb3f1e87f66bed3da3eb77217b7e80bc5efda8b9cbc4ffb2e060bf428a8204478b69b4cd34c3ddb876557dad4d04de52149a6752e2f4e9e60e24f30dcbf86e75fde59541f010001	\\x6a40ea88e4985c3fbfb57e5cc3d7527669c58dddd6881a1ddf6bbd3a0009472750cc385f4e9659df0698034037e8e7ce7e5199ea4b296fd2c989d964b645be0c	1675403509000000	1676008309000000	1739080309000000	1833688309000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
383	\\x93e7a4b6be522f7a3eebce76eebd01c7068c48d93f334a146c08d17799207ee3ff51a3210f0c0a81d31214e8f3f778ce4a0c06ff5f4b309b01a2c09f082dceac	1	0	\\x000000010000000000800003dd84e4952f36bd3e2956e3805c50af223f0170fda0cbfad20e745c0712b45ba8bf8697fcd93dfb2ec534e0cf389dc3465c2baa8d2cc781785381e154fc41c261eb5fd41c23582c503d0d3db0ea9a92c2064f3f39926e8ac898298f0167ee5cc69b02581c8b43ccb37f1038056bc65a896da43725b990246e5d3e795f7f3cf367010001	\\x165017fd4d57194e0b22d4fc54c9ba1cfe78238fa35bd48c653672cd3addcbecbd5bfe39188e47fe15c4b0d0a29578b540ff26f424a06f82d6cca6b4ea3e2906	1659082009000000	1659686809000000	1722758809000000	1817366809000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
384	\\x93178e3c3f57a0dd1eb3790feab99a30e46999358840d4858ae835b94f5045f6ca831292ce7eddff218e46601da6582f1db3fbcd9c67d76cf23bf85ec3d2bc06	1	0	\\x000000010000000000800003cc22873f5bda868cd11e7d8882e826b830febbdafac9df0178a03354bff57cb50748bf2130291fe87eadd5f08141cadfa6d53f74da382abde968f8848fe56617a5c6ba1c540bbf4e49ea1500a15c200bd1842d54c73903fa171d2aca1b7ee49507bbd373c926b45252b44000139dd7894f2ae1f552936ba63c054c8936daccb5010001	\\xb4d72b900aecb248fc7861a6c8e5995ba1b59468c7ee9ab39be1b6621f976094b7e7e8bf34c9e1ba4efc0476a6ea4be082ceffa49db7a26fbf3793d97adc0b05	1662104509000000	1662709309000000	1725781309000000	1820389309000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
385	\\x9307d25e77561a940bee6e46c458b5c7ab36bc20bcd55b6d64c1ddbda3388d67c7d3681b6de2296d27d9d4c4bd0bda16770590ea8345fdc7f2903e07cdae2061	1	0	\\x000000010000000000800003c287428c1e137ebba845b80b797d016c5d6827c9d66ac5cecb74ea75b7b3445dd7de4e34c0853303916b759bc034d9b7c6048df560ee732befec4ffb63cabbc6b8b2a350ddc12d7889ebdef09a26827892da75fed255dad9f55df706230c9122f067bbc351c491d6ccfae69c374d436f7d9ba618b44dcffffe1897e60b69778d010001	\\xad41f983ece2ddc17e4c57c71a691c1585a9a23c35d909513279882cde577d88bf49878fccc2e84bc69b89926bceefc93ab28b183c9772b5f5d6942c3cffb008	1655455009000000	1656059809000000	1719131809000000	1813739809000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
386	\\x96e7827723838362edfc3531458be6e56decf3629a9ee52b519d665668e13a6e1d295eead443462b4c0be4c0c8f54e5e77ec4b77f61d3cf7c0e8ee7f6bd12f5f	1	0	\\x000000010000000000800003978855454e71922ebbd6ed3e8a9ee167b5c88aab7d99ef0460cb66b7afb812d257f55ccad41f47f8f6ad4d2d9753918b51acbb30b162c9061858b04ce854bcb575f4b74025be43357ae98aa7e8f8b23e0fd503d8f6dcc42d99980eb614611dfdb2b63c7a1a6edfcf1a266b81a8f674e99e2c701e4a4ea2fcb4a7f0014df174e7010001	\\xe486951ee1c3546367cb077fa3753498373c6b71a163067ca02f3da75fa6240511b72e41f2c896d8fc9893d3ddc938039a5430144f2bd2173939aa09ff99df01	1659082009000000	1659686809000000	1722758809000000	1817366809000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
387	\\x99030cbee3e4445ea7aa713f152a4db1d304748613e4da82fe6dca1e3ec808b47cc575533849736451221c3fe0be2fc3e63668c9d5f4c761d3283a6b3066b104	1	0	\\x000000010000000000800003b82e5e203756dea6504885bf354df71f1bda9ae720b7e5728208c97918f98874875b136ac67104c6fa82ebdabb8b37cd2800da5fcc26b467a48d1cf3262bf742c186aad0782a091f10edd82ff5b0e3a696c0d5b6c39b7d749290575d386dbfb3db5f51feae90f9d38817bf53ca10a99bef0eb7d173f4253c19cbea55e5e41421010001	\\x1c63cc36ae4c481dbf3ee5ebd0bf74de7c17dc3ee0b81ce280fe65c0d3d05ddfa591afb5d41190b95d8555398b621ab786ef96b501aef762d527049ba592620d	1656664009000000	1657268809000000	1720340809000000	1814948809000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
388	\\x9ac321a984b8e3f0500b7084809770e3d0a11017e315e95c54a3085954b0995198710ccb1c986336e217b7e0bf0aa001258ec8aecab4c1c0a94dc5854fab324a	1	0	\\x000000010000000000800003c01194bc8821b5eebc6c5109845341052864ba59649e0028d669c1fcaa4aec63540f4ab4c3c31b62e97c22eac25aed173027ceb8ee299f33ef8e866ae234d3325d29276a8fae4c50f63b1bc94eab045a1ea83264b0f0466b0f471576ca636b6f2a69bed18eca2e802f767738360a95d4fef9153de514773e1997040eeaf906e1010001	\\xd56cc7ad6f91e818943a93b1a8b46caf348f362beddeda77a700f01800a7d02ad788ca96de50fd96ebe9b1a42a3df9ad0e82f435ca7c58f3f518226cffc8300f	1673590009000000	1674194809000000	1737266809000000	1831874809000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
389	\\x9a57f7040a45eb53108507e44d7b466a091a0ebce72fe71943067f1cd44bfb52d26ac2e67520c16d155b1f0e71476dde6710248691fbb8e05057ce885e5e69f7	1	0	\\x000000010000000000800003b649ccd1a2bf8802a6a9b6770729cb9d9ad55847d3757a9bca833ba4adfa60cab823b4bd72b246e89beecc8360241c3a912dd713dc9fd45ad8e9c4718387480c87fb5bdf617d7fb974fd46a1576ff991815689ba0e4b2cd240eeb5d4c4cae81aca2f2266840dd7702b44a886053793c3ad637ad4f13554b735185e40a32d236f010001	\\x0fd2b3aef7108951be304c5b94967d414f86283314127e06c092c936c876e96731f547daef709cc4080dee6b9c738514e4de5c4a2577ebe4c359edc585eff00a	1654246009000000	1654850809000000	1717922809000000	1812530809000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
390	\\x9fbf1ca5be0c91a7c64727ff931ccabeaccdb6f2a36f7237ab3185bf37430df7848530305c8e4f057a43ce5b899335573843fd2ca1f16e049caa54a3ec0b4c1c	1	0	\\x000000010000000000800003d9a7f0f85f42c1f2c3c19f8934f9a92d34a2eb1b7e56c572600a584f580c2ef93d15372b04fad9d0b6174527e5f8d170f5652838165aade854264e8265a0e0e76cc260b98bb10b4cdae7b4a89c0e165f9887a9a921028599c0a3fca1c79b81f6cdbe6fef9427d51e9c972ff3feb2e365658f3c863b97b9d744f98686b7356d9d010001	\\x6d5c606b8ea175cc85ef2bac2b4f64785a7a2606487b8cfbce64e416f03c9167e3967b3bfa4b6268be1ef97e4c88f0a1056565cfbe7d2fb49157532e5f283f0e	1653037009000000	1653641809000000	1716713809000000	1811321809000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
391	\\xa04b7d87b19dd28b16efa8d68f81febab2882b68fed3cf84c56ef405d5942d5ef3f03729e4e09384ebb207a7f211cef006cc9be39e83a83cfa25d1ca911ba638	1	0	\\x000000010000000000800003b573c292f81b4b0295450c7908ba9015553b6037bc858b79999141f55895f4f7c68dd6d3a8dd6c065d8aaf8ec5d07b14f3f9f46e663e51c955900a728c3d1c49d842a4f1ab6e2abd2e4c5bed847be643094788ab13225777ff72d5c38080ca38f44823bac47e3c6a1586a2290556b1f9d94252b6b5fb6a6da66e7418caa58a81010001	\\x6c1bfe09a6b573cc9f58d8e95a268cd217abe8db807acbdb7e7b73805c80328b9cd65fb52dce0aadcd688125ec408b143abf46c5d0df12e7a014188bfbc84108	1651828009000000	1652432809000000	1715504809000000	1810112809000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
392	\\xa1f718dc76ee064b265785fc91ba2b50e61aa8409e546cb69b4a73d842a7c21a5e59bbfadb3f5c27bbcc5f7012499c0deeee2247c8123f550bb624269ca156ea	1	0	\\x000000010000000000800003c247466427cd17e3d318c241f0f4436dce31364e761bb429060680b45fad29a870f6ccfe61da608cbcb3dcfdf5f09f7723facdf9270dd581838c2ece91469b7926a446842954b9237b38baf5cdcbc569e8212ae61f2fb09ae1d6b65a2f665c32f2aeb166b50e4ba660be3fedd029365547ff38820a58e29a90c279754db7fe55010001	\\x3e9e82be49564fbd423637a86c3682cb5177fa102f867c3302255df792fc3b99b63de9897f4b86b145b98fd251d2c97713a5a0cc4c1f1f82b6cb8fe86eedaa0e	1674194509000000	1674799309000000	1737871309000000	1832479309000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
393	\\xa227d8bfa318646f97f1916da78d4c2b51e2eef391e7c632de9177841ef4a59752f1bfeea076c0e8144b6bc4f884a7cb023f2922187a4c68beef9049e361ca86	1	0	\\x000000010000000000800003ab3245e57a90cbaa780c0ae3cd5748611fe43109a2278b12542e1efb448e77f7a80493fee8f4a772e8fad1106df0a17b893ce0a3eb62c63e941bb3fd6aa6de1e39d50eba697d2a05afd62fad2d2d91146be5e7d6e572998457d37a7f8d34fcde7357b0ca1a115b85fa53da52fbb73cf901e545b27d42a6d35b61203414d1ada9010001	\\xe7aa05d4b2b36c0db13e4f22ae8c5583aa612ba2975c22396d08b87269893d50c28298a04fbaf7ad7dab68b6bd26eaab7e87e1b27ec04bbb56c2c68a9aed2505	1667545009000000	1668149809000000	1731221809000000	1825829809000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
394	\\xa3876a843b0274f3725d827dda6e64f34cbf98bf2cf325f7a231073c82225c01134564c1eb70ab89fc5a38c285dd1521ddf95f8142651e4de29df4f9160f3be3	1	0	\\x000000010000000000800003c1b727bd3f0de3c60cda155b7929f398297ba4bdcd4809978db26ae534e3ace4e4b91296060b15bc68a3eceaaedacde6e65a2b07d7972ed25f830248909430859f64c9f2620adf642cbc3d5d4b0ecc95e0db106fbafd75f192b31db8bff482b3202e20a483a72578fefe1601984d74b003b75feebed26324bf384f7b28e685bd010001	\\x0dca5950e3f7244afd2e217920025c5a7cf552a5880e7c37aecf31fbd7abbdf7eb917d6828f4ddf8d20b4181be8746bea89bb14e35537f54298594889cb6cb04	1677217009000000	1677821809000000	1740893809000000	1835501809000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
395	\\xa52b695ee58771bfa1a316d67256df5f7ef0b5e5c2855ffc42a69b6b493b09dd8a6baaa093bf1f733088d890f64feecaf70dc6d0d8b6183a1f9bb2f45eeec73b	1	0	\\x000000010000000000800003a90ec0e7d40f13f8f971b5cf86698feb10b26381db0878f7eae4bce42d267b8cc364e77a2c2c2bf1d5de5753bcc86f1cb367499741b435bac874c31fc8231c70de25bd39b9b55cb5e8d9360dcf91fdbf4932c9e2a753b3126c4ec3cdd5c3520b4d5e9448302d31f7eabff42aab7841761b83332c5601c435fd41f0108b6500d1010001	\\x74d3aa7d45eb8dcab166060510cad915d4318187af2dff4c3f4d93b11d851cfa49d5da28848e2acbf9c5346e461fb802c1f88f6d627152feb46c60c47543e90c	1653037009000000	1653641809000000	1716713809000000	1811321809000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
396	\\xa937c1e3db4359eb48f4c685d78ec3e6bbd04a596f811fe194ef7d05077fb9595e7ebc956f9dce91060f3965f002087330be0aed30954c7c4aaea44de3eed6a4	1	0	\\x000000010000000000800003c8481a7f007ba1ec57a4149921048482d4fc8c78058f9b6b99a8f12c2b00dffb6319e355003533b8db60bc155aad63a30ffeb2fd5274bbb3753b3661cce7ec65b1ae808e07f0cc06a8cac48a0d6b2095d688cd5880c171ed4a4743fe2b6277d7a56ecadc52568e1e1cc9debaf151c2cf994981c837361bae1e770ac4f28f52db010001	\\x6709f931246ac4a358f55d48cbb825810252c08ffd5e857ef8ff8891a40ca83eedd08e85a2351fc7864921e349b3ef2490aabcd422faa568324e37bd9214a300	1674194509000000	1674799309000000	1737871309000000	1832479309000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
397	\\xb027b5a0145d42b419b8ee63e5bda1de6af0aea72ee62c00217c175793ff678b82864cd77a002e16ee4d955848c1fbc20a42eafdf8f0f776e8bdbce77ffd3c4b	1	0	\\x000000010000000000800003ddde80a37397dcb3bdd6a5de0be4b48efe77c275b3802306d95ae6c8c62a536020f789b6525b3e8224143661d4d5d5682be8542acf7eda5af95d9ab304517b245c7054178a1e3fe418d283554146ad6eb35862fe001e754f98d223b1b7ebacf46640c774424d3cb3de4fc8e6455a09c428688b3ba1eb254243421497dc43a999010001	\\xb0b21dc0be462eb150a6afbcbf5d01648e4d6f3753f92cd986b32cd9dcacf56eeaf4f6f29d146d674c713c7fea8c5fd80355da287e01d85401e559d09a240306	1680844009000000	1681448809000000	1744520809000000	1839128809000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
398	\\xbf9f4ea2ea5aab0f603fc2232420dd60003c3099331cd930f335edce8a8e6e91cd8fccce7462d38df831ec846184ad59a212add531c902ed9615d23bda16ff22	1	0	\\x000000010000000000800003a55847ace5098ee63f2c3548705d1d3907dc348bce761bfbf5bd4a7c0cf94c609b65929608131e9c525c66057d5ba83df47343b25d5aa54345cce1ebfc08c67abecf1e2a1ea828ec454e5b84730b36c3145eb6b0b68c0cb6748e69f71282e06a50690d2fdd63ac7cd175f545a018379b4348b43cd8d0961cb6ed04c0e8767bdf010001	\\x357d1d149e25f82a735e278d26854994da1f0868a1fc76e666e63ae3eaaacc5f6d44e5c32aa0311353167835ff32eb7b69c48132fcbbfdc180c4e0eba101d70c	1650619009000000	1651223809000000	1714295809000000	1808903809000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
399	\\xbf1b1bfcb7097a137334fe6df8fa70820c37eafb2b4fe4e04135f7686c14a169bc8774bffe39a3cd4547e966743eb687b26071b802a39c6a4b3dc1c82cbdbe5e	1	0	\\x000000010000000000800003da512cf72f9fbec4970fa33d12033597a8f02d9ea64b1b03abfea8ea583bd6322e66f59dfa876011423202c4288b6c310170c12c7fd5d1377469cf37114cb59a1e4b6d6e9ff402abf569d1b35573bdee80c90189194ab45d0a982d4a3dae55b6cc58b32ed4bf231af553cfe09dc660d1e3d29d8cb4c48e7592f3641c61cb7719010001	\\x1045c851d050b6b2172d4798961611f6e9544fdec4791159a4f1f791c8c74fa4a6a62995e6c840992f3c05ddaca2265c7899fb86519ba8c1b09143a45e79580e	1666940509000000	1667545309000000	1730617309000000	1825225309000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
400	\\xbf170ce9f4869f96f1f484504641fa37dfd8f5ba51dd06dfbe062b3403d1abdbd171e8b2335177b983dad4c4e7a2ed659581764df687b873923b9d47238f5979	1	0	\\x000000010000000000800003a5cb5736f3bc524db75cfab4d532dd845fa4e0aafb8d84f4e159ae93038b3f2c8ee96c1666bae86e7a5fff05bf371a2e5607879a8cffffea1ffd482d3afb583ca609d5c05b21325c7e324d01e3bee900b0b76e36fd776e41bd6263d212b74c6b1f5c64db972b885907b164a2505ae7a50ccd8a1d4472ca4fa3d72299a6bf3643010001	\\xa187c616146edbbf3567ddef95bed4a4b123648a001ce9bc5fbeb623d9273fc1c45eee38c3678ef55ad3e5dfe34f59612a6c94543f256045552ccbde9cd35a0b	1650619009000000	1651223809000000	1714295809000000	1808903809000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
401	\\xc0dbfea4b2a1102d87afb349a715641559a70f824ac1cd6cf4aadc5a73dd10d001188b76c1ab06baa16106823fc35abc10baef2c28686833c455b8781a73e0ca	1	0	\\x000000010000000000800003a556b56eaa0f5244b29d29073623a805f8e22aca63d4fe3ca343a04ba0566596e8c67db41cb2a177bcb650a3b24da12129bbaecee133488a3a4ed6042eceb28fad12ffbbd65d9c653e6a62a667c0896b1bf60d55b8e75a5360e3c390041945192baff463a6812f3ce6414ece19230d88256ef7a6ecfd2f7f7cb6a85a22618a9d010001	\\x98b4c8190f75fc2e7b7262772c5a6f775437bfefac37236c35c38a9acbe6a177f111e25391e4c398f0f628339b12725140f96d3c63e45b08e1f8c77d9521bd06	1673590009000000	1674194809000000	1737266809000000	1831874809000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
402	\\xc1ff55f0ca7c459b27ef0da93554c98630a47671d4756e2e3233e8fa69dffef271310026c576bf6c7ccbd86af1ca14541f7c95b21a3b617adbd90a69245cfaf2	1	0	\\x000000010000000000800003d0e87c6fdabf05f3f27821e4957609fd7e806a5b07061a483896acdf6e943f04ff032ce6059056fbf5444e32b6cf0af319d010b26bcbbe4e072f089d937ded92fd6806872d100e7af3d9485bdb11a75c0256eebb37014b19e3fe9bd75513c788d0c418fa22881681df8af7c81186bf69050e8fb666cfb512294ffbdd9cd04727010001	\\x3d36ebd3d6bc3f692f1176e3a399f92a2ac478de092aab23cd7543a3dcbd510fd312abf617b458c0bd5b15b5444e1218f9e2478e3748845e5ef3766e7c07a402	1660895509000000	1661500309000000	1724572309000000	1819180309000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
403	\\xc5db73b77db589a1ff384aa304cfd432c149c90629f22e3c835323c39de3e00fad46cdf35bd52ca919839f22f8cb22e133d66b05ba12d9826ad64511f40ad367	1	0	\\x000000010000000000800003d374ca261f1f2c6dbd2b48f514d27e40fea951981d6c84b938d5b69ac6a1c231620904079e94b754d663c29d95b92d0b9161a1cd5ad965e30c820ab8c079c297cf1e12c41bd1aa8d7d740db6b02e57defdb318261d248051991cf917541f719e6af7f006e3516101e440bac389a87720087fda62bf84b2c5a24d0dacda345eef010001	\\x00def0231d94699a759d60c84a90b54a3e1754eab4fbe65680c48fd3b14f0196f5e441c6757ec49ce7ae26b043390a7f49b1a3b84bc906a4a14c21e45f916102	1680239509000000	1680844309000000	1743916309000000	1838524309000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
404	\\xc7a7bfaa2fe9a526cc9a306a0a934cc5f9f0781c9f4d315c9fe09e4fad362975c9ae6d040179ace8c2602746778cc7c9f7cfe5bb32cd1e8be088d3f19fcaf184	1	0	\\x000000010000000000800003ceaff3964a67dcbe141b78c93168bf092e10a99c87c4323a229a19a247c0347120167fbfa1485659011adbd856a71a777733d397de47160a3c7083ea96c3c921576a9826a3f42dfd4a376a5b893e2f8b074cfdcc70e44acecb06367d29f104940437c2377656946b572074d1a48bf9fc53624943d5cb458021c2b17d985d27bd010001	\\x7324da99ae569c688c6466b9891b8e0f9fe9edd9f628fc3a0950ae73b787cfcd7fe00e8d91c669f4c1c1203ce5d074d3a9eda4c848a1930fd929944a68974906	1668149509000000	1668754309000000	1731826309000000	1826434309000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
405	\\xc7a3daf967487af122f9cc180a8a001ee7172c57a5a1095a459ec25e036b6a491385ee2dea3003aed4d6a216d996f60f76956864682e1f8b1bc2da994506dcb6	1	0	\\x000000010000000000800003c1dee34c1cf5ac5fb94043524d02d25033078022aaa6b899e55b64cff760dbf9dd6cf83b508af6996105f232f5258fbb1565a80ac4c735f65c7372bc9463dd2f5dacf98f7c66b6b62dc86b0821ae607223cf46b79ea5344ca283cb22c0902d020eee00ad0d25ea2ab2e160bcf1d951bc7dbd788d01763cc39e008323f0d7871b010001	\\x25081c9790f9fedccd368b2dfdf2bf9dadc39ec7ab4d6fadcb0d24623f814054ec043ce763ae00eb989daa35686159d2c712f0cb08b4be06bc157653f7996801	1654850509000000	1655455309000000	1718527309000000	1813135309000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
406	\\xc7affe84af82078b69b5074cd8e11b7851938602b55b643150e4011e1b3a9ec32dfd4d1dae7f8c297b22a140f89fd1437aafc4f8ebfd159d99abbf5479f5d635	1	0	\\x0000000100000000008000039ea721c70ae91fdd47d319d2677db96f4028d5fb15636a8bedc52bec436d85d20718df1ad9b11deaa5b4c1f861e7ea416b3842d77fffc8e17d453c59e2d05472d11f04c0a7aae98ae1056ec1607c89ed4b98f984a49d62f5666b66af5e6abf8eaf84ec93bd2720b5248db6983f3072446fc87d9f737a798c0e8aea888ea8ce77010001	\\x333ec97e1711f5c22d39c7e07e165ecb80dcb0e2c768d1cea6b83b93dda884c9e2a504245bc6481e671c2d06f4636831d7a442d9e0567550f8af44cc54ec7f03	1674194509000000	1674799309000000	1737871309000000	1832479309000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
407	\\xc817e2c0c4eca6953576635ce450b78adf87a55a6e9833f33631de2401f71e4d822da9fe0df7d948cbef1e07e78caecdfeee7a264b35ba6cd016c28446245bb7	1	0	\\x000000010000000000800003a4b6910d921fc07dd7c941ca58d00bc17d3d872d10d771ffecdc0bb7cfc4b93174f45886fba4fbd73a6976fa4c7c8d6562f74636ea51d48eef3ee7cafe32798af958ce5d8a8199464ebfaca6c917dd16834695e23ca66e2a0e9c559ede8c901d853da7d73e2a434d0b254b40db776b974aad04525b746157e4601f4c4927ffb7010001	\\x39a305883973b1f3b2690b5e8af7547b114cc16ab1fa28f361d8728736843c4ccc170a78e2a52928db1f2230f498d02239a3ba5b0e0cf5e03f370276e96ebf07	1663313509000000	1663918309000000	1726990309000000	1821598309000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
408	\\xce0beae84cb888b10e20e8176e80c869c4d0cca1c8d7813de72eee07d38c8c5dff46918fd7b38bb85b275572924d8edaf3bc2b3ec9bb9262ab30b5c094181357	1	0	\\x000000010000000000800003b3a8edfc34eca5b0295e30a4859d7019a35a40b66257f167c9cc350c3f6eb4b9a956f61028a277cecb0f63dfc91a785876b3d737a59177cd95af0efc9282d847fc003372b10d69c8c3d3d4c6351de07742155c31c5ee5d2531170781e7b1f147528fc7b88a78d5dae115bf0a137d90636571a98dd478abec20d8fcfcb18d2983010001	\\x9862a249faa11ea782224c8549d1e1fcce8c901ffebf3c790a697d6c2f08b12efa4d7f8c752332d58c95ad3f643d2c5b59f06c1217d3c8a8a3f4820ce8f52d00	1666940509000000	1667545309000000	1730617309000000	1825225309000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
409	\\xce77cc9b39cdd16965a8c90e3220860041bf4286151f45a97e6a5d3740931bfc72dcd78bb608cbf4695fe312f1c9c372c63680a1dac7c3af1d2d363e605fef7f	1	0	\\x000000010000000000800003e138d9ea9ad97de60dacff68049a8d1451fb1d793ec30995e8766585d9fbcb3949f5275896a7023a39f504932196dd77cb924abd80c4067efb926432ce6746dcfc982da33469337715d5521eeaa7ef4c08f34f7ba083e082aec70027bca7b3cc29b1041ba82dd254296ce4f6942e3b08fdb35b568c6b57f5a387b4d93ee3a173010001	\\x7fce619c0838d7d7e7080d9cbbeea5199c36777e2f5211f2514aa6ccef6e1a52f5d4bf58cf6267363688430e8a6b7714943d18b00e4458d020d955525361f109	1660291009000000	1660895809000000	1723967809000000	1818575809000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
410	\\xd0134cf8436d4f428213082b46859931e89fce8b1ac9f31f111817e0d258f40963fa82706ac9e6e3fc1fba6d5247283af588a1e37c1b2107fc4c608812547a2e	1	0	\\x000000010000000000800003c4e78f9c24d74d7613cc43ac00e7bc45f2c6da07519fad3661a7e6fee48a05cd64f254d3862aab56c16fe9157d2ac76d333caf2b062f68798c316d1db3834efb7d7da16fe8385b247321ae22d1c210385ad274d7af131cf6aa41abd9771ace6d772d13a237fc8a588784dfdc72057f93275a425b1210053b483b0b1a39da6f83010001	\\xd88b0c9cc066bf557cd8ab522f9bb1f54596b5e81eff99a9ab7062234cd587c0792907b02f3fdc546574d066f2f392b991f801350b3e8c440986f2ce73fb5e00	1662709009000000	1663313809000000	1726385809000000	1820993809000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
411	\\xd2db2661448fe824452ef9afea84e2418654b5be1672ccf1f3f098f68e0622992872f069d2a529e2d2a2b079bda9988ba0ec1fc632fd0c50ce45fd32e0aea1c2	1	0	\\x000000010000000000800003a11f9c8c09f4212781b808748f511078fad123a24e94bc89c6c63bfed89adc93c4a0fbe1df792e476fc06af201beff77038c51cac1a50dfed8225f443539db17f3eefbafa1c554d9bc2599fa551a2c5b9192909b68a6167c61f9b80496715ac8ac2780edf61824904c9493811b9e3e6be33ca68bcf53a5ccd29e30c932c39ea5010001	\\x410ed01b79c38ef17b2c15a7ba41114f53317452a65954f35516ea015db8f3b9fcb0001be6ec5b490eafecf158340f67da5ee6c34e86d9aacaaa133372f6d50b	1650619009000000	1651223809000000	1714295809000000	1808903809000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
412	\\xd4ef3f9e16fdf54036f1fc75b1525edf029beab5c8d509c73afa60e36b5217285b0f3c4b47d6f2ea49185fe24187b0af3f79f1571472763d7ee686c2af087877	1	0	\\x000000010000000000800003e1eabeb76eb4a9808043259df2abeedd3c88df89c09360a0337cc7729a5d7a8ceef8cf2d4eb9276617cdf2a669e702845c7554d512274a5639096aaccc7ad968765ebb288b65cc7e60f2e2729c23493e175b82ef0aeea659527c38ebef325ae25f55acfb6cf001cf52aef46ae4df655a2bf9ead99771e2e3871c21533270192b010001	\\xe508acd3f8b12e00fe799dadc0e44c97f63f35eab23db91d0b5f113ece33c189d8c143566b20a14516d9e6eeb4e6f7a0e47d511a6b4e5cdad3d749c61a64c808	1670567509000000	1671172309000000	1734244309000000	1828852309000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
413	\\xd99bf2c7adf0e4ab3c5558972f850478a7eb1785b13832ea6fe30e77de0b7cdd324e83e9870f056511e772a912e731d7a92b5d134a46674bbcca7652539cac96	1	0	\\x000000010000000000800003c8606f70c2e9fc81dcba136500c37501b834c1d8004c250aa6ec079f41c52f7d30d6007a74e1f3ccbcf19fc3e3d93f8fd8f6a48c6d828214e42faba9ff0f017b9338de0286f033c14cc72477cacdc20c1c409758a68037f839fe23657f5d0221662e3a81f79d0cd5253a5e6bb29ddbcec80789b214aea6d3b07f245f87d9274b010001	\\x72e0d95b1bf7bc1df5e65d05add56aa70d422e8fdfec632226c0586e12e2132b52f190149108d891deac76997aecbdfb99b6a710aab721dc150261def974df01	1664522509000000	1665127309000000	1728199309000000	1822807309000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
414	\\xd96bb30c39653cccc29aa285827286f2d929fd272c7a880598dfd162a1e56ab177c131f46287a6358f3ae035215391a0726b5bd96553bd0ddfe798a571902cb1	1	0	\\x000000010000000000800003ef6a54acc4766e8297fb75a16a2bc82d67ed08e17020d668f392d984f72bea57533b85b060337e97a9ef3c544671fc2ea6daa35e02743a5bfe8d8af228b2fa834e66f56382663ba63a903b4a3758e45819ca4fa60ed3373cb8b5795cb16cfcc1592d00e0811e83085336c270933f68480623612656f998cdd20a0f37a343aa8f010001	\\xfc62455ef84fa8be08a151ae006ff5d3d30f7615daeaf3627b724852c16337aa763fa034f1907ba99cc0809a5746a657109d9eafdf3ed4cf51ae5fd606673101	1671172009000000	1671776809000000	1734848809000000	1829456809000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
415	\\xdc4bb14ae808e1afaf3a64792692396f09366bae1f4705fedc70915eb932548a2f2b78c78166a5b5928c0eece229163088724bad9967215ac2f7d933c18032a6	1	0	\\x000000010000000000800003b861d132ebe22d8fc669dfe06e9021aa08223d4edb818038b82581ebc6529cd06c7e733fadc63e365e801cb4e623c6ca7caff088a4dd5216bca8d76d1ef818df08ca5b7fce90c1b26431f64b89321b86a12c29c589b413beb5bbb61c91ecb4077436649923d87d74e1ec0e60a38bf7f936472f48dce9375666416e16be1aacdb010001	\\xb707051612d618f5b64fca6d5060dfe47e6f8a50e60f344590be669d3f9e8d71e751eae3d308312ed14da35bf04294bcab725c24a45b03466f067d8ff800170c	1657268509000000	1657873309000000	1720945309000000	1815553309000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
416	\\xdd8391e028f9764954904fa1f64318240bcf9a9c5710d0da481b9297c2211250c8248b90da43d20a6078610db51acae2308bc0ce46f1fc99d88b259272797ebd	1	0	\\x000000010000000000800003d17fafe2cb14490c6ec2dcf0160ee400714b5a3b301c5a7d7b3f99b3efc0b83d3d866ddc662ed751b04fb7ce805b61eeedf60409ba4118f12a56fd56c53de118f2373b4600da84f8bcb29e9dea31f21d8afe84a7cd60a628b302518e0cf1df35e8c658fe8a4ead96309d425b1b76f51ca0b161575bba1f405704dba4601423a7010001	\\x11a15d944af88a76c4bdc4ef4fa1980535f9cc4976fa186c1aab297caa748f41e36aac7196b64216857decb6e99c176c25ddedbd5e9e95d7d3f10913df177505	1667545009000000	1668149809000000	1731221809000000	1825829809000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
417	\\xe02f3c4621bbdf0e8c478a2b553188cbb7ac30160aec8f2134b4cb49a2cbf5e81724479e8de30cf13cd1547685a02d176df5d62e92d5f44de15c8371a75f31c1	1	0	\\x000000010000000000800003bbc9de82d1656964f7ae92465190af48044450fa83cf0238330f0545a27b32bf65c6b403bff4a7de80b78c9e229c70d46e1b73da12c0cf223e353a1910a693c8dcb1a05ae3d69511311221a3344ef5877992ae0991cd145de4975108386e8c3944abb82c858dcb175481ad15dd77008fe4ca55fd7b7cf9677d3b336980630563010001	\\x69e3ff6fb1325981a487cad683c12d18ff0cb2830f5723a734f455e855da25a77d34581503b0446db7db68e84282ac199edd3a8463542dd6a07f6f78d017260b	1655455009000000	1656059809000000	1719131809000000	1813739809000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
418	\\xe01f0676cf2a214a157f41a203219cc68e9145a4818540cf11b305027911e174b5fc1656bbbbef383aa86f02545a4279e9a038272c20951c7d7bfc1d35ccf1ac	1	0	\\x000000010000000000800003db977c61b871b68fdb227d3ec02f763901128b1ebb7c1883759d824bbcf32fae4cd5eaa51fa7325ec99541c6178b254981c51ad69295500d0fe03d003ca1dfb37f5105ded0fd0a34ec433a813578a6f0cdc7bd34a3d19ccdb2b49582e540428dc343dd14de5f00ed822d4c19a6a861685182106267ba57826be021c22971ee5b010001	\\xf216bb8bcf9737a17b5518c9d4065f53cb8a4c330450910531a024f60e6a19db07c5e61373a0e762cbf7913612c64f9d05a70c514ece6b173a73d2e63ee61d09	1674799009000000	1675403809000000	1738475809000000	1833083809000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
419	\\xe2e3df867d54b7da796f57a8d3c4cbb9e3f06a194caee491b68fd8bf558b60c773232f2bf41f4561548c0ca7c904a4c220dd4980c1d006fcb93d13cc89644e09	1	0	\\x000000010000000000800003e2811730092028b53c9f7c4fe1bfa8220c72ad7aedec66bb6781d57fe95e4c5609d853c1e7caa8dcea3930ced5a02829a476ee8e3f36455103b07683cf489d5803d273a497098a61e4a694032b216ee4c057eeffec17a2cb0e9925b07a6c0a1edaa21ec5a55feebe3c2950f94f1863a5b00dcf981369f25325f673caa7ba839d010001	\\xd84ba9648daf043f116c6f338a57267ad6071d25456f84091b78683f00c3a7388762b401194600205e93f2cfd3e08f211504450529dd7e2d6786645c82c27a02	1668149509000000	1668754309000000	1731826309000000	1826434309000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
420	\\xf56bd7761bec61b3643560f83679e03dde34f63e499678804640f31aa0de7c68d3b746f1069752e6fbf7b2d20b7b28058370b007cbc0e1b210dedd976d3bff42	1	0	\\x000000010000000000800003a0b0931ba0cc252d5ac2758f231fa4cd942dd17f306d5453ed47ecce954c8779263b4fc2d0e6c1c8cdf3c1a593928aafd1254d71f8ae8b5830486413093de289664f30b2c08995c135545138b44bf55140271978247f4cabdfab5b1e573741fa1f6f93da3ecb02c5482a06efd14a22fa1a8bf9743e3fb6f978b18b93f2065d6d010001	\\x6434455669f29aeac0f1aaf763344ce50d8c3f53f2a1fa4862307002c4c8d69c223ee5358e4bd2af427558cb54a406061aa98522f7ac3c3ec5abd7ab6b1ca704	1674799009000000	1675403809000000	1738475809000000	1833083809000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
421	\\xf8afa03c6ad8dde5e96dc12ce7b6b7022f165979e5986aa7da886cf7ffab8eb563780fdec413d2a7b55e0dbc0f268c9d2e79c8e337f58a683f3a1daaa9bd380a	1	0	\\x000000010000000000800003cf9ad8906ac4f3c88cd44fc30497f4934ee72a663b0bc22f8f5bd15fb9a9dad2b3635170921d6961a7dd43b7aa1b6dfa447faa00fe9ed4b70d06e5fe82e73a3d67c1c9c5a5eaaa442827a184cee523e8bc883b4b44655e31d444cb6b9ecb91e48757336fc94b9776781827de76490a0efa6a37464aceec6e17ded8517d365c87010001	\\x6b816a4a7485bd16cde95c67d3109cc1c38b230ec5537f88cf6eae4c920d8ad1225c65076aa1eef85f62c03d62885c410cb4f01d683bad41f4e27e52931ba404	1669963009000000	1670567809000000	1733639809000000	1828247809000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
422	\\xff57faf4b96bd85f8115cbd9f10dcdb72a34deaa03b4eb1e6e2fb9ae6e449ea8168586ddb76419f160817d5fff7c667cea1cac5cae622dda0302efc2dee158fe	1	0	\\x000000010000000000800003be8e6e32e7b1076658a3be61306f0bdf3779b5038d7d3c8e67d778caf5f819577d77ee183af79f6bbae831c77703ffc2a36d8985f8b1dfdba439e3916a10a58db7592d7982440f35219d2ccb4e664137a43caeb3dd32f39dde4638abf98c987af66de41f6443f3c3842e01c3b0f4f8b1993519b2d37bf275adfa915a37bf4e0b010001	\\x096d7aacaded80d5ca898764728eb121b7c9c50594a3ed00c14200575059f293706a701be3f2400742794859f81291ecb11068a2db04378fcb16514a9ff5fb04	1654246009000000	1654850809000000	1717922809000000	1812530809000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
423	\\xff2bdfb5117d5c38863843fef2429cabd412acd1e6c608a9a60a2dd7276de9694db6822554c41635aa8562423cb6a93f8d3db6f642d9d4db86a4ed371caf9a1d	1	0	\\x00000001000000000080000399ab8e7003d2698ea465b6e0ea6193f847d4a29eaeea30c500291e22edffbeebf07f7baaf0e45f1fca5b3cdc130d89e5b17c896423d15f5212aadaab44e42d6469d37562f31d8d928f7790e931eaac5fb31fc87dfe945b1b9ba76cee75d3f2a03d927d8e60a4a2c8504b6991b56c97e33cdb285de7f26d570d1eb988351c4029010001	\\x1fd329c82e95a064322fe430686fc461630b1dbdd308d3b053e0359a15148922fac2f081dd54c7a963886a49206f1f323bd51c7f4fd77b3bafff0a9afcbabd02	1655455009000000	1656059809000000	1719131809000000	1813739809000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
424	\\xffe3c6faff0233238cd8a589a3a9f80ed76527990a1501b48f0accbb49ddf1f649321daa681b43ec7afcf806c4e84b6a93b60adef11c404039a94ae78497d840	1	0	\\x000000010000000000800003a59a94e3084448324713a27804f3b415e2d09392affb6226efed7d7ec90f7853a1106033b1513cbdbaf6e7e0b1e16cbd08dcdb147267173b7357d20458db8f9c36d9d73d31fb2a4e61f4334ad58b964197b86a5dafb07cd65f4a40773427ce2611a457da0e555ae031fddea40e7185de641f5bc3776a1791b3d72cedad52555d010001	\\x0b4e3c60ee079eeeb92f78baf55cd225519f0849fb62044725661522364b4473138780d0622c9f3ef367167a6a1486526b86d562aca4eddf8ac9e4c555689c07	1663918009000000	1664522809000000	1727594809000000	1822202809000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_extensions, h_wire, exchange_timestamp, refund_deadline, wire_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\\xcb7ad24538f33a8856df81c73588325a6f4cf233320a7cfeb4d70130953c7eb1	1	\\x50447b5de5cb994140ad973d517fee46f46389e529c7c530a7d425a898663e4b69ca7720da0021cb9177dcf39f495659ec93d6609eb4a5e91436aec4542f47f0	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x08958422f7d3f89fbb23a2826ecb415725864f0cdc2a7dfeea151251549df09a295b94fe86248e908bb61cab04ebb859eb65ca4a80a9aacc3c6516cf556ccd21	1650014526000000	1650015424000000	1650015424000000	3	98000000	\\x1fe8eb2a27b86887f0f65c9ce97c613185875a84c36c80f9ecf3aaa353271d8b	\\x1a16d9ed3ccc93d197ff84dfb2ca8b465040bc334b2bfd7e67e03ea9ae49f15a	\\x9fef52b9d7d302e3ed71969de1b26b8a2476f1099206c160b3dc4fb2bc9581695d294f90d153345835cbe9ebada0b580be56d23a39e7183c715f13c785acac07	\\x76065cc662a91208ef11d575ea56ccec98001b70b51b1b1d7f6dab78a9b15ef6	\\xc0203399fe7f00001d79f92e975500008dda1c3097550000ead91c3097550000d0d91c3097550000d4d91c3097550000c05d1c30975500000000000000000000
\\xcb7ad24538f33a8856df81c73588325a6f4cf233320a7cfeb4d70130953c7eb1	2	\\x7efe3c9be5e38024c9a7016b4afc2d1f323dce980e028495e7cf1ffdec3ace5f858a2485395b01f9c558dfa8538eec9747e9062c6eaa7e7fb5f2ad379a8c9907	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x08958422f7d3f89fbb23a2826ecb415725864f0cdc2a7dfeea151251549df09a295b94fe86248e908bb61cab04ebb859eb65ca4a80a9aacc3c6516cf556ccd21	1650014533000000	1650015431000000	1650015431000000	6	99000000	\\xd22a95e0d49bd4b46793cf37f9af398fbf73d0a933eddadf9f410030a9a685b1	\\x1a16d9ed3ccc93d197ff84dfb2ca8b465040bc334b2bfd7e67e03ea9ae49f15a	\\xd967ca7d2e3642f489bdb7ba9c19d6546b2bf1552fa5e0254b9116a8d3cfd2159e80a876455c7ba663ab8d0c57b4bb5cf7e3a5fc091d1099f443036750117709	\\x76065cc662a91208ef11d575ea56ccec98001b70b51b1b1d7f6dab78a9b15ef6	\\xc0203399fe7f00001d79f92e97550000ad9a1d30975500000a9a1d3097550000f0991d3097550000f4991d3097550000a0bd1c30975500000000000000000000
\\xcb7ad24538f33a8856df81c73588325a6f4cf233320a7cfeb4d70130953c7eb1	3	\\x25efb64376333c64521bae84077d656a320fcb6942fbacb125a9aa724256f5e13dd010d24bb5be1c8f0104ce979a0d5c607e09560e0d39b59ec795d3604bf0c9	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x08958422f7d3f89fbb23a2826ecb415725864f0cdc2a7dfeea151251549df09a295b94fe86248e908bb61cab04ebb859eb65ca4a80a9aacc3c6516cf556ccd21	1650014539000000	1650015437000000	1650015437000000	2	99000000	\\x4c36aae18f2099bbd989077313ab0bc70804e6059fe2bae4166f176ce33a7791	\\x1a16d9ed3ccc93d197ff84dfb2ca8b465040bc334b2bfd7e67e03ea9ae49f15a	\\x2c862c72f12abde2d348b07c4e7c4cc40093e36c0e9dc4d54c77fafe6d8e889350e80965e7c33ab0485ddb98081debcea79746aef1666245aa7130f490f96e01	\\x76065cc662a91208ef11d575ea56ccec98001b70b51b1b1d7f6dab78a9b15ef6	\\xc0203399fe7f00001d79f92e975500008dda1c3097550000ead91c3097550000d0d91c3097550000d4d91c309755000070bf1c30975500000000000000000000
\.


--
-- Data for Name: deposits_by_ready_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits_by_ready_default (wire_deadline, shard, coin_pub, deposit_serial_id) FROM stdin;
1650015424000000	640839160	\\x1fe8eb2a27b86887f0f65c9ce97c613185875a84c36c80f9ecf3aaa353271d8b	1
1650015431000000	640839160	\\xd22a95e0d49bd4b46793cf37f9af398fbf73d0a933eddadf9f410030a9a685b1	2
1650015437000000	640839160	\\x4c36aae18f2099bbd989077313ab0bc70804e6059fe2bae4166f176ce33a7791	3
\.


--
-- Data for Name: deposits_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits_default (deposit_serial_id, shard, coin_pub, known_coin_id, amount_with_fee_val, amount_with_fee_frac, wallet_timestamp, exchange_timestamp, refund_deadline, wire_deadline, merchant_pub, h_contract_terms, coin_sig, wire_salt, wire_target_h_payto, done, extension_blocked, extension_details_serial_id) FROM stdin;
1	640839160	\\x1fe8eb2a27b86887f0f65c9ce97c613185875a84c36c80f9ecf3aaa353271d8b	1	4	0	1650014524000000	1650014526000000	1650015424000000	1650015424000000	\\x1a16d9ed3ccc93d197ff84dfb2ca8b465040bc334b2bfd7e67e03ea9ae49f15a	\\x50447b5de5cb994140ad973d517fee46f46389e529c7c530a7d425a898663e4b69ca7720da0021cb9177dcf39f495659ec93d6609eb4a5e91436aec4542f47f0	\\x9ab4814ce2316e6a8290bb79cec54cf37c71b05770d0558b86642a40798c26f9a4c8bbcfa1e529d69f63d5a79ac8195ed08393f82b96d6b59f154bebe56c1503	\\x34251ebe5949ef14a0852961c32668fe	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	\N
2	640839160	\\xd22a95e0d49bd4b46793cf37f9af398fbf73d0a933eddadf9f410030a9a685b1	3	7	0	1650014531000000	1650014533000000	1650015431000000	1650015431000000	\\x1a16d9ed3ccc93d197ff84dfb2ca8b465040bc334b2bfd7e67e03ea9ae49f15a	\\x7efe3c9be5e38024c9a7016b4afc2d1f323dce980e028495e7cf1ffdec3ace5f858a2485395b01f9c558dfa8538eec9747e9062c6eaa7e7fb5f2ad379a8c9907	\\x5b7ffb3585d3edb0884c5e892ff5dedad9f58eed259d5cface44080e4449356ace19b3684ecc0c8d61521498b7726e85fd2ac143e65cd6a4406b7e03138c9504	\\x34251ebe5949ef14a0852961c32668fe	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	\N
3	640839160	\\x4c36aae18f2099bbd989077313ab0bc70804e6059fe2bae4166f176ce33a7791	6	3	0	1650014537000000	1650014539000000	1650015437000000	1650015437000000	\\x1a16d9ed3ccc93d197ff84dfb2ca8b465040bc334b2bfd7e67e03ea9ae49f15a	\\x25efb64376333c64521bae84077d656a320fcb6942fbacb125a9aa724256f5e13dd010d24bb5be1c8f0104ce979a0d5c607e09560e0d39b59ec795d3604bf0c9	\\x5691247517b0f7f5501447c6505772071861c74d35daaebc1b52465eb2cf3faaf7ceede4c12c7c1e959fb8cd6492345811bc9a5f5f32b2f72af99dc03b178a09	\\x34251ebe5949ef14a0852961c32668fe	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	\N
\.


--
-- Data for Name: deposits_for_matching_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits_for_matching_default (refund_deadline, merchant_pub, coin_pub, deposit_serial_id) FROM stdin;
1650015424000000	\\x1a16d9ed3ccc93d197ff84dfb2ca8b465040bc334b2bfd7e67e03ea9ae49f15a	\\x1fe8eb2a27b86887f0f65c9ce97c613185875a84c36c80f9ecf3aaa353271d8b	1
1650015431000000	\\x1a16d9ed3ccc93d197ff84dfb2ca8b465040bc334b2bfd7e67e03ea9ae49f15a	\\xd22a95e0d49bd4b46793cf37f9af398fbf73d0a933eddadf9f410030a9a685b1	2
1650015437000000	\\x1a16d9ed3ccc93d197ff84dfb2ca8b465040bc334b2bfd7e67e03ea9ae49f15a	\\x4c36aae18f2099bbd989077313ab0bc70804e6059fe2bae4166f176ce33a7791	3
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
1	contenttypes	0001_initial	2022-04-15 11:21:49.817761+02
2	auth	0001_initial	2022-04-15 11:21:49.956463+02
3	app	0001_initial	2022-04-15 11:21:50.053829+02
4	contenttypes	0002_remove_content_type_name	2022-04-15 11:21:50.071767+02
5	auth	0002_alter_permission_name_max_length	2022-04-15 11:21:50.083816+02
6	auth	0003_alter_user_email_max_length	2022-04-15 11:21:50.095736+02
7	auth	0004_alter_user_username_opts	2022-04-15 11:21:50.105566+02
8	auth	0005_alter_user_last_login_null	2022-04-15 11:21:50.115699+02
9	auth	0006_require_contenttypes_0002	2022-04-15 11:21:50.118652+02
10	auth	0007_alter_validators_add_error_messages	2022-04-15 11:21:50.129129+02
11	auth	0008_alter_user_username_max_length	2022-04-15 11:21:50.144126+02
12	auth	0009_alter_user_last_name_max_length	2022-04-15 11:21:50.154337+02
13	auth	0010_alter_group_name_max_length	2022-04-15 11:21:50.167901+02
14	auth	0011_update_proxy_permissions	2022-04-15 11:21:50.181002+02
15	auth	0012_alter_user_first_name_max_length	2022-04-15 11:21:50.190825+02
16	sessions	0001_initial	2022-04-15 11:21:50.2133+02
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
1	\\x2237d6396eff1ae91f4fe740c101dad918ba0cd63badf538829ca27fd85196da	\\xbfbb4ee5ce876960d303ccff84438ec931527f9b088fa19c6517036e9493cc5022a84a6472513a0b9319c1ae867922887415606f91beeb15892be1aa0e077f0f	1679043709000000	1686301309000000	1688720509000000
2	\\xc86cba2b75d7167bf83e6f4ec26e48fe5c359db4499ca17730e113cf159d4627	\\xdfe6d925e369850084a6aa1ea02bf3c3cbc273c0d66ebe361d027fddd5e73a24947d147bf5830cae0b05027fb884254c04cf5466f810fa3723e8a3c723cc2a06	1664529109000000	1671786709000000	1674205909000000
3	\\x76065cc662a91208ef11d575ea56ccec98001b70b51b1b1d7f6dab78a9b15ef6	\\xf9448a76182e24366dd22854b3878ce425ba67eaa44f1f727c72a80eb8dc7851622e7127be1e42e03dbd6895e7b10631aa97855a652999446cb9cfa18ced770e	1650014509000000	1657272109000000	1659691309000000
4	\\xb768eb99a977d8e1286e3420f947fd043de9920359fa7b1c35b1719180837da1	\\xe7c86607c2aea54e3462fc31712abc61db20681f1d0711711bd537dd5ef2f2ab72c04cc5308a632ef7b81c5caf75c1dbf7133f368f9b9c150fec0811b5f99401	1671786409000000	1679044009000000	1681463209000000
5	\\x9747fe562ff133a0cade43d25fbc256c42cd91cb661c2aed598551f8eb071589	\\x0b28eda43a141fd0d756d06d39404e3952bc9db99c4c45531a3659198ac05dc74228e817d3a90a30bcc2db8b4578b957d2d01adc030ba45fc955b66131ae900e	1657271809000000	1664529409000000	1666948609000000
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
1	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	0	1000000	3600000000	3600000000	31536000000000	5	\\x3230919bacf1e575e3e6f864c9543c114af4012fd910ad0e9f1c21098f68ca1fc069cb71d5db1533c332ae1a346ebe10c1c8ed34090489ce0076cf9a13411402
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
1	359	\\x1fe8eb2a27b86887f0f65c9ce97c613185875a84c36c80f9ecf3aaa353271d8b	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000b3d2729cf51b76860bfb2462f723559167c9c483d2dc0a2c4e26c855f7366a9360d644a92478ae94ab3913b0a01cb3454a90e8d323afd0a5cc5834a243fbbaa1e7544ed6c5afa2a225e70b12f1c6876b3f2cd49c18754a8ce7083aa580a9fbac798775b4ed46bc4145c5475e0a1da3e835381519f26fedfbf57b3d4718891485	0	0
3	75	\\xd22a95e0d49bd4b46793cf37f9af398fbf73d0a933eddadf9f410030a9a685b1	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000039a41b9dd9b0868a4a57b4c5860e7846f7284f5c3c27236f5f799b6cd6a015fe5223196b2e6888d1032c4a03dab316d1e7bb4f6756c76faa88469a99a8fac02a30304469d68d450fb198bd9b05cf88e566dcf1344abace0c023626d7f34811a788d7f4c3917c4c8a1f5849cd5555df4d1485f68ed8e9beb1c9a8d03761b722aa	0	1000000
6	100	\\x4c36aae18f2099bbd989077313ab0bc70804e6059fe2bae4166f176ce33a7791	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000085abfba9d64405434a0d4515a42e3953e1fc21b881e73ef6cbeb403bfea24fbf150ecbd5cdf03cb34a7c7709a81688cfe32a1f5290f117db7c9dff97c45c21344386ed4a8369114676abd019fc4b0d99e43457b8fc6c3ca27382b2f9a4fbe4250f9e876540116b5f4427717fbc4c8f738d23bfaee54db7a0213463544d73a035	0	1000000
\.


--
-- Data for Name: merchant_accounts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_accounts (account_serial, merchant_serial, h_wire, salt, payto_uri, active) FROM stdin;
1	1	\\x08958422f7d3f89fbb23a2826ecb415725864f0cdc2a7dfeea151251549df09a295b94fe86248e908bb61cab04ebb859eb65ca4a80a9aacc3c6516cf556ccd21	\\x34251ebe5949ef14a0852961c32668fe	payto://x-taler-bank/localhost/43	t
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_serial, merchant_serial, order_id, contract_terms, h_contract_terms, creation_time, pay_deadline, refund_deadline, paid, wired, fulfillment_url, session_id, claim_token) FROM stdin;
1	1	2022.105-03R8TPEKYZ3AR	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f73223a313635303031353432347d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313635303031353432347d2c2270726f6475637473223a5b5d2c22685f77697265223a223132415238385151544657395a4553334d413136584a543141574a52434b524356474e37565a5141324d3935324e3458593244324a50574d5a54333239334d474845563153415234584557354b54563553393538314144415347593641355046414e5043543838222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032322e3130352d303352385450454b595a334152222c2274696d657374616d70223a7b22745f73223a313635303031343532342c22745f6d73223a313635303031343532343030307d2c227061795f646561646c696e65223a7b22745f73223a313635303031383132342c22745f6d73223a313635303031383132343030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22534458443448395259435838474e505a4737334b4232314a4239514d5357484b36383537535a4e4d5457304b3135395746545247227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a22333842444b563957534a395833355a5a474b4656354a4d42385338343146314b39434e5a545a4b3757305a414b424a3959354430222c226e6f6e6365223a2248383257434343364e503452535a4b5a3935534b584447353459383531334a47435059315734424345584b485938454357583247227d	\\x50447b5de5cb994140ad973d517fee46f46389e529c7c530a7d425a898663e4b69ca7720da0021cb9177dcf39f495659ec93d6609eb4a5e91436aec4542f47f0	1650014524000000	1650018124000000	1650015424000000	t	f	taler://fulfillment-success/thx		\\xf851afe1ac9b49fd8a6ab738684d528b
2	1	2022.105-0042WZ0D0GBVW	\\x7b22616d6f756e74223a22544553544b55444f533a37222c2273756d6d617279223a226f7264657220746861742077696c6c20626520726566756e646564222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f73223a313635303031353433317d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313635303031353433317d2c2270726f6475637473223a5b5d2c22685f77697265223a223132415238385151544657395a4553334d413136584a543141574a52434b524356474e37565a5141324d3935324e3458593244324a50574d5a54333239334d474845563153415234584557354b54563553393538314144415347593641355046414e5043543838222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032322e3130352d30303432575a30443047425657222c2274696d657374616d70223a7b22745f73223a313635303031343533312c22745f6d73223a313635303031343533313030307d2c227061795f646561646c696e65223a7b22745f73223a313635303031383133312c22745f6d73223a313635303031383133313030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22534458443448395259435838474e505a4737334b4232314a4239514d5357484b36383537535a4e4d5457304b3135395746545247227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a22333842444b563957534a395833355a5a474b4656354a4d42385338343146314b39434e5a545a4b3757305a414b424a3959354430222c226e6f6e6365223a2232383233475742414b4759484e4431415056574231374a3954454456324e45344d4d574546344259515a42585a47474254545930227d	\\x7efe3c9be5e38024c9a7016b4afc2d1f323dce980e028495e7cf1ffdec3ace5f858a2485395b01f9c558dfa8538eec9747e9062c6eaa7e7fb5f2ad379a8c9907	1650014531000000	1650018131000000	1650015431000000	t	f	taler://fulfillment-success/thx		\\x6a2f3e72187b4b6784fefbbffecfa5e6
3	1	2022.105-02WCWZCHBQKVW	\\x7b22616d6f756e74223a22544553544b55444f533a33222c2273756d6d617279223a227061796d656e7420616674657220726566756e64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f73223a313635303031353433377d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313635303031353433377d2c2270726f6475637473223a5b5d2c22685f77697265223a223132415238385151544657395a4553334d413136584a543141574a52434b524356474e37565a5141324d3935324e3458593244324a50574d5a54333239334d474845563153415234584557354b54563553393538314144415347593641355046414e5043543838222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032322e3130352d30325743575a434842514b5657222c2274696d657374616d70223a7b22745f73223a313635303031343533372c22745f6d73223a313635303031343533373030307d2c227061795f646561646c696e65223a7b22745f73223a313635303031383133372c22745f6d73223a313635303031383133373030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22534458443448395259435838474e505a4737334b4232314a4239514d5357484b36383537535a4e4d5457304b3135395746545247227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a22333842444b563957534a395833355a5a474b4656354a4d42385338343146314b39434e5a545a4b3757305a414b424a3959354430222c226e6f6e6365223a2239375352434b52464e363443354d4b4b5a50415130444e5a364a4a48565846544357583636584a4345595044394b345056534a30227d	\\x25efb64376333c64521bae84077d656a320fcb6942fbacb125a9aa724256f5e13dd010d24bb5be1c8f0104ce979a0d5c607e09560e0d39b59ec795d3604bf0c9	1650014537000000	1650018137000000	1650015437000000	t	f	taler://fulfillment-success/thx		\\x4aa12922f397f1ed19b77c605d66923b
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
1	1	1650014526000000	\\x1fe8eb2a27b86887f0f65c9ce97c613185875a84c36c80f9ecf3aaa353271d8b	http://localhost:8081/	4	0	0	2000000	0	4000000	0	1000000	3	\\x9fef52b9d7d302e3ed71969de1b26b8a2476f1099206c160b3dc4fb2bc9581695d294f90d153345835cbe9ebada0b580be56d23a39e7183c715f13c785acac07	1
2	2	1650014533000000	\\xd22a95e0d49bd4b46793cf37f9af398fbf73d0a933eddadf9f410030a9a685b1	http://localhost:8081/	7	0	0	1000000	0	1000000	0	1000000	3	\\xd967ca7d2e3642f489bdb7ba9c19d6546b2bf1552fa5e0254b9116a8d3cfd2159e80a876455c7ba663ab8d0c57b4bb5cf7e3a5fc091d1099f443036750117709	1
3	3	1650014539000000	\\x4c36aae18f2099bbd989077313ab0bc70804e6059fe2bae4166f176ce33a7791	http://localhost:8081/	3	0	0	1000000	0	1000000	0	1000000	3	\\x2c862c72f12abde2d348b07c4e7c4cc40093e36c0e9dc4d54c77fafe6d8e889350e80965e7c33ab0485ddb98081debcea79746aef1666245aa7130f490f96e01	1
\.


--
-- Data for Name: merchant_exchange_signing_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_signing_keys (signkey_serial, master_pub, exchange_pub, start_date, expire_date, end_date, master_sig) FROM stdin;
1	\\xcb7ad24538f33a8856df81c73588325a6f4cf233320a7cfeb4d70130953c7eb1	\\x2237d6396eff1ae91f4fe740c101dad918ba0cd63badf538829ca27fd85196da	1679043709000000	1686301309000000	1688720509000000	\\xbfbb4ee5ce876960d303ccff84438ec931527f9b088fa19c6517036e9493cc5022a84a6472513a0b9319c1ae867922887415606f91beeb15892be1aa0e077f0f
2	\\xcb7ad24538f33a8856df81c73588325a6f4cf233320a7cfeb4d70130953c7eb1	\\xc86cba2b75d7167bf83e6f4ec26e48fe5c359db4499ca17730e113cf159d4627	1664529109000000	1671786709000000	1674205909000000	\\xdfe6d925e369850084a6aa1ea02bf3c3cbc273c0d66ebe361d027fddd5e73a24947d147bf5830cae0b05027fb884254c04cf5466f810fa3723e8a3c723cc2a06
3	\\xcb7ad24538f33a8856df81c73588325a6f4cf233320a7cfeb4d70130953c7eb1	\\x76065cc662a91208ef11d575ea56ccec98001b70b51b1b1d7f6dab78a9b15ef6	1650014509000000	1657272109000000	1659691309000000	\\xf9448a76182e24366dd22854b3878ce425ba67eaa44f1f727c72a80eb8dc7851622e7127be1e42e03dbd6895e7b10631aa97855a652999446cb9cfa18ced770e
4	\\xcb7ad24538f33a8856df81c73588325a6f4cf233320a7cfeb4d70130953c7eb1	\\x9747fe562ff133a0cade43d25fbc256c42cd91cb661c2aed598551f8eb071589	1657271809000000	1664529409000000	1666948609000000	\\x0b28eda43a141fd0d756d06d39404e3952bc9db99c4c45531a3659198ac05dc74228e817d3a90a30bcc2db8b4578b957d2d01adc030ba45fc955b66131ae900e
5	\\xcb7ad24538f33a8856df81c73588325a6f4cf233320a7cfeb4d70130953c7eb1	\\xb768eb99a977d8e1286e3420f947fd043de9920359fa7b1c35b1719180837da1	1671786409000000	1679044009000000	1681463209000000	\\xe7c86607c2aea54e3462fc31712abc61db20681f1d0711711bd537dd5ef2f2ab72c04cc5308a632ef7b81c5caf75c1dbf7133f368f9b9c150fec0811b5f99401
\.


--
-- Data for Name: merchant_exchange_wire_fees; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_wire_fees (wirefee_serial, master_pub, h_wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, wad_fee_val, wad_fee_frac, master_sig) FROM stdin;
1	\\xcb7ad24538f33a8856df81c73588325a6f4cf233320a7cfeb4d70130953c7eb1	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	\\x048b2043231a4ee14f7945f4ba117b95297cee2819a9903fa76870022240bd2bbdcfc29ebc567893f07e7be13ca9bf71f17a7f64a13e901f34b9100a045c150f
\.


--
-- Data for Name: merchant_instances; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_instances (merchant_serial, merchant_pub, auth_hash, auth_salt, merchant_id, merchant_name, address, jurisdiction, default_max_deposit_fee_val, default_max_deposit_fee_frac, default_max_wire_fee_val, default_max_wire_fee_frac, default_wire_fee_amortization, default_wire_transfer_delay, default_pay_delay) FROM stdin;
1	\\x1a16d9ed3ccc93d197ff84dfb2ca8b465040bc334b2bfd7e67e03ea9ae49f15a	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x0000000000000000000000000000000000000000000000000000000000000000	default	default	\\x7b7d	\\x7b7d	1	0	1	0	1	3600000000	3600000000
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
\\x493e579593b1fc75729ea2b91888aa3de91f4c09bbdcbb4890a84dec9406d12d	1
\.


--
-- Data for Name: merchant_kyc; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_kyc (kyc_serial_id, kyc_timestamp, kyc_ok, exchange_sig, exchange_pub, exchange_kyc_serial, account_serial, exchange_url) FROM stdin;
1	1650014526000000	f	\N	\N	2	1	http://localhost:8081/
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
1	\\x229c408e3b8fffdf59573e5dddd181ab659a01394f1bf89fb82b5508fd0aca3b9b55bafe22b7c6c4120e5879e743cb06afdb0d404090e0e828b2e3874242f700	3
\.


--
-- Data for Name: merchant_refunds; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_refunds (refund_serial, order_serial, rtransaction_id, refund_timestamp, coin_pub, reason, refund_amount_val, refund_amount_frac) FROM stdin;
1	2	1	1650014533000000	\\xd22a95e0d49bd4b46793cf37f9af398fbf73d0a933eddadf9f410030a9a685b1	test refund	6	0
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
1	\\xa0bdbf9256fc69f5cb40821c64dcc0455ba6ae9f11c52081023dccb91ab69fe89557e2e6a9331a8b55478960fb9f3389f98428c26d08b40406346ebcb5a3f758	\\x1fe8eb2a27b86887f0f65c9ce97c613185875a84c36c80f9ecf3aaa353271d8b	\\x3454af2af180fc70ab5d74c2f6b03210e4501921fcfee6181f80a2b3cadd727afc1ceddb792f0a33543bd991f69409b5d357eb3965dd1a3cf37bcb1a903c3004	4	0	2
2	\\x9b42e15302f58bab8a7e56edfadba5b5138beab1f459a89903a7bdd40e7b7f0ffdd9c10591ec7296a4120218e35f316beb45ec7d1aa4101ad4332037df6eaca3	\\xd22a95e0d49bd4b46793cf37f9af398fbf73d0a933eddadf9f410030a9a685b1	\\x858f638d2a47ff261d6bb146746df196ae2a1e4647ba2748dd676787716f3da458142f4437d637dcaa2af2299099be85784735cb604dc6f8810df4bcc3dcad01	3	0	2
3	\\x10594dc7baba5c9e322dff409b08e4cece794c96521e62d5c832dabb2e6f6259698d8c9277dd3889cba0979a2dbc5ce81c86865545902273dfdf16d4475013ef	\\xd22a95e0d49bd4b46793cf37f9af398fbf73d0a933eddadf9f410030a9a685b1	\\x51d960f6ae8055fb28034370e142054e562c5fab94f8b4fb38fc280d3c124212e1af2b38acea10e40b33cf1f46149ff916c25c314a8b4c2f77b02c3c11d51c0a	5	98000000	0
4	\\x84bc42eb47ab15d3e5a7214a40bdd6fc59b25c97328eb7ef8e3360b4b6331bd5ce533267ec29d2bd2b69be19390bdfe5639a8a211bdaa3ed2e8271dd40b4939c	\\x4c36aae18f2099bbd989077313ab0bc70804e6059fe2bae4166f176ce33a7791	\\xa4cc3cceda87ad5f0eac4e8f780df2f5828e234cd76306dc04d405bdcb7ac97a8bade8cfa02de90cd25c8576ff036c21faa9f876605351a9035b346205032502	1	99000000	1
\.


--
-- Data for Name: refresh_revealed_coins_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins_default (rrc_serial, melt_serial_id, freshcoin_index, link_sig, denominations_serial, coin_ev, h_coin_ev, ev_sig, ewv) FROM stdin;
1	1	0	\\xd69a261b9e1079e798a82e305870504358b7fac025cd0e0c97e12d2d87842f5b4794fd6b087acca4735eb6d3ca398605689a6acae4c1667ef52a2b072b56d507	87	\\x0000000100000100b918d41ccd7ca470343617dd38879bd7141ccdaf09618c304890b527858ee73a189304d9942cb6852c4a8c53d9c4a9add8e726f45b57bb7b1bf3a0f0f9b17f6e1781db814a7e2ba488eeaa0a591ab8825322ee1172013802b379ee5bf49b4b7030070a964026806870925ecf694dd5bdf2c804a8f71eed2e2bac27eb15edb5e0	\\x2d2c5804aeaf965f9bd4a5375cf28b472b6246131a24c778e6a73b4d3c7088cd0ac5d097304f0d891c7246de43bf66f1485c7d00673cf8450f919d3273fa286c	\\x000000010000000161da782e9a6c3d3be72d94102a9095d97443026511bdb64a87ddab70c17f6f1151bf281f8e3cd22214e774ae0e64bc5aa29e30fc14e539201ce1855c6ce35f458b79716d6e4a46153056bdcc880930eef1f7366a3af8bc1474de4c4fd6573acea5c6cfddb60c7879ea3cb545ee93fec2814d911acb8aebc5ba33b6bd2fb5f4cc	\\x0000000100010000
2	1	1	\\x76118203763e43f325d10ce99ebc36d8c72af63d4b0e8b46f9d4a8a5a231e7590fff2fa4fa4e905f1216860a82cf1b4796f6b038bc23719456617a2337e4f00d	137	\\x00000001000001003ae998d0cf4aeb8f8ba65eb0092626599344d947a2edf914d8bd599c483b16a21984732c56816d0ab1e6035f9e88f3b4e4bcb1ded30728c972d2f902b46bee1e2a342b3e09e1a5e0881d4b2f5af36ecc5c155ad667f08b32120cb5139bef13c1d9c2738bc2ac49b63d45a0baf23b2ef158e9862a6fc3576d84549c30373a9255	\\x25d44994f48a8ca45642b1a12720d06b143cfd55490c34e5feee123599094c77243aa3905bcaf114a4552a85728723241d1ee642422a17d1ba1c75800dd1e4a5	\\x0000000100000001687282e6e48156890b3edacb741a56c1fe4112dcdf1bfd6f0d5ef3aacc302a35b5cdc4a7dad07302fcead6ecbe7b410d36d6da717636196854d53422b755b8bf4095e294c46c71e9cd3845467e38d1b4ab339a7cf2ef5b675e25b7a9a55c1d7051793df279aab4e919c2207bb7bc4ed9ccf1037689dc0f4e58396d3d69d340e2	\\x0000000100010000
3	1	2	\\x76da3a0d71104afe4ad6aeb1241da408660362ed3407c1101e9fac460c2df13156141f736625375899b643ebddbc7b853f6eb98c3108cb90e26f362e7e46c003	85	\\x00000001000001004a6ed730d6d1bcbfc67ae4d94e40b6ed52c3d4e45ac4780d1eeb1e9222dc9ec01476b5b348a89b8ad6350b3d3d70debe55d7156ade9677581e8d15989ad0a76cd95fb06d9b84c8b3f6abb603f2b70fb15480f06f93aed9cd1595b588455f6b807993957b8ac74581fe3f34b843ad85261cff2a107e932fd9011bffbd694616e8	\\x47cc3ff0f992d4fb6b635334e53042ab9c80f90d2269e43e92e4a89e350f14351851c5513a775669872c49489c6189b2a3ac65eeb318845483c2e52549857c70	\\x00000001000000016e97a84c55505ca5393b903a0ed91954390ea284152515b4206082485c0c4106c6c706d953dff23902cde26c5ca1e1b77eae0a7303c0c004beced772305c2066ac4ce40c87a8ad528b025d61434846309d6a72425332873f396cfecd3c5393886e4784d83f458e54b6496ce44c909614a285507e69b701a480f89ebfe1276a7c	\\x0000000100010000
4	1	3	\\x02b00c6088515261122188a0a508229342ec6c12864fbd23710ebbe7cda4897084a0debef06cea15c27665b68610fb72f3ddbc4ffbe2eb81a8c2d1244757b605	85	\\x0000000100000100a3bab728c3628262ddde909fb7f320fc86d6462f28daaf437d48e1f7b07d1626ce399e31e3a3f73a8013f8895415a4341210a2b9ef720bffec3cb14f58afcff9edfc33dd7ba1a30b6439781fb7f545c55060eeea92ded03df9af5af38a89a49f854ba4298e3ebb3ee72b0779710756a64771b1286afd8025cb0f7982f483ef14	\\xe36d3da0a05c701d9297ad3b61cafafcc1636aa5987b9c52bc8c9022f607fe339402373758f84c25089f2a7b111a80413663775226d0011c0b42b39c0d673169	\\x0000000100000001b337b0943c6a9dbb045be7919940dfafb69f2827b02065a6db68ad6cd3f2869f893226c3b68f23e925e36faabb51677c6485cc59c1b465633a4558411b7f6f3c13154912ca1cb66efdc9ab9e84d8b3e044a6d3959fdbd0a9454b4caea4541286247c07c5f06a5d21b5a84254227629c5aa14228ead485dd555751e068c243102	\\x0000000100010000
5	1	4	\\xae2bb9d917dcbe0e8a2bdae04fbad6e5a310609daaca2883a56f51afc68e30f93c0fb8524f5b5dd2a333abbe008010d255412f5d7d6456a67e98867dbc39db08	85	\\x00000001000001004c63cab34854b472bca5face23bc1f3256d94cabbe7d08c0f62a6cc6381d1f1020ed46179ddbfb9ec2556600fc0bd90131505a269858d7a41c22e1f4ba9020d2595765b42acaffbec295043f569d4292ba7fd82cba4e6978637ba9e1cca28869d545381fdf44b0c3bd20a433eeadab38fd374944bc365a906c9f2c8e8ed754d8	\\xe539475259d0310fd31a9305ec5c517ef634cf80038b1fbae912748a7c305a59bb29486f969c145ac360e5b50ee90f13886d0074a9a566d467e1dd446f4b45d6	\\x0000000100000001af00e5078e9dcf89c75e7a503ef28bc7b67f4fce49f935556c92fc7d82e26f9b6aedb1f806cdeefc0ae9d0988928f129226b7f09cbc0fb741e2573ed4cf09a00c7ca8b4b14dc148a2d84e537ba8686e8f5ed7ded7e98adae42a74d2a4a55cb9b86c1d805a10b2815f39cd38b4547cc0b6a6cfd5e6f3e9a6d857522aed5889485	\\x0000000100010000
6	1	5	\\xcf0895aca62c4034fc52adfd5a467f30da76033cf9725b761323beded1340eb664c39dded88a3b0cd6c7b2de01f464aff463a15715cb787409f20077a00c5c05	85	\\x00000001000001001fe73997b3343dc94689d68526b8f4e95b3a0ff0f67e76d98be3558680b24814734b7d4ff3b69382ef1263d50b55112c298c4ba1c86bf7320309426729301e34295d5aad484991ca9f6b65a0023a3333b1febe579e3fdf5528ee721d2cb36b9e01fbf200ee7dc5ee1a13464becd6b7f3da43754b55c140dde3d232149704b5e7	\\xf3c9b2a106059cffc62295a49c197190342100f8eb524e84f9780b6009cfeb6536ceb020728fce8fecd82bcbf56a3863050978f3f2489d5ff1531fe4a582d112	\\x0000000100000001526ad985d0848ba7ceb16e5d433f3b9d7ca6bc831120f38959cc8feef4ce46e660679a68ae027a4e32cb74f4051cd5dc0eacc661645fa03bf1fc2b73683501bd21f32b7be17aa2dde8a21f546eafca5126a12a891c1fbfeee437706e86d52a4c4c2f8578d8e9f758e5032e68ce47ce1c84189725bcb9d6d962027838f9c19164	\\x0000000100010000
7	1	6	\\x7767b16d2d0dfc1851543cbf12997de92f9dade1bed7a52bd86a17430840564073dc4a78b2e4229ca8e4e6dab191d04054d14c68a0e71d40a640dc5bdfed3b0c	85	\\x00000001000001006c5dbad3f810a4a6dabe853b627a6886be4f61355d5b2a2c155d92b17f5c1f5bd3c8ea3d62ed3b0afcdf99840db11e02cb7d3ed5e95f1fcc1a94b293b6eb1b8aae7b396db4bded54a9ba4f777926f3becf690c37f69c7bfa639bced44dd91837c48127c95c83da873d21a7013bda55f9d44e62b51ee904ac240f948d3e57a874	\\x042a0099ab39ebf423ac5aebd3b6772a9ba658b5d67317fafbbbe41fd0f60ec8b100c47697c018bead7b574e08bb657be036fc791d63372ab7179f4dea573993	\\x000000010000000109cf1f752b011e77ba2e77c86c5592a3a1718fa902ecfccb449ccfea3acd6a9455b00b3af5074750ef6e982cd73660d7b43d250ef1c0fcb7a165898edfaef93707c1566da9984d979a5dfda25a3a02cecdc00867cb479e5f4eabcaeea217c10437496b34dab1dbb4f9f9d19155cf94856d8abb809d66ef2b83398d2fe29c2fc1	\\x0000000100010000
8	1	7	\\x00eac9db544dd7470cf242706ba577e9c85d881ccb2ac404c9b00c014fd63534cc7ddc1ddee30ffbe0b55557d6f76eb5d552c70c1f16705f81c19fe41735e805	85	\\x000000010000010009519d88a3f4a649d578b6e967cd2b2c3ebdf71b7f1746aff37861aff1d70681b195575d70ac9fbd69fb52c9f6d33eb8619c4a00e9826da9b04aeff17d37c4d3cdca5f7649ebc4fc290d1212ef6f1cb855c520365b10a0d66c0f85e1664ff260f12c60fced24cdf851276214a88920d881da23862a8f457cae49402b34fa29e0	\\x93b3088efe2f89d42bf9c39cbbd2ea2c6adf7787f48d282eb7321fc5a79d43c21f31b704c0d44f59980c4b1c94745a27b14fc7765e9600a8397166c0dba2bdfa	\\x00000001000000017f692e52f4d92b247067509ec1ba532f3e131ced2a86bea410437d6d6ef6824437dc47389c9db85b7bcac90552b9afa7bc28ff50b29e52fbb58f6040a02ad4dd489c30634294afe88af91e7636c4d3114377084a13d41dfa40b8df672a1fa0808d4603559d124f5cc6ca93220aecfc700fe81986bba8a0cec1db56791c162147	\\x0000000100010000
9	1	8	\\xfe6af82d178ae37bd510bc95bf4ac4cdeac9d4d26b7ef5f17ff05a7a5a71c62a17db56af0ab6b8e7e4558060c1dece309f29ba5260b338a34688b2c622b2e505	85	\\x000000010000010034f9a58586d94600bdf0e2fd97e31f55ad20786870599cab3b9f8a8c81ce02f3eef6e437cc9f9a6799af6bd52b9369701e4f921dcebe0d30997e087ab47acda9383403b997bfe3eb10458cae9bcc6c4a28744948bbe0311c888fa39c740516548bea625c87e10d29d4fd47023155103fabb3b93492e83bbe271a8a87397bdbc2	\\x7b92f01a9627a318a894d9fd11d1cb53a4e66cac9584b6836f24237d095f5fc2d0493b03712b21b369ed239c615a1d5417e2a791c5cc1b0fd826f60d70cc0de7	\\x00000001000000017c45fe838f2839c4938ae7b7fbebc41b88036f4ecc9286b3ff0b26c845713a691a933c59c335206905dce1955fd3e9c3a0f28435de6e58697aa4f2ad21aa1bc5e16c99262c5914fa135065c7009ccf3d5187c43f746cf3d1d10f1756a3f01de58da7a4c0773b5057d48cb7f4cd110f0b23b1d54142cbf1bd81595691c57b4690	\\x0000000100010000
10	1	9	\\xd3f7fb8a7cba39f3bc6ef598fd560dfe33a8dbcefeaa05c03968a91959a86f6871d964577c24d9777956ce86e93e4c925aabb10cf5b4f3aca8374d01e2687903	85	\\x0000000100000100b28b40b7065ecbbecd2e857cc6622c37ede2116dc087998456b8859824bf5bb417d6607488418d928a6c881a36926da0bfd35e495ecda1fa439b5c48430a41bbc41142344551892c73939287ad3b58fcdc4b017ca75ff159b4d5353d4ade011308e20632c55d7512c8ab33ba12b351e8f48a151b8ab82877a8793b2addfb152f	\\x23fa8f00046c95e442c45a76268604a9f6e5f6a57a2700d49f71c3e12c5dfde07714bbc8158a3500f11235c69f5524e44db88b5f785c85a3a934fad78be83dab	\\x0000000100000001961c2d01288330475f447ce841eaae32ec9201c25630eaee4b3d94acf4c329646ab27c1db29adab350c81d2f1d4837ec346aa22e7f68f48725f6682e9137cd261a3fcb9e3bf7b84a49079db0543267da297af1375c2e441d0bb5d1f230716ae0d03030be3aa188054a88b11ad987b7b7978bbadfef24d9128f51e2b05e2d0d36	\\x0000000100010000
11	1	10	\\xbf2c7b3f30cabf3443b26b74e84d436c2991272f7894a66aa5281f20a4dcace4a7a1c683ab7d96ba79d29809b9b9a168d8abac7436d5b4c59b0b1796e34c6009	140	\\x0000000100000100b86a956480410675205177ecec6c9f641db3634259ac2e978bf33dffc960b77b6ad92cc37d6867ffd8296c6fadc6b5b4703e06f512b79772b8891ab19f5d72eb51f1e3a0f4bc245e855780263f2304524c7eb741e57adac49bf6a58aab13cdb84a548205ffca4490c27e2a4ea10c1a4e35112dbe309aa02c829bf805d0b663e9	\\x02098e1d0d1a739cf47aeef99c1733c76c7fcd3536ad51f70230076fbae221001f75bbc08f53279f0f30b9da5ad3ffd4f9aad1ff98fe2582df4498bc7cfb96dc	\\x00000001000000015636826a38c654e8700415b3a5299cecf6a1960b6eb959fcdc250391dcdc8c70dd871fb0c9ca522da5a602cd8ffedbf1243ad0c743833dda683b8e211fa76c87185316a97904be75329442007cb7d8df0958b5d91847b57e012aae00942f71f08bc19979d8040e843a61bfff6abc8ad57471a41ca7279e30a34176c7b30f5523	\\x0000000100010000
12	1	11	\\xcf0ac21155c21b725dca87d5cecb41c4d7b7dfacd3598dea0648571152123ac382aab0712d666f49121dcd56273d324fce36b3ff3d5b887519c5971d67aacb00	140	\\x0000000100000100ae72c08b30552cd0465504267c58e4dc22dd6bfafcea14d93b1ddb603cf1c1576b3d7c85f6c4af6c8dd456984ac0dd6fe6eb16ba1654245e873dba5b098dd9ed6ff3869f007e4ae829f26a3f4c75f679df44f59d2d902e2638af0b4610dcda7424fa11d7e82fef50b7b0b7303ec5e6610bb40b68c334ed26d80569679557a4f2	\\x48eed151943cf70e1be815395b93277f6549ba3f43e26cdbed6da40f10651a390acaf305bf7a2b1606173d6e2e549b2567afd34c04d2f2b6f7aad52a2cf6dd39	\\x00000001000000013d1bf0114486b2ecee918431a17a4d54a30925abeb4950ef95aa3ee72d0786654f66914d8d820511576224998db695c9c16baf6e72b00ccc550695eb2974265bac3fb2a868312cf10607436bceb0cc35c80ad20e094a458986f894af0174daf78fb9c6c7305c8c28000dddb33bcb84d904a0b889df726b75ca59f3c6e672a909	\\x0000000100010000
13	2	0	\\xa363ff13bb1638528925354bc5064727cfeffb54bd4a721b93b00d97f9b5bc93fb921271ae6cb961caa7862a1461f2c6c0a7f4023ced2e2eff80042badf12a00	87	\\x000000010000010015cec9e64c6f20950f9abff9eaae0ce8ca0ce5509b23fd410f79b0ca36afb12096624d7a41baa3f1e6c38d1290d9e4441d5f683bbeec33c78518b4c80c738e14f2abec2fab41e6be1a72641e4cfa3168e3b402ddcd3553ec068bc32fb5c17d5665c5051df99573885ed1c8e5a1e37b87817eb74b5599286e000196fd26906b3a	\\x862aea15c2fc1f0943a26dbf31168605980eee7368c222912c10db373870d12d120f408933faa323495844c83b87b06e73cf2a8ae6501a9b35a778078723426b	\\x0000000100000001251b477731e3e76060f728fa3b31621f8488927451162172340ac188a5aef8e6a6c411193a5467571b01f7a464cd288fb91d969b23d6c6f28812e9a29669e0e23e8f7e9fd87873e3faa32860f35612a798d2e5952e405480ba0f5700c3eca093ffe838999ff3ec52bc4c04d6383acfa245b67ecb69bae732accb39aff7f83718	\\x0000000100010000
14	2	1	\\x21ad7641c6e371ec86a457ad758358e84df5e41f5c3435ed83dd6c602de23d7c33caf1e9e5c63e2e4a482e01609ff6514f20fdecc7a34b38ae622eaaa2908f02	85	\\x00000001000001004047991510b2b0d59076218c5c6669d6f6cfe15864efeae74ec5ccb2e642c511482af9d156cfedb1772013495485b8afd22ccdc15eadb9731177c2ee9bc868960edecbb595a1da5b72b767f36c53c224c0e52d17bedcc05abedbf07e8023c04d9af9123cf0e0fbdd3552807119f70c086e6e8cda952f66c3ae2bfe96db531116	\\x5aa9e0e7d7ad4fbebf41d2f8830b5b4d61294bfd9bbd910c93f885c7b48ee08257c530ca3b3b7553fbf3036e7a97e8fab79bc48e133bbab306fe2473ba288bb4	\\x00000001000000017e408d248bc0adb4564f36756015af6a6d2c97d3d5132256799e187ee60417f96432cf6bfb63b55b2282cfc907225bde7cd7d19b8ac7c96db833057fe44cbc56ecebcf1e8a2b40411eb159a7bc15eb43148c97755c82e38402a3bb25cd17839a735a961dc2a22983be9ac92e2facc86a3a6fbf8af256f9a7688eeb155afc94b4	\\x0000000100010000
15	2	2	\\x10a7bfff122b11c70bb424546709e03caa8ae419943b60c9c42b824b8c1a50b5fab903b83fc2e507f5f029da8eb685036e20b7e40465ebbbafd176aa6f01cd08	85	\\x00000001000001008acb519095b1dc8f8675c4e0e6906d24f8411d30ddb5dcf870c41b4e71ebbda96300b7763a48497ffc57afa0512a7dfb1713524dc8d59e3066588ed75d97cc401fe97af909a6a0eaeac1fc1031070d4feb5280a6cdabdf608bc83e04d32d1a1469402cb2ccf869ac81491e06ff7001dc0a67841de95ad1ce37483e34f538ca2f	\\x05a6cd2bdc5ab8ea120ee2b4915a0c2d9bb8346527094f84e5c4144a63bd0a50e8bd7349d65fbd2f8c638733b5b3bd58224d9fd80b5ae92bf237893a15d768e5	\\x00000001000000017f74c74ceba635bdf9aab37224da9cdc072d38d88bcdc9b2ceac1d98244772e15a40763c350844857785b199f9e80928c49b8294739e201c02fd0d66fffec46ffbc8110ed44fa01b2342e0d9fc8b965b15a6689269fce0a2f21c5d146a6f68c4d69cdb6273c71d33cb116eac353b9ac8931350e6ca04adf37196eda255be11b1	\\x0000000100010000
16	2	3	\\x19ec1aa62138c6825d1bca7d06cd9c5838030ce53f6e4b432eed800c8a1d58a5418d48f9bb239d09469f55c396c022d49ccce817b1dc63b7bbf3bd6ff8e41b04	85	\\x00000001000001005327dd7147d0d08d19010413a6895cee80d7a5dec5614c956e8bdd04a6e85341e21ab4fecf0c5ff04cf78e721a6dd31043ac431bf367778e6b7f47a815148305f41d13bf600fea5c8409444ed88e3bf5277a118438258e880eb7d8dcb12788c5225362526857fc7db32fef7d7f08f3e3c524d4e96e661f4ee6a40a2ee29ec2a1	\\x4f67ab924d709439934340b75f6683cfacff7c87873cfce717cc94c37fda631ffcb6cf496bcdbb96dcd7311d87e41281b46eb1495fb5141f4d1582956f304e2d	\\x00000001000000016434069ec2c96ac59687ce986f593955141d683551b2f5d0e4f66d3ed60bca6f7edc31f5eada1536466f04a9158d50296bfd2af3115fdc9a65d13f0531740fcac415928954fd758110466fd611fe257505c84dc332a722c8bd5e521c31c4e44ac4d1f90086a052a077d2471a770b9e1c11ddd1fe0996ef54312975235c7de410	\\x0000000100010000
17	2	4	\\x7a54bdd80d7385fe4c32dc02c021df8823ab75393d782383ffb8b71ae3fab3eb83e3fdef414f02ab4a365166ea88dd3631b7022c5d23d4f30c212c857f9b080e	85	\\x0000000100000100b21fc15f6d9f1ba90f5cb89b36b7bde3656852a295ab3aa395c4be24ffd0990269fea1cea197d0721cb367e0b4f09c21876a92dbd397406cd778ee272e45c72e88bc7d4206ed1ce3dc67d9cc1feed7c137f891ecb5b0d6742507feb7e3dc454cd4551018ebe31b1b352baf5b77d1dea3eaa18a9ce89d26f555a5fd0a18b0de82	\\xb19748fbe444974b6f7766bd9000b73c9608f822f9925a63ca214f9ca901f03539f861ff44c2c5f7fdbb832e2a60ecbc55a3a8268fcf600c8342fa4c9203456f	\\x0000000100000001bbc49f21137786fd6bdfcf68767b7bd9fa7052cdab8b013a0ad0f789a5a738eb1497e5862d83c7bf5a7f8d04d069ac4d4dc2e177d39b75e99ea1e020a68020933b36030467006911e77382239ce54474785de6c8e79df77835d0506387b46ed7eb0254893b124c8f6090f56fdf9bef5d555b87c8668fd46c124b4e4aec80d5d3	\\x0000000100010000
18	2	5	\\x3c2f03ee08c487aeb3bcf60a36655dbfccf3232c005cdae12543791304c892412a8dc9db91c45d096dfce2000844a5419802343d8b912388a06f03f52d82ec04	85	\\x00000001000001005667c4b04189564a46cd007727e57d2ed6b3d79ed826b2fd2e84ca06e892b870fa3e3ab995e4c99f5d304083870e2566d1c8c71831746279e811732f80575e40b23b9b102da4908090ff2cc2032b42ff86c96459e1ac3340c4c7da6ef8b450982424e9dd7e28f51832d6b1e615fd745c3f63b21b2f78672ebc36f565c5ff316c	\\x34f47303c39ae46ed557b0f61dabf093dbded482b1e2a23a6061d7787012d73c7445bfd50dc76d3cf45011f2abd28c5691ec184e331544b3ac4d0a518c9c99f0	\\x0000000100000001b23a1375acc2cfae20944a5776b5159ae3a66d1d4d0e5f59c79519b5ed52bf4cd567eeaa87f031a8289f7067f317d1a8df0398ca9707dba3195b39291a446c96c5a7e6854e5b366593aa0faeb07e35b406693c78f6226a0488efc067dc4a1ce3f48a9848764ccc054c3f80dff440ec42b279d79b501d4d60a5e6ffb6eaba7b88	\\x0000000100010000
19	2	6	\\x8d3356c22ccb8a98e27f253bbb32ba3a4befc7053fca1e5cf9e679df9b3c9ae39335494e1e22cc19c2b08fa0dd3c7eb4e0c86864d4ea1681f35b902e7a9fbe03	85	\\x000000010000010009a9d39865797dd0f2114f15deb0a8bade003a1abaa763a094c55ab40e28a1b795809a92af50cd8aeaad45585641a2c61e8fd841702e5deeefe0c1243eb499f4efcb5064f426ab741e0f46eec3217c49041d4852c8266db44cff5fb4a3465efae3ac64caef7c0979034713c3bcb5e75e5667e3d363474099d8cae375cca4144f	\\xcf9e8784057adf97b68afc6d0278d4c9b585a7d8007daab9c0a24dd9bf33c9071be67d85ac9b0cfb7bb29c29ca5f167b50f4b89ea1cd0776c7acf8b0af746d45	\\x0000000100000001afbc1afce9d620324a8b3a1eb76a7a6dc2da1034b9f6afb0850c7af271c98fcefb85ca482d923380387a0c0cdbfea437a599a31d619072e45ad65a454fbdc11454a78d9d087f38d740cf37bee2065539ffde637a810efbcb5ce4d093767c9c4ff169dde011aa0abb2b4ea7ecfe7b9bd79071afcaa73057085e511306b3c58ca6	\\x0000000100010000
20	2	7	\\x8332b31e3025d26690a9b371c1f779f348386f6810646f80a0c76486df1f4f90ed416026b3ff6dbd6c142ffa132dfeb5d6e6262691c73d99ef76d0a8b9a7cf0d	85	\\x0000000100000100c04a12c47fa47ea2f2f7ccf4a97921f99b6372d7f4e4351070465766cce93e45a1b650aeef2a96446e5c9da7e5cca2bf21eec848f57afe27a33920151635f275d087078a6ed04affb516547165bfb7589a03e05058379e883d186d5182b3dfa36bcde8597d68ccfd9c21f33fed9954b7ea3eb3f15c41840e7497c9008dca609a	\\x537f82faf636c7764673b9211983dceafb2c40c4e806d290962125acf0506843aeddbefb3443a896808ff02de76fb4e8d1e1870156ccec0f91772dd0c010da89	\\x00000001000000015c7368b1858f49ca7fb535bf42fe25a8428d08b399cfa90ab6af0a34a2350b9dfd7ac0bbb69f5d4b501b36024a35eca32335107d9ee8a8bf3d4103e64f2ada686753e4a0eb2f5eaa47713a894c3477acee72f3c043e133585cb16ea0ebcecb8eafb7589ea4a50dfc7cc92503bd31d638a26bbe040f8491b91131ecf55040bd04	\\x0000000100010000
21	2	8	\\xb51cf22b64c2a570f4323b2f98d0ac74a6b6ff55d93b8970b288700bac3acf4c95eb1ea9f856d1df74aa39b139d0b420648c39ec67847caead8f0e47dddc8f0b	85	\\x0000000100000100573e52d34192c76a3ec3538e92c860940faa0e58421103a28fa1d207ce0e476945cdca5b549613f0ce035f9c8cb8980e47b548638132556854de1f6b36014787e0852faf39c09708c928b8fbbe66fd48e4fac4a15bdd2b65acd3ffabc2cf0b1ebe3e68ad1a5c8288a47b89ab2bb614810de92074b210fa06c03e1852212562d7	\\x0fdd76a217991f5a09c05335351e7b2901135124b95d81664399a77fd0c891427f85852098694f0b0b25ed6595099498aaa3bf443b2c6903bf8f81d9638a1769	\\x00000001000000015db0d11cd7e82e0d7a4fcf85ed13186e7a482ff216be4937221aba812b6350c1fa73f030f77673f75b50ef1a92ba8420cd30b2d939c99e6cd18d295a0750b89d2eb1a44bafd94edaf573a5ade3716252075c16d5d7aecf91696f13968d16c523e135c0325ac80244d720f9aea20351b5c3814503f4a92000ea6f93413883aa7b	\\x0000000100010000
22	2	9	\\xea16d89e3d0cb7bc7a4ba30bed6088c4800742e32775f3c512616f031c1e2ba45417bdb8a962af14b5296080a8e998e32f726aca0d3021ca750ded82aa29bb05	140	\\x0000000100000100ac0b2af85ed95e47f5e4b21a3cf3aac48be07dd2b2966977aae58be6c53f8e91713ebd696c3f72276423778779b804a03bfe6d2e633fac2168ff16d1b7099435c595df7124f46654c63c503d0b3a3a5038452cdd7286b104d40b9f9e460b2af05706cababc926549629808d37b5213a2f5a1e99dcef76e84c49361feb98b0e7e	\\xa7c61b05820cc596c2dcac8eaa86da29f89dc96f655e8d72dc8a9e425ae9d42b42d0d3dd4dae31d1c4e45c4e3595ce9da6866aabdd135dc4f1e0ba0a01a5b8bb	\\x0000000100000001217812e889d98744ba95d472051d8251e214457e408c6506227c76bf733d813c7b2028f82d65a5355fe4bcc3a76cf7ad455e56a662a2c69bfa6ac6a3333821eb4955750623bd9d33ae694c789ad1b3c57395eef79e7cfffe18d651b4bc0e91c44ba3f449d66c27721d387c9710669c1f104fcbcf767733c377a90597e3caa44f	\\x0000000100010000
23	2	10	\\x60215b434545ff7faeae99bf8d7c88356c0c1949bcb9255fdb597eaccb06b8ae312634ee1a29e8e4906c08a38c482a683fd9d8d2e245b8008a79017e561ea008	140	\\x000000010000010078be069014fff86315d33e7d71cd35b2ad3e50803819267260fbadb77d58bf61a715f63b63f5a1b88dafdbc88567cbe4ed286a2e575e39a081a126cce072e4768f77f7d286ac9269bf608e6b0bc4c1c1d3eefe2e683d5628429ab60b6b480e66a5dc411db622047baa5ec8ce3d2d45363e4e724682172aa88ccb48ec482953cc	\\x7afdf47ccb705ddb61b5abc1a483ceb3f3b500343dbaf56493b109394869b3d4d8103c4566027c2f107668f922c5159468cc41e330ad5a5042302cf15db17503	\\x000000010000000127f3e7aefcef7053e91e0aa67e9b77a8d447091130b2e68fcb65df302614200af8f1f4cf6dfb50da02ecddff1c58f545591cc8bac6b590baa5cdb14ec1cf02f351cc627131b6bd916e35354e74837b099319f403355db27fb43fa373bd7276e81a2ec859000e33687bec6fb207b2775613ac1e9c1e8102e33e93de9166039fc2	\\x0000000100010000
24	2	11	\\xf8e7279f6a7bb9b6d4f540524617805033a50f82c3a74390ead35047a68e24c114fd76a100f59cabb884e9bf6a6b3ad99da78a419203fd52fa8886552a076e0a	140	\\x0000000100000100a7b521537ca025dc2e44ffba19ec6a531ee0af27d8f575f55a30e4c212b8d98a98c62486a1943425599e53b8f25aad6a18b055d02c11fb4af75348e22fe3e2a86a3b4ca11b9af5b63b6edcc5a7490663deee8711294161d92b588b68a4d777b928d79af0c489d15915a4bf09e42557f5234d7cd7d15f5804a08ff5f169d7c3ad	\\xdac78a3a32dc376ae9ab3e506e34ce07b5d5b95e88e500cf4e6580f549138c9a688f64dddf6b3b5c9091bba2af4f40216cde93ab31e222bdaaa644e0c0a5f16d	\\x00000001000000016cb383c33a22944736f457964941a35a5a732c24de185c6da38ea24eb58460ae84ea55c7eaa0f71913638c22ca5d8232bd3964c5d4250c36684bc132345fd3a830d9caec7035c0ab1ad07a10d2e2dbdaf90e8e092d8ae4807db249fc12086b34f57b92cdf4a63cf10269e01900fa35cca530d86d612326c1a6571eeb4e9e3b33	\\x0000000100010000
25	3	0	\\xfa5077ff2d1ab80abfe71aabcb3b23856ea2736b3ffa06ffa971a2f5275b8e32669a95366c5eba04e4a3ac880489dd781d40aa1a5d3860ef404f0b0886084b0c	100	\\x00000001000001008e3a9aae82aea1bcc60b0db16d687ff577098de0ab8f39eaa9a38eda422f04d773b8a3d4bba343a1861799d42ded662cfeaa07388047790f2e53000af174fba0fadcb222f4a3f66698a4aa500c063bb1999a5e4c2741518cf91dc935ff81afa0ac93ca291a4262b79ea707ec50579bf9fedccb4d0e45f5fbb6f2d1370a57f8a5	\\xe33fb648efeb31c949a5388ee3e3619aae5b864c477413cb887e382544da39da6df8b8fba51839d1d08c14e8e06dcbf3fe66bd99ae424a9c5e1430616581f2a7	\\x000000010000000121fc67bda66b77f7eb5ff2311db3f154e8d804f7eba4645776d798cdecc847ca80e2a58b4a8458fbbd7694d39265987995f01c406016172b690db9ccdd0a00b29b57b84514f047df898f0be3824bd44d72986e3c551d9567df497d30cd2d52bf2e61141666f5a5949aa6daa6af8fb249cd3a743d29c6c0c7665ffb3904e410b0	\\x0000000100010000
26	3	1	\\x7e4e2b0693373630a22dc1ab6328dba5e413bd68b51073eec6d700c5e3c1797b4dbd26ce3464c5e01dc77dfb77ca3c89a1e2e29736633ff72853659ceb0ae107	85	\\x00000001000001004974f82546f7bd78abfb3c5964034b23ed585b51613d8d97c72fd0d1622bf0511e38266d1eba803240ab66205034740abf38820b2eafd65fa8de87206fd27de889790bce5ccac07aae87b1d011ed9ad685e3949ff4ac852b5add6082b0135b81993a2bb08861b1affe804b4a46d3eefb443638ce26f19a6b82c0f58c6d0bd651	\\x4206d82a13ab14ad65e7e31c74ff18d87b494df6141680290d201d4e3c18b7316e3a3d2dfc1324810c5399c1d789230257f2633d03cde9e3546d379ee009af85	\\x000000010000000184f3fa1aec80b623afb1176d3308cb4b778a1b5c3f3b76e6a269b8472613eae05d8774430952027054c9103d0228b6437db1fb54049f06802bb26999fd9143a7af2119c809ca7f990082d7283c73c65ad6477838bda8988586d72f1ce759cbef2ebf2f6cb7d56c1a31f7e8a5b36c25b1bb59ae46bac6df3ed3bf02398c0989d2	\\x0000000100010000
27	3	2	\\x3fa802592109ca4579d522f43a222a3aa8566d29b6c7281b26b900f4740337d2c768248296701f0a9999f4d6b2671aa5cfff26d02630cf363dd25171bb372008	85	\\x00000001000001000844d44d7b8d1990dc1fcb24c0e8725eac473189fe917f1316f0244cc80c4de5310f9ca4fbc3319ccb161f0a5a6982fc2f6de60e66c196bb64ecf3d3c815c7947cc5f01a76860f0a670861fafdf42cc9802d2690662fea994c518bc2b2eea986c1d1a61a42c8589afc8a6424da7952eef659422856c423cccddbb59549403c50	\\xe98615080c968f458f8845e49e2e58f7909f8e2a536702eb8d1feb26de22b145183ae0bf8f4e8ab21c482b2d20c2104fc7101ed8be59dc010f0ef18fbbd20dba	\\x0000000100000001afd7574fa8674c751f6174c769e3f6102179c07f8f30acdb1d0b5bb4d0118605d7496a85b06b5c7ce1b2baa69ee25cbc1582b7c4f8d8a76d38bde992ca31108fc50b0e2a29edd3d495c7317436b3c383aa9e4c207fa3f777d9ebf7fa91bb225ca884fa5677de33eb741d51cf6abcefed73597b38b49d14efd25acf4239916a6c	\\x0000000100010000
28	3	3	\\x79653f2a8d79b84a134d859894567706005c0f5475bbdd8328ac77a411a92dd7ba65695021b693163e8bdf4652936aead9e7aae313ee88867591c2cc36ead403	85	\\x00000001000001009dc6452f5ace9ea975d2e413a0f724a2ee1ed3962b5c2035e45471279decc202c7e250179cb210650880701b6f564fef85ee9edf0c196d9914518daf0296cac1568ce162f9a4222cf7aaeb2f10d45b505c252f8677090cfa50e22fcb542ad2c9456c48d66eda1111f13f3346ed6846e3006d03351e8a8cb3dd2c0bc8519fe32b	\\x8fd490381dabdfc5cd5ff4bafa4de9f2aaad1ccabeef61e41ab854224422d3795e5d5a1fa52c34fbdbafb8914110f81ea9380e40cf3087ce63f6e8358dd629fe	\\x00000001000000018b6477d1f866a63c2dcf7c75a63e5858d5a599723e64c17223f1b19ecb44a7bf2f51cb0ca4be9226e70082f64daec49c60fed94792f7b72673802403226359ccf9d612155a3ec8ef896c6dadef861331ab24aeafe638c47f432d4b2d78468e90993121cff402d781d9ef4aabe9328d23fdbbbd5ec9662a75a89608eb096ff80f	\\x0000000100010000
29	3	4	\\xe2f8b1c21d48404a667054d9e9429b7965e0b2ecbc65c8d333b111a46ab7c722d3cc143ca1b7122ad2867c7b0c5626f0df56cbd9463764474360353aae8c1e0f	85	\\x000000010000010088ca3689b0d894d8d50d5b6f58ea002f0575c505824d9fbf2f54bc9142ee36c2e29b478c8d9713ef3a4743d65cf4e4b8f61e5c6a231e15fb04cb7f338edf7d4a0d40b5f3fe2711d39329016c6db2406cf14c2e98313bc999aa3d64c78ecde3496f5afb3701b77fba3d4a67a04d4967bd091a900585ef839e76bfe090ee375096	\\xbd48a2d48212eab1487f904f5dbb2224277b59038a9d4a7992a6f046fe12853e24c5e4cb7f98d6353665b22241ac547e373d0b630b04f47c7f08f9f599922d1d	\\x000000010000000137f5aefe9d723e59f26a8ec31fbea4e0cec5da52b0b475703baf6e1c028bbb22e989661a47181faa4e25cba020526f8707f7331844ef09eec111bd5d82b1e34005e6101ae00451c80e7ef2c54ddccdd96cf1e6d0ede93d1e5e9023d7fde61daca0ccfa4c4db2cb0a24182558cd4e6624cf2146dc2cef72dcffcfe3d84918808c	\\x0000000100010000
30	3	5	\\x26d7a479408e108a3db21edf4f2184567902b918e51987be45433db15caf7627a23962012f6430ba0b7adf9dffaeeed0797e4a5cc8bd4743653426b64c6c6107	85	\\x000000010000010076f8601af098169f81c86d78524498c72d2c929fca0cd9153477e0a367fb859d7f976bb90394707bbaeefa65cbe8d721ec42d88450dc76c010927c80e700b486f5c453e13e0fcffaabc15a2913f0979cb4e17fae15bb675b76d1d11d75592673abd77e4e313a925ca8112670f735a2f7d1594f51c13ebc2c0a5c80fca8e55992	\\x637b7dff7c7227117c3b5696f742cadcc895eb1c45f56f9e77a5972e7a3a2d365143f6535b794efd55c7d54e530b3445c6b2b8172aaa84411d80597713514d7b	\\x000000010000000128923fb2d7be1aede0e6054a29bc557ae7cb233c8f3ee61a21916e123691d480318c0307a2eb5b21ad62a15cd580af68bc1c66281b1fa404f27470be40e46639d6833427a869b1961b2b3b10fac4bac319a643a1a4ad5cda546c8a59f538d2aa7dd8de7b15f16a8a84afd2e43472947be7c783bc285ca1b4ffbd8892407d73ef	\\x0000000100010000
31	3	6	\\xc71e71fa4ec7896661fc78ee6e337bced12e0438c73b0126256631061eb540864fdbcb109c9629f0c721ef9b712ebaa6f6a3be16d42586f1c3295c1a60c4e105	85	\\x0000000100000100a079a852adc40df90459834aae1c90f11e0e40f91a99e1606ef90115b64329020e8ff202c223f89383d99dc85e64d7d76c003215b241295654823963097c7fe518646a195e8c612503ec375913c7388b95e965197d7bde285bcef4fdd6896fef95bb6e1d535d6e3b2db9eba763983e8fd33bfdd0a8c1922cf76b898d0243aa69	\\x39725e7f16c964f7549b59076fed9d5525cc02ef3162b34a11505a87fd758ff3c4ba6ca4da556d7bf5a095b440254659faf0da0b585f129f52021795a2b34696	\\x00000001000000014d89a635e99407bbf8ec2c332dd727247de3a7be6a1e0a6a1d0b0c8bbf4aff5229197ec983e966c7455b114a5d07f81c14a36e0585c4969c017797da0756705bcbbdd5712197dc41ccaf4bb2cc098086bcf3d93504b29c9202f8106fb2b58cf314cc5b9474189b04ca144690a9b3e6b645733498aefdd3e9fb60894de4b3a727	\\x0000000100010000
32	3	7	\\x73f9a04a01593ab26d8030a6b8ee8bae24551721a9ba6577060d4a09f9622fab08b6c78dc91b7587648a93bd1db6448341d2bb66c98b3ea305b6cbaf863ded08	85	\\x00000001000001005fac2e61590472e85d3c6d88d04057dd19ca297c42ba8cfce18f42a691c141e9cf77817e7ce4b69bac39759fb99746bf9b05c3e399fe4d1e4903cb632bcf2b9ca3b0524956129b1cd70e95340fb873e1ac3817bfa8df3465c4d19fbc01f39b68bab6ec0066152a0c615bc286eaa1ba433de376b39f482fcfbb020782bcfe76c9	\\x1e079a5e27a61ebca47f6c411fefab1a3b79827cefb2e2acbee85d8935c53b50c8eb46a1da685512079c4076bef722c957c8dc047191e838215bd06f88b9a0eb	\\x000000010000000123e38444638890cc53351612a03502a0d0bdbd9e4c6b1f1f8c0cbe1cc402b9b252624cec90c317744688c9d0efb034a30752064835a5af72ed160ade7c86475f22f3a346bc3d3190d68a29e241488167fb79cd4f3e626ae0caebb95c504f81f2dbab2e4edcaa1fc0aa2394cad3b04b8df8d3dd4794091d5e5995d94557e7635e	\\x0000000100010000
33	3	8	\\x2d710d7e790bbdf3ad0e68f73d9499200d76982ce0b168ca246bd6977af8414fce0483972c0e528662e8316bbc95ca2ae209bf53407fddaa0d8ed4a9882d4f09	85	\\x00000001000001003c116812ca4cb6e9c457fba18161dbca08a4425729db9806c49d966060e02559be03bbf6f739e9ee2af8f75aecb8b09aa992399decb3fffb041f8ab87911e54a0adefc492ef0b2616ec96eee1fd48691d7ad266fd69715ddc946f3f303eb993878fe346d571dd2b5859ea02b77e27290dfdfeb94d21c62a3a40f415b0b4cb123	\\xc580346aecdc82d9d9bf440c42193d7f02864189a93a14a8d88dded56e108be252863cfa5a6a80d6c036b84c62104369a1093cbc75f6f20fc80969e85de1fdf9	\\x00000001000000018c3be3f18c4b9b222c2796c15eaa7b8c1ab8b1335b1fe9404e725b555cdca3d9402f1db23285185e29d1d2284ab4e9023a602deb33e33955acf816fbc4ffd6bfd648ebad87536d382d20a4171d6b8b16c86f8509afd8c44951c43fed99769ed48cf832c02177f9d0990fbbd5773a184e9eb6a0921012436dbe67675fa189f0ce	\\x0000000100010000
34	3	9	\\x7dea23014ae2516375b3a8434ca78c02ec12414699bcadd5d62a11788f3a6e5bfb22f8822f69f43b9c1ffbf90ec6064c20931298d2286013884b4fab7e3a9101	140	\\x0000000100000100929caa106aa332a794daf2e3cea70260a1dc08ccdcc5f73b6d1f8cb757c42af2cab20012548b2f4b964b2d744ed6efdf94f5ffb3fd30b7b132504464905d4b1d0f2de23fc21235d1cdf8a96751c4f6a63c793b563d525cd109e50363d020530b4429bf8d7d1295c41f4a8da992ff5814c146339e75d275d6a0519df71e1fd0f4	\\x1bcbc61d0ec02953d2735590e1af84a6816e11b28e4853d24408eda18ad27f2220c869f493c5db38fb1aa57535326831fd871b313413c0a32edd8ed98f6ab495	\\x00000001000000018d346337f48cf15052f78044952093c334dc55407b5b1a6a3f287587a2ecdc692bc74a702ba2631831be13142eadd7b2758c411ee9b648c2825fcd537ff68ed243c76f7ef5138513112dadc46bafdc08cb16d81c42266b6d9209e957fdd5856e5af0ea8840e8d4dad24073d6256fc30132b285565a2ed6812ebfc0e37208ec3c	\\x0000000100010000
35	3	10	\\x712afd6d818f9a8e3e7b2066f7b5212fd0f04c5622f4c896d6ab6566a6ba18383fdb146b0508a0337ae19ee492152622f5dcb4f00a6d1014931d4284b7517d00	140	\\x00000001000001003dad7da62828c2dd2759ad936d476d4bed41b3c106bcac208daf3a350faa6d7a1fc1577ba165266759244db9e6990c293a15c834976a8f266c6524571fed6085d2bca78328126e35874da1562c5fa9c9a69fb432d845271efa1d10f51848017d38c676e8e12f34a2b5821b3ee0c19ba95caa82fd2698db79c126ef0c9d31be01	\\x08339324de0f8ec9119751260f0dff392306eb1bcc0b7a921029632446b1bf3d420b303d7e1c1bf042f152c7a5b2b9d751d8c3b3ce3be6f1a68e2736b8dc4adb	\\x0000000100000001aac0432ae8eec6f2451616c8495c01cd14f1d04e2a37baf8c86c5c5182c6ba692d0cdfcf51e939346c0cffc1b2a9afa40ed052531eb0e45b6098a00122bbd7702eeb5d641503229b87cd650476c289eec286f52d2cf641895f947337534b67d421f91fe205c901ebe0b6d47bc84261c8bec81375265bdf1a9ba10c6ed337022e	\\x0000000100010000
36	3	11	\\xdaf649e5b1e599c83d5bd75de199ae12013611cd853953f921c065af6d8c02cbca56be0f223d4197ea3072c8f25de3dabf26818adc26af39de3e5aa56e8a550d	140	\\x00000001000001000ef2a898a09c2bc2c6dc7b3cc7f5f50d1686dff9d7f655c5c00a8aafb71319aca6a682ca93f4f75bd9b39c9fac9e305928dc8a0f76b020253e02595091a27086ed966bf4880a64b379f3478375f7d5711d046ac4816fbe400af02a74ee66549cc406d7bd015851fd7fcfcb5a21a716ab720705b33fde774a526a2be432e24ea2	\\xd30161ba21f52d2a4608c60261ce65327774fa78a83a76e34f38f77642c850f9d4e42812dec656a98e9d8c43926247cf4b5b5480d34d451cd32518a8ceffda46	\\x000000010000000187dc1905e316a53a7de86adcf3bf23e74ba508aba7494eae15dada7f672872cd4738ec7650aa178af409837bd491e633e8cc74f7aea9905ea20fa60d9648dbe5be3436abae72d9f2f03e6464ad008d27908da6fb4f1be0e0a754a5c05ec7ae04f4be0861af89fc1b843551ea1175318c32f08bf1240d70c5c652d02e76dc0d25	\\x0000000100010000
37	4	0	\\xce45dfdd2dee8ff89c2a65c017870c2a7743670bb6f94bbb0c43a3330c43181fe90ba1cd4a9f233ee00bb1a9437958ce34b07134f6b90f06039c916b7293ea08	137	\\x00000001000001008cf3347f750f7140f921666afb58cc3fdd2cebd1bedb4df82b37bed047e7d9b7f2a78ca4065185c4c55e908c345e8cc2b6e4d84eb1103a0521a4a9b857b6016cb830120668236f1fb4055cef37ae89a3437a7c9429bdedc5aa926b70c94ba0bf18dbf3edf1e9075d868839622a61caef8ecdb20f23bdda14a73c0e479523a351	\\x941276b75467e946788aaceea8bce4571bfd91ed980aec38b5ca3fbde51bcad4c327d7bba509c30396656a4627aa0520e3dc0dd3c6af314a1dd6bb39b297771b	\\x000000010000000190e353c35d18f9b401a15727b92b621d828391987b0f63a0df01e0599d9e5b41ec7721d548f9f6c37af8670065bdbed192226a05843749bdc36628ca7dea4aed6a32dfd6b74b1529da7c04284bd26a5bbe29f042663bdabb44210772c1b53f54caee61a2f5ae234e47960479cfd0ba1d79df9e5e9ab2608c11d421fb649a8bce	\\x0000000100010000
38	4	1	\\xa7fd49b50e177472099127a916655eadc7690f9535cba6f5aed45623b374fd1b5de415b6e04550b975c3d209beb98068246b02fc9dba2d2c644ec8694eab8404	85	\\x0000000100000100475d2c4bd2455f30e4d3a7fdeb788fb71e78659bfe553b6e567a527290c4c77c790fd951748c88535a93533efad7acde12ce1333f69d444efdbae56c9d251d50a5573e3ebcb0b1e5e4110c92a8832b059b91bb4a3e319c0b16bfefb1871f45d869fb0f74d409d6ef3a80135c7ba8622a567dbeeabdd44cfa9cf1d75c9b0ab879	\\xdc8d9893ab84b834d9fb922fb901637c1a4cce2078f1f10dfd6c0bcc8895230515640b8c2addf259e94a4748a0018bab00c4b0260eda0ebb0cc0606a1487e3fb	\\x0000000100000001bca9da7c9a680203c04f0f8cad6d7d0015eb59a7fb0d662c83f9b55c1ab2a279dceac14ca3b20bab0a72c07290182cee3168de5ce661145a003bd4abe63854ec4464cb191916221141af28e50edc534fa63832c54fffbc0f5a699045ac317062f21c97b36281e42f2c0ce408b689cb5f4dd48e7a3c698a27146637d4c834d7a6	\\x0000000100010000
39	4	2	\\x011194b6c3839da0f92c9fea7789405f114b16d7a2de31d884f15ae444549764a9c886b0a082793ab23a40071c130c873e3bda34bcf267c7de0a02fccfdea800	85	\\x0000000100000100ad995e6f4276ad6674d3fd03add9a68532d56043948b7e53965e08a99e49b6565d8c3f35476508d2930a2c7ddaefb434d3c7c519b73d2826ede6d1603e7f5b0fe5fade0ecdb10204d40c017d0471969255b379828e3df2147ed7c55bc6953ad95f1ebd1b779ddcb6c598da3fc3c45973c1366f9f2f054d75fffde04ba45657ce	\\xeead2481aef46506c22107fc24ceff8d182b460da7aa7db1144b7d4a0417f384627519317ef75e95369643cde3fbc44dfe99d76fb1bcc17aeabd005e46920dfd	\\x0000000100000001c0afefccf69aac51fbe0e9b8f15a6a5e60af37d61fe4968a008ede85b088599e092237acf834b1fbff438150f7eace6a78c4301481b911393179b8bcbce2e2beff34c86c63036ae61aab23206ec484f5eec8e3bcb0ee103aa51faa1282998e22a8f82496f0813cc4a6b81b6b9fd369d47337349e4ae555a2f917b2ba83a5eb82	\\x0000000100010000
40	4	3	\\xc05194f71f43d8f60435eed47d62a245ed7bcc8d800be3b368f22a8909770246dd7544bc4f9ce7060c317d09c2780f3e70c56b586dba61c88d10bcff98b16206	85	\\x00000001000001007c42df63ca906c607f0494e73177aa95a28ca5df00060d553c5c8b2bc619da3b1f77284ad8de66c7c8a1faf142701687f6dbdc077a253d65a8bd85ce726cdba645105bb3290086a0fcde87e758b4c5fa221a57e85b364312f61ba5d945d79d25cadad47db72ef2f59fbd19e4f3987d54bbff25cf9c98041df40f277e0a86a677	\\xe2dd900914936aa3a89ded4913e0229ab3814aa418ec90ab6e12dafe851395b44fd4e0518ebf7592f87c5c68fd0dac7436312a6eb3ec1c48d2d9486b5df20835	\\x0000000100000001b32f8195061f98725a6d18c8dade86336784f77381e943d8b4973ff084c13164848c831a3866221d1807f0b5173de77cf156fcc81e700509a7f9e61921c012b64b917953c31597ae91536b69151ec8fb719edf9e0187cfec0cf30c8a7359c908f78f0a1c6341d878ee33c84c7b2e2c517c766983df703838b1bd7b2a808d813e	\\x0000000100010000
41	4	4	\\x2498847e7d21dc487a285317c4b42f85b3f04f7ffa7ba6b1a52f024bd5dfd1059ca92b497a31af168f4d4e4f8b7026678ebcbc3f667448c98554a01e96e6480b	85	\\x000000010000010083ef6dbf6bb3d873df850a9228d5c6699054c1b770460c183222b4bac3f3a2b1a5d2ddb7b4a56cb81ba09430140e28b370225f926be222cd9f9888b737b1475e8a09a041ddc2b0beb29f2c84cc64c9f7a7f7553439fbe0d7947fec1ee456de2dfc9bf62f1b6d2a801e40cab8906cdada3dfb431cb003663fdc1868d639fe9666	\\x6331b047b5f8170ccf3457be12ada92c017422b5ce1ead8983742ba79fed1b07c3db943ba1cada84de5d2ad2f89d1dba338a0e6639c6a765fa9a4f7f7518200d	\\x0000000100000001ade50ec293cafee96093068ff0e886672dcb4fb72fb84d3787e66a4b53b292d4d143ac6e4c6f9fab1dcd8caefbde68bcb9b30d1702d06dafb54427b72869bc17ebb1462a341fbe35ee2de149f90b556de63ef486a7a7a9536367745de5b1735c9ef274d20fe972014d719bb704c1f053a9e617bc7b1e96a04bc7cb788ac01414	\\x0000000100010000
42	4	5	\\x4edcf9c235060674fe10b3d7c2133335a45a14ec9e497bd196f290d1f1cc25e60b9b987816599d5f9bfc708dd7c9f72e66aa14da6295185e76c9c1192a90f60a	85	\\x00000001000001002fb45b2d1141dfec3efd923afaadbb83dd94438fdcf6787eab6bd6aaab3129c6244b8110ed87c259f1a781e08992ae8d86545d4397da3ea7b91c60957802390f71bca605f69962b90794d7a23ed45471099a251f07a07a6ff4a746b90679d0e7ed0febde64f4aad2b99b971a18a8a26cbcdb51eadac568bea7c774f417dbf598	\\x8f43b97b3fe43378aa4c0daf0bb7cc694986f336edc6f87bd081585b89d71c9f578c4131b4f803fa25c89cf626e5b880fc882e10a78684e2bd1bfb397caf983a	\\x000000010000000119f23840d85fc5d35fe65ad7849a4a64031271e2cf9471d18b0719653af9765e270e2cf5591cacaa2bbe525b0124770d3c0155cb5fe8cb716ba3f7d963c136fbce5b8415381d977ebff253109a32bd6367dc22a51a9f149f689b7ba1433f1160d055ae1feb89faf28114b5c540912f95defb695d6131a4f0757708cb384d76b7	\\x0000000100010000
43	4	6	\\xbbe19206762956c03ed3811e11d3640dbea49cc8efe00292b3e5d8c398c21dcb009d41616c78c4663ccb35b3cf4b5398f52849a43d421147e92905fad975f701	85	\\x00000001000001003596622dfe9525e84d2e31aa50c849c059b5884bf60206e8afb10480f3b451c69d3fbdf7877b152017c0453e2db0232040708234a8a8ef90d170b20eeea361566b51e70ccc6773d95a935c350248b093ae5de70baab3323e5ad48370c8fb939b61b9f8112f0bc632e17a2e36ddcdfd32b2c08c723bf7799ad6a73f03b3fd565b	\\xa63ccc849e5d5e447e77a9d977d0fe263b6013a9d179f0de7d1ac2347bc3e489fec5efccaf59cd6385e714495141649fb4813c1a4f2eccbe99c90e8f46421984	\\x00000001000000016ad787caacbcb9ea0da0a38a449b50ba50a43487aa7999a58db445edf7f8e917214baf352dcfd9ba1ed5066a69207cb7dd089ce07885cbda659137ccee7866a730cef26c372699d00efe3b7c418d5e3febc8e809b7263e9b36a6b9114abb7b215b69b3fc1a25deb2cd2857610e681a49e8dd7b8b957122e72e81606980dbe627	\\x0000000100010000
44	4	7	\\xa70985a156cad80f996160bbd8b400401c1b58c287a6b4f0f474d2adb7ce42b600d205c6607418f40e5073bd7c2d19c41b4aadc7c0c9c606db77618bd3c1520a	85	\\x000000010000010061ca0288e1e2ad9db96ccdd5160e7ef73e2ea74073803d722aef2be554ddf411cc8a1f20f0b0a43d7d3a4089ae3247ff24611b1e2234e111eec854d8b7e38bc6ebd17f6b19f8b25703a94341cac172802d7d294d48b316a46e5076725937c30306568e1f284dc2735ec0b21c07bfdb09fadf3f7fc7b2df9189bc84c871c6216a	\\x4441b86d68bafb477fdc3da1c701a015a97872c8fef7ea48414cd1b32eae40e7dd43615a6b51bd95a31790c0632c2f662defcc79ae63685a4827657ddec36a73	\\x00000001000000010e40e99ae770502e123aacf1a910b85e24756b97d621c818cd3d9db2ba1c49e73945ac6970df2871e8d672ef3532e5da75a00e13c85371676061c05c77de10043c5b860496e08dda7f92f8acbada727836928edff3b1aae5a2017a60e0c05e859af9ca614fad1ed7f487178801dd1a8bd127184deca4b86466134243eac6fc53	\\x0000000100010000
45	4	8	\\x7a15802352e348d0face21d8d917b3e385279f231bd7aa765ee408236e7cab10adcb051075f6bce00c343fb90229a0d1ff5ad530687a1732bde4320ed7828703	85	\\x000000010000010009dbf31dcfd093886708109170e23cb91a30d9314d67e1a2dcc34f2e57c0b3393aabdeb1c02ec0fd8e100377f70eeda266436006e42631e41ac06b7577c462d2a1c67b6a0d6d6b6a64ae42dbaffe5d20a40c5ef7422cd25a790b99a43656e20652487795d0a979614b18310f44d955aa3fd9f380df99c94ab21b305bdaaa9347	\\x5479944c4f2c83cd5efb16e03f0420d7d6ce757a81d2b6b42404e6660e8772c8ba094914b8e3caf0d20df62254e141e91f977aff74efbd99e2436749e4c3f113	\\x0000000100000001585bff0b750b605e9139113f708b9be41608a7110c6073401a3f4889cc8974789064a1013ceb81198f93e20ab1d81367fe0740c0c107a20263d2159a05ff59aba2e3a2538f8f3bf6c7402833b21a525a50b0d695d92dec59b294107fe71b7fae64644e374f77b3305b785b98b475f459a9fa511380758dcbee23ec09f30c119d	\\x0000000100010000
46	4	9	\\x94c8ba19d6411c9bc74c7c0c2a05085acea70c936c416d72c63dca9f883055c6e8e6c0a2868fb076293ce793c424eb58a78033482e1a07129352dc3be3007a02	140	\\x00000001000001009ccf2a6a92137db634fcdf0d4cfd4dcc00d05d1e15bdc0af35aa9a7b7404a4fd173e15329e6a69f731bdcfc2e571cb330b93bae3cc53fc88b35adf4713645da533aba36925af4bbcd108fd28284ae170cee7bc4d121aadbd15262325f6a70c5294bc2930e26f8be2366c576df21bc322fba151cd023a9e083f4ff490fb592f80	\\x45ea1524d804756395c34f76f4f3b1f71675d22b904af46aa7dae5bffb2e880ca1bd9afb733d197a6afd61ec255fc558c920a8deb29533620fb0a4252f233a53	\\x00000001000000016fba4737ea12360ddfd79d2e580bee5dff3c2a33921d743df39a83b6f565f9f2d8c5001dcd143bafc469a80feff9e91f25474bc8f044fef670a7a3f82584cfb325c5bfc293810cb89b832ce97293c76bddd1b1356c7b83f5a1cc0d3fda29df54de407b344f1af2aa105d03feda49d8300d63b9f1d72e8921e37864893ee2bada	\\x0000000100010000
47	4	10	\\x1283f64fd7051042e919ac84f9c3dfcf0ed13ee40c2028454ea6f8e9ca36b6bf8be94d73936e78e81877911eb5862b8a264ab8b00d3ac513fa8c1af9698ccd0d	140	\\x00000001000001000e05efbc300ac3c7bcc282fcd7edef18b1c4c11f92a873b8b2945940329f003506c2076126077d8c66309887284750d8d6f6f44dc8b17cb83116eb32778a1fbea1ed43ab3437c6511feefa0aa8c05937fbad2c2c881ac150220af5ee421b3e971c6c38b27601db6366da710a10f2ba4289213f353b208118c8147b0bd03fafe4	\\xda975d8cf9400745ca640a0b233dbb3287c4622a396ddf15c1c736cb6120aff33d8ae8ae54d2db5edf3b88e581f130a343ce38334790d0c2ead1f47c2bc904ca	\\x000000010000000128dd0dc7b7d787d69990924c5609d33e6b8cf5f8f8fa311359fc4e5d9f2fd43fac4c2d6513d1c34def06a6bad1ad4982fb33e83cf8974e5e68ce6912be6bc2d0fce46f4002b31e4302b24da296f42d979adc385e0ce562a0ffa7e015510370e46e9d35c9491d746d4e9cf57715dbf6d67b7dc6871442edcd0612fb93d8a2c1a7	\\x0000000100010000
48	4	11	\\x2a3a48ecadf797923360bc80ea2f914fca37c4191bb5c8dd983f1559af7ccd8bfa2caefdd2068af8390a0f704ae30a8294e048b70b814544f27903398b3b540a	140	\\x0000000100000100a58e3614b2b87f13c1b2404ef9dd95841bc8c9f3fe7950bee223db146c41fd13627ddb6f7b0f9f50bd0a2bde9399cb22f0a52447fb8df2de09d3ecc9b350fb793afd8836345f78862b878779b66f701c264954f749c8cf85411ad1d6b81d310f7e859569118cc62a80eedbeeb227ac03cbc32d634b59a4b73ff58b58d7a96b11	\\x2e578c44e66ffd7c39454e7dfe129892a6a63288a807def01ae75c4c9bc50ea790a05fe1e70fbd1b5c4f98f49b5b7533a2576b8206857d91238ccd2b923f0b90	\\x000000010000000131a02883cb53f833a4d4012b37f8198fd9dd4adcb8a9b59fa5693de1361f50019f6466be377ee6c4007d60408fbbf4803c298710078008b86af3b89be50161e6138fc31bc9079a77890bbc7edb867bd7a05226d0b9410f9be4cc6c0f2300c014c166c90238e6b45efde99272ca5633d32fcfa278292ec99b54e4a789259545e4	\\x0000000100010000
\.


--
-- Data for Name: refresh_transfer_keys_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys_default (rtc_serial, melt_serial_id, transfer_pub, transfer_privs) FROM stdin;
1	1	\\x22819b3a7f14c6c42a9275204e45341485cec3dc6331520428610dd816d39850	\\x6f761bcf1d856e1dbaabd57c38a18b9a0107c8f69268b4d4abf2e810c82582745ea80bb8886fe83c99c8af9543c22c292840f41a313b84f62faf559444b01d17
2	2	\\x778d4b8febbe7f4a4870063ca8998fccd598bf659db231a6fcae4e5de6bcf221	\\x4bd9a668f9976315f8a11d1132496efb3bb79cdddb41f05e371a97f50d3dfc31705f9a2ec21c5022cec168c7012b174dc393ea37b4927639d86a75a5ecb44b54
3	3	\\x4e17009279b9ba63e5ef8857742a4265676682a15a8b7cdde8524c4b9bcd9c2a	\\xce550e93c112220d80da7f0df93aaa6cf165aa3e6414c1787ac3d2966781d220f60dc2b4a4b11ce0b3b785a16929a8da0656ddad88e7c3f83374e2ccf46c4bde
4	4	\\x360ec7c03166a39234ff9e10c8f98c4cfd40cd8f0ba274accb31fb0e1b976f1a	\\x1a62770187acdd141c8bc310a7a44bfc99544626eae39725b6959386b68f8d963f20a4c4d178f968fc35576e8084e94fb4649dedc98fe12215adc9b61dfe57e6
\.


--
-- Data for Name: refunds_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refunds_default (refund_serial_id, coin_pub, deposit_serial_id, merchant_sig, rtransaction_id, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\xd22a95e0d49bd4b46793cf37f9af398fbf73d0a933eddadf9f410030a9a685b1	2	\\x124eeab0e6364e4bba5c5ff8ba51a4377526b75e1bbfd30ea7b70dab16036e6ef1fdd23e387f7e53f383e1dcb30f0279831af4c3723776109a8559464ec8dc0c	1	6	0
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
1	\\xd6da76f3f9c55ee0dc89beb45ea03202b4b692a3a0462f42225b70ecfd1f05db	0	1000000	1652433721000000	1870766524000000
2	\\x81722e13080dd1775a9977ac28f981d0872e6af7950edbf3e151de0722c2038c	0	1000000	1652433729000000	1870766530000000
\.


--
-- Data for Name: reserves_in_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_in_default (reserve_in_serial_id, reserve_pub, wire_reference, credit_val, credit_frac, wire_source_h_payto, exchange_account_section, execution_date) FROM stdin;
1	\\xd6da76f3f9c55ee0dc89beb45ea03202b4b692a3a0462f42225b70ecfd1f05db	2	10	0	\\x5b455cb349eab5fe14453e806e92015a1d24d0d671b5bf53dffe196945228e63	exchange-account-1	1650014521000000
2	\\x81722e13080dd1775a9977ac28f981d0872e6af7950edbf3e151de0722c2038c	4	18	0	\\x9a136c369061ba4324a1ef56015bcccbd472b2fc28c47b0af63c679a2498107d	exchange-account-1	1650014529000000
\.


--
-- Data for Name: reserves_out_by_reserve_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out_by_reserve_default (reserve_uuid, h_blind_ev) FROM stdin;
1	\\x4b369bae1316c6bbe06fb2a51e4edddb4722ff539367a00e59bf3d7b328f06e5fdad2ccf3021b6c2a6ab585c64b7f7ca7b97b31be3dacff4c29fc897b6aed970
1	\\xab4a5139c7d23062c63baae3e5bed746fa671b1e7dc087c8cbe9a2dd381bb2653c074510a0b5b647184a092d41dbac48d66a15b6b7f340980e9a9490b3f93ffa
1	\\xc6f1ed8f221483ab242aa9bc7af1d3769b27a6d8fbed391b0766662d3a59bd66baed4aefccac92d082ecff362abafda5292ab46f8e5c457aa506e304fec1c9a5
1	\\xaf3d3d3a6be483f2bf4484756985ccbb8ee34dfe065e98e387d1717cc4275337ddc6fce568e7f5a92f04eb41167349c5a341d08c8f99db8768c4b7de50e677f0
1	\\xa20d3ca37caca28bc9469c4460368640fa2e729e80dbfc5f15c3285a57118ce32bbc486d0cf1cec2e77ab86ba6e9daca34c1e8faa950153be01c43121b2d4f7d
1	\\xf79870db2d9de84f9e1dba992a89df457688b902445f5cfc310d67c3855135bc339c4b87be09be2c9911c193a12531edaa70b9f6cdec10545f73d7199c252b91
1	\\x58f38722b765bff0b2f17a6f7d7e0155ad1c34174d8cf886eac22a66be790991732b30b6c10a2d4e76e570b99a3652c628ad01287f0889c1e056582a1e3168ba
1	\\xd31382649086c5da5fc85b7e9f125a9ef2e88ebb46f1d3967127c4a2b8104b6d54e027072c500527ffbc9626be39a9b5a0c15cb7db86791d9603b5ec42ea0d67
1	\\x0f332b070741d890066e6a1a4dcb39f3600cb8200ea16a5a1e0fc217da9e7c843555ab12cf94666c1f25715481ae5f37107afc77c0ed71f1e642cd86d38ebdfe
1	\\xc3f60b8f3586c3440e6841e1eba546476eda21a463a293a289c908a36c0eba95466e75d544b7c6ad0a425e0a482ca1be9f14967c2d8fad2577b7bb59f54049d6
1	\\x69f993e1123a8dc9b82e7d54712ce39aa65b77dd012f37b2ba7c90e172510a8d9832227eebec07d7f9058ddad386a0bdd75925adda586a20cbc27949d7df136b
1	\\x704a3ed930450d64a6a80f3dcd038b98e6a3c89bfe2d8cfe3190efa13a3c31f2f7f0892c77b65be3a7088a50f051b05d43c2ee3d029db78988ff0bf96f0c2a1c
2	\\x35b8d915e39d3d8442e07edaed5a5d34346a59d3436545679e4e3bdebfe9ec77b4739f6166a259022a5621f3ad11d70ccbf922ecfe0cf265ef3e9d1f52ba75f2
2	\\x01c2e4995413f86490f45f7d50476cd6783541cb8ee5f8dc90cfddd06ebbd0ad0c9bee90a6949eb8c7288c7b29dd14dddab8a79309679ff03819dd0f74e8a14d
2	\\xa2401dc8d922146c6d1dd191de476dedadbd0aa978ea91264966e7bc2b0a31e45b616c87a774e7c605acede0c4053b2fd4a8b704da0a8aca0d558fbe69702e0b
2	\\x37e351497d2ad64cd5c5624b628a06757aaaf8952f08f4fc4f4f569b6f1c416f82ef6d28740eb0ece76b3a4d634545bb0977654fc443d98751d07cefa7062ceb
2	\\x2172bc872b3986050e6e1917975e7c732941c6407e2d83ba31cd82bef7fbe34ad42fcfa27f34da52f30761a8dbdbc37da5f7b17285b9fbfe14a55939186f383f
2	\\x628471b8077b0c2f15c19933de6198f091ff0e7f1324f2cbdcf5477786aadbc51d6a3f20f3c16d329c95a10be382cc40c36b48bbeac883f529f3d5f8ce01e4fe
2	\\x6d2df56d70482d71ece4cea41988eccb8f8fa4be45d960206d1c8de250379d3763c657fe28dbeb6a71b4783c7f625ed16c330325f4961e76176c15159911fee5
2	\\xad553725a1e069e5c3a769a8c7060877ae6e6c57d3d113765ea36c785434f540dcd262c4292f66c0157d1345a489cea6831d5a25898fadfe2bd9ab6e39fc100f
2	\\xd08d5c74fae4c8422d8e34708f9c0557f3897a7300ed7f2b98255b1a744dfbb5a2be591b75bd08eb61415709a1ee1d001c34a8ec58e761fb784281bade14e8f1
2	\\x4f9ddfc439bda39caba2e2562974238b0192a8e32ca18db7acc037eeb363e5ee48644f07abc146dfb754d408901bcc42651049471d08170541c5af4d86e2196d
2	\\xe19875eb38b7e69a668f181276c1c4b6711b92f58543dd225e6fcdf5e73c5d306bdc7662a6bb06e38127e074299e9f4fc5950ed1706d026ec6258c7f532f40cb
2	\\xc9136fa49985028b43604bf290af1c12f6b7860d2f47d674e2cec060ee6d751f496cac2c2a9dd196fd445bc6515a0ffdda5e25513fb8d45d17613875304c1d31
2	\\x27929147455936fe86b18de053eed1cd88aaab69c1993f3a09cf6dced65a2a0cbe6c4c00041377e1a79eb5d570b38ff59fb4d60216ab72b36740be00b03e13ea
2	\\x403ab08c0008c6f2d0f26e8667165786afa8906ffb20e338e558a90030ba92191fedb4427791709881a33e17381c444ffb986298d11a7102611d6b35dd1e551b
\.


--
-- Data for Name: reserves_out_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out_default (reserve_out_serial_id, h_blind_ev, denominations_serial, denom_sig, reserve_uuid, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\x4b369bae1316c6bbe06fb2a51e4edddb4722ff539367a00e59bf3d7b328f06e5fdad2ccf3021b6c2a6ab585c64b7f7ca7b97b31be3dacff4c29fc897b6aed970	359	\\x000000010000000126fc51feafa93ff18adb59faba5e14ede65dcdd98d1bbe826d7c9077c7f56859571529a8dcf8ff0340aca0a1bcd74c3621156f37e25ff11d7a383ab8cc1859026359349eedfc4851791970df40b33b49444c9e544292aaaf31ac4bd3a6986bbe5301b9e03c64cbd4ab765d8a9fd031a012500b00acfbfd542b8a0558d971727f	1	\\xc993a65eaacd71443688a7ee06bd7134cdd1acb55f3dacd0d06be98f6f755db55dd90864cb22cffbeec8ccd241ba46535ed2dec512c29342919f8707301cc80a	1650014524000000	8	5000000
2	\\xab4a5139c7d23062c63baae3e5bed746fa671b1e7dc087c8cbe9a2dd381bb2653c074510a0b5b647184a092d41dbac48d66a15b6b7f340980e9a9490b3f93ffa	137	\\x000000010000000119d9a38c62ba298df64e0033be3f537e688498eaa5afafd16cfa48859cd4dbd18fa1e7eefd326548b889e8a07088ec2e66d06225268b4f5869cda02e874d1e9251347d85ef5fe5141595a4aa9d6b89fa232303cf76c0916c099c0fcc2c52aba73e2b38128a396e431ee8d845462d1961c864f3e85b6d9601e70c881abce1e781	1	\\xa4646a85954d3bb4a407270757464a286a2ccbfce15d4ed547dfa41375df93595f5d50dd63f3e1e6d3f4d3a6036e3a1ed15a679e10d211d57de134b680cade0d	1650014524000000	1	2000000
3	\\xc6f1ed8f221483ab242aa9bc7af1d3769b27a6d8fbed391b0766662d3a59bd66baed4aefccac92d082ecff362abafda5292ab46f8e5c457aa506e304fec1c9a5	85	\\x0000000100000001bc9eafbb802b1fe5ad542d978d9d55e33a23708e3dc31652d51378526db8e2d1600451e496cdcce4d4f59d50ed63041f83e48cabb65e7287212fd099d134ebe2978ff003d8df01a2f71eeb2442f60dc8782ecf46a3b567ce4228493b4b2e283e2e0f8e5a568ce6186f0be9206011887c7fb8f6cf43db3b4b1ea870356f8a6f8f	1	\\xe4d647af0456667dfc80fa2ecd6311f5c92122338fcb097900e1c5a822df9997f295eec681f40863b896c62dd2e1d4d80ed24d1536607e11fcea018f61ece803	1650014524000000	0	11000000
4	\\xaf3d3d3a6be483f2bf4484756985ccbb8ee34dfe065e98e387d1717cc4275337ddc6fce568e7f5a92f04eb41167349c5a341d08c8f99db8768c4b7de50e677f0	85	\\x00000001000000012713d71308ec9a5db870b08be519e8a95e718fca755648b86ca726a5f0829a7b7ae6f3991b525fcb205b410213e5fc30cdfe9c812a4bfd71530721d15480b05248bb3d82deb51a8d2f3645dc54b1c3cc86d4eb5608f36950dfb644fa5e3ffce5571b024e54a8a5cb1f24b18ea5903f66a6aeffdeede705a90bcd3870b0bff9ad	1	\\x5c50d371dacf29a50934f90809f47ae0602c65c8d5c11d8e329c1e27546e40f32a876b7387f67ae86db62044dee4dd53705e1eeab0cbd0d3f9d0bf6a9643330f	1650014524000000	0	11000000
5	\\xa20d3ca37caca28bc9469c4460368640fa2e729e80dbfc5f15c3285a57118ce32bbc486d0cf1cec2e77ab86ba6e9daca34c1e8faa950153be01c43121b2d4f7d	85	\\x0000000100000001a300e158218191e9d6309a8d6ea04b46c71bf589beadcae18d3ed05d45761b792e4e5fe63ee9bcc74ec7f4499cd7a29989a97e3e45826a1d444821779574631ec5e17ecca933296dd77afa3df5f71a3b19ced2056a14a42918cb6340d3ae4b3ebf688adcc6b78d090533d015661597449a9f79698158714408368009dc60322c	1	\\xa71d1bc30e587e6170a9a17ccd2158c1cc5d44089d456304d45191fcfa2800c416ab57d0c4d8e18b285d2cf8e8c4bfc25ebd0f1b57dd27ca92065d1bb8aaf904	1650014524000000	0	11000000
6	\\xf79870db2d9de84f9e1dba992a89df457688b902445f5cfc310d67c3855135bc339c4b87be09be2c9911c193a12531edaa70b9f6cdec10545f73d7199c252b91	85	\\x000000010000000110674ace9795c8836859115f56f7e6564aa6b8e03bbd7af5e29f975c79bedad1260eefb0c6907aa9001d46b89f45c0366b491827953f2baa45670a554dd0b724fc0fd1b743efde22245c71f6f9ee851bcc16c7561896646c440d3a5a8560c803b6d7e9868894319551d5fa26fb1f6984a95fd05bc2b301815715d471c44bbbaf	1	\\xb065326c869a62cb79eda64c319cb47007f5a01bc4fd9feefe876b566dbf9457c2c6a72610a8e37507c9e9bb2a70b6e1d8f32a833983f50f0aaa0c017882650c	1650014524000000	0	11000000
7	\\x58f38722b765bff0b2f17a6f7d7e0155ad1c34174d8cf886eac22a66be790991732b30b6c10a2d4e76e570b99a3652c628ad01287f0889c1e056582a1e3168ba	85	\\x0000000100000001ae2b9d5e14f1aac82add69cb5709c0d7d76587dc4d450f632ea879dd1e8b3914ca3bdc65e2638e309085e0af8460ee335bfdb98d5cc579fa3a412851c0fa3225e2e4804613ced9508a0163e7588e5eeaa9530021246e09a259d60577407624597a72baf505dfd15f5a1175a5eaefe29333f74cced0dad1d8b8755cc0f020b8bf	1	\\x3ddbbd463f7e34848a593a42c68558c493b3ffb8863a84207b8efc13df90f8ca2140b506505c81931ed7c8df6f309cb15aca2bf63c1d044d9514cc27fdd16104	1650014524000000	0	11000000
8	\\xd31382649086c5da5fc85b7e9f125a9ef2e88ebb46f1d3967127c4a2b8104b6d54e027072c500527ffbc9626be39a9b5a0c15cb7db86791d9603b5ec42ea0d67	85	\\x0000000100000001b0342d6473b2e4791e94a9353090eb965edd3131dc1c524b22f3fd4babc894a9d411153e1cdedaf55476742e72ac6b80888cee85368221e276e778615e22f0a3ca9cc3991e05bd993b9ca54c2022fe5a945c53da60733a96e4e74e5bd94ce170f846b525db2a45a3344c7bac5500fba60d049568972ee112c49798896f5c06d6	1	\\xa83454ced9c509a5ddc69020795e7d255ddbd6f9c9356b074c7fc87f20b77faefdd52d60b19385c68afabb8e7d14a03c699154388e60dc5d64315d7752edd50b	1650014524000000	0	11000000
9	\\x0f332b070741d890066e6a1a4dcb39f3600cb8200ea16a5a1e0fc217da9e7c843555ab12cf94666c1f25715481ae5f37107afc77c0ed71f1e642cd86d38ebdfe	85	\\x000000010000000110060bccade21e61c7c71218859c7aaa0d38c828838c19d3510d98b0a2018b25a7743295a7aa22db1fbcf775c71bf6e497ad7a131118bdc0f21bde5a0c54b3ef2f5fdc7a0c7ace0e4646cea2b1e468a9f7acdffe27a81c19f280557c0a9e6e1f52f7cdb2f97fcd3c82449fe2130a2544eb41f4898daff1bc1f769633333f724a	1	\\xfc373db5f4e6357bec7feb0a3591e01ab03d095ed89afee4760457e98d2e27e765cfc9ed875fdefeb4ba7a0de3a6082619dd97453838aac00998aaaeb257ca03	1650014524000000	0	11000000
10	\\xc3f60b8f3586c3440e6841e1eba546476eda21a463a293a289c908a36c0eba95466e75d544b7c6ad0a425e0a482ca1be9f14967c2d8fad2577b7bb59f54049d6	85	\\x00000001000000016d21e0916e7279ef2e788a48ea02bdcb8e48944641b41afcd0d7c7e0504e52f79054ee077c3475be9a34bd021a8f9ea44707884888e16e755dc350d2c70e14c8e5c441073d82ed75cbb9ac783c8839b5bb5840456b5e98bb11ffc8a868324b6b7b9fcc664a52cc41ecce75c6ba5163a70e594ae87e67b683c3c55623f8d4a079	1	\\x7fda082ffbdb9c19bcf0eb69f075138e41ea7548ac8a04c9bcd35b226bbaa42d313c77cc6cf4280e318bc438a395a812ead319acfe300d20653a56a86340490a	1650014524000000	0	11000000
11	\\x69f993e1123a8dc9b82e7d54712ce39aa65b77dd012f37b2ba7c90e172510a8d9832227eebec07d7f9058ddad386a0bdd75925adda586a20cbc27949d7df136b	140	\\x000000010000000138c898eb1a4799eca29df4c99eb0628645a856548dff43060b71a3926159ba3056c4f8b111e97a70a942280d53e8446b5f1a3dfc0f67407c9d824ddade3d3f392b2c1fceb325826c37179ba2ce86641d14b68eeb071bf8074ebe7097d146f39e8de7f79a3409ee7a93b393e2de2159132e738bb973d0fb4fc4ede6fdc54023e1	1	\\x7d4280ae75b2eb590a2861c78f4ef98a68d903c73e83b7ecd1c8fadf01d1815e6c875a4cfe0659e15c0feb7d36780b77f4a4b5e0364166560fd9528b40b1d708	1650014524000000	0	2000000
12	\\x704a3ed930450d64a6a80f3dcd038b98e6a3c89bfe2d8cfe3190efa13a3c31f2f7f0892c77b65be3a7088a50f051b05d43c2ee3d029db78988ff0bf96f0c2a1c	140	\\x000000010000000148f0ad303604f3d5ed2fc82f2093c93f68bbf559c1952e1a773ebaf5fe869695ea09379c7578cf1081cfe7d80a0c240a7406efb2b7bcee2d7b5626c89c955fb1ccd4e37719991428cef008092630b35caeafdc0a364f586ed087971efd5f7b272c790539f5b8c33dddf52058b6b55c53066fd4df24dacd8189bfda8a3166c922	1	\\xe601e8867317489e9ef7d4345c58d36b848e3639a7ed421e282e007a263fac108744252f64cccfe69ab4238ae3a00efa973f72ed1359e91183b31f7c8c275c0f	1650014524000000	0	2000000
13	\\x35b8d915e39d3d8442e07edaed5a5d34346a59d3436545679e4e3bdebfe9ec77b4739f6166a259022a5621f3ad11d70ccbf922ecfe0cf265ef3e9d1f52ba75f2	75	\\x000000010000000197b2117bedc07c52e25d92918dfb482dfff670090231263f3c1058ceb240bb140d22e0ed53704e81f53880f86641130ae1c41163228eca942e05c9d65b0865aa7bf2f5c0f243a75901d878ef5ee2a700b9a03f7578d84ebe31c3275e0acce8dc6bc5c810862e555265e1518a34e6b1a8a029bdb8409694bb321b3c0634507d45	2	\\x0970e0d383bf5d69cfa52b19230a4687eacb3ef45ca8d5229fbf8152c90c2961dd56bc9ac61737f68a8f9bf43e2500ea75826a357232e5358e3ba7f121f3ff0c	1650014530000000	10	1000000
14	\\x01c2e4995413f86490f45f7d50476cd6783541cb8ee5f8dc90cfddd06ebbd0ad0c9bee90a6949eb8c7288c7b29dd14dddab8a79309679ff03819dd0f74e8a14d	100	\\x0000000100000001b0d63dbe451ac7dabe0472cf239c4bd1a01d7221c506ed1bf7b80336eb8c718f374ed19058df950cee7a30414a4891f5250e70a81f1870367443dc80ce78efe8c403bc5547b286b92a1b995e7d92788a500dca625c2328c50d212579c4d5b03d3c5c5352fa63b3e54323257c56fc4c9206c52b1f1732e101ecebc5600a45b251	2	\\x632e9f266751a2e3bb9b0090752fc783fea8ff09fd06b981d0475f2b1a9be5284ea229d1cc3f5de6f1ff6a60acaa747905d286f27430aa10ecd99caeea855400	1650014530000000	5	1000000
15	\\xa2401dc8d922146c6d1dd191de476dedadbd0aa978ea91264966e7bc2b0a31e45b616c87a774e7c605acede0c4053b2fd4a8b704da0a8aca0d558fbe69702e0b	87	\\x0000000100000001439705b785d31aad2b51f7eba78967af8a570b682759a6e76569f71544d43dc9405e26fdbfcae2b48dd9a4b8fc315c0fda37736e0fddcf3a88bdd655023123c71e0f225ee28f63742d02a2e02df1be6f7912e44cf0a8a5778485be1b88e0f894e809c3a3baaa7a09864824ee8dd12c9eff536132ed493b0bb333aaa52c04dc05	2	\\x82c305974470e7b54a6bfd648fc4485fd4c16dd856490adb8fdfe19f4c0c150a0ad1aa64f2a901b53bb1efbb5a1c71635128f63e6e51e4d26e8387466b330805	1650014530000000	2	3000000
16	\\x37e351497d2ad64cd5c5624b628a06757aaaf8952f08f4fc4f4f569b6f1c416f82ef6d28740eb0ece76b3a4d634545bb0977654fc443d98751d07cefa7062ceb	85	\\x000000010000000103bb72587559053c170af76a70ad52e46b7f3f2c7e7179110a3642eac7d44e80bd6fd2c90c126b09a78c83b0c924b9f2dd254f2b17aa42acba7bdc4dc254a201530ff6ecedf8a9173c93e518b0c6ee81c56ad3fdfeb853900503e84a550a99bd196b8563789416ed157449e0ff02fb9465fe7980492b46ef70cc0eae36c3ef4a	2	\\xb5e086ee2cf97eeb14a379e7f9e093f6969483154208ba370997cdf2cfd3fda54e3308f2a40f577d116522b2fa62684ecc981db9cbe5c564d15a8cf930b08f0e	1650014530000000	0	11000000
17	\\x2172bc872b3986050e6e1917975e7c732941c6407e2d83ba31cd82bef7fbe34ad42fcfa27f34da52f30761a8dbdbc37da5f7b17285b9fbfe14a55939186f383f	85	\\x0000000100000001beda641e7ab8f64d0c09bf6018fdcd8e77cb393593e8e105fe05e395c7a33bef030ddd0ef1726db7f432a86536748892467d9e39e6441d1d219b284e9c9e4d42fcfd3a74762568501da3265cdb252ece47d7beb99e3d2a95bd644f9c2f55583c9ff15d60b722fa5ee7c5352915749705f4876752507d48e7c478f3c28f2073fb	2	\\xcde011b373434d7b985849f5c43fca0aa1445d8a05c707aefa8f79fd04f8c1eed2ab9d345961803d2778fa77027044cf5dec9310677f9a9858671e7fb7f3790b	1650014530000000	0	11000000
18	\\x628471b8077b0c2f15c19933de6198f091ff0e7f1324f2cbdcf5477786aadbc51d6a3f20f3c16d329c95a10be382cc40c36b48bbeac883f529f3d5f8ce01e4fe	85	\\x00000001000000017cc17a0d3d8e6e7b50c38ad2865ab99b09cfc9c6912efa5565cbca0dc7e423d6f91ef4279684ee2a7c5c4e956758e1d0f4f715157936770b8819b8ae36a2fb793e6c0f3fe6b6177105086a9568ae01045d2b8684f2f384499b79cf160a2a08949685e8779ba86530d586383a2392c4f211c7a07fb6d1072fcff3150ed400cd79	2	\\x25919a14f2d89b7edccd1023bbbf9fda4a376acc02a060a16b0f5bf8c02082273d2f267774cab3328e4bb3672807cd8733d5707bda98a747b8e582906a82620d	1650014530000000	0	11000000
19	\\x6d2df56d70482d71ece4cea41988eccb8f8fa4be45d960206d1c8de250379d3763c657fe28dbeb6a71b4783c7f625ed16c330325f4961e76176c15159911fee5	85	\\x00000001000000019918dc8802e64ad36ac4a89560bcfd7a78578660bcf607a9ad7fca2c600bb630b099f652f7f931a11586159135b67c5949986b32cf3b76a006a44e77e7149443974ebf53c9ce31ef4936c7af1291a63855329b0d2e549a66c3db2d675fc9f74601ae66d649a969367e0360dcbb51f84e40638373ff8ea91cd7a5a0639bdd015c	2	\\xde42a1b857de0f1e3ed60c7466e98ef04cb727db53a9e5d23aa3fd4dd6f2d90a40eb364060c7cc4300122b4bdb9f182f1c8106470376f8092ade5161e5e3560e	1650014530000000	0	11000000
20	\\xad553725a1e069e5c3a769a8c7060877ae6e6c57d3d113765ea36c785434f540dcd262c4292f66c0157d1345a489cea6831d5a25898fadfe2bd9ab6e39fc100f	85	\\x0000000100000001936ce5e7cb3f434f18a9bd5a2315de4db711beedf233f7d54b2992ef1b1364270dd81c654ae65a2614b8f60c206809fc18389df16fb0a2289dc0a616722526aafc2f18a1874dc41d81d797fe815f82a81e013c8bef403da49bb5c33272b13bd5df800f5aaed9bb7dc953a6c846046cded0ab33ee8128f8ca0f0fea3b5b140a91	2	\\xa646016889766bb119a6827ad7f4a8cd6d16bc510c35074e00c3f3420b5909eb70004f8d60e41d771eae3412cb0ff6a0e99f1a80eda1d58ce3b00d0429f38f0b	1650014530000000	0	11000000
21	\\xd08d5c74fae4c8422d8e34708f9c0557f3897a7300ed7f2b98255b1a744dfbb5a2be591b75bd08eb61415709a1ee1d001c34a8ec58e761fb784281bade14e8f1	85	\\x000000010000000102ef96b9334b914341f0887f7d6c7576c8df5f91a4a49eedd9707b9665f49674aaba3c489038d72a011efeaa35380c4c2478e99cbb02b3cc26d997a9a9cf2fdfde1d905523fccfc86151506aeb1339685547a7bf823ea0e6da95133e38ea2bf565d371e5086fb41d92079fc923f5e1fa638e8a46b8cc127ebe8217a2179539f8	2	\\x64b2bd93685ee26375c56f819073d62c2c61445c3174b950e54a0491622b777bd2f6061af7350812aa8898a1134d7a25fe328273791b683c57b55254fab1a00e	1650014530000000	0	11000000
22	\\x4f9ddfc439bda39caba2e2562974238b0192a8e32ca18db7acc037eeb363e5ee48644f07abc146dfb754d408901bcc42651049471d08170541c5af4d86e2196d	85	\\x000000010000000106916e466ed61915ecfc31b11f8ff0ce2c4ea00a81f2375fbc45da4fe308d528b067c2a39022899f686996fd27031f0e376cc0b92890fc8d91c2986e6910da1efe353cd1944a35485f42720e2f87783da64eac1da2a68e74be8574568a8052ecb415b60a37222a94a1f0fb74e7b8c06a43ae201e57b1c8319b5141d3899e1096	2	\\xb63ad8bf8d18b6e5321b6a312ed643cb427173f1877c6c834278fec751c2bb36423935619a4eee573fd195d1348ca9b2226dd0af988d81d9699d554c1686ef0f	1650014530000000	0	11000000
23	\\xe19875eb38b7e69a668f181276c1c4b6711b92f58543dd225e6fcdf5e73c5d306bdc7662a6bb06e38127e074299e9f4fc5950ed1706d026ec6258c7f532f40cb	85	\\x000000010000000135be524465fd912d76812d43dd5532ca998064b3f7b789b1005744b0cf7f8391d9d3581782de854915074872a08336db230322903186aa7136184a43bc4863beb967b2f309a296eeaaab6785d9d7a5e8773174ce7f6285b411735430d9b5421ed0830b8eba3ac9c4abb419542e667f5fc42667df827717fc55fc9e55f220083e	2	\\x9efe65db26a830dcfeb7fcb0097a0d213ffaeeed6a1fc72ea8e525c97f363edbef063256b476be63a0dbb39a9f564e8eac7753bd97c32e13c9d1a34ef2f7a904	1650014530000000	0	11000000
24	\\xc9136fa49985028b43604bf290af1c12f6b7860d2f47d674e2cec060ee6d751f496cac2c2a9dd196fd445bc6515a0ffdda5e25513fb8d45d17613875304c1d31	140	\\x00000001000000012eb990b48c971a719dfd76caf6d7f142649a4073768259924ca70804ad1dcca87e872bd2cd0a9f8e6d84ab35e0f4ad40b85af926dd9de54732b3d3d62f3481fdf6c7951756ccec8f452d3e96cc9f061708522cd9e534619de97c4bb4e51c846204bc378354f7ac39510658238cca5e2683d3046c6c5894e64fb5fcaeab97194a	2	\\xee98a051562b22db19bfbd049ed44b10f0fb34334a7fd5659baba4f18e2a074cab43c6a7d24c207b802cad80a79f405b8f40fab70ad3cc6744658ca1aa9abf00	1650014530000000	0	2000000
25	\\x27929147455936fe86b18de053eed1cd88aaab69c1993f3a09cf6dced65a2a0cbe6c4c00041377e1a79eb5d570b38ff59fb4d60216ab72b36740be00b03e13ea	140	\\x000000010000000154bcecbd6350f622d714b6f50a4ebc14ccf492586c8d5b2f27102b89ca349544a11df58dad84ab4a4e282f286c60190896d13f846342d9c9378ccc14b6e858699c481f50e44cf48f83d3fa27a3e4a276979627b14f0c155ecf63ac54316b99800b5a4b3d5834a7203544236a54da45c0b5bf862edda8b0ee2127945e908ca19e	2	\\x0b55bc5c772199483125e03d7781e418d65e6ba934a412814d8fe395e7c768ae97fed49f29339847fbbfb13886608dcd18aa7b492893b20aedaf36a67ec8000b	1650014530000000	0	2000000
26	\\x403ab08c0008c6f2d0f26e8667165786afa8906ffb20e338e558a90030ba92191fedb4427791709881a33e17381c444ffb986298d11a7102611d6b35dd1e551b	140	\\x0000000100000001c1a32030e3fc725ab479247c230e4e770a8e871ff0d7a4c69cec6a6a65406ca3e772a2a410ebcad727c8986a7b23d93197a386eb0abb77acc442982e11aad4eee56230d3c8d26fc007f74b7a0411180420a64c9776fe3216acbc739f67dd6677ea490edf548906b6b985fe84b6b3c0898db15a6b7371c7b363dac36cabadc8c7	2	\\xb54464ad59694692dcba5e9edfedad1b18447954284811103cd4951f6849c17a99e3ababb49b515ec498ce3f4d1c9867798d459e188ea61320949a9848d7cd0f	1650014530000000	0	2000000
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
payto://x-taler-bank/localhost/Exchange	\\x39b31f2995044490135097f1594a240d820a6db843376ce7488ea19807f23022088cbe3f1a32d686a662dc6da77fd0911e803c1aa2e05a23ba0ac4ff774e2805	t	1650014515000000
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
1	x-taler-bank	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	\\x048b2043231a4ee14f7945f4ba117b95297cee2819a9903fa76870022240bd2bbdcfc29ebc567893f07e7be13ca9bf71f17a7f64a13e901f34b9100a045c150f
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
1	\\x5b455cb349eab5fe14453e806e92015a1d24d0d671b5bf53dffe196945228e63	payto://x-taler-bank/localhost/testuser-kk2uckk6	f	\N
2	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	payto://x-taler-bank/localhost/43	f	\N
3	\\x9a136c369061ba4324a1ef56015bcccbd472b2fc28c47b0af63c679a2498107d	payto://x-taler-bank/localhost/testuser-hkqg1f33	f	\N
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

