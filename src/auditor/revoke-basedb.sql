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
exchange-0001	2022-04-15 11:28:10.216866+02	grothoff	{}	{}
merchant-0001	2022-04-15 11:28:11.008751+02	grothoff	{}	{}
auditor-0001	2022-04-15 11:28:11.550555+02	grothoff	{}	{}
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
1	TESTKUDOS:100	Joining bonus	2022-04-15 11:28:21.559392+02	f	1322e222-bad1-49f5-979e-854d2eb88fcf	12	1
2	TESTKUDOS:8	MH110V1W0C7254JFDV80Y2S581CJ5KZA5JH1BWR7769E727CD3H0	2022-04-15 11:28:25.224019+02	f	c96043c1-3508-46f2-9295-be47487befc0	2	12
\.


--
-- Data for Name: app_talerwithdrawoperation; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_talerwithdrawoperation (withdraw_id, amount, selection_done, confirmation_done, aborted, selected_reserve_pub, selected_exchange_account_id, withdraw_account_id) FROM stdin;
3f5c5aab-67ad-496e-a796-d1183f7fa762	TESTKUDOS:8	t	t	f	MH110V1W0C7254JFDV80Y2S581CJ5KZA5JH1BWR7769E727CD3H0	2	12
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
1	1	71	\\xce532ea378e90c4e5c0e1e7d0c6bed3db0d1b3dde17094baa9b141c50e78e82252eb15176a0d905443df88c7485ca6e39e2dbb3622bb1e133fef1989aa5b520e
2	1	270	\\x8b7949883384e8472fed274a1aedcc2a1d9576d9ab6fbc977b1843214ea9b4cda93d3a3be0360f45c82052f4a3ed027ab80e801010c74eb6f1101cbf5eb5be0e
3	1	324	\\x9723f3cfc06bd30e2dd3a16ec1cfd339361ec56c7caf98548b498892740a757faceb79a4768b857f5d0e720f56fd3341ea30672f4d6e0726579bfb4f946ff207
4	1	141	\\x65e24a4a7242b9c17c49033e491bcca5853e1346fdb531ca3e714e3493af7f0fcdf7b2b19c0a01cbd214f648b99ad96aa51378f24a1ca62077d6b09747bae60b
5	1	337	\\x9beb0b8a7e0fe0e5793d0a12951106c468a3fa43bbd1920cc4cd3aaa7c7547771e7809a9e8eec13ee3401a98b292e590b3e9bf36a044829a97ec0f4cb658d302
6	1	350	\\x6b9cd1c3c598f6c6d0f09c24061325989fbd5567032fbb421c7b7509316ce891491dda142028ef8cd9918f38b251020e62247435292c06e085a08b374843340c
7	1	264	\\xc3de17c44f2a2c603e5f3c31924d3fd0595e52a85bb1d39488be8fb1ca333c862b2ac506e4431e84d21e5d4765675fff56092d0e9cd9674b780b869126581b01
8	1	271	\\x1d143749efc025aa1a54e9877bdf98682d8568c6014484a931a1f8e8655fb59f0f84d78d506a2fb9f242aba53e8b2871ac985bbd7a27516bdc9c748ad14c1701
9	1	49	\\x420bc34f3b64f949df5573a8a8a193b2d381ab08aeae5f14678ec817e8af4a9802db1277587b4b56f4ca7888bc101cb882e0e4a0f9a079e606a44428e4e9a305
10	1	262	\\x0c9aef17b594b4d239dbd958656016ed519bceb6376addd88b1e3c4cdb472db548af88d0e1a9b0124961b882da529e0c8b4b94b888d95591facba43885fc6101
11	1	398	\\xa8e5cc0649c64431f13e6a7d1eaee0ccdba20590747d84cb42c7197f49e7b5de74236cf27fcc94b0a9a58e7450a5d5f1fc2184ca116d44cea32fd643d0089009
12	1	59	\\xe84783a16535d64af8a041ec6598b56bcb3114f7b91bd1511e82024a4e8a216877805b62f1111137b8a9ad5bf88d8f8a70ddcd4e5cd574641d308251893cc50b
13	1	77	\\xbe2bbbddd7fd66dd5b87c13601cf39380dc56d351ca4f8bd8ccdc1417dea676cdf96dbc8da458928fb20d97fb58a08110aeb05a37c29871a3f0b3bec73d14d04
14	1	125	\\x4f1bf246e4e0c444117f17766ca001cdb1e2aca3ae925c4980a296eae0d7ee59e35674e51c9edaf14f60bd37a1655f061e0c20c5ab5958acd105276acfeb710e
15	1	159	\\xe062a794034c0cb7f1585602abc1760bf4d22efb5ff564ef32414432b2db311022d57b36539da252f42e3a7b644126fb9e87cc61b01bc03e823a2e28ad1e090e
16	1	182	\\xfc19e246d264858c23c91fe92d56abfaa83317eab27f75acf7e3fe7325cb301179368a11efade19a46974eaa7fe96a43d3426a26f6b2398e7dc835359bf7490d
17	1	72	\\x33c382acdb0d62bd22441fb585e32cbb5b8374f12d12b6f3a8f486458c0f29fe889f677988fb052f88831439504880c92a17761091bcfbbbbe6bb45b7ecf6f04
18	1	245	\\xa4dd465bcfe2cc24d90a08cdfa16740725a75ef59b3d9ba2906af6b11f1f8854093a884b24faf76b84b1d26e03c101365fc040d5aa5bd92408ceb7db25bec60b
19	1	277	\\x7139f046025422e892807cf340556af78316b0b8bef88b875e45188700622d30b58f0b2a143e07af3edf5f5176b7f47dc7ff714c1f04d3d1e7e46a8507bc5a07
20	1	237	\\xf133bd22897d0069a8996d016d2fbe76167dec2982b6caf3959056cf2f82f27aca8f97ecff2457ac68b0533a404b2a00339f0cfb4b75d6024b49138da8c46f0e
21	1	278	\\xe15df7d275c787b5adbbad7d567aeb332f3f84ae8bffe386003ffc1b67f0ffd198b59f9d1c1b4638805a32cc6647b43182ab3d5ab6e6aa70502ef47bbc6aeb05
22	1	11	\\x2a5760a845de440fc4222a7a2f6b3b6b5cd14a7f3c47b27b7c5835bc064f732493e098375a97f5395ed64bc438a512d01b0dd982298d6fd3764fdcbeec7c650d
23	1	23	\\x76ce1869b4511003031203b8f90523d988324890aba77dd1f8f7d79138ec791160f8f8f7113be854df5c7ffc78ab47b06e85f3fefb9818e4c992d7cd10c8760e
24	1	42	\\x9a8c101d63054811ed83c9894b7242df150690a54e90cfa4b9b58400216ccaaeb344fcd602bcbc3997124765fd181b753da33f8b2e403622edd8aed6512e6c09
25	1	178	\\x33cfdd8f30184829ca8fe6991a668cce6262908566d494319b4008448fcd741d3f5a0305173aaf922c54e8496110375cf5f7ee73571ea0991e0d8c11aabfb404
26	1	261	\\x0a7f83686957c2ebbb81a183b016726b43e67688325dc6a1dd4585c906a72e9a2d668a1d6ab4dbab16922b5a815b3844ac88ee2d522e4357e7a2f23815c48404
27	1	325	\\x1d5f740ea5e466b6fe8aee2ed7752533ba4aa3702384a9f2235722bfc023049025ee56ec091278fab1d1f0b3fa25e9f0246e2607e6c3cf89fef9f711676a160e
28	1	403	\\xf9ab738ace6b4302ffc9036c4374c3a5d0f5cb19f39f630ce530be18afdbfb71aa4680469f0257bbafc3825e3b5c6d38e78fe8e24a5bf079563585287add1906
29	1	101	\\x46817b77b32db5d00be5cc41bd2223257c16028627bea04fed0b86c45755342cb51eb5503f59b0ca57e3f761943b8dc8626716daaa7f118472aaf4938a91fc0b
30	1	326	\\x75d07ab5cecbeb0afb79dc7d12129d064089f83185f85ca4f2265e473771eb820d495e5068e1436d3c9d44e373bfc62451c7e7fe06ae53d98e8ebfbbab602a00
31	1	359	\\xc1878cbbef378984fb236c35dfcdfdf3cf8755f794a548a968aa004b91b5b2c2a236fc10051363aecff50094ebf6ea365eafec02ffa36a3077bccf25a4b28d01
32	1	397	\\x66cfee777469b9fff34060f536f51ba8b86b77e85f57b12506bed5ea2f92b9aae443dd5cf8abcc8a92b23bfbf1f575656827caf4889b5f225bd2983a883fdc02
33	1	168	\\x1e94a9d8c1beac0a5d473d8b994a466a791f941be3b6acb1bd063229e2a1289709c6233b705a928e663dc0bc0160c27d7147ca1096d343614eb247c4e47fdc01
34	1	281	\\x9828732a83b3351f1b62162cb5e5022b96d81f9622ba5d9af4888f05f041e2f8168d78fc49a9882df36f1ef104a33e6fa91101bdd2034ff91a35cafb5a61c403
35	1	288	\\x8ee37e5a21cb0fab22da071ccf891e1693b8ad39cf1a38240f609210bb478de0ca115d7d3d2623d403b0cda080daba4466c79a40d70a9aa2fe1ef2cfd0682105
36	1	131	\\xaab08dee28984bdbeef3ebe87ce221bea01f986168fc8d8d0c8b36c4a913a0b6b442ab0edd3288313959d5653e452f9f227fe0eb9c7cb215ea405f183514780a
37	1	339	\\x7a897cd850b9e6efee100891c112918352a318849f7730559c4c46ee10d568eedb15777a44e3389979cb37837d71b31078e74a5d6a74ae85dd7df8786735c909
38	1	75	\\xa6cb83a218d863ac8bdf48ba5b3265fc71cf704e61f41b6a01ff77f21cc45d9b48e0406730f00ac180845d1f1eae070d9e82096a6417a5060d000dd76a4e1d05
39	1	134	\\xeb1b9ae8b1e512f07e0c470d4c2d0e23f1fab8591cd389db78c2514e16e0d14623b6c56d868aa7f21c016ab298e6a2593802e61c895249b921d7d83a6a75c60e
40	1	349	\\x4835681ec6b695c7b32ac1c2282f9bb6a062a3e1ab4e1b2ac9b8a3184744762c4b2763b1a5ab665110b751d717de3f30dbcc04c2e48421fe28c04ded9d56b50c
41	1	295	\\xedae326bc058f05b7be3afb4713c7a6febecad9784efb1fa9c04cc3ae67dd077e71b0d9bde5f138f28c2cd9bf9ad3074bac788538e51951a35f2138738d7cb0a
42	1	322	\\x3662f9d4303db4d00dc6c197ab21d4ce11610210d1fb2c2ea4c6f5306dd3c3aacbd3b6cd84a82a7cc029a198c5e73995f713f29e5b15543c916a83d961925604
43	1	199	\\x90e7ffff853a83e10c72443f65e0fe0b958eb72dad3b41a77e862f96886e08e6a45bbb29af03b5c46a061cf89bc8a6be97c4bd3e1c552bd6f45f6ad0fed6a80a
44	1	405	\\x0a954f292406c50e50319ffa6d8a0be82ec6c3622597bed8d869903cf03ee338fe6cd8b45a794efc64c966206e64681514b0212f83a42a8ac33e6094ac17840b
45	1	174	\\x6bce4c51a9f0b10d2ac9771fb48f1b7f02af250891c2caecc0b2d9fb1e30b6ee52e8dfd75ba02272f54b4e5befb66630235de2c08cbda60df84df40f84a42f0a
46	1	294	\\x387d30d68287fe7501ff47920f88e90146b3edbf2974370012379f6bf86ed86e3b0a0f170dc19d85e145d6da802532e4bd2759fd2daccd9ed254aae5d403df0b
47	1	362	\\x998f7fe575cd34122ee5f36c8f835326f0bb91bf1feeb71c31016365d856ea1feeff1653b5d29df905385d5dea397af2fbc63eeebb65512981faa75d84211201
48	1	217	\\x8b72a352434b8f9b0e366be221f0fc9b8b99cd1b89ab86769b1d8b23a2f54c13df1615b348e0d291e7299cf93e6dedbefdb893a59a24a67b8cc4f36ba7d02d06
49	1	161	\\x4d9d31220be53368919c0ca35703bbeaf3697a64c9503aea4633e672d2932c5caccd0e006388130a42fafb3db656f0927ba1429bed4831c8db94263bec1b6309
50	1	268	\\xe43ef3a8d24eef5af068f346c146749cd16929ff4c242919ad28c2c0a218be575daa7acddcbad1ce96bd7b22fbb3b939df83ba3734ef4c11dbb7ca18319bc800
51	1	292	\\x9658cf8e5b1974d2a3ba8520ca19e48354b75f48c3a84b0d05ad8b645ffd97abba9e9ccf790d84ec8ddd5008bb0654afbb0784a70c7366d9eebbdedd91b1dc0a
52	1	284	\\x5ff7b577ddf90b1b994c3fdf1d790b339a477b7345d48cbe7fe91a7657a44f62525e49fff797b9f8f934ea553cbd9e169860f028a590b8c8d1b059036135950f
53	1	203	\\x04ba522dd8d81ace0763687be8b6ab4c2e8676fc0d748e793b07abf9e68f7751068b443a372c862021a51737495f10c7fa92eda51a4a3ae1b26f623e7e504b0a
54	1	417	\\x9111f45dca09ab68ce9eccc9cbf674d338618faeca5c6f84996e786b2e96aa8c4e4297a3770690c60d66f5680988ec8102046ff7c81f156ac09458011ad41303
55	1	344	\\xc0dd812cc7a0457558057f0605760289499a191093d37736ea96100373a72110324f10498e6f95bd81d4f1c1834129cf354d44d25de2f0f00848aa1b2d3aab05
56	1	70	\\x985ba31f7757656ac94113fa22a775c82073922b9d56e699951bf23ba5c401f18d2b04503947c30621e7b470ba492ef185dd0b776199cadd211978f30b456c0e
57	1	85	\\x2102b5e21ea71249916b82a3f6e134f73320a7e9afdb1a040453f8c1609776de09059c7688bfd1e913a6e024bdd3a13ebc76e6ad9e1597c916ba7809cecf9300
58	1	419	\\xe2fa3a65d2707012cdfbe40343748ecfdd850824f2940ab945019810357b4d592f4d66cd5600881b3f8473e71ca9c1c228316467ef506620ce02e633d870cc07
59	1	317	\\x0c5b170e8accddb4be9d0d46effb48f1d6a92d570102bdf6e40f4cd1aa6e9ea677ee468872f039a53f09df9d1d99c97d28618a4fc1fc0da3241a93370923c502
60	1	367	\\xccdcc945c5b8bf8eab3b692e3ab2d66e261f73aa0448f00badba9f650b46be5dbe35cc34c0e79801013e327a599e387acdff9bf0538cdaa54c3e22c908689403
61	1	334	\\xe424f5c95b69c4dde8b2adb5a2d4aab2b2837c1a876f36b756e32bb359aab2164edb7f1218face364dfd7e71fcfb9702b19e3f1d01622ab58009d328e7f8ee01
62	1	92	\\xf3bfc63e0b93d2cf4d195a9a333bc2e560469ec9e2ae713fef369cf0ae7f2be2373b9e0aa59776fc99cf0154f56686c628e0232632ab8eac091bf2da378c4a08
63	1	286	\\x040f5009ae1f67b0a95399940ce0a58388cb03041df5dc6becbccb15fb12d5ee743331958fb47afad9654dda6fe649fc44db126a8a2c0911b0e3e1bf75607403
64	1	132	\\x0c1f11c3779d8b5841cc7d99f164be71353efe00ab102b0286f6118c055e35900a10e20873557746ee3a2e2dd5bd12c05bb19d16a71c138cf04acf7b9f25c50a
65	1	99	\\xb1ac1d67ede3cffc42e0746fae4cd8b43c5fa4d757fc6b4c71f3db912a7c98510ba43efbb6c2ba5bec48af841060e32ff204b83843e5a56034b68d3b4982f907
66	1	126	\\x78c99b4dc986391ec92dde1369cb8c8a025c8e1c062cd59cde44ea0d608c3b4925f30517802299f87616cf793f087fe6343f95e25f60c2a1bff46038f930db03
67	1	18	\\x56fbe85a5a6e4896e6a810340738aa451ef48b3e6913ce05373183542190ff0fc2b623101fea38f13600ba469730dcc23f57d349b18576b2bfd68eeb05c19b08
68	1	84	\\x088811a5b2fb8ccd049d4cf68b4cbf0b26987164ba20d09aff28e1411aaa44b52c09991d21b9e6aee0be17e6ec68fa0a3b516a4d06f72545369384024cf6d604
69	1	157	\\xe9a77454d290cf13d276411c70423a0c36ec9db78549a44676b0f4eada79b39c9cbf00ee20be350e7155120c614421599b51dc0839373e032a92b048b0e7bb03
70	1	109	\\xc016f5f823bd9caeb9d5d6c135df196a324a82dca411aefaf62a9cbeb0c9028cafaee783828c17f9aba3d028765afe057025884f0c08382c40dca2b6e46ed20d
71	1	404	\\x568b5f3df5d264834dcf117a8b30cf07d124733460cd356743ac616ee7ea6f721e33e8ffd77f0ba47684b347438749ee1059b23cc868341456fc674d3e1ed90e
72	1	158	\\xea5d4668553c1a022d4e52427f640018cbed01c53654d536f4a00a0a2036f5d135d048a2f8949ee8a5b89d482f0f532ba41b920d2a77b381d10f3161a49b0308
73	1	211	\\xd8d87578ccf1803e2d80001cc88c2e1675a0221435a7a4cb5bb208e1738b7e4ffae89c5437a0b17208e01d711e83250ac4d904875e5ac51f2a91eb3b3282c102
74	1	120	\\x2374d633070c181573cf3f3ff0eb222e996b365872cdcc19b252cbd91021cb53aea23ba65a745b9273de0cdefeadea0c7ed6fe093f421b8eaa2694ad2bf98d0e
75	1	306	\\x3cc922b5589c08010d289227e2a1dc8075dd39d620403cf66a640339ee6212bd88b654bd1ddd15346a77177561735e9de01a524a14fa2c2f694b1f90f1d9e700
76	1	382	\\x3197ad368108b02d19ab6701c18adc7afec99fe0779ac8d9e0d847ef8cd21659adf71764058f2fcdaec65d0a2a24d6265b188f7d50c1a95b6a7f367981881e0d
77	1	343	\\xe8dc85a7b50d6157d0ed47ea012bd512cb9e9585ef1aae424397dd728e2d7c4afaa3ab282387508719b8670257354e3c92949cad65e4f9d5775d7d9f35a7cd09
78	1	207	\\x672a19a7b93177bd841c33be28b949785c7a5a26bf0db286f1c314198f3c19e8f6d423280f0b46505bb68ed3b26a3d83c5e06a2f77e8d50f4588239cda5b2500
79	1	56	\\xb9ab746ae72a0f25b0c76b0ff8a3f1ef3e88fb7f2c392ad52e026fb95e468837c304a822173d215deb966e02da811fbf1648349ee23b95f1b482c406f057e50d
80	1	216	\\x2660fc88b415e8607e7665e4edb7b48e250a6786bfa0f310eff608dc58de6a44ad84f377e6edca5982c2589b17242cf86f1a95711976583318914accf579bc08
81	1	252	\\x69dc1789c585c13527da62d335d239d6a528da6eb69f3a7434095b10afc422e2aa85ab94b97ba88e03643b87ce564cbf5ad380b2b0716f46106cd133cb59600c
82	1	283	\\x01339c74357490f7c4ec5422815a301d14595f03dfc1bc5c19c811c753d76126e7af5d2e0cf5ec0cf27058f927a0ddcbfd2b3a489e425f779a2c18ac3beb9304
83	1	378	\\x0e3fc96761b7e516f4debe9018d2ac841cb7076dc3c3292ff64a4abda37549f41b2ac5646387b92cf0af83f1ceb0dbbf120c6c140f2d08020c3accbebe26d409
84	1	10	\\x42fcab626942584b64d08107cebb0699d161073b8dd363bd10638d9f438ab606b1b4c200bee030192e6a679e7693877d7285ccdac36e00190360636002fa6908
85	1	253	\\xbd4e4c77958038f9995a2f72dd43f35b573aebe4428fcf02225f9eed01ba017d2d85d59cc968e66668f81d9b185c5d83246aff79fea1d73516345c161fc5550f
86	1	146	\\xb0d0053673e2fab2d2a0969e3e80447df74c7193a6003790393b000ae98a04fe700f6544f5551f2e02364be6f6677b8cb06d60719d6956f6696780a299eb0d08
87	1	310	\\x7306dfbf40965024c9c94276cca85c1d256f6e95ec1c3e59f5505a495f54d763a50e5b463f0ec07dfaf46080a6084aac7a1e5a8680bd0aa53958823c0a5d2f0a
88	1	33	\\x9c7139487727c7d2b58d0339c9b1670db798369db15109f07c95a31f57f421af6d8c93cb9feeed8cb4d01171d32cfd36b2eb2bda521c1c04b7a62bf9d45ef908
89	1	30	\\xf5ef93e740a4effd57cb7404309fd7dbb998869e56be59c374ce1c9e96da761e3c0c90abac5513b23b556e451b56488211304bf16f9184407937b0909b217100
90	1	366	\\xed864563fd0bd3b23b5f8d954ce33cfea1a2628174b8b4f246cf6009bf7e0ca094e620f21980b85fd37b980278a020afa4d05285a2e85b092c4caf567d3fc60a
91	1	187	\\x4b6a389a41efc81db57c22df592e08f29f1fe8d852a21f85691816d0a6f1c640e2a4133bf44d40e8b30b1a1636935b59d6a2d0b2e095003659840138ec9eba0e
92	1	257	\\x6d4a1f476eca49208c92d0e8c5911461d78d39eeba0ad52522ca999214e3ea0d0d31c138891dcd7563bd41ffe0fcf5bf498dd9e8c34ab845ca20ae516fdc6f09
93	1	375	\\xc0d71ef20ea939cdb624f2ef7a27a965ef032b727e613c9697d2f114358eb340a3b4e8d71b2fe45930a57903e6b8c26ebe02e745f2d71789177df4b6772a150a
94	1	21	\\x630af4444e80eadfee18dc3f3b051cee33abb141c3e5c2963d465228394d4306f15cc381e142080f039e59fca9233778a12e68ef153282cb5f6328119984160e
95	1	163	\\x4067e6f59ccddcf2ee41211179f3483ab545c0af39bdc99a09e5cf7eefdbb7fee446cbb73495f567532a2829de94d83ea29f4d4c4dfac9e610b8b13c97c9be01
96	1	214	\\x7f783900a93f27972f83c33748676f4189a0e433a4f5bc2fa3c6ed44691c10bba23faad9ee6db01b7553ca9e7e0265ebe40081ea22db734060d9db3c07281a08
97	1	263	\\x64cc1ce23f2752f8d2c632b49294b36a9a3d3499745f017778bb153a915407e9c76ecb69466ca9d02446959452fd6a364ea1b98e0207b31aea769632b9f8980f
98	1	401	\\x61645910ae3ae682ff9d348462df93d864eba73066a8f91aa457144fbff409050e5237aee3e55fede195809fb8d6625fe5aa061fdd5580012c31e853fe4a540e
99	1	166	\\xffee6700dd03b92e45284b5cad7ef01d9844d344ff61a15104d1ec8697231311efbf46f28cac1a9c9def425ecf414db00c5ad5590e78c5a65770c61acf1fcf02
100	1	365	\\xe4144c4b9639d726f0d948cadef4dc355ca17bfdb9a8a447e7afcc332604f587b00009f66a6f5e0ccbe94eda26c7afca2b8ae08fa2c6b1cb295caa8453b0f80c
101	1	333	\\xdfcca9a5725d9ab4705e8eab64a16a252fabdd2aeca79b975b7decaf18db53008cd13c96acde038d3c5b711e36b95a8e8ad17038989441805be01c9003afa50e
102	1	129	\\x7ff7fe49d4902d54b88f4ec049025f1fd5a9c133de4c4f538c3859256a33c70b9ed95adc70edd03604ea1af43e26c62dce5de04e5b53f3bbb6c98024f842a50d
103	1	27	\\x9a7825031cb0d1e70c234fb5152217821d3d7d2e20f605e9d5a03aca7a13491231267cd67a3dfe1e51cf20f35c299100eda7dde7333807eb6b7d85a84810a20b
104	1	66	\\x55de69378e4b10ba136950571c3eba1494fc746f6b22b3ebdfe32d94c2c19987eb2e49940724aa39529937a63ee51598dd6213116a8d414de7fc6573dafbef05
105	1	304	\\x0e266ce07f1d653f9cef30d2ada8c6789297493f81eb87a482d97a6511b5376dc63c8ea217acb3097a91a29caff23c28779a185b588b92539f436f63c618100e
106	1	345	\\x71f5d1b49aeb361d17d3fd36ff38057c9cf26c64b3b26117d36bf55cdaf637d908e6d14a3b6658832c95d73363b302f70cbaa2aa1cfb3925ff7303cd81fdbf0e
107	1	371	\\xc868eae30bb539802fc94b9ea2d184d268d79332aefb7a915ddb0fc3223d37c29539aa6a8c430c6ecb19b4b0c39bbc69f9ebaeb0481565c0b3357379e6fe530b
108	1	379	\\x4199f4a54ffbe09aaa9a51b88b6feb6ab6907303a729f77bed1665ce0548f2ec0a8f1661f7a705ca61933d6c01030e519fbabcfff975df6636066d7019ca0008
109	1	185	\\xa6d668c0c201f40e369cb0107ac5bef5e9f82eb43c50615209a8792f658c1570889e77202522563ffae7a12ee2299340e891c0652a9432fe65aff204235e970c
110	1	17	\\xf28a0ccc7b12f922f2093d814e9c516e7a8fc13cdd3ff546e77cc37257357d65f82875a797ec5be980e10bb32a6b41225489cde0dbd35355e7b17936e68c7e0a
111	1	43	\\xdfe2013a6f3fe49de2d742cf67a2eef8a5e246fab47fe3759dd6c9936e1f20ecdf7d1ce1ea091bb8247e7fed5e545dbe8764a6e8caa7ed265d8a234e45f5fb00
112	1	380	\\xb086172cb5c6660ee55736317f3fd3816a5df769c865c7ac6c8c5dd5286e8bbfe89749c7fe7e8531e0596a92f983aaa3c58b217ef0ec0455c6be16ae223fe100
113	1	302	\\xdbf10861d515792acb13f937679164feed57b1b73131a44194264521bd1ab2bd1b9c6ab6a18a4c1f6793bb63764eba14037a7a94a3e813cba17fd8f904490200
114	1	48	\\xc0c220fd9183c0cbdeba82d2b3ef2feba08728d44e2cf44e8530011a9819a6f989902534161936ee73a3572730effea39532041d06aaa9faf2e068c3111de909
115	1	117	\\x87a0daa66db932cea25c1a068b8a75ddbd708ff5c21b58b844f5c066ee5ee70da0de8495512119ff5084b8fc4b26c9a8869a7a092b32958ee2d8a18d7c41660e
116	1	97	\\x797680dfcaccdfa8ebae2d2cf8e5ab860706e01faac2dfbf34c1d1585cd155f94322852e74cd87d4e985371749d4e4c95aea4e232aa878411703fe47f06f580c
117	1	69	\\x696ef00f684087a518a4d8f1bb96c3590febea8a8ffe6982d492c51ad0f9550db5d53fa98678ce71965342e81d8445b05c3db1e9a1d3523f29864bc2ada5be03
118	1	236	\\x52027d3ded62b1ae22fddc4d16ec4ad9f3983b2ee331fab30fe9af2e495788471e923b9223c15adfd1e0535712e201f6ef2c5db962b6c82a078761396f1f1101
119	1	330	\\xf8ba514e7a2d82f5a2653ffb2ad132b3e5747e839e0983f65bc3cc92e751c73ef729f5a9bfa07ab7b6f05c74fda9e76ee851d1ecad4d1a0d75559b9055e3aa0b
120	1	244	\\xb8d149bb7906b844a932f5aa56e0ae1d9d9b754560544dfca3ea112a0ae58b1ffc9bb505eb8a673f4ae37eec09ada239b8b144007ce06867212e87bbc49a760d
121	1	291	\\x161094c86473724fef34f2ca1db3c20536afec43b5e43c3a68260d30ee2239322c4785b3f26bcada5a5f24abdce1c897f871262428feac1845c2cfaf3b773a06
122	1	5	\\x34a8b57602bb13d50cb746f05bed8cb772355a01006a6725321acd9a3628b315248e544afe715304fa28552c144039672a56d899f8311a8b1b651ab1ca209606
123	1	356	\\x859117e4d653543daba7aa63a66f858e6c1462499c0a74271c6ca3abb864da833185cae30a615a9d1bf8784b5e34a9bb013fe02b03d0d9d0c6a1c121443baa0d
124	1	86	\\x87639f4401a154853f35794f2b8d1647279a5256478f32b106d42d1f13f45d2609832c155e46cbed3c1f246d95f841cc695ce40e50709bc3936edc047f9e5105
125	1	14	\\x78eb23c5e7180258cc569732bf8a3aba2d96bf39dab18b7f397ca95335833702486c5af48cf4265f5b6792c0553f3a5555946b194681bbf66ecfa29fe616290d
126	1	13	\\x6e46a5e89f4c2bd507c3c55a886eb9375145f0ee5d5495ecf225356447e8348e430be04a58608a064ddd79f3da4b39c70ee9ba7807733fe97b94b2dc2344c10f
127	1	91	\\x3e2bab9537d197c70e9893bcb2b8e90da2c86b3911049d2e19335153ed4cdca7010303f234dc062745fbb16704bec383f926f94663770eda65d92a991a0e210d
128	1	9	\\x8ac88422aa8f51b1a1aec9a673759c6ceb8dda50779fe1965440a5b5024b39accc94d2ef9cf3cd0fd3e4ba8a622dc4f94f2d5ed2afb8321bfc1c96c637235807
129	1	36	\\xc735e069626fc7da50479a618efb3b9af311122ede7e04a349aae1f4f54f755285330705ebe22f80f6fcacf6787575836f6791115044a2eeee0cbd5584ec1e0c
130	1	246	\\x15e85794458b1e255834784e18623faeda4d3d6ef28fa04a3c451d12fa2ee2eb24a03b72e59104ab6dbb70cb0f10ec62cf02ce62b7dc289c30ad634c8d215401
131	1	28	\\x1d12f87b2b53595595c46611affde8fa49cf7593ecf142c72409483f91d24cee4cb7e2653a3477651a538e71edd9d6aede76868bc34c58afbc6ac36d75fb3905
132	1	418	\\x702be69321fdee551c0043ce56bb60ea0b9d0e060d61f6467e9ff02a7dee29a63b74e6517c526747852058287bd05b56ea06fd47403e0c06f91bc1478485af03
133	1	215	\\xab453f6e696a311246039b2c808ab2d77a28d1c7e5571c87337cdcca52aaeb3777c6e84fc4c6f03de428e263998df2a5271991b1fb6aa07fb11c5b3a99ee290f
134	1	241	\\xcbbfc64c475524ca443e2abd2533fb3c6cfa12988718f31c5170463dd4841276492fea03bd85708990d736f1bf2ed1d5f6b12be5f5c9ef24d39ff90d7d515700
135	1	393	\\xe95efa4b370ac19af64151a56bdde01f0d423686cd4566103fdb40d275825e33ba228957c8719d71f0691096b71e1cabb6490ea1be1c8aff5c0d8c18ea840d04
136	1	355	\\xba6fff5a3c56d06893a6fd429a37765340649feeddaee0f507e8891e6c73c5e0625358b7170fbbb99424051069295d79e3a42280a2f9729e8b6fff6e3c9ed80d
137	1	62	\\x700c6f2b7efa7dabd6398c8cb7f5e2e8b04f730358f16a4ebc551d8e4f48f3133a8a1b94594a03b955f5da6c55073db4cf49c16c5c1d2f272d9d862f9228a205
138	1	156	\\x8361991f09c3b5354164233ac07e1b82e561b3460c34e824873937a7fd55da087251280ca7ea2e05f61eb30f5255bdd1599f42562758596af4d01b5bab1e1b09
139	1	221	\\x838c2b0b7b828fa846831f039f242dc6767ec62934ec48a54616f38af12caa1fecc3743eb4811bedf760ab379938d1c34423818acc987364f8ea411c5a67520f
140	1	128	\\x81bc4e3299f7207cdac85a27ce1e70a9da18a402892ec83d052ac112cd52e73252ba07d7c364835ef0ee062cc1bb98bb175313f4628995865f98e1ff1edeb102
141	1	354	\\x1e8e34b80b8d487e75be84a4ce0a5729633abc4274f43bb2a213fafb3b747dd12bab6de66431af62026ed8b776a5c431907922a62744bbb90b533359342e2201
142	1	238	\\x36152793cdc8abd8317ba029005787e3e59af577e5d439a9f8c909ffa6724a1021e34cf657d207e78d7876dcf3035f0dee8d7f5ec724a3594f57053fe182f504
143	1	183	\\xa5b11599b9dd0297bdc815689123c4c7f3876f8adf3fb136e4791972553bafc7df03e735a78af09dc19d8955752fc904d30452fba4246d08e5157617a500df02
144	1	206	\\x04b2975ec3963942734b03e95c39b61aca3f4c56516ab2bfbb7cd6e01d3a0c619901dd46f568361b30551dc975dc57696ff1903a4ccdce24df7d5a0ddf296e0a
145	1	38	\\xe1ec2bfb623e468d81132f86b24695c244945862c475efbb569098150dbd0a601f61fd51dae96ced6e27879e3a8d9a4d22d8812375c1d97ac40d35a147f70c0e
146	1	301	\\x03d5ce18ac5d24d49634682281f078be2835645d6924de56941b6774a2e7de9faf951f44a5f2911f8cfa2231ec7eab6a4c1c44775ca9e1103d9f37ca535f710a
147	1	65	\\xa62a77047f019772072dc5f86e121256a6d987ef7c1bcf7018cab6d684d8b725a187ffe3a75f57e23876dadaf29af095bb3f34ddb176115fcf5c51f1400d9e06
148	1	137	\\x02488d9affae929436e46a4e0133920ba20bb38d903be7097eafa1189ffd1c039f59691a4b9c7356cde91e4e7014e07b4254b22e4781842992572360cf5d2203
149	1	300	\\x44d63daa9b630bc911fa2552e38f2824689b73c79af941cfbaed93fe61572f9f85751718b36c2e1455ecc8584a74777465c07ddbd3dd584761c214b1fa7f3d01
150	1	162	\\x70ca9ee6cd2dbdb188e690382a2f6dd44f4af27eee099ba30693a7fc4676a3b6fad52ff92bdad05f9621283960f33c2d4c1f4225109ad6448df8ef99110c9104
151	1	369	\\x2bab19d5da8bc85e83dc38afe659ca3ae14a0fb32e2f5f29464898ad3634453e107e36f226a400f8ba81cebe0e9f6d7c7ad3872a4993d3ffd52a6aa6dd32f609
152	1	76	\\xfb479a78b00220d4c465f786bc3d46b99461c3149490fd288560593451f527e258f672a4513c358b5b19f200676ae47d924101e14a82722cb96463a16ccf930c
153	1	327	\\xfcf7ead8dfc901f83eca15df3fb23e1b3e2b278a9f8ae3b2354cc62305a75bbab580e2d1dcf2b3bbbaf88687cc4733d637bcefb67df4f09a76b9f64b1601d40e
154	1	323	\\x1bc3e8d3f191ad3568b453dfd4bb131435e4fabe0b5e2b5bbc5341382a83a91d65d98ea14ab9297bf3fd06dfa93d2b69d0de103f70f074e82b50824d283e0c04
155	1	61	\\x91eb4d762da82dcc7f7cee6664a1960993139c1b81d249e191295cab76a9993aacc92e9606cf0fa53644754ca1328b4d3b763493c150a5e4c44c63d405bb4e08
156	1	130	\\x2872dd808b9971f153b9593f721982e06ae59778832c335afd49e9212e12d5b171f33b6e0e138c3b166fd1ca280be7321079682b27b0c442473f35f9a5b10708
157	1	247	\\x2d66a82155c3ec9e36148d12545edb77c99ad55b8c4eb09bae1e54def123ea2b2d622b9a896ef28dba2a2708b04f23fbc85478b1001e2a1a3ec0fc2ad32f0705
158	1	298	\\xdff5dfdad9459c30dc5b04f9e5e5de3cc601f5054836374fa67ce8e6d698eb41c80508e3adbf611f7981b41bee1cd8921545fad322bcb06a69e3a19630b4fd02
159	1	279	\\x08d2ce610d477ffce9ec3c65f811091988e1d9e1e1ee5dabd51520bd9b55afdad2f6901cf3da890979eaaf74ab69809de9fc1bce1de7da3f83639a01dfde500c
160	1	280	\\x8905cbe41f3cbe73875644270e195b79d14370a4cc5bb87576fb7c41cd8261f16edd54967a541ee47a5e2cbac429b7340307fdec29d8e9679230eb5066b56306
161	1	290	\\x8843927f7420aaae0f3adee54eeee78ff2f289909797d2923597fe10a1f680319a6d0b61c4a92239a97cb6abcf41d27e74ed3087e54885d4712e9e3df9d5cd0d
162	1	148	\\x6f0a61fa4c5ab715773520778c753829f65834eefc30a14bd772a1c82d6fee402dcc172d4b8451dccaed1ab4d6fb07b4c02d745103ac0bc0be709414acdc9103
163	1	415	\\x52228c62e913937ad2060b6ee02327e8c892c324fb97ae915d617f33dcadadd0a4d5d400d6c5ef7085e09f523094e2bddcbbf1960a0b8dfbdf07b45552091d0d
164	1	308	\\x06beb3b10adc00476439adfd349db4443423979fd895dabc4ac62ea3380367ab3d7a4153973825492edc765a38a98b3348985dc413b7dba756a3f9fb357fd102
165	1	413	\\x71bafc165d379d82ed34f029092a6bf2ffdcb0e6833205a477aa53517bbcef88fa7d21a217acc70bbfd8a46e772b55b928bdd81b92b1fc9fefd1fa1d39416b0d
166	1	318	\\x0fee4b9727b163aef27460577c6861d598fa1f78edefc8eb923b7d0adf4ffbba2726a0fd15372ac10a8f8ec020ce7c46b45a73923d266a84028975b75e1d3f0f
167	1	12	\\x86e98821ea3354d2fdd99033917503b7810b69919761959b2fc98437fed160a1257e5297b6dc18065be0908397a505c1383bf865fb61efe2a91f4ff82999830b
168	1	22	\\x50e2bea68e2b9c3e4729786fd1f097cacb42b7da61daac7e2721bbd320ec02db559a0c9bb105064457945dfde43e021c0e14085dcb44bf5e9bce9b3911579e0c
169	1	348	\\xf60f90ad00aea4ea1c759931165a2c042c2e857f88252eae20e53e75ed727982664594e0fd901a23c91c6942b5d7ee0a0732ca97a30b5bf8764ea976d502ab01
170	1	19	\\xc78522cb3a8478bbadef1b2889d20a548f943382096567e8b415f8ef086291977baf9e6d8bf814b0a5109584295be548373024ac1a90435193fd537e23473106
171	1	287	\\x6323c21b0ec98e6444306122488316822a7a926eb982f4dbd144b1c5885787cd63d5fa2e586376a8f97522ca55ee483874d17f997f5ef449d94781f588053607
172	1	383	\\xb86023579162eff1cfe684df87d375fe13431271d995bb2b172be29ba40016c64ec4eca204d9cccf54532bf3daa205188007f3b1af5b13f7925b665d13ae2301
173	1	160	\\xa77986c333b64126207c63951c7785affe1b1a82e1d7e8f1fded82771f7c82296d23d73fb5a6ff7694e65f8c6ca0b4fc64c5e5ade7d9a89fcde6634e1c1e6600
174	1	177	\\xa7d3e266555b3bf87ac3d6974a37fe4f0e214da14929b109569d78147194be06796b51fd92bfb6d25985d03d4ab361ef5b400db6dfced5a76cc782a0e3005c0b
175	1	357	\\x645dd4b2245be40ec577ea43d8f4ff7a9b47b718f27e7dd2e736b1c52f694880a30b24f090860433e37777613c6f1ab0977885e2111f99b204da95a7e0f66e01
176	1	197	\\x9437fb2fe0f4f556793eaf82c8d056b170e742cedbd0166acd0516fc47f7a7a45f706b9933dac8a8e33c185258405f504c72429ffd598b8ce96db5efff238505
177	1	227	\\x6d6472e8e9015896b902415224fe859cc06a603807ddbb5a53850c62fadfed9cea71728f4b75ffd29391ab9e775c7f083bd8bc40ae2ac7e78ef589a274915f04
178	1	242	\\x02bb5d5091d0b8c0e3f158c341565ee2b1075ecf0495f2ada6d32b4dcb331423a23fa5397c32814fc6fe7b83c04174e0c412a474fa37d561152442a76ff11700
179	1	195	\\x66dc3cc381bced083cbabcfe04f026fa8e613c2e494f33374e56f114a7fc69c55ea907636d45a8522d6cd639e854e8ca7b90f992486eb162b85a74f993bff306
180	1	2	\\xf514c0ba2d0f66fbb5bd18061c14614edb4e2de4c606da9860021defc49ad1bb260b073dbe27819f637521aeb7e44d5c94ce50a73319179079f01ed9d69caa0d
181	1	229	\\x082d3d0856a724c130626781dbbb2e5c0071d1937bbddfe751b55e17a2483e425c3d606ce1c1b7ce81cdc2f857fa38fe063661a652e9ff3bc5b965ad7f3d5a08
182	1	106	\\x545c3de938f24617dabd8af4d142083cfdd040184070baa75d4c1692af728e8bc4bcdaa49649a83465da9a8a50ad5ec3dca229bfc2abe1732b9bd6c74cd7ae00
183	1	94	\\x9d2a1a299d176f3c3d9f9a4327ba786c083c95d2fd5a9bad5e27e42b75e9d52b139094ad403c44c20842da41c4668363d246a069f33af9161cc1b72db1012400
184	1	46	\\xcb9359aba31c2ff0e89681f97687fcd3d729de59ca9bba6f6aab675c40178fc7e79f9d8bf4e9ac86688a3f41cab96b68d5f5ed491c0b7e3e00f86f4c724bac0a
185	1	266	\\x333fff83ddc2b2fd4b159745a898a37c8ad74c98430558c59eca92dfedce42fd85b406b4798152937c6449a9a1f694f7185e167e70b7fd41dc9de5c34f748d04
186	1	194	\\x4c55c22f56f8f24ce659592a7a61b9f424db49192fee8893e3ef794582ec216422e8358a03ad663f52e665889724d4c1ee7fb0724d44cfc1a014f02ff053710f
187	1	305	\\x8c7700dd707ef068ab15ae478096aea0546e5992f897999679ecbcbf1c952ae52eb5d7a86b226febc6597cff9e7cffb826d8a01b1c6677c724cac2ba78b51a00
188	1	189	\\x0685c0e475bd899e818a816be419f759e7ffbda901fec17ef1b0e1d2e6153dab415c6339849e5dde34fe53af937a7f5bdc0d00175135bb1c4a16f7216b32490b
189	1	110	\\xb1547ac9eec38d6f1e2cb4c329e555896844ded07a8edd2027750590274493dcd49b9af7fb4e31dab046c3c37c2591fce36df1ecc655523ffdb1d9a6ddc0de0e
190	1	39	\\x059543fa43e02bbb98682b929775d906148fc196bd674436bdae30d6995a409388354185e591783ee815f0fac01870432ed426cb7872c0c82de95763dec62a07
191	1	219	\\xcdb778360ff77dc1815c2a5ee98962503134684d0b0f1129a69ed0d8f89631ec762bf3a480998da3273770d6ec0991e0cc9414723fd908b40647d3825a443a0c
192	1	402	\\x8b5d49e0427cf3e5ed39fc950e65d6fa1e46c19df18f59ce5815ca4f970c1451ae59f64e34445d3bc2885af3473980045e0e3f12fd088555edf08917698cad03
193	1	390	\\x55f4b0f1f7359ecf72559e9a7449e5ec5a5003a44f7eba117dc25c0a63dfe90c952210f0735c87a201acefa5e066c48dac76715e14c04a73149f9316b98ef604
194	1	240	\\x3caf2dbcd4e7aad1f18ed014e698c00b71e6d0bea964d862fd46ac5a3ffcd6903e0360740ca7c9d0f0ff9dfd1bb4e6e0c30c90f1483ffaaa4574eab2d71fed05
195	1	173	\\xa5edd6fa9c11a98adce0beb5aa5e869fd96cc021a549105181ca061daf04c50ca409133628c495bb22cbc6bf3c99c636849b504139d4cfe0b18d4d208be3c706
196	1	123	\\xa197e32bdf45c44f693c0f6b5d756004a1a57583b306cf237cfb683d456c9945ce308abb5cbe79b667edb46990a0e81c89f9f5641c32c4965f3ade968590cf08
197	1	175	\\xa3a8b59bfd14918890a085cf39bb756572975cae267f6e75505b30699860ae8488d2d4250d2a10d741f8c41c6a185e0dde89255aab19a43c86592a87c8533b00
198	1	223	\\xfa0dc225ff84602ee5701404777aab18753f110f2f5c67238629db599e638eb0f34490403465a7b18ad9c9d7d7009241bdafa890bd5c8f81fe6ec9ece3e7520e
199	1	392	\\x7b93462679664941cdcf7edc550fff7aaf07fd31bab9fbdc5dcdf13c49d63b5acc3751f71b580aec629b625794d6467357ebf26b172c4d7afa82a228aa3e1706
200	1	408	\\xfdeef595738539e2603456a6bc81b8e126b45c50fc90ffe7c44b9349f25564f60b4dacf050f37371630cb729ce298a0bf115e332172a0b93618edc79dd792c00
201	1	313	\\xdeed0887e4215693142f8d867b1fb0beca1f766cd5d56274b76616f7601c081f98cd9ba88d2ab669de891ebabc74363276669da7957a94ac1075adbe5c878b0a
202	1	47	\\x0aa9c90686141362c00b5f5074f845787ae85c9afb8dc31cdb92241ec900e1a0bc459af7fda62e184bc9a890da7f733e9ab985e54932191500abaae15050bb0f
203	1	172	\\x6a95339bc7001b30a5e0efa8f2f779cf64ecc630609fc4f0fa4a664decf3d5a6adb8a5650ec60c27931b7fda5b19a551e48069e815e6e318a4293474e7f5c40f
204	1	179	\\x435fdbe728431516deff971115d3574554a8944056a68d3fbdfaee6affc474b0f52570665ce6e74453f0843ac653239acca87e818718dd6ca5d9d80cf92ca00f
205	1	95	\\x88dd37f68ca6c2a6cbf5483e28cc27779e6d871383c94068b7a870960cb02160365618799cb8049525d635597cb278e224e9d16a3692e39d67af3d535d92900e
206	1	218	\\xcd90fc790aa6522eb425f85d9543920486c024cfd3a55253f0b1bf00b51d1a0d935b6b35ee0b5504653bccf5e8eff5894792e0d52513817a4247e0fd97b46907
207	1	265	\\xa27d498e90416e303b8b10ef79c7a911e4ac330aaecd20ffd153a9108ed1bbb70292ec9132e720c857d9751b53bc0b91f00b8fec693349a7f511fa39a740040d
208	1	34	\\x1ae64097f261c4157277138dbb8309f779307b7ccbf18096680da04c59b94afe18abb33ec1fd5e0b8ef0ff63e9e32533f2563cfab208c3d06ea3089414a1560d
209	1	276	\\x2588ab3c878754b09d4d5fba356fe71b89a9138d1305e9986be4f5c011a347eedd8760f3f5e873c281fb28aebc162ff7ad3144d15053531c094ac03c30a39600
210	1	340	\\xf5615e24d4e21de46364ef9d2c29ab50a21360bfdc4ec2376f59fd1cbd46ebcb5e9b9749e865bb864d9521fc90d51ae55e89fe07757d77f987cc9b3a3a83b80c
211	1	364	\\xbc11c883de0061f6af573c5ff40cec15506f0368591acc6ab0ed25c3e4bef7e05b2251e85e434873d8ad1b310b57d75cbaa92d27f260e0919b090686c5778500
212	1	372	\\x2de104d636b10e02e1db3313796b833200be321c6a3c89003d73cd19d2729d98abc99a4c30d3f14a3213cdbc04d1b28685cc6698b2ed8f45d3152ea3aac87602
213	1	1	\\xf97efbeff739c5ef2425892033b0121cc10ad8dc40838316eed42c84b7be5646cb59cff71e13bd042f5660184406c68c86e61bcdb45484a3cc4f3a98da7d7409
214	1	54	\\x6a47232f908f37f42dcb721b6228c5dcd719a3acd97c1d66ca9be48ba36268bd7749c46ab9efc22d93f5505c71658b299e2a02a49bfb96f9456a09fd5c8ffb08
215	1	74	\\x7912fe8e3f4c07277b9e0ce4ca675f3b8f6e83ffe9aedee2ffe9ef119a44735d8bd33de02488d62db58570c84c0db73f9730763e3575802dff8d80f6d094bf06
216	1	52	\\x57b4827c36f5e8427537c44ea781e2a9d01db06e065e8e2948e820b93b1141140669541b7d53370f27db57c56c4d3bb6741dce58f093f1387f55362ec307bc0c
217	1	273	\\x26630dc2e69a737da5b3b3b6bffe24403d29b575eaf91c37669af86e6f942f99095b9a17aa05f7c7bd33eeb43e96e864872138164b29f26726b565a26bc7b303
218	1	361	\\x5629b2553c387ecaab24d8f749f7bc36ab74e23d2b729901621fcb3376a8c0d2114e858cee2944188646da06c9d9ae8cb5c815906c87dcd6e1005bdcd282880f
219	1	396	\\xfe7e5d24635a6155472bbd3099242f7ca6d090c61126958b84161df351e7c60053d24de9143d8fe46279b2f5b06a7b7aa3ddb0ab909c565d8e59db77d829590e
220	1	399	\\xaa6f521ddbf1b8271f9132bab35fe2dfde07c2384773179f7ef2ed0f9735cc22e93b9200da92aa36991fa97711f78d493d2211e150e823b200415cd44998720e
221	1	338	\\x653864dfaf68dff20ffe8898a9d0c57969a6373abac098060c1b6ea90b0db717bd5644638323867306c6c57c7bb639808e48710eea4c9d6bf29f4c342558ee0c
222	1	192	\\x5778862d807fa4a2e3b89beaedc12b1c48beaa6f242664bc237d57cb913d6510f850ded6eab09c8d9c5d2cca36aa75f73c7f2b98452a8742a6d8b3aff6b9410c
223	1	138	\\xf407f7c6b5ccbb0b587e3008eb53468b167a360749d47c1eeec5ecdf9d8b906290b9f1218092347dc5ca2c7d2baa76bbae4c24ec199ddeb0ce2d48f773be4e0b
224	1	20	\\xb84919870bcb9ac71b12597608208d382ceba17e7cd9401684c9f395b7235efe1c574a94e92896d50105ca99a0d4b3911cd71ac6249cb3186eb906ac15d09b0c
225	1	143	\\x1c96d87afc4bfa4cf92ce1b62e1273cb32d6c0edece8fe94f72dccbf7473f34444b35a7e89b8ff769c24858774f14c5aa7f333951133bd6eb82a7f6b8447f905
226	1	41	\\x1c4bcfeb309b614a7f793e7476dd9c934c1d1b4977f0e46c1fb9a3da6a97c44192d22386dd560059c197614f400842d412b5fce885674b4ab7c9be0e52196305
227	1	100	\\xb18fdc16f5d99d174fdee56e100399c353bb30d0e8584a579a1b1c4902f79c528bbbff1b1b606bd01abbdda7200f796b17ae27eb86368d4cd0b16123638a100b
228	1	249	\\xb12d7133fbd8142abadcd4dbde655ba2f8abc7bd4642b4bc4a1f41af420d05a42255aa7c9310b0e28bc838f876eafa781d151f8e502b904f7205801f616cf505
229	1	44	\\x320c5883de2078d8d04fa984c3ab5a270496f19fa8041684d46ccf9b95e04cd290f172e60819d0ee919d2f581208089bf69bbf03de35e3cd32d6f7abd86fbd07
230	1	296	\\x70d343ea7dd7fa68ea62816cc3f57a7c83c4e1dbb60879f449ed65c6f3b01151b17969654d554b83ca6fe79885430657a148f27145e391464b1833fef109dc07
231	1	224	\\xb3e5f2351ba2ef91697a2b7861e16c07b00ce400e70566bb807ee53493a3ea284056cc529d9c69e3166e3c0650b4711f02d9a18e3c359edaa67f64ac43cb8d01
232	1	164	\\x998f4c56763969185602521476c88493c0292e20cd6ca9f4065295042e719316a3432efec30dff4fcfaa9601dd4548a4d6c4bda07dda2eb906c1ada353db3f08
233	1	25	\\x82ce5d8db0390aa9ac68967831c3cf323013f18a6f132c0cbd76d8c33f5d0f989ad0e0ec48d3bdcf461d7e5002e054741c9bdefeec25f8ac890b57c67a5c6a0b
234	1	275	\\xa689aadbfca988342075d594016b9879da38c280c26b2044304ae07c0f7191b8ded5a6def191588ec2a49f74bfba55aeb9f4e9c1e4a32220606621ca4f8cc80e
235	1	272	\\xf2ff13cf635ee8e615d52e24fed9fa6f97c89db0709804a3889a00845962566312827320c8ebbd3b807f19e8f0d5a5500c4c2aba304665004a0551bbad8d990e
236	1	96	\\x5a7c54fa7d824b014682ffa6ca6fcf6d0514993cb358cacbc7a08534d2a2459ac54b795e0b6f176742a11d176507e8157b562c8c8988da826126e392cd66aa07
237	1	274	\\x1d1b1d52aaeba6a86bc96e0d2f380fb4223cd1942ac39b5760406795aee89b224ee469b0bc22a058dd43eb9a76d1e00bd50cf1dd91854f34e5ce66c0eadd9401
238	1	113	\\x5acda7155fcc8eb64f2e2e105e1524f311ee3b313f7b87f6245d2c9d5f03336f55cccdb27ec44ee20ec767e67515e1dc1ac07fddfb20ff6f878025f92f63bd06
239	1	421	\\xa34fcb80a0d9cc6568cc8eb073362d520af72652b919ff55070d4cd18230638a17497f35d29b7e3bd120675a7961fbd2045d00fba9f4b871ab855b082d898d0f
240	1	176	\\xdc350c814bf69020744531ca7defd54024d188515953e454b61002993d2121aedf85ab4cdb2e4bd26d7790e51e2cbcaaafab2bce07646490a91fea9fb8984509
241	1	409	\\x058868dfbe41be9c9a83f273f0e2c3d825994dd77b10692613a3bfa87e0db3d3e2c0eb29800deb0985d8dff94d0aea27cccdc40b1f38d4a1f4525f818337a504
242	1	122	\\x74e96c16d6139db42ea6febfdeb8f45e2e295991eaaa3558a3437688e2897c59ac7188aec6fa730f58b649274865f73d6d2c20f27c7e1248705b8b43c4029704
243	1	391	\\x9f5b0c147e92db6733e02fd98ac28353435e29e772ebabd760b04ce6a9f5f9e25a42967fb644d0c6a1093e4f4443377f5bbf5291ab58dcd79450f693fc104608
244	1	184	\\xc1dbff4e8d92aaa9650b17dbccfff71b7585a7133c63391f7bf1cd7fc74befe4724c51e93ddc98d206f9f41dda0abe888aea76f31a7e23c157cb72fb9701c006
245	1	260	\\x14cd1deead2f1e2dee533a4644dfb2ef66bc89a60c652dc1151954528d874e62ed9afb5d8d740792396ada48a0c8b2d1b49d435d74fe49ca122ae1834f77ae0d
246	1	200	\\x52cc66087c331cecd36528b1fbc58aa2e231bdfd06060665ee02352a0b11caa77a968c2156b4f616ee9fb0b5a9a58600e670ed0d325f173c5d36b9675085090e
247	1	45	\\x09b63079009364d83c955b7e0fbc5d41e6841aad584d9df181aba122a3a5494e8db14644f9a6db296e8aae1db4d0f035fc123981b42741ffc13cda2955fec70e
248	1	258	\\x43818354f49b9bf34b631c4f37243c4dc6793791dac11916d26ad98cc21f55eba880765104334676c036b84a557a830d4930df182c3cc7ff75f2b3b29920f900
249	1	186	\\x16ddf9fb4d24ffef387c41586c2db101ce1cbdd325ceb229b5f34a4bccd3ce2070f880b9234c8da7c72d7d74defe68e6e967134682d7d05f4c91bcd2d8c92c06
250	1	53	\\xc12a7804ed244315ed33818a7b2f99af3c1977cf9f9be343b44260154af06218a6a5764c650661aab5734d7fa13614c140c7e6edc4a7e9cea6f1fcc9154acd02
251	1	147	\\xcf839449580afa63a1bfd4b506cd751973d1ef8efece8f846a37eb888118a39c4a52eb90c596222ea64f9c003aebad777e7d5933cc1411505801046743b57802
252	1	209	\\xb430637aa31646ed24ed2f5bce38f7de87349fe7860188bdae3d52b59fbad7f62d17648179fb08e0dfadc932dca18a3e726971d74614cf6149559dccebba620f
253	1	3	\\x7908aa4f1b98488524f1f696816da704d6e3e5c542eb17e6315186a71915c506975080806024b82e196418883ff4e388af6d2b47b2f609f3312010d60f84cf00
254	1	112	\\x834b6422ec7210c029afbecd6437a275d318741fa84794d80deda0db7d08bded7d8356cb6b329d719b05f28e95b10e6c80dd242d3c454c1af71803dd71c8d607
255	1	331	\\xf5a23f6e650ec7b2c0fb1096ff6f9997646733115f92373541a5ead0bb602a00acd4b24ea4325ccf626baf912583c5fd2c9337fd5d87ca2a2c1053f470aa5c05
256	1	407	\\x4e0c1e037c237d8094fe881a42f66fde03a2cb1fa156f513fec767a47da3323cb495665262b2d369809fa4e5504b7434cf07d1b8263550f21e6ddb1b8bfa7807
257	1	35	\\xe99c7da75cd569e238a0026f5567481fccd8c46ab521e2f0233765f5e3a7442d80f49b0a399898a8d8eb53bbbd92e6e3a41ecfbeba610d57ebb291eabdd53a05
258	1	360	\\x1312439c80f36ceb197fa928e33e875b02b7c6aa3589cd0d1c5e5b99283a7c2de8da4f4da461fad1ee8142c8a1a4bbcac4dfe3b19b8e5e8a6b6ad9c7ed57a60b
259	1	127	\\xa48fc05d9ada1eae0cd7ac785228a2f8743bd378473b580d2f0dffb18b857a924f9beb57d4a5e75e267060f2e76a91258ed57b9a348bdea9f3b887afb8ffc703
260	1	149	\\x015efa838c2d9604d911c7935e621d5f9602497d8f001c638caf2af823f641d416fb07dfe3f5c1d57fc1b2b917a65ea6d4b979e3f45afda01c3ff25ad07d7203
261	1	188	\\x82c9e3263b5cbd36414c4a9122bbd95aa2043b5c538ab10b1a7b6570ce24703479ae6e9ff42115e38c24f6a51542df39d021db7348035c8b034343ad90568805
262	1	202	\\x75122d90554dba709988f70234237553a4ea9a61d6d80e5c1fee8a779527a95b83ca8bf952a548e93bc9b490a95f35185b208588dc2a9bcd2a7da84c4e36d90c
263	1	352	\\xad633edfb0774430012dd84cbd40434618745bb98d8d637523d3e076e026b3fe5f22e9608e10f96abf450affb4361d29cd59443b9647fb60d81fefb740ecef0b
264	1	256	\\x0f1367c22366770661d32b71cd70e654a835600af4e6ea963f79fda4e23e89493593b0e3154de9a3cd1ed3701b775c760dc4a06ec765df85e73840224e12580f
265	1	107	\\xb4d26471c86885e5f6af157343e49c1ff3632f95909c7a2152c87bfbe83a0d9409793d6aaa3ae6a8cf23f92fc86a184fe115045269314b910d6f8e1cd1e57305
266	1	212	\\xb7f2b24b87a680a9e15878b8a0bc7d495c6e517471d9a0ecc9818100e24be682037b133c9928ed34faad5c993828d1db3dd65c27b24b29909e3d5904af0b7a05
267	1	78	\\xf4d468798a507d5a60726de961a634965dfd3bda694461227cb55cedc9f6508ffdf4e0ce263ffbb1455e08d80f360ee5ba8d43be949c0cb8453fd99af79edb0d
268	1	82	\\x492c5ab31cddf8c522715b892598749ce0a0bdb1fb216c557efedcc742d855b9a1b316a30ee5bb3dad66803fedd612c94a5498fc83e26d5d4e90faec36206303
269	1	377	\\x97c6b1799d4c0e221567b8beb8bf35805d15e559facf3d927bde499752bc7ed23cc9385d09e00293f67ace9e1f8d503a1ae3577d74d9156731b2bdfabeca7707
270	1	81	\\x2fa9da3b5c2a7f08fb519edb44e2c0ea98fe62b41a586a51fce2f62ab37c51431008764bdf6b7accd47771f6a96903d6c0ecd4ad2df4adfc5bc437081587680b
271	1	374	\\xebf6ce19a344d7ac57a616597aa4bf82256616979a301b42d8600280ce06c704fcf2cb406e4de392dd1a33be8c7437bd47d188ff4662548fe4e3bc066feb090b
272	1	335	\\x8965dec2b33e2dcd0911208d8f8eb8034a893dfa9b7131a9b4a364d7dc40c7faafea9576ce26d19412b2db909a49816009a9e56c981db0d66e8392f8f3f7540a
273	1	328	\\x70a9f855585b88d9d69ae7c6d5a685ae074a5342ab2aa4c7f7d8bcfc691ec1a2442df0c751dfddbcc395e9e068391ba083566677c5caeccd6b041c7eb46e770d
274	1	152	\\x5317b8c956ca3fb935a9538497ebc926f56994f846d8c19cd016ab575619bddd18df3a9f02295c79e79955b6097655794a8a50742bdc4c4c13bf530acb2fe30f
275	1	234	\\xa58f58819a60bbbb47f28ad100c801fc1a6c745766eba662bdd0a8666e58f04fd52f2a25f624c73fd9aea731df4b707fbefe814bd65fac11be65fb99f4985f0d
276	1	222	\\xc355dda513eb7e24607a2c45296fd7f08a80941f36fcf7761d39ec60c71f278f3b08ffd252633805e046a54acd5956fccc2e8f3ef1eea45731fe7be8be5d460d
277	1	119	\\x21d6e64f39537c2a1107b02b4a60aa3ee888e6871c93d4d983e6ad4941df72d06649f64cf9c02d3e55dd51792041603afd8b0a315f546d5943d97d7a4796540c
278	1	191	\\x909c0ab074f48763eeb48e7edb0e5bff7d504ce3353f56dd0ea8d2d33f52bd9a1f09be877bb05c4aa442666470db904fb8adcc215d92b40b41bb5d64dd10560e
279	1	285	\\x7a010c471f7e1a861d64bb52a73eee4fd338a1396e8e413bf3833cd542ee579aef57c55b71c80a9c0363011e98e6b50ac43479bd27c486a8835e7d1f2409f80b
280	1	180	\\xb2a9c39728bf3ec992ea73316bab510d0e3512f6f55d8af3defc4be44bf2ed4468cfec9223c128bb06c89045d3d7760cf549225ec50baaa1a65cebc4ae4f6d04
281	1	358	\\xf6119ac4f704cfec398bdfb7f0ae72e61c5dcc76fbbdf66f2679f1b91ffe3453fb36c081d4d760c64763fe72e01c6131c9e955be7bdf0aa58df9cf4055264909
282	1	204	\\x0753d896bdaa38cec279b32032e3ba1f3301d19c47e81870211339db32fc8dcec0f726ba5e01a28ab81d14f7fa492887af063d1f6e42cfdbf19192ae0ee0bb06
283	1	297	\\xacbb8ca55bcb5e2bb3256e0990841e5082744a617c3adbd77b282a13e2965664c52659d7d5f9b73758463eac48d3bac89bc5e4ddc49e1ec299e5dc2703abe60e
284	1	108	\\x5b721da701768740580c22a8ebb20a6d5c3fd917634c8fe79d3dc2f4d0be092d580f5a939ef22201a40c93c61749cef65530a80eeaa16d257745c5d72914440f
285	1	16	\\x48618e7d59b3f27620d2554382c77df5d61fb16b2e3ba59e7d1d8e71619368ff741420719091a037bef6c75411716375644d9575d0c9c996c492a1a52d092003
286	1	167	\\xd4664772d5206f11a7bf457bcb2e8a8fe1fd2ac7eed698e01ea1a0595642a6ac05289471529c67a834d34c47510381d5a6c87023eeaacbc8ef8e56cc974f1900
287	1	235	\\x753bd6c84f2eb74555276856865f8577b05928633651533e01dea3a9244be5efb9ef174d64720c3ce39667c9d9d6950c2ff1c4f727036a83b737bbeb6bce3f05
288	1	73	\\xabd5811afdf032e88d06a11a823ef80b08c35e661a33d386385eb0eb58ed890e5d1f7752a6fc2035a88bc75cdea8329396b2e699da4ce9cc28ced56f230cf307
289	1	83	\\xd74cd6aa995b54e5f73d4e324757e15db27a59838a8a66e65a34ee589163cdb65c03dc40da19f55cebd0e939b659286871486dcbdb95be8a6ce5e3544e59c208
290	1	103	\\x927cebaea08d85f63a57aec716b6a6190ea8a6eb7b42ef9b60e8f0e7a5e5840cee500c64e4fe040e79cb1402190242d8e0e6badc0fa448d8e98dfbd7e5445a0f
291	1	373	\\x2219ad0ceccb2358a4c2a867c95c195c6caffb74347f68a86e30c1e0c14600ff953579d1dceda8e4c57efee45d45fa83d70d875640c74ed5645a634e071e4c0e
292	1	210	\\x1402842258868382fc6221a7afa14277c31f5b33069be1c14d8e5a16c816bb2e191da12f41cca91a5863f3d436a86175f7ec5c6f8642ac2c61baae1e83e5e30f
293	1	155	\\xfa516df0d26c0afb30e7f451cb1e95d06ae6d85aaa50d3008ebfe88319ffd23364e7fd574369b78bd0e2a4f598758919f424772506e389d1b9100ca05a61490f
294	1	316	\\x1144984f45e89f73b16d1da2fbc65bf11934b29f56aa9e531dd9da3d69d76bb1adda10f592c44ecc128934340f5715454c1eded878ba8258fccaca6d7adef607
295	1	181	\\xb3be713409b4ff4c7fb671e2771242c9d39384540d068afeb676713678643e9e89eee5c1613ee45be3233712cba60ca35b2096d4e46fcbd7defd56ca9115fb0f
296	1	422	\\x922c0e7b4a70e7bacd1c189438b1d18e7a3cb5d948998b6912bfd1836176f78e5eeea24b35c721978f90912c4eb8c8d797afd7094e45262d033d4e4fd5ee6601
297	1	142	\\x01930b3ca110244b4078371723768f0665d1cd62f39b8eba66cfeb2ea347484a8e7b4e23897e41b382afdf583f3a7faa17da419503592fc2f4946063871a3403
298	1	165	\\xd5d94285e652643cc2407cb38ff0ae0dd8193d4d3cacf0dabd4b918dd1f1ea779489782fa6673000777d4405266077331f741f44c40805e1a236302b9341b705
299	1	232	\\x7029fca3c47c1a038abbf7aca49b4abfaf893fb267a5594b532939f516b7069c60392d7f9a6cd655256301fc7825ffe231ebd74c87dee749e8a5f84a5b01090e
300	1	135	\\x5d24448998c5b7b07dad17bfe6c0f23f10604a81b17e575a1af85b21b3822e7bc2a368d7c7d6287ed38f535935130a903fe279d453135adc1f734b577cd19c0a
301	1	32	\\x17a1ae6f722d231555d8ad2216204b7ff95c1fe74f73be3dbad402707fbc4e774bee483a2af6483431cf9a1d28413c105d37ad0a673b521987365df2c22eef03
302	1	105	\\x69794c5b4f50d7290cac6b7f15a537d7626374b8d644814da8613624d996a29c8def4333dd849db55c850afdcaead597e6784dddd761224c1a8ba8596cfa1e00
303	1	6	\\x75757d6be82bcfeffe87a056cbdb410d871df1feddff713d263c6bfe1e9131cf2f07475b965b974064f32c58c2efe0e827f0f194f7b8c30afc1ee13b44bd5e09
304	1	321	\\xc184a7bb954c62307f6131a1e0beb9148e21d48935f9a515c0a3f53cc3373fca5ab1bb30d19f08711d8d42b32482f2d6b1e295435d334c0f065f66ae9f18e107
305	1	114	\\xbeeafbbb089e969fde476fcb928011c3428697d2a1aa0af35fde4debc4457c5f4e3b847f11d3e6e39e36239d75503eee1488675557804c545d30985679ad8203
306	1	388	\\xa1b1a727d833353075d2520abc9fc80b6a9cffc12e0ed63bad506fc3185cdef8de6c9187fd25520ae63f5ae561d905019a6e929778fdbf359b185133324cc700
307	1	136	\\xab0c745f33dbe03576f13d4c649849dbe0c3bc8a1d30ee35f5136a2a40956831cf379b1bfc306cf68d17c2abe0c12940690673bb36397e523c1009f9b711710a
308	1	230	\\x62278d560d59b3f8c8dd70757b83a87868191fb9ddd813e896e6e9e7ee547331597e2058557e82012bc4268b5aafc21d0cbe77c3f2a5491a63462065a1487d0a
309	1	416	\\x38f4296e61dedf7c20583ae6fee93026bd413e576843773ce5e0eda982b574698ab9cd7007c5ec0399bf194c6c09d0d9dd7c581917166175963abbe17ec2f50e
310	1	347	\\x56cd96c64579adaa7aeef2c1d02f9b53b18cab8140c7244d4f7e6c8e582a2ad995d204f0dd7bcbf6b98ac0264271a814f2b803aee7e7b5ef73b58708e39ddb07
311	1	251	\\xdffc330fea61a78e164cb4ca9b3052062d728d4f671f58619c6bd0575a0d60143d52fd908b00db50aee4f28014aee68da07dbd38a25f61e4e90f286000c72206
312	1	231	\\x76b9a36c7c2ec2b5a26b27bbe224f810e8ee114705d8413fc60ac1112e4d5761d652458a5a32654ba07b54f8286aa53c28e687a26050e843f9f3598b0a16d30b
313	1	57	\\x70b847fb9a04a67cbf68acc5fce0901bc874dee4e57b0d5c9f79854792ef18a9b0e806d797a6239a805acba54213237063df1b202641a4916119ba9de8d04308
314	1	150	\\xacd34fa0cb4937aeac17c6782f5c559f275d35759e311d0270b7397ab687187e33765ee36965e013685e215964f4143780a7b96085297821412c7829e2eb3c08
315	1	98	\\x16272fc5754c84afdfdeb7c915479bb22858e8225923c7f55791ec0cec251696a136bebe1a4b880194ff494821b8d4b26e9384220a0747c5f96e4fef49beb502
316	1	111	\\x6d4e0818709c2e19bc6c0161ffcbd3f8d0c7f3ed5c5ccd075cc89cb494e549f7514825ab291544dc3b2b9f932da39f51be9de813354094136f4851083b760801
317	1	153	\\x2a75d364b781674df85560a672dd66cfb4540451f903c28e92b7a9322fe8592d16576354321a6af7047a2545c82a20c10369da63816e127f2d14e72f6da9200e
318	1	267	\\x20dad15345945b2eb491d648da6c74fe2925ca9c280e7890f1b42fb4761a876a2f2a72abfbd5bf5a36a534a41eeb63d4e9bf5eac9506c611113589516fbb4f02
319	1	342	\\x18ced3d34bc23ff5e010e9106afcc575f1a09aa7ef6af90c68c23d8a7cc8da177e49caf49c73882a16f37ff57c86616afc1303b99544c5c81ff1a8cf9a714306
320	1	63	\\xd8ede07cd6f3b2dc7c27ea3c0be3b8008893991d6c7873433d8cc85da0e6932a66430a3be3834401d421b43d5ebe03cb4297db10d07a285fd63ea0c70e2c250a
321	1	370	\\x651834b29464f9fcfebd08652bc70a7904466e9c68eecd4a060434e7ae19dfe83ccbdd80b2d85f7e0ba82db9cdf917a2c5fdc478cd5ca19d02981f8861fa9400
322	1	320	\\xa7d4ddef3043a0e807264c5952e0bcc2d1c7a73889fe0a0bb6233c34c1e41db6b8a82902e379e9d6d6c01c72d9be7e9190ad0d40a3365276827170ccd12c8903
323	1	314	\\x6870e2a4cba3e94e57bc4dcb3218178b55e52f766ae1fda50f7e6ccfc7ced43d86b8a7d47082b0ceddd91a1c145b2670d6a8a79cbae6615777bc9ef88df95604
324	1	154	\\x76544410b7a95d0b01e857e16959b0fdb3cf0def0bcb7b94c69ca2b2925898baf20e309a9d9125779e2cbae681827c995397895a3f0600b71e1b352e1270be05
325	1	309	\\x8ac9554c816c5098618d91d191c2464506d51e009b0e541c62a85e27bf8762114969c761d0822ee004a6a286cb136573a93b540fffc52ec30e490f065b5f220d
326	1	124	\\x525f69a29bb67d11c5bd23ac3fb011903da7b21dc6bcc38ebe40054967c8c92d817f152c4a7e66c6d01295e64f842df9904f7b6e08dcd96afd3427caf00a670c
327	1	387	\\xedc39f369b80913277889cb8eebf3fc83fb270cf9b8279622febe87369b0f21c51910109eb1f36ae1b5399b734541369e491f85e0a45b56b2e3aa58580f2f60f
328	1	394	\\x8e044e32dce9daee541ecac3ead7f2b445cb16382b44cc5cf301fcc1f06ae8e3425385fa2cc3eb008a12c64c83320fcbaa31e8d266f81eb2df44057c1ace1a09
329	1	55	\\xb4edb9ffdb6f37a4b749be4b0e77852871b0f548aa65894856398703cbd721e4653119e8e8414afef40cebb530e9753d5c1031fdb2751e5046ecb37c13fc6a0f
330	1	233	\\xcccca637f9873ef28d58aef0be852f36e50ac8f22a32671a21b47c3b16be21da3627172ca18bd180bf02540085b11cacfb981d4c375765bf9fb8eab4b012160b
331	1	115	\\x329568c774419ad7829dca09f330303d1cac6854ec4c5c239a7b2f536c7b3fe1dc305c7001f05afcd022dda51e5d2495633a194735e591459c2d36f0b8521107
332	1	93	\\x3f97d495bc8547c08a563c49d05f02f4ebea7806cbf81388038f20ad452a95fe7e6b7221227e556bc278e08cb73c7cec1233ffd4fd3b8d86e6a0be3dcee0ee0f
333	1	40	\\x4c2c23472c6aa13eb8ed3745725dbea33d51ccd9d8d7c58dcc00fde81c1654bbeb510e3dc21c398e6caece3a411b2958b9fdcee82723266ed0cc1b121bd1ba00
334	1	307	\\xf7738a82d60d1bac872cb5b83eb395592f3eca1ff43e72eb82aa94307e9af1f020fea94701060e9721949faf29c8821952fc1719ff999d4cbc994371a6218c08
335	1	248	\\xf38b5d7399ae01671ce96fc8c50158fb0c484a6397695144b4bf81184c09bac11b4f935963827f1b2c7c1e5022d136c36181652c8414b8668c3e3a25999c9202
336	1	386	\\x61c6bfb186ab83e959c66e021e31de5e1dc8252a34b47367b489f876a7734aa752e54540828323b17c9217725d9d13800bc4eca0788df9b21b9a5399a4d3dc08
337	1	196	\\x84b0bc5c0cc3de1f22dbd5cd5bbb8ea40f4227efefd14172af5b971ccd3c6cddc263878491cd86774dc7757fbd20f3e2049646b3966128840ef15f69a7dd1e01
338	1	423	\\x277ab6a0e1402156fd351851ae1f5cc15ce9f7ffd508b0028693f98a755fc13a2be280597c19d990bb305e70638872409c5901702283c79f8c51ebe8c676b005
339	1	26	\\x8f9ec33b67bfbcf4c0e862c60139e946dd82c97e28da9c39926784e92a19413d8f8b6649e4eec624a579fc7f16cfc52330fa03b327f459706cbea53f292f8e08
340	1	7	\\x16ece317d62c8c3f0c148a964dbf43b52941aea2df65e1e74b785838f5a4ae86b476ab00591fdfc68a058b0c823891422a53396ed8df336da27dd66d71d42601
341	1	133	\\x9d1784e51727f27c5f472aa0ff501ba0fc19915ca68cb3703ca39014eaed40605db2964b4966c93f0c9d0a4bd006e5e35148b109a61028a9811287b05f454a01
342	1	118	\\x9951b5d31bceccb671a6d7f89d6b2736a45714c6f3b9df86dd354ffda4450e35a6392dcaba2214eb2386958533d9bbe8e81a9e0be8c29b677c9ba3a0dfc44408
343	1	79	\\xa56601ed7e22671460cce67a3296db6962ecb9af720d21ed3c124f2d0693e7f8cb8482c579a47a459bbb070adce0f4d50bc13a216b37a9af261cf98ed5e84003
344	1	353	\\x0423cb5902c4676832ff3ac897334146e93d63bd2d87a8154a1fc1b26f2d9d8551638dbe9ab5abe67db75111f295dee20382eaa5a3a2a9ab5217661aeb56a30f
345	1	329	\\xbd1409aa312d1c8acb88ffdadc790c34be3ae658293595edb4f7b7e3eca326a108d8b0427e203e5335273713823a4d72e1db638d10050914ea998d82f4a3bd03
346	1	193	\\x6338f6e62186d7c42fb31375824ae80ba92be23331ee6dddab88415796f95f2857d0886374017d5e4777546d8951340020e2d37a0f1004cfd0cc29e5a6022306
347	1	37	\\x6e8c2910226de17dedd90dfc2e5994553c473a272a55873ab93d81b821f1a933ef72e6a88780fa1eb40db2dfc7b61d28ba72bf6841a9d476396c91f105cc9e05
348	1	205	\\xb4069a4086fdffe9dbf05128a69ddfd1f7c463efe09d7dd368eb8ffdcc50e49fad34e994e44d5557d779079bca2e61fbc49141fb775b4e0742864e81758a4f02
349	1	376	\\x59d1622f4e9273ab208666111911c8f48d4e6c582e1ef962e4893c99dc8220bb506aa6215e49361a7b83f65299a1cdec00753fc64bfe8dc4c2dcd153cab55c0b
350	1	293	\\x5b93c96863b40ccb12499616bba4b6556e62a35727e63008a1d3234b17ffce1b52f5b11c7fd765a55b255c1c0fffb5402aeaaee32e874da5782f9ed081b95c0a
351	1	68	\\xde973604ecfb84fbbf6f3fd1e7c3f8536b47ee1991554b6f85089b9ee71298af3c741c326a23f7710264d5abc5de0498572a1cf844b8ba8f203d727556555a0b
352	1	51	\\x1abda9013818b4a2cefeffcc8509cb21b6c4500e06c578b950007cfc084c786d139da2788bddf4337b4a7bde83a1b5ca1ca5d97301f0ddad7f2f2828791a6c0d
353	1	381	\\xd4c1e81d0aeac0de48f28b96a6626181c65e789007923a8ed361524ab293a12b4598187038847397993df318e0340c5bbef03108238ff135b7300406642e7608
354	1	395	\\xec9bad81dc43f80d1b29494e70f90651e4a84bd59ec4d7e86945c1d7a42d4049c67b2f01b721cbc8425ecee2b49c906cdbfa41fe21292926d69492e3a2cab607
355	1	289	\\x5dd219380aac7a92cc0ec6a2754d165abe82fa472e17bd86e287148158a6f62f8f04331fa5330ec5ae7417f3b7021f983bbe0a0f3434ad5f81faf296f4dcae09
356	1	220	\\x0613f3286eff05dbb82758fa7306c2c313b7108e47c7fb4c8593cde9d6019e1dcc8c1de7ae85c4379ea6d7b1d495d6b2d6658acc21e08492e6c18632fcae4b0f
357	1	269	\\xad886ea142745518dfff1ef8d5071591bdb48e04d602ebddf53cccfa58f6816c7a8128af21194050ef688e5b2e07badaeb1bec816059275d1225518eeaa40107
358	1	410	\\x464e3130a1a09a1e8a5cfd02582a459ac8a177b4c2869d7eb4dc43b6fcd970a0a69ee33d5ea63ed12545a32873087a36acfa8ef9d667151cd5b2d95a60a43c00
359	1	58	\\x5cc5f16aba414f570ca1c21cd6320b7b10b5b9e7d157b5b6943fb6075da9b6a1a51565672c00032b48c99f40ede2c52241d228f72b70a30dae2806d8d5e97308
360	1	116	\\x10f55ccfdc55536b3d731377e14388786ccc8b8b5d870fdcb5b5d0eab8830e58d186a389b839062f9e94e16b8c706fc7f1028ddb7361110f7b203350149e390a
361	1	80	\\x286ccad2f18e4779be96535db500bdc48d9b7ef8844cc060860ce97504ed2a6f9649cb36181c575925408860f59b914c8b2487611a8a5b6f879e544d61a79c03
362	1	67	\\x249cb3f670af17379f9ab92062ae7aea1b4a66f5f66863ff793dcea45c53353ad1336e91360f4687a03fef179900f55b9e69c619d599e6dc6acab2b0f2114d03
363	1	254	\\x81917d97c819b1d3533707ebf4a85d45dfa1a5376a8160dd3e57f381b570fe9b1a853a0bd9e94f3ad0c63896bd8a18de6241cb17e7e486bd30c3cf85b0b67200
364	1	89	\\xf584c88065f0a1a0d722fcae5333d65f26e4ed5b6aa14eede93a2926b4b4f0030ccfb22db6c0e86128bd56a0a1b7f5e2d31b100c299b22f653d33f99d6c2470f
365	1	332	\\x12f34dc70049eec51afb69fb8361cfe3e1f02cb80bd2ab931475f7f112d8cc39189f2ac961bcb98b328a506bc91441ffe68949778662de8a0964fa2d35d96a04
366	1	250	\\xe235276d4e3e02126c9529ba57b63194c99bcdd3c6d10b888e19639884d08a47c5573043c8c381815c779329da5a174fdf0567290e9c9851c29878e53ef6a504
367	1	255	\\x20ba76354b341fd03365c4c47d1b2a8482fa12e608e60861a1f5bbf618145a00c3fed16f355b326c0839746fc67b15b82d6a3bf85f3127954be83532e8180405
368	1	121	\\xbc7bc14071314f527ce05963cde8f3ff94760ac95f3239b6642073a9cc20d8441202ed70d66abc1ac017d57bf22c5c1ff9e3d0ea0e7c9be18cc70deb00d2d704
369	1	312	\\xde22f1b3a8952847d900b365bb5887cccf6cc1a20e6fa4e26c5d3a870156bf35322e313ce9d824084fc3d5f84bac43f45e8bdd057203ad8c8b3a556ff464630b
370	1	169	\\xf120990f6c4fa1d1c8214b62bd2fc935d6fcf8042fc4a460b087f495b1442d1869dba12b9fa75416dd7ea8e5a0ad3afac71287995a5a9ede3bf2b3c4ed40ba0f
371	1	213	\\x00d7f0dde7fc6279c5700dc2cd4a1d8f59bfe098701e27b511101c2ad89bdf7fec4ed88b16ee89714dd6803383e90a7705f4c20878422243db2d7c170b5f660c
372	1	104	\\xb207921658e5d08113167fe7b06e97f8cb4b4051ae2075f97fd1fd39dcf860431277ab69e4f958af1e92484156329bc3757925074800adaa1c8c08b643621103
373	1	385	\\x33045f7e570407035c558cb16525d27cfb35aa63c91c898d2ab73bf2916bb5eb863ae19ed4afe89d9adfcbb520857305b8e5ccd6d52dceea9f1e2b25e4884c0c
374	1	420	\\x68a4b30fe4f262df4d413e33c017a273c87be8230ffa3adad3eb34736657c10c5d04601c89ba51ac19d341c54f948608b01a126a107860f0c00b232596f0340c
375	1	303	\\x236eb9b9f8da2a0cbc314b39f786592802747293923851f5eab2d64d48de5a82ad69e6abce1ac8618ba24db7c7be4a96c6477239f39b15bc3b6d0b7fea178209
376	1	351	\\xfc4e1d4422fe7d4a1ca1f4421f18047035651f881fe06e03001a42c5c5f8e45c67d792fa78a72edad885b795fe259186c0ae1729b35f3585427c27549ab37601
377	1	243	\\xa21b29eaa3abf6567386647bf7142223aa5f18d75f06ad03153fa0dff7fbdbab37e56be7246bf70c547709a1f2ee677734a87984bee26728da47a35759f3ba0c
378	1	389	\\x30f016568b16071202c7acff7cab959eb7400211d087233b646420c52c9ee2cb31118f65c99ea956e57dd573ad9300c710845a751e2c44c4149ed9ca224a3707
379	1	346	\\x6e1ce0be378b5f4578bf31abe088d098b7d28cee28d2d42a6ec19f0a83a413a3e2fcf49678463d4c7cd1235f7973e36788161aaf48674882ca342602e5dbe502
380	1	341	\\xeb277f2be4648ba56b43e92a1ca43aaae3686a355b44bbb6a370272d157a995c5f2dc409736845c2cfc649203a4952eb0754e63ab66ab027cab3561de1173700
381	1	239	\\x04b6969b4a56f725c15586b97b9d1d204229d016b25e458004eb4dacd434e2cfb88bb175026848abbebcd90d13dbb223eab107c61f5f448ebe32338bd5b19d03
382	1	282	\\x38494d5416863081280d02f17994f4e0dbdf90e9a90bc6061bedd343a6135f180623ba0088aa2aa3deb53678c6f2c42d574b7d45701010fbb9aae7fd75de3e0d
383	1	299	\\x3aa3f1ea71ff1da1ab6f95534ef0e23029ce14be894b37d7db634eec8089474c7890841272b7fb805c207157c33852feef36cc28c6fea844582d818db026810b
384	1	228	\\x4639d3988dc3e3d9ce75b18be4f0f46f1ad1bdc6ce5e156867a679c3c5a0c2dde8c602f617e16c8c16f8230c70b0bfd9afb4896956fb6d482f84c8c1cc79d20d
385	1	412	\\x7c30b28d69b86b1f5607ef9b079c33d9402c01b0b0e4431bf3a8467bf72dacf6ca23cf4b4aa44734a341d6cbcd76862e3cbd3b9bb509e864c68c109767ff6f07
386	1	145	\\x3bce781504f80e616421fb8cf0b356d214748a3e497b6cb5868e1e978181d49cd07db0bf293d84446f0b872906790f5376cb34353330e88b85b7c9358bbead0a
387	1	15	\\x85771971279e6ae55bbd1c5d781fb7d7fd208b4d1ef87aa3865f843040176dfebf5cfc89f0c681f43610ae43129bfe86f91fe9c4cd2e9727347e0d616308fa06
388	1	88	\\x6ab636d351b8391f3ec3848d6c01f3d02355889fbed32de86ee14233aff97d12edf7653662626ff851e581dd80a32ecf7e87964103f5c9c19c5c5a46df240b0f
389	1	311	\\x59afc162065dd2504cb9a7724498772b23084afde20d6d01403c66b58fcfda5a827af661e5ff0b1a54038c5a6a327a515e08611d07abfbca7c27f044f3453905
390	1	226	\\xac44a9ffdcb5977c6e79b4de4c23c7aff995fd2d2f153280d8238664b5cd0ba4aa318f488f3a08a13b46b81661c7dea8b3b44f59bf234950f3bc60d87f4dcc0f
391	1	336	\\x6e167c7a6ac85e0519d4767414a4c887d4455d5f1177dbeac69606bf7bbb2c431e512d320ec7dcb876c082d7865f7dca59453ffcb26c46523d7e74c7f8919506
392	1	4	\\x251d3392d19dbeabeb4cc08f6049077dd090a4c791eea3295850fd37d9a0b1f8b1e27925141b560e44466b1863dda84881f2fc3952471a2c2f815288925e1003
393	1	170	\\x5af17e90a5c9395c21ac50bd9e9e2308d387e8bcacd541cd6b1bd22dfe8524b4e542a449de1733f924291085dabfa1cd365b3e7eab7163fdbdb1756662d8580d
394	1	190	\\x62479df39ec84e3a00ff8a16c7411578445db300005adb3e9dc880f4fdaf241bc304608ef91bb74a36ae9a5c49ee216f0c641d094d96b3a8267f0945baa72e0e
395	1	406	\\x945c167c3ec6fbe6a8d880dc1260f2d57b90677d1250cdd313ff7a9891571bde660a3a26cf088ab8d45e6900d51a671ceee8ec2fc2866d1ce2f045296e398f0a
396	1	8	\\xf04c40779c78170f8ad2f2e727cd2c6da7341218966bf38882a60bbe305a30eb1af4740f55c03e9a8b03fa7ecd989adb7d856ae236160d68bb35d7d02f260206
397	1	363	\\x12ce5f0c1dddcd3c3a4cd12e2961c0e99bebfaa612ac391ddce04c047393588bc6a35d66ed463d6219c9a4337de4bc038edd78571f82a5ed854d3748ee42f505
398	1	259	\\x25e5f528dbbd93f42afd5eab69e1ae9328233fa8f5ba58a413dc4d6e5c3d5b39ddc9f71a6c7e47ac26b5944240059e0389264fb8af93a7ed6c9b51a3b704a90e
399	1	400	\\xf15fcc9f891dd53ddb44bb9173f35127c91b53197c867672ff3b5aa4fd34395a30350682b8f4856ea420c3e7f4b50a9e7e0d1d6366784baf4cb613e7ac827704
400	1	384	\\x0a3299937f69d109963716bfc1d574e125f03445918d798677ef12f68129aa90306c5093d0e2e67d446ef57d881b46400eb0407215460afb6cb03d81f1d40300
401	1	151	\\xc660d468cf50e09ca44dd8513b47c401fbf5125401a89f0ef3c349f11c95d6c74414ba5f5a8ed3708e9dbbf384556b2e050b2c0aab344d958eec3a0be80df90d
402	1	368	\\x8b6e3f483ba9cd43488910e91c25e159013dff31235fe619397ad1deb13a8b6f1e7f58efe05e4052fcc9a9ad7ced53034b9ba9213f554025669bf71aaa4ab202
403	1	201	\\x6e4a5a018adb8ba4a6d2502f455f71e4fee77bc6371739b7000a340aee968156578a4f4911b97f9a88f906a5bcede3b044642394353ac9e317c4946c9540b30d
404	1	315	\\x668f498746b0ec24c5e33409370fca0c0c033844f1ccc4cf232d25318a5f5c8b91ff778fb3974c6644afcfd111a43ad80642ee5b2572feacc2a297b5a0191208
405	1	24	\\x2b9c9f05379f632427d83fca6567efeb60ac61d0970cf329dd05b012b0b21d7bb5128ed07b5676f53e9f915103d5ea5c3142334b4736fdb7d964bac76c26610a
406	1	60	\\x678958e27c1e6069ddb4f6f178b2df73793a7903fb61e6b47fd76a758577e1b5dec201febde542d4803f794f005163f03cbc9da9594cd39de15b8b0936ce6a08
407	1	171	\\xb2759d3f0c9df9b032cecbbb4ba49d4ecd6b8b7cbb9de818c39e16ccffb86feadc497575246c20fddfdd7607b608ff29ab2914979a7d682916271de752543d05
408	1	102	\\x0001955537e17eddc518d8292169e7d0bc8945eb3783efcd314def87971ac409a0d98ccab4ca33e881c65492a9b0e5b8715bb57e6073a0b556f096b34f52c807
409	1	144	\\x1504656e4b68e298fa02eb0fe0d70ac59285f07606f08ffe36228f6ca7d538059cda71cfd02a0039d3ace85592992ef8e3e18a0d039d7e870efe3e8a9790a806
410	1	424	\\xc86e6abdbffab6e6cbfe997368096a7d038b83eabee29a6a978d0e348917b9abcb84f5c11d02f3ec50d1c798ab3d8c7eea18cfcea2551c367dbe872442ab0603
411	1	90	\\x5e61dcad704950adbb48765a5901d8171acd802286b9c5b9472e80c88ad1376039c3a1eea31838c15bfd7a5ad9384beb19b4df27dee4125dd267ff9191a97502
412	1	411	\\x94e310ae61a0dd707eb5aa43a01bb445e44e8843dfa282932fa9e8b2106a93b85c012475b0883d1765df5261d7c479c9731ce3918fdc6a1b6f1bdb295ada860a
413	1	64	\\x687493161ab743522fa4db5e6aa3027a4d33a80fa11dae122c9ab12a6448a1657304983a503dbce0b7fc2d86d1263dc4d3f73f7c1717696180a5ab45c111ed03
414	1	319	\\xb5fd53a65e1b4fd20edbeb3f192541809f60159d50670b6bb6dc3fd7e29b7832f88d71d2b8ddf608276d5fb72795b0d24eb7c1396af7678cfd7a7ce563e52302
415	1	414	\\xa0903420970e84a7ef67bec53564ded410ef5437d11fe5fe2d00faa8ecf88f0f8d6894750c953e60c7925ae991795e5efd2c3d9b7005fd8509cde1db4c09ac06
416	1	29	\\x6496f6b26fc75665f6571d9a1e3f36a5382276449a40e6112508f427f211d2bf460f47db5804f2eb79653b89cc30ad260b5b61cc6a54170998e7cf2076d0e605
417	1	31	\\xacf14bc22d44fa06eeec4876184c433df74ae9be6381f648412d724f3e40fa7418a8bdb608a2e6e7c20162859b0f0680c7a4c6d1fa9041421e224a46d8abd70e
418	1	87	\\xe9270bfbecc192f3826cd7ab21d79acfb2c841123c20d68ec199bfa9c6363d13537bd23c104dc5e685ba54659f3dff5a60f4007504083e4d74ba12e5f54f2e0f
419	1	225	\\x1447baa88b7188997fe59afdbb74392447ce71c43e03f4301c06ba581ce9b664d8781e0cc67657ebcf35d5680b21b11a00d6f6d5d3fe8fe68ca7d42cb3163e06
420	1	208	\\x9d1e4d9075015012c08cccaa58f41f175e3246134e6cefb6edd4ac9767df60970ad18c7ff4930979e809a958bb69d84cba52c89ac5cd5ccf3ce67ed1d9ba5202
421	1	140	\\xf7e480d34d2e3b0aa1b061bfc152fadd83dbe58775298c976561054566849c4fce70c27597bd158389469bd8816cbfa7e941271de44f98675fb84a9339f6d00a
422	1	50	\\xb2fd26e681f517199f1d86523c02e09798fc061a25796ec0c59667764f6e5c021212449158b6f9a4ba98d6494de97a40e2a531db9df61efa4ab533a3eb972a06
423	1	139	\\xa6b82029f0d722663a326b914cb123199ac2cf68e6738268a87bdf36c5b1e494ffdcdef9a8f0042be6faae2229843749165234bc0782476c6e2b76f68c4af50a
424	1	198	\\x566f1267f3dd8b6062ad4cf6512b2a0af4b77ec5b8c78a60a9e402e5a3f266a972d7a91673015a8c285304ffa830b53227625c4ca7810d6f931abb3683bfca08
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
\\x3edc6ac2a2dc10610ddc284fbcb0e11e201265346792552ca9c8b84bb1d2860b	1650014891000000	1657272491000000	1659691691000000	\\xde292cf6cb4657a9df7d4bd5a23f6308e04499941117b3aaab80b660d2c13f03	\\x431c7712733519f91caad5fdd85c740f9e15ed72186a78653a68779ac796518eada9b7327add52f09533939df30cb54b808fec6d63f2126920006ad37a67d80e
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\x3edc6ac2a2dc10610ddc284fbcb0e11e201265346792552ca9c8b84bb1d2860b	http://localhost:8081/
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
1	\\x6305d3fd7e7e3dd36f382d6794aa735970e10e0ede5f36ab50c3a4b2440d6329	TESTKUDOS Auditor	http://localhost:8083/	t	1650014898000000
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
1	pbkdf2_sha256$260000$kuCEncWgVlGkbWM9HeCb0s$92e8F64sdZCFNP+pWaTfciuyYiZ9GlSgucNIVpCFpgY=	\N	f	Bank				f	t	2022-04-15 11:28:12.476708+02
3	pbkdf2_sha256$260000$DV0Bdw9sO9G9hXESXSdvDI$UYd9WE3o7QFsCTU0Zz8utxa6229YYMN/KLZXDoeI/WA=	\N	f	blog				f	t	2022-04-15 11:28:12.663211+02
4	pbkdf2_sha256$260000$MuJhO20wCnOEmfaIafffpQ$5GL+XLH5T/bYTu+RGneUxckVtrZ3cTVQr8BLGTeO7eM=	\N	f	Tor				f	t	2022-04-15 11:28:12.754891+02
5	pbkdf2_sha256$260000$DWm9eMljRdFgmmFsLjb808$mL9hVwWJmcFKwMd+Nb6C3KVF2Ln7YMluW3ztKQq/y3M=	\N	f	GNUnet				f	t	2022-04-15 11:28:12.845906+02
6	pbkdf2_sha256$260000$7BdolPr5gezqYxhS7VubRd$iViABppj+2jaYb0bm+tJfP5AcGEWlm7a5+wRfj3xw5c=	\N	f	Taler				f	t	2022-04-15 11:28:12.937887+02
7	pbkdf2_sha256$260000$vkQnlYR5ZFWQQvzSwsYtAD$6j+/h6anlrGI9tUBB2UXDDxEZ1PgyCguy2xVvzcIgR0=	\N	f	FSF				f	t	2022-04-15 11:28:13.029981+02
8	pbkdf2_sha256$260000$8ERUOXhnUBAmeZQB8mdKyW$IhbIYdzxiX3l4oHL5QCUpQWXDth3u+pIk7i5uRHKhSc=	\N	f	Tutorial				f	t	2022-04-15 11:28:13.121212+02
9	pbkdf2_sha256$260000$0d9pEkdPR0PmuPSoiZfdfk$inn+/SwQBCm9dWtKxb6nzVDxjGYkkjNw7c2SDdgB3M4=	\N	f	Survey				f	t	2022-04-15 11:28:13.214659+02
10	pbkdf2_sha256$260000$tSKUgy6dYras5loquZBitL$B9dQCNI6CBJax020t0AO3DkAJhr+DTF8A4IwK74th30=	\N	f	42				f	t	2022-04-15 11:28:13.668154+02
11	pbkdf2_sha256$260000$Dj96MOl6MjH8uC1c1lJ1Mj$pNB9gPJlGcDAPxewtbSZJ9Kaie0rKvCRMh9edzRxzxw=	\N	f	43				f	t	2022-04-15 11:28:14.121187+02
2	pbkdf2_sha256$260000$egpfC9mW09EEe66aLVnBjL$VcCBBUFxP+iM52CyLT9S6HqlEuada8G4x6cmUuo62eM=	\N	f	Exchange				f	t	2022-04-15 11:28:12.570851+02
12	pbkdf2_sha256$260000$fAZVpw23ch4W9VIwSA5YUK$/ou74112N5cOvsojEkDCecH3iFMXA1Y2kGekUDOa76k=	\N	f	testuser-yygbrwqa				f	t	2022-04-15 11:28:21.431526+02
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
1	208	\\xf223b4c5a8f6b44375c155e855445659a2b38fc3e2a39696e07b901fd6d56fbf87d8e80ff2b7abef41aa6afa34ce89a1abd9cc5fa148e9dafb3a7d6612cff409
2	64	\\x3b1900209b7ca792ae86790d66d91c905c669323537cd4a579b6429b898f13210b349bd500cd038bf4ccf06f5b7017a9bd8e5bdd1431524125b7fd5b4188100f
\.


--
-- Data for Name: denominations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.denominations (denominations_serial, denom_pub_hash, denom_type, age_mask, denom_pub, master_sig, valid_from, expire_withdraw, expire_deposit, expire_legal, coin_val, coin_frac, fee_withdraw_val, fee_withdraw_frac, fee_deposit_val, fee_deposit_frac, fee_refresh_val, fee_refresh_frac, fee_refund_val, fee_refund_frac) FROM stdin;
1	\\x0170f398c3c2a01a58853c4fa2d469c71c2d9bbcf04d2cc4675b2241646e54887ad124928d09d5c8bc7ddb912ee2462640d685ef0ea9f2ccee5863c482aa93cd	1	0	\\x000000010000000000800003c64cb768b846de8edfc9d085ea3f07e74ca0224e9ca1f3c339b8de503a20ddb388e2ed0578e91a84a22df131ef556931e1a865fcfb237bcfdc5f3bfbc580d57ff074b5e6100f2fab31d96ca98e7eaf1a2be6c5dea9c464f9da786e14772e1e581f3281395d17a74f15b93aec68d8d7bc20e3083bf93c590069e4cda349248af5010001	\\xae917b79350d1bf839b83e414ae5f8ec5d8552498514a0b078a49f421f2d799ca6ec5a774474021f395990c41c5c3de13f29c70fbec240ca004e81fdd8c88a04	1665731891000000	1666336691000000	1729408691000000	1824016691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
2	\\x02cc0adf6262cb9335d4b626502f5315e1f48fd7a15b9b333790a7e18d0b77300ed8edbddd3166c0bae6b52070b992c7dae3fe77038cb48f21d3977d72fb614f	1	0	\\x000000010000000000800003b7583ba296c2358c210138caa8074cad3820de74a5771d731a6db9a55c108d977b65945c6ba360439b168c4532b1345ed305289f2170971d48deaa0d048aa762610b66aa09e34373e8c427aa8feabd6c3666123f1a32c30812f21bfc16b50073dad6cad637fc88bbdb049bfc86b6aabae28ab13b1be36e84bea167bbca967dbf010001	\\x6dd46bbcb7712d47fb17122cd20fe051ad42fd45f425a67f446d959676da840430fd25b1064e1d2ccbefeeca1f27da5f6787a611c14380ffc0bd40411fb93e00	1668149891000000	1668754691000000	1731826691000000	1826434691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
3	\\x0b3834eba50be20ba64599323c5ea7b187509b1b28bde255ea36f20d6046312c961e3ad625d0de4c57590539718c7db76bddd45dabeff3e063a70779d9da879a	1	0	\\x000000010000000000800003bedffa4b2e11ffa4cba6c3c351bc7ed2237d8443f454a8d64184120b314bf3164d1677c78263ceabb63d5ca9e8275c8b6a3261ddfb412bdb1bbf69f8f51af3fb6ed8c4b6d71696722127b657ac06a30434feaaf90f63b1240fe809bf69fcfce47a7673693ee21d29a50b26a8adf9f25e0c01c6702516ea918c6a312d6b826fc5010001	\\x809265c68be97fca449c0366267113fc4a9ab58da2aa53c4b4e834176370c3d61bc549f93762459c501e55861b2080c72d7bc02f3851f5855bcc41873953a80e	1662709391000000	1663314191000000	1726386191000000	1820994191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
4	\\x0d38cab5fa9fea8b99c4339449b1167c86878af81225f033123aa30c99f0cd322ab7beedbfc9e34b434fadc8c86f635163dd369cdec067cc6077b41e17daef97	1	0	\\x000000010000000000800003b51e1c81c3d237f143233b0e81e3857c82b944b793c4b9d4d0b23e8179be66f6ffaefa63cd7715d14deae573e13e20ffb8df96bbe3a9f4db4ad6b257dda05557750033509480a4677976707b41b50ca03f72cf9b18453f4cbeec14524eb4c9fad83de79b80cd810a85212cd07aea9c13810db961307f43126c4ee44d3103f403010001	\\x71bbee9200f1e651151e56f6dcb8c3b19e6c3f1da98a5da0def3292d9c571ea8da155e42410a92150bdfc1d7c6a716d1ba649580c87b1be0fa075761a4efe70f	1652432891000000	1653037691000000	1716109691000000	1810717691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
5	\\x1174701fb76b9a31fd50f757759c6391afa944f4984e517ba43ad279ac2307a391177ba051ac40e3fa0e2b8dd2d724b19014ef2ab94c322e4b54c402f18527f3	1	0	\\x000000010000000000800003a57593c638bb1fd352276bc96af149011011be53642c3c5398b61b71f4c356ad6c21084431bbf3f99d1e7a91772bc9df849d3a06f36ddbf5f17026a0d8e3b32b0d882b3c6b8cd77d1089450c996268278f5771443d8ab287cfda2cae0b9fe440438adae2cc398a899983487d6003ab4795747cb79db14fb9d2408fb8e697bef5010001	\\xd9e4e9f9e600ad51549fca50969196bb56f9614af8c27b4a75ea18ee4ea0cac36ae6196711f47f45874dbc428ad8edebb0156debeb3ba0c0f7b1469fa7d91e0e	1672381391000000	1672986191000000	1736058191000000	1830666191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
6	\\x121090c57ed5e282840456bfe32c25c33620dffd10310af9a1ee7be13c27521f2a5d51df33d3823bb1e0d41be5dc12b32a3c0623a11b10dbe124287256ec76da	1	0	\\x000000010000000000800003e53e5603eb9315a64bc201790c0ab431dee4a22a42ff3149f4ed9f0d799e1979c67d6d23163e13e6e30cef9a3dec5cd10a6111d42bba950440fd936d89f72f567c28a69c7be0bcf24160b2672e75469fad7673f997c6b8a7d70f9dda788a1d091b3395e6f8c22cee1e5ddd83d5c213f066d230bdda4089dca31411946f3fd97f010001	\\x18e00fb5b7e2a4f139a3182fe4c49ca5a96135de8e4229c1d7673f599a23eb94232d249b963dabfce2054ee8b7c901e2bc34e41383ef181b110aadfc92218e07	1659082391000000	1659687191000000	1722759191000000	1817367191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
7	\\x13fcc66961447dcc5fce75109bf4458970a84c6c4c74be9e6ce763745215c4bb25be2ce0d8f6feca85b4e7768e20577ac698c35d116b6a2fc3306ff398084efa	1	0	\\x000000010000000000800003cb717663b354c66e08376eb9072185f4b571fc9040ddaa7a697f2dc2721a9b546100ecdbf9707a06c618b07d04aa69052bf41640f671165dd79fedd448429e9149a3d7f1d5ae9186766b6f618ac14b76efec553f224552b0600fe3af221810948bc25c4899fe4e06481c14ec52a72cc516e3e28009d440b46f0ef47069fa65d3010001	\\x21a36b7ae73763a172adf4520a18e55102ba119309c73ac3e70726c9f87f63fc763993f89f958f13facb6cb5f9b03a8c76bfc1f775d91fab744161c0ec198504	1656059891000000	1656664691000000	1719736691000000	1814344691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
8	\\x156894d5843b6002a7db8075512d47544fdc80ed5adc7966ea521294b7f80807ce8f383935424f3d05937e27c4fecdb83ea836f56b08afe252e1ea9b12254218	1	0	\\x000000010000000000800003af0fb6d3da7471bad64f1951bd3b1ff656ffd8b2ab1d25af45cd740b3570779b6240d7d20c0c76182bcf817e5344ec92077a74d08d096618bc37900c80508047f24a3d81308ba504f5bc8ad4fafe30334401230e79a5107f3a2ab2142ca614317e928c6e7e30fe6823721329c3dd22a5c0491e6c9338c2b426b4d99a1d0b94c7010001	\\xe0149649caefdbd3e6174d6bd08dcf4649407b4165d97c0acaa14d544337ced294086e24abe15031e61c57488965f383708a6d3d328caf630d1c0cdc93c54202	1651828391000000	1652433191000000	1715505191000000	1810113191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
9	\\x19dcdd23de38435b44c604d5493041c3d8e4d161626b5a6cc3a2c4c77d6848cbbdc9a31d174a233db9187a6a704a47f7ac67cb92cb48c82321e80bc6292e266d	1	0	\\x000000010000000000800003b49d3d8441877324eed4ad0dee2d7d51e792c7f4779068f424d12d409f45fbd2a663a89b46fe954e60809e0a1c8c92ce5c760500ea4dcc82411d3a1e1cccf678005ff5330e534daea74a70e6eaf94e4897295a43a3fd3abd9cc2d291ce809a72b5c8ce4be254914f077bb7d0cf2cee3839e4019ee08e68dd38a8e06060df34c3010001	\\xd2fc70e56cf2959127ecdf5d4e3df1ef1475abdb054fa2ab7d0f02829410d9a656736c03e80f8ab257d216baccf9c1c7cc6fe52e952e12339eec1a2c94edad0e	1672381391000000	1672986191000000	1736058191000000	1830666191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
10	\\x1ac8d83a69e426336ec548297455fa67f5f11802fed34c91f852c6355ba2198a7356783fef1fe0665a6b9a92be13e71b9a7224121e874ce13ca17df8e675ccbf	1	0	\\x000000010000000000800003e28bc53a2934a4664929b4eee023e47a220fc0b17340ffe2e09ab7baf65391bb41fcd912823558b8f313145693dadbc59b5375e77b014422724fb5482a7bb1a1b947acd49cba2863fd73df1a8ab7864c9cc876027529ff6f4481b2e51f6a7fdd2afe93b940d79f240634aaeb6de896a6873bce89f76814f62a04f6a9a35c445d010001	\\xd1734a9af791e6a380a7161f135fbd2d5434f1d53a1c16a3d1c88921ed98878c196482864481d879d38bed8b5ec873cc5f94ada114250bf6da0e9ace99f4d406	1675403891000000	1676008691000000	1739080691000000	1833688691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
11	\\x1d7cc72749f71ab72279ddacb0eb2228c5e7d73c7a440546648c88bc03f99bbea3140dcf10f7f81b3e5863e421973e9902a1955d7b4d14e85d55ebd2f4f11da8	1	0	\\x000000010000000000800003ce337f7903e20a55cb031edb5b4d1bdf38c56ae0c0b7972594c2ad2a46c7445605e4dc851b911cb88ec2555a96bb0eefcd7897182f7ca2d4cc4d416ee29152c6b292c45eebc051e1425bfd615cba1975a016649cc5487949a1bd13f6059cd94f7d58c81c7fb5be8e180df3435e6d5e48c21e243d9f500ec236cc6796d04d2fd5010001	\\x4a32d5ee2cc992cfa87dbbcaf5a0712309f77e7711953fbda934fab9c2c830b1e1778da36617cda9ccb970238cdcbd9ec22b49ad93d7e63ebcbe32837b94ce0a	1680239891000000	1680844691000000	1743916691000000	1838524691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
12	\\x28d0251a604b28f2a38e903809867d5330ee93f66a3c647d8f8b448747284e0e3e755be128f843329f49225dc6fafc8f14770e28b88a50e389023087bd251cbf	1	0	\\x000000010000000000800003e4703d1d02ecad79e6f39653722aae23acb106847182c0aa84977c363b0d13b30c5c6e7fd718060eba1ce443072c798b6c85f3fe41399b102d29a58b871daec39dbbc66f8cbdc3dca57a57e31159055fc992f044864b879af4bce37ed6534be8278f01e516c2ce6a83d692d4f5e54d772bb5f01c08ca47eff6f8ef48f996256b010001	\\xed32a7eb8c3d9c46952b67fb7b0cfa096b9206a6ef07ee4d663a909428b812e732ea89bb8e63ef23a2b859dcb1a1230aca82f1ded6a14226168714f4e60cb00d	1669358891000000	1669963691000000	1733035691000000	1827643691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
13	\\x2d405dd8cc4674164ff544bf071c71e825a7b76c37aea35ed450c5ec9002b3505feaf209616629ce766f792a9367feae6ea07fa6110e7e363e5c0f50cd876761	1	0	\\x000000010000000000800003de960f3a28439f83df40079c8d0cdae1057348705fe47667a5463a72c88f1e95fb1146332509af5c95c0ba82717e77fb9f479a0ab16401f3ffe3cf1bad73928998ade3a388fdc67cff174280876bca65055646737610fa18bdfe7d5e1d271fc415752ffeb5416def9ff15e60b915e87e9d654ba31c3b8789b7f79b94d851be17010001	\\xdfead6fcbd8e0272a635420feade8d5699b49a2ef51e2b7a62aa7229df3039cb324fb74c6ba23ee2f7ca527d05ee88ea69d2d95eb24f19eae973a5c7d5b1bb05	1672381391000000	1672986191000000	1736058191000000	1830666191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
14	\\x2dacb1386d2fa7ab7ccb42065b91a86a0f30cab2a584e9549c1e6702f4515efbfb66a5eae2dcf1616903a1b659b56998ba9e116a13c579dc328d9437faaf36f3	1	0	\\x0000000100000000008000039b4a28677406d170dc8d1f4ddfe2d442552ec3520d00c2b18ef18072346bb4f532d897aebfc69607bcd6c6d6e58ce4d77a70b6dea9747e5b35aad2725fe9f3cfa75218bfad6ebcba40b841c22ffa28ff4ccb93079435b6bcf9c5e0f44e5ff1023dbd5c2eb276e2e41ac512164ac070f8aa6008a5ec5e243c780b135df26751a7010001	\\xf4e9982ed5a5d147cb300e4a98c2df940508e96ed6ab249912f275a13b55540faac280a312d125b999d8af5efb57347ae20c396f4afc35d064255c822daabc0b	1672381391000000	1672986191000000	1736058191000000	1830666191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
15	\\x2fe464a4d1468f708649eb100d79ead389f761b44ba53fe1dd901f0116b92d6604d28d21c51a1da0354724f1bc8daba8f0d2f11d7f33c8f996212d5140a76b3b	1	0	\\x0000000100000000008000039fcff18374706695a838a041725a741b6aea3f1bfe4050d99c41e0653c103b346face90b6750a5d8044f7e2f11dd2cda4dcdc8319934daaee01df2a4b7c18e9afe3ec26ef61106ee1ccefc77f0f8c4d27c49427b3145cf652e1e5f33b98475bad7d43b8155fe3f180ed87d23120138d2f627adeec3f74394128bea4968b81027010001	\\xc790d89c3f8b0e95e9b59d18f4ca19ea3aaf2b260a210262b059230e198e031c3b2cb28d7f370da490379241cb47974353237cc6c46f5762be4aa8f11ae2b203	1652432891000000	1653037691000000	1716109691000000	1810717691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
16	\\x31d471a84b6131b63cd939f46fb8827d795449b74a0e4fc2459dd23bfbddf0cfcd613807cce0ec145930d41248ce066934b541a44e16fc5e1ba04da0266ee4c8	1	0	\\x000000010000000000800003a95a439a1e6a824942ed6e9093cb2b683ab73a400be4b8c01cc12bf1558eb4e813d8ac2cb747f531572f313f7eb3bb82f420bed2b9fc194e8e49a5d9605dceb8283cd5a222b28fb9c642ce3238a13d2bc24806cd3462caa58dec825f624b6d28e664eaeb0bb8ae8ea3ac8cd69b44ddb28d7e8823ba57fba6467c9b6ac2215df1010001	\\x210e6ee57f396342c9c7cbe57b908b55bf101fd9bb51746ba8ac97e9a5713e8543a9558f1f3d88315820518fdab448e7e1ba63116875edc4cb46eaa049bfa008	1660291391000000	1660896191000000	1723968191000000	1818576191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
17	\\x314450ec185efd07090f7669c633c96f98bf62b9238c278079e1e8327202bc4e9eb023ce7cb06299d19ba2d41bd8c7daeeed87aac68cb6d07dafb3b380741c9d	1	0	\\x000000010000000000800003b3a384198cdceaa6d115503a8efd583c7bcaf21d75ecd286a4d6f7d6aecc3dbf584fc2398c6871706c7c9cdc710f069df6b6ffea7f11f0d7bebfeafb6716d6000eb2eb4333fe615826c9eecda63fc7ca8312b20729ddbfadabe2182acd40f314e7c864cdc1dd8f2d5e91cd2e9b5f1ef1461f87cfdcabe77be3326d6f58726ca3010001	\\x1eb9de759ee2ad66f68f379f18a1c0a76bbad6ac34278ba3c0905886e0f3efc37d8cdd52bbd574e7eb06feb38fd8c8a9884e56e3571ba5981fbeb387b5a4360c	1673590391000000	1674195191000000	1737267191000000	1831875191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
18	\\x317025de40e2f43ae8919b12e7d4858090dac87ecdc287c4b78f93dddf024b8b1e16bd993dcbfbf54cf15d34f81e577fd13c3fe9a0e01ed10d0df057e97a9653	1	0	\\x000000010000000000800003de69915549976aeeb4c86338e20c92a268ffce4416f48501c0ca9c01355dcba92a59a0587f6d1a1ab61715a7d6a8f153ecf551b1658f8e12941c207c55bfe5dad82124593edc8724b87a9e4ab63cad91aae010924532c7f0cadb8e08ae1da8050c8d956a31c80595e060472ac916f8369b92541a2e4f612024387be4c3cad5f9010001	\\x5ab88917a326464c5d35f076292c36bd21306ff0930635dc0f40e361be6732b2af57dc31901f0a72212520135f5e53fc308c0bc568ae37fbaff37687c070d400	1676612891000000	1677217691000000	1740289691000000	1834897691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
19	\\x39fc9370d5b28844c8df313fb0eeb5484d6ebf15d767780f5444f4c57ec34b36c4297d11958ce3456c3e56f687b42b8379e5f90c96ee2accf87d30750f6f71b0	1	0	\\x000000010000000000800003ad56be3fe0f4f606a961b6b43f7f1d1e67e79de2dfd343e1648c95b0384a845ef1242e0a117ce892662d0573730e657c698630d8279a909fdce625d2772b4fabdf93e2d5a29653ec9e41a8273baa8f7446182fac5b280439c9df4c04de33469f2aec19f39ecdf2044499d5e4ae564d0356f682425f3a820ba80aeaffe4051879010001	\\x068c70009fd59a597abd24af4afa7f23ea5b5b226234de9d621e2902e5cdd2bdfee6e463dd3c8c12bed0f65268b2683f87b265c23cdbe12dca64218f9ed63808	1668754391000000	1669359191000000	1732431191000000	1827039191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
20	\\x3bcc6bf356d88d30d5bedeb32b571478104f60fee72181072bd3f1e4d6d6e00e3ec3ef0246689407e41cae9e6ca802be17f0bb7e908f0946c96573eca1375d8f	1	0	\\x000000010000000000800003bb7fa18d3bdd49ecb3d14626d3f1835f77d421ddad35ef156e03dd9b7aebe740c00b68b651899730c3c724af39d5448dd24d65aec3d444ffe472be056ebce923287a2bc86182a37ad8cc3c84269901cb6905799cc4b8e5fa47f917a16a7e1e863e7125a748a4a9a32916672a657c7bba9f7ffa836a545a170c654be44c9f1c75010001	\\xd7598f2a42c94f5ed15fde14d53f3c21f7f7b2b860c470d136f22e6f58afdafdde503d2607bc01356487e3e2040b67b911f71f8df91feda109d29f82bedb6d0b	1665127391000000	1665732191000000	1728804191000000	1823412191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
21	\\x3b641d66c2b35d7809e828270784661c84fbc530f3e0c39ebe9cab7444c03e234849422f20d61af648d1665500cc1675359c63d36b95f8ee0c2d9ee746b52563	1	0	\\x0000000100000000008000039ec0069b3acf9d739429ed402d7a1bc727220b86613bb32f1cff2d21509d9359b72dcdfa2a1718c219fd7c2c75ba681eeb633f2105e57248529b4e1566baabaaa7d9f24969ff0191238fb94b4319001633e5939de9f15524ee5ed0bb1767a478cb6e40da7dad28dfc21c33a9c9cf25318da6bc1d84b9f9e37005f08861674a9b010001	\\x1aaf0f257ec66249716a14d38f0372eca62c3306b9da30135c8ed9d060dd9db9bb07520ed49452e14ce3b96cff5b75ff5f4f9b069a7bd22a54f5e7757a74f200	1674799391000000	1675404191000000	1738476191000000	1833084191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
22	\\x3c30b3cefa4eecc56f5729f9f47b7e83e4c67187aedd87af8ab3ec33c3d714b3bba80113e404b6ae2d948fe261c0be199c22639589e0f7a25f29aff36ba0ffcc	1	0	\\x000000010000000000800003c2271cb97eb264548de71b5c2b07754f3423e10a2750019c23dc300a71a0959ee3b251b989fbb5cdd67a1d71e9a4aa6fcb219efdb72957e5b957203a8d523d4a107d3b3aaf025ac1554afcd890704c51562e11f395d125d6cf85b61482fc61fc57b9d45827db41a483c43b84ad8fcd4c20ac4a1e49079cdd0110ca084e49d821010001	\\xb3d32d2baaab6d0af4d0ee40d33d808b2630c2a4eb0b599dfbb7fa9a90eb747c55275d36338feebdda28781b7a3bd25a7bb21c2985b0e6ee2bda3e3cc7cff209	1669358891000000	1669963691000000	1733035691000000	1827643691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
23	\\x407433202194c0c02f17557d8e214a610465f1f096f5f30fe62486d9c11e3559d72c1dd83776a232ef414bdcc1fc2775e751decd87e23447f20c048d52e9142e	1	0	\\x000000010000000000800003c2f0e56eaf7d3c7248b262585b40957d0debadc2fd0b386c944548a820ae80e7214314e4176ae24c27828ac828a9cb9a84755cbe333968ef23adb5d815d73529a64dd01a1330cc4c5e27ef4b6676cfee1b795bbdb40759c2aa35c622c127cfebe676c1ccbe0148f905c1a084f183f958348f280d6f884ca26090b70d25fc8e65010001	\\x2854296940be2d59044164b602b1078d465bbfffde7c43053417f01c3c222e85ad156730ec583486aaf37d1d2a4447cc435ad31b2c51064f02b6767f082df30e	1680239891000000	1680844691000000	1743916691000000	1838524691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
24	\\x4204f9763f37821a07f4f4ebd7b6d9c9942f2557a942f468dcab6784cea951ab736e1cf682e0dc3bcd95c4eb4fc35f5906a45dff512b6502bb15918e40046e3d	1	0	\\x000000010000000000800003b1ead859d40d2e94c1e0b7e7114b1107c7c2360a95ee90479c04c1a6e8086e47a8de52d233c7eda26a7e1779d981d8fcbf26b7c04ece4be25880295d49eb31b73d7356c9472ad81f9eeae5751ba21238c7c5239be9a17deade567a5e5c605d8124fc2da97c5debf8c3df0cec02ae3a0180609fd73c9f9dfe4a39b9a8f9802aed010001	\\x0422ec6fc1dc7df8ae5c20bc9b95928d7750dc8ad468f06eee9f90f5315435edb61b6e5b10f0be2bce1b86332bce191b7d1073ac0d0eaa3e3f31b905ca4f1d08	1651223891000000	1651828691000000	1714900691000000	1809508691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
25	\\x4630ecd9e0334e24b3bbac66e20b887a7d6b78d258b62b9ff3c60319dd9c3868abba4955d7375318c7eba48706c9eb265aef3229173477badc740a0d5ecd0e61	1	0	\\x000000010000000000800003a28d8eca7aeaa1cfc5f0db88053ea30c9806f851169edf1d6edd079feea19e1cb4c5466edc86e5dd857afe5bc94755cec649784c7aaeb4419569031404d4e67fa494cdcdbf2deabdd219c4890718cbbc836ddac0513bf0d88c7b4a9eb9c3ee83bb7086e3628d8351cc7a3ae369a21a0e730d204d197af9fae0b7829e4a7e2e65010001	\\x81661da846f87694f886f99ea95d873fb0523d8823d13748e61cfd1c5be9f176fcf9fd75c0ce6f387b3d12cc0846d92e52bb11df3422292a4a9075f90954820d	1663918391000000	1664523191000000	1727595191000000	1822203191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
26	\\x4644d7505f3b61734844333143389e6d5a4ea72e9a3749630ec5d35a96921d3400728f733a65484f32fbe6a7b80d0c15fbd11b127bbf476098a20c3ad4e88f3b	1	0	\\x000000010000000000800003c193bf07300b6b2d6226451f87eec414717a41913a5be21a730acd083e30df4ecd06ba729af16160d745ec33d80198eaf7a769fdd8247a5857ae19349e9f183caaf8cfae47d726f47922331a1d8b7c12fcf29249c4946eb0f88a8c3949cd9a4cb4ac27f8f2ee28d1e47da9fd632f700e00ede9e6b056fd0fc5be7b3db5b0678f010001	\\x88985f071b03c72bfc94bd01691c28ae2c63a0f74a1196b8b857c60c049b6264a0aa622741fba8477458042e2c8e9fd385cffcc372fff7a95dc67e8eaffb5e09	1656059891000000	1656664691000000	1719736691000000	1814344691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
27	\\x46c0103d206002f35c3b7faa8a451bbf7b0e889bf56ee6bb299a74ef43907e83a9a3d51c3fcefc70184e2fbfc0c4b169ba65e5e18461db8613da2fe3a11784ab	1	0	\\x000000010000000000800003d2bdc55b0df9e255212042d80bfce567e823425faf027d25723a3c5d09c4535deb2f43349df02d46b9601df2a0965d64c710ea38acf5d3cd7fd0905da687f323b572b27d23d1e540c8c72c70b0647d1161a6bb29680f0ab79e93ab562b44fc771778035a33f7e3a0ab70f18f376620c1e2fb2af1d0fe9c72ba26326a4f5d8099010001	\\xb6beaca3e69bb7bdf07adfe522b641f2b80669f51fe52fb036fb454e0a177c3ae8661c53de1c39b0533d3a7133c4d8d36ec1dce8de3091345802eb70674cf308	1674194891000000	1674799691000000	1737871691000000	1832479691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
28	\\x4b3cd91bcabb1b6a6a1db9d0df7e3720310dbd81a9add16456daeff86aadf633b895a3a9cf3aaa90aa5345f339a115842d1bd76f5462bb5ba7ccdf8530e8cf5f	1	0	\\x000000010000000000800003ba549d11956a24b6a5b7fd03ce4ec50807c1ed950afa9fcaa3560ea664dbba7323464f67a34b014906563d95b0c6e4c23332749eaa64edf296675ff72be10477286303957e1fb16bebb5b7e1b94ae4b81219d9172361cf85fbda5667790cafb2cb450fd3de01532ca131e71ad993742fa65b8c5a6e132027b4ac877714d4f0e7010001	\\xff7f2f7edf77f0344a0c8faf1802fcfbf9cbbe49fef48973528112c027b5348287c7a373587fcc94a241680bf2202f07458da056316e647ef93cbbee9d5f0c0f	1671776891000000	1672381691000000	1735453691000000	1830061691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
29	\\x4c70b1fd1b6a956fc18bb3a2807b1f120ef16bff51a58056c2592a4397b3ad7e421234c5ad1f79b953db3dff939c3728bd220e226b0d9b5957097f70f4cfc9aa	1	0	\\x000000010000000000800003b171ea8870b651735073e45a60c0c98fc4d03ea37547eb70ed44211e1b2e4619e24c89e82f0cec8f4c30dadf0f552365aa04d33120ebd572724ce0df94d5cfc6b5c03167f4155e5f1e8675e5d7bf6ca75482821e8816b1e8e7239509704aa6c13566d178194f5cb804f58ae54afe147a8e15d55677c981ebcfc1be3dcc8b800f010001	\\x38982a5418536bfb1b76fd93f8f556d93c12788f6a1b151600d85eb60bd571b1fd9357575ae555836fa4abe3126d14c7d2fb7eccf931748f0a1ef8c247827206	1650619391000000	1651224191000000	1714296191000000	1808904191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
30	\\x4e943fc4f41c56d20330ff8f980e412b7fdb402ebe8ac1c2204e8ef7fe0db73db3f4f61a69f676d596972121c16bcb35e5093032c031a5d9d1130d3900312cdf	1	0	\\x000000010000000000800003c77d327d28c689bec6af8229163004cc7954ff1cc4bc6b8b546bd447371199918b59555207c7076cd0d4a8c6826ac0181d74e2b4ac16dff5018938d57a192477a15c7287b463099b21b9d9bd23b006eb3f4e822c79d006b46801fc29b0d2203a31feb7005683b30f9f09e81aa82eef51330391d6346188c3a90138738a06f20f010001	\\xddff20afc7b90191786b3f950f9f4876657359818da17b03a55dca49b439238bf13b43517785767b74e48d108c7b82e654a5b1fba50c8b005fb65787387cc004	1674799391000000	1675404191000000	1738476191000000	1833084191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
31	\\x4fc041bfe8fcbdc2a5324e46804e90d80027814d96a18946b5e5e87ae749912dad3fc76d0ab170e30d2bc6cf7cff1d04403e94b70616203460f839b5668b8dda	1	0	\\x000000010000000000800003db0b16e0c1b948419447e2033315110115d576d0f9c0eaa9f5f0d3484f8b35ecc2c10087721d2686c8e7dbfbd7bd12afe003e49dcdeb998ea21f8d7753b2a74ec172ceeca45d71761a7b87463f0b1a3609478ffdaefdcf62d8bee4fd7f7904d20e57838d8d51884c0b30db587818af8ec40c71638fb4bfe798745f796a05a805010001	\\x0c3d8c91727af74d21083b35a9895ec4fdc383bc78bb8d583071fcabc23f5dda44c91ed83ea11949afe04ceb43e214baa41dbcd7329af81612a0211bac05bd0d	1650014891000000	1650619691000000	1713691691000000	1808299691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
32	\\x50b4add1fb4b3d6fb24b66763c650447d6ebc302e644c9971841add20bbee1ac34af1ca36f819e91c373bd6b1107503ef9a96de835d0063de4dd4b9cb435a5f4	1	0	\\x000000010000000000800003bf409e1c4e1b257ca94c560f4ba0f4e4046b6f57e124839aa0efd353add6923b1e06e7a7223745784c5c1365002c5f9e96b33a05777b086b426382eb61344b7df2b229b582a54318eb3da9e10a5747d3c3b633ba145acb2f35b503621af571dcb5006bd2db430a068ce89d5cf897640eac8cb2b097cfae676f90be80d655fd43010001	\\xe570ddaef95c1910515fe2d044d83350079ea2445e030f585f67bc5482878d07b492e9b22cecfc66377139f54801107d0d5a137786b42ee99bcaaa7f4c0a9108	1659082391000000	1659687191000000	1722759191000000	1817367191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
33	\\x55b445e7a9070d61cf513fda84b7f846ea6610b19ee5d8572584a49f62e443b66129ae96d5cc65d02fc6d9cb4f4a593aa564f51fa164f25790d770eb6efaa0b2	1	0	\\x000000010000000000800003e16c36ffbabb315d38c246d39282bf415f5962ae877ad9722f54f5c3df08debd127f0a18cdd9718ad0c1a991a3ada732422cf9cde6d22ab603a97c033939cbf85f9755dff5d57727fc032dc4c0ab16fecb372bf9b204703fe831baddb5418b895c89808ed2066df9a22d1491755125e8bdb6419f47e2e418b8f7a08d2426dfd9010001	\\x99fe1e362643298930f92004478006aa209685a7b67b4927a0d18368c04fa1b23202656e43d2fe26116f0ed575b76961b9ed62cd5323cf026b12e72ef677b10c	1675403891000000	1676008691000000	1739080691000000	1833688691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
34	\\x5558013f61176dbfd38c18b1056796ee0112adf25ec11081423265c2382efd19a2aa386ec3453cc75169f71a0da366ae7eeb732379cb7d015f8e388e2376c62c	1	0	\\x000000010000000000800003b076ea533dd49b8f8e96eb3991d9795a9f37878fab88af8ddd5822d327e529b8b9aeeb95a7245ab6f4a306209bcdf0ed4ceee5f6e4e72686579a98a71e0f4960044b322f5bdc0eb9bae972fcbbd8fb8c642df58c8f2c03b4549d4c5601e97c1436b15ebbc523765838877abc6ac17aa5b36e70789b72d70df4364139cee2fa85010001	\\x8f270c5b814bb95528d9b47c8a9bb81c4ef71ff273632aceb0bee26e0dea15200947fb9aef8274d447207ca84abc7baf7d49ce1035cc7413e64db7836ec5ff04	1666336391000000	1666941191000000	1730013191000000	1824621191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
35	\\x58082cafcca5a96123abb3d8556ac93eb5869e6d8946341195bbb6ca159e63039e574e0a05b2a74e3cb9c5a312bb36b2c3a9524c522bb65ba79425395de41b00	1	0	\\x000000010000000000800003e8cb8811d5b7eaf6bd7421a4f7c1642427088f6a90660598c8cde17bc8529e00178fef525612fb1e5876f9fb2e87860bcab3794a18575654d64a294582903ff392788caeb4c70aeed3758c6ee2ef42318767c4c0e555ef17a235091bb6c07e34785abc4e32af88ffeca749054f649bd6bf1fa766c2f6fdd8284f9b6bb12e2ee5010001	\\x9ffd026e81d80bf46a6ad581fb6b5cce4b4883a4a97dbb6a1130f0d61273cd8c7fceba538a23a1afb58646ff13b718ced4dc2b19d89b64eca4594b1e4af7c109	1662104891000000	1662709691000000	1725781691000000	1820389691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
36	\\x5888799851b4b034ec44bc4f830b868da14cb3781caf63b7d54788214c9533243f05a43bbbbdd9b5bcceb86e1992a73d66dcc3fb4912aa1c48e5c7804c95c7af	1	0	\\x000000010000000000800003ab2dd0ab9160d01af049450bbb111e2b68d9d60adae867530b8f17aed586950fd542f1086fb408ca7daa811f279aa28aa2184caac7e426aaee45acfce65adf43920e42b0094c6b5402c947b434cd14e3254661adc85b2b09fde0ed0ccc514059aed14bd2ad78313790ef857fda485c8cd616abfd6527528f375fc7c034bc56a1010001	\\xd12f649d5b92287197002af71c7313ca2d36d6d49a0747b81887946a69062a97ea97f9eca3d8467143450d3f3ae665b71efbc5aa8e6ea4d3ed9463debfc6a503	1671776891000000	1672381691000000	1735453691000000	1830061691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
37	\\x5c181b111f81829b9ce7336cb11a7e547e04910930d264cc4b9746e0e75d380afe9c1f991f463cd478ba7c490096dad16c079b44ce24cdc8ece7e3e925fdd535	1	0	\\x000000010000000000800003ca47f6d05238ddf1228c0851a9535dffb7e2100980dff9147ed66fb2eecd6b5656f01416b0a876b7f99c275987683fd4cd6b75747cd04fe2ca43f7888305b2a42aec0d9df65286899343d45b6df660b01e79bf953b71a6d7ac55ec084f6c82c4652919761871600b761bc94a4239d9c384db539081b5e29004584a9681a7d311010001	\\x35497210a245e79f95125bb55bffb8607477ac07c7ce021dbe6bc7609f478111faca212b321f8931e9c0ee615f8bd49696e0ff0670d06247634e99c86ff9b505	1655455391000000	1656060191000000	1719132191000000	1813740191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
38	\\x60f03302fc79fbdd147c254e2bbab38e7ff3e8238fd3cde1d4885ca110c83cb1dad020e3200aa9f56bcdce9a358ffa30f6b7ccb5af9451c2bf6749798f211f28	1	0	\\x000000010000000000800003cb908094f58ebf23258008ad3b10a45a3be61f5771942c44ed5e0327b4b2fe916ac4d59e4e8bf55eb31f5090b3074d2dc4b8d708b7a254dd03f8c4695c80e6d412bd01b781b758eecd3b2005209feb3e2bfb312d0576bd4ce8968ee80be3574812010c1f0a83815a1e184bf3a0475df1e8e3c35eb0859bb8eb27adc6ff4f7b51010001	\\x7875ca2190bf8dfaa29d946426cf2c632024b8fa4c692fb8a52192bda4d0123ef277f900312623d4337154bf4ba108a777d682d93c2e54db2e1a8242dd320104	1670567891000000	1671172691000000	1734244691000000	1828852691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
39	\\x60cc4317539789ac7000c14bf4b87d98491acf929ec8c28e00a6d775543dab042b2b879a2cadaf1efaf22606d08523d258d31befd0a1479d4dc0931cee0d7528	1	0	\\x000000010000000000800003c8cbea58aa93c1d70546f73d5c23f8439eb6dfdf20f83bc723892f850428ca9a09cbc30e89965f5d5b3da812f25640aa828cc91978d8da1a6c91fbbd983926a56d410fc890591a23c2bb937d96a9525ebb1980bcfab96f08129ed95d3ef213becd0d37d6ffb66b5b227778831dddf235e11678693841ce5c1ce9100687a0ece9010001	\\x234393d75b8c2d087ae711bf50bfe90bf5dd069ed63bb9c525409231f92373f96f7a4ba9a8a4a0c6b9624d7685ebedd9876f9d5ba395841a7994631fa61f5106	1667545391000000	1668150191000000	1731222191000000	1825830191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
40	\\x63f06fef1a7a1bb1e6e1b4bfee77f44dab5c5e9841fd9a2d74b7019bd29e8f9838089aa84fd97100e859e856045c4aedee8ad0d009e0ba2ca118bc7a19455858	1	0	\\x000000010000000000800003e4352f70cc4651b666a0845c0ebfd6f9d0b177a83fa98ea91a2ec5405e471549134f3104e48d1e078992485835e4fd1e9249f4478095fb0962b7f2b9c42b2a977de9c61db0578536881b0722182bef551e4d587689058e948b02437df8528d611175ac48ed31a42b358e6b85b80aec01f1a05d3dd08c0a29232a432ec088caf1010001	\\x3fe1415224b088606e8d94aa6adf83d363f954279fffc7b144be3b847f9d524586e24723ab130a19c9268697e4afbb6bd4c67c1c4cec4a33b77d661e3576550f	1656664391000000	1657269191000000	1720341191000000	1814949191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
41	\\x6470a1d548d83fc8a07c3064599013ccbcb545e43f4a0faa422242fafe0e571c5ca25e645798a1af527251828b1489bf420749ff0388da103943b25f4f4c0870	1	0	\\x000000010000000000800003be21549ac59d814a350be3d6b26e370b31a972b1cb20e0ddb9b5a3056067dbb9d83ba538c8c24c599b97e7d4876d7496f1c30b806343fdff98c556dde94d0460ca6986e43805c2e3e41a3c30d454e020ce480957c50c43d5885ef5e15a6cacc853c2842e84bcd017e44fb36532a8fb1a13f32da22364b91f20b9266810fdc27b010001	\\x1cd4b7382f0d4d8b4a90386af076fd0d1732a5a2667f290e45572bc894d3c916cdf95dcaa41e9c57445a1817c5c68b95f75a8696f374e017ec2460048ab70708	1664522891000000	1665127691000000	1728199691000000	1822807691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
42	\\x6a20a3f38ddc9198b3b4521e909e7e714c58fdabe56b25c8f81a1b1901b8894fe46eadaec21b3c294dea0bc4e62f8d38e9da1463d6230162cdf958ea52c648bf	1	0	\\x000000010000000000800003bdc179d80fc927d24d1968e8d4be5424b432c1908060379040538aca587cee0ef7dc0173049cece17c3d99cc89800ac63666a2c09d6ab93d72dd5074029e4a44f761dcb3cae5ec3c1042867d77920445fe415691e976b86065e722b03e96e6fd1a98095b9d9996bd190cad6d8e06391aeb583209eb77a494d7a45763e348022b010001	\\x45f157d56c494c121f98bb0594ed361faf0cb5b3c96ed656129bf456520d5f51e37ea142235100a41eaa64bbf2c9335340d51f47523b7b1e1df293ba11cc760f	1680239891000000	1680844691000000	1743916691000000	1838524691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
43	\\x6c600b46d672bce89c4a8255b62093682e6f3bdb719efc8b21a31fdaf0c63bd2a9d1132f23784dae21aa0bf87e39232b436246fbee375807ceefded6d8ff88e8	1	0	\\x000000010000000000800003bad404808a1c96d30c18f403bd4cc0428d782cad840dfeac9e2a31e5082c1316b018a9b5599d32326af2b0154ad7025b69d80561fb85cada04c7afb33a1b7fce18eab6069dd13d126ab0271c1533453d00dae7581b734cc5ec072a84324a98aedf8f6a0aa8f227954c7791845c2824a4af57473327299aff711cf9754048f90d010001	\\x2a13bdc3105b904ba0d0924538d75ca77b46a13411e5f02b436872ab7fe66bb63804e356c52417fb2a23d29b2cc0b0043ef41a5f41d10a32b1b1d4757868b401	1673590391000000	1674195191000000	1737267191000000	1831875191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
44	\\x6ca096342455b08bc554a67bb5ce999e421da5afaa73dfae4df2b41d7cb4d6ec7f9ff9a8c858a69fb8d8ca7cd81b378102f18917ed2bcf35d1c6c7c69615948b	1	0	\\x000000010000000000800003c496c939c6ed151c4b29549d2f197035be52921cf3e11aa62e36411b6cd67ffd683be6182db0e0f2e93cbe5025c5474c36d8711b90cb1b43346240bde03801af00b79279dfab8bf2e481c8059ae73b67644affefa11aa029ffad6dd4b8c984a751c9ac3fdf96f8e7f672f76573452a9af15bb148cd485349c6588552a65e8169010001	\\xe680edc27cabf054e367a97877b5901f245f0a588a2d31ee87a11fd75f0889d7346b6c0d5520067d477b7844c41c1319aec8f65e4f0119359156a18fc2181501	1664522891000000	1665127691000000	1728199691000000	1822807691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
45	\\x722c38aaf8b76b924dd7f38a001a82fea4dafa56a9d354073b87e70b9e4934dc07895abc7c64e1d8d1a060559b65c98c086f035036c3f583ef8764a7b15842d9	1	0	\\x000000010000000000800003c5f7763fca2e5782517fe6883797b57fc69014b38057e5bbffa28474877501cdbe7e20ec12fb2dc8dcef3904f0cbf52913a51a581cc18de12aa3376aadb37feab22268b9ca7ba0cd9ef830d336e207b079a4cd5b9c107a6a6f7fe0eef1642c156c7ee1312190f936407e81d7d6111d70bb3eea099cdb918d0617f5e3b2226fdd010001	\\x401a5ba07234a3e4d7fb6f3a945000688ba129a5611ef7095916d73aad89b37c10e3c240fd16f633bf83c54def3ec4ca0e40273ef23748e8219d0f190a281a00	1663313891000000	1663918691000000	1726990691000000	1821598691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
46	\\x754ce45ecc37e36ab0d7d80ce6714270c9c704a596fa954c5d35ff9c3b610663693d7bf19b714207b2c62c7d03de084916d11bfc02d9c4ba13dad3572f944008	1	0	\\x000000010000000000800003bf4142a6896937052fc2e46215910308a2783451e894c6c4e4df8d4719f29ce937d744bf1590f5da3e46b50a56eff2643f19d815df10543228d0cb0773334ed9ab7812c575ad6cd3f66ea7c90b3e600d3fe3b1ff3ec0796fbb9b13f3e077116c763dd8895d9921297ef775018acd91c846c5dbeadabce4664fb92b120a248673010001	\\xf32b9c1e256e4c37335abce5e0562936b39c04c4fbab2ba823ec97c4a83109fa6301f9aa24208af6f0f0edb73a94e9713abaf53aae7f7c567f51d2d7f9a12009	1668149891000000	1668754691000000	1731826691000000	1826434691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
47	\\x77e0b57d083b622f8212221b67a17cca66b9d99abec112a051520c9df5ff14a2a1a3e7e58d6f2e21965f9010fa06c00c0c4b7de5e275b462b312ca68c512ef0a	1	0	\\x000000010000000000800003c2dc08279390cc8a2c2027154e9a5c5d7730f68f21438b6f7696b35a9785396d16b3e505971fe4c440e0903aa8288652728d4e8316d2891a836815b75171ebfaf618a2e88fb094e2633a5697dc100afb70418062ab1ce1492bb196a0a97625fe27fc5a199e97fec2ff4cae031f088b3a3c44da3cbdbef5b212d14c38379f85d7010001	\\x5570bbdaec5bff14b218d411f0c1e571427756cb9dce19e4a1c2438efd109682b044159417955f25d20b4e6b9e826cfe90164e06cce6d2efda9803c995b88305	1666336391000000	1666941191000000	1730013191000000	1824621191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
48	\\x79b44daa6a696cec071674ea9bda13beb84f620150f7c51182e5e5d9c0aeb80b5c4d92c611c253f233146b32519941db3e4d756374f852d777f08cd20a481238	1	0	\\x000000010000000000800003a90c55b07e6cf1bdb43a56093a625adf9fba86332fee58a70058d999d705b9821b7af4372254e870784362a473f46019eeb5d056676c6830af36d19a1cdadaac7e72f68782329a2d5162cf702dfb91a74e86ecdad042d075257a83e8ff32da4ac8d88f147eb8ff71c4a529484c2d93eb2766bfe4b8c1044c38f9d93b5ccb69ad010001	\\xf45c20d8ef02eb3aefba901b4cee413d4d292c9f72021e297ed4c7e9304355d2db8c1581d71aa0cfcaa946511ea26c06af898f3ca2142794ca2ca0a86bb3dd03	1672985891000000	1673590691000000	1736662691000000	1831270691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
49	\\x7d3452eefd5f54cee87e834417c67c465578e35fc45a1baa37b05972abad151edddfa2b5acff7f6babf11db687b30e81ab5d2354d15a3f13af5e4bbfd3a8b3e7	1	0	\\x000000010000000000800003e2f2a0485a01fdd50655ba313207cc76dfa1ed96ff7e3f40c15d388c69cf44f3806debe645d2f3ef9bf0ab5779d3cd7669188c3b2d5a455c2f1d3f47a44bec9fbfec7eb251297adbf25adda4bb7824878317d2d4571dad21f1aa11727e454362333008be5f8ffa8e40f2f52d3616091bdc92825bbf0667f08f179219930289bb010001	\\x9ad24ebec72f795d3656cb58b671c7e24635813cb6a7a70d4bc4b2c73215d48c3998ba760f0386b50cab35bceacb878f8afd8441d1a5a527169e8aab5c7eea06	1680844391000000	1681449191000000	1744521191000000	1839129191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
50	\\x7e68d7017de98321e7121ca3607ebbb411c4e2c1a110739ce7966fd6494463c48bec4cbefaeb91fb1a6dd96215b0082d235fdfa9ae827df6a3845b89602b9905	1	0	\\x000000010000000000800003cbbdc1bbd389c58709298d77890d5a1553bec1e8f2cdfb194dc2f071695c8edcca624c781fa9979ad570defdedd2416fe87e7908f7731fee79361b16d6b12cad6bbaaff645e6cb0f7c5ec1c2b3eec9c6dee47773f2c7c560d835d38d8216e3aaa83ba18be52c6a4c4eb57e043219edef6727e9f7e8a82ceb8497381b5ac70a95010001	\\xafd72ee9605d477c352f81ed76089b5eb5586fffe8f82ce75a697aec8e6ffd8165ac8903f1a2dd357e3dbd21ba3b909ff56c4168949b02741992641b01a46a02	1650014891000000	1650619691000000	1713691691000000	1808299691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
51	\\x7e44b74420f0abd547acfabb48271af011c492a94a184dc1e1a0516e75d88c0174007d71c421022e9f10c6f7bb5f96aa59dd3faa25c7bc7106dc04e92bfe466b	1	0	\\x000000010000000000800003c6e1ef65795f1874449ff8510899e7a0e46452b48063539e8a1520c4e5cbe91086854ed1f3ca98096fc89b8df7d9971768fc5594a0a419b5b14e905a01e27e5331f7e1f57a81fb7a373eea9f7e0e53c97ffc1b818e7d90ffd92f7b4b81ce93548c81eb34996dbfffd949a06dbba4ddcb4b9fdaab8efe9377985cdde0745c4bbb010001	\\xca372f38231cac3ba7d882e40a0c8864b8390329f9c869e0c2e18426647d36dae39c66a3d8a947028e0a3fb3a8759f3da3db59f49d92fc9e8b6c15b13a1d9705	1655455391000000	1656060191000000	1719132191000000	1813740191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
52	\\x7f8cf55afc38c0cb16ab4eb104ccb9a99917b5616fdff56df71436f446d4fa5caab8f339f1364ae87cf790c8ee2280690adfed1e0062bd57f718ba65b0f79e7b	1	0	\\x000000010000000000800003b52929d56692b3521451d024a9e114c9d87e2aabda409a0d41313fb7f1feafcbdfa6092174f06ee29d80f18a376ea199528769c8ce8ca025334de927d7644b9deb4e9e827dd9689356df528a0f84f85fc07e0e6a56bf5b510f1fc5f570ae9df9f57e89625a6d8542dc126cc7f0007fe5cb705e0e10fe5fec52f8f63cbb36302d010001	\\x69ab3964c1996472932c4affe71ac8d8d1a3fe13a816802aa440bd3597dedac2f8a22af4d683cd198b30510cd801741aff984b7b32ddd4b0d59bac7e786a0b06	1665731891000000	1666336691000000	1729408691000000	1824016691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
53	\\x7f60cd602ebfd83ecb8e1a5c9cccddc5508ddeb33dc03dd923966c7f53d5b4b6fefb7f3e86262d3277edced669968d5d22832972ef85cb6aba830fc31211aa4e	1	0	\\x000000010000000000800003be3c6e052155058c0e1f6d40c2c2059f6b5de27cc078384c3b351e188eea6a23ad04fd19dc9bb267a96a19f4541183f590ab92ebb2efcbb7e85d039cffb9d88ebd322526401ac84e0fc5efe8c7ba192899c74e5108ffe0964071fe28c828a73568905f23d68c8dcb603e8f6ce1ffbf2a1bff94544197cd73a132f7d1208129d1010001	\\xa233628f29976352bab520b862d1293771a25d3e81d0291d2edf8c574ecac89620ab272267bbb9be4b9a3c54f890dfa37f1e7d2ed5a43c1aa22ae777f5dedb02	1662709391000000	1663314191000000	1726386191000000	1820994191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
54	\\x7fd803bd05eda0ebfc06c0f24a44ffe792a69d8fe11b3a7b137c00410cf20b584535ca58b4823975bc026510a268aba32db85f81d40ce1beb439f49b506f9ab5	1	0	\\x000000010000000000800003bf15301dee64f3485a2b921af365467ce4c2812dcfad91f98a52d79deca6a7fa2329bfa6a9baa774dcc7fad41412846ef3532d524e478877f9d0ce46b51ea4cbee4ffd94ba8c0ad82c110ec4c550f0560e4dfc81166a4bfc34543be7cde6adbee43de1ef848a988a4503f21319c318871ba72bf787f96e0f27abd5c9c24cbbad010001	\\x1fa08a4fa15c354d883b4c6c9310ff39b7f5b911f258a0e20653c989ada4f2d91a2d6bbba0750049a800adfcb598a1f892d2ef397c1dc8536b728fd2a8c52908	1665731891000000	1666336691000000	1729408691000000	1824016691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
55	\\x8200eda0068d0afaee41ad664dfd2381fcfd1ebc364b4968aee91fbaf3f741944ad283005e9de8155136ee811ba72f4cce6a569f1dbd9966a3e6fba7fdde8a68	1	0	\\x000000010000000000800003d0319970ba965b80898fc8ede57d33dd4a96f3a92091ada90dd9b4a0e18e718634745480a05f70176d5a34ef6ab426dc629c3ea90b49c93b2d334e145e7214d1155ce78e583ff21f1d43c3b18c904416b830c36445db28dd2504c6b970f4e66d507eca221bd2ee9461727416c4e3e5124f0b1b12f086605ef1187e9883f9f2c7010001	\\x867dc9b0c6df7cc64eb40b7dc19ed57804d2ef7d18f068bb4ac2c140424ed32f86afe48acc1649c4812895f0b2b068be3d260316e402f8dd04b5105b747d9509	1656664391000000	1657269191000000	1720341191000000	1814949191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
56	\\x86c8dbba53c42ff1d24dc26632b668714ef27a1129ad4d55d309a65e2a80cae7146bf9078e603a6e80483933518170702e0c8fd2d2c9618ea8c8baa81aa308a7	1	0	\\x000000010000000000800003d16bb61b24fe703257f93db904e080a3077419dc7f79c88f0fb7f24e7cac44eae9dd92cf1cebbf163977d5a6ea672e7590a37d9e885a6bf0f15af4a521eacf654190346676a8b5fc63d56eff3a016aadc8822309ababedc78d993219a026e32450fb077f7268c937928ca8a61ec4994ec686838f3ac40539cda68afa84b4e24f010001	\\xd89ec2fe74f0183b9cb84b927af935567ea2656f6c4d93395269b26023738703f632df7b11de6945fd7a9b8fb283313fcc6a2cf6231df25b840b42c42b91320c	1676008391000000	1676613191000000	1739685191000000	1834293191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
57	\\x87081606ed65e1000770655cd6f3431a4de8f4f72726eee38bb704f3dcc6b13cb50905cb0961b19b88f6082bdb74033a04d36cbcc0160bb23905e62ce61a2152	1	0	\\x000000010000000000800003a9bc5aa0d4837c2aba0d840ba10b1c7a379950dec41e85ecdc8eb2eb2bcf83184782bd2ed932e4b3d9f52314f367ee87e73aaf8e8eb048ff9d09edca1c3a44210c16726b6b982ed8e96ad54b8c0e5fe1654c1ac89f2ac9f2ba2ebdd4115c6317188b3aea22df8967c18888760eef27a33518f8e47ea155f38579c37a3ef17d13010001	\\xe5340edf8dd0880a0c66e21d2d92c0fb393efdc4c73fbdc12a16a32aedbdfedb0c62fcb956bda9dd9914cff56b0029c964ed40bef288005d8dea4f68c3db7c0d	1657873391000000	1658478191000000	1721550191000000	1816158191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
58	\\x884c3f1beac98de9d84586036574e6e5beaec82c468529f3e45db11fcf9378e97d6eb496cbf1f8e83ea2864fbeea3de2b0240628a8f57a7e0b41a74e86bba0d7	1	0	\\x000000010000000000800003db2f997c7ac1d79b906b9393bcf590584584ef380288f3f7853a0ea9d236278cdcca9b29e3fb5d3c996923fb913f762c6689a173a7bd24598c6e219e62598785e74b2ddc0423ae677ab31ee5782e908f1236c95588bc96c9d8c704d7609168e8974926432fefffdfc63e4e10df501f89af3e8c7cac6683292b6e78efa4d365d7010001	\\x01a51d673c6caf73a286d579a629d4b96c1c8b31a3cdf29235f02f750ab4974e9702112a6d8ca157267a81444ccc96807363cb089b2719d23bb512d048dd9205	1654850891000000	1655455691000000	1718527691000000	1813135691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
59	\\x8a60949ab138e438bece5f0cf8a659ec0e2f48431d9bc7c6614d4aafeb6ae0edaa6ee883a8370d75227e606a7046d207dd3a22aedf8dfc2f2241c8f95094c1db	1	0	\\x000000010000000000800003ba0bc63be44560d86a0e991228739b28fd34ebabd52f41a834c4a4d2f62591d4b1a5192e47fce53eeed304b9cfaea7353d8f977a1dab0ee82b44883ccb98dbbff06fb0df87e2f6f3dc9f070aced52d5af24da990da4013418a81a67602b042b947246f1c4db268124796f7c3453b3aed28b0a1d7963706b863dd49876fe81317010001	\\x39b6bf714d58ed24187d13aece27ddb28415f0dc292898f9521587119377d0c0cbb90e068e09d5016b417b64896fd61b41591b9555a336dfb2e6c5dceabf6905	1680844391000000	1681449191000000	1744521191000000	1839129191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
60	\\x8cfc788fe9ab85252eee2dbf974e38f2e5d079bc3508c987af50592a5194f96e88c3898bfa9bd69d986ee4560798a9a84ab7b5e1bc79e8cb57497b9d2372af01	1	0	\\x000000010000000000800003b0e15ea6f1d06bcfdec5a793e2c34444ead918020e1138acb705305fb808bce93a703f99be29409504f7e224c2899e5b7acfbe07a7671a912e7c988d78e7c8a7afb27f86656140160e8fd53fca8af576927ccbb1d7c8d90fc47ee7e549884e31b3c12c55e3aa74b181bafe5b601cacad9f3a30ed7e7312e8bae170fa4ff685a5010001	\\x794860127be0f6286120f1141580f1f95e1ce15578281a4393b285e05123bdb743af61a057f7f554a11586d7ae0fbd9851292d4b165e38fca2c5f943553b210d	1651223891000000	1651828691000000	1714900691000000	1809508691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
61	\\x8e00f48258bb9963a4f69e792dc024b5a4bf582b7513bbd5997aea7309e7cdba6cea0923902359ca86d6afbff9941060ba6e0ad9063932e4d8136a603720a9b0	1	0	\\x000000010000000000800003f3f56ea0702a61848caf4561ee49b420bff599137bd66c415a280a1b68548ff644faea55e946d7a72bffd0a2f694db141a6bb6ca456a0881ceef7759281da67762d570339c336dfadb21ac37d9d76ce4e656eb8111db2c0e2de3209ca761c7deb1ba7e256781b56841198b828ffb7e114dbfde1fec29e18efb70b1bc1e72bb07010001	\\x2cd6191096f8cbb7293f810072a10a03e66a8bca5b43cd0eb9797f015f65e6e2dea9a81b14f2eadb2c3906fc68a7e5063b4e6e845991bcac6623ace6cf3f060b	1669963391000000	1670568191000000	1733640191000000	1828248191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
62	\\x8f1c032b414775aac46710ff3ac7c401d7e56796c7eba217a7182847f1dbc705a7deb23f40b2368403b283f2f57a6ed0818067342725a21bec2105689529248b	1	0	\\x000000010000000000800003ac08eb5aa3d6a7c266313d5b75b40ffe53b31709f6a251aad5527fcfdd3685102658dd63f3816c993da1e7a4471816d52fdee3e6edc775d0c6b028c135ba66ecbcdf8da484dbe28f2ebeab29c888c45b338c43cdd742b136a6324d7dbf7c4864df62ee264b47c9907eebb1a6cb0064c6b722a80eb44dfcf8bb241f40a77afb87010001	\\xaef5b64503a7e8261edb263e30409f5ea69b9a4a5e6ccb7ea7149624299b6d6cad18895d3eaa786ac94446c9b01f0be84339743d98b5e025f8c30b866bb4c50d	1671172391000000	1671777191000000	1734849191000000	1829457191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
63	\\x994ce1fef3ebcdc2ba0171a222aec7d5a4860ada7d6e7d9c985b2a961cfa0468d04f13bb7c01fdad007e3cebe049e7781c2df95cbadd7b97da70383a22986d75	1	0	\\x000000010000000000800003c5d57ec06153d478bab1d9941304818ae6d140520749f2a2b74414782c062cd953b0880743c812b9ab0b6c2750b4435679daa9ec96529e83e4a9bf7e5cf4393ec620677deacce8599e0db756cc26d4467145195428bfbbb4efa4afe2d170b93642bba33f5a8eac54a0d722d187a22c2aa2022118441c175c2996fcf84c701c99010001	\\x631618027220cdec3293000ac1c0e4fbaaed30ac315297f263d6c85f5c7e6905d1a8de11d78d33f89f43ca042a7fc965d97d8ede4142056558758a2e999ae40e	1657873391000000	1658478191000000	1721550191000000	1816158191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
64	\\x9b7407d8752268f2dd57156eac4edcd052e77507477d711042d3137e13fac57987184f574cc1b12e31c089c094f88aeb27f8db9e76fbbba8426d991edc158d24	1	0	\\x000000010000000000800003f66e74ce643c848342a52218df739e3d8c97aeddeb79b4d1fc9436108887e8cbf04ae4eeb58ae1afe80d9bdec5ddf30c7f6f4a0ccf73f874916e26af1b905235a8ca88ce4b13c89ce7111a7f21aecc89353225a78518fcdae46b811394aa5c1b8d98f922adee0e070cef1a08d311d9a4ee3586651c10d2e78dcd800734a2f927010001	\\xed1bc67619c568652094f5c49c64a5dcd6423e3f5207b47a7e7cc6eef6f1ee35d6b7bd9b141931bc0c630d2cd0f09b62a62b4c96bfb507de4639b661db0ea603	1650619391000000	1651224191000000	1714296191000000	1808904191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
65	\\x9c94665c73a8f7f875f972b3cfab20f87e10b13db61d9729fb92b496c916deb7415b5cf5c3cb071658549962ccbd6f120bab343d16e6cdce14130fd3589558ee	1	0	\\x000000010000000000800003b9a733695dd52c51aaa5d78deebfe337cd0829eb6830393e4ee39ed0335563b52625add1a9306ab5c3341bb74c189c484a5daf1ea15573b69822bbbfcc6e5ac5eb6ba15c9f189cc519084da241a1a085800effc48f629ac815076a20255f763659d4d44c8c2690841b60a58096f3203f447cc5dd7b75e40ac01c3c0514659711010001	\\x863dd790b039e133955a15e6e965e60574b6b2e64b1161d618cddb3cadf5e3597c34ec69edc37be3504448a1a7332ad98235aedc49f52a50fc4b71f389c43503	1670567891000000	1671172691000000	1734244691000000	1828852691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
66	\\xa2a4dcde56d887e56c7b31d8e4757341b5ac704b3d09d4b1ecdf4f8a24a6ff6595d10ae5d3b434b53454113290fdb779bf26932b5dbc7af368b4c7df9ba2c305	1	0	\\x000000010000000000800003c5d8738d426589ec62e6bb0beb1a273f2cd152f44c525ca6611f70c93ad71f4ddf5afcd2453615145f6909c58b3e8384ad666d20034793e28ab9d3eedc323c799629a19dca9baf457257ddbeb67fd6798150d76e2216b47715b001ea46ff4ecdb8853315b111364c8f1863498b5d53e46ac497577e82a760eba7c336bbb016fb010001	\\xdf8b3fbc7de50db313520b4cc5c815c72eec78289fab16d37eaea37f7086944bc9f7c05e3ba8603722d8d4d18b4ac55c52467dd42bad59998713c958d9e2b406	1674194891000000	1674799691000000	1737871691000000	1832479691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
67	\\xa3d88759c660a5ca1ed4e4837ab285914d9c37bb8276253aa4b2db0085e93e7b58bf9fcef8cb4a9bc57a3c63b08234c5462bb6bf294693886402bc64a3d59ebe	1	0	\\x000000010000000000800003d473302f44f5c5ea60804566e3e634d260deab0179a25cb3379fe74dca0b723b7b0fdc9df2f9b809db9be3f8f6e5d085ed1f0e9d30b8fd55f38435877bf5c8d99270f14c1f9e6d904d3ea7cc5b6c05b120622b0c2f485ca7763901f7abb752d481372da28d893d42930db61a992c6be963a56defbb75aecf477f7fe9ae93c431010001	\\xe61a787b99ce0e249665f9de808cb05c3daadf5e5dd7a5c9518e8992d0f3cb9ec1e42f33ae6856d2cdab334dbced0a5ad7ca68e7af6d2a2a22c16c2af0590103	1654246391000000	1654851191000000	1717923191000000	1812531191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
68	\\xaae442d54c2eda71de9dd33e53ca8dea72919c5adcf1cdcff8247a814317ca4ee5a47dae67367b93b3adede1a00ae0f898152e580819bc8792834c6f23bf2e4f	1	0	\\x000000010000000000800003957cf62e0b8a0d7b3970bf45ffd3c1053c23a9b7316415df22dc94f99e50e4b0f44bef03b79792da37c3a3fa6748a4cc0b486838d2fc7e962250adbb8f9bb9540093e12de2d436d5af7f2c4320545767fb9d88385483f9499dcb44b8ab37e5bb778550c7741ddcef7782c16bce56efa16da62104ed1203bffb20c857ea4747fb010001	\\xed7577607df8b7bb486c57b0d21ce01cbb282be8d5e8c6d01cfcd0b5e861d5ea7380dfe2c23825656a45c6dc3a694c27e9d24742ad1291203bdbd57ee645ca0c	1655455391000000	1656060191000000	1719132191000000	1813740191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
69	\\xac2c7cabfbb43f79feb89db14111163c56e755d015f7744daf1586a7f1214ec1d24f3afaa9b48505661cf7e2e7a751df2edbc80a62dbf162810fb11e0e2bc07e	1	0	\\x000000010000000000800003acbc35aefa1d778cd9de46d0a79c5a7b456044f6e7c4eab0f742ae7145ddf633cf19e6b46d86852dfcd5b752d1d2c86cc0066b18818ec609be510d1b937255eaf57a6f41ea206c0c6b0556f2d181f535ec02b9339dca50cb26a4211da29aa5c1be16637b8d0d8ff4e1f0c6ac5dea1d00def54071b95e859f32689b94f7b52c33010001	\\x9820299af3768e4c87cc2e45812bc7542fc4b15c02569b1db5b8fcb61ff6b90b28cd02fabfbb75770731c642dabce11a651c37ad5afecb3fa9de27901dbedc03	1672985891000000	1673590691000000	1736662691000000	1831270691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
70	\\xb0fca7be87bc2f41aa5cb5fe0531532afe10d6cc93220bfaafee125e0a71d02e15fc1e146dfc2e0488af605d5e0b1c849dd6c014924203d0d1827f35501306ba	1	0	\\x000000010000000000800003bec9117db9d8c6d5ed12ff7b1171ad2489e1be9c542d56d61f1edab85302a145dc72a577e29f4f601f87169b3bea9ecdc1cefb0a882fe3a3bb3f4816f837725d21cba00cb5d032d33d5f9f7ae3210d2bb201de6c865862778ca98e2ca13d42591fe595d313c440ee966a6d4b08273609d7b27d5ef6de888792d753f1f8d34357010001	\\x61069ab89d2818fd2cc20bb4f62479007eb1c75bd174936a35d753684648e6d1e95c20e8f5c311614a7560c3553c292afa075dd92a8806f946147ac67d651909	1677821891000000	1678426691000000	1741498691000000	1836106691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
71	\\xb298f6c05077f7d6d13a1ce8199c9cc77d90391b2c67a31e15d4e36a5f05bdfc12bb4b275686d07dc6e46aa0b138482e64f92266fcd11317b46bd7871ef7ade7	1	0	\\x000000010000000000800003f31aafdb20c7a0df0a3a39a6f8bc8f368cfc97401dfc3dfb39810a945e178e78acdd6dd2db048a42b05e2362a90325ec4daa5a9fcce828dea4ffe9449775acc77fc96f72e59891e64431201a5ad9f0ea4e2c383e00ed63cdaa28c5a5aba15e5b1364d4515a1e76f261ecbfbb988dbe9c0731da8b42df313f0456ccbb3f37b7fb010001	\\x7b4de70b4298a1c490d13aa4e5d4fd103280f40d287ac96ce21031e061f2237afb9dac1c7d0863587348d94abf7e92a9c0ac9df7ab6ff4095fdf72928e8b9d0c	1681448891000000	1682053691000000	1745125691000000	1839733691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
72	\\xb4d88eb6845eaf4417fbb571b5a51ed4a5f1bde306fdf9eba33d08e0660907994407ec07bfef94ea54943193f7c712ada22fcfda7719df4cd081ac0f59d30c9b	1	0	\\x000000010000000000800003b09d3dac432a36b6d6d15da181ec4b84d66c93b671961df50180cd0026ebba78d754797752f0854fa74b9831282437c49220fd9d757ac8ec4b9f4b3997030110e1141761d888231f1a7891719c4f764a429bbf6681f1b8d0df54e45d85be06ff379a765ea75fe18cf686aa1a39a56eac2158676fc16f804204006609172f3765010001	\\xd13e15dea852f61b78a0acafcaeb3bcfe3c72ad3dd3683af8e7ec4e45bbde7f4572c3af30dd538da81e838bb8f245c5aba994948c7a6f54524e4a5cc5acb9109	1680239891000000	1680844691000000	1743916691000000	1838524691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
73	\\xb5f8663b1efbdf028071ee0dfa59e46f4051120fae7ac3ab48b7dc242df995d3ef8c4d0f71a8cca41f606c7e45cc94cdf3620199b83ca551944194b67cace3d5	1	0	\\x000000010000000000800003a38c256018f2f4b44b13ef4fec1ed8d0b84890f8a9cde256ab91410451d38413e885961c365a3922f6020405da80914bd1a696cf02f96dc0cff567ab8b684ee72f5b2af746f842753b20adc2b575b20a03314919700ba432ff8046a22d5821f0281b9282441ece15a00a2a260d4ab921c2ab8f1343dc3f468417dabda4da2093010001	\\x1fb23fac9fdc566c22ad7d74dbfbc66d57dac88e04f1c035b0a3b253fd3c0d97ae38c08a678b93420e13d1cd8e245875eac1179a115bc4129d882de5d671f702	1660291391000000	1660896191000000	1723968191000000	1818576191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
74	\\xb61c9d2a27b468863f37201c0479b03a08a9febc80605ea55bc5d23d757896a87c1a1c76cd3b8aca1067d8b1ac0b15c37ec151e9cfa8ce72163443d355927746	1	0	\\x000000010000000000800003b5e3a4f34a3cade81cfe56dfec05a53ce63641cae2f713559371ea311ccd16b4d5908701675d44b1c1ff1f1054a666ac1223d7807b441f78e1c5d9d5faa6ea956632923c580fc2ef4bb3f71e736604f02c56b7d9bac70e81c2b7fd71572687b1ef5237588a76556a479366956ceadd7c9fed846897234d6af068ec70e0de8fa5010001	\\x085e9a72be42d69c5d88f79ef60d1fab7c149ba2721a16eca04729d0a684e81b7fb807080f91f2338d24f1694947c54ed42271e1efb78b05bffee87cf31ffe01	1665731891000000	1666336691000000	1729408691000000	1824016691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
75	\\xb814781120e3d2848b9565f729a071419c8455fea25514b1b384608a93244dc7b117a025ca17d62310a1ec52115223d56f9fe105cdf3ad009ad9b85cf943fd09	1	0	\\x000000010000000000800003b28e0471ebcdaa7ccb5cf380db6200de17fed7ad7cea9040c2dd1088da5a529c1651c8636fdb6f87b3b9169000793caad5d6bd45e070dd5f472ebadd4dd7e34be8f7b4d5c99d26dbaa49968f5c42a146a1eb71e0a1de1c350ef09f4df806a4a2189d365f0ce4a4a792b6de653b54f85dc015c32465261311aa960a0ec2e2db03010001	\\xd16fb86c4b6a8092660336e4b5b8c8849b92e117d435c98104ff4f3db221d6076c0b46827ebf932c435ea472f0e0f815fda9d8eff713a0cc79daa8bc61e8630a	1679030891000000	1679635691000000	1742707691000000	1837315691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
76	\\xb95c8ee33e65af98108ed419cdd7120bf185a17d654340a2aeb6368362a8513f006b23d5da7f981f6b99907616eefca7f560b0c80027da46b185f78670effc57	1	0	\\x000000010000000000800003dbc40d35ebe0f10db9f1cce1608c6f12ca60cf481edbcf7026e14eb8ecf12c43da31e343af508841e5397029a81bb74f8b174e3cb25fca8a02904942189673489a1d4529979755ce7e6e5744c1f977580e6761c9410e22ca41314e8b70620760741ee5e2173db4a330e670f435affacd0e7aed98586ba26365eddf267ec2eb91010001	\\xa348f6b4ad6337fd5370d02c5a1c195393d5fb26228e540e97b9cc7fa868a7ae6772e4923eaa38a7b38eab192cfb1cc69cb27501aba1a739498ab3eb55a7d508	1670567891000000	1671172691000000	1734244691000000	1828852691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
77	\\xbc54b9d8a6facd09379baace7ae2ca2e526ebd027072a35d3ce05c11969727cffc727adf11977e5b696cd10d1be8cda9d29576bb03bc64ac401bcaec7054a7e8	1	0	\\x000000010000000000800003d5efd256a5802cc526f68aefa87e24a551633a40787a13cb3bb12d4b74630731e2e3504bee514ee25c6f47508686bf451c3c19fb64ae07c9c7921311eafaf8589f74927d4d17cede36f8e56daeaee091aa0a99f84cfc35590f43d1aac371cc4dac8be63fe28feb8f5c29e2469a54d882ae78d27349d7d9fe2116a349c7beefd7010001	\\x66540d0dd4683d35df8fe9fc6ccfbb06b6968e710c7fd309ac59fddb1e67173a9b5956bbd2e184f4210066297e61ed107dded0e84886a020e6623fda18bb010e	1680844391000000	1681449191000000	1744521191000000	1839129191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
78	\\xc008a3932fd5e4937d21413f254f7a7c67bf2cacfe466cba01559713ed3020a55733ab82c631eb89ca147766c38bf3f86bddc1f095abd54c7354aabee45d24c4	1	0	\\x000000010000000000800003c5ac99579125d60641b14b2b10951c41a119d860f3e41da55f491b1acc3a1544b68c6851330601a1ac1cf418c7e9cda2fd05c302759abbd89a5001246116f66b143a9ab3c3812c40795860ced31ca42ccc32a45da774bca8edb771717805c28b78cb1f99ce0fb9bd515f4f1194d76cb7c6dd18edd1e31c58aa234903df9c3ac9010001	\\x35d7bc7822a7acf463bb58aa72c45bbbcf3772cc468a43c2d8d5d4322ee77a30d1f9490b2b6693a91ebbe16805a92a1bc12a2be044e563c00e44d7b25e6bc709	1661500391000000	1662105191000000	1725177191000000	1819785191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
79	\\xc13c88aa3c5ecf7e5d97eb19775fcbc8dbb2ea8cfafa366206119d7b1a6de3baf671466c3d1e0fcb3b1369bf347fbbc29b7e7d72fa8c3326bc9f3287ca9659e1	1	0	\\x000000010000000000800003b916da05dc44a77a77bb6706c89d41b38a22d76ff38d5eeebc4b116027f79f463aac5c857e2635798f13ea3421a67cbbc1a0584d950944916923bab8b192607ff0e4711db4758c251e9d112191aa32f14f9982b3a843c9a499dc0f46fd35cb4232b756056864924bcbebe706442c46ca2f9733e9895d00fc049f16ff88d25767010001	\\x9f2c3975c3cf9e0736561470fab2f2155d23aa0b3ed2eed5944268e466aa3e740ce0d0242333984061becdb736fb1858bbd0556eb65be62c67c2b7c97a6eb006	1656059891000000	1656664691000000	1719736691000000	1814344691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
80	\\xc1001dcceeb4eca0c3d30f2945684d4e2a8091b64372bbf4621062879f2a891f9f723ac575de04f8e0e545579b627200a6d977ebf6266adfbe25061b9d5792b9	1	0	\\x000000010000000000800003c05bdae9d7b1ac8545160240bbe83f145cec15b6478854601d37d05841270e76c6c1596d2ca4f2d3bcc4ad0842d7ff24b8207c7fc97958f05064990f348bd8b779b3bc73c00389c89b533ad8784ede1354d010cad3c7b660a661d7f0196e9d3dc032084f287a0391a1a14d8ae18a83887303f254a6338a6f8be0e45c4f363459010001	\\xf22202d1859914599fbec56b20ac28514d3754dedf86a38ca8d3510bf853a15eed02c436b77053f3148f0d34ec36a13f4ccd719dd107374f6becb9052665f50b	1654246391000000	1654851191000000	1717923191000000	1812531191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
81	\\xc460dd2a71da8a82f5515f79dd1b36553b9c4ec2386a236a49994163f5461efa66830d503bfc1d26d22aa300e915e7b8a3569ec4173a11d8c9a4df05db6a75c5	1	0	\\x000000010000000000800003ce2c32818ef9a85f44ff73e1e1119fd1607e6a64a1e04caa9894b97c77b0fada245249dfa8ec363a6b9da01a12939a4f87a34183573e67cd2a3c4e86c3fab267cbfee85cb7e8f7e06a26db49dc180a8f1ff3366f2c1939e824d4408693922970ef5235afd64e94f8ae3bbab56f8c4eb58df0088541c711b08eb447e5526eb18b010001	\\xdecd2dcdb9e875832f9e469f141b41cbf07dec70d5f59366bae7c5e8dccd11d02e9fd8c59525ef22d23164ccf9aea32481bac16ef965a2b582c3a8ff529afa00	1661500391000000	1662105191000000	1725177191000000	1819785191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
82	\\xc614e1890899c101e4078e8421a63fe7585a7e2b9fccca652ab73f9d39e3241f88f5917df6249b40d17a6de187b4c4c0791b5ee4850daa7cfe9f513b7953ecd9	1	0	\\x000000010000000000800003d7013c03e465256b51df3c607eb47a7e29073b4a67dc9190c85c366a1ecb80bc6fd2540683b0bcb4e4f78d8d8ee8862f0afbd54ba3e73138141ac6aa5110010ca0cfdcf83dbe0a75a3c5792162fe3513d8f359fd6df37a0dad6d5306a347aa3d75f519cad35c4dbcc958a727dcc9727501a3fa25d6aff6bc416ddc580240bd5b010001	\\x36f653d55e7d94b46ef5cd22a467bc321689907bb8ae9dcd376cb80c9466d78059986dd3e12a03f5f4a6e7b5a417c32d2cb316456f534251fc6080c48233ee00	1661500391000000	1662105191000000	1725177191000000	1819785191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
83	\\xc7fccfd8a1c9303b0c33a9ad8a71e07bab0e74a62c81a69ae4f8d1a89512f990efb85436fc0f3a782524015492ed7264700a6b9dd609e80215090d1d29022a2c	1	0	\\x000000010000000000800003b116031f763594b024db71249488117b5dfb7958b8ca291597aece07c7842d6da3b9c1f110774276630f32681e39b2d80c89713c231496ef44dae0ba4d2a64c28d6381dabd39c6902f9247c28dee3e3e2779a3e9b068c60ae13efe0553a2944bb88b54691451382bdc808e6e7e094af0256c7725cb2a4f93983bb7cfbcc71fa7010001	\\xf4938bfdc86fa489f4addd98a202316ed658601792f6d11be1124d4fdc89e1e9d7f3efa391c92888d09850a86505c9bbb836b82c3f1701fcb6258c603dbb1d07	1659686891000000	1660291691000000	1723363691000000	1817971691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
84	\\xc93012c70184fa0fe998830d061f58828c1e5094cbd08da33de02ca2927b6985f1f0c24bdb5cc2a26807313b2db5676ae981c2f68537f159d20ddbb1d6b3d01c	1	0	\\x000000010000000000800003a8156e8cec9a97536c9b9a3e8c0fe5d0de7d6c76e93784d3425d4847355af563551e497604167a5df5cec9c5fe294547321aed8c8229f0ae4194e37b31d1f504c442a6d6ec9c08fe27c3973334aa449b977d7607ad9c7245e1f61313829f8642f6318cf03f063a87a3c78bfd463634db7a60b43b02d8a693f64a3c450530820b010001	\\x3752c4b56a267068097650aeda1cc049df30455bc9d5a8d88e0c512d769fa814ad02fa8c0a840a42b54a8f1c9b5f9a9ea2986a571523bc6ac8c21461f048ce01	1676612891000000	1677217691000000	1740289691000000	1834897691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
85	\\xc9d84fd7f28ba441b827f1a9520c0d4d1a4ec244ec51453825651aea1a8cac1a1df32251bd036b7e2456fec3d15897f466573e65e7b2ea045c9090e562a76acf	1	0	\\x000000010000000000800003b4fbf35aecd9b236d7277c47bee83dbf8b1b9d0d2bc776a1fb7b566ebeb10af41b73ce018d64b29dd0916bfd18d825519be3b21ba761e937909481cf7fe260e51f8479ed12367e47e1af3a3f39bf5ff470a10a38e4d91964e2c7d1b7011cba7cf5ab4e88842deffe4df668e1dc020b1561fbed68e5ea6ad1bf04daf97028e3d1010001	\\xcab63753d34721bc34c20ef1f96dd605d3c8091c2f7e7ae9d42c79025109d59d6efd74cc88d440572078895f0b01134ee24b398d484bc0ec4f0dbf2eb9ca0c0d	1677217391000000	1677822191000000	1740894191000000	1835502191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
86	\\xcc64d9eadfc3a4b45c946ee5320a129ecb54e793c9713fb23ea6c0563a18ce4c4abdefb73eeab82ff887ab601ca5ce2355eb6514e14c1f1dcd9308b1ad5b5ed6	1	0	\\x000000010000000000800003b15e7f053cd8be4246e7ba92d1e071351ef946a0e291a7b7aa61fa895392b5d2207f3db0556c102744027e38641405776f9e72fe760109d609b4be43f102f77c6f1aab91ed48d13771dfaca8a037d5f59bedd2a02cad1e69f5eae1176aa078c7fb8d59021d218888aad20e11e31be6ca664de597d7a853abdb524b382dfb4009010001	\\x865ca52c158ee828b616b3f211f9ba3486e30f01924d51e9e5c56982d920f3a679bbb6fa83d9024fa1d826110f8050e0575b0bb8786ceba27e425b4aaaf36203	1672381391000000	1672986191000000	1736058191000000	1830666191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
87	\\xd154b784a9400858f52297102bb03a8dd0a2872e5d9d4cb58b25918beeee3f0b9d64e37ed21f7474073ca35941ec6448ab0962887f8eaec7e804d7cda307514c	1	0	\\x000000010000000000800003e26af41033ba030e00e3f451da291c4890fc35ac7949e588d682f9f67cdb9e38648fc250892d62fe03d0335b380cab1a195674ed2016adf217bc68d03715082f178fcd15d0fc980fbb85d5933dcc4eceaa95f8118de66a286b700dbd1b0a7b203b070163a55b05fe06899ad165c1027df56d85e302f6940b162a12c6eb765cd1010001	\\xebbddc2ccb492c6ae1ff553764552cbbde92a706db8b3ab62b6733f00eb2c46e58ad8cf9bd05631ec4359a44f34d371d5e4e909ded3f9f7643f05cf023332d09	1650014891000000	1650619691000000	1713691691000000	1808299691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
88	\\xd228cbf813b0960d1b5d7439659d6857a823b5816182239da6bff2788e34a4d68096a86da2894c81e3c9857dd0c3170da8a337cd79e77d59c3dc69e03783979e	1	0	\\x000000010000000000800003b4bc526c421867177121b59fb504e53dc0a03c1c683a635a42612d6b354d9567fd06cda88a7fce6d2246afbca85f97147f4f45d2171b4e8ebe1a2d0f2346ee1cdb768add582a855179bbe0f5f98d896ebee7eebf379117495cb2af12482ef6367bf2ab2cc11643b754a11e7a4a45aba9ea29f275e117c1d6c1f9cceacfb8b6df010001	\\xc8858de1a45d6888771d981e0ed29a87938a808f8de9636e90da166a9ee552720a6b87c4dcd0376252380910d4b93d3fe448a316451257dd61752ec752258505	1652432891000000	1653037691000000	1716109691000000	1810717691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
89	\\xd3ec13fdc5a6b008e2a9aa9744f7222b0216eba0597c350aea55a354a6d5d6057b118fe3c84ad7c7dc339045630312d7efe611fed0b306196eb12efea12fba3e	1	0	\\x000000010000000000800003d70318d332444e95e719e2fee3d49901cda59d4a5d3355c1a3398c4dca823247261fb530397e7a1f28c0a043a70e31a092ef84d51885268fcf77ce549966bbf47ed9298378fb6b9a3cafc2bc91a8d746eb1e146083f30035a2e0c6bcaccc60dd1973b9a931e745e0a84039b59227d47a029085491413d86e4272baa3b4912f15010001	\\xe988315091468a323e5451f1f5f9444658fab55644da3eafc67bf21567ff152a472115488fd7efd7a850cd63c58b25dfe3a68fbe0db888e685837161675c0100	1654246391000000	1654851191000000	1717923191000000	1812531191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
90	\\xd460da9d93205912a3a64276a0c6a5da4120b18e28d23e3e3aabd4822632475d9d5e4ad729135cb5120bd51cc708083d1237f1234c5eb3099de20df832a1c4a2	1	0	\\x000000010000000000800003da7cc98129f6d5adf0a32a87c505b2aa53dfbbfd3a1785f7e452c8df42d925c3582f71e91d1f3c5084d8bbb4d7d14161d7220405970b00bd6fe2dd77df632ac16b575435ce913ea1622065d857dc768c2ebc5c86394dff1d3f95b24cd7b67f4c927f7e7cbb021c197225382c79766d3835b8c40027c1f929217cc89760ddd10b010001	\\x46e38322ae3e406f1b11bb60cb178d9f59e79e72b8cf48149ed5519c1d2af102a7474cb49c7e0aac86e993b722339936c18b7ee863b80c65772c81c618c8b600	1650619391000000	1651224191000000	1714296191000000	1808904191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
91	\\xd47018b62ee9b1b2e23c97624b59754005bb47ea6e31e8a8588bfe25e95d4818b0e681030c75150bc578d51f65d72bbaef8a00d2b3cc026f277ee8d97b9db55b	1	0	\\x000000010000000000800003d9354f6d389b9d8ee9911d8073e86da725f578275ff970c740d3de13b45dd32fda44f56479a6a9c28ce58975f1187ad56599b327cb8c471508700d7f76c9ae53b14727cc96429254abebd15f28d170ec77150010141f8f2b945110a18f933e2ed41420c4c93d6369bc330e9cf8d48e31cea666d92803b955a698b2c86f6686bb010001	\\x9948a95d9f71e1290d56338fdc310be5e9306f37d9e959fb2e03fe17c52486a0cd095730a0ff3ce3aced7bd7d778a11d3624e44c7a1343dcdf7b0785144f7607	1672381391000000	1672986191000000	1736058191000000	1830666191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
92	\\xd7e0fa6f66a4a35e17db8767cea741a789d76ebf378de2444ae7515004688f212419431d733516deb4ca3a6943b6b296203f4f9336701f27405a6eb3d117311e	1	0	\\x000000010000000000800003b136c83502ec235d4dadd8a857cdd947ff8a7215ff5a1f33d3547900e28f6ae661e807253f46fc3ec0b44b8aa68e8e55f15ac8f88d72a051622ed5d1207aca7f9efd4ee4b204dcfcf89e0f81b684160793da7729976d156fed0ebbb62c6ce9e3c1d7e6f3e6f55d19ffeb060b769b26d337c2f8ef0d3e5274d7303ea525f19589010001	\\x08f9105a62ba184932da98b2cb1bc09537ad5f082e296671861b67c9d7051f6f80edc1eb4df521c41a3ecf6eae4271e8b5c920b370d1f4b66eff885dcdf3f700	1677217391000000	1677822191000000	1740894191000000	1835502191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
93	\\xd70482ba8a0295048557a39b7bd168dd41f11073bdebd1b1092fa1d13fd1d4010e2ac6428244d74413304c92bc37a15129adf9a6f56b9a501d15b7cf74766a80	1	0	\\x000000010000000000800003bfb920536e78fd1282af43de20b1dcf9fd5397cb11dfe214ef86ef542c1f385670e7a21282ace4f32e6ad6b8209bda768228f1d2ac079840ff291a89747125741ba0935fb9b9375af477566758b2e3c8306434a10d85e00241b6e153765a50ed7c4ae7497cb2476d4627c43c8b5d83a140a6f58ec39998835ff62ea35fdc136f010001	\\xdc49db04618f0141cd96bd46512d9b1722285b4eff4d5d866a9e8a36089255993b9d6e9977013b0734b678c00a73b582eca98f402fd3875b2a8d27669614cd00	1656664391000000	1657269191000000	1720341191000000	1814949191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
94	\\xd954e6091ddb81abdb8d78bcfb0fcd55d65cb84766365036499f2589793f7bb839824b5e1ebcba680e1ceed31e3cb219f7132854287cf20eefae19c5d737c472	1	0	\\x000000010000000000800003e311c886ee29fc61c9395ff6a7f187c538d49207f41cd8794cec5910d558a68ba9be4e418fab7de3e2b79a5b0cc1692c945819a9b812df0d61d29c52b6501cd4c4c3cdb3d692d2e66d6acf1bb1eabd644b806db87ee584e2543772d3b3e23fef22ce0cd8872518739d39253979a31debb55f157a0c768352266da541624a9cb3010001	\\x7535ad6fce72ffc94a3f91926e6de42b10ed0816b1f9e2159699393c49771a5ef8461cc0d7cae7262d1c1cfd775e6bb23e474ffe5e53f3cbd0a7f9b314695501	1668149891000000	1668754691000000	1731826691000000	1826434691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
95	\\xdba442defbaea76d61d9e310be8521026b95073de68762f3bf052845d3e2c587a919a34d553c604cf75e55da04e9de6b64c2fa1d65f1c4a32cae58888d929158	1	0	\\x000000010000000000800003a2bd6e9a4a6dbb1ceead6d40f1f0a9b71a9dc4c24f7437ebf53c88754fbfe1ed2e9616748d34062572f6f7f6fa2895021bc246de3a307cd89a4d6dcb3d9c149bd5536fabaa1cc3b94b08f6b0431f8733ff3a737e75a0b37c0bc96e671624f985fcde5960f56a2765e3b966c88b6b030d3feb9f8e475d41f024a8c2dea3b6b683010001	\\x5984a5c16548e6577d4f2257dc0c8b7eee95901ae5d6f8808e2aed93110f4f94c1be5e8a69221b0b3a3eb4e37b37c471698d8573bf362e2f8046122d39b5740b	1666336391000000	1666941191000000	1730013191000000	1824621191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
96	\\xdca8ed066c7f6bd2b3d3a88853ba33b523531ef40f40ad3cc66757e8a51d1c41714f2a336aa884d33d533adeddb4d590edf27e875513d7ef934d58a3ed19d8f8	1	0	\\x000000010000000000800003c8e97f80db404789ca9c5ad8942f3b8bf0a78680a2baa1da6962851a203bfa19373c50598689f9bcb986e8a95c4d23a99be5781f9d87cd7f6eeaf0eb47375d73b87cc6ece33e0a4853c55781d0b9c22651b9aa07afb39279548488d2aadcad0ce912b2bb8e6b904f21f4cbb016e9216a7a43f9fba392f563643c0ac91c0107a9010001	\\x28ac5bb21ff323d58f1124d186c79bfbcb9ebe69e79357c9a626b74c772f74a8642ab7d00842c888484f79d2a5dbbbd8c46b1492a00ab2b35334c62eb61dde01	1663918391000000	1664523191000000	1727595191000000	1822203191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
97	\\xde8ccb3c6042716a02f6ffd56db35caaf62a356dbf6574efd55db665da6d1d2e60638f99286a1c2267c96c8a811ad14d271312ccd6b1cf1011a66e38b274036d	1	0	\\x000000010000000000800003cc84aa03e942d77833347d8cba1173c4d7435e93c796e93f07c2ee4ca52524b460bd931b97b65d6ac93e44158c786884d48f92c3ea34240fad4f5c091f4d1d90cd9cb07dab777a05f4e5d662b84a3a7d9142547da1b5e341c0ed2de741b138af5913e2cac1c7c56c8012069f601cff7d3b0a1782dd72af245123d112ca21ddf3010001	\\xecb93b07d1ebf1c51501cb6988acd8a8d848b3a8b5073e3378fa133de69c3ae2c92dc7c3fd01169f68eed4d994f861176fba1a7c2e90099994f17da60bab660f	1672985891000000	1673590691000000	1736662691000000	1831270691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
98	\\xdf90fd218f754465a092beec8ec22cecfbac4cc71ea6f42cc6b278a834e76c036999f90c9c86983dcdaa7a1e20986f672d191a3a18fa04f29aaa628233582de3	1	0	\\x000000010000000000800003a18255ac018b5a4026d38f540e6efb363de82ef315c829f49e5855246537aeabeca001bb00632b1d2556692857f4e4f561d0f984f8483b10612d56223fc0c3611b6fa0fc1c21b43b0865ecd1cc019a45c5a9b6e6e137f019bdfa60e6c83dec36466c0281cdd725654f721941cfa00a24dacd98117da504247966a2c1f4cbb18d010001	\\x0d48e828c4f05d46b9a93a410672ed179b102b04fed0e0ef8173e9635168322279b74deebb732d238da817fdb5e4bd760636b3877d675a4541245f1f7dc3fd09	1657873391000000	1658478191000000	1721550191000000	1816158191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
99	\\xdfa8ecb8e23010a3095b167c2be1da1b9210bc6603e284681f41adec4594bf0703d1d6231715b0e986d238787a42db3678627e52b72dad1019d3127af3303877	1	0	\\x000000010000000000800003d0aee1b73ec85eaea0d35d85cf7b286981046fe9abb5d360068bfb871746697d790711f2939398575ec3e9303ede53cd5f667381e329911ade46cee8dd8f24567b1790bfc2b8aa87d93839e7bdc0298816f9c6ab9514edf2f3a813641391c49bd6675da129ea856f7863fb9e535e81fc809c0d93240d6dde8cee32c8f0ad2e31010001	\\x642ef91dc5c0d01a48863722d83dd86060da9f4fa95913dc256b3ad96c35300ddb3dbfa4ae79ee94dd3b9ec98b9ab7760731d56b2ea883da40862151eb7b040a	1676612891000000	1677217691000000	1740289691000000	1834897691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
100	\\xe0203e962cdb0b794d1df2873784163267c400e7feb3e47cd1a4fe98b505a1f6aab7078f9f91926764a59b77e53502f19292cb22aeb1c555c7245ed3a9b31462	1	0	\\x0000000100000000008000039659306f75d1956844e4d104011783ed3c30b22751fe0ba84cbb0edc81cb9f174e759b1943ca826b3072e11f5ce42137dbe5295ac9925d3abfedb89f967821601d1b1f8d399063714ddf4df5e2be9551435408b93389cff07a35c0700d05409511bf0a19b0a1eec3376595758771be4c5e24628d9ab2ab1a7399000a177afb71010001	\\xec85a4092ca4f05fb636b28c73a18635cf6f0348adf8831d217d842d6f7159b7af17a6cd439fe8c7c8fc3f57d0d9da12a74ccec978ce340b42d30850023f350f	1664522891000000	1665127691000000	1728199691000000	1822807691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
101	\\xe57c1bdaef1ed6af5d28392db3b966b4fc90c5bb1df645d156bfc7052b0accf6fa53684f639d9eb195c48ca2384c3acef7e3f78e1520432d19ee635ba7dbb43f	1	0	\\x000000010000000000800003af2c0f8862c834bd834e85192dbedcbe9474ee291a78e259d7e6e0c3b55b5d5cc733e3dffd6c30b041e206c68d1e19c755a895d70f37c464543f1b79d8b41ffa7703d453ddf29d9d0a83ea9e4eca3f1006b014db04217458d5a1b183a598b1e1e0bdd1a12ef6045199f6a44a163958739f62e1d82136533fc8fbd033555481d3010001	\\x90b46668c4f64b130dcff38cee3dcbafb05784c90705e2fce8ca5c5a5ffa51f5f51ee352ca5ac1ebeaef03a72ba50f7bc14f24e2972c3b7c723221aebea3fe09	1679635391000000	1680240191000000	1743312191000000	1837920191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
102	\\xeb68a0bc4d8c19046892dda3479940c6c493e4ffb4807b8a9965e6e03fa8b08e1de04ee61eda1a7539085834019affc5daed1ce52e25e667ba7c5c645468e7b3	1	0	\\x000000010000000000800003ce200bb33e546cff551fabedffb1d71ebe1c27fbbe460b5a443b4f9a087828fdcc3e0c58ff9aa0c43ec3460999581a0f9a14be9d35385f00e6acae10ec3f6a6fd55d1bbdffb04ad3004a4222f21246679fc1e20f43fbb0ea4f2ee2e416de4a776ca10f02087592bc88c480c7f293917e8decbfc62c786dd08431c2facbda4319010001	\\x4a4633999574f72188ad4ba7b36f906c748a363393e024681f5ccc1ad9f4b8bb68cf4dda59389608ba92fd7e633e9a73f9a20bd1572bb95a652d6a049f7d6601	1651223891000000	1651828691000000	1714900691000000	1809508691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
103	\\xedb0588a6d1838cd4a797e8a1407353f3755cf2b1d548bc03ae99746b313363ede2fd46fe3b66068333328445c76394c38866fddce7444b35567a6a073089faa	1	0	\\x000000010000000000800003dbcdc68ab2a2260547efff5e1a7ff5a5abf05c82be298a390917843da41dfcdf84eef41d9ea1703900b9607bc902d06cd3539c0a951f63a67d1a86aa254b3234179aa16482c92491bc49a476d8de6797a79b57624a36a808d1bb4e95cea35582b35443a5cad0afb6c70465a793d7f0a087d1b9bbbff5b83abed4ac289b23fe43010001	\\x455901508668806bda6160acd67ad756ad92bbb4c34a8e95ecbd78e027e5ad095dc3b867177c0b883f83d97392fb3b1a326f9759371f415427d020dbfc786402	1659686891000000	1660291691000000	1723363691000000	1817971691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
104	\\xee587a012e131975c30621f83fb9f9fa4f8d172bbbc9e3c46b4d918233224112c41bc0759857c1a3f2268285526096ebe1f4ceda2c8e32be32bc1da8de008de9	1	0	\\x000000010000000000800003bbc7e02cead891bc38bcd59316e7fea946507a6c3bd2cad2f8b01c979b8e0afe3c351cb65c8e93a9aa2446de7e8c4f51943021aca20e97e341fef90a6ae42c51fadf46da9a304c3f36a9938a88ed1d0ae863c3611fe8c1a9c7228cdb0bdddd2974ac229cba4f150b05b4b3c739b910712515757eb1e7c6d980734955379a1d09010001	\\x6ef2751527983b3b8ac456dddd741014c204c942697549dc52192aef87ea9572938357bc350b227bb861329c4b4d25d3648ccb41cce975e97e4ad5f74d763908	1653641891000000	1654246691000000	1717318691000000	1811926691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
105	\\xf0ac5f85045978a65664aa413104a59dff249d98fdf42904bd1b9abee072a727c7930362b325e5a81f01d166e207b1b328cf743d4f2af38eb1d3d6015e051a42	1	0	\\x000000010000000000800003e083d678662856160e15ec093b6466adccdd2bf4be37385fa40f1411a18471625a4fe5e5a96f3a57e2a88058f5129c580ef56934537c7035f2a3bab97beeb26d994cbcec4e3522cfd84697f9f30e514d7d4576fb5f1526c41c4e906ef29872ef801bf5f2e4868f0997fea040456dc004b47829453c635a531ccbd287a186fe53010001	\\x67749ab659f3d903b5b5cdb7701f4ccd34b5e0b18be3255d2f067fcbe207ae078c0cd6521b22e141858c5846e4df388bcf8b015cf3c0e88d9110a32009c03706	1659082391000000	1659687191000000	1722759191000000	1817367191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
106	\\xf2684987cb982bef848a9cda383cffb8cc40e24eb98ae010117f07cf94c262f3880e101687351131db2eb9f5baa784a849671c1d73512124da0c3a8a8366214f	1	0	\\x000000010000000000800003f0609e81a9e000f2473f89908411609ec5af433d5a567e11ba787587241e1d475c2dda2cb9c5fc254c7899a035ef1ec6ae94170100b2fd76bdb68004a0ccbed7540466088288e52c3f487ae32ddc77e90c1dbdf18cca9b2acf5636294efef759ef6801ad136c79a686531eada52cb5c80d591fc98a2667aaab22a8b9333c14bd010001	\\xff75ac2cae833e180b69f8d302fdc6a1e8e91353dbb4d52ef95f9b311162bddc7aff5b34e169fc46f96719880541755f4ec1751170a191ced6a6edcd6ca0e407	1668149891000000	1668754691000000	1731826691000000	1826434691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
107	\\xf614e84a8fd15dd664268e02036592f250e6c84039e2cceafd00b86a6c0c4ab0b75e9ae5a9c5e7b50933ebb047b5c3550bf31fd1ac9b846442c170244d757c41	1	0	\\x000000010000000000800003e3f2bcfc7e14ff19e50847e611f322fc6e229451a6f8ba19911d40cfbf11ee0b521dd3aec28eb6ee743bab57653f372b9537f7bce6ec992e78a1fb577fa54b3ec0e7918162201aea2ff6666b2d68a103aa02bb777bee3fecd0fcde5666dc6077da40c521ed0c01dbcf07bd36560e74e7346548c3a5424982a952cf8e0efdcab1010001	\\x1ffb25288f221de7526caa32a0a6c71e347182baf96fdcbc050b86118096e66bb7fcb02305e7a041de1e96e717e733e418743aa28c8422a592863b9a784ae604	1661500391000000	1662105191000000	1725177191000000	1819785191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
108	\\xf740109947ff3bd3ce1a975357f7ccf25e703fb797c96d09710164bf7b622e77e172c71a80eca5c40012f6c4a5b4c64fe1771fbd9e3741cd03d32b40fca15052	1	0	\\x000000010000000000800003b93fcc14279ca3a4ed5a6bdd8e3c18ab60eb7ad955589849b1c8899884c178106fece3e50f03f1d0d58c6f59e8c68bf22afd6a3e646e4c372ed5284ffce36e2b0c8745524256652a2f566c022c82c8b16484a10a03a92cf3ff6c7261ed5ac574151534f8704f6db6c3502939162f057778022937fdb53e0606fdabf6f2a67e69010001	\\x21a2630a76a5d404a5d77a45929ddabd25704191a9b555f9b2d1c598c993fa915b21110b1597829385f697d2c895fdcae557affb2751481338bca27471e8d80b	1660291391000000	1660896191000000	1723968191000000	1818576191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
109	\\xf8ccf3ced07859093f7a31c229f5d0e13e150192618d642112567f99ec9b9b7e38aae0afbcc311a2736af3f392f366014bcf661e461b403bc5fa969f664520e8	1	0	\\x000000010000000000800003a325a616ad8dc680a8392570195d9bdc9aa31d3d14a80a0819effbc050f9d3c5be61da4987c89b1d2be4512bbbb4dba5151857453d44a281f64c2f1b15a94034dbb957387cc3a8a6748a5500cc21100bd65d606b30a86962c0b8ff3af1f8a6140568c15c1f659edb1b326521242d482f9e55e739faab31c27f96f68e424414d7010001	\\xf0dcf11c79bc2c8b131f611e056d3d0b42ed3f41756d55852575b48ed2360ab68689b363b62caf0b9a590fba3276a1b2832756b147d1eefdf3a53d00e3f37d02	1676612891000000	1677217691000000	1740289691000000	1834897691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
110	\\xfa3c6d89d0157c73174cdddccccaec5e5fee062af84ff4577fd6701cc1e1d383d36329284729bf3505b0e183beaa168bf66a837835f92f283c88d4053d6653eb	1	0	\\x000000010000000000800003c1e5b5823f5b88ce4ee06320839013d84ed71f281d654db66a7361fe918422e630e4b9e8c39cf43ffbdbc2783b7d522b343a3e9bc1a590f06657dfb3ac6ac43387154ce6d843bbb407c578f324c3a062f5b2bb86411b5af81cdf2598e806cc91ea2b473f62534d9555cfe45378664a7c42ee84d9a10e4a225166bf5685ba183f010001	\\xd962497735e6d2c2673ac8caa486e3d82404372f4edc5b28a00b12b915d94096ab9e6a8ad85bbf79686eb88cc28a5740c1b7cf764b5e21065f89cb7407e39e01	1667545391000000	1668150191000000	1731222191000000	1825830191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
111	\\xfb2040f0eaa0b1713e2c838941938d197e7706c23588e4161dfc2db1684c7d3c1b30953e3c9aa9b5c39b435af7de5d98920eccb7ce9e0f7bc412f153cda6af15	1	0	\\x000000010000000000800003db988d7ebb03a7999944268098c0d41053df1623fda05913e265085f6abd449c70615406ddc6b767689b06d2a1d8e250c73846e8d25a7dd1b16e24e7976247d449f52db409f040b102f89a61ff87ccd1f52db6d9f748f8feb5767ca9f49fe55858c5124888222a3a170719565fb8c9ef0559090ed29554a8e4c9ae60d55404fd010001	\\x96ed466722dccdb2ec8f18dee7df110b44dff1dfcf8ea8936fbdbda6f6fb6be33d0a1d8c236afdfba8d0f6301c0533f64ae25a42f1ea44b84b14ffb22cb9cc0a	1657873391000000	1658478191000000	1721550191000000	1816158191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
112	\\xfd20073913fde22aa97b7ed56756d782508874bbaa3c3e992055306d2a97e7bc5222d4385e6bf2672b31852a31ecce58239ccba69a4fd7df402bc35592a48e11	1	0	\\x000000010000000000800003c3997cc390009e0ea85ef06cf59e6d6508066c5ae7c390bcac31380fe725e2c822e7761e0db061f51ebb32e6ae1f215ab34e7b761cbf44c51167537e5b81e52cc746f7281ad5f9287cbe5c944c33c12082c9369108dfa92c27abe5895b8c44a6b4113b89588ecc91e523a31aecc24441af8fa75deffde22c99f7e8efb62987f7010001	\\xc6d53fd6e0d629edccc6ed1048ed0abfa12757109c851221c986b2716f4b4f0e2e095721431f05ffde7cfd5f30b32a9100dd8cd5a72f5d212f97bfce0f78a504	1662709391000000	1663314191000000	1726386191000000	1820994191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
113	\\xfd90f49e7f14f3d829b7de5590395871413cf3a24279c7222b2102290f2229445b43bb0028a37843340c3baf05a90a75acad30c08ef81eea2743647ef38e7fe9	1	0	\\x000000010000000000800003b6acf95d6f04536d9f62e281d2efbecb7858481b0ac3f3108376814c75bc556e0991d91d57bee43baf4f7992678f7f1ad94fd6ca7dff8422ad74bb7ef07658b714b780d985d8dd797f4f06590d9758a3da3293df16c91617a8943eda6cec2ae47e838f5a8d98c68f2e751af23209fa93b3c804c2eadb89ed1c22d7f7bfe175f1010001	\\x7c4ef19d9ee1710217249e480e2082c323d574a540d84c4517a5657f45754598b9cbded7d30a9187f7ffce672d6a8df541934699538720cc595ff1ded91ca603	1663918391000000	1664523191000000	1727595191000000	1822203191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
114	\\xffcc52f9dda856b7f4a7f38c6d31db80d1dda21e91d2cd3b40fcb89dc5094c70084670b62ca4ee79a3ff68ea9efb0127a17d35c6a6324e0091f58519ca81fa8f	1	0	\\x000000010000000000800003ec61a01989860e2bf0bf83f7043dbe445dac109673887768ad9cd8ec9258c58020e1a421f413784347aaa5455025b668676e6e09db6f6e7d377a9cae2cf5faa34e8a143356839e707cf5fbaee1d6fa5dcb2297740266648f097cbbd6fdb9b3158d9744926a57202401b7675e50ba65258dcceab12f2f62f18ee54abe7f5c552b010001	\\xbbb5b02addd03f79594b80496eeb3ac7ce897520f126faef649fdd7b2f596bbbee60c98c2c878ed91beba19430db4be1919c8f893b354fae746235a400ca820c	1658477891000000	1659082691000000	1722154691000000	1816762691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
115	\\xfffc0f640c96971561e47b0625dbe26f5d732aa569e63f0a21391751da2f6aaaa620f563ed9d8d82ddc755fe283553ad651104c1e4f58fa1a738e1e0036fa290	1	0	\\x000000010000000000800003dd1073ca376201d22abee54b9cbb567d4c5b1d3ce6e483c2d4982d16384d24ca8936d69d5fb9b29d645f1285f82f6b03597549fa452b9a4ff50eabae132871f6d96b14866ac5fbc34cc3df4cd3b48d4f7021415e2ef5cfd2e02ef24d15b3f6e688cafd6e6eb2c2c108fb305d3f4506b21de6610cd3cb2cc25504af46021347a7010001	\\x2258df5f918a0590fad213781d71b73825ecaca6439598beddff7efef845536498e72a890ae7bf1803237a6238e1abe83edef4687f3701b4d7c617d9a433690b	1656664391000000	1657269191000000	1720341191000000	1814949191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
116	\\x0095dd95fc2a72cf749c6e49b3cab5e9d29bc2d3b749ca0ee096f064ec7b79e615b604cb6978723dda8f2e93ca75ace7e6686ca2f3537a3c255bb99eac04f4b7	1	0	\\x0000000100000000008000039745c75dc0d28d81cb499c408f36c44430b5cc8eabd52bea07a86c610c78d2f1b4d048830aaa9ebd905b485a463b682bd01aa23d923cc4e9c1156c458952e7790cc0cfff3bb349ced25d70b93e4fec8042b55a87d3ed040f3e599875bcd311d71cb6d4803841c07f9b15825d2f65e7fc05ab10272f95cb56cd486c4dd31c35ff010001	\\x5aa6528f7d1ccb77acfccfa9323b727942d5dd3444bb307f32c5b23d808fd58e2c292df61e5e4e6ddd9d9c3ce707d60648b73c57eea353d334bea2d9cd7c5b08	1654850891000000	1655455691000000	1718527691000000	1813135691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
117	\\x00657bb0144c6940da5bc47f804219fbecabf61aec09dc6d97bf3ec3890f3b657bc4a879ea3ec3f8e84befdbc56031dd49c8284eacc0d96886a5b6adb18ada24	1	0	\\x000000010000000000800003cad78a6117d485545c654f988ecd08228658abfe5a406e99b17e47dce2da03d3de7e6b24c71637d97f1a38a41f04940963abfc864815a102356fc5be5984ae7dbbe85baec5541f9bf5516815f198425db32260fb2bfb8b4d4f74d191104998abc55675df26bc55e744b346b97d2c4632b957c83df0f7547b2735a7d753bb3601010001	\\xea948f2cf99e6d96d7e6f854c1bb2636d6eba757da1466d919790c98cc74f2668050eeb2f4243d409e27b4f003d1ab1ad88443911d04924a4ccc7e066984200e	1672985891000000	1673590691000000	1736662691000000	1831270691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
118	\\x01a1dc034b0be4af8b4c20ae7460dd527af5bef2b0fe2df9628ddb3a6217d444b4482b55a8e83577432428d5725d8ba14656567fd8bdb98705aaa6720fdb0d21	1	0	\\x000000010000000000800003a165dff1fc2f4124353a86b79a6bb68fd410243927939e3d32d79df9381ddf897f581be1d12c0af913ee650bc3c39687ded903a7103f8a5b40cc4be7adc749af1dc8fcfc72ea76a76f410114ac0e9967aa69a2d50e58648d1d834278cc58e9f19a0fcb0b39a9783457ae411a48315b2805fe589df7c485de09461d1b083adb8b010001	\\x99c6296df73ae021abc1a8da99c1157c11c02eaa15071133e5f287aa881f65eeed562b9e6e4e53a1be0f410439ef4448809472131011b3cd73c3683723918407	1656059891000000	1656664691000000	1719736691000000	1814344691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
119	\\x01f51b72b0eee0dd15dbdb46d66b915142f04112c5c6f56a58c7d44334a8289ad1f060da2a88355e6e1d6616305a8b69a7a850ac9c26332d39012daeedd2b6e9	1	0	\\x000000010000000000800003d9db350132343345d2fd32188e6448e00263782fdc04aa14a48d1dbf22dce14af9fd1485340a0408af488585d9a17b82705a7ca5d946609623d88b150921d674052cc2789a31505e32e998f718c0e7b67e5a3329861daa57f023d27f92b50faf7d7fbbfe2c94571935462cedc2b150a651049008fbbd3c280e1d474c80d3bf9f010001	\\xeea68f160219bfe8a7b316a2ab32d456cedb67af875b9fca64cb5f3cc78facd6d293236ac6d8471097fcc5d236663c78a7e3c3b0aebc787c46664fce59d75b0e	1660895891000000	1661500691000000	1724572691000000	1819180691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
120	\\x03d9677a8a90796d1fb8ea4f462fbd97b804aa9878c3a3076a0fff7218db86625ff8fd0828cf329b232d975e292edec3e04b1f0c53453c1df1855c9ef2b73ff8	1	0	\\x000000010000000000800003a6f644adbe9b0c52825347aa668a6e20fa050988802ebdfab8eaba824b1a91072eda90bc3fe1bf5aec6320fbab0a2f47fd28def6da8a4ad89739cea3890c0fbdaef8c9fdb1d369fbe50b36d7df87f100ba4587d61e6a44e415a4f39f63eaa78c4d3c8c25dbef5a7ee27d66229ee89ace95dd505c2212ee0273215e901f77e5fb010001	\\x4dcc1e4a4dc5af4fb479bf23dd8fc26c9b75b24c764b110cd3bd5b08153716dda075148e61958ea046806354bb544c892c4ac26a7d81d822a7b2509a90ab2808	1676008391000000	1676613191000000	1739685191000000	1834293191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
121	\\x09f138299672f7650db1ba2e6197921d400c5df7c1a8720473208d2d6e7936b84ce691e22990c2af1c498bc6face3246c795569b7505d89063d1c1a38a5153e7	1	0	\\x000000010000000000800003b88a8dd82c3edc619dd72dbdbbfb4ddfc6ca3f562a2a43b1cf89bd35bd7b0c92e607cdda53919045bd5cae9c6e8f342407dbbafbd8e844ff784cab6af15705ffa7815b9640cad7d6c260a2a391aebbaa312bf8322fcbcd848147c6f52e7a0d2cf7ca08973457fdaf5f9778994c66eed3711fa9a4f733980d24cd7ca78f827271010001	\\xa378dc95f3627188310c06d4dc85fe1c0dbdd5de2ea964d6ce4856d4d4311da0b0c714aa31e2a01b49e0cc962fb1380d4c2ec86faa8fb3012013bd2e861fec05	1654246391000000	1654851191000000	1717923191000000	1812531191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
122	\\x0a95fbd18285686b3ba9f4aa6d46f08667b53e05e2b65c58d60b04736ec977de0bf8efafb7a8c834fb7f3487fea3e5a1c4b503fa7e60d502ecfb9e3af77866fc	1	0	\\x000000010000000000800003cd090be5ab58eec1dbfccc700d5c14fcec6499f900dbf406b4ffd7fbe2257be5d65c43f0a64a86f857e49b3878b8a8f8c2e2e8a50612aa55f01483652d156ef645fa21cb91d7924d5b38771b50db078bcb254a6b82cd4069978291afcc36da68d19014469141f48ed8e3fbc0ae165d2dc8ed52109f6f7bf5b95003f76b4a41bf010001	\\x8bf4fb02c1941e62d4a90732eb259a61e1983ea026e88bbd114cf7402c15ff902e7c3c07bbf0a5f1661be7c85fa198bd91ea596f3facc5d59220cd9bda9e1107	1663313891000000	1663918691000000	1726990691000000	1821598691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
123	\\x0ccddc4872cf9fca61ae921e6ce63a229f0d96ec91f37e07d07f7c53a670b5c670c2489df91dac4e921e6836fdc3cf50495d90c9d653ccf618d88d08f5497189	1	0	\\x000000010000000000800003e9c69f73af6a099f0ab96a5494121cea5481e20d028e3e9c375762da431043dbc7750f4c622e927f48d493ba97ce7cc300834b85e8189bd3fad7aa25a83599e92366dca4b1805002c6def6c08d1686d7b6b3628ce430ec0003be7008e4be3cae17c3698a3d880c7f5a2e7c0a8b0a55415cec06ab5b89d141abf72fb6a39bbd7f010001	\\xfcb3ffd8af9c16c1165f39c92f72351d68a2631963a073efe82c12236a3c48088285fc2b5da9ff3b979c9456402c07684fcb9ba120407581e0962b0d79cfc705	1666940891000000	1667545691000000	1730617691000000	1825225691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
124	\\x0c4df134d15d7ce92df7d1c1d017a4804aa479c1a1db78590a2bc062566577b2ec336c1eda0afcd684e1c63d5d6c5cb541cad077a78b114ff5edeb447b1c6168	1	0	\\x000000010000000000800003d2473f6aef00c1a75782fa96a47fdb19c32e8dcf492d578bf73d2e22cd73b8dc8b873270b8c6975b2e0c7698ee19da6c1111aa5529c58449befe529a43541f0bf14c4847ef260dc4d019726c4a09d36bd38a6207d25d59ee61de28dbcd95e099dd0b0c302f424ded28acfb9974002cd8ce1567da4f9edbdb102035c6068e3131010001	\\xedf1817878230ba84145d7c16ddaabe51d15e343d7616c9eb70064740ef53204423651c2f9d3d8de935856cdceda0b391e606155e30f48e152227dee53e72200	1657268891000000	1657873691000000	1720945691000000	1815553691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
125	\\x1091c08dad255fe493fa13605b9ad6340f67f1878e50239d4384107df357f0735fdbceb1ed01a9657856363c61a53539e179087ba604e974e92741dc3275c596	1	0	\\x000000010000000000800003e3545f2be1b4601a7c1dfe7a30145788bdd00de0c1c8fb7f843ca9e5c7324368dd504c5741120e059dd8bce83cbbc486ac2393b7a912655f0c287a872bddf2716ea83eb1b1597bc053640c6404c06b5c6dbc289267f91d784e7007d7c5a51fcdb77443c153f6844c7e32c6aa4ff84384c872fbb1138f7704b36898745c906efb010001	\\x9e1e7563f276302489a9aaecbf02cf8d7be3e8705aff52446c0ae113efca76bc367a6fcbafa70bd8c3b7635eb7a4842111c9575e57379031253eae0b66bdb608	1680844391000000	1681449191000000	1744521191000000	1839129191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
126	\\x13e56d5d7dfb16208a701158f6e6bc4a114cf4679b95e5da977b463e73955570f8aae0b0195c3a4feccf9b383e636c3da578ed7662f0ccebcb6d4fcd5aadba72	1	0	\\x000000010000000000800003a7be632d187a20a1230419ab00b074d4b04ee42885da9f01155044aafe6a759a9ee14376edeb3224b47137dd41c9f28526019173489f0ed1ca312fd1d6435b33fa8a2302c480b916428db88545548311a641998a34116315bc5b5be22240485a5bb7da3d5798736b1e50b1d0974b247883e3b5745a3edb55d60e214e6e44186b010001	\\x2402fb1d5c56de7c6258862e8d413aecb01eee79d7fddc54155bcfcf01d3e3f9103e4281bb77396ea1dbfe101dbc665a0130df429eeb1f16da7f88a52274490c	1676612891000000	1677217691000000	1740289691000000	1834897691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
127	\\x16d55e5a3fd0e524dee0cd559482990475d6ee441277dfd517d88219e7694873e7eeb5eb8d73ea451eca6f033642e5c153ca3eb138464aef0c84fadee0c117bc	1	0	\\x000000010000000000800003ad728c9da1a32d546c15185a5153b49e3a674116f79f8a354921dbe8640394dcc137fc9d8051f42d27e8b7addc55b83b88aed721aee3f2d31203e094fa5d7e0da6564e88e758a00803e43c7ae3b046c7e8549e02fce0d05277c493a9a00523fa67c7da169a1841f36a72399f69079ac198736b79ce95b2062d78399edf6d1bef010001	\\xcc4e069cc846dd0b61c719e97284417f3f29741c01e31b0008e597674437d9651db7082326c58a255e2bf6f97599289d7104c16814217e58a511553f94638a0a	1662104891000000	1662709691000000	1725781691000000	1820389691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
128	\\x1729c0c63f09587a4e2b23422d4307180f5333bd078e40442f31dbe1ac15683a402faa09e48c75cf7858d57eea3bb3b322021b12d7ef741af09f42bb2a452ffc	1	0	\\x00000001000000000080000393c727843fc7504044ed55bab1ed513d57c75f978c387d01d69c804d32b9449d1eea2613d13c86c24a7edf9f3a9159267afd814052aef44232660db45922271d3efed3578234239acf03248d654c147834ed4182930434c955b309db922ecf6a1feb07537d71d0bd90cce8c2c4552aaf5cda0949764bb1b70877cf6741293101010001	\\xb8eea39ffa8a8f8b19dc733a257a2789f36c13f4afb9609435c57288829ce7b652838df8796bb96f276d0ac2adec0ce6df5b76d885b9fb13fcd06a027464680c	1671172391000000	1671777191000000	1734849191000000	1829457191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
129	\\x1c4db68bd8836ae9116e219da32c9c6754f186c6324c3c92def6299d8181f3de5902331784f01ea7c9958f414ba376d76b0f9bbdb73d793968cf54784e0ff763	1	0	\\x000000010000000000800003c82dc4863198e1b1ff8074b60945e24d82ca4650d32078d8e8a0360bdd5a1e0405bfe84ecf81a52a6922ae003f604acceac5d7c579191414e48b90e9d0a27332f648ea1e42c50686948a72a495448f4e2de4274e2ffaa3506eaab8c0db9cdcf4b10c0b04801f861ea080f9ae8e53407eda5c6786275974d095b97a4a65896a47010001	\\x65f0f3040a4b8fed62d170207134ce1960c27ccfceaeb95756cb4683f9c8503587097bdaa2f713937780dd3b67d45b9d495206176357947d78f266f03865f902	1674194891000000	1674799691000000	1737871691000000	1832479691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
130	\\x20316adbb88bf170d686c7bd8f0977047483500e354910237f59fdbce84ff6e9a1f80a9a278eb99a30bb4af391770413a052729e3e28e814add5c9033d284b0c	1	0	\\x000000010000000000800003cd8d661747c71a7e2cfca448b8a41f71757ab7a34d59fb04440f041aeec9318a6434ed4b1331466f4321618792ea9e838275864e98cf2271730fc262a5886f3ac249ad7fc63bf544cc9804628c6f66115c6824e6eb972e02e2b0637438c3cab510ef260021e97005d2322269feafa67531d8bf9d62015ccd9bdd7718f3c185eb010001	\\xdb3bcd1b45b283c15c3fdee179790e046c12c56dbfb0cb81756715296d3d23bd9a0e5b07216076fac88f728684dc571aea7c109305415cacc21453d09bdc0a0f	1669963391000000	1670568191000000	1733640191000000	1828248191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
131	\\x2101b2d5f566dd36188864dd8e127b3ed9403d6a02d36e612f1bfdc6f3308970763ef66d70b9239937780f180f1f83746f87a2cbc12f41e95f80c790485829bb	1	0	\\x000000010000000000800003acf6d424e36a443d60e8addcc0eedcfbaacd496936a826894376447f66f4ad68d3c37ab441bee35375917b94f9ddbeb778a45e37d2c8a5bf1aeb41fbbaabb8ad1009ba383116ce58c8fe39c46f03e6dbc47de5e9aa26dcca11f4cd82023f2dcb66dd27a895c234b654d9a5994f631f2ad95486c10302cefdb2a4ccd0afc213af010001	\\x7dcf82aa307b9106bc399610bdf85ee9fc933d411a9400a165dae6e0b7b70cdd435065a493a3e3898588e82cbf7fb6d60457dcce3786e3a9f3d19309eb9cf408	1679030891000000	1679635691000000	1742707691000000	1837315691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
132	\\x2291710856b23163141c343db0a1dd2ca6cf0c327e95d8177cd5c6f650950da00d8563ba8971641a933101e422891f821b0d00f39889620849e77a037a9f246f	1	0	\\x000000010000000000800003c1fc24b0a03b6d7861e40f3a5e7bc74c4fa0221feda8c3ce47d7e71e77a34af0364644acd3f94c2ef572d2d4a98c48daa67fd8e73e3bbd077257a06b23d373e2eaac976d3b87cde7b8862bb9ccdaa8c5b88b6eb59d589cc03efcfb470e7242a30bc39812a77b7e00aaa188fcafcc0d01c00a2396011f5b5e7ec948a19fa0f5a5010001	\\x5957fca2dcbd5c24bedc95c818518eb3e4b369c3d5195b847e46b9464b0f66e408b3fe74f2954af738516f06758f10e70418aeea7c558a979b6953dcb1118009	1677217391000000	1677822191000000	1740894191000000	1835502191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
133	\\x258960d97e318e15a90d86631a9035aeab6f2a95009688ba1fcae9185e803b6efe9525823e055e9f16b61b32647c14d40ce5cd266c2a2c025b6d9b9ae62e5d8c	1	0	\\x000000010000000000800003b37b0769fe5cf02faf79659d100956daa19846151b3c5c09eeea455e3795c948784a219656c933b8cc24adf0629d5259b8246a1941fa62ccea0a14092f0c312ab6ccfac9391b14176a0a98cd480114edeeac28e0435e4d7f586570e8d3ef300f1e30bd7e5aafcd505a96272c173fbdccc981d8b8735919cd6accdba1fbc88f4f010001	\\xf9f19eb54f76a1f29aeca292a5413cf3139dad992188f662c12b150ad1187e0da7ceed6422983bf9e351e2c3be16b4893ea199a8612e40e2670f5803ec0d4b04	1656059891000000	1656664691000000	1719736691000000	1814344691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
134	\\x29d97f2ac9f2929d63bdac4db42b82b349a7b996cbc348eb74d81bdd55f87bbea694ab675ca339a44991b3477a7f47cba15de4bf65bcb648f40096a3af851bae	1	0	\\x000000010000000000800003deda0765b16ed80a2770a202910ac51af70aad68baa5277c1e9cdf1d10c56dad2f2e18101ba3b0b87e1ea08591699af3682eef6cef4461a325e4058038dfb56cca7fe7e057a7e22ac8278f8f94bee1c99bf7d6d90b2506703e3f77ad56b0cc7fb6dbf7cd2235b928ae89f4ce96e5b4524c4d45a5759ee51b82308ad3d90c827f010001	\\x5ac4fb8b81877d8e9d20acea75d2086100014100f55cc64e6108d0901d3fe345370abbd0ae3f4964450b5b0e5c70b8d56896e1a7a33c04a8befbffe7e4bd1202	1679030891000000	1679635691000000	1742707691000000	1837315691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
135	\\x2c85f9dae6cfa14701d2b91c1b0727bde5ec4c46af95b9206b66357fd9a8eb57b326c3bb9115438934ec2cdbf0a1f058e8bb660759db4633ad021663dd317050	1	0	\\x000000010000000000800003c1931a58e65d1956999b4687e840034bde91ae1bf7c9477ac9d769f9cb93e3831371ac871292a0f8c43bc1c700d64e9d71a55914144183f99d74db1e40c05063af5a0fbc1876beb997846ed485c1ea9da813d9229f1fd882958341d1c630f43ef5456c79099b9829cceb2bd27c5fab286fb45bb48e434472c630cf8d42bcb4f1010001	\\xb4ada5c993361251a32b4323cb18f5743a2f1216bc89d06bf6e620cc83d17ec8ab2dcb9eb56770f49b5acb5cb4f895fbe698d2c7c75b587decf4c4493d366b00	1659082391000000	1659687191000000	1722759191000000	1817367191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
136	\\x2db175d42c84c6f2793fe1eeded0f7df6a5ca52883e53e00c1fe399bdbd0eb2ac89ced69eb3128ea82bc3c0f02508dea29d270f463665c83be9493235860eba6	1	0	\\x000000010000000000800003ba48bac7a3cf07e4db0f1d41e2236a13baac0e136085abb5378df32fb36aa1df59357150966e4228ca40a55b9b156ac7360132fb89e3e02c62b5606792097eca30f74dfccb8766f8dc80830565ef50d3f77a27895122646c5c89d6d86818b952a26f7d229df4417fe2d541e16a202f7c8a2ecefe56aa2f541b11cd047fb00ef9010001	\\xb50f3a7ef124682375e427bd00b755630e525df2f85b53a88d9e4acdb6555b156f4786c84dfaebbcbb08be928187e101ded8fca7365aca7f68c74aec67ad1f0d	1658477891000000	1659082691000000	1722154691000000	1816762691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
137	\\x2f9d602b64e4812e0a3eb09edc895e0669128643b638fb2f329ca1c07c66b87f15736a2deb312647a4719b3d9cf4a66b0c80aa8c174ce94530613d6de398f69b	1	0	\\x000000010000000000800003b5eacfb180906956fa3e40f3ce8d94fcac9b541cf8206425e54bd03ed45593aefe8023fd0da9efc65f68f2bcaacf60d8adc1af198e561f94d6f546027a7dc7fd560dd375bc784303d217ff2616c8758d97b29d53b88683d9bbcef84aab93b6aa39aed7bd11a4828523e9a12569876d1498fc56a75b28bc29d12584e0cecd1451010001	\\x2a5388f044830aa08ea9304e8cd4d98fb9b4688048518cbeaa8bdf7d4af76b9f4997ab273a56e7baa5225a4e994aeedc8bb2df765453487e1576c48c10c5e00d	1670567891000000	1671172691000000	1734244691000000	1828852691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
138	\\x30850370c801d01bf02b7e53f0a15476c4cff13582b170a75a914ef91bc158061e416bcc54915c2533a2fa4f1f9c9d672bb6d03d915a0d92e2b0e7f8d4186422	1	0	\\x000000010000000000800003c26af9b083b097358fd4ea28a874890f43ef73624c1d721b8da85731525a13aefd6eee964a9cf6f6296ba9b80d1bee54496eaf3853a6c9ab3b920978c7fd74431508cecad149430b983d60d9347e7f010a32486fea9aed3bfa5da4e939e9d3f5d22559e4788513cf6836c8bf6753fef07c512b7d884e915d040c6d2998ea9d0f010001	\\x52f9e5823b8bbc6b04b4f024fcc11365537c4d44e4651dafe0e28bf7b8345ebe608d4aa71285beb3bb2ebd77dd775eb1b4e9b37aa38167a4330b255e7247aa07	1665127391000000	1665732191000000	1728804191000000	1823412191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
139	\\x3059709d5d80c507c331b8eae470e58181884b1c4e74f44c23234ad77b9c456169adee4d3d0b1c165784f5d928b4877b810e1db75e9e4dced8023f16664450bb	1	0	\\x000000010000000000800003b596700b4c2c5243cac39fbb74ce96983a2ab87aa918202144e87c3ba36eb0c0f31129421b55a447da09e6bc5a7f911fa6e9862514a11277ac30701c9f1a06cc3ce95f9b6d8ea97d2a1c3e644b498855c61aca8e7c2e0aec2e40d2c3cc7feb50a7d45a2a55eba13e5deab486393a17a5e4f2b4d2334bdf74ef9b2eb3fa791925010001	\\x668e4b2673760c17244f1a61f333c2dbe9980f74685950f15701989a6c69a4252a4a6fe4b993db33c6cb06671623b5ca052453da3adba02774d71d34691bda0b	1650014891000000	1650619691000000	1713691691000000	1808299691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
140	\\x398d973fd9c8d69d4918dcd5de166766b0b87de1374413960a9ff97df56119ec6ee042f8924a99f35cc680bc173a70fda1bd6b1905e7977452954eba14babd03	1	0	\\x000000010000000000800003c5843a6fb7aa9b115adba65986ece697168f1ee9d36582f904f5c42279b64a56302da2afd88cfc8f383d1a597ffafed571a0bd09c5156e52c4f48bcf1233fa948b33e34cab31aa302bb6f88ad6d537417f3ee50cea5f093e81c6b4987791ddd58b313d3f3dcf198f6347180f545c5cbfe38aaf6b55431aa02e9b4d5d362e1847010001	\\x458c9918a88fb6ca33df07625f19ec94b2c469460bf208ebd99fbcc5d6e46c3da8a50168bd5e2351a833504582c40a8655eeeb635e38acf73d54fab862a34809	1650014891000000	1650619691000000	1713691691000000	1808299691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
141	\\x40d5205a1cb4385d2a7d4acd6df3d826e78e41f8e590962f01614b785c09eb4c322696bd8ddb4edc8f918df438a1c76e25b2c7af1e14ab0b73ee8a1266de6054	1	0	\\x000000010000000000800003af446ba7b61297fda8e5a2d343fda03c596d6c86a3435c5d2b5b2b2d74ad859d115938b84129c4247345fad457349f83384e8f9fba4fedd1f72b17e8d04c7855c68dd983a87b6cca6d9806cc2cd241f60b823946d6a299d7be7e9f15143679460071ede4db582c7f9f854eb45beb6693cebf5ebd2711a7914d9b6c881c3acfb3010001	\\x4e077cb45bb92f809db0bf4b248d191a8b74610d7f228964aab6abe4d9d8b4770da42b5e4b2622c10525510e891da4b76551e428e6fdc3ee6a33d93e11242007	1681448891000000	1682053691000000	1745125691000000	1839733691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
142	\\x42f5b42dbde99649e9e256c73cc9ffcd28418b624f97be640fbe1c39103612e3f52f7dc14b3e1449e32b6a97971cba672d38645050cdedc07f6676b7265282cb	1	0	\\x000000010000000000800003c4af08ab758c07be1d8dc3856e003ce87ddbb83d2a9f8d7acb8505deb5477ca97ea9840f785ed74ed9b997396d791d0b184ff7a80a139d32935eaec4fbdabed86c83af35da8c704b548016f8a5cdae7f168c0e4ff65c3340dc9ff3c84f2e183224e3fe09f535acc41828317a62dcd7a215cbf8c70d81e27039f2c827a9641fd5010001	\\x7f52671b8a9335103bfee5859ec9d94da6fc4446e1be1a47ed4facdcb2691db603d23c42d7cdfaf528fcf1bf2b02f5a70cedb2afe9c86cdcc3e1ee796c2c9c00	1659082391000000	1659687191000000	1722759191000000	1817367191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
143	\\x43692987dfc8a63ab596d4eb3f2a76072f366bedea4c26d9bea6924b0d08aca5fe0dfef26bc9870b4b8c67282c55bdaf70581153ee81d440d0a90ae95aa4d7ab	1	0	\\x000000010000000000800003b310e0e7e3d2c795882fb30314017a82c197eeb27004c48dcd14e9ef3895f5ebeecc2accb9dd692a81b5b00461f9971dd072221e508047345cb871242b30ab18df6a54e249226d83dbf2fcf676ebe8f2428ec8c86eb06b9cd113b19996458714f1f5ac76cbcd05f4e52bd412515c0a0bf8f5d28c2d53c11da2567f05b37c6719010001	\\x93c77dd0e6c56a242ffac4a3c94a41427f3a9f6058b9e94bd4b283662743bb3a9ca2a457cb6b36d8bf53dff707ae7bc5371b57ce3821c26093039bf0bb08a30a	1664522891000000	1665127691000000	1728199691000000	1822807691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
144	\\x447d65c22eba0e59f915063adeec0c87e5a546adafaf9a6cf0de42545bf300aacf74c3942a2e533725be0cc22257504244dd30472756b81107e1a31573d04abc	1	0	\\x000000010000000000800003be55dd5eba69f667e9d6a5629b09c10a023bfb74caac7df44dc084a1e7512a3f0f559f402a6797ab0dd6ad9ce995b66fc56821b468b999c968959044b721991f0f819e218003f88f94e03e0eb57947b21789ea915e590f6fb7eddd93bdca30a43a36f327893ffcfc03c678b5444feea395c4e989c32f760d4588cd9145a278b3010001	\\xa01ab2768a1a8a841521ee9cb2352785c6502e8055c947f32a670ebeb8b7f2c253868030ad85f8cd807f6b2410f644fe1c81434d92cc1f36775355a006e12507	1650619391000000	1651224191000000	1714296191000000	1808904191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
145	\\x46b9a1e9e6f7431c9dd03477ed46b3d64c4a7d72d81b5589b8c943bd0ab08178d844274885c1a1d7c6ad521cd84fd89a5dad484aa5fab6fbb98522154b4e1341	1	0	\\x000000010000000000800003ccacc9c3124f09f427ddb8fd2032500ef270c40e5fed2a35bb87117e5ba54eac916712929ac94f4ff81f6f4778b5664423555f5239d45ec190b3672abd7fb6bfeed893cfd0ba68a24856d052d1c537fef9c6ce93c399c6e2fd99a857edfefbe01c3be6155f7f05c677279b08dc999492450bda61eb7a1b51638d194052072081010001	\\xe947fca012a14454508b6d701247d4617ea9749acf354ac80d89ca3b6d6a9e2bd7c182acf82b53c4a097fdf618850a0c035d2676816b53fae738c3c2de385403	1652432891000000	1653037691000000	1716109691000000	1810717691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
146	\\x46b5dc6b305786d8a9753df7d0cd65ef252525e702f6df74fd9f9d585a683be05e91d50cff0e0391298e833877c704f520161d19a1f1d0f2f57de341f3b3b100	1	0	\\x000000010000000000800003dacabe0ea172ce32a3066c3bcf9bab63270f3850ba78631a634e3d8b8bb1256cf18f63ba5c4610a7d5c9e0094dfa4649f5171b09b16675f43c3f61c758334d94abe9cf0bef081ef9bb8da2fa6ce8097097bfd388e7a971962275279af83d3b8a298f7f239f842bb193e2458f6bae882cf7abc79efa9ad78ac579eebd50a879e5010001	\\x75cb032edd09063fb4d34dfaa434546f8d9e87170ed01468e979a6d103de168c217ef22bee1af956d717be5fd47b200963995260538f064add5963067f50f70d	1675403891000000	1676008691000000	1739080691000000	1833688691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
147	\\x48792223393601e09352328c448630dff24779b69b10d4d1de24357daa6103519ec1528a38e46d644d6d296e952b4ee8483c95a3b655a65d5dc0c015138ce4e6	1	0	\\x000000010000000000800003e6fd209f0dd1ab0f3ad5bc2d70481bf6d59da2f6e47e60088f0d0baae2c5f0eedf0fd354e9bfe0594f84c039923b949dc6cace7a9ca4191b3f473005bc4866d073b39223f1f6bad27deefeb10a569e1edd676b4ff46bed951262236a74393d47904661f0e6fc81237dccad38fda4fc197672e43e9ead685450275f3f6f5311c7010001	\\xa5d8d04704237413d35e739727123fd0cd25bd16ba3593725ab496879f880d14adf3d1cbfd143930a5b1cba93e9ac53b6d803e8f5e8af312392553c90a05a20c	1662709391000000	1663314191000000	1726386191000000	1820994191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
148	\\x4a8570c34f2aaca3810fac13920402daa37e30f16640569596ab76a89e5202403d4f70fd5aa92662350c27496b5a001df1ade0c490085bc3cea534f7e1fd584a	1	0	\\x000000010000000000800003b652160127dbf234c57bc8f900341f09cfc187378ed0943f6fc5282505d137fadefe77d8e5c0f33c71905ada4b93905de9ac8e96dbdaeaeeb0112b45a01102bce1460fc31a658729e564f015d99ee9989aa0e60336604882356c199395db86344350281dc1ce1d3e0ff10fb94264d7f8c6e8734050cf58d177576a5895d93c8f010001	\\x37fdc72f2e4ae741114afa7e753341e146d4138c5c3906c06031f7cc6500ad57022121b4d9e378cd7a29b248199875eb347219a8ee0d17175d8bae8fd405dd0c	1669358891000000	1669963691000000	1733035691000000	1827643691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
149	\\x4bb123924c5a06e4d9ea784f989cdcec112e55a8bbe0b0867c960d5df8f2fb73d09d9404c7e9d4dfdc492fa580e96116ed5e03b3cd0cc8854c4ed50ffd422f0c	1	0	\\x000000010000000000800003ba8e264b84c9f8ff9d4c697f06ceedeba8f95874d89ba71ac9e7349352e38ec0608dd75efe0e99f577c7414699ed60a242011ce5316ce99180d4f9e6f39e5ff8a634723628cfab7ab0d52a028a767a85915dce26ee89035243e65a004e210d9f3251f270be6e4395966bbdbf6006afc62bd7daaab83e743e16ac7e976fbcd361010001	\\xc63398fffd660239864f7d60832bc1e3fa331bbf508212e401476ba365fc3cdda2d6272c0e8ae0f9cfce891e6a1e7a8bbb3f2539b3ed47cc50e12b65d239860d	1662104891000000	1662709691000000	1725781691000000	1820389691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
150	\\x4d91f554a8a69ede16dcf46127d2ffe9400729b053d6f44f090572f0bc68a08b46837551a421db65b22e5e8f6985cee631fedb368fc2c96f7f063b4167b48a97	1	0	\\x000000010000000000800003bacec7077cdda5e24eea1e5409ce5cc5e73c93c47b752c21afa69d421088a5e37ad7f9ecaff6e48c458cfd5320a95d8d72a0ea55c198903104b1016bfb2a5f7944fd5751cade21176ad9d11ed1eedec8fe7e4fa61ea7e0219b61258086a877e418b6836201c025639e52f4740b7c89fc7cfa24bb9be8f61ca5e0bba304820a1d010001	\\xd1e99ebe45cc17ecf549261bfd0194dbbf7b59a63d59968fbf6962554a4954a2b5bb37a50a3da434de885dc39e559ffa4a44c5af54b950db9e24d72060aa530d	1657873391000000	1658478191000000	1721550191000000	1816158191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
151	\\x4f8d123b36ee531646c6a678d43b624e3c2ad025ca3f870540edd55b8c081e22d0ed03dde6f3bdeea82888d28634814b3f0d8de809a9193d2a6939ae98d1640a	1	0	\\x000000010000000000800003a389d43053774a3281056a5b607ebd99febdd7e6f4411979b61bd70dbaa35f57e2edb002113744d5630b26013f560a3d10de80eb265609346d07c9cf71d816987fd31c4d21329a905d02cf5f39694bd33760d2898df8906d767007f85c9647c7f5f579b5f653ac43e7a5c722922ae651aea7800f9b69bc3dcf75df62b4e5e597010001	\\x24af640ae8d9e33a9a720de1d45c95147a4c958ddb69fd25e7aa41d62e8f151b37c8259bf84a888c4e1387beb88f94e790737ebc711055eb430b20c19df37c03	1651223891000000	1651828691000000	1714900691000000	1809508691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
152	\\x53f54a9b38e42a0053d118e8db6dcba68fc68a2a67814b1fc317c4897f301949a91242546e037fb012e835472b71120aabe5a239cc47feb6da9a3e02c435b5d4	1	0	\\x000000010000000000800003a85c434ba5573e1fe0e228801541227f347251b8aa80c9969719883bb11dce274bdef8b88a147e504a2b2f99519f3bdffdca9652b1d7814639236147fea12a360203835bfd46fc8d58920400e2db53e9eb84895455f11e58e263680709d79b1c6cea352316562b4977a911298406f58c344e6c8fd66e153e081251d212f8e30d010001	\\x2e484e3a708f2700a2b4dd3e5788fd410284a2bdc263b551521ae623ca140905246d6347e190c221dce0e6ac880f9aa0b2d555cea73bea62315d4bdb7ddc560c	1660895891000000	1661500691000000	1724572691000000	1819180691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
153	\\x56952955e8116c3068ab1a2ab517f9890d468e1b5345463e45d46ddeb62177fdc7a5222b191a06c492cf7b4dcac9629234ba8c5e604a55a6e7bf2dcbd5724d28	1	0	\\x000000010000000000800003b74c926c181577260da46234c5313ef2ac1b8162ecb8fea2ff7bbbfa4b8c84b9bdb1b2ea345201ab91d660c944a3780ab07046feb2cc135dd1332f76c70675405956e0515bf56f85d2350b4112691c7cdafb70a2e8d4226aa228991af5e38d4bd3430d7c54235f6b106bd8f3d910091e0d726804614c673ee1c387b54877081f010001	\\xfb02586dd8bb357189423b9b60451a8d8ddfe0bfac14274fc93d4b0ba2e4c9923a3d1a2b5dbe98909ccc873e887c8df65745fb851b8ee552a98b5ee5ee65fd09	1657873391000000	1658478191000000	1721550191000000	1816158191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
154	\\x5791c588344e6b26ed0377445ff9bc83ab57cde97fbf315cb48e00272aea3e5dddd6899f201f00d4986a15fd9b09da2021e3215efb0737ff2cbcec6772d689b6	1	0	\\x000000010000000000800003af0b60e89ba6764a7973b526c543f05b5b5aab8eb9d70e6ae2a6c3e2f4f4485e7172aa3eb7356c2deaa05957aa43b65800c7dae1faddafa043e169382751105e986d84cdc92759a3ae762b6909a6aa3c19e10b3729b96c51a9f3a14e16b5a476def2e4634ba378d236f096a8702f09c4a8485e1af65f0f28a63fbd3f24a3c185010001	\\xe8cd2360cff4d933982870a826d4031937f7aa4e36bc1dc26ca16c160b2bfc9ad29f11fb728281a627d7353101697fcb519a76a38cbd87651c78714db26aae01	1657268891000000	1657873691000000	1720945691000000	1815553691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
155	\\x57d1d9913c5fec7deee5ec364fb55aed7eaab4c507953f5acab05570ac0edfde885b2fa765ea1dac54433c6f6a78b09b2659400d4f1a84851da68ff23087f070	1	0	\\x000000010000000000800003bf0ea0eaa7432da7a5f758b6ba1165c5eaa05f2b0fb83ff472331f378ba4efd94cb43e8ddfd174f1cef7d7f9a6e2e0db83d1f42df077502ebe10f8fe41dcf2cf6028c2b1790c803b21d0085ab7a9a1328436c67fe7f497e8a4b194df28266dd3fe24e3b4b03521725c09008eb8849b55fa8b39019f11ca6590ee7642cb9c5441010001	\\x1ad32c22219a806133592e1027067267253bee3317311b6dc600a0789ab6e86d32b6e38052f69718f9a295bb1baf7bdf4e87629871edfddd7c00b8312e1ffc01	1659686891000000	1660291691000000	1723363691000000	1817971691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
156	\\x5939661c343419b137d9ca7d6ffbfb37846f7021263db922a83ede6a38c32bce80c0e9d927a83dd4f4203548c4d640c0f3118a6588690eb76c9de3dbfa2dec05	1	0	\\x000000010000000000800003df814c1d331e71c28c5e8cf24e2d380b65194b47b51f022b9f3d6e99dbcb7d2b5c06cc08ac1154b56bc7acab27c05bf023ef982b7bb5062713493e2f401efa13f5d7aa666c41675cb47d0faa0236b9bc88b269a19b2eeafc1557277c195489c50027ee9182ec035d5c67913f741656d8f1ddd0a81b27607214aab98b50072e8b010001	\\xe0583a7af077f51fce885d0af3dc950bdaae47e017ae516dd73356dc2ddccfde072419ce79b0f970f95aeca49f101480fb4bd17d6c5492442c0750bb76047808	1671172391000000	1671777191000000	1734849191000000	1829457191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
157	\\x5c7d548ff51130df3d23554d86957d8bdab9c85a6f470c255368ab620078696dce6361c1ad768a6e865df592f215949e5b955768ff49d9fce40b861d9d3072cc	1	0	\\x000000010000000000800003c3d9031708ada1452dcfee51c4b16cd6f5bfdfc9dbe6510fe9d055408d0f5303d1126340c97a30a27fbe72aed15e8f88709361bcf4e285713dcf80ad7283ce227e8bbf68bc01312dbfcd287a652f7ef8bb8b6a10e26828d23ec7d35aa684bf943e706362ddfea52d47099a9e4b6472db2ddd2a42c93a1f20184012e16dc21b41010001	\\x4ac07394158e1f0dc6ff1aba65e815b9528792d7e31f25b4d4f0c0cb209baceb99b403d0bbb5aa5ef68e269009d5039752e57709bf87b7c2e07350cd7556360b	1676612891000000	1677217691000000	1740289691000000	1834897691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
158	\\x5dd9ed228133c2bbb33a24b54084db9030729fc4a933ac00bb46257f49ed0a71d43674595c5acc580a6f6c2a45bd9479177ce27dede0e2c6d692c0a22c18b10c	1	0	\\x0000000100000000008000039cb67a56901e4d3f42bf585ac765782f48744c91774d8f8cb09fb7ec4897a6aa6fa55eefbc67fe0cc5b50fbdb3252aa0c44a34c7238c4b6c073e812b86c8f720d3788339bea89f1660b506b6dfdb3ad639b6dc4c09664e7b4d7738a9d49fa7325f4c77ecc36a85c795eef841964d83e864d35496ac2442e49e9d341ab1641907010001	\\x51b89a590c05cf657c8b936c6e5cbcf6745bc3e6ce126bd9f2881b287fcb16c983a1d071152389daf25c9da20e0f1cbecdba0cb6afae3db4d536a261a11db50d	1676612891000000	1677217691000000	1740289691000000	1834897691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
159	\\x6b912636c1386da7dadb0bb2b4070a6e3d3cbd2e708bd8892f3a922e162372fab1bf81ff047a6f3af19d94f779b4c94792188d6f243d42661e073c2967d96ee4	1	0	\\x0000000100000000008000039639d8cf4e15b3254167468bd79feb2a3e11b27148429cf0ea735732afd65e9be170298a2d35f8c0f4115ac46140e5481072b3bd293b61c48d2db56980049c699853674ac666fa645675cbce12656c6eb8390768b25f1d224c02eda3eb5cfb77e131311ab1ec8d6e500242e9f5db5b85cd1f03a41d4f0544a8d41c2ef248e47d010001	\\x99f221fbc86bb278a576102b1ed2218ced78c99c0d4b5cf009024994632dea686b3411ffb25f42d0f3e9ce9069a5c751d03ea34f16930aa43545257096677308	1680844391000000	1681449191000000	1744521191000000	1839129191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
160	\\x6e09e38d5c3d81f1837e3a48ebb9d7190b3e7c9794dac266f6cfb59dcbd869a4f10014b63fe13ac727f53b6cc2d1d6f3350bf159969ac4891c9f8818f9b105c7	1	0	\\x000000010000000000800003eab57d678e48af96ca30b39f8c40d3d509af9c99f068cb09ec270d3ae157852a58e9482878da8f100e4a3e4e805c3dd645b8275cb5a87290a63e433a2af6c2e25277a86ba43cf3009b7efb23a20ed91867893de68db433862d664fbb54abf5312ef8f00f3946327854878cffc335c781eb9db822f3e5c586059a69c158a6f019010001	\\xcffa4c70ee47b2a45abcccc5072f0de517db0250c33c3fc4b865bc5ff45eaa8b83171741e91ddeb817b5c2e4076425e725fe69cd86200741690ba57870d76d0a	1668754391000000	1669359191000000	1732431191000000	1827039191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
161	\\x6efd06193cf6c1d54f2ca9ad1a34dcf286e83895f153474ca7b48b453ad18d24003a222dbb114668370e1bc408c55401026973385929f31404167ea86f4d0a3e	1	0	\\x000000010000000000800003c278daa5e1a20725516ee13c08a8fad49197b8d709d236c4bf9eddfd2c9788aa673ab72f84a9bebc46228671c97ccd43522aa4c36e5a949a1abea8f981b78927ab31e2abe6a7c5c2788688baf907120f6e54081494632cbfbd2920cba52f67682641efb7ef7c50b667c964f50e29d6ca741099fc7a92f3d06d228a8e63ba1439010001	\\x8ea201f62083e9f9a5790f5b717f36abf29a412a9a052ff29e321d098d58edbb4606cddf143a0f7e439f4fc74d74275866ec6afd0b7f5f1244c08bcf6a3f3509	1677821891000000	1678426691000000	1741498691000000	1836106691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
162	\\x6f01c2929b86eeede29d3876820b97a52fc749d98cc1d1e07358a850e8c134f6805567e7b3fb87652a0b16db9d38830123d5164d86e6555771388e30a7b46fdd	1	0	\\x000000010000000000800003d09cba1e24dabc50bbb2063a4ca743b142215f492b546222d77b32d82a3c608ce83af9448921342f4ed2e826a27246b1f96969474fad602151e1775567dba8773466da1cab3c4a3370720c11ce71517e798a25cbe0e8b8b1e7d54e85ad3c09f0f06330c879390072c1ab761f953cc5738ebda2af4ecd37d7b859469b28003f0b010001	\\x125ab376c14846f004baa7e7af43f9e42ed9a0b5b668359c68788b8c508e3a4e55340b00613b1cced8945eccb50023f9367f496e9a301252353d762dbd42730b	1670567891000000	1671172691000000	1734244691000000	1828852691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
163	\\x6fa953ab0376ac2e497edf4e0e23e7a8f898e0d0b4c0caed7d961b19aca3b03d8e3e9dec5cee752b04cbfcc563474e046501ed1787c2d1834373df6123802da1	1	0	\\x000000010000000000800003a859f8fca9a1cc87be7aa83ace6885edf6d0f0285ff34e0c079ddea8300e3e9d7ebd2fb2899d1085820f3497ab20b92f31ba242691a279a6ffa006ffb6ef2c133ecb520ffe0db46f8d090395e3da26df5a08e9690635d88d60b10451444d41fee1e7c41aa93f48e16edb3fba6058f78f409d90871b68e96b96befa023774f20b010001	\\x5f3bfd839c9b253bbeca56f9ae3d43b4ecdd7697bea4d9ac7bc381a3a8f7efe6d43055b76dee03663af7db4d0fcf1ee399627ebfda5ec1a8405ea3f33997cb0f	1674799391000000	1675404191000000	1738476191000000	1833084191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
164	\\x72290d60cba9f8c6edeb4cdaebb998348280eea6fc4cf1a5e19b15653db3f1b030b288c71af8fbd46b2767bddae0c4ded874eaa99d5e59dc74fd583e2463b4b9	1	0	\\x000000010000000000800003d4f8b31eeb6d03b144b6904ca3e7c174fc43b77d21c995097bc759e4103863e434b93eb3557594c70705577693a4f5436968b3f3e576ef324760c2928ccb40fb3ea2f78834456cacada67bac17e2245b277d87d1df8f565ad4ffa3a0839bf55b8f1c744aba516a0c8b3f76dde28bd9b6a85233e71a0b480aefd26dc5e3343521010001	\\x637a169ab39b4ad4a7f324defbf08b568785b2acf318a752cb1b9db334b76c95c92b23a2745435c3b16cf807d55abad2b7f57110d442d48b910839b74b27db03	1664522891000000	1665127691000000	1728199691000000	1822807691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
165	\\x7629003f27b42acb1393d33f913d3452b5f18471f943cffa569618d6ce129db4357385a63b38b1be10b966609a9dd41f9b42cde1623e8fbad55f006d14df9ca9	1	0	\\x000000010000000000800003c9ca64ba2561d48e9e92bbeb3cf36d184014f117ba759ebd4fabc16ce31ef57efb3b3496cab036b3569e2f634c88a708cfa42f6fa85af1531bae5c7b7d2a9d336c26ee7adc450404536a87b723161eda6427f79caaf19933f8c97f338ffeb3e8e1548c689c0020f47f99c993dc49e387787d92b494d606b1ddb001ed1ad88127010001	\\xd621909ee88c59efccc6357a01ddab32e88828633d0c4274ce3a32bcee56154a87843f2f5ef84feb676880ab3fd9e0e1732df7ea7679418ded7fbffdf2e56a09	1659082391000000	1659687191000000	1722759191000000	1817367191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
166	\\x796d32e4ad5d58894df62d573570a48d058fb132a9648e9564917ac6346a20cf61dd96b47b49231b0323715f605f109b6a10dc012f0c83833d216e3b655afa40	1	0	\\x000000010000000000800003a67ceefa0613b7b47cc9d9102d3690f5b3ab83462c146850c5d1c148e85fe9a28b0c4b70d749b22e3cf925aff7dbbb611f2e51bf960dbd971c127037ca83b98c2a347ee0e4d4916dbf699b6e7baacc8f77adf6a5bd16a30330a3d70f40dc21f6f0ab77379e4104ee25d9432f80f136347ee45c488c5f9b4200e205c1f1e1db25010001	\\x00285226f3eaec5f26dfd929812e803980634eb9aa7dabe08c3b2c4344e3183c1ab72ff663cbccd91a9d1edba25280e8195d8675ec2212cdfef576ea3a0c5c02	1674194891000000	1674799691000000	1737871691000000	1832479691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
167	\\x7a09d0941822e4d745c8ae8418520f565f113940a7686aa1de5d7e55623c8c4360979cfff1c29bc2fd85178dd10d0ed6a060f87b946fb32544a13fbe1ff93c7c	1	0	\\x000000010000000000800003b9ca96cafee138c032ef3547a1da3e6c10e98601ebf43c61bf80574b315a5525542fbab4a7708c9e07d08a4dfe54b512215110d338090895a355c1b6363ee8d7cccd918594b8e2c60ca101eb9410b86b038183a39ac3f4f93fb5a8193b92c6ac8cd26b733cf1632f4a372d9d58d7878ee4034a2e6bde988949edee00e87c8919010001	\\x1baf8360d8fa0735613c172fb6bda2efaf14b27750ace551846aa147c016be3a155f75078319970b0192d0233f930922a12b6c8ce312c78bb651eb83b081130d	1660291391000000	1660896191000000	1723968191000000	1818576191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
168	\\x7d5526cf94472a86c8705bf7a873f8135dffb9bce7423602a27b40906a7be7e17c243ec7f02b9f2c88580568a4cb0a45aa80758eecce3f6d4d4b2db67556eede	1	0	\\x000000010000000000800003ba54b213b1814b664621c49f5e8170c8b778db5d5b898e70cd3fc5dbe11cea86772b28b1bcb314a281629ddbc31ad9334c5d269a80d2b9f13b721f872762df65380512f5c87c567b54e4fd4f3a2bc1afe8f26334436aaa88f0e8dc077b96d38c2d1cbe4efed1f988c26419c25cabf4eac860365772d5349aedbb66e9ecc29d1f010001	\\x3126b1cffd89b3062177dabf6e72141aae419efe0d7ea97d3625fc440a81ebbce254092e8e7472d68f108cf9aa2e0aeb415bba9eef0755e3f242c2f3a7031c08	1679030891000000	1679635691000000	1742707691000000	1837315691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
169	\\x8105325187c0bd640260b165516de49de35afb1f2368c6abd3cc441c20d9d388129539af3be1881226bb8ce332b5ce28aa6275f74df2c1c905b87e2c132d4691	1	0	\\x000000010000000000800003a4a6335b57b69a979662b6092a19dabae4c5165d0f2bb4956501b31a88da9be7f54f42742542105ce7c868a9f416eb1549e5ede3843fd00a5eb2910c47dcdf31b65a3c3feb498249fd41c21f59b6e2724776d0938190b0ac795794d1e8abe325eb68ddf277ce9f0ea41b361379e0df00072c290546f2af8d319ede7999484dc9010001	\\xa03253f2f0426679f9f67e1af413c33d8a7d8875fb48d89bd540b1e9c332b3bcf963fb68197f476a1add06971a44bd4a7138e31eb98ce6bce853802616d71a07	1653641891000000	1654246691000000	1717318691000000	1811926691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
170	\\x81f9a16b2d7fa1f8f52fefe2a8d49a9e062b249efb3f0ad0e448d4df28539dc3441ac067ea746951fa58b8d0de4d09bbd08f42eab056cdbf39161bc838c660d9	1	0	\\x000000010000000000800003a5b34d3dff8082d23310cfe7236373148167ad2014eb7a2eff0678abc6fcbf5c43e3481ab4eb76a8baf5471957d692134fbe895426c0e13a217d2764c5ddd88b7d1933645078a20f933ff9038dedca186191b1e5383ea3b761af6da00142332b2a4397b2c84dfeec9344d7c816b2253882e5e54ebd7dfa5eb44c455ccf4cc1c1010001	\\x69259f0af8140bb42566f49a29ed306d47794273dd35d5ea73150dcee5c6ed9946e6c97518ff223200f25e3a7012605c5ec05e55292b29ffa0aed9d7eae8500c	1651828391000000	1652433191000000	1715505191000000	1810113191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
171	\\x81553b8f34ff57f93596258c05ff2b6fe0706bf06be57606a86374bfc0cf5f0bf24ce5e9e36872ad285eaa5ef22066da3b3f168014e96794ccb1025e395a80da	1	0	\\x000000010000000000800003c79f6007cfe09830385f393db986b73ad4d0de080b7cd1b7b4ed2fcc87a9693ecf32f7ef8d6844562bdc8221d15f4fb4dde6741c699b671b260d88abb7f5fabaa7ed9985a67b6b7888e75334955998667d31b09a3ac81df975b232a4831e7005e4b7671db8ae44d04170f079d2256797f1009831fd48d8e7b95bfcd61be27667010001	\\xdf7a39360b4f10700f304cfbf0f1bd24611ea06be52f0bf714d99121a3c95be5e1d7e4dc87fc5bab1d5e71f7222f5436ee4c84312140732f71e8170fe99a2203	1651223891000000	1651828691000000	1714900691000000	1809508691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
172	\\x82018b826acb0782dbceb0ff1526991b22c602b91efa9a755eb8cabccd19efc20edeee0395e202332b13b913fb20a29d469e7e6a8ad979ff6d98b7f888adf331	1	0	\\x000000010000000000800003c4f763a7b03dcab68504baa4cc55fe40368c55ab4236694134c5962a6c94ad2e9db2942426a0b73e607964dbbae1b4edf545b9b8da8e3b81680897d95c023edddf7a1ab9a0985de140e79bc1178deb8b9aaf43d2c78e9503345dc80a0e6b2317f5d43ec08666ab2ab993d130b5fed0e393eb7e1c22452fac4a7109ade6ab0b25010001	\\x5b8f25c7c4eda3984ba85f5aee15b127cda1d312c99e362618ea1a4c618144cedf67e06ae8a4fe1bacba4da469a69969a0e8cff2dada4e4fada2f5dc8792ec07	1666336391000000	1666941191000000	1730013191000000	1824621191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
173	\\x83456e459cb2a372a1a1de838bf6d6b25adbc658867c2980b85816c09ff20aab82a27a6b31f2d80a14ce8e898098b55ba1c0ac3c03d9b04a7f525add72e75450	1	0	\\x000000010000000000800003c5e9d98f121f79cbb9475b4912cc986ed192d9a28730dbab14343b8ed1f88e78f2ff5a33cc6d27531836df9b0ae06bf2d5dc5833c9276a481a47e446b8a2e3e0587ba76774b04fd8369e74655a1961901b8d1ba0a71f84988e495d84f295c66023494a80361b446d9306c03c07d3eb9a918b5677178bfe7a6f7aa04bae2ae85f010001	\\x0e7a6ce3301fb0c49ff1c5c693fcd575b0c8a20c9947a80b066f130c52cd1d3340011c84ac3886c24e6e62372cc340863b51eec8456387608f27f2443c18110b	1666940891000000	1667545691000000	1730617691000000	1825225691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
174	\\x956563a57d50bab18ee3506115bfdd9d6035604b52f7884505a767f597166e70bb2b75308294c3929ee0b520978ee9f2833f58ef5de30301c70228170bba9607	1	0	\\x000000010000000000800003ccd80edc3fd4e3af934cd76f4aab4e9e589fdcb2025de5522942775c16d6a6d345b9f2f6c524299d8c8aa8d56da1fb6e4b108c012deba35fc82549639c943eb83c779838e2dd0cfb24cb467474d94e2dbabd4a73ceeb8ad50b7b8cac5c054208991e334b52f572facbce3a56d7e0a10eedd24b833c6d9b1f57def51a371b53e1010001	\\xf344f09c665eee14010ee108c0dd46fd340691594cc3664e8ca86c1035d9ad563458f142f02cd40eef57985231645528106e0a7b438a25d1d339915c76161a03	1678426391000000	1679031191000000	1742103191000000	1836711191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
175	\\x984545254d0b0c1a07b04a819a99c60ea184a54fd14134e965a9831d46e12aad835c734c5591de32042cb66f46a5219463bb61f7258592915aa0ba9b38703ce8	1	0	\\x000000010000000000800003d10aef2169ac8ec9931a8243e037693b30e08280fa0bdb156f5d9c1549ed351cac2fa9a9ce91ad6a81b54450daf70558fd45fd363af29056d95f7a425c06d0f31f2a018dca0e66695586f99b358ec505fa866e0f415ce0785bc55c5ae6431d03132a769795644b12ba02e0c629ee6bbcd990b974c8cf4af1b433d6f6c867b7c5010001	\\x6aa20d3e378a27d58df589a0065fe5bc34778527490330028bfc86c8ba86ee1eb5ca54de57989ea64ce529aadc10252155fa877b548f3dd6f673b742eba6e006	1666940891000000	1667545691000000	1730617691000000	1825225691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
176	\\x99299f8dd2aaf36d83bdddc814759162dd19d80c006e6b0899b54312e6f69cbb13e42270f5e6b3cbd1bea22f5cb09ce6dd010cffc9f19acb8693858bb72e9d9d	1	0	\\x0000000100000000008000039dc39eb1cfc0245899282a143c851dc90e159c9f03c3e22a26f2fc423d3a89e4fa660ec7e219bb8d9707a601288cf74817a3c4d9948081151a4e320352f3ebe80c9e8a1d8616331ee9bca692e491905f5bce103ed40ce2c5406d4161e1837d265be5b18d004203cdadf4c4e9375f9481c41f8492e6fb81e3f16634f15eceba11010001	\\x307f5adb2eeb6cc70ab175c94aaff3204294fa1ae6384818d45bb7718e45c18654d8945ca2c46cc731f21137590eefdff58e9c59e14f576b8ccb339185e41009	1663918391000000	1664523191000000	1727595191000000	1822203191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
177	\\x9b252a6e045b20afb6cc34b61457ef2bf06ff161ce43531c617f69f8d69946ee73c02208d81620656d30b3351ce52c3a51acb56b0ea7f28e812c26dd635940e4	1	0	\\x000000010000000000800003baf8136f13bf5bc7f72f369b8c46f41aba2e4e8d927a61c324a4bf70c9254497f1bca3d096786eea5295231267d7b2b276c4f9e1dc1ab16ce574991b6dd703d5c9b509cc13ada1aa1bcfa0ef4ecc16913e7b0eb2b45f26a6688d8b107edf0380cc6d579c618b324fb11677ec1262891b15ceb35a268c2079e17b02935a1b89d5010001	\\x9515d4dc7f01edf817164037d03a1bbade2a33cfc7ffdd8168177789d43c02257b9508f3fdfda47231df1678491074b720c819e018dde6a518b83cd92c715d09	1668754391000000	1669359191000000	1732431191000000	1827039191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
178	\\xa09d696b12e235bd3bebea4545cfba6ed7be776b738052db8f3f764d129d48a5594fb29688a3644075776699cc4fcebfe8fa0d3c5657a4a01005e57c9ed4c1db	1	0	\\x000000010000000000800003c315c3dafa7213279bfc54d6c33fa3e8ea15008f0c23340b62eb825ebd7f452233a13e99ce6f9ff9ae2b8726c28f4c181c01d54cb3222de4adcc40c5bc9b9e040f2dbb40a04c255ba3d8f22fcf329d2f18b95e75e252375b3e9bea4f8a1c8ed8480f7a08b85e77b187d5bf96558619e27998e711e65dbcad3a68d624c6a5c8b5010001	\\x6d315fcfb8628825c3b0c2c6ca34d1844abddcebd710d4c979730bda057040e0067d1249d816a4809a526e8ba558d555c7d56a642d3ea9d48c5477f79916c206	1679635391000000	1680240191000000	1743312191000000	1837920191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
179	\\xa4c542153c6aa30a4bdfcbae2c3dc349132bbb069af9f36bf4b6abc5032f17ea48bf2275ca27814dff16aaebf4a7ac3517e6a3023854d410d214179792c623f0	1	0	\\x000000010000000000800003d2d27e9e3707e265682722459ac31d7672e5dab86ad54216d0526d9fc5e0d8f314fd79dc69f61267ee469d142c500c1de9d494128aaf99ef54518c9fd7a02b67f8fd88cc60b9e510a5c512516a50a717c0360f70571534ba907c6e8537fd2cfea45b3df115769dc0048eb25f2db77310d17e507ea08cafa9ec97325fea0bff4f010001	\\x4c4df68a2157df976f2ddc86426ea13383d9a52ef253766e9766771f94ac36688bb11097134c295f5763b841bf1b117acb27a305845f57cb088c6ff6a92d180f	1666336391000000	1666941191000000	1730013191000000	1824621191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
180	\\xa6f15f8f9cd909ebc31bcea3eac98b50f53e43c9292c3cb1fe3bb1c2f668e2fabcc50d00b08fcbb6d99d862a721ecba177716b46c75cd7d569e08df3ffb9e1b3	1	0	\\x000000010000000000800003e64001854d05bb3f6191bbe2756cfb66d3a1502e89d4da45a05d2a5baaa71e2f51afdfb416043d806ccdbafbba297d5e7039d4176fb7014587e6c33836ec82a4b6e73133eec7d96e94c6031dc0b920db09460ee8f20f6b625d887ec34ae3e9a4101f1a77152940e9810dc6474f188e0996e840f4869320180227329921e01109010001	\\xceb38a876f85f3f9314b3e430042d60825dc18afc60131e2ffa8e31ac2c3288ff722ad00e8ff9fd6c5cd7c558d4e7efcce1fc624c929c41167d9f447587b2a01	1660895891000000	1661500691000000	1724572691000000	1819180691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
181	\\xaad17a94f27bf10ab2c1ecd9fddef6eeb0d5374b32a896945d42036822332060e792d1654c331cfd712bfd525d0a9f35368ce491977a677717080d8cd24e6a49	1	0	\\x000000010000000000800003a6b03eea71ae198d8f587d145821f69b0edeeeb7265a49ed0126553c4e75e3b891320b5f56f232aa95ef6339865f4221dd60d93df21ffd9c6ed4d803047f811a2ca1f386cf64d70f470d7a27d84cf081d1e00933f4deb3cfe2bce39b9ce0a4c2f996da6741cbf1dccb89700c00ce42499f1142714234c6c2b138050816d0ac35010001	\\x60dc50af44fba80890f5a054dd07de8caf1d38abdc0439f25fe94c1f9e760977c353c3fd5e494122be2d4416d7d04539e45d18b9384556b2c9aef2d9670f8f06	1659686891000000	1660291691000000	1723363691000000	1817971691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
182	\\xb041bc9d08eab07d73e325ccfd103904a9536cd04454041224e88b86f28d2dc9eb6f15f2017e41344c09683c8947534a324329a850c8959ecc6d6bd23d650979	1	0	\\x000000010000000000800003ae232526db235306ef1f77c0839acfd5f85f94d4da210522f781134617af92393492a499946d8c547900e2e44eebe2c396604d85cb7a8743a3e5825b4eae80db2e2aaf3d69bfadeed9adc7fcd86e251ff57523181b26205dde8c7c717b6b9a36b3446471886065d772cdb7a117cb4146bc36f89610cec70652ecbbb2c19be2cd010001	\\xf7bf592bde4a680cc7f63253fe414f165b7b2d9516e21cbdabec9e6d6a751bb7c5ac90d43b57d35d04215f1a52d26805a0594b6d46d0b72532d0a9b0703d110f	1680844391000000	1681449191000000	1744521191000000	1839129191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
183	\\xb039beb4cb1e06a7675c6303603ea1494c79c57556eab850926a6215250b3f80618555142e13ff7062d4dab5596d934648952fe96b1fed4ac572fb6aa8d4bf9a	1	0	\\x000000010000000000800003c50e9893f7b6e3e4a6c7da5a397560faad2b9dee642282ffb33508622d01490489a0b57b4ed97e4add20b9c5d5c352f62f7dc6054df6a707ac2d4eef7a436503d07e9381486cd33504bce608d6ebe7ca114b45d31ac6ebf4030e97025359ffe896a241bcd83a069d0a907143862cc7b3ad75b6f37bbf30bfe66569e26d00f0cb010001	\\xf2e825d788d0c5805fbd476de8a3c066fabcff1b370867ed5edc3d978ea94f2026cd0c11f629258af8c07f5d4ff5906867efbdc06d54f77437ec91eeb0e74e05	1671172391000000	1671777191000000	1734849191000000	1829457191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
184	\\xb259cc01dde4d833d94899db9f58dbc940bb1c0d2ade58a4b105c41bf51ffdc863a3e90679db22ceb5d6b0f4d2d287cd20116d0cf05d3e4b11f608434784e7f7	1	0	\\x000000010000000000800003c9004c3226a39550e03ac3b763b2a83eaca3a6289cc9ad44bbea7cf9a55e2c5ed95c601dd93dfa0367177392054c4d44b5b05301865ea7af2b58d59959df9cef32b6906e1a022daf28023581736ae42a1ba8fee6d8b982c9706cbf6138c93ea69fa9041f2d44863b995fd8e53207fb21a603989b58a6d8855f1d9938bb9c693f010001	\\xd57addfcd0f176c26e4b576713f238fc617b598fdec192783279bfc65add728a65ccd3c36344218401fa8af468a78e6b5f228d4a7387801965c61c5b9ba5b008	1663313891000000	1663918691000000	1726990691000000	1821598691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
185	\\xb2c9e01bef8470457691dbd9a00676a6aacfded74be7a8ec9fea13abeb981f84e60d7644fc5203d5d4636304176d911197d7423f1ed9be1341adcf8aed913d21	1	0	\\x000000010000000000800003bc22a59a5fff322fd3dda41fb50e2cfe899867f10f62d538461a1ff5a2b107d21c2b0506c8319b5654ebea9f36447a9ff288a8f05227a00240cf206cf8870a6a14ddec4479ef460db85fd1d314074d81a6d746e476ed8f763f5835c1bc99cb47d7f87f395c4c441df6122459950807cfe4d36bb78a49668428462edf938bb34b010001	\\xac1f4085ab48e11a039800fb6244a014a911e9b81240fe142dd0d46216fb985caab379ba5b2e7698bef820c0fa32aebe8fe10ed3eea0f4e7b62a75bb60148f0a	1673590391000000	1674195191000000	1737267191000000	1831875191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
186	\\xb25d58fb0c9b842efb1dd0cb167b49f5081bb8168ed68ddced6cfd31f685da7c28115f7bf4c819b9a285c36f834f1f48728660598033f303ab6e4090ce1c6725	1	0	\\x000000010000000000800003e07a9d60b703b50aa1654638c18d255ae427815d714c25d24dbc5036a1af5af5d6ebbdda216bb097d973a0902d32e1bc5f29168e3efc9b6ebd821d43912e2dec76427afb1b9e4ce831c9155414c37717cfb8363741b03aa39876e48ae408002b5d3bc507bffe09e7e32cd9587e5e71e231f2d11d595ff34e351ddb1a4be5b195010001	\\xfd20343605b8da298fca52c396646dd554c78d9a2d091531040b90a1248dc670dc78d63f9529614cc4d09448312d948ead031d3f880c590e03a8258eda01a106	1662709391000000	1663314191000000	1726386191000000	1820994191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
187	\\xb3c184fd2cf618eb88c613d375c9ec09a9d329e054bcf02b4371d15e3c1be9ee705d18e93b24d28ad0d366cfa8534d2ce4ea8e250c305aaf699bdc4c78c15495	1	0	\\x000000010000000000800003cb4a04d73a8631c0b06e244282b739f05bd2633bff75f0098ff8463f5395c5ae5eec5f1eff6e763b6cb1ed073326013578de949d99ca3730ba8b8dab63b91b3210c536c2fb877d40718c77f2c5961151ab3cecfc6ac79fe48fb37d92f5e3f87c432aef23561e08667ee4b35de442224e526429c5cac1786aeceeb7b1ff7e53e9010001	\\x5fadb3c57614f59eddec1625ea6df57a58647a6e7edb0c9fc16c541159453e67148607e0068ae68d9f14847b545cd3b23a4e661d67c51e113149839dbcd5f10b	1674799391000000	1675404191000000	1738476191000000	1833084191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
188	\\xb74107b673c0be3f4da0911a9135cada25a5dc430b73078fc5f25c0d968d02a0088bd895ced96b83579b1df50e2a226f3161557482b3d0ee446c162d42c1fb67	1	0	\\x000000010000000000800003ab4236fb452468a50d1640522a761bac0ed6fb1846a3a7f711943c2cd6a3f962bdcbb3b5967d7805e348cab27434cad0f991d7d36b16886422535925f87b7ce3b12b23d4ea59bad64a7f2110da88dd8fb474caa250850ecda19ed3a1523865801bee3eaa0bfcb1cf76a79cfb3aef35103e1f71c1555e059511e0321bb41a9847010001	\\x8e99308b35cf7fab81529e5fc7c3c932684779de594b776764a52816bd6cb3280afbfc0be3bc07789f7f84493df5f083d5bc36fd0a2521f9518c43e7072aca0a	1662104891000000	1662709691000000	1725781691000000	1820389691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
189	\\xb7c500a1827416fd853cee2274ff654b93e9f3c63ace266752d10cc4671dcc710b65a9a21eae93a99f484983bcbe3c7c6709c378fe13c0ee648233e230d3dcce	1	0	\\x000000010000000000800003f206fa76ee19d952998c4a6a382e36016a166c1af5e7211fed19da603cdb2a7a9e17d07eaa127f8e40a4c7948d4d4c6ae7217afcdbd8d2e532cd04fe124274006d8d2edc7b185ca1d50a65df2338662c4d91a6ca487d8ab3a1cbe81614e5aa9f672f25780482eaad7ef7f263b68df7018e61913467aeb6e41f4c37c4ed696015010001	\\x7d635bb7ba0f352639162bdf9d0753956a5cd2cf2f1e7719726f6e7763138113959a15c086493f20fa379b1305b3dd61dd6ce9f40531cdf12eb7909d829abc09	1667545391000000	1668150191000000	1731222191000000	1825830191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
190	\\xb9257dd48f7ead99622fd6ac41a94d5ee6ade4ba16f2a32356e25398526776e675bab010f8ad8da098245669e3ce99b02fb09615395f7f1958786edfc86d907b	1	0	\\x000000010000000000800003e7c3c1b7878ec4b9f6d0ea0969c5ef934ec339e72d452dcc1ac409b6cb90aed9542f90af1663d7dbb41464a4fbe7cc1b608ec1d7385c213b43e1682a7e7f86cba8402fa457000d946b70bde9ce2116383717320c412b9e35e18729a1dc2ec4fbae816d6fc3ee700d509bbf4a0de3546345132c85ceac09f53375d06944888037010001	\\xfca6fd259cbafa0f9fb5b32189e3c1f1904ace30e0b7916ac9a5f3c6581d3ab07ec6f4f05598adc34bedb902b5924141036695d0a1ac62381cefe9c09247b902	1651828391000000	1652433191000000	1715505191000000	1810113191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
191	\\xba61615d19e0976cd276416f2b10c6f77c0508b5e815a8156e51cca18391324b3c0816a0a7e28d03192a88c6756b759c0f955f8d8463d33062290a560b39ef7e	1	0	\\x000000010000000000800003c3635a938f3729152139ddbaeb6c19409a631370f7a30819c61ccda768c3f2c78d328221c7a2e73ae6179d4caa062e0637101a2701bca5685e194140c8d58053e2a5830153c273af2af40b087a6f1fbe792360c1585446fb352a34c3a7a2be9fbc66f01e8878d0e0c10ee1c6352deee523d90d5c08122128420e5eaac1cadb35010001	\\x5645a8eedd90d6f1331f3e50ed5068e5b62d4d55aebc880e20476c6998474f13a904c246daf263a86f4f152c41d6c83cb24bed328a81b3092282ccb9cfcdf105	1660895891000000	1661500691000000	1724572691000000	1819180691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
192	\\xbca9525bf084401174a9799bf75a538faee813e7d0c088fe4b2b02702438ff78bb7b00371635a22029da32232284e6456e93df9ffe8810622cf607262bbd3f0c	1	0	\\x000000010000000000800003be462f601ae7560347acbdecbd2c093827b209907e6725af47b29fb2dfa4f06e655c257e493cade5abd1677cb225dc8174658c62aad0bdccbbe1437a954c615eb492819a9224f37d810e53454d1d7b32138582f64d47578557b6623d8345b9008e7d229bb915ee0eaef543e14399c5394ed74960a59abb7266d5223d780e6961010001	\\x18f5d81d5d494f2f001a084d3fdb2c6f2526ea06e99b1feb6199a68fe66f0c57540a6dd49621e41bb702939dd915d70596a833989278f8c5b98582a454344e04	1665127391000000	1665732191000000	1728804191000000	1823412191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
193	\\xc2f19bd956c956d7abddf48e4731a888f91262121b8dfbe556ced201712e97c3f75ed5a456fd80b7d236bc526d64a7aad8949157baf944452a7c00f3c114c0fc	1	0	\\x000000010000000000800003b3711b7e2e6f7a5b8aaebbe45d4b3cc8eb4dce664307cc8f03fac0ae6496fb473e38d06011240289ce0dc850a34fa1ad5cdde4194c3198e7b0b2efbdd2b1045d7d0f520798098185c22a27b7bc3f370ade2d534719db1540f674403d59574294abc6614a73120a6a256461de44a30794d6bdf5be5be6b6ab16975c37ad6259f9010001	\\x389c5332516636422ddc342b038afa710e78ed64ace279cb75070cbe5e395763c5b37eef04e651b74f14175ff5e4b4656465628a81d66c898fed8611d0f4d504	1655455391000000	1656060191000000	1719132191000000	1813740191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
194	\\xc3518bb963c0f57cbb07730a4f9d706fd60974bb4afa14519cee61811f084b8e12a32632fa545cec24126384cab55cd0fbed3947832d918c53438465f62b027e	1	0	\\x000000010000000000800003c100153f1b02658d81c16bf83e4c3100614e044a3a670d47acca31b5f273697438b5aeaf25f03461063ce4854698e9feff5040fe93c198763e43b1fa459ead33a85eec5d7499bc59f291e6beb9b32825324bec28806b0e0cd8f895db6d1e8d878de9cdf4d720859cbd0d7aa0b299714aac75cfe8e8fbfe03aa81e63ab9b546d9010001	\\x8a83ec698e8b1c18fdc9445ece6d5f99fab27fd42b559ac49b9ea096b5bb0c911bf41eca37ad27951d69a396a3c9b2d19e3448c354c58e3d1766066b0431c606	1667545391000000	1668150191000000	1731222191000000	1825830191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
195	\\xc4a1996016dd4af432c6d63fa9ad28792cef702b07cafe515d9620c167934783eecafcf07a847d9822739d4c13509ffebecac1969e7ae4e12ee30c27bd8c9e4c	1	0	\\x0000000100000000008000039bcb406b462f325a153564af6923856c6b02c6805ea956536dd04093909cca86ae5eb76cf4b60eff5b577b877d964d95797732b7a9eb3c1880d96fea145980f8f750d6afe475f9f1aedfa09ece2598b84611c794238f4f47480f263a1fbaa8f97285e50332ed2dabc3095eef820b3e60d5c531fc585b02e0b94c882618821d21010001	\\xd32313cb1b64ca69c4243c67d3f5156deffd7d0c3af59af2fb79986cac3709ab49e94fd9757a9c89a84c8138358c0290303bde536654792dddf45a2bc5843e0c	1668149891000000	1668754691000000	1731826691000000	1826434691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
196	\\xc43ded9a5ba39b61220b9edc7f1ad928edeb8b983a609c649f479675635c597c14c2e36a70119dd886d9dec87bedefb736ad1c2445f1a37a81222081a3839c48	1	0	\\x000000010000000000800003c0d2860e0e1eed631bc3aa1201a34bc19f99eedf7762140688428d51abb49a5a0a318e3e9769560e75e021563383916814b003d46e77ac5182f0fa7d4535820b9dc61e0d5581a5dc6958899f41e89875d50b6db95170e285407ba0e947984cf21620cad8f5a25f8756dcecc79cddaedf9d6b59652806eda4be09359161245a17010001	\\x27bc5b22792b41e0ad8afd8c417f8db46233df7a0dfe4552814e0013627c0f01a6e9649ac8e37ba50573c92edd99a041ef1529b5f71aab410f8bb4a03ffaa101	1656059891000000	1656664691000000	1719736691000000	1814344691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
197	\\xcf7959325f909b69ba6c251dbf29d8c39ffe79be20432d4cb49ff3485db28d94aa21e45c5b98be4265972883aaec1d7dae348ff965ddef2908ef655acb6597a6	1	0	\\x000000010000000000800003e2370fc513be330b9ebffb58d5217c0c2c3f42553e6c4867408c3bbaf9c766474dc977eed450a16b6abbf5a8a9fd2208debe3e36893242bf11760b15363f526dc25b15378c4a392ceabce6c9a9d34d6acbf2bf695d34b95edb0d702b4182f1492d39dcbc93bcd4248ed046c12dad23c145b36409ebf96609dc5cc78b4f7c11a5010001	\\xf80cb5f70a0a57dfad509bff336af98543ecb95b9a8a4c7d792ac2d82278bdb3703901bbd40f8b3bb7128d825c600921815f217a7ad86de3504e42b8ed93990b	1668754391000000	1669359191000000	1732431191000000	1827039191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
198	\\xd0852e4e711769218624c545287d12f1e27bc18157e3ab4e631de26b5ceb59482b3922a219683df58f412b5b0d80f0876bc9994057237ef00c60715cdcbc9392	1	0	\\x000000010000000000800003eec3cbf71b4b09dd92058f9efe51eb7ed3eb05c45669d1f677cd0c480db3812c5c8f43aff8e251fcc50b15be5a3bde3b4f95cfcc2d9b569bf806f44843963eb76c3256a1fa5a58c5668d15ddff2bb3877c97a897578a9af6701080b7b23a71c31db399eafe577bcf824433188e453de2ffe78b467eed8262b4e2c987f272c43f010001	\\x552b5f72a8a61c41665128f2287fd4454e7ac6975e9879f6e440e7e62ad073b752aba5959ba1288b5eadeacd9d07026d47d391eb114e645d35f8f4ffa5bbf90c	1650014891000000	1650619691000000	1713691691000000	1808299691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
199	\\xd2e9c044ab2d86c7a0db1a8ff5def7c52e1647651e238e85f330d7b5465fb63077c31674670066880f6305a9c2558a26bcb8b0cbbb399e6e9f48c4fe3b084142	1	0	\\x000000010000000000800003acc834893543d6b40db3ca028d07a54f6f5654a16ce5b6ea2d393f7b56c38716a0659b4a12ba21ba587bb7253a170bdf021b1cf083b9a0a7a0830171a6346c2e895437408af462ccea5421b4eb6e16e4909ea756a05c7dc1f7bc59e180f6a698402ccc2ece5b7ce9033e55c2a09684400ea7ef0d864ad9de16fd1bc661292473010001	\\x9953bfe14771cedbd61b2e7281c512c7e9a3c0d718b86feac59c835ff2381bce89167b4632688ff630e6f3923e700d13cf80c781f52d9a764d3a5dbb61f2fd00	1678426391000000	1679031191000000	1742103191000000	1836711191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
200	\\xd4951935eb0dc2249c74d8cc4142c54c19fffff01384a71315ff854986267332590951ffa95b28173e8d2b72dbc6a2180ac3e55202e42b5b97517d82a5e47dd5	1	0	\\x000000010000000000800003e55bca6a25e4d5a78607406d50ac6c99871b46f4a3abfe88bfb7a83796908ef1494f466bb31ed0adbc9b4df560a940e9d74d4ef0e60d6ec4236912b602f6affac57dda7921f7d1237fc93ae2fa63f226ecd9a99a46030f3914710c3a2ade3b1c2dd9306e894147193d5552ff2ca1427b8af78cda8a88235c87ec220b395b3009010001	\\xbf8d8a45a191b5ca5299b553cd81c8cd9a99d51f56f0eb9a05382b3cbb7a20a796c808f86cebbf4e123e4ef27838cb4be730f86bab269bc1d9d9733cf81fdc0a	1663313891000000	1663918691000000	1726990691000000	1821598691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
201	\\xd7315bff37f5ec4efc07a64663932750ef2965c97b2c58092e83fea8c7fe6b70b9e2f370a4ff0da72a5d4ca9082431c1d9628779f6c74dc77db7f9d76214bc83	1	0	\\x000000010000000000800003afb169e1075e70a07ab99499885e15d00d7ef1096d123f42a1838a45d1ec884bc25a44414f0b4033b983a95ee4ed1b7a1d3b971c9f57687c86f633fdc600b7d1ba9f017083392eadc1ee0a24826ecffa7f6cf26eeeef791ac72dc0b2cf40efe0a10f5c1f97dc6ac0043777588f2f5c1d265405600f7ecfd13aedf3d9a342b7d1010001	\\x7b6aba93c2cd11ea8db2505bf3f271f7aadee22e501c142862a79cf57ea6d7e225357d3fb9cb8e413d119cb9f23077b15af3b71658031bc9eadcf64ad67be40b	1651223891000000	1651828691000000	1714900691000000	1809508691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
202	\\xd89195200fae79e8acd198db9eef3db59067d3715652a0f591e943499180a27f3cecd0f14b3cdba053f1e39482441448bc624a0ca8cce1e0d05bc17fb6a6aae2	1	0	\\x000000010000000000800003cc82c02a9c2d12230a38e4b0029db2b9c24b639a4f6302baceccb28c25f0a6ef8d9b2b090116efd9194f9664e8e6f845c43ee432d57032362b13a0bcc226319373117316471f2af730580cdb75be97896589866e373a0b55ae36df5df915ae03319cbbd4a93ea6e776b7f9a39e28109b4880f736aa594790c1e5ff1abe07c99f010001	\\x0701f39c53ce75bb02ee89cdd0e24d7333965a6e30827a30eadd30f5fa14d895421071f43bb99cc892219b001decc3783c74f65feeac5ea61e80e12c216cbd04	1662104891000000	1662709691000000	1725781691000000	1820389691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
203	\\xdcedbc0aa2525d3a37c949d334f8e72bffc29ccc026effd790af3ba14ce82c3b62527cd7f044db8af61f10ff9652b85ca3bed42775c38539b78f9bb7a9fa11c7	1	0	\\x000000010000000000800003bc80a831f2b6eec8aeb81445dffc58db54b39e1d34b4b2fe5c44da44f07a297a61ecc35b86505013378c261f211c60bd9b4c9d09629b2bf58021c88dc04563b47986a6e919c6525537a88bdd5297d8aa77db4715f572b0fad2ae74fdefe8fabe3a29d6d54438a79dedbecac4bbada573cf156b67997f9aa1204671d35fc503b9010001	\\xab76c2977bdd01a57456ae9125daca33bd601d579735df599cfd6e2788e8d3364ad4301f3616804740b7a37108e87d5837b61e49ab02f493a34eed6a25563604	1677821891000000	1678426691000000	1741498691000000	1836106691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
204	\\xdd4de74ddd1533c5a9a6c353395431723499ce570cb5fd05b55f1a15e62b041a14144227cebc163114158c6d2bbde1362fa05f443a7dd3f8404c2419b1b47a79	1	0	\\x00000001000000000080000392da7cf9ce4dc0f78aba519dddc2b786889cf1cef713b49776205553181f50902f53ffa67f1ca1a31d1df482f3efab4fbe8c9292f1b73ba2b285bc206c79daba2da19da78281e0542fc191320c7edd993adc2aba91f179a7fe13f1fde480ce5711f8b35fde2d832123d50f49785a4ffc6128270b0d89acec5202ca408f074361010001	\\x56e8dfc4ef50eb0ca876edb99f924a22b814e0baea1e2cc8555bfb6d78a74f9713aa2d429d1f2d34e1f224bc8f8116889853f4967f0220fc76f0bc32f0e36003	1660291391000000	1660896191000000	1723968191000000	1818576191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
205	\\xddad5ee29e691b6fca5a1e29f89db1aa4bacf4c95c456c85a611e137a6dcdb6023bfa184d251db0d5e4b2c648b2133abbea47495cb6209f7fc923962a4e6c168	1	0	\\x000000010000000000800003bb8afadd473a7a2b1e130f8945074f917c8edf23af1433ffe0beabbea3f22a375105343a5a31381e085dbdde53b35d8b5bb29c67db9b7caea3168d2e4d2cd21dccf3c8ac2606ea63fa021f987bfc78e93a4ea5ba28d8059bd606b3fc3fd4783c11b4445bfa9d4cb7a11f5f0ccf604c332e44e2277e1014587931a4fb4a96d6f5010001	\\x08803227cf03610dd541b5e12c4b28eca213ad9c7149d367d39f43307fb34075680f96b640a5e850f60e39e89dba75ae89a6a5775ff5c229cb4191a29c8d3c00	1655455391000000	1656060191000000	1719132191000000	1813740191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
206	\\xe0c5c6a9495ae1b8514413acd1314ba220f1f1244f839e87864ed39b7e5a34987483ee10f40cf6c6ecb0b4f64ab844b61260b4716dae7fa61ac21a3c1657e9e6	1	0	\\x000000010000000000800003cd4a8fcaa2f9dba40bbd7dbe5b72d0cae2910512a7abc852e6bd213105258eda82feaa1d6581953388170bf00c6d45a0512058b47c9e5f8d564ae0cfec5e86928a25859b2ddecc9f77e7361b38aab5e0237702d64ac2359fc7bd7706890b4b9e5740eec3f4e6f0a6a0165c7ded0678a606aedf00af9166b92568160be1a62bb9010001	\\x2e3219484258fd296af75dd797395be6ad9f49d5e0ae717d5ab404eccfab985b17d2b33130de4db1ff587330b30b8a2a82d33523455b4f3f3134a36c00eb2508	1671172391000000	1671777191000000	1734849191000000	1829457191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
207	\\xe229e9484339b458d4f4a40d73620b796f3811b7deddb00c10307e5b235cce45c21089282b1b35055a036c5342b8c1545bdf456a13f98d7707ff8b8ce1b4445f	1	0	\\x000000010000000000800003f8e651d0e25ff763102978e14f6dab3d416afa9f438ef90538516e4f455dc84978b0917d09b8de0e5b3c4a0a3ccee94e13341c5e924bfe43e96d52499e841de3d42b12c866b119e187b3e720c80d04b87fd77fc230530b0dfaee7009268b0f057c16162679fb0ecfa369f3cf6e56350c23ef227a86647df86c2627fe1fe37603010001	\\xd3c5428864999f2c3d4812072f1dfeda67d3c44713909c6109719c5f2eaa8d928133df20fcc0701e29f93f6776f52295a39db1db459267f5aaf3dbedba89d708	1676008391000000	1676613191000000	1739685191000000	1834293191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
208	\\xe2099c328a8f5b197c569ddf68dfd1eb4158852c5ad4228056b74f8e2a75419acad2d4339e7938a8eb661f46c7257af8816385a805f8749cb37cfa9322dde24a	1	0	\\x000000010000000000800003e02e6e39cec40fd2ff4d74c9f51dc67fc906d192cfbfdc0fbd303b62f43734d1c9b5853b54c5f33fe8b3e782ee79adb7b926adb1d0a98d777080f851d7ce31db00f4f5e8749126a5fc86272e60836523b481863a63330f51f8b5e8fe45235b7f0234c10ebf01816404ea21d406404e6148defcaf1a9ec9d7999292058b5476c5010001	\\x58767610896f1d14be13146aad5861af6aaaf10dbb1125cdcb3a12c4b12fc75211760b50ae9b16fb5aa34bc025022320b66c64a4b20c366b865e93c25c60d50d	1650014891000000	1650619691000000	1713691691000000	1808299691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
209	\\xe355ffdda6e9bb551e66dea72c72afaaa01b6cad9a90b4e418f17f1f2b67b833f4192640acd50e9e78c18c91b7db270cb3aecdf40d59a9d9e1c54b7ff036b273	1	0	\\x000000010000000000800003d65f3de9c25bf7c9dd8a94e5b4d78d1544365be0b4c4d070df7e64426a3f0b620ca2958feb0f53cc2bb119133cbe2f8fc80a46c763e94f08f9b5fe92d89561e3c4d53a2b4cc9fc23dce250439235ca2fb7b651919bfb8798ae475470b37eb41e4c74cc7534c3f65eeca4b1be19cb8eab2c4d717a957fb3ad5b9b569f9ce59165010001	\\xdae70f8d355257db7d9d5d76b79bd8128f3b91ad77dc69692bedad1afe4ff449e4ae418c28fb90fcb5f389a36c61cba9bd30f39901c8c0c7d3a5bff6c7ab750e	1662709391000000	1663314191000000	1726386191000000	1820994191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
210	\\xe79d93062f06a866e65e4f747f4a2af520b019793a79ed76c2e2a1a90c07329553ec5cb8deddf12ce41ebf95593fe6bb04f9422b5c6e28ac4bc32b2d8d39a4a4	1	0	\\x0000000100000000008000039d06221b4c58b844fa5b1f8954f343f789ddc08603c1f766942b393e46410581fdd7df88ee80090328c3a754763b4eead1474b8ae0bc2a99ca8b677fe3b5f1210f345d2e2672de232fda67d93737a584293dc5b235aeac4b49e54ca76ea7b83d790c633b2d55df8078707ba045954d70ba07b19818eea11eb3d697318c08571f010001	\\x163e229e64a751e860d6000585e279dec26596c3db59b88ad9b72cc2ef8a282a61e6fe7ea918a9508bfb530de673ffd8308cb4f85756505370133175d30b2503	1659686891000000	1660291691000000	1723363691000000	1817971691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
211	\\xe849421ec4b3b880a703fd8f44b8de3ebac19d266bc7562378691d757b64ceb2c009352628e34520a2b06feba13e6f9271147183912c1b1ca890e8f09ce912c8	1	0	\\x000000010000000000800003effa7f03b61edfc4269b56c471dea6be735e4ca4e60cfd7f59a3abd40e4f12c6ab836c339cb5dc035e01587ab1b544e0973bee87062a58dc1430b2de3d390c7333c336798525f253b89a4ec34cf12633670abeb6854ce3ca4f5e662c95a0402ba051b24e72ecfc5c481b0d9fe8484924941df8ab9b3f6db7bd18357286253e61010001	\\x69355f13c809f16c71a1b89697f79a8838284992e226e3885e629473a614b370c5f0e8a707ab425937c7b0e067b1d87467156016aa431466c79a01a7fe8d4b09	1676008391000000	1676613191000000	1739685191000000	1834293191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
212	\\xec295a80bc458953e592696cc7c5bd9c6e0ca293f4e4eff980add81d9804baf57b209696b5b9a7264065c03591ff2c2a02d697890fe5fc32ebebbe2f02485af3	1	0	\\x000000010000000000800003c18f3ea98cb8ba9980654f296e21cd8311394b6664315820ada81bb64b2ac1addcd7bdb6a0fa54d090be92dd95331a7cd29445898ef359ee3e40b8e9eeca053d282f246f5e0e9a6a5bf9dd1f5d2ddc52fd9ce1781fe85cd7548f0deae5a10de922e53e7565b18d95c4b0405ce09c689655cc3e8f31b4657761106c2fee3a4c99010001	\\x3a99667dc31362bd29c4e87cd49e9e992da378e187cceb6abcf5afa5230ebc7bc58d6812c600c5851f39be4bc6ba113ce2d9f3c86474c69b5385d418055aae08	1661500391000000	1662105191000000	1725177191000000	1819785191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
213	\\xec01afc25353aafd58a5435cc60c513ac88acc4d19e09726d00943bccdcfd2c374079542f1d400a4f63efcf144235cb9a56c4500a9d4d33d8d5ba7d7e223c95d	1	0	\\x000000010000000000800003a063d02fbb1a0ef30935d77b1652fb96251544f41bdb8f240135bf8c4521c3781dadbb09ea33c7f1498edeab72c6aba67abed9da5ed31cd9a3c0859900e2b53afd6ed00308d016c9eab533ddc20e4e70d0012b94b91c64382460adf3f8f2f225190071122b4ce8e7f122528020d1060f5d29ce4d6e772bb15d66c0237a55b51b010001	\\x625fd01bd731dc9ec7cdfd0a033930ec82e027759315718fd29472523dfddb568a6ff264fd8c25eb7cae74f1df831434440dff5bd3cc4a3d57c597d73e62de04	1653641891000000	1654246691000000	1717318691000000	1811926691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
214	\\xf1d19747b051d75397376bb1c93f62293b09725a72c761804f6f56c4778dcd745ebb07508295e43fc14ec32bf5af75fc1bb680450ff76a6f015a2b8d791fd40c	1	0	\\x000000010000000000800003a6f0d6dab21f3d7f705a54eb0da96e690fd4053ec2380b595863fc72ecc0791ff3b5c8824df547a5e955ee8604744e89b108c08723a89da5f3fe8abeabff71f22cb4e70f02f88619adc9ca478638349b1cfa2fe1546d43d67903810e8f8241289569e01614362ae03a979fe9772beca1d7460384b6c272eaf3091aae544ac465010001	\\xf4c1a974171a707b44fd68c6dccfa4a93da11f16493f249d54d9fae3e8b44cb1a89b902e2ef9e81ab838975b31af5f6713170df15edaa661b513480c7eb4f40c	1674799391000000	1675404191000000	1738476191000000	1833084191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
215	\\xf29d7facc7cca1b650190e6431db8061e931098f057d59a9f8d2a94a1164c3815f0fe72f8d44e4147634167b3f78cc3a6abb6d343e40f8f2338d9e966b90d168	1	0	\\x000000010000000000800003d093eb4dd1bd68106f606788f6650b3110049c1cdfab4d8701de68aef84ce2a293767223794fc247c56f9d21dda858b922e74ac79e6af630bc91748be38928b3b907f9da6253156979a4d04aadde82aebbdf86015b4a64cecf42cc68ab07f7f41e309a34ed136996d523fb3fe79e07139263a8effecfe2a8944bcbec5b88520b010001	\\x0bf1ab527a7075edf90e54c2d82931cdcc0c6ca78b32a0f5f5afd4d13c605e8315a9ef2611e2e5ea7623139bb2a089549485cd42e1aa2356bfa8776eb1f89a00	1671776891000000	1672381691000000	1735453691000000	1830061691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
216	\\xf39dd5c670fb3c2c9b76354815d6b936592d8469565e61f4863f02d00f6477801d902d80ee380c26dca10a3146831639f67758b57545b76a5bb08ac1b39bef9c	1	0	\\x000000010000000000800003c6a639b2dce621191ef40041ecf755c65247d467352f3d00ad09b20d188cd38789ce28e54a83426c898f28d0d837f188b39fa3c125cd9e54687bf453e0b325d2d8dc2a5e662dafa978c2a389769a809cc8a452039fa529a546ce89d07066ddf33d8c1e31a7e47d5dff6e0e46833e31638689cea1bebd5b07bf48c1dc2aac0a43010001	\\x2a50aa480d54049d5d8d357eeab4d3f4d59397d7c329f70e1a220d8788d4d9a4b82b8596db3e4f6ab1e660cfa7d076d8b154247f228783e0391c2e2ecce7af05	1676008391000000	1676613191000000	1739685191000000	1834293191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
217	\\xf49d7d0b0bd150483b273868b58058480ed6389119008cb37315ba41399aacd184e3bc7a8572bd2b335034a107bb8ce7666a57bc641c4aeaf6113ef836327706	1	0	\\x0000000100000000008000039eb60643512d615f2ff11fee33867a9642c2af1d3f8134d8130735d3213969428d756c85334e767b776a703bc76647abb22abb622f940abb08b56eba9f8894d491e4399bdc52b4d564a966604780941ed2bb8aa3afe31c0cde902e2585aaafcdc96806e19786293b4698d9c0906d8c55e71950e136849e71ad66841b29f3357f010001	\\xc70eafcedfaeeb68da1524ebed6ac54002e4a1fd3d0d0d2b344e21f2f2f31bef6707e0bcdb20bb7642f952a4bba4d8bf61f1bc0d0bca680f6313c15753594d08	1678426391000000	1679031191000000	1742103191000000	1836711191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
218	\\xf4499a5a29f3ab6f568b68acd98292f6d92404809c25ffe730c71e05cb9eef37fb7e18f4992ed1fd97d2d9260d9a80260a58ef5d1726f69e15ca9d228436a6ae	1	0	\\x000000010000000000800003d8953eea6962384a9832a314b0cad21a9690643954e73c208aa7310c0cf733b8bc033bc156f7c9dfb8b0cf10fc11997147a48c22f0c15a1d4aaf778f02535489d7a8bf1c160553aac746e9acbbd5da60153578c4429628dbe488cb4565d61f4f00c73c2be2ed9a3b719a301f2a8b6926f076485c5fa6f5f48a40c2aadc70d99b010001	\\x4df00ee3d08845011063d817a25b4a8732c3f37bfb12ba8540a79e73b998bd6303f7c8279bc60652228c9110234956879072ffbb40740bb2e3a3332b46149e05	1666336391000000	1666941191000000	1730013191000000	1824621191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
219	\\xf84d2501c3bdc3aa682de7dbf5f119b1c6e8073686bf9f7269ffe8d604ab8f12e8afec92aeafc67df0f93e20fb5e8d783b22a2faddf57533b5903aba170af62b	1	0	\\x000000010000000000800003a4045df07ef1c3d76567052274fc2135120f13a1b1abd3d87cf8af3f1d7210238f974b42b0a6f516233b147553a48310e92dfede664faa58f15ea130322f4539a7fd41a002ef469c00a0c7cf440bc0cfc4e100ef16144dd656932a83a96b4a5ba2e04f95ed000588383202df5842d8a6d9518f33b3f8c6861ae897b3febdf383010001	\\x1ca707a0f56b94c9963c144bcefd5a0e0db39f0f20aa229c55f0632fa5fd1e8bcd04051918d8ea2d558ff10395c0008d366d40f9b384e043bbc4bf66002ae60b	1667545391000000	1668150191000000	1731222191000000	1825830191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
220	\\xf91947fcb64889ddc924300509f3e9fe42b2f4eb6878b6ba3c71014adaae8c5434636dd6e9da2d7d55d88b322622ecb0941a99fe31debc9377b289f1b9dd392a	1	0	\\x000000010000000000800003e58f71e6d5baf6725deb1cc0c2e20d88bd9ef1ca904974ae02b064d3e485d77f7eb5eac4a4ad9c779ddb13f505936ffa9ef8847b1411ffc2c48e072aa4b153f243eaa30f2298b02bfb7f79254376859a0c4cd471e62273e468705084aaa55986fa0b46afb601c5fa742c298e5de5b684d357e6456ff3d07114dbc6edf0ef14a3010001	\\x492cf4d9b23681b822aa2014d141aa5a77a2612f953bf1ac2d754858f65e465afab2f36d16efdf745ff277622667ec1355696b74ee796cf51f53d2aa2477f900	1654850891000000	1655455691000000	1718527691000000	1813135691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
221	\\xfe852499b6b18037681c410b804b30e214aa2c7a282fb95fcd2b5ccb0fd02f0ea16e8009272fb377b5cf9eb5d105ea1f9adffcd6d098a5f82d1d362ad7b66f36	1	0	\\x000000010000000000800003bea1e80e762216a64be0a6d2ccfb6e6ca3c4873c918f019b8ded900a50f40eea06be1ecff16076efc19668031c2f816bd784d5d22d0bca7d27dfe541d1c1328a9fdfd34238c32f3dcf4e51322c7aeb9353eae59aea30037641db26076071ad6e4fc134c2d5a8f0309b1fa34b562a96a142577d23479a0a8f4d81fa1b4989a2b9010001	\\x72d8cd91ed25ac5f220c2e7bc5005f8c9d69caca299d75e11543cdecec073091d20d8164395ed0203bb2ef57873b0c9e442ba18e7f1f6fc5dfc6992433f0ee04	1671172391000000	1671777191000000	1734849191000000	1829457191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
222	\\x0446523bbb975bf6760d76201d11e55fe7dfdc920e30feb16f80d96f0697ee8d6103d5f1d98656285cf33ad43c684568be23781e718e30920e85987b578815ec	1	0	\\x000000010000000000800003cc07be7a1765da5362763179204865ac71736f3640907300659fc96a5e8fd93f97d70eb37f1de414597b3447a50c5590161624453c919abe6b847b21be17996b07b54f293186adff2fef218c9a2506e893dbad0d8bbfbc2b2bc0db9db9d45bd64ae4a8dde1ca91d06cf9ef35445543f93f5263981340677c87de1951df058875010001	\\x94090d1bfc4cb633abcaa4707da1cd72d51c57ec8298d3d7bb4fd4eeb19e062b22e13ac0cdc5693ff00a2474a8cdd2499bc1f97739cb4894de700da3a620ea05	1660895891000000	1661500691000000	1724572691000000	1819180691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
223	\\x08be6ed487f898c727a513181702f647a6b6842eecf2bfacf14899564074fc5d0894baa52a914ee5f333880fdb69065decb38be61da20ed2f86074c61ceb2ff9	1	0	\\x000000010000000000800003ba96821e4e6f89fd907bc62f3d6f0e81fba3823b2c3460c6327160c16a457df13e867020db596ca7f58f87dfad9c2636fa461eef35473619202052d95ec9cb329ca4a9f96e58117f52a6a01be357b93eefae097e0af78cf66e4bdfe8467238c0e7efd548b7758299ac2776daac7ff22e8c1c52f6177471015e00b2ed4eeb8b77010001	\\x3aa25993e4b507cdad9eb0d287e6fdff65d6e17505e6a8949839da924d6d06106221d267ed9482694671cc0e505249a04f5ac9071c228545c86143202aef1200	1666940891000000	1667545691000000	1730617691000000	1825225691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
224	\\x0b9e027461c16c60f858a6a9d5557bcb57cc6da7898a8537c1950926c46d13a63afd8dfcf2d57a1ca35ed23c2db011619de4bf269ed9c8bc9ee16d220106f33a	1	0	\\x000000010000000000800003cad8f61353a5ca4e2e3d9ebe564c0bd4f2570d22b756bf3cac3266422168feced52c418b32741ecf583c4dbf46de52a345c19a62075273c7755526504734afd145549b11e8fbd2034c82dbc8a2e5d66c40823be017b4ddfc96517154c24f4e8c125300236ca39f3b7b25976959f11b510c5c7e13a1694d5b6efeb9770a288773010001	\\x253a5c1296b3d80a9c2871594156d121e7350e39e00b03efdc10f371dfd5d99ef127f7542fbdffd20d5efc91035f2d1cadc35e855b99667c1c20eb680c9a360c	1664522891000000	1665127691000000	1728199691000000	1822807691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
225	\\x0f9639e41ea41aa0cdce38f68174bb7d06beee2c5cb727bac20bf389a0675597ee15d8fb2e3aa063a060f42853b650ea695d30f0afdb653b884f4a6de5326332	1	0	\\x000000010000000000800003e09120d17d6dc4c2fade878d65d2a3d793480237bfd7b2086dc96a67b49e3ddf6341f6ca958fb0df2c84a6634875c18e35f3d8db926684a1f6069cc3eb94272455e8d90d8a844b96c0bbce821a23d0b53e38b76a4b04af0d72cd9b34c458ea270d097faac8e8ec5060b676938d6ec345c8bb0c17396066240150710c97427e65010001	\\xa43a0a8dbd8331df6a4dfe9648b388ccc11122b7670b6cd15e48ac1290b9159efdfac969c2acca3cc28ae2223051c0307d5bc0e130082da44b7d275e6c23e801	1650014891000000	1650619691000000	1713691691000000	1808299691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
226	\\x1266b2c9c4ba217d61d7a5fb973c53fec8472f48ef2fe65c5ca9c265c0aa72324912f6a9b446fbba41e417be467de76aa62bcc71ee220f7088f2d24e4c7056b8	1	0	\\x000000010000000000800003cdbc4255deb5c4b9f1e0442d73b6f410ee9d3783ae53b8452785306764715938c339b6b3c242aa6676623344ddfcc96614a561542cead9d7b99cb341d6d517f7abbc16e7ad41afc287ac5d9bd729f8ead06578d14a3ca12239007613727979f22b1a74ce46e93cc94d20f532a8ad207a46e3c222aaf470878e172715c244140f010001	\\x610ea04c88c87900ce1512bd61ff401b4e5499d88c85d3452f146f66758279d5dd7641d5823e5247acea705b53b590612010896242457aa43565f4602ec69e0c	1652432891000000	1653037691000000	1716109691000000	1810717691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
227	\\x18da43e2808d587a006aafcded3e8b2f397f47ae4eb69cf7b23176e4b0bd1f035f0d99bdd91b39db8270ec25be3ef5ebbbd8f7cae8f4eca02735ee04b375c91f	1	0	\\x000000010000000000800003c5a08ec2f9f93c79115777b2de125cd6d2981fbf3aac0766dda42228d4100fa93ed51d3eb464ce6f57f6213fc53a32a1b2fc10d084243841cf534c9cdfbc5ee6db557506881e6bb52aa174d90e49813c0fde6d62a90cabbd284345b259f7b66da1b967e99c3646b5b70a967f50ebccbcceccb7f6369f56969623f4cd607b6ecd010001	\\x353f6685e9b67eb8ec306630b41cee1070a2968e72fd30ba15bf11422f6e09306412a54630df452419471f75e1756cb86215aa1f3c0b990ea159557469f9d901	1668149891000000	1668754691000000	1731826691000000	1826434691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
228	\\x19362269b50a5cdd4e518fe08d8dc1d2b19e551fac795f05b88fe493e64b94ef83b6c6fcef55634d52befaeef0d03ff875a064d5360ecdddd006f430a28c305f	1	0	\\x000000010000000000800003c3c6465f6ec750345cf463dad19c4fd6fa6c19edffe929e822291c7939d265239d7fb5523bcd6f01045ce4765a35c3f7ad93393cb00b3bffb5512a0777edd3a18db5c3607cd2ab4dcdc4fe76874edb7518de13f0acbf1a503a1a3268de196eb53090de1a7d8e8313b4109e290726cb14a4db129cb1ad03dc9e64d48de90ace55010001	\\x093083d7af787cb5eefa68c4f86634138b3871a3e8e25837d33760a23ddb0fce08ab9ef55ca04eb1bb79f7c4fb4dbbba29f699a21523801270cf3316b5b9d504	1653037391000000	1653642191000000	1716714191000000	1811322191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
229	\\x1c32c3e0e196f8ef06853956e1dc7b85630401710e6e3e13e1d952f425bd5219e91dea134bcba4194be3374e51b1a1aecb0da971210aca5c30ea2cd1a950b1e7	1	0	\\x000000010000000000800003a3cd58137e2ca7f67b9c718db7d3702ca9e059ca3f2386a69621f2cc514ed80884c6f61b38e351ec045a06dc6c43a3556b1b624b044e44ef3752dbdcd574f6457d0eef29b88c2b09643e239f11374de7ee03765d3fecc7478ed1cb909014de8e4a9795abeada375cca7dfe0446988e7f431e873361076166bb5b201a619d47af010001	\\xabb88aef8cc51b4fc7a3edd7a52b7e10b0ec87c077b0f663156f91fc7dbde4c2db9c1e2987aa678b41de169fc8bdafa2ac50f5ef6e6481151c1941ea8f093e04	1668149891000000	1668754691000000	1731826691000000	1826434691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
230	\\x1f0e37a0f108cf12dbfa96f256b1fc239b021a84ccf7e9eb087eb4d67b26aa13d1d44e846c2f760d2c50edd6a77c6f902df885368e1171cf569d8cbe8f46ddcb	1	0	\\x000000010000000000800003e3551e6d516be2bfe1fd9ae7e45e1979aefe9a76e21567306303d63db326dd84b1af642b16b1eebd724e38249722f4979ea66c9d6450c430108209dbc73599ec809c0f55936e0489c0a0c335df8e7d2907cbe63ec20b209d083d0738407efc579efb5586726b97b46787a210e873196edd7a0bfaaccc6271d558e3f449feb93f010001	\\xa102442e9f6bf37c1e62e323c562f17e5d71f845ecd36fbb084960b3569bbfa2919d9f86b1e41c4b9a750b880d1de6c542a59e04eedbd4ad78115ab12aebc309	1658477891000000	1659082691000000	1722154691000000	1816762691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
231	\\x202ad6693ef02ce085ee93dada5be3fd52288f803e52c86ffa428d4d592dd537547280757169a6de2a5fdae2b1c0e001c0a85567fd743438d9ff96167239f2de	1	0	\\x000000010000000000800003c77ac18245050b58383715c7d373909a5e1d836227846f709c41fad90cc59fb3cd5b3b066f6c57b9a8d0dc5bf56da21cd1a0bfafb51d1ad7cbf3157d793085ceaca452202ac11944192af041de593b0fa7d4ca71c46517a62d3e671970a00d793ee6bae117f58ed595e0173f544f00527a153e6955e1e7eeea45ac0613ac53f7010001	\\x14e52ffd4865e6ab11937b0360663ade6599bab2e9e78060a351a1241381dea0389d11124971aeb5653d7bbaf4c386db48c3e668f7bde4dd33ddfec0b2439104	1658477891000000	1659082691000000	1722154691000000	1816762691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
232	\\x2156cecb2a752c8ceff6632459049167179dc77abcc4c6551a3324d9be22c4efc69a6a1481d9fdfe9be14b4f58b4dca4a5dbe834ea60a9e06d9f8fc99339f9f8	1	0	\\x000000010000000000800003ae8139e1a55f4481238db72499b3e29b1b35944f2cb8d6e5a340a1988bf853a24a5e5206abd2f4e81e5cbb50ab66cdd144c8a41c53bf31639da2f8e80b69930dcdfbddbd7ac2eef56e228b197011b0f889210115e7247986ae8acf4fa469d4fefc0ecce6880ccec288fd2a15e1fe4ed4ddb1b01b5e8e348bcdccc30cb7eced9f010001	\\x2af0db1a763ec48d021169c7eeee31a76ae8b8e7f7025e90b11c9c559c3527d05ba84e812131ab41a599c698a17c0aafb94b718a99ea5353504aa3868a76650e	1659082391000000	1659687191000000	1722759191000000	1817367191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
233	\\x23e6121ebbda5953db262eb930fcdc5195d814a74338d011e78b5e7841b5860ee2cb90810535087bdc72d853123450c4857738cd2ba8e901b4b75aed76412169	1	0	\\x000000010000000000800003c3a36344092233664b7afb68473af19fde564880f96572b360ccacc572d3093b2d35d5faebe790847994bf37b9713881cf5bde29bce6453e1d3824b440cd480c543712402a3b7e415fbc87f89ec3eed2b394aeeb8b68a057564b4a4c388bd2add2b4c2948e83420525eb6910751a1a0020d6f6428df326041208b9bc261976db010001	\\x83dea4436089768f9ef9aa5f49ca3c81548bbb605a041e1951d8111940b5aa143ecc3b9d343e67017367d659599c6c8cec46c7285e02fffbc9d1dc3b1c19a204	1656664391000000	1657269191000000	1720341191000000	1814949191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
234	\\x24d2efdaa4c6793458be1817f33be061b865a3a864a71652e93b9312ddb414f291a47ff08c8644b7f5dddaf633e798aace9b724813c4500b4e6e4cdf609c8435	1	0	\\x000000010000000000800003f697a509a8553d68c50d0f14205637e130708160ef15a6c905d316e4a25f455b0049e0a3b9cc5c7c85691dd26bfb4134541f4dcffd06343f240d17560e22241bffa1534dac4f0d8f79d66222ede6c445723d8f9f75f9c96a6d5bb58087b6e91038583edf662c585dc122206ac2d41389ce90a4c358da6aabab307cd002adb297010001	\\xc37d0a3011d1b113eab06a4ef5b4dbedb6ff7fbb4bff44ccbfb05ef70f291f74baab224831a97c02dcadda022469d2b5cc85f5c9f1f773783cbba091994cd503	1660895891000000	1661500691000000	1724572691000000	1819180691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
235	\\x2a9ae8e08231713f207363918b6424e36d76e3acb52085534d8a655b8930b714b97e581b58ef453a23fb1ba513c1de46379892579e4f124902c5623666b88175	1	0	\\x000000010000000000800003ce1d097c5ec487901c7969b74fbe0a0149af0a7c38e9d8f52c73b0aa42088cae34524f450aed67ee358b1f434de9ab16fb254ce036c874e35126587d7df2b126e3a0c45b7ff5915b4f7a0e14e920f6e68849d0cadd0cc67413e0c98b6be78490cf34f9db4f690d24fb0dcd63f1ddcb3e2a9eeda1969014168fb3653ec5c782c3010001	\\x1dd81a521e6035fde57d60c524e28c0b5450e5f8c722f2ed366278d064524a8d00d174b96a8d75a39849dcd31d1e74b6bd49059c07ac01c65db3a57adb34d30c	1660291391000000	1660896191000000	1723968191000000	1818576191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
236	\\x2b6aa191c6860f86fffbe2174ab948161f63edb4dae922e4e8d0146bb5cd2d73c1735e7220b3e18516c415612c375f2dea2c0df2b924b811d14106f7048735e2	1	0	\\x000000010000000000800003d3cfcd8b8a21a88bc67c5ae1f66af1b94b6b88cce4197fce6c45e948d6e07d28add48f4141d5ba77590099ac5352b041c81916fd84ffb4a09c44ce0419a12e82e726b38c188d4d652d172917dbb272632508d3bf56b748c616feefe9fd5b9b797aead420e6c896080e74cb0449f9c2a17fe10280970a24a3ea444f6844904087010001	\\x91123595b09a65e0765a2ca7a9bb27d2476dcf4126b1d64c18598f00bef092b46da8619f630653fd4f112a822c94afce3da6d49de968bb94cc68f3a23d036107	1672985891000000	1673590691000000	1736662691000000	1831270691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
237	\\x2c624b0a41ba945c105730631da4ea86bf1182a513561290e5bf146f4ef97360fe74c84801fbf2f64fd619d5aa8cef6fc4839bd7262663542e13c64a6af3ab1e	1	0	\\x000000010000000000800003a70c450ed26e731b7b763d711b51303c42236c2af710a79ecb7b81558d1557518fd4ecfc79191f2f00ba0ddd1946846af31f1f3dff692845871679b3c888caacdbea3e53686d8309f436b150db742e401bf40a47a081ad8540ee3044e691e293ddc1e6dc9b87760e50c708e6533ab4e1e9df063f635dbab8d27aed8511e80385010001	\\x35bb18a12a49ca03e56e3e5a2303e0265c82fee80bc6f5cdc9b330f69c69071f850f183fe0bad0daf40d499c6262eb400e440a9f49da69006455f9afb3559e02	1680239891000000	1680844691000000	1743916691000000	1838524691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
238	\\x2c020886219bd3dc2e9734bbcd6908d6d8aac0335f07cc255c9fb3f650c5db49a0c20d1b2fd9e9c364cf3c70e9a45658ac3d66f238e17457a69f0da1fe60bbc0	1	0	\\x000000010000000000800003cf34d26f090d7b67d179c0abb808304f825d10a12d9d5f938456d2ad287177776387bb69581210ef4ebaa6e1d1e81bc4cf535eca28ee92331d6ff84848738308e4c708e0620ad4d950847373c35b005cfe9222cb73495b78e35012e7912631ef9e46522ac96d6eeb9a3638b0cb07558d5b61b83cca02f6ad4bdbc43aa301ff5f010001	\\x3f8876687c57f7dfe057ff29a073dad630ca705a3368631fffeff4dd3901d9642a39b3dd549c5cc79296a4b1da48b193b2b109193bf1a060396ec211935daf0e	1671172391000000	1671777191000000	1734849191000000	1829457191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
239	\\x2d469f25e2dac4563db8f5b5d5c925c8b6eec8c01e6e1ec4259c89e85246d29c59cc65b9e7d623df65438b9fdad0df3fb7217105919a6a05d6011adfcd1156bc	1	0	\\x000000010000000000800003a998bac366029f00c52aea73ec9a2fb8d701399dc24617288004d0e7af62287893bbe2bc9bf90cd2de7c660042cc23e3ed143fe6c0077506249dea14c507012d7dfb6810ec31d0737bdab8b7322c6a9e4e0f49feff3c4c35531e9ddf97c17836ceea5e37749855fd2c6ea7846dc5895658782c679173198d2067dc88027b7ba9010001	\\x0335179d007dcc776fcebd220c40753dbe090da2c2c20619fab5114cde62eaa3127ae370d1716b0f5b8620b9c2ba90baac0f29a5132b5c5cdc52750d4fac9a07	1653037391000000	1653642191000000	1716714191000000	1811322191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
240	\\x2e229b65ccb7f3bc8eff77a0474671a8330d97d71c2fa9c9f5a8618d4d99d7718cb922c9d34347984bf38251ff014f0bc3eb6408807b5316d37c87815c66553a	1	0	\\x000000010000000000800003f99cb53946885bb43371e8a2ec5bf2e11ebdd048d67eafdb7940a527d60f29196cce9d4d5b1910fb5d9095abe78903d0b2b659800ab07ab88249580f7fc9b3ec31f3eb9fe38aabeb45299f79f6ecfcd697ef8ace0a60c334405b425900e51630bc79b9d066756ef9b9b95744bee242f363deeeeb78d2f3c2da1099754dba84d3010001	\\xc756bfaf432bb48d07a1cf1108eaec333635ed7001ed6a61f81d74e165450d7858012266b9c4a1628fbd0861f26b1d2464ff87d08e79ca229e7d30a42e061f08	1666940891000000	1667545691000000	1730617691000000	1825225691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
241	\\x300ea98861cee98bb61adfe5179dd81fbd1ec1e34b7b6dd61c342f9160855c59d15cdb505a8e9c6ce5528ebad70478a60fb4ee1af0be9bda77c764dc3427200f	1	0	\\x000000010000000000800003b50dcfad64aea05f19dd672f958059368c750f3bc832b753982f90eef88cd57ec9f3e1d6b5d619bc75a575cb35d58484de8dfe6a6900a02a09c27457b7ac6f28b9543190aa5e1883033c26eb97b4a2842767fa3b799a8827663b7f6c59a1586ad3e823cbf7d6b2dee41e72538627f15537b541ff9cd8959623043ff8a1684039010001	\\x358264c40d1ec83d6a7feaeffe05e9b5f108b17dd6e4c16718bb3d119a36a13c297fc3d867d846c1c3d11a916816de50edf6be0134c11186ed50fe2a2386200c	1671776891000000	1672381691000000	1735453691000000	1830061691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
242	\\x31e6fb0729f27f0085cc699685c010b6549a8509c3c25b34cd085776aa47a79e701f607556f36d8935c0dc9af083e1a5c5368118209bd3d73b7a8261952cac92	1	0	\\x000000010000000000800003a7ec37a01ce93c0d75a6e878be300266fe96fc5788e34511a9ba1a5e82f113838141507101e0fb66c0b2a1fe0703f04a76dadee9eb7eabcb04ed2b8130648e4f4acab9ea7cbf8835b16d57c7043ffe3a6acfc35dd794dfc425bc8f2f0a394718b87fc97b2c402dde0267ea40e69ec735f91cb7fa3c980dbf21dd139026e92135010001	\\xa332c6772a3fee7b82831eee0a2bc952749b9c6d24d7e1ddf8e18f7ebd0dffe38d63896bca141538652acab6f3a11118ef25e7fc481e37a287ee512a3c342404	1668149891000000	1668754691000000	1731826691000000	1826434691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
243	\\x323a69fe5fa634940fbd6b4cd788fcbed3d8f2e1528ece51ebab0d97161171dc2597ba3c07beb14d7c43bd4e4f10a0357e5f706f6d7cf12965220d532eb451bb	1	0	\\x000000010000000000800003c76088dea05b97f3fa8c3a6bbeb5a5eef1cb088547ef58b436a28744987a2d8eee23a5fbee0ce598aa217b9a8b34c794e3afe8f4f00281f9935b4585224f25c5a2261f16cfce9229a76b690d841cbd5bccbe35549c5602740c011286864797a5528cda4b7b1c3757ec66ff08527d15dfc3161204418c7e3feb467f7bfbe38d91010001	\\xe9a4a0703e889dea794bf44befb09d29faaffc0edf9623f9dcd69812323b3b725010694cb71161f1835a2f17fc50f602880370116ce0f95464cfad74f0068707	1653037391000000	1653642191000000	1716714191000000	1811322191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
244	\\x33921cf05e3b89ae407750e5d82c5518a60ae64b471b1c36f8361520a003d45b6d459ea53a196b0eb41d8aa9f6e0f50859d4bfd8193f1d9d8123bb6903a64305	1	0	\\x000000010000000000800003b911e22ad650f6352dbc99a360c088d66ba32d9f2f3316b7cbbf3808e4349f8d63a9597abecb03fcc582837747891f79370ced0f622b12458937e4f371e847e19639f7ba7d574c03abfb708ba0914e7d016394c4c1e8157148ab4cb284ee5eaacc0f44a0ab9d112905be15a2e195c3cc7d8cc198c2497a645a2635d9b278c317010001	\\xe364021ec4aecd563641479b1b3acff75c3ea7ca8982f7fc16daa978f0741c63cb9fe3667483f43ba8e816078c18742591175282b533350a812d5b80a1b58703	1672985891000000	1673590691000000	1736662691000000	1831270691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
245	\\x349e07ac2e15831bda0db31f6abb66cdd0f8223078f40b1b4874c250058d9f28657fcfa829d7330d8bd2cfdd5453cb0e818c884ef59ab12ab664091a2bf81968	1	0	\\x0000000100000000008000039ed5b469f9515ad73e43b1de42bc1f154fe81aa883f6ffac1578b009b93ff59696304908ecbaeae9a65a9204b0387b523ec9894724abd02294ce9d01f42ef5fadd3540b0fb7f6f1b0479dfb16f3d146e5b8054ec6a7add6419df7308689eb9515b0d6647fbb924702aed88504e24d7d23e6114670969d86b87442da999782ab1010001	\\xc1c9bdd9c2c5bbd6a8a711e11105a64bc55d9650df87215ad013d480e4f48732d1024d01ac722d9c1593ea0841e39d96f8fc4b24f2531f0a35ff964a653de100	1680239891000000	1680844691000000	1743916691000000	1838524691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
246	\\x355624994eca4e94411614539d16c970d799aac4aa54347cb983e094130f896c4a498baf9ed675d790de170f701c1a8430e6838ce2fe57cc2d17fa2cbb36f36a	1	0	\\x000000010000000000800003d59c1d8756baa04ce0d91867373a7ed44673a4585b485cce3c74fb86bae4f04b5e0127363470554d6917b3a49df8bd9d5d6b6bcb73198ddbcb96b9d7b4aed3cf3dc630ad7f06505c31f752ae81aa7a22d79b69f03d70612e0de544cacebefb5f1b7567d61008c9d48682d86a4ee60a541772895ac86cf2132e95444ea294e583010001	\\x344041d05ce46796d1ed55829d5debb5b0658e380742bce786c7a62b7b39006a8c8940c79598ccfdeb80d76f47259218e22300d778ba54186cc0f37ef864c70a	1671776891000000	1672381691000000	1735453691000000	1830061691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
247	\\x36220f328d34b365ce31ffe87734ef5f929e45120a8f392ba894c2663a4a2845e76e0ac9350be70903ca55414bdfd22b956bfde99424f105c789841769bf0b4e	1	0	\\x000000010000000000800003c49800a66ecc9cb989d29b27249dbc40b7917676586cbe0c6c10719d708b2d8fa75764a7fe385102ff17ebfeeb2e756522d78688bb74673940de67ae2b79ea73181edf12e8b398d15059a2c0998b823b255d294f1e5f33601108774b01738468082a8693f345a1220c510264a264b66ddbefb8d9c35aefbdc6ea9a3009011c6b010001	\\xbdc86141ea32ad5433107385ddb8511b66b0c23f1cf38dd96942b667d29683621d560228bdf3370c25427cc45aa51cedee2da56e1c9b0bfe9033924b12f5bc07	1669963391000000	1670568191000000	1733640191000000	1828248191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
248	\\x38ea9aab895f1e9b02f0914f4c43a4c880cd24d20e1e6e88509c0776a45d2acf4c4d4abcfa4ed0be599cd2b417839860d9ead816abb3d80d72ed2186c0e4adbc	1	0	\\x000000010000000000800003aab669372d40cfe779cb2595d664f4c5909f4f9f0e8cba30751f2e477c5b5a32e9376f98e6150b46049cb275235f956dc0dd442ca1371f994f6731df9f987570521b0df039a00f083b2ab08c54d218915c98ba55be320f601dc834ce44f8329393edcef178287ba5da62ac81d56df2041c43a8ae479a20f1d461dea4e7562c11010001	\\x00b8118533202fef2015b4971482bb39ef30848feaae2a7a7165e5144062ceff43b43bc48ff10527552f5afa102fee1f60d64ee4f2e5c6d3647d0a3afeb31300	1656664391000000	1657269191000000	1720341191000000	1814949191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
249	\\x3a066f577001a5cd7bb55a743e461cc2ad2555983ad403053c627cf3402ee8e51786b9fa777034dcdbf5efd1c493c1617585e08a2d192433dc739dbd24dbaa0f	1	0	\\x000000010000000000800003b9f6ab8832883fef2e92502af44c8b6d3af0360f889037fb08e88a689d8f565c39e5ce26ee69295c2e43d7195e6b86df6748a3b0265dbae79ba5308fc1ba5cf8e77ef1d0b3154603f4957ece3c3acd53a660eac8c842c68824eef7738cafa4166bfa91a84630715aa6a00a527455a6a777e6f44869cdc5fc1251084507e5b82f010001	\\x3b2714b08e62d21b780d3f2f04f62187438bb00b6fac6554146a1dbf20bc3196548dc536772f923d8cea049512985f019e9d4b63d5d42c3d92a89f805f0ea209	1664522891000000	1665127691000000	1728199691000000	1822807691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
250	\\x3ffa3fdc3756c113df1b031862ed7016120a67cb7d39fdac9b5e95698540548ad1083e329086de499c3a773c291d899e7802f869352ca211af73a823747dc351	1	0	\\x000000010000000000800003bc3d614c259bd3426349090cd4fad3d5c2dea2365f792501292d4baef63fd50ba631493a1fe8c08660e58cc8dd60823407dea27c9032a339f0be66447ccda86f1c69989bada9961b52f7b22314ae9b47cc83c35b2d6d1b368e4bb8bf2c3798483ef49608f62f5f10aa4a096bbd18db8793b3a6dc33a3f4108a493a23865e8a79010001	\\xde18be7f07668909da490bd834adb551d808b05125209933c2569ed7665adfd5d93b8c8c40a7026633f8a37a0f50008be8d2f9b942cf1259ad64237bc58baf0e	1654246391000000	1654851191000000	1717923191000000	1812531191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
251	\\x4086cfa576395172ce8f4994f13c538b2d6fab7bac3e8b6502ba98124e8ba761e7475df5b92acfcaf3f34b449810b3259a3bea53c0875911aae04e43814b55a8	1	0	\\x000000010000000000800003d3d4c6de16626b94ddaad6d7648d607f61f685409840e5ec172dbbce778de90743df7fb1e95c0490c7eaf4badad95b2532becfe93b378557aafa72132bd9cd9ff663b47d70eb850de38db70d422cdb367f6159f770bf27315f508a7e7998ce0a85b336a4cbc72ca755a1b2cdf444483d7c601b776d03b7fab8bcb2fd7190b9df010001	\\x0e72efc4130d79d93f372e0b94aedc57b20c950eda2e466514dead07f5e0e52702b4c50690a5743a68f9780995cd7a1e69fafa27a940a08e1d21517e6268be0d	1658477891000000	1659082691000000	1722154691000000	1816762691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
252	\\x426a9c2b1ca81640b1198510a1929ba5f018d34678f9ea13576ca0f76245dfc42ed32284a4d9a193d35917fa6750e20f4b0a30d7ae754233cc534872054359b7	1	0	\\x0000000100000000008000039739b1b99148dca3f2f1750fd83c2143d33aeacb05d72f105dc51e0a1039974aa06214a0de71fc7db9bd41720f2950266877dc6e1d6b0fd6cd5daf97f2deafd7c728675eb6fde9c6b5cadbe011ef7900cbcee7524a881beae18ec2d407465b3f28b80de2f8d1fa78d55b0e56780119df2f2d62f82f9d54f8d59f101753839a07010001	\\x8589d232508a4080324fc6fd39df44e89ec66df156276c12d75463ee31c3a14a2797eb361e8583c11b458620b88333dc10886860c952d4f1e10f2390aab4a20a	1675403891000000	1676008691000000	1739080691000000	1833688691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
253	\\x427af04fd2c2e6a8b05a0b9d31014e6e0f13832da807f375371aa1866065b61b304edab09de04f9ab60337d902301f4bd7313cbb4505112889538952a3643643	1	0	\\x000000010000000000800003c075693192949abd9dc336600dc69340059f286d41b6c6d6b7d7001d86633f6d29d8e093947c13fe783c6937a6c1e04efc1006f2a650b8d59b5b54ff5bef092c3d40dc32afb692e0a5a4549a08470b866ebbfe90c944532e66a8448c3dd01f4c6321d500610fbb50b1ef9bc56099a6802f318020e29e313fa1270f8c1512b931010001	\\x0ba9e99481c26343f82ba771a1078d513777e331ee216c903ba8cc87e0f19ab09dac1c598878029a9f7b702924fa06d739f4227124e9562ed93fe8d2ad038d04	1675403891000000	1676008691000000	1739080691000000	1833688691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
254	\\x45b6ea88c9a851ef386c84667e7d23976b9af893c0eaee28740cdb62aa310adc738594c720aa8a3dcc3099d86b21a98c77a8e29ac3e1800c5e969d71e1ce6587	1	0	\\x000000010000000000800003d55f998adbd82e671a145f2e9026e8136d0e999e1e8c5c55b2f44acc130f92efc1a4f7f23afccfe60fc7b6c693616bd00c25c3f76c36307406fdf252e36264b0fe1b13ffcf26a1d9242b24eceb01f942895415c05d0c11408bc214eb70a2558765e469743b8d6fcc126b620368b2d52bece1be177d738781f7cc42c5bcc6555f010001	\\x294d0b1088fa1244d2cfdf84ba557589f0788bdbdcc5e7ea5e7a3b4dc3790c38d3aae2eedaffd593774e4f0572c0a7a500ef40c506f0b17f9e28a2e83711c706	1654246391000000	1654851191000000	1717923191000000	1812531191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
255	\\x4af6ebd15fc6636b632a20039a3e80cf870f005ca1e6bb08741fecc0af7754bee19156ec85c718577766d58ed32f615a77bc76d824dce6f2e80eb65293921285	1	0	\\x000000010000000000800003c1f806e2b39d8718cd42ccbb35723c11c5cfdd3b2773817e78f400eae86d15a4a7d19fabf0e8cf9a596e6f6099fc3e24ff63dc8cc82d4e6db8cd9ad9e27d0cff216ed66e306f1fc310bd43525a38750f0053a3758557294097dd3c334f3358e05b8d311c277fc6119b14790e67e1f04a243738467fafc6551086b4488175c23d010001	\\x3f9ec34fd0ee0989396102461ab6c63380ea50a2626bc7498e6856a7cac36feeaa41b435af319bd45ebe436c01988f4dbd525c4a7171de6a91cb54c760ca3203	1654246391000000	1654851191000000	1717923191000000	1812531191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
256	\\x4f3aa73048f24e83f39fb1a2a9e037dc6f6a93615ac9993f057ccb670213dd6de031c142da5d4db67e51876890415713ff279f3a02aed62c6064bedf3d5ba834	1	0	\\x0000000100000000008000039cf66af346454e032de8ba2249e973c403d6fd12c4d2f1575f64eac93e9225b2db8955a0c2cadf95668221abfc70770887fc099952e6f20f87d233e27ac2ee322b94444d31ce4f8ac6f13ebcf18a4032650ac5ce5e602980bfad7a70860d4eb76798ec6e7cc1454539b19e6f0944e7afd5883cb3ad0e998c55230d164f3329fb010001	\\xc25272c0c46f4931bd78b0d25774c6533c04a295abb22adbd02b6ee783cd8e229c412e80eb37be327c4ace3ae8199e747503747ad05282fcdd94b71e419a260a	1662104891000000	1662709691000000	1725781691000000	1820389691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
257	\\x50829648a0090b63fd106e518037687e27c3488bece921076bc36e03db7e1c57673a6f1e4784afd2b32db11e97c9943f02335d5035cef612b9fb4eb22f06663f	1	0	\\x000000010000000000800003c5464b6c9f2c48b356327e06dbecf691ef4349e5bb786a6d71beca526bbb18a41e0c43173ae9840cd3b3ff7c3e63dada064c9a635d6826eb83064ddb13a96d9fceb7207898fa4836b7c3e25ff31349735036662c2fd19a82cf8146057915d47dbd901a5fd81bd670669e6af1cfe3c58797ec027dabf515dcdc677748244f7cdd010001	\\x4ead008ca56a1c6b6038b7413018a389afcbd70d0c19376a60e7fe8e4ae37d8a79b3a43154eec6e552e80605e7d3f852f4c911588c8d5fee34f58772da33f30d	1674799391000000	1675404191000000	1738476191000000	1833084191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
258	\\x555e89e370a8ad77cf0c2bdc92d11343d8c8968bd1f03ea79255b434efbea8bd43aeefe5485f63fe2f9314b1bb3d14ae01ad9e79d4a047eb15a7cba577028059	1	0	\\x000000010000000000800003c40c335e23e806b68f0f0165dc928733b1e10cec5560c082afb66425d354827fd316d307e2d70d1e3349d25d8eb89ea41b293db5b48c7aef2a2b2fe6d6b8014dde6dd64fb336e19cd989f11004794d511695d4c1463362c3b145f76c63c65c12ea4403f848d8407f0dbf428e7d0e41a19f33800b04869a4089ff02384e4d004d010001	\\x9d58e56bb05c0bfa568083881eaf6f636f6693f63f8e8c6966e1ab041e15f5e059121d48db78a49c388b96380d85c9ced90197f61360e218ae6a3854745fe406	1663313891000000	1663918691000000	1726990691000000	1821598691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
259	\\x5542af12823e497c30e1381b228df13dde57c103b8218b0565e827204b74c13774cc8678538bd6ffeeb1324f7cef87da086db9866c11ec2f23bd2a37e644a014	1	0	\\x000000010000000000800003a8eb92e2b844a60e47916b0e68d5068698de6e967c350dc9452b76b05105476d0ad625c456244a6317caf225de61d7cbe1a2261862cfc6d8e98363262d1ba238d66a27658c66067e065afa628533a8c93d95811b84836d111abbbabbb8ea51976cb9f5943661502bededd0fbc9d03ac6e51487517f0e7090f5eb0506d8648a6b010001	\\x5dd009a84c8e437ace5d1fba76a6655ab71824c9e1567c732101ad92dfa4bca38083316ba336f1f718f1a580d313a4a4b3502e85b2d5f0e40f0828f3723c540b	1651828391000000	1652433191000000	1715505191000000	1810113191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
260	\\x59462871c352890920fcc3dc9226b829f224112055ac2650a8ee82ec824ef570fb7448e691c144afbc35e67c123dab4afaebaaace54dc7121eb0fb3856a7cb05	1	0	\\x000000010000000000800003b519209ad40abbe75a69b89cf527bbcfa3aca73a5e3c902c2a0581bbd7f6bca452aad95044a008a4cab17bea1f246384007f88740ab29bb7772eb681e4d0c6c2670a553ec3700b51a723a3d236d0f0a0033651e3545622e0307ea4b3869af07496f6df03fcf232223056f801808622b96d0c02fcdba308a966a83ab9641fe871010001	\\xb0aaf03ac69f079002bb51148fa726f9189580cc9863540ec1db14b5a6943bb7be1c979cca3284e0d3acaa6ea8b94881e76c1a9475bea44d62ccbfa58f0c3302	1663313891000000	1663918691000000	1726990691000000	1821598691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
261	\\x5c9a03695b9c317d17df1616e6d96594ea6116c41c4f94425d173911e51f4e75efec11e7a10513c10d1eacd05b2b87ea7706f3ea7ad564e2e23780096895f3b3	1	0	\\x000000010000000000800003b78d6b4edba289ecb959b236e5188b3953aa8b4849432e793525f8044528b5b615b7e6a364248c61b29fe07b39d94992823e22b1c5e3e2a1f222690dfa9f4ab36043c985b5ccf27a577a9367eb232ea375082d2bc8d4759f4a66a8783cfa8c0e00397ab765df2c1386ede2352e837b9e8921c03132ae20f93d2416caf0b8084f010001	\\x9a82a98642ce8d7d80dbaa863f540d24a3bac125e7b133f61c2ad6bf2808c0b0e749ea905b8038d6b7d56e7774ee723781f7762737ccec396a2ebc887f995b04	1679635391000000	1680240191000000	1743312191000000	1837920191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
262	\\x5c4afa19d28d0dfdda26311c9aa8096d8cbe60366812714f2274c1e8b3b40d7de4f731cfa1864bf1958337c90ab452d2c7a33dcb2e95a8f83bd48fedcb8f720a	1	0	\\x000000010000000000800003c646613fb75b47939616eef5c5fe8aaa0a882887debbaf85881f8f6f50d4add32cae7bcb09b151d0c429660b06b36e9c008cfb6ebbc9eb4288e208b30dff84a40585aa3bbf22643936424f5fd3b5cb76af0b1bfbdf874622031967615c4c803eeb6860631eb30b94cf2d7c4dbed699b2e72ef4fdf24e8ccb00cc7db5659fae8f010001	\\x7c8b05ad558f3b29d40f1aef8aa9c3895af31cff6c488cdc3cba4c9f1e93103eb11bb522dbc18c2297dcda0a5b4604ed7dfcc3b5a0f05f959485c554c5562e0c	1680844391000000	1681449191000000	1744521191000000	1839129191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
263	\\x5cfa31c53ce079a7cb5493aca30c9e415ef423f6807144f0c273ba85e72428aef15efbb7368b024633db5aff657ada4e938d70177031ebbd19a262e16081e63b	1	0	\\x000000010000000000800003a3d78f624ad491a2e3601483d8a91561a03b3f9263d87996070de1647e0bcd6ca20389239f6088ea8a1874333243a1729729bac38ebeaf5b51308379a430cc3f8a89a242b35ba00f60975e12f6af628a8835042a99d218d53c596ed2da8fa511b1f8e2274c6255afe856370a7b7e4908cc0ee35f4ff8dc2914d4a6788a2d1345010001	\\x15d93eca6ded11aec3ecc17141bffcf51b74cf8f52e40bc3d4338381e7bd80e1ef6fb2ef765ade460a3cead98c838318424d1ecd099d540b8780b290b907570b	1674194891000000	1674799691000000	1737871691000000	1832479691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
264	\\x5e6a3574e7d1abf2454309fb3a6102fcef703f21034796cd1ab1bf33e8cccc3577a47454d971b501c9c576a4ee16d8c78899d6f9b31627380d29b34dca7696b7	1	0	\\x000000010000000000800003bc48236aaf8181ad5401053fd8368c7c710591b2b4e45b0f33b0617310ae77d30071c80452d9fb4af49bf22f0546401c3ca51ca0c7937678f5a30e997fd6d277768bda395894211501ea198cea70f4850b2180f64043f24a5a58d950dd6ee6890e6b5b94d1c44049e5796ccf2b495469a849145c0f4fa9fdbc0d86ff36eafc21010001	\\xb8ab85401e6477c5e786321ef232c9a50d0735692251b717e5037b1e4ccaa78631f6e914914583e082875cdafe2e6b49afcb703c686f63d11c7b9f5c79461d0a	1681448891000000	1682053691000000	1745125691000000	1839733691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
265	\\x5fda428f0774ed9206ae37d54c8af4dc77be040a771435891b6f803ab489fb79c6b0be97678e3e2f68c0ea8493b26518765b800d80a2eaa57837d998c2bd818a	1	0	\\x000000010000000000800003d0b95073eeb114dbaff4cf8bd6da8c49d4e5e56d6446122150ece31050b9c627df3beb5ec8cb3e29efd9bab2de22143ba47c88133d02c891f22e7fbc7a37ded0adafb81dbc91753974312d1098c3a1fcac7f8aca7beba6a22c4aef7036e4c8a0097655c68b8e25369f75f55b61ecedae62f5ac229f02cab691e59b82302221d3010001	\\x5d88f890dc945b5c07bf0d803f17171a7636ab87b661b5ad941a67a1cbd9572879104273a2ac0853c8ed0d29ecd1a93efa3811f4aaa2242dadec62f76b2fbb04	1666336391000000	1666941191000000	1730013191000000	1824621191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
266	\\x617ac5c557b911530f43782eccf87fac5e4e07ed0d4ac35e6fa027c669aa6695517a53ed74078c6f3ee00446e46cb74daa57188aa3bee3602c34e34b6d7d30ba	1	0	\\x000000010000000000800003c2801bf84af5152b8aca4fb7576613458a70a250bef279dd0221d0206d9d7f035b47fba82acf3c6ee2fb11b720b9e1094524770deb21844ae221269b3b9f8aa4cfc99a64f042eb575d48ba13b5b1e7199328d3295f8e8c5a77bbe71688648156f077dcbd8b34314828d5dbb4b71dfe8dc96e100b299bbad5c78f6c8362216f5b010001	\\x006c5c637d9a95af0def8766c17cbd7ebe836d0b8d9904dca369c904fda17eef02f88d9f1d5b10e2e6beaf5d5f71ffad80e883a4a1d7ad5027eac9c319650507	1667545391000000	1668150191000000	1731222191000000	1825830191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
267	\\x6266758986c8bf84e69aa5a57bca8b7ea72b4450567b2db3fc84bf6deab490bfe4333ba12ac9d88b1fbc3b7204cfeb4880976ad13d90b34283cc2cf59dbf2852	1	0	\\x000000010000000000800003e24637560add9096cae438ba5a77db74acc104911d6b70709f40d50841810cc72485997620a4b2e75f467765071a94a2618555519b34d9e4a095b8b52b7054f4292e0a500269ef7ce9f36e30c6f01f1552fba363fc86d90f76368c1420660028f0161e034f2bcecd4a9371509a4191ad2e7579e744247c5c20d325f13dfc2099010001	\\x0b53b7c5d24a3ac3fc06480acfe32fd265254f69785a4a083ba1a60c5b97b2cd261d782f0ea58c1737a26cdeca91bcd7173232a652e76b5fe205b7b077a02303	1657873391000000	1658478191000000	1721550191000000	1816158191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
268	\\x64aa1488bd52538d9e6fee16f3cf58ffd24351e750de9ad170b20c009c9c79e8c1c00fb86f6d4728c3559c85d55719cc441479d0029523a2d2cc577f303edcef	1	0	\\x000000010000000000800003e4132287c0356a4c8b78b949328a49edd72a221d58fd7aa539051cbd2993382a5a387665ddca2b70ed83965f57dfb9c8b0ae6c93f4f6d4e96523e517b22b6bb117c13f25362c3483b400eb7c0c5f6633da13651278e498dc5dd7993d8dfeeebcc21832d00d350766d5eacc560c931d8eec24442e4c670a98e0675e39cbb41d39010001	\\xf21e339c6be50d8f6e24f2ad3d5ef5f1f3b4745f5eac30c250133615bdaf73831b664a3f7a08defa09c66c17fcc75b12cc884f165d55a213d783edb04bf2ce0f	1677821891000000	1678426691000000	1741498691000000	1836106691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
269	\\x6546414009337e62ee3d3f63c72ca094758d4b9ae3de2932df331f54fbcaf0e0d9b6a02646eac9c62bd04e59aa4c5eb5c864f956fa287de0f50508e4a6a98cdb	1	0	\\x000000010000000000800003d05eff4f74e71a8c61eb16ac42c5c9482939a509069a7f484237d560349adb44fbbccb520afae72c1170bc27487d0c055b615b4d11e17a1120977c9539fc0f36928631f71103ed871328291c8acf8808be8125922d181203486d98ae1cfddd3b7f2cabc2d4b8427dcb9d7e7a6208a17050dc1904be5bfa47d1487b00483cb2c5010001	\\x7cb19c3e272dee737d2cc2f5e34e07a8c30cdc2681544818ce3a60869f23038b5cfc67df1c1260b772677d2b89cc3c7a851480cb9aabdec7c824c362abdf1d00	1654850891000000	1655455691000000	1718527691000000	1813135691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
270	\\x652e23d30501cf1988cb601d33feac3824774398baf0fdf69a64f4bc83e43e4caf7316c9c315aebf77011744bb6fd39ee83e0b17c7e2952a7c4fff0a0e0b166c	1	0	\\x000000010000000000800003c791f7d193a719bb715837606e42379d4378609f4094d6e3ba0253a7fe47d257d5b23b770577f5c408a3adfff2bb3489bd4061066f33a3f58697d3b7ed9e09f7a49276bfd476f4f2653e4ab95f07b2115191f26a4fd44b4924b0f3089b0b361f80446ee8f97dc66e5837b320a73ba8126cdd640c87ce49ff30fd06d1ba332d4b010001	\\xa2b4b036ab9b179f70a04d7453764e1aa425a8e53606859303cdee838655aa4c136ca8e41501069fbf8d6d9e5f88284cc93f21670aefd5abc63843441fb9c20b	1681448891000000	1682053691000000	1745125691000000	1839733691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
271	\\x691674f3b421d7fbecd645ceb26cbba7eac26b5a7efb3800a58f53c4c9220055034150d3a4087612577d2dda683c06e1e00255858e64d254a496ea661d039403	1	0	\\x000000010000000000800003e59dab18d6af0f858fcf52218af5ab9aa97e9f09756621a93974d046e81b68e46521dc306a78af6cc4b6e3c661a7d0fc769ea1d9479e263f9a7d13731988d6e3c44d27ab4aca9e84af74c5e31c6bdc1bc48a00608921a84c9b13adcdcddeb884ba752aa3d84f07b0ef6e5c33e290d3aacee404e36f3c5767565bd2bcc575eb35010001	\\x1e6c8d9d0abcae903a9c29d174c6264b1fd377f50ca6404d576fef992d353eae69cac5d8425d75324ec99bd4b12db21ca67420aeadfcef20114d70991950be07	1681448891000000	1682053691000000	1745125691000000	1839733691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
272	\\x69967c25574cfba9677f7769959d58e96c3edb6a238930a24ec21f5e730bab637201c734ebc36c66e451d57229822ca179259076791192648b977743256eb876	1	0	\\x000000010000000000800003c0962a148fd7ac85b207c0413e81ef2fe87b14d2336f9e40ac13cc7deaaff55f3c4e85a2991464a3d2bb9a0f113f61b56366ab339971624195e6e119dc7de8b00727ec2d342ec96d0d3cb0e129725cd999c3697cd16dd59adbe5c00bbc5b580aef95eb1771ca9e62f26a3cb3d00daf6652fe477c468a71debec544a4f806583d010001	\\x0c96ae85a7de0e20dad933584d93129fc036e943e0db65a097a2d827261cf33857113032e8de4ebceecd7b19248ae9ab95f9820fea1075dc325cc0fcfdee4b05	1663918391000000	1664523191000000	1727595191000000	1822203191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
273	\\x6b9e55089757a7229a889997ca396fda2289c854c72c286d884cfa5b95fb521e9d6aade4f4cbf2bf1363b4813c1a009d648a9114302c4ff4b11dc82d03bb2e29	1	0	\\x000000010000000000800003ac1061dbaea4ad44ea6332075ae476b8e4c7c9cfe4b0419abb80a29b776f93c9e9b82ad6ed16d4f728e9e1869c5f08fac45baf3b5d59769c82a4cef2f2b583c41736bc54edf378c5d860411d0a8a1de888d81140fc135d69c3c6f03fce9777f6c1a092f614917d9cec946dbbccd7a1f5cf40c9afa030f6372b8caa2c4e7d593f010001	\\xdb12d351fd8c5d0816353832dd5148a42a897d2b9e2ffce7721d218d1d80ad74fec296b015267583e5d377e9777a1604002f6d8dc3588c9476b7b272a6e35d01	1665127391000000	1665732191000000	1728804191000000	1823412191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
274	\\x742ee648208dbeb7cb8d97d4d4839a71d2a7feb331b1c5609c3ddf5b72cb89949d07dc3d80bf8721f7a6d31d40b0d757ff30d942f293920f7d40109d9c98c9aa	1	0	\\x000000010000000000800003a96b0a3030dfb5f59cfea4b69b9a9bdf34becb63547b62896bbabaa8ced0c9010b5d34f32cd8245b5e04686969cdf3e3fec82bab12c4ee95f4fe5970354171bd44fa68d80d67e5233142bfd6f68974d103ef92947ef6e12a5a4be8a7df27b14a584cb411a23bc11fd5f2a990e6887692934bc9ab4bce8f651f429b514518688b010001	\\xccc965d3adce8c6e80132210ddf2a315c7ce1c46c9c519aa1615d59874b0e1a2c191891789115a704da660ab682390a13d0ea96472af882cf8a4edebf6e1ff03	1663918391000000	1664523191000000	1727595191000000	1822203191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
275	\\x79fa47e87c8efd502c3a7cc927ce31124c2242d9e8abcc38e694c1a9ddfd457568da0261cbb6b9a77b59d8741b1ba657569d7e5f2e5ee0e2f557d4d6d8607d06	1	0	\\x000000010000000000800003abc0a7f27cbf8445937ad74c8a476765fd9e0c573f77e686e4dad833fcc940e3dd32de7c4ae8a86ac73fb2b56756c825902be32a773688eb7dbb5741ea26710e38650e5439e6089511c6123b94786c4b32662889ec0c373e39f86f5e4b0ee6e42d09414cfc4083d08f4bf8f92b372a5d11bc73437bf0f3fc270da78d3fdd67c5010001	\\xafc0831f5983b33e3204bc9a2de9392bdf8ae25ee3c8ed27a1d12c01c3b1307e69840b308c3e7160f6198ef12776be3093e33f0cd195b3bea7a5fa351e3b0703	1663918391000000	1664523191000000	1727595191000000	1822203191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
276	\\x7b324909199b3a819b02d28cac6cb7102f800d66c763d9390135d80db8e5d147aba7b212972067448196ec5fd2f07227a548e9436e8202373c684d83a6e1e456	1	0	\\x000000010000000000800003b90ad6ad9fac7c3ec3cf882955522e81cad36cdd62cb294830114f3e10f62909a8f2ffa243eccbfac5a765837cc63e9ef41a83739381ae1f1c7d620e43c660a261da13311f4d0b83fbefcd89ea6c9e9f495bb9d85d0a41a0b4d834d87be4bb1f10f0fce4da2da45807342b531d0232a879a190d625df57ff3d476f47d9af681d010001	\\x353b55bc942436f9bfeebb46690ed0cb17b9798beeaf3639f47b1e4c3e3f0c6cd467e586c9973246177c3ef9725f9130f64f8b9c41511fecd9cf09e3a1b8c50d	1665731891000000	1666336691000000	1729408691000000	1824016691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
277	\\x7c32fdb4d35a9b30008021202eaf76c4c8e4a77de9d1f430ef181fb7f0fd847d7f69f6ba1b31c7ff1b91de5ce8d53ec8ad4283a25bfb2d8e2c6fef2937790b77	1	0	\\x000000010000000000800003d3280093cc517dee5436ea997cfb54c756f7e9844fe9a9a2b8223f79ff91141ea1dcc8e58f94d940951d3e41c069c206b936552f55568358695a3c2feaab8db573d070de8c7128b56ddf0377cec90ce065ad6fad770f927f8d7dc3d7147c618c589c2194204c65dabc8c59a4a93735efb5c12ed8cf6fc938b77107a81896388b010001	\\xcf8093d998448a72a618423300038d1449e3926a7691d7c3c4a64b67d8ce927e3e0168e7142c6299183020fb3977d54d42a38e7b909f06383eb4c1f548f02c0e	1680239891000000	1680844691000000	1743916691000000	1838524691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
278	\\x80c6dceb7ce81f9d34cd06f1c29de26ea788a1bffedb95009238af74a56a4d64b879195af55baf5b73e2736240ce54fa72c42ba3f095dbb7ec185d6a5c904fd1	1	0	\\x000000010000000000800003c8cfd098819071045dbd16f469da06c1a7c793be5de19fa44ab8f7bf3c2f3a2edb566ce9fe70b76c7ce7e9b2e30c42ef0c06707af55a2f435ddf7cec48d5f8e1e353c4f1478cd6abc4279ecc0f4c50829c079424f1385a7e4a171c37976004aecdd95ef7be4f0639ccf6ff3f789b2530ffc5dbcac4cb04524d9dd3b6f35fb851010001	\\x40e2781b6b93858facf0b503e918a8810a28dbeda95cacf5f5b3f17c095ad9a9b0ae5b86b40b7a352f634480db33d2d1966abf6837086366ab12ae66343aae0d	1680239891000000	1680844691000000	1743916691000000	1838524691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
279	\\x832a7dd095e42ddb545a98612832e0abeba52ddb4c978dc88606d0deb4424fdc22bde8e7804619912d56c9b82ea69e6d110061091406eb00230f238bac0a14e5	1	0	\\x000000010000000000800003c43e637c0cd2124baf27be44e4aff931e149e76fa67f44c93804bcdd901f1b8dbd4cf15487f6e0a894de063251cb2135aa9c5b99d81563fca8391e754ef7f0b49d5d7f36d322772c94e04845a9c329ebf4b5ada5d5a5706176652add2cf55582b7e2902e47afe9cbf052c0f32a3785452a0c0369ccea76c2e33d61c8033159d5010001	\\x93c78339ff57b042eecd0587ddfd84d9c5b2a1ffdd9eed241a9e12199d428851f87c4584c281100d45eb662c284bbbc407b4d0b1fa45db11752ee970097f0505	1669963391000000	1670568191000000	1733640191000000	1828248191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
280	\\x885272249965368be63f2ac078bfc7b9bc03b1d641c537d8a749630f289e0a6f1ede5f23c1bb3ac4ac53201e6766e789c0d918cc834c2d1da6f9c066d8d5d1bd	1	0	\\x000000010000000000800003bd0ff46ea41743df7545a5671880032e7175ee0b79a4ebffe49b2f819ad4de498de2e074f52a7d4fe1008f03026ac1f7b4d287bf0cffe77fffe6c0a4a08c0846af3f69ac95c9319d68a3f64431390e2f42f403841ba13a1ff923161980579a6a74a3fec15a3cb58adcd233a3e640a7309046ef1aede7efd4d89dc4b5ccfa60ff010001	\\xd2e512ad5dff4f1b8f1b00a7c296ad94ec84e55eb49d4b1ff925a603e2351456964e9e6f6500e545fd42dec354bebbd453e4c28edbc7b30f252347dac2309908	1669963391000000	1670568191000000	1733640191000000	1828248191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
281	\\x8a7ee3381bfaaafa8c5ce3e70e6cd18aff54dc08e0a07e137786178a499156ff3d37559dc94bf6a593feea015b4378d03bf283d07389c1476c53b5ba383d9614	1	0	\\x000000010000000000800003a734652d0512e6c40f4dde02b8e51f19634fe8e84450a1f063b320fbc4c77e99ffbb72eea2fb228b569ef915a00745c641421be1415bf980ee5df73e8933494e671e1c427fee9a40e94316019d3bf1a21b18b86aed1c113748e755ef4fc81609df8f5b4fe89ee301fd61be4801df2ec98e4a95ccd70125fee962a1c8719cca83010001	\\x2fc0cb42b55ecc62beb5f77bd4e62338f869641302c67683887c783214008f65aeeca06c0be0b65c4a36c37daa1ca85792fd275bbf9124adfccb642753c69007	1679030891000000	1679635691000000	1742707691000000	1837315691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
282	\\x8bcadede5fd25a3f7c322c4e1f31a1df3c28e2f4e1ecebb157c75bf4f6a32bdba19001432b3de8c3fd550db71c4c9fb1c30f70eb642e4fe2b68e84aceb617c6b	1	0	\\x000000010000000000800003f3c7eb02e68fd5efab8ba98e4c0c6645d7973dcd9b1a6d1f174fa2c2a040022a04dad7b59aaf3e9442d1206aaab6aef056101e120f33d733f3c3a038b494f67ba1b93e5bcf2c5067f7655c92a7ec6ef2159320ccc41b0eb99d60b2120fc6f1d67d04814d253f5e0d37d9f6727b2512dd47441f61a26509d657cf0ac1af864007010001	\\xae9ed2644c9e932ca6af7fe2da78b71fbb3d63b563beab49c3ca73e2faf47e9932210fff4266a487a1752ae3281d2f88ae3ea7e32871b3fe2df4b355d8e9800b	1653037391000000	1653642191000000	1716714191000000	1811322191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
283	\\x8fd60098589bf2dcb8ebaa71937cf39b44566e24c1c756e9114fdcd8b341c4abf63f384e70e15142516aacd032790544832c82218877e1e67fcfee17bba5011e	1	0	\\x000000010000000000800003df6fb15c2f2481db9cb77cf2d533efda21ae3a0dfb502419f5df3573ed090c9aa20d763d8e472493d0256fa9a43015cbf05e23a069cce61f974f18a35209b6a9c1f661a19357d38d0c90fd62fc66d37b9a022dc6aa8a9aeccc380b9906be8982f9af3fa7b2434f1d3e2f4d35714aaec3cc0bed3b664655d3b6555f871a08865d010001	\\x2cd57f9ab90a664a1a3b4a402d92cfbdedf86a0abbf93b8e6666f34c94564f548719e002db4333fad29c4ff1c7206cb1d0d833c5a036799731bd4e9de5b78303	1675403891000000	1676008691000000	1739080691000000	1833688691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
284	\\x90e6168f2cc820d8ddc4687ed8a47a70f380a2a4671eaf9e2e3589f6d783f200e230cb5d00324bd1f9a922ed7c506d2ab23be4e635e7cc603f6be63e14ec5cd7	1	0	\\x000000010000000000800003c2a022f68ac80cfca79ad0a431cc047ee8370a6ae300d31e5b249aeb779f69be3405eab8d1e86928f7a5da5d36c9240ed7455a33e0a7bf7d73bf7c5bce57b24fea8fac1912d9c9a4dc6e568fa61539b9e7f5200a3154e5a1eb2d06da325c2e246c90f4554a395819fa2f9416fe40f16ab1a0bf86664c1857dfaf0cd1c512c6e5010001	\\xc89044efd7dfff9dbaa03a3b48e7350b9e7888e34c8a38c9f8afd6d026514e9f1823b95f7f80f8e78f5b3e724d015d6299551f6b0a7796b381213305740d9400	1677821891000000	1678426691000000	1741498691000000	1836106691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
285	\\x91d29d36aa84f94fc4fa78435c63b23c0849807706dbf2328b72ad22fffb95a7a0efcdbb2462d435001d5c37c819f315203507b8c43dc0c03daa285d9a352999	1	0	\\x000000010000000000800003ab40d64e5b34906acd41d7e597218da2a92d8641d33b77a8aa35ddee9f0c4b7f207002a06d239fe1db1732f43de7129e5c3ec16f16208a8736e89ec8247e26ca2cf70cc8ce669e1dd7e17df304b607820f07d5ca5b84c22b5255fd7f942808ad9b86523a0dadc39b99c94b161493b29941cca07ad6d439633f519d2666d71d2b010001	\\x86d6af5245d0f7a06b46f0946e5e7c1c662e35114cf148c04233f7db24a086e69fdbad50063402ae1a6fd61c19c5cad3f1c4ff386a7790d91a24a956a6c0f601	1660895891000000	1661500691000000	1724572691000000	1819180691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
286	\\x910a9833e862da3f70f57b8a992e1633a70f3f99a19776f0d40764e9e4dd43eadfddde1b1182de64d98210c1ac3a903c4aee654922721eca7a47b9a114c1f36a	1	0	\\x000000010000000000800003aae2ceff60c371e22758c34216ba0662a133dc00cd18bcee4fa14f0c6c18c1bf6ed95569214c3887ed4f834811686885820245fcd200a5f81b8886268e7733aef73b38c7997acfed84a10fd40794ab7377f4393f5190c9502c5b3ce391101da065077f32cc473410f554982fdfea78ecfe180576e54ff96e8035bb2bca250951010001	\\x6d9124d05f74b9ab07fe32f18d8642f1f42df9ef4064c97d4b61b6f530cf6673221547478dcdbfae1665f3716ee06d62e7a082f6f772b02d150ef830aa3b0e0c	1677217391000000	1677822191000000	1740894191000000	1835502191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
287	\\x92665de9630b0ad8637a0d927bbd097f27b92ade6df7723eec50137637eab9338fe5df96614d39a515c4459a446367f0f7f9625caf56e4e08ac0458ea82656fc	1	0	\\x000000010000000000800003bf7aee0fe50b283f8d47f81d43c49796934862113e38878813439f50922cf7aca41c63134182ffceaecd2d909212772344d23bdb93a42505620d205d59bc9d93edd17983abdc834695b24f87e75744aef9dd0858ddf6050df1a0dad04b4e07f84bc72250fe91e9a9d9412421216873c8f6b774a5d9193b5f03f03c4bbe34a76b010001	\\xbd7c986ddb34ab6f48481dd667350e3e1ba0c9f1ded44032956797637c4340d90961aca35bda21f63e6b064d374257d329ef51b6c2cbff7b8f3407a14b8f4f01	1668754391000000	1669359191000000	1732431191000000	1827039191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
288	\\x933226470c83ae847d544d50cd3b5f205e249f3d5de8174b4c439c92794021764fd08dc60b699db4c80cb1b92616578cb7c71582ba8b58b626f5f9c1dfca6162	1	0	\\x000000010000000000800003d8bb9848b8780f43681636909257b278d99cd27da42e710e7dc999a6e4e40a8e5433adfcec0b9ee22456f26b92a63776eea0a13a03f7e3e6e90f2e1be3ebf8eade85a32a55b7cba77bccbc61c41faf1ba3ea19171f9b0dfdcac58922cbd90e8543281a0ea3174bd147c38223a881d55324ac95ad381dd70803819d8a23fcb7dd010001	\\x56c8cb975cb63567e7c9b97ab8735a4fed00e21c5480196c08285468b9b11179a8c2c49b12f70ec5d931fc6604bc1360ebd86daac787e73fe5631ab7801ad30e	1679030891000000	1679635691000000	1742707691000000	1837315691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
289	\\x93de747d3d101f16457fd84c77e8bcf0474a8643ab28b1b1d1e35baae0c08317ebb338901366011a58847f156c2c2fec781ba63fa5e3ac1c7315355826311102	1	0	\\x000000010000000000800003a1e3c580e2fdc98bb6bc8033f907844f54da4f56d36525dd9661579d7ab12d6249474b497228ce8a24e1914f0b7cdf56be73d859d9420b56e82a3eb47edf32e795bcceed54e3e1cbc12ab49ee1afa093a4e1ae4e96a6dd818bee4539cb46d17a8fdc6b442fd966252e4fdda3627a6eb1d57b759f52bf993504313feda4957ef3010001	\\x5ce1af90fc2c63c940df55b6e3c1760186ff3bc7db656716efac9448cee38f0072565dff8cccfe74585bc240394d6834b765eb78e7d4817eb9707cd8ec8fe202	1654850891000000	1655455691000000	1718527691000000	1813135691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
290	\\x97e255a399d7a57f8311ad7a36006453f1d4d825dafa3b4e58ec3057809d9055a6a2ed09a6e7a266e2b270f5e6ad6cae2adcef38c5b94a90fdd41aa12b83665a	1	0	\\x000000010000000000800003cee57e5174249ab86d426deca60b4047d5ea3645c9baff305c3c6d8437a8d832e1da463c3140afdaf8733ca9686d56e068689d80ae1844f4e48a7afa647382a8694a25fff2f8ba8b800029d0d15f2bea6641d414683ba968f6e901a05aed422fe72f7fc5890e66f77b7aa0bd331e43caaee034461096d5f9dab3a5fc9e0af813010001	\\x068d8384aa7d9c3f7bd966f6013f0eddab698b8f23c9102f8bbad44b7d09954b0ac59a4babe01246f95760d67cbe34787e4b96ee1622126f989e21a3a8efe208	1669358891000000	1669963691000000	1733035691000000	1827643691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
291	\\x9dda2065c1520c685750bcdae8cfb56563b7eb9097e6f0248e011942efd03f399fbfc15f8e913d0b2add3f33adb62a9936e4f5416a53ae946a9d7fdd50c6e9ee	1	0	\\x000000010000000000800003ace342a8f0817c02f7c2393a8b1a462e71106fdac52845c2864a96d432dd454980c424f9d6cb2425789aa14eda8f675a4ab22bb1579f7c81b5ba9e6643576d7fcaf16cba32f3f525faaad48744a066a4722be46b472827394ee04263b42566f441699397f641d0b840e9486b4b7391eb022e6cf8917c515feccd0a620f2e1f7f010001	\\xae18ebdea774311530962494da0c0a33b4bafee7cafb3d42137db53c59049580a7e4b661875df606ef3fbd8111627711e8b3e50a56abd316eca240feace80a0b	1672381391000000	1672986191000000	1736058191000000	1830666191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
292	\\x9f127dcfe5d01c1f81179490ff2ec6f0c61b579bce0d3302f54df75b31c2695f00316eedd978025317f1b04acde9b9026d18563fa8bc54045323d33d2fb52aad	1	0	\\x000000010000000000800003c0c59d11f71b3f1ffdffd07e6b613651375cb78a547fe565ce6b6204c6c6cf0228f4a788de4fbbc5083c4af25985d85646459c76875081e2c52a07e1f42ae02fb4ca502dabe783199c66b2dcc55be67fcf3a1074ccf63bec7095b51acbf23fbecf280ad41b14881ff262f74edbb0a135dc9f65f5a2eca43680f5366150142883010001	\\xb68abed937ed8918b77f1e958c5089c7255a6b99abd24b6455ae0688cacb8659b117bd2bc7fd7414fe0b6c5014fc8d2fb32337ed272065b766d4e5091a359307	1677821891000000	1678426691000000	1741498691000000	1836106691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
293	\\xa20a4775a530fb4c4a56b4a9e01bdc46774a93701872b612ca384f2eb19ab14258f200df508fcf521b17611a1f566a567f93345c3149ff3ea4d47e75e9a7c856	1	0	\\x000000010000000000800003ec0a3c10dedfdd656c164ad5cb3c39bc9f3ead49cbba525d78ddea051723564f45e8634ed0246ff4bf328256432395ea1b92f83877e388303d10005235ea04e352f66e8fce5b3ffd1c5652ed565e74d9d7c5b6cf29452dfcff4c4a18a8151118c782b255cc8df8004d2dc207450ab0e56ba14cd9b28bf7e1efc2c94810a2c5df010001	\\x24f56ca8fd80b766b71dbf11948dbdaea624427e10118a55691cafedd1db34a50ea50322ccbc7c72a6524297f254f1c2f8b93773a617524dd67c7d60d42bbc04	1655455391000000	1656060191000000	1719132191000000	1813740191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
294	\\xa5ee8a6146c15b9a1417e2b9844dafff20c8d87f8a62ffedfe1fff6ca6ffcf96d166896c401feb3105bceb2d1d2b15998e09c9c784810779ee0895cbc4115f00	1	0	\\x000000010000000000800003d146a8e3bfc5f0b6ebfbb222860c31b258b87031efff6ca0f17705f2f730dcdd6a866b381b75276c72536a46c33ba83247777819bcd5ae0132befc4ba885bb0cee710c2a25cb1e43f2c1e685075214743fbff5173b23622fb167f20bd7149d1c144d20950c12b9b112ee014e6c034361639bb27753bf226d2dfd2cbd3aaa76a3010001	\\x8195e68b724b3f4ee9154a38a6153c02be5c273c41b9bda46261ef4410c6904607e00e180baba5a91c199439553566fdc17208ac4489ced7ce0cde29e23b840a	1678426391000000	1679031191000000	1742103191000000	1836711191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
295	\\xa9aeb38b8656f2970e31d87171c3ebfa2e56ede504a48a4531bcb7f52c085dbd593908a404d73fd70e5efdd65573d160a414eae4060dc952e6abe9a964a6e890	1	0	\\x000000010000000000800003e76c186cbac895a84d717ed6743fe9ceaea1846e38f5770f14acb50760eaa4924d41452133706d9fbc32543312628d3d1af14edcaa92c7551e5b39743209e317093ae80512d7edb5b835cd0f9cf1ce2e5d709a8b9a65c0c830691529c09eb8ff9836f4d6873c83a22c0d6803560f7acfae1858659b2d22bd2b5e96dfbf980791010001	\\xd9384020eb43423f102ee681aec52d54d08737a39cafbbc17e76d1fa096330a7ec9a9db9b48db3a3d91435b659e153bdca6def38c2ee8dd1cb0103bb7ec57d0f	1678426391000000	1679031191000000	1742103191000000	1836711191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
296	\\xb62a79bc6344fe5dd5a3e18f1b15f757246e5b439016731249f6b1c7dc4ce840400e72f84b679ebb2bf6fb2fed521942708345c39c402cba334e74983af9512b	1	0	\\x000000010000000000800003d9f104ce4b6bab19bd780820d2bbba0d59be27f4d1a8e6065ea8cb0561514a2af93e7b481cf849ee47325e3592a0a6cbabf11521eaef59bf66434cb98d4562cb2fe3d1f8eaaf745fa9925498f8c7c9eeeec7f85b3956d2a6c0022dcbab8a6b407f20aeea210077978a5934f24ac26369811312817017b8b2b5934ea712c48421010001	\\x9cb1775bdac5d4b12eec28c06361422c8cf6009162e92b72d7f6883b74f13c1ca1815338b1afbc193f03cac1998da4a78023735d0f075b1fee6ecdff674e0803	1664522891000000	1665127691000000	1728199691000000	1822807691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
297	\\xb8b6906a3d7e5530c8871831d0cf8ff2323794322ac50ed82cf72c4bc5edd6d6f1ae254a6c8c9dca435407e35bb82a8b91634fcd1336ac71eaee1a6ad1eea2f7	1	0	\\x000000010000000000800003b4deff047eaa39535c9ae0c515f65b9a33b3eef0e59b71a69a5ba2876c1a0623b1ed3071db8aaf3d52f28a1b031300617af02ada71954a67df95c0cdf74e298bdb2737175df78277e74d05a379709afe55157c1927980248bd0ffc7186116ca198cf1dbe9b700c909375323061446e808ee6712f188dcca746d0660b2274e0c7010001	\\x78dc9e20a4bd5414296dc4d0184364461df407babb374e5276d5fb157c66e6334a8010ae7ffab1b47887cdee92a82ee78a4cc74afbc65127de4c5f8f70d12003	1660291391000000	1660896191000000	1723968191000000	1818576191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
298	\\xbd82dc367f56440e838bfa151f6050128c02d97a5056bccd96ab46e2b4228bf370036b5ebd858d53f27e15e12cc3001601201eff4ed19f20c7723a14ba28f9f4	1	0	\\x000000010000000000800003b635156f3db6b9558685b61c93e99a5d001bbc6f979de5ca854b170fba731793757ff6e4087b0df55f0eb3f4356ec496ad0a6bc79736ebd6335d16bf663c121e01f70f31d8699fce6f2e551ab96a20ee6b2c20e41223022165fd95f3c38241db61950ff19ef23e741fc7cf0864e822087f0d4aeef0f9b86357f133db7c148f6f010001	\\xbc6cd166dcfc7c5fc054c3f410a672068180e020858f443fe88d5121126fb1276eda0179e43b17eb1f7af5dc592fffdf51acf096f7a32eba699aab1adccd660b	1669963391000000	1670568191000000	1733640191000000	1828248191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
299	\\xbd8eef20f1e8433c0e2dc00e4692ce8d012f1e4b4b13441b85ea2445048a9dbbd9c32152460301bbd2a3a25ac05707e6afef6f3a19b6319ad807e5e77d1c4671	1	0	\\x000000010000000000800003a9cb617066aefd25a582b995a042ec946009b95d254af392b8e4a112376eedc32f852963135505d6781398b09ecac9260dbc0a54f21883c5db4b5fa4eab5494751be7e2fc8b3916ba6e611bfc9c2c4db19e8cae43ade0f325f268160bfdc6d2dac0633a93bf1d0a46ecf539fabcb616fd975229e51f1604e8dc621799ae1bbc1010001	\\x45ea4642f89e57917f6ece4cbc10e576a2b3f17f2e7173c1756dd27e709fc3e17786f0338d12c0cb2f9830dae8f2402958d247b66467f4fea2040be38ef70004	1653037391000000	1653642191000000	1716714191000000	1811322191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
300	\\xc9327d3d77a06bfbb151d99aadaa8cbbe4b2f5194e958496c7b1dd17e50b792d2e7c77ec8f3f851f7fc2f1a1da20a98b71a6367db3de6b80d7e304b35daa76cb	1	0	\\x000000010000000000800003d549db9b5eafbb1dc03f4e271575b27654ae6a5338ac250728e5428f146443b23b74a56eb8fcbe475a834711618c29fdcc92c68e84a9995e2785c646282de3fb99d61d0b9582936a12a199f61c6489bf5a1b570c8ba0115180952f31e934fc8413b40cda24bfe0dcfb4ca211a84dbc58c824319172b2352df75df8bba60be541010001	\\xba121e8fcce6315629a2572bc15250a1c5f1ed1c1dc8c9b1632ef58d4fc98b7ee6b2b6545f441d73007b8f843922c5a81cac8490ebfb6908980ac57ac6e62405	1670567891000000	1671172691000000	1734244691000000	1828852691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
301	\\xcd229824c8fd3eb82dfb1aca68656b4367fce1b8cab3794beb58da25e6af9115bcc3d141c9988799a66dfc98882eb395b407802eafed6ae4435b2703bc41c93b	1	0	\\x000000010000000000800003bae9a2edb63a51e732a88d5f6d51de71eaafcbcfd6a5741b488ef2509d6ec15a53ff225e969819237607c714671a408a25eb118fc477a3b97aa1ddea1fc948595dad597d2d81a0b690b95fb5248766d3ad0b583390fe8591a4ed3103db7af4f79d71d53c32187a90892f507c4e59bfae43898c9cba4e75ea2c0ae9c2c8b2ba27010001	\\xaa0790dd0a39447b94cb7d3faaea53e892feb264cabb5260220ba88869805fa6709d40112fc0d9bd4179bbba1c8ff6360e94d09364079ec15969ef2a1ede800b	1670567891000000	1671172691000000	1734244691000000	1828852691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
302	\\xceba59d1a8210b8e3f55322f065eff4e59e4d4dd789ba8dbf78f9f7e50daffac72768cadcfbdcdd7af86d53d4c20d149deb009a933c7258d40fe104354db886a	1	0	\\x000000010000000000800003aa1cb56d445dbcb4958f922f6335894292ebf6e9e8ac02d60a26e6ae8e742fd650a3041ef7ba761168a6dab6ebe671595016d315ae6c53534fa3a52fcab9966a3c180f6126b2da70f640d66bea390f2cf7d992577f343b24f8fd11e9e5789cb6e8ba69beab15b546b394e1a4000eedfe39a2512346552f53dd41cd1509740d71010001	\\x588ea22185dee5c82b9d3d90c81eb373a81259f2578dafefdb8ebf91adde37e511f28f0e54c53d476a758255908bb5c827ea2db6b02841dfff65c3a7aec24301	1672985891000000	1673590691000000	1736662691000000	1831270691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
303	\\xd016282c3be3099751d929e1260fdac40dcf9e16dd4dede4ddc477cbe275a02a2aa7c32471b8b57636d9b991552274cb1e600ab980e6d73fabd9d4406028eaab	1	0	\\x000000010000000000800003b548e5d10fefc3809ab87a61c6469308a07d62932e5b850aa8e60a25f1e9e10885515dbd55f904d7b978c4877194e572730b3004cf740cf94e3c3609feea7bf474bb56bf8fc906f87873cc7dae74883aff53ec902f6afedb5b605b863dbbc968e03a0af9f0114eea38f105c7866ff3ed1a408a98a76237fa0604befdfa1f353b010001	\\xa032182f3cec212d3c0afcd7c3126396187ef02727663e35859a86ed0134050ade57de17516b8a19e3ee70ec6e1b71f44a27e2c0ab174e7c1ddc6f8a4da68f08	1653641891000000	1654246691000000	1717318691000000	1811926691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
304	\\xd4fa79bb21c3d33a1e06cd7d7ac4e6db7f318f11d6ffa8fc1e72f4de0d0670b4809a9af34d4cc29c4a8de455cde0339666c13de5d7cf48543f229b868b24adbb	1	0	\\x000000010000000000800003b10f4ef8bad14980beca238995f0edd65e90027f49718600caff1371e58e874cd3b36beaa5d719cd662be6ae062c7fc0ae484c971d8f1792586c395bc47230bc6b04332cf394e0643b079d5b9fbb5ba8a0eb58cb7c297b8fed87dfbc4b4a64fe727c5492fcd229a344fcfe14e8236ea610fdb046d8841ce2bdc3aaafdaffdce5010001	\\x73bbd710583d04c061827bab2a5b84b711c2f59c8ec0ba0233573428fe4b80b5f631d4c79772e468b8169eb41755931df4b2ba3b3c7f145322aa24d62685b108	1673590391000000	1674195191000000	1737267191000000	1831875191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
305	\\xd772375c038c9b8dc999bbb3b1b629f0e755bc10e7bb46dde120c8b6f5b51521540cf15c80206e48c2ac60b9a1665f6cc596b99b7c0ab63f3da24cf5647df1a6	1	0	\\x000000010000000000800003c3b2dd38dac4149ebd5359e7d6a3d04a25f2cec5e18bbbe6c349dca3ace8ad808b5d73847f8346adf9a4c77206b5fd1e24888726dcdaf060690ccca84e8eb8d53057b4bca5585fc3e15cb38ee495cb3512351c680801f9e6fff0fafe7f0c4e97e2b9553aedef2c5807830ea440c5126ecac9217a073a36fa10a27dbbc4949fed010001	\\xbf197bc49e58b9777d1d7b233fd29a3ca2ed3c1f749ce949f4ebb1154cc4614f340b142f2f798561670aae539b0900e467c4a499d10372b8a3bb664377075f05	1667545391000000	1668150191000000	1731222191000000	1825830191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
306	\\xd7a60d233a8ed243d0aeae25acae6587c6162cc8b896ab375185b20c764152fce09b4ca7a683eabd79667092ad2aad3fb5f03d08860bd1f4277304bbbab20a4d	1	0	\\x000000010000000000800003caf6790da16f657591b9d995fcf65bce4d7ef4a1111f9dcb43e5894e7853251b08c69d042f99dca57a1cd66acf679d30b06e4e437f21083eb28884fcab38a68ea72af39a992bd7d0d542d1d56947be767bd9041e49a76b5561f55d497758a6de572f3a9a1d5e4e98c3a285f65f6ee80d7ae5bbc45920a061dd94d4355f6bcad1010001	\\x0aa600f436646bacbbeecb7d2d034955d415c888010512964837eae9193899aa646715a76ff69b400bc8ff0eb1a8145bfad4de5ba636a25132b86f2954022d09	1676008391000000	1676613191000000	1739685191000000	1834293191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
307	\\xd8e68066a2d94622d338529c04f0ef4506720f5016928dae25c6138854ea7860074254d0977eaa85b01e115c8de16a21ffd450597fcf4753d8bdc5794cfe9bca	1	0	\\x000000010000000000800003ba9f47af80dcd741c3f6a103162b5c2e7862772ca114885d199e10073502e3b7d6d18d75f593c5ba93d77fb4bb502b633a09533168d4173671436232aaa581d1283ec71f6049f0165ed392c85fce8a01416c7f7e090766dedc280e4f260c0b3f30f3ce585d14f9eced687814f948681df347661e7d768b4dca99c296960245f1010001	\\x0e0992779bac5ac11d813fec001579f38aac73ddc6802b181de6ac85e5b91936f1abc0b1634ed14d57122e7fbd07414beed8992f77490180daa1eb3d6d325c0f	1656664391000000	1657269191000000	1720341191000000	1814949191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
308	\\xd97242101abc434f7de4c23a0a95763e4c8a482b0655566c6281266af089c1942dc789d0f9849f59716e4b659a1095085a2ed8819227751f188ae94a46e368e6	1	0	\\x000000010000000000800003d2c6a325478284557b8e5045d2670c0b8fa0d37cf6659063adb96a54dbfb294c40b29098a9891180f2488d651bd081490e8fd5d70516e5711bc29dbed605fd8ae3606d646b5509d61243683bebac32ca028a7e30d558696b2da2bea5dca129e5eff88fe210eafea0f1084aab4fa1275d76af6fd92acf1cd3532871daa0ddd65f010001	\\xfe4e716a844bfc53600fec93d0147462c7552f2dbd8bd0840df3f867b07681c00c95f9d4ea5d0087c9a6e94bb157f1855a4fc15631e5a15ab490863bc00b8701	1669358891000000	1669963691000000	1733035691000000	1827643691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
309	\\xd95274f3717691373f431521fedc4da8c330e505ef047b66aa00ede0272d80a004db088732b64ee770a0321ccce5ccba51fa051a83794adb5d5ca83a5baa9493	1	0	\\x000000010000000000800003c0142d2a017da09dec98a8ca481f41469fe679539fcbcf077f9544f726cd750d577a0940bceeddd49e7c2a00de2e65e64a68a3a9d541e8e0980f9d5f95f207790430f8040ec966f86f81f369642815fcb83a3ed83805aedcd7918575787094985873133e8b2e8cfbc49d4133edc6c84e374fa299502a595058bf7640e4c48387010001	\\x43d2ce2c7570cfe11385ac69b354476f76b1de277c8bfa7a90e406fc556ad96ba04431ac6c31264b64694a36e90a71659a2ce901901360a5f97a7897a888580d	1657268891000000	1657873691000000	1720945691000000	1815553691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
310	\\xda8ec339660c9976b3252540c653ef11d4a933b5af4461afce89aff7ce52a0f8dd028ab0a28e62ff23b10bdc58d923b2d43ca78e33e484a376d97d6daccf9dad	1	0	\\x000000010000000000800003c331009d5f2d777dc649b9e32d37d11b2803f496535137c180b4f078d52ffde04aff97ea1ff77c4cbd647ac07851c4c4ad91b623d180a8d533fa7f14f0469aadbed218f64f779af55d2fb4522c2f3a9e624da77801875b18af2dd0ed30e74f69df01b3a9b713e977dc7bab78c26f56f13f9dddc5cabcceef06fa6cf5b4f519dd010001	\\xaa2d09fbfd6f1b76eb8386e3bb3e829bd1bef68fcb45480eb06e9cb268408b5d3f3d00bde006c914c4c014f067eecd65d0b0bbd5e7a9dbd46e64bb72342fe607	1675403891000000	1676008691000000	1739080691000000	1833688691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
311	\\xdc16636d10f042fb0b3bc1eb30ac1ef1dd371700320c1f82c7ad10e115af11245e295e5da6ca24514fbda375b67f4892d2f05b2a56e74a4fe61c7f8e2a39254e	1	0	\\x000000010000000000800003b523c6c6236bbf26ae4023e9699136a0975bc74df4f96903228d50437e12fa5a87c3aa318e55dd108a9035f81ff04b9811b6fd817a7c7bbcb291559b6c3b4cec65c5748c1d9cede49e505cf62a9bf6bb1247477971865c7082f65ad431256a3523b4595b30edcb4880b2c9f7070c7fc5059ec7e2cbb26d98b15f12ea7cc4b3b5010001	\\xd192c435dba9d476b5f30b7edab0cda8a462effa1a66129145f1a5b9a154be7c65f4c328641c4d176e9a03ffe1876ee13072812bcfccb29ccd71606b05f6b70e	1652432891000000	1653037691000000	1716109691000000	1810717691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
312	\\xdd4e08ffbe3194e5b259b4786ace6a153a754e8bade1ae5f2eb862ed4213af3cec465f2695690929bfafaafb7e011bccd8dc77fad868cb292b0710e6b63f14ce	1	0	\\x000000010000000000800003c79fe77393fe71f09b9adce58df9f0a80df73714e6c4d99d247681b4681eeacaa06298cb417adbc59a86d2e47f646f69d2943826095e0c75384be7a8be1a04a17ed4355e5c2a3af9381f628b6a12ddb202482ea91bf8b3109adf707e4a83f70dfebfa7b9b9d70d0d336ec8cb111f5e939ebd124e6c387706ce64f48f9c5a7169010001	\\x2853277e2a1e08165a37af9850eeba3a259e204a55f5b77f676e3ce515ac16ed49bc4b14928dba496461f2b20e70a771f27564ae914a6b0a434d41bedee4a700	1653641891000000	1654246691000000	1717318691000000	1811926691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
313	\\xe146487ce2d900d4072d83be338fe2f6affa4a5771994f0f54fccc8da948bf7d15364650e4a28a6d3e4546ea1c27b80ce1b3cbf26678f69fe89275b9eba5ee2b	1	0	\\x000000010000000000800003d574a44dae5471698c2f7fff13eab1c723ae6d612c852ae4d6cb307c242690bc5ca51eb9637231c6abb035c24343dcfd6e6b4b7b786b888cba344cc321d68a8b62a726d846f9e19f6d918b54d7037f56d9345bb1845bf919de24179bc57c3fff35c8389e9618da05e4f0fda19f37e039a90f158831640f044c01f89d86f548c7010001	\\x45e5941ca4a2646c3ba0840863c98307817d594704d643fdcf2458297cc0389c447496baac3227ac1f7979dcae9c8a5dac6759b0e4288624baf3e4845334140b	1666336391000000	1666941191000000	1730013191000000	1824621191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
314	\\xe13a6d7a68cee67203eaf2a463259e2fb181b7a6f480a796a9e1f1ceb9ef8ebae2f7e77e8ddc191ce8fb2c50d6505b6c740937352b9746f2fee07b7ebbd9d11a	1	0	\\x000000010000000000800003a96ab3a39f7e6d5e08ba669131b22a9272f68a81e5dee6ac42b571117312870605e578eaa7e4ad4c0952ca1385373a8fc21b7059ea7487aa2a9f34f83a530851ff6328e2700f2a5b82fce0f5974903a2266fcfde120edeb57599288aa67a477368617392c3ef726f2855cb3a90b5b8319f62fab2d42832ab9499f573aeb1c44d010001	\\xc5a62a7c657562ef235c4f7542dd794469c14154a8dc0c4af8133c24cba58d6cb04b896cc0b2eb08fc210aa9e28682b53a06ff3147f7e532aec66d9cdf57d70f	1657268891000000	1657873691000000	1720945691000000	1815553691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
315	\\xe29605a5f6b7bd77ce0de773a161a35856f5971cd4abc9ed1a5dc8938229c78686c7125086f70ecfa10bb431c9eb26c67e44ca7d5fd37d9cd194b938385dcce1	1	0	\\x000000010000000000800003a9a1a118539528f15caa9cda1e6339b273310ec0943f9f264d3725dbfe4e70b36a72203004440cb3665af8e1831a7c7d22679e5f720a19b2bc6604cedac0fe1687e2bc03615c6855ef77f8499a695094a6768653974b682b03bbe45dc58214b7e1250305b4a8ca05b106879e06b475491ba64d52afb8702b9de60c2c24671177010001	\\x60ee4ed55e93f92320c3d542b6e13d290d9c0289222bbf9a4f1173e684ab700e99982e683b7cb4d197f08f28600c836b17b1c525e0b3e86057dbbdb97424cd02	1651223891000000	1651828691000000	1714900691000000	1809508691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
316	\\xe34ef76ff7ac571bc5b971fad6ec42dcb285b3f6843ef97c6fa0a389c34af830c61e1150f6c90039b44ac3383b33d92417cf8d6e1dfcca332e5cd6b8fe47b207	1	0	\\x000000010000000000800003c3ed9c68204867a8d0893960b26da1aa185e23c0380af02f071129483c44ed342f63036e0a060e6610ed4df4b0588c915383fd57ea7819d82d6d352bf6fe4614839f76064c07acde0f0c0c276137c3d0ee5c22d401c97341751e81ad2fb49e0be4894d46a483338538450f2f89e33b8962bb837d36b9a4709c01922e13dd6577010001	\\x3db58190b9a37e795967d95182da7dd5ab186d181e5242218de6ec0b31142942af8d9b49f937aeeb9d2120db76cf8ab7c28859b1e64e27f7a312804281126405	1659686891000000	1660291691000000	1723363691000000	1817971691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
317	\\xeaa6be91fc5a90741c5a867e2856ac6472e527ce38c135a13545d0c918dc182569f41095124d65d7af64e616450b823f90bcd4e88162a906ed1f942a67ecb944	1	0	\\x000000010000000000800003ba673c1dbf3ffa439fb11c2312aa583e6b9197a3fd3c01acd9dbb4276e2e0b5e6d1addf9f69da4a7a10fb2d83d8fb3e705e0d7d927c18759933041bb2b3737fafa47806ea79dc03085c41357ad11b82af51b9df5fe133062de003e2c2133657d7ce5a8808db8a512f804fbca7c485d977a312736d7dcfb66fbbe0ada414b669d010001	\\xd109ca2126b481bc1913e037d96f91de2c964fbfc9f6e541eb2eadefdf56105ff48e37807cf83a514d8b114ee7235e874869b34a6623da5880513bf33a9e7201	1677217391000000	1677822191000000	1740894191000000	1835502191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
318	\\xeae2ed191f5e6214d2e6032c0da0fb440571357214a205a639c8951dd62f16668af7e7f2a2632717c2bb529df30498ba68618203efbc84fec6326be898cfb87e	1	0	\\x000000010000000000800003b0e784ee58335c61c62855996f50a526e9f497c986e434b0825f174e0ea5ef257fa46901c6a0603edafc23fb4e0ecd4d182251c017565633071893a36713e0dd0068000ffc9b2360680dfa5bf83793a957315cb2ed8422dc9f9c38f1b4a3c05c3a9cc7a85e0d134280e6377dda3f517a56a3c2cb8561c449ef1e072e0c1c2bbd010001	\\x9fece2eaffb1ac0645aa09c5c7c4005149f08ce7b0ccaa2c9426fe7e5edb2b14128ec8f6ec768aab4cc1ebed90b3fbddbcbb5636e07f219bcc6098cc2dc40209	1669358891000000	1669963691000000	1733035691000000	1827643691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
319	\\xeb76aa4843bdc27ff07008efcc7d0854f29ee1a356054da6f1b8bac1e6acd9d4da7ce93886a0ad22b2853be794d30a55f594a016cb7fd5d188877b823b390c24	1	0	\\x000000010000000000800003c89965495103a012e77e18efa530b5f025fedff967cab3a2bec5befa3cefddd7ac1eefc4eb2ff38d3fc1daf00e46e2ee870701bbf9ab3e79d05b85bf13f7914a413d1f518c7de78d3e41bde991e4127ebf95fe6502a15cd04dc7bdbdaeda408f037143623faf72f9ea7763a48e8f339b71fc1081d6d6ca9c353f2d4983f37037010001	\\x5bdad8022a0c89ce860909d9bcab156ef0f9d6dbd2c9b02aa5aee68c7d5dbc8b949251e4fe6cbf1602d956983a5c93a9a58a36e36a4114684047d7057428da0f	1650619391000000	1651224191000000	1714296191000000	1808904191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
320	\\xeede03179fa7ff45b2014bae994ed08b7bb86542b38faafcfe675540e9aa01b35e3e46699f97110a53b0b448e335c0de8cc2cc2291304164f9bc33e27ba9ca00	1	0	\\x000000010000000000800003d53826b0dd479be96ea3bc5b2b3476e8cddad25a1b652f1f03c3caf3b318f7d090e6dd728c88eedfd36087cedbfd6a24f8d1068f347eed12a4a3c62e61ff94c78d9e25d4d2b21f62a031dc28da98b55f42210a2b69b1b7ca4dcd75760826139151c4ba7539e202281396019447098896b822d510ef6276393b4484d7857ccc87010001	\\x8b562b99398492c7a5c1ab5f92e06eaade60302720749bfdd574e1e5157b978c833c82a092bcbed6158a132d9e6206985566f216d1d4bf58174e09ed7093ed0d	1657268891000000	1657873691000000	1720945691000000	1815553691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
321	\\xf00ac032c9b1d30565d5820dc617f7dc87c54bd8afd123f30d6121452c979508a0cca1f737a177209552e4264ce7567202cf8d4a4dd878b671c089bbc5567c62	1	0	\\x000000010000000000800003cde524c4ecd8e26449ab6e419d73686bd70d39b862fc4332f548768ee16a8e6c8adee61f985825b016e405e973f2d3acbbd5ecd8025527f35ceb59e592fbc6bae91bb58ede119903bb70cd1e8d5c21f0b87044b3a8aa2c0cf5ccc73a2965cf9dd76e06e62ae7207fa3e7e7b195670fe68f41edf2c37f9c815a69e1642007d4b5010001	\\xb02c0cbaeb2a84e6e6c0f65eeb9a92b2b0810f7d6fe786649179220e2b5813612d6446b1798b43f5ea78fe5a251f5acd6a1bc23ae9da0ace58212c309a35b401	1659082391000000	1659687191000000	1722759191000000	1817367191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
322	\\xf29290cc7808dc4d77b0826338de30e444a00cc60a46b89516ea66852dae062b522240d4f914eb05f9ddbc77015d355f3a89bf2b9538e90fa7323cc03d7bd549	1	0	\\x000000010000000000800003b09d9c3d19c2ce176b3a0dec766121a7caef901b130c65e3d2e1c86a70805caa6fbe11f7927cc5cda3e68cec2f6dbd37f0c61a1e1de87cff75a2c97d89816e28fdee7fa31e9f9d35087ac2506c846025d7a5c46ec4d7e929763cb6e9e7720b09b88054fc6364be218896d3a31a09820ee5bbe88887ef65a196c9907540f2cfc9010001	\\x86b7d058f1f748f60519649f7c41a1b37e717ca4e6ceec4c28c2d898f4d8938c762c86506559eeb9de2327542bf187efd6aa3c42481052077950060944206304	1678426391000000	1679031191000000	1742103191000000	1836711191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
323	\\xf5beb7c7cfb20c05e66d52c8753be2474e686ac249811bc4e93fb5aabe95614160c7673f2438dd915e73892205d43f38221951be4447ef53b4fd6baafebafa8e	1	0	\\x000000010000000000800003b55c4025914c0670bd9bee5d81eec124cd69d6dc56f5fdc2f7804f9eff1bca089da5ab0ae6dd3b1733f5f97b88f47a37fa3c7f23df220bace3c106812ff65a9d8288a3e1cb367afd4fa42ba26589fecfb388f052684e959a1eb187bd1e85d2675d88b87045634e61c533f52dd9e50e6b56c07b7cfebfb087e4315f9691c8d2ab010001	\\xa2a2109d7a1b0487a016eb334f7f041dad4620aa304b284256c55f8843865e501d04b3626b37a6a497de7ac0be8535210e49e393de756c101be71cf4eba27709	1669963391000000	1670568191000000	1733640191000000	1828248191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
324	\\xf73e6f1088e5d0e57513a9446a6718ad3e8832a4c61f4bb41fe05909ece05151742cb24e9a936cafb89ed67d05d86a27514407f961d5d18ae3074e215be024a8	1	0	\\x000000010000000000800003d2bd855305aa4c7c8db7fe9f8f0a9559c21456934f46976b3c94955085ddfdaf1fa2148d37a2338dd991f31dcff8ea73569e7b0811b48c6db2854729b090be863aad4b9e2b38417676b199a5d590f1a2c400fdbbe9e8fcd6b0628b969c4aaa065bafb2608b21183857d55f4e34305d1e3432700f74c7b9be69e4bfb9a600b6d9010001	\\xb96eaf604a3bd785ad20e0e9cd9444a3f56ffc9356f869580bd618bf326cb210d59e652b3523c6d310c9c86275c9497fcd4cc08a5bb61fe51efe41d1ca8fad06	1681448891000000	1682053691000000	1745125691000000	1839733691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
325	\\xf7bee1f2002a7f6527e06dfa2d1242297353b27324f252ac9907e15d3423c5f0071dfa74fcd39b9803cd08b91fbb13189063617f016921b54dfe46b973a1a213	1	0	\\x000000010000000000800003c03ba4b76c3a148f5bc0911ca5b42bed8776edc46fe5ffd58ee4caaf1c287f77ae8c2335a9c667f5cf86c5b44b9a191870b89406efd3e8da32ecbdc9aa0a7567ec08cf1eead1e9f7dfa6c03e5066616249e635d277f7c0bec1bd2d1a463298af20167ea849bf96fc39ad444f68b24ddfdc2e4aaab237bafa314ee03d310931cf010001	\\x9f6b57842589b8e22f700e757fbe2612bebb1bb6a3889a4900e3931bf297047843cc9d3ef488e5cb34caba5e28a900cd2f5d063abdd931a0e2957a3f3a4f3c05	1679635391000000	1680240191000000	1743312191000000	1837920191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
326	\\xf8d2a4d609ac46ec398412ab91c2f735b3285903c82c9b51d9a883496aefcbed4b6f6c261577e25a627cc357ae4e20d86a4e155eb806147ce2e483900d7c2353	1	0	\\x000000010000000000800003ca093a8f7f9c4831cb5bf5edc3c579c2ccb627a70e7c3abe44beec7fe8ba25792a750e3132a32b217e9d4385a67776dd17d2f1a47dfdcdce315ef980a8b53b667f1ec67159c1e3f7b39dba3c30064a67b697f2cf8335088d2056d5f3d527959158fe93a11a4aa00d869baf95688a85da3626cf73421b39d813ff12f25d13fabf010001	\\x88b28ecc2792b66c6a62885bdcd77ae118fc7ad843090d564889a3f51da6a750647b0483a88e6f9ebb39a1b1f9210f5d39a8161efff892edf5edcd0f7ffcfd0e	1679635391000000	1680240191000000	1743312191000000	1837920191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
327	\\x00df0021097b801aae85503d6adf55fc962872b24561f8af794e3321846862bec72c177d966bb893c2ee6afce5cabf470ca896ec0ff342bda5e6bfc785a54856	1	0	\\x000000010000000000800003c29de1fdb03002007139e31b633880ad50c015d265098a4fb64a2ad214e55312959472c5daf7230a49d1c0d2878f24c59a047a45296f3fb16667ee06a3ee343fd6dd911083b2039284f4a3763f17b7f2d08c8c29dd13d82726422f12f18406fee654849f5438bb5f8bf4f071b1c706ebaa54d4f548044676b4f2322e0c3fcb99010001	\\xee47f2229657489a0d4f65089268c9b592f46968b9fa7af20690d170015aa384a0c725acd24136ed4630663feeef3a18e382e13aca6889d40a06670a9e82040c	1669963391000000	1670568191000000	1733640191000000	1828248191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
328	\\x0703e15865f97059312db4acabc1457a7737ba553ee7e782c6e53317fff999e7ba24d181b1483f8380e85ab2d2df80ad8571c51930922d696aa6cf1ba2fdf9ce	1	0	\\x000000010000000000800003f09fdf408e2378b8c52f5a0699f8776a1da9fdd680dcae0a56cb1222daadb3073215d7241ddf363af2e4c58992cdf94d1c3bf37dec07486b7922a0ebe35db3816d9b1b1c8beedc534975c864375f677afbecba642e29f9ff8c97e7d84467a86a64c3eac94dd0f6c6cfb3905676cabf1787265ff45de6f2f0852814087f50b587010001	\\xc1d6d7bd17137bad3ac1ae595df94362e49da2b1f32da90838786d982199d01354e27074d3ca8baea7f93fc294db09f8c956453f9c8a1986299b49fd2449a207	1660895891000000	1661500691000000	1724572691000000	1819180691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
329	\\x089fc11e7053d4e54194fe3bb4af725ec703dabd3cefc4ccd2fbe92a7912ccddb2775ba7ccd197eccb4e9b42f6a86f6d6bb7ab31273c629a33484c8a96f8dfa0	1	0	\\x000000010000000000800003b388e98fc37693c920d01fe267bc4971bae44c93ba5167d680be64a86d01ad8b050f4d663ad99891b995f43d0a626b0cca84e18fd668088e078380043213662c5efdcc5ca43fb5d53198860e167b19eeb6a15329ec939ffc84a017a8869957786898f35ef8a841b59f04a32c564f553a722d7e54d7b8bf3ffe89012e6f8d12a9010001	\\xb81089e5d5d510b3511ccfdc79f54f1ee2a5b1916d189425ae578e335175356fbe32008b1f119e46626b1b713ce9036368fc67243d388abd7da859774165620b	1655455391000000	1656060191000000	1719132191000000	1813740191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
330	\\x0a07cf4c39044a0fb34ec200e1778d7b757362a86476a4d0a42b1aca8c1a2b01cf0e1537c8254a26fb6680a9857df75a2ed7407662ed7c46a44d4ed4ee51955d	1	0	\\x000000010000000000800003e5078c73b3f5b7253a05334935c162b74cfce34a37911e2c4ee7c84332d35c25aadfa245b2c071da8b1115ba81bdde609ebb7fecf2c3c85a49aa922f716522b1fe48606fbdd3be511de5ff9a4bda9f27fccc77ce91cf7ceb3b25ef02e0d82f572c15d32e1b66d80c16cd31e692c368744a8bef2972153cf21fe761666bdaf353010001	\\x666299d7e6627ce115ad5086dee2832a9f204099d6545fb3e4f129e603f98abbbe54b08d2eda6113efee13b963ec5044c17cdcc592314011776de4796aa6630e	1672985891000000	1673590691000000	1736662691000000	1831270691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
331	\\x12d71e1d6800f61fe2fad258f79820340266bdd7a21dbab765127241616d38383caec89784ea0fb2b9e08cbf9ce8d6537c688be7d2c73d4f4e4840c9e0d7cb37	1	0	\\x000000010000000000800003a18964eab1f80eedca5ab62c3641bd100a7de0329dd0549503700aa62777a9d5858704ef3b9de5beb0ab7835278fd6222ccee2a27991afe06e2f66478ae04f110ecc1ac6e635e84f9a24ceb7ecb1bec20fdbb18b417c65ba828ec802911d7604b170535bf186c03c6ee99d21be83f8176df81797f8d362a85913e4f96bea83f5010001	\\xa6b24e539eca4fb1c18946ce5a1ab45e2a3f9cda7360b04bd59600081dfabf003082db32d258965e127a952a35f5ad50bb09b52ed302d3633b074936eced900d	1662709391000000	1663314191000000	1726386191000000	1820994191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
332	\\x154f6bf460794fc9609b3c316c5ad3a2e3f55f002f2bce3d92917ee72b507b2f1b58a0faaa201ddf1b902ceb36c04c0f980e038be8b450371a36c56e5ee19cc7	1	0	\\x000000010000000000800003d4ac7bc5f4ce438fc13686c2b8017e8fc5daf7acb07e80bdd75c00d6d1e1920e845039e7acc4a422c805ff7ba73b136c3cd04853934805f63c2466adf00345e817c0a8584146a5cdfc3624a2f915ba8f080bc753dcacc2b12739b66c41625af1894a03bc13b7a76caae07dac0f57b94e26eddc03052236a3c53bc1b59e9705db010001	\\x87955ff215639839fd7d255956b4f648ac6cf6a1cb7c29363512116452176d6155665afc16fd8a98043e3f1fea8e08aa6b1fa0e0573f340902a850ee20e99c0d	1654246391000000	1654851191000000	1717923191000000	1812531191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
333	\\x166f81d690ee852fd96145585fff3107be154bd2e0e8506d3f39b4814d29fa2ed0902ad52dcd0b7c63b2240e71cfd5a10f41b8ce0a11471d116f5d3ab9133ddf	1	0	\\x000000010000000000800003c3956254f1da274dba77dabcf72ac45436624323714696a647d6e419b018a70dc0bbab0efe26adc13ebcd0a20dbbedccb00968baf6fafebe45cf754d83c24f0ff9d6ac2d63ebedc03bd6dfd012b5ae4610cbee58fafc813804a0d7a4477b0409ebef7e99d67edfb6e75defb715a4f4686fca20009dd5eeb988b112f7f9236585010001	\\x9a19494b49fd51cbedb665b08eca40f5486e8092d4e626781b33f30cd2cd3068f5d0093fdd3b96d2ebc82d041bdfaa970f59fc0c474632315e8d78205f3de104	1674194891000000	1674799691000000	1737871691000000	1832479691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
334	\\x19d7188684d063191a943e675be0a69b25d34948383b29edf3e186cf7986ff7146b6f4825c3a7f44cf59d61cbc1f6444af1becb66df9b31044349092cdbc2df6	1	0	\\x000000010000000000800003c1d2719af106dc9fceaf8b989974aad3519e779b43709264d6d2f2a85b1ff31410b9f4b860de62d765b64d8656b5a14551ac6445bd4be295ccf6df8268e368136f4bd6f1210ada3f25c0d66b44eb79f0f967fb9ab75d642b1a26f3d240d4874dffc167ad10a8cb21ac70fe144ad2e3f6609f3e85cff6a3ae4468b40f4c511f59010001	\\x3eeecd5ac9975c7fe4bf83377e7aacbc6f114c67366669b7a29d05ae6ecb29320b512237c7809f6383ff5fe8e8a2f6f8d1c0acd03b85e24d4d03b4460c3f2307	1677217391000000	1677822191000000	1740894191000000	1835502191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
335	\\x1aff9722062a51b339831183b0ddbe6a27cdb769610e5ccd2e836ec898d09d29260b287fc2efca76060ed232c3b3c5c0d9a77cff2e14fddbe2bdb4fb62789404	1	0	\\x000000010000000000800003c176eb12ba07b8878d2468f40afb8a91a60a8c9b408e2ccc6581d17bf46ab9d5d1e86b6abadced044604c88c91a617b5888c7df72d6306ce8634d618aeb8efeac261abf45f975b07d00eb204f9e4ce81eae4c9f2b75ffc3f780f871b1ef499a47c9cea34562028f9c20a911b646025eb5e23532f27eb43936ee13d1184be1b81010001	\\xfa0cbc4302ed0ef481b78fa72bcacbb3e54ef7c920b5ed8abc5c6f2d999ceb957d1e2d65e992f3fb1bf3ce04d709ee7c955162573e6a717a703019cd07806b09	1661500391000000	1662105191000000	1725177191000000	1819785191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
336	\\x1dffbcacedb51294c85d478d17a041b77c34c7181f264694c1081ed85bbfbbe04f032ecc29864da8442f507ff2ac8c69202a66d05d7f604fdc9ae8a2f545914f	1	0	\\x000000010000000000800003a530598485e18a91f138d883c006410d7727b805399b8ebdfd1126ab6f696a548f072937765e56b3fc13cddbf955c916bcee8eea199505ca9b763b332c23ba6ed2bd2a386d8b3522701b3ddcbf59359fc2f65e3eb2e90623524c9a9ff3ec05394a0ed6cfa34fc055125bd206d024ae9737fd9871d423fc6b1fb27fab83f3d26d010001	\\x42e5b411f1a6044f8d87b3aa9b5eee31d5de0db95e3a82eaa492efbd702f5624cdb19473ca4d2c088d3a7d5b4e275fee22becbffd4e2615893a4a8eccbeebd04	1652432891000000	1653037691000000	1716109691000000	1810717691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
337	\\x1fc35eac40334730a168ff44e713f90ef107b3556bfeb44981dabf278e7c902659f6a05b968876bdc44c12ec31340f8e055da9e824617c93afa47e75bf3852c1	1	0	\\x000000010000000000800003c6e7c1e069a28f738cf893b1689c3d8e0f5cf6a833bbc710f1f0910adc59370d9599a451867586f0a6b3648b12c1de422c11a013cd89290880e2fcc96b36f154a118c9a3fb35c45bdfac2016801fb920953c934054fa199ededadf3fb86294c7968e07b4ee7499f8af49745742a9b9c5fc4ac407973d13862300f7cbfbe0600f010001	\\xc9f2996d59c7a3920a02b3952151eeff720f70cbc5125a0267673c30df2023ad5ce4ea7fcd9dd9aee06d4b92da8b9f7d469922b7a1725ca954d7395aa931c604	1681448891000000	1682053691000000	1745125691000000	1839733691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
338	\\x1fb771576cab2038162cbf3b227cb5e78afe975b70aa0439d4b08ada71ab2f065cf4e8d0fd111c88aabad5a4de9ca8fee9c196060105223c34c053d98def2c51	1	0	\\x000000010000000000800003c39f6c3c5632dbac3775ab0eb25ec4c8d1236474f4c464f922afae805745323e33e6e595ffff7b14c627aaea45c3c8accb65de82034ce193bae4d23d008c44e40d713035569c5a8db932602cc6add669b07bb9a2bbe43113fecda455abe0ff3617949ac002fa94ea96eb2df1cd68bff4833fa9ec525d128a7f5f0e786aa6ea0d010001	\\x43a683e14246d1b87618adc41a91c97d40aee52e1adb0fed69ff762ed71c369bfc2c71896de1da032047a0a5b313ca7fffbbe7f0f07b2db7c8947824674d8709	1665127391000000	1665732191000000	1728804191000000	1823412191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
339	\\x237fb9733b9a2ea3a5d94d558da4d9d2508482bd05359d158c3da35d92067b55956446e503c4ee8b21cd134c12a4ffb4bd87e0aa74591286bc8ca65e87ff903f	1	0	\\x0000000100000000008000039e05f3432e9a3f7066eab1e2c78c61dc1611ca09c35cc75faab9bbb7bbe5f6118b35491a29844c090dadb394a1f9092731685f9f64dd53e575603a26e31ebb5752b467bd31b40a28c69de6e3f667bcb45bf6aaa012d43fae1a453b0165fc3b8b4d7e24b2803de632f5e2c1021d428df802a143dc682e5940c4fc14efd6036081010001	\\xe5d4b9b96aea92723f6252d37b14db01ca0d6fa133e1797f01e2b6a236f96e2e5eedc44e85131c194ec48710d7293abb8ba428a466256ff95a71c3c0c9735b00	1679030891000000	1679635691000000	1742707691000000	1837315691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
340	\\x2527b27529362a15fbb80e2cf1ad2341b1e456b427e9669a956ed4fd2ab8dc9860a49bffa9adc206049520ee2393f5ae8fe6e964050ef6ffccf7cc5efaef5285	1	0	\\x000000010000000000800003c60263f3f014f890ac717c96d7fbd934e6f9945113668391c5aa4fd096748fbe4df7b08042bee023e9bbb1408453a8275eab070fd97ab423ba7503331c25e3b6db7058e048f2984142ec0e0db01df6fda58c3957aa50f79833454723d8adbbe363af4751ac96c718fa14679b6b297412f21198df5e77e06c3bb11f77f8f9d875010001	\\x6ce0d9c8e93e29241a6379d8c886c2dd1e71bfc0e2616d69c8711de4f70d2f29a034bcba7e921ffe7fbe95c9206a2c86853312339c0b5fa46e2019388a75bd03	1665731891000000	1666336691000000	1729408691000000	1824016691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
341	\\x27237f2191d995f6b7ba2ce75850b921354f9bc52c3d3d26d73762ef0b1c6d580bd8d6129fa5f7d3263ca60fd7bca320c7d3ae5f112b683728b991f9dff09609	1	0	\\x000000010000000000800003d952d966ffacefa04c2e0071b334162bcebfb293e1ef572f3aa516eb33193f987b1088d4323a7e86d0edb7ce806444fa7abe3afc53345978919883ea571fd3da9239300be4bcbac7759ca8093f6db20e422647f00fcc4df06ede591a3e5374aff962d79a53afcdd844815f9e9ee0c1047a8be9aef75726617a7e62af27875489010001	\\x8a1cd55dd68146cfe97644c203ab57a2e51103d8084c4748918e407da2607a9043d4d9ca31e3f85ac3b702dae406b76c4a57fc48c3fe2f778d7613a637357901	1653037391000000	1653642191000000	1716714191000000	1811322191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
342	\\x288f45e0c3666361cc6a6c7c30791572fc80fed5ed045e93bd066de362a8ffd333a2ca8d2353422c8139487fa1b438298693aca0037c6abcab06667217004175	1	0	\\x000000010000000000800003d26a7fb0ad9f6af5c2f65cb5c85ba3bc0f184990d152c9226bf687efeae4cf8ff2ea3cefb3763bd68966491f941df1e53b72c415040f3cb2135d15fa83c14217f07769521f89daaa1c8bc23e260b53c1746ae5e28928ca4076b99af173c6e0c47a5538778c46c06131b02fb29a572ed44341d924f9e8bdb6e752bd067ca5dbc5010001	\\x0252e105d84e58c7f1cbddac17881fbc494223353fb9cd9b53e5177704650530fb3ca462eccd7d2c6314964d640c43a64774d05ef6345b412a3b403208f47d06	1657873391000000	1658478191000000	1721550191000000	1816158191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
343	\\x2987222b219ff98133a06b6411851cb434a8691706bc8c1d1669c23d1105c96fe6fad15e6605996554c1073ba5281560a9ec469c2b24e7b4df8524cb781b8951	1	0	\\x0000000100000000008000039769b3faa52d02975d84c59cac9aeffe94dec413d4c6aa88583a634575786131747c56ef7a4ad73368046883f5eec9ab068f28ac657d94f8f1d1606a61c8d93d4ee4c8ee170ca4ed55c437b49cfb43f1a3c5a2c827b1ee4c751472900fbdbe88c4779e0c0b918fa3c80a8f4ff905b9f49b4491981f33195f7fc4907ab088f695010001	\\xecded23727de14cc757febfe5dd73b4ec81c356cd0ea279840c08a9628967e52b8b5fd0e662b7d1b083af465519f8cf955ed0af581da2e32a2dc11006a82f800	1676008391000000	1676613191000000	1739685191000000	1834293191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
344	\\x291f697fdce7f045a85718a0b1e3fc3823b42e98b6c84f4d4b533b6c1d5a03ec50052d7fe95fe5ef795184c8416a4d2f34e0fffe0dbf2c9abd5bd6cb6f219514	1	0	\\x000000010000000000800003c2ef702a6333aaa0efd5c4deade342800d31f4f1f10656a30fc83f35859af687da358278b0fd2e62bc7afeb7bd51efe093c28957a6929148327d07b4cca61f5215c39867c7f120d313c69c562605e356674c292eefbd2d74ba9cc981ae24a1f44b7a514afb9c357ada7f371c7cc5e44adaa7ec6d31f0d2252aef8ef6d0639149010001	\\x381e3dec60ccd60ed74363f39488ff50e5fe3944338e7f80f47a2ce21733a548cd2e145180c5d37f9cddb3dd4fbd4e86158a1ed21375b80065f0964e5cca8a05	1677821891000000	1678426691000000	1741498691000000	1836106691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
345	\\x2a2ffb894fa173de4b857e78ed896f77a91a348b85c0fcf02fe8f5822fa3b3de413662b66d3be5a20e89e4a1023877e9d1c7c3e298de13b9ca0ebf31e793b432	1	0	\\x000000010000000000800003bcee255262fe821d9484be899ee3217bff651d9189995e98494bcf96ee7663262f9440c84f24ee906b2acf533d65f74b29b50622fdcdd1e65357c43a9c9d940de11f7b62fc1a4e5eee5036464ec70d73301ce8d4840d9e229c67546775dcb81eb7da885410deb8bc1f8b7eb032525346244e4eed306e2b154684273b6f72aa0d010001	\\x7302c27744d04252665e84b002851f3fa09ff8d5a14b84f5fa55ab6826a173f08d2abdbc5090eef0befcaaf7195632ddba0c143fda9df0a0e3b557aedd2ec90d	1673590391000000	1674195191000000	1737267191000000	1831875191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
346	\\x2fcfa5fb95a2c4b89b4f59f522a65302f088b9d7f7c58661f0268eae29ac21f0013c4cc03bef80bebfc8458132e91d01297abd18e60f59ebe6deeff9bfd8ae10	1	0	\\x000000010000000000800003bc8d09cd6f2abbca3629fe2901661823deaaecbab782194b57216ab815a76496fb9424dea6a310ad179881ea8aaffa3d9c0b71d8d379ae5bd4b0164586f8a60f00071b9c270a3f2e8b4b660924b64575cf4bcdc834b3ffb7bdef062e76de8c98bc6e18ea48e00ea4e05b835a488043162f4b845507a6ad71de48fb834aa118b3010001	\\xa9764c42de3f21796906ec156cf3ad5a1a58cce3880de64e853cbfaca0ab31c9fd628b679846e799250ec5ed25f3d3599d71fb2fc6e1f0d3a22450ba0a65fe0b	1653037391000000	1653642191000000	1716714191000000	1811322191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
347	\\x334f1928d06c1f8bcd7b0cf0a7acb6c6cc650a2e74f00d138743e1318f251d092444957cf0c6c0009b1e36a6ea3ccda80cbfa76dd8158875032bcccefca6fc22	1	0	\\x000000010000000000800003c10be9796a508e76336fb6459e596a901b2343f416170f27badb4784b16cc8037e5ba237019e2a1143aa0e868d53d6689bab58900bde47f1c5eb95fe17110aabd2e31b24e8a8d245027f31895edf5e05cf170bb19e9f6eee437fe087ad9453ff8bc533a5a02a3a94d4a18c577dbba576acc2a257e903f161147f7db8a1297683010001	\\xa607a3b8f66dd958d7275b34974f826978955db0b1211965377923f3fca76c581177d5fe7961a2589611ac4eac026ea26ed36b65640937379026f43c4169440f	1658477891000000	1659082691000000	1722154691000000	1816762691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
348	\\x334b9a3fb5bc9134006b650f73345b762c9ac34da4c86f7ebd8c63d7ffc1d83376057dc2fa8adbfd2e0c32050414f642daf8d38f5a7790eab074776e45788567	1	0	\\x000000010000000000800003d8b76ebfd7295479a7f5f2184d95284379194604a805e8e3a649f6175619ad9cc1a5831a1b0e7a7562cdef747aefdb8aee6f06489ec846d812312dc74716ea29179e4f79d18d2da8fb79ce047d7d8b00b903e573e4bdab0c05f823e510454c5ebb61cc6f20ee6fcdf84c34375d1ef0ca5ad4469a282bcd4b4592121d46031cf7010001	\\x4ac1d57bc0f248f64ad431745e07c63156766e54c9f5f5f96dbaf7eda5ff7101ece690f14b1ddcffb06938760bb624ae2bfa496a7282d3b194ed5820a72f4c0c	1668754391000000	1669359191000000	1732431191000000	1827039191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
349	\\x39df135928458be8c6f6421150f0f495b92bbba0a6d462b82813a74578b808d011a657d17d0b12681c8a8edc34a233a684033ac8ea201b145343dbf56fdce36e	1	0	\\x000000010000000000800003b127dc91c84c32c4ca3cde24d8eed5201d46f9caaedd91cd59d367e3c4961dea18e44c4a63bb78a295a9a66d81d8ac3c8e106c84e7439d2d37aa804c93985153006f2cb415e041ce6795f1229cbd7a9b77a150637dd1927de7eec82d86164c729873fb71caf184b526555311d081799759080af1f4a9bfff490126b2b76b9957010001	\\x06c2f1ea0b7463779cca3d489f957ae4007ac594a0c5bf16cd3b1e3c5362a5209d6782ccaf86ce2340fd7242b0463678f27cc4e0749c631bbe1f0baaea4de606	1679030891000000	1679635691000000	1742707691000000	1837315691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
350	\\x3aff08cf36ac903b580d99b67412aa5214b76b4991a2d80668cfde0d1b5c0cf1904b69cc118f3e2540d252aef473ed09e20c4a2275c5ce5974bda92fcac2b776	1	0	\\x000000010000000000800003b00b2b8daefb0fef235fc429708033d4c52beaaeefd3d5054820f9ba182fb28e802cd5d03ddf5f4f6f7d4b7ef223de93851230a28cb3298afde94c2c35fe208bedad54c9851af5386951db0b7fd93aa79cd644a9546d31141fd8436bec5e57c5760be03575bdc31ff04ae0e30a203aba032fcdf23a3b0ab17eb0e99fb07d05d9010001	\\x2fd28bafe247c21b1e2dbb5ad7b6b48112007b5b735cac32aa5287afc5676f5ddbacc08efbe0f1d509332d47a064a48f875221fe0692e55677a1bbc708ca630b	1681448891000000	1682053691000000	1745125691000000	1839733691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
351	\\x3c43bfa512740965b54f41c2765789241dcdcd806d42ce7ec45c26646be934faafe1b864f819aacef3aad6ae4061165dadca548744dd8a59e63d34b813e935d4	1	0	\\x000000010000000000800003dfd0fe19be8401518ee99c864bfcdd178b8c309d8f5abd16a468c2075afda34fa560e93c44dd75d723e5c70b0dea2c18d1831a144a37609e783d8f9de829585acb52efc54111e76ce87aa2c62e149df4515bed6d1a9c6a6af55ba08277cb1ad1bb49318c37c0d33cb14ad1bb1c6b49da2603769b225ec4c229f229e1b1ddd497010001	\\x7a98b35828a768456c95999aacdc2694d4e7041a8d8722aa241fe7767d750fe3ded8499017fde4a110938c6e823fb16b3b279757943106af36b278cf72b38408	1653641891000000	1654246691000000	1717318691000000	1811926691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
352	\\x3cc3bf35eaad02a19812128afce543981e8859319e5fb679c6cf06ff488f299ebb082ef7b3685b91b71aee38a3aead385731049c40ca3682662ef7e59bfd1d55	1	0	\\x000000010000000000800003bbc6b32dd3c83954c9057ac227c3d6f27aea9a63331712d57547e8ec26c6922c7d9cb2f1fc721786993f2509df10aeb868d71e034539631b9d431747e0b9842295c152dd7e059d3af8885cc201e66703fd535ab644b2344c53bdbce158822330f1a8a2dbc256e645cab1078c2945191afc8ea5d3a814d1c1465432564b6463d1010001	\\x0192195e8530fe9cb0dbe9d4a6a67c5e6a7512fdcf38bfac06067a70f6f122907eec9a1912c6bd1dc307728db25cedf2024d74e6286c4f7b104134e89c5e3a02	1662104891000000	1662709691000000	1725781691000000	1820389691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
353	\\x3de7121b1d2266718c0191bb62870a68d0067dd7f1a2d29e4aec354c0ec78646956088c450fee6986b0eed2dfb179d3cfac339e916127d5482d5585b2f9483f5	1	0	\\x000000010000000000800003b0e93d348ff0eadf64d42ab3100da17fcc9f3fe22762905ce632024763924f27657be0f4069a4d4fb170d2fa4de4f90510063d9771463ef11ffbe2565d54a4d07564c3a5fe434462b7770abd527f7d8af3b8f66ec3b5719c70afe68237c8908f20a2f5605d33dbb7f8f57da0c5777c6e7edfd9f44ead265e628dbfff6d8109f7010001	\\xb21b422c976afce09b124d4700fc11e29ca68404a85d4b680ff9b0f60563417c38e0136ded81347911817a5c61bfa9bb43467c71bf1431236e308cb2754d6d0a	1656059891000000	1656664691000000	1719736691000000	1814344691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
354	\\x427bba03edce778e79097a96c0bdd8d1ad0dfa40900eb8157ee2a69b47de60e5dd6813aaf745964880903052c06b9436f09957300b19d88c05f159ff7fbbc146	1	0	\\x000000010000000000800003bb038092533492dc1ee49eb9e2d53ae5925a4d7076dbcdaf37d313b658234e523dc2f09ec953d487bae18717a1f1b5b2d3439c5c847e714ecf319e5f419c11cc81fa50256f57b50a561040993addec7129248665d2a248262c0f6ef44c88e4ee532a2c08341f4619cb785f7698307c778fe338d5a10d2088d38c3e04313865d5010001	\\xc3f3059e68ba5a16a9cf948ceaabea3c26c855660fa3f7bb3b7a65032941375bf1ddcaee3495cbdc9a205c15ddf6661365f6f7f56093377b0dbc107a20e3dd05	1671172391000000	1671777191000000	1734849191000000	1829457191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
355	\\x42276b99b121f2b6ee0f35ba5c135c75f128865474f0faa692b125bd2cb736b619345b2063b98c3e28d69696bbfd58a070d792305c9ad6bb55ff1b39409f3733	1	0	\\x000000010000000000800003d68c116e75da7334d498874dd14b1b8616a50dcfa7697c5fb78b4325796b53cd4b7e98fd00e01e1416cc61febd971c26428a0c2bad74f064afe34d765376d0edadc4cc04a092476f697918f780fba9e9c69e7197a5e072d6b26d23b553f76153e851a08cccfcdea1062805cb0764a9f63f80467d6f29b41c1e5dfb55bf978dab010001	\\x89b5347fd7032ea301c11d8e7568668bbdcc574f0a9e9ef5c8b33bff65e7916427a9e6d13b9cef1989f7bd880bc56bfc56b653f099dca929628d2448a75e430b	1671776891000000	1672381691000000	1735453691000000	1830061691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
356	\\x4363bc8f74834e4386e46ff038bf230baac73dd2b420a87c3ea50072329e77f410690832e0eec6a754c4caf5671295dc939167cd7cb6559adccdb65ad0c1fc77	1	0	\\x000000010000000000800003f256d89ea868f1473701c3d4f1d70206de0f125e38221a5816a1a6ef9202183b7b220e83057393211f0635c4bb271845b06690291b35a1af36b1764575d6a81dfb6fac8de62fd96b2016746780470aa1b0e0a6debfcebc3760f384d8064080d8b7059ec519c20d3abc89a686dac45e20ec0b731c37d517e91cf7f412e1e55d49010001	\\x5f453478f18a6c4f47eda3d5b333d838924915fa10dac3d81eb45ee246abecebe2861f442775f040441d0014adc9fdd34798a782517de345cfd8f412c17c1704	1672381391000000	1672986191000000	1736058191000000	1830666191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
357	\\x430348db7fc729e0dd891939baada1bcf7883029acf87b75dbabfa1c808091196c3ec357c72c3b56c1d3169e58283e64dabf9a5af2af63721072c5b5910bf410	1	0	\\x0000000100000000008000039e5ebe2c311594148af0916db227a78a90cfa86e9288b14582cc8e4082d225f845e0f29f3889a7da5ef2fe22ccfcff6f20b9700c85ca3b8a7935a2f0b793ac347a1f0f4d25c89881fd94acf942972b3035b45e5300bfe677f6d72dcae37f9d14385732e2d6277e8e1c53174110356e0badbd175b33e93e88c17e733bb0159e31010001	\\xe45712509fa649040335fbad8e4f8d162f325ce546c0936df294477c104c0c82d2c07713fbddfadd84c95521f924d6de0316592694adbeffe0130070fa06d801	1668754391000000	1669359191000000	1732431191000000	1827039191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
358	\\x443b5b0aee8237ed59a4aa6b5b98282c9c4ce09c789264a397afc77ef63dfe4e86a9ca886a5937ed50d36f692f89533e58e6f45ac54edd7efb5d6feca8030ee8	1	0	\\x000000010000000000800003ccef9e192fe23ec603a295e32cc88ef4cc1ce5b5808701468ce6cc28a3acb3f6efce943ee308c84bcccdf3596cffd5b92916f20951e7d381b6d69105dbad15847307e930597e77ffd1bfbbeed1919cd2e2aed41e6b060a38d054a558a53479c862b11210abda0f419c57ba321b4436029885ffb4f178d7890864385dad2b481b010001	\\xeb9a514b5554333650c75f8387492c037b78a6646d93fc4b74937c3b54f70742bc75688d19d888463d0f935fd2aaece6a88ae96f59a79ad231a7d81434741c09	1660291391000000	1660896191000000	1723968191000000	1818576191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
359	\\x45b3dfa6109d2e9ffc901aadf43ded590822cb19a61cd82f52db5c8e74d4d9ad2f7491d45f9fd736060782501a7a48e6518e367b648e394832f10abdd8445959	1	0	\\x000000010000000000800003a063a4c5050965a8e9eeb456eb2505c0405b1cef1171e60ccadcd1585ab0a7a4446dacc0534340e04ed4ed4bd7daee9e7f5e91c16605feec8f4b5d7611610a0caf2e7d8ade5d48d4cb7f8288c3ef037c3f1593da0ed1ff1d79fdeca9b3a848230affab5fd8c6f9bc2cafa418c126b31fbdf8f6350feb0585c36d446fc98825f7010001	\\xc9614864eb9897a34fd14f93e9bbfa409d37f62787bb26a10931483f5d6cd29bd8186e22ba0bffedda388a349079569538a31b67e03b600244fc597f8bd48c0e	1679635391000000	1680240191000000	1743312191000000	1837920191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
360	\\x478f1abff8dfe02cb5d1e6b0684366281e498055ea511fe8bd57f5585dd1baf5d9a89d587705b7fe34678604a14708a249864b3c8dac0e34cb618beface91ea6	1	0	\\x000000010000000000800003bd2fb698f61bb695ae1cac18bf9571c5cf1b678d69f1b9b9cad22086ffbc50d2b7f4ecf26bde7b70606f6bfc44fdb97f84bd611fa6c4e346d33a382d458239574fab0a56b2c14886537a7746e60930ad5c5787d682b1f38a63be4be12f2603e9c0f2c16645f9517f1a0387c0c581f1157f2fbcfeaa0b862a61b70c7006fd097b010001	\\x7ea962855e6fca6f1c81569979edbb4ef5fbe4ccf5927b6ca2284a00f059f7df9ba8d85a747fac28a2e5693d88a66498b714b729ef9561bc5883e7b694bf1f03	1662104891000000	1662709691000000	1725781691000000	1820389691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
361	\\x5d7b6f9974bb2b48a8830ed1cdd8621f3a7a71986faf50260212fdc668b6f73f5e45e4cd8cb84fb8117c91fbc1a609d8f11c9893475ce14a58c22f66cd07f739	1	0	\\x000000010000000000800003c788fe8fd4ce70e60961bf06dac6a32db2c3e092fe91a1adee990e1b15bdeb012dacc0e2ec3d78b2200bd5d11df3eb2eb93b895f922d5771a03ea68d163ead14d11d06e11ad09c659c3ee9c84c2fe1f65afbd9e89f84717bbc7c7fdfcf41e49416f0f8c47fd9f0de2920f44be48c40af1b020c114e99557f3e563343d7395795010001	\\xc039051679f98e4e5b08fad982e317d979755a0cfb064588d68d82c8e4973b84be1480fe45986fd5bc654bea80f8f8f797ad72252c870b153e20505d927ebe09	1665127391000000	1665732191000000	1728804191000000	1823412191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
362	\\x633b6a2e9292d709e518dc0b4e295dc6ca1390faf9f3b0547d46c3cec090c49b947d857e384add1e39b2e609259dfde55f16bbf71f85e791b9a6a9e009f544f5	1	0	\\x000000010000000000800003b9dac28f35886c19f2f798436edf8f0ef926daec16eddce5a16402f77e7092e0436c252094fd6723a1d89799ad3e961119d4134c919288c824c737b90339b8c302dae7accff507ea7f2fe68e2290c5cb2a7eb7c4cdd92039e56079f5fba30c82126ae319af9f580dcc614e42e8715c81a1c7cc0b2acb186e3b77fc778d154843010001	\\xb927517562f849dff0715a6444cd9edc2404332e0c9963152b1fd859cf6dc18466e8b92c495cf4ee7b70da214e1e1708c319d31b0d92c984b0fa099a67d34002	1678426391000000	1679031191000000	1742103191000000	1836711191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
363	\\x64dff6cbbfe0caab47071dbc564d8b5e2668463aa4b0d57a2394e5c49b2de4c56a719fff85784015760523a40a97e147ac184d2db9a7db98725960ef6f5a789d	1	0	\\x000000010000000000800003cbcd2ffbb4de6030bf36e305670355710d7a786e38125bc40b6c4a0bbf004a09f6aa66a556bff913cc8191fe08362697720139ad6e7a6cdb1d8b913218d4459068fa39305b399149ec38d9d479ae3d200a52020420b221fc8b936a582b2f31d36f06dd3726c15f4b491d7642bfc80b0313ab410fca63ecc863f94d5ca2c8ebb3010001	\\x0b93c72c44a82cdaec5ea083c0f9e2d39175bd384ac65b4d38b38bdf29ec87173466ea853a727600f1bc256ee1f00d8eebdd808b32e6bf326ee4acf7ee246e0a	1651828391000000	1652433191000000	1715505191000000	1810113191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
364	\\x65a730ca94f20efab25d1126c226a54f6d20c94b5535228219d4b3dc52987486af1610c34c8d6cbee4d7ffec8204949b62e0c23677f87cb465f9d8e976987baf	1	0	\\x000000010000000000800003d3e076198f83078723415941652decdb5d6b75a8acb00f708acb35b6b6c5938a1d49c50f3a42c95eeeecb6899078ef5c45fe0f6ca13aeb34adeecc6e65ec64c618de411bd3268bc3eb7f0fc5cfd11553a16be0e40e6eb3183649399c4f79b8e4acb11d87d5adc318fea9281a92bce9b5948bdb318e227d6ba9d79cd0072ad6c7010001	\\x7dff60af2e55a6edd33fb59c74cb7026f3b5808c5a41e124aa2684ef1082c8c7da953db2f2cdc7c02a5af0e5b7fb008c7b8f4918c8833c49b61b757b76362101	1665731891000000	1666336691000000	1729408691000000	1824016691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
365	\\x665317d519a8b9e45a07a20d006590525b1911fda17d3882fa260f574ea89dc7532b57689114467f88df3ea63e577c9b6e3435fa35b7f54418165b481a793854	1	0	\\x000000010000000000800003ac7b6a3016028c5df7f5682350bb078bb61b22231569c13c201bba5549cba40dc0de851a620c7d5aadac01c1bdb08a575dd73610a534232149511d436228471985b38b828df0cf3341faec3732b8611a33f943f810eaedc12745b28947f247b57ecccf2fc2501d1c55e0d9387d1fbc970a6dfb367bf1b0964a19c4e8e7b15633010001	\\x5b9ff3e5eb5470317c06b234a3ce8cf108991f629a26dc842f5bebfe016ca183965e4cd8f8914998e8b3bd349e30030a2429d7303ee03f84a91ac5422930680e	1674194891000000	1674799691000000	1737871691000000	1832479691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
366	\\x6a9f1a66cbc29a5f61de2adb8717b9d4315c01f596971b62512c390418df6dc1d46730c204c606afa4cc5f5db4f005d5cd4cf110ce479e7d35a588eeea06a1d4	1	0	\\x000000010000000000800003be9d6777279f7fb8d6679e99d04a9a0af9ed863e079eb5737e6108b5c52a372793b3e80910cc981ac773cbbbcb2b12cdd8b33349fc631c6a5274c77f7f976744c345e0a1ae0d00b86f55d480077369ceb52acba92c55c368443c42d6674c66e7cca6d1d04883f5b7544c1f03028664ee65e4369baced211dbca44ec2ae7d97dd010001	\\x3da5bc13556666a507345d3245b7924ab196e241e0ff27704bfd9f1c9dc734c1d8ebba4a7008fc7264d8ee1c4dc8fb6a677355cbe80cfb5da3e2bc20801db906	1674799391000000	1675404191000000	1738476191000000	1833084191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
367	\\x6c53ae4b4349eb28396f8982ea270656ded47ffc013a503cf9265e80a989f41a619b0717004a5b54d1cd73f3d2e60a2327ba8cf65449b64d661cfa5d3b02b16f	1	0	\\x000000010000000000800003f31562f2a5d3e1378ba037a1aaa77b5336bf9121d5cd95c5523150cfc821e1613d15e39dd95aa66cdb3b39853607f62a355740ea7857138987a77709952bfed19c80726c217a4ff472c1f8eff3289dce98977418bdd42c3f52a4763d757c1b294193f6610a835f9c369142b66afd42fae090da3d4fb624895bea711df827a157010001	\\xb0da41b0bb2b68cf5c875d665df443a89cbd944a75abb9d0c0da49e23e787a5a38a8af24519447c28ad897f0aa29420df05f90caef1ea60a7edb22fd4e9aaf03	1677217391000000	1677822191000000	1740894191000000	1835502191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
368	\\x6ddf052b030727641c04a38cd5bb56140402d9bdb40a87490593b4fcccb5a4dce1d580b0204d7bdc2c7e550cd5e34c99e5794ff45d3abdecb39a2caaee45bca5	1	0	\\x000000010000000000800003afcf6dd27e86c64a5ba51f79f5c73874d039edacb8c642d321c74565ebd6b85afa19b8a0370a9b481e073d0615fd9aa520b6f07887254122bb04a53b157da51bc2c0c1880bdeace50474cc2ef92d6978e9aa79d789e0d6a6a628589e475e9191f9fcda7374dcc076dd4447060ea06b482163e1482c3bb64e5e2303567e4fc1f9010001	\\x0e153d1babdc32d6c7d176bd50e2f87999aa2a3887642214e714b99df511c36279432b59b543e8ea81f747f8c8416b48aa1d9206a6ec00e0ac5b95339f4bc60f	1651223891000000	1651828691000000	1714900691000000	1809508691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
369	\\x70d33b22d00b30d352e4724bf9354c3546a2af5bbfd3c449b4de407ed3ee650aa04ea869ba060fa92a0b0af5c48cbc6681cee33253d341fe14c7515d172e8ad0	1	0	\\x000000010000000000800003b39747d97a4c859a38b33dffdc086f7cd165751d2af7874bdf82b28bcf220ce5fb06c05d919f389e652c9659689257b5eafc9822e803c6588872b662bf6e5c8c8a907129aa4e4ae9184764a25079a75aa640644db575d3e83631fd13a63146eaee91e632c17b52369982ca5893cb00e99bbc8968396077769e347e6abe13f903010001	\\x48049d307c9a1e36e5e09b0e217f62276ac3b0c09080920b93e25e277245cbfddb90f1e2e05254797a8f27c75c0826f9ffbb5f7ad996aa742286d1b6fe22de04	1670567891000000	1671172691000000	1734244691000000	1828852691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
370	\\x72eb14702b2929a8bfb47b3eee31164da44134ad413251e20e3e9171670a0ca1c78db013549c1fd55fa7a3887e32f6d4ef1c681a23f787a6157b853974534d4e	1	0	\\x0000000100000000008000039de9acd65f2528d2fc1bc089bd187396d2fdc242a883c544f565538ffa059e881950ad9df4c2b6dbd13449e3d3aafc4af1b0587c840e7a02e0a211919c8386779301df78d0a96abd8a9c2621a19b3da8b136d614471ec219d9156b65ed34a4ed7e2102cd2870c575d8fba5ea3088a7a7e122fe2b658c299af6f5502782556fd1010001	\\xba18ba1d4712ba69de33579f2a4d08bb0908ab0544d4834810f9b525aea2b397cdb41fa6c81bcfd344c72e0f06af5cffb07cbb2b43df47c4781a23e1742a590e	1657268891000000	1657873691000000	1720945691000000	1815553691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
371	\\x738f50e7e7cd235783ca4d0be4eac487224c0e9abe9f52892c1bb1e1b10f44fe5e05b8585d4e3ec096668e82f3492947a92ac9cb2679abc49e67b5ec3f531d76	1	0	\\x000000010000000000800003ae18a347852e093404b367b8dc7417139006677f8c94a0e032c84d40c93c7e71b95ce71d82a9673f9ab287eca4b28582e15eee17899c8e33bda254af2fb2016d892ed65d7740282e234536de19b550063134b8c27e6300f5306c6233f6f437227218431a0da48fa6c1633a21c62c6600203d3380ab3c36bede2478a865bc1e5d010001	\\xb27ad39c7568d023ad1cfc78e39118d88ff6870d56682c16fcf8fbe35a13dcefef0632c555da926c235069acda4f8790a387c872a8e512c3ac8926205c231f0b	1673590391000000	1674195191000000	1737267191000000	1831875191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
372	\\x745bd9f95741634e381657620da81fc7dd0f5843bbcc4f0e96131dc675374d69ac17e014dc506d2ea5fc7382d2e0d9e8ff805f05b31aedff6584bfd5af1bac59	1	0	\\x000000010000000000800003e1a61eb46f4c11b75807a4d04c2f14b3ddafc4b8d11ccaeee0609894bc866d2ae8f660c3acbf4bcbc9ed49bece752045deee32c5995eb14012453ee966a2a505cee7cfc5f34dabb8820eb0adf9a2c08cb9e67075fa85e9fad01fa308a51e774e5e3139332e5eabe650dcb70f5218df29e0e507c04507a436e14521060ed821dd010001	\\x09233cfdfd3fab89af3f6545155629bd25e3b52c2f52b2028e17e6b28fa1e2b43a3bfed9fc0c77b8205fe0036893b7572335c00aae74fbacb8e1ef14bd21d30e	1665731891000000	1666336691000000	1729408691000000	1824016691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
373	\\x76537855864927ecf599f541528ef7d77dfb8c91314b89f639c1be3c0e26067b09c86aabaac90ec0998dfe0f25f8a5954e40be115f2298397ae6c931cc1512a0	1	0	\\x0000000100000000008000039831051f8466d2dd925e7799141ae5de2eed788445a3ea14d60ebf360117489d5b28f403f3d87f44ad90bb822126ccdd743a3b9cac1f3ba3ab472e6bf6fd0378a5e9ab356859db3ba0a73a0a1196fdab65c7532b188096b3cba96d2fab101824e57971acb41ddb5ac1c74a74f83310d25c57321f75f9e0d4c9d29de4c48fbbf1010001	\\xf29679a9574deb0c3fd701d4dcf772c66d58941346972e5a8d180c6c446597a21ade36c16baf192ce986e5bc59018690448d207d49c68bd209ca3b435822390d	1659686891000000	1660291691000000	1723363691000000	1817971691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
374	\\x767fbff214d7a59e9fe8c3f0079212b0ee54ce3f2d62606681d79c4717ef88fc6aabc2099508ada03ec145a1fc77725d24ea0683a48214ad70c7cf9c5a50688a	1	0	\\x000000010000000000800003b56f23a1cdf014695addd0b800e7020e647b2cebb9bdb41ade091d2c5ef8f78c8fa3c997c6db416ff7c3f5fee46846a41d9388072953b88577ed5150f6446795ee3ec4caed538d1302097cd5ba08e21b45cc006687e89064d2d7546d043a12d14e8d4d502dd2208b79b860650933d2e5c32edac1a16f5c4f2c3c9f1029e6d15f010001	\\xd392c02215c9929c5952fbceb3b12a0a6bb6698423283d9940dab5ebf5baceeaa1daacf3a65272a1f5844036f1711f023d685bb507200c7d8478fdd7636af10d	1661500391000000	1662105191000000	1725177191000000	1819785191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
375	\\x7cc72019b75bd6c60d8257beccb32ee77babf93617e6c699f8759942e20913588fab08b175cd6b62b2176cbd512dfd997a0beaece1c14fe3f460f8f5077e6f9e	1	0	\\x000000010000000000800003b53dd5f723e95309c26124a99b964c0f1142d2d94aecd907c37df3f77170f641c7f992398feb27cbef14afb6c0431bdd23a0437b3f3f477fc3cd09ce14b8f9fc4f4ce010f69d6ddc7a3c3003f448c12214d09544a14a44399a7e40fd6d8a5ee576db4677a50fa016129e0928d3f9884bb512d4e960e334681cadcf795ea93889010001	\\xdcedc5d9af9a148a8db1c2b7c354ffe6cbb56f42967c323bc8a6d2ea7d00def39dedcaf6e5f4c179a45d1d2dd93d6202829807a8a11580b8a536a592ddb07b0e	1674799391000000	1675404191000000	1738476191000000	1833084191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
376	\\x7cd7bac0de096a6f64b844886a3c6b5ebd761059ba01e38ec87bde3398d58b6f19fc2a91fab160ebb3d73598c51b0a16f4c21cc72b642b6a2866ee402c480894	1	0	\\x000000010000000000800003c0524f8c9dea463a650be2127f55104e4f1df3aecedb9f93ff32ec3e3213c4aac27a59e47a7fb41d490a533a927e75ae15b3f49a89a3676ea53db498824e5a3be5e2ab5cf09f9c7162e9b401543bf27ee7eb196622f1b5ef78801cb31a2f9e70acdf40adf5ea173f1ce2a36dbebb771c8cec78f98749fabac96b102035309f17010001	\\x99507c163e43396992166cd23d4caed8f956849a065105e2725acc786cf37e5183a2404ac7831ed55e5716e4416cc48b6b18be5a754f03a62e0436501cbb3b0e	1655455391000000	1656060191000000	1719132191000000	1813740191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
377	\\x7eab0e52cc371421065a247d66ce0a3b835bf571a125c25f859b19a593db3b62640130d5f3ebfb29de7e2260846070caa7491f9601fb31c19ef292551be7e0c5	1	0	\\x000000010000000000800003bca31bde08566d0a007414146085f99bc58dfb2cc832613a4ca466564794f25f95e14efd62b3b39d13de965b470a155f4c96fc962a404c51c1645ed5cd4cd83e317455a9ccb2d2f693681b6995d949c445b877bf6a40fde25b9cf495893035af715eb3b56b9518a61509b852f77d6086058b32dc7f1a92bd931764495ed4a879010001	\\x81123c04d896c02c2ce5ced2c0411a36e5446612db2fe5894aca2a706f330177047344801fdd81e919d0726c79670316e82daaffa356fe338337a187be9d5b04	1661500391000000	1662105191000000	1725177191000000	1819785191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
378	\\x7e8be0c85d92d06dff3151b4f059a3804d02c1fd0aa53298a59465cbc602ee1361485afd1ad6deef10408ad3c45217a39984d41023c9bac2381d9789aae06b3f	1	0	\\x000000010000000000800003b11f63a5a41106a2d9d3dcaa0eb4b97946d39eaab9fbc3f9f2924cf320f30f1485212efcb5e49e7f07ba17e4c1f4c4401ea24be0fd5f7c5141d72015a413a119e06ff092eb85fb1fe3728aabc7fb3408c224fe66df0e8710582d1db5bdce25af186f279fabab6ec530877bf546ea708997204efa8e178caa7c957dcbee728275010001	\\x2d316e5bb6a8ef19accb32169b104baf87ac62846f61ad8ab1412be0fe3d2c09a9cf77f5617699788ced33eafc29cf5569c6ffc6503e1727d5424ebaaba0b308	1675403891000000	1676008691000000	1739080691000000	1833688691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
379	\\x8177bcee0dd8a5319542231ef10d4cb92571e2914a4d571ce4557f6084aa5b47e3d447ac54867dbcfde312f01fb24e7dfc88182e94b9dea6f01f55b897a4003b	1	0	\\x000000010000000000800003c4d580b60b5bfe83ddd08bcf97de560d40886f4ef9de4d7e9ac47e2221cfd27c81718e511d475dca07687afb7357ee82120f11d08f6c73a5b5770b7f75163ad9d8db1e054ee990a111ba68e65076979d355ba52306b8d49835eea1163225ec40ce8a2fa54a6e7375a03e25248a1fe35320d33b054d8ef1fbd835b0722521d34d010001	\\x26b7fb03a20751d3c43fa191f59456bb905b7e7e4d29b37f514d84634f1a1f66d7d3831565b2f1f717606a1bb262ccffcf92d1071cbffb9291023c05decf810a	1673590391000000	1674195191000000	1737267191000000	1831875191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
380	\\x836b91e979d5136c5887fbfef06c176abe53ecc7c21fa8a070184fcbde676cade157e7cead81c74263153dfe5d69a3c6ee55c403cef2d642838aa761a792526d	1	0	\\x000000010000000000800003a58ae97c2e35eebd72cc6639f318816577ab6a2d3a99930c0c874a03f8b77fa8dea8bed90118463f5598d2d7c72d630b3e2ca246f7a9a871752ddc2f344ad4f3a64a46c5f142a68fbd23e410af236b0c9ade54d9037342730bb4c69abc13e272439bc345b9bf42e525c019bc1117b9a171f0feb7ed56ead4e9afc51234da0327010001	\\x9ef528c383da2edc7f8cf294a7c5b7370f43a9df3df3589aaa5f1ab248f1a63392031c43f77d4fa19d66817025ae907ea6608d1d96576e9ea9622876fdac3f00	1673590391000000	1674195191000000	1737267191000000	1831875191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
381	\\x84230d8fb6eac3929e0475c8eaa8d6763ea4a7e59152c5e9825f5e857d5af250494f0fb634c91bd107faaab8323564af95d19acba66ed9417c843a4084ebae87	1	0	\\x000000010000000000800003d80308eb40953ab4a34e63fb1e9b5bd61f3acf557e2815b4d287f84f2c2f85c9ac2a2cac77eef91a0b2275d9cf942d3ea0b3fe01b97accea37a6482457161112720a8038a27262b772894eb05550f170712b2e44850dd51c1ffc4941c760f725927eb3199457ab1d0acd41904c4755d6786abc31a7a04d421e410e4e46bfc9cf010001	\\x5918836a74360a3346ff6a5df5c9861ba90bbdc72065e208e37f3d30f231c87537095b451ba9f6042da57cfa3a4d8b5dcbec3bf9a2e33838b36dd0bd47180109	1654850891000000	1655455691000000	1718527691000000	1813135691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
382	\\x85bbfc0c18ae3a901993ed402f6e020335e743e5f95e05c5276be384c80b9cc551e77c52746451f8610f949bc7eb8b47942d85eec7acdb7abd2f1aee0dd8a7dc	1	0	\\x000000010000000000800003be654a492c3fe2844c2a4e9f4fcc0f066eae6a6d97f7083099245b4403f1544ba186d15f9f2d827b86dfb618fc073f76d2e4dbeb8b40e8b18c64b552390e300a93a74f37fc2970151fd387f6e8dd7325f7c28d6031edcf4c6e8c281edd9947acc5147bbe95c64b6ebc925be83230712d71ccf9f1f56c4052a7ecb06243a922c7010001	\\xa2a6441bfad6f125974cad4bd060fd10fa3c3f9c3d671e87c6b405e5f5bab8650298896e806f0fa5fdc80fa8b14fb076f352eb1dd105cb6132330487fb0ae703	1676008391000000	1676613191000000	1739685191000000	1834293191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
383	\\x85ff0796f869f324cc8c896b1bf0784150af1a04ea1b5bc2fbbed6a85f80791b94fb538f1897b8560c2b675991c5554920118502665f6177e2653681ca2d7d6a	1	0	\\x000000010000000000800003d50664603f8148f80eb38c82ceee2b84cee30fa552c58b28863b97e5303c4247cc84ca0049a73336906626eb0d08d476e6440c1d6443ed11fd62d8f71a670dcc6d632122919410638ca56532c54d1e1f5f5fe06ee6c1689edbf493e225c3f2bf2126829f28d4757957fb7afd9c233f3f82ec8ce1c8b4054042a9d6717f8c2c81010001	\\x26fbc38d1d4239c61625a9271ecc6305b74c1ed49b4eb966388a6ad32128841641409cf9031fe55f43beaea42711bfb2743750d10debbce2ef491d762300260c	1668754391000000	1669359191000000	1732431191000000	1827039191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
384	\\x8e6bba57db9ab5f61370096e23d239494ded48e26cf8aee303dfc8ace5c39fd567905a1732819f261550acc28e9147ad546e9417330408ca36adbc5f24f12fbf	1	0	\\x000000010000000000800003a009735fa5463132b2467e42b1e9bf232528e41afc648086f4ef3a23d1f78b9c039be84b4188ae4c326232ec014bc18f34fac04982e2272762ed2e60fcf1dbc03652b21a63620a1e7471d9a7e34886b82f9f49b4c1d40f5e2c125cfb8779c83ff90ddccf4303ed0a295c35210c6eeac5de12b815b5b40c6e282893bc9e1867ad010001	\\xca194e608d0a5b1bd07ec003703472ce7173b396e55819e01527a6f0b4b95d5c66c3850ff2320120ef595c0a910b0647dca593a214082dc6265f16c5fc36760d	1651828391000000	1652433191000000	1715505191000000	1810113191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
385	\\x8f9f1369132a69b350a36b74476462c1d403f89ce3318008f0ca1a1d59eb22c9beda53c0d67cc5183ab4ce597731f8c661ed94cde3179ebb711fa442de12d27f	1	0	\\x000000010000000000800003bc9d37e1cbdbb138d3e8ac273dff5210effc10cc3296bef420646c66ca46634dcf01e8ea9cc08a76ad2e0a17034c5156d6502e915bc0659ddb060fef73262e0ee5ac8d8a534adbd5e33c1351ffc70268829072bdad40ddde51a5e4a897b0b340ade4145e13f510864d49eb37877e3e95892fe071bff68dda2016b352ad134f0f010001	\\x0fcedc227416d8b52f72cf4c65fc0eaf79feec99d7b45232cfab31472456ac8c50feea2972abf1821185224b857476fd9a168aaf679166a16b26ec7af115c701	1653641891000000	1654246691000000	1717318691000000	1811926691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
386	\\x90f32ad991841daaaf4c5590c217f3f4a5654eeeb0a221ef314017c5d9995d698c563b61a8cb20f1a9c164b9a4078e596186db971bb97ab09ddbefa2e2f577c9	1	0	\\x000000010000000000800003cb1b9f50438e360b2fd08de94c88f0d071e8e63fbc968f79547644129af28969377b9b92c8bcac4bbe6c2a8f6ddeb7aec640f2fcc02929309d2f3804d961ad2823f52be0b90a334feda3f94e66656d0c3b9318920000aacd5a4e7e39c110f4e7ba3f61254212ef9c7745bff3fb9fa9230582b184f4b50f11068cb3f92ee66e2f010001	\\xadffd3fb60c5c9a2e641bd8e9acdf790244334e73081d554ffb9d190c530bd0dca56606549d25095036832cb6e7c3a40caf86d9767faf38b030599059c5db80e	1656664391000000	1657269191000000	1720341191000000	1814949191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
387	\\x9103f8562b7a652eefbeb62b56bee278c4e0c496459a96e777b3012ed3d9ed222f9beba2157cf6c3096c5dd6844df5c18fe08d75e6289db279323c6127809c8e	1	0	\\x000000010000000000800003be178640b54f0b31ac1066131f206789f21138f08675e56130926cc2456a951600f483322808e0c0409969c035040ea0dc8fd5c9521494cb1e0c06578fb511fdd7baf00bd3c1067bbea44b8da2824dd9b1ab05e83f9479d452ca2d199658c4dc3784155d36d67bc9a66467c8cac99e683e4d61af6e5be351b62fc205cc1dc565010001	\\x3e585410f9ba6b77d25012452af272c094f354a35fc98627a376deb3a0f723f050799a2f41e11f3c9be64bae836fb42071f1f59f60717b6c2e0f7a5646d69b00	1657268891000000	1657873691000000	1720945691000000	1815553691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
388	\\x92cb9a38a9150cf0a085c0e2d82bc42378a80fc6832116d08da2b56d64af4c2deeaa9d0b7124b8a3cbceb3722aae3c6c1245798e751015c46b0902b52add2c2f	1	0	\\x000000010000000000800003b0ea07e0f11d43207b3142f7b23b356ca247b9a09b415af5f8508db990aca74404b4970a083a4b1a498e8c5ff4854dfab345f88eb190c12214bb297c316078503cf405e4b468b08e826028975912d5ba1e4861fc8ac9539ab0d3f01b61bb5bf0297a8b587aed4cf24abb610ae0c048630ae9f25e2d8b880575f05ced06a9e2d3010001	\\x0d9e538e3bc185cf8a204c690a5f1c757893be2909be5f4d34ddaf95c35b9889faa7bc40d67f60f188ed3fa935fb0e20ed2b6f8d377d27837238b6c085777c0a	1658477891000000	1659082691000000	1722154691000000	1816762691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
389	\\x96836ab5880c8de585bca349cb81e52204203af136677d8a4de98a47ff29091cf0f1aed643b3b9460f6bee0830338626fcc727db940ca9c690dad733402a470d	1	0	\\x000000010000000000800003c39156fd2dd390671bf57ff92cdb15d0071f697430c3fe98f398adc3724d906187a167508b30784865f9b8028abaaa61934b78bb34a2748ca0cba42f5f1399deb22a99b50c2746906e3918333060bebfdf382292eb3e78d847d5a985e349c99c6ac57cf6884d1d487c5dd11de54554963b3b46b98aa7b3efb7e26f5df0e053b9010001	\\xc13d0589a93d42e5dfc8fa77b48ae5674dbcfd666e898128a70320c64e0c7b02c60f7f00d789841752a00492637d4782d2f692221d93e418f6a4ce03e762d60b	1653037391000000	1653642191000000	1716714191000000	1811322191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
390	\\x9adb326758e62f68553a8cbf2055d55e0d822384791d532fcdffbe16d9b38fccd10bd5bdadf1151b76c7238d7e530fdeb81394227469b07b999b7b8ed493b7e6	1	0	\\x000000010000000000800003daba60dc4fa766ccdc9b0860e70fd22380bb8d8e2367b422219cac3808eef8de89a6e4e9c25fd73ce8d177ce235eb246972f406e3bc4f5b6cf676578a30073c3e8a8e8d5fc2021ce3a90f2c7502cdd721e4d5106bf9ae8f027637f0955c40fb01739458e3383692dd2a77e002816a5a9c6d84115b5726e7bfbb242347682d5f3010001	\\xd17f2ccdfa9951a69f2c8ccf7358278781697178e5243db27cf68b89c63272df60773c54fa32fb6e2347de0d21756bb6a687eb1d3ae27c21fe2b29135fabd40f	1666940891000000	1667545691000000	1730617691000000	1825225691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
391	\\x9d4f6bf3ac6d955e961d589a788d75e9037d24848729134f6a57cd474811e372d08eb2d0747203f9f82522c2a8815b4f61a0673ee427047ab50a357d2933c9d9	1	0	\\x000000010000000000800003beae384c38d95512196a15d0ee1f33a958c90758159c55d55405f65193bc326b9c063be3297da6cb66a250b8b624986b2cba9d4cbff6f2d735873d2ec04ecdf29b41a0556354ec12ba9e8b53b8aec48cf9fb2faa518ec11a958ec87ceadd64df60f7a3d0741907e6b2594bfc21418f74e7463bb8c3f70a3431a56efe88bf4e27010001	\\xadb051c7ab876e05280d882d70f453cf44a068ab0350834842201861839f9d910beaf6725e778d4b2d750538a66ac296d8fa91098049936c9efd2dc1bd6a0407	1663313891000000	1663918691000000	1726990691000000	1821598691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
392	\\xa1677a0368a673122d4da76b07cf0053c7f08b8925281711f01faf372acdf9ae7d5a90e3846886cf112519f19d9de6465f0e72212809a8a1abb98d5ff4e44e1b	1	0	\\x000000010000000000800003e27335a4d555591632be4c97bb5dbdcd27104b19d54d44ad80d19510bd83e64143c79601b8501d22dcf903c2ccb74ce17be0c2034605012c44d9634d135c0be465f84c9f3fee1a58601d1dddb27368516310f7e8b80862ca298f6d655fc3b7b0c985607c54a06c06bda5c6b9ade2a338afb762a19eb3ca3e8b466a18de4a2d4f010001	\\x05a4a5eff7090f320d99eb3af1372f09e4595cc6a320067a429fa9fc4ef70c4d6a252a79e39f41b1ee59b824e0a870ce87936d92098c711249c31063b255bb09	1666940891000000	1667545691000000	1730617691000000	1825225691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
393	\\xa5570434e8c40c12e243a0ef523fa958aebc859866acc38db776252405534ae85e95c8aa734042942881bbc4249210d4260c2b4a77bdfdfefacda08f8f59223e	1	0	\\x000000010000000000800003bb74317f81d9aec33320d611308c773e34a683fa9353c6c32861e61c9beb9beff96d4c8e2c7e4c36b8221ff35655604a71514dc1158eab91c7422b4cc5c6b6ae3b400aff41133f1a3b412a6f875a80f0048f4be868808f59f17ffdbf239afe1e90154ab592c11fa6c6cdcd9192b37f9ccb234b04296971bd383215cf2ce34431010001	\\x3b4ba3a861cf158221b2a33358d6a0a2ecf84c00200917ce2da06b9f630e13884bdc390d6b500f711784d267ebcb3de99e82da4d3543f69980f40553ef5c2c08	1671776891000000	1672381691000000	1735453691000000	1830061691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
394	\\xae6f726e7f2fc387781a01e8c8877e888569d5380027cfad63247a1cae3a65f554863dbc5a7935d15c163ddd776475bbbf22f66b53dfb5e0fce9057ee0d0223c	1	0	\\x000000010000000000800003ab62d951d1fbf839aa966e74f2a9f8150046e8e56bd3fec38215be7da461606d3bd297dfc7305346ace5e835acfe1c5aa9425061c65bbbbd0a844c4e320d36059eee483b8b4e706a594659fc3d6c02b6a74ebfb8ea240416bb6025080d21ba26a2b78b2b4e4f08afb8a58e10fe305fbfd38ec1f8370a03d33738fba787698457010001	\\xe6dceb8b91cb8041d0fc777880dae1d9328ee1ccb7507b41d96880229a6650aebf4b562a36bccc93be26756ad1b7611e96596d820061ef5e341c458bb6c86c08	1657268891000000	1657873691000000	1720945691000000	1815553691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
395	\\xb0cfd328cb84853a1da30f49822ed5da746bc52c9c941a46d4d2b6f19252d85f0bae5a7c0f5f157234c1717c540027c98c64af6b639218166e3b08658b610ec6	1	0	\\x000000010000000000800003c70de47dc779b5f157f9c33c6275bb31a380b9e1efe22de4d1f9a1b68a10632b37e436ba9a8c83b135f545537d587db6e7c361d612ab5ca3751746c053213bdee6d29d555660bbb1537f0cce7c12862d40685a1d6351afdd5c693509f08623bdafd39e53c895ee7987a1d9fb7ce02fe3479d693890f64c0c5d5a27e6f68ac04b010001	\\x680d5055cc8d27abcb59370cdd374ee3930a9b233b0c3ae5fd3b6ad342843a81c6bb734a7b9df43147205537503ac22e4fefe06ce1d47b2a9062154a786a0c09	1654850891000000	1655455691000000	1718527691000000	1813135691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
396	\\xba6bec560bbca45032c2c7ed261902c138377b20061252f72e182c75f2a0298e6455fb85181d96176a9ea569e4a93b11254a1e75bb13f63aa3883ed65b6a23bc	1	0	\\x000000010000000000800003a67e88b403ea9aabb00681e3c69bbf997a2939845e19bba9d9943c555f4527bf1ac9c90927b9c23ca422b1e84e1c833d522345b0a183adad2c79d5269d58dedb502ca535d8a69d89b75f123b20ce9ed46aef4a5ec3fb6b5bc247b24e49cde4fdff36b68a61c7682c022a3e38e21599ef14a31bc4ff04a33b6a3c3642ded75b33010001	\\x35b1905e2814af7dc8970e9e27bf82217c67ac7845b715ae6bd20b7f7a590c4912ca4c21a960f1bd37844c7dc847a6edb645aabadb7b9b233c6be98438030e03	1665127391000000	1665732191000000	1728804191000000	1823412191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
397	\\xbdf72d5a88e110a0be67b1fa010e2ff7ad50fa7f7343740609256dcedb779c31245ee7829e6be92186eeba452b524a60b27d1325ae6818050505ee9c84b39bae	1	0	\\x000000010000000000800003cb79283500788f9f9da3b079187461e9227cdfe3b6f1b6bac8aa4729caebf78bf03f81cac574133ffe9bf4293cc99b81ccb499f22e227bcf9441ee892ece11819b4686ccd0fdd23c3c5e892243df1776b7360b30f847d14498c78b770bdb968206be6d334f962651004301693c35cf823d362dec7e86cad6678b7b9e9bf74db1010001	\\x4a3ba366e33645a560a4d3b71778908319d42057cf5228a0cda6523676827441f407dbc74f38be63f42fe8e26b34630a08cf0e9b36e50ef1f15806d3b694630f	1679635391000000	1680240191000000	1743312191000000	1837920191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
398	\\xbfaf8d055b2e1bddcdd512391e494f1f087b231e29742e1fcb9598b3122fdeaa1767464ef517d3733d7f987ca13928e4e676c324dd107ef51edad361b6611c17	1	0	\\x000000010000000000800003fc56b9f64b802a4782686c5e07a0422cd6a8d26d635fefd3a2d45b1a7fb340cdd88ac6705d7e992a7f4dd61d6456e7bd8701ec926ce175b785ba761f731a1ce49ba25f7d8af604b2ca748b9050a73081d62b51f8f609348dbc2dfc71318aeff14e7542319d343a43d9fe53b959f14723630d288d9ced550e7126fccca24ae2d5010001	\\xf48d63a4524db71f830d62a509fdf4c695fd872dd7c91f550b656589476201b83c413f8f2ea88545b1bf1ee13a2f8a46eb40d632ac8d9cc33f14405e26493a0a	1680844391000000	1681449191000000	1744521191000000	1839129191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
399	\\xc473ba9b67fea6b2db4056f76a609ad394e828fcf9155d0b567a111299ed54138f8e3477ddd1a82a89c717be3ccbd77146a06d4911314fd9e4e5d8b18b6e3435	1	0	\\x000000010000000000800003ac94fc38113e681fc8f460372525196e98013b59ef363cf9ef7e415eb6fa5f85f13646769408dacd470531780c9cbbe099b6c4ae05995f94a11ddbb2674cd84bba572eb046f5d5303d051c13cd6ac1cde92f413cc92184c6ca2362e7e15b358614b5ba7ff3c36aa1c96ccc2daf6adcfb056aca521281e782f1749b2e6fd2001b010001	\\x187ee1b2f3adf4348e986dfb2e267a99bd0eb6314b2efc06c4d07dbdf46685400bc670fdc2f7f8d3f96624baee6a67de49b1156ec7cbe48db82b109c2716d609	1665127391000000	1665732191000000	1728804191000000	1823412191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
400	\\xc9436320ecf38b62bbf6817b1a2efff69f3695188f71ddc579c019a7162c79731b9ddc8a362a4008ac59bad590cfb8a5720ccc54be545ee2017746a4df858e69	1	0	\\x000000010000000000800003f99feeea1ee6b52d142bd46cb7c6b9ab0836d77024e7543d25aba76931940a0e852b5ef18b3160e36da1be8fa80bf4bbb61606652e27649f060a38ae74ba00325a8162f384e4ca72c4d27df3455670a8e91901b1fec563c84cffe86dd3557bf32c5eeae61ef5e80e366b40cd703cbeca9b37de3571cb4a2bcf87384146c187c3010001	\\xa88a2acf60ded16371008e3f39b4e49c22cd9edae640b00670038e1715ab442d5f1a0fdf8a66bd0dd9793317aa048923e4684910c5ae0c55eba43cb009083809	1651828391000000	1652433191000000	1715505191000000	1810113191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
401	\\xca2f1efaa6328f2dd5473697ac00a61f44001a44ebb148d059594978d775ac20a2f7acfe292c3da8e84cd7053e410a7507948dac7be369432ef74f17f04b5413	1	0	\\x000000010000000000800003b63b771f1cf4f7f7844f64963182100908ab1cc5feb2de1efe0502f59c618ac81020f9a2a6818ce6cb343dab9c2b8f4852ef95da030b7c29206f841b2f08b7f84c7ab74acc4635c7ab1448530caf5c628f0da37db5dd7aaec49e9787d22fd5a8c2d2fc4a00bad7664010d2d48e5127a6ef12fa1c40c08038e1e9b28966e8b3e3010001	\\x9d67090f7f4650ead857eab803641d40cc1397cabdbd95737a3570e74331b1dcc4c81da667e78fda243bb46235bfb19a4933ff8f061879622488881ca1a14109	1674194891000000	1674799691000000	1737871691000000	1832479691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
402	\\xcc2fdf60d7400e0b603c285de6e5d23d90a8dd619042324aa78800fa669e452dd1542a5088b02f279d2fda4a021e178b6eead50189a6ebb11dc8a40642738cb1	1	0	\\x000000010000000000800003bc44b504c81cb848c85e73278b4a3826da53618527e454f709579b09178e4ccbf84bd6668c724bf6ea4e4e0c8f9781305f476965e140d05ebdf576eee05fc0baccba27dee138762622f2a20244880d3621ad93c6eed31ef1bade475a507b34267cf040e86ee87b007d5644a5e0cdb80f9c2451f7063f7f99a94b014a0143458b010001	\\xc983723e553d17ec9eba46249f220941bf32b7d6651977a66e987e9ea630f5e203de240fd12824f5ecad4706f1839f3088dc204953115afdb54e210a797fae04	1667545391000000	1668150191000000	1731222191000000	1825830191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
403	\\xcd87a4c5ac4bb042dd7577cdc533005fabece7fb843e3adb9173dd105c1449926133a25e91fb104fb15284411e1f6f804383fc3eb9910a7a2daeeba915ceb624	1	0	\\x000000010000000000800003c03defee3333e87884fe301d76c8d0340dc6f5a0d3f6dd8dc12a5a39512aaee294ecedd794ff86ea0d20e9cbc6138d1a1fafc5b2dfd8abe35f22371323d0592934f70289d05283af42e02e2dd7f5dc777066c92b933b76fa27cc94d2993a755d95628ac2b16f826c36235b75f090cdf9cc8b7e7d0ed8c1468c9b71266710d149010001	\\xd3ca831792a301f28dcb6224eec0f11c3ea5b90175b34b0384a4ce6809e2e5b07e37d354ef984f116cee28f39a864a8b1fd2ccd0dbd97c8d1b09fe86e74f0b00	1679635391000000	1680240191000000	1743312191000000	1837920191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
404	\\xcd4351b65d49be1e8e472ebf9f09e2e50d1759687e2c6f1f649e89859f2a16db660be49184db482de8e2a5dd4abe6ab253114c7215f171ab6060a1f331ec1410	1	0	\\x000000010000000000800003a3328042f4bbe04f65a3bf6bab937b7a5a159a51e70e6a801f022c3d4eb1e97b9da4f5567c9d27e6b95824b4c86b6b937d46f689229009f081f4c899a838076fcc0b24a3ef434117e22b33fe416451fb4f7dee3d68ba043ada8ee908fa9c88ee6c317f6c2935a88ac95fe0ac809760b568d6029b118d1b73d6aad7ba0eb6a5f5010001	\\xf30669f43023e034b07916f121b0405cdb833a29da2e4690b1531eb9ed2ceb8260ab15fb14d1d2b4e94e35f69ee656bedaa6e44f1374287991b7ffaaeaa71509	1676612891000000	1677217691000000	1740289691000000	1834897691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
405	\\xce5b820ccb7256ccdef6d0e009dc35535ee5cfe219195bbb7188985a0f12767b07fa8bb0bc1f85e977aba5b3317486d6dca0cd1e825b36a993a50c08f8dbc061	1	0	\\x000000010000000000800003aeb86202d73d92bacde1ccbe81ea3a54dbfdad3e60ff530f687b667d0065747bfe889dc000d6af5e85d13f41d90786de0ebd0c0f11ec8d24bf30c2381813b75d63acb62d08a5559a9f019d3b8661d5d6a2946dc1ed5b13f91c1a56790955af846ad1b50e2ceac0d4f6dcabd976d73f0b61227f1e65327d9ab765b3c5b26abe2b010001	\\x958923479c5949ce645c730c9242dee4da86125670ab53daf1126e9e9f7144083b497f57c17de723654767fdd411db8a2076769a3f6261d3b42567193bb80c0b	1678426391000000	1679031191000000	1742103191000000	1836711191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
406	\\xcf57199c1473b9ed185287267b68e28b3cda4487bd15c9c1b11815a38ce58504f690d8725477614a5b7f58037388cfacb08ff255847347676cac8c3986f78b5d	1	0	\\x000000010000000000800003c69062107a18ce38b80e0d152e0af99c189c3ec5b546cc06b85b25d31a2fd958d3916fd6f0ab7ea38eca8a53bb3b8e10eb56bfb0c744af3938fee6a4b1c97b802d780071e1efb779fe1b12ddf5ee8efc04eb22783e1de753e6008f50d5fd16e885d930b1545ab80dfe0d05fae5f00ac3b5a74abccaedcca890cbe0c4fca0a3e3010001	\\x284c71c66a4343e5b2eae3818b240243cf63b27f7410ecf95d099d3d39818536ae1c0edf87c42b3e47b3ac001021b4d97814e1b4abd3b2513ff72dd1290c270b	1651828391000000	1652433191000000	1715505191000000	1810113191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
407	\\xcf03059b5291c7bdf42f1e623794cd235fb52b4ef44c1f2557ddcbebaa7be246008522e24763ef215cc0d36bbecb5490a10bb7b8904fa0cb3d99e5cb811fce32	1	0	\\x000000010000000000800003e4e5b5a93ed75e9bd4d0fdc04e2bb732333d25885ccf857eebefd4a34db0e5e584a1f16933133236cd24f9479501bee6ed0ae0f0fc2a4119999b1699f02d207c6b141349309ea907d23ef32067362085205cc35e39e0a1e9d65f918278259d2a82835750f71025cd79814f9291cd6b6164a799c571d2e6966d8d3172b82d021f010001	\\x9c6b9db2070aa7aa4d621a58fc2583b8a32ebd6d38bb62e960696442bdd067e32e8a591d871c287a5c7a095d1010a477853c750c74ea2a551e0fd5b3702fe00b	1662709391000000	1663314191000000	1726386191000000	1820994191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
408	\\xd373e4c33a0d56319f0677678ca2fda53f7a6443995de3df68f0bb07dd68a338a718f45b53d8890cbdbdada4be4cf2cd4ba9d57064957228799c25e13608e4e3	1	0	\\x000000010000000000800003fc6213197af880c26c1eae1e00224b64e2432d247952f7e399cfdc5c6a1d218195f927ccf4e8302eca06778992c3a2c1edaeb623c40b02fcd088704d5f0b4c6c0f203a158efe4e8ac9bb74905d089a6765e1b4091a3b97c80bdf382147aa8da5ca951e18abac269cf1b4b0be60fc13bc1ab1aa4280c3692af538fc64506a24b5010001	\\x327023f4e578371b5aa25f3693ee506cefdb7744c4df7aebe3ac0c881d058076377b8829dfb19b2e59a1266dc49a8069814e34333a8f0bd98917f27062682402	1666940891000000	1667545691000000	1730617691000000	1825225691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
409	\\xdabfc7e0a89e478acfcf2e26f6c4720f376b29d33ada5bf7ceb548633a49de224800d15e35121709081172a9bd7ab3695d8f111b26497ca5b12b120cfa5bcad8	1	0	\\x000000010000000000800003ba859b8292779a33868191c5f3d31f74837898c6c7c11f459cd247c77f8f13d7ac608f63f1ca7132a7075a89a32b7e0b593cc8d16fea86b29aa99bde352d909ed1e8dd8f1a13bb03fa7a64bde73eff533204d03fb3ecb97b1576a346026310fa7d8340c2352ad69602d77e44318323160ed0d880260e281c281f702d9d7ec027010001	\\x31b791ce780ca45bdca7d921bcaf99255fecfcb03a4a4c99b112f0a5c29e4a6952a00e80d82b2745a54049b3f4a5d2579dad6485d04ade35f9b1855c07520a0f	1663313891000000	1663918691000000	1726990691000000	1821598691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
410	\\xdad7511e022625607a6d7322784cf7ed897aa78f4f2a20328c6a51595b1169bdaa784f146540c880a64f9c4b46b3d846d281d823504c175a2e982fa163cac274	1	0	\\x000000010000000000800003c81edea490cb7b1a41b605edb451b0f16ad7178fea4a8b7655b3b7bdc5d9b88d3f21ba44e76f0b4c860c71150393884272ec28f390b0a5e98eefa1314400d97a766e05b06adc20d8adc457228d14f8583674295f0df79ddd62633a5260aa99a9790f87fa2ab4b763e4906a71b9340b72466580586412639af11e93d283ad7539010001	\\xdb78ba65c81492e92e8a71ef0c6925188d85c48be1c3bbbc463145429d445fc33c0e0f536aa6413d954692eb0b93bd3a1c3d492ac5b169c2d7f53423efe20504	1654850891000000	1655455691000000	1718527691000000	1813135691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
411	\\xdc9fc7dd7fa4522a0a990b30c7e40d7048d41e49a137a2675393d5f69b9315ea876e0b6074d2aab90ca9195a2b730e86f2160119791467024b28b33e30227564	1	0	\\x000000010000000000800003ef9ca3e47883f00e437b61b68ca4b954855f19893f0afc8a430863e5e30da262a8f164668c127fe4cfb24f5fdf7ba922ca2ba9b466e39d5a480dceecaeb0ee907a8390a8c20317971189b8e1b822b8c92161edf5fecd7dd2e624d8da0c10d5a7a463a4d40ec6b4632b30127b1e737b12670f0fb620a3683f515b8f4dbc875b8b010001	\\x56e6567bb06e34101841d19ed578d57fa7670fc1491c70a695449e6030c2455803b5ea4fb3cf9921d31e5fb9f4b6b17ebf4516a143acbd6ffe7c596c087b2c00	1650619391000000	1651224191000000	1714296191000000	1808904191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
412	\\xdf8fc56f8ba2f0f729aca816197710bfc2eadf07a8308fcb34d29977a0f0fbac1a682dfcf6515a3458886b96d74a2936a55d97f689f6d66f329cc2256a72a5e6	1	0	\\x000000010000000000800003e56fa2c3210fe24cf7a6564d6312d9a12ba314b287121528690fe8324da908056d9e081a6d177931311235fdf2bb019d027e71c88b3e44fd2be64d5260de8edf5f2f2437dd4cf5a6f3c44fe10ec97727653473202e9420f7400979457bf47a80d6d215a51fe9e195066cef088899abca5abf49cc44834add6564c93e4d9e534f010001	\\x64452c56af825dcfe15addb18df8c78c781c5ee52e8c7444751212f33df91163d4dc6fdc0c32dfe0993065cb417cea2d858c7adc245762b02217d74581a09904	1652432891000000	1653037691000000	1716109691000000	1810717691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
413	\\xe1a3837dc0b0612f1fe1b7ee59c1237498ebed432d4a544984c0c0068e59e8094e08f06eec8ad313e4eb82faae677094535520ecaeb8ac80e86e33725cc7bd6d	1	0	\\x000000010000000000800003dd19fb09199d8c7289c500802c49e56784fe4a49949cfd9a9ecff2d60c3cce0115d09f11ebcc8b3c031b7aa54e46eb469edf6f50f658a644d447065030d1fb8281ccad6d5872eb09fed64f1bcd2c2eeef96114656fdfa2bac054279547dd388ffc63cfd67fd168d977bca7ee8a4b49d27ee032aef805a5b00b430d022a9737ad010001	\\x6ef62125615fd6f35e9b688f0f684e24db17224b6586f54a0c3bd22ca674f7ca16c52e48df3adf2d587d621cd93b8a2ccdd933744d6f0dede12a6a3f8d440a0f	1669358891000000	1669963691000000	1733035691000000	1827643691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
414	\\xe1f3892851e526185abe21fb96fe60d1c49107ade0a5fbd1bf1a7c5cc15bde664c5bb2ad01a361c49270911c49f4837cc4bdc63ba62adcbbae77c958bdd77b4e	1	0	\\x000000010000000000800003bbd10973aa6b89f3689b8d8c26d46f525f38a844043cabcfb03a2f01c4450d50142e081c99a704aef9476694156fb46819a9bdcbf1e8bc0beac6a1344ac01995998fac965497082e3a12a65e0a4f0e10b6465a40bf32ea822d89b3adb96c27bc55f8fdf66f853421c2484ce4df5a5e840dc2f72785dfb019e510ea10c30f4ced010001	\\x2fc455f4711409d305304da7472d0f0501667d806b98540aa6f06ba3f434c595a94eefff407607b82f6abaaf17e36e529b63be6e43c02b1fac18c1c42b75e30d	1650619391000000	1651224191000000	1714296191000000	1808904191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
415	\\xe23fe26822db16f0cfdb542573df6eab01a3b4913c2577f55076c69a8bafd540a364dd8ac11a071abdd8af142507730f8d64d33dae9cbc6096708cfa704040d8	1	0	\\x000000010000000000800003b7542877dcd2cd207b04e5cb041e2de3f56286f18b02d289e48138094a0cd28140a5353fb0f79e9fa6cf6b9eb0c5687fac5f96fd6b881ea98999e659dee10c9a6f91c2fc915e0cf546604ec0dddefaef205a22a9ab2408a2f2fdb0f23cc19f0cbdd4be964fe2d2f47ca0d693b7d50d051c79a6b05fea5944ace295d9c2e94cb1010001	\\x48c2ee67da2ef1c841101abf7931adff1de76d53871ddd366962f5b0dc320751bcb186330c9f0cc905d541dfc96c86ec72d0fa14030f3f0b8deb2e735461db05	1669358891000000	1669963691000000	1733035691000000	1827643691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
416	\\xe393fbf4da8a10854fcbc86500af27dd8dbcc4289f038f18d87f824174b5ead1e55eeecc28b4de966c160fc3301ab4cc03bbccc8b09e791fa080ebe5516dacb4	1	0	\\x000000010000000000800003c891d64addf9e970e661a7470df2cc24c622db2241f828e0496c4216fbbc2ac77316ecdca7882833ba4dcdc55c8442bb25109222bea199df56148051234a6604b6ad6e5c0b54751f1a3aec57594ed95203bb6e4f0a3e92d6d60da8b2829b439a03737a987f0b395c943c8e46c5dcba68e563e13482e5b4f93cf36f17a47b231d010001	\\x7f70e8282bedc3d2c5c066b351626237a7f2cce9c079fed75f548770f9ce0aa0147424ab13b0acea51062d2bae676e6de49118d6dedcec99a99e14df2b2af008	1658477891000000	1659082691000000	1722154691000000	1816762691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
417	\\xe6830394f7cc11a9b0ef885169e1c0f348d372041fa99996fd7ab742b97b4170a34797d49f7b121023a81229c359102d1123cd9bd8ad3cce0e1794ccc5339702	1	0	\\x000000010000000000800003a1000b3d429e51c2dd88c9b83479c7de3a4badcae352f19a159ed49bffb2d89a94b4a7b16b440c9eef9113e3c18a90f6afd591de0519a4a356610fe20b11c57df4f3ba13caa4b485abf4b70262173e68aec4f77fa640856b20a423c465ec74a9f2d6537a370f8128041b91909d338714fdca589197ee9519de8ee8bf5a2d04a5010001	\\x1f76526c2c31f02c36f5db51503e4a1a6d40934e83b77c285519d0f021c9e24a359e8330a5d554291a14cccb81235529ab06a8cfa713d7663142a1abfe85cd01	1677821891000000	1678426691000000	1741498691000000	1836106691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
418	\\xe96b2edec57ae1033537db3374977a1120aa9116c29d3d7f6e9a40abe5d20270c7c97c959f660054f449ce0088cc87d1b2030df30a2414694b4dd862d0344a56	1	0	\\x000000010000000000800003b4825b4bf36dca647f6ef2f42b354b4da4e66fe4639bcbfa257753811e9aec1f5f36f3e2e62d3aa9ae72a207304a8f14481dc2e45632c46a975b3f744ea45b9ccbdc76c70af671fc9da1478a0126969e396cdb196484319bf8639ccc451d576e52e7aaab0f3caf6248654dc60136783e2a08c5fa274b08d60b907ea5b97a229f010001	\\x312b6e29154e6fec74429c4631412a92572c221c2506204aca1ea3e2cea6b9a8f04a0a998b8c31d83845bf92a481b10b234afa793bc2c33b289cbafb3c2e250e	1671776891000000	1672381691000000	1735453691000000	1830061691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
419	\\xe92f561fea86091c8342eb4f0aab56b47bb024d6f9bb51da4c728f2b5a6c1b8b74d866654f47928a1822ed438ac2f9eb154b19bf24eaf96155bbe9b939bbcf01	1	0	\\x000000010000000000800003c475934f9ae557f13be937fea0ece092b4140dea2bc280248488fe62158dc22be086ba0ea447a374f3d9d7a49eb15d11faa70b6f5e152f62eb7e2d14c8a496b49ecfc2f2dfa1e113ba862dbfd7c4a14b3908ee210fb82423a653e4774b5b5cbdab6adbbbd9b21216e00a379658934cae927a44c05de658ed9c3f63cf169e5af9010001	\\x2fe3a2b77e71d22070a272dfa99b2de79baab3b64df4780b24fd00c95547fd687fba8c94ef8fa809c16717b40296c9f245061441827e82374f4aa48f395fe00f	1677217391000000	1677822191000000	1740894191000000	1835502191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
420	\\xefd33f28b6c04384e7dc137185ba7db4377a8cd3f5f5938be883fa7b3abaf0cfb9c52f170d48007f42d4352c71a88c68b78c58422c9360ac51cb82d9f5c1e298	1	0	\\x000000010000000000800003dd99c1c60892e81e4f21b1bb3523d9a37f91e3c5a1a69b9a296d0668aa513945a7e80e1e0582384b4f0ef2509cd8f6f463e9dc50db9298dcc43fb2c43d796f39f09ce9e6d8368c9b1b275368e7d944447884bf02e4ac9f2c38b64512af818b3b34d10c0d6b2aa24e2676b46065bfe063d32708a6203bf1d71cfcf8082dad311b010001	\\xa01aaa8c48eb06195725b2d46e6f6fe01ce1f23ce7e32f211635091e324e6da66eb8ecd40eee5d54285af512b76833712e8a45b6a1287037fe4a91c08606380d	1653641891000000	1654246691000000	1717318691000000	1811926691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
421	\\xef07a6fde1776b03137187588fdccf4f4479312ce2b95fd0213a7eccd9764ae5b0a7ca8aa87722086d8cd68e70b24f125765355d9f2329a48792e52dc69b824d	1	0	\\x000000010000000000800003e415d1c95cc950f2bd03313edb6a87dc93e17ac9228f8baec26185db6605af9f0a9fb8ef384c77132399a7a4ad383b74d477d855560d0eedbefa326c15035efd446537b1fa59c865593414ec5e42489b6b2bdd467eff72c0e6906f979d13ca0fc0d502adcea513fc8f9e4149a7cafa1313ed9ec3b581c7064ab08c5c26b7d835010001	\\x389aa6f58f5130efe7923f24958c8f0350be1423e8df08b1a7e5f6615a7afb54d7529807d828666e20a09f3be2ce1785cd506bbaf20196b828cf2ffecc6d4104	1663918391000000	1664523191000000	1727595191000000	1822203191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
422	\\xf363d3e6a91f474071a230bc27e934f96698822aba17b564bbf969382bbe5e0bcfab6cec0c2c926fe3977cddb99dd9d572939d82195a4724bbb7941d4697f1f6	1	0	\\x000000010000000000800003bf85c1313de283a428f4ab66ab63b9e4fc9a5769eec61603e11fdf6c8679ce3aee01f592813a19a68f233931437ac247577738d3cb7bf444074a8c5f33763b5b885d811ac8d59ce4159295a2cc88ca565f075fbcd7578f7be98433662769b7563e4f307dd48255b3722b6baa48400aba8887bf1bef1e35c361bb4e4a3bab06c9010001	\\xb6583964bd849cce2b3e9b8007cff991cd609429272ad8c6e4523eabff5bc686bc4c97d5eae28485112091fa88c84508040effa7caff724034b4079ec9c4f00a	1659686891000000	1660291691000000	1723363691000000	1817971691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
423	\\xf56b9b3b7b45e7012854a5fbe3c7a93bc22faca6bb137254b699853e5c298f6a0b65393d20426e2ad1da4c9601277c21b118d6a6f2750492b11063b844b0a2a5	1	0	\\x0000000100000000008000039e46b176c2d60aa2be6ccd755a1d11fc0b5f7da7edb133862f38d679c9c5f4c7550beb1c7a84852d03f2821ee21e20ce78eda307bd3f60f45c4b75e3313d2b56fa807964e4a861d6c4d7a9c613b83b264a9d0f0ffb11d65d1b34e5a2bc1f3c4954f3b1397d62985cb95dcbea5fbf788724e28a7a45981cbcbd295830eb1694d3010001	\\x25aa83cd3fcbfb7b6b95cb4ae8f38e71eb77af0c04914d9ebced16cd2dfef0cabb092718d4b6a402e214b8077097e8f209eee1f63959156e52905fc973e9a108	1656059891000000	1656664691000000	1719736691000000	1814344691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
424	\\xf897338881dc0c1dc4f8c152320bf4138695f3fc43446fe74c5323a632e267fa7d911b95cce58e572d253f1737a408053d6223dd507cc28cbc046dd32cfe4d8a	1	0	\\x0000000100000000008000039dab70b6719e4c3063d682c21b45d6d754deec7728403a738886a1ea8b6527dcbb82c6021f67d37ba84b7115d593a5704c561ce48dd8b363309dc02f18de2b2298669b65acc2c2ee19073db12dea046e5c0dedadda1cc60f86dcdaa8ac975d4968b025ea32c9ddd6898ec0730a0ede27d8beef9c03f00295fd049b68a8e94bef010001	\\x27086d5deeb45954d6c9660d8930f393cf8f9a08bd93438460247e5e5b052dd800400b8c0bef64cf2e40ccab7456131e9c79c29caf5d774898bb91c438756d0e	1650619391000000	1651224191000000	1714296191000000	1808904191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_extensions, h_wire, exchange_timestamp, refund_deadline, wire_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\\x3edc6ac2a2dc10610ddc284fbcb0e11e201265346792552ca9c8b84bb1d2860b	1	\\x3d39358b2a2a7a512262e928cd7c28f046086e44c4cbda1ed1f65815b12b581b23a51764d945c8c988a51b2f62bc6ffc45a5ddcbb0b0c25b0d729fccab6b7dd9	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x478b82d2589c200bd9243779aecf858a2a88c28482909193453580de5b3d1f0f563afc155c439bd2a614e089d8a4a3e99976c4f52aaf05b51c7963e2c0b19b64	1650014923000000	1650015820000000	1650015820000000	0	98000000	\\x6a2edabf479d4f56cc1d5a5595a0ef744ab68fe3ca7475363debc3de3da8ea1f	\\xbf043aeb614c13f9ca8f80d43371c8b0c86117e4d7f95b0cac7eab0d535b429e	\\x2f99a8bc52f11e98b7f7ca4f41d5d19cf61f948a3f87b76c508109079250c4d2637118e94e253746277a7d1bc81b92c0a560b203bf3d725b18808990f990db06	\\xde292cf6cb4657a9df7d4bd5a23f6308e04499941117b3aaab80b660d2c13f03	\\x707234aaff7f00001d199d0fcd550000cd349f11cd5500002a349f11cd55000010349f11cd55000014349f11cd55000070bd9f11cd5500000000000000000000
\\x3edc6ac2a2dc10610ddc284fbcb0e11e201265346792552ca9c8b84bb1d2860b	2	\\x15ba140137ed47bf4ab326ee8022b6eab22cf5d5531fe88fc7b4f22dab9df508855ef766498867d4be0d33ec44019a5d1d4ac619b53487ba7bad6a26b7b8c326	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x478b82d2589c200bd9243779aecf858a2a88c28482909193453580de5b3d1f0f563afc155c439bd2a614e089d8a4a3e99976c4f52aaf05b51c7963e2c0b19b64	1650619757000000	1650015853000000	1650015853000000	0	0	\\x04cbe80aa2bf917103e27fde4dc02da718a733f67f65c6f13d610d01b06c1c5f	\\xbf043aeb614c13f9ca8f80d43371c8b0c86117e4d7f95b0cac7eab0d535b429e	\\x3de385e616ea96cf31d1f230b3abb4693623876d3b1da293da983b4e22b02f8c5708736d1380375a67a633c815efaaa9b1cbff7a400aa8fe042539ba7b9e550d	\\xde292cf6cb4657a9df7d4bd5a23f6308e04499941117b3aaab80b660d2c13f03	\\x707234aaff7f00001d199d0fcd5500002d67a011cd5500008a66a011cd5500007066a011cd5500007466a011cd55000010349f11cd5500000000000000000000
\\x3edc6ac2a2dc10610ddc284fbcb0e11e201265346792552ca9c8b84bb1d2860b	3	\\x15ba140137ed47bf4ab326ee8022b6eab22cf5d5531fe88fc7b4f22dab9df508855ef766498867d4be0d33ec44019a5d1d4ac619b53487ba7bad6a26b7b8c326	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x478b82d2589c200bd9243779aecf858a2a88c28482909193453580de5b3d1f0f563afc155c439bd2a614e089d8a4a3e99976c4f52aaf05b51c7963e2c0b19b64	1650619757000000	1650015853000000	1650015853000000	0	0	\\x08cd257e527bd68e24f94f86d3d34d914b05523cedefc11fc3e5ec602543cd0e	\\xbf043aeb614c13f9ca8f80d43371c8b0c86117e4d7f95b0cac7eab0d535b429e	\\xe32d769698ff900609489216e9c3c0a5e10db2d36cc429150a4f13cf661e4bbf6ce3a610804972493fd6b35509a5f7ad7bcc2252de072f09d0dc532766bbc000	\\xde292cf6cb4657a9df7d4bd5a23f6308e04499941117b3aaab80b660d2c13f03	\\x707234aaff7f00001d199d0fcd5500003de7a011cd5500009ae6a011cd55000080e6a011cd55000084e6a011cd55000060399f11cd5500000000000000000000
\.


--
-- Data for Name: deposits_by_ready_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits_by_ready_default (wire_deadline, shard, coin_pub, deposit_serial_id) FROM stdin;
1650015820000000	1149703533	\\x6a2edabf479d4f56cc1d5a5595a0ef744ab68fe3ca7475363debc3de3da8ea1f	1
1650015853000000	1149703533	\\x04cbe80aa2bf917103e27fde4dc02da718a733f67f65c6f13d610d01b06c1c5f	2
1650015853000000	1149703533	\\x08cd257e527bd68e24f94f86d3d34d914b05523cedefc11fc3e5ec602543cd0e	3
\.


--
-- Data for Name: deposits_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits_default (deposit_serial_id, shard, coin_pub, known_coin_id, amount_with_fee_val, amount_with_fee_frac, wallet_timestamp, exchange_timestamp, refund_deadline, wire_deadline, merchant_pub, h_contract_terms, coin_sig, wire_salt, wire_target_h_payto, done, extension_blocked, extension_details_serial_id) FROM stdin;
1	1149703533	\\x6a2edabf479d4f56cc1d5a5595a0ef744ab68fe3ca7475363debc3de3da8ea1f	2	1	0	1650014920000000	1650014923000000	1650015820000000	1650015820000000	\\xbf043aeb614c13f9ca8f80d43371c8b0c86117e4d7f95b0cac7eab0d535b429e	\\x3d39358b2a2a7a512262e928cd7c28f046086e44c4cbda1ed1f65815b12b581b23a51764d945c8c988a51b2f62bc6ffc45a5ddcbb0b0c25b0d729fccab6b7dd9	\\xfb019bb1c438b1bf7db3c494c54b14ec7e2f70449a9a375c1f5fe9c770077580e6afed847c9396fc649c88a01ddbddd9bb7fc0c5454efabc7361adee9deb0b03	\\x1f897957e8f5780dd00e89b2ef9b6f9d	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	\N
2	1149703533	\\x04cbe80aa2bf917103e27fde4dc02da718a733f67f65c6f13d610d01b06c1c5f	13	0	1000000	1650014953000000	1650619757000000	1650015853000000	1650015853000000	\\xbf043aeb614c13f9ca8f80d43371c8b0c86117e4d7f95b0cac7eab0d535b429e	\\x15ba140137ed47bf4ab326ee8022b6eab22cf5d5531fe88fc7b4f22dab9df508855ef766498867d4be0d33ec44019a5d1d4ac619b53487ba7bad6a26b7b8c326	\\xe5ba2f78ebf05ab4d11e35796660f8940f6333fbcb1902d627a88dad94055104a9e5fe4bfd1d6ef099616333c0605c962aa990064545a4c5bf997cc0e4224d02	\\x1f897957e8f5780dd00e89b2ef9b6f9d	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	\N
3	1149703533	\\x08cd257e527bd68e24f94f86d3d34d914b05523cedefc11fc3e5ec602543cd0e	14	0	1000000	1650014953000000	1650619757000000	1650015853000000	1650015853000000	\\xbf043aeb614c13f9ca8f80d43371c8b0c86117e4d7f95b0cac7eab0d535b429e	\\x15ba140137ed47bf4ab326ee8022b6eab22cf5d5531fe88fc7b4f22dab9df508855ef766498867d4be0d33ec44019a5d1d4ac619b53487ba7bad6a26b7b8c326	\\x348c57e5131be5448c0c87876b635d75b4b6d2465f433b2cb2fba39538bb0dddd61396d4dd66614d0309cfd7506c3e5b865e0ee94ef6e5fb6d4be0b6f45a8305	\\x1f897957e8f5780dd00e89b2ef9b6f9d	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	\N
\.


--
-- Data for Name: deposits_for_matching_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits_for_matching_default (refund_deadline, merchant_pub, coin_pub, deposit_serial_id) FROM stdin;
1650015820000000	\\xbf043aeb614c13f9ca8f80d43371c8b0c86117e4d7f95b0cac7eab0d535b429e	\\x6a2edabf479d4f56cc1d5a5595a0ef744ab68fe3ca7475363debc3de3da8ea1f	1
1650015853000000	\\xbf043aeb614c13f9ca8f80d43371c8b0c86117e4d7f95b0cac7eab0d535b429e	\\x04cbe80aa2bf917103e27fde4dc02da718a733f67f65c6f13d610d01b06c1c5f	2
1650015853000000	\\xbf043aeb614c13f9ca8f80d43371c8b0c86117e4d7f95b0cac7eab0d535b429e	\\x08cd257e527bd68e24f94f86d3d34d914b05523cedefc11fc3e5ec602543cd0e	3
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
1	contenttypes	0001_initial	2022-04-15 11:28:11.976939+02
2	auth	0001_initial	2022-04-15 11:28:12.113152+02
3	app	0001_initial	2022-04-15 11:28:12.210319+02
4	contenttypes	0002_remove_content_type_name	2022-04-15 11:28:12.228453+02
5	auth	0002_alter_permission_name_max_length	2022-04-15 11:28:12.240594+02
6	auth	0003_alter_user_email_max_length	2022-04-15 11:28:12.252397+02
7	auth	0004_alter_user_username_opts	2022-04-15 11:28:12.262037+02
8	auth	0005_alter_user_last_login_null	2022-04-15 11:28:12.272047+02
9	auth	0006_require_contenttypes_0002	2022-04-15 11:28:12.275071+02
10	auth	0007_alter_validators_add_error_messages	2022-04-15 11:28:12.284929+02
11	auth	0008_alter_user_username_max_length	2022-04-15 11:28:12.300373+02
12	auth	0009_alter_user_last_name_max_length	2022-04-15 11:28:12.310455+02
13	auth	0010_alter_group_name_max_length	2022-04-15 11:28:12.323729+02
14	auth	0011_update_proxy_permissions	2022-04-15 11:28:12.33675+02
15	auth	0012_alter_user_first_name_max_length	2022-04-15 11:28:12.346635+02
16	sessions	0001_initial	2022-04-15 11:28:12.3753+02
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
1	\\x639e912010d6d6a4a8315c8bdbc5397d09f1ee56b1a8e76b760d0c49045f4efd	\\x69535ebf6809571d0622d01180f1723e1c76a5fa2776753cd88078ad926b1f57df1b86bd744c7184f5a361cb25b355a88811e2ca6bde280c15a89436fcae7001	1671786791000000	1679044391000000	1681463591000000
2	\\xa6f15cf03ca7517eaf46714fd9926183cb2713bfde6398a1c8fa631323608ae2	\\x94662848043c1ef2032b604c6b324215ee91debba1b0db01d800d0e5e62cf8e90f4238e3aa8a733b73108fc6e8c7642106bcc98768143fee7021c6265fb20f0f	1664529491000000	1671787091000000	1674206291000000
3	\\x061b709203d969717dbf7a758366c26808a686ee62113ff2aa8a2d449ef7c739	\\xe272a657e3c51de0c847ae548227c6d4b1506fe37814e959e327524bb0d377506b45942ef5ea887fa6ee64e95a9417726f0691720d9f06f6c1279b7f48bb1b06	1657272191000000	1664529791000000	1666948991000000
4	\\xb6e2f3405229792b32eb3ed209203f96b2b05f795e9825748368ab74a94e66bc	\\xf50b66646eac149517279c545e7705f893f2f152eea8344ef0eff42de091f2d27ca96c15850eec6a95e9cb15bcd1973f18815fdf7a86acb84115312fde49bc01	1679044091000000	1686301691000000	1688720891000000
5	\\xde292cf6cb4657a9df7d4bd5a23f6308e04499941117b3aaab80b660d2c13f03	\\x431c7712733519f91caad5fdd85c740f9e15ed72186a78653a68779ac796518eada9b7327add52f09533939df30cb54b808fec6d63f2126920006ad37a67d80e	1650014891000000	1657272491000000	1659691691000000
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
1	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	0	1000000	3600000000	3600000000	31536000000000	5	\\xc30f8680aadc31012fdfee4b398dec834ca3d71065f1b92ad69669c7dab5fcf7d2ce1ec360feae8e9018110ed6eba4b31fd775a5bb2967db10448eacdb503f09
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
1	208	\\xed57b2865be7ee72fd6b53f7028069693adc0f59de1128bb9e6343901dfefc0f	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000042ce9dc8c8231b53184e44d4aed41ca8475b9afb1e9141634432d827c8915e8f173a1a892c39c99935ba1f0e8c9168cf4947674b0c35ac7c45041988b9df64001531767de50a1356f265d2041480a216ffa21145350e83eaa49a56c5e2a783e16c7b5e103b5894d4e9eb79ed3ec976289a2b652350598331e6a927e1bb604b9b	0	0
2	139	\\x6a2edabf479d4f56cc1d5a5595a0ef744ab68fe3ca7475363debc3de3da8ea1f	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000a0a182570ef5db4b58baacacd601cf07f2c8f8a850ec1eef4af7a110af80570c053bb44d7b8ea92bfe46af24ea411c6b2f08cb9746f363974c1bd06fd1f5477813403c1fa55d38ab335b2de52a277f9bd7c85e6f860c5065cae26b9ece4da319eb7e20bc36715d95c3da2c11d135ab788d42239af007bb0e8cbed6689df489b1	0	0
11	64	\\xe492b4177d9fc9338149cb6ed522f4b62f8c2d2ad1dce406e01635e33382cf8d	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000045003641db6b076f79d5f0e7e883e8423cfc8fd33bcb620f219c27ac9581174f565d427124250be577715d3b798703fcf3da9196397f35c57913d217bfdc57f46ec0f74067224f4d24292057e8352e2dc05be3f29b7baceda6503b5132d72287039c6e7f7888f6965a6ac4acd4bf741453f06023fcfc77b99a94fc5a26352704	0	0
4	64	\\x204f13ea5bab8478b4e4712da71071bc78adb472093ed65ea4cea37de84781e9	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000004e6d0413ac5ca4e10850d8aa5d5f29d8bf0b96fd8bcae22a45a811d3c556d69639b86ad24da536b02c34ea6a0ce60f1cdd0cd0e874dd1c5aae25c40b92ed7592beab34b15734ca988c9ac71f93833177d0caa0c2d36cecda37aa53f244b8edb869d043a62c0424809953f0cfeea905db5e1a03750c5fd6156ff63fa25bdb7766	0	0
5	64	\\x25ab1f579e2eb9dad87fd6b1eb27572dfb9b969fd188bcd0e0d9d719a5178fcf	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000bd4c9b6fa5a3edff8f88d7c12d2a82c411cb11546debbb29deb5958b0a60ffd31b66688296d7ecb7a6ced81a95f326158b42db3cd19d2e93cb5f02b04d0189998252c44b730669b9bc0dcc2ea28b2dfc0293b5734eb1d39572c83f995d16fc53f3a4e3e53945cff96641b5e1153121749d9df9c51e45f90aaa7d72e9169ea8bc	0	0
3	225	\\xa1c00c9804ebc6adf68b2d2208d43e09afa7746d32de2d3c68258ba1cd4a8e73	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000c7bfc045e2a42c21811647332e497acecddbc54adefc44940221924438939880b6e7bc04c5010d3b76c66fb9953f08f316c9a734f425b2e69a1b575eaed4e826decd9da73c9b1255ae0dd24374074029f424f4d69e88a856c2321aefa67750ff0e5021767f0a7a24eef95ae827a484613adef0a0f54fec911712719dc456c9b9	0	1000000
6	64	\\x6337d438e3c436727fe9576e8533b93413ba36476509c2d11b5a983d30f57379	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000209aacc132bfbd8a181217b880e93d8127df7aa9580c819756595b77ea9ffb8da05fbb67a73df0f836d7c97bffcf892983db516663d600d55b677e4a82a46c614bc26c75c4d2d205a6e90687285a659a4a064dfa73488845cf58a4b272eacf640209a69a15cbd2fcb72614e1cb3208e7829e27aec3bd0d872bead589d5891530	0	0
7	64	\\xd2f0722b9792543976c158f46c87fd9ea9f1d64b9d5fc59b4c57d7a47f774277	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000057db0177e18cfb59316804744d0f3e3da676d97a6437cde4efe1514156c4eefc99b45b41e80d7fbfd41978feb3bd7d2ffc15d754bb93b3596e481886d6a17853a4c9d696fe33b5931f500c0b8c9c5f531fbadb5d3a04fccac0a2d11d31a7b48e33abe429ad00db785a3259316d231c31b9d5610a7d46f4efe628a639d7fb85f2	0	0
13	411	\\x04cbe80aa2bf917103e27fde4dc02da718a733f67f65c6f13d610d01b06c1c5f	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000006b9df98a358f8e0776e97df00b61dfabf3613f9bb74298c6929bdefe2d60c78774059092f5abfc6907fb2417bab97a3ea7510fcad0c80a0e69a26fcca4f2abd80a0df2599685fffe38ebc426dbe92c876e37680a1d84a14b93f77a228c961b5f9002200f363e67ebf7fa9cd92799e5e3a93e88c790821a4d19c99de1de0401cc	0	0
8	64	\\xda387d45e9e7d959464acd2ab25f5666b2c34efe4e70ca9c65bc04d7fa784c3f	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000e893c29ad2b13fc8ecc8c2a95b006a2fdcd72acbe9fe36a94e8a2b1e43aa5fdbf4241f065357d4f18795fef3b247f9ff2a5f531c320529d67e65d8fe864366d1df47d91b7453f947a22e39b6c661a5b80c39027f96df0cdd2ff349d4f5d4a5bbff501d6c62697684efc23d8b5e5f230f9935cac30476fa059519a3716dab4cf1	0	0
9	64	\\x5c03aa02235428daf462859e8a3ca6dc17c86f73de3b902fae3dab590cbbf9dc	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000021b4491624293c51c47e0324b386eb2248c8c2c6b81d07c93dea667fe2447350e0f461cf2251444241b31301a6f241af0764f7dc2337e79b2be1e0767c8141b1cb768003f872b3d53209692c9726d7774558c99ddeabb59fa22d9a6bd4d88faf16be768ba26910a2e80c6a42c368843f83640f794feddba19192ea21edaf0e53	0	0
14	411	\\x08cd257e527bd68e24f94f86d3d34d914b05523cedefc11fc3e5ec602543cd0e	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000017b43e6df08230bb15f814c5a1f331560a7d6a86c01ceb8abf1374491b00d59b7c432a1964c36729e7c5b78a4308d4811b2f425606e3f5c98ca8db5a90bb440aba58927389c8e73193820a0231d28d9bc3aabd531c0945dba2309cb24bc233318978230434a52c560fa052a937dde9cdd18bd60cb9aff277cdec974f9a9f1c42	0	0
10	64	\\x39b53822bc6ad24f14da1fe9902dd11693bc8b8c6a3a61e7825d0f5856375185	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000091ba01378cf71175691a71c86bafae04fabc97605e8168c456b514f49386c882ff1f3f3c79808eae7787bfc064e4e3a38db452bfd464d9753418b7b964ea4dca6703f0661ed2edff3e8bcbe1839230aaa45cd080c81d6417799528a11bfb45d48edb7bd8c99b38933cf7e9fc3627103a8730ea16ccd6c552de78c773f5b0487c	0	0
\.


--
-- Data for Name: merchant_accounts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_accounts (account_serial, merchant_serial, h_wire, salt, payto_uri, active) FROM stdin;
1	1	\\x478b82d2589c200bd9243779aecf858a2a88c28482909193453580de5b3d1f0f563afc155c439bd2a614e089d8a4a3e99976c4f52aaf05b51c7963e2c0b19b64	\\x1f897957e8f5780dd00e89b2ef9b6f9d	payto://x-taler-bank/localhost/43	t
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_serial, merchant_serial, order_id, contract_terms, h_contract_terms, creation_time, pay_deadline, refund_deadline, paid, wired, fulfillment_url, session_id, claim_token) FROM stdin;
1	1	2022.105-00M0BRXQJE1F2	\\x7b22616d6f756e74223a22544553544b55444f533a31222c2273756d6d617279223a22666f6f222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f73223a313635303031353832307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313635303031353832307d2c2270726f6475637473223a5b5d2c22685f77697265223a2238593552354d4a524b4747305150393436585754584b573548384e3848474d34474138393334543536503044575053583357374e43455157324e45343736594a4d524145313245524d4a48594b364250524b544a4e425235504d45374a525a3252325253505330222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032322e3130352d30304d30425258514a45314632222c2274696d657374616d70223a7b22745f73223a313635303031343932302c22745f6d73223a313635303031343932303030307d2c227061795f646561646c696e65223a7b22745f73223a313635303031383532302c22745f6d73223a313635303031383532303030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22375645364e474e3256473836323345573531375653433731335247313453394d4359393541423539533257345143454a47523547227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a22515732334e5456313947395a4b4a4d4647334133365745385033343632355a34545a574e5033354346544e47544d545638414630222c226e6f6e6365223a22524b3547365636344e36564154334a4a4835334e333259454433423143394631344d3545594b354642354642344e505456504247227d	\\x3d39358b2a2a7a512262e928cd7c28f046086e44c4cbda1ed1f65815b12b581b23a51764d945c8c988a51b2f62bc6ffc45a5ddcbb0b0c25b0d729fccab6b7dd9	1650014920000000	1650018520000000	1650015820000000	t	f	taler://fulfillment-success/thank+you		\\x8687beae14d1953a576cbb0d8deb955c
2	1	2022.105-0371GG4RCR620	\\x7b22616d6f756e74223a22544553544b55444f533a302e3032222c2273756d6d617279223a22626172222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f73223a313635303031353835337d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313635303031353835337d2c2270726f6475637473223a5b5d2c22685f77697265223a2238593552354d4a524b4747305150393436585754584b573548384e3848474d34474138393334543536503044575053583357374e43455157324e45343736594a4d524145313245524d4a48594b364250524b544a4e425235504d45374a525a3252325253505330222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032322e3130352d30333731474734524352363230222c2274696d657374616d70223a7b22745f73223a313635303031343935332c22745f6d73223a313635303031343935333030307d2c227061795f646561646c696e65223a7b22745f73223a313635303031383535332c22745f6d73223a313635303031383535333030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22375645364e474e3256473836323345573531375653433731335247313453394d4359393541423539533257345143454a47523547227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a22515732334e5456313947395a4b4a4d4647334133365745385033343632355a34545a574e5033354346544e47544d545638414630222c226e6f6e6365223a2232585741544e4431424658315a4d30345941503150384a4b41444b4d32323954343253474b30365052584d564734543338563047227d	\\x15ba140137ed47bf4ab326ee8022b6eab22cf5d5531fe88fc7b4f22dab9df508855ef766498867d4be0d33ec44019a5d1d4ac619b53487ba7bad6a26b7b8c326	1650014953000000	1650018553000000	1650015853000000	t	f	taler://fulfillment-success/thank+you		\\xf0ea97fda79bef086ac2a57d9ab46a05
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
1	1	1650014923000000	\\x6a2edabf479d4f56cc1d5a5595a0ef744ab68fe3ca7475363debc3de3da8ea1f	http://localhost:8081/	1	0	0	2000000	0	1000000	0	1000000	5	\\x2f99a8bc52f11e98b7f7ca4f41d5d19cf61f948a3f87b76c508109079250c4d2637118e94e253746277a7d1bc81b92c0a560b203bf3d725b18808990f990db06	1
2	2	1650619757000000	\\x04cbe80aa2bf917103e27fde4dc02da718a733f67f65c6f13d610d01b06c1c5f	http://localhost:8081/	0	1000000	0	1000000	0	1000000	0	1000000	5	\\x3de385e616ea96cf31d1f230b3abb4693623876d3b1da293da983b4e22b02f8c5708736d1380375a67a633c815efaaa9b1cbff7a400aa8fe042539ba7b9e550d	1
3	2	1650619757000000	\\x08cd257e527bd68e24f94f86d3d34d914b05523cedefc11fc3e5ec602543cd0e	http://localhost:8081/	0	1000000	0	1000000	0	1000000	0	1000000	5	\\xe32d769698ff900609489216e9c3c0a5e10db2d36cc429150a4f13cf661e4bbf6ce3a610804972493fd6b35509a5f7ad7bcc2252de072f09d0dc532766bbc000	1
\.


--
-- Data for Name: merchant_exchange_signing_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_signing_keys (signkey_serial, master_pub, exchange_pub, start_date, expire_date, end_date, master_sig) FROM stdin;
1	\\x3edc6ac2a2dc10610ddc284fbcb0e11e201265346792552ca9c8b84bb1d2860b	\\x639e912010d6d6a4a8315c8bdbc5397d09f1ee56b1a8e76b760d0c49045f4efd	1671786791000000	1679044391000000	1681463591000000	\\x69535ebf6809571d0622d01180f1723e1c76a5fa2776753cd88078ad926b1f57df1b86bd744c7184f5a361cb25b355a88811e2ca6bde280c15a89436fcae7001
2	\\x3edc6ac2a2dc10610ddc284fbcb0e11e201265346792552ca9c8b84bb1d2860b	\\x061b709203d969717dbf7a758366c26808a686ee62113ff2aa8a2d449ef7c739	1657272191000000	1664529791000000	1666948991000000	\\xe272a657e3c51de0c847ae548227c6d4b1506fe37814e959e327524bb0d377506b45942ef5ea887fa6ee64e95a9417726f0691720d9f06f6c1279b7f48bb1b06
3	\\x3edc6ac2a2dc10610ddc284fbcb0e11e201265346792552ca9c8b84bb1d2860b	\\xa6f15cf03ca7517eaf46714fd9926183cb2713bfde6398a1c8fa631323608ae2	1664529491000000	1671787091000000	1674206291000000	\\x94662848043c1ef2032b604c6b324215ee91debba1b0db01d800d0e5e62cf8e90f4238e3aa8a733b73108fc6e8c7642106bcc98768143fee7021c6265fb20f0f
4	\\x3edc6ac2a2dc10610ddc284fbcb0e11e201265346792552ca9c8b84bb1d2860b	\\xb6e2f3405229792b32eb3ed209203f96b2b05f795e9825748368ab74a94e66bc	1679044091000000	1686301691000000	1688720891000000	\\xf50b66646eac149517279c545e7705f893f2f152eea8344ef0eff42de091f2d27ca96c15850eec6a95e9cb15bcd1973f18815fdf7a86acb84115312fde49bc01
5	\\x3edc6ac2a2dc10610ddc284fbcb0e11e201265346792552ca9c8b84bb1d2860b	\\xde292cf6cb4657a9df7d4bd5a23f6308e04499941117b3aaab80b660d2c13f03	1650014891000000	1657272491000000	1659691691000000	\\x431c7712733519f91caad5fdd85c740f9e15ed72186a78653a68779ac796518eada9b7327add52f09533939df30cb54b808fec6d63f2126920006ad37a67d80e
\.


--
-- Data for Name: merchant_exchange_wire_fees; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_wire_fees (wirefee_serial, master_pub, h_wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, wad_fee_val, wad_fee_frac, master_sig) FROM stdin;
1	\\x3edc6ac2a2dc10610ddc284fbcb0e11e201265346792552ca9c8b84bb1d2860b	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	\\x78fbd61470a82d67fe97e9887fc52b2d65f1417679983d42aef1b5885aab0bce35fd81fab38c85edbd64db2f66c8b10d783e35a2fa634aa75ec250773cd6e90a
\.


--
-- Data for Name: merchant_instances; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_instances (merchant_serial, merchant_pub, auth_hash, auth_salt, merchant_id, merchant_name, address, jurisdiction, default_max_deposit_fee_val, default_max_deposit_fee_frac, default_max_wire_fee_val, default_max_wire_fee_frac, default_wire_fee_amortization, default_wire_transfer_delay, default_pay_delay) FROM stdin;
1	\\xbf043aeb614c13f9ca8f80d43371c8b0c86117e4d7f95b0cac7eab0d535b429e	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x0000000000000000000000000000000000000000000000000000000000000000	default	default	\\x7b7d	\\x7b7d	1	0	1	0	1	3600000000	3600000000
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
\\xb3d8e6bb3680ae2afdbb843d4a39675da873af4fc776376a4681c2155f95945f	1
\.


--
-- Data for Name: merchant_kyc; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_kyc (kyc_serial_id, kyc_timestamp, kyc_ok, exchange_sig, exchange_pub, exchange_kyc_serial, account_serial, exchange_url) FROM stdin;
1	1650014923000000	f	\N	\N	2	1	http://localhost:8081/
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
2	\\xed57b2865be7ee72fd6b53f7028069693adc0f59de1128bb9e6343901dfefc0f
\.


--
-- Data for Name: recoup_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.recoup_default (recoup_uuid, coin_pub, coin_sig, coin_blind, amount_val, amount_frac, recoup_timestamp, reserve_out_serial_id) FROM stdin;
1	\\xed57b2865be7ee72fd6b53f7028069693adc0f59de1128bb9e6343901dfefc0f	\\xeec2eaf77bf6e60cfa98dca95561ad866f8fe57636b7772dfbc3866c8b3505a9b9242f5172e7120ea2d634f2f7e7f0c213d61b87dd3907dc802aa3e07eb0600d	\\x57c8f0cbca46eb233345ce79904eac16734efa175f6da79fbcf742f771d4b35c	2	0	1650014918000000	2
\.


--
-- Data for Name: recoup_refresh_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.recoup_refresh_default (recoup_refresh_uuid, coin_pub, known_coin_id, coin_sig, coin_blind, amount_val, amount_frac, recoup_timestamp, rrc_serial) FROM stdin;
1	\\x204f13ea5bab8478b4e4712da71071bc78adb472093ed65ea4cea37de84781e9	4	\\xd4cd4f729312f4d830e09104443ef45760781ad50644c614a8611fa6868601f2da5fc9841f6b03593c9cd1fb6247bb6526fc46be28f946feda56b58a9462f301	\\x3349226cc077b0e053f251634e7d543c1f62ca5ce7dd622dd027c918d0fb79f5	0	10000000	1650619744000000	3
2	\\x25ab1f579e2eb9dad87fd6b1eb27572dfb9b969fd188bcd0e0d9d719a5178fcf	5	\\xf384c60f8b836fc73f540d65dba323abf4cd83fe4be11a26dc2ed8547744f7c2b7bfffcd12ddb2b834a288311024c42058f901046b1a7df40b3132b0153ad20c	\\x9bf4b4a79293d603f136c64ab94f3fd3902db66ce897b5682229a3b0248c40bf	0	10000000	1650619744000000	2
3	\\x6337d438e3c436727fe9576e8533b93413ba36476509c2d11b5a983d30f57379	6	\\x031a8252acaeec34d17aa2aed8de4c5e43404639ca83402120bf105b49f3ede742ad299d69c6dcae1ce681c9c2442e4b2d87370ad557dcd3123f04bc17bc9004	\\x5177c9e6b4ccbf5192aeb2043f04f62bc3227a04d7abe96bf372eb5e03c1ee4d	0	10000000	1650619744000000	4
4	\\xd2f0722b9792543976c158f46c87fd9ea9f1d64b9d5fc59b4c57d7a47f774277	7	\\x5d1bd3a383cd268e78568bfc20820eea926a3bbd2a8e6c6745d5c6987cafdbe3526cf3930ed2e807d054b3c9a67837458b3456ba191e87b97004f6c2daccfc00	\\xacee97de685880bf3a73a32bbaa1c892f06feb9a1a7cc285517edd9f58e2c4d4	0	10000000	1650619744000000	7
5	\\xda387d45e9e7d959464acd2ab25f5666b2c34efe4e70ca9c65bc04d7fa784c3f	8	\\x293b3414b4e79dcdbc591662f6afebf3b7dab5118cabab32fb9077b04b9384f7066a2a82cf68b31203f888d3471205614d9c1fa4d942b310394db6cd131ec00b	\\xbe06c4d2a28c3a7bdb051a772113d41add5c96651e69e3072b7baf888fe3b6d9	0	10000000	1650619744000000	6
6	\\x5c03aa02235428daf462859e8a3ca6dc17c86f73de3b902fae3dab590cbbf9dc	9	\\x72cf913ae6aac53c4b35c2dbf5a09d7ce2b4def0e63a96a0b905ed2babd0f811f1f634eae55261642b2d91ec72c7fb6bc8a2ffe291fefa9393c04a7efbad390d	\\xa4e03dd96f240363f28dce95e02eaac07cafcaca2b98383db4a6241789289e08	0	10000000	1650619744000000	9
7	\\x39b53822bc6ad24f14da1fe9902dd11693bc8b8c6a3a61e7825d0f5856375185	10	\\xe56a31d4eacd86035d110d1a600fb74c303757a27763f17fc266cdff06af821386fc52cfc15d99e803df229fe408411268b3594034a3c7a632eb752a33caf803	\\x8fe2f5807dd0e8ce7a5a750b0036e8d079001db7c47ee1e9b67bfce1f1b1a755	0	10000000	1650619744000000	5
8	\\xe492b4177d9fc9338149cb6ed522f4b62f8c2d2ad1dce406e01635e33382cf8d	11	\\x7e196fea2476408d3b9bec9d69eddab8813b8bbed916b19ac6036fe408588a48211c3f1a00cea3f49cfdcdaa178883e51124b5799e2b748426f223883d46bc06	\\x59863e2ee29494c0461b257265fe45e134015ff45880e6dff76499234d8dfda2	0	10000000	1650619744000000	8
\.


--
-- Data for Name: refresh_commitments_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_commitments_default (melt_serial_id, rc, old_coin_pub, old_coin_sig, amount_with_fee_val, amount_with_fee_frac, noreveal_index) FROM stdin;
1	\\xb687a847b887d1750a03a372bc298f3f6324e763043a2c12eb739829fe059077ff17e91b75b79aafe2b623b6c7ef5894c3a750c1d675dd715cd0ac869a59dcae	\\xa1c00c9804ebc6adf68b2d2208d43e09afa7746d32de2d3c68258ba1cd4a8e73	\\xa468ff4c4815ceaeb818129b97504bd5ef3d833a4d2521ac5fb3a2461623fa997c9a77397fdd1d7945d173bc1eb328362bab9a2d51c735f0bbb1bf4906b6f907	5	0	1
2	\\x67c8bf2ec1e8bb4d9fd3e51f35249584ffa1eefb58205a7f1d53f38ea6898a32eac37344cca8ad63f52c3b202279e2ee8685684d109e407f5049eb243c8c0c2b	\\xa1c00c9804ebc6adf68b2d2208d43e09afa7746d32de2d3c68258ba1cd4a8e73	\\x38811774fa70fab0603c21871a54139f697d57cdc0a967860b6d2bcc5fe5f3a9179191cd118da10184c160e5e17400ad255336080d9147d5a2e5f66e67ab3d04	0	79000000	1
\.


--
-- Data for Name: refresh_revealed_coins_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins_default (rrc_serial, melt_serial_id, freshcoin_index, link_sig, denominations_serial, coin_ev, h_coin_ev, ev_sig, ewv) FROM stdin;
1	1	0	\\xcbc663bdee2c98964c3b130104a406cd1ed4261501f2416561899d1059061cd9f31b8c47805c1c2c6baffc58419e68cb57e71a825deb8d5249b67ee735df450d	414	\\x00000001000001004ddba8b7f77d76b71578adc404a882d5c53e1fae293027b798b1c16e94fc1a352dc969cd8d5b5fb50bb3603f462e57fc13b9ee7bdba96f91fcedcf26560c494072a07e599bd578f814f762acaf4fb8f123e796c9c2000ca4e5d9bda87dc78906b96df5cb8dc02d649c6a72766701cf99c03be6df0f1f19358c8a54956f4b6222	\\x86aac840e704c17c953ddb2d73b2f1e80b721d6b99af225a3bdafadc97d710bdc6ae7596a76d3a7c95d65bbaff606b5a6a20222c9b3a11262b4a4893f1b22591	\\x00000001000000015bd26847889ad00f58530ad0b11fb29c12734ba85cd72ff727633afb6e5c884e5f6f8ededd315dacee334f27f51c14f964c77355100fb0679dbfef95d1fc80c824a6732cde7b0038c2202da21c5e38adf90ce9f9180f597a82f8d48e15c30964dec526447bbe952937ed1c40a92844b88929536a3fe53c57bef94a58538d59b6	\\x0000000100010000
2	1	1	\\xd0581496fb58ec81d04889c204e57ac5a7ebb2c10cbc4e4f287aac3e654aaa813a5a7a286267e1932e1c05f0a10227f4f8089e6246fba06f8b96c4849f59330c	64	\\x00000001000001006fcb85d3d337a3d9e107fc8945dc807801f00c039bfaa1d2ed4747434b45c26c79c57c5cc1b84ea9ae7ba4c12d1ed226bfae5b95c25222589927253a6e2661d76b2bfe208115599cdcd96b87b2fbd442fdb2b374e78232839a49d081461787ce382c2d6bcf8fd732391929b85834561910c1094992015ff1f62fed601233baf4	\\xd1c465acf1adea5546e8039df489112e7c91bc8a1b198d62771d33729a9b1f81721dc62d9227715879e771209380b49d4b742ebfaaab443aaa2b9de600b8e2e8	\\x0000000100000001e1880e88fba32bfe70e2b9da3b2af2d273f8e623355ed9bd54f25e684189cc1824a6672315241cfebe25f0b34afa88acb20f2e4db5b070a6f493c73266975677f0af87935f2bb0e3dbff733dd7a020ef354e45a39c2c19b41df5c4d07dfbc104e866ca405a29a8a1eb8d0514e3a53f4150a8bf26908d8bcea6f16ce59fa6eea1	\\x0000000100010000
3	1	2	\\xae223af911714d26b56990b9b2a7d6ea3d84a73f57a05c138ff53770b26692487b23007d80668a69dec79a0aaafe760924e8f439b569a2c9deb54653d066650f	64	\\x0000000100000100e5d9346797238cf7c894de1c62a9af17aee83853d7eb376ecf19cea5c5f66cd1373a79e661f0cf8765e2baf9d68c6cc060a398b1a9cee88cab649492b45c35d56305b3b3c9e3bf286bdd440c37f35e115a68a4dcfac7eb3a12723197488b229dfc910de2b0c706ce0bd91d01167912042a5fb02efe7284773f46880c5148019c	\\x3aa06d4d9a22503e357b4a3ec03d84d483c46cb1ead752907c5f27e9ae3d452f4e75d2f2a978c493f2ea08534692548d4fba109001b60bc430f23aaa00feb005	\\x0000000100000001410ba78bfa4540dc12f83cd484b82caa6daa9dfece805f99086c0edd330f495b3382857150465ca8fa28f3c78a0d65c4cbd3225a0dc6e643809b5bb58219da08601703f0f0a3f6e8986abc19931a1e382aa2ad4dd0cac7be2dabfd9e05b036681d9c1074e401216efc365428f1931fe66d4c420f5f48565c4d846924828901ef	\\x0000000100010000
4	1	3	\\xfb33c4778796cfba69aab071f76a2d478962223d5bc5f35c14e51c580056c85ad502975be7fc7de48087fe76631ac5e3f45deafe2d05691ba2a55cd974437a02	64	\\x000000010000010047de1c4978a07680c28089521847cd811a7ea669d40441c05a793024dcdf42d1f492336d86a0323035db5c8a97c118ea65642935b068cd2c477d61c0b1c07f363c77586160076e6cb665af8797bdae8a46f93b844f44afec4883e81eb6b38c047de93fc8765e64d41caeff9e617f799bf6ad77986df9092901931b5a4bcb5f7b	\\x413bcc8f5929dd2ef462dcec197105c254ae574278d93f63020c7e53423fefb3448616de39da1c07372c7d2a51b33077faf2f65b6e9ddf85b66b9bee2e3f787e	\\x00000001000000019c81780d6e70d1e933af8ab97ed4e0b4d7e0c665c5410c2d7fbf73ab8d00709801e6b95ae0f1e7f9cb55ebf5a3acc3322fd8367908bb37859774953884c41e919ee382b68702ab71cdf7de9533c372d4a0c94c37f56ae5992e681f2c96a1d19b796dbbd484e1be7eaa889afe679451baac53549fc569022b01b559325fb676ed	\\x0000000100010000
5	1	4	\\x79ad00d0a278abbd880bfd9451c011bb14df7b76afe0a607adc8e1f6df7ca43d30f0f30a75ad77c30975fb9931ed91600f5d3b2f6f86fc87679ada316c744206	64	\\x0000000100000100cd1e653cf5d51481414f19561c2994d7a21c501cd0ea69db61cc6f1b39b4f40556022f63cb7266e3fe628c74f72a05b6a23f9f384e71b2d3bec791a449c4db1a33ed2a97fd8431b3fb1bbb441ad32d761fc90c3132e38cf704fdc3a5b7e5203fbdf9f940f796bca5fedf7a39ca865cc32e91766b1bf81690d1ebac1eff6a7494	\\x0e5c027262bc7b6bf17cafc004c0d9917e90ce0ace40258e05ccb8f56d83583947727e1e1f3d7bd9d3ef055dcda9e5d226463fa16700fb8036924add89e63a5e	\\x0000000100000001b2032adf835c1641f9fcfce0e0258fdafe0136ccc8e7d846c9e84a0b6a84ebff58d53cfa03cb9f50fc299b00b622f5b327394dc8d566c5a82504041d0f1c7ca5939d1025fea029399c158f65423691b93ee1c1ee9aba274bfb3e1ffac987271cec49c040d9cfa0f8e7819c82617abfe31ab6ad99bb1f7f8c91dd3000dd042248	\\x0000000100010000
6	1	5	\\x0a89aad120309eadcda27cfc4a1e9bdb5187eb85db84792817f5ee48be3489fc404aaffcdfef270c0e137754d489a9b38da078607ebfb3d4e39e7810bb636101	64	\\x0000000100000100c48df6e850430da2f582b84ee8579a98fcd68863d0d782d9480661fb96ca5ce78c10d1daa0e985c2f69441389b665b01a19b14070afae6a7bff5b68930a2faeca44c05733ae410b5712b42edb39934604cb50425bbb811e42040474a37117aebfe8331459a50079a1a28690306d178e1965fba83a0f5eb532bd1893c49490e25	\\x4c6fc0011439a1c48c1cd45df6d96f7436d09903d70dcb0edceef3775ae5597e9297de5b410ff19179735a66eda9ea6818167a31acd4a56db26e3319c7cf9eab	\\x0000000100000001e562c5a57761edac771056085742d7ab79281b3d93d9d8d19d64d02df4d488307c69a90148bebb8c1e85c9a862435f6b3d02a86cd5d61f851812fab206ba82cee76318bc211419c0d47f8513052200a90424c4afedec12b6576cfacbbe22e6b7e1a2459b54d4f0492b5962b6335d12569dbf306640aa82fe5554f7c4586a476f	\\x0000000100010000
7	1	6	\\x5f646c98f79089ced55f8d9649047ff127ac41c50802dcd2d33721f8e67b37f2213c9f0b5057207e739097586837a52852949a58130d4388f0bde7067bcda608	64	\\x0000000100000100ef32e260e99362eac6d5d39b83ba24ed20e170274a95c921feeb5611c837caa67957e97231a6ea0601cedbd44abf92627746f4af6b46fbb801c46d62cd3288064f5dbd11ac1f983e033a45df59881d354dbce85d8f1686410827a146d2bec4f3098a8e60d666bbdf489e1d18532ea86532593dfd784acc9cb3f09eb56adc2944	\\x0c618bc337b31ff0625ba095a9d6ce9acdb7f66bafbe2714f3d233f0a160362eee5acbd90e95302409af1e31cc89374e5213fff5836df295b758d604a25e9aec	\\x000000010000000124e56b2de7b3d5a4d94571279fd92af35ac8ecc3677c27310b719d19161b26a7810a42efcc096a60e034bdd0aa352dd22699715955061a4f58a459ba95c1552b8f4121934e4c0e2fa9c9c689973e9287a7df86a521c81b45e9a10acd8f75961ac7357114df29a0ec329680d78e12bc4ae2138d9fb713dfdc52f8bd15a655ad9f	\\x0000000100010000
8	1	7	\\xa3a8f9fc417befdead4de04ec68b54ba8307ad646069dcea9f2384ff1a04d92d884d6a601fce1aff8bbd693a440b3b99f2650649cc825ce4993773e835738900	64	\\x0000000100000100455f192224854c6d1b0dad142372cdbf36ed5a1424127aa1f29ab85d8b7ec689209815245a44deae4b66d787d1093dee1fd816815c753f290537725eef54a572b9db80a2dc30e3dce1f193ceb5a4693297f033667e3ea51bc4eec7b1493c0df855f88d40ca1c5f0896b1956a550ad9ff2789d893c2d8deab8fa3b55ab4af6fad	\\x307bca201128859a75356e79e95f3943322d9f5d8c25c40090dfae7385a50021aec6c3b575edee8c8eaec917b3b7f155d812210a5d320059e8f8ead55acf033d	\\x00000001000000013624951263cc326ff332bb2802bb09a7ad1c8249114650069635868ffccc217d72ecd4aa98a45d300f2a5d757d940c75bde0e40c0e9b216fcbf3910ce8e561ae7afad2ac2c06515407e6a7076da35c6684b2899ccf5aee3de012027775e67d30a84a1433b46a2a47c5dfe149ec005628ddab0108a6438ce68c411a7e51b1fb	\\x0000000100010000
9	1	8	\\x9975ff64314fa2e6cdf228272f5b27f3c792e5c8064ba4e2b0e80e417d5f9c34e27772d1c62a7728faabde4461afac6621e30f980379a4bb06e1f6dea92af908	64	\\x00000001000001005187eca3681750a6d79ab19d62dcb3fb7d6b277f9a993993cdfecdf67a4e95aba1f77bee3454f3fa743d3db80ccb6cd25f8db7949c48c7cb0eb22243ee226177b1cb79b334af5589f1be2ce8f5f78058e5af03fcdb50cc6d9fbba613bc88f967e4c63e812775a0efef13840cc8d15d4f3c94273ff0f63fe5e87fb35523e5f9f7	\\x562017b4fc55d3ff79489e03834215fcc61e872f39944a6fae324fb40b4e05daaafcdc42fcda4dc5581ba8a6f9346b1f871097ff5979ef454ae8c72908dfafd1	\\x0000000100000001092571f57c1fa121ca49c2ae8c3e96ab890cf5d7791a70051a0f92ac52a4639617a97411bedd524eb0e6dddfd5b0f496472938e49ba3c84d23ff30023b47ca835feb0c2a7fda79e0d37cc5552c755f37eb3e8048bab2a179d73268b3df2e7fdd3cd9ede66be22b5c0bcd111b8ecd39a005ab1ddeb4500bb9c7c99f0f40119f93	\\x0000000100010000
10	1	9	\\x1b5cfc20e5d3518e050d961069207da4aa1ec0c07c219504c5fef0cbf1aa33211a135c82312e96b449463e6b2d4ecc0453ea4a2df07412a240028bbf4d960d07	411	\\x000000010000010042fa879ff86c0caf9730a298002a010b36295e6edfcb4c7d27c7969a4d515e292c9ff75ffe0bd1e276ed6da7bf579cfa9113857fc0512afba2faf9491db7ba12baea9f078bfcacd2b2ee8163c7282be450e2466cfc688424f4214c520f7df4af6ebc19ee597aee04c9d3c41d19d0b340f344b441bca1cdfefc8663b84cbd512a	\\xea19dea18ecc726c92778d19fe21edb018a177e8f4d5af7509bd7c37497f6b7099a713e0cc4ce5ecf09e8ea4b3b0a55d1e72a5e9b0a0f36dd8ab843ce3c68024	\\x0000000100000001ac65f6f1e5fec08dd05b33e58061e6a082023d0bdbe1d979461b506d5d351b5a81c38d4ef60a57c69e4c85f97fcb190e56d9f5f534e771a824e8a39ad6755afd22eef3924b2007d9b579cdc7d3c1085f77b6d9c44b17d8d6f187b56b4c01ce76afd87e15190b2479432bfb229ea2fafe6ba36a38807008e4a63f64687a5a8afa	\\x0000000100010000
11	1	10	\\xb0c228577c284f02352b7ff20d5c218f528b6bb529f4dbcb1a4591f2617f10d26193920515f31e410d381cd1491559415053c2c3d321b566c87ae32324820b08	411	\\x000000010000010066e3ef162a2687cac3422d0e3d2cf3fd32ea9588d2bbb2121568137043927af5b42ba6d2548bfb9e7f5f1020afe8234add333287e8f96c523ecdf4361e29b05987b540620f67f59245ef8a7794532b3ee2e902a07062c2e4bdf882113b8ef95b3dc21f0e2ae61259551b4834c5699d85d1a94d5734ed3b90ea07b10223fbd536	\\x1ccc669c52bfa07d12c14183babf705a30d464861cfafba4c2ae25de92a9a10bb7044271dc5ac5a2c2465e27d310c28aa48e0b578cbe0e42328f8d9e0f10b0c1	\\x0000000100000001c4030571bba094e569a7aebe848ac434b27ca2a0140275f6ada142629f5b4c9a938524c91824042ac2a7972fc198d3c941e83615c0a5bb4d1ce2e93cf5c0e08a026f5dbb7935046631fd905046d2e772aa53d55eff8849d15bea2c94a22b58bd0bb53f06fc3e580651960c07ddd73027d053a9a3342e6759ab74626253095997	\\x0000000100010000
12	1	11	\\x5c2d13f555f42a4dcd5a29f344c9c7c8bacb60c1bcb5e778e32d518977134d8ddbe6301db478b320fb6ea774cc46ec69c0b199dfabccf20965e958db96d0c30f	411	\\x00000001000001002470142259bf8c68f81529a6b8bc8eeab8543c212a4642cff793f78b0eadd28ec634b2ade02307c93661d97e3009e1629592b4656b13444025a1b14b97abab128b3c3dd606ca4c857396743c85a4067e1f77c936043f603e95540fe976d808580755022f7e25d9794ddd26230150b7663983c9f693840e405a8545ce024264cd	\\xee46cebb10c888bddfcba4d0da935677c3a99346aef23f89d722d0596690dfc093c9a821beab8a7c2ef573eb40066c2faf86cb29bacbf2fd8016344da30d0c02	\\x00000001000000010b02c01db7c6c3a6e7e19c4a01c901ab859a57d339e678ef5f334f455bd6e106254ae61830fd251093b586ab63c56f6bf0f9e4862615db226301a1f7c682bc1e2435129da41633a0ba983a4c6e21341cc8a366a4b7a8d564b667d05e639f0b8f3e303c73463c863cfad8083183075507f26abc07ab228b007f5b837e9e605910	\\x0000000100010000
13	2	0	\\xfb0957ed80ce2c57b3eb5cc4f785dc0a72390c97da0f43ac72ae34e904867003c21faa347b0170a0ef48e29888252d9ff28ef219542b711c68bbfb8de4b7dd08	411	\\x0000000100000100295da9000f668f1a20df7281f8ee89ccf7d63d9c709ecac4f3b8c8c6c88b30e26f63732a5891bf528c7f3cb3ab693014662b647c224bccdb973cae8a4e5a1f99af6b4bf05c66e3f5d0db5dc4d666e0e8e975a84bc1ab955414ca1b692be54106f5b46641217d8b6e23ad1ff8c8846169a1bd566352d2f5141dc76c057ba48d46	\\xa7c1164f0b01bce951640b8c8cf4f21f1834846cd096cc621a3de79afff389dd3d5d63a4d895528a77828c871f0d65a3e9e3438ee29b1b24b9c15afa03ac5ed3	\\x0000000100000001be4e8a0c83a29e5f296fbe7b2581409ba3ad4628b82dd9dbab36a05910a623f91a65b40ab3818d96c12485cca6300fe91764326f2b39d7456c8639e3fb9c441910f1a4aff0ce9eb18687524a5f7e8c0d39705351cfb16498a8e65d6bb5739ccb236f1330d0ad2ea651ec16cbd984db175214f7ee0b6deffa73dba5d352136048	\\x0000000100010000
14	2	1	\\x3d7e3441725cbf34d2bbf691f40d8fab670bc327f7e19f642472069b088b10b929dcf3b2f65488ba6dcc69572d1e33414a52c42d58144e9ecf6cc06304896c05	411	\\x0000000100000100d2901580e177fc2ff3d055ba09d732b9ce6119f29100077b9bf1eb0e8be3341af5a15cd67681940bc55cd8c9f5bdfe64b0001fc56257229d8526dd22196c33b89bf12317686542a8a627a41778fcf70fc1d240524b49aee921316c50b4ab2ecf2346610af68d7932adda081d0a375c9376a38820bffee9b69f620210ec4f3cd6	\\xf3919a9a0beddcd0e903d232475e6e363103595d0840b81fbefb6eae58bb0ac3a7f2dcc35f92ef3ea8a13be1bdf7b08756b8300d38d40523a24690a4f6b8f8b8	\\x0000000100000001e9c333584dccbfd26bfa5290c748e2e07e21ea27c073317845cd27d75ba2af7d8f78f57f02888807fdcdb7588fe0f4c1c528af426de6ce8c378ba3089a04276e28140fe50c15141a7d7fa5baebfdb9afb22212ac58972a218b052ae08c02e98d5b0f18e3cdc7bf0266eb7af258c2d83d7d5d9ca334508aa0d896fade9152779f	\\x0000000100010000
15	2	2	\\xc36d0cc069b17cf64ac772381943a70083d3bc8fb12cc223a7331cd3b2529dc6af4830d8909413ab2349fbad97c76e8f97b795151e87edb775eb98e44d945f08	411	\\x0000000100000100876ee172d086a73012a571b05ca73e9a46bc4ce896245676c924041d63d42637781c1afc56fdde6f60e764aece8885922a30ff23ec546b8b10364fd9a97d89993524a15e33294c49d94a34e92b2720ac6c0c79067ebe5710a0518970a3b40a40aed7445cd7dbfd12963621cee479642e13567a404824b7a1f61df226880f4e81	\\xcc81215e02d1a36b59fe3e6b97e56983b9e8a47d6f93393596b6440fa0d5e3882042c5e9d9a441b39402e12e707e44d40421680c5d96042b2b86f3b8b484415f	\\x00000001000000013602a46ea3c425dc1b222adbdb5b2d51816f7590b6072fedc5a62171e2915eb8c72ddbb4414da4c83fb28121bca3a33eaf6b0080dcc4f33cb84d54986df05c140bed16acdebfeb816fd883dfd5b564c05969992e54ad2bed109bbcca72468fd5c1d961174b01e00a302264d6c0bf3255438c1e189defd7a75ff60960d98208b2	\\x0000000100010000
16	2	3	\\xd3897c2128cf93f3534a439f3a21618ac172d895d3aa2043cb0cf0c30c0f9a9bf051dd44b2c7ac0f7058d3e57b544d3963a423935dcc5d497d992032341dc608	411	\\x00000001000001004174b54949f47b3b130dafc43d51592d35cc2dd5f1b66adc8fe6e57a712f3395dc740654bd14de5ad2aaeaa47475df912826ac0be7843ae34302113e6e11fde6038399836adf2ef163e0d579db1b4d021a39045ecb2140d7b46e2db41a2d135f1653190cc9ceacfd791e7eca872e91029958b293223a4fba758aafb581010dd5	\\xd84ba4bf1bc4a6a2de2cf37ce5a38d6200c3fb9ab0afdecbf214499fae74a28c208b5074b8f756d1cfd132a0eb80afbfd1342e29eb53ca6a1ad4f66500768870	\\x0000000100000001277c214689fa8aea60f44140790d4f03403a30a8aaf855c7fc72fad7ce5758a6fa225f9591e651f74e7561a500b47b1ae10476fc9864509d13ee4fe1a83082fe05c134675528dde14a7466ee5ec364f032088cbae0cb3578660cc32a0d40d79aab40398e30297bd1e4c36b941f0ef7313882cfdc7d39ded3a4b9d83919bc32e0	\\x0000000100010000
17	2	4	\\x5a979746d62b8fa4df0a4b5b779c68b2a9801c55915c0900462187ee32625e08c98ec9562b142c82975e9013425307b41d7d10d34f42db0ad59955bfe0d56408	411	\\x00000001000001000415fc08e4c773de65b30c8cb35d827f5324bd5543dc4628060a119c08f9e47c2f5dba7d93486711c6009ede787e82c38c32d6b40aac20d5ce50820297a1daff67310a26b45de180a60200d6333c8f828721417f1fa98cec69f9211533f3dbabdabb20e4de06e7564deab046bb6c18da5135f15f3987b5b09456cd3fa79a618f	\\x1acdc313a45fe2135dc5548e4c34b858e7c1e33fdfe76623c8693a9fa78ee8730ee915cea8f76911946d5adc1fdcad3f7994bd4997d7dcd9fd801d9320eaf4b7	\\x00000001000000017da12dd4a535302ba9591a5aef493f0512bddd0ca73917e18a39452694e5b5a2e99cdfab0cb3ff5fd14ec2def3e05ad3c8148947cb1e9cdd5b8285b6a1ecbab152483ed2f9085ea565250d6a157b94da851a53ac86ba84d62fa32c8ac6cf68652f9b50025d0d624049094465e09d940707f38450a95b704669d7042927034dee	\\x0000000100010000
18	2	5	\\x0a07e4073dfe5420dc0802cf5e1f41d94795fce438ed63f1afa01673ffaeaef30fc70f38245c73554a6591085a89c659a7f5e9f0e87233bd59e7673f90fcfe09	411	\\x000000010000010089e2f7a8ae61679827c78644de8204c8c21d4a0a2f25d075eddf2d1bb91b3c7957e610736ff91267db57769f2d8f7165c7c700c13b8e5d7e7a19902528b79bbc1b0f9ce2716b89b9b3fef96ff3f5693c83cc7771813556a4a17d24c107d480414fea6e208ad09e533ec0b384a9cbd2d088d372c9ecaa6593e007e38f22b1177e	\\x4b3a6d5ac92c46594737947e1b14368bc43c85fb39b4fc9ceb81de590c812b5438a11fa5a4d8f35854680cb6b144a4dc73c065248c327a3c8bdbff455ace3826	\\x00000001000000017a560e281a68a5479934fd336dc7f3412a593d713c49a06f198b6984ea371b6ba26c1809d3e7ecc644a653199616ad50cd207c76fcd4b3f3d41815deb89f10e6be0792dcd813ee1fd14b5dcc8fef3a8800f049e84b076f4740487351f4d3bae189e9ef0134b42d3b8d3b19683e724703e46bd04b740bf8ed405e80bab10c6e19	\\x0000000100010000
19	2	6	\\xddeb1f4115728a56bf522ec1059d778f47023c4dbf29b99a3fe31a5e4c86e1c9e562ebb91db6f150b33712ac72b9c76fb7cf0bb878914ed747cafc40238d460d	411	\\x0000000100000100aa5c5c4338db78d49e567f737d13e2b8bded3c43cb812055289626ea043d324faf2120a52aedcc5c3bf5eb84c24b52e3ff4d00575b9f17a3dc2678f665460930d623a74070e0539ff8470bff10ff5ee0154a9b6c5e01f8c06a5698eea7588f9163823fd712c21b2317763261b3483c65b3453d5fa614603e13f21ace4930a559	\\xb2cdef20b06a3fca0c84ba868862e0eb813ed45d0af745fb27c3c5cdf8a4d74cf009b76d4369a7477b217a1dc1656c8363a0bd8ca5285fcbe772b51390c377ab	\\x000000010000000188beb37449191a1df45fb7b6031ee5d08d592d0b11817cd5e4cb15a827555a6f3c5c1e7f98c488706adeea6326da782c6f7559aac92cca9147b56b8632d448f9843284d8c44ab223fa9945383dc19ac0daf597e821ae7b34e3f6df04f213fd79f0b4ede3d29800f913d382c708bf7cce65bf78b840d137546aded02b26064e87	\\x0000000100010000
20	2	7	\\xf375a04643c0e9d779429cb825c8aad30618a6dcf246de064cf5ec0f512b302eedf2c26a8b9599805b68134de172591ac3a574f12084edb7b7cd98be76b0800b	411	\\x00000001000001000625a54a589b7cdb2e975d90c7011d07d07151c800543a175163256024a9461d7098991f4493f5d442d015749510ea83293b9e1c085708b10998fc8ba972003fdf2b9df41272703bec607ea6e2dda43399111dd73f5a204f79a0d046704bc910a807fde14ad31349ece7001de8b72fb57c794045700f931537db986bb963c3fe	\\x1b645390f7b2f42d7f7cbc5af1c81bc8c734e93f79e7c43702af268b8557ee1cea2431ebf812b75b7a42b3134b52eacec3c067bef34bff6f3f823abbf59fd3d5	\\x000000010000000140c3b4d0bef4641b7e8f36fbe7cf6214be2fceeb4d3cdd5d36f1a7a9201edc526f2ff8d3ea3a6c51b9678edbbbcb1b1584aa4dcfd37992c9e33d3bcc6f4cbef8fac62ad7f7c1311326fad52921d5c5969d83245a81c97b4ce7cd74bcbeab691f8c8cd51ef00bfe9b71ce7ddd26cc84b7c5598c12e871078c9cc140d94468be08	\\x0000000100010000
21	2	8	\\xaf142fac22de71f0b27ed4054a7aa0e0c22078335abb995f3248a89a9190ae341755f29548d7b5ff9a1510689f169012e9660bccdf9cec1340cd352d33230106	411	\\x00000001000001009cd088bed2571ddd8c8cae01c1929095fefa36c8d4e5522c76a4a220eefd40139693b7a49c8639e154a7dc0d2163edd4cf4085551f9f66c1a977570382bfc38a644fa6c73f5837f387381af923805bad75b16114767a0366da1b25038ba7e3aa78c45a1d5d85c6a0312b6df9e9b21ef1285807a0cf889aee1531a78b1181318e	\\x2f48002012c355396c2b6ae68f7b6239e0938baa73e0c33b8d81e074a8d11408a46a8bcbfb5b197e06dbd3eb8c77b7d2950b0c2507cdf6c36cfd9fa249f75a4f	\\x000000010000000144d34717e34f6e8ac2d061e029d38950bb7d50ff17e1c23baaa636f40443f5bd70457b0ee22af2529d80aea0184c7010d1268e1acc78d0d7c368bc5fe6d82c00268078e0e2958c95bd9d6f0da28efe1f29c08816ad55ed7efd3b710f67b270d0491563c4c0177850e48159077d70f44ca468b02b51ac272b493797c189a4dd67	\\x0000000100010000
22	2	9	\\x30efea5abd61431a6a84dfb8b44128547a28c45c1203b5a305a045c5adcaf0f7fc76a3c8889dfd84c04a30d83a523f304ddc8e85ef7734da38b4c2fa7c61b20a	411	\\x0000000100000100b44a4c47cd8d431cc08bd8e0e4f2fbf5714fa5f3fe903a81bf701e12d48c5b2905094db1654be3766671dfd7f125e5b8b7c24f457d920ea1a942897a87a88366d0aeca51906b3ecc652657784bb959ef534fddb3420f9b807711ebc7899224339f20c0df073bdaff944996488cdab841a513b6e3f8f64eb8f9efbf640db524da	\\x22cda1269422bc0328a07d7c52e56742c0d217baf332ca23b4751c983f358df12877fba0a0b5628379fee0ec21efb706db143fd8b9f6a865da92281786d0fe73	\\x00000001000000017cdb244ef1a1abfe9898d858f479aabef587d3217b73c9f0f4fa5e904fbd6ee1d97d9759cbf7d540cd2beec88ee3dc2aba42e0add523f539bf4116eae309b2d544968fd416bad0cbaaaf5fc6a5612d3155e1b5973c2ad1da122383f39b25ac51076c8b8f520192b725ccbe17e9880c136487b6a3f7153285138138297d08a5ff	\\x0000000100010000
23	2	10	\\xc49f6f766c4949dec5e9068de693b64fe4c8f348187ba5811d25ff28b389b027daba93ff9f2d470eb3596e4e21e8cd050ab0ecc3dda1425c92bb09e1567b2d05	411	\\x00000001000001009417e7eaa206820eafc66aa23e6055e6e7897bcce189d8bb1364c77eb83fc54b3402aafc856232fabc46c07b1b3b81fef9b61343aad558b0b199857f4130bb0c81bf5f410508b90632f8ea026f69b1bda24056c9a28b9633eafe3712a7004ed1576f7982070e21d1df8c4bea78d3d04296b483fed4a19079a8a0ca9ad21c1b46	\\xcacaeb7fa7496ea68e470e22faa9c0072253b355a972cbc3f0584d15147c729e8081083ccb74ec0af9ea62d1560c31d8afec9765ddb0f90dd897500474311868	\\x0000000100000001acd5d1ffc2d84d915d73a20c7053a6828ffa46aca759a10cda90088b9b785722c99259e710b1844bdd8b818bca3322fb8b3236fbb428e6ee3bffe523a8c025489390920b1de190de7975808fcdca625c580265a523e1f10c9ce0776e40842155d6b4da20790c3421617e98c8f7784d889f2b1a680b60f7b2de422e83c67d575c	\\x0000000100010000
24	2	11	\\x4865183fc7b705a91b1d3edd673c895e85f0d67901a7f926b0ba6f99dec3510e249cbdf1449e5c700abc668f254aae49ee2577d73f5bdfa383391774adf6f507	411	\\x00000001000001006304ee1dfeb1393f21c03e7213e76ea151275d307ee8dcf61fe6688cc3b4da2f36bc3c0a3ca0ea954665888be79e5f9bd8f6c33d3d46f8d019b2d7b093c666bdc3135ca82424bf25fbe4e1049a59ad661e24426d7ee4715edbccb4c3190bf59b1734508622febba4cb7e8a837ef9277fe5a61592294cbb94ac5bf3ef997d0708	\\xe70a1ea9cc0f48a41f792f46052f99c59b5d278519dc6874ff4c555769c0ba7464c532885e93516192b375608e736b04a330a991d4c97bcf4b537bcaef92411e	\\x000000010000000109f0032a141c3f4a1c43204da9f9d0a133d52c30fbef26a1e5da90b291264a3722402fd136b3b5104349c4c15a989b32a70046b9694122af8401141158757a8670b4d5d40b0f3b597623fc542478a39bd11192d4616cb353562017e99ab426e67c52cb5c6694f38e7fa1f3333f314ebcd09c52a07b3d638ee45237b2db060523	\\x0000000100010000
25	2	12	\\xcf9a6d80b6761e5e01d81b823bebea74f152dca85230e0f908a4e7db153012596274b36efa6f9305f766ef12383ecb2708fb0489db0abcf0ca3996fa334b2e01	411	\\x00000001000001005607a8d6e8b553bc959b64ffed137e3ac1b26e2e4868e62ef4fde5a68d32c891f23db655faf2ad606aa49a203a3915e4cc5f69db9741b7cab3965618837ad4c8b699850f3c163fa3e208441b7f0e83a22ea44c767df65e0952905056a95411cfc017c690315594bb18d26867971c32be7f48420f973ede3f649a2a73d79b755d	\\x004968e4eab332cb6134baaa26856ed2468b8eb73ac6f1c8730e2a7ab57471fb284c9a0b4ac07d6d3d9324c0cbf25f5fa73b885828aa317a893358fa18021b79	\\x000000010000000141be627ced2e55711af636ab212034f20d40015ac25d32c898c25813edf7b495fbaa3de7783240a7cb0bde294671a15cc9ebfd10ad9a73cef830468d34ba09082d6023b27cf1fc9dfd2624285e59a9237c4b4151d49eea7a35aeb93db689145b6cfc83ac5f3d13a6b024a9586ca24359b319ca75e26e88ef12e8afac29229ccb	\\x0000000100010000
26	2	13	\\x18c1ae726e4e50cabd59291520b2a668938ab2e49ea86ec79b35bd8b76e74221a7cfc33017a44a554f9065648672e149e6a6e40078984349702aeaaaff9bef0a	411	\\x0000000100000100e3e3d823d41b393a18b996a38cdc6e29f6cfb40926858e781f1524acea0ccd663caf47e3cb74c892bfd8b40e19c2c0756df6ce2e8b509ba338fdbcf4f85bf34d31a54945501230e2d6cd2d487fdc23037265871fb67c3de6e19a91929fdc413aab6fe4fede1e0ba27ceb82d03626ff616b63c6b785dbf1f140bfbfe0dadb0df8	\\xc91b65283664be13ffc956f795a46fe430d84eb7783f64311b72b75a6a3d8c4687f5e88ec21095b8d40c1e67d5c7cb4e3333077c8a4ae324cc41a3ddf8bbd1a1	\\x000000010000000142b86f54dbe249a5e1f74fe124e82336b69e67ae25b4cd4b88e0c36225a90b7e408fd678c84a8961d955fb2a0d89c98817fa9b94dd37615c9029c909b3352ee346c2645a00a630330334bb1d7fe88ac9699931b960d3a352c7a2ea5e6797e72be48093571476b6ad4deb3bd6e299602b813975eb25d8018f5fa57583f0ebac25	\\x0000000100010000
27	2	14	\\x6b118e2e7dc17873ef50dcf1be0374834db2f597490e5b10de6ce769135d41ce0ed950f5c425a2ecb22af095b34d6e721f3d0da65e695100365fa1f61370720a	411	\\x00000001000001008390b30f1867ef28b9473475cdb0b46576141c1715f964cf44a8360daab485b92c4138f6433160a913f63937e6322822a0f8e1147c7ae0a28b1247066e42cbf022b825d8c08e1b05282005d4f5c5a7413f5bb6770f3742ea0846423f9432f1e4dda4b11fb07f77156e334d176b6a5c1667ade83e4ed963ce407668861d0725c3	\\xd449cdc524eab57dc763192df047067549f7dfa2db29562b5170fa0d5742dea0be62c50f1a7ab58e5c2b8c413a22ca68177a89dca3d248a908cfe4be62bbc426	\\x00000001000000014f70c173ea3f3a74a079de9bf4e3549bcad24ef9b025d3378efc3ce434a460d29262a8ccf221544e821c6f12b85ec80e3cc2b2424c7578b6fb0972e8f048ccf31973a23172dd0a7bb21eca9bb340a45f3403494e949454150dc9298e42e1961e70982669f55e6e8e1907d52ce17d6b3915f2874ae99ab55af7ebf7fb2413460e	\\x0000000100010000
28	2	15	\\x8d52fcab2115fbc7a434f9221d7f80a64c550ac70281d89005f31914be95806982a4225c48832aa487a4dc01fa55fda621915c2c8975afb6331c74eddbed2702	411	\\x000000010000010041de7313cf1fd64bbba689b80a7f459703cf785be8ca2acbd0281bbdd1926412638eb8cb81a671bee6dc6ce67b1395d4d6d4dffb8bdf526c34cf37f0979f98b59fce1e2352bd1c574c82c1e13f565e736bc9c2dedc8d06689e220aec878d1783b7f4c491e6256f8152475828e6c1adabd5bb6886fa8c8c9a8e71b395983d815f	\\x491e2614414482e9b821fd10b0558f2d06b8ad4edb258af10be1a79cbaeeaa20bf37c5083a19e6e1f7fcfeac53a9fa07ead7d47b6dab32da1ee4dc0155a3a3e7	\\x0000000100000001eb6a079bc12b83736542c5387d9f4cd2e0affb2938e3468f4aaf32785f140f334f36ef586a1cb5cbd35166550f0983b9af6d824b87829007c30b68fdc699bfa87870f3125e2cf69687d1a5e104d2850e22ee11e8dca6cdbb5d7a2071df5b2652feee6e87454e29006c60014fc2d8812615b849eb644f392ab6d7674a8009d498	\\x0000000100010000
29	2	16	\\xb4cc0cafe75e9cb1a6be1088800f5b864e5a021e57cb74e0007d79fc095e766002ea0bd79d003864fc98b6ea3b7adee9d9aa206817102e8eb4fbf857c62e2c06	411	\\x0000000100000100ad20de01b98618ac3c51c3478c8462be12a01e3bf05e36fb9bfbcec56063344f1861757aa728c329e885ccc86dd645e23abdd21b02cca21c3f44921fbbdcd3b1aa1cc5cc64d9f2d5679ff744edce16396641622822a191b24c4614ef7d2df19d0e3e44661a554914f37bd2ece035c9b5271964c0cff58828d3483e540fb0ebd1	\\x381abde69d7a8193a5e6409f68d9ddef494f2b44ba3e385d2d31e18f4379c8f8760f9d68d1a7e37e073a8ba5d9dcdc2fe5f4d72815fed9550366150f9a6f7f4d	\\x0000000100000001144faaf0beb5b985b17444c206cd22c7ffcb022909fe6c47b13649ddd9f317aa4571903c377188c0daf87ae46d2771332c23eeb8bd70df66ece4f80a62c0503a06b27a3d8acb3c2cda9ef0aaadcb3c96154e538988ad803b89c07b8c2fe863326c03f2727bbf6ce4aeeb227881e8b816d7516d9aa7d913e949d0e2aa79cafc84	\\x0000000100010000
30	2	17	\\x5acd8f18e7a054af1697600fe899baa67f09293cecf9a3edd1172e55d5fbc8710be01035020e68e6ffd88ec9e1228d774c1086ba74ee84fbd5c3e28b6dc6a10a	411	\\x00000001000001008ee51b47eb89c32c09348cfbd6e0a4c526acf87372ab449ce40ac56446e22dbfd0d112a56286a14e83e60588fab56cd48a893f3da27527f78dd47aa704c5794e021be246f5246a4d8828d1dc1cd2fcc0c876434db25f5edf5129eb997c028e735640e2a896a3b76874be37b92f8ea031c8a512dec3c89eb7ef49306c873e2902	\\xfb976d65da936ff61af1c88ce105e238fa9924fdbfaeb6a758d1b25bb9aef1c4a3fe5e59065e8d7de02e28c6e2499a9bfb44fb6c7d3f093d572379d1feb57001	\\x0000000100000001a147d9bb61256feea84232aa1a528f3737a056568899db043e2bb2014a275f22fb56abe1662ea98a4436c4fde248c69bbcfd9ceba27bf41e526885f2217bf3a99eb57d48144c6be6b05e96b311b1a8d60dc1a57de24a72e4d88ead2ff22dedc7b542c2a03080e54fb747b5c4e4f4c9364e9aace7b49e6555d87e3caecff938ca	\\x0000000100010000
31	2	18	\\xda3ce2490a5cbeef40624eb0bd1909e89ac608505e60814f13439982c5ee6d2580c256e20f7121d8e6c737e7efcf0a90c6ede1e39176b64cccff5bec29fcab00	411	\\x00000001000001004f75b31d1bef3b24cc0673602387d00bf9dd26779062018c3e47444e5932dd7b4c71c73f9e0ca88735d176c11595799af45ada96f177da92cf25e6fe7b05a825fe45ecd54e618ad642c73fdbf9e5c35d96968fd3d1478bd4f7e890fa7e44edbe2df588dfe687f8c2ab5c3622ab59d3fb6f442b481778958435b44de6ca92908d	\\xf9d306e605e270b4da2aae4c855b314f1e8e8e203285d9482828da5bd6906f416ea00d7bf7f821851fd6b513f44fc17436aa2e9a3c2b70406f5d33e70e3967a1	\\x00000001000000012af3f7037b88b10b56c29a44d3ecce52a258e6327d1ec0cee923249ecc5986a579f1c0452a9ef1dbd82d567bc5c1a2eff98707ab142a4b1f8956faffb6aa64b900a8db5ee8899ee29ffa4310d4d78c6c0c0a15b760380e79d4e10077ed1d7c7790b59eb41cb9304f30200cb2594efcce93cefdd0e74e74bf5f962df25e8c353a	\\x0000000100010000
32	2	19	\\x41496fd5150442e53ecc10e036e6f6636f1e8fa5a97cd411aa8b0609e40e676993a0bb86d62a9fa66b84048259cf25fba84c3ec7233885081d9f39cfc6c44b00	411	\\x000000010000010033a9fb3bbe55bff3a082cf620f48927967223f2118e198ab04705041f879dddd89784e368cfc7350aef9633365745e3dc9abba009b319ae6f58a9537b2604e229e20feee1b277d2704366ce49ac19e28bf2d11ed740ad043fe952806a985407b6862fee55b074fb4c32fd66d7bfe515f2d71b5b098c349dc0cdd0d333edfa960	\\xecbf106170a5e6ab9060fcee3549e27f7bb228c82f441da27443bfb290e445f457263db64e2935b082c9561d7cc408b75ceb4d29570402117d32f7981a7b7029	\\x0000000100000001d5c45b6891f78c6cd755b95a258b3f4b1978226c1adf7d958add63738cb515810bce163ac2291c06724f2f1a87ea9f50eec74937f6e06d992d3e519ecd4b572d54895a4a900a80ede9355d245e4ebe8c6435dfe3450af6843e49693329d0f24b24f3656bd7bbf5263de44301e34e2c87bdf667dc54403b86fd265155b5a7cf24	\\x0000000100010000
33	2	20	\\xee13699fc55a2e8955f3c699b55076d0c85a6f9d0f8c1fa606deb3a4cb6599fc08c4aa6c09ffca3f5cc5063462defb5febde3c39d8676c7eb1880c14177b2c0d	411	\\x00000001000001004d688fbda9ea237d92bd2d2de96f242391d71c7f9e044a50c34c08de9f22eb49f3e086e629fae925a409bb47a31a0a5fb3ad773d2912aa7e434d7ff39468a6cc91705c9860d4d1144301e1be874319fad38179bb9d47d15871b25de0ee747b546787208e3800aa3c1e3201926f667dcbf1c570889cd1638f58cbfd0e9bc92254	\\x29bee055a6c3ad1c446b741a2b077f702237b6ed15f67a71eae2e69b5ef6741897483a56d214efceb3826e68785693f4df944abec04509b8d1c8d88b6559aaf4	\\x0000000100000001707ddf73f4a5023c82b212a831816da3893f52f2c8f3404587534e95ce624c819268f14635838eabe0e5870532c7cf40c69c58c2c410bd5bcd5e91739b5e1c4fb91a0fdd60f1ceff1a9a4fe96cdc98a92779a039148f066a8c90eb7b2b121492584c038e892e7f24eaae00d900903bacdccfcbee32ee6fc500fc33bde48dd7c9	\\x0000000100010000
34	2	21	\\x472990db8ae1209757c830bcc9dc8839818ef4978aab30d98b110e65fc62f31dfabec22609544879295cf4637de4ce5c3e251c72b07bff3d359f552554a61b0a	411	\\x000000010000010002b6986280cf4f1cee57fd70dbb03bd72db561cc2e448d6a7561a03bd0c0438982b3ec96ca8483496bd9a205a2d607b643173c65d077df49668ed695b4a55732539d6d683fce90963ba231895cedba099bb239d1d92525c0aee6c123fbc15494c624561661f0df9d56a448e188ab6745fc598c25b40e38bfce1a90e3fcbc424d	\\xf7314a6976adbfda15e2bce020e49fe848219a58dbe791bb103616fd6f28eaeebc2fe2e4c31c9c8406e22701021cdb68d8b0d6d5ef76ad84637dd515d99a25a4	\\x0000000100000001e858e12b9b12c49956a536ad2e239ba181340fcd77cf222f7ca73707498ad9e22b252f09428387a0fd794fade0ad73888a0434bba16f48c74559e1dce1e463712e869a889dfc607f4f3220f8356362586fb1341465932de9271963b513914a28145c6bb45335c09cc81c2a904bf7c087b19e895928a283885941ce412c329e18	\\x0000000100010000
35	2	22	\\x0c3552b111b166d27690af8105bfd276a1af4a90cd3d077f1e6c9df319f81903b4e58151d56f9f1d1b3a7c5b3c326e16b4e6f2f2459304325e502e83d1f19b03	411	\\x000000010000010038ba81950de6b981fd2b486ade9e62ba73426f52d71bf1d78bb5742946d64447b7c3e564f61da8f9dcd6a02f15a00221dc57b36c5c6f6d630b865cfa92eb5684aa213c92f02553762910579640afc511dcd75061c9c90ab73c40a2f54c5a8e97e2e6660909fe404b9cb25702501a6c97cac8599870eeaf88168fcf99dde04601	\\xd04311a1587165cb6813960ac1a1a9eb45c5ed76dfae7f1ae680196b5822799eec5270a4cdc9cd727ca83364120c8bb3907985320f99d90cec7073082a0c8457	\\x0000000100000001ef78a7b5bfa104b970f113eda3043b9b5444b1c3bddad9ad95bb07b7a51841dce6683ea76dce977495130f1f86692e4fd7c2c2d4df68c4ad36cb72ea09019d9d99215badc8530752704603b301410b21d3eb1eeea6de5d5e73055aa4dc5dbd4c6f186c061151b94d2d8cde7fd766fececc6c4368fec4bdd4a2aaea8eb08abc10	\\x0000000100010000
36	2	23	\\x083116d07cf56acefce677fc364394853d5a3245c4b2c3122320c8094a6b06832782f262e5e4b9fd09a831b1aad7e835fcf6eadd0ff0ef0cbec07e6e84966d07	411	\\x000000010000010013ba5a90f31367e170e66f76c849fd4876f9015fe4c3a7c14472cb4303fdf36eb1a0c30508be10c9aec53d3f5e6cbcf4574261f46df023c07370a27f2edecdc0a8935d8425459124f9ff438117ada1b9b6e008b2fbe5f30ebdbb74a942ffacb142f2aa541ebf623021e07a24a82051b15c443b091646c12240bfa3973bedb318	\\x5a767c23ce290fcfd6138175a54606f88524c75776c60db86045e03410f17d0659ca6e1b62556ff93df5a2eb4e51378bdb3cc81d48f8edfdbc6f961100331d22	\\x00000001000000012ac2015e647db52b3be9c1b5c78c136553720416b8b97aa69bf618f49d0f8c281140d221df777690da0c293e1d785cc06a07ad16ee5d08bc1fc0dbed21f8ce96c35fb873030d4582c2badd2601b62e861e0d5cae28f15f5ecdebbeee9456858968cfcccb0a706d337df253bdf6bcaad44caba53794cc709d9b6a263aede1faec	\\x0000000100010000
37	2	24	\\xc8af1edd0336a3200fa9599423ba391450f1f91cb001c74ebf5dfe0e5a2ba5dda3b10660ea0d4511b68286f2a9b195fa527a608104be609ad3df44abff00cf0a	411	\\x000000010000010041253c509fc7854c802a1784d2f51306abba46220ab0ddee6b828d60c0b782b37b6e94ccb79fd07b23ea79faf97d0c6e233ee016b66cd5e52fe8446dfbb412f2f9b2410eb0a019b5e57129b820382f44cf3a3cb5296edc7fb399a96d7fff2f86ba2ecce8dde7b66e8cd5ed36674533da3c1b44cabf1fb5c680d9b85a97dbac8b	\\x7b86a835a81c233f589e1c49f4f2c8c2dbaab71bb5b429feaf54a2df96f48d8d4ac5458adc056c71738029b24ebb5cba9fad375ca40c2849eb3db6248091537c	\\x000000010000000165fabecd5a521b58bf64eae1793f6d9ef23a3307f22892bfeaf90da091ae1efbd13554c601a6b1ee5f8e6d8a5652d38c3b7dabedbc694fb3354168dc4ede9b99291d45770a0f66c7dd3c2d7369cd77f0a7980f9865f7c4377f1f09abafeea40fb44930ba9b1855899cda0d617748eecf6ba5cb00001af1c3ce073e4ab2abebed	\\x0000000100010000
38	2	25	\\xf45c8d23089f9385a5c9b3c8475f49b136154127ad5f707d34058527e3d869e0427f5b85125ad439610f7ea4c620739d1ccff1d86d02cdbe9b5e23d606bdad02	411	\\x00000001000001002adf2dd7d21fa4fb718a99d033be38e7e3807da400635e99b4d51cc84bcfd5e130ea57a4a5a80cd82ef26ae5ef7209b68cacdffe1fd46015963791e8bc830ed0ccb60d5ee48c03e06e23555cd5ef95dfad7bfe0b9daa4673bd6b86e14b042c3f2390ab7b363d982fda9cf23365d84ab6ffc4168d439948e5ff85125420f41715	\\xa7dc739ee042050210984dcd9f6fd92ec52c179376de5e001c1c287a3e2d121b1e3ef92f2d9b4a57488c8bc9e1564021fe2f5ea8e2f6f8abe8813d60d28c9c44	\\x0000000100000001d87fb5e1fe34b9890937401e5bff1adf07559e1da83aafedddab299b85501bded50d62032b73fd9112e7ebf211f72e4411405b0e95085dfcf245cc143703296da0af9e15e8b9cfb5b644cdfb099f8e2fff9b2c068b98641ae33860139e538de0475ccc8139d268bf91fe38f173530cb421ed360e0cc78c40a7e388a23c0f22dd	\\x0000000100010000
39	2	26	\\xb0f32b36d0992dea273d9370eb693e5545a63c7aa0ab013cae8f86eba1c3776330298fac5a12c78acc405aeb3ba3663f5371b910bc5f275128398e354d644909	411	\\x00000001000001000c584c8a408e6179c9f3b664d8845f7212bb254d20733b5db4b608153358fa56203824e97a852e63cfa2c9c556a12aa45aee65922f70822f67c505205b6fcdd9ddef0a38dd50bf9910c130b3a7e849836910b6137094edbbb158302d50909982e1b0076bf6ec61c24574f1b7ac000d42302f62fae94b7c2439ef1174c60fadc8	\\xbbd5318ac88b51d043a3d37c249bdf7895318ad6d0d9384c07c9e1e5c7039292f724ad932e6481acf43065939147454fe03c8ad8793c35f01a803924cf0b2885	\\x00000001000000018187f1da84c689c822b313a076be4732ef9a404b83361d2fe7b3db7eb405c25241c8889b67a169b3bee7fdf9cbef236013d7a653eb413706b4774fb4af70f02b60d54ffae1293fb86f115c7f5aef331212a9a530f4325724b158330eab1135f219a356406b4cdd3fd56164204f68132e613d06c5e4d4d5a73529a4e2d28cc901	\\x0000000100010000
40	2	27	\\xe14a8a960e1da8b727f076356b2cc6a74e12aa81505ba096c9330db10c1ac4aceedeaa0600dbe627fe629db77c708228e5a4ba105b31075739d87334a2d1d008	411	\\x0000000100000100c483a4a01cf5559857bbc138e245fe0f47c968a8021cec5d81d1d8384b89222ac50ec0b0162b02764537f8d785e36a9a4453df7cdca483a7560726e61faa133b4dff9791822f763b0fd84be9f43dceadbd97070ffd1f01839d0176d1af96d0ffa904aff5a2ffc54800365af92337df78ac8454570c6721bda7593630d9b1fd69	\\x2ba44f4312f00cb5ece43aec9f21461259677ee228ad0f3dd7e6d2b57cbc734d7cb6d7a521b3b75cddcfddd7c0e7860dcb6c9915e2139b73bdf8d6e8605d9987	\\x00000001000000014a8545901da575ed266dfdf3bdc92f781bc9e2abdc0d1e0350a18b429b96598e2411dddba7a51159b800c26ddcb2f861bff085dfd92e1b3badd24f62f30b7c8ec1bce138d4b9c71e372ceaebc663ed800797a96c3b08e677913361955fa44a7f9761b50e9ecaaeee53186f45f3cb466466e58fe3ef14d542dc152bd4a5d8c569	\\x0000000100010000
41	2	28	\\xc4c882e12c4457dbe58392b2a4c3554a927df28b36c668175666f841a93212da7b3b5cbcb52f7f15dc156777da863fa5fb7239cf6f12425f79837da8dd21b30f	411	\\x0000000100000100c994eda002831655545b82973cf347f29823f54b11ae8cd93b7148397039016f79703c139b52a4515505901823625ff5a805539303d438e2e215866cd8ca396b49b8df7eed8f23962381eeb7fe5d6066a7297796a758849190e3735e88b0fbd34ac6199923402f4d1ace396570284351f7e258c36a99e86962cc4e70382dfcc3	\\xd546cda52dc210163d8e0eaab87036d9f871b824e90c690f13726dce037ce8e185ed1306d1759acb69c44f164809f5dbe22363ca0c92f9e3539ef817ec906389	\\x0000000100000001af0978d640e072f45f541095cd40ecf1f8f3080b5980428c578f9400bb636d1c3df82a54c0ed9d29e71d3f280b3c2acaa2f1063616260e44af4e8807a7a21ab33116c6b2eb79e67f3f5439bf3581e022e1de383bffd70701b8a4be4d01ac5be5c2ce2dcfe29cc14860cf2c910517bf3e5d1722e69b53ac064d761edd3877b8b8	\\x0000000100010000
42	2	29	\\x7517d8b577d6b15cb1e78a4617dcae171fc7f27042a9269c75695aa9f68a8746aead2c956e69b4602fc15fbb943c9ee3f212c8be53b1260bafd64b60702d9f06	411	\\x00000001000001004d5e465029e541516ac3557db2afe2024b9a1704653c30fe63cdc48018d74dd49a2bfe786ca7eaebe05f392efcb01b2c4239df8bf6a6564e3f1fe15c9df6472e7888125c8e341bde03281489fb4880907f4827bb47f61abe446156dc41829c262f551832fd794643c08e614367554db63326a77c6ede7db923f70c4f3401cad5	\\xda56d267ac99fbe6c1202a89faaabfcaf467be98278a454a7b5dd9fe346a6a6859aa2282427a7edae12e91ea1bdfad9f96f0dd4c6e00307e27fa7c295c4afd43	\\x0000000100000001c62e1dbdfc79cbd37786bea29230e92fc8e7705616126af9ab9d1fedec4ea32dfe031875f80136e6032d0f6c3f7234d890af22afd807969c0942b47bff3721337af6e90779809ed9d7319ed614b02b332c2ba81d4338e55f12578b9bd1756e8d59af1ba5dd3ac2e89ac4d411492f102a171881feba44890aa70b4e0fd5595071	\\x0000000100010000
43	2	30	\\xb942e17baeaecbda85e008d444c2e05c3ce756be0bc3bf35cac69d23ac387633942d353987754c008c6e68afc52a27e54f552c053c25bf004e7520d0fb943107	411	\\x0000000100000100dea740a35d931a923796893ee5484ee72f8d25fb3dfe1216fd13196f74626210a89e15097242fffd0d7722b9600e4fcc153918f311dc2393eea27047e66b4fef6bd27d3c6ad92e187c3491236215bb0d001e87659f28d2f8c8c0d057b98c98397dc1430a1f227941be13809c104b581a887621f61fd334cdcce6008e1305c77c	\\xfc55116c2ad93dd63bb99007d6f01eb9bade09f87c6baf64aaea12983878efde677bfdec73b2c650b8bdfa75bd38148cc4a76031bada4cfd1a809baa20e6fdf7	\\x00000001000000014ad9636dc3acd865432acb6e7362472e2dad48d331e1b74b04ab3a7a932b3e49358642e7d3d420ca6431eefaa1bfd61aeae71df80f8a96e3dfc2fff36b612d621cb485a0e75dc12b36bea6022e82f4b0511d11578e8c3aaafa7923a4391ac823ecd0244701bad2d58e4253ab5fa1ff18a7682f7ae77dc3902ffb3ecc9eb0580b	\\x0000000100010000
44	2	31	\\xfe7dffdd112801be7eb4c99a130d0f79c1330829860e3b726db60b828fe7da080725a490ba76005d9234dc536b112db4170b318e0bc30022295b735d54ec1f05	411	\\x000000010000010075b15de92ab931e3cfc11f769fb07ef76070f5f88ba28959ddf78c19f2f6d6c1b02a86115cf4d42050e52f1afa93593b07c573942f0bfcd7cfa548f080f6f4113b4d08643c1704021748d8f93497d85e733e4d5b95a33778ff077b6b0a92954b72acbaebd13baa8e5767d859a11267b70ca2b5e9a192eba48179ab1329b7dada	\\x41b4359a01d233acf01a7d16aa3835f4ef87d8f8f412441e6cb02596b67c787873d00de717b4f68410f7612c23eb9919a46420c815c67658d469a65f769e6278	\\x0000000100000001e400ec86cc51fe9f4716285d2ab75b593ac54ed6c8c7683952b4e27e02b453f0db09e2a39a087591e7b1d1b22a658746d5bbabd2e6b49fdfa4c6a165e28028956e733b897f8df930a2a90ccf62ff3dde54b53af36997ca89010526caf6d4980007060bf03e932e7286b62dd1b96ca4cf18a1caf827d6433a4e97ba234f7ec822	\\x0000000100010000
45	2	32	\\x7fa3985aefbf2aa780a4558b8a88c6fcd7d05d1633a926480ded8d253fe6e2141bb57ff0eb5f308cbd94fb6ce8f6d3cd8333e741d09fb8e7f822030994c47303	411	\\x00000001000001001b0d228d23865f61594e6ddb261f70b0b267a3ea3f74d048809dd85f5a4d3d38872a9452bab6e6da9f8c887960a5389c9ada4825d26435194f2fcf55aa6d9aa52197aad591a875ed840dc1561b1c343c3045d84f34e3624d528f4f39203bd3f2dc011734dc9c60e68607d86a0fbe171686b46121b90a6ab3491117cbe9c5fca7	\\x12f628aba7f8644f3ffc8f63b523e48d6834597a2174372bb1bb22fb731a29108e567cadb018043b91e988446cee934325af1f1dc2de67a0e52535606108b366	\\x000000010000000185d49e45246281b93320577c5df0b928d9f9875f510176a72cecabdbf0578e5e1798caee30d9b4341669e1aa1af1ca22a00112491b2705cf41b8ec829d3234b53d6f00707105ee6ce204b91f2484f96c5551223259520507d1751ecd0309a80709f22bcb3f0c0d71a26485391be44b425de9bede129a2dc3add4a66fba6e7d50	\\x0000000100010000
46	2	33	\\x588405b27a8616ddee679ffe61afa183bbf0a5ab5e17e02a3286f185168738ac47ebd840006d507f11ae2fffd5d41a1de0afcedfac63fb5991d1a23c814a0807	411	\\x0000000100000100c1ea149c04a43930427a523cc8c96035a44c73d005f953729a201e81cfb7068a8d2243f503d054ed8ae4a89be7ecb8521d90cdc26c8dd0ab62f1574e4139889e6ceb37c98e73756f317468ae8a964f6febcf462e62dbf67ffc048c0f7a6b089762c1639aca12074b4774dd48732a5864a059a1d84e5dd981d89568182bc9558a	\\xfd2a1bd290f7ef4a71f5a7b94b913963859c98b0811d14a7f22338362ce9e0e10296954ea2524406832a76a747440579d8810870f847c224ce69836f982fcfa2	\\x0000000100000001225d7398d39f0f6733ac4ec3ea45cd756046dfae145741a3ff62548e4680abf6b8be14cea590e19352a60a3829e4d10cfa72aa1e6b4590777f31128d3787784a8aef5a65e793e66e352210134068ab90e3b433eb64136ef9da5d300f19780ae651bd4624ca129f601fe296eebd994b63966a29807049695692485eab012032de	\\x0000000100010000
47	2	34	\\xffa9a651f41aac848dece1cdd2f6dd796fb418b066c9cdd9d32e66367c9706e99f2c5239a09ffdad328a669048ccf9664186d457eca978b5b66250e73d65f40d	411	\\x0000000100000100610c4fd6fa4c77e7575916a3a7eaf3504f63649dc2c79a09912ebc2d2b7fb907b20f945609a92309a20c94eaf00d3abd3a1e9b78c4ea4642d272f1cf8e3e52d89dd9931d723c5533c2803b850b057dfd707e321db18a4064a4a05154aa64004bc271e0eb53375a8edc5e6444550e1074816410058d56368747cbdf588219cc93	\\x5bfbef15a1cbe332de678de5e7521f74cf27d13edf96e8b7346984dc3e44cac9a22dcea7a1733883ed8e20d5be0bb7e468e6759913d38e33ee019e0d5c374067	\\x0000000100000001c006ee9ba332db1e1bca0af4b138e04115ff7c134ba578edcbd04800e4efd13e647298697bf0c37bb7f763116f9c0a3101a74e7259ddf1557fdb1b6f982c98e8cbe52d4f49280b0f4b7ca29826f7989835b8bbc5e06f5886a9316f89072afa34a83ca6aa87a56624add10011e60bdf452eaf104e35e6157b16f4903772abfc65	\\x0000000100010000
48	2	35	\\xc63a5ebcf5a6d784f2d314bdf701154db7b6a759ef77c529f7757ccd84d6d425e34274514b9e2416d04fb91a21254623007d5ce08f539498e7f2f84fc648b106	411	\\x00000001000001004096b1551d3eb7725192de5c976a4cc0211d39803ec1a59c9e40ff8c936317be89b5ef250b02d6e7e76c85d0ab508d36789fcb556cf6efafe9c50742d332c573a0443d2f2a51375848c86bbf34ad271a5c8ada8f96a0881c4cfde204a62d3010d9d0741160612ca0b7342d39dcafeada5e92ff67f7f5ad07234b1a72bf999670	\\x90207135da714e01927aeb758989dcd038b8bc4670745b66bbb58ff89d977c3ec5842e3f2923eb310f26ffd6de0ccd14149f1aa4904682e419bb5e733aecd8b1	\\x0000000100000001add0baa290495f928b22dc00ffe9bf16c37298d287c2d37b88499a2abbc997391bb4e5909252b26042ae94d1d6e521f84ac9b7cc1fc6abd1870d84fd6e4f1d84d5926d1dc6bba059c0e3ae26bb7eadd4451c323cef247b436fa6f42d2fbe254fbdb23ec45b8665e170325f2ce921f6a7d9c8f3d16ee26780d623c95d2bb4febb	\\x0000000100010000
49	2	36	\\xebc7b85fc795ccdc8e2b0eeb7c8a246671300136965126272b785a949e8628c60fe0557fbb181d90be31f2a839134babd8e72f27afe5092aa2512268f89a510b	411	\\x00000001000001004c8b36f87bc63d2949200d1f41bfd9f65e5d661ef505f3410c9e18d1ac7d9367cef5f6e718116d4e8eb8494924bb1a0ec83e761b9440063224e24d6c9e577821d058ca8372336e54797e854c81bc59ff23e712797f4b75496aaee9be160afa85d0915f5d01323754badfa9162d7be851aaa814df59250d3f73f5ebc7acd75e3b	\\xff5498c6c6b0982008298413c0294c798a82fc5c106e8f8f5830b74d93e3b759ff3be4f2f898991e57931afc897b6e61dad2f1fecec262d15f3a4301f7e3c8fe	\\x0000000100000001bcc16bafa2287a82686287a321529b38dcf8f232b33a0893c1b60ea55b72996f41916cbdff94804696e82f3d2980fc2e2c24646f2278794f805977fa8532db178e5aecdeeed5b11ffc10ab5fc03059d84a27ea5f314dbfb6f512f51b94a917d74f1377f2e48a7361b925d7e8340f6ed7d204df29b0dc23a19ab6ba6073bb1a66	\\x0000000100010000
50	2	37	\\xaf7ffe2c8f9582cace155924242ed7674293ce1c8c8be4221231615643cd23eb7a69014e5a9ab906409e1f4e185780c9403ec43f7c84ac8e087d52b03bb13d04	411	\\x0000000100000100499d4868831dd0a08f5a30931ebf6a33167dfc3486f52acad7eb48bf9920fa9bbce814aea8a939393a919aa3cefa036c7e9db2fafa06bea0d6a64cce4a90c5e5615b0be484a11ac02b30fa9b0d962193670d6861b4301275641a2a4983acbe45cde76dd6517173d0aa46007119070636364c376c5d5964ccf20ab7767a3d24ba	\\xea3a8de42fe66f690e9a7983942c43975da48a6f0ecf986ddd9901bb6612eeb736272b1a364d9fa26a59c7e506a58387959266bc4ecbd37710bca7b8eeb1b43d	\\x000000010000000178e17ea780aba69d7e48202fcc440d4f46d6151e5ef2d481a624825c3cbff2fee9c650833e90662ae185422db117f4825cfa87aaa2ed50b90b21e1a0a4d1ec994b81fc764ffcc43a3a81cf8c706fda2ff24f2e28202a2ec16928788c44ae1dd86461748bd416163a978dcc41e05f3b871b3263390ae19e6675746ce047c776ee	\\x0000000100010000
\.


--
-- Data for Name: refresh_transfer_keys_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys_default (rtc_serial, melt_serial_id, transfer_pub, transfer_privs) FROM stdin;
1	1	\\xfd2ebdb97cbc30c98ad552c01e0cfcee02922d88feb5e8ce2ec64a11fa397645	\\xe445c33954c9dfffbd846e3a9faca25b87d83ab10de53bde9d09513abf6303d43ca44304b7920b5e947fddb80249e77591115c20aa075e2782fede5ee4eb8aad
2	2	\\xce03ce33b925a7793fc91eed7a5f6730c7bfa8914f0d634e9580fed258036868	\\x9573445ee76843afcfb13d16c4c47bd6d89150a8ebee1f0593bae001da9fa6bd3047564cdb31f238c0b6aca4efc5ad247196619b822e3bd5af4cef8e32b0a1ae
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
1	\\xa442106c3c030e22924f6ed00f0b25405922cfea2ca215f3073992e388ec68e2	0	0	1652434118000000	1870766920000000
\.


--
-- Data for Name: reserves_in_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_in_default (reserve_in_serial_id, reserve_pub, wire_reference, credit_val, credit_frac, wire_source_h_payto, exchange_account_section, execution_date) FROM stdin;
1	\\xa442106c3c030e22924f6ed00f0b25405922cfea2ca215f3073992e388ec68e2	2	8	0	\\x03fffed4d8d4617c2d80c4b15f08389670f7782422756ab1ba72e8d7b94f6ee5	exchange-account-1	1650014905000000
\.


--
-- Data for Name: reserves_out_by_reserve_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out_by_reserve_default (reserve_uuid, h_blind_ev) FROM stdin;
1	\\x170bef814d040aa1cd1cd97af31dba1247536662c607520bde48415044c60316a160d6c98aad5c7d8cc134c936e84a6bc8e7e2c45070cb742f6777153a80143b
1	\\xd735dc89fd190fccbf8fdb9246bbf70bded418832d5e396c22e8b545b838654495f430f9d0973d4bcac221a447bf2b66f67790a47edaf964402ee024af73d8b0
1	\\xd2b97cb3eb0e2f40b6f1d58725b59bc3aa5314d08a75fb7b4a23a4d5cc1da655a2487b2af97ca6463aae654a647ca115f67fb483518fa0383dae53c60e092a32
1	\\xb20dd5982b56c2924be5f5f4d6df8a3793d10ea154b72e482f5b05be2cd0bfce7f94452eeeb1b46579d13a0a10f6bd083b6cef4ea23a3103f1567b08b045f5a9
1	\\xb6d88d5190c4ae85b204cab61a74857fa90f27325e8cf7c0cd35e623b8c4e09b0897fa5aee2051e0efdd2b1c0e4c5132bcf540745f0ab9cecb06145169f20ba8
1	\\x79d7c305e9d10f587276f01061c0e5a0b5b541d5ff290223b7de3afee57dafe5b129583d945984ac76b0ca9d3e63309f1a92aa669b82f28719fce7137f289ccf
1	\\x22ea6907da7e29f88b0c853fa85ec237f0db95b17abb8366a92c01dc8ae0e257427f8f54d5114c0e94085f132040457635f0740d941f34340f82760af5def78d
1	\\x744ce1e53ad7399798faa0b460e294c20470263459fd14be55f0f0fd5e874ccbf06773442c94fcbeb84070f78608a2b03cd1a45423915a0c38abfe5f068aefa9
1	\\xd792899fb29b78cc81f083a31bc5c5a95957259c5a32a29034465d0b4b2c9fc4f765cc9031f3552af9797d677167c426de340e75d58296a639902b4695dfbe87
1	\\xf9903324030719954179de2a42ce7d32b4cbc7d9ad17cf00a9fbfdf7337a76f05d1d16c90fc99d4ee851ace711ce55b284d846d8b586a97bd06c82f26e2ad6c4
1	\\x289333b63278bdbdc8156e5d7f9b0548c0029d76b2a79e38af4e7c7fbb2756f05a86ad4564c7a1cf99e7aa0ced9ef7a3eadada03a0081015bb7dff843ab3be99
1	\\x21cacf07eb2df45e7dfdfa99a6ebb901349e9505ad604dfd387b6f72d81b0d2d424eb490ba971bf9add89ffd414155de254e851b7254f553c328ca5915561b17
1	\\xc8c7dd772785f1d1943a6c9b1faf322009801811794064b7988defcc50a8cc636b88f4297efd1db432f2af63fd9db9e03457994e2e219efed5ca420a5be50ca0
1	\\xecf7ae0d87acbe106b416119bfe34b1b94185d1e96fcfb24cd6c6a14a523c3c4b0750bdf3c4f9e7b7a275a064289342673d058154d74b888d77660d9babfa415
1	\\x580e42812a72b4c051aebbf9f823e78b5c05eabe53fc671cbfe4ea47154b7bf1ad169d4cdf6f2147ca9d3fad8b0416e529e0850592e6675db5c72282bc49921f
1	\\x14da8ff7e8587f5247244e69a898527bd84c83e963e30eb48aaf0c23a87bbc45d7b074402a8fbdc50229d446c650c9325a4eee34726bab09c2ab165e18e2ccd2
1	\\x805b11c39553fe7282832bdba09ebda68986589218596681f4a3980e095354d048574947edc39fac44a11ed603a57f29091ca056a439ffc56d5dbfb4e0a55ec9
1	\\xfb08b6d56464b6321da2f5a2aeed8ea403ca304ee52331c4a7622d024ceb2a9116a8efaecd12ac2a257ebe1d36a0ebfa5f528e883f57bb9b40bc6b6ad5ebbf08
1	\\x7b2d3204128ee6c0338d91ec6652cd7969d6f3a99e63a6324939a186052774077b364a4ad8eeff3604520d0546ccec69d5b00552e37f85a04d480ad3255a7b6b
1	\\xee90043eb2ec64b54f31981e4504448110958599975f650224801aa0b140a159833217b26cc9ca23e1005e254dea04284776741142cc5c86fafd9a93d71cf3c1
1	\\xeec3e9657057cd53969899b332852ba6d43a3594656acd770a34ab7146caf1a3de0c6b4ae7f9e96d5ee7cd1b7d4b72a1128e5c1d843a86cd77380cc7d3efe222
1	\\x182eca792f39c37b11be690e6b44fedaf4f514e616e9dd5b4e3ce65f14287fe46041bd84eefcaf5a06fab03413b2d060ffbf0116f091316bf98616ac0f568a9a
1	\\x67680bf29279ab59cda6ea6e0f52f352a6bf5b2ff69eadfe205b1579eeed4fc579a756809a6852b1c34f99348a22a5abb29b7a4db6e8a23d47098e14125b9572
1	\\x85dc1a7c0846017d35835b15b7625b31f4c3f6f0fe9cb2401e34fd8a7d95d00df87d3f277fe7ab9513c3e1dfbbcd239c5bf96d6bfdc34873cd8373f9168b2e08
1	\\x1295fa89c76ce53e4747eb7c0542e64c154feb023dbc22783540a5873c319cba38f639f2bf34ac5d06bf0716c1e5466ec7fb978272c631f8043bf4a190582c11
1	\\xc2d15260bfd40947fd2e9f2968ee9d81ce296a33a18844284ad35c38ec6ddda8d3cf642e8d539d181da1c4e49fe09ce55fc1503ba1d320146c9677b2d697dc99
1	\\xc04ab1ada1dd3f1f12ae480a91a1b81e0a57bdf7b1fee3dc805bcc351b5cba2b42c9042c6dc072ea32d240e7b84d68c1ebaf47795dcf886f5a2440f99ad9c2ec
1	\\xd52b9995a1de02eff7315732bb1fb2ec7a8cca582a8e0a9570147e8bf43aae489eb437c4e3873e0a26b9d4f4adf6725699214414a20cb3c3c6cb723da11e21f2
\.


--
-- Data for Name: reserves_out_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out_default (reserve_out_serial_id, h_blind_ev, denominations_serial, denom_sig, reserve_uuid, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\x170bef814d040aa1cd1cd97af31dba1247536662c607520bde48415044c60316a160d6c98aad5c7d8cc134c936e84a6bc8e7e2c45070cb742f6777153a80143b	225	\\x0000000100000001625232e5e59fbe9ace26c9ca4e2733e4858575234f412936ec02fe1a2acea05584f9bba2e1ba5f7c522999e8d76c7ab0c4eed3bb9ad9dc3eec8c24aa80259840ff6e745ff2c36d945e6901a81535f59a2b146cc621f4a04d556eaf384f91b49dff034bd0b6ad604e464751572900cd8eed2fc8f0f7ace97eb9cb0cd5f810bd93	1	\\x443199a55f6f6d2349bdfc042a4c85cf06fb07defa31d3072acb86e052eb9845ed67975d2d72b2f6442484b5eee4f08c2d1053fc0d24330a524bca19e112690a	1650014908000000	5	1000000
2	\\xd735dc89fd190fccbf8fdb9246bbf70bded418832d5e396c22e8b545b838654495f430f9d0973d4bcac221a447bf2b66f67790a47edaf964402ee024af73d8b0	208	\\x0000000100000001aca8a8ffd577f824f1080071d6882aa07aac7c0d0c52df025e235b61b526d6fa9ab7a7f8ddee2371ae39f74ec4d20cee577014b2400650b9f3896cbf4ecacfb648a610fcf7be0858e3b28a076731980c3663014805c946ecbe91dd4dcf70a0386403cf9b6b09011cc664d56569ce4bff3ab81570cc3835de127fba72fca0b636	1	\\x8f7097806cf3b3a5b182c9dd1dda07405251eed632f1aba948292f3dae39577c9de34e3bd3cd3b719692afcfff73b463353ae7539e8dab77a65ed4b71fbaae08	1650014908000000	2	3000000
3	\\xd2b97cb3eb0e2f40b6f1d58725b59bc3aa5314d08a75fb7b4a23a4d5cc1da655a2487b2af97ca6463aae654a647ca115f67fb483518fa0383dae53c60e092a32	198	\\x00000001000000011b41989e8108cc6d0754b8b86d5e5c3703ad17e94e57b3ec5dc996eb661503cbfec44680ed949a67cbd843f245ce70c2d9cac641030e098c5094922d6ac912ee2b01b4c2f6424dd5caf0bf4e12def163aa1a11c6bd8e09f2868a2d14641389d6e7e0e52c2e66a082480aa919a4f9db590a2ff9bc3e35d562f8ab288b5f605e8e	1	\\x1fd1fcb0e3e9e4fd0f6481cc6ae9cc2a90c029474254816a74908df37e1cfc19f0211e1373dd8a94495d30da2be7d296e2847e98c79338759c7b23aec395bd04	1650014908000000	0	11000000
4	\\xb20dd5982b56c2924be5f5f4d6df8a3793d10ea154b72e482f5b05be2cd0bfce7f94452eeeb1b46579d13a0a10f6bd083b6cef4ea23a3103f1567b08b045f5a9	198	\\x0000000100000001166ed14830c38632df67ebdfeafd3c23a41c20cc1f1544d4152d5d00065347876c2d7db5ebe88ad96129de63b3d6fff9eeb0a1dc3c9b6018ab0f3c1a33498e540782fb63ae94ff11eafd42e58f013b1566582dc4230a068536b2ccca105532032b41cef32efa6ee06a1d82c2e23a072e045b49e3029f05bfd8e99815b3a60f1b	1	\\xa52df0fe37ea7634653b611c0a11e32faab7118dde05b2b49040c491dcf74178a31e6622b08b49861e87c60ab32b212557ca43489d37b682215c4e6ebc460007	1650014908000000	0	11000000
5	\\xb6d88d5190c4ae85b204cab61a74857fa90f27325e8cf7c0cd35e623b8c4e09b0897fa5aee2051e0efdd2b1c0e4c5132bcf540745f0ab9cecb06145169f20ba8	198	\\x000000010000000172028feac2c274784ae981d352f60d329ac72414a8c85f411b3cb03f47129546c1fa46aaec7d32a483f7cfdba66a3d08698549c3deba45edf0fd77fb3ce82ea74c5cd4e11a31f9f56352b5fb08b5f03e2b62bb0d28b3ac97c49752dadb5519c52a9863affca12fec5214901f4a5b9a0dc8b3888f0f0b848dead354fe2a6791d7	1	\\x7606be9b8b9175565085500f1fd3d02a57e0aba3bd89333fde8829cd80e2212b0717d78ee9c43b08828903aad4c415ab4760a31c79d35e06a3c6263441a8aa0f	1650014908000000	0	11000000
6	\\x79d7c305e9d10f587276f01061c0e5a0b5b541d5ff290223b7de3afee57dafe5b129583d945984ac76b0ca9d3e63309f1a92aa669b82f28719fce7137f289ccf	198	\\x000000010000000120c4fdf53733d3f0bd880c78b0b05548706ddb9446a08fa2871b49c5ad0f3aba76c5405d2aa34fc30e2d92002309ed2ca3853e7321b325cc2bf2ca5957789b793496cdf2a68f62b2aadf7dbc2373de1d44fc91be66a7cf54ce4e48a1f41d60aec3672b455b4aa55cc63d72397b5d7687de83ddcdf0d852dfae99890dfe268f98	1	\\xe4fbedf9dc589eec3e50bea4c7889e559c33922503a416218a4a35b2647f3de7608ceae57afc9e1787612af4bb5e3bae3f88439b2e3f4fabd68c37cf108daa01	1650014908000000	0	11000000
7	\\x22ea6907da7e29f88b0c853fa85ec237f0db95b17abb8366a92c01dc8ae0e257427f8f54d5114c0e94085f132040457635f0740d941f34340f82760af5def78d	198	\\x0000000100000001270e977ef5ea32fa3d18359facee5140b8a38e93a34a72250ead2f633c9cd06118072c53da5e265f5b200dfa533a5f1c88841b0533a56a7fe89c9545abd8b5b1afeda3da6854113ab8b390d88614b0f5fe9bb363a71575a78bdbd036d495ec2e628e84b257b64c900453e11683f92fc78a9bd0bc8083393fc249d1e3f1411266	1	\\x07ca666beec4b2a2069a9c80cc82bfe98ffa9fbd2c0bddb857beb3916f3ca4475ed8c25c474af954ac199fe10240824430c506665c75bfffe0629d0258804e0b	1650014908000000	0	11000000
8	\\x744ce1e53ad7399798faa0b460e294c20470263459fd14be55f0f0fd5e874ccbf06773442c94fcbeb84070f78608a2b03cd1a45423915a0c38abfe5f068aefa9	198	\\x00000001000000013a39b5fb35e12b33d0e47a887d08966c59675493dcba67cea9237ea0e405500bad5ff50bbef7ab872932e9e795721aa8da99cbdc5ac9e37fa5171c93c72e1bdc19c640dcecd23e5b642ca7d07638a1a376b0bd8f0e88af906fbc7ed5b259c573c332ed73488e6e4e1b710b2d2f05f9f6a2ef16055eb8981b5b6c6813139b0bb7	1	\\xd6ab4e408438081c3958578edd208b033055453ca3da94b43bd416f3d368db455a2ddfff6c4afdfc0cece9bb6203c50d06854aeab295dbc40b5b2478af9add0e	1650014908000000	0	11000000
9	\\xd792899fb29b78cc81f083a31bc5c5a95957259c5a32a29034465d0b4b2c9fc4f765cc9031f3552af9797d677167c426de340e75d58296a639902b4695dfbe87	198	\\x00000001000000011a68a6f345b4e5082cd7937b12337512a5765c6ecb67e6b40224e792a46738d3016242918003fe2965d606fa28b689f0a4b4603cb6fe8dd9776060be4d5464b30518bfcd09d474818abe67cd67244572daf2672c5f00cb698083d0fde8eb96d8edf860783153d08ae52f0d94d6f7a1e0415b7ecd8c98590fd4034b3ef2909777	1	\\xced6a8ec2296a6ccac81e5b758878f5b1777530d4162a54e6c1fb8aefdb8c9f9b93fcb20e9f072aebf72b7cc64d12c02191a9fd3c5fa6edf5047cb25e18b9a02	1650014908000000	0	11000000
10	\\xf9903324030719954179de2a42ce7d32b4cbc7d9ad17cf00a9fbfdf7337a76f05d1d16c90fc99d4ee851ace711ce55b284d846d8b586a97bd06c82f26e2ad6c4	198	\\x000000010000000174c33e2d21c3735d93e0a1f759d2cc91b175b64c9222c70c15606b08c6fb8fc3357040711207be1db0b1c57d4482690c67a68df3ceae38caacdeefe9fd97e9f3ee7fcdf90997082aff8f5db12deeef29c4abb6b8cdbd86ef08808185fb5b6e141d8000127122be4112082fc81e7ec42cbf0506047e741ff5838248496e377942	1	\\x259da068f523ec1f8d9565aac60b909f4df820312bf0d4b4911da1951f5a049f0e6e5c2432560c20a2ecb8e0e2e54ccf34061c414f1e66b5a54d090775a70f02	1650014908000000	0	11000000
11	\\x289333b63278bdbdc8156e5d7f9b0548c0029d76b2a79e38af4e7c7fbb2756f05a86ad4564c7a1cf99e7aa0ced9ef7a3eadada03a0081015bb7dff843ab3be99	31	\\x000000010000000176babac5215d3cdd81c98141e1e0f2b33aaa8c887985601e7d564bd9e0fa601e95d2fc3b85651fb11bc01974fa986286fa435b86393675b2ea54eb1465a83c2ba0423d0c5a87263b6a3bdbff376ac625c056e23c1e4b27f0081f3fddda388df06c13f726a12147b24d62ee587fe13748041c65fe614d0f199d6336b8a41f1315	1	\\x9875c667d17ac09f639bf7577b4000bc81511daeed690ea84ec29e5831c6439efbbde24e9c043d8d839309c07abf5c76a10392891192241a3ef86ac8d168ab0e	1650014908000000	0	2000000
12	\\x21cacf07eb2df45e7dfdfa99a6ebb901349e9505ad604dfd387b6f72d81b0d2d424eb490ba971bf9add89ffd414155de254e851b7254f553c328ca5915561b17	31	\\x0000000100000001b8cbd252f2ec6581c234b7239f9b5d28eb0dcb2479f956bc38686b9f55e1ac2fbb4114d230a3266df5e5743b9500cfdfad542579f7d94675723eb1145c4fdc2cf06872c8376f63585b990d62b89eaf3e5b3faf057c33f5312c38e76c8e5ac6465747bcaf39d57359a7104ea513be137989b8d94219bd1e1755c4bbad1d7ad94b	1	\\xd2a19cbc15347fb7092b3026da567545a32d8b93c79929597076907ddd3c6b1996a5ca1c61ae2bd2a7a251669257ec24ee183deddd947c7a4991869861041d02	1650014908000000	0	2000000
13	\\xc8c7dd772785f1d1943a6c9b1faf322009801811794064b7988defcc50a8cc636b88f4297efd1db432f2af63fd9db9e03457994e2e219efed5ca420a5be50ca0	31	\\x0000000100000001b02f38e648f6f988ed9858d3db098c03df806bd04d513437e56788f305bac20c9f7cc81133d7be28a364c301da604e50914da642341babf8967fd20b9bb71b5401053be0df9266bbcac8ee70f3307bb58a32fa142d13d18762b90d84f5ffa6ccc0b08c85011b799c71c5390e2237b7c624b64bef1493bca172c3f86964c6dbd6	1	\\xbd2e796705c4d447afef4c066b75c986422ac0070b13e986d1609ed95ecc5cbc4df3c0d5629fd8c4c08b89d324c4b3d070593d9d16fef2a8b39f6701dbcb2a0a	1650014908000000	0	2000000
14	\\xecf7ae0d87acbe106b416119bfe34b1b94185d1e96fcfb24cd6c6a14a523c3c4b0750bdf3c4f9e7b7a275a064289342673d058154d74b888d77660d9babfa415	31	\\x0000000100000001724d68e3db04987ad457d4bcb5ac89c4f3ffc79edaf50137c01883dcebd82c9a359f7c047eb903b2cc7700265f93b35dfde281aa3272d39f96a17e30673c19350efbe85c9da5defda8ff0310de03c6b0616d574dce1941198ba23592f566c9c73cd968b7cbe858e48a51717610ea135e7eb28c0a93efecedcc26cf3499815a0f	1	\\x60c51a7453e0847f887d1d35039ea1b5633ae65d67f72e6948d38b733aa88acd3d99fd2663dc95371201d012020325da63efbe11b8174a5372a01579b5b31502	1650014908000000	0	2000000
15	\\x580e42812a72b4c051aebbf9f823e78b5c05eabe53fc671cbfe4ea47154b7bf1ad169d4cdf6f2147ca9d3fad8b0416e529e0850592e6675db5c72282bc49921f	139	\\x00000001000000019c69929ee88016333e1f7d30b3af335d3d56235b4d107bcaba29dc93a9a9baedcde2ee9a4491fc352ca46ebaee7c95e1d98c097117efec6007166b43395fafa0ef61a3576746c16eb954dad5f984a4ae56565938cbaaabaeaec7b436948d0dd819acff013666b23a5549cf34d268c3272df3c33c828949251d67e28641aa87d3	1	\\x56da5441aca73cb95530d235d332cf615bfba63b033ad482be21ff56f073c5f8ce88a2a00cb118e1919bec6851e0d82d6c76d46ade11231fb03676dcfc6ebc05	1650014919000000	1	2000000
16	\\x14da8ff7e8587f5247244e69a898527bd84c83e963e30eb48aaf0c23a87bbc45d7b074402a8fbdc50229d446c650c9325a4eee34726bab09c2ab165e18e2ccd2	198	\\x00000001000000014e89692ec6a3df8a9a480677e39dc5fc425e104fe7853380349e7a35cbec73e4e2bfc69e257d8b9e0abc8f6636c7709b23c530978d0ea690d2f9cae3e7f3fd41c74a77a39ea6994875233f6b619891799d90af2a42cf73e56f5acb7f495b08a610d1da53d183a42f430c4da87571eb8a53eacd50cd760e6bbd6c6f2c3782e56c	1	\\x406e9566ab5279023921694406dc28bd65f8fd1060d424a932418d1d84be8745442827b8f0b0ee3055f712d4bcf816dd310efa64ccdcd967cd481ecd6c2cf304	1650014919000000	0	11000000
18	\\x805b11c39553fe7282832bdba09ebda68986589218596681f4a3980e095354d048574947edc39fac44a11ed603a57f29091ca056a439ffc56d5dbfb4e0a55ec9	198	\\x0000000100000001cf46370aeb7b1bcec1b1e9a5e519edb7adfa8a244ef5e1a686666bfcb619f72849b2989bd63a9476ed7e7e2b262506a4eadf65cd4cb6ff0a344c202746d617cd1520c4630901107f5ebb2f62c0c4ed20c1f01f87b1d62bfb130bedbaca0e84b903e90a5fa2607b9c1e626374e8adfb2cf13e8df5c561a2adfb834dfd4179dc65	1	\\x2bab3629be1646773e0651bf3b916cda58bc6157815d40784ef018cfa6db63da1149855d1c1e747086c67e93fa85e07770a1fd4b257aedfb9194930537044500	1650014919000000	0	11000000
20	\\xfb08b6d56464b6321da2f5a2aeed8ea403ca304ee52331c4a7622d024ceb2a9116a8efaecd12ac2a257ebe1d36a0ebfa5f528e883f57bb9b40bc6b6ad5ebbf08	198	\\x000000010000000149739cabe12a08bbcedbe665dc1f5cca2098ce10fd5e0f955cc8a3af2cd6ec1be68f529cb555fea47c5bc25d85a8cbba036a26e0493e86cf793200e1f121b7c95b32858697597013fa45bcd1515518218a8cb708e348a76b19a2ef7603d5183de7d853d8350bba7b2551514f4dfe606d3218bd4ed37b74c196d4fda8e210a3c0	1	\\xd668801193c98b036fefded13238426b8081eab1c935c2688780414099aff830eb043a6d9c7f234d4c9e423c9738975207bef96daa0b1aa2a29ced1d40d5cf0c	1650014919000000	0	11000000
22	\\x7b2d3204128ee6c0338d91ec6652cd7969d6f3a99e63a6324939a186052774077b364a4ad8eeff3604520d0546ccec69d5b00552e37f85a04d480ad3255a7b6b	198	\\x0000000100000001e5a531f828a1d7c8c6cee1815a945a58f140148a592304dd4e99e5b1c51117679adcb6fad7396aa49d59488b895e4fd99644ae197b98ded760ed28ab50c7eaad3e4e1b7296a74db0b15d993a5d1daf4250ef6cceae563ebe1e33ef144038bf315c5656d10849b164085f12d6e56ce8cd3266427e54549c60408724b1eb92c68d	1	\\x1cf796f4d9ce408163a632cb88b9607ce897956bb1d83b2deacdd0bf59d788f09beb97cfa53eff7fc5aade6a6c4845c2a41619b3bc9fc73990a096a58c5c8d09	1650014919000000	0	11000000
24	\\xee90043eb2ec64b54f31981e4504448110958599975f650224801aa0b140a159833217b26cc9ca23e1005e254dea04284776741142cc5c86fafd9a93d71cf3c1	198	\\x000000010000000186b8e90beb47e13046a94b731cb31cb638c519941b03ed985fe8a2c4d6976d5d4cb963ea241b0e69784b8ae99f15c49043f83f65aaf75defaaf4bb439002f42f01ca50b0c1d6410ede9e4ebf1a2a4bc5e40841d39d2cbc79117c74bb15e5470571247c33e0836a68b3251a1374f71c452faeee9f16ca518c2379754a9cbe4780	1	\\x09c2636bf13b262efb1387f1a1e5fc6524a47f0ffe2b91508f4ddc21e681ed4a7b0bc404c7999b3662e3ac356e9daac2711960a574a61db87fe58ca3597b0f04	1650014919000000	0	11000000
26	\\xeec3e9657057cd53969899b332852ba6d43a3594656acd770a34ab7146caf1a3de0c6b4ae7f9e96d5ee7cd1b7d4b72a1128e5c1d843a86cd77380cc7d3efe222	198	\\x00000001000000018960077bf1634d2ca6bf1095b67e6db97bdfb99db7b9f6ecb47ec019438efcd42e18a1d26c98c97445c0cf8f27beafc6cada56d07f80463ebcea5e2a101eba36bf30fb21979766583156371cb858f93c64e8cea7e10dac77afab50a0b924cb8ebbf316c9f9ab2f8f468d6e2eb39bdd9b6e273837ae4f7e8ad82812c57678781c	1	\\xd95aab79d53e41165f53acc5cd7fa03e7db7da87c42937a310cb540e01c8f0d8bf33d753af8ab5ae759ccf1c9928a66ef06ac01c50af33c757bc39901b671402	1650014919000000	0	11000000
28	\\x182eca792f39c37b11be690e6b44fedaf4f514e616e9dd5b4e3ce65f14287fe46041bd84eefcaf5a06fab03413b2d060ffbf0116f091316bf98616ac0f568a9a	198	\\x00000001000000019b6ee54a3f4f7e6d0528a1556a8914d715b259256de2b579585a7186bd515d39df3cc9a08447260fc59a2edd9e2d9923c2e8605e7f42e9308075b60d89cab5bada99d4b313ad58115e72180afb5af812d5ab7d6d7e0fe16eb0ee2a8d30bbec74432344eb62401822833b37430f6cb584aab37b2ce298ed40af9dd23147234f8c	1	\\xaac2ecfc2d6481b0e1ad95ef0c90ff2a08b82ea06f8befa6559a90238fa28a3048267b43bb5df24580ba25c218c202bd595578504f37da62c3a96c1a2da6fe0e	1650014919000000	0	11000000
30	\\x67680bf29279ab59cda6ea6e0f52f352a6bf5b2ff69eadfe205b1579eeed4fc579a756809a6852b1c34f99348a22a5abb29b7a4db6e8a23d47098e14125b9572	198	\\x00000001000000017baa8f807631592957ec15ddf9ceddbf0a506fca2f4ce5ff6650d01ff61d650e25ee1daef055f3f88de885d52b4818d8a81c257b15366ced75c426ef302eea943056294c47a80541b0f141fcf4ebe487f5f27b4cd20b7bba7c02dfbfbdf7c4570d42f8f102ac70ee67794d8960d2533b9620bbaf37f279c7ca30a7ae89bd57db	1	\\x758472308b8f746d5c7092d612c84ed7d43b235f9fff52becbab6ec8b03be462ee79dbfe5d3022af60f5af8a42088c4a2519dbe2e8be2b199344186faf4aa502	1650014919000000	0	11000000
32	\\x85dc1a7c0846017d35835b15b7625b31f4c3f6f0fe9cb2401e34fd8a7d95d00df87d3f277fe7ab9513c3e1dfbbcd239c5bf96d6bfdc34873cd8373f9168b2e08	31	\\x00000001000000019865ae1bd232086b81efcd28c74514ac903710499076f05fbe25820816b564805f76df80036b84b082a596361e22dcb73a18fb6c9a778e5f054b2e236bedf63f8a76725f571e05df69bcd3f5eb5288e8e0278a0876cfce39536647d10e38ac6e375acfa1ca546ad89d19148daffdfc068ae7a8b46cfac0cd13419ec3490f346b	1	\\xc02d5dbf67de8280d37cc3f3c4b6fbbe7bd991ca8876359897a28bfa49fb0272f028a8ed400c293002513ab718080c533d585aa4268ee36c158b89ce695b0405	1650014919000000	0	2000000
34	\\x1295fa89c76ce53e4747eb7c0542e64c154feb023dbc22783540a5873c319cba38f639f2bf34ac5d06bf0716c1e5466ec7fb978272c631f8043bf4a190582c11	31	\\x0000000100000001b6c8efcb4952a53cf140506b34182e55310b8030fdc2f352a69b1f5d387ac18b42e559cbcee5667d5676c831ebbc2913f98a037463ad9f5654030f6aa7f05f29109553c26f133afbaa18fdfcca808ec278d19ca43d3c510d6fe56d2c3866f2d99a8d07035e2e290c25d2149581ae6c9489fe8cc16393e15f0b6a3d07d323d47b	1	\\x89139981908222dfdf2ac99d64700cad43364df6c0d1d938c7bfecbcd2b54564988b5608bbb5f26522504167721915c21d18467a5b5f7beb7a0c7bd71d8e7f01	1650014919000000	0	2000000
36	\\xc2d15260bfd40947fd2e9f2968ee9d81ce296a33a18844284ad35c38ec6ddda8d3cf642e8d539d181da1c4e49fe09ce55fc1503ba1d320146c9677b2d697dc99	31	\\x00000001000000011efe64a488ef211aa133d7ee9c39fe0d78211e8b8f7b1d81751c67a29ac21bb6892e8969029b82300426da4e38f37161aca14332b3aab31bbdb440525f711c354b14f0864e185417bdcba3d711c9ff31dceb1c4746f1c15c040e73d6fde3cf08b32fd8925fc3ed9f3d9126f3f274dd3cd6f993169abc6ada56ad2f5acfc8f92d	1	\\xa2143cb6f71f10f37bd9e9574bd249c4f27aaa9705ce1d2b6fa5b0be16a7eb7a043d6b3b468cdd0957160d62dfc9c02b611167fd46da255135090c431fb92c0b	1650014919000000	0	2000000
38	\\xc04ab1ada1dd3f1f12ae480a91a1b81e0a57bdf7b1fee3dc805bcc351b5cba2b42c9042c6dc072ea32d240e7b84d68c1ebaf47795dcf886f5a2440f99ad9c2ec	31	\\x0000000100000001c9d682e311664b3e11f318168428ad60e8bb0c32684317228e78ae33e99099f826b2d6900be48bea4f203ba5019ccf5cbaedd9bc716edb73c55586e990b7066ffa2c564aff45665258a0e9fa25717c3abbc02d5f48b0238239a9bd8037cbfac9224f17b6b900c9ff773463e35afbcaa9278a65ec5f82e71de1763ed2f766a136	1	\\x30d4c610af1f39242ba5a580161dba48528edb5090ede4f7ab5c978fa0f737502c64c3771dc158c435a33e2d49506a3541baa48fa6d153367d0a804a6acbba07	1650014920000000	0	2000000
40	\\xd52b9995a1de02eff7315732bb1fb2ec7a8cca582a8e0a9570147e8bf43aae489eb437c4e3873e0a26b9d4f4adf6725699214414a20cb3c3c6cb723da11e21f2	31	\\x0000000100000001d529ae4884867c39ef3ad66ebf777d262646ce308be4fcad7802d7b481ca644c9f16044f2e39399e009cba4e1ba0ce14631c1dc2be459f7984624ef1f5b7d574b829293c5e646f6c3cbcf7439796a4ab94cb19679ca2e0096eff18b5ec8e7227da09bb252a9ca60c5c4dbfd8a01e2da746708bf750a23cf5f51459fb76050b65	1	\\xe1478e685c982e1267688b3fdf7faf3fc8431b14b4ee10cf241af1f5d476dc90b32a8e7d6aea33f9bbcd4bfd5d603de12f2a296c4057fbf447efe9d34561830a	1650014920000000	0	2000000
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
payto://x-taler-bank/localhost/Exchange	\\x9af7cf42df9cf96029b54e027cf4059003ab059b15c23c66640ac1039f404d0e22dba31e6168206d946748f21dde5d3447695b32d25b6555afca1378faca1b08	t	1650014898000000
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
1	x-taler-bank	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	\\x78fbd61470a82d67fe97e9887fc52b2d65f1417679983d42aef1b5885aab0bce35fd81fab38c85edbd64db2f66c8b10d783e35a2fa634aa75ec250773cd6e90a
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
1	\\x03fffed4d8d4617c2d80c4b15f08389670f7782422756ab1ba72e8d7b94f6ee5	payto://x-taler-bank/localhost/testuser-yygbrwqa	f	\N
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

