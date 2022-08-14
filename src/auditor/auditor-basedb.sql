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
-- Name: auditor; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA auditor;


--
-- Name: SCHEMA auditor; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA auditor IS 'taler-auditor data';


--
-- Name: exchange; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA exchange;


--
-- Name: SCHEMA exchange; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA exchange IS 'taler-exchange data';


--
-- Name: merchant; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA merchant;


--
-- Name: SCHEMA merchant; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA merchant IS 'taler-merchant data';


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
-- Name: add_constraints_to_account_merges_partition(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.add_constraints_to_account_merges_partition(partition_suffix character varying) RETURNS void
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
-- Name: add_constraints_to_aggregation_tracking_partition(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.add_constraints_to_aggregation_tracking_partition(partition_suffix character varying) RETURNS void
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
-- Name: add_constraints_to_contracts_partition(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.add_constraints_to_contracts_partition(partition_suffix character varying) RETURNS void
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
-- Name: add_constraints_to_cs_nonce_locks_partition(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.add_constraints_to_cs_nonce_locks_partition(partition_suffix character varying) RETURNS void
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
-- Name: add_constraints_to_deposits_partition(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.add_constraints_to_deposits_partition(partition_suffix character varying) RETURNS void
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
-- Name: add_constraints_to_known_coins_partition(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.add_constraints_to_known_coins_partition(partition_suffix character varying) RETURNS void
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
-- Name: add_constraints_to_legitimizations_partition(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.add_constraints_to_legitimizations_partition(partition_suffix character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  partition_name VARCHAR;
BEGIN
  partition_name = concat_ws('_', 'legitimizations', partition_suffix);
  EXECUTE FORMAT (
    'ALTER TABLE ' || partition_name
    || ' '
      'ADD CONSTRAINT ' || partition_name || '_legitimization_serial_id_key '
        'UNIQUE (legitimization_serial_id)');
  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || partition_name || '_by_provider_and_legi_index '
        'ON '|| partition_name || ' '
        '(provider_section,provider_legitimization_id)'
  );
  EXECUTE FORMAT (
    'COMMENT ON INDEX ' || partition_name || '_by_provider_and_legi_index '
    'IS ' || quote_literal('used (rarely) in kyc_provider_account_lookup') || ';'
  );
END
$$;


--
-- Name: add_constraints_to_purse_deposits_partition(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.add_constraints_to_purse_deposits_partition(partition_suffix character varying) RETURNS void
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
-- Name: add_constraints_to_purse_merges_partition(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.add_constraints_to_purse_merges_partition(partition_suffix character varying) RETURNS void
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
-- Name: add_constraints_to_purse_refunds_partition(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.add_constraints_to_purse_refunds_partition(partition_suffix character varying) RETURNS void
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
-- Name: add_constraints_to_purse_requests_partition(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.add_constraints_to_purse_requests_partition(partition_suffix character varying) RETURNS void
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
-- Name: add_constraints_to_recoup_partition(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.add_constraints_to_recoup_partition(partition_suffix character varying) RETURNS void
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
-- Name: add_constraints_to_recoup_refresh_partition(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.add_constraints_to_recoup_refresh_partition(partition_suffix character varying) RETURNS void
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
-- Name: add_constraints_to_refresh_commitments_partition(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.add_constraints_to_refresh_commitments_partition(partition_suffix character varying) RETURNS void
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
-- Name: add_constraints_to_refresh_revealed_coins_partition(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.add_constraints_to_refresh_revealed_coins_partition(partition_suffix character varying) RETURNS void
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
-- Name: add_constraints_to_refresh_transfer_keys_partition(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.add_constraints_to_refresh_transfer_keys_partition(partition_suffix character varying) RETURNS void
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
-- Name: add_constraints_to_refunds_partition(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.add_constraints_to_refunds_partition(partition_suffix character varying) RETURNS void
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
-- Name: add_constraints_to_reserves_close_partition(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.add_constraints_to_reserves_close_partition(partition_suffix character varying) RETURNS void
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
-- Name: add_constraints_to_reserves_in_partition(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.add_constraints_to_reserves_in_partition(partition_suffix character varying) RETURNS void
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
-- Name: add_constraints_to_reserves_out_partition(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.add_constraints_to_reserves_out_partition(partition_suffix character varying) RETURNS void
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
-- Name: add_constraints_to_wad_in_entries_partition(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.add_constraints_to_wad_in_entries_partition(partition_suffix character varying) RETURNS void
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
-- Name: add_constraints_to_wad_out_entries_partition(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.add_constraints_to_wad_out_entries_partition(partition_suffix character varying) RETURNS void
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
-- Name: add_constraints_to_wads_in_partition(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.add_constraints_to_wads_in_partition(partition_suffix character varying) RETURNS void
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
-- Name: add_constraints_to_wads_out_partition(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.add_constraints_to_wads_out_partition(partition_suffix character varying) RETURNS void
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
-- Name: add_constraints_to_wire_out_partition(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.add_constraints_to_wire_out_partition(partition_suffix character varying) RETURNS void
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
-- Name: add_constraints_to_wire_targets_partition(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.add_constraints_to_wire_targets_partition(partition_suffix character varying) RETURNS void
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
-- Name: create_foreign_hash_partition(character varying, integer, character varying, integer, character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_foreign_hash_partition(source_table_name character varying, modulus integer, shard_suffix character varying, current_shard_num integer, local_user character varying DEFAULT 'taler-exchange-httpd'::character varying) RETURNS void
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
-- Name: create_foreign_range_partition(character varying, integer); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_foreign_range_partition(source_table_name character varying, partition_num integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
   RAISE NOTICE 'TODO';
END
$$;


--
-- Name: create_foreign_servers(integer, character varying, character varying, character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_foreign_servers(amount integer, domain character varying, remote_user character varying DEFAULT 'taler'::character varying, remote_user_password character varying DEFAULT 'taler'::character varying) RETURNS void
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
-- Name: create_hash_partition(character varying, integer, integer); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_hash_partition(source_table_name character varying, modulus integer, partition_num integer) RETURNS void
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
-- Name: create_partitioned_table(character varying, character varying, character varying, character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_partitioned_table(table_definition character varying, table_name character varying, main_table_partition_str character varying, shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
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
-- Name: create_partitions(integer); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_partitions(num_partitions integer) RETURNS void
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
-- Name: create_range_partition(character varying, integer); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_range_partition(source_table_name character varying, partition_num integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  RAISE NOTICE 'TODO';
END
$$;


--
-- Name: create_shard_server(character varying, integer, integer, character varying, character varying, character varying, character varying, integer, character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_shard_server(shard_suffix character varying, total_num_shards integer, current_shard_num integer, remote_host character varying, remote_user character varying, remote_user_password character varying, remote_db_name character varying DEFAULT 'taler-exchange'::character varying, remote_port integer DEFAULT 5432, local_user character varying DEFAULT 'taler-exchange-httpd'::character varying) RETURNS void
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
-- Name: FUNCTION create_shard_server(shard_suffix character varying, total_num_shards integer, current_shard_num integer, remote_host character varying, remote_user character varying, remote_user_password character varying, remote_db_name character varying, remote_port integer, local_user character varying); Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON FUNCTION exchange.create_shard_server(shard_suffix character varying, total_num_shards integer, current_shard_num integer, remote_host character varying, remote_user character varying, remote_user_password character varying, remote_db_name character varying, remote_port integer, local_user character varying) IS 'Create a shard server on the master
      node with all foreign tables and user mappings';


--
-- Name: create_table_account_merges(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_table_account_merges(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'account_merges';
BEGIN
  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I '
      '(account_merge_request_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' 
      ',reserve_pub BYTEA NOT NULL CHECK (LENGTH(reserve_pub)=32)' 
      ',reserve_sig BYTEA NOT NULL CHECK (LENGTH(reserve_sig)=64)'
      ',purse_pub BYTEA NOT NULL CHECK (LENGTH(purse_pub)=32)' 
      ',wallet_h_payto BYTEA NOT NULL CHECK (LENGTH(wallet_h_payto)=32)'
      ',PRIMARY KEY (purse_pub)'
    ') %s ;'
    ,table_name
    ,'PARTITION BY HASH (purse_pub)'
    ,shard_suffix
  );
  table_name = concat_ws('_', table_name, shard_suffix);
  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_by_reserve_pub '
    'ON ' || table_name || ' '
    '(reserve_pub);'
  );
END
$$;


--
-- Name: create_table_aggregation_tracking(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_table_aggregation_tracking(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'aggregation_tracking';
BEGIN
  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I'
      '(aggregation_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' 
     ',deposit_serial_id INT8 PRIMARY KEY' 
      ',wtid_raw BYTEA NOT NULL' 
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
-- Name: create_table_aggregation_transient(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_table_aggregation_transient(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
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
      ',merchant_pub BYTEA CHECK (LENGTH(merchant_pub)=32)'
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
-- Name: create_table_close_requests(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_table_close_requests(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'close_requests';
BEGIN
  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I '
      '(close_request_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' 
      ',reserve_pub BYTEA NOT NULL CHECK (LENGTH(reserve_pub)=32)' 
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
-- Name: create_table_contracts(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_table_contracts(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'contracts';
BEGIN
  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I '
      '(contract_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' 
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
-- Name: create_table_cs_nonce_locks(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_table_cs_nonce_locks(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I'
      '(cs_nonce_lock_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' 
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
-- Name: create_table_deposits(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_table_deposits(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'deposits';
BEGIN
  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I'
      '(deposit_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' 
      ',shard INT8 NOT NULL'
      ',coin_pub BYTEA NOT NULL CHECK (LENGTH(coin_pub)=32)' 
      ',known_coin_id INT8 NOT NULL' 
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
      ',extension_details_serial_id INT8' 
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
-- Name: create_table_deposits_by_ready(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_table_deposits_by_ready(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
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
-- Name: create_table_deposits_for_matching(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_table_deposits_for_matching(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'deposits_for_matching';
BEGIN
  PERFORM create_partitioned_table(
  'CREATE TABLE IF NOT EXISTS %I'
    '(refund_deadline INT8 NOT NULL'
    ',merchant_pub BYTEA NOT NULL CHECK (LENGTH(merchant_pub)=32)'
    ',coin_pub BYTEA NOT NULL CHECK (LENGTH(coin_pub)=32)' 
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
-- Name: create_table_history_requests(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_table_history_requests(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'history_requests';
BEGIN
  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I '
      '(history_request_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' 
      ',reserve_pub BYTEA NOT NULL CHECK (LENGTH(reserve_pub)=32)' 
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
-- Name: create_table_known_coins(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_table_known_coins(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR default 'known_coins';
BEGIN
  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I'
      '(known_coin_id BIGINT GENERATED BY DEFAULT AS IDENTITY' 
      ',denominations_serial INT8 NOT NULL' 
      ',coin_pub BYTEA NOT NULL PRIMARY KEY CHECK (LENGTH(coin_pub)=32)'
      ',age_commitment_hash BYTEA CHECK (LENGTH(age_commitment_hash)=32)'
      ',denom_sig BYTEA NOT NULL'
      ',remaining_val INT8 NOT NULL DEFAULT(0)'
      ',remaining_frac INT4 NOT NULL DEFAULT(0)'
    ') %s ;'
    ,table_name
    ,'PARTITION BY HASH (coin_pub)' 
    ,shard_suffix
  );
  table_name = concat_ws('_', table_name, shard_suffix);
END
$$;


--
-- Name: create_table_legitimizations(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_table_legitimizations(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I'
      '(legitimization_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' 
      ',h_payto BYTEA NOT NULL CHECK (LENGTH(h_payto)=32)'
      ',expiration_time INT8 NOT NULL DEFAULT (0)'
      ',provider_section VARCHAR NOT NULL'
      ',provider_user_id VARCHAR DEFAULT NULL'
      ',provider_legitimization_id VARCHAR DEFAULT NULL'
      ',UNIQUE (h_payto, provider_section)'
    ') %s ;'
    ,'legitimizations'
    ,'PARTITION BY HASH (h_payto)'
    ,shard_suffix
  );
END
$$;


--
-- Name: create_table_prewire(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_table_prewire(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
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
-- Name: create_table_purse_deposits(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_table_purse_deposits(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'purse_deposits';
BEGIN
  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I '
      '(purse_deposit_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' 
      ',partner_serial_id INT8' 
      ',purse_pub BYTEA NOT NULL CHECK (LENGTH(purse_pub)=32)'
      ',coin_pub BYTEA NOT NULL' 
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
  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_by_coin_pub '
    'ON ' || table_name || ' '
    '(coin_pub);'
  );
END
$$;


--
-- Name: create_table_purse_merges(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_table_purse_merges(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'purse_merges';
BEGIN
  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I '
      '(purse_merge_request_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY '
      ',partner_serial_id INT8' 
      ',reserve_pub BYTEA NOT NULL CHECK(length(reserve_pub)=32)'
      ',purse_pub BYTEA NOT NULL CHECK (LENGTH(purse_pub)=32)' 
      ',merge_sig BYTEA NOT NULL CHECK (LENGTH(merge_sig)=64)'
      ',merge_timestamp INT8 NOT NULL'
      ',PRIMARY KEY (purse_pub)'
    ') %s ;'
    ,table_name
    ,'PARTITION BY HASH (purse_pub)'
    ,shard_suffix
  );
  table_name = concat_ws('_', table_name, shard_suffix);
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
-- Name: create_table_purse_refunds(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_table_purse_refunds(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'purse_refunds';
BEGIN
  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I '
      '(purse_refunds_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' 
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
-- Name: create_table_purse_requests(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_table_purse_requests(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'purse_requests';
BEGIN
  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I '
      '(purse_requests_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' 
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
  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_merge_pub '
    'ON ' || table_name || ' '
    '(merge_pub);'
  );
  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_purse_expiration '
    'ON ' || table_name || ' '
    '(purse_expiration);'
  );
END
$$;


--
-- Name: create_table_recoup(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_table_recoup(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'recoup';
BEGIN
  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I'
      '(recoup_uuid BIGINT GENERATED BY DEFAULT AS IDENTITY' 
      ',coin_pub BYTEA NOT NULL CHECK (LENGTH(coin_pub)=32)' 
      ',coin_sig BYTEA NOT NULL CHECK(LENGTH(coin_sig)=64)'
      ',coin_blind BYTEA NOT NULL CHECK(LENGTH(coin_blind)=32)'
      ',amount_val INT8 NOT NULL'
      ',amount_frac INT4 NOT NULL'
      ',recoup_timestamp INT8 NOT NULL'
      ',reserve_out_serial_id INT8 NOT NULL' 
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
-- Name: create_table_recoup_by_reserve(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_table_recoup_by_reserve(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'recoup_by_reserve';
BEGIN
  PERFORM create_partitioned_table(
  'CREATE TABLE IF NOT EXISTS %I'
    '(reserve_out_serial_id INT8 NOT NULL' 
    ',coin_pub BYTEA CHECK (LENGTH(coin_pub)=32)' 
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
-- Name: create_table_recoup_refresh(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_table_recoup_refresh(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'recoup_refresh';
BEGIN
  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I'
      '(recoup_refresh_uuid BIGINT GENERATED BY DEFAULT AS IDENTITY' 
      ',coin_pub BYTEA NOT NULL CHECK (LENGTH(coin_pub)=32)' 
      ',known_coin_id BIGINT NOT NULL' 
      ',coin_sig BYTEA NOT NULL CHECK(LENGTH(coin_sig)=64)'
      ',coin_blind BYTEA NOT NULL CHECK(LENGTH(coin_blind)=32)'
      ',amount_val INT8 NOT NULL'
      ',amount_frac INT4 NOT NULL'
      ',recoup_timestamp INT8 NOT NULL'
      ',rrc_serial INT8 NOT NULL' 
    ') %s ;'
    ,table_name
    ,'PARTITION BY HASH (coin_pub)'
    ,shard_suffix
  );
  table_name = concat_ws('_', table_name, shard_suffix);
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
-- Name: create_table_refresh_commitments(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_table_refresh_commitments(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'refresh_commitments';
BEGIN
  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I'
      '(melt_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' 
      ',rc BYTEA PRIMARY KEY CHECK (LENGTH(rc)=64)'
      ',old_coin_pub BYTEA NOT NULL' 
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
  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_by_old_coin_pub_index '
    'ON ' || table_name || ' '
    '(old_coin_pub);'
  );
END
$$;


--
-- Name: create_table_refresh_revealed_coins(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_table_refresh_revealed_coins(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'refresh_revealed_coins';
BEGIN
  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I'
      '(rrc_serial BIGINT GENERATED BY DEFAULT AS IDENTITY' 
      ',melt_serial_id INT8 NOT NULL' 
      ',freshcoin_index INT4 NOT NULL'
      ',link_sig BYTEA NOT NULL CHECK(LENGTH(link_sig)=64)'
      ',denominations_serial INT8 NOT NULL' 
      ',coin_ev BYTEA NOT NULL' 
      ',h_coin_ev BYTEA NOT NULL CHECK(LENGTH(h_coin_ev)=64)' 
      ',ev_sig BYTEA NOT NULL'
      ',ewv BYTEA NOT NULL'
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
-- Name: create_table_refresh_transfer_keys(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_table_refresh_transfer_keys(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'refresh_transfer_keys';
BEGIN
  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I'
      '(rtc_serial BIGINT GENERATED BY DEFAULT AS IDENTITY' 
      ',melt_serial_id INT8 PRIMARY KEY' 
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
-- Name: create_table_refunds(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_table_refunds(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'refunds';
BEGIN
  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I'
      '(refund_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' 
      ',coin_pub BYTEA NOT NULL CHECK (LENGTH(coin_pub)=32)' 
      ',deposit_serial_id INT8 NOT NULL' 
      ',merchant_sig BYTEA NOT NULL CHECK(LENGTH(merchant_sig)=64)'
      ',rtransaction_id INT8 NOT NULL'
      ',amount_with_fee_val INT8 NOT NULL'
      ',amount_with_fee_frac INT4 NOT NULL'
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
-- Name: create_table_reserves(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_table_reserves(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
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
-- Name: create_table_reserves_close(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_table_reserves_close(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR default 'reserves_close';
BEGIN
  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I'
      '(close_uuid BIGINT GENERATED BY DEFAULT AS IDENTITY' 
      ',reserve_pub BYTEA NOT NULL' 
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
-- Name: create_table_reserves_in(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_table_reserves_in(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR default 'reserves_in';
BEGIN
  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I'
      '(reserve_in_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' 
      ',reserve_pub BYTEA PRIMARY KEY' 
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
  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_by_exch_accnt_section_execution_date_idx '
    'ON ' || table_name || ' '
    '(exchange_account_section '
    ',execution_date'
    ');'
  );
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
-- Name: create_table_reserves_out(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_table_reserves_out(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR default 'reserves_out';
BEGIN
  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I'
      '(reserve_out_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' 
      ',h_blind_ev BYTEA CHECK (LENGTH(h_blind_ev)=64) UNIQUE'
      ',denominations_serial INT8 NOT NULL' 
      ',denom_sig BYTEA NOT NULL'
      ',reserve_uuid INT8 NOT NULL' 
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
-- Name: create_table_reserves_out_by_reserve(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_table_reserves_out_by_reserve(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'reserves_out_by_reserve';
BEGIN
  PERFORM create_partitioned_table(
  'CREATE TABLE IF NOT EXISTS %I'
    '(reserve_uuid INT8 NOT NULL' 
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
-- Name: create_table_wad_in_entries(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_table_wad_in_entries(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'wad_in_entries';
BEGIN
  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I '
      '(wad_in_entry_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' 
      ',wad_in_serial_id INT8' 
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
-- Name: create_table_wad_out_entries(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_table_wad_out_entries(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'wad_out_entries';
BEGIN
  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I '
      '(wad_out_entry_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' 
      ',wad_out_serial_id INT8' 
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
  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_by_reserve_pub '
    'ON ' || table_name || ' '
    '(reserve_pub);'
  );
END
$$;


--
-- Name: create_table_wads_in(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_table_wads_in(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'wads_in';
BEGIN
  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I '
      '(wad_in_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' 
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
-- Name: create_table_wads_out(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_table_wads_out(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'wads_out';
BEGIN
  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I '
      '(wad_out_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' 
      ',wad_id BYTEA PRIMARY KEY CHECK (LENGTH(wad_id)=24)'
      ',partner_serial_id INT8 NOT NULL' 
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
-- Name: create_table_wire_out(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_table_wire_out(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'wire_out';
BEGIN
  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I'
      '(wireout_uuid BIGINT GENERATED BY DEFAULT AS IDENTITY' 
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
-- Name: create_table_wire_targets(character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.create_table_wire_targets(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I'
      '(wire_target_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' 
      ',wire_target_h_payto BYTEA PRIMARY KEY CHECK (LENGTH(wire_target_h_payto)=32)'
      ',payto_uri VARCHAR NOT NULL'
    ') %s ;'
    ,'wire_targets'
    ,'PARTITION BY HASH (wire_target_h_payto)'
    ,shard_suffix
  );
END
$$;


--
-- Name: defer_wire_out(); Type: PROCEDURE; Schema: exchange; Owner: -
--

CREATE PROCEDURE exchange.defer_wire_out()
    LANGUAGE plpgsql
    AS $$
BEGIN

IF EXISTS (
  SELECT 1
    FROM exchange.information_Schema.constraint_column_usage
   WHERE table_name='wire_out'
     AND constraint_name='wire_out_ref')
THEN
  SET CONSTRAINTS wire_out_ref DEFERRED;
END IF;

END $$;


--
-- Name: deposits_delete_trigger(); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.deposits_delete_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  was_ready BOOLEAN;
BEGIN
  was_ready = NOT (OLD.done OR OLD.extension_blocked);
  IF (was_ready)
  THEN
    DELETE FROM exchange.deposits_by_ready
     WHERE wire_deadline = OLD.wire_deadline
       AND shard = OLD.shard
       AND coin_pub = OLD.coin_pub
       AND deposit_serial_id = OLD.deposit_serial_id;
    DELETE FROM exchange.deposits_for_matching
     WHERE refund_deadline = OLD.refund_deadline
       AND merchant_pub = OLD.merchant_pub
       AND coin_pub = OLD.coin_pub
       AND deposit_serial_id = OLD.deposit_serial_id;
  END IF;
  RETURN NEW;
END $$;


--
-- Name: FUNCTION deposits_delete_trigger(); Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON FUNCTION exchange.deposits_delete_trigger() IS 'Replicate deposit deletions into materialized indices.';


--
-- Name: deposits_insert_trigger(); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.deposits_insert_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  is_ready BOOLEAN;
BEGIN
  is_ready = NOT (NEW.done OR NEW.extension_blocked);
  IF (is_ready)
  THEN
    INSERT INTO exchange.deposits_by_ready
      (wire_deadline
      ,shard
      ,coin_pub
      ,deposit_serial_id)
    VALUES
      (NEW.wire_deadline
      ,NEW.shard
      ,NEW.coin_pub
      ,NEW.deposit_serial_id);
    INSERT INTO exchange.deposits_for_matching
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
-- Name: FUNCTION deposits_insert_trigger(); Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON FUNCTION exchange.deposits_insert_trigger() IS 'Replicate deposit inserts into materialized indices.';


--
-- Name: deposits_update_trigger(); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.deposits_update_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  was_ready BOOLEAN;
DECLARE
  is_ready BOOLEAN;
BEGIN
  was_ready = NOT (OLD.done OR OLD.extension_blocked);
  is_ready = NOT (NEW.done OR NEW.extension_blocked);
  IF (was_ready AND NOT is_ready)
  THEN
    DELETE FROM exchange.deposits_by_ready
     WHERE wire_deadline = OLD.wire_deadline
       AND shard = OLD.shard
       AND coin_pub = OLD.coin_pub
       AND deposit_serial_id = OLD.deposit_serial_id;
    DELETE FROM exchange.deposits_for_matching
     WHERE refund_deadline = OLD.refund_deadline
       AND merchant_pub = OLD.merchant_pub
       AND coin_pub = OLD.coin_pub
       AND deposit_serial_id = OLD.deposit_serial_id;
  END IF;
  IF (is_ready AND NOT was_ready)
  THEN
    INSERT INTO exchange.deposits_by_ready
      (wire_deadline
      ,shard
      ,coin_pub
      ,deposit_serial_id)
    VALUES
      (NEW.wire_deadline
      ,NEW.shard
      ,NEW.coin_pub
      ,NEW.deposit_serial_id);
    INSERT INTO exchange.deposits_for_matching
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
-- Name: FUNCTION deposits_update_trigger(); Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON FUNCTION exchange.deposits_update_trigger() IS 'Replicate deposits changes into materialized indices.';


--
-- Name: detach_default_partitions(); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.detach_default_partitions() RETURNS void
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
-- Name: FUNCTION detach_default_partitions(); Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON FUNCTION exchange.detach_default_partitions() IS 'We need to drop default and create new one before deleting the default partitions
      otherwise constraints get lost too. Might be needed in shardig too';


--
-- Name: drop_default_partitions(); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.drop_default_partitions() RETURNS void
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
-- Name: FUNCTION drop_default_partitions(); Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON FUNCTION exchange.drop_default_partitions() IS 'Drop all default partitions once other partitions are attached.
      Might be needed in sharding too.';


--
-- Name: exchange_do_account_merge(bytea, bytea, bytea); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.exchange_do_account_merge(in_purse_pub bytea, in_reserve_pub bytea, in_reserve_sig bytea, OUT out_balance_ok boolean, OUT out_conflict boolean) RETURNS record
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- FIXME: function/API is dead! Do DCE?
END $$;


--
-- Name: exchange_do_batch_withdraw(bigint, integer, bytea, bigint, bigint); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.exchange_do_batch_withdraw(amount_val bigint, amount_frac integer, rpub bytea, now bigint, min_reserve_gc bigint, OUT reserve_found boolean, OUT balance_ok boolean, OUT ruuid bigint) RETURNS record
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
  FROM exchange.reserves
 WHERE reserves.reserve_pub=rpub;

IF NOT FOUND
THEN
  -- reserve unknown
  reserve_found=FALSE;
  balance_ok=FALSE;
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

END $$;


--
-- Name: FUNCTION exchange_do_batch_withdraw(amount_val bigint, amount_frac integer, rpub bytea, now bigint, min_reserve_gc bigint, OUT reserve_found boolean, OUT balance_ok boolean, OUT ruuid bigint); Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON FUNCTION exchange.exchange_do_batch_withdraw(amount_val bigint, amount_frac integer, rpub bytea, now bigint, min_reserve_gc bigint, OUT reserve_found boolean, OUT balance_ok boolean, OUT ruuid bigint) IS 'Checks whether the reserve has sufficient balance for a withdraw operation (or the request is repeated and was previously approved) and if so updates the database with the result. Excludes storing the planchets.';


--
-- Name: exchange_do_batch_withdraw_insert(bytea, bigint, integer, bytea, bigint, bytea, bytea, bytea, bigint); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.exchange_do_batch_withdraw_insert(cs_nonce bytea, amount_val bigint, amount_frac integer, h_denom_pub bytea, ruuid bigint, reserve_sig bytea, h_coin_envelope bytea, denom_sig bytea, now bigint, OUT out_denom_unknown boolean, OUT out_nonce_reuse boolean, OUT out_conflict boolean) RETURNS record
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
  FROM exchange.denominations
 WHERE denom_pub_hash=h_denom_pub;

IF NOT FOUND
THEN
  -- denomination unknown, should be impossible!
  out_denom_unknown=TRUE;
  ASSERT false, 'denomination unknown';
  RETURN;
END IF;
out_denom_unknown=FALSE;

INSERT INTO exchange.reserves_out
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
  INSERT INTO exchange.cs_nonce_locks
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
      FROM exchange.cs_nonce_locks
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
-- Name: FUNCTION exchange_do_batch_withdraw_insert(cs_nonce bytea, amount_val bigint, amount_frac integer, h_denom_pub bytea, ruuid bigint, reserve_sig bytea, h_coin_envelope bytea, denom_sig bytea, now bigint, OUT out_denom_unknown boolean, OUT out_nonce_reuse boolean, OUT out_conflict boolean); Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON FUNCTION exchange.exchange_do_batch_withdraw_insert(cs_nonce bytea, amount_val bigint, amount_frac integer, h_denom_pub bytea, ruuid bigint, reserve_sig bytea, h_coin_envelope bytea, denom_sig bytea, now bigint, OUT out_denom_unknown boolean, OUT out_nonce_reuse boolean, OUT out_conflict boolean) IS 'Stores information about a planchet for a batch withdraw operation. Checks if the planchet already exists, and in that case indicates a conflict';


--
-- Name: exchange_do_close_request(bytea, bigint, bytea); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.exchange_do_close_request(in_reserve_pub bytea, in_close_timestamp bigint, in_reserve_sig bytea, OUT out_final_balance_val bigint, OUT out_final_balance_frac integer, OUT out_balance_ok boolean, OUT out_conflict boolean) RETURNS record
    LANGUAGE plpgsql
    AS $$
BEGIN

  SELECT
    current_balance_val
   ,current_balance_frac
  INTO
    out_final_balance_val
   ,out_final_balance_frac
  FROM exchange.reserves
  WHERE reserve_pub=in_reserve_pub;

  IF NOT FOUND
  THEN
    out_final_balance_val=0;
    out_final_balance_frac=0;
    out_balance_ok = FALSE;
    out_conflict = FALSE;
  END IF;

  INSERT INTO exchange.close_requests
    (reserve_pub
    ,close_timestamp
    ,reserve_sig
    ,close_val
    ,close_frac)
    VALUES
    (in_reserve_pub
    ,in_close_timestamp
    ,in_reserve_sig
    ,out_final_balance_val
    ,out_final_balance_frac)
  ON CONFLICT DO NOTHING;
  out_conflict = NOT FOUND;

  UPDATE reserves SET
    current_balance_val=0
   ,current_balance_frac=0
  WHERE reserve_pub=in_reserve_pub;
  out_balance_ok = TRUE;

END $$;


--
-- Name: exchange_do_deposit(bigint, integer, bytea, bytea, bigint, bigint, bigint, bigint, bytea, character varying, bytea, bigint, bytea, bytea, bigint, boolean, character varying); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.exchange_do_deposit(in_amount_with_fee_val bigint, in_amount_with_fee_frac integer, in_h_contract_terms bytea, in_wire_salt bytea, in_wallet_timestamp bigint, in_exchange_timestamp bigint, in_refund_deadline bigint, in_wire_deadline bigint, in_merchant_pub bytea, in_receiver_wire_account character varying, in_h_payto bytea, in_known_coin_id bigint, in_coin_pub bytea, in_coin_sig bytea, in_shard bigint, in_extension_blocked boolean, in_extension_details character varying, OUT out_exchange_timestamp bigint, OUT out_balance_ok boolean, OUT out_conflict boolean) RETURNS record
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
  INSERT INTO exchange.extension_details
  (extension_options)
  VALUES
    (in_extension_details)
  RETURNING extension_details_serial_id INTO xdi;
ELSE
  xdi=NULL;
END IF;


INSERT INTO exchange.wire_targets
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
  FROM exchange.wire_targets
  WHERE wire_target_h_payto=in_h_payto;
END IF;


INSERT INTO exchange.deposits
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
   FROM exchange.deposits
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
-- Name: exchange_do_expire_purse(bigint, bigint); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.exchange_do_expire_purse(in_start_time bigint, in_end_time bigint, OUT out_found boolean) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
  my_purse_pub BYTEA;
DECLARE
  my_deposit record;
BEGIN

SELECT purse_pub
  INTO my_purse_pub
  FROM exchange.purse_requests
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

INSERT INTO exchange.purse_refunds
 (purse_pub)
 VALUES
 (my_purse_pub);

-- restore balance to each coin deposited into the purse
FOR my_deposit IN
  SELECT coin_pub
        ,amount_with_fee_val
        ,amount_with_fee_frac
    FROM exchange.purse_deposits
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
-- Name: FUNCTION exchange_do_expire_purse(in_start_time bigint, in_end_time bigint, OUT out_found boolean); Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON FUNCTION exchange.exchange_do_expire_purse(in_start_time bigint, in_end_time bigint, OUT out_found boolean) IS 'Finds an expired purse in the given time range and refunds the coins (if any).';


--
-- Name: exchange_do_gc(bigint, bigint); Type: PROCEDURE; Schema: exchange; Owner: -
--

CREATE PROCEDURE exchange.exchange_do_gc(in_ancient_date bigint, in_now bigint)
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

DELETE FROM exchange.prewire
  WHERE finished=TRUE;

DELETE FROM exchange.wire_fee
  WHERE end_date < in_ancient_date;

-- TODO: use closing fee as threshold?
DELETE FROM exchange.reserves
  WHERE gc_date < in_now
    AND current_balance_val = 0
    AND current_balance_frac = 0;

SELECT
     reserve_out_serial_id
  INTO
     reserve_out_min
  FROM exchange.reserves_out
  ORDER BY reserve_out_serial_id ASC
  LIMIT 1;

DELETE FROM exchange.recoup
  WHERE reserve_out_serial_id < reserve_out_min;
-- FIXME: recoup_refresh lacks GC!

SELECT
     reserve_uuid
  INTO
     reserve_uuid_min
  FROM exchange.reserves
  ORDER BY reserve_uuid ASC
  LIMIT 1;

DELETE FROM exchange.reserves_out
  WHERE reserve_uuid < reserve_uuid_min;

-- FIXME: this query will be horribly slow;
-- need to find another way to formulate it...
DELETE FROM exchange.denominations
  WHERE expire_legal < in_now
    AND denominations_serial NOT IN
      (SELECT DISTINCT denominations_serial
         FROM exchange.reserves_out)
    AND denominations_serial NOT IN
      (SELECT DISTINCT denominations_serial
         FROM exchange.known_coins
        WHERE coin_pub IN
          (SELECT DISTINCT coin_pub
             FROM exchange.recoup))
    AND denominations_serial NOT IN
      (SELECT DISTINCT denominations_serial
         FROM exchange.known_coins
        WHERE coin_pub IN
          (SELECT DISTINCT coin_pub
             FROM exchange.recoup_refresh));

SELECT
     melt_serial_id
  INTO
     melt_min
  FROM exchange.refresh_commitments
  ORDER BY melt_serial_id ASC
  LIMIT 1;

DELETE FROM exchange.refresh_revealed_coins
  WHERE melt_serial_id < melt_min;

DELETE FROM exchange.refresh_transfer_keys
  WHERE melt_serial_id < melt_min;

SELECT
     known_coin_id
  INTO
     coin_min
  FROM exchange.known_coins
  ORDER BY known_coin_id ASC
  LIMIT 1;

DELETE FROM exchange.deposits
  WHERE known_coin_id < coin_min;

SELECT
     deposit_serial_id
  INTO
     deposit_min
  FROM exchange.deposits
  ORDER BY deposit_serial_id ASC
  LIMIT 1;

DELETE FROM exchange.refunds
  WHERE deposit_serial_id < deposit_min;

DELETE FROM exchange.aggregation_tracking
  WHERE deposit_serial_id < deposit_min;

SELECT
     denominations_serial
  INTO
     denom_min
  FROM exchange.denominations
  ORDER BY denominations_serial ASC
  LIMIT 1;

DELETE FROM exchange.cs_nonce_locks
  WHERE max_denomination_serial <= denom_min;

END $$;


--
-- Name: exchange_do_history_request(bytea, bytea, bigint, bigint, integer); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.exchange_do_history_request(in_reserve_pub bytea, in_reserve_sig bytea, in_request_timestamp bigint, in_history_fee_val bigint, in_history_fee_frac integer, OUT out_balance_ok boolean, OUT out_idempotent boolean) RETURNS record
    LANGUAGE plpgsql
    AS $$
BEGIN

  -- Insert and check for idempotency.
  INSERT INTO exchange.history_requests
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
-- Name: exchange_do_melt(bytea, bigint, integer, bytea, bytea, bytea, bigint, integer, boolean); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.exchange_do_melt(in_cs_rms bytea, in_amount_with_fee_val bigint, in_amount_with_fee_frac integer, in_rc bytea, in_old_coin_pub bytea, in_old_coin_sig bytea, in_known_coin_id bigint, in_noreveal_index integer, in_zombie_required boolean, OUT out_balance_ok boolean, OUT out_zombie_bad boolean, OUT out_noreveal_index integer) RETURNS record
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

INSERT INTO exchange.refresh_commitments
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
    FROM exchange.refresh_commitments
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
    FROM exchange.recoup_refresh
   WHERE rrc_serial IN
    (SELECT rrc_serial
       FROM exchange.refresh_revealed_coins
      WHERE melt_serial_id IN
      (SELECT melt_serial_id
         FROM exchange.refresh_commitments
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
    FROM exchange.denominations
      ORDER BY denominations_serial DESC
      LIMIT 1;

  -- Cache CS signature to prevent replays in the future
  -- (and check if cached signature exists at the same time).
  INSERT INTO exchange.cs_nonce_locks
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
      FROM exchange.cs_nonce_locks
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
-- Name: exchange_do_purse_deposit(bigint, bytea, bigint, integer, bytea, bytea, bigint, integer); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.exchange_do_purse_deposit(in_partner_id bigint, in_purse_pub bytea, in_amount_with_fee_val bigint, in_amount_with_fee_frac integer, in_coin_pub bytea, in_coin_sig bytea, in_amount_without_fee_val bigint, in_amount_without_fee_frac integer, OUT out_balance_ok boolean, OUT out_conflict boolean) RETURNS record
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
INSERT INTO exchange.purse_deposits
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
  FROM exchange.purse_deposits
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
  FROM exchange.purse_merges
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
  FROM exchange.purse_requests
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
-- Name: exchange_do_purse_merge(bytea, bytea, bigint, bytea, character varying, bytea, bytea); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.exchange_do_purse_merge(in_purse_pub bytea, in_merge_sig bytea, in_merge_timestamp bigint, in_reserve_sig bytea, in_partner_url character varying, in_reserve_pub bytea, in_wallet_h_payto bytea, OUT out_no_partner boolean, OUT out_no_balance boolean, OUT out_no_reserve boolean, OUT out_conflict boolean) RETURNS record
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
  FROM exchange.partners
  WHERE partner_base_url=in_partner_url
    AND start_date <= in_merge_timestamp
    AND end_date > in_merge_timestamp;
  IF NOT FOUND
  THEN
    out_no_partner=TRUE;
    out_conflict=FALSE;
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
  FROM exchange.purse_requests
  WHERE purse_pub=in_purse_pub
    AND balance_val >= amount_with_fee_val
    AND ( (balance_frac >= amount_with_fee_frac) OR
          (balance_val > amount_with_fee_val) );
IF NOT FOUND
THEN
  out_no_balance=TRUE;
  out_conflict=FALSE;
  out_no_reserve=FALSE;
  RETURN;
END IF;
out_no_balance=FALSE;

-- Store purse merge signature, checks for purse_pub uniqueness
INSERT INTO exchange.purse_merges
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
  FROM exchange.purse_merges
  WHERE purse_pub=in_purse_pub
     AND merge_sig=in_merge_sig;
  IF NOT FOUND
  THEN
     -- Purse was merged, but to some other reserve. Not allowed.
     out_conflict=TRUE;
     out_no_reserve=FALSE;
     RETURN;
  END IF;

  -- "success"
  out_conflict=FALSE;
  out_no_reserve=FALSE;
  RETURN;
END IF;
out_conflict=FALSE;

ASSERT NOT my_finished, 'internal invariant failed';

PERFORM
   FROM exchange.reserves
  WHERE reserve_pub=in_reserve_pub;

IF NOT FOUND
THEN
  out_no_reserve=TRUE;
  RETURN;
END IF;
out_no_reserve=FALSE;


-- Store account merge signature.
INSERT INTO exchange.account_merges
  (reserve_pub
  ,reserve_sig
  ,purse_pub
  ,wallet_h_payto)
  VALUES
  (in_reserve_pub
  ,in_reserve_sig
  ,in_purse_pub
  ,in_wallet_h_payto);

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
-- Name: FUNCTION exchange_do_purse_merge(in_purse_pub bytea, in_merge_sig bytea, in_merge_timestamp bigint, in_reserve_sig bytea, in_partner_url character varying, in_reserve_pub bytea, in_wallet_h_payto bytea, OUT out_no_partner boolean, OUT out_no_balance boolean, OUT out_no_reserve boolean, OUT out_conflict boolean); Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON FUNCTION exchange.exchange_do_purse_merge(in_purse_pub bytea, in_merge_sig bytea, in_merge_timestamp bigint, in_reserve_sig bytea, in_partner_url character varying, in_reserve_pub bytea, in_wallet_h_payto bytea, OUT out_no_partner boolean, OUT out_no_balance boolean, OUT out_no_reserve boolean, OUT out_conflict boolean) IS 'Checks that the partner exists, the purse has not been merged with a different reserve and that the purse is full. If so, persists the merge data and either merges the purse with the reserve or marks it as ready for the taler-exchange-router. Caller MUST abort the transaction on failures so as to not persist data by accident.';


--
-- Name: exchange_do_recoup_by_reserve(bytea); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.exchange_do_recoup_by_reserve(res_pub bytea) RETURNS TABLE(denom_sig bytea, denominations_serial bigint, coin_pub bytea, coin_sig bytea, coin_blind bytea, amount_val bigint, amount_frac integer, recoup_timestamp bigint)
    LANGUAGE plpgsql
    AS $$
DECLARE
  res_uuid BIGINT;
  blind_ev BYTEA;
  c_pub    BYTEA;
BEGIN
  SELECT reserve_uuid
  INTO res_uuid
  FROM exchange.reserves
  WHERE reserves.reserve_pub = res_pub;

  FOR blind_ev IN
    SELECT h_blind_ev
      FROM exchange.reserves_out_by_reserve
    WHERE reserves_out_by_reserve.reserve_uuid = res_uuid
  LOOP
    SELECT robr.coin_pub
      INTO c_pub
      FROM exchange.recoup_by_reserve robr
    WHERE robr.reserve_out_serial_id = (
      SELECT reserves_out.reserve_out_serial_id
        FROM exchange.reserves_out
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
        FROM exchange.known_coins
        WHERE known_coins.coin_pub = c_pub
      ) kc
      JOIN (
        SELECT *
        FROM exchange.recoup
        WHERE recoup.coin_pub = c_pub
      ) rc USING (coin_pub);
  END LOOP;
END;
$$;


--
-- Name: FUNCTION exchange_do_recoup_by_reserve(res_pub bytea); Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON FUNCTION exchange.exchange_do_recoup_by_reserve(res_pub bytea) IS 'Recoup by reserve as a function to make sure we hit only the needed partition and not all when joining as joins on distributed tables fetch ALL rows from the shards';


--
-- Name: exchange_do_recoup_to_coin(bytea, bigint, bytea, bytea, bigint, bytea, bigint); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.exchange_do_recoup_to_coin(in_old_coin_pub bytea, in_rrc_serial bigint, in_coin_blind bytea, in_coin_pub bytea, in_known_coin_id bigint, in_coin_sig bytea, in_recoup_timestamp bigint, OUT out_recoup_ok boolean, OUT out_internal_failure boolean, OUT out_recoup_timestamp bigint) RETURNS record
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
FROM exchange.known_coins
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
    FROM exchange.recoup_refresh
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


INSERT INTO exchange.recoup_refresh
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
-- Name: exchange_do_recoup_to_reserve(bytea, bigint, bytea, bytea, bigint, bytea, bigint, bigint, bigint); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.exchange_do_recoup_to_reserve(in_reserve_pub bytea, in_reserve_out_serial_id bigint, in_coin_blind bytea, in_coin_pub bytea, in_known_coin_id bigint, in_coin_sig bytea, in_reserve_gc bigint, in_reserve_expiration bigint, in_recoup_timestamp bigint, OUT out_recoup_ok boolean, OUT out_internal_failure boolean, OUT out_recoup_timestamp bigint) RETURNS record
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
FROM exchange.known_coins
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
    FROM exchange.recoup
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


INSERT INTO exchange.recoup
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
-- Name: exchange_do_refund(bigint, integer, bigint, integer, bigint, integer, bytea, bigint, bigint, bigint, bytea, bytea, bytea); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.exchange_do_refund(in_amount_with_fee_val bigint, in_amount_with_fee_frac integer, in_amount_val bigint, in_amount_frac integer, in_deposit_fee_val bigint, in_deposit_fee_frac integer, in_h_contract_terms bytea, in_rtransaction_id bigint, in_deposit_shard bigint, in_known_coin_id bigint, in_coin_pub bytea, in_merchant_pub bytea, in_merchant_sig bytea, OUT out_not_found boolean, OUT out_refund_ok boolean, OUT out_gone boolean, OUT out_conflict boolean) RETURNS record
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
FROM exchange.deposits
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

INSERT INTO exchange.refunds
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
   FROM exchange.refunds
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
  FROM exchange.refunds
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
-- Name: exchange_do_reserve_purse(bytea, bytea, bigint, bytea, boolean, bigint, integer, bytea, bytea); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.exchange_do_reserve_purse(in_purse_pub bytea, in_merge_sig bytea, in_merge_timestamp bigint, in_reserve_sig bytea, in_reserve_quota boolean, in_purse_fee_val bigint, in_purse_fee_frac integer, in_reserve_pub bytea, in_wallet_h_payto bytea, OUT out_no_funds boolean, OUT out_no_reserve boolean, OUT out_conflict boolean) RETURNS record
    LANGUAGE plpgsql
    AS $$
BEGIN

-- Store purse merge signature, checks for purse_pub uniqueness
INSERT INTO exchange.purse_merges
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
  FROM exchange.purse_merges
  WHERE purse_pub=in_purse_pub
     AND merge_sig=in_merge_sig;
  IF NOT FOUND
  THEN
     -- Purse was merged, but to some other reserve. Not allowed.
     out_conflict=TRUE;
     out_no_reserve=FALSE;
     out_no_funds=FALSE;
     RETURN;
  END IF;

  -- "success"
  out_conflict=FALSE;
  out_no_funds=FALSE;
  out_no_reserve=FALSE;
  RETURN;
END IF;
out_conflict=FALSE;

PERFORM
  FROM exchange.reserves
 WHERE reserve_pub=in_reserve_pub;

IF NOT FOUND
THEN
  out_no_reserve=TRUE;
  out_no_funds=TRUE;
  RETURN;
END IF;
out_no_reserve=FALSE;

IF (in_reserve_quota)
THEN
  -- Increment active purses per reserve (and check this is allowed)
  UPDATE reserves
     SET purses_active=purses_active+1
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
INSERT INTO exchange.account_merges
  (reserve_pub
  ,reserve_sig
  ,purse_pub
  ,wallet_h_payto)
  VALUES
  (in_reserve_pub
  ,in_reserve_sig
  ,in_purse_pub
  ,in_wallet_h_payto);

END $$;


--
-- Name: FUNCTION exchange_do_reserve_purse(in_purse_pub bytea, in_merge_sig bytea, in_merge_timestamp bigint, in_reserve_sig bytea, in_reserve_quota boolean, in_purse_fee_val bigint, in_purse_fee_frac integer, in_reserve_pub bytea, in_wallet_h_payto bytea, OUT out_no_funds boolean, OUT out_no_reserve boolean, OUT out_conflict boolean); Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON FUNCTION exchange.exchange_do_reserve_purse(in_purse_pub bytea, in_merge_sig bytea, in_merge_timestamp bigint, in_reserve_sig bytea, in_reserve_quota boolean, in_purse_fee_val bigint, in_purse_fee_frac integer, in_reserve_pub bytea, in_wallet_h_payto bytea, OUT out_no_funds boolean, OUT out_no_reserve boolean, OUT out_conflict boolean) IS 'Create a purse for a reserve.';


--
-- Name: exchange_do_withdraw(bytea, bigint, integer, bytea, bytea, bytea, bytea, bytea, bigint, bigint); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.exchange_do_withdraw(cs_nonce bytea, amount_val bigint, amount_frac integer, h_denom_pub bytea, rpub bytea, reserve_sig bytea, h_coin_envelope bytea, denom_sig bytea, now bigint, min_reserve_gc bigint, OUT reserve_found boolean, OUT balance_ok boolean, OUT nonce_ok boolean, OUT ruuid bigint) RETURNS record
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
  FROM exchange.denominations
 WHERE denom_pub_hash=h_denom_pub;

IF NOT FOUND
THEN
  -- denomination unknown, should be impossible!
  reserve_found=FALSE;
  balance_ok=FALSE;
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
  FROM exchange.reserves
 WHERE reserves.reserve_pub=rpub;

IF NOT FOUND
THEN
  -- reserve unknown
  reserve_found=FALSE;
  balance_ok=FALSE;
  nonce_ok=TRUE;
  ruuid=2;
  RETURN;
END IF;

-- We optimistically insert, and then on conflict declare
-- the query successful due to idempotency.
INSERT INTO exchange.reserves_out
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
  nonce_ok=TRUE;
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
    nonce_ok=TRUE; -- we do not really know
    balance_ok=FALSE;
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
  INSERT INTO exchange.cs_nonce_locks
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
      FROM exchange.cs_nonce_locks
     WHERE nonce=cs_nonce
       AND op_hash=h_coin_envelope;
    IF NOT FOUND
    THEN
      reserve_found=FALSE;
      balance_ok=FALSE;
      nonce_ok=FALSE;
      RETURN;
    END IF;
  END IF;
ELSE
  nonce_ok=TRUE; -- no nonce, hence OK!
END IF;

END $$;


--
-- Name: FUNCTION exchange_do_withdraw(cs_nonce bytea, amount_val bigint, amount_frac integer, h_denom_pub bytea, rpub bytea, reserve_sig bytea, h_coin_envelope bytea, denom_sig bytea, now bigint, min_reserve_gc bigint, OUT reserve_found boolean, OUT balance_ok boolean, OUT nonce_ok boolean, OUT ruuid bigint); Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON FUNCTION exchange.exchange_do_withdraw(cs_nonce bytea, amount_val bigint, amount_frac integer, h_denom_pub bytea, rpub bytea, reserve_sig bytea, h_coin_envelope bytea, denom_sig bytea, now bigint, min_reserve_gc bigint, OUT reserve_found boolean, OUT balance_ok boolean, OUT nonce_ok boolean, OUT ruuid bigint) IS 'Checks whether the reserve has sufficient balance for a withdraw operation (or the request is repeated and was previously approved) and if so updates the database with the result';


--
-- Name: prepare_sharding(); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.prepare_sharding() RETURNS void
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
-- Name: purse_requests_insert_trigger(); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.purse_requests_insert_trigger() RETURNS trigger
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
-- Name: FUNCTION purse_requests_insert_trigger(); Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON FUNCTION exchange.purse_requests_insert_trigger() IS 'When a purse is created, insert it into the purse_action table to take action when the purse expires.';


--
-- Name: purse_requests_on_update_trigger(); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.purse_requests_on_update_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF (NEW.finished AND NOT OLD.finished)
  THEN
    IF (NEW.in_reserve_quota)
    THEN
      UPDATE reserves
         SET purses_active=purses_active-1
       WHERE reserve_pub IN
         (SELECT reserve_pub
            FROM exchange.purse_merges
           WHERE purse_pub=NEW.purse_pub
           LIMIT 1);
      NEW.in_reserve_quota=FALSE;
    END IF;
    DELETE FROM exchange.purse_actions
          WHERE purse_pub=NEW.purse_pub;
    RETURN NEW;
  END IF;
  RETURN NEW;
END $$;


--
-- Name: FUNCTION purse_requests_on_update_trigger(); Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON FUNCTION exchange.purse_requests_on_update_trigger() IS 'Trigger the router if the purse is ready. Also removes the entry from the router watchlist once the purse is finished.';


--
-- Name: recoup_delete_trigger(); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.recoup_delete_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  DELETE FROM exchange.recoup_by_reserve
   WHERE reserve_out_serial_id = OLD.reserve_out_serial_id
     AND coin_pub = OLD.coin_pub;
  RETURN OLD;
END $$;


--
-- Name: FUNCTION recoup_delete_trigger(); Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON FUNCTION exchange.recoup_delete_trigger() IS 'Replicate recoup deletions into recoup_by_reserve table.';


--
-- Name: recoup_insert_trigger(); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.recoup_insert_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  INSERT INTO exchange.recoup_by_reserve
    (reserve_out_serial_id
    ,coin_pub)
  VALUES
    (NEW.reserve_out_serial_id
    ,NEW.coin_pub);
  RETURN NEW;
END $$;


--
-- Name: FUNCTION recoup_insert_trigger(); Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON FUNCTION exchange.recoup_insert_trigger() IS 'Replicate recoup inserts into recoup_by_reserve table.';


--
-- Name: reserves_out_by_reserve_delete_trigger(); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.reserves_out_by_reserve_delete_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  DELETE FROM exchange.reserves_out_by_reserve
   WHERE reserve_uuid = OLD.reserve_uuid;
  RETURN OLD;
END $$;


--
-- Name: FUNCTION reserves_out_by_reserve_delete_trigger(); Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON FUNCTION exchange.reserves_out_by_reserve_delete_trigger() IS 'Replicate reserve_out deletions into reserve_out_by_reserve table.';


--
-- Name: reserves_out_by_reserve_insert_trigger(); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.reserves_out_by_reserve_insert_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  INSERT INTO exchange.reserves_out_by_reserve
    (reserve_uuid
    ,h_blind_ev)
  VALUES
    (NEW.reserve_uuid
    ,NEW.h_blind_ev);
  RETURN NEW;
END $$;


--
-- Name: FUNCTION reserves_out_by_reserve_insert_trigger(); Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON FUNCTION exchange.reserves_out_by_reserve_insert_trigger() IS 'Replicate reserve_out inserts into reserve_out_by_reserve table.';


--
-- Name: wire_out_delete_trigger(); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.wire_out_delete_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  DELETE FROM exchange.aggregation_tracking
   WHERE wtid_raw = OLD.wtid_raw;
  RETURN OLD;
END $$;


--
-- Name: FUNCTION wire_out_delete_trigger(); Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON FUNCTION exchange.wire_out_delete_trigger() IS 'Replicate reserve_out deletions into aggregation_tracking. This replaces an earlier use of an ON DELETE CASCADE that required a DEFERRABLE constraint and conflicted with nice partitioning.';


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
-- Name: auditor_balance_summary; Type: TABLE; Schema: auditor; Owner: -
--

CREATE TABLE auditor.auditor_balance_summary (
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
-- Name: TABLE auditor_balance_summary; Type: COMMENT; Schema: auditor; Owner: -
--

COMMENT ON TABLE auditor.auditor_balance_summary IS 'the sum of the outstanding coins from auditor_denomination_pending (denom_pubs must belong to the respectives exchange master public key); it represents the auditor_balance_summary of the exchange at this point (modulo unexpected historic_loss-style events where denomination keys are compromised)';


--
-- Name: auditor_denomination_pending; Type: TABLE; Schema: auditor; Owner: -
--

CREATE TABLE auditor.auditor_denomination_pending (
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
-- Name: TABLE auditor_denomination_pending; Type: COMMENT; Schema: auditor; Owner: -
--

COMMENT ON TABLE auditor.auditor_denomination_pending IS 'outstanding denomination coins that the exchange is aware of and what the respective balances are (outstanding as well as issued overall which implies the maximum value at risk).';


--
-- Name: COLUMN auditor_denomination_pending.num_issued; Type: COMMENT; Schema: auditor; Owner: -
--

COMMENT ON COLUMN auditor.auditor_denomination_pending.num_issued IS 'counts the number of coins issued (withdraw, refresh) of this denomination';


--
-- Name: COLUMN auditor_denomination_pending.denom_risk_val; Type: COMMENT; Schema: auditor; Owner: -
--

COMMENT ON COLUMN auditor.auditor_denomination_pending.denom_risk_val IS 'amount that could theoretically be lost in the future due to recoup operations';


--
-- Name: COLUMN auditor_denomination_pending.recoup_loss_val; Type: COMMENT; Schema: auditor; Owner: -
--

COMMENT ON COLUMN auditor.auditor_denomination_pending.recoup_loss_val IS 'amount actually lost due to recoup operations past revocation';


--
-- Name: auditor_exchange_signkeys; Type: TABLE; Schema: auditor; Owner: -
--

CREATE TABLE auditor.auditor_exchange_signkeys (
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
-- Name: TABLE auditor_exchange_signkeys; Type: COMMENT; Schema: auditor; Owner: -
--

COMMENT ON TABLE auditor.auditor_exchange_signkeys IS 'list of the online signing keys of exchanges we are auditing';


--
-- Name: auditor_exchanges; Type: TABLE; Schema: auditor; Owner: -
--

CREATE TABLE auditor.auditor_exchanges (
    master_pub bytea NOT NULL,
    exchange_url character varying NOT NULL,
    CONSTRAINT auditor_exchanges_master_pub_check CHECK ((length(master_pub) = 32))
);


--
-- Name: TABLE auditor_exchanges; Type: COMMENT; Schema: auditor; Owner: -
--

COMMENT ON TABLE auditor.auditor_exchanges IS 'list of the exchanges we are auditing';


--
-- Name: auditor_historic_denomination_revenue; Type: TABLE; Schema: auditor; Owner: -
--

CREATE TABLE auditor.auditor_historic_denomination_revenue (
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
-- Name: TABLE auditor_historic_denomination_revenue; Type: COMMENT; Schema: auditor; Owner: -
--

COMMENT ON TABLE auditor.auditor_historic_denomination_revenue IS 'Table with historic profits; basically, when a denom_pub has expired and everything associated with it is garbage collected, the final profits end up in here; note that the denom_pub here is not a foreign key, we just keep it as a reference point.';


--
-- Name: COLUMN auditor_historic_denomination_revenue.revenue_balance_val; Type: COMMENT; Schema: auditor; Owner: -
--

COMMENT ON COLUMN auditor.auditor_historic_denomination_revenue.revenue_balance_val IS 'the sum of all of the profits we made on the coin except for withdraw fees (which are in historic_reserve_revenue); so this includes the deposit, melt and refund fees';


--
-- Name: auditor_historic_reserve_summary; Type: TABLE; Schema: auditor; Owner: -
--

CREATE TABLE auditor.auditor_historic_reserve_summary (
    master_pub bytea NOT NULL,
    start_date bigint NOT NULL,
    end_date bigint NOT NULL,
    reserve_profits_val bigint NOT NULL,
    reserve_profits_frac integer NOT NULL
);


--
-- Name: TABLE auditor_historic_reserve_summary; Type: COMMENT; Schema: auditor; Owner: -
--

COMMENT ON TABLE auditor.auditor_historic_reserve_summary IS 'historic profits from reserves; we eventually GC auditor_historic_reserve_revenue, and then store the totals in here (by time intervals).';


--
-- Name: auditor_predicted_result; Type: TABLE; Schema: auditor; Owner: -
--

CREATE TABLE auditor.auditor_predicted_result (
    master_pub bytea NOT NULL,
    balance_val bigint NOT NULL,
    balance_frac integer NOT NULL,
    drained_val bigint NOT NULL,
    drained_frac integer NOT NULL
);


--
-- Name: TABLE auditor_predicted_result; Type: COMMENT; Schema: auditor; Owner: -
--

COMMENT ON TABLE auditor.auditor_predicted_result IS 'Table with the sum of the ledger, auditor_historic_revenue and the auditor_reserve_balance and the drained profits.  This is the final amount that the exchange should have in its bank account right now (and the total amount drained as profits to non-escrow accounts).';


--
-- Name: auditor_progress_aggregation; Type: TABLE; Schema: auditor; Owner: -
--

CREATE TABLE auditor.auditor_progress_aggregation (
    master_pub bytea NOT NULL,
    last_wire_out_serial_id bigint DEFAULT 0 NOT NULL
);


--
-- Name: TABLE auditor_progress_aggregation; Type: COMMENT; Schema: auditor; Owner: -
--

COMMENT ON TABLE auditor.auditor_progress_aggregation IS 'information as to which transactions the auditor has processed in the exchange database.  Used for SELECTing the
 statements to process.  The indices include the last serial ID from the respective tables that we have processed. Thus, we need to select those table entries that are strictly larger (and process in monotonically increasing order).';


--
-- Name: auditor_progress_coin; Type: TABLE; Schema: auditor; Owner: -
--

CREATE TABLE auditor.auditor_progress_coin (
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
-- Name: TABLE auditor_progress_coin; Type: COMMENT; Schema: auditor; Owner: -
--

COMMENT ON TABLE auditor.auditor_progress_coin IS 'information as to which transactions the auditor has processed in the exchange database.  Used for SELECTing the
 statements to process.  The indices include the last serial ID from the respective tables that we have processed. Thus, we need to select those table entries that are strictly larger (and process in monotonically increasing order).';


--
-- Name: auditor_progress_deposit_confirmation; Type: TABLE; Schema: auditor; Owner: -
--

CREATE TABLE auditor.auditor_progress_deposit_confirmation (
    master_pub bytea NOT NULL,
    last_deposit_confirmation_serial_id bigint DEFAULT 0 NOT NULL
);


--
-- Name: TABLE auditor_progress_deposit_confirmation; Type: COMMENT; Schema: auditor; Owner: -
--

COMMENT ON TABLE auditor.auditor_progress_deposit_confirmation IS 'information as to which transactions the auditor has processed in the exchange database.  Used for SELECTing the
 statements to process.  The indices include the last serial ID from the respective tables that we have processed. Thus, we need to select those table entries that are strictly larger (and process in monotonically increasing order).';


--
-- Name: auditor_progress_reserve; Type: TABLE; Schema: auditor; Owner: -
--

CREATE TABLE auditor.auditor_progress_reserve (
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
-- Name: TABLE auditor_progress_reserve; Type: COMMENT; Schema: auditor; Owner: -
--

COMMENT ON TABLE auditor.auditor_progress_reserve IS 'information as to which transactions the auditor has processed in the exchange database.  Used for SELECTing the
 statements to process.  The indices include the last serial ID from the respective tables that we have processed. Thus, we need to select those table entries that are strictly larger (and process in monotonically increasing order).';


--
-- Name: auditor_reserve_balance; Type: TABLE; Schema: auditor; Owner: -
--

CREATE TABLE auditor.auditor_reserve_balance (
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
-- Name: TABLE auditor_reserve_balance; Type: COMMENT; Schema: auditor; Owner: -
--

COMMENT ON TABLE auditor.auditor_reserve_balance IS 'sum of the balances of all customer reserves (by exchange master public key)';


--
-- Name: auditor_reserves; Type: TABLE; Schema: auditor; Owner: -
--

CREATE TABLE auditor.auditor_reserves (
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
-- Name: TABLE auditor_reserves; Type: COMMENT; Schema: auditor; Owner: -
--

COMMENT ON TABLE auditor.auditor_reserves IS 'all of the customer reserves and their respective balances that the auditor is aware of';


--
-- Name: auditor_reserves_auditor_reserves_rowid_seq; Type: SEQUENCE; Schema: auditor; Owner: -
--

CREATE SEQUENCE auditor.auditor_reserves_auditor_reserves_rowid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: auditor_reserves_auditor_reserves_rowid_seq; Type: SEQUENCE OWNED BY; Schema: auditor; Owner: -
--

ALTER SEQUENCE auditor.auditor_reserves_auditor_reserves_rowid_seq OWNED BY auditor.auditor_reserves.auditor_reserves_rowid;


--
-- Name: auditor_wire_fee_balance; Type: TABLE; Schema: auditor; Owner: -
--

CREATE TABLE auditor.auditor_wire_fee_balance (
    master_pub bytea NOT NULL,
    wire_fee_balance_val bigint NOT NULL,
    wire_fee_balance_frac integer NOT NULL
);


--
-- Name: TABLE auditor_wire_fee_balance; Type: COMMENT; Schema: auditor; Owner: -
--

COMMENT ON TABLE auditor.auditor_wire_fee_balance IS 'sum of the balances of all wire fees (by exchange master public key)';


--
-- Name: deposit_confirmations; Type: TABLE; Schema: auditor; Owner: -
--

CREATE TABLE auditor.deposit_confirmations (
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
-- Name: TABLE deposit_confirmations; Type: COMMENT; Schema: auditor; Owner: -
--

COMMENT ON TABLE auditor.deposit_confirmations IS 'deposit confirmation sent to us by merchants; we must check that the exchange reported these properly.';


--
-- Name: deposit_confirmations_serial_id_seq; Type: SEQUENCE; Schema: auditor; Owner: -
--

CREATE SEQUENCE auditor.deposit_confirmations_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: deposit_confirmations_serial_id_seq; Type: SEQUENCE OWNED BY; Schema: auditor; Owner: -
--

ALTER SEQUENCE auditor.deposit_confirmations_serial_id_seq OWNED BY auditor.deposit_confirmations.serial_id;


--
-- Name: wire_auditor_account_progress; Type: TABLE; Schema: auditor; Owner: -
--

CREATE TABLE auditor.wire_auditor_account_progress (
    master_pub bytea NOT NULL,
    account_name text NOT NULL,
    last_wire_reserve_in_serial_id bigint DEFAULT 0 NOT NULL,
    last_wire_wire_out_serial_id bigint DEFAULT 0 NOT NULL,
    wire_in_off bigint NOT NULL,
    wire_out_off bigint NOT NULL
);


--
-- Name: TABLE wire_auditor_account_progress; Type: COMMENT; Schema: auditor; Owner: -
--

COMMENT ON TABLE auditor.wire_auditor_account_progress IS 'information as to which transactions the auditor has processed in the exchange database.  Used for SELECTing the
 statements to process.  The indices include the last serial ID from the respective tables that we have processed. Thus, we need to select those table entries that are strictly larger (and process in monotonically increasing order).';


--
-- Name: wire_auditor_progress; Type: TABLE; Schema: auditor; Owner: -
--

CREATE TABLE auditor.wire_auditor_progress (
    master_pub bytea NOT NULL,
    last_timestamp bigint NOT NULL,
    last_reserve_close_uuid bigint NOT NULL
);


--
-- Name: account_merges; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.account_merges (
    account_merge_request_serial_id bigint NOT NULL,
    reserve_pub bytea NOT NULL,
    reserve_sig bytea NOT NULL,
    purse_pub bytea NOT NULL,
    wallet_h_payto bytea NOT NULL,
    CONSTRAINT account_merges_purse_pub_check CHECK ((length(purse_pub) = 32)),
    CONSTRAINT account_merges_reserve_pub_check CHECK ((length(reserve_pub) = 32)),
    CONSTRAINT account_merges_reserve_sig_check CHECK ((length(reserve_sig) = 64)),
    CONSTRAINT account_merges_wallet_h_payto_check CHECK ((length(wallet_h_payto) = 32))
)
PARTITION BY HASH (purse_pub);


--
-- Name: TABLE account_merges; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.account_merges IS 'Merge requests where a purse- and account-owner requested merging the purse into the account';


--
-- Name: COLUMN account_merges.reserve_pub; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.account_merges.reserve_pub IS 'public key of the target reserve';


--
-- Name: COLUMN account_merges.reserve_sig; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.account_merges.reserve_sig IS 'signature by the reserve private key affirming the merge, of type TALER_SIGNATURE_WALLET_ACCOUNT_MERGE';


--
-- Name: COLUMN account_merges.purse_pub; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.account_merges.purse_pub IS 'public key of the purse';


--
-- Name: account_merges_account_merge_request_serial_id_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.account_merges ALTER COLUMN account_merge_request_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.account_merges_account_merge_request_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: account_merges_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.account_merges_default (
    account_merge_request_serial_id bigint NOT NULL,
    reserve_pub bytea NOT NULL,
    reserve_sig bytea NOT NULL,
    purse_pub bytea NOT NULL,
    wallet_h_payto bytea NOT NULL,
    CONSTRAINT account_merges_purse_pub_check CHECK ((length(purse_pub) = 32)),
    CONSTRAINT account_merges_reserve_pub_check CHECK ((length(reserve_pub) = 32)),
    CONSTRAINT account_merges_reserve_sig_check CHECK ((length(reserve_sig) = 64)),
    CONSTRAINT account_merges_wallet_h_payto_check CHECK ((length(wallet_h_payto) = 32))
);
ALTER TABLE ONLY exchange.account_merges ATTACH PARTITION exchange.account_merges_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: aggregation_tracking; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.aggregation_tracking (
    aggregation_serial_id bigint NOT NULL,
    deposit_serial_id bigint NOT NULL,
    wtid_raw bytea NOT NULL
)
PARTITION BY HASH (deposit_serial_id);


--
-- Name: TABLE aggregation_tracking; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.aggregation_tracking IS 'mapping from wire transfer identifiers (WTID) to deposits (and back)';


--
-- Name: COLUMN aggregation_tracking.wtid_raw; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.aggregation_tracking.wtid_raw IS 'identifier of the wire transfer';


--
-- Name: aggregation_tracking_aggregation_serial_id_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.aggregation_tracking ALTER COLUMN aggregation_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.aggregation_tracking_aggregation_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: aggregation_tracking_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.aggregation_tracking_default (
    aggregation_serial_id bigint NOT NULL,
    deposit_serial_id bigint NOT NULL,
    wtid_raw bytea NOT NULL
);
ALTER TABLE ONLY exchange.aggregation_tracking ATTACH PARTITION exchange.aggregation_tracking_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: aggregation_transient; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.aggregation_transient (
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    wire_target_h_payto bytea,
    merchant_pub bytea,
    exchange_account_section text NOT NULL,
    wtid_raw bytea NOT NULL,
    CONSTRAINT aggregation_transient_merchant_pub_check CHECK ((length(merchant_pub) = 32)),
    CONSTRAINT aggregation_transient_wire_target_h_payto_check CHECK ((length(wire_target_h_payto) = 32)),
    CONSTRAINT aggregation_transient_wtid_raw_check CHECK ((length(wtid_raw) = 32))
)
PARTITION BY HASH (wire_target_h_payto);


--
-- Name: TABLE aggregation_transient; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.aggregation_transient IS 'aggregations currently happening (lacking wire_out, usually because the amount is too low); this table is not replicated';


--
-- Name: COLUMN aggregation_transient.amount_val; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.aggregation_transient.amount_val IS 'Sum of all of the aggregated deposits (without deposit fees)';


--
-- Name: COLUMN aggregation_transient.wtid_raw; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.aggregation_transient.wtid_raw IS 'identifier of the wire transfer';


--
-- Name: aggregation_transient_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.aggregation_transient_default (
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    wire_target_h_payto bytea,
    merchant_pub bytea,
    exchange_account_section text NOT NULL,
    wtid_raw bytea NOT NULL,
    CONSTRAINT aggregation_transient_merchant_pub_check CHECK ((length(merchant_pub) = 32)),
    CONSTRAINT aggregation_transient_wire_target_h_payto_check CHECK ((length(wire_target_h_payto) = 32)),
    CONSTRAINT aggregation_transient_wtid_raw_check CHECK ((length(wtid_raw) = 32))
);
ALTER TABLE ONLY exchange.aggregation_transient ATTACH PARTITION exchange.aggregation_transient_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: auditor_denom_sigs; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.auditor_denom_sigs (
    auditor_denom_serial bigint NOT NULL,
    auditor_uuid bigint NOT NULL,
    denominations_serial bigint NOT NULL,
    auditor_sig bytea,
    CONSTRAINT auditor_denom_sigs_auditor_sig_check CHECK ((length(auditor_sig) = 64))
);


--
-- Name: TABLE auditor_denom_sigs; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.auditor_denom_sigs IS 'Table with auditor signatures on exchange denomination keys.';


--
-- Name: COLUMN auditor_denom_sigs.auditor_uuid; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.auditor_denom_sigs.auditor_uuid IS 'Identifies the auditor.';


--
-- Name: COLUMN auditor_denom_sigs.denominations_serial; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.auditor_denom_sigs.denominations_serial IS 'Denomination the signature is for.';


--
-- Name: COLUMN auditor_denom_sigs.auditor_sig; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.auditor_denom_sigs.auditor_sig IS 'Signature of the auditor, of purpose TALER_SIGNATURE_AUDITOR_EXCHANGE_KEYS.';


--
-- Name: auditor_denom_sigs_auditor_denom_serial_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.auditor_denom_sigs ALTER COLUMN auditor_denom_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.auditor_denom_sigs_auditor_denom_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: auditors; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.auditors (
    auditor_uuid bigint NOT NULL,
    auditor_pub bytea NOT NULL,
    auditor_name character varying NOT NULL,
    auditor_url character varying NOT NULL,
    is_active boolean NOT NULL,
    last_change bigint NOT NULL,
    CONSTRAINT auditors_auditor_pub_check CHECK ((length(auditor_pub) = 32))
);


--
-- Name: TABLE auditors; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.auditors IS 'Table with auditors the exchange uses or has used in the past. Entries never expire as we need to remember the last_change column indefinitely.';


--
-- Name: COLUMN auditors.auditor_pub; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.auditors.auditor_pub IS 'Public key of the auditor.';


--
-- Name: COLUMN auditors.auditor_url; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.auditors.auditor_url IS 'The base URL of the auditor.';


--
-- Name: COLUMN auditors.is_active; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.auditors.is_active IS 'true if we are currently supporting the use of this auditor.';


--
-- Name: COLUMN auditors.last_change; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.auditors.last_change IS 'Latest time when active status changed. Used to detect replays of old messages.';


--
-- Name: auditors_auditor_uuid_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.auditors ALTER COLUMN auditor_uuid ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.auditors_auditor_uuid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: close_requests; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.close_requests (
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
-- Name: TABLE close_requests; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.close_requests IS 'Explicit requests by a reserve owner to close a reserve immediately';


--
-- Name: COLUMN close_requests.close_timestamp; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.close_requests.close_timestamp IS 'When the request was created by the client';


--
-- Name: COLUMN close_requests.reserve_sig; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.close_requests.reserve_sig IS 'Signature affirming that the reserve is to be closed';


--
-- Name: COLUMN close_requests.close_val; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.close_requests.close_val IS 'Balance of the reserve at the time of closing, to be wired to the associated bank account (minus the closing fee)';


--
-- Name: close_requests_close_request_serial_id_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.close_requests ALTER COLUMN close_request_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.close_requests_close_request_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: close_requests_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.close_requests_default (
    close_request_serial_id bigint NOT NULL,
    reserve_pub bytea NOT NULL,
    close_timestamp bigint NOT NULL,
    reserve_sig bytea NOT NULL,
    close_val bigint NOT NULL,
    close_frac integer NOT NULL,
    CONSTRAINT close_requests_reserve_pub_check CHECK ((length(reserve_pub) = 32)),
    CONSTRAINT close_requests_reserve_sig_check CHECK ((length(reserve_sig) = 64))
);
ALTER TABLE ONLY exchange.close_requests ATTACH PARTITION exchange.close_requests_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: contracts; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.contracts (
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
-- Name: TABLE contracts; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.contracts IS 'encrypted contracts associated with purses';


--
-- Name: COLUMN contracts.purse_pub; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.contracts.purse_pub IS 'public key of the purse that the contract is associated with';


--
-- Name: COLUMN contracts.pub_ckey; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.contracts.pub_ckey IS 'Public ECDH key used to encrypt the contract, to be used with the purse private key for decryption';


--
-- Name: COLUMN contracts.contract_sig; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.contracts.contract_sig IS 'signature over the encrypted contract by the purse contract key';


--
-- Name: COLUMN contracts.e_contract; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.contracts.e_contract IS 'AES-GCM encrypted contract terms (contains gzip compressed JSON after decryption)';


--
-- Name: contracts_contract_serial_id_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.contracts ALTER COLUMN contract_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.contracts_contract_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: contracts_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.contracts_default (
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
ALTER TABLE ONLY exchange.contracts ATTACH PARTITION exchange.contracts_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: cs_nonce_locks; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.cs_nonce_locks (
    cs_nonce_lock_serial_id bigint NOT NULL,
    nonce bytea NOT NULL,
    op_hash bytea NOT NULL,
    max_denomination_serial bigint NOT NULL,
    CONSTRAINT cs_nonce_locks_nonce_check CHECK ((length(nonce) = 32)),
    CONSTRAINT cs_nonce_locks_op_hash_check CHECK ((length(op_hash) = 64))
)
PARTITION BY HASH (nonce);


--
-- Name: TABLE cs_nonce_locks; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.cs_nonce_locks IS 'ensures a Clause Schnorr client nonce is locked for use with an operation identified by a hash';


--
-- Name: COLUMN cs_nonce_locks.nonce; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.cs_nonce_locks.nonce IS 'actual nonce submitted by the client';


--
-- Name: COLUMN cs_nonce_locks.op_hash; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.cs_nonce_locks.op_hash IS 'hash (RC for refresh, blind coin hash for withdraw) the nonce may be used with';


--
-- Name: COLUMN cs_nonce_locks.max_denomination_serial; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.cs_nonce_locks.max_denomination_serial IS 'Maximum number of a CS denomination serial the nonce could be used with, for GC';


--
-- Name: cs_nonce_locks_cs_nonce_lock_serial_id_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.cs_nonce_locks ALTER COLUMN cs_nonce_lock_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.cs_nonce_locks_cs_nonce_lock_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: cs_nonce_locks_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.cs_nonce_locks_default (
    cs_nonce_lock_serial_id bigint NOT NULL,
    nonce bytea NOT NULL,
    op_hash bytea NOT NULL,
    max_denomination_serial bigint NOT NULL,
    CONSTRAINT cs_nonce_locks_nonce_check CHECK ((length(nonce) = 32)),
    CONSTRAINT cs_nonce_locks_op_hash_check CHECK ((length(op_hash) = 64))
);
ALTER TABLE ONLY exchange.cs_nonce_locks ATTACH PARTITION exchange.cs_nonce_locks_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: denomination_revocations; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.denomination_revocations (
    denom_revocations_serial_id bigint NOT NULL,
    denominations_serial bigint NOT NULL,
    master_sig bytea NOT NULL,
    CONSTRAINT denomination_revocations_master_sig_check CHECK ((length(master_sig) = 64))
);


--
-- Name: TABLE denomination_revocations; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.denomination_revocations IS 'remembering which denomination keys have been revoked';


--
-- Name: denomination_revocations_denom_revocations_serial_id_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.denomination_revocations ALTER COLUMN denom_revocations_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.denomination_revocations_denom_revocations_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: denominations; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.denominations (
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
-- Name: TABLE denominations; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.denominations IS 'Main denominations table. All the valid denominations the exchange knows about.';


--
-- Name: COLUMN denominations.denominations_serial; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.denominations.denominations_serial IS 'needed for exchange-auditor replication logic';


--
-- Name: COLUMN denominations.denom_type; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.denominations.denom_type IS 'determines cipher type for blind signatures used with this denomination; 0 is for RSA';


--
-- Name: COLUMN denominations.age_mask; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.denominations.age_mask IS 'bitmask with the age restrictions that are being used for this denomination; 0 if denomination does not support the use of age restrictions';


--
-- Name: denominations_denominations_serial_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.denominations ALTER COLUMN denominations_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.denominations_denominations_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: deposits; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.deposits (
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
-- Name: TABLE deposits; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.deposits IS 'Deposits we have received and for which we need to make (aggregate) wire transfers (and manage refunds).';


--
-- Name: COLUMN deposits.shard; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.deposits.shard IS 'Used for load sharding in the materialized indices. Should be set based on merchant_pub. 64-bit value because we need an *unsigned* 32-bit value.';


--
-- Name: COLUMN deposits.known_coin_id; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.deposits.known_coin_id IS 'Used for garbage collection';


--
-- Name: COLUMN deposits.wire_salt; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.deposits.wire_salt IS 'Salt used when hashing the payto://-URI to get the h_wire';


--
-- Name: COLUMN deposits.wire_target_h_payto; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.deposits.wire_target_h_payto IS 'Identifies the target bank account and KYC status';


--
-- Name: COLUMN deposits.done; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.deposits.done IS 'Set to TRUE once we have included this deposit in some aggregate wire transfer to the merchant';


--
-- Name: COLUMN deposits.extension_blocked; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.deposits.extension_blocked IS 'True if the aggregation of the deposit is currently blocked by some extension mechanism. Used to filter out deposits that must not be processed by the canonical deposit logic.';


--
-- Name: COLUMN deposits.extension_details_serial_id; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.deposits.extension_details_serial_id IS 'References extensions table, NULL if extensions are not used';


--
-- Name: deposits_by_ready; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.deposits_by_ready (
    wire_deadline bigint NOT NULL,
    shard bigint NOT NULL,
    coin_pub bytea NOT NULL,
    deposit_serial_id bigint,
    CONSTRAINT deposits_by_ready_coin_pub_check CHECK ((length(coin_pub) = 32))
)
PARTITION BY RANGE (wire_deadline);


--
-- Name: TABLE deposits_by_ready; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.deposits_by_ready IS 'Enables fast lookups for deposits_get_ready, auto-populated via TRIGGER below';


--
-- Name: deposits_by_ready_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.deposits_by_ready_default (
    wire_deadline bigint NOT NULL,
    shard bigint NOT NULL,
    coin_pub bytea NOT NULL,
    deposit_serial_id bigint,
    CONSTRAINT deposits_by_ready_coin_pub_check CHECK ((length(coin_pub) = 32))
);
ALTER TABLE ONLY exchange.deposits_by_ready ATTACH PARTITION exchange.deposits_by_ready_default DEFAULT;


--
-- Name: deposits_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.deposits_default (
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
ALTER TABLE ONLY exchange.deposits ATTACH PARTITION exchange.deposits_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: deposits_deposit_serial_id_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.deposits ALTER COLUMN deposit_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.deposits_deposit_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: deposits_for_matching; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.deposits_for_matching (
    refund_deadline bigint NOT NULL,
    merchant_pub bytea NOT NULL,
    coin_pub bytea NOT NULL,
    deposit_serial_id bigint,
    CONSTRAINT deposits_for_matching_coin_pub_check CHECK ((length(coin_pub) = 32)),
    CONSTRAINT deposits_for_matching_merchant_pub_check CHECK ((length(merchant_pub) = 32))
)
PARTITION BY RANGE (refund_deadline);


--
-- Name: TABLE deposits_for_matching; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.deposits_for_matching IS 'Enables fast lookups for deposits_iterate_matching, auto-populated via TRIGGER below';


--
-- Name: deposits_for_matching_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.deposits_for_matching_default (
    refund_deadline bigint NOT NULL,
    merchant_pub bytea NOT NULL,
    coin_pub bytea NOT NULL,
    deposit_serial_id bigint,
    CONSTRAINT deposits_for_matching_coin_pub_check CHECK ((length(coin_pub) = 32)),
    CONSTRAINT deposits_for_matching_merchant_pub_check CHECK ((length(merchant_pub) = 32))
);
ALTER TABLE ONLY exchange.deposits_for_matching ATTACH PARTITION exchange.deposits_for_matching_default DEFAULT;


--
-- Name: exchange_sign_keys; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.exchange_sign_keys (
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
-- Name: TABLE exchange_sign_keys; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.exchange_sign_keys IS 'Table with master public key signatures on exchange online signing keys.';


--
-- Name: COLUMN exchange_sign_keys.exchange_pub; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.exchange_sign_keys.exchange_pub IS 'Public online signing key of the exchange.';


--
-- Name: COLUMN exchange_sign_keys.master_sig; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.exchange_sign_keys.master_sig IS 'Signature affirming the validity of the signing key of purpose TALER_SIGNATURE_MASTER_SIGNING_KEY_VALIDITY.';


--
-- Name: COLUMN exchange_sign_keys.valid_from; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.exchange_sign_keys.valid_from IS 'Time when this online signing key will first be used to sign messages.';


--
-- Name: COLUMN exchange_sign_keys.expire_sign; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.exchange_sign_keys.expire_sign IS 'Time when this online signing key will no longer be used to sign.';


--
-- Name: COLUMN exchange_sign_keys.expire_legal; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.exchange_sign_keys.expire_legal IS 'Time when this online signing key legally expires.';


--
-- Name: exchange_sign_keys_esk_serial_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.exchange_sign_keys ALTER COLUMN esk_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.exchange_sign_keys_esk_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: extension_details; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.extension_details (
    extension_details_serial_id bigint NOT NULL,
    extension_options character varying
)
PARTITION BY HASH (extension_details_serial_id);


--
-- Name: TABLE extension_details; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.extension_details IS 'Extensions that were provided with deposits (not yet used).';


--
-- Name: COLUMN extension_details.extension_options; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.extension_details.extension_options IS 'JSON object with options set that the exchange needs to consider when executing a deposit. Supported details depend on the extensions supported by the exchange.';


--
-- Name: extension_details_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.extension_details_default (
    extension_details_serial_id bigint NOT NULL,
    extension_options character varying
);
ALTER TABLE ONLY exchange.extension_details ATTACH PARTITION exchange.extension_details_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: extension_details_extension_details_serial_id_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.extension_details ALTER COLUMN extension_details_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.extension_details_extension_details_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: extensions; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.extensions (
    extension_id bigint NOT NULL,
    name character varying NOT NULL,
    config bytea
);


--
-- Name: TABLE extensions; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.extensions IS 'Configurations of the activated extensions';


--
-- Name: COLUMN extensions.name; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.extensions.name IS 'Name of the extension';


--
-- Name: COLUMN extensions.config; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.extensions.config IS 'Configuration of the extension as JSON-blob, maybe NULL';


--
-- Name: extensions_extension_id_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.extensions ALTER COLUMN extension_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.extensions_extension_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: global_fee; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.global_fee (
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
-- Name: TABLE global_fee; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.global_fee IS 'list of the global fees of this exchange, by date';


--
-- Name: COLUMN global_fee.global_fee_serial; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.global_fee.global_fee_serial IS 'needed for exchange-auditor replication logic';


--
-- Name: global_fee_global_fee_serial_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.global_fee ALTER COLUMN global_fee_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.global_fee_global_fee_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: history_requests; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.history_requests (
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
-- Name: TABLE history_requests; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.history_requests IS 'Paid history requests issued by a client against a reserve';


--
-- Name: COLUMN history_requests.request_timestamp; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.history_requests.request_timestamp IS 'When was the history request made';


--
-- Name: COLUMN history_requests.reserve_sig; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.history_requests.reserve_sig IS 'Signature approving payment for the history request';


--
-- Name: COLUMN history_requests.history_fee_val; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.history_requests.history_fee_val IS 'History fee approved by the signature';


--
-- Name: history_requests_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.history_requests_default (
    history_request_serial_id bigint NOT NULL,
    reserve_pub bytea NOT NULL,
    request_timestamp bigint NOT NULL,
    reserve_sig bytea NOT NULL,
    history_fee_val bigint NOT NULL,
    history_fee_frac integer NOT NULL,
    CONSTRAINT history_requests_reserve_pub_check CHECK ((length(reserve_pub) = 32)),
    CONSTRAINT history_requests_reserve_sig_check CHECK ((length(reserve_sig) = 64))
);
ALTER TABLE ONLY exchange.history_requests ATTACH PARTITION exchange.history_requests_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: history_requests_history_request_serial_id_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.history_requests ALTER COLUMN history_request_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.history_requests_history_request_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: known_coins; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.known_coins (
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
-- Name: TABLE known_coins; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.known_coins IS 'information about coins and their signatures, so we do not have to store the signatures more than once if a coin is involved in multiple operations';


--
-- Name: COLUMN known_coins.denominations_serial; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.known_coins.denominations_serial IS 'Denomination of the coin, determines the value of the original coin and applicable fees for coin-specific operations.';


--
-- Name: COLUMN known_coins.coin_pub; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.known_coins.coin_pub IS 'EdDSA public key of the coin';


--
-- Name: COLUMN known_coins.age_commitment_hash; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.known_coins.age_commitment_hash IS 'Optional hash of the age commitment for age restrictions as per DD 24 (active if denom_type has the respective bit set)';


--
-- Name: COLUMN known_coins.denom_sig; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.known_coins.denom_sig IS 'This is the signature of the exchange that affirms that the coin is a valid coin. The specific signature type depends on denom_type of the denomination.';


--
-- Name: COLUMN known_coins.remaining_val; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.known_coins.remaining_val IS 'Value of the coin that remains to be spent';


--
-- Name: known_coins_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.known_coins_default (
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
ALTER TABLE ONLY exchange.known_coins ATTACH PARTITION exchange.known_coins_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: known_coins_known_coin_id_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.known_coins ALTER COLUMN known_coin_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.known_coins_known_coin_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: kyc_alerts; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.kyc_alerts (
    h_payto bytea NOT NULL,
    trigger_type integer NOT NULL,
    CONSTRAINT kyc_alerts_h_payto_check CHECK ((length(h_payto) = 32))
);


--
-- Name: TABLE kyc_alerts; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.kyc_alerts IS 'alerts about completed KYC events reliably notifying other components (even if they are not running)';


--
-- Name: COLUMN kyc_alerts.h_payto; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.kyc_alerts.h_payto IS 'hash of the payto://-URI for which the KYC status changed';


--
-- Name: COLUMN kyc_alerts.trigger_type; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.kyc_alerts.trigger_type IS 'identifies the receiver of the alert, as the same h_payto may require multiple components to be notified';


--
-- Name: legitimizations; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.legitimizations (
    legitimization_serial_id bigint NOT NULL,
    h_payto bytea NOT NULL,
    expiration_time bigint DEFAULT 0 NOT NULL,
    provider_section character varying NOT NULL,
    provider_user_id character varying,
    provider_legitimization_id character varying,
    CONSTRAINT legitimizations_h_payto_check CHECK ((length(h_payto) = 32))
)
PARTITION BY HASH (h_payto);


--
-- Name: TABLE legitimizations; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.legitimizations IS 'List of legitimizations (required and completed) by account and provider';


--
-- Name: COLUMN legitimizations.legitimization_serial_id; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.legitimizations.legitimization_serial_id IS 'unique ID for this legitimization process at the exchange';


--
-- Name: COLUMN legitimizations.h_payto; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.legitimizations.h_payto IS 'foreign key linking the entry to the wire_targets table, NOT a primary key (multiple legitimizations are possible per wire target)';


--
-- Name: COLUMN legitimizations.expiration_time; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.legitimizations.expiration_time IS 'in the future if the respective KYC check was passed successfully';


--
-- Name: COLUMN legitimizations.provider_section; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.legitimizations.provider_section IS 'Configuration file section with details about this provider';


--
-- Name: COLUMN legitimizations.provider_user_id; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.legitimizations.provider_user_id IS 'Identifier for the user at the provider that was used for the legitimization. NULL if provider is unaware.';


--
-- Name: COLUMN legitimizations.provider_legitimization_id; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.legitimizations.provider_legitimization_id IS 'Identifier for the specific legitimization process at the provider. NULL if legitimization was not started.';


--
-- Name: legitimizations_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.legitimizations_default (
    legitimization_serial_id bigint NOT NULL,
    h_payto bytea NOT NULL,
    expiration_time bigint DEFAULT 0 NOT NULL,
    provider_section character varying NOT NULL,
    provider_user_id character varying,
    provider_legitimization_id character varying,
    CONSTRAINT legitimizations_h_payto_check CHECK ((length(h_payto) = 32))
);
ALTER TABLE ONLY exchange.legitimizations ATTACH PARTITION exchange.legitimizations_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: legitimizations_legitimization_serial_id_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.legitimizations ALTER COLUMN legitimization_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.legitimizations_legitimization_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: partner_accounts; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.partner_accounts (
    payto_uri character varying NOT NULL,
    partner_serial_id bigint,
    partner_master_sig bytea,
    last_seen bigint NOT NULL,
    CONSTRAINT partner_accounts_partner_master_sig_check CHECK ((length(partner_master_sig) = 64))
);


--
-- Name: TABLE partner_accounts; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.partner_accounts IS 'Table with bank accounts of the partner exchange. Entries never expire as we need to remember the signature for the auditor.';


--
-- Name: COLUMN partner_accounts.payto_uri; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.partner_accounts.payto_uri IS 'payto URI (RFC 8905) with the bank account of the partner exchange.';


--
-- Name: COLUMN partner_accounts.partner_master_sig; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.partner_accounts.partner_master_sig IS 'Signature of purpose TALER_SIGNATURE_MASTER_WIRE_DETAILS by the partner master public key';


--
-- Name: COLUMN partner_accounts.last_seen; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.partner_accounts.last_seen IS 'Last time we saw this account as being active at the partner exchange. Used to select the most recent entry, and to detect when we should check again.';


--
-- Name: partners; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.partners (
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
-- Name: TABLE partners; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.partners IS 'exchanges we do wad transfers to';


--
-- Name: COLUMN partners.partner_master_pub; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.partners.partner_master_pub IS 'offline master public key of the partner';


--
-- Name: COLUMN partners.start_date; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.partners.start_date IS 'starting date of the partnership';


--
-- Name: COLUMN partners.end_date; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.partners.end_date IS 'end date of the partnership';


--
-- Name: COLUMN partners.next_wad; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.partners.next_wad IS 'at what time should we do the next wad transfer to this partner (frequently updated); set to forever after the end_date';


--
-- Name: COLUMN partners.wad_frequency; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.partners.wad_frequency IS 'how often do we promise to do wad transfers';


--
-- Name: COLUMN partners.wad_fee_val; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.partners.wad_fee_val IS 'how high is the fee for a wallet to be added to a wad to this partner';


--
-- Name: COLUMN partners.master_sig; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.partners.master_sig IS 'signature of our master public key affirming the partnership, of purpose TALER_SIGNATURE_MASTER_PARTNER_DETAILS';


--
-- Name: COLUMN partners.partner_base_url; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.partners.partner_base_url IS 'base URL of the REST API for this partner';


--
-- Name: partners_partner_serial_id_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.partners ALTER COLUMN partner_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.partners_partner_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: prewire; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.prewire (
    prewire_uuid bigint NOT NULL,
    wire_method text NOT NULL,
    finished boolean DEFAULT false NOT NULL,
    failed boolean DEFAULT false NOT NULL,
    buf bytea NOT NULL
)
PARTITION BY HASH (prewire_uuid);


--
-- Name: TABLE prewire; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.prewire IS 'pre-commit data for wire transfers we are about to execute';


--
-- Name: COLUMN prewire.finished; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.prewire.finished IS 'set to TRUE once bank confirmed receiving the wire transfer request';


--
-- Name: COLUMN prewire.failed; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.prewire.failed IS 'set to TRUE if the bank responded with a non-transient failure to our transfer request';


--
-- Name: COLUMN prewire.buf; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.prewire.buf IS 'serialized data to send to the bank to execute the wire transfer';


--
-- Name: prewire_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.prewire_default (
    prewire_uuid bigint NOT NULL,
    wire_method text NOT NULL,
    finished boolean DEFAULT false NOT NULL,
    failed boolean DEFAULT false NOT NULL,
    buf bytea NOT NULL
);
ALTER TABLE ONLY exchange.prewire ATTACH PARTITION exchange.prewire_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: prewire_prewire_uuid_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.prewire ALTER COLUMN prewire_uuid ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.prewire_prewire_uuid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: profit_drains; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.profit_drains (
    profit_drain_serial_id bigint NOT NULL,
    wtid bytea NOT NULL,
    account_section character varying NOT NULL,
    payto_uri character varying NOT NULL,
    trigger_date bigint NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac bigint NOT NULL,
    master_sig bytea NOT NULL,
    executed boolean DEFAULT false NOT NULL,
    CONSTRAINT profit_drains_master_sig_check CHECK ((length(master_sig) = 64)),
    CONSTRAINT profit_drains_wtid_check CHECK ((length(wtid) = 32))
);


--
-- Name: TABLE profit_drains; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.profit_drains IS 'transactions to be performed to move profits from the escrow account of the exchange to a regular account';


--
-- Name: COLUMN profit_drains.wtid; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.profit_drains.wtid IS 'randomly chosen nonce, unique to prevent double-submission';


--
-- Name: COLUMN profit_drains.account_section; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.profit_drains.account_section IS 'specifies the configuration section in the taler-exchange-drain configuration with the wire account to drain';


--
-- Name: COLUMN profit_drains.payto_uri; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.profit_drains.payto_uri IS 'specifies the account to be credited';


--
-- Name: COLUMN profit_drains.trigger_date; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.profit_drains.trigger_date IS 'set by taler-exchange-offline at the time of making the signature; not necessarily the exact date of execution of the wire transfer, just for orientation';


--
-- Name: COLUMN profit_drains.amount_val; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.profit_drains.amount_val IS 'amount to be transferred';


--
-- Name: COLUMN profit_drains.master_sig; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.profit_drains.master_sig IS 'EdDSA signature of type TALER_SIGNATURE_MASTER_DRAIN_PROFIT';


--
-- Name: COLUMN profit_drains.executed; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.profit_drains.executed IS 'set to TRUE by taler-exchange-drain on execution of the transaction, not replicated to auditor';


--
-- Name: profit_drains_profit_drain_serial_id_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.profit_drains ALTER COLUMN profit_drain_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.profit_drains_profit_drain_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: purse_actions; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.purse_actions (
    purse_pub bytea NOT NULL,
    action_date bigint NOT NULL,
    partner_serial_id bigint,
    CONSTRAINT purse_actions_purse_pub_check CHECK ((length(purse_pub) = 32))
);


--
-- Name: TABLE purse_actions; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.purse_actions IS 'purses awaiting some action by the router';


--
-- Name: COLUMN purse_actions.purse_pub; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.purse_actions.purse_pub IS 'public (contract) key of the purse';


--
-- Name: COLUMN purse_actions.action_date; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.purse_actions.action_date IS 'when is the purse ready for action';


--
-- Name: COLUMN purse_actions.partner_serial_id; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.purse_actions.partner_serial_id IS 'wad target of an outgoing wire transfer, 0 for local, NULL if the purse is unmerged and thus the target is still unknown';


--
-- Name: purse_deposits; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.purse_deposits (
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
-- Name: TABLE purse_deposits; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.purse_deposits IS 'Requests depositing coins into a purse';


--
-- Name: COLUMN purse_deposits.partner_serial_id; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.purse_deposits.partner_serial_id IS 'identifies the partner exchange, NULL in case the target purse lives at this exchange';


--
-- Name: COLUMN purse_deposits.purse_pub; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.purse_deposits.purse_pub IS 'Public key of the purse';


--
-- Name: COLUMN purse_deposits.coin_pub; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.purse_deposits.coin_pub IS 'Public key of the coin being deposited';


--
-- Name: COLUMN purse_deposits.amount_with_fee_val; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.purse_deposits.amount_with_fee_val IS 'Total amount being deposited';


--
-- Name: COLUMN purse_deposits.coin_sig; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.purse_deposits.coin_sig IS 'Signature of the coin affirming the deposit into the purse, of type TALER_SIGNATURE_PURSE_DEPOSIT';


--
-- Name: purse_deposits_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.purse_deposits_default (
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
ALTER TABLE ONLY exchange.purse_deposits ATTACH PARTITION exchange.purse_deposits_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: purse_deposits_purse_deposit_serial_id_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.purse_deposits ALTER COLUMN purse_deposit_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.purse_deposits_purse_deposit_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: purse_merges; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.purse_merges (
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
-- Name: TABLE purse_merges; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.purse_merges IS 'Merge requests where a purse-owner requested merging the purse into the account';


--
-- Name: COLUMN purse_merges.partner_serial_id; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.purse_merges.partner_serial_id IS 'identifies the partner exchange, NULL in case the target reserve lives at this exchange';


--
-- Name: COLUMN purse_merges.reserve_pub; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.purse_merges.reserve_pub IS 'public key of the target reserve';


--
-- Name: COLUMN purse_merges.purse_pub; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.purse_merges.purse_pub IS 'public key of the purse';


--
-- Name: COLUMN purse_merges.merge_sig; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.purse_merges.merge_sig IS 'signature by the purse private key affirming the merge, of type TALER_SIGNATURE_WALLET_PURSE_MERGE';


--
-- Name: COLUMN purse_merges.merge_timestamp; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.purse_merges.merge_timestamp IS 'when was the merge message signed';


--
-- Name: purse_merges_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.purse_merges_default (
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
ALTER TABLE ONLY exchange.purse_merges ATTACH PARTITION exchange.purse_merges_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: purse_merges_purse_merge_request_serial_id_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.purse_merges ALTER COLUMN purse_merge_request_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.purse_merges_purse_merge_request_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: purse_refunds; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.purse_refunds (
    purse_refunds_serial_id bigint NOT NULL,
    purse_pub bytea NOT NULL,
    CONSTRAINT purse_refunds_purse_pub_check CHECK ((length(purse_pub) = 32))
)
PARTITION BY HASH (purse_pub);


--
-- Name: TABLE purse_refunds; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.purse_refunds IS 'Purses that were refunded due to expiration';


--
-- Name: COLUMN purse_refunds.purse_pub; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.purse_refunds.purse_pub IS 'Public key of the purse';


--
-- Name: purse_refunds_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.purse_refunds_default (
    purse_refunds_serial_id bigint NOT NULL,
    purse_pub bytea NOT NULL,
    CONSTRAINT purse_refunds_purse_pub_check CHECK ((length(purse_pub) = 32))
);
ALTER TABLE ONLY exchange.purse_refunds ATTACH PARTITION exchange.purse_refunds_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: purse_refunds_purse_refunds_serial_id_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.purse_refunds ALTER COLUMN purse_refunds_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.purse_refunds_purse_refunds_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: purse_requests; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.purse_requests (
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
-- Name: TABLE purse_requests; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.purse_requests IS 'Requests establishing purses, associating them with a contract but without a target reserve';


--
-- Name: COLUMN purse_requests.purse_pub; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.purse_requests.purse_pub IS 'Public key of the purse';


--
-- Name: COLUMN purse_requests.purse_creation; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.purse_requests.purse_creation IS 'Local time when the purse was created. Determines applicable purse fees.';


--
-- Name: COLUMN purse_requests.purse_expiration; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.purse_requests.purse_expiration IS 'When the purse is set to expire';


--
-- Name: COLUMN purse_requests.h_contract_terms; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.purse_requests.h_contract_terms IS 'Hash of the contract the parties are to agree to';


--
-- Name: COLUMN purse_requests.flags; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.purse_requests.flags IS 'see the enum TALER_WalletAccountMergeFlags';


--
-- Name: COLUMN purse_requests.refunded; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.purse_requests.refunded IS 'set to TRUE if the purse could not be merged and thus all deposited coins were refunded';


--
-- Name: COLUMN purse_requests.finished; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.purse_requests.finished IS 'set to TRUE once the purse has been merged (into reserve or wad) or the coins were refunded (transfer aborted)';


--
-- Name: COLUMN purse_requests.in_reserve_quota; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.purse_requests.in_reserve_quota IS 'set to TRUE if this purse currently counts against the number of free purses in the respective reserve';


--
-- Name: COLUMN purse_requests.amount_with_fee_val; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.purse_requests.amount_with_fee_val IS 'Total amount expected to be in the purse';


--
-- Name: COLUMN purse_requests.purse_fee_val; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.purse_requests.purse_fee_val IS 'Purse fee the client agreed to pay from the reserve (accepted by the exchange at the time the purse was created). Zero if in_reserve_quota is TRUE.';


--
-- Name: COLUMN purse_requests.balance_val; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.purse_requests.balance_val IS 'Total amount actually in the purse';


--
-- Name: COLUMN purse_requests.purse_sig; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.purse_requests.purse_sig IS 'Signature of the purse affirming the purse parameters, of type TALER_SIGNATURE_PURSE_REQUEST';


--
-- Name: purse_requests_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.purse_requests_default (
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
ALTER TABLE ONLY exchange.purse_requests ATTACH PARTITION exchange.purse_requests_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: purse_requests_purse_requests_serial_id_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.purse_requests ALTER COLUMN purse_requests_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.purse_requests_purse_requests_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: recoup; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.recoup (
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
-- Name: TABLE recoup; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.recoup IS 'Information about recoups that were executed between a coin and a reserve. In this type of recoup, the amount is credited back to the reserve from which the coin originated.';


--
-- Name: COLUMN recoup.coin_pub; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.recoup.coin_pub IS 'Coin that is being debited in the recoup. Do not CASCADE ON DROP on the coin_pub, as we may keep the coin alive!';


--
-- Name: COLUMN recoup.coin_sig; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.recoup.coin_sig IS 'Signature by the coin affirming the recoup, of type TALER_SIGNATURE_WALLET_COIN_RECOUP';


--
-- Name: COLUMN recoup.coin_blind; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.recoup.coin_blind IS 'Denomination blinding key used when creating the blinded coin from the planchet. Secret revealed during the recoup to provide the linkage between the coin and the withdraw operation.';


--
-- Name: COLUMN recoup.reserve_out_serial_id; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.recoup.reserve_out_serial_id IS 'Identifies the h_blind_ev of the recouped coin and provides the link to the credited reserve.';


--
-- Name: recoup_by_reserve; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.recoup_by_reserve (
    reserve_out_serial_id bigint NOT NULL,
    coin_pub bytea,
    CONSTRAINT recoup_by_reserve_coin_pub_check CHECK ((length(coin_pub) = 32))
)
PARTITION BY HASH (reserve_out_serial_id);


--
-- Name: TABLE recoup_by_reserve; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.recoup_by_reserve IS 'Information in this table is strictly redundant with that of recoup, but saved by a different primary key for fast lookups by reserve_out_serial_id.';


--
-- Name: recoup_by_reserve_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.recoup_by_reserve_default (
    reserve_out_serial_id bigint NOT NULL,
    coin_pub bytea,
    CONSTRAINT recoup_by_reserve_coin_pub_check CHECK ((length(coin_pub) = 32))
);
ALTER TABLE ONLY exchange.recoup_by_reserve ATTACH PARTITION exchange.recoup_by_reserve_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: recoup_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.recoup_default (
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
ALTER TABLE ONLY exchange.recoup ATTACH PARTITION exchange.recoup_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: recoup_recoup_uuid_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.recoup ALTER COLUMN recoup_uuid ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.recoup_recoup_uuid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: recoup_refresh; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.recoup_refresh (
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
-- Name: TABLE recoup_refresh; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.recoup_refresh IS 'Table of coins that originated from a refresh operation and that were recouped. Links the (fresh) coin to the melted operation (and thus the old coin). A recoup on a refreshed coin credits the old coin and debits the fresh coin.';


--
-- Name: COLUMN recoup_refresh.coin_pub; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.recoup_refresh.coin_pub IS 'Refreshed coin of a revoked denomination where the residual value is credited to the old coin. Do not CASCADE ON DROP on the coin_pub, as we may keep the coin alive!';


--
-- Name: COLUMN recoup_refresh.known_coin_id; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.recoup_refresh.known_coin_id IS 'FIXME: (To be) used for garbage collection (in the future)';


--
-- Name: COLUMN recoup_refresh.coin_blind; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.recoup_refresh.coin_blind IS 'Denomination blinding key used when creating the blinded coin from the planchet. Secret revealed during the recoup to provide the linkage between the coin and the refresh operation.';


--
-- Name: COLUMN recoup_refresh.rrc_serial; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.recoup_refresh.rrc_serial IS 'Link to the refresh operation. Also identifies the h_blind_ev of the recouped coin (as h_coin_ev).';


--
-- Name: recoup_refresh_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.recoup_refresh_default (
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
ALTER TABLE ONLY exchange.recoup_refresh ATTACH PARTITION exchange.recoup_refresh_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: recoup_refresh_recoup_refresh_uuid_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.recoup_refresh ALTER COLUMN recoup_refresh_uuid ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.recoup_refresh_recoup_refresh_uuid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: refresh_commitments; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.refresh_commitments (
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
-- Name: TABLE refresh_commitments; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.refresh_commitments IS 'Commitments made when melting coins and the gamma value chosen by the exchange.';


--
-- Name: COLUMN refresh_commitments.rc; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.refresh_commitments.rc IS 'Commitment made by the client, hash over the various client inputs in the cut-and-choose protocol';


--
-- Name: COLUMN refresh_commitments.old_coin_pub; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.refresh_commitments.old_coin_pub IS 'Coin being melted in the refresh process.';


--
-- Name: COLUMN refresh_commitments.noreveal_index; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.refresh_commitments.noreveal_index IS 'The gamma value chosen by the exchange in the cut-and-choose protocol';


--
-- Name: refresh_commitments_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.refresh_commitments_default (
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
ALTER TABLE ONLY exchange.refresh_commitments ATTACH PARTITION exchange.refresh_commitments_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: refresh_commitments_melt_serial_id_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.refresh_commitments ALTER COLUMN melt_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.refresh_commitments_melt_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: refresh_revealed_coins; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.refresh_revealed_coins (
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
-- Name: TABLE refresh_revealed_coins; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.refresh_revealed_coins IS 'Revelations about the new coins that are to be created during a melting session.';


--
-- Name: COLUMN refresh_revealed_coins.rrc_serial; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.refresh_revealed_coins.rrc_serial IS 'needed for exchange-auditor replication logic';


--
-- Name: COLUMN refresh_revealed_coins.melt_serial_id; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.refresh_revealed_coins.melt_serial_id IS 'Identifies the refresh commitment (rc) of the melt operation.';


--
-- Name: COLUMN refresh_revealed_coins.freshcoin_index; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.refresh_revealed_coins.freshcoin_index IS 'index of the fresh coin being created (one melt operation may result in multiple fresh coins)';


--
-- Name: COLUMN refresh_revealed_coins.coin_ev; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.refresh_revealed_coins.coin_ev IS 'envelope of the new coin to be signed';


--
-- Name: COLUMN refresh_revealed_coins.h_coin_ev; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.refresh_revealed_coins.h_coin_ev IS 'hash of the envelope of the new coin to be signed (for lookups)';


--
-- Name: COLUMN refresh_revealed_coins.ev_sig; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.refresh_revealed_coins.ev_sig IS 'exchange signature over the envelope';


--
-- Name: COLUMN refresh_revealed_coins.ewv; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.refresh_revealed_coins.ewv IS 'exchange contributed values in the creation of the fresh coin (see /csr)';


--
-- Name: refresh_revealed_coins_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.refresh_revealed_coins_default (
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
ALTER TABLE ONLY exchange.refresh_revealed_coins ATTACH PARTITION exchange.refresh_revealed_coins_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: refresh_revealed_coins_rrc_serial_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.refresh_revealed_coins ALTER COLUMN rrc_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.refresh_revealed_coins_rrc_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: refresh_transfer_keys; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.refresh_transfer_keys (
    rtc_serial bigint NOT NULL,
    melt_serial_id bigint NOT NULL,
    transfer_pub bytea NOT NULL,
    transfer_privs bytea NOT NULL,
    CONSTRAINT refresh_transfer_keys_transfer_pub_check CHECK ((length(transfer_pub) = 32))
)
PARTITION BY HASH (melt_serial_id);


--
-- Name: TABLE refresh_transfer_keys; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.refresh_transfer_keys IS 'Transfer keys of a refresh operation (the data revealed to the exchange).';


--
-- Name: COLUMN refresh_transfer_keys.rtc_serial; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.refresh_transfer_keys.rtc_serial IS 'needed for exchange-auditor replication logic';


--
-- Name: COLUMN refresh_transfer_keys.melt_serial_id; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.refresh_transfer_keys.melt_serial_id IS 'Identifies the refresh commitment (rc) of the operation.';


--
-- Name: COLUMN refresh_transfer_keys.transfer_pub; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.refresh_transfer_keys.transfer_pub IS 'transfer public key for the gamma index';


--
-- Name: COLUMN refresh_transfer_keys.transfer_privs; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.refresh_transfer_keys.transfer_privs IS 'array of TALER_CNC_KAPPA - 1 transfer private keys that have been revealed, with the gamma entry being skipped';


--
-- Name: refresh_transfer_keys_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.refresh_transfer_keys_default (
    rtc_serial bigint NOT NULL,
    melt_serial_id bigint NOT NULL,
    transfer_pub bytea NOT NULL,
    transfer_privs bytea NOT NULL,
    CONSTRAINT refresh_transfer_keys_transfer_pub_check CHECK ((length(transfer_pub) = 32))
);
ALTER TABLE ONLY exchange.refresh_transfer_keys ATTACH PARTITION exchange.refresh_transfer_keys_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: refresh_transfer_keys_rtc_serial_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.refresh_transfer_keys ALTER COLUMN rtc_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.refresh_transfer_keys_rtc_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: refunds; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.refunds (
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
-- Name: TABLE refunds; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.refunds IS 'Data on coins that were refunded. Technically, refunds always apply against specific deposit operations involving a coin. The combination of coin_pub, merchant_pub, h_contract_terms and rtransaction_id MUST be unique, and we usually select by coin_pub so that one goes first.';


--
-- Name: COLUMN refunds.deposit_serial_id; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.refunds.deposit_serial_id IS 'Identifies ONLY the merchant_pub, h_contract_terms and coin_pub. Multiple deposits may match a refund, this only identifies one of them.';


--
-- Name: COLUMN refunds.rtransaction_id; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.refunds.rtransaction_id IS 'used by the merchant to make refunds unique in case the same coin for the same deposit gets a subsequent (higher) refund';


--
-- Name: refunds_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.refunds_default (
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
ALTER TABLE ONLY exchange.refunds ATTACH PARTITION exchange.refunds_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: refunds_refund_serial_id_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.refunds ALTER COLUMN refund_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.refunds_refund_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: reserves; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.reserves (
    reserve_uuid bigint NOT NULL,
    reserve_pub bytea NOT NULL,
    current_balance_val bigint DEFAULT 0 NOT NULL,
    current_balance_frac integer DEFAULT 0 NOT NULL,
    purses_active bigint DEFAULT 0 NOT NULL,
    purses_allowed bigint DEFAULT 0 NOT NULL,
    max_age integer DEFAULT 120 NOT NULL,
    expiration_date bigint NOT NULL,
    gc_date bigint NOT NULL,
    CONSTRAINT reserves_reserve_pub_check CHECK ((length(reserve_pub) = 32))
)
PARTITION BY HASH (reserve_pub);


--
-- Name: TABLE reserves; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.reserves IS 'Summarizes the balance of a reserve. Updated when new funds are added or withdrawn.';


--
-- Name: COLUMN reserves.reserve_pub; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.reserves.reserve_pub IS 'EdDSA public key of the reserve. Knowledge of the private key implies ownership over the balance.';


--
-- Name: COLUMN reserves.current_balance_val; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.reserves.current_balance_val IS 'Current balance remaining with the reserve.';


--
-- Name: COLUMN reserves.purses_active; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.reserves.purses_active IS 'Number of purses that were created by this reserve that are not expired and not fully paid.';


--
-- Name: COLUMN reserves.purses_allowed; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.reserves.purses_allowed IS 'Number of purses that this reserve is allowed to have active at most.';


--
-- Name: COLUMN reserves.expiration_date; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.reserves.expiration_date IS 'Used to trigger closing of reserves that have not been drained after some time';


--
-- Name: COLUMN reserves.gc_date; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.reserves.gc_date IS 'Used to forget all information about a reserve during garbage collection';


--
-- Name: reserves_close; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.reserves_close (
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
-- Name: TABLE reserves_close; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.reserves_close IS 'wire transfers executed by the reserve to close reserves';


--
-- Name: COLUMN reserves_close.wire_target_h_payto; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.reserves_close.wire_target_h_payto IS 'Identifies the credited bank account (and KYC status). Note that closing does not depend on KYC.';


--
-- Name: reserves_close_close_uuid_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.reserves_close ALTER COLUMN close_uuid ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.reserves_close_close_uuid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: reserves_close_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.reserves_close_default (
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
ALTER TABLE ONLY exchange.reserves_close ATTACH PARTITION exchange.reserves_close_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: reserves_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.reserves_default (
    reserve_uuid bigint NOT NULL,
    reserve_pub bytea NOT NULL,
    current_balance_val bigint DEFAULT 0 NOT NULL,
    current_balance_frac integer DEFAULT 0 NOT NULL,
    purses_active bigint DEFAULT 0 NOT NULL,
    purses_allowed bigint DEFAULT 0 NOT NULL,
    max_age integer DEFAULT 120 NOT NULL,
    expiration_date bigint NOT NULL,
    gc_date bigint NOT NULL,
    CONSTRAINT reserves_reserve_pub_check CHECK ((length(reserve_pub) = 32))
);
ALTER TABLE ONLY exchange.reserves ATTACH PARTITION exchange.reserves_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: reserves_in; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.reserves_in (
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
-- Name: TABLE reserves_in; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.reserves_in IS 'list of transfers of funds into the reserves, one per incoming wire transfer';


--
-- Name: COLUMN reserves_in.reserve_pub; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.reserves_in.reserve_pub IS 'Public key of the reserve. Private key signifies ownership of the remaining balance.';


--
-- Name: COLUMN reserves_in.credit_val; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.reserves_in.credit_val IS 'Amount that was transferred into the reserve';


--
-- Name: COLUMN reserves_in.wire_source_h_payto; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.reserves_in.wire_source_h_payto IS 'Identifies the debited bank account and KYC status';


--
-- Name: reserves_in_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.reserves_in_default (
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
ALTER TABLE ONLY exchange.reserves_in ATTACH PARTITION exchange.reserves_in_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: reserves_in_reserve_in_serial_id_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.reserves_in ALTER COLUMN reserve_in_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.reserves_in_reserve_in_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: reserves_out; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.reserves_out (
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
-- Name: TABLE reserves_out; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.reserves_out IS 'Withdraw operations performed on reserves.';


--
-- Name: COLUMN reserves_out.h_blind_ev; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.reserves_out.h_blind_ev IS 'Hash of the blinded coin, used as primary key here so that broken clients that use a non-random coin or blinding factor fail to withdraw (otherwise they would fail on deposit when the coin is not unique there).';


--
-- Name: COLUMN reserves_out.denominations_serial; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.reserves_out.denominations_serial IS 'We do not CASCADE ON DELETE here, we may keep the denomination data alive';


--
-- Name: reserves_out_by_reserve; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.reserves_out_by_reserve (
    reserve_uuid bigint NOT NULL,
    h_blind_ev bytea,
    CONSTRAINT reserves_out_by_reserve_h_blind_ev_check CHECK ((length(h_blind_ev) = 64))
)
PARTITION BY HASH (reserve_uuid);


--
-- Name: TABLE reserves_out_by_reserve; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.reserves_out_by_reserve IS 'Information in this table is strictly redundant with that of reserves_out, but saved by a different primary key for fast lookups by reserve public key/uuid.';


--
-- Name: reserves_out_by_reserve_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.reserves_out_by_reserve_default (
    reserve_uuid bigint NOT NULL,
    h_blind_ev bytea,
    CONSTRAINT reserves_out_by_reserve_h_blind_ev_check CHECK ((length(h_blind_ev) = 64))
);
ALTER TABLE ONLY exchange.reserves_out_by_reserve ATTACH PARTITION exchange.reserves_out_by_reserve_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: reserves_out_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.reserves_out_default (
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
ALTER TABLE ONLY exchange.reserves_out ATTACH PARTITION exchange.reserves_out_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: reserves_out_reserve_out_serial_id_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.reserves_out ALTER COLUMN reserve_out_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.reserves_out_reserve_out_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: reserves_reserve_uuid_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.reserves ALTER COLUMN reserve_uuid ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.reserves_reserve_uuid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: revolving_work_shards; Type: TABLE; Schema: exchange; Owner: -
--

CREATE UNLOGGED TABLE exchange.revolving_work_shards (
    shard_serial_id bigint NOT NULL,
    last_attempt bigint NOT NULL,
    start_row integer NOT NULL,
    end_row integer NOT NULL,
    active boolean DEFAULT false NOT NULL,
    job_name character varying NOT NULL
);


--
-- Name: TABLE revolving_work_shards; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.revolving_work_shards IS 'coordinates work between multiple processes working on the same job with partitions that need to be repeatedly processed; unlogged because on system crashes the locks represented by this table will have to be cleared anyway, typically using "taler-exchange-dbinit -s"';


--
-- Name: COLUMN revolving_work_shards.shard_serial_id; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.revolving_work_shards.shard_serial_id IS 'unique serial number identifying the shard';


--
-- Name: COLUMN revolving_work_shards.last_attempt; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.revolving_work_shards.last_attempt IS 'last time a worker attempted to work on the shard';


--
-- Name: COLUMN revolving_work_shards.start_row; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.revolving_work_shards.start_row IS 'row at which the shard scope starts, inclusive';


--
-- Name: COLUMN revolving_work_shards.end_row; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.revolving_work_shards.end_row IS 'row at which the shard scope ends, exclusive';


--
-- Name: COLUMN revolving_work_shards.active; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.revolving_work_shards.active IS 'set to TRUE when a worker is active on the shard';


--
-- Name: COLUMN revolving_work_shards.job_name; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.revolving_work_shards.job_name IS 'unique name of the job the workers on this shard are performing';


--
-- Name: revolving_work_shards_shard_serial_id_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.revolving_work_shards ALTER COLUMN shard_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.revolving_work_shards_shard_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: signkey_revocations; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.signkey_revocations (
    signkey_revocations_serial_id bigint NOT NULL,
    esk_serial bigint NOT NULL,
    master_sig bytea NOT NULL,
    CONSTRAINT signkey_revocations_master_sig_check CHECK ((length(master_sig) = 64))
);


--
-- Name: TABLE signkey_revocations; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.signkey_revocations IS 'Table storing which online signing keys have been revoked';


--
-- Name: signkey_revocations_signkey_revocations_serial_id_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.signkey_revocations ALTER COLUMN signkey_revocations_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.signkey_revocations_signkey_revocations_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: wad_in_entries; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.wad_in_entries (
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
-- Name: TABLE wad_in_entries; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.wad_in_entries IS 'list of purses aggregated in a wad according to the sending exchange';


--
-- Name: COLUMN wad_in_entries.wad_in_serial_id; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wad_in_entries.wad_in_serial_id IS 'wad for which the given purse was included in the aggregation';


--
-- Name: COLUMN wad_in_entries.reserve_pub; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wad_in_entries.reserve_pub IS 'target account of the purse (must be at the local exchange)';


--
-- Name: COLUMN wad_in_entries.purse_pub; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wad_in_entries.purse_pub IS 'public key of the purse that was merged';


--
-- Name: COLUMN wad_in_entries.h_contract; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wad_in_entries.h_contract IS 'hash of the contract terms of the purse';


--
-- Name: COLUMN wad_in_entries.purse_expiration; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wad_in_entries.purse_expiration IS 'Time when the purse was set to expire';


--
-- Name: COLUMN wad_in_entries.merge_timestamp; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wad_in_entries.merge_timestamp IS 'Time when the merge was approved';


--
-- Name: COLUMN wad_in_entries.amount_with_fee_val; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wad_in_entries.amount_with_fee_val IS 'Total amount in the purse';


--
-- Name: COLUMN wad_in_entries.wad_fee_val; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wad_in_entries.wad_fee_val IS 'Total wad fees paid by the purse';


--
-- Name: COLUMN wad_in_entries.deposit_fees_val; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wad_in_entries.deposit_fees_val IS 'Total deposit fees paid when depositing coins into the purse';


--
-- Name: COLUMN wad_in_entries.reserve_sig; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wad_in_entries.reserve_sig IS 'Signature by the receiving reserve, of purpose TALER_SIGNATURE_ACCOUNT_MERGE';


--
-- Name: COLUMN wad_in_entries.purse_sig; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wad_in_entries.purse_sig IS 'Signature by the purse of purpose TALER_SIGNATURE_PURSE_MERGE';


--
-- Name: wad_in_entries_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.wad_in_entries_default (
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
ALTER TABLE ONLY exchange.wad_in_entries ATTACH PARTITION exchange.wad_in_entries_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: wad_in_entries_wad_in_entry_serial_id_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.wad_in_entries ALTER COLUMN wad_in_entry_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.wad_in_entries_wad_in_entry_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: wad_out_entries; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.wad_out_entries (
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
-- Name: TABLE wad_out_entries; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.wad_out_entries IS 'Purses combined into a wad';


--
-- Name: COLUMN wad_out_entries.wad_out_serial_id; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wad_out_entries.wad_out_serial_id IS 'Wad the purse was part of';


--
-- Name: COLUMN wad_out_entries.reserve_pub; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wad_out_entries.reserve_pub IS 'Target reserve for the purse';


--
-- Name: COLUMN wad_out_entries.purse_pub; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wad_out_entries.purse_pub IS 'Public key of the purse';


--
-- Name: COLUMN wad_out_entries.h_contract; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wad_out_entries.h_contract IS 'Hash of the contract associated with the purse';


--
-- Name: COLUMN wad_out_entries.purse_expiration; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wad_out_entries.purse_expiration IS 'Time when the purse expires';


--
-- Name: COLUMN wad_out_entries.merge_timestamp; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wad_out_entries.merge_timestamp IS 'Time when the merge was approved';


--
-- Name: COLUMN wad_out_entries.amount_with_fee_val; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wad_out_entries.amount_with_fee_val IS 'Total amount in the purse';


--
-- Name: COLUMN wad_out_entries.wad_fee_val; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wad_out_entries.wad_fee_val IS 'Wat fee charged to the purse';


--
-- Name: COLUMN wad_out_entries.deposit_fees_val; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wad_out_entries.deposit_fees_val IS 'Total deposit fees charged to the purse';


--
-- Name: COLUMN wad_out_entries.reserve_sig; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wad_out_entries.reserve_sig IS 'Signature by the receiving reserve, of purpose TALER_SIGNATURE_ACCOUNT_MERGE';


--
-- Name: COLUMN wad_out_entries.purse_sig; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wad_out_entries.purse_sig IS 'Signature by the purse of purpose TALER_SIGNATURE_PURSE_MERGE';


--
-- Name: wad_out_entries_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.wad_out_entries_default (
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
ALTER TABLE ONLY exchange.wad_out_entries ATTACH PARTITION exchange.wad_out_entries_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: wad_out_entries_wad_out_entry_serial_id_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.wad_out_entries ALTER COLUMN wad_out_entry_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.wad_out_entries_wad_out_entry_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: wads_in; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.wads_in (
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
-- Name: TABLE wads_in; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.wads_in IS 'Incoming exchange-to-exchange wad wire transfers';


--
-- Name: COLUMN wads_in.wad_id; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wads_in.wad_id IS 'Unique identifier of the wad, part of the wire transfer subject';


--
-- Name: COLUMN wads_in.origin_exchange_url; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wads_in.origin_exchange_url IS 'Base URL of the originating URL, also part of the wire transfer subject';


--
-- Name: COLUMN wads_in.amount_val; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wads_in.amount_val IS 'Actual amount that was received by our exchange';


--
-- Name: COLUMN wads_in.arrival_time; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wads_in.arrival_time IS 'Time when the wad was received';


--
-- Name: wads_in_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.wads_in_default (
    wad_in_serial_id bigint NOT NULL,
    wad_id bytea NOT NULL,
    origin_exchange_url text NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    arrival_time bigint NOT NULL,
    CONSTRAINT wads_in_wad_id_check CHECK ((length(wad_id) = 24))
);
ALTER TABLE ONLY exchange.wads_in ATTACH PARTITION exchange.wads_in_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: wads_in_wad_in_serial_id_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.wads_in ALTER COLUMN wad_in_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.wads_in_wad_in_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: wads_out; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.wads_out (
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
-- Name: TABLE wads_out; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.wads_out IS 'Wire transfers made to another exchange to transfer purse funds';


--
-- Name: COLUMN wads_out.wad_id; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wads_out.wad_id IS 'Unique identifier of the wad, part of the wire transfer subject';


--
-- Name: COLUMN wads_out.partner_serial_id; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wads_out.partner_serial_id IS 'target exchange of the wad';


--
-- Name: COLUMN wads_out.amount_val; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wads_out.amount_val IS 'Amount that was wired';


--
-- Name: COLUMN wads_out.execution_time; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wads_out.execution_time IS 'Time when the wire transfer was scheduled';


--
-- Name: wads_out_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.wads_out_default (
    wad_out_serial_id bigint NOT NULL,
    wad_id bytea NOT NULL,
    partner_serial_id bigint NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    execution_time bigint NOT NULL,
    CONSTRAINT wads_out_wad_id_check CHECK ((length(wad_id) = 24))
);
ALTER TABLE ONLY exchange.wads_out ATTACH PARTITION exchange.wads_out_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: wads_out_wad_out_serial_id_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.wads_out ALTER COLUMN wad_out_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.wads_out_wad_out_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: wire_accounts; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.wire_accounts (
    payto_uri character varying NOT NULL,
    master_sig bytea,
    is_active boolean NOT NULL,
    last_change bigint NOT NULL,
    CONSTRAINT wire_accounts_master_sig_check CHECK ((length(master_sig) = 64))
);


--
-- Name: TABLE wire_accounts; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.wire_accounts IS 'Table with current and historic bank accounts of the exchange. Entries never expire as we need to remember the last_change column indefinitely.';


--
-- Name: COLUMN wire_accounts.payto_uri; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wire_accounts.payto_uri IS 'payto URI (RFC 8905) with the bank account of the exchange.';


--
-- Name: COLUMN wire_accounts.master_sig; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wire_accounts.master_sig IS 'Signature of purpose TALER_SIGNATURE_MASTER_WIRE_DETAILS';


--
-- Name: COLUMN wire_accounts.is_active; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wire_accounts.is_active IS 'true if we are currently supporting the use of this account.';


--
-- Name: COLUMN wire_accounts.last_change; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wire_accounts.last_change IS 'Latest time when active status changed. Used to detect replays of old messages.';


--
-- Name: wire_fee; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.wire_fee (
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
-- Name: TABLE wire_fee; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.wire_fee IS 'list of the wire fees of this exchange, by date';


--
-- Name: COLUMN wire_fee.wire_fee_serial; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wire_fee.wire_fee_serial IS 'needed for exchange-auditor replication logic';


--
-- Name: wire_fee_wire_fee_serial_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.wire_fee ALTER COLUMN wire_fee_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.wire_fee_wire_fee_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: wire_out; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.wire_out (
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
-- Name: TABLE wire_out; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.wire_out IS 'wire transfers the exchange has executed';


--
-- Name: COLUMN wire_out.wire_target_h_payto; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wire_out.wire_target_h_payto IS 'Identifies the credited bank account and KYC status';


--
-- Name: COLUMN wire_out.exchange_account_section; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wire_out.exchange_account_section IS 'identifies the configuration section with the debit account of this payment';


--
-- Name: wire_out_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.wire_out_default (
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
ALTER TABLE ONLY exchange.wire_out ATTACH PARTITION exchange.wire_out_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: wire_out_wireout_uuid_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.wire_out ALTER COLUMN wireout_uuid ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.wire_out_wireout_uuid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: wire_targets; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.wire_targets (
    wire_target_serial_id bigint NOT NULL,
    wire_target_h_payto bytea NOT NULL,
    payto_uri character varying NOT NULL,
    CONSTRAINT wire_targets_wire_target_h_payto_check CHECK ((length(wire_target_h_payto) = 32))
)
PARTITION BY HASH (wire_target_h_payto);


--
-- Name: TABLE wire_targets; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.wire_targets IS 'All senders and recipients of money via the exchange';


--
-- Name: COLUMN wire_targets.wire_target_h_payto; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wire_targets.wire_target_h_payto IS 'Unsalted hash of payto_uri';


--
-- Name: COLUMN wire_targets.payto_uri; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wire_targets.payto_uri IS 'Can be a regular bank account, or also be a URI identifying a reserve-account (for P2P payments)';


--
-- Name: wire_targets_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.wire_targets_default (
    wire_target_serial_id bigint NOT NULL,
    wire_target_h_payto bytea NOT NULL,
    payto_uri character varying NOT NULL,
    CONSTRAINT wire_targets_wire_target_h_payto_check CHECK ((length(wire_target_h_payto) = 32))
);
ALTER TABLE ONLY exchange.wire_targets ATTACH PARTITION exchange.wire_targets_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: wire_targets_wire_target_serial_id_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.wire_targets ALTER COLUMN wire_target_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.wire_targets_wire_target_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: work_shards; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.work_shards (
    shard_serial_id bigint NOT NULL,
    last_attempt bigint NOT NULL,
    start_row bigint NOT NULL,
    end_row bigint NOT NULL,
    completed boolean DEFAULT false NOT NULL,
    job_name character varying NOT NULL
);


--
-- Name: TABLE work_shards; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TABLE exchange.work_shards IS 'coordinates work between multiple processes working on the same job';


--
-- Name: COLUMN work_shards.shard_serial_id; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.work_shards.shard_serial_id IS 'unique serial number identifying the shard';


--
-- Name: COLUMN work_shards.last_attempt; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.work_shards.last_attempt IS 'last time a worker attempted to work on the shard';


--
-- Name: COLUMN work_shards.start_row; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.work_shards.start_row IS 'row at which the shard scope starts, inclusive';


--
-- Name: COLUMN work_shards.end_row; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.work_shards.end_row IS 'row at which the shard scope ends, exclusive';


--
-- Name: COLUMN work_shards.completed; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.work_shards.completed IS 'set to TRUE once the shard is finished by a worker';


--
-- Name: COLUMN work_shards.job_name; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.work_shards.job_name IS 'unique name of the job the workers on this shard are performing';


--
-- Name: work_shards_shard_serial_id_seq; Type: SEQUENCE; Schema: exchange; Owner: -
--

ALTER TABLE exchange.work_shards ALTER COLUMN shard_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME exchange.work_shards_shard_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: merchant_accounts; Type: TABLE; Schema: merchant; Owner: -
--

CREATE TABLE merchant.merchant_accounts (
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
-- Name: TABLE merchant_accounts; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON TABLE merchant.merchant_accounts IS 'bank accounts of the instances';


--
-- Name: COLUMN merchant_accounts.h_wire; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_accounts.h_wire IS 'salted hash of payto_uri';


--
-- Name: COLUMN merchant_accounts.salt; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_accounts.salt IS 'salt used when hashing payto_uri into h_wire';


--
-- Name: COLUMN merchant_accounts.payto_uri; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_accounts.payto_uri IS 'payto URI of a merchant bank account';


--
-- Name: COLUMN merchant_accounts.active; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_accounts.active IS 'true if we actively use this bank account, false if it is just kept around for older contracts to refer to';


--
-- Name: merchant_accounts_account_serial_seq; Type: SEQUENCE; Schema: merchant; Owner: -
--

ALTER TABLE merchant.merchant_accounts ALTER COLUMN account_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME merchant.merchant_accounts_account_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: merchant_contract_terms; Type: TABLE; Schema: merchant; Owner: -
--

CREATE TABLE merchant.merchant_contract_terms (
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
-- Name: TABLE merchant_contract_terms; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON TABLE merchant.merchant_contract_terms IS 'Contracts are orders that have been claimed by a wallet';


--
-- Name: COLUMN merchant_contract_terms.merchant_serial; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_contract_terms.merchant_serial IS 'Identifies the instance offering the contract';


--
-- Name: COLUMN merchant_contract_terms.order_id; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_contract_terms.order_id IS 'Not a foreign key into merchant_orders because paid contracts persist after expiration';


--
-- Name: COLUMN merchant_contract_terms.contract_terms; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_contract_terms.contract_terms IS 'These contract terms include the wallet nonce';


--
-- Name: COLUMN merchant_contract_terms.h_contract_terms; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_contract_terms.h_contract_terms IS 'Hash over contract_terms';


--
-- Name: COLUMN merchant_contract_terms.pay_deadline; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_contract_terms.pay_deadline IS 'How long is the offer valid. After this time, the order can be garbage collected';


--
-- Name: COLUMN merchant_contract_terms.refund_deadline; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_contract_terms.refund_deadline IS 'By what times do refunds have to be approved (useful to reject refund requests)';


--
-- Name: COLUMN merchant_contract_terms.paid; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_contract_terms.paid IS 'true implies the customer paid for this contract; order should be DELETEd from merchant_orders once paid is set to release merchant_order_locks; paid remains true even if the payment was later refunded';


--
-- Name: COLUMN merchant_contract_terms.wired; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_contract_terms.wired IS 'true implies the exchange wired us the full amount for all non-refunded payments under this contract';


--
-- Name: COLUMN merchant_contract_terms.fulfillment_url; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_contract_terms.fulfillment_url IS 'also included in contract_terms, but we need it here to SELECT on it during repurchase detection; can be NULL if the contract has no fulfillment URL';


--
-- Name: COLUMN merchant_contract_terms.session_id; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_contract_terms.session_id IS 'last session_id from we confirmed the paying client to use, empty string for none';


--
-- Name: COLUMN merchant_contract_terms.claim_token; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_contract_terms.claim_token IS 'Token optionally used to access the status of the order. All zeros (not NULL) if not used';


--
-- Name: merchant_deposit_to_transfer; Type: TABLE; Schema: merchant; Owner: -
--

CREATE TABLE merchant.merchant_deposit_to_transfer (
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
-- Name: TABLE merchant_deposit_to_transfer; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON TABLE merchant.merchant_deposit_to_transfer IS 'Mapping of deposits to (possibly unconfirmed) wire transfers; NOTE: not used yet';


--
-- Name: COLUMN merchant_deposit_to_transfer.execution_time; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_deposit_to_transfer.execution_time IS 'Execution time as claimed by the exchange, roughly matches time seen by merchant';


--
-- Name: merchant_deposits; Type: TABLE; Schema: merchant; Owner: -
--

CREATE TABLE merchant.merchant_deposits (
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
-- Name: TABLE merchant_deposits; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON TABLE merchant.merchant_deposits IS 'Refunds approved by the merchant (backoffice) logic, excludes abort refunds';


--
-- Name: COLUMN merchant_deposits.deposit_timestamp; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_deposits.deposit_timestamp IS 'Time when the exchange generated the deposit confirmation';


--
-- Name: COLUMN merchant_deposits.wire_fee_val; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_deposits.wire_fee_val IS 'We MAY want to see if we should try to get this via merchant_exchange_wire_fees (not sure, may be too complicated with the date range, etc.)';


--
-- Name: COLUMN merchant_deposits.signkey_serial; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_deposits.signkey_serial IS 'Online signing key of the exchange on the deposit confirmation';


--
-- Name: COLUMN merchant_deposits.exchange_sig; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_deposits.exchange_sig IS 'Signature of the exchange over the deposit confirmation';


--
-- Name: merchant_deposits_deposit_serial_seq; Type: SEQUENCE; Schema: merchant; Owner: -
--

ALTER TABLE merchant.merchant_deposits ALTER COLUMN deposit_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME merchant.merchant_deposits_deposit_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: merchant_exchange_signing_keys; Type: TABLE; Schema: merchant; Owner: -
--

CREATE TABLE merchant.merchant_exchange_signing_keys (
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
-- Name: TABLE merchant_exchange_signing_keys; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON TABLE merchant.merchant_exchange_signing_keys IS 'Here we store proofs of the exchange online signing keys being signed by the exchange master key';


--
-- Name: COLUMN merchant_exchange_signing_keys.master_pub; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_exchange_signing_keys.master_pub IS 'Master public key of the exchange with these online signing keys';


--
-- Name: merchant_exchange_signing_keys_signkey_serial_seq; Type: SEQUENCE; Schema: merchant; Owner: -
--

ALTER TABLE merchant.merchant_exchange_signing_keys ALTER COLUMN signkey_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME merchant.merchant_exchange_signing_keys_signkey_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: merchant_exchange_wire_fees; Type: TABLE; Schema: merchant; Owner: -
--

CREATE TABLE merchant.merchant_exchange_wire_fees (
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
-- Name: TABLE merchant_exchange_wire_fees; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON TABLE merchant.merchant_exchange_wire_fees IS 'Here we store proofs of the wire fee structure of the various exchanges';


--
-- Name: COLUMN merchant_exchange_wire_fees.master_pub; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_exchange_wire_fees.master_pub IS 'Master public key of the exchange with these wire fees';


--
-- Name: merchant_exchange_wire_fees_wirefee_serial_seq; Type: SEQUENCE; Schema: merchant; Owner: -
--

ALTER TABLE merchant.merchant_exchange_wire_fees ALTER COLUMN wirefee_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME merchant.merchant_exchange_wire_fees_wirefee_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: merchant_instances; Type: TABLE; Schema: merchant; Owner: -
--

CREATE TABLE merchant.merchant_instances (
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
-- Name: TABLE merchant_instances; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON TABLE merchant.merchant_instances IS 'all the instances supported by this backend';


--
-- Name: COLUMN merchant_instances.auth_hash; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_instances.auth_hash IS 'hash used for merchant back office Authorization, NULL for no check';


--
-- Name: COLUMN merchant_instances.auth_salt; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_instances.auth_salt IS 'salt to use when hashing Authorization header before comparing with auth_hash';


--
-- Name: COLUMN merchant_instances.merchant_id; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_instances.merchant_id IS 'identifier of the merchant as used in the base URL (required)';


--
-- Name: COLUMN merchant_instances.merchant_name; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_instances.merchant_name IS 'legal name of the merchant as a simple string (required)';


--
-- Name: COLUMN merchant_instances.address; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_instances.address IS 'physical address of the merchant as a Location in JSON format (required)';


--
-- Name: COLUMN merchant_instances.jurisdiction; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_instances.jurisdiction IS 'jurisdiction of the merchant as a Location in JSON format (required)';


--
-- Name: COLUMN merchant_instances.website; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_instances.website IS 'merchant site URL';


--
-- Name: COLUMN merchant_instances.email; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_instances.email IS 'email';


--
-- Name: COLUMN merchant_instances.logo; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_instances.logo IS 'data image url';


--
-- Name: merchant_instances_merchant_serial_seq; Type: SEQUENCE; Schema: merchant; Owner: -
--

ALTER TABLE merchant.merchant_instances ALTER COLUMN merchant_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME merchant.merchant_instances_merchant_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: merchant_inventory; Type: TABLE; Schema: merchant; Owner: -
--

CREATE TABLE merchant.merchant_inventory (
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
-- Name: TABLE merchant_inventory; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON TABLE merchant.merchant_inventory IS 'products offered by the merchant (may be incomplete, frontend can override)';


--
-- Name: COLUMN merchant_inventory.description; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_inventory.description IS 'Human-readable product description';


--
-- Name: COLUMN merchant_inventory.description_i18n; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_inventory.description_i18n IS 'JSON map from IETF BCP 47 language tags to localized descriptions';


--
-- Name: COLUMN merchant_inventory.unit; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_inventory.unit IS 'Unit of sale for the product (liters, kilograms, packages)';


--
-- Name: COLUMN merchant_inventory.image; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_inventory.image IS 'NOT NULL, but can be 0 bytes; must contain an ImageDataUrl';


--
-- Name: COLUMN merchant_inventory.taxes; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_inventory.taxes IS 'JSON array containing taxes the merchant pays, must be JSON, but can be just "[]"';


--
-- Name: COLUMN merchant_inventory.price_val; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_inventory.price_val IS 'Current price of one unit of the product';


--
-- Name: COLUMN merchant_inventory.total_stock; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_inventory.total_stock IS 'A value of -1 is used for unlimited (electronic good), may never be lowered';


--
-- Name: COLUMN merchant_inventory.total_sold; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_inventory.total_sold IS 'Number of products sold, must be below total_stock, non-negative, may never be lowered';


--
-- Name: COLUMN merchant_inventory.total_lost; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_inventory.total_lost IS 'Number of products that used to be in stock but were lost (spoiled, damaged), may never be lowered; total_stock >= total_sold + total_lost must always hold';


--
-- Name: COLUMN merchant_inventory.address; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_inventory.address IS 'JSON formatted Location of where the product is stocked';


--
-- Name: COLUMN merchant_inventory.next_restock; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_inventory.next_restock IS 'GNUnet absolute time indicating when the next restock is expected. 0 for unknown.';


--
-- Name: COLUMN merchant_inventory.minimum_age; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_inventory.minimum_age IS 'Minimum age of the customer in years, to be used if an exchange supports the age restriction extension.';


--
-- Name: merchant_inventory_locks; Type: TABLE; Schema: merchant; Owner: -
--

CREATE TABLE merchant.merchant_inventory_locks (
    product_serial bigint NOT NULL,
    lock_uuid bytea NOT NULL,
    total_locked bigint NOT NULL,
    expiration bigint NOT NULL,
    CONSTRAINT merchant_inventory_locks_lock_uuid_check CHECK ((length(lock_uuid) = 16))
);


--
-- Name: TABLE merchant_inventory_locks; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON TABLE merchant.merchant_inventory_locks IS 'locks on inventory helt by shopping carts; note that locks MAY not be honored if merchants increase total_lost for inventory';


--
-- Name: COLUMN merchant_inventory_locks.total_locked; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_inventory_locks.total_locked IS 'how many units of the product does this lock reserve';


--
-- Name: COLUMN merchant_inventory_locks.expiration; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_inventory_locks.expiration IS 'when does this lock automatically expire (if no order is created)';


--
-- Name: merchant_inventory_product_serial_seq; Type: SEQUENCE; Schema: merchant; Owner: -
--

ALTER TABLE merchant.merchant_inventory ALTER COLUMN product_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME merchant.merchant_inventory_product_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: merchant_keys; Type: TABLE; Schema: merchant; Owner: -
--

CREATE TABLE merchant.merchant_keys (
    merchant_priv bytea NOT NULL,
    merchant_serial bigint NOT NULL,
    CONSTRAINT merchant_keys_merchant_priv_check CHECK ((length(merchant_priv) = 32))
);


--
-- Name: TABLE merchant_keys; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON TABLE merchant.merchant_keys IS 'private keys of instances that have not been deleted';


--
-- Name: merchant_kyc; Type: TABLE; Schema: merchant; Owner: -
--

CREATE TABLE merchant.merchant_kyc (
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
-- Name: TABLE merchant_kyc; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON TABLE merchant.merchant_kyc IS 'Status of the KYC process of a merchant account at an exchange';


--
-- Name: COLUMN merchant_kyc.kyc_timestamp; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_kyc.kyc_timestamp IS 'Last time we checked our KYC status at the exchange. Useful to re-check if the status is very stale. Also the timestamp used for the exchange signature (if present).';


--
-- Name: COLUMN merchant_kyc.kyc_ok; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_kyc.kyc_ok IS 'true if the KYC check was passed successfully';


--
-- Name: COLUMN merchant_kyc.exchange_sig; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_kyc.exchange_sig IS 'signature of the exchange affirming the KYC passed (or NULL if exchange does not require KYC or not kyc_ok)';


--
-- Name: COLUMN merchant_kyc.exchange_pub; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_kyc.exchange_pub IS 'public key used with exchange_sig (or NULL if exchange_sig is NULL)';


--
-- Name: COLUMN merchant_kyc.exchange_kyc_serial; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_kyc.exchange_kyc_serial IS 'Number to use in the KYC-endpoints of the exchange to check the KYC status or begin the KYC process. 0 if we do not know it yet.';


--
-- Name: COLUMN merchant_kyc.account_serial; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_kyc.account_serial IS 'Which bank account of the merchant is the KYC status for';


--
-- Name: COLUMN merchant_kyc.exchange_url; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_kyc.exchange_url IS 'Which exchange base URL is this KYC status valid for';


--
-- Name: merchant_kyc_kyc_serial_id_seq; Type: SEQUENCE; Schema: merchant; Owner: -
--

ALTER TABLE merchant.merchant_kyc ALTER COLUMN kyc_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME merchant.merchant_kyc_kyc_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: merchant_order_locks; Type: TABLE; Schema: merchant; Owner: -
--

CREATE TABLE merchant.merchant_order_locks (
    product_serial bigint NOT NULL,
    total_locked bigint NOT NULL,
    order_serial bigint NOT NULL
);


--
-- Name: TABLE merchant_order_locks; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON TABLE merchant.merchant_order_locks IS 'locks on orders awaiting claim and payment; note that locks MAY not be honored if merchants increase total_lost for inventory';


--
-- Name: COLUMN merchant_order_locks.total_locked; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_order_locks.total_locked IS 'how many units of the product does this lock reserve';


--
-- Name: merchant_orders; Type: TABLE; Schema: merchant; Owner: -
--

CREATE TABLE merchant.merchant_orders (
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
-- Name: TABLE merchant_orders; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON TABLE merchant.merchant_orders IS 'Orders we offered to a customer, but that have not yet been claimed';


--
-- Name: COLUMN merchant_orders.merchant_serial; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_orders.merchant_serial IS 'Identifies the instance offering the contract';


--
-- Name: COLUMN merchant_orders.claim_token; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_orders.claim_token IS 'Token optionally used to authorize the wallet to claim the order. All zeros (not NULL) if not used';


--
-- Name: COLUMN merchant_orders.h_post_data; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_orders.h_post_data IS 'Hash of the POST request that created this order, for idempotency checks';


--
-- Name: COLUMN merchant_orders.pay_deadline; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_orders.pay_deadline IS 'How long is the offer valid. After this time, the order can be garbage collected';


--
-- Name: COLUMN merchant_orders.contract_terms; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_orders.contract_terms IS 'Claiming changes the contract_terms, hence we have no hash of the terms in this table';


--
-- Name: merchant_orders_order_serial_seq; Type: SEQUENCE; Schema: merchant; Owner: -
--

ALTER TABLE merchant.merchant_orders ALTER COLUMN order_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME merchant.merchant_orders_order_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: merchant_refund_proofs; Type: TABLE; Schema: merchant; Owner: -
--

CREATE TABLE merchant.merchant_refund_proofs (
    refund_serial bigint NOT NULL,
    exchange_sig bytea NOT NULL,
    signkey_serial bigint NOT NULL,
    CONSTRAINT merchant_refund_proofs_exchange_sig_check CHECK ((length(exchange_sig) = 64))
);


--
-- Name: TABLE merchant_refund_proofs; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON TABLE merchant.merchant_refund_proofs IS 'Refunds confirmed by the exchange (not all approved refunds are grabbed by the wallet)';


--
-- Name: merchant_refunds; Type: TABLE; Schema: merchant; Owner: -
--

CREATE TABLE merchant.merchant_refunds (
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
-- Name: COLUMN merchant_refunds.rtransaction_id; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_refunds.rtransaction_id IS 'Needed for uniqueness in case a refund is increased for the same order';


--
-- Name: COLUMN merchant_refunds.refund_timestamp; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_refunds.refund_timestamp IS 'Needed for grouping of refunds in the wallet UI; has no semantics in the protocol (only for UX), but should be from the time when the merchant internally approved the refund';


--
-- Name: merchant_refunds_refund_serial_seq; Type: SEQUENCE; Schema: merchant; Owner: -
--

ALTER TABLE merchant.merchant_refunds ALTER COLUMN refund_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME merchant.merchant_refunds_refund_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: merchant_tip_pickup_signatures; Type: TABLE; Schema: merchant; Owner: -
--

CREATE TABLE merchant.merchant_tip_pickup_signatures (
    pickup_serial bigint NOT NULL,
    coin_offset integer NOT NULL,
    blind_sig bytea NOT NULL
);


--
-- Name: TABLE merchant_tip_pickup_signatures; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON TABLE merchant.merchant_tip_pickup_signatures IS 'blind signatures we got from the exchange during the tip pickup';


--
-- Name: merchant_tip_pickups; Type: TABLE; Schema: merchant; Owner: -
--

CREATE TABLE merchant.merchant_tip_pickups (
    pickup_serial bigint NOT NULL,
    tip_serial bigint NOT NULL,
    pickup_id bytea NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    CONSTRAINT merchant_tip_pickups_pickup_id_check CHECK ((length(pickup_id) = 64))
);


--
-- Name: TABLE merchant_tip_pickups; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON TABLE merchant.merchant_tip_pickups IS 'tips that have been picked up';


--
-- Name: merchant_tip_pickups_pickup_serial_seq; Type: SEQUENCE; Schema: merchant; Owner: -
--

ALTER TABLE merchant.merchant_tip_pickups ALTER COLUMN pickup_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME merchant.merchant_tip_pickups_pickup_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: merchant_tip_reserve_keys; Type: TABLE; Schema: merchant; Owner: -
--

CREATE TABLE merchant.merchant_tip_reserve_keys (
    reserve_serial bigint NOT NULL,
    reserve_priv bytea NOT NULL,
    exchange_url character varying NOT NULL,
    payto_uri character varying,
    CONSTRAINT merchant_tip_reserve_keys_reserve_priv_check CHECK ((length(reserve_priv) = 32))
);


--
-- Name: COLUMN merchant_tip_reserve_keys.payto_uri; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_tip_reserve_keys.payto_uri IS 'payto:// URI used to fund the reserve, may be NULL once reserve is funded';


--
-- Name: merchant_tip_reserves; Type: TABLE; Schema: merchant; Owner: -
--

CREATE TABLE merchant.merchant_tip_reserves (
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
-- Name: TABLE merchant_tip_reserves; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON TABLE merchant.merchant_tip_reserves IS 'private keys of reserves that have not been deleted';


--
-- Name: COLUMN merchant_tip_reserves.expiration; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_tip_reserves.expiration IS 'FIXME: EXCHANGE API needs to tell us when reserves close if we are to compute this';


--
-- Name: COLUMN merchant_tip_reserves.merchant_initial_balance_val; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_tip_reserves.merchant_initial_balance_val IS 'Set to the initial balance the merchant told us when creating the reserve';


--
-- Name: COLUMN merchant_tip_reserves.exchange_initial_balance_val; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_tip_reserves.exchange_initial_balance_val IS 'Set to the initial balance the exchange told us when we queried the reserve status';


--
-- Name: COLUMN merchant_tip_reserves.tips_committed_val; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_tip_reserves.tips_committed_val IS 'Amount of outstanding approved tips that have not been picked up';


--
-- Name: COLUMN merchant_tip_reserves.tips_picked_up_val; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_tip_reserves.tips_picked_up_val IS 'Total amount tips that have been picked up from this reserve';


--
-- Name: merchant_tip_reserves_reserve_serial_seq; Type: SEQUENCE; Schema: merchant; Owner: -
--

ALTER TABLE merchant.merchant_tip_reserves ALTER COLUMN reserve_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME merchant.merchant_tip_reserves_reserve_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: merchant_tips; Type: TABLE; Schema: merchant; Owner: -
--

CREATE TABLE merchant.merchant_tips (
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
-- Name: TABLE merchant_tips; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON TABLE merchant.merchant_tips IS 'tips that have been authorized';


--
-- Name: COLUMN merchant_tips.reserve_serial; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_tips.reserve_serial IS 'Reserve from which this tip is funded';


--
-- Name: COLUMN merchant_tips.expiration; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_tips.expiration IS 'by when does the client have to pick up the tip';


--
-- Name: COLUMN merchant_tips.amount_val; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_tips.amount_val IS 'total transaction cost for all coins including withdraw fees';


--
-- Name: COLUMN merchant_tips.picked_up_val; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_tips.picked_up_val IS 'Tip amount left to be picked up';


--
-- Name: merchant_tips_tip_serial_seq; Type: SEQUENCE; Schema: merchant; Owner: -
--

ALTER TABLE merchant.merchant_tips ALTER COLUMN tip_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME merchant.merchant_tips_tip_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: merchant_transfer_signatures; Type: TABLE; Schema: merchant; Owner: -
--

CREATE TABLE merchant.merchant_transfer_signatures (
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
-- Name: TABLE merchant_transfer_signatures; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON TABLE merchant.merchant_transfer_signatures IS 'table represents the main information returned from the /transfer request to the exchange.';


--
-- Name: COLUMN merchant_transfer_signatures.credit_amount_val; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_transfer_signatures.credit_amount_val IS 'actual value of the (aggregated) wire transfer, excluding the wire fee, according to the exchange';


--
-- Name: COLUMN merchant_transfer_signatures.execution_time; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_transfer_signatures.execution_time IS 'Execution time as claimed by the exchange, roughly matches time seen by merchant';


--
-- Name: merchant_transfer_to_coin; Type: TABLE; Schema: merchant; Owner: -
--

CREATE TABLE merchant.merchant_transfer_to_coin (
    deposit_serial bigint NOT NULL,
    credit_serial bigint NOT NULL,
    offset_in_exchange_list bigint NOT NULL,
    exchange_deposit_value_val bigint NOT NULL,
    exchange_deposit_value_frac integer NOT NULL,
    exchange_deposit_fee_val bigint NOT NULL,
    exchange_deposit_fee_frac integer NOT NULL
);


--
-- Name: TABLE merchant_transfer_to_coin; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON TABLE merchant.merchant_transfer_to_coin IS 'Mapping of (credit) transfers to (deposited) coins';


--
-- Name: COLUMN merchant_transfer_to_coin.exchange_deposit_value_val; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_transfer_to_coin.exchange_deposit_value_val IS 'Deposit value as claimed by the exchange, should match our values in merchant_deposits minus refunds';


--
-- Name: COLUMN merchant_transfer_to_coin.exchange_deposit_fee_val; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_transfer_to_coin.exchange_deposit_fee_val IS 'Deposit value as claimed by the exchange, should match our values in merchant_deposits';


--
-- Name: merchant_transfers; Type: TABLE; Schema: merchant; Owner: -
--

CREATE TABLE merchant.merchant_transfers (
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
-- Name: TABLE merchant_transfers; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON TABLE merchant.merchant_transfers IS 'table represents the information provided by the (trusted) merchant about incoming wire transfers';


--
-- Name: COLUMN merchant_transfers.credit_amount_val; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_transfers.credit_amount_val IS 'actual value of the (aggregated) wire transfer, excluding the wire fee, according to the merchant';


--
-- Name: COLUMN merchant_transfers.verified; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_transfers.verified IS 'true once we got an acceptable response from the exchange for this transfer';


--
-- Name: COLUMN merchant_transfers.confirmed; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON COLUMN merchant.merchant_transfers.confirmed IS 'true once the merchant confirmed that this transfer was received';


--
-- Name: merchant_transfers_credit_serial_seq; Type: SEQUENCE; Schema: merchant; Owner: -
--

ALTER TABLE merchant.merchant_transfers ALTER COLUMN credit_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME merchant.merchant_transfers_credit_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: auditor_reserves auditor_reserves_rowid; Type: DEFAULT; Schema: auditor; Owner: -
--

ALTER TABLE ONLY auditor.auditor_reserves ALTER COLUMN auditor_reserves_rowid SET DEFAULT nextval('auditor.auditor_reserves_auditor_reserves_rowid_seq'::regclass);


--
-- Name: deposit_confirmations serial_id; Type: DEFAULT; Schema: auditor; Owner: -
--

ALTER TABLE ONLY auditor.deposit_confirmations ALTER COLUMN serial_id SET DEFAULT nextval('auditor.deposit_confirmations_serial_id_seq'::regclass);


--
-- Data for Name: patches; Type: TABLE DATA; Schema: _v; Owner: -
--

COPY _v.patches (patch_name, applied_tsz, applied_by, requires, conflicts) FROM stdin;
exchange-0001	2022-08-14 19:06:52.598746+02	grothoff	{}	{}
merchant-0001	2022-08-14 19:06:53.686078+02	grothoff	{}	{}
merchant-0002	2022-08-14 19:06:54.070924+02	grothoff	{}	{}
auditor-0001	2022-08-14 19:06:54.19173+02	grothoff	{}	{}
\.


--
-- Data for Name: auditor_balance_summary; Type: TABLE DATA; Schema: auditor; Owner: -
--

COPY auditor.auditor_balance_summary (master_pub, denom_balance_val, denom_balance_frac, deposit_fee_balance_val, deposit_fee_balance_frac, melt_fee_balance_val, melt_fee_balance_frac, refund_fee_balance_val, refund_fee_balance_frac, risk_val, risk_frac, loss_val, loss_frac, irregular_recoup_val, irregular_recoup_frac) FROM stdin;
\.


--
-- Data for Name: auditor_denomination_pending; Type: TABLE DATA; Schema: auditor; Owner: -
--

COPY auditor.auditor_denomination_pending (denom_pub_hash, denom_balance_val, denom_balance_frac, denom_loss_val, denom_loss_frac, num_issued, denom_risk_val, denom_risk_frac, recoup_loss_val, recoup_loss_frac) FROM stdin;
\.


--
-- Data for Name: auditor_exchange_signkeys; Type: TABLE DATA; Schema: auditor; Owner: -
--

COPY auditor.auditor_exchange_signkeys (master_pub, ep_start, ep_expire, ep_end, exchange_pub, master_sig) FROM stdin;
\\x45be0bb109f61ca7ad3a550599a2b852602c53aa25d0125418e8fc86dcc48820	1660496827000000	1667754427000000	1670173627000000	\\xfbb791f7723feb8207efda8c8b03f95c21a2339ea9e29c7c4f68e479c92c4c44	\\xff1127197e35278affc4c1b867ef654e94ed4911247b52ab5369244e60d0051b962f51e45572dc94fea905e23f9be6ef421fb106adeb27c3d60b42b82b24960b
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: auditor; Owner: -
--

COPY auditor.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\x45be0bb109f61ca7ad3a550599a2b852602c53aa25d0125418e8fc86dcc48820	http://localhost:8081/
\.


--
-- Data for Name: auditor_historic_denomination_revenue; Type: TABLE DATA; Schema: auditor; Owner: -
--

COPY auditor.auditor_historic_denomination_revenue (master_pub, denom_pub_hash, revenue_timestamp, revenue_balance_val, revenue_balance_frac, loss_balance_val, loss_balance_frac) FROM stdin;
\.


--
-- Data for Name: auditor_historic_reserve_summary; Type: TABLE DATA; Schema: auditor; Owner: -
--

COPY auditor.auditor_historic_reserve_summary (master_pub, start_date, end_date, reserve_profits_val, reserve_profits_frac) FROM stdin;
\.


--
-- Data for Name: auditor_predicted_result; Type: TABLE DATA; Schema: auditor; Owner: -
--

COPY auditor.auditor_predicted_result (master_pub, balance_val, balance_frac, drained_val, drained_frac) FROM stdin;
\.


--
-- Data for Name: auditor_progress_aggregation; Type: TABLE DATA; Schema: auditor; Owner: -
--

COPY auditor.auditor_progress_aggregation (master_pub, last_wire_out_serial_id) FROM stdin;
\.


--
-- Data for Name: auditor_progress_coin; Type: TABLE DATA; Schema: auditor; Owner: -
--

COPY auditor.auditor_progress_coin (master_pub, last_withdraw_serial_id, last_deposit_serial_id, last_melt_serial_id, last_refund_serial_id, last_recoup_serial_id, last_recoup_refresh_serial_id, last_purse_deposits_serial_id, last_purse_refunds_serial_id) FROM stdin;
\.


--
-- Data for Name: auditor_progress_deposit_confirmation; Type: TABLE DATA; Schema: auditor; Owner: -
--

COPY auditor.auditor_progress_deposit_confirmation (master_pub, last_deposit_confirmation_serial_id) FROM stdin;
\.


--
-- Data for Name: auditor_progress_reserve; Type: TABLE DATA; Schema: auditor; Owner: -
--

COPY auditor.auditor_progress_reserve (master_pub, last_reserve_in_serial_id, last_reserve_out_serial_id, last_reserve_recoup_serial_id, last_reserve_close_serial_id, last_purse_merges_serial_id, last_purse_deposits_serial_id, last_account_merges_serial_id, last_history_requests_serial_id, last_close_requests_serial_id) FROM stdin;
\.


--
-- Data for Name: auditor_reserve_balance; Type: TABLE DATA; Schema: auditor; Owner: -
--

COPY auditor.auditor_reserve_balance (master_pub, reserve_balance_val, reserve_balance_frac, withdraw_fee_balance_val, withdraw_fee_balance_frac, purse_fee_balance_val, purse_fee_balance_frac, history_fee_balance_val, history_fee_balance_frac) FROM stdin;
\.


--
-- Data for Name: auditor_reserves; Type: TABLE DATA; Schema: auditor; Owner: -
--

COPY auditor.auditor_reserves (reserve_pub, master_pub, reserve_balance_val, reserve_balance_frac, withdraw_fee_balance_val, withdraw_fee_balance_frac, expiration_date, auditor_reserves_rowid, origin_account) FROM stdin;
\.


--
-- Data for Name: auditor_wire_fee_balance; Type: TABLE DATA; Schema: auditor; Owner: -
--

COPY auditor.auditor_wire_fee_balance (master_pub, wire_fee_balance_val, wire_fee_balance_frac) FROM stdin;
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: auditor; Owner: -
--

COPY auditor.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_extensions, h_wire, exchange_timestamp, refund_deadline, wire_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\\x45be0bb109f61ca7ad3a550599a2b852602c53aa25d0125418e8fc86dcc48820	1	\\x597874d0e5022cc5dbd261010ade882413c2ef9e8c18b4a80f5a5bba5ca5309b91e2b0f7a4a588baea19d589facc2dd755012720592e33faba0ef0ec0edc6f7c	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x61c651ac7705133762775ebf7c518fbd11cadb136377114a287a40c62b9bf52677df4e50f3ad1b95fc0e7f34dbbc0cda4ac10231fb2f5a36be3cf4085626b4d1	1660496844000000	1660497742000000	1660497742000000	3	98000000	\\x783eaae82ec2154e5c9ad14d3e2ce7a01764390e6aabe3668160cf0b03553495	\\x8769ccf09e8ea34fc0c56a60f4ec964cf507a82e6720df9beec492e4e213432b	\\x9d6c8ab33566c4587d7ea9f5b5d921b78b0a6f1ee72fc66ea91542c804d8dbb5cf7150bb011c8db5b41db0e4b5d0591148823c736e98dc33adfcf98f51ae0e00	\\xfbb791f7723feb8207efda8c8b03f95c21a2339ea9e29c7c4f68e479c92c4c44	\\x602d3421fd7f00001d79936b2e560000ed3a286d2e5600004a3a286d2e560000303a286d2e560000343a286d2e56000090be276d2e5600000000000000000000
\\x45be0bb109f61ca7ad3a550599a2b852602c53aa25d0125418e8fc86dcc48820	2	\\xa6eebd77eb7679e3100e6206fec477488677a217826f47d1f22434f946e5e504ffaaf24c1a9a617a816d8a579678c0f420d4a6cbcb8510623219f37685caa2ad	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x61c651ac7705133762775ebf7c518fbd11cadb136377114a287a40c62b9bf52677df4e50f3ad1b95fc0e7f34dbbc0cda4ac10231fb2f5a36be3cf4085626b4d1	1660496851000000	1660497749000000	1660497749000000	6	99000000	\\xd5ed3b64fbbbc1e505af7c1e32a3231a4b4a42d59d35410dde1b312f9dbd3c7f	\\x8769ccf09e8ea34fc0c56a60f4ec964cf507a82e6720df9beec492e4e213432b	\\x13f0cc7c1370920cfe1daa6a011210568ad8cb75868b3bfa59fe4ed8aa5945d9a037b3c29ad2638c0469acd2d69601196c611cb7de8c48c0e1e51e13ce387c06	\\xfbb791f7723feb8207efda8c8b03f95c21a2339ea9e29c7c4f68e479c92c4c44	\\x602d3421fd7f00001d79936b2e5600000dfb286d2e5600006afa286d2e56000050fa286d2e56000054fa286d2e560000301f286d2e5600000000000000000000
\\x45be0bb109f61ca7ad3a550599a2b852602c53aa25d0125418e8fc86dcc48820	3	\\xd720212ae0eb064129dc42076d7fe438c1c9faa21d7f3d713836ca6e76af7109115b4db437fbfb39a6a3d6e47fa5f6197e4f5c97a42ae7bcf16df9357b735ce1	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x61c651ac7705133762775ebf7c518fbd11cadb136377114a287a40c62b9bf52677df4e50f3ad1b95fc0e7f34dbbc0cda4ac10231fb2f5a36be3cf4085626b4d1	1660496857000000	1660497755000000	1660497755000000	2	99000000	\\x92203c16ba68b4a4f2ba445d68b1e3375b5411e0eedcab31f76700e55c8a2039	\\x8769ccf09e8ea34fc0c56a60f4ec964cf507a82e6720df9beec492e4e213432b	\\xf34e511fa0f13ba105585d1c295e2bc83315fa3ef66d1d9e7db038517c3b102db40a985209c0c8d00bb81a4fea262afc4e477df1ebb4c71a84c07399c7f1860d	\\xfbb791f7723feb8207efda8c8b03f95c21a2339ea9e29c7c4f68e479c92c4c44	\\x602d3421fd7f00001d79936b2e560000ed3a286d2e5600004a3a286d2e560000303a286d2e560000343a286d2e560000a028286d2e5600000000000000000000
\.


--
-- Data for Name: wire_auditor_account_progress; Type: TABLE DATA; Schema: auditor; Owner: -
--

COPY auditor.wire_auditor_account_progress (master_pub, account_name, last_wire_reserve_in_serial_id, last_wire_wire_out_serial_id, wire_in_off, wire_out_off) FROM stdin;
\.


--
-- Data for Name: wire_auditor_progress; Type: TABLE DATA; Schema: auditor; Owner: -
--

COPY auditor.wire_auditor_progress (master_pub, last_timestamp, last_reserve_close_uuid) FROM stdin;
\.


--
-- Data for Name: account_merges_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.account_merges_default (account_merge_request_serial_id, reserve_pub, reserve_sig, purse_pub, wallet_h_payto) FROM stdin;
\.


--
-- Data for Name: aggregation_tracking_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.aggregation_tracking_default (aggregation_serial_id, deposit_serial_id, wtid_raw) FROM stdin;
\.


--
-- Data for Name: aggregation_transient_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.aggregation_transient_default (amount_val, amount_frac, wire_target_h_payto, merchant_pub, exchange_account_section, wtid_raw) FROM stdin;
\.


--
-- Data for Name: auditor_denom_sigs; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.auditor_denom_sigs (auditor_denom_serial, auditor_uuid, denominations_serial, auditor_sig) FROM stdin;
1	1	5	\\xfd61a41232d02ef7022700797bcb4699737190d18d8c1ec18d7f36346fbc1f788f04119a07b313801f6abfa85845990377ff66f2faf19747e397a69c0d073e05
2	1	16	\\xca3113c170a021e87d5aa69ee0c1773297ae3a6cc9cceefb7d6a6507edd52d4c8cb0cadaebbdd6596576e6d0b84bb08ea0ce21c2d07bd68d8293db1a88675a02
3	1	90	\\x767566d94eec485077b037fb9950879c19d9794d51abeb7e6d8cc1e42ab37418fd341eb6aed080c8ca87fddbc0567c39c00503ce28a51f25686895e9f278800a
4	1	303	\\xe54eeb15752db99484cc1cbea2b23ca3ee1bba64bd52f68e76b30f75482470157360553b2c6e267142ab0bd6bc646516e4c7055ff1bd1b55beb62f8a4141e307
5	1	179	\\x320dc35d647af63aa418b263db28043bdf670091b00aaf11aa6fd0f5b2cc349070ebb9c81842f83fa11cc5a56cf2a890abde08ec0eb3d24a7b332898b062db04
6	1	81	\\xc27b2169a0da7fb56db2f5d40c37397e9881e39061d9dd8227926df863da1f69a066628b7ba078e35dd1699caaa599d92985fe97f855c07ea01c0b78c293e403
7	1	166	\\x4e51a2d9f04ad70293c0bd505182552e44962eb0f48ee7766b9e49c4b648454e1203b776dfda6bfb8ce486ff5fb68218b1791de5de931332ad7bd8f68e505f02
8	1	126	\\x97142d62c93ad19a803b7600ee0ee29cb1f358047e2a0f161b9a68ef765308dde7031bb535702f2fde711a0eb15876695cd8a8d4c9fa54b3d0e96475610e740d
9	1	136	\\x4d1bcaffbfa9fdffd789ed6175dcd8531212378a653f3320dea474fc110832cbd0d3a5742aae303e64fc82f42b64d6b4a854d6c75105be785c2c09cee694ca00
10	1	335	\\xd501b6bf157a0b79703e2cfa5c1e05fbfef43b217500482f2fa484fbed01142eefc5af2c7268211e8df3743e107b16cecb6fa820f958aa44a9bd2f3ab1181d00
11	1	15	\\x92f4985e3de3c0e284584e7dbef6b42b2520a9993fa45886904e2f2dc1d860df6dd28a021492af80f4d8d825c397d21e0999b7090cefd7aed8ff33b279caaf03
12	1	367	\\xd034833c3f9891546014470caa68ffb5b4212d1bea0a4b12fdf57a2767621f7edef71ad96189d9f50c390b2c7f7fa6240d05cc7c6222fea21b19a09b65c9850d
13	1	253	\\x5593804ce5317284f2093a8fa75208b0c57f8b2fdf5952a23c3233a73e2ee695783d23abb91f74e5871bd027a898880f4e351f2a6739eb8535dd86e6e0c46f04
14	1	22	\\xf36dcdc7a47439eda629b8524f7e432fc6e1ae6e1f32fc962c5ae03d8675b7cf7c70a803f1150a5fde47d890b2568189ff6a79c24d507cef39052a0d5262a305
15	1	292	\\x460a7c0230f0994d54cfa8b1fab86b1b72eb4f00281432e841d487a5b5abafb091400663b24733e13acbcddc8eb3e207cca09f9c101f3dd850a08d16199bf909
16	1	324	\\xf6d0a754105625e6612fdddb7805fa75583bc1d5c713c4715fdd8f83d7b3d655b748770dc46ebd9593b5574b95057afa41e41d8af418e174f72ae0342a547b03
17	1	418	\\xadbf6a524f59688d6adef0ac7439b7cb687cc4ddbb20700a39cba969ead4ae4d8edd4466f1cab14dd6defebeaa269a5a6d5c6ace6a1f7779ac88c8118d49c90f
18	1	330	\\xae2b86f06101687a95c9e76f3e314eaf8fa210c60f13bad6d1a5092c4f40b033332e22b7324d7b51a6b876ff9967abf3ecdb8312eb4f6b8c5a095217a21f6e07
19	1	140	\\xbdb1aede8e1212619f173a4a55505dd4298df7537415297353a9e1d00adb75535d3261aa0862c65b2f1cfa61295fda881f36a6a52725f970a446fa40b6866703
20	1	296	\\x64a3871ee8d0ea7fb85f8187164fb3f1626ac29c9b83f64850bac94d329db24422b4d6594bca5f31a69edd2ecdb8913d0be3dac7a400be7f3ceb04ac03fabf02
21	1	241	\\x82f5dd540f6bc108cfdf396219a511bf3fa5e677f736aa9b793c3ce6f99d192a9320492b88462c823e913a49c5409ae5c6b5ae45857f44ef04e3ab65c9a78107
22	1	186	\\x7937ff5872cd544bbc610b9b21367f52f37e09e2d0ef664867bb150fb8d61e74901bc42e9d1b9457bd85d7cbff3d7676788d55625812512e461b1bc59dfb7308
23	1	10	\\x518f6cab9d27e0e882014dea849bf6a81b0155d3fb38c3365bcf5edc24261295f6c295eb6a9383618aef94027c7c4aae2072fe767b4e1295f413f1a97071a90f
24	1	42	\\x9caf20c38625d793bafe406400fb4caed909ffbfd8c8de0db0770979135f86df0a691141cc1b40d82c1be422cb2c816ac2d70b41dbc26bf13352aee8e6003e01
25	1	59	\\x6050fda8384fe6ff817510b2420c1dad92430555d32991df3bc0ab7659e45cac5420baf65f7c112b9093f77e5aa85036d0710d291b156c1abf710b9265d55902
26	1	169	\\xca567fa7ed1abd023b11b50a896e846b6aa08684108dbbf01b27db97f64d2edc978c340e9130be295431fbb190fc1156c665566b0305296403edbd4f5da32c08
27	1	410	\\x980737ea9c62a43c161b45519c90c86ffb8723403a5231341533e4e63e2fb82810e451bb6c2764a1348c01ad6e5eab1b89c651dfaf77056bdea4fb0587b5ce05
28	1	366	\\x99aa8c92136ee134b28c1d41920cc067810d55f65bb6fc63223daaa219226bfd62e16b6404c318642ecb5509adcf2faf78d037c647db5965b18193e1868c540e
29	1	309	\\x6ccbf0a81be70574a1dcc56239fd9ac90b813c5903b38b3a23f977bd1122a2898ed1a105ef9b35519dea8c2be6155f71a2e62e416e398c0d1ccdf5222ee49e00
30	1	276	\\x74a87c70f8194b404be00b8374093aa98d00579bab50d44163312009c1fec1a86fc207ecb20d4fef0332930613bf4f9a0abd52ee38f887fb79635386edc8aa0b
31	1	307	\\xb5431d5f798c15d3c82a9a372a1e7ff03d99c640df3599d8a76905a14f34a7d02fb5cd83ae27bc1a9635a23913e8acc895bd14cef59768590b5dc351c2cb5306
32	1	371	\\x67d215b4f92a23a49c789591d9e8bd7ceffd93b56b24ab26f8a30bf12220ad9199eb063eb2979aeafbef27dde3d81941b01164edba216400bfc77e06e8e6540e
33	1	195	\\x330eea2283dd0b6d6eac5ee2d137ea2d07e80765bc7a84595c9dedfad5462b955f8c2f078942dcc4de186e00db0f3e1e1c0551ec6e769765ee58a73892bf0d04
34	1	110	\\x18babfabcf82f41fb0a980e30513dd58fe197eaa60e6bf578f1f544d6d14cc4f92f5faeb6c0c57f9698e841b22ef9c9f5ceac78acc774f7837102a2a5924850f
35	1	184	\\x8f037000ae0076e7e7c19fc1d8c13ccbd6dca29ba0933ae2067a05efc214c8fce94b83a0c4c91707207f0a3a413db8087938bc2f6d3f2059a0d4bb4f86d64705
36	1	345	\\xb8234ccaf30595e7daad3d74dcd378afe48ea27589406278b5f06424f2e1d47f35f1e2ae31324ed03efa9f66b25525d1b23ca97d3346ebd162c1b1f5e35a3301
37	1	247	\\x960d794ea1d419add491daf658f6fe7570e9d4099da62595becfa49b7cb5d9fcebd472cebabcb67ddc5389c6e18feea66d64d4936ff38c147280cea39a019b0c
38	1	217	\\xf51edc1ac1d96910c1117d3ae6a6c27e3264f72b6f32c7df170389a5d344ce32d0a1a4e2b94c683d68ad7175561b94bfe0539d9bfb86b741e0dceb1c8083d706
39	1	20	\\x2b7875cbafdf89e7fe5f65b9e869624d6cfb53e5ad5dffa1280e9ebe0006f0e636f6ea8d7c38c22a993f760281d10ae6e3daa8c816d2d231e2bd724eb0217909
40	1	60	\\x3a7f658e7cfcfcca733a96b14156bb0a2518a8861956e0e5b815905b6cd25ea132a9c9f08b246763313dedf7021329ffcb5ed24ce27708bf1cd75ffdc10a1c04
41	1	128	\\x094f47770469cc82eeb7cc8fdea460c4b87608c16b17dfd0af5913ea02c06993fd5af4e13910c777a1e977f05c87fe160c89f87f0779a9e8dd82f6567f8dcf06
42	1	411	\\x8c77392625edc87debb60b654d3791e284120d5de52cb420a1e74e86bfb9316cf50bf52a4fdf932a4b1d1864a70b94b699ef00301648a50e5ec4be2b8e0b8c05
43	1	295	\\xd1be6ff861137673d5dac6391c3c297adf7f30a7f18f34b0e466235a0058b83f062c65a347f2ee8ead8bd43ae08607ae317b5f652c540cd1f0c861dd568d7e0c
44	1	204	\\x86539fa22ce5fc7fc65038f18c53a9b1779acba2f483b5ef1b6b5805d1d547f726ccc77bf6726d7ed61a1a4cf6f185549ebcce43aa96a2969667a7e14e3e7d06
45	1	339	\\x5864475976ede83af9af207fa17c9a9b199a237b4db878994c69cca211f5825f90d7553fb37e9e683700e82da3023b2bb3a5b6847d68186253df4804ca71b204
46	1	375	\\x5b2388a3391dce42840282261d85f5ce6df71d8734f5597b5b8165a1e2f14c16c3659bd0c5f96ff2f25dbd59622c70cc4aad52a85e4a8943295679cd4237fb09
47	1	55	\\x62688ba2afb0d15bb0fbb5d5a7fd818000018119f8da88ba4caa9db4d5fa8080f743f028215131fef27282347fe7e2dfe60b287ff57e5b5fb7f96c640ea8760c
48	1	331	\\xc8d3394996e63a9a65a63c413f78f7f95a543ce6b5dc22c09fda3b95634d45abceb5b2751327a0b24e6e3c1433185537e4075169c166adc2c95bb908700a400d
49	1	206	\\x92c83360d550ead9d6aca861b3c0b234a061be60340d293bcffd0946a0a7af7c94b6d462b845947ba36ec23d68615ac67af2ad20064df062dde44e84f509ec07
50	1	213	\\xc9c07c56489f070b168cff06a07f23f1edca24030a4054d7620b97c3c343dd8ae2b2207d91c0abdd041e5eeac53637e74f83d13066f3b9f09fdaf3e02d5f3308
51	1	103	\\x7313fc864f5d2ee28b8b547632046a78c6ce9591c26853862c2cd39d284a9aa9e6ff7c61d7499d5d5db44f3039823622cfcb8f90f0d48492d916c7fcdcd30c06
52	1	350	\\x3330f7d96d06f4603a617b4184037e61f66a814779d627295dbd50005ac528cacde240449daa2882f8b47e9ac61c3aa585fe1e83fe3688f1c9b81b5379aec304
53	1	257	\\x3357223442d642eeffcc371175956d5118ef102187750a8f5cd250ea0749e6b3717e6450194cfb854338c523213baf6d7c84d84cabcfc64d06b77e33f1f93f09
54	1	305	\\xc08aa1924745af0b3a7c6c1d541df9855743c0cd21c60ee6da78ee32a0c593cd52c3e68f6d69c5567ae9ad1c4465f732305c45430012c6cfc09bf7e74f5ea80f
55	1	398	\\xeeb52e1376aaa82c8b0b30d43c3a42d8eb2e3295b8bdff02fcb1267ddde522d37c77666dfecd099ebf11ad14fed549c40a3ab254c2691c38706dbe385cd31b03
56	1	380	\\x05439deda7697c9d9915f684e430d5f49cb9eccd568cd5b20f26766c0145428b20517900b8bb2b829c5382601915f3556d6676df75a6d4e17addb0dbead57801
57	1	76	\\x290a9e7970bd0ee1e358dda6445c61c8b6ec0e083ba2963986320e8e028a28f1fad9246a2426df2538d3f7bf284c1d7a3031c8d7167d14eeb885aec86c30a403
58	1	151	\\x38971576be29ea7500c310c2df53ea172b2b66124ddd82716a2dddc9235a528c7a8a8b9a5c89f42a37ba7a901af65a6a5e35b68e706d3598421288d2dff13b0b
59	1	4	\\x04b21d3388ebfd65781e1a81432a20bca8f1f2fb5311fe80484deb54389d1a1300acd1c6c939d71973dc607b124dde12cef48d782f96e9bf8adc1fac334ef00c
60	1	54	\\xd10edd00cd34506eee622594ed9aa06fbc33c76127a0050cbf02d4b1ed15a7be4e619d5df190eafcb7441fd7975bb28e64490cebecdff8f3428495886d492700
61	1	159	\\x1770f2fb7a828e4acc7fbd3425e3092fc59f99fe2539e9c88de9451592c6520c6ff9b7ed64f13175008b3b0ce582bc7764f114afb4487b9874c0bd28a2b9cd0f
62	1	212	\\x3182a212f864ffe8bc5f8ef652bc20c98b83e76428de47fe61a724f91de9acd6b1c4607b73b4dc1764e17d3382f69d9bc6177ca7943e556e5b9a0a9f1a88d30a
63	1	334	\\xd5df7ab02fe10ec56e96a22f961a50598c30835d0dfd8a1c70d8666b36119adb2c6826ef6ac8f2b49716788c9faa6d7cbd47c2a2dac6fed536aab9b09d5d7404
64	1	146	\\xfc42f86dee45a4993e2c4c4517fbae1e454e28a34fc2b82d708d57f2c27f942641a49e5894def81b3a05e1d058c21018bd04c40a4311ed45dce8bf6d2d2bec06
65	1	160	\\x3510edf8e7386ba3758d2d24e41cebd1e01a1dcdb62c299405c0118b752f086b9ab1616f9fb76e23cdd6123baa92283254709b27d73b1e1f7a3f58ceef7bab05
66	1	301	\\x94ef019667c4c27130ea37bb7ab709694867f0e8ef0804ea8451af33519b06ea00f0896b97451d8321b0f28ae94ee393803f9e9ee6d50e8d4eb13b188df95500
67	1	137	\\x5ff8818d032e3c4619e726ffce3bbf4188b2eace477c74d9c733a056a7d34dcf6bfe9fb3322d3e816609291cea249a226fed942bba97e903bb33f8c9dced3f02
68	1	294	\\x78c7192640f550535a1566e86f64f70dec074bc12b8602065d9e77f74c7f366a5a931bc098eaf79dfb9768fe9f96efa5fee1215e28c59dec3a7f335e34471d0f
69	1	422	\\x3a8ab8843541f23b2467a919bf779f34238eb1584e6505081b61fc2d958e8240259d22733d27086e78585bd9df030513c7a72abfcd35d7ef85b1bb9c29ad970e
70	1	420	\\x37fa488a1b63f9b46b1bd0e5edd916ff2f684c40ca7200d5557319f1ba8982538f0be6b72fae62fa040e695783facb03db9673fcbcb898e26ffb02dda0f5eb0b
71	1	269	\\x4892369610491ec6da511fb1384b825a9d0b9800d53913377c24cb1494e66cc0f2584c8964a378eeb94980ee461120d30def41cd144aee34970fd8df30290903
72	1	92	\\x7bc416b91354b67c7452f4bbcc51172821ff0f984c66edb6a1b18ac70525e30727f6dab15e0748dfc98c074dffceacf9d1c806beb85be9d3c19bed09bdcf020a
73	1	19	\\x299e0a54a39a8cb86118671fd1d9183cbc176b08df98d0d549bd7549e2c7420efa57f4df8adfd48137727e78943903a0b01b4f810738a087ffc45420d85b1600
74	1	194	\\x8b061b14f91e8432fe403b22e752e654826bb83131aeee5d2ed43abd77a487e2f91273b28ed062bcb3c4203a9031c89c0dbebea1df093ccf7069144e61ae000b
75	1	326	\\xaf39383561cc48570f0e3361e2e2e2538b065593681f9c8bf6e8544a8e1ca8c0954e3c02b58a0710f3c4c8c28be1d04165bb542fb110b67cdb1a0ec9c0a9e204
76	1	106	\\x0eead3e632eba5cbf69c9ed359411ffb4245b2e3c6230c0bd9a3ee2a655f772e17eb88317891cfbbba0684dd37d17f0438c53654af77000f30eaa26c82d20f07
77	1	249	\\x6e882d154e75d4151188bdecfd0debc5f3433a65e9e322159759387a19d7235b2b1ea8ad9de34bc8f54bb22cd728486b23e59de39c20f47bb68bb39bbc290705
78	1	67	\\xbb2637577e08f9657b90fd1d723a31024fcb8cc18e83e05eeb305ebbe7e180b0bca6a764a22283d8e76396e3bd5cc6dfe9464b742ffcae4b34e74c9f05ac2407
79	1	356	\\x65c3eaf020c7c59d1b2c2281217a4b1402e5451d95cbac3768e53dd7abb83697d7e9c0a2a55f34a57f1e67960f8326665064d2f5eebe24c1978489b186144009
80	1	182	\\x6b6001663ab3f128572036c2e5c5de9342e8a3912ebfd9f8d67a2178f743df8f3ae36568e5db255b509033a4d2d452bee0baa3d20e28d2fb36daa3127d76270c
81	1	214	\\x550aca77efa34d8d4f6c3395492e1679786450d71d47b8afc3456760db31bdc9ad190f718e5ef4456b87b9b4f1ec1fc88ed4d464c19a520f1736dd614fadd10c
82	1	70	\\x82b04e483d8d9bdb0f888513d0ec93f0c888c172123dde21355382336ae478f98960f96fed5c13fc40842532ba6112628c31d58d0dc1f3fa2ab27856f276e004
83	1	104	\\x4ec76c63ff69dcba0e4f367a3f5524c7efadbae8b793fccb8d409402bf95650a374269fbde211aa96bbd6b900cbe3d5472ddb612843b6408f31390a766d9210b
84	1	363	\\x5d9eaf7666bac422587b4efd96a062692469df05ddbe2b307fa1bc6ca6b71bd3b05d2231f1f3d93f281b429cdbbc9d585e86e052b806f499c875330fba55a10c
85	1	7	\\x0686fc8005e21ba3d1f261577832d6270b498658e57291d15da636cbb563c69d5d23ed83b5c825365db1b92328df976c275cb372d82ebde2f113fe37496b8a0f
86	1	399	\\xcec8f839ca5e6a02c22091dbf73268e8842b78e44ba7fba5e5c02f05a519f1f7656451d5799a2f1df93a8a5a892d9b4c1101181c08388e706aa7f0b51ea0170b
87	1	32	\\xce6f8260d2b88e5b8b4483076c74d6007bfc1e46324ed8540aa911e04f408f883747c002e1781cfca86275fb33cb0d26f062fb74e78e1f508a39dab175692509
88	1	391	\\x6d8fdb2c232a7dedb9ada06960a715d537cd741a745a7e5473552364e2241ac4826fe14a364f7fbd975c0c7a3208bc83a0ca8bd5b77c5b9f6bbf0b1fa4481000
89	1	64	\\x14c8abbd992a61024e378ce1accf6c49d041e0123f59b93cd2a85bccf648f1b5156adc1469e8e3098328633a911b1a71527cb69503af303f7a259786235b5002
90	1	21	\\x1985745f0aef689c898e54aea2bea6458b915fee7d1e67bad3c19d4ff7096b3ef03f8b8332ce5aca21e3b83fecc416d0d5bf83cd8f35c30d51a0f7b6ff14f807
91	1	222	\\x2f3a1d64b4eef9fed8f024f2f9712afcc3a017f81012ff9498ce22a9c71b5e17131d0cf7985c09b62cbb3a7f851c5467933b24d1e6cac4c070fd792925383408
92	1	231	\\x1a3b482b5147cdb6dd00caa0ba35d8edb0478be3023214f83a276d00adf463e307875197ac295fd7ac6f50e7fac0ac8a3cb4be0299a4f131c08228a94059fc02
93	1	277	\\xea0c1fab785671a091ccb4edee3325a4ffd4b1d022c1a81d96cb159691d6b0bee8285f3f5f31b5e4429177ba9889a2a1c439cdece0cc7369c18bb4be8a8dce0c
94	1	219	\\x75c6813964efc485fd075e59d46ee66c716888f47726a9d9282f569da7436178bf9dbaab6b01d3a17c0ed8cdd27b1f6d74a35f79096e71ee4916d41514893b0d
95	1	58	\\xe3a1c16f55bd266c769fac738574bed6672d21151765ae946923217ff4e28faba9f0e883f5c8a74b01bdfd6d0ca6845e4686730e721416686ba4887ebb9ec304
96	1	192	\\x6429e76db1a65b92c3c23761613c1cb98015c354d16217c0829ff99ae2a91c1ce9baded08f7b0e1b91b4d86ff2f5a6882f075f8be22cdff18ca3207a5b6b6d01
97	1	215	\\x8c4273b5fd9aca686634f64c235b64f69620bfb24d041643af1796b8f69fe488bb77c50c23bba3c40184a230ad76ceba9134bc218f920d335e205bd4a0f09f05
98	1	112	\\xf798a8b8849bf630b1ef6660a0c135a685f561c27a5d28fc250b4dcb70b4b2847139ca1aeb2df7188d9724bfaccbcadd62baf58ed2b2f5f5321726ea51c6d50c
99	1	187	\\x430418bbdbf353e8075009d564e0c017e0f2c45f429db3322452490c5fc1f5372910f8e53cb1968ffb495d6655b4a68e3f8523a6d6a28fded53aad9b7c4e7e07
100	1	95	\\x08700ebc257055c01c1b04a9bf67fe49e581a48fe97ff51b32551b7d1c45ce75ea3ea266cc786cc79b7c42444be9d292f5f34c696dd77fe4a1da04f7c1b24d03
101	1	125	\\x42cc6df49bebd6e0cdc819444a3f86329b4af6262cebfd65e94bdd1dc1a3efd3a0490c3c793ce0396b871ba62b77c1cb9bb5493a9b0f83a8cd7cb3a9860d860d
102	1	361	\\x19b2c737b482747ef336b58c4680b0396ea6940d4a32212fe1f5294b88466172fc618a1417cfb785be0c3adebed55b4d29cc640e5c0ae963252255be9c21b305
103	1	18	\\x7bd7ac32a7ff1d476f1776ded3544a5606da051298e494f5971e763771e1e03d6270ee1dcd65aee2e5fda78c4b0662869d34f8d2e6230f956820fc82e48d8104
104	1	273	\\x560fc987cc6f70655c4c1c538f9ef48fb0940af3dc26e5a006f6c929743fa1f46263348e021810c80c3ef21b7bfbfa47ff87787f486e8fe73af624aa201f480b
105	1	31	\\x3fd39e869cb4e5878f1bd52e93b80e6bb72c7966c10fb610da2312b2872a3c82e9a2233acf90e382ff201b785fb7f00fe78d784eb904042a04ee1da7449bf70d
106	1	369	\\x368ba974eae80e580065ae807d58dd17d3fddf0e40fc49224ac43882123a86c14ca7b6138a37712d599224982d9ec8cbfccfef89541e7321e2caf26707658808
107	1	285	\\xccb944a89b77f6a5101bcf0254b9094c604b19deb0555f43cb072bc1fba97dcaf5f60e00ae1dd426715fe30a83a5438daa5281528e36a1a50de47e9e521eff02
108	1	117	\\x9885c6aa445fcd873208ced1876ea7660641fb7a630bd094c205258c571a56f1762b5ec0a986096fab1cc1b1c3fcf441fecdc39ee0b998c5153125f9bb670d0c
109	1	193	\\x7ecfab71aadd9d387e54fd0fd9bacbc6144bce348d16ac04e14401352c4c0b3bb99dce416b17a842eafae53270a95f6fee44ca1a8db6ac80cee87ca3a5b34801
110	1	235	\\x222e9dd2c7d888709506eebcf02395da4925d0d0b137ca14e5635aa3507df457074a38e2620dedd94887000b7c1a1b8be48326d41958dc74c3ba1407d468f507
111	1	327	\\x4214f2622b2cab1680fc0b6bf892d4311eba2de60a6e4f69868c397e5c9d08f83ef689d514f846b015a03d580e4afc3addd024836bd206a20781340038ff1108
112	1	393	\\xc590a238506cc1fd252d832d6cf343d5d2d5135a39a4f9c13e77c89fdeaef1ef78018bff81972ee736c9eac3f67fd0f685c0dfdc3a590b9e799408fb1d00ef01
113	1	175	\\x835d55613823264b077c37e354c54d50e7eb9570a532d72e1dd50233a8530030016bb98a50d215a672c7e21e0c0f1aa169fe325d0c46e7de67ad5963c477b80a
114	1	266	\\x4fa4866a957651b694013ae4d9c5d4c82541c76f9ce30f2a6cc5a69a3b42399d74b4ad414c593b77c36909c93d355c3aeca143d732b58cc43b9ba4b13c9a2a04
115	1	111	\\xcbe41eb74db5b642f41af62fcde73fac625e90c24f36ee6b86199381eefe5b4f3dee1ee83b5b3add4c5e7e63204c4d0c39fef8cec84184f5cc4a714ac6f81b0d
116	1	318	\\xe55d949b3bb7b792ff1b1e3483d7df2e6663140c89305ec71a9ec6d7155cb8dce84b820725d7edc4046444ea0015a92e307647f1f9e740d1c8ed376daa391a00
117	1	265	\\x23ae89e8a58e6f6df077b4101fe9a21dbc5c12880b17dfbc5b6dad71204feabb42b973e10fed0a446d49a3a33bae9867c9b9cc85c0573f361f0485eb1a11a307
118	1	52	\\xc332cf8a7b343197bb2c412b5e4bcd7c432360e7a82aebfafa3175e3c3a01d3a56b985d559bcc71324d6ab8bbf36be3e2348b549fb7d54e7b05ad5ef4be3c30c
119	1	79	\\xe5ec6b5d5650e9723ec40d9598469fc6cf73c01669b5a49051ec82e7e2f7d2639c7701064f31a3aec56f80c6b175a3d22f8bc394ebc43153ca48428f6432ae03
120	1	223	\\x8251cbbf7f9ed06b98115220576872ac5fc46a70ac54c50a59f0de429677c9fecd0431b4058a30b0786dcc1ae1d63cdbcfd9e5d9e51976f8a8484cff77306508
121	1	394	\\x87567097e2f6436b02b75d5b3adae224255207b4dd799074643d32615528e41141bdea47c34847fc5c593d3544b471f93384fce456e4b8e3d3317f7db88edb03
122	1	321	\\xedbab59d77448c7070561b38700c778bf5180cf8ba8528de501a0e0dec8f6b3d46caf114f2bd9c55b3123aa8ca72190e389adafc0f8800338e1f3d80690a3c01
123	1	47	\\x17e29f361cfe4b3e67013c14407ef1f8b73d515c48e543a879b1c68925039d6299178bcae1771122b62bb8e0b2936f59cc7dc122c9bd822b52561fe1ebb1f608
124	1	25	\\x80041871619484c7002263e4d394209fa0ace8b3fe0aa8d1bb80b49dbab85d4d314420809e1635525efa2a84b5efeafe4516dbbb21f6f5d0a8baa42348e2a004
125	1	91	\\x2f0522a424e309a5aebf63215c281a35454357b93552730e3994b0b9f6cc98fc13916b527fa74b3f78be099ed8a9494baeba62066bde6bba588ac4c6a31c8c02
126	1	382	\\x40625397bf019038e447a45f4ac93fcc817c146742b3f68dfd45991532d4bd79da2fb92bd05ce48791b7cb9f6b6287060da52160f3edbffd4fd14c318096fd0f
127	1	234	\\x71455ff937df2f142cfec29d96f47071b6f886f1cc4858042c42fa98b77365d3e06702ca347cdfa672d73bccfa2766933cf1b5ce8873846aa9ce2f4015ee3904
128	1	378	\\x11f0b5512752728179eed1d7630481e93a25cf62f1d1778e8c2799066b62736cfae7306dbfd9bcf993eb18155f1dd880c729181dcaaeae4ad2252a1fbab27709
129	1	6	\\x92d1a6d87554230aa5c1f18bb54b857e0f0e5ba8818decd363d0ee5a36c01ba940ef8f31138ab8c74bbd9698c197b97ac93bb905e3116335258a7985b8498d0e
130	1	14	\\x6e2ce0ab6427211d5e81c86976fd643004f4402b4ccd239596a8dee224c0cbdedca5c15cf32237f255a409e5f0fd628edf4916115347e41712acc91ebf8fda03
131	1	200	\\xed3366492283e27a324ac9e4298c243af3bc45cf765f9529a9587fac29afd1e2afecab45161aa77a4946acf6acf44c8f8eddc56ca8bbf1aff4df7f4e962b9b0d
132	1	211	\\xcb16b578cebbda2605897a224dc5379524c43a573200d208c61936a963034145275a099acefb01b7159aec92fc12bf5ee13b0c3bb4ca7d72642791f0e4cc9404
133	1	308	\\xdd7e7abbb0091bdd54c811c67e7d3e4e5cd33981fa06ef94f9138cb267e41b5f0edf86811f31089d3e30e0a88eda4777868b4b251a0524fa658592e20de63007
134	1	268	\\x8f792b6013227dbb149560189ec8bbafab31041fecb12b4d003dcd1bf25d11f433faaaefbcb8a1eb9f07534b98989398a6d0e218b433ea388fe2d44dd49f8805
135	1	315	\\x1de07edfad7c42e4fe1694a34549b06593447408d904ed0420df3b49d75e150244e98d7cfa843bd831df5cbf87cb8d5a7684e43eda169915404d50fa2c9e5d0c
136	1	17	\\x1f97dc9f65ca02ac3930c8c441d0526c65e8edcdd93182fd3ed837ce2951527a67598d38cb5483a644c932bcb9a4f632f20a16c4d64616b8cf0ae2282d33b10a
137	1	254	\\x6160a3bfe649cc1fb69c9e39736bd7854cf45a7378b76ac94153ca2729aea8b6bd639a71742a9d881017ce39aff55aaf4f89384f1a14c1ac4b9089a3e61bea04
138	1	400	\\x11297be0fa3a483abb46ce48a639911923f5a04c2deca83152af0c051c82f773114d49b98dfbec7a6000bf8c3826ae12692b13d06e53b421a3d5a4616dd5720a
139	1	297	\\x60623e24b6186dbb3e378b997465c01fb204fd79102771f24cb395e7a05e20404f7940d16c1a01d7a7021e94af1bfe6f670523b72dac7e3780ff55b331829a05
140	1	157	\\xd3148cd55a673cb1b4c10f10f638faa190faf7a123a9c80190864ddffeaa57a1152beccefb489a565eba9fbcf7b875a2d290b640d09e80837f42d3af5fc63b0a
141	1	260	\\x11d7631dc0daaddbfa835789a2c3406e290d5a0a2c1b8e84a43a23ebaeaebbcbecddfcb1bb2f73d093263881066bfaf3f5c9f804289bffb165c7bcf906068a02
142	1	209	\\x3bfcd5da246f6f3675c6cc05c48dc5b06dbd87f147ebb1156a706accf768522e0e60ab38307cb7aa205eafb0ee5cfcd0c37fa01d6513ac03763e7483b2c06f0c
143	1	13	\\x3c1f24e8a7afc5e074c8d4e13aa0fd853d46bbc07338c69cb953a52efafb3c8f22875387d1b5db9c2680b854eada48f3ef8055cfa0730f96c120b2214d7a1f0d
144	1	33	\\xea2cbd5b9bb53e3a49c19231461c3f481ae4ffe90430920c0035959ee967668d5501ad517dfc3f0309307e30cf2a9ed3a79e0af6a7de3588adf3e9498d46850c
145	1	230	\\x90c5d8a01981e1d7772e88a17973dd1edf59e8086468c01b1989cb6a0aec07b02114b260d89ae2de837b5e7ec9a3a893d909a6f74e6ff9bbf1a06cb170c95106
146	1	118	\\xe7cceb662c685064ff63affc80ddd98d5f76b11008d2f6626cd589868944d0d502e4be614896e227c832eeea7342e86483e9bbe7037e30c599f9cb5fd4246503
147	1	198	\\xe585f20b714a7d83d29cedfaa2f21c99edda3d6e8ce8d79fe68f514a3967c9aadc484d05fbfb5934b5645ab93ef25ac57ce2750ea6de76e60dcbf05076056b09
148	1	362	\\x366a69f1dba1f948d5536f61ce3aacca5cc354e51ad26c4b23cb399a56b4a1c3f26f2373a63d1aa6587567794ca5f1a33e283f584f5ba27752fe7d438f850c08
149	1	127	\\x570ddddfb91fe15a3797c22ae3f1b81a85f5940c333ce4023fc656553db4f9ec678e3abadd77e79aeb55b92ff32075f9bd3c10b009e7540252e8f23078d92e0d
150	1	388	\\x58eee5b51ac65a7d1a82efdf0f5ae90b14e6cee674871eadd0c4ccbba93e6c6f5c309cb0d5148c4da8a893ada05438b2e10f2b5ecd7fb10e531d5af9790f4a04
151	1	412	\\x26e7d8f407a460010de78067eb769a7eb333dcf54277ef86da4b1aaa19fb6aef7be89e7812a19c334d9aed535653e215e2386320504512245755fb2d8db5d60a
152	1	383	\\x4a09d08096904c888b09a99b3043b719784a92f4fd7265a601bd702eb6cbbcb35bfa029f603e4475e1b2e794780a108959b7847a3a60d5b5ee09820265012606
153	1	346	\\x4d0fd7067c8e65bd2ed38af7bfd4bd381c1c7e0d8c9d1adb342f3d83e5b6ea1fcb26707a2df124a24bd23795c0ff1c3ccd858cbc90eef916332b635d49d1b504
154	1	406	\\x30522de9060e9593f73dd7144b3ef959f24cebece18298e1bc2f995d51a89755b91aad9880400a0eae401a815ee332c1b712fce09faea698e6c82b62abcf0807
155	1	74	\\x09566fc9a5bf3ee67e77c8db982b5440770ff1cb2f2ffa207c36fabed4748086b5d94f6c0e293727db1fca20630b7a1f8e01028185c2ac169e92767a37655a06
156	1	402	\\x5fde7e93d010fa27ea2bf1337e244e7e47485e53d66c9076838987db2bf42f1c40b6b7aeb4afc39a5b12554e45552730d2af4876451802e4efd7e2f318e60f04
157	1	278	\\xa1fe308bf6edfca29e47d15cf0deddc61ddfeb248c3a67111f6a521abbeef10e8e98232a6b49429f0e5eb3bc4261165f88149d64067138844ccef2f668ecb20e
158	1	274	\\x565ddf00dc6a036e1ba3531a8575f3178ee6cfb3375bf784a4a3c9a2584135028767a9b7ecc87e8cb4f61e5d6f83a3bdbeebabac0f4711dae59c62914856fc09
159	1	129	\\x3b582248b17557e2d46c689ef5493bafd24040a08735d9caf255562e392ca3ecc7daf80c9bb96ff4ed3899ef8ff4b566a7531cc8aac45f587530b8d34c08a901
160	1	243	\\xccb79ef86100622ab1a3cb32c4ea030fc6908e77ecc57805478b30bef2d588c2fc17b5a57ed7931e6d8d46ef5f946385cf9ed18fa94f8b70a068a07e09df3305
161	1	288	\\xdb2c358c314a83a435f038e3d0720f9ec44f40ba7b2bc0e67ee667b86ee0caf21050947a76c2323e5eeb23ba035a04d71804433f508578540eb40ce70f12e90c
162	1	93	\\xba3d4d6961002f755540c6b449d190fa875bc1613ef3df852d658a181d1de26675d82290601ca1165c1ffeb84228482be50a6b544c33a02b00cf3e4da1689101
163	1	205	\\xb5f6e16bddcd04a2c359b8aee5e9d49a873049ff531e4f3b590e10c0fc0731df6688645d4492b54e3b323ccf8f70f6c63ce30b5e481af83c212b800c5ca23501
164	1	316	\\xa865bb6954b162b09a3c39190cf7b289dd8f336befb692d708b1d35732e4e349b29dac27d54fd3956ead67ef61cd77e5ec9f1dc09686ab19776addda47814f0f
165	1	221	\\xe56f2942436b8f194ee953231c8c1bfef49e5bd02dc261c1bc4869b9ce04435ddc28e6ddec7e271e093a5b203753db82634c56d3f8570f1924e33c1a067ade02
166	1	210	\\x32a2d48e7544dc60a82fe529ba65597189b3a408886a5a15f4ef2899245d6ad65de24c3a15e2b699108818beb2ae7a4e0aca3160ada3c6975f96c9174ce67609
167	1	61	\\xc11d31abaf01d18e65c84f03a6d3a252f086005dafe220247228eff5dacd85abbb0e3adf92e4f5ad7cf2f4ab53a5eb7567203cce5eb4a1df57ba65152682aa00
168	1	77	\\x18da398109128cc5680e27a6e8b6ee44beb44b15c21ed35f8e2362e7fa73a417dcc3f1a1bbbaec0b7eaad539eb7ebe00bc3ce35dd30ce716bbb0fde83f546904
169	1	154	\\x74f0518b42065fe4da7306e9079bb3825289ddcad7e69f460c520a211b1c061c39e6665d495f32556812c366366536b066b31711d1e1a6c025a53b259664cf04
170	1	357	\\x5d1efd01980028b8a9b6a058590895abc6f1f354daaee87505e1ae17f0fe26a012a5ed3c07eec88129f7f140bc8c656a1f0127958ab80759e5ed6d70eb8ac50e
171	1	121	\\xb0a0f10e4b74ef0b8ee14e7a45919fe3ef9a16783593bcdda2dd9e9ec1605f2db61297ec97157ba1a3d89c8459d7c9be0eceb5fb99682f7e92842609ac11e007
172	1	120	\\x08af1e5308bcaeeb62335a1f3e02d3730b1278e1f585a73d788042e3a9b0efeb79186e8173873ed2db5341b2055584a1c9652f3b81eebda9bd560e9755915809
173	1	147	\\xdf1db7fba0ae33d7489909b16cc55374e4a6f12afd4ffe576100e2916d343f98590225016c67e8c4864ad042cb284f51961629d08f483d40dc4dc7c41898110b
174	1	158	\\xe036a508fd5beef29ec3101b415b6830cdea3e1d195e56c0e7f332428f8b8b77a55e3dcf4e76824122ce40dd5f893f91d17dc4be4d410ba4f5adf6b741ca7900
175	1	9	\\xb6c533574b8d05ad7fd6c76f37d674b4ca9caac2b91e7b3ec6960dba1e91577f4351c8a279bd32630375da3d3472ae9c5a94b2f0c3adb19f9516171d7903890d
176	1	191	\\xd97e20fdf8ff220f45b553a517a210ec1653d6caf997d435cba4850e2a18622e9aea631926bbe116cf59bcb6ae74146d2a5575ec35303270f9e851fcbc6a370c
177	1	404	\\xb292235b6a687e56b6f55767d6b9fd5d7d5a8a5976ac29c2678c6127337ab33b3159ce47e86a91433329c76fd5b96ec2e84225af7c838797c0854e49e977980c
178	1	379	\\x452a6ab8178d083d4d061a0a4a3179fa21de7fc65f14f546210c4a20350c36c00ebdbb3c895b94f66c6020bdd90e0a8ad5889cc3e64cb8a0aec68cacace21701
179	1	176	\\x350dd1153ac461e2949c143049b81bc628e761eba35d5db5f3b77186a641b2bf0418cecdaff16181be096e17573d94ef0e71f4acc4ac14a54d7f014cae6ade02
180	1	313	\\x85d1f3661b497b6524005a0abc541208bd231d29d40ae9732fd32d5677725fa4a1e8d94b82776d148309e9a3751ed5796364dcec0cd0c6dac4db2ba879acbd04
181	1	242	\\x57f0f625a97cb78fab901f032b1d2d3296894e1c099222c9b071085a98b428283eb60e1088055f871379a8ebf0528262154ed21a354ff1b58fcbe127166a0d02
182	1	396	\\x959169bc78670bed4b135cd9b8b1c4dba6f17051e57678c5ccd715ae49f41e032b2d265bbaf8eda886f385e42a0776852bb533082f8b5ba8c28a7a1468e16b09
183	1	264	\\x4bd7842b14696a02017f8d62922ac9994891c8fa68306f269f303989a09af7c4260588b107be54df52f4e69ad8ca555fd43cb69fcef64a00e8df7617c5637407
184	1	8	\\x6b60026d7441c89b7b8e43ad2bdf7dab1c650129bf93a75f319a5eebcdf06285923dd7704b7c7daf18f6c870c33ae00427b0e3a98dbb13d9d867d80faa6ab602
185	1	89	\\x91a82801c755bb302beb72358df190bf53f5c7c09ad7acd33a2e81dc253dd7312e2539369dd855772aa37f4a431426e83c97b24548052e8667d2332e4849cd0f
186	1	328	\\x22d951d7a78ee151c9c0477f5a2c9d885f9e36a6143de02ce06a9668b6569abeda0f1f22dedbfd7b924ae965fc694ab6721048e14426fbaa32a4439d32f2420d
187	1	27	\\xaf01175ca18dbf5278f9c93b9f62e9b1c5df8e2bdfa3d4fa1dcfa160868fc098b5407142faad1d6b6e3507b241d182626c6929dae0f867cdcb927dd73764970f
188	1	201	\\x9b6178bb9bc2e10d77f6d0cb170120523842ecbc5cb2ddf2c9c46849981af5e11332d536b47d6c9414f0df77c8cceeaf3bdd6f77da4651500334c004980d1001
189	1	227	\\xf6d0507e7d01ba3ffb27e74a622e7b9e5da6de391d7a82b0888d285766abcec2ff7f7a18b10b0b86b813ac67a163a3e35ca07f0b4677e55ec62ddc9aabc00e03
190	1	229	\\x5429902e950474c011f05af59568fbe697d081d96a9b2f4bc70bff2a6df3adc8e1733a5c37b8956471503ae900847600d37a2900caaaced9a199fb21c4a5e90d
191	1	199	\\x755c7b3894a03cc0af7a975ec745f0de3c42efbc35d26e9b179e50336b76ce19d4c6ea096eec180a1b442368c772524520955af346361afc8c96d6f67c22da04
192	1	109	\\x28470de528ac30057fbdef7d67a119ae78469526d0a48460394b542921e138c948b00f173a3c40f8a245657b92f114a6ae6e94a536987430b7a1ed0bd8d60d0d
193	1	105	\\xbbf3724637896dbb2f509f28e62f9a236fef936f552d05fc6207db147a10a848c067fc15ff9cfc45adb523d093bd397ed6ec3fedb1af20f86c6a400045c9750d
194	1	351	\\x03ef76697020f1b5291987c6c793403b261fc9f92255377f03ad32dfab1774a61b8d7c9cb1966cdab2033a3b52d58274f3dde4c27569d4d8fc690170e22b1e0a
195	1	408	\\x9fc27a9ad361a5a80dc15c78bdbc5d0d9f125c8c20b33357736f08b91c58baef883768c32e26d2ec1515b3171f0e59c2e7cebcd61577e9275848f577013e0003
196	1	302	\\xdf6c58bfef97ca9dd701943712a9d263e8b37be3b68f546a5940ec3ff07cb91bb1cf9502643569c35b1a4e0a1cf0797bcf0b3b0b9fd6bdad910367fb4c41be07
197	1	310	\\xd97bcc7d0b0c4656b075e976c33ff5a005680d62883a50e2bcfbc09a43f465c2f13d90c876df3b8398c1068ef8c3955cb5af8392b908894c94e115f57fa71509
198	1	174	\\xe838eacb62621b1e17d6b40abcb002655b6745883bb634fd5d3104f50fed5177c4113019b47c65a6bd866a27cc68f4414f28152d64314c94a53b09691376e000
199	1	141	\\x9a3e0477f1adcd89e37115c607a8458c03d5e2c6573d20fc08653caa0a6ae8bee90b95284648e07c83bfd08b213fd820e9eaf2d72119c935925a4072781b9f06
200	1	84	\\xf185beed20b10cee3c3fe717bf8fc850ff164baffbe3918876b192f8a9a0a31349a4ecf766da49020c5000d0ca42fcd5bb7b3a11becb28bf79e9ddf03410af08
201	1	261	\\xb8edb60d9911dfc9cf965c89694cd3a3f8f54a8d8ab8a64546bd4c84cff6e561e7cdc05be0fbb9c012b746517e83b40017bd35f2614ceb7c867baf455afbc108
202	1	167	\\x3c2958113467e6bf8757e67ccdaf7c271436fcc8901107b1361a1f51d0ff2a2d30e7664ee0e383b50868c813f96adf4c946656e67c47ec70044055c205d1af0a
203	1	387	\\x4039288ff1c3ca0f7916d6b569d40ffc05a1cd2c3f8656ae1e3d455c75bb36329fc08bf1b383941424a0392ecabc7aa2f301bae4e1c83b64f3d2e993c4fbdd0b
204	1	284	\\x118b772f6c9bf357ffd1315f9122e6f362c71acc714c05852e1ac91cb43587283ea17a64cb4fba410510b29a39bebcbd2f1627ee3b9ff0542c80c5450997f00f
205	1	66	\\xb30a2606be87e54e9f4429578ccdc631eef5c554e41f4eeb180c7f3c836989011ff139ba774c6e464f51f273edcd56d368f98342d5ddff5ef8440299df3ed707
206	1	73	\\xc030371c4fa82b8e7a53004ad7fd5fd4f98b29c692242825b238dbb4eb98e0ef1a6eda715bad47a92e55a9ccd41579ca4beb5e526ec69eb6230de8a001516406
207	1	124	\\xd4802d8b2200b04997fd4b975febcc04c007e955ac2bdead6a2b6c2509a3fc5e594758483a6587c76c3cb3869c63cf179bfa26a9c64a5b49d83610fc6c991409
208	1	80	\\x617cd07350f671371a200037e657efe1755f9ed473ec9c93fc195c40d5ed1d8dfb300661885ff78c386e37037cf17945b5e5ea05f4d7e15f65e19fc0d5b25c0a
209	1	30	\\xd68340b73702cc2750291facb5d2fca4c398876098f403a999af747a971147068b1797b26dbcb3f9746f4dcd2f2dbd9dffac1d2f5263e2d997ef98561c9aba0c
210	1	134	\\x0393a31dc7dccdf1f688a27796fd20a11238f1afd26e02076d318e16dbd86483a2132e500244a185cf6beff85d539c437f8cb84633083e2a0ec014598faf4300
211	1	149	\\x2c4e528782a14060683e5579146a35303df702581aec488549f5ce797cd1045e60d5be8842b08f9d0f90395d39d75b2ca4376ea6104e7aa1e54d2d049710da00
212	1	368	\\xb9dd9c83444f1ab1bd67a9906e91490323e549b251bb001b5d261e41b6f46b11bb2cd9b03cac5bf4c28b0afec768d3944ae987478e85dee7d8407bd9a199bd00
213	1	322	\\x554fcc0e6171ac2988f533db29522dfc4cf6c76c206396de55dc1b2b75abbace5c4c0777799666ddf1bc1accdb6bb7228da8260e48ce370899df23859a705407
214	1	148	\\x2a61303e371c9e4fcdc074a4a32bbb8804b699da6e81397ff8fb8ca85497eee460840b2622730fb19b631db0e47111a673c3c4440fc482c2387e8834a506b40f
215	1	23	\\xf1ec281cf43b9dd185f5e53e93ba790ae6620f0bfe1d5b9e93fbde0fb0c4d958ac2829b001c128d105d4772cd99416bdee1856888467b3aebe43493e7811060d
216	1	365	\\xce79faeb0616a2a97294c2b8bd16f8b0482fdfe242335613169217a7f06cffe1ad9fc9ac68f27f5b5e49aec0625bc3cb2b31077723bc961c7b808ca329a0cc09
217	1	397	\\x1f1a460a18620d64379dbed102ee2991dabd62c3d00b374aefda763ba235e1ed93036693cee89b2b56847ac27d353794a4e49274d2c15e79067914bde0261602
218	1	220	\\xb189c40dcc391a33b258a35256a36df1202acf04d8ebd0606a90d515642b5f74cf06d6c5dcad10f994d3388f185884f673123cc63ce67e29557be7ee14b58e0f
219	1	108	\\xa3deddb765ccfe31a8d74f8ae430e2a336ea43e1a7376321835d79b6df7e58cb4bab3c5dd9f2317bd7541bcc9568c478f0570249ff68cf5ab4ad8b2b51126800
220	1	181	\\x5488571c88d083ec3a206693db8a54b405cf7126dee6b9542864d90f62eae0f2043fd5bb444915d3b5e858718a7bef186e9948ee05cbaefb3f4b22bd612fb106
221	1	340	\\x238ea324bfde42af2effd44d426a9ac4f6a371b41abc522ef28045f0a04255a0ce6129534d1fe7e7c9f963b745dd72f010b34ebe1a694345fe1ba4c24f850408
222	1	113	\\x7d37473e713c49653a856b296137af0ebba0d48ba4ecd0755c241cc4c816f50c9f7ef3c040ba92b128262a8bcbf4a92139f7af7fe0eb0187f3c0f87db5c45a0d
223	1	88	\\x2847a2be1275b9adbca739029869192368f3f5e7eb68221e649b5522bcfa00dc487e18482705294a9048ddc8b9346dd06ca54879c72364fb0c78b255d9e65c0d
224	1	133	\\xe6c962eaccf040103b5edffa4720660ca54cac6744bdb46b394847dd15ebd83de52a9fe0de0d3f34a1ff088b05bd56d85d6d612baa522a92594f51a0bec9d604
225	1	320	\\xba72f9ef6ad16bcf5dfbdbbaa53db8584486db2cd09da1a6c0f644f93766cb3693a3c6d00bbfd1b756f006247588afcc872426fec21f0c25c64a1604e2465d04
226	1	281	\\x095a62499a06106892a1f607c9d6870e439d0ecabbbe1162fbbf7109f9317d34d9e1d9cbd0eab08ecd15ecc4ab1b5c70b925b2078dbb5485b1b991e9e8bf5c07
227	1	43	\\x34d69dda5b6ad4e3547faa8b25fdcb5e79b9d0d15caf45232d3b84e13b0f2aef738b2623728fd83423d0785bfa871e6d70757046685335be62ff739bd26ed405
228	1	319	\\x391dbad663f66b9ab5681201a0fff00535f2e650dbcc90041e5801339b74822c03ee78b840186fd72ea66464d13f2149acac00bf6e68c6e431d81d6ee1eca90d
229	1	282	\\xd145f7355d071b1ba07eb19c1ffcc43e4003ac1ed156c1a16eca6ddb72c6839d099d102d87f99f1c01ac15fc8ae7d1153b73b6aa9e9a0063ab7038eaee422607
230	1	384	\\x0d01cb9fb132deed81bf477588648f9c5fa085eb103ad5eeb4586615b4306db1c2523a9f2cfc233ed47e8c20f5537a10bb614fdad20516dc73bbb3270335d900
231	1	275	\\x9afb5e738b70bf7a11c49305075e93120c15d99d5d5964732fa4eee97754ac163e0490745195db3adc053922bb485bbf977efe968ad0d5fab39fef0809fef805
232	1	150	\\x7b4b03e947de1beee243889b71638381ee21c97f66e2cce613333355474e6d5a3e34533cd5b3a2801e3578e1b99780469c59a69817270316013b5e71bf5c5c03
233	1	172	\\x435c065e9915625cc2d11fa0291c9991ad21d8f0b7c0d7cba1bec12fe827a012f8f8bad25ca3196819978b86d5312801584b3dd262b81f4a9a209e1237db0b07
234	1	226	\\x343f29f4b99b2943afb879680f1218c531083768c20f9ee1bcffbaa3f79e12c557568ea73798a23b96a661a0fd5a9361281cbf9a2a0aee685f23e8a9aac4ab02
235	1	343	\\x3684c26fcf5488ddf146dc3f9fe794555b3e8be7f588705b036a1e39d822a317fc92732be26b29611d7618a07a453b75992759be2f546b6d942648a723804f0f
236	1	180	\\xd27b4909a4bc9c7d5940d7d2ef1d2f626c3cad89182616a63246b8fa1a2a32f956fa55ae58b65ad24170836dcfc92853cbec3297de9ca1a86cf6f9659c3a5802
237	1	280	\\x6b4d5610af32bc4ceda54342d137205af63df42f534c878b459624bccb949a08af4e8d8015893bba053cdf0fb41dd6771d0b84cfbb2b9b9fc20f0fd05de59c0d
238	1	101	\\x43933d0bee62a3d2cf4bf9e7ed7b4bd77aca05f5fe3d1a687470e1b7f19b0c12bc5d37760f47af807b7ba3ecd849be9cfa94f301b126653bc8ec164cc009490b
239	1	317	\\xc34a7c5fbc15a4cfae9a0ed809476d8cb52e146c55a0f033777d32b1442e16df170c87d20eb0b44035458d3eb96807e6edcffe41c70130be34f15e010817440b
240	1	349	\\x8237317d9ea3be95bbfe5170e8003f5d02dbb3d6171d51ea1b52d614d9469a688d631b51ffacc2ff8b10446747749f5e1245ac6772756193b2414032144e8705
241	1	173	\\x5fb18da393753f7d907c5048da7d98001a743dd82bb9f420b75ad6429d7d9beed65a02986df81a26c47fcbf20d22553ccf85b78b01b096a3f36f41a35fdcc108
242	1	1	\\x5198c1d84deccedb202a0f8b7dd835319c52bfdfb92bea8220216baed45e21d6a8d6a1e0107102ff7a6f019c991141ea8bad823e667749ef056cc20f6408c005
243	1	24	\\x4960d0fc94879317a6e56ebac46903ff878d06cd5af0ca51b0811114b27b714cbc71a99accbfdbb92c42886c5e2a75a38eca9e524f0756921c2ed1c3da4b380f
244	1	183	\\x2ca967e27eac1601a7635c3792069d10e05a422de7437cb7baac55175804d2839bb857abfebcaf9769782636cd3870f230656b5db4a9cf98becdc9c74a9db60a
245	1	100	\\x51bc84e2d69f5ec60ff7ae6c679227c948cf0f98a6fc653345206d02c3ba9c26b800ec71cbf8a5f7c6744f35cd07c150ddffbbd31c96408155ef7eab686ee200
246	1	228	\\xfbafdebf35b8403bf27a4ef7ba3214a85639534989b2deb52e0c7f367b4f884ac8c6d587df0b0c3578a1259ebd27231ad10c9de21379f7861b0040198fe0e80f
247	1	38	\\x31be6f8616fbf581e4565492409d4682fd718151838a5628f69bede17ce442bc215fcaef2248cab4e739613d5e1d750eddd8a2512026599aeed651728f5ef104
248	1	72	\\xb92226fad26c5cab8d59a3b052ade0df4600215f756907dc1c522fcbf3460be951f9348c04990fa7a14032aa82eb058546219ee221c40336fd4ac86f61986c02
249	1	290	\\x7fdffd7c3c510adebc862ba52dda618f9d3ee17f77ed40d528c7a308dd22c022af04b28744cf7a332d21427e58b3b651c6318829d66d4ce72062f116193aee00
250	1	332	\\x5e2143b013b12b0a4f1dceecf9429164bf1d54076daf7620db15ba71800f6ac141ea8c87250bf174f8f9a4533b1d186522f0b74563c21b083febda5468f3ad0d
251	1	71	\\x259ca5cc63efd5c547d62afa07f71c0d4405fef5a79f0230bf98fd715aab5a697bb0f0bd7e7683a7fcf8a76ddbc929ef63be879fc8c6dfc00873f6c5db46470d
252	1	344	\\x9c36ea28ae9242037bfddfbb1e140e56516da1644e97888486225abdbbe0e05f7fe1f71c3a8f1c5511cb7d83d02bd29098f34da261081bc38a463cfdb32e4f06
253	1	237	\\x96130886d2e188346f5d27565cedb4867fc0cdbc0d55a2130d237f01370e471438448aea48c41f0ce95706578125db5cd1d454a305f4d19909ae13dfa4727b0f
254	1	122	\\x93c68d021638a082e7a7190021200cf9d70b41d48aeb750fd5eb53d3dc4cb74315092380256b1f9b215ceb7889b57f288667120be53a266d134638052cf4b707
255	1	314	\\x825076fde56dfbf3ab989ec5c9b5b7a5e949eb21f78bd293196a8cf94ec0360c537ad2259474ce05a619e90eb42e5af918c08069c406cc4628213044c6248605
256	1	56	\\x9781593a3536a04a1a2c4b4959f7fb2ffa5f0e3816d013a2e11b3462894025c2de4a7f49cfcb9e3199d0eb42c7bb32f88f252af1d2e93655c9b75e070aad080d
257	1	94	\\x9a5fab5f56f77a250ebc4e7989e5c136796c65f9638b4248c770b080978ffbae65086a0b3d234401deed35ac7ce1941a3b70155ce18e4f00b242a8685ec0fc0a
258	1	37	\\x5d917da25c1b79a500e06dde0d693f12e9d1bcdd7cd50026779464e678498c4a1cfea50068b1e056d5eb3631552f42a209f4441d36585f194199270952bb340c
259	1	272	\\x86f82e397a18afb651a4f83504f1544ab80249d7b837d818937d3f6a225aa453499b3e8ec9f9e82a2416d2d52d861987ddce5bcee2d605788ac3bb64c74a3a0b
260	1	190	\\x48254f65ce9d90ac53f3424a5e584aacc6d62512b6b9e0553041f84838a131b5653356477b71c3e9eb7d3345746f8ef151cbda40f603eb9841604b905c804309
261	1	355	\\x6fbeea12491a5192542964a131abc449214370ba6a58d1b87ef40c943b263f7aa650d92bbd73d79de36230a8970e8a47f89f13c005ab050e5e9d6f93ef05af01
262	1	376	\\xa7dee586f3e7f0c4c13a9879ba3c40e586d7a86c7561ef95887822df35a674542b431763a366cfa3351d8796e23b6c9e0e47a368a675a159de2f7423f07c3600
263	1	236	\\x8bc89f6e05f06ba6804f696f30e0f1824e9760c1cdb8063cffd570cbb4e6ba3b0fc26041c9bc9cfb8a892bed3b0afe5c51351aa2ba83c6415c3f61ae9145fe0c
264	1	287	\\x431d0095ff4e1888272a5e07ffa2bb3006674caf009f2a0ec9802d3bf932455d8c11a135d76fbb02bf8a8dc86d79a7a89ccc354f0ef29b7df347eae393c3bc0f
265	1	385	\\x3d24a9e7a96f9dd44541bdd71dbb68a503784f5105aa0ddc04568b0b86bf6339ca2c8b8d428196e32ae1b880a8a171b62513e8432d20bfe09297c1086e799600
266	1	245	\\x156abcdb248e7ffcd144b44ac4ddaf12b89b0f3213bdd44c2dbc0e30d636c7a85d90835d074914093101006c772954397eb739edd477c8c48b19b8b62486a50b
267	1	197	\\xfe0960086a60e3b8834bbb7cceb0da8ced44833cc23b5db38765ede5e0f9649b1f0154e5fd6a5c7369a2c4012f2473d8a244e7289601cf19b2cfbcced3199903
268	1	48	\\xa5993b3e6ef6ba7c9d466d2aa1f5cb3510f399df5e017c9473ae321f92bb55d677be63062a8211990b2bfc0c5ce3bd9851b2f30ffe68ed6fb0e67ba1f797c907
269	1	68	\\x3819b153926d0f5a5cd76b09d04136343e56243a0b5dbbcc5aa5b57406807e2c08e2a9bcf4913785606ef6125cfc4762ddc58d3a68819810837957fb3206ce09
270	1	116	\\x37d9540bc40cb08fb71b6f6c912703ff0203afc02ea23061727b9ba9cc65073e5400d63bdacc91982894b0778c87230a1f1e213f0c983c08eb83e92bc5f40202
271	1	196	\\x4116a470a251ec8b842a56531add969d5eb753e5ff48bdf575bbb1882e8bbb4e445acdb9013bcc89b9a6c3f8224d13324427eae9fcb359dc8ff0454768edc202
272	1	300	\\x91cb6b0018c8590ba4b9f5dc8a454a4804c315f09cc33cfbe7eb479dd7a9cd595502c93b08c5a820da95e3fd3b5e57521477b8bd12811ce9daa6af1bc30e6600
273	1	421	\\x6413e982b9da46586d870ed2e0411e84be4e1c97cdb179a940bf0ac423818491ee6cc8f87748cbe8e9c321d0e0a2fa067bc21bd07affd5e66f1e2e1d1a639f02
274	1	119	\\x048f3bd8aa1ad562ced0ac50fabf09aa5fa45a6a3187d08a1fe71eb32ae3c6734805b2b175b6c3bd29995db0c81eb342b0c0b99995686facc45e8dc0dd37ac00
275	1	161	\\x2642387e1c7ff12a55c5f00ddb8791bbad32318aef88591b10ee61190aed66cc0ff9e10540815a54ab8f434e39be42b3b9ba5a7c802cb6b06953dc546d2dc70a
276	1	256	\\x7c3049a5add493a883d8005cb08a0ea122232a4f244884d694a07705f163c61cac059e13f0503718e1b897c1443dd03485db7c8fdc1952e21a5f7963794f650f
277	1	389	\\xfc3196c9de0eb11fc3404d7984692710737b8bd4a8408361ec9e4f5070af5c58a1faa47225e0f41ad6fb75222c285b03b8f26fb7228a7de8e1f809c53b02c404
278	1	312	\\xf3765713549f73091c7963fc2015a149e1758da0a3c0dae377793c8658c831f5967464b17a95e3cebdc4b91cf3a456adf66144be70fcf2d80a9511160342c306
279	1	107	\\x7715fc35b22c490edeeeab6e5ca6da0acb60517b7406157abdb760d64183acf72e3df8711ec1a60831264ed6e79541d3cdf60471a75befad421daddf40466d0e
280	1	342	\\xbd5fe366bb874ec5a4edf8354dfeb6f539a8ee40d530b093b39e35ec5c35daa142b5214d0d310dc31c0f6e29e3d8b718911fdae572a8a358c72e27846cbd4602
281	1	39	\\x4fbaffc5ee92b23f7607fe1935fdfe519f57bbb41a214c5936171eb5b8e89944f009984a649e11ac0dfbf2ee92690c9caadaf46fcc4d7b57f4d0286674d71f0e
282	1	65	\\x183486f2e9d8347bc5d82ef222027f5efdced3e23bb9da9d5c931cd86793819394fc0d2740e7cd02079439589b7400dda1d0867b630f644152e485a60ed92809
283	1	401	\\x7812ed13e61c0782a9ecfdd4e4145b2081c3478d551168f616b9cf06407ab169d14de3e45bc630912b63f3312f0c75dc3f66a2b9b6811ac97043c8f51a9f6206
284	1	372	\\x9803885dc8cbf103b2ec8aeabb33621d6ef0f960fd6e24f23fdff80e1fbf1c8113cb3478831080458fd5764d736eb544b89eac5f340d42d7491ceea4e962fc03
285	1	178	\\x3a82c3499893ff3ce72ee23132e3dbf768a9d909a83a2777bbe049c8b2c97213aa1e0062c1670398c330758fe73cd4eb4f8016eee43758e43573efb857829008
286	1	28	\\xb5e0092988cfe27be37f1dd85720f78fc191178cc2c7239b93698adbfec9a5ed92d6d8f1792041c337720e98eab339c150aac7b52ab1790685671b1596420d03
287	1	40	\\x89c6358d9b0540c02a30b0c593dfb17a63b317df0c7facf179688390cc6ea686bde2be594219ffed7bd9c5602545ec75c7e632cda9babeffa6f31bc36a1fef02
288	1	51	\\x3e239edff4ba327f5d693fd431d4f20ff1f0f122609ba9e3a01823e884d6592e5f934fdf48e50953dcde7867416de5afa8312fdba79e830b548ec5744252e90a
289	1	263	\\xf36419462fcac010c1f1fe6db9d1d2ef9fe2d7a7301812c44d820dd08d6cdfabcf8953bb5ce8ddf3b75edd5cc1b1c32c5892546381c14c2c36957cb295f04800
290	1	232	\\xa0a354b5866234d44a3970edb3960fa8646f1161d3766b2f42c8217a5a2da7f4f9ea78d482e702f55443ab33e0516673d079d9657e13e98542100056502f6708
291	1	130	\\xe326efea34e4d64970016b68bfb0cd033ebf4e6203afa75f7bb19d5b9c6c3c9311507ead45ec6bc8fbe4c92a19217759b151a692b9301adaede0517629a0e603
292	1	244	\\x257fcf321909271e95f3c065a622eb6422b702fbb40e9e2ad5bacd8c25865e1906bc6534a16350a422b4047b54d8a9fac1a371da2ab5b05f5a6c0f359492650d
293	1	208	\\x1d1dde9cd1d98c6143c434c6cb5bdd9f2a6e46d241e1451ab45fa1307f75157ac7285f00c87fbb9591091d2e50b6b9b785400afeffb664d8cc8329ce01d27b09
294	1	36	\\x44c7d24b87e7c6ec7313551251d66eedaaedaeaf287cbd7ec26c66bd2cc69f9480851785d4b19f202fced2c67a4b2cbbc36f2c19259e68f4ebfe6e38d9cf2e02
295	1	57	\\x9b5c8c5e144972b2000dcad667c38878fd17db48dedc09ed98743c7c73f9d980d22c6fa1d56ae627230d9f7a8e88a3de14c90be861cfd9b5d0633cd5f925900f
296	1	143	\\x2df8d2bf46135341024c80a447cc9f2a05691c034208555198287483e0d473cbadcec5b0a1d47e5bb1ef01b07a7a701292b656069b8c1cafacb59fa0db83e805
297	1	259	\\xac7cb1f6184643dad0ffec5e50b44ddcde1e8ba9b5bb1912a59418f74946069f9757d6b7fd9970b6170b607138858292aa2e7a9077cf22bc7b9f605ee9ad2e0f
298	1	3	\\xbfdb1fb1cbde47d139af1cc96db4fcb33b54d2a324a8f227c7f8ac2208b580a910837deb0cb20a8fc21df37607420c56e8ca33ffe0f50e6650c7c04c693a610d
299	1	246	\\xf87c8603e4f7fb84e80dded8093aaf3f037f402c44a2b331092ff23ac3dac2f2ab14300f80bbb2ebf7dc957e7aeafc2787fd24e571bd3a3ffbc47b0c2fd32307
300	1	283	\\x22bf83d2dc4618ffc22822bcf54a675c8c5d59118f5622bdc674af34940a55a4844093ea4c63102a8e32e92161d9b6d7de2d3d8bb32d0479f346ab814882ab0e
301	1	293	\\x618f2b9b1771d3a9fec8eed0f954c95fcfe0b324cb796f443132777a0eb3a41ee0bb1048e38e2118def9e4265b3500b6fcdbe0bb95244241b04b1b9a732abe0e
302	1	62	\\x52047f253793c769369613fdf1fa3ae4bb3a7dc4a94476b20535709d88127ed194e4195eb780808c6201af56f810f010c7b4f514ca4584cef70ceb754273a207
303	1	381	\\xd5f003a3af3f7860a74ed2f3c03785b0e84c02ce2cc8c801daf819b76e6ea239263b232db18fb8c9b0f5b4c47c285fdb38b9ed2c5b1dd45660d08912a5d5a701
304	1	341	\\x03cef47733048efb16def13a82452f53a569d872e6d3bcc6b988c24b26f752c20058bf643f0122cc4dc68a501082e2aa9e0585e8c40d859dac374e8b8ff5d40b
305	1	286	\\x393831f11e4f60a5da452cbcbca3c9f3bd9637ef7c3d24b86196ebc46ac3a9445bed77ae66f153e6ac5b6a9ec6c8f5f4541365f7f7f6b178ffde953e5398ff0e
306	1	392	\\xdb372919457e0e28d391cf9a59d920931a7483c85c74d1c5286b0760de1b31c7e5f03e740ad023d9ccb2f37a13679cb449b52d4893578542c26b6942a614dc0d
307	1	270	\\x45440a85ea28c47c07f8a3ed96cd7232de309a5e57533ba177fc326766c6e6f5fb8d20f44691a6f57756c37af8614d47504b60bc40970a78fd486840acbb410a
308	1	114	\\xf6af510e779dbf36d3c280315b4d9561e0ec82d0905e5c36a09e7e2d5a305c2fd25d73e7e044019d6d8cb65ee8b3a6c543db86f5f4a328006fcdacb1837c7601
309	1	370	\\xdd9c65c0475ff42509c45e30d8274dd918a82d8dd15825acfdbea3e2b9fb938334b74bc60cc4f93346f0b3861ad46bfb5c820aeeb1f913ff40064dfb96382002
310	1	336	\\x6b1b6d58296340d3745123de1562af816fadc839f44356774174b879c7c734df3aee905d5a87183c888ef83115d9fccd7a3812016915d730992bc0a96550a200
311	1	233	\\x8cce44b18e192c23401e4a6be4e0e2ec3b64f3f5abc32443ae1223f09b2e0eb1f3583e392a58cf5051be43e5f15980922a3cd96c6501e82972b0a4de1dbb9a00
312	1	177	\\x50f12fc5837e8f3e84f3bb71226c8d5a0505f1fe314c35b247f70a3c81df30fcdb320522c3898a47aab2f7ee633930b2ecffec71534046b77b2d73a6b40e7508
313	1	165	\\x5a683392a2545b950c0ec7b11744969aed3c6f96200e39371fd648c2bd1b24a0e7419d610baf02b1a11f8f851c8541c9fa4094df9dc8867186872ab71548120e
314	1	50	\\xa706fcdb0fc4beb27e2df843066a035beaf792bb1000276ef3ff0d1b6ffb3364f882cd500eee8bf7315f9c2cc7de66781c5eb5c00b5c0df62ef5be311c34ad0a
315	1	424	\\x0b0597b4c65cbf74776a10d061e18940bca8cd1a24136295a2c7da0c5e33b53114022aa9a421121dc7eacc026f9aa8760fca177d4ca387a3babd2135af544309
316	1	63	\\xbe17453c36e93129e4df282e53e0803f989122cffdc55f4b1bc3d1404cd127f06cad7b98cce1821875b095fd5407b19ccae68789d00562988ce990ca72254107
317	1	225	\\x3599e3558beb34ab7296c15f6e1a66a1e118a5384d6b61ccc1f98f1f0da3e2149a158c49318ad5076b85c0b9cd18fe9ceaad489a99d577ad1af814345c8c1705
318	1	97	\\x55d51cbb4c1f1bd58c577f76fcc7187e266bd68330d34e1edf648e5b18ef8e5856ab26b774c6677159442d18ced77f3749e1ea8ee19f7cd78f560a586020bf07
319	1	239	\\xe5f1986571f367e752a36531f95c3fc0caa2235ef3fbf7a80199d4693ee71891f1a7599217e492ca0c638d65cacadff1c71379e43f49a33d9c93243f78207405
320	1	102	\\xacc44676d28510210443595a60fd794848b88af3c65cb9b83bdbb3261feb5437f735fe23061257be10772d7327b729b3ec08c3c1fea02bebf8158ad17d65100f
321	1	358	\\xb6d19423169d411fa859eb71a5510159784ad4abe1f73940b94ce10784b63b260d9c1538448242aa5e501cf4114d91556a36313b3815b469638facf1f5b9a90d
322	1	12	\\x48a4bad6e2673a8830fdef5febef240a49d118841fe78c2675a48ad503295310bf6bb96198115c157706582523a829c790d05a173424bd11503762ac05065d04
323	1	267	\\x6dae4e7cec4d992e4a3bb4b2bbd1aed254c81f25eb3ae49baa11c12954ad6fe4a6b5496e42a535357f483dfb499c4904dc91fa553e641de89281e68a6a97720f
324	1	29	\\xbc8419e321611833bd42aeebb66d0addd58c58abf770ba8250e4701521bf9fcf7bc9c7aa763a9aeff0a08edb1b256d1e52845440157f02e3f6b11772dcff8900
325	1	258	\\xf80222cde164b5d1040ee6296ff254d80bbc064faa1430c45dc6146949ba9b7cbf6b5b325d1891b9375616f30964bd3a2e14e4434cef08b6731023b3f6f5500f
326	1	306	\\x618e929339e74ec1148c5c037bc58ae9db5ecb393710dd3832c13369e1ba823ee408fddb7576d1e521add1235b3564b4eeb38e8db13dcc8613776222480efb0c
327	1	271	\\xfce649a10df7ca0b11fbce88059c2d543cf457e780a0a47a5bc828602b1f6cc218fa7de990b27d02177de5932dc17fb214d8654b0af99ba97fdcfd554e6c3f0c
328	1	75	\\xbdfc0eb54ca5ed4d3c5833d19d57b6ec10c563ab88240625912ba2b6d36953c1a3db10da6d43fea8784fd7edd1e3459251eeb5a02e7d62dbf2c71a66c03d570b
329	1	405	\\xf4e4433accbc654bce777361ac2119490ee596f9219c251e9cb97c82d443ac6f649a08172e372090ae5ca853a61cbb30531095c305b32a7d72da31752750c605
330	1	135	\\xccb67d878cb26173ea18d8d2833440ed8e39c7278ff725359f4d89950105e75eb33e2c8400ed46d2d0c5e9ec0d07658a26e5449da6ea305105119d2680edce0d
331	1	359	\\x11ee24cb4ed5bd689d2de9cb7a9b3910161ca481053d9ca49d2f55650c64b9ecfaf91cdfe391838ae4664cbcc355945725370d85de65ab1f067907d16dedb500
332	1	416	\\x22a6b814241016c651570bbd3a74f753493f30198091bb6fde8ed303e3520f082c756c76a6a29a57220328e2b183160209a43cc5bec7b83b747fd1be68a1d009
333	1	311	\\xd5f4a542a017c58ce8ed73b4c46b1a05d8fa9ef212c79457366862f948c5602304543f68becd14c64d68c36195a04a85fb27a3bfa500806aff4cd55d371f320c
334	1	41	\\xd1ec187728531fee7913b1d2693e79ddf3d6054ed801194a1a272d631cd15f093ad3f06434339209912c2bc730634034ab53e22ac32275ead1a1f5959f399b0e
335	1	138	\\xef19fd0a16db7a7df25926194d913cd3696d35cdad3531e5b55e379f10c762a01971f05ee2dfa17fe2efe9e955ab3d8fdf2ccc53888b9aa95606a6d7d84d7a05
336	1	145	\\x5c1c25f71bebff3bc0ef651f398e7e733f62d7e8be4b8bc2e5bdb71d5857de367ca5c6d4fd8cdb3ca9e6fc62515ce9524fc2e19e3dfbfe3caa2c495d184cb40b
337	1	163	\\x16bedb5bc27b004b4ad27cbb0d1996b099d4761819e3c4f3b26169d83ca3a2e795e90571262a58ed8d6fc7fbdf6bb5bc3e9f203b781bd0d2651693bc25907208
338	1	414	\\xe609a4db528611d7ff328ba85a723ef5565daf2028e1014482e098e39c26db0d0b4cc146931002e5badf4c233acd25fe46425b623d0dc9a689e0b4af5497ea0e
339	1	170	\\x5a925d50d2389f430adb6039352fe7e7e0040db323f3dcac1d6c0d68c7857fe18df3facf3d69c8d649490e1d4541f036bb3bff89c3cf29594021f8fbdfd13f05
340	1	250	\\x8d122898f58f74aedebcaefbed7b2009bd5faca29da81059fe3af99c5c00e74026e0966dd0058e5091fadd0bbab89c47c540e12e43a355f4f15025de2e6b0107
341	1	171	\\x4f18ed980ba03fa05df6c782019151659127ae1b9ef4da7594a9e6beb57f6c4f6d92adb2b418f79f39b9cb4a73b3f61892aff56d6a4f6065c5b67487bc7f240c
342	1	155	\\x8ebd51fd3572d10c06c165e0284085ee6bb93041ebf02e18d5aef5b5c467658e92392e56d43aa189ec6c9cbc37c65f059d136d39c94a22a76d3749cb1bf21c05
343	1	329	\\xdf27dd677efaf63f795456d6115885bc7c26989ab905b3921c436c531d1520d2f86d7fbd0270889e34b65b5b4131070f5d9cd326341981cb57db7c71891c360a
344	1	238	\\x9828a24f3185439ea747b3ee1ca84e54e691b16b0c868e3c21e3f9d363d68b01537e7b670d7461790e8b47f0bf665460467b10f790de0a07c879a403b3a4820d
345	1	216	\\xcaa095047b7681cd8b6a7f4ffb33ca6373cdb5ddeab8f7812fce74b34977d1847f66412ab026272b1053084511cf199a933073bfd2b96fca0a33a862226c6306
346	1	395	\\x64ae1de98b7f9e2bd96cf436a51b1835f53d773f7b724627bf79668637bad5c33638c414aff7b26e177daf544e34751694b54b25c10f4cc967707948dc9cc60c
347	1	413	\\x9465ff01854dfd4ef9d51d20e02ff8381dd68db76c69b8654cd831766374524a3f85c600d9591ccbe22536089038758802081245d9d04175e10381b48e924b0f
348	1	224	\\xb5bfea4c3ce76b95993c946b869035ffacbb861fd5fae9bd2f83c4a4045ba05166858fb3a4ebed4e69b784d3477bf2ff5ef97d18782b316ccb15141b26bd450e
349	1	144	\\x9c2e13bcbe8c7cb577b6dbb57b82932016dc60f6f3f967bc82d4860fa5abb946bc4d8229faa818367c3e044e9d7876960d5530d777da9d63887304e760887206
350	1	409	\\x4bef2274bd3487124f22482e7c60fbd59db5df1aa7cead1a904322f85cddf4a3e9e88abfc74d591a99a88adcf5b9eff7f04c98fa5eb5ef2440fd0e4ca21abd0b
351	1	98	\\xf52a9a901e3fa7f0f2065b9f26cd3404fb1851ad306c0ac478057cb2db44dae79da9627b7c9b941ed99af04b61b5d2dbeb29f17f8469d9a23a7691d1efb46202
352	1	374	\\x5307f8509c88744bc041df636bdcc835c69c2caa41da7e753018fd8d0f212e00cf09850bb64dea0a49bbf06ccc67d1706dae4f9f8e777cdcee0b0dcbe6792b04
353	1	255	\\x3fbf86bf2bf063c31334673b9b755fbea9297b5394eb1feb4c0c50c08b90d74cbbadc2425361c6dd0f65b98996d5727fbebd33ffd56f4fbec948c83e5a653704
354	1	35	\\x776dd4ced3c22457a3ad9e26b6bdcbb004da05407541b4dff304ef2a9b1c710466f4118a4824beeabf7eca01352f137ea8b5a88d0372f6cc9515632a092c1d05
355	1	251	\\xbf5651dda418459d225f523d5391cce41a17c8b244be996a87786624b9bcbc6dcb64e24d3583e6b1b71e0a6f508dd92e046d91bedc3d47b0af860bbaaadfae00
356	1	188	\\x2894218ba949cd0c71313e61c9d453a80911e266b2465715b4f8f6ab9212e944faa834f9a6a2aa89ee95a31ab65d2ac8e610d7c6e34e51913c46c59af1f8a804
357	1	338	\\xdc15d8d18dcb815839fc4caaceba3b775acfe6e25156d9f1d1e4bbce227d67f1bdcc77460007938cd77c0c6bbe18aa173ba0dee8dc79f9ba2926d6d90ae16900
358	1	423	\\x2092c1793c8db7c504a7c2495f82de22510864e99a2e0d453b1058522e380256ca6b5f2e427036554ec5d3d74df83be1d31c422e8a1c1615c5d0d2f4ad9ac800
359	1	53	\\xf3c989e0e85b847599a2ea68b281c0818a98eedaf9aa343244f1ac7217dab530ba0e36e1d742979f2120bce8df4e3b5b6fa13d058b50b4cffe73969aacf2ef0a
360	1	34	\\xc9787781e61e19ec6d4c0b1109e37c7bbe991909b233e3fd08ae763afed679855e07628a3eb0a898975f625153b9738904aa1971eefd4aa76fd161354799e402
361	1	26	\\x50e05ecfb196462e34302eb4efe2786aa4c16ab8cf5c608ffab29ce499506edcbd678214e7993bd1624c32b04cc11c4a062437909bd545362cf9f7124bf6230a
362	1	407	\\x3731bbf992111fe4512f7ad7509132b0442c998632c97f0289babd59b7f48c57a50c0a096eb8b12ea8be09fdb66e7d44aba14c87c3b6e23ea12ab05f3779ec03
363	1	347	\\xf42c7ab702fdb2d3a86f22be738e828b69e864e8e740e86387586ff5dda531552c71bd360f669a54c0269a1242cd8b4218eec5cd29769f82665e38b4b5438805
364	1	11	\\x5d8c25cb2a7155b991c5531871babd18f310e80899a994a6cff6aaab23b3215e6c30a77c42dd947dc4417060115c30306412cc0e4c40c1382cf8a88423f35b0f
365	1	168	\\x3190e0da7bfa34eb5fe44cfdd97fd2669dc29b34403851b69e7c0aa8bcef660232d97666e8d77369f5658e78461d464d2026a7a9c54df4c4b079fb579688e90e
366	1	291	\\x0d9cfcd93a6d28e8c3bf27c01b1870316f6f480dab21d1055d98c6b7284a515f9f5ccf1d80126370c156fd5f552b6e27a4490b67bbc9a678628378b16889030a
367	1	419	\\xd5d6ed6266a50456fbabf38d59d5c89e71ee355dbeba2a811bd594defc64a3b0e75b3dbdef842be65e789a0a5be80cc635d9d43658d487f304b8b39a6d244109
368	1	139	\\xe2e7aeb14613bbbdc75c483145ec76ec07b05f56e61189fb14bac2bef9014a235cc7dca3f56c2ab4b34081a27cd31336e90ecb06c77d037d185573a5a762cd0b
369	1	83	\\x0c78d48eb5e6ccf173043256b1fc0f0a4ffb04d155a47d3ac096aa800606b66479df27e4981cbb6f043b6aa6cdf66190a1ebfd9fa195dbc6ba9b5632e164d304
370	1	323	\\xb20158e466c8d8c33d6397d1f0b5e2e1c6492144bcecba7a3bc0f3710594789632fddd2e218f6dfb406bb40608426c2c6d7b70687770876441fea2747b349606
371	1	96	\\xa5b73793f124f3278ea81951c1a7ef25b1dc34b974b57a069b6f6794a3faaf14d2f7e7e76b7fbec2f8cc37d8a4d99ba92bb7c785ca249dc0799137675137dd01
372	1	279	\\x1757ff9c3c31c9f36c6bfa8ccc21f16bec00290c9456f4e618d422a2f1b20a2990c760125d125b1cbcaf3369864e3b5fb48841a76c4e95f20b99115a1f2ff10d
373	1	87	\\x59a993a7fecdea4632bad0b5fbbddb4cb1606b152af1712e84814be94fcd7b1d621dcc9654410a1ba914bdb218f5fbcb9d7ed9557ae9f36480cf1fdf139e2b03
374	1	86	\\xfb4c07689753210b4aae0cb5b180b83e300d47a1af7da18ca22f3b9aa3d673a848ab1e71758a9401770904fc5509dcf4c12de14b46c350510fc2779d008d1106
375	1	390	\\x6f4b2a5a71685f7c105089b4cabef7f417ace357f4bb67f9cdee7a79f8bda02d48123e22ce6dc5e6073d2622df04fa31abda5b6c815ce216d4a6d60bd648e402
376	1	325	\\x79a5c9466bb7c1e39e57f3a57c3d43a351be734e160c4b3cec42d69e1fd1124a55416af13045e0524cbf20b1522642073239a9cfb97e39fa66752fa7c920f70e
377	1	348	\\x26cd72397c3c48ab1c66e977e5a8b96c7a81f3ade27ef67b6ba3981034c9d2c7189f8cc66a0d7acc17463dea057561b6354bcb9739b53dbfbd804b5f8df8f10d
378	1	85	\\xf82d824c0de788b59a0ff8b9f2f48c439cc9921a545f1e689be63253cf14c6afd696f8b860b6f863d0caced0ab8b336ff50df74f4e0a10ccd33851e800d69009
379	1	289	\\xd75a9a5ef40c84f66e6c3f52d2da0c65b9474541dd28851deaaf7d75cb4eb9e1db7ed67f4638e4ca3c79100f8683aa10d5d13b40a8908ab7e7dde57d9d491905
380	1	352	\\x3735632bf836cb2a462ab5bd78323930a8f1034ba1077e7ab47be15d7c6e4f4655ac84fa361b239ea50ec4479b086d9ea82c05ca4be952324c44e2f4844eac0b
381	1	189	\\x39aa9f32b44c0fec6c32a55c2845e7ebba3028bb8c42da3f74d15253c3f3b0234218e5ec57d7a1ba17e7c4c7ef4bcc22ab3129599d0c28d88d8930c2fffcf60f
382	1	403	\\x893899161c2ad0c29d5c299bf3805380763654a9ac8e091a7089f8d56b3c1fd98ebc5465feafc234f2179ded7311ce4dd581957988c86b893e6a53151b8d6a04
383	1	415	\\xe756305e7ae37def3c626e56f2410a78e090fc416944b4aa06a0cb833796600928aa2c04ba5d9d8f7e9ea8f018f1e211119112f4ce46a8bee67187401a003b0c
384	1	252	\\x637441452990bc35809958ca5f1c27d3c008783b67c8f60f7a56a889709187b29787e92e9c55e1858746717cd37ab88c1ca611713a2d0e1593d011b974b5ba01
385	1	82	\\xcd0ec73a8d50a1de18dae00bdf88d50e04290d59f186197c797025804e36e40bf1446f5332d9abf3cd33ff04767743cadb40970f6cb68274070df9c630f7890e
386	1	162	\\x3ff2a243891500b1101917baa8e80cac900ec1e901a1feee6172a6ff05e7f308e81070825c78029c37908f54255181a3de246942054ab6ee758e7a9dc18a000d
387	1	45	\\xae6ceb480a06b666d20b4da4d82ec2a30a3383658fa351097b5bc071d1829170967a98582ca1ea066524ee6f3fbdf24a05d6794fd2e87aca5bea94c50be77a01
388	1	202	\\x6061d2d18903695ce3daac96670f3ce7f0b2566a46dccd3e96da0c84cabcd45f188eb6a11048edb02b0a854e16f82bd2405e3c1344bc0a30e3bb63e708683a03
389	1	156	\\x66a18c78fe427a5f89b0b1a54918685b7a082f4a8ac3bf16873379b1372d26335969d15ccaad9b9bdb643903ebb5ac2843243b7a80129b11a79a1b17af16640a
390	1	304	\\x17d9020933750dcc9802c0f6b1443cc805fa75008b2298a8efcd60f9f865a6ef589608636e8dceb320fa28e172c4e68a609ded306f5317e1a04e0ef3721c3406
391	1	207	\\x47d977ce59add4ca197e0d940f60f17b4273d43c16cfeb7e046cefcda271255c5bd15dac071724787c6592f58f07106c1bf8a53d3728eaffad71373a4b669205
392	1	337	\\x160d57469e007073a7ca9928ae735bf6a8c34da05caf58e04b4f1e07d1c334e66e20afa6ca66ce1484c1ba73025c48900701c0abe4010f29463ec51afa6c480c
393	1	377	\\xdbe6071f8c136967eda8aaca60baf840495086959fcafe66e3a606665cc5dc4139b4e9bdae8aa6098b2405036524e2004eb493bf89e0a2df814dd5e77f8ac704
394	1	49	\\x16feb3d0e90e8c735674b168293332c30aa9a9856acecb5860c726ed41c981a24c25fab01a99c68ccd371a97b570c0c6ce4f0dd8417e3290486ded209f334f07
395	1	164	\\x0276488478460ab5a6a039ba9989507aae2c870060cdb85208b3b427540d3f80261e3cc48f74ab6fc034aa6671ce4efd746ba9766c3857dca6d0c09d58846e00
396	1	99	\\x197bd2634a580499e67c413bdc394e9a004376e13167f06b37a34d192cfd508e2378162de3d97b0fd6d18bb74f01511ca61659d0c060042762ffa9642a970108
397	1	364	\\x147cced3c53d95292f4561e3405616e910a6fdb2207d32e30fc21b1411e489b57f281563c4b7b8bbae7f0496d815f661ba200f745881de28fb9b80a3f0211e09
398	1	152	\\xae63f1f7923d2c0613717b6999255041a8dceb7a7c5515e0c84cbc18a456973905853ca342e8ec94e5e8eac93517bf2e43d4343015c820ae63191fabb381fe05
399	1	333	\\x7e5c9fe9849650e8dbded6c778aa79a2e2046007c2cc51f8fbea3b6a0334d95bf2d7aebc6f5028e9d5d3ca3843f82db5a46d2e95fd3656e1cb49910ac4801f0f
400	1	417	\\x2ffe6305343f1abac4fa361be8a0ff9644dd6c80ab389e38132950069496eb37d1a1d1640a6c16f45c1ef467eab386e83615fa91acc936cc4356e882142b2b0a
401	1	218	\\x6a722d6226648d6c08e21d723d1da2bf9c0fbd63ad420c4b67686d26c4fdaf31c85b9b9f440214f88899e1eddb1bab3f1ede6e48aa90e5ecb32750c23bf34405
402	1	69	\\x86124bd4e416fc7d611956cb9b43699b54642c612c9ca208af0a6c0c80cc621f7f1bf436aacf04c46d70f7ca78a8a99276bd84d824ffed25f5856ca74323b701
403	1	240	\\x6a614e8f5e4cc101c23ad9ea9831c0f5c8d87e2d897f91eb26c358915f4dba5fb74062d2d2af3c00c11747f70157c35d9ea96149fce7d4b3da7ba6f750fd4e09
404	1	185	\\x6d34724ad9f562a2541635877c0e0d561539e5911da799906e798af1385cf33a14633543cce6927eb2a7b5d1fc544e0355e6a9442b1e45d88f2851893a64d602
405	1	78	\\x0bc2a462a43543a4b4d2d0698998cd233ce1f7982c5ab64440b407225cc87a4f122d2426f61719299da81c178baeae9594f486e0a34ea754969bbb62c872e20a
406	1	299	\\x7b9ed71888ee53c0442043206ad0c77b6e4df5c4eea39c2267d0acd85f177a688efdc9f07ee448ec492a6a67236c90ea95e86392f50a1b08d35750d9ec1a9403
407	1	115	\\x2fb2ec121aa79839300d7b9ab088514acfac38a7e012cb5a3f76d35ac105a03e284b14b733a15ef7bc64e4cbef096b2a6ab00818bcdf6f46a82e1cd50ee34305
408	1	123	\\x72af8484fb4b25a3c43a27f2c80c16c0c75730934dec815af1c356ce38a9d321858134cc299a3d676062ebbad698834273a627644468e4220f06b101992f5e0d
409	1	2	\\x13b649319268dba165bc635ae6ce348b29932b8842fddb147db70301fc6c212194b0dd4162fcd48c6f2ca1ab5cb0466e4957840982f6d37a6aa8159e9d3e1202
410	1	248	\\x323d341964550c31afc8223b3dfe8f792f27768d3f70a38be99b7df634af85c4b4277fa340967f29c2bcaa3656f19086cd8af7db1c33174b352bbfdc03344b03
411	1	203	\\xcb3ae936250d34ded3015d478500d0e5ead0595f8be5cd718493a4d921217359a0161179d8509f6b18bfcb492c0a1e4ecb80c21f80b2f88d473e574decbf8002
412	1	386	\\xf99015a183153cd7d5d2b9493bf20cc86f26f6c2929b1ebd74c190125352bb142f67a270cf1b3a24a7dc6f1eb4e7d93c5db927e6e8695a33cb36a09e0c945009
413	1	353	\\x27fe807e6cb7c94862e533809488404930848fe9e13bcd42277ee177a1b120eac995ef2e210744b9338f094679ca14756d85f343f946069b0ecbe4ae77076e0f
414	1	142	\\xa7d7c29f68b5e9de32f11b345d21eb3bb4c0b4a72b33a99b0adb4d22ade229da2b9f8aab7cd24f5e49c0a3c5e287efb61d41488d4f6a02dad1609ccade272b09
415	1	360	\\xd274d6532a465ac0d0071eaa88c520d6d2b1e7e4a86db355cb8e553b412ba8932b7510e77952b6fd5e1e7a8aa941b404728fa20e30257c0478bd2214b2ed5403
416	1	262	\\xf0f80c6bf475a4d317c9b9211e2ba08a5bacaec5d8f9d3ef18186cd1ed532a399f032618c2e5df890dadfd5bcd8ad64ed8585e51b84e2b87c12242cea2f40609
417	1	132	\\x66ef5454384362e3638232b1164bcb02ab42c5a422477bd491450e9fe217bc179ae7e2a6b3ab1e1eba9f95b8fbca4b1d0fd253cd34d466085d1c7220b1f31f0f
418	1	298	\\xebdf36b194aa3ac07402555d9de3389b3440a1dc6055aa178d21e8e63928283a79a30ee7713adbdbda758c9e8d4b0cbbf995e2d1aae5ae49bd0bfdf0ec4ed103
419	1	354	\\xc27d71e638a859136f17f04d40541a910f30d65ab5327afe2b1be619e460416a4448a01c80881093078bfd3baf679cefb8ad0e0a6225cbe7caf7ff69ab337701
420	1	44	\\x92e4416d3abcb450cba1e64dd8337e86bcd69cab8854d410c114c56749a6b11cc5808c8aeaeb9359ac9fa5e95b945e1cdbbb1e0abde890f3e7ea630309dc5706
421	1	131	\\x554e27d418d703a5694d0f01ffa2a9b5628790d64c1a91b0a53c43cc5e06e9e0582a1ed909fb86f68e61cd2d4e2a64dd320ea57e5703add1c7f401f18388de05
422	1	373	\\x26a4f3e3397d2aaf5f7db7a6e566514cbaed3cafd33e3ee7ddc7b874ef7e8230f7285a0156bc14e72e0744d0f83168bdcff18af7c2b27d376d0fbb444cfe0a03
423	1	46	\\x3d7f0fd5083bc11548dafda76abf5f6237470cc43935fd738fb1c9fa13ebee372e968f82d6c0ec87535343b2392e4aa6f5ae46c37e22db38cd602bbd9db3b604
424	1	153	\\x6c1def86738fa6cd52b7b69e8632939f147cb7b0b1f136e2583608018306e5dc249f65e1f1b84d77def77d23fa9555fa6bfc66c92398267d1df96d3d2ed6780a
\.


--
-- Data for Name: auditors; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.auditors (auditor_uuid, auditor_pub, auditor_name, auditor_url, is_active, last_change) FROM stdin;
1	\\x2072e35d5d2a07cec52b69cfea7644335bfc4c9f1bd4288bc56451d68a2521d5	TESTKUDOS Auditor	http://localhost:8083/	t	1660496833000000
\.


--
-- Data for Name: close_requests_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.close_requests_default (close_request_serial_id, reserve_pub, close_timestamp, reserve_sig, close_val, close_frac) FROM stdin;
\.


--
-- Data for Name: contracts_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.contracts_default (contract_serial_id, purse_pub, pub_ckey, contract_sig, e_contract, purse_expiration) FROM stdin;
\.


--
-- Data for Name: cs_nonce_locks_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.cs_nonce_locks_default (cs_nonce_lock_serial_id, nonce, op_hash, max_denomination_serial) FROM stdin;
\.


--
-- Data for Name: denomination_revocations; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.denomination_revocations (denom_revocations_serial_id, denominations_serial, master_sig) FROM stdin;
\.


--
-- Data for Name: denominations; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.denominations (denominations_serial, denom_pub_hash, denom_type, age_mask, denom_pub, master_sig, valid_from, expire_withdraw, expire_deposit, expire_legal, coin_val, coin_frac, fee_withdraw_val, fee_withdraw_frac, fee_deposit_val, fee_deposit_frac, fee_refresh_val, fee_refresh_frac, fee_refund_val, fee_refund_frac) FROM stdin;
1	\\x04f465998a5241bcccd9eb84b6d5331c6742238a7d1b0e7c68a3a9eeb2d2b9ce2627110e0946c212e1b7db67dfb9afd2bde272fe45bee664e44a163ce20b6215	1	0	\\x000000010000000000800003bde067e55fec04c98c68ea99ad5fcbe41b9763a16696044936d15a33970ee13acf7f8b1e9f4308bb47c162d9b0fb811ec122773891ccd5508ae7dd17b042fc57d2e761cc7a05ac1281c82a92cebccadd3488a04e01a077e621f35ed1b02da12157811868a25ec51684f3b11e5a9d49176bed0933ceffd2307725a5421380e419010001	\\x6b7db8e3c82f6f353711d854ca1858fe85cbcec7f6c4f13c4e121f6ad642603a7612fb8d93e61d36457ed7e26e5988d8253c0ca5ca13bd1a2e94488e68421000	1673795827000000	1674400627000000	1737472627000000	1832080627000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
2	\\x07946b96e78bf3854107713bd280ce5b987b3a7fcf28764f014d42373ecaec5a5983469052332a5f1be6733c9a0ea8a24d6367211a453d011d20489307b8aac7	1	0	\\x000000010000000000800003e515bf8c5343cf920dbae39eb2cc4f186f1fadf4148b362b25a622722b16fdfcba95e051a94cb653e90bd8666c0588f70d919bac636371d0b5bae1e1fabd76adb11e23e8ecad19560aec34d72d0f11a37df6916741d4062c678936aa99bd7f4cb8ee1365dc97343b4865eeb37949c4570e815a1ea2791e53e502321cb60526e5010001	\\x551cb6896b3215342af235b26e3b34d062e0d4de84eabc1be4e62a001de80b7593c6c991f0ecb9fce2bc21085600bc7dfe92a23badee2e55d639ff8ebd8aeb03	1661101327000000	1661706127000000	1724778127000000	1819386127000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
3	\\x07c880b2d2602a05fcbe01a23e2a6147b5173f7229c6b67ede98273978b40724cc5af8a8e43bc45144821ca63e072b56fb254f3b9d5f159c7e78ae8422377d86	1	0	\\x000000010000000000800003cf4cb3f56b13f1486a84e5f4d6fbb70cc35f243eaa062cc0293427b145f7c3d71edc7d8c95335a894e0076cc8577b34ae6786a059caf4c6e55894e753d834e84df585146b5a70d9b6c73e10d2c5f1b7b6b9d7b89ff1b65503161f778a7072f8ce2580b387e56bc131c17131d45aae41b00e44261d5cd1a223c71056aa5725ea5010001	\\x92f962e4b05f39946b2322fa06a9cc74a989787c849824a5361b548b73f4428598ab02ddf1b3977bae31ef8ced5d6d296b7f954c9a2e5e29679ec6160f71a205	1669564327000000	1670169127000000	1733241127000000	1827849127000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
4	\\x0a0cb0d04ad76395577b9208b5adc967249b46af57ed96b06cc0c37fad944373ada55d60f64a76fb7824ddd1fd17cea49df288aad2b6f6644532551726221581	1	0	\\x000000010000000000800003d8f005c52fa72ee4ac33a027e273c9ea990e280ab454aadbc4373259eea7bcf82ec2f4f78ea839af54b5102167e08ffa367697d79694f4c9a9bc087a77baff6bf47cbce43cddc3832eab19ec355e521abad1bc90f981d2f11ea6f212dfde566849990dbf8218d6ea7db89ef19bef350455146823bbc3af04fda0c8c3aaf888fd010001	\\x87999c4cb38a5b38774a84d8f2be4f9f6cd838beae30cc950ffa474d55449b784db68097f96fe3e1272d07d5466836a3f738ddb624700dfe806edd19bb32fd05	1687699327000000	1688304127000000	1751376127000000	1845984127000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
5	\\x0b48d55a9e6b5056f60e280866da09aab385228ff68b9777fd92678beaf4262e2bc96d34650eca50e7ce349bc958b3d9424eeca476b62065889bf6a743e8db39	1	0	\\x000000010000000000800003c3755c246f66c7553ac8b3548d4e7d92da6b498bd4ef0a11007e0d3f5e4f5463e5459b3b688e90e771bfa55011de3eaff8ca1174aca226afa3899dae8fcc1a048c64cdd80311deef2eaa9aa8e5423fa8fe7a7a9e231a238d2c14fa0bc69212bdbf67e7002b053a8dae03d7ee108d10d1ec5aca40cb8d53f25faf4cf5e1d150ef010001	\\x94b2bbc10f80946de41b695396b335be2a5feed14ab2e9ce706bed91de40aaef93247e988e44e29cb5f43cd9e991c978663dda32a3ac51c74fb99db742a0c402	1691930827000000	1692535627000000	1755607627000000	1850215627000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
6	\\x0b10b751744d3b6ac27a18d8052b11459c4b6a1c71c9bac7c1c4dff9763e7263a6df4d7fc77f3c9046b0bdaa38c0d673ed3f049632aff2583925d0703492789c	1	0	\\x000000010000000000800003a7717e24e5a2739758fa6b935ac2ca75c5bf5613f8d2c4e3bd9056b21c7a0e53ccb88a2548bee11a34bd94851f428879ff0cdf9b82afa4f82a4f60478e79d20884f7e054611df3c6fbf5d4c1c5ca8d2db2fcb882b505592784ab716b40186b74ea19beacfb6f546643c8574a02542244a5e71b0f3a9a0c7d63599f4fc378fb79010001	\\x90b502580c1e79963358d268e824858bd843212c75d1262cc1aaf9146e062221ec69f886c908390b62c46f94555a489930b15296874d12cecfa4c26225808e0e	1682258827000000	1682863627000000	1745935627000000	1840543627000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
7	\\x10289a9e94cd4e3b058eaa4315bc340673cac073a1a3515515ece5338828a3d1b896bc6d38c787b38a52477d0331ef8afaf05596c288f2038bc35d0d399e0973	1	0	\\x000000010000000000800003bca67e0eaa1e269056e1670e7b329a47cdc19338fe60f744bf82c9aa00c655260e4097ad0bdca63cb772317b62bb16b42984dd4262b81812f392cda64e6c02a8d77c29792a481e9ae4ba3c5deb3b22aefc5482c01da404bce8309d55bc29003f3bc7094f67f133d97e66dc2479e4052d44d01d4493f2a30932f537268dea33e7010001	\\x130983a29632df2214c7d47db7b235e9abd77a7594ed69f51a154efe019a275b253b7858e43a7eed7318e838c6e2ef55d7efe88d6bae89c1c49c30663ddcb205	1685885827000000	1686490627000000	1749562627000000	1844170627000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
8	\\x10bc63a87e46ccc1b2d69bb42882f78d5062288eefb1afa3eb5ffb6ee34ffd9aeef6b092bbff2d3a1f6cd5b5361dad716ccaac345e38f4ffd8d9024c79437795	1	0	\\x000000010000000000800003c3912c4333ab4a053d613cc3cb19c83a0188ca0a994b9dbc5373d4aae4ba01a1d6dcf4afda5713f2487066eec4d6b01988b7c4fbc990fe2bc0d44332826dc9ef90cbba7b8916e48a2d69fcff6272b62b33208c99b279ef4e3ac17ca1f8658638c5bc930b0f23271485bbd98dcd169ada95f844718c1306c9df708cef4684df85010001	\\xc30f3bc6146bcc52b1eb959151a063cbb5ed0ce56d83fadf518026af61bbe464de0cffe76823c2f6fd6443b27422f2700dc44ce7aa1cd750bea945491772a40b	1678631827000000	1679236627000000	1742308627000000	1836916627000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
9	\\x11ecd9a0f31f74c5b81a3c2664349815fbac7cb090a1c1f9b589804cd3914539b5fa676f1930efb6735087a8c922184f2d4dadc8b5e8cdccf49a0d79f1ad4bb7	1	0	\\x000000010000000000800003c06de9ee3a2058053c9f51eb6ceb0fbfe16c5ecb909af31fc9b1d3ff72d9cd93fe2f4fa6b4a6d062403e4f7ca4837191360a8526d9050d0b927e2aa35966a13d26381f34a1532e3c64063be4d4d4a987fefa26f8540288e72fbffc2608117ffa423572c6a25856d9db8d69d409479c45d92ec07c2c5a41d5dacb99542e6f4d69010001	\\xae9bee16ca65f62cd21ba95200f9108cc3ec3992c27bbb99a02173e079a1a47ec0c0f4b31fd4c0d1e8c14dff6422bf0936e07d8d6717f1a0d07bf27c5145e908	1679236327000000	1679841127000000	1742913127000000	1837521127000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
10	\\x111c0dbb923c24e24c70be28d651e76a3971918779c468ac840a7968ce39af4c355798300921505ab9623545e7abec93691ea6eaff29dc26257076354f220b51	1	0	\\x000000010000000000800003bc2140e5b34883ced4e6bcce42680d3411433488a2c7e722003d2c30fb851a4dbbebe262a806f8b5f2c8575686bbc2673830a282f54f85c65e997dcf1d1479bcc625a348b5ed92ef12801afd91151b7cf24f2eb1891b968272b810bbb6b7a70036e18974b59f4857783491a00b4155cd40c6a5483abecd167d18556d3d80a8e7010001	\\xc25255eb130d79d0462f1c9ef07f56c901a409c9fb754e073cd1ca2f7b36fa6394c5a0c5d43dcf6ce614bb25296bc253b5e701b7e61c7c77282e9b1c4605e30e	1690721827000000	1691326627000000	1754398627000000	1849006627000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
11	\\x140859d688c58c5eca0a92f20b645a26280e00c8e7d0e1363c03f5cc714681bfbaf1b5026df8a08c9da52c613d4ccbd5b07e3f4d0052c9cf02d64c82fee3c03d	1	0	\\x000000010000000000800003aabb7497fa91b302ea4093bce0dae5e855bb529f0785b6ded690675ed5ad6a1fececbe322a3725985ac878fc20b15f841d858933fb0ab66ca5d4d3017b69b00a080e95f9dbb32b80b8b44f516fca9c9c4246a7d45ef5689f21f190a40932abb98b3f877ba16b5e36b8a62ccb29e170910503d7b4827840277bc8bb6b158ec01b010001	\\x94ce496e323896d7da92de9d6fc2078df0f2ebc66c9d095a5ce5b5c9fa22b1b7aeab5001e2105faa465707411f278035985ca60511ee5b3b2271cb1f18e76f08	1664728327000000	1665333127000000	1728405127000000	1823013127000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
12	\\x18f4dec9782f18dfff7ae0a53d1ec15cdd8db96413f35a75f06c85e58d08101c66ba315120531372b8db7de3ad153828b4be6aa6494afc3621d0ead33e8b62b5	1	0	\\x000000010000000000800003db1499e7a226fd6b3d223130903776a77ff987f8c394a26c1283f02c8da9d0c947a989c7c8ec2b1a7332162cf1546475620527e1753e2417cc4e7ca2174a64ed82f1fd2b9f6409ce8f284857a31c4a6405cd539795a39d5e7d661b842dcf7024690b74b61ed2056cbea3abf6645c76906a9a02c2f00fe904c7304ec2322b653b010001	\\x380e6c7c2570e7b96d2ba6c0d118787584f580bbf2e797bcb9d7fadad731463d471c862e820b063f9c271f7174e46cb6b97317368fbd74eb80fcb21421cc3902	1667750827000000	1668355627000000	1731427627000000	1826035627000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
13	\\x1b08a484f10d48451561f76894b554f34b8347436070369df68c7a2b95c04b0a9896fb39ef3097ce2e12b71ec88737dd0d968ce7863eb63e856a91283db5e01f	1	0	\\x000000010000000000800003b67081dfcf94c11562da3385d81140053b3cb40ef4d9906ddd25b1883e3c213ceed9acbca1791b7e70c251f9551445946181de811fd37287759eac47f164284bfaf1e711d2ce04b717625d9623d16e3f1b80d673a4736cc8a28a8d6c17b18f3beeb121d8b6edfcac6f265cbd87e5c1f624a5970963bdeba7d40528931579870b010001	\\xb32ee39c4047f1236284458f6791339472c3c67e20d268be1bd540079569886620c9eb4fa255867cfa24260106c2e9ef7d0c77f20eeed0127ecc17b4de962d08	1681654327000000	1682259127000000	1745331127000000	1839939127000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
14	\\x2214c56abebce0a949df7e6c92851106ff72b5c51b7b1c659cca97ae76e4b387f76e483884eb2508644f7ac56a02319e6f12f9f49bafcf7cf356efff23c6ade6	1	0	\\x000000010000000000800003cd5e7d1657f8cb4700784c1904949bd9f35a8d847a84d9559524379147734f4f70334247557ef886e6a3d4cace9c816c990effcc8eef26d6daec35dade45c801c23772a85e656a2204e45e0dcdf566111e69ee019ae53e6f23f9b2015c662e51aabb325353a277496b3ef863e8e9b9d5a28781eb382d290e179ee24e1e91171f010001	\\x0b0385e71d9b63c9d3f6d07091bfd3cd2792a62fdfb1ec326548c1865f1151623ae702687924fa2c9d3d3e3648619d0414c93860f1fc72dcf8ed691726c5ef00	1682258827000000	1682863627000000	1745935627000000	1840543627000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
15	\\x2334b343cd2af6dbad3968a0d463d3aaad5016db59ee307720582775f2bb7b19eeb3cc76af99faa62958a332ef32aa569011d8ec0c834617515768dfb206129a	1	0	\\x000000010000000000800003c5a0d190928ef06d73a801da9f00aca1dce71d533d71b76bc6f16a799e471ff80ad5108da74b1b2c793dbe47d81fd9ddce1c3d19c009f097b144f9059bb571fa6a4357ec1ecc856f38c46291cf14c068940cd852845a68801ddeab5d9690291e6c964fac95453260c05e271a766755d741c046937bb7586afee745660b1ecf57010001	\\x7794e0ca88517027bd2f3c209811d8533c1511e3ad174a520880c38e62a6d6654f261c8252ad599df72bef574dd8a2e2a18fd21ce9efa0107b6f0bef715de002	1691326327000000	1691931127000000	1755003127000000	1849611127000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
16	\\x28f02903bfc0706ee711985696069da9dab98891030d340b4a94b7f14670a69937e7d9d82a64f9db444b8170438d39e158ea2ecb4c63540939b4818a24b0b516	1	0	\\x000000010000000000800003b9377b5e8fee41c368d8e8d248815c1be5f9af648580c821a4ff7e20c83bf18294c62cd1635421f329a5e6c05537eba17579828355ff34c00b09f61a13e3df394ff6ee4dc6a2e88e4dd6b9dc124056d86fbe7c526eea59a4732b6241b94f460190a0094209f31755899e99f30ed01aa36e983af174ad74184bcbf158ae62e1ed010001	\\x3a232d71be7d227284df66f2ace90b7a9d8c00b54fc8628612230b3c31a2fa83173d7e6b44f1dbdf1131498e133c32a8121308b5a0e04c15be217515b9191800	1691930827000000	1692535627000000	1755607627000000	1850215627000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
17	\\x28180c61b2050ba40f6a8371f124480263f81f0a663be37b8e6e7d379d5d9195f26ce382d55386fc315f19223f1b63154b0bc090154536c1374416883d67d782	1	0	\\x000000010000000000800003dacc0d03abd1484fef24aa004323c827ca8ab060b38030e2da89de8aa4390c375c748329d3378b6f2819f1ec8ec4cf9e1354486ea389f7b50fa5165e8101bd7cc6fca1a4caccb565df16b81bdc9e97ad1c8299b76d01675c00f93994746120ddab3aa80192d2e6c0c590fcb5e1ed09e779431f18ab17383b0bb83949e807eab1010001	\\xd6932b00c63605ccfa53814c2ae8f249b45ff0af8a56aeb2bbd5ec81f19f6426043685a3780000c23f4095d8bd228860ce61d51adc4c0f860df6bebb869b1f01	1682258827000000	1682863627000000	1745935627000000	1840543627000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
18	\\x2c4093df0b43d10019cf69f747a846f627b8cea61ee7052e76ed11279539ee5b9725cfb62cd9e52d7cf7790f59175051e03d26cab4d42bdf57136801ed5e5fd5	1	0	\\x000000010000000000800003e7f388f7ef1955d503927fe0bbe7a09ec36a55d2d78d17552375929c8f5a2a5514ff7f11b8d71ff78a566f5e2211b4f1cafbd8bee453ac554fec55de5194c7f0dc37d49f6326abb4cc3f3b1cfc4733dde386d4bfe9d273733125503a622ca79d1663d3376a29d189455a0601ef2c8b8a648ea032f08a64d5868b876a3fc17b5d010001	\\x2282d162aae49fc1bcf54cc8939600e76b2efecb9f35b3ff38f5ebcebd372e28496d38fa995e7241641ddf9043fecd68dd0deb181e8b60aaca584451b421ae0d	1684676827000000	1685281627000000	1748353627000000	1842961627000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
19	\\x2da807bab45902ba8ba3188e2778b2745e7892d5945f169a4a4902a30817b962ec309086994ca4c80d4c8cd8e042dd8f4d53b1e7897bf5bbe2a3fa487eacdb2a	1	0	\\x0000000100000000008000039cf6bce93173a92307d593605c7c56ace3c86fcb60027831fa707cab12b42bbbfb83366c7f53f225bc76dd3198293d81f4f977b0aff2a1fa01b3c6fa5afb2fb8cc28d2e546bdd62641d35945685d7fd54bd4b10083bb5e7d07a8bc3a20f00a32cdaf034bfe86c15174873477aef3d61c6480ca301fab4c6784228d8227134177010001	\\xa8469d3595607f12a7e1732a9cd1e3eac405c1284ba3ccdc12f6bef552fe756610fe4b382c251dec27c2b2646bf54684906e747ae0a6c8695c95cfc4c70a6006	1686490327000000	1687095127000000	1750167127000000	1844775127000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
20	\\x2eb013754b7f3ad7206780590ff470d9ee2dc9123f1ed4fdcb2dd0e4972785eea7706f0723667710d96c2468a5323ecb127e8aa8572588b96eb6800f9b4a919c	1	0	\\x000000010000000000800003b41c60a9be20993b2684a15574df6c1bfd0f312b6352d8578c06c2a97c3d208861ede856bfd0af9c29948b6eb57e1713c5fc7b8fa36b906afc79aa9ee92051726641e656c513c17434ebc0697f00aa357e2dba65352163a5facbcec8c74d7a31297743a7d1a3fee3cb51548213d522c5389c9a0d50a4bce20db9564275fdb651010001	\\x8a3f22086e97bc7d665c9aa7a1b205b0a674f9ba340feeabeac95e86d2f64290bbb10a9800de0d55449f20b9e45ac80175942361155e08b0488dc2df8d28ce0b	1689512827000000	1690117627000000	1753189627000000	1847797627000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
21	\\x2f409d3d388729d2bd1fccc85474b9298667e565546c7379c4ca3ffe98d196ae20057b11ede857f13e2a71e4f0ea3e436e217877ed17840a81cfd0c9030b592f	1	0	\\x000000010000000000800003d5cb6a7dcdac6dc0204960a2086d4605230228430aaaa3a1afa4f2787264636536f07b579be98b7fbc30d23f57e05c5fcd6aade99ee7196d02bcd586502c956a9581032f3edb568ee88176e46b3b133ffd0d0b9762136cee3f3120cdea33c0d7c6ebe51d442c295eaaf290e27d9eb960c1de10e81e41be863c07c530de548995010001	\\x728cdee1e176a7e53457e9e2bd6c2ad5494800ef40cce08036dc06496bfab589728c403c8d8cbb74b5e2899903420ccef1684d942fc8cc5db6b34e0c26d6c70d	1685281327000000	1685886127000000	1748958127000000	1843566127000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
22	\\x2f5890f9bc40e38722c4401c00eed60561d1511f0c8c73a275c35dbb94995e4614e50e53cca194c15ded17406b150c862f1798c85309e19f9094d962f74f6832	1	0	\\x000000010000000000800003b1a0e525d1935c21b770b1e12fef085d5d3f23ca894393aff6851bc71301b327d58382955bcd2a9ff00a24420fe17dfe365aa6b96917dac7129209a874456b7a0f41c411135facefe8ebe3004620761f734343a39974abdd7f5c948e15731c21ebd8e28a2340063329d7954ceff319d19d3ca55a76fe8963ef55d0ff7fd6faaf010001	\\x917de0a99026966f6bb92b7403906f654714180851b976f326d0744cb539fe10d67edc30e6e7faf3c1a5029f71ed5942f9064b2c733f7f511bbcd87ce9057007	1691326327000000	1691931127000000	1755003127000000	1849611127000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
23	\\x332ccff6c2b9f3649409fee3f711e8217390c36745a8dd690fd66feacd9f07b4bf5811f4756a47c5be10bbf180a864a1990b67bfbdc4063ceb012e153721f4df	1	0	\\x000000010000000000800003d6ba0168a34668323f575296719228a5baa4ed2491be98ddbf8bfb55e53852ddbee02cc1b8ab615c18d7a33e2a23370a5b11979be26f452605c729e19eeee38a8f1b1bdd4b73e8137e59a1acc65962d063ecad1ec951141d1efbf32c5006c1802e939fd40402f44dd520c01b6241f5dda75986baede40242e99895f69db4457b010001	\\x43c80e4751f2d41d71b7c4bbe126aeb1737a5bc76986d9ffdefde79e9864490ee97df8c6e38696c1373979635f97c341f6e2ee293b0ec46405d81770ac85bc0c	1676213827000000	1676818627000000	1739890627000000	1834498627000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
24	\\x350c30b0e1fe8aaf73344059e69f42070db0b28cffde2bf00c80fef5b166dc307ee84159ab02a85187898362326b26e633c3fa036bd24c8e8d775e7e630c3891	1	0	\\x000000010000000000800003c737330701d1a519eeedb6aefc9aadbbaff58ef1bd027f77fa5f222bcdcbafc5b0899a900473e8048d9dc66112fda610dffb568c00a5f738684f09f1159a76793f801f28465db60255df71f4c39548d3bd7359a6c6c971509887bd6dc2d4d482bb49489946fd8515b9c29b9ebe58b426853ea4febec76885a1a686ffa24bec7d010001	\\x7b9d5f850a5e198a9193988caf51eee029a27c9365e4f1f537c4b09e865914a9e0ac34d6a6c4d47f7745006a8f597c66404f87cd178d7b767f6e5e8a94d89005	1673795827000000	1674400627000000	1737472627000000	1832080627000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
25	\\x36c81452bad1b58f86c3cc798d2f2c31324873637891e691642caf649f5d164e7fa2baa3200ac603891f0a5a3a8b631459453deca83aa19f944055f2a1d313a9	1	0	\\x000000010000000000800003d79706e1ccf973699d9ad4429ac346cc5925c8b62dfb9ead08c16faeaaa7c5954f372c87fe5ea4f9bc95a6e0ae0f80c48818fb454cbf9b898abd9e5c02dfa7c4894a13f5284bb25230ef1ad514d7f697c9d92790dce6c74676736307e29ed7ee0d16759f3483aa4b87f1fda1f636181427acfa499638ab60dbfd8fa65a0afc2d010001	\\x376962f4cc3083d3e752a9fa4518ee5fe6eb5778f9960051c4cfe417b4567f3aeeb11a2e9b64c053b3a492863daafc80859554e13832c6116c83a8f7d92ea406	1682863327000000	1683468127000000	1746540127000000	1841148127000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
26	\\x373cab27df4e1dea4d52a5409191fae7f141417e815d3da1e2ce65fa54f5511722cb28dd55fbb9e3e3b7c3878f17b2a9da88f5894817b776ee67d15c31a6a35c	1	0	\\x000000010000000000800003c93285654a4eb7cad7867b4836aa9979c3a70b2f7feecca3a031af4e02a8a3e10074485fe41eeff7d1a02598c6940be3e8941ccc186462d936d2ea7a481385904aa6554ec0f017293296d3d4c9b50dd58e3f6718b4f6815fbb4848a708211dd2580811fd221b9ae18e68c4ee15bb168ef14e7828f3a7c74ce778eba771e0bfe7010001	\\xea9fd8a59f7c975ea314aa5664e1387303bd6aaae63d505ffda0dc7749736036fb0110edd18ef50e9ab207ebd7b579f6ad6c8b038cbf7ec160f77f5d6483db01	1664728327000000	1665333127000000	1728405127000000	1823013127000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
27	\\x4248ff16d75db09a9ff2205254836e6d0c29b3b1d533ac7be970da6be3f067352b1682d6ec1dbe0f56cc46b533cb202c52d876356048b2a69614b181ae8c1dbd	1	0	\\x000000010000000000800003d6a021935f6acdc2d992ec1fedd97a407e8f97f4722f31643f150b7c6c11924c288340253c87ae49cc7e93016017e4683bc5103bfda9ca2b5cf21589ef799a089daf989da57dec4d8f234a12e96eaee5003440fbc237b557184a0e5e2c7fef89d586e6b72d56913deba90756d52870b305981731441edc2157c81310a83c3d99010001	\\xba25b317829933fa10da4d54ab2e660573164a9ce78e3235f5f31687908782a89e44f77482587a32f403e1056ccf3dc9f0796cc0a37f8cf18366cb5c6513f20b	1678027327000000	1678632127000000	1741704127000000	1836312127000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
28	\\x42a00d33329c4c5e064174630724efd53a203f0adcf2eb0cfe66d0baeea7e9c3de9be3c475c7dacd5fc461e17b4eff3997720a99e3bec0732a7f96f4db760bbe	1	0	\\x000000010000000000800003c88a20a2625bfdb0e260e8a380ccff7a8c7a4bc334fe6e2142a07370f7fb06964e4820411b085182763082855f7d39e4ce2c6b326ddec47c4b843a207ec0462c2d51db45f7b1e0e2889d0fa560e9eb835c5fae4d6810c70f6ff6c2338b1ac642100e60d458b0c120f04fb99cf18418c4d814d953f9e951cbe4b3762b9ea6b653010001	\\x9dff213493612dfa62e4666abaabe27475650c598c867407478e3fdf086900ccf275cfac4b9a277e88c4367d46155a708c4dba264bf4381c38c0fbfabd34d309	1670773327000000	1671378127000000	1734450127000000	1829058127000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
29	\\x445042858bb055dc864a48242ab2a4c6df22440ea8d8b7d086c0b4b1166d5c7a9d0ff9c25a84bc9fef8e97baa8c45af6a4ef44f1b48e479d35334c78b6a1f52d	1	0	\\x000000010000000000800003e12a9b1d671c8a26fd90afb4b84b1f56dcc0839dd68d9b5a08b7b42c75bc898360273cf1947893c793f6c539c676641930366e38a89c966c742aadaf3b51482bda2897f4528e5c91b729311729e1cd484f1c680ad2b8c1bf7f262827f4fd9b06b3eca5a3bba7536ce10b58f60c14920292ae396f5c3f5ac54a1d48234da7db63010001	\\x5c8f0f1fdec0882abf2645e33dab4004cc4cb47307e65a051ae8d289a41ab6543fb212f68c0830c89be64f9a55ede73bd41c458c67f76ca347f990a7deb7dc03	1667750827000000	1668355627000000	1731427627000000	1826035627000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
30	\\x485cc6f00c6274baee63cd2c5e7d3f6746783d1eb21cb313cb6d976a079e60db63ec26843bcf91dc038bdc45eb08d05dcf1e38f9da994369cd00ddee8a93eb25	1	0	\\x000000010000000000800003d37ffb9dfae8a06c8c8987159b230b2c744ad8dede73a088b46b8be9d79504b7df5d11fbf28694478ec68f5eec5209223464d192090be4264761c4639f7113e0bb5028a534f78147ec9da5bcf6fdf41c79ece6191a979081fc36b8db0e35db3c8479da9a0e36a43b2303a3d59e669a1ef1a3a74b0b00f6b820c7ed060e92cf31010001	\\x5f0f3439c6c34fefd09bb7d4c58591615ec02da4c81f7b6ca199df3ee91993fb5021e4889bc556568394321a3f4fdc1f140c86d469a9b8ec35a0698437f12d0c	1676213827000000	1676818627000000	1739890627000000	1834498627000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
31	\\x4aac77bf482dd93ae9c14b59b444c1e6acd929825b8851af0c18839ae7ea1bc3702450658a1296a0d08a46deb600105b1131f358ed2d328c86ddf7b4f79cb88e	1	0	\\x000000010000000000800003ec5aa70b1c13e7887706cdf7cda1fb2d9875030d22a9a6d64a599e64d650aba24597e0ca4ed42618f392a2d559fc26c48358668874eb65f358f2bf9a1ef371901d7e00fb80c00d1a2ccb7ca3e5f1b4a1eb8fbf95df546377d658335864c5acf735973cf0151e503195311f098ed76466b205ba15f687842729cfa0d5f7f79ac7010001	\\x259bdededbc00f51aa388fc6ea1c1ace5800323d95caec0f2e521825642dded3d28259b338f793155bc498b584651382540871d7f8a6189c6c3237f41334a409	1684072327000000	1684677127000000	1747749127000000	1842357127000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
32	\\x4f30228c97aef18901270569d4578f360edcea79d4986aa5f07547808a361431415b21a9b9a8d986764e2f5b236f77ce3c9dcc334f3056abeec1dc971e73f91d	1	0	\\x000000010000000000800003f69ee40916216004fc9a24bb4aafbf3825e53e3c96f15a0daf326c84e143b82b24fafd43c975ec86521255aa2f419855f0484001928cfd8775efe27a49d9a48b0f00f06abe1b8bb9110c5ffeecfccbfc0872453d213deaf44670f911cdd68c210ac7ec7b7e5173d539c1f4ebdd3586d8ae1d57561c63031dead7803b347dffd5010001	\\x28af81bedc632d95fd0338ec270fabce8f7130502f1c5a49cfc9d09237b858e06f60a55dc7f040c059f34c9a0bf2e8c5267a5fca61f4de4e8118e96919b58f00	1685885827000000	1686490627000000	1749562627000000	1844170627000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
33	\\x52b82de050c1a736fa15adf4498d6b5d8e4fb73561635f62bffab793443216989f9c27e5ddd4ec0f6704a1142de5e09c1ca9310c2eda043d2cbe59e78f016dd3	1	0	\\x000000010000000000800003b2e25ba8c11d3a97804630c2d6163fc6f2b08e6d6eb8aa139dc0cc18fc40aa58a5aeecf0f84e299707c6d8365e2e6b5b574f1eb1fa5ec3d33069e1d5f083398a74a3e27dcb7d7ce14b2caa436333534785325da8c50dfa4932e01d808b28d91fc4499c2d4267da8b3afae905602ee2159471947467320448e11cd7aa30728bcf010001	\\xffe841565c6e479fbdccdfd0524f2d6ab94c569c35e6ed66bd52e97de80637519241230bc12c2f9307bb36c6e0bfb4d344e79879ef72000bfac68a675073960b	1681654327000000	1682259127000000	1745331127000000	1839939127000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
34	\\x597c6e69a55bafc82a8bf2227fd1288683a4d49d6703f49b31b71ddbe9de4c9bc32a1f79f72f571f0820976f4b6bbcf24606d49e739956d9e52a9f57fb81a80f	1	0	\\x000000010000000000800003b8bfcc1d3ccd301bf4f6bddd925738acfcda9ae908b9d9b784951bba9d166ee840618366c286c02e0413fe543bd5df0fe91b920f00e12601a61c775835ef24cce799a15f05833f67cf7035e2a71d6a0de2ec0091aca6dee49f25e6faa2de801e7d9cbb69d05b0b7a2242644b01b8e4e3118b22fb3445681472e00f1a7f3a2617010001	\\xc914b606aeee36924660a2c4f85668406d0e9f940e59c3f239453cef75b2e835a60936fc48d09f87d89d771ce935003d9e2e56a7e8219ce548cc16d029fd7a0c	1665332827000000	1665937627000000	1729009627000000	1823617627000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
35	\\x5c08c6a597c689eafd1c2234cfaa250e16796ecadc3594ddd8ce285273f855b0be36b576a9efdeef80adfb9879f035c5a79fe30b48622fb7a90e7e2ad71a169d	1	0	\\x000000010000000000800003c776c9ea33ea9da02b97a3423f42751e70a1f9af896a9602e963f39634d428bb2cce43cf6044ccf79e9748cdbad96151f22291a303e6ffc092b5394df2990c2136b6f6785972f3c1e571d32d8030b0c77f39d6b41dfaa31d17198b37efb78d1e763a29e0a0e90ba0d1c2385d44020a19e131722aa2f2b46f421add1b4bd56023010001	\\x2717b7d97e4bbcc544c248f41637fb655ab59f358fb0938650506647f67369cf980e15c87dcab2f0e2c165d7982206ff07a47438d7c76a41d33c24882f737904	1665332827000000	1665937627000000	1729009627000000	1823617627000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
36	\\x602c220a0ce2f3e176ab6cf08be6935ee942bc79ddc07d56a079b4d0065c11db7375ffa2563da83a88498c0b292a8e635843793324fdd47174149bad1fdba663	1	0	\\x0000000100000000008000039777d0fc52210b086b5e43c1d0db25021af95a78a2810dfb9305ca39636659c849b7c3c417eb5b66ed7ff27e766fbdb5f72c262fe8ff0d6db0ad0f0875ad700f06c23bf0c8ed72129be995458ec2bc50e10a21566068eb7f42a3bac4ea4e3ea6067064daa3d0f46c466455ed9ecbffd92415146c6a160e46051a157bc7c65bd5010001	\\x9d72d0b8637ee5bffa5b9795ac7ac2b09bcc6110a02e34e7bbf48ae50de3bde2a73f594e39cb25611776747e7ca360c68c44a07e20791e674fea0206d02b0500	1670168827000000	1670773627000000	1733845627000000	1828453627000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
37	\\x61103092266eeaa78fe2cceb8e9679daa14accd8210672d9c2f862fd76aef3125dfc68449d8369fd2f1e4ec984eb0abcac81739a2fdabb142f3a8b90f14d34bc	1	0	\\x000000010000000000800003c0de980a16af86d75e380fa83ce91843d2356fd26a36f4bb02b21a3aa92778771cc440418cd24662e65a338292cd59d2e47d312e20d23f5b2badb47a312203f2c9e4e01f27b1cd4eb92dd14ba7278aa4d6db2f7bce8de9b75c86f91025c1d733362692a7dd97ba06377c959e3635a5a7d35a85678e977c445672eab3754dfe11010001	\\xd796eca31705e12175dbec2245bf8c4499b660e5866492d189ca8e541605aa23e738e3bb2ceec97471235ca504866915c9ade5b4926fa054f6da95bf6e75d300	1672586827000000	1673191627000000	1736263627000000	1830871627000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
38	\\x64d0e6e3737b2d16a52a66270547440a7ae5a23dd9d34b23171ce8ca0bf0b8626c954bdf585b96e4cf8c9112efb13327aadaaeb1f82e69142ba886f84dc4ea31	1	0	\\x000000010000000000800003ad28f7da38269292ea21b644927648803965a2db5d8336d5cdf149ed43a56804bc40ed2f655aaf5a6bdf7d9ecda6e10dc0028cbc5f9f8b9864a9e59ac918a2be5a8f9d19b4d5893f19b892b70265c490760978e90f10720269bd02ffbb587046f1e3527b1b5eafa99620e0d28abff3ee8595d2ae858ac6c57be6471024edb237010001	\\xb7ae19abdb453d3cf15597e2448631198037c306237c4303602850851008c28d4d8f5dca8cd7a4b1145310330c2fe105342ecd92a3fd80b365b7e263a3557209	1673795827000000	1674400627000000	1737472627000000	1832080627000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
39	\\x68c8893f246d2aded7f6c0b54f315612e7f65f7cd119f1317b3bd0dd30a983b410aaac46735d04f23b72aac2d545c864dda4490c5d9a8aa82af42f05b9e0366e	1	0	\\x000000010000000000800003d1a125c5704fbba0c71bfbe26b722cbdcd4497ddbe887a6d6836f6c26243ba01007c1a630726510ab8e68e4b7cde7834f8fab34289453c705f07b3d2a180507e40b753f8ee8bf896d97b6fe736f3d58cc9796349055bb9b559fb652dff2667dc3914ced872324129bc0ed604130fea370ffc38ef6926a4fb33f67ac887a9f8e9010001	\\xd28cc29fd10fe9d364601765d872d03c3635fb6a696fba873b385dd55e1a12e52e584246c27f32541c9a50132dbd455617c0d74dbfd7c91169f6fb3c1bd08d0b	1670773327000000	1671378127000000	1734450127000000	1829058127000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
40	\\x6adce20c8a40ad4335b4763baf104969eb2078f867635ffbf2077418a3ca5dd36de4c4a0a3db69129c09a5e7d1307e0c3e81e735e614c26680767b66928523d4	1	0	\\x000000010000000000800003dd0dee2fff51a3f3063acf35ff339600002db4f55d2b9a422d3b14dd7f98d40822960c89f5ed6d992c9d537ac158418bbcd4479c94d30d96e15d1008dd0e976405ed958734a469f1d0c898e7c98cb58327669ec78f512751a3494a8ce71e03df5eb205f4cc2f893517a41954bd57b5a6a522e19ffa27c176dd1d9fecbdfc8173010001	\\xa12113e02c5611c29103fa8ce55d6c96a5628bc654e52a6ed0658934cabcf6a2006c8111046349eb52e9ef85920dbeb8e537efc9711e67a1433c3955f8a37402	1670773327000000	1671378127000000	1734450127000000	1829058127000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
41	\\x6b040e8f577aaf4373d0867855f080d0023c87560b9b584a052ecca2fc63d954de129374c51800ec8926540d2302c93209f694583ac285ac07691aca84445424	1	0	\\x000000010000000000800003c0f8962323636777f1c8c8e586f7ec85086abb544b49c0af5a1bf4796d1274e3fb06f0c874752a0242cfbb051bf97f115b3a84f27d31c81413aa6f7913377bf92a5b7a927cd1db1c6fd2fb03a6eed7be33a06f64aa44d97d370415aa8333ed3472ddcc819bd534bed184677fe2aa91df223caf2b855cd9a4e94ee03296475501010001	\\x2766e744c0c8f6e353c83227d33472c099ef1760828b6c0f525b92e64a0bfca055ee13f763ba3f26c1956f1bea7cd5f510c1b4e19a56c444f328d7eafc48330c	1667146327000000	1667751127000000	1730823127000000	1825431127000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
42	\\x6d0c3b513a59a33ded37c07b2395310e5760d22578b593bc2037595f909023d67f0ac9e91f7591c2a87298de9ef9e2e027bb1e030663260192d3c7d3b1e04819	1	0	\\x000000010000000000800003c912511621609cae3555908f64b88a7ed04f01de3e2d4dc657b412c9709b8a9c196344aece94036bdf20024643678047ccb006623e97c65945b3e20a7ab18c1d03b02edc45d81dede42591d3e0d4a1677bf4607d8f8b6175686671eabe894b35d6c4d3eb9410c4555581878d158b4a734bffc965b494b356f4a8973f4b6f3985010001	\\x92e2bb586387b15b249e4dde20174306fc87c9694b198c588891b60343f96620ad3c390c8bdd6a696f37fe5c96a9473c541685cf30b07d6f2d7c68a0a93f8c0c	1690721827000000	1691326627000000	1754398627000000	1849006627000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
43	\\x6f5cd087da95a0d3d1ae87863572c9ce70d7c103185d201ab6d58e127535b3a14facdfb4211acf0507bbcd49e65b072266113d8cca2b2480ce30f913a57a6c27	1	0	\\x000000010000000000800003f112607a98a42a4a60e1b7872212fbc9fba3d145de3179d625256aa2b123de5d3e618b7aa0d51c5b9185f1b5d051ebb39272d3d15f79b9556e45148a0579f52556b53de71a9287a517b4cb4b12cf8c635f04c3ad6cae98413f8ec8bba8826edcd2cd3ef1eafa60addbcde127dff69a8c5a4455fc7535c73e5959972b56e8169d010001	\\x7dcf842be6173767147a8edd2da54478c92edc42cf57c6e53b9d433f38dfd120f44c3c4e0fedf62a2a43a874030cf6d7d1e7a7498b5df208d330cd89148dcb04	1675004827000000	1675609627000000	1738681627000000	1833289627000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
44	\\x71b4f665b8b5c9cd311afeea346e66b23d0d7e4fc991db3709533f1303241ad6a11d4b8b1e3162fcbfd54395d72d1a5a3cc189e213a4bd3ca6262e470d74890b	1	0	\\x000000010000000000800003a3122923644444f515ec8ab93095d80c8fc419b6b4c436c0973818eebf27037ecd98971bb46748e39279fa987e85e73e5190fefe24eb52a03365602b0c86f4cf8a81983fe89858dbc4d16972279efc5d1413fd3e25ac52fd0bf30a6f5134ac93b5f23c5eb303a6fe60714d52aa2a3e1e930d658011d739b52a5600e25db72b4b010001	\\x36fe93aaea5dddd1439bba109becbd021275f95fbeb566dc308f95dc17ade24942247f73f816401b1a1fde173aa7b757c9ad36bbda1e9adb9185abcbcbb41f0e	1660496827000000	1661101627000000	1724173627000000	1818781627000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
45	\\x72ec729884bc67294676f5e435553a0ccdc84e57b218073606a6d901d4a79e365cdcb8e941f50b291798d84f30c84180bc55105bdc05f51125c943d16314a0d8	1	0	\\x000000010000000000800003da8affc1e33e1c9740dca61a0e404f489cab885d653e3288fc5a57da4e59d2b5269b2c11aed1595b57686c2872afb787ef487ea22cd9b54a0a75abca848f4f4dbcb707b469806e3e557e99987f50e9fab99ce51483eab846bf83c9b2c194c0b26614569f0497d13651c1fd36e6580c6e4d42ea9691935c445fbed09daaaafa79010001	\\x108385ccc93499a825087e11001a3a233246b2888a3b02eee5e3a3514d74b6629153e067131002f31e694a11bb1fcbefc1ed40d5fd80a95bc0eb811e0ad9b706	1662914827000000	1663519627000000	1726591627000000	1821199627000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
46	\\x7354e9759ab063c5cb998d2c4eda2d812e5ff895afcca041eb22bfbc9e8b0ffda5f71dfbdd58ce5cdfa4825e86e7bfb89f7707c7a23c4fe45a29fd9a6b6edc42	1	0	\\x0000000100000000008000039f2406ad1b62d762432140ecdfe969e0e2c4424a5a66baef3c144dcfedb56097357d38f3792ae43cccd6ac1824a690a2c391b52d8cc0ccfa3e7ab972ba797e556bf904d74ee9fbfc6a4e2f7b91c78e127e75802ddb96081b3606e47b2240b759f678ede1eaa243baafd0777ef23ce4ac4d38d1cb5640ef15425af8c9b59414fb010001	\\xec0612282f058b24949c0947bda2db69531ee4ce17ae850ca855a315f25e84457ddc02ad58654ade8ccb7dbd58eba7c33ac00c437cd931f37ee9652aa6c2fb07	1660496827000000	1661101627000000	1724173627000000	1818781627000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
47	\\x73f8583ca2af5034cffd07dfeefa1efbb67587b0700d6f80f1a6e1bac3421484ecd6e9b56fb3bb972d82a42e497278f85db8d0bf272a019b0003ab9db14320ae	1	0	\\x000000010000000000800003f02d9835d012fbc24a10076b517947f2b0baa480e7695cd5fbe1e24710b35a956fc8fa9a95df7b7ec14a4d01a782437a7de6ceae3f71bc661171262e5d5d72847836c7b4d6123d36ccab13240985b6b586303967c3bffccc162cf8abb365c1f3a60254ac4ccac0829d6044d9a8fc8445052199e03a426868af30b2b9c8b35921010001	\\x112137c786464f2365a74b9779e9bc199c76bc3f165a413af2252780cfc3bc8abd0c85f4b15f43b6a21e94cbbd6f41178fa889d129245ab1f5a4c5ddbf12ce0a	1682863327000000	1683468127000000	1746540127000000	1841148127000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
48	\\x74d43f7bfe9e20c2356cf006d48f127d2e118c7799d5d61151e3b537b63bc9b1a37d391f9f5cc3887058b52d146b8436b47016384130467919dee142ef7724d6	1	0	\\x000000010000000000800003dfc701363c737bb625bafdff75c8270a1e2b0fcfaaed5e19d825b65f95b8d8727baed5dbb6c372a0d27b17a993a1c3f07b91d8222f7f014aa770b7df1a49173e2324cd69e415a8f823792ea3398b1f8493d3ce44092ab8cdaf229b5ede37263789f2d9b64764f1d513e0e74ce750f852a5a38737b07b57b75f802bb7082c2edb010001	\\x6e8d0d532737bcee3a9e5c1b8c4c1821b978d874e9b4933194117bc36d768e0517dd5f4a68e0fc363b2ee51f8b7618881b063c8e13bba31243d27dd4a62cf704	1671982327000000	1672587127000000	1735659127000000	1830267127000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
49	\\x75fc33d8b5793e7315e05e1b28d781dc65097e90434f8d7601ec641d88764d9fd2e50332464b1f85a865829a1dabe9dc6e3ec87cfd2c2e7a98b1c5a4b5bf27e3	1	0	\\x000000010000000000800003e2214e297147e27de62d54a415009870d6e532f25a7233d85cd95ce7af2dcb5441efa9136f1a23ccbb894ed56b22438fa34915a6089ac836b69a0efc6500f3fa97c1cb9b72706a2a535eb65d3f394e1cc31338e01ea1d054faac13aeee2dd4749e35e8517063eb59e338b2348944654b2de3b024bc10d300b56ea6f5b6aecf69010001	\\x55b3717231499100cc3f9e94a464ca49577b3754a5762e2034392413dfe996be2c2a0bdfe7ca2475bec4d570a72ca48db0b3a92d8c1fcc8151560ad43569f502	1662310327000000	1662915127000000	1725987127000000	1820595127000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
50	\\x79600324ef5736db5660f62c73cf63b90a52d4e2adbd71cd3e39b588a32255d4347a4dfb0852371806ca460808b86cb79e43dd801804a401f4bfca9f68d50ef4	1	0	\\x000000010000000000800003b3b997a96488ad09a7828ba3896a334db7a61b22502e105c213d6e80833c0e8987dfcd037d44ce2a789aae6a34c792c1ff88a8c424fe491d48a7401d87f06fcdc4378016d64b844f7a92777852b6c758de68bbe109e73e443c89b9c3fe52b4a317e2fb9ee4ac5fe59ebcfa614ed55e738bcad03e1bd661d80e1b3c106bc31b21010001	\\x99379232393d8dd068f125c299705069f015529ac6358b1d32eece64e9c8cf4863a955962e43606d8db8f75fcbaa2c71f810108b6b0d25bd68ebd3c3369b5709	1668355327000000	1668960127000000	1732032127000000	1826640127000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
51	\\x7a40da06900cacba14561b872440b93199fc87c83a47dfd011ef344680465addd9d6beec76b4191d0cd92db34f8e6dbb4e4241e31d22359fc66103b224e95f21	1	0	\\x000000010000000000800003bac6b55955076bf57094182889e1ce6d1918185bdc131f104f5092c3aafcce9e3fca34c0b91e260f4b8c5243d5f98554f9f569c7efbf54205726f4b8f7b8f26d7ac57adb06fa7e10bff36cc5f7de4c9b1f944fff0d508270cc082f72c5b1fe91fce28786b6d09497ab1a75337a279de43688da96a0b2b3c7635c4e0142142d89010001	\\xf69faf51f56a41cb25388440af85f24b87abed5f38fe6db06f42f9600000f821a9105c2762c3a18ad66b86172267edf62f0d0b8a58620adfd555ce8d1899c009	1670773327000000	1671378127000000	1734450127000000	1829058127000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
52	\\x7c50c1c7db21be1817e4b8244cccaefaf8c9e039aea9af4eb2f55703607e258b3df2bfd7bcea8ee3547c9b83f614af0e27fb774fbc7c0011322dc10b4419cf79	1	0	\\x000000010000000000800003dc4b3285c1de0db75b424f12ab68276ca95cdcb7a3406de37eb879b059ae274c53e7c88898b2a1417a8889b1bf4f84a9ced63d401a5a896fa4772b83ceb8ddfa2c1f8286aae6616593025fb8437875b5d48a39b9ad6cca5a53c208835e51edfcb91556e6d0f5a80dbe5e7c1f76263a0aeb22d576bc2eeeb4e78e0a88a1e389c3010001	\\xc99b0eaf5b839772328bfe99a52adde8023e7d6657cd8ad3a613babfcedef711abc2dd9b1392c033a9bf0e04284c25484f43ebc6d1597223ad907bf805869007	1683467827000000	1684072627000000	1747144627000000	1841752627000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
53	\\x7edca0f305c422aeed84daef252c89d7b9536de6dc80f925bb3164b56e0c770e4ac35e3594398ec6f1f2eb50cf0a74192c281240ec9a0792b65d3bcdfdfea279	1	0	\\x000000010000000000800003b50ca7c7f46c88885ce8d789a2f8911ddc71ed8cc9929f2b6341d8a5e76b6103835568a89a645e197468dc41d30b6c67df39497bb7649305ee97c88ebb77405a7a6a54498aff0242d4e94a44f431e4e5042bd79e8a5a3b382cb004ca6eb6a3da6e59c37bd6853466176ea50d31d14432643f0c6d9e96bc1e4cd7dc70ae1590ab010001	\\x05ba2e7754a384feccc5d28fd71866c2e49325d3b26afc56a9ba696147bf9656c9a08e99c907bf62bc2b5785665b12dae5cbe343260128692eb17dd36fac940d	1665332827000000	1665937627000000	1729009627000000	1823617627000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
54	\\x804c3796f3e9b1adf9049a4ae2ae9e96bad6f13f2a11f4c9fe70ce3fad8d28085a4eea70bd93b24e026ed97530b4dfd3fde7d00b8f5f667c8453cb7671140796	1	0	\\x000000010000000000800003da11d3db1d036336716c7b5f07d2d8bac86445a7bfd148415a0f2ac58992d9cf758068750e1a4076faabd1a1c7ce7180ad3f4e9a81971e7b3c7e861a4c0718337a5a40bda5e4d6f6c7f4751bd639ac614e25cf7d10c06bdf9f0d846dbce5c91867151d69e8b33536e250a7d8b1255a20d90257a886bec86bdcf82eac70d0fbd9010001	\\xcf15337271f0109d354ee3dfee6f68ccc8e370b4c8cfe9ba680c1852d4fd9de2be17a8ccb71dde0df24d9b5d0a3ea1b125bf835349283478eaff537076935400	1687699327000000	1688304127000000	1751376127000000	1845984127000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
55	\\x86acc907a263a876b473b9ba0c2d665026fc2fe57a50e4f0b8e8b766d85ad04d31fc38465757e0dcf866f11f334d1e217341607bdb4d8ea66fecd96dd0167a80	1	0	\\x000000010000000000800003a738fac1a6de10eb5383b57537eca868daa4a920503e7c8ada9d8562faaaa33239d01e966a6226bab744746244c3abda3addea465d1ba4a1126f5106d845d6151a02e685a7eb145e23b91e46cf7d47b58aa85c7300580d2f220b5be33cc91bea6c0d1bd4d1852d6a80a660db3ab47d512dd06d04d179f9e6de4acef10ee930ad010001	\\x16c54bd648354312ebd2c78566ea5dc35d1925ab786bc0ec717777b495acb8ec5567b685eb87c9630de71ebe36b9e461a6e8e723c71aa4c305df16a7f4060a05	1688908327000000	1689513127000000	1752585127000000	1847193127000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
56	\\x882c122ce9522207113e36e9e9f77cb9955e4fcb5acccbb23eeea79f056981fcf43c018f1db69e982d080424fce680aca4659426f0e3f10d30bd49b006b83805	1	0	\\x000000010000000000800003d6c695af0f63db2d8b403d5ee098edffc26a1c810b45d81cab7b385d5086fef2868b37ab4cc070ede1979c41a38c952b56274ef7a85ac79ef42ef6458010523a32c0e9377aa412348b9a4f2199cc367b5ba98cb44b6f74d8ee5dd5ec9234d7e51ce114368222c96fffc1b2a74feb5d2bae8096a3da218c6217356e25fbbd24c7010001	\\x68e9e72399d432d9d02df654f12d1782b471024713d4f2c3a00a443cd8f8142972716fb83d17ef31bf685671fd2e8ad8800494ff1d94b17b7dda743afa499a0a	1673191327000000	1673796127000000	1736868127000000	1831476127000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
57	\\x886c2383809d3123d26f0465ec39a482014e034a00abc756295def8155f3436e93f685453763736135de8f57aaa11b21a0dbe750b82a9f794ed84900322854ef	1	0	\\x000000010000000000800003b22c1989f583e15533f0cfa5852949075c3984101d94086e82fe1b960204d1bccbcf9349706d6d0adb54f753c2e7a3c2de6a39ce69c689bd7215e581b47720529e146c2cff2141a76886dbd9af1104dbb49857d36b759c31212554728f6c42be372e53336cdbd0aca2b0b5cef25839adbe6c03436b757ff2235a8f2799e7cc9d010001	\\xca40844b0d2640656f90ae67d9fda69a3a1b136793547cece64055ad3975eed6f52c452cdc5939337101eb5cf0241a7d559a7ad2726006a95727356718073f0e	1670168827000000	1670773627000000	1733845627000000	1828453627000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
58	\\x8decfc14d758e2077ddee542e24abcc86fedde3e7442e5eb76e1acba48809677c6ec8366f56af96237bec76d2be856013635ee1e2932da1603e34cef677b7c96	1	0	\\x000000010000000000800003d55efc74fc52df6055f1787ca9871ca9ec691c9d020dde948916de79537b2e2ce24b4b8e5762b29342485b6e22142f803316d6858dd8c02a241aa12086a75d2c2b14ddec39958d2e46cd08e504a852e2e382abe21bde27df0a42ba28182298834ba5b524110e6f9c809e32c6a18eda8b59975032def5b4f68305aab821a3db5f010001	\\xc66ad79c0f16276bcbe3b422a88e4a8e9ee8bf3a45e864e296ad6c79ac88ef84034286fb3b5c9cc0264aadf8a72fb6d178d87805c5406dee797d99ecebd6e70e	1685281327000000	1685886127000000	1748958127000000	1843566127000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
59	\\x8e50d9ee64192a8dacbaa3b3386c80bb84b004ac6f8c6d096fc17b020b29b89ca79a7063d1faff931334c9c1aaadd3a11a44236cf60382f37956b2b026c9c922	1	0	\\x000000010000000000800003b679f405f8d237afe60a84626893a21ed6a12ff153871e44d802ca007f2d183d91f4cfa70c9b29f40690595339a344c65691d0a4ce6c77d73c14f9b286e5a419aff7fcfe5c864dfbb9ab1d8d4fa1896bd26091ed68dd16dc5bbe456a30b033de2e9f5ca0d9f3f64c0c00fbea6f1ca63353a3f6148ba6f548cb8e6130f245c959010001	\\x5a6b89504bc233286c02932d862d89ae24d688edf2d535e4767c1f3a506c7cc72d3149b1a5a580270564ce174d67aa99c463ece32d669f1739eb83738b00660d	1690117327000000	1690722127000000	1753794127000000	1848402127000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
60	\\x911065327e721584b06c7843739f4d36cd1880b88a6dd2027fd4ff3d0b3a3efd63758e6103c34d5b7813542bd5206c310144168ed2a41dd83e7c68933a5f0244	1	0	\\x000000010000000000800003b9d92f29f8c450b1522d6002c493a1b5c013846e01943707e846036e340f131cf6f0b24c2cf73f36ea6845c40a65c54225cd87f4406f10e74fb51e492303b29105bfed8490dd97afe69b8e47c315fccd7c5b8bf684a30605d7b4e75f5dd8a3781f75b2fcfd226cde0f4f01df9aa4a85bbf385a06e57e2c05c8bbd291bed89189010001	\\xf2c98fd98035c0d2269d87e9cb2d06e5c69b31c4bd57f42643b3b6914cd175dfb3110eeb0bb5b60a0a6fb36085f9f5c60cbac0e06659290754ff2e7b4abff708	1689512827000000	1690117627000000	1753189627000000	1847797627000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
61	\\x95e0fec35400ffcff2b12cd175471bdfc1f2f2f58661466fc4380a2924b8480740bcbde517afacdd3a8c2365dc74940d55cb7ff01cefd22ef87ad59fab0e9e2f	1	0	\\x000000010000000000800003a083a2cf1e196de34715fb26dba4224aa6d4e7e9fe9202d2327d0d9da9736e34e4cffbea583705fb8c251dc5fa27ba6a2daa54110b04117f7f2975ccd02d78fddd5e88b6c43082889b346712079bd44abcb60bcf34e80a6f32bdc1470c60871d7adca2cfd7d36081f8ff5466b1335b0897fbca53d14c2aa436584cbebc293de5010001	\\xb2a6a52a75c486eb370bf1dea645849c95b3dac8c8d0bc7c9ace75186a8de015af0676364ab1527da99760e2ddf4963bc9a7a345df8e60365fbc99f49ffd0a08	1679840827000000	1680445627000000	1743517627000000	1838125627000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
62	\\x96fc9a3f459a679ac3b3d922e0341fc3d0604999f72e12876e2fa9a276431350923efb83407d5d78ced26b328e3cb5d2aa2bd728fb0feec086fe81c973bfb059	1	0	\\x000000010000000000800003f30fff032da4ef07cfcb608e0515365c307dc171159c5fbb4ecc0e3d6e87e2a4594ee6f311c61946b3055d0a0d5f83dbf8ccefab9e4075396048943d835fcd1dc3bd578a217561a35edabff06e8a5df0ecf0a8fb292206d07cc34b06e0a67fa58fd50b1396c4c790094269a9db4222e51266580d027199eb840b09a05fc0452b010001	\\x62ab916f0eedeb9e07d234747208fb1b334156d35c5f908f4b7b48ea2056a675f2ef32122e41ad5ec6be094b072aeebb56f3b673fb7d4782c8d39f5558a0dd05	1669564327000000	1670169127000000	1733241127000000	1827849127000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
63	\\x97d052c64d1dc15389160f9063adac78597e6a5005bf3158e5506e665a374c1c8e0a2c388192a6bc1f335619b20a29d731125b63361c0fdb56ae07b0b2418dc7	1	0	\\x000000010000000000800003ba147d91d93dd78f2cd17fb493a119a4b26dd6aafd6a95304eacc7624b5266fd78df38333bf35ef542c5460e876e273c53ec56ad7deed19fa4c42a70897ee643988864f147487a89bf3546f12063500b1ac576030e1867205e95e05521fc99168b13747ebcd48094d20a05dd14927f62bd43d6e92fcc15ae5b3cb268e89c9b6f010001	\\xaaa5a14c59128d9876da9883b43121d4c411971c9bcaa54ed1f876b9c46cb7d1582cd952c0242dfdc339301a8bed9c8f9b00c84dadb02fdc81fed1bfd4128f09	1668355327000000	1668960127000000	1732032127000000	1826640127000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
64	\\x97ccb71fcd902fa52441747ecc7973cd51ace8c6744cadbf989986e7d15ab7312c89d894514869ffd4ce001373f65fd5da9a92a41eb8d1e6b282ad499bef8f1d	1	0	\\x000000010000000000800003b247ed593346a3e7dde96e3dcb8890caed76c71bb484ceb62407ec7212e6d582a9bb02ddecd014db97520d1378303a2e45c266b42d99e59f0dc72b24062ef5c7a1638ca2cc009f9e8085767505f4d5302d53fb4800f2871a7de80546457a2403b9ae92188789add75f9085535969f9b07a69b3abed4424bea3f653c0cb34a56d010001	\\xd7af5d1a1c6ce1ecede7421979f0deec2339821c439fa0f85a9d29e5b9378658842c484f744b3db7252399d0223b328febd125f763fc1c9764028902d7381907	1685281327000000	1685886127000000	1748958127000000	1843566127000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
65	\\x97a0c1a873ab58f4bf05c7c0d02aba36096fb68c6e358a7f4d6cd9c661fb2fac85a7be54774993ec44cedb451aee994e4d84e315f0f05923e2735b1ed5a0a96d	1	0	\\x000000010000000000800003b5eb93481e740725731285ad45daac94e1c04c19e6b3340558c69a028d640c26c993ced88b002ac362c0b5f5fdc84cb0ced21ee2da7c4cf0b0c2465d11a3a0973738ed8e1a0af0e51eb654b4511a353891497d1840c7e1b184240346375682c7bf567a76944cd7ad5c28f886a870a5cdae04765f425b7c150d7b32819b09de21010001	\\x1d7cffa55d39f757f6f0d6fc42f07f0fcac7ff1a005cd4353b077435e3bfebb1feef2340c24c2380e08bf798fdfd66f760f939b39bc5530e839b53eb5d586b09	1670773327000000	1671378127000000	1734450127000000	1829058127000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
66	\\x99b04d6aa9d8bf9bb15f109cf13c4109b9d04a81c0825c47459441ebce07f2c8412d24471af8e4936a20d80ca0d9399998a085862f422d4ecf3b0067b3a374eb	1	0	\\x00000001000000000080000397dc6eb5931fc8bacef6fa9a981c603fc090d961d1007ab9d2b9d5acbb92470fb534876de1ce69e8818726246d9e529628e95d11730f468eaf96e51c2dd9210a4f75de632dd5901ee261a4889bed7fb40c811dd223e5445640673ae23491945bde64075f1dc0e452b5ebe627b67b37f35215fa5484aa96015b4706da25cf94bb010001	\\xc3591f0b107e9e893718b695fbf0785727ca11a90c6cf8b247a83d381779dd93eee01456c7e7783b26964213c9d3324f28e10e32106bfdad89bff6491e43430a	1676818327000000	1677423127000000	1740495127000000	1835103127000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
67	\\x9a0ce5301fff9535eac9d44cd41ca803b5647e684a401970054a0912ffc3eb564ff45d2a50910ac2b034f2ad3101d4a88be081c2bb88753b22d9a32871983e20	1	0	\\x000000010000000000800003aece52993f2d241d38bf6715bee06c723096654cc040f3ec813727d693b59173a5445faf13687fda3a06c95f96e2022a705a7141d82f986b21643632ed8153919dc1bbe00c20a02df52a7d8776b5d8df3c640ec22b21c48445151f087c1dc1115e33ecc1bf7fc7908e6ce4b477af919c805e1bceebd3f62714890424a7ba0e87010001	\\x596d67254daec09defec9f6df07dbf76ff3d8c339d19c941ecd6fa1a0dc83547cfbe5100fce80811ce1c626179077ef925979c842ad37c803ecb4798a099fa04	1686490327000000	1687095127000000	1750167127000000	1844775127000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
68	\\x9c10bd3ecb9d2410523e434b5d01e333a5a038f8efec0e391741a8945b1575fd2fa90bb469317365c0afc9f0534c0509c1f0c8c50d2e90ef14ac4de4c63a85bf	1	0	\\x000000010000000000800003f73f739c2739b75b9a94c480dff6cad8c24c06f75e79a5f446d9a569c81fc9a5e74e4bf82f26d923ec278a476698690575677f67a04a3ca4623c182d00a1d1b80e41f947ff62193e804529d429ae442bdcffa0057055aef3b8b2509d27976e06651a068d3ddf4177825949a2d3e0d2fc172ec32fb7a690a53dd5a19caa74a8dd010001	\\x1b68ece5ffd00fb7c8d3bdbab7935269c75adef3bfa48b18fbc570e56e326cf701619400e24792dbfff9f043679db6b33dfc9de54d8c1740cea65a037be10e07	1671982327000000	1672587127000000	1735659127000000	1830267127000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
69	\\x9e94db9802d2d3f1deea786b74c082f9d9a4b672bde219adb5b9613208c766df6e4d2ddf6780a787ed3490e7e16067fc3957f8b10c28355a98bd4b33e7f093fd	1	0	\\x000000010000000000800003d8d32d2ca5ee4d25246e37a08cc39b5268fafdde1eff595a5cff350cb29fa100f9a073704473a911109310e0eabba4895ce07fc30724a4c511712e1a58e4ac9c6653965cef7009c58b53c61c62f7661d03a341c4890cbdfc7e6f24348d83619250b5b92703a43cd3c93ba9389d3507154c3d919cfd4b77d9ad90ade8f2e70213010001	\\x2091abf464744cf571ef6d03d4f4fbca7ef9328e97868d43e53497e74aca136a81d152c421a1031fea73f2f75e5773b4f92b46e5e7e18e3b6bc79773512cbd0e	1661705827000000	1662310627000000	1725382627000000	1819990627000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
70	\\x9f74a487540ba61a77a02184f2d92ef875cd1ae23629a2914cf8fdd95a1091e654394877e3aa703e489e6555535603c201fb404aaaaac30126ca8aa8afcc5407	1	0	\\x000000010000000000800003c21d76025f226740d0865a49aa0f44c2d30491f6339d065b9ff8faa19b0bd75ad66bc1b7348fbbbbb24c7ee895f3dbcedf36bdeb4aad0d9b53fcdda53f0c2a1d23904c7324eee12dbeffc29c4ba5624c4f758d436d57f3e7975c1001d9b2de9af0f2065b65b9706d35228999aae6dfd6ea695a5439ca858ec87730c1fb83f1e7010001	\\xbac276cae8167780208cfc74ceec0258d3dcdb8b3c45c6da54347068a2ea03193d217c0e7cb14fe3c358d0432e5e6cc8375b9cb69bb9c238ffaeffa828c4b80c	1685885827000000	1686490627000000	1749562627000000	1844170627000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
71	\\xa4488e5c50e2105c0a42bdbb52d898f18893026ecdf261c2cca5397af53b355191ea75162e0a2a5c348a40d44b2e0f77613ea1bcde94db2381bffc107d303fc6	1	0	\\x000000010000000000800003b49a2672b8e942a260448f7f65c79dc03ac2608bd1f431c133c26e1e6ad1cf7d79a3b67762d116cdcba761c2c5194bcb7446542fb4cf1963f1b82b2ead067c0eb7a913c89d8a4b71f0e0b245a12a883e44f99d2566a054109ebae604a22438fd18fc30cfd1e14e1d936f13e54298a827e7c8867151e8cb91183ce1b7ba792bdb010001	\\xe482f21169caf6a14bccc1695e26ed2f457a1173c354b3065d07b2de2b6cec1c69872e100ae46e0ebf28fb828468917edee336233ba237543521d154ad1c7308	1673191327000000	1673796127000000	1736868127000000	1831476127000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
72	\\xa4081b5da568fe66403d25e904419ef429c495410003fafcf44a8b9c5f56f70a9626137a49af72de740950cf985605a5acfada559f809a4518dc347db2b948d9	1	0	\\x000000010000000000800003a492efd35feebe681c385b09bfe58d2a1c635632cf3fac5c0037b73dc720d5878093fa1fb548e47a13b3416f3998a31738beb237580d504924efe08b8e6e937886c66cfd81d86d435f3fd490c58d5a2e3b18c1672349a0184103c7600630a0f16f1ce24aaec07b2e06d9384f962f8c8a6552b94c9d979dc8c7e6a228d0d2defb010001	\\x601b821b90c4848b37d935dfd0d699c18f8501beddc3c06718b714ea744f16197183e8f488f723a1d038ef9508a6c576b065897112b4c8299c3c02d440a07a0d	1673795827000000	1674400627000000	1737472627000000	1832080627000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
73	\\xa7086dd50210f8e00b138770d33ceb74cc76d004580aef1269d3227c21c29900d5d8bf9998aaedf8e1f6e157a86e30c456ef14146cb17e675a91b309e45e8246	1	0	\\x000000010000000000800003cad23c9de181caae6f40e149af5216903153efc203db5fc15aaebd97f79a55f2154329f8daeb065f690a67445d749e83494e49a8e0c667e5316b7cedd8270f2971789f55604da79ff97e3def7fe48c1cfda67471754977a2eb0ee03c61ae03c9b076bb59c1899794b82df3db089437eb5aa90fe0806a8196e032a324d50ddb29010001	\\xa5012fa3539aff44a2bf4df872306222951ae737e95e158accdd4fdf8e5c2f2edebaba600a995bb0ebd89633bce415aff3a2d9ac33394a10a557b23ae735490d	1676818327000000	1677423127000000	1740495127000000	1835103127000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
74	\\xa7cc3766204fd7729b38190f31f442605ca8155bfcff3092b45f17de53ca1730d0dbd00f4f36397499724e40fd90fa3a17f20e007a0892212acf4ead66564893	1	0	\\x000000010000000000800003c0c3f0d1756a7c3c065c05974fb308a8b2fb54225e4b6787a97e3132c841687b934859b2eb2b2a4fb880042a924b6e99a1643a9e3621418b24f37637a60211ab966dd3a02f7c071f15b2e0223283c932b02fbabad4e4ae4cfd345c28779d8db65ebd84b4424e5b149a7556e3de06e157c7199a934fbdfc3aa00c811792a17fb9010001	\\xa68aa62df1feeaf1539b9e403eed735baa5ae7c284b09f065f80e17a5a122f91c05d6bd3ff898b07fd04c637f70e7f02f8fb4db179143b1964fcc1e7b17d3f04	1680445327000000	1681050127000000	1744122127000000	1838730127000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
75	\\xaca08f48b7c344014db7a185fa929f29dd1b7dd1bd7ca67a784cacafceb3ac9b50b610e64c69d856140dafbd6284d56ef44a9ff1caec62838119bca472748918	1	0	\\x000000010000000000800003a7efdd7782bc67d3bfcd54f168b94f32683acded4f89ed95d825d0b38dba3aab0f09e117df6b22b972bfbf2d6b6b36f0b44721beb6d97b05d1c98e982755d0a4e1c1dae3877094c39647c27c3f2aa84eea2fbf194ec371d1307bb463af2edfebf2dfa3982221563032601acd8c18f994b30de49c247c6294af492c1a8da5d4cb010001	\\xf17812cc8e12eabf54d589f3f3879eb58388486cfb8eb9b0a5aee4afca57efd340ed2e649ba1d957826e6223a0cbf1af9842805cea945fc33b5e5e29fd7dd70f	1667750827000000	1668355627000000	1731427627000000	1826035627000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
76	\\xbdd81bfd0a56bde74b646a86cd7eb1be28231bb525f7dbf5f3807062a8fbccb5f471fe69c891ad681ba4ee55d7425a9eb665321f8db6fe0bca319d055ead2bf1	1	0	\\x000000010000000000800003d2345c28f94807631040dd512f9c0a96c220d5237f287e23bf50d84847117ed2ea879d06f324019977a5a0ee371c89318abee431cdf87de0bff45746fd6825a040437c17df62f8dca38ec93000a029ecf9a7922ef2e1c03ac4e84400f70f1b0ef1e1fc532534e3c3c0ce4e93780de47b00d470a9292f104634b3d8b1805c2d59010001	\\x47ab48ac5ca39ff5ee4fc7adde58e29b166cac37b8ecb844260489a724143b803d5e8ea710ced4a96d7cf3d503cc833e21c5df17ca01fc26ccd3bb5d97f89b07	1687699327000000	1688304127000000	1751376127000000	1845984127000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
77	\\xbf2c92640c7debd8e7569c6e6b33aab8306d2809a40484f57f70510744455a3f400919c5b1effdaa8c6ca7e8cc6bd29ef098fa8bbaef110aacb654bd2b7db3c4	1	0	\\x000000010000000000800003c0c36aaa2a249314860bed697d2d134f45e7356c6cea4b4076f9635031842017b3b06191ea5ff6924e684e49fa00aa311571f44a485e91a99048ca5db132cbf3c6c90002d3d77acfb08d5068755ee1298bdd96482049792b35e58a5dd5f46ed2fb39035175dc66cc63ff9f71c097df4a5e3c2c76fbc1dedb4b2fc8c7f7458305010001	\\xd3ed9eb8163324e0aa3af845a6be4bdedcd97539cdd36eb252e854de163485ecf6bc6a49e73a0b18e274385834177ebc5e35d529295372d4ec916ba4cd01860c	1679840827000000	1680445627000000	1743517627000000	1838125627000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
78	\\xc0a47c56599a9c4c7d63f9d0074c0ae5d9aac8820537fb01c16877fc554a048a4f23b2ed49fc7ff984dc47422ce7a99f99015d73e869a2777c799d72c2c8e77e	1	0	\\x000000010000000000800003cada43065bd0de0dc8d553d8d08cd99066df889ca4d42ac96122961116f8b89160b4bd48c46141df19f3c032ce2af12017e465d5de4fb3f17d089948c6741923055f2b3288cae2cd582ba9551ec0e91f4b6044f75c4c9d606db58ba162ef29c71d2fcf961ac9e379383ead5271b4e55b9e401a720e4da8351365ac3ebff743d9010001	\\xfdc0ee6bdf6eb3174a50bc7ac8a680b90eae3be0a136732e5fb4dd540f4de88c75daa321a782c29962d1a6de074d85e534e444a737ccb72104b4191c622cf900	1661705827000000	1662310627000000	1725382627000000	1819990627000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
79	\\xc0f8b763fe352ffa334201aef3c14cdbbae91950492f24cf7faeb776fad0ef61d9f691a249e00817464f748f59c0c7c2bc2d1bafa05a948e4243de3736dd0819	1	0	\\x000000010000000000800003e842b27ff06fd63edcf63773e15d66382033dc3112e062b51d53c2cf685b4823d643b6b505f530a0d3dae683a0987bf3fb20454ce2b771bce37b02128502c5c9457b302c2d8d02e850721607b0004683c7fa88b6443ee2b0b5aca9ceeda486ceeaafd8a36426f70f8cc7d29abf052816687e004df795e2c87997564a305cb1f1010001	\\x5d5f8adff4cbb095d4f9355d4dc14cb9505f874b0fc3851d53f3d41d66f731eadc2920fd7cd1e3ade8da344893a7713bee647f878cbdc5645d39c894fdde1e09	1683467827000000	1684072627000000	1747144627000000	1841752627000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
80	\\xc1d05ca34815c624f9517fd136a8e62ba5ba923b308f6cde6346ca1c764e138a373974334e923eee6b303d7d4b5c646c0a8c2305d549e81211a7cb4ff249bbbc	1	0	\\x000000010000000000800003ac3cedabc900d94a47b9a2c0b95eecfbe74e8e24e3b77491cb3c7f928ea00194358363587f1a4c8ff2a5dd4b3a1c9bb7ed32b871266d35e69befe8dfdd8666a6f9d83279d0de4cc157f42ba3bc393d89d4803affadee5afad179c1ad64e84ae7c1adbf57aa79044825537fe49e0c5020db8d22fbb2ac2a3321f1bd653ba21bb7010001	\\xf83c29bed08580bf8fe5b17734ed51e6e4fe83cf3b46a9fab16eb8b75e2298fef2ed71ba08d92192d30b251dc4f7a80d678f185dcd5dfc06def69de85aef1703	1676818327000000	1677423127000000	1740495127000000	1835103127000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
81	\\xc2b4b0887108a602766ae213727dd8b1be8ec757a321d1f8e201defe5e1ba59e2ffb0e12bb49eae7b1cfe16932807c8372c1360078a2b992d0897ed68d9c2f42	1	0	\\x000000010000000000800003ba47d115fcecb80b5db57a9313b7f6b8af28344a381a84b3fedc261da33a6582e14ceb0f7bcae4777370b8eafafcb5248eefba82efebfd0c921322194e8b225a3d4b07e6f7e13ec53503744b0d2a169ec87357338b54cedf204d93bce9d1ec66b915b452c49b47ee65934edb24dbf4ffbf0dca1940ff5d90bce8f4903ac1cebd010001	\\xa8a1eadbc0969fb8da6445dd30fc553b50070210a0462569b89f17c6560efb3436a829d0a32e1ae54ab64485a4a24f7a5d33e024e9568194790e6df21003b70b	1691930827000000	1692535627000000	1755607627000000	1850215627000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
82	\\xc26cf30617f47b2d04edf9d1b790a86850941a9337b573a938e0e6768a5987339e959dfde5c94ee7a644139f14fd852a68970f3a7dce9a740c7529e1b5ddcc35	1	0	\\x000000010000000000800003ae1bc582ea8fcfe51b63f1a0789a9ba5b357c5926aa80bd7a35a77c3e28aca040a1571397ef36a2272297ec860946e4355bced18faa82df98b41d0ecd50eed4264670f873abd25754e3161b8c2b2393f18740c7a461865348c416494ec553d45a5638764a6ccfdd92705b48188c28b111ea9443653080a2c80aa846cf7cec88b010001	\\x484c1a77964d3d430fcb235c48264f80dcd3559e7b47950697e74771088f1e44d926051422d0630e91b8eb13aff57bb37b7a91b22f6280d64c5060f04d318a0a	1662914827000000	1663519627000000	1726591627000000	1821199627000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
83	\\xc350be86ee523855574ec3e266e5669065f98ae70832f1531adb4f1c9d9e29d82bc10ccde83587f0f852f9f762c70807d10435d389818e44f2fbf1e81dfe8aab	1	0	\\x000000010000000000800003cbfd78fddfe58e3c5c9d89da91386ea44abe0575929932e358b66c1c141ae50df5a6ac3e2eb1dcd3145e8f18ed22b9c8ea5e70c7ed50c8e8eff40c2b79880d19e5c0d0d13bf9f7a12e95ff3c48211a538b33cd216bd1ac3723e2ee929872fc7e8ecdaa96d6285e66e760d508beed23608d193f8d238698f47db3ddd9b52d7e89010001	\\x362345c428e555a7ce764672b83cd495a4910b624d85f14d92d4782ec931d867b225b98124c60af075da41e4f6e7b94c528570574dcb4850361eee88fa23ce0d	1664123827000000	1664728627000000	1727800627000000	1822408627000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
84	\\xc660f91ba09a297d783ff1252df3341d06081a53c76fe79c8969de059f55744e3a5f1fe4642a69a5e240a0f9b417a326aacb3e825c1ca79a88e038b865d4bacd	1	0	\\x000000010000000000800003a6c2973651daf91befd44a8e490b1998fac87b8aa7d14d4075ce6b9f312a9929988596d11a2f94541fe7af013228e9221c25a93820362749680d7ce7a7a3401b2bd4968d221f20ff7848a186b37e1c56b7b5a547e7dd2a57f5e1359e361ec6a19150d0f202eac143142bda60189d0ed0fb016e914692b02f8718272f35dc340d010001	\\x3e4cceb1b6d78a514c0dd2fbd8e95e72bb0911ce8981f66f77edaecd73133ed65e741746039c2acf0066598e0bbafff6b6104ad1684329f0b8134cf9e19d9e07	1677422827000000	1678027627000000	1741099627000000	1835707627000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
85	\\xc6b8026a548ca8f6eea80d443cf43e3981584f96cf15e469efbca8f332d1be0b087abcc2b6a226058cd4dba8a3786943bca88d90e9a18eacb6b0796ee406bac4	1	0	\\x000000010000000000800003aaafc76f5ecec48baca33f4de66ffdf066d528feb7f6bd1b7931e700b009d1227797343f07d616340b95a0621ea4adb1f4f1523f51a73473f28c45e84b4686844f464b947be406a22c291a5cfa4793b62d80bc3864643992819d2886b661a86e0992b2e9757744407a1d1a1a8822c2ef747b51099e1dd33ee0fb1a0da2d1a443010001	\\xc0930b5b4fa2085de862b6a9d2cbf8ac73c319b783a1b994e61be5c2a0a23685550d8d47bd6b325cbeb9e6350974823c3a46162700b4f2377dc228f94b963e0c	1663519327000000	1664124127000000	1727196127000000	1821804127000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
86	\\xc6bcbc0062f19f8df535bf59c76f41138b8c051f485b84afcc25c5ea45a44c61a409dcbe69e07b5fb0bf4c3dd39813552fe6432909ee51d4957cca69a72a7be8	1	0	\\x000000010000000000800003d195be098cc3b174a31cf8292d63eed4608266045d0afba3a9c46bb8c5e833353fdec4fdea1d777799449ae3bd0a7331d77d9691c1083562b7d91401205a39c9c25a0d6d227dc1fc35fbd3180520cea6c769aa61e0a4097964244f659b8bb10a20c29fbb796851bf495460823112649cd36f6473e08ffe1c287ce60987b16cd5010001	\\xcc9cf44b7491e9e79bf516370e1db451748ccea65e2b48b4db359a771f51a293c50e82b97502a0284615a6912895f8952a29c64f48dd9d735b81f15144de4100	1664123827000000	1664728627000000	1727800627000000	1822408627000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
87	\\xc8a4f33ed5d1142054d00dff1484a5e16a2bcd4b023da355d51845c7e9432a979a36258cec265517953309bf63c304a1309e4da53cc6af5d73344026dfa54ef9	1	0	\\x000000010000000000800003b5cefd1b2f7ef104bfb77ea807995766423566fa2f3cc20f15940da914c2c7344d4743eb0c8d9b69b56911f51c59f4d850f01ffbd9539c7b274bcbc721d1dd8d746b92a4139ed0a5e7d3882a2837a85881c56adbebff5684b11a435b048e6c3e8b3b20c632c9dc24cb60fad54fa0fb89289f36c36be16c1d2e14cf3a0afdebe9010001	\\xdfe35ecf6b5f09baf06f63b6487152ae1ca274f1af14db209e5fe8873e22ba5f62d3a89df8dfca85baca1588157f54ee5ba8599176fa6c095e32946ca9f38406	1664123827000000	1664728627000000	1727800627000000	1822408627000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
88	\\xcaac8d32d86d0ee4398caf799e2ee2e4a97941caadb6c1db596940c40017ce45f5b8df3a78bffa6a8312776bac7ce8e1d20a7a3fb7471eb541f1c6f482957e42	1	0	\\x000000010000000000800003a7c7932acb9d15e3e9739ede93ae7361bf89d99da514609fc3f4543f1a638acc5a6bbe9dc5f8321b6d37a59501111f01387a7d358186f7e7e48b02715c1d4e102d55a84eed616e4f1fc2a295c7107bad90488e98bf6127b03fb08c40f1ed86742a987a59daf0e1c40f5ed023ce81e85d4cd4aeedba72f2820ecfbf5456a9e35b010001	\\xd9fd6f2537fada458d28d80c85494b76826cdd4d2122f2a7d0467e8b8e79c3a6d7a0d6b168249f0e9a65a51ced19bea9faf0b3371aedbd7262a5083c0ad5af0d	1675609327000000	1676214127000000	1739286127000000	1833894127000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
89	\\xd0a425ca58d54d697433ba9562911d951afab3faa0a18214cf5d46581732cc367e3a5017af2fdd4dd00078781c9b7ba1a2abd17766086dbe85c29667eb00ea58	1	0	\\x000000010000000000800003a36b8b764e5be9eac67b0c1b337e3ffab3997500208f4b80ebc9c24153f5e77d9c1139af390c72be68ebfdf4623f2891d5b2819421f04809776c4ac67b5cda46fa966d95b50c4e5d439d589cbb71a0b6304bd627bdad6c7ff30b999969e9897d8609f14e680e7b5327dfb947190b69702e942a022c608a097c67c45b5941ba77010001	\\xb2668dd046876efa305a227fd28343331252d0b44aae4d53a6f09751ed909142bcaa5da78b55def7aea35e19d2f31fbe25febefb4ef7d737161f3d68b0d0770d	1678027327000000	1678632127000000	1741704127000000	1836312127000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
90	\\xd2cccd49dc9911ccc0156ba2ca67bda4fffd508c3c4e83ee7d52501c22ade9a51a76bdf6b3d67b856712ab460f80fae4907274563b00a014ce08729ae8686637	1	0	\\x000000010000000000800003ca6abe48aed5eafcd3153317063b66beae2294789696f8d59fc0aa2126b1c3d835c9dc451341b357fdccd4f72da79d7f801fd9b018c96bf636c39341c0580963537616f87fa43f4cc6d089f726954ce77533a3dc903ee0e8a394d23c29a760bd3dfb378ed386d919b980f82a6c16efa9a548ef4e18f8bc6c3f67c85a5dfb1fa7010001	\\xf7da9356ec13119da79bcf4d3c39dbe0d0321ac85f843f90d3bad27ef70a5bdf6316436aa20da6d4a67a20579b0531cf31000072bf7068c13e2d14213a0ddd04	1691930827000000	1692535627000000	1755607627000000	1850215627000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
91	\\xd28c96a1752b730eb0f418fd670d96040118fb58bf269582441951098b421c6d1c766abf3b4763f8027a942ed405bd02c5473e08bb0c264a69cce1a916b608ef	1	0	\\x000000010000000000800003a0fe618c7f43a08b9e29b7cbff674aa46d8d2d87d755df13f65e2ea9f3a06ac5a66158442c3f10b3eddda0dfe2408916642a660f20deb325e64c46d6813bfc24c91fe137094f6dae460285f3d64e0cf4c1e0ef28d838339723f68debb8ad836aad556795ad3965ae95253677b7b49fb02aa525bed73377b08e47af3c9495cf8b010001	\\xebec759843d4ada1d1f2492b4d5b515f678c7e4613b213a2abab0a27aed9350332985fea408ec06553714d755a374ca8152135b99b6d6874be7d09f0fbb5620a	1682863327000000	1683468127000000	1746540127000000	1841148127000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
92	\\xd9005ff1c81803d227c0174c23a4102bbe20aed6bee11f54cdda66cf0f54baa2d0fac3bc4308802f06b16222cb6bd134778a30c6956414b869c873de7cd133e4	1	0	\\x000000010000000000800003bb6a85225e8b8a5bd4bde268a052783c4b12780abce56d8a35f78c89d79e38d8eafb441b1bc516a448fa829ea1e7d22745d8b3ce95ec4f777bbd5a9ea3bb16db8f65ec6f1e2ef261b14c2190d564377ea955c73b7dc2f1bce195808855f109810dbf4e1afba65b320aadb82a0ffcd8d72f840eabc1bc0c7b7ee4d1402c132489010001	\\xb09e35d49da7c42d45a2c82c7e6fa179b8ee72044cbf61aba952a6108d690fe51ab51107231f3a542bcb8ccf0628cf0115df03e6d7ce7f1e674e149c8dd66c02	1687094827000000	1687699627000000	1750771627000000	1845379627000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
93	\\xd9347ea226566a3784b5a5391aa9dc073582af8bfabc0bcac1c432fa0c914f210d11b59b0ce21d04def4134002c840fbe5c62d0f16b1a35eaffd785e1840c0ff	1	0	\\x000000010000000000800003b0e8a44bada84dc38cfbe754b9f23035a9126ae216853ccc8e658222aaf67e24756b9cc76514bcc28783078f74d628924b18d90cf25a0ae6d42f5cd379325caf142493e2a3e433bcb123039ee021fcf45763f730eccc4d1f9b70cde90e0da8d76c0d86cace995e1f28ac70a5bb1db5a832a29d0db6ebdc731a2dc364b887420d010001	\\x440cebad172803ce36673e0ac8a278c70fa4c66de5810dde387d0f1dd7da35a37de6cd09cbd4d47921c63d9b7846e27de783f5274894d4a3f6d8d915fbf0c300	1679840827000000	1680445627000000	1743517627000000	1838125627000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
94	\\xdb0c04047f80b39911c1aa95b173603dff0625ce3e83448bea7c915f441d7a1633f7018c30600884a1c2bb8b42aae059663abd4f4ee507b9bde30c800888f445	1	0	\\x000000010000000000800003e37cfccf7a60e4176ef1c90acc2e1ff5dbbe8a1b1ec278d0fb2a91d6e31d3366312cf3df9b244e61e017d25989274bf0e387e622baa2e88d6f465b3152d26a11200a77e53bb3b5f01786abbef7936f9790c8da77b9d028e9011fc7f9d6fd779641f4e64889dfe521bf493d74b68254cf8dffe00ea31ef735c813a94f8878f6eb010001	\\x09e400d72207e6033f221698d14f3dd9c81e41637a8f2778e81736ae56969ba02bb525640cb30dcb52c86c0db650f5a0b1e3a5a2b969b9f8b89914105707cb0c	1672586827000000	1673191627000000	1736263627000000	1830871627000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
95	\\xdc04cf4a2e51ebdd4c4e9e2ed88427206368c1ad5dbd888205b8543d7ca3805763e9d892c0135135f6808e922fd48dc1ccf22119347526c261c47bbbf159b7e2	1	0	\\x000000010000000000800003b31cbe6de027525ececdc59e060a5728ef510a5d3b82e0988f93bc3f0f252b1104f4ccf9a6371b7fff9df784f3d11c05ca19e423005d093e6e6d85c347fa750c7e8a23f86d76f7cc9b25ad9806da88f8f5b8ff8af2bb6aa65b693ccdd5ec328a54926cec505806a0a25903e680a295f2e6c3f3b955b7953a5fd985894f4cd13f010001	\\x39cb0b8ecbd1158306890f6acce69492fc2ec8b5110ae5aa37f077bb9b82fb6cb369e3acccb88d6eb89766741c76ee0254b8470330fdc78fc9a4600a1e7ffc0c	1684676827000000	1685281627000000	1748353627000000	1842961627000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
96	\\xdd64cf3d0ebb039ec236727a7bd45e28b43dd5a7d9d30f353895dd9e484d6e6fc1e45e3143c10ccbb7be6fb710fdfd74744e1146aec0334d65f67262b4028a97	1	0	\\x000000010000000000800003c00ff004e22b77343503c4b0204063b94f502f4afc86f214d7548522f4043a2aa85c39354711a45b9b9573045375adccdc50989067be2edd598acf3ca5016b45b467cc7aaef161e6939bd2b78a66d5a747deb598a0bf987ade530fc26dec22f11ceeee7a280feddd241f3e72bad9da5bd42d93b86bc49e017c9487e94c806c79010001	\\x55f14dba62bca002ae49f8111a097cd50c4f69c0be27f1c1600844fc3f98634a14ce74dda47dd5b90b39fda68a4c645b3f18a67ecc30a2d8cc96322914f57d0c	1664123827000000	1664728627000000	1727800627000000	1822408627000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
97	\\xdfe8e49861fdd09f86d9d1429dd36a8657d6b7dde35574e019e87a0c815367cf7b123a026bef2612785c67fbf8fadcb678db5fac8e82d45fecbf21059fa75da3	1	0	\\x0000000100000000008000039bba0eb864c479102129290f09e2474402d9d37179d2f4f1594a05cb57830b8e2793165ff66854d9e88cb29847ef65ccf7a38a018093dd31ce6b80e01c395ef78b70a562c78c467544758df4ffa011cc0265ae20ba5add2e65b3d65e772c79226e001556301400c734212bf9e1e117a6ba3daf1bb376a233e08bc1eff4730c7d010001	\\xb7560f65b16ebafa73d3f8d819fa80ce929d12a75bd86880658a437c83f0945463f1bf4fbee051330c7d1fbeaf3e35bc17f344124d392b6f329c71f754eb6208	1668355327000000	1668960127000000	1732032127000000	1826640127000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
98	\\xe03867ea660d7acf7a713a83755440383bb71ebb92c510080060bf20c1c06b5e46fa50c475792dea7e47250087754850d37b80375fc34889d59a7a59dcd8c691	1	0	\\x000000010000000000800003df8ce50be9aed06827840019030e7bb3207176e53c3ddb64b9532415b0ad66a724171d2778acd143c4aa9ca59d761cd050ae9652578e69be3b241cb089d6862fdcaeaaa982f4a4ff9be9d7e4212323043fd263a8ac10b55a4f3d09fc2671a58851fc1e2e0521f84c878038ed542ccc0c2beebe0c59028adaa64e07bb46b28cc1010001	\\x2c98167196f3938864b1c71df0a8add75742b1f63266ff6aeb5484f87482502dd6ee90ae96d91eb8ee07a3a6c6da3b06fe3deada164d5f2f54d0cfa9634f070d	1665937327000000	1666542127000000	1729614127000000	1824222127000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
99	\\xe204ffba38255bf668c6622585765b138de3a2c3f8b729ac25650c2962ce8432d83904ff85dcde12777c1de6a51d11b30ea586b92458ea3c405cdbf613f74beb	1	0	\\x000000010000000000800003b7367ce6519a7301065aa9c7d8361cc8dc03a74b9eb00d9bf42bc6ab3261ab5da664042bef116bab5dca5a7e86cefb63cedcc91749215c632ff275f69296de4a61f99c5c4f73738d606cdcff6309effe5bfab86d4abafe30bdb59f9391038e0e2f1684b0469c46eac85641a1a7cab295b062de7e76a037e46efd1e18988913ef010001	\\x71ba84f5bb3a22a137c2e08a874c9a2118277f18595120eb2be218e2554c06842a7f0f132706c3cf6d2eb86d2c611050ff9578973437d0d9f7e328ceecc6a704	1662310327000000	1662915127000000	1725987127000000	1820595127000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
100	\\xe484b5b6f7c6354d9208fc69889babb5345869045108d28c7d2b6c9f5d2bbfb016c136bb04143c3e05a98080cb1cf96f7484d0391ec84a2eb3043098438bb6b9	1	0	\\x000000010000000000800003a46f90c6d41c42266acc2d36a02336816063c1455a846c3f6d5565586f0e209ce7e979f01da376383041d49ead5358fb55ddeb0ffa03f9d333fdff9cafeecfa7753a3f94984face186008daf2b6444bc39e82548472ef6c055c75ec1706212d62c68c657aff3f90c5cce4c3a4e55ac33ad8f5a13355582672b5ea4e75a648631010001	\\xf02c47c89c0010fb49109d58b639815b8f8a3bf8a4e8c1a3a8edc1228f782afdfb67841f1d50cce641469db89bd65c7af265c0b24f93224b09168fa033c5fc0e	1673795827000000	1674400627000000	1737472627000000	1832080627000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
101	\\xe78002c6efb87420a2131dd937bf0b94c6add3c1acd783f3d681558db689e81faf7797df62d2968be22df426d3d00509254ecd0bc4284e650d226db3c3898e49	1	0	\\x000000010000000000800003b4558619054eaa081fe17b0fa3abc5c7dd4aecaf84627cf5b66535dc0a2c3807fe426659224248ed9e416ce79d6a6d7f5502d923b573390a82bd0dfd13c9eb9215c903a415c68f8f00e7104ea58aa4c04b38bbb6ce19e1689208ab7495cba3aa5b28b51c4210a01b61fa06fcd111d4cf8279a33b0b4eb5e7c8a6ed63208a3077010001	\\x3f727bf09ee9456e1a646d570418b7eb50d32981ed91ef6ff94550df9a1ce03103754ff47534cc05a1a773e092e5b9ba3e6c5c552b022372cdb11f49fed8c906	1674400327000000	1675005127000000	1738077127000000	1832685127000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
102	\\xe94cee2e1de782d3b98af367c78092888f8d70ac3abaf80dea9e1ef7943c3ac531b522a2543b8d328b76639edc5e58babd49347fd44cb875cc7ac2dc13cdd90f	1	0	\\x000000010000000000800003cb2993bfcac45672fbbb654602a479455e57f34e329e1a196d0109b7c17e30658667539f91dfad561f417d03a410cf07ba097b55ac3b4db35a13f6da80e1752507be8d132902d1c17fac2ab312818f0eec26953de7bcf185a295212b5919f316261a3be1a5c68ffc9b741a7d9ce9e530e1201822e6cb8b773ae2e169869ad30f010001	\\x9a8dadb680a5defd9d00356a44c4969d2736f386060587a6a40a46b2ad5e5b214b98e60c00dfbab41a1719b9e0d81999ae5521ffd1a6691de16efaaaaae4590d	1668355327000000	1668960127000000	1732032127000000	1826640127000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
103	\\xef386faf2887c4e0b71721a18a3925502e3f0b1435df780eb08d5b71520e7d84e9adc196b430decc5b61cdbb78a40d44440136fc5e49750e6a554f3039ff7c09	1	0	\\x000000010000000000800003bccc0d7f483fbd91981e5c579078f13ee6598a3209b71e249b6f550c9fd442649b9485564fe4b435022e9f1e458cceffcd2971a4830b5ce5bc16f0a19618494227e74e463b35a5b8a166e4678f760e091074ecbfd4b07ae1e6e8c399f1d68fc874b226760dca6c89f5a1755615c96c25b6c8767fa54bc0edaf1e93806d2ed005010001	\\x704ed401b14bdd268681a50d64cf58ed2b1115ca6a2bcc989977135427617c4483764c6dea2d978c843e7fe548fd51d80f41d8deda4cc079a36645f2517b4608	1688303827000000	1688908627000000	1751980627000000	1846588627000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
104	\\xf008eef4f599ddbb8801fb80c5439caf4788b269bb288208acb1902279441d56fe8ba96ece4e1aa498ecf676f138c3a7b1743a1bb46221582ab21adf66a1a215	1	0	\\x000000010000000000800003d93394a5a9c0d98dbc02460a8ec857f187808d59e0c421612a8daabebab3463d638addbecb761e2ca9d4d984d9da58540315028003beaa4ce56e2ad8614cc58462fe1ec301f73b04d9368c422b3bef7c13de943d7754d94e4cec775155d83942774e34a12015f9ade4e774f7aff19963145578759eb3fdf36ed5fd92ae8f2423010001	\\xb3fec6380c6b266278b93385197646a2c6428d3663691fb966c307d6bd872c357d53d5da585ad793b7e90fc3e96459c9248d3dd113eafdac3e029e320db6ac0d	1685885827000000	1686490627000000	1749562627000000	1844170627000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
105	\\xf3ecaae2ba075564a9b8c281ccd0df9e1cfa3340d58afd0d758398e4fef2ae2aa02539fd7fc30c33d3a233188eca1c1ec1845d3278d51a317ab1dbc1642849b7	1	0	\\x000000010000000000800003d63b8a4278849b4382f9ca75350f9c77d9d3934107777f75aeec64d21a2d9292dd313df7f4d14ffdd94484a48771614cc7347a4150e0ba1c555f423c087ad34f428f627987f067e55a09aac79cf5794271c183c7ef7e976f893d1f4cd772ee3887f8c4bb1c1f5afc48b2b9a0220ad05b0d60c36c4ca4c222f4a956ccecea5317010001	\\x605e6f2a3c28c31b99fa42b941ce49a5bd6176210663158e350b6cd1095c364fac545ffd31720477cfe81ccf3c2d54de238527c15f6b2d447cc43d3cca39d20b	1677422827000000	1678027627000000	1741099627000000	1835707627000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
106	\\xfd68bd779234fd7d41951e40d8adb82eb8223bb2b2d917358e4fe8a63da910608a33fa879b956fa39f6b4e2474b486fafdfe546ac7ab53b920dfd6ba68658e81	1	0	\\x000000010000000000800003cba31c70ab75cbfde992834a522208466ef84e741fa4fbece4823b68e128f33976000eae8c3ee51491dda0f588f28be94e35a7420054988377c12277740251f6da9fd22a2bf368f53703b228c90ec6c552376422cc0497735a3f54b8e717eb588c45a88e85170a34c0d8dcbe0748d61609c32b84b21113648ba8251bd3a29b75010001	\\x31eaf6dc923a959f1730388cabe3a46471d734756c1de6b3cb927c6e6fe72c3db827e22370d961f2d3c07f911f7e667b2c9cfcfa38a8e08bd944483999a0ce0f	1686490327000000	1687095127000000	1750167127000000	1844775127000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
107	\\xfdd4f1d8b9b385f81c47bf0fecacd1798095017d5241bb751ab1453322928f137c454706fa553e68686c5dc803353f6ee58791f25597e6d9e3e486f113c05fc0	1	0	\\x000000010000000000800003b327b316c2934d2ac5d9849ec3592fe53b9f329206a62a576820ea05173d77c30b48c2af7bd49e148e973ac5064ded25d65b40e066a19d57bc6ab45da9cb86866a878fe996c9b9f4a2cf052695a27d4ddd898c72485b25ce974848db673008d51ee782ead2d156978918bbbe8cb2d80228816a36db91c55579593b546c1197d3010001	\\xa25811a3fda94a4be1c945b170e6429b99d3eda7a930d85cf8b3f18a40489bca0956ce565b064c0fe56f75400ae1dd9de83dc938ed5e0f4afc69e83d7805020f	1671377827000000	1671982627000000	1735054627000000	1829662627000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
108	\\x014daa2f5fd49d47b6fb5bc44ffd47ee6ba66bda612099fdb20673b6c6fac7ff7b04d7f0b589f5137c2b5b2ced34202edf79cb5a1bbfe4263793fff7a79fea55	1	0	\\x000000010000000000800003b15216534fe35bec7a70648e6f1409bd246d6183d48e5da6aff65f6313a38c10956ea3bc505c8ce9cf99bdcf5d9a37f4b12ded0a4830c111a1ee8aa38fd3065a4af86501d48c352e95326c464d28c9318a25f0b964a8e114eaa5255f6c7e50313d586bcacc4b3b7d7b8ea0cd82f5a4145f0a1a3e4ddf8636ef4eb0bc62a15f39010001	\\xf6ddf764ad84be208d9777159e243c5455443f0401c418f291792c4b78dd657aabc9c341bcbec1f8830200f982e8fc7c147ed4a3fc212d257417b5be73d60206	1675609327000000	1676214127000000	1739286127000000	1833894127000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
109	\\x0169f7921c0444b361601f75e883100a875e80510c0f8b3319cd41873e2a0c7657090fa70b77d7b39d040007c6c631a1878064356278202568d2d4f98ce5e419	1	0	\\x0000000100000000008000039982b98915016d8e0700e1f3032461bb0ab61295e68e1eaef1e3102bc54335baf0d5be03923cb9603603958f675236a69aceb698a766df2b9dd95f383477f3b98a0df3b938407ee8464d393521c0cb8ca9058f35a17209ad528373a156827cb24e084f84520f5612bcd226e4a5c5793e9951edd83fff8e29f5cddc4a699df0c1010001	\\x0d9fc7e84a972497d121ec5b8cdd4e143c3970faf0a9502852b3e259259c669fa747a855245d0be3978ceb180098d30776db0e6032d3519b5f1d2234b086a10e	1678027327000000	1678632127000000	1741704127000000	1836312127000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
110	\\x029920f56c7a7ee6479bb2abffc882b82e53fad94a997d589bd993a379881dbdd6350adcc016fab781df8a506ed2380df823933e1ef1b0bcf117eeabe44623ae	1	0	\\x000000010000000000800003d7c9708ef26fe849d7fb34374ce00f34ef157c343bdcad14f230a9642fdee7f95d0f50fc7345262f5644d845c972cc53b3a21bd3108a9d2db9ecc884c3eb5d248f2ef27f9fa8863e82efcf70c2490fd498c94cc8d6c61ed55f413e097105096cc95151f6015ab456d583c63ba58d026e3f2c678d50dd00dcac28e6aa5dc62b3d010001	\\x26b731a0e5d84c66a9c25ce6e98e0c9a960deb08dbf5ef0c6aaf43b61675c0a2827d4559f72e0357bf28d02cb00293dddda99f251330b96a977aba328bd8c806	1689512827000000	1690117627000000	1753189627000000	1847797627000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
111	\\x0361c977255d6b05db60b5ea8b92bac5042d445270686306ac3fd67c6321bc4aec45043d81377136bd70d3cd721a72fde780b07d37c053878109baf56657cbe7	1	0	\\x000000010000000000800003c5bca515c45dba297cc88641fd3196178fbc4be27e5fb92175cda3afcc9cf3dd780ed79c5eea764367a7fb408ef33a5db3a892bd3d0bb2b356a7fabbfa0d8b026fd84787890c1281c2a286d7a87f5dda83f6542851237875808938cbce11f7ab82373775b74864a52f5ed1074ba35553bf51544b92891b31805684bf085ba553010001	\\xe98cacb910dc485a17df208c285414036e307dbb3cc3355207268812fb86d5f6f132a5d37379419ae45c4e01057c03e76dc568441038541ec32c3b0b3debf50f	1683467827000000	1684072627000000	1747144627000000	1841752627000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
112	\\x051517c6f6ab67aa6138bd1ba7beb04858078f0cf38af5e9d0895c3c9e685467346fe5412506dcb68934073d3fa145670aa3b0c74ad3278dd5d92c5afc959326	1	0	\\x00000001000000000080000399b2afd833d0f05a655f327e3d005b61b0d872f3e8bfe553c999d3f46baad28fc92175c332df9a8f1044e45d2ae2544765fe4cc9944c58ed74dadef1e5291e5a19f942acbaee0c4dbb986de72ef035637e892a743545ca7fc25757ebc663df668a7f354d17b798465cbcef3d2a86ba92d987f1472398ad88fe0d9eee06091cf9010001	\\x075c4afaa03be0731817fbbe20154dd6eed4bc945f7a9f2eb8f5b62d7e0c9c63431725c4d330282581ceb0bebda80fcffaf0bbce397a89103c2b4f91a2b39f0c	1684676827000000	1685281627000000	1748353627000000	1842961627000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
113	\\x06e141294f9088ada04fe47cef24144e72cb779ab148f55b41cb8b38ff96d45e883951fcdbc58ca3ca4a0c917cfcd7e07dd53ff03782af36a43416a671604428	1	0	\\x000000010000000000800003bc9eaba589bdbd90ecbd7601cfc8c3c089b8def6b39fd6420914cb7631bf054981e0d171af41fe0b4f1d59611b644a9820b7fc1c46ceb1c3634c930adb84c9d0e2847d62e399984da5b83e481b819914ed8bf4bb4b95c9e74d8b660300bb017e35a3d67bea82d37740c2368b3f2f519b055a0155156e73541349282129e33195010001	\\x855839abfbfd47aa540e93e8e6a5ba18981c82a8aee95e64f2ec0be3e5a4494bb1e2f1d0e2528bea8fcd218637d41ad54206724f54d4cf5bfd56cba6cff87e01	1675609327000000	1676214127000000	1739286127000000	1833894127000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
114	\\x0791ed3cd363f386d41014f183d3d32401321b1557d2cda55da128c2f0e7498e1f3ae7185840dc3e2be28d996167fb3f53162b54f63c9b986b9eaa270e94697c	1	0	\\x000000010000000000800003ba4711d07d95f8f13e501ddcadca0072ced6aeaef2f6ecc96ce9bfc54f98caef7da40ce005e6c9c0d8bc17fcbef4f1fd4e3959a115188e7fd4d02566dba4894678cad50abc272e242c1d1fc7114791b88ffdf5eb09a4723f8fbb59ca01d9b41f7406de3ece2a46b57989b582e0c38ff9974c27684299af2da46ab663245f58f7010001	\\xb1be786fc15b5ea8be25bbf1a2d5847b30583b32984cc99222b0b00437da9e648bab611d11b840ce58050658b01c781f3061ac5d73c9222d32585c172eebce0e	1668959827000000	1669564627000000	1732636627000000	1827244627000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
115	\\x0ab518048b5aa4852c747d771a517b212d1e1d0ef98f63b9d989517a7a5594d9d184e883fce5787003462c27daa4412ea758fb6d1aabd044bf7f2ca1ec83ed07	1	0	\\x000000010000000000800003c319f4a802e36ec8d65bef4335ff88848d7c6cca1b2747d74d693cbf71b562352af041a84b194574c86757ffcfe679eb4f8867929fe8077cb2fb9cde423c930f91ffb916b46957c81ec2fcf759babf94406258d9edd619a7051d2fac90bab2b9d4954cfe3749f1dfdad3c95ca47071524ace80c9b2e53d7fdaa23700893d354d010001	\\x4fc9c31a6c73ed749235a73d34f98e5c2d35e06ec4397063e67994d13cc5641e4e735fb019fb2a4ee76fccbced8a36b3cc1f9a488054dcec14334db60e479a08	1661705827000000	1662310627000000	1725382627000000	1819990627000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
116	\\x0e09c6894379aad260d220cc4bdb5f9c6d586f6743240d9c0916728541971d746dbb52bf4f129b8f3ed55ee806104f3192de7bc8726b59e0088e476d45e8d135	1	0	\\x000000010000000000800003cb5b53efa370416bd9063690ed2d1465cff21650e339222adbe2ac57c4cecb7a27bb1c5cd7563391a058e0a3b39c7badb16b8bfb1e09d44f62419e43ecce5b3b573b9ed31bb5f9e10456c72bf129b5442056083a4dc1d7c9ede82979682e032145e2568ae005368b93687e95003ea59dac233e437798692d2496a80844dd283f010001	\\x29d216efd87f065d2676f7fa744043a935ca4ead0c42e2287410a8c27dd5871a6e0d3ebb7c32b0f6a23069bbf3909acbff38eb797c727738c85f48cdc2c67503	1671982327000000	1672587127000000	1735659127000000	1830267127000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
117	\\x0e3d8642bbc1a3d67440660ce3fcef08b110e768d4e3ae63e3b56f5f132fc41fa29447676f67bcbc77f726bfb8d25a494314e9ea85c07ae28b11899c4cb6aee4	1	0	\\x000000010000000000800003c38764fc72ddd75a7cd423794774c7a8a248d90036eb2aa58ed5f0914eb181eadcabb2e1c3649110d2ba73accd0425442055eab5ef2231db8e673abaa178c2ae65c74c5ef19097f96719a3da43f242f86d0cbdce28e926b26df9860c2fd6a70de17627394733737b191199e4443353a148d0f9b370797657b8903846b83308fd010001	\\xeab5c0be403f3f834ebb30b0cbf95ae915d4e57bc6e6d3ee302d4e4e4c5ef73186e311d770cecbba08fb14f87f0623619a7e20523ed926818d5bd36822d05407	1684072327000000	1684677127000000	1747749127000000	1842357127000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
118	\\x11fde2bb13b46be630dc2345d7a012267161f53f1b230dde5f408778fd4ab5bc60d6d8dbf00ea1c72531763d85776bee5fcc544192b3cdea2ed84ae55f1186ba	1	0	\\x000000010000000000800003b869bbac350875c6dc06da223d406173567caba754a028987ca72a15bf5b471d3fc3e0f22308817ca52210e0bc0bb3b48aa8d42bca14f6bf6d279cb16f57cc4f4605d82e8b4618a996f7541a2b29318e3190bf5edad6b038d11c84a43b21fc88fa0c6e5ffecbb2ccbeb60b246a58e7212934966638f6f2109191941ceda757f9010001	\\xafe0c6472206ecb5d6a2c0b7c287b29932846f759c15b76c3127ce95098b3249a81c6542215b0ca641d0b3233cf4747c5134f02d8d87759aaaa70080ae55cb03	1681049827000000	1681654627000000	1744726627000000	1839334627000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
119	\\x126d4f27eeb6e7fb833843372df020967c119a4970b61c212d0bc17cbf55889b26b6601c1c46a6405c5c90302926c82832116815191c6cc6857fd65ff92e2174	1	0	\\x000000010000000000800003bc3a83bc4b971d4cdfc1c299b7ea4ebff95ad59c835ee27efabf016e2f508172b2e0b6fc631e24aa55d1676147831c006c475ae42f1cc684cb15d666879fbbf172f1a3d916446cc0e720299234c2e27c74712a474e7b0e8fa695d767adde2678745a369064f2ec4c0d6cd21daa5ed363a78eeb596821f35fbc349eda9ab2e5df010001	\\x190e34ecae7f6b9b6c35fb6fe49cdd4433ff4ed89618150cbc77cd31c890f951f2fb909666ccc771655de690e665b0e411ed0589c90f6eeb3597da8dc725610d	1671377827000000	1671982627000000	1735054627000000	1829662627000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
120	\\x12a900123215039495e8c4cb7665efa0d14fe9ca1ec0abdd5b8a123c34186b8c46d324f66392aef21e6b2898b91693441701ab7c3169830f08347e4746e3b91b	1	0	\\x000000010000000000800003deec2ff0f46280ef42dcb7f10260b53aac6160097aa3e67a097fe983bbfad55c9152e05c3d5a8cbd2a9c7b26222f2263c820b082fef2340ab3b398a82e34d0d66b71d5bb41f3852b52679d28d4cb3d14d27c7e2803659e4965d05e9dd632cacb86e48ab552b2136ededa406ab377acc9a202fc80be4faf0e04d020b577124e1f010001	\\xdb0055c4f36a451b6648cb107192695512419721ed01a8fdbaff4b623e34147d439210ccf49299934607bcf6ea766b6ca0555227e2da336fdd374f58928b1f0d	1679236327000000	1679841127000000	1742913127000000	1837521127000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
121	\\x14bda1447e214545d86bcde1b77af200f0983e8c02bff0c231af4a7ec6b68c2532810a3720925319d83362be7fe72e00d68c379c93717918275c5f7e8d3ef841	1	0	\\x000000010000000000800003d2b5b2790a8d3de9e0eb07a2164ddf286dc80796eb126297de3e2182d01b3369d4c5d48c63d5bd07fa4282a4cd614a13bcbb32826353580396c69b28b37ebcfba09868c7daafcee7ea11b06936ad7c001b9ef25ee1e5da378b7f7bcc6107780c5d91c2addfb7c11561e84156e26570073f57cf05160c56767db0b8110bf07281010001	\\xc1188128f0ae6725190da20419a7c9969114423db9fbfa2faeac1bc47d7c46735c77cc109e65cffb95aca152162680849fb67de105611c186ec8f47386bd4f0c	1679236327000000	1679841127000000	1742913127000000	1837521127000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
122	\\x1629ba7e0e8d1e5dad7372a392860e97a57fc52b8c52f3322a6627391fd0c72fa42e942ec4b17ffdf615f321dac32f80a23a43f70a65263576bff92162af05cd	1	0	\\x000000010000000000800003a515a64f8f32aae6250d308279956e856ac7f10f7b57eba636380302122b9484ae40b0c9716ad1e49f927f993ef9bb508e317737f944a3b4c54865b506fadfa3a3ff798dc865f75cf2875bcfc2bf348af708e19782c33cfdfe63e479427f2758bdb3f5df4aebdfe5d8cbac1009e3ba677fff485c49f49c332b780babf431ebd5010001	\\x2e8c54aae3cdda93ab5cdc7bdd0e8fe4443f533ebe1feaa5d4d2f6c11ec2e729bc51882bdae6f8f5cf081d36d9a295b7121533802e502597c57780c132570800	1673191327000000	1673796127000000	1736868127000000	1831476127000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
123	\\x177181269e2c0e7e96fe3eee27b223cccd02bd66e15e89a549a75bb280fef9aae297f57ef046fa1964a580df4c367febe3f9a650d186c7f82feae32b799e8526	1	0	\\x000000010000000000800003ce2e36112b6d808eb1d2b028e058c04abb479563a500cd3254516a1236e4e2519bde3c672048717e2194ed80921d4a26f1082961defe480791a81acfd8874a42321a665b78e33eb4162f77bc526e0e6153bc85ab954a8ca2af53cee7b500855b142ceeb470ef2d3ad014f6b39ff44e4f5b6c63af3bcebd4ffe1c675feaa0f3c5010001	\\xa7d31cc2aca0f1e4adbcaa7e0d156148aae131b81e24b316344f9ede21c239dc8139a803e4fe4f4e4faead57bec2800207ff9f914abcf62cf43ffee007ae380c	1661705827000000	1662310627000000	1725382627000000	1819990627000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
124	\\x187109130edb60ec431b0d70235fc0cc14ef78011c13d7995d75568b1f60b3ff8a593667bbe88db7ce498837df9b72490202d63ca578708d982a9e5edac2c9cf	1	0	\\x000000010000000000800003c962faf3cc55cf464b9fdb5674e6be689763074dbef0ba3808d2ab553297902def9fba3ba17bdc1176fe22c125839ef140ca5aaffbde384239790ce5ccf117f740298eae01f32ca2a65a44a0d509e8ae8c7bace8378d1346755f69ece0db11654e0235f4c266305fab2f2e59316e6080cf28536c969c8a16e09a03c74dfa381f010001	\\xafbac5f9d13f80bf20ca0d4f0aa806de4180bf0e711a6aca7728f2682d94d56333a61a3fc13b8ad48023dbc582276dbfbd7848674522c9535e6c3aff1b848f0b	1676818327000000	1677423127000000	1740495127000000	1835103127000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
125	\\x1a6945715cfa0e3d10e89f3d28b67121e007506b66491ad840cdb5be10c42b3b3075ebbfd172f41bab96831eb3e1a93b05718705b922c679f5187e84cfd253e6	1	0	\\x000000010000000000800003ec9bd10443c26abb54c1ba9adcc7acb8ac1f65636b42d9082de9e730232e97c39fd195ff2e01ff51dbcde2b06abc0c7b22d18ae927c312661b3de55fe7c4169dc0ccdae1c2804799fd02c4679009b403548636ac90c53a7914636b24cb1c9881c34861d0b0aa0aeb80f1101e43a6c271604cf98e19b75cefd15d18d331625079010001	\\xeaf6559a89431f21453843e02cfb9c0bae619c6ed601065f257a3352a67848c1c324c3510028d3afe96af74b9d29029c7b69ee7b7ef821b543a5647da1a2cb03	1684676827000000	1685281627000000	1748353627000000	1842961627000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
126	\\x1c11b751d030b7b70e17ffd59a3ef3f256fbe6c9ecdcb4f6d134c2db416b20605ee9270891e885df0e8a08f7e0a143780ee35cf0a4412489af88903f1ef59bec	1	0	\\x000000010000000000800003e7e3c32b826b764c99f7b2d131991c3002253caf35aa9493a3427784b3bc31864ad36942be172d65bece0774921c78ed8fb8a60b91478779726abad19f5bd27963c26f0705cba09ddfe6737d8e410dcf1be08b0d288e278062727b380ea1585df5b488d297b2fc4c27742c204ec9a5980a12eed051e05914bc2129dd2e7b6c5d010001	\\x85b5ed9930a1e745c044b52267e59d064028b25904ee8c0929548fc0a3ac7e4d48f50241be09cce3f9b10fd57ff9d3cfc80b3febb186a53984f92ab89dc34a06	1691930827000000	1692535627000000	1755607627000000	1850215627000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
127	\\x1fe508dd73008f1f978130a9b1bc3b7bbcd5c6b83c7ddf191e79a01921cd1dae9ba75db237fbc569372fc42bbedd8e722e524c30af77e6137c1c7913924db5f4	1	0	\\x000000010000000000800003a953da09600b7b4d86bbdaaa87d91070cc83de2a2a2d3a3d9bbcd759cfb3f0ccb9f0e6937ad167bd6552a165965a21fc218dafa87305256d8e776aa132bd6344f7a31b692178e61e641b8778fddbba53f2028b02511e45567e2c18c072c357082c304775d384bdc3f5ab0085059bdddb62131c6e24cc68490d42a79201e69d03010001	\\x2997484dfbda377bde27afa6e264625ec1597164fabfd79ef520627df5a137f1d93a57d981413bc1777b9700ea76d2b5b4b96a4de569b04a49fbfcfa8998d104	1681049827000000	1681654627000000	1744726627000000	1839334627000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
128	\\x2441f6e00f859ef54fbd98d3bc9d7be7fa896a311d89309f4e0bd01143a9a34d5e6e272d54f4b67e2901d5e86b4840ae7cedfd15a3ba7dafb02b9a2a174ce57c	1	0	\\x000000010000000000800003ab7105c4dca47bd1f15e9cccadd8c49a800bdde584a99d5aaa3f7369e8aac04251edd4eee678bd68b0c985054ce319195dc53a15513c72d17c78707bdedf6c5f4f94c25331610d531eb8b950f3bdaecb21910e93d976c6f763b6c5a14328ea5228ed0b6e33575f7816cf3e368161efcf2ef1f17bc6599adf680ccb71c67b249d010001	\\x87baeacb478f0f1e5cf1e7b489e74b14c8de7bb9ed12b33299959cfed5becf7617f856e40dd489a6304081409dac503abf238ca1b04141b3539ed0df7a163702	1688908327000000	1689513127000000	1752585127000000	1847193127000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
129	\\x245123a79645c60524f3ccc40640bdaed315a3c2d2530b8e479c43552c085f6eba416ec78c9457cb62f71128a8b0b676ea88ba0a5cefb799b3369dfa5503e2b8	1	0	\\x000000010000000000800003a09320def029a9dd96e32241e18e6b2ba20312f84ff87f1af8cd0bcdd0be7acd0fc9ca3ea19a0a96ccefe935121bb0129e29d6f0793c75568e1a89429cdf59d35982956b18149145cb4597a5e7ccd278af98b935cd2fe197ab0bb3a523ff82c54eef9da6d9212edb505980425fc0782fbbd1222fcb9339b16812d61d2e69f7dd010001	\\x85369b5be236578a946454b59d4509021c79082b7d6051094f7907aea89bd4f7eedd3cb90a47d89859fb002fe460046a3dd821d77b57f38653259dc8a4db2d00	1680445327000000	1681050127000000	1744122127000000	1838730127000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
130	\\x2c4df889c8699cbaefdc44eb5f77812a2a8da85673b755c55b3a016a30d2c6fe3d2f086b9b4998b1622ace1aa50a218b2ec5ada979c0482a89cdd79caa9cdd28	1	0	\\x000000010000000000800003b399fba61048c28041fceca73edf11429c2efa8deab27044aff4eb1519dc7a3422287f0e1b486d0e23dfef7ab2fb6e936988def190a35f8a5aa5228aebd3a65e31299aff6c9a0c33f730e9ab83e2f7e4abb4b6873b4be5433fda1ec14001e860e654dc80f819894d3052e78ad267a2d271f743a85e8ad168191fa37267d7d81b010001	\\xb5c1801b08673a2e61734912e7fafc66274712baf0dfd543b53913826d426bdbccf077c4f999a25f9807ab9110dff8ca83e33b9d0119d84e534050e14a042a06	1670168827000000	1670773627000000	1733845627000000	1828453627000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
131	\\x2c45d2c4ecce0bad6ae587ab548ee34f1f676d06afb5976714caa360e71a7d5820cabdd057a5540551913219477359ac7ecab0427a9180a0ff7c3936e155dab4	1	0	\\x000000010000000000800003e4b3f4bd1896e0bd98e97aecc2a1f8fd12e601e56d407ed15fdda35cce1a5f645631e67294e407056e2e11ff212cb292b5f82d8cfacf3df23de84d6cc30238a65d9db9d64d7222f987eca91c3f24dbd75e018fc4cb161d78c484708704f02b4624c3a7004d2186c6f5f17dda09b70774cd9560ab63ec3f857f9657126bec6fa5010001	\\xac716fe02af4732984155afad2a1b5864914c4aa814c22d80d2d47960ad1539a464b3c1485d55f64ccd02d24ed7dd4b22f69214b803496144c76429291ff9800	1660496827000000	1661101627000000	1724173627000000	1818781627000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
132	\\x2e116cdd3be5d7f403398fafd89901f49a67fc4d477d70b54ef818555a30515a612cf9dcb5173f850c7cb6892fbf4d944b8d858bc2e9782014e41c7e7b681aee	1	0	\\x000000010000000000800003e184e142f1593ee785b94f0cfc93aa5ce8e73d0b6a9dfc8f249c8292f18769037a482fd7847826a254ded75a807d26c404aa83c228e0d70a8ea063c53d2a05608c736379f10636dcf2a3d2879c9dc47b0626b9494b47305f2246c06f1071d7381aaa2ff4fefde183bef622a671f237f72f2110245355fa9d2be55c83453083fb010001	\\xc6337dd5efcdb28d2fcd078aca04af49649bc11697c9c37ae1872ba90ff9a7266f8055840d33203bc36b4de345a106302342a0ddba554660e12c275033414c0c	1660496827000000	1661101627000000	1724173627000000	1818781627000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
133	\\x32e5cdd1c0dbdd70d2879b2cab8ea11903283328e7065d8302fdc5ec2273e2752c7f0d28c5db39eca3cae97b09bd5a027b4795b186dadb391a6126a9acf19756	1	0	\\x000000010000000000800003d3916e96a4df9b8835b14124f5585cd4fd7b1374d69555d2f1cfaf21fd64557b987726905cd7534a46d764beeea688755ef5109701a74ca1a166db98c3350ee1c1e0c563a7f89b087664b4e61b386e03da25f27b6d3baf6519fc4f2270012418b35139fe98fcf83497442d3398c9ad71d0b4f38255eb3250913f35f4b74e9ce7010001	\\x4cea5e3a7a79fd4214dd30f0bc51080234f8f1b8733db7dea9242f2f9e57c50fbd1c9d868b6bbce001eaaf3b8355b962b28ed0b3c9e95a1b255c9932bebc7e05	1675609327000000	1676214127000000	1739286127000000	1833894127000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
134	\\x37fdac91d9df36801ed1c6e9855f68ffdbcbff825a081884fb083548eca7ffcbf48ae9073a6236b7160d6928b2b816eed1462ddb7ad8dfcde977b876627bc1d3	1	0	\\x000000010000000000800003f4b8e156375f7dabdc5d7fd049da5f7aee14b80ba81b8e3d9b55f11753d610acb2775c52acb48dc8f0b8c82c306c83e04edffff61eca8904ec3148c203affe3190469a3b93db5616e6bd78317fb9e65e249b8b551565ed14e0b900ef3372b52776a4e67f7f3a83c6414e444882ef3c90190b7da379b35cb80837626b931c2899010001	\\xfd898c82214e12ea021c2fa621d94578a52a4310292aa88acbb4617e82da14332968b06bc7110d217b318c37a9aaebe871f530e5aa375d1ce845b5518e4fec06	1676213827000000	1676818627000000	1739890627000000	1834498627000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
135	\\x38c1229286885dd4ad6800e3ef3a22a6df43e4a2b668a469e38ee58fe36923b31489ff7441797d1456c42dbc531a0af3406c867dec1f55f8eebc73761470856e	1	0	\\x000000010000000000800003d7a6aa84197a8994b35431714f1418ee4a48957f78dc793fc843c70365501c529c35c44ba12bce7061eb6e742385d5741dbc784af898725788ba5c7cd0f5caa4b04a2293a1f92bd0b0c832676598f40ea6e497cba56065d60f86ae743409358d95681cc8f6962eff413a135d9d3801da3b37ea955b7c2672d3c2cf3cb565305f010001	\\x7d00687ad67d26395529a41e90bf744536bb14233af1899cefa8119eda21219231dfb307f23c996b5fc13b3445790b9cd555c5db949c1a4e9e26dc0bd13e3d01	1667146327000000	1667751127000000	1730823127000000	1825431127000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
136	\\x38097bca30d89112ca7a5bd0295256c32c1e0ed2e5b4a2d29b81f805833e2d5cf6cf36e9c9cb15986d00ed4bfd229be5d21222025d26b92671e5ab613d925da5	1	0	\\x000000010000000000800003bc3472e397fb1a3862d332e44f8ecb72f8ddd64b9c9bfb225171d5639e6a169b1861db8dc313f1fd078992ce0c04c66a9c7a2b72ca6c1ea58acbcd733d77d4e9e46a0025981f83e38fb5005416b2d72b87d549d0b22994bece035fa0e36f83f7a12861cad948e6399cd42908fcb0467e3a1ad1a783a420e649703875311b1db3010001	\\xe26165c49ba2d5affbd3def74d91994f888b3d0d862c393c81b9c908210164b44a49fb7071ca29c5115022f6d14274a67312c24b09fba938bda11d0f67b54a0b	1691326327000000	1691931127000000	1755003127000000	1849611127000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
137	\\x3a91f364e51dffbec9447f27a48cf8af5f96c6f020857a238d65b4054707cab1cfd40875e94ac498ded54ef09e22b41b3ae970c4875df2c40d72f7a179df9a52	1	0	\\x000000010000000000800003e579085d5461bdda3c0b5020029db0c418ac07cd2e5838aa674bbe48571562b5b73f0852916e1e4d1cf82d4c18885710190c6a41aadaebb2d7710daf31fc1c49bcd81f4b7f229f10d3bc25e21b1df7ec53c5b31f3cf59168cedd009a05a02227f8f3f950a493a3ffb85f4cd924b0049c8a539c0e161b4c2a526d216f025f686b010001	\\x4ce87cfff230710cf63a3b9da3ae756d3219460469dfffcedb2a89a04896a9232244c2be91875526eb2c01e12c6a260af3eb5fb8624391c0070c28720cd66709	1687094827000000	1687699627000000	1750771627000000	1845379627000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
138	\\x3bfdfc85018c3927796793b374e98e2e6ba297a7c8ee0552d50dcd0ed66dc64efc1755583c1ce39b922dabb346ae5bcfe024aba9d3039ce1d6f4e0f997b6e659	1	0	\\x000000010000000000800003b243368549ffb05ee1fa7f11aca2f8e75f08740d05a9eb01af80ae4c33c261e7c5bd376582c01b92267ea4ae81c8569ae4a0c4c74fa525fc83794f238d0e71fc823b3301f149249220552c8cecd7cfbdf7d33e9af48011db612f3d32d98eaafa8e3a33ef2a2a9bb904f2b43653151048218957436f5896d3b173953633886183010001	\\xe061d7f9d63f1bb13fe2363fd1ec48d72b29b2df72b2e156c037424a0e68d990cc176ea47aa5ca428764820e43a9f110559d43916469ffc35c07230450db740d	1667146327000000	1667751127000000	1730823127000000	1825431127000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
139	\\x3d212a89fbf906f05c23570f2bd6efda437b006999e1305765d93d35c67fe65a8067ece86ec2880c5b838c90a292dfe9797dbd8cf1e01b84ee279a4f8a4a9f7f	1	0	\\x000000010000000000800003b0e2afc9dbdc470acb20db0c970d020b366922ded56cc946397a463a4e39730e98cc4267981e66f3c447a5dd73a47868dfcc3a5abf51cb2799d23f46df3a457a0f9adb6757201bfb1e3ed2f0d6f8ce81dc212c1dd244f94635ae1a85a10e76fc226ef939cf92a135f5f71f8e14466f7c8c947bc897fb27b75c41fd0009aad063010001	\\x6e41351a27ce687e1bfcd340e754d3efa5fc0449063ebd0b56652516c7c47ed865d9372d13e010bab176b31eb8ebd41a459c9dc142cd55d324284bf6e6636305	1664728327000000	1665333127000000	1728405127000000	1823013127000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
140	\\x3e71332254d5350500c386aa65cabb796ae90b85991ec5ec75adcae0838d105799e4475dc4ed220df4ed0fb0d0678e927edd3f3145c820d57048be6f7f241ebf	1	0	\\x000000010000000000800003c6f88500269eb8f4cc326eec1be311fbbfb28cfe63f2bc338a892a45e1a506d97f06d4b8cb2a4103d6031b1058361d01765954da92f411836bcc10d52ab89c9b49ec3a0e7be643bbe34069ea6fd8274b708f71a6de56c16a52ea41958ee9a3514bb41a06f493fd14310c144825704d05573f5ec1923a4ea87c6f45c1278319af010001	\\x8250008d1ec491ceb7a3efddf36af37288f218fd684f0ee4d34df3608d07cb431028fbd4fcf5490c4ab72a0b3d5ea618e988879a34d5dd9b52acace2c6202f03	1690721827000000	1691326627000000	1754398627000000	1849006627000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
141	\\x42b5442d2a24b6dbb1e6b1f2e2acf118f7a185053f319ed0e7cdcb6dc02700b69543e2a5db6b4985e90fbb1a5ad50f287d9db15a3cdc9ccc5b43bdc85eeb9a17	1	0	\\x000000010000000000800003de4fbad69ffcd4f8a8f9aaae2cd020d4af99c6ee4798028e1d1f6120c9702003e5d9b3edc76685a6a7733c0b5cff5c50d8d0d4a08c131731313bd1c7ac631cdfcb76004bfd2c58fb42b2bddc452b70bc6a6c101958b697362eee095f072c6e0432ad9fb616f30ceeb4bdccb2247827510591c3eb0c4e0cc0662282d619e38f11010001	\\x299418bf1e5cf435522c2787deb9b816fa19679a493ac77a0db5a76f7872820615ce34f8fef1075750f0d8b57e12c0a48f9dc6814e2344762965307036c6d006	1677422827000000	1678027627000000	1741099627000000	1835707627000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
142	\\x441ded46273ad82c55839911b8b72b7a7a7b3956732ef3cedc046e4b6bf91f5acd8cfff4db8305e2f0764b63d10b532e2da835570e75c0720d4b3cfb9f0ec847	1	0	\\x000000010000000000800003d221d6c1ab2f4607b410928d3d4d66ce9abe9fad453570b234cdb27a1544227e2ba22ff63ed542fcdfd8176c132316d1b04a4998a6f1629d34c63c00af9a7a9fbe1ccea405e127adeed4ea3e61bac82e4b63fba48043be97ba36f4169c8931b912a9fb50bd71cd32122eda8dcbcd35fdb192cec5d41b99263a2edffc4d6f2c31010001	\\x5d9e91fb7008736342ed7c5f7f7df72e5d34fc401044d3f9902293be45cb7c014dbc4e63c6481837c571f5ee003c867ba91891ba4913be4bfa17dfb286fa4e0b	1661101327000000	1661706127000000	1724778127000000	1819386127000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
143	\\x4999a586543ec3288e6d38596635386ad6f23aa4ebabecfc39c351e5ec0eeea666f48e8ca0ae81fde5ff61cc3c739d125a2422abfd3d49b36db2ebfe2d8b0b44	1	0	\\x000000010000000000800003e9565815a20060a4cc17e77297315effcf98fc80c53a6621fc001776afacdcc96d5e5ea80d5041efcc06f110113f20d4d8ed4e961d1a8b9417f77fe7cad4276b3ee29bd7750836ef4d508506d7ca93c5eb0f4e7f52f358b82c37def63792b79d2eb3b0ca725c39947a29405b0bbde378ec0efbfbb88d85bf45cbfbadf5de27cf010001	\\xc23d021654197d065f6a69d35402f9dcb321f929be8e3c06387817c48768dc74afd1135d68913513a3615ca1014c11e3d0f3b4d77b2ce6bb10bf5f0300288500	1670168827000000	1670773627000000	1733845627000000	1828453627000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
144	\\x4a854e381e25c49314f9a79ff2a673271a77b5929f261007f53be92069a9d4d8c449eef6f0d9611b82304dbc5a09a974ae9f094fe06bb4fafca27ef90ecbffa4	1	0	\\x000000010000000000800003f51463b52818232b4471a71743ce95786bf722794e93dcb17776b879becd4fe42e15f061ce6b52930db2d14d830d1987ba77bfb28becefa6afe5ff5c09e3e0ba66b52d8071420c973e15d2180925b3007d6b222672867f01ab5b0607b02a531ed809e9550565627879ce12ea9ae379ce3775adb5249ee07e34e3066c490094e7010001	\\x6781b079a68fa9002864ab016ba4b5f58628671c9b157de49d94e8eb766df905bbad06c909022407e5c2b6233f9dfb8eee5bedcbde0f04fd09dad0c3bbdcff0e	1665937327000000	1666542127000000	1729614127000000	1824222127000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
145	\\x4a25a99601ee488cfcbdac38f7729e06d87a3f351eb48f6665d2005b494a49846c755b9e8e8693faea7b11ff6b10c627d2b06a88e5864de466f30a1954c2da1a	1	0	\\x000000010000000000800003dd97a824f2b498c911cffcfa3763a7cd35cae505799251cd0460690ff17bb4805f0b326ff7e71e85c51fb114d95cccd85378ddbded0e4b3f2323cfafe3ae0c07978a7745f1ec457957050709ab0ff11c8afc9f1ecfa9587ef4be6f557c733b4b818dd0527de5d375ae5d961c40ba11e99121d8ee24dc8c97ce34995576d514cb010001	\\xdc3b31eb08b4759facf3bec78d92fe531aa40428a93b6c71c8efb65ba3e79b536f8b1899eacbcdfb62d691ca2496e37879de31c40ce6f9f98349a258bcede704	1667146327000000	1667751127000000	1730823127000000	1825431127000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
146	\\x4a317468f8a40c42e893558eeb338bf78bfb47267779fd06bea7c517886bfdbfe8b50b017f80ab86cce30d0b8fcf39bb664a39d0aaaaf106239e1af8d2d768b1	1	0	\\x000000010000000000800003d1b077c7091d33328c563cfa07992c9ee83b9ec381751a8e3051bf2f3f3d044c13224c93f0374198db67519210b96b33caccd4e967d1853922eba33fb8baf46b08e497cf80b5e87f555d606d0e8588da9604df5d2d899450c68bf894946e8d973dd67acd3ef1766540fb5dd8fb366296b258c008bb6f17ab5300263781889bef010001	\\x15a1eebbaac29dbfdef9c27055fd109a4257e956be5dbe0ea9cae0fccaed3df46bd94d21e9425f2e1be985b1f8de0d86b45024f4defbf25a00de2b5c39d35f06	1687699327000000	1688304127000000	1751376127000000	1845984127000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
147	\\x4e0d557863cb3f5b06a147871533d1a6728ee5dadc7daa7b905a3ad54465e8cdfe3dffebf8bc9c022c5821733aea1f314a912cec49ed17f0d00df50afbde8b87	1	0	\\x000000010000000000800003af9187d02f6195ab018be5849d0170f3cf66bb279644d9697c8e233fbd4e164c122b71d07f080794061fa6e653c8ed35769f200c352baab21308cdd2b2af6b630e9624c91608036ec139d0b167564fe6a528b1278e88c2edca9f67181ab8741f9f379d32d8568afc65f1728afca427d1bb65831418e39d87495fd5ba8a3a0ebf010001	\\xb23ba34374e362d299b9e9ba19fba909dd78ff4b9fd03a18541dc2d2ac3f37a3ba4e2d448ebbc722f247ab9198424c3b45f274798b2c8feae9aba12d30f0df04	1679236327000000	1679841127000000	1742913127000000	1837521127000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
148	\\x5025620c660e6484c9a546edc88aee62103443b792d623bf19d9b740a6a5e0cabed104249d0629b9f4e30e6ca4a8462c07edebd26488401c63b91400eb1f3873	1	0	\\x000000010000000000800003bceab057f4a45c4ddecb315e3400f27e36e1a4de1e0a4c2d644f28b2b9bc473e88cb99f9808a29c0009783356db96b6d7ac3c86047394eafd2daa5e706429b9f5351dd38a36e115d47b2c8d8102dad0c32ea6855f35dc0cd78c78b4949e1c2eabc8a514710116c02455d29266d64ee62f42b4020c9a7069cec736512b750c449010001	\\x8a48dd49c6ca0e0448addc2a21a23e63dda47c1c163fa475777b2d7169705106ea736faec7ae04f2cff75af93fd17840eee3dcad49260468fb2f6c039b124804	1676213827000000	1676818627000000	1739890627000000	1834498627000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
149	\\x5231d305557232cb03884ea9251ed2e379faa9f96c863f55f69d166a4e586dd49a8d54ff64ff7146d3e33643e6190ea44c5088bd793636725b7a4bd091084c93	1	0	\\x000000010000000000800003b4e373299748fca5142701392276173c5725516d2397fbcb2c2a2bbe9ef63f90f97cb83a73ca0973ae5714129c66989a35000fbcc45666f75f3c25ff756cb35451cada7461f846e0ffadb79fe98571c354b20c8c6e3f2e6dc89f3ec16ead8627f8b56cf7aa2edbb993b27d3d906de76b6399449c8cc31c223fbef5050b2015d5010001	\\x8424897bc6720b0245478888485ba95d22256f9f9dba0c8633e68cccf729ddb0dc6013476a981d7ec3fd8d99a76bd12487abc1c56095f6ea86f904a510e82200	1676213827000000	1676818627000000	1739890627000000	1834498627000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
150	\\x544d5f763b8c549028ac8753a0ec4c726579c5b53faa60201d9953496f1e149e0b75ba681f7daa6e4b1a5c37141001c17f98f3fd79afa4d6b37972db28422163	1	0	\\x000000010000000000800003f8f280c81fa78cf87d1e80ea9a8e67c78ae682315e3987b85ff18374bf575c34ba31be612f8079f3e21e48a1b5e78ea329472c84a373fedaa4d21426c114ae54ffcbe9374b47b2973220dee70d88809bfed01534ff1cd9f091a5da57554401b32efb3c7f38b38587823ac77cc89ce9cd2a4f00c64f6656106cb0fc6b6c01af0f010001	\\xaee584d4dfac06d5117cf17b5b12e55c0d46009477cb2dce83555c142bf7cdde1d3043282d26088df7a06b428371edf29a4fc0c9476a4e818da7ad030f28e608	1675004827000000	1675609627000000	1738681627000000	1833289627000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
151	\\x557961a4724b460232315cc600f4604a3282a1ce51da948eb235e61ebee11150a5593adebf140655b2d9d820a7cbc5a1a43c1b429cdd094c489ea2b7c5aff8cf	1	0	\\x000000010000000000800003e16bb50f7a77f8577e59a8f8b7f8d614101e400c904b291449507c3d5b6db7d479c3499e6db5abfb19225bda6c9ee764f076c96427002f518742f920e84ba277605b345b1dda16a23c80d6354ce8435876ad419590e3db5b215ae49ae0ed2442a2302d550942591880a1572f1b21e8a22814cbc77a9f1f8c4265c826b041d45b010001	\\x90e73246ea57895eab7f6657877dbb0d271a4200315b814fdcb3011e969a78066aa5ffa76f4f099a0ca5ee24903b5491f141425dd84ed3d5b64ca0a16d78ab0e	1687699327000000	1688304127000000	1751376127000000	1845984127000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
152	\\x5a15dbd62018432927cf842016ce17e21dff5806ef4b7a768a403e4654bdc59a2238b64522117be838c7f39fcdd8050ed12e1e7f5d09f1b5d2cbd597c9b34f23	1	0	\\x000000010000000000800003c4bfd09c3de07647a1b1e603c2079bb94bd32f3c7054deae82135c7372078d7c7177f0a303557da19f598bd158f8a7204c6bb993df34df805e03c6835b35c724d5d65c27660319a046d32abb91b46db4c714e08d3308e0c9b7ec647b7daa140ba01cb0df38eba7c96c18e3d1bdd0e9268108a64709ee596a6740d78357fe3f47010001	\\xd3ccf921d7ee22946ad1e8b0c97ec7f1a2176ceab7c532ea15950946151dad150963e8ee36ae578d27702bbaa6840cdf33b7712b32595fb7d9987d2f2b81af0c	1662310327000000	1662915127000000	1725987127000000	1820595127000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
153	\\x5a5d47a7b22a454c4b292bd360d1af26a53d8f03f53fea7d8e6841aeb99af797c9534d0f211ede45aa3926c702e253e6c3d286f90741aaf4bdecbc262252b813	1	0	\\x000000010000000000800003d4b7db516b327f721a756546da1e2b465cc4650b14d70e73ec57a5228ccdc3e2c25e2a389d82e39bb03cff50f42ed08091b3b48abbd786bc1a9827655a4368579f57e0da7359b35e000580a769ec8af14c2227f240e30d4e2eb90f2304ce9d8a843ee2296d63e19ebb93a93d23507856e5c4f859ec19a7a3cf34acf4a4824d45010001	\\x7184c6b94dca195c0cf501027fc34abeab4f1b139c4d084d58d290d30b04a2cad2c253227bc128fbb571b415adffaa50b37466ab1ebaebcfd45a3bdb6b50910d	1660496827000000	1661101627000000	1724173627000000	1818781627000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
154	\\x5b51cfa915503901e172b7f87b43369d1065a885ee62aafefb025dfee97bd503897c254eef64a8fe97bd7a6e5594d5806d71bfdd51e885b3808432d076b4a90b	1	0	\\x000000010000000000800003c15e6dd4a78443c067e12bf826404b37ef01fa24e00b08b5b517930bd355bedf67e41f9a923f31c1f3310b69795329a8227b64ca3bc75b51358605203954b1125c5bd537c07e11d983cd60769016b93b5ba266a419e8a401ad065cf2f63cc133d7fb6a282936fd566eb28bca126af510f568328ae632caa7754ba20d6bca838b010001	\\x16880fe7ebe77bb33f3d23eec392eec2731869ed0077ddb5c9460f028f037fea3f83d025a10fe2175eede35b8074ef223f091d48acd2413b52ab1b5e7efd2308	1679236327000000	1679841127000000	1742913127000000	1837521127000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
155	\\x62d11c728a16ccc41471704bc9d691bd1f7fd2e20b86b678d596b61fe5b10d20ae6e9ef4b0e8878131bf4c73e088b2e58456aeda688a9114491c7b8e84814a85	1	0	\\x000000010000000000800003b29f9040515b35e73d9f74a4800ead58c4b2254a758d887837f08e4f8457923dcb299e45403a9630c7cfb6b787b8cdc77a8cf98031f68325014962f1df15d6ad50dc66c3d4282a89df8fcb08829bc030bd5cf541f7d1868aea91eb0b4af36ac97296a89dcb50000a4c76b4c59cb48e35418886d934a40e814b1f854342bed285010001	\\x18a46d86427c00e6b539c5cd0d4fd6522d7f3fd65d793999a2ace9606b75bcbe7afa6c89ffdecdac80199f27a8395396d4ad5edb21b4e74f8f34020ed81be706	1666541827000000	1667146627000000	1730218627000000	1824826627000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
156	\\x623d8f219c7908da5335f8aac87b3576cc412f3646532552907bdc9f8263f15e0f6e66686ed9f9c84b16945f4ee0c1f3d0fa4d1fc25594eab871642cc490c06a	1	0	\\x000000010000000000800003d0bbbcb80ddf17e1b0bf584af6de0c4cd2a24b01528d2139ecff0d790793c61bacf9acf70e1cbbc9b58a895f5f6a7dc29ccb4f5d57edb3e19fd28ade0a81fe704a442af45544e30b8ebc7c0ad748f67df3b700d7cce39d74b8bd9f4838e4fd2fac23fa16ec8dc7139286952ed1b289ee431030e37dc2990aa923e6a7d12b2449010001	\\xb4cb0dc380491621c41f27b7cf4f0e3104eba682c0f124bcefe1409234452231085f10c6e7da8489f38e5eac5e3110e6c26f8036ec68038dd7402de7138d3206	1662914827000000	1663519627000000	1726591627000000	1821199627000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
157	\\x64b1b50b9031307b791c0af38bdce7f6d3269201f9dd15de9a0df71616145e83a5b76facca2687cd05ee562381bf3f2d957c95744e5e870d32d099d6c55b4f8a	1	0	\\x000000010000000000800003ba89fa41a0c097d930e7584f1f11352886413bacac90075ad40cbdd65464c824230ef34089cc5f6f65d921cef758d34087dba3b21c273e1a361480fb1bf0839a7c82292924e721635ef53c71844b32bb483562dd7a72a1181f50ad8b9f43e8188058f8c3ba7dd80cc6cb22aefdcc31c2db3f6ef589580b16a2878a9502108b93010001	\\x07db1729e32181042a651eb1ba8fbbb4b1e437609b0ec6670550a7adb2ea3c23a39d087a583e0026a20de9f7a6f0542ac3f4664494a3387afe5c17af1b1b360f	1681654327000000	1682259127000000	1745331127000000	1839939127000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
158	\\x64318f6c796cebf59cea61c79a3d449aaa156f424edaac685058a12010574af54e8b6457f0eb95ccc08458640ccadb4ac28bc770b5004606fd2816f2da5fec35	1	0	\\x0000000100000000008000039d28c84c8912297659edea107d0aa08df36151598756ff4bca4e335bf317c1264e180999e5516a5d3781d55d05d22d4f17251d2877b03e6971e56cbf501db75526180599a2a5d79fd9d6f29a70abb55df9921a9c59488098d688961ac0a65fe26b9be6c101c0e5871ae49b800e0aed4ecabea2f9c261b839e42543cde3cfc947010001	\\x5de8814a530cbb36507af8b2dd08f74102f27f8d13a93c14b6a01eb69ac650a0b55984bb3dd4664fc1222a6a57918365326de0b19b84db2ab901fe36d766f503	1679236327000000	1679841127000000	1742913127000000	1837521127000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
159	\\x67b5a2e4ef5eeedffc67f65cb3f2a81bc8594c09694295b7dc70f4dabcbecebc7457e3907d2c9a06528bed7da4d26417bce5b1f468a0de2263e7ad72fafbb0ef	1	0	\\x000000010000000000800003cba33972b3130e0bd11a70df0223b2904132c4feb4eed83eb46a4138d05feaa598740fb72ac42570281e92b94952b6fc9cc946e89a1e23ea506c2e0e5b6a3547a7ff639c1a8db6d7697889041aaea9de871dc266c389b1c73ffaff2214dbf902c2cc46644d68544ad490c38dc69aed89c6bb1960408ee735dfa88d2896e290ad010001	\\x3f4c4b27579f098b5f69fba3d1857300baf072fee0f610ca9d5a3c205679f8809b49ce68549f552a881a84868c975e461bbbfb7433c37ebb4e10aca67f308c08	1687699327000000	1688304127000000	1751376127000000	1845984127000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
160	\\x6b09490b2ef2e99b8e7debbad1d79ecef0fc4309f61a3e5d620dd8efd99688db399e06300a81e1fec8b3290af8ba5d52b5e27226e14b66dd78ccf63a852ca693	1	0	\\x000000010000000000800003b9a1cb4b092ad294dabea0d419ec5101b80624936d7b304403a65ca6ba0116e376b89d5af33d8bc2adf05fe8f10866f9e41a4fadae921f12f8362155279a33482b69a79c5bc1c3080aa8bfd2c5e15672be9fea4fd6c9e0056f673cf4c15633c2a85a7978906c04c97c5ca5ea00caa26c842657c22fc3f7d7a757b859972239a3010001	\\xe84783031baade0eec34a3548f0d7ab0bebc39b47d3aeaf07e0209fd462ad393328484e1946e6650a2301bc2fddf42dd3da9c081a72c2f7b46b13ff6da659b01	1687094827000000	1687699627000000	1750771627000000	1845379627000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
161	\\x6fd90e4bc1f5e5bbc900d95e998cf0411881b9b82920bbf1e0e75f0c68fe9551b1539f3020ec49fe1b058781dcabc4095ccd0ee3c38f15551f056309ed494eec	1	0	\\x000000010000000000800003bfd9f4fc83cab3969499930c6700562043b045ddf15b47c9517c181c23832ea60a735b3f58bc221b855750d97198ce00713d512deffe2cb1287df2ff7ef4e6a3495cb6b9fd632d7dcd6c4b2b421f0def8ac1cac90ae4f8fee3a2655f3008123d1ef1e530323a9dd58fd3fe9d7a66491804db7c8b93bd54a2db25eefdb83078fd010001	\\x3e03b7c7a9bf11d7d1d7fe77f8410a6c11e066d15a89dd14e38d02ce125cb17e4d12abc8927b361b72e1d1fbafe78f1daa989f57907989dd6e543400265b7603	1671377827000000	1671982627000000	1735054627000000	1829662627000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
162	\\x7b5513405044f3e34443176bb4bcfcd8520a82ad4904daaf0d5d284488042c9ef5b0f10d0dd9b9318f8ea6fb1aab92e9a3428b12effaefb5691b348978502e81	1	0	\\x000000010000000000800003e06763f8df965ee6c5eb86486df7b98802643052dabe0a3564a30514e8b0a6b3583cc7c249a192099c0ce97029a6a33ccb31206559393a6bf6fcbc5842319b598850cb32a46eb4a82b45f08c0fd8321250b95a454535e187b7a2761951ccddfb3bd6e48b3deeb4a0e7dffab30793ec1e7d92c785fd88a139b124857811b850b3010001	\\x6405f5d594d9294cbf2ee3c0c0a82065cd1b91587d71d8b63585b595777e69f7d7c98b63d2612d375e372569098d4f55d46c8eeb752d68b07c11e3e8573f9402	1662914827000000	1663519627000000	1726591627000000	1821199627000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
163	\\x7c9da57b244d009bacc4e0f75bc9907138eeb9bc35cbc66b3b10731a5e119af8fa87ee0c69fc7b37c07b85e9eb382e309a224a41869fa770735c5bf5379bc119	1	0	\\x000000010000000000800003f719b02453c06b25235d7cf95a1def6b6451111cfdde6f65e7b85a02474f816a4bc9935b380e6929efe09b9f6b03de6fef7516951a7e073a32d629959b6076a85aeb504eb6e708f252357c59a92c68d0780437feed501c566b0af65ba550b2d54339543cd05f230b42f60a46d4d4a4e9aa4c63d9944a83304ba65252d138d2b7010001	\\x10e50971ef6b5016850eb35e5359b598dc94c5ab9a97a00de887c78c9bf147d21cd4638a9db47e0e520e9722a04886504103dc3d6cb7a908b80b49cd7161a80b	1666541827000000	1667146627000000	1730218627000000	1824826627000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
164	\\x7c25ce19d510c7d9f0efb47062f364d5ae0ee8643080157bfdf4436526078834d0bc05ff0cb888e0a8769a09a87589eec3b7181fe490adea61660e7de408259a	1	0	\\x000000010000000000800003ee5d8c62b8c690c851b3bf182927ebfbd11bf68fc9ae65efe589a456d449a944f438bddd638939a421be332601e060fbab31896ba2edd8adfe4bf99d4cba1f01d7805b7b98688427bc762c804d20bc5774e2c7dcdc5eeba5b72f3dbe8b639d9707034b23bdadac834046ecdb29a43f4ce84d5f8dc986d6cb6ba488543f0b52d5010001	\\xc229e46acb6fe2e3e2d80772e34451833fb27c7e3f7a2a9097942fbbadbe17c8d81adad17e37b5350413af8bcee703106de6efa1ce7de2112f7f6a37c5270f04	1662310327000000	1662915127000000	1725987127000000	1820595127000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
165	\\x7eb1220bbac193a2778e4ab2d50f8e0a57799276d148817f4652d920e860b18bc06b0b3de51aa070fa9b4e23d842332f0ef1b91c4625695c800a7203c148e4a4	1	0	\\x000000010000000000800003f0673a406d90749b5042cddd121a5b8cd0ec4fbf60fc430900aea62f2cb893e3932786c761fc64644fa2a35f6e5ca7c4c64d81baad325e3a8bb689614aef4fcd8ecfe64c04daea9b61a0e6e86c262ff0b858f06c908d9395241eec93862bf759f7347945cdfe992c533c8b0fe12289238137ff2a67b5ff4cc2b1d59d4f9ac519010001	\\x4d22b240d9f5213c9741bab09db559c0eedc58dee868faf7a45cd0a77ec5e55a9699c2b8389222571623bc26a17764f9136895823c81d5dbd77a3dc367c69a08	1668355327000000	1668960127000000	1732032127000000	1826640127000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
166	\\x80d567710f13db8d3d68adec193f09bbf003bc1f8ed83ee5a5c121c590a75aff9c3be5ced2ccb3c428c8f239cac37c4364f3f2bc71c1e0f4d0c6ef0b09c8bd49	1	0	\\x000000010000000000800003b1875976a7c1150bf92732ba306ddbee4c2e2cb00683870b0fd64e52946998e594095725e911688aa66294bcc7c779687da30249f43be62b03fff4046115f650a658a27936628f937cfe5640d35fbdc761b82655750ca54944600e3c5fc1330082458abd0a1d52a4ecb074214d748504e49d6c064629fe368d5666ac0d86ce99010001	\\x093bcbc8ead08d43ed36114f25217231ac78c68a03086453c8a241c27815178f730506a291ef2206fcbc70af5f5cbd57dd3e3bdc9db6962e036f3482dcf54204	1691930827000000	1692535627000000	1755607627000000	1850215627000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
167	\\x819d75d7437e14fa5ffbd7a9724f71f6d92994de7f37bfc19760ddef1ef3484832e543365eb73abe9daf04b8c203c78ec21c427989cb3b50fbd7acc067e84f30	1	0	\\x000000010000000000800003d1c1385f5991b2488eb6f5a5326265393ac56b69aaf0bd384a8d4007890732475d424937e50b3bfc93a2746040daea9a5c5e315316bc7373c5c0c9698feb75da51e9e8257694d12deef12b37b56ff1ad49a3016eee835512ad57a050484f95eaa715488a36ffd4feb325ecab1a5e37bb750cfd16f65d3cc7ad932f192d8a1603010001	\\xe2c93b2610b25b89e8ffdb935b7ef8a7c075301f177000469fa2d7f4da8a196fb4b21d84da27250a0acb0da27e340aaa1cffbf4669de998ddce8765745086700	1676818327000000	1677423127000000	1740495127000000	1835103127000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
168	\\x84c573fb5ad25b7702a05f97db51f2ec223a5d35b2201d50912b9e550f40278fb66657deb7a133f9a0592e37b236264c6be96bc42f0888afcae32e34ab8b1713	1	0	\\x000000010000000000800003b21432ec717b319535253419cc72809fc103a67eadaa7d983e9422aefd55716fc3551fdf10464805528abf6e7a0f9b0aa576cec1d410e698eb31535a7b5af49379752c0b28bc8e9d133390c453c0fd17e0c40fa4f7bc9d53a19002ac3c5fcc8b7e0337b3f158c1e4b921e296a60033e8edb72c61af5e9ab13038e03f73568085010001	\\x434d94093772b22fd662a40e094ae4aa7a8e499c55e5baf567c4bf8fedfc64d428e7e3e454731ae00f9aab9749a50fc745b34f3af3be993dccec921cb835b30a	1664728327000000	1665333127000000	1728405127000000	1823013127000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
169	\\x867d651f8125bf9733b9c0724a95586be3cefca249be75b3954a55ce9052e3837a9c0f56bff976933e8e0177f57bacb81153fa6427d4877de5c94b037c466242	1	0	\\x000000010000000000800003bb676a9fe978a01f7b9f6ef8a17e29e20fd02f7683d318dda938bf2cba7ce8cb98866749d8e7b791fd6dafdaf1429006d378b9190eeaf3892a6354eff9220ba3ff2d317c189a5c5cb372f75ac5a3a3241ea24724875260eebceabec654e363bc8e88060d3d861c30e3461e76736d7adf15169df9f71766210add21058f41a605010001	\\xd7c33f9e417e14ae4394bb03d8caf43324aaf93615245cd2eea5d83431a53af0e8a0608370a832b3a137a6e9d3815da4adb5be8505424dbbc00afdb17436f10f	1690117327000000	1690722127000000	1753794127000000	1848402127000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
170	\\x87fd9c65c107a1e9d9b972f9bad4a2fab0a26e8e42f739fb012b05ceaf0d0536f8323cdcd4fd9b4fa0957fcc99c0b4425ee79d00b084cb47efa6f08395cbefda	1	0	\\x000000010000000000800003e7101cf8c29e1ab5db3b1bb27fff9d5585f978cf78e9125a83edd60556e1b973989149f23f4a776a330cf4ff55b201e48df1c51d49d94b5052730e1ec5483e3beddf053c4e5ac5183934203765ec607e0c62971dc0e3ace0b2ef8c2933e6e13017cf3c7a0101cad9e0fd57ed2ff77378fd07bb1e012b213813b9dda0032b906f010001	\\xd438efe5025d31efb919d013a8cb84e6fa6a45add656a8166d4d03b827a5f9aa8e9b1178266500639407d5ace18d49170781858722102ef58f72cf0822fd1d0c	1666541827000000	1667146627000000	1730218627000000	1824826627000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
171	\\x8939af4fc6b5837a207b26845d1c3f33d5d515685df937419801f66b45460cf42fa82054fdcadf7b53f0859a0c65eb2cf492368779ec9b2da0017eceae06de62	1	0	\\x000000010000000000800003d6bb16b46cbbef88551898fdc7ab83362a7924a087f4199da3dd8af64ffcd4311b0205f013963abc44e4f626f663bd7e8de91da36b572241cd5d49727e54044c8edc8ef65051c1b014718a66c30a607037ff95db4fe748d334384eeb104620b7727c3d54633a1cc6bc489b1d2211ab8a586d34bff3922d4b7e8bf2371a59b7d5010001	\\x6648742a11c6a03ab9a8826dffedaf5332aaf5624d89cc0e928e4f360d2776127afc66816508c23b5bce17c64830870434617ac51b3911d476a8104cc5a6bc03	1666541827000000	1667146627000000	1730218627000000	1824826627000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
172	\\x8e2d2dce701a3d1edb68e92e2ad5c4877d767f29e3fb1295d669cee97171f6e2f36b51e4f13cfa040ab001886273681a845e9ab81d9554b5f44a2dafe1fe288c	1	0	\\x000000010000000000800003d81896b88ba9ff4dffad7d4abdbc5951221feb2a42a15198362836a0840fd7ab8dc1cc4978817678d88a4e990adc7f25ca5fa85b4ec8459f325bd2d0c766150e3f87e9eb09756b67dd78a7914e9f106b1d5b3c936efa4d08512841e9526e72215aba93ed1de28935ee6004f5f6c5520510d9a97775359546afdaee6000365591010001	\\x09492c589b953cc4835658b04928217d3726eaa55d91867a7ffef57f0a6f23c16cf9faf52079d1d954fd4a47a28b94cc02e5b98fc473935b54a8b425dba6c006	1674400327000000	1675005127000000	1738077127000000	1832685127000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
173	\\x8f35f9480a9360c98be9c8496bbe08c539fe8b380625b6305f0c05b97fd45ca8da9a6659aee465a1a43842d1d191c21d99a8df3d4449587c918e16124ec08601	1	0	\\x000000010000000000800003a57b7141324d5f20e23b870d9c845501c5859029d8cecd4bcc1f2b343c6d6ae759aee9c8460b7d2ebf062c1982ef6f5032ee0dea862693731cc5b45ea46a66642eae20d4df8f7ae59370e048eb62caa8701c78a2693c847a73b0572254315d8a3e890837f2cfef755f1ab3adb64a6d1579e3942eac54b6ef1ac1faf4c21f040b010001	\\xcb9c9c005b0e22d5aad65c1380a84e131db3fc1afcc5e954fde0b2e988b40043df629d39376c336f883ac3c87f1e012c5e37a4ab0e1c04358032d330721a800e	1673795827000000	1674400627000000	1737472627000000	1832080627000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
174	\\x935de6232bd5fbca867b47175697e740392aade6faddee542be1e66b6df8acce0f60b3a6eee1d04e77403777bf4ecc118015107b03861893ab53fc1d50734418	1	0	\\x000000010000000000800003ac70498f04c806ebc25de3d0c335705f2424903d4ee1da99c070f4c41061631b363f9cd6fe251106e7af2b20aa26da867966c52daf72a07c779e25d8060ebc92b276636514833823aadf537bb2b7ab44e68da660db28943453a0cea8516a8731918f770f48922b5ce6c47264b90e29a6aac12fcd9b8bbb1eca0130af2eb3bfbf010001	\\x20992122b1678da611d7e36b1ac4053281157411468b6cfb7174a99de335851046d826b735fcf3e37277b7c21f019eb8204323d72b69358092fa09c64e62560e	1677422827000000	1678027627000000	1741099627000000	1835707627000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
175	\\x98f14c5d2bd11c0044d71be1f04e2a041d17369d92af269faeb9d26da9f3cfadc527a152693a35230f59b83bc4e01f76e56027aa3bea7cffd925d09f26a316bb	1	0	\\x000000010000000000800003cf51524959b38a37986b25d48b97b661fe4caf5ed2aa8df236a0002534be54945b522e4dd8c82fbf3941fae9fb7235081fc1d3a2be1be42eb0ac9636ec233d443f43457d98bf6e78563756632f362090270e34b3b0dd0696a60e596737d4a7a2de6370185bc87af649a2554e7d65d9411635d2833100055ff4c9e2396bf51f4d010001	\\x784ab1e3465dba3940351e187ccf097d0c8a49c8b28948d262e7fcb032fdc0eb5952b99e34f0122f7c0c03bffdfc5ddcb48a0fc1857bad67853ded89c1dd8c09	1683467827000000	1684072627000000	1747144627000000	1841752627000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
176	\\x9a150d7f080e2d854a6f0685c9f6eea82f31cd86e4c0d4216221dd1797acdad5740a52cbd8a8cf6de198190ca5d539fac5ca3fbb079d9e570e179577fad8cdf7	1	0	\\x000000010000000000800003bbcab80e3ebbe63fab3fb913b02c980c2f74fa77dc2df9e87f2fbbf6727b24bae98d748d246ff0d5e05b3bc02f427e809029b351a1abcf85eea25b2e0a6ee9500a6fad4641b6c038d2dd0b94e1edfe11b3571ddb9130b5a8c31b810c8e86e577adb7831220a4fb6c81aef7d232d5fb48ed3c58f9ba6cb4f536cf547e685c1771010001	\\x7eec4f21a877f0e1dfa42ef920d27210048d7a372f668a80a1fa76a6402ee4af84a87ebd17fa61e594326a5a878da025345cf16f8d8f71f336b470bd1631e103	1678631827000000	1679236627000000	1742308627000000	1836916627000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
177	\\x9b1939b9f0b3d8c170dbfcb3fbee404e4a686ea6e2525d72058744176f8f40300901c273daf35f6d460eaee6bdd79ee41aef3f25657f866223f24938a88951dc	1	0	\\x000000010000000000800003b8c5a402a519fbbf7485ac239510809974cc331759ab1e7be3d145160a7379aa5358be4d542a69d1a1ebc15db04a9660f6ecac9c61cc58167a8bf5c13b780b9918f3a4cc62d1589c7cf5367bbaf4e242c62a3c210c217cce7e83ae93ec9822426617451c5f970422c167ee023b5ebcaad6d058a6cb5b784b3092f8cbb6ad77e5010001	\\x380c643cac5ca06e2f1a895a90f6d01aed2ede62f5eeb48425fb11a49bd8075422b297e6634333a6fc5dc54c84e6f6e568e3de409bf89ca74aa2f149ef31e206	1668959827000000	1669564627000000	1732636627000000	1827244627000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
178	\\x9f956f7bc7b0e67d61d1396ccfeee18efda42d7082b2e1fcb006fefde4ab4276ee0d222e63a48361a23592cb8ce072c87d5516318a7877bda02a84fce7164a81	1	0	\\x000000010000000000800003bd8c0bdab3b7c6b5fc2fd03ca66e6e114320bb84925a5a9f33e574a7fed26aff7727bf7e03e29d4f4b9ad18cbb6adcaa73f2b11e218a561647b4b7c036799a07869a3c438aaa38789c7c7267beec539c3e7aaa059644dbf6f2a4e40e45d2a7bfdc4e938e74431d52941f06f3d52ba594840fbe35e372a009a9c1cac1ae897cbd010001	\\x37a575139557562a586e228417a046e4cc4f0f4eb9b4dc6f183109785ebe49a594c396fbba34d54f78b8eaaa963d98a01c8bc54d3459d456511fb1b6ea999901	1670773327000000	1671378127000000	1734450127000000	1829058127000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
179	\\xa21d093b12b985a80db814ec19869999241ba533e33442d5416016f9a3cbbeaad11bc41ce8eddc748ee779f70d0fb4b38a86faf032691cc42888abcde4749309	1	0	\\x000000010000000000800003d28ba910461bc9ccbba42601a307f8dc37b7bb3a7e8ea22f18d3c4866ce4f53b5018663a73a8beb76c65dfa71211528a6fc80dfc23c2be9df09b2a370efe9e8f333e9d3b498e026e54e7c0843f8c769842ed6f2523150037b0add48423a1a8e8d45244b7c94cab96c8d8f5e1ddbc39d3d8ca118685354e4299cc9db772c5209f010001	\\x37de4c03190085cdcc15a36aad53db0f94e150ed0b453136beea9c260221859e5c978de0f833ae69375e060d496e5cafe0f341aa018d86c6894b4430cb5db601	1691930827000000	1692535627000000	1755607627000000	1850215627000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
180	\\xa3895543d5cd82e1c8d962abd81430e781d79e851bc0fba270eaa2551dc5e922bebf18aee673966f965af30216972a92874b99c905d8983b9f09db907d836723	1	0	\\x000000010000000000800003bae706851c816e8e2e164a8a94da72b4a087595b8237a9b6ec776600570e079a59852d4e735dd410a5339c0f4757d3734e0229e431c2f811c635788993470c9775a8fbe03b7d85cd4dbf7174eb50998683aa1bd11b1225ab701042f46ad9ed2423776092cc88069b4a3e97b4b3014d4461eb67de82440181e7d2d80427caf7c9010001	\\x281250891a8adcbd00d21e08294b4642102423cf6eb76c54ec5f46ca025708d2d95412399d870ed703d2245b9c49c6c9a2db4aa2d59c82fd605ad879306a3e00	1674400327000000	1675005127000000	1738077127000000	1832685127000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
181	\\xa6714710b1fe4bd668b0ee4690f886f23b00c7a8a1538763e5a8045c190b9deceba50853eea927c60854dfb2165df83cca63bb3419929665824beb39825f0088	1	0	\\x000000010000000000800003a786866902a0d1b86adc85f05068e0c4f76a674f37b6e9bb17f11c82867a2359992d862cd926f56288af005f8ede2737438e35cc734ffd2f11909e5179efbe5842f2b1055575e24888bd3f1223f50ac6aafb6dd67a1d40788bc7158f60c384559c1743a674e6fdcbce0f00869b582393c5eb278f6d971e196b87a21692ac579f010001	\\x76fb9c921907ec2885c5777c7b288612b04080ee4bb2e865398ea76f6c6e978614c9408ffe3c1ac9824bb05d1370747f95c0119e3fe7ec82d8154aa0b2fc540f	1675609327000000	1676214127000000	1739286127000000	1833894127000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
182	\\xa731e430cc7ce49a95496ea441a4a68ffb8c888557bef05b7ee21e065014e162affbffddb8b91d1dbf9df7b13d306134916fe8be492e0229d4f54e266563af91	1	0	\\x0000000100000000008000039ae1e9782d194963a62770c775da2a77b36e2badf0009b688d08670ae3031369a207e5aa1a916bf10a576327f87ad263d32319448d5bccc98cc1d66f32b2d143f801c2cfe5237d210601443726c521dc5e8768a5e0612a1f4a908a469bc2eb9d5122796dc1dd8e21f59e3818c4a8ac444d8ac7d885fb475fa96fcf80e2e36d2d010001	\\x2fcac787a700b0b4542dd36164923e07a1969c23f1658fa4205f15366b1a0c6fb90fa9ad2db61d69de52715ef1e65e55016ec3b206b235f6ff29280a6f82e107	1686490327000000	1687095127000000	1750167127000000	1844775127000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
183	\\xb161d166717a7fa8d04dbb7d1ee395b0e1eef2f431d38cff0cec72a92489bab62d3582a0b8a031b5a114b33333f45876648902095673df046fd9183837f66a1a	1	0	\\x000000010000000000800003aab91e5f804ecffafa210ebf3cb4a71c5e0063fc01e3b546e33a23b1c7b301f43ffb6ae43f8350976b721b60be2d82fb0547055758f76634c48ebd6d695ce5d977a0e8e828a1c4938fed323b7e4e2f35b9d99af6079c9a9096a33f6b112f3d6e2e0ed20fd7c85a6c7b968906de804a8c7841ea67d8083a2ce68f36a970c26fb3010001	\\x0aa91cfd0e76cbab6c4c903747f209be1731e9ae0c84ae11893ffbd70c16635f4eb05fb9df8090376dd965ec25c60f9ecf2b165e1309af5928e5f186fc592d01	1673795827000000	1674400627000000	1737472627000000	1832080627000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
184	\\xb231db6fa23e1e2561c7e340da24f256e7685f902cb9bd07bf2f9e9672c99a5065b529e69c3668b15eea4282679e591c83a843a20e9e2c2db4dc2bf0394af2a3	1	0	\\x000000010000000000800003c49e2fb0b4810038252ceb9d5549bb879c2575d9ffac923726d76fc03a119e01982c2780cda165ad32a8dc77b9306152f4a5e5903a84b180b5aab984bc481d85a7ef907bb848b68012969d8aed4e2fe22b5509964583e477506206034a2130ef205c019b66c00ca8a5f654059e88a492cff15d4bee4a81e5f1d02cee1b18872b010001	\\xec65b4104fb66de1852d1b9610f5c6b16435dc2e32883a4ff505940d0a27c9f3367d3993fc45d6535a123c132dab6ca30fcb12206acde669d6e9a99afc68930b	1689512827000000	1690117627000000	1753189627000000	1847797627000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
185	\\xb2c17c159dd8138d19829cb798ccbbc03d91824c45b3805144536f4613b5bf845357b81db770edc0f517101d43629a4abca4b912b564f3c0c883099acb4ec3dd	1	0	\\x000000010000000000800003cf87a509573162fa6831618806735f5cc9da53a308654f5e2b1c26d40e61565f630001b7ddd5fa144797f853d1384a2bbc227401c61b7f2443c5df56a541846c852f8728a662b6f6180261bcefcd57a8620e78db875b7d8a8432a68952a167e75216563c609951e56150eddbcd630ae55a4b82f3ebf512b23445c0a3c884ad57010001	\\xf9304c202f3e0383d93cdb82cc08c89875f9b3c173361eccde6d561f1187af4a4228db8399afb212409f91876e1d49248ee6c93d5227cc46b402be552f31f202	1661705827000000	1662310627000000	1725382627000000	1819990627000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
186	\\xb39d4ff3e408e88896c28d146d334b0b73585fd853b87a5b01059fb0d05bd0a777d94e5f54726e31f79cc572c0434da81877d1677d1784921e3204877f51bee2	1	0	\\x000000010000000000800003b85a541360522d92a6560965e8ded231e2f7b30eeb9aa55b3fb5f150ee90c60f1121dc0aa55817c3f142a7626943b0c823d64ab01782d2eb9d4d970c091771fd6f6c7d879ab0a08e4aa90e08522407280848ba060b1cf25938264345e09da29fe34b085902638b6936ca6c5c2b50180741579c8aa34e69e9e9abf66e7420a26d010001	\\xef82acab5471a40cb74f74474b8a56dbf9d2cc8ac7fb0c9dd41470b54ee4fc4cafe5e1eedb5cc4693f2bdf5c6ad702d68314ac53e934074df2d5509d9f3a1200	1690721827000000	1691326627000000	1754398627000000	1849006627000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
187	\\xc0f1ac6f2f290460b2986b564b7fb47278726b87552dbfabcb06b1165982f889c0d269874244fe8f1bf8365a90ab9a11412daae1eb9de898c2a71cb52b1ad5ab	1	0	\\x000000010000000000800003a379085c5cf01d4a6a7bace3fb6a91f44b01c3009e0e628abc7495e141374fb989fbde884810437f5ddd9f3848e50eae4b576f884f64e67ffe5771e0cdba98a955565687643350ce15aff11b2ffec88943a88ff7b6bb5e342d02ff11366c7ddb187b1d939efd6e903c3e25255facf0f9033e75b37c84319c6bd0b061134e3ec7010001	\\x5228f940af83f94136857313e62763581fd77f569b2364c52e933ce95c22c4b67aa5abf124f3ab9969b4e950cc9a94d34bee8144af0b690325eb0024983fa200	1684676827000000	1685281627000000	1748353627000000	1842961627000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
188	\\xc2f1de2c225dc82ca053710efdfb115e00493f80710546a5630492cbb6d4307cc62d7813690ce6fba9641dc980b3e637a10590c195a86d2d46b7b2ca69700963	1	0	\\x000000010000000000800003ac584fa1dd19f513ceae795a23c8178573b42ef66f78088bf1eb4a8b420ebe7dd5b9664ec99f6d672141136729c2799cdb45ee6790428e76014b51af7e52dcd98f79ea5379b03b71508196c1b253fabebcd4037192f17bf3c19f9bb270308b39ea48dd227c4f24e69d56a2d974ecefded7d2c0303d09d04fc291ab3c15a284ff010001	\\xe52234f37e2391e9ce6273898c04c3fe90fd9f7c7092b1bdbaffe3039bde99837571dd9d9021fb4202e38e43020d6e00f7a815d5375fdf8b83425f6f39d16d0c	1665332827000000	1665937627000000	1729009627000000	1823617627000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
189	\\xc5656066a7a306958ef2e223929c2386b79ec9f907a0e7a00c74112c8a74b724564eec29f605034f21ed8c0882c753d847ac0713f6b716374e8f5dc7d3f2edff	1	0	\\x000000010000000000800003c348c8ac66d6317af936f2b40915f9911ac7b7c2ff8733d95941b80fdd668d45ae27bed4dbfe6a1a7b1c501f042ec61041c33cfd40fd8daaa83ffa6acbda1dffee8b393459493f249b3895f4db0488af751249270074fff3fd1dca16ec417dc348578534b88db9ef4395040e551b718c9ea0645a516b7db6cdabab8df8b14bc5010001	\\xb49b4be703fed2ec2cc063c16bf8e1e668d31ebbbc80ae4e7029fcaedd9699b34ff329c2332177b0c94e762bf7a968d4bb07473b4736682c61fdb4932a45f902	1663519327000000	1664124127000000	1727196127000000	1821804127000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
190	\\xc5cd427dddf23a6400917d5ff1a6d65ebbdc53f776b1bf7e978c84da1482bb6f3a3855d2f0317890b07275f6e5ae91ba5de84327d9bd89d165054704fee600c0	1	0	\\x000000010000000000800003d7133ad8bb11eac3d91546634c61393861740981612cbc5bb0731b850e50403948961b33695622a5b46798bec17014a3e22a305923857c6277d65e98fee5249dd25b10a4756c93becbb1f794eee13fe6e849e66d55d40534e2b1da30664f968dd3df23cc20f1e292c4e60bd895b8bae5a7b24d171f087eb9a5aafc9073e3fae9010001	\\x8b04940df7feb42da070f20d3281810ad3a873e28cbc59a04eb717c2f18a8a3990483fc1839224af2c4a393c5a93b3f037777f9ab4b3327404200fbb9a18b305	1672586827000000	1673191627000000	1736263627000000	1830871627000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
191	\\xc7e57b96ef9f44b6f3322c4a65b6d34761ce5d5131b5f453258be8bd3d1daa33314645f193e697383c8bb8347d7e7a934d1130dad5b052a3e6b937fa9e9f66ae	1	0	\\x000000010000000000800003c584a73c03a87473b5caad33e83373d84b6b54ac9348a0b296b7441fa477e6869576a39309db687645c3096ec57973df990e242af1260b6a628be0d647d83da163f9dd356f7f673048ebe0a9a3176f42afc3ade9bca57d7412776b9a22f46b9899ec33377af3515a24134dc8f24db0e1230e792b57a21515f755889e91f5e4cd010001	\\xdcb09b13966c7490f05b65393df58352090f34bd5524c2d0aa9fb60d2d895fe82c14b6c48a3fc203dabdfdab6aa5747810e37fcbccd53a48f8407b281f357c06	1679236327000000	1679841127000000	1742913127000000	1837521127000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
192	\\xc8e5a832f9738f027347c392640adcd37fd95a47fba20d8e3cf4a88f2d02ef3994d6cdb7385d947ae0e88e0169abc50ee1ebd2895599c94e17fc9fada430e78c	1	0	\\x000000010000000000800003b968145ecd43f653cdbe794eeb2ad5fdf79c3e0acb60c3dad9fd04f3449de5b69af0cd3fa36c68072ded52455ac6ef4a0df324a450d41e325e556907d7d6ed0542aa0a8c1bd0d12798dbca00ae35ead678c73f578acd9aad12f6a567cb3e8ba793ee5ac711e98ae353b24f47ca54ee4008ef7793cd2b33e7f0c787665676c109010001	\\x623b959e605876f02ed498f41a31fd410fb19e4199db506413094768d0a7300946492a2baa1e1e6cc9a577666ae55440ceccafdcb9a5669bd267d7f6ffd4d909	1685281327000000	1685886127000000	1748958127000000	1843566127000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
193	\\xc9d50065a18dd90015cdbbd3e2042f7b63219797ab701d8561df83fe43d36bb13b4552cb81399a81ec4675799389ee40522aaf79a71a494d15ce718cba14d904	1	0	\\x0000000100000000008000039edad6a2ffa8789a719c19953af839f22fbf7798bf537f74ff4d22aa92cc5cfde23cec08eebd630b9d6f4b9fdb4103602c2b01968ef9fda15ea02580a6602ed7494bd07f8303a234780b086cae8b40eea22641e24220a0b91b2d38fca4eaace65665b1c38ef9548217906136b7365b23a7fee83a667ea50f497900847ce06851010001	\\x44a1cde04021a87d0d0fbe26281de4a1932d20256850505d164e4c3f185738f920e2e7e78bc0cfd84901d79a9de05c787f0bb71cb07e98c976ebc056d7dc2f06	1684072327000000	1684677127000000	1747749127000000	1842357127000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
194	\\xca01a5219c70919ce07d28c263b75ac7dcd865c73d8c50f6339d799f6ed4e04af62a17b935badd7303003ef56f3564131f63a76e766668c1844fff8b4fc1aa11	1	0	\\x000000010000000000800003b7783979d92613a662d5e453755f2b5f677381665b6526cf3a88f3925377c952a536abe56f3bd964047525d03dfe6c13b35be0c423b447485ccec775c88f9352c57117336dbee54ccab7651dee8c978e730291a6fab02602492429e99816dad070f4f3942685b7bdeeb484393a8484d72c12cd45ecc489fd55d3283c9555ccdb010001	\\x33b7136e8335e66b422b8d30f21a0d34993503daa31fc6bbc8624a8deb42ce7e1ce354d5e5e715527ca3a5b810a31eec12bd3ebe52b699f259b8247861e1f004	1686490327000000	1687095127000000	1750167127000000	1844775127000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
195	\\xcb5d1976c6f87548b852044cafeff682cb4c7f52f5cb116b6958448c5c93f7c84ae7599e830b62dd13b3ba03f1346b3513ac917385e82e255072b8369afbfdb8	1	0	\\x000000010000000000800003d698778b416fa3ca6acb5765b1d0be290eac03df247e4079b233378273eeb95af047fb66fc201b9d6b235aaa79847a6771740983da15ed9b68c048288811bd321b369698293f7fb499c7dcc01c9037d859bed8d07c28de801fb67a1068f5617b83091a7aaed15c96e8879ffce0158b46990313fecf432c417ef794b2f2830c51010001	\\x398b00dc3097f340b4133798966593cea20e107db1dc23da605b1b06fd0af51aa61ba742567d84712fa70de72b3c0f4b0c3ab5d2b97f963ce27233527b39440a	1689512827000000	1690117627000000	1753189627000000	1847797627000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
196	\\xcdd5ac20fbafc750d070570828cfdaa694dc3e277f342f79cec849e0f8d3b68c23d40921c1002e611b3366e324b134ae8719560784180432a43b393cca5ee1b0	1	0	\\x0000000100000000008000039e11d1a639cb2aa5c9132d438721d7606336061cebb795443dd90bf097837fc307b87b24d998598798a538c4632d63dbf57d4463cd59091e5f62ef09203c23329215ebe2908d8321e358919c367a0a5124e8880e2d950d27825f4c6707ed3938da794a8bd3cb4299296057c8b2023599671481342c107de5f7a8cacef2b2282b010001	\\xa68789ad5e2650830f695e2c12504d719b4a95d6443fceebdbbe039d220da8779cf33d84ab1c89605a73449aef8eb4771220eded5b3206ea5f6c6acf6bfed403	1671982327000000	1672587127000000	1735659127000000	1830267127000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
197	\\xd2a5d5c2a59ef919db2eff13fbf7c53af33e41a76c318f0805c6ccb458b9b123849489e033c58eed470d356dcd1d98bcbabedca5034825d940ea6ab1b5d3ef82	1	0	\\x000000010000000000800003caac502be0cb367a342941edf7be69b968f7ea7ac767fe4a2873da01a8631474c569be2bd077633d04e8dda811bc32a37cbdbd3893ef5f352cc871721ce073e8f04c94291f0fc0fc314d92a01e605c5e372db4231c69d17006e307f1efce52bc2836b09de82ad0d23b57eb56090605eec92d284e88b8ace7293d3eb3d709337f010001	\\xfdc0949f158e29f1b07b07d8d73fa1a27b85fd9e66b38ec3b1e3ea71574da004575a075fdce9d216b290653b013b0f510d6d0689defbec06a3784da6b5269706	1671982327000000	1672587127000000	1735659127000000	1830267127000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
198	\\xd579a3389a06e4e7648b81cc06d2b0259e67d6b6980de700f7b8185686abbe3c22d2bc773cd3f1663a569cb6f763bac27d51ec066e073e636c0a9fa2c2f8b328	1	0	\\x000000010000000000800003df840105c6cf48f430f405d7fe9180dca6dcba57a0a97669fb84b0fa0f5c8bf1e7c85e5e75f773d17a0d5381d74a50236aa8f19e90fdb9c17b8008ebe59310eb963597d14ed49889f9548053f7e7767a50e153bec3fcbd04038893c91b4e008927ec067679a7b51086091b4e86a8af0390be4d9a3aba6e98046fad860b06d651010001	\\x8a3946900536dc12a986d439460318846822bf9d8fef488767ae7e3ab83f266728fe8ba694a4c6e0e4d41d125d12fc2cc077f234b1ae01084102a3fdefb7c505	1681049827000000	1681654627000000	1744726627000000	1839334627000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
199	\\xda1d1b562c9f1cb2b23431dbd3f243ebcf27e1c66634aa1e9ceae0e86ab952d66dde0a94d453fb7331bd5fdfe4dc11ff64342b31c75029a0d255534d8f427b2f	1	0	\\x000000010000000000800003ac90bc175e775da6bfdb542f837ce9712ea847f7c6df03f21da46efdff4a5bd9aefc498bf7515c54dc172b54d4be5a3d64327aecb9e9e452825427610983f18e616b34e01f6b3263bc201d244a2bf76aa4ce38d10fbbb7019c17bdb24a8e75989d31b20e7b617868c498acc142a8b43d27f24eba855098b38dc2c47308d6553b010001	\\xbd67b96d7fbbef927ecee87114eb0c984533f9e4a9788bbc6deb3350d191d48568a10191dd23003bf6b807ebbb10232d3e5301758406c3e6fa163ed4c74a520e	1678027327000000	1678632127000000	1741704127000000	1836312127000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
200	\\xdbf51f6927135ea24ef47536a69515f6c17d5c6ffccf11c41b4c905ef464ee56b7d063beeb12825f54702623f468c2c6dac0bb88c88c2aab03f924f02931b3e7	1	0	\\x000000010000000000800003d3812c2a60cbc6359f9e4850fd2bf6ac28b31e62a24046079a5c097f9d85cd93cb09afc446ff01142ebaa1a9808f0208855674b892e9a759b61f6f368e23a8034cb5d24877d007bd4c39a2afcedba6a3d72ece4d80f422fdcbab6fa7de60a0cc57d683dd24647f82c2cb52b277e90e9b76b4a9ee7124e750690f7b004eccff5b010001	\\xbd6e05598bbec3fde6953396a85368f93d15e88edc8503228d61fc381274f1181aafe53b74490e56c5c19a59ee4a8dc411b2e255d00804782e3b060e35faed0f	1682258827000000	1682863627000000	1745935627000000	1840543627000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
201	\\xdd4d4d6929bb8c26e20e67cff74aa448c0ee5782ad0e19d9abc71e6149ec4e46b121a0800016e5ac5173538f7c4fb099ed516e3dbc3c8cb6b775002f9b6aae06	1	0	\\x000000010000000000800003d9ea2e937a931685bff1ae6941acac6f42860e2fc513eb64926f4372914626a464a78caa4acea6f882dc897cdca5f973458448b2add586e402007863c48639b7423e90082ee6def0c52b0c14597217bd69c0551785cb1af556ae56c499e26c185f1b9579f987947b8e53d1d3220fedd5ea8820777bd0b21abbd81b92c395b147010001	\\x18eaf2660e6a82f158af3359a2c16a120645bb7bc6d3cf70dce8d8d3d55e5cc0e03d87d34fbf1130734188af8fa6b373bf18c205dcf99b09feec944929706a02	1678027327000000	1678632127000000	1741704127000000	1836312127000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
202	\\xdd3595a3afcf1493e658d9611aa0628b6fefe06a171249798bff43da8d3f64fb739fca8d641257f6cc5e7f5c5e85ae644ca086d38f829793ab69fdc565bb9158	1	0	\\x000000010000000000800003b682eb4172bba3c053211fc34af794032fc72f5cce3c956b17341f059611c163f8c14cd34eb45f009debb5016943879df8cfb00d397d8de1c1bfcf9336dbdc34d858ef4ff0679739d7babc4eec85c96bf3e658b696b09ba5c1444bb02cf3de420764201a36194148013afbb5e010ebb2edb26c17d5a9a97550122beacdf553ff010001	\\x678956faa94d36a79cb176531a5a319fb03bb2105102f2bcce5877e61d604457eadd925970598ee35da60a7d15435758a2b5acc360f8f39221d4f2b42049340d	1662914827000000	1663519627000000	1726591627000000	1821199627000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
203	\\xe28d5bb48237e26fb7611eaa579e63baef978479c9c03069a07c9019fc07352685958f239031cf516d3285ae186d332a6e4d9180750fb4374686e8faf2e7b43c	1	0	\\x000000010000000000800003ccd7a6d8b152a5bca6f4f8466ef046b822bb3058916f0fe7885f9f15e6e2e45bed9328071c77c1cbac6bfaa82d1ab929fe6ed2de139e44580a4b3ccaf512e4b0c377c9527d840241c0d08ee7be2011b4219798ad26507d7be482230ba8360e6f9350e991585d6472bc0a5f1a90296d5e1e4d629a3f971bb87b3f964483b72dd1010001	\\xd4337c75882cb6729db9b13801eb03bce3152f8fd00be308a052df934dc09a0e7d2bd3f2865ea9d89c4803eca956d0251346b13ead806bef36bf6f7ae1a3b904	1661101327000000	1661706127000000	1724778127000000	1819386127000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
204	\\xe835bef62616fe619262a4e38a01712bad71225686b66e9d9b84b0e2009a19ba523387a9dca1be7e707d25e8ac414558d5c57bb39b97aa5270abcf699eaf9cde	1	0	\\x000000010000000000800003c870824031fce4780fa90f02b283271eb45de0652b6e495e1f2f877c47151a409edbcd39fb9624251e0ce265f02fa636f940beb9a8efcda6435aa777d542c53be7802a49c5a917874fa49d4f36d0913178c7137af3aad5acca485825468676699486a62eb1f4cbfefec39dc8e0b572e24cb843fa3a161eda19f36a136253134f010001	\\xd904177eb2f4977a00a337e411b9adb19b40aa2d8c220448268f16516a89727230d162c947449adbbc670777db2c4045146e0a2e8c5a4f66eedbd4a18a982c02	1688908327000000	1689513127000000	1752585127000000	1847193127000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
205	\\xea8d8c23d70ebf4dfcb60a570d92818c9e0257d2696689a813646800239c0ac12dc5d9f8f373874e2b46cd91e3e04b26379b0106b9e1693d32d9aed1d153974d	1	0	\\x000000010000000000800003d966677be3c0ca7d2690d914b8be34faf9df9ed42c4864139d310424e35d0eaa23a3a6ecba3935424694743db88b3a687a541e1666ff7019a323d7421ab32c71a148da9dd6ec60942f05c179074e468b5e9c6c252dac5224e9cb4b5d7ac36e42070334c2696bac542c297bd65ca924f1dfe858272153c397cb868a7f3f088b93010001	\\x362f9ffe95418e7c751391e55d0a6a5d5f80bd3cb41a4fc039344025f3842e6a8055fc44fa1c594836a92d3d6222f86036e7622a03169709e2e492ad589d7d0e	1679840827000000	1680445627000000	1743517627000000	1838125627000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
206	\\xea35c4ef00929404dd53d1312928d7ce6732c5a1fef7327558843d6096d123973aace9064394340221f77709618403e028496288a435a895f7601f7b03d254f6	1	0	\\x000000010000000000800003a570e79d3c814bba08260d996179d655e61dc5961c7e3928c4b61ae0457f1b2ef11bf4c573ebee0cae691004f62c27ea6602f3883f70d992ab1b80cf96a12195aba704bd577c87e5cc1d59cb0ef993970f404317255587cb1f0ae9a1bbdc108dde7558cd272357e345c9edfb988b20e42050b31ff99612b43de2a9c500bff06f010001	\\x02f77a6147c3f2acd84cfdb2ac72474a2424b8fa3e6c20ca9f0566ae262ef5738cac69fe50d18064a8bd6b1d17289063249da5daf0fb934aafb87f75571cbc0f	1688303827000000	1688908627000000	1751980627000000	1846588627000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
207	\\xec3d86d3c794dba5e34d5f555dbdecfee7709ff0a40fafc73e0dbad069ae3e05411cd902eb7c7b231bd37408f838f9cf245871fa6522e89373198313fdb05da8	1	0	\\x000000010000000000800003e3d356a11d5f32bad32a349ad898b40c2e9887be4db30829d9ff48a494cc7377a6c8b4aec18ac6952f0e7a62b7f4043b6d008b70a44cbe3deee0154d92e67cf5fa8c8ecf37fc9feb890edc9ce67330f765608c7c64464b2ea08b811f925d71c0efe4b4a389892a5c44aef076667b6e891c5d3eb27bf8b11a429a0af22f934937010001	\\xe6338df7f5a8d788e2bcc722e26ee89e2a2d4f72f0e365f234c426c4cf18f5dce4c04de0178c56f5551d37737daa618d574c03feec688728d687ea931f83e407	1662914827000000	1663519627000000	1726591627000000	1821199627000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
208	\\xed756f0418104669fa2f0653a7ef08a4d5381b62c451bb996339f7ee8102bc5b6b63b9054048100006e6c4f6f4d52e35c898bbd272d1b09f80951ff43c31da97	1	0	\\x000000010000000000800003abb6c623e5bef5566883af2625a3f9b7808fbd5da1031ea3e3827cad7686a590224282e52eed787b54eb7a6c24f5a2cb41e7a57a4f3b89b33ca08393238088dde968e41c7f6b3bac6d399b9e7e293a3bc4cb4bdb80cb2ac5a0e546741134d328fd6aced3f00bda93c39c384375f82b8aec6284be8be9a36baa8714bdc82ac62d010001	\\x434708129ded9166792e1cc91b892ed154bc49493c129a81d18d94e5db777b0e188f82d2a22130dbbf0c97a1248b8917f506c178d73aeb580a5f6f0b7642ae00	1670168827000000	1670773627000000	1733845627000000	1828453627000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
209	\\xee8d3cd3a4dcb2b54f92fc198fb4da67bc416bd8336839bcc6d07afb716319e3db0403139026d40d20cc394716bff5fd12de6e932efb6c97a6063cb1eb2c9011	1	0	\\x000000010000000000800003957071ec34b35759d579046b2a8163e0b8e43f8cc56bb86d3dcec6d2bb6a4925d153a1564e871c3f9a494b61e96b8c118bec6de8b13654da96d6faa299fa53af5ce9e1cece865392e2663ffd18b44ffe5acee136a743a88bac681516cfdadc74758fe0805447a5c7d689909f7b5037cfd6431cedb6552b2fb41a05c2ac7e4213010001	\\xd1cd048a7bf4eae70b3532b58e161c3ced7365365fe70103ed5859f0cbb6d5a71d979f84020aeefd7d7026d813aebbbf082513122199353de5b4a77ae849f601	1681654327000000	1682259127000000	1745331127000000	1839939127000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
210	\\xef55af7a6e916310f27e7ba6c69c0092021c0db0643d97a30857724764c583872b4ab3fb3c1851d53572c0f6c2842ab431fb9c5b74662d056f443c879e5f15f9	1	0	\\x000000010000000000800003e82424e0ebc54dbdcd10efea6b8853285ddba41bc497a74964c83dfe6a0ca54b81f68c67e7b41b6bd9b09c01f28f4e5570a48227b6ba02eb56d5840d2d5477a89de4cd779ac95abadf5b435b24b82f870779e6c21e451244befab05c11a0d55aa72747888df67b1f0c4fc756cc82b57d7dd7583ed5905c036e97981e595bf881010001	\\xceea88a662f7ec07f136df08c4b65fb7d3c81bfa77549c75591f2785275c9e5dafe0987a4629eea45e34c560a3c3a17ce1974d11951fcf22ba900f9bcacc3807	1679840827000000	1680445627000000	1743517627000000	1838125627000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
211	\\xf37925f31a3bf61c15e1507f83d5f06063166d89f4349310e5b27afd805975f8f49be6405db697c220a54dc50e5ac8ecff4d2a1ac1b9dd52d4cb88ee992f2377	1	0	\\x000000010000000000800003cf3fe14ce3d87f073ddd319a2c19c27a5e739eddfd72f0388f4e188ae459def9c7d18de00841869ad50258d178243c0ffc5f3a25d19435cd15d7640e201f124edd72932cab538430866897dda959286b2b5ef27604a4c7fa9774d4d68dc161bdd544beef31e7f260db79e99b23ce0bb4c2d00c7a8bbeb655ead1c8ce0af4b7d5010001	\\xb2ab47cf79bd75b1304e5582b6eb057165727fa95e3d026a7c1ade05979d8e1c746376772e00ce3fae486011a79d97319e6acee123b8062f1befcc3f0bc8f30a	1682258827000000	1682863627000000	1745935627000000	1840543627000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
212	\\xf345a0ae07476d6e8457ba2f1e9979d88eb9137a00ca603a5c9a0821ada386951ed0ffdde9ca2d437597280adca6c72aed1dac0d4e4b562277b7c20d1e826176	1	0	\\x000000010000000000800003cdacafceb69ea29ea8b9a932d092328df3d125df2c6f71ca0a2668f3f1fa802066f25620a85fb0f82f0a56dd95a8b0f2f9e33cf6f51adb701f7b14eda58e651a2d8161b24cd20f239c8ba9b4a157b86168263cd73bc6ccdb791dce3beb970f1705367acf1f506d1a2df0eaf58d1a39029ee9aeca29dd4e3501013528f5421e03010001	\\xf7eeab7e93f4649529058c78418c0fbdb06d98a33d669981d7e55260ea3a8e22c3ce5452dea2dcc692d8a0c3f024401d893af6a490c239ba5d56b867a1a5110b	1687699327000000	1688304127000000	1751376127000000	1845984127000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
213	\\xf4b92883329459b37ecc3c337835d4582385f8604fcf33eeb9774c2c16b5b43796e5c8086c9aab60bff1d90256c14f47c1f46c995d6d63f0f269e9f1de7bbd6a	1	0	\\x000000010000000000800003eacf12cbbee95479e2e82f5ed0e26899287faf9dd874c7b0725ac5acaf522af2b91e61a73e2e2a37ac980313331593a89f0fb68f33805b22b2e7e1e149311faa4f44de7d023be74002eedfee3a05fc0d909ae4a986b41636e21e7aea4f4b43f07e70367bd2059c9d98ae5ff3a1e9bbade36442ec209a70bd36a4f83a9e7edc95010001	\\x3e43ed586bd2840d630406c7180abb51f45ea946bc3541b7f98a2148b6d161c04c2a5b84bdc48311eb7129e9835bee3d31ef30da6db4ae0a3ded00805cc96f03	1688303827000000	1688908627000000	1751980627000000	1846588627000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
214	\\xf46db14a391c72d080a576e7751c55ca9a43987490a54b5699dee513f63d3f7c8eedae29609647dbe68f7c31b5e7f3377dc955ad9c1145b4d37bd4bc81cdac90	1	0	\\x000000010000000000800003ce310e518b3cee60789faecbbc3f2608c8d28bb7358dfd3146b06393619e1705df582b4c5d8a9d0bab31f327ecaa4c7d4a4c6ed1c22843658f1c22c46fe77b3281ec7daaa9fc899165d3aaf1dded64afd54d4e67c9a2c3a0b75f223cd22f01ff5d8a6dbea08b30d34636ee04b78ade8f29c3e21639abd5aff3e00f38e42ee209010001	\\x76677a286f94ed29f30eab4527db77938e10e0d25242e9dcb2211aa1515cffffda460c6aae5f56ce5715dc1c41df891898984b699dfe49905351996586084105	1685885827000000	1686490627000000	1749562627000000	1844170627000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
215	\\xf6415a8585d5d23bc585e89e5475229d6c6bd580c4a0a0e3f0c2dd1fa8b24ca945db96c46a9e66084f7b59ba048a145155bc501b6ec6dcce2255ec88b29190b8	1	0	\\x000000010000000000800003be3274887c1997a46752ad03d7b7b2d715e6ac971f14d6946e967de320adc4bee53bec629e581e65f1c381277a29e1e8c998a9c34455a6373670948bda721fb9f8ff28eb4e1f8bfbb146e5de6eed9095ce584428cf3c1fbbfc588f6eaa16b6498c114e4bb1aa1902d0e1afaf072f4c0d8f0ffb69511c4d2fbadb25792a6866dd010001	\\xb09178ffa0e6da708602917d313c6004b7395844245cf91928137923d77bcd1f9a81b4e306c6c62c4f3f585dba80e0f570f9abccca2d2632b0c5ded3f5e9e90b	1684676827000000	1685281627000000	1748353627000000	1842961627000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
216	\\xf6054b55ed9c79d103a55deb087f660015e48b596d96ae5ce5c2fc8109504d86ae99c62e593edb08034cf55a301e7f4fe21f309defbf07bff4192926286f26dd	1	0	\\x000000010000000000800003bd43c07f03a7e59129ff4bfb125ae0326cf538d844ae107ab6d80543ff26e7cf3f38a6c03201f14091b6cba130fc04f3c2c1ef5182da116aa4afd7e1020928e3cba6205afc40e130f959e70c34a73f00e4928da67a008f738a42d89919408ca7e7f9127ae9ed495c89044b882cc891f3292d36ac201de46733815dae00fb6f97010001	\\x36e062e6435213a4d802cdcd58db9f1633ae6166d50bb87f703fa562d81ce14b3dfcd24bb42e601bc073f92a033e039c0b095e19aca6129b5e9970f6d15b2e00	1665937327000000	1666542127000000	1729614127000000	1824222127000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
217	\\xf745d37faa98517345c65e391d91d59740fef918433ad1a394f2b04fececaba279097d75694b26b804546a1d03fb8e5d99ede755a7a9608b1cec9d15d2b17ad1	1	0	\\x000000010000000000800003d173b93b1d25f9cc01496915a5c5bd7db6a13087a26317dc58475138d8bb9d7de67f7dbc240851d0743a5b4160dcce250a7efe6623ece80cffccaba3d3e368abdbe749bafdbbf2856b724e1e47d06c9a63c77fae130b2d21a1343b759bdd15aca0a220a5489126dcb1de443589b8e8f5a55a12e8854ce3fe377f151777c90599010001	\\x2c81f765786ce35c5a9db06845adf21612741d964ade5ff972c389ca15325e8e38e3ccd2bdfb823a1844eea4a73b2acfee5f743b9330c883f96e0a18e0991706	1689512827000000	1690117627000000	1753189627000000	1847797627000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
218	\\xf70d71e257fb595c4d664f2c7f5f386d2d62596d7c27a74a28b6c4a231da500600cf94a1334d9cf0c84515b33388a4daf3beaee83a3448d3749b6f383a822e0b	1	0	\\x000000010000000000800003ede514100fb6ca9714bb286a6ecbcc382ca0ee59e5c1d4f48ef345dbeacbf8ddc01f4cf8d2f9e95822f446cebab8bf23f6f4b16295fd58b74c57d34f34edc55f7a37edca3cd9d9c0aa5a879454c406a4c0388e4ea372f198d3463946e83caa7f4ccb13ba0fbb97b82f9c6892513ea1d522d53a9169be637db6d267ad2c6ec03f010001	\\x681a354603f23957a4d8b73fd1728886e5b0e62f78ff356b91875d507c0c6ab3c812f59839363e860e8c32ae9fb19af4c7dbc8a9d4763c37a6a8875dbbc65806	1661705827000000	1662310627000000	1725382627000000	1819990627000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
219	\\xf99d42d755360ed1da9ea548894a22c7477c9fa1788d172af2a90fe08014766e9646bc8d4ca323a9fa4f5e02b824fb504a8d93429e837ee626d943dd977ac5a4	1	0	\\x000000010000000000800003baa3357b1b903b269ed4ff933a2a295ae90317cc3cfa9b4a60b108b025410f7fc776a3249695a90275e0ed163d4781e7b4d039ece776de0ec8c3ba960a508a28b70b5bdbd1affcedfd343a75717a0bc8b70da6407303054e867004ef1196f7f8e3fd51a8582ab1a79b3d4ec0b7d9d522fe4bbf145806ca96db02db29842842a5010001	\\xb1703402405219415f7887b8edcb6a967331f16cef19d8440d190b43807886aacab866dd64539bb629398a908c3a1d2c731c1028f9012be434092842e7568405	1685281327000000	1685886127000000	1748958127000000	1843566127000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
220	\\xfab9d8ced7526c899617ea5ef0396a8c7a61ba915ff0df59527d484fd8b5b3b41e8704a14e05315da2d30d5c9486df8fd361ea8915f4fb2388738f277c1a96e3	1	0	\\x000000010000000000800003b3fe94cbee5512c27a6c4d3a64a61eb1645e5f55d2f1550f84cdd3f3791f25d0aa968acba94bde95419c363c1678d19153eaedf07cc7d0c496822997f8bda48c0a46989323d666c4c3dfb02ae2bd1acdf1d7c2044276ef8b9c335ee793fdb38420cd5b92a5a8524117651efd6b9f81301a5e3e4dfcbbb7d8f716d80874d5d45b010001	\\xb9d45f74c4a3a45cd7ccdfe9b7cf325ab6be05b7db702e83f5b1ec95553ac025b9cde4510b3bcf759385f27698c21624de6f92f657456f841ff9958005a1ac09	1675609327000000	1676214127000000	1739286127000000	1833894127000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
221	\\xfbf183154f4842957c7b3dfe8c733b50ace6e5f9d9a39edc5d08316d2d8f331b7022ed8b8c4e0bb30b711ba528094c5e64b34c48b23c822f96501d7055638bbf	1	0	\\x000000010000000000800003c28fc6667d16f934d2a4e7fd04e8789e4ec2d9f5b6f16219c1da62ba1ece45af5dd005ee1259225d7026af56edec9745138f603fb713d1c5f44ed7374c06d452486d84563671c808adfee3fa9ae8540a6cc69cb8e8ff9349ce84950eb436afc9e492651f265cc94ef7a1a2dfcc55e2ce18e920a77499a730aba3b5808d2b473d010001	\\xab3f6afd7f3ec9daf1a0d5c076eaba100218332d2dc39b8dc0cf8056fe93b40393b1bc7593c0b53389350c4887efbbf9aeea986d1b5dde5e19e82f06f7b07b0d	1679840827000000	1680445627000000	1743517627000000	1838125627000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
222	\\xfc51f5495116d5195c07b4a7bf46bf38584a79d38cc96366ddc86c0fb56cde1144bfa27e85de83843ddd425146ac7a1e184dde61a2455dc8f685165eb82791d5	1	0	\\x000000010000000000800003e514584a352912f3eed064c70495e1b5652732bc83ecfecf44765beef9d57c0513c9ff124fc87a5d5cb5b4be2eaa9b00e07c3353f1671bab8f0f09c9a458a4d427d994f912627ed694c8d25132d712f9459c9eceec93a99c61db007a366dedde29ac881f7d2eff74a29d8714316d77ae4cc7f287fd544e13ea0428f2f2210f2d010001	\\x383693513d1a12c65c306556a801c17dbf892cbd7b459103f1e4b15f6d3109722ce6ec1a2f19578315f24a1db55d1433a62df7618e0aabb1b2932c21ee562f03	1685281327000000	1685886127000000	1748958127000000	1843566127000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
223	\\xfdf92fd693ef2c51128a8c4328b5aca17bef55f6d80d669ec0aa47e936163d1a2bfa4c70bcf3ea3a493ef511c9a382330307fa13ac633e0425bdeef2ee765d0d	1	0	\\x000000010000000000800003a8e09dd06d5a5cf6849ea17d2f088c04cd7a5742fde32207c0b7336c1fcfc44d1590d602bdda79b707e8c26a5cc70e026ae05d99ce3164e5756ed27daf720455490706a8f4ebd83cf3c9cd58c108e46a7f27f84ff4f45d8887edb3f4744277887ba354dd84a1d61f0e32899ec142e5dfd1186f39ff27a2853c3385a6ebeb5991010001	\\x28cad6e584a2b53660118419df3123fb097e15a1e171cb3d44606054b3c8cf089f6a2b734ea0dca8a8981f56656bf0a5cdcf14f0f130be6413fe109a0db12f07	1683467827000000	1684072627000000	1747144627000000	1841752627000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
224	\\xfff120445ffa61537248d58723525166fa2e2869acb163cbf9d0d2c934908871f46b3dd8e6b0ad5126b23c4dccd39d2ee1df27ecfa837c1cba354d7b3095aff5	1	0	\\x000000010000000000800003c09125d56ef936a9ae9b577de72fef6dc890934265a8e99960d589359751a565898785730be429ab0b69d14c7206e7eb68d2026d3a45485a2859cc3347bdf649d55eea85f0ab5a0daae9e1c20d750c627267ba14ce7a9377b9117055d2df9c195d1e043a485e6f7e417d869a401eeba20a8def0f18680ccfff9d84adffd6391b010001	\\x7cbaa0db8acfc3882b1d57d022eb8300be3326a48fcfbbbf787799c62c64ceac42b247d275ef488fe96ed9168cbe9c87624e9fe0f84045c4ea2790c646e1740a	1665937327000000	1666542127000000	1729614127000000	1824222127000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
225	\\x0056d106f5dabf04998dd5447d89ecc9ccc61401b57012e6f17340eeb6c6e3fc479de9c190f7b6ae3ad3661aaca722cdfb738af44ce46dda4e292dc76eb2de9c	1	0	\\x000000010000000000800003afcb1760f9109a2bb8565ed915ef6706c22d9580faebc59e57d13de897ee7197ae3a8d80ede5b8df3608f51bc0991e82d893ca74e70062b25bf8039613acb4bf3e562c62813b81e7e942a431b502e5d0bbb34899548830e1f2caf25e896dca5ac0d78017914fca351d8db05eee2e8d9e37ccf8b634e34f808a67fb9e96acc76f010001	\\x4c26b9618692fea318eb0144546859f3c4256c0154720b7b9a5e6014956ed4ef6b6351214f81c981a12d8b1c8aaed2337b859ec1bef191f559907cc68fb8ab0a	1668355327000000	1668960127000000	1732032127000000	1826640127000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
226	\\x0332adc75bba4fa8670789c9f918b5db0b316f916c18c0ac5cb3c5a426edb51fbc8336513fa3700773b4e3bfd73e68e182ff27cec38e66e49c55479e5118488f	1	0	\\x000000010000000000800003c62d7f8cca53eb48476372f34d50814e7a0cbbdfecd2f3444172f73e16dd6af0cb4d3815acd573b075d17c366dbbfc426bf9939665877d0b4f960ee97e6c2b4d95907697fc95fcf0f551f023071670f2dfa1f4381f7ce963bf9f339532fdf8ec038a8f50a76e2a6f7fff1f38bd3bd549ebf00ec3f016567cb4dc597909725605010001	\\x3a48d724c18005ec8d84b550bc1f2cd87e7d0bf3dee7af06773aab0f561a2e39024687641ccfa34cb801261ec412adc8c39d3fe0455d30bbe690b35284a56601	1674400327000000	1675005127000000	1738077127000000	1832685127000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
227	\\x05aafc3b1728b5e52270a95ce05cdda1d40fff9d0618d84664ee6cf8daeb1d1985c48fab5ceebeabdd3db2fce07aac93eb2951cc64c0379425d2d92d27f74f0c	1	0	\\x000000010000000000800003bfd85119fd6f355c7c51d6e544eb2b85ccd23e311dec1a0192cda9141ee375b06b3b34d97c21959d91b0090bcc3d6c69abece989bf6a58e68e4b163521aa5d09fc64527ff5b48b70b7c763b0195f8288ccc449dd6851417f5dcb6b1f65fa0dd01d2122b7bf4abd333fbe7f449cbe0a57bfd40363f0d82ed7881cbae9bf814bed010001	\\x15cbdaf5383faa435e234d6cc10ce20af053b74f834b1f9e37373c8f36c1113729a5a41a2e9ba6d68a394527cbafb91994ff103f1ed2657ecefb6efa74948402	1678027327000000	1678632127000000	1741704127000000	1836312127000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
228	\\x059af7382b37f3ba59f3533c35263308af0d3e13da2d6aff54a054f00444559588b44b673deb21e0bb79780359333fedd8d5d31bd7e45f3675653da595f9ed2e	1	0	\\x000000010000000000800003c886b6c2265dfa87c46e530c41ac52827b60d02c14cb04299a4d6fb3f8711bde711698b5eecbec2c1bf9aaf8c3f7a306c9a1de49dfd60647e161c085d5d3bc1d683670994b702a293e3cdf9278f6ae27fe1a87f0df1e26cb9cafb0f33579c1814d568e45a5f71a5bd4e08f8bd72c3d397a415f1e36498d990594744c0c16a4b1010001	\\xf6a02c2098fcbff3cd90b9b8900e18341f038cbb5777f6c731a3a39cacb7f24a5514ba2e901ce2b85a157498ee5fe561faa0a7b08f13256a378e485b19ea0202	1673795827000000	1674400627000000	1737472627000000	1832080627000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
229	\\x061a3341f7d44d2bd4b22e73e9cbf5ffc34d88522426b17adb53a6df887cd69fb3705a68e5273254f98a3f80baf665ea54d097860c69373b1c22358d6d70e021	1	0	\\x000000010000000000800003cc394b7848b984b5144c9d31cb8c4e813207152f3df95000991c7c707801a0b665779db801e40c6fbc81ad272592d28f9e41a4eda3e713a04f614ce6882c6b44e5c11b88be01304e9ee3381371f9d034302c8759f16f3f851934cedf31bdd73e2eb50c56f8f6f9ce8e098ba6b30f9a5550669e7dfde07630712774d6b2cba391010001	\\x19275c0f37e0f3239d0c4cdb0fbf5e8ca513605f04f64a2a9ecf026b5ced979def84e80096d7799ace7f40caac456e15f74d8615a65656c1ffc1e62e4b0b5207	1678027327000000	1678632127000000	1741704127000000	1836312127000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
230	\\x07161a7da063d3e7efe5bc198e4e06eb3baa6c473bf2f307e18f17c10eca441e920eb60c2d85506f2e9b8cbaada961442fe634b82037e106548ce22d49fe2d15	1	0	\\x000000010000000000800003c8fec651b0bec89cdeb1d0c56ad664555e0f7715530c9f3d06852049525e46908f71fcea814e600ac5441520ac3c4ff1659f4ea353ed2a52ce9fc6804005642eb1f22b9c71eeded8d42a11b230b3bfa7c8bf787edb0ccce96ee7be54f66319d132429d4b29489f73fb7891b3470fd75950893dc4f1aa501db504d9a738974ff1010001	\\x735a5a198aebddc7932f967ebbb68421d22d738ca1f86036cfbad0ab3a5f787cbc3bc7372faa006969b17b240f5d29c183bf7fa811f36054f9cc20e6da77fb06	1681049827000000	1681654627000000	1744726627000000	1839334627000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
231	\\x07a2f6329c8d77ba17ae126ea973fa221d0c67f0e7612bea2d45d4583dc67f5694ab2363b0bba7a59e67eaaa7933122d16cbf5ca63e5aa76ff773311a7e499ee	1	0	\\x00000001000000000080000396e65c2f398bc22d4c3d3854505f461810db2334e0b98617849d0c4e4af161b4661bdd0e9967ccba4c1d995a54af4b760aa15f4f51ca4dfb2cc568379ee763b0350f92e813b10558a5cee4cb034f176be4385a083cf90997349f60081ff063478a2bec240ff21cfa7c34096f72f84bb94b2f9884fa410cd45b1f1a234006b2f1010001	\\xe5b1e653ed1a047d7376f2940c48a19e5840e8b2a1a24bded36d629ada3a55faee1771154d8883fce35b4b26861eabcf1e8c0d1804e11cd4e528d5531add5d08	1685281327000000	1685886127000000	1748958127000000	1843566127000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
232	\\x08f60a822289a0f3829cd8580a33cf8ab4ba32980eb257d1bf9e5e09db0cf3268bdb49f5fac2cbbd73b9c6bee6e93855eea6c2b37a3931eb9440264aebe115c2	1	0	\\x000000010000000000800003c51b1a1f3bce8d7bb0de62e30be1532e3b7f3548814ac73a79fdca7225325a95fadf4f632faaed7dc68ef101c395b46c1fc6d9a010ea47ed040c7a1109fa7abbdbe35ef4e3c7ac6fe991a77a1efb39d18afe1c4a3f0dfb0cb3b7813b7367aa462ea8d01a03e1f3dffc571ef2f87184516f88a6187542dea4263ce4d81fd81cd9010001	\\x50e5a03d06c2633a0111c11032397623883ffdfab6d11192f037059b3d240e1e4eaa55eadd2c46a660a09bf59132ef8cf5cfc76f089cae29b3adb23ccae47900	1670168827000000	1670773627000000	1733845627000000	1828453627000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
233	\\x09f6791acc2846dc45826258043ef1d5a3f03660af3ec53e42aaa63e707d2dbfcd03eed95007c8430dfe92b3aeed75fa9a7de3ee50544c598c14ea91c884b496	1	0	\\x000000010000000000800003e09147a482d7d42eacd8eed52e5ac739b581fdbff784f8fb2323c995f972fad68eaabd038f973d1daca51eb7048c3f0d88f43f71b099d1a6b7d5d25c4ea10e8d181bd55b458018d8bd46668b690810acc183d91f7ad7a2d9b3ae5dc98d1f751ed5946e07dcd68980cf2feb133f5cd9491c67fc07bc139b0f1740441fe8fa5e29010001	\\xcd8cd80d1a11b2cf22e1e8944e3b6947d5244a5a6968b4e98727a3a0cecccc2294d4f4fe8dadd14eb820475dff99377f6158a4f6083c316ea33301368d48440a	1668959827000000	1669564627000000	1732636627000000	1827244627000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
234	\\x0edec64a11b41775474640f64f6d2dfeecf9b9a80d6dc146259b2396b9434b471295146f56ac96a7c6d0e6dbd10b2423a47969895745e6e241ad60e9fa4b5719	1	0	\\x0000000100000000008000039758cc0670794697a2517b9b63f7bced29e1f707857daab8fe034ba002a7bac4904e4e44beeded8f84fb58a90a79e5ed6f167ca01dd3763d49df882028ec9888ba493e0779dafa2075b6f8fef5e3c398b4d650a44bd29aa201a1c4bf5607452e7352b6615f828074bd8cf32b712a221c70f402c48925f2e0a8947fb975adc4df010001	\\x21a25c7081d856973d45cb242cfcf895118f2743d40414c82fef780551d1c312eb7354090c741d2464ef8f63d8d017250394f5835339cfc64b1f81f6ddc18809	1682863327000000	1683468127000000	1746540127000000	1841148127000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
235	\\x14de9a2ece451453461f3c60b699f81b83b13a47a3e852ebf4965e7f396f0fa0a0b3a3a7dc7a6632171b4bcf741a3e9c70ff84cf215048c81f42766c5de60f53	1	0	\\x000000010000000000800003b4ad9e408d41eef91c50ea1864f1df3c7228b99ceb4030e4d2979c36436f45bf71f75c12fd4f61c785039c1543e439f1758fbe49f3c0b5350dc269803e1e6d35a7c2c05ba0791b543c9f37c3cc1f410cfb5c21e8eb56ea1ad686bc4eca01ba8d43dbe4b24ce5cca20c56c13fc0666dfe386dec1aba688ae22af3dd65a7c782b5010001	\\x61b962958f0f6df0115e6ac1fbc3b098ea3f3dc5782931fc6bbcecb6746a59d3131af916cabf09b740977a7ac486901be5e6bd1d5edbea0be9ac70630a855101	1684072327000000	1684677127000000	1747749127000000	1842357127000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
236	\\x18def3bc08960c1de15cc7e03e57c17d48b86cdff27f81a8b0ab88170c439951d1e5e9448990a25eca296f8eff5cd0cbf4c2c47cc482f4acef1a1ea03bf81a92	1	0	\\x000000010000000000800003de622f1eb7f71550477023f6b82fe6f84c676148fbb33131caaaa1d94c1773f20df1c5b855850080bdb9b41fb9515a5026d5f740ead2289e10fafd8a79317533657f8da66ec87964b8f5da5e9695a08c7cc2a2fc3cfd224b56a05cfbc8f0f6551ea498c61b9eb3d7901302761c9b061dc7e9448656a8c675b9bab9a9533243b7010001	\\x184fe66d6379e548010d66608aec38e34eb7bb677e0d36d5bbb97435fbc45db8ae2c62171e5f18dc580466387db1aab2ab5f0550301783222ee309be040f9d06	1672586827000000	1673191627000000	1736263627000000	1830871627000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
237	\\x2116e02f5a15ff8a49af3099720c3910e519199df58f0734f5ebe0d52925ab3890a18b4fc678e22909b3b9595e2ef412dbd4899ea70872e8b36b2012a406b2b4	1	0	\\x000000010000000000800003b1765ade9c809a94f9d396e6268411a6fc3e57d0d167aff154027480bbbd809cedf9f5596075cfe1a5697fdd778a94bf81447d8f354499c74d699ff8738b35daeb4748127a25ce8b783f7b1a9a9f42425b1eebb39d3ada893a311476f74bd9b0b4fa5ca179cee5b0a01b78d1d12076a0e907d045253489f5fec3c61dfd210f73010001	\\xb7b2ebc93fa832afa9a63fe4f4a23c57449e86dfa8ae6be1b2f3523c6f21bf0d9f888d4488a125b2cbc7f62a35605668009023bd8076d5fecc1a32a7113fe805	1673191327000000	1673796127000000	1736868127000000	1831476127000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
238	\\x23d687c4af934ac5c7258559da936a6ca94e50e617328c2f1616f39caad460c9cf50c38fcf82d03bf60d219697b8cfa7ef489c47f4d7e3329b5777f4f7de255f	1	0	\\x000000010000000000800003f66cf1a36ff262ae82862d4098ec13cac7c83dbb628da3982c5cf89c23480efd508b83248774ccc43a6e75c9268283d9ce47f64cbbd0303c46d032b5488fd34f50474374fd16c96e42f1da95712b8b4746f91f0c7f3f7075656171a8fcb6f6fc34a9449c1e09359a1f3d0cb1ee82791fb938e5fc3edb2c14ed3415225807f261010001	\\x0293ae96cac010c1a86ac4d198cbe69ded35c9e8a62907dba1dce9a5f79116b668a86e7db104388924014c367fa9a6ffe66c0b1a74d7bdcc224de0b536a7d309	1666541827000000	1667146627000000	1730218627000000	1824826627000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
239	\\x23ce875e32209ec7e443f394acdcf0973a3cd1a1858d25af0a4e590e9380d4605179e068d17ed300ad2511a5a222d5ab32b9e71f424a2ab63d23ac7851b53d15	1	0	\\x000000010000000000800003e1674084b6efb12d1587268e99118920547eb113a1d1af7c69e059172dfb2ac39833cf87a0f3562cf5772cdce8cd1fbbd437ce133d8d6329e09f47cd19de6a596da5a5b284832bb61d4151344da4df30c880f4be3e249e9d04f74321587661cfcbd6252ad33abb82f882bf7664b11f0cdc4bede1405259bb6d16f18b33955db1010001	\\x466ac6cf9f9aa08b6c6ee4b809e56f39149679a9b9da17838feef6758bfcca3ff51e52cb4ec90bda650f2d8766a1d53ab1314c6171ef725f2af42685452a1b09	1668355327000000	1668960127000000	1732032127000000	1826640127000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
240	\\x24068c44718896b8cc8d20e880be6c6f7cae53a4d599f007cc0fd4e3f9466336633a1eacaaf4ca129417aabe66c04628e1c5602a965d7360ede2e6d9234a07de	1	0	\\x000000010000000000800003b8b073826e01acf5db248519f222f5c034134cfc69a415fa70810f24394560dc712301da09fbceca9c910fe24505f05645be390bc8938ccde78bcdd7eb088c640efa3d2f75f3001ce0db7e7e4497dbd408701c8c0795f09947717459b04144f4bdc64ed07d80e47503091893103454e3f18b38aed34b52705575775da0ee2533010001	\\x215e9c0bb8d93162fc8df26dd88d0a818c1333e0eb09c0dfe62f4f17ba2f014f1fc8edd9d7e4768f3ca581c7cf93e42d9d95467aaf75cf6b5529a0dced1e7f01	1661705827000000	1662310627000000	1725382627000000	1819990627000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
241	\\x242a0dfe96126442705ac5c71fe77c028ebe5b831f035d23c5eb0317d16a2e7566409276fb221f0267c5df03b389fca38cb3a07106d3e9607a5fccf83f59a2ed	1	0	\\x000000010000000000800003cdb8ba5f6e51203255fa4d7f3e72ad0aaaeeb289254c6029f5fb582d918f602ad7fc9b3a185bad56c396131e3123ed0fea948984d881083f7ad9dc6d26c807cce7883b92a7bf6defa2676e6d451d52fa7a065ee2b0a428aeee74fa6dfdfae7ff872aa99c425e4be4967e558ad7f70269907ebe210cfa184339a89397d9219b13010001	\\x613b5df11027e2534965aa0bcf4bbc88d2a0650c4aff3358e2dcfea984bb4034baa967e5148e9ea6ec96343fd0fe0c56841f85ecc908b7ec3dc842d8ea4b580f	1690721827000000	1691326627000000	1754398627000000	1849006627000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
242	\\x26be2d1090856ce0f7a3cd68a6dab7292c28b3af71c536b8ef0356959673232d42fc5712169d3bbb60960f9f6700d1aa5147102e4ef0da93b91bbb096324ef2a	1	0	\\x000000010000000000800003c41a6cd6be234495a3aa8cb482c1d1f3f3b1696460ffc00fbdfc2cde599d4516a878d75e4837aaf805171c4bb91d24c0158b68fa76c854405ee294f5a69c7ea75d7959c077df23138b646c0ff42c98bb27e0f1dee2bb7beca3d7858904286a1b6882e7277f675efbc3659ea66b6ab8e0e821cd5a6c29ce0578bf97078ec05dad010001	\\x115b9eaf0e52802dd1ad56bdf9b8df805e3247915ba621ffa63c16418d563dd207d672ef610d4176cbbd8140e12ad3206b905e36675d34213e97c6799f7b1d08	1678631827000000	1679236627000000	1742308627000000	1836916627000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
243	\\x2c36943382cff387706553c74a524bea6d0d30d0d035015eda5d271a67b624a0bc4f018a682611bd932f91f7bbedb2fdca8cc45f8fea2f653f1a7f85acd4c5ed	1	0	\\x000000010000000000800003a8429c0a1fb23adc2fda92380c55189c30cfaefc167e83490bdd7f6aa8531c22772cb191f944ed41d6b673506d605272bac71e3dd77b28baafb2a189f799ab99f37bdc0847b6c75fd1486ca8ab34c250b4757839532ddb821cfeb3a811bd27ce8f960b7e7dce2b4d8e02a99bd96b1cea15c93fe653fe32a106b787d8d5f1fd05010001	\\x3043962ae6bb489bef70b5295d14f8ab72ebaafb9280e1b6ed28522565eefab3e8c3c21fbc588620d8a01e7e65acb4fea4e63297a4f0a0378160fe7a00d6b405	1680445327000000	1681050127000000	1744122127000000	1838730127000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
244	\\x2e8a02d0e2bddd5d268de91c00744c659eacdbbb95561c85eecb362865ce87c2ec787a214195bd90c2998ec319056382acf5d8da6cfc01d253ac9e43b8e90a89	1	0	\\x000000010000000000800003abf68e35424c7851735cafc14533c7c16619e0d2629221d1fa4c39a2986dcdbb2a37c72e2c14287335df5002db859060c9450cf308f8a49b87ac254cafe2137a075bb3af7797a79a0a50c5b375d88338fd9a4da572c1e23aaf1e80f3c54833c9ab01444eaa7086ac102a325955c27a25d9b253aa812a8fb2dd0ff82add8380cd010001	\\xc09e45ef0c731dbf0699d9e67111b70a9b80814ca803ddb2c6a804a3ee2257c7f823458df295e09c8fef718d50705f3463deefdfa8b6320adf6cdd353e084305	1670168827000000	1670773627000000	1733845627000000	1828453627000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
245	\\x303694aa3bfd3a09b00fa980590884b2de87febeb17316cdd5d21da926c40c0c2b7b83e2c28f21aa7320e1837f85439d28ae7a9ff51423e2ad1d68c59d3544cf	1	0	\\x000000010000000000800003c0b41edf4f4d0741735e786cc0aadaee15ce4557c5eb44ac2af6e0845361ad132d0d6307ef8ec69099ccda182c32d010bc91a0626c4293f943f20c650cf47ad9e817681c9602b1d4a672abdb4a5389dc566e4b4436a785e962e4c2b6c054ac7d38bd7c9d2e4a7cc3ba033fd64177aaa835b5ede40a1314a4a26c3afbf76d258f010001	\\xc442a593a26f63254e3363d09564af9540cec153170bb12a3a482b26c30b0d0f9ebefbc45bead2d521a026389d6c380fa42e5d20923cb47041fb4c6a17a7e007	1671982327000000	1672587127000000	1735659127000000	1830267127000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
246	\\x31e6f17228675108985e28490f2b93294ff93b209e0d14a47355c114914ac5f46c6e83c3fa9000a3f085b0a454bcc9981213a529fb1afc0274397d285188cd2f	1	0	\\x000000010000000000800003c322e817b5aee648f8a53b3adee54cbb092a4de5f408cf6703724565437ced296fdc25acac8397f7c51ea720154afde2f62c535799680c03b486824ed093ef1c367577fa9b705a4d901cd6918d72eda505c14aedb0e48f668cfb4924f888d723c2f3840f133b97ee11e3cf88a071b15f45a8f02e84c713570466ea6c49d48de7010001	\\x47228028193ba6f4ad50592657093e593e1a9caf1e5e709ea08eb6f045373810ae3e5f09736c6ee3195a2327a384c831da4b861e4cd14921982be02b7211d406	1669564327000000	1670169127000000	1733241127000000	1827849127000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
247	\\x32f6819ae6568afb8c80e877f317b4f11167bf98ce0ba9d7c98e2aa45760830eb9bff0b896d16600a4a348902ebe16908dd91b5a4cc940ebbd5b94b7e74d24e4	1	0	\\x000000010000000000800003bae009941b08f529ae0e8609c45ad0f890eb70ab8484264f7f7aeeb55da972634e508b8ff3f8d21146ea3570cc1ca2faab3fca0bae6980de71285f6441e5976996524899ff24954336c8808cec0b26886e709225c28d657a2b1110e628e532633edd279e728121bca27e8d02e2175bda38b7821274579d7a00bb5ef6e2151681010001	\\xe85a2c79bdd63c4bbc1e16716ca537c6bdb4a7747e66ecab31c46c75fb47f8dfb0755067203b9d6bf24dc7e2e4eab8fb4457aa12181b408afdb3589e4452310a	1689512827000000	1690117627000000	1753189627000000	1847797627000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
248	\\x35ae6b8842d1c4600c0538917bbf2050392f54ae34d43ce73290c1c7ffc374299bc73547dca27b2d31bd8ed92c3309f9e119957495a4cabf60c4bf6e09f9617d	1	0	\\x000000010000000000800003d6442318e6b181a550cb5f4635b9c2edeb0b1f88198dff07d02c655851c69335698d804beb707605f8347d13eb59272246036d32915ccb76c2a4d808ac63b1cbf267561fe161f2be9ff74b7a7a9405e271dfc7da69a9dfd1a171da52983a41fd7dc0094daafe0209d18f01492676cdc55a87800a23072903cfc56f9a9b60d581010001	\\x73a36f6703775c00bc9dcee614c993bb05c38f19eeeda189699a0bb7cdfe46eb3ba93de9711b50790be637498b80ef97f17a241a615f3c1423714240877ecc02	1661101327000000	1661706127000000	1724778127000000	1819386127000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
249	\\x3566501abbd39ad6472ccae2b5d3ec76f494ec3131ed9f0645e016eb522b4296ebd3dfe28513499455c9f1208240df488f50879e661bf1c9771e148be1b8eaaa	1	0	\\x000000010000000000800003e8ce5fa8d124ad0f20417594b0089e755d02ecffc17b6bf9e1cbfa797fab6cfe5b8639f98af36e89b1bbf1ec25d66fa75122a8f39882d54700a670b8154b78ea77ac7083e337ed8dfe7f55c02dbf0a9955718b19dee3058abaad00d05dfd1f94fa9c3adb3703025e2327a1284f2bb0eca50ca192909bc6f45ad0b9db485def93010001	\\x90fc83f9f7a9716bab0d53dcba68fad1f4a8874973d8b1ebee567b3be55d194c3e26bb81aca660ae70d14c739fb537bf872476f12eaedd21181a59f533e5730e	1686490327000000	1687095127000000	1750167127000000	1844775127000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
250	\\x3772a728f4abea7d0e45b622aaa4698d30939fffdf1e335308c80847ac0acfc21649bc2ec79b4fc999ea96017278043828dbf75ddca2cb8f8d6a13376f5b1eac	1	0	\\x000000010000000000800003e185e9caf3e090b25963f2aaad5348eb1182f59273b4d4fbf407c0195d550da08ffcbc47e9883b99a13cdcadc1c7fe0481676e2bb10bd3ee0e2c329c74deb9f9d4e8baafbedb53e1399641a2e22d110f55d364bf7561b0762685c373686452e4b34164ec38661604a82371c9cc7e4f2188d406ce27ff169faebf2aad2b6587f1010001	\\x0a1357278465c641b2ef9089111c92d759623a697eb493d6d366b79556e9c5fabe822728ae86504940d9afcd6325df63ca08ad8afc83fbfec909cd5c4c8c3e0d	1666541827000000	1667146627000000	1730218627000000	1824826627000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
251	\\x38aaf3f26d463c4c5d863ee3979e0cb67ac8ce9db4310d5c3bde8aea6b2bd1f47165c743ffb7d59d76cf0db4bf18d883ff8041eaa19daeb25a8ed5af684e704d	1	0	\\x000000010000000000800003d995f1d1d4f51932667a9355f310ce1ff260280e7b080b6e944011fa4728c31a5361efd3f176f2bd97354d88f229ab5900f052ca8ca0a8d1812ea558ec0227816eecdd79e1855806de4240a0b7b66e8205c7b3d88b9755e8605d97cd30bf3c8c16a24f210a012b8adae2fa5f79a5dc35aa8c8b89e35b51f4acfbff8515a5571b010001	\\xf4791087c2327429a573bcb2f9e15676781e36e581b4b533676d33edd964a819488cf5dfe97984ea3afeb35844503c4cef7b1d4182c7f201567ad3266004ce07	1665332827000000	1665937627000000	1729009627000000	1823617627000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
252	\\x3e622ad9eeaa6ad505f5b18241cb3b39698cbd9bd3c29672a76416d22219fe79322094f207ca99b028ac2e0eb9c653326f5ddf2780ac1a825fa71ee4b98e30e1	1	0	\\x000000010000000000800003f620f0398645f57dd11a16ff069245f9975cbe4b937e88a73914bb9f8541e56d8189e75cb1f7ba0154bb07f029992f030d7ee276eff93d5124c30875647cc002880421e02be236ae7519e1a6b75e7aeb5ff71959b51434b869c32f0d0cb01dfd04f1e3336e4c08f7f79b19bf2719200697687e482909f46974438e6b561a9c5b010001	\\x75978c198f5fd509079153c065206f62aa5949d29be60d3aafa18b8903ce255ac85e1db9ca6781ef8caedc8820dc4ea85a9e36e0daf2754de0f48efe942c0403	1663519327000000	1664124127000000	1727196127000000	1821804127000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
253	\\x428eabca5fa9040d2f99b169d4223a0b10a400ac4f83cc5c240285045d7e62ca405a87f20af34196083c0389536829acd76006ea58c1af85889fb256426855ae	1	0	\\x000000010000000000800003c5d49fe133241736b072fcd6465acf5641c83f7f31f423cfc239bdaf6294bae4acca855c5cd4c75477ca964a9144d395755cfb732a95bf4370d77411c508016fcca7b69a87005c999c08d624b21bb43b94320c306939a9e068e89e6a0e10f8812d4e0873c379c9ace02188a6662085ba28514dbf78730d0119f4776d95586aa3010001	\\xaa013f7850885b31b206fe62b734aa314e3ca92ea41e2541defcc42064c5d307327661d0b709fe7eb3be77d514506c0ccb937db6cdb4faf6f6a4326f1fad550d	1691326327000000	1691931127000000	1755003127000000	1849611127000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
254	\\x4266c0dcb35925babc906d94d465b9ede74b73944f0f74a11f55b0f3f47d1ce01d491387b0404c54deb8cd2d9a7019bc0168bad7b59f0ef67a3364e5fd2ee526	1	0	\\x000000010000000000800003ded0f9b92479c18c2e75211e9dca6a096d18ff8256ad35cd172ff8eaa8942ba257f4295b2f0f59897b605785f1ff4cc1c409717008bbda4066c4e649af29d97982a63e5c5cbf11aacffa76d20ad08b26468c1a1f01b39d67ee525550e7fb225ca11c8f468ab7ee314cfb959e652795c54836a53c09572670060f6731dc14f31d010001	\\x1b9b135a341181b05bb880320294e854383ba33b082d9152724bb906cc71d096113d4ccc551f450c2a66f9508883c7aa6d67c62c4ee3e83f6b6070bdf8d79c01	1681654327000000	1682259127000000	1745331127000000	1839939127000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
255	\\x4982a9ef6525d19d7d3153e03cee7304b5c2a7b867db34794d50bc614a248ccb5f1afbd2942d789dc034fbdff9b6d7b7d9c9a994e97f9f00c904d3ecc7bb148b	1	0	\\x000000010000000000800003b8896a2e1d80d9f6d4c5e137a8dc38c332adfa43e0f970d079f91f1a28f93f3ea00f9f88cfd557922056446e72afeb286a4a1bd983ebf310a7f56b4d88080fe197f6ad98de4a09180aa378f5941df7ed8abb71e51d57fc351bcc64dba8580c308a52bec01a3ff296244fceb81f46635953a38ace8f2fcbfa9f605c1cf2b063a3010001	\\x0653da1e503ea3b5fafefc05b93f224286a1d472e556eb00cfc46bd58233bbedc7aafcdff4982e376b0ba747f758dc1d8769edbe27a3b84db8fdafa4864eab09	1665332827000000	1665937627000000	1729009627000000	1823617627000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
256	\\x4ad2b3fd689f18b40a675af6309fa78cfb4c1dff8a59ccb3920e5ce619b59e47e86c60a27836e53b013b1b51b87d77822c544ee6d9d9038167d7ae2e198888ac	1	0	\\x000000010000000000800003d62303cae581ae010d02b9258f5f45188f4309a4a7c9347adab2479b12742c9920dba6dd4863acdfefab9a2d5cf99c2e4398945d3ad7e414c8bb39fb238c672581fd2c50b6170fd106dae65aef6cec659b409906a5cb1262ef6478c510f2c493b4f60711d995d829735bb3ca5eabcdd47c5f70dd44f66b677095772d98dadedd010001	\\x2713626da916c96ceeb6da21e5021bbc9f4a0c176cd5864cc784be26559678445232aae24379ac13bab464fd9443b9d7027d205c5d5fd033b04d24463b6cd700	1671377827000000	1671982627000000	1735054627000000	1829662627000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
257	\\x4e32fb5940b29a42d25e9bae2b25cce8bd6eecaa2af1ce5d12500004b6622368d3afbb8cc78eeb2e6ee8065d45c010eda1f1025f0fb606a12d8fba213b56c71a	1	0	\\x000000010000000000800003c7d2c421eb0a15b8d8e9a7133dcb8edac6e72ffb967de131090cdada4f6c89799e9465bacc9d6384535dc4c0fd5059ac2b18e0f51e64d3cb56b99635989efa12b62d4dcf0d3ac6610201e80c4598e366a4690f6afe338381bf8f54c8d92311e00b8086b30c50e5483c57f3a902fee6c8bbf68f27e5fcf26bdb4c1b2b9c68dde3010001	\\x6261f4cc833e0d8325d35b7f29da6a8f6e2b22f54f9eaee21ac6f869200d2ecf2dbbce8ed5843cea9554509b56e5af4220019ef878da238d0d0bd8c32037eb03	1688303827000000	1688908627000000	1751980627000000	1846588627000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
258	\\x4e4eb383d117b6caa74b8aad71ca3503eef087df135294bde383781498c476e6318e3faceb518b3203d024a1659d552287276ddb0e19d6fbd816e32eb0b61a59	1	0	\\x000000010000000000800003adf93e5458409255c6b9de06e8e6956895733016e2d133b8348cb50c4a7755b765584328a8aee2dabded6e1088554c17c2e4bd64c5e8cd1c0b71c787b5d83d04ac59fdc5341a66fe21b7b6c1c5c260b8a5f7bd54665849a4512d0541f01be5484fae206fb29292d140baed83423a901924c839e22d31821d164ea6e20576ca81010001	\\x9951bd8a8bc3a61454b84c0e80506e21152ac46529968ecc4a4b1ada89a79d501265de170613b7473096ae4eea5419787b64755f2f99f6618527ad69b1d33107	1667750827000000	1668355627000000	1731427627000000	1826035627000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
259	\\x552273f2d633fd35f5521624b7feb22c9c6ad91acc145b837dcb41a1dae8b01b6d2ea1e6143df565214666df59e789ee1fb5f031ad062fe0c114074f9f49fd32	1	0	\\x000000010000000000800003b13ad6a93e8b32891cfb7bdfda5796fbe7d9cd59a1cce33f800617ba6504515168902006ca18354cd647188439f6783bf35b3e60f9007c71495e843b4969e1795dc162af2717b139117b520851f0b7fa37077a3fba05b75c70d69646aa82c22647971eeaa4556820c24951728877766b1410779c6a432aacc5990845e80deef5010001	\\x5c1a453cd1679c75333322e1bc42843447b2a3ce9163348fc10915a445a18ab41a52ca4ebf9bffb03fefee03d52848c9243fbc095c79bc73f5d043f295258b00	1669564327000000	1670169127000000	1733241127000000	1827849127000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
260	\\x55eeb1a2218cfa8a5992e53939a8bb149d3aa6b90101db0935b48dcd523b9a9382613e7490d67333d479d5bff4475e37d72ba1e31af088c6c82dea2b2f58c511	1	0	\\x000000010000000000800003a56643d6ea07501ce52bb6346230bc66bdade9f571d04e9eac168246c72a7032f81cca8f7064c2e96a9a4c10ce33791488d07709a0505a7d8f509b7b384e35f87c2bf337db1dcc71279db4528d42d56dc5ae251327aba5fb978c29d7e2090337020f6ee0602437f7370f2719db0a1fc774edc411da94cdf35708f2fcf7774297010001	\\x17053ea58431f2b769324c9ffc313132ea0e721f27a33838fda39acc4bb59afc080943a2365412e05a2bc1e1815e71e7a04577de19d7caf55df4560ade936402	1681654327000000	1682259127000000	1745331127000000	1839939127000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
261	\\x5676470225d1b3c45e962c5e144846a5ee7d3f2bd769a40f1055fc6e70ba8ead12c4e77c3493f9dd6c0232bde8530b8e5934f8c8b2ea1923df0caeae4e0b6575	1	0	\\x000000010000000000800003cee6b327d65070ab1829a373c33c3f9f475e0f121c0076cb2d9a2806fba4bfb95b0e373feb22ac3e091c9c87821c0cb09b64844a3d292a3410eff6e0721d350a493426eaf70f93afbfc5b311a8bbcc7e00e87b4ffd5553bdc0e08e473e8a138535adbdc772224481c16305467cc59b5c4fed51ebb390319f08384d12434faf45010001	\\x111b57cb5ef543db9c06ffcb5a6a9e377ca99ab8dfcfe0a56947c5fe704c1d46c977faa3df9cf4ee2f3b767d73656b1c6bd434ca79e40888289aa3ca3edb960d	1676818327000000	1677423127000000	1740495127000000	1835103127000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
262	\\x560a2b10cc30087ee16beaf9a799e3ea866de80f4666267e6da521edb85467d611e27eca5ed95734f3f5238e8f034c097ce5d4a94043062fc3340a6115270c70	1	0	\\x000000010000000000800003d31a8bad5535ac4952f1029dce647838e3a88c862ee7108376c818c8353aa28ab137ced7f958a9f27d621a5d421c70ab1e465ee4a72c017a20d2194fca14382b53dcc5fc405c5d64a3a101f4fc4211cc196c0a15f4c6c8a939345f7b2b3bfe61108a8b8fc2086c9d47b45dcbdf14c64b71ba4a0dd66b3bc8bc29d830566e6c15010001	\\xf35452592feee21293cdec4594e77c252ed2bbd2c616235f0758d54eda5b64707ba9fa3f09ba5d92542eaf0fc71b5965333080e6050a655d9b63a2252a3e2408	1661101327000000	1661706127000000	1724778127000000	1819386127000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
263	\\x590e38452fa579609d4ee8d76f849f28548ce07c65f1f8d825dfa3e72c415eb2e8525217c1e54e721b11005a76554295feab20b030b504a335b58d023321f0ca	1	0	\\x0000000100000000008000039f081f71f7756ae26d3e5a46110be790fe241d9a40e41ee797547c7e33f68b955dc93aae33dc02769dc145a853ec027dd2cfb674919b576fd61920c789279a01df7ab646696f07184ed6081ab88f07c1ec732bb1f2f51f59570f656331bc0aecc089b12b452cdc0559a73a9994a818758f47ac1a39161a01a558fbc228d9cacf010001	\\xb45bd46c3cedecab95f21eae4e72192d2f9a1b56c4f0f81754462c233534ee6084e8b0617afeec1aaed3bf8dc60aba4527fff99aa10c2034b2b43511075e6605	1670168827000000	1670773627000000	1733845627000000	1828453627000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
264	\\x60c2544ced0bc0bb3e7aed433d4cf918faf5160528f74548b320d1955c9f167f0a645d689776d538eec5022b8ffe079931390773aa167a25ff6456edda5050e7	1	0	\\x000000010000000000800003be69fd99bd3e0443d47bd1bf081448bc83165e016de43b7332a9e8ac72826266a5423d567e4ba9744a39c08b08b67c263d30c96f2de2e62c4feb9bf27d62061f262a497cbe35d7e8f608afb12b6aa49b74218651c9ca765d010bf2a8009425115df697a79e700e22b55d225b1ff3224441d07236f1a03b19f2c0acd9835e8ca3010001	\\xf9e54ae757ff38245804a833f09b152945e86b8b021994c12cfdc3bb1d3b61b05a6c4c168b47662a48d82456999310bd9328ce39713fa2e402f168fc5ce37303	1678631827000000	1679236627000000	1742308627000000	1836916627000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
265	\\x60f6ce5c592b671bd56de9b85fa4c7d1aabdce4ec6b48d929c82506325b81de9345492ebee31c9b7c769c6b5d98c6cb4a38ec2d239f735e01a4b92bf6bbeda33	1	0	\\x000000010000000000800003972eef37c6e37f62361e768ceeccd0b8d8235f6b8013f60bea18d3a698e7163d179d6fbb8f448d767170c732dcf14d4480d05747b6de745e8de9b816cd7bc9c9eb1c0ed46e05e110f10ad4bc5fe2eb4a19de86703c7bbbd59c72ce96881bbcc0e4d8b7432afc839e31d15e7b1965e4fd429a3c63188f706d09d2928dd8cb7089010001	\\xf82c108e9c1fc9ec6d3ecac2371826a6d89a9d446228d93035144c50526a188a8845af2d1aa78655df02c621e744a1e5c189ca6656fa9d83f3b7e97160931d0d	1683467827000000	1684072627000000	1747144627000000	1841752627000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
266	\\x61e26eed6f745d984a532a213f4c254e752d20cf016691858d95121ce08aed040e6b2f494b3d4e16a93db195be9ff033a8fac9f3c19f406117f48faf0acd6619	1	0	\\x000000010000000000800003d995eb06506fafe1704fffe74e01b86b9142b18c911800f577dbbfaa27994b7228563133af6d286c1768355874c5ebb7a23bf029e63ecce44c66dad113e851f1ea29cde7619cf727dbc5f6d4bc9aea76581d0684a34dc7d1c601618343c394d9643a82e5cf896bc1bc2ad4f068e271a4c9e5595d233373e9c622ccaa7eff354d010001	\\x7ead7b7b0c54cbd4d7d142288c0ad4b13d278cc797d6a84f2d1766f36093441debe587d1346d483179d1a73c7a35702be533736c7f1e7deb84d7fd6d3cf28f07	1683467827000000	1684072627000000	1747144627000000	1841752627000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
267	\\x64ca0f2f8ff920bf1e70fffe3871d511da87fa73204fa20fd150978b86858d51d15da0b04b5ce2aeff9049079e41e9bf2b694fec059c60adcced8b16e282c90a	1	0	\\x000000010000000000800003a909b9483b0f4a1807d5c0d0c78356c11010c7fba940262fd669c33e1d8a94d3f7ad59799ca5220d977dc6da229ee794b9d626d49960938ff3b59fd0b173ace99c33ecf425fa0993d4fbfae582b5b772a899b49c4e9c1ffbb1851a4583c033beb66b7f21ba33ffdfcc0c0c01702bab0a3d3192e570d0bb52766990d86d527acd010001	\\x996e4c68598b0cb8bc2fa2b7d0d860ffb6441f7ccb00b7436a904f9744e0ffdcfa51b899721e3efd44dbd5bc0b73c4c737612e6e8393bde3693d33e9cd2cfd08	1667750827000000	1668355627000000	1731427627000000	1826035627000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
268	\\x664a9d049ad1038c1ed6000c020a77245f827cd007f66d03eff5f435a8941c67e5aaa7f2f386a1475153946b79469ee0dc01f6304af09d0f1397351d58ad2594	1	0	\\x000000010000000000800003b1347fbf2a6e7701e0a015a8ea0bddc057ec915a207a9bd7a43ff98e0ccc374ed765661b91983c7cac2f4ca313b7631c2c2c076f69559cc85265cc49b2276345bd462ac79390df9b2b1dd005e90f33a4466da762ee377a991ff4d8759ac24b18a88f48d0d039df6c2812da43a2fd6bbbf4a7c1a92bebf49d04f9dde5981d1dc9010001	\\x0cf6d24817fdf1ba11bfcbec1121657a3f53e1c7ea94882b6464111907aabde9ef209f151a830e32b68c8f57137d73f9fc5a6c0a9e00184f6ccfa99843120109	1682258827000000	1682863627000000	1745935627000000	1840543627000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
269	\\x6bfa27263a5a449250157be8cd8a93a73993ac4487a289c9bb13e022b3eb4898349cc2c3d2cd549e783f70463521bb967ea060bc13b13937956295252868a41f	1	0	\\x000000010000000000800003abb714eef5108773275e501a2b333362d2ce6ba5a8f7a1053a2c9eca2aeac81d4c937db9e183cfd7aa3a0b4b17cf244cbf8630aec37a63980610ef96994a50cc431c0db98fc87f650201963e24dde70f2acf4eabfb454f8489387c17d5525fc4a5f388a5fa8a62ab903ca7d2439c715e69517cfc25dd22ced08f1358f598221f010001	\\x8fcc0b3893e98d62ab51fe5b5e9805193331b73509e20b30bec84a67bf52780059fd2914e14758c198d22802e98d92ea2a5316764ee14f0f30ff21520242410f	1687094827000000	1687699627000000	1750771627000000	1845379627000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
270	\\x742a6610d4602cc9a48b8ba8414d348e69f3b49dbadd17db67f6c4f1b5b6c6be7310747f0e76d64238f0eb1b398fbcf08f1f0e4aa38e65ea8e2e90460cad4c73	1	0	\\x000000010000000000800003b3f16d9c37e4fa47562e2c398daba2e70ceac6d2d2c3a1c628d1d16447df5545234118826c271ceab823ba79fc3f0d81139517447b8e420143cfc9f5736048ec7fe489ddf06b7938a30c6ff809f6d377f553751ed60ea5bff076294e371bd2794f345fb6185e24437a1932a83906a211a37a4d4fb29513098844fab0ae7d6fe9010001	\\xcc8c365c3bd6a3623701a0852a85572251e672ff871d4473a61acac8a380af07df646adeddd5dfcef91e71e8638ce5bc7afedfed37c438f3c664651991390309	1668959827000000	1669564627000000	1732636627000000	1827244627000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
271	\\x7562519104c75f7ecf5984c0c5940824ac3d372225dc3b8251fd68e3a85cdda7d38a8c22caad7c36a30efa01f914c021dd359ce93437cbe1a250f83cae2009e9	1	0	\\x000000010000000000800003d4a53e53c51b37546654868eb12348a9d9886ed1dd4b3cdf9033aa83cd9fc8e63059b61b46ef44c13d8faa115989babf1aeb2a6f070badb74e5aeeff9be8caf9b4d5918cbf2ac850be125a0564a530b967b3163b7bd9ed8c249f79a13809a6b2d55f72784b5d08fced90d8bc7ef8eb8e5fb841f6ca3f75d3fe3d851c701c3a57010001	\\xaef70a6b7e48a89fd60e06464b62748006ef4b2bd91dbd41376ab78f0199b859a51d50ca3e96e9a9d48e9825fc0bd0688d0617a08d9e0d9e06bb532cb4d99e0a	1667750827000000	1668355627000000	1731427627000000	1826035627000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
272	\\x78de7b1c2ed3c445767445148f32c19803b30851523da6f2191c82fcb78ee0a28c3dcfb11ee765a39bbe08fa790e2b6856b2cea3d0c4d56efaf6ec0acebecc14	1	0	\\x000000010000000000800003e2e9f5baaceb80ac84a80825cc8c9d5de03d388658545c56d375ad6742dc1515aef16f5a2c5ef5c9cf2637d1d5a50d4050a3d489b4f606be97b5e27e9553c9a9c5fb455a596f47fa8d9953f21b17c95006726d485971df17c2c5ecedbbf25b22ec17aef10f01bebdf220f1a6eb213a2d4076080808d6190798bb1821bdde6da1010001	\\xc07d2dbff7b52e63e61074a0a381c935278e62ca56199dcbce41d7273697fd584be695b610c28e791338eeb4435e8573f28297365495ee3e292a1cc4bbd49b0a	1672586827000000	1673191627000000	1736263627000000	1830871627000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
273	\\x7fa6b89dc348141846343c42a2f26c6b9c99243d8693d51d6298d3893f22ae3b0daf1e0cdf640b22260875f781b2d81e201411f75a4401e55cce8dca5153a3b9	1	0	\\x000000010000000000800003d446915a78cab625a746285969e712b9cbc36fb5875f7b1abef819f77b2d74d676808e6cfcda0c29409a9b254bdb0175be155dccde8581f9a0de504d15bc51c292659196cd2ff897be930f1602dd83924880b29c148102919fdc4e6c495e36414f36b27e00569780ec8e77944fd68c92f1c6c4f8195a03d2274bee6910bd7a45010001	\\x7514bbbcb14a68f3b38a55e3c57caf973036c10a59494fde3110a7031396eb04b5003b7e8fc0fd8821427361c69f48dc67ee7f03bb4bf4808d0d2ddd9b163c06	1684676827000000	1685281627000000	1748353627000000	1842961627000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
274	\\x812e2b62e9f621d11093d075d469f53796023cec0c42b4c7f6d5421820119475dd5d776945897868e33baf6e59f7c17ba855f92916c8cf102cc069847b0f0f68	1	0	\\x000000010000000000800003a0d6c683d4d8a74e7c7cd146105c402b79c56009ac95829bfcc2549609e36d54972a56b91b37bcc87acecf5cead37f84f05a6423a601c7a5dd65c182bf282ba5f32ad4731d400922949ce072aa1b84ff75190cac250da536a906251e278a7c7edf71a333bc011f440711e1793e4c4198bcd38b8c38af8c3b1d53c3632f30f663010001	\\xf8fd4b0922fd1b4d4577c944f5182b74c1b005c11647066155d69284a37f08b8add7da4d3061ab979fa82790d4496bb5fefcfbac3b68a42f619fefa8da4f850b	1680445327000000	1681050127000000	1744122127000000	1838730127000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
275	\\x83da7aff120cfcb818c2ea782405c416b6eb953db5e3d44530cc6682f9afd9923130e34b3faaade9fb048bcf4b9348391e93fa2e291af165147bb707c63237d4	1	0	\\x000000010000000000800003a27f422abd843f0e3a840310279d2ae74290e73e012d38bb7d59c2167aaf36f0844f0229ea213a37ac31f716ad38deb055bdab2bc851e978f71bc27d780748e172326e5ee7cd2d7f85907def5b3e96384b2b6144eed9c187743c682233dc127ed9dcd11a4ff17970c613084605ea2e16cd8e614eb998e11876402d9d617d77d7010001	\\x6937e3dfb5a9b820e2dfce57ba93ef6a5277fda5836e70e0a12af777654db58b46ceea91e87cd794c6c62b1a98e87e224e4d489f49b2594566802e1e1fddf20c	1675004827000000	1675609627000000	1738681627000000	1833289627000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
276	\\x8336b2bdf96262bc691ff5b063a271a04cf4ba782e8b6d37fc934502c60d2e3fd704870ea988c99c1ef04d11445fad7e0e7858de5c98b9077abc1cee78f990e8	1	0	\\x000000010000000000800003ade2776c8163db6e9b39f399a2ec46ef7f70f17b59d156171059a777af1b10dcbc43e03631a6d3bbb5f2ec83ba3b44fbbc81ab4279ff583ddc76e0af278416937b2632722f1bd9c4b007c8d271e49547a95b2be07d0dbfde5ddc81822148543c085a1731ef48faee3036f8e3588244eb9d0094a5e74a7fc007b978e2fb5a2e8f010001	\\x034a9f4c32acdea7b1586f4d1635ae35529f2cd8600bd2e7f7aa06596981e55395548f5ab1cab322c804229915b463792ed16e764952df8e44e35b6a1998bf00	1690117327000000	1690722127000000	1753794127000000	1848402127000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
277	\\x854688c690e71bed78154186de6761367509b022c5390b7bdf7e93b66afd29de83b51ef2353ae022883264a92c48525eeb491b2895c5a3e81b2f285d0603803f	1	0	\\x000000010000000000800003cfe92c803dce9e56dc3692c2dcd2a3d76e2ffd92201a9803d7e1af824badc74473ab5a28bb7f67711ad011bf70bdb355f30c73622553d59c104fc72053e5b250b4075df3a6410fe057055e47ab8119ca6aa02e823703564792e27b6e63416f5743ad782b616ad7ed8a13fcc68274d6d27acb406f33db288cdf623a80469ee045010001	\\xf132fe4b22726531d0994b751ec2252c5bb9c6afec0d0114468208a4c3ab062876a2393ca5f72bc0f15d2ba43f496010e5f64dcdd023cbaa767bc6df7dccfb03	1685281327000000	1685886127000000	1748958127000000	1843566127000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
278	\\x8646279488b2239a964cef777c8e89d7c734aade2db86f50bb1b3c728bf021fb6fe145a1d14ffe6896161b8cea3885745e22e84d68ced779a64e02c482e5a865	1	0	\\x000000010000000000800003aecd4cd52fb4fc08d9725214a96a6b183f07887d6e4dd0cfc7664451edf19ed83a899555cb048aab358daf97dd1aa2d35637aa48451d5e3bb6ed6777d19ef188aee68aa961d0bceaf765452f413d2a4be3a687e5f107b601599f210589fa134babbaf1b1c26d0566efbc8d4fdcc4f3ff023a204ff272620298c76b046da5f1cd010001	\\x931f99b284fde0cb3cf4215247d6df949161444481f9a1b4aef1a8bc56f523cbfb179048743e4adc9c9e2e470f796a51907d7078672f71c5bc56be8e31fa0909	1680445327000000	1681050127000000	1744122127000000	1838730127000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
279	\\x87763bde881d90949220963f41e6bcaa2b1ee1a4d754ab9e3ba369d8161fa2e2955957a9618e47c0a33c52876fd935aba6d7919c465fb64b49e18eb9feabf303	1	0	\\x000000010000000000800003bfbb0bdc15ad6cf5dd595468156b0b951c99548f2ce299ea692d6cea330c516709fd4ec94a8dd8965a28faaa4747b2395fa847b734c7bc45dc032c503fe390b11afaff4f2ed18843c5fa4b21c60a7ae6b9c9b33834918878fa84d10fcd44fca7cc72197753539b8e0d83879885994825aab8e5061d1ca35a34493616d0e0cb49010001	\\x0a6768b078f372e36d1885492c3875e7b156e2c7db5f00a0da15bc14d03160cac7e777a1bff8d0ef46537ee208ef5a3011128c9a898f32a1d696ba6f210efb01	1664123827000000	1664728627000000	1727800627000000	1822408627000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
280	\\x87d21a8944e42a119c5fcc1a880540df3f723d25fd7d9de527a10ed3bc6b853651af575e2e0241bdbeb236c3ba23883fab4212b43a18d7792900f2a894cca084	1	0	\\x000000010000000000800003bf7787e233ba917831d9402bde03c17455295e5e7a34ce8f9fae2fe741d75b9230adfb490518e33796420904eeab2e3c9e2cf9813e7ffc7eedd2d2fbf51cd762289e21acd174fbf83940a16498ec7b7143782a24a957902e7f3cfe17e6432b34d3cc9ad3c1834ea78b87c9e982093e70bc9eaa98466bef8db70eefbb18ba6675010001	\\x3316dc55a962d0836f81a60f98da9099ed9f217a574a54e8fdf644a68862309dfda8b90101867936b9eca349dd80f6130a24cfc1c79c4c6ebc04a5d66f1bf90f	1674400327000000	1675005127000000	1738077127000000	1832685127000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
281	\\x88a638106efa919bec0575272b2b54a612d370aa505fc2b93f4c5b2148feec6570bc7147e061a54c547b98d1a4702ca896e6a0cf423046f11c8c901e29d346dd	1	0	\\x000000010000000000800003bd0a5b1d9e6ea53bbac010ce08bcfa02b8243478b8bae0fef4a70ce28002b59eca9bff2a58c7c5a1bce1ceeee8d58529c18bbc95aabad6cbe914595d74296600e329e1c0bf89249ec9fed4dfdfbdfeb0ac606ac45cae829bc2505e0e2cf43b7410a436579cc1119e155892fc75d390719c2ff839f38d28cc7b415a42f17f3b41010001	\\x67835bc4aecf9dcfe9e606b9426bacb040b331ffdea2167bfb108d76382113fad9b7c034d4283e666cb382738518a9f598e4139dafecfe4beb08ee74d7eeaf04	1675004827000000	1675609627000000	1738681627000000	1833289627000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
282	\\x8a2a99aa448ed3ea95efa649464a217fe9696668d6e1d36ea8f05d9a51bd7cfb80fd318e01e8951e25734d509238a824b19711ed8cce5af988d6aa9123124af0	1	0	\\x000000010000000000800003d41ad6eb1323b9c808852e045695a20da9e6d3d95e15025498f2986650e1d12b94eb04762e339e3e070f340023e5667e81a4162415810b8fb21a01266e6b9a23e78c9fad5cc4f66491233271ff248a335d2dc5d5a78c7efb4deb27a7c5ba31d021188f6e1f83c0befb138af5b3b21881f8660ef505a0e6623ba59ca39f4e5c99010001	\\x425224bf4d5252756db12ed4e712a5fbc42d7c525fbd3c79358fa243e1aa1ad176162760dc8b8978041f8953e053aa36a63d212a9a6e99a5208d785a30a9bf0d	1675004827000000	1675609627000000	1738681627000000	1833289627000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
283	\\x8be24933f00fc66eb4b69b23b14dc0876dacfbabcfb44b1f3e463b11180c478dbc414232dedfd3916e8d54ded81d829c04a8593e05eda0e2a4c113c5807faab0	1	0	\\x000000010000000000800003a9a88ed5a24970f14b688494871722275e46f9308d25e1815fd87438465a8ec50dcc43e1840287e528d922db9e1082a0e344748651abe75d42e33fad85f909c4953c499abbaf0b6431cc37977c543df6d853e5bff448ab87dfa943840b0e938ec019b7b69d35bab83ba91345f503bea1d6843ec650833cf493655f5edc0d9fed010001	\\xf212ac5597b0f4417267f19162f669ef61ff7fb952594bf63e1afc2acb532ffb9b5f05b12a819eda4bcec0b34147274297364e1ab139727c7a6d5703af797006	1669564327000000	1670169127000000	1733241127000000	1827849127000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
284	\\x8baaf539de76efdbe996c5ac4debe3b6589a935d0ea42c1fc7f78ebc37bd6e9e8e05e1b29d1172888dea7dabd41bf91cd2bce5ddeadfea0e29bb52517374a7fc	1	0	\\x000000010000000000800003d9688e6d174afe890aa137e07d7050af22042fb68719b1f72d3472d18a5d80f3207a75ffbf618fd713bac60c34dd004954d44f4adafb7b75c6a4032e62a2d105f46c3ab4af8d974aa52e7deadfd6380eac42bce52c8c90131d433affa70012408ca39dfb1191779c46e5f72a3db1f79d827b254f4dee7dd4238d14c142164dbb010001	\\xaf3976a70a87fb8b3f6747676a7f87f7e9ec0392e9d5d9d72af7fd5f7cf3d1a0362cb265f8a799e868c5266d0a42e8055dfffe099af8aa7f5a3b6e3873de970a	1676818327000000	1677423127000000	1740495127000000	1835103127000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
285	\\x8ea608e80bdd3661ae0d5e883db5bd73d987b51e6f698b2c317d820f88ce8842100ef5638831ff07d418dd4d756d7e3b4916dbf7ade97caf541c7a3301fc8cfe	1	0	\\x000000010000000000800003ac07099a4ccfcf800e79aa0771efc2b0896275e3409219ea879e6374b0290a8442ba4761190b82b080c20d2c9c4f4b97cc4bd8ec554651cf59455060bccf9c515cb75723157fa649e6d8c1a3a74528c75544f52188cebdd28bb55d44754a2aa55a92a0265556f3ca11de38ed9d98f4d14d6c6bb179b1418cf94637ee8cc93305010001	\\xb4fa8a041b561817b61b5a6a3be39bc51f18301989de13b4d9b4fd27435b8d1372c86108d33cd08bf42b2b41d184ebac3115af4b0905cb5d18f16695e72d0e03	1684072327000000	1684677127000000	1747749127000000	1842357127000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
286	\\x8f062ed412438d60365609c3915380054247685ed729a9c123daee35af1e53d573e535e3b404d0aa428d50f1bdba0ce72329a919173f2bbc1c468759d540279f	1	0	\\x000000010000000000800003a48570af7bd9ac461e2508793be5ea1c9b124bf674eaf44862ce977db84c000917aefc1c9843121fd43f3f12d1ac19b02c6a2cac992944b5e55011243084ab8db6055e4a640a2a3c4d0ac1751d9f769a2359bfa9aa0dadb8e65c56b3a82f2a20a3f31a933295d33bf22b33b4d9c52504f122c106a55c26807a6b0981883c1663010001	\\xa94bd2e0058b35a1baa5c52b56e7b429140dc92c453dbe215bb831e3790d664251e2a0d18686d212b3c64d90f2fc1a12f7bec9226749f2aead2d3ceeb1bc1905	1668959827000000	1669564627000000	1732636627000000	1827244627000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
287	\\x924e7739fe25407571559da0f53edc0e50a7cc8f705818a7f00ded1e7ab29f040ad3f9c8ec4026cc33cf6a1c4374dfcd5cda32d76bce6ba48c2821ef2d65e936	1	0	\\x000000010000000000800003b95d7b9a1db23e4b7e85f9260e81b6c7c6e625993e2a6be102ff17ee1f2e36206e1bbcb9fc669fea282b57d9f6c9ba1afdad87a0277230d1935b18005a0020c18c5e6df2f5327908fd3031f5b250ed60b5043f0dd722385ce9b82cf5e8bf23585dd6ec02076a7ba1e6f650949f1e9f05482cdc80389157881cdaddd4a203bdab010001	\\x720ff39406e44a6b5ee7b61fc4dbf4b03dac91ae46453311e8941429dde39dba5728542554a13f47c6e07c00103f4aee750f4140e4cec14734df22a85088a003	1672586827000000	1673191627000000	1736263627000000	1830871627000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
288	\\x934ecb0a074ad3607c6723de81eb316123553b6a7e2d68cb58bd40db22d2a5a71d65cdda747f001f948fb2c2fbc0538e9ddc12de0c810b63fbe861eaed52c1ba	1	0	\\x000000010000000000800003b7436ba0e89e06a3354f50f1792520490b1ffad82a2578aaa06524f764d04ce9f1067b8f3412bf1b887c7267b0d23b1860e9ead69b3fa5c5d9ae36023d36ca5040d51158587480b4459b35fccfbfd3c84fc7e942868633c96a8db47df5d2de082d2829b442213b831a9ffcd762438755b0217d90133bb75b7e2396274b575c51010001	\\x87e342c7ffc7078fd04ae8a0c3e56a38ee2e4829fd80739ec84fd66b684c6b791789882278a52d40908fd42387e2ef47610a4247e80f742f2b0fe375d65b030f	1679840827000000	1680445627000000	1743517627000000	1838125627000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
289	\\x940aa25dfc2efa5e31de3946e3a14d618b816e61defec8928121636989bc374b75d88b676a2e0d35f649bddb209c9d7444b921f208d021f326f1d15b1d9daad7	1	0	\\x000000010000000000800003d4087eb13079db86d435ad599180645a7bec4edd3289645c51248bfdecc0187744a9e4d7dda281683721743d9f86e4eeac328cc8a0c37288e931341fa484989ce4634f5da5ca26442ed1454865d3b6573436034b08aa968e7c5ed7db15c59084f390edd0196bf6fdfa5a65b5d54e167079b0a9d7c8be565364b19337b709f587010001	\\x856c74e6e97e015c79e42f72d61f29acc1952b8b636a689c8705493ad842b974af136a75196177bea2315cd460cb69f0cbc7983b9a50fe2f2d47e3f100615402	1663519327000000	1664124127000000	1727196127000000	1821804127000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
290	\\x97fe34fb76afb16752731f7df2cc2a4b9d1c00ce0ed888bc2c986ebfb0d4654c2d08050826f72f9f9e6456cb6e29f334775c84f11096e7d14a4a385b86b967d6	1	0	\\x000000010000000000800003b376576ad35802ae543329ce0073d4c5d44ac4d974bdaea3976a140337d420cc35917d4f972d24861034911a40be96cc297e10bfa7915350d3e517c0786ef6997595b8154efc7e303d91dae3b7a8e7b467887be1674474503005f0e72080c160c8f63bd1a8c3ad58422031c6ac0f51190359e21fd19707cb8e992b1db6d50801010001	\\x7c1e8c0abdd770c3d6029bde85bb8af6414afab947dbe455a5fb22655a02296c0322974d03ff016e10472e1ea86826a49804ff41c94e2925a21843b37b240703	1673191327000000	1673796127000000	1736868127000000	1831476127000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
291	\\x98f2ad26d5ea7a30fc7f92bdc1877fc32acf4f2c4c428938e14bac8141ce4ed5dacbdaf233ffa3da9d512580a84a8e3f4accc7491ce9a83d5bc9f7ffa44c71d6	1	0	\\x000000010000000000800003a7101c930f752dee54084991903522446a4a7793d6f57cd416afe4071461e844f52d622c5a3298dec6673fdbf083903b6cfcc54e2e3c0087ec65e9cafe5914803bd70ad60f1fc72dd16b684dfd046fd513db6d93294aa9951b2ce7308d1bb511c730bf79d4d463945aca45416484dd68d9ec848577c7f6c12e753ed0b68f5b81010001	\\x49d70c4a659cebf983e3599ea18c416db97f325417529508eeb5e075b6817413a6cfc55c85e63f51332be6ce564de2f08c04d9de51c4eeeb69c7b622e2523c05	1664728327000000	1665333127000000	1728405127000000	1823013127000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
292	\\x9a0aa1b915b2b4db8a452594c2d57c2bdc9713540a8156c856331c565ef1e19803b671e438ca714570f9479ec4ff96440ed829ad9e30a8e8bbe5e4ad3e138a23	1	0	\\x000000010000000000800003951f755a517320f04697c60be422ddd3b6686965c6915bfc18da9ca36211d780bd92cec0d14d53aabbaca522eff155864705f05be7265d9e369f286290ccb0594e30f37623d7283cb01a6fedf71c9e1498822eff4c3f0d354c7069b1bd7b90a3ee0171df8e4a6a8a163321ffefd04c316b33340288ebf2697f7a45959ec9809d010001	\\xd07394acf7e8d7bb5bb11c508c7b93706550268535ba790c47373338f7814ab9b0414967e7c21ce849da07de477299383b077835773c31f360b4c573109a7e01	1691326327000000	1691931127000000	1755003127000000	1849611127000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
293	\\x9abe1a6b639de4d8687b5973c6257b5386a4b5e9220a0417f408cd9c84a66291f3074c6d2f531ee7a328ca359346cd52a7a9e4ede4d2ed3bcb20a5e23458649b	1	0	\\x000000010000000000800003a94c0483b0f423a725bf4cb6cb0d192f8c05965a669f01fce03f85fb47af2d15e872dd6084394f7ae84c3fe08c8171abad7abff7908c46fa379d448829e054b6a5d4393f9b0a50ade655a123f3a63e6487ec50aabad7cefaf06799041833ee630b5394aa7c296f417335e3a3a039f0ff5759a13fbe4542b9256f7590370e65e1010001	\\x183217ef37289a13f5d8e9c2fe7974931d0848df55dbc64e3299c74a9f473cf951ceef8e452c63a96c6c09e1263bfbf8f2b880f98ec695d0191f4d3ce25ce207	1669564327000000	1670169127000000	1733241127000000	1827849127000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
294	\\x9b3289777eea8a7aca8c34fd789b859fd2e22b0885d6e9a3bdcd26a9acfdcf20e8ca3ec43cd375578348c66339a1b353c353cd0c81a94e70446d9de58c661c59	1	0	\\x000000010000000000800003baa96fa3fda15a3cb0fa9df00a8bf3d3e21275005ca51ac9a3d69234da84ec04e66ea483dc11af47302b34a3beb8f7ce0df927e8f4be01104243244ca2a6ecb9822f13adbd19b194ba94e1e70084f28bab420a7507530b40e81782bcb8d51d2024c0a8dab562fce9a2cab0b7ce974e9c0d1cb3be33b8d00ef1e567686eb1c567010001	\\x5d6494790337d789b16b1263ae137f9ed8285b063338b4b89507ebb1a22d26225410e1e4f041c7e5b5822d90a65718ccdf3065fc6677b289bc0d3da16a18b50e	1687094827000000	1687699627000000	1750771627000000	1845379627000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
295	\\x9c02793b6ac9a50a4786451667318b52a0d2d6485ae782f459d7c3613836ace1e738ee4e63cf68bd1facb7c069d00c306cd574782c1543acd52f95bcd428718b	1	0	\\x000000010000000000800003b5072233e43b770fa445718214da1e3d9aa9a3a12d60460def7755ea07c587c4c52da6afa769fd73e459dccb4c8136873f7af0af5b416fe6b0846749d17625036a7b2c706d6a30b84cbeeacbaff2d4e86525c82546bb474c2462df1f06d2aec8a6fa75f4371058b919a27b936087cd47537e0ea7aaec74c8f22e45e231b5643d010001	\\xfa4048c2dcf90d73ec3152876903dc53b634d56ae66946285e81baa1f4cc671568e6429a967cc6dcf322be0a959b5986d0280d4c47ae6148c02e0652c4638b08	1688908327000000	1689513127000000	1752585127000000	1847193127000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
296	\\xa46e63ec07613c9bcb48099c3b81560a930384efc95d045f72b0af066fa17a0f2514f721a89dd299088d115263240b3ddf8bf48ba0398f2a1c9815358ca98b25	1	0	\\x000000010000000000800003a836c3666d5b0388fc46ac802e306048ff8486dfac2e3a759bbfbb4cc510c83c022b5cc49d6157b07c418bb4662fd400f2adf1825b676d71d6e3659e5c88589150a17138ce6fcd42e9a3d643fe2c9eb2ecac58a6af508bba9dbc59125f61d188eb82606f24e048ec2bb8c3a9631a54cba8ff31eadb582f9899d1f9e88cd9dcaf010001	\\x3ae0a3e84d298cbce9c957d8b7d5c24fb5d7cc5ec073133969772a2a44cb4f5b4e9b74aae12c881e081936cf711a7caa938330f14dedd4e202e062f7de4b3005	1690721827000000	1691326627000000	1754398627000000	1849006627000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
297	\\xa892cd88e1109b01ddfdefa72b03dbde964b7f702acdfa10223ec1b63b8ccdf52ad8d5d481453cd8bb2edf83d37082f6e58e3e8d0acf2db9e3639ed688622a42	1	0	\\x000000010000000000800003d9c89494494ac43ebaad4b9da456d8d49fece9035ad3cadfb8f774196369d7c825e00cc194622826f2bb2e3405f13a38bbe7b87ba886fcd5b68c40c7069c28fb329e98ecea3cad7f454242b8617eed5b875b9120c374f953394bc028a5a058c7c9bba1eb01228fede01033e7aa7233fb8d148011f05ade0bd0f694861cd0a503010001	\\x9589da5ecdb0d91807df0dd998567eeeb7a54b72c28e4568d751b7e98293406ca3e7e8db306d393f2e6f98f90ec70928099e63e614a563e135fc29e6d665050d	1681654327000000	1682259127000000	1745331127000000	1839939127000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
298	\\xa98a76bc1253d9e1a9a11e45b2b443ef8a3dacdd17c9361d0c00898e06eafe9b0faa3e3542f55a9622ee5fa16a5a3e65d3e42224eacdba9155e86df1041b5277	1	0	\\x000000010000000000800003d3a4e50a015ff4a41e47c09e829f75c06f4579c374d6cfcc850a89f39457436f5d4a8ae06af149d98c6151117e5b823ec8b778a2c951301e150adba6ebef942c83a09e4fe02b4c85451edb1431827be6b7c7e49181559d5539314069d6a7555e36cc82ec5f2bf03e98ab50f8de18ad745ede00c17e58ea080b8182e481818ac1010001	\\x682ab0a4fc8ddf02d4de923116566cf491960f67f475c5288120c2bf0871c9f0a38baa48174ae9ec0328c718a0ca4f6db2b1d2d9d1eeea42fbf0725ae1c1f704	1660496827000000	1661101627000000	1724173627000000	1818781627000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
299	\\xa96af6d34c7b02dff5bc22a4c21051b547d5589ecbdb52431b9cfa1f3425963ee9af3c788f3e27d712c97ddc980a276a2d01cdda7cf932aa0ffb55f668d247fb	1	0	\\x0000000100000000008000039c8d4c38240cca9ca946ef5e6525dc23b0d402c56cec04447a9fde7057764aed72b4926b35bca98cae45aa5b9c8014934b3227a4ac4b1162dcdf6baa1441f0390c831e6fbbd3bb8e39a297d8c15fcc3d676e9aa9f3e4c3a81b90a915c951965f03ceddade6f98bc0869d320219043c35823be46444e96002ec7032f8901a29d1010001	\\x4a8aa9bb685bb08f3d4bfb9c4fd1199b7740251efe43c00cb2108c987dac6e400cc0fb9d0967b49fbee347b56c8b449640f67b00626868378d5bb29b898fc60a	1661705827000000	1662310627000000	1725382627000000	1819990627000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
300	\\xadf642700e155229d44d2108a4bb4342c83163001ca24ec645caa4cf1902ffc8b45a4bb36b3f540c16b08324f8cf6484f7e6f0c76fe38f02afd865216789ef40	1	0	\\x000000010000000000800003f73524e06cc22a9a29274e316d3fa2c4cba1855b42fb069e742bfa7350080fcd0a78ea931c90ac550eae43c88c781c2c428b16934cd023eeaf74e493ccde3ddae9e96da27e1df7555c838ded7de63a004ea9e782c420b88300b8a0f01f99bf0271c749033243a156b2706647fc32b9bb0ebe032ba61ef62b9d3a4f6dbd49a455010001	\\x8d5c5f6da397856b9996412d1809630271a4d48fb13a25317d43d10d44cf7b9886d0ab5fd281d2593788e921852ff0915aba554fa0fdebd5162d6e7b6f13fe05	1671982327000000	1672587127000000	1735659127000000	1830267127000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
301	\\xad2272d3cbde9fe1b6a74b40a3cf4e1609f0ae18435272edd6cfd2fe48225c91b083014c00d405f197c923f91db3495e07926a35b85934c2ebd3a780c0e2b1a6	1	0	\\x000000010000000000800003b858bdfa486a29e34567d4c5c3697795e2d42c317da2724f11174d657c4db9357920e2ac52a8c61784e622e223b1608428dcfc15fb2783dec679c557a064d17261f861b7d979502e583520c3e29c514816e761367c739c8d3bcc81b8345b2ffa1a3290938cbf7e945c541e3bf2710f90617d48665c314ad7e0a71fbbb3d7a519010001	\\xaf7e82d2d46938b7abcdc5404864773d444b6d3875f8893148b96842d3ac7d1630385aaab69a43f0447e1515d5c75e2b57f72584d70fe514404c3574a36e8804	1687094827000000	1687699627000000	1750771627000000	1845379627000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
302	\\xb1fa6bcc90070927cc68ba8ed6dff9682db51262fa0da9169eff0d583a61a08087e15704ef4fd20d99ff2649cb36a065f734460d056c2c8c9e048edcc96b6eae	1	0	\\x000000010000000000800003c3905407445c774dee16ce4cf01242ee952b37b351842f03634e8c26af65eb0e6b7de810b25e081e1faf78034c3c5b402cfbb74000d7672c1c0dfb43b8a0ca9f307a96d59b4aeddaaa07fd17eaa20ab2d99265b87b2aca2f6869fe21f8e7ef9a159df14f59061567e741e74ee5c4c881b47775586d58ef5e9957159396df6d0f010001	\\x37899b6d020323066685c713e78dd9e7d7fddc031acf15b506e1d1c58962b849227ee46aa7a12b738505de2510bda0030f9e195191b93f2340812649fc182507	1677422827000000	1678027627000000	1741099627000000	1835707627000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
303	\\xb8e2f03446f088e79516c7d543d70d90a1fcb869221e99b5bccf7e40c2881238f250441d1445b8d4ccc06c071c26280a09dc48e7c789639046d2f41d2d30a634	1	0	\\x000000010000000000800003b78ca6b62765e84df7c6c3176e294d3d89dd0234efd22630113ffa3423d7b12f610fa25446376001878e7146a2283dac12fcd3f69209893f313c92c3872ac70e1d0f2df6018b38b16ddd53d1d9efe3d2ea4e0d5f5cf52cbfa57cfaede6889419100d82e5d078c95b9de34b9e022ac524faf11c9ea21328bddeb2609fa5e2dab3010001	\\x4583bd15bb7516e5ac2a23bdeb3c84c8229faf636006399c01bd272a666d75b324fbfd697220de5b76511ad657b4435ea11343e33b47a9083a86adf8be849d0a	1691930827000000	1692535627000000	1755607627000000	1850215627000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
304	\\xc0f2ebfb7913b1cef3ec246d419dde802f4a138f403c4c49ade5730b09b94f6fd19be790f623f519690f156bf132a3395c5b9ea3ae4a06c8211ce41becb26b8d	1	0	\\x000000010000000000800003d152f8a041a6e5600e99b73ea1222e990d8916ce13dc01a58d144188f31dacf4669335ac42d8933854bb8ede67d8c22e9cf7e448951be82fc7d22ba408ff895711efe174897000db40412e80fed9fd7b973b812b0a0ec54ce0de68ff60ceb6c38ac21a148eef65057856530f0d4b78d66f4194d9d42130f8235e9774010e590d010001	\\xacf3c2f2a293c570e9310ae6e0b41bb1eb28d9e731974e4bb7badde80fb63642955404a9907890980a6a157e552d412b0c32f9e6a4af08dea1f9d130c1985c09	1662914827000000	1663519627000000	1726591627000000	1821199627000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
305	\\xc232f4c13ed0cc3297cb6b0ff6e55c581de400440921c5f9a8e829720ff9a197b06fa719c7474eec864f5888afa9fcb7d7ce2b2b50e371390dd322917a1642b7	1	0	\\x000000010000000000800003c741979168a3325374c48fa47f1f25c5e59b7d416b2becf77d9a9fadef9d2c3bd2c30f5ce880d8957933db0c774a2434f6c778186cd622dbb9c506870bf4249c18f7dbe9b22cb0f9a4c852050e26a15ae57d97e7fda0a660c07492951bbe404f06a0e209aec1e3709d59bd7de36e855d196cc8c46ff9087e4cbbcd5d725ce103010001	\\x3feaf5bf1b04de5bae7ef1a2c1e201c056731ec3fab389b4c8decd8b0c7032a29c0054fd8e33902994245d30caa27e8f313d279daefbbad43576b627785bdc0c	1688303827000000	1688908627000000	1751980627000000	1846588627000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
306	\\xc8d6fde7620ae9b98c3168c257228c89000ea5f7c4d6b361f9a54175770afa4f7c9e7cbaaf6803172654085fda59e36cbf161fcd0b33bfd3d421ada6d5bb2298	1	0	\\x000000010000000000800003d324cde90d842874f4cfa8f235a0b0e6976a4b40963ad31cd39b51a78898c6fb7d945fafde93333e41c3397eb16bc3c4f22a7040108437368664f630209f2b220de2e9dead69db91e6a96f413648cbba9cc6d62b22f2847d8aff4b1c34cbbc3e534b50114d5e0656d0ee46ab62a4a502f5f4e0a500c100aea5cbc59c48c8f68d010001	\\x22d4b8ea9d6fd0e07f986c55f6da93f6818c158609555589009eca693e893810e24a988313e305b9c7f1af814f3718dc4efcd0bf2376ba38c9016c3c85628100	1667750827000000	1668355627000000	1731427627000000	1826035627000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
307	\\xccca8e2db7275f224781f2d04878858ab9b1b1c115655f9252ddca640ff180220d6f28f62e3aeb8837a550590b22f2c8597e3da7ee192af6fe2a597159df0bb2	1	0	\\x000000010000000000800003d07670fa986c0b45d462e61cdadb80755e3a2e004a43edfbc284d4522f5caab4904426e3d1a72897045ff4c2edabedd2a4b5769bf858a5c453e34f805cd33fb74c328da58d61ee2450c02b2b1f140a6aac5f66f21b5ca878436f36f92c8f5f876f3e4569fc09eb60d6d4104b32d5e12f178e9fc784970adf263b012a606b9169010001	\\x94da5253ddead998aa47b89c1cfeb6ed297708910149684f472a501724f6f8a7814dd1695ff103773b1fb392e980842a9ab852d3331d186ac307583347ea180c	1690117327000000	1690722127000000	1753794127000000	1848402127000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
308	\\xcd1ef49af1db860390abc9cca3a76190357f268c11dbbb720a67ece56663203a9ac0aa8b9dcb517476583c0d167610889c0381963286e7a8c321f1e761d241a4	1	0	\\x000000010000000000800003db9ff259dbcbcba2f7abdc12d7cd9b4e6a94f224d91060f62eee551e96ccfae76db0228d67263a191df43a21b445c970c92f50fe2380db51c99dce175422d11f96bebadc690f75901b49c91122079e4220250a665e9f7ce5734d3a79a611b55f747a803099853bd2eee82fb309a623ee03f0123ea6ae630c4b5586389fb23aa3010001	\\x25fac35062773ee2181fea91a9b605ba97d37a133b3bfe15c7dcd768f118152c50b969b4df884e980df5623b1cfbb25ed70a7cdafc5a9c27a3e1b95fda3af707	1682258827000000	1682863627000000	1745935627000000	1840543627000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
309	\\xd0f619a72c61fa35648ad93e9f631d95733385234578d8bfb08150a0a332ea447d2038be50197e064219c9b68477bc725c28c859525117aa3e2a0097be3179ec	1	0	\\x000000010000000000800003d4e9fbb0d3c64ee7f72b6722043a8c4a26f9dac33c9923e4563775d14f4fc8879b6d3337829ca0886ca0d9fd96251874eaabe2007f124c1e4d1ff1aaf9fefe3869233fbf30749ec9edd3ee25a5324b810222801de861be8012ecd2d17735b30d1f0e61aa6420bafe3776a0d9b320b5c2487c3b4db8c0c45b427159fb8e3e3359010001	\\x94f22f7cda33eedcf37a9b693f6bf9d3b0f0911f5a516e171a63b7e2e0dd7f51d1100f77f4c4763e329d28eb342e930723bb8c04fa7dc4cdbf742e7988968703	1690117327000000	1690722127000000	1753794127000000	1848402127000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
310	\\xd016a1c66061860f6b386526b079917e7e61bcb50666e2f5a7bad5d7bc29fd2bbfa6ac83d45036b5f125f79e01a5c9f95256d5a4d69062e1241cba8ae7570a32	1	0	\\x000000010000000000800003c9d5e452070403a7a5163ddd39769674ac6f4d3d8b6143c6d56b833d409db6d6365f836d11b2f0f22699802c13b7575c3af59891eed02344b4809327569d8386da0062f9f1efd5d0cc3f2260e6bf777b360a3c6b74faabcfdf985ce0b9a21a081b6b9f6dc764148d356688d74f8b6827ed10892e02bd955be93e796c85886851010001	\\x7ce7b1c70d9928a5124029de1d49383d947a77c7d0a0bf3183f75ea36fd72bb1b34ae620713aab04297fe3026e717454a5cfe44ab93f55183c4de13494bd3c01	1677422827000000	1678027627000000	1741099627000000	1835707627000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
311	\\xd0bacf8314c45b4ad836718eaed81d8a7cd500f3d0ed9b2024b4115ca01ec3324016049e33dd1c9776b311cf3dcc0134165b470dce401f7d3bd179773d711eaa	1	0	\\x000000010000000000800003bb86ff6abf822580ee2e707c0137646d5382882d84a56ed21848a534ca19a32ac52d4f126c833da45656262663bc03eb5d3acf289c33351b2f9acd55d9a252127ee012a72d2cda4e0fb4a52038b1b4f1731f4ceda35a42ea3f1c5606ac7d6c53bb699bb8c9b124daf9406dc2feefe679fd489e6e41f78ce2d31a016d623be3e3010001	\\xf5afa5c9983551094ca64b4eea5f5ae46804bb85b4b9587b24429c98e152f235b5e1d80d0c35c2573a5c881aec929f96beb0db606bc78a4117caccd42c6fcc02	1667146327000000	1667751127000000	1730823127000000	1825431127000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
312	\\xd68e04614bc51b9474908fba2c38a703d5f95cfdaeafef5e3628be6ea98c4ceca835508f88cc776886b08284635ce44cfd38cfe888cf00efd06aa3abdafa1280	1	0	\\x000000010000000000800003a927043ab469b36cf375f038fb7a554569b9d35f0e8117e9f4a309d8c939f438779276ff30e841a9e4665b4d19e0a380acf60d8bb7826294ef956bff4f3f09dd1ae33667c632eb35fc09f7606cf1c9d5c5848444723a9cf04fe6bf1a5f108fd8d2e0f520104efde3c525f2031eff1d009bdbf8d9bd2dcbd125503007ffd84879010001	\\x29dd291c862f411a97c5d77aec31ad4d147eaa322e616c3b8bb6426686a03e28ad2626b25f0e3d1393de60acb0808d6fe969bc9ba9488f906917db3ed807120a	1671377827000000	1671982627000000	1735054627000000	1829662627000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
313	\\xd7c2c9d180349fc024bdb75bb05986a96eb4d02a1a88235b1722ed70d4badc4325aaeb89a5892f8ff04a1a844d67befa473e502f3f0e324fcb4b85ee1fec9c56	1	0	\\x000000010000000000800003bd48167aa6f5643aaa5b7d73a124eb0301de94fe8fdbe9debcf860990eede23d649c0a82543555a75d9e0b4eb9395a6baa042801ba0126cf6c3e9e7643cc4fef9229e563d445cdcb0db423ef66cc6d7e766b8295b230234c0a01874e87bdfbbad9110398acc4a837137c171f1268cd8b27523541a815905ef8764154f76440f3010001	\\x72d7994edbaaaa9c77309f8dfeec668fe6d2e66cc92a694b71c2d4b7227edd25694789de6ef7c35177ac9ca4ee11b7ee368a0af72d0e01ca8ef4b7516c916a01	1678631827000000	1679236627000000	1742308627000000	1836916627000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
314	\\xddfaaf3ad871e0e489b63be19c5c39ed0b3cb6cae5ff863ab8c6ea9e2418ecaa6e4d7daa50c4fe4ac4367dbb4fced01d9af4e6e1cf209d8578d5daaa1ef84e8f	1	0	\\x000000010000000000800003f9dab9b1740a235a18a1a270acee2e5dfae7a04e8402f297d82aba2af2200a9ad0d682ea74c671b8b3601b204ada05aa491aaada6dcb423ae3782a54e5139f3a4a0eb5361d2a163a0e78d7e755987561a9184963eac19f4bd7bd3241c935d432bf9089cb2b9cf23a2c962aad542e23f2bf48db5390b973c1f0ba1d623812417d010001	\\x600ffe2fb32a14de5ab6d17970b1691f9d327f732940808a20b5c328c3b758ac9d611171596108472e31a0ae4ada61623adcd9ed0496f3ea11939ab918ff410b	1673191327000000	1673796127000000	1736868127000000	1831476127000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
315	\\xde56dc7c09abc3af56fc71683b9e7dbb6abdccf572a068491393e77b041ab11dd796935ffaa324d4df68e94e7fa7fe4a55ddf90de1ff37e21ce03712584ddc0a	1	0	\\x000000010000000000800003b425bbcb2e251905a5bdc014b3aefaefc8671b7de39f10d036351706604898a11cb80881536c4e7edbe7bcaa4d67dfc516a4454995940bdf47e122c17b76b174b01820a1cfc40a8e0fd4d525cda17be05f83251f20ea02004a405853070607f480ef96d1c9b256604df427d46083668156f316b41e3fab3872954928886176c3010001	\\xace581f5527881e7bf3de0e683b64a1109f0c4a99c083a0f6b1c07b621736194a3f984e0fc78e1d4755a5bf52e9e119aa607ff0cfe75d8db126d25bc731ae603	1682258827000000	1682863627000000	1745935627000000	1840543627000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
316	\\xe48e57e8323a6c1c3586beb93671dde3ae33e7bbb6d903a3451807f50fc513e3fff356dc5e62fd40a9d2ad268e4d5d93fdb050107de51c6072a475011909de12	1	0	\\x000000010000000000800003c4c4532cfe22924606bf795884db648ee250bb4c5ce26c524d6f9f3d0da916af13328d843bfde2484b185f249dd9e6476ac11f9b680107c1a0a4ef0f2367ddb9a587814e33574026ff8a5612482f9f4ebd3ac2e8cc2085c1941ac1db0877a6de740df35a88363435a7508aac520c197ca3c958cbcfa550e615e2ce8755745761010001	\\xde95cc499919576e703ae09292d7039b4e9428f625bcf56c81ff96c40c30bc76bb31cec9b12e55383695c1accb636a14a985a277aa1be570eb979b17a69d6c05	1679840827000000	1680445627000000	1743517627000000	1838125627000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
317	\\xe50243a5ab03c04fba37e869d8299dbcf5f25fbaa4f3dcd05172b434cfd848ccc78102267aed1dc97ce993df1c9111afe9433d6effd9f3f208fa7ac5cf9343f2	1	0	\\x000000010000000000800003e3f4724e4ca09b433c4ae680cc675c2e35a26a3c26c5ff409c04f39141b3363771760589303900dcc1fab151b5c3948aa422b2cfd9d1ddda7ef7d9558e13079672248619dcfa12c4be3355b4664f6c6a93154c0a30eecfb98cb4523065b2611fa7e65ef2f549daffb04d6fad8d42dcf9251d02cd230814a2971abd845f5316e1010001	\\x12bfa76d3d64bf92c7cbe88e8de9fbae423f427d9c9c99065fc78418fd192ec2ceea4ac81998470cd504435ec44332e11bafffc03edd93fe931d7149689b5b05	1674400327000000	1675005127000000	1738077127000000	1832685127000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
318	\\xe67e11be79eab2ebe0a67f4bde83061729dd6b646d5c5b70703845cdb52a7540b6ed3d40e1a52a83ac7f65eec5f40eaab9ca78735d0bc14666d8875a2516ecc2	1	0	\\x000000010000000000800003f53f5b996189aba6f0c9720fe09cc356ba4b53f4fe6a06e2d71ebd0d27df198ad7a0e6f79fb08268dcdf9b94da4525295d6b0c6afd2d4b2edd9f854aa146da69cab140fce25c558fac87b2c61fb8b8f7e719ed6a71e2d9def825a7fa9380307d988cbfa82e8017e4cc77cef7dfc74036c3883e0e4a21d6b9be9d21e8c9b01f55010001	\\x1ec3c95b5ae6381b1b7b0befa73136b4d8c94e497f41fc53261eb6adae15aad9978ba919127309cb454ee765d703ecc59b90e208ef667b740b6258cf9119f603	1683467827000000	1684072627000000	1747144627000000	1841752627000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
319	\\xe86aeef30044f15796f94bd3990c21e93d0f2b4687f5d947db09efc7c8fa0ce7c34a603b7243a157f75b3816f41a5ddaab0de387b20cd5c7e0549497bae51901	1	0	\\x000000010000000000800003f11a054764f7b296ce9f8bd1335d4e60e6137ff328001e4d2c531b87a1ffc478ee214d34bb17ba7596d8145816486b27518f1e80d49417206e36ab3fac6d9509dde8e36402fdc266ceae5a944d4694c710d4b1ab8ad1618878ef596dc71bf185561ded454dbaf6365972e20b5168df2e6a72b29a8566b00403fed8f144a7e295010001	\\x4d94adb9b23621ebf2f3e8920425f7a7572e31ebc70890618dc712bb0e79af5ac062675a6a7025e696c39f8bfbd4a3875e461341a05527aadd9b2c4699509e00	1675004827000000	1675609627000000	1738681627000000	1833289627000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
320	\\xecf61e20d4663d34e9ace07829f813b680f1fe6d733ff3159f7e8946505ad00eb7c6c56fedefba76d0cb852c0dcbbdf207d3fc4d0c7fb5efa3dcf348d79be831	1	0	\\x000000010000000000800003da48c3f1b0449d22374f67bda116154e045f9d475c3d3231de9a89315b0da6a6aed1e82c44a2d35c6ad22047929ab665375ec9dd35400439b494caad65af86fd56841433c57e866df0599d3471fc93ea98d13147face1906c272631e2ee114b9435d845c9d1e5b0cf30d382c788c70b6cc927622ae224af503a45c1474480d49010001	\\x8a4c04e313d85210f4b430db77b8f38a518f8e70999bf9e5ed6efc4cacb0740d8092097ac05e5026817da3eb43c27594fd665901730f60c2cf6650dc3110fe0e	1675004827000000	1675609627000000	1738681627000000	1833289627000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
321	\\xece2e905686919d4cf72b9fda0c665883117809af8786d18b4798b121808378eb1a9a2c60d629d7c40fed6be1ae0a80eb3d1cbde1b344e65e6f1fb0fd1de7eb6	1	0	\\x000000010000000000800003cbbe1cfcdd8bb3f7f1a4aab75ecdd07e7f408a3b6c408c75b434260569ad69cfb950b8605ebec616498c3f402c74f350d38e2815de29be6c634342e42e961cfe6022db6abf2656717600bed8b21a4241c450675b197d950c72d99d3c22cb57f3c457906e6c7866563a76754868b78349e094ec9f8c93052e2cd0185ce5dc597b010001	\\xdc5c7921125a16ddb99b1b163b3e6cf81f092272730639537117903e6446f4635199f6009fdb144fccf7399eacfd6009bebf5d4d54ee8172982d0f959945dd02	1682863327000000	1683468127000000	1746540127000000	1841148127000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
322	\\xedc605c047ef6af664530ef31c58abc82e50c581d4f66c75efaf6bf34cc5b98583b44c8b57478db37b7ded14e0d9ad9312f7e7f53f18773e7f4e029460ad569f	1	0	\\x000000010000000000800003c0b9c36522e65b44f0b153d61d2ac95e0b199764ee4d0e108d687c7bd001adcd4e2673642da0316070401036a11fa5d46649f5591c4b0a6d6498ae74f68324244c250813a7b7ffbd5c5f3ef4e5abf178530ef817c3f5333c141a9e4eaf5c3e774f6d2ee9097cfc965ce915eff0f408c6bc2ede529e9d52c778dc0b7007d6a8bd010001	\\x9e9d43bc5acd3ef4ca4c527a796abb07d39bb38f5faad9e576ddb29e01bc45cb9bcf18f28eedd0e7e12c5af63a1b1e5f22db2b96fb2d72442bfe09d70d50350b	1676213827000000	1676818627000000	1739890627000000	1834498627000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
323	\\xf96efea13e34cd636ae1efca9ca6295818051d6a08e4e76ea5820abbc76f55cea3fd12320dfe60818e07e45e30b8a126b42b5b8afbf17c16de194ea63e44e7c2	1	0	\\x000000010000000000800003afb95635f8850ade8deeb9563160a5115ce9dab97746fe48df854142722095eb7eefeb01f5d4f8a1eed40fec4dd3787169b1ac4653c7e519b3023910d22b43ee1f32c5403fb72521725faf7ee029be142bcac68d944c5bce277206f0272ef29d2c60c3ca39f40f532dc170e0c99fb83f003a0bf8bef6503484a8fef3af1119c5010001	\\xd29ae22ed1481bf23b0fbcde6830d8a4dea75d5d1b0e58bf84e2476eae3c8a4244a0bfad13ff22b65bef1775a3cbbfcc5713e9922a1cb30af26b4cf078bbe604	1664123827000000	1664728627000000	1727800627000000	1822408627000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
324	\\xfa1e3ef9634b4bfe08fd5cea0f5e41b06bac94dc3cf71cd232cc8f4636c8448559824590daf99ffd4997ad501525a7611d9aaf6012b121a5f7d0753f8623db8d	1	0	\\x000000010000000000800003b7fe5d2ba95ede5d3928061825c1d12c55c068699e439bff9a5574be984e0f84e0213b569a359d84d4e92172deb88a3d92f9e89350a232f3cae460454d258c2cd7b3117769ea573bc7786cf5475acbc59da27ed210c5e2dfd8b04986e2348ea4da4cde05f349e862a75f9b43ad4b024b0f505209b2d0ae6bd2d3b664c9b8d62b010001	\\x8f3af844fdc8c462f9d73cf747adde3b8b40145d4347f42597537422bedff4e95dea2a413850d87f02d062ae9cef20c1f57170cfac1e195628db364baa27b40e	1691326327000000	1691931127000000	1755003127000000	1849611127000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
325	\\xfaba46e31e9e3f1725c0c84f24e4a89f919cfb21c0d7e8327c942a756b1d2cdc5fbf8d481da0929f231503a36bf2fbf718a5cebb7ec60918170269dff98ef41f	1	0	\\x000000010000000000800003b742f64af7018477d3b8ae8093d1b1479a08f5f6711bb815e26913ff2e991cfe24c700322fd0850874715084d3a7459e7325cc412c1930c2deda7195ad034e924800427ea8af257da8f93486f9b43a262853bd9fe27af82d3581d0306b5dcdc3d91320010daef46ef40317a597c5d54371db3b630e118bbf9264ee37e05dccab010001	\\x871aeeaa7fe6169bfa6b2b61109313c686c6c5259460792b1f6eba045f8ddc06b1bcabdd750903050e12dd8240dda6df026f59899cbb87a2a4c865ceb575a103	1664123827000000	1664728627000000	1727800627000000	1822408627000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
326	\\xfa92f9f73f883b17bb5153798dff12e66bf4b3a4c855930e86c664d9ff367aa471d74ea6e5930e0aca45eda4a3348e3a129a5f33a264e52c6f7de4baa5f13522	1	0	\\x000000010000000000800003c6f1aa0e4462028e5b784432b3bd89293ee2b9cb3d2caae3a2e52920060e0a68211f89d17f45852e13ce9fe4dec91acf9204680f64854ebbab282373b1d3a9f3b321366142f170c37308c86be458d0f7f685bbdc85531cd269ee9a71beedab7934e42f27dcbc66506e60bc696dedae0b65a7da758e1190b54f182a64a9884725010001	\\x8a4063fea00b1019a63bc6c88c945ae869ba7da3684d35dbaf02bafc98eb6e5472aa57e75202c445dcf8e606ed855e0b00943f0b878c238d8415e5ca2f9bb608	1686490327000000	1687095127000000	1750167127000000	1844775127000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
327	\\xfb8235f8e789f2c49607a8e17e02674c74805b2a23fb4dab15f79e64aec2976f28cf26d8331cc2ece66186cd506e49f5d77b4fadaff71febb69eb23143513f3b	1	0	\\x000000010000000000800003a741df8562b93c5c313d55ba5de371a0d3c6f04bb21cc850bbfd84c14eabcb21137e960b110ac74500ca52277ad5ddf91d1876da7d9ba4a375604b240f3219ab6d48ed414822eca32e7a8ea65a68efe8f1b3bdbee8ff11b00fed9df04a119c7c3ab5040ca70a0b9c9330c2f226dcb0548f3ca29c123f600ae21747991ce93fa3010001	\\xd0d157a6f285a164c5904a7ea6e30c7845cf1717a69af6ec40ec5a122d099de670a9cc56be6316ac7a526654455f5fe0fb75d6227dbd52cb1f6b29856c665103	1684072327000000	1684677127000000	1747749127000000	1842357127000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
328	\\xfbca18720ec93f7c74e962006c943ca45d932252c110ba37c72b87ef4764a09b9ea09ea4684e2c1ba0f25924752bdf4aff4993f6a002eb81b70691f250161695	1	0	\\x000000010000000000800003a8c9a70f300e90093926c43ec24d41b39a69ff13b03a8a9e7d888fe414495fe70cd2840daee0f579f79c1cdb486231d1b2d102ab771e783e4698eea2df5f578abb1b8d45653cc404a84ebc1df687b3aee0695db3ad34593d79e8cbae5d57e38d48bca398b7a37e66211c8e517cb3a9694679517fd204da02bb527f99602811a5010001	\\x4ed689feb073bc3256064b972fefb84d05f3d62dc7c61c7c2991339192226dbe50ff46677b5de5286eeb44e4c424b3584238b2ef8f4f66e91c049d1657800609	1678027327000000	1678632127000000	1741704127000000	1836312127000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
329	\\x0103e17c3e6f9c3b91c6e67025235c7b8e549bea72dff1fc13a47c4553b9837b4d92aa8364bc08ba97e47a322f1478b287f95ce7f47d8ab92662e406fd8d7e7e	1	0	\\x000000010000000000800003a443205c1f5e3188f8845955baba3f70643b9b4d4ad5068c5000699f3d79f4708083e8e1ebd12750e9d3464c1aac955fdb3929a624f06854ff70a13ee0a7a74bf3d7d5a3116276eae22cf7d76bd0cbecc907256522806ca7a6f1e6ae3de68c56665db238a15606c9fc886bab1ebcc16da0eeb5179b897492b20f117948c5e42f010001	\\xe8cc19210566bb3348b092dd9e7c2382d67f8a214acca9e9e9e58400ce9635a435f1292a09c57897d7d8bc179cba09d16c7a11e6f6d6691e2001d12b8f3bad09	1666541827000000	1667146627000000	1730218627000000	1824826627000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
330	\\x025beb21cc5efad2bdaf34aa92853c5db4559e571a4ce775674fd6f7bb26522adea1fef312ff61d0e7d2aa43ef6ee242bcf71aa4f69a1d062be5fd7ada510457	1	0	\\x000000010000000000800003bd24ea60b682804b407339e161c92cce54f07cd70e50a0e6ec18f00390b1bef6991731707858a7a5ed04db3932d43c51d821fdee81702d772b03bec94e1c9a3ca2eed22604fd8a8492e9aed113a1332d1fa13150c715c87b1d1ae9853f40727c33a59aabec9ddd8c85a61a14d81d685ba20d8d29a507b57cb50563b4f4228e01010001	\\xa5d74a7e4990106d12af6a18ab20c2ce6f0e22b50049cd81b96f9de43e4c6cc85338ebe9b8f5358a34c609c559c09b3b7e5a43f2893c47a3cecd66c7fe814905	1690721827000000	1691326627000000	1754398627000000	1849006627000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
331	\\x033f8fe37254fd13f2ce692d30e951a1154cc6a5ed288ef98026e337c3e02bc94fe0a8acf29ec7ec994580a1744f5fd9ec83e44815ea3df54e67062c5093a6d3	1	0	\\x0000000100000000008000039a281b42bbcbb0339ecf001802b71a7a24d3e1e3ebcd786f8312326109fd91aec49b6f0e104579bb44ff76816dff0c9c1f239ae281e880421c03e5582a1b7858fc8b79d4a92ddd09db04e8c4df46d778555e88450932694fdd0b11cbbd5718c2107ce9c2d8063ff6096cc159e40ee44db20a6a4bd88dd9e9a907872b4a3054df010001	\\xebb4bf9add095897b640bc2f0e9b62f20c955a09398f602f5e662156b56be31f58eacf0e33a5c556535d4883dc19a6b80744cf43c04029794da5706bfbf2090d	1688908327000000	1689513127000000	1752585127000000	1847193127000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
332	\\x053f982eb188a0f68b7e4b947dbe29b9e128b8aa55be950a2a17bd93b8e67a3060c9110d8b452e1bb541f6be0b5e42485a551dff0de03ea467ed82c2de09059e	1	0	\\x000000010000000000800003b0466996d5e38d58646e611bf9df60af606e32efb2bba00565c9ff5533e7dac61f3f88ed7e534fb6629d70e76d220d0a8896408cc717ac09a3e4481300460a18a4ff8e75da286ad2f080170a66777ba4d3a93eb7ba38e7a88e9c4620a54a9b4a70d7ea2f037ac38868c9ca9aea9622689d84b956e685229271c6207340884e1f010001	\\x7b2b0cb713131b32f180ea4d46d03dd5b4066a582f7f35566d06af4d29e93cb96580b0fcfe6766d968c8c1188688db3e4b991adbef43b616cef26dd6cdb8c802	1673191327000000	1673796127000000	1736868127000000	1831476127000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
333	\\x064f639b03eaa81c65e83d1d605d4d94899b21926679922940497b0e9a6345559a6098748c23dd0eb566784f063e6d8a738ec2aff4f6ba09c46b94864475d1db	1	0	\\x000000010000000000800003bbfe5b3d15b459e98db2d020fc425a4e6fad8fb78b858ea9a8b13924bde73ce72287c04d5a299ed753e4216c879737f2c287f250c713c51b7a6bb3fdeb13ba4cc4263d333185e3feefcf07e9f8b6f94c8beaf46dcb7ef053f258ee27ebd26ce04f5a2c10662a5000cb4f25ec4719989500c70d94ba13d078141cf22598f10007010001	\\x1a822e9c756bdf0efd2f91b2fdff65e973c26ce6e8c8f8b8b46a72b24db4b312d6d315f5ab45a9fc1bf5928c08a8afa9df54c58d15da87547f7a99235686c608	1662310327000000	1662915127000000	1725987127000000	1820595127000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
334	\\x07f75b76db414297aacdac78d0b1956e4dc6fc8d4b9122b4f070774600f9097d5835ed0209b9195395ccefdf69f7bbdb5de0abac92b8e2a552732ea488ab5f5e	1	0	\\x000000010000000000800003b08943762fbf850d7fc00e066c74b9bb13f51e39b2396beb06a2ac83f5a7b35274f97cb373dfcfe54f7b0df7802a78c65d6d699c7fb01229251efa0d27fab80ea88e7f175ec9addb4c4168491837630b5b3b715998d54e6ddd3ebdea26fd0652dcd398d5443d3ae60ddcf1cd25c3a5557e0dcfc515e197276f6d2272f7b68f3f010001	\\x5c59ad6cab89a00d80a493569440edb26014b60eb247b536b2abd0d86ff95566c968313619b46886578795bf54dfb49580c77c22f90b780d3c38af2ebe34ed00	1687699327000000	1688304127000000	1751376127000000	1845984127000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
335	\\x08df2e480a56cdd5c7e6ed00d6640e41f64b3e7e283d22e9800bb71d8bd10b54effcdbb6d9b79f1e3babcf99c82027a0ff04757e28c39e56edd087c04aa7f94a	1	0	\\x000000010000000000800003b213cdaa04d4f4072369bb24572a102b6eec3b9fe559ff208c1800d8a8fa7ab33a3e71bc562d136fbb5f8a2e9c96391d80728b136736f1c887ead95b2a3096f3e18cb0897e992347da5e0b5d6373411a90cfedf89216f1bcb35424537052fa51f717fa2d3d7f246397c2008ba9bf8ece5306ffef724bd12be697e171c02c6051010001	\\x386a02eb099ad7990126a8a74385c4734e31794e60978a297288dadd57ecf481d09b379d4d2ef38353156d631c89c419b98201258ed109ab6f64ccc1ce60380a	1691326327000000	1691931127000000	1755003127000000	1849611127000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
336	\\x0b27827d5b9ae37bf0fa7c4b3776b2960669001231a851851cd3b683432ee5f82d2dacd1b39d2a60c2b9188563afec8e5b5ab659b92cbde931cf60bc7a3f4ebb	1	0	\\x0000000100000000008000039da07f9defe3004f91d4e92f9d4f76f47cf1b77700c7904c88d6abdf8607620534f49451ac385210486acf86540f844e5d87aa4d7f87974537661672e8c20a31a097149d7390843f4e786e97adebfbbe497317f8377f54708ec8d884f26f5d2bf8ec45df13d706ed6d3a910b7cc7d540654239a7a5a5b280a435d844ff4049b1010001	\\xa86e0f2f76f194f35f45e25a619b155fcd611017002694fcd84290d3bda876741ade2e3d8641a2d3bc7a31f3cc26ba4e0fde73c8db7c3f31ee6f4cb26255d30f	1668959827000000	1669564627000000	1732636627000000	1827244627000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
337	\\x0d9bb89fbea31f910d85a17405792d04f0ad95582d800096d90b3673f9dcac444b1490a74dac7daaca7c92608ab27c970c1816167fdac23f1bdfe904bca339b3	1	0	\\x000000010000000000800003a58f6bda0681c9a3217b6d13c29d64411a6b5483ee1413dc80db0e6d22cfea2df4e894d8e646ebe4b8b72a216031ecc080301327923ecb0f842330306751439af1c1328df632d85cf4f3af0577f6913089e35be3e834b182416493021f469d30b7e4c29da9ee2432898a8d5d6aee212834b7b8eb43785d14e8c93e7debd60d0f010001	\\x51fc4077b705e94fe61c83f48e71c10c47c9e67fb284e713787dfb5da75e68f22a0c6677d2ed4ae914a697a03efe4d7a1b9f4f833c3ae777fe572652f00f8900	1662914827000000	1663519627000000	1726591627000000	1821199627000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
338	\\x0f036351b7fd55d935505f5278872a56146ac179ca1233e42ae616470bcaf846c1f131ba8cb8f45f34959915f73a38c8af958066eda97dc419587ccd919ecb2e	1	0	\\x000000010000000000800003d9daed5a4dc69bb499a9c1cfc4ce46f334e66c9a3f37990eb1cbc9755262362c7e98969ba60c4a6c989f47a974df5a256d651786bef36fb8a1900ee89c1dac3726c2c1ce897ea53ca0ce1168cbc5624c60affc16ab8fb20eda26c5b5d96ba4680ee8a49255a034dfc38735296e7fcecac685f8375c777b01e4da6beb3d06d23d010001	\\x39227bc2a4d37489e683cb93d66b5b656a2c85aac52823f7c513a5dcb496f4b3364fd0e5c0e36789cacebd40653288e974608456862c9f7eb1b86d05bd4b620d	1665332827000000	1665937627000000	1729009627000000	1823617627000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
339	\\x16b761371bd9ab5a685438ea5f7880a7c0359934338cf4eeede02a58ef37c869abc05ac2ab5e4e57fa97df2612fe18c42af8447a63c4e8f688216845788f85bd	1	0	\\x000000010000000000800003cb12df52ddbb7bcce4e16635ea2d537efa1bf7565cc381c21bf76c64daddbb7126015c9de40e2d8b3ae626413cbacf66af04733afbe53f51b1b37be508a7a3304460466cac23daa7e347c77284f2b84a8b6c2abc70ba229e81faa4631cb17f5261d3521ce0227e655a6f64daf293be785c582a65f37af313fabe3ec08cc8d651010001	\\xbb44b9c854addd18a706fe50d6fe39a94fd968a8dd3b482bed59d81528118f0bd48c54401fc70b4b9e9164eb795ac9c9ec55b8c57afeafa0f13432c1ae473c08	1688908327000000	1689513127000000	1752585127000000	1847193127000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
340	\\x167316a5c9caa786f9b1faa618d99fc2279d60c63ba06f6fc492ab7694fed2eccd7460b213cca7356f749a8d669ce2e041430791f99526eef995b67053587c62	1	0	\\x000000010000000000800003e3b89a07514c35015d0fd0567da4c3eee4d6286c11898b3fc7cb6239ecd8e9652639da4c1dc99af80f09c4cc2cb3f00f956f6e681e88a97de289be2bb58dd953b56b6b95842f0533ff22e30cc33b7168f736b5803b7218776ffb5a0fa6e03873120f7dfb272e86aadf1074f0714c951fda8bd7bcc20b0e1aba09a60adb43c6bd010001	\\x7ced9197f1383151f3db69bf947c5fde1a4bb7f80eaff9020af288b88355d40d23b1d606475ed38cf967f10a64f211e81e128102f3a605f1e95b7805de109802	1675609327000000	1676214127000000	1739286127000000	1833894127000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
341	\\x199fab1fd07697eddff8436f12bcbc08ce977ffaaf6aa5235bb3938b9673e3084249e1f7d51c0b7b7462f8187dc9ce7534d03321d297d747c71d0a725f0184bc	1	0	\\x0000000100000000008000039ccda749da1fc923a12e48471583a7a0fa797f9e53ad072baec81f7fe38ede68202df97a88cf1c18954e56e33d35c15ea9b4cec56f63a1a011248b2bc5c981643f51d35e907a07921ce52a6ce802a27c16b6757825bd248eee1eed8df69d8ff97e13f861c27c812f9d278cbc4ce91d7a4b5ba221aea2e0c456334b5811eecaad010001	\\xddfb8bbd0008b8eb34af12f5391eacd87ac511d2f9d119233e097c9ac0f2d459125ad4a823556c35db1805a18cf99de92525fc34c10a20f6aa9f86bc00594705	1669564327000000	1670169127000000	1733241127000000	1827849127000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
342	\\x1b5f9795c69ba648877e1744e4f2713b625cb77acd6da6a6fc7b1e88eecce4d9bfa9dfee79bc0663ddb32abf6ad3205d8bf040aca0faa6e8ec6fe509fec3fde9	1	0	\\x000000010000000000800003b1262484b02d3613c94bcf149c6f9cf88d0c6c695472d2331e245ae9ba397b93619b5dc9a677ebb68e976a59ad2107d88f05894ac1c40d6059bd5998513f6774c7e5a06fa7d6161517628e657915a1e7e181c8fb561a2769db262d2c339e942a02db106c2bad16e9c9d489d5727a481a7931a6e518756baa1e2e31f3f8d134af010001	\\x8236684ba4ba0202320211bb9360e82d541c94d8e872186e5a1d7502e327b9b2d92a3fc3e5856d715f3efd69b414fca1003d2d3b9cfbba86c4837fb0da59420a	1671377827000000	1671982627000000	1735054627000000	1829662627000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
343	\\x245ff778898f5f6de63532a97f63262d6460cdf2dbf7c31f16a75e241ee0cc25d9e4d82dc16ad53d3db7d1dec0f03a5be9688c58fefd3b6344e769b2c7ec72a3	1	0	\\x000000010000000000800003b56b9b5f52ec3b433b6aa5b993af626c79d5fd89c379bd444977264409703c21f84fbe0790695fcde66926503e2d837167e8fb6edb9f85a535ef4c0d4bf1128ed2e8774d5d76a62c7071675ddfc41f708a011d5913bf317b18a99178fdb22f11b2a08eb3267ac5159d227ecae2873a26ca482119ed6aa64c30844b0aa4c61203010001	\\x4de6e6b6a58bbd943d0f5b10bfa39aea4f72aa3e23c4b7ba744140f973090cd261fcbd4a86b22165517ccd83f8c2f72eb5814ea3fd8553edc72795df00776403	1674400327000000	1675005127000000	1738077127000000	1832685127000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
344	\\x24bf2ec7286675402cbc8a15aaaa0f845054c87e885ceb87fac7ce9d285237fa97ae2472cc34328d2bc0bf9aed6ecbc925de1a03b9fef7bea723fc61c51d5c99	1	0	\\x0000000100000000008000039b4492063646e6f1e7a00cefe245113f3a356e68271be840a38f66eb78db841af86da8bd2db7fda7570943a1ecdea072d9dd981852a9fcf126b07efb7590a2d211037c24156c3882c2c80e3f557413a9e675912fc49ad0df6f2bf61eade609f178796dd9beb1b6cb2741b9240bec8b80a03a24a713c14f0ce904d62bc2cea57b010001	\\xbf0d165d894c46e152726a6f9c4d4b3ad645e0130387e58037b3569d2a3040331266786aca5b25aebc448df48dc9c6d567996b9ee51f63c90e3e11f69f13e806	1673191327000000	1673796127000000	1736868127000000	1831476127000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
345	\\x2aafaccfc33b66fae8e81b31966e04a8f347c46f8c97fe1cd466edae09da418a45c1df30d0f2f4d80befda4e4bc54a25bfc9e96ef8fc754dc9ceb417e26036c3	1	0	\\x000000010000000000800003d3d8568693f37e90f42c346f829f97cb1bb6bcb9a5c54ac34d7cf76195ff2b24def69163a2d0274c376852d1e217b8a60fffdfb88f7e0c380ac0dfde1b265ec5683af85544a4c57c9469802c2bcee7408ae697a9cf3ba8719a18affca16d1264f164668f6449f11477003779a9d874972aaa99f8c8dbce824a5fbfbd76307eab010001	\\xa326cba9d112abe6206aff43ad0616e5077a872126615bba4a4f322c0d641c60e1d8735fd2cf29dceb6f1da3d7acf80c1e0c895f95424ccf8533f62d10510609	1689512827000000	1690117627000000	1753189627000000	1847797627000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
346	\\x2b8f024ce4bba83f59512d6bc6accb7e4978e2c39ac758abfc8ca1f6ba979876105bd5491b8e3b4500551bf8042022b6ca699a43f4496c8fd1b8a8b49fb54093	1	0	\\x000000010000000000800003b4921244e001c5db3c210ee93fbafe9c24b213501445f604dffb3850a49925402b82f52a957c497c97721e46e7230be86e2757f0d178d019e9c0263757188fb9b8475dfa2fbe10336e94c8cb9894b161f519ed7e9e4adccbd1b3cb8bd73c276d6f1b5bf569218955118f0a4a64788b4060bee4947802a33a7534703ae5bc3a13010001	\\xdd34af9eb5016986bcf1b92877752a29b52c1d8383b38c57a7603c10846de59e687e339207e6bebef55cef25064e8cf83b9033f6c196dc984be24c4aa3a0fd0b	1680445327000000	1681050127000000	1744122127000000	1838730127000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
347	\\x316f4f0e93786274872ec2ee11015da22873b75f41930687fbe9e5ef0972f8907e15841863e3ba33e4094e64fc1a50f22e91bbd5ed0bc0ee0aa5f4e35716eb1b	1	0	\\x000000010000000000800003ea97c5d0959477a1574ed445b1c5bd13c15490f497424c1f6478fe11fefb8b5e0b5fe5392186519530e1fb7fae914661a9119b0eb641a2616be5f10cc7984b0ed6e1bca154094bc4697112b1193d0c5375591df3deeab941046bbfd18b276e8dd7e13788dc46cf2149086e3e387b20e2899cd8c26854b4a8eee5a679f2789e01010001	\\x2db6462c919a9f9672db261fe0b1d462dc709df43319bb4d34b561a60f2818bd061e6129684d1bc39f74b60be65b8f430bf504cba13045aca0c1b4248a797a0c	1664728327000000	1665333127000000	1728405127000000	1823013127000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
348	\\x35c3be99c3233d2bb8da5f5d6fa8b16f3416913dcae3150622e5a9a4fea61082a97c9ad479a5828316c9c536cf0467debd8fc91cf761aed9c2903e284b387d21	1	0	\\x000000010000000000800003e52991c1e594a7d1dfe3acf4c799b6a7727d163fbe3256a9648ae53a6658e9d45d1d16b47681558f50554d3f8a1b379c0d27c81aa06d98e5dabb03b12007cbdba84f713ae05a09fa41f7c7aabe3d94c1f243304f9401b42fc3fca7307252f6d31410b8eb7feafaf4fde8c83a13ae26287bf97b1358693bde1bd11e7270a683e9010001	\\x8d9fb144803084f3dcd6f28292bda3dd10a655115e93bf8ed98c45a048a2e00ecdfb91a4c924f93d742ed9b6de6f111c39c77489a36c77adea16a1e399f34904	1663519327000000	1664124127000000	1727196127000000	1821804127000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
349	\\x36bb7db310c31e79e5a82624e902ed21174a861082549c0e83845f458e0fb6c402a0dc1eed4ad3a9f1657a905c9f7863a28dbb48f9c9b2c15575125620534aaa	1	0	\\x000000010000000000800003dea06622fe90b72675421d201e31d6daf7e23121b9ba2e3bbb8f12c74889a5b869881f5724d1a7aac8937857a7251f376ed2174792c91db5a9d1b70ae35cba963c8df449a3258d8bbe54408d139291ecfd4cad5b2b6f8fd7ceeb75b6e2fce0608b053037c39c3ed0c78b50a8d849947b55cd65a774488ad1d2dd7ca68e50f007010001	\\xc60e15200ea9dc6a3bbc647788032e037edaa0e60f2469c324d9f336d50064c526d37fa401a1ae61dfb6289850799202c74f880bccbb2abad439a6443d91be0b	1674400327000000	1675005127000000	1738077127000000	1832685127000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
350	\\x3a2f0af2e7b2aecca09290a8d1cbbaff180679b7cdb625aeace1b61d1209271117d97687df90fe086a4d9d3068e6a10991bfe35d4e1e10f52a36290769e77fd6	1	0	\\x000000010000000000800003bed5e95577b016c097155dcf3c594bb42f39129699691625440e4ddeaaf3103391a90d01ffdfbcf9af291699c58931b4a5fb9bb1ebe0615feae855f8f099fe7136e8882fa7bcc1b737f97dfee21a01a4284ec12052cc1038ebf794e2d1d4e1a7afb4022173cdbcee0af650b0791817eb562c087df798ef280dc1c45071d817fb010001	\\xb48d4bb0d0d506d915a8505a4184f8dcef56c775ec795f7f7093a667c0a5cc06c9fdb31ecfe6a227cd63333482f9898777cf4e216025b4e6bd31ef053b5b7303	1688303827000000	1688908627000000	1751980627000000	1846588627000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
351	\\x3c735988690295c03b4a77c728be85d3f7a18388d0dd61473b1066f9fc4d90f61d2d1f07997ebacf819491d7af4db98e03c2432dcd6e94fcd7c49fb2f6fd0a6d	1	0	\\x000000010000000000800003baae5aa65b21919186e4930f0cd73d9518dedf89fb8edcc68cd62d6a3996fffc7d83c04e1745668eaad4c9cd1b874330afcdf3049c33c89f82e0bb43901cf0b12061d664acb1de9099ddff85c9cb8fc0f1e7867136d3a010bb7d134d5bb4d25d8aed8d4af2410e4e300a4aef06a753f018862ef04ccbbdd7c410fb10ccb6bed7010001	\\x5a016e13fdf748a62364e2b55895a2463bf53a84ffaee2fb8c0bc50565a7a17f0521ab84dc54c66f6e09bcf2c759e6caf1868545787559d062685d591c190604	1677422827000000	1678027627000000	1741099627000000	1835707627000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
352	\\x3cefff558ac23117a4938b5157b7c749126ed843292d4986520e5f51d510d7b3ce434abbaecbe18649a144121d57476b03289ac704b7f479be17d98cb9cd8cda	1	0	\\x000000010000000000800003c8f40e9171e1eec94f58099371e1eeecbcfdcdd686cd7b6e3e9baad4aa2708991dbc5cf3a6a8e2fc127bc8ea8cf47aff872871869ccf2cd9d67569135f48bd85732e017399a9895b61e4b71f90f79640d5ac0d2763356434ff888635c9564e6fe87b937259ed1cf51310adaf98038150a006e18a04725fdc7424b708c7414cd5010001	\\xbc52b5bda2fa9be93e142522e1a07f2d0f6a69cbd8818a82a6d1494003b31c686749d160a8ea79a078154d7db1f88be731142ca9dd816b8e2639c9ac9fcf4307	1663519327000000	1664124127000000	1727196127000000	1821804127000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
353	\\x3d9ff517cb1c0248b73cf40e4aac164f957360cec888c37f8f92b3db11d0d5bef060be8e8c4f883d9374e0ea8ee7b86a93f14c506f34864ffc88a86c2d2ca984	1	0	\\x000000010000000000800003d1436faddd05b3e2a87bcc5450a29f4a56fa80c95bf2bc2033ebda81382a846d6a7bbce555569ed1dfa124b211db6268081b038b55b78e63a6602ee2477217860ec73da6152b7307242232aa4f6b65c8fd17e000437fddc0ab619c37c14b576e6ee4387df7f8626e2cb927deac5054af4846059e33d9a783fd892a124368abbd010001	\\x009313a377678d880ac4381ec44d4537439b5ecc44e2182f0ac08d88cbda04a8fef705979bfc81e7b3eb3dfa3080f1a2d3453e9534d2bef62b7bbc5f43eb9e08	1661101327000000	1661706127000000	1724778127000000	1819386127000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
354	\\x3feb31f9478aa88d145ab79b563ce48cfb52d898d41cb090979f12b046597db2377e5847e8421bdbd0d3d4aca87cfd65ef1a2ad850492a8ddeaa12b599e1ba92	1	0	\\x000000010000000000800003d745038a406b0135d7f9c159cdc4d91bc40a1c2afff5caaaa4555d6f7aa06af78e8544041d2c13c253e9b5cb15bd1ee03cba728fd4c200f29875cb82c1656c308aeb961e61f15d418de5496dd213da25fb655d9d936595fcf81519338535a4eee52a527edcb64b729f3114b93f0b0d6cabc92b1bd33bc2780bee883ce39dc215010001	\\x80d5ab3df0cebfe396a504877f11ff8e96c29917b1cbc927731e9896a1380f84903431a304e45646d3b5fe59c9ff06db460158d164743b9c1736534d268e4707	1660496827000000	1661101627000000	1724173627000000	1818781627000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
355	\\x4287a0c1b91180ee632e7233be54f20ed101d1cfc6edb5ff26e374a8c5e22ebb1b6220be36051cdb83e82a589ab99304f89e9408ccbf7e656b7b2212d960765d	1	0	\\x000000010000000000800003cd99eb9689a200588c99860257545c52cca7466c5515dae67ee5e226fc1c130995b4adc61934f725184a8d4f4481db91c0ac90d1bab03470e7dd61191b900da579093a339271de1765667989e6e9849c80d80c166f7dba6057ae149031ae6cd8676dd165fce3e9778574891036e83c7b6bdd7f4681445b41b8d1e1b8fd1e0da5010001	\\x507cfd00d4ecb80bed30de42525dfbe586c5fb893fc87a7c467297ea4a602e26ee613419c88bb6e0cbcd850d1ae08ea752175afbec612b33fc5f7451af9e090e	1672586827000000	1673191627000000	1736263627000000	1830871627000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
356	\\x427b0a4b434c96daab55cded53ccbb6b7d6273b0eda866adfe44c9feabf5ef62da302e1a68f7bbcf8be378d0224c04db692677dac41e6ace7f85fe9a52f826ee	1	0	\\x000000010000000000800003a83ff8a5cf2e547167245c1697aecb5764adc84f19e818d4fbfee835e63860de27d543ed5b0e33112b0e196a55e95cf539539bd0f2c8748240e60498db33ae86d620d78a4509d5492e44496a9f74438f7e28d2adacf1ad50c58092360bd5866be97e148d4037b4f19c7e291e38ca157445bd6360c7ec83cf78848cc00e2edda5010001	\\x17d4133a6d5bce9439cf1694e1b098e0b4cd6b9f4f38572862a4c23839856aed0f0910d2c671a2b9c8c172f30755b95a03744274343325d5690a401898465f00	1686490327000000	1687095127000000	1750167127000000	1844775127000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
357	\\x4803f647ff9e8fa1c0f55834ffce63d7613ed71b42877df5416b119d8d09763dc46ef1bea6b6bba5c781b75b4502d68a13737228b9c88bd7ea66cade14fa2956	1	0	\\x000000010000000000800003cad7801ecfc83b5826250974921f9d81d95ae6415e387487b22419a02326e1c0a280400ba7e178137235cff6fe5fe3d2ff43598ceb061ef64fb1766fa626512213d9fed00bf4e4b0a83da95a92b32bc26ce71d2cde1447271a2f9edc7a5f21e5df9fdff1bb5ea60e808a966937b9762ec22f313ead1737a4ad96147c6990b865010001	\\xfc2048210084ca5a890691fc5d08e0f25a489264a4afce6bdc381c22775c80edb79692bfb751c778baa13f2fead2e30a53e3a091b2b17aef22366c1ec84b4d07	1679236327000000	1679841127000000	1742913127000000	1837521127000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
358	\\x4fefeae7bfbe9a78af210fb95c6cd037b1bdcf936a6242282f5ee843cce96cc7a3a86206ac63a5aa95c9d486a7386b07601bc33b4fd67e8fe2d11d9fa0498f5b	1	0	\\x000000010000000000800003aa40c2edb93d69c0db440b1759f7062c179bac5afb41815afe79fceaf19cea3aba21647ce047069b62a7f6d7b18867460ba01dc7c5f8b441f2bddffae90cccb35f1e3ba560b33c88e4f0890a2cdb8dac96b48f31566c3aff6b851122a0c84a61fd0ab4c3a6af053468d6412a795a35f59b2269270c3380aa527883934d74d0ed010001	\\x63267c3ed387bf0bf1dd5fc7136071c177918630ceca8eea8757869844d9d659d8f89450ec7136a7c0bbea92f0ad10217c30804f89177fa51b6df1aa67607e0d	1667750827000000	1668355627000000	1731427627000000	1826035627000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
359	\\x51473954b1ff782354bcfb17cfa6ad194085722e5cc8996eade489962d743783981f59e7a36cb1eaf803ce777e0fffb9279c991ec5ac9ed299a922699c7e8dc9	1	0	\\x000000010000000000800003d1eedf964a4c942aa6fc751bcbd45295e77f7273dacf9addd28572953cef1c9de88ba0b577037be362ba5fcbaaecb62883a0012ead2172b89663fd35c87bfb934119dc76fc12e3d9824d8e4559231731aef931d03ddac7870f5f3256f1500170767dc901975da5a4864e48545a24618e5b9307592234e26e78eab1bde365415f010001	\\x9240a16da7b2007f46422e47be9cb88fd09319d1e3d1496187ba7e4ae634c4986123de2ad1e53dd13107f186fa5da0c1c87d4791f08a4eb9f2ffcefe45471f04	1667146327000000	1667751127000000	1730823127000000	1825431127000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
360	\\x53cf05b4f6d954bb9f11f9cab0a6a4a93c30e8aee23e52d629ca230ee742ad776d0fda0f1887bd2d646cc96b7f542b77a14f2dc9d5adceb1cee9326de77ef00d	1	0	\\x000000010000000000800003ba4d71dc3a92b5b6c47babd26703c79af074edf31a725944c082e902c7dab5430b9c0456fb06254e21cb26bb8bd5d32773fe8c5a9e94566ce0e745d8ac9b1c963b26bb61b7e48978aa5db42ad1dd440c70221e990c9e8a712b6d8eb35a6d0bcb4a084024027af42db925ec0012ebbc4744c340c0b5a013627561df49b1870fff010001	\\x2b13006fc898d8fd77ae6d1a78a2499bcbff3fc8bee6096b359645985bd2c8e62051705f18d0d5979ce36410ff42b9d8a8478a94f47ff24f0dd9f0118e7e4400	1661101327000000	1661706127000000	1724778127000000	1819386127000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
361	\\x544fb2320bad963b2762802ea83c3618f78e77db5d3da98cad8ff3f1825c3c1ec5f115544f4e614a9c96dbaff35ad9969d871318c6a5c5bf06cc229a758bcdde	1	0	\\x000000010000000000800003aba243840702f5054fa9883d02088151c59ed35a2cd4125fc05ce50dc8abf4910ca64bbe9ec8b1b0d746c359eb2e92676958584611ee5e1bcc1c268d5f72fe2c86e9a03187ccaabd4e9f6d8143f840b00a05bf91420ebf631e5b0a54af88ace1eee524dd62dbc2a3e26f07d357bfed420863a5829f99b5adc7983b38951d5b83010001	\\x25ee4703711fd10a33461bedc8af21ed262fe3f558b67f2b612bd8630787515d052599c86c739c387443c91badd8ef6a57fc0280afffbf4be2ca625464a7c404	1684676827000000	1685281627000000	1748353627000000	1842961627000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
362	\\x5d53ece393f766f6befc3b6a1cb7f2b5ca4047e0aae98102c01e9c21b1d942ef5c9123edda7011869f20c7703f625a52865e28be431c1299ca36889878b2d652	1	0	\\x000000010000000000800003ec0374e75f20755dba9cfd520234ccc7bdf6f263c9395ec931b260cf4cad5f5b4407464db99518224245b1d216774ab8d700ac91ccc297d16e3650de3f4def1bbcda3c5dc94468fcb90a2d9bb193c38d3754bb4ebef237003cf892ccced88eea6eec22938f58ae867f30399eb9bfbe0466f35818ca2a23f90ca8d55c3ebdaa2f010001	\\x63112ead1655d43eca16ead719ee05518be82ebcb572d4d1b5ae38dc1c4695338ab67d4a1851aff010bd2c17662227622dff76fee346b4173e7c4ed6a9245406	1681049827000000	1681654627000000	1744726627000000	1839334627000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
363	\\x5d7fae252534fd21a3ff8f9e945913d6465a6a36aa93de63c20e1758452f394fcd9ad3a7314773e29e88025f67531f7dfd136d70f14cc2c130ec09c3cedee304	1	0	\\x000000010000000000800003e923600b553f190aa84917164b20a4973aa01baf3b295136cbb5142bed3881c8dfcb4e549fdfc517d9c73d7a73daa7a7768752ed7623c5a0283f5bea981af38595866bffd9285b49655b1137c7d6cbefa85122f61cf3463d6aaf463be999d70eea17574a3809192cd6dc96eb04e1e3fe0262dae8d7896321c8c9062b8974ffd9010001	\\x72f63b21eb1a9a80f3687ea1fec5eb8a2f3897643cc599890dc67f536e79a34358cb0ab1e412c0b9ee57b56cdf8d1b6a835c2014e534a9b7399b7922003cd404	1685885827000000	1686490627000000	1749562627000000	1844170627000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
364	\\x61fb06449ce152015052222bb5fbdfb37411f9077736674ae07716d8e4b37881ab8d6520fd100f70378eb8bdbffdf00225f9378f82d616ae687e6883075fce7a	1	0	\\x000000010000000000800003b1768a5e84b846a493ed247016f43220a979eac6ef2d2d23b329a0e60964479514c64357ea5ae001368bb266a2022a3450c48cd371d9bedea39d8d202559c5df3295fc58494d61442bef2d887f131f641c0d881b341076e8506ec7c1e1cf3e836c45299b070e201614c8ae11e9db46241de125f79734e706bbf8d32481a6c38d010001	\\x91a9da3ff8aacdd8962cd4720c84740b27a7b64b20a40e4f4e65c8c28535ad3c0cc37a63b4826efd4971a59a96f16f22cf93040a8c653af55779d39f31729600	1662310327000000	1662915127000000	1725987127000000	1820595127000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
365	\\x6363c4a6e6d6415cfafb1564810ccbcdb6ce3ea8d4f932b3dce9d00cad0d98638c6b796b923d6bf265382e4a3c943bb4e95bef5788a92ba41ee5b8a05e19f436	1	0	\\x000000010000000000800003a27703a3cd30855d2714593f8728f22169604a06f55da04513c3887f4ad87850c9ab715ce0b10edd9fc3f41ef107755dc1d43dbbdda28bb1db1abce7fe1431c7b54b6bdf91e7df467fae519c4ca96d3a1fea9569cd66c79dfaeb7df8d5b526f724bc2e58013fa8e0dc993b169ae192ea41b54f317eeca013133d4b5f92f96ec7010001	\\x72fcf62c8b63121ee2cb37ce61f321050d2e61bbe0352fe2df37dc5b7c805c334edc6b1eaa95662a835aa5e489110533c36c7a49442df33c97d158467629760e	1676213827000000	1676818627000000	1739890627000000	1834498627000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
366	\\x667777074f99d5aa120d965eb09c34a835b59e3a67bf62c7477d8d3922d82f4c2a4af4c51d995d13f54e910ce92b32f40276d2248d5f76d65081fcb8b990d189	1	0	\\x000000010000000000800003bc67910c10814be95b25c25413ba618f9cf16264ddeeae20147ac716344e121d0262fbd732c7c8263c7b06fa7fc8e0b05b9030b66b004c0db797b63da084d111d779c9c0dd721ca0b6f6e8b909a4f5718cf99199eb74abcadd25dc35b00019a159062d7148575ddc50a342da40340bb4125446d777cc912385747fb666e128b9010001	\\xc341fb216a57b3a78b370cab1a5ac560a8938014f334597bd2ef895029fade7953b1bad8f21acd0bbdb234cd40b25b3ab3e261895cda03e65be229d357169108	1690117327000000	1690722127000000	1753794127000000	1848402127000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
367	\\x6cdf63139487d7dffda22a63659c3058522873ae91ec48b31a82cf64c3f4070836c52c6a7aebc7936fa18d325fbcfacae1dbab0a871b48d9fcb3229ed6280127	1	0	\\x000000010000000000800003c725c3742d12db4a018632999fb543cb222cb00d0c1b676698b1f93125d9d63c49640add9dc762669c9baae0edb60746f76270edb1267be907f6ca05b630f9ddc1194a323322ec9956bd9d8d5dba264689053d721da7be68466f7f90b2faa999e99ed9c2237ee76a115a1e75b610c352cfdce20a87c3b5bcd424533e0e42186b010001	\\x45a8b6caa3efff6646c6c385db699a4e0a37b05200d692306fad52628d66b988f150506ce4658cd9b5842068ab3afe42521fbec995f629bf7412cd8f6e388802	1691326327000000	1691931127000000	1755003127000000	1849611127000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
368	\\x6f57643134caf6046d9346e4d4fc28ea29459d783a986ea7e62b6f4ef88312f83b9adc362d087660356a2695a8f799385083da06e56d6e592363d679fa7b1ddd	1	0	\\x000000010000000000800003c0dd87681092d64d52393e759f24b3aff1ca3a0ae670b36b6d3b1b71bad152a7f37c5f749ba9b7d0bafdf6d75af0a5e2fadf5cd66f5c4e6210329380a22b8283e0c50188360cd425a9711ee8825837418ddc14f837dbe2554f281d8b2c9821e84a5e80399a061168dbdd90a16cd184c3e76b0858ad76e2f5c627fe92030bbf1b010001	\\xd73135c6cd734b08c25bf6a11bb71141064147041596fba64fbd163168d6d276149470a7aee291bdaf620b57fe2a5b257f8fe30d174eb7890e941ca50701d205	1676213827000000	1676818627000000	1739890627000000	1834498627000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
369	\\x6f2b1c26e4103bc3dd0b47380493c8738f82055d9fd7f215799d104d5011b6f473c9ff45e6b8a1c43aeb5abc6ab43cef4970dc317be90a7b286d6b597704f687	1	0	\\x000000010000000000800003c5c17f55ead4eb2ba881a1d8dfbf8fae874a4d1375cd95d658c4e30ec2afce4bf674e51790e67df81bc22163f31c1d7a172e9ad41733b92e6a474bd293951c308b0896a70c4dc7309102b3d4928f7c9a26b1f8b156344397fb1e4f3234a7dd86141044e5faf4f3cf2e3181008d1cfdc5dc39bb229c8b252408a0968201935771010001	\\x8b06806115b35cba3153403ffea8b7ee02b45e746d6e1a8d3f1a751ddd64d9c33951df950179983ba67eaa2eb322d618ab56f0de5cfa9db48966aee243468703	1684072327000000	1684677127000000	1747749127000000	1842357127000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
370	\\x7067a554a757af121051f1438efbc3c663d8649cb81945ecb6335c3d0663a5ed881f6d889c6f05e42bee8b6f02df99fd6f87a631c66fc157693a42aa37bccf25	1	0	\\x000000010000000000800003c6c175996f052cd137fa3b1ee8eb882ec9c163ac96515e71b8416e901bcd96f9d4951c7c3e3c745f2a8952f2add939bf1a29c5511774db956c9dba34e816baeef4101dc860737a7cf05a0cb65df671143aa954033448b58e8d01ea1970663ca2d1485c7d907d190580ca00db268674d5724968117a80e40e057177ced5491ebf010001	\\x3e5adca973be9e433bbbf9d2218f0ef15ffcbb912939fdf153ba420dc5b873fd9651c5c6cf2f1d85bbdbb74672d1efd157f1a82eebceb788635f725347bc7601	1668959827000000	1669564627000000	1732636627000000	1827244627000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
371	\\x774faf2d11324e45ffec659f69bf04ad65208f41523f6d9e48e2cd1ff6edb5a2edeee7a53628188dbaf81cee1f831cb1a9af7824b0466f3d7f4a78ef33c39e01	1	0	\\x000000010000000000800003ce73a96ba3f41a379af792e72a1137662a46f13981976911728ae342be2fa3536bad07f52644bb09cec2fc37fdf90f554c7a7de338891cbff405a3fb4d4d540fd5036b8cc4202d782e6aaba194f73faacee541db1489200e9e4b1f098a936e7bf81f2ddd1e838a42f1549eaa461260b9e6b77d81a45662fede2aa7db27859227010001	\\x156076b078264f51736d1a7e41f97f0667ad54a382b0a8848662c0ddd4873adebd5572b93f3b73a27a6814f61ec04dab874d5ce50bf054f24d332ca2779b880d	1690117327000000	1690722127000000	1753794127000000	1848402127000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
372	\\x786f43eed612332ed408550667dd22395995ef233eb20f9a3c1c2778ae587bb6057ab64a29e6618883a77e3ee3a20bd1a270176e5d8062599cb639a575e75618	1	0	\\x000000010000000000800003d0368a18246bbd19cb36db30249010793d64f0d9e17ddf1495a001c096a53c4b1faefb201bb6be37cfddd8f143a2c0c813ecc6bf6ec71aa5244cb5c1b982b9917c330ff92cecea514a5efc6a7745c2c7c26fc478a7a45e8bd13237a9d3b6113fb91e0ebb9e6337e9af9bfc128b59a1d4d47b39c463895dda96a54c503081efa9010001	\\x10713ae0807e6b9d3e863d07fb6b1520417bd62979e8cc98c991e7071c5c5a148a8fc2025191d9dcc94fa4b6835618a5b942221f187b6b8fe4658d8b631de108	1670773327000000	1671378127000000	1734450127000000	1829058127000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
373	\\x79ebe808f29052974d7827b2b74ac2b5cf4416a194ace624a9101feb67fe63c3b6e6e73f5282faef5456f860e272115a7c6ffb56e71d6e9e6e10d18797de5892	1	0	\\x000000010000000000800003d028252eb6dfe16c26770d2e80274bba19692c21ceeeca08b6d003ccdd8b772389346ed076728856673bb25953f32f0337435e5e82fa9d20597b1460dab45c2b73039caa9c64805fb07a0f4b2635f280f66348ec67617cd2e646e5e150a11b55683e4b4d880696c4a5b02136f0578c06185b4f4b64d56e940a86d871a4710339010001	\\x2ec1b3cbeaf502e8bc038ec15be3f378b272b1fa44df45d3fd0f33edcf5783155b8c039ddb71e3b256ab5a46691d230e57d02d4e143863692e8e6b5ce29a0a05	1660496827000000	1661101627000000	1724173627000000	1818781627000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
374	\\x7dc7a69b5944cdd3e3e71bc5c52c26fc841530211a4a585b0d87944dc3a3492740c815e8155444dd3944a6efc655194b941d411f601c506c992d73219ca7570d	1	0	\\x000000010000000000800003cd4731b227d84502fe0bf07ba238376df9f962264e6152e0be06220013b3ac5ac04e51756e06adb08f507d153cd710e7b3044f0c0dc74f7318513cde9eb23e905b2cbb7bea18b8c8f5c845306d36074a71ef6f627930851b0554e11c01c71b1fb2d73ffcc9d040529cbf78cb31fe16ba21c459901df8ab7716fc4b07f29ee955010001	\\x6b45b3d46955f3729b5abb4b665ed0162d4e8b120c614b45a11237cd4dc6bcd7bea5a531779ad821c08831fd16d310c498f63b972f13153ab8c041c4d1ccc90a	1665937327000000	1666542127000000	1729614127000000	1824222127000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
375	\\x7ddf931fd494cc64037f8d60d68d573a05192dd8325fd33dcbc53c7fe59155027a9093f1cba13743bc017fa860b49b56d3a804eb5d034e58d16d5f88ca167b21	1	0	\\x000000010000000000800003b3fc4918da527c2c939d9f4d4ace4c2f7d2ec33ebf50191f530e176f7c9865e36e8f89da4d75521d82322e630f779ffc5f8e208fdd17e1b7909beb275aa74be214ab783a45d5dc161e0e305e0e74456ba3535221ec5270bafe1feac1fb706a9f189e9461c4f6fafde8732b96b34087d7ef992c149612eaabe24fa9bbbdf64a2b010001	\\x3a1e129bf4c21ceb5ae23ca8fec7237ec42b0900d5ea1e73c2b2e2d033329ff693d6be19332d9177291ecb9fcdc9f3cf013f443d1b671c89ab3d899f85d89401	1688908327000000	1689513127000000	1752585127000000	1847193127000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
376	\\x80e3c942ed21e599bb2d7b6d0a8969aa6fd2c160bd68e7693ad0ea81cbbab27ae6109f0ce1aeca2ad5d0eedde1a209ed66c63f618c387ee7c48226c2a43f2662	1	0	\\x000000010000000000800003cefc3eb17629c856c14b832b5ba5eb18ff2236409349bc2b9722b5d684125fcb31d650fe947e189d398663d2f886e14bb471b6dccb62a15749600fcb560b8f43b335b7ab261f350ba0107a049b0fdf4bb2ee97b010b5cb1de48f3481410b0a259c020318b978335bf75280518c90a3e8f6b6ff7d7fe78196963bb47498e98079010001	\\x2c00ea6a15ed0dc5c44fa5c5d00b84a6646d557850a0a038a38bf380d9f0aceb6b3e7094ec515d8b70224442f79a20897d9a21bd3427e15820c87f118ce3a30c	1672586827000000	1673191627000000	1736263627000000	1830871627000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
377	\\x8877d60fea2880b70bc0d60db5c88a316fd933c04a46e67aa3fe0c6623b2f9e312a13ea007c2810ff285197b7b0e31cf35cd35099e9f797c530f9f649dfe7522	1	0	\\x000000010000000000800003ae312a9cbc20b105c6ed4d63b94503784dc39b5954232fe09dd56e519a79b739846d68f220d5eff6987e48ad6f1f81beb6ca852df39609cecb7265c83d7b099c5e44296b90abb2a4807a16b017d4a04c92ab02a7b51b11dea97aada0f5b89267dd68cea5ee40e4489d4bfb429492ef07048923d1c295d35e809c025f1519a75d010001	\\xf79ad48b5b3aa4fc9ae8b00db676aa23f6f2c5162192b87cf3db8df08f084c567f7251bf117d0c811aabd95a92911bb6e5124b0060821c88589028600ec3060d	1662310327000000	1662915127000000	1725987127000000	1820595127000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
378	\\x8de78ce49004f62c57a5e8bc14337aa086e145c6e5303e0075d85f9db8ad569cf6f6212dd4178ba3cc7d4a5794e98e963e9011bf5e78d419b482a6d04e0199a8	1	0	\\x000000010000000000800003a8d1c12ac829d1c00664b7798d72344a012be86e8f768b60c54cc8889ac8335fab8bd96ea99858544ea5de5db436111085db66c3dbf49cb45de1542fe5b3dd6087509bdfd2aebb8dc83e697805b8ea416ab44d4d572675d9ba91796093e03718fed283c1340abbe5c361cbd4971554d2659f53a82d2061fd8aa0477dd591b2cf010001	\\x7597e7c11e01dbce43a9d4a74478507e819798229728ba162708381b226c39e36aa05a204f4b8b2f0d5d7c5b97f4ff66521e28847fa696c1bfd37f8a48dcbb01	1682863327000000	1683468127000000	1746540127000000	1841148127000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
379	\\x907fe376547779c522cbf6095ce665a18112df7bc95be8f50b24b69350f75bde9d27199ef2258daad013f0dae5644c0926bf64ab36c108c996ad100f40b6e8ae	1	0	\\x000000010000000000800003a23a326cb04f056bd0bdaae48be9a1b3db348004bf3e8063e715c9badd29c7a88e4dec186e8bd69326991a4881e8363511e5df52e348ae37072bbc234a39744dea42a9517873767e0ba56bb4e87d093ae49753ee4f71a2dd6cf37bb46b3028f9d2ccce1c9dfb9656dc4baca0c036de297e857ebe5ecee7da4f4ac8bd7816800f010001	\\xa51a1e6fa3ad864ca1c4dd0d4556364e4587ee4dac19bfef8d3049f780cfd75f2f66efe3509c870f2c8ef6080d34f346ea76d91582a159f7d97d189fc19a960e	1678631827000000	1679236627000000	1742308627000000	1836916627000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
380	\\x95af3207841419fb9feff6ceaf4bff73fe52056bd725334c8add97a46adefc7479f9c8d3a891c1e7f1473c76e4de2ed01f1420fe752c17f6c81279b49bf1139c	1	0	\\x0000000100000000008000039e92970ab5b2168e4d3956b692953bf8ccd4bb3ae9f6d3d12121edab1faba788d08c55c6ec05f874d65ec370e78c9e538dbe4e22c492b84e23c37418880133592eb5fc8746f26608cd31bb77437319b5dc522b3d6e19984f10645599f2a8961e092e5a5260ca8822c70a504e8274fb6eead7c39c934e3e187fa9e6c117eed5a7010001	\\x215ea29f201e8869db218c1c810e735770e1ef92477af36b9b6cfc8fe1fcb0c1428f5466555ca10141b7f404054a4d002904f83a93d7bea6e9eb4ed20995c402	1688303827000000	1688908627000000	1751980627000000	1846588627000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
381	\\x978731d357b69809756f70507a4264f77db5aef131f1889f3125f9aba9b0ffb1f26c3f614650fa1226c5cb733aaa9427b6ce9052f0987a7cbd908ea1f8a2087a	1	0	\\x000000010000000000800003dcf144e6a14d8a172e3e5032cf6ce58e7c7a988bffb294fa82b9a047d9fffb41ce9bebe5579ee2d875dd14a27d75ac8d297834ac11b16a0c2d46ab48d0de074f6ce5b39d2c189dedd629b79e5641bca2eaa4b854a7cd5b59c0dbcc212499a3713cbc7f237efc0f186eb16ce669ad4eb61b06ec071db74c13991248f1e9cf96e1010001	\\xcc90c677f6766025b4ae8f8c226535edf1873fa3477920277a4c54824a7a7337e406305d4ad870e1d6b516c5cad759203bd519a8fa27a1e230799ed850227c02	1669564327000000	1670169127000000	1733241127000000	1827849127000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
382	\\x9d134a458f6a981cb958a78efa314340eccc40bd58348a0eb720794c2a41ace681248afd90a6b48a07c1e1faf4bfc4346e83ee076e61135f842f39c8d0447f62	1	0	\\x000000010000000000800003a54ec5b17e5f77b6632e4682d12ab0c382175403a7373ed0aa0598b924f5b08dab7a9c4c1809d786cfeebce84942dd2fe9f6ae0d1564c88342af60a3701a8e715a5f4805b0e6fb2d2d18bcd7691a68b00b0c5d58a7eb7ebe72b54795323d3bbbf8102dc24bc809c5ad737b3d5e38f0fef058a1f17d79500fbbadd9aea6199e83010001	\\x8a5d8e3c7e3eeff473f9779732ac0bcde55ea652922805cc8c8cd65279d0a2b93fb02584d9128aac5b04faaeb15db5fc07cbdcdf667481c83066602ba5f5c007	1682863327000000	1683468127000000	1746540127000000	1841148127000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
383	\\xa407aae4dad8e337c83d75a981a97118f3b567dbde44bb1f48a65d573702dcc763a7d006e9171b6c3f79a63fe62892ea3f86c279ed4ec370436dfafadb4be022	1	0	\\x000000010000000000800003c1aa70e9fb8ee3a4134754620b361c4a8a90587c860cea2755c2e32224b709953453b07c32385349ee63be19609979804df307542042801483aaba33957a69c98d5defbdd044015622396ea2910b9e4187d4f9709db93be39ca194c226808fd8f1aee2bd190d9094d8220733c394ec36a4d43a54b36983024b04a77ae4e46df5010001	\\x343edd5236ce5bc44d17023e6f31dd13d2cb9ccbb818800c33ee2badb3e1e60464a0e490f05992fb7b3be8aff5640424d2764fd81febcc761ca944889ff76308	1681049827000000	1681654627000000	1744726627000000	1839334627000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
384	\\xa73f3b15d8a7377797d60e25e4785044812a606fefec6d9fea4b6284dff756a23bda40e90b67d8bf018940f6ae996315dff869796a6546243d9ab5b7b023dc85	1	0	\\x000000010000000000800003d748a9b1a3f9b28c78b3d5d77565aafbf48c25df573913accb2d9c12bc3c2e9029ce7c26f2f91fde1bbbd4a3818aaf78936b778f01feba880e3968d892e9bb1d5e424780766636f0e7bd726f8ca6e2a37e7cfad21f1a3da32b360631958f7da685214095f165b68f731b4d0f61a12653cb6313e02fe5c1ee58e9c4d7159f5383010001	\\xf9b5d64042b46ad2118cfac2ecf92ad30852d171a5fd5964fe4704fb4d1560c2e65c23cc373401f8dcc1be6afb9c686d527abe633cea4498e4e7ec7b7d277502	1675004827000000	1675609627000000	1738681627000000	1833289627000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
385	\\xaa8737ae33778ab9bedf73ae6c6d118f3962b5942999e41c4ba8538cb8d95877c121ee4e736839c93dd7c86e8f0e1f442972019dde0ef949c403170eb162443e	1	0	\\x000000010000000000800003c6098b645f6248a8cb696c2fd3aa410aded76bedb8be7a21b1e0995eef25de227691dfa221a7a2cdcf66dc53b8da4de73c46cf1591960e748365626fc6e0f97090e2f191c820cc417dbcb83cc427765d567b025abe9a7f3e0f9f67f2b75713d387ec827c5b738b518f96de270de11025d0590a4c9a980e718e27eb37664bfad3010001	\\xc0f692f37b50d2acc00d45dc38fdc177c8d7ac53245fa2f57ca9875d6911b68bb26d19511d3859eab505a037a4134d9c9a0f87da67f3377603e7f1049a09910f	1671982327000000	1672587127000000	1735659127000000	1830267127000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
386	\\xac2b929b5c2f0ea98a1bb9cd0f00bd25ed0105a6e86cc45fa5aa8561ee6808df6cda5b7ff47a52131c7196b382f5d0d4cdd68f974c7c655c9cd9f8c732d01eac	1	0	\\x000000010000000000800003f77b3fa8d612dccf3c9b0ef45f3d8d487e9bbc2f21db238587d07fadeaa93638190b30ce5b88a8f0403fba8573064bba3cdb742716aee9ad6113c8a0d32feb9a2828081742dc4e8a33deb71d2ccaf36aa75a973f4d3f54a67173010ea03040694a1c7a429170369dec4b3b2b4ad64ce0ceea19bacb21cb22d93024a486fe9607010001	\\x9f4e423e84e08d6a5dd2263e78ffadb154431d8a9e05dd13bd20e281e338a0cc57bf934a3e581a213348961cf5d8a1a40df5f80ae26542a22783c39005737b09	1661101327000000	1661706127000000	1724778127000000	1819386127000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
387	\\xadcfd8ac52fca511aa441e82f151c99a5a91a9e4fd2f9837e9cb6310fb45593d6c28aa3fbb92b736ee984cee9fa55b821c33f1a27b1dbeee6ddc5b3b396954f2	1	0	\\x000000010000000000800003b2d9f0ccba948a3b7e31a19793570389779a79369e3d54afa4aa0c90843266aa334331f36669d47a858f5c9422b4039e5aa51080521f989a81c186388456b9b325918d2c58e1814765e90ee7ce7ebf75be28386ca14074afddb2d1775b48cd78c7ab66285177c6edcb82409bef90cb1965bc7abb86ab04d777cccac59fce13a1010001	\\x54b2bfc17a3d518d51b9ceeb0d6dca61649d516fe896927b5108d4d9290285b4a65923b0c876814f3dd1c5d42ebec4dd46118ee6c676a9a34eb273be253f820e	1676818327000000	1677423127000000	1740495127000000	1835103127000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
388	\\xae7b0ee8a23f2cf15c2b86a3534e649149bfc95d45c52ac7e9f238e45b365797ea89d61abec42f7195911cf278eaeb9aa01a081cec8007e15f262d3896e4a19e	1	0	\\x000000010000000000800003bf37f350b391a03cbbb4d5c64dfdaa7a7547f2be3429dca0eaf1bd41764ac7f0f62c07fd78e4a3369df8aa820951d720c7b0de9c030e717715fc03836751e8116ac98462d7f31a79f8a98eff4060020d635c3338392f02d97c30f0e4efe6066898fea3cb4a5b1703709d82541d05ad9014b9c242e360ffe42e0065826ff02749010001	\\x62a768c80b49e0bd3ff344a85db9ee484e793abba08061f058f85923a2321e918f5839d0463596c52cf00144aed65d8850d6fd52f6137dee162421addfafc901	1681049827000000	1681654627000000	1744726627000000	1839334627000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
389	\\xb0c31eaf3574b42c34bc0dc69534e44bca8ad82d46dfe2fd89e567da97bc27bd6685f77d779d29939b030e708ab0a240ee6fc18a8bbfed9e177e7dd2055078e8	1	0	\\x000000010000000000800003d1b98379dbaf3d5d62fbf49fd4368e4e958a136e8a9c861e68d87ff39340b1d2cc940525c9e8d7ee73b8f24ef3dc9c105cc175182fc6c3a7046907424a16fb0a2fc6b51ce70f8d714521031cc255f8d6030b6f812d71cbeae31566b5203c623e64f4b00d81f096c92decaa01118f945be4cc89b4915239d41ffc62305729731b010001	\\x9912255a0326624874ae888497e4f4d16c544081c91946aa8198367699b0423b109ec5ca2722c58b9a1335f282c78e530b28a015c9cec29c5944a4c0cc607409	1671377827000000	1671982627000000	1735054627000000	1829662627000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
390	\\xb61fbe665ca33a206ea01411ad433318705ad0e144a6ee46021dcd7d32f264e90850fc2024df0248980813c80d9411d3a7de98c530bcc7dccb320414f120c916	1	0	\\x000000010000000000800003cecdf723a111690fbf554edf1f0c19fb13e1250058376bacdb326d12b5330de2812103d1593b0beeb608950870fcfccb05c7dbf71cfc12a7082c286604566a6cdc9f6530d3ea1762ca00e03a09e51f81704478ece3be37f0d07a16482729cd52ee4ffe49b6a18559e6b20bc72ec62b89ffc57a2f7dd2850fc3a2b2b1c44cc1a3010001	\\x4d461b9cc2e2338a5f22e132af658938ef108b081abc050a560a5f64d263723fa5505f886f8f97f4c8d151b85904fec6f1aabf1d96045175b884928b3fb8a901	1664123827000000	1664728627000000	1727800627000000	1822408627000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
391	\\xb673806b57c292e353b537c3275bfb2f78239f9adc90139def9b012c2a0bdfce9efe23c03a7b0cb375c71b381f95c8a9398cc9bfbae4c853397b9d8108944c7a	1	0	\\x000000010000000000800003b4d8b9027cf022e23319229cc32fb65ca3c2e2c07a0f6477455bcab30a562bd11ee28fc20db18289a6fd8e4148e1392cc6814ca815864624f0185c03d6b73827f9f321bfe2c7e8e95bb1b37a97f86fa435addbb0f138bce45c57674886b2310cc9e1bc5ac23850063dd4f25977db18bb5d4ee575d834c32268d4fa1c91923321010001	\\xfb1fbe2fb0861f036799ed6cc5d7580ae9093474c9f1ca114bd6ea437d214797163383264660c8e7a06a333e28fadcdc590eb8b55e947e5b0bbdfbac1ac54408	1685885827000000	1686490627000000	1749562627000000	1844170627000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
392	\\xb8a3ce750facfba91a29fc7666c75573b0cc9a55447c204a06dc41815b2e5950e0e6ff140c2d9cc901fdddaee88e5341eae8a09bd65006f6a4a925dd33faf3a9	1	0	\\x000000010000000000800003d304b2677b2955a67f2bece2ef23afdb2f3fd5ad43ff7b75913d6d65731c495392078ac307b44e97746cc19f8f4943ae84a478826955755ca18496c089a97daec67ed01a6aacfefee13b7d3aca89e6b5794120c59e75e0db8d62f1046433640daed8d0bdb3b271c54f078f98bd48bc29e6c4f46ed8ef8d7de12bae3ffc765b73010001	\\x939eb65d9dcd8ac1c50bc285330d86409671c0c1ee14bacb5777c44a195b5e3aea497861934aaef6298901d2e70766f5c6d9f440d5228f7bda98e2e693598c0d	1668959827000000	1669564627000000	1732636627000000	1827244627000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
393	\\xb81369870cac3410e7e5435f53a3ad65d74b49c47b79f56e7a262b5c543e83f05e54a213ca7e47939d8c2ee2fde5b87c9512ce0104d8f7780d00402c97876799	1	0	\\x000000010000000000800003df9d697f3608c2892d937a4018b7654c014a716064e60dde225d83e118f7ef8bf2961e3fd1d528b1ed7308dbafae0731b0e87c5bccd703f0e7e281c827991b597c1818983a09ac388adc7ceb54c225a00e68e77d0af7038bb322b907e74756279f08f2f8ce0d3453929fbd687b6d57b29026ce4f3255a28f5ef9a21e42a861b5010001	\\x7ec663d998bba45d703eecc5ef861d1f2b31e838912b6072b57828b9494f39cc51f83f277cdfd419276a1791c70930be4490629e5dc7962acac6fa760dcc7b0b	1684072327000000	1684677127000000	1747749127000000	1842357127000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
394	\\xba033eb383f38ce0f5b81983d4a8ba943d0929852b8e5aa98a7c8fc07f99aa12064160a48c594eb1848462d53594cd86d232d34d3d20c12085c1fcf4acb3501c	1	0	\\x000000010000000000800003af8e439a5065b7875fbcb2c678ae6577eebecc2fe33a67d334647d513cf9e8f6aa408ef5fd65a5f2d8a60f4a5d2b722c28652fd58c5dd8e8d77023fca4d5d7da3c78788b481e8683e86c808aaf543365cacbc77f58f1f27ead8a387cabd3b2b875b70ed2a23d65d567b0de4e08f4b1fa6013df95092261024a48ce150166bf29010001	\\x3711546f2ec947bb873dedb572206c03f7360c26bcd2f0541f8f1766ec81978cf2fbda899fe0c3e1c04bae11625c1275263bf63c63137bbe372c1d545f183502	1682863327000000	1683468127000000	1746540127000000	1841148127000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
395	\\xc287568dcf03366b2fc365d8e616952cc723790954f4be91973e9e7e692b872b989d0eaad471258f6f96908848bef35e8df92e11a20ee8526ede5c7cece7c6b2	1	0	\\x000000010000000000800003ee28c282f76f86ca071853ad071695938e36d07fdabef9ff714675e498242b04a37c50d641c331243346dd5c85de7f069455c57f8163d8bbeff6dabfd46531a36a6655dc8cb8539ef515b1ff5ada91311b7f42144d0973f6772003024b1b10afd5fc4c9598ed2ea695800e204d30766ac7d69680b421ecd068c3c792756b6ed1010001	\\x99575a447fc6d27688c414c8d4b5cdf2374d394c170bd6e964a802b57357f99c9e7f5aa2ad016a81f2bddda1c4a29922a0b5eb731d8110073e983fb7a5ebbc06	1665937327000000	1666542127000000	1729614127000000	1824222127000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
396	\\xc2df6c0cdec5eccb29d108c0396aece81e96b64cd0ec9e70296141a892e1716a64a11000f7c53c046bffdaf0b778caf14bf68c7e7ec70f1ce33f48a2ab3c4b0e	1	0	\\x000000010000000000800003cde99f7e4e5ae5f9f37b39a53a22923ff86867826fcb308f8d570576abcc193bf1ceb140bc0fdc1b8872922d7fc03aaaf4f6fb9d5123995e19aeab138b3de25748ac6962acfe5098a5e3aefd628bfa67e27a6fad3a9d7fb398ae48429d11f8fb6b2d4644282057852d5591e7dc907e5725caf010ba8582656106b803a0e39583010001	\\xb47ad16b90bbfe9e65aa7a21668da926e58a9839879bd1ac2ce09c22b0ff4ef1ce0b9e48f5f86c82bbd0f7c3fd90208641b23e0bef9065e946d5090ba6caaf07	1678631827000000	1679236627000000	1742308627000000	1836916627000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
397	\\xc533c27602c04ac16266769a232c037b91816be96f37f08981d6f9fc73989ec150a1a8ceb06b07c71a48c736de3af11d5f49ce57b1f7b07a5028af543d457ec2	1	0	\\x000000010000000000800003bfa22e1de05bd9118a1fd411f2ae2cafd1509711d5848742dee280e16b461b7251dd6722ac989bbd7442524cbfd3452f0498404264e895a5c0c160e274b83e0658d44dbb6ee4d8ed7f66dd33893aa4b008a15b3ce638cf7a5771b2541d73ac09413a11f861f80859b803247ac4d58457656e78975ece0804928e6054eed94421010001	\\xb76781dbe11fa5c6b69008e7f1c4191649b84d1d893aa8d7f1cabdc1b47a73ddf3979df21d593d901d16deeab95dc3fb631dc175c0b09bc11edb0747c8006a0d	1675609327000000	1676214127000000	1739286127000000	1833894127000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
398	\\xcb1705acd43072a44847ac15c97061f45b8a4281eeb4193c8b32c96d5ebcb8c0edc5a797a829e08528db33e83115b6b690870007bbf8ababfc8d324add9cece9	1	0	\\x000000010000000000800003c27bbd53e05e47c4da4643901433df7b995c2d8235f9551071c3e97ec4fff9f19c1e0d4da7f6bf8494c2ed71d048525801af1c027fab6a88f3ecb569a2856a648abaf9c5cc3e78bf0e6de2d8ac186e034bdc95ff1c9364c253cabc88fc3ab4f45c5d398fa578f18a06d2589da120f13833105fe0c662ee7a01966260237acb55010001	\\xbf9b2a617a4de75bb9e2da234ab0cc6b6f4362101a78572d2c9e26b34d7097904057df29ff09b99865a3d648436ab82615bb188eeece7eb5bb72f61518f92308	1688303827000000	1688908627000000	1751980627000000	1846588627000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
399	\\xcd0b1516ccb092782a35c5c248121a638d42fb5638b54895195d4a29a82a88875e340164dda85c4cb963e1f12cfeed4df2259315a8c9e2bf57d079f95da3004b	1	0	\\x0000000100000000008000039b9d0886dbdca42bbdb9eeb3ad0b5a21a4727ec7e2e5c793ee6588a1e47b0cff878b1b7581fc18b5a62ed2e92ab2cc27c10645d826525930ff98fb6167e5561381244544dc513cf70813e9c27cd2e9111fafe3ce950f1d9ad6c2da54caa71c449671244388da3804520fe51d271f586483933d6b0ad04064e43a0ef5d258516f010001	\\xb6daf749f97d44f720f95eda040d5c7c0da465609638a2ba00c38ea64c1955546a2e304d9cc564cbc34912a3c044b99f475aa29d03ec82b8eb0940c989f97f0e	1685885827000000	1686490627000000	1749562627000000	1844170627000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
400	\\xce4f7d47633103091faf05f0768c844b2d0fe9cc9e672c1c6b8a506c2f032ee48f27f6a95622453b144ee07f74ae0ea1c119805714f9374babf3f4801dce8b06	1	0	\\x000000010000000000800003c98f0e1e0122ab42446f69e812ca91b2e10eceae94bdeb03935dca4f3fd87defc6dcbd9c9ef66642dbc6c6d0b1a7e781d39eabe6510628a53bcad13d13c70429ac9ecdf97b62b6e54995756b9f07473354a38f5f41120ff8f1cb999c183e013b120cbeef0ad28ffe1c443b17e902c3bda383480b9542d592e46b467b176837a3010001	\\xd4ae835c7dbd9d22b053b94ef08ea98ad10ceb91203df56df0e77c4aa1ea4644463595e52c9303e9db6ccbcbb99d5d8586fd475392cb6192fdcc47b396f53604	1681654327000000	1682259127000000	1745331127000000	1839939127000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
401	\\xcfaf6bcc4b52b972f7c3b50e45d68adfa524e96b2955327d05fecb48bca1c10a33ceb7aa38150f6b84cc44d4f27592732387d20aae717f14975f382d0daec4e7	1	0	\\x000000010000000000800003c77be0a3c4b4a1bbab8d6a07a6ff4de9414f9bdcf8ad6e45f9afe494db91481a87c02ee0cd9446dec1ce428b474cfdd7dba879ecbf22627817ec0e9ddc7d019ac23ad6d4366d59f56679cd4cd9e627b7572d46105fb2ed0da5c13ba72160d99c4578e7867ebfc6bef61a1b4dbdeafeb5034fb1a4a0d4720a78fc2939e99d77e9010001	\\xea20bbeb4607e1257ce19535dce25f39a11b6609a06e560c836a040d967257af74ffd5197fe4206a27eff955a0e83d2ebb4f10df7a0c9f951dea72f47c2f7300	1670773327000000	1671378127000000	1734450127000000	1829058127000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
402	\\xd09b8bafbb65e5f1ac2ca28b827c4334f3db9fa343d3fb20a55083d5d0e92755fef35450ba89d9fcb0f6719e5bd2ef0ffc61dd726d7d22353a95eecf06ae4cbe	1	0	\\x000000010000000000800003e1feb286eb5331e43b790e18ad46f67d8950ed9f0d716a2b8730e3a184250964d85921cef2bad444d92cd999f64098120e21d1d9bb1b30661142945c603c55287bd927ebaad0c64214121131f84137c78ab7318b2cd9477a8dc2599e165334ceb0ae18062beaed5c43e5eaec1f78c23227fd6ec21ff1e9893c9b78d5f4e3963b010001	\\xbd806ad75bc062b401f207735fa25414de5e1fd1ee02e11490cfdf5f70dfb3fd1dbc7f1953e60156140cfffd840750514d32d2e15415d18bcdb756ca88004206	1680445327000000	1681050127000000	1744122127000000	1838730127000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
403	\\xd46f3973ba0bbdae15bbe4d77649d2ffe024bffd37ee7025057fa6acde732c1d45d0f4f8636cfe961b53545c98ec710c0847d3446065c657f0076a7ecfa46772	1	0	\\x000000010000000000800003a38c3f7caf599875d928d3f7119e662a9d065175d41104584977bf91c1d45d20612cb477f8fe2e84138645c9910d7f7b70d5ddad57d91c75c7bf26ea391b9ff68154a1b343f08f1f468cf497f33614befc0c374a4f4dd9110d11f7cb1b277f3be3618b22c0b1597166bd0ca7203eba548b4c0bf5f092e8f9661bfe68812c01b7010001	\\x0830492f0b3be8cb9fb8c5a2ba56f4416e24a9db235d785ea679f4b5a8b20b689d52d335612fa18c435385408cfd89d0e903584c151d8aafc314972ad725db08	1663519327000000	1664124127000000	1727196127000000	1821804127000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
404	\\xd8db471130e1b78c131e16388ff8bd8cf68bb86a3838a80e6b442a1db03c1616daf3d93e0622abd74f46a6add7e3174b742c6b0fd4fc6ef6cfa9928ac61e1a77	1	0	\\x000000010000000000800003cd337270134040bf09146819246fac8e4dabfdea66374f3bdceaba99a45f83f6ca583cc09b31835a626e2a4687e7af42dc395589609a5de97a1711b8b5cbd6088504edaf9009bda2a2fbcae7f7bb9e27b5b14f5470c01ed37a3159f6bcee0f55afc210b35fbb49e24631bcbff2ad0e6c63afef2d1f502d7829e906394088df91010001	\\xeda7b1afbf4c4be1585f5562b23fc6d7b96ee62b3bbb6aa29417b7d13ea6f582518b02980fbf4412f49d025c0fe3cc81975771a0de4a7e023260ab20e175c907	1678631827000000	1679236627000000	1742308627000000	1836916627000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
405	\\xda5fa12fdfe2c0847b0e18e995a4f0b690d4d3a3b3e87de8946753a6a30f2d8f9e64f77ab95bd525061f5f10b57127649fef08b91bf9fffe67de05940359ce29	1	0	\\x000000010000000000800003ba5ebf7722672aef6607470b8aab89541c187df011aa9c69c2eb0bb7ce318482c63fcd5a952ceb441ff95705668823828e2ddabec928b888368ecd553110051a8bc930d4c4dfacac0088d1ec17a62beb99cfc8b073c82d16ce9e5463f171b52d83b1cd8eecc507d85cb6a6cffb4fa9ef23d1cecc82d7ba457abb2df2d0d2f24b010001	\\x1e5c251becee7210d44aa585583d8e96002c95c431dd531bebb22b6ab417f9b3e9a46f4f964a4917a7193d886e44aa4094a0ea0a5e25fc326cc3e6187b8bf005	1667146327000000	1667751127000000	1730823127000000	1825431127000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
406	\\xdaeb74f3ef7150b71017c7a81fe19c1a3a1c0575b1c1fbe9ab69c6579bf5ce21762de561bf4ca5b96829ff56d15a4b4e525e92b24f19bc49487cc2449929b9ea	1	0	\\x000000010000000000800003b72f5e306d1fce1f4fcf8ec9113ce47a9e4161fddfa731adbecc5f5ef9bed3a3363bdd864acdef60a69d0b7a290143b3d3df47d9fd5965f36ffcaa40d6656ce2bf73b9e17c43fa718c9147e99c39d0a2db7db7bb018ff3ccdfee784039b83d656bc382af68133c4d1e35c5784434bbcf44c0d02ce2e71faf1751440a4b532109010001	\\x978544b4637cc25e8a09701c5f744976b6fa41635f749aac97a9d3a7386bd6009d653bc83ff6b196ef141136e490205b72cb69307d7e8ec6004ce3862fc6f308	1680445327000000	1681050127000000	1744122127000000	1838730127000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
407	\\xdd8f917626f23093585392b8076bbff1ba453c595445df6039d8770a6011f34ae5e300e0ae12087ffa3627f4901657f324dee37a622d48062c2e796c6fbab1a7	1	0	\\x000000010000000000800003adece84d49bd52fc3759caccbe1c1b526275b394cb81ba3c810dea85c37251c2dd25d324bedbecfcc3b12a43e210d622aeaa3fbbfb0c20d26b9dac34ddc3f5ec649518c6b45c8e071c4a373cefdf5c4618183d759ddf7e7cc977b942619f88574d7d23377652c920a8516ce25e9f54b955bf64ded3b105bc6af23618c6425269010001	\\x3717a0e2bbf131eb3350dcf7ab1b4d42bd401a166efa927ba1fa694df95e5f0e7c8ad1aec73af6eae7bea783ac1bd95c61f1a2254cca0496b5ac10ae57d54b0b	1664728327000000	1665333127000000	1728405127000000	1823013127000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
408	\\xdd775f835fa4f410574f8937ac3831351c5793a8274350bd248b0164c9fe47a1449b8336799c3618d270f5dccc5da992a29624cb1e0fd3127d27eef458983cf0	1	0	\\x000000010000000000800003a5b6ae9403924c2f435f7cd6d7fac81ced720f50c46742cc9aece8b96d067e6c73b3412c748c317e6870c7a598359dca905fd8c3c604e51abde15017b5a6c6c0721f0d685a0c2bac2a5f32b28fb0cd8f53ca9a4eaf29c3bfb81052551ed901bbf5ab56f69aa4f850a04bf66ad0974098bd62b8506962acf342a933ea8219b565010001	\\xf400886ac6f417e34d7ed29dc20755fed7be65a0e82ca402a2f731129181689876b71475b8c14979d173c34976a4221dc6dce00af47875027d1b407e6eee2e07	1677422827000000	1678027627000000	1741099627000000	1835707627000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
409	\\xdeafadf79aa38047696eabccc374250b544625124ed974d4e08da1cbea6a232600f68cc9ffbed1e760c9c3b6d010b191a88316dd2d334c8ea2342081f26e7d35	1	0	\\x000000010000000000800003d4580bd2eb73acf59a1ead072519b856adc7485c6f9860453117a7ee6c77fccde9cdb92b195ac6ea4dc28695f0e50777856265d17e7995a9006bc00be0b688f08a3e756fc2f8ffaccb22287124472163414a88f472ad2d7db82af2c3ae9339aa347672ef9c1cb70b6986347fab8cc14b873b60d0a1ee7e1bccdc3b64a7d6f987010001	\\xe956924c20ed2350fdbaec2b77fb787bc9cdcc45187f9172ff434933cb979dd93f5f3f18f9df4a2f694993f8789cb3d33f03c4afbdd0c93e6c8afc991fdeed08	1665937327000000	1666542127000000	1729614127000000	1824222127000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
410	\\xde97ec6999b264b814f7011fd31153b2a619597438212707d9d9d5bb874d420edfb2eeab328df52ddf8a01ea35be700b7ba48b1a709db0f1da8d68ab4ceb0b98	1	0	\\x000000010000000000800003b77e3e58b435fb904a3ab729109ddc53a8c81168ab0711e3a6243c56375ff22dc73fb869a19d0f7a2f47cc70f56c090dccaa82315a227aee82debca7fe5d88632224f0804f9c083786c345680d7088adb3444578ee793fd58d9fc87bd4df6798230cb6e460c2d7a45cc3f58b7ea53692712e13ddc524d51d4dafb53fcc3dfa8d010001	\\x8d90525eed80aa4a1c0624b70b39e244ce846d8930a625148b36693fac0b68b21a20b205d874647a6ae384965cd87c02aac793a4833baab59696464e914fc007	1690117327000000	1690722127000000	1753794127000000	1848402127000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
411	\\xe0b341e30eceb3029496e460787fd5082dc185b0d973db7d2688bc22586d056045c5e9fea0aea282a2d1717b30542c755dda107772959db72ac0553f39d4e450	1	0	\\x000000010000000000800003cdbad9c1d3f6504a5979863962eb926c674791c59c871dc81d85d012d895a01c3a689263d29c86e6dbb8b9d52661e335823f25415f96037937a605eed1646d6a6b1013f3f33ba920cc0351fd8a83e496eed2aeeddfe4f7263e1ccaf3853ae68d6a72de8f03b2ea811118172ec8baa5a695ef3ff8169d6b0fee215614bfb184e5010001	\\x6b5ea2a56e7d19d639a6b27d80fcd69177aa5fbe3f9f9b8a0c8493b38d2b943bbb04a554c2632640d1841643dae4c0c2afc627931d5c45f6591d4eb547d67000	1688908327000000	1689513127000000	1752585127000000	1847193127000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
412	\\xe1cf7149e4be49e28ccd0012413b725c6575e40f5f37729da9615e0bfc66902e3d539b6fb612a242eb9595ff9451841835f9dfb19d3f400d94d91317a03b91a1	1	0	\\x000000010000000000800003c0b073ee9b8673154f6bfc7578614763ee35a873207bc1c377a032af71b5f8706c05f53dafce551812f9299f65da468082f8253f3ec0e5c4cfffa8709a7123c3d9fb3bddf7b0479994dbae26a1eafdc3d0da6949a15ceb3833217b6c12a6abe5c061e043cfaf8f0a4ade80cc2066b8abf92d9bd3f25dc3dbe65ed8af736b627f010001	\\x7e9ab296ce16a79332ca584cc997c34f4afd3c63c26dad4111fd4e72154b73240a3768048d93e67546e7092b631e7332d6d9c0c7bae61f42c3a77958f3dad809	1681049827000000	1681654627000000	1744726627000000	1839334627000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
413	\\xe20f4ad4bb8f9b7f5ad7c2a169b6e9528d311bee31c209e7d4deb475c94cb7eb6a105fc04e04c522b246a299e7fd9adff50d541e5c59412fb8a58064dc62332a	1	0	\\x000000010000000000800003cf5d0fc5f5b411acc2a1858cacb11ab2be0e03701ca594937cc67e5e7e37955d95a4d8463eefcbaf391fe04a9b114c471b7d8395032c948827c59b8d87fa629d9404de566415de6fc75f5bfa5e67a37561066257e28423c62bbc96ca13b574bd0825e7c4d698944062875b3fe7fa0b4d1e7f1d4f445350e575d9b80cc281528f010001	\\x5946405a1fb0147991330b2cb130afbda3b299d4cee41e8b63771e8162bc43ce93a8063cf406eaf6c507140a1321748ba804e6d31931b4743a4a1d215d021807	1665937327000000	1666542127000000	1729614127000000	1824222127000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
414	\\xe65bfe7ef25632144671f225c7e335ce5239712d3501210177dd2812a41d261b990f89d268f8efe0fe21445784e30c021210bf22c571a804dfb4cb3801fe461a	1	0	\\x000000010000000000800003be1a512cf42bd23a7a32ed9da5cb29b25ee0270d3895aae44e879a6ff16e2e02286676657fa88b7aba7b3cbc60cb7c508498ff585cea4f40cc9113e122e5f9b1e874ef749c228794420d78294637345ccfd034ead06a1471f0479cf88ec7804c3e40aa0981ff839bf9aec0b93a52e99b87b5474985cb6260f01be5a0a5833039010001	\\xc2590372b2792c33aa132757cfdcb62a824be16e97d241ae78cb82a3f08c9fb9dd765fc6674b96050f257bbb284b17d97db3814a297bbe2de090a0c17bc8a004	1666541827000000	1667146627000000	1730218627000000	1824826627000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
415	\\xea4f8b9eaa3e92a7298f3454774eaeefba6f9d9c61cc3b4eef9ce3d46750f5fcce39e5746747dd50a196e19d18626b84e608f3ff43a5d61e075e31406e12255a	1	0	\\x000000010000000000800003b465be5ec7f35b936dfa30cda4caaf0f8de3acb269dd36e2b135d649904b5538f14178df1a49b9562b243072f8f245570e8ace4f41a482d9539f53db2e08a4c69041be1f76dd71c985dd87d82be69f5134bc59d17c74ae624b3828cda0a86dd8363edc1e8ffd330f503ff30c73442b909fde17c3cf5cdc2b55305de8081bc3c3010001	\\x88ce5578a79aedb3c12f22499025276fa04aba81eacc6dde96dbaa2500d00615c6ccabf3df8a0f6333560e391f1ecb943af8a842a43de3cad44c90ab5731c30d	1663519327000000	1664124127000000	1727196127000000	1821804127000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
416	\\xed834f501ffd90c50bf47b69d9826ed37e07d17ef3f7b3316409bdf9558ace4986016a8ca472a5aef6caaeb00c85eafd0dc2607ea5c62664e3b61bdd732337e0	1	0	\\x000000010000000000800003bf84d53de1721288feef5f153e962fdbb9fba39d735a2b20e219a42bf90f993af6dcf5c29402f41e809744597ed7644882a8a00250fe907685e1575b342d78bb13789b80ed79686d92ac4bc441e280b268ba72d6250f5b0a075e8ed282ecd2786f50258100bf12037c3c0dd1158f35d874e6f8fe7d97a841ae7dc49b8a2fc065010001	\\x4869afb71dfb7bf24aea79947f1140aa90fa32f4683e85805dc1f911dc02bfe23dd613acc84645c9aad68af58590a15584fb7dc7b5090971d8a209a2b04b5206	1667146327000000	1667751127000000	1730823127000000	1825431127000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
417	\\xeefb20d1ef7d9aa24e4cc8e0b5c080cb9f544994f4484c447348ab20f9d909ba43776aef144512a3b8faa6a0e0e886356e02be19ab2be96e299a5367eb54fd76	1	0	\\x0000000100000000008000039db3cce469b9484885bbee639cb3fcd7899d3bd7eebf2000c4402aba076bf6a7841e4e6f54c603b687ecda68726c5ef16e6edb794e9100435e804c5780cdae2b28df012a420873c20dfbdd3cb74652ac9526583ea128217ee90106627ae2c2bf54b30671654ace7ccd19ff57071ca4e7f681bf15412a8aa762899ef4ecd17aaf010001	\\x9328ae5860a7529a656464d4925c86422e8068758d79af3ebbf78d77ea3b25f93b13df4911d146a2127e7346454565f979d5cd5457ae11fd8924d31302a10a09	1662310327000000	1662915127000000	1725987127000000	1820595127000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
418	\\xf16b880bfae8950c177f43d3e574fa8fd6b5a0567df425baa350e02ca19de8eca6bdfec419e9f35a3b51de9d0679c60eb53f0b6475537c0c8fc8db3bc66081db	1	0	\\x000000010000000000800003b6e8f9f77d2320f629e30da49bf759b59b63bfabebce6d62563e098e2bb6270971cd4ee2870d8ccbc55aee4ad804648ee5547dc85e07a557de1dd63648720be64cfbfcc5c4b99a53f452fa680ecbfb62f4736b0df9154333a2ca445900f28265cd3f5613a12132facb18baff9405407dbaca29d7e6d52ba4d8d26e01262b771f010001	\\xc90bb86bbd74907ee50fe3024a1365e324f0d2f028cba49ac69995340814f47f21f5bb9a4817763d0a8538eaece859c97075569cf8bf58576b20601f33a0480b	1690721827000000	1691326627000000	1754398627000000	1849006627000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
419	\\xf10fc05ad6ae1b7d23a8c4a375b0631a57588a5478990d687afee4dfd103e15b6be2c2c619aad8921a868155aa2cb4b06cec9c3ad02e96e82aec96c94504e13e	1	0	\\x000000010000000000800003d958656e0c40593a39d5aa1ab415cc9c097ceeb029c1b08b1043ea746d61ee1cef6d9a72ca810008770fd7539c4a549bacdb66da2a84b7358288a07aef213741dbf6cd87762be4eeb67a2f549d2c5596b0ae00c26814837f5b3a4730195d9ad868045419d84370304614603d24df58a0fd4f2fc545faf2128aff0f6a738bf931010001	\\x7fd142edf2d29c4ad1a0e15bcb500bb7bf5f66c38a55829f67b96add5ca844573665124f87c25c367e5a9965fcb271d6fac6e2a2a62a107456a3642abf072302	1664728327000000	1665333127000000	1728405127000000	1823013127000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
420	\\xf6bf31787c610eecb4c5246e4bf5a0252a9a55a47f9abf91665ccd7061051e83e7be25b0ea6a797231df997dc0f9470dcacee7f96edbf0340c5702aea08d7c5a	1	0	\\x000000010000000000800003a8a4ac975a0c49e200da201714ddceb3dae266cf22f65c80559a21514dc8a409302ee57c8c492229826d3b816af7acc176066a7da328acd477714bba8ae23eaea5e029445f72948be379de59e803035342d7d8924d91d7b352cf12b3c2fd30c995a5da4df230fb65bf7fae9f13e543320afea591aa65c9fa3779c97dd750504d010001	\\xf46e3c8f459298736b1c087a5a17f4335086da53c2f67eca860757bb78704c27bb8fa3e92670aaea5907e41220d8889a55fa208ccfdb8d3aec40150756fb8900	1687094827000000	1687699627000000	1750771627000000	1845379627000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
421	\\xf747538c31bb838f843622836ecd7f09e9857866d9f4b4c329831235e7db1e577776a9d3969700906bd454187b76021b4e68810c97cf09b27c3461248b961462	1	0	\\x000000010000000000800003b84dfc2f9a6267f7e18207be9814dee3281fde1adb1fd69ffe5a138013d8451f57b173357eb5e9290c10245898a87a65e381de7c637f045ddca72ac482134f08568ebbef257f462de1b634e56a11108dc96fc87f9df46b9139a1dd18ccc8ba7c9d3d32dcf615d4700b270b3d4ae9cc34d7898aa1b41c56ed2d903a32f7de132b010001	\\x25e79a6c97b58e59405bde12fb42020fef2fe596df933f3e7c2c2b6373cc35a64145dd86c73654fe5cd2b5f6bdce222073d6bc7cfbb00cae3d0cd4fda3f8060c	1671377827000000	1671982627000000	1735054627000000	1829662627000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
422	\\xfbd356e570bd1577dc7d809897963b6f17e593a442ad01223eab8a7a0ea23d0fc14f4169ceff145778b06214ab5607c2bfbe2e86eed2d786871177cec98b3181	1	0	\\x0000000100000000008000039e452fbcc303bec3fc487f369923781491a723882ff9fd200f84500bf893317632b5da32be90f09f6fb36ca096c66bb0fd72cdef82842d3a18520088c5d2d569b8c5a1c3bcf3072c9ed92ebcccf0534247ab752784e3415998b59968690a101d7ae9aa5bcead2ad3533e8e4c08b30f02da575c1ef8531659d1d8f97f938899ff010001	\\x1fca1979badf60d880ba8cd4e871546d75e10c259836a2ae69bf98a27cea5da325141a0864f0e0b032e9376ac0fae0447ec9d7c73cc8b2df30469159bbbb2406	1687094827000000	1687699627000000	1750771627000000	1845379627000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
423	\\xfc7739eb9760b355933b2c03117beed91109e44d4fb7d978712c591df91ae6676c7100aa6432e0b83dd4b14fffc081088b2eff3494c213a16238daee65bfad74	1	0	\\x0000000100000000008000039677ae9139fbf67ee9da4904accdcfc0afb54f4fd8549c685a9ee65c29ac6a7daabc5b9be7e325fc015706ac78a64c36e0913b7b5de62472f936763d665479c43f8482282f872e97ae7120a2077d92f45f093663e03736a0db7901eca89670eeb8ce29152c036dc2f848c93d315f42af661cba8ffea917a5d83659f0decb78a7010001	\\xe073444c0f8cedf460ed896922bc3ff093b0c14a0b79d18601ef40b985803394fd0b6a81390365595e51c760c3a95e81610528bb8d4f988fe9cdcf5351169801	1665332827000000	1665937627000000	1729009627000000	1823617627000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
424	\\xfe974b8cc5e7806b915f34a32eb22f8bd8903644840e697335e853c2bc8a0f3afbf979d4b2d9e9b32a3b89daaf874ca9b2f012dfab4bc9460396f0e79585eca5	1	0	\\x000000010000000000800003da8094ce602c5b92c582dc01d81d144fb48ebc911fc02c46cb71766ad97c0ac17622b24a1151ae93d09f16a4f532ec4eb3bae65d0618cd65d38ee762b9a63db894cb51a9e7f12b73f4334c6c06bbf827b1da804cde20299b66b317c3382a9a8ed63fed0144c6437b0ba767c0e6c52a895625f9544deb1eb99937ebb959975be7010001	\\x4f4c34f86c41b09dd745f51c631caf5a89ab42ae517954fc4e8eb55b7b425e09db8282d8798dfafcf9ad76d514a25363c3b465e04af308eddcfcde59bf935e03	1668355327000000	1668960127000000	1732032127000000	1826640127000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\.


--
-- Data for Name: deposits_by_ready_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.deposits_by_ready_default (wire_deadline, shard, coin_pub, deposit_serial_id) FROM stdin;
1660497742000000	1050953537	\\x783eaae82ec2154e5c9ad14d3e2ce7a01764390e6aabe3668160cf0b03553495	1
1660497749000000	1050953537	\\xd5ed3b64fbbbc1e505af7c1e32a3231a4b4a42d59d35410dde1b312f9dbd3c7f	2
1660497755000000	1050953537	\\x92203c16ba68b4a4f2ba445d68b1e3375b5411e0eedcab31f76700e55c8a2039	3
\.


--
-- Data for Name: deposits_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.deposits_default (deposit_serial_id, shard, coin_pub, known_coin_id, amount_with_fee_val, amount_with_fee_frac, wallet_timestamp, exchange_timestamp, refund_deadline, wire_deadline, merchant_pub, h_contract_terms, coin_sig, wire_salt, wire_target_h_payto, done, extension_blocked, extension_details_serial_id) FROM stdin;
1	1050953537	\\x783eaae82ec2154e5c9ad14d3e2ce7a01764390e6aabe3668160cf0b03553495	1	4	0	1660496842000000	1660496844000000	1660497742000000	1660497742000000	\\x8769ccf09e8ea34fc0c56a60f4ec964cf507a82e6720df9beec492e4e213432b	\\x597874d0e5022cc5dbd261010ade882413c2ef9e8c18b4a80f5a5bba5ca5309b91e2b0f7a4a588baea19d589facc2dd755012720592e33faba0ef0ec0edc6f7c	\\x55ee6cdbaaf60fd5fb279aa824cb5513cb242c0470403aa6135b73f533f4461ce1c0a200298a5f6e3746c56011f87c2b36c205dc23378942410066d0c1bce80c	\\x45018ce122b6819ad72419be5f5c791c	\\xd31e3f48cb5318906dbbb7948326362f41604c7a728323230ae82aa995f27400	f	f	\N
2	1050953537	\\xd5ed3b64fbbbc1e505af7c1e32a3231a4b4a42d59d35410dde1b312f9dbd3c7f	3	7	0	1660496849000000	1660496851000000	1660497749000000	1660497749000000	\\x8769ccf09e8ea34fc0c56a60f4ec964cf507a82e6720df9beec492e4e213432b	\\xa6eebd77eb7679e3100e6206fec477488677a217826f47d1f22434f946e5e504ffaaf24c1a9a617a816d8a579678c0f420d4a6cbcb8510623219f37685caa2ad	\\x3f5bf6a76b15d41ab3e70d27ff62bd586e8264d2bc5d17c0988e7aa10c5d11a4ebc9f1d8a140bc760b93c2a0badadfe54a5719e0defa871a0fa339dad8484006	\\x45018ce122b6819ad72419be5f5c791c	\\xd31e3f48cb5318906dbbb7948326362f41604c7a728323230ae82aa995f27400	f	f	\N
3	1050953537	\\x92203c16ba68b4a4f2ba445d68b1e3375b5411e0eedcab31f76700e55c8a2039	6	3	0	1660496855000000	1660496857000000	1660497755000000	1660497755000000	\\x8769ccf09e8ea34fc0c56a60f4ec964cf507a82e6720df9beec492e4e213432b	\\xd720212ae0eb064129dc42076d7fe438c1c9faa21d7f3d713836ca6e76af7109115b4db437fbfb39a6a3d6e47fa5f6197e4f5c97a42ae7bcf16df9357b735ce1	\\xa44b0f728fef95ecf1bed3fbc1462585c63ba73f71e9afb19b174130ae0c45b99f7deda2d866ffe4b33d4b36a96583749d511abac21a438461c34b7e03e11703	\\x45018ce122b6819ad72419be5f5c791c	\\xd31e3f48cb5318906dbbb7948326362f41604c7a728323230ae82aa995f27400	f	f	\N
\.


--
-- Data for Name: deposits_for_matching_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.deposits_for_matching_default (refund_deadline, merchant_pub, coin_pub, deposit_serial_id) FROM stdin;
1660497742000000	\\x8769ccf09e8ea34fc0c56a60f4ec964cf507a82e6720df9beec492e4e213432b	\\x783eaae82ec2154e5c9ad14d3e2ce7a01764390e6aabe3668160cf0b03553495	1
1660497749000000	\\x8769ccf09e8ea34fc0c56a60f4ec964cf507a82e6720df9beec492e4e213432b	\\xd5ed3b64fbbbc1e505af7c1e32a3231a4b4a42d59d35410dde1b312f9dbd3c7f	2
1660497755000000	\\x8769ccf09e8ea34fc0c56a60f4ec964cf507a82e6720df9beec492e4e213432b	\\x92203c16ba68b4a4f2ba445d68b1e3375b5411e0eedcab31f76700e55c8a2039	3
\.


--
-- Data for Name: exchange_sign_keys; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.exchange_sign_keys (esk_serial, exchange_pub, master_sig, valid_from, expire_sign, expire_legal) FROM stdin;
1	\\xc0bf62b780d51bb74597af05f39b95fefc3e281ce681e4eb8b6035c26eb7e04a	\\xa555095a294fc21b21559730ed61809c3cf31d632a77b2c72d79a93792e4e025379efcec3651a51b542dc29b24063aad2fa11a85e7308a2493a26e9e4285bc01	1682268727000000	1689526327000000	1691945527000000
2	\\x530b014fb8e51f8b5479bda462c77f8d728ef55b78331f3303169f4de759bf7f	\\x1a2043536b13c444ddaccd7fae17823177d4f9833320cf8a5c7153f8dfd55546ae14d3cb216afb0ddacd4ce92e02dbe3c46829013e95c5f839820793e231fa0e	1667754127000000	1675011727000000	1677430927000000
3	\\xfbb791f7723feb8207efda8c8b03f95c21a2339ea9e29c7c4f68e479c92c4c44	\\xff1127197e35278affc4c1b867ef654e94ed4911247b52ab5369244e60d0051b962f51e45572dc94fea905e23f9be6ef421fb106adeb27c3d60b42b82b24960b	1660496827000000	1667754427000000	1670173627000000
4	\\xdd1bb80756046ddcd1edcbf53ddd3f8335b0847d430c43efc23d6d22a4695ef7	\\x152f2fa56bab6c4407575cab1f65c8b96de38f6e75ef16d84e9813a9fb86ad553f60bd895cde8d083a50dd4515e0ef18dd929ffbda34fa000e1b04449b13220e	1675011427000000	1682269027000000	1684688227000000
5	\\x9e75a33ecba1645bb55f4935584a711114b08b54a9634d07dce5c6ec95a6cc8a	\\x0912447e113f21ddbddc5c8abfce22770689b3026b7f8d386d68a59d78375c28d407cbf0ce23d0622ce202bdd8ab2e8aa6d4a43f32f66df5e08eb1140fbaa10d	1689526027000000	1696783627000000	1699202827000000
\.


--
-- Data for Name: extension_details_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.extension_details_default (extension_details_serial_id, extension_options) FROM stdin;
\.


--
-- Data for Name: extensions; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.extensions (extension_id, name, config) FROM stdin;
\.


--
-- Data for Name: global_fee; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.global_fee (global_fee_serial, start_date, end_date, history_fee_val, history_fee_frac, kyc_fee_val, kyc_fee_frac, account_fee_val, account_fee_frac, purse_fee_val, purse_fee_frac, purse_timeout, kyc_timeout, history_expiration, purse_account_limit, master_sig) FROM stdin;
1	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	0	1000000	3600000000	3600000000	31536000000000	5	\\xffba9fab782ebded3a6aab359854c18d6d9a6a3b86aaf5d1460efeaa2bb4ebe74060cb26790582c4c0f6938eba24c9cb2dec0d86a68f81c479238d99e2dcdc08
\.


--
-- Data for Name: history_requests_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.history_requests_default (history_request_serial_id, reserve_pub, request_timestamp, reserve_sig, history_fee_val, history_fee_frac) FROM stdin;
\.


--
-- Data for Name: known_coins_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.known_coins_default (known_coin_id, denominations_serial, coin_pub, age_commitment_hash, denom_sig, remaining_val, remaining_frac) FROM stdin;
1	298	\\x783eaae82ec2154e5c9ad14d3e2ce7a01764390e6aabe3668160cf0b03553495	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000044e91f4330d6bb63fece1fbb68881852860ee97c8de442b703a6d2b448b6e4840cea98c57bcef33642c085da3ae7f5ce2aefc562a59ba6dbcffc6d5228c617aa15b84aa83497945acd5d76a87dcc48c874223bf76661d002e4eb9f91791589338e97eeb649e2041dd69878f2cdc99356f0c60e3985fdd12646310d85a9298271	0	0
3	46	\\xd5ed3b64fbbbc1e505af7c1e32a3231a4b4a42d59d35410dde1b312f9dbd3c7f	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000008dbfed38ead46916ac2517d898ad6d5ee2bba954b06c7947016e6216c6afa75f060cae966dd1ebe01b591b9ae863f5fe4ec1bedb62acef97089e1f2ede89115c857ba799bac2983119a6fe95fdeaa06bc55ac88ef889703ff4a24dec62fdfdf5db4b582a794bb0e2962d005ca058db8ae8908bbe5d9f8b4f5107b027a0cf1c2b	0	1000000
6	132	\\x92203c16ba68b4a4f2ba445d68b1e3375b5411e0eedcab31f76700e55c8a2039	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000330027df591a4cd9929fe37b58bb41478029458f9c72d42812370dee7424d3f7e579d262d73c1f8c806104594465306eebfb01f4aa26671d3bbf94e0a77015997e6c07c5b6de7ed19657b558a89b1a6c65f511844b3f4b376f37143d9fc4579c27407a453da731ac1b8e206cce0a1a1de0b6997d89df8390434cb064b63f5189	0	1000000
\.


--
-- Data for Name: kyc_alerts; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.kyc_alerts (h_payto, trigger_type) FROM stdin;
\.


--
-- Data for Name: legitimizations_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.legitimizations_default (legitimization_serial_id, h_payto, expiration_time, provider_section, provider_user_id, provider_legitimization_id) FROM stdin;
\.


--
-- Data for Name: partner_accounts; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.partner_accounts (payto_uri, partner_serial_id, partner_master_sig, last_seen) FROM stdin;
\.


--
-- Data for Name: partners; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.partners (partner_serial_id, partner_master_pub, start_date, end_date, next_wad, wad_frequency, wad_fee_val, wad_fee_frac, master_sig, partner_base_url) FROM stdin;
\.


--
-- Data for Name: prewire_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.prewire_default (prewire_uuid, wire_method, finished, failed, buf) FROM stdin;
\.


--
-- Data for Name: profit_drains; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.profit_drains (profit_drain_serial_id, wtid, account_section, payto_uri, trigger_date, amount_val, amount_frac, master_sig, executed) FROM stdin;
\.


--
-- Data for Name: purse_actions; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.purse_actions (purse_pub, action_date, partner_serial_id) FROM stdin;
\.


--
-- Data for Name: purse_deposits_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.purse_deposits_default (purse_deposit_serial_id, partner_serial_id, purse_pub, coin_pub, amount_with_fee_val, amount_with_fee_frac, coin_sig) FROM stdin;
\.


--
-- Data for Name: purse_merges_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.purse_merges_default (purse_merge_request_serial_id, partner_serial_id, reserve_pub, purse_pub, merge_sig, merge_timestamp) FROM stdin;
\.


--
-- Data for Name: purse_refunds_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.purse_refunds_default (purse_refunds_serial_id, purse_pub) FROM stdin;
\.


--
-- Data for Name: purse_requests_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.purse_requests_default (purse_requests_serial_id, purse_pub, merge_pub, purse_creation, purse_expiration, h_contract_terms, age_limit, flags, refunded, finished, in_reserve_quota, amount_with_fee_val, amount_with_fee_frac, purse_fee_val, purse_fee_frac, balance_val, balance_frac, purse_sig) FROM stdin;
\.


--
-- Data for Name: recoup_by_reserve_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.recoup_by_reserve_default (reserve_out_serial_id, coin_pub) FROM stdin;
\.


--
-- Data for Name: recoup_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.recoup_default (recoup_uuid, coin_pub, coin_sig, coin_blind, amount_val, amount_frac, recoup_timestamp, reserve_out_serial_id) FROM stdin;
\.


--
-- Data for Name: recoup_refresh_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.recoup_refresh_default (recoup_refresh_uuid, coin_pub, known_coin_id, coin_sig, coin_blind, amount_val, amount_frac, recoup_timestamp, rrc_serial) FROM stdin;
\.


--
-- Data for Name: refresh_commitments_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.refresh_commitments_default (melt_serial_id, rc, old_coin_pub, old_coin_sig, amount_with_fee_val, amount_with_fee_frac, noreveal_index) FROM stdin;
1	\\xccce4f28a72744898567e6d77ebdd92202a0181a52693be4a4186aaae01cfd3a587c1c553a7fbbac47df23a4b7bbe6558ec9104a6e47ca38b43f627aba0e4296	\\x783eaae82ec2154e5c9ad14d3e2ce7a01764390e6aabe3668160cf0b03553495	\\x256d551583a72b197c62f92169f0b6c6ec906b37164bbdeff635938be566d195903ae36157483e508df2a62d4898e6b1ab6f68bdcc1b974ca694a123b83def00	4	0	0
2	\\x9771410001a8b6a80674400b15533c894137d2710d393f945f92f06831bda94bbcd69183f89263e8ad28d7064636798608ad8ebd943290fe3d114b371036ceae	\\xd5ed3b64fbbbc1e505af7c1e32a3231a4b4a42d59d35410dde1b312f9dbd3c7f	\\x59b0d868c076cb4d753879a8db11827edc1b4942f2fc792e1463153d86fd24065906408b688cd004fdaaae35dffa1b0ed99358324dfbe5728f979dec8462b901	3	0	0
3	\\x1845783ed380562cdfcbd032c4fd9281498461748c6d3d65737612e10c77390ee7b682f178c7fa7b7384b3008c796afda137affddbbdeebea01ae87488de3624	\\xd5ed3b64fbbbc1e505af7c1e32a3231a4b4a42d59d35410dde1b312f9dbd3c7f	\\x9ab9dd1c41648ff15bcb25fb151363e6d948774aab00075b4aac23c76df552ca6e426ae937836d64492d7a785700bd785a75b39c14accb2d9ed5f9113bcceb05	5	98000000	0
4	\\x2c165e52f60e85af478063b3780aa35943183ce2303dace8c9455f890fc754b2b4fd22d00189cc0afcbab5d70a7c5b69d21b61f8879df34b2737f39307509445	\\x92203c16ba68b4a4f2ba445d68b1e3375b5411e0eedcab31f76700e55c8a2039	\\x8b02ea5174ce943ee80f3949076af007ff0fa9bedfb9093ccc1414f753034a8bd39ef5f29540d510518d804020a76ac0b36cc111e827583dd54c082b89e0c403	1	99000000	1
\.


--
-- Data for Name: refresh_revealed_coins_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.refresh_revealed_coins_default (rrc_serial, melt_serial_id, freshcoin_index, link_sig, denominations_serial, coin_ev, h_coin_ev, ev_sig, ewv) FROM stdin;
1	1	0	\\xe6962647974cd8280afebd9b2b3914d1eb8f7c3c1d8df0fcbba915e20bd3663302e592db343b4a90f90822a363963d6b90cb13e61568d87c678175dd0b020905	153	\\x0000000100000100ce78a6b830576da21ab221a288cbb81326293e9305a140db1fbeb1eeb25173a5c667f9cc6287cf8caf1a007fc3cae94a2bc05cba4acaefa646d0b9553ce503ccde2b1cb3f8739e2a852a6c8762617b69e5085f75cec46d034f95c534cd22f684d066ba468ca2f3fee7b8d05f01943c173ff07f285f16c954143334c69b8c6dac	\\x9d9b145a8592881c9baa480fb27babd1862004778bef6a62dc5225601140669b2b592470d81f974ce2885e6c7f993110c01b45daac01fa1c290657c37b30bef5	\\x000000010000000185715939c5d16703c5d79bcef279fed7718f0e040e263bdc0b91e1b0284e17218faf06013ed0534683de3c92608fec578fb1340fce05c086957898f026cd93b3c9ffad587973f704edd2663d17e0d43bf7e5a2d3fbdb3197f0acb3646a3d3feb9f4d10e8c0505408d2cb60f884104dc67eb7528e37df4a749fb73e6a16d47bf5	\\x0000000100010000
2	1	1	\\x02676b0d9222fc558372e21689801a380696afdd4a6a9aa50584fac24352e3a47ccc223ab192edb1910b8c3ddcd6c566e28d928f30d6a0847d407d17daa15c04	131	\\x0000000100000100b4217ce1415b747179eb4429a4772522b3ca8a032050b747c78f033235d914ae5c9b775cb6edbc33565d61e4327a9ed6238f1bb979e84abd753eac33704aaad7a70dc8367fec3f94e9f29a14fc86c1fae255a27ff0e1f1b07b2685c6783e49ece660379a6cc558aac265703361361ad372532bbb71f8e5b6f34a02aba73e10b8	\\x29442af59a12116142b2c45fe14d5690ebec2a425c4b90a80c6248bc514aaeb438478cb6c2b8cb674e70801156e70cf785c76f2e55f9d6e11474776e4349bf20	\\x0000000100000001324bfe73f6f7121eb6836b5ea768b313ae1b452454e2dab48e5113a3cc35e7795cf8a8f46632e2948769aa316e89594f348e47953ba52df9356263c564ec52f6cca6d9557fca6093fed4fb78ea88943a35f21bc3f47148712a2eb35f2892b69c18faa694ae4c596dbdbbea4d98993451b5b384d92a1900d80983ccd20e85bc7d	\\x0000000100010000
3	1	2	\\x6d9a9888242e32d72171a4634c6b5702a3770ad18e4ff05cc9ef7f0e62499ff263e6d52945e78e845f79d3859b0ad24a77ec23a90703b17ab490d850a8253606	373	\\x0000000100000100705963aadbfa775aa2f6e5d0c9f8d4a7270d17d65d2b4fc7e400342ae75e6a5c0af2eb20baeaf1510ca38104be23ad7fc63de2fab483df2e6f4cf7f655c6df50e1c03a1e7f0cb65b513690efb20347627da18eedb97b424c507390e306d47b0858f120fb601863d598ee7f69c4d193b5675fd5401302168443f707dacae758a4	\\x7ebda84b7e6a5c2a19675ca2b4388abbede450a43f5c0461e24fd0d5693094f5b49c4581a5cd76a4a86f68458bc63a665a5e88d3c4c4f87c5d2172789fd8f194	\\x000000010000000195232c2e296b48df44f04cc01685ac7b9a8ee552684b41fcff8e3bdaac5f7f0bd8c329dd65e8817b5e9ee102d2ef76211b942d9e0843df5c5ea4cdcb4d82cfc10bbda6aa08292337550580a8efa8994cd91ee7def76a76a8ed5f8072c58699fe13a01bb57d80cdfacd44c68b7b2521aab440f05b757ccf0a5e32b2809532581b	\\x0000000100010000
4	1	3	\\x85a73c7dc667692a960e1d3a76290135f8afaa4f0a829905e1f83db95eb74cc904852e707fc1cabcc9e4a707f192cd45086772ec25adb8cb7d11007831c18801	373	\\x00000001000001005c4e95f822179af1e01ddd4503cef85e7f7dc1bf34487365b8ad03e36379b5b0d5d3b18c61ae5f3d947289316d36228a93e82351fad074fac1a2a801ce4d6761425445bcc1a441dfb92848214a2b451acc5ca0741833a22e50554ee271295e29d43ecdb4fc928acb6ae26e2b93a5c59ff20beaf0e37ef4f25463d3276267bf66	\\xfb3f7464084077a58dd3e75e27090f97fff3b3094b3a245d5745e9983c9b1d665baf0d04d4b2c14b287044e95f26dea150b1d0ef6d1540b167db9e5a02634fb4	\\x00000001000000012b8ba93df9a5730638cf99ea5fc526aee2abd1cfb57ac53f733b04d994aa8704165378e4c32870775144ad32b9900213630d0c725f53314bb8bb5b5cb3ab81e60a59918419f64e5030f54ed76bb83f05af74cc0da7306edce9812a515f459ca61759bd03a1d4a58167ad838be0d26417b5bc985b7b619b6db24c15836bf98b5d	\\x0000000100010000
5	1	4	\\xad83ace38cf2d3425f05cedf83a13a402d43a1eb191dc982fc8fab52fff1911f3e08e6d4337554ea96d0a8a4c4365ba496965854b24cafcf69a27dbea5ca7e03	373	\\x00000001000001004af2a331c4d0e78853853e94546bde3a048cf368d0fe6cc49d4e6524afadd3a609e6738d65afdaaaab2f61d2a6113a9eabd15cce3ca27044f6c0c6dc11209f43b8f10281ec2347054faf14979fa4776f706cbb4d632ff3d9326995ca9356c07db11dfb2e612fd2fc3c5a3129c1e8639365ed6d9c55ec5d0a12817536129114fa	\\x3ec572fbd0196274213af215f6b63d725e3ae90574fabc54de1689a0140ba42c5ce14776a6476314cd96f3cb6eaccc53db318a20a0cb6b4256e17e80dbc0880d	\\x0000000100000001bff25e22c608211a6ed1f31a464a85bd29b511a7f24c94c7f8b73281aad9f3449e7b90b799d426479b8390cf642d9fcae164f89348486bf5f5f6e68151657e882b5f695baa0559e81059af05a80b50f1425cb7d55900cd785be104e4a2d72b1fc40a8c494ec4a49212d9a2561d81e63747f6db428f2e6d759e7289973ed5f4	\\x0000000100010000
6	1	5	\\x82f2aa9cf30da973b24baa8b4d10022db58cf25181f3f359df416af68b380681a4af748dcb4b36f36dfe2c0327d907b73416b58db5b02fc4d67c1ffe7d1d5506	373	\\x000000010000010072102caaadd4aae5dd499b08a107435ca3425a4e81793a8d5b6789f2a5520d63abc1f1f690b7fa52789472f8aaf72db6aba4dca9c9e77a3f4684c1b95364981036c7c42dc6d737fd52c5f23633100e9fb047d13c7855bb23c82018ef03cf0f5b1e5b55f7f591cecd24cd79cdbbf777094757d0c42bcee7bd04f709ea22806b58	\\x01ec156ffd4939f67444f13f35450a97c18978da987836b3180bd15d2435794c5eae787d59f868228d291dc73708a6991cc9cf4563e927ab42e5763f21275bda	\\x00000001000000017bb37ea2b545aa74921677fcde0dc3c657e27d827f85a6cc720a49b4fb2a812a0517084acfe872f87baae40265e2c569459bd808c5333194d396450ca6069c0a1d13f0a68e72f83164e04b52a1088da3381ce56294dcb61f86c61760f34102e7ac3ac4f84989fe52a66ab06b5dccac5a4c6396ce5077449878c1897788ab31c7	\\x0000000100010000
7	1	6	\\x83fc1018b0d1cafc21fe5f1478c1147bf68a811f7640d5d7d8983b88251ef14e5f2f917321e5029fbba8ffe2b9a7a1a0f26f01ae5d4520f7a4153fd0a25c5a0e	373	\\x0000000100000100ae4f6f34f0901c9d804900aa8569e30185a15e2d80775d96144fee97bade6ca09af8c2ab3af21cb8174a5372c33f218e267cb57c666d765ccf5df9afa2be91ff5afe5f16eca3c6ae469ef867252dd26fa7477484152fbba672aabffaa09058d0b3e6dd63f7b3b108a3b04314029bd6e3de40282d445698bfd9e5a61aec0561a8	\\x1efc569713d22eef7cf2a88800c049e3f402a85e81b89e5428525d994f5d966a98e2b2f602a26162ba53b282354f8d3ad7b5b257793653f395478e8322cac3c4	\\x000000010000000165375b84474ba5d45a29204201c7c4b2c5dc293c18ec6e264c78b5b98ceb548551339668bbb81c5bdb34ea4a94eb34beba00632ca97a04d4da5cd8c5485b5c9d26e7d7de3e8276d92174d5954c298729528d57143ddf55709ca01c0734a1cb77256b0b30b4c2a01c5db2ec637b5f39bbb65c997d761f4ed1f86117f5182cfd09	\\x0000000100010000
8	1	7	\\xd9cfb682d3e74475b244bf86b350e4e3fb4ac0d1bb44803ad4e1d70c14c01ac89f83ee427887bcd433ee6599ad58c13f996742022b4ff8079bb4fe56633b9600	373	\\x0000000100000100450c48cef0f8eeac4bc249aa0cd213962e8e667579d8255112eab08b0e0d4126436c49465976b67728347a9cccf0a3f76979d81c6c6037feb6701a5b66ecd537a29da82d023cc48b86e7e3814c51e26a1bc530ba066940bf8a48a7636b4ccb1248dcc89e4bbd596d7230665f87b3f28394246db0fda987157a5818ee0fc26420	\\x2c9d7b853b31a8f7e5b3599870269e8544117096d97591c78df23eae5fa80b410722f390c65acdf0a762621bae427f5fd4e56b4f87f67b84e7dd9a5baa50e9e7	\\x00000001000000010d759fde54ddf09f4023d820cb7f724a734bd9e88bcdbd795a7fce072a1928fa5af69538e67b85e279a9b44e3eb56c940fe520190ac2ec808928ab8f98db1f60ff63ca640c1eae57c679dff1a2852be35a76ef62416a212b13a2c142d2275d690d5e51a7b13e44b6eb976082747e20b4c5cd5a41d1c48d4d0bd31f7ae876f80e	\\x0000000100010000
9	1	8	\\xc3c7303ad0122385fbc1359a570f3f7b445c469e7d98a630c5b0b6a0be401ed5cb6396fe32ec5fafa14a48a9d28f4c9961e324ad63c966f1e1da5e80c44a9b03	373	\\x000000010000010074bbc6c932e10b5ab0cb42cca7512e7134e44fcc905b5a8ddd910b7fae647faedeb03c4959f1e5f9c1a04f8ef4a14ea7558acf3d1126016955863055cfe4cc4bafe931033a8cac732baf4c8d39ba7a2fc90c0dff9f2a4fdae3020a33a80d9df195efebf29483e2151fbff0f9dde6e00f3cecaae9fc4d90cf20f647958045d93d	\\x4253da6388e45711243dfd85a4e0015a8b94fcfddd16f885d9aeb0fb52c5ead9c576300f2ab30753c3d57af44c34733e6fb12a3dc4cda87b669ffe2e555af39b	\\x000000010000000104e95d43c9f3de6680a2c402cb5e30a1ffa26c04864a7118ef1e91c31e50124d627dbe0e770396b99695ba93ab9a65c8fad6edc4f67a929fac99a2417c1b55dea80cf0440ca4806e62a53d95b539a72a166a9d80ccad83251bd03a50c97dbfa026d3b21db62b11f870a702e5ab601c3ad6a1c7c99c0786e0a1bfed2792951cd9	\\x0000000100010000
10	1	9	\\xf8512c6923fc06e4c9c8bc059b244e9ac4fff186989607274cdea1a0506d2c43897368a2b016100ae6156b374568f7ffcbed236ee9527dff5ef4612bf0aac00a	373	\\x00000001000001006c6989954e02d5b40f33df6740464873802ba309b430a781f4bfae52a35c2c5ce3538e1f1e246d0a2dbecfdfe1fd68fc910626634ae5676236b81129f86e3d86407dc8492732567982e595e158faa1624884023eee0cde2862183bacabb360b3c4d857157dbb5d221df5eb45613e0b451d6ecd31e959f04346271dac24499045	\\xed7206945f5fee78ed828b7f387ac792ed733a8fbe696ea5519b5d070ea0710851491139bf6a8c7c9fa0724e331c0ac1110e514352a93a2ba22759970668d62a	\\x0000000100000001abab5a902985be33935d7af1d6ea7f144f2e86fbf013a9b58bcb37e37d10dbf4ac287f4e2a99e52203909cd085ce6307458e5b9cfca316b4ce3989a2ef1a4eae524f1c6b07f573cf2520b69c5b6cd392e2b46f2f4c6b2bd755d3785f83a0ee0d0f9c80c932c5c83970eff5cf6a14abf48ccdc4a3adcb6c5d785ab63c78442cac	\\x0000000100010000
11	1	10	\\x12d9222be2d4790537a2eb4d9eff71261c80d57405a141f140d0796ead5e215793a8634692533457d72638d7710ced06db60dd5846a3f5edf0935f4239b6d205	354	\\x0000000100000100019ee54d838ed53ce13deb2a3c6523723c62dcedef984d0d325bd1d1ca6bd2bfa29659497d2fc0e2f9a8a5758bf7dcaae5ee48eb99c1bedf9b3c00a5182e491d93699b8dc2dde92fbab38a50b035f08327e703f2bfd3ace3f45647b2027a6b212aaad261bfeebcfa55c34abd15fc1baa1b368e58dbd6bcc9d543afe48f92f557	\\x638c985f9651e77c6a2e264e32e5b703c4fdde63ac2e52d4cd330f9d99dc2fefee3ead6aee1277b21d9b8003f27ae60c664b28e2b4804a27d64123d684acffd0	\\x00000001000000010419cc6742e4be22b8df1457cb43e88d78ad96fd07e183c29ce0b444da9e266075b0fc3b70394f0280637071738c58de9d77b8b14f37a4ce1be2c5cce7f27e466f90101d940aa9ebe38b67cfffe8ada5842bbc5c9e80bf47c785e50324b2da1a58cd0475ca32a526e153b5e17600db4098a09d4ed7013a9e74957d23f8642831	\\x0000000100010000
12	1	11	\\xec292bf2826fcd9f2453c3fd3ce154d678ed862183792df0badb4b0665ad844b87f8b7e71e3767b57b93ffb3a36ee0d941f6c164ee0737df46c512287f372b0f	354	\\x0000000100000100cb5a6b8f990f20a6efa07b0939360bae21f5ea1baff03f4f401559e3510e429f1ee6a2149762a3e98b267833975ec1593bfc490b7d13e6a7ce2a0d1245cefad1115848a158b5bf7e4d462b2a8788021f5021a656ef9805bcfbb3877115fe966f13a5ed8814e85dfd3593713ba75d047bfaf7706905080d0bfd81edcd8d7089ee	\\xddcf38f13b2b42bc39faceee3ef4504de373732ef209f38fb66bd0bacf0728bfd54ab138c67a8679795aae49269d4382dee54b789fbb916e748b3f698eeaaa9f	\\x000000010000000111517f30de015067299b03c3edba67e223bd7d3a8fc1da321c9cc8e37a2e20b997632e6993fb0a900393133df721a147f708a1e4582b4cb3d2e9e75f84d3d2217767dfceab329cb0bef7fcf0ebb846a33c55dd83f985b79ecd3eceaa018d373bbae294af18a29a16822f08b98aeec5d20b49119665897eec9dc2ce7fc68e5144	\\x0000000100010000
13	2	0	\\xd0dd68bd6cd2c0636e6c3c3875517fe73bd88002db2c9e895febb260e763b327952c8590aa02ce9336789eb7824e9b1f96b604c80a225e458d1ec8e89baad006	153	\\x00000001000001009c97bb22ed237b29e85d5fa8587f64873b853e68051f4002acccb24252f771113bd209829b4c9998f94e85acd9bb9c9952682466443bcad8b8b8ed45ea2c1bac13a31022d4a83c88689ec02d5accf32759071ec51286e81288a0c268e493b761b5525f70818900734fee8d5a199ba752681fc2e7da4a12f88eae8073bfc45a1e	\\xeb173a2662d4a635c5d95f7c8a4f8ed2c05617143fa24a05feaf9d74a5780ca7bf4838394abcc8f03f27617be6d7be81c549af83eae47430e8e139f64b81654d	\\x00000001000000016c6c51f97ebd2b82971f1d5faac8fa9c7f1801777a4d5422fa3cc4e764f8ac92e5e7fe244f563fbfa81747a0d3b030ad61940529dbc6791ea9634ea85b394022afb3fa9abcdd6479f53599953c64b8ac6d207c2ec75faddd28e8297cfc734932c796208c723be72b411bb2b36890dc771787efe6a1c896b762a0de618bd06ea3	\\x0000000100010000
14	2	1	\\x31f6efcae51377cbcf611c7a170c81bd54c089de0f61f20a3038fd9d4734285e8d927f82578c1bfb0cd6f95c36d745dcb225c148ef42b6fa8817f038f2aa5800	373	\\x0000000100000100522463283426958a007a35e902d503e574fb6d2b6f03232735a1f7e692286e2847f5731a9efbcdb2734aa4162f05c9a872cc9ae7f669f17ea8841e210d705a43309d04f8c54f295e9d82610c45916a1d89fff0183022acb494109616c39b79993bfc24617e342fcd1d9f9a8895fa6321b19785e9a2ef8b54d24cd337d16945f1	\\xedc0a38e2d8edca691a177a28f97c9f0bf5c96798a2ea696f2702a184b6a844e7750d232c5a4d9ae25effd2c06382858b775c3418299feb3ca1de052be0dbaa1	\\x0000000100000001964f4bf0342a9acaed4b59bf778095a0507fd829a259112220d365040ff863e0a38e7ec9ace9a7f5a709c41084fa250ce0fec0107e83e999c7e2dcde3a4aaba5387a968ccf02fbdb4627c23a517a226b69f11cda1c04fc7316652d4dd9cd8e92c8c2710b06a6fafbe1ea861e8efeb2907143c37680cab4d4217fab63a8541609	\\x0000000100010000
15	2	2	\\x7ebf524c660b78a45c9c4033a9ad710fec29f8bc212acc0d11f87e4615465e30c564c419b4878d7cbff7c235e1760d63cef008adb6bd6d7851816106b576e300	373	\\x0000000100000100a1c1fad4571094e22eedbebd0e8939aa23294f7d86f4fd07e08ff667970669de7ff81b4ba00a0b0537d5963ee2f8b38c1b88490966a6dea0bbf708f0b47278e11cfedd752faf07dc9240fcf9ffba4e20dc592dc3cde4dd4a40ec7036f814da0738a76c7f159c05a4f3db3a5ee8bb4bc85db1813b4274ff5139d27d52166ec254	\\xa83894bc32cda9ae3e55318275f9237a36083efe6073e6cdbf0770fe8664a73e7b6b3df06dd016781fb24cff2866ce62cb13b10b7d73abcfd0fd9637202dd4e6	\\x00000001000000012f3c45457d55da16520253cc2c56306f418c74e71652c8894af316ce291b6d8f214cbebd6ae2859bbca601f0d0f16fa1738cfe8003eca3b123866a6c9cc23111c6a13e5ae8195cb606014676d46ee771709c73b2e44a9bce8c7c7751eb75e4675319a2be39d5a38cc610677bacbb666d9bcfe34f8f5d86232cde7596a3e857e0	\\x0000000100010000
16	2	3	\\xaa7aa2bfbe67f8adcb44c5c63bd5121ca245e12a9a1a79c3877be51c4f59dd315c5744952e5cb0cb9551bd0841eb9adb58a8924e5e7af11277088760b0adb304	373	\\x0000000100000100ba1762b550fdc6f84eabbbb7bab1130e3efa7d47afabd197278614c1f184a5678b6365c601c5ad7e2ae0ae98bdfc2ad95fca0f8f60c7067dbd064296967b8561883cfb86fc5e3d5e8711308f2e984e1b9aa600dc520846f13ef831bfb3ef412eba94ddbae62be9e3f7dd1b3b9e2c6e4ac591ecfc527493dd74c610fdff940e0e	\\x95e2c5cbaf66ccb53fd30dba042fbc3bed932f91d9ad0470981f9de62373f4f81ae965a345ae7369c9f506e481aa51fd577f96c4c536c2e1597b2576d55c018b	\\x0000000100000001b07b25f4b0b98d2343b47fe8770b741324b5f71b08c84633cde209a30eda827cd7b61e1b7be3ca3954dba374ef5b058a6bab50bc5500095e680ccc63e0541e73a1709a77a82c2bafe6f3c5b1b3ed7452917c55fbf65ac7c9c5184f45e1dd0b282992374a00ec550d8fc188bfbec3bfd53c2eeb44ac1b43592272dbda99870076	\\x0000000100010000
17	2	4	\\x1631c4b50a630e282bfec403de5a614ac9f3bdf4515571cddae64caf1e7e666b3e75b8bf59d2e6ddff4e738284fb33495b074aee1301afa0e8958617a52f8a09	373	\\x00000001000001004376c84ca66c53431fa04669292a46b6362d7ae669269a030bc376a39762d8313d4b2dd66b94b3a6df0db3a4b21cdc9aaf0fdcba64751fccb58b9b0a3a343a62bb3386ba0b63dd3dc11b0c9db9f637ba6f56eb4dcb233ff2995147731ae64f6a609b4058e026e59c2644aa07c66ac973e9a1008ac1d6e1582ac02d3eb63de819	\\xfe73e0026168c83990cc9f5be4430f713f27010961eac503c46ec118cc057cad964f1fbd03d4283b7ad70d392315d986134508ec5a836c5988a0371db3bf0bcc	\\x00000001000000017bb75d657cfa7729cf8bd99b8ef8faabe9c87d95a73dee81ba73ddee1a590df931027816d08d788053d07c404fbabe227e1fd855bca03b594a56bd96a9cb6431ce511bacbe5817e6097e8703a452d3144656c8c1e92209434d547ad36af14339de70f74bd90af95d98a2b5e917ffdb344c8a2a3b464ef37f002837eb09253aaa	\\x0000000100010000
18	2	5	\\xd33f006e905dc548a9bbdf01110dff02c892318ea6b291fadba4fe93f1b99698b9d39e0a6eaafde6406f5ee74f5fe8c268471c1eb0dca128df529a29f5ee7b02	373	\\x00000001000001006950f9ef061a9fa6c24b95e82a4b08228a7ef8ed586fd8095998e4b66ced7d98167397c29a923dcfdab06d58c2ac006262d1e7d06e74bc2f41d7fc8f7b1a263d18c5caf156cd927a8ef99dbfbec9107f0d5f9842063a2b3bb907dda4842b3da311576b11f9cd0fb49cb92e818f14732bf976454a0b50e8fefbe5ca08b9540a6d	\\x5b25040455fe78d22ac3d0cf445272a09736c19bbbac4c0c576f4068ea333ff43571538f1eec6749deab5a124035114c988db21b8e21f29507beaf4c3918ce5e	\\x0000000100000001a47d35e4a9cf7d38db6507423fd20605f6c1ed470694a79a0ec57709b66a7c7bd7945b46059e974073ab5a8e392d04f3e0ab2df6c187e6295f806e63e2b12240a5d8bfc01369fb7ef3e52b0f6511b180337d2c0e8e0efa488a98419c32db6cec2532e584a81e83d7eb36c7c8ed5bd86ab4720cc4ee5f75715600aa1c2fbe4c74	\\x0000000100010000
19	2	6	\\xbf66e5e4ca44684a1471e0b502d90b3e8f5fd0b4f3213f534acfefef7bc7676e612f0f989c858d3b24f7bd513e74a38c0eebcee3d80014e46b1f4c28b4043204	373	\\x000000010000010029c8d0e026ed724dd2551120dc3e03445c06a555104fdcc6ccc06b7086b89bb51b141582e03cb684a3a84c0a5a825edf42eaa7e4c84286a91b91b38028c9c778b25a158a73f2ae780b2b457348ab311263d6fb118e031da6987ee405cc8a15af7f253a11622be06c87d87629ff294295edca1570f52fc282a27d2e109c7ba0bf	\\xc8083cb7f66caf90ac1a234f4861b6d10fcb6622fb061dd3df9510a3fe8874ba626403cae45b51437223e2169bd94bead0e285dcb6b0878e57bfaf850b9c9ad6	\\x00000001000000011389c23a162255ca4770333fbc6af4776c6ef589d415082c28ccebdd258b3c51aa35d8187ebf6bcb49f3c3093eaea9de99f284ab92091e441e0d33e2ab59cc6787a409d90bec61b904f3add711e5838c9393be06d5c5c59103fef19cb35073cbfad88e3bdf24125801506393600ca1f9f9186cdc3f02ca086ab534ee3f721643	\\x0000000100010000
20	2	7	\\xb5d4d748af50535ad556469a0ece5b876a511ccea9e83a57aec4ca52123c76657b1c666e0434a6533ff5f79cee17cf2101ed237f9c51d73fcb6bda9062a3e60d	373	\\x00000001000001009159adc7da0f5538b59e40fc837eba319701937f1e6c6904d459353f1fd08642686e8a8b76d9289545a71901546a65bb28fc7f4b435e469b4b5e865b75c896d77a37c9fca74cc7d9da681680b60d565fe0783dca3e0f3c4307909381ebadfa29a2bac75025a549b367cde7109e3cfb990a07348557ac364fefe94a098c5fd041	\\x77ce8ffb45482f561f331927ce1bbc519470282adab9debaa832dcc9d770846c3f4b2d0ebc384f429e4e97ca271113701463a1f4ffea4f4f19db1ac60c43acd9	\\x00000001000000017c91ca3d8de8159597da15147edf2b52ce7a6bd0210d3772a3997e59d3de381f9bbb6890c3f788cd2d3b3d6b7a165ae44b3ea77e4f55b37e70054ed330cfd04acc2761289c84718e678831cbee2ba80ddcf3d2123884d22741f0080b66a400021019840ba65174e8cc6feb1adc16a399c2a668731b4b6aa93d0cc9d825de0258	\\x0000000100010000
21	2	8	\\x1415667b2b5ee291c88ca11e2b918856d801657c293a0cc5ad4c0c24c03617970c28182edfc559ba88fef085580d74121e147f067dbd83cc87add01af412f50c	373	\\x00000001000001008effef987387ed8ca671a756cb400720e8d2e70254f50b43067dcdd0464a9863700b4a5704cd4cc73d4e0278b303b287eec04e2bdb4b52a9ceec2222bb12f28ec26d15d4683d1be941dda72873366406a0926247235cbb0bfab5455f5d41f3298e4e0a480ef001059e2f9ba00a4822037ba44c5e158ec7da7d492e235d504670	\\x85bcfddbf4e93f093178d01a9ef0a2122db53728f9d3090aaa9af16737ce88a634c1ec237d75603d6f23fab1ba7f676084f423feb89fb7330c292f4cacd476b1	\\x000000010000000115d92e760ff73005dd04a6025459bef8b52b788fa00c8e7f66366f9a35e9cdef522c32a35d02fa7b333241ee3a388251adfc5ea493f0b76a4ec47bd39f01d51147e1c06d9fdebff0952ad7a6a1361de91200e18c9e9ead059d060ed699e4e7ac9664da283ca15e77648e0c48844ca08f17499946136affd52dcb31290b55bdfa	\\x0000000100010000
22	2	9	\\xb822ab1d67f69b497d06f34eafe7dcff72860a3f867ac0a15075d30344f63677d138099f1884e5b82815a05db3148f5e282437030591fae1fd1741afc3ac7106	354	\\x00000001000001005e934d3ad0b2f9d539742b1567c700bd17bae56cfe0287c7543492a018b6921f76c6c75d0ff7089fac43bd8e75ba58c87aa96eb2062f42e03486ea3a7162767339e0f72e8cee7b1c2fb2f1cf2886ca59716ff1f4bcbbbb8be0cb42dbd831ba24136ea9b4a3a2f16ec99a904d2f40f089d73a6b7af1c90a2afc930f71cb111458	\\x18bf4139986568bf208668e6deffb3610867dca783460e37a93a4457229e1cd4ab2fe73e65115d8d667b49a049672b9c73bd5532dd1641f583b9dd456a81490e	\\x0000000100000001d295d06e37194d8e7fb916e6fa611d272f02b0a3286420780e639943049cf98c81e0d30a6968a355e52155b4d81eaf6f86bb178e3c6f664fcc51d96ae0907a3c26298bfb75ccd8309db49e169ce1a0856b4a9931e24ccb54586da2a5225d18db4929a25b490b0f6f1046b088c63ee81323a15795278454dac21391dbe3bc8014	\\x0000000100010000
23	2	10	\\xd84e8d18a9a040f57b5c205bbee77927b63727ec1a82066aa85e7793c30bd63c491a67f41a93a33a6e7d5facd15dec09724676377bed92b79bd06b534cef5f07	354	\\x00000001000001003ee5579347ad13d3af1e35840fa319adac822935b36c17d23ff161c35355374c5ce0c55aa1a90e44faee411fb2aadc033acd0d97e036d50066549de7a66b45cf6050722efbfade591b5e808d6d2444cd11831cbe4b81ecd9d48c593d82026776c44ef270c39701c0a2dc296301ef3646b25c6793a334698187c29c5966e586c6	\\x873fe4d68f78bc7253ebf26cc4a97d05f3aa03b3c605bccf53d87bd51e72ba0cacbc006a58b9ded06cf636c986db90aa2161a61d3ff98927b44d8508783d7e48	\\x0000000100000001b8df91933f990753a48e3bb65ccc785c840755c61cffb6c99414d0a60b9aa2fd46794f3c84de8053e147bb19e15b1faf5c03973ef28f174c87330df5f1366cc0f3275c862074fd885e3d6e2f456e4b92fae89030be121e26d6509864409627858e49772109dd049193e4985aff0861710a18267fbe3770c9618b506f20ff28ea	\\x0000000100010000
24	2	11	\\x6b1c17efbee1bc24855172cde91e24f3684b60d27c3720e4977bd4beafc9bfe7f5a1384560124f24664eaaedb025f79e0b7695b0cd749fb90a5ab7ac451ede02	354	\\x000000010000010083c948f5324f3894dead6a98f176cd3f7aeb32ff54be0924f1cf2c6f1d41747071cdb7cfc917d568885895f97b2f6a9471f818489f16a68232b9f56090b3ade9fcc69d517d9cdb212dba843f6c06399488d569e393087aa57f980eaecc11fdb61425d41101eafedd03aafaf79e5243084aac1bccecbf64e36cd85522d39a1777	\\x98be93bec7ab0478ef46341f9f4a6355d85dddf5f32b0946afc52cd15189d4137abfa55a1e17214a841d1c6d29a00053c6f3ba58968dcfe325429acb7a0f4f4a	\\x00000001000000018bf7b17371cd84de13034909fb88a073001f4166269d135cec3d4e5e923c29d2bf28ddcf155911fc74e992db8ddb62b320d0b037c5c7fafcb294a03b3c255e08f9c5439bc379dd73860ffa1eac9778c63f4046c20a30c628ab8cdf5290d3eff9b08bd55e794d5abe670722df58ea77d25385a206c94bec62b94fa1e15137da4f	\\x0000000100010000
25	3	0	\\x0c72b76510b12a3b75a557a98c6b7c6bb530bf41ccb796d30376359c9bcb3ce131faeb56e4c1a2f6762500e1ea96da2d28e08c5e5e63cc8a111d25f05d69db0c	132	\\x0000000100000100ce5ce513b50a2505448b8a5f7b42f1053fc6d429853db6ae304029eae52c38d3b3af4503c33ef80bd1f779005a74e0b97c1d53b86d2eacf9e11599950a8dd7d7d625d515522edd7aa35b9d4f45630572b01aa3358efd2f0ed1ff9ff7722c2d43c12d90ebc4c3bd253c2cf121391c8412771f472e0e0e26838066f8cfa14bcf0e	\\x1d06f6114f7649175aa19979d693d684332bac1db23a729e9ef1394e10c36e3111fefea78d2b102d740e53a082ce9aace99d169d5c37f269746ca469da858374	\\x00000001000000013367c278b787979ab0eff0c6e3c80b0b2c993a97ddebb18be55b863480d8e7776556c6e2b41979c9efe0baf121c2ef563892d397a612dc7759e614792d37df2959bb5f74d4eb85c428d23b5ece51783b154b6aa879b150e448f225fcc9a2075d844922fcf2bc865bcad5789c0e59d663912fb6f6e46de4b7db9a9f2376c31e89	\\x0000000100010000
26	3	1	\\xf055b466a3649f9528d0fc6346ae637b9280a81d8b8f501d190253e51b6fe6cd72f124731fc2c646fd499e8929943f8a8a126cbcf85219669b96088094fdb803	373	\\x00000001000001003f433a04ed3e3fd2829afbe45f54188a53f719f702549cb15087abb67699a06f54a93c195e872ea8fb4fe4e1e7b3e0375725cf2e56d6fe4fdf5d6651e8bbb7719e977ccb468b6fe7e38e7d5ca5c879f2942e3107e5d8f2490f812e4865e095c1be7b18aa9735f43044abf6ef28ffbb2b06edc55133695473cd513f2f5d56f4f3	\\xfa4812cb523a8ce0a14dd3216e19f80bdf1d5453df10f940eb91ea71ac072c34843b70f3d8a74413ec40dd51dffc3f6e332a1336d7a7d24ba854f057e76da124	\\x00000001000000014c61aa52da8ce4c5bfb60903f54418bca53833693d00b9dac443243d7de2cfe1e6552333f078b0d290f8782f397ccc1dfb55324e644fb6eaf626d154645baefc6f0d24dedb79a7b4e85e7ade4b0a2189fe7155414b59acb4489605bc703080c9f191e7a4638d661a7104401a55c6e5a6e136f2ced87d77b136beb28dfed1eb3e	\\x0000000100010000
27	3	2	\\x5b0800ac3a8bbc7bb8314214b481b324e680d5e000d476b164d40191c0e8cd3e9500d39d350f10d799cb2544b3a4d9af109fd9429d925bce095cecfbf84db606	373	\\x0000000100000100936268acac9b09abc5f6e9afddbff2b2ac43381ee2e034a69c9615a808d03dc6f356a374f20375d05742aa2a1e54e227bee7abcfc910be4e02b868b065494847f59473cb565ee777726dbc2195f992b0b279310248c374fa2209abe7a8ff994c1388f36559d32828667d14eec952b1757de56011b5662fbc9736f7269763d4a7	\\x39bbccb4bc0111f8996d8401c3ac77947cf777af4ca78694f2eda46d29ff75d97b8dc54fb415e600906cdbf26390cd106020172929b34f504129af460d704842	\\x00000001000000017b1e0055721b4c4deeb9771870186f0b1dbf90ae9b706d45b56d5a00c80ea6bcc87f4454004245b9b8bc560dbd13828cdf358ad847d1d35670a7592bb441aa4ca82c3edb11a96690474b39e708e2fc3b83f9f348c793baf085e827d1da5be6cd5ab741e3aece3e67982c3a139fa92dff8b283ce84dc9a8af8105d6a5786234a2	\\x0000000100010000
28	3	3	\\xcdff80a845c266fef285fee848393a8b93a78085dc13169addf70093677dbcbecf1cd40e39e712c7e4f17387ab6f3edd9ca13e1a5c8ab6bf6a708427fcb6f508	373	\\x0000000100000100bdd89763cc36c44f7aad478ea167dd566328b091898d6c3618e2a2d8c6b630cf8f04fcaca4bc74df1866a50049e13c03edd78dd03599631360149dc996cb4f57a462a21ebeca6000057217c39bfc2b2a5cffb546da85845cd3c292b60aa83dc6ddc2506bb0e09ed531619ea84120802a106a8f492d4b0769ac6cd50665526078	\\x9ea33a45a9e989a1ca8161faed11d92f004e4ba44ac7f9316b09047b5b2ab7cce98733631eb566d428a7a2540d3803f09f85fc73c15760bf7691c24cb1d4b497	\\x000000010000000173f991f26c6cdb8a7629e0be7222162322c63970d80afd86fe3f6e3f2a646b5d96b7aad26d45dc46ff4f5a35184271de18580a03f769643ca4adbf6b092e91841530a3d9d35c1b0ef9cfa15f7520d6db7b07437cdbd4a5b135fe47260eded00366057f55d46d003a73ec0049128e47ddc1374449f9f65821e8c3487153c9eb7b	\\x0000000100010000
29	3	4	\\x6c2c23144d2829fbecb7eb3b11b51fc86464952de9fcfaa7602e6ab3074ce566646986e7c2c3075ebfc12932a4291b00394cbe4e6e61a493de9a96266cf7f703	373	\\x000000010000010030675d05dc088456ba7ac090d38e37c6e1c5d4e5d5c16b6a531e1c84f431ac7b166eb065217d281818c3adedf0d4ee581c804ba132c4522fffe4431540f68e2894fda05baf3a4a4105be39a0cc9d4744da87aff3877697c4a8587e0db9686ce7d86498715953cda3db89c02faeb12f9457791a8f5beacc9cd5801259724e1185	\\x9a66f4fc12dd14d4ec689748cd8091470b446a5935f720457949cd91a1e42bd211bef7511cd7a4db7890a2f48de80cac4c5f73e71d2bb990f7c560965e01b5ee	\\x0000000100000001489650b9283612e43cba9a9d49065bb939eb95929f39bea66e4a6b3036170ccb53018a5e3f28c7101cb76e0a3f8d8de023002f3f96386a0b5f78d6df5ed96491ddd1d7617c1467d3cf63f4e261d8941787fe40ad96139bea021cbdc6ad9611962805b5e4948f44feb4e54923eac8dd2a3a907585f55f4df1b87b2746f1213787	\\x0000000100010000
30	3	5	\\x90b286b29039e903bb2240ee23275586a2242becfa1936fc26da17728742217cda02dabbc825e19982199ba91535fe36f6c515e11e07afcd8868611406fa740e	373	\\x00000001000001005c4b91b6ac15ca216e7bc584b9c7b30de325d57b981182a736507a0933d443f46aff46798226d51aeaec76278b10d897fc556c725ed7b6048265b834f6122a42b89d2acceba546adba7d923ac34b064ce01b0b150fa333063b301edf6dbd19a5321bcab6d6857c8bfb977f48b63bc94ce2a64f47cb69311364b88a7f6b8b683a	\\x63b28260ce3c738136f26cf098e546eba6b081e2dbba12cd40d09510a0b581cfc8b1c28aaaf44830749bb880240e6a14d740667ad4818cd4e6cee96508b6bff1	\\x00000001000000010a93c79ff34102499af19af101e1155c299b25b31f6ff943599678ba978e8518047c225f4d750d46d885cc4a490693db36629745cded3f8fc5a30ddf30e6a03689474252d3d06d75c4697b29faf2a3853601796d2967bc954fe82e65fd8219c0dc138a9707a7b8b35fac53e04f56fdbc4a62521d18d23b727963e485fd5b49ef	\\x0000000100010000
31	3	6	\\x47f92fc5b970f52217575081601825903064d860fb405484313e8aabf859fa4e342081378ecf6bcaf8be8c60f0e2b5e3733b005eb7736344243b127a67c4f002	373	\\x00000001000001009aa688f09da5f35b6a13b75039c859b2094c12c410e351e26d069ad4d355825bd1d9dba37217179a00a8339f63ddd8da5e65caf7acea910996f54daf84632b32bfec2e9db8892261e159d3efbccc34d8206d263ddf889d154bb0a6091a095ca3098e47b2498d24b010ca2b8d7ceb18aa3d6ff913bcba003d49df7783da1db8c3	\\x35bfd437b59a8dbe9c6fca7e1fd317f40d05060aebd933b68003ff86f82f6a715ce90b72aed4b1771dd2ab1988b8de9a881fcfbc7bd9fea8ff293a63a39b1e4a	\\x0000000100000001a5d956491a423b8f3518b4b89e6ef2e3706961ffa556fd4157724699261312b498df06dd056c81cca7ee9726ce0a706902d77fe6ce5cd70054695778efe89df0a47ea412ff5e43e164a1eba4313ebb278ae64d9acfb6d2f1ab55b52b55ae46725b9ef86618cf6a1b5808f1a4752131be6c3d4d0ff798c20f14a6e107ca7f8d54	\\x0000000100010000
32	3	7	\\x46e45c958d557b877bf9a2154e050ef99d03b311fe72f4acc785ccd0e7dc89fca26aa57d0b783bfc543410fd1b8f0df329682c274bb0f0f35d2ef7ce96f6fc0a	373	\\x000000010000010098d5f4787e05ad0661028383a1eed7403b8c9eacda179f9831fe375229dc12b5f9ae6574b0e87149a61fab996fc26d171ad036068ccd88a9e03df12de9d4b5e8e45588245b6f4c4513c1eadc2f00ed15f5ddd957b7e0e58c7bdbae5e1d0fd8e2b6bba5b4c0758bda32247d4af4940c23167f9702a92e757004eec6f8cc84f15a	\\x1733c50c5ec5241bd0a1e78aa3a7b0f11f5923c117e3fda31d22ee79445b80022f211633df10d320c81f1a953329716af9cc416a71a76066d87d888d7ba6b71e	\\x0000000100000001bd298b74114d0a85b331ef742ab7d28636259eb89440de17ab99781a026e9bdf1a5d11ef3ead989714b9887e91efd5e00dabe1948a3707f523fb7eab9e5dca702425154774e67380894009ecb775f45368029d2673f5fc9acc4b6d7c188c33697eb16c87ea2cffec8a508e9ddc307c4d5a10babbbab1d622b14c778fe7d05602	\\x0000000100010000
33	3	8	\\xfc51c605535c00e0edb38d0ba85de693d79ab0d79a60c9bbb18f6c591a54de2b8f8fad741540a502bb35ebea7a180d813ff0ad67c9e79728251894b7f7ca1e0d	373	\\x0000000100000100bd11a63510e741fe5c591dfb9268c844b79a4667a7a11b283fdd26fd3de71ffeed838a071859326c4f694656571fa73b32275290d4c4c74847d7a9408c51f3e030126e05ea479e91502d6bbc826428476834acbaa90d1399dee9e5ecb36de8ffe5bae79a52893495b081c3267be2d3475e0175f90212488f0fc972b7200c6e87	\\x583332b4c0ebb1e0890ecbb684b6a8f6453e9e286a170fbe433f1f0cb7c712c27f32238bf0ccf62f4a9b824778cf81893591dbd758b03ebc1ff861fe4f51358f	\\x00000001000000012f9dbefd03b9a4029fd7dc01b2bed1e925d96318219b2850e024f3a488ec0ebe1a94ec17518e84bde6c2ddd03cbf5c5b9069fa5f1c9f78d0d3e9eea412b0080f9117846e501492d1394d5968e7dabc42ad2712dac7b3c9cc743bd3575149fa51b691a0988a2e33e5d0edeba0979d86eba1ea516f7ccb6b8184fe7f114c379215	\\x0000000100010000
34	3	9	\\xac4701b36a9f85d93792273889d4f311aecf210e39d5d39b552efa4c215e55961af8f7c7669ddd864ac949dcf15a56f6c18f4622417af9cec3cfae8e13b0f507	354	\\x00000001000001007243061544ac557314d42a2de690379a9b6abd9c75f9a64d83d204f9314284ebd9ba448cade283b8bcb2671858ee7bd81ef0f7f2e879d630b58be1569e2d6846468c49bfc0407d0bb071ee50c6d74937feace095907c7a1c343430bf70e49dd25134d63c252ed6f25131ab3ce964df5d1d9afbf0878c7bcc6fe893ea00ab4cd9	\\xccfca8e19c98269dc4026aa55d4281d72b1c2706953df4c2746b1804c2c95406a18dd0efe7c927fc84466361e768cd762bbc490bb858e8d51c2ee382876ca143	\\x000000010000000138fa719854583adcca1ee9ee102ed8468823dd036941a50e52591f2a2812fe608b3ad92e47dc88b14c75b9eb38cc8eecb9ea772330a5f6597d6744b06149d18e237035c8d2bff1e2dab345310294f5358494d81b25f86a8ea4384d7de4efe1f350faf63c685796e4adcb92190b767d9d9bb533ed14a3127fb205e0201f01f510	\\x0000000100010000
35	3	10	\\x2d7020098b8c448a10f54e2a3528544195659467de7b741153b8d2e526973ce12c14dc84c829295030df772ad6da032c8d488afb740ed1b12d19c23158856d01	354	\\x0000000100000100a898b7e9dd00d351d1d1b0ad47bb1d121b9d871fa92d36f7d576a135c48614b340330809cee635bb5191c430ef4a0bf7badb42bf9a28456c88d836094aef6642309f15cc560be247d01dba63e33d5dc89ceb480bbf9653da1a721f04b5dd59b6f166ef8fef8d85882c9a8126618b7963fa4d76987765f8cadd7c8bf444eb4947	\\x3dd6fb05caa7abc469a9e05733fb7f68ab6e0d98aafbc9ab0ef9d5ad833097a8a1b45a954ba5535e35f5da9172306a0e66824ddfd798d002d746036ebbc371cd	\\x0000000100000001d2d3c1ebf93c5ac1a285d3c1da18508772837d29d26b8ba2bda0516ca486db9e348098e603128a00dd4f3cef7cfc78a7cfe685a6f7b61ec0327ca3dd0b220e1e752bc5e83a8a0f462e927c09648a5c205e0a8257c2adb997386bf7e2e985c055420306f100507605b5424b222b3f75e50c8c1f5c56f176a93e3528e124566e4d	\\x0000000100010000
36	3	11	\\x404de611489e6c4d1215549d88ac1251f8a075bf12d710f8b5ee77cebdefdd2028ec5156b060656c927b53de10540556b79c5e6027a1c4dc943e9950a633e30b	354	\\x00000001000001000e0d28019f54dfa9e24bce720d0e7e99e2b0e5177fc6960fbde31331b0e2b3495e671dc263447f8a88971b9f825e9bf649baa15116fb00721793798ff021897aa1ad756fc5dd7f081d45bfbb86e2c7e0dfdce5ec1506abbbfce9a352637835e70093c8f86dbcf1ead5d3e486aea4ed3c4dec0b5a6804969bfbebe897ea837b28	\\xe5d9d6ed2bfc5979a062576a71fdf9ae55955e251a57e717feeb6455f5b51065743a93a67ff253d6ce02f3deb709e68668b895f5c89ab0c5c053fe9081431e02	\\x00000001000000014723524313e3a4536226719420e07b425885c88e9bdf709c968ce47f0d32d9682e1440ded7e231bdf23994e252623e97a3806df2ca30e4ba80f3cb6d46c23e5b8d1b48bdfa5dccd1ccedc52183746843c24345fb0e76ab6aaf5a14090ed858abe79c35d5d1210dd974e8f72a914dc7f985fd0159e632c099bfb0909d62783043	\\x0000000100010000
37	4	0	\\x96931e50a51ac14b5b51de85f1c7f8c89669ebf00d8494404896c898ccc7dd135bac9dc74159138b95569ed7b76b70665e690927a9080a48912be33651f04105	131	\\x0000000100000100a8917ff899932cde9ad6334ea6d59252c5d67eeff5fbf226db112fcf4620dd66c8e9e9658b0fe3d88df2db2f9febe7dd246fdc75f07316a765987be3ef9ea99fbb7831133d7ab39d8f50bc6c3042908e0efe0c011c160ccbbf7e3fefda81a38eeef11bcda91239f2b1225b7486f4149828a9f51a3b0767dd5c7ce0b9fc2be090	\\xc7378f4a9bfe3aa515a33d7b06a21f9b0af589da49918fc16ac161b4d682857d200c51ae916307be46c7e1729e936fdf4258d4f4c5e50a8bf6ca916aced96cba	\\x0000000100000001aa82e1ae452869fbb22e0f234a02ebe0777ffc9f648f088bffe6147118b24089bfdcffc210a943b16476ff405f7355f891f9ff20e934d9952ab13e04421523f4960838cddc1f8e7c29a68ca92891481776b2f0ada2693260010224be9a179b26a85b8ef19326297b3b213d31daad18d070b91c80a086037a7418fe93e862561e	\\x0000000100010000
38	4	1	\\x3a8979b210a4fa5a498f5e29288c25eb5a6ee3473a5341c05c6c3e58976b809a0d28e965003d05c9908f7c39d3d3019be3bd80de6d551aa92ea240b26f3de100	373	\\x00000001000001008f200f976bf2730ea8493e572f45dd414dc673457b9807a0f46cf476fb2b0866f8af9fc1d29e7526bcc5ec13f65c8746b3c3f549dd46d1312c7d8a0ce14bd1ea4b4264636b0ae3ebd3231e5b9363e1a91c249defdbefb3c5b96600eb9f56c0ea0f57507c28a2b5236d9b67d3623ccb2ccc09c9618d7f0bc877927be4252a4f6a	\\x7791762645229d2b62156bb70d29900817a79aad66f6a0a70e44e7284fcde4706aafcb94819c4584ff58c379c179aa892395575d4b09a06ceab020b965476756	\\x000000010000000152c5b966ad99dab7be11c23252adf416dd5db20c480a4930a3ac93a1d5a3c85abd4d550c9f7529cc80d721fce336185027b622331943932764870af035ac025a04f1f898922bbc76c2fc043ad712cf55692429a624198ad508111c1b7f59521650022bf16981e719a58bb86b0435fe403ba53b4d009607a5565861d4a165442a	\\x0000000100010000
39	4	2	\\x907361cadcb2f27003b633efd634fe3fa7d7626cea1ff28eb92858daf4fba885971b55e55f2582aec7d84f0965b6e2b2bcf88b5449e84304fc0837d531be1802	373	\\x0000000100000100475588d61082fb80464877129658d3d3999d5134a367f7f80ace346a7f7abb73c0e976b28c937b24c6b53da5d285dc05c6e37a9334542572fab23657070c2877d108fea1d2e1423ad363d12062b5cfaa31eeacd0e8eb680a07528b942065c9dcfe175a646ebe087e1f35b8120237b7c29472882cda3ee0f8ad1a52ebe395e8aa	\\xeb2aa4b2952b67f19124a06a30aceee22acbb191021f2de427561c5011576eb7838578e2de085fec1accac6e8b172c1dc047121c8eca07be91c7d672a71441e5	\\x000000010000000143fae2882bedfd3d0689427b653ff2f398b9091582828067d7adff06c843162c4889599ef4731e9a7e467d76ea089f0469879ad8d1bede10b7ca6af4ee912ad7afb70b08cfad93ffd3c24464a2c73e343b994c19d49cbbbaa6fb3112312960dd4e1f84b31eebf839057ed9a42c3dfaa6f3fb31623dbe457b22fe73813b3efa19	\\x0000000100010000
40	4	3	\\xf48bb3e6adefb0a8c432177f6fcfab3eba8268a38d4dfaf4f16e3287254b6805adad83a2fc45f0454eeca10cc5c73bbaae1a71df033221078378f55c3f5d1406	373	\\x0000000100000100b536a68169c4c4ce25debd7b68d7a7edf7849884fa21df97553a0206f345d345eba2108ae9932a489710d8f56c77113dd2b4cc4bde2fc5a7e477a2f5256f3fab61b8b68bedd061a845d9c5aafd9845168804e7a25a3af7e352bdcb4f08895e4a4e0a0c8f416376707855223f7996a2ccd1520e68822b2c2348b84a5577a175b6	\\x03353b6c258e910525aee5a5cfab1d3c1e5351a81c27bbe98ebc8a3acd5ee0dbb3eee29800553a1216b8326453e89d2e30110c0059576e65136d579740e22c99	\\x00000001000000011f11f019abdffa9ebf6d14023e6aa45095cbee543b2bcf924539323823d9b1eca062753b5ce91787ad65000c1a2ab512b77b819d6e49ac15e379fb885f157429e7dbcee59cde2259a99eb98b062d5a35ee14e47e1d9fc5cd7829de44d29947d6f7bf7c8cd63aac0ff30e3e4e69e91ff07758d909963a18907086af20a0b80fd9	\\x0000000100010000
41	4	4	\\x0caa8280c3f10d574e1244f72f0800d444582f7374c56f9c806414c5cb9f4e6e55484cc88e78072ba5619c2dadc7a169ace0d7f65bd64b41a6af228bd7810d0c	373	\\x0000000100000100037d3158666cbde82c051573d70e1f36d1df9ad41d51681fd4bcbd4e6435047d9f4c537c43f8d9c46183cf2656d21e45e4ebe36ad16c5b1cc4a5e021fe72e9cb0e6f784eac40d253956df8e5906fcb7b76afe7b94b3857da25acde3e36b28e8fbf784e7fdaf607006acc22373326d0acc03ef21b149b24b42444ef53c1fd86c5	\\x98d9d04b06fa3e5d3a12f81a09fdbc04d312d89fa3d47bf16f4fbdec163ddd07e35c8b11bee1e25ab6841c0cfff0a43f1e66ae5f9a1d1afdc35505cbd8b94081	\\x00000001000000013decd68b6a50c708602d149fb33a884b3d09a346eec30bbc448b30d2fbd48b821a9bc678ac47538740cef100f41a56de297c06890914c898108091254a194bc1eca7885929934ea04ad1bd65ecbbbbdb6999cb6a9fd147232f7b373f964b7ca90454a9091f1447f0e69bbfab98133a3824daaa25ea616b4eef4742c5f8698122	\\x0000000100010000
42	4	5	\\x861c1e8eed3c64ec9d6ae3d7b93def7e43c781c3a3ce703a16b29ac2f5bdf8e37706fee1fecc69842b0215861f4694adb6c1a4340adf4410496d5370947ded09	373	\\x0000000100000100731e60ad4c91020558bbaf8eb03878cca11bfd3be19e246cfcf0c0c03af463dcfd6397470612097120e1e2649e5fcfd70467dcba62572f751955607daeb2a639390d6baa2120bc97b0d010a70f2ed7fa90e5b20d5ddb8e6c3600aeebdea853d2a593bf9b9d990824fed5a493aa1f22b58337d73a14e95a2a130cf0c15848519c	\\xddd850afa40dac4eff573e79afffe0a8bfedaebd9d19e0a757c22a896be163b8101473e3722ffa3ab668b1878009b7977a4016532858217d5e45683923f69415	\\x0000000100000001ca42418fcfe6db43b59213ab9d9005099296c12c60d4be9659f347a527bd59a8a77c3e8312630ce097490083f2418fac451468ed06f29e37c331f36bc5270539a1dd8656bf20313e773692ccaba508efc64aef7ad9a230ca3bbc6820947a943912eaa7876076abcef101e439b041afc3a32bda1fa2d4506e7c1e0846177c13aa	\\x0000000100010000
43	4	6	\\x5089f30fdb01f39b5209ebfdfc64bb5a9e22db476ca479aa0e83fea06af945bf6b1f1437c9e1a718684f3304551127ca6cea86e8a34ca1d4fe9653eb8922cc04	373	\\x0000000100000100564c2ecd277a93f204d232bb569c03e1c5dea3966390fcd5f270c7e7434172b37b42c9d02548187a5845e5d2fde20a955e7e0165737bc2aca53ac1d8c1b6d4bcd2ce2e500e087d083a5cf1f77ddf63ec1a7da58425a518925a82bbe18caa77c243b3f670dd95bf9e24d8c2da1f22463c0670d847feb44ca90e66f0136021e636	\\x2815acdf5e8b7c70ff124ecde716a7dcec427cba253f135cf2333516acf1d79c2ce6981b1c7cbfd7be54d0ecad92ce393c8be06a04a265f18ced7d61058bf0ca	\\x000000010000000152388d9722973fb6a3295799456723fe7d20ee094197442397fbf4091506724d79d633d934c0b4447dd394ab0bdc1d78118492f736a7289325f813b2a0a8086986cddf3c85316d5b4ba4ac4ed3ececb03d8df7075106302ec7edfdc4d725ca1149dc3207212c90bd707232bea9c07eb94456423b131433b8433a91393808ed12	\\x0000000100010000
44	4	7	\\x8d8b4ca3dadb91c4d8eecc1117b32bacfb7c163c82a6a7fae3b8d38e5b13bda23a7f100fb05318d14ceaf27bf8112b3256f63959b68827a70a3e9ca75b5eda0f	373	\\x000000010000010014b08d38b7a44dbe016dd2b344e0ea7b1286badecf75756ee8bb9423b4e02b378d3abcec24d300058b87b723274519d94b768f158e84b7aea25bc57265720f83949046ee1d52b11297445b234442015de780744983efbfeab3ca22e1fde92155674b35fd51f7381053e7180d5d4311b35d5aae35d817f6cee6a1dfbf8c02f90d	\\x6a7c40a6424361a8b9819a908bb825bf5bc7268233e5205d2e39646a05e40bc0b1a1e5692654ed50b0442c3aa1660d9fe9eee4a7c620ec176c069e23d7db101c	\\x0000000100000001a03850dae28186813f6178000cf2e1baa29db225d1ad5853de3d33a3b510290b31cd6668b178e64e3c8cea192ed5c8ad784b14ab509cb36c182e0ea68cae8b08d7ece983217cd8cc423ef400464321e5488f3c8435ae88b6f2b03636551e2ba8d0a9d18bb0711769047188f8080929ff9413f9db81a638f879158b2ea08910f2	\\x0000000100010000
45	4	8	\\xaefe193a416461b9493b5b9647b97b67b7e3d24028135980ad06fc425b20e7f886ae0d9999b3ca566d8d89fedb9d24b940e27fb56cf6546cd02346173a3bcc0c	373	\\x000000010000010099d4a5db0826f9a126d228386f2188c7cf2e1f8d559d0e223e0624b7b84b778a6c6a3bc87b46c1340711ee48ba12f91c869c134d0e956fb01bd5b0a6ab4c2e45e31facabae0e64520fcc890b19723f3f2e87690f9aeaca82fce826354b9fd2fc6eeaccfd0a993b261645ea817df3535f55757fcda15c927b2aa5e513bfedc185	\\x02d9cde8468c54561b82c600649ca96a13abf7ef5cbe59b4fe9a9027d07c394837f28cfe0264da449561d4edbaee6889b32eda8c6ea26fb98d6214c6e5fb7db0	\\x00000001000000019570a1a33075d0758d627ca6f781ca0a954a0ba17d3f1a9452f676b46408cdc16d44fbaea7498fa040fbc4cdcaa06c0154efd05c80a4f5976c6b71f352d3cd07b2c3b56d96b049a65b0c6344b7d5065e18a4668160990972b5585d6a3e203aa4a443ae599a1abc4fedf9d9d662adc1e95023b24e71647c59599ce11e4b009059	\\x0000000100010000
46	4	9	\\xc9447a5f935c49604050882e5c6f1f8dffa070c49fbabdf8fa99ddc0cabf06bd07d2accdd646930e8741de96e7fa6cd920947654dbd8e8da52cb6e9281fe730b	354	\\x00000001000001005f91c7221223901676f24bfed97c62d6fdbe25ab4359b9b0988d1584f12d8ede853d29e71be35e36e28011a1f26d5f22dca27764aec0dbe508da8563d3849b6fb7be2fcfa39a6c2ba8f76ad6a174993924816af6ea3de6e59dc586a4a77697f8f166658f918c0132f57691f579cee603707868730febb4d61ed98f5738636292	\\x011f9e1247d15d4bd9cb1b0245212fdb55fd1b7fcff4be5e027a5e75d0f9fc37746319065688e7e95bf522a85884701a191ff18f9709a16a30090d6c6916dfb5	\\x0000000100000001821a7ad9384f4122abeb7baeb4091be505359855cff3f358b2375cd09cc563cbeae9a7cdb8c647c127608b0dd5b18c630535f3b9645c9cc9e4bb4cb6a4e898c81a673547a65b978bcdcea2ad15a5fd666c7530ef4d00b32c0905e2812170e899546a16bafc32ec5d6143d8dc9847a2572ca9f16624b3664cb3d5d45b497626cd	\\x0000000100010000
47	4	10	\\x49839c73df018ba4b2e5ce8dcb07cac5bea97c2b297f2aaa7f4d0d6bfb03374b25a18ece324b1d8667d3fa4d307f957240a5e2984918a2a98917a058a861950c	354	\\x0000000100000100b18613547af5593cc63318afb0135374dab5e48c7e151b029a5189eb66caac4eda09cf0bb132e70e7d383486a94d646ea9b70dbe4876d4834066cc6f89e406c943d0ab6ad664665818eafe040aacf610e74938a086d9bd3ea95a913dfa8e362f4b58a9e41d56043c48515bab3056f48a4a89a9f6a088d7be4a3ce7274f687032	\\xd3894ed9c04511eea96f5e8a4926824a0f51d4ee673d526d46bf1407a99a520d8b98f67dff793091a0fdea69835d6240b6658f22cf724a8417cfe17d3c63a738	\\x0000000100000001553ae0d6bf1387527ea9788c1cdad398fc55e2b4903e2ab16559248ee23e6350ed4ff52824a435e81da05432526c7173ce724a27cb539a6d58a8d47c1e2553e0d47206b93438396a7e89c8e1aa3c3227a34a7d84db1fe7890b24af44b42037d53818ccaa233ac84a172bb6e391293c480fe3fc3e956660f1d3b41d048c170f97	\\x0000000100010000
48	4	11	\\x042b933a0fc40ba75b1b1e8532a9b9fbca7eba8d3519c2a082ba264c4852bbb75bdee077d286f38916e7c3ce42a4c28c56937006fd0f1e3dbe971e3e3bac3600	354	\\x0000000100000100512ffb9179838dfa7a974740ccef33ddad5e8e25bdf380f27fdac190d35a1cb83e355cefe4b926762a40374edf993a08848204b8008e13b65174a02ae8055919ebe954b6d6a2f4d75a430d623ff84242a7361beb2bda33e7b6c1fe9cdcbb5a583027e926fdbd952094ca4b75931201b258bd313285cf2b47e65e3888905962f6	\\x183575419318156963775e1b4e8f744e2994d65aaea344f7255d3746a078736709c9f9c2766741cca27b8563ccb56b0e978933b18af2ed0476e4aaa5fc66bc69	\\x0000000100000001b6a62635010ee6250fe1eb274b9dc501e0b8ed98b1e140920c85ce953aa3e9b2a79217afc0ba3a0067cbce39ebca27b92d073ef29d3d7a3510d4652c231000ce9e28a50164d4127cc297a40be3d9ed2a8d749c906cc61f87f353af408c9291ae8ba81610605ef169c29c11ce9492f7d064e2c77448d3cfe2078347329699f1b4	\\x0000000100010000
\.


--
-- Data for Name: refresh_transfer_keys_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.refresh_transfer_keys_default (rtc_serial, melt_serial_id, transfer_pub, transfer_privs) FROM stdin;
1	1	\\x8ef44e006163985ebc2a24b0411d05947acf39bd6d547006a3654fdeeaa6f92a	\\x48006dc0ccd70956cfafee43ce8a4d41cc2afd2628d61cb247a916a0159915c5441e31a339576d40c96805624eca77f052e2cfaf9de6008c0eebd732162c3798
2	2	\\xf1592ed8856fdf1ef9d4aacfb5f7ecf5a6777d21ce6cd7037babcdf0ac8bc92d	\\x1f8a8ff90f31aaa9da49a087071df69398d285559b437e8427b8443beba9a0c6225af426a0959d2448b40565d055667d32af75c2956193248aed5f90e27d9506
3	3	\\x9b9c0da423eab5b615a61d3b89c294a2a6e55bd3ac08df5e80b030a7e2d06113	\\x0dcc17032ee14fd53766cdfdceaa26dac7ee33cc8f6427a03811e98bb12626c19157122894f7fa7ded62cc9abca8dbd5988ba4958f9ccfeb2f10279ae1a87705
4	4	\\x8ffb341fcb24d4fd4af85f175b9907af82e103bff1bf79b13e8a2eb6a0ccc87b	\\x5032b36ad87acb5e4c3b54da09cd9b83e554ee5c03fff775ad1953378d1f6d08af066739b73b3900e6fffbbbe740459c81b9eb1079936268abc3798b7100b097
\.


--
-- Data for Name: refunds_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.refunds_default (refund_serial_id, coin_pub, deposit_serial_id, merchant_sig, rtransaction_id, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\xd5ed3b64fbbbc1e505af7c1e32a3231a4b4a42d59d35410dde1b312f9dbd3c7f	2	\\x4a49bdc76a002aae7fe1a8b91e27756ac719f2f201b03934edbdfe54212e37f0aaf24196f9e34bee3c28f0b7ea7a3657db2ef9b869104620029d1ac8e6c19405	1	6	0
\.


--
-- Data for Name: reserves_close_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.reserves_close_default (close_uuid, reserve_pub, execution_date, wtid, wire_target_h_payto, amount_val, amount_frac, closing_fee_val, closing_fee_frac) FROM stdin;
\.


--
-- Data for Name: reserves_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.reserves_default (reserve_uuid, reserve_pub, current_balance_val, current_balance_frac, purses_active, purses_allowed, max_age, expiration_date, gc_date) FROM stdin;
1	\\x8eb866d99c72c176795f3ff4d426a13aa9ec1d6cc7806c1c47f56b221ee486a3	0	1000000	0	0	120	1662916040000000	1881248842000000
5	\\x98b6258fcea7df4e5c872cebb14747c66ca0fbaff082039134aa78b6b17a4915	0	1000000	0	0	120	1662916047000000	1881248849000000
\.


--
-- Data for Name: reserves_in_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.reserves_in_default (reserve_in_serial_id, reserve_pub, wire_reference, credit_val, credit_frac, wire_source_h_payto, exchange_account_section, execution_date) FROM stdin;
1	\\x8eb866d99c72c176795f3ff4d426a13aa9ec1d6cc7806c1c47f56b221ee486a3	1	10	0	\\xcf7d58a62eb6ebc422b9cf888d44f71807c83539a83c0f30ac0f5f85f2fc6ea6	exchange-account-1	1660496840000000
5	\\x98b6258fcea7df4e5c872cebb14747c66ca0fbaff082039134aa78b6b17a4915	2	18	0	\\x9f728b310d2988d837a8a6a011cee25f6c81ce784beb52add7ffe41befe25f6c	exchange-account-1	1660496847000000
\.


--
-- Data for Name: reserves_out_by_reserve_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.reserves_out_by_reserve_default (reserve_uuid, h_blind_ev) FROM stdin;
1	\\xdd0caa270f634e24cc82e52368e6c9c18d1a76866fcfbe78748c0a501c264d0b59bc229cb5853ca661dd43793ec427152dee63cc42b3bd332f36805478fdd0bb
1	\\xb271dd901b9d1bfd863febb394166b005ba110b36b87204737d9e191be127f21d22f679fa83a4515c0198832421200ca7a345ccd8e0cb30441e663f86e51025f
1	\\x09510c7ce6742c9ab12a8a83507284d397f51fe8651e482a43063fb29aeb79c1caac4fbb6a3d4bfbf9aa006d79b393a5c55ab0f322ca20da260428bbf863f8df
1	\\xde1ba17261c4f06fa2ebcd004d7d46441e1d68e20cabd08f97a2d964de26e30b107bf2f4613489cdc70dfcdb1b272eec80093aeebf0f885789b935688dac3424
1	\\x70d66b8a89836fd85d19c3b15deba61fb6acbb97cbfe71cfdf35782b1968f4dd1d074fc2d8c1b04b3b0d2ee2d1e56480486d45e856fe538f37432732f11019ab
1	\\xf99ef428f633181c74140940bfabb33ff16d847111caebe6eb1a29e173417a1b7eb20fe50e43809f2199445036972d602af3d8b45d05e307a756fef782430c4b
1	\\x8ed08b669115ee376efdb4f5de3edf2f18275bdce58bfedb0b94ec2e3362b0eb4dbb15ab05fe735b958bc97f3e29ea2e33c71139c810e21118bbcf24c9837282
1	\\x6888160da643a29af35d075a6b0eaad97d1f20fdda79fcea64ba679e1909cbaabfff3efef55d66a76888ec72e04a3a7af640ec3afe502db8453d55b78b5d4c78
1	\\xf9541b6229b1e80e798c880611165e76d5a7a1c1d90596f22927e50ad4e137641e54797edb1a7660d2159ed216bb988fb5455f36860bda2067878c7c8dad34a9
1	\\x3e44530d991b5045eba8044e01afa884d08b37aa5ba7f53563a820e6eb2b9218c16964141dfd5e0c2e13f6cdb3c7032e0073f87641ed87b55e66bee95b60ed5d
1	\\x579c65fdfea1bcbdd7685abf2d7b014be9dd9f159417aa21457aea3ae77e3e5a7bc63b9ac84781d535412f5199bc8536675ea71818e4d1629de7f9b292e11e4e
1	\\x2c208f5170a396b88eab19d878be1b91fd20abf5ba10c551b3ecd4ab1f7af6dc5b892a61b036adc2a4422c2f18b869a528ba119cca811a425d8daa8dbf1ceb02
5	\\x8e8a1fc23da3669d1a9819b273c62d7eb97008b987a3032705b2a36af48ce32130269da963da01e12246a58836ffa2e7672fd390600f06ace7effd20c5d11dcf
5	\\xa504ce017512a0a2dab5ccece8867646b7282a2d3ceaae32398411351ce66b7b1cfbcc138595c429131a1efcd0ccf430c560d1e0d3faf53e82ceddca87fd6f50
5	\\xb37fa0e353a97ff1d752f98137424239c72146715b025487b5920319f81aa05f59bd3b9f62191f98e976588d5f552f6682b8fce3d8db2294fb20c2953ff10fb5
5	\\x33b597e200333e42644aed2431ad9f12ac59399aa62abc46502d4c6817f61bc1b97041988aa5f7b0bf62a0b40a9611d12712d5000aeaaf45efce1c32c9643360
5	\\xcdb8febef9048d9ce457a3ac3693f4d076ca321764568a2be20af21bdc22f75119881d7591f25e3c1fbc3681fadd1075f207f47780d6b2d6050939a0c22bf3de
5	\\x102ef24a5b799e646263b2fd54ec13da125d9d57b7b54895182774f276bebed9ecc3d187f242a46f5b3ea040591aaedcede234d13f86c1b1d998cfcfeb432340
5	\\x9237ad22b4481616f658a0d0e491a1f16218d35b9f6bdf86f7bfea92e96e47132c9464c693a13fac87ca390349a642e3bb36c19c15dcd425ee71011ca266de2c
5	\\x1dcc86fbc70898924864afbeffe2c0ed6e06f29ef143148c949f5c56130808d986602176856993d5a917e0291a002e13779baec3f77b279f71b2e37b42f1c04c
5	\\x86a87e3168bf8c6f4f6a7c574b7ed6d86a42cbd4b840aecb8ab185240a3a0268c7004b0207de1d5164cae198fde554ae8d6181e4fae0512c82bbe26c1397f0c2
5	\\x5faf7e8b44d43d0bbe2efbe30e35a1ef0b6643c918e22d34a62821f1083e52aa5d5b17465d9f3ef008dda7e90916e4a15c12a2c6c35002c64d13ae478d00fb41
5	\\x0db6373facd27a3a69133e58d73e1b6cf343a9064f6313e8d539dcdcbb909749841651883b9a804c75ad4dcd05fb96e771cc16fbb86dbdf47bdb0bf3a1fff325
5	\\xf43e9dbab9f9b84d4c47bc90d6e9e0eef3617d549379027518a3ed9b7d4d12f3052bca18354e68b43a5b6f22b8fde3345033e6e460e260775c5ad7aa935c3b6f
5	\\x2adfdd1460ebc66a41a330989e88c82422a4e5411cf65fd64b500962f2da465d1249a67cd93cd5495c03662fdc2985fa95ca18444e451d6a24313fdfd105cf09
5	\\xf440af64bc69bf12b12c105bde88c8a34a6a181400d30fabf1c22588e3d7bca1b9e971830860a94ae4cc1ecbe6ddfbc68ee5b93a9cab1b6dbdb1815b699e4486
\.


--
-- Data for Name: reserves_out_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.reserves_out_default (reserve_out_serial_id, h_blind_ev, denominations_serial, denom_sig, reserve_uuid, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\xdd0caa270f634e24cc82e52368e6c9c18d1a76866fcfbe78748c0a501c264d0b59bc229cb5853ca661dd43793ec427152dee63cc42b3bd332f36805478fdd0bb	298	\\x0000000100000001821f5d2ae00d465d21cd314253fe4c4d2eafa26134827138768086dccd611f877832646623763bc9ee4cd6d90cbe5d9fd7fbedb7ecf4d40dd5805b583b4b7e2a21f5a77f3df0a20d1d8e9af64d7624950427c905f170aa793dc91ced27cd79f22f75f019fd0af90824781ceafacab97bd2573e1b26febd933bc0a5ae63ec117c	1	\\xe578ee2b5313d5fc810eb1034f0fa441958608239a044be3bace2f7c86e773a92f82ba411640632057b51a612d95f8ad466a09c3215e9f7ea10681cbd85c6606	1660496842000000	8	5000000
2	\\xb271dd901b9d1bfd863febb394166b005ba110b36b87204737d9e191be127f21d22f679fa83a4515c0198832421200ca7a345ccd8e0cb30441e663f86e51025f	131	\\x000000010000000149f2210ef20dd077099e89f30f73a4f5a4d29505b75c0b01fea2847104dec81020e9ea54324f55d4309ca54cfd062a703b0b706ed7e8f7b137070b9ab2591df158e51ab0008f8411694024455a52d76709243693317bf5456a9070cb2b9c2cd06cd2093f62345ec6db5407a3fd45f610f064f8d8bf18ac375c1ff971037e88eb	1	\\x715843df7b20604457839f3ea6ee056df12adac8eebf7719d2b63dbaadab7793d661d558bd1039318f1982a011cea43d77e62ec675a402c35f1f51aebe307b02	1660496842000000	1	2000000
3	\\x09510c7ce6742c9ab12a8a83507284d397f51fe8651e482a43063fb29aeb79c1caac4fbb6a3d4bfbf9aa006d79b393a5c55ab0f322ca20da260428bbf863f8df	373	\\x00000001000000019879a282e894d1988a1eff73159c9bb740d020d040dd8b6be6313498bcf9c4776d90247959df8e998dda9c57395a8a264acd7d0a83e9513fd0bb956ab2335e05a22869b9b820cb5f054d40acafde39caf1e576ee9035f357b4dcec63c90226adbe55a3022b6ee618357880de7959dfe06996568352ca68f5c388615297fe512a	1	\\x7b61ea7e37ea6202c4ab5297aff972e938483bbf950c54385e41ceca8049c11250aebc290d396e989952bd5fefb6973d5fe950b195ff5968081c8f358e45b304	1660496842000000	0	11000000
4	\\xde1ba17261c4f06fa2ebcd004d7d46441e1d68e20cabd08f97a2d964de26e30b107bf2f4613489cdc70dfcdb1b272eec80093aeebf0f885789b935688dac3424	373	\\x000000010000000172c0c905c61db4e9eda8a629cfc44a5a61175c4d66164827f41a0ae6121d2949355efb4db49dcb5546c6743d6c66df20828a75525529d05ffdcbb502c6c402c01aa098f3148594bc21bddc4c6b6a2bd0d218fffbffa19a00a0322583b6837e00b0c2d88fc9e94e5f8685308a001efdda59e50334956845e29038f6d90467508a	1	\\xe7dbfb0126b236a97955ca2c5efc830e0f377afaf4efda4f08e2cd9a9db256b2052a8b3e9ab824b53dad65296c0633e2d9938d9e5af48352fc3b78541db46e02	1660496842000000	0	11000000
5	\\x70d66b8a89836fd85d19c3b15deba61fb6acbb97cbfe71cfdf35782b1968f4dd1d074fc2d8c1b04b3b0d2ee2d1e56480486d45e856fe538f37432732f11019ab	373	\\x000000010000000184c214a972c21cdbffce2aeea3440602dcc1583c654c3fc4b23aac5a2f1a99c05c74b4bca9634379f43b70267072bb9ef6edef007d3e1009ef3e48b0c3baeff009f9bda682e28bc03265921594a58e2ff3c41cfdf8719c2f267eabf0638175b64c96d9fd758032bf02b059a7f4a24cef1f9ba1bfd0a7f85948aa161f47c0c73b	1	\\x556c467e454b720be33b2045ce9ba40c8bc49ab1b91dfd92e7f84b473a15423c5bd3a23da66a054ab5e18f39411d3933bac3a3b087470a131dc652b03b449c0c	1660496842000000	0	11000000
6	\\xf99ef428f633181c74140940bfabb33ff16d847111caebe6eb1a29e173417a1b7eb20fe50e43809f2199445036972d602af3d8b45d05e307a756fef782430c4b	373	\\x0000000100000001c4a4b4846893a098b1d1d133361e21206a935505d258196cb57654c3e2f9981d903afd5b21346459cadd9bd168eba7e54533914a91ab1ae4013912538d6767f47771e405efaa90caa3709207b354b55f5ceea014b80fc9596b7b2a7d7a9dc838c89b69ca2734763a0f35e1d8f5ee92b8d328f8017e25236881eeaf0f8e29befe	1	\\x9859e044eda2c111c5011e39ef21f9599388e49deb101eb2fcec875d82aead9d0653fd7c5ef056723940ec5c69d753d20056f7740e4363777f44e7812890ea06	1660496842000000	0	11000000
7	\\x8ed08b669115ee376efdb4f5de3edf2f18275bdce58bfedb0b94ec2e3362b0eb4dbb15ab05fe735b958bc97f3e29ea2e33c71139c810e21118bbcf24c9837282	373	\\x00000001000000011debc17b45c0b9b8ed41b1c0d1439af4430a6841130416f1fe893307d55653f97af417bdeede4b82c37f8e0e99273b4abf667f9f3b69f61bc4c40af59c841fdcb5d78f66918db5f02b1c78f6d0bdc2ff4f2890d42a16f5894923c81ed0654acf37ed286ceacfe2eec9d32a61c05f5eeeb1780dd413bc0c47445cb7b92a92340b	1	\\xf3028b8a8375bc7caedeb733f9ea9dcf36b7a508f812fb6b4585e177308620a3d12bb9a4b0a81efd70764c926c91670c0b2000c55f64dcb8a8c2cec887b5b602	1660496842000000	0	11000000
8	\\x6888160da643a29af35d075a6b0eaad97d1f20fdda79fcea64ba679e1909cbaabfff3efef55d66a76888ec72e04a3a7af640ec3afe502db8453d55b78b5d4c78	373	\\x000000010000000127ef7e86ce504e9e95efbebb49e7483405da2c04f868edcf3dea448f7cf17ec948d4e4e80586c22f4bf5bc6e02cd7e9f08c71add68449bf1a27fd84046ce0a92a942272c8760d1a07f3849867d37684735a54c28c4a5754682acc0029fd5e478deaf1ec57acd5277f337c87e80ad0a1e587f6303a7eaa823e966369e8f4b4be9	1	\\x8c95d611181b08c1bdd65651f987fddefc7e73b8528c3aa3a18f2ce6268fe9f28f00e737e0a07363ce884fae1b4e88230b0e8771811b3508e3bee4018b3c0305	1660496842000000	0	11000000
9	\\xf9541b6229b1e80e798c880611165e76d5a7a1c1d90596f22927e50ad4e137641e54797edb1a7660d2159ed216bb988fb5455f36860bda2067878c7c8dad34a9	373	\\x000000010000000136ff44f64e9eac4b96988475022aec9df24a7ca7556d293393504e8dbfca54a7f366e8a18479585196264b7eb6184efd42a49ff9d573d2f4325f86ded0208731232e471f7cc85b36f50cf1cce29b433033289382e3a7b70f4daa369db390e574fb807d58dac5676a78e54f1f1167b2de415185b4056e9fae2a33aa20581387b5	1	\\xe33d345f01bfd8871712ea6197a23b87bd0154c51e75e154d899072a308e8d68e308fe52319882dc653ea8ed98715f83a57f68175e08caee763010f21f3b840d	1660496842000000	0	11000000
10	\\x3e44530d991b5045eba8044e01afa884d08b37aa5ba7f53563a820e6eb2b9218c16964141dfd5e0c2e13f6cdb3c7032e0073f87641ed87b55e66bee95b60ed5d	373	\\x00000001000000010bde6e2b7ff6da0f36d564f8bbe45d0f072c75bd3f425f306d7a3f5847e13537c0144c1243735df8c7228cfc44d96be12279b0d21ec0fe37c52b871a999a059b43f1255535022921d33008303ea434a72e2a62a5f294199b505ca5dc89b0b4016675b39bf8ee91af3baf2df8f6a2fdcf89a75e98b634f50d983201ff10d8b940	1	\\x574df4ff3ecfb081d249d46099baf73cf7ebe0d2a64a02f2df40c4f6b7c0866e2ee19f1b1cde50a2fc2498584c8c991b30df23190d3c9514970c86a619145d00	1660496842000000	0	11000000
11	\\x579c65fdfea1bcbdd7685abf2d7b014be9dd9f159417aa21457aea3ae77e3e5a7bc63b9ac84781d535412f5199bc8536675ea71818e4d1629de7f9b292e11e4e	354	\\x0000000100000001be726fe905ee0258e188bc567f99344e0866fe0cf336b35e7ea7194b60089b6a9d4012acb7d6333c5feba4b9f7b924cb06b500807c1c637858553b96e2ada55d3b632b488953783edbbecefa9ec0b29fe7d3a711296f139c419bddd2ed6f85c64299e1f6c7810730378669c7faf15f4270f13fbcb8a1a74bf44f4b4dc6189401	1	\\x8caf5c0dabdcb277189807359ee488b1a382f775f01308e001696e789832c3984e7de89f639b21c993fd2356386357f1fedae4e001b2a8035b1d5de492db8109	1660496842000000	0	2000000
12	\\x2c208f5170a396b88eab19d878be1b91fd20abf5ba10c551b3ecd4ab1f7af6dc5b892a61b036adc2a4422c2f18b869a528ba119cca811a425d8daa8dbf1ceb02	354	\\x0000000100000001c1f333cf0f9a87868c1105c243680b294164092c6fc29d9a92b37108beb612cd659f61baa30601999fe19fecc9c7dc90f4a295a23eee46018c59f2e80df71aba7e409a0b992137d326b2b04a6bbc91a192c6b7789b220eb2b8c05b0f3f193b66a61b37bd99e6c0a256dfdf4ad44da0bbc2075a1aab037642ba07fa3450e51497	1	\\x9238c82aea5e140d826ddd584735452f0e59af352629b58f616d5c67d272a14b8968abd2993165de306cbe2687e75087e494092ea9e9b6068e96b8358f9acd0f	1660496842000000	0	2000000
13	\\x8e8a1fc23da3669d1a9819b273c62d7eb97008b987a3032705b2a36af48ce32130269da963da01e12246a58836ffa2e7672fd390600f06ace7effd20c5d11dcf	46	\\x0000000100000001047d8dcb428d3458230d5f99010bfaf8b7e6fc012784c57b2de657f2a812c1209afb6b5e7c8f183792d6350b058058653c9cd08876f66b476286448ef07b29400b9ee769fc6a7f3d2ab3a159dcf3b506ed4ba2b232f2445c8d9ef83184d4f5f15de7ab6cf803a7d7c90e349a2f11121c4083d5ccc84c4312fa16f5dd713e69c8	5	\\x4499769f6f0d85dc2868d2e9b16cfc7a03902bd9422a518a32e98bc3db8268ee8d1acebcc4e72f7a0f86b31b7698c72bcf105ae762596e7ad96a3fc1d1ecf700	1660496848000000	10	1000000
14	\\xa504ce017512a0a2dab5ccece8867646b7282a2d3ceaae32398411351ce66b7b1cfbcc138595c429131a1efcd0ccf430c560d1e0d3faf53e82ceddca87fd6f50	132	\\x000000010000000188ef727d3271531143b2aad00838099e27e2ce8b91be54a6011142e717ae171d86d0d8a0fe419e82c6497e0a3a7753d196b73d6a608e906c847d6b4b29378c1e94efe92efaa030ab0eadb6bd8976ac6752c436b9b806fcd48c80bb5ea9f1d3a6e5f669d430811e7d448f1e296de2c48f0c9228b00b871a4529ec5a6e0cc293cb	5	\\x8b454bcadcbbf527ac1317158eb59b074ef84b70383bae917e6226d3e36fe89c0309f602dd06cb9f2516e0a0ef808b72ea4cd422cd388797a80d00a919f44c0f	1660496848000000	5	1000000
15	\\xb37fa0e353a97ff1d752f98137424239c72146715b025487b5920319f81aa05f59bd3b9f62191f98e976588d5f552f6682b8fce3d8db2294fb20c2953ff10fb5	153	\\x00000001000000016fb198f5eff3b4b1dabc8dc5e338de5e1d59e2318ed52ba41bb5418ad9224d5a27c0f36eb8e1aa4af150f3f01da95c10cd6b3d04a6b6a72aa3f64893a75594cbc7b645d7cabd55c281b15e5ac3864fcf8f3f6dad6260a44be0d19a361190e0da40586f01e8a5e2fd7237b5618f7de1ea5c25aa1e6c86891a43afc1d4ca2900	5	\\x5109edc77f43292ad195c0219b0d767ab5d28e0b849420ce5df08fa0a984516f006ae2051ce24b63aa82cbe85282835442d1a2bc551505451b2dd3fbe5ab4805	1660496848000000	2	3000000
16	\\x33b597e200333e42644aed2431ad9f12ac59399aa62abc46502d4c6817f61bc1b97041988aa5f7b0bf62a0b40a9611d12712d5000aeaaf45efce1c32c9643360	373	\\x0000000100000001277d0efb27500573df68835754fb7fa5d749db7d90dd0e07a09a84392e37bb981691d2914b51bca1fced28a18c9820b0692ace91fec0fcb1d4df6ffcf4e2cb1106f8be4f78d9cd7079e2414ba1bbcfd19ee7d054213d8c79a1efcdb511088363ac333987da956877c0d9fd5d1e305fd6daa2cc3aeabbc38424c6f6babfbf9137	5	\\x01a817d575a2cfbb20a5a44afbdf9bfc40be5a16f5733438ac4013ad19fd56bf9658c7a2e7679d500fb2a6318db1fe7e875d4963cf5d3f0d1bf97f85669ba70e	1660496848000000	0	11000000
17	\\xcdb8febef9048d9ce457a3ac3693f4d076ca321764568a2be20af21bdc22f75119881d7591f25e3c1fbc3681fadd1075f207f47780d6b2d6050939a0c22bf3de	373	\\x00000001000000010d1a8c39630995ddf2904ffda0d4e64e54790a4ca109dba70b1afb3fa33a17cb3a48504c90606e65fd92a7368891febd1f003e2c77245f1f70f0505589fb7a1d224b3672c0d9c96a9ce7a2c43a180891068ac5ef1a811702084c782720191560e8d8b8ecd023062348c33a9d43237cfe0c78c543321fb2ddcad8008b1729c870	5	\\x10e4b46fda9520adc8a974dc9ad503b8e83e11a5975bbe7558e57f9cb7881148a949357a72cd742884fe15e451f4c3175a29e3b438c16597aff9f12fd9c9ca08	1660496848000000	0	11000000
18	\\x102ef24a5b799e646263b2fd54ec13da125d9d57b7b54895182774f276bebed9ecc3d187f242a46f5b3ea040591aaedcede234d13f86c1b1d998cfcfeb432340	373	\\x000000010000000127863d21c8c7838961a1cdce3f9809bbb4905a799d4c786547b8f37162596b5321a07d72aacdd28ab3d4923359aefc351124ebdc1202f80295c13e0f41cd82f29b8697c5562f493a22ba45f511b85f8a9dc0edf04bde79f5a74889e1a82ac96d5385921f8125188bc0c72d68ab1b8f96fea842bf5fc3cd3236f948114676f55c	5	\\xfcac89c82b75691aa1b5412aa98cc802e03840580a171cbbb7398e8a1e5cef8b93f3afacfcfa672948888d3a86570ba5434dd48ff4bdaa8626b4321e81fe9e0d	1660496848000000	0	11000000
19	\\x9237ad22b4481616f658a0d0e491a1f16218d35b9f6bdf86f7bfea92e96e47132c9464c693a13fac87ca390349a642e3bb36c19c15dcd425ee71011ca266de2c	373	\\x000000010000000159bfb1c9e549120ec5040799a814d1f2e0a04cc19230ac20a39ac0279551eb613ce076ecee5a38a0fe6b21931d19e6786ad141ff54974640497b697e3f90ee655f8a81567adc6ceb4f874cf7abc54cd926b43fc02a03995f9308cdd87a1c062e8475e9115d8b4348618f79d9c014a5eaa659d8b3257fddde11dd7345a1df3c21	5	\\x6dbb61fe8cc6f656d1cbc65692e03fb67d6d0d266153eedaa47ef102f1373443e133b33544c828e5fc0d001cdd54ed6066507a3189ac5192f76968a3c364420c	1660496848000000	0	11000000
20	\\x1dcc86fbc70898924864afbeffe2c0ed6e06f29ef143148c949f5c56130808d986602176856993d5a917e0291a002e13779baec3f77b279f71b2e37b42f1c04c	373	\\x0000000100000001034b13f96b409aa77dc04be57712f19c744258b97c01d3875221717ec296d680f3bcc0ec43411cd53de9c06e46be4f03462f1e0f9a8a735ec7be18f829a5c072d19c57a9c8d531482648e211666c09ef658b72e208d298dc086b69396b47abd9780a4376cc61915f75ee55f11325e0addd3ca1b13ba82c858228685b6ed77075	5	\\xddfbdda4b917f807512a46d39ba5414028acdf55186f2f3f30d3ff7cf2961774475968b609c262a24ffee90b719e87d9244988cfd0ae5c52299276b0eae8d509	1660496848000000	0	11000000
21	\\x86a87e3168bf8c6f4f6a7c574b7ed6d86a42cbd4b840aecb8ab185240a3a0268c7004b0207de1d5164cae198fde554ae8d6181e4fae0512c82bbe26c1397f0c2	373	\\x000000010000000175edd598269a646d25f90b835f1d43e7df9282a0a6e986f4b3f80d3f4c16d41729d5ab29a4da91cc0271851faacf2efc68073a33d9722b76dc9b299135625ce4275903e4196f59ed3d34e07a410e1049dccdf69196e4bb07c7b88d611dcf2eb580f4dd1262af149a9b107a7904b0668fbeaadec0248ccb66a80cad8a90523c97	5	\\xf2dc18fc83ef597ecc8e0604383b9354205c2652c5c4689957b4101efe3dfecdceccb968c80c9289b0d5d1dd18fd81bb86f4ab5e4e6cd9025220ecf07d19fc0b	1660496849000000	0	11000000
22	\\x5faf7e8b44d43d0bbe2efbe30e35a1ef0b6643c918e22d34a62821f1083e52aa5d5b17465d9f3ef008dda7e90916e4a15c12a2c6c35002c64d13ae478d00fb41	373	\\x00000001000000012b126a55fb6b728b20833087e1d22c3d9ddf1cd2368ca11b5e2fcb65c9fb251f5386c3003d79f5466c92bbf25847a5594e8029a3197908833d91f3750ecdad617b350f0ccc8a72b987da571adf1c3813dfe5fca14f74d4efb9fdd7198bd672f18dab2807c4f247d8a3786ea0bcbaccfe064f7bca48818f7e29b63582d9cd1bcc	5	\\xf68d3d31ab1806cbf461ca69e79e649d37278bab615a7221af850094aeb1e84d7df2be33570ecb9b13a5b5f979b22c95c2ca7ab19696663ea7a81005f2cade02	1660496849000000	0	11000000
23	\\x0db6373facd27a3a69133e58d73e1b6cf343a9064f6313e8d539dcdcbb909749841651883b9a804c75ad4dcd05fb96e771cc16fbb86dbdf47bdb0bf3a1fff325	373	\\x0000000100000001c870ecdb90091561762286f88214824df6190811adb1afb5ce7fd8aff2f3e575765162b77567b1475588b156837bb7af78752ca24d507f619f48c0305eaef0739566aafe17494e9015b4fd1e117c3313f068ae3e6eea7236965c798c511f5eac2a3f46b7f7e685bf7bac1333168a5b5d2eaa47ca94a72f8d9be456ac7599c39e	5	\\x26a910be3867dcd6f7ae99e5d6f054efdcd87d93a16bcda52097dcbb31b81f3367a5e02c7bfbc822338d89049a32c476689b4a652b00a129cc4016ea43068f03	1660496849000000	0	11000000
24	\\xf43e9dbab9f9b84d4c47bc90d6e9e0eef3617d549379027518a3ed9b7d4d12f3052bca18354e68b43a5b6f22b8fde3345033e6e460e260775c5ad7aa935c3b6f	354	\\x000000010000000127cd8e9d24394663d73f361d5ef30528d3f1774ca69b54eae8abf5a70a30debf4e7586256fbc25872b75acbe5eb4f875c355c913947355bb1edd968de16e8c03867fbbaf75071af99a1bfa090881384fd3ef3387c627c9b2bed65728475eeffba4ce1c2494786ed9d1b6a0fa1c04a1620856636e253e9b027f5f69fa4873053f	5	\\x787661aac13efdf5b725532658a8e2a91a055d0f45b10c22ca19877344f942737bc1d2d1912fa1dae8a770ad00d1e804a2c469a283d32b07992b6b656cfddf0d	1660496849000000	0	2000000
25	\\x2adfdd1460ebc66a41a330989e88c82422a4e5411cf65fd64b500962f2da465d1249a67cd93cd5495c03662fdc2985fa95ca18444e451d6a24313fdfd105cf09	354	\\x000000010000000162c90cd16656c6cdd4b170e44988be21ac4bd3873eb810d1b8d12213633d216580249d90096bf73f45e61374973c809c4e04084dbc27cf06711ea56d701d30d3b13d5b3dab7742e8cc674fb8c93db8ce32c541cb1cf45fb4f832ad2383dfcc42efb32b3181b15f44862f6529198b17e8a25761fdafc80a10a381af140dbc9082	5	\\xb06d5005c0a53c7d01b3cafbef61e334a2b9295592f4f1ffd4a3919a7549654552d198d339f7198ae03797f50224647284fde136138468c5f103444575418e0b	1660496849000000	0	2000000
26	\\xf440af64bc69bf12b12c105bde88c8a34a6a181400d30fabf1c22588e3d7bca1b9e971830860a94ae4cc1ecbe6ddfbc68ee5b93a9cab1b6dbdb1815b699e4486	354	\\x00000001000000014f6faf5966389ab119ba12390146da655bf5e2bfc90b51fe5c04ed50f92ee08b8348e331edb11079b596fbf407f9aa84103f4459c81ab10edc251cf47626ddad37940c882d6e81be8ccdee3e6059701bd53a1bd3ab406f1319b8f684fcb22a38c965d1ec011dcafd5605895c33066aec3dea3952949e2c4e004ec54eeb421701	5	\\x03a477d47106452a78e5fab0c4991614c8b37199b6fa310e4a190e097111003c137fb3f5127b16e64e897b3e9dbd3cb4b19542f7a62b5ce886a4cb4e7a231500	1660496849000000	0	2000000
\.


--
-- Data for Name: revolving_work_shards; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.revolving_work_shards (shard_serial_id, last_attempt, start_row, end_row, active, job_name) FROM stdin;
\.


--
-- Data for Name: signkey_revocations; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.signkey_revocations (signkey_revocations_serial_id, esk_serial, master_sig) FROM stdin;
\.


--
-- Data for Name: wad_in_entries_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.wad_in_entries_default (wad_in_entry_serial_id, wad_in_serial_id, reserve_pub, purse_pub, h_contract, purse_expiration, merge_timestamp, amount_with_fee_val, amount_with_fee_frac, wad_fee_val, wad_fee_frac, deposit_fees_val, deposit_fees_frac, reserve_sig, purse_sig) FROM stdin;
\.


--
-- Data for Name: wad_out_entries_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.wad_out_entries_default (wad_out_entry_serial_id, wad_out_serial_id, reserve_pub, purse_pub, h_contract, purse_expiration, merge_timestamp, amount_with_fee_val, amount_with_fee_frac, wad_fee_val, wad_fee_frac, deposit_fees_val, deposit_fees_frac, reserve_sig, purse_sig) FROM stdin;
\.


--
-- Data for Name: wads_in_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.wads_in_default (wad_in_serial_id, wad_id, origin_exchange_url, amount_val, amount_frac, arrival_time) FROM stdin;
\.


--
-- Data for Name: wads_out_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.wads_out_default (wad_out_serial_id, wad_id, partner_serial_id, amount_val, amount_frac, execution_time) FROM stdin;
\.


--
-- Data for Name: wire_accounts; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.wire_accounts (payto_uri, master_sig, is_active, last_change) FROM stdin;
payto://iban/SANDBOXX/DE514871?receiver-name=Exchange+Company	\\xa58cd05de445d0845491b3270ec08103b6efdd7312e7dfc7c446b1c1b387e2f45334edb1df0f445e618d011796012b1e8925d5582428d992b8860fcbd3b2a10a	t	1660496833000000
\.


--
-- Data for Name: wire_fee; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.wire_fee (wire_fee_serial, wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, wad_fee_val, wad_fee_frac, master_sig) FROM stdin;
1	iban	1640995200000000	1672531200000000	0	7000000	0	1000000	0	1000000	\\xd824128f217ac66458b67092e474d5b6023730070bb6abac51d180fdb4988c3e5972bb26b294283799eacb0384410691d37cf8ae97e84353e813ef9a5ee9dc08
\.


--
-- Data for Name: wire_out_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.wire_out_default (wireout_uuid, execution_date, wtid_raw, wire_target_h_payto, exchange_account_section, amount_val, amount_frac) FROM stdin;
\.


--
-- Data for Name: wire_targets_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.wire_targets_default (wire_target_serial_id, wire_target_h_payto, payto_uri) FROM stdin;
1	\\xcf7d58a62eb6ebc422b9cf888d44f71807c83539a83c0f30ac0f5f85f2fc6ea6	payto://iban/SANDBOXX/DE729925?receiver-name=Name+unknown
4	\\xd31e3f48cb5318906dbbb7948326362f41604c7a728323230ae82aa995f27400	payto://iban/SANDBOXX/DE474361?receiver-name=Merchant43
6	\\x9f728b310d2988d837a8a6a011cee25f6c81ce784beb52add7ffe41befe25f6c	payto://iban/SANDBOXX/DE729731?receiver-name=Name+unknown
\.


--
-- Data for Name: work_shards; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.work_shards (shard_serial_id, last_attempt, start_row, end_row, completed, job_name) FROM stdin;
1	0	0	1024	f	wirewatch-exchange-account-1
\.


--
-- Data for Name: merchant_accounts; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_accounts (account_serial, merchant_serial, h_wire, salt, payto_uri, active) FROM stdin;
1	1	\\x61c651ac7705133762775ebf7c518fbd11cadb136377114a287a40c62b9bf52677df4e50f3ad1b95fc0e7f34dbbc0cda4ac10231fb2f5a36be3cf4085626b4d1	\\x45018ce122b6819ad72419be5f5c791c	payto://iban/SANDBOXX/DE474361?receiver-name=Merchant43	t
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_contract_terms (order_serial, merchant_serial, order_id, contract_terms, h_contract_terms, creation_time, pay_deadline, refund_deadline, paid, wired, fulfillment_url, session_id, claim_token) FROM stdin;
1	1	2022.226-038BYQ4ZX5FTW	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f73223a313636303439373734327d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313636303439373734327d2c2270726f6475637473223a5b5d2c22685f77697265223a224337333533423351304d394b45524b5142545a51524d4346514d38574e50524b43445648324a48384639304343415756594d4b3746515445413353545436574e5a47373759443656514736444d4a50313038525a5042545436545a335358303841524b42394d38222c22776972655f6d6574686f64223a226962616e222c226f726465725f6964223a22323032322e3232362d303338425951345a5835465457222c2274696d657374616d70223a7b22745f73223a313636303439363834327d2c227061795f646561646c696e65223a7b22745f73223a313636303530303434327d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2238505a30514338395952454146423954414d32534b384e5241394732524d584134513831344e3052583359384451363448304730227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a2247584d57535734594854484d5a4736354439474639563450394b544746413145435747445a365a45524a39453952474b38434e47222c226e6f6e6365223a2236323333455244574659334b364e50455959303541414a39454e324e3732334b4744325934354e44534d53305142484138464830227d	\\x597874d0e5022cc5dbd261010ade882413c2ef9e8c18b4a80f5a5bba5ca5309b91e2b0f7a4a588baea19d589facc2dd755012720592e33faba0ef0ec0edc6f7c	1660496842000000	1660500442000000	1660497742000000	t	f	taler://fulfillment-success/thx		\\x55d763e6e8800ea4f744c64fdd18c8ed
2	1	2022.226-0049MDZV0K6SP	\\x7b22616d6f756e74223a22544553544b55444f533a37222c2273756d6d617279223a226f7264657220746861742077696c6c20626520726566756e646564222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f73223a313636303439373734397d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313636303439373734397d2c2270726f6475637473223a5b5d2c22685f77697265223a224337333533423351304d394b45524b5142545a51524d4346514d38574e50524b43445648324a48384639304343415756594d4b3746515445413353545436574e5a47373759443656514736444d4a50313038525a5042545436545a335358303841524b42394d38222c22776972655f6d6574686f64223a226962616e222c226f726465725f6964223a22323032322e3232362d303034394d445a56304b365350222c2274696d657374616d70223a7b22745f73223a313636303439363834397d2c227061795f646561646c696e65223a7b22745f73223a313636303530303434397d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2238505a30514338395952454146423954414d32534b384e5241394732524d584134513831344e3052583359384451363448304730227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a2247584d57535734594854484d5a4736354439474639563450394b544746413145435747445a365a45524a39453952474b38434e47222c226e6f6e6365223a22564e33304636374b534d59574b4b5843374448324a3441364d474143584d39433030463152314a4a545658414b53424a41304a30227d	\\xa6eebd77eb7679e3100e6206fec477488677a217826f47d1f22434f946e5e504ffaaf24c1a9a617a816d8a579678c0f420d4a6cbcb8510623219f37685caa2ad	1660496849000000	1660500449000000	1660497749000000	t	f	taler://fulfillment-success/thx		\\xd1435cc3c73c3e864c0119c1fb21a31e
3	1	2022.226-01SZE8BWQ7XH0	\\x7b22616d6f756e74223a22544553544b55444f533a33222c2273756d6d617279223a227061796d656e7420616674657220726566756e64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f73223a313636303439373735357d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313636303439373735357d2c2270726f6475637473223a5b5d2c22685f77697265223a224337333533423351304d394b45524b5142545a51524d4346514d38574e50524b43445648324a48384639304343415756594d4b3746515445413353545436574e5a47373759443656514736444d4a50313038525a5042545436545a335358303841524b42394d38222c22776972655f6d6574686f64223a226962616e222c226f726465725f6964223a22323032322e3232362d3031535a453842575137584830222c2274696d657374616d70223a7b22745f73223a313636303439363835357d2c227061795f646561646c696e65223a7b22745f73223a313636303530303435357d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2238505a30514338395952454146423954414d32534b384e5241394732524d584134513831344e3052583359384451363448304730227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a2247584d57535734594854484d5a4736354439474639563450394b544746413145435747445a365a45524a39453952474b38434e47222c226e6f6e6365223a22454d4244455251394d44305a50415734363751563243313959364a43573652385157325444525141334554365452325646414d30227d	\\xd720212ae0eb064129dc42076d7fe438c1c9faa21d7f3d713836ca6e76af7109115b4db437fbfb39a6a3d6e47fa5f6197e4f5c97a42ae7bcf16df9357b735ce1	1660496855000000	1660500455000000	1660497755000000	t	f	taler://fulfillment-success/thx		\\x97954a47bcb1e9a58fcdbc5539ab9ae5
\.


--
-- Data for Name: merchant_deposit_to_transfer; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_deposit_to_transfer (deposit_serial, coin_contribution_value_val, coin_contribution_value_frac, credit_serial, execution_time, signkey_serial, exchange_sig) FROM stdin;
\.


--
-- Data for Name: merchant_deposits; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_deposits (deposit_serial, order_serial, deposit_timestamp, coin_pub, exchange_url, amount_with_fee_val, amount_with_fee_frac, deposit_fee_val, deposit_fee_frac, refund_fee_val, refund_fee_frac, wire_fee_val, wire_fee_frac, signkey_serial, exchange_sig, account_serial) FROM stdin;
1	1	1660496844000000	\\x783eaae82ec2154e5c9ad14d3e2ce7a01764390e6aabe3668160cf0b03553495	http://localhost:8081/	4	0	0	2000000	0	4000000	0	7000000	3	\\x9d6c8ab33566c4587d7ea9f5b5d921b78b0a6f1ee72fc66ea91542c804d8dbb5cf7150bb011c8db5b41db0e4b5d0591148823c736e98dc33adfcf98f51ae0e00	1
2	2	1660496851000000	\\xd5ed3b64fbbbc1e505af7c1e32a3231a4b4a42d59d35410dde1b312f9dbd3c7f	http://localhost:8081/	7	0	0	1000000	0	1000000	0	7000000	3	\\x13f0cc7c1370920cfe1daa6a011210568ad8cb75868b3bfa59fe4ed8aa5945d9a037b3c29ad2638c0469acd2d69601196c611cb7de8c48c0e1e51e13ce387c06	1
3	3	1660496857000000	\\x92203c16ba68b4a4f2ba445d68b1e3375b5411e0eedcab31f76700e55c8a2039	http://localhost:8081/	3	0	0	1000000	0	1000000	0	7000000	3	\\xf34e511fa0f13ba105585d1c295e2bc83315fa3ef66d1d9e7db038517c3b102db40a985209c0c8d00bb81a4fea262afc4e477df1ebb4c71a84c07399c7f1860d	1
\.


--
-- Data for Name: merchant_exchange_signing_keys; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_exchange_signing_keys (signkey_serial, master_pub, exchange_pub, start_date, expire_date, end_date, master_sig) FROM stdin;
1	\\x45be0bb109f61ca7ad3a550599a2b852602c53aa25d0125418e8fc86dcc48820	\\xc0bf62b780d51bb74597af05f39b95fefc3e281ce681e4eb8b6035c26eb7e04a	1682268727000000	1689526327000000	1691945527000000	\\xa555095a294fc21b21559730ed61809c3cf31d632a77b2c72d79a93792e4e025379efcec3651a51b542dc29b24063aad2fa11a85e7308a2493a26e9e4285bc01
2	\\x45be0bb109f61ca7ad3a550599a2b852602c53aa25d0125418e8fc86dcc48820	\\x530b014fb8e51f8b5479bda462c77f8d728ef55b78331f3303169f4de759bf7f	1667754127000000	1675011727000000	1677430927000000	\\x1a2043536b13c444ddaccd7fae17823177d4f9833320cf8a5c7153f8dfd55546ae14d3cb216afb0ddacd4ce92e02dbe3c46829013e95c5f839820793e231fa0e
3	\\x45be0bb109f61ca7ad3a550599a2b852602c53aa25d0125418e8fc86dcc48820	\\xfbb791f7723feb8207efda8c8b03f95c21a2339ea9e29c7c4f68e479c92c4c44	1660496827000000	1667754427000000	1670173627000000	\\xff1127197e35278affc4c1b867ef654e94ed4911247b52ab5369244e60d0051b962f51e45572dc94fea905e23f9be6ef421fb106adeb27c3d60b42b82b24960b
4	\\x45be0bb109f61ca7ad3a550599a2b852602c53aa25d0125418e8fc86dcc48820	\\xdd1bb80756046ddcd1edcbf53ddd3f8335b0847d430c43efc23d6d22a4695ef7	1675011427000000	1682269027000000	1684688227000000	\\x152f2fa56bab6c4407575cab1f65c8b96de38f6e75ef16d84e9813a9fb86ad553f60bd895cde8d083a50dd4515e0ef18dd929ffbda34fa000e1b04449b13220e
5	\\x45be0bb109f61ca7ad3a550599a2b852602c53aa25d0125418e8fc86dcc48820	\\x9e75a33ecba1645bb55f4935584a711114b08b54a9634d07dce5c6ec95a6cc8a	1689526027000000	1696783627000000	1699202827000000	\\x0912447e113f21ddbddc5c8abfce22770689b3026b7f8d386d68a59d78375c28d407cbf0ce23d0622ce202bdd8ab2e8aa6d4a43f32f66df5e08eb1140fbaa10d
\.


--
-- Data for Name: merchant_exchange_wire_fees; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_exchange_wire_fees (wirefee_serial, master_pub, h_wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, wad_fee_val, wad_fee_frac, master_sig) FROM stdin;
1	\\x45be0bb109f61ca7ad3a550599a2b852602c53aa25d0125418e8fc86dcc48820	\\x21e4a5e9d5d17432fa0b1f7a02f8047c7634c1053d6aa1f6456ac134caa8bbf3da7776a78f85636af980472afd166b4edad654979a89d92c49a4ba992a7e3571	1640995200000000	1672531200000000	0	7000000	0	1000000	0	1000000	\\xd824128f217ac66458b67092e474d5b6023730070bb6abac51d180fdb4988c3e5972bb26b294283799eacb0384410691d37cf8ae97e84353e813ef9a5ee9dc08
\.


--
-- Data for Name: merchant_instances; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_instances (merchant_serial, merchant_pub, auth_hash, auth_salt, merchant_id, merchant_name, address, jurisdiction, default_max_deposit_fee_val, default_max_deposit_fee_frac, default_max_wire_fee_val, default_max_wire_fee_frac, default_wire_fee_amortization, default_wire_transfer_delay, default_pay_delay, website, email, logo) FROM stdin;
1	\\x8769ccf09e8ea34fc0c56a60f4ec964cf507a82e6720df9beec492e4e213432b	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x0000000000000000000000000000000000000000000000000000000000000000	default	default	\\x7b7d	\\x7b7d	1	0	1	0	1	3600000000	3600000000	\N	\N	\N
\.


--
-- Data for Name: merchant_inventory; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_inventory (product_serial, merchant_serial, product_id, description, description_i18n, unit, image, taxes, price_val, price_frac, total_stock, total_sold, total_lost, address, next_restock, minimum_age) FROM stdin;
\.


--
-- Data for Name: merchant_inventory_locks; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_inventory_locks (product_serial, lock_uuid, total_locked, expiration) FROM stdin;
\.


--
-- Data for Name: merchant_keys; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_keys (merchant_priv, merchant_serial) FROM stdin;
\\x88719a7d63db856cb8ab97696b77e6511b3acab1cc73092b0fad3384b64ffd32	1
\.


--
-- Data for Name: merchant_kyc; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_kyc (kyc_serial_id, kyc_timestamp, kyc_ok, exchange_sig, exchange_pub, exchange_kyc_serial, account_serial, exchange_url) FROM stdin;
1	1660496845000000	f	\N	\N	0	1	http://localhost:8081/
\.


--
-- Data for Name: merchant_order_locks; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_order_locks (product_serial, total_locked, order_serial) FROM stdin;
\.


--
-- Data for Name: merchant_orders; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_orders (order_serial, merchant_serial, order_id, claim_token, h_post_data, pay_deadline, creation_time, contract_terms) FROM stdin;
\.


--
-- Data for Name: merchant_refund_proofs; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_refund_proofs (refund_serial, exchange_sig, signkey_serial) FROM stdin;
1	\\x77a6157d83727373d84e75c9d7f4398275cf4007f4d9086b8c1f61a75ff39f1ddf0691c446f623cedf18e11207bce1a375e6d804cbcb607e59a0ea2aac60da02	3
\.


--
-- Data for Name: merchant_refunds; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_refunds (refund_serial, order_serial, rtransaction_id, refund_timestamp, coin_pub, reason, refund_amount_val, refund_amount_frac) FROM stdin;
1	2	1	1660496852000000	\\xd5ed3b64fbbbc1e505af7c1e32a3231a4b4a42d59d35410dde1b312f9dbd3c7f	test refund	6	0
\.


--
-- Data for Name: merchant_tip_pickup_signatures; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_tip_pickup_signatures (pickup_serial, coin_offset, blind_sig) FROM stdin;
\.


--
-- Data for Name: merchant_tip_pickups; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_tip_pickups (pickup_serial, tip_serial, pickup_id, amount_val, amount_frac) FROM stdin;
\.


--
-- Data for Name: merchant_tip_reserve_keys; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_tip_reserve_keys (reserve_serial, reserve_priv, exchange_url, payto_uri) FROM stdin;
\.


--
-- Data for Name: merchant_tip_reserves; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_tip_reserves (reserve_serial, reserve_pub, merchant_serial, creation_time, expiration, merchant_initial_balance_val, merchant_initial_balance_frac, exchange_initial_balance_val, exchange_initial_balance_frac, tips_committed_val, tips_committed_frac, tips_picked_up_val, tips_picked_up_frac) FROM stdin;
\.


--
-- Data for Name: merchant_tips; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_tips (tip_serial, reserve_serial, tip_id, justification, next_url, expiration, amount_val, amount_frac, picked_up_val, picked_up_frac, was_picked_up) FROM stdin;
\.


--
-- Data for Name: merchant_transfer_signatures; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_transfer_signatures (credit_serial, signkey_serial, wire_fee_val, wire_fee_frac, credit_amount_val, credit_amount_frac, execution_time, exchange_sig) FROM stdin;
\.


--
-- Data for Name: merchant_transfer_to_coin; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_transfer_to_coin (deposit_serial, credit_serial, offset_in_exchange_list, exchange_deposit_value_val, exchange_deposit_value_frac, exchange_deposit_fee_val, exchange_deposit_fee_frac) FROM stdin;
\.


--
-- Data for Name: merchant_transfers; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_transfers (credit_serial, exchange_url, wtid, credit_amount_val, credit_amount_frac, account_serial, verified, confirmed) FROM stdin;
\.


--
-- Name: auditor_reserves_auditor_reserves_rowid_seq; Type: SEQUENCE SET; Schema: auditor; Owner: -
--

SELECT pg_catalog.setval('auditor.auditor_reserves_auditor_reserves_rowid_seq', 1, false);


--
-- Name: deposit_confirmations_serial_id_seq; Type: SEQUENCE SET; Schema: auditor; Owner: -
--

SELECT pg_catalog.setval('auditor.deposit_confirmations_serial_id_seq', 3, true);


--
-- Name: account_merges_account_merge_request_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.account_merges_account_merge_request_serial_id_seq', 1, false);


--
-- Name: aggregation_tracking_aggregation_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.aggregation_tracking_aggregation_serial_id_seq', 1, false);


--
-- Name: auditor_denom_sigs_auditor_denom_serial_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.auditor_denom_sigs_auditor_denom_serial_seq', 424, true);


--
-- Name: auditors_auditor_uuid_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.auditors_auditor_uuid_seq', 1, true);


--
-- Name: close_requests_close_request_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.close_requests_close_request_serial_id_seq', 1, false);


--
-- Name: contracts_contract_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.contracts_contract_serial_id_seq', 1, false);


--
-- Name: cs_nonce_locks_cs_nonce_lock_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.cs_nonce_locks_cs_nonce_lock_serial_id_seq', 1, false);


--
-- Name: denomination_revocations_denom_revocations_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.denomination_revocations_denom_revocations_serial_id_seq', 1, false);


--
-- Name: denominations_denominations_serial_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.denominations_denominations_serial_seq', 424, true);


--
-- Name: deposits_deposit_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.deposits_deposit_serial_id_seq', 3, true);


--
-- Name: exchange_sign_keys_esk_serial_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.exchange_sign_keys_esk_serial_seq', 5, true);


--
-- Name: extension_details_extension_details_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.extension_details_extension_details_serial_id_seq', 1, false);


--
-- Name: extensions_extension_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.extensions_extension_id_seq', 1, false);


--
-- Name: global_fee_global_fee_serial_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.global_fee_global_fee_serial_seq', 1, true);


--
-- Name: history_requests_history_request_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.history_requests_history_request_serial_id_seq', 1, false);


--
-- Name: known_coins_known_coin_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.known_coins_known_coin_id_seq', 7, true);


--
-- Name: legitimizations_legitimization_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.legitimizations_legitimization_serial_id_seq', 1, false);


--
-- Name: partners_partner_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.partners_partner_serial_id_seq', 1, false);


--
-- Name: prewire_prewire_uuid_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.prewire_prewire_uuid_seq', 1, false);


--
-- Name: profit_drains_profit_drain_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.profit_drains_profit_drain_serial_id_seq', 1, false);


--
-- Name: purse_deposits_purse_deposit_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.purse_deposits_purse_deposit_serial_id_seq', 1, false);


--
-- Name: purse_merges_purse_merge_request_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.purse_merges_purse_merge_request_serial_id_seq', 1, false);


--
-- Name: purse_refunds_purse_refunds_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.purse_refunds_purse_refunds_serial_id_seq', 1, false);


--
-- Name: purse_requests_purse_requests_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.purse_requests_purse_requests_serial_id_seq', 1, false);


--
-- Name: recoup_recoup_uuid_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.recoup_recoup_uuid_seq', 1, false);


--
-- Name: recoup_refresh_recoup_refresh_uuid_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.recoup_refresh_recoup_refresh_uuid_seq', 1, false);


--
-- Name: refresh_commitments_melt_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.refresh_commitments_melt_serial_id_seq', 4, true);


--
-- Name: refresh_revealed_coins_rrc_serial_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.refresh_revealed_coins_rrc_serial_seq', 48, true);


--
-- Name: refresh_transfer_keys_rtc_serial_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.refresh_transfer_keys_rtc_serial_seq', 4, true);


--
-- Name: refunds_refund_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.refunds_refund_serial_id_seq', 1, true);


--
-- Name: reserves_close_close_uuid_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.reserves_close_close_uuid_seq', 1, false);


--
-- Name: reserves_in_reserve_in_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.reserves_in_reserve_in_serial_id_seq', 13, true);


--
-- Name: reserves_out_reserve_out_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.reserves_out_reserve_out_serial_id_seq', 26, true);


--
-- Name: reserves_reserve_uuid_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.reserves_reserve_uuid_seq', 13, true);


--
-- Name: revolving_work_shards_shard_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.revolving_work_shards_shard_serial_id_seq', 1, false);


--
-- Name: signkey_revocations_signkey_revocations_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.signkey_revocations_signkey_revocations_serial_id_seq', 1, false);


--
-- Name: wad_in_entries_wad_in_entry_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.wad_in_entries_wad_in_entry_serial_id_seq', 1, false);


--
-- Name: wad_out_entries_wad_out_entry_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.wad_out_entries_wad_out_entry_serial_id_seq', 1, false);


--
-- Name: wads_in_wad_in_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.wads_in_wad_in_serial_id_seq', 1, false);


--
-- Name: wads_out_wad_out_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.wads_out_wad_out_serial_id_seq', 1, false);


--
-- Name: wire_fee_wire_fee_serial_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.wire_fee_wire_fee_serial_seq', 1, true);


--
-- Name: wire_out_wireout_uuid_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.wire_out_wireout_uuid_seq', 1, false);


--
-- Name: wire_targets_wire_target_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.wire_targets_wire_target_serial_id_seq', 16, true);


--
-- Name: work_shards_shard_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.work_shards_shard_serial_id_seq', 1, true);


--
-- Name: merchant_accounts_account_serial_seq; Type: SEQUENCE SET; Schema: merchant; Owner: -
--

SELECT pg_catalog.setval('merchant.merchant_accounts_account_serial_seq', 1, true);


--
-- Name: merchant_deposits_deposit_serial_seq; Type: SEQUENCE SET; Schema: merchant; Owner: -
--

SELECT pg_catalog.setval('merchant.merchant_deposits_deposit_serial_seq', 3, true);


--
-- Name: merchant_exchange_signing_keys_signkey_serial_seq; Type: SEQUENCE SET; Schema: merchant; Owner: -
--

SELECT pg_catalog.setval('merchant.merchant_exchange_signing_keys_signkey_serial_seq', 5, true);


--
-- Name: merchant_exchange_wire_fees_wirefee_serial_seq; Type: SEQUENCE SET; Schema: merchant; Owner: -
--

SELECT pg_catalog.setval('merchant.merchant_exchange_wire_fees_wirefee_serial_seq', 1, true);


--
-- Name: merchant_instances_merchant_serial_seq; Type: SEQUENCE SET; Schema: merchant; Owner: -
--

SELECT pg_catalog.setval('merchant.merchant_instances_merchant_serial_seq', 1, true);


--
-- Name: merchant_inventory_product_serial_seq; Type: SEQUENCE SET; Schema: merchant; Owner: -
--

SELECT pg_catalog.setval('merchant.merchant_inventory_product_serial_seq', 1, false);


--
-- Name: merchant_kyc_kyc_serial_id_seq; Type: SEQUENCE SET; Schema: merchant; Owner: -
--

SELECT pg_catalog.setval('merchant.merchant_kyc_kyc_serial_id_seq', 1, true);


--
-- Name: merchant_orders_order_serial_seq; Type: SEQUENCE SET; Schema: merchant; Owner: -
--

SELECT pg_catalog.setval('merchant.merchant_orders_order_serial_seq', 3, true);


--
-- Name: merchant_refunds_refund_serial_seq; Type: SEQUENCE SET; Schema: merchant; Owner: -
--

SELECT pg_catalog.setval('merchant.merchant_refunds_refund_serial_seq', 1, true);


--
-- Name: merchant_tip_pickups_pickup_serial_seq; Type: SEQUENCE SET; Schema: merchant; Owner: -
--

SELECT pg_catalog.setval('merchant.merchant_tip_pickups_pickup_serial_seq', 1, false);


--
-- Name: merchant_tip_reserves_reserve_serial_seq; Type: SEQUENCE SET; Schema: merchant; Owner: -
--

SELECT pg_catalog.setval('merchant.merchant_tip_reserves_reserve_serial_seq', 1, false);


--
-- Name: merchant_tips_tip_serial_seq; Type: SEQUENCE SET; Schema: merchant; Owner: -
--

SELECT pg_catalog.setval('merchant.merchant_tips_tip_serial_seq', 1, false);


--
-- Name: merchant_transfers_credit_serial_seq; Type: SEQUENCE SET; Schema: merchant; Owner: -
--

SELECT pg_catalog.setval('merchant.merchant_transfers_credit_serial_seq', 1, false);


--
-- Name: patches patches_pkey; Type: CONSTRAINT; Schema: _v; Owner: -
--

ALTER TABLE ONLY _v.patches
    ADD CONSTRAINT patches_pkey PRIMARY KEY (patch_name);


--
-- Name: auditor_denomination_pending auditor_denomination_pending_pkey; Type: CONSTRAINT; Schema: auditor; Owner: -
--

ALTER TABLE ONLY auditor.auditor_denomination_pending
    ADD CONSTRAINT auditor_denomination_pending_pkey PRIMARY KEY (denom_pub_hash);


--
-- Name: auditor_exchanges auditor_exchanges_pkey; Type: CONSTRAINT; Schema: auditor; Owner: -
--

ALTER TABLE ONLY auditor.auditor_exchanges
    ADD CONSTRAINT auditor_exchanges_pkey PRIMARY KEY (master_pub);


--
-- Name: auditor_historic_denomination_revenue auditor_historic_denomination_revenue_pkey; Type: CONSTRAINT; Schema: auditor; Owner: -
--

ALTER TABLE ONLY auditor.auditor_historic_denomination_revenue
    ADD CONSTRAINT auditor_historic_denomination_revenue_pkey PRIMARY KEY (denom_pub_hash);


--
-- Name: auditor_progress_aggregation auditor_progress_aggregation_pkey; Type: CONSTRAINT; Schema: auditor; Owner: -
--

ALTER TABLE ONLY auditor.auditor_progress_aggregation
    ADD CONSTRAINT auditor_progress_aggregation_pkey PRIMARY KEY (master_pub);


--
-- Name: auditor_progress_coin auditor_progress_coin_pkey; Type: CONSTRAINT; Schema: auditor; Owner: -
--

ALTER TABLE ONLY auditor.auditor_progress_coin
    ADD CONSTRAINT auditor_progress_coin_pkey PRIMARY KEY (master_pub);


--
-- Name: auditor_progress_deposit_confirmation auditor_progress_deposit_confirmation_pkey; Type: CONSTRAINT; Schema: auditor; Owner: -
--

ALTER TABLE ONLY auditor.auditor_progress_deposit_confirmation
    ADD CONSTRAINT auditor_progress_deposit_confirmation_pkey PRIMARY KEY (master_pub);


--
-- Name: auditor_progress_reserve auditor_progress_reserve_pkey; Type: CONSTRAINT; Schema: auditor; Owner: -
--

ALTER TABLE ONLY auditor.auditor_progress_reserve
    ADD CONSTRAINT auditor_progress_reserve_pkey PRIMARY KEY (master_pub);


--
-- Name: auditor_reserves auditor_reserves_auditor_reserves_rowid_key; Type: CONSTRAINT; Schema: auditor; Owner: -
--

ALTER TABLE ONLY auditor.auditor_reserves
    ADD CONSTRAINT auditor_reserves_auditor_reserves_rowid_key UNIQUE (auditor_reserves_rowid);


--
-- Name: deposit_confirmations deposit_confirmations_pkey; Type: CONSTRAINT; Schema: auditor; Owner: -
--

ALTER TABLE ONLY auditor.deposit_confirmations
    ADD CONSTRAINT deposit_confirmations_pkey PRIMARY KEY (h_contract_terms, h_wire, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig);


--
-- Name: deposit_confirmations deposit_confirmations_serial_id_key; Type: CONSTRAINT; Schema: auditor; Owner: -
--

ALTER TABLE ONLY auditor.deposit_confirmations
    ADD CONSTRAINT deposit_confirmations_serial_id_key UNIQUE (serial_id);


--
-- Name: wire_auditor_account_progress wire_auditor_account_progress_pkey; Type: CONSTRAINT; Schema: auditor; Owner: -
--

ALTER TABLE ONLY auditor.wire_auditor_account_progress
    ADD CONSTRAINT wire_auditor_account_progress_pkey PRIMARY KEY (master_pub, account_name);


--
-- Name: wire_auditor_progress wire_auditor_progress_pkey; Type: CONSTRAINT; Schema: auditor; Owner: -
--

ALTER TABLE ONLY auditor.wire_auditor_progress
    ADD CONSTRAINT wire_auditor_progress_pkey PRIMARY KEY (master_pub);


--
-- Name: account_merges_default account_merges_default_account_merge_request_serial_id_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.account_merges_default
    ADD CONSTRAINT account_merges_default_account_merge_request_serial_id_key UNIQUE (account_merge_request_serial_id);


--
-- Name: account_merges account_merges_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.account_merges
    ADD CONSTRAINT account_merges_pkey PRIMARY KEY (purse_pub);


--
-- Name: account_merges_default account_merges_default_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.account_merges_default
    ADD CONSTRAINT account_merges_default_pkey PRIMARY KEY (purse_pub);


--
-- Name: aggregation_tracking_default aggregation_tracking_default_aggregation_serial_id_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.aggregation_tracking_default
    ADD CONSTRAINT aggregation_tracking_default_aggregation_serial_id_key UNIQUE (aggregation_serial_id);


--
-- Name: aggregation_tracking aggregation_tracking_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.aggregation_tracking
    ADD CONSTRAINT aggregation_tracking_pkey PRIMARY KEY (deposit_serial_id);


--
-- Name: aggregation_tracking_default aggregation_tracking_default_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.aggregation_tracking_default
    ADD CONSTRAINT aggregation_tracking_default_pkey PRIMARY KEY (deposit_serial_id);


--
-- Name: auditor_denom_sigs auditor_denom_sigs_auditor_denom_serial_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.auditor_denom_sigs
    ADD CONSTRAINT auditor_denom_sigs_auditor_denom_serial_key UNIQUE (auditor_denom_serial);


--
-- Name: auditor_denom_sigs auditor_denom_sigs_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.auditor_denom_sigs
    ADD CONSTRAINT auditor_denom_sigs_pkey PRIMARY KEY (denominations_serial, auditor_uuid);


--
-- Name: auditors auditors_auditor_uuid_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.auditors
    ADD CONSTRAINT auditors_auditor_uuid_key UNIQUE (auditor_uuid);


--
-- Name: auditors auditors_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.auditors
    ADD CONSTRAINT auditors_pkey PRIMARY KEY (auditor_pub);


--
-- Name: close_requests close_requests_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.close_requests
    ADD CONSTRAINT close_requests_pkey PRIMARY KEY (reserve_pub, close_timestamp);


--
-- Name: close_requests_default close_requests_default_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.close_requests_default
    ADD CONSTRAINT close_requests_default_pkey PRIMARY KEY (reserve_pub, close_timestamp);


--
-- Name: contracts_default contracts_default_contract_serial_id_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.contracts_default
    ADD CONSTRAINT contracts_default_contract_serial_id_key UNIQUE (contract_serial_id);


--
-- Name: contracts contracts_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.contracts
    ADD CONSTRAINT contracts_pkey PRIMARY KEY (purse_pub);


--
-- Name: contracts_default contracts_default_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.contracts_default
    ADD CONSTRAINT contracts_default_pkey PRIMARY KEY (purse_pub);


--
-- Name: cs_nonce_locks_default cs_nonce_locks_default_cs_nonce_lock_serial_id_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.cs_nonce_locks_default
    ADD CONSTRAINT cs_nonce_locks_default_cs_nonce_lock_serial_id_key UNIQUE (cs_nonce_lock_serial_id);


--
-- Name: cs_nonce_locks cs_nonce_locks_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.cs_nonce_locks
    ADD CONSTRAINT cs_nonce_locks_pkey PRIMARY KEY (nonce);


--
-- Name: cs_nonce_locks_default cs_nonce_locks_default_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.cs_nonce_locks_default
    ADD CONSTRAINT cs_nonce_locks_default_pkey PRIMARY KEY (nonce);


--
-- Name: denomination_revocations denomination_revocations_denom_revocations_serial_id_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.denomination_revocations
    ADD CONSTRAINT denomination_revocations_denom_revocations_serial_id_key UNIQUE (denom_revocations_serial_id);


--
-- Name: denomination_revocations denomination_revocations_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.denomination_revocations
    ADD CONSTRAINT denomination_revocations_pkey PRIMARY KEY (denominations_serial);


--
-- Name: denominations denominations_denominations_serial_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.denominations
    ADD CONSTRAINT denominations_denominations_serial_key UNIQUE (denominations_serial);


--
-- Name: denominations denominations_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.denominations
    ADD CONSTRAINT denominations_pkey PRIMARY KEY (denom_pub_hash);


--
-- Name: deposits_default deposits_default_coin_pub_merchant_pub_h_contract_terms_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.deposits_default
    ADD CONSTRAINT deposits_default_coin_pub_merchant_pub_h_contract_terms_key UNIQUE (coin_pub, merchant_pub, h_contract_terms);


--
-- Name: deposits_default deposits_default_deposit_serial_id_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.deposits_default
    ADD CONSTRAINT deposits_default_deposit_serial_id_pkey PRIMARY KEY (deposit_serial_id);


--
-- Name: exchange_sign_keys exchange_sign_keys_esk_serial_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.exchange_sign_keys
    ADD CONSTRAINT exchange_sign_keys_esk_serial_key UNIQUE (esk_serial);


--
-- Name: exchange_sign_keys exchange_sign_keys_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.exchange_sign_keys
    ADD CONSTRAINT exchange_sign_keys_pkey PRIMARY KEY (exchange_pub);


--
-- Name: extension_details extension_details_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.extension_details
    ADD CONSTRAINT extension_details_pkey PRIMARY KEY (extension_details_serial_id);


--
-- Name: extension_details_default extension_details_default_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.extension_details_default
    ADD CONSTRAINT extension_details_default_pkey PRIMARY KEY (extension_details_serial_id);


--
-- Name: extensions extensions_extension_id_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.extensions
    ADD CONSTRAINT extensions_extension_id_key UNIQUE (extension_id);


--
-- Name: extensions extensions_name_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.extensions
    ADD CONSTRAINT extensions_name_key UNIQUE (name);


--
-- Name: global_fee global_fee_global_fee_serial_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.global_fee
    ADD CONSTRAINT global_fee_global_fee_serial_key UNIQUE (global_fee_serial);


--
-- Name: global_fee global_fee_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.global_fee
    ADD CONSTRAINT global_fee_pkey PRIMARY KEY (start_date);


--
-- Name: history_requests history_requests_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.history_requests
    ADD CONSTRAINT history_requests_pkey PRIMARY KEY (reserve_pub, request_timestamp);


--
-- Name: history_requests_default history_requests_default_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.history_requests_default
    ADD CONSTRAINT history_requests_default_pkey PRIMARY KEY (reserve_pub, request_timestamp);


--
-- Name: known_coins_default known_coins_default_known_coin_id_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.known_coins_default
    ADD CONSTRAINT known_coins_default_known_coin_id_key UNIQUE (known_coin_id);


--
-- Name: known_coins known_coins_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.known_coins
    ADD CONSTRAINT known_coins_pkey PRIMARY KEY (coin_pub);


--
-- Name: known_coins_default known_coins_default_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.known_coins_default
    ADD CONSTRAINT known_coins_default_pkey PRIMARY KEY (coin_pub);


--
-- Name: kyc_alerts kyc_alerts_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.kyc_alerts
    ADD CONSTRAINT kyc_alerts_pkey PRIMARY KEY (h_payto);


--
-- Name: kyc_alerts kyc_alerts_trigger_type_h_payto_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.kyc_alerts
    ADD CONSTRAINT kyc_alerts_trigger_type_h_payto_key UNIQUE (trigger_type, h_payto);


--
-- Name: legitimizations legitimizations_h_payto_provider_section_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.legitimizations
    ADD CONSTRAINT legitimizations_h_payto_provider_section_key UNIQUE (h_payto, provider_section);


--
-- Name: legitimizations_default legitimizations_default_h_payto_provider_section_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.legitimizations_default
    ADD CONSTRAINT legitimizations_default_h_payto_provider_section_key UNIQUE (h_payto, provider_section);


--
-- Name: legitimizations_default legitimizations_default_legitimization_serial_id_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.legitimizations_default
    ADD CONSTRAINT legitimizations_default_legitimization_serial_id_key UNIQUE (legitimization_serial_id);


--
-- Name: partner_accounts partner_accounts_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.partner_accounts
    ADD CONSTRAINT partner_accounts_pkey PRIMARY KEY (payto_uri);


--
-- Name: partners partners_partner_serial_id_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.partners
    ADD CONSTRAINT partners_partner_serial_id_key UNIQUE (partner_serial_id);


--
-- Name: prewire prewire_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.prewire
    ADD CONSTRAINT prewire_pkey PRIMARY KEY (prewire_uuid);


--
-- Name: prewire_default prewire_default_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.prewire_default
    ADD CONSTRAINT prewire_default_pkey PRIMARY KEY (prewire_uuid);


--
-- Name: profit_drains profit_drains_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.profit_drains
    ADD CONSTRAINT profit_drains_pkey PRIMARY KEY (wtid);


--
-- Name: profit_drains profit_drains_profit_drain_serial_id_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.profit_drains
    ADD CONSTRAINT profit_drains_profit_drain_serial_id_key UNIQUE (profit_drain_serial_id);


--
-- Name: purse_actions purse_actions_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.purse_actions
    ADD CONSTRAINT purse_actions_pkey PRIMARY KEY (purse_pub);


--
-- Name: purse_deposits purse_deposits_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.purse_deposits
    ADD CONSTRAINT purse_deposits_pkey PRIMARY KEY (purse_pub, coin_pub);


--
-- Name: purse_deposits_default purse_deposits_default_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.purse_deposits_default
    ADD CONSTRAINT purse_deposits_default_pkey PRIMARY KEY (purse_pub, coin_pub);


--
-- Name: purse_deposits_default purse_deposits_default_purse_deposit_serial_id_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.purse_deposits_default
    ADD CONSTRAINT purse_deposits_default_purse_deposit_serial_id_key UNIQUE (purse_deposit_serial_id);


--
-- Name: purse_merges purse_merges_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.purse_merges
    ADD CONSTRAINT purse_merges_pkey PRIMARY KEY (purse_pub);


--
-- Name: purse_merges_default purse_merges_default_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.purse_merges_default
    ADD CONSTRAINT purse_merges_default_pkey PRIMARY KEY (purse_pub);


--
-- Name: purse_merges_default purse_merges_default_purse_merge_request_serial_id_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.purse_merges_default
    ADD CONSTRAINT purse_merges_default_purse_merge_request_serial_id_key UNIQUE (purse_merge_request_serial_id);


--
-- Name: purse_refunds purse_refunds_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.purse_refunds
    ADD CONSTRAINT purse_refunds_pkey PRIMARY KEY (purse_pub);


--
-- Name: purse_refunds_default purse_refunds_default_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.purse_refunds_default
    ADD CONSTRAINT purse_refunds_default_pkey PRIMARY KEY (purse_pub);


--
-- Name: purse_refunds_default purse_refunds_default_purse_refunds_serial_id_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.purse_refunds_default
    ADD CONSTRAINT purse_refunds_default_purse_refunds_serial_id_key UNIQUE (purse_refunds_serial_id);


--
-- Name: purse_requests purse_requests_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.purse_requests
    ADD CONSTRAINT purse_requests_pkey PRIMARY KEY (purse_pub);


--
-- Name: purse_requests_default purse_requests_default_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.purse_requests_default
    ADD CONSTRAINT purse_requests_default_pkey PRIMARY KEY (purse_pub);


--
-- Name: purse_requests_default purse_requests_default_purse_requests_serial_id_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.purse_requests_default
    ADD CONSTRAINT purse_requests_default_purse_requests_serial_id_key UNIQUE (purse_requests_serial_id);


--
-- Name: recoup_default recoup_default_recoup_uuid_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.recoup_default
    ADD CONSTRAINT recoup_default_recoup_uuid_key UNIQUE (recoup_uuid);


--
-- Name: recoup_refresh_default recoup_refresh_default_recoup_refresh_uuid_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.recoup_refresh_default
    ADD CONSTRAINT recoup_refresh_default_recoup_refresh_uuid_key UNIQUE (recoup_refresh_uuid);


--
-- Name: refresh_commitments_default refresh_commitments_default_melt_serial_id_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.refresh_commitments_default
    ADD CONSTRAINT refresh_commitments_default_melt_serial_id_key UNIQUE (melt_serial_id);


--
-- Name: refresh_commitments refresh_commitments_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.refresh_commitments
    ADD CONSTRAINT refresh_commitments_pkey PRIMARY KEY (rc);


--
-- Name: refresh_commitments_default refresh_commitments_default_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.refresh_commitments_default
    ADD CONSTRAINT refresh_commitments_default_pkey PRIMARY KEY (rc);


--
-- Name: refresh_revealed_coins_default refresh_revealed_coins_default_coin_ev_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.refresh_revealed_coins_default
    ADD CONSTRAINT refresh_revealed_coins_default_coin_ev_key UNIQUE (coin_ev);


--
-- Name: refresh_revealed_coins_default refresh_revealed_coins_default_h_coin_ev_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.refresh_revealed_coins_default
    ADD CONSTRAINT refresh_revealed_coins_default_h_coin_ev_key UNIQUE (h_coin_ev);


--
-- Name: refresh_revealed_coins_default refresh_revealed_coins_default_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.refresh_revealed_coins_default
    ADD CONSTRAINT refresh_revealed_coins_default_pkey PRIMARY KEY (melt_serial_id, freshcoin_index);


--
-- Name: refresh_revealed_coins_default refresh_revealed_coins_default_rrc_serial_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.refresh_revealed_coins_default
    ADD CONSTRAINT refresh_revealed_coins_default_rrc_serial_key UNIQUE (rrc_serial);


--
-- Name: refresh_transfer_keys refresh_transfer_keys_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.refresh_transfer_keys
    ADD CONSTRAINT refresh_transfer_keys_pkey PRIMARY KEY (melt_serial_id);


--
-- Name: refresh_transfer_keys_default refresh_transfer_keys_default_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.refresh_transfer_keys_default
    ADD CONSTRAINT refresh_transfer_keys_default_pkey PRIMARY KEY (melt_serial_id);


--
-- Name: refresh_transfer_keys_default refresh_transfer_keys_default_rtc_serial_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.refresh_transfer_keys_default
    ADD CONSTRAINT refresh_transfer_keys_default_rtc_serial_key UNIQUE (rtc_serial);


--
-- Name: refunds_default refunds_default_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.refunds_default
    ADD CONSTRAINT refunds_default_pkey PRIMARY KEY (deposit_serial_id, rtransaction_id);


--
-- Name: refunds_default refunds_default_refund_serial_id_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.refunds_default
    ADD CONSTRAINT refunds_default_refund_serial_id_key UNIQUE (refund_serial_id);


--
-- Name: reserves_close_default reserves_close_default_close_uuid_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.reserves_close_default
    ADD CONSTRAINT reserves_close_default_close_uuid_pkey PRIMARY KEY (close_uuid);


--
-- Name: reserves reserves_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.reserves
    ADD CONSTRAINT reserves_pkey PRIMARY KEY (reserve_pub);


--
-- Name: reserves_default reserves_default_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.reserves_default
    ADD CONSTRAINT reserves_default_pkey PRIMARY KEY (reserve_pub);


--
-- Name: reserves_in reserves_in_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.reserves_in
    ADD CONSTRAINT reserves_in_pkey PRIMARY KEY (reserve_pub);


--
-- Name: reserves_in_default reserves_in_default_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.reserves_in_default
    ADD CONSTRAINT reserves_in_default_pkey PRIMARY KEY (reserve_pub);


--
-- Name: reserves_in_default reserves_in_default_reserve_in_serial_id_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.reserves_in_default
    ADD CONSTRAINT reserves_in_default_reserve_in_serial_id_key UNIQUE (reserve_in_serial_id);


--
-- Name: reserves_out reserves_out_h_blind_ev_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.reserves_out
    ADD CONSTRAINT reserves_out_h_blind_ev_key UNIQUE (h_blind_ev);


--
-- Name: reserves_out_default reserves_out_default_h_blind_ev_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.reserves_out_default
    ADD CONSTRAINT reserves_out_default_h_blind_ev_key UNIQUE (h_blind_ev);


--
-- Name: reserves_out_default reserves_out_default_reserve_out_serial_id_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.reserves_out_default
    ADD CONSTRAINT reserves_out_default_reserve_out_serial_id_key UNIQUE (reserve_out_serial_id);


--
-- Name: revolving_work_shards revolving_work_shards_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.revolving_work_shards
    ADD CONSTRAINT revolving_work_shards_pkey PRIMARY KEY (job_name, start_row);


--
-- Name: revolving_work_shards revolving_work_shards_shard_serial_id_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.revolving_work_shards
    ADD CONSTRAINT revolving_work_shards_shard_serial_id_key UNIQUE (shard_serial_id);


--
-- Name: signkey_revocations signkey_revocations_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.signkey_revocations
    ADD CONSTRAINT signkey_revocations_pkey PRIMARY KEY (esk_serial);


--
-- Name: signkey_revocations signkey_revocations_signkey_revocations_serial_id_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.signkey_revocations
    ADD CONSTRAINT signkey_revocations_signkey_revocations_serial_id_key UNIQUE (signkey_revocations_serial_id);


--
-- Name: wad_in_entries wad_in_entries_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.wad_in_entries
    ADD CONSTRAINT wad_in_entries_pkey PRIMARY KEY (purse_pub);


--
-- Name: wad_in_entries_default wad_in_entries_default_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.wad_in_entries_default
    ADD CONSTRAINT wad_in_entries_default_pkey PRIMARY KEY (purse_pub);


--
-- Name: wad_in_entries_default wad_in_entries_default_wad_in_entry_serial_id_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.wad_in_entries_default
    ADD CONSTRAINT wad_in_entries_default_wad_in_entry_serial_id_key UNIQUE (wad_in_entry_serial_id);


--
-- Name: wad_out_entries wad_out_entries_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.wad_out_entries
    ADD CONSTRAINT wad_out_entries_pkey PRIMARY KEY (purse_pub);


--
-- Name: wad_out_entries_default wad_out_entries_default_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.wad_out_entries_default
    ADD CONSTRAINT wad_out_entries_default_pkey PRIMARY KEY (purse_pub);


--
-- Name: wad_out_entries_default wad_out_entries_default_wad_out_entry_serial_id_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.wad_out_entries_default
    ADD CONSTRAINT wad_out_entries_default_wad_out_entry_serial_id_key UNIQUE (wad_out_entry_serial_id);


--
-- Name: wads_in wads_in_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.wads_in
    ADD CONSTRAINT wads_in_pkey PRIMARY KEY (wad_id);


--
-- Name: wads_in_default wads_in_default_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.wads_in_default
    ADD CONSTRAINT wads_in_default_pkey PRIMARY KEY (wad_id);


--
-- Name: wads_in wads_in_wad_id_origin_exchange_url_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.wads_in
    ADD CONSTRAINT wads_in_wad_id_origin_exchange_url_key UNIQUE (wad_id, origin_exchange_url);


--
-- Name: wads_in_default wads_in_default_wad_id_origin_exchange_url_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.wads_in_default
    ADD CONSTRAINT wads_in_default_wad_id_origin_exchange_url_key UNIQUE (wad_id, origin_exchange_url);


--
-- Name: wads_in_default wads_in_default_wad_in_serial_id_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.wads_in_default
    ADD CONSTRAINT wads_in_default_wad_in_serial_id_key UNIQUE (wad_in_serial_id);


--
-- Name: wads_in_default wads_in_default_wad_is_origin_exchange_url_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.wads_in_default
    ADD CONSTRAINT wads_in_default_wad_is_origin_exchange_url_key UNIQUE (wad_id, origin_exchange_url);


--
-- Name: wads_out wads_out_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.wads_out
    ADD CONSTRAINT wads_out_pkey PRIMARY KEY (wad_id);


--
-- Name: wads_out_default wads_out_default_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.wads_out_default
    ADD CONSTRAINT wads_out_default_pkey PRIMARY KEY (wad_id);


--
-- Name: wads_out_default wads_out_default_wad_out_serial_id_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.wads_out_default
    ADD CONSTRAINT wads_out_default_wad_out_serial_id_key UNIQUE (wad_out_serial_id);


--
-- Name: wire_accounts wire_accounts_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.wire_accounts
    ADD CONSTRAINT wire_accounts_pkey PRIMARY KEY (payto_uri);


--
-- Name: wire_fee wire_fee_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.wire_fee
    ADD CONSTRAINT wire_fee_pkey PRIMARY KEY (wire_method, start_date);


--
-- Name: wire_fee wire_fee_wire_fee_serial_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.wire_fee
    ADD CONSTRAINT wire_fee_wire_fee_serial_key UNIQUE (wire_fee_serial);


--
-- Name: wire_out_default wire_out_default_wireout_uuid_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.wire_out_default
    ADD CONSTRAINT wire_out_default_wireout_uuid_pkey PRIMARY KEY (wireout_uuid);


--
-- Name: wire_out wire_out_wtid_raw_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.wire_out
    ADD CONSTRAINT wire_out_wtid_raw_key UNIQUE (wtid_raw);


--
-- Name: wire_out_default wire_out_default_wtid_raw_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.wire_out_default
    ADD CONSTRAINT wire_out_default_wtid_raw_key UNIQUE (wtid_raw);


--
-- Name: wire_targets wire_targets_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.wire_targets
    ADD CONSTRAINT wire_targets_pkey PRIMARY KEY (wire_target_h_payto);


--
-- Name: wire_targets_default wire_targets_default_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.wire_targets_default
    ADD CONSTRAINT wire_targets_default_pkey PRIMARY KEY (wire_target_h_payto);


--
-- Name: wire_targets_default wire_targets_default_wire_target_serial_id_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.wire_targets_default
    ADD CONSTRAINT wire_targets_default_wire_target_serial_id_key UNIQUE (wire_target_serial_id);


--
-- Name: work_shards work_shards_pkey; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.work_shards
    ADD CONSTRAINT work_shards_pkey PRIMARY KEY (job_name, start_row);


--
-- Name: work_shards work_shards_shard_serial_id_key; Type: CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.work_shards
    ADD CONSTRAINT work_shards_shard_serial_id_key UNIQUE (shard_serial_id);


--
-- Name: merchant_accounts merchant_accounts_h_wire_key; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_accounts
    ADD CONSTRAINT merchant_accounts_h_wire_key UNIQUE (h_wire);


--
-- Name: merchant_accounts merchant_accounts_merchant_serial_payto_uri_key; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_accounts
    ADD CONSTRAINT merchant_accounts_merchant_serial_payto_uri_key UNIQUE (merchant_serial, payto_uri);


--
-- Name: merchant_accounts merchant_accounts_pkey; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_accounts
    ADD CONSTRAINT merchant_accounts_pkey PRIMARY KEY (account_serial);


--
-- Name: merchant_contract_terms merchant_contract_terms_merchant_serial_h_contract_terms_key; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_contract_terms
    ADD CONSTRAINT merchant_contract_terms_merchant_serial_h_contract_terms_key UNIQUE (merchant_serial, h_contract_terms);


--
-- Name: merchant_contract_terms merchant_contract_terms_merchant_serial_order_id_key; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_contract_terms
    ADD CONSTRAINT merchant_contract_terms_merchant_serial_order_id_key UNIQUE (merchant_serial, order_id);


--
-- Name: merchant_contract_terms merchant_contract_terms_pkey; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_contract_terms
    ADD CONSTRAINT merchant_contract_terms_pkey PRIMARY KEY (order_serial);


--
-- Name: merchant_deposit_to_transfer merchant_deposit_to_transfer_deposit_serial_credit_serial_key; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_deposit_to_transfer
    ADD CONSTRAINT merchant_deposit_to_transfer_deposit_serial_credit_serial_key UNIQUE (deposit_serial, credit_serial);


--
-- Name: merchant_deposits merchant_deposits_order_serial_coin_pub_key; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_deposits
    ADD CONSTRAINT merchant_deposits_order_serial_coin_pub_key UNIQUE (order_serial, coin_pub);


--
-- Name: merchant_deposits merchant_deposits_pkey; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_deposits
    ADD CONSTRAINT merchant_deposits_pkey PRIMARY KEY (deposit_serial);


--
-- Name: merchant_exchange_signing_keys merchant_exchange_signing_key_exchange_pub_start_date_maste_key; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_exchange_signing_keys
    ADD CONSTRAINT merchant_exchange_signing_key_exchange_pub_start_date_maste_key UNIQUE (exchange_pub, start_date, master_pub);


--
-- Name: merchant_exchange_signing_keys merchant_exchange_signing_keys_pkey; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_exchange_signing_keys
    ADD CONSTRAINT merchant_exchange_signing_keys_pkey PRIMARY KEY (signkey_serial);


--
-- Name: merchant_exchange_wire_fees merchant_exchange_wire_fees_master_pub_h_wire_method_start__key; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_exchange_wire_fees
    ADD CONSTRAINT merchant_exchange_wire_fees_master_pub_h_wire_method_start__key UNIQUE (master_pub, h_wire_method, start_date);


--
-- Name: merchant_exchange_wire_fees merchant_exchange_wire_fees_pkey; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_exchange_wire_fees
    ADD CONSTRAINT merchant_exchange_wire_fees_pkey PRIMARY KEY (wirefee_serial);


--
-- Name: merchant_instances merchant_instances_merchant_id_key; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_instances
    ADD CONSTRAINT merchant_instances_merchant_id_key UNIQUE (merchant_id);


--
-- Name: merchant_instances merchant_instances_merchant_pub_key; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_instances
    ADD CONSTRAINT merchant_instances_merchant_pub_key UNIQUE (merchant_pub);


--
-- Name: merchant_instances merchant_instances_pkey; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_instances
    ADD CONSTRAINT merchant_instances_pkey PRIMARY KEY (merchant_serial);


--
-- Name: merchant_inventory merchant_inventory_merchant_serial_product_id_key; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_inventory
    ADD CONSTRAINT merchant_inventory_merchant_serial_product_id_key UNIQUE (merchant_serial, product_id);


--
-- Name: merchant_inventory merchant_inventory_pkey; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_inventory
    ADD CONSTRAINT merchant_inventory_pkey PRIMARY KEY (product_serial);


--
-- Name: merchant_keys merchant_keys_merchant_priv_key; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_keys
    ADD CONSTRAINT merchant_keys_merchant_priv_key UNIQUE (merchant_priv);


--
-- Name: merchant_keys merchant_keys_pkey; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_keys
    ADD CONSTRAINT merchant_keys_pkey PRIMARY KEY (merchant_serial);


--
-- Name: merchant_kyc merchant_kyc_kyc_serial_id_key; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_kyc
    ADD CONSTRAINT merchant_kyc_kyc_serial_id_key UNIQUE (kyc_serial_id);


--
-- Name: merchant_kyc merchant_kyc_pkey; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_kyc
    ADD CONSTRAINT merchant_kyc_pkey PRIMARY KEY (account_serial, exchange_url);


--
-- Name: merchant_orders merchant_orders_merchant_serial_order_id_key; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_orders
    ADD CONSTRAINT merchant_orders_merchant_serial_order_id_key UNIQUE (merchant_serial, order_id);


--
-- Name: merchant_orders merchant_orders_pkey; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_orders
    ADD CONSTRAINT merchant_orders_pkey PRIMARY KEY (order_serial);


--
-- Name: merchant_refund_proofs merchant_refund_proofs_pkey; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_refund_proofs
    ADD CONSTRAINT merchant_refund_proofs_pkey PRIMARY KEY (refund_serial);


--
-- Name: merchant_refunds merchant_refunds_order_serial_coin_pub_rtransaction_id_key; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_refunds
    ADD CONSTRAINT merchant_refunds_order_serial_coin_pub_rtransaction_id_key UNIQUE (order_serial, coin_pub, rtransaction_id);


--
-- Name: merchant_refunds merchant_refunds_pkey; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_refunds
    ADD CONSTRAINT merchant_refunds_pkey PRIMARY KEY (refund_serial);


--
-- Name: merchant_tip_pickup_signatures merchant_tip_pickup_signatures_pkey; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_tip_pickup_signatures
    ADD CONSTRAINT merchant_tip_pickup_signatures_pkey PRIMARY KEY (pickup_serial, coin_offset);


--
-- Name: merchant_tip_pickups merchant_tip_pickups_pickup_id_key; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_tip_pickups
    ADD CONSTRAINT merchant_tip_pickups_pickup_id_key UNIQUE (pickup_id);


--
-- Name: merchant_tip_pickups merchant_tip_pickups_pkey; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_tip_pickups
    ADD CONSTRAINT merchant_tip_pickups_pkey PRIMARY KEY (pickup_serial);


--
-- Name: merchant_tip_reserve_keys merchant_tip_reserve_keys_reserve_priv_key; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_tip_reserve_keys
    ADD CONSTRAINT merchant_tip_reserve_keys_reserve_priv_key UNIQUE (reserve_priv);


--
-- Name: merchant_tip_reserve_keys merchant_tip_reserve_keys_reserve_serial_key; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_tip_reserve_keys
    ADD CONSTRAINT merchant_tip_reserve_keys_reserve_serial_key UNIQUE (reserve_serial);


--
-- Name: merchant_tip_reserves merchant_tip_reserves_pkey; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_tip_reserves
    ADD CONSTRAINT merchant_tip_reserves_pkey PRIMARY KEY (reserve_serial);


--
-- Name: merchant_tip_reserves merchant_tip_reserves_reserve_pub_key; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_tip_reserves
    ADD CONSTRAINT merchant_tip_reserves_reserve_pub_key UNIQUE (reserve_pub);


--
-- Name: merchant_tips merchant_tips_pkey; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_tips
    ADD CONSTRAINT merchant_tips_pkey PRIMARY KEY (tip_serial);


--
-- Name: merchant_tips merchant_tips_tip_id_key; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_tips
    ADD CONSTRAINT merchant_tips_tip_id_key UNIQUE (tip_id);


--
-- Name: merchant_transfer_signatures merchant_transfer_signatures_pkey; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_transfer_signatures
    ADD CONSTRAINT merchant_transfer_signatures_pkey PRIMARY KEY (credit_serial);


--
-- Name: merchant_transfer_to_coin merchant_transfer_to_coin_deposit_serial_key; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_transfer_to_coin
    ADD CONSTRAINT merchant_transfer_to_coin_deposit_serial_key UNIQUE (deposit_serial);


--
-- Name: merchant_transfers merchant_transfers_pkey; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_transfers
    ADD CONSTRAINT merchant_transfers_pkey PRIMARY KEY (credit_serial);


--
-- Name: merchant_transfers merchant_transfers_wtid_exchange_url_account_serial_key; Type: CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_transfers
    ADD CONSTRAINT merchant_transfers_wtid_exchange_url_account_serial_key UNIQUE (wtid, exchange_url, account_serial);


--
-- Name: auditor_historic_reserve_summary_by_master_pub_start_date; Type: INDEX; Schema: auditor; Owner: -
--

CREATE INDEX auditor_historic_reserve_summary_by_master_pub_start_date ON auditor.auditor_historic_reserve_summary USING btree (master_pub, start_date);


--
-- Name: auditor_reserves_by_reserve_pub; Type: INDEX; Schema: auditor; Owner: -
--

CREATE INDEX auditor_reserves_by_reserve_pub ON auditor.auditor_reserves USING btree (reserve_pub);


--
-- Name: account_merges_by_reserve_pub; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX account_merges_by_reserve_pub ON ONLY exchange.account_merges USING btree (reserve_pub);


--
-- Name: account_merges_default_reserve_pub_idx; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX account_merges_default_reserve_pub_idx ON exchange.account_merges_default USING btree (reserve_pub);


--
-- Name: aggregation_tracking_by_wtid_raw_index; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX aggregation_tracking_by_wtid_raw_index ON ONLY exchange.aggregation_tracking USING btree (wtid_raw);


--
-- Name: INDEX aggregation_tracking_by_wtid_raw_index; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON INDEX exchange.aggregation_tracking_by_wtid_raw_index IS 'for lookup_transactions';


--
-- Name: aggregation_tracking_default_wtid_raw_idx; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX aggregation_tracking_default_wtid_raw_idx ON exchange.aggregation_tracking_default USING btree (wtid_raw);


--
-- Name: denominations_by_expire_legal_index; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX denominations_by_expire_legal_index ON exchange.denominations USING btree (expire_legal);


--
-- Name: deposits_by_coin_pub_index; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX deposits_by_coin_pub_index ON ONLY exchange.deposits USING btree (coin_pub);


--
-- Name: deposits_by_ready_main_index; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX deposits_by_ready_main_index ON ONLY exchange.deposits_by_ready USING btree (wire_deadline, shard, coin_pub);


--
-- Name: deposits_by_ready_default_wire_deadline_shard_coin_pub_idx; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX deposits_by_ready_default_wire_deadline_shard_coin_pub_idx ON exchange.deposits_by_ready_default USING btree (wire_deadline, shard, coin_pub);


--
-- Name: deposits_default_coin_pub_idx; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX deposits_default_coin_pub_idx ON exchange.deposits_default USING btree (coin_pub);


--
-- Name: deposits_for_matching_main_index; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX deposits_for_matching_main_index ON ONLY exchange.deposits_for_matching USING btree (refund_deadline, merchant_pub, coin_pub);


--
-- Name: deposits_for_matching_default_refund_deadline_merchant_pub__idx; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX deposits_for_matching_default_refund_deadline_merchant_pub__idx ON exchange.deposits_for_matching_default USING btree (refund_deadline, merchant_pub, coin_pub);


--
-- Name: global_fee_by_end_date_index; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX global_fee_by_end_date_index ON exchange.global_fee USING btree (end_date);


--
-- Name: legitimizations_default_by_provider_and_legi_index; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX legitimizations_default_by_provider_and_legi_index ON exchange.legitimizations_default USING btree (provider_section, provider_legitimization_id);


--
-- Name: INDEX legitimizations_default_by_provider_and_legi_index; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON INDEX exchange.legitimizations_default_by_provider_and_legi_index IS 'used (rarely) in kyc_provider_account_lookup';


--
-- Name: partner_accounts_index_by_partner_and_time; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX partner_accounts_index_by_partner_and_time ON exchange.partner_accounts USING btree (partner_serial_id, last_seen);


--
-- Name: partner_by_wad_time; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX partner_by_wad_time ON exchange.partners USING btree (next_wad);


--
-- Name: prewire_by_failed_finished_index; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX prewire_by_failed_finished_index ON ONLY exchange.prewire USING btree (failed, finished);


--
-- Name: INDEX prewire_by_failed_finished_index; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON INDEX exchange.prewire_by_failed_finished_index IS 'for wire_prepare_data_get';


--
-- Name: prewire_by_finished_index; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX prewire_by_finished_index ON ONLY exchange.prewire USING btree (finished);


--
-- Name: INDEX prewire_by_finished_index; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON INDEX exchange.prewire_by_finished_index IS 'for gc_prewire';


--
-- Name: prewire_default_failed_finished_idx; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX prewire_default_failed_finished_idx ON exchange.prewire_default USING btree (failed, finished);


--
-- Name: prewire_default_finished_idx; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX prewire_default_finished_idx ON exchange.prewire_default USING btree (finished);


--
-- Name: purse_action_by_target; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX purse_action_by_target ON exchange.purse_actions USING btree (partner_serial_id, action_date);


--
-- Name: purse_deposits_by_coin_pub; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX purse_deposits_by_coin_pub ON ONLY exchange.purse_deposits USING btree (coin_pub);


--
-- Name: purse_deposits_default_coin_pub_idx; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX purse_deposits_default_coin_pub_idx ON exchange.purse_deposits_default USING btree (coin_pub);


--
-- Name: purse_merges_reserve_pub; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX purse_merges_reserve_pub ON ONLY exchange.purse_merges USING btree (reserve_pub);


--
-- Name: INDEX purse_merges_reserve_pub; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON INDEX exchange.purse_merges_reserve_pub IS 'needed in reserve history computation';


--
-- Name: purse_merges_default_reserve_pub_idx; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX purse_merges_default_reserve_pub_idx ON exchange.purse_merges_default USING btree (reserve_pub);


--
-- Name: purse_requests_merge_pub; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX purse_requests_merge_pub ON ONLY exchange.purse_requests USING btree (merge_pub);


--
-- Name: purse_requests_default_merge_pub_idx; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX purse_requests_default_merge_pub_idx ON exchange.purse_requests_default USING btree (merge_pub);


--
-- Name: purse_requests_purse_expiration; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX purse_requests_purse_expiration ON ONLY exchange.purse_requests USING btree (purse_expiration);


--
-- Name: purse_requests_default_purse_expiration_idx; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX purse_requests_default_purse_expiration_idx ON exchange.purse_requests_default USING btree (purse_expiration);


--
-- Name: recoup_by_coin_pub_index; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX recoup_by_coin_pub_index ON ONLY exchange.recoup USING btree (coin_pub);


--
-- Name: recoup_by_reserve_main_index; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX recoup_by_reserve_main_index ON ONLY exchange.recoup_by_reserve USING btree (reserve_out_serial_id);


--
-- Name: recoup_by_reserve_default_reserve_out_serial_id_idx; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX recoup_by_reserve_default_reserve_out_serial_id_idx ON exchange.recoup_by_reserve_default USING btree (reserve_out_serial_id);


--
-- Name: recoup_default_coin_pub_idx; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX recoup_default_coin_pub_idx ON exchange.recoup_default USING btree (coin_pub);


--
-- Name: recoup_refresh_by_coin_pub_index; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX recoup_refresh_by_coin_pub_index ON ONLY exchange.recoup_refresh USING btree (coin_pub);


--
-- Name: recoup_refresh_by_rrc_serial_index; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX recoup_refresh_by_rrc_serial_index ON ONLY exchange.recoup_refresh USING btree (rrc_serial);


--
-- Name: recoup_refresh_default_coin_pub_idx; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX recoup_refresh_default_coin_pub_idx ON exchange.recoup_refresh_default USING btree (coin_pub);


--
-- Name: recoup_refresh_default_rrc_serial_idx; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX recoup_refresh_default_rrc_serial_idx ON exchange.recoup_refresh_default USING btree (rrc_serial);


--
-- Name: refresh_commitments_by_old_coin_pub_index; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX refresh_commitments_by_old_coin_pub_index ON ONLY exchange.refresh_commitments USING btree (old_coin_pub);


--
-- Name: refresh_commitments_default_old_coin_pub_idx; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX refresh_commitments_default_old_coin_pub_idx ON exchange.refresh_commitments_default USING btree (old_coin_pub);


--
-- Name: refresh_revealed_coins_coins_by_melt_serial_id_index; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX refresh_revealed_coins_coins_by_melt_serial_id_index ON ONLY exchange.refresh_revealed_coins USING btree (melt_serial_id);


--
-- Name: refresh_revealed_coins_default_melt_serial_id_idx; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX refresh_revealed_coins_default_melt_serial_id_idx ON exchange.refresh_revealed_coins_default USING btree (melt_serial_id);


--
-- Name: refunds_by_coin_pub_index; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX refunds_by_coin_pub_index ON ONLY exchange.refunds USING btree (coin_pub);


--
-- Name: refunds_default_coin_pub_idx; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX refunds_default_coin_pub_idx ON exchange.refunds_default USING btree (coin_pub);


--
-- Name: reserves_by_expiration_index; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX reserves_by_expiration_index ON ONLY exchange.reserves USING btree (expiration_date, current_balance_val, current_balance_frac);


--
-- Name: INDEX reserves_by_expiration_index; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON INDEX exchange.reserves_by_expiration_index IS 'used in get_expired_reserves';


--
-- Name: reserves_by_gc_date_index; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX reserves_by_gc_date_index ON ONLY exchange.reserves USING btree (gc_date);


--
-- Name: INDEX reserves_by_gc_date_index; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON INDEX exchange.reserves_by_gc_date_index IS 'for reserve garbage collection';


--
-- Name: reserves_by_reserve_uuid_index; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX reserves_by_reserve_uuid_index ON ONLY exchange.reserves USING btree (reserve_uuid);


--
-- Name: reserves_close_by_close_uuid_index; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX reserves_close_by_close_uuid_index ON ONLY exchange.reserves_close USING btree (close_uuid);


--
-- Name: reserves_close_by_reserve_pub_index; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX reserves_close_by_reserve_pub_index ON ONLY exchange.reserves_close USING btree (reserve_pub);


--
-- Name: reserves_close_default_close_uuid_idx; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX reserves_close_default_close_uuid_idx ON exchange.reserves_close_default USING btree (close_uuid);


--
-- Name: reserves_close_default_reserve_pub_idx; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX reserves_close_default_reserve_pub_idx ON exchange.reserves_close_default USING btree (reserve_pub);


--
-- Name: reserves_default_expiration_date_current_balance_val_curren_idx; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX reserves_default_expiration_date_current_balance_val_curren_idx ON exchange.reserves_default USING btree (expiration_date, current_balance_val, current_balance_frac);


--
-- Name: reserves_default_gc_date_idx; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX reserves_default_gc_date_idx ON exchange.reserves_default USING btree (gc_date);


--
-- Name: reserves_default_reserve_uuid_idx; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX reserves_default_reserve_uuid_idx ON exchange.reserves_default USING btree (reserve_uuid);


--
-- Name: reserves_in_by_exch_accnt_reserve_in_serial_id_idx; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX reserves_in_by_exch_accnt_reserve_in_serial_id_idx ON ONLY exchange.reserves_in USING btree (exchange_account_section, reserve_in_serial_id DESC);


--
-- Name: reserves_in_by_exch_accnt_section_execution_date_idx; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX reserves_in_by_exch_accnt_section_execution_date_idx ON ONLY exchange.reserves_in USING btree (exchange_account_section, execution_date);


--
-- Name: reserves_in_by_reserve_in_serial_id_index; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX reserves_in_by_reserve_in_serial_id_index ON ONLY exchange.reserves_in USING btree (reserve_in_serial_id);


--
-- Name: reserves_in_default_exchange_account_section_execution_date_idx; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX reserves_in_default_exchange_account_section_execution_date_idx ON exchange.reserves_in_default USING btree (exchange_account_section, execution_date);


--
-- Name: reserves_in_default_exchange_account_section_reserve_in_ser_idx; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX reserves_in_default_exchange_account_section_reserve_in_ser_idx ON exchange.reserves_in_default USING btree (exchange_account_section, reserve_in_serial_id DESC);


--
-- Name: reserves_in_default_reserve_in_serial_id_idx; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX reserves_in_default_reserve_in_serial_id_idx ON exchange.reserves_in_default USING btree (reserve_in_serial_id);


--
-- Name: reserves_out_by_reserve_main_index; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX reserves_out_by_reserve_main_index ON ONLY exchange.reserves_out_by_reserve USING btree (reserve_uuid);


--
-- Name: reserves_out_by_reserve_default_reserve_uuid_idx; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX reserves_out_by_reserve_default_reserve_uuid_idx ON exchange.reserves_out_by_reserve_default USING btree (reserve_uuid);


--
-- Name: reserves_out_by_reserve_out_serial_id_index; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX reserves_out_by_reserve_out_serial_id_index ON ONLY exchange.reserves_out USING btree (reserve_out_serial_id);


--
-- Name: reserves_out_by_reserve_uuid_and_execution_date_index; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX reserves_out_by_reserve_uuid_and_execution_date_index ON ONLY exchange.reserves_out USING btree (reserve_uuid, execution_date);


--
-- Name: INDEX reserves_out_by_reserve_uuid_and_execution_date_index; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON INDEX exchange.reserves_out_by_reserve_uuid_and_execution_date_index IS 'for get_reserves_out and exchange_do_withdraw_limit_check';


--
-- Name: reserves_out_default_reserve_out_serial_id_idx; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX reserves_out_default_reserve_out_serial_id_idx ON exchange.reserves_out_default USING btree (reserve_out_serial_id);


--
-- Name: reserves_out_default_reserve_uuid_execution_date_idx; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX reserves_out_default_reserve_uuid_execution_date_idx ON exchange.reserves_out_default USING btree (reserve_uuid, execution_date);


--
-- Name: revolving_work_shards_by_job_name_active_last_attempt_index; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX revolving_work_shards_by_job_name_active_last_attempt_index ON exchange.revolving_work_shards USING btree (job_name, active, last_attempt);


--
-- Name: wad_in_entries_reserve_pub; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX wad_in_entries_reserve_pub ON ONLY exchange.wad_in_entries USING btree (reserve_pub);


--
-- Name: INDEX wad_in_entries_reserve_pub; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON INDEX exchange.wad_in_entries_reserve_pub IS 'needed in reserve history computation';


--
-- Name: wad_in_entries_default_reserve_pub_idx; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX wad_in_entries_default_reserve_pub_idx ON exchange.wad_in_entries_default USING btree (reserve_pub);


--
-- Name: wad_out_entries_by_reserve_pub; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX wad_out_entries_by_reserve_pub ON ONLY exchange.wad_out_entries USING btree (reserve_pub);


--
-- Name: wad_out_entries_default_reserve_pub_idx; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX wad_out_entries_default_reserve_pub_idx ON exchange.wad_out_entries_default USING btree (reserve_pub);


--
-- Name: wire_fee_by_end_date_index; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX wire_fee_by_end_date_index ON exchange.wire_fee USING btree (end_date);


--
-- Name: wire_out_by_wire_target_h_payto_index; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX wire_out_by_wire_target_h_payto_index ON ONLY exchange.wire_out USING btree (wire_target_h_payto);


--
-- Name: wire_out_default_wire_target_h_payto_idx; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX wire_out_default_wire_target_h_payto_idx ON exchange.wire_out_default USING btree (wire_target_h_payto);


--
-- Name: work_shards_by_job_name_completed_last_attempt_index; Type: INDEX; Schema: exchange; Owner: -
--

CREATE INDEX work_shards_by_job_name_completed_last_attempt_index ON exchange.work_shards USING btree (job_name, completed, last_attempt);


--
-- Name: merchant_contract_terms_by_expiration; Type: INDEX; Schema: merchant; Owner: -
--

CREATE INDEX merchant_contract_terms_by_expiration ON merchant.merchant_contract_terms USING btree (paid, pay_deadline);


--
-- Name: INDEX merchant_contract_terms_by_expiration; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON INDEX merchant.merchant_contract_terms_by_expiration IS 'for unlock_contracts';


--
-- Name: merchant_contract_terms_by_merchant_and_expiration; Type: INDEX; Schema: merchant; Owner: -
--

CREATE INDEX merchant_contract_terms_by_merchant_and_expiration ON merchant.merchant_contract_terms USING btree (merchant_serial, pay_deadline);


--
-- Name: INDEX merchant_contract_terms_by_merchant_and_expiration; Type: COMMENT; Schema: merchant; Owner: -
--

COMMENT ON INDEX merchant.merchant_contract_terms_by_merchant_and_expiration IS 'for delete_contract_terms';


--
-- Name: merchant_contract_terms_by_merchant_and_payment; Type: INDEX; Schema: merchant; Owner: -
--

CREATE INDEX merchant_contract_terms_by_merchant_and_payment ON merchant.merchant_contract_terms USING btree (merchant_serial, paid);


--
-- Name: merchant_contract_terms_by_merchant_session_and_fulfillment; Type: INDEX; Schema: merchant; Owner: -
--

CREATE INDEX merchant_contract_terms_by_merchant_session_and_fulfillment ON merchant.merchant_contract_terms USING btree (merchant_serial, fulfillment_url, session_id);


--
-- Name: merchant_inventory_locks_by_expiration; Type: INDEX; Schema: merchant; Owner: -
--

CREATE INDEX merchant_inventory_locks_by_expiration ON merchant.merchant_inventory_locks USING btree (expiration);


--
-- Name: merchant_inventory_locks_by_uuid; Type: INDEX; Schema: merchant; Owner: -
--

CREATE INDEX merchant_inventory_locks_by_uuid ON merchant.merchant_inventory_locks USING btree (lock_uuid);


--
-- Name: merchant_orders_by_creation_time; Type: INDEX; Schema: merchant; Owner: -
--

CREATE INDEX merchant_orders_by_creation_time ON merchant.merchant_orders USING btree (creation_time);


--
-- Name: merchant_orders_by_expiration; Type: INDEX; Schema: merchant; Owner: -
--

CREATE INDEX merchant_orders_by_expiration ON merchant.merchant_orders USING btree (pay_deadline);


--
-- Name: merchant_orders_locks_by_order_and_product; Type: INDEX; Schema: merchant; Owner: -
--

CREATE INDEX merchant_orders_locks_by_order_and_product ON merchant.merchant_order_locks USING btree (order_serial, product_serial);


--
-- Name: merchant_refunds_by_coin_and_order; Type: INDEX; Schema: merchant; Owner: -
--

CREATE INDEX merchant_refunds_by_coin_and_order ON merchant.merchant_refunds USING btree (coin_pub, order_serial);


--
-- Name: merchant_tip_reserves_by_exchange_balance; Type: INDEX; Schema: merchant; Owner: -
--

CREATE INDEX merchant_tip_reserves_by_exchange_balance ON merchant.merchant_tip_reserves USING btree (exchange_initial_balance_val, exchange_initial_balance_frac);


--
-- Name: merchant_tip_reserves_by_merchant_serial_and_creation_time; Type: INDEX; Schema: merchant; Owner: -
--

CREATE INDEX merchant_tip_reserves_by_merchant_serial_and_creation_time ON merchant.merchant_tip_reserves USING btree (merchant_serial, creation_time);


--
-- Name: merchant_tip_reserves_by_reserve_pub_and_merchant_serial; Type: INDEX; Schema: merchant; Owner: -
--

CREATE INDEX merchant_tip_reserves_by_reserve_pub_and_merchant_serial ON merchant.merchant_tip_reserves USING btree (reserve_pub, merchant_serial, creation_time);


--
-- Name: merchant_tips_by_pickup_and_expiration; Type: INDEX; Schema: merchant; Owner: -
--

CREATE INDEX merchant_tips_by_pickup_and_expiration ON merchant.merchant_tips USING btree (was_picked_up, expiration);


--
-- Name: merchant_transfers_by_credit; Type: INDEX; Schema: merchant; Owner: -
--

CREATE INDEX merchant_transfers_by_credit ON merchant.merchant_transfer_to_coin USING btree (credit_serial);


--
-- Name: account_merges_default_pkey; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.account_merges_pkey ATTACH PARTITION exchange.account_merges_default_pkey;


--
-- Name: account_merges_default_reserve_pub_idx; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.account_merges_by_reserve_pub ATTACH PARTITION exchange.account_merges_default_reserve_pub_idx;


--
-- Name: aggregation_tracking_default_pkey; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.aggregation_tracking_pkey ATTACH PARTITION exchange.aggregation_tracking_default_pkey;


--
-- Name: aggregation_tracking_default_wtid_raw_idx; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.aggregation_tracking_by_wtid_raw_index ATTACH PARTITION exchange.aggregation_tracking_default_wtid_raw_idx;


--
-- Name: close_requests_default_pkey; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.close_requests_pkey ATTACH PARTITION exchange.close_requests_default_pkey;


--
-- Name: contracts_default_pkey; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.contracts_pkey ATTACH PARTITION exchange.contracts_default_pkey;


--
-- Name: cs_nonce_locks_default_pkey; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.cs_nonce_locks_pkey ATTACH PARTITION exchange.cs_nonce_locks_default_pkey;


--
-- Name: deposits_by_ready_default_wire_deadline_shard_coin_pub_idx; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.deposits_by_ready_main_index ATTACH PARTITION exchange.deposits_by_ready_default_wire_deadline_shard_coin_pub_idx;


--
-- Name: deposits_default_coin_pub_idx; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.deposits_by_coin_pub_index ATTACH PARTITION exchange.deposits_default_coin_pub_idx;


--
-- Name: deposits_for_matching_default_refund_deadline_merchant_pub__idx; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.deposits_for_matching_main_index ATTACH PARTITION exchange.deposits_for_matching_default_refund_deadline_merchant_pub__idx;


--
-- Name: extension_details_default_pkey; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.extension_details_pkey ATTACH PARTITION exchange.extension_details_default_pkey;


--
-- Name: history_requests_default_pkey; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.history_requests_pkey ATTACH PARTITION exchange.history_requests_default_pkey;


--
-- Name: known_coins_default_pkey; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.known_coins_pkey ATTACH PARTITION exchange.known_coins_default_pkey;


--
-- Name: legitimizations_default_h_payto_provider_section_key; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.legitimizations_h_payto_provider_section_key ATTACH PARTITION exchange.legitimizations_default_h_payto_provider_section_key;


--
-- Name: prewire_default_failed_finished_idx; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.prewire_by_failed_finished_index ATTACH PARTITION exchange.prewire_default_failed_finished_idx;


--
-- Name: prewire_default_finished_idx; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.prewire_by_finished_index ATTACH PARTITION exchange.prewire_default_finished_idx;


--
-- Name: prewire_default_pkey; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.prewire_pkey ATTACH PARTITION exchange.prewire_default_pkey;


--
-- Name: purse_deposits_default_coin_pub_idx; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.purse_deposits_by_coin_pub ATTACH PARTITION exchange.purse_deposits_default_coin_pub_idx;


--
-- Name: purse_deposits_default_pkey; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.purse_deposits_pkey ATTACH PARTITION exchange.purse_deposits_default_pkey;


--
-- Name: purse_merges_default_pkey; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.purse_merges_pkey ATTACH PARTITION exchange.purse_merges_default_pkey;


--
-- Name: purse_merges_default_reserve_pub_idx; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.purse_merges_reserve_pub ATTACH PARTITION exchange.purse_merges_default_reserve_pub_idx;


--
-- Name: purse_refunds_default_pkey; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.purse_refunds_pkey ATTACH PARTITION exchange.purse_refunds_default_pkey;


--
-- Name: purse_requests_default_merge_pub_idx; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.purse_requests_merge_pub ATTACH PARTITION exchange.purse_requests_default_merge_pub_idx;


--
-- Name: purse_requests_default_pkey; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.purse_requests_pkey ATTACH PARTITION exchange.purse_requests_default_pkey;


--
-- Name: purse_requests_default_purse_expiration_idx; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.purse_requests_purse_expiration ATTACH PARTITION exchange.purse_requests_default_purse_expiration_idx;


--
-- Name: recoup_by_reserve_default_reserve_out_serial_id_idx; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.recoup_by_reserve_main_index ATTACH PARTITION exchange.recoup_by_reserve_default_reserve_out_serial_id_idx;


--
-- Name: recoup_default_coin_pub_idx; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.recoup_by_coin_pub_index ATTACH PARTITION exchange.recoup_default_coin_pub_idx;


--
-- Name: recoup_refresh_default_coin_pub_idx; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.recoup_refresh_by_coin_pub_index ATTACH PARTITION exchange.recoup_refresh_default_coin_pub_idx;


--
-- Name: recoup_refresh_default_rrc_serial_idx; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.recoup_refresh_by_rrc_serial_index ATTACH PARTITION exchange.recoup_refresh_default_rrc_serial_idx;


--
-- Name: refresh_commitments_default_old_coin_pub_idx; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.refresh_commitments_by_old_coin_pub_index ATTACH PARTITION exchange.refresh_commitments_default_old_coin_pub_idx;


--
-- Name: refresh_commitments_default_pkey; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.refresh_commitments_pkey ATTACH PARTITION exchange.refresh_commitments_default_pkey;


--
-- Name: refresh_revealed_coins_default_melt_serial_id_idx; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.refresh_revealed_coins_coins_by_melt_serial_id_index ATTACH PARTITION exchange.refresh_revealed_coins_default_melt_serial_id_idx;


--
-- Name: refresh_transfer_keys_default_pkey; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.refresh_transfer_keys_pkey ATTACH PARTITION exchange.refresh_transfer_keys_default_pkey;


--
-- Name: refunds_default_coin_pub_idx; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.refunds_by_coin_pub_index ATTACH PARTITION exchange.refunds_default_coin_pub_idx;


--
-- Name: reserves_close_default_close_uuid_idx; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.reserves_close_by_close_uuid_index ATTACH PARTITION exchange.reserves_close_default_close_uuid_idx;


--
-- Name: reserves_close_default_reserve_pub_idx; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.reserves_close_by_reserve_pub_index ATTACH PARTITION exchange.reserves_close_default_reserve_pub_idx;


--
-- Name: reserves_default_expiration_date_current_balance_val_curren_idx; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.reserves_by_expiration_index ATTACH PARTITION exchange.reserves_default_expiration_date_current_balance_val_curren_idx;


--
-- Name: reserves_default_gc_date_idx; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.reserves_by_gc_date_index ATTACH PARTITION exchange.reserves_default_gc_date_idx;


--
-- Name: reserves_default_pkey; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.reserves_pkey ATTACH PARTITION exchange.reserves_default_pkey;


--
-- Name: reserves_default_reserve_uuid_idx; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.reserves_by_reserve_uuid_index ATTACH PARTITION exchange.reserves_default_reserve_uuid_idx;


--
-- Name: reserves_in_default_exchange_account_section_execution_date_idx; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.reserves_in_by_exch_accnt_section_execution_date_idx ATTACH PARTITION exchange.reserves_in_default_exchange_account_section_execution_date_idx;


--
-- Name: reserves_in_default_exchange_account_section_reserve_in_ser_idx; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.reserves_in_by_exch_accnt_reserve_in_serial_id_idx ATTACH PARTITION exchange.reserves_in_default_exchange_account_section_reserve_in_ser_idx;


--
-- Name: reserves_in_default_pkey; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.reserves_in_pkey ATTACH PARTITION exchange.reserves_in_default_pkey;


--
-- Name: reserves_in_default_reserve_in_serial_id_idx; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.reserves_in_by_reserve_in_serial_id_index ATTACH PARTITION exchange.reserves_in_default_reserve_in_serial_id_idx;


--
-- Name: reserves_out_by_reserve_default_reserve_uuid_idx; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.reserves_out_by_reserve_main_index ATTACH PARTITION exchange.reserves_out_by_reserve_default_reserve_uuid_idx;


--
-- Name: reserves_out_default_h_blind_ev_key; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.reserves_out_h_blind_ev_key ATTACH PARTITION exchange.reserves_out_default_h_blind_ev_key;


--
-- Name: reserves_out_default_reserve_out_serial_id_idx; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.reserves_out_by_reserve_out_serial_id_index ATTACH PARTITION exchange.reserves_out_default_reserve_out_serial_id_idx;


--
-- Name: reserves_out_default_reserve_uuid_execution_date_idx; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.reserves_out_by_reserve_uuid_and_execution_date_index ATTACH PARTITION exchange.reserves_out_default_reserve_uuid_execution_date_idx;


--
-- Name: wad_in_entries_default_pkey; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.wad_in_entries_pkey ATTACH PARTITION exchange.wad_in_entries_default_pkey;


--
-- Name: wad_in_entries_default_reserve_pub_idx; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.wad_in_entries_reserve_pub ATTACH PARTITION exchange.wad_in_entries_default_reserve_pub_idx;


--
-- Name: wad_out_entries_default_pkey; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.wad_out_entries_pkey ATTACH PARTITION exchange.wad_out_entries_default_pkey;


--
-- Name: wad_out_entries_default_reserve_pub_idx; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.wad_out_entries_by_reserve_pub ATTACH PARTITION exchange.wad_out_entries_default_reserve_pub_idx;


--
-- Name: wads_in_default_pkey; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.wads_in_pkey ATTACH PARTITION exchange.wads_in_default_pkey;


--
-- Name: wads_in_default_wad_id_origin_exchange_url_key; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.wads_in_wad_id_origin_exchange_url_key ATTACH PARTITION exchange.wads_in_default_wad_id_origin_exchange_url_key;


--
-- Name: wads_out_default_pkey; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.wads_out_pkey ATTACH PARTITION exchange.wads_out_default_pkey;


--
-- Name: wire_out_default_wire_target_h_payto_idx; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.wire_out_by_wire_target_h_payto_index ATTACH PARTITION exchange.wire_out_default_wire_target_h_payto_idx;


--
-- Name: wire_out_default_wtid_raw_key; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.wire_out_wtid_raw_key ATTACH PARTITION exchange.wire_out_default_wtid_raw_key;


--
-- Name: wire_targets_default_pkey; Type: INDEX ATTACH; Schema: exchange; Owner: -
--

ALTER INDEX exchange.wire_targets_pkey ATTACH PARTITION exchange.wire_targets_default_pkey;


--
-- Name: deposits deposits_on_delete; Type: TRIGGER; Schema: exchange; Owner: -
--

CREATE TRIGGER deposits_on_delete AFTER DELETE ON exchange.deposits FOR EACH ROW EXECUTE FUNCTION exchange.deposits_delete_trigger();


--
-- Name: deposits deposits_on_insert; Type: TRIGGER; Schema: exchange; Owner: -
--

CREATE TRIGGER deposits_on_insert AFTER INSERT ON exchange.deposits FOR EACH ROW EXECUTE FUNCTION exchange.deposits_insert_trigger();


--
-- Name: deposits deposits_on_update; Type: TRIGGER; Schema: exchange; Owner: -
--

CREATE TRIGGER deposits_on_update AFTER UPDATE ON exchange.deposits FOR EACH ROW EXECUTE FUNCTION exchange.deposits_update_trigger();


--
-- Name: purse_requests purse_requests_on_insert; Type: TRIGGER; Schema: exchange; Owner: -
--

CREATE TRIGGER purse_requests_on_insert AFTER INSERT ON exchange.purse_requests FOR EACH ROW EXECUTE FUNCTION exchange.purse_requests_insert_trigger();


--
-- Name: TRIGGER purse_requests_on_insert ON purse_requests; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TRIGGER purse_requests_on_insert ON exchange.purse_requests IS 'Here we install an entry for the purse expiration.';


--
-- Name: purse_requests purse_requests_on_update; Type: TRIGGER; Schema: exchange; Owner: -
--

CREATE TRIGGER purse_requests_on_update BEFORE UPDATE ON exchange.purse_requests FOR EACH ROW EXECUTE FUNCTION exchange.purse_requests_on_update_trigger();


--
-- Name: TRIGGER purse_requests_on_update ON purse_requests; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON TRIGGER purse_requests_on_update ON exchange.purse_requests IS 'This covers the case where a deposit is made into a purse, which inherently then changes the purse balance via an UPDATE. If the merge is already present and the balance matches the total, we trigger the router. Once the router sets the purse to finished, the trigger will remove the purse from the watchlist of the router.';


--
-- Name: recoup recoup_on_delete; Type: TRIGGER; Schema: exchange; Owner: -
--

CREATE TRIGGER recoup_on_delete AFTER DELETE ON exchange.recoup FOR EACH ROW EXECUTE FUNCTION exchange.recoup_delete_trigger();


--
-- Name: recoup recoup_on_insert; Type: TRIGGER; Schema: exchange; Owner: -
--

CREATE TRIGGER recoup_on_insert AFTER INSERT ON exchange.recoup FOR EACH ROW EXECUTE FUNCTION exchange.recoup_insert_trigger();


--
-- Name: reserves_out reserves_out_on_delete; Type: TRIGGER; Schema: exchange; Owner: -
--

CREATE TRIGGER reserves_out_on_delete AFTER DELETE ON exchange.reserves_out FOR EACH ROW EXECUTE FUNCTION exchange.reserves_out_by_reserve_delete_trigger();


--
-- Name: reserves_out reserves_out_on_insert; Type: TRIGGER; Schema: exchange; Owner: -
--

CREATE TRIGGER reserves_out_on_insert AFTER INSERT ON exchange.reserves_out FOR EACH ROW EXECUTE FUNCTION exchange.reserves_out_by_reserve_insert_trigger();


--
-- Name: wire_out wire_out_on_delete; Type: TRIGGER; Schema: exchange; Owner: -
--

CREATE TRIGGER wire_out_on_delete AFTER DELETE ON exchange.wire_out FOR EACH ROW EXECUTE FUNCTION exchange.wire_out_delete_trigger();


--
-- Name: auditor_exchange_signkeys master_pub_ref; Type: FK CONSTRAINT; Schema: auditor; Owner: -
--

ALTER TABLE ONLY auditor.auditor_exchange_signkeys
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES auditor.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_progress_reserve master_pub_ref; Type: FK CONSTRAINT; Schema: auditor; Owner: -
--

ALTER TABLE ONLY auditor.auditor_progress_reserve
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES auditor.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_progress_aggregation master_pub_ref; Type: FK CONSTRAINT; Schema: auditor; Owner: -
--

ALTER TABLE ONLY auditor.auditor_progress_aggregation
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES auditor.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_progress_deposit_confirmation master_pub_ref; Type: FK CONSTRAINT; Schema: auditor; Owner: -
--

ALTER TABLE ONLY auditor.auditor_progress_deposit_confirmation
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES auditor.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_progress_coin master_pub_ref; Type: FK CONSTRAINT; Schema: auditor; Owner: -
--

ALTER TABLE ONLY auditor.auditor_progress_coin
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES auditor.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: wire_auditor_account_progress master_pub_ref; Type: FK CONSTRAINT; Schema: auditor; Owner: -
--

ALTER TABLE ONLY auditor.wire_auditor_account_progress
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES auditor.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: wire_auditor_progress master_pub_ref; Type: FK CONSTRAINT; Schema: auditor; Owner: -
--

ALTER TABLE ONLY auditor.wire_auditor_progress
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES auditor.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_reserves master_pub_ref; Type: FK CONSTRAINT; Schema: auditor; Owner: -
--

ALTER TABLE ONLY auditor.auditor_reserves
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES auditor.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_reserve_balance master_pub_ref; Type: FK CONSTRAINT; Schema: auditor; Owner: -
--

ALTER TABLE ONLY auditor.auditor_reserve_balance
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES auditor.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_wire_fee_balance master_pub_ref; Type: FK CONSTRAINT; Schema: auditor; Owner: -
--

ALTER TABLE ONLY auditor.auditor_wire_fee_balance
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES auditor.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_balance_summary master_pub_ref; Type: FK CONSTRAINT; Schema: auditor; Owner: -
--

ALTER TABLE ONLY auditor.auditor_balance_summary
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES auditor.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_historic_denomination_revenue master_pub_ref; Type: FK CONSTRAINT; Schema: auditor; Owner: -
--

ALTER TABLE ONLY auditor.auditor_historic_denomination_revenue
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES auditor.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_historic_reserve_summary master_pub_ref; Type: FK CONSTRAINT; Schema: auditor; Owner: -
--

ALTER TABLE ONLY auditor.auditor_historic_reserve_summary
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES auditor.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: deposit_confirmations master_pub_ref; Type: FK CONSTRAINT; Schema: auditor; Owner: -
--

ALTER TABLE ONLY auditor.deposit_confirmations
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES auditor.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_predicted_result master_pub_ref; Type: FK CONSTRAINT; Schema: auditor; Owner: -
--

ALTER TABLE ONLY auditor.auditor_predicted_result
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES auditor.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_denom_sigs auditor_denom_sigs_auditor_uuid_fkey; Type: FK CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.auditor_denom_sigs
    ADD CONSTRAINT auditor_denom_sigs_auditor_uuid_fkey FOREIGN KEY (auditor_uuid) REFERENCES exchange.auditors(auditor_uuid) ON DELETE CASCADE;


--
-- Name: auditor_denom_sigs auditor_denom_sigs_denominations_serial_fkey; Type: FK CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.auditor_denom_sigs
    ADD CONSTRAINT auditor_denom_sigs_denominations_serial_fkey FOREIGN KEY (denominations_serial) REFERENCES exchange.denominations(denominations_serial) ON DELETE CASCADE;


--
-- Name: denomination_revocations denomination_revocations_denominations_serial_fkey; Type: FK CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.denomination_revocations
    ADD CONSTRAINT denomination_revocations_denominations_serial_fkey FOREIGN KEY (denominations_serial) REFERENCES exchange.denominations(denominations_serial) ON DELETE CASCADE;


--
-- Name: partner_accounts partner_accounts_partner_serial_id_fkey; Type: FK CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.partner_accounts
    ADD CONSTRAINT partner_accounts_partner_serial_id_fkey FOREIGN KEY (partner_serial_id) REFERENCES exchange.partners(partner_serial_id) ON DELETE CASCADE;


--
-- Name: signkey_revocations signkey_revocations_esk_serial_fkey; Type: FK CONSTRAINT; Schema: exchange; Owner: -
--

ALTER TABLE ONLY exchange.signkey_revocations
    ADD CONSTRAINT signkey_revocations_esk_serial_fkey FOREIGN KEY (esk_serial) REFERENCES exchange.exchange_sign_keys(esk_serial) ON DELETE CASCADE;


--
-- Name: merchant_accounts merchant_accounts_merchant_serial_fkey; Type: FK CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_accounts
    ADD CONSTRAINT merchant_accounts_merchant_serial_fkey FOREIGN KEY (merchant_serial) REFERENCES merchant.merchant_instances(merchant_serial) ON DELETE CASCADE;


--
-- Name: merchant_contract_terms merchant_contract_terms_merchant_serial_fkey; Type: FK CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_contract_terms
    ADD CONSTRAINT merchant_contract_terms_merchant_serial_fkey FOREIGN KEY (merchant_serial) REFERENCES merchant.merchant_instances(merchant_serial) ON DELETE CASCADE;


--
-- Name: merchant_deposit_to_transfer merchant_deposit_to_transfer_credit_serial_fkey; Type: FK CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_deposit_to_transfer
    ADD CONSTRAINT merchant_deposit_to_transfer_credit_serial_fkey FOREIGN KEY (credit_serial) REFERENCES merchant.merchant_transfers(credit_serial);


--
-- Name: merchant_deposit_to_transfer merchant_deposit_to_transfer_deposit_serial_fkey; Type: FK CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_deposit_to_transfer
    ADD CONSTRAINT merchant_deposit_to_transfer_deposit_serial_fkey FOREIGN KEY (deposit_serial) REFERENCES merchant.merchant_deposits(deposit_serial) ON DELETE CASCADE;


--
-- Name: merchant_deposit_to_transfer merchant_deposit_to_transfer_signkey_serial_fkey; Type: FK CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_deposit_to_transfer
    ADD CONSTRAINT merchant_deposit_to_transfer_signkey_serial_fkey FOREIGN KEY (signkey_serial) REFERENCES merchant.merchant_exchange_signing_keys(signkey_serial) ON DELETE CASCADE;


--
-- Name: merchant_deposits merchant_deposits_account_serial_fkey; Type: FK CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_deposits
    ADD CONSTRAINT merchant_deposits_account_serial_fkey FOREIGN KEY (account_serial) REFERENCES merchant.merchant_accounts(account_serial) ON DELETE CASCADE;


--
-- Name: merchant_deposits merchant_deposits_order_serial_fkey; Type: FK CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_deposits
    ADD CONSTRAINT merchant_deposits_order_serial_fkey FOREIGN KEY (order_serial) REFERENCES merchant.merchant_contract_terms(order_serial) ON DELETE CASCADE;


--
-- Name: merchant_deposits merchant_deposits_signkey_serial_fkey; Type: FK CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_deposits
    ADD CONSTRAINT merchant_deposits_signkey_serial_fkey FOREIGN KEY (signkey_serial) REFERENCES merchant.merchant_exchange_signing_keys(signkey_serial) ON DELETE CASCADE;


--
-- Name: merchant_inventory_locks merchant_inventory_locks_product_serial_fkey; Type: FK CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_inventory_locks
    ADD CONSTRAINT merchant_inventory_locks_product_serial_fkey FOREIGN KEY (product_serial) REFERENCES merchant.merchant_inventory(product_serial);


--
-- Name: merchant_inventory merchant_inventory_merchant_serial_fkey; Type: FK CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_inventory
    ADD CONSTRAINT merchant_inventory_merchant_serial_fkey FOREIGN KEY (merchant_serial) REFERENCES merchant.merchant_instances(merchant_serial) ON DELETE CASCADE;


--
-- Name: merchant_keys merchant_keys_merchant_serial_fkey; Type: FK CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_keys
    ADD CONSTRAINT merchant_keys_merchant_serial_fkey FOREIGN KEY (merchant_serial) REFERENCES merchant.merchant_instances(merchant_serial) ON DELETE CASCADE;


--
-- Name: merchant_kyc merchant_kyc_account_serial_fkey; Type: FK CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_kyc
    ADD CONSTRAINT merchant_kyc_account_serial_fkey FOREIGN KEY (account_serial) REFERENCES merchant.merchant_accounts(account_serial) ON DELETE CASCADE;


--
-- Name: merchant_order_locks merchant_order_locks_order_serial_fkey; Type: FK CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_order_locks
    ADD CONSTRAINT merchant_order_locks_order_serial_fkey FOREIGN KEY (order_serial) REFERENCES merchant.merchant_orders(order_serial) ON DELETE CASCADE;


--
-- Name: merchant_order_locks merchant_order_locks_product_serial_fkey; Type: FK CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_order_locks
    ADD CONSTRAINT merchant_order_locks_product_serial_fkey FOREIGN KEY (product_serial) REFERENCES merchant.merchant_inventory(product_serial);


--
-- Name: merchant_orders merchant_orders_merchant_serial_fkey; Type: FK CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_orders
    ADD CONSTRAINT merchant_orders_merchant_serial_fkey FOREIGN KEY (merchant_serial) REFERENCES merchant.merchant_instances(merchant_serial) ON DELETE CASCADE;


--
-- Name: merchant_refund_proofs merchant_refund_proofs_refund_serial_fkey; Type: FK CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_refund_proofs
    ADD CONSTRAINT merchant_refund_proofs_refund_serial_fkey FOREIGN KEY (refund_serial) REFERENCES merchant.merchant_refunds(refund_serial) ON DELETE CASCADE;


--
-- Name: merchant_refund_proofs merchant_refund_proofs_signkey_serial_fkey; Type: FK CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_refund_proofs
    ADD CONSTRAINT merchant_refund_proofs_signkey_serial_fkey FOREIGN KEY (signkey_serial) REFERENCES merchant.merchant_exchange_signing_keys(signkey_serial) ON DELETE CASCADE;


--
-- Name: merchant_refunds merchant_refunds_order_serial_fkey; Type: FK CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_refunds
    ADD CONSTRAINT merchant_refunds_order_serial_fkey FOREIGN KEY (order_serial) REFERENCES merchant.merchant_contract_terms(order_serial) ON DELETE CASCADE;


--
-- Name: merchant_tip_pickup_signatures merchant_tip_pickup_signatures_pickup_serial_fkey; Type: FK CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_tip_pickup_signatures
    ADD CONSTRAINT merchant_tip_pickup_signatures_pickup_serial_fkey FOREIGN KEY (pickup_serial) REFERENCES merchant.merchant_tip_pickups(pickup_serial) ON DELETE CASCADE;


--
-- Name: merchant_tip_pickups merchant_tip_pickups_tip_serial_fkey; Type: FK CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_tip_pickups
    ADD CONSTRAINT merchant_tip_pickups_tip_serial_fkey FOREIGN KEY (tip_serial) REFERENCES merchant.merchant_tips(tip_serial) ON DELETE CASCADE;


--
-- Name: merchant_tip_reserve_keys merchant_tip_reserve_keys_reserve_serial_fkey; Type: FK CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_tip_reserve_keys
    ADD CONSTRAINT merchant_tip_reserve_keys_reserve_serial_fkey FOREIGN KEY (reserve_serial) REFERENCES merchant.merchant_tip_reserves(reserve_serial) ON DELETE CASCADE;


--
-- Name: merchant_tip_reserves merchant_tip_reserves_merchant_serial_fkey; Type: FK CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_tip_reserves
    ADD CONSTRAINT merchant_tip_reserves_merchant_serial_fkey FOREIGN KEY (merchant_serial) REFERENCES merchant.merchant_instances(merchant_serial) ON DELETE CASCADE;


--
-- Name: merchant_tips merchant_tips_reserve_serial_fkey; Type: FK CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_tips
    ADD CONSTRAINT merchant_tips_reserve_serial_fkey FOREIGN KEY (reserve_serial) REFERENCES merchant.merchant_tip_reserves(reserve_serial) ON DELETE CASCADE;


--
-- Name: merchant_transfer_signatures merchant_transfer_signatures_credit_serial_fkey; Type: FK CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_transfer_signatures
    ADD CONSTRAINT merchant_transfer_signatures_credit_serial_fkey FOREIGN KEY (credit_serial) REFERENCES merchant.merchant_transfers(credit_serial) ON DELETE CASCADE;


--
-- Name: merchant_transfer_signatures merchant_transfer_signatures_signkey_serial_fkey; Type: FK CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_transfer_signatures
    ADD CONSTRAINT merchant_transfer_signatures_signkey_serial_fkey FOREIGN KEY (signkey_serial) REFERENCES merchant.merchant_exchange_signing_keys(signkey_serial) ON DELETE CASCADE;


--
-- Name: merchant_transfer_to_coin merchant_transfer_to_coin_credit_serial_fkey; Type: FK CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_transfer_to_coin
    ADD CONSTRAINT merchant_transfer_to_coin_credit_serial_fkey FOREIGN KEY (credit_serial) REFERENCES merchant.merchant_transfers(credit_serial) ON DELETE CASCADE;


--
-- Name: merchant_transfer_to_coin merchant_transfer_to_coin_deposit_serial_fkey; Type: FK CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_transfer_to_coin
    ADD CONSTRAINT merchant_transfer_to_coin_deposit_serial_fkey FOREIGN KEY (deposit_serial) REFERENCES merchant.merchant_deposits(deposit_serial) ON DELETE CASCADE;


--
-- Name: merchant_transfers merchant_transfers_account_serial_fkey; Type: FK CONSTRAINT; Schema: merchant; Owner: -
--

ALTER TABLE ONLY merchant.merchant_transfers
    ADD CONSTRAINT merchant_transfers_account_serial_fkey FOREIGN KEY (account_serial) REFERENCES merchant.merchant_accounts(account_serial) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

