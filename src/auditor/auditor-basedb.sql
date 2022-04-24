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
-- Name: exchange_do_reserve_purse(bytea, bytea, bigint, bytea, bigint, bigint, bytea); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.exchange_do_reserve_purse(in_purse_pub bytea, in_merge_sig bytea, in_merge_timestamp bigint, in_reserve_sig bytea, in_purse_fee_val bigint, in_purse_fee_frac bigint, in_reserve_pub bytea, OUT out_no_funds boolean, OUT out_conflict boolean) RETURNS record
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- FIXME: implement!
  out_conflict=TRUE;
  out_no_funds=TRUE;

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
exchange-0001	2022-04-24 20:30:05.360247+02	grothoff	{}	{}
merchant-0001	2022-04-24 20:30:06.209493+02	grothoff	{}	{}
auditor-0001	2022-04-24 20:30:06.721353+02	grothoff	{}	{}
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
1	TESTKUDOS:100	Joining bonus	2022-04-24 20:30:16.591195+02	f	c33ecd37-25a9-48dd-8319-319160544510	12	1
2	TESTKUDOS:10	FC9NASDVY4KE4R3KK0P211WMXV7X9A22CF7F7WVWWQETKQFWSXV0	2022-04-24 20:30:20.090194+02	f	4daba822-8d06-49d5-b69f-9cc5bb2b2aa0	2	12
3	TESTKUDOS:100	Joining bonus	2022-04-24 20:30:27.028146+02	f	bfe3914b-9a7f-497a-b612-f9e712892bbc	13	1
4	TESTKUDOS:18	KPGCC893AXTJ0EYQ31M9768BBK3BFJEB0G71C3VFWTWAN7A60CX0	2022-04-24 20:30:27.688807+02	f	0f664770-cfd1-4406-8f68-6e67e3cc8df7	2	13
\.


--
-- Data for Name: app_talerwithdrawoperation; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_talerwithdrawoperation (withdraw_id, amount, selection_done, confirmation_done, aborted, selected_reserve_pub, selected_exchange_account_id, withdraw_account_id) FROM stdin;
cf6e4671-0018-4257-afa7-977e7b88f92a	TESTKUDOS:10	t	t	f	FC9NASDVY4KE4R3KK0P211WMXV7X9A22CF7F7WVWWQETKQFWSXV0	2	12
05813b66-f3cb-47bb-9783-9153098226e4	TESTKUDOS:18	t	t	f	KPGCC893AXTJ0EYQ31M9768BBK3BFJEB0G71C3VFWTWAN7A60CX0	2	13
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
1	1	15	\\x73a7971fdbc434dcab445593d3fa7f0e2b39f079b774137c7f500d2a9a3477c59b021343cb69376a5af866c0cf9709ec462db3e6e96140852175afc47aab8f02
2	1	85	\\x01b543d3d620231384a80a18132318b231edae5fdf56af4d3a6c645fb9137dcd526f42d8508f018d2911bd4a6eee2629a3d585027d1a203ccb7a68a87c9c0101
3	1	355	\\x9cae591dd3da1aaafb6d510ed675e8475c31524770be2371076c3e68691de3b4c0a4a4ac32afc2f20fb251ad32f3d62e2af4dfe6280c9d41e14a950e34de7209
4	1	197	\\x2993055e9d908ce0a996605338425a67c26bb1831ebb6bd9c9b79d2ea26692c84d12b9d97bf8620e33505ed8061721b64f05bb72117a26f227c8ac9e9c148402
5	1	289	\\xfac46bdc818e7888f7bac077df40fb8f8e8562ba60be57dc83f730c3cfe23cddf37ca99443061bb726cc82c1dcbdffc467be9723a866549452d5c52da8105608
6	1	44	\\xff54beb9ee3094625491cb4945850c8da0ae7debbe764e816b6e26562761f5f1e768c963ce13d08c9f6b44137d5223c5a20552d349a02da7eaffdd319aefaf00
7	1	180	\\x2b1e0d8046b00d3f2fb113b69931bc80ec9728be55600b0c50f9898e838a3a5371e68de6a20437756ea9ad1cdeaf40999bc4f5716b87c9425d59644417b2f907
8	1	381	\\x532fc146d26fd1460215cd20a7e1d002f764699c2730ca548df9bab167afa3140f0f53155403f376c7bee3b3cc5f783f3e01c6108bec10f0789303d84d3c7e01
9	1	124	\\xb4b1ec52627727dc9fa89e1a45bae269f114a466fd90e3cee4ca1fe4c2861ec11dec0b725031519d94b545d0c70fa53e0c9482f2d96db7d2ca43d9ba6fa38003
10	1	122	\\x6434e2a726cab172e8216e44a6674403a4f571c486c055c71b15446230d24928568905d486f41dc673783d2b625566be94b8ca78321a6ac879ce84dfcdbaf908
11	1	357	\\x898f8dbbdbad2194641b8a99e3737069df33add2b9e6ee61388ced34b06829f7a77da1633791e4df457905adbf8b0b4f5141919211c4ee696c5357b2f1641107
12	1	380	\\x5fed13db25496cc85d51b7d2cdbab86d85b7ba058619db6cf95b7bf5aca925758a8e8c34343361f388eb067efea538a9255293a0538e7c4d61fb6194d501ad03
13	1	97	\\x226c9da0ef1cd3872d7b8256ed346fd9ad90e8bb588533463f052360b0ed9d31b274e99f8790e9d6641153d15678fe66966080a081f1b0bc75be05bd2def2d00
14	1	119	\\xa5e761fe2ab7bbb7d862438d282abe70657313667a7f7043ea20d9a13315bc78148b3592192fb104ebb225d4efd5547c1e73ec9f6cd9af11459683afa3f89907
15	1	30	\\x5988d9ed6a0e506d20619321fc87b7665a2546a8ccd63c3c20a91784286772e702b8ba28f6167912b24a34410aaa119e499546ee53e820aa3e53397fc92d5904
16	1	146	\\xb44d531cd87ab42dd549f45b9b361fa484337f486089206d5e6a39bd1c4f07b232fde762842c2904ebd3e906de0de6ea872ccedc5a86683f0f4b4c29383d1a00
17	1	205	\\x9efc5e22f0805975926cc6d4e81d9ef27c67da61c8871c2387f3a904dd14bab6bda649df523102947e5e27fcdd34c2e4cf9901b0e6071269700973f85e645f04
18	1	366	\\xb87bd1fe7b7d128de6cfb4259fbfca787b38d45f1ae2d7752e7df162349149a3ea70d4e5eab1d556a643e3bd85ad8ee7670f9c625eb71745fe9bb4ffb02ea20d
19	1	229	\\xe1ccc89eccaba2217bf40d3f242494462a559992dca672b10bb477740cd8f1f45f7a578005647808fd6031f2b47d9a17a5b4fa20bab10a7222abb95cee035a01
20	1	1	\\x044bcaace5f9047b8e24ea52fabdb289e16f468e84980a7e43669820f6aea4b9af0a85b0b6fb452562a5279c5aa87e5a58eba74874b2b42fd1b0ddb6c21ff709
21	1	239	\\xbff6b6b43872eb4376f7380a132e6efa15a415a99f679a5d390cb438ef95981aea33cd1ca01e3e026d27f2b632c23dda45bb7d546a7d681daec4288dc724eb01
22	1	285	\\xa4c6acb14182800e9071220e014ecbb0989d21e63c9db8276d72bc8a49c50a51e9bef6d2023e6dd7781cd48bad2b68dce0b4f621cb3294996863a42e3177ea04
23	1	318	\\x158e4d3babdc171076225c98a39ab652f32204fd94fe6d5f8811d696d28fad4b80a230a943c71c2eceb76c4fd3fd9228ff9e446813aee2dc21a5e6cfb9101d04
24	1	334	\\x9212f4b09687d61fab1e7274c8c65528cdf83bd0b89ebbf050c8255f377c575861e41d3d24093278e62cb9b13c4b6592168bb0914998505139f36f155c712801
25	1	297	\\xcf6f2f07b391c37e67a014ec76cc9ca22a318c55cf45038d5909ea5f45b893d095dc729e283593c28a1a28c09b2a1c21bbd99b7e1a2baf8a250386de1704d60f
26	1	234	\\x2de98df977274d2830d86d768e3e263027be2ef7441187c9a48eaa668c0e96ae569fbd65a6d6e74d386008cb1833970b295d7bec279e68426a458ffa5f2e2903
27	1	104	\\x4b3c7794babda401d5d1c43071cc0af89e64570fd460fa12db14aa961292e4df9be39d98b3d07c229a60cd5365b5ae503388d780569038d5da829f86f8125305
28	1	390	\\x80802ac38caa06ede6da630e48082675a6ce08a222ab3b869edeff69f42def6078c90aeb27429b748d7f0c803f0aba516ad2a53e14c775730f2affd168bd550e
29	1	320	\\x5c21d28aa01d351a20dcdee6bb92f8ab102b2efabd8f2f6d6691e15854b547ad924a860d50f1773c40cf44acfeffe0bb59cccf9e85d53892b68a3b02ea94b601
30	1	223	\\xf2e6339b12e94ec1dfcf4ad38c3d643f03448e34c268a14b12d1b46860610c2e17904e2493331081d8fd31df688e2a96f2fde0b93a5320a30204c468ac9eb30b
31	1	134	\\x85856b748425b29501e2c6257ea4de869b46f07acc3107b556ebeaf541e0387ba81accf551699c152b228bf500cab10a3f5a25dc5d5770f5206fea2cddbe9f01
32	1	367	\\x59d3b0dbbcfef9db876b994a3c9d06de03ffa04b8088e082460a8a11c0407a20307b50cf9b1abdee3eb39c2790389cdf3e2507f3b51b0b6f4c2e3ee941c4980c
33	1	199	\\x8e6d19d505474a211e3c81dc958ebf9c814d7f872d1977e0d749901c3986c1dbe79c222bef87550e05a1338990420123cadc4154c93b8be4311d977c21e8860e
34	1	29	\\x6baa4380cfd159f6b6cdb52092153abba743d3aae4b89faec9b046b8880e448ca2d631ad15e26cec6570780dfef8a34dfac357dd94d933516fd5cec4a829e601
35	1	117	\\x539a7429fe9ab4be3cbb9d8a0657069a572f16323dcb2e0ba045b987e830396a701f27c35c8a930ee4ff01295bf05be47aa8fea64fd3d39d45faacfa9fe75603
36	1	397	\\x08abeb93ad5ab343519e51443279ada0467d8eabd19f417d169329d27149230cf484dad034540e3b5e01362f5cc7c7f54fc1c89fd05f57bc8bbc34bd4095600a
37	1	154	\\xad7f8ba72d7983b5c931f271492e936bf9b396f0b245df22d0661c489d9c33482a72002cc5673cac2b89994f50ca83ad53ecd58d2093fda1d880443f0af0cb03
38	1	166	\\xafc44d349c6020c243f64da10bd155a53b785d1d4188d6b0777449b8622970fd6bd70348d4c848e6872f67827404e306f0b52ca19b12eb47ea3b589e936b630f
39	1	404	\\x66da36c7ea164bb58b096bacca3c37740a44c9f8de1cee80b2295f17036a619cbed5d16fb80ade520d8f2010329488854b2bd1f1ae349e06d835b40840c6040d
40	1	209	\\xc3f42868fd858c2257d68458a283f504db7a13a922c28b1eb4c8d1dede46c0c843db3cfde4affdb370c6d401fab1c48c22a77a569f35bc517fbc20fc8a17380b
41	1	91	\\xf81889ca0eb6b284fa92aadec5e02d72778fc5629e1bbc559eb5a2017ac96f3cc094f2026f9fc3d5f31f976121e2fb2c24480d92275b84826611245f7f2f1d02
42	1	414	\\x6d63649e678afcc715f992299453b4cb5573818905fd64835923b393b0ee38907b9486a18c632f8a5693b3d697ccc6f6f5ae092e7c15956f2886315ab6dd4e0f
43	1	46	\\xc56d6cd8747d10ff3204f264abe519a5565626ccd49c49b2c2bbbd24109ce7042929cb25b4078ad3263ca6adcaf6021161937a7ea1a4f7909b2aff8e8a18790c
44	1	290	\\x11096ed42199b3b21632b2e643a47ce29201496e02bb27f1d15753fc161f54d0258e8345a67b66c1b196a099d775a152a560176b928f4ca639b232f89165d70b
45	1	77	\\x5ce5bdb56baba37eac1a1e57a6cefc0c5d4645132b3ccf6de29c5f0ca25dec6833fdb498583928ceca1b2944c1917edae67b3ec0df8f8341c8f65855b9c9b40a
46	1	246	\\x17d1e1d42c454771dafc98b2278aa08e9238966bfb5f7e24279b1dca71321a02e1d543bc8fd17b02cce23932ef1c09878e8bac2031be91fcdf3d1da1eb146a0a
47	1	306	\\x6aa5be2237a06a19a8df04beabd4b0febfe8b015424282eb44eb310466837842e994a78c1a7f51315f338cf33cf0f84f5b59d96d84f46a897a91b39cc02a0b09
48	1	185	\\xfa6d372370a9f59a9b3c7f272520ab16d95ddf904eba1a93d289b239ea918f69e676c2895e819c0f616ab84ee53a4c3784f09c371e95f0ce2e612a5c7bcd7601
49	1	99	\\x3a5ea6f7e21e068bd0fabeebdc73f93a462597a83a115effbf3a6cd1a336fdb1362de6ae94611fcf47b6fa5feb56990c5531bb916269c2e44c9e5989af0e790d
50	1	7	\\x72c71c0b7340c36f1a8338c97a95b54eb79a30f54113c7f77080cf1f129c3cf0cc211d9e78a337985690fe4d7d9ff9b7d371cb98d11242ea2adc1900ea21a701
51	1	237	\\x4e58b139907b30c4c67b5294348144349b7b8ef6c67fd2dc0c111dd6ac3efacab37d89eaf687b1349d46eaa51bce9d1dc219269ec67a1bd0a640fe657e5c3000
52	1	385	\\x8cbb8a0762f79adf1ad206c18486f1aa9e6b90c548ed88e3e73a9a406410d34b236d81df77f6cfff306fb87bd2c94b508b86959050e0e8babc7807ebefcebe0c
53	1	326	\\xadfdd73e22c06948778c78f4af16588d0f34b7b4b5b63adb1ebeeb572ef22caf8f4f67b64f7732ae7916cc98ea9d9e77aa6d0d58ba5f1622ef17afd3f310f90a
54	1	95	\\xa6399920afd627f22292e726e246a2d2aa392a67c29094be30fe20702625c799354b76c07d14ac45f2c8e9de36bb8021cede3c967742166d58889eea677e280a
55	1	192	\\xb8073cb37551d617b534bf25d0868bdb2337754b6ccf88f3de699fcd561d5b37a0ab9f1533aaafe6a5d76e3f77f98e888b3c2baad21aff0b29d601fbbc90060c
56	1	259	\\x570299c1efc3caadd0a4648a256b7e8a538fac8cdf1d1ed4eddb098e33c902d1ab6b7020562ef0d9a2075dedadf96a8b412774bd765014ad3d778ae3338f6802
57	1	244	\\x07767ddd87d32fa2acf83fd29f857261f250991e7ff59a1a1f0c6e0d1c49e71f2654fa6ef33826ebda53f77460898baf405e5f7f9c8c0b2dd07f0882c184ce00
58	1	413	\\xb342a52f9a85ba5e316cb04bbf786a9a840b5951d18ecfc92d299d037fa2dfa79703ee94c1a3a7be31d7d404232e4bf35fdee2b2e9248b5ede707bb28d006402
59	1	260	\\x50d5dce838ccc79b4a3c821eb94c0f759fd5c7373d11176f79de940228df05354a443b9c2a9f55d929588b502fd500b802595a5c047b7631c11712941d9a1a0a
60	1	313	\\x0fc384cfbf7c9a9c55d1e4d118cc03edb758e17ef344d776ce36a4d9df22b1d7143dbe6ee563c53d5152a0e95c7818a3c6e135ccbf42cb44295e8977d1f2610d
61	1	169	\\x916465b71a8e5572fb447d127ee82eeea144adbc30c63fe42dbe407175e39d01490da16828e46645153b3a235ff9385b00ab7ed9de24b93b0812532efe77d904
62	1	267	\\x31e9b4a757a9d9cd47bfa767832345b215a4941fd9e2c864fede1a3bb0e7b5e5c0893cc5358e0a8515ead081195071545cd0139281c209aeec7d473f2c54430b
63	1	351	\\x8e87160092f56fac06bf2504b76403a30e320c19740ebb7b5cf44d810439d123d52a631bdb82a77f7432e27be1205ede35682fa3ef06c40ee8aec13d67ecb30a
64	1	245	\\x65c2dd5bb2da3b4f5e6f3d8d0e09868d9c54ffb6ef00eb8d79098ab0c01d62c5a314d937c71dba66fbc5e869c49d0174905dcaf3dde05aca9c42966b7fb6d108
65	1	311	\\x9098d70cfa66dbce62af77583d7e6ab8a2731c094492dbf86f8e43d1cb99f88641b48ee09842cfc8bf2b577fd567467b571696c00a0109509de84372273c4401
66	1	87	\\xec4b2ee56f50dedf6d08a4a5f798004b82681eb5da45934bf58c0145c5fad65faf41aab3b8152376728753e8fc3447a4ad5b9c3bb6aeb11b1b13bcdf22decf06
67	1	4	\\xc3e2e8b5df7e1e8c792217a5d5946e76413272522eecbee7d9816d1b756664fcd8327b560d3334479f575288c5c03a1b75bf1fc60fa1dfce6550b215a4cf9205
68	1	276	\\x526332aa93925b3d717dc04cffacb4826aeab294986d2ec562466fe3db10eaebd615e760f3cdd9d0fcedc42b2a96faf82d8d4b25d72395c48fb95a9ccce55c01
69	1	98	\\xd018986e33893273b2def6058a42da79dc2114f71774a9ea1bc86c932c4b207fd9bead4d37daacf35a3fa6d51354a1c4d5b86f8228d9bd925686c670c3d23e01
70	1	130	\\x3b0ceec9ea9c2bc3c33592fbd443416ef9d1aa27c3a20a8487be8738e233c85fe3fa3df07fc87ce5bf215dec51b1784230214fa4e44f3888c5220e08208f7608
71	1	131	\\xdb6592699a05b3ce43ae26b6baa05dde03f140b8cc04093d472c7dfc1d3d35a3ce5feecee086c5a74c93ad738c318365c02dd5323d6c250e87b316b0e4ff2202
72	1	207	\\xc1b2e42c6a2cd3cdefcc29dd3e3f1becd12371df84fc806f6becfcdf9eee062bc270136b2ae05f7ae92d1aaec728e0f758c172e86c98a329cfef6afa56407b08
73	1	363	\\x9e1485955f8d0e540875d7102e4a7458d5ecece1edf26d721ef094b4914d7daa176ce937ea5a37ffc185663589ab487535bdfb99f238551e531d322069df3106
74	1	150	\\x862a9e4e76fdf973201b9ed6e8e59a53c0c97f327b99b9fd8737cf627df2100b44ecfb0cced5d635d85b5e92a1167123b312420aa01d006b5a0f60c499518300
75	1	271	\\x8949fbea32038cee0ea55206dd65af4daaafa6fe877d304dac6d28e208faa72d0866d7bef8bc66cd9adb8fa0e3a4b261ba47e0f70c49d8b33a66d23d4ec07a03
76	1	128	\\x513be3e8f985eb04bf8af5e441a7430d993da59a696cd4933d525354a69220be54d79419d520bbb3b46320902b963dbb76034a14b80f07fafda140f324189400
77	1	33	\\x39c3c27c2b05c05e73b8e8a940db304b42a654bc6bca80b8c96a2c7b8d99c28a87b3ae002f56a9a05d534c35216fa752a747b5ffd1760f9f3e5652143642f509
78	1	53	\\x0f2c98fa4e29d1b375e7bb8700b7294566e9a7ee0e23cf09fc1750cc243bb0ae1c37c7eb6f658b40ff98523250f61e73423032274f6dd71924383a875839a908
79	1	156	\\x2af78d95be4d9bed76f29790eca7179db3e066ed071f597af1fb4bf7650bd07213ede0b3c5ca5c7518694e427a584fb4f1081193c85394d25784733e3ed24807
80	1	405	\\xe7bc9fca2a74e627b4a8c3c30561cc4291252471dcd43a1987bca824d7f8f310d72784fe90d0e9e4098a568531d1629c333be99ff28ad2476e24a4119ee0a903
81	1	282	\\xe6f7ce73d9078205dcb7bc7592100008d3b00b890043878b5477ae2b83804eda223492375d4265a010a71b9947b0f4e5751b51969ce5d5c8f766a27907e3b005
82	1	274	\\x5939061869ed1c9ae458b4950653c34ccdd28bab69a1116d43f61aedbb75522c882bae6b197ce80d5b628a38eb3f75031b5998308b783011b5b48aa247abd90f
83	1	268	\\x8adc9ac5a369b206c3670fa74471bac3a73610544cde2a2e0d6178bd87902b452bec60a8b2fd5aafe331bb5e0215dd07b7ea8df6b5e4bcbc95aca45fa5bb8906
84	1	31	\\xe9bdff50d481fead10a18b9954e0d46db4434603978a7a4636bb2fff45fd4d8c4f4d5ac3164b5c4e4cbe12b36cf580fb398dc855e8a8a1e8042a564e6eafcd0a
85	1	187	\\xb98e051a96e05c6677f3deea094c8a02b1615f5a5e40de8666fc6bfebd8d853581affcc16b8fdc87223b4e3655350eb0c7a15f712c64af49f4a896837c395701
86	1	396	\\xa8061c8f8f4431ddd5ee476531c6b1e246edbaedf7e1ed313e814e973502bee83fda50077047b4641694a64fc323452d9e66a7a467abaa7096e85d2e1ad6d80d
87	1	193	\\x779f73778c686f6916c894205855f635d2d852ac4f5cfaf321463dcb142d1eb21d17daac38ac3eeede746ccc357514ef2395b7064f2240e29b81a1d95375bc08
88	1	254	\\x5ed63243a1f20f4f60b8e92c800ddcf7d478776ff493efa093086ad696c9ed0672177deacae6219aacd5ba9aa5a838a70fe81138d7697d211afa078c7a74870b
89	1	255	\\x0387b8ac0970bd7d94420aebfae88ecdd05d34f2d7285cd1967bc5254d11fa50eb22f5ef63f40a9ba213aa9a0180f8863c5cff3b8e341d6929d395e0ddaccc04
90	1	161	\\x07fc1b0a3e6f73efb159a02038a9562d0455e524f907f18041a50c6caa81d55fc757f86e1a3e6e0349fa97029c2b7bb0a87ac21ad697b43433b111ddcea5cd06
91	1	383	\\xab69ec1811b3da1ce3f88a5e2566bacd038173ac004af7ace323b125947255f1ce0782037e765f23a62f20a05ff2097513240e6d5ca9a6e86596f7c6d56bb701
92	1	382	\\xed4a784b1cd48adebb267451d7c5fa3d75ec2ebaed468c9b6b95bbb44885a25571ea067259f50a10d4db4ed41c7f8fcebe0884196b478ccffc236ee28b71cb0b
93	1	252	\\x881db33e50758ade95f5efb5209a895496541e91c5a197f02360ea24523a7b16ee3dad6ab1afbb636cef9ba2a8cefa79078932de931278b02224ee323c995606
94	1	325	\\xafcbc1df29efbcb33ca7f77f43c9b8c1af95c712f60fbdc357c3bad2beabe68719a27d2c6659ee00dcf0697377b22bb3e4567640b4ceb25b4d1759fb7305610a
95	1	365	\\x5a8529dcf89fae6a89329944df1071a0b38801b37e34ebc6ca768577327d8c1f7cba0ac36b8a23e4e3dfe7e6a5a5f18bedfd9a7568d8b924f8b314700b24a609
96	1	202	\\xa59d6e4fc463c1a25d9a70c5ef27b6aff0b0fa7450f5ba53e7615484b56e5a5ea8373076e9c6b3acb24959cc3fd3211b1325a6bac57e2be11e266263ce074701
97	1	376	\\xfa90349035cad2e6bc96681c9c972bcc1042af21c5d5b67b442db149fce8d6d16444b543aa2958779e7471b9393fce03f1c14a1d8cf0af456fdba39a4d9d0c0f
98	1	42	\\x63b3ce1f6b707dca41142969d8e1c3ed0ae911d4b26aba6e63288a0e8823cca6842d2eb876e7b1eb1b6ea49982871541fd63bad682ef227f4d87cf56ee3ee60e
99	1	75	\\x084cbbf0e0f43a01d9073783b4ef3cc7c68076f177bdcd64d0796bce3d726cbe9784ac4d8fc4ea11ca37059e57b9ad8cd393bde771e74ea26b062801b13ab608
100	1	172	\\x9455afb8d6312081216abb3b9aeeaa59cf2a667401bf66f5a466a221ce36c8ccff7f6e5dacd90c4eeb8b07ec8fabc1d8af626d79cb008832baf883f080d1f608
101	1	308	\\x11ad638cb026402132d35ed9217de7b399e5f346b43f89cb75e40745cf561ce4d3bbdd86f85eb2ca76323951de4c84cfdcf62d242064ef317f62e1889f5bd50f
102	1	281	\\x8aa90ca4b0226c5a566267a56fea9464e57fee0245fe96101339a56c730284e29588d814a855a2189d7ca5260bd7e8431d987959734efb41cde11d969711040d
103	1	416	\\x45f7ef64072d512f232d8a62ad16b09878919668d54505e4ea289bb21224bf0de67495b7639de8faf7cd8a0c4e12210aa6c9960d9fcff5a9f76f635af2db4300
104	1	247	\\xa79c44ad54e1d4a3f34a612213a965e8b6725c43756c3e2b0798da7c18ab125a7a1499467d61f860d26b4bb138eb9af50830e077816b7f22792e0ef9c03a020e
105	1	168	\\x82d7976f03d99515a2a1adecb8abe14a9c9ae68c583133372368128af2c14c388a39597b668a994b918fd099d30aaf89b9a6e57c09bacaf393c6a4260a785b0e
106	1	36	\\x936c45b547c04e6b16ce874e2bae52cc1eb4d7f327b74145daeb150fcfbab786db06b5bb2deb5281bb41cb9ff6dc7836baa375cec845886b5c2307b0e38de60d
107	1	329	\\x6a1029e6ecf94e0dec0f95ce6c714d5c0eef7ee348f7ea5f6d20ff45683a708edafe54d4c90e9f9026595b5283276caeec8a41a2974f72bfda598ed63ccdf60e
108	1	408	\\xa27c40836aeb3e1c916aafbd869edf7ad060c1406d5a1a9ed3a132d714d2442e62b389355b119ece8c4964614c98de50a73f82d307fb8ffcab80c8ab9527220c
109	1	328	\\x388e91605b132993e7a4f53d9eb638cbb438d58e5a4bcbc04465e9fd8d2962e24e334dd07880bad62d62495f74cc84a4342ea6d977e88af588c21c51647a5303
110	1	170	\\x9914443d701d3783cbe710bf89519d40c82118e58500647f4fac4e57ecde12d83cc42e77f956f1a689a866f124310c8914e6365f01ffefc8cc8884aa5fd03f08
111	1	253	\\x87214c74f83de3bd885cd513a26d28ec4997c01ba07581bd433a7216221f3a15d497987f4dcf4da46dfd4d6818066e5c91800e760b4ea54b750ee7d7e37f7b07
112	1	353	\\xbbeb67269f61bed233febc1d4aeec9c7afdfba7bd8a3237852cb80250bffe4818dc0d14fab10c753bc1dfb5e564b216b506d56a0f8280a41bf926744cf57a409
113	1	19	\\xe3cd583eaaa2106376fc959a0e1d1b621525c03b968513cf6ff8f089286bfa5e646d55e835e233730973e6bed4d131d2ec9338dcbdf480f7c29ed3bc3914160f
114	1	399	\\xf00de0b586ede3d8abe37dbda066a203164a7cad53a38a55bf1921848c26a6eacda3a03eba50954a9b711769862d47372db79629d16dbcea4e05d4d9c8dc5608
115	1	14	\\x47123e2f143bd0ce2fbe32fd9d88c5dead81467303ec793ac66079eb35cd6f4557d1c01f250ae4731e9bd5dde169ed7eee484910dc142b2ca9331a2494752f07
116	1	270	\\x444269927872be73d5aa5fb02a3141b5bf3dbe48b7a6bdd8fe3ae4a33c1e86bfa9ff46ed0eb72bf4b20bfdc036564a66970ba13a9f829ade2f457829e0f3a401
117	1	251	\\x87184867e38b3d38ac3ea06406a6c55a6b88a49f0d9c032d03f8488986bdb3f50b47b101fabbbf26de38a3d4d4c40dfcde05161ac269ef0887ec810bf5e10e01
118	1	348	\\x5ec8416d93ec504cf381336f0ef9eda5c4e978ac243306bc578dea6a690854ca02ab5930fd8d0afc86a295157c333a2314cf9db1fb4622c2c57243a8956a3007
119	1	163	\\x44e4a7f8ec8b135edfd8746e6b12484a1032852ba2a65709e076f59f1cb719093275f0d9120426954f2a4f547cff39c5a35284b161ac72a12484a86d65a5dd0c
120	1	238	\\x22e5df458bdba63254f21c83d32ec9b7cc129e5acd2194f6f5673a3887e892fc8dd5782421e04e6099bad29749b5d80020a2c08b0b4427f15b16af59207f7400
121	1	147	\\xbe525301f725d5c208a4189ad55836d8aa62beaaa1d6368aa8d2942c4cf31dd1781ec32c5eaa224d7455decfc5e4e5ab221564433433709545f5ae622438cb01
122	1	421	\\x4dd5511777273d4daf0da79360dd25712651b6e22963760539f2dc5486c8075f386b8ef260dfc5c5eafa05230b7aebc95048ce32fdb06811885ff9180dc73c00
123	1	24	\\xa4f1465b0ab88c6e6df3fefdc3d406dd14906b73965156a3601fbfcdd8dc896f5949bc22917ac38c6b2fddfcf5f8ec9869d284fe46aeb0e80710de1bc74e910b
124	1	27	\\xcb21745eb3557776c21ec901206ba2f59ca58182584fec7682f2d50a15f7d65039be74752ef58e1f692514f037c9d437ff8358a98045819f332c92b13086d701
125	1	211	\\xff4aa4662f654987497be1ca4852682d4817ee75febf3683550e7224ca0699b5f69dbf11a62cacbef0a4c2f0316ee2bc59493cd71db626d43a6ac74402e8a50c
126	1	361	\\xa987f8f418929d11c24cf78d8f01c6e8bd442e73cb3c9019e4b95159e9c66c6a1e98e99f88a57685f5217030148d6f8131ee28c8ed701b7de11041680dfc5101
127	1	38	\\xeecf70c50e2259af641e5d7a937b534604b4628f37fee5a6e1bf555d552072712425837af549947bc83353e9cb54e68f927f3b36725275b812987b56c3794502
128	1	280	\\x095216778705a8cb85ad160e85439fb5520e74892fc262fb65d9685a309572046bc11c3712ebdba5e8bcb720cd24d93a4fd34f1afc2721bfb67bd358acf2c208
129	1	52	\\xb6bb7b0b8880c1b4a7afa8cc9ebd406f79b838e946a63d329ada3b12db7b361408cf84cafa450e272d8c48e59fca48c1d66e45647571f328e8feaff5ecb3470a
130	1	212	\\x6bf07454940010a71fd4f61444903966c4b5dbf93d4fda818eda6387256020514a5e0a1f375097288cac886648e0b70ca22e1dc8a94f284f4334884736b33100
131	1	314	\\x578de26d881cf091ec66b81d3cd0ed61131dbae279fcb1b204eda951f298dd6f4b71343c5927d1e2c9a4614b1150412545ab0b6e0bcedc5ae817f70d60024400
132	1	301	\\x1cbcee26eb0db8c845ff501fe4279ab60b6e59d388564e48bc31359dcedc8a3f8c57093853dd5cc707e81b6d263c34f892dc3ec7f89ee0c4acd5fca7f4843c0d
133	1	370	\\xeebe8d0a33fd81e11fad7ee23126e7085e13e6484426d45cb5e8caf5302657538e06a0dc03195651c06839ff9bbf8618a1f159354ebad19e2784a5ce96239f0e
134	1	302	\\xc08e8a493d45ee814a8d9f366896e10e32d74779ae42654c154325d7e00621d4de053e9894157913381115a63062d9db44aaaf0a03c6386c0061dc704a50f40f
135	1	319	\\xb123052fb57a9c96e11311f53b21882e70eaa5d7ba82c1da77e4ac65ff4813264783f3abeb73dd73b2ba89c228d2fb1ee174c11fcf221022fc33cb4f8780e20b
136	1	94	\\x2d748973ca3255274dd5c75df25616a16aa775be2d60b7e708ee264913c120f8482359ee332e44e799db05f419083e39c9371f62eeff1d0d820ad8856739fc05
137	1	73	\\x6fd9c0053c90ca9c1d1d3b3cbcb887f9840752209c8ddf56b30321234058360988dbd10a83a70a97c0f3612a7a5ab1b867e3533552a69f22748fd8f761a2b305
138	1	18	\\xf6db1719734a1f661cb722e78de544bc73b68820fc5cd22a048d3f733631cc8be8a7bbe02a44ae722fd14eb7ca6975b66bd6e5533300146ba575663e8d74850a
139	1	346	\\xee11f11ec3d9e41d68d97e49ae5ffbd1cb6678af29a5cc024a795936016369980838e0d6aba88ab9493c97560431506bc5b274f3ded4672a43aad57f3bdfa203
140	1	178	\\xa397913b63c0266f2a7ef6cdf61ed08b72cc6f308541aa2c05ee046c7a4b0cc4bfab19bac352a7357b1e49ad9d72f46ffe5ee2a0c455b5d08c216a3a000a0a02
141	1	138	\\x318820841d684c612616d914f415e44e816c21237eb88225d963b761cd3887bba58c01025aab5f910ec251eb60d081d710e9a6b8dd42b5f01be2da8864b7bd00
142	1	411	\\x5dfcb88fbf1265bb35c4dcc7ec183bed1734a47091cb743de97013dec558e9b002fa6dcd8d8ecf39b5b84474b91c43e8f3396a346055345bf19692690c3fdd09
143	1	250	\\xf796f15b9de200dd9d83bdbb511c1add5ce4891953416cd89cf9365d6e71bdc13f633e7a9ddd6d75f3d3ab6964263ea55ce5e04012ceb617c96817f1e5e76906
144	1	60	\\x5f2b497fc55d54c1f89991cf33195a44fba5b9f42522949cb6133a48dd2120d3631b030be58b30425e07591eb7cfc7c077e8b262bae8a5a7c701329f10b50b0d
145	1	137	\\xd64d65b2e053f1b068cc99e230e81ecf31c8b19afbf6717e5d9543162d614282f621f6286b8f83a9a2c104032300cd3fe543be4026b066fd5b43ffc4df95a609
146	1	206	\\xf375c0d9cc1f56a439362a3903552902e8f7e6af4d3840d3842db537974fed508ba2e0f4f0b992a287191f50a88caf21afe91f5dca62339f4567dd3602016006
147	1	418	\\x8abf8a6434e2b2ba24833e9c73abbcd1813ca6b677650a26010cc290a46681a99871d01975324fedc2b538e6757a471050ee36df518c8c2d8c8e9287d0055a01
148	1	358	\\xb3cbbbac293042be562d6c3eb321bed5b51a16c86a70547b817f2634d54aec0e8b16b65218138d01a2b6517e34232610bd7c4dd68466acc2fdcc491359fdc902
149	1	410	\\xfdd52c7adbbad7727774d47d17acf26ebceb43166f658fba3ec2a1bed9262b27b3c5978e80a250ec38b201608bcd42f061b0ba37923cd618d6b9ac43dcb1140e
150	1	420	\\xd6f2ee5a0d2370db5aaae1ab9123ac6a03434e8f3825e3f9b2f14f8e11ee6e5d14113af6deb802d8d3baada5df78ccccfbfd82c9f95d04c26a73a5ae3033e900
151	1	321	\\x5718fb14cb5bb6273d40d11ebac8aa2eee618cf8cf93f650538e87c07bc54f039002a3be28602c0da2c1ff601835d8abd011cc68a63c9fbbec48beb57ec63507
152	1	57	\\x1888fc1fff41dd805651775aefd1d0b0e56ce1ce2cc21a741d18732fbe3b7d9b2232cbf82cbff1343e3ce247b751d85906b0ad7ec9b09b6732e66ddac45b8400
153	1	217	\\x204a0394986e1152d956a0e7b555fa60bb59f477775b5bb945788fa4ec49e6bd8af5013b9e391a248e8020d10423aa393149929ddb0ae68485f8ca27a85a5d02
154	1	424	\\xea972c674840cc127c8a35b30f1cd512631dcfe6863133d6e941c5dc7c29bec358ed76dabc559427be57ea12a0cb50f39ce73c422f3f24a5f650d4890e8b0e0c
155	1	417	\\xdfd0de84b31a5e764acda27871783430f5ca6cd58dd181e1997074c51e2c8e4c11ec6b796bcfa348123ae0bbf09b397f3a6791dfe393474002f1459f249d1301
156	1	360	\\x31868bd7747868361c51514ca04da895ff814e6e41336eec82d14c103e9c2481851105d41085571ec62511961d0d4465b393b97f1169d6ed36391d175a685701
157	1	242	\\xc430015d5bd85018681f088189beaad045d7235377990c9e60cbaa2f06effcbd3c4da8604bebc55cce671499f63e7588778624d441a98e3eb06b3c2b51671d05
158	1	335	\\xa07bab331fb21afb688266ab72ef3038bec34cad94c2be53ffa1ba48ba72818f3d3726d5be22fb19f2518160bf201ffab43976893917baafcc27cd801b4ef700
159	1	74	\\x98886bf393b37e1e56133fe393b2ea1cf5f8a808b5989e6b9b74e14e7a66900a78ca31f77930db7fca60c3f96f2e249d02271aa0b321ad5686f613b4636d4c0f
160	1	294	\\x5f230105121874767bce649cead198ab139d4b0ca05abfb7a476f307de8662c08acad9ff24589b8a40c69b939c06ee6827a7a03b63a5d43803b0c02447debd03
161	1	155	\\x5afbdf08fe2f4ee0aec8f6f5f3a89bc2b7b2fb5da0ebf1921c191061b159c83f2ec485b34ee45e3bcacd9509026dc87de6033af67cfcb48158fede0bcfaeec03
162	1	327	\\x686b8142d0282d3f714a8d529a2eb2b86b7aa9925ffb34623b069cbb8f302328a5c315c2795a3cc56a1b60e1263b81982aa4e585ae408f3ee5ad7fae5eb73a06
163	1	394	\\x0d675dce094d09feff55d836016530329494e5caf8e9d929e153137e42354b24fcef4847e326008fbb7d56deff9ca5c58cb795267848c40b059cc5f64ace030a
164	1	191	\\x42c3be381ca141c3be89b369651ef4fd36d464c7fd4b7a46c3b56e5e6c4b3d4f962dc12638a68690c4aacabc8656fb005e066e9d4b6a03ca902a0a194c952a08
165	1	339	\\x65aba7e895f1172f713078a8b46d52b5f708b158e64dfb8667f865b474c10b4a8aab71dd59e0efcc4d384543abdbc6e21fa962f08c916c5e2dcecf43fd312e0e
166	1	265	\\x9ed8968c76445bd5919d579e03002acf8197493cc7dba2352294b79a536e304a80657b5302d9c090464ff3d4005df7e7469ba2fa36ba3f8fede1c18af400b904
167	1	369	\\x70415068d4a4e6670a11bc9457bcd3fb98499d64421898a17d3525df26db60c2300d043e46b301d26ebfdd7e5f09fb3c441416512d0295cec3dd8039fa3daa0d
168	1	139	\\xfaa4662791ade327c772af27c42e72aa38487ec635093281a124efea4bf4f8f5c7824e5aa2fd8c0f457f189ddf8f425249e7a27719a2915706633e5109e5930b
169	1	377	\\x78176c65435fd290730889eb68655a3bbaa36d6c0e23cb32ad9d06a109dff3a7961de043eb0d4a60b2d5361e700b4c3e8b95667b4bd6cfea823943af69775a0e
170	1	218	\\xc761e8bf3374b3ce4c93b0ca746d75c01332a83f3060dc78a232c9204b4e46f237a3a5a274e059fd1a86ae1bced6b8eeaceb47d70cd0762706dccabe04ccc60d
171	1	80	\\x85d363572e0f8ff495782472a2118d89554d0db8f6b34dea4ada9cafbc4d245a570dc0c255bc0560dd6c1529b2013e4b644a6edd8733727694ae56ce48ecdf05
172	1	324	\\xe89412d4dcef88be045ffdb298b3adf6050a428b016b51f5931e86ad589b8b483998ba7f1eaaac52e4497009f5b9407359b3139c0560188d00e35fd7c523b603
173	1	145	\\xad0f20e72e7d6550c51ee5e19112d095e8f6e916e6db875841347f194d1f19132413b1837c89c2613bb37cac72bfa3e7f82189153a531ede07f67cd068db8902
174	1	204	\\x2b775eef89fb2dcc2a45fdd45851506e88b55767d131673e30f32f3c9da540bfdea89ee80e12e9198a3afdde3f4a35aab37dae5944a4a35d8384f7a3ac62b90d
175	1	398	\\x5958810ea34f39cd8e1474f4310fa55a682535e6d4c4b223ab7b28b24112fb50407725ef38a408a24e4c9122461213c4eda9c77eb72709e4512016250d692b0f
176	1	347	\\x2ce51e7c93239d0f471a08444e85c010bc661598c6668d29e4fbeb52e2257c2b504452b96eb6275dead089d41ea9895b75a1ed86eb5a7cd41eb7893f0e413907
177	1	32	\\xbade12886490d6ca4a6c029d33bad0137ba5c735cad10203e68a16ca0497af41b0a1edde81372d88c3c6870b0bd43a06e5a3b4fca5d40e785588e085972fc201
178	1	184	\\xd2333ecef6ecab4d79ba3c120711731e8b6f778a1ca054893ac7fde6d870cf3b497e1abea1d86d2b821de69b41ff890657b4314613a5865f1a23dcaa582f7101
179	1	323	\\x8127586a4e31fc6b3694513df69ed0e64e8cb87a8af8f6e17d2ae3386b8feb124244483d26b9bf7b20eea5e7db8505d4ecb5052dffebc2ee599ec4f51e8a8308
180	1	105	\\xac60c0dcf429f74094a03a6ba1775b71625e1f593e65c096f11811cc656ca09a0c2ced9c50025646d7d2996742fd17341d95dd972e3ce55384c01f9e0507fa06
181	1	273	\\x6f976c18036286dff3b57256931e414967e7a6a44bfba933c1b907cc3ae5a20f8525b29ee08d9fbb4449f9183d49a40f2aec52ab98090875264a96f717312d03
182	1	231	\\x926638a9fde8c7cb3a18e3061c7aaffd17a91874249847d00ca01d87002ef00ffeeea56a6d6d74da059c3675dc48efbef41a4a4aad7e41bd6f7028246a6d6001
183	1	143	\\xfa6b8f5d7c25ce1d8ebedbeb55f9a261dab9b401543f55f6f0e8999bbe76d34337f9bf0b713aa9aaffbae35173835a2e896382960eae811ab25e2272352df207
184	1	412	\\x44b0187056cb495f3a7cf581022cb410a23e530ea07af34f8debbe9813ed19b3d5b30f4101a1a220bb54405d22eee58b3ef353dcd3d1f02bb874091e965cd702
185	1	76	\\xcc09d01173816bc6dd9ad52344de7ff8f26f90f8308d2dd234a0a05be6e6aa2bf86f040ba584669b57ad8cb465fa91ab5b13854dab4b0a36c089b671f5f15b02
186	1	66	\\x3930369fdbf770cf75a22cf833da9be90f0b972c5f72af4548275bd5f80fb5e4b61bddef536705f72213e4a366796fd6f9c0fcf938f208cecc09657113e7920e
187	1	342	\\x2fce1eb7bda3e014dbdbd6e9c0becad7e7e16913226be633c551aec7bc7f390856ab361cb9846405b73e278fe02d6523c0a3ea5da6d14ec5abbf5b3d2e04a503
188	1	109	\\x7810d32408b87536a4d86524eb402e64604f9d62276531fbb552be6a9a52509b20121381b17f6b44e84a061b809118fe964dc7c81e1659c404f6f5433503ab01
189	1	386	\\x2a150bca804b63edbe91f15744847ca209fce58e53e9f32faa7a03facf8a21b68f6ec7a3a1c7593772958d6d7d10be600f91698016141551dacc31a46aa0c601
190	1	118	\\x37696361e433a9a98bfb576bb229930f3d6aceda662011541c7dab17312a23b6db63a97d4fbbd6cab29d6301d98ef86c2d24d51f030bcce0fbfad88e81e14a09
191	1	151	\\x557b066827e7d3a79b3d238eda712e98b17d52a33df19c19d14e08c03369899312e908b8c89adbcfe85a8395c2b3b3a119bd3dcdbf0a6cc7358369011d40c005
192	1	102	\\x9a7a202b2413aa0e655f3a77443837832ff670dfffff57a212eb957837636b6093b27099ef81df935b2533e385ecf0ff554d50a93e147a51896b045b724d7303
193	1	340	\\xccb2f95e67d74002ba1f1289186a6248affad14f61bde093655197622d4878d21831323f6d9057041d30210db5bab1cb713ae0187fc6436461944aaa41d5d40b
194	1	152	\\x8d9b0dd0f3463012ea68f2c5b1d3e4755bac91a78e00dcb43ecddbc6e68094f5f4856cc743389543213138bb3e53335cf5631849b8732a428cc9745fed533006
195	1	188	\\x785642f215ab39542828e693c32c9bb8edeb9738434c29a9f9cfaea533e14eda982c51c9d2b3ad957685ef74feaa9a264b0fe6787e1a7e2236fd7193a3092e08
196	1	148	\\x30b9bcae2bc8f61a6024deb3810992935e9ce72d5fb547df44315b407745929b8abef066e8bc14e118d5b72699190c9826e6c4e4b0fa5abfe31ced7a7a296e04
197	1	316	\\xd7d28f4d79e6010696ea47e79ce8d5239ce0634ecbe2e5f68801a56bed096d0d923717a1dfd898eabcc4e8b9bb772f4f5fbade2eeee10cbed1762e2363ccbd0f
198	1	158	\\x5cc3765dcc63472d7669e8c801068235bd860f92e6644861732b042b090241d5922f414ab1525a720bc0f517f3063930837f35f6f2c9a581bf7d003318d06b08
199	1	55	\\xcb7b8b1927ccc9a8d2992ec63454e4a142e15b3f0ee75a52447e76f01fa015515644aa92077dbd15fd7da8950a9001a3e6e01b3429e8c3d7020d08d99246ff04
200	1	368	\\x97ee814910a4f6e75901d64a0b9d29889ffd04a683aff2154b8c9e262d2586cfc482f6be95410ad424655d9b756bc615f8b23a2332213028fd6b80ae3e06ea02
201	1	373	\\xe2d530f72174bb9f832ef0e3d3c2317da7e85bdb26257cc1400ccce2a16dbea56801fd359c732bb75e1a7d504127a240c34d345c532b1b0a3d48fe4ae1c8a70e
202	1	213	\\x0d68593402d4a1634a2c4a5f77b8f6d6070386d504a3bc5d6137b834d3409629da92678936e27cd7b96d59a5b3a49f46fe5424d451b4afb9e87d41c95dfde005
203	1	331	\\x39580b1294c2644f0c0dc927bd06384ac7cf3e343c79a1d9cc56b4eee8512a07483d607af06e2d058a6fa3b0dfa15113be15a0cd83683615023b0481faf6fa02
204	1	391	\\x3612a663467f3f07fdf28701f64ec813bce129b7d34571c9e09bd3ff9d4c30c93caa5739e901bb9409b2ea65a6ca019842387b0c556be0d294ca25d9344e7a00
205	1	113	\\x6ff78efea0dca00f45ef05e56aba00325234a1350dc21ae3928730cc6e684b06026813ac7613e3509d80564b718e6c8b67e17affd7b51e5439c6be9a3c504501
206	1	54	\\xc7c9865cb99df8f28348cb51d3e7992d9bdf2c2747637adb80d0bc389de897cc4a55f041c931e4918d662ad7224afe14f2017aa7a75c72512b01b79d2f3c8e0e
207	1	69	\\x158a463cbb448d84a5c1a2b983dcf71038d04d941c193ffeba561c7440a5016e7e8e5455d78b6567d53e7e1978c24a6804f4801f161d80a41706b26a0fe98f0e
208	1	305	\\xc1ac5e464ddedfaa1314eeecdb238072a06c74a13d0623c11532046bcad25f80b3093ac45b493ccfc2bd5b9fea43cbeca93676eef6446828697455b788c83904
209	1	296	\\xe9f0770243b22af9ed6b0e7e3a0e2af8df78c9ba5809a85a0ec917ff7363438ebaefecc0c43fa978f92ac575a4c80484a45538e21e19d4ca43ad215873d93d05
210	1	349	\\x9d52edefcbfadb6c31cde18ce486cd06c28198de2184cd14cbfff2a837f36179adbc809f4e114a58512aa5476ddae1cbe732cce15f2d078e83df451593de550c
211	1	157	\\x485763af74a792bc8d2d3754ddce3bd2ac0dbbd32efa98f9db3af09a4ab9e8d834825f448a188cf06922fe847a404d64ce592d3f20af3e9af029aa8488e61a06
212	1	165	\\xd79873fc122729d026f9326e37fca7dca47696c9e38a0afb07de9986d930fb145a2cc8042cc3ca4006385b6ff018f3da1909e7ddf69c8e31a3524596844e0909
213	1	263	\\x192e4cbd69e17746945f4db9de0010003693186c1f331e5813fd7cb097c6b1832b3121d0e3985aeebe54406de9ac3670c4313b8d1dca705b00821a1de59cfb09
214	1	112	\\x39de2ea69945ece23afae6f170c03dd38ebf5b8965b817523a9f9e3802e24943f88db7abffdbbc510f683da53d7c404f9a7ff10be46c2ea2ad0323b16e8eca00
215	1	371	\\x6e549d0ad594293450c4f3019dce101f0b353852c4713329150b3e3181671a07efd0cc6f5251cebaf2dfd8ec8eca0dfc93233354b5973e6281e307f6071cb100
216	1	225	\\x41357f21def2e406749aeb6757086da35a632597082e309c86e05e1d72bc6e0f70f471efa791c388d48ddadfb5c0a7c18d15f912e591d08eebe1a0ee430be20e
217	1	354	\\xaa87b6c30d89ae499cc4034ff39c5f4c27a5206722eeb587f0141f47c2d3c4a3fc0bc71dae36235f35927e6f8ba72cf53050664db56c34675675caaa2e702b07
218	1	203	\\x05054f182a07906bb9dbd2d4e424d08b0d333ec2a66f25aa47a9d9c2faedbba00a17f524081fa48fbb6ae01505cfacf736b183e945eac9a77cb8dd23ba00440d
219	1	343	\\x9c07dbd16a6d7527e9c14c4245bd6c0cf7ffee93f502c429ad7f119c444e3605d7b3a9a43b6ea7a2b568cf2e039009881e882b77694387ecbc64d72b6be61502
220	1	51	\\x845597a0fa2357c22dcccbdfa75e30e2cd05b6fcaa2a2af94bdebd5486f1725f9ff933f28cc59c4143869248f7fd4f5951aff7552039621f4bd08d2d2adcee0a
221	1	196	\\xdfde6d1d19a00b798640e7b13015e953162275b37acfed26deeeef8abf9835e03e277299088c52f60034bf30b952e0f42bf5789c778c7ae3dd65f7f4b49f190b
222	1	332	\\x9c3d22ca73d6f8b0c727fb322bed0ab8ac9ca6b0147fe893c372d124c921e301bfb1eac65a9914e12a532fd3309ea7666a6064b717964436d161050035271505
223	1	149	\\x12f62ec362c4a64a1522fc81f09a313ba002442755cf787aa9419b48c67613e38d2bd0a1434478b1f4e700314b3ee4a9de2451c180a7fce3446952a969ed6a03
224	1	173	\\xb9c8f697b9f92c66ab0beb77775ccd10ad638a21d1796462b89237942333fb73c4c509a4044a4b98d506f6ad916eef8862e43fc0906dc6c151909b91683d5f05
225	1	272	\\x353651445d4f55c494765a64867347934988ffc66e63ea821a900e7d5b19cc29e379cf228d210f6569aee93f68debd986cbbae9f986a9243484d5d591da5b00d
226	1	68	\\x55256e7056c145ae62e880450d59abbcc88ffe60769f11fb4169dec3a41a58ef6b434abc546096978bfd2f5d5f92c1f73e82ccb7422d8094041466159cd08f08
227	1	133	\\x4197f31fe71c34703fb2dcc0b0058d50383b4af50a9f943a96887c8b82418f3f731c9373d6d61507cfd3ccecef643688e3009b541727d4af31e2e243d398800a
228	1	400	\\xd0837172903acf88d292ef4b124550deb330b66cd29f417fd32cc7e9ec7337f7805c17c9010122d99d1e882dfec9b37d1024a74f4148f397b4d86464d68b6d08
229	1	269	\\x065b9249933175ff83d77d99dad45f0ce4fffb5f4319c3fde466de6233915c3b1183641ea6aedf4bef3dc78348f022369891db5a727d88704ad4ee5bb913610a
230	1	286	\\x5400562e7772c4cdcc8b343cbf163d3e3328ed2d0c9b53a7bef7441f957cee52683d0a9ccc36d61d22a8ed241391d449ce76d71824b1f821ad5f2dcc56e61702
231	1	12	\\xc20c48d5263eaaa37e019209545f1c278a05464d35f825f42c0125bce8bcf9465a2e5991005ddd79fb3916574e26ee1a52fed9e09cb8f1e68ec4e233eed63806
232	1	121	\\x9995cbc599c537221c318c221c948862f599234dac16ef229c01401b8e244a968524d8cde98fd09e0bcd5ccdc8c81fd4e15106fc4b6e7bb7a0e2d7da9cb3b80d
233	1	125	\\x94983edb784adcd85551aff2bc75ceaed1df19329218075c280674d691fbbd7ba3cac73e9a9675250a70b8c6c31b8a0612df6c5193e1c86484b48987ea68c808
234	1	181	\\x95555e4406c82ef75531ce5fef519778a3ed378736ecff97c0b8a1845da978f97e1e2044c0aaf6956f511996ebde2471846610ea357737a63ccbbf0cf066da08
235	1	171	\\x9da0fbda96b102f923334d0126e7e6d237db956aaeae6add6b51776e47bea8ac0ab9bb28222ddb817a16519d0c2ea416272dc09225ea2444cc7c2293cdc13601
236	1	71	\\x23909db4bda1864b47ba99963ea302031f82b1b2da65efdf0f85fc39cb68328efb7d26f007371c119d2b5507ab48649d9d86f9e3659d6586acdf3a0538c85301
237	1	132	\\xe5dac2db58779640ff8413b5e832afdf451430cf48e641a4957deb51b79ff731eb18b66b788790c585443c2cb4435879dd6a9f76d59e94a53769c0d47588be01
238	1	232	\\xad2ebac36bdfab3082c64c05335e32af4038b10da98e213174480ff43a1db486b51b97ccb26cc31404e8ba42b62b411bfab15a290aad071a51532ada9f623607
239	1	258	\\xf446d42db27d202642f404789a3632943695f674a94dc89fc3040702d081709a398ef0d32598b872c38e8d780b62acd91bf5d76cc1811adc328f93f41dd7d903
240	1	186	\\xdcf783095276559abbeac7ccbcfce877468f2070bc42a7ca8e82359506823d315a05e004042ea4ac7a0cbb86f274d3cc4902a0e4dcc0b0b6541c2646b1c93408
241	1	387	\\x2e9749cc0814859ff5a83f9c3ad7f98e7b66583fed46a56edde734b53c5f735a040fc1b0d02edfcaf7d212c99cf3483f702ac77805a045ca38b97addc4bbee00
242	1	330	\\x1498041b9a44f2efb6918193a3cc61af6b96208aa0a50730c0c9937561be2ca9ecf50527f8ca348e5ee5bb99d755c0ab6e53dca09aef2eb8e7ed6fecd10bc309
243	1	261	\\xcfa707a96a2ff032fe724b594f58bf20654a4886e11ea27cdca3382b1b7cea624fd19f7349fcda3d61ffb2dc2f9642faf71280d2603c453ec8674d59d7cb0f04
244	1	344	\\x2bfad4074c6bf8826c0f15fbb3808b8c94fd3ecebd1e50d4d485d28c2e0be9ac1a2330c10d1089da9bc6ea1ff623b7e28f27b7d35aea0accf013f93eb261520f
245	1	135	\\x965cae4d2e77c507d223a8959afc2accb7b7d2f2d658e8deaf2b447974986965622cbb6c6581d4c8afebd0205ecb340803e3fd18a4ff3f02cbe9b5592e60df04
246	1	407	\\xe0e8f9d23c205315232e990bf80528bc74f63c5e5eb9ef4f2ce47e9c143dcc9526ad41c65a56468673d674207054412f6492a690942e466b0832ad99c7d9ae0a
247	1	20	\\x5a8ceac65d0994ed3c1a26c1cfc8b3b11e6633e47553f8f7ecbbf30ac2a1c460debdefcc7a52bd7535639c751b8a0acb0625d96f7cd1bff7fdfd41cb519eed09
248	1	190	\\xebda8dabdb9f5de0733b94e10ef2ab72e1e33924843551f3d5c020c5fdaf60975013275ebf0faff0f6d806a7fc2ca90efa6a77a3e47d8b8d01447557abb36807
249	1	235	\\xda540337e53c3ef77e53b3654b501ab993aadd7bf89ed98d9c781126eaf0ef6aa6047ea09155e28385871faad0203c45113ff5dacb3e4ae50339ae9bfd23fa03
250	1	110	\\xeb40893b06066f5d5788533031083a6b1502d7ae37a2b40dfc245f012916459ba32284a13e86c81b7de5624953af63e07881556ac17e3404ab0993ca27d84e0a
251	1	61	\\x4e5e4e1a69e97256afcd666fad923e019d749c1d357d40eae9a07ae506402bc2fdd81f03d1038a86529b64eae7f418693455a3dc393cdcd8e9e12a404963cc06
252	1	84	\\x3d1823f61efb46d05f7b30e634daf4bdc5af07e15d383f7e02cd80092a91cc113afae1b82ff403339e9f8925118aad057635f0bce0c95ee23ce73e19c3bf8a0a
253	1	295	\\xe03c618b44295b9982da5063c38cd62edde97af360ec1590213ae16d95cd6bb22b39629cf4e91dbc025008a44ae64726bc9e20f78bcf06ce38885badd793bc0b
254	1	279	\\x8418e42f127ab8bd25c3c40871fb9c877a78b3a5cea6305d619ef497bf79de41eaa7719a05972e2cda325bf868c57fe58ae02247b50addbe9b2d1c5702ce440e
255	1	49	\\x286b36f0620b6da70176506d8e69893b85aad2a627266921555b9c476dbcfff88fe5fb5bfcd38046ae301b6729e0d511ec74ac26f783ff554b7eef3141058e05
256	1	83	\\x802252b1c33b778d81cfb9a9621851b32cab4d32a0a00a00fb67db0707a7ca637748d7014733518990337f930a124ad7eadf8d15f90796df3597678085535608
257	1	167	\\x70f38116fa074637c0675663f1bbb50b89a909e3f4fedccdcbec402102f793d364904a62cb5fdd1612b649dd574f5c248c2be91defa83065e595a93e3ea04f0e
258	1	310	\\xbfaac17aaf83de4e684c5f5bbd5b8e61f21af0cd615bbf44af409068a5374e14c40aa2b2bb3e600fa73e7a534b45c787bbc98a43ccd38bca192bf7ecd6e1580f
259	1	240	\\x3a2fc85367a3f4886d1c3be88bb7ad0e6a5796e896bcc7d6d8e840665c4e778c5303ac4ee5a52480a96b0d0364fa31c8a1d3d597308e7d13a25cc22a297b200e
260	1	201	\\xbfe0cfba8dc518ea1cc6a6808e1b5d3456dbfe794a54df8c827a3afa88a13162b80979061dd07d4e34738757d667e8b0fec2e7635ffd3277220545173139be05
261	1	388	\\xc6a33e278eb05abfbd0f4c8afb923ef8b11c68dac65b26cf1b1cb818d885215e44c956af9bb3ec1428c751af1a899a60e356618b40e8affc9bd11bde66e4780f
262	1	198	\\xc9778aa1401e4d37762ba04826a7bb0214aef7bd7b294017cabd97161ac960c5f7398984c75223f5ddd40a16ff8f9604c1bdec50594e04b30ef59620c3c8d605
263	1	9	\\xf7a20c9e0e23e6f4573358e3f8be7ccb2b7291c68d452ac496a762266de2b64b7b5f16c72166d52dd91dbbebe8ecf1f9ee669fcad3e3a43fcfd38a1cc6bb280b
264	1	291	\\x22eda43a226a3eb3c43b78b96adf37df52d47675f018cdbba841139774e29aa14a951bf6d05ffce39f6b6a6762b08214875c6659b78c56ced572ce4ba810bb00
265	1	227	\\x97100176b53c83dc43b5cfc78bccae83964bddc3bb9d97bcee2ace0a1f926e7bde2d70534f1a445c733f6452753b736436284b56dca679110fb0c39b30d15c03
266	1	293	\\x80dcd8704a7e39fbd411bcfbd6cfefd404eca7516238d849664fe1a042e7de683264b3d698c08bd650bfdcdf2109ed13ef679b598297e2082e1ff6e34bff7a08
267	1	375	\\xfb653308844c0da61844098afc7da94147857a6cf6e64db4af340314ec2f41d06fcfd821bf1c786feffb9506083b0ec87cd9840273e214c1dfadfc7cf872f60a
268	1	2	\\xcfa1247a5a0dc05dc524054574884b69343de297cb212bd81e091078587baa9a059db4aaeb75d9b9551de13c2c7201db982dbd8757bf7735a706ecf14937330c
269	1	142	\\xe9fd611eaac9e9e2debcfe3b3699b8e5a7637a219f58b49317a9ca8633bd0b620fbff41f9b16dd5a25bd999f1cef608a7c881372aa4f74f7339d56d74e8ab408
270	1	62	\\xa071470829ad2e0c73cbd13fda67b649e224a1be9a3ef323d620ca6eea47bb015f8e6a094b51ad43775a256581b9aa62e66505ea22dd730d5549b39fbf7d3b02
271	1	39	\\xe17d0f0160b111d5d8e7d87ddfe4eb2d493960192c45a4ff9fe226cea02edee251417d9fb8e629f7c1cc520c17be1b4ce1fa46803c29015e8d303798f296b90e
272	1	415	\\x546917f2dcf0dea20768eed1584fbdac1abd4ada07633c7fb8f4c5b6b9eafa9565dac3edc0d989bc71881a39a2dfdb8faa37af4814e7c8b54893d4a89f73b506
273	1	47	\\x155bb8e7f50a4578ac41941beaa9c8d4f58f4fbae9d0b7fec60dc659abce088dd6ac6db3490541958c458c214542b290a1615b252285cb07b8ae86a27352550d
274	1	13	\\xbf9c129e67b2a48e264dce256c39ed6c7c79e110a449d4b30b36304f2db4f373b3772228383751e66a4b87cc265d451ccb00f4d990a694e5a75ca29c63dd9104
275	1	350	\\x0f6276c476469f3594b8eaf51a020e1e8fd98a6fbea36fd98942d0f726f844821df6fc3c64bb8cdcd2f5a2d71729bcbc1d41d7b383d9a5c8d7c7403783ced905
276	1	126	\\x128462b0545ce8044db9687c2eafcc8bdb12e99df97c4ee1e43a4a6127510d47f7b4f73bc9ce436145f3992ef5a1e56b006c19f4b5047d6b0ebd6cdd6103480e
277	1	114	\\x5e84239f05d2e7c280fc7722eee869793b241e610ddf806a5718cb5e7bd43ead7a7aa40d0c5ea29baa98f49b7031ef900b276118ef979d647137d967a4825208
278	1	208	\\xefbe984307cec8dfc0448039494d48a210fc768a87a63c8d51f46b4d2c5542678f8b43c8035ae933a88c640cfb3abd7986d0feb3ad7962f6d0bd61e43acf690a
279	1	312	\\xb571647abcbfdfb1224720d1082becb95fd520c5a5cbe4787f1f57172e529b8f19b007a41fffb13ad4d6ae43d2d6fe9d1eed7bb17afc741791c5650c41c1610a
280	1	100	\\x8b6427579b8ec3f59852b0581d6f225f26723d5e191cd30e806af4fe7d1a8345308c01cd9c5f5a222981a5a5e32e67e39d709c7bf0851cf206fa2efa231c3904
281	1	299	\\x2cca7f95992fcdea9bc6c2def75d0e2c2cc6f839c8cd0c18ae05f8d597bb680f21cb0a7dde64197674ea6d7f50d3ce86a1689b480bfc11b2ee36a0f867e87106
282	1	67	\\xe11c4f3ec843bd2fd2f1f0f6a618dbdbef1cf0392980da5c92a74a5fc0b70f01698374ca781d7e6d1aa899b8251ee1295e3fb1cb0ae584039c736b691b038507
283	1	22	\\x6beaf42709b235905fcb0d6878cbc2fdcd6ffc13e5136e24cdf293622b42ab155ecc2003fca64eceb0014c35a827563ee156a86b11b005c0054b74b927a89408
284	1	25	\\x7fdcee7eb2b0590cfe5831b7d41f5bcbb19a5212b7ab5ba8a175db37f1491a233516c2bdb3ce4ef6cd5237a39cb1cc73b0167e948cb54d8e4f0e4490ec3e2301
285	1	3	\\x757fc44ec67c3442bfcfdffcb7507cd3ba8c9f763d81f3670d527c5950355907ae5a7709a9100be85f9429d33a3e35ab0a0cc7d15a88c266fa6a6a79e900dc0d
286	1	243	\\xa97f491072cb971826dc03ba67e76c25850847dadcaeca2f4ce0946f11dffe94bd1de3c6c6f851ec5fff600e549c982089886fe3142bb07d0aa7f03bc0181209
287	1	210	\\xef6beaf8980d8b18b9cf5de307e57e7853922ac13e1a823b6c165cf105d52665643b745d3bbbbb5574a03eff2f4f70f5a5bd1c3d8e309b0212968a03dea88a08
288	1	338	\\xf58b1798dd2544f52a69d3b15e0d6c809963e87f74c04519452bec5990653e5a2264d2fc44ed0d92094bca8ad6095152e00f21186ec29953d85ffbdb0f93c306
289	1	86	\\x8ff0d7b85414fb1ba0429afb6bf09ea0c768f6958a8a6094acb3b296aa60d6b8e62c07847b9d2fe7b1c07e2000adaaba6740aef362ec2ca52a4fab31cb2b0304
290	1	284	\\x57860756931f8e8eedb06774df2e331bbe9b85094317cfe20563feed40fd134db9a72220f5d18eb0123d87b23e695ebcdf8f38bb79c034e287755549a4230e02
291	1	116	\\xc68ee2139a54a857df5f5645b7f6ce5c3ae2ec0c24d8493c424285288c8e2c9d6819cbc269aedd14e75c6746b6c22f94c89bfed42ea64ec41525c8550c90400c
292	1	177	\\x2cf2c0bff9365e99af048d57d6f80e88d4cceb6339467cf1f6d1ee7375abdf17b8882126fbb9a34ad198e0aeb39a96805bc36f30950ae4e24f13882fbff03209
293	1	362	\\x416250dc4738d49913885b1e1fe4b30baafe79b88495370311d7257a55147eb443ab7d68dd7d26b87cebe31f9712f3906d4ca6825e5fef0201be15027410a00f
294	1	317	\\xe89b4ddba3f6f9a7c432170e9208cb7fc536b9e0eb88ebf1a89455241377ebd1f8fc0b6e8115bdd8bf1134ae90039f58151d56b80262b2ad1b5fb413a8c8d00b
295	1	50	\\xde30665120a3fea5925abac7ec2b95b28015b081b11bf89ecd4e79d227ada806a23603d031f0aacbd269eb952743fb68741bb9a90e666fdc234b42b4b2ffb20d
296	1	277	\\x146db153b0d2c5681a91235de3954a139aded7e4027c7a84da36f0f7ebc127881cf25f8595ddad46b636985d3b807bab0ed3eb4350b4ee449b178c27f894a505
297	1	226	\\x8dc68e0f872461e127801f379e0220f96a15561beacd3f2589488e0d44bd307e8b744fe7a0854d17e263f2db25ccc80a699a756c60290aadd37ed94c61f2bc01
298	1	189	\\x31feee29c6f9a770fdaaec009ea4b8a72b5a054122ddb2cd0374080aa766622b17ea67659368883e5a7590de798e0e7b3a290a438f4c44580ee30349b6614402
299	1	300	\\x343b084c681e32c3374a9d60fdaff22579aa470c3327ec23a02b638f958067f71b663281a280a296417599b2bd30039028f123bb753f138d9d6d337c48ee8a03
300	1	183	\\xdef59b55966b28c21b61334b2a57b089f956dd0c74f1f01cc87a0fd243147372f040bfaafb07421b5556aa78ad27d2cfb8438a9c9de691514c6a1d75e704d003
301	1	257	\\xed7f6a3c34bbe3bdfdb053d10f7dfbbc62dc710862c266127bdd8054a696554b97449320c59f750594a20becf43bbccad21f66b973ae05bedc3cf1e4a15fe10d
302	1	406	\\x1e0d1d8075e2c12c01ea4468d37a67c07a0313c867968eb73c2a4c5e515819ac627eb40fd1974f4fa94d9aa1dc4fbd2f7cf5275df199782730bdd5791bee7e0c
303	1	78	\\x2faca06744a9bbdbbc95df05664d5bd954bb5811835409f2f7e790594216e08368f0a3a53a72caa6a00c7b86dfdff87ead541f913cc7c30a5096e85830262305
304	1	337	\\xe62d1d8620f0189ad2b622fbc4d2b1fd4e205a8054d7652665b1a55e3f6d3e78a7f1b5ffad2bedcbedd9dafc37aee94e66f3b3329bc2c48585e855a390ea7a02
305	1	230	\\x23b556987567405218d83e61fcc739a22d542ba2917393dc796333c70c37a7d0dbb3b8a651d017a34f6949b1c9abbb26e6f9cf829eafdd52f63ea45083f6d30a
306	1	392	\\xf3e337084dc4db0b2ba340f307efac3fd3c77961dbae89ef3849ff930e616ac727ac2055c1e729efa087fab4b5e8e3e1da4b46eac49f895cc8f9665eb8603c04
307	1	256	\\x3c609f1962282c53ede6a66ed650c63063f6d1a7b5ddad6468821893c7fe4b7dd666d09ae4718b094862f52ca0a06a034fe233b427731af5015a24f065e83d0c
308	1	309	\\x761484c01907d15da0a48a417b9264b738327c746724f3cdd7ac4fb6c117a236767cb65d02cd9a0e85796b3423230346de9b97e2253642245985e453be695b09
309	1	174	\\x41dc516a3f8b69404d6f197a120af83227ad0bd66bbac6723cf37c648b2234e468b75f407f07e3d2c02a8003c6ae891f14580cae4f3c5b0ecc38b8644889db0a
310	1	215	\\x9e15bee330230a2b0d27553e5fb4d1b9e6973e07277b29afb536909cb89448ea4a4e1fc91efa94a01f94e7cd4b1a8875a9964ba6c1554088fddaae3b046f350f
311	1	34	\\x268d48483c234f07da918914bdebc7c8fbf506bc5e16b3e6585083d5c6a175899a8a73d0efc4e5e5457572217009b5f7ecc949e4df4b8d9d9d636e1449358f00
312	1	5	\\x907e48ab4a5d85c9282034df0e37f5c53ea0928a839051f4c115a934a711a42de8a3c86214472a7fa677e199c435283be1e6afaa74ecadd4bfe5a392e1a75009
313	1	101	\\x67651e351b613097b9d844fe607c71022fc67591c29fca0abc0cfc8257e44728cedce7b2a14b2e3125f2dc03d0c745d3d75deddd31fc82c3ac0b69ebf36a0205
314	1	278	\\x02f2b20f781b9d13aa1376758c1544975f14296783b72a04bbfce3f6cca0bc5207516bd1ca4a59d9d7808c7f07a003d929de4847d75c91b9eddb5e080ac7010c
315	1	304	\\x538bbca0a8f364eb26454fc02b7f411a4266c2adf807760a5d4f964e287f20b29371aac12066d796bb31428b0f5b7a52841e310a3fc7d46c87dfa68f8005270c
316	1	423	\\x40e7577d8a1ed3cc150c801c0bb77435e0ca4f05104c842245ccb9443ee1bbc238312e73872f2ddcb6188d0cf73cc5b0963a6d26a4fd023d58bfedc97c4bc602
317	1	127	\\x45ff5b9ca7fd2c03c4f6f3847cd0cb9496e5e19291032e22685ab56a752637c85d43dadfea263264a4372e1409cfa129d53becf508b16e3b82e4fd2ccdf40b00
318	1	106	\\xce7bcab474dc0d8bcc35a194668ce0d2bf5de02a20bbd6a7e988e15e671366b88bd3f896e41ea110cdf8f307cae7a284ed42292dd1656da1b54fad1012aa7b00
319	1	65	\\x80677f91ef3f7978ba197d3da67e5697646d4ddf1551992f85fac2d76825ceff8c21529ab71ae6d10995114fa031a991a98662efd0711b5907648031ee75a509
320	1	248	\\xd239b32ccd10016f73588c708465b0a5f1fcf987ebd93a657f03f41d25b0a2ce9f01f6f4ebcd958509c3313f7079af999cc96dd69de683b435d7805884616302
321	1	88	\\xa64110730a02bb30a1ca0b7d5642ecf19aefa98bdea01509a7d86e7581a35bb930bc6245d74b3e2acf3d29a5d8ce939cf5fff902d7e4bff5ae6f5e1fb041f305
322	1	409	\\x085389b64dc02a25a7835654107945e348b16fc6587bdaaf4a927bb54d812ae6dd103fe082891fd41243adebc89c2c9b909e67d6216b1e1d8d3666c3748a7402
323	1	275	\\xe893bd336da0ba909fabbed4bd8b9e0209cf2220daf126875cadb906e8898cb8eb92208ae13f7fcfb04b318db22d475b61a0fe976c254675027d9c5b9ef96609
324	1	175	\\x9a9ad16fe50e0531fc3964ffb675f108e4b0729aa9c6508f6646ad675de2d3d379b52b26798f9e0350c1c0f3d1c2df4cbee9231561189566242d2b98e2456508
325	1	249	\\x303af953c94d5cbe45c6168cb367ab5a004ae5dc8f379d16b8cb935e9762ee24efc0ca8b2a950ad3b3e8098be88e2457d5f84abfff8c8b2bc385c0fb66f0be0e
326	1	81	\\xdf72a6d439d0a090016ce2b22d96fb54b5b2b602a96399e7eead450dfe9f5d45d45d7f814654dd5dc66cb57f5b4575b85210e8fbdbcdb8a7794ae8e561ec010c
327	1	233	\\xdf831ad8d5a03d8c94a09f7242fbd1c535fec0e19bbd30ed178f66cdc7ed10e7d043f41743de732cdbbc66c72d973afd2ddc59c9fb1e38f82564f29372449f01
328	1	372	\\x71f06eeb2b893c95c611f5280ce83924efe93f3841c3d66354b68688d976c810aca0c24691ef358550145537f85d3f6c87e5f25ab2622cea052801e935d6f807
329	1	374	\\x059c8ea347ce8c56e74eb9b519bee22c5106109e5d9aa5b485fbb97f224873b16a8614caad263a5583136a66d0a3845e7eb1f337e69a6f35663efa50c3231004
330	1	26	\\x6f7c41cdef31bd9095a6f381256d0ef3a6a2b904c36b8d5038654856a2d347b79e5c467096dd375d56a967660b3f320733aecf1798d970d89befa729931bf30d
331	1	59	\\x725fb814dfb397a4e016b5b31b2093845811ca499376f46c4261518c8b11471fd56d773ed7199e3948bad84c1f34d446084a005483136d6ef675d87bbd262f07
332	1	287	\\x0c2437ff7d5c939e882f926d25c2d963c2f43922124ea388504e10f83746f0b33c1c325d08cc33bf30948ae8ac11cd3fb7d7972171842d1898a1e9c859a3620a
333	1	28	\\xac3def6f3ef7f1f9e5d794081b9eea2961dba40692eef6eab80b4faaa03736eb4d57f18f03f0d5df2016e475ca9d8ff2e268aeba734946d43c01561622569708
334	1	359	\\xf843372e3d35d9f3236b84a6d563ebd82600e505b40061f4766ed7576217a21184e1aafac7806898832af64fff50594c753b42ba76ef33a9718c582e7e735301
335	1	120	\\xbeddf2ed05ae125d93df4a8914af1acd9b753c814234305b7e8aea38d238f209d1dd3358afa15d7da61ff62acab2c4fd5a7900e0334f556beeffd358d9aeac0f
336	1	82	\\x81ac7927afecf8e9f0e165ae04e088d9c311fd42e0668bb07243971a2a77141662ffd8489a202b092d9638b6199439980883ce8b6096ee3fadc9b720021dd70d
337	1	48	\\xbecbef38118e95a6721953ec6902c68c7e5527fa617cca12c58e44e40e56a4b38442ddae98840690bf1f80de2f634116a407d9e3cb7ee2f3a0c930fc6aa1540c
338	1	23	\\x312edd32a84d7449642e42c6229f45c230587b6caa62eea2719810733c6c2fa277376244e783062d7ebc29a2c63129704ba9e0355e6bdde2f52ddadd03fa4c05
339	1	364	\\x55355dce1003abfb0562912f7c84fae55103a7eed66de2d88188d968f14eeefe65a85f6090445caef40221071df0db54e98e9ee057239583750b2ba516c1ff06
340	1	422	\\x0ec7beaa1d40ab77fda6128d025624eacbff521c207305a3383f944c853372c34831098acb3016d3cbdea2648863907a1fc85dbead3eb167f3699d3f5563e405
341	1	63	\\x48a4fbbc51c804b5a581b96bad90ea365e305f422a6544481b9a0f3cb499e51ce20d079392ec2fa5790d123faf51b1ad77c03154f9294b71909888100e38b80d
342	1	162	\\x1b39ec194c1f950ef4c045935f6320535c0c4a31b384d6e53f780a1b85d4294d7501efe1985ce83bedb819a65cfda7248bd2d518bcdfd6c1d0b448ef7a17990f
343	1	389	\\x76916c8759f5d973f060ab689be6bff19c23aa106e259eed68ca2a47efa6b886d1773858ef355b326595c18c306af1a6db3393b54d5a839e6663aab1c7850804
344	1	176	\\x0172c40a426baf44e23d8b40af0a0103294653bcda8d174c331e012a5b56d548d3e3a1132eb51b8aa80e9301c8d32d4d4a89f12522c0c8ba980003aa732a050a
345	1	144	\\x16db387032e5baeec905ddd2c63c5cbb7acc19a3ae1d01d6c6eb0174f32fe70ab05e373e918647afe722f9bd4911818a6fac597a7842fc82b1113f7047bc9708
346	1	283	\\x9cbd1d9496d59c313f5fc4d10b10e646db860b9f34243396cb7a5c74c1088e3f86437be476ab3a83569017b9bf77ea3567fc64a09fa0307bd189f9e8674ae005
347	1	303	\\xdc72d6d136454dd360125c3c4ef1a584484fe4100a49e863492d4fb939153427270622da5f7417c2a7209287687585eec25de09735db9a5b59e03a56bf833d01
348	1	403	\\xf1886b1afd2ce1b15d5b094cdf9c67aeb3700e5f9d16775602785262f1f5707a8c947e662db3847034e349b82fc9345c5546e90631d81705d708eecdb136a80d
349	1	40	\\xf63fd557d1e220f4b2f8d6d3fa3117ebf83d6520581d7401705123701ed9d07dddd78916ef8f395c23357b91fd48b08bf8e63e8beee7501e59dd05a0f35c2908
350	1	164	\\xe46daaf4a5c5dd5202a3b7025a175189c402c64976a0cd7642cd5ffb1e91c598e372db9a9938ba675ed1c71a6abdb8fd75c76442ec5f5e26ff4e0b78ddbec40c
351	1	219	\\x2b55844fde903a5a20dc0ef095ab86828ca5f70ef4de4b16f1915eda56ad8521ff41dfb4ad49b4d8427023b325e3c6b1fdaf1da5f0a285ea6d69f7224289e400
352	1	224	\\x3b88163a9a9137832efc4bbdb3b4eadd27dfa3d2031c58d91f16525d8db8298c023bbb4b640616ea1d25f55058e17d74c1fd66a0b3ac405ca8db7deccc95170c
353	1	136	\\x211d6a1ce9074ef052a65f914705b06ff760e49f1081e5417b34d33410e67f8b046da200a2120052eff5359f6abe373414f03241f096d5cba925e8d83511b80e
354	1	153	\\xf127db28e0cfe0a78bdfe47a79a764d5402a85f8c5efdcb55ebfbc2b96c3ec99548c4edbefa8dc36dbd76d07b41544e50e6b06701c98e03fd8cf27668989cf07
355	1	37	\\xc007a9747db13a92195e889c85873e6d4f80420629bf1ebebbb1cf793ce75b08821693e6d15fcf1fc0882bb099c5f89af8fed969d29e6b7a859cb73c8c4e900c
356	1	90	\\x05115bef136d768cbb912a9867e85a111176999285330054ae5dee12474e9279f4235db3df8f00be9612fdc7edddd7a20a14d6ff6616f51bcecf16f954025507
357	1	341	\\xe8a72c3c7353bb87bbacf05ae4484972fcb43e994fbfee57f57d69c73da8847388e7b4744e8a81c0976f6b6574cbdff4a356f433b66293d1c97cd96f2ddf710a
358	1	70	\\x4eb786374c188807747488a6ffa0e70393be1077646b3cc5ad6459090ec194d6cd6d95719b03857d67da1ec018a70a34ac1fa4d9d40c5d51e972657b4d09c601
359	1	16	\\xfac2e9210c568ad17f86c49c16fd4f263521aa8a88d2f65a8e089628cab1b798900fa188449e6db65ebdef567d4bfa76282521cba6b71e5ea3354a86a7e66e0a
360	1	322	\\x8802352fbef88ece52cd00a3cd570038fa6232ff6c24e821f5ef351914a96c9fe294dc95c64902c585b7799d0195ed7ad7867a7cc38843e97fa9289f10f5d600
361	1	17	\\xa74a7d5020890b1a52e8b6e21baf472097bc8dab7e54291bed5ed4ca79a926e23662d404db2c5cf863912cdf72f17c53566732968764e596fe48fe633fde810d
362	1	333	\\x5b9c8b118a7a869831cf1da41ff3c76af355edda69d0275ea52913223e0c0de5be50dc4f7685a2d213d916ae6f7d4e358c1a5501cf669fb330b300f79c76ea03
363	1	11	\\x5d4e327819d3512acc320faa22c04117a3572decf44ce6ded1a91048b569cb9f7831f22d9656d78a0f8a6cf6314948c05a36982a0a71c276436e801c02cc3408
364	1	10	\\x7833c33af658f5b0d60f565790970fded531a84cb944085eecc88835a24d29bd9e483077822ec3a10f3096289c364d7d8614e0faaca382135f5a3ae7c37eee0c
365	1	393	\\xe93433da1b5364c7c0994fef62acf28c4d37689026a6f130379e5f84830e175324da0998f28df40298b29794fffbacfe429faea17e40ff08b445a3572fbcc505
366	1	79	\\x0339c79449018e5d88f215c25c6aec6eb55b843aa2cd41788adcc200c44563e1fb934f2adf7afee01b340edc0444a65d2c325fd59bd315b11d2f2ff7acf95403
367	1	356	\\xc18f25864df2339794e53b3028f625428a2802f3cbe72a85ddc981ea95c2762c042c1baecf3b501215d8515e4075ac57aa842df3faa1b70de2ccab8fdd9ba809
368	1	56	\\x3e8fece513b3b39fb5d182bc74adf482d8e28aee403eefd5251c2a9390a5961ffe387cd38f9eccb65758d08d506f409ff44e50cf29ce4315b4175f8682732c08
369	1	89	\\x1b93101197945e81a7ee82d687008aef17f287931c457df99dc3df4d1975896e8044613a839dc5af18ab92ed0a437a76574a2420066fd55702ff70f3227a0400
370	1	96	\\xf17bea0a765515075f9b65a413cd9cd3fc4b804f1b970b369d53292794ef76dbce1716c466d3a38a8ef4a555faed4fa4aa2a885b7aec56b6025feed8d9ea250c
371	1	140	\\x48e0302a97ca6c078230a5561e1a5fb2b4c8f301a3e4f1b69e14fa392ca61be60569ae7b9225f51adcd2cea24f6f4883c3c23de89c4a48b17f3dbc5d8c855c09
372	1	129	\\x3748e7e84bd06f2acb5cd232c7793d6e995dd03a9d1061a1d9d154fee5f1cd157233cde5978f7c50f8fd2d7ecbc3da076ce97e1a5e39c432f1d634ef97d9a80c
373	1	266	\\x973041bc475a1c7a454bbef2519ed46f87885a5542c23e450a03b85b4ff1fb3ba36d9614604b36ccd1d94b6a8b25af991372863c7cf4c5e7d6b0ffcf2c09af09
374	1	402	\\x258e7d13c121bef5445245982d49c49ea9ebd2a804d6546e4eafd4f96a25046efa43ce013534ca3ec61bbb7ef7d4244ad9bbfe60eae9458330207075e4649807
375	1	200	\\xb113d121f8f7e9f12b3a4002127e54c73cbb67f2e0117877780e924841ad92f451e28c6c7e890b38bff7a75c1070969027b355407b2f8015f1655c049949ba03
376	1	298	\\xfc54ff86dfc312fdfa407c03ac5f30b741ab287b40e9251b1f04d99781eb6ef1b6cfc44556e87737d64170ffd9b2397c6159429b5527beb97f79acc353774b08
377	1	221	\\xee613448014010fd58276c3b862ebae0a48f58ffe63b4db0c0705863e28c5fe415bc7da33b20dd0bc72be8e774e4a37d40f8974c19ce0d3e38450a55839d9c0f
378	1	228	\\xf1172086fbba62b101e36dc3ab655bddcc3a58337721427364c46ddbccddd9a9b11e7e8b8e99a54a33f10740dab9973836f6cec65ad8e74b3b5157bf0cb1ab01
379	1	419	\\xbdd3a819298d5c4fd0e05aec4cfef66133bfaa1f0f76778a8ac4f793d9dc08ef525c01e26fc0238f38cb84d4c8ee61970c904ac7b56514f99f19283f9239ef08
380	1	194	\\x8cdf7205a67f610caffa34f808a820a9d37b797413f116047f5cbd5365f2279880ccfe74d4b8a81ac96c03a8ca381dcc66ffdd573fdb50564e9f99ac425da10a
381	1	72	\\xec47f23e41b2596fdcaa84815731fa1d9f8986f362196dc11521b1a849e00557c03e3b8d223f46f04c24d8bc8e0c4423556221187b5f04ee01e2c7d0b443e704
382	1	315	\\x1835b39b9d3aacb0f0289b53e832fa0b89f3f3e35da7d376b3419ed73fc0d6d689613570de0ddc1e9295448876e5f9b240585dcfb7fe5454400f3fd25c1e7305
383	1	262	\\x160e0c9c2ea6c3004dfdae7ff1c2a819d6627699c804cddaa3b21d491c6d0ee11f01a1f449e7ce8fb06c0fb385b6409404d8d36470d9573fde7b7a6665210d0c
384	1	58	\\xa6b92d82b6a6356f0f7d4676e08f749ba56cd59e19f292acbdb98fadefccbb2eafc6231ec01e4c2e52d4b42b3700531a51f8c88d614a11b9e3d580a8c79c9708
385	1	222	\\xd625f79b63819ed7a5e0aa36bfcb68143210fa829f181a00af4d4b819cfa699c8c283d316941344329e3d3fcbe4bad27f932a004cdfa9ad1457733f3a5415807
386	1	6	\\xdf1393c637283a74c27d41b55ba0126f44c361891fdda619d4f20c47e20c50e26e4f9b37c5a18bdc1ac5a55105800d7ae11c0cb469811f8e6fe6b2d043f0240b
387	1	141	\\x8d7bd7bd7488e99e45eb968f78ab4d59abc2bea54cd8d19dcc974935d318a3d225c428de01259c9b7d299c9580281f81adca713bbe06ce0c7c047095b0e1e006
388	1	195	\\x53193aa8d64ca617de0791ea9c741e25ee7580807a8a51e91b1ed9693795dd4fd296e3f6fddc5cf340188e233f2d8083fb4f084e987443ca4bce5fbb9536b90a
389	1	115	\\xcfafba11210b3fc94caae2172fb4a87c12cb4173a52e58a96eb538e49feb80bce6c990aa8559f94410d5c1f61d6fc74a544695f3200e5de291d434099a3ca408
390	1	64	\\x31743142cf64be54168d22aaa9c17c3aef328cff5f92c3e66d73cf37767ddf3c0e9649b60ad76bd243b57053591ce6103e43ea08c92b3f2bfb3c3eefd11b9801
391	1	103	\\x4b834e85a6647bf216f23b910f06cf784979eb149c5d90a91cbfe3959f55ff6aa558a861e7c7de494f5ca88212f42900ff1c1ca23f2302d84e2627df3ab0620c
392	1	43	\\xdfaff8da757c314c2bb6d2528ade71fa6050280ed26ef06fa79a9914a06b1bfbe4c49f338dcf6cb39ed28cd1d0591a9e75e723d62fc4aab0cdf348f76a8d4308
393	1	182	\\x5390b2f5dd58a5c806808dae38b54aedb926e9484c6b297cdeb77d56434051a52ae247e81f39dec23e9b93c54baeedebe1d1deed86911a6396d71556a994700e
394	1	111	\\xef38724f2284a01288a2ea01a39b7698452271347bd0263b1fd5c0a14bc126c038a9a0842a2508921046723288438a20772c7db14ff218b5c858ba67ed3dca04
395	1	160	\\xf7d988bfbbc42afd956ed970b4c8b9d81075b198f517e55f5f3e7470c51db77300915fc1eaa971a16d9bb2eb9e8fb5217b01845b0213327d89b72ea64fe29305
396	1	401	\\xfd88ccefb97ef998e7009d6e47a3b14a535658424b0f7b10599f2471400fe369b5cf13a801d00d063f115c15527df7be47ede28e28ed22e34a65e07137a93e0e
397	1	179	\\x292447dd808c5f5462469568dd20037a479cd3d189875132ac1288ae785a21d182b90b5c6c0367bc6ceba111edbb1b89dc4c45fa8be78223ffe3a91f19240d0e
398	1	21	\\x0cb6f334eb89130757ffeb5b6591decb80604ebccc6c02787d723d769e5ba814dd950a697f6cd1c9c2c55b1e45be02dfb79d03819e7f4ea92b5d26e44eaa7d00
399	1	108	\\x4e3f99a8d4ccca53a5b6217c47599e077186a1de71258b5ada55dc716d389aaa64be2b2f265e5090ad867d6376b3009475c54995a6472e49c3a3f373bbc3f00e
400	1	292	\\x9657cbfa9f535f0c650d7b4c2d43af012b8823b79dc36feef0869b9a01a776290727247e145cb1be0085d8373f50c30522d42245ed30f14a1c7c9739cb325c04
401	1	45	\\xaa7309ecc64701d9e58261e414aab71173a553460bd847c2c35823b1821dbfafa330bd8d7ba49e52086594b37b86eb5cd53dff61965ad363fcd3c9ab7047a00b
402	1	93	\\x240f2c8d8dd89be9b369a390a59d96db35f2df18c3402f52a930e319b8d46091b44bc8e3fc4776b2dc19fe8702808a922d72cd266703eb9d4fb0a6c93ae33406
403	1	35	\\x579819e3c66d6fb74a665409db609caa6a1fda214704e86f9da832febbabe6aa56542e7a8e4f795ff671fc922bf7bd96dc07ef1a4544b1014845f08a5537ff0c
404	1	216	\\xeefc084589caa4e24ba21787b40bd56de1eaba8ee100fab82d214c4f1131908a2be1a07d816b5b1b10b1c5857f03e981eaea890aebaaae1c9c896488cf9a380f
405	1	92	\\x2d080dcd78fba4f0b2b24a6af0435c98059193ef92cd705e6196d9e15779ef642a616b67f51d46d7ce91ef07816db09d30f7b60229114a5f3324a50153b06602
406	1	379	\\x987f2b169817281d388dd683a0fff0bcb83fc11484538956e3d3fc246ceea3669c54b89579f37e6bf302c16cb32034fd2c17d2bfcaef87575cbdca8123fe8202
407	1	345	\\xe1741ba9359cb35881b6fc07fc9de464d0dd40777dfe37cd225e526fa509e46159693570ca8fc1968b92f453be59b080c96a27722b020af4429e21927fd9f505
408	1	378	\\xa6bc99ec4ebea4bcb4787376fcc8125f2de090cef14b1b0639784a2845d58afab8b4fede7619ecf089b55c6dbb415062e55e6e4e99b21db144645fac4dd9720d
409	1	264	\\x051d3df7ff9d5fff92566569a45410f3cab9c4b2c2cda32ef43cc9502ffbc07c24bae0a2223c18e4c9ed1ec5edcd3f4e77eead4a2a75a631cd6fdadd71378e00
410	1	8	\\x4643a7041674918938b12a2c33cd92d388514aa758f493e213c68aa8e8eaef1349531cacefaafea462130faed7843859f12fd0f3cbcaecfdcbe615f730a9490e
411	1	214	\\xef279d8db6407034e57254d897f0f166e0ad0b9978710f1825a7b33a827684f764d564d956ebb353ad7379a13f5a2a33ebd8bc710cd3263bfd4a86485993fd07
412	1	352	\\x2e5e22654742ffc5a44337dcfb36f7859959302f000c556aeb0c406ebf3931d6246a802b0d90e291f1387b7ff1af028da30b41a694d66cd9ad46f35302fef40b
413	1	336	\\x7fa63b865630fbc9db4d4039a6742876cb22441bb7a10634c7c544da004774e9a51cfce116c031781e9ba98a59267ef753b1d456f38f357911c6863b9157ca0c
414	1	395	\\x1cfe2731ef9bbb0353ded3db70e7752332be166366b227178bf0c07181ec5febe7ee52bc6a9aeae018c9a0af5c9d2aeca6ee03c888e3feb841c1b4feb95cb70d
415	1	107	\\xf155263220702be8ed04a86e95004724c20d483821715ac0692a6733f4a64f43c41694daffd90b4e4a9b76399bc2f9ad20e4b6489339c53194beef2ebc34c302
416	1	241	\\xd0d02534adf95ead52f6df591845b4fdcf255941a73edf1321d406d1bd5252b0a2d663e18414554b7fea296850d22560f4a861320988aafd2f3105ff6f8b3801
417	1	384	\\x63523aa454ac00c10cd4235ab477698517fe0bcc58a500ebd981eb42f6ee7b073f0bacf7411e908d796bd1693ad16d2a2616640d9bdd2e81357e3e91ce6e2e04
418	1	41	\\x2531230c9c5395813b98b4be6d0e21a562b99511a96c1e9e9cd7653ec167b47c7fc727d7cc92cd5b03b076f44e34239aad1573f1a2de10db4097ad701a463909
419	1	123	\\x7c5a2307ec14e3c3130ee77cff571598bacf654976c02a8c7176ba86ab90a11d03c31fb2553672e42e2b015cd487274e45057c27baf8486878189c9fdcc41d0b
420	1	220	\\x89c18128f2ba8d31ab1a72cf390a78cc89b3157ca0f404f53f46c572d722f6434acea9a4e970cb1177d0b17da7dc4c2813aa6a0baa18143f84bf23fa69c0490c
421	1	236	\\x70d5fada49bb4151b5be82d04d1d736f9db28c21f076f29a71869fa4bbbcc14b1023137ed9772545089cf07f8e2b0cdb4c5393724a31f46c429a74f0f09d6d0d
422	1	159	\\x36a6f45b39532d062798ab81b5023f4c274464d7de8b64410d7801014ba9dd1d26ea96ef3fe9006455fae43b9e1a0e86a323ae46f3455b36f4a45a74626b6a05
423	1	307	\\xa1e8d3d7d97ee9aadfaaaa31f107fe33b6c2c8492657f3d36252a01d5619ca8f0cb1a0a21804f8c36b701355a1179f6866720c436b0d00967848fcce92179f02
424	1	288	\\xa70d487bd1abd79c3d997b1af03ff3423888350d8987c362d0f38dec3d749d06fe78f4ba154ba8caf33a5f3a8dcce65adeb8eb6a016d748cdc2bbfc164d87e09
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
\\x6027c5b6522f811b9740a957d7379cd8410a1a19bd114a9e885a0976e3edfa2f	1650825006000000	1658082606000000	1660501806000000	\\x21a32844844732f30628075833efa8e6fe025589e2efd9fa2ad7363162c3a148	\\x52410d223fd9df23784b769f27a505e0e3a210de3854a9795280900577c13a78583bb3f3cb648d4ce19bb56949d4c3439fa4a2acb8837da070bab000757eae05
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\x6027c5b6522f811b9740a957d7379cd8410a1a19bd114a9e885a0976e3edfa2f	http://localhost:8081/
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
1	\\xaf0c03a49e6778fe49f369e331c1577d5713a34402e97b6af60f609fbb511173	TESTKUDOS Auditor	http://localhost:8083/	t	1650825013000000
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
1	pbkdf2_sha256$260000$4t3ROYcZ1qFgwfFo0ISN1M$Rwwf5AzJBG/0nS5u2PIghYRR7pJLYCj1OFjUt/ZMZSY=	\N	f	Bank				f	t	2022-04-24 20:30:07.612271+02
3	pbkdf2_sha256$260000$xPNDcMUqxg4xi71yxvJN1u$sVeLgcf1tkLWNtsGOVvTUvYgkOqPcomIbj8u2aTgWr0=	\N	f	blog				f	t	2022-04-24 20:30:07.804299+02
4	pbkdf2_sha256$260000$s76flD0XCPULGhGjvF4UPv$OJyORNsNqGoGpcAW2/Fw3qYhjqhls2hI/mvyuIW1eaE=	\N	f	Tor				f	t	2022-04-24 20:30:07.898795+02
5	pbkdf2_sha256$260000$wcK3IdKlncnEysPQsGtlRw$IdXIWqgUpzn3w0C9DwmzYKEWEwn/PwIhoSXJLcLSr6Q=	\N	f	GNUnet				f	t	2022-04-24 20:30:07.994589+02
6	pbkdf2_sha256$260000$hM8o3FJlI7DOhnxHfHJ5U0$EB7ABy+602s2DQNyW8R095CJsBc5ZFUDqOeNmrZv0N0=	\N	f	Taler				f	t	2022-04-24 20:30:08.090307+02
7	pbkdf2_sha256$260000$MJMrEU2sxoGXBfPIqoK1gr$qVhziOF7NyolT8ePa4wB5S9ZzAhzoTlRl9Jo74oHS8c=	\N	f	FSF				f	t	2022-04-24 20:30:08.18595+02
8	pbkdf2_sha256$260000$URgzgiDIPmEoCPbcHQUsFK$cvd9rK7T1WbNK3JduMVSE+uwyCRcfOVe+BZC+cX3XxM=	\N	f	Tutorial				f	t	2022-04-24 20:30:08.280739+02
9	pbkdf2_sha256$260000$cpLPPlzr3fdN6zJImLewCY$YP/kKfnSG9YD4bBVai0nznVwdONwD5bY5iZsLWTnmP4=	\N	f	Survey				f	t	2022-04-24 20:30:08.376881+02
10	pbkdf2_sha256$260000$QKfFog8JfcWQDqNRUIhx4Z$siu7rR5lRG6cousJNBWI7xiUh+qokjUxlWxdm6iJzIQ=	\N	f	42				f	t	2022-04-24 20:30:08.841192+02
11	pbkdf2_sha256$260000$lun3PwDlYobdmx91TbamhD$BxPyXvtZ/Pzg8wSyZdf1OKo1eVSR7fjObPl7LIaTldU=	\N	f	43				f	t	2022-04-24 20:30:09.306323+02
2	pbkdf2_sha256$260000$DMLM4CpFQm0MMRngrv8VAv$aIRqhwbqraTU8ISYQRHuWlwz7hwtZOkONiecmJvb/dU=	\N	f	Exchange				f	t	2022-04-24 20:30:07.70738+02
12	pbkdf2_sha256$260000$TJ2DZtG8ysycQBqBbr7u3X$nJlBPAXud9faP5lFJONxpqPml0Rkptb/NZ3cfPfKE0U=	\N	f	testuser-gwvpczet				f	t	2022-04-24 20:30:16.475385+02
13	pbkdf2_sha256$260000$wadB8dGzZ3KnhRZU51R8Y9$qSMx37oTgy9PcPatz+Yd5QFsWqIKI6jTS/l4iXzpfI0=	\N	f	testuser-jfbjvv0h				f	t	2022-04-24 20:30:26.903022+02
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
1	\\x00b840cad9059eb41cd96bee7613a01a7ad018b5a12cc69319caee0bb2165c260965842b4f04f62091aac91b92eb2db5b443ba81ce4bdf1c0e510615109f3f39	1	0	\\x000000010000000000800003ba4780ef6989ce6180d45493901716046787ebbed4611516b24642941a3a0e424f47a1d03c8eca32fd985f80bac9d8bdc59ed3aebde75ae4cd44967f123a3c74d5eb6090d23ec558f0ace67c891b89178f314a012337b29a280e791e5186373bc880045e5091c075beb1b7392936c525c176b1fc1b46eb2e95e2840cca941561010001	\\x85ef38bd2c77b2c8acd2f9119120362a1093d146afc9b97ef96074f43fc98eda6ebffbd66c97eb5f1516ebeeb6f8d79c1edc66bce5e158c6cd761fef13358301	1681050006000000	1681654806000000	1744726806000000	1839334806000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
2	\\x0224a0410b4d66900447b2b951a104fc759c9a9ea7506f9c8425377aef74b7909bd524e385e1f0407b5e6d284e4bce6a12b606eb074716d0a8fa885fdde81ac7	1	0	\\x000000010000000000800003c3ba680104a30a47843119d6b79c8aaaf67d82ca014bf8025d21b43f27a1e443b8fff035e286d5e0d940edd43efa5f5d6b20f16ee76d87e062b533e23fb0dfd3528006ebb5950a526b9e39cb3110d067880fd9a33c94c509b0ec7ee19a81f4d757271ba9d6b8089d890ee061c120f77806c68998e1ecb77485b6b4c9c4d5afa7010001	\\x0f145a3ef58dd160e92d2b5839df4bf5710b1cfe6785dbcf3d1534e640f0df81229d80cf77c422845cc7bddb6c7868c764c6d825fbbde2675dde98527f9dc60d	1662310506000000	1662915306000000	1725987306000000	1820595306000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
3	\\x0914b7bb9ec185c44be4e174b480544911c34c415f7bb586525fed324bcc157281c896de6ac7e370b956873decc7dfa75b82cc69148c793c9cac1bac914ac033	1	0	\\x000000010000000000800003e45b748842d5d24703c7488c66d124488d73885412dd0a9d94d44e0eb2cdbeffdbdde81db862dc559ad8be98ffce9f49a46d21d697f00dea09b6c13f384559397ad55d19c995d2691c224905a4ba49d96c9b91ceb6426df8ece264eaca1569dd2d22e2bcc7b7830aaa9e090d1c930514e821d88b0a3553f0c115c893a8dff655010001	\\x29a141fd4a1d49c2fd7080bcf22c801d0ab42dad41b0c63338d035479dc1f1fb4b5d51ebe63114a5d43af85d7fb513b3e18afa997cffc033a8c71d65cee9be04	1661101506000000	1661706306000000	1724778306000000	1819386306000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
4	\\x0b4830231caee58be6cf767d85bbb99983cd146d42cf361264fc47d076ffc53a755c5376688b227a731987eb916fd7fd6ec775f043b15eeac6e7d5fbcc143891	1	0	\\x000000010000000000800003b4ca5a4964b3f641abf315180f541f8e58df910808cef3de99a0cdccf489274b3aefad7b1acf35ded17f06e57846eed94800b3684e425684227922108edef0445b60944ded23dc6ebf4595f96f2ef9c8dd1f0924a2891c57e4faf87be396b9a342a569d5c747a252eef0991e87ac70dcfc4ed4ad23786986b0328ecf94d9a637010001	\\xbc516dad809c5af0022fcad36ded552b591f62b50aea51274ecafa681ef20c40b33bdc9450050fc1a2405db42557383dab97a637e229452822ed945169bba407	1677423006000000	1678027806000000	1741099806000000	1835707806000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
5	\\x0d70d08c627dad8b3cc0ad6fb88183f679db56ecbcdf82fbcb745ae6f1cb44d38ecd85fbd01db89d4989b8615b577a0bc9ebabe337d9bb8cd0e871ccc955ecd1	1	0	\\x000000010000000000800003c534f3f92200b38eca1a2ccd05d41cad83b20e84c3398027e626be90222fe5f6c69bf403bc83f2538073dbc6032b17a67a2c6f40ff226b5909eab50274785a933e5809da5ae85948b8e1093c8c92307018d5572a7352242522c6829b102e5e1a547e2526c80a461696b6d8a872d4cf794917f4ff46c5cf25b1b81886d5e2f419010001	\\xf70581952c6d7ff3e393efca09f8007101500c7fb6adb3a01f465b9fee754ab8032cac6d72603afb96eec6c823e4a349b489727bd03c27e9f3d68b7c68eb7f03	1659288006000000	1659892806000000	1722964806000000	1817572806000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
6	\\x0ee814139baa6b615d4509015348c71b456b1bdabaed5481cd094ff4bdb992f3af01d1cb876f42eabc499ec1b6b846ff11b729a01b279995820179e30a430335	1	0	\\x000000010000000000800003d5236872ee6b65f46ceda3bc2e11d7cfd65165edaa786fa277fe479eaaecc87a75332bc53975ff0c01e9dcea044fa5e760855162f5420a2f813d64008e66be9b6904d03d29193759d17dd502cc968d034e697ac169df2c034635bb3a95f3ab471ead91727b156be23c389bb21f849899ecfb86b17d79bfdba2ca941267ec5847010001	\\x3de0dff6e3fdf0ba24e6a7600a45d9952f74e11630557839d162bb8d92f8d3306ee6287357a7c6ecbed8ea98d447461ad2fee5bc4007688205bcf2245599fe0a	1653243006000000	1653847806000000	1716919806000000	1811527806000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
7	\\x10400ce8d518379f0e76cdc182361e3ba09158a140d8af45f9d3cfb325ce84d432936e0c8aa090b03398c0559de52df457f48802be9c74bebb202edb6b502a4b	1	0	\\x000000010000000000800003b508e2cc1fc35405de7312973e5ac8d20f043e22bdb65abfb95304c3eac3eb0e93e8fc95a39423fe599f9d55705ca45b0b0e409bee662ffac6c03a31799c878d07ba8363641b0123856dea3df8358f901016d9c41a941494e1514a058289ab85d411a428e804e1cb2c8ed4091752d61c83e0d5ced5373ab96545c93601d4f23b010001	\\x38845aa56d91518fbbee9a34d9d2fc2065f6b5811d5979c9b70b0ca3afaae323656d564749529ca7145e9f2e9276bb107d5315461858841e6a5cfe5cefaae305	1678632006000000	1679236806000000	1742308806000000	1836916806000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
8	\\x1174eaa62aa05e5388d730c98e47cd274b5a33b13fd08933fadd53fa669462c2388a07e33801f2630967ca94a54cf98a9f1bdca9711e0dde4fa1d61df470208f	1	0	\\x000000010000000000800003ac680fb4e0b1a109388f634e546e1f1c091506f28ba600b68c9303d6b0b71a448041ee42af616f5e45fcaf8255f2e2f315da340cd54fe2c185d696a0d328f6bbb9f8beee806078c0a117efd5c2a0e5c8359bbdb4d3f6b7b1524b474a5a9481b99575fa90406de9dfbe0012ead5f35dcbfeedaaa088bcb39ec7a070711b2dc311010001	\\x4d7228e7e5faecd4e660124dd028cb53a118cd520a015e1232dfb9aa361c28dc9895118bee29893368ff868cd404d55472e20f3bf1bcb78259928b92efaf600c	1651429506000000	1652034306000000	1715106306000000	1809714306000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
9	\\x11cc6d16c3b41d475f4cf2d8dcba25f4dd7b66bf333e345c4d35f9b4ef1eb5254d8104d11634686a26ac89f482df7f12845ecc5a2e4f650abcc61f47aeba9ac5	1	0	\\x0000000100000000008000039fb0d00d63fd403f494528fcd73e068bfd221931df04f8cc95cb4f55d02ec0df09b8182d29e82553b83acadf966bba238a6e354f31e0e666840aea9487f4f4df3699e9358095098ba18c81783d74ac22c805af4b230291de14d910a9e4c6a76683524a1e62a178f24ed8011484b308aacc9164c4a7d62a5445c1f8ef0cbd09af010001	\\xe03b92224c335240b83022e714bc0790c1f0dcd9ebf28a2f6e87b57e28ca41ca8bc11a21004747fdefcf9a19cded180908f7ee0a8d52452c6bd4ce2ad6ad2c0c	1662915006000000	1663519806000000	1726591806000000	1821199806000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
10	\\x1298767fc7fb573f591c57911c34409c3948e1b2d201e39a078aa8432e37343603a9143ab31368fe748141ef1da96401832830a7fce4207c3ac39599457efe7f	1	0	\\x000000010000000000800003e505163eb6aadd87e47becd897c7285df8531be5c8683eb501653e6a7aad84411ce02c8c8561a8fa854407f7531689efa7f06f460a96fef26047abf31ac56137906e51751ff9c4f94686d104cc6bcb610985265f3fa9dd7971c4fa6dcd3ca489cbea5820848a76c6907a43f908b48063bd2984a3ba19aa544361f0907016616f010001	\\xa5cc8d0d233f961d7c4cdca216b72da0925395bcf7c06265ac5d4b969043e67b2004df93059401a1065d6aac9db3bec9b6e4bb1b94aa7d31150f86056b42670a	1655056506000000	1655661306000000	1718733306000000	1813341306000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
11	\\x139c184fc4bad89020d1f1c3298fcf9bd5c470c60f3fe1a7faca5058b77f56842b3806d8cc52e76674bb9c5980f9f2daf303c2f89272ea6f3c055c6cd85d4f77	1	0	\\x000000010000000000800003c6fc819b3d3e4fa07472de4924b15b86eab592032c18be2fb63374ecbe3f25e287f8b1cc58dad4cd7729cd66c135996c361592f3f155dc20262b7ddcce9b2f5a063bdabe1b2995fd800053f120fda0e23d6fa032074aa370bcc75246580ee70ab2f0a5faf78349eaa1a91a362d59e45f8675b15ccd5cc1840386a1fc9e450299010001	\\xbf624cc255894880fb9c4491c88a6803d774ef97f407cadc00666cad1b19dbd6a3183c6fa856c7a7eab5e2425119eca766fd606f960fb9787b55ee82f72aee07	1655056506000000	1655661306000000	1718733306000000	1813341306000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
12	\\x13181a7ed1f3d27b138e4395e821d2f288cc942598c5cb2a27783a6b6acc95fb6619fe34f6b80c7e0bba73ec7e2c8de6edf491e9515850d804b8f5d942276298	1	0	\\x000000010000000000800003a53d8fc624ccb3b47f33cbf2ab76be8c4863aa920617d9caa50004729ed712ca2a7185d12739aebccdba76b967b45977bc45d2e5cc830d8201f2375dd103358fadfac497f03a4e90f9376a38b914d6f571ff94206290da123b7290beb46bed938981d7c373d57f124291a806281ffcbf37ad680af46933b844d44b8cfae67ca5010001	\\x337d3dc7f6072f3a736c5876df127f307ad7d4bff1f5652b193a07710c18fceec35822e15c4045fabad50ea107c0c708d9e6827b4f0bdb5c2cbd3a082f465f05	1665333006000000	1665937806000000	1729009806000000	1823617806000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
13	\\x151c55abfb9be6976c971c658508b897c4d2342a9742ec63a3e6e0265ff06894ab2d1edb5e54a5ce897e69c39257fbeafc544416a0f0e4622ae22f9424cda79c	1	0	\\x000000010000000000800003dbdf60f5157af27601524cd5f3e7ffa4620c47c78456b6ca7f2b4011a94acbf94791161596074ff2715181280a381f1dc16650250842881b99375468af9603b91828656ffbd782548189f86bf7126a7fd97fe84af4fc689629df3bcd5730062e3354d96b5fa61285730e41cf3f5ba9a30a634a0c75aa4645af162d7790e774ad010001	\\x20b61ee26f8a39e886d001766bbc190c0b18a53ba1298647d13b1578367d0b0b72a0c14f06075c18acda13506ed983a44ec052abcff5e3bd144e62c1bd16450d	1661706006000000	1662310806000000	1725382806000000	1819990806000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
14	\\x1e54c298087b0ca67d42c3d76362158b81218bf0b70a12379f78c57ec2a8a8d9b1c919de90a35ac7649286157eb0e5457444311c48a17d50a648a4943964f14f	1	0	\\x000000010000000000800003e2c816c6037634cb5a9cf10de9532b1c2a7b14810290326be2667c51c9fe929694015521aa7fa6168d10837ebae8c32cd42b89a0e299702364a475cda6ee6a73ce705873781fb00540833468247c6b36f1c2684cb562cae2d495496be4178f6173fa7c76280332f49b4d3ad74ea0c6d14b37d0256ff198c25a7a1db0339ffb6b010001	\\x72529d7efcc7a0a1ac4deca650f4f71370d943e53d4d8ce57d0559d759bec84efebd62494ac21103a15b2a9246e89d3909cd07254ccd2c9f42f2a1e439d8f705	1673796006000000	1674400806000000	1737472806000000	1832080806000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
15	\\x1f7cdf04102c87176fb78b327c8223c75aa80e9e6520a7ddacb6e1a551544df93b07bd5a7a5a8cd57a492a34d080fa269f9baae993cdfec7f9c3316a542dd60c	1	0	\\x000000010000000000800003edd2f4ada2ce84f0a969a8d7961918ef7d580820ee4a5695f2144c91c3ad2cd031cbfd2bedac6544628944d0df295d29ac5164d01650041ef271a624363496e52e441b18678ace3cf15852653793c065d530d0a376f95a58f161a1c26ee0dffba7ec12e6e4186f13cba7dc02a863bb02748120728b940f431bac9ad01f68ada1010001	\\x74753e14a75b8d2b7c353fc9c25eb9309d140a67c6ece094d042591c6d64e8d2f455d27e83d95faff14c8540a1e9f0376d869ef90e0bfd93b65a593ff42c0e07	1682259006000000	1682863806000000	1745935806000000	1840543806000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
16	\\x24d8f0791c43ec08d48c63772dc631fc4ace44ff819f674689ddab7189150019934d6a960bdba3b80f7d2de23c50c9355df1d1c827b7b5c96cd66f37647b3d74	1	0	\\x000000010000000000800003c73edc79757e3fee8fcdcdcef3b8b6e065ae20927ca1c3a018ca3320c9caf27c10d79f8f0361efc38240bb3ab076a564645092864d9926046172c638766eba970d8caa617764486193189b910683dd1e71d8480736a2a6b04cda0a52beb5be2d398d59ca91f69ed21241b3d1b8e7a4205967cd22e8b7e50b4e266b2413371b55010001	\\x9741b0d6852b2c0b11e8748829b3b7cf16fb5ef5ff8a6cae74e5bfd9e4778f853a28d27ea8f35d526566025d25b0efa540f369cc6322e140cf2350bc86415900	1655661006000000	1656265806000000	1719337806000000	1813945806000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
17	\\x25fc827fbc869d8a9f9ffbda9046c195c0852dc31284bc29bb5a39962f287f256647819642c15f5319daaab372bdf5b21ea4883c7965b69498a79f7c1220b022	1	0	\\x0000000100000000008000039701459435d03691ec22ecc47b41606f25585b4225f59a152b9cc0163be7b7cf773bbf9d979f1e97e9e901603d897c2b07d37e6f52b79606ef8ccd0d59878f26492eb725d5f9c413ee84752267c730f143c391d07047112d524e57d75ce24667bada05097e58b47d5a2aef36bf5de19f8e49ecd4e68a4ca4b78c86b8c39ea171010001	\\x7bb4342e9dd31dc86fd10fcd5fd20fb49adaebcab5e145b772bf73359c3f85a0cfe0192740b6b66d3a4e9f1aad3ce423c6707a9136613f645aef2811f1063405	1655056506000000	1655661306000000	1718733306000000	1813341306000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
18	\\x2760156238ab76e358caa234e5e44600b84b501e4c474f69472b7408a7845e11a02f6f775f54bc425629f137336a3076fde17aa689ad6ae9d293a0afe583712c	1	0	\\x000000010000000000800003dbb8857e1d077fefd1f4ea793dc43b215df49dc62fe6bef143c9c79c26645aa55689c649cb1e7275ceb41a28122b3d7225d3c69c3f72d54425d7b8ed96e93fcefce72fe8b2c1af29697c5f752c88ec24b616c3998662348bda6b6d4c02d8ce98add6cca96155bff13b0f5523fe18f46e47e8f06c63ac5f19d825b161fdfe9265010001	\\x80e939dab0394cffad5b7f449d6d9b277fbc2e84216afa0251953a3a444739e8e4906d963376c55a4e9a56ee7e0e6e50fb7d1969d06359fa523ef52e17f0c30f	1671982506000000	1672587306000000	1735659306000000	1830267306000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
19	\\x284863c5a9e760c7bfb0749401f7b58cd747c5a55c2778c9d2d6e1662d64610fd59c7843d63e0bfafb4a6f438ca001f5abbcd0ddebd9804fc564d28f4b6f89dd	1	0	\\x000000010000000000800003f6884c27d3c8a597034e75435f59dd6c553498d340b611eed7835d55161401b96e610f82813d55a6d20879b8adcadeef5501771ded6f04755887610d624b0fce9bf750441cefd6ff421c8ca55c314d883e8b8e33729dab9f292a6550b13359ae8a1ceaec6c7c7ec7310e8d0a03d23fde8c6f6a806dac9d269d12a75c8cc4a181010001	\\xd9fda5cbdbc02935555383d56c7b0b7a5414e472453d01dfb543f52bf2d77f484959970aa3cbdef13d6ce0e82ec2788a9c539074d4a4ae039379b99f3f337700	1673796006000000	1674400806000000	1737472806000000	1832080806000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
20	\\x2918c34d764f3cde0673c86010020eb352ba6ae4376d918c7b8d124e1ec4599993fe5cf1376213c6942b1fc3daa98a369f294426a3cd328421d1bb3e27b36f27	1	0	\\x000000010000000000800003ae016ff9fba7fb1d30271fbcc0c2b5a9f81fd0a67e3436bbaf89923cdc2818d9ecb2ae7fe007748d5f440ce337237c48e3ceb40c340b4857ea6843beb81d74362d0734b0e40f7d2f5515ec371cb17005e5cbbdc385cc261b8d1d173f40ab277959b1cdf01cbf117b329c8ba386f9fd3ce89adabf5c46d08d66c803da0878764d010001	\\x7ca2b5733d3f3e503523c0dd77a9bb1e1bada9f68ce24c276f9ade01d02f6775fe043a43217d0dfa41687dff341a282bc7993c9b0ac94a4b2df68ce0fe859802	1664124006000000	1664728806000000	1727800806000000	1822408806000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
21	\\x2ad087e89f6e008260ee7f9a1811c80028e6a27a97666106e8cc298e836b688fdabd655c98b3d4504dea0eb4bdd91530d44c4220770432e850bebdde9177c6f5	1	0	\\x000000010000000000800003eca32448da42b589dfff45f51ea17b2e99b944421ec93c29fd9c49ea7f51f9281e025865bdbf58e73a515cc521a3d52f6fecc060289abfa94038eaf136d471f6c377b41101b59023e52ee7b64b2020d99d352a07d930b4ef9659eff07c39709d93e8e4ba0fc3ba6d7ec8e6ccf8d0af4416829b1e02b59d5c7b79ea9c67ca1bfd010001	\\x346dcbba102c49f6398dac5508acc26e16bd87727f13aa32145ef879b2ec8af7f2e9d496e1796e6c7020d4779aa443325d491b041a82e07de711fcae90f4f70e	1652638506000000	1653243306000000	1716315306000000	1810923306000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
22	\\x2ca82c5eb1a5ff439795cad750cda8831964b168362eff13c2aaf8d9470b0bb0d80876bfb1672eaa622a33d6e02fb5ef69fea4b17b8293a72f943a4b0c8aa414	1	0	\\x000000010000000000800003c4c3c1d0a095272adcb4afcc37fabf81d18690c18cac408bfe587f2ea9cb1bc368431452d2ff543e64b882f6ca43b38e95dab6ae9c184c5471fe0948836dcb673f539925613ed3dd2a606c0250a1349a41cb68b815eccd7d3f05e181bd1e6fe1fe36c8e819fc3bf711af8ea5fccbb37f224bdba3a9dbb6ea7b0703ce8dada66b010001	\\x710f8e797691ebbf14fd4629aaaaaa0aedfa5e46511ce5a03b91589ceae20b2f1ce7c503a6ba24ee56fc11944b7a556bc1f4421fdfb3caf43883c01c4f502403	1661101506000000	1661706306000000	1724778306000000	1819386306000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
23	\\x2d000eefa45e57436c1d7bec4e62d0082fc29e42d219f82b075e817839393dd974a2d46107d9e9b5d7ce424029df4c62be5a63644a6d3e73dc37b7fc3ff746e6	1	0	\\x000000010000000000800003d4cfbff94a072fe0f4ccafd04d26662aece3ec549b5da61b8ec45c9c2001314ebcbf2a42b61143d18fad442f88e33cefb56683e526dcdf52decc2e3e0500a9105629fd9d3af1fc743fdaf23a4bebb43eef529ecced897c99956d763e1c858ebe25c2917d77d52409327a4ae1c7dbcfef7734078fc5b53fb8252762176d027c2b010001	\\xa235a157457b25937484d662954b92ca020c3ce2406172e030b64ccf09fa71de1dae1c1aeb77d3ad4d4d1197d6de468f1c93f10bc700a39b6e3e1f4294021806	1656870006000000	1657474806000000	1720546806000000	1815154806000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
24	\\x2e2c1b04a8422a7257e7c98965ac03adbdb6e44c847a89db36d6c8badc8c9940691bb940d5ae695d223d3bad61ae6b583981d73d626f822314a049cb9d0e676d	1	0	\\x000000010000000000800003b3175aef63428f1bdef0d5144022b0274331ac535e472be728ca01e1f373e698956a785fbde68c2da1cfaa10da9e51f7484b550389c6887e0ab458ebc497dafed4a495f862becc5c2b059a2e02c0b89adf2f2988be6b4d03ecbbdfd5ee3eb444d1e5160ba849a1c522a61cbb0d24ab27cc00996798d7a8efb942fd57afba3d15010001	\\x150607f0d0a0f1d9c61a61d4ddfa02181c920e9cca2523c5b6726b7ed1388b6b10a14c9de66284feebaa16ce5c63d55ef5a599f600b6d4d01226db6d9791d30d	1673191506000000	1673796306000000	1736868306000000	1831476306000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
25	\\x2f0c64788ad3e5d02d6b2eb9db15a6baf272c09d3a3c21f36019e7344b51001eb207ea49f7ee06749aa15164dcbebc0e5a72ba464caab06080781da28eac027b	1	0	\\x000000010000000000800003d4476039156098cf96c184afba52291a547f832f727ff0af0e40424cc460222c0f4a7cfec1f24ff160ad6f4af858d039681c60db102108d33a84849ef8feb9600ef665acd7efe349301415b9029546dc669f00b8733a9ca976fa24dd43ac4810abb352808a94305c79d05e42233f522273cf9d37612746c5611cdcd0a6d74125010001	\\x6d2c98332cad6a5e9c969716daac4f90cdeabce211aa5632beac4278748803f26cf4331d5b4ac645addf797424d0eaa3ed39b101f6738ed2736558a100202506	1661101506000000	1661706306000000	1724778306000000	1819386306000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
26	\\x309c305398b2c92345a9250d0e80d2d56b278d6310a8ed6d9249632f12b7047356d0f7805c26cf2fcac6f7cf832bfe9bae802b3eff0b43cf13ac8a1170de4f62	1	0	\\x000000010000000000800003bd62cb6daf8806ca53b569e685411f6dc576e529b6a3c060d180a3d2b765f5110cfb302e3317f10246938450b6cb166d2846622fde857975e35e6063c2eaa04ddb33dcd8fe55b1b018f031545d3e343cca7ecf57efa210138e0a14ac84291de1391f9d856735b2e12d48ea389afad22cabf1eb0176c86258440304e60b690649010001	\\xda3d33158f293b1f1ac35a22ace22548bd7cb56bf4749376575b5ac1f1ed22156ad1ae6b2b4fd7059ef76ee9f97602da7dcaab5bf6e9c8b2a0261c16ceb28101	1657474506000000	1658079306000000	1721151306000000	1815759306000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
27	\\x33781fe6406aca000409fb64b0eb7c2a8fbde4a2cebb841623a92c17ae080f8adb7e4fcadff13fa73d8488a69788b48bb8546b3c3f94045933121c812da07a68	1	0	\\x000000010000000000800003d0281aaddd22cb13a73648fd5846f52b55e0ba1e689ad9a22d4352862ea069ea119d9bc5a9797a396cf7bd48685276d3fea23e647edefe9e93b2dfd786fd075cb4828039931ad6e6d72b4c4748b54537bb9500373bec77c30d146a6e8d07d7472dedd4235c76b1c0415d69a6c5ac04f76a985eb6f0970d56e70b5ab2a052b083010001	\\xfd2adef4381989e8795ff85a0b3216f506e2db0250ca474fbaa582935f57fac4c27433c39505e7483bd4217a59aa1c4ca00ff2da1ed3c16269ea110a1163e70c	1673191506000000	1673796306000000	1736868306000000	1831476306000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
28	\\x35f05a604ef1c6a0bf26fa4ce70f995a4e560b3d326196d62ea87b498da40e6a998075a9c52b70ff86fa77f299c8692ca3bd710758d1fe03311169ed34027c25	1	0	\\x000000010000000000800003c516f40f2870907843eb8bc6c57cb15c3b566566702f3f1a3a75baa93aa1f75f4a30b90bd4d85c76396ec1c50db8765d0191d331373c05d177c3409a06e7d8fdf4fda4987188196bb24fa106b459f1f9512c00119e95abc9e2492a1bf1e5bc50b69b51f2a134ee5993e28fd0da6b05eda8facde393a25baa808c09d3d84bc2e1010001	\\x41b6301a2c3660f80f160bc5c9fa2b5c3785f746c2f901438584e431c97a7022208f2472cc1dd5d6ed2a338fcb6e4edc98dab6972f4b4fe80b877f4d1ae0f105	1657474506000000	1658079306000000	1721151306000000	1815759306000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
29	\\x3558acf855dc04a306aff6818206303cc2026b6e5f060f83f64dfd09ed366eff6b71eb1e85e4a47c461a5c63845e558ca6ae029ee867dfd7c4c1f15fed0300f2	1	0	\\x000000010000000000800003dd7af5807ce33bdd044f8a55bf22250470ab79c4f25d3cd75d21422c78b29ef13cd9b0b238490ffa0e6d50611a1f9db6cda4d94c97f73d4be03c5bae24b2fc41d300a0b05e82616b0be045c6ebb517f1418c08e7de12bda085ff58c085cb3cf958be2a4559d3ab9b3960481b0bfa19b8a89692c62f170861c8380e80110b150d010001	\\x46b36e0fb58a604239f6e9f3d59d62cdaac5971422bcc29b30dadcba24d43a0d0c275168151cb0971606cab763bc363e7bfbecfc534dcc603e7034799e33d208	1679841006000000	1680445806000000	1743517806000000	1838125806000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
30	\\x364806a3a944be89af9fa144b83b08b28e49afa6f163f0f1e0325c074cafadc36bfbd24faffdafc6beb99ac1065c9d325be5b07c08756e776d698cf3b857efad	1	0	\\x000000010000000000800003d7157cec1de174c12977a78884b4a3fb3957042946c5cb4abd86de1fb337224df91bf9d3171f706a36246c6ebbacb1c7345c08487ddfc5fb5b592bf238dea0b89bc51c7da80e784d3ed8bd52ecad044b3c8c14ed051fc95f7e25e640fec0cd8f29b1b9f35a18d06b6d8836f191e5455aca861eb201d6af58031aa6f9e78b73e9010001	\\xd785a914e8e30e5074c59ec5eb0ec710f6858cdd25153ea94aa9a2182ad28847cc300d44b5ec2cb2426f1bc59669b3a3491d67b7bc4b472ddb15c070447c2d09	1681654506000000	1682259306000000	1745331306000000	1839939306000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
31	\\x361886505cb0791ef5249a4f5a914c14a91660adab83b11af744ed952142525f907f345d07cea2a463cb231b712fa803db680c06fdb386d95e092ebd43e9510a	1	0	\\x000000010000000000800003ac334dfafc27ac433b48d66a3c4667a2b64ded10c7ea8639b8dabd0cfb84734716b3d42f605487b7a825742b324533a6d9bbb380c77e6bc5b0700f2509ae5a43faec91c57d6e0811790b1ebd1f2c5d5c323aab6c1b454c4463046e7c5aefa8887b40a7ad9aed2eb091399f36b91e6e08686bda9b9afab81aa57482e30c821803010001	\\x440ea0ef98dd14a10f0e14dc32230d1cdd01f01074bea0874bbefc0defa244f278dc35d2f1298eed6a39016e16fa3317738915d8b0731a8710e4959aeb738301	1676214006000000	1676818806000000	1739890806000000	1834498806000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
32	\\x37b4dd6298705268abe918a27c63146fe5d9d711dfc5d0585ac664d4435be23f1f37e0328b518d27d10d3b32d1a85026fe24b88590cb3b77ff57d43cfd46273e	1	0	\\x000000010000000000800003cbe11d8c8fdfc088d7d47d48ea51e3c71f31724dd1b0eadd306939b7b406af70bcf46f3351f2a282d35c6087c81ee0513cf6d3f4f30c7c90daa3fca6beba66663b7f7db022fa4f853a6944411a1257480a873174da2d9b99fc74eef81fb21607919dd617fc26199f8221be2ea5101b02740c71a2ffb8cebaacaab8561a646397010001	\\x5a78a022c728f2bdf902e93d19dc823563fc5d9f3229f3fc20a174d71da919c5d2e63cd5c30368fc8ad2ca575ea35af4b53d92672ea0afabe3078c42d4f83108	1668960006000000	1669564806000000	1732636806000000	1827244806000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
33	\\x397c93a0b7ed06be003146ca3da76eef68405357b56b228be8315ec92853eff825d02bf54f36b5ef0b6057b6ed70c253f3fca1fb0717e27856932521a7915098	1	0	\\x000000010000000000800003c44200ba76113337ed75fa8ab254f2e26e0eb3c69dbfd8767d67e94405960b22bea22465a9a17cfe51dd43563581d120d772c77f784fc48687b34361bd4b63630d12ed622f6e956ca5e92a2e543ca2898ab1175934039a581a2c04572fedcd687a4932c7849388cdc258adf8c33e0dcd434a5aa81679d97965736577a8aa4d43010001	\\x017aff4820de2e60d4c5316d3772bbd422d662f42857354ff17fbf9cfecd39991b4d996274d8f4149d7eb5f0c5e09c63c2583610fcbbae141702ec0f5a93f908	1676818506000000	1677423306000000	1740495306000000	1835103306000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
34	\\x3a2c01f0ab0391f5376332453cbaf91f29ba1804abb2c8493c4ecb9fc5d17de2d5a371aa8b22c4992bfb8b7b78fa98630f1e7bfcfc23d058ca6f5bb4b7cea7fe	1	0	\\x000000010000000000800003ef9d653ece564c6fdafe47ce7aca289da66afefb18db0e63d5c480c55e3cc464a0d95eaedcbddf26abb7b163fe7fc6aa6da6480fc9da725dfd102dc60976645a1ca79a3f22846bbe0757c4ed08a43176d443cabd472c46495014df35d8232c52511027ad5ce264450d9e8ef48d37889a39a3882b9eab608a1601660d16cc2531010001	\\xe62c2318b04a3ead0d814bbef51b730f5d5215aee030fa2ed71dcaf17674466ff62ae52f812d3f6b712c07847c77c466e838c9df02f3e776895d8bc99cb82903	1659288006000000	1659892806000000	1722964806000000	1817572806000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
35	\\x3c38b3daa69a64f79ca2d10811f105993d5bb0b759a562f00716c2fd0d4180c5fe75ef2791d888bd441bffbbfdec5ded9157d616a2bab0b72c49eb4670cbd78d	1	0	\\x000000010000000000800003bca001c4452abe5af4bf4dbce0e45474c32f0cb7cdd59303cd5258fb9bc6458273f95282177e2943d47c072b21fa666bdb5c2102676dd4e5f586f6d8066be18efd1d649f4aefb1dd384107e1a00b0c4dd43dea5ac7d8450b6c2b7443d2c2e5ce0133c210ce736ea663b0add79aa664247ae248dffa96915468c93e7f7308d8d1010001	\\x1b5f571e787c66c42902157335006850425d3e1d22cf1a9e5e400994e7da5bbe39f3a4e143910474d028ffe1e4bd699bf824ed9c2c09ce0330fd8a0833015a0f	1652034006000000	1652638806000000	1715710806000000	1810318806000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
36	\\x3d10cbee41b6feed238b1479421fb8cda3ebcb32a44e4d6880ef826f5525384d36c3d7f2438c33f822b16ce6ca605f4860c809234920faf0903559457315fa08	1	0	\\x000000010000000000800003bf2b3b0082aba9faeb9e6e1db6f5046166d4cce93b89a77068779176ce6a086a9ef92bf148ab5b8e2c2dc68660783b76b1f2cf3b12e477a1fedb8ff18b13419ede7d339a074becc5c6b77ddd256298604e4cdc9f4b3366bb0a60b420c63cb59eb9e9c4ea0254a400df49f642ee9281e173006be43f5705c078a8e2568ee0c9cf010001	\\x410baebf80cd56f548fc4bea3737daa6f835aee2cf322d222cf3c99aa8dfbdb0a58c37aaa76415b4eae869b87f04f52b5fce5c70e87840402de0f4a5b7580c07	1674400506000000	1675005306000000	1738077306000000	1832685306000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
37	\\x42402bb5e2a801e718763f0353923cfbb6549fbea5a26954867944ceb8d2484ccab1868f2dc00a8e834680be16f0a0040341ca085eed382272ad425168aa6e54	1	0	\\x000000010000000000800003d7faab7dc7a943a6209c06e78f623dd03ba513877f83aa07911806e783d3c6b5050e99cf62107455d56948b50de3d22a5042e25df709ac9ee48460bcba6bcf243f8cd878a88df2d97ebcb77ff7d67531f5a2e1ef0892cf8665f598b37b966499796f4983c2722d0361ad895a85ab10c2d29bbe976c778a62889c3203b7f05ab5010001	\\x367029c9392aeac7bb35831d7ce53e2757f48e9170a21eb982bc3b237e296453f370f9b27c298fdc5506c4d541c7fdd2ea743f1fa8a06c48c476015e8e64640c	1655661006000000	1656265806000000	1719337806000000	1813945806000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
38	\\x430cb7c1b30a8464ed25d71497618bba71bae4b2cbd4861e2bb8c0f33e642a5488de7de5b7100b5bb888be3a32d8363eb169a42a4baf91cae308fc0cc1504e82	1	0	\\x000000010000000000800003c4667da3d27f1eb777676bcd054857f27a021d42f2fd74febcd44946f3f3d718b5b09d6d3c35258f3d0e7439542d35074c3670d792c67cb5fc898ae11550b6fe824b11755bf18e08acee721a2fd5427627e10f9821df6ec157e43e0695038d63a3f377b4b9dc73d39946e08ecbe7b4ab3399f2231c9f13d6ffb27eed823e0cc7010001	\\x1d50c7831288cce0483b0cacb96e34076ee5677197b315806781bfef5d5811776b7724f5afd6f42c179193e930711c2c152e23aed7444885abb6876e16a5ab01	1673191506000000	1673796306000000	1736868306000000	1831476306000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
39	\\x44788953f1091d7092038839eab864054fea7ea50eb85a92245a506148afb41d49c10ade04a62bcc1d891b9bf49ca3b2bb13fcaf6d34c0b502b9e3b38e30f561	1	0	\\x000000010000000000800003ca90db6ac1616b04f741db8da0e59d8400b7f4e52462d024a30fae3b17a2f27d63093a0479d22b97328492e3762d0831dfc366e97ea1e2608cb189e13cc54c00aa1d4c73c42630002ad23c1772e04cbc20962483bf1d4607eb0738e2c738c9cef010c6ff0f061128db063c94c83be58e03e168db89edaba1cfeb8dfedeee1ca1010001	\\xb37c7fbbe22b2f73b8057386d31dd6e0f3211c985a38537b98a45b8f059a8678ce07af8f16c00c016fbf9e746339d6141b4db6bdc38fd2abe62ad66ebf05060a	1662310506000000	1662915306000000	1725987306000000	1820595306000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
40	\\x46e499790352fef0c9493845e5d9bd27bdc41e91cc615692f4a00054bf44198cfa3fe9a8250c77db36a7f84041e46c37e8c4783212186d7e68d22c29d16e2c86	1	0	\\x000000010000000000800003be675eb58b2fd7622acf0791f25fb2e890c7f0d9afaec7a3e390dee4fa7adc71f7cfe19b925c8c82224e18af0d2156d019bde1a283cb8aab4d1df3465b6d18ea1f540d4480fed4da69eb9cb81c65e791eff7e0e7e5ff66a0f0453ad583495f2776e720f74a9796e395de188e8941712bfda924ac7ffd223b9e4055a4e73e2c51010001	\\x045462892effc7641b3088626773e0119fa7ebae467f78cdbf518e100c6c77ee4b2be658726a5340fa69edfea8f9907d96ef0b2fac68cd5a9f92142fb906bf01	1656265506000000	1656870306000000	1719942306000000	1814550306000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
41	\\x46709fcb3a9cee88a8503eff5733b0f2790d350ad8aa969a98b4be9b691b5c76aac78fc010085a14293b15b4c794849eec59a74716d2faf08336968f4b5f714f	1	0	\\x000000010000000000800003a6e957dab0324ac9accd7f89e921a9dbf06cf8db753329755f1cb1d131147818a6a7ee2a728a8ebdb790c28fcdd222bc5763fda92f3fab8483a3978f8f3e7318723b5cbccb50fc0699b10cd4dfb8275f133b690baccb129caac29b52d5a9d27ae3d9f99190f117e983c26f3cecea19fd0f81aac0b8b4be6b8b40c70a1251840b010001	\\x7c3116dfedd496495e1d2142c87e991a29936723613706a2a87519b41c86f24d5ddd50025c0f5b6d18348c10fee94a35ec1c23b9fcc64a16643e4c4bd885140d	1650825006000000	1651429806000000	1714501806000000	1809109806000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
42	\\x473c62e658e393bc4dcbe46afa8c1d60e98e1e855f90425bb0b697e6e08f6eb1d32cd74d51397868da006c1e6ac499199e78c54b832cf86ef6d2d52feabe564c	1	0	\\x000000010000000000800003c739edc583ebd9d23bbf9cdbf101be6de542b644cb7c9ec5111428f4d73e8c74b6511c42670aea06d502fb4e6b077a810de8e12ae99904af3d189f772359d143b83cfb3cb4d9bcab7bed9a5f90809083adc495d1d737e14d4f3e1c6e1678a23d9e6cefe823808201866535deae9d76666b5af7a3bf97f213a4d8aab31098bfeb010001	\\xc01c53e49173b2e4a79599dae8fe1829f31449a5c3aba4a9e19489f4b73e3daf1df17957f26e4a9d4022319029eb70b216dae5be7b324c4d6d84415e26100e0c	1675005006000000	1675609806000000	1738681806000000	1833289806000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
43	\\x49d8843686a716bbe9d0266bb90c1eb26f911920556626e99265bd4f91a1cc2c9a3df5355105f68f422edfaf5ff1a1ffd9c420b9ecb501d88bba5c8b7788135e	1	0	\\x000000010000000000800003d092f5afa8313c353e09da4032624e8a4b19428f315692805c10176351b6f671feb4ed9aae96c97408a53bcebeaabb480b3da84c3ed1b7e014c9c50f7ae31dec41937c026035c801e04d1e0e9ba6ec4a2655d9e6e317011ddde54fe32a49899615e1af86a8730419687050bca214eaa1e40aa96e9f92257602a7b32f15a649c7010001	\\xd0f4f9c3971f4365d5222a207f0448016d83ee147fa9ce221d7ecf38a96b7770677e63c358a16b7257f23d51884328e09d9f17fad62cdea47b0f082e6f019f08	1653243006000000	1653847806000000	1716919806000000	1811527806000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
44	\\x4fc050d8a9f8c5abd088dcc73b068782ae082bae4a4d2de5ae4a286c28fa15118501e0d0dff9111b5113334eefa5c84cec25de78d9e01ca8f66e20cf7ee868a3	1	0	\\x000000010000000000800003a878e92bb150833982a16894481b0e507dc6592611b134b9b4a6309012aaadf305744a814843391f1d7e3b4a99169d4b37f0f5684233808c71b38e21efbf737822904f37145fafe2d949872fd69faddb0a74c59061cd9c87bc3a52f27a583147440fe5d4699e88cbd55d2c6c680388a0c10a335a416df34cf1159224a918b4f7010001	\\x0f1301f07430a4b6b39bb97760a6fe56de2d59fba6bd36d393a31a640cd670bb4ee749a3824f693f97f88a34b8fe82d1bde70477dcf88efb66fa1f44a562140d	1682259006000000	1682863806000000	1745935806000000	1840543806000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
45	\\x506cec9063d91db920554562eae8169cf6c2c0d3c8aaf4d1c43d543ca7580d691941b6ea9c10ee2e14560bcf5c0591357a6c9a03fead2caea746ab55beb80dc2	1	0	\\x000000010000000000800003c605f0079ee15fe216fd3f748bb2855dfc13849fc140075a5acae3ae798bd9975b7f67a07e2b9d39a12ea99957b0ab00be78085788d5f17ce824c4bd900f12f8a9af969f4ec1ff92b0a7b7c06fd1b45d148e5831f268282966259f9b6af549111cb9fc06aefbc071fe72fd2511735dccb546332097b28b34f346f152191b50d1010001	\\xe27bb3fb7ecb2f1c727b4fb92057c31e3b242dc6d01a4877e3c8d44b22dedc99f0484401ce2f17454dc3e39a12221ef8003a909faad87dcb0f6d13517beb9b0d	1652034006000000	1652638806000000	1715710806000000	1810318806000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
46	\\x51f4d01de34d371b1929eb21dd7be8bc549f15bf934b2122011f5e1b4004b2423932922151cdb49e87b10dc799bfe4fa33de432aed38339cedf5baa5f53c3e76	1	0	\\x000000010000000000800003c3efc49872c5d53e2a87366ccf5af3d83dbb697187e1192f631d61a2c236564e0b7df88d408777a6859a6b4f2f4c0069222f32e82513c583109ce3fff9dc0d07d0cbbc77a22c49c5e93a8d3972a7bd8be4e4edba28294a8ec62d935515aee99ae14b27879940a45c0ef50c65653f17d068d50c492b9eb1b22110102d4c478205010001	\\xa00ca67399a927da4b27acf98de69507c2efd7c9f3ff8dfc4a595c64b3a8fab1b19712d652d349ceff8bde45d3253471aff5f42d4500f0ebe0e9bfc29fa6750e	1679236506000000	1679841306000000	1742913306000000	1837521306000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
47	\\x552435246b80d737eec494f295c51330a831cad3f5aa22d6d2328229e91fdd41086532ea8b048dcb3704436e1c2804e23731a88a0ef5d039c9c11c3b5ecd4f9f	1	0	\\x000000010000000000800003bdd54ded775da8168acaeb94ca1e33909bc359ca1ffed8b638fd27d28c7f991fc42844d5b531bffccda5153cc4bdc8e8024ac783427fd18b085174940bbc4771bb64df749178b3796019476fc8f7f018e4cd124199590ebc2ef456a1b37b011ecb04cd95d2e4a9c611e607f25f1912ce7d2abdfe242c1dce2605b4f99cb1f91f010001	\\x5f6678da33c61a91aac9fdd0b9e2fbe0322d62902a1e465d7c69836c5d757d1369a3401d8abfba7cf45f267fba7b2fefee8df7a4c0917f3f4090753510af6e00	1661706006000000	1662310806000000	1725382806000000	1819990806000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
48	\\x5840fbd03087d2c204d89d7e0364cf8c90b622fdd523d089d38f60d7cfae55401fadedfb0b642e9b10087bcd99eb89ac2c89ec7d13ec94db0bd8d775f189ebac	1	0	\\x000000010000000000800003bacef04dce4438b1e1fdf6b9bf99c4c5812af74552b40786961a6a4439ce66665d083d55e507c99652a6f20aa38ea48ea37583b32765396c66870443faa1ee728eed557d4ca2fb339ff9bbcdc9e05a0c08fb80d632a94b5cae43165fc99814f2adf6853f882a7f13ec094d41c5e61e5275ca6dfc8f88b9908c414d7cfba7baa5010001	\\x2c7515a9fd9bc99c1abbedeed82cc938a255e04b77510e7a45f19efc07c25949ecefc9e9c3b4f6f470ebfec7635c04969a742f45f6f4000b7e4a3d52caa17a0c	1656870006000000	1657474806000000	1720546806000000	1815154806000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
49	\\x5a00756bfe75d1b5fd9c4f7fbfa45b383a4023ebba5211529b2468c2d88b1fe176ec1de24608e9d7ba41e2a7a90d3049994ec1bdc122fc006c967ecba0aebdf8	1	0	\\x000000010000000000800003ac755f24a15f1aae578b657a3f36a34612b2fbb90c957d643a62805b47479db6acb7ea1ff63721d6d946ba0cc2c84704bea93d5d766252e6fa5eae642665c8f849341110b6810a46865e14245ed8c1af36200a60f33b6aaed24a4a54069889597e9100ce50881a6a4b06885b46053b7d1eac9636750824b6de38b3267457a717010001	\\xb38567ef6f9460199b42585d1c5563ce1cadd1d0b1694df9da24dc06c33201ce49242369de948f37e0ff8f53bdf3ec85e705f5ad19dbbd7ee4aa68ee4de93e0d	1663519506000000	1664124306000000	1727196306000000	1821804306000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
50	\\x6064382a0d49144c0fe1a2276ccebf7735a2db6be4f6d1d25401b4c8f0ce46f429eedb2e984433e4dd0c75ce8135fb4a61ebcfed13e8343211feb00a3b57b45f	1	0	\\x000000010000000000800003ea4f407c0c19a5a54f28322ea65b25f2ee2fd01e9a1718436d849c5e2256aa617811441009ea03634019898a3154898ac86ccda51a06e806f6a37540ee70b7fd848f62b0a89edeb325829d8e4013740c807d0ec54eb78ce6c9e9a932457646a230c41c31dfb8d147be74c8b8f16fe37501e06b0248ae8c5a230d88ce4195227d010001	\\x46a245d5d4f493e1ee50930826b6acc45683a5b3e559cc8dc6c8629983b477c7fb8c2977f80f513629dfc9b93694ddaae987614473dc2c1aeb086dbbb16b9502	1660497006000000	1661101806000000	1724173806000000	1818781806000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
51	\\x63848a5fc240d09f066b736fe963b545febafac23685f6471b7235a2ec288ae13a6c4a7dd4d1bc0e31d0f2267775dfd8503fc45f51a54524527e392b21bf959e	1	0	\\x000000010000000000800003e4f36fce68b29c42005c7502ccccedc1d9168053f57458a9cd94b039910f7d48dcc0b11f168f76098f81e82e79bea890559878ff37ad5921b86b06849f3ac7a0fda5e622e7c165ab68dba25e516c930bddf42e5b72b292ab61a2eb8fc5f6ab90809bccc02b801bb745e1a437fd24c3ab224ae03bdb0e76a355bf101b89bb5421010001	\\x8a6673e004b177e936ecde44968f49c556672b5b8f596dd437a46211d30493e3cc5763e5827171bf5374153ec36fd5b0ca0ae65d87a8b5396aa6f1ba0b32480f	1665937506000000	1666542306000000	1729614306000000	1824222306000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
52	\\x64c8be13ca49dadbf51cd602e98da306c9620b31bb4120ddaa3eec94d7d69c23e7843ad0633a0325f157770ca6b36a755e6fb36fc227d6ce1663c42e9bc77306	1	0	\\x000000010000000000800003c5120348409cd780882813c7403baeecf11547b8b553d628fff5bbb499b94133bf1bfa567744429a4c238d166c631332e642bbeac3ce5d27f68e1510d5fd62c2134c44ddd1cbf03aaefeb510c23d9bee3938a22bb5266e5157d5d984e767ef08fc4f884bd2f65d1eee07bb5428df9d6d230c88ef0690024b5e035800b781b6ad010001	\\x13e6583c63d1435c8a9816f7fc1c6a0837deed6ea1bce44c6dceabafd76110a178b97bc88e4ff2606647c9ecadae1dd7749bd0e1fc21e25579452f0da4b99802	1672587006000000	1673191806000000	1736263806000000	1830871806000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
53	\\x6764aa5cdf6eca96044f6268fe703daf773d0e4e8dc3daacd981b04e4e5950073b23751a16c3b6afc95d6eafb67b5542b89c106074362ee189904651a9390dc3	1	0	\\x000000010000000000800003d5ad1ed797088e4af52138d0ccad30e19fc2d7b56bee51e39bbae7004095c4d0d8d80e155f4ff70eb4ce89826a086fdcf81e3905207e8f3d4f4e00688235c90a2a8a47e72b53ef3d0543b67dc9469bf36ae89da9e6c346617cbe052c1535b4c98d0e9031c6721f37f502983c88683f508b0ec39eaa0b000e67776736cfe5326d010001	\\x00f333e7f10319bc75c244747805af0110d68bd6748096749581b096c99442f2c7371005b174bcaddbb42b34616c296a08d6c9a35de781ceab4ff593ee535e0f	1676818506000000	1677423306000000	1740495306000000	1835103306000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
54	\\x6954fa5a4f4921c7478445449dad8d9b9c0be8f893aa7d441e0a635cd12cad43741c2db93edd165514dec08a22761592eb77c99a6314bf78389e3f60aa7557ed	1	0	\\x000000010000000000800003f93013a6647d608bc42bb40b2e2d7672ce35f99d6191300298725229654528c5c1bb0596751cb9229380717021dbbe020f4553fa82a5ed656266fb77e203573efb9caf06445c78f91712a9c45ddbc424f38d083e8e05c00fd062cf8bec1478d4017974f4956398b30a78747017727f4774468a0835fbad55e2cec7487d2c9785010001	\\x42279fe994339484c05c62ff36f49457c4d1004ef507ff3872640616686b50c6a180e7654856333403d5966326caaff88474ec8278ef1b883c3284849c358408	1667146506000000	1667751306000000	1730823306000000	1825431306000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
55	\\x6bbc10c6b9cad87d8dceeaafbfd19e4b886b234bcdb5db520824d4669edda02b96ac1545f1e762aefa24e4623ba4e7ae5f9af8aef982908aa99bdc1fe461932a	1	0	\\x000000010000000000800003f1a1ae6f866ea8364c76daea9e4742310a788df4b751e50cdf4c111bcf0446bfd22ec810a67e99cb0442d5c06076642f1dae19a30b9b732bddc546cc03011dcce56dbb2e9dcf72d8d76370f7e3e4d83772bdf2158c033bbdb46faa7fb62d10084fc292b92a8606ec3cdde73e5a5cdf8c1c1bcd929eb4e1335bf798355b4dc4e3010001	\\x0dd88484cce20ba04811445a412a60659e9037dbf4e90a8f9fad58fd1364a23f090e0e5719cc50d3d27308a46ea891aaaa1b0d01a8f7ef87483865bea6d48b07	1667751006000000	1668355806000000	1731427806000000	1826035806000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
56	\\x6c18430fe42adcb6db42af45f6b69bf03e6caf6f9e8d198ef1e5315d0ebe2fc014d95439645618f112a20c6da91bdce6de77df658919083645edc74937aabb48	1	0	\\x000000010000000000800003ca4360003b2d705b9aca8b1a0a6917788c09210be7e183dcb747d7959fc7c602b2821528a95950518c5d6283cc7b1ec7f8531d48584c3ba033d2629fd24fd29de076a6eeb8202bdedbfcc95a060f854615283083732aaa0bac6ee2865f924509f0bb97a25fcc46fd70f70fb5414c4215500b796ba9b0c27e0fb22e8dbc7b6c23010001	\\x2c7679ac408aec9c68cd5dcea672dfa0a53e67de86f8b76c2dc2f8db4860a2a91a5f45a8f0e757aaa1e5aed6e7cfe6b40add4ef1d1e73b86da37e66cb7ff1b06	1655056506000000	1655661306000000	1718733306000000	1813341306000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
57	\\x6fe86048cb24571abcce95ec4907218c6e4b71d1a52bf0aec1a86d37c7085ed93c08d33d2e997b16051d558f0a6e78f1afdd27e5498ced11cee57e84e6e7aaba	1	0	\\x000000010000000000800003c9ce7276da9bd55319f615c72e1b8488475cc1f3b976869de59fc68ed87f22ee32ce4df5f08c93bd410a055d9b1844a93ad870f42ba4df5a145ca02ef110eeaeb4300a6e44cf4a829bbb6c01703125f95bcd0ee4ac2aa5b454bcfcda4bd3d174d7dc50d3fb7afd9dc7b1cfcd1689c31eeeed4a5fcf35cd0b0d138c796125fa91010001	\\x27fb33db285e62941374e0110354e74fdd41a980b5c249b472e005ceb50528be576086209b45a154ab3ce99c09fe5806fd56dd497ca109241f3988547bf7e00f	1671378006000000	1671982806000000	1735054806000000	1829662806000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
58	\\x71086d392272d25a2b0315ee0a777c3a42c7e099962a7f957ec6704d63c4573b0e734f519abdaa409522f75b0578f6001c46671a618f96d26e33c378f78538d5	1	0	\\x000000010000000000800003b646d65752d35ed6f14e7193d3f9883bf370cc5f6d58637c730422940dda5caa624508b0a8ec67588cf6cf419dabb71330c58228d5874e8dabc0d5049fd094eeaddfa1c62e8a4c9c0b2b4d91c09a2f76fb340cdda54a4f136d3453351c349aee8aa9c5b38d4063b70bb405074e1d1f86417366d19104739286e1e457b514d4d1010001	\\x417b51e7d9c6866a887ca71b33dd0a96ffe3f2457f63a9b1d863ea05f5cb5cbd9d3f535329efae944a8f9b940ffa4e63f42dd22c55df0e6c1ad790f44b488d0f	1653847506000000	1654452306000000	1717524306000000	1812132306000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
59	\\x735080011114bbb16c08b1abfa4c32ece2f890b98712a22505a83746eac0901416c1842519a363d3b6d2dbf5ed32a22bf7093226018d1ac3c8a9fe6624fca13f	1	0	\\x000000010000000000800003c0ead571dd3d7277538c1eba19d8d566c3b8dc6b38ca2169cf14de4a80f7d8d31040a32929e5e7e9da24ef3097254fafcdb88768277973097701f85e2fc2d8e3f60b63c12ce6b72d2b0cec915f43410cbab9bc58876c2206ecc7405200979c2b114b2558ba26e9004496e1b6e709a8aafc418455528f6d4b651c240757a4a10d010001	\\x9fa8a46275daf64e6f73b7bb7fbf0c39e7753d2e61cb8691e2ec0052b94dfae2974e3191a370fbb33bb39b06c123506a7c71ff8426618381b91b8588300dbb09	1657474506000000	1658079306000000	1721151306000000	1815759306000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
60	\\x74a42a856b726bd21750cf358e0effc2580c2f8d5e989de0ecc7ecc5ad80aba6226488eedce5213e16b3b6734aee9a3ccd47c1572ce9b4f749b105c1b0a1793f	1	0	\\x000000010000000000800003c20270b58fa25a8de6bd39f96d333cac6008c8767f50f1da6772069d63493eac8c067b395360ebc97d6a4e2232b9ef4dd3e4729c8a7675ea1879aec8dd10da8006e0a88b83243b44d3de7f18f26eb4580e18284cbfe2f733a97fb9bb26eb029d3ad5f10b06b7fd83953334ba36a9c63fbcf98ae3a63dbe8448ce44360afd152b010001	\\x3ada805066b7e93bde2bfe0a6b6bb53982e66d1a663abed018a0147bedfbddfbc9a41d4fab41f634bf028bb98cb8466f28a0137f12c516c78e0401db777d520e	1671982506000000	1672587306000000	1735659306000000	1830267306000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
61	\\x75c825830ddc9bfd4552ca22d6a66d5c2da93c17b9425a83f318c379bd3004d786be95dbf76f16c9c253e33acf4ada5b7c80ddeae9cb9d33f8e04dec3605e031	1	0	\\x000000010000000000800003b793502ca9f7283021cff39973318d1862e998571d3481930651c064ff4a217239631a13532eee1ffecc9e2aefa5feece9b71c2b09957d166b4c391f6b53d6453a9455ff32798da14362246dca6cb385bf672ed8cc458bc608e9d4edb039b92423df98edb66cc5ab66a6648cf9d15426725e8cd4db9f96bdcfeabf60acc3ecf7010001	\\x3ab06420e718308a5b47b6306fd48b01762522521a28c65cf9d27d070a8392858606e38953b47912bc347519447c9c81ad7845cc996832b5860cf4d70abce604	1663519506000000	1664124306000000	1727196306000000	1821804306000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
62	\\x7f18c6efe4312d6bda2a72122723ea2c2908ccb93c3e4310793a48e18a5438c02e077470fc4bfdb77c50565298a5ec2a8f36f591e348a1e00692f037a60d2691	1	0	\\x000000010000000000800003e5a683ec31d7de2bfe9378a8125de78bf45f058f25e1a6316d1e2093db3459e33ebd18fb6b2c47c95e43314da61cdffa09209ad6a755fafdfd6dbc6b7e3dc7459c6477e62be1304ed71ce169395ca8481bec1347bcc2e2a15ef940e0a92aba919630c98cc515433249f407593ac24811be8aa926007ff0631f849199838fc8d9010001	\\xe72364900fce01cbdb0722e7452ab90749e28e729ea2a27b0643dd6c0b4248dc08dc18f194cd84e4acf95a78726525179807c12838dd0ec9e32b30fa58d99007	1662310506000000	1662915306000000	1725987306000000	1820595306000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
63	\\x7ff0c48bad06ea3b32024de044cf1c7f1fbd41b6f4a7c8ff24cde83d4b7543a8ab8454090c351478ee40ceb3a00fb52ed0c6b0ef72b84e85515c75d2ec614d32	1	0	\\x000000010000000000800003a5a96443bb5ec4182381591f5b241f90466a16d68fa6d3aeca1b38f2a2162366647e3672667c18c0a6a6411122a8f5552b90a66cbcd561d79b10097089c5127662669b12cc893640528370f8e0ae503bdd6f6669c950d7d1a1352953ca1462071e533873679c94efe644748d9b77b048895dac73c925d794f8d43868a37f9ebd010001	\\x2b4777645fb771f17833f0bbd1cd1157496e04a3aac8d184e3110e9e0c3f277717995530060c368d61f4a6d96c4ca1fdb1036eefb1313f538b6671c81802700c	1656870006000000	1657474806000000	1720546806000000	1815154806000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
64	\\x80607067bed2490d59c1a0fb09eb74ec3b427d45bea558c8627e05ff495480a7426093c8d4de2872e2ff21e450557b5f8a05722c1536d68e30be635e027480a4	1	0	\\x000000010000000000800003cf05be0a98c4c9a076dce3d98d181624bca28d7e95b1db918e953803ee8d01a7b0add4247df6f5931c42e6c235bb08305c9dab6b2a78b14e45628f30791f89e98482ca46ee0eb7b900084300579c9a948d3effec6c11f174ca76d569de09aa51f2f833ce4471bf1caefe6c4acb9b292a035db03f271bd71756c92761d4be9e83010001	\\x03bbbd744904bdea64df70a9c2c221804b7f3ae5887e90050cd1cd7c7043500f4808c4319f836b28f4f83cdf289055d0efc67bfe63dc115cd92cba0bae468205	1653243006000000	1653847806000000	1716919806000000	1811527806000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
65	\\x85c85bd2ed10d6b0dba5904199448ce154a7d233adbb45f2fbd8d1fbab2a9eb7d9c4e8698f32058384242e73ae858225436019c039104cc1bc15fbe51a721673	1	0	\\x000000010000000000800003b5e34a40f46e7d0bd130ca44268a0b77ae6271e3379e4b40400f8813a1b49f87e3b4a9c2e3e7a172b00db837218d133ed3865f8e228dcb981d4e96c2343369437bab7f5eeccb973e369a4bb1324d7dceaeb51752a9e1200f4f475d84f88b655deb1c17cbff402cabffa2aa7b221f69db7984e1405cf5ac0e7bae37804eda6ddd010001	\\xdb5f0e8e5fe27b0e01fe944796d10f040b715bc0b7a820e65000f962a80d11855760858d4dcc4965b458ad0cb5492d09862cb53d612981ef90508e1fe7c2170b	1658683506000000	1659288306000000	1722360306000000	1816968306000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
66	\\x891c3337e6b32a5cd6ccd23e32e4667f6c7d73ca254b401fae52d92031677a5f6fdee0832bade9fe2d4580e5d6450c2cc18794c6827510a7a5c3d4604fffe5cb	1	0	\\x000000010000000000800003e155cd2d553df8d92412ed35d25f7f4acb484262c1e9c246d32256a64497cf28b1f06d7352310a143d18a8a3049aa62b44d79e64dec89d376caa49a442c138635c804a4893c2b229fc88e613d331c4abc174dfa196a175caebf43f0832da31a4c81553ff4095c3ac89e09e766fa9755d55ea551da6dcc7a349d11288adbe9215010001	\\x79b5170fa807b7fe6511bf47b250a65aec3bede5902a7babf5cfae64c504936494b6645d2b8585927fe81ecb5f0ae650d6d64bd03e78a7869b24f132a23f3404	1668355506000000	1668960306000000	1732032306000000	1826640306000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
67	\\x8938844a23675b53038e61700d260d1d951abb7948a011dfc387f11812711d21739cb3f8d2bb62f0ca9e4ba111b46603cae9108dfdd168d0046b029f0a7488bc	1	0	\\x000000010000000000800003c9d28ecee22c0d3b63550d149e4b3ed97c1958a50bf3a8575271c60df1cc799b0c2683a6220249dfdfb1e42577fbeda9939a4c50408e7d142a0f1964e7a46e3f1cc8bc57ed99fecb01ad118ff2e37147497722e24bd3a4c298aacba5ff3afe414ccc9efa40f70c0649afd87a11a9e7b7d462ce59cffc7778ee4e115de11236f1010001	\\x7d49441415c9ace927ea475e42ad2726187a6106783baa5401c7512a907f2103f859529f00aee5ffde2372f7354bfba706d65bb3d96b21782d194879952ed407	1661101506000000	1661706306000000	1724778306000000	1819386306000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
68	\\x8fb83a920e2ec8f9121dc8ef8f06f46010874a83d644ab74438a26b94ef18735e79e815a776e36fb7c1317f7a7f9ee055dd9d227883c6bf4385ac50ad43862f6	1	0	\\x000000010000000000800003b856a8737e2427ac58678c7834d1021d5d7441f1ab3a0f1eea79c6ac31d06b0a519d7ca82340f035d1c432f54b7bde2f779c5d32d521d82f86cf40682621e3839cb527e0d05de91b9ce0fe38d7ff758e9812050d84c6fa8fb340a1b78ae4aa3c7fc35471164bd1c5fca3f258410d39c7c768a41fdf316338dcf0e53583f09171010001	\\x60e8a128d7c4ac813e22cc9260734469de7c1abea058403d33dc6e5211a17f28d3ff827254a5ac1ae241a4c5f8b3cd9bac96019de07175f9cbbe4992a1019902	1665333006000000	1665937806000000	1729009806000000	1823617806000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
69	\\x8fb4b3c3642f72cd0f15516324e48bacf18ed35647e2d89814ceae77c5662c549fe52cfdc79fdca61d2ea70ddcaa5073b08ca7cf7c50cb208c4d6f58c08a1960	1	0	\\x000000010000000000800003d19fb93f9e44e6c762c130a0ba54bc9ee284b7356c47b7dc64e6e826787ec50874d1337c7d766c0d2ae65657e797dd4aca5c6ec20dc71d69b5926ca3b1aceddb5bb730f0e77e6623ff70bcf8a747450a776c0265ddb16b88b5d3541a9b9915a866e505d011c5c696c2200d0f47dfaf1a8c58f031ecc90695224da4b7ec3dcb27010001	\\xbcbc1f85ca39338f3f4a2c9fb0ddac30e6a1fd4407781812d2da7842ac0255d323683b6e6ea18fcb544b5fbbcb8c87967546362f754916edd60c8e3001454a0b	1667146506000000	1667751306000000	1730823306000000	1825431306000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
70	\\x8fc01cb47da0d5adf3642a519f94cf4208ebfc8d698463f60e365e21c434bde987a0fc3976367379dd19923bb020bbea5b3dad5e8a712523b1d3c18bcf7aa6ae	1	0	\\x000000010000000000800003ab60d7d9231801f68315ee785d1241ee1f8384d0e9680e0c961c5b6eeb9e109afd3c240a289dbfccfcb92db1f43c9408559f5b19d4ecd442f9bbabcc6379dab551dd60ee2358f31aed2917542f3a864cc42e8373a964c7a5279d709f8e30b1ef51d88dec80e8ab075f58b9207d7b79cac9d360a270cc1ad163a04913e29f279f010001	\\xfedc27c813b1188f7796545560160951779da55b037b6be9d67e87af2f4e4454de9208fc55049eb7b24268e2059b1848deb2aa58249e85bb0d23781a577c270e	1655661006000000	1656265806000000	1719337806000000	1813945806000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
71	\\x949452e04d2d42ebedba02b90b6b511c164883bc8682ac1f1433d24e24bb736ff0007606cf56465fd50425e5e98771db005371a5c747dc84ad8b2c68b11484db	1	0	\\x000000010000000000800003ad78817de91d0de177c5d76d2c74dd9535cf58a865e0ef03badfc64fcd8fcdb9e053e2865c24f1aa8ad031ee984a24b07d025a6d153a1e0a6380c89ccbbbddb846fbeb721567e930688d32945bba32be4bfd67c6c807bef0f55f1903c3522ca6112abf704e9aa143e411cececb9e6f9275df80825555ee7ec37b1261bedb159b010001	\\xad45639c490126f89aa5d19feeaebbe476dd65c60abeded73ec635aa1f456f10e0ebd7329740a84cc8443f9349b0584f564bdeb0467fbfd3881290e91cd9a208	1664728506000000	1665333306000000	1728405306000000	1823013306000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
72	\\x9594a83951c770e0b356f40148d10a08efe4248097405cb14049c1ff6a1a24534d49d066e9404f1350ea2802798dd885c6a3b8fedafd089875b838e8e23fb4df	1	0	\\x000000010000000000800003beb14d026fd14d338ff637e07f1807cc588e62bcc8065c778585f16373765cd3e483aaef22fbafe4e6309cd1ecd23d883138cfe79b97d6bfa60d7a98da09667bc69b6b944476f12393a6615fffb2d3500a629bed1b0b95c2a50c8b5deac01b05872403e1edd9dcb13cff19c2fc05dfdc4bd8b3f0814086c1f56fd8e392de7cfb010001	\\x8276c1105859bd5a6d6f9ef024826486cc2d8b468ff01148b35cd88fb6ba2a10648174ef0e4b3bbb5ec900c99d15fab65bb646b82a1b278c825ff93cc6970803	1653847506000000	1654452306000000	1717524306000000	1812132306000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
73	\\x96d0b49ad9333a5447dd2987ab16f85a8fbbfe132142f22e7d4c244e377301bb1a0ee3247e72bc4d5f4f34c572f3fa6db0ff929f5ef99e7a5cfbc6285b182201	1	0	\\x000000010000000000800003c78bdf19429c59d3383e6ae295dc3a6c31765cd8ceb950e6dc07625ce2eb08ddc28c8956c70d116a8ead1026be14d890a86b8c134a72177e14c9c8c90ec70fcec4c94c6fcc6f4d037f8ed43e145e98d91abbad73d58c75d1c7f31d7433fa0b9d17a006d737c444a2d85a1804ba780e16108279606ae5ebda29d82fcedadaaf7b010001	\\x4b5e4ef38b8a1615b056f7eaa5eb557237411d7ecadb990f7fc2dea9980e6a9f7bd5425466e9ff52cc909742df67847458b11be84efdef88c5115688ad7d0209	1671982506000000	1672587306000000	1735659306000000	1830267306000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
74	\\x99d467326558278de2c262abe3c040153d00353b242c974b88b21e4efccd7e188e12c6315680a7756ae03071fc830cd1f16f8e161fca39b430367177ba426d31	1	0	\\x000000010000000000800003bbbc4fe87cbc54b9c2d74a194e705145475d5554e2c0d6df24451e74f4c3b55360f20920e84c5c632746d4aa9c88ac4cd55c9f12f14532684ed0f0106e95bbb7d822b2137b24eb93dd2d6fbf34cae8b321c81ca6422d3dd483df465076832055c60d25a8325d86850230cbdf09b88b67e7a27301491f1690a524dacf723d3153010001	\\x0bb3ab5e312db9f065cd8be43aa0d60cebef0cf9bd283124dfa4d04333e4f349d0162ab7dde41f21cb243ead489d851e0cb79038dfeac59880c759d529f84f04	1670773506000000	1671378306000000	1734450306000000	1829058306000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
75	\\x9f9c5b0f7327b46be8ddf2940f5b8c737355379b16305887969fbff610e17b7756594cac574391a0865aabf1e6c779dd1026d0b73b997c9c2229038abd0ba4b0	1	0	\\x000000010000000000800003b49e53864bc6ba9ff58a993015d899313ba4451cb50c8ee8b201a95b2fd467906696b7dd83d9b3ebb1bdd2cde4cfa6e6326f85b4c17c1050c64b296d4f6cbc07f33d6b32caae707d0e8db8a6eb904dab3cc66de3843c95944f1f91086a1bbeb6be9b88dfd300fab4fe3efe38ac67e686343fefe3a77ce48345690e44e03bec87010001	\\xe57d564087b05ab2767922b08f141bc12cf2196ff51b4d7ccf903b212cfd0633d30be6e0726cd17b472aa827123835d6768e816398fa48218a75de3cc0a8c209	1675005006000000	1675609806000000	1738681806000000	1833289806000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
76	\\xa268d217c0d0fab36aedb00996f6d42c72f2728c39ff55ce82734735b64b61446fc0b287e3d5eae70147c36008e049a4a7d347a9fec562aeb87b5ba1381a5df0	1	0	\\x000000010000000000800003d7b0858a9e05b71773c38059bb9f87cb2188fd7cd2046045dcabd1fefda526d4e418c794585196da0b297ca30df21d96252baa386ee349fd7403e342c9ae9fabea46e3145c5820f66758fb64be738ac3af0e462b5b682fa989cdbdb805f1bd08e60acabd54ca1de5fc7925fe3ea0582331a005812017c9a2001a7c7fd3844c21010001	\\xb7f995ac1d5cebc3dcf3c6640ef063e647088c694adb012ca61d690d1de51cd00958d16750c80e047f8b0e4de4484f910dccf5b1f13051532b7a36db3938810b	1668355506000000	1668960306000000	1732032306000000	1826640306000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
77	\\xa29c373db2a044c1d378a361d9304cc3c51d48f50f71d77dae7523e8570f7f9271d5b0c7e7bbf5dade8695410ba87e60dd03680ce7c997f20fb1c81adcec5a66	1	0	\\x000000010000000000800003b40d18ba4a09c4e46a7f84c6ff489134a4bc6a29904907c3741bf865e30969ab788a746b93aae8b8727b70a4c95eb5935e4919e4ad19e0c33f3e5ec7d8da19c140ffdac9c0e2286307518382be3ba33b700a3db635e836640c96b60654711232f9b45eb5ce0842a87c578788a4e7acd68695fd86466281ad37d7839802fe4439010001	\\x8f53b72ad4f13fb341d28df078efe80ce52a3974cfde11bae59bb6b6b93bac49abc7aa1b76477601854cd76bb2742a7c6d6503fdd775602c3a9ec93b99c04600	1679236506000000	1679841306000000	1742913306000000	1837521306000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
78	\\xa8485cd3fcf90124ec1092f4f46839c9ed0737b0fd0dbfddd03fe5a72f1b404ed797c8f80e58f3d069d24ea7b7447ab197a7735fa55432dc81c12e3fe39a2770	1	0	\\x000000010000000000800003b26923b436bf6516308a2143c4e71aae8db93135fe8d9ec2cfd8667ce1d99fbe6e7a99ec23a90f93221ff114260cf12b8243f5ea1214518c98385296cd7a2903fa29bf93a8c3c7c4afa469804b25d53e99646aebb5cd6b42025b3cdef6758397222d355a7b72eb5065c270434697405811bc0246a0f2b736ebfb5d2b9a65a367010001	\\x8b2303bfcb6feb4609c883b9241f10ea5799f95f0bc317b6dd72ee8bced0288c49c63dc2059d02cc1dd95add53de7340bf49ff756ee51d6a578843347fb5c30e	1659892506000000	1660497306000000	1723569306000000	1818177306000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
79	\\xa9d8e5c8a3145788733c3b86a99383a8f1871d0220d97ba2653caa40e8f187fc2fc1dd8c0ee77e39ec69e861433d0ca5e8864763b07408654c0a3c1aa9e6794a	1	0	\\x000000010000000000800003cd23c4b87fe4233e8f4a9cacca536060dea2fa6d506773378b04158e2c1a5ace68649fbf6735d0f2a0dee03c8cde36fc4fb1888908115a641547ee7fe997e7cc2e410635655f21a2c3dbdbd60a3e03f083430159de547aeb8e7cd29056e9f8a4d9577a359e344c14d8e7e2fa0277a27ccde97d62257647baa5d5225ab984517b010001	\\xc0de30cf31e9d0512b41e4e5c8f8993fa4ec81bf6a382a6d2e2b369dd9e7a1de430f0fd8daaeebe1fd8f4795ca95967d32e767d97e2167a54847d1f7b89ed80d	1655056506000000	1655661306000000	1718733306000000	1813341306000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
80	\\xb2f48c5740ca43af166aef19eb3e0ce43f1b3b0e99ad40791a89ccf8cb022d403447f6554c538e17be3af19e821e133941e7953842122dead7f71f6174ca36ad	1	0	\\x000000010000000000800003cecfbf8ddd143f6707d9056551ed254fbe05f6e5a649e8078cd7bfd86afa47a3076257f645f4bb67fd51a0a709049878a58ce0ec5ef9deb17176be1992d2a7ab0c91b3a85ec67bd259c495f1f40d0f4a2bfb4c7df2270136d40895ffa7710c1d988b9a0d7abf57afbaf8ce6f122c7d5273a008c2e0492ea6a76ad32ea1b3a543010001	\\xde3bfe9587f6fb3de5b45b04ba4de8191606cf9f957617702cf1126938f555c4fb06181b4f4d187b3e1ba715f7f45c596b6f05fc91656978cbe06c51acf40d06	1669564506000000	1670169306000000	1733241306000000	1827849306000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
81	\\xb31856d8bb780ad34827c73c7b41726b467ad2157dc011b83bad1e6e3d017bf0f1b70f46afde69dddf3c7579a61cd060c88841897183a274eb29a9bcf7a2624f	1	0	\\x000000010000000000800003d3fc45023b096fff89324ac6f7032c3844bb43cfbe2b373d88d85fb078a531393d8a0a502c0efbcfd070ac57b2dbdcef02dc67ce245baa563cafc1f5f097804c3b5bc14bed3f3003885f72f9e611b4e44300080c01f2ad8edfd92a2359c3befa1fda3f512956c1f4d0758cdf5821a369768269f3d539e8917cea43e40e07785d010001	\\xb0358373f548612c6585cbb45f3e3f55ff1ba36c8f3771bb17b2c1663b9426d8512401a0a415ec9056dabc4161acac1329a5e76756f67ec63c3cd23ab8008f02	1658079006000000	1658683806000000	1721755806000000	1816363806000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
82	\\xb700af95cf7704cce10ac8d818907e0b2bb54fbea84ed414d64bf003ac5c9f56ac4b732fd8793d7eecb84415ac02e70078e12432e74d19d9d09c63074a1d38e0	1	0	\\x000000010000000000800003da5dc9d7b71ff668a422770f9b9d2d47ad481727641d536da23e531ffe83f7a16eb68ce96592a91192f058c7b197881ba7c1435e445991d23c2ac1bea33222fc6af47f5c62f377e2ce5a3634e1ea1bfb657d9d61c3611a176f9ed4b05807e6d963f8cf0ccb2260052862bcc3e8d13b39614ea70c3a46fe6079fba357f0ebdf23010001	\\xb06aa7f4b6fede3387ceb3340daabde7dadec758d3af831caef69013c0bab019f386e40c691e0a1fe6402db36232998a85bef876349819e916a0bbb15de8de03	1657474506000000	1658079306000000	1721151306000000	1815759306000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
83	\\xb9ec5701f9178793cc6d706aa9f126d374921af2d450c3d9404a2c6f06b0f08e3c0893072e340757a56ea8defa92dba4ae06d63b6719c3809eaabf19baf3fa4c	1	0	\\x000000010000000000800003bede8b03d41b0c64d0d14ef01a8305777ab45ebae1fa683010b2138095300657b98f81dc16b65494407cb167dd5719551ffbe1c154b2a22eb2d18b3ea25432c4e70222bd4e23362a12d497ed0d7ea9f8d68aa40626df1209475c074901e353598f6bc0a6b88458d60147f5f0d78c018642db910f03c83eac1422079245097927010001	\\xbab7e20078a57874758c24edea4822f7475e112744c4d3f30bc89489db4955adc6dbc9235f027900a62bcf7d27c14ecb295be433193a953184eca2163f659509	1663519506000000	1664124306000000	1727196306000000	1821804306000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
84	\\xbd8005ef00a8b9f5002f24105993317aa41396fb213debc86ddacb81f9c9428f45cab2c3e454bfb095c8c5c36fb0eac161515d94bd5d3c635cd7c30de3469be0	1	0	\\x0000000100000000008000039ecb33e6067878c912d9d69ff1d84ed3e488b77caa6695c8f902d4022783868ed76211647a63af83dcac4822aa9e4f869b0865a6d1dd7e5c839eae89f3d800fb93cffc98fb23d6a939ace1c9d018dc9eedf7d2efa6c052d60b4d6fc25b90e9ef925ed274b6b37383438309322c6e561aa39ea0d0e2cb9029e9fdb8ac8a1cdac3010001	\\x26a2d596a37733fc3d1187294d58eb9566969caea7e492511d73b6a2a5a281e98800bc2d4175839b17fd58c0e8efb7b310d988370247f8d8cd44de1d7eb2710c	1663519506000000	1664124306000000	1727196306000000	1821804306000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
85	\\xbec006b2b4f5952801d9ba7c53c0a637318e5426a7bb669a263223deacaff9bc1c7aaf246124c0bbed62665219279dc07c00f660dde2ddf018c18b611d7dd207	1	0	\\x000000010000000000800003c77ba4cef7876e58885488d7beb7920a0b36220c8d2aae9163e7e340e9ae9f4385deb10fb45e28df4c1a6d7f5c0793e58c839aa365f9c38d842caaf330f0828ccfb951c0a702cfdcb7b048fb833ccfe1f94e40993f9b146be520d63db032b9c3f3940c52eef3a428b8be67824fc2615b96a04516660f3f8f0ac28ecb44b199e7010001	\\x1aa5f8d5f35dcfa841ef2a99fa448e2c9bb569f30d92741d4bc5d3eb57f8eca7ddbe83c8c083b3e131d1f3b080b8f6144bee1b4faa128242317dbb0d61a1440c	1682259006000000	1682863806000000	1745935806000000	1840543806000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
86	\\xc3587bcee1d03287ca411bb6597bb37393f1a0a2454c187f3e46af13e846ebbf79d71b1c69b2b93c9a3e6cf0f9a6c3d5236f6646b18e4617402ae6ce21a00669	1	0	\\x000000010000000000800003c2a01b648df6128b008b133294ea58b13e99347f006f64a056331a7a11b7fedcbe872b00e14fe69574c44e281e11ddf6686ceda048ea5754167d1b5940430cd89d539f4b3b6a383a1f9cc6d6f59f5d22693ea9ba9776b354a7b292f624b59f5da8afda765922e0a3f86fb7500eb150cc56811f786364c29247b3e076264d3341010001	\\xa29e548c370499171962d65015068bdc14e32af1356cc2cc68b546d0700cbc28df6080e79b538c219db8b33b2629d39319b804971e5b3c87cc205ccda225d205	1660497006000000	1661101806000000	1724173806000000	1818781806000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
87	\\xc674626e8c6082b883a5cc658b17dd9efcd7307924d3d701ff1471bf1ccd36a673673f696f91cc1875f2836c2a0a30c73f9c63868247939a6f143421673882e9	1	0	\\x000000010000000000800003c58524b00a2510d38065e1e2f1043a31dd4aecb57a1d4e114dcd2f6373f4bfe81be9f0c47773809c123700d643cc75a97a4a53d2f0f2e588bde6d4a0633e4960e3b9f84b3b1ca31d28e52733759b0b94336286c8006a1af9a1dc7403f07bead48426a8e7430076bb360d16950736de7b1d50e1b6936c92a37d9b439bb09d8a73010001	\\x41d233964a95780c8874987a3f6c6ce6950b75a575003ba698452f747006186136bff03c066b03b206e1c66f3c1d386967768971caa67a9283f77436133b410d	1677423006000000	1678027806000000	1741099806000000	1835707806000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
88	\\xc8041515fc08aa42f18b39687f4f9758af3902121a44217c864a509b7005667242f2b9d74b511cdfc3ccf8aaa4b52e089a39404ea67f072a27500bd6f4e6e037	1	0	\\x00000001000000000080000395f220fc7baceca627ef5e133b5de9532e635e10fe053978e08632e861cc98df60feb91f90ad3d7e33a297c88995c6158b561ced21d564ab87505e62cbada960f0638824fb00e2b9a41460b23d938eff436f51d720bb4c08b8faf2eb727c5baa9adf9b7cbbd62b4b2588d7af7985ca2f4f31af5452f8d5aa625481730ea01163010001	\\xdffbeb30361888ad834a198ca8d44da9f05edd49f77c9c9c390716d6d5c1d7bd399ea16dbeda1d99d425197005a58f27f562cff99e0abbd42b6c101847fce40b	1658079006000000	1658683806000000	1721755806000000	1816363806000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
89	\\xc990b8d90c41d3854b4e65cf866d1671bcd5085513af302dc8702b76ce79f63562bbd7a28f085c6a8cda074a50247fbb8a6bd6107ef8ecfb5176a8a25725ae63	1	0	\\x000000010000000000800003c7902d43411de692b55660ca0794ab95fbfac4880e7e245700f4e0c7057fabbdb8a9b60e247d487a5dfd854d24c70b6656fd501ea20e8996c7614ad25ff298177967c9da8bd43bef83b34ae9424cd328e6ec16ebb6e395210fac52af45c8a259b04eaefd4766d3e3d521c5af529219174236dd145b3e1c3f587f7b54f5e8af45010001	\\x616015c2a33b427aed6795006d070a9fe3faf97ae239d254a3245529cbac314869a91e5eb7eabe7e8515b2cf91a2ca800b8a614dc5f541f168b1defa89211708	1654452006000000	1655056806000000	1718128806000000	1812736806000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
90	\\xcc9c4c1a298ff4e7af25ebfdae722512d17a541d1aa00700981c888df2cabf3740398addbcfea281b0d594f52ea960e914f65b6c33f3c7e5bd96b1aabda255ad	1	0	\\x000000010000000000800003be9019bd47340cf8796fb2ed96fb670db4013ade88cdc6fb2882df6081259f0a6908321d4326831d18401dd3a5a770746a95bb39698d3b85cc5ca492c4abfc789d62d95a4a74aee58edba929f919f0a4871712578abbcb3f3ba97f35543ac3dd60902cf52e4ef925f4a0f25c79adf0765e62f1435b440b1d31e383a378e4788d010001	\\x24991921f9075b03f736b03d32f4b4ea7cde91e352d70f4c643b328a64fa5865c72b551e7eb0215181027aaa2742a44d1580ecfde93c8f0f95d0fb1579fa5f06	1655661006000000	1656265806000000	1719337806000000	1813945806000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
91	\\xcc000d84099720486c90554a7dc6a5a61adb5aba78a250f8191b0f721218a767661714c89cd84a48b80a300bce4bc7c11d2a881171668d2595d2bcb663fb7520	1	0	\\x000000010000000000800003a66e5ddfba2bd278357cc22c6ed80c709da234d07081e200c8d0db9ea10eed15422fb58dcf691f6fbff183170d88864389d24bd2a8d7e639526a21ea60e4019b793f6beac7d3f9947cad2a9e67b908f5a7278bb2f9d3bb62e362edc6e5296de1111babb6e005dc4759a1e572339be2cfe3df9283e07abdb5fa37a39b6736bcfd010001	\\xf42e6d3584b74c8075c6bab947eac3bf08a8659910d4746269816093eac9d60c2ad93aa357552059ba7efed7d035b415cf50f85ceee9d6354180e238e2196700	1679236506000000	1679841306000000	1742913306000000	1837521306000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
92	\\xccd85fa9b29706cec091acf5949c13e2d38dfb5088d72cb25f182a9c9b9438cbc990f1a81214d203324cf4ac06bb4238f63fcacbafd72b48f0a00952b83fbc2d	1	0	\\x000000010000000000800003cb34f4f8d070333e1ffa443b268fcc7c601eabf1fb949f6be9bb8fa38c1bca964355a801edc35abbd3a86a330bdd445838d87e117510f84e44648825493d72e73318a3f2e12ab52d030222047679c23ebe36fb5a036664858128eff0c3aa81341c895d6f6eabb3421ab017edcaad070d4e488822c8019b652aa45d04d9b7d6d1010001	\\x95f054ad983b53da1b94c6f2c385c2b4cb306783a75de943d1b49920ade8581a40266d79a4ab6fa56d80bdf5f8be946768bb15e3fb198489ea609b5c2e39db03	1652034006000000	1652638806000000	1715710806000000	1810318806000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
93	\\xcd844fbd49daf608a57ca5e6a696ddaad92685db93a731ecec8c5ae01115411ec222a92ba418bb4a65c26d6b178f90c43cf0676dba93ffa66d9c099dd7ec9b6f	1	0	\\x000000010000000000800003b2e7d0704a03d0f67ef2388789021187e08632c968e7950c8f0b922684ff5ec86c196570abb6ed7b1dcf98442b57d57c8b040f1040d8943ac2e07b730a27694982ae17dd9cd8eeb287d84a03362551dac58412227434992ff872472330f2531e670b6952acfae60e942446f7262a2018a3e5c9d1f3f2fc281941af9f0cd4f45f010001	\\x2773f7e74c83a669566e246765124bf8a157f0cf13f665c0356f648878a6ffae1e24fe3740c98b98f1b973e450f5d3f98cf49f1ccc5952d6b79761e6fdb2f00e	1652034006000000	1652638806000000	1715710806000000	1810318806000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
94	\\xce24bfccc2bc13a6296ce1d11ff30af44cefc7cea10bd207e56e23865c598731ee27c6674ea7dff9b871ee0e45066f47bf278fc2af35d574d755e227e4030475	1	0	\\x000000010000000000800003be70bd5ddf3511cd857a436250b9ae02b5380b4f6ffee81e71e8a8ebe165c375835597b35f1773f8a4e8f9d83ab23681b836cce1da27d4216295b8467483919a15db4c34908780285b6ad553e0405544338ed7a5e57912b4aa9c3a725b71a2d2e009ecf924ce003bfd93bf96ba7d875426ccc52eca57486191dfe1309622e64b010001	\\x951941aa31eeaf2ff4ae543433a8f6fdb42c19f3e6e316de975023e0c11d5af801a95d0be671b66d8b9c3cd908659ab2f67df948e29b895f0f822d8cb8c9220d	1672587006000000	1673191806000000	1736263806000000	1830871806000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
95	\\xd8a8c72458a4e81ee93fae54b1ac776b3d0ae3a69c9e113c2042a2d3ff38fdfa1f3777967d5d9142e32806fd5a803f91f3ebbeef1347361b08eb3889b08f0264	1	0	\\x000000010000000000800003e872efab222cd6ffebeaf3e13990f30ae99e97aa630083c6cebeea8add480dd59bfa1fefa3c22a0c00f52daa0552cf349215c5cc79203b034ae0323559d7ccbaea89d0837f03d59c9235f01f9df6b794390608a905d41498bbd6157ef99a28c448c125d5d97f57e1e4e60d63ca1b313531149a55c48b3124d1da54b8087b4733010001	\\xc06108eee83f34c478b2f0c2fa8b8633fffa9f60d714e6404b9c08d11b3b9a4f391dad08ec9ba011ae2c9f748ff20ff5b9470c55d0738847bf1dc59b4386220e	1678632006000000	1679236806000000	1742308806000000	1836916806000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
96	\\xd88c7d0336c187abcab80aa6f8f603cc748c610eac293b7899ac9c25fa48785552c05485c5ab1322366598175d7c055bfa585096b6c5999347fe57c8b8f02e7e	1	0	\\x000000010000000000800003e6deb9a4c481cc3c32adfc1d748520f6a9c0489ac4b26ef8c98e37617241b9317a135dec77c9baeb89cec167a248be69dc46b92c4834bb3ddbffb2650bb8292974f6ed9067d29bcfa571d6543e5133faa7f778a8ce567030695b6374b7acc6ff8511caa16970e2c7ae68e11d41f2aa8b4ac656d346da199917f3a36ed3d01861010001	\\x29a522706ba07a02192d950429d38bde35c27404e990cacd2b6b60190224f506171c2c8d3e6c5e8be349d24a1a7306ddb4c72296898dafc112fa38080509db01	1654452006000000	1655056806000000	1718128806000000	1812736806000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
97	\\xd974ebb3e9ee22f7d3fce8c7dd6d859848399cde8fc62bf78ecf56106f2b05b9f40dfe67e67d1dbe08742a6bf5a2a45c4d27684b9b6c2116589d4d7e31885d65	1	0	\\x000000010000000000800003b488e6d7a8ee7a243ada5912d266b1ca5bab66aed33c54286998b84dffbb4aadd1c7df1e3e1b608f4520bb84b166e6ab98bb750f8d4e3664a95e939eb2f20f8fca2fa89ed66ef35750eaa3073de843e3adcbbd216dce3407a54319fd521f3dbe867ef7c4e898cf16ef06ea163c0ab8785d52e5a2de1fb377a970b154e3c52edb010001	\\x76d6fe80d27b972164e65d8e2636644fce08a7a6d65c5731c3d101a80477ab9d9f84574232dfaae1e937edd7ce79c319e42133fa97f7fe62d838a7d7a0b6b200	1681654506000000	1682259306000000	1745331306000000	1839939306000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
98	\\xda2c16cfd645dceed441b6fd7decc94fe24fb8343ba276e367da45371a016f3a095cee3527524d2f7de5cc2b7bc651cf8d686ee55f2f8eb4d5a885a90dcd63fb	1	0	\\x000000010000000000800003b6a7fa881712ae6266d44d4e82a227058b8ac370f8f5001adafa97e5f234927b03f3ae67f548a4b81d078c062a5cdfc2ae32aa36f50617e595910edd2e2bf3a8d4071c294bb92e6399d9b5ccceacffbadaced063c67812eb6df3c1389a3314e9595a428075fb0a5438fc4312576b8619295ed6db63eebc7adcd69607837ac2ab010001	\\x8d8034bc574279457ee65cf185f644b1369355ff51d04cebae2c52939c0a5dee569e2aa53dff7b31d12c4b2a42af18bca0a50d37457aea8da07c910470fe140c	1677423006000000	1678027806000000	1741099806000000	1835707806000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
99	\\xdbd00b13bd2a4580086c7b951c67595f0b9ed02885d2ee6a56ba18e12f2953f94d496e1771ba95c2d547bd8c4a97ddc2eb8fd5fbed85a9827bc9312fc1d3ed0d	1	0	\\x000000010000000000800003af134f102b662c055f251420e04a8ba51d135ccc5585e538332d889d63668ca3dae1cb1753bc0d9f7795a61253c8bbcb377f5ef5e87b047eb40096a22df6ea90da5034ca40c8db38452af10ca5d80f65896a01ed681159d53dc925c36b037e9c327a9e74bfe445d94bc2f01be4764580ac55da2d0ce766d819e956eaf808f1af010001	\\xe26c3aeac828f201ca8d382274bace6e1a287ddf7b51ae429ce2718447ee009c1860bce4029f2517c4e88236a4a21aec6309c195053ecbf30e544a032dccf409	1678632006000000	1679236806000000	1742308806000000	1836916806000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
100	\\xe1f0f3b772a6766a140efc1868a44af3e15f66c6cc1845953f84361c8f366b32835194819102412cbf67d83b4b31734438f05633bee2e86e31869caa5f11cd78	1	0	\\x000000010000000000800003dbac585b1cf88704e8465933927663a77d6332f9b016366a086f12ab584dabf6bd0e1face22342b9b332c7f566e00de6c76970c3e9d1dbe27072e3f4ef7379c2436dc32c34ad1e5ba17cbc25d6e5144492a82db258d9a8ba126a0bcacf3a605ee1f5b637888e07991b65ad38d880d2ebfde5cc47e8eb45bfd0fc692fe360d773010001	\\x53e42be4391dd5e4fa36179412d45a4141c82e623c42bcf92cd7c76cd364c14cbd636de59917cda30e807d60e0bee8c6a0878394a45361471fe373ce64a94f08	1661706006000000	1662310806000000	1725382806000000	1819990806000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
101	\\xe84cc4465a2ef8e96d387f7f0c65653f1aa25347f471b080dceb9508a65b1da05451510d9874cb07eeeb75d6394934319b785967a604b0f5f172fa246cf603fb	1	0	\\x000000010000000000800003e759131a76d1bb509daa25327933ffc8300a9f2ecba09aad4ccde0b52b41bd30e5964b59a6d814c53301d64a61b6ddd98b62d5fc43f853aeedb252fd6df4c3237ee8411ad726e13bd918facd3c0ed412981931e6a4b5bf6d5ce96110ebfb65608d9f6ac468dd33edcdcd99975f2c213d168a7887f36c8576ae9c67c000070cfd010001	\\x8e8cec9dac80966ffa5e82989f4667986c47a3023ba0eef63ec1e56dcfe3ce5e7bed2dd635bdb3f784bea6fe6552fb14c3fdda5d2dd032198f28332d92fc8d0f	1658683506000000	1659288306000000	1722360306000000	1816968306000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
102	\\xeee8f7193d358caafa47eef8a1e2144c69034b302b032ac2fdfc353181fdac002db2c38565dd4b2dfbda8162bd415ecae645db07d23c0f3e304d9b474c2084d6	1	0	\\x000000010000000000800003b6efb43bfd51c9f0a104e4d9736f2a4070b69a1559c507ba05ddc26452465098734ed1cef70f88638cc6df137a8eec2840616df8a631b59e00ce108bf80b72e456ec08d7b8c8153f747479a971c28630b7db9aa11661b19a1b76f3aa218a6cffadd359ff268cb3d1315330daf91f155d622955cfee2e556573b4845bed03fe79010001	\\xe7e637c66ef5244c77311d02b69efd007c8440f34fdf9d962db527a3176d52690f8359f52830ad125ad805e36f97d14070f01b6edcd48e41a8dd435a8ed5c607	1668355506000000	1668960306000000	1732032306000000	1826640306000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
103	\\xf1901d52679eb30c030aad6fbc96285d36fd598d34280a3a3fb9022d25f14069b7e22b667541318ef48ebfb83229a83566bdb5e416d3fd95514bbacd3c5d576e	1	0	\\x000000010000000000800003c3c819efb6a9685fe5a430962daf325ab0244a33059408d941f51a7a58f00ce3e9bff10be4167d85135b652bbde0dfeabe46d0f2e0c1e8e139a074802f3ee7abafb0db11998dab1abb7d9cf609aed40dcdb844bcf61cf4ce1c7542bf08f4b1119f0ca0d2218b4b307aa5542f34e5190d331c529a1c7e5d47d9f4e43147e25c2f010001	\\x50e657fe0d9cb23a8eedb22d06e34639dbd343f3a65008d96596db68a2dfe5115f11ad9dbf1d2f5ed0059abfdc412e418f9c13841b35336d6e7aa4b2e9045a01	1653243006000000	1653847806000000	1716919806000000	1811527806000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
104	\\xf2a8cd0a172be53c5c068f2261b9fba39855a7af34f6533ab8c1ddf293efbfb4aa0664c906dc4935bf59e18742a5fcaeda3f1e89dbd76b74d44092dd7b94a674	1	0	\\x000000010000000000800003c15ccaeeee84081256eb62d79d8a887647c882c85f2304ffce9f8ccea4131fe9cded896fe02d4b4a25363e4a2cbd2e9e9054ef80e7ac5a665fb9067ceebf232631cadcc6a4d6824fc950176e8d038231809732e7214c9a834eed7e676ddbf77cfa8b2524e467b3f19df8e6f83d5f4ba98d9cb62016150906c3d3eda878627115010001	\\x2bd94cd467166381aaab7953078a57da7788d1fff2be18e36ae3a4963089be065c45b953a258e986c500bf8d9df4a495c14c459c7f8b0378f37387b8c9e61302	1680445506000000	1681050306000000	1744122306000000	1838730306000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
105	\\xf55088f50deba344e8cadf702babf6e74070f24966809fe84f78a1e0bc83b0c13617521bbd2a34d881d20fa7cd939a054e5889d96204ddc970c76d5d3cf29652	1	0	\\x000000010000000000800003d286cfc4255ffb7274da3dc7ed54bb82781155888d5bb8aee019f3ebb863dd60afc9b8402fe5174c2cec6677d5179527e5db61991e95abe58c1a65522ba30814741c01923a10a4b6603461f66ee9142158ed2f500b62a350f2a202031895a7554362217c730e2b56c6ab0ae86f7ac3abef617eea91a3771f8ec47abd8c096f85010001	\\x52fd0ac55b616e0463a335bbb2120f380710bcabb11021be1db485a98687484c19481ee853b58c9e1533aeb919d6a6da370636c4bdd6ac9db84088e6c316e00f	1668960006000000	1669564806000000	1732636806000000	1827244806000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
106	\\xf77081e1ff59d17c3fdd657009a672290b19df6b7893c0095f5c586e2b5001ed5bbcccde3fd84b0cf98c792c6e52e4f96f68ac9d1bf1f99811b6653aa0252338	1	0	\\x000000010000000000800003d505199a7cd5358fdd1c7aadb996ab3e323b63c3512a710e7365350f7c63c7351ac698cb9f1bfc63629129a4de6dd6c6b16aafca241ea064419fd48b22134a4e7a262d5c8cf530c882b87499354553cf8c39e7f528bde34800572420a0b9da069e945b850f51b1dd8027e1787f7891b54118d72ef345ef54df444808afe5e4f7010001	\\xb9b03c8de39aae20a400863bfad132f1367a723cf2a9c504dff6d6cdc2a4f2c2dede30d3108b386ff01798a474e3d8584cff1f7d15b8c55f7cd3690c52584b08	1658683506000000	1659288306000000	1722360306000000	1816968306000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
107	\\xf7003b8976d4a4515cc0667ec95aced017b851331c04ceee25efb36cbdd52483d149a7942e9b6bfa46a10c0d16f7227cba9294f831ff36761824748cb79d1ae8	1	0	\\x000000010000000000800003c5d8aaeff129142465bf8c6190d35d32c79eaa9edf6c4b2e7a90ea0498523019e718d51d47f64d4918f09da28730ecf5a0dccb36d6539f62deeeeb6fc97174cfd896727db340f450243fcb3e9c4c12f82b33bf47da32dfe8ddbc956c56a2c8712587ad29bf852db43349f399a0ab85e1f35f2afc3350c9579e484dc4015b7b19010001	\\xbd559337c3b996e15a59e062a9e29513f772d7716cecfc143f4dd495f425b30b391c104ce25cc454c1d03d27a1cfd09f08893d20a9574790d4ac96378c599c02	1651429506000000	1652034306000000	1715106306000000	1809714306000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
108	\\xf7885e1de4ba1b71e22b0746f828a3a0f4e1f317e83ba897a829ee7038be4130a8566b16e7380276f4a3d8d0460e8ba9f178fae7c05d4c4589dc343cd43c44cd	1	0	\\x000000010000000000800003a714e61f758b6e5b025ac0553d042809dabed7a10b27af8a9613d17564d315842b92853e8f74107c3dc7fda5aa464364cf4635d16b81c65733c2f5aa081d8565f474462b06b65a1714d92baa70d4678c2a04c8b8051b5a86642734afbd69129e4cb72c0b2f5de9a5fa499b92daa645588c10f17b70073d7796e479aea0de7b9f010001	\\xae0bf9f09a39eb1dd3034abb35e1e4b9f342d28c54e2924d546a98848aca244ae10484cb0434994d13d3eafa252f0c89035c57c465e3c82ada617fa443bc690f	1652638506000000	1653243306000000	1716315306000000	1810923306000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
109	\\xf8186ec5979993c374799bd65f583da9d875195680dce76079a4d763f207d284031155fe7594bf003c742bfa43f9120fe126f931bb68bb2c3f757789881fd703	1	0	\\x000000010000000000800003cd44075a47e7347c825b163dc9dee79abfceb865209b1a02ff2ef9260c2c4c44685f534b8ac1f2d425d2e8d31ec6b3ab8d1066650f300272635a28d19388fc397f4e79f93753b9462db06a70ff438673114b56e80d966c1814d570433774256a12db63589c2aff6ce6aa5002f3a97c35cd9fe3beb57c4a2385086a792508e471010001	\\xf35bdb5e801b179ebc139b0e16e5e389a9765c1bbdc78b2362edc082cb3e0410caee36bfc2e0539db0747a838f04fa4c898b849e5eb15db8cf71da6a15303105	1668355506000000	1668960306000000	1732032306000000	1826640306000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
110	\\xfba4eff8877446e1dc6c19861ea65631f63e6f78f1a45a7273c28ee71390ffacfa6479e3ffa1f6e2cec69d04111c82794bbd23f0bdab0b7feab49d85e640a58c	1	0	\\x000000010000000000800003c63dcdb92a2576a35cb021b8bfe03d73fb3bd3434a474858d7e5df6b30245205804084bdd7310294655a5e3ae9979941fda751ddf8e51dcd1ac3ada71cfa2114917f306f93a8741bf618d10c93b0be69d6067a89ee2877885d277d87894087c877e5dc21e1b436e576fc5bbd1348be3b65840e190bdfdfc6678d14d5adc65807010001	\\x46fbe63e5acc9475ed22d3606034d5098874bdbc922d058533b2379f7ec2df3a1b9dafb83aadbb1314f7ad01d3c3c6162ff926f3935725fdd68a371b2f59ab0b	1663519506000000	1664124306000000	1727196306000000	1821804306000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
111	\\xff044db91a5fc382073742b405e9308db03d6d801b8d2da71f68a66625d8a13efa53fbc2c05413f0fc8ad2de4057837a43fac12ce75282b452d3b4b9b139771b	1	0	\\x000000010000000000800003dddf888ae89f9154da1b3dd55b02f079b62250c427703bccb9b70ec74dab1762f0fc764dd94a1c918d49bac09bbff77fb3e61d543ebe83bace5cdb8afeba55fb15202203830be4cc95b3af72f9af19ba43554828ba0ea51bdb8fe1fbe5dc339a591746341affff1d11023d959abd00fb5c82250850b4eb67536d47e047e791a5010001	\\x08b08bbcc051ec9e9c6c06bdfbd6efbd8e9635187e993408e39d05f16c03d29d2ba5514eef90d1437be5d8e3ef21edf72383d4377c1a1cf8eb92ba92820e8901	1652638506000000	1653243306000000	1716315306000000	1810923306000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
112	\\x0361b0f9500f3554dd83ceef2aa5b3b1c9d660f96a3f407f0131981276f6526bb00da9f0972796ec9634efa8de7bec93fba8eba84d45e0adb9eccc9e482f90b1	1	0	\\x000000010000000000800003d3c2941c7fd76f55f9f7ac0d24d94daa506493aac45578637acd2875854d85b8105e61979facc2842ce3e56ca6f37333167db62f41fabb644527f712d022a60e9aaf3e16788e3a826e04639b323c342f41d27d655433771e46f59610d91650ede7b971414cfbb03bf7b89fdb1a04e8ec10dcaf1eb846d91eb431deb1984c7513010001	\\xf1bf39110577d8b2e64f64cba63948900f9f19f3e176beaa40debc1c874201806843538c0c6fa249682b2fefdafb131fb022a449e4b1f364716228b22271db09	1666542006000000	1667146806000000	1730218806000000	1824826806000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
113	\\x09754b1478ab4be924f0ce3386387dd28deb966c1a773225c438f67b0c6479938c94821171c3b75ab00cb262365329810121f330ee6012f726442ad2fc69a762	1	0	\\x000000010000000000800003c5a26b1673f71f69e39c0f60bd969ce025a86a4c842d3e711d2cfa054db4cefced03070030b2da47a15a6a706d7b129b3f8a853fb96f720216059e5832c0c9cfe371f0a73430ed0d3e88908b1704700290bf7ae51de12d76665b8368c3aec7d9c2e99de7032c25dcc0def13d4ddc632e6e61f5eecd7da5d84ed7531d2807dd4d010001	\\x5e8143b54666562c1f388859574bc3fd38e52b095f7799201edaf8f1a35c7f1a33eb9b4afc6bbb0be6ad6c38de26b44aef75f672d490fc719c45d8f7b82a020f	1667146506000000	1667751306000000	1730823306000000	1825431306000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
114	\\x0901e2ccc4bb3602d60c926bced75643be074f9bc23fd53d4430dae2e963f9ee49b6d11ca1eaad7f14162af56a230df9dbe8aa79f605e735490fbabe3ca70b3b	1	0	\\x0000000100000000008000039ee664b790ebaa19ff34075218faa0430d1ad4c1f225a6134fb6d830bbe5774f3024c037397aa6f38f116ed2fbc4b7587e32e6d6640e7a2072222bcea8fae04cd31216ef78fc7b72f71847237fefad687186e61764e256b0f0c22328f62e28cc78f9e99b5aad1e5958c5764143784a9ef8ee433e3ffcb370ae41508d70010ce1010001	\\x78e7122a3cd17bb21dcdb3fc8452e7c56991645dd3dce5c3c3d5d80239183e4fb9db0671e9b47338bde20f945f06ffa15bd122bee2fd72cb8a2d1ff1cee67b02	1661706006000000	1662310806000000	1725382806000000	1819990806000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
115	\\x09d5f548e767777351d200dd3a34ad169a8e700090afea01aa29de9b5832d3836f78ff8b4fcd3720338fce00b2f8967f3d4a0fd4f12587fe7343d792128a1a24	1	0	\\x000000010000000000800003aa6e88524982f575c04d4746f5f5976f3403b493459d47789de3ec5aae9063b1986fb74e30e5c0da0439a6a1c3178c5f1b2e3fdd439b4b7fa285ef214451ac23b788b0a048ac76c94e290dec2c221b95f6c2f8a8af2aa0bb2bc2f25db18ca7771b725974f33c7f5b49cfa3b6f1d4fa8b3a88dfd222eed6e3fd68b2bde34618ad010001	\\x14cfa2457d4fc1ee9941da4f3247a8e7213bd7b009b8ec9eb9fcb4a8c8d70d248b9b36da0b4d6c0b5ed40ba1bee8dab788caad05af5d880865e638efb4b1050f	1653243006000000	1653847806000000	1716919806000000	1811527806000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
116	\\x09417299dbe8848fa9394d41963dfe13666b73584de985d9e53eb59018a677f32aeae9ebfd325704ca2d5b7b971075052354059a4cc24fec4ff831b05d138c8b	1	0	\\x000000010000000000800003d9376df9090b9ec70a49a2b292d177c86e994fbdaca3af4303aad5c9df81f53138a70e312633ce1e3fe769762439513d0ec8a98eb8c99131033b808be95312d9ae8b9c776668f4ab50909d7a73bd0378bad238bdb9843b7148490cd6d1b7e8f61248a55896ec36fba5b698588a22948fae1bd88a507dd904521caa5ed9a0cff3010001	\\x6cc3d8032116a7d976407ab542d373e80b8f9b2047190ea642700abae163726fc0bd599e5437cc0fb159bbcf4645625cb50c843e2e3aec9010f4224d58b5270a	1660497006000000	1661101806000000	1724173806000000	1818781806000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
117	\\x0cb96e5487f1968aa1f9d4dcf6aec3509bcbb0d7a1557d04329ac69bce9aa08a65a6a29d7fa7f946d0095b60b265c27feb5fc16e35c7f1ef5c2a38c776efb456	1	0	\\x000000010000000000800003ae1888374cffe967a442547167729e9d5d8b29ebae5ac420c45a82a0e628adc46994162d6f2e7927b149d00484d31cd073fa35c56fa079cef0ed240de69762b12683160e5eb0beefbb84f380965f67aeaeaf560c2b3cfc3dd8a88b0c192bb15203f734ab2f70849a515290dd18e52e93987425f4ac6173a2111f064312df6c69010001	\\x831a0ee9c240674e059cb92b9784600b582da6fd7eb690197ef833504eed06dd2d3da5c9bae6f0d036046873b7e078a58d28305917c9507b8bc37900b1f41804	1679841006000000	1680445806000000	1743517806000000	1838125806000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
118	\\x0d01c0ba71485bc063e515d3f8e4cee936a88102679f6d721235a253eee472830c9c17a7be1e752354bd3517c33de5d8eecf553d0603c1ca1b0f5a66d2d82814	1	0	\\x000000010000000000800003ca45559b855a208be4836ab599546a4d6c4859d7009dfce7021253d42aa84e3100700cf255cdce1309b4401690bd67cfe5b8ef76dbd02660849417e69f31d70fd4f798eaebeb99863ccbb67b774fab74304f565180bae8f61d48c11fca0a9f7bec81f7d556fe014efde3fad07b476cd64c8b6e9917a30eb9f4e1d4ef9cb4986d010001	\\x8d9fe9f277fc3c8ac59b1950876810370c704db4889cdb2fb59246087fbd51dcbbb593891ed251f1e03019e7b3ceb47780dfb27083c9ae32c980690536b93902	1668355506000000	1668960306000000	1732032306000000	1826640306000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
119	\\x123defdb878c35ecf870e01d2f51171916129100165ace256613cd50cc0b1ddbde550e3bd6b131aa45adf66281752d054b0700c3f0cd8b98b0bb235c2e8439d7	1	0	\\x000000010000000000800003bea46bb8657641e8bc274b0c8c4a0433f30ff1aaf031a9d248c2871c932e288097949380cc347e10a5fa388f15495e78e71cf4e633827c190f7154153efdbfab4cd2ec915be111fcac58f7ffe6d815f14ff7c879f8ce597ba77fd855f103894fa0ebd3245b89e72a3d655ee58cd134fc86da4869a23bee0b2f78766496b4f825010001	\\x6509785f71ffbb4dabbc3f78bbb5340e69578d856b5f9696bb2c7d2627992ef367628fa1ceee4ab6b8095c29b382c5a01f30c7ecf74c25002ef8375b9c8e5408	1681654506000000	1682259306000000	1745331306000000	1839939306000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
120	\\x13a5fa03ab14b615fb3ed56165ad84a82fd23ee23e873021f2171884d46247f66ceb164dbe476764e1b0269ac79ed41e85d00574f128d02ea11eee2614328846	1	0	\\x000000010000000000800003d1379f944120d97f07aa90851a1c4e550c8868843b9cbb5cae88aea6353a81b50a285e781c9b8c6eb7683003d1d150a409c8b2a0925324f3977d289f7c7d5196b54f3578dec31c6e0dbf9c7c88a240d2874533c929b8523155f04d3d5821629bed9b82332032bf076ea536714b7ca9be1ed292a7ad709996011d25aa456ae0bd010001	\\xfc5d02d7c303d9c197a1ee5bcbaae286bbc62d2d633586d1812a4d6a696e47448fa4047489d18dfe72ae6f899508d75603ba7d80438bbfd2f94ebe4994718101	1657474506000000	1658079306000000	1721151306000000	1815759306000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
121	\\x19b5222c6633ec111584bd065a728e0e9317ceee02dd20b14ff0c3214087eda13dcfebbb469504e0d6cc663180f09d303bc60a895995c94d61045b9dc0c55890	1	0	\\x000000010000000000800003e6cdb44103962e1d12fb83f4cedce6404bd70931e606dcda6bdd1785a3d9615f01c6f1f498a882a6bdf20e625e04f26631a3894e4f5c601ec6782dfe0f0a81d6c92070e93d1111e18737bf2cf0f908942acce01313f467e6d760a6783d6685ddcfc679f1b191d5893c93e44a75a7147e93362d1e9d4fedb03a253ae5cc473651010001	\\xccb8b4d72fa6c1e306aeb110836e98a8fe324d130172822e6f60770c309fd86579a6f8e52b445eb64fe47fe7365099a0dbb5cca9f395a2aeb232930dbdf9ab0d	1665333006000000	1665937806000000	1729009806000000	1823617806000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
122	\\x1a5dd9b0949c306c0dfb2de68770b9c7bbfd73d2c4d3915af63c097c41e95affc74a00af197b44d839e23553eb7c2c58c24b895bb6b6f821c0a20708437a1ce8	1	0	\\x000000010000000000800003c13f09ef4415cc3148055629142a81dae11fd853bba87f2956f3dd29f996e379b904aee6e0f7181a656a3917a55d087b7ad206fc3adfe44add53faf6ad14e4bdba2444d5d552cc0c6c63bd7a8c01e0e0bf9f5f0fe1e3b6dee3290ef1f38436296b1549db395725b98a663bf6f1366d213b475fbccd3dc96d4f0edf50be1d90b9010001	\\x2688dd982ddf5bcb7796c26651079aa412fc4ad8f2020a82256f93030b428417a57de4bcd3133ef3db70c7f2ce927eae4d78975dbcd19e803d8813830b55da00	1681654506000000	1682259306000000	1745331306000000	1839939306000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
123	\\x1c25db8cbf4e217971d7800cb159df2e97ac80a484bb1bba7464803691f5b50785eb62ce16b1048ce1378c79c2149e5b487483241d5826afd660b0b14da90ed6	1	0	\\x000000010000000000800003c80c7049d8f2d8ec4d209ec99028cd6ef832b3bd2e6e536805374a7698c67ca88d9078a70f3a0271d523656461e1c6f191d1632a320c81c8def7eba5aff07b9ad104559ce528320185beab115f95b1a0dafdc6f70922d83de9f3bb567c5357f86defa18b8d8245dee2dfe3d8827b3a7556fad603d2d206dfd8781eb25930b96b010001	\\x058d93a8838d31fe64ffb7afb022c2e8fb6c753c869603d018ea40c9377cf9d4b49b30d8fff38cc25eb88f12226e1a693bfd328c77a4d0afb832f0fb71a93a0f	1650825006000000	1651429806000000	1714501806000000	1809109806000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
124	\\x1eed79824d443363ff70f0d34da60f5e7cafce4396193550006b5afde1ed48c29e9742d5a8bea429ef51b246bf238e080e8519572b4c46ceccbfed99bfe7008f	1	0	\\x000000010000000000800003ce9e71a17d2a39ec01c3be943cb0305942edf3dd9df4d6f1c733239c30bbfce80f575ed37891ac035a88745911a038f27b8fe072b4fd7cf679cfd0052c07f7064706602f0b797cc454e8b4a41fe87867de69bd9b1f382163e2c4c3382f661001c47536f148affdf32fead8dffd55cb4b466bc04f984bc6aa8b8e4f4296094c19010001	\\x0dcc9513f9541957a75e70ca56b97c9707783efab390ccad2613b9ad53e616e748ea3a1c56ba13f0649d78e974d9f15facc449b4d5e643168a40d11fa7bcb302	1681654506000000	1682259306000000	1745331306000000	1839939306000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
125	\\x23099e5d98d3306646e0325e1de49aa513d64e11396c1401c7e5a8d40f85d0aa00e08347fe6cab751619f821c009c207c0d66eecabbbf2e1b343b533206bfcff	1	0	\\x000000010000000000800003c0631572ed97cd03ff5fd23f18a937e513295ef6bc1c5aaac75f2a5838216e5a87315d2c4c6facf6827eb352e08d4ac3861ae808068b2c242f13e5708aead8fc6694342b6999e8268dcfc9f801398dec8bac58ee97a949828fd91e0447aa412678dd85ce4efa3e677774ecb155cf51ea7cfb6b04b5d68ed182d1518cf3d3d92f010001	\\x4418e14820367ad0410c6788d08a487645ef8c904eee638c013b8de7429f550b9079c1d02a63f4217f98f4d663cc2e08d15ac4a4cbdf46563ed95311420c2e0a	1664728506000000	1665333306000000	1728405306000000	1823013306000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
126	\\x266d9b07a3c4be82914a080798144ef529aba2ecd0cf02272b063b4221ef5acc16ed914458aa213fb0200638ab018486adfc983bc0144031a5f9e1b18bbd9433	1	0	\\x000000010000000000800003dc2d9b3edcedc5ea8e5faf567aab202a6fb87a70e72b3edae4a18f27a1152fa2a3e404dc13cc005f4b699c8bf779e33e5ef752c117c3e6fdd24984e7227c01627eb3b91916698124f36d2ddfbee61bf3b03fd5edbdc6948d4f2358b77d66f7e6d5aca8e0837a64e49719280b8663806b794e7aeffd6ab0a78b3faf11775845dd010001	\\xc6a3124522cec7d212eb19030bf7c587b2f18f907d4f6325d13325d0b07661463ab67172d6d71ec7113bdae5fffd1781b22d5008ac9390b3964b05452ee9fd09	1661706006000000	1662310806000000	1725382806000000	1819990806000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
127	\\x2639519a4d8d4ba4359275b7714a72c9028af23194e5f5b42b4d81a57d4a7d43da7ffd9738647561e398685ba33272b91cb7ddc48c147cfef524fb99a0f2cff0	1	0	\\x000000010000000000800003bd26ac61f89899d2031dd3d19524e19855db045fbe2141913144a900e166937ecfab4d282ec3c138e5d7edc2b04262ec17746d7e92d46d044bf430ea164b92917f7a79dad4ddcef2651cc562f473391e5c6c4246859c9bb73d4d15f77f768b146cf6ea2b16059b36e730d772f1bb82b6972d1cd5fd86a7f0bbff61a56e153d7f010001	\\x1f8de5393acfd621833201eecca488a462545f03cb330d2b1fb0c0768a11a534d741d82947c59c88449c2bd0aa4b2f7308dc6c775a64f6fcce4249e39ee3c004	1658683506000000	1659288306000000	1722360306000000	1816968306000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
128	\\x2b01577c94f39e856ed9b82963a29f74a5517f7bca52b1c60739956bc92de04d50ee1b88891c88527666460846a8cdd889ea22a758ba831c0ec7675beb8a25d0	1	0	\\x000000010000000000800003a53f526c97374a2398bd5d9a4dfffb8358f98e35abea1563d241d681b79b970bccf8e95957939f96690e1a7456b72286301f076287282ed1165872054942609a08bb7a2776a3a12a51b150c0c7214bd7cd49c2641af0144a6189dca79447d5467d5dd70be264cd7cae2089e3e2284cc7634678c8030e47d8f9c24252916cb597010001	\\x37a5b080c24dd9409125ae6c3136ea7e4ba21599beb5f1adb576d615400ca9691c32f8a873e4414b597c83e989cf7c398cc3567f5163578460676e50ef1eb707	1676818506000000	1677423306000000	1740495306000000	1835103306000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
129	\\x35693cfda1cadad3455c2b8245933737753dac8666d0bfa11162ee2a36570ca9cb1c1bad042ad70b38fac60d9d35c8b494ba20a2b3ce62fc77a625d338bf843a	1	0	\\x000000010000000000800003b4115cac6062a59ab9305ffd5aecf959d5f8c39e2485307e45527da35df8b852adcacb78dbcd62302a6b2ea5fa34b6cab2492474f67a2c7c7ac9860f9a2da83adebfbd709110363935d39e03e52dc5a918731b27c3b8777e6d55ceccd45a1aeb5851704ed9d7635306fe219f5dd552329596c5e73b770a7fb7acbe769d61bd31010001	\\xbf3687b07ca0faef720ab021823e25871e0585ca7e2124f9924e0371f7cbae7f329257f2226dae4c555e98a370a0637c52954eff35c7262d6de711d20a210d0f	1654452006000000	1655056806000000	1718128806000000	1812736806000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
130	\\x3529bcc6ab95c770fdc7e98135a1008a01737e09896f7fe51be0f01f78b8970addb3469ed9fd08e4e29b8f205ee96b4366a2e3386eaf22ec8a1990624d256776	1	0	\\x000000010000000000800003ca2ce608eb6193b5ad62dc46bcd45a6b28d2ea75bfe4939fab9212a7c047cf47378a68a95138632939ce62c6e0d9d64fe0f87fa085eb081a381e16a5e1ac413c2ce0221a4762d7950e2c655ea0b51a411fa1dd74a1ff144576f1bd297f57c1fb7a65a4cd55ff60ab4e1b1162a4c711f883959a5bda0feb8f02bf2db49a38d145010001	\\x0274b671aad137f5e27153659cfcb1964c9580788ef0edfcb9f7afdf8fd5fef961c2817866322adf664a70542b6473ef5ad3274e06907137b8e4a5e662ddf506	1677423006000000	1678027806000000	1741099806000000	1835707806000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
131	\\x3801f2bc3101efaf905f1d71d37632e2be719376431203322e358de1dd04d330b75244b56e07db017d596b323ed998f72963151ad2b98d9921d996584e571915	1	0	\\x000000010000000000800003bb609aff323c205f4f7b8a5906a63593d67e185ce1833b430892ad24af88bf76fd9ebc75a732fbf183bcc6aecdd47407ee1b135276a6014d146c60c36b7082cb5652b989ee08c5ee5a0f1691e89582a749602a432485a3bc69b88aefcab26f019d94694cfa4e75814a175bb4fa830e581bbf94c9f1d536e4b39813692e95fc4b010001	\\x8aa8a6ac4647f837ba9c197db3bc27a9a8c263c80d07e9e82a7b4cb0d1b5359d1cab10c2100ddb4f3237a83cbab50ea2d53ff8a4d1aee18ff382b5647ff39b02	1677423006000000	1678027806000000	1741099806000000	1835707806000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
132	\\x39296d09553cdfc353fd03358bb3e235df0c7d81c22faf64520c119791e6a7e2d633efff01be244ff76894c545c0a80e45b855cdcf85ec2ed0478044e75b5791	1	0	\\x000000010000000000800003d3c8a1faa56d48b73438714563408c5b60fed6c59df346ebb3c73ab4c9750992637214c6f923a6b86905cb21ee56ca7b7b9c3c9722a7eff2076d1b024ee588f0ae5bd93a2ead803b06b7289b04ee6dd05087201b816f100197f040976ba1707d0658c4db0de0b8e8570da794e9818c8d2ab4c5bda9edb05a2bd509e5ac4ebda9010001	\\x2a7cc34d4b8757a5e7fe8c7febe1d55e8ce94567da986c10ea21e668b3b3002f36b8d822c03aa51327974dccb151f1fbdab1ed1306bbfa876ced28f332f45009	1664728506000000	1665333306000000	1728405306000000	1823013306000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
133	\\x3ac1248954dee4e88bf4f984d374976c287e5b45dea8e58ad52f88b2f07b83ce1b476d6e86222ad2258e9c33c16ef36d7914f0ab43dff09c866c2ed7abc58cb3	1	0	\\x000000010000000000800003c14dc33ebf85b5491915ffaf327249e10bbc20efbbe95ebd3bd0e81ca712aea15b794ad78de243320e237111f016252971f13bb3e1a940601b7d73af861067f264a5c0c17b4ddf4462aebcef34135d5194118a2a26b9ff47d066520e14cf95a4ec454ee2058d325aceb7fa46e8b1b97b77f03171b0ee6b151b3cecf95ff2b455010001	\\xb7d784e7f8c59adaf54bb93f66c2064642de6ef170d9c3d2fc4f527656aeecc4963ef062301c1a3238028d009a30eb9cb7c3d2cf5c1769e2e37e69ad7c2b3d0f	1665333006000000	1665937806000000	1729009806000000	1823617806000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
134	\\x40b5488cad078b4ea80dd2f8b150b5ee2c47c91504c532b46b00080d85a067dbe60be812cbe6d813d732c1be7a0f8ca213622cdeef2f4101223225289d887948	1	0	\\x000000010000000000800003d0c06413ce792399147312b89b6554892ba525ce73a1e5159606dd0476622136565e852248a7a5c76bbf0dc30cec8c81db2c30258623fe36925430fbba1fb080e864ac3868741630117f30fbba3138a4c4113f3b6dfe9998fd7f6e507116a8f6a4056adcde9faeddfe6a9a9fad8d88af4699c5c6f604f235710ca835b4f05d99010001	\\xac88222ae93da162fa8140fb5a9e2472e3e3c4cce495c370f2b61ebb4984c15d8be23357bf903b42372f739755bbfff63b987a84ce0f22c3d01ec664fc54300f	1680445506000000	1681050306000000	1744122306000000	1838730306000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
135	\\x40356458f6717bc3ed678ff863962fb7e9ab551808c9560d7b4e0846dc83210a649b24378b6b62aa1b4de58c1fbb08682b3ed9ce2483b5ccd2af375e8a3a6b44	1	0	\\x000000010000000000800003c04fae6664ded538a255547e376001a29f3023697fdbd032fa7a12f6fd8773245c65684fb50786c5704e6960984182755f47859340aa970eda6ccc633207f78e72383965a4e291b12355882774201491aac8edc23daf459cea7b5584982ea007f017a57bb8dc82cbd2560656463511133ba387150b1360b772686c4308712fb5010001	\\x454c525d4ada8633619f8732d445e04c9b1d1e61b7c32c4651fba8be5d1740a75e0e54bdf62d33f243411bc94bcd8a93f004965cd4fab00630f6f26621fd120e	1664124006000000	1664728806000000	1727800806000000	1822408806000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
136	\\x41cdac9b6c8c7b19424152aaad8e4df7df31076928962432c2bb4b7675ff6f156024eb37d7a79cfdeda5dd0bbc3439d1bf93d150fddb3428d3d46500e400b3f7	1	0	\\x000000010000000000800003af78aaa89e4abd53cb8c53c51d459f8d65822bf786d41beb1a9e37b367ef46f0f34fca72ccc06197e107bc6b5e60b418031932ede6ecad09cdefba511af0020477ba432de05036138d6d9fadb54e2b163b2a2a9a4a484c87609303fea6de4ed94c4b7659e29fb12f1f53f064223604c4138cef873947f6ae27e63b1c808d3089010001	\\x00a48033c8355280c70175b6ebd30c520b1ec3724f08e6819f067ab37dfa119c0c2596bd018ec1b970af4b42a8b352e1ccc3681d556d998a17bec1e4d7cb9f01	1655661006000000	1656265806000000	1719337806000000	1813945806000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
137	\\x483509fe2dced697dbfe6ae04ef229d88866a189e665084bb5a761fab27b71c251afe2b5d048f6cd1d9696cc0d8475ef9bea29c39bc61091f1c9a65aee8bb5f5	1	0	\\x000000010000000000800003ba478a3aa96fd70a9de59a94dad3511ba59e15f98b64fbfb6e998cb70ee4e1eb343f9348aee785ad9b82a99fb27ace4d33ca3d3e337e7cf2e383dd7ee69deed2f4cdc445bf6c005e02f57ef6d0605656bbf783b6c672202180fe278322effb3c41c78db525f33c78c20f60d9185f43cad174cedc62c2ee0c68c5f4991e7c6027010001	\\x0899a6f98141674dff990a558127acd04c79e4dcd8dbb7313962075d4d350cc1d6eae82ff2412f8a56587800ef93226d207aa1750b0f068538500bfd4ce9990d	1671378006000000	1671982806000000	1735054806000000	1829662806000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
138	\\x4c055f29db30db0dc41cdcefcd051458d306f6d6c75c02da3210d78a5027d00e0be6028a84a926f9b83bd92df45b7aa6adc5c5a6681348e6faa275a6538bfa2e	1	0	\\x000000010000000000800003c569e92700f5c7cb4b062382d6f5aa2d34724072dc245617a9e4fed8644e00a20f09e20804b97f09067edeec516dd0cf54ebda5bb63f020a6e74644efa8e92b4f1cf8f4275c3a0526cc387d238e3dc81777eade103d7b40022413fe56f287ff99e715b1c79f1f448fb65cd4a77d7bc55deb2d575fa3cc74c7a7caea5ea0c05b9010001	\\x01674c77e53661c10e987211c50b7f733fa6534d75e71ea320068dc02b8ded60e0b64b4d6598dc97923f0b97fb090c0c24022f7a2e151ba932dcfb53fb2d850a	1671982506000000	1672587306000000	1735659306000000	1830267306000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
139	\\x4d5de8cb79eb9f9e29400d81316e0a5bca926173af7b41f0bd34041769ce07ae78188d8becd59924fadbc4a3ea02d5a2182f7ffe107018c4f4339d0c65a67d27	1	0	\\x000000010000000000800003e4a15941fa33c12500724297cd914bc6c8597d8a21d5b3476a0583f929070917a1de8ebbb4d34bada4e3b6f5dc6a621f80e5c6c3b58304c20a847faf9d551df0f67962b880b0f5c875def0516b40a37c01bea3b226d86912e162e639672bc21c95c0742731060a7f3509435d22774b74ef5b04de61495aec9c45eb992ae27415010001	\\xa6e2723c1fef375068f4e1870580213a2bd37e7f1d733c8f1e98ce1d7ec2ba2133c694c3c88c728c70baaa5777df4c811cc2138d526ce141a9c920599b326901	1670169006000000	1670773806000000	1733845806000000	1828453806000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
140	\\x4fed5902429f4f8747ee9c59db0ef0df90ffa23ec8c810bec71728e328196d07a07c848c0555b025deb0404d65159c788362adefd54f992dd9c0e2ddb464b52f	1	0	\\x000000010000000000800003cc6dedccabde383a9d95bfc38e36c5566338e5e36fcd5b8fd9bb85bce2314cff0bb3fdb39c04296493100d28aebad07e0a94a90182c982e8a09c9ef43689ae166969010271ce24af8245392a9b40bf6a286b64337e3e48ccac5419f1b41ba5745850319d7aafee35a2b1dbd4fddca837d497ccf63b398dee380f48baa671a475010001	\\xfdb55693006751c29f435c135dae6f4a7a3a6712e330f69a2cdf79d42bd88cd3f408256f1707f912792b44bd1c05c779dfb3eb950aae0927cdca7fbb55a4280f	1654452006000000	1655056806000000	1718128806000000	1812736806000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
141	\\x507564021d6ab8e8ac9af9136dfee2d525b8457302b18dbfe6927d0677fc8d2c4cb4ff58e54a9b8113705c6ffa6b825c851e9d00b9e522b0c9f87e6a66bc5473	1	0	\\x000000010000000000800003c718f78073f1942746ab2f2ad03239d899aa711fd8df1221c6ba8bf1c08a92a78f5ccb682a30c39d54f9046cc27640acdce037ed451f19bb35e95b25556e58c2aed9dd116e53bfd3649a19a9339024c0babf5ad540c333fb7e0e738d3c6538d6f27950d68a4b36a7b41f54989dc81c7df4f63f0d5ddf4fdc667116cc2896f287010001	\\xcecfa6b05a0ba091fc5057a612e360889016ed8f96106bcc1d5ff7f6d1cb866ce184e784cd81a6e420e42fe4b9a60d5c1649f5160a3e57b267b61ae5a18f530d	1653243006000000	1653847806000000	1716919806000000	1811527806000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
142	\\x50817981b61f370a43785aee6f18663939ad66753d84c8fb7aa8536db992fcced974b9bc6295325431e5f5a4de00721e3e0292751de0993757b35b805132641d	1	0	\\x000000010000000000800003e1942562e743157f94fae8a065b2e0d09a8a62d9eee52eceea5c4ac596a047424b5b758c7721b3b6df544a51db87cfc8b65f9fb41bdc52b41371a23bd4f73d8d321fb5c9200372d562ced2b3a89e298786604164942f5b661978558a58e8847a85db04a9fa6e0364f9c8c5e100c008ca122658dabf7b5d92b5214d62a29e1897010001	\\x13241436c2132e00902283476365a4321b739875d9073b12c59f34fc1ed54e5a42e7de321e157a55ffe5974b154bdb175b4b28b5f689ad30765ca5af50a5950c	1662310506000000	1662915306000000	1725987306000000	1820595306000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
143	\\x518dff9b2b4853ef5b47ed97bea94db413cff7ecb533f71bf5e762e1426bb1fa588f2b380ccc5f19d1061a3e3ebb056ec928f09e185171183d9a63049e94dca5	1	0	\\x000000010000000000800003c55df523bc14d42a1d74f597a7ef4ae51b80547c7d1cc368fce8047c42f42dc2c2d010bc4d565f9ebabb4cc048389a2828db8369a4a32a08e2745ecc9f27333d140da4867aa7a30b43c25a33d325005b08df4d45d624d8ab73961d2e5563717e8ca72b93a6b82032649c334f5cd91f0186cc516c8a45b67c79009e0afe31961f010001	\\xfe24e97a3f9e2ae647a6a5f61d078633a2bed9e292abce647df564cdb9705bc39b5cdbb9cb55e7b467bdbc65f49fbd521de42b664deaa9549651a5539fc77c0c	1668960006000000	1669564806000000	1732636806000000	1827244806000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
144	\\x55011fd3f7813a93570f4b4a351f07ead3f14bd9aee576912b8527005918796c0cb5feff7dc3a2a95defcc985ec4c2a383ea7982ae85e67e6e5926d12e31a35b	1	0	\\x000000010000000000800003c834809dffb1dd1611d81816eab37d6f4b283f4658cf4d7c283de9475992c0534249fd9633c0e028192cc81818e263c44ab6960d564184da5cea216eb122f4601355bf02706b10cb32481ec7b4ad4df30ccd1bc275c5025e8d37be96e419de2408d05d128753a1cb0a6cf60e335c385647c9a57a26816becc89adc788b42918d010001	\\x349cb9acd84b6b5ee270ab5b314a620c8902913e2834f2c7d1aac74a608470d1cf6ceca75bb976d4dd8f5f2a97db6d803005b7e5f661a5d88bbd02ffe60ced07	1656265506000000	1656870306000000	1719942306000000	1814550306000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
145	\\x56b50539225c322539c4ef272acad38fc2195c5bedfd86159be8704fcf075b4a43034bb5cadb1e91b884c970ab906b5e769a44f01ee3b39faf0d2016bb5cce86	1	0	\\x000000010000000000800003c727078e8b1b488aa31deed66de474fdf4b24ab0a48088aad2296bd3a738c0c05762a6c32d7e7898ae80c3097d67960d7ebb726786a2f2ddd97c18321009ff67b3452d924922a9aeda80452f3cb2ef63da59c26b0381888353496020f6015f18e1c760ea67d3378c0d8a3bacc37f92826017a447821ad44c3d254b4a2b306df9010001	\\x43da95b5ba28e49f0b72251c0a075794d6ba8e4996cca1b7b9ed716fc95b440eb71b169f7665dde6f6940ad9bda5a5708e116dc8a9e00e7acce21a63e4af720b	1669564506000000	1670169306000000	1733241306000000	1827849306000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
146	\\x57955894544dc71eea94853ea897d42d8bcd60c71b04341700b059e83e3a577469281eb4c09dcfbbd94247ce5b82fb7044e7361b915944c431a5b92e119ff75b	1	0	\\x000000010000000000800003c8f3c816381d38d5320c25bd6cb77edb9c0cd8f3502fc434865a9826d29dcabb6e91f772456c5eb2e2ad0ce67c23ee63795ca1f929eab4686e4e2e3b60ccc28473cadda822c7c07246499f75e26f124d03fa8195aade5320d97cd768a7e336757ff893d1037a6b85c73359d7fa058110eac60ed4ff7ac31935d9b22dd2f45e35010001	\\xbb903775567b9df01f822c3780689200a5e3e281cfb7f354afc0b99d7bb7eba75c3e1ec0c57a5258f455f6728af88232b9b68732478680c1cf15d28cf634d60f	1681654506000000	1682259306000000	1745331306000000	1839939306000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
147	\\x5bf15f1b01b72f0c7eecc7109111b3fbb5733e1b9056fe37f9abe933e29320d7ab0e46b851d3ad7103c5289ac0915767a7038e18e49c7583dce8a46e9bbf85f2	1	0	\\x000000010000000000800003d4952f2d3c2e1f030628e4e93a5f77a49d1313d99c77cceab03f528b76e436e21c91d3762c754de0ed8e7deed4ea1fcd83abff2c3e923a364838f6c789e16c2925b7bb3c3ae909ceb499e8bc01e85eefced3eb2b187c26b4f3b2684e0ba16c50f7cde4f720dd5a262372785471168b67c95946ddb2f786a2db50d78b2f4e3d79010001	\\xf3fc41c69bc11ec2225c25bca37c65841d56245016276581265e0faeae266ebea43bed3f46f38a94d7978678f3481cf5b3c5e3cb3f7448743679f7bb7740c404	1673191506000000	1673796306000000	1736868306000000	1831476306000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
148	\\x5d759bfaccba4213bce649483635a6197d294949ca5f8bb2ab57e0497e4a86ecc26107737acd3714447923f75d4a24a676328f723a99822a6dc0e532cad9f3cb	1	0	\\x000000010000000000800003d2f15b8c39be0830895ce253e4da2a39a42d141053b4604362c3907369c429814b734f39f2412df1642742ffa3bab3a59be94dc78bad5846347674d4c497be730014f328622421887417040a9a6892ee9eda1609380c6f8c12e32d765e7141c7db25ae555c9e91923c4abdd2205539f6c9fb41d96582e10b3c1dfee04a65bdb5010001	\\x00fed16b1f4b02c9341e18c843caeb7d83d3527c6660a0851d7186dadc8b2e59c8a85e11caf7bd58fee3d8c8e3a29dd96014095a4319e8d6b29dda4a26c8580e	1667751006000000	1668355806000000	1731427806000000	1826035806000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
149	\\x5ea506285c2ab51d8627fcbed5c17c72373d58abf2751e2fd10ff69cb190924e36718e6d0d5dfd86249dab57bf3bd5fcea27810068cedf3d589504120195729c	1	0	\\x000000010000000000800003c9b9c4f9e6fe59c0996874759ae6451241f14472ba76e26b2616e9c46b6bf9de8739e3677109dfd1eb05432b42cb32b5b83d3e97b029c4cc906eb48fdae2e5feee8550d087d0e302116441dcf9b79cd2405f167026a2a17f2925f15e3a48a629d3cca1f81729a31062863c413e3faff26a15fd2fab91925c0648ab004bcc867f010001	\\x70c8553a89f8c5394f0a14a0e718ac8f720e7ae384d512cbe2164d9e0cfe14919d7f30398f9a741d26f286fa8105fb4abbca031cc4b602c5cc50037d93b49906	1665937506000000	1666542306000000	1729614306000000	1824222306000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
150	\\x5f15a3b632e5328a9e25e813c22899b98d4a659e41a3f88356c362f2746a84c2739c2fa567f2f30a0aeed164f16abcbac8320b2d3b5a566f1f5e97ea51abaa0f	1	0	\\x000000010000000000800003c604cb32d339527b8a6a2c41ba5a99652953ce6261fa3f32c100c64671cbf31e55ed8a81909d7b8b2057e1594f32788e4d86b66fbd5923a9e0067c17ce21a9c1ea2d653b693062a362b70ef5b3055c181cff54afd363d2b21b0e28a07f2bee769ad1d06ae0ee1e8fd89c5d9205d45e3057fe359288e3cf1126eb3864b93975b5010001	\\x6e9a2df86f4d670e12ded7f545b68f29f6127dffb23176786c4d22c293125084ad1ef08bb4b2d5269678154f760680872b333a194e1e8e9eedd1447b09ec5502	1676818506000000	1677423306000000	1740495306000000	1835103306000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
151	\\x61a1c00345c4246c2a25b2e2c14ba678f9669182dc2d03cde4f0385611cf4f152f1afe2f85163fd0cb71c26d9e6cdf60da8214dd060113f60a6d338d06114d0e	1	0	\\x000000010000000000800003b5db8151ea7ef975f9bbbd5e44f624dbd06b60e75be3ee6532ab88c169c3e9a008d9df362b39201984c07d9fc7fd06720c79dd5cd68c3ffd7a3e10b3993707a320542881a6d87bd63cb9fe1871df3ffcd507014e8786d801ec44ecf238338d73c349cc3241fe6e0bfbe3184b080e5693dbc2a1311e5b8688e4f185ed0ccf72ab010001	\\xf0efda8290d40318d1fb97442aff4a50ee881aa031293bbd9b7fd5e68898857884cc860098f80b514c48c180ad2dd6090df4a965fdf650bd783b8fe7fe5a1100	1668355506000000	1668960306000000	1732032306000000	1826640306000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
152	\\x628d522a3a536824799801567a1447f0220eb0c6dd142baceb9c3876e1841462e99b343fb5e5b0bc835f38e8f3cb1bff72972fa706bd2128d7d8c4ff57c73572	1	0	\\x000000010000000000800003d0e2cff953ad1d250c41971a47fbfdc1ca1ea24e7932c57430ac92a1978ea5d217d463a6db07bc3996e53ac0848d8478d8f1f74ec4c09a47afca2d4d932a535e7c7d4655c51b0e2838c16775c7306753531828bdd39fa0e21af628177acfd8062a93654df3d1d90e31039c97660fbf004e371293caf055f34f90c730cbc002e5010001	\\xd33371ab0fadce214c7ed3e0aa9f9e7b1ed11dfe518f44beafbefdd37f3e33fa0c64f41f8f7c40a45524b41f5a49965efaab3982a95c4404f844bcfa29dadd07	1667751006000000	1668355806000000	1731427806000000	1826035806000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
153	\\x666992e7ed1653083c63bef6950e9a95df8676bcf96e3689e5d556683f244618a95260e282da20ccb64fe3eb5f831f61ea5cb28fe155dd53201872dd3c9b2a6b	1	0	\\x000000010000000000800003a7a11cbdcfe0032674687a47ba593ead47555f71d78b7bf2f91ec1b7bf67b13891cfe5fd7031f94d7bcc1ab53acb8e8c3fd40b1815c2ab91920d2abe98fe323727e63d9a0d7e10f70df6d31274ffd7e99729d23e13149a5638bbb99da1f2405340d673d2d22f73ebffa1c3d623c7830bc6d01dad80af811d37cd3ec62c75035b010001	\\x1f76ac0e6cfed5fef11011685f5e4437caf3c7d391a75315a2e043dc9020020ecf2b6e68512b329ce428086dcdaa2b4fcda6ca160f932143b6d12425db485600	1655661006000000	1656265806000000	1719337806000000	1813945806000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
154	\\x6a0d5517c51e8f01002317ac00034d817342db62f2be87aeab89b9349617269eb2d79ff42f646700add54a6f1c38b043fa5d43eee4ec91385bf4d91e369a0efa	1	0	\\x0000000100000000008000039581a0afaafd41eab7e02ce125623738677189a65d9ce6180043b33ad95d6e265f8750f0876033cc1b70f75de61f15425f137bd28f9a591858901db5181a09fb089235beae2a4d06aee636265a73e3aa8f1c84de9b6582fa03a3fcfd6540ae4160f2135e0789ea289bd40b89bbe07260cc1d2df4b1add1ddf89b080476679abd010001	\\xe1738d511f581c90954c4d7106fcf86214599242ba343dba4017889d744432f745e314aae1b701c0a47524b5e2bad7f95d6dec5e357d923765826f1da3c60108	1679841006000000	1680445806000000	1743517806000000	1838125806000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
155	\\x6e71b271645f2358fd44933ac88488090f2e66a8cc56a79f3911aa71cf9cde905b6bd4e9d1b4a599fb28a256ac84b0ab3b8c993839f0bd6e82ec41ba4240e3d6	1	0	\\x000000010000000000800003d8443421672d823b412d96c682700c1f5ba6aa1e31b80cb9f83f3f48f98ebed6ad415fbe4de82826f255217373e2e707f61a09baf48e092dcd544dc73e856589e2cd4314b6854a4fce39ccf9c64414ec697aea2c1d79ce8e8326b1d2c8f1afaf646b5472264d13ca0c283af53cb6a540d429c25392031e79819465b196cc1d21010001	\\xad64ffaf6dd18ceb71ad3f5b7eeaa5ec544e1cbc0b88edfe4a6fa161e0aa93d594603d4d3967d68df567c772140d164c4f558a86626034e4e79492c0c98af90f	1670169006000000	1670773806000000	1733845806000000	1828453806000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
156	\\x7395ebbbfb579a9257c914362762481ff8c13b1a5e9561c2d87ed3ee45e1dcb668db29e551caeb93f27e38facce36b3715c665e33382ffd84c87a2a3c2f9efa5	1	0	\\x000000010000000000800003a505630829fd782027acdb3687517f929bea9efb06d4e5e897a85f596b89a3aefcb1b6553f46863302f0b4bb1f0aae1e341e3c2f2f4e493cc1f51216b5a9c57b4e46a3f5ae60a540bba5e1afcf66383e06f2062290ebe09db598730c0ac303eab7ad1db424e183b7660b9356618734f43a33ae8db2cd9723d8cf9b3a035d3f15010001	\\x9f455913f83e788a536225a88e18a8002760eb2dd6bdc5ca40c971b3d1a12fc0ccc9b49aefefcda5e063d203a06c9812217889427e846937368aab685a8fc40f	1676818506000000	1677423306000000	1740495306000000	1835103306000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
157	\\x765908b3cb4e80229492e4de8c0d3de384db8dcd7cc5a986c354b7faa5fa16559b7c0f3d30f265bf3317eace96eb60aa1c722406998d4b76efe293cf6c502e23	1	0	\\x000000010000000000800003c646cc249a45fe7083cfa8ffe0792128b9b229778af3a53b333e24764036d8f17614468fb8dfa5d4c42687bca6a660201bbf633ac61268d93832a1e9f1f05a9d517f3251f7558a6d039c8e958eeab19c72a9a22df39fb8d624c7fc1278485b3237c9e94610d35a0405576bf6ae2195bae9690008229133ed3e62d6f97e2b28cf010001	\\xbf8280c31a86ae898432a4de965369df07fb54e216c207542aaf9e4f6abf2213dee3e451754062f82f69ed5a1a609728b59aa99b34107aed3e221ddd1071e10b	1666542006000000	1667146806000000	1730218806000000	1824826806000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
158	\\x7861674667bfd2b07f36972879a36d1f8c887c963806c040e2e58c09f19448e9c883359352f3578716f1ccb18e0857d94cf5019b73ae15fea058273ff3818592	1	0	\\x000000010000000000800003cd43efc1e6352a90e23f2eee8b09081c82caad27390f330261d5bc9022c1ca67efab24fc3d013a36cf39e55d0081997dd83b43dc76358971d6eb243dc80ec9997967b993d0f5293f30465964e2148561a284cd7faafc86365148fd6a602d579778858d1d83e8c197ef1c8f8d479bd2c9e45f36716ef7c9ce337ab48323103555010001	\\xf2d1402ddf2cde6bf6387f83ca4ea26da4aa8b3fe1c8ccc3a1d77570edf94a9c2382df86d914d969769040decab810c495fe73fd33df57cea91e88fed5447a0e	1667751006000000	1668355806000000	1731427806000000	1826035806000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
159	\\x785d213341287b8df5c12199be790b947fb996d38829de2ae6f7f256ac2a479179a242506e641e0b823457638e142194284019ea08579936ff6623c822893682	1	0	\\x000000010000000000800003ca85a4dc32984ce4d1764c4ce76bed511fe0cd54a89965d8cf24e4df4bf561e66abd18c7549770225235e81724acb874c0f8b449b00235be36014ecbe25dc63733d6f436e0888d1ce0cbd157a51c9eab1fcbf1c939879f6951a782f2c80bfe3bbe4cf7057d94e2218e7b9a04d6f954d4a51e47c806e1c6def3bbf84ef5660d63010001	\\xd74f9f89f7cba7276a9113fb6b89b9adc657e9dd6304ed66a30e18ea9eda38667c7d7592adbf468f97a6ddd5ace752c3cee30bd58df2e634c47dfc30d1bbf30f	1650825006000000	1651429806000000	1714501806000000	1809109806000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
160	\\x797195a5c77355adcf92a4f61e7251916c5431c3b5584918897217cca371bb1b9af85e7163c9136e8cc583b52ced1ec15683323f459f45dca34d41a224f9b965	1	0	\\x000000010000000000800003f46bb9f8a2d1e7bd6b8ba19c027ea3baa660ee897795520e339ce14e06f4ce62db3a83f4227a92a1f645191b8d84ec7f2148b33281a74231557486e5f2971c8c58a103716566817e2e37d58a954955818734056a358ab47a3154340b4eb780c98e3d7fb33bcee14531414071e581b83dc2ea7065e103b3c1f1fa5a645701b5ad010001	\\x78b1d0c029ee7a1cfd41f283ec8e7b09d2f4766180d031f8d1cbef3fd16198c793fe9fd091fa980d3853f3b0b7e91135bb150acfe3179a3df1bdb06b1b672c0f	1652638506000000	1653243306000000	1716315306000000	1810923306000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
161	\\x7dd575549026e5162ec80b899eb3c4d01ad6b4d1317353353cf40df36fe04d2d439246ffb1b21ec9af6ac9ab0963e7362a033c00d15110275d8963fe90ef2d1c	1	0	\\x000000010000000000800003c7a5296f6d09d0621502d77f75b4403f44ab731dc3515c1fa073f8998a2d1b9256a9426bb7a30247016e1a28d8fb4a2a7735b8dcdcb8a91c4b6cbc9ebac37fb23875545faa7f0fedacbc73adb7bda4a49906f507a65ff6f8b6c43c210eb5f3e5ffb4bb42594d3a4e2fbdb02d254fe6e4f83406354d690571998a782a5098a647010001	\\xd126c09bfe19172bf53c6a2e59cbfe58c26f984b05bf11d7a9f510410dfec5b1c26819927697dd580d0902aac363a17b9710d8d6d4b8c08a5e322f1f35c67901	1675609506000000	1676214306000000	1739286306000000	1833894306000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
162	\\x80bd01c1f997b1a879e70d21023a327055ae1d0ad0a808be123a4318b91c2e4654d7384dc8cbe14a3bf889a49d0b16874af13600b8c40f2a4afb75c4dea1c268	1	0	\\x000000010000000000800003b48583a358f7f9eb92aff2d87426438844efd6537c1ac620f5b0a150a3d4631c29b1fac31ab99a6bb6bd47f8e85dfccd450343ed85bb0a392abeb5313ae3a635ef633ab9e94c95d9ad77f3e22abdd1809d7528cdd6f5e9d91c18732ae519a435eca73845ac2a0bb0d1daf16984e046abf7c8a2dd9d7ab0d7ca142afbcc00184b010001	\\x1cace756425551f2b99991944190ff283c391f45063f78f2b0aadf0fb61b1b7d55762724474591c886fa8b390541f949bb2d2326345f4758f28680b06a84a605	1656870006000000	1657474806000000	1720546806000000	1815154806000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
163	\\x83a157d7455cbf8b159b76202ff33e28c1d87c14a437d93edff67da6c8a9ade9fa3f9d452a4df861ec23ce98260a35b1372571a3babf923acbb6a283d1df7bb9	1	0	\\x000000010000000000800003cb5a2c4e688cc2b5bf4a382dd1ff97986a34acecddd73b4c8bece4fb3b9e017e9d08967db62c805284b8b796408545b099fda1e7ef16c2f7678a12af3f731f2362bce3e05043af71b88b3ac62127a24c9c5ab427a4b676c81994f1013a9e76d50a619e4cfbcea568c582a2328fb747487f8062411d99a1b572ec8ee4063edf11010001	\\x286db023930306503b6810babf2bc73a96152e77af9aa713324ee8a963d46ece07542a5ed8c2d1eb22e16ef8d7fc8d4384a021ad0426cd884b3b1db29395240c	1673796006000000	1674400806000000	1737472806000000	1832080806000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
164	\\x8409031104eac87ee56cdb43f61f4e80949440766f80bd318ce5bd89f5833f11e2139f1cedac8e149fd5755b96bd3f928c279fe3b5cde1db7798c76890445c47	1	0	\\x000000010000000000800003a84ef520fdfb55bf72cb187477f66b784f7e2dd56ee8da2a9759b19685f486636679c29c2b74e3e59ceb585f403035dafc9bda967ff0a82b158e9d002206a2cff4ca81e340ecd9bdaf72ae36c0f6ea50ad4e1366846fb4088aa3de958b31951f9798dc57f55a0869bf5bb7283d077738978b0e02b70ca15e6f956f68cbf0a47f010001	\\x6dcd4eed28354ff6832a3ce8f769e5c03dacedb1e0c3fdbfe228e9d8c12792bb41bf515dab410814dc2df2273f55175492355429fef9dd97d1e2036f80343a08	1656265506000000	1656870306000000	1719942306000000	1814550306000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
165	\\x86d9fad2bd405d1bde3a1f293660003d7c3846dbbd6107d94811816003d61b2937475bd99f300e7c6044b978675408ea1319b8a61c7a106f0b2706b387a57ee6	1	0	\\x000000010000000000800003c8e77c31f2948d624406f1d74adee066e419bf264d2eeb1f70e45a1232e21c4e7cc9f1d22298e94a5b1fc4837ccd89479dcbe438b4d4f3028d6743d76c6283953dde7f54b93a265788057b8418622c8cb86105db6a5c6b6c997fbf07307341e2428f443c5afb58d0c08cd09a5e75bf4db8041a4b75130a771dbab3903c843cd1010001	\\xbf8beeeeb92006b13cbd3c795c576003a8e869adfe2b11b9d90438b31f2d5b2a02f8865b42036c58e7ff5fea09bb4e9e77e6dbc25311c14815e761c9cfac050a	1666542006000000	1667146806000000	1730218806000000	1824826806000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
166	\\x87357ad13186ca09149bfb3c604c3bcb862d0b194fe7ded8655227148e254d344c17beb9507d966ea6ccab52273cbb7d9dac1158c63b741b2ea058487306f934	1	0	\\x000000010000000000800003bc13f6483580afb2a8440e1125075eb11466c2a80d9f7c182bda3e14f8e51bef4a7032f3f3935e6355342d519acb378a32592ac707826118228861b931002ed96bb92eafe35e252260ab6fb501a7da6f2cf603c019ec3a970c862a14e8823fd4aaa88f62b8f64d4442997587483bf720d6d6365699dfb090eaa089b69e62ebb5010001	\\xa9dee0f7b60a663eca385a76af3a9785fb68477d1b0ff7e30c8e4d88fdbf77a2089edecbcbc820c18be08187f660f9f7e0fe86720fb5c3295057eeecb556fc03	1679841006000000	1680445806000000	1743517806000000	1838125806000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
167	\\x89f1b4155b3589d172bfc7ef54b6ac24d5c1cc50e889c4fa410e2d5f9e151f68cc86773291713e0c3c62067f846723d7c9da29c38eb344c0df7a2643ccd9ac3c	1	0	\\x000000010000000000800003c0f9a7a3fa7bdb5d2944bc810a36309e5d703fbe3d7c4260ad49f7ca7117ea5fd2318eff00af1bf7bdb14c894164d08164b531582a06edd5348ddeea768002a505aaf206b6d109420018e1d3f5146261baa897f99c68fca7c363042d4aa52590fdb82c5c2a74d70f234ebb129228e84d62bb2086b2d6328b4bf97469040f4859010001	\\x0e488257cfb8dba24add40602cae0ae86a80588d9ac4ac81096a72c431c5de2e4e36be55f910981360e707de3d8bfe197df3085562f54cf1df4a39629c472c09	1662915006000000	1663519806000000	1726591806000000	1821199806000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
168	\\x8ee1d78775807c2c14be4dff12f1b2a977734e3fe36f88269fe7faaf7db8af4d3aed8ddc89ba4b80836dd5e6064f5806ce07e4bef4f3b5d484d6222800c0a2c2	1	0	\\x000000010000000000800003b748699c7c7090b1851e4aedd4f7c3aaea50d0969ea7dd0620313c9f21b55f3bb0b943b1454df4410561ccd9bb22f66300f3c794ebc083c8bbb5801ad805e11f65a4fdcffe7de15e4683fe62ff253fc01b43f4ca0bfbe162eb146506eae1004cae607461cdfaf3d4b6a24db84cef0477248c58ddfe97d28c64523906059152d9010001	\\x4bf16c2a9f5c216e942866d7008c016cbaaf15561e4f0c6bab633426b6769524b8fd035d0a780eb17ca06388ff0e0fa796487e064e820130e8f0300c09093d09	1674400506000000	1675005306000000	1738077306000000	1832685306000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
169	\\x91d1da07b6476eb4cf16acf4d03fd396641a1eb50c565e49c9e7b8578f7dc7b0e6d110ca6d9da889d164ff1eaccadbf94b3f5d762f471f4c9de6bc343525c23e	1	0	\\x000000010000000000800003eb62e39f302cd2ca4a0075425be07460e3fe82bb2d2144699ea89afed2173465887a1ae90efc9281463b0f2880289cbcd9d2b07581318ce04f66801a0b18151d90e1c1657d11122422d38aee9ac56500b84a75c2b32ab09a4a61a9822bc07a8c61ab1c863bee8783c996375bfee3d0aeac7488067d02178f510dc5d0f4ac3df5010001	\\x8d95d794659411f97a6cc97077a99f11d5b92a479f54972b0d636ca644f29298731a9afe93c81ad872e1cade58c864f32efcd68e36dad9f67519abf99f997b02	1678027506000000	1678632306000000	1741704306000000	1836312306000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
170	\\x93491b6481f80b1218560a650b887d07758d7eed1ae8e058ec7387f545b670b17a0e5e0fe060374e133cb14deb54a98816f946674a2fb5b20b129f9d94909d10	1	0	\\x000000010000000000800003eff2b73b4657c8834e56c1972da202856705efd99178380dab2538f0d07c75cc6197e84c4a135ec06d7577b74dac02089fb4857bc39c109d5b18d1c65a1f93f0b812356f1076c91ddd22a3630bfbf81305967237668065b53566577513c0448ab15c4b20d914356c00d212089b6f965d17cd179914d2673640430a36b507bdf7010001	\\x157b709d8939a4680553237d376a42282bc06b8aacdc9b6f825d00a06175bb4fd12f018ca4b807f3f7ee5bcf85ea955bc316e2071df4b26275b4f525cf973707	1674400506000000	1675005306000000	1738077306000000	1832685306000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
171	\\x9625bc2abe9b40cf18b1ffe816885d46db3b32eabb9f0ae0470161be136b88403dc4d35287e792ed98b7331b75c076f18403d81397303fe612389015b9a64186	1	0	\\x000000010000000000800003c479cc464f6414b0c47e00818c8ac6a4854ac61c4ecaf05b6f935c8af6811b9e9d848a120735dced8264f5b6b4221c67059d5b34f25f190db1c5d8f6d6c2c55b4a08aa17adf6c0a2dd45e94f468ced3dd6f5883d1c8136a4b3782c8282a418d97bf46128d0fc54d4b7b3687134504369b370b2a834222b589b306ab1ab689545010001	\\x41373ff0ae4a709d8deab2b1bc0c84b1941145cbbbb0cd4f48bb17bc357488b3dc937ed1b0f77bb179cec450781ac4df8dc6e14652ac850bfb8b7717cff99907	1664728506000000	1665333306000000	1728405306000000	1823013306000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
172	\\x9d956e1f15ca639958121b63f6b1cab0007ecbdb7a60690756ff398f7fa66b14df4f10e42d26cdb716e369f303237a9c16a8c6412f854413a51074db168f572b	1	0	\\x000000010000000000800003c4ddc15e3a558e8733adf6e0082da14c667c5ba45d1fd43b0c220e14d3953938de24cf21f1f63b062f3072b9b0da4193158ca206d991feb7b44929aa966ce145522d940f032c97fc4be8a1a63b7b5d542b4c05b4afa7c075ffa75b2cba5ac2f184e39de35c6896324f16822ab4363fcb2fc3503a2cefeeb544983344b0121017010001	\\xb15bc109db903a42e1f1ad5da0addcdcbd38f6087cda23cb4a7d27f0512914be472897dd259e86978fdb28764ffab3bf75fd18c6bb0405b76b4872ef43595a0e	1675005006000000	1675609806000000	1738681806000000	1833289806000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
173	\\xa3b57da09d39b491e2f550cbe8fe0a726a0c9b28633d727650a2bb099fef35bc0e76e74a6b10b411f8350e06c9e1a5733ce124a3be1ec5250e84c52598f573b3	1	0	\\x000000010000000000800003c896144d24b15faaaf1e8f9bb54c449f71ef40c31c7302dfe2c5bc4ce8cc1c98fb528e4afcf26255dfe4b46e78496c7257fab797c41d56e670b579a5d563c7a6a9f522627117893d5e2ba2a78b19e1869e23edbbb15b33ec65c57d845d77bec9b967b57b9b76167b185bc9ae4bdf73ea86a64a119b8d6a4a8e7c251657b4287b010001	\\xe4eb49d2614b313ff4888ed492bfc7682bb4e5ae1350cabcbd6293cb19e4124291c6cafe5b90a6b95a81c7dbe410724eb57bce9b27aa8319c574ee74df7c110a	1665937506000000	1666542306000000	1729614306000000	1824222306000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
174	\\xa30933852887fea1a28f619b84b1aa89f992232c473b60331db68aba718af8e0547d6e631c7f3adf402e51f0b5618889e6cb866b2c826c1bbd3223bec5c59fe2	1	0	\\x000000010000000000800003a9258e4bdcfd28b59a2f24c0b66c1787ecc05dde202b5569fb596b2a2e071b24594f251e8eaa9d716e6d3695a1cfda4492c0a46ba699be36f07e2d3f626afe9dc34c4384c4db4ee2f62e7745d37139b5a3ec7bcf7b9a88c8d1a0860c292e6678c1e40dd8086f9701d22497bd8dbb5688b0af809bf436c78e2aac3a40b09555c3010001	\\x09741d7658bf3fa91bbab0e1cef6cfc627cf6b18831ecd4333b8636cdb3690323b865a85cc1e2774226517e57fcbfe18e3c2b761575ea9412ce2889f16577602	1659288006000000	1659892806000000	1722964806000000	1817572806000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
175	\\xa729aa94e7b096f67ec4a354bb314228cdfb2cfe4d830259a1aa4276a02d649f2d87d7452448260ec94a1eedb624d058c2c629f3110c54035f1c54f32ea11b78	1	0	\\x000000010000000000800003ad159b0ae802cd6849c3b806f499ca3ab34c7febc83defa5af3e3b6795aea803bf03e52cb4346cad905a51b0778d5ae460652ad23f78b64012e8f4823e4e934f38e87e05ee85ccc727761c999befcfa741f8083c0ee489a0cd865563fce9871c10af5d5fd3d2456be0ed14083356651f2d41702b0a016edb7abde8988a3a061d010001	\\x877e85195b7affc1fb292d54f2db4e62a4f5ee02b3db545d00d3dadea72f5952dbe39cb89389c20ae8e5b1123e98193aa3ec0c15ce073e851c7cd5f67ccc6200	1658079006000000	1658683806000000	1721755806000000	1816363806000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
176	\\xa8fd6c9866db2c063985768f200cc98d72d3b5ed85cfff6ee1bed6d3be1f5b61ad309517fbeebcd10bb1de2e17527fe65fd780f0e838649ff13420ae8d4d694f	1	0	\\x000000010000000000800003d23e52a737fb9f7f921ccea692c3973adaf0bf2d3d15d54e17bbb1851ee85571632ae866b05a87d747f537f10436bb5910089dfca74cdddec8ca4b6571e32f0c85c997b157907fd943382e9c903e49e89575ecdc9f76df0f14a501c3126f30c0b2d54f0a172fd5b6d4e7dbb8aa203fd228a8443f156009f7a2e938656e2e8547010001	\\xef1e074eba756109a7912c1d7e489f27bfca11d42b16bb256f0b5a9f7947e29f753a567c68804d355b7fd08d0b6ec3f7d1cb6754efe8837570237c7e825c4905	1656870006000000	1657474806000000	1720546806000000	1815154806000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
177	\\xa9391bfe4c4eb0c670a352ebdeaade64450c5176edd1c05af0d9a70d719756778d2fa1b39081dcbd27db853eecbb492f0941db54411fa069304c8a387391ed31	1	0	\\x000000010000000000800003f16966743483cca37e9b9f7100f0771b2a2e2ce5c473325939bdcff225bf26a6f15e98dd672ec55c9f48213bf3279d280743e650ad5fd7a1faafc9119b563f40a5e6b0662edae016b5a98e665949e6ac732a65dd083189df7b0661b1bec5e2a6241f9bbceed06e37fb91d25c34d600329d55ce3c0153b29783facd976da1e72d010001	\\x76ffc4e550851a322e33013c1113cf74c262a8104bbd01e363251bec02052211d19d6e39143c6b525a55e0ed6da679f7cee66d1370d14819673e40e7d0ce0504	1660497006000000	1661101806000000	1724173806000000	1818781806000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
178	\\xa935175000c90bcb71eb79587102aa729005ebce88d0a4bc9b1dd5741eb33951050dd8dc2224e8bb19932750babc997e08383993bd98aeea5e58ad3a6c4c8dc4	1	0	\\x000000010000000000800003cc9c5f338528cc1697073db0c809686c3af5cea7d815b62023c50fafd8c4c7c3137c958a3447a72c54310463d066d2ceeeaad7e5228c8a3f921a1398cad6d302cdf5f79627c34444e75940ff55353bb40469d913a4139abd8dea80192581db11fe40a934dd659b353580842ae8952aca96bff8f5f9d1497b95a0e954fbdd47b7010001	\\x37adcc10ecd25dd58d0c02a9ccbe52b9a36574c1aa204f5c8d7a112a0b847076c50233f799b15e4bf24b6c085e615233b75fe601e539556fa9d3d7d93f544407	1671982506000000	1672587306000000	1735659306000000	1830267306000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
179	\\xaa29012eb2bc0431f2052549b2c68203ee2cf7ab571155136851a88186f2766f1aa5520c63e25de0aa21c11f26d8f7f6bcc733c9a267818e1d521f9372c5f6dc	1	0	\\x000000010000000000800003abfe1ec619a851743f3f37d2f1d6282291066493f55ea6c911c27431fb28e4292e33c65329b6b67d4556ed21fc6ed6aa97b025f3477730452e1b714cc3f23916ebc59328c3f60a1fc0bebdf6b53faee559b35bac9ddb3ecd16c055b2f1287e691fc177f063ceb6253a7387167756747a5e259000cb55514c9fca9c8c8581e39b010001	\\xb0ba9673573fe9dc455f3b8562845a66aedcdc6d3a5ed576294735272e8c3cd17fc7d4bc1cc182595fe1674a7e8f3ded8d7db1d639ec3f8aa7e70132f1af9409	1652638506000000	1653243306000000	1716315306000000	1810923306000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
180	\\xabc188851b91f84a0a2ceb02d685c854f91b2867539431d6c8ae1c76f32b3fc54dd77dd5b13112bcebfbeed148ce5e99d90ef40b9ea6ad5aaa9f4e759612114a	1	0	\\x000000010000000000800003cfc549fc78cc41a7a894a5c643766d4c48036507910a06545bdbfb29dfd3bf21b9cbb424eac06fbea52dd6f3dae0cfa8451539039f6c8a3f642cc9a8d05dee7dc6c8fbcd7c3108ebe9f33171ebe4a3bbfb716afb9e9f4cb9aed19ccf0153237f8b42d8876d8b3abb52ccc2cec1340bc2ea3790a561b6e585e4aceeec5bd3cdef010001	\\x96a243f5336e43d20948b7e68d2a074fba061d10d4246889aa0fab9e24092e6437b4691283b4e63090d841664abc2079bb41a87511455359b748824f44f17a05	1682259006000000	1682863806000000	1745935806000000	1840543806000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
181	\\xaf71ba389432909126945e6040c87eea80c471e07e4e0f62d0bcd187b6ade66c9d4571fbaa196dde656b869c6f69216402379df717800eb202af2d6eb78ffa03	1	0	\\x000000010000000000800003db06447fb7831f83e4269023f672cacc38f613cb34bf0882233ec0afe9bc1f6d974be7f9c15f7cdda527d244dd91f130b689a9a08efd25f38bd31b27327bf1b9b01dc2c2ccf601a889d61e49349cb992e4839e65f971f47f8242ad2456cfd525f4ebf34b0374681787b3aa786cb40a1227b3d762168811a046a4e705e5acf865010001	\\x2853d9ead3e11e958c660d212780afe3c08ae6c367fc6ff829f9f217bdeb304c22c66659cf70881bf4eace49d409a8b1aa52dd0bd594bf12319732b77c7d3505	1664728506000000	1665333306000000	1728405306000000	1823013306000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
182	\\xb17dfda3c0b14cb2d49edbb656e330484b1da18c9d407beffb3f992d05c4889467f2fd6aef18d272a0157982c9b3a52a27d9cd1c0633c5e1fb776418a07346a5	1	0	\\x000000010000000000800003f37996cc0f2f8315ac9a1d2ddb3a9569be2ad884d815760005b083e3ba433b49c15af6d7e4b922983e832587cfbe1aa8fb1226a26da3e09a4c9389b509b5b7bc753977630cc8dd3c58498e1ea9129ea56bf629db94f9d260fdc061f25e0d86742cd2dbbc49b863c61c20424a3e6af456d3194dbfd940f9c557356923e5546e0f010001	\\x5a3266cc338f16c0ab82340bdf4c0bf1622274c046e416d4f87148380c32d6a762efa1c44f7bda586dc152bf89cb0b5109b7815e8c0fd3d462a8faa4994c3c01	1652638506000000	1653243306000000	1716315306000000	1810923306000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
183	\\xb481db1fcd8396f91c8786e6ea2485a87cf643945b324a68be34de61b4ce1b6bb43b9d2d8a66caa178b8bd088e2555d31bb3ae7cd75e79973d357a7484431ac4	1	0	\\x000000010000000000800003aeb14ccc4162624ad2061157d8b74c35d079d69b0b631e23f4cfaab659fb2890049e3d9f8a99c3afa9c5ab9bd0269a84c9748d02a1c81a3be96b70c8d4cf243b356fad1c9223e6b5852b342c8bc19de161b2774a8138af330f9c3ee5effc4af668e244f236bb4e7d71021ddb06835ec151b32e59b148fac01ef403e53b9b3a5d010001	\\xa18f9e0d0a7249976e5169afc07f98ddeb927032bd8efddd457d9433f061d64adff8df5a6005268813d0a4f79c3ac5bde78d1d775b958f2d4dfd8a8a35ce1b09	1659892506000000	1660497306000000	1723569306000000	1818177306000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
184	\\xb659921e589b89c85711df1aca3904535583a8baa1c1a43f795ad7aa43d89523361565683a0d36684cb96c6c70a6c9f7242a42bd16afe85df7243e60e1d1d2c1	1	0	\\x000000010000000000800003a93eba0a0f36b377550f2d46b695c61840758b8ded0024846d6c50a9cb3bdc42e59481775f9cfc1b5be583dccc255109f7b1c54a9831d48270cacef8412998d8ba0e140c6aae19c312a2805ac490d8415241c9cd84f3602212a95f1c7832f6d55d0e6436aadabfd73be4b2c2d7e0754ba067fc1fada1c020007413fcc8e8a04f010001	\\xf8672c9f3d2fa6e045104ece2a8edeb51047d94d0fde7b72f34d8dc19d17bf23109c3efba432c0c07d2edee7f076e005c35035d2e5cd4d77dc5c17bfde503903	1668960006000000	1669564806000000	1732636806000000	1827244806000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
185	\\xbb1190bfc66540f4c03546626a573603227302c1f925c9ad3caf202711bc9c1f323fadb46f75bdaffb906f3db28f94279c329f1eaae3898407e4547e0b0b0b00	1	0	\\x000000010000000000800003f63fedda91454883c0246c7ca13bab09a885eefe8b27223c34478477974bbcaa35e31019bde2b3d93ddb5e87343de54286cfaf6fa1ae4f1c2caedbf215d8f2d39e4ecec546fae52515a342684a9490d8073d86b39266f08887b1df462cdd4a7a9e51460598ee3d7a5fe9bb52e1bb3583d969d28a0dca34bc0173e4bac215fbc3010001	\\xe53e398ab1629633363bfac63f84191f6f462f16a6db3150924cecd9ab7b7fd0fe740747086d294c68f682182d75894e1e338235ca9429032760e39ffc348700	1679236506000000	1679841306000000	1742913306000000	1837521306000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
186	\\xbd29cc989fa93bb872fe7d3397d88d8edfec8596ee13b60f7db26d5677b3d704a882349525d4e3c427547e06fecd2c1146f25ebe106e43f178e9e2626775168b	1	0	\\x000000010000000000800003a949a37e5370ee5f53e8593b5607ce34ffc9231f6b85f5dbe321f85b05cc31bfa3bd511b1c9462565897134d94f6413d4bcac3411d7776d5d4db8c08e4edb7b91979adefe06167168c1c97ccc2034a824e57537f06518cd1de35df1940e43e1927fac217cf67be68aed5337a35ba419d1e72b6dc37e2a3aee5cd51a34c816049010001	\\x6229b0d29f2944bd8c9499d8afdb4b70e6e32ef83f12bc1d11c3683b5681aa0994ce368fda2efaadfb555d26911f78d2cdb57f6013fb399ccab4cd8a91fcc409	1664728506000000	1665333306000000	1728405306000000	1823013306000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
187	\\xbee58d87fae988ad2332fa98634593763f5b3ae68f46dae96982d4d9869e05d842ffab944bd98f978fb81d8744aead1368c276b160f983e5d807eeb8e3c8806e	1	0	\\x000000010000000000800003a3f5a05efb819cf087fc0743848e171b3c4b88be0270cef2490796793d9a11be6ab1770c05b27b6c031d5ca2988745de1a2cf58bfcf3e04bdd2d7ce63b3528a63ff15f4981d40256ff3658d5c4d98188c7dac38a54607b1b4655862ede535bde57ee38ea0956edad6d9c27cc51652a547a803924fdbd64da9d2da5dec8a0c815010001	\\x482530a35c0c038e25d0c360581c5884118a05047950947ce3e4f14c846f9594b08f2bb9faa51256ab9b106ab508b774638a3dc200013e5836c3621cfc08c60a	1676214006000000	1676818806000000	1739890806000000	1834498806000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
188	\\xc17523635c92b260fcc7a11082c1f3537db004e9ac745cdf21bf934f7b3ae33e2284d1c8debc406c39fa9b2cb87219c3e80c7c6883b6db2a4e3065e023b81986	1	0	\\x000000010000000000800003acdefd15e6a22a6b821eb30602b6e0be677be3bb4eeca79ea7a75e836e03f6b9d52666d1f7e9314c7e42fde180343348b38c306dc26393db86c328e39f96a3e652d56ff8765a8ed8ca7c11c1ea676c1e892f01883a59a38d0c94fb3ab36299a595bc9d839891b9dd141ca54721c2621c258859020d3a5ea320db5454b48a3a93010001	\\x7b95739599662493d5b4d44291609a64cb301e5b871f03424ce3e1738e3d1383e286208c1f5773d1c91745aa08783be26b591f0986328e9c85ad72d4cee7d702	1667751006000000	1668355806000000	1731427806000000	1826035806000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
189	\\xc15139992ab74cb1cc247a3354b06f30c1cda1e7351ea82988b077603946e9632bc059c650c6f887b106e70cde37f0eb1ccc1c9eadf6656e4dcd51c573327a12	1	0	\\x000000010000000000800003d06d47f9a434987d5ccdc1fff7896d6e4af237dde57d9696ee7fc514d90b3ff5a9e00c09867203c686da8d8e48211aa75e54a218eaa08e58c4aa5d1e232c5e27cce9eccc034612689ff9beeeba1f15fdebfc18d28acbe95b5baeaf8d6fbe51d23b8f211bb3fc825bb187524e4bff6c09c946b8bfaf97d64530f55f6112f0e85f010001	\\x477a71f5a88969b7a2355f4588ae63d4c36ab09ddf4099d4089b7d34abf0891fbf8126f795fe6106a1a5f7eaf55d2c5ced4ef012c69794eb0964f0cc55c20805	1659892506000000	1660497306000000	1723569306000000	1818177306000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
190	\\xc26d4f09dcb80c45adf81ddd2d3a30b4bfb9c04874af9d537e023832043cd9359e02a8deaec98eee1d4a4ef086bc6b9e5127a59c906d1171ef5766c93e7a3faf	1	0	\\x000000010000000000800003da7a5ed2d661f15c0b361cd719e047af6c67d470497c891c91fee2d59dd496070c2de4eb95834050057e2cf302087578d064255e45d14725450852dc140b535286f96d76121d377ba94cdf349af439e0544d7a58e2c8b2c2154de0ccf49be2f8f138570bf6450562df6f2ba03138738afd04b9a119513533b022227c5fe4e66b010001	\\x92e06ea9e614e5b3442c4a912e9ca7586fe4cb5a803de832d4b54e9abb550f30a1d912514a7b4772504ac237738446c1e30b9270867d2a8112fa4a2fa39b390d	1664124006000000	1664728806000000	1727800806000000	1822408806000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
191	\\xc265ec77748096210297075d586bde3537e5b41e9f263d535cce787effb194d3db20345666382d45c9e85e537041754e4cd7b0d421786fc165ad5c74a91a4baf	1	0	\\x000000010000000000800003b90ede9a857d8355080995d297d2fecf96a244d764cfc15c7702675e65cd6b37b50774956138cde41b7fa4a53fae261f2668371e5475dea864d72b2b6bc798cb626ff8b4bf9836e6a98915371c0e6efa2a2cab924f726020064b1163d281a191733884f866266d1f4a516b9ef106824564d3b6dda52ab4cdd0721491c0697d69010001	\\xd61d6e7d3b4aba47472e9965225923d882fb25f352d643a0977c414c145de0ee8c38ccc5a6d194ff5576c3743c96d8b7a0722c68c56403add6c93a2f9c455307	1670169006000000	1670773806000000	1733845806000000	1828453806000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
192	\\xc33598bcb0d9bce53924ba7a55d906d4ffd9bcc3acb5e8bc3dc9b0e8c02249dd4645ab4784c8c2ca719f337b308f73ea7bca2081d9256203b42abc5bcfe40452	1	0	\\x000000010000000000800003e75924d81c353a9da1ed942e4c3bbdc20853ce92e9531c83f2c466f61269466185ba7c142de0427ea2698c2d0627e052e98987882c653c6db79b1c3f8c7fd4282817bf90d18c72e2a89a5cdfd9ee18b5a4f46257536f107a79b5de783cea0aad8240c7f1c3a3fd4f1de5caf5ae5a6e92f7f5f4c94898fe359206b9a290ca4375010001	\\x7829e94f78620ee006b0b014e017c8ee243416583a97ff7e8555319bf15a7d61fc31c0f59592a4f03ade85477148dc9ecbb4a87ed7dfaa18c7b899267e37ac0d	1678632006000000	1679236806000000	1742308806000000	1836916806000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
193	\\xc3593664f2b433d19beecfecabbc08a5fcd6d8754ae36a52d0b1548f9af227fdabb81970c84d4673c806d6ec07d3bf77e104752b7cba90ca787000d309d50b82	1	0	\\x0000000100000000008000039f599c6065e549992d94b4142b016e6cbe199017545cd4dd1f1492ca84ac741c287e080330477c66e441a57e4fb19f65b34bb69596ec21d0b635bb7ba4e0e311f2e1e77e4331fa22ef2f04ee710bcfe493a011bbfd9bd576673f32c88775997928a88e0f162b14c8f4f68dc9d419fb4384b82712149e97f079b1275458e9a099010001	\\x3ae03a76f95eae4f4259ebfa18ee0edb85a7598eba6f79f50720dea6cebc3be26d673857f25465e129c6d2df49ee9a8ce49b624ebc84fcd051b6713b60cd0d0e	1676214006000000	1676818806000000	1739890806000000	1834498806000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
194	\\xc495271e367933dd9de01c3a3121274586df9ee1fe3b3e2c426db19d82ad97f9c9499ad5b26a428f2655f968a1ec36c6186f1f25f9dba0ea0a31e4b427ee79f4	1	0	\\x000000010000000000800003c2493c444c0ff0d552621d8d148ab727a7610e1e52d77fed7dcf96aa94b98937c023c4a2a77836010570a7d380a739eb3220818aa7f1be383e96a2c9367576c319af11ec9588c13ac801730bce2a3367b99c56130cc31a2c58f2453a4c1e4109466b474b7301f8bae4e8f8db1d127abae70099d4e49fe3a60619758ddf7869e5010001	\\x2fde1d42240897600af68fd0bf0339e04ddebc0fb3b9a1286854451a3d416ecaf1a4043552808c39c6461a059d60a43ce5fb4580cf00a2dab3c880a4f2be6d0d	1653847506000000	1654452306000000	1717524306000000	1812132306000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
195	\\xc4c10def1f5601e5045bc8aae5c35bb400fc5e78072af5b701b82efcc639c5f51e27f68e4922481331103597a2884d56a5735b83f27c6021bc77c616bf0c4c51	1	0	\\x000000010000000000800003e282a061aa650c71cf77401f29ad8f37f413bd0e82a3cdb73e5a78ba5328555c995f2d288bd0589259eb144c82b33e0ce0b99a6a9aa9d96c5fe781f3bab14d1d892e545dd004920d0400535be130a0d31e85692043e836e0dd02a4471eb6d3871e902ad07536af43288754a0131d2cacb14f407e14614f1cac7a760208ea4823010001	\\x3e799ad7ab16fa14ea6bb518fb9b637224b68e6aaf2e4f38a54052e09e83bc8014c11343adf1e0152e1c5956b91fca47f9791a2fdac5cd5af2e9fe1890c4c20d	1653243006000000	1653847806000000	1716919806000000	1811527806000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
196	\\xc96d6a52222f5ce407846bdbd748683b666addc1fd37c7ef1784a95895d6a0b9c1889c9ece3dc7ddf5892232c445eab6c2609e3e199bda2440ee589b0a24dd82	1	0	\\x000000010000000000800003d9fedb1ec3f2f757520b5ef6724e683c5ada1ceb9b2b11d7c5dc222c5881c933b62e940d74722784302179f41361927b05223a664d491c2a50731a735a9a0ff7dd46ef0ee260183fbd00ebe408e6de736b92b3d8dd06219463d3f6917d097d5ac54aa8e47d7941babd4f3e9b615a4c35eebdf3ab8cc6bd229cc8e789772eba67010001	\\x8f92da1024514bb7c687618580c977189f5b223ba5ed108d5d106465d863c9fd3c3402447c3b408fb87353fd8c84af6d94384b89ea11b84212437fceb095ab01	1665937506000000	1666542306000000	1729614306000000	1824222306000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
197	\\xcda9bbfbd2a951b7efb9deda48e4d3ec85b77b5915b553717c8c9c0d158964d6d27f8cfdf74fb832f54e1b191fd2e5e3fa4246a1ac8068c0562224cb43384c6b	1	0	\\x000000010000000000800003c4a0e7587190bbc06a6e6a29a8227f4c67fc148a0cd277d503385cca443c64be7274fc420e56750986cb16aecc61bbbaf3f080528e62510dadbfadcaabab72326b6f09829563116c52b996d1801c6660bf81e2e2fdaec39b0fcdf9ac36818b49384c34d8a962d0a7fd675ea3ad0fce2373ac484b7bce4ddf6ebbaf88bbcae353010001	\\xacc4ecb4f1a6ea917e354cb69c8b669b9af89b8445b73df8b84a7567f7e57204638412b134fabd0e7a979314278fd3245986837315f4882c13acf1999eb7d407	1682259006000000	1682863806000000	1745935806000000	1840543806000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
198	\\xd1cde371a5c8458ef8483379b96dd01bcd87fe274614e24788ebe126b1926ed912c288a684f4fdd5a981dd0ea080bceb9b634a92337bb60b15f3d7b94b153361	1	0	\\x000000010000000000800003c0e461258691dbda5af134b03e021605c0b5816dfdb5a01d09a31ddaf57aecc872e10e56be76a1d58b3da51593a43d6b434bed117f3b2aa51da92857cd86f4c418515f888c8d78757db7be9bf222c428e19cfc27f09aa26ee4998161f6b9d1d76135d1a70b15694f1c624db8a1f02efcefbc4343c6527982d83e1bde986d1cf7010001	\\xdc043ebb3732ffdbda028a72c9dfecfdb052c2ac5f276e0aa9d876b0d2f9065d803d548827a93b8ee257d1a72d4efb471aa239a3a804499edc738c915c23b008	1662915006000000	1663519806000000	1726591806000000	1821199806000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
199	\\xd409392ec355b9bdfb189b59f740d2737e1b85e6ae75710f1e5fffa22a0f54b1918d3c69d9b0a8d63488662e92588a5904ffc940eec3774a05fe29fee54bbae1	1	0	\\x000000010000000000800003b9a769cefd66a4a3ef55c3381beaa66efe891ad863f9c10e8bac8d787d0299812f61aea7acb40386db35c4c84f6a95a6731e166e3053f80ce6ce59559292f33bd477b34ac9f7b99241c0b2eccc1b3d107e756c522844dae0ffd474d834c3158a5a9a7af12ee29cf186f8220d42a6253468ffb303ed8f00a90c4e25ac9d927e37010001	\\x3ac836c7827a5ffcfb16194d1f7ec33cd7e5566339774c1dfb4a7bf0a6e5c5fc21e8bcde7c65fe791f5dfaf05a503e5c2ac38d981bcb218a4566f070c2bcf50f	1679841006000000	1680445806000000	1743517806000000	1838125806000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
200	\\xd919fe4b8ad81500dfddf3e1cb5ee16da998ae93c888f32c12a895db41fd01ba07fb5592c8db7125aa146691f46b566fb0c5670a35ee5b2b4f66445ab8046912	1	0	\\x000000010000000000800003d354e5f9680aab14ae4eb27287288308551d171e8686b31f716096b0069c9ff504c3a200509c56630d349f889ecd5157667ee4624452adf31532393275cdece821e2cf738efb375dcb1beddaaba512c5a8c1a368269a15fd8faa395e6c9c30daa6b6c2f7b3d6a5fe8a96029a89901defdd798acd53dde69db5d678ae78fa035d010001	\\x1b6984d822b3e2b29420bae8c564c865f2ddec1318cebe0ed6ab7850bfbaf9fe5ae3cee81523ff46c1cab74eeb999e5a1458d0a821a39252835ae8e284faa406	1654452006000000	1655056806000000	1718128806000000	1812736806000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
201	\\xdd39df2baa04d0834df613ae7642352886efb92cedc07143cf2c8f9472110ab8879340beef4fc368757becaf4e366353fbda3343a528535e0bff1080d228980e	1	0	\\x000000010000000000800003dc63244c5e1a069358de163ce281de9db5c90db09f899f7f50e22a0e5a210d7fb92081c95cd9ba6783b1a78068348fb8dc96d9661d19fd6a955ce3e3a727985609e1d88d967c85405b696bd21c82a8b863e00ce51fb76171291211a771f656697404af55fd09bcdf53f3c6627b8710d3d21677aae20dc3c96d34b06b38daaf4d010001	\\x7c6de7f2504d55b764b57fca43c1f80f02a0bdfe544f35c38c1909765300d70d119a9690144a28fce05db89d07bc6a935080feb117ee172f8d0b58fd96c6ca09	1662915006000000	1663519806000000	1726591806000000	1821199806000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
202	\\xe1552c6b39c05e58f2995efac6d241cc52bdaebf30a5c3982416e9eed4a7b938c0aa3216f3c8bc793b9c1c35bef7a7a36e3ad27532ea9c084f1a7f533450b543	1	0	\\x000000010000000000800003b2a8cd489226611d94da660a2113f98ca0fc5dd443db52ec4b4e1d58e6a3f586b7d8a0ae316091746cdc763d19e8b394c199d820b5104da6476ae7fda1d340553f1bfdabb672bb8e61fdb922ad3eb54939aed99b53665ec7b24ac9d7ad97105b7df73a0b6a46f71d1dbc3bee744b63e3ff40d05c1ceadb1ebd1e527d17c2921f010001	\\xbeec16997fc782b27bb172b0cce4d1662206ea26a1e4267363568246d6890a402d51ab6299e2a42650cd40ea2aeab3683097552d2f07fdcb5fb63c6199cca001	1675609506000000	1676214306000000	1739286306000000	1833894306000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
203	\\xe6f16ac61fa29b4c494678f1de36baf76857b0b834b1c45ef8fb187f34eea9d41a8db2a9fb9ffd146c8665fffd06ac76dc3dc34901304272c697b9d7523a706b	1	0	\\x000000010000000000800003c56d7147c577f679c58271284f0602d8b0511938ea37c9842b9fbd877e6ef339f1973aae954f4475fb3e15b6344d5a693733b9ba50925c9e6d76a04bcf94f7ea8b1d37b54c0d117a54afd3b3f8a7156bc5b52e750958b7f20c8befc752be8e74d8ddf6e2f23469907684af3ea32d3594cc297cfb5b34429369147092a6cfaab5010001	\\x0d42f8e8b6ae1d8f23592ee6e98658d20c900927166d2c337da8baf5e7a34f6aeac098a84518e6561f75320d8637e45f40cbaec7b19c3dfa6ec04b441bd2ca0c	1665937506000000	1666542306000000	1729614306000000	1824222306000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
204	\\xe9590a2a1bb8b7d5a9c17d60c635e0fb3dd2ef04826a642a04697292239e4f8e0002b1b3d681441033fd1b06b19710a6ed162599b180c90c8e9aaf643ee290ff	1	0	\\x000000010000000000800003e537a09a83bfe8e7068129531f406bc6669a171f3e6109469872a71a1b055c57b0def6ed4d58b604238ec017e505a238c66b7447f96b6a7f9b8753d7064e71d3884445ae8163c1717fd4e52bd1ef1a4ff6e627e7e1dab6cc7e703e2a527f570f19e52c6a9f5a7d3b1798d68de775f18052c7a754657c127cc2f92fe8c96e778f010001	\\xfe159b9aefa1d4e2c323181be4d0b932614830ca0ad565a986cfd42e5021ec4d39be1c2ef3ffe08d0790bb63e9a95add62d988e6568057608208d64e3aa09b0e	1669564506000000	1670169306000000	1733241306000000	1827849306000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
205	\\xf0e1e9b67fbe3956784d0ece42009c0b5bf11bb8fe005a35ad4d4b1d53c59d4a41f36f09c70d2dd423b35c3611599790221bd01ce95e54e2da4f928b98b6b0e9	1	0	\\x000000010000000000800003ba0a24c36ee89c814a906b616a0d7037a6fdfcb8d8ad6a5f405ec29400bc225e5a4e7ea9d662e9d40d0e9fb0a7a78ae9d791f52de370f3a34d09fd0bcd3d5d3d5a440e13da0fef8ad1b0ce26e1c5c9045607a16742fb67dfb3e6efb4c2ab3e76d878714ff23bcf172f1ccb2a8255ecfef386e5c1aa1504cbf0d36ed064eb08ef010001	\\x072dcf45ea287c88d53421e655db2e2f822bbe6784faf4bb4b16bd52746114080fc38e45f65e3f925ff06333ae79b05f767a122d1664c099655cc5b48eb2460a	1681050006000000	1681654806000000	1744726806000000	1839334806000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
206	\\xf5d9aa5c4d4ee352c8799e37543ba6d40647d0042265f0e95e700d181f4be8cbe8884ca1f93a51c8ca64b4cbaf62e0397cb83c85781854990b4eced2c809d462	1	0	\\x000000010000000000800003da5b482fc7beb36692bd086d7883968755c2704637d6301d1b0ef4efde2f1a3dd2aa24394a437b8f997f3e13cd8ac886a35c0d2a09af6a86b41cdfb6647fae80179eed4855e60af8d1b079ac668bfb6437eed40913182c776fdf158a401b097bcc3eed6fd9ea4d055decf09d4e3d070d45ba44e3f1949055603f1fcc68e84989010001	\\xcc998c1619b84ae1d446256d13712ec846873d02ba05fd65bc287aca1aa6aa40a242190c7aba906364bf77b99b64c8ecaf1a2a90d4fc55199520953b5b237505	1671378006000000	1671982806000000	1735054806000000	1829662806000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
207	\\xf5d1bca9cb759ec5ca386521d11ba32211508d2e6254b6e6ad3be5b2a248606564ed70b2c6a1a5accd59e7905fde11ec2eac96aae8007ced97e705cd8a5a4107	1	0	\\x000000010000000000800003bf723a302dca2a6099911eaf5843e5782050f52d0829f1d6ce872bcab3cc097a450baebf8906d5d707ae2bd411a20d8d68e61613dbfebeee853befed7e878d15281e209f62e598953e60bf262eb668023cee908e7791fa5aa51f9e5c7953068e50b382f1af11824bf9004548843329d64d41eaf2a333a7f8ab703a4001f03e69010001	\\x29c85a66c341e8f86d7e183e053963c937c69235f24305ed8935eb92684c7b53fc229acf2fd7c8b8bfe287ee580f84a0d8f81ae63af1eca51697a46edf853d02	1677423006000000	1678027806000000	1741099806000000	1835707806000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
208	\\xf93104438fd3ac536752e36ed5b8cd2f4a27efe9bfff440d413bc36d4654cc434fc1ec3a0ffcf9c2d3bfdcab7c34809c5f77e63ee80ea7b427a33056b22db679	1	0	\\x000000010000000000800003e9d2f231c94bd2e81f1257eeea76b9a92630f4956ca712ae800c2c8bfe0ee16dd2025976858658025de087781840ccf8ed2be96e3bc6b9c1a10eb76ea32a2d5b5139c5da4b96423bd4eae5246025d5ad36599b53b6db0442f1c9d3333fdabd548e656d1ee5aa59a6099481f4a435a45982978c3c53ea9366e0f3fa26a743cb15010001	\\xa96f36f22769370e4688e5c9470f5387623434c510e0bb861d4257db5354f8707d3dbc8799a7c69260461c1b3a1227a060888b1a532e99a9600fd5e875afdd0b	1661706006000000	1662310806000000	1725382806000000	1819990806000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
209	\\xfa1108c9fd794207fe60608950c1ff1f799ff43572f6e8eceb24ed23493eb52c07321ba4bc2a143fbc95e23bcf52ab78bbf5f267735d5207f916a0b8079f2322	1	0	\\x000000010000000000800003c47bca9e42dd068db297bdff224663d9257fee5d5af6df2edf2c0bbb07728ead2b397174d8697926b3de0b36636dce378f6be0e4c778698ba96cfffe63f9d91de41d96db4ab9e2fd9c27072725b07aa0f1d2b973a49ef66fb555146517ec8883ab9fa8d4f2cd6fd46f26a70d98c8297f28a88fc942bfd89bcc1151064e7eb2d3010001	\\x3343525e4f7c8fde8c09447d23a2cdd65b9324ececfc60cb25f38f7acc2a234c4c3f47e37a6a3868e0e85d881a8ff6405fef9989bc101e7cbf8b9100e36f050c	1679841006000000	1680445806000000	1743517806000000	1838125806000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
210	\\xfc893ea2d21234188f775036825ea847a6e1067ac510b8489bb7d421578fbf063a962c89c035bf2761f00e417c1c8a9416ff150334ef380a99ce459060fb20e1	1	0	\\x000000010000000000800003a8e4875804164121a03f26e3bf384fed983de85ce5fa6723630f7134d75e846299f24520ee45831dc459d3a8f79a8871fcba66ae7d8272fa5651880a7fc1b78ea4c24ff9cb886c2c03a0133d9255f0abf3832f69651cd1d2848aed1b35210da9f8516e8d82baf255698b774d8ddd95dee2fedd719ce21f39c72cb8f6797264c9010001	\\x96475cf32502fd1c1cc4f4ae32dce83d48d65b9f1c6c46719005a1af1498d858545b65b0b0e7136e804087247a3d51c089a61183bfc04edf6394d51efb4b5205	1661101506000000	1661706306000000	1724778306000000	1819386306000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
211	\\xfeb1974742c44885c2b82ad7d363a8b5edf2b38228ece108d0ee896b3c2b67e112dc8a5aa096c2d90637b2e2623f4eb461d6204b061f815daceb96ebc01221f4	1	0	\\x000000010000000000800003be0702330b1f21329636c78f27bd910fbaa9d37f22f3f718f4965bc41dc8688ee4f78be1ea4005f9d26e6609caf88ccff10fd6bf49648193dd5ba17b366a0b4c5c746f301ec1e22d32dd6dfe5fa2584ed03df31b208116f6008548ee5bac39a161e1b645b638d42718b552929e5d351071a884f4078eaa63785fe67472dcc16f010001	\\xb50e588e8f5b4c2bff135f1914cebfe28abcadbdfb70126a714f6454982d385a2ac88865217b2695659f5a198bd0bc554387eb12a0b30d7278627bf86157da05	1673191506000000	1673796306000000	1736868306000000	1831476306000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
212	\\xff49fd54bfabd805ec694abca72e5bb4ef105c965fd6934cd16c6fefaaa30a8bf73486b8cea5be1e9f6aa7c391eaad4cca531247baced4b137fb908dd969bb51	1	0	\\x000000010000000000800003bce4257dc1dedb778692879bf5ab2d3a3ed4b1badd824ea7fffe009b4375cdf332e7cb418ef8f8b1b663f17480d7dbd68ac0ef181100d8e8689f19b869eec1324e4cb0ef75deaac02632e1a786971dd903a449860021332728949624bbf641b432ce42fe34ddcc906caa4525b6cbe21d66c8de64f27416f430dae14a23c9833b010001	\\xd9c15368e6d09f8fe0d08b01933c7ab433e22841b389947617f3a7898fb52a654aaf6c76bbfb479dbb15e1fd8bfe487aec5855ae1c981861073213ec57f3e700	1672587006000000	1673191806000000	1736263806000000	1830871806000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
213	\\xffc94f8581f5fa9abb336a1759d1f517792ef13a2d374676bdffb3d633e433bdb720925875ea45b234bd39dddb20ab9216381091e2a10a1c9cd6a00dd2009af9	1	0	\\x000000010000000000800003d7d1b2b01f83225e337b3c9ccd0572e4578d42ad18eae8627aae2347dd21e3d1cf40b8e12d19eec27317458de76be984a3f0cf743c46031997f5d246b2fd9fc470b542b48d1e783f151196790837a706a7d199275e57696ecb0593d433be6522af196ae1e1de49835f5e2484a9c52e4f1cd74a799379b81e93ba6ba264b18cf7010001	\\xc7ea4c04a5506e3153c7ba73fdf45d270c98463c54d505d29c708ed45090af2eb4bc9988ffecf3ba3576c702bb536234c4e3a1010b919ba46be2601ca673700b	1667146506000000	1667751306000000	1730823306000000	1825431306000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
214	\\x039ab6cba567f97f5a885148fb524791578482861a85d47f664aadb7ab0aa41e1e302bf95bff7c6a5543b4f26b88e2b5bc3dfd25d72cb4e1af08083ebd9b29b1	1	0	\\x000000010000000000800003cef2f24e5d84cada9760a2a2874a0b2c51dd26ebea5996d3200b8eb2a48ccbede9527a7cf099d33f83edd8163fcccfec112df7751d4714d43817ccbffede2b81dcf0c8936025352bd9556ae1708914918da8e1e85751e43c00bd4e19f5498ba4c79cf2db3ca8f204935c8d0abae70d734f81ac1ca72226e1060a4a28e9089945010001	\\x6e3fa22bb4cabb63f96202593d306e9b323df2d08fe859d850069a420df6a8bad48ab9a8b94d7165fd683657c5bc488e228d2ccee4f0049dabdc30aee5a2650e	1651429506000000	1652034306000000	1715106306000000	1809714306000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
215	\\x07966f1c6766ba9b3f28b62a3b726ca61bcd56844ee2899dbc4c9e6b4421479e6c395c31b0990ebba8a32ba33c5c41af06fb1de8560b995388361f141710b97d	1	0	\\x000000010000000000800003d6cb7e8ffb3b88aebeb6245950e2aed9af3bf47ac5e637abb7f4c532fe4daeaea7c12c979e50e5a2b2aac86b99502391f83e3d24e1fa6dc1346931bfdbb5aa70b19c06ab0e6d9205f4e9ba91eaffb47134c25e5fee0f7a8161dc565c74a7bda0cf6ffb4d22fdfd05012a490273986c55480123fe9b08cf52f8bc07908a4264c1010001	\\x978241571ef16d02b2a3c42f7f8ef72b529f865119135acdab63e1356afe7ddc919887ee130e46bb8d91eb6d2347a5ae66e1c6e1696cffd0a2e4da21dea9410e	1659288006000000	1659892806000000	1722964806000000	1817572806000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
216	\\x07f6c63de2da15ca427b1964244b77efae87434a687bc30091cac411b7efbfb052286cb2d6230d502994fd5bb5fd41ec73712a09585a12a546c5d953d789abe1	1	0	\\x000000010000000000800003e0bb1dd7cba454c87886c09e455eda8fa7aff88f3c7f9140782f3e39a3593de7dd9537d119095eb6391d44413bc64bf546c3a2b83536162d3430b159edff3e038594af7a4525b621ebecc48978c166e7d6bbb7354c5aae8b8698eec4904f18c4623a50ac2f96c546bc6a9d8e667c6f3d71845612b83c7556ff3f45e497a35ee3010001	\\x3b91b0858bd68c00daf8c11ef081e19e6b711bd9fbf2c90af64aec7d27aa082df7a901535f1902dd592b557a76acf37bb866936147e50b997a052d164f698802	1652034006000000	1652638806000000	1715710806000000	1810318806000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
217	\\x0f76ceb263455978a41e69f4d4706cfb6e2f3f5390ccdf58f6a9592b495b4aa8376bb73fd4f228b49127002e9c69a5e63760a8ed87d815470c7c54ce69e31793	1	0	\\x000000010000000000800003d0bed4582aa0e8cc574856edf8465d1097ccc6b2fbb5b69edf8778ddb5bb789f9f2e03989d762bbbb59fe4e7916a16324627c43e8595b4e7d1ccdf17f0795c76261a6d357bb0e789e276f7ea4465071233750cb0fa09183721448802b32b26421b10268a8fededbd9b72b6756b68c0d33e9d22c15215975bc467eaf2f8fd6313010001	\\xe615f0e31afbb7bd238aee5e8b30bb0da6f73a4de5040c721d7cd0313e949ba27bbf6e688486d221f63394bf878093f0a4a41bcb593562b671a004581cdf5306	1670773506000000	1671378306000000	1734450306000000	1829058306000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
218	\\x11fa09150f7a65b5df5cc8986aa7db1a1579caea322e7e7b720888a56b6f236869550d16b3ab6b2d3b58a7507e2cd0919d2974a3a7459c15f93526f91db95a6c	1	0	\\x0000000100000000008000039c6c4d71d62516de45e1c630dd8ea752d517bf2d397981ef0f75a6bcda721f282e17264526800be2770d3b2702fafcce6c2d0911272153d435e4fff17588e4e5b906794b40f50cb45546cee273707020a3e006a123a6fafb293633e7d9b0d71960652bdc4f7964e7552e7ff70454fe2a067d44dbbd5953a9e9a9641a895bf1bd010001	\\xebe1dc049c7488102d9883e80b5bae9a0476cf469a2ba440fcb980f834366d5f58b4cef05574ec5f3f7298ad739a80bc7595d2f71c0c3741092b150c38daec0c	1669564506000000	1670169306000000	1733241306000000	1827849306000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
219	\\x173af7640a7de797a3dcc746e11ddd577245046a1b001e8ffd23f8f4440cd83793cfd4370e23a7e454829140a2fbaffa49a7d6e77fc35a16150c2e32a4d4887c	1	0	\\x0000000100000000008000039b1c452dc51b5c91d89178c5994535876c99fb07c7feb2eaaa43103ed3504a898587bdf89ce07bb842edf060be0685141d0d51df93b4ebe090fc16f67af332bd4103413c1a6f373d98cb0dc2eb8d2d29457a8c324179f7a5f85657abebc11541f64fc208a64a5b5d600f19c37636b89514240711de331cfd8a4199e61a56e6b7010001	\\x6530e497f1ae3642ed51b96bca3de42c907ed2675681de9eb45253bde6484ba22748f903afb398a931d61d14be5f5140e2426404fff68cbe3c0b221481e30402	1656265506000000	1656870306000000	1719942306000000	1814550306000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
220	\\x197a12f1963575dbdc2773a2c37f59a0a7bce2a5df448137b55dde60f1c31314ab425277a428b5892ec8130fee02295fc54749d844df990b48745ae43787ac49	1	0	\\x00000001000000000080000397e2e7c6454238035ef3dbd6645fc877573a538499f3016a3a465303caeb18dbd7c75d9a63f904c7de3dae10aa195b933dcd401f2c2c33bab2ed3fd4452c191e4e4f571eb21ae4bda6b89fc679df7bf09f00c7525f121de177b3be248a279d45089f25a85cb3327bdbcecdf130e12a6803757e363563f54a46c302b7b2e5dad7010001	\\x3ce039f26366a1c23e9b94db6ef0bed58d1f2ac094d553ed6880221e894e41ac4db0e5811105e395e178c8545a37d465ee3a741f49a649407aadc217dee8d700	1650825006000000	1651429806000000	1714501806000000	1809109806000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
221	\\x1cbe055f7cc50e61d5ab6c58798475569080842267023fa62aaa0f4e304fda8642b9e59d8f3f0376e5aeafc6a0cb7ab0a28945546f65f63c1912c097b8230c6f	1	0	\\x000000010000000000800003adb4e99cd723644532d2c9f3764882f0a1b97a522b32255cf5308e6b37439e1416487748ad4a354c8d4483b6dd7ed130dc390fcf32a4955cb115695f990ea3c17c1242ad98d12a93e634810a213eb4f00c77826122408a917f8a21b910afdf00822c1859afd6589e1d614d7def211ffa5a532281c0bed3d435d129e924f500bb010001	\\xa022fe337fb72a48d6e1b59075ee3288e1d096687b582f7b41c23a0ededc8a52a735acc30623d51674b37b10083a6f37e067dc7bbff611c023b3952f44d74e00	1653847506000000	1654452306000000	1717524306000000	1812132306000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
222	\\x1efadd03fe1f49e2281d4b69635f851a375e2c3e9492fd482c37fe8c21d1e1b4fa6305c530b6acc0ce7d4c4b4b2c498f02b08dfa25991e9fce9435112fbefcd1	1	0	\\x000000010000000000800003b0ff5da6b265c15638fd56e2abdec98682a752622ce6bf601e30eec08ef42f0b1dd50f8924104e685a01c0f9cfb765739560f05e6f7c5f4f244fc048589ed14fb989f260ff4b62dd97e45c71a757e6ea88dd5fd48530487651d20ba5508057d22306728d648ec676cdb9a8d44312cb2e94663fdb47fd5f1a131d6f2ada828d47010001	\\x0904de4a1d1c554742e0e64dabcd6444a8345a455039d796521d3373a22b34d6a1e45c1f126b1181602c878565e99806efecf7ffcfce1f0d137a58c784a48401	1653243006000000	1653847806000000	1716919806000000	1811527806000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
223	\\x20fa2ab389dff0bcd504dc90bd04f966abd6612f75be29185e8ec62e11cbbdc03c1788700e5b2512ace0022769fddc433774896430b2cb353e21de1b1855bcf3	1	0	\\x000000010000000000800003a4923988dbe7ff026c614397388586e0bf44808f15271f4761490f089f5b5e27f3f539ad15fc8b97a3d21d2990ec768ba6666c7a8e2234f4d071a3ff22e74ced08dda67f5037d918a5ec78946e4a579b6b2b4aabeba5802035bb824b49d6b793bd4280c12802e803c07520a5562db1d832f0d34c3fcfd991443a3eb0dcd3f161010001	\\x531f87e5ffe1f04a033ad38eb589a20d568d6b23d8cc91833a9f6315bf2699c11c177e52b5cd7c91809408dc8943eb27706ca0e318bc16386166f068844e250a	1680445506000000	1681050306000000	1744122306000000	1838730306000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
224	\\x23b67f16e2a5add3f2776b129f4e7ed301fc8a437316208f7850f27a379b2326f5c5246ceb9cca4fb8b5df0d3b50a7145321fb8635404677e71760c40c1b0199	1	0	\\x000000010000000000800003a416f4db6f593f5cab9ec5c2ebb6cb0807b760d1f6bb07a21a38f2e21bae9909a64522917987a5b075e07558ff12a1de32e3d960400074ca8d600d9b7c874665d969639b88c757cd57e209de6dacd2e6579e71bbb769904f413dea13d7eb4195ee8bffa059cbd65675458b1fa75cdd61f4f2ebef9014d1d9e1d5f06d3a96750b010001	\\xfea65894921728033164ad2a53180bbaf4a41e69a261ca7bf752db5d360ff60a559b410fb743e68850fb812b1bbc902cf7e92e2978b1126673fa810da859c70e	1656265506000000	1656870306000000	1719942306000000	1814550306000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
225	\\x25ee4c2436403bc1398d995b93af6e761b0783abca6002ae77cfee8341e707b284d65e49765413c914c21d1c7130f4a60f1265814f421227058e1f19861e9c97	1	0	\\x000000010000000000800003e32064ba1c51ced0e3264fda8a7740f17f7ed793d1edb5859b7bc90c9d2f9798a0295d7a47664536cd110ae3c73bd3d259593bb58923f73a06ceabb331434cfc45dab03359ed13f937d0ea3149661aacb43141edcc3b1af6e856f620bf23c102a90087ca2d56599346f43a886f814e2ab72b76b27cdedbfb4669bc8e66f55587010001	\\xb0ca5579c761ac528f95e2346de9542c1347968793d057cc4f2ea977986b95fa08ca7001495de8f5929a6f66e0af65dae49ae86a3ebdf51ab5c125e5c2361105	1666542006000000	1667146806000000	1730218806000000	1824826806000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
226	\\x25d6cc5eb5fe75901137ab07e5314e6f7a900837495fc4d496b5e48e09a51229b0a1995034e399b3db86a5c727a7ff6c4ad31d81cbd60375f813779e7fce8eb7	1	0	\\x000000010000000000800003e5225f0283271897308fa7dde2f0873e254697bad0d6ac23eeba9a267139f9037b03eb1176654f8f16d396089b0c4db2ca780953d7809da41b4c461821235f6b405c11f62df3b96a3c74adc43dc327d25c6668c1d696b3315cac82fe2d358a1a4bd2b4fd45e69849e414bbde5ae0ae8a0c0611993b838a289695c7510c18fcc5010001	\\x6e31350c4e600703775461441f1df1683886ebaab1354c1296610451f4caf341ba3fb27273e6e1006be770f74e9e5ae1f549f771b99127d690a7f94d625d8301	1659892506000000	1660497306000000	1723569306000000	1818177306000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
227	\\x25c263fc975f4b1c633b802534723a9df05fbd7190a3c5d46cd493136b532f03fefba8f170f4f84f62668a8d97d760601ef14fb505e9279c88d1c68c38631a44	1	0	\\x000000010000000000800003b4412c781bd0f0af4a2f346985d1e639c1a6caa3eef082e69b8cb5241b6349ff8ce980a1c93a7c116ff18d0083e3dee2ce4507e92fe396c04c57d3068e8acc9fd5254b5a9b8030f3545225f5e59fb18bd2208c279782995fbb46aa893294fc16c5c021a0f52ff567ea5df414017de33e7fa2b8ac0ffe8f526bdf2e888e9a958b010001	\\xedbba246fb82c8c359be07bb094cde963df2935f7004b5f7ef500900c2a888f2a0fc4169e47686e8c17a66f8fa14a58fcb134ecffa5a8280152ea6798785580a	1662310506000000	1662915306000000	1725987306000000	1820595306000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
228	\\x290ec6d48655958c68b82a041031ed1cd12efa7dff8206356ff9652152f0b49ea5d0c9d7b6e418cfd6e0e7735c29afd4662b8bab21be41fec1884dd242cf9fff	1	0	\\x000000010000000000800003d3727466603928a60825a7cb80fcbf8770b930913feb5ed3616e8b8397e67d14373cd2eeeaed319e4eb80780400df61884dad1bf8e22809fce1ed1a8f1e44170643c9599242474c0ebc2cc89ea1d26d1929686befd31a7e21d221972c0d41a2bf53f04730fa791bb30f49d1ecb421107b49975cb201185b6e15c690f8c72a3c5010001	\\xeee36ad7a848b644a87b9137bd610cc1f6cabe6fda68b40232d0cc849ac16c0655017be7d015cd9aa0f0c06a59eae7768af40ce5265f8a7c432d5c6d4ad2a603	1653847506000000	1654452306000000	1717524306000000	1812132306000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
229	\\x296a2f7d6b1a092cff0c1d1269995999452a87dbf9a0ac1a536ba1a7f487a75ed06124e809e82c09de8d8fc76056e53b8f08bacb478599770ab6c26d2759fd33	1	0	\\x000000010000000000800003aa06c6f62ee9df546c1f39544e345390b5b8e6564101843caedc5bb101ba5e3a8cb5f7d880d804c9fdcda60a57a2d8ac5878e7f2f0929e4ec7952b5a6a176d032dc3cb264f676a15bf66d5430ee168878b8f681f2aa7c0b6eb92fa27887c27a941af06e368cc2c55a4e2d477a1d3ae148f5363c1113ac975212d5bffa5fbce77010001	\\x67d8d7c1bcac33eb9c96e6bc5e33d7db1fc5547d8b911c69d37789cd82f113ce0a289e31b28d592c723966d169684a3c6c3b00439e84128e94e41340e1ad0204	1681050006000000	1681654806000000	1744726806000000	1839334806000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
230	\\x33da11854722c6009cc592df33d46212a7da8750842b81946aa3e65f37584aef8b2a717641ef478d2b101a3501bc4adb135375abc52c34b55334dab2d7474a12	1	0	\\x000000010000000000800003cefc01158bfcf5bcaceab4a22547e681a5630c21d50a08bda398e8cfd9957a4ddb75a23172299288f271a1e0f4bb706b1e7b255eef1733ad26d125de30bc92e715ae42c165a49db2d967577b9fcdb5bc6b819348d23d64806ff1f7e7c928c228d30652968ef3b493f06bf9fc13505538308ae3fa3156c973c9fadd881e831c17010001	\\x7de350fb344edbfcf899cb3f299cfb6bc783be37ad778fbd8fff672fbcc7acf98d78a775748eaeb158007bb2eb71c0460d61d202999cb122a9a5feba7dac0409	1659288006000000	1659892806000000	1722964806000000	1817572806000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
231	\\x367e1b00e8541b478b54a1cb714a1bea075a7025e97e0a41705428797bc337bcfd9eaa607000a3bd3506e9231d1593a1a7fcdfb6b17e45da43ee97efec996997	1	0	\\x000000010000000000800003abf7e3d4e80a35ee02e219a9ea72406b529221591c992be8dea70988cbbf4b9afbb048eb4f2bf694a4293064dad3198f92bb5bddaf8410d213a28bc5f43647e8245c183932fc15221acf0fa8bf86a58b4307b92120fbf567418e5cc4561dddafe1af1996d5faf5499af1314523d6b92f978333bff5f412b9365c10e82cbffed1010001	\\x596c887fee724ed2dd92ec9ef7f293fa4465af3d539fbad327f9f9f2113c38fe2d478228d409ea7bdc08340ee24cfacbd85c397b2ae553dfab17cc3334d21704	1668960006000000	1669564806000000	1732636806000000	1827244806000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
232	\\x382e4e6765cd68bf7900e970d81232b3870b6a8b604ed16892cefc9ca3e4706eea5c334aa0a7df5f4ddabb6cadc5cc0ce04340d86b83f6290a38fc163f833e00	1	0	\\x000000010000000000800003dcd29d342036346de7dbae758f920427c5b48c54c22328e92d9f4a2c3670dd75998624adb94399d676e6b782994bcc4843b514baaa1f3c14255041ce8b805be8e197a20738e97fc09616814f5ef58fd99cd35425852af5ff2b6dae732436b7b961600173db5e87b849c20a04b576c5bdf3fda9e77566c667cf0d63af35dc27bd010001	\\xb0d9c0812455ccdc5c42cc8df8df6b43fd733d1659f2d9b6c395717a15401238541dda58e8c3da1fe212ed25e8dc1ae2ee6c15d6c8c862ea13b38327ce0dab0d	1664728506000000	1665333306000000	1728405306000000	1823013306000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
233	\\x3a4a7101eeecba9dc0708c799ac00c173710f78196cd268e4da9331935906c73970ae8bb13dd6d52c75c71a1df629a7f53e541edfb8daa55e2d5ad7a6263c210	1	0	\\x000000010000000000800003efad1466ca853a3dea97767580f9dc22b5469bd25bfac5434e37c480f21c11abde412007c1c51d2e05e990cacc38d40eda0de5534833a304e208755c12691882d3853551cf593a7eb73d02248a41478d9057aecc1955c1f2282f5b22bf4f3ce17d291505aadc986e47a7831fd3c65e504a77bbe8dd0000bffacf011ebd07d353010001	\\x47dc6ca316948d7bde62e948ea7ac4262e07b8b1576c5d3900634a7a1767f89c38cd24ed3592c7ceabac7b5ea59b13088f03e72f549f3278a348951e10d4230c	1658079006000000	1658683806000000	1721755806000000	1816363806000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
234	\\x3bcadce6061d927a9279958ba86bc87b63e102cca89f68e0986cf6eda1b4b0799923fb560cd9e171fcb974e185f8116f49f7aeed63e539cc0bb4b57f3db3fb18	1	0	\\x000000010000000000800003bfc57be1f3f788bf3eea0dcf003e7653b9ba46c7ea2fc8904c61aa3eb126bed0596e0a559f947d49f7459dbaf658117e87e5f67821cf603d5a552c62c940505b0efd46dabe206ea8ddaa10362dd8ba86c3990674d974c518a22f2949ea11933c80f520feff385b01ec83ff618c04f720e6042a892fd9c654f53b0cb6d01127ef010001	\\xbc38fc91e5f5b4a2c842c4845c3adf57aff42389a96080094f669008f47881b4ec56e06ff55aab899db9f14915cc6c640c21628286af1017c2bbe53177c1340a	1680445506000000	1681050306000000	1744122306000000	1838730306000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
235	\\x3c4ed449fef274b70e3593d05bed09cc3592c62b87a0a718824c0422f5ffeb4cadf042228a4924098bce2333a44a6ece0e35033745aaab015ecc18d9a1cbdfe6	1	0	\\x000000010000000000800003e8f518862d721730d5f9b2b1775e4b7d3c46be74a39511bc752ba2ebc660dd9b3f81a9f0200de6d39a978883709e3cc51c9aa68202f4a7d93c387ba35dd69f0c11a3f5ec31a76fcc0619474dbc32b406d5b27d9f832b15a4886153d6876608dbf0c7dcf141dab79f7056fd70d8d31ec7c558996189837f23ac943f18f5a4d46b010001	\\x3e470a9437fed77472f9658619e0a87427c306e7e4f2faa07943d1c7546f80fdcc1f3e016bd8e628679efd8d93fac2ab323e167609cc37776079b81a14d7be06	1663519506000000	1664124306000000	1727196306000000	1821804306000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
236	\\x3d1e21ba1cc90c20051c0f0e49a24b3e3d5bc7c7951059fb9ef845532374ce68949d15d0e99f2f3075f9180753357939ee75ba9c5b35a55ec6b333924ac25fca	1	0	\\x000000010000000000800003cba94bb424bd4864b0403489fd36363da6b9d4bf33acae6b8750769e1888d16afe45105dd10e0a096f3e5278f95ef55dd538c8858efe4411647ecfc712b93572c64f40ac40d5f7aa3cd0fd586d357776ae1af28efc80aff2e4c82f52722e84b6626598f4225205bd6a8cc49472ba3e3ba3cbc6d73a4c29d57555967f1a4684a5010001	\\x2a9487cfc9d233b8cd2d02bfd40d5e6b70304523af0184a78c10f5d954d7bc6709296854543953a77172f4ac21614b653bf34134401c3fdcf32c622b8c6b1b0e	1650825006000000	1651429806000000	1714501806000000	1809109806000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
237	\\x46be39ed64323450b1a349b3e1a0bfbeef0d2bb3ee6fe41a64c4f40f56926823fa754bec08b7ea0293bddc39f4b09f38940b9b37a5f490ae4987bcab537f180b	1	0	\\x000000010000000000800003bcf0ca1793c64412aca9088385f6c5f0e68c03da5d38c6e3edf1ddd84b114540b05962c5c927d48c57f2b16e0ddc62259566c040e384ec83f105c41f23957cd66970c81642a2422ab3a263e42010781fbcbb597c0590287dcf50c8903eba88aad0ed78d1bbc7d3efa72d8dfbdaaf12b38a5666da900a4c526fa2446449f98b79010001	\\xbea5c1c52ea42338563d0fb3b58076eb4ff1d95efe310df20ba1b0df9d74c2903a89a416728f923f7a7265b8b34d9e9fc5adf44bdedbf8b249a52d4e7743d40c	1678632006000000	1679236806000000	1742308806000000	1836916806000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
238	\\x478a0c14a615d8c20ac4760e50c1dc83a4ae882653d0ec7ce0f085a181f68daeca1d10ce33cc9433d74c191039b2034bc0754fe6ad182b4d1fe4e91381c0e1b2	1	0	\\x000000010000000000800003bd485f0833250ea03d51c72d382bf8319bbcee13fe13ff3a61bf295572609a9b67aee8730d25274bda5fc8954ca9d405cae2d665d5ca334b111fa4600653df6265a25f171571ce372939258ce5a87d66cacaa6ee15f2b1bd1c32e3d6bd3f2b08fd023e1ec71f7f6c9bb01d5349dde64d0b078e047777afd7214322e5cbed1039010001	\\x5ab3e7441efbd6c0812edddb4998a1a061e797998acde3e9a3183b2952f2945b13467fb99b73714c58d140506fa8fd27a8e2e8a76badce55ac7af684cfac9a0e	1673796006000000	1674400806000000	1737472806000000	1832080806000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
239	\\x48a25a1661e8c8cb45ef606f344e3be88c7009fdf2e7efd3ec55f127d8ae56a9e3bf4080ca8e4a19813f1d7561128d6d838db7f0302ca33c7f131d5393f7e145	1	0	\\x000000010000000000800003dbefc7dbb4421243870c11592fa878e8459a0ebf4e6b7328b0b51a7156a79e77d57e70a4d0a4b5b22c25dd4ed67320976cd935571ae281f489e3f6c5ca2e2d8e71ae2c9828e6a63fadebd89dd665f4a3bc13ea0b8ee7b249ba606059c56a9986f5fdf3020cbe0224df84b0bfa5f88a6f46cc5f24bb22c1c9229eb064e1112ac7010001	\\xf09c68283fa3c3c4590e623b3875def24deee2ab8099fd7466faadebb4fe771882902667eb8852c69f43c5732f83ec50520ea3c06c5c1078f8e77c1142c14f05	1681050006000000	1681654806000000	1744726806000000	1839334806000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
240	\\x4b326282663748b5d655b3231af90bbb0a9d7c16b63f6f1f33b760aefa70f269961b7f292d4ddf997b244a81b93c71f74e25ea21df3ce7b79c4ee2d6faf59cb4	1	0	\\x000000010000000000800003d82ba386583369fc39da2d117afc0bd2b691fa4055f0adbf1ad57015f25d5c734c94b4699c566aa410447a3b2fe185cbf970fa103a86f331decfd53ae077c24865157bf65eedd538c0fef5bfba39a2e56515cb627d19dc567791251d12a368b2478be00681cc987ab9a5a62b3ee76cfe1a6296a2dfa7f2b39cc4161ff1027c8d010001	\\x7551c4f2901fc6c85c9b3f448e56d77edb212d03f7b12401ceb303035c9a675ad5d76e496452318a714b2232770e9b0c93f7a47c40121fc929911af3c4753f09	1662915006000000	1663519806000000	1726591806000000	1821199806000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
241	\\x4c1295dccd3594f7758fb4b55015149c288b9a3a3b8c69d9012b7c0a82df7a98d565d0b4dcfc175fdf23ac1f180da6dd4bc9005c77af4ac732767a9011ffa63b	1	0	\\x000000010000000000800003c9b422bba6a875cfaffc4cfc8e28c71693145fab7773282aa21629503faf97a3d0c5b739a15ff3adcf90b5176cd826fee0a3ed333a46cf31254de67a3f8394d2b0bafc27c02e35cb8f6d66c2be23feca3fa32e61abca357c9d4b401ea1a7954d0f8ccb188a5ce92132793f133caee3de96c57707593a2f6d3248e7913a23e645010001	\\xd78ec82f01d4ddde01c6c4e9572253e3a9380d93a9c1ed3ce1ffced366fb064466c1d937e6ecaba5b4bd4b58ebfe27e417541d519e19b3acdafe15f23ee58f05	1651429506000000	1652034306000000	1715106306000000	1809714306000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
242	\\x4d0e29e84d5c485c43c9829c3a0ebd69bb28bdbb858b165953e790f2d85e817d9d6d6a1c17d30de6c802514271571ef6b1a88e0a97708b518c9b39232c9b8c44	1	0	\\x000000010000000000800003dfd7ab1ab54defff05e462e8f5702424b8da6f169829511d66902beac2634e7e8112279d48a14936212f952c08d88b234c61c651cad747ebdbf230556a676a3f5c9db16cd30030a4cf0b2f9798564f64bd3a7d6fac885076c1c9102c6a6f5dfcecbbe87b3dce4c4a0d09fed6873faa08141871bdfa50a1b7c4b95fcf6413de13010001	\\xa7641b4a9944284c15a56cb7a3f2fca22562a95343523cd17d945e404f3482bd88dae513d539fb3554fb1ae57c9a1560534b1bdfe11bfcc665e982669696e509	1670773506000000	1671378306000000	1734450306000000	1829058306000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
243	\\x4ea65a86a2871b05ac6b1e58fd7382f59cb62ad3e2f070d1c7029397491972e68d338edffa2d5f1aad9cb8c5cfd43176ba6ea7c302d03a4bb4798f10c416f819	1	0	\\x000000010000000000800003c277f6fb0f1c525b868751f4a56b6491f78d7db64a754b4f7962c8dd16d85a9d8c70d334d37b0a1ab220360c85b08b0a9ea2d4e20b8d7916d472a80ee5eaf22e30a02724f9d9aeb1d340aed4b7f835b83f82448b8dc374c460d25e956529aa4bf218236e617a50e69d28578e01c7a8074a4270027c8fe4404bdcc3ea1d8039c9010001	\\xd585625e5c8b4c809499fb8db406d20cbde4c40b87e69750ca7a5b2bf2174a69d04815066ba3ef8c7f23c35de01aaf6132768c9117d6ed8f6d314a16294b5308	1661101506000000	1661706306000000	1724778306000000	1819386306000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
244	\\x513e8ab3640dab776535b868126ff9693b08e694467f660e760479f80b462450a8851c01c2375ede4b93b6a0def8f9765eba94403bc32bc3a841648a0537f088	1	0	\\x000000010000000000800003f5240fb896af9c0ed4b811f15118b2fcf1e56ca7cebb8cd2d76c5ca22f2c8986c170ff2c702cce1f0950c921bf77d9c76c8e8e78d08ec6a0d7934dae364419c44b43d85da029694fb23ffb478671c4370fc1fb857c500f1c4ef6f69894aed01e1f2f0e07bb6ed7ef4931b446acf56a852b20101e1281b0bba4d6f0e62a2dac5b010001	\\xd1593e577a9728853052ac7fd8dcd079924d7a61d38bffd9d22b9e6b89ff35f0984f106046ed541c86c1d835fe785e516040419036633dd767c46b3d30eb2103	1678027506000000	1678632306000000	1741704306000000	1836312306000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
245	\\x52ca706032dc59e30b22b1971495b83f8ed4a165e242e0e8e80451d03328ff24d2f79fb164202da24876ed444171df05ec83519e30d5de0fd9f6d709469ebf55	1	0	\\x000000010000000000800003f4daabfc5abfff2164e51f8b9773c9ac5f93c26a62e806843287fa1d9dd2d7b01eda971c428f62ea5cd7d529442a56892c96430786a0b2b6727b4b11e4649224314dc429a4f524526ccdf34d612744bf2fe8d44b421934fd6d82c57268b277992a905e8c3c59ccf3b0150b4403315c472c73ff09852bec0d882c0c2ede2508dd010001	\\xb7a59684978656d21f63ef48796fac0b4ccacf7211cfc6cc92f30a544851b6e4f4978e922437527632239c2fb8cdb5dc6404311b994cf56392bfdd1feb820100	1678027506000000	1678632306000000	1741704306000000	1836312306000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
246	\\x58de13d9b0c4e1754441c372acf2c2c2fc29aed1e91a1a96b2b645b97b16dea18add5dcef26cc4bda4f20fc3c2466cc1a46c71dbf92be2f41a1bca4ff08ee80e	1	0	\\x000000010000000000800003c5a19136e260140a3830a2716d2a1841b255a221c95fcdd5b939a44af2b81ff57ab7163c8cff95b410c37320a980ed93275ef8d4d2a35356fa02e24de58acca08186a661b7f741e70c33ecb0a7d687fe8a07853909a83f46e786dbad28f4a8e3875b68d7653728d195ac29efaf662d5526e5b9510832153801af54e5c7e1f7ab010001	\\x9d7f7ff11c401b3323502b85d0176b9fbb5603b8be23e195ffcd6a61535914eceddac3a127155caf67ef3bce848e0de4ada1bfcb37975702cb591cf5aa62eb0b	1679236506000000	1679841306000000	1742913306000000	1837521306000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
247	\\x59ae95da1ad69b6db883c2e9081b1ea0dac238e09feddd2dfad3929f6f12350e493b25d7cd0d6fceb50b2a58238b274980e19d4bde551230d399ce5f9a58df7d	1	0	\\x000000010000000000800003b5b1bdc6063b00a2ad951ed7e72897f33d59207a70c045c1293c3b7c5040518c0e261af37d9e186f549fa3e8d8d11d850bdf673ae62f6488fa1d8f44c2cd584e6eb10f583f6c002e66cdeeb43cdfa0e51a520bfa9170e4fb62fca8a468c1e3fff96df17a3193bf4bfde5ab5617938cb3ecfa5cb85f05504e648c10bff1e53543010001	\\xb14557c36c0043be8712d1d5380522d269e9f878a0a6d68f930605c8e50486c7c3c9be5d482086e664df821f32076a4edc38167586bfe5075dcba0adf9da9e0e	1675005006000000	1675609806000000	1738681806000000	1833289806000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
248	\\x59c6d08fe3b2dbae1d12b8cd045b29590b34ac7f47417e06b45c6481b8bdbef697bdcc976b538c91b2c2b54e55cfd7bb966a07c9ae0bb3ba599335edf5f70fc7	1	0	\\x000000010000000000800003ab1529bbdebff43963b6d4f211adc4c9ca0bf8241dea9504c7c49de41579110ce6002c99b3cd5ea06fbeba0c2f49dc2f20e8f469277d205f23874feb6e3763939ce841175f602b766ce08b1b734871041a1e4b05f455d816880a9febdb3a1ccd998f16a779f3d0d14aeb11bfe71da201e67d9d3a3d0e4cd092a465be8c32d49b010001	\\x67b701068d408d6749d1dbc5f981a3d676899f2f331763b58613da70daac6e35bc99f369f18ad14361e23cd5859d4e108236859a42ae756d74d13b36fcf26c07	1658683506000000	1659288306000000	1722360306000000	1816968306000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
249	\\x5bfa8d37ee1b3796b7b64fba20fd315b997b911c0f5f4aa0131cb99b646670d950ce28ee5b3daaff5252b66a8c850d265bd678ff8922e49bdbdee61831beebd3	1	0	\\x000000010000000000800003f93c402ac64fe98a5f69f4c1ef961cf82deeec69da932a619effb25854cdeaf83df9d838a299a880fbfde7b3e1082aebd9e9abdfe1ead74c831e3168e118bd4115b03a0354885fa8a4e5afb95cf2c24bc4130d76ec82cb402e90fcc033a008a082d6b3f1e22e902b3c4cb33d981e68711cc0d98a564999a1de900054d9fef1c7010001	\\xb492042e4649bce33d679d9e5f74f9c3aa8c14cbf1df69c1dbde2d437a3ee94aa4055cc494926ce4c133405283c4826d2d0840fe670df633f6b5cc41b3f8bc0a	1658079006000000	1658683806000000	1721755806000000	1816363806000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
250	\\x63628e5fc793573dcdcc16741c099b4c85021459af4ca3126d36940cde4028766c96ce40a1ac952ae895d24994c36b014b996b4af2de337b15532b078bff3b4c	1	0	\\x000000010000000000800003c65202763f3bce513e61e04da50d4e572c8a12cc3e02bb16f75518ee8cb630befe1b9dd4f3b9ed4bbf793c39a701cad264b314d0a26483a0914207aa10c2720072bdfb48340f4fbf9069bc243ab89cf95db3b39bf0bdf9fa9fc671a78f32daaaf1d14f8a46eb681a9fb0cc426c246dfe3b7b2730c94b11fff36c456bc528ee77010001	\\x803aff7a395322434a89a9a03fe009bd4a85a398a79e84b813554499b763be537f15fbe90cfa0c5659f94ca394fcaa5d4541415fb7bc8564a313b478c60d6603	1671982506000000	1672587306000000	1735659306000000	1830267306000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
251	\\x673effa25cce4861d8c4f6d752ee07a71f700792ab3ec5cea5794b8bf393b6b7cd1b89fb24fe5c8fd810addbe39dd3bf0e5ae7123ea3ccc66cd57f9c35ac91e3	1	0	\\x000000010000000000800003bffd7a062d98a2136c2ba2fde85986bb19da3a30a789b22d5335818ecd15b71f48de161e1a119c273c5492c33b0d9587516f7a1ab2e0549f9a49266f7c4f094384c6b8f4e1795704188f04d825625cc155824e7e75d936ecaf024d4c60183d5f3e0b03cee1814dddd9d1fb3e078590ec45fa8d495c359ea952bd8cd8ed66632b010001	\\x4cbece209b0c9522b7ba2be80a355939f3e371660171771d69b150d33c585708c2e2bf1526e2ad60085f1788309f8b100b90f28afdfb96a0eb1284f42ccb8501	1673796006000000	1674400806000000	1737472806000000	1832080806000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
252	\\x675e04852406ab747fe073d0ff62c68856d5106f597ccd23a64a4015db1a2389f0afd40ff3f6085e1222a9980554c062ab9effecdd9fc563d831421547f79def	1	0	\\x000000010000000000800003df994b8958c851dde40f2cb269e3132936435093bb1ce67141fa9090c4c5528b5208c7b61d1b5ad75db8f265827bc3e6de90c4465974539becbd15cf882b3202024494711ccf96d0b02ca07267f21f2bac34bcb972eb608f6315f43826d1959a1784e77303d40eedb6d3d274fb6f2bee0a5ad1c3dcb181882a5ef67723c7b7f9010001	\\xd7f3da91b3bc547740cee761701cd7d45d7106a403557304b6db33b33a2e0a20725d149ffdb7607760fcca1e9979ced76a7b8ca585e573b9ebeb5cb9ed69980b	1675609506000000	1676214306000000	1739286306000000	1833894306000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
253	\\x687e98034c07ca73ac2c016043df26a96368a854de7c7c6958175f9be7a7c765bc83fa5b6aaf24c7d0c48258975ec073d47f41525d9e8d8a7d23a47b49b40bad	1	0	\\x000000010000000000800003abc944d8b030d3cfbf6da3602188eac9e921e9b023380a862c485019e9f4b23547ca5e47ddc72aab50d89e0ae415f170efe75c7143cc98d7700bb90749717581f0d4631ffb9ba0d06889501d089f1bbea00303ed91638ec3502fbb29ba55a75e078938936248ca0bcb0badb0cecd17afd70a80cd65e1d995217778d22069f021010001	\\xd9750fb64c0187aa5d1e0c29b7c098eda2cc0a69e14d23aee1a5a76125f1e91199098d9146f779071d73cdee37bc7e5498a42e58640fe55ab3cd897e1a55d60f	1674400506000000	1675005306000000	1738077306000000	1832685306000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
254	\\x6856c36db842814821fcccc7ff3677924ad6155ea36da133c89cc821d86f326c6c4cae040b5cb50735b002a726dcb6f2c50677fef4bd778d1180d00b6579107c	1	0	\\x000000010000000000800003cbe052a47470284e52b87c7356dc855664eaa8713ed224d21258f6c23264d72cf781fb8f7ae7e9be51572e0fc1f8f81e9845ee6da4443b6bef8dde3e4977fd798d8ac3deb94ddaa77f5adc03e53fd0162dbcbe4920c4b762dcfdd065ab2c823e0434bfd567ea1cc6745c941bd0f29430a553b210bba183d9931ee213c421f68d010001	\\x186dfedeb5f9ef73dad1db3fc32442fd8195fc663e25980536fb23535fbe780f9744f8e45dc3bc4cd2817dc606ee35cb672abcd343264b83d9cff622ef00bd06	1676214006000000	1676818806000000	1739890806000000	1834498806000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
255	\\x699a07d25370eb781a777f64f735051a70a85dbafffa2a768467d6575f6a463b0999208e353d9417932e59853169e87828d694ded6529153d249d2a051f3cec3	1	0	\\x000000010000000000800003d0ea9774e4a55e3ed719ae14c4c78824b0149da92166b46c6fe65616592c9f9394aac2d46b9abcdf0cf95aadbec9b7117000623b12a380da0845b351dc84e315ce5d45a41c3f912ca4e645cbebccedbcf9b1096ce73f52652f202df050de878cb5c90e2d9f606a0c5c8f66c988a1676343c723141bb5a7950bcd0f77d9f42a01010001	\\x490673ccbd7b06cc7c1791dcb158919ec46928e16e10d4a7116527897d21cb90522df50429c29dc3a08fa893d14ce9d31438c98d5fbe620a5e4a81f36b97b00f	1675609506000000	1676214306000000	1739286306000000	1833894306000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
256	\\x6ad279de88e4aa8357cd0ede5ff2723f1dc5a8ddb1097087e34ea9a8a786ad86a9780807840a0f4c391c0692e386c1b905bcf4eeeb6acb63a0d2c50ad4e4def8	1	0	\\x000000010000000000800003df62b16ebb33186650e4a6cb0c4fb69b8f298d4acd7f9e8bdd81e6979e02a84e4435b26efa15db1a152e6b249d5a72281b4bc826eac564350836cd8697d26fa767534773b9817831537969f38714c3d8fd6a4f747840a7c6a83791c5c87d18d75bb04c63e6f4e1f0d9a0b4a13dd2baba934a1f6f0c0c38c7adb8cd8242d2bc87010001	\\x771fd046efe3bfad8f388a92a9cd9a3e26c32ea2e1aec00a485e7f2fb4a0f042c8debe8d1a2a703debeb6be658e758469cb2a5af42f0cead33f7004c6f129c08	1659288006000000	1659892806000000	1722964806000000	1817572806000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
257	\\x6c66c92058b36cb33615921f9c66cafde2f48881e9c563c8a77fd8981610a31628447cb50213f995f398eaafc6898a0e06b4bb5d0ea223e67383f0c963461c0d	1	0	\\x000000010000000000800003c13216fc623499803546c687d489de7549e34724f56ed0ba3a2e30b8805893962d509f677de3a0acba78bc73f54647b9f27217286e8e8c62fa7e379f23cee40d0405fcb76bf2f8fb7a04bf8b20ed336369ac0f0f4ab2f688d8674eb95120b705972c016267fee37541ff2ce80073f35626e8448a449bd0b56afeb4344a0275a9010001	\\xdb609ebc592f75e100c377d563f0b3fb99a480fd039aac74e38731fb271f3f94e1abb9857ba1c93f27a683d4ab890c111923d2beeeaccde5a50e9dce63fac401	1659892506000000	1660497306000000	1723569306000000	1818177306000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
258	\\x6fee76eeb7bd5cc432390d143150ab2da4aaef00cde44a9ecb717b264d3a05c48a52880b83b9eca9ea24ca1061b55aa58c64947d6defb554746b03504ee0523e	1	0	\\x000000010000000000800003e82ff1b85a72638a7c758283c0242bd533e9c46a177d31c99c6352508a3819dd82b40c31014e8f5a226a9419e77d84d66806bbe62ebaa61c21e5ed13d677813ce755da014768ca168ae83de55ac4922264a67fdb3927e96986c654903921c6fbacf722aac33a6d3e70a3848b0e864ea909528664652540fc8b04dbc40671d3ab010001	\\xa37384e64f7047a924ea85b0495a9acdc3ab15ec8e2e99789c6306943d84e6b7fc7d35a61b8bcfc31c8550a9744018e185beed9d4fe6c79ac41227842e4e0707	1664728506000000	1665333306000000	1728405306000000	1823013306000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
259	\\x6f32207b72b3563a01ab47ebd44eb62e9f59b3747bb6d0c5f9d9095002ff60e670f910b477829418babf1a2b222469bf020716ce5e3969ede4368e01b62b5b55	1	0	\\x000000010000000000800003accf8987d4263b151a21005dd61312d5aa3dbe7955054191e1caedb9f6d6e1deb978f0072fa7fa60d20ea5f74611a9d2c5bd83fc79fc663c160bb2ba8ca814c484e9132e551c0dc4cd367db336a21f162dc797bf55afa241519e2b6b56f4ad73868ca098a52a6560cc620ed45c2fc572c6e76baa6e10e1306bc9fff8e8dc8c99010001	\\xd361b9937868ef33131f0a4b33b9cfaca45c9a764ae36315c3ce5d98bfe4e7dd290763f422752318c28cbb7a19b672ec8353fce63731a77f0836465d35205d0f	1678632006000000	1679236806000000	1742308806000000	1836916806000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
260	\\x705a9e38d409427884e8befdcff820992557e2a9b6ba4528018f41a65836e9e7ca9ab0c8075195ed62b9895b95738f314e4ef7c650859608df44bf99eb3c4116	1	0	\\x000000010000000000800003b2b8e553f9dd1e8130e0829727a368bf1e6e97430c851b840502f8debdf2f77eaf1c91e709c1f7cb36ca571dbfdd93e1ab8197da15a27157122d689e5b9cdd8e0319ab4bc3117da19be60a77d4355560c138eab2b38949f0d0d10faf02eb7c24f68e4fe6cdd91d8267e94499c1d771482587953578baa25caf6f850a358fbd7d010001	\\xf23a5c4b138a897acc4429ef694931942b456bc589b8cfb0726b7eddb8f0b5b66a502b6144df567e266914fb520c817f2bfd7ce6a5bbb51fe84cb6c5602dcf08	1678027506000000	1678632306000000	1741704306000000	1836312306000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
261	\\x7462e962af9d2a20369ec31f4ce7945b6b0941f8835ac5b3c26e91fe6279838197c5c3cee20eaadbaae5c314b74a58413ae8d6d0eed284463f5485852c160e18	1	0	\\x000000010000000000800003c2675ad5c3c37922ed3450479fc6f7741234ccdc3a7e88bba1baa13d10ed499e8cb1e0187e89911e72f4f1d41302b90dad7c8178df613be39bcd040141d6f6001be1dbd719d592152d7a289c48ca8b52f42c4f33077d2c1d6819c611d5a793c53401c8f780b8cd9091de3972c18be4000672beaeddcb4f4f46b5d8591ac9bf9b010001	\\x573f89a5475c458137dc4456b22dfe4a4f1a131adf09fc682f4adeb9b6e0c0101aa185971979f71735cf727e39eb8de592f66b1b0918cf12e88f1e97b1d2e50b	1664124006000000	1664728806000000	1727800806000000	1822408806000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
262	\\x7826f7b802c9bd5a6c41e708de96ff99c4de27d6f7e1b6b0142401e967c384774a5a17b93e5566c41a91e15bb00360d427b48e36a787f109febfa35e1777ca28	1	0	\\x000000010000000000800003cfca4033b77e2da3b47ad912bb35b2564163536938c5ba8610900c57c39533813ac1829939a19e68d88e28dea3f2920ed6fb0693524ee427f4925c8afab00334d8e2b85d54b22787e4ad8f46007a9e6d6ddc9e98f613bcf3ae844378075250ee2b5f3fb94e1f5de3150a16c0ea62b6ff9355007a4b71f685fea1d9ff381b01c3010001	\\x6613b101e4f4f5e8cf99855c382cd9991a38438f9757daf7660178a801af0a694cc240569850b05811c6885a8c1aaa81ea878a4896acd5e2780d32f0c1201606	1653847506000000	1654452306000000	1717524306000000	1812132306000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
263	\\x7cbe2cab0d669fa77ae106de5c1a4d8b2a01ac54c84fdcab3773c6d52f995bf166ba729e294bab92873d8f632f1dc3ceaf80a3f60f288f2b13a926d912baf8fb	1	0	\\x000000010000000000800003c329c94c77495188d475f727d95003c74cdb59cba30cae6cc0380f3b10ac9e7f421b1f22f6d805eb22ebfcfc1710e4f940073bd3de2d551156fe8c300e286f2e2bb5a425cbdaaa119068c69e5ccf823aab7edd85fa82d197358ec966b724cd6ec2cf5982be368e2e2a16ec15a0d9d92a05b526c584ee92956d36d08308242221010001	\\x30259413b098cb634e3385c93755fcbdc08a20fff9054e43130983216d7c8b2e50516479c1dd1ca393ef2fb2abef0ef64b612448bf2bea2cc9fb3d4df91b2504	1666542006000000	1667146806000000	1730218806000000	1824826806000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
264	\\x7e6e83240e4d91f735c4ab504ec885d75bb2c0304ad5c0287e4445cf7c049681558a34e0314f64f9e926f1018658b055f61bf490e4285a12f03063f85a4092d0	1	0	\\x000000010000000000800003ac915c6854ffb9d2bdbc07951eb771045f5478213f4020540e143ecde591163dcd9db00ef72827a614053a2bb4371d623a93c8f46d32e82f00d0e8f8471582cead9e5fca4b91b8d80fff380431b66da0561db520216d7caad688dbea9c19626ecff2dae22009554569fc78faae865f1bbb7e34675979c02d5958926a7547b097010001	\\xfe2a00b19b956950ecf6bfe03db28a88a6aff10868cff6288d8b57bcb9a4a83ff57721d884f9b3b42f417d17e485d8f757f3607d0a0662652ff5a2a7c8637d06	1651429506000000	1652034306000000	1715106306000000	1809714306000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
265	\\x7f7211a5e14f7097c4d3234bbe9875965fa9f3c153812b159a03bb93c90c148893b1501b43bfb7fa44ac0ad50f364860ec8d154b0294f816fffd54add658a670	1	0	\\x000000010000000000800003ddb2da78befb5762dfb60240eba1fa4e9a59de4fe02b1571df27a58e39ddee381464b4765bbbb292252193a49535f0adc7ce808b8b83f5b27667a88f4adb4a3d6260a9090275b208a9d5a7c8de75c799b653df438cdde342a0ebc1d18a2cbbd8275808da583a1ae9ea599be29f72e692c471589e8b0bc672fd614d5e82d7ce37010001	\\xede330d661bfc507006c4035833ef58d8c41576cfd186672d2cc4d47021c1d9df83401c4a2b1308302323a8b91ed8e6945b4d3e619ec499c0d9cf78fa0f24605	1670169006000000	1670773806000000	1733845806000000	1828453806000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
266	\\x7f9265802bedefb800299e33f7145ca4687a26f3da1d7830708eb51c92d28d80bcc31d0e0364fbc80ea569f5df4a0bf3ff32bf5ddc572c5c39a3921348f8dadc	1	0	\\x000000010000000000800003c2936d5c05884d05606699ad37bf8b74a048f3be7af7f094c56bf551577644bd22902535a12378cebeb630171b402792a276c602bfa46ec5eccca85b0fe00eb89b468036e1647116bcf7f83fcc4926c2a69b7e137b52142bd9778af77f48a7bfe0b9ee66a257f4d41a3cb92ae37a55709036a5e75b6be70cd792cbeeffd75d5b010001	\\xc50ecab20f8484c8f7e7019a93ea2956e2776fca057643db4e204625124db22509b8dc4793ad63eef4cadb79eba135211b7d4c806ff9a3057189ebb7c6d79c05	1654452006000000	1655056806000000	1718128806000000	1812736806000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
267	\\x812a64a10657872938db8a5f74460c56e8599883042c0044836692648ed20ee507070eb4e43b0a800dabb0999ce138b4908e38cc08ff0b55bf876fd29ac8789e	1	0	\\x000000010000000000800003a4f182309bd7aead5c49e612a4c5dad83903bf1e3a6a12c7b7bf432dcf2bae21213912b17310b6ba82d492ac63923be14d6e21f83a9aefa23a0a3797c6d0ffdc302b2fb922127e3068156c8221e58067f359fab2b1d41db3e38552c295bebdd8065c0c8f070db756e6e51530f6d3d60286210861adb6284bccd11351c0ce1ab7010001	\\x2881031f4d37b15088593b1fb700964fcd980d58737ad71820fe856de9c51c59efd4d4b7efcbc8865344b5c0fa1e19a3b1e2157e4b5ae2fa48c8e547f8eaaa08	1678027506000000	1678632306000000	1741704306000000	1836312306000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
268	\\x83928adaf09296e6b48972b1816a60d75456d36adb6c06f46c5adbd067d19bd1cd40cd41018289793037f071296ca3a8e00e9fb0669a95b96fcae0f281385149	1	0	\\x000000010000000000800003aa76c9061bd4c00e5bf3787acca9573f09d5109d32c189f9e3bfd542f37823d9f1979802ee9eeebbf7f96428c4eef96c02cb85713df6e9cf72aa9f81e9e3e820293434beb672a149831d02fe42aa94251c6352c2d65b07a3ccf5cc29e704969a130603b34cc15b6b302324667ca0cba522d4923c9554b5be3abac1f3e4ea7a79010001	\\x5eb3829ea24649f912460a3bf0fdba90dcaf2c5c5c10c339d26ba2b59ab1083a8a80366f94e68d71ab1e983bd11bd5989ed08b0431d30231d8f318520cd68f0d	1676214006000000	1676818806000000	1739890806000000	1834498806000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
269	\\x897a59bcb49eaf08a35c53d604c7008c2bc85df91dd79bef6fa6207e40c96f152ca0e67a5e4f3fe3b0d364bde91c4148b207c6c9a984ec2a4c8c6caa806eabde	1	0	\\x000000010000000000800003bba2dc37b8517fc618dcb358cfe870f348c0d16843acad21b576abb8e44c1951df8d7301873f8ba5060fe58d1688bf11973d85ad96e32a35472fe153a3eac7b5ce49d7730d1ba7f31b238431bf79054de2563384a54d7ce37ba18e1381f3aa5e0dc0b72773a478caee6666ea8215b0922cffb9746e3e43dc84af2b50e375d58d010001	\\xfbec2baeed59bd6c7654e91b46717d3cfa54074de97889fff96f66f85e7eae44d4905ce41f935b6809d00a7d696bc35203dd50cded4399b264c4ab1f3843db0c	1665333006000000	1665937806000000	1729009806000000	1823617806000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
270	\\x89b62931b5d9ac9ece4935fafff17a0304536d22cba3d779c6b2b7c7dd544f6e62b6c3fecd76d57aa512a9c96efe4009142d276884b178a24bf5ab1ee8f73795	1	0	\\x000000010000000000800003daa1307753367bc5c42ad28c499d032c3d027ceb4112a53e9263b5867e116f31986f11c91d7b8828d1ce74ae7abc96d3a1ebc6a8d636f45a51fc6d370bc650eff685442aab9776e887d40049a1472ecf6875a9c83570123e1019e94973f2d912e14a7b97af5a0b81ec0afd30a9c0442010b5080554aadfaa7af1ad32b21c987b010001	\\x41179bc0a29f47fc6acb43ce135d99c9861bb6a86b3be961eb0029014901f856638706a43d00317d2ca182d43ea920caae204967861fd1543f1f49a59e72f10a	1673796006000000	1674400806000000	1737472806000000	1832080806000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
271	\\x8a024d84a5a357e36d02c336b3db30cacbcea7bb0d5f7444a19325cdd01675d4d1f012f552d3f3ae8bdd3df845f5356e3de3f15fd45998b28491a14ea523f383	1	0	\\x000000010000000000800003c6257aabcb277eb673ca958c0ab6323b642707b21ac300399c3d7204193fb28db11f841d185daf4e2e6dec16f205e2bc4ae4615e096c738f293e83d618ece002d6107c44239efac0e292abc605578c7f827f7fc6f9bd07acbccf01a2add7804ae5d98f7409b21e8793d9951a89b7794a762ec6fa6fb8914939cc04f983c911c9010001	\\x62072dae891e1c6a3a7dde373eea78b82b61f2c6f0e4ee9f6ade7e5dbcc40dd3f37a81977efd5eb462ad1a819ad156bc08e3ce5990d81d337408db7de72e6604	1676818506000000	1677423306000000	1740495306000000	1835103306000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
272	\\x8e6a14e65acea55fb291461c6ac504de506d230ad6c5325f5e39c6cc572259d4cd10d7013818a88f40f490df4bff6fe7d894841db19c6931815f3fa0894599e8	1	0	\\x000000010000000000800003cce5e2aef8e14947b4201e455580f37eff8e7ceff856cec6f11c3206cc6b57d763786947c3481370db0593f3c5676c9fbd2ba62947c0775f9985a005925e57abeb8bc097cb693ecc6fceb0d6118abee0e2b63a872016e3861569e137ba6f847158efbd8bfc797f017bb8c04788bec24bee0a09276c20759ba3f4d082c019967b010001	\\xa721f06775326222e15e222dfd0a9e0548a5072bc9904d73e17492d533f3d8c5c311c374ac51ccdc1a3dffc20814b9dc6d7e89048af7b1937fde6798edd3310b	1665333006000000	1665937806000000	1729009806000000	1823617806000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
273	\\x8fe60e8b7471317f76b9981926d1bef508c7ba3d4cbd8f9c03f98af89cf4af1921ea3eb3f35f1aaa24d2f79459fd277faac501077bcff6ce90dcd6a35b8f3f35	1	0	\\x000000010000000000800003a76c2b60588360efd3d9e065acc101ada968e923acb6ebd3d1712df94f640194bfe9d470eda930712b8fe45b05b570e6a6186a0a3d71050c4726bcba051ebd8efc749dfb1ce4d9cbe3a86050db67278c9abd65c5569103d6f930038dc3536b12a859a4821fef2c7458ac11e3255b253d1d007a86069923cee14d52a052aedddf010001	\\xd97644864173d4995c20d0e93c8c434d98e34071fa55b97b88327ee060903b1b890983dbfbc2f1ed0c50398a700e2e36450a6ecb30bd792005f1c0b64b357a0c	1668960006000000	1669564806000000	1732636806000000	1827244806000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
274	\\x8f762b81d9cad51bb6fedf67cb191723a0e8d688d2ad4dd058e6b7b7d661577e24db1bb20c043e2a11de8cf28ae6dede9427d796f6beb812658f5d3387559ed1	1	0	\\x000000010000000000800003faab11ad299f8c3342d860b49bfa02b1b2cfbe51188e0bb86d567df089d6afbe908ca4d5dc32f4207f80e65681134594d3800ad2304f2ae4ec7c285baeb23d80a9fec6a17794473fffdc6b1659a64ee2a6e4308d779d69ee587b14fa5cde2321e2fde6278844784d685c1f37c1848e8fdee4482fa161e67e3430427071ef14db010001	\\xef104a1411fdc644dd0dd17ecbdaa01f863e6c41c6cfe2b17651437daaf8914ef66fe9342f17ba8459aedb704d90ec7dbe9081dde85b80d410cc345a6b49d50d	1676214006000000	1676818806000000	1739890806000000	1834498806000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
275	\\x948afeced711adf80dcd8d55e6d8ca94ec54b471ec6aca9a75c213d9a173404d35a6d17407f9307477e0f2bca3a76f58307b12382fc880607450e2b89a34059a	1	0	\\x000000010000000000800003c5d759ecb9b759c49abad67f9cd492fc856e940b2ceebada67bf932646a3f5b7f2f47ccc08c0f8cb1b31fde7b3c60fa969680e1f0da624ba5e459ebba645a97b1595f1757d51ae21e90c44f5e2c64901845ed518ce471eeda9bde798d27f6ffee7798b7abc1e70c39263ea864e5362e0cfa8e0de7700e838a3711b7071b92f51010001	\\x1bd4c3d97eb3e36ecefaf8f70c35e514ad60af910a9bf983e6473d0b85cba99437206c53b7abc23e02c52666c3d15773800846d092678bd9aa0dbcc501493a01	1658079006000000	1658683806000000	1721755806000000	1816363806000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
276	\\x96b60133e1586748502995839de3912f3c894e1b60f4330be6c5a514e244ad43618700c18be0bc31f1bfefe298b33b7c1b7b69d8927cad957203b0fe699fc0ed	1	0	\\x000000010000000000800003cb2af7ab1cfca72cd3052e35529955055a882ffcb83691432da25b0a05e3691cfc49cc3ce01aff124ec05f6b0dd85732d7c81a0986d45223ff625a0800908e5a34e21e4af1a0f391b0e6b5948b266cfc5ebf64d661f4f9556ba489deece48a25a45268ae8e12f3c5cade6bdadcfde75c1b7d6f1203dcce65561658b8257fec97010001	\\xd4a5e174ea93d5e7bdbab59a7e14741082c35d43dffd46086528927ba330ebb1792a177cf5090beef4ca7373efbb2f5ec8024e69161ccf496ae341c5a7cccf03	1677423006000000	1678027806000000	1741099806000000	1835707806000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
277	\\x99766fb83deb6f9a1194ba0864c7f01874c6fb9c830f4748f3c0d77d0d3101d1dfd40c8bee2c6825f36dfba610422a5eb6736be3ea1f5ea1920f0cf758a21983	1	0	\\x000000010000000000800003c48b14f1f5e40c293f8a5525a2f3d96b71dd55ce587aa3b45de65b5fe66b8ebf5e8ca06dae249957de784696b3550669818ccf827ca4c6d82bfa91c161ef817fa1ce36c6bfcfcb60591c80692d9388f299f1a7f5caff5079e7981abe5879c0f538956c53b5a6be79070c5303830d2c5184a44ccadb1f74e9f3c8440dd6d6ce3f010001	\\xd6bb845e1d640314cfeba6a12eaf995151837e85a44b9becedc998b84123cf5ff1680785d63652a75851eef6d33599fca035c4702d56da2bfdd85fe5a895180e	1660497006000000	1661101806000000	1724173806000000	1818781806000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
278	\\x99e2e340563ed044d751578cace1af5851fcebbc895424cb32dd1e7cdaa3064ec1f8f75c7ec71d3c5a8b11d3055059a99840daa33d9ed13ca1b12feacf8ccfbe	1	0	\\x000000010000000000800003b43b552818965038bd050eb927f60c6cd84b5e8e928e9c91ee70fc97869cff9e0466a18a3dad6ebdd809be1492aadf784ed225b2aa5dbd302044633d06f3ce4e31f5dfeb7727c716ab50557b8c7ddc86008598c9028bb55ea56ec79950a8ad4c87acb2288247e5df0e5e7ba9db50d997f1e46cf507e8e6a547da7c0fb4ee6f27010001	\\x45d604a9f36a5bde8674e5d0805c96c780b2dd55d255b1deb18c4546d24e4f2e453142ee1d28b83b384aa323e3bd6da23f370be63789c757729754e11344bc00	1658683506000000	1659288306000000	1722360306000000	1816968306000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
279	\\x9ace41906f15f576efcfcf1b1a85d44d3fb6378130361e58493a2b4f164faf3211a629dcb160f7ad3b056060d8c1223240046fe1d941b34ccb9dedeb12fca698	1	0	\\x000000010000000000800003f9812adde8d344791ff489e532d087fff4236890b9917568b457bea9344b833dfabd6a4740153101b1b1ecf54daa45424f778527077407a816b81f0bae1b8c0cfe033b521d1e905a8ca4bb039faacc381a335b154308f137388b303c8ca3ee26aac6f543979204caf21357ad010b5fa6fbedeaf058f3ad1919dae48a1557f639010001	\\x70a21086dca261b5eb0cbeaa4cd0a305afe0ec22092545439658875724375a4f38aa5ce50ac1f45f77308f9aa024cfe9455506f8bd6f82bc3d11c866bd4c8f08	1663519506000000	1664124306000000	1727196306000000	1821804306000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
280	\\x9b322ed4320e33de04467bd9b30ea22f2a3cf7f10e33947608a8a35eea3460095879df31b2e14c993076891da975985ba607a0a5bfc457718adb7df7c29f8114	1	0	\\x000000010000000000800003c83d45b7d19761ef53ae82a0af2efde3e1aea644c75993ecf8d571efbab023c0bc0e7906d1742558808515fc573753a4c27ebe741d9c5ca1b66aa08a46bf2d742ee74f12f0ddfdcf319587f315551bff45e9984eef806bb678e989f516763697b4fb9b804d6a2f12d4101c64863220c92f1381d58fb9840cc9441ba72034416b010001	\\x092b6dd4f2a5febb686a3d40fafa3fdb21a98a773eb7ae3ba127cfd5ab3d81e0174d86b810924b8ac81c82c6fc13dbd58fb8446e53cfa1e9e42541f77c44e30a	1673191506000000	1673796306000000	1736868306000000	1831476306000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
281	\\x9be676fbea8fee461e80d1d30425b793346f443f27d45f0433b59d6852473aff8bd4b910c1f278aa9bfc597f9e9c6677d25bab8e97910a815a043782204ea169	1	0	\\x000000010000000000800003c8cc323c383fa6b9c828c3660e1f37aadc53c223547840ac51d98a26eb71df6913002cdd0221b9580fe5f6b6fcb25df3124a622efa38c3d57b43c1489a78763ef1bd7a42ebe8e37a6c71803d2630632c0b452a8498ece368297f525c1e91ab8cf2f52283bcef67969b04cf2f316f1f66376a7a4e86a7b901a340744fe178454b010001	\\xd9d72ae15c6331a680d00eef80bfbae8094239acdc8f601c0bc2db7417628e46d5fe0913ce4578c5a34670d5a28f826c615f29e60f673bb09f4eaad558598c04	1675005006000000	1675609806000000	1738681806000000	1833289806000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
282	\\x9ce68fa6542fa738abd3704278e7367b1a451dee0f081db9fe2539a7c89363c5bf7e22140612eec60df3f558eb0532a4fba6e370c553d404fc4d28a928a632ad	1	0	\\x000000010000000000800003ee277e0b0af59cef6c9fa620fccec20b9afb2c22aeb19b624e55f516bfe6ee1a92e004ff78aa07d7838c6db6d71baccfaa6b7a045d58028bc3693c98970d342b3f7e8508da63127d1a5e3e3e57d5796031cfd35b257771c92ebd7e786e877b5f21c452a862135b06472267d6390d3b5dccfa43c7af003417c55cf91108ee8ca3010001	\\xa2a8f489343f704d3e9a4de57a340b08e6171e46c96b38590f5affdde658e9fe07483fbff0461bbf5c8b065a5e01937f095c373176e828e97443af85cb876408	1676214006000000	1676818806000000	1739890806000000	1834498806000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
283	\\x9c3257060b5a1695d996ded748b588efeb90fcdbe645e4f7c652dcdbc62c3de0ecb8a542b1d18bc3838ef2592b640d7ee404daa09de0cbab61afd939e5e46ed9	1	0	\\x000000010000000000800003b4af67ad28f9ebe558affc6a1dd600ec13022fc3e75681fbe3eee890feb46d291d4e8c06b8486310a56f7421eee760937c4ca09a60091ea753d943a1aba2f1ab355350376f3e4d3e0188e3d2caab4a958c2082a09a9316d58c16933edb9b693286cf6a070527055bbf26648d99ae99171c1d6773fac6e3f1b9732def571d2e07010001	\\x65a971b21d5a40f28a7ddd0d2223af211fafbad2f3160076471d77da952775be478f8551050da542b9f1a5c4692868bb5d28054ed7e3898e723f6a360d19c10b	1656265506000000	1656870306000000	1719942306000000	1814550306000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
284	\\x9d461a94a3fdd7eeb470a7f415db9ce36db235015245f388ba51cd001dc591a65092715e8688b0b72e1f67345a7f743dc5bf6fd20ea384fcc897f49636b14f14	1	0	\\x000000010000000000800003ad06fd2c3db1af142f26752ae20b8866540e31e8ae9354da288732699bcd3704f2d5c40ef339b1cf840611d04613abd5b5599c6a27767bee48813a6e951d9b87c89eb9b1f50bea282784a2e69392536f962e2a11ff58ffa4d1a7f116fef00da02127be65f75d27f69ff2d9b682e6f7dfd5e63119cd986c258c146caec8535d81010001	\\x4866c6e8ddf6889b36d21da7137cd1afd0b62d6a02edb495d936dfb3a3b0d5c4cc5afe38f16f7ddd5af4050128b4c70a064f38ae07e495905d34e36e66f3aa08	1660497006000000	1661101806000000	1724173806000000	1818781806000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
285	\\x9d6a3b22122334a06006b24107718e0c24d43997d6ad23d0af9804dd35f9a8541596f22ecaa9dbaea833c7589231fbb79c7d4d22275115e09f86616f34b62fe1	1	0	\\x000000010000000000800003b5c942636ff6539d4f248e75dea4bbb8cf4ed53a9b4910b67c14c7a3a5160c977151ef34871642dea24459aebf4dceb050b89543bd6c2c5d1adeb106045d04c2399075067fc9b37eb99263c3f28ef08810b6e0346e62ef0aac87fcc1af39274bfc8a85825de1e831a4f477b4dfdbb3672335675f86e83ca317968d4784328a53010001	\\x6859dcdd3a325326060a658642cdd9e0cff9b9dfebce20ccfde318f0f4174d7e16eda594fb86a4605bafb44b89ea3e4503a08259f02941f7530929cb39d54204	1681050006000000	1681654806000000	1744726806000000	1839334806000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
286	\\xa0e6cee261758ebdc349ca983141482128eb8b9c588c901f9b71d36bf8a8d93ec53703292982086a3db783ea38757696436b51497d0a9e2fe3af805c9bbab780	1	0	\\x000000010000000000800003d970d7dcf9caa33152a6cc13135f9aa8626c78f295beb1340792e9bce01661ef9a4e4518bc44d82d098cfb97fb6074efec74578985de7c8ec7fdbab270cc6b54850037211051dbb9c4bbb0266e1b68a9bbdcce2144ffb67c6a914198b3b46ea829eaa91269f306a4667a932fec58fab176c3fe8b7c19ee014acf854fc3594b1d010001	\\xe3780e8406bf1d01e75deabb9c05812c81ad0f9811b0f5c26130b76b85f7cd7b5531362b598ade7e97157ea3bfbfd33e8c7c848487d9806ca012a3d908eab309	1665333006000000	1665937806000000	1729009806000000	1823617806000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
287	\\xa29ef8094acd918d0fc3b04ed4443bc96f885840f31b2b4dfb25a25fbb14100f214ced512830391daf68329ff50cd2ad543d2d9dd081a3f3a771a453bd542068	1	0	\\x000000010000000000800003e72f497608bc77f00fd00ce82e39cedb001d669e2acb07d36ef366dea6197e5f731d039efb40288d308f3402eabf0933c7d3685815172d6eb2e4b2a796ce204e39115766d7d8b075630cc597504681ecd6684ef213081112addc3d192639e8e6f4ca5a0ffbd7ea94edc87dfe84a271973d98c0c6bf9faf22cc1366e9ce20365b010001	\\xece21c4ee2f12b2109a30a8e45a859233451cde12d04142acf72d7676a12435ac37ab0ea9c6f7292bce04356357a265b584232fe61761b5666b9e154aa17a009	1657474506000000	1658079306000000	1721151306000000	1815759306000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
288	\\xa2f67927e7ed1b86bceb66fab1b44cf5a118be071c3841068cb620e69e5a30dd338463180894a34529e9e79c5972dd637e96afeb007608356cdbbd4325e2c92f	1	0	\\x000000010000000000800003d24e4bfb781e9b08434e9babcce781a0358ebf6d37ad2ae4aea01001a7519f45e1ddc8a0b960f91ff79cc417d34b671c505b836a40c1dcb46703c8c868dea45270c427f5916068e866de38ec88c3076f0d8c4c1d709915c92c36f825c80bd3e539b87a333511f330cc3f174f0cde0ecea5ac87d7589f7543b184d1f1ff10583b010001	\\x98b8d5d5734a0a808befad2ad0fe7babe0bef613f10d026ef6e325ba563cc2f701b4a75a0ac2d298c026784c24a1f7534597d7f8447a6bbc0427fbf829712d04	1650825006000000	1651429806000000	1714501806000000	1809109806000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
289	\\xa6b2cfb56ed9839176360d899696f8f7d67b4d3aa16afa7633c4c411427fd4c226d272cf382c0023d864a9a6bf6139173ddb979305c963024e7d1f6cd797c4ff	1	0	\\x000000010000000000800003d3dd7e28cd99b9245bcc71b3a89678ae1571ae1646c9fda000a5112b7de8c9296873f7e694843a135e3470c555ea63eedcfa5443a0add5e1650b776c1e3944e92aad1500078b16891e4ef80553bf569573ce79234abc5ad2071994e586814e1e6df95a7af41959a94125f584666df4dfdadf12ec0d3ce97710d39ba88747b969010001	\\x4883ff51fd783a5644ca0d812303fa65ad23aa0b22ffde7b4010c754f2564b66d74878df76d5e64e5c8bc3947b3f4756d7b733ebcf6d67c62982a65200518604	1682259006000000	1682863806000000	1745935806000000	1840543806000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
290	\\xa8d6780955023e7d3c9f237fbe06c25eda51a82a8e5fd8ce950f6a57e7d1b9b474b0f74c8dad28c0eb00b58532a1fc31c72f873d6fd911080a593f6c0b358f7f	1	0	\\x000000010000000000800003bf4ce137f695da430683473e468db478869d19a0d5ab384a27c65eede19d2cfec1248c51ca9fa284a8f9329e5590b1b5ee7755cd022419e749dfc1e2d5b0cdea5d50cc43e04dd7de87db6fc2bb59b91c64f71fb42f95990c39d1e4b3a8b9ad5751254f9f1d01896f9872ddcd3b495c8e6cba655069667c9689f5470e042e1369010001	\\x0dad109a0ca24fb43b97c31d1d6f93806735865bdcb0949adf0130530b8f3120c3ce81033484ac0b73fcee81c84d6d9b20ac301c67429c93a8bddea581d11a03	1679236506000000	1679841306000000	1742913306000000	1837521306000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
291	\\xaafefb8ceeaff663a318cde70b8bdf530127b1ee87dd4a32128704f57dd53b150dc2bc5c25b618db42f054b7f67a894239ddf490944d90fbdb6ca64e5a5b8b6a	1	0	\\x000000010000000000800003c971ca427c4d89753b5a0178b7b6617c447605659c62e5f0bedf9ab0f469eaeee01b1ac6624c669396b9e3b8cf08097072eaacd175d6810e6d5697e37f23d09fe4821fe4e877a1dcef179796aa4ce6f8ced6b3fff64b5ec556fba98317a781c9c625ee9cd8a3cbb870dd7a785dad3c1185351553b19fc3c748e5a6cfcd1b45e5010001	\\x500dcf3c925f7b36f80a5899ee27e49266ab96084879d91c8020924cd22e8d1526e8e1bfea56377ba1aa01206a6ea57fc83d56dbad42a6e5a6a3931f0fd4e10c	1662915006000000	1663519806000000	1726591806000000	1821199806000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
292	\\xacc6af59158eac30fd3692ec4a75f1cb547ea9e8964a2a8fe59f735806f5931580127aa79350827a6e229db6cda3eb18d0fe29357772b82fb7cd429bdc58deb3	1	0	\\x000000010000000000800003c8c8c712f68cd4003ae62afb30e000e7ce2c5bf6d734539bc23b1c27fa68e87f9d629d28bdf4b9fa544e10b822d2b0995f75f647186883c5853baf10bb31eee56d37df4dd36fd26badbc89f316d6d7e7bb70f90a4b26f52356d93b8c31a21c0b2d18e53ba61f76c29f596cf20c03d61d26531a6e34b88e2af0e711eaa32ca74b010001	\\x2f8bf7b45c53be6d2a76dbae5af5aae68d146c5744bb7047ed5b242dc2f8febe0063813ceb09fa480f1500d93e8c96c7c7aa8de727efd779655c03633882db05	1652638506000000	1653243306000000	1716315306000000	1810923306000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
293	\\xac6aef09534e42d60aeb412b91baf5a74f4a6a7f2b627aacfb577f94e46d942138a7757e6f7900438f413913177556bd82d54ead0c8006b02d93ed6523e0d1ea	1	0	\\x000000010000000000800003da4150c6bbc064e1c0e4758fbe2e6e3a530c512accec8793729596d388efee3ab662cea365ff727954afdbc1f95ff7d147888f63e44d6ca9afeb14148af353cb8349db9b34f2780d5dc796ce621bd3df7b5622538e8ec69a9c3fff38500b36f814a956a9bf355f10b43669b45464238420786fac721d9c86ba0f43c4516c606b010001	\\xd001c168e8b03b6076b404c268909d538eda60fbd30650a9fbe7770bbf5f7aa76b14f93de622c46ca0325e70e85135e2b76666097d76976ae68f04df9c22430a	1662310506000000	1662915306000000	1725987306000000	1820595306000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
294	\\xba22a15336b9ad8968aa572c409716e18aed69dc581f81f20e1fc9482c944c65e2828ceafe79adfcdb49c0663935899e376b355014d0b29bf33618de9d07f3d7	1	0	\\x000000010000000000800003dc9f26ae204316fe6e188176e523281d63e5668f03bc0a399332c6b184f5cb65c5b345f5b72275f6381fa1af063012ff5f4e090ca08eb2ed49649211c6a577f55660b58006a08038a22b6dd61045c66d192bd4946372084177e8d022d11d9e2f6ac8b0393cb864ea6198a76905c0d9cc05f462744145f046b1531bc931d74aa3010001	\\xf27830994fc855eae35e29d3b0e03fdcc30f5780179c8831d664ae17224bc5fc8b378567b1f534a70eab568361f1c7bb7e7dedd97a24ff85effc7a9246f3490e	1670773506000000	1671378306000000	1734450306000000	1829058306000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
295	\\xbf12a7977c575b5546ee9d1a2fe7a87fafd403c089b084b904d3b4eed19320265212cb3bf86fd1656f466ee024939111555e7dc35427f4b7a39971d634e8c132	1	0	\\x000000010000000000800003aa395926506efcbab60bfed2fd7866b0ca2b6613af0695c737a51addb66bd30eace6a47579a0e6bc876392e500fa91d639afab684a1242120bec3e578dfa22a5bf74c750a87b1f0b76ecb3334d68b4597b2feb9da94cfb7e3295734868bdcaea86e813544801b91dc4a80dd6c25286ee4ee7fee58e78d85abcbdf3956b9438f9010001	\\x0cea6fabf4fe6ba97a6a954e1b873263dd6abc3cf79dde8996fae116307d16ca62c8c67a8cbeea1afe07eb156fb308174fbb46233655c40ecb81860d6b370602	1663519506000000	1664124306000000	1727196306000000	1821804306000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
296	\\xc3760ff783871e3d09245367dd1102d474812c1df2cb69ac4b13433a60e78abeb4df40c3a88d82a7b624c22bdc66e46bedfb3c514f8281fa9d1589fae3ca319f	1	0	\\x000000010000000000800003e68545d37f7ceb92012255458a7bcb0676a17a6f83cd40af38cb5b29e815c970667b6985988687728975e67a2b3e33ac1a65641a34b2f4603c2f74f240936ec3e0c155d4339834bd80d5d43e0b542b4eb1d7df1dc5204fc6903dc877f63247f341a96307f785fd0fddab7db2671c3ac53b4bffdcb8dd73603d25d6bfc3d78f2f010001	\\xd1082f02ea0e365feca6686fe39a485f37bcb358256ca2c9268196779d33d7e2e76d6b525c9f93b9e13f8a6151b6f6cd8efbe442ebbc6794ccb759e0d428450b	1666542006000000	1667146806000000	1730218806000000	1824826806000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
297	\\xc70a75ae9415aed5255ebde4a813742ae476450b97ef6a34247942c48088e95ce8435120d426f0aebdcee1d1faa491daa740a0f0645ad1e33ef083a38dda3da7	1	0	\\x000000010000000000800003df1f3450a8b05699132217c734f784c97c698dda8f326c68b6df3ed3083a4c324bf74872abc68ab0c65576bf3025784e02f6fe4ab2ea63a445c8676a64c33afeab537b84f765e246da78c757c5bccc3d3221beeabe67f7963089db681549c58d824fdf5cabc573cd78d9f8ad9cbb201e118c96af528477ecf99e06338af929e7010001	\\xd7aded0ab6e3f6076ebde48def33dc09478109bf79bb664b46c3870545abf622841e97f1eae95284c187357b4eb0426d4337ce50be3fe1369870a7bf97a14e0a	1680445506000000	1681050306000000	1744122306000000	1838730306000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
298	\\xc81edd17bf9ed3777d82d0e0956f09f613ac72ac5034fc5790def8b0589cd5fcba65a708f501eae534b57071944dd3c2de78871ded8520a4690f8c0b0a36161a	1	0	\\x0000000100000000008000039381cc2bae54d02a09762ffa5851a6ad41d0a703b8d25f059da2da3d4d3dc11c475f99d0676fd3c2c05d48c090e9ead75cb739376c0655fadb55a196b9c12d65b80a15328b256f3fbde85cecc30182cacc00322081eae49a70053c89b666ec9d9279847b30e58e470deb14197cf30f746a5424d391923b8a2021b8f8f81547cd010001	\\xe1f97798564a1241854e5a868f2a0177beb26f3a296b0da431405f7449a0f428a77a7a695bed199c30086a8ccaa929a2ccdb23942f55535f6ea2b48ee2ca7b03	1654452006000000	1655056806000000	1718128806000000	1812736806000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
299	\\xcc52e068ecac66ce49c5ba8324b47e17ad87fcf7b3393f8e58bde783a9304851425e8b8468bf22236ccc3764953604f1265833a23186566077fa900e27891799	1	0	\\x000000010000000000800003c800dad4c5abda59564e546c5ec82b414f0705f237cf0a0228742ed9493fc7754926ab2061fe27aaf7abd44fd7c72fcde1fb3d0f873619694ddfe9a37d5ae58f67eaf7d5c614edcc1c4c46b8461c23e273bb9551bb7922f6caf58dc1282f39a35a89e2791a34ea40beba139f25ab9035998469b9976b17fadd56e70c48db624f010001	\\x12a04e79b2a4d4759df728b82c8b9af9abe5cdfebb9763476275deec5a24cf066f612b64c946b060713c089d8c43d593b5ec3dd2ee0b88606c1d3616a6f9ae05	1661101506000000	1661706306000000	1724778306000000	1819386306000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
300	\\xcf9a6a20ab68c7eb51feb0589fd7dbbfd4c05a77c5998d58f82e2eaa631bc2250e4f4936cfe33c0811cea3a1e6abb03ee8bfcd7801f1b13c0a79fdb1e0b15f4f	1	0	\\x000000010000000000800003ba3d73fa24beb7f53ef33702b7d557830ed9f01af14e483ccfc9c305fa85711da6e4af2ddd80e4a47842dba241f7e2b3e50223533c3260ce54feb6d00ca202da8eae6294e597884fb8c719228a907b6777b2f7d63e2ecb75074c6ec370b1e86ef1f868b737640b63bbaf7ba7c8ccae20451d5d2703d195de86de756446a25033010001	\\xa72649d168a1aa7f76459d3cfae3e20cb8e9b251a4cd8b0cfb37e0ba40e0d578767cc9537f1e1340210d5f5e41ec11fefa15ad1fc1ed7d46976463190fa00f0e	1659892506000000	1660497306000000	1723569306000000	1818177306000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
301	\\xd05abd79f2a365505872b4ddfdadd9ac4c2cf79a4e7ba2532c2f5db5f8c89f57c81cb355feb6c8ce86ded550d023b3d866c8e94117010a949c5a298fbec2a617	1	0	\\x000000010000000000800003b87034b80443160488fbb9f14d3599e7397f50dab4752b5abf720ec14d141b6bdff5a11b686aaf902e129b4523301e1e2cc73af860d1f78755d886c0fb018cb08a11c75840d54c65dd812a714fcdd383ad7414163ac012a05ef20eac62747c554ebdc399069ffad9b5a28918571478f87b4a5c6e47100c05242e041ee92d7017010001	\\x8a55aa23f21d5ee2e55bc0d643619ccba367c1d909a2ad6ae13e0c29d5a75115e131e73a459ae43d75cd710f9990f02208d2942a110d1b7c65f383897664a501	1672587006000000	1673191806000000	1736263806000000	1830871806000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
302	\\xd0aacdd6d0e5464119f1afb8a2ac127444fd30daf82fa386e3f1e5c00c830cad1a39b662736716d812db34c790faa529094130e6db18dba0c7abb5dff9104327	1	0	\\x000000010000000000800003fb80973ade8dd5c8bb8066fd24b9d0ba2b14f5dd926767a235177a9b73b581bb22e8f62051a42d9c60e177b18922bface1bf5fed17339e38d902b3432f3b72c169e49a26b2572cd7f5252373e1dbbd07a482c7d0ad5eaa96eebfcdca414412ccf83b165d65adcbf00b73f9db9b5a4c55ca1a71585903b5742a234fbb1187339d010001	\\xfb987548231d8d370d411febbd05220ea23e29d56192e77c664aa7b51a0d93419a6ac96ac65ae3cc58fb8cf8edbd0dcf15d052efd7197b5a3fbed5b6022c3f0e	1672587006000000	1673191806000000	1736263806000000	1830871806000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
303	\\xd19201558d0a73155aba81a5f7da317c66b5a6cfe76ce6cfacec066c5264afd2c0e3dd5b71b57b0223703f3b0c733e1b308f80b97daaa1e99eab4f53d3842116	1	0	\\x000000010000000000800003c86e74bde0ea5f9aac2da1d40ef74858bc8fc39b16131093f99433a2c5f65555dc70c23497bc62447abab1b1876fbf2f81d7e53a6b97a36d7925233b1265ffc76278bf434f3d1844742aee8cb21e7e535f704397e3e30f9dcc42dd939577edb0129472ee27e8275e02e04a4352427e4b4ab52ee80487db1e5608a2bb96f249bd010001	\\x3ba20ca81b259202b48db9619a5a271489171177baa825b0fe82ebde08c284976ea72d5e504861a436e30b069e05b60856bd7b202926afda1bc9f4a044c2970e	1656265506000000	1656870306000000	1719942306000000	1814550306000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
304	\\xd1ee2e6df2d7c90bdb8961aa68a8221bbc7c9e4a1632954ecbd2d26955de4bc922f253361d60919f503a70d56a4baf368c56e28c1da27a7477eef7d92353f06d	1	0	\\x000000010000000000800003da8fae1db79875573e8db42e751f1558a592f3a1241d4042a6a5d4dc098fb9ff4c261962ba8ba2234f3b1401ff7690d2c26869cd70dcc628e442417bc8a8186e20d27282001dd79747d5406d5ec645ac202f12f7709e25856d59f89a44dc9ebb8b7d20640198349cfcfb9d581a6a03f36db9c6bdc18e7446b24bd09c999eff95010001	\\x61e6bb0ed47e66942342c86e9893a096aa1e3e2cb9fd0b8c0b4e362d1b6bd54dfedc12ebd3478e5d7e447f27a9fcc5e1bdcdcb235dd1f80eecdb2c547b3b3b0c	1658683506000000	1659288306000000	1722360306000000	1816968306000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
305	\\xd216da6006d42271f7048a40ef0f67be8facf2e6ef62603d87ca9a9725996dde943c3dfe9f89b5f0988abaea8b775a0c919d64c325468730ec77d95fbca057f8	1	0	\\x000000010000000000800003dbd2210831194ad2beefc5ad8913530258498d662b85c93a51799e726e984d0e08041c542551d9316d71512ee75f3356ae54e52673b2695c8711be748e79f9a4263b3e493ba64f11139240a35d494a454a69c64eaedc522fb9b72163e62f62959062e1adf4fdea302730e1aad3c0e59efb83bb88209f1329aefaa3460f5b2f21010001	\\x8e196397eb91483609fa30f27a2d7614bade3d47505cd48e61be49fe6ead13ec5c0ccba74f82d6d33a9fd988ea75031a2a8df7b7f328a1f3977614cb6b13de0c	1667146506000000	1667751306000000	1730823306000000	1825431306000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
306	\\xd936c4d5c3c88d96bc212df82e0e1cc5512318db35179d0061db7bb30291809adcb254e4c14d803647db43e0edd741560eeb22cfd2bb59f1c7c5ffa058eba26e	1	0	\\x000000010000000000800003c6b44814b6df3db60c085acdfed54d917b666ebf9e8e856bbf7e70e7aed8c5a0edadc69d1d34090e0ff34b199ade6983b541e110b429b17829dfc2c31ddc8f29e0b48af39d0cb00d217e86265b8e5572b46d33a48dfa1bade9bcf28cdd91d7e0038aa96aa68cb1388f494d669f7772f8b3257f7bd766411617039de66c64a899010001	\\x5265315b079b68909f8f911c15237367adb7d92c2e6a4b32484be1a8cac92bb0461dbf5213d5ebc3098adae37c662338016584bbe9866e6d5a8e476820f49a06	1679236506000000	1679841306000000	1742913306000000	1837521306000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
307	\\xdae6282baccaf6a91743bf0afc863a56ea35e7235c7c76f09fd4183ebe7f63b295906be499f56f321bffc2cef7ef77341f9edf412a5426ef8be5ad4f4c373afa	1	0	\\x000000010000000000800003bbe7af8460a23bc1d571172cf42db96a85c854e30a225a1984c0cc9871f6c3985c6e0b33fc4af4d40572284301f499f9fbea9f292127545b86033fdf6705d6a62947af96d5042c23cc73147d8dcc7fb7b4107fcbfc5bcd36cf124a14217c5de9ece71343c66e182b6470d4f9da7d1491179c5dfedb1dca232a11bc087696725d010001	\\x8f64d5bf33dfc0c08b40f5f58a3fe9fe5581c6d5b9763c1c09f7b632dacf03e987a5b663003cdc7d4fd8edaa8f24e2b8004626f78b909952565fe9db0190850d	1650825006000000	1651429806000000	1714501806000000	1809109806000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
308	\\xdfaa784f29b80129487273ad674f4f6ee8bedff96a443fa473470305c65a8ba3edde39a07922be415f02d94edf16937042d5331c608ee3f33a7f3b07ea551022	1	0	\\x000000010000000000800003b8161abfda437d27693b2b0db72a6c7cd4d74468800df58229077beac6ba76b9d0dd0c1ee0d07fe1e5c3e3c2565bafab3bc6c63eadd96e3cb27f7d5d714fc6524535530b95974f1e36565f67c597c5881700945935a695ab94a083636e93e475c9850267b7f2723d1f3f0ebd47fbb5b3b0d8eb20d99bc25fead23ee37a2946af010001	\\xc24a615c0db9b41d4e015f5f78adb2fce2c25a4b4e8c51a8202fa5ea10fc27ca42254102a9ed867dce4e2e9db7645290e3a1c5f43aeb273c35351f0fb63c1400	1675005006000000	1675609806000000	1738681806000000	1833289806000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
309	\\xdf2a555f81306de37d6f97bd63a1a9f52f06e2d145cd25ac8c343f87409a93d8b467bd1a36d98cc440e7b705f0527f9c92e5caf6538fd4a259bc30cd0809ce75	1	0	\\x000000010000000000800003b525a5e7e76feed36105cb2fde49477e3e25af64a577cf87e10beeffc1cd4ecfeb7dd879d7f4d8a146d7a64541385c3f9b207a6dc87d13a69be6d44e95e5f5dc7ef9a8ab9b6569183cf326875bc84e56a81dba4a62b5c7dff0fbf04424d77437afaaa563c4c8970ffe724bba7879cd027c3339617b013510637f60513c2425bf010001	\\xfa1f9b18bab5cb695218eda8fd481a9ab0f5a79d5e71b2fe44faad5566521766ec9c0bc987045162d712352fd0953d7ac93a5b9d4a6a8c6454afd49f4fac2108	1659288006000000	1659892806000000	1722964806000000	1817572806000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
310	\\xe0ee503968db5fc934cef6bf643ee171e750edd5e96265d25f0da114c8c69ccd00d32afff1229a3ff8f099c29b0dd67d949a9ffe9a8b10e660bd981d91e85e58	1	0	\\x000000010000000000800003dcff1166669861d45ed4739aad59cd0d07898a100aeb847a92cd491c411ebe81669f647a309d51eda2a19b6c70d69f538da7186a66b827b4a32a9f567a2b82686351afab273d9c1d06d26f38903976867b1065a753f104dab4a1d05e66c89d480b244305265ebfa811d08e8b370440a45b9ab6550221827290529c00483603e9010001	\\x5bf5bdeadb633c7a7867287aa0a79c4f4ebe273bcbaab6b98f858c31043017eb4210aa07ff1036f1c8c2eed15ca065e7aab4d56048f239952a0dc833192d2f06	1662915006000000	1663519806000000	1726591806000000	1821199806000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
311	\\xe05ebf3b446f6b3f663a345811bac85130534622119afb0603324e8ca2ac9bbcb78d72f093b64420948686756e0d8bddfb0957a08edf708902e32d1867e6a021	1	0	\\x000000010000000000800003de2ef1e869eb116952cd7240df2112921e443d4ff1c03d78684643afe011b6b00567b9cce2b309835e4038662281274e4e52742185ccd159f20d7447e2f785d52f163f01be9c9218e4eaed0284ea2b0f1d4476536e4a2b25dfb54b8b7bc1040d2391ef25d95d5ca5d24d030b7aae5a15549bf15346896797587247af4f9898a5010001	\\x9cdd984f77ce6bbea59ef9b93e9af5ca545dae067d32ebaabd21a03ab9d369bfdb82da78c94920effb3cc0fa158edb5feb2cd1f9dd8d585559d10ea17705900d	1677423006000000	1678027806000000	1741099806000000	1835707806000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
312	\\xe1d2dc172a75b6c65c91a3b73aaf0caacba824f5469158ee40a4599274ff90ab62e6a238ff5001661ec73b873e166d03b92d574a2f86a305cd7255b8b58672b5	1	0	\\x000000010000000000800003b4f74d02ac93961a1010066ffe39c166c57b88c36fd43b212925fab9645be4457b61c0e42d79f9ee0f0464e98c8fe3948f13ab88dc87db99218ff15006ac6cc4e71ac83c5ff2bce167f91af829a69caeaa860b71c4ff9ad5fbfd36bfc308d02418cc34a71b240f40173f2afe7ec88276de933b5a75da3b3873d3462f7f881d93010001	\\x5ed6bd2fdd7fb883a4c128c1850b751827c0a91a579ec454230121bb911c7b7b68fe379333078a3f5200817df5525d60dc825f2d6597b67c1f62c4a171467709	1661706006000000	1662310806000000	1725382806000000	1819990806000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
313	\\xe2ca844acd15467986fc365ddb5cff34c4d2eae6af2292b173998a7aeb87fa10f9c970a6c03fc994a46a98ef6e11a091b8b34e373f860a1a8ed8c0159dcf4131	1	0	\\x000000010000000000800003ca5a9a2ab8113f6e424afd7331dc0f5eedb8d7748a18fe52ecd85627c559d2f839535ef675688546a4a83b90a6abc2d8f8ba23f1d384880790d3a21f645cea59e96851b6126ae8282d604c36da44ea2251f52755f0ab4894d0cc35851e9af16662307f3816437a277adb88fdfab7ea68de61e99ae80baeebe84abbdc0d67a3cd010001	\\xd020ea8db6821611fba6a9711938d2aa4c9cc234f1a8f8c3f222fd4bda125d2bd38a63f15199fd705ef79c1425ecf98cf801c31fb4ce6128a64ad774e7bdf803	1678027506000000	1678632306000000	1741704306000000	1836312306000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
314	\\xe5aa0ee1492df8a583e7d77a87006957a762bb5aa140004067bf5f2e20cdfe11af416cc608a802b66e042a8b212ec72393a77441276adf93cdca14c7268626aa	1	0	\\x000000010000000000800003cfa2003b05c3cb3304695c2fbead119999f9c10dc5be86737fe561d4745781cebc92634bacbf7b4b7b700efb5eb5abf100839fa5b3147c7226ef70624f200c23012ff1c8305d2275e70954c53d86cfb743c8971563128750b53a66a8d7077c0ad42288a3dd70061c4ca06cc1a5102948629df5a402acbcaeec6bf9bf59156ea1010001	\\x0311722ebdd54e4da5ae8fa2b726ddd311179315f83f692aaf1674ccdfe29cb03423280ddf59f806a226f24cf9068484279494facb0b78225931853d292aa401	1672587006000000	1673191806000000	1736263806000000	1830871806000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
315	\\xe64e4ba4f9491b1cd38517b46458d3e3add64860424b38102445c3bc2b7d947f5311a31378b7eaa82be5c730543e878ba72b3e09c6c0407bebdce26a4f63226a	1	0	\\x000000010000000000800003b7452920b4ec204b327c02a6462d34cae5939f8ce397eed2ca50c772a11785f7924a66532caf63ff41b9f82fa13eeddb53dd0ecd4de631b3687c760826bc38960ca55bc345fc0a82fe354de11ba8e926bb3434e9c39b57379dc397d3d43732602a4101d29eff01c23990a8f41169fe168917d02f7b3d07a6ad610372aa847f87010001	\\x7303b72ba17dd6dede7ee67e8b63d5e031398509aa12d7ba86c8b8d065d5828e7acd0e542df9dfa57edfd595556783c385e6d478972b4ecaa87eec3d964bc703	1653847506000000	1654452306000000	1717524306000000	1812132306000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
316	\\xe88ac0834f875765c9c5e24b3df359b534b8103fa613fab834664b7daca7952ff413ee158fc1851083956b60440ac42f2173a0184a2593d6d145e8726afd97ed	1	0	\\x000000010000000000800003b374ae6df7e798d3832f4ed213fc6293397f94eb7dabb5ee534f68128eb44b7b23a3f5ab85343f81277206f11ff5b148741d4591dfdcd585a1eef475afa90fc216d534871b9081228fe1bd74799bc81818edb96802daa5b689c791d8f532c7540c7bbcfe3b4c3e60b75658e3be51bb47ce119a14a98fd59474c846acb614707b010001	\\x5da347683a481a1f79c282594ad92e761abd4944559e6dde88d4ca53b5660f30cb01b2a21d26fe2902834b41de146cc4a15f86090868b98565bb500ccbcdfa06	1667751006000000	1668355806000000	1731427806000000	1826035806000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
317	\\xe90acb4a9195c1533d0300ab98787fabad213ba511afb85f570319a2c4f3678ef4c52ef17c9490a7a1fc6caa15a7be3f557af2c41490daa48ddfadfd481d7968	1	0	\\x000000010000000000800003c3f34d971260cd0b8b144f1d6e38ef4a24a4d72decc675f9876819468aa061c39595a680c3712c658f2026ffc01779d374b93cea215b778c7049049e6ce7c5b21fa952f671812b33bd1160d4fd616c2afd96b2af9f155d55f5b34c2780bf0895e3b6390e1e848184007384c7962c61b488600c981ab792a393c721e48a3afeff010001	\\x238709cec4b9fbf46fb2f3bb6fbeb6175fd1e58d42ba3c301c5fb46363e542dbf0eccd354f81017c874c6950ecb92130fdfb7afaa0c5d41a0c9443559d933d03	1660497006000000	1661101806000000	1724173806000000	1818781806000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
318	\\xec42cc06acb2a51cb65751820b9f1aefbe6ed6185af29375e9cfef654d07b6ed67247a2f89ceeba34e7cebf989f9ed46a9122c4f6e2fe5bb7c16d80cb64ee32f	1	0	\\x000000010000000000800003ac2352292230ac881a8b294b5b1489f8fd07184cfe62c540a5818e8d5168781d7b6dcb4725f1266efb1876220c95abe88306f2edcb1ffeb8f1e25fb84fe2f2f66264712ff743cc9ab784a64c54ad87343f8f59df0db5515f902fed6c35ef76127972a5cad729020e964462a894b461353f45137addbc1b21ffa29b6661706dad010001	\\x59f1d7b831fd6a01bb0bc424ea005df7ea1a4caec2279804cfaee55aa2831cde51c57768e622ebf64517617397e15130ed9f91d85e61fec86336a52b85440709	1681050006000000	1681654806000000	1744726806000000	1839334806000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
319	\\xf046c3c964c1eae4da51d7049d0f811b649c9a9942478fc2b154a0707c08679bcacb4c7ec402a1d6adcb8f23cfc689d4c1fd64aa5bf60781aa41b859b82f798a	1	0	\\x000000010000000000800003ac78672dc0507bc99d4141ce162c8b726536d0da2c70d2066c1e08e272a8fae9737dcac94e901d334ee2f6ac37a7f8e9e4cb66153747c5f953367eefe54efc64e78230fd9e90b16403728077d0197beea6239521ce2c89f0cf0e41d9e743e15ba631ed100e6e6a73627ca4ab19df3ae02bfc04865b44b75e57d0697bb443a6c1010001	\\x41c9b83bfcdd5868ec41873684404643ce70a3ca63e2ca47ac4d583db8fc477ba23e53e37e69176eb52cec500bcded787ffc035894a73669050945aed5edf70e	1672587006000000	1673191806000000	1736263806000000	1830871806000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
320	\\xf23acf88c1e7e3314c9a990ac1e03e68c8f0fc7807cf29f3dbd276608ae6b88200ff2a8d00ea1e08cbd7e324df6283432810fd1d358105e64a3fcf788fa9a620	1	0	\\x000000010000000000800003a8adb90743100d27df39ff00fef9328634e83957476a7a3988a301f52e2d6bbf4b0841c5767a32946c043c2384257318d7aaf1d4494ec09a62a15133dd0a3e296c9a2d2de554657b71ac571b49b5bed6711452bdb12574a8768982234e0148ca215daad7af67256ce786d99339ad572bf21276b13a12e17831dfcc31770e8a5b010001	\\xf36c5f5be1e5cc402583509b1508c51d086af25f69a9f5f3abcee8aafa3ca9feef3c89724488cc8d3ef5a1d4293f70907e82be57be984e06918803c788242804	1680445506000000	1681050306000000	1744122306000000	1838730306000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
321	\\xf3e2e50843beddba865609b95c03686ea2097933a238a319806260ff07311d670c8a98c54f3718ccc719e46db1ec1c6c0333242724c397ee3341ea563b3d8dfb	1	0	\\x000000010000000000800003bafd240dcbe64e833501292eb8651c97e2e14f83c75a3c948dc7bdc8ba0ab7150e779d0cb1c2bf7cb1dc8ca5d7d16d4d20a2f7b6dde004d3ce632a2e06974e63b4fd1ad4b448854ab58a85fb8d7a2494a2d87d955bce6e0501e8e4205fd505ccc52cc87763f5398b78e010180e1041854a7824ff1dbe58eb3d60aff9eaeb634d010001	\\x82978f78b1bd1fe3df861f388d721fbab5fe95849cac9b3155aa3a482139861b8afc8e0bfb9374bc1fb92996b841deee39b951c9d2746e91224cf5f1c00d3901	1671378006000000	1671982806000000	1735054806000000	1829662806000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
322	\\xf33abc0abd698a6c6ae95acbc443f1ea13c5a25cac2c652d34d0edac7aa8e56c85209bf06c5372e97e004e1a26dc1d5a85bface833f36f3641f601b4578e5678	1	0	\\x000000010000000000800003c2c9ce0d716b9b050275254a547a041cada61d105f59d8a38fb28b962e074c05ce4bd233f90d371d2245ce42b0eb5b59c43c103c2e18d9443dd88eb9720a8236fa4754a21f4a70d29444c378c6e7b37acc131acd69264d7d38afcfd01e799b65eb1d17ee4466d0763f13a554a5f4dce9fdada5d42e22bd8c44ae8fced75be969010001	\\xdefa6f06ba1ea9f7b0b46d955049c331f0edd5d493b637ee9fbf1d5f8a3af155ee0c9ca673db55c15af9df4d85589a07737cc2b789dd2f907170f53d2b28790e	1655661006000000	1656265806000000	1719337806000000	1813945806000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
323	\\xf682916ebfd0304ad26e4e7950a3deb3faf8c960c57ea661a8fc3de00eed532d28336e7a75d3440ffc3d7c1e186dccfca336fee658ebb80b2ed422bb48d681b3	1	0	\\x000000010000000000800003e4d249f495a9b7d4f42643fa08fb00473316f2076742a4b8e5802ff4ea16c2ba0e8091a6875e5ed61c4e746aeb2ef5489fa156bb499f16113354ec698c96133830b677dd71e0f873fb3b9b9d3465a5ec42eac9edb215722d106b73fa9ebbf343c3da487ae5a3e156fc358418e0ccdf1ba38bc0d9d17cb6de416ff68eb1461413010001	\\x2af2cea65b18c21920a5568d91d25176a1af5e248e74cd646934caf3ce9163f8def22477faf3fc649f2fa96c8a7d20f6a24d8b93cc3642e9e1863247646f7304	1668960006000000	1669564806000000	1732636806000000	1827244806000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
324	\\xfac6a190ef49df90ef23b7297c77f85fb8c9364eb7ac8f5ed57b0a75ef0eebad73f21c13a57fd392a6dd6832d5e95bf82e7720b8a656382afb7e18833bdb2a01	1	0	\\x000000010000000000800003f64caa4b48912b81098e53d132d9bbd935653d0f5725dedcc4feb8797836b72351fad65424d0ad8770a6e33fc8ddd8447991989670d5be35cf0c324a05cb938babf552ccd3730ddfeae3b037946128fe31d13ceb9e13d4189b0229fe44bca01a20a15fdaf1aab5adb7128fc66c0443ff683f80e112016b1566ad847f08a6047b010001	\\x6854f2c7692fbaeed4d1aef0f694682a2bf27f0287c4bbf397fd73e237feaf9cb0241253aad22db99062ec1ff80e1902910b120828ffa26f3cf21081e2c9f600	1669564506000000	1670169306000000	1733241306000000	1827849306000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
325	\\xfbd6de55db47613e14a77744b816ef8ab463e0e10b36345f4d78adfd7c1775df3c219beaa7a0bc25383e631e63bd91c28567c926e72c9bce96ffa03a320166a6	1	0	\\x000000010000000000800003a9547f10ff4de4184d5eef0e1d1981f3441a6f3260b7f1b72dfd8daffccd3f43e524b3f23e4cf5e3975fa229a16e383f1325279abda2d44c60c6e62e0caf52355806f95e1a188b47113f89f69f33d47ed1929f99aa04d96c56af15f2d6b207723e5f68a1e432616731ff9cc6aaee2af786a69203e49379fff1fb760b39feb253010001	\\x52fe3c4e3e3f25db0a6518fc52cab6f83e59e7aa304398cf49dd65f7b7407980bd71b602940b444d57c816b435d7380b84f94ddaaea4f841a2027d1b55ebc20e	1675609506000000	1676214306000000	1739286306000000	1833894306000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
326	\\xfe62b53cd100265c85dc08c9f9240aa8e12061e2f045ffb155f53f6f770cdc1d0ef19e3ccdc40d74219de071a104066ccc2cf082f08c909d83a1d3aa9f44ecaf	1	0	\\x000000010000000000800003e986b263674542a34c33a26b31bcce34277cdb47cd3e264edeb7bc80b9f44ea745fa4e80dabcb804c9d359a0822363c30ac24dad81bfb9da62cb48d81ce214660b3f750bc0a676503e07cd94bef4f379dba2df4c165f385385195a748a8d5f39c50b77e1e5676918220ecb8fda220942d70c023a8cc8d217ff34b65ab27d3285010001	\\xb25aa0bd7d42045d24ec1ed8d33a7f3abe9a545f0fb371064b6c51d42592a47584a1f3e77bbfd9c44ea4adb597ed797e68f94ab6be799181adcfc61f483f8502	1678632006000000	1679236806000000	1742308806000000	1836916806000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
327	\\xff0abeadfe63207a2c5faaae57bf92858b7026c76f420f5feb0f9ed0d1542b963b4da815e76e89904d81c026490ed7ef2b8ae6a24d51671115096095733746be	1	0	\\x00000001000000000080000395b303c1c9b506433b9538bb4aba4777ebbae4779eb9e6e7dcf8affb7e6acbf3329180806771e171c0abdc1f87f758bc611b9b0fc84bf1f653b3ce384ac371059e964bf42c7997fee31281ae4daf735b0d2798a02b7c46353136fb828e8a219800b6e563d664f4626c29c308132d06ca54827e9ad71e0e8a59b1e4c695fa0bfb010001	\\x431afc95f007d0445204ea365db6b726c43d1e1cfdd506bae1943d3f7bfc80e30ba8200e3aed69120f5082d13baf18cae07cfcc28c015718901a9080713e7e0d	1670169006000000	1670773806000000	1733845806000000	1828453806000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
328	\\x024bb52e2e74445950e1f89302a7c7e3b23cca95206ce57b838a8c9f88ee21092f10654097ebf3194e71fba01dc3d54f4fafecfd9914bf02069a779a66051c95	1	0	\\x000000010000000000800003a1a45ab9336fb43181ee06310cfa12804169972dbc3e69e917d73c100d121c6148aa931235c96bad3f7d04df922812cbaad0847f8e084b10bc0b8821c91d418bd34ff4f3171dcc05069976f583efdb4b264b58834bf2a2368e1d85381c255ee355f31c47fb6cb9ffd23b456cf35f7a9340c7af63225713b91f07e72ab6c7bc9b010001	\\x80b44bade7c913db7504be87c6a0eab37945de0a3a4e99244fc5c65e5c1435ab117089131bbfc48f0aa9cea210120e1ca5567421d2276eb047181951a6049000	1674400506000000	1675005306000000	1738077306000000	1832685306000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
329	\\x059fb6188788ea8fbf85902301fa7d520de1307c61dad4db6b163759233f409fb4d31cc148e7db3a4b1dde7c5aad0f07f37952c4c7cdea9600ccefeb3d0ab764	1	0	\\x0000000100000000008000039c5f5a0d6445b71ddb72d62bbb85ed4916fdee6842c441f98db34675f755914aa539b25c4a6ee407e4116995f17f22f8459816e8cfb7c94dc1838b3bbe37ab3903efca8d0d8ef33dcf02c0c6ad4073ec70008bd9d7b031211d2829a5dfbd8af7320192703bb0acd599ad7c3c645e8d5c5d48184951176dd94b06965625050baf010001	\\xdc3afe70bf72625a56b239b2b2e8f45ef4855103fa6ed20e3530d915c6f22e4177a700394065a9634e058e2caf843721088c993ccbb52c31d702b304340a0407	1674400506000000	1675005306000000	1738077306000000	1832685306000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
330	\\x11b33aa28a5ac5ab451f20caa2db0e0b93be8499e615756d8ea9d54a61c731582f4e69b66c8657fa51cdf0cfe5c035c9167f8e08437d931e5492658914663c78	1	0	\\x000000010000000000800003b5da88414876b3bfd178f71b5ff94701f48f50d80ade4c44fc6a50a467951f20b942bcf5a083dc51636e73094987748a94af66dbe525e14315cecfe49bfb5363702a948070d9683d1b527a01893379f3697bd883b5e53dad87156655d39c700636259d9af772de46665c48d5e391c2527087b690ba05b7d4b4deb329fc647f01010001	\\x119a9ff9ed3f02e7d93506e791125b10db4efdf4dc5b570361685cdcc23991d0057cc720f779fead17dbf7027226ddd143412cb8e7ec482870aa8f28921b190b	1664124006000000	1664728806000000	1727800806000000	1822408806000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
331	\\x13034058a0a7c09d20c0e6c8f382b09036fe4ceb13e2d515ef1b0679e470bb10e09e653693175412b4d90a31fa8e2c8646e9cc887a408102ee9f1b58c9eabe91	1	0	\\x000000010000000000800003f0f09a5999f7d6e26cb276138344bfd23a1017e8053ff57afbb6d0f5177cade6165857b01524a3460560c56a6c2c0b613e4fe8c34ebafc2307765b59bf1d30cf9306c81cb7e2ca46f7eb6a58fe06d75d143e305f4b8d0c242a9e3bbb9ecf4708150d6dc064f9ce7a9a6db0cbf02f3d9fa56a762b561128510f71e0ca0cce3c3f010001	\\x0a86f4f5b14e96bc3bf04f0dc91bf209895e07b32065f11c1441e205ef89f86d98f518c325f7f6d9c9bc5c1827be497899ed6af2e76ba0877cd0b53b40bb0200	1667146506000000	1667751306000000	1730823306000000	1825431306000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
332	\\x1737b4c84babc9a8b27b1fd915d90508513b196dbe4557385e118d5e574aa83cf3598fe8901778457176379a3d556a27c87636811aa1ac50c7b738cf7adc7575	1	0	\\x000000010000000000800003c5aba1cd536fd0a0afd513980c0f4e88455d8069734a5828998852c5ff489c8c727872c5f49eeb41f7a0ee840f81fdfd345477d2ee32911ca49c806e03a64301427291260a73e6b34d4ca5c26b08a052377f764f300fcdd53f0331443dbb8889340203a7cda12bc11e4c61a750712de65d0604fbcfea647f9bcc3b4851332aef010001	\\x944651ec4fe4d0503004beded47fa3bb32190dc39b96b4c45a74ab0bc5f242400a18bd95f551555fdd69e8e01ada3aaaaa079da5effb5d1b5ae6b7beef6b5301	1665937506000000	1666542306000000	1729614306000000	1824222306000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
333	\\x20230ca7a5a4500c70870074df3d9cee6bc7e2f621be5cdf14d57d8a8c89a40c3f7e0c6dcf3634e5fb60db0f334dbc5799f9e55522fdbfe79d72fb9e328ee954	1	0	\\x000000010000000000800003c545d94ba17061c29cd590530bfbcdf9f9a88f02d54629e7c86cedc074cb5979b8bef1a18292b4d29fe652062799f9d9a8458b8af61464eb00dab353049f95b063a714d8a13cad73d41f04f304610ed63fc6ef3e7fa97069c2798e82e948815d1b0410ccaea7fa465834985864d80b1de29bae3c925963e5de589d652cbd9a4f010001	\\xcc1b5d608d2cc60de9bf7977f6c357e7a66276a6c279994ac7b3d504f45ff3c058733cb72c7f9d617f70c303fa22051d38edbfee1f3a60b58a03c6a1144fca03	1655056506000000	1655661306000000	1718733306000000	1813341306000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
334	\\x23cb499b4fa3ae794fa3f5135d27c8c23eded5277ab0585338e539f4d73e392e68357c848ee15d08d01644727962f089558e82d45b9ceb880ebab8ab0ba19453	1	0	\\x000000010000000000800003c47973ec7f94ec881327443891c4848abf1e47adcebd63931a2707c3b1fd2729c81411a3722851c53078e016f396aa4d4e764894c00b477a60f309f66ede42854a427c4aa2d4a82ce295b503c9179c4ec5e21c7cfacce81c9c11b551f52fa26b78fc8202f0711bef5f07590b03384afa139068db953299b27e8f47ea06b05c6d010001	\\x202f4a8e42a6cdae6d2b01821f8e23dca5081ddfa15fbbf6a131cbd056b0fadc381438250ea9b3b998bd635deadb09441a97216d7f44776d27f5719c51bdd603	1681050006000000	1681654806000000	1744726806000000	1839334806000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
335	\\x24effc99476823871f92f535f6b1c89bde0b390ed71ccd590abf56556f3a1aad1c463d49bae0cbde57b19b914c141a867dbfeddea76380fe6610e02403f385e4	1	0	\\x000000010000000000800003ca60cbe09347ec78f948e212e83c488bc3bee546b457814ad9ce7b4dc1c0732670b1fcd446aa8748621e3b2e03a78f1d7c6ca1cae41aece7cb0c069f9d8c62f493ee3dce993896c6f223ab43605709d4ff2ee55decb797f2580689639d508fb9f9b5d0a7016739cacf342ad3b3067633dc7da8755a2ce0d0563d99fc9a0e51b5010001	\\x85fc964e9138ee627b5bb81f5f7a5ec677ec0df4da11ef27680e31b7616a86c2dd3c393282c132cd838ec39ce48c9416ce24ed13efbc6202078fd992c544fa09	1670773506000000	1671378306000000	1734450306000000	1829058306000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
336	\\x29177033fc532f3f51c613a6e3da495a424f87017d29d8dab2554d404cf35a6408f6e21856682e6f579de31dfe1e65d3104bbb9ae844ea8dd1381a26b75c15d5	1	0	\\x000000010000000000800003ae4e9064c68f82748986031cba79fb281a924ce4c28ecd66f11441aa88425fdbf45fefae0bbd40f75ed330d900a168967f4bcbba402bf94294fc34925def3362a60024a961331213484414f7472f12f01001fc228989f4e6227df0e8e95f5b39d60d3a5fa3059e15c23efbb9b1994e5693693d37965b798af5ac098c94672b73010001	\\x39bdb50cc650b569303df8e218acf213e5796707a47287043c0770a61172b5f7684f03de20922e2f2dcdeb20eaec21537a434184479e3bde34add4ec8bfef701	1651429506000000	1652034306000000	1715106306000000	1809714306000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
337	\\x2c6f26244ae4ab65db97e528a2ac15e30bcb398276fd17f15833a2d26df0b9acb99ddc108cbc087019f10ae2fb2d584dd7ea616280c4e6dfea6428a6fe92a08a	1	0	\\x000000010000000000800003c59fc4622911a0e4b0d13e204f08784433233421320ca404af1f4df98c2b139034e4ca003ab8825d03e8acd3ccce91117644988122868212c809d3006d80c8d17cb4df7477965714f2e884c96ec11c9c611c617052670898bcb62106d44c3859dec5ed6b4f84ed409c69335fc4a1dbc5904558e6bacbf26e8c9ba0b92906d3a3010001	\\x9058e386d34805496ecee6a57c3e0928a6bc37ce256ee54c85c5a0c3d393ac0a7fbd265e94bd54aa553184d43fcd44697fbc3cd02c3895155a7906141310cd0e	1659892506000000	1660497306000000	1723569306000000	1818177306000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
338	\\x347be50f03a56300413daf76590474e72d430fc107b2194034b9970614ef927ffcb8389fa34adc3bd93dad73a2c3763a0cb3e05f25145dd1699dd407c8852926	1	0	\\x000000010000000000800003db240c009b55a95b4d2c9401376e2144ab69a6f7ef0e10f3dfa2fe5b8d752d6e6843ec4b3a02a66ac3658cdd6b77f56bd801fa29947c2a3f65fdc0aa26198c47c60637f21b03bfff56693abb6f0a2a648f8a0f63042079a1775a8150087e1b9422aec7a3945b89048497694cdc407f93fb4b34520c7afad8dd6cf709b65b8a4d010001	\\x352010c7da6f8becf2202856ca6627419cb4bc459c29a9eb6e861bc458ea6c555f0e1303cac1505040235574811158bd89c1ae6f6c2258fa9b9c8bc256ca7e04	1661101506000000	1661706306000000	1724778306000000	1819386306000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
339	\\x35835a2255d332ce23cccaf0f44c90809c96ab69aad41d6ad9bd317c8f4654b45a68391cc6aff31ed236e5152a6fad0f7486a08b29b220f400a475e9a49d0df1	1	0	\\x000000010000000000800003c07fe115660db8761cdacf07087261de6ac9430d0a479b213025d04313ede14d8b4180d11f888d77f590847dae6bda6d2ea48b55399d361578f5b69c1db6fca7174fe1f47874b58c186c6bd5265f003bd26ef1b7794c82045ee952d05d9e1c1134db8e4fbb1b766010968c3d4d434bd4fc0bd846ff015fd97e0ecdc380eef1eb010001	\\x230909cde68353ae0c322938ef84c2ac2914210a773058279241b9b8afdd43aac7efee4e8832912019d95b5d660acc0c85d2b56174c3aa682fc9a200f94f4205	1670169006000000	1670773806000000	1733845806000000	1828453806000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
340	\\x35af0736bb4546b039dd1ec64251b580224c8ea78f48d77bac15a4a65854f08045db1f38edc8ed25f6c95e2ba1a5a0c400bdeb8141d68b69524bafb49880df29	1	0	\\x000000010000000000800003ab14088092b32a084fa93686a5e4b81037e1fce71f913967e8231aa6c3703995501a0661138afad99cc6b89a7e74958cbaa9c26f71312e3ddc728f6a0e254639b0cc643ca9add9fc841a1316409c73307c5cf7c84ac6914583f338e149656d1826ab3c1f42302b84844e601fbcb0b1449f328fbab2d9f651ae1a9762a56c4843010001	\\x2ee91168def7e2cf014c2509d75062332a4c115c529cbeb0868a146d18ed01f07ca8bf7b0fdaec583d3bdc890a33840fccdb2a7a85594825b2228dbaeb26120f	1667751006000000	1668355806000000	1731427806000000	1826035806000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
341	\\x3517bbf68aad3ecaeba7225e28e3db2571cfedba8bc1faa3ae651a0c62cd25ba2da9717ef975e01a495826b5450fcf54f776523ae7f450044c98e45dce710618	1	0	\\x000000010000000000800003d661182744b44c0617f7360d36c4dd7533dab1206cbae31db25e37608bf4312a41a6aee990c094a7c4fdb32a0ab9becd110c6443a0d5e07479536c3e4ece04d51ace681a48cd7916a65a46e0f3693b0c6f02acdbe9156bac6daa57f20df0ff4aaf7e3d18653b2246d4078cbd784b5593313cae9b78efa09eccd21c660cfbb977010001	\\xf098876409f038196699d93e29b91f7ab2110923e738045d5075afc28e435b58e4f10b14ee2c041cc2d48341044388587815ba17116b1279efd9d1cfa7ba1a05	1655661006000000	1656265806000000	1719337806000000	1813945806000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
342	\\x39c7590d1a302c2e819d8f0f3b8f998455d999f6cbbdbf32dc242c92525a64125f91e65b9da45b4e0c107f61b9dcff999b1087406dd13e22a2302d1b97c5dca1	1	0	\\x000000010000000000800003b793460c6eb945e17958d685d47bfe82afcab2dbcd28a2cc8cd19b38a2c5524317925631395101bb2f9a7ffb148f5b6b1ecbbbd4bd2684a77c530afd6c100bb142dc2e12f8a5e0cc0321ebfd014a43fb2017c7865ac53d4e0b1bcf19c7be5916612fdc8f0c1fce881d8a5a5f8582936fae5b1b21413a621d061da6a177bca655010001	\\xc6fd5ea2d96b452c27093b0e62966da56e34b6f883fd5e2502e82413f7c8330b13f153a18cf8c061f5adb29b2bb114d4248bbaf3756f69563ff59d3167339805	1668355506000000	1668960306000000	1732032306000000	1826640306000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
343	\\x3d23ed539dcd6615c1cc972a59bb1ed126a9b9884c58712ce6aaa37da45c5a3396667b8449338778d5787b5e726e7bb4b4774170cdfe4ee96619450442e33d06	1	0	\\x000000010000000000800003db97bf65589b85e4f8047e9dc3ae3fe50ba937c150700236e3cdb4c78ced910149d1f423001203f2b3484914b250d6ed9d29af2044c4f4840c287352e0248f4940eeb30168372bc58dc039a2bf91ce3c78f420131d2b8b3c3a9a348b37b9a6b3df3ef5f5041aeddc042c7b66f80386b074acb34c57f1da88def42bf80d2feb2d010001	\\x6f74c35063a27800ab2bbcebe77cde97be2c9aa3841fda79ee884076058dcc5b20faf4e274263165c985567eb1a09cf4f8df534a8ad22e9c60665357b837db0f	1665937506000000	1666542306000000	1729614306000000	1824222306000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
344	\\x3d23c6b9db963409fd4a386781263ee516a541c61c685888cd7076e505d81026c87a8ebec6bda3f4ee7959d0ca0d10e670ff532f89900794b3f1ece362adb867	1	0	\\x000000010000000000800003d453ab6a6eeacc6de346b4d8aa2220d158c2431a1e908c183ecdb00074f941ad7552493e6f2f3be650c2a0a95e01a07738f17b387150dbeab7a1d63bc8268c23509a075e256bef243df97c4571c6d680555db3e75014235d771ec153fa29d2b24f17f0a1ee729f48dd2788c7f44359697278f9be4d21a555b025cb5c93a5ac0b010001	\\x0ff0f1c2c927d0efa8ebb330fade12eb63f1778bc949c6a164aac621b1ee6b05b5a20d0fd95c2c4e1c9e5be22173f7d3a9423c592e7d353d88e5b054a23b050d	1664124006000000	1664728806000000	1727800806000000	1822408806000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
345	\\x4057b19e345f2a120e8be198693123bfb50bbd0ff5a36a3c50d3da10cd71bc17254236000ad3f3097482141c6ff9eb1a6d97f066c59d06904107bdddd6853860	1	0	\\x000000010000000000800003b9f3f44bad948f0a2185cc96f5c2d1a2b41b4663e9345373a50da922cad966cbebe0c2b797709d131ab49a4085f8eb2d67d5811d2b9aaf8f49a0b393d9c4aaee92e52895864e44867219b67e4aaa581e417fbd7d89cb94e9e12494db84687572709c4a7d32e03011523dd45f60b3bb488a94a1987d0fe3815971cd31219e7fa5010001	\\x9834e5905a6fbb8aa7a86c5d628a14f5c06e04b4d086ce4347c5168eb6191fe47e54ec68053df3bdc31b380b52a8c0272a4dbb5a6539da8d57e0fc4436aa3907	1652034006000000	1652638806000000	1715710806000000	1810318806000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
346	\\x402367be0602da8f5f3ed21a783c87cab3ae6d09b5eb02643e3d6878b4d104ea84e9abfc1395cefa42d0c6b1d3188adbd0f5642a5c1213350924f642f8d23bdb	1	0	\\x000000010000000000800003cfac2163eaf3fafb664744c3c5c1a1f2f81cd91bf6cfd3d3b89778e64f53312d71a767473ca2ee04075124e27164c99e598eb3342de756c7024f0f9a591949d521cc65d95e1c057fd9e4db82a355207c85a1872c086f08b6986c63f6ef4d97ab2e61130ed59c4745dfa76b6c1fe68b72daf664e3fd21224ab4ab7a0f2feabdbb010001	\\x54a8f402bd720a3eb165f271ca2070b056fc639e9954c1c0eec2b985f3707347b38476144322752fd4110a1711ea5efccc58d2e3a051d4c05437c909ee4ee609	1671982506000000	1672587306000000	1735659306000000	1830267306000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
347	\\x45cb908cf05c433514e6f51f281cf08e0a0dc787f564ed687ae2ac50912a93e70fad09659c28bf544a9c1854a3ab3076a0b72be23d42fe7956ca1c185946034c	1	0	\\x000000010000000000800003de0daf8fb1a8c225eaa87d44a51e2185d6fa4032e35daaacd9b4531b7e46d78e2c4fba6410ca6f98248ba9fb31210b1b639ae6c2171404f545a168fdfeb3eebdb51cb0a7892c27152e4f5d477ed553c46cb81d513bf6386017b5a5b3d0923b33fb1d41996cb63cee4faa1ec04ce42dbe607862cb77e3eee4ea53642fef4a87fd010001	\\xfb31fa73e5744463833faa378e1cb8870b1eb262455ca45fe45da7f22002b89f98a4b00419f04e44ebdf2997a5f1337dbc59e3fce12238312f2ba8d7efaf4503	1669564506000000	1670169306000000	1733241306000000	1827849306000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
348	\\x48078f2608c36b403fb01448fb10df798fedb40eb8f3568e01644a129fb205753b0e86d5f60454b73750216153bba7653475ba4393038814e3bf191450dd276f	1	0	\\x000000010000000000800003d0ddade6c0c5cf6d3161eb2859041c313c16d08e7810ecda8b088ead037e37e85b34a3d36a740a54da3bab8c8bc99cac2d2f102841a063618852ceb2ffb8e76c034c99f0ac5ab8d76d674d30717a3ee711c06ed34b6923bb8bd84e0c0806de040414be7a1c2dfc2d1a7c85ff67b366d3258d15b3e27728a84c3181c85b552eaf010001	\\x1dea82a7d27cf9b47deefa0bbbf02e4d685ee961c26d0e33ffd1d7f4424849d99f779dbac2c9bae419fa27efa16cb2fd38bfabd4db5ccb7bec15fae5c9b95d00	1673796006000000	1674400806000000	1737472806000000	1832080806000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
349	\\x48df1a74ac33096156a32dfba98aebc76752afb929225348abcc96276f8e78ce2a16affa9561405ebe73e22d635cb9e731e815b75850a77260fba547945a9f23	1	0	\\x000000010000000000800003ad93bba0cf6e9f89beeba86f53aee43fd774c43c84e64d886b5205ddd2a53ba968bbd05d86c65e3e2d21b0631c6ec11f9e3ef1a6d9f8cba89d5ffe9efdc2a26ee668d6c54c5a2c931e1caa4dceecf1e552f94fdfbb82b70594b3b1b16f3bfea989ac53a88bf3211dc9afb936421085ccea8a1ff13315c43edc14bd7dd94339cd010001	\\xf17575a27a37b2ca6e401302246a5ceedd9def09e727a5da101f7d3c1c54c667aff31f9e61871cd324dc2c017311aaf32867707ed25764661fc30d6338841206	1666542006000000	1667146806000000	1730218806000000	1824826806000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
350	\\x4927114bf65d17a8b12a976828e88fd3b2e74c88f316b0d3f5a18b7edab8150121aaea2117a5d294b6c836c96093d40d11ae0e055b6999f92555b9ad2c415727	1	0	\\x000000010000000000800003c11e80efa0f9eb35fcaf0143b0af1245f0ccae757c6e9db0f17c43804b7a84fd93d1328cd185c793e47abb63f322d6d37a5fe23773cfdaf11aa825ac9f2ed2ebc5647a166e7c82f6c80420ada8ae9f77391719a181ab9e41ead47afbb3842aa54f25e82ff5bd1a3abd12320968dcb915644238e0c8720608b9d03cf3f02d74a7010001	\\x170a2a99a49778d7390b56544bea67d07233273caf550ae47fee3631926a6d3754724e4c8bcd68e4538dde576fb122eb0f0ef5b645d0ccf7efcac1054153600f	1661706006000000	1662310806000000	1725382806000000	1819990806000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
351	\\x4a9bc0e097e0666a313b645cc7192121f33b548a253911fdd8ba409db8c00b6e8a1c84d3b34ec82c5c436991433cae294ef273e3cf4ca869e7e052856a045661	1	0	\\x000000010000000000800003d29467b141b95cc50546cfaefc4dd49345eebabc1bc182aef668bda7162b907a0d1b6e1907f55f20bf7f1748e8ab41ead035ed5cc3c79ba6c911a61bc73cacac3ae3d3f95dba43bb0c34612f12b16af6cf1650b52487046e7eecf8738ba9c233cfb81bbe02bd6ef59e84b3a2a32cc9fa42f0a5be727ec0ade79514013f66d5bb010001	\\x0a71aec9ccddafbc72ec994df788ef1db0227534720bc9e23acb2115c755543b7bd3585b705542fe3e41541381825274499813db22c277ac0c96669797ad9603	1678027506000000	1678632306000000	1741704306000000	1836312306000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
352	\\x4bafb8b99094def1e5afc5f2408bdc722b82f3a2647c640643c3a4775a071357e3fb2d3ee22703850ea8a656cba8cf9a9231e695046fa7f08c32e8abbe6d328a	1	0	\\x000000010000000000800003bc4d6d0ca2f8e539db161d94489a285a45ef2a50d83fb52f8acf7071895b2f818d4ed89cd60ee04899e5649909460cc8ce9e501babe80f4fb20ba4c9b629e2a13f6ec272c39c70aacde8fe30bcfbf169994baa6d7d897e03c8bc0a5e098cf249b619db74ea725ed71242d59cc35a98840b76a24d9eae94d26d147226f01bac29010001	\\xcdf4534793459b393849b896ded41fb6d848fb3fd2f1d02911cc2ed9f6f9cafc975a267b59a16dedee370837d5bc4f2f88471c17185521ad47ba4cb5c9e8c20c	1651429506000000	1652034306000000	1715106306000000	1809714306000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
353	\\x4c6b7526e756cdb02f915b3b9cbb15819c773a2e3eaeff8328b5a3fd9a9145df0e13162a542f3407a47b8096f169b49d25fc956f081e4453668fd55d21a3d568	1	0	\\x000000010000000000800003b1e9978ee3c8e7f4d0cb005d3e2787b192cd5332e6b39513b8a64676df09db1cc7735f1cb854afd55fcf13fe0966b1b9549977c45fb3229849ab86f12a5485a0c0896089b43b9e20a07183d1030688c063b19a2f30e54a591ecefaa6ebc8a2bcda97e897c12729d11896da1d7a0d69530a2d02a7838259a752ba7d0498bf07f7010001	\\xe549f076d11010d3a0131a8ac3f465bf33b3b7082c4c2c13fdbd16ac51816f50b08680954301632387dcb1c532a8b85d9a7f916df7e7bff30a33c000a4d2ad0c	1674400506000000	1675005306000000	1738077306000000	1832685306000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
354	\\x4c7b1c800971a32fa5047b4f27b285c7bdd313c806e606f7a4a64076bbd29200bea5b26eb4b33e61488f9c444388a530409f2ec51e5aa650dd3bf080e05d7774	1	0	\\x000000010000000000800003ea861202768fb45c57e75a25e97addd9dfd94d759e4a0353074989eeaf67ac52395984fa816e7289ea9e772a8bb193711afd2ae7929304806c9f045be09bb28812c9e7edb5f4ad64fe5512e724ca4901993d56f45dd055dd3338581e4ff42439a5155b91c75ee2cc3e5de6fd62095d712e0ccf62935ce40d17459a80e310e5f3010001	\\xec09dbad56208b117bd5fde0c7dfd99f35fdb1846fd13a577941f628c17ee2046989e79e54982947bb183f00084ed3fbbaa02061a6b7465a95f13b7423961500	1665937506000000	1666542306000000	1729614306000000	1824222306000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
355	\\x4ecbbcbfb7504edcbf8dba37032ca42aa89bcfe034a6c82a24f4c72d430a9804651c04a05105988bb4af3c3b0902fbd8f96e78f7b631371e17b66b9b5bc53a1d	1	0	\\x0000000100000000008000039dac4fea1184bf4d0487f5f82a3e9158867e15761db752538a10af439f2a9e884633ea90a3880f1472705c99997afad121cf1c966b4e07d7d1585e2e49d14d076cc4809a4b27cb794b535c05113675cd0a21fb91793a5344a3c3a48f711802d27cdcc98beb0a5b63cff956edaae9dd24e55083033ca94c783b9893d86b5fafbd010001	\\xb5596178a4bcbb00db8a0e089ba1bf2896ae0be1aa0ecf039ae8bc5d24a776866e6fca40403d4fb219ec9074a5f2f69d27973daa46173d5441a3a10e56299002	1682259006000000	1682863806000000	1745935806000000	1840543806000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
356	\\x51e7034f0ddedb6855bb246e6a9dd1a81d0acd2013b62d2802e7aed1719dc4d52ea22ee71b6f18a1f2f044e74adcc21161d4391bdea225bfcb6c32893fb9b50c	1	0	\\x000000010000000000800003ba07a8cbd4b5cb6eff2c16e1cadd7adabd5ad43ffa4d5482df9aac0426a495d0391fdd323c3007c0d4bb0d8447ba46cc76964fc8ba86e62be91d2e66c693ce1dccd44924cf0790df11d1c592945f1b2a63de40cc1148a25f76aa78b8e0a0b85e64b3c30dda2d4c0942ef14d1363ededf6f69f7c77be23139cac9a3b36dcc5eeb010001	\\xd1111eec97adc96380ed36dfa1beba39e93a1cb8fe99a33779cbbeb20ddc26e9d672c508aa1d02423c7658eed5174ec89d57a5a3f97403bd13e704f25b71e10a	1655056506000000	1655661306000000	1718733306000000	1813341306000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
357	\\x538399575eebe216a112fd94c16eba1b3de73e31ecc11b73d0ec04582b3a2f486b3ee231d755c0a920ba79830d3dd8f08ddcac2802127042afbaf9a2c462e599	1	0	\\x000000010000000000800003c41c99cea82292446a4ed721be899d60cd0477e3bba7465aca8b4354ed58d087ceffed0a4648ae46924a288fc9b09fe9ce64edf6b31bacade14b8100e13c56403d877f9281f8799c170c090e0da0b6414310e634caf2551eedebca35259dade599a05175c1e9c2d2078b44f15fcc1169bc87ba5ac9f2f1ce34b47c22a379d82f010001	\\x06943b0e17286db3999eda62c151db856c1b8d56e4b2a174be7f7e569d6da622de7f261599809c30ef58dde1c115d61a9f7a1fbe7fd5a60583933cba3e6ad608	1681654506000000	1682259306000000	1745331306000000	1839939306000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
358	\\x53e7b61d9f1ca099a2b9733ddf4e2274ec58f85b13cb0c19ed0f73c0e59523cf5dd8f28c84671104d7247ccb97b396ed8f460f4de2a2ac1d78c3a20da07adc14	1	0	\\x000000010000000000800003b90a2b7112a820cbb41a6b438a625390a3046402f25f2a1e3656d1594de47d0036d580a471510d19b52ba1617ef734f04273af26693725163e827bd1f6eaf3b683cddeae5dc613761fe925a9a75e43e5938b90ea0cbf928f576d00d56acec93113ca2296a40a6c67b4542396ed6528301a2cd845f7f9682b50bf4201b918ef9b010001	\\xb60651e62fceb6c50b6db5c2d782238f0e935c173dd0a7ee7267bbbf3952f4e74af2483b58f3021b2a5bb36c2898016df2ce64d48f68acf40bdb7701d3ff5f06	1671378006000000	1671982806000000	1735054806000000	1829662806000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
359	\\x5cab4815f6cdc1b38470038ad6164a19a3043e961a576330d6501a53f452e7cde1ad1f9bd2e8595787aa9fe91ad592f3e53887c2c6d09ab3d9a6a3afe622e66e	1	0	\\x0000000100000000008000039c7e2a6e9185e27f77707013fac469dc75e355064a67186077335ceb79eb78ce03385405db5b52b6e2331cb135f6b386308de164194aeabc05686de60e6af1510538e99e8d37f7273f31e25adaedcb949e3221b9760a6d375bad761c6d97f11ebf66cff923001edb2609f82c18d503fbce6b2166809ad45151bab0b1820b10f7010001	\\x16dbf0195c3dcf21c47d45e0de3e2bab6844e9b5417faea9e1d35f5483762e49c5cad7b958cacb6642c42c061cb020e58d984dab3f3db19df6f3c239e41cdb02	1657474506000000	1658079306000000	1721151306000000	1815759306000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
360	\\x5c97802bbaa67d76ddfdcd1a9b4f8d16332ef4dcc790dff1b8004f5f0b49639970cada3b4ebef3f8cfb8542904972ee48f0fb8df52a9677fdb0606d253dd80f4	1	0	\\x000000010000000000800003aab25ba2e6eaef39eeb8eb4167baf15fc5bfa8fd01fc9974416a348e5015b4196342bfdb0358c97a031ec50119158e2619a7d3ea8c1623220a789214f12cbfe96da9a2fc564c1dd997e273917df79757fadaf5d0a4dc6d392ac5d1db257d4f0d8f89408bc1a4910f6b996eb4f9db3864f3031176529697762610b3fcf4331ecb010001	\\x6905e23da94ef9da58c342b38cc2013354897d7dac590915789ea2f6a779f2634051637ed208d54ab67701a53f35f27ce214dc981c6a2702c76ee303e2fec807	1670773506000000	1671378306000000	1734450306000000	1829058306000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
361	\\x5fb3a3dc2ad6f26c97c249db669b774e401acb12e16f7af860d6958c5fe7050bdce1b47a2c6bb713e5691fb31157a99d946cac931feaca57ca41fed5369ed9f3	1	0	\\x000000010000000000800003caef107d4024c6c627a2e727987b9df3d159aa82b7b35199b8f4d60a14c61684b9251695764ddc380cd2b353879bdcf14895d2d88b559b68917cec359caa57d79ca3b1c6a20e1802cbd65d91afd57600dcbf210332ca5ac13a96084268f035bde00a476c0c4789a0e8c3f969b6675a3c5a2af649723d8a0211f7449f4daa28dd010001	\\x864f1021c55b42e1542b18955bebc77d467452cce32ef3ad0c4919fdf6da9c43fa2d9cb300d205c7b8fee76566346e377052a722e960e7a79b5f5310a9408909	1673191506000000	1673796306000000	1736868306000000	1831476306000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
362	\\x61d384f1d6f426678e1dc23f35b590a0abd3e4c27dd93f0df390be667f19d2d1d14fd46846ce3faae0a23331e76a771458316326a9e72687a87a7f813c7b8d59	1	0	\\x000000010000000000800003d5e1b48efc09b8c816eb757e3a38b4534ab5c52875fc31b060544ceaf254834bd60d0b3641c1b91fe251230ca25bd840304f9293f9b795f7f06070abe577f0d3427f4844d03f6fea88ee1da3717e0ea0c97495689278b07c01c6208d0bb5eb74037c8e99468031b6e8b00e2daf4319bbfae0fe8d4e29989e65e46e1919fa3f89010001	\\xd92f99e4880e4d55115370d9b1964549e36e4aba1c49596a4198cc5eff04dac84dd743ae06a9243dbd83e0d16d19556d68a71a6781347a8dcc0514df3de77106	1660497006000000	1661101806000000	1724173806000000	1818781806000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
363	\\x6273726ad79bbddd1aba69702ebe091a4101f14a6308e27bde644a33c26c7e4bfef966f8c717eead5c15cf8f06d51441129c8d93617799fc498798bbe99f751f	1	0	\\x000000010000000000800003aae7d27d470cc13f168c4765bf65474b6f5d3809944d347737f88e398a405b5271f54c64fe176f94c83d1ff242f86c6aadc87c323690a831c609a7c8ee5e7b29fd3090b89c8b4f907d1b7e3032fdf1d4af7a041e3172a14c9327d1c01f1ebfb9611975be25533d2133f07eceb831f84010e442ef12deef515e085b2622204559010001	\\x86f674612d16701b7b78a8f8bf5c0c78f145298f83d86a7f5abde6193d6bf68bdcd6ad503e03c9892cd35a33fe878d0eacc08147eaacc7a50666caeb9e948a0f	1676818506000000	1677423306000000	1740495306000000	1835103306000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
364	\\x6d2331a2c1ffed17d4334b3dbd4e23625be1455afa2c748634b5143201012ca10ed4fbcd0eedb75fa7eca4172a92fa0550d725426eb685eed49248d5104550ab	1	0	\\x000000010000000000800003c4a3657978e5e6a49b992695c7e40c40fd2912da8bb23cb469c79ca69547f00824e5dc2bab9ae39805f2d0f00c198e8f8441826ef91748d62d48ada3a59d2c57bd9b06a7d3d5070c62ad1fd584ec648bd7665f3cb5322c737c52f840b95fb09715b254531a6dae4f925615de652dc148bef2b39a11e0535f887956257f22eff1010001	\\xdb949f8e298f2eb55b0eb0bb98129de25ef8c619a4cd6833c43c2fa307a3e00031c5fe0a4e9b05f4474ddcddd1e9e67ebc6b43705cf9e829fd8bdf1f532e9c01	1656870006000000	1657474806000000	1720546806000000	1815154806000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
365	\\x75576d23784998227dd2f6c2b3afd587f0dd983edc9118fa8c74fe8561dcddbd1240dea1a64a4a8f235859b4f39794c98ca452b5d841506f9306086141c4012f	1	0	\\x000000010000000000800003ed82ba57ca4069500a81ecd91b6b50a7b9c60893cd6e84d4f9b5211fe6f06edae0d0609fb087d8eec8f2579268ce71ad6ce38885f1bcd0d16e281d59fe3b899d8efc94c9274a40de8d9c368360d65069aaf9f9323547154be662ab3c26616f43403ed404c1b1ea9c969362eb32775ad0ff142b7c05f87cb3fe8ecc1076068be7010001	\\x6e4cc46450389211410a49a5b9606c5dcdac3969b139bfcfce6a8d6d854ccf21b1af06606077aaf6062db3e34e9a94b16fde28e40bf368f8bacad71e177db60e	1675609506000000	1676214306000000	1739286306000000	1833894306000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
366	\\x76039e125f99134259742d4aa9e5474fb98992f59f14f1616238b2ea3ffb694025ae439e7bf624ea4139b430a9083eab8ec02a2bcaf427b1fb573ee420d88d17	1	0	\\x00000001000000000080000398569879a41588dbb459f2b2a3a4af7acf06fdf4a7b4d1991d6523c35f9f87ca7e774d48ba76234ff8668d894756787ef5e82de82d75f85313c8859f0fd48f070e3ac9ceeb800d0c2e07f67ad469c3d3e6f31bdcf60ed22014de73a106de8082d2e3152f5b3442137616f35d9c8f83fe7069fb4043381c8e2e89d83d139d3561010001	\\x95acc49d5128818b14e8efb17e1941ee9fde32cb6edfe9ef7b17ff77c045efa11d4cf72d9d3239cbc8e785c6a91b98980c1ce8b25c7904808e33de9b8a7f5e0b	1681050006000000	1681654806000000	1744726806000000	1839334806000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
367	\\x7913036d31a33cc6de2242194bd2a9d8034b72d3bf6d54a2c1f136f79ce6fa7e7f31f9d91a64509025b1e0f654b52381331ccf85a4883f047bb6c5b06ab4e298	1	0	\\x000000010000000000800003ba1ca51813de1711325da71b425354355c3dce3568ee79050c91b96a0091c521987c3702b91fb3ad2de58b35bc3f0bf331bbfcc44d59aa5003f08986ed8e752b82d3e0c9d64c510c49f9f6b8266de28e519cbe1c616e90bdf524716b48acf011afe196b98cc2de8189b40eea9f0c5ee19ea7f1bd7c1f179672ef7146883d388f010001	\\x6ac5e2f1f44418f341a961bd187e405b93f1929d7d0995eff12507bdcdb92fa93a9fcaaad8072300911f5e69e290229b3daa99ef424cd482ebe0d44f5141d706	1680445506000000	1681050306000000	1744122306000000	1838730306000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
368	\\x7c7bb451db445a395d3b0dcbfc5be2a958b44c3a14d47c48c4fe99a51a34f68d3990ba0c4f8142dc21ce21c22d0e00c0709abc01dc80b545ffec30b252043743	1	0	\\x000000010000000000800003d18f7d438c4b18db856295af9a144787f6c114648e46bad0a7340da853cfacfc26f9337fe8aa6a6d698b943dc52065305ab63e4def67c80ab3390c4443aeccc11bba31d333de112bb63aa9314215271f4ab7d07b5867c9a116b372e45394ee9ce9a4ed0c7fe480c874b6c32ad8647ca208a9fc39c4e1c944cb5c30b4719b8d6b010001	\\x8d3b54eb8d2f5bc5f3edd278f9773b218438897ce4522c2a5e56e7b8331c1c58ed10bac2d9b8419f44f76516bca04f56c62a5c5a970af3504a5146223485aa00	1667751006000000	1668355806000000	1731427806000000	1826035806000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
369	\\x7c030ccd967420f7b2fed9a0b39ab6945aacaaaa92268687359cc18210aa074af3e6ba754965d1689d867524bf051418861735370e4a4201edca660eba68f529	1	0	\\x0000000100000000008000039a46eec129b8d35b5e51b41c4d09ba7564599964627dd37780865510100607d88568852289f75927010bd068c7e359750b67db487117a93be3bad7c1998b10387132a909d1cb8a72b6b522e3f58cd37230ce00678ffc83d38162b9466ac0e588e5e7466023a8976fe1e3d596abb3d42459a67405946f7cb75fd85bfd23fb782b010001	\\x2edf7a9e04c41cfb7a075c8099a7341128f1d53ccf2f32bb41c86d8767a50f0b313dcfa9470a610024a38f254696799ab993aa1216096b83c4031c7d153be20e	1670169006000000	1670773806000000	1733845806000000	1828453806000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
370	\\x80c7924a13f9ee093651f10511f950fcbfc5b4ebfcf8d5a835fe419adda8bde442f30169ddaa4becb3aea8faae2ee7987e1d70de475c96ffa466e649ad7902e6	1	0	\\x000000010000000000800003b7ac532ef1032ef6d1022e18df7892c7309c01a680e6f4a82c6998f85d6a23b69e006a949e5cf2bdbcbc764af03be74cd4390625d3764c38f22afdd3165159e4240120c66b29b419f7b48d357a20a39c4fc7d0d3193faf505ccd63a683adecaedd1f45bce36641505ded03f2f21a7c68d7929022a147417711d804145c1b3421010001	\\x2b8b9ad35bf22dc71ea890a472401543de5ede2591af5a5087f511fc6dde72b38470fd3770cf2c0bc89b0a832a7699f4e5117ed5d52d5c52849695cbf439790a	1672587006000000	1673191806000000	1736263806000000	1830871806000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
371	\\x81b3b7b1c725e7c5ee77af5818905f16518524427c87f540b8ce89d592e473a59fbf13d2dd58667b959e65ea331ad5104bc3e26c5fa08467e53b4c92977ec23d	1	0	\\x000000010000000000800003c00f6c378c093c1c14798ae98f0aac31da5b3dacfae42a280881345984fd3c305b7f1e3c437377019e569b7e99dbd79df617bd95afb820e0d86e6786dea2b0e4619e456632c98ba7be811eb941d0c5f66c22dd1c90155f1781f5c2a832240ae8be1206d57ade33340dbfb0f3786e7c7351a0edc8ab2cb0f6113b7da122c0e32b010001	\\x422211523afc0fc91556ffdec308f66d5dd8554e9ee1ad88fd28b77580c837669405caacd5e9df2bad04a52727d4eabec50fb0e5837a469668bb102e9114f90b	1666542006000000	1667146806000000	1730218806000000	1824826806000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
372	\\x841feeb7dea1b2dae0a85f9fb9738cc71db39eeba6a5fd8d4f3d9013f20cbf1745b2174e184f2fa4eb47c628111bae79bca34270fe274b6e1d258523f90ebf15	1	0	\\x000000010000000000800003c2bbe370a3b4b9c814efbcbafcbc13395c9fd6bf51acbb14ea532167314b419f65d96f3e0639fb12faee9f12a93220a1bb7242790ccd51b940f1c1332549fc1009e1ad0798a361ff115cfee8f1bd3544c4866275de9dd8823d07141cb76eb4a3f5c5fe3081fe53a4eb5ab24933633d7b6024f189f54e25d0c5334c4bc44a046b010001	\\x4b7feabc94e7a82b014b4e404bbf5f2251874517e905e27b56516c1e447c59430bf71f94343269edf06e6d98a89b4e6bad15b651db8839522fbe6c2165406309	1658079006000000	1658683806000000	1721755806000000	1816363806000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
373	\\x87c35b685635f88a65564534cdeae4707bb7936fb3d5785489faa9329853cf9ddca044d15f6b17fe3851dde04e1ab1a6db13522f722f128c311f23fa7ced5dd7	1	0	\\x000000010000000000800003bc043dcaac828a24c472c588d29f72d50dd32f988a46d106ac115de3a9800269607f1913133f2ae232b6a69966d076c36ad6e97e51c083293de7a4c56738503d83425d0607d29625d6bd58325537341297b65c5575b25a011b692f5d2e88c5c8bfc7e6c2736cc1b4fb9281d77e96ae5b2ec45143372924179b7d586ee8570229010001	\\x5604e52295e7ad755223e4a07297b327d5bc2a4a3e39c639116a3725de9e8ae9642c2bf6615eb8b700471dd4afc5737002c998df7bddb783404258ed7b0c0e04	1667146506000000	1667751306000000	1730823306000000	1825431306000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
374	\\x8c133605e69d1a5a39177f0e2d6af67d707e88497fb79923a58d7a3def453032ef7313f69f0e63afe00c06c992b60ad30b2b1fb4b2468a27bde57c9d811a0216	1	0	\\x000000010000000000800003d6e6e4cfeb67a5746f8937bddffc4afd274907b97ad4f58522980c8ffffe9305ae40ee9b7ac2497e66e6e667d32ea41fb05fb08f3c8c8b92d6fe10c47b3c51beb5a118d5ffbafcd3a0f0318ce4fb8021c0df29b73f7d612eeb82b6570d604f0220e9dad7b2713ea9d4b38d57b87ab98a8707993d5c96de2fbed6dd472288df47010001	\\xbdd246ac5678b80733be2311f7d6c091aa4d7982d1b6fcff3f25d2dcac47340ca899f14524bc6efc1a814e4af79826154ec53261b7a29bfc93d47b1d0e112f0a	1657474506000000	1658079306000000	1721151306000000	1815759306000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
375	\\x94cbada99d1d4fa94b35ce1bea4e5b880fee7299d059882534907e3baa1fdabe0040f803343764d34566cc040bd98250d34e40db024330888738efdf7a4779b7	1	0	\\x000000010000000000800003b87d399cbd239dff55595cf45661d41a3957ac77c30a96a996e118f879255eac6236e84d7367454f72687b69f0ca9aa1e6a9a9f3cbd28569e9e3024d7bd9c353e9cf0a233ab947e37b99f74f3e1dabb87272344b337649e132223825e31988bf7cc1a3587d0fe750e84da88b0a41d5ba2143e13441042f928baf9f7264911bf7010001	\\xcd984b6c9831739e7c2594bf6b8a0e4a05aea2adc522ba7c67299d478aa372a4c92f9b7e00727459282eade19877258b6734ec26a183d23b708aa48a4d19460b	1662310506000000	1662915306000000	1725987306000000	1820595306000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
376	\\x9933d62c0e048a4f958d9cba75bc3b0882cf90113eb60defb68b7829ac9aaa1b0c8e71de596c5cc15a2e9fc9aa32360e189efc487439e84e78584eca0ca55d45	1	0	\\x000000010000000000800003c32b27d5074299be1dd57ae229b5423af18756f8c23cf4ff5c3f4d63a5eda70ded44b406883f99c05879510fc810fa67795ba0a232daac7e8eec1f599584096ff0e41688db502aacd6433977a79462b274180dcc3c465b50b5ae98a394e4ca2803b8f8e6d5f87e707aceec274e9fb76d2965c6d29b4e39aca42445db405520cb010001	\\x04a902768eff511fe7bc04f5cbfc0ef89c06643dfb15152691c3c385ee46fa03a444a6feef693f6450d95714059701e0e86e8d1ab6bf679d329e0945cfb9b10c	1675005006000000	1675609806000000	1738681806000000	1833289806000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
377	\\x9a03521eebfa9f888fd83e02d440d1544fdaddfd5d4f84e5bef3a02678cf5912de87551448b725cb51c49ef6821054cfb18be337daa591346b89a713e66b0597	1	0	\\x000000010000000000800003e0881d37f5aff532ac5db3abd17ebbf175c4e1ca34dc1fe30e3d71f5836b68c1ef37cb4ea6434823ee0d0151770f4552b1047372a298a332432a15d3e3227faab964cd7562a46ec416aef965fc492190edd9dc972f9d2718b51781e09aaa0da57261a7ac01d60ecd4b94e3ce90a1346f4ef56a9863703c9e2774216b99aeea27010001	\\x76a3c943f34374140fd08f5809fd15657b8c807a1a785a7d6ae28e167fdec5e1cd9d5bf24ff263580d8dc04edd1040112c7688c561f4760664da40d5c77cef07	1669564506000000	1670169306000000	1733241306000000	1827849306000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
378	\\x9d0b9af6f5ff6846e69a2564ab9657cccb3fa7abe6c65bfa8ee2a560449d7305bfdcac9d993ad81750cd6c7199d1023d217a7c0d96ec8e124d03be23edfd445d	1	0	\\x000000010000000000800003c1f88d0b71b5b20285b79c90fe0be09a740673ddfae00c08386019c9a86deeb2a24889253167e14393903dbe5cd1d37e6a56ab23832b32bbcedd9cf6f19df0fb2410e244db320a134489eea44750ae874b92bb9ab7e9745084001341924e3f8f764f5addce88d8fba3bd8e83c6ffb052e03a22702ba0bb62d3dbf716a235a9df010001	\\xd6db4b4a86f9550e7de48eeb0dfddf1c47965159c8d2220fc8ebf51438b40cb2afdd74a63a050d54d389a1192a9566b9842c6583291bafcbff77514eefacf106	1652034006000000	1652638806000000	1715710806000000	1810318806000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
379	\\xa1276f29a70396f5729edb948fa0d4edb37c0508132f9212bc69723e6f80a20a8f028a898e2ec8d9ab1093f3c0d07b262ac22d6962a5840740eee1f5014303e2	1	0	\\x000000010000000000800003de3118f56d37d540a185507b0abde7c531011e59fc39d10c33dcc132a7df53ef015bbb3eff7ddda8f315550823ca1dbcc74304d5470f4e38b2c14578d74336cda65f0ad23241f77b3f4267e58996396cf4cdda0e74aa12922e57a04497da9aa20fd98ea1b3d2023a820b4cee494d4c6e48b8ef0bd2641523797135b9c698bacf010001	\\xb8728f62fc8b9cf8691322f03bb9efc9e654db8f82d82b7f35a33051c4f4c42fc50b97cdeec262b0d646b70735958666a2d36a56650711bb751bd7530c6c4901	1652034006000000	1652638806000000	1715710806000000	1810318806000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
380	\\xa5c37b745bf10d3caf237707b2acdbe234ab1458f9d5731f779c4937dad8ae346907affb9fb9a0f982fdbfb0a76c08cace10c67a729f1939dffe7d516ca770b7	1	0	\\x000000010000000000800003d29be438d45448b297ad0206f1cd2686a898c55379b33b76fa55b8a28b89d705d837365b737f5ab7c363a36ab384529f5c583f05310b1ba80101dea0e9aa2b4413d59f4a59f4d097b15d6f6cc495f5154bd7872f5a3b00bbef1497c6b1f84275397f2ac6c93c098cb5db2250e6f759ff500539927a2049c085a6e8fe85027bb1010001	\\x0db1cd89c060002b43c419232e914281fba689a7e2d6d6b8e3e82ae59f46aba62442498f885f408a65cd949b82261bafd15e262ef50bc7e3e89baeeb591a7e0e	1681654506000000	1682259306000000	1745331306000000	1839939306000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
381	\\xa6e7a2b270a3c1cfdb400832062330a1a0293549a53e751069ff67838f3a3c77eb35f65154b76a7efbcf511c7e467ce180b548ab982bd89cdaca3a315f1693b4	1	0	\\x000000010000000000800003e0873d5c943bd704ac2b5f91d97c27af678e74176a5ea163a8319297f51cbb80360708eded3c7c05d3b184d47dca90f8ddd01329a5507458c4e91fc873710ebf992188f1f28fb27aaba1b0241a50d73567807c195f04073897d18eeae08f3619d216c7c1a5406eaf1c6264bf23c4080af40b6f17ade4208901a127316a59a5fb010001	\\x86cad16e54fd033a8715e6a8136bfb66d84c3e3c5e87ab66765787c579b7514c9fd8388e36269da8166c2cff0761dcc88655b691a367bf1101c5395d69a1e900	1682259006000000	1682863806000000	1745935806000000	1840543806000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
382	\\xa9af842fa1f3e43b8dbeac482f7d42ee098be1a43a83d679c73cac2a194a03fedd5633e68ae32575b4467a4b0cd5cd9b58db2acc1f8635ddd1f8237998005071	1	0	\\x000000010000000000800003cc41d095dc06f6256a768751f8009b2b3a3d86790512c6330b717911978471700bd1432a3031b3c67cb12425f5ca3ee42914023e1ccdd67575b50406356f4264c5a10c15ec0280c50dfa8dd22ca6d9a4828a89e8bf27a125f2f433250bf5f3fb35d3077f8c85c5288a20d23cbd3a0e89c82b32ab8a5a9e8aa319b4322971a74d010001	\\x4230803c18e8a7758f56f311bd37c332bb5422c9e422d6f2c6e1ecd4c8891fbf4ab68a7eb446ca9904b9bb6210c8446848f02d330df6bacf9f7a2b9f2dc98008	1675609506000000	1676214306000000	1739286306000000	1833894306000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
383	\\xabdb80e08ed3fb6426d0cc8b922b466ad4697e8df3eea762d503b4102c467682d672068aef2617e811e0b94c4c9a57b6f844013f774cebf56d4df6eaa2f336d5	1	0	\\x000000010000000000800003c577c06de259e0feb9c4d6b0194894154cb07cf93dbb6689cda52bba77e7056929f364a877de9226d898791c9cd5a7bb6c9413ce69613517647d0599d6937bf457a5cd3324daa631d1d08bd7874a5fb8dea2688f41ad32509a95e62b45886f6fb6e59360e5fef150c453b5947e537eeea80931c9c69ef1c4db67f9f67a68f155010001	\\xa5fa326dddb519d5b8635b55baa008262247809d5439374cf5ffeefbbb7caabde14a9e6b333abcf1576afc7f971ab31de1ed3563e676c1162fef8742cbe5b40a	1675609506000000	1676214306000000	1739286306000000	1833894306000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
384	\\xae27a69766bc9670985df3f96f0651adc0d409c9c8fabc1e5ae4f903e9e1fc6c6e3568a789957f67a5f1911623b0bdd1bb48b41609fa7fe834304bf1a28c232b	1	0	\\x000000010000000000800003aa2ea25667d9f506a208c7ecf638f20d6ed7a2bdbbce4ddf70c52fafff46042f9e98ddaa4f77e9a1c925a5ce6cc5025481a6d46a6cbfd4ca39b894a6d00b139cb40282e25ad22051f8c22414126756563a92e8199bba0843d871cbaae5c93a855a169f55b456d6cbff92cae330133eee1aa28e2d3d41250c2c610d25ba4f6891010001	\\xc05d4f0c97a8d8759b7accee89c5a92bde72f43c29e4a48b0bc3d9a66e78de3a6bafa016adf2ff32e8fd79f50d02740ccb7dd03c0239dd61e7fb68ce26daf302	1650825006000000	1651429806000000	1714501806000000	1809109806000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
385	\\xafa34ef4d41862e41d794efe1f238839746cd63df1bb89f7d01c7f93ed77e5f122ac5a4612f1627e410cebe011bc6fe6cb955244049fd819ae0f69a30cb07d49	1	0	\\x000000010000000000800003b3201cd9a46776c2fee63206cbeb485cf8d4aaeb3b737e475d8dc819f2cf57d781172ebcbc67dc99098f7eb4c36abf67d13fbc1fc00a40c13aac18e0412181d6b4a6c5a835687c9e537e3a9d1ab7df9b05fcd2e462f843866022d6acaf22859a280ecda5d6fd44e9d9f1884ab6374dc86ba60ab0429ccfeeb70075419012961d010001	\\x73d0fed8763066428b1253ccea171b07f9fe13c07346e739684b23fb506c7b5e49d58346e9c23658bdafbbfe1100f97ccdd4027b6dbe6f32c7bbd22ce059fd0e	1678632006000000	1679236806000000	1742308806000000	1836916806000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
386	\\xb31b7e8bf0474ef05d21869856a86ab744071c77bbfab912ca5e25930bf89c426882c5e9a88df53ab24412b89f63698b787bc724fc13c757c1633c7ea678d112	1	0	\\x000000010000000000800003ada70bfcb6f5cf21a4ec51d7823a96457ca6c65b90de1fbe269654286714267abebfbf6955acb3dacdbc3bbd474ac2da7ec0639a770bc556f868ad93f3a17d6766d6dae75a4bbe1b9aebfbaa9c0cff075f5fccdc51bad6fdfe91baeff3a460f31da78714276ddd76a3a51da637cb6587fd40f524fee468777f58a52b55eb76d1010001	\\x248ff273147f1de38de5508e658e2a12a8d0a09a406b9fe2283fad57d54270604894d3338dabdf22420785c8eaccb3cdb84f69f75e47a5455fdf382b970a8702	1668355506000000	1668960306000000	1732032306000000	1826640306000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
387	\\xb3dbf2db9e38c82b5eb8cba9e0284d682a96266134c40e30c4c3e76ff67fcd3aa6ff09f79f452f3483061511f612829c8468cbfc3ac3f4a083bef85d7b285ac6	1	0	\\x000000010000000000800003b4d4151fcf8fc370969892862b16d5e9e0ec5091b6a541edc44e8ea233233f590e03e4aef1ab6fd636393791ec2c97613ef7428c493cff889e2a74a595c1be9a137a1de1881cf376d86d2aa18bd5af1e92719899e981adb0257d98cdd9f909074c0b93e06245771aa25234ad1af45436c8a312e516296ea3c1be4d53ed53596b010001	\\xea6e9aa109ed07eda41fa19d0aa3d2dd05428dab4573321de2e59013c4e01693c0b762651c78d9454e47402614ae9c557453577f5921d76164981340cdb29800	1664124006000000	1664728806000000	1727800806000000	1822408806000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
388	\\xb63737686c17a8a1599f4cf0924361745a74b9552777a6da81d83daa205546aa6cfd68281a5903cbd917a1433667aed1a49b189adc4d523b8b60c0ee090f5214	1	0	\\x000000010000000000800003b2a56266238da1e3df1475a279dcfa1282eb3e25f3272a3fa79fae0fa254a648df931fc0c2bbaa7c14b65f81a9630d5d1bb6b198a035057ee0042fadbf52faf4bac5adb8aae1c958f2db2c4638142315b27298649d1de72f8cb18e3ca09fbeddb2809f146fbad0289b73b040004729c224fe144cefe24e10d802df2a2afe2e8b010001	\\xd1b13c3c02efab98efbb53f5e50360c35fc0f8502d9f996f6d371b26dd8bd3f922e342a568eaa5d693ce2cbc0f157c7a03def3361c9278386d9c626385950600	1662915006000000	1663519806000000	1726591806000000	1821199806000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
389	\\xb6072ed9d8481578d9e09998793c3530efbdef5d6eab238cd1f7871e4b8336259e227b149ff545c1550e747a6ff01277e9782b613268115a61fc964f9612f82b	1	0	\\x000000010000000000800003d8583c6623462beb0ce100e16e13051f3427f5e05b35fdbb9e60b6549d7fbd4add42af7c393e79e8f7b25c40f9607886aa534447a69d57c3b8c971dc650b01509c9f8e2be5e7c4b2f0f3dcb747f81d4463fbf180821577532aef94956c1b783f11c4fefb70dd47fad4799e4993405ce953ae8c1e7e09840361571b1f80aa76a9010001	\\xa8ac6b3cf4183d33537b5dc1252b5827eef892be77f06ea9adfd19a531af6401f094f40aba4e010c23d0adadf7940b1c73e66a4509955150a695f8c8fb7a0108	1656870006000000	1657474806000000	1720546806000000	1815154806000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
390	\\xb77fbef7f323513f0969b9254485bdd30701d631750f97337221be8b66db9188903d14c918e80172a8910c6c71b325330c892ccce788f7d7109c40c8fafd29a6	1	0	\\x000000010000000000800003ec8f5a814afd7ee179d147986f89af7620544b5af17af9f72ab03844472ca4ca5e7305d2e563dc4e42eb897be401568d4fd2fbb5e35834d7b0a4436b2bc48e81a2248b8d11c486ba04755577f0c1a35f825ccb773acce81262c2d6d9a6a90fbdd13f610e0f7327b2a3401026e847127d90556553a17f3472af0d44ce6433546f010001	\\xfecdaaac97780ad918cc706499d6d5f850b3fdcc024ae5c68ff1654c5ae76ae48abc717fedd5b24414c33398c0efb5e5bcbf5d24d6f7efc2f4343e7fe4576601	1680445506000000	1681050306000000	1744122306000000	1838730306000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
391	\\xb95353878adb0993f3073d159d46ed2b44a95c9d0c41d2b640dc88c07b0778e5ac24abd243c5db2114a7fa30ab2e81457d4b463e5704dddd0c8abb299ecbc175	1	0	\\x000000010000000000800003b2a9c1b1ac32270f83acc1d35c1e2d7e61b84ff831836b03dd8d83219dbabb7ceaa18f6be516932a173aaee70102f397d4eed4ae03ea767aecc17134b10eccbdebccd67bbc680e7ae4c1de0f13c6893e6b5e6fdfa2d0a1f626e14e3f059851974159c7f1a8aed34966b48962812108119b7feeeb3800df1898d21f91cf4f31d5010001	\\x38dd18cc1c72bb92cb387d314c16cc1c31fab1964524d3755965872561d2d300181da1079b246710fa886e536ab3e4c04b82ba84f0c88a6bcac144549f286102	1667146506000000	1667751306000000	1730823306000000	1825431306000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
392	\\xbd4fa75ca5ed3c404629fac9cf439887b468391126e72211fed43f4b7b4786584e83d3fafd21aa90c9de69e5f25e9cf0d875d95a1ed3db1c6769605d9003b1b6	1	0	\\x000000010000000000800003b4e9c3cec8ee3df2493eba1601910f005a4a75b40e3eca55e936d95eb399327e1e69984d991dd6a394d8d66c5bf2df91acb0fbae3402be0ca9fb5df6e17a2db33d4f42f06381d563a783e6827d661b017a1c9e43f10a76117b56fb8b4e2cd07144efdf7fb62e683344876281fc9d534729b3dede0fa7c97f22a3502bc1feb8cb010001	\\x26f1806ceee33fa0d9c88444e11733e7964e86ad355b2c7d5a7a2dac14c121363262f5f908b3585907510ae80883b96fffaedfa0ca1aa0b0409aa929ff4d090c	1659288006000000	1659892806000000	1722964806000000	1817572806000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
393	\\xbf17c596c829404a34dfbd5a64c7bcda616b336e8683e9a9109886c95a3caac7b23e5a2270eb066c0eddbbbec6bc6fcceb746b407ad5a8ce9b39589b2a7499c5	1	0	\\x000000010000000000800003fd68fdc3c822fd847d1f3b052aebd02d94eec47462b77dbd784f40d495e6fc08f3d8002fcf0ed173fda5653149ac37f0957b1b25eaa0266922a345dbd7ea17fb66aaf497163d069fd5ca9d51f03cacc95c155f1a3601cdefa5c871b734b2bb0cead12768e0ca6162ae7afab8bb4bd0f63292baf3a9651ac56918d3027e69ac91010001	\\xb7cd5f4dda6fd453461d3cdf8fd2754e0b91c81bac597f571194c8b9aa6d99e860f2b498c0c8beafae48c7f4b03944f04a23d5d799e9f2d281f9cc29d41f280d	1655056506000000	1655661306000000	1718733306000000	1813341306000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
394	\\xc13b3069702b0baf8d213e55927915d68e7ccde6fc2e9e3308d9289519b2d266cab3b20e4baeb561e6b072ae24e85bc48da8936807eb78d8940aeef78e2df30f	1	0	\\x000000010000000000800003bec33727cb0a3014808c1a007aef34a56205ac3b3d2e7d3e2dfee95a12c3f413fe63e6f2b098be87d3e79e72e7ad7d715dade10775185d682316a1f01c59fbc809af46b034c720aea199d06cf302e1b09ed0c1985d5fc851af191eb6349ccfdd017e9cb18650557b117782ab27c6b12320e87ae9764c5f00e115ddd5dd61136f010001	\\x4a0e7cec336fea28e6b003e91c58a05a4ed346d4deb6616c3257d8500f683b7d59163b9e0b66168bb5a059687fc253aca66ddef8322db589fad622daf9f1f004	1670169006000000	1670773806000000	1733845806000000	1828453806000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
395	\\xc4177d03a0f22491f48bdbbb1f7971c284b3d9d9808fb3a88e7b9349867bc35ec57d3df7251bbc25a6508afe9585860aae29150923cdb39a636b4d4f9305fc0d	1	0	\\x000000010000000000800003bc7410d00cb804a21dab6c04b40d9e0abef26476d380d7fcfce3aedaa9fc0e1fbb3512ad236396a3166d7fccc6ce336ba6037937c46d83bdfae91b2333fb271596646a0760cea919e071b7a200a741bad53584af48f3ab3821d21b3e0566e39c609c6de5142b3760debe0d13512e305dc190fd5d1c4edb670b79ec6553d61045010001	\\x030b064baeee71b2aaadac705a0e8060aff102329227be7fc4bc69a94116e54c3ee41c45f1e31e5cf68bc6ce1131ba6648674d3fe8038cc4d467a5cc56951e0c	1651429506000000	1652034306000000	1715106306000000	1809714306000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
396	\\xc82b86d3fd623b7af84cb879a42fa140382cdd58dec91689006a517968c088ee0c1035e218d5d79af1d5a416024ec646f3f6f9d4cd85a803d056737d39523dd4	1	0	\\x000000010000000000800003e51e37b15233940326d2af84969ce39e999ed7aaff9226fbe261a012b4b47ef7981841a4a769c0d601c37653d22e2176d5707d422948fd89286665e12ef503c8061e2e2878e32691cf34931fb33e37dca953d67be718a54d45c3bbdba41c7295dc04d425bd25ec28945ca85bdd116309410f99655155ea5da801bb90533ba8d1010001	\\x2c7ea8cbc7ddaa13087394183c9957fad72fbdca0d10262cd62756bc77f7eba0cb4f6d3ca5d3a029a0e86f6f6dd4d42e2ceb5d5c1aba1476b91ce618fd23a900	1676214006000000	1676818806000000	1739890806000000	1834498806000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
397	\\xc953e65e273e6c144c396dd2569ce9fdee45d5e2897b3ee38688083892770b7135fc404ab3b00a775c094fac6d589557c9e0ba4d531551aef544b593b2566fba	1	0	\\x000000010000000000800003bf7b24056125ddf471d78feaf89de2be3f5a7b8dd79c475b295393004101a468ee799dbad9656d396cad639c970c6b608aa02fc3f8eb137bda6c3bc8976d2ec6affef67a4c75ee4ea61714d3cd8aff9de83b591a2a42185336de8515a9955fab87d733b3c47c9b2e6f6cf69f82218d1cb9ccf2c42f8f24beff4f10aabb0e37cb010001	\\x4306ccd29367fc533f9199241c9dc6d453924d7cb2796f213067eb70287fb6faf7b68a255afd3834c2a10ccde01149aabe45f5df7dd05d5e88720a4fb6b69608	1679841006000000	1680445806000000	1743517806000000	1838125806000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
398	\\xcbcf82c5ef92d9e8c7553c366b29beed1ccc1ae68c39db9e16774afbfa939fc977b63ef97c329761f95aaae1882672e242b89118f3af58000322da8d84a3b16c	1	0	\\x000000010000000000800003bee4c10b5bec7d7bc0443de03e81ca8623d9314a13d9e8595715a651fe31f525e63f86823245f9e22cabfd0031d4db1f16bff0fbd2c013b3720028e43f6144e8fc4a96f13cc544463eb1c6a5c2dbf0b4e70311bc98b9fa258bf3310ef636429261574e526eb9cb7ff05f7ad02761a0c3b22a2ae0870fe10d5a71dbb69e1bd835010001	\\x3152318b7da2f65bcf76064a34730a189d9d0554220743d83c4eb178d4df534b7e5ae44a621988ce3ebb3a137ccbee1f1a46ba6646fb968885695e43b8b2300f	1669564506000000	1670169306000000	1733241306000000	1827849306000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
399	\\xcbbf291e144bbd5b1922a87b220cf4f6b568c115ce645b70e5e275bcceae6632a15ac570b912fdbe1e769d94f01fc90c117dca26f7869c2086d9cc776dc202ed	1	0	\\x000000010000000000800003b58170f0cb3a927f068ef1f5f75e91f93fd51f6f18751421b8168ffdc75bfcf24440fef4ecefc6775e3c11b88bf2d72a9b2d2d55723f1470bd8522446f5f18ba651b06bb4ffa38cc3cc95ddbc4e3b1d7a2625d670c1abfe507c0f4af7401ca49dd0c7739c5821f5b3650139b477347d95398e9cb7ff1a8011010200f1f9629c1010001	\\xb23988e989fd28cfa0d3da37b96ca780e33fa114a3b6575d8a66465933809d1f96b9a72fd9b104d0d2078a3a3039bcc4ba7639e7190eb801bea9563b8107d004	1673796006000000	1674400806000000	1737472806000000	1832080806000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
400	\\xcd5fe223d7253d6d2e21b06ab2126b6d094f6f1e3839ac6d04ffa4c27cea505e5acb5e987398e9bd1d3f47166c79a499550245aa3dfa1a401ac35994b0334770	1	0	\\x000000010000000000800003d3afdfd43e8040c44a8e285e1dd36d24f3b644c067fe53612f35071d655ce7131448a69d069a0f1f64d8b52b8b083d090f34bb3562901496f2f82e8b5c1a92c2f1d5c515b657360dfc40bbc5b9abbd4af90fdc96c34a3cba4d864b09f7c053b07b2f5704fb3160c59e536e2b232150fd7fd3e5ca90a9065239f1dea3de06ab77010001	\\x423dae983ce880486fba2186cd4f23a7a0f2c22526e7f42e132a7a4582a5c38bcc96e22ddb3006915ed96980874f9480729a7043e1afdf074652b7900217d905	1665333006000000	1665937806000000	1729009806000000	1823617806000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
401	\\xd1a317c9f59a9bdc334e8f77f47fb27cbd87cb4e0765c6cf5630b3dd966e90d03e97fc0b5adec7db4f96a36fb22586959ca91cff339d2f7d5af78ff141b132d6	1	0	\\x000000010000000000800003b0610dd065a382ae6cf8e0746f4c54789acecae5e907142ce3c39e27481fc9bc1e5c31eaedbdeab98fb431cc2742b6d36629c3937ca57bcb92884a1702128efe913ee60779cfd87515f2e5e13546fb8212bb68eec6a99484bba82cdf8882385af21fa99b7edee58d04d37c17c88fb135819eff7e1d5b895f5eedc0fe7eebc3eb010001	\\x7256b848627bc5fe5c879cc01086895deeeb8e12927dcb50996f045090e33bab22830de5a957516ef5f08bf39190a2aa47f72eb2f1f9d0b92d4beb993c4fd607	1652638506000000	1653243306000000	1716315306000000	1810923306000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
402	\\xd39b616982fecc567c23087f2c629ca892d7d78ec45ca884d01366a47f38625ce97944b60c7a09a15ae373154f8ed96354fd6f48286a9f63ea1ea6efc686711d	1	0	\\x000000010000000000800003cf7bef367dc26c0ae0d63919ea76b047cfaac0fe15db5e128c4adcbc208a2f8093fcabf0d64fdbe7f0f8f9e253de04c3a896496f29ecedbad5f45c80ecd368535410c162bb3f15e9079aa42a9e1532c498121cf8a49727f5a09b5c488534b041cd86d51913daa8f478bd3bb55097ae453bf72951eab363c74a43cfa0f17394f3010001	\\xc178d2fb451e58ab3ca32c11ca2ebb2eb119311dcf6461545e1aa8cafe11a76366c67f6c6d3b396e37ab9c17fc2117e14e3e538a2b5e0352fcf9b5cc3b72490e	1654452006000000	1655056806000000	1718128806000000	1812736806000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
403	\\xd39f8a069e5c61e33dcefe4f4ea8a04b90f26aeed1552f866b915bb5e94dc9b8b7943ef3fedb4d064d7f587ca6792e5f9ebbc36c83786415909630e5dce77a98	1	0	\\x000000010000000000800003a87341c26501599f75c864c35f7d31d79a6cc334aa358a39be43fafa0833002cdfc46aca4f5f0d8faff7e67114c0e1448a2ce9c8973c8058ba5691ad310dd667e5e5be2987c3e07042023effc1f7d2dcb2aa460647354e58b952215c11bd35362f6345834d5d364873e8c3d0c886f899e1c8e65468e99d9df629386f31e3f3f7010001	\\x72d1d206f4949900c655ccbb854fd6404fca689d24da9c3d6dca14fdd1746b541f637dea54e4d2f17549c11b7f3a1f4b4f0fd813ed2255a627ed67ec22289304	1656265506000000	1656870306000000	1719942306000000	1814550306000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
404	\\xdc1393474c07c989374ca15a3e148420f71cfcc2b5ad51518047d092e20dba7c1dbd68e1f1346d1b96351f3995f678964907a9fd8f79c8db1450006915382e62	1	0	\\x0000000100000000008000039ee541ecf4b2fd202c9cdfeab4fbdf33d1b6428c9ae0b2fbbab7d884a380a5a4c89e7a45d28601fa0962f8da65f41f25d71d9d3d20f0dbab89bdabae660b487c2919b78a081ea13c9c49a701483e3e73466df1cf039baf1438da29b20cfe8735353bc8e38cd539ac973dd71d5bd78de0fa38837232e33dcbed0fc4efa78fe7ed010001	\\x1224efa51c43bd5f5625c129c352c83eab597110eb7cdcae66ca8cba05c62f103933a1d091adffa927951e7b70b4e54702a70923a45779ca6b7a6109bbfcb904	1679841006000000	1680445806000000	1743517806000000	1838125806000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
405	\\xe1cf770bb38f8ac7d6e1049d5d9eaaf193b45ebcabb13f30ea68a2c7700162501bb9379b4a062c141d5b388b378190e31bac6dee2f7cb5f081313aa019adb241	1	0	\\x000000010000000000800003a0571916dbff35211e005e1f3868cd32ef624049cbf33bc2f8747c881573b77ebc26f56510742c203296f773021a04d0b583a3a1c68869ac889ef763ad31a3ac6589a548db158850222d199bf94bf66776fa2d966b87777f22d1a2115614ae11a14634c35af88f102fdd94d96997dd81ed2a30f5d9c3bba989ab8e4f4e24e377010001	\\x851ac2d8ecb850c6c40e8e8a55950e79017acf3a2455fa762e4a28d0e1a8d2ace9e6cb824c62f70c888dcdfa7e9b2360e2f93a3a9abc7158db581af921d5fb0a	1676818506000000	1677423306000000	1740495306000000	1835103306000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
406	\\xe3b750c85488dd6031c82246cd570f42ad43a4b7f11d3002ebdf70588dad0a017388b3fdc41fd12384455ec7975d1bdcccd43d55f3b0d54a9210f39df37e1060	1	0	\\x000000010000000000800003bbcd4b8b0af7622cc21b304f306deb9601467c7edaa9b60b6e97a3bd2e8d0df0630b34fb1e96119a4bc35ee8f8dbccbd02fbd603655169e360583f6f4a60ecc396edc01e1d7432faf1bac4f1e916a2e03c6d6b28ffc315ff84ae6e334e2318301c972d28b399e7acfc34d150db4acaa3c6336834d6e395b87792903922a94423010001	\\x3c0b46f0b807e34c2c123831befff5458df31b8470e114a68edd0531feff695a580a716be8c72aca5bb1ac9d5a53be1259cf781f894a6e970340bd8dc3dbc507	1659892506000000	1660497306000000	1723569306000000	1818177306000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
407	\\xe5cf9c825c5f8e8774e45b8bff50c9febba0531c902e7fa4e9dabca36129dc79c83c8c8cee7808e5b840958c61ccee72dfd4c464c66382c9bdb1df5c794fe23c	1	0	\\x000000010000000000800003b3200646493525a6482d28189de9b7c302ef9c550c207599e11ebc12511b7c46d862261fca701a9c85c1be223dc7bad9bed7b829e09b11d848e2b663ebaa72f311c7f0e56e538d396a1f01a2a077106a34e4b5740d3096f6d2abcebeddd43f1a7bf9c42616df592c8fd58be78f534ec82f8a9cb8073b1fe4b5d624fb864c3259010001	\\x12ff1a3c5ce5d285755aa4e15d43ef0be03af38e42a1051c85850dc605079eeeacfbae50af508ba4fda2bd67361f0346a7f818967fbf9f20cb9d4332a245490e	1664124006000000	1664728806000000	1727800806000000	1822408806000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
408	\\xe6cb8e15b82805e3be62fc67f4c2942e2e5f7cbe66ceb48c760ed7a3f325d631f37ae25038bc306b6ec035278e0da4044f5957da81416517565f4021a590130f	1	0	\\x000000010000000000800003d1be95139914d2013ddec44d408574c475ec36880ece7e9ba4b66cc3934ccd4d66bae90ee115298049bf78168ba800dfbd9500c815f427f17ec66b71d11a9ddfa2b4d025bf242636426c41a19d59e8cef7b9b6efe3d1ae032c85abb56615ab10548a08c283aa36c974f6940bd24137340fec9ad693cf838e14517ae1643e62d9010001	\\xacded04824b0bf2a8e6d6424d8426a0c7d883517f156bc955a7b56f3442e2db3672a85111f7586b67e7a1dfdb52728c56d4e92a56a42f159dd2245d3d84fa706	1674400506000000	1675005306000000	1738077306000000	1832685306000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
409	\\xeb9f731520879dd2deed5b4806936b93f6b3a6ac9dfa53a01e83981c77806a03aea13097026afef0537c8adb86e4fcd3ce63564c8d963b3ee765e718171dc72c	1	0	\\x000000010000000000800003e192055336c61a1324b830e649c371829c2d987bf2a63ee80209670d50a015b448924098d04c1066f3991fec611bc049849d3dbf459fb132fdb136ea92dd05e446c2c70c4ef4cb4531436d33b96a74ce44471fb299e1ef32c25907b3d29946a7c809ef492768d3001a9ec6a3ebe44212cc8fa3d383562640755162ca041238bf010001	\\xf9fc8ca9ddd054b6295b522ae8498c574c032ee0f3d891883578b560e652f580822bffd447702e3660ec0b54d86a475111179dfdeb73f9780777ef057cf0bd0b	1658079006000000	1658683806000000	1721755806000000	1816363806000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
410	\\xed2b6c907c4dc7d656d6b46a3c6fc55201b3fc606ca338ed74572c19d8c8dd2080f038f101d0a40878ee0f5318f100f6fe9617890673bee9d3bca98e6517f0ae	1	0	\\x000000010000000000800003c47e57331517ea692192c9c8b42f52a6365d2ac06fd037b67c45561681bb9bf09b9431e3011f56c539deb72b80ba14b9715a4380a994e0aa7fa27a74da83ff7388d9c9e826328c1edfb23aa2eff4cb69176d02ab73afb4ded07cb1371407a9e32989b39257b92df9da5cc491f52181d81689cb8e88bbc19a5b33e27b9cc66d1f010001	\\x85e362acf5bca844b2a38a9e734dbd7e62e7fc6037f0809a57f9dcb0fd08a8b4683a8004877de3b0a2ae4ac50ad45cbd977ec0522e15893d2f2e45cfce3fd60e	1671378006000000	1671982806000000	1735054806000000	1829662806000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
411	\\xedb797e14336f24e512ea69e52534a37f738133d849a778588097feec8706c62ba84d6df7529b371f7c4e722bc9c5ca1b5a4475da54f3a5faf304af836eb5d25	1	0	\\x000000010000000000800003a3994071665e28e87221d9d0ca8639d8838a1c6e3a907b57532772a446591a60257e9afa0e517f26b39b1e1d6348a8b45574873f9c3fed412828c79793c00b4ff6cc8181b8f8dee8c7e6690cd348ccb7151d3c8bf9928c960cb0b3b584dc175ebfa204f5dd9113ec10261feb69490ca2b3fa98ed8a998a49239de2a37eb4c083010001	\\x78adf0928eb689f41a08a278bac3fab5028859cd16811bae03c96ecce8e7bb0c4a7a15c507f40809466fa55c1834de475f8f5a40283205a0f00fb29ca7ad1609	1671982506000000	1672587306000000	1735659306000000	1830267306000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
412	\\xed778844c7dff3981a5466c92fe44bf427c39354c7e31f7f0beecfb1ad8cfcc9e1d2c08d4f01210ad354e6907f2ebf7973891c3c688143a558f54319250c8e4d	1	0	\\x000000010000000000800003c23aee84b59a3d30fc33ef7063323d9a6c73f568edbd60fd28156be94733b382c6f6c0257b9107729144ec3511df272a2bc507e94b47c2e01fb06aa43f6ffcebe6b72c57cd6702ef04bd216f11ba67a4f144e358ef7a2be2ef3dca63bcbc97155bf869d26c459ddaa2b5e9b2bc5ae36f86342384a109e643cfcd348911c67e29010001	\\xe4ed81c2718fe7a72970fbaae4fc1499399d53bc85cee5af89de28d9220b5012a90c965e935efd1419f8d7abd72f5055143366b1febed3b05ebf3782f6bfd20f	1668960006000000	1669564806000000	1732636806000000	1827244806000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
413	\\xee2702040154f160f390428f2713b685996b8fdb5da75d6cacac5a6af9935bbd0713e532c742ce12536eea62fc2bbc6b90f44135a495e164453d841faae09d86	1	0	\\x000000010000000000800003b0e8e3271524e04a5758780bc7e08f2f3c25cd00161496c106189894746b55da405cf174ec1eed0ed8cb771f233cbe26403c28b9f904ea92c84837ad980c776b4d2deb44c08db53cb90a358e77c903ecdc19e322aaf8de1cadd04bf8e528ca03c1af3adf26b00542359dca8ea4b423d3b992e82f4ac845ecdc0d01e7dbc8b58d010001	\\x2372b6ee4ea84721f34f9e6ba8437a24925c7326d3c570dd9d157e203f05c14d31d64fe3f02034a3b257a56714ff9647aaae4037a356df2c4e1f980517bbe309	1678027506000000	1678632306000000	1741704306000000	1836312306000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
414	\\xf06fbb93d692b0c7123734d2a54756c74a85fbbb6ffcdba27b04d95748a10acd9ee974be9559e3f2a4a24e6a0c4d79fad9c6230153c521abf9690c3cd4a580ad	1	0	\\x000000010000000000800003d03bbedda2040b681fcd6ab699d5ea0a3ac0b92b29a2165699ff3e0d3840ea8341afb54969d6dd19c38fc6b17dff7b95e1c224a8a05efceda621f470a00c00e9611bdec61468a0c7b19378d540271c99b06c76ade3f133dd0ce2aca39ebd5928f90f1c6db4e7f617bae044028f2debdf1dee245c4588ffe8badfb219cfd13fc3010001	\\x7969495224097b0a5514bbb427f9aec787f8b5f686c78bea20939abadf7b33b2fc9081ec4f615db030848f075b647bac1654db405df3967e6325ba5927a04004	1679236506000000	1679841306000000	1742913306000000	1837521306000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
415	\\xf2673f1b8b557c642eb8b8fa3bc1e5a57364e229b452c9ae415861f2ed3c414c784d3611d7977cd6f6e2edeff28cad6b7a5c1a1f67dc7ef0cbbc3d089fb56cb4	1	0	\\x000000010000000000800003e11f2b9d22e9e9da421383d620332bb08480bf7a328c2211a1afec77c3342c3d1b72b3ae8eed38afd8fe1f952dc976c288cdca20661cc7fa709fa11dc2f60cb63882a0397508eaeb5a9061896f1b1ae831640c0d9b7bd1b84eb83ecbe5ffbe30127bb259837d731b997f592d98629626654a11afa368af813cf4b607eeb7641b010001	\\xb9ea3f154f2c1892e12e6616f9c08e7c61c9df34103d9cf624e81540dd4153eaed96bb95050ada23a17aea0524aef89b95017b7face8a8d837fe54b482e39f0a	1662310506000000	1662915306000000	1725987306000000	1820595306000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
416	\\xf6b744a5790cc9d924f53b54747db1af4d38dc7aa8600646960afed68464ceab0335b0b63e772f10b2ae6ea06e01b8dfd6e2df2060aec531c9f13ead5be4ba46	1	0	\\x000000010000000000800003ed124642d56a95851cdbd7c3c191fe5907dedfd90bc3b8bd60e8b8b30fe472ea638aa65bfaf47ba6ed42e2695cc62ae3414b2345a0a18879f7852f54f5f213e5750da0e38a6a8d31f5d256808fae1096ab7b59e0c045155dd41e76dbb0ef674290b08521e8aac2688201bbe95a53de3e7e890d257293fc2c9dd215a493a45d1b010001	\\x36d74939a6f0ff3747ef13ff77337b55c1303f0accfea5b15f72d687ab23060d83eb4298b10e2909e5982a72d2a5262061e73fb9ccb14fe0e12699f4acff250f	1675005006000000	1675609806000000	1738681806000000	1833289806000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
417	\\xf6f7ddf51a346febe4a726d4e0089e7f1cc917d41eac7dfd8dd5f8c14da822fbc24898194ebc37e7f3874d2b543bd1b9889835db37b00696c286623e0c866e4e	1	0	\\x000000010000000000800003ae1cf1bf3012f734d9f80a216f2e231f0fa3451482b603d45efeefe33c58c0813566ca3c49437660f9a9d33f99807babc958d069d28b476fd6162e88e0e39c041527735e7c4d36660a3ebcac31d3323addc862fa2957891321b3021e9a40bdd1d35ff10a8495c8d67d2f982dc139831dae025faacde8fa17685763deef0db677010001	\\x029c020ba12a6f443df5ef011942732708f8aa883b3463646df7e2c69f6021c1327a44abeacbae801b439e38ab60c24a2f2cee7b3653d387c17711c4ec6d4808	1670773506000000	1671378306000000	1734450306000000	1829058306000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
418	\\xf8afcc0149f6c29c5c90e8e5d295435559fd33f6d6877e8b5c01e2ff6c30f45920bf0de3833fe9b6e33d3c075ad77551a91948c21a18754a7ba79946fd47007d	1	0	\\x000000010000000000800003c1ecac49062a7e4917ba3753f43ad11d171087cc76e5c5a23d31aac51cbaae217af960bf88ab7f02fe90baa1c8b5c6f08fb513559f4d9bcab2af4d43d33d682be860745283f2f4fefe898bb5f25cae589a0b12b4e3794eda0320bddd84a3ce70a67e5701be9bcffc894bb7fdde29faac2d4e3b3bf5cbad26f43390b04f312131010001	\\x96b32705439772d3110f27eaaa3c603fd4225403f81006d130d1d672457111250c946413d1e110f386161626769122f6866b3bf39289edcb9b4f7df23fb2520c	1671378006000000	1671982806000000	1735054806000000	1829662806000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
419	\\xf96f6f163c42e4eee5badffc66874b1086a41e543c8f9d650c20eb399a7a82ea452044f03760b4108330a7daf83b12e2771ba713d8218c8b3cfc98223a949dc0	1	0	\\x000000010000000000800003d55db0edcc2ae8278bb9d89999fb01c03422b95d3ec506821383c7c650e26862ea1169a6a1adf6af60c75691d30078cecbb5391ac4421ce6fa1c1cfe3d359eac38cf2640fb55fb2d50b302bdd28a37f838a6b8051e5fbff00d0bce6e3158bcdf4c5391407587a8a9071f267ecd0fe6825abd4b65bf17b65239f5cf61f161e1f1010001	\\xd22df8f912fc1c59a379a2f3a63ed6607d10e41319e841b3c72a42dd443c7f76edd100a06ca00acf988c39f24a5da4869349f891dcdac2282a8f08de12d99c0a	1653847506000000	1654452306000000	1717524306000000	1812132306000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
420	\\xfba7c9c6c27d9ff7d5fd32aac31483bdcb1cd1dca72d15527149e95c362e6e6fe37f61b33704477f2d5de962fc6d5f13dd862cbc32cfe42fc90dc0f30999117d	1	0	\\x000000010000000000800003d7bea384b4c9b8d48cfca09666a39cb425cabfb1071c76cc3f888d1bf314412c18490c6031d22784041c6f794fba7f66bb4b4483901448e2faf109c09250ca7fa4f2930fb161c13db7d34c3370f6b90e6235441f80ff210d0c2600881985d739edd472c8e8a7edfc9bc4dff0d3fa08d5b935bcaa30e27ac24d7b24cdc550e95f010001	\\x33c67ebb29bb4f6b6dad6d9de9c864f25b67bf662ccb3a459313f62e24176ec18c36b0f59c9f7c2aa9a5b862b5f7dc2e66f775ac696e89b75c1f3366d13f720a	1671378006000000	1671982806000000	1735054806000000	1829662806000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
421	\\xfc8fbb41d6efbd4bd449751d658d8056af62b6dbfaa2ff266c24d8ffb888e5ab5ec7cb5da4ec8739118771f544386e760ff83deb5dbb22ef017bc78a27e39dd7	1	0	\\x000000010000000000800003b020587f17d6cec32452fea392265567bc24380167c013d11b237b8579b4d82f19ea95f6e6a139034d965fc01bdcf4dfcb5dbeae90b517631606bccbbfa03d03ff38db2184f6538faa046212a28c00bae393bf865d0a5b89b4a3a6036dd07a7a22f6fbb03b71c98f32f779d0d2c78148013a52064bce3a6213e2c6989820b9bf010001	\\x2119aee220e5075ded7493002211d44985a893d677622c3686a1a230d91ab710a3e307bdd9907360f2f4ca0228a525abb17da7185dcc10d892d23bbaa2193209	1673191506000000	1673796306000000	1736868306000000	1831476306000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
422	\\xfd273732b21f9df54b912f5616d957bb15beb378032a812360f96538133f8eaedde7e6e3ec7746f308465398582e343fff6d29b6d57ec7299ca9337a672eba14	1	0	\\x000000010000000000800003d0d5eebc636b050afe22341bdf6764def7db73e848699d46edd9630b0310e07a8eaa66fa392080d928dc66539b2a84e124653af5cc137d74a5e5fede2f24b6749f484281a5130d2b953dc49b3f1ef5ea67706bacee1325eda7b1b63b0a2c2321f00d8defc511ec62d7dedfe4337278fb796645315043a00bbf1e8141e6130f3d010001	\\x243757dfd3100e5ee7cd8d86fd97d164a14967095b1edd46d86540e8be5bac173e8ea1e14ee56bc6120242de2d2188d841f9ada874a478a1d747a75ce4406006	1656870006000000	1657474806000000	1720546806000000	1815154806000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
423	\\xff3745efa1555668096bc6bbeaed6f7590077a1547328c3a08c9714d6b3e0dd5327c9b92451debd7f140bb9ec7514373ac45d747c86ffcce859e49580a1bdb16	1	0	\\x000000010000000000800003c373b0a308b2f3b28285bed33f0583aeb4753ff3d5c4b34f5bc7d52f785055467aface49a5fddf8e589281c3e5bdd38a92e0236b40ca8b144ec53265d481b209545c9af2706ab9a8548545b2ab42623bae3f4479c287be1887777fa8a9a4f38a2bba7001ec0c07dd4b322d5a2d7ed5b045839be832e346309da3a28b62b24293010001	\\x2767199c9c9f7d2428d8126627c45812e81852ade1414598d07f7660f8161df7de5402dfeaf2c2da4be2d4eceb5685cc4060ead05a889a5a5411a07ea7e9c90d	1658683506000000	1659288306000000	1722360306000000	1816968306000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
424	\\xff8fe1f1c4727797dcad1f5669911b8f6771f368ab8b8df04c4b9867e13d550b21b85e63bc71337f305e2ad61545c63bacc92f39d5d7757e2ffe033741daa52d	1	0	\\x000000010000000000800003d2d7dad41fdb9253eac64cdf4459340419ea8dd535ea5647810b28a42193262d6abe54e775e865da07f93737aed68addf642498cd427e593166ea298dc682cbe7659a6bbc1c2c03b7add7fb338e25fec246c64da7c421651a278269f04b0aba11504cab77d45014999ea5c8d1bf0f1781dda024c944906f18fcf53a6e56fd5d3010001	\\xb8af7222c02d940f3ce0befc4709cb65c98971e2a9d3f78a5b4877c86a625bcc06e609e97c782c18a2b590efbed850aac4db14132ed557056a5800a0749d470d	1670773506000000	1671378306000000	1734450306000000	1829058306000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_extensions, h_wire, exchange_timestamp, refund_deadline, wire_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\\x6027c5b6522f811b9740a957d7379cd8410a1a19bd114a9e885a0976e3edfa2f	1	\\x0629dc8f082fc5310093435fe150a7d12145840640369c8b0ce492f5d6ab6402fb8037aca359a27ee57113394fa749196b7fbe29feddad0b2f7ad60a344ec388	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x5790d6c7366504d81e4d0fbcc2cf4373b7c4b8232fc1e8b458d12e2c132b7bb846f07d192b19d3a2c82a76acc7963c81a1882c038e67ea72fe40a695e9e6b73a	1650825025000000	1650825923000000	1650825923000000	3	98000000	\\xfb22f276cfc9f2860fc551834bce27f04a654a6ac1fe4e70d5f398c2a0565f58	\\x2c888021e0de196c456c47db6b2cad23799d112a3b7eeb319c5cb91b8671c66f	\\x77e9660271d3ae3d39512b172cc93b852cc7d4d2b1bc6e03365e9595543b65061fc0a68c926cbf9c6df934a879f4b9181737648711c147d23f6009548754830e	\\x21a32844844732f30628075833efa8e6fe025589e2efd9fa2ad7363162c3a148	\\xe078a918fe7f00001db9ede7ec550000cd4a9be8ec5500002a4a9be8ec550000104a9be8ec550000144a9be8ec55000000ce9ae8ec5500000000000000000000
\\x6027c5b6522f811b9740a957d7379cd8410a1a19bd114a9e885a0976e3edfa2f	2	\\x63c4f7c34195a6ed0dde5bbe0c162b888ef5d0b579be589dc0d3919eb55fa921ea9d21b6a5abb41cd6e28afe3cdd5865bd96f0e502834b8ed9bff07c37867675	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x5790d6c7366504d81e4d0fbcc2cf4373b7c4b8232fc1e8b458d12e2c132b7bb846f07d192b19d3a2c82a76acc7963c81a1882c038e67ea72fe40a695e9e6b73a	1650825031000000	1650825929000000	1650825929000000	6	99000000	\\x4e9fe3e0730616b81d47f74d78dc5c6ac8d5906e51a1a89e1d6b467c882440f7	\\x2c888021e0de196c456c47db6b2cad23799d112a3b7eeb319c5cb91b8671c66f	\\xf078d5c3a225163d27ccbd634379f37daccbb67c0d61cb0f4834f7172965ce1192eb24f2808a258635e701b87c2e64cf80c5fea4a454eb2de791c171efacbf0a	\\x21a32844844732f30628075833efa8e6fe025589e2efd9fa2ad7363162c3a148	\\xe078a918fe7f00001db9ede7ec550000ed0a9ce8ec5500004a0a9ce8ec550000300a9ce8ec550000340a9ce8ec550000d02d9be8ec5500000000000000000000
\\x6027c5b6522f811b9740a957d7379cd8410a1a19bd114a9e885a0976e3edfa2f	3	\\xf5e23804fd9d9657e8277a87aba0b452c71dc79d144d23d44226a83f4b8d9e1faf88df7a83a4459fd5d8a9b9c948b693272d86dd54a056ede44b82d4ddbe3098	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x5790d6c7366504d81e4d0fbcc2cf4373b7c4b8232fc1e8b458d12e2c132b7bb846f07d192b19d3a2c82a76acc7963c81a1882c038e67ea72fe40a695e9e6b73a	1650825037000000	1650825935000000	1650825935000000	2	99000000	\\x2da7c6bbf84eb9ff716a4dcdf215543745ab1c796957adba2dee9ded6789250f	\\x2c888021e0de196c456c47db6b2cad23799d112a3b7eeb319c5cb91b8671c66f	\\x8f4d6541f60b24621301846893369dd6b4da2cc0c9fb13d81457459b6d13f24044650584492a4e2d4d25473c80ab02a3624bbbe9246b5339ab25b001eca1ec08	\\x21a32844844732f30628075833efa8e6fe025589e2efd9fa2ad7363162c3a148	\\xe078a918fe7f00001db9ede7ec550000cd4a9be8ec5500002a4a9be8ec550000104a9be8ec550000144a9be8ec550000b0439be8ec5500000000000000000000
\.


--
-- Data for Name: deposits_by_ready_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits_by_ready_default (wire_deadline, shard, coin_pub, deposit_serial_id) FROM stdin;
1650825923000000	1066023514	\\xfb22f276cfc9f2860fc551834bce27f04a654a6ac1fe4e70d5f398c2a0565f58	1
1650825929000000	1066023514	\\x4e9fe3e0730616b81d47f74d78dc5c6ac8d5906e51a1a89e1d6b467c882440f7	2
1650825935000000	1066023514	\\x2da7c6bbf84eb9ff716a4dcdf215543745ab1c796957adba2dee9ded6789250f	3
\.


--
-- Data for Name: deposits_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits_default (deposit_serial_id, shard, coin_pub, known_coin_id, amount_with_fee_val, amount_with_fee_frac, wallet_timestamp, exchange_timestamp, refund_deadline, wire_deadline, merchant_pub, h_contract_terms, coin_sig, wire_salt, wire_target_h_payto, done, extension_blocked, extension_details_serial_id) FROM stdin;
1	1066023514	\\xfb22f276cfc9f2860fc551834bce27f04a654a6ac1fe4e70d5f398c2a0565f58	1	4	0	1650825023000000	1650825025000000	1650825923000000	1650825923000000	\\x2c888021e0de196c456c47db6b2cad23799d112a3b7eeb319c5cb91b8671c66f	\\x0629dc8f082fc5310093435fe150a7d12145840640369c8b0ce492f5d6ab6402fb8037aca359a27ee57113394fa749196b7fbe29feddad0b2f7ad60a344ec388	\\x43213f6f81a0a8c2bc540b16eaa092f5fe19630176f61fa89e4b8501e01e9e1f3b1e5ae62d646de6c32b551be6c6de21765004b0b52f323621382cb98324f708	\\x830b4f0fab259d59adbdd184469bfd28	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	\N
2	1066023514	\\x4e9fe3e0730616b81d47f74d78dc5c6ac8d5906e51a1a89e1d6b467c882440f7	3	7	0	1650825029000000	1650825031000000	1650825929000000	1650825929000000	\\x2c888021e0de196c456c47db6b2cad23799d112a3b7eeb319c5cb91b8671c66f	\\x63c4f7c34195a6ed0dde5bbe0c162b888ef5d0b579be589dc0d3919eb55fa921ea9d21b6a5abb41cd6e28afe3cdd5865bd96f0e502834b8ed9bff07c37867675	\\x450c3185c72cd6af615bc9af0fef17687267affc0fb7d621adebdc7f62e86d327d156f4396bbf57e7fdd829234d803871ff39e9f6e3cc01cd6eaa90be5d2fd06	\\x830b4f0fab259d59adbdd184469bfd28	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	\N
3	1066023514	\\x2da7c6bbf84eb9ff716a4dcdf215543745ab1c796957adba2dee9ded6789250f	6	3	0	1650825035000000	1650825037000000	1650825935000000	1650825935000000	\\x2c888021e0de196c456c47db6b2cad23799d112a3b7eeb319c5cb91b8671c66f	\\xf5e23804fd9d9657e8277a87aba0b452c71dc79d144d23d44226a83f4b8d9e1faf88df7a83a4459fd5d8a9b9c948b693272d86dd54a056ede44b82d4ddbe3098	\\x52475dc1f9b91e24b6133557d69f88b3e28089a9de586289349d38408a50a4a22c9fc55f36da2b2a6755b97c4f802c72c6150b533f09430b75e3f1093aba4508	\\x830b4f0fab259d59adbdd184469bfd28	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	\N
\.


--
-- Data for Name: deposits_for_matching_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits_for_matching_default (refund_deadline, merchant_pub, coin_pub, deposit_serial_id) FROM stdin;
1650825923000000	\\x2c888021e0de196c456c47db6b2cad23799d112a3b7eeb319c5cb91b8671c66f	\\xfb22f276cfc9f2860fc551834bce27f04a654a6ac1fe4e70d5f398c2a0565f58	1
1650825929000000	\\x2c888021e0de196c456c47db6b2cad23799d112a3b7eeb319c5cb91b8671c66f	\\x4e9fe3e0730616b81d47f74d78dc5c6ac8d5906e51a1a89e1d6b467c882440f7	2
1650825935000000	\\x2c888021e0de196c456c47db6b2cad23799d112a3b7eeb319c5cb91b8671c66f	\\x2da7c6bbf84eb9ff716a4dcdf215543745ab1c796957adba2dee9ded6789250f	3
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
1	contenttypes	0001_initial	2022-04-24 20:30:07.141196+02
2	auth	0001_initial	2022-04-24 20:30:07.26017+02
3	app	0001_initial	2022-04-24 20:30:07.354966+02
4	contenttypes	0002_remove_content_type_name	2022-04-24 20:30:07.373578+02
5	auth	0002_alter_permission_name_max_length	2022-04-24 20:30:07.385786+02
6	auth	0003_alter_user_email_max_length	2022-04-24 20:30:07.397396+02
7	auth	0004_alter_user_username_opts	2022-04-24 20:30:07.407239+02
8	auth	0005_alter_user_last_login_null	2022-04-24 20:30:07.417329+02
9	auth	0006_require_contenttypes_0002	2022-04-24 20:30:07.420458+02
10	auth	0007_alter_validators_add_error_messages	2022-04-24 20:30:07.429842+02
11	auth	0008_alter_user_username_max_length	2022-04-24 20:30:07.445857+02
12	auth	0009_alter_user_last_name_max_length	2022-04-24 20:30:07.456573+02
13	auth	0010_alter_group_name_max_length	2022-04-24 20:30:07.469985+02
14	auth	0011_update_proxy_permissions	2022-04-24 20:30:07.480005+02
15	auth	0012_alter_user_first_name_max_length	2022-04-24 20:30:07.488823+02
16	sessions	0001_initial	2022-04-24 20:30:07.509979+02
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
1	\\x6191ed6cd32946e87cd12dae1d512a0f50dd4b9bcb61c2bc46d4bed37eefca7c	\\x53c3ae2ce45e685d41db1c560aa8ee38245bfe9aeb534ae34d3346fc81ef5cefe87bfe4ae21603748c07972965ff0b668d2fe9621e00264d05d826de90e06c04	1679854206000000	1687111806000000	1689531006000000
2	\\x21a32844844732f30628075833efa8e6fe025589e2efd9fa2ad7363162c3a148	\\x52410d223fd9df23784b769f27a505e0e3a210de3854a9795280900577c13a78583bb3f3cb648d4ce19bb56949d4c3439fa4a2acb8837da070bab000757eae05	1650825006000000	1658082606000000	1660501806000000
3	\\x700f2638c9e10223603dbca47031d578938625ce15f34a8bab886a7a257da93a	\\xe0a97f028c221e73035497b039eeb7302eeaa51dc6e364ae09eb7f979369c2ae35cfc270f8f14d3f28c281405afdd5b81f34baaf1f46e609a2652fd91c31860b	1658082306000000	1665339906000000	1667759106000000
4	\\xd132aa7c10df3a80769df7164b8dbb6ae4fa75f539af9018a745c1fa328e6be8	\\xc8cbc31fa11e01868f7d05ee438e291e50c67a583e03ce42c6790f393005610aad0bc740b3d0897e5c275af45f219fc6dfe8661a15d00c53090dd55ac3ff1908	1665339606000000	1672597206000000	1675016406000000
5	\\x1836181856cc22a6aa2df642b7b735a6c2b6a709010c236a7571d2f1989fbc7f	\\x4a55d9967650acbe6ae5f26959a96f82eedf0c9b1340cc983a7743d337c7e42186d9ac1916a9eb65f8a236c84f57a7bdca8dcbb051a5a304873c1d34c0a1cb0b	1672596906000000	1679854506000000	1682273706000000
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
1	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	0	1000000	3600000000	3600000000	31536000000000	5	\\x2a2edf281b248408f15d141167938d6e7e34dbe03d73074c65c79e894ba4232d72370bca8a6f516149a83cc4ddcc042e8c6f8d1ff5a4a5340bc77a4276d88c00
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
1	123	\\xfb22f276cfc9f2860fc551834bce27f04a654a6ac1fe4e70d5f398c2a0565f58	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000774029b1bcd3da28a0e5e561855ec0d3e690e63f74fd4f69dc637cbca2d39fb0298ab67831ff30f2912ed6e4ea3655b44e9fbf556ccce10083d0bd9cf57fd61c77790f8e72513e4eeaffd738d6e2378c795f79f3f5f21e70bf7f2b7c74146b2f768daae961f1ccfd694774b20ccd71aeafda2fb2b3175487a492a71a27310bb1	0	0
3	288	\\x4e9fe3e0730616b81d47f74d78dc5c6ac8d5906e51a1a89e1d6b467c882440f7	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000000e2f837903bb41867a7eada906dc0ec30cec8876bf29ecbf682d2736788ac4b9bcbc83b03eb0d88dcfd5b6ad0ea4d1766ba65bcbbbefd2aca9f29a919f6b5ccee119eef52019f35a42a27a02adcc30167da77e9c0c0d4e8defc03ebb8a4692cc7cf0543bd2de8dc26b2ff6311c2fd2d408f08a4dfbb3ba860cfc57a452b3042a	0	1000000
6	41	\\x2da7c6bbf84eb9ff716a4dcdf215543745ab1c796957adba2dee9ded6789250f	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000097caa901568acf2c03c7f6eab7d0e26f8cc1d0b55e666f8c168376e60413fc56d99410b54d76fa2ff79451d941f19adc18f409d395657a8fc7eed14494b0faa4c071e03af153f1b4c79d61d7cb0a116a29c24be0200775b1c6741ac7fafd29fda1cbe6bd57f3f71997370a1a54d8ab2af8f640f6e16bb4457f9cff5a7a944137	0	1000000
\.


--
-- Data for Name: merchant_accounts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_accounts (account_serial, merchant_serial, h_wire, salt, payto_uri, active) FROM stdin;
1	1	\\x5790d6c7366504d81e4d0fbcc2cf4373b7c4b8232fc1e8b458d12e2c132b7bb846f07d192b19d3a2c82a76acc7963c81a1882c038e67ea72fe40a695e9e6b73a	\\x830b4f0fab259d59adbdd184469bfd28	payto://x-taler-bank/localhost/43	t
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_serial, merchant_serial, order_id, contract_terms, h_contract_terms, creation_time, pay_deadline, refund_deadline, paid, wired, fulfillment_url, session_id, claim_token) FROM stdin;
1	1	2022.114-02M7WW0SAGZVG	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f73223a313635303832353932337d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313635303832353932337d2c2270726f6475637473223a5b5d2c22685f77697265223a224159384444485350434d324447374a4431595943354b54334545565739453133355a3059484432525434513252345342464557344457335833344e484b4d583253304e37444236374a525938333843383547315257535a4145425a3431394d4e58374b42454547222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032322e3131342d30324d375757305341475a5647222c2274696d657374616d70223a7b22745f73223a313635303832353032332c22745f6d73223a313635303832353032333030307d2c227061795f646561646c696e65223a7b22745f73223a313635303832383632332c22745f6d73223a313635303832383632333030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2243304b5742444a4a35593048513554304e35425845445757563130474d364753514d384d4e374d384238345144525a445a385147227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a22354a3438303846305652435052484243385a445050423544344457535434394137445a4550434357424a574851314b4852535147222c226e6f6e6365223a22424545525a51474444594152363743524433515046523954435131364e3830585357453132313756483532395651303248545347227d	\\x0629dc8f082fc5310093435fe150a7d12145840640369c8b0ce492f5d6ab6402fb8037aca359a27ee57113394fa749196b7fbe29feddad0b2f7ad60a344ec388	1650825023000000	1650828623000000	1650825923000000	t	f	taler://fulfillment-success/thx		\\x6deaab54b3acaa831c343f50608feb8f
2	1	2022.114-00W5SJQM3GQ6A	\\x7b22616d6f756e74223a22544553544b55444f533a37222c2273756d6d617279223a226f7264657220746861742077696c6c20626520726566756e646564222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f73223a313635303832353932397d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313635303832353932397d2c2270726f6475637473223a5b5d2c22685f77697265223a224159384444485350434d324447374a4431595943354b54334545565739453133355a3059484432525434513252345342464557344457335833344e484b4d583253304e37444236374a525938333843383547315257535a4145425a3431394d4e58374b42454547222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032322e3131342d30305735534a514d3347513641222c2274696d657374616d70223a7b22745f73223a313635303832353032392c22745f6d73223a313635303832353032393030307d2c227061795f646561646c696e65223a7b22745f73223a313635303832383632392c22745f6d73223a313635303832383632393030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2243304b5742444a4a35593048513554304e35425845445757563130474d364753514d384d4e374d384238345144525a445a385147227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a22354a3438303846305652435052484243385a445050423544344457535434394137445a4550434357424a574851314b4852535147222c226e6f6e6365223a22363035434b51333443573556344b5a3439594e444a4239315056424a33354e375758364d5a305443435a4b5035474d3534415447227d	\\x63c4f7c34195a6ed0dde5bbe0c162b888ef5d0b579be589dc0d3919eb55fa921ea9d21b6a5abb41cd6e28afe3cdd5865bd96f0e502834b8ed9bff07c37867675	1650825029000000	1650828629000000	1650825929000000	t	f	taler://fulfillment-success/thx		\\xcec53cc78dec77973b78a46f0dc35e42
3	1	2022.114-00V3EJ3MKCDJ8	\\x7b22616d6f756e74223a22544553544b55444f533a33222c2273756d6d617279223a227061796d656e7420616674657220726566756e64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f73223a313635303832353933357d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313635303832353933357d2c2270726f6475637473223a5b5d2c22685f77697265223a224159384444485350434d324447374a4431595943354b54334545565739453133355a3059484432525434513252345342464557344457335833344e484b4d583253304e37444236374a525938333843383547315257535a4145425a3431394d4e58374b42454547222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032322e3131342d30305633454a334d4b43444a38222c2274696d657374616d70223a7b22745f73223a313635303832353033352c22745f6d73223a313635303832353033353030307d2c227061795f646561646c696e65223a7b22745f73223a313635303832383633352c22745f6d73223a313635303832383633353030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2243304b5742444a4a35593048513554304e35425845445757563130474d364753514d384d4e374d384238345144525a445a385147227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a22354a3438303846305652435052484243385a445050423544344457535434394137445a4550434357424a574851314b4852535147222c226e6f6e6365223a22524858365637533750333048533451345252364443584a5657434241534a395758574e34525945524a5947334544424a35543930227d	\\xf5e23804fd9d9657e8277a87aba0b452c71dc79d144d23d44226a83f4b8d9e1faf88df7a83a4459fd5d8a9b9c948b693272d86dd54a056ede44b82d4ddbe3098	1650825035000000	1650828635000000	1650825935000000	t	f	taler://fulfillment-success/thx		\\x93cc962013e811875aad40a7121bb900
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
1	1	1650825025000000	\\xfb22f276cfc9f2860fc551834bce27f04a654a6ac1fe4e70d5f398c2a0565f58	http://localhost:8081/	4	0	0	2000000	0	4000000	0	1000000	1	\\x77e9660271d3ae3d39512b172cc93b852cc7d4d2b1bc6e03365e9595543b65061fc0a68c926cbf9c6df934a879f4b9181737648711c147d23f6009548754830e	1
2	2	1650825031000000	\\x4e9fe3e0730616b81d47f74d78dc5c6ac8d5906e51a1a89e1d6b467c882440f7	http://localhost:8081/	7	0	0	1000000	0	1000000	0	1000000	1	\\xf078d5c3a225163d27ccbd634379f37daccbb67c0d61cb0f4834f7172965ce1192eb24f2808a258635e701b87c2e64cf80c5fea4a454eb2de791c171efacbf0a	1
3	3	1650825037000000	\\x2da7c6bbf84eb9ff716a4dcdf215543745ab1c796957adba2dee9ded6789250f	http://localhost:8081/	3	0	0	1000000	0	1000000	0	1000000	1	\\x8f4d6541f60b24621301846893369dd6b4da2cc0c9fb13d81457459b6d13f24044650584492a4e2d4d25473c80ab02a3624bbbe9246b5339ab25b001eca1ec08	1
\.


--
-- Data for Name: merchant_exchange_signing_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_signing_keys (signkey_serial, master_pub, exchange_pub, start_date, expire_date, end_date, master_sig) FROM stdin;
1	\\x6027c5b6522f811b9740a957d7379cd8410a1a19bd114a9e885a0976e3edfa2f	\\x21a32844844732f30628075833efa8e6fe025589e2efd9fa2ad7363162c3a148	1650825006000000	1658082606000000	1660501806000000	\\x52410d223fd9df23784b769f27a505e0e3a210de3854a9795280900577c13a78583bb3f3cb648d4ce19bb56949d4c3439fa4a2acb8837da070bab000757eae05
2	\\x6027c5b6522f811b9740a957d7379cd8410a1a19bd114a9e885a0976e3edfa2f	\\x6191ed6cd32946e87cd12dae1d512a0f50dd4b9bcb61c2bc46d4bed37eefca7c	1679854206000000	1687111806000000	1689531006000000	\\x53c3ae2ce45e685d41db1c560aa8ee38245bfe9aeb534ae34d3346fc81ef5cefe87bfe4ae21603748c07972965ff0b668d2fe9621e00264d05d826de90e06c04
3	\\x6027c5b6522f811b9740a957d7379cd8410a1a19bd114a9e885a0976e3edfa2f	\\x700f2638c9e10223603dbca47031d578938625ce15f34a8bab886a7a257da93a	1658082306000000	1665339906000000	1667759106000000	\\xe0a97f028c221e73035497b039eeb7302eeaa51dc6e364ae09eb7f979369c2ae35cfc270f8f14d3f28c281405afdd5b81f34baaf1f46e609a2652fd91c31860b
4	\\x6027c5b6522f811b9740a957d7379cd8410a1a19bd114a9e885a0976e3edfa2f	\\xd132aa7c10df3a80769df7164b8dbb6ae4fa75f539af9018a745c1fa328e6be8	1665339606000000	1672597206000000	1675016406000000	\\xc8cbc31fa11e01868f7d05ee438e291e50c67a583e03ce42c6790f393005610aad0bc740b3d0897e5c275af45f219fc6dfe8661a15d00c53090dd55ac3ff1908
5	\\x6027c5b6522f811b9740a957d7379cd8410a1a19bd114a9e885a0976e3edfa2f	\\x1836181856cc22a6aa2df642b7b735a6c2b6a709010c236a7571d2f1989fbc7f	1672596906000000	1679854506000000	1682273706000000	\\x4a55d9967650acbe6ae5f26959a96f82eedf0c9b1340cc983a7743d337c7e42186d9ac1916a9eb65f8a236c84f57a7bdca8dcbb051a5a304873c1d34c0a1cb0b
\.


--
-- Data for Name: merchant_exchange_wire_fees; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_wire_fees (wirefee_serial, master_pub, h_wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, wad_fee_val, wad_fee_frac, master_sig) FROM stdin;
1	\\x6027c5b6522f811b9740a957d7379cd8410a1a19bd114a9e885a0976e3edfa2f	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	\\x2a3a8d8aa134f1c7fb8b895e834c07bd4b78d80d007c5e21e94c5b09c4770fc5a4d459fa6fc835d0da7180b55955c1cbee640e7c008388c83c0da96d8d56a10e
\.


--
-- Data for Name: merchant_instances; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_instances (merchant_serial, merchant_pub, auth_hash, auth_salt, merchant_id, merchant_name, address, jurisdiction, default_max_deposit_fee_val, default_max_deposit_fee_frac, default_max_wire_fee_val, default_max_wire_fee_frac, default_wire_fee_amortization, default_wire_transfer_delay, default_pay_delay) FROM stdin;
1	\\x2c888021e0de196c456c47db6b2cad23799d112a3b7eeb319c5cb91b8671c66f	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x0000000000000000000000000000000000000000000000000000000000000000	default	default	\\x7b7d	\\x7b7d	1	0	1	0	1	3600000000	3600000000
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
\\x1708069741d94b46f0d5832957f09e3c34a55bdca747980ddf768bb226d5b273	1
\.


--
-- Data for Name: merchant_kyc; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_kyc (kyc_serial_id, kyc_timestamp, kyc_ok, exchange_sig, exchange_pub, exchange_kyc_serial, account_serial, exchange_url) FROM stdin;
1	1650825025000000	f	\N	\N	2	1	http://localhost:8081/
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
1	\\xa44498f6cee422d9d10ac843542452ff849638d2a95dfac6c72ad852c65537d760b5aeb55c78dbec8eb36d0c0e49f3e3fe484c52bd5bf4d76b4901f72be6630a	1
\.


--
-- Data for Name: merchant_refunds; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_refunds (refund_serial, order_serial, rtransaction_id, refund_timestamp, coin_pub, reason, refund_amount_val, refund_amount_frac) FROM stdin;
1	2	1	1650825032000000	\\x4e9fe3e0730616b81d47f74d78dc5c6ac8d5906e51a1a89e1d6b467c882440f7	test refund	6	0
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
1	\\x842a7e464d44a939ee0f0cb4917798449fbecc5d00f9ebeb1ce044882bfc059c06cd7b591046a03feb289772a8b8f349732bca6bdd8d2abad79eacd92d0a6208	\\xfb22f276cfc9f2860fc551834bce27f04a654a6ac1fe4e70d5f398c2a0565f58	\\x0f0dc222319a6f6c7ccee4aeb49a88bec38928a25f4e86bcdf224d5747d14f7ffd3ae6c0ba45e8d6dc803d935693ca05ac7b0a47b8b00244a6eac0e626556f06	4	0	2
2	\\x6a0c5f5a40c32277d9716643a4fc7d69e2fbd48fd5e96a2e2ed07588260ebb65d4f88ee232702c33f5ae316e5d7dd9442adca0e6ca949908737c81c205944488	\\x4e9fe3e0730616b81d47f74d78dc5c6ac8d5906e51a1a89e1d6b467c882440f7	\\x69f61f3508e7d9f54e626ef9d74ea3c71abfc2fe44ffbb12940a9c5f392cf7ab91fb13014976fb3985c8753d64246b1976fffe6f8f8dd48033e6d1501f134c03	3	0	2
3	\\xac603e3999bf7ce2ba9fd86c89de9aba133fb14dc9256a6136416aa48f8145a256f3c4c954eee35e4f4c1dd2e5de574c3846ad9482ae9a34cb93260eeda64e3d	\\x4e9fe3e0730616b81d47f74d78dc5c6ac8d5906e51a1a89e1d6b467c882440f7	\\xb170cd063c5b0f762cbe215c6ec9c5b959523d36230ba46074e863355430f0a940b57b0b403fecc4e5efa8e512ebfe8b11d5ef9647a7d667fd36daec6e113005	5	98000000	1
4	\\x341b599dccb5d5ac2550e7782c4e5c4f8a54d3882747bc248083c53645ab32a953e37cceb9804c820a414e860eaa33b3d0f09303cf8c377d2a950a7f99fc9172	\\x2da7c6bbf84eb9ff716a4dcdf215543745ab1c796957adba2dee9ded6789250f	\\x79b16f84e77b7bd699575d132236a7949cf3f7cc3018e53e45daefb0b36519cb9e4c3c06a8df751fe0c8c4005135bf39ac5591f961c23352d4cdf9dcac17100f	1	99000000	0
\.


--
-- Data for Name: refresh_revealed_coins_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins_default (rrc_serial, melt_serial_id, freshcoin_index, link_sig, denominations_serial, coin_ev, h_coin_ev, ev_sig, ewv) FROM stdin;
1	1	0	\\x86a75e8edcd7c7a1c623b49652a9fb631a0d44979effa54fe89f8878ccd0d487abc5d9340d7545f7de1d67a0312c354bbf297775a1d04bca3cdafbc368b44808	307	\\x00000001000001003f010a70f39be27e4e5e2e603556a8a7395527b5ca701e5304d2fce03aee2838650b74cd5a66a55787fac75171b71a4f96d6216e174c20616821dfd7339381574a5858060532b9acff8b73150e74734483c8aa3bccad95250de8f53e1e537956f9271b399639faea501ecf887dbb86d3b767b882ec34dc4aaf5c7dcb7cda80fb	\\x4291281d9a0e545921ea88183c077d12f86738522a4eaaf7dc788070c15c8d1b48e493ddb85a7f75dea5bcaff4f97ae9a599ab14b9d5c13e5e606567d9c10471	\\x00000001000000014ce32723a965c9a8c7f24469f66f8a9690c1589ba4c39848e8121374f2aedab69c7bd1609e2503b33de115e2bfbed3c0d1d77e05138bbcddd3385ad0da720d17ea3cd8070c00db24ccbcc75bb330e00a6bc48dbda9496907e8a883edb3417a2e95adc1afd4b9b20d8a3f208e3a0862d4433ec88c6c78703e94a247297bc3bfb6	\\x0000000100010000
2	1	1	\\x0512d72a15e6e9c75fb2b52bfaa456981782ed9f66cb5053fa6b0c87099357494d436eceb372ed36017e0afd5c3353800c93abf8d59424bad92260de3ae44903	236	\\x0000000100000100af140d577cd215e69c4fad6d10a86757c025fab7c5e49c4c7ec67ec42113b307d941083b7053a9db684a0dd7b33265af4e0dcb3169180a276ac874a637b8f26e95c1dd66532b02111e9add42c104205d4a5f91cb18d7f98e04dbc2d5fb789cc72eb0435c3dcb726a296f5386db644244967a75df512ea6628f6074804160fb71	\\x9afebbfa3e079c4af823588df991f6f9b3ba571f7c3f7f7048b809eefee1ea34eab1a06858d31519836947318caeea6c2d8078424df33110bc165f7f8459700e	\\x0000000100000001b93a940201f61d331f7264b458aad040d2e04174d6f96fa316708c4803f5574a036635866c37c13485877c223a659877c2e3f8c7ca5fe1553540bb95fd1ad2ae82cc5c1b3765c7f90be29b9bc38fb7f1397701c23663504b3dee86ff1bf7355dabaec4648dcec797b5e8f3d0e3f3cdbf8853c376869b83f4fc90372700523c61	\\x0000000100010000
3	1	2	\\x76ba0d083d3ee56960951fce8c380d8935b1a1de94e073819bbf113895d67e5a05a0d1c4fc4e4ee1754a75af930612275f906fb15c11bde63d0e000395a6730a	220	\\x00000001000001005a404fc61bbea763905ac7b50bb1e09b01a6bd8548561171331169963af523e12a4ea06ae65d1b36dc53b8f83fe49fabebfc287ec704bd5c1e6487962298f923125d9d20284adfdba230f06b5ff948123b18ccf2cd620cd0a08ec0d45dc32f800483e4b40b5b94b38d33f2ab464caedf7070399d910dcea8f64f9abb5f4ba105	\\x2a5fcf6bda3d52d7a348876a78559d648ad3ae72718b4e21a032d6ff1c6963d78c8d46cba1d4772ee6f26f831a54157d94b125c7a5f64a3b9d6dcae8ed14caf6	\\x000000010000000185b27335c038a28327d1fdc3ee6623d715a0b624caafe6d0af367ce2c65d8d884d3e3f05d29fdadc526669b807b663e9d54672d8a6a8636cc4233fc62067cf20b9d506bf63d4d61f5bbd3133847bda32f433823969fd7b39b87dc70d3b191fa19e4620e95d3729352d7093c6125954228cb28c4dfa4fe0e10a624cd37bd0e7a5	\\x0000000100010000
4	1	3	\\x85a73c5b1a63bb9b22e840a671bb9f84e9dce35c59bcfe77c23fcb8c02e5ecfc2d0982430fcc61afa030ab30d2f1a130e75ef4540c81c0fbfa3216b5026c790f	220	\\x00000001000001000c4173752d1d5cc0496400556089c2f03c78c8d27a8cfcd114c4ea65807b5273b682c64382b2888db7616a84a741aca01e351457e46ba87b233e3fb8aa46e8685a8bc5a7503e5ecc06472df875a00ae2d2111c0e87bc691c668948a150e0d1af04453b1c4677ce5865d89301890eac4fbe48e26eff0701cad9fdc13c3f8857a8	\\xcd5358cf91a3b7b60454847de72bd6bdf40a454e460612dc07d6645280dd4d8f264cede08bda1b6f927ec744d758bc753f2c9810db12d6567a0a7a8d394cf867	\\x00000001000000014ca1b4e17d19c32b4d8a06ece06bb5408b3694fb3e224f17aedd924b882fa6fd578c6997a6e2caf79171f6d0bbb4f45708dcc11145af56544bf0a369e4c7e5817bfdfba2a620a7000dca8fb4b354148b5a31019ddf95b1675f3a47916b93e90f71ea5155c1f130dd84d4587d6a609325c378ffc2d332a69b23bc3ff2580bac93	\\x0000000100010000
5	1	4	\\x314642fbed00031fe55e0656ac49cd45108b3d34edb32264f8c1e39445f65d962f31b3adeb38a7f2c12b1ae383e60b825d880cb64d6ab4ee901b7bc68107ad01	220	\\x0000000100000100508e507a2ece1454fb8f9a91101a5553324946aab9d8024aeaf75d4c70166a2d77afd08990fe13f4d4e9372ec30de755ac98fe374827173312f617af4804a870f06d53df3a098530d6d8203bf39181c84c635b6377871132f7583f2e74d4d10b771f52fc6a0c24ef2ff4528167eb522cea43fca5d697ec849311f5500dea53e9	\\xd6554734bba1b4fbb5c556b69211656bee729926da4b7c8c1570ed7b4789989f95a3995e25293495960d40a875d6ff819b4ae593162b0ae433daeae8df7efbf3	\\x00000001000000013a778a323254d3ecb7ca2186bb0cb563871723e31a8123c4fb9d630a3976b6a483c8cc3bd898719f193abd413285c504577c93dad3ce329267e097abc6271d71c9c054de51ab037628a4745c4511c03293103e7a799a6c4790ad4821b61b2bd33e7683d02b44ac2c688afd8bb9b9d1a693f492b018c865af45bf4503fad990e2	\\x0000000100010000
6	1	5	\\x507f81917fae10b287898c7a9a0ebe47b2aca3c2cae170cae3bc173e8af96c821d109bf33e9c170827dcd194aeec767c656e3247f70cb044a378eda5ab54d704	220	\\x00000001000001003cdb53c653225c8e04454c7acc7020cc6d89410e4bf108b7c06a32dc611b31ca64dcfddd105c3cf71052dec44ad3f297aebc4f99795aff9a7c8909b820fba91d68bf37b365e957ec99287f1af23cb2c895cbd8050023a7100f33303f0e4bcdc39efeb67c4f3671f8895dfc8bc4d34b68dd8f7409bc6b4c62fcb202d68bf44b34	\\x8ce615cde77d49e78fb26c99cbe9093142f9ddbf3433857d75121dd63f003a49e449ae0e05f7fa5e0d75c61f311b23c14bc3a9a332f6a3faa3eb3c90bd41e49e	\\x00000001000000012f738e601170a9ae7d603a405673347c16ada0192fe28098102a57e92b28f6c117043409d51968a52b7602a98f51e0783dec4929450dfb11cc4ca4b24ebefcdc64e79efc41925ec6761bb5488707ada4f6b3e8eec6cb303662486807ee36c6e2538b8069eadb6eb8ad72f10a5f29d16c29981e19dc12ae7b18de2cbac099014c	\\x0000000100010000
7	1	6	\\xfc0ae5ac7d5433ad1ec350793c8b9fb43ae3a43452b71d343836bc8a321080d0e1ee04b9ae646133df2dcf21b1c4baa53f759b06bc906d57b16ceca3badc1608	220	\\x00000001000001003aa6bdfe3cbe4307a676887d4fb1167732608c6d2bdc7dccf707ecc9fae415dbf843a59b111293dc70261d5f9c07f33c1d33a57c0fd1c28feb26fddd0822e04e0e02d690c38c4cf1e07c78878fab50b1c7912a6a603f45e38690c9a99470be156bdff9035886a5fe8a8db71740586283142cb4fed3e927fe2b549bb3fd8cbd82	\\x81a2c0af5e73056e8e6caa86108ee5fa5d0b168a03a42b2e232e697709ffa108ccc4c0dd93ae3220c48a61ee6749ff26ab8bf32b1515fc0d5d11f50a66051a4f	\\x00000001000000014c9df11b01928e031ce5188de0799a78d2a267fedd019745049d9ca5c2a7c11e5e1860aa80f3acfcd5624338a0598a26727e202f177a601fbfeed85cb4c10cb541e31bd5440a5d259bb589ace8bd66c714b353e918faad6cfd550ea4bd05fe8f09fbfbccbeb52e453908bc0b681ffb0368248e5948ae83d7d81fd25c255976df	\\x0000000100010000
8	1	7	\\x20d5028c7a414c42f7e06e7342608a2357b2dd445b81b25961c4e118a1b216134692f596eaf542a954e073ad9fbea797d6dd2ce906e0f14659837eb0d1fe990b	220	\\x00000001000001002ea1f3dc916727af228ada82095b2e608ea7a0905a9b4e9ba7c8bdd425756a1144890dd32a74d295a3a96d40b58bf75b5d82371ac35806c4a7dddfd0be652d517fc53c975109a1b0f844e77bc7dbe460a70f4c5c2127bca3c57a43050806e872a937198e14f966a7c685c5d8592fc5b7df5ac68b740d73ea83ca62e672b39b96	\\xe204bc42681662fd24172d21ab2bd7d9207c9a71a2589761eec3214151c362570eee138c1a8cf650cf5c8a61e2fd2933f6be402f55924c8010e0cafc063e2cd1	\\x0000000100000001368ac744212e331caa3c7e62f4b337a9bffe2a08174dfc389ddb925f4d2309564157030a35005fe9b8b1c6bc096471dad00b19aa918ff9440ab91a4ea474df62b2bfcc775da77b88f3d862cf608436f578964e573a04231cd808b27c4847fc7c214d5af7de21217c419e404d440c934e707fb06a6627d6cbf3bdad1f26bb7b48	\\x0000000100010000
9	1	8	\\x4ec9c69a6264917618e3353cbe189d06f900de7547a23808cc98b633d4f3ddb80a930cba04d3ea33ebf18b1b88d35632e5079d0b572178e920bdb8427237a20b	220	\\x00000001000001009068eb7de91607a3d13a5045893a326f9aef8fd9aac7892161978fc9e3709fdc41a61dce68e572a7dd25e0700980c3f226ee92083c1a95fe4a237430b40f731ed8f2816f73bb03dc9da4b7945acf0a7cc02d11e1ed204c46c7def80d66c1c47a7e853d5f3cfd6ba59f9cdb334fe8ef45b23e5239a2f2beaf572bccab6fff23d7	\\x2823146f3bc9332cd822282964dea3b88b6a8b84d212e96ea2aeb598a3d14dcf1148b1f946acd93f4bee499a967d417792c4ade7e7aec4841ac47c9be194aaf7	\\x00000001000000017fe6a1b79bb92c809e5e471309ec3502fd2c686270bd12e6c34d7113a888a821b2948627373b31276ab71bc68e6a47cb0443dd7332b3269007153ca4148704e3c351bf2e490a9f53cb148190051647f09bf16bff2ff16a8dc4ec8e323421ebd1210bc002a928057d4c71aa22a66ddf61a6eae3bab68e6bc3135752710082686b	\\x0000000100010000
10	1	9	\\x09606056a0219b787a120d3bf741331fd5b5066feaddffbabdeb340d34f08d05f3008e1dcfb4d39609ef60e74e8f33bc9bff2b7b4bb5fd1b8ab78539811de20a	220	\\x00000001000001002a26f621563c53fdad61341661a4619183b215dc9869524a66a6ecfadc5cb89f61108eb27ec6a5b497b71bb4b9a8b79a203f41a8d82293a8a65a0d9f0767370a4a1b763f6dd5d240d494b1d5caebf3bff61f0b7d524265170a95954d509b58c28a2607005d899af80b7186623ede52b6b491a1bff6bcf3cbed7b8914e0e82e19	\\x450f9a676045f1c76859c5db1bec2ce89b39a25a23fa8cf84adc1e3d70354ab3b3c89d1684433d28ae7c6285e5758ec8299460d0b517d6c60d266434ae5e5eec	\\x00000001000000011228d35d20f75d0bfb2d2b6532b4da8763e956ffd2d2ba5b426cecd83b3f1f3ce40966c7655026aca8bc0a76d252f4a3cddb06a3dccc710d7ee95ac64d14d1e8fd0c6f623d8d5fe50ebe3be68dfed5a10b20664d27df17eb29e371db40f38858768b5078d64a8417b6e6b8e2b3a43e7d0658d3cb9c412a9824133e1fbd40d87f	\\x0000000100010000
11	1	10	\\x06710ded3a3f37dce9ec162f20499ed0197032f7e73596eab06ead18ab09d0ef93f692827fb17c0bc152cb1da70088cd9bc3376cb87513a03890fde5e7ab030b	384	\\x00000001000001007f33a1384fd1a684675c4e4488fa525d21fb22614c34c36dea0b710b336242bce106acc522f6fdf06c2438bfa91903d82a45b1849aa23643230c2235038753107e59f54c1f6a0424297e72a9113ca0a05bf78566fa01b6079bd568e24d479683adb0a9728511400df30f2f414a6e5e663d36f58a1d62678d9066d168167ac3dd	\\xe39b44fbc2501f1bdb67803c4cb82dab4779292dc661cbba90cc45c14df5f7120c2b17a5bc4a84961ad497159d097434fb4679cf1614acab535ab94b01ca38a1	\\x00000001000000019afd645ac50ef2dd655fe682697212a22571ce6c254d044ff49db1e1414972dcf42b6bc021470e73af549740985a835201c495ba77468612757b2d136e587105bba322ea1ee0cd5ba74c725e462664b66ff1ba2777a4c2ab487592de7fc4ff102413591e0ab8dccc6a0cb5712f1846a8cc08710d14e19cf7ac549c52c138219f	\\x0000000100010000
12	1	11	\\x5756f4b43ab69150fa72dc25d8b58a4915c4d94f9e49f44fc08808512c1a5154b971b6b2140a9c721b74a25965aa1c48548f3362e31ff9dce39efb2408e9d40c	384	\\x0000000100000100a3114339967e20da0673409469994f48dd45a084762d4ed9069233fa890611e7883784176684b8ae6602eac30fe97fa3522baba8af4c21f3778ddb362f3477ca5e4c96db28754d47badab62e59186dd9e3b41233f93cd459a08086225adefb6ad540d4b44b7f1ffc151b4d71dc1525e83db39767f15dec8a4fc33900682c9c3c	\\x7f390c0c17cfef548f1743b51fbe7eff41d2376cbcf0ca703679c6b9e35c6958c101f49249df24168fce5dcd461f7ed44d4282d941d9b4c1df7ba9868a5f9285	\\x00000001000000018fbc54576c31fdf76b47f1d455d60318f653dfe2b9ea11599a45225367c1ff77516c67bf1dd245ae8402dcad388eb0437ac54085e5f2beff05e2a028d88340ce3a63500f660942817dbb37086ba908cdc17aff2984055932829d35eb90b93f9f7f91da167af091c0e03dafb4119455140ceb2c9df58c919a4acb52ddd97fc42c	\\x0000000100010000
13	2	0	\\x7fddceeb23a136e54324197b0885bf1a165eed5c4c143ed85f80e41fd68db6fe6a7d9d78d5218e1830c943be3f4d1da1444a8ef1d0c4257cb2875e43c2a3570f	307	\\x000000010000010046a91a9fc7be2ffa4a44acfe6d6a879e8724b03a2187ea4fb12de9afa8c1bee30e88896795f123bc89e8b6f8f3e0f6b8ecb6a32bcb3e408713ea6c5f16b9461fbe7a97dabf8a597055c5f510329149cffb88a7de3c6d8527c62679dedf4fab9abfe4affea35703f507b1a887e9ec10ca9dbaa3a1d0867e9c03e2396245e4c1c3	\\xdbb5b630d9025d02a0b56dd8e08a2c81ee70a167429548e953accc79d4c53359f710dd4a7175336088d87a025a7f3ce2a14472cc3eee82edb77b931fd985c30e	\\x00000001000000015a048f6359c9691493b7354825753888bbe75959a38a435dbfbb31e2d9a1cbfe457d274c14ff93146ff2823dedc2ed33ca948b0d1698529c528ccd28e13da6a3464f2ed8ef1af774eee6247a3866a7d0288f46786176b2d7e67d8e15687e85ccb2de4a7e0661195a9a3c527ab418ec8fd8966083429b73cae58efde064fca17c	\\x0000000100010000
14	2	1	\\x2119c8f4cddb2aeeb1179401b3efe33951b091b48707dd27ff5a491c6f1ab943579029ad5b87d74d2a602c9a83b1dadac56a0456e84a1d72c39900def2b5360a	220	\\x0000000100000100043d140dc44ed116f7a7a9e3976a3e3f0c9a2511eca7d06377afaa370835eaad5b33da97ede54bedf233998e6a8d96cda564a9a73086809ba838d055bf2b17e1bcc70c7be2be2ab5023923587c1d8c9a7b384d80eddbc7b94853e60a7dccf8cdf33809491447e269506c204feaf20c194f440871fb7b82ccfe9c9e32a8eb1572	\\x5d780df2afaa3a487dbe5390bde3b3979959038fb9508d74ae82092c6fad432cce5c151f0f64b93a9acad599856890e9ebff0f90c51633616a2b5b2e9e5fae59	\\x00000001000000015bb78e032fe0fd26a21858abf37daff2cf16723658b3c5c79dca2a57e441b0ccf06cf0311e6064ec6d9b8f93f4113c85510f406d6357310e6067386931e99bcf9c2c21a2defb0350c78c9d529737baee766566cd0703be5a070d09051db10d791b9410c49a187521d5b0385fe1908b0d596d4a0a8f8b518446f8432e324d5efd	\\x0000000100010000
15	2	2	\\x6590d39a2834fece8abdc4d309ed9e5f0dac78b1d01efa6fa4dd971091537705d04616875071191a38a5f7e1174e9f41d2bc7c2ebf3b6595eab716cf80d7880c	220	\\x00000001000001003d9f7f6c2eb8431b97427deb4ec540503597bcc927ba3ec8f153ab8b480cab121998c4c453b0f9ed867a8feeec88ca7045bfc139ae859127b07a5fd416e35213ff4c1091833eef7b2f03d678a18f7d24b6406d842ad9b524d5e040edb8ba0366eaa6ff3f5e5c9e48f970035d75f6385be81d51561b0f9daee6789221a6ec66f0	\\x1c438478406279cbc0e0cfda46bae095ce94b1d3aac9575700033461c0a43511266918cd1617b0cbace4e74bef7c7a92dbfda4952a01f24bf45994d38123621a	\\x00000001000000019388f41693c8b9c58cf3511f4b3ae86cd1b74d3d35f201a46958b70a7900308442ed6079eb585ae020727a96889e21b5bc450dca86002fe24383db00f4e4042eedf7f7c07f5cd996813f703830a712467fa8f1b6b1f13c98852cbd52d1f5b479c03fef563e08d3bf45644cb26b3d558dfa348056c8ded7588134747a9f16bc0f	\\x0000000100010000
16	2	3	\\xb26d9dc64205d6b62e971e5a8caefb5244ef55af5879cfef975970533cba90e0f4c61a5a386cd5d5b6a124904f651f7c99bb93aab0ad200c77646689af95c409	220	\\x00000001000001006a1289bd8c07b7530d122bd58b33a5a3dc512f3db810a2eef3f27c04c448ce4d567fa0dea09b5654a7df10540882bb4e5ee2a3cda7e9e88ce157fcfc7ca49dbac460f314732c74f601fa6a2f09d2a149e5dfe2de39af37caee40b3166d42d37031ae7c81e275b1eabc3cf570e9b75d462f4c63f233ab3ef0f122ee68e3253eb1	\\x87fc441c7f43539750a7630f7026ba26b928666713102756c64587c945c304fc590bcdd33528f69241ea91c411655a0fb2d64cfb8229ffb8d6fcbb519235f47b	\\x00000001000000016ebe11ad066d5a47dc8da767f5135ace4eca2ae86d99012d76d44d42b8c30e36c214d3ffa14b53b40a0799ddc13d2de494874cfd3b184757d6fa570ffb3e70564cdd6c3a2560a9d70fbde6db7939592c65e59fd631718f1898cea58224e4010d66931a407d9b7dce12fb4c843261ff8d50b48338e6d2ad3b27c6ab8945f0e930	\\x0000000100010000
17	2	4	\\x5376c1faff42afe8c92edbdba15ea0106659974d4ef66ca75e7ae2df6e3bfd8e977751b0069f377dc6202d011d8c5a7e5a448ef4dba76a42e2929f9aef243b04	220	\\x00000001000001003c5e88fab78b2f35bef74638e21a84d78647cd148525085ade77db15140adc973088928bc9abe2d7f9e86fa7602514680dc329106c3b396ce3abc44db4a8bb94384734b17a3072b94a6a1dc313f7474dcc0946a16aa6779e27a1df57977ecdab090ec09c81c94c8566ae675ceb717e5897a8cec98dd5b596daa7e835f10542e2	\\x662989dd3d16888ed4a15b3f42ecc1035a57a8b0afd282ab9176c85734b2ba9f2df03c97fa183e4f4f23d984198a824d42ce34363af5b8e1ef9d49d49ac83bc3	\\x00000001000000017c41f84a74dbc00d0d509bc6516fb3acb23c68414e4af00baf70f43f3196511ab751e94ae1d1f44a227af32c2151556167419712076975c01ff3e648dd81e931694a3d72444c251d6f6cc57c25d34fd905352eed1cdeaddcb40b777862bb66b0fb20f69ea7387d86877669201b2bc34835745e6ca9bd20bf76a1d3896ce65f33	\\x0000000100010000
18	2	5	\\xce29034733faf1ce3795c8766871061ee79b85b88614637d9c1a0a1ec2ceba2d7a9df0ce5c6708b6879dae2f5ba8f5eefef6423142afaa01a31eb44e93ac3a07	220	\\x0000000100000100236d4f0dc759a6e9df06af070dbb9ba99bec87327c8e349acaeaf1515e000ff75c06ebb54d9e91523f11de6243830c862bae1ed97e89ce2fd40af76f59a522bb2a796517e05d4dc5215db35b08e98f8e213cfa68a23b668b01ffe6aa527ba5a73f1545b21417e9741e274c1f7df8b768832359872ee8eb7df372d7db861eb99e	\\x2f2d6bf0e7d935762bad7ef20bd7b4a398aa78d51cd0323a1541e29c5cd42cae577aa788d79eb30577c14748c51375454bdf7e31cbe9c207675a58584b6ffd7a	\\x00000001000000014dc840b64a10c12ac29982fcf170a436391a42d35337079d3e773e2591b8aad1dd6f310d1686a4ecc570932a96983186877393b141a1ba75b3230d7120af42ea8a06db4fbbe025b226db118453441432757d05111c005a3f6f354ea0a84237cc7fbddeabfd22aeec1b33f777eec1c83038d77723a8a9600997c8615afe3e0b65	\\x0000000100010000
19	2	6	\\x0d8a1d26096fa04462a5ed58662b9b2e878c43cd730cddf3a3054af3c241982ffcb71279dfe4c10a018bd4eb0bdbc09ca798df80748792710ab223ac1acc9b0b	220	\\x00000001000001006878fa82a94d0d4450e27192fc981155be2ae1e798f4825826af1254ff04d4bb08d269590f24ca89cfaca6d084bf5486aa85a57c05b5746fe047299bd834e5cf97655c7fd04517f9d47ad7663dce0112bba21a81b02c2e0bed86cdb54b7fd7bed21bbdfefeac8769fffb24a4d94ebc90a4f691cfc438a99115e3344118e805ba	\\xa26aa5282ee2bd2be4d7b74946324a6f6c3faf8bdbcae1a08e85ec87a6962147433c0498a0b733402587a80c7ded584caaa09d4f47708ecb1c4ebd685bc6fae0	\\x000000010000000162be49ae0a74ec58c944664f44489c737e8e0e5a5bbd8d5b7d30cdeb964d1c0fda6b67016c73605d13c9a62cdc3ae0f2e9f3e0263745f088e9b2fbc94b85d9754cb7112028b7295771bc4f788064b93127dc8e97bcf0d9d8453473ab2cf15aa2db482fa7a637bfdca6399a64fe83736423516cbcb66c4b920844bc3083f0dc9d	\\x0000000100010000
20	2	7	\\x7ad6543dd08bb2d90f60b7ff1961c4572bab8f475b277e88c48039793cff649419561beddcea0869cf2d7e6a1a938889bb5574322274f311532cb48c2e877102	220	\\x000000010000010036b8f64b86707a783d6fe05cca55b2de997b1f47feaf4932dc144756513d4e446984ad6e0ed71eb00a3bb259bb96b2c1f31d4d4724d09188dff3718e3828197be8b950c0d8cae3192b7607f403fbd4be09d354f15b60da14d365e8e3744cf7b5ac8905e7046d6124d0fa84009f3951063632223e9249327e39eece85cb051f97	\\x13cf469d9b9a317f2e2ef128be93c03cc7609f825e6625a775331d11d3a28313178c7ae660ff1dbe3dd1717df1abc679a9e33d5fa5eb32f29a3d5440bcd13079	\\x000000010000000104b0861cd40637f09ed655590b8ccf544ed4a5a9bc9d4c673a08a025140e1574519ea3143996b697c32debe67f209c2bbf9f00b9a1dad8e315b4928ad9aab9a03308553a8908735d0debf4d52ca75d176c60dc58b958b48ad1927987f18b2b823297d6bfaa692cc616470acb493bf7ba55a8c825cfd29cfc911c197beaf83d4d	\\x0000000100010000
21	2	8	\\x17835345cfd3a74cf7f75c60bc3691c5966841c9d8d6e8538c4b7956901bde23880af09b6dc3952198358f438d32700808eb8153c47cb6e6f54e298cdc4e260a	220	\\x000000010000010085892cb737c45a5beccfece5c742e9c14e7d8a571faa6593253dda9f4f8eca42381cfb464d3df736da010cb7defde06308482a9a8e809ef5fc5d04c7a81f997b84b47c7371fd67007d1fa3e68f9f7834ebd5f6011b37afd5af39a69993ec1f6edfa89d62ea0c74ed8c7b25f9070d1cbdd8e19a31a5f541a587379bd879ae0936	\\x19568c2c7fdba344541eacb8bd2f35c23be366654786c73d6622c416f791815210f36c324aa8b9e35e3963e722f62f912dd56e44b76a06c58cbd6d958dc6ff8e	\\x000000010000000167ba7f93e8452ece6f8451955ed0c59b991442bf4fb7ba0366e69c4451a454d6ddc11fecf56675bc5976f0ba5d2e06e80689019a2645e8516534f41d80bf659cb88545378de745b6fca40f0ae56ba039fd1a2f3c1c7723fea3e67ac22b7b6c8b22b2eee5d2b37e97976031fbb6fb1287ad9988536177e71539663068dba1f70d	\\x0000000100010000
22	2	9	\\x4375f7be52e6e013978352b4315c2f4d756eab1c318b1100613fd455b448b0e1b0b8589f62cb6d29a107f17faef16fe815f89fd61a8c4fdfd5ef8d6eea2d4f03	384	\\x0000000100000100851e0b3a90a95dcbb502898928b5701ec374686bffdfd4720574a76f0af7528cc4cb1fedf07e015ed7159066ccd78aac1fcabaae30346d4f15b57c61f4c95ebf95c5515e7d8e308478e0f1b1ae339b449e864bdad325227f19302bd2c4dce0b0672780ec1e5eac49a5557dc43640ad6af020f4f17caea5a6ec681d48aafa4238	\\xad7c8ad36ff4f9354eed9bd179c4fd8daaed03cf94c06cfda5b2f4fb70eda1a1165842b1925b6a9ee13058e36b0d608fb6dbb5421f4677d350ec2ec19fc219e3	\\x000000010000000196dd76ecd5c40d8e0f63988203a9b99ce2b69cf93165ac4295389060d1c72be15fb29f166858a916b30dedd20d75eb92e987099eea9479cfbe0dfa701199255b575fc38d8ff1f6d7d52333030eac0d780db0403eddd3d86f39123376d81351b7e2ea7355f9b2f3d2d88bb3246696c5b45bb563fdce42c5994cc31c2dab44a7c7	\\x0000000100010000
23	2	10	\\x68a60b73e9902403b5993a6a9f0f5ec742b51c733f7d43b6b51455396969b38e3188d81785ed0da213561fac8d2fd721ef0b41f4926f27b5f84cec21c5735d09	384	\\x000000010000010089aea327bfcff0633db4db8c0f158fb5e4bebdc261ee58a9a98f5560d5d7f8ccf21e2dedbb172999e0f07134c45267c65248fcc1ebbd373564d6b42049c8ef351439cd348e3e3c15c31cdf6642a51a38a56793197492715d33b754a40e3130b2bebce9c2e96c4442cb3d9153a921ea4d71263510654fe5bb7035ff5a11be1458	\\x56b0fd1ca4875af661cb9b508f1bd535751331839ac7006bb8a2fbdbca12ae8962d63218799350d8bf43012bbd18302f2a928a33f153d581e6bf371eb0464c6c	\\x0000000100000001590f4c21322ebd0451be831efbc35ae0711866487e56899595e3b664569bf9bf1b9f5cd92b314901a37c709c5afdb3ca7efbc614b77a97d304682c549300b3ba02011ef18f469ae821537bc36a2f6091797782745f0f3766d99277dcaca11f5abca0dbd4a21090375e1bed286447bd033149f1284eead91b86ed92cb021838eb	\\x0000000100010000
24	2	11	\\xadb1ac70d697bc98719796ca6b1259f05fca010722fafa1851094eb6fd453fe4607440db15ff8315c4dabb48209c6200b972ace68abea73420af17d6089fa704	384	\\x0000000100000100720a2c6e3ea77a415ff3e02223a50832dca012455f18c800be4042e4d86cbfd482c514b4412a8d88619ff9faccf8e2934b2473742a3c03451fd4edf82d44bfe52f2dca8fc6bf1a9895f58dafdbbf3d8eb73ec72619dd80fb79bf5887f34199d2d2238697ef1b2acfbab0a3d99d231439c43be27d30df20981ec69c628c484541	\\x0eb1bd9907e1c62ada5cf2279b53980493ec6a6e68d1868d9c372f5d924ca04418f49cc1a50826d092d4ce29c830bca0d9017e5f80efc52d5ebfd16f43080536	\\x00000001000000010506b63c4285dc261bab6671d2584df66bd1673158f890b69cafefec98df3b11f531e7f16447c12b295214cecb5426f1c133d5b5097b171c632372c6579916c6beadf367c035dc14739a8eee6d9e44803c11dc0c1a1ace9335806244d216c039e883a5b851e05baba42f74f21b971371c523096dd73c0c2cb36e3556d72f8955	\\x0000000100010000
25	3	0	\\x7778e6d68346a50d4aaf83ba78156d61767e8ed967d40785fe09350cbd5040304bee9c4223e574a2120fb7aa1120cb1d01ae9b0f86788bd5665ef1acef9da903	41	\\x000000010000010021b2c5d5cbba54754111dc341b0f9b99a7ed61df49baf44dac7bd07b1e33e828c9771f9b6faca94e6032ec3ae5b9b3bf0fb0765944240e3fec1ddb33c20215fce390171a5b1914ab9e6df9076d73c6397f94cfe208e9a9e2d35890e010601b1f3286a4e794d2b619a8027f17c29954ef34f0073cb5b26880987c88d8bd49e75e	\\x20564535a123d4d3515311b1f382b197e8657c7377348aa3a08c5594d0929a88ae3c613bf97079a14ee18c98d34251d28550db968bd3c0f644c2753971f7fc30	\\x000000010000000162485f54493bb37ca715aba63209df8a0e962752a641093e1d775270d95c5740589eafe9d273f28f698759556fcaf553dbb6bef3b60454c8e5f93535c0cbcda181c11cd627676592f47151f46c29fb0b75efdae5f3e8ea543e4b75bbe03bd0e9541c4f2ce088ef4dc33107bf3956cf44d252b665c60b90e789aee93c8173d4ce	\\x0000000100010000
26	3	1	\\x9bdc1a9cddb34609a9a4a264b92fb25bebab5b5de7e9f4656caa3ef6cbb7d2569ae3af061c2e4883fed48525e38288ce808fddadbe02f46539b5852529726f0d	220	\\x00000001000001000357ff4424ce3b750d4e08160e23c9d74e9cbf01d21c6333e7ad5af3e8e054deb3080b6f876a2b74b2b19107181dd7637e09d1c5c82b169af147538f14b10c14c78bf2d4b2ee71695460742630b6efa8f3b917391243186d076d7ff54bc6087f9ffb647f6fe5672a65a5dabc1fc108afa663076853fa7cabf372ce5480fa6d14	\\x042fb7ac6fffe6505623142dba7e155d3fe6afad7bc6645fa157005353e3b8176270444cadf494867c11954800bd4bf0c5ebb9be9590accb3d7c2e2d66cfbdf2	\\x00000001000000014073e4092a9f7ffe19ba77013f83f08a1a7be0fe74e4c205c3ca7bfdf6525f78f6adb870d737fc8150c3b2c78ad86b8a6465817a651f0a86965e77ecffcacfcb3ee15d9677ccdea6eba4d8434b96eae8702d092478fe52e1eb2d9ea735730f80f188f3bc8ab3360e6b1b62fb029421a77191990d9441fa36a5a53163f5e3eb4f	\\x0000000100010000
27	3	2	\\x8a22138499054187b769b5a3e19e98c06aca154eccdd32faf6c87d6656202ebcfe37c1d98f4ec665a24f82096aa8291e79ac2b08b7dca25d50b51f2fb9270806	220	\\x00000001000001001ae6229c9b239cdfe5cd0de12aa9dae7e4c4fe359987c54f7cd8bb312f4464d5f1b98bf3c7fca713a7e4aef62660b97ad8b2d322347d5cb6236644cc9dea3015f39874850000a743c8626a691a460cfa022acfb4243fff76c2c588b5fff3468f9c23a2418352bb6120dacbd44a1cbffb939fff4b17700106b535c3a40aa0445b	\\x7e7d9630f8d580d44da9f4d66a566dc793df845cac1934d84cf32ca2a1b194f13317fe303a2ce3429cea30315fb9fc352302893cee1d3d774ff33cf676fc5f9d	\\x0000000100000001431ec74758dfedb67ec4a0b73b4b2cfe5273a7f871130cb8c24517aa93b745915926acb306c46b9d12219005f7a00f811a02b9b232f2f68b0b738112868a344502c6ccf0ab0ec774b01e55585df45fa6b82087bb5d9009eb60febf1e91a15e5f2f01fe1a9a08e2a7261c15c0304ee6695deb17223a0bb3d916a3e7721c0157e5	\\x0000000100010000
28	3	3	\\x39dbc36749628de70d01ab39289b515289b0b2a735272f2ab43a4293fa476634a4d6a991a8bfbbc3ea890f55445291bf51a6fb1d734e570f970f6ad5508b1502	220	\\x00000001000001004e310295e41c2ad84388633c4e05f5eedd83220f29eede7072a3a9e9a4f3a181999281e3c503b5218cfe7a790dba07f98b77989b088b13869a2359cca12a827095a8142b606ba6909de5c862627d210a169e816c0eff8f532cb3f54f4f2934ada1872cb22a6d051903f448b6a6b6f37a6548d3f47a5530f93e279b434d730571	\\x4a14943749400ea7308a6ddaa90948528d6a7c95a087775609760dc4293aa19496df3e30c51c8a1e344eee41565e9fa736a26202a455b9ba14df0ef83bddc3c1	\\x0000000100000001193e2bcdbf2fc63d4c706a9a8bc21a24e221b40914f216f6e6d933bfc90d7c9138ff0767323a80b70b6b91dd7a79509128a75b29b3b93471e9d222644be358d4759464644a03bb35d51b4521b53e342baeebce7ba0436a4753c93feb02ae881ec6cf83a06fe184907ddde3c98a5978a6f417c1653b0acf4454940a3d6a39a2f6	\\x0000000100010000
29	3	4	\\x8e92c76868544e414e76365768004d58e8142341745336b40343ca9eabb7edd5bbe4dbafc274bfbb1c56b0da4661430e5ed6369e3fd08f7a4df6480a48cebe07	220	\\x00000001000001008c4e5a87a6c168c8ffa19a1af45d87d9f019397899667f61e186db4966f9d64c5f86f16d864dcbc2d24fb8a483174bbc3221b6df170ebab247f34d8615dcf8a64961f084eef8f598c6276d30c7c43725d01f2d48589c4e6065d473148afd3319d9e095734a7b5c2ca9bc43ec823921f3c423ae053b77858360ffbbd0ea64b319	\\xd3716d887e98ac37f747e3b53638128d16f47e7277e3083086482ba3ad79681ff05b09321ebf49c7c24f8ba17ea1db278691a0b1ea9e96419ef94534f4e72ba2	\\x000000010000000186c13c3158b95ce620873dec130faf14e20fd82d6b8063dc9ec93b0e644ffd56876511a3186468ab24d8172b654478185691b6161e77f36bbdd62a68f1335e00f7ae34ad464af618235b3efd48c1d7bf05bb501afc0191a307ec578a4dddddcf570c6119786e3422a690853588b7892a285fd620aaf132159d33b18113d5590b	\\x0000000100010000
30	3	5	\\xf403796d4ef831dbc23dc71904c94e3f437ac052b22ac16d289df24bc8a2f8377c05f5ac1c13374e3f7c2bfc38784555cf61c76c4e8096ccb599f9afe80b9a08	220	\\x00000001000001006de6097a7e8bdebd4ae914e8e708d8cd61b54a4e393f8ba5230d7e927a155f98cca7210bb896d2518a9b9290a09bb107da6cf5b1c8c96628aa8c717ba9a4dba8bedd0cfba5136efad79927a869da45b507cb74f2458dfcf0c43718939c5a5d9b78384fcada3860ab3186750f4a14daeae5528417583ea3b6e764ad4552d2b65b	\\xf1d4c709b6bbf0c96f477680f77896c244b199123a594d469cded2df0bf6b5723d81968906bddba4e727c93d0edb8ba839a3c30f2ee3cd2aa94e685e5218cb4b	\\x00000001000000015cb5ea317b8f692bf2c07e2438af75d808b2bfaf69c3d3ed98839985278292065ca7eee75403dd21e8f0d1c3f9befc871c9d903931984a3cb3b12131d77f3ffe9453ecdc7ce35391d352bfde3fd9c7c862e276dd170d7d01ce756f770d15bbd9f57aa9dc0a313ec4e137d53fd37009283598f2ec8e00d56b84945aa803add44d	\\x0000000100010000
31	3	6	\\xa51925ad79c87e38058959e226b286fc7ab86ca418874690b2c8c88c3585240f5297cdf4fcb3a80b4307cffc5136c6e9c8bad7d752ff95ae57d6ed302f138305	220	\\x0000000100000100660623ff6b8161d3280b12a7c8f1b28ceac9b1225d89018a999e619d00d0c1578eb6dcab9d74d6507793c6019ef7311cfe726005f29898cd10416847fb73255a3f6e9b26efd296bf7734a194b3e16df99e1ff0134ab8189e894824c2e84c93fbf263c14177d4c1ba5dc46a3e1cdd2b68cb5108365f2c2cde36ae543c7933d318	\\x8a1dd7d9b9b74dd2a647f2109a7224593d46b6791b6305dd1336adac585d45d3b4e634fa12fff270d3f0ad753621d9d73d068d634f766c901df8279837de8340	\\x00000001000000018f8926f64203ffefa22bc5a68004782f67a4b638cab5edc5174f9768c33998724a27babb458893c6a0f73dd8db7b084bc76f9d9f8f6e85dd7cbf2c814175e885fb470936ec84015ded4514848c1cb0dd67c322c0cb2f7b49baef36895cafacb21ae99b24bce7ebef0b3104ffd5670968d2b506d6fa0695c9b3aebc202c0a4994	\\x0000000100010000
32	3	7	\\x245f2f7ae36fca1cafaefd8baf0380211bf30f36c933b43ace364f924ea9346d935141f40aa077308c5f34ae77d88ae2a6eadf735595cefb4d09e42c91628f03	220	\\x0000000100000100095f54cafc64b4f10b37b145de16c03c72f376f0c084fcc25ada34176b015703673545c68afee1f0630750ece1f5602d870281c0e34463e3c0bcbdf07798b1380d212d8188e6cd44ef92b57976b65726209cc0fdccbf7afc3cabeab96b2927db3e97cfe7e920d5697d1b15d24d84b710d12de1120dd76aff8d7c2040cb28a56a	\\x2bbbc9bec7a345bcecae51338a5f5feff04e8b4103949b3c114f28f891af981f6eba2c0d45c49e3892b55326be7766f9d0c810dc1139fe7dfeed9c69e4611328	\\x00000001000000012c452e52ab6718cd2dbebf24cc45f76dcf0a588f330b0a8e1e444c9c3b1123fdb0f235e5bdbf8b108c1b80397c7b4c6b37c0efe339e12ba635898dadda488454e87473ca1c5b124f2204056b2aab335337c328e8abf1e9c4ec542f72b6c4c71e811f822ea5fa873d488ecb413ac9a4f6b1ec1393de68b5870852e7c881f278a5	\\x0000000100010000
33	3	8	\\xae0dd7dff718488aa5ef87dc409b2e791e857551de5d0c35ea00dd121c7745046ed47df3e2479df990a423d0f0427081e528c3884e9c4d703cfb5734bd6aaf0c	220	\\x00000001000001002e88b39691a6614737eb1eedf14927946076a01059b6380f965140c00077f967599d8239a0628a5e9aebf124d0e2d31f90f393b547d2032c2d0f427599aaf9fce7e5663cd46285d01cff51356bef05fb72dce5118d8e9a037c7298d42bdb58bd2661b0fcf6997762249ac14b8805099eaf6a1204cd73d783684444fafe71a8f2	\\x0a6e3ace190758d5d12832b8859ae551ec05a1b20e99e2a4d1263c76276ab7857d0ebf93c72ba286e0c25f154f6942a8874a5b2d4efcaf51eea04540da823e59	\\x000000010000000135f9cb57096eb318f4e3ea99f9fa1056636be7d6c8695426079b98d1355c61e2e725c82b90a220ac61e4d75cabd9438294fbaedd222784d06987242d0a7279ac5d3edd70f269f76edf1f65de61a4db407835bc289f038cc26359140235a8c7ac2649a70f527d213013f415d4600f4b2c501e77c9eae4b896d664050d14013f7b	\\x0000000100010000
34	3	9	\\x1f1efd362fd625f66f04380a370bd0312f09771de7bef312c62ec079bb1b3665676902c3c3b852c3c787d8093ed46cb8767fe941846068e3ac0e6472ba188c09	384	\\x000000010000010062133bf93ec9d1f6f77a71b79e4539ebc899556cd9c5f29f46031186a96f8483d3e9ef895fc8336f18beef784347346c9498ae99f727b129391bce0f30931ec853aacb3d9b76ca16323b387f1fd60d07ff5bf46f9b853ef96b159b6796be12dc60219e3ce9a725e20a72de408747c224c564208eb8ab0190cdd0f9cfafbb31cb	\\x227b277024bd71cf2c110b7f35f289e7a887583360efdb5eaca9938e1b026c6271b6856175e0c9e56c42b97fd723e096e9dff6153adc10d49a22d84d55e09935	\\x000000010000000152b963cda5684f77cf334d4aee965a6bccd26440adb47560ec432b3a30c179770d8a1d6204336bcb2ebe873d2b00eca487be861eec14178a34a148fdc99fdafac3ccd4e165a0304fe209fd1801200c26b184332a26e93a362b47e460be56fdb1175f603e3ad259222f7724f0cccafc2a3cbcf341c66920e917569fb78fabe1ef	\\x0000000100010000
35	3	10	\\xd544989e0e0df34798e7491d9f529eb95205c283c3d3d8979c6ac582257a0e8e593a0684969c08d3c8f85875739a2f7e82c527e92dd3c39793e7c279d8364d07	384	\\x00000001000001003610bb7a3fa7c16e7a320d77913c7719601965b96d64a23f6e16cd3267ffb1ca73f490cc72f0b659ac86071cffa3fa7ddc27a2cd0130aa9b0e2e3815cfaa802a79c1850d6c22b36b4858436411d3c1ddd17e221667908db8114222a86141358d9f488955768c857c8790b6505a010f7038e8a5fd779a454171a7adf176261241	\\x9f1280ce83a8a8d74acfac5f323ca64b493389a73714e2184a7b7a07f6efad3cd877787ca7759f41cd700aaf27d4960aa49c018c460f322b0d1ff295f8890702	\\x00000001000000015657d20915b5f0ef4725a4ba6004be9f0417e307791a5a237476b7b77e9cecac04d23aa861df669c4c86b9d98b3be7bdda0620dcdefbc8dad46f173a94f030cfd6b5f3c2750012c24cc9837b4fe050318b564303364325e1719b90e2acd1ef88e23faa6aa339027125e8a04b684d1aa4003e09c71b405e5220a1fdeeb964d36d	\\x0000000100010000
36	3	11	\\x7b56b2beae31e0f48c47faf4fe06a3d439178effdd2519b107548104fb429c6db51069d0e504ab1e0c95df3a2f349ce885fb610a74e6ac1147856238165b190e	384	\\x000000010000010041c47c6b7c96dc01cd508410e104f13061baa3ed7aefaff6de72cfd29158cf61909a569bcb1cda34bcf7ebdfa48fd6bed1f1141bf09de904e01646e70a8c78992905eb067c1741a11d2ad1046180748d5c1c54cf8c6e28b88f114f2d4222c5a0218cc52223a007084a1d8a878e8392747ffaa7c1d35dee5dc6c900ee59b19df7	\\xe3bc6bc961e1d69ec870cbdd971ec50682fc98eda5d9085e042181128c3fd34a7d9377c0bc6a74c041737ea39126ab76a31aa1180d06170f668c7e47651b16b0	\\x0000000100000001a16f0857ce087bb0dcbbbfd284276cb1c31c5b54a46364b46cd0573b3ccc664e8d5833b679f838cf9c61e009e9c781901d0931c83e53540a5586e0ffb9cac0a29d21d85c9b09154c94633dff8b07978ba7e4f3832ff2dacc05e8a186a9d2377811041fce455b94155e354cf1ee9e8ee5f0d3069af640f24e3ee6d7ff1b658402	\\x0000000100010000
37	4	0	\\x7cfeb57c5d439fe0614c3ee6c2bb7635be217cddeb0b379d001dc9385b227c267a33057a849ab58c75449f24919f2190ff9a79637462b17c570685930981d90d	236	\\x0000000100000100b8a51674d9567848e99816c2cad36eb15c3c52f299fe17ab36cd937a250d22edcff2f0bd39e701ae8aa34750c703841c02c691708d5d801ecb0b9a46eff14492d97032e4867f1639d6d6300d3a70ec91ddfe27368759931d6f559b65b95a4e59618f885ec1298446d96468df4febc4d6dd1e65eb0b52bc753e9dc41549f2b09a	\\x0281b6f3901a1dd8d4f84671bd7f45ddea6fdbde8aa130cfb9f3f9b5f52989c089f08f3c4df3e7dcb893dffca9dff51e462696d5f800a8e40799777bde8911f3	\\x00000001000000014475a98e9eacd18784681ef4e510bbc47fbf6fdedcdae2c4ecf4bdab102c34136e47ac57c3c965be90418234cfea5f75ad17c0cc67a38264dce84bd0f6bc01f78fc65af529669de2746077c1982628e3852d8774c036a0e86d3d19222cdaaf968d41e3b740dcacbec77822503b6c6cef5ab880b1063046a8de39cbeb18771773	\\x0000000100010000
38	4	1	\\xad77248f77fc6cb8b6ffee2a1337dd2b784e12dcb1c214b8fea0fad041899eaa14050ae466aacbe10d8d13991e19fb7ed9fd4373ffbbe56438b62c27a02ef50b	220	\\x00000001000001000293212791554c93386c5751416ca601892384b623c90f33b32afb891e64ee68c1e27fb3c1c3e4a751508432790aa514c0b80dfdc0a86741a3cb7055de1b85cbae6510dfb08d78c1c5e8c5e673032cc327d583fb27ca0bd129f79bee528a8f4a650d82f755cf874cb4066da0b23bc93673a33effe2fb8f5d76bc42f6e83a90be	\\x7d28f2e894dfc99afcdf57d861391c2adb74464a1954ece32a60ebb9950085949610823a8170197d5fddb863c5288ffed9fb45503ad5350d66779a9f725fe4d5	\\x00000001000000012da785393ce3572a2beb6a0282eae3d58cbf026d1f53578e43d5a680629a328a596c57586e9b207afd1129576e69ae41941a0ee98f7afbcfa86e920a3cffe3235a5b2311f926a978255c2f25b9a41ca04bb757a2efe1b36c909748878bec22f057ca717b606819da05356f9d57a7ea7a0e5841f6257993a234eee6526f0c3bf6	\\x0000000100010000
39	4	2	\\xfc736eba70ca04c3231ecaa0daec4961d9332eafcdb7a11891c3d53f10fc0276da76c7c8c8fef9838eacd48731782de44b1400b4e9e80cf009ae0e27a60a3505	220	\\x00000001000001008bf3246b50f7380b954b09a3b6fecf477c699a5fffb1acd2d6818a4b3bfb705cb9a03ad7e0d89474b5400534ed42bbe1341d8b7aa5e9e229f18100f40140c85c5811667c2309d1099e1be4804c8a78e51c8ba73d9d7371b3ffae7f72932ed27b09a7caf048706fbaf71028f7f4e197b239c3d3a881156cb8b2f598a971688e22	\\x58bde4ae11ef2a9193a0861d94b65aaecf6164cf6e8288d6d3d9dc28ae81d74e46f0b81adf03558043e6103654353446e8891532acb937c71d974318936f90d4	\\x00000001000000017f64acecf9e26d5674a632d2cddb6d8cd6b97f58b35e5ae8c5e1476eba4f0c37df0958d66edafcb0fb67436223978698db09f4a51c9ee1772f0f126241ba0bc851289392531adb7b77fbe7ea706bbba8aa65a16fc0b7b30ce8c2d741e8bf16bcecb19badbcbf070103c027d5257f56691479f94cee02907dce2a6e7fbfda7871	\\x0000000100010000
40	4	3	\\x6383645da7e4a2ff36fb2f3211ce6c7471715e14df53ddc3692eab7c5f1aef82c7a5ce37d418725c60e8fbd7e06623a13d4fb2c16462b4c2d7863aae37241609	220	\\x00000001000001006d40889c36c0658dadc629a2e4a12dc531fa14209bd5d2fe5f9e5976fddf74f1be8d0d0a0a82d89328afba4b9fa5c1f44dbe669f382b390c488cf7de32691312da435e65c51e6211682734516ed81d057c1f10a96944467a8503528aa8258850d36e03e14eb7edac287630b67e8b4069142ad6fc001be8a9893cb5a8f4955a8a	\\x6ce1d75d550dc51f8dde898a3c0131e00bc3ab63d6bbdb1ded52ce2688cab7b6ff416c623f60a4f391ffec2dfb426a11e6537058c681cbbc4e2d583e18d53e71	\\x000000010000000148608c13311a4f4c118f216d08c0cafbfe322b7575a75a645dbf9af869cd05151260ef269c123e90729b2b7ed57e52015f6d4c50f36e4ea6772c80692ac3378e5561616f441d62d04667622c9b452dfeeb3b75905e64aabc2143d84e0f5c4f37616527e55225e26787e8e4df989b61605d4e149c2e53394e5aea9790e3b718f3	\\x0000000100010000
41	4	4	\\x4caf754e24375d6f9d0697078ac3cc112313765df61cd60830d158a008b390ad0e08201bbf704cb61e713edcd821233e758a7395a838f325453e9c1f4cb7aa0c	220	\\x000000010000010069c1bb7c001e8cd4b5d13c0714487bfdabe4145df3d41b9e20d97b17df030a2f0597ac2914fdd7ce741e7cd1120cd233f33ff1b916e9816f5f50324f5c361d70b5cdd98942139354bfe64bedc892d7153386e33cd33cea3c3fde3907dd5afbf04b250ad41291d3a2f8d6249a628dfca19c8a454513d394131c6af44f842df472	\\xb83a34d1f80c2652c3a1136476c147249e766ea119729bce8f7374ee4f42536132dcf9e1f760a4261c2b2c84ab04bc181f9c9340722a0c4372a15b0fffbf54aa	\\x000000010000000182a605eeba9689f5ea997fbcad121b150816a3b613b7f379de4c05a68e895b8b52d93265ccb5b5afadd29ad589e7151d973304eb378a80e80298c86debcb013036a0753addf4b8616ff24c86cf83872aaaba51e1e8172841eb1294ded252ddb1bc940080f281afe5834c430ce311b4f2cc5f258d32b9519c6c45b94be06c1677	\\x0000000100010000
42	4	5	\\x32a320c61dc8805a0d1e7c6b9ef612e28b8fcbf4a9c6a19b6960ba7bf8ffdf015a339202b26083269688080b43eaa2106ebd58b4e60cb1138a53176c9ee8220d	220	\\x0000000100000100155193c08a8adec4deb252de366df3ad5dfb4b3121a4232d16a55b9359a73b1bf706791fa2f790a73103a79fb7759d5c36e1c54ee8f0aa0c91ece9ade426687a9bd745a50c1a418aa91c37da540911975788aab261b30b335a7aa1d3778042aa7991d078a22d2f9c062f85b7916de8693b91f286c8ea40d5c63a5354d1fe23e2	\\x3262e415d5cac64468fb7888205276fa45e96afb905d8974053e648851aba12c1c06f5ec3fa65ece4d17819d2fb9fd7d6cfd45cd9329eff9069611b219e2ebd1	\\x000000010000000102dc4817799da0d64ee6e3e7f7fae493c936fc5128a76ec159b54182893593e7bf0d3c86bf892672c67318fa975e84581f0244a73645a4a6853d637572416055fd75c4080f197745413aa488f70354dcd6a857dc40004f1a8a20c9ae498f8c46c1a09daa0f2e5a589996ef4b21ee96685e919c610b3e98be33a0307e2a242096	\\x0000000100010000
43	4	6	\\x9a094a525cdae926de6f55151026441fec088f787eb08d4f706af06abee4eb5f0f8c67be2cf969cac49d3a87bad416e39f9a97d243269ec67be75d87c77af605	220	\\x0000000100000100025774deaecf332fa879dc4a09575ab9db5900ad701de2a1b81e80d08c444b5de4267c5bba8a88c0b7610e569ae2d15aa5285f662d9321f58b08031fb0201bdc2c172c4be22c61e89bfc3aca00f6b01f1191262499a589cbbbed4ea4975efafd9b92b15600622a1635f652e63971d1565df8af4e942363bab100bbe73bcab339	\\xbd258b184e81a29a5397257543387931050e634ba84983df39308247f74c0c4481ab8c355c9f473601dd9a122db5bc3bff21b69e4ceaddf4071411bdcef59966	\\x00000001000000012b3c208ff0cf4a8d268993474fe4560bd3e62dd492b1f3a9092cf5f5f1ef38e754138e2c97244ace36e83c9e06d442235e65ecf308e2adfd28c14614107e14f4e990d9f8d325b2af41cf430f1931fd27a590e68e8162aeee096633744d3846829a3eb6a9551c034064ec722b5087c0d7eb85ae51886aa668d075b6dc1d6a350e	\\x0000000100010000
44	4	7	\\x8ce2b9da36ea3c313e786e911fdce25db0bd4640866cd7a93ec77004704235e984bdbd047469a2e47fb1f6dc3b8c0b9e85772acd226b9f064214698249c20401	220	\\x00000001000001000ad84bef23309d093ace7e6f37366d2dabb43bec6e60161876b61e09e772b8445766cdc69a8e6df84dfd3e22220f35e1184344bdb59757fbdc50872a7ea621f05fa811a4c7992ce671bd5fcb1a173a9855570c892635a9b57b0ab2ba96bda92685e92229976efcede1d533362da3bc8440d0097e150a93d8a66fcc140af29921	\\x40e46721ffc17d13220406b6170a770b2c570eba8db4020f985ae6728fca8ad8d891f324e2cbcb9347584895649d7c003bae27a21b47b3d111dc0b2f795f92f6	\\x0000000100000001218208aac5151f1a6f435aaef2938d4c19955e0ac1bf6dc92ea23fd9dc91f942c08860bc10c99871a33f3e84c6736b33dd3a1f2386c453059d91fa0761e0e360729b489edbd376642dff55bcc1c466f02434e44e4f470656e989bb4d81163f384c574630ce68bd15d7d462481ef52a2f7df3a9bbada79cc188f7dab0735c0c6e	\\x0000000100010000
45	4	8	\\xae9da711ce18785fabfa1f02cd2c8e8c563f4c18ab4708f2eb2f45d935dca1297773810d6a46144ce239282e36d83d13dcb5a6b86ab0a1d6bbca1a2c90a58d05	220	\\x000000010000010064565b1773bad13d36b02b250849dad001c76cc9b5c0407d30417cd844264fccff0426309751cda23f46b4e18c7e754c16d12c12a3f29c4127618e8adc47c71c9703001581e5b92f25b27acd2efc4ad3d04250a59875d42c9ee2c806db2b3b5984650b8a1e6e2726087053d0268b36916a8a1b5392fc8607a78491bc4629ad21	\\x63990fbed829b71a0b7c899f75b2c1e5d46b00d34fc8c79922620df472366fdf10cbe9a57decff4724a2960f02c6101ed58483ccba08edc86541aaf034493ed3	\\x000000010000000108d577acae58dac6878947bc30629311c2032657ed7bed17fd8a730c2649747adbc1ba836e8fecf366fa640abd7f86a38e92483279ef5a699be9c5ce8b862620f43010d0dbfce9b3ddf0acbe30254fd8cf41f6946a83708a8be11d20569e0d7834ddc0732c95f66b609f0d6ce8006fb12251981149138e14235a0a0359bfe9df	\\x0000000100010000
46	4	9	\\x82298eacb3480f2bcb340ae0871bee2948aea74930340afd6c2fbb537cce2616ae2d9d8d08c096b7fa993b3db106cdbbc2f1a2c3acb88dceb5817824f412a703	384	\\x00000001000001005243e8c35fa758a32c158db3f4d6bdcaa25edca0084ee25b1867a6a9db4dd0eb0d0288355ea2733d12162b2a7e5e39bd22f3856e8cfe6805f2aac75fab8e7e1fbf40fcf06bd1c01a4462956cb52c0b5775d75920086ba8f99c04d5012b2f1a1cf6401567fbade6232d703ff21eb27c5efaa036adb8ec0bb746e4bd9741186c8c	\\x101394d0172299fbc12eb7579aef48c9a03574a529d2e95cfc030047e0f9d09711be768cdf41687849bc66541c3a5af989915dec865e8a736f5719db89f64c83	\\x000000010000000153648fc2b40fddd18a745233b8c1cb62422d4f9a193900a1b5e5cb94ece5eadd266236777ca7a5c400b7a203c4093d9c7c0de8021c3999b57ab03c58252f880457a11e9098b4d66f0352aa0be679f6d9ea4e170a673b4627551108308870a1700d789b1f0349d3ce35f37cb1f15ae70b45cb7145a2b9e40c45d764ee307e5695	\\x0000000100010000
47	4	10	\\x93540d35286edf0ce6815130a21530b22042d0e0ae8c1de072fad3520a1bf5396d1267d5bd230742351b423c6c6b7865a564f97586f16a9601d389aecba47c07	384	\\x00000001000001002306ba24ee2b0cbac78ff13e388cee0af370927c5e78a3925df5481b3b0342d2be29cf76e3a707899da85fcab4520d08d230a1a4dab462041acf9c6234675aea2c3d4c8eb45001f93c6815d00c87b8364d934e8bb322a00c28789b32291ce31775659b357f4e82416c60f063aafa9fc838b588fdd0a6a16e9feb280d78a4766d	\\x6445d80c33a21f20e93b79ca6ccb868d5a2538dd36eb51f21e03608dd5be8acc4e44458bedf44338d7c85749cb514b5c7552c53a54e12b3e29832b596e718fd6	\\x000000010000000197264dd1738e4e27c6ebd3a1061d50dc6fd6eabd5ab2b3fe39649545503a88c94653bb922a504eee0ada93e353ebe3acf89fe6d24eef1a8621cba96ffefcc6b16c33e2c8fae81b5f10e8a9e5139b285b9f6a1020b3d23ddc8b1ae140d4d1d63ca93a68a269d93aff0431065fa412aaa1938e58e4ebb0ba0a181d44d568e0b19a	\\x0000000100010000
48	4	11	\\xfa2e9faec52a7d0e5f6270acd0eb8649871ea2c94eac6238f61bcbe433e8d0bf36ed899190c2d8621f1e54937801d0ad2958ffdea96f772ace0d7732d1139f06	384	\\x00000001000001005ff264d7e535e21a14b318b36d9c52bd3c024147ce69a002e15cfce3f338b663039d2504028d6650d78b3b1e2425c881c26b085af0cceae81de5f25f6d04b4737d3810c407346aa9c054c37485b60239c189cf3ced1aeaf5af1d87d4774c06f64a9b9f2f7383437b5e60b693bf46b52820bef966a22f323f3f95ecc51ed87811	\\x4c415cf84eb2c8b1a6c736f1f2b5ad89b6a8ed7bbba0d5faae85e4d501d954d47f792785f8f467e9dd4dd08eede2774a0d497f75814f9a5d6eabf9fde3ad2074	\\x00000001000000016a9bb7ba99fdf29fec86555f608ef5d0b21ded7740478b25028447c82ecea6b46399cdaf07b4ca80f3f37b00043fc38db50e032c7fcf88c676d5ee18a1dff737150d52fc56ad90925cb53fafa12a1239803233a5a026c182bef41fbf499e930b2995ea0528aa952d1d2e4dfa39ca765aaff5c67755b01812c267716786f067d1	\\x0000000100010000
\.


--
-- Data for Name: refresh_transfer_keys_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys_default (rtc_serial, melt_serial_id, transfer_pub, transfer_privs) FROM stdin;
1	1	\\x8f160b154802fa88d66ec457bae3425dfc13d0faa413bd88999d7a7ae8a9d943	\\xe3665b95596eeded17cd8d9756e8dd986b230cf6de881009d87da9ce858a5eae81196164bdf5b2a29a7281cc4ea866c1574beca2834f792c97ef24fa7edae350
2	2	\\x1ec972c8d4ebcab24b2e691a4670475e150fdef538560e33541c695c1b76dc13	\\x03ccedfc01774296ee5303c19ce39750428a5e90b46e4d5acd766bfda04208c1a60d8c23e0864a4a23d6152b20bdc692456919641cb3910be2e19150ee0b71f4
3	3	\\x6c56733aa4d05b6ed0139cbbcc053bb51a625b4da44c0684b9560966057dfb60	\\xb5340939c9fb8004336bdc82eb5e99ecad5f24ff4dec1a291b3299f4c75d6725ec14464e900339487001a9bd53da3ab751fa0193e2a7ed3865cfef4a7e5e8c48
4	4	\\x35a6342c595155206b12f870e73fee892ad242fe68ca3e3cc2f5fe7966b37c13	\\xdc3c87ab3983b95692c95d09d8c7819b1d66dfb4d52c73f596a2ab349e8d73b91bfd8a8c63fcad22062e3c604fe8d88d1f87f7f38e35c9603d68025ea49dc196
\.


--
-- Data for Name: refunds_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refunds_default (refund_serial_id, coin_pub, deposit_serial_id, merchant_sig, rtransaction_id, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\x4e9fe3e0730616b81d47f74d78dc5c6ac8d5906e51a1a89e1d6b467c882440f7	2	\\xb8936bd8abf6d39fa6a7420292dc5b820b7e5bf3019a53dc2ef007f64679484672fecca66fca74733390f1aad86b320b1138dd7aa77b00a409a54cd15727d008	1	6	0
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
1	\\x7b135565bbf126e26073982c208794eecfd4a84263cef3f37ce5dda9ddfccf76	0	1000000	0	0	f	f	1653244220000000	1871577022000000
2	\\x9da0c621235775203bd7186893990b5cc6b7c9cb040e160f6fe6b8aa9d46033a	0	1000000	0	0	f	f	1653244227000000	1871577029000000
\.


--
-- Data for Name: reserves_in_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_in_default (reserve_in_serial_id, reserve_pub, wire_reference, credit_val, credit_frac, wire_source_h_payto, exchange_account_section, execution_date) FROM stdin;
1	\\x7b135565bbf126e26073982c208794eecfd4a84263cef3f37ce5dda9ddfccf76	2	10	0	\\xf2e29eafaae154ec69aa7d2caa4e3f08d70fb15a0c30e522ab75778188ded66d	exchange-account-1	1650825020000000
2	\\x9da0c621235775203bd7186893990b5cc6b7c9cb040e160f6fe6b8aa9d46033a	4	18	0	\\x362255b49fa872ee297be907e9365cd1816e6fcb3f091683a498bcc9617cfc5b	exchange-account-1	1650825027000000
\.


--
-- Data for Name: reserves_out_by_reserve_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out_by_reserve_default (reserve_uuid, h_blind_ev) FROM stdin;
1	\\x4262a0401a07022d4d99871ea6eb8c57288de4e6f88992a23bf2c3e1af6c4e058012e04f95ffc0af9157acfa9689d79af3993f488bdc5cc823adc6e6c5f7de63
1	\\xd1c57ea35e358eba2b590cad859ae275878df814300e2b0f94fe4d6c603c3477ee3f1700d73a28f9b132174a542b0503f5840f0dfb38131a5c0324bd980abef0
1	\\xfb5e7a4e59bb965f77cf186daab8208587eff92f1254ae3b48b09b3e5738a551abe8edcd8efddfce758ebe5851a5a70670546aa554c9946ffe2186943fd0661f
1	\\x6690526a7b8f8ec4460772607128fe7ab90727fc5e4b4bf173b47b5e47afff7f73dbdc29a3b10109d6b2df144d4934587f1711fb9fd0891fadd9061a6e429737
1	\\x76c2a392eecb57ff23952d6f9d6cc218c7af8585752e1687b5d6658f760fe2663d4b343cf3f78cc3ef3f986451cf899bd2775872fb73d5986400d020ee572390
1	\\x4249614ae9969ed89fcc576441c281da07c519dc486e4e72c319637c19a5620ed72a6c4b41ab4642917b5eef6240a312bf4375f8936a4f42f411dec1dbcff58d
1	\\x337c00c4f938673998cca47c2bc10465bc1b960e5446c8b7e3e80aa93ab743572c33089b8caecb9994aa83ca37689d14415ccd01745ccfb9fe9a6e86e55eed51
1	\\xf6e5c17ba64d1773ac1af0a2627821f185c78e4e0da16ad46942873660809fa54591d61ecf34cd7698032fd369aacecbed4a2c254e53f64a82be53419c741cd3
1	\\xed57877f25d088f87b0ebe3419271a5b3615d3432b8dd6674eb4c6acc679e2b30fbe3f60be8c5c4ab57a71b1943ae4a4f248b9fad7bf6d9c189039a63c0a0a86
1	\\xb0b7e21f36d36b05b42a877acf36864387fab0fbab4ceed43eb09b21d5fa0c79677265855d680ddd8ed53229decf3b5924c52bc587903f8f2b802d82e79021e5
1	\\xc6faa4149ad35b17c13dfbd492ef9c48f39d23397bbf5a1933fb0e7440fbc71dd1cd8df7063a2f42ab0a68b503a2ff44bae96ced913150fe6a79cfb1f94122f8
1	\\xeea0971a613709ffe9ff73171039c0cb1ba8a4b25c76d755b7086d332ce14b245f9482bd5cb62bb73f5b966f4076d2fa75859592f9a54a09f0a097ca44491224
2	\\xc06336272cdf1ced5db92a6809a8c1181e67cd47f5427287ca5ea9d9b094b1e71758e70975ec1c6523fad66ee45959fbd1bb69d00f18a15dcabb5aae5430a76e
2	\\x7b5545c5587c525a5d06ab8d3facbc11bcd460179740d74fa0a099e3d29b62ecfbe0161d482355bcb5bd826d67b38a4a717328b9c4a91ab350e8c8ec47a3a1a4
2	\\xb40e4eaf0f0899ac144e0335c3c6ec3c91fe8836a6d576d37a876d8224d6dec6ca176472a0e68717fd67e622b1b90b22c7b87d93282d845cb26d631d06d0e4e9
2	\\x22ecd110f08882d18b8700ed10e6ec490404bc87c902b4e3a96c1cec2ff2431be13cb5ddbab379202705c59d5b5bbff44d8796252afaae08bd807ff9bb76074c
2	\\xe9ba3b63bdf288c3ee3853525dbad11cf53c756c090ee7c7092f797ae99da9555ddcee1beed3fc9ffcb90351a63d10d6d1c0a0f964b02cdc4f597731b39d7754
2	\\xf5f429c15d0f2b1229d6d6edefe49bbaa6c28b410da861de80a65e5ba161440dc58bed9392ca73fcb97c75c646ea138e3116c7da2ccb944bb87a46c561c351a4
2	\\x35a3f4a45e399432be0567803a3d7ceac131c6506daed7915e93f6ba71ba4d526af2546eeb353fd6eafdfe6f014b8ae635a87f9eed0bda136895ad810775a6de
2	\\x4ba2f5978726ddf3c142dd9d6bf4a11a3d004c0ba8a5ee9f207415e63074fd4cdc311ef3143e0aa0b44d107bc8e09b9741001a481265d5801fac29545dcdf0eb
2	\\xeaa4a8c35b1a5f184ee038873f31e575492ef985690a1f770e0a290bb1e7c4617785044ba0e1d4305dabb54f9c5c28279d39284a6438c58e338bb6c8fd3712b4
2	\\x76cbf41b20e303d2c7633d38854c9911f2122f6f495bffcaca2161444d75a47eb1a56ade98ce4b37656a1efd20446c8a7275f4077f139d8c329d0d426cf79012
2	\\xfa93480f03aac3dff97892e6a76f31c1f4d6ba7f09b2ea5fd9a4fb213b26826e3c3e7dcdfab506d339700b18b48ca46f08fd32be8e0817df4d1ca7b6fad51afe
2	\\x32e6dcd5c143478741b6302e5af7d16fbaf7bb2349cf69be66463c040a1c9df882a95e7f2614141818725558d2c20055e5eda1fa6af2f4d9a57f836c09c5d175
2	\\x922b0db86a6e1103a251cc29c84417e24980bc690dcacea2eb8103c77e83fabd3bfb47ecb6ef739bb231104982555448ec563e7ec4b42cf9a1d65508ec008c0e
2	\\x1ec473f2df44ad7f00a5a429ccbe007c1eafe31f9c12e8b9ffa075cac2ba228af986c879f04b70c1e88aed77556ec68ca6d452edfc5abdfca630a427535e8ce2
\.


--
-- Data for Name: reserves_out_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out_default (reserve_out_serial_id, h_blind_ev, denominations_serial, denom_sig, reserve_uuid, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\x4262a0401a07022d4d99871ea6eb8c57288de4e6f88992a23bf2c3e1af6c4e058012e04f95ffc0af9157acfa9689d79af3993f488bdc5cc823adc6e6c5f7de63	123	\\x00000001000000016f84c78f00c583b11a6367dc11e697b94b690ecfe675a38005f30059de5e89639cf9c3357b3275ad20cf349baf37eb89993d81115e705ef597071c602371a254e17571c2c00909ea3ca7850fdb67fa8905ca71670ec3208517fcf748f239173714780aafdc31f6c428bfb325cb25b27d600cbe471af26a0831acb0146abaaa3c	1	\\xc75bf89468379f98f3a81fa0f390c31e73f4e23a02d42caabad7b4998b98e87a7d200792ea6e1ee26d746c93ec0a3eaf725305fbdb0f5d86462b2feffa126901	1650825022000000	8	5000000
2	\\xd1c57ea35e358eba2b590cad859ae275878df814300e2b0f94fe4d6c603c3477ee3f1700d73a28f9b132174a542b0503f5840f0dfb38131a5c0324bd980abef0	236	\\x00000001000000016d6f3ab0671fb4a59c8a0c20ce769c61303102ab2be7544e6ff4d7fdd7e6242a19bccda0fa4f365a8610469036f411db7c94ea08c3ba1c908ef4ac9b883b7cd75d0a8a16dafbed7c2db2ac8e6bb771202b0b6a62c4835c93efbfc012564960aac317cad065f172eb090746275e38ae997befdc04ce933b4cd8354a45ee0f5817	1	\\x3a3e0e6fed852f9981a66b6694ceec09019531294e4cc2f032aca7487bef2296edbd17fb143162761f458c8509a3219edafeb55e7fcccf7c661a3d0b5c163f05	1650825022000000	1	2000000
3	\\xfb5e7a4e59bb965f77cf186daab8208587eff92f1254ae3b48b09b3e5738a551abe8edcd8efddfce758ebe5851a5a70670546aa554c9946ffe2186943fd0661f	220	\\x00000001000000011f38b42cd691e8a809dd061d93d24ebd7a0d45b1bdd9cb95841687563c3a1ad9cfe35172485a5fcfef0e71fc0533aa0f5e7c167435a35bbbc593b67e3847383ba261ab2a0e1b60c85f37cb1c5187caf72269a36a785461ff6702974504e1c4fca27ab532f1278727c66f330955bf49345d37b6332cf08af7b970f535317b3716	1	\\x73c7794b31f9c334b5452e4683f75c6f98d93ff7496bd6d8ff2f8b9700c3ae4ebb5580a422e84db4f4a30a0cf6d53f92f99801c2227ca92aeaf2d931ffbc790d	1650825022000000	0	11000000
4	\\x6690526a7b8f8ec4460772607128fe7ab90727fc5e4b4bf173b47b5e47afff7f73dbdc29a3b10109d6b2df144d4934587f1711fb9fd0891fadd9061a6e429737	220	\\x00000001000000014b853764025060f9ee5eb1080f2dc55da0a428f1959f0d56dd58b0344aaddcf9b5df39156cb2d72f1f707aa524ddb3a2f5a98b3705178415203f830bb77f7b70f5734f6c0aef0c9cc42b8da5a5310ccca7880ffa95f024b89c90a6a89c6775a84f38df85893b8f9a8c3416d241ea9934ead601c1aad2cb61b11ead22fb4e539c	1	\\xaa50de31549144aac34e066c24da69d6380f3f1644f1227e667ab797ca710c7d1828890e2d391ba1df716253f50d5b402b27c1a7969839775c23476e79b2b60a	1650825022000000	0	11000000
5	\\x76c2a392eecb57ff23952d6f9d6cc218c7af8585752e1687b5d6658f760fe2663d4b343cf3f78cc3ef3f986451cf899bd2775872fb73d5986400d020ee572390	220	\\x0000000100000001614fe170f7a4e988162306e8bd7359610ff306d8bec2124f8ba7657ed792713908bb1e91f95dcb6dd1da80d584cd42aa53901c368247b7c14283ebbd60712cb6b51523555a183742a76b107e5f8d26e9ef04a98d38c554d41e1ce1abec0be650dd8fca401726c7e60767507315415c2c42808305b5dd1155c1251b6ee89c0d27	1	\\x9ddf415f2363575e6d084015ae937f5b16a4a79acee88b0983ce5e3324a67c5b3de91e4062fcc6b641e2544d207a22329a520a4c8c82d6054c2a5409d3ff9202	1650825022000000	0	11000000
6	\\x4249614ae9969ed89fcc576441c281da07c519dc486e4e72c319637c19a5620ed72a6c4b41ab4642917b5eef6240a312bf4375f8936a4f42f411dec1dbcff58d	220	\\x0000000100000001867723ba62594b6169cd17997197befbb6cf836b68bee14bdf248ac07677ff0881f16068cfd836cd93d5d7e19a8ed120fde2dc1c34bab7e498e4ebb820fbd2f1bf2a31da61a17932f133fb96829d07f00e00633d0686682cb295e62457e893c503a3d38b56def3cf7bfd092932be953d1ed0ea8cff9a5d1bf5162d13dc4469c8	1	\\x994daaf88f1a0d222feaeb0cc504077a21acb2ce72e6ccbd2afc7a55c8dff41f0a0b3be78e5711c0a6c8289d372687f0a5a2eebed716e06d05c5eb8173d7170c	1650825022000000	0	11000000
7	\\x337c00c4f938673998cca47c2bc10465bc1b960e5446c8b7e3e80aa93ab743572c33089b8caecb9994aa83ca37689d14415ccd01745ccfb9fe9a6e86e55eed51	220	\\x00000001000000014a939fad54e090886ccfe3bf9f68b874999c15cf14706e0ffae335a33b556e9a275c602901a56076d0b5eb9d0b3db4edb38e71e4237e3ee0ade3de186149f1259a51bba93b735575bbbbe5c461ad13779bcd8f2f26f33e3a73a831c720feb438cb68c2e06cefd16304ec7ea9f0518cfc50902ac41d3487a875fe5135324110ed	1	\\x7e6d87a6c1bf741b16d2fce8f74faa5d3695564fdbcb100204452557f1606414f469dbb87d721e914c8575de2b53465268baa89265cff82f68e2d1fdf0111f0c	1650825022000000	0	11000000
8	\\xf6e5c17ba64d1773ac1af0a2627821f185c78e4e0da16ad46942873660809fa54591d61ecf34cd7698032fd369aacecbed4a2c254e53f64a82be53419c741cd3	220	\\x0000000100000001911b1d2ecfd8392acff5449ba2079612c5362233c2b62c7f2058ef33408fbcb1ba3a6d343d29d9f57210d2bb976cd40d557f6dc43312743ba338de7d49d71af240be9aafeb8b35e68323324e3a16662ef690a09c658b32679075304f7a6ce89ba44d43ada311dbcc769cae9ae97e2770ecceaa98df5e0c12d6875d5b6a44e6d0	1	\\xaf9e98d51001e6018356138eb685450ed4661769a285429b205489a3b44e0afcf667861389e18d3315bc750a159446e993aab65c5bb3b029ccc1a26be3461d0e	1650825022000000	0	11000000
9	\\xed57877f25d088f87b0ebe3419271a5b3615d3432b8dd6674eb4c6acc679e2b30fbe3f60be8c5c4ab57a71b1943ae4a4f248b9fad7bf6d9c189039a63c0a0a86	220	\\x00000001000000010b7b36298c2b15b0876a8e2f1f5b3598afa6b1d2adc6815d91fc0a809d9b6afebb5be95b313ca48b2b46707cc0ec0e4bdae755e5847bace82a1f17cc27bed9a18862ca1557af048a5b5e195f293b75d8868eb7c869045ea0435ce9fabb82543989da7ea1ebe5083e5b636b64bdd755cef32429971e07022d29b1337e6933f199	1	\\x7380f6b8978c915161f2dc0529b06421fa94fd7fb95207aa6aa42f54f58108eea09f3899992fab77714352ad90e21f71365d32a4fa00e8ca66e382bd4d598702	1650825022000000	0	11000000
10	\\xb0b7e21f36d36b05b42a877acf36864387fab0fbab4ceed43eb09b21d5fa0c79677265855d680ddd8ed53229decf3b5924c52bc587903f8f2b802d82e79021e5	220	\\x00000001000000015ed4a83c2954774cc20e77fa9cd096810eacd8a8fb8dcc98ab9fd48a7f8f5869be734c5b7016c11679169ea88dd760b9af33b427517514bb439191c27a40e4084b7c24dc60b2b51baeebb45b1212cf139cebbb630b9a57240871a3820d891b533f625897a2b027b29a37c37073734b7888021a4e97129afad37eb0b35e959c49	1	\\x005fd1f805df7514e0c8860ad34c83c217d7a65c1cdc141fa1de399501c79dfc51d10853becdc8a7f7f881181869578ad8c53c59bdc95571585cb21c2df9c30d	1650825022000000	0	11000000
11	\\xc6faa4149ad35b17c13dfbd492ef9c48f39d23397bbf5a1933fb0e7440fbc71dd1cd8df7063a2f42ab0a68b503a2ff44bae96ced913150fe6a79cfb1f94122f8	384	\\x000000010000000115c2d123e0b0674d61e852597a78d1d34a44adc9be5b7972b112d2f67e02743ca5bbd9cf5a52e49e2358e0e91541441ee15794994318ac2a558d73d64f918e31e82aa275153f8e41b2506fc037bbdd421076b6ba6976617d6a4e3c77b324c7635139c26d9682d9847305a3192cd1db0a6bed445553a1714f9f55d3fbcc919ca9	1	\\x8b3df55ecc5c00f118bab999aac168e4712c4ddaadb02db185cc933d94efa8d04ee9a6a613bf92b21552363aa159a7f066d30c77db01b928c0da88c424ec4e0d	1650825022000000	0	2000000
12	\\xeea0971a613709ffe9ff73171039c0cb1ba8a4b25c76d755b7086d332ce14b245f9482bd5cb62bb73f5b966f4076d2fa75859592f9a54a09f0a097ca44491224	384	\\x0000000100000001703316058cf14217f501fd82b406f6448c1d32fb9655ca3985e39f883840a0b5efd9425f0d42cbe49532d4aa808aad02433971cd9eba513d1b60da0e4e829dd386c1192d1031bcae255c26f14e299e465eb3a2601bca663b3e6453940ebb7f686ac988e5a184774d3c4c6e6e15931da9095d2ad09cd7c4d7bed2b82d08bbdc23	1	\\x14690480858a6db5c426b206d7f732b8c23e0e0a1a1bc287d53c5e1a52c152f541bab58a12adb7d1fc1c57d15e22d58389e7ccc8dcbd7d2bca0f65d7f1e9e10a	1650825022000000	0	2000000
13	\\xc06336272cdf1ced5db92a6809a8c1181e67cd47f5427287ca5ea9d9b094b1e71758e70975ec1c6523fad66ee45959fbd1bb69d00f18a15dcabb5aae5430a76e	288	\\x000000010000000117bf7341c84f208e5ecb8184ec3ca2e858776fbcc1b54452e2a343d0a55c17d0acdd10244363b5f8ea3c3df3f1e2c0a3aef48b7d9f34429dad747b1999ff193154fe0faaa0a659a6e507611b41873b94e501ce938fc64a36640ceddb2204068528e9556b5a33132d2fc953c30db3aa19929a7982a77538d4b13a27cb934cab50	2	\\xf9229789a0add9a590cbf25e31708441061a91704aee2eff239dc7a23b6270a524029ff3c9bdf3f1fac566f54ad12ab49121540690f4dee1155f392601768909	1650825028000000	10	1000000
14	\\x7b5545c5587c525a5d06ab8d3facbc11bcd460179740d74fa0a099e3d29b62ecfbe0161d482355bcb5bd826d67b38a4a717328b9c4a91ab350e8c8ec47a3a1a4	41	\\x0000000100000001a035d28bca9be48db0317eec848e75c7ca87dcada90014b603c448f094489362a34124695245151f802deb39a227db876c996c048bb1d6fec4e4cbeb994104cfacc9d9e83a9534bab416760d91c596ae0f4ec93ad2ff5583201ea8057048ccf8d089c2aff87f7ace3eeb039ef2212e00deb7654109c0384232733010e5c000e0	2	\\xa2a70da07614e24c9afe44389f11e17dfeec6d5adc04b75f4e8acf315f3230a9f8a3ed28ce5d4476745e0af1e8e358e9f7d15f8fdb668702d34c6a33179a5500	1650825028000000	5	1000000
15	\\xb40e4eaf0f0899ac144e0335c3c6ec3c91fe8836a6d576d37a876d8224d6dec6ca176472a0e68717fd67e622b1b90b22c7b87d93282d845cb26d631d06d0e4e9	307	\\x00000001000000013794746d0624d824be344bb382c0e48bff5f5d2c49c5331bb4c28412c6281d3492c8682b059612ebb3b51e1fbb6dc477794b10cf26d9b784f2aec5fb2bfb614890ef8baff0c9fb3ca93a0e409071dcd2c9f299c0b245445f3bde817fcd6547c213c9c2af239da50d69c97513596f14339a5f0b93231156139c4b2d1eb7973c18	2	\\x661ccaceaa7b2c003d125cb6c2c3a85d1a0e4dbf754cc521a4ee7fa893e052d853c00f9516d98341f057c5035997532f666c9fdeafc264d18d4af4f145449402	1650825028000000	2	3000000
16	\\x22ecd110f08882d18b8700ed10e6ec490404bc87c902b4e3a96c1cec2ff2431be13cb5ddbab379202705c59d5b5bbff44d8796252afaae08bd807ff9bb76074c	220	\\x0000000100000001830708f7c7a7ceaeaa0e6901a93fce575faedf28c0d9e488d7aa754e53462a3d9154f363793dced265e2fa95eaa34b169e3f36398de28a697fe53c093c0042a2bbabf8b3874964e2cb859e517ee00119d1021905c8fd772844c943b3e27aaf8a065462a17bad0afa2d0a3b0e0cc439974beb58ae482924946287198f8e28dda4	2	\\xdc80872030459f7f6de45675aef1f2b2c1d9474d8451ca861fcc8ef2c385e6337a5f23b71df50edd9fe26cccccf6ca04a672564698bb325574a09e7006dce80b	1650825029000000	0	11000000
17	\\xe9ba3b63bdf288c3ee3853525dbad11cf53c756c090ee7c7092f797ae99da9555ddcee1beed3fc9ffcb90351a63d10d6d1c0a0f964b02cdc4f597731b39d7754	220	\\x00000001000000015420bd392f6195eb93822b0940170b0eb7ae2ef4c2cc22f14ecde00fc17d2fc253a79bbb54c7f7fadc5981fb7383b18cb26ec4d695aa7c284cdf9b96e70bd574550ddd371f4e0777168b91e02d4d6e2bab10121116ec89056175600befb921361824c6f4ca1ea492430f5d3b939cf4d26f6cd7c7cc21381ababcacdcf8ec3654	2	\\xf05244e70b89090e7d033c5a0b9973fc788a9a44461114f6beead0d44f941477f191a3f6349c06ab14e02762dea44859e9dbe68255b58821068e226b635deb00	1650825029000000	0	11000000
18	\\xf5f429c15d0f2b1229d6d6edefe49bbaa6c28b410da861de80a65e5ba161440dc58bed9392ca73fcb97c75c646ea138e3116c7da2ccb944bb87a46c561c351a4	220	\\x00000001000000017ffb602482ee3bfefc253c3b24081b1b3f0549a6fb329060336dfdfe0f16574781d957e33c12c2a35f28f6d6b26b7667af67718b2519d011118c89e12d0c636c9fa83bfe2974d4df55d753cbaabf7f1d986dfb5d33786b8c7f8994fb3fd1ae13853a8cb69b10e12fb04256a2afca073934c3615e1d8d1b64eb923848968c6a7f	2	\\xd4ff408ad8b7120a4ba5bdbcf48d5b10345935e02c4cdfdb6854dc209c0df8ae2faff6af769ef34557629caced5cf19a3763f7eb166d63d3eca1ec066a519300	1650825029000000	0	11000000
19	\\x35a3f4a45e399432be0567803a3d7ceac131c6506daed7915e93f6ba71ba4d526af2546eeb353fd6eafdfe6f014b8ae635a87f9eed0bda136895ad810775a6de	220	\\x00000001000000013964848cf69558d8722393f03496c883d0f7b5b19dc12761869c5766e91c5e52fa4d8f12cabc383f112e0581f16959eedda302385599befe190da8f3bcfa66e7c4a738ddecd178a35ea1491a27045629c38713cdce90c66c2c3355683bc31bb1808be5f0cef74e769a48930c43ebaee4c745d2ccff3d24db27f91a6fb52911f7	2	\\x752b6953ce0f898b2f7f71f4963cae0503cd988c184d4507e9ebb5f8aa474b8088b8dff84f173b575f047769f3a305c9c5d8a70df317e7e554698e54a64f1a0e	1650825029000000	0	11000000
20	\\x4ba2f5978726ddf3c142dd9d6bf4a11a3d004c0ba8a5ee9f207415e63074fd4cdc311ef3143e0aa0b44d107bc8e09b9741001a481265d5801fac29545dcdf0eb	220	\\x00000001000000017429c4a7a73f484ef75d32015aa2b05b75c7c5058091ec4b677be12c06c8c522e2cd84c57cc9a8972b342bf43ef4aeccbf53f6bb636e193e8b73d89280e771caa1fedf628c82a0ae64a6c38c4b1dc4ce920e3d06d1308baed997032145e39572f0a4917c132a1afd2aea0c748c0918fcca40741d00ecadce7384cd54aea34a24	2	\\xebda948eb35c5e212d15090028a65fff55c227526e30001c6b0e3043cf3687a8e436c5a2efa0e7ed2aa9f7e0aaa682949ac9fc6725089bb364b63cfcf9643d01	1650825029000000	0	11000000
21	\\xeaa4a8c35b1a5f184ee038873f31e575492ef985690a1f770e0a290bb1e7c4617785044ba0e1d4305dabb54f9c5c28279d39284a6438c58e338bb6c8fd3712b4	220	\\x00000001000000013bd8555253a3495e2662a5c6fb9ab3252f91ac13ea1871bf34153cb928006e0c3de1961fc5499f26e7a5f7af5d907b5dc7246f55bfcc68ef63ff9f681edc400c679286782dde98f46dbdcca507279052e70dff750edc9f2057803a2224d44e13db6e15dbf03cf14a26ac679b0fdd809ceaf84a98d4ca37ccc1816255afffd3bb	2	\\x0985a9399703ca5e3d11970e05fd23f791f66583f6d412831416995bc94bd19a053004d84368084909a9ba6cfb3a8966b0865d3fc1786d20b76d05cc2a7c400d	1650825029000000	0	11000000
22	\\x76cbf41b20e303d2c7633d38854c9911f2122f6f495bffcaca2161444d75a47eb1a56ade98ce4b37656a1efd20446c8a7275f4077f139d8c329d0d426cf79012	220	\\x0000000100000001233f979e2e4ce270a85e91dec67385a98324f5e537bdbcc90faa32573f82bf835ad80cdc08082adf965218d7289d446bb93d83faa84c6cd49e5acd3f5c4485e8716b75c25c84b818fa7ac3b6988bdbfdda4e70c3ffbccc9361d1d2e24b6d57177638fc6d151056192e1218bb8420ed08503d80dc55422ea3f1d24f2af5824235	2	\\xf2c2880af09ac2318607599c842982b98c3b92ca9d09ba1ec58dde29b14e4e7c395474a193176439cdcd05437b511e982f07d74abd021e50253ab3cb6f7ed608	1650825029000000	0	11000000
23	\\xfa93480f03aac3dff97892e6a76f31c1f4d6ba7f09b2ea5fd9a4fb213b26826e3c3e7dcdfab506d339700b18b48ca46f08fd32be8e0817df4d1ca7b6fad51afe	220	\\x000000010000000124f9d4e4ced52592b92080e227b4a28060340242a6b8f4c47c9630dc32abf225abce43aa1edeedc34af2b2d7291a2e4dce110b15659017d22780e1e673aa2049f8a6a038bf94c8cbd7892e64e56c17d9966a1ab744c4edaa8abe625104d6379eac6c82cb2f2195f5780ea8b2513f07c98156dc7b6123f864f29375bb3fec5cfa	2	\\xe7499d1a5fd483672e2234d81586f846783642d81c7e0f7d7e5829b420f2b5197fff3113208c9cac26b924c1c469b0a69d7007955a8dd9ffe25157cb26f26209	1650825029000000	0	11000000
24	\\x32e6dcd5c143478741b6302e5af7d16fbaf7bb2349cf69be66463c040a1c9df882a95e7f2614141818725558d2c20055e5eda1fa6af2f4d9a57f836c09c5d175	384	\\x00000001000000013e2dd0d2b28462268a694d2e380bc45e663118c3f4078bcc3dabff4d0c8c06b8860d7748c9c99cfcd650c78152a5900a8ea1143b5a6449d89199d8d32fdbda8980638bb129e8617af8dd6699ec667d2954b51aafaa5a8cc8f2958be55e465d8012e20b82f944ac7e234c4c10283a2e4d2cd2dbcb0ba4222191af87101040091e	2	\\x48c80f5e136d40e85e95d61f68a4dc92cf667ad0b7a202db5599b7fab157fbff6ff258d724f8e6eda8c5ae4b1e6b8c91e8b7e4e5b2053c990f5de696a191ee02	1650825029000000	0	2000000
25	\\x922b0db86a6e1103a251cc29c84417e24980bc690dcacea2eb8103c77e83fabd3bfb47ecb6ef739bb231104982555448ec563e7ec4b42cf9a1d65508ec008c0e	384	\\x000000010000000180052a79472ec730e55048f43df18bbb97ad4947ae9d1b75cf27d37d7a2ce4f688d0d18d9c7bb5781dfe74ea76bef11ece85c207b5ef3e5a575ddad9fecb4980c1dddd451d6c87db71218a2b56864e47cc435a587f08a7f01a07f8f21ecd8f613be0524cc9289ea93d4732933cc476b2805def16fe0b4caa5c8ff99b9e232204	2	\\x1f1089acc9b16795cbfea6d11ebc39ad57542da356abda906f47b23065f71fe918c9c5a6025c0e50ae6517ebe4b6005346cd91c8018b8c645094f2fa60f02b07	1650825029000000	0	2000000
26	\\x1ec473f2df44ad7f00a5a429ccbe007c1eafe31f9c12e8b9ffa075cac2ba228af986c879f04b70c1e88aed77556ec68ca6d452edfc5abdfca630a427535e8ce2	384	\\x000000010000000168f5bb21e0fbdc36e1c0b20b97264faf698f4d42efa4d5e2b259271a6d99c237197b5fe92778fc39ba994989939c4a0a7054e03031368e2e4e076a8d491285f74429ccd5fc540539e0cb2706442cc78d9ad78797ed6b2aede1fa48e10823e5be4120094070cd9a20471ecda3580f91329fd5f2f52080566cbfedd47fd000b470	2	\\x0644f563d6ff54ec960fe21e336c51de241668965da51547d395ccd4f0019f440b803373d93bd624a06319dfeacfb8dbba453abe03e38db15e11d6c0c7dd480e	1650825029000000	0	2000000
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
payto://x-taler-bank/localhost/Exchange	\\xb63478c99c52a3276ff3bd806a700386a07117516de21d0e6da1417ac9cd2320a74c1e0375120fca0fa6a2662c71d3d3119f1a26e41ede9f75b42a374c2a9704	t	1650825013000000
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
1	x-taler-bank	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	\\x2a3a8d8aa134f1c7fb8b895e834c07bd4b78d80d007c5e21e94c5b09c4770fc5a4d459fa6fc835d0da7180b55955c1cbee640e7c008388c83c0da96d8d56a10e
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
1	\\xf2e29eafaae154ec69aa7d2caa4e3f08d70fb15a0c30e522ab75778188ded66d	payto://x-taler-bank/localhost/testuser-gwvpczet	f	\N
2	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	payto://x-taler-bank/localhost/43	f	\N
3	\\x362255b49fa872ee297be907e9365cd1816e6fcb3f091683a498bcc9617cfc5b	payto://x-taler-bank/localhost/testuser-jfbjvv0h	f	\N
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

