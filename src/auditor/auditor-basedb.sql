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
    amount_frac integer NOT NULL,
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
exchange-0001	2022-08-14 23:25:10.682499+02	grothoff	{}	{}
merchant-0001	2022-08-14 23:25:11.739394+02	grothoff	{}	{}
merchant-0002	2022-08-14 23:25:12.152431+02	grothoff	{}	{}
auditor-0001	2022-08-14 23:25:12.279332+02	grothoff	{}	{}
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
\\xbf29be54f7e3f7eead459f05a19dae8dd447c2263bf56744e731bb3997f322c1	1660512326000000	1667769926000000	1670189126000000	\\x3e6f96219a5496cbeb7505d5a3681d2e2320f472a5e6c66051e2b5ac7433e8e6	\\x40839256784eb80ca73d436caf4494f82eaf0e85ac151127b9e5cc0f10f7b0e6d54403bd395126008cead15b908aad1cfa3af61bc85ab1668c43598ff4b1840e
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: auditor; Owner: -
--

COPY auditor.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\xbf29be54f7e3f7eead459f05a19dae8dd447c2263bf56744e731bb3997f322c1	http://localhost:8081/
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
\\xbf29be54f7e3f7eead459f05a19dae8dd447c2263bf56744e731bb3997f322c1	1	\\x1dc78c0db550fb6dd5f6584331beca9f12a6360a01bf320ba171764c323e3eb954165ac652eafa48f616b71d21091a3b5c37bbee194fe0a4ccc04c45cdd13d14	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\xf47970a8b8271fa73af3ca50f28187ed10632f8fdfd96cfdc8beb9776e3aef07232a6533dc58e53bde4abbcf6f77741f510b2178cfb011abeb70d4898d5382bd	1660512344000000	1660513242000000	1660513242000000	3	98000000	\\x2b1e50c6417270e052ecfe4cda4a7831c5cca061b59b9cccb0163d6f3ea46ea0	\\x13074fb0cf0afb2d553acb2113c69d0aaf62b3d15ae83b7c812dfc121c060aa7	\\x06140e8bdf036034320d6db2ee2b133a3dfe83f1f0a2ecd0fc9a1e35f77fe9e64a351fb3a061ef72c681c011398fcd3c46865df317bac4b7b515e95a095ad506	\\x3e6f96219a5496cbeb7505d5a3681d2e2320f472a5e6c66051e2b5ac7433e8e6	\\x60aee1a9fc7f00001d39c0b0f7550000ddfa11b1f75500003afa11b1f755000020fa11b1f755000024fa11b1f7550000807e11b1f75500000000000000000000
\\xbf29be54f7e3f7eead459f05a19dae8dd447c2263bf56744e731bb3997f322c1	2	\\xea76029b68f01208d37a9546ecb802330bbd2f754612cd6528a3cf97a6431802fddd7f52eb7455493fd0bc7de53af1ee195061b124887804652084e05fd0324a	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\xf47970a8b8271fa73af3ca50f28187ed10632f8fdfd96cfdc8beb9776e3aef07232a6533dc58e53bde4abbcf6f77741f510b2178cfb011abeb70d4898d5382bd	1660512351000000	1660513249000000	1660513249000000	6	99000000	\\x4e35a55b7764fb8f7f612e274a53d196543db4c5faf347dd6994502cfe098caf	\\x13074fb0cf0afb2d553acb2113c69d0aaf62b3d15ae83b7c812dfc121c060aa7	\\x2f4683e2307c63c1b8eb152179d8466c04f4dde7971a50f4503264e3696c01fd10d24c6b3d7364fbc8b5ffaf7cf495ad88b75d6dcfcdd7a337cf276226591504	\\x3e6f96219a5496cbeb7505d5a3681d2e2320f472a5e6c66051e2b5ac7433e8e6	\\x60aee1a9fc7f00001d39c0b0f7550000fdba12b1f75500005aba12b1f755000040ba12b1f755000044ba12b1f755000070df11b1f75500000000000000000000
\\xbf29be54f7e3f7eead459f05a19dae8dd447c2263bf56744e731bb3997f322c1	3	\\x7025824934f4bfdccb0766a8eb445f80afd82bc969eb775ba9a637b0f4767ebd5ebb7cc01fcab0cea3639759047856e14a5ba97d620b5da2d0b6ab3e8b0ebeaf	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\xf47970a8b8271fa73af3ca50f28187ed10632f8fdfd96cfdc8beb9776e3aef07232a6533dc58e53bde4abbcf6f77741f510b2178cfb011abeb70d4898d5382bd	1660512358000000	1660513255000000	1660513255000000	2	99000000	\\x6936d088922587535a3b521583419cb22e24fa8bf7e384c6fab77d826ecf155a	\\x13074fb0cf0afb2d553acb2113c69d0aaf62b3d15ae83b7c812dfc121c060aa7	\\x903bd10cc48d3a923697b3fede90b33f93299bd981c2a7c80896ed395a78c7f91cfb58703ea210264ac176782affa8097eccca2c019bac0dd6833bfe9037fe02	\\x3e6f96219a5496cbeb7505d5a3681d2e2320f472a5e6c66051e2b5ac7433e8e6	\\x60aee1a9fc7f00001d39c0b0f7550000ddfa11b1f75500003afa11b1f755000020fa11b1f755000024fa11b1f7550000b0f411b1f75500000000000000000000
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
1	1	29	\\xe92e5b24854c8a00be6f49bc1ee362116779fc89b69bab7f31379a94d1cef851caf359ff07e05175a5b3b1b993dcc950c8a89a319e287417621847c6c35faa08
2	1	93	\\xc7794075e236a76e20483e7d7e17d3698cec1b46029f11c7f9cd4025d7ce481ccd29164abdf0591312478344d0e55b0298ad09c4776e25b57ed9a4badc82bd03
3	1	407	\\x07ce1af4e1eaab570d376af6b1296df0a91930c5e96cc7245459f93b7d6a39d1870b2e073886de72bfb029adbcfc61ee26a837d858d1b274f80a730a33b8980d
4	1	136	\\xbe0253ab48b9fcb73d0b88fe32948510ad4917c58e921ebabb01dc6150a157f6d293549e471a28236f4b0ddc7ebdbcb4a5b91c965704f14e4a772c7eded73e07
5	1	45	\\x56f13ac499ab633609f4c46d016a0e02e1ded8cbf0c2212adf047791832480c02b5410d5ffdada7d4ae20a9e7d03a1a287f0fa49499d8765b488ca582efbe600
6	1	195	\\x7eb4f7325f7e5ab6511e25d52136c9318b73c89f6198f8c5d6b7bc7a9719409262b02cb3b9ce02c0364d6daa2576df0da54694989f45f9c930fbf7b61d55ba0f
7	1	99	\\x1b3745c67b8089879981f7caedca712bea1f9986e0d4b04f8a0c21c59f71274dff9b6d237e8632c67c7e0b403dc896b457daab5f0d2d0460c1fe9e317db5de0b
8	1	368	\\x4232f80c442b47c0dd0a68c16354016fed9aa668e53a243b033baf2c823793470ceeb13835cb6fa833f6fce7b0acdfed84efae520a1973b63b8b9499d26dd700
9	1	248	\\xb50704f87e0e13ad02080fdf9bdd4029c1e6f1e1ba3b30c00c49993282095346801b752ec1673f173ea8fb694c6c0cd915800e1253857af191c6e413daced008
10	1	134	\\x119bba376cf21da5de427f4da3aa5f4c87d615fdd7b1ab96da350930f7350c38dd333065f77a222a023225c6f715c9498bd5a4108bae19ebf238fcf25fd26702
11	1	353	\\xc3e45cfeb75d822d766522fcabaecaef8ce2248f4831cdd4a013a42f74bf8a79bb310976dd9520b49a53864f2042481ff247adea5a820addf32cf12726cde706
12	1	205	\\x3a867b21c9ffa22c14f9927bc21d75e9675703bc3090c4e322f4d139e07a4cef388cf687d912b1676e920d46b4aaa75d525cbc997f5105a448f16731ad92cd00
13	1	255	\\xb5e55a746d48f5057f92b552adab5a437fbe66682989362e07a73556db573199b30acb93c7118f7c05c0d763879eeb7ba17fc20a6b90859fbcc6365be129fa05
14	1	316	\\x9b2055eb814a92da0c68fd9f98eac2c4bfbbade0523e01af7cebfa4832c9a2fdf9bab53f4ec3358bfa013de4da13d745c7a2b7eeec0939739331d45c8a34710f
15	1	355	\\xdcde16720f3ed8aec94ea8735f81ef8a82ff43575c063140009cb2371713be31f422a2d7fd048b6c1989ca685c5b42a70345af50940acfe9e1c37da856793c01
16	1	364	\\x29907361a42e5d3cf5537de6b6357119d3d32314f415708d9c8e6533c0b5f9129c79e885a2d2bc2c0a33d76eeac76107b0bdf8a4ce4206cc40714ae4058ce101
17	1	269	\\xe2bcda412f57a2ac08aad274c46504a2bbd57c80aca353b96a1a997d71dbeffe33b828231b02dd1d3bf6f829ed380dd9dc258275b9914cf9ffc72770d7f8dc0d
18	1	95	\\xcbf38c54189ac11457cb32fd99a310018b35e93a9d22735e60341a3b5f4d4730b3f3f3f517a093ca459752ea152eda154cb338f9bbe746b6fed522fe54a2fe01
19	1	292	\\xf4c072ebeb51096f9ef66c246143c2147a62a3220b47dc645685763d422c0645957f8f2647b019221b82f76648a5f9c3aac79900f2ea38a37f8a856aea08bd05
20	1	386	\\xba8e9f262141117b6a2a52adb50aeda3e4c309484a5d24cf58f0912d5eea993f58500e0796433567d45501b973e70835e2b362c6c038840754605001955bdd0c
21	1	3	\\x2c66a9bf7db0367bf9ea3f991b0198bf2fa29cea28d40f68e933dc7be67f19bdda07bd57c73327e2ab676a0af15f9498cb342b0196608ccd573319334fec4906
22	1	67	\\xb0fb94e3bc52bffce69056a1c150c24a4f34fdbeb96de0f8257d40bbb46cf679fe34a7863f227768d9b729918c4c8bde7ea460b660601e79521904817b0b2b0d
23	1	272	\\x43a1af738dd8a3c2760b937b81e5046072a07d6f41159b943ba6764d033e36c2c4a4d8f2d7d4179934389b1baf11f91b1f6882bbf09de562f3e631d91782b50d
24	1	328	\\x4cd7fe633887d3f83db34c92086e891b5baa13b03acf5acb8e7202bf7db254213006e9942556dfc0b35ec8d808b79fd2998e7bf2131770bbfe3961b94e6c2e0b
25	1	411	\\x36f82d9525eb434abbe13b66a0632119ae5a5370ce8d52072d6b73c8ac37a8721c4b66fa1fd2cf3f58b39fc02704f182ac4452762d65a914bd25723a4a132a00
26	1	405	\\x4eeddb291ce2b53615967a833bbc9d9721a80820b484691f411f2daf4636a4f9ae2be1529c208734783e0469c76cb29c5a72aa31ff7e5fc694e00add59186406
27	1	14	\\xb084e459641528c3ec9b826581f7703931b7fb020ed77874a6c6af25e0e0ab47d8cadabc7bc20b8165b19b1ef29fde13d604f3af2afbc75ff0d9f7f457f48e05
28	1	246	\\x368a6afa979f458ca3a897ab9fb1a9d70dfc72ed50ab84e29c57bd32435993b6ad54d2418efe0bd97a59590a815764899d8c0b79de632ada9c61f343673c9f0e
29	1	12	\\x380726735d3ee0e29189268428ac6b7705abca2b32cd9afbb8f511164d15c8acaa45914ab18d34fdf2951d1e8ae16c5cc494dc249a4719e387cf88544b228709
30	1	395	\\x07fa71225db1cb905275b459913b329be771f38d2589ec985d857ba78c74c7bab3a45bd0e9694b183fecdcdcb609ad6e14bfda7ead6f4f544f48b1f9a196f905
31	1	89	\\x5c85819792afbb3b166e06deaa41e49b9d987311bc0b889433129e3758d5ee135b13e9296727d6751b2531c0681e4be6bb8cb4387785a8b2c4dd8811fc1c410a
32	1	240	\\x218573100e13cae0ebf35a4c054d68720cc431ecf51c7df8d0307ff0efd6f592023f3765910f9890531a9df517fcc266925b2621dcc6f1e8b78b5ffe6318e006
33	1	192	\\xa778e064a24ed735d088832378f7dd0c18e1b6b2aa7e8ed5e1669d2fbb77ffba7b24233720fd42d0db715576ca7d92fcf67f3c298afe355cd065123122a78c08
34	1	103	\\x3eb6e9c19cceaa767b58a59606d6cadfaea72e9bac45ebde0a7058cd1dee0e5eee08ff157bf5756b8d988a66bce33bfea7468254131b3f769bf48378f490460b
35	1	165	\\x2a7769cce666886fcd7681c20eaa98a09975a10cedbddbc5f3ad4a568eca39301eb891c000c805b2de4aa0c195c09cdc5694f50998e5f5f34b61a36fd79a330a
36	1	413	\\x5415f75916ea4e8ca224a9293dee3ed338a701423ce955948b3a857f48b316046c32a1616a2f3569ab36b2a7d036e41b96dd875e51c10d7f859db3010c462501
37	1	162	\\x1e8f2a932b6464088da9d108d18f5869c52e6babe13b7fd749bf77d13dc0b7b3f2834dab763ab8f78c6a2d04c0d548d744fcbe4bd0c6f82cb838802211d96903
38	1	280	\\x81f48f278cde7ee46502aa2bfd875e82c1b9b09fff893c9f26b5688ad01f710be645706c233a526cdeaf6aab5acdb0d0203764488ef8b789279f985325bb2400
39	1	181	\\xf1154b90a502a14d65bef441b585808bfb57a12bab728da95af5ca2ee287f49b9ad0969056465550a3ccae60266812d4bc8e6da2f0930157b3a00b49461a0c00
40	1	42	\\x27bdcf02977c944cac7340123f64d7a5773f67658d93bb7875b21ae3066d1a61cd88310d64af210fae060b622b3c8c2349fb59cbffa4d5ae2f7d205854a49005
41	1	90	\\x8730cccde92418f04d368650f5864cba9424bbdf58b1e69c2bf425d6679e3e2f1bf544fb49e4fe7fe252188515c5f0d0427f2e078245e259fa574d83b6989805
42	1	53	\\xdd338f1a23d301184ae53f22dd663b76bfafbd179c2e112bad74285b24c6244439c376f1568f11e4fcbd558c27e5c95d497ca7c32133425a92117d9f27267007
43	1	388	\\x24eebc20abf1b638db2c675cdeffec8fa8e149fa3f03bf6828b7390829127b18c57d46ae730c4f231e47316deb62b27a73a9d20c336798d20295887bd69c570b
44	1	416	\\xb2a19c5140a44d53d9d44519dc887ef1d140f188a15786d4e19800afe3da967187791b23b0745f26e8bf57f14eb644ffed73f6948d404803a319f3a73330680b
45	1	227	\\x96aafa195ec427cd94789bd298f3c92906a896077df7c7aaf8c12b4fc9046e13374c71335b17534344c946e4b706a5c0895f03e9ab2980acee2250dbba12a50b
46	1	270	\\xda9d03aac663353faa2c46e3de56dbffce4d44a7023d59da79fb07c7baf3095940acef50fe2ea2c22e40489ad0ee5920cb8a294f5a41738c1460cdfafbf49a0a
47	1	356	\\x41e825b2643de56f651593e447c6716d98a42dbec8c73d0e1472e06e84c75b5c66b87abdcb7d5464deaa0d075b8ea03fa71e89ec1fc65c700a658f23a9184b0f
48	1	318	\\xb998ae571094ada227c4eb013a8ae17035b769df3c5ad0c90c32c240c62ee29db4961db1baca72d062a457242da69a3e60cd7cb97a3a17c3c64ef46ae22b1c05
49	1	9	\\xe9d8fd99547af7d09697395c44802537261ada9eb7651e4f44c0218c5c31d81fe892208e499508f012eacb6dbcccb327a397bee9f83194ca46bf374e512a1809
50	1	376	\\xa9fe156185604fc82ea04bd1a50181669dc9cda1493244b5a5a59128ed24d6d15cdea4d8d0f49777a2862cd54991d1fffbc57028af5b704757daf61bf595df04
51	1	46	\\xdbc5a5d9c23b83a0e3acf5dae4471e44b4069d975f4cca2ba29a29b36136840a2f7d27418fac15f6e50520940ea20793aa832bd5a22c56c7ef40982bcb304d0d
52	1	54	\\x019ea337f906607536d4ff03a73f9b6fb969fb8e7f4c48fa90601d60f1128e1e575cee181b6907929c7759e2064b9b9d3563a4d0e77ca20200499807f1b1080f
53	1	121	\\x28894c1b0ce5ffb4997ce12e9f44e199955d77806118ed9008d60ed962fa026ad77a0cc27721c82d142d5055d51ca47baad2487d223682f03238d929b3d8a70f
54	1	97	\\x7c1de7cab8a981184a87413852737289c31369cc3f7482e5f01959e594446f2962094f668baea1eece6a41779e93e8c30cc5bfe2d2d854b12d9f31c824a41802
55	1	213	\\x272616127ce469251aefcfe30205d1d7231305054dd177b42181da8e9114e6745b3127128bee762e4c63655c8f738ba5e71e9a066b6529f598b5dbd13c984905
56	1	185	\\xebaf8746625fe9e3d6882c66bbf2b4b761d127da0e8bb8f868b7937084e39259da92f6836237c830a350abe68b9db553640668f1acfda951e8f84ae5c547a502
57	1	37	\\xc6da291bc2ab073c1f9550036265386ee7b5ee1a0b9f6b5ac26d8f3c7398b0662f4e1c82cd1b3015c12ecbdafb78be62f3e55c12a7cd0acc3cd26dbf6dcbc201
58	1	344	\\x8af51ae0cf61d3d6b8a3800ad651eb93537bc99427fe8134337755e4a03fff02335195c73b8d59838549ba85ea2b81dbaf5edb99e323ac73c2d7c5acd5359408
59	1	39	\\xf75ff0a90a670c88e7d0bdb60d12e9841efa5c8a257de8b60bc11cff758d779fd05a174ceb4a9a7845b3930ec6f463cc796728eb116745451bee34dabacc0e06
60	1	424	\\x213ebd76b2b4a7928c107b35b369f54005d77c3a64382b9cd0f53e74380e0fc3170e61c843eab5b6866fb55c9cd8ac3fb637bd3c9ae494e6085bb4bfa5945e0c
61	1	170	\\x42440508e385278ffb827f6302dc447514c4b4d0b8586be7a8c7a876127c38217bd28d6d3c13712ef43ed4ded80df336a6c23fd98943351bb63f0fd7385b660e
62	1	105	\\x5dc13b3fa5e39a890821c6b7729597bed7d7ed568afc7430b93312ec937e397a3b139eb7d66151fbaf700de80086b73276e1101eb3ca5b8e37b5f3e5b11a3c07
63	1	234	\\x83626920714c26dc85f56d535ebd2824d32c93bc8f8429bbd0aa5d27a5120c30004d0ffffcdd71f2a93c4dd28a9d805a1ea8f2a08ac39db290ac992b7a923d08
64	1	420	\\xaa3d945cc7be32462ee33ecd5ed1fbac0e7de53ae20d077153a765b1004406fb4d72820c6c05ffa5e7f22c8ce08dbb7f70340745a0ef154f2db3264c083b5702
65	1	69	\\x376a6d72434e4f2c91f60f1c0b7200d1ec2b8bf971192eefb33a283767516dce9618af624832a91cc305732c6919b301c71e94700438972efd4feabf17a94001
66	1	76	\\x9025c42ccbc45afc9a81b9d4352a6e24aeacc43bcb2f7e2561447720bb8c9ccd9467cdb875b998ccc49b54c185150d16d4833caa1a821ce5ea917bdcd626a60c
67	1	163	\\xb04b4773d4b3f43030604278b800149d6a2a89e90ae4e29692ce51a62a6a3cfc46fb396029bc70d9d44bb2e1d132b5bfaf8bc67fb9a04c51b84f5313e1435309
68	1	187	\\xe0d6f401f78071cbc5329a536a28be4be91e23cb03579b6b977e5117978e0561fab8817356672520482d63ea71d6b61b0787f1e416c066035a7495805fc5c206
69	1	305	\\x5e6fb1642682a064c1f9ab6bee3f517e518d9c8c1400d5d057ddf1984b82c105dc16ac8d5348376de7da4cca887b9c0831d0deb24b3ccfbf830f647ea96d2f09
70	1	394	\\x4c86927a53d684708c6ed38cb21ef0fd1ebff83069c0b25fbe0b5ccb1301ec822646fa919aa0aa1f472e6b3c70a2d5b07a02a4abe2f56a9515867bb04e8bf003
71	1	235	\\x11fe3b71b8cf0ccfaaf0ff1c035c2a389f7d138ae74058d3a4b6be5dde4dd7fca85712e4409a9647ba49df2461ee08718bdc84da94d930c891abc713c954890e
72	1	363	\\xde3292c13c6f9ba33ceb4ce755f3367395e07fb37bf91b8cae5f24d46f7e9b691fd7aeb1c375a4a964d9668eebd5c9f34802b6cc460307423e6e1170f874670c
73	1	302	\\x5cb2dd88a06ae1a75b3ebee8146f126149e5ba5cda732b57d834161be79f6d74ff36194701cdb3e1339d495579396fb7356fb5da79fbba2568be0f5816eab40b
74	1	5	\\x9a72e13c2ff2f9a329dae64be2a50b0acde76ee6d41e57c4c73f7f3ac246f71f97698c3fd5e4b4ab973af440a459720917318256d775f1affac5518481efc90d
75	1	366	\\xda6effc20c0e34de22ed057cd0dee4d3233bb6caacd2a7bc87270d4f1c6f6f9d0815f012adbf29f56eb7c9b6f4f55d00270455243f7bebc1886acedaf6a02e0e
76	1	174	\\x9ba7f999e2f4396c1ac71cc92358baf60d2e768a9356a15fc23df65d0cb0c7d9473c25740fac539260f20bd3998821d2c5f9a3769986b11d29588eb8d07d8905
77	1	239	\\x1f901f432090e674249f2f72c7125eb9472b92f6a5c2e6dfe99530548ecbf0b69ce4255b277788722d40ec33347d5ff545a26ffce860369969f0b30300c7ae08
78	1	73	\\x1092a4bcceb6e92b9de6c671150e681492cbcf0052e40337a60798ae8a52a2071defe05312a30b4d0dd00e2f51fc1c64d3e15c628b9dcad32db2eb91da46ad06
79	1	138	\\xebe7b341d4c6dfa66c3fc4a545e0280a5163c5f6a14c9fecb956e6dd87e094c4f31922913d97cbeed11cc3b6ff7f28e6b1a876da83629d211765a3e9a2617b02
80	1	348	\\x54eae872274c483d695552e460dc013a79508da02bdef2e6a674e64c0971fb5a5a43e6f10e9cf048ef5721176aa87c31d57619a7773d8299f28307a14a57fc0d
81	1	178	\\xe7512ddc61871864b2438666067516f74185c004117ea1749ca03722e4762b7d67e21e350f25f58202d4a2d39c95274af5accfdbf20a6912b59be0663f620a01
82	1	161	\\x9efeb0e6e8944a67cb57be87cf2005786974ef9548bcea892ef8d5ed35032096aee624e3dc6fbe88b75b2d944e700b738628bd5aeea4c50a2b9790328b24140b
83	1	25	\\xb90db35303a4b6a276b083535add86ab989adc9a4e53f706b01404cff27579ea8ed7987e7b86ea0b15014dca6b2e77ec4e148b7a3d5eb9d82db3ec9a9eae4c08
84	1	367	\\x7ec4ec28bb11ca484e8eb3b72b7ce06024c6e3b2b854c9f9a685574e0ec3868929837dd41685f2bbd42f9f37d6588e6c53fc8b5356beab4227b75bc3f90ce104
85	1	31	\\xad6a03ee4bdc3a65796446f7827bf6bd7992b976843f2945c745fa4f73d97925ef4d8e16492cf50731fed886f2e308e330c25fae7f96e8ab3d8a6c8435d67409
86	1	128	\\x75c5b14a43936fdcb5ddfdbcf71e3ad18be0390fbdaaf396f244684e5e9f4df52f598554a0b9ce9a57cad881affac52bacba06f852101732603a8b27e1e79d0a
87	1	389	\\xadcc7c84fc057ee3ae04c6428f7d4be44541fd829ff49a282d57d8f91603f9afcdcfbdd3aafe6f9a86d60e644def34bfd5197b0b79b336dacc064e63194f7505
88	1	249	\\xd2ab048bb97c2e25a519ebbf941a54a83afe60879835914c4373d9791415587338444b092283d1c5f72c6dab1741659e0b869ab80805923bcae950690534b608
89	1	167	\\x6ca80bad9b110173bf3af0fb884056c3b60b705d5806f48465a3c4bc90c3a628efe2e55dfcc51e5411a1b8afe5448555c041ffff209eff61ac114296ed48b702
90	1	22	\\x40d9c2aa95e5ec86c0e0290fe538cd76a4d7c529e696a51fbe497ca27ab9937e7aa4ee0abae91a4d212c65f089c12b19b336af6bfbae83da6f311ef4518a4f0d
91	1	369	\\x5f61f15b24cce69a1910ce89ff253724065dea392bd68079deb310b340a7dd2e6d81187f56671d26619d144757e51013e6eb9f223d6a26de17bd3565b21ebd01
92	1	393	\\xb3e4240d39ca6f71babef2f03af76a12ed1a87ba19aa173a195c0180d898aa4a432fd6bd8da3054e50817c2554084312f6a7269c113c5071ba559d71e1300204
93	1	221	\\x8b852ab95d32d31f47ad1b39fc9161e3e84dc98fd86587a52f233eeb809ef83d04b4451c1b8b963fae6e77d66c2d4599a106c7dd5bd7aa100767a29ba19d320b
94	1	209	\\xd63ff270faba6c96bf9148b6b92871004aa515b72a3826cbc4f279274c0d29183c53266737ed63ac1c1a090e2c6014a00fe1050b5c40b510f13e08f093d22000
95	1	82	\\xdedffc7a4dd0e7a5028ab1f0b2edbdae00f977986faa18984f7ae40e3b89cd6a6755f21f7442e9a70cf4272c65e3809d71ced13fb187c7ae31a8d79d631e4b06
96	1	126	\\x1661cd4907d8d941495e035d2fd1d67563f3fdc11d99521d2452028304d019679283308c2b685f3ccc97cedcc95c8990ac8ad43f42c9595af0e4a382bd7d5c0d
97	1	118	\\x2da06ad19805b65d6b96d978f08ad1cc9bb2f08e727f1aac9f1234c2e326c5706f11ee21683e0fcb338cb91d25a6a62500e64c459c398db334ab9302675fbf06
98	1	374	\\x5efddcb856e0ce1fce464046f38e8eaccb3375162719baa1599af29b4f6150eac8996c543679b0457fbbae755ee98e56c7896a66e6d927c9b323c7016b3ffb04
99	1	123	\\x610eece42844840a4ce61831caf7a23424ef40837496f38412a3160014c7ad90f85e4175260e24d61db87f8cd9df307f9377c0c960434f64fe8b3a049b71b906
100	1	403	\\xf52800f123adc0046a7728a28a972a5d4f5673bb213ad6aff1be462d16cf8438b61c1c8cf911efad3781d89702c3645a0558fcd9e859197db5e1e61aa617140a
101	1	423	\\xf233492b5f725e66e2efedf78587e0205ef88eabb79897a10b50b2a23202c8d3af144dc10e3c6eb14b165e4cd69a6d48cbc53d023bb52fee516a729532d46b04
102	1	133	\\x61d0a364bee20191c678d02911494a565be508d26f20c4ba479583cddd9421bf5021c1160b0de55a1735b0d872422d9b10a277d1f48ae8fbb3c4ed3322f9f007
103	1	341	\\x4c079232d28f81663ef8c476038ed9188ebd9d87d267364a91eb13474d60ac23e60feb3fef950bc7d2f3720e2609a0ee8b5c60b9249b439c515d0c9ec6605e08
104	1	326	\\x820898559b8722075aa856c56abcba5f9e9b80738e4ab72656b894a3a7ba08d87a1740f3772fae0dec77b02c73e0dc69a54abcc1f60efd20234be7452dc89204
105	1	417	\\x6072033344eb54598dcc97cf121e50ebbe5856a0f38e8c5f4b52d4021c9b222b66894ae8ec80284fad522d7e74254668371d6b74a02c08dcbc5484dba0f34206
106	1	289	\\x6b3bb6420a9bd22e88e678b5eb0d81eb4066b9d846d715c278a0206fc6792d8fc59632f6df197a580fcee8e503eb87bdc748e6745fbfaed4333deb628739c906
107	1	325	\\x449f3aee6889989ff662222dacac6b4f1cf4c9ec984624d9f01d009eab225719e46313592a55b845dd5264f9f10e2b668a786f06ae9ad665c9f502913947f500
108	1	199	\\xc69a471d1c4ac0183dcd1f5802a032370860242243f80dc472567cbe946b09a1cdf37a992b638ac211ea9c40f01a01b9d1e9948150e249b4feb46139550f4f01
109	1	38	\\x28e09530fb5cfc8dcc96e6a2f71bf2124ab0b65bc9df875be3429f15e2d70e838ca5623ecd71dd6241c78e831b5d2aad90ace29388b3d099dea2a36dca44d706
110	1	273	\\x0a7fee52e45e1255533b986cf1882efcd222ba7b2ad9494022567f316bb3ea9fd31f8d6aa8de8921e37758d218858a7a93274df7dcbbc22d25d6bead9857390a
111	1	156	\\x3b77bf491ac2dc44bfc7375f90466aeefc37a8f760cdb8cc962b85d7436f39bf0cfa735556db8984c420b02b09080ee4d8565f5e0c120858577a1a786f9aa106
112	1	259	\\xc4313f4a3a8ce8d61eb446d03f13838e2c8cbce90999810d17d649f9f38705602bd09723c21f1703362536c1ad9a096411f96e9bafccdaf5e07a25a3c2fb6902
113	1	65	\\x8ea9501884e0df82668ba1996ff1d8212f0f39916c971b156b847cfa44eb4224c41f08302f337c87abaf2245cc3fd04bdaeb1443bcdb074d89c658b5a36b5302
114	1	330	\\xcea967e7f559386213a3f27474bc419fd9456962f83093848a4b7fc2cb7a063f2479ab58baaac803d228d9552db3b2eb9fb225ebeb75e7d4f78abb73d80ece00
115	1	253	\\xe28c8254c337670cccaa42bba5a4671405303e596ecea5c6a5d53a324d0c2dd2cae6c0c6cb2823d99280ddc147281db08070ff269b0e6147f49423cf7250ac00
116	1	329	\\x129b18c1000ebd7fcb55d843f5ac619af8cd1ac59b282aff692a337edd3eb8ad21801049e9fe0f0e79d0e8fe7891fd43fe1e96ba83405114297a57f1aa85c403
117	1	154	\\xa122e3181c1e18d71d60364b1cd1c12ca07d718aba87f0b9557e0f2e1c5877651512b542cde6d563c5eb35b50381427e3931eed1f0fe52419be06981387d500c
118	1	51	\\xaf6998a311255adc76028c8ec5723d19dc020eb221f54efa73c0b3ab94062bf3b20e220d7ff616acd1ba78b865fdfb1be907b424594158c19d28ea681c16e107
119	1	184	\\xec4f5f20fd7a988dad4ae65e2f6fdebbd5f90b7fd90fa30c21fc0dd9e2affc1faacc7c14dc3c1fe8102c09222a5a3fb5c8553a81b40f5ba9ddcc1357032a3003
120	1	68	\\x389345ce37bd8c24179b7ec8e3a8e6d3b6937d94cec853fc0d78477d29c58a947a2f6a467a71158c034bc995a2557fefd54a36848df07f246a099b9daf5f720b
121	1	127	\\x993d523a1c99ee899b47fd17323f3b81b388313663e4140227f170ac2dfe11b5aa6e68ab899943f297406ff99704ad3b1e7a0a04365b64794c4d5efb75f8250e
122	1	177	\\x4de7e682fefbd5ef699023020256ffcf8de76d50e233360aef4da4af43fd0b4b01726582f1ef53e0c7a46b1c90ae41e619f6b857dedbb52e812beef860e99709
123	1	215	\\xce0eeec46023f59769730199fc7d12f25c616b12bbe2ba5226311915a7da1fae834859077031ae766839238656469e6919e76c000826f340112dcf6ac241a402
124	1	49	\\xa31e4fb18ed2098bee01fc37194e1e2fcc0ccf561997a3510d678fe402e20f861d7356205121d555f532d4eabca858e4f7c7aac7b301bdebdc0ae497ac1d6a0a
125	1	349	\\xd46541a4f28c65b1a0ddf0ed711c806e2cc0131e828717a2f767f013c7d8d5285dfac4e9d9947ea779508fbbe9d1080689358ce12dbd7134e648b63ff7f1ac0a
126	1	244	\\x93c84f8a04e0055071c2c2a66602393ff06900d305cda8ffcfceb19a945f6f359128a988388cabe37ae3c6f086fe6afe9f2b4f44ded1bfcbbc16c55001da7404
127	1	193	\\x1470dacb9e0a6bac338a38e197bad5ad1f86a7a59da794fce4e2e98663f79d6e01efadffcf9ffea3a9c96879b7af9833352a67c245f2467f3f77f560b57cb401
128	1	20	\\xb6b8d7532024c4f4040a53467e064460b7cdaecffdcc2f9018155a0b14edc165fc3328d0e6026053475e6e0ac821efb7fb65ef2c07331ccc5fb303b9191d5d0e
129	1	2	\\xe7db726752f932ba612535a89ce14741c07fc97533ec04df3b8dcef076eeae316a8c95913f76555d4b88d40f6f3072635a0bb5f221c3a00c57344004ddaec500
130	1	196	\\x3d77f4862f6edc4bc1ca04088eb925bd0aa44cf2513800de6075e151ac42d0cc59d13258f803f1e8a4fe2d844f246e5ddcf4bde400d3c59c2eec7e231de27b0f
131	1	169	\\x41d32f0508b2b38acd225684a3a844f85f108b06a842466f33b335867f8025820dd60c03c29bc494fefb7ddb04d874cd6cea7b88ccd262ed260202f485e75a05
132	1	207	\\xec665d6c44e656b3ae079ac8c7b837bdb97eaf25901e7cff86119726850502721758c8b0c37dea48e5831b90386199a7b52b00cef99b8760bfe705e494d46d01
133	1	176	\\xde9aeb70f7198b992b69d22fb9170485baf4a58a6e7cda4aa62b699573903de02f0f5d5e47ea62faf32b4ffb752ac7ffe0af230511739f8f0abcb1e01d0f0c02
134	1	268	\\xc2396211e0bbf826592ec74aeabf8455d0a8761bea638cf6aa8c69b0c5e27dbe6700558258956f3606cf8bdbfbeeb1736980947dee84a14575b235964ceaf10e
135	1	211	\\x8c5b07c0e7c204ce4fa0964f043a40c3a266943495c530b4721ff804bb42308d341f265a071258c1031bed20701d902f4cbb6e90174f6066e2ce2f14cf60cb06
136	1	258	\\x9b068cb2261ec1a587e86e2e83970aff01f4d13c4d0d11649b5a6ddb14506d353965568ff9b5d4f7602cd6f982e86f806bc9f764142bdb8245162d460f54d508
137	1	36	\\xe4601f8a0fd96f7baa95335ca3ea0dab6dc4843962b0fcffc732da952c737e1f6032d0a7a4b78c9918c71257242895d9415ee5d8d11909945fe9a47c2526fd0d
138	1	59	\\x58fba160f8d97f511057deea2d3d518fcdb061c6ca6f5bee7cb7eb8c8f0d755a7fb6e50c8aec418f841f0a134db1f9862d65a064f3ff24adae2f928e8df5c00c
139	1	247	\\x843b85ad559947f1e4466c849cdb831754d51ae401b339ce5d3c23758d42c8720a1db25dcc539e035f397219ddad0c7803642e7b50adb42329cc81c3ab914305
140	1	285	\\xcd2b9356f131db10de550bdf1dab92acb45b7e869ef0818bf1121883dc8b46761656066e34f4543cfa06bc3259aebc4b40155b6016043ebc83334e8911c24608
141	1	41	\\x535f00fdbb393d50ab0ab21e7b18168fc47493d8790c774d8d1a78797081b4f0e55201167ccf0b6f21b2cf4dbfefbf4471c11c6c6ae442f20887ad2001c7400a
142	1	171	\\xeac698da70114103cd9c74d11bde7e81fdc4d760530157e84d7af49c8abdc71344b9326b8ff286a052475ccf7830c0693d769b772ab24c154812e4a10f948c0e
143	1	401	\\xb8ba79b6f9760f63988229d93f262d252b3e3a6339ab066fefe6b1588b9aa1257d9757141b7d20bd893b52c0fadcd6d9611579e456ab02bebfd0cc184a29ba0d
144	1	294	\\x41ba3bd0a6b3d72d8ac8e2192c6dc1b6f87ad45df7b9f6e1b55d574196ff0c4643e52447e12548b9edfa25e81b516573d66d766ec862a0607828e66c37e31a03
145	1	102	\\x1af000eb7b583349653b41d207ae985aea924be6afed145c515fa2417db3cbdb7ca718c18d0f14fe390bf766152eefb3c7a13cbf7ee93470a8d9c094e516540b
146	1	279	\\x521f5b7bcea20340414c5da7568109703bc577784ea8b7187722372004a97c90bcca2ff8bcff1e2b74a081929aeaa07935115afa84c824e080d823b7d436fd0e
147	1	71	\\x398c1695efbe60b64252821abc520d348d137073169a0a1bedee8a5d4ac2f4c18e6aa4e87aca2830013d390e74210793d264b7aacfd16796b44da94eddb04a09
148	1	222	\\x703f4c33b0cd5c40a5205f8b8d2690ad3c1a5597019b06cb2de66094cbd1c5cfa70693d5dbb116686a88c286f6990ee7bb60af2fb6f7d083c8d59161b0123b09
149	1	233	\\x119593bc6db98b87c434a3b1540861de05bfda556ac3e73d11e28dc596aa56ba490d4cc42ab7aa0c2887ee1f648796291f767af7812ad0bdb7f5a6be12a21303
150	1	343	\\xe265739b9adc344ba085b29ef899bd8110d8aa6125d4510638f140c737691daafb21aad83490a5863416ca68d84f6842fad865855c3e2814852bd75bdbe71504
151	1	351	\\x94396ad57a90cf3ecc5f64b1594817335f9ac722a95537c37540a652b70acca6ee9c236432cfba3f77595b12bff8026d9e75750b9538beaa1ef254c2d164e907
152	1	74	\\x8c0f26640a8f8b6bd78832576a2910842c2a0b2a4628836742ef8275c5a56f0d4612ab7f36ba95a42bf4a91ec7abc16cee1047cb5fd6bcbb3e9c33442afc4701
153	1	26	\\xc2edc7ef1bd587108f1d3e9d1b59a83491a4e6aa0ff77ac00bb5181b2549a794dd95f6b361f9b61f0ca0a77b59b8c62cd8e4e9c79ad9ff17d2163b7f3f7e080b
154	1	336	\\x9170807a42fff7540fd6d8a2c81c7016e12e88ac8b57dd10de4a33ee60859631fc69054522ed11ba04720e3c36de76d5fb40760e78c84d158620a4dcdc77a804
155	1	277	\\xe9e271041b86c0a0c8bcde29c3e858db1038296dc1ec3de40dd5b0aa08762925679135c1ef5eef0b670675d78c88186243d35ae09365dbb06f10c98b32d34d05
156	1	200	\\x51b28504718e34eabcb6bf3a0146ec96e36f49aad179c44da9f81fb7813f247e2d7a5a53511bea9982151cb3f94d7c506c982b21338943caf5b05564736f8302
157	1	230	\\x6829a8593ec96d0febe8b904e70d19cda22b01e8d1e362959e0e1c3ceefdf197ef8f51d1fef6b4195309dcda15276626dca33b977da9917d533d417326815c0f
158	1	310	\\x999cf18360765a17929cb1f3e4d2e41fc13c3c84ec6e44b4d9596061fbf5a9210f21cac3e86dfc99122bbe7c95b47ee5ee141cc77497b5b85c6198345c8b7b05
159	1	117	\\xf508ec05e416db15f8ca9956344dc0e3fb006de113d7056194b10561bbe5ca4c4ae56d559854399952713ec23f8ecddc12c39af281e3436a14c060be71340a01
160	1	120	\\x2eab2117307bf6e5a8a7869dacd25e13091b1cc3028736c94eaf2e940db94a2220c11bf190d6f9d85ee5dec5dafc4647c00a6fb167f418defee880374c69350e
161	1	245	\\x047eefcf04fb363640e3253a0141e6c7b26a6fa58cd4894b1b76f1a662c94543d1c20d66f4b3713b9e0f646edd1238f49d3b0237888cbf3670b0a89879b1e609
162	1	323	\\x52d43ceae3226ea29ed5b8db3d8f8b8afed52587ff949d7cd9b3f69d78a92d5473d787b0d4dd36925c889e69c2dfe742f8b13a643d70008db8d1d7f790b35f07
163	1	338	\\x178b1bba84bbdd1126d3b5a793999535169b3849d7c5242088fd7ba10577469c7d6ca787ecdb1c0fc696ca9fba498dbbfb1ea1122d8a5b262156efc0cc94e404
164	1	282	\\x167d7b6a41205aa8abc1b7d1bfec68d3ee32a432f657d61d4eeb645ba2479a1a4dc11f1080cb06d52e6f59a81d15b9b49240ba4cafaf9e45ba8976f918e9b408
165	1	183	\\x14f3eac3a10bd9f7888cbc4adca71d6cd4a04575e8bf2e99af9b6bf26bbafba40f34fc882520f5ed2329b709309b58afd7ac99b4dc73a3d74f69358fee276c07
166	1	415	\\x50c33ebffb98e5ac934dabab39e1b2f3ec7fb4cde6eb59034af2ea3cfd459aca32e462c845828eadc8f05bf26b6652282ee1c22a54e058d1af1ccbab93d0ff01
167	1	299	\\xe4c8c1fa2097fe61e89b6ab920e0d34c2670ba0f996507ebab36ff04db674740157bd1dae0d7a1f84594d0f5e69932bad8aeb3ddeb53edde0e49a864dbd80404
168	1	422	\\xdca04f72268f98aa80ee5ff5927c33b91e0d0e0984713a19cfe5a27deb2adc863c8df9cd198585fe40077d264c2cc2d44fd65516fce9c5d5413c792ce64d3304
169	1	358	\\xc4cc90e3cbc2ef5149b3d4cafeba6a7e0220f31649f73deca5ebc09afee3d36a8034955cbfaac7cd7b622caea272474a270d6cd175db9401d9932b288e6d9b01
170	1	276	\\x738372d9448b7b2c3b580520f081d0bcd1d910af5610eca24ce58c7247f368856bcdf3113669af9495228d6905adc1163dc55250a2e3ae07dc06381929c1fe02
171	1	217	\\xe8e50a7a3cd8d86894d9791c37398c17737796dc1658c52521a9a7fdba64e389737e00c846e3b539489b84afe79b10f5a107649e71a9a40f76f80d6f3b3a7b09
172	1	342	\\xe2fa2365db9fe354b2b51fa0895c76ea03f5e9d890255134c53ed935e2f08b0bf1e83ba2c2024abb3949c24d9054556e959fb776633135f1eb710bf9c3ebee08
173	1	172	\\x6a2afb02b375831100582d2a0233c483f3fc826db4ba708c8b7ac43625ff4ac7caec05904043cc5c53c16827a3dadc532ed5b38d78d1f529ac25162f624dea04
174	1	159	\\x1fa900c6f39cb5534cd7797c0aafe4ebbf5a951805f7a7a3a788ef442aa15c548fec21385d214346b0f2b8c77da961d13e38e575f54844816c9be8ab4bc7a502
175	1	153	\\xacbebad762445a9b09f22c9052c25d2441a63f16bc902f6fb2d74afb239a52219309eb666e66fd6493c8af631ee66c64e2e2c237b8163347616a716a738f600f
176	1	197	\\x125f0469330d6cb6602951be008e55c371788006e177af8c87fbdf33db83b7167b948b19e32f43962b970340b3d5a228a1c2e48c9c81d6faed41d50eaa3c5305
177	1	271	\\xcf1e9d2b5f96b3935a07a3dc60d0386c72ea3b4eb5e540b6c8bc9a2be0d7a4598045a823ba177942edb4cecb651db464695ddb9608a18a0d3919f1d9db77a002
178	1	210	\\x67789744109c9601e6db85f5e949c683534e046ae66c135d740838d20ec9a3c343a5a7f7ff6fb62a9a98f5a388e810a2392ebe005066069fda92631b6fd73e03
179	1	331	\\x27218ec94f12559d58d278dcfb9a12b58ab4b531691ff39b3ce852c817b80f708d12739fb0a85c4aeb3adc3e196312e044baff91fe61fdb957d4816e2db74c01
180	1	379	\\x395f9bbaf05b6fae5eeab231201055cdefe3af570f0eeae1935937835112baf1fd4ba5d0014615c96ff74f4da9cf3682a1e7d014729bc508b10214ae95cc7404
181	1	168	\\x6e9c434fd387759887b5dba752028636dd0ce62b4a2d5b8f7a24fee809ad70c875742698b6415069f4fd6964d72231605a1d505899ebe9e7f5a7b2247df85502
182	1	412	\\x91157bb0f512f623695e8ee464468b94050b2513e89d735e46d54e211e95b4791923dce4989df080ce0e22d7269142efcaf183fe8df9b02c4e99d4e1c85dc40b
183	1	28	\\xbdc09d168482db7badaea866a281fc842ca4d7a951da44931c3fadbb3465e263d57d72079119e56f19262a8ac02e5c7863382bf42b51c133b30ccba467492c06
184	1	112	\\x505cb8c902464a84234e48e3215a35816faa7751fc18d19aa415cad5a104c316b66acddd7003fd48966e65b39bdd6a28ebd2954c96ad96cc444c5e3a970f5200
185	1	194	\\x0ca0760aaec59b24eef5f35d1a752a999801292efb1e3de49e572ea483aa58e3ec0710e716c7806accd5ca93ccb6c2a24862cc8a7d0a9b15754eeb57d2bc2501
186	1	131	\\x3b4891187bbc439876d26e70d221ebba2acd7ec391f67dea6dbe32f067f08d8dab7df92aa7376b0388d796e1d2bc21cb756e8e5cf42b704f3c195cc2ddb50601
187	1	140	\\xcc6c976e2e25a9022173632a0c5c73190c3792fa0e353b49c3e2b87d566824ffaee4e5a2eeffe990712759dd12cea2eedd917ce2c0afd8de887269ecc4247e0b
188	1	66	\\xc2b2dd464252eca614cf050b49fbafc656107023da78ad6d19738e4acf6c406bb8cd5ee44668471cd1375fb056551d846b6ff6c2c1529caf373157b5843a1403
189	1	309	\\x43ae0172bb563aa05d01c5181a1067dabe12d3ae149e12f8ba8ccb9beb89fb2b069c1005e5bed3f15c0206afe0baa8a39b98eaf0f9e80956dffb264b08d1f50b
190	1	397	\\x16a270c19354e4d8b9c5dc02b1a3d93f83e1d987d084ff05222b942020f8a9f745b8355f1cfd28f286edc002e69d80f778aff8ddca632f0acdb171a31ec1b204
191	1	149	\\x7f77674839c11d3dc6c39b76f3df473fd9f1599fd3d6d195fef427827001044d577cd0403eba01e1ab8fbdc74ed6171bbcba274219c444560cbf3c7149f9b303
192	1	13	\\x91600882b995a981a9dd4ae2076c138aa97af71069f239abc3d3e1c6625f201eacf6bffcaf9e31c52f78aef8f1a94eea0030b77e387cd012109ae12d4fb2f20e
193	1	86	\\x2948f1a7995846556c936633754d87bd577c11ca0a2c70e5b8d6e462b0aeb096fbef897697b39a824d6278c25624ac7f378271ec417f7ffc9bf513b221075704
194	1	15	\\xe4dba8629d08deb76c2bc224bf334862ed05e59f3406c33a541dbbcbd9c6804ca1a58a9dbd64a2186de7be93588409b895bc742991bdc487063d75ee1a02c709
195	1	383	\\xd77fc457f4963eb7ccd9f5c39d2d7e039f90fe8f9a501e22dae7b201aca7b0f829d69e9810cb1fc36dfcea43976e510187ee4a6b49b8e4a9d18a86f666e5d800
196	1	260	\\x3701a4c3fe3c3bf826a5b2dd9751277e70d5da75c4ba4d545428b1e7296a018c2b084ae95c71633dee17143ec1c7d7d86eab0213aa9f339d08e18428e9c0e60c
197	1	372	\\xe677705b63b83f96388f41393ab6d7fc648d6bb0b5d01ba73aa67876f39bcadad63f985a6284e836932b4b136fa4f76112603f4a4ac870cf7e75fd04e4e59d0b
198	1	267	\\xd2ba79e3d00c36cc7eb63d037e8377940a62ca0ef39efbe2628b9ba8f178804083591b8a074c628147c7151008d1865e374f765070d6eb321dfce7f3b0492002
199	1	385	\\x09c67212154ef0c5f8b3e28f30a843054717264430c84793787702f6d1ec174e67f2cc5d782e55918d59ff10d5771dff2396ba86a1e0a76182d55982c5e3af0a
200	1	421	\\x62eee77d643a7c8272a64007b47a2e961924970394c77249a9e23272e4ea26869731986227100788c226bf1c4c9ed77ecc1352226f31b3a266e2bcbcdf8e700e
201	1	218	\\xc4f95b6097869887fa8eff9dd47a44bceefb5fdd3d0837251a4e0a17e7774629a1fb37a8946180f01e241d42b475989aaac9fb7978be2665f7f9155236bb2803
202	1	250	\\xfc8af7efbe3c3152cb4f39921ec40971a6b71f4a0f16ba7734dc6d84e1064e33d6df99e49da7427316f7cdea848f4c272e56940518d33c8b201636cf47d94505
203	1	100	\\x9dd0cb80877f8bdd34990de0f89d0c41dd4e6a8d259f1ace50522d72802ca5ffb37bea44d254641f2103f5c5a5fa452ce9ea4cb385d44c6919da4d4500f0410e
204	1	414	\\xe906b41736f46f286cc23aac4499281bb5c909fa96898cc4bc1d53e11334bdac60d566cd5068a0bd5ca78bc9c36c9b8a8cac85fa4a17865078ce2c309a290b01
205	1	360	\\x985ec006375339d121e62fefb327c5d5e6fde8cfdd5933a74b8b697d1969194f6b36f609f05feeab4cc6701928775b25525c6fb7408512e6e874bc91b3d4d501
206	1	72	\\xddf00d1f55a8a9e29001e70313c38c2f0f885f9021f07a8f3e2f36677c3ee7ee1d14d95c7c3980d6576b732aa66b293fc4d533704279fe68c873c49929a16c04
207	1	290	\\xff5b59da5cc9e9d74d79ab38febec2e38c10a5b916623de4c8f959e6be065a6894beba51fa5a949d50fdc5506a6c980191c9e07f2696b1f6d36cae7a6dfdcb0c
208	1	362	\\x3e90257b6839776c571a04c1ac74f678a06cde61bb427a3d0fb7d84390e05d42802ec15eb50a4408c017c3de6cb2dff101482763e3024d242baf58dcef782307
209	1	220	\\x29443c4df6de25dabe77752f66fbdc1eaa92d8b23c4782eafd2cb70f3cde32204509ea026ab6257ebca14150e4dad355f753191941e39981db6045f7d8b8dd00
210	1	40	\\xbbd88da41b72730d56f5a207656eb299bf377efa0469f4a143b5496a1cff78884c29815acf70554c4467567136afdaa301b2eaca237b70fc9b0a9b6a087da102
211	1	182	\\x4c6773f67693a2cd7f89aa205f4788ea5884ee3595619f2fd28c045bb7f87f61de0e60188408a4016a8943eef21dd366934934cf4a3c4fc912bdf6e8c4423e0e
212	1	148	\\x23e3b30386b68457af198c4967ea8bf3d87379b19e5d8af028220831d9d4071728c7826727492a5c9159425c0acc188047f2b2b8249bd7252f6b6c8d6b3b220c
213	1	390	\\x393dfa6130c7119bfff221fdd174fe2bc6940dd34050e817c64206e7e006887ea76fc9093808124969851b77d4c39e0734881afc95f235f80375ad25727f6102
214	1	43	\\x702b50d31bc4756f9d2e09175968f617eda91e30d919d5c8f349331d368c4089ac6c90179134f68488ca874edf566195515bc892d98773ab458febede0bfa909
215	1	101	\\xa046cd0e15cb5d4b9912beec7e0e7ccdc8df86c5946023965672c936830d0dc600d039816ae34ad9ee5404e3844e2d3a5154b4edb328ef36140e56297e389b05
216	1	113	\\x8cabd996ab6269d29df2945a368d13c454f2f712ddbfae5ec43bdbf4145646c2f950b645efb20d6c8a31d77c107f0c0691e1204a22fbe41091082335d11f4d04
217	1	4	\\xb7fb2bab764b3e1c66acc94d9b6657cbe2800df7cf33ad16bc778ab30003e2171ab7076e347c07b64f7b3ae44be163094592fa3763d2ce9959d80edfeb41e500
218	1	229	\\xf784820388329da5ea77692f7cf8e29095f92caeec4c82b4f6b1aedc9c7c0dbf8b1b10efc950d0a6120ed2233c80176a193412a0c44aa6c603ac61d2f7ab4d05
219	1	307	\\xdb82ab41895143d526185b5c310b3d25371a854aacb0e1dcdd6e39b2e61ea714e0fd4691891a7a15e6059fbea1831a529459175dc767ab85bbd93e90e82faa0c
220	1	151	\\xbff10f825e31d4b8a8a5175a091d78d5b49c9f330ccc470fd312dd814636cfd7cc37d8a589bca39fca054ee6b5c148db395a4b8a7c329ac92e20533a97a9cd04
221	1	106	\\xccf1b3e06c07a69dadcdfab153f5440db33170eaf907497c9a270a9496de385bb052ad9cc3cda82c1ed8d0d4e208b5334e2fed2f5b0c679d1275f5be552d3708
222	1	265	\\x87db747ecf1cd54d824df3895cbe1b52f29055fdad5c99137547a8f582d631e95775877392448d7360f1560d0b19e538b12d5c3fcc04a422a79062fda2cb770c
223	1	361	\\x3fa14a6582a13f4b9bcd58eb0dd354f9ba6481e99644090df9967c241b43ddfc0012a0d895a684d505d282b37ad130a8ebabd27ac32e8895222a8be9339b4503
224	1	212	\\x36a0d292fad2567ec189d3955b638fbd68c852ec25e1f6498f5694488909955e00bf7ea6a52c7775f08bb5fccf7d9fce8e8575e605905871eb28c07323a9b901
225	1	254	\\x3b56468c88a871bef8b2354d6702b0d094733cd5ae024f02a0dac35aa014910191408f5caf6a3c4432cfff1fc8c7dcd8e0201ef513e8bf71cde10c70cfefe709
226	1	399	\\xaf9c551d3c13f0a8323a84c82a7878c8364b4b2b11a3b88b05cd5749c52d31ed1e2328776a3066b3208e6ae7d3aabb896c01c8e2f23c6e9389747f280d5c600b
227	1	202	\\xe4a9fb3247ddd47c3518f165abc3fc54324cd84e74f87cba9bcb6c50e4d89de9948ad211dee15afbc1cb5dcfed12d879b9ea19a34c4d13bb61666a6f13fdc90d
228	1	324	\\x3f5e7525b07c96898a1b8382ced5fbc62d47de879a6df5ea095e95644fe165de2dc43f231d77fb411c070b1aaca7f2d2bf32286dd393b4fdbeb03be05692d300
229	1	303	\\xfa24454c65416a19a3405d6cafcc5df85df16aaa38a96d6e2140901e564b81d741ccecfb16e00555a3f24be016770876ff31fe80c4a0387bb60d769bf3cb6f02
230	1	27	\\x0f7b09dd3ff8a6e8e69dedbf2fb702f71835bc94f57837819dc455cd53ccda3c7856449c605e7c414621b36721d4d15650e1549369599659f2da8364dbc58c03
231	1	232	\\xf8f69aef0382d57f09bea5fad2d20091927d9710f7ec74b7905fd9e185edfa955527ab04dcd1c124d79d5ac1f587272455e8cfca8779ee5335b6d400fd94d90f
232	1	34	\\x958db3b05b748b069e39df94b59e2a121ce037b192b54387ac79f80cf95406169a0712e210c142330d9d967bda927ea179d46de02c240e036de1ec9c8c617806
233	1	378	\\x0d13596a7604a676700218c156287842ed94c394778edb846c2dab31789f5a7682285a56cc44a2b2ecea7baaa46419d432113b9785dda47078a22b4f47993b03
234	1	410	\\xf265c573dc255d6cb0a302118daec8a62747bf5334592b0a5b7384151e47085a28996d60a4d427bb192797b56f5139e19191f6c362798fb5271a1d961738b301
235	1	298	\\xa4004557a9bbc95d0c6157f58bc7b7feb93c8934f5cc2c75cdfed3839715c22936f69c0204755aefdcb6868572650ce96e5bc742e91b9ddfa37b65b8e77ee20d
236	1	236	\\x88731f437461f67c19feac102e0965e25c8ca31b749209c0939bb7137fd021aecb066c17703950d4f8876bb8f76662d17c1a81737a0a1560e561fd8069ada201
237	1	377	\\x65611a0768983d8cf259a132e368016842741764e1b8124453d2c8a0b9456adcb8856b9363d47b53f05302b1e26433cd816c9127f9ca561cb6cc0e8fe3559007
238	1	382	\\xca914aeec2848678b294eaa31613f2bb33cfe24bb1efc2a100a34dfb4466162c2c04776ccd5b4ef85d7e2fd553effa0eba54c04244a404cf48a4bc9ac8c1110d
239	1	186	\\x12509fcd20d727aac10c2249ae6877b4e3f3f2dbe258fb785fc141257023f2c2a78b1bd812bd639e508b3f41708a4790d2cceb556ebb0cf9a6b06f4331bca405
240	1	274	\\xd61fdbfd98ab88dc0ea289216cf82eec1203669e28d9cd4f0f310b812a153e5372b56c4a51df9e7ba6f24ff741471e6ff3c740308e31b37adedde13325eebf07
241	1	261	\\x758229e7d364786d2a2125dfd0d8853dde771b4b51f9c9b141e4d22c46f21ad9a4388078872a26050fba4d032879e4670c026285edc8f2a43b3752011d88a004
242	1	306	\\x4791df37d4ba997b74e7a1774da232ee7c7b67d791e05d7b44ba006ee92bb6c04fd38129c46ed8dd5076e1d7a6dc4027fe86c6afc5bffd71c06afcfc842d6d09
243	1	116	\\x801831cfc57685ad9d2df044e85ac171a6c3c0e2bb78310574930f0c978246bcb503f4b510a85fe29f1ae86b43a7f3e20514e0167c85a21aaedbbed4b9b0990d
244	1	109	\\x51d39d0638cc2d886d655c8f5387864e97444aa21e0c12778f5e572bf9e9f095c493aad3a043792bf797842f726e504bc18571f40fb5b5bb22f86e54e226550a
245	1	347	\\xb7c2d3a047bdddc39fec61d3071fbe243f67a51440a616fc0ed063eecc1949f078f1998b844d960404f95036a59527efa842a056a78c4232cc3612288079d20d
246	1	319	\\x131e809395b32335ef9587d211b928581ada0b39e25ed4dcd0c74265b04be9a4aebcff2d388c5d9301ded2a64730623dbafc670e757f58513131291449df6705
247	1	300	\\x2444f45e50c349596f2a734d07a7c930edc4c1340d18797321cdb29fb77868985b5587b82db64e3f3d0b8f82002712e55aa456c9cbf0c29c2f51b39efc846703
248	1	16	\\xc793bcf481efb4173c48220b4ca3a808dbf6a40a415548f78b5dd40d81c7c61df4f770c08798a6cb934dd9a86decad1baa269293cfeece2171b09c1c1f802b04
249	1	381	\\xe6f0fb12f8e5a0a562a89f74dd9e1c8d58f260fa90067f2e167f0ccc486d4f4657b1fc26683958f79f8729aa84fb86736dcf242df755976cd6e2c62d73488409
250	1	223	\\x523459554f01aba8f4bb72cb63554dfd2d7c379abb4ab8726b31756ef469b2ed642a6bc5713957d1130d33c11796e4b3619f193d742260d4570cd954e31cb00b
251	1	63	\\x2e49790ba6c968bfe2f673daa85bbaf4b8d118bbae58c5e67224f81e0445ca020ee10247103d704e9a56770065677eda1c6a749369aaa71f48fb18484f29a50a
252	1	64	\\x5cb24d7bc88b3bc8bde47247a33c64b53529b5ee323516184f6bb983f0124c144a368a9c026a19493c8a1dd98d0f9790a395665f73d09a95b5cc7dada9b98e0f
253	1	198	\\x38c09ef2906280f64bfd448421e91bbc9f00547935226d09f532fd16811fe161c5558d027ae5a9e8c0c393d7d6aa5a65937adfa3e85ae481885cf6f80bef600c
254	1	91	\\x72c1af80873da7909f37921da504a078b419d9a6917b79c5e2cdfeea9ed655a804fc3ea1d3b509aabfc6825f9e5a47d263cb1ec543d456d9d9f59302cd43f40b
255	1	203	\\x46974812098099a5167415c5aa2fc0eaa4159cdad9d84984a92feeaee4cfbe2bc325f94fb55d2d84d1ca813ba27616c9b9d5b550b733fc86585b7f009ea94908
256	1	387	\\xe3d16d3eda49cab882b1e8e19f96b88fe783d82a547759d4594593d82a544d80b313a18e04301501fbe95b083cef49d72b6f52d85e1e99b93f266ea06280520e
257	1	55	\\xd7eb2cf316d159eae167ed87c49bd727d5c71a2eb76ed5f6b43e86bd3f2731db94b476f3f9d05b8ffaed66e30a1a2e5e238d7865040aa0a11a36611eb60d7508
258	1	79	\\x33fb13ed669125f6d5b45a6d438292e39e54f8e0b2e2c73ce0c1adb010ff566b30450d3f021d264d152eb43b038b77986cbaffbe5e6c6ad1e7ca88e8d3106e01
259	1	238	\\x5763c8ed8c89beda6cb01d6a527961d3634e0774e6468608a35476fdebe96d4b2107216139c123c309a2cd06b0c9ca457378f67f7613bbab84573fcf9551cc07
260	1	334	\\x59e5ea8c6217fa601349eea4353e01140de9bff402e75437c3431558d6d6abecdf083b9edfff3f2cb5a45a62298b5e8d8e57475095ac399814b438651615030a
261	1	80	\\x4efc63ada43530516298c9fb876138b4132b3f27055a0caa2367f7a2b56a5578638309b731e3e6f02a92ab23b28d33894f9c110a2b2d4c903c8662ebf49ceb03
262	1	256	\\x600883357cbf6b93ed7878677cb57e40270689838ad1ac347cd0662bb3065e3ea32685c8027e0b408cd09e9238cc452c87ca50e63fa51c549b57ac39e9071901
263	1	333	\\xa05d5d67b5f5f480cef702f52f8eef7b99b752b697ed9f79ed5ef4fb743955e5145e5784a727e6511511e05d1b8e975252c25df777bc99d51dd4170667e6b70f
264	1	135	\\x0c3643d3a43463925825cc535c0a7fa055e11a9fae6e3cc8573aa82205b0e5f9ff7c551cb2956d5c267f4b1a84d409ae2493c991643c92025d1ddfaad7d1ac0e
265	1	58	\\x3a539e82042d91303dc822ef2af257dc4c8ba140d82afcf5d5238d3a27620fdffa50cdf44204c34341100be391d6fa5af8d766a2aecdd558026e6a15b7b29209
266	1	48	\\x2fe1722f2e4cec7a6522d144ab5d307f00f649e39b3140cba26112a24b25e482a3457d1768453f3722ca17d8d5dc6700ba9cccfaecb820d67abf7882be0c3904
267	1	35	\\x9d93a0a9d456b69acbf194c7cd7c7f95538ec58529ec61abfe2e77bbaa820e9417a07afb0c078df712814fd1b839ddaf2448fddd615b4b1b03135887f49d3802
268	1	408	\\xe1d740639777023e4855570aa0ae6be307477d523901512a42ad91e2656c370af1956778917405c2d9d32ae128f5a6fa4fdf3408d42caf35e91f6327cda59008
269	1	317	\\x2ba73a7a9ed37219bca57cd672951ccd6215d5955ebd19bc6537c57d4ec3365cc0288904d5aa2f5aef06b6eb365fa03390cd8abf523b7cf33c75545679363005
270	1	281	\\xd12bb0c39b91e83d2d47be157aadf6629013817af2ecd8d68f74bc2feef67bfc2b723d28f08759c7ffa20fac61c89ccd270641674ae80fdc792b269ba1c55a02
271	1	288	\\x34f137e4b70a06cbb3112b38d1f7b42a4c3b9eb6024ff37a3df2581f469434c0f0fefaf713d6dbfcacb0b64a998d58aafff7419797f235b094222e5f13e2a202
272	1	373	\\xeae4fba49daa7ad34b1910a2ad28c4548a55eb0b323f9554ffb315c2500e15dea832741e22dfb828424056056680d748d0816cfb62cb6be6ae7c2630cce5b306
273	1	313	\\x6c13ee3f7c4ecec12aecd8f0ed9f75d1be6f5a855514bb0b6794764e3748e9861bca949a1df1d0026d1118514605d04a615ae98ad244432fa599852f303f8c01
274	1	60	\\x832f129ee9564b789b43286e4749774d04cac602bbd77e76107858fdd3efe6f03c5ccfe7da0e8744b8173ffc2c24862909a7ee59b8db1862245edcc82b75690d
275	1	308	\\x9b5886d474d63155c791248d2fb285843b7aff281e95a3fe4965cfc1e210be78f616a671541aaf13e3861bd8152e3a62e3a44bddb22815d1429d1e71b668df0b
276	1	224	\\x2bc62afa574158c156f7dff9e3dad0fb9fd26e7e27e9d0bbbcd0a43eb0019c955aa29b90e25fcf18f90792f92536c7fe8a31a90b83915fa0cf6acd6ff4c34c0e
277	1	70	\\xa92d1819cebfdf28475b1ca3df7de2579ad9f2009d8281639ca84926890363edef4bc731f8d091ea5007a49f1521ee47656e5b8261bf09b84e363a140677b10e
278	1	225	\\x5f1c204133036c272f7074526035562bb4a66a7c7b8f0a25e0e07d75cbfb32d0ba805087ad60b06605cafad95e291d8c38b829f4fa11cfd1be959d257972580d
279	1	47	\\xeb8887befb2a0f80eeb5b02c1cc219ff79ab8d71ef122cd7fb76d903a35d83be3acac25679747b89ee55fd5d7a707e573bbf803a7ddaf6691fb52b1166b63708
280	1	208	\\xf2326f6f0cbeff8807d3d698de7ac30fbb68927bdfce9b9984f84ed485f57d7833619b9e60253b5e2d3d78ae82fe9cfa30cc12f0c8416783024d1edfb7869b0e
281	1	263	\\x0977eb95b0169f72da5209433ccb788e9aab5b35dc28852f24a5b40b4352eac214fad4db83de0979df910dc899ae8dc94bd73d815a48678adef5864a56d5900e
282	1	119	\\x618159c1f7dbe79064d11544df990001c9e631497521657526da635c14f5d034b9b4be9f9c9b6cc2c7bcd88ee59e9d4527d5d67a254b643a30b9a56db3f31706
283	1	340	\\xa5d64730560e1343d71f465150abf2f81f18a3051cef5277feaf02d6edf62d95c3d61721c9bcd0aecdc9335afcd3613da1664f1bc4f99bfe9e239e55632cdd05
284	1	157	\\x2255b55ffa27ed08baa3536443658b40cf436224997aeb12f0a6e0395df53a6e675707a35392948f11bc915381a62bef9a8a592d4cec834c121f55c01980340f
285	1	56	\\xa3e298f0fef7d50937d82a9dae976db70a9cf0e3e6564831870778cd6a77816fc62f45a3014361ab2d00bfa27b1f67478a6a4523b7f0b130950fc70bd02b9604
286	1	175	\\x26057f4a4ff53df9a92499ec4519aefed1f9fb6de4255c84864d88884b0f0ed1c55399b2fe1a5b69323b3459d1dd8b0a179d3edd79113124602e9be61473e001
287	1	125	\\x11673e053b2623cce969ab4e7c077435fd4a604ea12ee6d55e37167428db9f31a20189c83e119747f605bbbf4f02cd935cc3a4618f6857328c051a03d65ad00e
288	1	278	\\xa1bc8be2a97785ae786a6460fc8afda732771d5abc65eb48247238af22503f4da825b8d498fc4c3b08afc9822ac4e124b49ef3852bc075283a086c7c5fd27a00
289	1	243	\\xca021bea20b44f17109719bc568a75f790af0796fbd0edbbfb01c44c51369ce40c759988d08e96a9478ad6c4faf6b8b8ddf9f6b27e623f426740a9ecc5793c01
290	1	143	\\x5570294cf66e5232bb2b196a3ff333abd036e9ed0db061fb740937b5b8a19417e8bb76f6330d00ce3a888f0579f287fd970aeecf2e59f20c9e8977ce524b810d
291	1	189	\\x2d5cfdeb5eecf052d53c3257599fdbf342dd8e0202d790cd51892174545441cd2edd70b52193080cadb750fdaff7c39e0d0451a38763ba175dde21bac314b404
292	1	402	\\xa2de4d840c940bef8cbcdc21d3adf29593e79f523b2dba9cb2c0a5b8c31127b6723c0a7e68077497ed5be5e861fb88339be8666d00cff015e1faa46d1bf25f02
293	1	145	\\x62973933a3e5b8cbd5a26047f115be5aaf76470cf891c588ba6c014b6ba36128d82695a119ee15fa75dec473a8ad92ccfc335c92304ed9c1d530f2c2235d2d04
294	1	242	\\xca51b8873081116d1cc698e6bd9fdcb9eb7de9c916e16b35c9e0abf82fcea2af6b12376ed908684e4c44140bee122037548e0cfb2b958454150531d919169303
295	1	83	\\xceec337151fc34fd21756c43e439db1053da6a09ea5b271067ee94ac515e0e106a36fecbfa5055ec3a954b597932d9b3cc29bd82e5fa50d16ad35d1bc4da7f09
296	1	19	\\x32cc40d6782538ff6621412937fb71cdd10030c37e8492632bcab9548dff189d31e39dba55928c3f9711094f956e676d1e43f67367cadf544d9c3a7996657009
297	1	104	\\x54f4a9f4bb794716f1665a2a4ea18f77332f3cf43537cb8a9de25e6395678dac6314d5a260c9cf18179b7cf22f0bac17d2c844016fc43bb44377ceb9ce312d07
298	1	214	\\x74591e5c3b7068c5c9832f390386dc6df6f11ad62df818f5522db1f146aa44f3ee612ff0e0c693a0232ffff17e9fc45f1acfa744ab38d74feacc38506231c20e
299	1	284	\\x4d2dbeb6708885e5e855375713bd027073baeb0eede58594e277d80ae475d0d853111e500181b5e705e702d43cb5f4913acecd271ad8da761e8a9f392fccc50e
300	1	96	\\xe74f314a245a3cddbcd2497da2b756d30c978655d7bb1f46fd3278ebb9e9e5ec44dec5ba39dc49e3f035fbd001f2ff50238115dc2de73300e2241c32066ab004
301	1	166	\\x4dd81ff2c889ea1d0816ac343a10d004ddf13c2051d67e3dd7fae7de6a42567178bbe595d097b6b0aa1ce19d63ec6e80852dae63c163ac79634c06a35e353f02
302	1	78	\\xf4e28b531cf02220db7003eefc1a25484be0001d0b058576f7633903d2e17fc90a19d45ec8f2d5f4597db805e213d37522e3823ebca45823e99fa3fad7992703
303	1	107	\\x66d3d15de48a6bcc20ad1f7b3904921d91c0de11f081a3ed25913229fae7bdcd4bea5dddfa8c60c26b3e636ebbb2ffbfe96ac12ba813ec9f59c82f72276e1f0c
304	1	84	\\xe230546db50b723cbfa83f9153625ba3a39bb75b01c99151b9330f3076d7736a74cc79921ca613ddebda0081b6bc74ab6c02e00da0dc740d95b320f92c83f500
305	1	137	\\xab368aead15989ae39588ba0cc514edc751d81462894da4425a1cea724e636d2bbc1429cc9201e97e23e7f757418dd2f716fbd09de39971c19959ce42202dd05
306	1	321	\\x17924b99976d388f8d79e54e342535cd6b8f2cebf99358d059507a2bb76283cf8de93e6512caa6468c088fb076d41c9545d0f3fdc6f1bd5c41303a1d28aba100
307	1	314	\\x640c3d0a01e8156e6ef9aea586250db3e47d8144c1cac8b55b1884211d5b5101d0ca1c27120a4492b0a83af505baa3ef7d94806ce647ac44adfd1c150ea93c03
308	1	32	\\x7ef5908cac8fb04ea123b62df18606491c0e859cb2c24a12db254a3f3c25becef37acb916d4480d5304b042e4eeeb3e9f785354491f4b08373b89ea8522a6508
309	1	332	\\x28e2a554430125ca49189a446b01eac5fab4aca89fd18c527dea3441ee95f6ae4154a6b628f9ca861408aea86144277fcfd41e8acdb706c136fc76429cf2c404
310	1	311	\\xa2bb850aca890683dedbc24f6faf4b5e382f92c62a03ca3ea809c5f106bf3274fec6a1a80eedadc7618c97189c2fabff37d0cf4b2e61d798e6849fc522d5d908
311	1	339	\\x8276262b4f8e797e764ac3494c2d3f58a0d57e1e0a7e077bba89c48564203d82d41fb4a7443e48a21e38f0b341e7a5d9f9c1673ffa0521c1ee6faebadc65a009
312	1	155	\\x8e6621f57b8b7ac931360c508a9af6399673828a4a1e11fff8754b58ed58170df9fc430af222bed2e87fd898f95ac72d4e1e1318481497209f0f2b4f104d3a0d
313	1	94	\\x7c87aef9419364ddca32a9655e8adb717d2ed29419d7b65fd867b9ad9323ac17bdaa937f605b6fcfeab28b041f5df1c61f167a6ee9de5570cb6ae38161867901
314	1	216	\\x9bfc4c644a4bd777970e5797cf7d19af78dc200227974b71f608a16bfb49fbe3c21be558791d8c37fda4e28028617885fe4f6725a9b8d6a1a79291cfd6085707
315	1	371	\\x34e3e13c782f5df281cc30765a22c40ce75e696c77fd81097b33553646065226c4b5a649a008f0220fd37bbbbd6e9892c7ec123b12fcd9bb1ecc922cb9bc4b0b
316	1	251	\\x41158be66617149b969d033d23dea53f341f37df81a6de5a4054e1016c2726722d915264f48d8984064d93c0f785672d505329d30da9cf9a799cfe2f5760250e
317	1	1	\\x66822d3aedc6f7538e5e672c75684c01fd408323b6e90e3ae94992a0bbbf9cbf7fd3fee104a4608100df5cafb181288d80b2a8d841c2a06bab76e92008898e04
318	1	320	\\xc4eb4f2c01080c853bb4b3756137eaffd4968841602b0bca8dcafb72098db1db74f92499119bd2dda6e5961e09518b99e5046d3c1d05d7c5826e5df8971c5c07
319	1	312	\\x2559b2a2c9200789058e4c168371cff427a52b3a34b9e5e12494910f01f3f453fc99eec4eab6963624c81fce51ff856df09c4e964a155949dd872949b90bc603
320	1	17	\\x1c1836f69524b26b8ddeda65527515769dfc6fd28f0be9aeabe63b500dc8c71687ffb9e9b2413609bc06b333ccccc5ff31b14bb4f98055bcf5fd2a19645cd406
321	1	257	\\xc0db2935aec4953cf01c8f81a9e5c64838dac8891f0b0e39e511f69e3a6f2948ed06845c542f62e261d1d7ecf52e8a453639b2f7c218628b126f902087a88707
322	1	262	\\x7467f25cc499bbac77b3740e287355ad69e26ecc9717f078bd401765fc0419c7c25eb002926f4bf7d40fb1f74d08881facde67f51d0a55c9f00b263b59e24701
323	1	147	\\x4fdd65232a256753b50e65511d02f0a5b07af0510d9ac6956d3f870dd6654d2419644df6ba1d95e6758fc69b4dd41975366675031ec0bf108fbd9e172e4a800b
324	1	111	\\x26cf7ff6b6a446d0557b86d54a4f0cb4cecc298ee067681a459f529ae498242983369274404242a0ce4c52c98ba60a9f7f5d3a641a219b5a4e0f42f6fdfed607
325	1	115	\\x4d4bdabd1caf7e95a1e9af5e747af906d4f9395edabb3d850754e3b5d822b34cfcabf2d9363326ef3333b7d2499d348c7d1f750d3bc64ec5cebbd4977dbc670f
326	1	322	\\x2232d232b1add072ed9a6fe0de0c960d8009d64efe9971c7342bb3134d1a915f3d6e6647587b550868c13a9b1b2910c62b961fa47991558d67a6f1206feed60d
327	1	384	\\x6f69fb829d4238744e60f0b3b92ffc3a80af06903ed80ee2a985db069ac5c7a732de8f315e2dadd226a97200610a1c163a58d94bdb794ea72859a3b3dcd1a10f
328	1	286	\\x2ccfea5673897ec3284e8d5cf22cee0dc87502ec3501e2e994d0a741a41d61505034e483f1b99cd2e81fd42ce2b5e49de7c7c281f3b8406e2c57989fedee6a0d
329	1	142	\\x410039c8788374dceb08b2863a4efa0d4afa477f3105617ff862f67c7deb872c33d630db1cd32921468fdcc7fba479be3623eb813396faaa391067f143909902
330	1	44	\\xaf8f86dff43d222e846f31be3c3e8280af34cf0d476efcef67ccacf64e81db3ad399a4da59c7be12f3c7884d87f1bc89d4c66cfba28b2ee0e18f5ea7e901c904
331	1	392	\\xa5ce0900d260c67163145b760b7048f3961714b8f728a655dcf073db71730f83890d4e38ef011a42bb4c94db6129dfc6e28b920f6c4381c2e868b36417f49c0e
332	1	370	\\xc1f7e7103a11e27e331efb0b09490dfddea4ae153797105684adfac9b532398d9a4c2f4b40a4405a59d638ffdc4bb68eaa6831b785afee4d35b52532c9a8cb0f
333	1	10	\\x3f06ba05058c3e39aa772a4c1a35b1c1c68fc57b6baa4513944f55f04b048fd16536c6338e094ca06bf1772f703c418654a67cca57355833612b0e1c5de3c608
334	1	152	\\x75e9b605043b6ddbcbd78064dee28bb83c227f2746b53c73f0624176d7b39437a2773d48c3b61b019c36896fae2d214fcb0157683278ce59c5b4dce2c0a4c808
335	1	206	\\x1cc1f9c9b1abd3691b7cdcc1dbbbe643c5a002d32e86b97afa7955485a996941fd67bf363564408e5bc5f73c138263db7ed68898cff45a1f0684afaf011dda01
336	1	141	\\x343320033d2b712350e550c3ba5f6cb07c1b4db506dd5abe93512e28c61ca2b55e01982ed856434a9c62c708cbd223a7fc8fe78f0d21ddc47a2355e3c03a4c0c
337	1	359	\\x786506274fad24a2b233981b70a97003dd6c7ee29e4bfb31f8a8685d982d8a621530e703f8f96c19150f9122ca280797663583c05194b41311295e7dc2a89905
338	1	188	\\x70f2f182c18ad2c7a1a28bf3c789279e0e3a0491356747b2c040ab3f045076e7fc6b218907a9f611495c3b5a0abd6e84c334802b972857915864dc0ea572f306
339	1	219	\\x872927780af71a246bf30108a917020fd8b96ef080c3cba212cc315c3b1305592383b8235bb4dfb1da256218f283b54ef9d753ce06ef77743213caac6428310b
340	1	98	\\x841fff435a620768d1debe91c1a4af79fe6bbd3319821bfc1ee7172b153ff8f2b97efd7c02940b58132e56629801d8c14ea58e170e93fc92923a5110ca2d8d05
341	1	297	\\xdd36ba59697df74a8d8448e920a78a95547850405281829cbdad6ccac3717de30b134fa8053d26f1d1c123909e4127c2d3d72cba864e3794eed939ea36671207
342	1	204	\\xd763f429b0af69ca37db098eea8cd7939f8857459b0615d143702b4add4c2a6d362656fbcfe96caa39cf266c1009d921764bf7a8d69b88a9797c5855336f1a0d
343	1	124	\\x47ede34a75bceccdd3bd8f0d528b9be6dac733f3b7adf557ddc22f922b59950a477c39161ec36afa0cc0b577ac9ebabacf0685874fd2ee637db3af3b1d55f209
344	1	304	\\x52a87c07de170cf7d56c4a8ce6d287295783a4ba568d6a0001c46a4f73703d5bf4374c06caf2a8b2bbb9b8d7196256dab2422a27ba0e5284e6560d891635010f
345	1	283	\\x68cc8a621c20cfa1b870a8df93467cb3fa49532abc9984198e4e9c4e4f350b1f884c98fc3ef1fd9cc9d03b33f2ed589d46e84405df8f7ee636dc40a860ba890f
346	1	132	\\x767d69538586f6ac16fc0455add8d6b4ab3ca6558dea1584a1af99b59974bf74494bd583569fe5e1c20f9e2fdb62993b247aa638ba1d506701677f3498267c02
347	1	293	\\x75839003bdd843a5d75e6445e427db08043f4e7800e47b76af6605c24182fc9a6f58b98c649eda59d5d7bd6c9fb201dba88f14b73296057a6987503ce589640a
348	1	404	\\x399b018b1a7b6280f6c76de13284d89eb239f8ceade74f4e15d8e9b91a0bcf774e0e683d7d1704f786673931893cb1d1e8c3ce5f514b64c596c956afb0328a02
349	1	61	\\x3d8b9dd5fd508e5d02f71469d957c0d4e2fc7b5f39ed9e87637c85892dfb666ebd1aa42f1f9bb7f0efd3be8219a2b6f48fa1d145bcaacc6040d04700b789c001
350	1	129	\\x5141c7a725db494cc5b4e7084852bde0a5d3cb3f6b4d8b8559219c3f9084eadd79ce6a8462643a46180bd502b0d8226e1f4a77e3d182f370697843fd05bf4705
351	1	24	\\xe497cb16ae3a74e2930358a24c1317cc1f5c17d9911482d7bf2ec1d6bc602f56ce723763ab028cac0bf5291ff8941b947d244cfa7a52260d568db9ff2e51ae07
352	1	237	\\x30de9f6c54c755a20eb347e5305203ba5c9196eb54b668079c4227cbf3e70cd9d895eebf66888503d1ff77b1615fd921e1850405a8a16ce8af3879abee1e2c0e
353	1	226	\\x85c9a3ba65402459fd145abdd3b82afd28758e56221b91189c0d96e14c67ec5adb9f36491b069daec11b7819d4f047452589d24687317b989a1f379c111ba804
354	1	180	\\xdcd8a51a3ff2904b6eae81822f2e5f8b955a60372ade4de4920cbd549a2d5d7bbb08ea5b2fc12a0ed52047119142f878d1cfb0567f7df8682eb2b93c4ebeee04
355	1	418	\\x7b3c0ff5dade32ab6855b4e2044fa4cb073b753e7499876635f03d5942d0034949a80555d3bdf7c84026df988e297ae091e08423cb47add1de38746f50d1d606
356	1	158	\\x5327659010cea6aab97495c15ac4fa5d9d66ac431a3f085adeb4fcba8fc361628019de5330eb8b9c16958c67a8d020107ccf62789d95efeceacf294ed3c5d100
357	1	6	\\x7022458884229d3daf215017a5302780c1148dcacee5d296074fa36514bd4b80b60eb2ff644c8349cdccb0c4f9e529f3b30fbee21b91f3e08443c8c125c8ef07
358	1	179	\\x605faf357e75b7d688dc1869200e6313ce3a9405d51b9197524e0106276a1c5dd862583b8d8e9603c1c688de0111a019cfe1b5919403018e3d70bd19494fa40f
359	1	380	\\x480cc00dee37eeb9912a463ec3e24c1abad667d1ee46f11e870dc597050e86df8a2636782289b39699cce668b95890973e1387781e7bd7c0c7f14886349c0100
360	1	173	\\xa97e7aa03e80079d0408589485d304f420324dcdea0b6a7e0bce8e7d75a2724b0f59b5d9b2487d4ec7cae0f6d67c0da34c3243ec5704ae7942f927c310fa6b0f
361	1	62	\\x81046834341baaded120bfe58091ee9802d47dccd3775a0638c23b777ff6e249eb3aeb34176539f5360b52b00be09ddc2bdd83b48f426fcaf369e592b1f2840b
362	1	7	\\x4c27a16ccb7ddd7101e7de518ca2668ed9f6b0efbaf1909a40ad3aa5f07aa95bd3a7edbe70b3b01ac230cb791aa4387c6cc7e38ddc598718957a83da6fd34808
363	1	398	\\xa2dd7f9fb3d953527e3b03a04b1be3be34abbb08815443639e3326ca171f1cd016dedb0d6c4dbadd95ab857e9d815b5213bd13c58cfc7f3fc17d466903a95205
364	1	8	\\x751def4011ad6c9d6d032fee2a84188867d59938634fd3364b202a4de8fa1bb077d0c7a818938f384a231e252fb3fcb7b02fe8c580224320925d9b93b4da4108
365	1	30	\\xf7598a5c82d9a64d7934d351c92cc09aa6e5b6ad6333c58bc93527749a02915ab496f993e6ac41fba81544f3bb28108ffeb0cf6c14bb036237312f0fbfd2e102
366	1	108	\\xb04776e9dbe96de113b2a922b7eba02fcab626563534221187536e55161bb09e45c88dc0462c680d05b8bd8d86229048b52a029e689ca093a3619e61d58db909
367	1	228	\\x01b36d1965264e5f148b9f2b48f74452c067af674d24f70eced3af5b33e85ec13c40223f6c6678a5e9c3c4ba843c548c48338914979ac32e2cdc2c68e0c5c805
368	1	21	\\xdabfda038139c3efa9ee11aff7003f078ebc0e2702d54c92d65922cc953d1f0345ad74b868d27945bf9276b8679582ffd9be4e4a28bb5f93f8481bb8251c8200
369	1	241	\\x0521633366b06b2d5bdcf3252267835a627e9ec4e828e0cfce5fd5a917b2f17e8e9703ab4e4174dc403e3384b970674817d2ac1be8f512949302b91441b89a03
370	1	110	\\xbafba843d86b2720f5aabd422ecef14a9d0b3dfbd093cc2668e740ecdd5d5aefbbcb54bddc8363ce391c1a29ee77edf34e7a2d242f779af23ad9549ab811740a
371	1	354	\\xc2fc29c72f5bf651478bfdd9706c9f9fd86c59c5908893e49f759f9b3fb71ea775d772f0ba390b4f114efcc1504d2546064283c5f35819ad41fe9ebe265f4003
372	1	396	\\xd731fd10f2bf00b7150791615da0a343077f80329b2ba4cf73ad1540f4b7f3decf70f26053d3fdafc27f35760c37205805569051c8e90a267956bebe7e2f7607
373	1	160	\\xf0766c4d92f4a08547067aa2a75d34d40d5e67cd221243e4a3f08f0391fa58cf2b3a729a6c206f15bb3f9ac7f5a32e137a3b399ec0b92d17305fb1b50822da08
374	1	87	\\x035bfd645cd82459cce661627714584f98bd134f2759a615696b0ae63bd4c4ef698a8bb198bcec840283ab0837e900e29f6c642052fea87924fb64aa8cee220a
375	1	301	\\x0aff9128fdd0e2815fc6f02c27248261888031010198e5d4497fb38e7e801188fe7a14571eadf07ef214283caea68826ba3ee214d52ab67ab20d3e1f25066f09
376	1	92	\\xc8607696f1e9ba44820b0b30d1334d2ac5ced6025b46fde356f5bf67ebc58c1e19c25ec725dc2f3ba5011e490ba251df4335af536a1d3dcc432496f674fb1902
377	1	335	\\xa0e1cc72beb408d39476c7cf7f02f50450b1f9090a178472179877d3bec48663bbdcac882fcea8a90365ff15fed1d4436c2ac41d8c0c8f6fa2a070e29dce1204
378	1	291	\\x13e31394d1a600f5b8638e2cd8abc6682ab9777aab3a4fff5be22d1e83ebb9ec9c51fff7562b8cbcff6f5e5a3332913e1216a8e9d520538477970ba98e71b400
379	1	352	\\x9e4b44b9b7278489148b5440f04defab8e20f228d5f8842aeeafe98f89d0d7f3131f7cf0dbb9f3931ae4910127bad133b4387ca08338d06dd6dfbb17503d100a
380	1	365	\\xdaa0a3950d46a54ec7a941442f029817b51735637b9133415cc8ddb2e9a836ef7054ac0b0a449a559dd5c5dd9ef730085c2acb2ec46e91ec802f150cd0045f01
381	1	11	\\xc4a86a60c8997f784a4408c94858f4e5d4c340bf3f33673b4f010fbcbf37b5a375611116429e1f61d5eeb76d98bca3704b0d3aa37db2ab6f0d6cf866e890080c
382	1	231	\\xff0e3946bcf3979f116cc9914aa8241b66f663c82ad64ca87cb81acec78aae43822cc8590e7c4e15ceb7dc70795828acc40ae95be60479ba395afe5eba683305
383	1	201	\\x2d1b8f18038a14b3ef792c27e7f7e03463f1da763fb8de89b54597da2bb172cd1a10ee2b23ff64b433d8e2137c040dd66384abe8eb4b295dc7deac16cb031505
384	1	287	\\xffdb2df82701e2d5c208f3923320de9893310fb4b8af1e7e2522a56be7376c24fee08ff28d097a23ab889483ded7576ec3ba7c97b96ac3a8b2b367ad9814f004
385	1	77	\\x1118856372be196a798631694b1db4cf83586f69541561e2b14c7f97893221d1d3180ba87885a974030f340185811c0f4ab0f37f09446f55fc2ecdfac68cb409
386	1	81	\\x83929a4edb4c91d26c06815267c83992e4e24111021780ea8f703a8e04bb3c4ecb471cec2056af76de1b9722b8e984d916128a12dc7d15c36a125f8ae08d1409
387	1	139	\\x08e48f406b15d1fd851d066befd34e3d90faa2b61b2208148b9adad561b3a482c86e78a4694534a3f59b38859ca5aac1561d4c0ec880d27ecfc116c4938a5100
388	1	357	\\x2433d6412f8b2e19d6a4274295cb56c7593b9572f85d42b641139f8a743ab98c3f5e9125276c7bba850fe5bbd63bb2e01c13918d833ac47c00edd36ac8c42a0c
389	1	409	\\xf518ae71b9ba61e700e59e5268120bb59bc71e12e50cb904fa200b850c7cfa7479344ee2ad20b762d73b80dd35c54cacab88123f7a29438def57e73ea3d8bb0b
390	1	164	\\x553a2b6ecefdabfc8aec91b246b60249c0a3857b5470a60333dc45b186afa4d12ec0afc4f20482d3af640b1771e6380a67f862bf252c9d88edaaafd25dd3110b
391	1	275	\\x4aa78481b217a1a9167cfbbcfee8bd52b02a8b408cfa9198f37214c15adff806b0c26279bac4c1db2dbd30ae748874d64d3a7f717e34b46a8760e0216f38240e
392	1	144	\\xb97c78b543c428be9ba7a684372d065afb861580e73b0b0c7ab6a79c557f063de094450651888991eeb7d35abe0b93b78ab92f21b850e87d3925e57c8197340a
393	1	52	\\x5bc76089613b569487d4903b3237a89e06de7a79058431197f5ce92a80993fd19b304fb15a5f10d2ccc13f17937c898825d1c26ec48e7051c11401ae2b837f03
394	1	114	\\x8a9266c792364c3ffc7f4bb10b3012569d2527eddd4f9666934958ed2b8e57b138b4239a331ae12cc4a39bcb68c127c451837dc4d1496fee6ace6cae8617e000
395	1	400	\\xdf912ed4b71f34995357a73af13cd9fb6cf3b834b2170982c9e8d83e21afafec75aeb29a521c4904d33cf50034014d50dcbd8e1ee873dfefc2a8fd9bd5416002
396	1	190	\\xe3fd04a84fc2d9185b2a395b814dc4f3330d111ab8afdf32c638000ce880842b1d6bbfef2019f21a989eab001cc0de2bdf58cb2952f7b639e9e608470e023b04
397	1	85	\\x71de29ce80a53aab3b2dac3ad6ac3689fa3374a68465f0e032b758b8b9f7bab0fead92842ec2d0d23448435226ab27651579d01fd53a4dda5b2e475a4c1eda0e
398	1	191	\\xd7e06432d1aa4fb21eefd5d32188376fb195b8523f3ef64c5f4da956439aa389ac7468b09f6cae11d5b76539eaa92695cfa873de3c720cc06157f8c22de95a0a
399	1	345	\\xd1b695e417825e1f1fb39ae755e504f116d4a4e60afa8c9f2d622f866c77b04b547554b0b9c5c5a0f62152e50057ae09d4bb07f6392943e24986bc52b989e70f
400	1	350	\\xd4ee90362f135da7ea473f828c646e24d8fb4cb4861e7d18597d9f553fceb60cee8ce2e1a63bd5505f45600ec8eb6ef8c9a26ace6cf749629937e3107597b806
401	1	75	\\x96cdbff91b7e481d60ec0fb04f74b6c6687b8053252d2dbff3abb9ac3a8c25871fc15f96f24b0ed9c220d5449bc8078d53fc8ada3efa867d9b5561f7654e2401
402	1	295	\\xf15558c3b4a7092124738a806718f65e1dc94aa72ba913308c49822d6287b225e4acecb2bc9c626558c0c2ee6d61f82f1aed41b265d85d9db64a61e85d3b470c
403	1	391	\\x48d1fa82c3484e5e55bee86c3a8b921f872afcf73a50091a918bcbbcb1e07e479b8122d048a603a0a509b59c8ab56ccd4b722e755319e7261aa7cdf1c5adef0b
404	1	18	\\xdbc33682cc87a6b063ecacb7c3d0a329b27fc0c5054d3df3ee2297bb71a9631d2db84ddb6cd1560bbc328164e09be236b712f866d9e1421457a471521b58d206
405	1	88	\\x54f78726d3ede0463cdaf6283a398db55c226444c0c232ce498302eb59f1bb4ab99b526777af2ffca1cd7d92bdd0f95de2f4578b5080a6e2d693feacfa78d701
406	1	346	\\x6265e76727945836ccb2992f9ee4238c9bd441eefeb339fa17a1ed2e348459d73aa13238316423389ec0fef069964693d30974855a0ec4859e5682aa35369f00
407	1	146	\\xf1688f9ae2fd9fff6952dd34e3f4c6b0be73b023bdc8d213a1f86741cb00bb6d631852b9bd07b1a49114ba4ff1f4b94304743e2effb41263184499b064548507
408	1	122	\\x20a809a34eed7fd3958b719efe00a8f7f0c085c58ee2e47fa4610d12804da8e9665297aa61a6f5668da8d766a2b02bf16380d1177bf660e6d2b07d58ed006e04
409	1	337	\\x67da11e0e34515d596fa251a386e65c2390c8d1075180210835dc055fe0806013b5114b45a4705ad046c8947548064de6db580da51d9e24cd590afba2bcb2008
410	1	150	\\xa584edd0b0ab4202903670d7cc1c6e695e77e749616b38ba4b8d4af042cb14565c98fdc70b6a23f0c6c0a3d6af07b2111e3f0f57197109983a052b7037e3ae0d
411	1	296	\\x78ab3275e3de7214273a887fc9698a11712c5b7a5d78e8b49d93b0f86c2a4ac391e1dd0e6b578ff1105e91a8d54a43b948cf1838f0bed42653573e1b9b0c6309
412	1	50	\\x04d3052e18f6e4c195cf08f64f7f717c08856389671ba13371978761e62e26f55664ebcee3b32210a3db44672addcb9aeac64443fd16ba0db9a220323de74307
413	1	266	\\x3e0b0a541cbf90dd615a8d8fbf61b13f80c9780f0e1199f4f2ccfdce642b58ebb070b649d09a486f49847c4382d1a14d087b93d38321a26b1004ca4220479c00
414	1	33	\\x01be746d31c9bf34a849baeca5a0a4ede4db338bb1a135438cb4a09a4586a3da6f47e749b0b84ea59ec2cd213e8fc081ab9e735bdc295ca6e7a2b73df8578a02
415	1	375	\\x13fded7f8e1c127012c8f85964fd50c9d5a3b4d2844e6ea78e12a2c508101debc961ce92fa36c3568f9687ef78e3b629cc31b3ad4723bec23be18d18e4530a0b
416	1	264	\\xcd3bc468d4960ef58b782aa01cc10ed39cce77add9f89b9f86911372b44d06bbbb885cf03fa5f14e425f04e836b7bde49362b3b34b6d50066f41a3f461336e00
417	1	327	\\xe4a06090da07bdaa672391cba9594bf722ca7a59837b9778c7fbcff4fbf5a836edb1ee9c012743a1e6661bcbe5f3e54fecf5c5ac6ed7da9bf1bbb42a78dd340a
418	1	252	\\x0fc3e87533b4730025e487f2ce88ff12c98d774759a11c9673d8bc787834b109f1439c94c92b3a9b1ebe3b9143bcffa3cc2be235ac8465f89f2680bb49cd4d02
419	1	419	\\x3214c2c4a3e2e5213ce1120af49ef6aa210d67e13b310a0c0ab0670d4fde2951062132455d8990d5a7a541ac51839122ee188c1d183588b3307b8d1a928c0b05
420	1	57	\\xcee7969ab6cbd4a694be467d678422874606118754694d5b8330d90f2d34c4d2287e08993a393ff7330bbff7e60ca15dfd1a49520379465fd910e82556d0cd05
421	1	23	\\xcf7f57a0497ca7bfa5ad7db75d93085c2017b851262e053bc303bbba5c17fd47b14b442ca6aa959c0a0ed8b54493b39b1c3a9be6df2c925cb5804c7a50906e01
422	1	406	\\xc713e2b31264c4e68fa859c7a07c4192910eac13f07775f0f66cf47f88642df1991b16a2a1c2d30cf3d5b53f4c450f0b1407f5553377f8bb25bc5dfbe9494108
423	1	130	\\x8ab679cf375319c535c0735946a4cf06d7e4df1a64e77e27a55033a86929f4568198900f5e3377846c64687531b23b9ac18ac699497c06ec53360972303ebc0f
424	1	315	\\x5a7d74657019f6e7aca36588b32223d6555e2725bec693c904030307ab3bef3c43b3350c121adad978c75a15cf66268609cc95ce2b2ebd6ad62191ed467b1a0e
\.


--
-- Data for Name: auditors; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.auditors (auditor_uuid, auditor_pub, auditor_name, auditor_url, is_active, last_change) FROM stdin;
1	\\xaeacd36ed7059622013db963446bcc2db8637be105c268218725b9e29a524a74	TESTKUDOS Auditor	http://localhost:8083/	t	1660512333000000
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
1	\\x02f4661811dfd4416f736425e9e3f90f0ae9602e83a2cb9079dca599abe60f0c1be0fd1f19553bd87f025ee896c4bf9f9582b84625c7180c43eff485b4a14c4f	1	0	\\x000000010000000000800003df931361c907d45fd118257f562d029481b7957714fe5c7ebd427af86efc7e66d9852d77528ee50ee5dc161d130c2c2d9af72c8516dfcc330d55f89999548a20e172d810e28d72103ccb5040e2e919aaa3a96f73ea65456e51c3f3e8e76b470adcff7ca97bb13432e84b753e8665bc5e0764ee5e344a0e2c6533c662873da4c1010001	\\x40c7c43c82538de766e64dcedbb26989a21ada2870e2294e43087b1c27b4bd6a6c8ee3f007da1fbe275508eb55c3d28d01a8c32d264fab968670443da4038d06	1668370826000000	1668975626000000	1732047626000000	1826655626000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
2	\\x07d80a91b022e2520467ce7d1d1d6e1a423b7fa6c790a139255a232c21f5b8da5ecbf74ab0c76fe90e33533d8e35bfefca12e4d04fa1a017212251a86776f1c5	1	0	\\x0000000100000000008000039bb6f535d73d2395c41e0505f1608c7a77776eb6e16e3afbcac220e656284576a5c88c81a414ff1b74532aacb149863e5f2738ed3004b3814d7da4936486cf6ee3a82ebc6465e1b7f9e59c0dfddeea3fcef0f22f234f646f1ffd7081ab68270983a2b794f28904ee0aef3206c38514e32e67b8fa534c3f12bac50882d351f6dd010001	\\xf4958217f4ac8d3ae7052bda229e01b91e049821dabfc18fc77a735e9c8bf724e3b42a7e38ec6e644a06f26565d568f130165e1671f3a210fda9818e551d5404	1682274326000000	1682879126000000	1745951126000000	1840559126000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
3	\\x0720970dcc7e2fb97a432c3ba86588902c4f2a7840e101a8e60beba89d94eeb29c09c777ac22c01384c3e6f97aaeb46e9a9fe774da60d7242bd38d39c500b37b	1	0	\\x000000010000000000800003d12e4dec501b9b1cc256c2fa54fe59e9480f410e959d73305f241746ddc58a41238e21bd0afb74d63e80bab2a9fa8dadd1a46c65560da7b997aa744efb9a15e384af8f0629d15e202bfdcf15f460985f340427d2b9c1adc5f9dffe96f918a2b87d1963fb5a520296cafefe91c64b15183736ee49825c48d098c8cb4fbb162c47010001	\\x9f79fb7d1ed437cfc562d632391110a3723b96f3503b7c1ded1afae2d47f9b697b277c3f1f85592d8e2039bfc3a537cdbc0345814e0e2ba47ad92a418c024605	1690737326000000	1691342126000000	1754414126000000	1849022126000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
4	\\x0a849b4879b066832b9315669cf269c31867712f79c10599bdc68556b38919e8a3fb7fe68077a766f78d4896c6f6fd42c3cc91d1edb17f8e881be03e4d48d311	1	0	\\x000000010000000000800003ce71712662d13fd819648e71b7b8c64e8c3a391d1073ca0f00b0c9b3b191e74d46167d7dbcb1eaaf36189c4a7cfcdf768d2ecbe8d6c001eb6acf99cb4cb937de9f7ba0678dc311406ebf0ced9b4a6771f5c4643c262ffead2ada99ee8ab873ca7536885481bb31a8fc1046c26501830bacbf79fbba885f672402007572ae15b5010001	\\xe3a242bff53a08b5d9bbd084872723007cbc949c9700198dde5c41f1f89dd7fe7204ea9f2c6a9737f156dfbf4f713b4704d2d7f2d7eb6b7ede0baf91d24da70f	1675624826000000	1676229626000000	1739301626000000	1833909626000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
5	\\x0bcc10c86d3694a27c61cd248ddebe1214a02b9234930b6bb227396073eb567191fca5c0ccb1665e0c5c84fc850924a6ae8a65480edc6092b09490b76b7e4474	1	0	\\x000000010000000000800003a281fe880765d7a2cb6d923ed1d586cb693520d4b6f9294b50d7c901f2ec77a54ddac53fd15b02cf168204334d5cc4041cb33aebcd628d8111bae7c469ad4426443954e870c7723aeff4ef62117f417e76579d7494dea04c698d7e79ce038b24df111ce2e5ae39f14845639a3225f86d6c4777766c30f684c3d1201e88d5b767010001	\\x5c7328362354f92c2ee2e866910376a2c8899090cc3042a8f9dd8e46dc98692ed3ae16ce557cd3dd32040da44b10dfbde66dc0baea82858bdfd1d2208e350707	1686505826000000	1687110626000000	1750182626000000	1844790626000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
6	\\x0fdc3055b4b62293ffc86c775fb211660c011220dffa55000faa2f95690cc1af8f48d6d802a501e03abea4bcb773a905da66f09d3fc73b9f75a18da5bda9779f	1	0	\\x000000010000000000800003ac16a58d631bd61a07a010b135a3d3cdc80c61619d27d14a253a6e19818f68b05b8e3a53b5799efae351b3fd40e81ad785998fa84928045f1261748b51ab8bb87b274ff8210bef15c148fa6c326e30797acee40ba5cfd46ace66653c0c44347df3fe71544c65631aa9968cc846bdb454a150348e47f15e988154a4faeb7500fb010001	\\x944c80ff6826b8680dbf96569a893af761456bd576c1f8289dbccffadaf487fc4ef61d32f1b9ea2680f943f423a18ee7937553daabb7ddd2299be2de25f5cc0d	1665348326000000	1665953126000000	1729025126000000	1823633126000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
7	\\x10381ec0fb89a75436647953442da93dd3a912d95e73d47ba4c34f7cc58d3467e695d152c73dff484bf95ce6405a204ea87de787929ca130008183fd53383558	1	0	\\x0000000100000000008000039bca80a6a4f25e88f0cdaf7dc399a41b95d48e1ed5f75623e66bcc7c882f61f8d1b18f9e0d1ade85aef5e5668f7eb3642bb0d7f9a5140cb265cf43fceef0408b41c2f3c59b1c4f5860bd50d37ec055747021c104a6a8ad3d7d0d5d5abffe3aa3f4aeeccd82690fcff50c0cafb48fbc02dfbc60f729dc1d4e8ee6376e2b5ef425010001	\\x6b2a111a7a91168d9b777e9350069f95480d343e31770322752488cf816f9d2d1766aff475a9e6ea4be73b160e7a5101b93dd9cf9986b0499cf278d48449f004	1664743826000000	1665348626000000	1728420626000000	1823028626000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
8	\\x116480fcc84f6dfa9687e7b33330028166d0e649a710baf386cff2e0068431eb43c06502364d8d900d8e5759d258ee866ba2dcd565b737ade52d3269d2396390	1	0	\\x000000010000000000800003a8be00585a951a78db53bc861696e1b5eb9ee91b1bf43d218ecdb20e82eb0e82ed7136d8de1f8ac70d43c8931a04caad7fa34f2cef0924a28040b49126f1c144281921e5f2489a188027a9546026406cc620f3c15a3f48f574af7867054d699814d6eacc40c576634a85ad98322b7f13b070db252552dc35141a1c3cbfc7dc79010001	\\xee9fa86b82637341b789d9b7683e9e0dbb341eb6b650e1202a05530619fa347475120c699a411987a5a8dd70cbf4f9c71feb147aebbd7cb5d2dc04708cfeb007	1664743826000000	1665348626000000	1728420626000000	1823028626000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
9	\\x12541cbce05a1bb24e0018de83289538472b6feb8fc3c2940cf04e15effca9bbe9ab8d67bd4751d15d9b709d25357567be41dfb34a1acd5f716a1a006e8ffd23	1	0	\\x000000010000000000800003db24f06055aa0075533496e89dfba864d904142824190363cba721c147043f82f5f4ec0a277a5fd2e1759339c6d863f45fb0f40c2421a6710122c52f084171cd417d1c1398d07089978d72c1a1d8a4324760c1576dc2166f9f2da332b2b89e8a4442577ee01158214984dd70d72da164bd6801116b4cd82475b4f006db40c5b3010001	\\x70cc3fdb2edcf18f903e069b5e7a22843efc8753265ee473ce5671489568e1f15982e96e4a27d5a55945f11e8a7cf3bb7fb0e3c56cc8173f8661145f7a38dc07	1688319326000000	1688924126000000	1751996126000000	1846604126000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
10	\\x134c2697f6e6478bf86995876f439d0c805dff164a6c29e7e59db899c1c6129353205008162cfcdfa7fa0ba54159bdc9f441e86118e5b9306456a97e69d717bb	1	0	\\x000000010000000000800003f9a1e5b018beae47e14144c9069985cba69463d3e94ad49249e4f7c231440d059dab34466e51df2b7191eccf35254981581ba8fbac748dc76810673c6e03fe92732614376e56af1d433d4121d9c253c710c6e0cda12aec9f3979faa401dbdaa68961c3125d397a6a387ce3b39b2a665bb3892ee9677945d71d45bda8c6b03e5f010001	\\xd7b681fc74770f6219562177533da956798f668774871b946e920176411a7adbfef1b35cfc75e241724232f9e83ffcdcbab79afc8a450dad9f715585e8578607	1667161826000000	1667766626000000	1730838626000000	1825446626000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
11	\\x159cbef6dd88cd1d7e271e6193caa5328e34860b459c1a725c245e232c6e32cd048b2508adf7b8ad9051c413401047f7b72a866d08139c048577c2149fa2bcf5	1	0	\\x000000010000000000800003e59e618f5edd09de5dccdf102f100d1488bcf477988badffd696bb6603d415b63439052cbb7ce6118d62e956ff6065788a20abb886ca745d5cb120e50cc85c15e4538ff2916720cc6c7950dd17d47f3725d8b62f5a50af692c21dd92a650a14695ab84869a5e6c9523504407861e36730d29f49abec8217b36866851f50280cd010001	\\x76c82fcc9f17e8374371e78de22a9e4cbdb863e5e57428cdb8c58dac8b598fa7545fc189393ceb191ba1071a3c02f190472cfd9dfc01a78cce5a01d543dcd70c	1663534826000000	1664139626000000	1727211626000000	1821819626000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
12	\\x16b4420a7f8a001e577ba8a0860a9008417c9c92694408e55b36f1b3de399e1266c60fd178f7233ee9a8918d2e449dce14e9b27a25ad835e734ae151a10b0db6	1	0	\\x000000010000000000800003c290011762d686bf577b85bbdaf477f32afa39def92d1df0dda5bd4fc242ea421d562302acf43552fc0d4665d37f7ca02d45453e63bb1519fa5e1cfd7470e07d17f0d610763d2beb3a2eb96df8b4978abe14233c1b6a76e6b389e3b8083b5f1b4e78ad783f3c77fbdf2bdfde4eef8762feb1e83df0c7aebdd2206adbf4be639f010001	\\x243caef683849b1438340d454eba07aae840091881808e47ddda5e5d33cfbb1882c232208cfc3a95de6984b7038beddeaf9a34bcb0b558245916fa6e125c110b	1690132826000000	1690737626000000	1753809626000000	1848417626000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
13	\\x16c4a67d8c469cb9251fa9928c8f5237cec8e477122a241d4c7ef6da750e84a9ae7fd6b6daaeb65f934fc082b85d3dc71c0c9eaf212ba16c163d6345b9f6268d	1	0	\\x000000010000000000800003b46fd407f933cc10fb4e7a0fcf2a1c784521a64656743ef2ee12e6583621ab65e796c8042edef4993b7386efd1ccd1c6b0223e7a45fe32fae927bddd0b0455dcaaf5d5a2af486302211f3ab05e87de082faaf707ce5c15fea1a4f9f10bd6b154fd5e18cdc14b8b9cdaf09e38033e928efca76c235d03e8ebe776e6f80c63c60b010001	\\x77f1a4003ab89ad659793733a867650d1d6c8d2639543b36ec0360cba6ad338f8527e0411bfffeaba09106d0f978f0ca64b1f824d585000a1d4e7e7d2d7d360b	1678042826000000	1678647626000000	1741719626000000	1836327626000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
14	\\x1690e672733bbcaff72373237a93085f23ecbec864cee6113e3076c4064a517c28df63507efac56820e020d9ecae72fe409ab7f6be3c5059dbd7fb8282bea533	1	0	\\x000000010000000000800003c30389efeacdc6d67882503aa4ce8d5e2d07d6316a49575449cc2425332be666643584f96023dcb1e1081a1064f040899b5105968e884b0436ac87e281fead282171c5d5a8787d8a23dc0ba38858385b431db5770496be7267860d11ccc2ab37109f0827156fc12c117e3c3092cc2545ceca44d4402d1df3940ce72cbb4f2c1d010001	\\xfc30a6de549e86a73f911a5c501337e1c5c47fe02ad374ada7fb409d11bac40511980282b7792788e8182811fbdd7c85a506a3723dff2feda7daa84118ba980f	1690132826000000	1690737626000000	1753809626000000	1848417626000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
15	\\x18186efbc18cee8e98632ac943e10d07f8fc75573915df1fda613649c40e696adc19a73d3a1de898b537ade6e8252410ddd0f54a02d089fd9bd9bbcd2c121296	1	0	\\x000000010000000000800003d020fb32aacebd67ee4e58b79c72a547873b32d5a2a3ae00ae5c59804059ed88702c37d7827e1330fa02643e86554a1ef32334f62bbc78bead281dbefd4965ac4102a9dbee2ac0461330d2d871beab3a73608df031c4b4d133cb4047fe9beaa5dde06f4c78728e99e0a6631e41c7a9c1e59cacea6fb2fecf085a3a4df551d75f010001	\\xdcbd84a640f98ad406ffa8f2e9bf7e5e8b7ea43eade6a55d724874e6595e71c93959b92af972e77d79dbcbf30092df003e1a15304164633c4ce977571c01fe07	1677438326000000	1678043126000000	1741115126000000	1835723126000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
16	\\x21a45c72864896618b42cce6a70cbbcf73feb0f113ff5b57868c2729d9240708011d1d8444ea957c6417281006ec1fc28ad96dfd192d4df3d53f4a6cc1f4826f	1	0	\\x000000010000000000800003f1153f14f14a6be6cfb4d23df90db1299d15e9a671a2e16007bdd183ed70aa0471a9639aaa5bc87f3a7db87a559ab4465686a681306a70f0df85979aa7b1ea484fffda5260ddf748308157ef9a9da4f9f1d2f987c8f011ba56c4c42fe1f3a26821b185cbf15624ad2e22d236b93929121c0e0a91f113c5fa2eb989f07a96bc23010001	\\x5d7223bda0d27352702f16219c48706a39fb90e809828072d2ec4202ff68e5048720dc4b4e8b50bd5f763a0fd8e6d6e429d133c5e20d8a81c86788e3ea42c004	1673811326000000	1674416126000000	1737488126000000	1832096126000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
17	\\x2584e59c6ec4769a1f0c591140c8f7cbf3278911c669ef8be08f0a8ddb654c3ed0614758636e12f71244581fc0bafecef91496eb8adb0ff9d6ff50d9e05ac8ef	1	0	\\x0000000100000000008000039f9f2399f87e79323089b7a2ec94c1439ce078a1b2c77f0dede0578c089641d49fd7246a599d4ef2cd2ad6c1404ea7dbd48807d910a57603d5bddad70d899ff632eb84c45fe8c3d540e4346860a447376c3e9c2a5ec5f264cad4ac928a38c1e42c0e53118d70f9aaa00bd62997d52c0821855de123e62ec288cc71621ad61029010001	\\x6d5c8bb2bbdadde85f1ad4994981006a3c92ead4239a5123b759bbbfbad1c49e43efed89974cf09f5cf8414502e3b9155008457a49a1a9a55c0a417e02631905	1668370826000000	1668975626000000	1732047626000000	1826655626000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
18	\\x2778edd3f3992db44331dc2c5825def67899d726b6a652abb69a6dcbdb42dc43827f47f6ce9cefa57667324faf2155c4f425946af69483a137230e1565683fd3	1	0	\\x000000010000000000800003d8ed1c54b7b3920b57bcccf8d829c3f981268bf68ae63803f2a1b392eeb24925255978433e6b4a309899401eb25126c78c202da0c8ea514a522230051de5540e8c81206f6d0c36a6b0b33caabadc66890a6e3df12abb0659712609162a6421c7894c395ad9401c0a47bef95803ba4649a7cb506ea1e9c3a72d44dbb0cbccc6f9010001	\\x63a6280882f1c9ca7a12dda82be64da5c63a4bbe809acded178218fd42223ff08d44c84841cb0d8fb3c24d52f790e570534506b59db5f95de0912fb5dcccdc06	1661721326000000	1662326126000000	1725398126000000	1820006126000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
19	\\x28c0724a886ba11cf26a55e48bcf40fcde1e22a6cca51d67cf9f89962841d7814df2d9fc4dbcd249013a6fac7a0c1e7aa9a063abc6abd8eede38d369d1940e81	1	0	\\x000000010000000000800003cb217fe7e3b0bb62aebb72d665c616145c0db878ba5e9d030e9b9169e847eadc41055905797a6814b6fa6768ce95160312e108c2a53bd4cfe0cd6fce00d110fd24ac63b9edf2387307be668e4d73816143a08ffc2938298dfb938deb45092058667b134eb7f90b3da6d6ab343a85a273ddec435a7e9fad053ecc26881856cf53010001	\\x1c61d189b420e8ff330cadac2d647221a958aa7f29e2874b10ad82120e78b7dbae72df017df383dbf00dd07b864ec73717b269d04b31583f0651519a2e420205	1670184326000000	1670789126000000	1733861126000000	1828469126000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
20	\\x2a4c923a61f3e1f08d834ddc0652b965450925cd5e53830abfaaf2f405e4e20aea00b238d53fa516c6337167822437ff3b7e01d09ee125e695d635eefda5fc7c	1	0	\\x000000010000000000800003b720bc6bf6590559097b218408b066745c63d5db27b4892e6a85dd674d5748ce84abc7e8f67494d6bd3bbbe565fe9f577f6866036f0230815c43cc5393e7001ee370e7ead7ad2498cef1ef411df6609d77ff0d181c3933a1570ce8bb143524049f19a5b64db6ee62a80759d700cfc8848448a634fdd7688dc38a734d300edc85010001	\\xff0d8b9609207729b3efb8e5b7c89ad7d84c0902cc0993e850e0159b7bcbd0cb41a377f67a92849c3ff0604a90a4fbde151e33751deb7eeb613f26b66d4ed00d	1682878826000000	1683483626000000	1746555626000000	1841163626000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
21	\\x356c9a1c4dfc441fb420a1b9e00d399d520fd6467b3a47ada2ecdb1a466551d876f982c8239dbbc4a7b28a8affa558a74e19f8cbb092f0b090d587aba3633e90	1	0	\\x000000010000000000800003bbe5084528b4a3bbb2902ed69ec0333bb79a513fd9f585aed665dbc63e93798bf47a3b33949e5242e90a0effeb9a020b13f2c0a6677f74422170cf1b9c5e3dfd41b0d3f1b007cbdc3d06ca74e5a88a3f6337a849ae83a9e7ea5308de6e0c73d508ecb230199eef2a9dacc44f7bbdd9da3712f5a6438eef99c79540a7e9acf9e7010001	\\x2ed338c877a72e6491264d549a4ff36ef25227b0195157a64f5ea453bd9eec15d71cde722e0f289242af82714053faeb0aba0a27e60c436632b937f348d8f906	1664743826000000	1665348626000000	1728420626000000	1823028626000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
22	\\x36103b0c258f4066a1f383a66b90a28084364399a79757f7554cfe4cd0f2964f4c91a9008a5d754aa59c89ec3b0fa62f4ade31becc8794b6eb9625b5ada5e606	1	0	\\x000000010000000000800003b7b745f8adea8380da69e0c0bc78e7a287aacb4708375571610e42f68cf1830407fe1e7aa2b67c0531f295b7d22742f71a70249cdce233b9c3fbeb40b9f2abe867cf5cf64e614284d8d323e4c9295a2906179de24b0b4c2d563cb3d203db7ab9e8ab6b11b68ac9fb1bfdb12065d95dbab0f4609681926427b175c43eb79012c7010001	\\x0731b51febf6f5fc18d154f9b5e86297842cbf601c3e5ad69fff08e370601fc0ae887db7df9ad6126342a404b5409b5e34e2d6650084ba6e1fea3bda950a9804	1685296826000000	1685901626000000	1748973626000000	1843581626000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
23	\\x406033f75d6dbaeb3c31d67bdb605416566a11ee61bb9a91fb08840db88014e27a70554a6fabd3c98f3887be5129e19bfdb7cef5c7b859676019e3d4c5d69973	1	0	\\x000000010000000000800003dd87db3895a121d2fe1c5b21e3802b72ded851d847f6317d669dead18e799c2ff93d77e74a1d89fb8145ad98f8ec4242f811e17ccb62557da82a870d5ce424b786a66bb5d93a06be4f4229beaec43195b9996e53ac45eb310179124f485fbb1e1465c0335cb05235a6cc1c05d35a0dafff61ae712fde0c4e4cfb4d2b2df31ec9010001	\\x699722a027dfa253c430994198f3ada86ab7878a80e897eb1e637cf2e3fc737c6ed686c8b7d2224ce2f0272df7b42d8705d2d7acf21f1eb82751cd634dd1c40d	1660512326000000	1661117126000000	1724189126000000	1818797126000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
24	\\x42cc58079d3171948f83149d4e0fa31efdf0725bbd9d089c57556f656abe03e463f417a8cb2f345528d9678dfec161e40e8f642856bc3c52b41b4197ad07934b	1	0	\\x000000010000000000800003bfd05cf285ca672d8ce302560f9bf37fa715c32ff298c27b3106bec6474ba01c7c4e584932f286139e16efdd1e69244cb7816908dd42838ddd255137f14156230ee496da5349f34576b2b54d6f491e3d0e1b5ff162dc89f0ce268a78caa57c954d13272dad42527f384ff5bd4b40d18834927815606a75b87d3a047b6e4ff31f010001	\\x23f3cce8a997aad7357e4d3d429871d1e845feb1b4b19d55170f1e35a8af394180461b5f239afb6cffce49301eaa1fd8930b724d129e5c9fe0a672f709b07506	1665952826000000	1666557626000000	1729629626000000	1824237626000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
25	\\x42885bceb752f169aaeb016be1e452b29758f3bebe5c6bdd2df72204dce1d26315b25a88a9e8f25f3bb86c2d9347b79afc997c7cd525b41c20f6695069e4000c	1	0	\\x000000010000000000800003a620ad71dc1539e5fe08379a2aad8a503e9befef7df0ae7a41f99b3d73f7223708bcf2170a6055ba74d782f197afece883871ddbf7dfadb1e1c412b6abff8011a939f1a25d14a61f133d5f977b2ba6253d3784570439d8ec65e04dd7d039fdf57d227a83370a00cfddf43cb12c2eb16f4a4e49fc8b7fff1b54a68a9e402f8911010001	\\x5a5eae9b30d891ff65b3b9ecb4c46eb3bf4f31b83dc541005c4458f4cc545a54953a964b455111cc39dfa092670e9ab77719cb71f4e80f59ce89fa50abdd180e	1685901326000000	1686506126000000	1749578126000000	1844186126000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
26	\\x424c6de570101a8fb035bde688d9d5aa5fff3d6c56038721b74d0e8928021fdd73d53d04aa49a86a3393c59de3b3c7d93b3cf54de5e1aaefe9659df0c8780a36	1	0	\\x000000010000000000800003a1643f6722c5ab423bc3018ee1e96c0798e767b0be328f6f09fc43a0e464a746e598612df0c74dfc5404ef7873b7df205aa1de772e13ea0b78af9bda8c1971e4b36fddb39617b7a90b5ae107f3084bc04721c1c1425e83ea7cc7a8fbe376e958297361bf9e77e25638d6a1a71b58c7e3a161d83a629174c4023875db48a1a1eb010001	\\x2ee85d9bbeadf950c61192b7210f764d30e7f1382161e8b444049512d9fe36a639280bce41621c736dda6ba3c725a9195d46baed00584c414e69ab494d17d40a	1680460826000000	1681065626000000	1744137626000000	1838745626000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
27	\\x44083e375cc3057d9d1319f5abdd866b2dde49c0666b89d2a5503cd58c1ff2cac93acd9399797a610a959c5c586658d1bfe77260a93d45e5275678eda08dd0d4	1	0	\\x000000010000000000800003e8c2548b2bf22be6bee43e7a4ff6693cee1589be5761863c70278710cedc114c89f9750cd42c02125ec773b30921211c2ec08afbff6b7756f367de31117788560d6f242e140918b8d0aa32ca2ec114c5b82d457ee7bae105f05e1ae2f488571aa832ba83ad27d893b54fd7b39dac20ebf2428376e91f7d9576c257015917f35d010001	\\xd6af3cc6cef0a966ecdb4a3a2acb51afcb3a955469e6c92ba67b2390b0ba6bd42e7c04cf5b4a574ac1191e8a6f9427860dabc01adfbe61495156c964c96eac06	1675020326000000	1675625126000000	1738697126000000	1833305126000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
28	\\x4640532263588c431649a49bff637d7be118649b535786ddd870424a2b3dd4ea1fbc9d8701d5cbfc3f6967bf2d592b1435f28e2b2838907c30cb5c34f3e34a6b	1	0	\\x000000010000000000800003fa25dc95bdb11317d5b45267f8d4d0ba680589792d80fe8e1247146aad4a3ce880283683106b5939fed3d4a9045f6a763e2e05d0c87b9b6ef4cb541095dffa4a70ba41dd51691f7394a6a5fbfb21409d734bef24dd76a1b936dbc003e45a3402f0027d3b45d0074ff1d55a35739f3f43ed97876cb5f06750c8e93aeffa1d2fd3010001	\\xa3598db61528dbb2828f66e2192b685fea74ac70eac9300dbe919ee0c2e3724aa47e359361e706603cb6f6b746ac0c2ac8d95c8a233ca915a46c63cf30551a0b	1678647326000000	1679252126000000	1742324126000000	1836932126000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
29	\\x490c3dc5e484b30d5a18ce38ab27d679eaa1441b32db3be44d398b8f69870cf7d73a95d951cfe2113d995d8e6cc3f7ad1d65654ffc5cff9ccc863e490febdf72	1	0	\\x000000010000000000800003d006abd398de01a9ec6b5a1c21202aff63748b9a74f422fd87f55c930ca739c31984823912f8b4c2473ce74817ee9ab1c821943857d653dcf061439cb8322fa822d55b56e099487ad7c21fcdb212ba69b466d9570367f0a17b55ac4ae69f952862e9dfa3ee88ec0570e6c3f6318aa19618a63c8335c31c89bb9a7dd325f1184d010001	\\x62483d0cd945842d65d33a172d2c41f01119dd673ffdd0a22019511fd5e84dd0ccad9b124473c22b4f5cd75ebc9c89d379ce091d875168eb66316481bddeb201	1691946326000000	1692551126000000	1755623126000000	1850231126000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
30	\\x4a44dc6e0e7892f5671e76e17b45d93f5f5b8615739b47fefd2d0c243308989c0fc0ee50f6afcb8cb53dd85af210b4dba2095b339eac4c5a781932850b409bea	1	0	\\x000000010000000000800003e1be86d1dd27041f5889ff7fa6bb84ad3ffc4c1c5bb2d550ca58fa7dd45c47f70d7f9d626afb3fe266b3d1919f71bdbe1ed3764bb85c3d013e28564b5a5907f7858dbbab16ff5e071c0a54c0b622a94eba4fdefe4874969c840e80904675bb26ebca45e36fdbff82b82327534be273b83a89bd559d5bfdcbd7ec1f51e174777d010001	\\x52e2f3b3bd502233165a38df5f09f53445fdf939e2fd808ae83678828d07811226e6de88256fb6f3908c1c5cb7f72d072300c55ace98ff2c49ff82e7a1e24c0a	1664743826000000	1665348626000000	1728420626000000	1823028626000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
31	\\x4c90f55e366a3b49143610546ec9880c72441c655e8f6a415f287404e749b1800eeb13d8f27e5a2980c9e888be4346257e91c33924236c6a17d380527d9ed65e	1	0	\\x000000010000000000800003cd2301b57b58a11bc7e0a0c1124ccf0828863cefbaa7b31a011ae8b66495ef7ec1b66178aed180fa1c8e072dd92292837af896c39183946c1e99be0d23a8a187367e8876d3df489469f77c7a8350ffb75e815c57b84f8db7838e6cb7865e87e6ff3aedbc32c957a2956fecc62793f022c5117248ea9de13ec6e6999412e164c5010001	\\x9c6bbdda30608f529fcd81acdc8157d240e5de9397f1353f7c71310dfdaad887e8c33fbcb1fe6922c5b40a4bd3aa20b76d30942fbdcd49cfbb784c9e9ceb590b	1685901326000000	1686506126000000	1749578126000000	1844186126000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
32	\\x4c10bc87deca45f6e021be7e4cef05407e1c0eb6adb1f64ded457d5d7a68c88949278bac553d039b4f56b591ffa133e3e26747d079a16d9ad56fab3fd03c8bf0	1	0	\\x000000010000000000800003ac1f6bfafe112d61ecbd1e9f186bdf33e9979df25a432f013c5bb32ef28bbf3ae3a3db7a7f6f6a9f0792eb4089a7e3ab19c6198a4d431c4c45314db98d57ea7d23416fbef7199b64a3bad58612e310989b79d3317af06c6e8defa693db2faaeedc1fa5378ecffce4dc398d45b83b93663cd47c072b9486b475d9c8239978b147010001	\\x7195c50b03ca174a0a1c1987b702651e9f8bd4373f85a2ccc27e6e7a035d1e11e510e6791fa1c80371afa6ada14c715c9c0851df0f0cebc97b187ca120f45f03	1668975326000000	1669580126000000	1732652126000000	1827260126000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
33	\\x4d3c8c5a15c0d5ad3e99a1ad7d41cc3b8425fd1c002d77a52326ac777adcab8244a3144418ce09a943c40285351aca4685990caebf8333668a9bd049525c6653	1	0	\\x000000010000000000800003c1780c2cdcf610eff9e9e1f489860d9bc41e7d2a4be5f82b26d98344ab18abe4fabc8c6b73b3536fe2e7329a557bd0635b5ebc69bf6db8c166f475528f39ed02746f7f3c92557ac75ce4cf4172e351f98fb905029dbe4e5a0bc8c6d138ebdbc874946a61bc87894753060678e4bb0bce92b75a5479ea32c2835a41e3e55e9e11010001	\\xa7457a1f2ad3ce24237518f1d2647c629701ccc7583de22f945042453ef64b2d444eaafbc3aaf07b9eef6a3b5f53a7d2f480ff1eb1cf4a291929332b8d04050b	1661116826000000	1661721626000000	1724793626000000	1819401626000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
34	\\x4d08ab5367721657d1267a4a066b4f78c2bfc2aace4d1ffc029845d5c281e0cb293d23623be3dec2d7583ebac9a9b53c0d990b213e7ef8b20f55b6367f6584be	1	0	\\x000000010000000000800003d2acb7afd80bc526361bf78b30fc5658e4f161cc3faa22467c115c4486565acb81cec18fe74a2aa6ed399fe295275c6fbbb19127b848d2dc8e0f8a40eef3223f7ac43b48934ab6745aca9d3209feb2d025423d0082cc58a2f8d5395e64ade3f047f2706de23549d5ead53b89caf328f048368c1e0488817d679c880fc09ff9bb010001	\\xef319f48b7c82d1a1c62bf5cf7aaeadc72f6bb99849c1030ac7e8330c773dddc5dbdb3580057e5e5288ff09a6d393a1be15d7df977d0ce53d045b464e019e90e	1675020326000000	1675625126000000	1738697126000000	1833305126000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
35	\\x4e586b0ce93c48c7b376795d91aaf0b1f476d0a9ec8680ef2ddc6901f1cb78f7ecc4ec4f9e5b1c3a8c0821e89927c8c41e40cc059afdff0c0f39c08a2960eaab	1	0	\\x000000010000000000800003bc25859f2bc12500b86bc4248a028439e5b2bb31ee13161f3bd44cf344f7d3369bcd0baeb388b6d55db1b569dd6472c54019444f117458a6655847d5352c4e2b624ed1260118d446cba545ac58308e660cb94f43b75931ed7e551ec005ab6469534a090a3dd0876c0e01493c375807f62acbd68cc68b62aa95f000a891fbdc89010001	\\x085e3f1f0e2ccfc15829cbc239324acb9c9a122b9ac7a485a616eb0519906c290a81e2fa03c4ce39825ba05b4529d1bd5f06b9601d36947708a2f3dab6107101	1671997826000000	1672602626000000	1735674626000000	1830282626000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
36	\\x5320e55a8ea65c2452e6e07d24ebe9618ff14a22337bdf365b972d2484f06585c1dd260a0f642b6f270c5824add767433c29302cf0345f27ccb6647559af5b53	1	0	\\x000000010000000000800003aa912c10f66551ee7c8be1adb0834c9baa22923aeddb957e538dfd5d624c596d9baa0b4ac057010445fc2a33e5b1c69da69538fd3892369eacb28f5a29e514b28889bc075f5267b734f9c50237bd0049323f650a085922e3b6a2bd782ff5295578892a7ed92bb415815367650594768adc391998f3ea94e1f8d10a11a254f9e9010001	\\xeb1a92633b8df0f5146a1ca7c23519182e863c5b6cd1fd85d9d050e7998fe46e628b6c9fa83adaac623914ce30bde57f67f5337826660c2779e284824abd050a	1681669826000000	1682274626000000	1745346626000000	1839954626000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
37	\\x55d893be6bac83583bcbf38d6dcd7e08a208ded876a1a2236a1da49b11d5b3241b77050fed507234001fd20537276de84a566e397c31a2d553360180681ef789	1	0	\\x000000010000000000800003b9f0ceb49670b157b137479195e3e08d7476b8723f5c9e4239142832d136e41a4da7f961d9aac738df9e198123cef8c37ddaf72c7490a48a7ffed479dcf2e7aeb3f8af39daef21fc1431a346ac798c5e2d959714172711851e741250ff1097b8c8b9384479c57bd143868414d1f119bcacfcc805af989aadf2b7005af29191eb010001	\\x378f4cf7ddf3b02f06dff79e6c9d0552097ee3bc06393551de923c4c0ec2fd444948e791b28947beeb04000a2a1b8821581202eb6999fb9a1d08652a846a9f02	1687714826000000	1688319626000000	1751391626000000	1845999626000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
38	\\x5abca37750c25245442c8999a95b561a2c5509de4d633c3a8d06d465e616183c97154463b0c45931b6af7516ea4d946aa3d80972b1211b8fb005f14d1dd2acda	1	0	\\x000000010000000000800003ba6faee5d19391dcd831824d39d6fab826258e0755e2fad4df8c9f50decbb14cf805d83cf0401616bdbe022e038bf0455f79af61db44b6b266e43dbd7ad6e1024704d670767472e24e0c274b66f88e01f92398d9e1de514136ec7a06b34de8030117950b831526dc29aaac35555cbdfd61d309ab3977786c1204b855c916a8d3010001	\\xce626bb5fb35e45c8072b0d4088425c7dc6e3b3883ca1880cd11ef6b1d16fb78f0110abf6cd522e219d3b7f73a2551b355c8ee481caafb2060753ae279f16006	1684087826000000	1684692626000000	1747764626000000	1842372626000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
39	\\x5b408609c1e3671d1dcddd3be7793f2ec0a201a9511478a4d36aaf3edab96d65892a346f1d5cea733b45237e6fff72b3818bb1bb986e82d8b1e9da6f9b2264b4	1	0	\\x000000010000000000800003aec0de29cacef8cfe48886097b4e1970544d36d1d138410fef2ed15ad9157a150996b4e079d09ceba84ec9daaf3b9999759f5c67cae8f613deb63eecbb2b528a5acf4840ee9cea9f5a9bdf3c8fd71e18d9e5893c2c09e16369c74643d53d41d7bc4cef2f4cc1fd422f7a2cf1a774d56b14709714dbc3ee6691d2869d6173d54f010001	\\xff21b42cf3fcff7f0d6da67d85ca319f6e88913e6d8d43d63680a937276e3939fab326cada865d24e4316615333c322777aadb67921cab87fea909e7df689e05	1687714826000000	1688319626000000	1751391626000000	1845999626000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
40	\\x5ce840aab6ed6e569095a74899612f44235c507d5f25274860fe71900cb3f3bfc9798f2f0cc8cce1b33bfa6a2b5d0369361c77261c9b76986db3e1475c27baa8	1	0	\\x000000010000000000800003b9a5f23afd069d0ebf891f5474a25634e608fce363b62fb1d43d92f07064dd368d1fb0013f37a60f6900363c32a291cd238cff86fe43c0d528326180149c992cc348e0363eeed234fd5fcefa55d4dfe516a5ef2e0ceb9b8c3431728b7281235837de0664e3e04a6527843e55f67a8fcda47b7d376b2add742f22286568262b85010001	\\x3ca0c92ef74e567c6c9e836266d4e36f8a684d778d1f7ad220d45a814c867d14111ed8f4cb428d6fd32001b35c09b1680b8dc8694bcdd60e5113847a40d03a09	1676229326000000	1676834126000000	1739906126000000	1834514126000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
41	\\x5d00d8dac52ba00fc32c561789c83776a6eabfcfd78e0392542148b582dccd1229b2b2211c1649dee7a2339cd960e99d510b5c9a44b5611d9e37926f3843950d	1	0	\\x000000010000000000800003a8ccab6bafd8334b34320ad43e990cc4169dc1b70877e9e03214550ed27cc106f0b54d6ba941dceceb07c76c34102b056010f01a33b41876d35956a0cb731e60e5c27feb19ed1decd9cc0654d853f38be2634d2363e584eeff06586d74136b126eb4b23b0b113df1c1d76c14f2d4237cc4ea8ed6d438282d7b63fa46e21f5121010001	\\x9033d7c8245a1920f7ea4bd5c375f06f6219336fa1ad84214a20c65c6336ef28e55f6123f2e201ba8383481145ed97c5223f55d331c66375cd5a5cc11adbfd0f	1681669826000000	1682274626000000	1745346626000000	1839954626000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
42	\\x5fd06dc40cdf6dedfdf9f64b4d97b747d4974dd2713895c941bde020e193bba0d5af27d54e229bc41237e1e0017842e7c580ccc0f26e0691f6514dce469c46b9	1	0	\\x000000010000000000800003c9b8a5d6c6d7f273a6d6e2f73a7effc72c610a06e7f2f454131f44f876a23d6976ef1350537dab982b5dafe55f08c6090949637a195f17e8fad1aa5dfdcabdf75221e39fa10e4d12b794190a8823a598bb0b015105963f41c05f7ffa9137a3cf448ff316431627cad08e405d10a52d8578043b77b11a311314dfafb803a57f43010001	\\x8077ed4c92f4f806277f7f76df9a2a30e9795e9796f7159d03630e1f26502b93ac0b07aaaff69a229d1e24f9d75df97581ae7a9bced1fc127be21dd9a816280b	1689528326000000	1690133126000000	1753205126000000	1847813126000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
43	\\x60706489733424ea4d5bc1472fa30e3e403d07252fcf7616715263cac6d1c8f538cce0852bdb85e7ada81bab2150c06dd51fc95be240f9f429ae022200d1a4ca	1	0	\\x000000010000000000800003b86efb1e4c8c1b1979f390438480bbf1a550ab77f21eb55049d18bb314bebefdc161da51d38c1f2877b74fb8ed8503eb7c59133f16a0dc4d517d07c417b21ad94c7d516b7920c4a5e321a4375bceb86c35c80ac1df59696c96c695a5810c3b65a04118270c6cf527fc3e87fd04e29d2c573501e2bea469c529511c8d945a9df1010001	\\xbd65397baed406bad8e851564e5de5d67c3998267e26c45e250eddcaf7aad597e398e05abd91de935329ceba253a320bca32ba6c3b2cb7596aaf98886ff39000	1676229326000000	1676834126000000	1739906126000000	1834514126000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
44	\\x616c4e34cdc13a323b450d7376dd313939a85f0bdeed205d63762c1d82c8c58deaf6adbfe940f9a1fcfc4f6b00c758140783cf1308ec85c795726d0490b0574b	1	0	\\x000000010000000000800003a6f7eec5cfc6802d1ba84aa774d2dfeaf68f234c3a630b197d2d4478b4fc8caa48e34d1183063c87dc8ba3d498b98af2e9cfb91114632074704e2ae3b397e77a4aa416b02aa880d6fa4eeb7b5cdbb277839a7630400cb632701d57a552d95ae0c992e7cba29ddc977f6b19cb67365ec16375fdcec387c6220f040ae0159c7591010001	\\x87d33b7c680ba79b331122c630254d4c5a0c8842dd5cacfaa8f3c052122fc0ad3a60aca11361d0db3b2cf52cc3c1bb67ebfc6a7898555dd0255c58b8c16b6c04	1667161826000000	1667766626000000	1730838626000000	1825446626000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
45	\\x6adcfe7de3ded4a1d255140815e71167fe5121de33c5c5297b9ea1ef9f980a6c6743ba65dd98aa49ab7a423d72bfb7031e4cc48754e474ed95ff22aed0a4934c	1	0	\\x000000010000000000800003c79be31a7f608e651acf23dd5829d23e8a2add28fff69508d3a2b71eb77226f1d56efd92e39ff5e7234eaba9d40a7c421acd5cd3db48b2973f11d682cd196d8d4e2334869ee72bc6c4c191e31a079e6dd4acd3ba2a80ce12354567dc60f4d0cf1badc80af6ef3efb0cbd8b5813b344d98987ca3ed3b8e2f18bdf241ed32dca1d010001	\\xc83206f697cd57416f8c521b593bba5e76394c11cf02ee08d61fd6b60dcfce859ded6bb92c8385a22e007e0d36a67e1ba8b49acf414354365660f5c895d1ad0c	1691946326000000	1692551126000000	1755623126000000	1850231126000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
46	\\x6b044634ab6263c3357aafdd0f9a3fa941493c3929e36785f6d57140a2ea27ae5350aff5bcc52075920d1db3357bdf49047da69cadce50a9861d93d5aea8e06c	1	0	\\x000000010000000000800003c36e811dcaccbad83fea53354f23b1f5f1c3782e2a482383781ecf5b400b746dc815515faef2f83fdb336a7cbb3b9063537783784b0b4747252f2341ede874a3e7701b4add2732ad7cd9899a50bc7f5342aecce9c19fc980c28445f7dbdebd77936f0507ce84408cbb8ce42217cc90e9bacc1f5b7d98cb32ea8dc618d4c692ed010001	\\x0bb7dcd0cb8e86b095702e9892ae27577182e4808fbd9cf3d969ce64656dab45bef9d47c02415e7cd5d2815e61e60236e13a539316143990b494428f5cf08302	1688319326000000	1688924126000000	1751996126000000	1846604126000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
47	\\x6cac517eab0ef4e938b584bc34b135e09156888fb3fce96da509c69b15efab037d0d1cc286b57d921f51e3bf073644fff38c12b950866f9f6ce00883c2e87b70	1	0	\\x0000000100000000008000039d6994b54d46b7c063611e9ee40fe9ac153fd0c25c82cc8ab665ac2a4bb0bea04b520f0ecc5d81bfa20ff776d83ce4182920d9a1086b64ca771768a2ff24327078c711bb97eb0f2142077f36291828af6c6da0ddaa3f5b033883ca9788189bbf7770964be4d0fa0c45f86fa12ca653e58d44ec4233f499bf432018fcfdb92f89010001	\\x6c4fef0d204dabae9102facc0c15068a7b166a8534ab022e73ad6bd76a166f263d20e05b554b2722827231629b168ead44597ff92c6876bc6dff59256e85b909	1671393326000000	1671998126000000	1735070126000000	1829678126000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
48	\\x72b8399273e8746c8c231236792918299ca53efeeb5d0be9df4f2aa777bbeb9f1f59cfa98fceba61211158493a9d7ef55bcf9d9db97f77911f6544b5b33b9f36	1	0	\\x000000010000000000800003b90e21c96f71053d2308a9db5de691db3f59d4a31d25053f23e599c869831267257c6896e404ea15baeaae1a5015b9b1053b3f299161252d80c93d8998611065e0d5826ef7823342f26dfa3f74a379751cf9e96fd8118fa887a903b8337cf61776e1d8ec48d88e740b8a02b72c4c16b6e4d204722b8a61d1aba0264da0e6bf6f010001	\\x95ff4ca9350b5fd323ff305ac9a1b41c1903215bdb6a3c41a346c714c3c0139c9195d4d9c2581c0dbec69ef9e171dce8dd8a72262e375e8c57221c3493e08b0e	1671997826000000	1672602626000000	1735674626000000	1830282626000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
49	\\x7338266a25ed2e21b39fb848bdcff3409d3bef9a632c77161806b15ce376e6a1f3bd2b60b82b456dd80d57eed138034d7ea80d5942870109cccc8b99f76a1472	1	0	\\x000000010000000000800003b90a8982938db2b4835430714564451634604dbb3a9225eb9b0a7bdaabc026cfb9646e985e854793cb81b4b4f9320bd724864f7a717734c226e5f9bab9469d0d7a2c0247d60bfc53d498090b587c213b1c42576364fcbf390324ec56facab661902f896c21c53ba66694639467403b2354cea010a4a9d05c9fd5eced62050ac1010001	\\x060ffd9a3c530225f245846c0f1b9116101c1e2e84cebb5dd2d2b73120f3b964e24386bfe4ed7d5754f749a421d80820d7e36a214bd1c87e5e682057fe3e9709	1682878826000000	1683483626000000	1746555626000000	1841163626000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
50	\\x76d0e2fc2fdb8f1118ed588cad1b64391d7a0008d21532d97af3b1b636da68fd3476474eedbcc87c90d8a727849a947fdd57f5a8d5f17b4520b7121c74f533d9	1	0	\\x000000010000000000800003e473187ba2cfcbba7567ce2e49a8c39e4ec051c3b9d7244a8d860d9aa8e315cf4d6162385c7c9fef5ef950fccad484adc65a285c117e58300a9ddb85f700c094dc6d66efe0ab01f4954288a036a7f80590e3a06b808fa08fdf3efde02858cb5853fb691db1da76e13f600a7a2179b94e387e6ae0c70427f6871a3071d254b837010001	\\x365d9b6980da71eaf33498d6a16d9a665533ffb407ebd2cb26a1630c975b72b6a47703ac688384556aeab33aba3ab5d08ddb6c2df024c1fbebacd8b59c114d05	1661116826000000	1661721626000000	1724793626000000	1819401626000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
51	\\x77b0c71c4a4b7d417b854111adf861a56aff5f5ad178b795c82ba7b3afa90212a6eeefeb2282c727e2d5bd7f43392ed1cd3fef6d8f48d1b879f5e2b9c79ad281	1	0	\\x000000010000000000800003cce0b59a07493b4cb76f72d7284ec391804696e8d83fc4acc7db3ac2fa5e124049cbff21f4684845cb6bc7c55d423406b168edaf850a7c049067c3090b3e033142c64ca022bac14a63232deb8ad53dd4f0abff73ed75d5a2d9829086f27b7a261503fd75d2929cd380ca3a258e61e33766c4b16aed0683a3e357bfda996bc091010001	\\xf042a4de89cd16fa8452906d6f5a5d6a4ab99db66ce37da0ce519f68f030ca5778084a78ef3047deb8c7708107b831f682f4e852f58e35d5d69a2632c6d87504	1683483326000000	1684088126000000	1747160126000000	1841768126000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
52	\\x774c43b5afbc64b7236d38204bc8b5d6c2feac001a789350084090e1dd9df8acc8bffa08791a581a6a45311567310f3e9189e4a84ea6b8b71d89153839242118	1	0	\\x000000010000000000800003b2e6298ab8034e4fa5291c68ec756daddf00adc846d4c7a68311fa211e906004c31f755c5532cd7533d3548f7a135de6b69891c24818e0f143d0c212373205983b9f0a7b3e0e188bdeb5fc4d6a207f641ca6484194301b220f10a36ef43205438397d37f83876907595320d0f52a4817dae27a67665eebbb45ebcffbc5f7fd31010001	\\x1bef9bb275e9ab10828ea74be2ded79cf07966c2f652685c80c15b2424e7a08b14f49107545d6b59f587014a4eb653538a6aef12cc3da109f0a3ebae8ed8c80f	1662325826000000	1662930626000000	1726002626000000	1820610626000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
53	\\x7a40c1224d52321389df6e3682b1d75f67c44aafe6ea3e05a5afdf0a8549bf1bab3d3da42aee757498655ce8654a47c591bed0048e11613e891b30efa7d8f525	1	0	\\x000000010000000000800003d4a1851239a54288b6c5864801f19eaaacb876f16ef48da03d9d6614dc2403042b6a1230d46c2b2fba9789d8c7c570ee942875ffb72deed4076662c5c0375581267ff5bd5314d4db0e3df498469754ec13e8a822043f3eee369ef7f11d9ffed2aacecd898811edae5f1e2732fb5d5d0bece458a1da2792c04072056ebc53532b010001	\\x52b1d65f460c2ae4e9812a131a5774baf36b3afbb1cbb200f88e40bfdd4738605a491290cd3bbd5cc42052ade3db054bdac72e05bafc6c37c6f895f7ee4b3f01	1688923826000000	1689528626000000	1752600626000000	1847208626000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
54	\\x7a004a32b927f68be0d554cd66bfe2ab5347ce5fd2f3e18fa689febdee131876a2c020670bce3677353a406e7b87835eb5419d11c76bad8cd72c1b4007791e8c	1	0	\\x000000010000000000800003d9cca9576856cc06a3aed751d16935b2438b82fbb085695d6f6e2656c33b605319b2960510c04b3f1b691a6d15ccf6e08e30bce07342fa51fa4f9e30c4a0c42b176769dd0ba2b82fce8faf35a7326cf43845edd0a9be8aa5d41097390efc9edc71f20066e744a5808ee17afb003cab0d2776c2cf767fac102b07321c915000b7010001	\\xa54ddf9b634d6a24f2eafba1b5c01f5cff557ef47411dfdb78bbe8853de65519176520af61499b2e85a8c986c23e54a07ba36bafc6549d30505265224f63f60e	1688319326000000	1688924126000000	1751996126000000	1846604126000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
55	\\x7a18c76679a1090a3c8997914ee23eed7a9b490a63c30e7bfd4dbd2a2f826d1f87b5465240f5f7c34c8af3ce49c45d49f9ab4f3ee4a37600d50a26b77dd42378	1	0	\\x000000010000000000800003c9ee927e0b62f01dad68ea05ebe12ed2f37cf1cbdc901c249fa3377802c9b7bd9936ef5fbd5ce6bd695d702e9fa2ef62907e69d6ac3efde087931530cbfdb3188b844be9b979ac71f388504bc1d7dee2fe418bc465f2b0301d2bb5e5242b285e47ad4794205a98831fecbcef82e6252ea9a960964bc5e7689ad3cfec4cb81a77010001	\\x5f4ea17857afa312f9691de3c7544fbbcfeb05358083ca75a3c261f55abe32761c38ecd62f48d715bfdddfc0f053be905192b01d6c3008af0a5eb5bd55be170d	1672602326000000	1673207126000000	1736279126000000	1830887126000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
56	\\x8134a4c51e761ee6bd57cae279b489bf72a18e032bd0435fb71633c97796431137433ccae996db819edc32779a335cc31502716916505ad6ab9fec313f75e01e	1	0	\\x000000010000000000800003e184fec0d40e7d446d8c6f875b5b248afc630424241df952e4bb66b4fc9aaba048512313f7c20433f8217c9fcbe2d7288bf484ff1751c3141110613e30c9bc20f70d2e8efb4e9ef2837c19f7e093f2ac65562f45c84ad80b2aa75b3c3e6423db3ef80f1fed41ccd5778e4a80b1e0c0aabe1c0778bcfbe28eac0e276246e84d7f010001	\\x13d28934ac57fe43ab5a155a60208aa7a1052194a47385641a9370682ed09320958524563f97e05199777b56133328bd7dfd489bb3779a9b667577d4db224709	1670788826000000	1671393626000000	1734465626000000	1829073626000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
57	\\x85f4161648dbb8342c02a46d55a17d1e95ea3029fcad67855172f24da49c25a5cb3b810e0dac871b77c072dcf1512a434cc97555c66315c1f8007dc47243162a	1	0	\\x000000010000000000800003a9e21461eb299cbae3b5978a2b9b6acf513704df615b2b01cdad11532429c3cdb99d2fb51ce03c970d31635299c351527a0f0efd9eaebd337d8c742bec4d8a071709bfc8e0d61c98a5a293e168fcba922400637ee54c9b73027363f119866f6ef61623e97f6780ac519d3fe2a3b43e8e04330d8ed34d25f588df247e7974c75b010001	\\x2ea0d68f42a7d7e2b4105402ce1ba5491eef3c4ef03553417f1dc544a6b2c0aaaf115a1c8069904260bdd6459bdacd50f4151e186314a84ad16fa65d0d8dcf07	1660512326000000	1661117126000000	1724189126000000	1818797126000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
58	\\x87f4c7bb9c522576bc5abb1ba71bcc577a5a15a2b4a5406a99ab33058214a6df1fb90f311fb5a82732f72e2382b9dec1f010fa5e011fc56f5cfa824f647edf25	1	0	\\x000000010000000000800003cb29baece4af1bf4349fabd80694bf33d68b8e9ddc3f209982725460052f06d584fc62ec7d1f6c3363db1e30a535fcdf7d940a54b6e06afaaae77af0f52c8124e839d6e0e753891e41399a54dc343638cc82d5e0c0b89ac089154f2cc491d0dcedf08302a5687036de366bd17ccdb68564afecc96635e1a651ba4e9a05d5c34d010001	\\x68e6cdb907a585b458303719165d934071ec666f249063c14d93e96596bcc7b9ead9ba4a359c9c86ab6edb1992a48f65b84ef229dc6dda9258cf8ee0ff1e1a06	1671997826000000	1672602626000000	1735674626000000	1830282626000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
59	\\x89c073674b47dc5ec274d25859b29f2435b156447f0ba3dacb7b7f1a0efad936d1f26fbd982ed13e3a00d64d440ae3a85fb130f14d63cc25711845ad4e00b490	1	0	\\x0000000100000000008000039c43bd340f0be94b0e7c3810bea7bc5caac08328df809e5d0ce5527f3190129add7826bacdff9ed49e7e84d5ee645dc008c66f66fc9904455830843971cec81678e3f54f341a69674fa85fd49a59be2708fcbea79e990c05b89dd004de32e37dc9a14056d55082096bf0bcbce5b51e29fd6916faf69fe2bbee847a3140ffc88d010001	\\x03cba8c15c4d0510dfe084d28472506c249956a7676d734837b57fb552c9d2ff31703bef6a35132cb83ce7ebe9d9992c885104a1b3554dd045602f502aff7e0e	1681669826000000	1682274626000000	1745346626000000	1839954626000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
60	\\x89dce2662a8a42c65e5999705633f10d95279a3b74972be3626d8af43e262e7f43850ca93c0c0e6d5d14a2256e6b7a951327b3983d0bf4f60e459cd157ec42e0	1	0	\\x000000010000000000800003d0de034b0cd12b1a282a323ca1a6fd76a37177982d374c08e4586ed1095067eade93cf0cea589adb3d4dbb0d91c6a63199f5d405341f6a294d4cee4875b319fac1175ded3c60af320cd1f0f41ad8ea1779f09ea95b77f586cc2a9393b77e220575704cfcac3fdeb431659d624d3f3444dc766fa55a123a68a47ab01c1b52728d010001	\\xf854c218a1c7e2a932fcf0fe8b92ded8094990209f586fcf8afe42d7eef8588df77438c0a8add062bfa622f6f27b24b43cad3d8311b8dc33fbeda925e3f3c105	1671393326000000	1671998126000000	1735070126000000	1829678126000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
61	\\x8bb85d4b9cc2bf62af47c317651c9bdfbf3a573fcc3009eadb933fd1ee20112befaeceada44fbb747d60de63d3768ecfe25561c61597bd23fe37c5fd96fc1e00	1	0	\\x000000010000000000800003f02719a5a1da71762bb205fdd84e2df6a86326355b94877a366c51ec6f29676ec8a6402918bf0f2c42e61d1188f7e7ad9a09173abb8880e0d662c610242f566910bfdd59904bf00d00a6a0446f65f0520b22df32a63e9ed96964c9c76707bc2add9493156fdce6ac16b9d6d0debc53e5a242af977f7bf6d39799204fb9f6bacd010001	\\x17a0dd76d38607b8abeab79504ea0632c1112b1b2c63283760d8549ecac0a2e55c2f372bc7d2597671cf8c20c70c2ff10600d909d28c9c1dffda920c1101cc08	1665952826000000	1666557626000000	1729629626000000	1824237626000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
62	\\x8be8939d23e8fcde26fc963685f27a2b854aab8438316b74ed4c3f8bf7e1d3830463851789926acc87da40d1b2582aa1c6edff1fef194eea6725af32630b02c2	1	0	\\x000000010000000000800003d434b6c9cd8dd467dde1b35cf13e4ab5dec20a8ad8e23140848e4118164dc68e22288aef2b10850b73d3976de5558450387192912e2d050bdd5fb6487e92a5eec3eb43409091304360c995ccb1c467909701fbb7cf1d1a41e1ef6e4864255d1381c7de2cf00455a53da7ba7d99db706ff3e73c46373c99dd5f5cba91857ce05f010001	\\xdcbf661a18851e5fbeb4c15aa63f2667e6952c1f09c535a7c3134b985996b216d21d6fbf41614f0c9296ec32e574eef21fc03df77cda0e26b4da27b22af6e809	1664743826000000	1665348626000000	1728420626000000	1823028626000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
63	\\x8c248dba3194c1c0fc4a5461eb54185a084eb7808d02c3441c8c9e3a3c8c89a1d9644d1e13edbc33a526b3e1511cf142bf1b5803785ffcc5a8907e797ba80843	1	0	\\x000000010000000000800003e57aa9375f53c83eb328bb190295343a0d19f5a92223af3653a5ccfa08c589864df2ef5f69466e4da4f4014a130033b88bd74475c94430f4c3f815e645d26c932838b97334345f0632201d16ac0bf0124a57460b23f29afed0613c174f8f3adbadd1c1f9dea8a0deda3f9a3eeb8489c37d92ea0d69124d65a1f0d48b78be4511010001	\\x4445d1a7e7a4d7fd3d1580d137b501301f3f037ffb1d4f8e58da72c688e96ff4fb15c208eb60fcb4f925d3fba05ad226f64cff562c3ca123bf45f710b37e2405	1673206826000000	1673811626000000	1736883626000000	1831491626000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
64	\\x9020021f952bc3636acda28f43a5fd75b9e749e21af380ba0e4031ab6ffe9360b5a5a59c8be827174b060dc2c7a09ef0f0b546c7274386368fab2e07344ff204	1	0	\\x000000010000000000800003c2901ecb447f49ca60a8c81404f02308cc51bc45398c14c855c90fe9ac1ce173049d83bd5d694c92d1fb46c2a940a62019066de4f7697805cf7705b97eefe7658b7cb230fe81caabd3ea80c0d9127c731a0fc67fbe8d5246fc0dd5fd2ecda23628aa06ef88983517ae5df968be3e176208823593e1e6fe75b0e64249e7486407010001	\\xb3a37fcc288a45fcac2bc71d2513563a6472acbff36b0874997c365428215c6cc8663e73b23bc82bc8e2e6a097a9e4e3b3b04b5259219ac4457c3413ab189f03	1673206826000000	1673811626000000	1736883626000000	1831491626000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
65	\\x9344f7c6468ab28254751adbb842f1f34d26b5a3fe20a81deba8e486740a0283514379311351550dcfb2b02554b07481b980aa618465af0002c664e10486f9f0	1	0	\\x000000010000000000800003c3388ec656be98c3088784a3f61ddc01ce02589d78a275730c14dfb9c8bcf9c1249924df5946ca7bf22c1e7514b9b11fba8f23236b7f5809526c6cc82ae2dc258eee4f98e669eea35654e5c3e9b0d564cee001388866b3fb2d1bf14b7017e147a761d9b5f95d22b255621fb6a5e144bc41b92e70da39721cf42d50f739656c47010001	\\x203135c394c19fd8ba151d6e6c4dc63b8b1f3b2b0fcae30a9506cbcd40016cca73463e5ccce52f35c928af4387627aa802c7c78674f7546d4e4af218908cc006	1683483326000000	1684088126000000	1747160126000000	1841768126000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
66	\\x95d0884cc733d231a143bd000d17f00df6e8a5e906ec09fce1ac80039adb5adcdd6a94e9c5343da602d639b55b5519d68e699f65b1de8af023c36445f766f362	1	0	\\x000000010000000000800003c1467796ec6dc1af822e6b3b4c7bc684db3d12d3688de9577c37a111275ca428f7f6658796f2ad53badd6975faf7e402dc2827e66650be582dbdc5f9320100a1a511ee2516cb36e317df4de6d5ef6392cb4cae6830ed0fbdaaf8f914e3aff37ee24924b5b8e1a53beb7173cb1877925872dddb18113497b5ba950f5f22aa3f6b010001	\\x39e5305377e9c86beac3ee86545844ffa6c46f432685b5601be37b1178b3e0c3d58882c3932a8330ab36365d9c132113083819f98c7ba959cf0d8ad75c27aa02	1678042826000000	1678647626000000	1741719626000000	1836327626000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
67	\\x9608d5a1c3c7f3247019329dd464c1b46480df8d22df1315c72b656e813bb2eff01179bb3c4c4034d1c36f3382a204edf2b80431b2ed447bf96214e7ebc6b0df	1	0	\\x000000010000000000800003c7bdb5d318d479a40ce11a252aef5adeac08d2a74a668f220e58a7332032fccc82305ce0f5b770cad119066b84fac347de7f26c4d2941fbed32bd4e8f659c5671a24546304581697e5c0d6b4095b2512e846234a4d6313bbc23ac60e7ce0087842f105c23344aa1983071c893366184965d6985596eadb9ffe06f8588b710cdf010001	\\x17cbd967bd2ef080f3bd649825c08725d4d425c1ce0d456edfed5e93f9a3b230d1bffcad04104ba707c96a5c0e9eb81d6b15de0c8ee8c48a6d64e7f926dd260e	1690737326000000	1691342126000000	1754414126000000	1849022126000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
68	\\x9a30c2bd5fbcd7988e86b5f80697ff4bad9de084b13a3e76738f5746c61cb9fa957b8c24bc7cf62d86768b2d822ba442bc8a591359abaf11930104bfccbeb0e5	1	0	\\x000000010000000000800003c79c5e03d6228eaf1c82bd2ab7fdd8308591500dfab3a327264731dce0c8e6420aa9733580118e6378a5a12a9cd375426f116a9946f9fe5203cdf8c5a78d711a05d8bb7bb4d19dbf706a272e758c227ce873933bc76b515a7c20433439eb3b5c0c19bf2d37656a3960a0be2cc97c15d3065f873ae1714ae6b154d3e1e2420d25010001	\\x08a766f83e77f91d67d1a677b418a49bb62eca6b25ba2a55d63b5bd7b225a9e8b53164bfa4445867616e20d831a82587aa0c15ca884aac4d3a4c86d6b7af460c	1683483326000000	1684088126000000	1747160126000000	1841768126000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
69	\\x9bf834e61cc8df43e7d4116d0ef089cb081048f0d739345c67d0d90d2bee368e829da0132d0cf97b25461950878eb3a17f9bf180656f1ae23631eebf5570d0c8	1	0	\\x000000010000000000800003a8b5110702294f7296c8850dff52833253d63113176d41b258e0285e671b3af391b5e4fd0a3feaf2c21f329794836c76501515ed4f231d9802ac4048ab31a0d67d43c3c789280a5c7ff3fa9a683725fee2e61db80e900238de0cb293596ffee0b7f75e837810ba05a289753a139f99d37a2594fb600728915ad4a9f44e229ea1010001	\\xc3b84ca4690826ad345c7708d73da342eaabaf7c3a2cc4f91373b604bb03d9eeaf8b617df5deeadab9b26dc81d8a4192f87af67bbb3b7f8ef7b91c9e504a4b05	1687110326000000	1687715126000000	1750787126000000	1845395126000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
70	\\x9d08187588819f0f16aaf40411b4f15f26bf9ad3d2f734d70f3acb364d174c7d732a6e96270722d2dc44ff2b48c2bd30e51249088e663ee7df5fcd6b185afae4	1	0	\\x000000010000000000800003ae4c8c06959fad4f274f9b114f17702cc41bda63c42a63063cc553f11aa5fa0e58b7dc92ab69a2f6c4551f004672dd79338ac43a474aea885366676523ba8a8d9eac4555d56225ae0633dbbfaf3b12ec86f59fe281cbd29f069c866dedd8d6f242d49b6511a2f1f7db4f057981383ee69cf5ae26c9269fd989e8bf220636635b010001	\\xa6455fd923c717e808ae0b9d6c75d771fdceafb6a7c54c61cf0d9ad59d9eaa81b61654714f80cabf954aef6a70caf32caf1cc1079cc58562a00b99e64b47da0d	1671393326000000	1671998126000000	1735070126000000	1829678126000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
71	\\xa0102ee6b11020aca7d24f16d61f24d00f415abf89fc309db42ec02f7abcc164aac07562f8ed2d65491e2ce66a0c05333258cea50b36bf65dc8a4cc5bc681351	1	0	\\x000000010000000000800003b6e9818f4c249babd4b6b856989cc9b48d6104898cd5303ce7b5313e1fc5a4e68f12e2fe6be54e826ff9cbe91144baafa1b202b3db879c40eadb0dbe229378709adbe1d9c0184088e1ba1db47ff58ff121e1c2a5bdec54468ba2b5696c9f6077c0240a3dd97ab9a91891fc7ee98b67c3ceef4fd6feaacc1097886ff49b30d113010001	\\xa8b718d6ba7ce58cb018ec8928051b8b017e008d8fdce29fe92e09e8945cb2176fde27ad2e2e8def45ca138efde21bfa2009a0bb2fd3d79a8fc75b50b2da8100	1681065326000000	1681670126000000	1744742126000000	1839350126000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
72	\\xa1f89fb8c517a4c924a100d41bf7cc2ab414f2c5ce2426432667306583b8d349b08207709ed0fe18064ae00d8cdf795f10852d2554e2016c599ce085aba48120	1	0	\\x000000010000000000800003bc36235db7f5af0e63ed1b0104ab694368a1b4faa6c114b6cbeb5dff05646ea2da7764b0b37f83a6ea216b9023e230ba6a3519d88f746d38b00bdd65464193387f538f5d6737d7a9f72d48b109f60e1f81ff571e832a0a2d8d66efe7c4e59847b40f6fe7a59aec8b09f5a3c3e7076c05f2cdd0716f07d2eafa452afb183259f9010001	\\x0cf5e830b3ff88a2594c43f214605a275267a437ba83f6ff6397a534b43b1036e33037d84733f8c27f0be35bdee009f628664722f24d71abce9416c8de2e3c06	1676833826000000	1677438626000000	1740510626000000	1835118626000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
73	\\xa28c0139fb8e91e6982af74e0846a064d21a353d5dc86189d4f6842ed0b2f6cab91b1aa7a409c8bb1e48890fe06837551712553789b1a5de080e1655225f6434	1	0	\\x000000010000000000800003b7c7480b097b11a879b9de45b8245106db8ab8a47f3ee4f33497b86e99a1f78e0edd1fd7ff8246d956e25cf40366f4d1ed817697ce762f99460addcf2ee20bfeaf673b2cdf2de07e75be3844a9683f52fc2f0743698e36990c9ec3aeab324b203c28b925c5626b9ff169e24cdc6b7eb15e12d6be942dbe860a649f821a53ed17010001	\\xd1a18dbb4e04b77a9fbdc7ea0791b9446fc955ed820222466a2a757ddc7f75bd351ec769ab7ba6bd5a9275556c334283310419fab4a30aaa72cb45c015c54208	1686505826000000	1687110626000000	1750182626000000	1844790626000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
74	\\xa488b5d8307ed5ff27e9623d01cbe3c9ec0b7343c04be4d21a6fdb8ee5a785e5d2c48fb882a6abc3b65117980c5c748a740bdcb77271cfae199c1c0261c2978b	1	0	\\x000000010000000000800003ef25f7fff7e263aa1a026fda2b390e5d509b2529fbdad61b7f13bb4e3132ed24592ed4ced2384258c4e84d4cc5d4e9eb2c0febc0edf1f536afa2ed6b8ef576f5551ae9973285d93a212a99934a37d26bf71dc65dbcfc053357a27578e7bf4576b6b5eeb58171be74e1a7edb5cef0dd3c245d568bd89bbba2f486dcbc50a7f657010001	\\xe989714e1513ac2a0108f332baef6d7366a86270252f51b625bdfe6d1cc5b39b76cad601001d5b9c4b55edaaf382509e0b94055f5ef69ab0c2ee655d0150190e	1681065326000000	1681670126000000	1744742126000000	1839350126000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
75	\\xa9b43090e6d96740469d3a4f8f0e095e35704acbfe5f683d6d446daee9d9e24399fda6b0035e100da3da39fa308064b722f595e6629551f0a838575c8b1537f5	1	0	\\x000000010000000000800003c8110b1f6f92bfc42e3940d3ce617ccd15c9d890cced1d098935c867d41389a0529817a801879e7be70a8b8138316886f886e976d041848fec00ecaaaef02b0f2e8c1d525ca2f3fdc1b839a5124a758503a55eec977ac755369158a6a72669f4b43576d20675010e37666cbea3ff9a486e837ac006ec5a7553f592e355e06415010001	\\x7f3801dd2bef81af1ad4f5ef4de255407ad6525e9a22d31855c3f3a393a2367dfc07578b49ceaa44d0b6567dd2d99de9e9575b294f69aca7494eb299e2200d0a	1661721326000000	1662326126000000	1725398126000000	1820006126000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
76	\\xaaece338f3383efd142382eaec3862ba74494034c4a86194355143d81b9558146fb404587b9febc82be6fe4bfcfa4565274f3bb24829747ec77950845e83257d	1	0	\\x000000010000000000800003c6af7b364f3024ced944a645d579bd33503ead2b9f7e03dc11d1fa1751e5f3a1f0f6552e78e28deb9f4842bc4db21e9fa4972a523a9a7774f8e2a05f8a18a2465907c402c734c545049be70ee458ddfa874ad4b23603942fc80fd3483c3921c226092a1e1359d404a6ef56f182d89eafa83826e813bdd2b2aea5c12b9e104a83010001	\\x56bbcee1cc034db2f4a25a0f6e67527c683568c41d990bd51896e32358ac049075568a8173c02087f528af6b1877ef589c93039a56c3c57ec4602f6401ef3a0e	1687110326000000	1687715126000000	1750787126000000	1845395126000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
77	\\xaef0e512535138f8fa938b1089f534d877a2023ad663d6f6deab0413447cb3a00cfaf24dcdd37663d193fe88b89e7b9edb5ac528a3a7ef52c71ce4abbf6eb60d	1	0	\\x000000010000000000800003e81d0c26e04397bbbd341ceb14e23f27cdc59fbfc756e8426e10a71f6f32b97d67354ebf3c750a07d5d0f65a5cef001ad8d32e35bcccdef4bb82ad40c6ef061fcd35e6c3efd00a87a50c076fe0cda8055ffd2fe44795a22c5e91a64165048d10c521c62b40b8cc38a723447dfa5ee2a7c458732ee03505ed2ecbd9a91da5f5f9010001	\\xe23b30422295ec24dc56eb6c17192230d21f6585f160860d1f162a20380e4c5eaa05bb88836fd8f0b6fbaf6f536b5749ae945d97a9e57b9922cb1666e1b7e308	1662930326000000	1663535126000000	1726607126000000	1821215126000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
78	\\xae3c1b3e90136726eef7d0951a2f36f9cdcf0a47b8b3d2f3e3768ad1966765c1e3ddb9baaab4a51a481a325e9fdc1b51fec0241ef1468e3c65f406c0bc7f0cf0	1	0	\\x000000010000000000800003abf6237299b5aec0a0c1e930015205e08cda8cb861ec7e1fcecd420b210e9819d97c6575163a374c66699dc45afa1ceb582b9cea66db8d90d404d3d82461248bac3970ea887e7117414fa734c4f9515a321e7fb617a731250f9546c65dc8e4e1e88e6b1f54da1bd6a8c49f40058167ab63fd0e384bd12cc7e8601a4d7ee52683010001	\\xa0d327082df692b363c918fa52c56480016b0e3f634ee80a97ad926d947e75465a5544d1110310fd1c0dfad8d74aa8eebcff64d5d25bc5e777deabaf4ac7af0a	1669579826000000	1670184626000000	1733256626000000	1827864626000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
79	\\xb0f0c64259d80e16a2b30e5bc3c89be1789b5c92afb445f5b63675dcaafdb2057613c239f7ca7dff8c241fd9103111229f1207ccd165a1bfa3e9a850d98eebbc	1	0	\\x000000010000000000800003f90847b8683a941768f0e7379a32fc466c7b044da5f2590fb6ee0c7f054acb81d61a7e1c7f488c8b64f193947bc29244b3563bc51e5d7e5eb9f083afacf7bd4b5ccec83b88e9747aac76fd02ff2d7f55e3c35acd5f6e99e9645ed21790a82088c5b9a218a4a35c2c43e9fb82ee6f96235033b379c77225bb13766737fec88f37010001	\\x88f21d8b026b754152a7bd8e1c913254e3663acb49e1cae618d6e68d0baff9dab1f8ee03c77d01bfcf50658c457030f750ca9e25e3d92413f0160ea7cd001d0e	1672602326000000	1673207126000000	1736279126000000	1830887126000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
80	\\xb92c467cc7b9a61e8d1d4b7f38f7774b65d992bdae553f09a3f1d412e78ac4e8eb490e4ce7a16e7fe8c7ebe0cd6afbdfe06b9fdc615dc71fe917aa4d14b517fe	1	0	\\x000000010000000000800003c8ebb2faf3e0b993b46450727f973344540d0f717bc843f8d30753e5e91c6622fbf674b55bab1481bdd9aa448d4c2a388d2b5fb4fbc49f6b1a8ae78164fa583eaaafd843a1d43e5c7e1036d442c55e9fc8329d0ed78e4985a7a0887508e1010b9ea547e52fb9c719243b67f1f258e711cae4d2943c3814daf9203c316577c22d010001	\\xdb2aa5941c50aedcd6f42ec84130c196aeeed6fef425dca1d4ee7fd4e9e771969fcf335527a217ee01c4e8572fd022a81f270d5d5482a39d4e7aff0d3dfd8802	1672602326000000	1673207126000000	1736279126000000	1830887126000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
81	\\xbe3c1063d292cc4c4b2b6ff45e81cfd7db496b50c49b661d2efc937ff13017c6ca9d694238fefbce90bbc5445a6fdbe8b7a9aaa5b8c79e08f68457440d7301dd	1	0	\\x000000010000000000800003d907546db9475f82440dd253ba91db37b6e81d6249fd8481cc89350f72f76b41ed498b6e0551f6d65e8369fac6b9320756dc6af4681eee7c7ccc463702b69a303a9b3d7816aee22b55695f4d2a440cde13f36fdec35be4c024310d1db2f426d8c1d69733631a41831daed3ce1752a68f91e0ffe4b331a54052eb3dd2c05a5a6f010001	\\x497ae8e853f9392e53f64c679100514ea8e15a1a5f60c53a215602df6bb090b015d08a27b7a9415f1d73fb861d8c12bb3cf149960e9d5ee682622e998333ae09	1662930326000000	1663535126000000	1726607126000000	1821215126000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
82	\\xbed4c493d826f10656d7fab83c591f593e25b355f24b2f11fd17a0e4a32a67750083af84a0a4418c326d99b101b8ff2b108b4cc5923d698b58a0bc5bf491e745	1	0	\\x0000000100000000008000039dcc7ac4a37a084d0ff0cef5dfd1f993a928854d337e3f0f564e829d49f43f0a031b4c0c15af74fa4d259fd69c99ce87569f11b400934bab4d9e2cb7afdfb93d84ffa846362b5661304b9fff37c9b31eb0c95f159f02eb76a448670f3cac0ec257891a8b77ea6e889cd22f12f90907bb5553e2c0eea349881bd7a764749f487f010001	\\x5732c771fa9d8676aa86c1323c67c7cbc6c35e7340e1e576ecb90cd0984bc5d5e929aa6d79f92ee91939e15207b112f96ea5e1ad863a5cba3d1f30b66e3c3607	1685296826000000	1685901626000000	1748973626000000	1843581626000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
83	\\xc21844d1e3088da8007939e48b892c05023d917a7a580c16daa91376e680a1ec07aa96a4877bb561552aa51d2800374e25eab93b853cc8518c8a778408d017a6	1	0	\\x000000010000000000800003bf718f5f158afaa2dc1d805295fd946f25993a1dbf6161ae29b05807909508a9d17250dea8f76f886e649c00fccb42c420b3e7873a66e71ba09cf61108bb40d54e802d44cde60129947845c24bc277fe789fcdaf679f5b5ae98193a011e775c92b0fab323498099291b6e7b4da1eadb5de4028537ab22a32188ebb68e489d953010001	\\xce210e922263c1afb3beb9bff902adf235d659ae4408ba675df72d7c375d7566cab3090266eb35fe19cc2ecfef3d7a4add637266e89a3b8ea2f2a3d72334cb09	1670184326000000	1670789126000000	1733861126000000	1828469126000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
84	\\xc3fc498aab79fed883bde39866486f1e1686daf93f2975170d97138d3079b0f3e271432b1b2a8b38f1da0e5bcf07be7af266b7cf22a848b242aa886658024686	1	0	\\x0000000100000000008000039b27ac875b2bdb7e46750496c53cbb35f79a7fc2343b41ccb40fa2aa900c4c8060b0abcf5aadde37a46f165da8b91e5e1847925e603b63010d74fb6bd03b9ec29694980abf6f207bd1ee79e065f8654c5b8717ee2bcba1074b689ab219639e91cc47f1b269c3f0c03d4167226345abed7a1f512cf835b18555321abf6d9b3d6d010001	\\xd458d7247c61496f6c1009d7c755c5ef303f565cbb79214c03c7d3137170e37830e929a57abc3b27885243342f5c5ceee5161c7e87b7fa999b3ed7eeeb65f60f	1669579826000000	1670184626000000	1733256626000000	1827864626000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
85	\\xc4f4ad0294accc4b8252ea020b8dcd477dc09c8bcde57c63dbaf6783c673079edc7ae0ff2585de6256aed063e239b9c74234472527a45c9c6c9f5e622dd00a59	1	0	\\x000000010000000000800003c85c7b77f65eea74abee82ff746e9f64217f153174363f58e594e298681fa40f20c360f99a839e3d19ac8795d706c66f714bfc2f4dd2e368a1af8c43878051205607aef933be51d928935165655e1ba386b9164bdd2564641f888d8ef78dd0ebbeb4b842909a655bab21acdf1299f74e5715d02185cc40e95c0ec2f4d9919dcb010001	\\x90d646bfa99f69254de60202b348d23e9bca5fb260ca83348ca281a399e2b490754fb7f41f98adb1cd05a34f4baf106a5e0727e0c6648f21a13eb44c840c3506	1662325826000000	1662930626000000	1726002626000000	1820610626000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
86	\\xc4905c90e4f93cdfb3d5f3bf266cbd59b463afe1793a88c8ffa26ed943c36bcc686a763c38f7d8f639de9def3f31fdf47e1d23c700967d11e388823cd0f55a09	1	0	\\x000000010000000000800003a47a17fb397777bcbcc211193271e31df8a657d01c5dda919cc079e163ad217f08215611429e21d6e41801d3e8444d85b37f43bfda802a2d8c39e3e62fe938bafdeef2073e2662c4e9590d7598b093606dbf0c39e5aaabe4b52b292cca988d78c49792105dbfdfb33811ae762f30ed3d2c9a0419b1a84043ad2d8467f2527ab7010001	\\xf818fb28225a2a9b2d6e779e0f13bd1e4731a23bd45f698bf56b17871a6733956e5ce95728d4467ea2a4476d86b5a192da25f060560155e2d394343dc1ad5d0d	1677438326000000	1678043126000000	1741115126000000	1835723126000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
87	\\xc45c7d3f8cce669de5ba6e00e46f05103e0b9fb271342d8bb2c44704c3d0510c7116b0d6a3c938748fa149df6fbcad1e39983ba4dcce8bf7659e697684f51e56	1	0	\\x000000010000000000800003c142ca55f23e3a125e46cb3ea50d330be09a565efbfd8e94af68aace2920fe814c9223b8081778d743317012eadb585c0808465053d459c4ab826dab5b56a6d91b2bd7a2a2934360b5a5c586e673733e3becbe8072190d42934157ae0285b55c047eae491d18d7bec9904dd1cb24dd0cb1b95dfa3b14ee46400d2742c5df1525010001	\\xf24336e43689730869a7f1690cbc0dd19415ffd7b5e316a4f13e831f7555bfbca8120f64be1beedc876fe23c0e9c4a592e5110027845c9e2396d060e0a43cd09	1664139326000000	1664744126000000	1727816126000000	1822424126000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
88	\\xc554f2a092b99d1789bb2113e0cbb5db2a23930a93a85d17c3c3c8a35b1139fef573bc44930d2c3c6932bcc916368c5573f7568554fba14d0dba826eae0f4b5b	1	0	\\x000000010000000000800003acbdca44ddcf8fab82306756fbd210399558d2124c0eed5510ce0aa7390d86c21b71ac95a7e909d33bbc186d5ff386b4dd3fec9c9e5a5474378da834a617f6e8101d91c6285270d792fa481015b664dd0a3d7d348710c80249fc62bcf7fd0edd8998e7ddd96595a4899aca37f03fbd186da618b6e733fd309b950ec9bcb413d7010001	\\xed69b910dddfe1af555bf9029eed156e835adeb2d5aac6cde8e9357903e620ea68ce8bb07716ead8b190539c8b10b058b89d59107ba3e45aa8abcdbf8f40b807	1661721326000000	1662326126000000	1725398126000000	1820006126000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
89	\\xc62c0cdd5475f818bf822be1d390a4bd8e38f10ef981b05c2ecbb16226ae283f79968468f132cc041c7e9bf8fbe09f2e92ec385059d0891d5dc6a86fdebaa169	1	0	\\x000000010000000000800003e2224818813337a96428ee9ab80914c0bc502c063626ff6d0e8bbbfa46d5a0eca396ca167444aef61dd2244b7f584167660a72ab8c1c023100ff34b53459fa7909f819d11ee65e417852fc41fab64bcf68851b87ff5cba5f0e5ab437dd86ef63c4f4ded48563e2aa8e8e714aaa678ec0772c316c68a9221d3d0d103e6380b433010001	\\x3ca362b608b8d0b6e977db03dfd8f21eb745090896400b9f3c8b49b522e312f54451baa8e3a3acadfaec304e5660eb213bd532f15af5a61247627ab029e8210e	1690132826000000	1690737626000000	1753809626000000	1848417626000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
90	\\xc684db98d9e5ba7fb1174d3c37ddc6296407cc5d0a375b71a5da364f08149b28765cea55a09ae7d9271bedb27e9aee115e89e2dc48c7be9d73b2e177022dca7e	1	0	\\x000000010000000000800003b9970a480d9b19140f50f8de72d25005ca65cde6bc38a7db55c62bacca909fc3a9f1b78696b3fb8557a0f7883d78aaf7a3c40f582f152e379b22954f0f8b648aaff15024a71c2b8d4ae1d4a3d2c4509eeb8f3578576537267d5d913cbe1b185d9f188fa12c236bde92c8c098935f9b70d6bf97cc0d6383b7f691e837fa559d1b010001	\\x827d8d1b94b2f4a4d0d5f105d775e1fbce44c1e92f64346cd48ea3d15cfd5e82740c58d8c13119e0e46509f03704bab1822037b09ed034727eb9e21bf8c3d600	1688923826000000	1689528626000000	1752600626000000	1847208626000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
91	\\xcb3468d745783459a4612e8f0c918253267a674566a321bd742211ac62c1a47daa9abc8fe0b5fac82e9797453415e7a2a827f04d737804e9ea14d0d56dcc1ae0	1	0	\\x000000010000000000800003b09f92bb4c78ace05277b3ca36140ef664d4dfabc211e815b35ec239a18a4276a251208dc8d318e1bf53ed6c2155fcfc9f46e8d95d9380951315bdd1d9d57a291210d0e4de44cb0e2307c3792390ed81fd14d8c5c0805f9997172fc59872b3fb49e1a329327c30c6df7b4c1324c44fcb6110f1fed9e36d7f308d1e0dfcc8e5d7010001	\\xbf56dbc69bc3d380c60094864d602465d0565b2ba68beee7ad7856207125fa7c3683d49bc7e1d6329b7d04c00f091065c6535d739462ea006f9280f658ea3d0a	1673206826000000	1673811626000000	1736883626000000	1831491626000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
92	\\xce884dc65ef93057c2ce749b87ded9894c184f10c98400b0b1406b69cd1cff8c0063a2ffd30a9782dbe7d9a2417d9bc834429794b4ec2e99c0356504961023fc	1	0	\\x000000010000000000800003bbaf851e6e4b1eceb9003e9ce9b45b7dfb70d2362f464f20cfd26c44eb52a35f2f5d0c5671ac599a117641d1f5ab9398e5b1e7e94f03759c3116ca1986ad1d8dd8aecf9cca4439f26a99596caae73d56d977f94bed73efa393360a83c99cf1a60d76b0aee6d7927658baadf00716859d3cd79785ba8b82c2c1e23285bc9a1f6f010001	\\x69a1055a2071fef71639eb12f3dec2b9c2ab05a4c5531dbfaca544df47e2fd29828ab3ec54124bf80fad696bef06c8eb0b057d533c7e58d6394586c9b531660a	1664139326000000	1664744126000000	1727816126000000	1822424126000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
93	\\xd2c09036a81840b30d092728131346cee6a3e25aa0487adcbd8d060515b0616c67321ab21c7a02de4a34470189965c7dabb3a3a064172af293da1f48e98182ff	1	0	\\x000000010000000000800003c3f402e5366efdaeab256bef61e5af86d0f6f76c09b133235109d3f473ec669bb3daa463bbc07a4c23617819aaafc3e78071b7041fd0d84488c37f5cbe7c60d9e085e582efb186d4cdc26208c2eaefbb596fc5a6dade7e06f751079457eab04a2151b95545957c96b65753dec21676e817b8d9172626d9ca73d0bbdd2a565a65010001	\\x165e87be6058070587bf11daf694fbc1f95be5d645c664921f386923252f796f2d23bfc9f36cfab4bf1b135c10daaae8995e6219c6cb7339337a71374a75680a	1691946326000000	1692551126000000	1755623126000000	1850231126000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
94	\\xd3c45c19c8a59eef0f340dd0719fc912dac8155be321e756a27b8a1d8ceb0be5d37ebfaea99af01a1b20a4a86c3403fc52d43d81dd47c94ced5dd3fcabcfddef	1	0	\\x000000010000000000800003c2b176cedf543ee78bb3a9c848644054d4c9fadc1a360beedab8837e0f40cabfe847de790bcdda83dc529b4cf9a4026455dd966909af584bf241fc353bb02a9a471980676a78613e47d81a917a380c4914f2a5a1676ad5b2593a4b2579f9356ca105328303982e4f50dba029322f436ac74b7af36a58bb585a4324b2cef64489010001	\\x96ad06efa787bfef7d4e395843962246fdf90c81414a2f488c506ea2cb75671c7a6fc37e413cc405184d79577ac2f8697799cf5e6474d226de19b5b1af409d06	1668370826000000	1668975626000000	1732047626000000	1826655626000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
95	\\xd42cf78f5358bcffe4768511044e3285581acd1eaa8ea381ebdded64edc2ac3ba0b40ca46c34ce6ba143421c365e08d2bff9c040251d2cbe3fdd0785c53285d7	1	0	\\x000000010000000000800003c11ae9e3b03fc7955444539a9846a6c902e49c0b956e9498ce98fbbf78c85c643821fb759ef297508d317dbb92c02d75632676a6848301fb36f95bbd26de1fe9da63d61051c8d57214e6c9462daaed17919fcfb51b7d7e93ca766bca1afbd2a4a3da40dc010d6779dfb1c7166e8625e3e50c9d08cb5f17d29e3208b715249ac9010001	\\x3ebd7532c582c086e5c9065e3260ddae64e500fc8656abe91a8ebd4503411eda993e2a67684bdd8bdaf9d837a28d1ba21f2657fc4c32d63e05aa5533dfb6e205	1690737326000000	1691342126000000	1754414126000000	1849022126000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
96	\\xd9fc61f09d22b6de0fc20d4aa7b3cb341b5132f2fc1454b38871165123ca592690ce9a3e5db276f1e874bf18a354265158d6e6af3f3112580a81b45e099b86e0	1	0	\\x0000000100000000008000039f03c4ce8785c739e1e4325f535fe31633a4153ac33daa6df3d2afec08f6d2d528d6ef9ac26f0b88aeb9dda0ab0d758d84dc28a8bf462287c68a13f28e60c2d5bbe538dec04b3377f658f8991c394182c7f2f50930325b178273b595f3fb28f2b76d68d56e415a50e453abfb1b18eabdf86b334c90ab56ff922f63f31cb516d1010001	\\xa15a968e0704c8818236cad4c223910ee115376ed240e2f3ac28e74aa1265d63a50bf54ed6b4001ae3bf5ccb96b2310bcefa3ffd50d48496bb0f32a039677908	1669579826000000	1670184626000000	1733256626000000	1827864626000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
97	\\xd9901186423feba358f59aa92727d4fe55e119306554edfd708746bfedace02e90d05d539fa904f1f7a410201a241deee36abd79c31bfbb06e60d0b5a4616f5b	1	0	\\x000000010000000000800003e3f64931c96f2b1c542c4536cc07a11f73bf0764f292147b8d4f9d58b2ab742360e3855fb1c819c20dae869fae20a402c5f2816e539d5ff43f09f63b89312af08d196dc5dde447d0098414a3a037ca33b15569e1760eb000ec199b0bdc3e4da666c9ede3289099d2fe8fbc96a52046dd2abaa1e1b128eeacca7557ec78a1152d010001	\\x7911eb69fc7affd70f8c64d4b5cde8e06cc06c36cd6b325ac5f640ea10ea035c482c1397d98782e6b7061a1ed79e7ab4c711ef81b717cf1205237808ef951a0a	1688319326000000	1688924126000000	1751996126000000	1846604126000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
98	\\xda448311c82c819c12c81046946152d2b588e3fffd4f889007ee8ee205757e2f1d318f7752475e2ee5781b47838b53ce34412127ca142c3f1f12cd1adc980b02	1	0	\\x000000010000000000800003bde41e6d9f295707e611024460fae92011747e95ae54381368799134f8bf50382466b82bcf965f104adad42a384abac71ac3873c68115b9ef4823e4a84deca0353f46bbbb32af4645273df373737410eddeb2ea2ab25e0d6d13c45240f53496fccbbc8849fa28be6882fb660e0e79ab9da615c58c5eea184b142cf6f30310683010001	\\xe253a5c9c06cd22ba9617f328c87b3064e5929dd15aec7c42b4cce064852a7ba3b36e96302f26024fb3d5e615faca6ee426347849c4f156d01461f256218f60a	1666557326000000	1667162126000000	1730234126000000	1824842126000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
99	\\xe7c804112940485179b6fbd78a1a27ee3be27195ef5d02e9fd51916c173160edce0e366a381ced1dc9734faa46f1a4dbfb4a1db9728bf3db2774a23052bf98bc	1	0	\\x000000010000000000800003e5676800f2fb21b9943e506fe95e1fb6fb8e1b6c8da9fabb73a622cdc1eb65902c2e336ec75d69c2bc191223d7e0f987b7b3c4a8797c6f88de3ca1e661887c9efa5a7904dbcf868e9eb339a1c5916f210594f9a0160ce465ef6561aae16d619b9dac6e6642d35e93cbfc0b2e64c14204966c1e71f2c251eaefc309cdaddf8939010001	\\xc5708aa776e08585f9345b3f4ee78bd4291ef9da0bd051e88cdceb0eee0611e6b641d59931982532b948ee9efc706987112cc703837f70cc7b109176c9d42e09	1691946326000000	1692551126000000	1755623126000000	1850231126000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
100	\\xe70cc1e739ca91630eccd97a3ff068f4a804fbb950b8ef53967d6b57bfb5dd4d308aec6ef4ba90f88bf636c0617c8f0b2e852566d35eb3d68854cba6cb3dae26	1	0	\\x000000010000000000800003c89d84cf9e7d989158c2dcdb052c2fa075e18d2ccb83c253f6f6f87ca536fe54719d30e7cc81558f0d30985ecc58917a5edeb36c307fb44ec79bc4e07a602fe553603c62fedac6d796a20fa0205593fb4957df8cc16785c417b85d509eabd04b9c4017f646d9067b06f7b57b2e218e04043eea1fb16f031efbdc9c0bf8c8fba5010001	\\x549dad43c9a313340127f3afa90b599d529b827bae2a1935e02b162ddc09d1bd1c785f278c29ba24834af9dcb9318eb5b758d9bb2b43483b621992767bd1d709	1676833826000000	1677438626000000	1740510626000000	1835118626000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
101	\\xea68a6f77959f1d6a2d407539674a74b2a39cb86a6968eaa9f76dc98028837c8d9f950a75694add9955b397ebdc20ae32203633007632440d75a79a16ed0a3b1	1	0	\\x000000010000000000800003f941a6e1fc59d10b0b0110342daf782a0ae228977336fe52711ef9a8d0230e73329f2b52b0b405cd8da75c8b63df6173624c98c94815009d82ac1db6a719b7f9b93f18d663467329497f5c6b67feaf10f776c83ca3cf30d98a417c7d062cd37dc09187b34ee72bebaa0c6d33ba61e6bac45c2608bb2d9f63fc323deb40b2fc57010001	\\x8358b188e03ced9abef07eeda3fbc96c4df2146edb42fce3a2cbea70c43d5a1909e0350769e6934738266ded782fcec460b13bd1a74cf47a87b6a19c4cc11b07	1676229326000000	1676834126000000	1739906126000000	1834514126000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
102	\\xea40862bb25c487c73fe2ad655e0b37e9e3df611767aff081e466ea794381c8ffb94cf1fa90ec900739cf5fca9a6561a9c976dd2f8d14b5ef5ad74eac94dfd0f	1	0	\\x000000010000000000800003a40caca1cda0c1670773da3db064b4f7b14d30a020ab1ca7c6e95e587a697c84e53102699e4986ead91cd054760f2806a51caea6c0474f356acf5e2ce2bea800435f6ff73e578314498236ca127a45eab45d3cbe54e5e70e916e06078acb2a526f79d49510d63ac8afe9d26848dd62ddfc8bd76973d0ea430c1ba1b0040a0b85010001	\\x7171e854f1ee17f1008af44c25740f8ffafe412388b251222bbe708057630bc872739f8c150da19f38d26c8996aef5930cc41cbcb6bed6095f09834b99225f08	1681065326000000	1681670126000000	1744742126000000	1839350126000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
103	\\xeffc92447b8c6cc849ad991315a5c323dbab5e0d589ce2ee908d5fe4d0790ef737ca72759e60c4a4f0c109f4bae6f12133c7b62a49b4e5cefb561abaa976378c	1	0	\\x000000010000000000800003b03bf9313b8c445a791af77788ac8c76c9067d1f406598c56ccbc8e057fcec5b081355ff7e7fa4d0b806abbddcf63b89a9d6778ab967169448860e87484333409d32826339a7c81c43156bf7fec9ed81cfc036b35884d99437f6628ddd23a890885f14523de026e282a217604d004b69f83c996edf91bb7c58f861c3117a71a7010001	\\x8859cc5c24f623f132729a9490b170b5fc965fa323db80afeb6115aa2af996f8f9df6e60915d6caea4d0d1c196358c5427e3e849bad1d84c6155e9b457d5570e	1689528326000000	1690133126000000	1753205126000000	1847813126000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
104	\\xf24008820c3bd0699dcdd8539c6fbd1d3d2d0d66cfe99539e6e87afcf3c8fb7b1cd485a1cc35345f31b76da000d666316b602031d0f16a56aa2306b9c7c99d9e	1	0	\\x000000010000000000800003a53a5185408beb793953f159b392dfec21320ec00070636e0e6487cf69bc1af1d829413079c419504bd5fb0b2e60ad03e43b7866806b039c098b86bd1711391b60f654805f3820b2de4d4310ac3ae166929c3d0c12b4d487790cc5afcda02b0edbacce7b3a6ddc15d137896d1a1e1e1e0a5db7de2ba73189b4895bf775a96bbf010001	\\xb7f08340bd2f0b7947d3aff5f0c91c2508aee384aa49166a3f6f9662e7d64fe30e422ca101e0b6e91ce0b267c2c15567b859d83840362701416f6006ffebf301	1669579826000000	1670184626000000	1733256626000000	1827864626000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
105	\\xf3b8716bbc6c790e5d2ddabb1240a9c4158a07593b7e5ccfb7c7cb9ffa4ee251e5cbe9c956db5ad7818e81e71cbded1c5b9b5df29b04829ad1ebd82eb3a18d62	1	0	\\x000000010000000000800003b5491f79762ce03c31325b2100a1d2f04726199105dd20a08064eb91757ac3770e91f2162b98b875fcb8743b6b01df1ac5dc4b63c55ea9452c6bec39175d2c96e8f829838a549cf2beb57439711b994ef7604409a16dc8062888e3cdbab23fcc5aa6de02c29cf4536936d06d1ceac660d67379fa8f0068ef1ba49f94fd08f0a1010001	\\xe2b4a77f267c64c0ad2691b25091d52b6d89838cca3f20704e57022fed55518732cef109a24396c4d50f4a99edebc707cce6eada5f9b48be612878289a683109	1687714826000000	1688319626000000	1751391626000000	1845999626000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
106	\\xfd7478b9d23cb566bae02877930686ea9b638b543f364f5f8fa3fa31f59236b4f7d559845f4a25dc55e91f8909eef5d2c39f2567ce87400a244e934b82a60e68	1	0	\\x000000010000000000800003d042a8d17a4bb44377ababa7d9f0a9bcc51f0f7feab28e9581bf7891c95c299da86ac1930cf25750c5ebbc6b5df1dc8c1d34e27ce7352fcf983d7413265a384ccbe513d6fd61d84eddbe0fc0dc42ac5fff3b10044672bf3e36d10fd040fb64ec792b7938ff981a026f19f77fddeda55af11fe5e2eb15924f86dcfdc41654dcc9010001	\\x0f8266fef764f74cbf37eaa1183d4eda71f0c19c574591c801ff167be5e925fbfc264f640946e22bcd1595a3e1f7efaee9331a7b9343d4800fa44d4966873904	1675624826000000	1676229626000000	1739301626000000	1833909626000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
107	\\xfda09fb2a95742fbcc92622d14fdd84c21a0f594abb0bac74dbcf1cdba60384a0f50924cefd0b0f93d2105775df9697176de282d7e0ee6d340f7dffea4887755	1	0	\\x000000010000000000800003b3a71138b6ba634c3ac68cacf19738b1460956a87c17b4062aa3e568649e7d6cc1285799b603bb3ab8819ef9537d4bbfc75cf4aefa83665797675d089c1b6d5de92f3d34949e15fdf08de976af82d79956b6b22dafddb5a6f915f61bd732515a218abb1f5c36f4d52b75d68ff8aef106b587ea13db1fb7770eae060245e12ff9010001	\\x6e8b0c4ae7f0bbaa0843a17fcf06a414e6fd514239cec2db9eec4035c41ec5c1c8accf7eb198f21a045bdb975f8702e8cd5038e5381c054a0f6a6db1de80f206	1669579826000000	1670184626000000	1733256626000000	1827864626000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
108	\\xfed023bf9384a67b63ab0983267d11416ed31e44dd6b0b440e82b6c26e8aaf371f4411ee651276c88242692466606b08768f873cdf0696ac874bbab245a7cfee	1	0	\\x000000010000000000800003baf0de378cb4dabf6f8438905b31475c57e8dc56e91a8ac37878705a89352cebbbec0ec32f9bcbacbbfe6606d9c515735d23c77ec7f36df7543376a03a66ad7b04734b1d4a9fd17fccc5b4c9cf2b08e46bfacb41c4b278c490b210c1cb87a5da63e2d23d85b860d4bacae67c2f7badfaff85f5845f6a286464be3c38ac470d79010001	\\xf2b7f5a1981d71d0b97730620885e6a341b4b6e11a1c8fd6b0d705e30b3bc9fedcbcc0009f5b4876bcb170e9960a3ca3cd6a8068aaa18645c3586863da750b08	1664743826000000	1665348626000000	1728420626000000	1823028626000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
109	\\xfe586026fbb11f7ad7b406a47840fa023e485219b131cf132e30f573bdef418abe8ff8315adeca9967641c898361b493e6f03e32d1d53eb37762328b500af6c6	1	0	\\x000000010000000000800003b6288e2303c1aba1b86f9517ad535624ef5bce325aa978690cf460d027959655545c26717af2c5f6f48e4ae9f2e01a54dfa7358944df43a5723317e363e7b3dc1eef3ee5228047adb7a831d17866fd12d98be5c10ac35ee4c19a380510d7d934cf5c846d36352c0c8573773f0529c0450668513e422aa4044713eda4fb166341010001	\\x3592c6c7f5c81c80621b43000c49cb3410c49a9112b299933615635f65ab0dd4abf834fbe9631f42e0a4d6fad9e4839b3f73d498a9834d3e6e8956040b10480e	1673811326000000	1674416126000000	1737488126000000	1832096126000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
110	\\x0381116abe8ad6d755088cd20460fe12b0d55e2a49012c2a61fa3ce7cc5cd2d5df0a273dbe921122e8c834defeed70ec8f9e2afb350adca30621a20fd512edca	1	0	\\x000000010000000000800003db841d3c3d1a0f184917d6997de0fff80d993b432ad2c05cd11a531379579b57ac449c001a21dcc838209678319fd6e0865c89ac6ccdc0948093b38d955d8a39922cd37bf2d04e9ce642d36437f76e9b517805bf5e4346a84fafeafc64ef151b4e673c17ed0200c390c78bd44c8f0229501c1082c42bf67843a8673b62230431010001	\\x824d2da1d0bb492a9a0e6398f25f43891cb242a86ee742bb65d64b7a39eda62812d3bd433e2f3172538df3070d9b4d159ad6e1e10e602b55c5aad2f76f08a909	1664139326000000	1664744126000000	1727816126000000	1822424126000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
111	\\x051169d2dd90f0e4761fdb7f9150f1c75d88e87f2e334fd6249c21d654c45e9f097c73d59bc4fa8b1d8181551465dc45f98c4e02a881d78aab000f6b39525545	1	0	\\x000000010000000000800003d8c331963baa76be11e608f77242dba34d3823d09d980b4b9a4dd0cf07f6a3678c028cfee4b580fe73e89741aa1b9361bb500202ae82dd0c4d069abe8f7e68db27c871d12ca2634aaa093898b6afdd5e7317c8879181d1c054b23d647b3bce80ee4368ab11895e7ed9c392aba75f4e219527de3cc7159b5a02ced99179cca5a1010001	\\x43130f73c49b57d448ab232860dfcb58dd9753b0059f02361d34d58e00a0b150899dcf500005ec24fdb477ec9d7df6a0509cdb0473d01aebaa13a640d837ab0e	1667766326000000	1668371126000000	1731443126000000	1826051126000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
112	\\x05a5472e137ff3e41e7e5db48be03baa2b42e7e6f178cea9868e5cb80b5326de7eca9040e355596c8aec1a54946003ed0bee0a761a28df4a2b83d124b830808f	1	0	\\x000000010000000000800003afdc5a90b96490f809310559c2c497b1d893007b4ca9f7c9c51fac9308d7592e5fb75d62d0ed0d90729887909db2d4617507c0f9831cce680056fe7c8e38ee7c9d6e41533b573ee1034f31db23bce5698e0ad9695621bb256b83bc9cd745c19ad68f2df82520b489884ceb5d6c93d0a90026f4e872e153a6c26e218edd217d21010001	\\x26eea5d3ddb1d3f18389fee1245d69aa872a76841fb8af8c781f8be3c0fe3b6b9b078de3c2e33e5b4ef384584248b81b45e751920c98c99f5ae4d2afd5bcef01	1678647326000000	1679252126000000	1742324126000000	1836932126000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
113	\\x08192b47789567b0fa97662adb863f71143cd7ab114634ff71e92ea67b5cdb0c592b145ba0344f5a0e6ebed347eaf3e9d9c0afb469fd903f8700be332fc0b056	1	0	\\x000000010000000000800003b7459777dc47a850d069821bca095858f456469856d5061a076840063be05113d27e846bd115163b1b033038b5e1d58675096cce8edba4777f0dcdac57ff70d414a4c82999b1180d45873b365bf12a6dcbb2e39185a2c9c510a3f4d2430487a19a28f595411c8ceba0ec33efba16d18addabfde037558a01b132d77f1b25604b010001	\\x1afceb2f6a4d1e28f02e0c9df54c17cb38d8f3eb395fb2a705ba075e2055c47ca82ffe5022dc185c2c98cf86bf5c0c9f7eb5145103aa4ed7fdcf85f24ac3de0e	1676229326000000	1676834126000000	1739906126000000	1834514126000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
114	\\x083534c739c198335ac01362f0737430fd7e9f6c8d91837e7b5b3d317496f57742829e176184226629a75425ae66752a6c81a83e44b6ae69bf3f24d1434abfe6	1	0	\\x000000010000000000800003ebdf2a26d4abccbeff79005964e7fd50179bbafd236a9a79fbd77c34928630114f3f1d9f5b989c365bc7363954e995c335c00ae0b45c580efd22bfe6742d959515e1e7002b1c396ff212cb665b5ab91c225dd0a8197a4235f00e2e39a69b545b07ed20c627547d7866975f57cccda59e0df3fe205c6d3aad43bb8d028805c52f010001	\\x4db3417ea3e4dc02f31a9037f1e257fb3d0879d4cfb820f9142b77fa0c359e8cc36e630e09c706b9b2dbd486c609506be25f628414c9f39e2567864119995c05	1662325826000000	1662930626000000	1726002626000000	1820610626000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
115	\\x09f5fa4302600f5cc1f8c7ec168643a29dbc39f55a0293a7015cc968e79e2202a632e20787a2285d11ccd8e4bc29a1bf3da7f87fa29fbbec8b63cb9fafde3550	1	0	\\x000000010000000000800003b95faa79dc650f960bc44f36f4736a474e231d5c9e70b75f2ce7b4b44e57e8ff13cfe94c19a80c7fb1461557a845ff9ca5271b778039ddc9f3adecfd913ca24a4597ad5d54e9131246bb46933e482724f08c3760154f44949f98c33ee73f0007e2d6574ac185c27bcb761a2f085ae62c545e512a4cee3c0edcb95e9004287671010001	\\xba9668b92f4447d987756c693a3e2a51eaeb9da206a4416bc370b60c5b76ea27f319c5a74515e159a657f715d52e13a9fb502069ba8e0fbff9f9f8745fa6cd08	1667766326000000	1668371126000000	1731443126000000	1826051126000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
116	\\x0979bb3d90f7c81efc63d607e4b2bb15c82556009af42d0bad7ad4074658d44063f57fae2654f74d65c6c10c24a299dd3e0c36fa92465f22b19b86d286be5970	1	0	\\x000000010000000000800003d4074f8f27cc4cd5e8d59234fabeb873362ed61aa106998a7e1fb227cc629fd5a817be2e5dccb18bc1a16eb6e62067f09f068a2cf20fee26eef8952a9be57794ff12f0cd0c73f9c47aa1200d81d78b55eb78c681e0383c53559fccc07b738a13c7fa64fec72deb774756337e20e1e9a3e308e2e6ba2ad96f90344d5dbb3438af010001	\\x574b1baaa37b1e8b4e62a4b9c7bc436ab9d9014f8339ad7c1cc1e5b0f6799709c05e240f28f41de125e75245850df8dff8978969028f78fb671166bdc1cd4207	1673811326000000	1674416126000000	1737488126000000	1832096126000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
117	\\x0dc9ccbabcb895f063a55852ffda47eb57ad3afab794c94112f36ee80aeb58c47ccd8fe015819e409301c4b3d90fb802b58c72140cab2b01452e07f256297b32	1	0	\\x000000010000000000800003b7b249537fa7276115e91bb6a306c7a129a84d08e0221b36ec10f29b2ef25a3bcab88515b642e634122369fe91ecbb4825025eff875f6cc4a6423e4e39201e90e80251cf36c326c2db3c01f24f486a494c5a85341901cd633edb95a688766cf2272819e47328aee413bcbb63c09555a35f0bfc53c73d2c391360457a2b17a537010001	\\xc3a35cc0a4cfd20084b2bc9cb969a9d127e7af5fcb7c6c77abaab3bdd1d61ac5b2fb7257a87d1f64d5eb16d9f815a6e17d1b3e3b8e796128eefd8240d52e8805	1680460826000000	1681065626000000	1744137626000000	1838745626000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
118	\\x1149a0d0d4469f47b8d07ae6e70fe129819134cf3c548340be47802a0086fd0b9cc9bb607f28d3e12ed1da6c21e2b59dd5488b23879c245b98980edd0943d65e	1	0	\\x000000010000000000800003b1f6c8bb542b6be480a88cc232c9dfd9d35ffff8d977d520b6116d589edb352fdee07d76576664f947f81c44cb7caf4969820851c9c03d68c183f6d55beb5666f3a31a6ccec739fca0b91a8afbf4c65c927c580acc83b1eb84d963f2d690a1d2d96b654266db9e2676f136ca05279abcb65611f111705a3af940b9348283801f010001	\\xe35b881b2b0a7240f64a30438efad1c5467f431efd3e957127db0d01dc34c2c91ee4e76cd035503daa8c43bee2133a33604c8a477c8ac1e1e94e3a59880f0a0b	1684692326000000	1685297126000000	1748369126000000	1842977126000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
119	\\x12057f36d4d14df27201930aa2c6a02c85a5f7683525703dfc9da6c767eb12d24edea909299d47d520eb02dc37a47cd2e9b68c57f1426e942aec43d7fb922fc4	1	0	\\x000000010000000000800003e375495569b3517dad801b7401b7a4a2e3a77e35bbeae89080bdd6da7bad26ef459f6df8c5050aaa3d49afdf5468d0b24bd71df5c80255a9bf273d8fd2c7e71de089db0e256a29d3d701b9c9a90331c538f4fdc418272a241230873faab136caddf324c7ea84fbff1f8db649e22d8cd6f0a2d8c85f0b7ca3ad252841c121f7a5010001	\\xcd205d8030535f62bb3471a5b1351eea83121edf297d48cbbe49b2626c087bfadbe1000c44b99bc18d401677f252e64f512016dd741a76850a110b88b5282800	1670788826000000	1671393626000000	1734465626000000	1829073626000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
120	\\x12950704be99f62d36b290c662400e52d11cf153e399d86f3e8150af9b77c61c3e1ee7960fd2586c430eaa42acc85db71e91f6d22da4cd5689b887778d166ab0	1	0	\\x000000010000000000800003a97faf10a34c6d557fb559bba7c5215a78e63082fc07ce47b1c992d4d9e2e4dc1e15c50e73bb10cb276e7fb293ce7e19e7e4c2e309048c200903e83e720effb44a729d569dac87c266160cf5a52363efc5dc6a82361a693edb5be1b285df53f2edae6070864a77f2cc5c1bba0d548cddaaf481e08997740654e651774a49905f010001	\\x853fdabef61a4ae9cb246d9b755c69d365b00a31a8fcc2dac987dc8ef6c3afb9e4fce049e2be5e0cb6f17895a16170cbfe2b6b68e299f503dd0f60fc7f0c2f02	1680460826000000	1681065626000000	1744137626000000	1838745626000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
121	\\x18113b7c27faac9d8776c9c4be04e6efedfc71215fa29cc2b7c5fa9b169d5f361a998f178894cb9f5230e8130518a0151246331556abac6b8198cc550ba8aaef	1	0	\\x000000010000000000800003b957928492133393370b8d397b14bce543c9c773f10877a89a72fe579510b80567d9bd64b8601c974e5396eb4c4042bec68b1b3ff75847be7456dd1e1474c88ce941d5e810db93bde5b47b9853600aa3a0a3c3fb35d004abc9f355a21fe1c81d4268c30ec823df82624b6307e42466caf64c4a740d3855623f2b0dc73b661eaf010001	\\x37ce0101fbb86e7e36cf625876b68d646a669a74e4743342b04f8ac2a74d9e56c6d59bb3c23566ad84f0a931f59b5e7291037fd8e1364572cd0da39bde4ab40a	1688319326000000	1688924126000000	1751996126000000	1846604126000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
122	\\x1bb95ac23721999ebb45723f8afa8a22b7d0fa45fe30ac58ebc65e8d9f353aafdb711fa1e013a305669f48c40af5d6ccb21de5d6c40b25a74d76b951f252fc55	1	0	\\x000000010000000000800003e5742a33deb4022b5f81fb4d50efddd6c68aacd969f6f63c843155a872607fee0240b0747dab7ae1ba3d19ed9d3f93b3821f2d4e578b5c4d943251adaea90d879319283556a4b51e478dd6d614ef155ddffea3259c00bea37ca3bca052c193c39717c57945ef42f784285ae9ec7ef5064f14408943ad64761fd7236f9a25ca15010001	\\x38581018833ee5800a1a7a5b11f04fccb06cc185130b6eae4bc4eb5ba4483f4bf243706201a9e6af28436ec01699b94b50457f5ea3a60d398107a7d6dc76c705	1661721326000000	1662326126000000	1725398126000000	1820006126000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
123	\\x1bf1ebc1fbde76b24e565b7a6f39a43909d1484fe447f5a007bd9d0ffd2dbe24d52810acbf89cf929688fe97792ff9908d35c7095d05b5332c83b423e6b0e1dc	1	0	\\x000000010000000000800003d2051d09b0b70fa5290df8dc96c2bcb938bdc848661e4a52c005ffe3ef7c5230239d7d4de3443ab562cc87c8e2b7545740b6cbe3d672ff88da8c1b337de1d2f1bf85aa6dd2cc4ca768a1bd4db9d4a55954d3f4b3a0070bf6d3e5dfb46628977f7a470f1546b6ef0f7ea3337292c3fb7646dba033d00c674cebef95a96d19695b010001	\\x5075c93a2988bf1e5564d48b706a07d6e94b70100f6c2173fb53d4be25b576521cf95dd38262a69ff66cb0c278b4937f029464498414c7ef889b486869a39609	1684692326000000	1685297126000000	1748369126000000	1842977126000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
124	\\x1ce59a017b3b8165f4887b6bac3a71222edf143af65f85f4eb6d7926deeb03bfcac280ec6a91af6c2f77d430b24269e675f60bac27d75eec44c33ffee81d89d4	1	0	\\x000000010000000000800003c1f053985fe58f27a1f431182314aa06dd3b35c2edf4f976ab6f1df8115a623974a1956073aaf2effd2f4e3176bb1538b2923845f1aae2e1638d32c48655a2e11f502d9972d673a0061adb3ffcb5a5cacadd65666ff88e11c08dcb6ae88e3374904d2b3ed1c7b4047ad20d41599cfe7222a01cc8e4a4fe6bba0b9018925f694b010001	\\x2e5e566e279032f763ec82b169816f85bd1bc1f66f18cccb6df1617191d3549562ee19f9be3bde5a5c7abc1a774038bb1ed7673670fe020918d4ae4ffe8e1c0f	1666557326000000	1667162126000000	1730234126000000	1824842126000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
125	\\x1f45234c3120fc39778d765c46450623a7775105af6c653c422af897af7982661b611778ac6135388fbc2808cc438f5e1ace70947b971010acffa7cdbc87f7be	1	0	\\x000000010000000000800003dcedb7549fd90fb3afef1f78f7a0ae799859b8f011a0f0a6d85f359787423dc5744102bd4d847780bb8f3683c124f065c40cfa6c42bfb6df142f13b37f97ee2044994c1aaae109743942ddc4c70472a0456ecc56d1c43dd8a7bbff5cd7647ff824fa921667e272bd5ad5ecfdca1da6feb3ec74659f8e866895993185a428be29010001	\\x2dcd2ae67602c02fd66db9271c2fa091b831ffca0d0a147093b7aa4bdf7df74489eda0e2d3fde8da1426a491683eb781759c485967095ff4a6a44d9b3d4b3108	1670788826000000	1671393626000000	1734465626000000	1829073626000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
126	\\x216d1f82bfc2e07af383e9fe24981c94048d961d6161ee0c501923c3010b5f2be7872a326842847eacab86b7ef557f23cb49df218fd1df8f05bffee87a7d20aa	1	0	\\x000000010000000000800003a01231b6f21ac9e4282fe0bb9678b605cac9176ddad8a3823866f0121066c023bf6d9c78c0cf04ae1fa02c84766ece03ff1a08f94581e6d77a9202ed6deb650d43663f3d90cb9c1a7334c73e54e3a9acefdef2358ce6771603c755e959d3d96cc73bdc3c5cbb027e12c20c2c4ef19b9b28310b477c61cade99f3364a2cb97bcb010001	\\x9fccd59f3b651c1e6afd3b0251124e7b61e74d7bfd65ede5c4eb3708bcd2ac4570460e554047610cbe932bf552e400237e9ce116cd6b8794ac8cb7fef328b800	1685296826000000	1685901626000000	1748973626000000	1843581626000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
127	\\x2261dcb90ddec87d2c0d282515758b0fef758a33258b42a2ec094c65dca57a3e58d6b0a3522a0c7d525f3a22a5716b7a1d83475d908a3198e4808d7cda5dc5bf	1	0	\\x000000010000000000800003aced7e6e7c5fcd02d8c65b71023b1f13cdd25791ec3e79e8873139cc44303d25ed08d3cb50dc000776833cdd9b5f8f14dfcf027b3badc5d0077fa55fe26844baced09d6bf95517c85217f84eb931051de02f69c3c2bc4ec5418a41bab552b2f6c53a3e5f5fc2dc052cf3d7dd753ca8b77e54c6baa28f3d2ee9483f1a8605f90d010001	\\x75a9797929511eede373cdb10979af2914a31c55293ef041ba1e4af3e2119c480226221d9bb5c0b98ba8daa066d9002bc792dc351c57cbcc91a9ab74a2acee07	1682878826000000	1683483626000000	1746555626000000	1841163626000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
128	\\x241da57155eeb17ced9508e9ff26ab247c38c5e11823d5cbabba49276a602bcd5ef833e21e8cf3c6ef221962b480a3568dc09425db983a4cdb5975fe6d6d40d9	1	0	\\x000000010000000000800003c648a6a2d66aa79b60445b5c56bdf464914f8942eca9210bf3f11321728bf40dfbfb8f2e5c4e7fc0b11482d0d8c3587ccb0a2d997ff1713d41360669efe55cbe64ec371364df8514478bf305afdabe845a81d7fab7afe3107b802fc9eea77a0a520e8d1ed834178e94c6b94139608a897047325d26941c45fdbb274af699af9d010001	\\x5a155730531bc2901da798c2bf0e439dc80d3ebe6ab5ce3266d1013213510eafa4101bea3a227f1bd65670810d2af375462844ab18a0f4ff58e6d8fac49dbe03	1685901326000000	1686506126000000	1749578126000000	1844186126000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
129	\\x276905c0bbe6547f55d56935c0345f2e730d7290509f2fc448b0f78a81dbceeb8e346ff3432ceb6d3b9aee641445ff4ec064326c001fe1969ea28a1245631cd1	1	0	\\x000000010000000000800003cbdeea2a2cb33d23d86c46497becfb08f5803306cdfc58338d3386874080851d3e8e9bf009c2193b6028e5879273ac469ee92fb70d9feeb03711d3f2112378a7618c4815703d51b2b82d2059d33fc5765c4ab4dc75bd7bb2678865c4e18cdab9ab51a3a67f34568d457b8335e060a7d0489de0fcf74478116ed73eb26214d38f010001	\\x02792c45bffe429f8d5cbe3b195804c8dbd1976f47a3d8c4d9329ea89b4480912896177961d688cd9fefd809b18c6ddb49e71f99d70e54d1bf221c4825c1f50c	1665952826000000	1666557626000000	1729629626000000	1824237626000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
130	\\x28b135e3df3b339ae5e833369314793521dfd4983dc0418dfb8ff9457fae828a82adeeca47d35c3f437578b932df5c03846925c5c443cf9b505fb5683032475f	1	0	\\x000000010000000000800003b5cb0db7d79a48ee94ff9b860cbc7397083a0af45f33f3e2455a968aa123038d91cd97dea649da335496f17efc0f0a8d6a54a65492807741825d2f7f9b1d001862a2a0baab35aeda7db2f650ad1fafa59f6b802bc76e741113730d286df3e7d729edb3bb28f139176ec7beda5e963e23c8cd4f3bb6f23b7792c6a51e069f6891010001	\\x82baca1cd8ba21e4784d6364dc20b4c0f2127f903f2d74c5d03d2b0354a493ad353b2a9c17cbc9022ebe2fe5c1d109f001165699da6c656286bec492c5167605	1660512326000000	1661117126000000	1724189126000000	1818797126000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
131	\\x2e655f037b124460ed72a270f0340cc6e4b303365e53fdefec6c3d339ed59c2c6d9d695b65b70cea06b395906aa3839b315f6c2cec9d2146a3bb253d21c5d4e9	1	0	\\x000000010000000000800003dd0d9225bfa8bb36f9ee1f6ef306c8820aac56606267f188c847792d6d5f05b3774770e5d454d6dd208bdfdfbb0d994b73d2a6390de3fe5caf97446f0fb709c398a491a24d3b08418d8af8668b5638a69025a533caa96a8f0e9fa8fe4fd93de889578b3ccbfb79fb0c459a7b9043b7109f9198dfb020305a6b0f20cb2894bcbd010001	\\x2049f9a65b5fd086cfc2bdf346b1e16345735597a6b00695b3e46d11856076e55ae6b554481c1e961d351eb643bd564b4a72ab014b13125b7f9dee571d6f2405	1678042826000000	1678647626000000	1741719626000000	1836327626000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
132	\\x2ec504c9cafe263cbce818a4e5cb9320138210c764ec68ec079a3d8e4e7b28a6c35bb3fb8ad98f45da68f9ec3637ee33fb5c884a8708963d10925209d8416a33	1	0	\\x000000010000000000800003b3777e0bb23f94679776c1da384b32c502f202c69950711e1cfa871df6fdd4eb1aa5cfbbac055bd65636f6ee68685ae70f8593e86647d0a1e6cadaafe43cda2c50d414da59ade315224a74d057d091485b48177b68ad6d5748fe85191f75d9183b41e35c692a872bd59ab309612ff0682dd6b97ea6530369f753ec162d64e8db010001	\\x208b8d4d0ce91438278d9a27c16bdcc17c3e46365a0aa438a45d1e1c30c6c17a23a3237755a51d5451a01d9a526d07f928bc9f86a7495a25cb6da1bdd3ab2305	1665952826000000	1666557626000000	1729629626000000	1824237626000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
133	\\x34e59b7743be258f7e62592c1b6cccf37d6f867db929475427b655c8d4a3d8af7d52740dc5ada09150897c9087f35902cc60ec69e4013c5a72ba6806eaacf168	1	0	\\x000000010000000000800003f9c18b274e223d1d5da007268403e146315252861c88c0bf9243211aa3df933fe5e75f7b487845332a89fbd9e8cf2719226dd9167c5d65eeb73f495b08b142e906a73c8b490e7dbca1b9e9022734ee62545c4a1593c3bd7832ffcbbbf9baa5b991b49ab4e5b07e524c82d7c597677b3a82193c953f968e04a5a1cff7d19a5f45010001	\\x7bd5e678820e6c603317f1bd6100cb0cc7784979fe0c11a443f2ad0b2f04762d86a729f0f9b62e6996a44cbc791565c4366569d12baae7a3fe4dfd399fd63c09	1684692326000000	1685297126000000	1748369126000000	1842977126000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
134	\\x364dc9f65b232ce52073f560cd7b61b0cf13a6259cdda21da0cfc80198f268a2811a575d5c29ef086f3d30865e4afeb0a5c7a3ed96f9276627eee32fefb0dd74	1	0	\\x000000010000000000800003ab7a0cee4dde1d7d13daff28227adeeab20895f38c27a9cd64f135de34a286fbb344de1c3ada5e7bc2b0052a0bf62a197de22dd3dd2e6a05bee8578239009e45ffae6e035742fce3b96e12b95447b60df27f596aa0d36cd6e979989b1d28dee9a0845203643dceef22fa8929f0d5a8da6043467f832b9e5575920092cda9f95f010001	\\x2d94da41c7c5417728fe57b64a7d76d1d702206a8a5c567b2420536cbc23433b449244caf2464fb4501434c613c7653e504449a6444bfad4b1ad93f84c46d10d	1691341826000000	1691946626000000	1755018626000000	1849626626000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
135	\\x3815eb0c6c45130431c147e610156f314e4482dbc583a39c57033b7f555f0319804e8e7c705ed4a031f050507e25c071bafec9eddc6c2f3e08bf0bbf1e0e87bb	1	0	\\x000000010000000000800003a02ca9479192122d4f75303ff46791d3668d61ff810647c3af506971d75ad6bf79478e1d0b867a70e6dc8c7fe014a9f14ea8f84e6a6c3595d710c12fc727dc9d88c07e64d857dc76cdcd7ebf3ccde6a65da11893e378a0f6a3c1ad200b4bea5aac7f5fb3a17a0a4af7ecf2454fc32c2da9be84bc1120bed4d38853af70766077010001	\\x9d003578e77bcf829c9fa0d21e1fba349c441f740402a17a4d7fd919fa95d0c6b1ce9014527eb18e714b77ffd68d505532619d385897a7116848bdb40d19be05	1672602326000000	1673207126000000	1736279126000000	1830887126000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
136	\\x3905a7726cd72a3ed81a7c53187f4f3b073272ec72429e00e628938939485450b5ec840983adb33e382724c0f708e960d5c1dbf6b07443929468da835845a27f	1	0	\\x000000010000000000800003bef09f988412e94334f5335a85d4c44a23b4ddff8fbeada74b0a569fa01d1de2e3f29dcc766205ddacf7bb216a05505966bc4f60355e03a165b9e8a0b6cb77435348e272b0ee6edfd3b60a8fc317c73691030784cc88ee1eb144bd61f4e79f439f5b6e89d8cd41658ce359655efa28317ae6d33cc84e502f2ef32f5e9ce16867010001	\\x26c81466615759a5b8d78466240951c0b93f55bb932553a82d1d4aa317783d30af6522625629adce5253d6343b9b4b64e3ac2e0ca962e4f79224fa2fbe032909	1691946326000000	1692551126000000	1755623126000000	1850231126000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
137	\\x3905bede28eb4c5ff47cf298c48bee243a416fbb352039c4d95a09bdf3e17b1f587debe958c4d5d46e9e941cad195dba185aff8f1d459639ed4d150adc442b38	1	0	\\x000000010000000000800003d14f60a039190779d668e4dad7cbd49955008b8419544be78ca34da12e7735a3f3147f545027243f447c4d6af81216cabd1d09c77ffb0a2b40b78a03ef557a4dad97cc7e1c9c1179db43012095d1d4768045c2655fdd9fdd17ade620c4e38ef9433eef0de1b522cd1c39c659eaa04d3d01348815462ffe583005afe7de388453010001	\\x6cde41ac8dbb2aa95b8531d278cbe1f010b4fe206fd7a3f99e3842b5df5d43aa91af1a851646c98f533474100c09036406cec496046070228a2b4e4d92d3730d	1668975326000000	1669580126000000	1732652126000000	1827260126000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
138	\\x3d25995462b7b041f1cab35a317cf6b49607c8b864739dffae47aed7fddb9414abbd3a02d7b2917e197b48aec97ecb05e3430178534d5062fe9ea44454b95401	1	0	\\x000000010000000000800003c38fd04cf39be05c3d342d551ecdd860dea2d902db2fbd6d3786289b2e38ab0abc52f68ab9693586fa0478febe79996ec53f8630d5655f2b62f1b7bf85c3231da5eb122bfb569fe59ba207624302b83130b895c335e0599f7655ae2515dc293faddfd5f0029fae3941ff471e4558df211f12d92b343d7f953be4bb477f20a863010001	\\x71aae669a5fbc9211cf4f6f7d53f05f6dcbf545f1c73daaac33971d6412e5cebc8b437e0c58b5ef9ee1edb2c7a7bd058becf7e819da867a6552349772234da05	1686505826000000	1687110626000000	1750182626000000	1844790626000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
139	\\x41c96b0a1c788fc25c670619ef040673b4d95607f4736dbfda08e1fde790b6556e71af4e2b3f5497c5785894a12d6c903af08aadef41d77e421e8b6ffc412bd0	1	0	\\x000000010000000000800003b73b121408398a9cf79a2ac44bf4bd3115663348be0c09346edb389676826c6128959f39168ddfb31382de4272c431d93f99a6593e6538a5fdc4f8f31bb525fa144e2fbdccff07ca8019089efa68e0796019f72e389b88e595f42d0653411832265cb4f58fb138c042cb16235a9ac627bbc5da0cb775b3bc40a9f433ee2088b9010001	\\x9697885c34fc873fff2ac465487bb67b6022521793a3d90193c4da547c9b04dd315b30d5bcf81d058f24ef864a59028e33416053206beab7da9f17ccae1c5704	1662930326000000	1663535126000000	1726607126000000	1821215126000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
140	\\x42bd0c8e4d5037b877ba671ac00cfb71f381be5d9136d0334fc76eef002b378de8c542278c5293e7bb29311a8a5bbe9c6fe2495d3fda99ecfc0cd253306f2cd7	1	0	\\x000000010000000000800003b0a8f7a209a5d60610d623cf39e27158fa3491924d7e599dc5a1e685c98b903ff0356562b7629a82e28821784a581927d91f8c539e5f31d5d3aa1b66ca215b07da30d7306631a851ecd20d78a9ea66314a790b9cc9384b93a0a899919bc77323ce1bcec80e53b09201919496e725136796127e2c4f523406fd3f93efc306f86f010001	\\xffc32f384e2b1a3adf339196cf58b980df2c417be54095386c7a297f0bd1652490234030905b9665a5656fbcf5a0687545b14d01808217bc8e9c2a9dc2602c04	1678042826000000	1678647626000000	1741719626000000	1836327626000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
141	\\x441d88b4f483242994ca8ed4bdc10daede413003005a69fe39d1b18bf564406e05fe58a1e5b7304d83d4ac454be575f026bb09350089d9e689787d6486d21751	1	0	\\x000000010000000000800003bacd62194b532e1acf13cc914cd2db6366c5d180f36c5baa4620396e98b59749067cb7eda79ed0f98deaf0fbb25b9b8b6e679281ae7f1f9fc07f7f6e51c3279fee7e6b0c98137bf10ba6c3e13a55c1035bba33b219b525b3b99923a62ff4db3b5bfb9f92aa668fa305c8788534c728f77173c57ddd9670ca31b9c96f8a0713a3010001	\\x5f6acbf0e833ae6300bbac3207f2e4754de18c0ab6040148a54ea0b8b2dcd01ff2f088cff244df66416bd309f35fee2b68f508295218510014f1e97580803c01	1667161826000000	1667766626000000	1730838626000000	1825446626000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
142	\\x45d907a991ee4c16b8cf4a0862fc6be3fac609a63f761d9d3f6ebe66d57766b6aaac3587050a0bb4ec847043f8b5a8ca893aa2a5bd5933dd0d85621b2cac0f6f	1	0	\\x000000010000000000800003cfbb1e298e7f3e061769dd63238e86e7a3ef8f8d5d50da247f13a16109005354a06ced85bc1c8179177dcf2ee5fdb6fc067a465fbbd2dafac7ce49f9552e28b2b0041b68c3b9fa053adc54ca38eab57367aa53eaf990c73d9c14e67cd4e5b31b57df478e68cdb31e88c7c4561da2c778be4b2f495705edc1e8ff4dae72742c3b010001	\\x73b9057a53f91d9470d82f02dfd9ce525e04807dd50f9d5af405b15794958422c5a2193752fad89175159536de301aaa6e5f4d3816be43004682a7aff6b40209	1667161826000000	1667766626000000	1730838626000000	1825446626000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
143	\\x48392d0d2308d98568ad220b9c9fa4c81a7e3ee9ce97ded57a700ee306a48482b8724756730a12320a342b2ff020c6709206d9a70dccefc79a735da44b9dd0a1	1	0	\\x000000010000000000800003cfb7f888c2d3d9331aed7643d25215ad2e140216c2fd38fe297c067bc8f92831d173e3cbc69f07ce7e5052121cf53fef74e073e76c8432c42609e815e9611ebc84a99e585cc3b049c0aaeef484451f177fd7dece7a1d5d768b8f24605365639a3a7fa1c2dc18ed41b0883458a60502a7830700a99ab1519ae2d22b9013dfb167010001	\\xf6a98be92d9f733df149e96c11d0983a84e4cecaf60069aab66e06d4d6e148ed1cfb3150aef9dfba3ceb37131ee4d7e5c998014d575f1cc0eca1c48ab388b507	1670184326000000	1670789126000000	1733861126000000	1828469126000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
144	\\x4ff9149d9dfd7eed85823f1a9aece37b2e0b4e3d7556b418882a3d2e555cd6a5544c658efcc783d750df2e2c77d61c15c211d50acbe429b4ffd02b0ef90861fb	1	0	\\x000000010000000000800003b5fc8e6dcaee89cfabce7d422dd563bf74a57bc1f19785db6e56e9913d1aadb9d22f7bfbc599a62a22fc7bdf3372facddc805a726c5dd582eb4316ef121e1e3b85cc5b313c04808a4f6a2168fc33e3115680602e00a887fbf49b87a623f89750d915a3b98d88da6d57896f442c7b091944cd10118eed2d83d7e8a5a5ba9644db010001	\\xd1a9c55245c29e3d564dea30e6cdb2056a21c6a812de4832612eb275064c91aba95631dae9142401143a5014a563998e6ea67697d7f37c105acb931189064602	1662930326000000	1663535126000000	1726607126000000	1821215126000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
145	\\x50e5f375f3ce2cbd19cdf5d387a8a600c9e70ea0eff83d2a1471ac32cdb7507b7fab847abea03eee9adef6e352d951fcea07e0500afe34cdd16828489ed2c5b2	1	0	\\x000000010000000000800003bae2a332ed7a092c526fc738400f509af457feebb6ca904f188168edb8d7e36c98a415165499ab0e8f1bb59426266be6a1ab6d2f82f6e1b1b9f207ed35705f91e414ddf1a5a8b2f9a3a80c9b8979d1a444f1108421b2e0f0e83a88519a1641acabbeef666c4fe898f3b0644f46324f006c3492a84532e176ac55f19e7d676699010001	\\x0f2e42ffab4548ad7988ef671e4150ff410e6f713e1a36ab68c8f433880f89fb798cc0791764de751fe108c4ba41aa734224e440d39c086a609f748bd07ad500	1670184326000000	1670789126000000	1733861126000000	1828469126000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
146	\\x506d031e79690d37bea09f7b70dc29652c4cb256f12263cd06b7ae424e49a3372db70093dfaa77fe0e48f05a006be116ec65ae045773652c0f6a57df467722b3	1	0	\\x000000010000000000800003a1b5a1bdbad1c993b4a75180cc43c6c7a182cfd98b718221cf18ba6042df6c25972bd9e0241558dfb2fffff6d62a4797f4c08da77335107c981dc0e8416db159f78b155e640deac5571c4dc87fc14590d9f561f589d91d3a97e3b3e81234ab3600be184a4dae69e2a2208470d1f2282395d52fffcc38e07b6723ff26b32fde75010001	\\xfffbe5936ff88a8d1d95b06832c604e2e59d1828f75016e9ad5f6ce2f79a624df9b073b7b8ba7423061ed791294f8b42d7175d7bac4d4b2714209253842e5506	1661721326000000	1662326126000000	1725398126000000	1820006126000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
147	\\x5185ed14bea36c2c6b44eb592057448def741ea1cbb3996c3067e45db73b5c499ee100504a1f4e113ff308fd97ac6c51d9bf375d6694c5b0bb478f3f558ee6c5	1	0	\\x000000010000000000800003df78100b115237d9cd5976316e18479de3e991c468437022d38cda7776589289d65a1a96a586622b83eb7b098c6a9f576e3f2f6e4b6b85bbea0abfbb94949886ae5a5b3ae27e90770e5016dea3948effaf38e50be85c4fc34baa6388ed704f1f247110dff3343007623f22c5ac5d0f0daa8e0d505c32d3f11ab70b3dac680a15010001	\\xc33ef1aaae62fe0324b0d79341e2e6ff44fef4a462abb6936c0d8a7b30c5493deed0dd065e5dc390ed8365961149dec972f276b5b7f8a1e7eed98e4edc87300b	1667766326000000	1668371126000000	1731443126000000	1826051126000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
148	\\x51798ff6fbfb08bb6bb387a62b668ecfe9dfc15ffcfab5db5ed663a737448d811c1fbdea98591324151a638694bc9231014c4459a11e55e011a019f6c0306690	1	0	\\x000000010000000000800003ccd20810c9ebca239449102b3761bd84243b31d359f34585492b145dea4368288d291739cd6006bd056ef643c9a2352045b87ad06f9beda9a079f0503da36b0954cd44f2cc03758511abb32dcce32a6ec1bd7c714823e06e94640f2f1bc6de76e9284c9bb794308120a7dd089eb3161c263887abc78eb9c870ba7eef7d9f9c95010001	\\xcba9ba574308994abb78d48928eb37e9a6a1e9a1b9e21ed29fddcbd2cc2a268876b5e1ffe52a3579cdb56dc2f1e1e88ec6a953ddc06bdf4292b58cb20abc4a08	1676229326000000	1676834126000000	1739906126000000	1834514126000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
149	\\x51ed8787c49b4744fdb2dab3636dd396ad11be71c36fa8878302dc0dbd596e3789909d80f480d459376b94f7604a78c6d32ee73850824f56c870c057dae22205	1	0	\\x000000010000000000800003df4047d4fc36db8347a40020c135bb3551dfc92978352a444c81c729cf63e4f4053e6b4954de2a5fd732143318b855a4047e3a77b169d62e88c93a9358bec128ddd081e085264977a262820b60f4bec7f50ff908e2c8676990c112cd3b0c70e68e5237cf076389f250881666f6c53009615094d515e5c2b9eaa455128afb79bb010001	\\x48a61c4131aaae1899a9adb414c03679cd2aed6d990edc306c446fc61a017c37ba6cf13946f3c9e1b3bff695cbcf6f0a01588f626072a99c6ef86ef39885ff0f	1678042826000000	1678647626000000	1741719626000000	1836327626000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
150	\\x54850e841d809318eae3e35357a36a3d60f4f5474ee14642a2a0feedabc5767774ce3cbd24f8d4182e4611feb9d8e4c21cac464d0d02d5663e9c113fba76e3f0	1	0	\\x000000010000000000800003ad162e3094f678ad44a21e7e75b134d4a91e031098c005bc431b90f6a00159e0fa7024af0a50626c87fc775828eec3062af7a4aff20e3e5cfeb52d40a2c9af58766c9549c963965c045a7fc64f5d131b4edb12779cf599135bc7994b25890fc39abc3bfa82e002d1c9c4880d4d1d849adc8cd657f467a9d818008441d8a5b90f010001	\\x5cc04d02a6bca2b6b0c6c1830c1579c695c377317039067da28d9dcd3c84cfeafcfd422a02d1f95e1e318f42db851baa7b58280834eddcb234f801e629934e0f	1661116826000000	1661721626000000	1724793626000000	1819401626000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
151	\\x543947e783a9b2c4767a35fd53836e0417040ccec0714131cd48cfd3e3b70c5119574f7fd1619d0284e217e1788e1cb94022b040de23e629391f2e6e10367708	1	0	\\x000000010000000000800003b306e18e5e12e780fa581b64cd6d514e90b121c0c5e627476af642f28470b768e49b63f10f6b227a01733507e0e604af84705d95ce30a40061195e1e96ae487d397138f4c927cb576f36ff16b8ff54c980e47d1f9d1ac494b59a9ba2f43f9a47feedf8d6e46de8046d71677d74681eb17c223073313c7b2940d6f5006bc3df6f010001	\\x1c8b129330b5ee2b93208a290826d765ded7efab9aad503e0f2960379ff032524dc2057cc8d3e11bff831c8cd0d268dcb7aed54098d0b1ede0487ad939e4af06	1675624826000000	1676229626000000	1739301626000000	1833909626000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
152	\\x59719f10cbc3cd67c0f1dc596ea0964d321580c5b9609910da67866b657e5476130a12993bcd3c92219ff854816a9fb9c3029ec6ae0bf227b05d0a4286d7e32a	1	0	\\x000000010000000000800003b19000bb60efa20748a92149202dad4fd92de3194de32759ca5de75abfbd50f765f395a691dd7878de1a92be7c0a69ca0d497beeccf5c303e75fa11f950e2f25f7cbca3f7e04ae58b6c2926fc8906b99fa3c31fc9f2697984239ab6cebc13a9b2ae8485a78fb8066efa6036ec8f7fff07db159536ffb9f4f85589c78f37a6347010001	\\xbe9288112b85d1583f707543eabb6de3fd4392e359b943217fee432c7d2a55a2f1737aa137f0f9446645494f6eb428f34a5fbd783ca00d09931e64999d23e103	1667161826000000	1667766626000000	1730838626000000	1825446626000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
153	\\x5a6d9ef19f11a03bfb2756c382d83856b37bb28881535c369e354b4724d0905f4a303277d98b6820b83998041a26f203cc5a966e2f66e2e49503dee8fd415550	1	0	\\x000000010000000000800003b6ce4a45ca5e29fb549c119ab76d879e5cc4f70a50a746d4825400f886ab9826e3e2422b2152ec5bb9ea2d4731002cbd8864b602131ad70a49e690fd908a89d61d4ec5c247479bfa60b9197556617460e1692e760515f6b1eba3122253fe5c7c84b5c04676a97a965cb86533ff0424d9b4b7c646236f2185967e631b92c7e637010001	\\xc61fb8912541b744dac89f05b10b6e944485aa31f2d0a4c068440ae48a33d04ba59b48150348311ca4e2b55224638d36acfef791958db6160bad07b4df49f10d	1679251826000000	1679856626000000	1742928626000000	1837536626000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
154	\\x5a25c4de59c75a28108ab62fc252f106c5d1bbd7ce06ff45537d65aedf363d471f1e36689096ec7f6a0c0f4361e4e2355d1671788f968cb3d13b9b6c58bbb178	1	0	\\x0000000100000000008000039d401ba02b0d5e23911bb439dc4d9828674b66fcd3e3679af6f64b3646a2a7bcc7afb079ad065b9e3c524c152fe834cea0c24a56cbf68e3842b11977bcaf0c5e244824f8fc073266c6031a5633f97a9cc3e8a5668ce10e13e08c0d1abadeed31c95b7e4238716859f97f9a0a5fdde30ed7312966297357ddd9b1040676c21b97010001	\\x9ec0866688d21f9cc9cd7763a493114a617c98b11f56152f2c7047a299448d45ccc358b0bbeec19b65cf4109966f0468da5ad0a15f93f34c6faedf79eab74f0e	1683483326000000	1684088126000000	1747160126000000	1841768126000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
155	\\x5b4da2e20bb77203e0171e2b014bbf6ee8a71d7bbe005cdd91e7d393122e21bd2b243cd9872b66c59f5ccb4ebc83ae22d1d8c357dfcb501641a4adfc5d528e51	1	0	\\x000000010000000000800003b6611ef6d645adb928a079b8ad8e156a773f1d4dbf33e932d20308c886ad919772ef30e062999d31cee126331154919ea4daba255f9698ec5e489d248117eec6910c12c5d841255821b4d7a37b45d79d5f1004d7d67dd308e7d9032f927cafc6f6ae46e0f3e34042d5ebeeb0719982a73db7c7dd32127754b6af298aae51bc49010001	\\x2311db4b9a728949903a60bb65aef5bc4e9da8e331f8e94b8acb916cf7636842e0a4976dd8f278dfebf94b4ab9f311eea132fa7708a86f456e1571d1af57d70d	1668975326000000	1669580126000000	1732652126000000	1827260126000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
156	\\x61b10bdbddb12ad34bfdae9e892a5663be049479f505574c8080483a5021d84cfe573e7f20e82ecaf6578156f5908e2f9dd412e23f5756b1ef19ab54e1e497f0	1	0	\\x000000010000000000800003be34c9c5c74f4e85da1a89d279608576f528ed48db8cc72cc0e2bc50738070eef018f2f29a3e99c08eb399271823f45277ea74141c87f81c75364337fb356cfb87e4ab6b574db8ee73c5c5fc4951ddb3c73025df75648d4dc6fd09a994f8e85b957e7b18007eb3d79955e91056a6d85c59ce51575d8a0d81ce143c324ccaed7d010001	\\x92671309c63fc2e25214c9ca268964483172ffed4e834ce7b3bc726bebdb59675b458035435febcfa10a19483701b02a89a5abaa75104425931b77f600b84400	1684087826000000	1684692626000000	1747764626000000	1842372626000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
157	\\x63e5ae9ce7947a3f3965e65009eae2f4f7a5231537cdbe12523dce10f4ca36f4d91aef714a102a3b3d2f7c48b39ff7b2d5e4e703b26f261c1e6f9adb3635b9d9	1	0	\\x000000010000000000800003d67a80d9e76af77c798ce739c8ad155c0441a81d41720d8f2b31ae1bb3461831f252347a9402b836098f32d56b44e2e7672a67e05c80621649aa8c83ec3e39a732315785b996ac1c7de27ffc42d08293eceaae2e7c8c40593a620a88b50f2e713e945d799c8604c135b5b03bdd2b77b8a5523c0c3a1958f13fdc04917bda9f6b010001	\\xfb5848fecdc1af476c6a8975b4cf18c0e4e880eee0b6343ef2c905032163cc68393a209e2c4b7a329020f991870d17cd1ce24d5a91b09b0f272575151ac3f307	1670788826000000	1671393626000000	1734465626000000	1829073626000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
158	\\x643d1873f64aab2929afc5315b2bde61f40b47c7f362115840f6161f4922ff119a61c4af62b66ccd46489f488cff721c8fc3c8a38db52148cd624671f86270dc	1	0	\\x000000010000000000800003b7febc3b08f4801768dc5efd67413c48add178e44fd2698e5075da733808c2af2bc189cd1159b0a5b564148be4185ef1b4592b6f625099e9f95d4363f8fc55d775740228a47edeabde5bbc1d020359de5ce67a5c0dcc85dbf2b92151203f1779f47ca16543e7945fd766b597d3fdda7bf07e4fd3d49eedafc6f3e820349bff95010001	\\x41f88c349e3bec7a007da3ab467867f4737170578089e10ffc59afa3c2ab8a1c5afec5445b9980d3ba2c4d66b0e75f477830e21ef795aeeec32e65c77260d80b	1665348326000000	1665953126000000	1729025126000000	1823633126000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
159	\\x6589511214cd15dead61cb10b3d9e0b39c175ac3e6a32610e60352c17272c250a15046336289016de179f8341328bb8bf50435f23171d817eda1ad3647c52dcc	1	0	\\x000000010000000000800003e88983848e9be88bcd2db2e9297398a2ac48d2910cf91d1288c47234869eb79b4fa384e24e82ee627a0c53382453a4654cdf42ba2edc9893885addcc0ce36758939cb60089c64980ccb8a61ae574de6cc81153e6a3d52a353db0d6648aa21b4233ee98fc32e05432757662d979f1e9bec20427f1ba5dd2e25aee2070aeb940af010001	\\x73072deb21b9141323b0ea23a4a790207406da7bab064c41bae4b6947d6791568736a16c5797a00ddd8d127c4f6d7370e224a0aafaee8211472149afcd21cd0d	1679251826000000	1679856626000000	1742928626000000	1837536626000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
160	\\x6579d1dd1a3cca80630842086db4eb10e22931a48b1ea806a1e6b4f5d7e3022165687a68f9c4fc8b32a34c59ddf38d00717cf989f4da140c76855a2be83fd8f2	1	0	\\x000000010000000000800003be04e6a2f49c8071f8078de242c1eef601a36f5aa7c771c0836f16fe297cf38683d5751725e032dce7a522ffe24af8f29d1d00107004f12185e455eb6d35579f041b515e66ba3335d6582e6da4b7f9196f1be36a3364615e18abb78478b0512503df8db7f5e30d35a54b32e6e554f71cdb1d17f85de1ba773e7d32e6dfb0fb27010001	\\x720802b7abd6a78729cb57d4828a97ec710e14245d6188693f8f727a8a6383278227f1239f7c06ffcfb0029142d706035f655d40e546e70e28c9a70af8879b0e	1664139326000000	1664744126000000	1727816126000000	1822424126000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
161	\\x688d00520bf33e90e1cf28a6100b1334fd4bb262fd609b565d276ba90f6beca45eee4e9ed2928cb8b3740fe9d35d0aaaea131a2c5538d562b354d1de51df29b9	1	0	\\x000000010000000000800003bc0eee291c3f7cdb91fbbe24d587129294e67882b3ee9101c9cb0b4084169001595d4aaceda7271a38289442f0919faa1acc6c03ca461e68d5898406a4f4f32719f106b1fea953869462bb7fb82c5512c1d0a2ef1a6d3711bc02326f2e057cdcec35ffb71f470ba97ec649f127c15c02c1c8d4c6c61009bc00a78cc7f32fe55d010001	\\x73f7a0d3dddfa426a15e4de5305b72379b61b1b9615bc148ead4b2aa22c54a0227bf2b3622eba7f6a205be4114dfa9b860007db34000b2afb7e5701636afd305	1685901326000000	1686506126000000	1749578126000000	1844186126000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
162	\\x681d56176a0746e965c7191ea03becac0c4cae378de9a6ad09aae244c92e7c1d563efe6f8bde7c57329a6c1c54d15ccc4ad23993556edb178c2deeffeaac800e	1	0	\\x000000010000000000800003c47e768855e4f52f1ec75d28b8ab3a9f8e5e47fa9531f97a14f59cd921a8fd3a9740050e1cd9e826a600f0741abcad74c6c8ee304f11a26554e85e6e686313321bb0414000ff198b04a93c8fa39264621487f3f75b44e5fbfd7eb0b038e96ee6ca3ae91216c6ea332d98d0b2eebcb95663a1193dd43a2827453f1d438bdcfc49010001	\\x6ee9ce1200b59a1517bd6fbe0012ba6eb086ed00f474cb4625edfcdeb10cc8305260e810f9b5d9c2983f8a38ef03e908270f39ba287ec8f050ea5181f41e0606	1689528326000000	1690133126000000	1753205126000000	1847813126000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
163	\\x6979a92d25799a7d9a5d4344174099694c7a23cca7db7e9c8c5e706ff8b00a9e690315012c2ad42cd717f78c2a78ddcd86437e03202619c901ff292b5055b19c	1	0	\\x000000010000000000800003d3ebf168a9d4a98042266f26f18fdeb8f691cbd2459c090de9bfb14d40acc01fae94ea8c60f486cf7048054132bebf7a0769dc6460c0d8559ce7ef22d1b364e70cbda640a17e8c7496d8b6577abe482ec6e27df68cc5911db6f13b3d6f2fbb06a5060dfe9d5fc675f5a6bf53d41f7e1fb0afb2e0d4ada28792a629dd84f4fe65010001	\\x4778577cda7e385a13f69902684ed016dc2f6b0fdbf89d99ad90e878cf2c2c238edf12cda5720a2c2f756b8975e50ff81c3398e76152afe8a1c45db782499700	1687110326000000	1687715126000000	1750787126000000	1845395126000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
164	\\x69b94d964a35aa67df7cf9e9ac69853d59adb4d5b2b6a152bf6108136f9e23119935212bc13734ad6542758b40519c2fd2816f847075e8c56978215bc1d86ea5	1	0	\\x000000010000000000800003f097168308b580f2c91528819875d13b57a2cf7b610ef1c5e2744acfd36164fd3b1b57c6a57f3ac27abce71e0ddbf0edb0157b1b178fa1dd9a3e960ab3a8740c84e278a7a385cca3e7384c48c422c51131a18b1a483c88de38efb53875c37c98b75ca93b5f9f3dbedcdf07c01a897fd24d6465e223102a92c3d349ed2c7127ed010001	\\x0729b25771bae988ec89f83d3712b54b24f4fa61146c6db1a15b4566e1ffcad9980ab7e15d679f5eb83585d09a7dce9de60703b13c9607f170653e77bf9d160d	1662930326000000	1663535126000000	1726607126000000	1821215126000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
165	\\x6ac90ebeca7c131d3e8cb043747f6b34252c3dd06057b175147015d0830f0339d18ca1a3f5fc0607250d5f2540072b1ae7a82e5fd3cb4c53e7eabb2674c4ee09	1	0	\\x0000000100000000008000039458042d64b3b053418c2857839dfe96247d1337ce43943ae5b3f85f961364a5618ca5e3ef559d0be79a142ccca3e23a412d96d503e9e86d41e22de12c8b971e3f32746d2aecc46527bbf249589962e0b2dd6e69c020d43b0faf2a8c24504a7daf4f98aba849525517287bb2a7459b0f8b7eedb0e007faebc6fc4defdc02fe01010001	\\xf7d7f0101b8b09892832a5bbf3408495a291c22c1c7a1a32126c5d39ba7bdf97a839bef84c14c59b3fb77715b8a4f9a9d2ab76c284972bb2f962f179f856df08	1689528326000000	1690133126000000	1753205126000000	1847813126000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
166	\\x6a79b3eaca6d7067fa0571e34c54ca84d64dbcaef5f14c0ae8b883b44ba24a5ad7c0de83242819b4e28d595dd2f8b8fb51006732e750e1b5934fb07a0471787d	1	0	\\x000000010000000000800003c316cb83052041c194ade12b3922e3bfa3f7607bd7d38b10393067b1957f65fe8ab7f737519a8389e9ea2a844d1293f82eca40cb83fa0df1a48046b786f34620e37452263da417fcc2d1c8b6732f2475f601ef6f952c8e4e23eeca51151c1a336f09aeccc52770f6bb11e0db404beb80c505bda4e473ef40d3bead3d9c38227d010001	\\xdc6ecb6e5c1daf1d38a26f6b439dfadd44d7b290dcf3aa251e81a0eb3ab4a8554ef9ab0fa5f90c522aec66f50b860b2791e45e56bb3f737d0ba9fc678eb59f07	1669579826000000	1670184626000000	1733256626000000	1827864626000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
167	\\x6c398758967b96b2d19393656a283cd4383918f0525a785c43c55d5a01c19e88e5efc26947aaac4852ed2324e46344db462544ed850f86cdcaa9313f3d0dd2f3	1	0	\\x000000010000000000800003b3c763d3b76374db6ddb0fef4235390d519f19954d456dad2b9c1485376e9939aad6b401e958e41b044f456870eb708b0d761c27089d2739e776b6a58a6d0abe033d93995087925fea2f2ac2890d6341408c447ffddeaabf7ab84afeabdc7f0d1300991be3818244dd78804497399f541837f52cbbd6fa8dc7eedb9c7c40abdb010001	\\x06b9feca29972cf2101bc5e9496cfbeb33d10f2cdeb68e7461ac30398aab97af45688c92609bf233fd1ee424cd228c3c3eaa153720630a2dfcaeb705619a4b08	1685296826000000	1685901626000000	1748973626000000	1843581626000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
168	\\x787d744bf7b8ede9673ddbcbba3744a01cfd78e710e1346f4e815d2e83f32fa584f01e31fce42d418209c1e4b0e01bce17f33cc80422b57774ce846b7a14c42a	1	0	\\x000000010000000000800003e1abbb945b412476f598298fe7cda306ae72c277b2e7286d6908987f1cb3716f156268e88a2ccd6de76791a2afb692023e002dc96676dd85963c8ccaeaf4f733f8b33f4dbf2ecf31f6ca3e8571c66916105965b29f8ce831c15427495df739d0a0ddea243628601ef8099a51a30e98452f411628be9bd95622daae3c4ca618ed010001	\\x539199c72e7cf4c39210e72aecf217fec3e6b35e30f620ada3683516a05995c3c8affbfd02e477a0ee4a18b593a21036b370a3189df5aff78b4139dc54ec440a	1678647326000000	1679252126000000	1742324126000000	1836932126000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
169	\\x7819c27d3ac583da6a3e192ce60434ac5d35493f621c0fc7f6138de06cffe834eb7e39de79538e3bfb7606ad39ac4027816746235bd5e43707070802dd0b7b83	1	0	\\x000000010000000000800003eafcaee190a8fbc9f15d4094ee123dce0ede9e79ef2ec0c0d763c91b9dca105d1bdfbf8cd84d69ded24478463a82ad1eaed4866a9228baa13050c6c2c8093ae0ae4aac3600212fabcfdadecf4deafdaaa6074714a89a1191be7b6ca46d31dfe675881a63c814aa5e02bb3289781ed3f6a1ecbb94e51cd4dfd48e2639024fe231010001	\\xc0a14327209acdb9a85eb71b479923b4baa650561e543153749c0ef8fdba1b1eafc48ac96a42d62d66a7d105f1c889c44aad01401317f469d5e41624ba29f809	1682274326000000	1682879126000000	1745951126000000	1840559126000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
170	\\x7a55f7c567023b42ded20d89ce7feaf47bc9cc5f6aafa921d01edfd1da08b50114fd1fcf4dfa472df41c180261314a312c601c867eed572871a456f4150bfc22	1	0	\\x000000010000000000800003acd46f3b606eaf13346c577ab66f64b9cd17e089e98feea47183b69a34173f83c461cef392eb354c38c6196aeb87cfd158e0e523ee49c9d4677741d269b5a1ec1d7391c590d6433278bf79675e0221e1f96360d3f77f44b87a8d891adf562644fc66eac8e9fce5089dfb8c1f53b8dd5d6f91cd8c5da850047ae0e9c8c2e1164b010001	\\x8cd41b1f04c1acb074de935dc0675c926fe4b7534c11312d97199c75f9ef3a6382f0873469ef57061aeaa7d9dbe5e127ee14cac9fd7d59e286a9d4549932c00f	1687714826000000	1688319626000000	1751391626000000	1845999626000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
171	\\x7ccd2565a1057b2f844aa0a47f319f83ffedbaa0a1017e83dc273a144a6f9fc2c9a25fa32220b26f833848ee8e59435bb7685e5371968e78efbe5b9da1611d73	1	0	\\x000000010000000000800003b5a55de8dccec3e623586b13eeb78ebe2fb2c954efec0471e6643bf4d1b46ec27f2517b964b19896cc7e792432ca8549e8d8ea94f2bbf5c98da1833c9dd1d3de56ffaaf208f2ff0c8defde1c2d8f4dd29f532ba283b7334a6014db853e7ed6582b67ff29a43f523b3e1338807e890924a585a89ea01ea052f8512fc02f8a5b39010001	\\x1e0a10bc123f5ffff0bc0323064788baf6786f2567e0abf5b5f3692af30fe3bf62e3b841c0f7ab32333432a983bf5f1fa2f8b3c7f19c7f36f36005a2fe67fa06	1681669826000000	1682274626000000	1745346626000000	1839954626000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
172	\\x7ec16ca8626cb4cbdaeb255c7015634d422cec522bdc22d9a3afb27dbba77814bb14c8766e62569b7749e173efcf2df3a4a06991bd03815a192f124a3c54a778	1	0	\\x000000010000000000800003a281d8a8ec952831a5db3adbc9ef42127a718a1d29666d1f1f50fed67f8bbc4e2f67c38adaf7e789a9fc61f047d0af8bfce077c8b8131cb8f08663e3856f3c168af987088c86dcbf2a42141eab7c9447e46691a73d586e36e2f4f92168a621575340aab57fe7e465ebb65844c1acae48b141e3deff20e2c92625b261bf47397f010001	\\xbd2c9cf9add2187559b4791a2a609da11ec6b3b2ec4a647d205828f92f34e737d6394a92201b63ef886aef0236b4b04407b465021425362028e258e995e09300	1679251826000000	1679856626000000	1742928626000000	1837536626000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
173	\\x7f7db8bfddf1c69a435c69db0fb894227ae19c206ebb368bc7853c84a6ffd907c7d3e9b9cb75a537d8052011280d2ec1e1c8f1d0d746c64f4a4a6b3573c1378f	1	0	\\x000000010000000000800003a33b50dabbf8372cb993dde8550ddefeb0fd8e4d6b1c2eedfc1c6105ac727f05af3663463d155b7ae98e8e8356862c5fd52c7ccb34e598480b3defc091985eee61470b6fc367a3acb875fd9da7db3b8eeaeb2e282015fd0600669da885d3909c905cc5228eae9d7dc7a1aa8b61c1f3c8a1258079eb9516c2a7d6040d7a265a65010001	\\x35cfa72e9280bcbd57d6f5f90a19f73c14792453a15b44d4479029505020ba50d172c575c9ec9a743b51a52f626b553de74ed084873e67b606d3f8745d5b250a	1665348326000000	1665953126000000	1729025126000000	1823633126000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
174	\\x81b95743278b6921cdfee5757140f44c21df8bb2ab7d5e9e6ee665c060199120befef5fbc289c0b72a1aafbc5ee9dbbc7c0e9717e510554f9e5aef1d28ebec54	1	0	\\x000000010000000000800003a42cf7ecae043ff6a695ecb0494fad1c5f8fee1142095aa934e90acf2d9b4a85d0a43aab26644e46fd020944dad745236e7ecb36a6dd76dbdcedce96cebc453e3a1ab876c8b7cc10de1f4045c7c8d7fd1a95bd23d11de5356bf79718a26bb9084130549c0ef13b1dd82fbad10b00f2d5e4da73204eaf4c14d5d925e7adac7f0d010001	\\x1707dbe76976f0b4272f5a17bd8c84d3a5e3958f4f5faf0a9f289fac9d25ac6e799dfc272a599b7277ac95f1c1380b5b4fb0b8c487a6dd501fe6170f9c57840b	1686505826000000	1687110626000000	1750182626000000	1844790626000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
175	\\x81e5f5cf3947364b138466effca90e55f31364f84a593da7bb2b9eca840e5fc74fd0c0a36781b81b0fe126e705d12682e85747cc62e97133f2557778170aa0d3	1	0	\\x000000010000000000800003a3b18d672d21116b711a927c70a2b58d59f6b152aaa943a287c1deb67ec4d333349017426f1aba3e807c7c6223f2b021d852ab24aa3d9a0c7e7da4a23d4cb69919897a01a525d17dcd4f1f2c16df6ed0eea933d5089b6565ec657c0be1b120a15a0389f28fac79df3a1d376ae148f1714c58c47508197dda57232a643886b2cf010001	\\x93133a457397b0d4390be3f4ea07d17b9f93e404f1fe948d38fcc6a640fbe55bc7d50a3c8f4abd570547b151efcd822be36f18c1dea7a15964c1721e3443bd03	1670788826000000	1671393626000000	1734465626000000	1829073626000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
176	\\x826d897980cd0460d43e0620df361f10944775c11e85cf398a3ee8d37ec72d641acc806520edf4055fc5e57a22d95fb221aa03747786abc4943ed66b9c29c2eb	1	0	\\x000000010000000000800003d7ed7bbc5b454e35d29c0266e5fbe28893fba1d2395c729f2e2b7af4f6e6d32f28cee0ab49643af1a0814b67e54362727ad57a3d810cac8ddff332e0ee45527beff0d20bb7e3ba86e0e529d13b1d8078bc2df0e9686a8f0da92fea65f08ed8a2ed1d4e89cda155bd0b9c7539e127e2ffd3f8eacc100f9d38fd871090c4ba965f010001	\\x0be98f4a3894757db73eccecf6cf5abec6e14f04784e59506a016ea5e1919a781ffd7e7ab1736254a9328a7c52326f82a7815ffcdbf0fd4e49b4e2b4753efd00	1682274326000000	1682879126000000	1745951126000000	1840559126000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
177	\\x842d49fa3ee2ef7be4db1dcb2d4b4cb31d02fafb285918aeedcda9b031dceca45ee98ac6603ced0bde25b08a89a5321a724679569e59a3aaabb3bb8e8e249732	1	0	\\x000000010000000000800003be3a53e7da14043e165389fe930ff617c05f9d640e1d0671f7cab275ec7a1746cfdf73443387c254c071de91e9905eb53b5e72fae5e37ad51ad5e573b1ae2c4a6b99a55a70b95a61eaa47da6b3586650cca9c424cfa138f26c91529ea53cbc72a1f4a8078732e80baff602e490ed4fb4d37b2b1cfb7c3299fd5a4e64e9533051010001	\\xc585173bfe0a590f98b2d2d0b0ed57f0359e0edd96682bbe2d6884c05b25f67b1d752e86f41d1d31cf5c426179379db1612bf4a6b1ce7ce6673eeb6d5bfc7f0e	1682878826000000	1683483626000000	1746555626000000	1841163626000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
178	\\x85597d44bd5daed94a3d4e399d4134321f604a9d9f67ca8b2749248847d072a7fe13374b759825364f83f3f7d3fe4a977167e0802e04c4e6962652d41904c906	1	0	\\x000000010000000000800003e29cbad97a2de9ff4724256ab902834defa93988bf7e8d311204f65d1a1d50cd7570cc4597c3031583812a61aa7c7462ca16ed1baef28c520dec8c692520ee811050550b4218d044a010595296d34eb43b176900bc0aecb6895b6fe2e09d7113be2e3da547cba29bb3a58788c208d88744b6649d38218d9d4ebd0c95702906ed010001	\\x4df677c36caadb598c19efa6e59700882c97055c91f96ec1685a7e1776954c265ce48c66e58bf3e3b39e812fa806273ab351316630772363e1becf9e2646570b	1685901326000000	1686506126000000	1749578126000000	1844186126000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
179	\\x86299a489ade9ec877112da06a14cfe35ac5017498b03079ac83adc373d44723a7f6c93df0f177501906ee66093ad9d232881c9c5723005ebb2a492ff5738218	1	0	\\x000000010000000000800003bf3e22d65242f7bae25825aa83e0652950adad86987eba342fbc044015d2be2739b14612537078fc10a6848c008849c0ccb9dff7ef8debb8387a84896c484a45b6a6d0ce9c4c6d36f1848173b97e1363e7d1f5ba5426e6948b66dbd9222ce2439c38cc33c8712f8a42b0abef7858833fa90f0fda6d353d6c3e877c492165e81f010001	\\xd250293558ccc1bafddee89d39b2f959e721469c39c17898ab9794f7b98e137de7dc2790a6798bc7e2db32c7ae39b3a22d6a7443bf9a924923a999f4d980cf0b	1665348326000000	1665953126000000	1729025126000000	1823633126000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
180	\\x86bd29e35319efaaf4ebddb3a99a9dddb598bf56cb26b2f4a42ade0fe5b77d1fb3730a5aae480e1bc9c6608ce81e2c1cf99cfb0a73c173efb93021aa5acb2935	1	0	\\x000000010000000000800003bd7c21b7747db1e4829e4bd10909ca2ad4ede05b3022dcb9bc2fe9d5f714f243b7b1f211c6aa152dcf43a86f6eec25274915187ed6c3348af1b91d69dbb3e558f2e883b7d923d6487d8da11de0aeb7d4e44dc367c6b9720fb00133225e916b8ac945d74035335758cc30e84564ac2392c41c37fdb6edf97e7e2741ce82e64b61010001	\\x26464a745762ce75dfd669b1c12d7d99b9d849c1a9834afef1cdcbe132fdbfa12b7afc51fd0e3c2d3395f0b18fcad4103b6fa8d93fb39de3cd2ecbaabcfee40f	1665348326000000	1665953126000000	1729025126000000	1823633126000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
181	\\x87a5138137f1f7a54356cc2c20aeeaf44207b2a42b846ab05b12213e2176590b7cdc6a320c7ab8b5b25f8879a2400cc7e47ef9bcfa2c366579f5db90385329a3	1	0	\\x000000010000000000800003b8c113ba9a4425668fc64555477120b7bb0be5a46bd0a6fc8f029fa31447ce7f202ed3d83d9e11af5561da77148094a5eb5efc0c89d0e2f1611dd9677d81f7792b5fc80c6e2a6afcae63de3de8452db47d9cd6e0e73f661fa2da67cf6ce97b6f57348f3abf34d7c47d84dcc7078dea81e337890d828bba6f2215ed3254a22ed3010001	\\x97c51bd2ab7f84a55476cf227546118658854a75946059ceab8f17f154a34e9cb6bddd5d05626ca6bcb0a4c2feac467838cebe03e0980feb8a904d34b7c16106	1689528326000000	1690133126000000	1753205126000000	1847813126000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
182	\\x8a3d9ed8c8b7794db2f32730c4abec249d8553f9b7fa80c4efdf00e79ff9fd4747686adde330e79634ae6c768faeb156f5623c8a1c93cfb112098f4ba97d1374	1	0	\\x000000010000000000800003d10ae1880d9fb3aff05478c5866f4bde5fe88e0533a847b8cd2fe8b4597d57bbbed2ff66ed46ae8cafd91015f7efed021085058a804d975542ffa1562521d4b70d14944a6062115bc2a823728f8078ee7a5167af9711057886b54bdb86f15da3fba914b7ef34b66305f9aa54f3a9b0e1c26bfa434653e8d9aa36571d89d68aeb010001	\\x64fafe6a7bd5ae8dc37b2eeda74c83d4c794e361732c1af70d65d7398613721508c154dd501108bbef4dbefdb06a794a2ab5ebc9e1491a1c8f2391a5bc75140b	1676229326000000	1676834126000000	1739906126000000	1834514126000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
183	\\x8b7d6bfcb85099d687879571d175cef61873ff43c63d4ba93601be434e21209a6112486504bef62c58b5231219f34a5f8d100122c474aa87e0ba6aac0aa9eb0b	1	0	\\x000000010000000000800003c0464b4aaa3ac571eb8e5a29523a8d1fc1f970f1672795d027b0e707928f54d719c21eeae6f6e42a1b71ba63ce50ea1c41b9c3f5c1bfb2feaf15bdbd729656790feaa3557604f9bd83de218b2689d8f6e38588fa4d43d59ee53c9975a578dbbc75501bbf718fe98ed4768e0aaad05c7060c44e9b3dda0c57227316838d792da1010001	\\xa587d79cb85ddb4ca8b923e50f59490ff57d80f433541a39015405c6199ce2dc7785b2d50dab4f5d43b0d026bcda14d964c464fe16afa24c3a35fb1306be7e0c	1679856326000000	1680461126000000	1743533126000000	1838141126000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
184	\\x8b31150171c52235826901599e69106d4f4134480f6e0e649137a46575c43ffb6537f2037562ec4cfe74bec63f9278e51e8fb028015e4350038fcd0d3351c32d	1	0	\\x000000010000000000800003c62d785ac4b66b26b93f3bc4b1c16146a3fa5e7143596b5e91379866bd03c504f16ce7eeb308a91db3213c3521838b643f8e4c8af3f27710ee0b0bd990853445d5f4bb7bdc944bfca046e1a55ea346aa834a9e56daa9c35681e782298a7cc4f311110b6d528ecdec54195acfb5a88851a64dd87de9b4dc6cf7654ee72bd73cb9010001	\\x07b3e90ef3f29b7b0d706e02294734a84eccc1f0662e28007c3449cce2569ac96b3a7a3ef5b54751521b2a2fefab8d041dbafd0cb5a949669554b6c0798b5c0e	1683483326000000	1684088126000000	1747160126000000	1841768126000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
185	\\x8de5bb20ebb1d5842395ab68e568cba61f83eab30793c29c2046912f97ba584bb9a749a512fde050e12c45092582f2506dc926460bc0788220118ec315a6d22a	1	0	\\x000000010000000000800003ba7af9e2f02067d1fdd515d535afd4bd371886cd52f82687f50b5e6e5ab88a7bce83fcadee47bc2d5dcbaadaebe07d8f29f4ef1621b97d110d752dbd48bca47affc5a6dd65a5088f74935291de972958f3a9a43131291c99aab1228989b33c117158c73b97a3b4e2ce2b3c6088eb3075f78d16c5c37e55a7dab3b8fa07080255010001	\\xeadf42d7a46c247555ceb81a3b2e084ab0e5615e48c3c7de3fbe5a65435f9a7ff873a7b87b01430bed097fdf471614487fbf8036dfb1326703fbf9cae772700c	1688319326000000	1688924126000000	1751996126000000	1846604126000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
186	\\x8ec1eb56adf0580b42d57bdb87ef76e73430949f43880ec9ab6b48a1159697b2b8639898a8edebf787528e82ad952a1b389ac26c3e205b60c9420bb1a39845f3	1	0	\\x000000010000000000800003d99047b60d2009744b08a65495337b141156e2ed17c3f1d4e0657aa8f8a43399a58e506a2a867e4acbc3b391282703993a474c1ecb281730a4acdf436c66eb5db224d9d090f390d3afd8e9f40c2a7066e2603dc83057583c465154979c07c983a4ab125a583f1939ee99a061e1f9c70a6a881f1b2df5aa6ad6439de7ed22162f010001	\\x868041a8db6c76e09f5e10d6558e0903857fcee37715447e600f6ba15a04da88f8de250087f8cb8e90e16af8645764ce9fb96c6743d9b1b245ef87dabb4bcc0b	1674415826000000	1675020626000000	1738092626000000	1832700626000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
187	\\x8f151e920b61004f579cf029129c9f6e6247a0ea06307dee8c250e5012bb23f10c3d8094d19922e814a621990956193886c511660c1a7bc39727341631f24462	1	0	\\x000000010000000000800003dee216ca047126b4efd7ea609fc76645e242f8dcb70fa6eb70bf5874355ef1c5007081cf8916c577a690f8f5f0f55033d1a42f2c166fa754f3b3b5a0de71ae5e1a179ddb6dd1b27f7324b26e5fc3eb4c8afb173fabc063a64389e4a12def3d3771beaca26fa08931809d2db03375329d361644c141fd646b217888e7ca9f3dcf010001	\\xfbe6f24239a3a3428f4cad145131cbd41ef963899fb6bb419874649ece12ddb5cbd7fda25d604cb43c0c16febe34fd534f603b076d8891cb9b9c57a93381c805	1687110326000000	1687715126000000	1750787126000000	1845395126000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
188	\\x8f5dba844b05c8fe023111b3b26cbb1414108ad7029e2020c75c8096420a1c0cb1f8c8a89291c7f2dac7da9e535770214f71dfc2dbe063507f580f8777f2b365	1	0	\\x000000010000000000800003c901c1bcebc2fcd190031722fea4199c31cda4edbe00454dca5f5b347a7e87b289b971480c2b7195ca4a4211db2c371948e82a72de60781226ce544075eb21d4730830e0771fdbfb0ea021b03bce0532d850a879584921fc3a66f786d3a7fae0722ac0bcb7159a7d3d0b55a5fde8ca9a5de14fe77f9df7f57c3d9b5f37da19d1010001	\\x5e366411e17dafbfb9b00fbc679803b222d8caf1a28fad56d7766e09e21c819d1de61a61fd9385154486a4e54bc94102e9a88dd68e9e1ae65e1672f6bd9e3003	1666557326000000	1667162126000000	1730234126000000	1824842126000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
189	\\x913ddea73739be31c9b1ebff1a71724819e61d478e267f32a8ac997c039ab930a5f345e13a9f0534bbeaf67da56846dceee10c9e44323d12a758178cd1f8d712	1	0	\\x000000010000000000800003af561b512022ec748de7ada9246240264856c825d18f5712cd7334d9a88ca3d4c7198c91fe32026720d747dbb40ee1213d08d8c2e7edd99c1ed95f9593fd425f883aeb46d58cc8a53d8c384a40f4480c273bcb1f1106bb26490bb6a988d510cb4571046b6e91cf04085f3303afa21dc155fa574daaac2deec611bed49cd7790f010001	\\xfefe17603ff09cf9556c368987b99a25e351bcd993c7b7f063532e88f8d9fcb0f37026339f5d710e6a1caf4330fe628e2b4b054f5a1ff7389a20f19dc2581c04	1670184326000000	1670789126000000	1733861126000000	1828469126000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
190	\\x9ab105f5a006945e96767e83f5b121fd055d057b7e8c5fbdaefb68aa2f04814eefd3d80245006ac4f465c7e39a945e3317bda1e64fc99466385ddddb8ee69964	1	0	\\x000000010000000000800003d927700e16b27b5ad525fcc37c470e6661ea54c857b90b110579488d8b33dc6329a8d6452b38d95c573be6d3b4af341d18d71ff2f9f488da7b0e28283cdd4aa7f31eeb1075a776be8429dc480fcf13e50d4fe878648a050bb44db69aaecaef416b6c13d7333253b6aa0f934769b68c3a0d4d241941582889d06001cd2eee0e97010001	\\x4098171522fd1d2d7a66bf74474f7f61f2e0efd53d5d28514d9a8016f1c2a2bb8cf069f2aa3eed7edd6c0a01bd2c5e12b5eb4222a764b6107d249240fe96d408	1662325826000000	1662930626000000	1726002626000000	1820610626000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
191	\\x9d0dee57d0be25d9ab9ae61c81e37eed8848472a64c141b6392a68f08afa118e7ac5fec12a5613cb4e89d8ae9e1de53b2753d83ea859fe770a75c9a8efd826e7	1	0	\\x000000010000000000800003d1e174d3a470f19691296174e2a92875ee9edc195c6569a88f330f1adfe34fa29dd6cfb01ac84b9e462e9337de32a4b46ea58e3fee3172eed36a94e6dfa1569e358de21574a4231764da0d45f114e3ed1442980e0217b1193e86a5a33ca3ad1e7c6e1f4dfede72b87513fb7f7052b7a58fc53869faba6877f0c891764f10f25d010001	\\x26c90fab7cf795460e0461a46019f402ea5a6f176eee0ed7a3b9e3c3d3900ad3f3625dd37ef17ad049400a1eb69a3dbb580f37215434e6b7121915b16827c50f	1662325826000000	1662930626000000	1726002626000000	1820610626000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
192	\\x9f8144c5e2440a2142f61a852d9635cd10b0c88a7e5434c09a210d4f9c28e1ff4e16c054bc0b9c53ff84f86706b150acdbe19814c04a99c097b8ae1787681acd	1	0	\\x000000010000000000800003bed80524ee7287ad345b1912a44f8f3d5fc13907d97f2e3207729ddeec16a3dac0e41346c05fcaa8c82f21d8321bd59f49012d2a25a1ee8e963be9e225476ed5664984421e3679cb4ae0940abe3f486e931d768fbf2387708b8b700e600015d33e9182251761b2f2a37af13f03396b70dcd2993bc1aa8115402e89c1ddebe217010001	\\x7a52dcf2f5cf102a255a8e5d2346fcb804ab858a71f75103b867faa967ea9cff1a435f0cc83bc579ac3b88bcefcb59908ad09f3c0afcf18bfff5f8cadd5c170b	1689528326000000	1690133126000000	1753205126000000	1847813126000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
193	\\xa0615d290b533cdc2b7eeb62d04d469b949081e8b47c11494186187ebc3f3c4584f018e440fec72e037ab3306e323be77c3ca35df91c34daaea61c56446d431d	1	0	\\x000000010000000000800003e2a3d277624e09a046bcc467205fa860db08100c90d5eee068d9ae1a747819658a9e3563ed963f9c3fb2e1083b03adfec71933963e1c0b7892f960bafbdede12a367c0a1c665b255b28a3752726ef0d2678a9c0474b2261b80499328e9bfa535641414b01fa356e011bbdb30fef5f202c49a81d04d8d078e60d2702f903dbb2d010001	\\xb78c92d3a5c9e50bed499fb6a31d95607fdd85986b92520c2d63b6387b362e02b5d6f87e8961a9849e823d035e32b5862dc78c698a24f6f7f7355829af977801	1682878826000000	1683483626000000	1746555626000000	1841163626000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
194	\\xa195a14d24116522f1a6fb7bb2ca9e00ef041ff95f96f7184f08229ccde172ca4f04d9a85c3e41597e67c017bfd2d32d33d55f63f79ce890e6b251cacdd558ad	1	0	\\x000000010000000000800003b03ff5f9d69b33d40cdc389faeb3ce877745ff62ed88659b42517c774808d61ac649243f598760782017cc928e2235b331c772c4bf2069764b6eb1a8b19d569cc7f17e648b89ff9914751937d4bfc6c155cb46f58866e347731df6476fe180b2ab24064fe04eff13a9478f9d85dc3e7546a3e549ec22e3da8a301feffba2e1a5010001	\\x3ded5f40b804c2617e621cbd14e757dbed67958e4714643386b1ebcaff06653af03cb82b3dfbf522cafc8774de26760c15972bc68c3f2c292068d4e3c9a6c009	1678042826000000	1678647626000000	1741719626000000	1836327626000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
195	\\xa1093dc59a08383bb3214eced8ad8db3c2431c23e9344c41e388e18b6ef9b281023e66c5f85921e789797a54e6bf964d7c5dedc6917ea0f355624486a1745f6f	1	0	\\x000000010000000000800003ca410a6667c378c06d3138c2e325e23b634413363819375a73c4f57907c9dae8e35ba26a2ac9b1c7bed2ecaa12abd4866cc88fb51328563de8f156514e31cb69f87a15143d8bc0cefcc2931af0249dde98e41b697ebc0abdceff042a19c67999149039456798b3273a6709ee6fb2d25bceffdd6b9e631e360099c3eab268ccdb010001	\\x2edb80469c5b0bc019df344f22ef2b973ab902499eb232480aea7c7af8e40f65014e8b5d7abc5b8d27e6591678076792920426131ddda3d47e3b2da871a5ab01	1691946326000000	1692551126000000	1755623126000000	1850231126000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
196	\\xa9a1b976de9f959052cefca41eb133ac6614a932024bb1a9796bc288693771760f29148b8598ba4d9b44f3b8df0685ec965e97fd086f1e5e2dcfa462409d9278	1	0	\\x000000010000000000800003e4ed2bc11f2f8129cbaf3775db0c7794770893ad19f6a7a20b651a7679fd16ac0dd056e477fcc58b4636644591de3cbc6d6e3f123c8188f51053a9925c6e4d2a1033d801c9ad3b2fb5b3113a77f016cd06eaaa1c264fd7324452473070dd6675a8f950aa9077fe2721cccb9ccae6a1a35882cc5155d87ff5c34076181716d9fd010001	\\xe51b564e7345b140a21fcd4ceda9ba8a8e35276f26d08e5192de9db9a8f2733895077a40dcfc95bf19824379d311b3ba12d855409f7e3f99dd88b113ae3f360b	1682274326000000	1682879126000000	1745951126000000	1840559126000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
197	\\xacd91b285a32b26b9a0afa5788d0228c928db34e99c577c8d0a3a7ea3622f5ea5134ad2929e010a78e71422219d179adedb5a5467f07c2c6c73c7f2e7d5d0c6c	1	0	\\x000000010000000000800003e51bf82d6fbdf036d58471070a305eb675ca4ad91dd70da1381f51047735db571ca7cd4fb6d89d77ddf580bb4faee7142ec0911a4e881b8d72d6e1bdac20c455ce9fb05fcc20f5592fc8b9f9fd2ccbaf081382debe269c09795f60a2acab5c1a9c6556fc13969d328b636325a7c2c6796010b5a5ffca15ec51e55f6359fc236d010001	\\x40f6480f7c3b5f0233c4b37db733ce61a94ba0233c242ed0a2a84d55ebfe1d2c3943d5b985770ce99de9bb5ee838d98bdf26176a47bbc7987e17837fa3acd80a	1679251826000000	1679856626000000	1742928626000000	1837536626000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
198	\\xaeb9ae6b2caeec1b96a4424eaee1fd864e4a74084ceff4b02da55968c8c096f709433bcfcfd7e32cf7137b0724c471f7dc901a8d9e4d71086dc45366b8e5073e	1	0	\\x000000010000000000800003c144f9dea2d616acbc98f410aa5530ecfbfe1a1142d93d0dd8c40b2af1c78901f260fad115b1ba4d45d9fb92cec0868ad1dd63d590e00301ea91f17b4d8cb936059da1c83026f3d4b91e2e9da86fda1632139a3d14871d4e51df8fc673cc1fda9c5d2973007eb7252bfcc12aeb5db72b3ab67e75d38c011b372b72ea646bf46b010001	\\xc8713d535f9171632e18b28927acbe83bd111b44aaf7249455438f545cca866229a807b6aa51ac98a9b5f5a29f943420c4c55694cba679314f56a3594d2d8c01	1673206826000000	1673811626000000	1736883626000000	1831491626000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
199	\\xaed12c5948860f4a1823b7e1006d6251216c01c03919fd96f06da45ba91a22bcd28bc34e18303919b7667fb032e5e8421cd8d4e2cb3595051b2633aa971acaff	1	0	\\x000000010000000000800003c2df4aafbce54ce5c47acdddc1d00647436e1bcb9e6d52e0b9b10de2b218f9fa92a4774844e8de71aa7c0a9e0f17e8c514ed3f073d548ae6556cf6076824588b0afaff2c6e7cab3931a4e9c8ba264830bac2ca2f2eb98678eb1d8c7a94390f4a9e9d7134a66d247747dd4b544ca5c71b1842dffb91d99cb4e24698875a7aee49010001	\\xdefcaf3e7b7ae9bd3e3567ef72aff697adf6368deaa9b06997c89d4933de544936c3668bf05619262656cf0ecb30623d2991a8c3fe32f7016e4ab01088405703	1684087826000000	1684692626000000	1747764626000000	1842372626000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
200	\\xae75054ed43c2a9802db99a4d96d746c0a1dcda847aaa77cb0b7ad6ca1a8fb6a3af9be15be14eae94d343615088e8679663d9576a61a2437867b26a6b90ad881	1	0	\\x000000010000000000800003c7c5cde9c8e0f5efde711739d8ff6de03be1fd94eef881c39363835f323258b4684da974488183005d70aef04522c5d3b6dc425e92a224676ba06639216d382d411f51b3795064891ac203ab03290cacd8a6871e4c93c33759c06866df89c04cb011ef659b6e18b4528250c0e7f6b87046de659173b2bbd0b906f8d5a4656547010001	\\xae4513d540a887a97fdeb410d40f93114c2ee87109d3b408d9d5b9bbd8e004c1e03dad6ef9914afdbc2be734030f3e5d5169b5015d902c2fc62b8fd3f6d6280c	1680460826000000	1681065626000000	1744137626000000	1838745626000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
201	\\xae2dd619583d5476a304bf5a4a8c296ba64153683a2f9807715aa85911a46af1f14a888384390dba5f4923b3514e2e6ae85123e19a6fed88dfd161ede6cf27dc	1	0	\\x000000010000000000800003b08087b2b1dbf570d02c3cfa59d57748173f7047a3a966df12534a9e2e07c3ebcd246c0e530d15d80938053dc36a092d6af97d980e419a917f410da6ecb55590648e702520f7d39ac1c3fa9d834d39711dc29a16a493aa483bbe8dacd322ebc9a7e2672c58badab01bd5a2ea800428e270a318d0ad5cef696f8239540d143e59010001	\\x5131da2954d962013ad147d27b46c52f4277bb9b2e5e8c236d508feaeb4743c2f340a192eff7b818fc66e3267729993a559ea0ef8070213e69499b42af33eb08	1663534826000000	1664139626000000	1727211626000000	1821819626000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
202	\\xb45577a6359d3273878cfbc8a7b8e7bba051deed20c10a38bf827f8535dd5ee3c5d00c1f7b777a15402ec33d26b451c475dd8e603eceaf8fef8eb386e15443d6	1	0	\\x000000010000000000800003c825592953feaf65613110fb57c12ca2c15996d1249257978ea0d1f12c08376313a6ab127ade518140eba826f39d93e861859e4abf99e2bba130ea4fb24b098cb14828f4c959cecf78a3a2576026bcc43ec91e530139562563d5a6619bc624eb9162973f7630566a3d20efd954f925da236e1667d2815fcb66ddaa9322f43075010001	\\x9332e2a23aa4fa7308ec96c5fc5125a481d2dc4b2b9f57d45ed83d07ffc3c7412609df53e659d8ce92c9bae9a31974e670da92302f025b4839b56207b3afbc0a	1675020326000000	1675625126000000	1738697126000000	1833305126000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
203	\\xb411860b51eb34a7f49ddf64fac71d3d5a4fd08ff28a7d4339a5e2a5983fa211dae8dd5cfa9e1989231afe7c5f4196e421a6507dc1f8dd6150074431f20cdd5c	1	0	\\x000000010000000000800003bffb4fb5fcb40f8aa9cb4caf264960caca3a72e224afb2489c0ae45c1c0a84759c33305d361b223e3f9b49bab0ddc0a06a09858e33870646821d2bb4a23ca7c1859ee2ecae5cefaa721f1b02426454359c95bd57e8114422cf7f0354fd6f1b61e0b9371faaa793ff298c289954c94b41dd97bb7a5aa0a6f68717d189a29969dd010001	\\x3f2baae0e9467082864a486b079070b339b1b704863d17717b127326e5e5a45f9c8f25a87c56df9d4fceb3e4437819e8ffa21ed8c5d428863d286debd876720e	1673206826000000	1673811626000000	1736883626000000	1831491626000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
204	\\xb551fba7a447539d5d9fa023b2a4b0a4f79e25248481b7a2a6353ec50adba26b57b37379f9b2ad01b1615e9cee46289763c70126b0f3955fdc46c16cb2ea84dd	1	0	\\x000000010000000000800003ae9d330e5ae9975867053332af6c0aec3375e1f1d10b5efe36c64f507b7d5998978d7a5f4057571d349a4c277afe36e3ef444141b2d4c89a82dbc7e56a774f3c3b78eefe3a04a255f4b3bd79574dce077c41f9347d123e38b348bb2cd04fc00c371238a8ae68011debe46b14889ff804c6dd94e9501d3798d4c177660a07c607010001	\\xeb54bdc1a3abf27c2afc96723546d6a7cb460673560f4a614f8ed11d196c80744a761785e027fe5556e593136fac88822a2dc41f1f84ea4ec457dea42221310c	1666557326000000	1667162126000000	1730234126000000	1824842126000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
205	\\xb8013cdb0917554e753bbfed95813ecb3b96bed916e96d6fdc9a02df2814e55ef83b27864cb083a526f7d10f0ed8a9665a1c7203a708d0ef333d82e968ee8eb8	1	0	\\x000000010000000000800003ba4e40055f92e0ecc1fa76fa3cafc420530dd431c186909f27ad67200e8f626ecf5fd15160f0d3c2f6046e633f378bc128e447f78878ea1565ac17d46d531923a288cf6de785818208e55b45f1f40b08d14f7605362cbb23cd7526aa527d88de76e73959e62588b4d1d167ea6cc51d5e1d5b58468589b681eb22bc2c2d13b75f010001	\\x5b94467a6cbd8e8c0f09a25de1f73446926d4ae34cb1cbb192fcf6b75aab5f8b3239695750d6bda02bb855aecced563ea4a244b9d19e10de11a7579cc0680f0d	1691341826000000	1691946626000000	1755018626000000	1849626626000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
206	\\xb91d677646894b80f8b4e01fbb04677d0fb88a0b985a9a5563824ae3e686e2ffd59fa40c29edaa9c80de9762ed984eb189664d31e70c1c976dcaa36b1c2e5cd7	1	0	\\x000000010000000000800003b0319b24a0639c68843146db884ffa9bd96ea420b09c7a8005b30e247432f007c9789a44352f7913a48e347009c87f2ea16bab1d46db3d9078b033cd049f4190528c33a1de377c2df4d9361bd080bd01308faaf64ffa7d2bb5d583dc065631f82e466df3a433c3f33f82b49c5609765bc274f815bba2d61b11e14ccf33e26dc9010001	\\x7761df1dc8c8a5d5f4d6961d536dba2a9d0bd73f44278915382d526ff525afbbeb785bdc37576f8e2026175f93fed0a1462dd58954c69a7f99323a1b13c2d500	1667161826000000	1667766626000000	1730838626000000	1825446626000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
207	\\xba9d91947bddd28cb05d4e291afd6167fa21e2bbddb807284b50ad42dc940e45bf749361d71b91fba386665f4f7732a366f0a83ff1c669731991ad7b800c05c1	1	0	\\x000000010000000000800003d18e4364563da4b4c23c42860e1ad181c939b320d6547f85d8eff6a449f4aa2431143b3e1d3b5db3327f2f0868289fe22997135a16473e99c3e7cbe06cc27e587b1c692aee768540ceaf596139deb1770db24253855a77ec6765836092e316afc293d8a3a92ba6bddfd9064a7ad6a6d800468a16e509a663176cc440f6281fa3010001	\\x11d77ab4d39a7296d2b88f2d5cbe3f2ca99438ff6b8fffc08578df537aceb0aaa28997e9cd99cf684137ef810a431ce99b7c5d003b56b8b3140315f908fb1603	1682274326000000	1682879126000000	1745951126000000	1840559126000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
208	\\xbe91de0055dc30ff8e91c8979ee920f1f075fb68223ebe22cb421b794778a4a9b200083db0f5d9e5b18daadd296551526e5dff507bc4a840544ee2fbfd28fb7b	1	0	\\x000000010000000000800003be4df8af0471f1d0aa9d119badd0d8330062d36cc7673896572ab5b94d851805e80185ede16b20e61b7bdfe7a8b8b22caf21db8e238bbc6f49a1caf7ffcd30204939285bcdf1628c71ace09469c27c2d49215027f1e30c3706ec5e7c70df90ef51c3385af5c8bda10495bb74bb7c933ff40bc190bde0c97c67ba5c281e8449a3010001	\\xba8533ca502793d42f239de8b62f93ecb6f20d4bf98a45e37840d0a4f87f26f1d4174f38ce4806308386c4db547d58c5101d49059293ee2c414bdada0fded50b	1671393326000000	1671998126000000	1735070126000000	1829678126000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
209	\\xbf8dbeb8c9414c4c7d82b41e97aa6ca3bc7ee25ac6ffca06823971fe1625ceac80ded06bc4947e09e172e495651f8b2e857ac07b395a30a4da8217c285b04772	1	0	\\x000000010000000000800003bcd24d98dda076e7756e83cdc755587b6b025993dd3ac4a08ac70c45a4d7dd1f09231635e748a97f79613b85bb2f5cd1ecdcf9ab6a7b7d7704ea7415103d972220d2cf904a24c095670b9e86678950b8f523e7cf50508702e354cff8d1fe1260ff7203dc327bfe9fcb7770f4f2e3200abd708315b1fd03f1f01cade1eb2e3dbf010001	\\x66cd33e437c474db0e9b3115e24f21cbf3b7a9035e9a7539f6abb40ecbd60a3cd4d1d73302e57e8c632a3a437db37920a17848dec97f15c55b6e96d64ef82808	1685296826000000	1685901626000000	1748973626000000	1843581626000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
210	\\xc3e5839b7841a12f220a2479640f290464b2d35cbd90ed1bbc5bcbe18c0db7f7d5dd89bb1f8984ebe08211df4de7c39710921024bcf1b793b04293748fdf82af	1	0	\\x000000010000000000800003d6f435d91064e5f381b3a387f1431a612e69b1ed70a017ef135e84dfcb31421a296d38dbceebeecdbf11a4858107634433ea87b8ac58e30b1ccd962fa990be7a309f4f2dfe4aeafc52583c8615e6d6c5dca4ae20fbc15f7658c326708ff3a31b32acc5441e523cea25c36e57ecbcd45025d76a4968468ff1ae706e359cd7f46f010001	\\x534bf10ced1e5b0f6f9f919c0bb500f4a17f582ec8125bff62e268a18f43577086b4e442f6f4366c25e2c37c8b9f35a486bf048e54a495de21a1a8c3f5633906	1678647326000000	1679252126000000	1742324126000000	1836932126000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
211	\\xc3a946c31e8db60b20fa684523ac9027494b7f4e8c0ee2aef5f94a678b47a3f39cc0ab9aa1028aedbd3663f5b9afa36d136eae31a1c0e6a70023929ceed8828d	1	0	\\x000000010000000000800003cffdedf8dac289c82700281874194334b1d7b87b898637d66b4fe43242802fd4977ab3a6086ea488fcd880b5360c411ecd1b55c65cad9b50ceb742cf3fb8c8c4fa2da41bc54f3dfba902d4728f755d70fe24259cbff64897be7fe20d22a9899b3027fd1c4df2d5e1115604de265d79e5ec3ddced7f13074c52bf1dc3e9bef1df010001	\\x5ec592b9f528358ef51ec3d1075bcf18c943bd7e8c2a65279f70124e66fcadbebc66f5b702c74c08a6fcdb5346b6e754a3056449079a95d81ef59a1897f29c0b	1682274326000000	1682879126000000	1745951126000000	1840559126000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
212	\\xc34994efc073951a9fab7537c11254e5ea7ad56cdcd37a2e566714c91846699461577b342fad56e7f01e2a70a5b3ac63fd878be5686b853daf4af40129a55032	1	0	\\x000000010000000000800003a51a622b43dff1f5a81356071b8dff853f08d42e400248a965e2079b31cacc5788416661c7bf109463629c2546b3dbe777fd87efdb0fff858c4a9cb5a1466d17a26ec59f8a46c532cd6f8a2ff564d20944bc7ecd72aa75d7741aec5e1e95d37d9a51f20cc365479b8ea432a89b35a860e1b624e62b76318e860cb8576c8b6481010001	\\x83ca56cd0f586e103863e29e1231d22e90aa2743bb50c8116769155028d9f8691ce3cd73d7a7a64e1cce94e527210f408398d07e552a884037098d111702320d	1675624826000000	1676229626000000	1739301626000000	1833909626000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
213	\\xc87d016d7602880281905a2c9e5b32c56e720b03caa56f6463e94ebb319881c11e4998ca4e4fbcfe2c2bff42a24c4af8f0eef8485fb902025fa46e5ef6ad9c6b	1	0	\\x000000010000000000800003af80e2a32a48bc299a19f509deeb5416ff3ad580041c6fc4e01333d86788a85b4a6af9ace422738cacd8c51ae595666cd50ee118141b9129d85dae403b0a42e6f914c71f87528d53ab7861a915ada2518e44e96215e1576a300a6d75ba579de183d2dd3c601ec1b62aa7e9c2e8253139c2eb6b7ac4330678fc63fbe283697e41010001	\\xd3d5a389ae28e438af634bea33c86142a101f4222ca1d8ff31e8d235dc1895554824a0a1f342b6bfb3d6341fadc629cd3b628c75bc4af46be52e8c5d657a7f06	1688319326000000	1688924126000000	1751996126000000	1846604126000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
214	\\xc9bd556061bda3c746ba3eecd497dede4c1f1462eb8876a18f4847aba51a4bad4df8ba92c3f357d44549bcfb2efa557a0bebcb0cd86ea6fe37e6278904bc7588	1	0	\\x000000010000000000800003ac609864584efcf739f35b75d27c982259cadefcf95a0f7d5eef2b27d86c33b16799dc0a17b0c291feeb1b04e2364d3b618f3ba7f44146595b156d1c909861f92204e72ea97aed6282847b61e215067d61ca71392024b0bbad5eac860fce786155ec7082aa78a0af26a54bbe588689261d6c723d7c45c3c1bca369edf9dc81eb010001	\\x756cedac678b3e0b8ff77927e4848665eace9f997a6738eca744f9646231dd4175ad87d0ed8cfedf311bfe2186dacaa4abf44256fcc27efc68190e442bc85d05	1669579826000000	1670184626000000	1733256626000000	1827864626000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
215	\\xc91966e09265cd58c48f23c2b8693d05f1084d7d569714d51bef3515d04a2bd9e096d7c447952eaa4defbbe6ca3cbaaa74c6d41677e32de039815f2c9199f582	1	0	\\x0000000100000000008000039f1287b14e01fc0449697b3c794c875b8ac10805dc7093bef0671e0ab56eacefba431fdffc5ef14e516084778ee877868a8256de5591e9f1bedcb5c0525bc48aea5de8d4cedbbb2a42d8fd4a92b3eb46add8c6631ec8b57d91dbd4ae6a85e8cfb717a148b856888f6ea007928a5101e8e42aa112997193f71af1618274a80257010001	\\xe8102234a30922bccce11039fcaa9c298a34b7ea32026a7b8fd94101ee7861fcb003935a82a93d14c6bf70d4d7530072238074399b2a860bf92801a2e180ff0f	1682878826000000	1683483626000000	1746555626000000	1841163626000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
216	\\xca19d90f53da391b5e3ec38bdd95ff229eb3709230f0c2da85f70818a8794ea6b108380178010253b47c85506be29ccc2962872d589586d48312a1f0620e43e4	1	0	\\x000000010000000000800003cbdbc97fb84178a113abc6a9b245e9c0964220e9292d8a63f5246f908f8701e4b531cc9dfea64800c920f52e13847648c1d5f93f8d30e3afaf204e0697541440fc41a830ae0caeb022b74faa0f8a6e2eb85c2423159033c9a94e308afe835b2a7c5a01fa7c7d3ef8c77031dba9d1c13bfb2ca6ab07eded68806d6c6ee4176f2f010001	\\x243fc333be1a98ec380526cd6c14c01159493f475079f0f0668bc143a173510a30ce250c5cc21dadfd4fcf750d135ef1a21215768f3fac77fad581e01bad380e	1668370826000000	1668975626000000	1732047626000000	1826655626000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
217	\\xce514c7ce6e0ac08f5023648462d9ca14cd866b76737ed65ec7f8e56a05517bb3823497c66dd803ad7daaed5a12568852e801a01e47b3b9bd0c1a853639374c2	1	0	\\x000000010000000000800003c926da7525950950287e37b07347aeccacf4de0f229e5e5f8cac85cb028a14ab34cd653ff001ce107d80866eb01c3e1dbf72628f1f7188739c931310dfe31d096c842b17d86b3aaf9daa1fe293ce064ac6209645fc776b4e0a1d35cee6969d04cde4a072bf39de2357160dac7172d42ce16a6ce90917b0b0f456fc24cceb1563010001	\\xafedeeefb03b4e96bf7a7d5b601e19cf27207a1c2a050984b7d28aa434f23b2deb6bd12be12ee3c18d6861497fbb48f1772b9c0b57ca4233505c29dcc5b6c500	1679251826000000	1679856626000000	1742928626000000	1837536626000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
218	\\xd02933ca8ddff2f3d8690be5b6d68899cb1f13ece1054fe345a695aef0be5e3b49dc263955d0fbf9f315d47765e8926078b2fadc770a16953f1578de7bbc5144	1	0	\\x0000000100000000008000039d4e63357648a8a474036dd3d3133ee5cc19c9416e9865bb7e0ee154030ec7773e93e9e1203683fcc8db742381979826ef5815e52c1f42cd15b8e3d98b93660547970a866d353192371be7bed2939807f05ff94b816ff3ffee86044d8214fe2d61b4a8a67c1e80c17abcd86454b47b406c3180db9f92d3b53b17749be0106d51010001	\\x00bef920aed6b8a36a5a2393a67981d6a3c86f4ef0aa83bdadd57e95c9f1a3aec4fdb7b2346f797d83d89c15373c2896b40b2ca987b90cd40cc4b89939b6590e	1676833826000000	1677438626000000	1740510626000000	1835118626000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
219	\\xd15973e87e69f7b307066cee35d4f8dc35810a4a3b748a9545a6e83650ffaef402a266f9a752746488a3e27e6f485643e0b95d3500a46a4b0f6127d9f5e4f06a	1	0	\\x000000010000000000800003da2ae3f94c4033390efdbb5662ba5598029afc49b212ea96ff27e79f9d481d223729a52ea56587137d5adee6978b81854241aa5a12a7db9727020ac6af0bba9c36cbab92147636710bf80fbdf527006a32cd84960a7551f105a05d331c8ea0231808c732826c0e390ed38f8d655f610ed43bc6bcef17380d3ebf2e95ff9430b5010001	\\xc378d77d8d5213b0b8e009045f6d694977cd3d4f29284ee8507d1ef85060ee616faddf99958a5d73146f1451a1a0e3f80298e121cb104c9ec73b4fce6a698f00	1666557326000000	1667162126000000	1730234126000000	1824842126000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
220	\\xd1b96979976a9378bc63dad027b40705a9084a8b94f501ee2538ab45e2a827b6dd5a1949f4cccc014011815f5561081e01c824d5f80724a5b4be6add39c3dbb2	1	0	\\x000000010000000000800003ab8d0b6d845904c2320be645154fe1438bd71e2d39445d6e9e63026653d7e1f4c9db608f19d4fb807b8e003fafcae700ac6cd762d23166960fce915db1a65e127c1257cc9d36eb74ed44c0214ea0932cd02ed0dc6435033ed0bb2e29f23877f36f24758fc46a79a4fc33b6c912a2a2892fff15a144b8bdd6ded28cc9e33bd6d7010001	\\x1ee33e45ef0e72fb85a3ce5cc7886635569ab8918fe93bac9d3b1710c0e19d2b5da5a4168ae717c1f9b0fd6f80694cba708b57a14b9e4c3eedd14a86461af70b	1676229326000000	1676834126000000	1739906126000000	1834514126000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
221	\\xd3913e2b90b6d3bc68a78f886cba5fee0ae896f9f4fa10141ceb3961f6acb241727c4638a5d7564d9f70fa5ebb858c25589dbffc7d6b642ef7750269fd72768d	1	0	\\x000000010000000000800003a8bacb02d911a503df2eb89ddef600086dc1956cf267305179470e39173a34fdd47e85e505be8832d70cbe4f5bc3b3df28ae9077b1568cd077d18a11955ed287147ac3f5a1257630c3dc16a509bb7a819223036cae944d76594441203e6141889fe9702a6b7196e482dff6b39c3e90a6f7bf477c93ba5f320604df88a71d7873010001	\\x14b8eab5703105cb1f2dd472312040c89db594456e48a39a177f76d7db1ab4582784123c42b4f1b67bd4304f588a68cc8cb17f35238d8bdbf1c7fa194045f50e	1685296826000000	1685901626000000	1748973626000000	1843581626000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
222	\\xd5753c47709caa4c6650aa9715246786da200c97e240bd3fb0fa4204f6e3a874824b140ec2155d1bb7669b7b6597d3d998d2d60b9087cb65d633b190ea5074cf	1	0	\\x000000010000000000800003d1a2d748038457ebd3500c9a59cc6fc3a6b92fb0c809bd004de55ead7a862e07a44abd5c866f9f27befa9b30728a65df38cc52f7eedc37387af1af0e2e7066698afc1ed224a122454018391c2e9a03f856a962b6f6e870c22645ff5a6bd815595fa4933e2849d0c81d77d828a7de0f37f5cca14bc4294bc3bede1a1b145ce90f010001	\\x0e50ce99c3f804571340598a37903b3985ce4a54ef46af4438984162abb1466b016b87b3a0f288194ead7f4cd738fcb2d1b43963202b6ae44df896ff1f85dc0c	1681065326000000	1681670126000000	1744742126000000	1839350126000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
223	\\xd5ed59e66127c2e393de4d26b0e369d72834a937d31aee821608fad5206ec51f279da85cbed7a8962db77f4371cc9136279191177a439f74b6fa844c44d42090	1	0	\\x000000010000000000800003c8d174a57433cd7c2259347f6d2e7ef2338f15e685d9a069fc22fd19a03f6f3f9b22a73537722541d1da422c6be6f195014b644b9ef50ca56659db0906b5dd577e9c76a225ebd60bf130ec3f45f0550a432cdb5b30c355cf712997fb5630ca36ca332f0851454c58c8deec3a1a5068bdcdf38c980ebfa4a8181bcafb4141ba7b010001	\\x87c8818245e1733656fd634153a42d34f90f44cc31b48cc42b314704953396b138451356b744fd76e6747b0b608bcc1729c7f198d71a849d1efe935834f71703	1673206826000000	1673811626000000	1736883626000000	1831491626000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
224	\\xd9c5316d60aa5488a0657c83ac096929cfcc035019210c22413d83c04375ccbba8938b167a647e50ba81ea2bcf1c78b0d85919f6f5cdf442723c06b289e2dbc7	1	0	\\x000000010000000000800003a17a7760ec42c4211f6c7511e2c9aa3026055e0ddd5e75101ba963ace1a7c7a11a99e412bc7b82a71541480aeaf5a2813803ef34818d9b823c9d98d1e24749dc94930f6e958bad86c8ef99a57d3c8247625a1855fac8951c21d82f21d0c1f744a12de11e722c57a3befddc27aa31a646fd16ac076d1716a1bd75234f31583d1d010001	\\xef002e6ac7a4dbe27e1f8859008253ea15f1830c94c7d220a8b6e86c403ae4b3262c606050e745e9e2951ef8327d260b9a39ecba2cc8b6e45f131e5a56e9ac0b	1671393326000000	1671998126000000	1735070126000000	1829678126000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
225	\\xdaf906c6deebc29b21a5c39cb7d75fde1bb1b1289bd4890a52b431d33c893ef7f70e93d501a92ba4d26aa2886543c29b8226149afd756f2379a6f2b2a7729bd9	1	0	\\x000000010000000000800003c1b77391cc3dfe4f5cf425cc541d926805759e51e6d530e37498d358f1cf8ff2a97a8e29d75fd169c0e9eb1f0378917507733cdf01355c753ad4a86bb91102c82ae131773a2bc760d3dc0e1daacc15f03204ac0e34150ed0b591da0ee2ddb68cade5803d80546270b83bf7b1aa92b8f88f6d15dbe01cc0b4a271733b4ae5cc97010001	\\xdcad03a6d2089bdd44ba4806178ace6b15b35e721519e2344e13a853248a38624ded34ae8c95f46411064eee3f0a8533f65abe4097cbfc354e7273875596d50c	1671393326000000	1671998126000000	1735070126000000	1829678126000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
226	\\xdb713d23fedaff5fdf804942928e6ce522066f3efd54b06959257f5f0250dbe5970ce87b38447dd621dd7edd263e2b603770c4ef9b536a88f6c4b7148ac3ce54	1	0	\\x000000010000000000800003b3e6a4b07df112e75136a73b3083438a4afd74bd1ec634fd32ad7854877773fa6875d54bc3b90a49e5906b19e8e8fadf57e63c795d5650ee3a26127fff2ac120c270cdbe4e23f29cb1ba27a2f9c7afd274f2abc931bbff4ec9cc00bfeb6a35878082e1c0d290e70b1c22416d1cf7fff8b7493e50efd97890164182261205cce7010001	\\xa43973a5c9fd94681a9475f969b6fba093f2efcec9337395fa6b376bc14f83b5af6a07fb617440022ba51d8994634c95028bbb2fa04c08110afed0fa63a24100	1665348326000000	1665953126000000	1729025126000000	1823633126000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
227	\\xdc1db62ad794f7070fa60be5963d67a9e32715e9a765e81aeb3dd94a2710ea7b83bcc1446aeafc4724084b608f6ad1b6dd39af974bf027229395475997455518	1	0	\\x000000010000000000800003a6ffa6bcd951f03ab90a80790175af539f9a84abe3f8342cf80aabe4fb0d73d2c28d80c1078b3e4fb78e5861ce6db18e13468d43fd9e7037c6f7e26629495acace0464da93d9382b887507ac16bb66e070abf643687c5418198eb9bd17bc8f9055ed7ee47697268981fc16f02adbbafe246e079e20d97b556df9bf02024a9881010001	\\x42906c28970c2a8082535d64656fc6ffdde77de599d6d531797a724cd118ac5239b271dfcc9863678fc88e58d293bd2a374ade6ad9c50fe0cce39db4ec56d909	1688923826000000	1689528626000000	1752600626000000	1847208626000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
228	\\xde0dc38417e850581b77e2124060a4f57b21ba6c8e9661430128d4fcf2dbccd597a552a83aa23f7947664ff1c2038e29b9ec9101f201fc18ccacf85db169bf65	1	0	\\x000000010000000000800003db5937521ec73ea8a3b55c742157ee9ac6f6203ce5a61e62f59e3f2a1b1fcb7b8a291d87b360dec041487ff30945d14e3b0e7b3463715c59ea51b265ec3915416af1be23190cc359f5292ed304a2534c9343889815d8a19fef5a9d55fbd9427a29971899f1ee03d59bf3374cba8085ae9fb0e9b9b26b33bb9bc7a62d83f7e3c7010001	\\xcc7db3f3c21be6aa9a366291227f4a9b23c0c69f589f258b25335117ec5f359c02c5d98bcfda5bef1643ef6ef1202a4fd8773897059ce252102cb9787c8e3e03	1664743826000000	1665348626000000	1728420626000000	1823028626000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
229	\\xdf059643eae9268650721559c540c7611d346127bb6ab40fd71c9eabc48244862465ad7bad76a0f78f6556f0dfd821ba60bffdd8d045bcafa640044954dd676a	1	0	\\x000000010000000000800003bcdfdca3688f9fcfc62d6a4e8664214572441fc025df681bfe5abcce1913d9be26670e7c1e0225f1b7f95414353f4e3db440a1c6fcf74622d5cbc0a975bd9178e189193cdb51bdccd527ab63004ff5b909e1a6579eae643486281932468b2c6f2c972bf262d7203cf160265d3f2050b8e9650e242ae176bb9ccc76009be8fb1f010001	\\xa0aa5a0ab2c44fe5074048200a9b6d2b3156507411b765a231ac942b41b17f4fb81eb84fd9c0228bfaf28808717c257ebd29706713a0236e7f8921ae19ae3f00	1675624826000000	1676229626000000	1739301626000000	1833909626000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
230	\\xe3c1df3aa0ab28efaa736673248a14b1f7e75908b46592b049e1a611865117482ac137fcef922b1d174c2fcd59d8fcd6905e4cdcd08ebeac762e8a2300571033	1	0	\\x000000010000000000800003db4e7185694062af3d2095e39201cfb26ac73e8a1ad6312c4ff16883e0cf81e49ca7b61088c4a2cf0ec4485ac79c080378584100c9023facd42a9b2dde4d310ab653af7dbc80badea4f478a1e95934ca9f7368ebfe907f8d0ada09c704de1ddda9a2afec8e6d81c39eabfddf1cea4a48498df9d2a3caf08de283adb1416a212f010001	\\x40129bcf6dff70577ec0f967e21e90d82e94bdd9c5f08a143f298f3d08a83485dc7d93f5071b1e0ef780b8e19423bd349b77eb01ed7ce4cba5ff45bf0ac5200d	1680460826000000	1681065626000000	1744137626000000	1838745626000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
231	\\xe665a5695ac0415d95af2e9945e4f02a0e25e69eefcf0f70003a73a3ba1fcaae5aa91d2a99fc33841bb2c25d3f84a303be9d5bca461c56d32a2a21b97729862f	1	0	\\x000000010000000000800003d585e997089b3d0f6132753bc2ff4ad520d1e1cc3e48884b7fb5e3f4963673b8b2b62cc4ee5eb100309e1ea7b3b8002a1313490b9215785cc7e89762d28a3b966610c69eceff30e779198d03c8168dbf967790310f57376b83ef5e4517ad0b73686d8c60e2602f9bb891df4ca7f067b2d5d6e653cb07880bd5adf4f9b52cbed1010001	\\x68460c6547552867c83414c1f0bdc8ece81fb610df8c4aa126c6a1ecfeb3636c68c95ec151a56de33227ac2efdd6a4a114878bfec0f3e28a7720fb64bfad560f	1663534826000000	1664139626000000	1727211626000000	1821819626000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
232	\\xe7e1c610a22b3fe9aefbedf95d51c9ab512a8fed8ac42faaa24f05ef4129c9b72439bda4a31fdc0d458f494ab8193f3918b755ce67d3d2543ee2566e5bd38148	1	0	\\x000000010000000000800003db68f4bfa3c32378f719964446f24c97920ac1585a4cde3a1b2596735716b385eec568b3cde5643e141f60c19fc78c493281840b8f300ae80c928ec7842278427b3f38fa6c71dcd369bbbecc8cc91218966b5e6d19569df13b47dde8d83faafaa72425170e42583cb0772143706df4c2b4837e425031d8bb662d8e11e571fccb010001	\\xe3e5eb563184eba5bb1f82ccc1daacb1468d974c4f43a3b7305d766883e1fedf413ac89c79f9ef410d99867ab77dd4380d1cce3586359397e93209355be5e003	1675020326000000	1675625126000000	1738697126000000	1833305126000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
233	\\xeb650a0d65ccb94cd8208d291f967ee467cda8f088e598176813f7142ab935fdf56a695c7c1998543ef43b38a7b91f684c77633620cd015c6accfcbab3f93e71	1	0	\\x000000010000000000800003c366d34f39c13d38b4f271314202931d46cafda6f914feeb0c483915e44ba18916fd9debc688f07663079c53d817b5128cc25eb62b214c08538692f18754c67f6f83ef790571b40e587f5b20e0ad82a9dfe0398c0a1670e76ed25463531763ac09b241ab95223b4e83604881bcd2553d1d3e535c101c98f583a9588c81c49d5b010001	\\xd7431c844d8fbbebf88394ef5f589c6888a7e75f00400aea21bae0b25abf75eb0a5d3a3f3da5f65ebb8a98fb34fd6e3d12d9d2c1892f8f54364aeb0e29b7110c	1681065326000000	1681670126000000	1744742126000000	1839350126000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
234	\\xedad1f128c02300c6d3df889dd28cd9e9026af34ee749cef2da8f8978a7fb461be07c6cd1dfe3f3434b9367060ea7b7d7bd58604c84d268b33bfa5907b296f6e	1	0	\\x000000010000000000800003b4f84b0f8a4181b92e041698601d9afaf906ec300a98e3bb5f5faa4c48dd9e1f1bb910046fad82b8b7b76fb40b5c01c2cf03ed2bb7980e9ee48b829019875c7e9b2fd1e6438fa4898682f91d51e8c84eb700b1b7809ff3acb059befcd9a58cbd71f04ead43b5eb6555e837a3181ed14f42f25f29757cecba1933dc79312aa247010001	\\xaf4ff2c80f3916484da77ad07062bdb358f20982273e36ae894a807b0c7316f5a6abd1e1edc28de3f2ec79cfb1612e51aa781fba044808b24fa1be1b3bcd180f	1687714826000000	1688319626000000	1751391626000000	1845999626000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
235	\\xeda9b14a390ebb289c631475800acd9bd79b9120a2534480dd640e028b17465ea837cfa744ed0c0812d597cc4901ab15a775dc4a4fe8ba2c474dee9cc06ebee3	1	0	\\x000000010000000000800003ebd45ce828624eefcd059f15499e132155e09fc2ffd0e3796775e97cd4d8adc3bc16859185de435041fe320a1f0a41cc31b1cc8646d55736223394a446f81c716aa2371f079cfe430d83da13e89bbeab9f322073e75b23f847f6c7e8012377032ce26777fb4dd8ac290ab1f0f3a5c51c3bd622093bbc9cbe0da23504c3cb6a1f010001	\\x6a8b93fc83dc25d3ed3f5fc79b632fa09b6024f5623848be69baae0e8598d2538473f0571ff3c453d78791359970fe878ed84675d7a2c8ec6b39d24915fcaa09	1687110326000000	1687715126000000	1750787126000000	1845395126000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
236	\\xee59e0e90e4547e4f527d6c9bdc44a4ec271f2b82fc79c9a2db741c4dfaf4910815c48c6460dbf61ff260f933e51d9a20d335dfd1075b781596256171158a42f	1	0	\\x000000010000000000800003ac41fedfd69377a20b6f25dc2a5f520fa3c3fb42685cca4f1fcca5c7be2f3ca8bb40afd111a4830ac6f78812cb9a086eca53194c7b0e76003200e9bd2381e01f82e67074744c93b3997db5cb527db06442882034545f2259eef4aa33685360e0d90ce234d5e12fc6091de997051ae4cacbdd923de1cf364fa06c736bf622df13010001	\\x1d5e9adc2b55dcda0b5288334e302d8a44b120ee5ab53774c7f383c283777225754b52e7dac1fb827396f62ea18c21901d21bb896c3612e14123e13ffc02b407	1674415826000000	1675020626000000	1738092626000000	1832700626000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
237	\\xf16942875057afdf9158692602545573dc3f5f8b1d647ae339ed52b0db490bc6383ebbfcb101be4462fe1b13c6a46428f68f984ef9c87f177ca488179b96a5e7	1	0	\\x000000010000000000800003d4bbb618ef6a3e4ce5c21a1482e643ae6945157f7ccac4c10dd5787497fd89847e00ece747cb806f6f216da2757d8b76d65d7ec3576fb86dc2d179ddf208189d4c6634111543d629faad9bae3ae4c7ecabd14427b5450b60ff21d2c59965ab9108147452e85e51c73985aa666d8f0e2df9a715df5865fa4f195602a7bddc684b010001	\\x007cb155a714986da99330fe38b27f6fc3eef68328f6439692b3f6eb30e80b74eaad1fded13ad19bf894ad1ccd7cce6d5ca4e5e5632a9ec0b61238eb6c3f710c	1665952826000000	1666557626000000	1729629626000000	1824237626000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
238	\\xf2ed188a8efffdb46452e958cf5a7379bcbd3437535743212efe3fc30250b26b48a7e6b2f3bd1cd769845ea2d7c01bbb80a2402a8b964ad24f6a69f8e55e83c4	1	0	\\x000000010000000000800003f25ad3b7f5754cfb294e78beb982566008e1712989036044e3071bc2c4c3e39f95e778174d1024f51c1c540600433fc9f4a44c966c858ed5f156aab21dc72cffb3a7b21ae4cc1568158bb73dbbc0047fb2908651e09d6538422b9456ec9902835cb5b0f6dba0e842ed032bd189206aaae75cb7e601390078464b6d466c673577010001	\\x6b968e6d880aa788c8f22b808b324110ff05e01c8f00cc36b2e2e0bdb6206964a43a651b525de8dc6447055eafd5ede79635ac974bd193bf693eac33dfa9b20e	1672602326000000	1673207126000000	1736279126000000	1830887126000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
239	\\xf339590993504b0391b56f4dafb4d39a09c7d77b32a160a189e3e69564f3df8bddbc6d509c5a492dfe24435898e5149a06ffc9b07efb971a4d44c0eed8487c8b	1	0	\\x000000010000000000800003c0dc041415b6e2b0872c43c540be2129bba0aad846c61dad4ddb5e37d62c28a4ec36bf12808b6dc1a22247fdc34eabe9b211cc31b699056c520bc083c017e6ddcc934f2356a35cc466b39a54401cd0c8b85b486ca86ab21b0295aef582487e7a69cf0d0806bba5b8f3abdbd7d950bfc91cbb259825e883ef5ffaca71be1eaa39010001	\\x3d0e5d9f50f0f8fac94edd7b8309524f70616d211ea6c55b5b8a75b9e0acfa9a67f9605df6805cc6293af143c09fa1d2f02854f28fbfbb06c9eabf2be149c902	1686505826000000	1687110626000000	1750182626000000	1844790626000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
240	\\xf55165ca705e241c9c022ec95152e80462fadc48364dd97c3ac11f900c01b78b9cb76bf1f0408e9e7b200af991429bcf1e578494e345bf257879ab08e22dc3d2	1	0	\\x000000010000000000800003e4dd403a1be45fbb36b3d7ff08753f4aef14088e2d9b80d29ab978f9561d49d12d0470807b1806305f5288e2eb9d0b793acdea6849b163e0117423201727173e5e5a8da33292bf45dfc67374be835e48f4d83297d3a2a72f5e2febc522b346bae7d7597839a9e680d9d5fc7bebe7f112ebe25bf615995ab6b448f71efb06a1cf010001	\\xba5da19135074420ade37c3acbda21f142758c6695589722a4abd5f46ac023465ce4a779b33b8398e9b29d88e62250417e5beb74f69389d2c5d2e9e519c9de00	1690132826000000	1690737626000000	1753809626000000	1848417626000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
241	\\xf77d32e3d34d1c1772d5b0ca977fd35dcea23321efc91502128bf435813c7554a98164c57e739675f91cb768df595d1e89263e8902cdc49ba049d269a6e7748a	1	0	\\x000000010000000000800003c07295844d8a02fecccd21f3e686dc635008f76c11debff59a4e0a9b6b630633138ea0627d8835cedfc6727ae3f9cf65a981ead600e40d25b49bb34c66dacdb231ed47886c1d223f152446143e48297cfc155c5a6ed77dc361c0be8bdc5b1ef1e200d6fad3637bfd109d146a24d1b7064fae1e6cfdaff21946dc46a4c4a63701010001	\\x80c6ddf8991264547a7f16b8ab5d9fc570af45bfd3ce3f711ea45d76179dd01c4b724ff2f74b45ac7a2734131be4d20b6a4fb4f7fa005d5241b683c159fc2005	1664139326000000	1664744126000000	1727816126000000	1822424126000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
242	\\xf821e6995f993025c4dd33e8599624a7b81c5be6e72cc0d3519c304e350bb0649d888cd1db047e76b5c1afa8abdaff0d48f330a2025caa7ab5caceb180702c90	1	0	\\x000000010000000000800003cb8093e821e935e0e1037b627555fdff9e2f1daeec032fd34361c9466a2b2a1a885562de5ddbd7734ca98b2b20243eb8e8d8aa3ee0f3db24ce6bbe7fdad9486effe78da266caa23b2a2b106ae1cd83fb5a0005ba95a3730ee0e9e70db4b23dd75bb3006813abe9845616eb93a1e95f7520282f77f70a8210629e4f33153ce13b010001	\\x2b6dfeb30464ae5a8dcae2a43a7e7d306c522dbade23dbce4d146b325d0eb0fd3da86f1e3f9dba2cda0a49ff4fb6bce9fa6e78242d5c22c90cb3fd9e2a734a06	1670184326000000	1670789126000000	1733861126000000	1828469126000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
243	\\x002607e1935b33c9048f9f15940c8e6d6d1eb866bbf514064cb066e50418eb652804892502ef75d7b5d5679904d67801f4518d34f9924bcb5d679ed2efc6ab30	1	0	\\x000000010000000000800003ac7c18d539cda92754738750bab887bf5929db94b9296b3fa3ac4eb0a76cec3c62a4c3f6329614978584a737a659fe91693a274c76df4220fec086beb5aa80a861305b0df94db36a8244fddf7f1ecc2c7f8da139e3c57e7a902b1e7b4c4a0ec1e71e5502a762bda356f03a747c6ac15029c6f110efa0e94e2d71ac268ff6b87d010001	\\x1eb1e53381f8bb665b3932f23af8c5f02be3edcbc0973ed2b7459920d40f764ccb5feaa70eb2d1e1d636531db234aca39b519ce035114d07a88a559b246f7901	1670184326000000	1670789126000000	1733861126000000	1828469126000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
244	\\x01de416f29ac15e6ccb93d04db5d7af804846b04a4f7b936e506c4f54db6fe222c36b4c60b770e080d6c55e74964bc2b817b6aa8278f9fbacbd3c31e5585d7c4	1	0	\\x000000010000000000800003ca253b49f72328f5a68179d20b142bcf949a0e72ad80d85c9adec9383eb711104165162868b7a3ac4be87ee3b737ecb5d6694c01602ecc30cf4619475f7b526d0316d2d04233802e17252de4a12186b729d2c67082e80f952784d5f71ab8c6b2939714fdd10a0311a6c36f187b34d8523a84e39734352a7678435398d4cf0bd5010001	\\xcfd75a9417b29a072f6c7316f4fa254e040344d88208f8ea5ace248cfe27c48d57838b45e9d36a6e4c38878f782e7cbf25bc0b91a666c4baff605c867119680d	1682878826000000	1683483626000000	1746555626000000	1841163626000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
245	\\x021e31fde3307771e02a96a237dd3dbb82c973d8a11f88502e774b915fb2b1d9f1e86b9e32f93305db48801f6d27c846f5911b9667972e966ba1f346fb53c9a7	1	0	\\x000000010000000000800003b434627355810731c9347b153f279024c6cbcf4d0ddfcb17b4b5d54d3be2b0e3264aba66a0e850c79ca39a710d8bccad2c37386148a684d95d78815cba179c3480544b4f5afe9d03d6d4c8f85416f8d6bd3ac5ae28a5ea093f168a3bb110c3d76bea5e599c8c1fcd338c611fb4411be70979ccafb7b345c0fc60620337bf003f010001	\\x28d7c7bcd8bc551367d52abd1572a72ba234d516e823d696f009b066b7b084ffe42b852fe448a22e01331b70e334518ad56d33ebbf13a75fc59377b05343d600	1679856326000000	1680461126000000	1743533126000000	1838141126000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
246	\\x08569d6862d61b83c3ca0669ef85a1708f3a99afadf7dad6e420c690776c3f0f0efd621b295302d070f76a8ae141d3387ee939486201988eb1fd68f7ce233c04	1	0	\\x000000010000000000800003b4758b531243aac591a2562b232cb8ac49773a52945e6f0db013d690a66335f135cd5a21f96bf260a2aae65c6a8376660bcde9f45950a3e235ef1f26855b4ca43561e164e5c3d87c449b284ee0db0fccbe51a88502d783e6a6edc0860f31a5566c288e89e43e0c9da1a7d17a3ce261e20d1b51c4c3811924e46575761a2fda3f010001	\\x582261d04c5c23be9bf10764470430338dd7e04a14b590e83dc742bf271b714168ec179c3e3317c91b4db60de8c9cd84629052ec02a69df9e7eb9d8e05322501	1690132826000000	1690737626000000	1753809626000000	1848417626000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
247	\\x09728e441631fd49c3083d4b43edbbab21d56f8ed0fb5fde04b91044270e2e89a9f41db4cc6ed151af097a5e783fdc1a495efa18e5061543ae071ccd6ec7ed80	1	0	\\x000000010000000000800003b7267d5b5d3f979308d7c8418afd36a5c039c27a46545fad6a3d3ac6b1206c8ec2e602eb3d340498cfbbf81a8a5e0a08ba8b75b1c47d70c59019bef8299655f0cbe229a4c4326a997104e5587d46a238614bee0504b265c767125bb344de18a784e6e706c3c58bf66a3547a4e223578273547d169c8a4119300ed4d31788a2c9010001	\\x47b8462061591da6350bde8209aac5c891fe3547fbc7f55a5c06d05e092dc26074958381ad4ccabb637e0a8f20db7a05eb76cf8b76dbd349584d58f22180c20e	1681669826000000	1682274626000000	1745346626000000	1839954626000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
248	\\x0d32e5846779ee3b1b8e6e08c6ddc6895e5e8fdf101af431914cfa81c503ec25ebb83caef26058b6177b031d121a539eca812f6bc54c5b2b20b659dee25fe4a7	1	0	\\x000000010000000000800003e874e935e3b8d2badd10cf1c53c7b84309c22e7d94b49c409d01cba40fbbc16260a65310d1684ed476aa0a2a9a3b272c47e1c08067794163bb0a8b450746acfefda828cc4c6d3b9c9f0f7f68c0c740708771b4746fbd889e2448fa1b3b2677c62e482b9db019ddbf93c3d50b5f43b93901c427f1a6b9ebe47167004a819bc423010001	\\xdc013369fd1de575624029332bf5defc95b31afd77b5ccf79e1b3dd8ee285eb80590e579dbddb1d4c9b8a6019dd512ee6fa5c9a9d4d2e0f4fd7b5a08b1841602	1691341826000000	1691946626000000	1755018626000000	1849626626000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
249	\\x14724dacaf5325f1c87ff8e4389eca555aa992aefe0492923bbae9264f74a8654c816b6b42177db1eb9de258eb919b49b7080f0c498094865a3d867a2e5d5c79	1	0	\\x000000010000000000800003bb5a2b91f7983eb06efeef832ac0a1dba2624164a96807591309d44c203b213ebcefecdb61dbfabf0ed675b796dcaced35fed947dee5e8fe776fb3b2c2753f26ae04fd8c799e9f6fc470df2ce46426571fd89df9817c349e44ed27553348f4728a9658ac8cd088987d911eb53b14743e7c508f6725226aca61b800a0a0331a03010001	\\xec342eceb28ff92a1228b72716d986f4eef427c66f0a41bc5e76f4c1c5ae5a33253e69a873eee8464f2417a0445b8dfc5bef4fa20d3ec6aa44e09f28cafbff08	1685901326000000	1686506126000000	1749578126000000	1844186126000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
250	\\x160248a7ae18250b94fa18b1365b43d4cf09cfc75f1591e7e3f72c65b274b21be1ba0fd097c2af272b144d30f40639cbdb7c718a7a37c4d7334b0fe076520165	1	0	\\x000000010000000000800003dca0d3b3bbfdb8325de72cd51998c96f0b59b03a3abe7d750c876f763df3a219ac17ecaca9310b09d38d0d5f6f2612eb8f825c696de8729b1d4966a2cff66ccb5e57e5ddf400dfcdef984464cf0e1b5617726fca489a1283bceb40303e6f7c1069ad71538d3d796bab48ee0a2cda187bc894bd1dc26f7a369e3d7f08386b0fb7010001	\\x8cc4ad1b2095dba9c95e79e80a20ea030c493201e42110cfdbdd3be02144e52c702cf5a854bb030cc0e2bb9494b21a645cb4255dfb66e26cb962eb202707cd06	1676833826000000	1677438626000000	1740510626000000	1835118626000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
251	\\x1682fb6b39fce674dc84ade1ca925f3f6ad4ac649f8317fbb60740b0afff056cb5519db2991ad6e6c6266da380ab60b40b28eedd33acb4f95ddbdd6805600517	1	0	\\x0000000100000000008000039bcfca77db79b86b546ff80ffa53ceb5cdc13fa1ee3ab1adaff700d6e78f613454dab7005f170a2fb15f574d8968db13c880aec17c354fa8465b0e4a0d36cde652424468aa709e74e84e4a991f70207b13502fc46c1b9c8852a8e5b2ca70bd7c64af8d05e6172d05241affd426989c556480c1826c5e51a0df7072e588e5e321010001	\\x1ba94451ffd6761dae8c77bc0565398f97dfd222770a244a47703a8fdc9b691a501d3086513452b168ef999ba3a632d0ff27c98240d02379d6f201394d7d380b	1668370826000000	1668975626000000	1732047626000000	1826655626000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
252	\\x177a0669cf2fa5a3e39145fd8df6cfabcecf9d5208b7041248810734a1cdd0b1a98c1ed37986c0bebf72f6bbd8fe57f06f22f3662a18e1fa70800581d25b5970	1	0	\\x000000010000000000800003e7c7da29fe6cdc8cf9f6fc4d76ec94d47588e7950a0b3ae17448b37d861ef509dafc5e39d9f042d0bb17a97dde6372eb31bed90f25d5a9380ba7b3dc667f237143a1f39e4efa17647611d00bbb860e0537e324e2759ffdbb23210d3f25922014d456f98a248215c22a90ceb41fb47b912b72d8d6c074e9385f7aa3a3b7497b31010001	\\xb93279b724214b45d4eb7065cf84cdbd2a996d429803a2ac98f764c425f5d88d4e81dc634d1c9c396d4fc0efbc75d5134dac422d401b0388f16224f1426cc808	1660512326000000	1661117126000000	1724189126000000	1818797126000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
253	\\x18de6821792c5cd2752e6d0ff2604bef36ddfee238ade6ec9085e469073f89a2196e5627704646982b061e341ce69468080c4b91d4f351257927d81eb6e97869	1	0	\\x000000010000000000800003e59ae39a1cef915c1434f942210a88a0a9cf626f5ce325ae7ed0bc33fb72f51baf4e26744ce5501efcc605784e89249ec609866bf5d6526ff4da724703da36028325e076626f8b5ad8a400179ef45db00e80ba9e2747132a35d498e2965113c8b5191a0527666e0d0cd995ab692fb16c1b76ea9d504c7fd5b929082f5554cfc3010001	\\x5afea4143679fd37bc541b982cdf8b4724654a23288ad48c16128f45c0444540ca59fd895ed7490461042880aa018fb798f3d7eee050631450c3347115204b07	1683483326000000	1684088126000000	1747160126000000	1841768126000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
254	\\x19ae250720fa669d1bd094b24d5e8551f5651e386aab7ae2af9487ebe5b9896794b2b5a108174c8a3ad031e250bdc7a29cbdf0e33da3fb691708fb726b298b49	1	0	\\x000000010000000000800003e9a638201fcea3459c3afbae809f2a1b215646fdd5ccdfcaa2d360d9847f2ba4c67c4152fb8381c2d4f6d4260a3911597d00fa1e16fd49739cf4afe2eb1930d2d9784fea1b037da2432059e2eb12d62235b47669903d9e9b53f550a519118eac0b6d68fd198d2506caa03e0aa0be2510b4d371c340111563a74a7f0f1eac1d43010001	\\x537959142575d5a916b3c45e9a60946e0f81e1fa1c89aa0e7a1be400f6a8a89d5a664ec76d8071eff23695147c6f61e92d0baf08de1c938296ad34d34d36cf0c	1675020326000000	1675625126000000	1738697126000000	1833305126000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
255	\\x1d2aaab570b6bc258f69c3e096aa3c455bb624011200e228de1bdfe9a9e2dff127a6c67672115b6520f491add450d2cd0bfd902fddd7df3b348e15560933e932	1	0	\\x000000010000000000800003bbdc50650f937f9473f6521d47c2b7811967be3fdc226974d6b6fca6bdef32161fb843a49c7cef11ddb3c518b62a62101e26f87f6891bdfd292b323923da59a5c53971abd1a429fa7e9eeb54b3d0acfd74782203614532d635850f5302a2927e86b7d953a1e84c10b5c15d5a6f7f82e568c30bbc44c9fabe4dc778ea3ada877b010001	\\x2e9f89688a9a6efa1fd974a283141cb3ab9ea71e3a3bf89967259cff5c5f85e770c07ee3c814dd74e156aed06acb4e4e43227127a43a0f220f14d6c0f7beb70e	1691341826000000	1691946626000000	1755018626000000	1849626626000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
256	\\x1ec28c28f5fec9c52d794c0698b5688592efb4b268d53681a653ce5da94ade2f2d25d84a844c13c8201a4b7ff5426c2139506dd7d8735230820a8ffb895689d1	1	0	\\x000000010000000000800003a3d68726c1b9c0b8fd2568cebf143d2d6c97e55b7e5439e6e62aa724390ce1453f5401f8cd4b300f2baeffb6e861a8567b7fd34821887802be0659296a8e65f588605df8c2bcd8e9494e5b4f6dcac50294c67a58b7f9fb11db760e157b06512887b224857c2b662b7174a4e2a641202225f4bd43afaf305b86664ebdf34c1c11010001	\\xd70a401dcee2927aac539063ac02b8d00f5d3944cb26afbec998286e1de368303696612898b5a3f39160ee1e86eed4eff3fa424d100cb0cc2c58c194db2ec20b	1672602326000000	1673207126000000	1736279126000000	1830887126000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
257	\\x28beb6151f87ca254dc6a7cad632c97e7c7f33ed35c1a089da12cbcb800f2605b78d5d811430b377dd373d0e9662137c5376e4e556339f0b6716a1957f169131	1	0	\\x000000010000000000800003be086cac5b6b7694059ba7dabb8a748a79070afc28a6031f9d9ae83c8a6fd27b4978bf948c2fe5901813d33a0e637f135ddf0397eb24799eef3f6786057d75bedb5b47a1704dddea5d1ca789f1ec6ae4a0218d2408b7d476cab896fe2f59e7f049b70d3a7b20f21c53ca3e264c5a9caecbe7fcdbf7bd5e6fbf9471956e002e61010001	\\x362b6584989aae0e7413f495c40e8653cde65e3f766dc29f2c23e193f9ec073f830438b308cdd6111fce0d258351fbf6017401f043165cf2b9abbfe477bfa501	1667766326000000	1668371126000000	1731443126000000	1826051126000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
258	\\x2856c75b9e5e0d7a5d103254d690b0bfad7a0c3397e3b53c6431ac417afca6b20e02d1f25b82494ce38fd49fdac8d85efc7853e7b851c8429476b2f838d0f271	1	0	\\x000000010000000000800003ce5183a7d4572843046e5f8bf76766bd8260bc5662d34360d6c717d9a830691c6c380264ef1a54e4dcfdb220eaba716f71ba9b8101445a863c931388ba084efabe124a0d7e6ae90fb43f80df3a7661d8a55eefa407b224eff254731fa53fc2a52f85fca62368c90cf64554acbeb003ea09b451861943822df4c4916f1c789cdf010001	\\xf72c5dbe3dd8439e0a01c646361330e249abb4ffe5a35dd9803847a8eb3995338a70c43661c17f20b54be2060a939f119d83e2422e3d313a34054109ab44f808	1682274326000000	1682879126000000	1745951126000000	1840559126000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
259	\\x2baaf35acafcc13dfe229de0e5402f9ad95775d4f0e8eeb1b702c188edd435e651f4dfcd38a76b414e4f5180c28b0adbb8ba1272ba010c890ac66f83890ace1d	1	0	\\x000000010000000000800003a47321500745d3f282b1e634403a1595854bb094ba04b456253ebb2497508a5c0b20de5282cef811942abc6dd55956796b19fc4983c0c357402f63222a392969457eaa53137403a1e18a45b2ddf13a7080b7484cfdd3eccee4928d5d8ffb69ca1ee806295d45374e4e4b4a1bec61583a16e9e6ed33c21bc5f7740776ea857c33010001	\\x6f6cac660660b09971f8e4e7dff87470e491fd71a7a909bdda887dcad342bcebbd8583fc71d24410974a6cf1565ee341b449f0c0aef1e4758e62d903b046aa0e	1684087826000000	1684692626000000	1747764626000000	1842372626000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
260	\\x2ed29353c1f39e385634f26ce6623900652d20f3595e032f924136a408f7f6ebcc8734040d812fbdcf41c1f81633881f08f2cf97a3d6bf3c9ecea94fc3c5b1c4	1	0	\\x000000010000000000800003f713b061aa7de1c055d86e7548d4e5a6cd019ad8bea0ca769ddd6a68fb166de2f3d89bbc92dc3c09a688d37ec879e0f6c947360cf289e32bd248b6d197d192db2b5f0d8bd555228179f34e1898125b341c8d5460476dedf7c250cd9df44afe03d91c4007a7883fce8d1f97e3d35f427e29b366cbf4b492aa2c97a07578efbe79010001	\\x6c1f971f45dc2d225e097eb910ce0e8749653a2465379a3f824cdceed9c882db157bd690492ca90f35cc46809e05b94b31b7ecb12697a2ccf7ce9b8929045806	1677438326000000	1678043126000000	1741115126000000	1835723126000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
261	\\x2f92190a1ff9b2f42ef44c2030ca00eb8bcdbd9a6efe0ec4295cc00efec0d8b30a97e161fae1b6de8f02306cc469a5fda47d6165a9f93aa04e27670ddfd343e8	1	0	\\x000000010000000000800003acb2dfe2065b40809f859f131f56f830b2c4687f9035e28ab566a00503e382d5a82b8a66f600969a96dfbece905b4db53846795a887cef473164ff919e49401029a3e670d0193e8dfe5fefbfdbdad9ffa76022c075a2420b03db8ee26c05461dceb80e2cd30fe22763f71ffae12b112bb70e6d11145928175dec89298889d18b010001	\\x4c0b7e3ec1cd67ab85bb627c11fc0a67e3ce59e3c839979318f8efa48d3029a75fbf930604ce9df172bceff492a94797a89e730fc449d1e89b8ef9128a72820c	1673811326000000	1674416126000000	1737488126000000	1832096126000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
262	\\x339a9aa1aba7971f918eec036271c81e1f57693fe47654d6f3021a268ee1dd3f29a49d39358c542f1174584b23c3a7fce660cdb06bea14341ea52acc5264a707	1	0	\\x000000010000000000800003ce0632332fd658f8cd79b09bf9cf33e7ebed20b46e81956828fb6e950b64056abfef5a6afc565b3dc7d9857d819be67424d7aebae655da598eec2edd6b64b41896660defb60605337e1274f91a42aa1e19645d75bea05c96f8857826fc5a2b94c2ae647d4003032cda7edc57dcb21ae17670853ad235a858debb9fc9df8993c3010001	\\x59954653c58e65bc530f5634b434fe7e339c80c4221fbde7bd74c7312ae0f7b7b9cfb4f5c098d2305fb5aa47aa6339bac38da4268f929c721641a2a388e3f106	1667766326000000	1668371126000000	1731443126000000	1826051126000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
263	\\x3616e5cd7e7f7a16703f56ac816873826794f173dbecfb10d9b9aaab23b93a8293f3c478f27b49c4de5f6ee45d251264b277124c276d4ee6998aad8d63785789	1	0	\\x000000010000000000800003dabfca2b41f5b87605e28061497515310e3e191af39461d3399b7a55617f2ac6948a644edc63f0ad4acc2f1d51637aef9b6e1370ed3736a563b880b784d12877eec588b7ce82377e8d12b3c035e90425f0814a7527424753db229eb80ba4849daf10982e10dff9db8db965c27aa7da374ce9699d4ea37406ef4c00a7542f892d010001	\\x3937c31b34d8e8e2af2d3238372b7373a36a0149eb46815bbf0ebf73dbb5f56af3cddf6333fcb0bcea1f54ec6fe329e8dd54c3fd4bd41804b679da3dc4526806	1670788826000000	1671393626000000	1734465626000000	1829073626000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
264	\\x36a21530d4d2895404b4f13380fd03042d95465731be55242bed0de1b40ee84a5ba2dac07eaa058075570017d9b374530fcce6e4af687183b4d16b0b2b7491c7	1	0	\\x000000010000000000800003d680d5f03d92978611ffda45f4131eab5432f11da762c2b828525941cf563f77a7de864e5d8f372de49ccc164ec87f96c589b57cbcb9e58dfb1f745772094f260d24c2aa218646dca0ff2e5c604b91cbb10ac9971783e3f1dcbe2dcd45b8414783530b328f87ff1bc3e6f97500f62437f55cc21076b5a64d681a1c70e24b014f010001	\\xa5cf40ac297c8a1fc3a15351bd28d82ccfcc4074dc0d5227d353f359ced2f66dd30576bee6d8547e7468c0476d93486f0aa9ab4e6a8f84139f3aaf898831a002	1661116826000000	1661721626000000	1724793626000000	1819401626000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
265	\\x3b429005bdb7a4928a1c9199ba3eb5191eea630e104511fbfd5b1054a1fd1e664a049943cf81f96327e7ab571d1d1564bc8c83ceb3c0edb60df6a3bee28b3339	1	0	\\x000000010000000000800003b3213d21b179b420fc3b707c7957809c056095672c274a0ba2d3ba72026c5f7670d564539f453e76bb74e2a34d1396b6d4d291832062be666a423528d60d6640f5a17f2c8c7393344884e129b4b971c7001bf5acf743a77def1454b4cb1c18923b473f84a631fad2748087c62af419334de6a937470997fc9e6415dceca32693010001	\\xbc5ed7d56a1894c4c714a76f649f2fd942880673b4023575b5ceca0358ebb189f05bb6c5ffa5c3d5353cbfb7a227826187aff68afad09bdc9c762f8a9d3b6404	1675624826000000	1676229626000000	1739301626000000	1833909626000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
266	\\x3dc636d5ca75fb845cdd829cac1f5c40deb027de687b1f7f04ba827216107fc60db39731aec829772fd1f2939afe247dcfdc97d35716459d96eac690717f594f	1	0	\\x000000010000000000800003aabb19e4c65c5c8c2d6879efb00e028687255499984bd0c9959eb86905f65d5ec504be4eb3d3832c679998c3dc79be5a2d73329ea749e5b471a5c140da1e5ef4424acaec619341cc8a3e69270dcd83f210f904e12b87c3cde6f7bc03de0451a552c6758039c8fec95373117899434e0110ac000f047a94bade8eef3a2d4efa35010001	\\x5a23f74747e74d4a75d51acf922f090052edc317eedb3a415f916ebb6a4c27f7d9e444135bb2a7dd572d97a64c80e379694f67fadc8adfebecb769e7b6adaf04	1661116826000000	1661721626000000	1724793626000000	1819401626000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
267	\\x3fca7a46d133261ea3f06500e3df1af1938d3992120afcbe9cabf3daf4e5e53bffbe6572a6e917e5de93d2327e925986db34aa9740ed8963f3ddd46089a436e3	1	0	\\x000000010000000000800003c0d1c364c75acfd69b8a6766cc11318ac363b6f3dda39c638a1f18ddb5f89db7526c76cfc6a330aae8f05e91a921bdf403d762197355bf2ec12bff7d567116e25e35fb3e9bbc15f4f6ebced04d1aa0365cfe1b56d4b0a68593fc04be1fdb8a838f36d2c8eed2576e4dfc81b70c7920497bc128e7dfd9dcc9eb14d6a4aa234e09010001	\\x3d15eecf5d25aff2314226d1bf92ed1a81edb47780f7cae875e0ecb1788b0be99cd5938e999a33c7d4bb3ce32a8e2b9ce89f61ecbd3a576f776b09e0f09b940f	1677438326000000	1678043126000000	1741115126000000	1835723126000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
268	\\x406a4f7d9450e6b9b3ed3b90a1e1982c2f072b2fade096b59fc40995c86cfa8ddca0631b8d45b24dfa1450d627988357026675edd3e085c2122c944c1b345fa5	1	0	\\x000000010000000000800003b699ee9cab1e90576fd3b240a6a9452ba888204e80575cb25d8b48cbf091a5959a1d91cb7e6b301562332e63909d98d110a46ad0329b8e78f4d3ed9493e78e226fdde9d9e21ece1d3665d5ad0c2fafedb8dcae6450dc4f259763f825a18f12444bff5dcaebba57c3fc123ea22f56aad3aead8f38b1cf17de7ad8562f92a8aa0f010001	\\xca4a586d5f32f75f0f00af7f42276951a90ea9fece7b9d548487747ba99cf85f4071fc6d4385e7a95d1545d98ac9aecc230fc0f51a8be6c0323260f2a4356b00	1682274326000000	1682879126000000	1745951126000000	1840559126000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
269	\\x420a580c83fd31979c3072c7cbd60cf6b06f82d71973e50b7b19b987008738dce68958588261d5c3a8dfd8f0518aa0d2c7f4796cf0752bb392cb79f3985db145	1	0	\\x00000001000000000080000396fdd642bc526ff6c80fa8eab03b55393ff799a42a835468cd66865b3441e5b830bc746cab413d892ad8915f3c84140938f4fa909494b2838b269c2f5519158c471c620cf1f2198dc7c23639bcc159ff95c5a8dae7eec5dae6c506d4ce3d47c4df566d2d07509e3d071eead4dc2ce7a6658dfdc648e4df4afa64bce0b9c75d9b010001	\\x4c91835e41f910a2c8c1c2b5350e8031635f4927736be7a70edd4394c4b46562a85d2f8ccb9090f141e3ddd02a5d2bfd44d5acfd574ca763b0c8eec981b99f09	1690737326000000	1691342126000000	1754414126000000	1849022126000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
270	\\x45fe36cc9a0cffb4ababcc2bcc86b62a2342a9d02a6ca90ddc583a1a60dd94b6ba4b48f023f2973e6b48379c2b9aa70f9e1c1ad389caea7bb976a54f4ffd64e6	1	0	\\x000000010000000000800003b06579ea9da4ceffcaadb682bf075dad5f2dd7189007fe984f5004c694c77f036ca08264cc2ffe9524606f08c7577d90df50abe84ee64ba714ea94b3688a3dd35793cae23b54e971b53e74bbcb2553b54fbb2e50fc7a2acda272da953244757da677c89709b514253449b06871b94477ae9474c7ac04146e0a5d11c830ba6c1f010001	\\x12463c9b1fba4ec9f1b7b665ec49182b9a4a3ed380cac3693dc30bf691490c7c8100e1a3bf24df879817c53351e7538f56b5b96ebdb12653bf0bc8ea6bb73307	1688923826000000	1689528626000000	1752600626000000	1847208626000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
271	\\x46f2e961e189d7c648ab31e2470edf96e2081b8b572df96853b57bfd3c96c78d7eff94bd2adc6abbaf538c26307e7a332fbfe6a723688a60a8acf5c3b20d8a3b	1	0	\\x000000010000000000800003b3833df5d3a8250f085080dec1a4fbff181bc34baf1daf42ce02b72ebd2f5891c35381ef276156e16d155c3ea45aa60299ae98d5b09453c7dddc9f97a977833a302776da36d0ffa06068da17ee0f65dde6073a09e067fcfe0c2c02a3c62f1a5de385ce6fabe450952b50e598397b7d91f1e14c5d9be05301da9f48a6b5ea564d010001	\\x27095f58b94520751f51f2677ab2fe2363e813f71e3a0cc225fffba5e4a930107aca669541ca30691371b594fb16eb0020c5cd4570533a9b0696ff4822527f09	1678647326000000	1679252126000000	1742324126000000	1836932126000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
272	\\x489a2932eccf00c63df87f80e87f9ae371bd420ca285e5f47fc184edcd81003bf37b8d7a95ad83129d38846cf63f542badb2e98300e4f5b501295a94f23030e9	1	0	\\x000000010000000000800003abeb67c7603a5d624f0992033cfcbc418073777ec886ef029d68771daa5197df814a778b05b9018dc352473e3fad55970b996d4df7324dd4a74029ad91e993462a8194c3d6ff4bcfcb3af1b3a7716392b675d4bb86509d8ee32e78da1bacbc34545014c72ab9d487c1f98c63a463bcc0cd021feb67e56c906ad918e7a3f17b33010001	\\x800f5a9f0866b8c754c0b75add58a8d3140c07319ce23f3bff817ece5ac5c52d3aeb26bd5454c396ba56d65d1b5abbe4c058993a98c697c4ddb75793b7b6cb00	1690737326000000	1691342126000000	1754414126000000	1849022126000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
273	\\x4a3e6bc18f8120a063b53a0617792159126b3237019aabf431d65bfc54e6947c15cfbf91c46718ef1089e459891471d628bb70225a7aaf608590281db049be37	1	0	\\x000000010000000000800003e97ff426084859db78f466462eddc71a39beec33bf1fe4797eaab09a04fc573be51bb702177e641e9847785e5c4c3a4ddc6a3a335949d81416680b7be744a46392338aad24d7ad66d3877699dc728ce32503a5e3b3c953e36195ab855fd6512edfd94c6269444a2c868226aae46427653de5412bda0848f826e5dca641dafaf7010001	\\x4c8661a861b8bb9518e506d1117f3fea250da6860301d31acf7d5f0ad4e41873bcbaa707fa62d7d7687e0b7f9ecffaec7d293119898567379abb17b057e7d203	1684087826000000	1684692626000000	1747764626000000	1842372626000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
274	\\x53ee60ead1eb1fb9e3e74fa29bf3999985b3086bcd5d3a40d0ef3d66e1301b4150f619f0d0fa6f5bc94b737d71619ebb102824e4aad0776b4b5b3a3d99b36cee	1	0	\\x00000001000000000080000396b04cbf8fd8d9d66dd16739dde4a5a759a95c0e28db25d2a24a5c74b6b79baeaa2094bf1c28d0d060544808de897a6efb024709ce501d8eb35229d2a93e5a0d78e06b4f053acd363b742fb8743ed497e95dbad2c5af435b41fc64dee71391d57dbf5fd6e2f01b6ee4248817af3b0e2b954690d6d4b0e4d1be8647f7894af57f010001	\\xc4f11ebaaed25701eeee7e5e875cd93073782292e29ab005dbcca593e44dde50dbe6980096479a8b08ac93179e7504e9939308c098f8d301e9e7328688d9b707	1674415826000000	1675020626000000	1738092626000000	1832700626000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
275	\\x5906ccd3f82f68324b6c314a696625316b17313d70a7b5c44d0152b898ba857104ad8c48b8c0e1aa5f121cdd6718fcfede6cc7a587b5817982ec2e74997a982a	1	0	\\x0000000100000000008000039e70b700c182c4d0d6f66184b482aae4ec6d23cfea55e2a8ce97a3f9696c28b390b363f02d7c4b190ce905808e5bb80a5a0efa26558685b5cb36f9a692b9e9fb7bca4c12253432926deb920402cd19b8186703e8a7098ec9ec280a73d3163e5987588044901ab41f44f17db7f04d6e5725cc0d1c1a6ead6b8efe4f815b225f9b010001	\\x861b996ee4a824feac1ba510d05b28a7600b57ea9b41535d8b155fb209a30679745bb6fc32bfb44b8856f0b2e5ccb0b78e16f9fb2de6243241923cfdd7a3910e	1662930326000000	1663535126000000	1726607126000000	1821215126000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
276	\\x594ec6cabf5288cdaa5b8d74759cac168b2029e20cd2e4cc2fe97958ff2fd71dab28dc6143e400b2d263c2ce4f8574d150422d304d8f69ba0b7394d07da65ceb	1	0	\\x000000010000000000800003c2bd5689d318b754faabd6c9ded90326f62f5808f67cac80735c62625c636ef0bb9ddcd2c455b50df019139834262c2bce8bfe7e1fc2faf22379a7befc220861d206802f484dda80b8a2413d3e3d445f30d80bedbca79578e7d485c57f6a540a0a3806cdeaf31fd970dd1cdfe917e990daca280a7b6a44cd6ca0a1fd6d8b6d2f010001	\\x87ce896e8debb649820b38027387f12082f44af8cfb0e716d4950dc5a96ee4b3720580dfa021d2c0fa8b125a4dae5f39b88bf57af808127b6b25a332938e6d05	1679251826000000	1679856626000000	1742928626000000	1837536626000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
277	\\x5a0e0615fc1ee92b2cbda795611ac76839598d8e81689dae8598a7f4e5ffd5155523be1c8d5917ddeaa1f06000a6d21116f4e632edc67368a7b1575e4de0f75b	1	0	\\x000000010000000000800003d13c410527244b4d73ae36eef21f185a2fab2705c30b2ecc838e6fb902c9c8748b2dc2765e353b08fa9139614aaed686d0c40beda927ec9b75384d4d52e95d663c324ffc304a56ef8e5524a0b1e027e7356c703b70b06dcbf5b5fa74e2667fade570ee676c70beabd4f23fa5702a8527f6d50711af674dc37867605bc137e83f010001	\\x8bf306d5307bc840482054547721b656ab4dc54bec80535a0a9fa1df78230adbe639f924b688d73471dad3eeff10b4c3df9580dbac8236dd0c41c5ae5956dd09	1680460826000000	1681065626000000	1744137626000000	1838745626000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
278	\\x5b4ab3e92cf6e79d903c759b8f33ff7a820edb09d734114a8c336bb61e5849fc7e366251be3e1cf89be6d48f66a5383a4bd30f47b665218b64a24b6ac8a0e90f	1	0	\\x000000010000000000800003c9c30b5b5aaa794849339c8bc44846fa70e9ae493782989c22d7ee9e89b341f157198c0e71b61acc2bf16663b0a1c808a49fcfd55ed76ff9fecf9e517828258c6eb91bb9c00a3b8d6b6ae4b71a2c81462d6595e753941a419e3cf6635f104c5287b66d27a027a64746094d479e8727b7b374308ba2f1d16f1894daa95d187473010001	\\x70d4d1ad73c1faa355ce6e708775f81593cc7c44e9c7ad349e15a582c6b361c1e042459622b7f6e983b6d293b8f9c78941c16c938590d45cd5f8454a93edc906	1670788826000000	1671393626000000	1734465626000000	1829073626000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
279	\\x5f4ab076548f95628803aa971b024441d74cce2ce2203e776b382f8f7a2198d69344e604c9ae89af35b9e249e0cd8c947fd06137ff2f0528fd05715397e449c7	1	0	\\x000000010000000000800003e8c12ba727d2cbcf705838a745193de252eec22a561a36b0514ee39552018f513a75629bec35972d20dc48e320fbbe0b3e14579e14cd80bc843c1e901659e1c0d828733aeb89eb8ae859c76910c2a3d33e34ce66879ab28f6ff0a015047f30821d4ae458ecb58e36b6d9b89fdbb762887f152c02d8aa89a20a083b95ac8a054f010001	\\xd94e4a7d07e5e5bed6b07483486f4b5a5438590da7d4ac32194df73f4149930a2cec188702d2fba39d64d87d6f0d84b555b472e3b6720aa6b9dd9deb89d17f01	1681065326000000	1681670126000000	1744742126000000	1839350126000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
280	\\x686adbcef16f3cf268913696192585f9fc87b2f31d06b8b6912398d8905b998f12f5a1c576cfce690e125aee701d9bdb8565a3d3158db1200640284b8e568442	1	0	\\x000000010000000000800003c5df815aa16d39152b6cc016bd04188e3390e3909c8a13a4b5656f186dd1305d0f672d8cffed336b7d148cc47854b4801cbcbac2932abecd2d8399cc8ff3eb3b3d75193437b477815340a1a7d6f19907085dfff7c494a33f0f13f2108c5890848696aa30e6abbfd1c87138494105f29b682ca1ab75972a77933ebefd1a59fd0f010001	\\xd4a806b5575042997abd4ce640c86fdf95b46ab23ae7c7fad871534ecb946c9da968909465c08af65f3762a14b6e2bc5484d0ac2b161b5e47facc270d7334e0a	1689528326000000	1690133126000000	1753205126000000	1847813126000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
281	\\x68de403c3729cf049f06cc4e9ab0de5ecf2eb8398e78343198a74342f7af9b01b8d89a03d6e3df9d7504e462f7f721039b9e0428c6229fae9a6140b117ec8412	1	0	\\x000000010000000000800003bd440c9840568e517f7f2e93c8053c09a718042def1b78d6a7a72431d9b618f2853e3ffaf3964abbe3c9043d39bcd3bcc9120a5c7da35f96b31530f21afdaac7489a1daae44f0598e8f0f3c378a8028ec752feeedd0844ccf4b383379689f4fd9877f0fa35a5b38e8c78c23387a83767828abfac30d58409f88cbe9d9ef21b87010001	\\x346dfb67e33d8330131923969a9cbb53cea871e0d55c9eaf684f6eafc58d82da91016489b51212bed08c23fd00d812b77d7d5f7940e86b86de2bbedb2c5ce10f	1671997826000000	1672602626000000	1735674626000000	1830282626000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
282	\\x6e3249fcf69dbd810f61aaf5a88b7f8760334aae6108ac0916fc61aeabb9e8e4c72d1933573da1898aeff5838b7448d1a86f6507afeb29c77576cb49ed14b101	1	0	\\x000000010000000000800003d368ee770d6e8eeb4aefb7ec3d3eab30951379ad85708b0589ab85a35788a33799db907698b9730f8af2ce67f07b02f77eb269c9dac155a08afc23fb3cfc52ca133d4ceda1b2bc687bcd0f4a35b01cd4e9e19aa1d6d329ee4b942ce6cc2e1d79afb0f0ae7a448b3811e84f492df0f3dae64ff0ad32430a7fe563324fb32b315b010001	\\xd5a5c73b7ee6b076e7b51991f7e28e10638a59eadb89ab95e9c9564471dd06f3988afb16e291bc52fdd14041d01ff599daeaddcc0f234d1e123548acd344ce0f	1679856326000000	1680461126000000	1743533126000000	1838141126000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
283	\\x7486c23ee823ba227a0046ef2feffca8e4c502415859e631a0f683e3075cef1fb163b0054bc64e1e67010d05ffbb4194e292ffc2aae4770913478321be91df5b	1	0	\\x000000010000000000800003e33d588cf40df0382d1a10cf8c6cee009f4f777059963668256c30079847dd26fc7e56119cf3720e11f126b9a1a5ae2b2e2fae7d81970d78adb6a03e563dffd8bddeb17f6e15d9c2a2f43fc6323eb863cf5720616856cf7e513e4f78385d7635f443a3e90d6c53ada4e0feb9157f20dc2e0eed0d981301972cc6bf0538fde715010001	\\xd588dba8386f9ab85e4d54180f08db3167bbd7609d4244a3d1135c7b992ccfb9ad2da6d5c3ca6e5032c8c3cbe9b052d32a64585d1f6b39c095b826b5d439e40e	1665952826000000	1666557626000000	1729629626000000	1824237626000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
284	\\x79aae5bce1050ef05212db40b0061685286646a88a6422e44d0155f179379c457bb6559a2bff1cd00424b8a8a6f9fe55a04d2f8505178aea9dc5c9df40d1a28e	1	0	\\x000000010000000000800003b65452132c9ab46b9580881eb8aee31de35f6f623fd6ed1c5261c5caa20d868f79dadb2fe68a176ad69dd61fea6ba5108f9a1daa6cd5a3943310cd7baff22b21b212011853669e30a47a2515a529a6f94baa0ef37bb1a4f9d9142130abba2d2c7bd773fe020ead6f7843f754b5575d237ada1942d35cce4c4fa176ca5a1a01a9010001	\\x2616feb3ed7854749093c0e69ee24f20595b58d0d91181b79156964c1ac6bf2f59935cc78a24993ee769925012e06022f1ed12e6f496dd8aa3ea5e3d1c582c0d	1669579826000000	1670184626000000	1733256626000000	1827864626000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
285	\\x7cfae715758bfaeb883e81f233f56dc75932446ba76162a91da0f47ec834e9fbe12ecc8a2d10648e290233134db1c6c0c5a1ac4dc799ef60ab522851f5cb266b	1	0	\\x000000010000000000800003c9501e1cc79aade07af5add31291c6405231f3f57d1121cbf8a2f2547a50e47bf2b2566ec59fb606caef8d392f012462ed955a0e78935ddbe16e55102bb14393bc88d837d146761660663230890059d14f8759ada8478a6d42da7d28f1f0e8f9ce60522e549551b3e5fe2833d019861db81801ece15fecda967053f66006ad63010001	\\x5509d17eab1a1c1f13dcc84ec2b82b61cec8efedfe5f2e4648a1d8b93a3e95bbe78f1749272c646223e20e9741127c480e5b598fea4b18fa0e951c156dd65f0d	1681669826000000	1682274626000000	1745346626000000	1839954626000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
286	\\x7d5a0d4d812e973692d933996550ed25681c2a806ead2a9aef690e56aaadc0678bc90a81a49b3825bd6d2cbcf0938529d620e035f79e67c1a3b3beb842a752af	1	0	\\x000000010000000000800003c3a90013e74d85c84a984cbc2826e0cc36d1c27fdb9d46b6269cea0f56016288ff6dc980e480d9272d670d6650c7189882ce85472dfb2295de5788ceb22b761edc5341e16943d55892b8ebd87ac011f9b903db7888654e95614c843ded1a652d6e8b2da141496a9d98e11e170d2778702569b8a13012bf9e4933805360de703f010001	\\xef16d87401f9d41adedbbbb83f0c77a7280e5461c40736bffc2e8c2daedfefd963bb380d2226014d755ea636d16a249f8ebae4d11d4d76aef9c6bac8fc6b770e	1667766326000000	1668371126000000	1731443126000000	1826051126000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
287	\\x7eea754d53eb5ceaa52242f1597819483fc047a3eebd387d8f5a1653c760de46e04aea4e8ce31addf12403333523ef8abadaf7dbec9074be26d8b8841f92feaa	1	0	\\x000000010000000000800003b2a29d92f548e32688f459314e5ec46fd5401e5cc13c366fbb2d2bad16f0feb86fde6104ca798a24cd4e16d4b8e784ca7d51c268f726e94b8257b27f39337f320919ae4e1ee87f123d2916629649308946aa2bad54748b0e71ef90aec2b60c0d4f639fc815d482f254ef31430559cc1c597616e0f0469ead1239693aff2933ab010001	\\x2d834173a45a284febebe240690257df5395e03dddb7958c3d74e72d4482eea63bf650825068bf01276ccea4309770af478ec55bf34857142f17c841076eb606	1663534826000000	1664139626000000	1727211626000000	1821819626000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
288	\\x7f96c90f48da0cb92ee0c307d3232678e9e455d683befc068f475713a9fab57a557666ded71a2d01c8caa8abdf82771856646c2dfb4f0cf94c23253e49c0fd58	1	0	\\x000000010000000000800003afec9d4b178769f49292782bc50a4b4c005fe404beec1efb65810b851cc198e041913b6b1ede2eb68929f04d1a7441d4b23e3193c5d0ebfcab1b1ef3eadd628db471b05c4c5911720cf89b23acdbd8b3f7a99cfa6f8a349add7bcce826b94fb962611e549fdc0e74f2e4621f1800fb7757401eb89c5eea10b4ebf48ec7456ccf010001	\\xee41ef79de577abcb9820e73c3e1a3ed58c49e48a1c8b330f6f1d2a0b9a2db03b6d3971fc1ca88937f4ef97aa385da6c9d5fd87c61da0e058c3ec0f64c844001	1671997826000000	1672602626000000	1735674626000000	1830282626000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
289	\\x80065c20748e1e77a793dc2f61b1e140c1e5a63f5dd6b1ecc6ac8f21e4654409f92117775977d5e94de4b539c8455a50d92511bb19fa325db8819c2e91528197	1	0	\\x000000010000000000800003ca56a1159a8a65dceef9fb6854a48bcc993756d0973e58841f998ad172e3f32d3fd1928a56ce3e7856762fdb01b9885c0ae2d9843ffe101f9f4c260f4a6cba2b70b304ea07ba19af9d734cb8ce13a9d0e4dd945217e9cccadb975d450894035171e46e6e75da7517b223de54c015473539d9213931b3515a72bd5056ad96d595010001	\\x49f1dfc6067dbc7623609c702f2f25dd1799f50f632e27c8c9a10bbd8a5a37f3336d200ffaf7b5153f105ecdd719b881bb2c8a2daf0aaa5b0580374531c44f05	1684087826000000	1684692626000000	1747764626000000	1842372626000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
290	\\x833e5e22039d6bf54cf0a1bd57756289dc564a4673924f68fc1a193c162d6d780d1580f882c1516ec8afccb719e41ef52eb9412133e5c86eca3974c3127c385f	1	0	\\x000000010000000000800003fdc1db770f7ea1f433c2b83716afae28c9be0c7bc808f8ecfdafaa5bcefc7dc3544553483a06bf066d32190ce19f9303f367401a138b3b1a8fedbd496c9b84f4dfb0a3a1ed01dae16082063204b0a7d094af8d7bec2a14d8817fbb8e9a833c52d6345d5366a4007104172c8002882f60ef59f89d38005a1ada19fc1084783deb010001	\\xf989fb0022d5a02b055995d0ad2ccc9506b5e7011bf2e8a74ad5b4f73d3e88a4146c749419b26129ccb708baa9992a213ea2e1f0ab929b9eba885eea56524d03	1676833826000000	1677438626000000	1740510626000000	1835118626000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
291	\\x865ef5cc51dc2b3735896714e34b48542fa2ec8f2ea4c4b0be192824b360325cf1dd844a42f5bb1e6fa8ac8b7b5a2429551c2263f773d3f21d5634b9e19c0ebb	1	0	\\x000000010000000000800003be340dfbb21be99aeebfb03ab62827516e3bca3858fd3f825c1e4ad10dc7643b4b95c04642171fa0bc69cf9d94b82b8a2f7e16a8ad3f9573810dd1cfb317b26fa6a0d6cfa0942322e3a86ae17104e03e2396319df828f011fab32df1ff095633083936eaccba4759396e0f37df8f5b355d495b0ad76def0ee44d83b4e9fe417f010001	\\x95bee3c1021cf6b40ea4d4d732c65f7355ac19e60e0d595d57498c9cae57407dd532ba530ccd264176d47857c46cdc2721a8688914a2ac2c88d46e086cf00e00	1663534826000000	1664139626000000	1727211626000000	1821819626000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
292	\\x8896fc93393f5293b570626a6900144cca95e10d080d3ffa26667c92f9a058523198fb88b42b6929ba38e8dd233e742db178c4d8138162471e2bb036f3132e2e	1	0	\\x000000010000000000800003c6c279e96a5fc35072b2d29a460de1c06c8cf77c213b4747e064baa51c4154a8dc12abfc19fbd54fcabe4bee3b85da6914a37987f6763f7117dbabc1a026690198ca4e79d4b122aa342efcb19f8c0bc132cf6466c4a0b2ba042d9031946bec572eb5bbddf04c62f7669289d3f330b84f0357662c409bb0dbc27c8286b9f2f527010001	\\x97a2b490ea094eac085dc86670fbe57669aeef3c86d04318593bdc3363cb397c4ba8828c6297f3ed26f3929f326b0a95b02b31adcab5740bb3f1fbdd107ead0f	1690737326000000	1691342126000000	1754414126000000	1849022126000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
293	\\x891a721bd37685bccd9ae5126b7a6661e6143d87ce9554e782a047acc8da441ac1f5caff8c01656ba103bf26a18d6e9b9bf3500385d4dc9cf5df315e6abc3545	1	0	\\x000000010000000000800003bd5430ef5d26e0b7496214f90d8015840e58aff1789cfdb90861ce6b714ab14c06bd4e4d01d7c8b478cee25563ee57ea51b212d6a0c0dae8c266eff9b903698e2b885f7df44b583efa8d0cccbd7adb1743a7a83a95d60f7e871e176cc272e968e51a55d96b4d62ee2726eda2fc7a59cb274130c09c3cf422f5570b95d1431e9f010001	\\x7e0634144c8407f565c32b511960f84036129a2b5fe9ad4bc3eb26f17e9afc6edfb6d7383b00116bfef061e56d5918450673c85b34c70451f0a622497d27d404	1665952826000000	1666557626000000	1729629626000000	1824237626000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
294	\\x9206294f725744ac5272f06990eb7a387c4d1e0ad666f524588350a60c0a8aecbb6cf9f64755e97a339dad6919cbc631989bb1fa6d2f8cae29bbcee0f1dad5ba	1	0	\\x000000010000000000800003b7c0800dd5beef2c43fdf0d631b4899b4361872c8366df55ad09be2854124fcc7e5f8d4ac887a8030095f67b2bc9ce8a0634dff7ebaa60434a6f15bd469287a0e156dc620a5517d1da397028001d69c8e323882b705e198ba3ba317e01422308ee1a65fe1486324af127c456b7674fe2d8cb283ecd02d5a1c75dd93be7144e3f010001	\\x69f79ae7b40835cfb7e7f2f282a16c46c43c359f2b5bd766248f6188583d04ac0fc62ef51f0bdcfba840f5733447081c8836c45489787e88a950d9b64ef7a90f	1681669826000000	1682274626000000	1745346626000000	1839954626000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
295	\\x9526f54363bba7e09cab7fc0f31a422f0c4bd1188934b3d83f774f2cedfcb7ba38da7bec7687e402f682962551e000b22059e60d1dd1626b9243de0433156d3b	1	0	\\x000000010000000000800003ce445e1919d088ee2a51d32828b192712fb6320e7f83704d923cd24a1b9659b4c2ca329b3488129d6c5b75f26bc8cdd288cdfcbd99b91e883aca05aa04a4fd1391a4cafa7bff0391db533c8d9c57b3306ba3a23d6bfdb5152072f5fadf7ff79bce989cc26c98f560177aaf3153f740075f5da07d508e1beba25cdedc2a39c479010001	\\xc20a262adcb37bf4d597410cb791daa7633709d8824db5fab820da21a18f6af3271f07a4c0746359008c9943f02579bc4b36144404150f1d5abe22b871af4408	1661721326000000	1662326126000000	1725398126000000	1820006126000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
296	\\x971a6eeff967f90e064271fb41ed0c8ea830069ac184436c6fe74b0938baeb670aa27336c694f5575a312b7ad46704f8af797b8b89ccccac47865742ea27e36f	1	0	\\x000000010000000000800003a901f955b942d14b6e5e65f2dcbc87892fbe1b083c7ecf09561f6ff26ecc75b2be7b4c842c35062e3055c7980c8792a0d608ead34dec1e30639d730ca4ff2c5d5e78d20eaf2ddaabfdb583fcc1d5478b45538a6ec24d0967da8e58772aa813ffed309bd095ca07d97971b7f702631f51aa4c04d41458273ff2b9d80adca45915010001	\\x42f59996512fc17da3ccf61d689a7ff97acb2ddfad9cdab3f03112e3e39ed81e15c343aabef8b84d9b0704beb819ecb92d993f3b1b9ac92edf20c2dceb32aa01	1661116826000000	1661721626000000	1724793626000000	1819401626000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
297	\\x9a86cc30747c6b30cb089867e1fb7d66a43762cf612ae3023512ca5dc0fd8d0c97f20a567a4564cefad05df851db84a1df3f57531d0c126a522e656a8e985697	1	0	\\x000000010000000000800003bffe9847f81da757c9734815395e9f371566126cc6e1f7ab7a5ccfab52f12a7d22dce67363ddd3068e670d74a30f881a8167491a7ca446a75e8a1b8b13f63725ae09c62361cd2d2b066c63fadc18326327d665490e7d5b01e91316f1de6dfc167698d9f0e8ec65dff09dde1f36b44ad1e2d9c5105f7caed1995ab0e2be7d71af010001	\\xbf85bcf13a7f1f8b633e2270bbe4d2cbbbc64d11a177c20098bb02ae67e2db7e24d06e612595892e02546a6b843255d19d276558d8509563ef7a6212c7c2d301	1666557326000000	1667162126000000	1730234126000000	1824842126000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
298	\\x9ce2daea748c50e04cef7689d23311883bcc0e50eb5ee56cea2cdc77d7c53c3125ce5d4d93493c50490cd9de4a5eb7544d4f039fbdbb4b1b34c8e75ec707156b	1	0	\\x000000010000000000800003df9b52970cc265f566e20c915b52a760d1b4c02f179ba4f969b39779732411e648e864679805a1ef732f3b0dcfb61346c8dbc9b41f2f7399d3de0d7b2283dbf65835b1063a5aa98582bf33aa34d0a6ae0b666d5d46966ff3d4bad008069d1696079ff51ad30d07054fde3a6b74e7a9e63a3e603927c14cdf36aaa97a364dd3e5010001	\\xd05e3cddd4e4779888b474d08801e29b7cd6766527eb7e4cc8560fd8b427d8fc40495056649be32c6e505aa205b56466671742daed2a77e24434b6f5b7d55903	1674415826000000	1675020626000000	1738092626000000	1832700626000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
299	\\x9d5abf2ca6845d97633efbc21413913c53439d30d3ec491ac6c10be4b20a9cb95a2a055014ad20dc81073c47c4df6047cd205b1d410d9ef80cac74b4a3a7f343	1	0	\\x000000010000000000800003a4abb3c345e1d442664d38a9d9cc47548cfae058237e9863c4666e223e553dcccd5a70e48170de3295373dff6c95159125ae1af0688a405909ee987f58d8ac9b4188a8236bafe3ef9088cc215b13313dc826bf7124fa7d86508e93b19cc1a7a0c435f1e4723ffce7412c4f2feb8e1c062bd3d85f457a297dcc556c71fbee7bd5010001	\\x2a48a6e58cc85dd49792c3d75298b75d425cd7ffbaa1eb6a8b268a8daa20f19a149c22e3173074448848644333889ddecaeab70c7d0fe152f25b137999392a0d	1679856326000000	1680461126000000	1743533126000000	1838141126000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
300	\\x9d4e6d430098ef2c29484e814c0494920c2fdbe5b59a90a2d059ab8ffaee747b71c4d569406fe96ca23b9a2ded066d2c9a39d1fece427fac2ec2f3357b63a67d	1	0	\\x000000010000000000800003f7d547172fb68eb655f1b24b16ebbdf723024b0ab73dc97de57413075d17f57dfb3b4f874627ce80b9716852d45de0b86848ac97063ec904cd5677e0da9d5f5c06ef4ce4896c7cdbec0c9c59afff3eb39506061a041386a83d2a118d29ebd0473cdcd2cd05fd40841141d7993ea00df3534602721e902f2cadf9ee26d1dff685010001	\\xab4d5e94fda1e41d7290a98da35e04a34471b5450b9ad18cf9dfe197effa723ba2185af5c3fde729cef3ff2a12b44cdf5af789276d2737a4ecee61d67e656803	1673811326000000	1674416126000000	1737488126000000	1832096126000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
301	\\xa01a65dc6bd967d5f53e344ecf23d685449b906bf7051c50b04a01e1f0fc69511e9ea77076dd4859d749d40368a801b938239e8ba4cc2c36a740c20daf6ee50e	1	0	\\x000000010000000000800003c209017e6c950059e064da6550268f8fd3a5df89f92220f7959e37d76cc83be29c67468668845ff8774a48b36993154830b5177fe4fe65a2358aa1f9eff348ba1f4936ad79c87aa05e9cb0d5bbed822a0bcf3e563b985ec3a8371cab632ac50be1573e816d8bc53af7ec80cb4226f7e5a31e9ebd57910bd5545c970f411634f1010001	\\x527c5805ef31e4f723f1953ce88fc2b6cd8462528da4ad545d1689eff6dfb9a185fc08a748b15be86cf9b957a1c72e035f6ba3d60a1cf8effbf85e7d2604a40e	1664139326000000	1664744126000000	1727816126000000	1822424126000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
302	\\xa152776f0b31abe51a369bf610e87d368c9100df5971bc06811128ab3b44fb511b652239c7e3f38850c7bb04d88f55231008c52960a425bdd5f2e35305ff779e	1	0	\\x000000010000000000800003a2aa42ad91577a6b56a8bc0d6ebbdf550c79a557b020e6d22730d9363acae541ee1bf29fab26030d90991f9833dab079352c469373025cee4ea7f3e7ec0dfd2a45bdf8d90bf635612c6180e013ebda5f57802873746f0c3b5082225e8df5e58083fdb7a85753e72ce742c450d9a843061c278d63f8df7331e1a61be1c02215b1010001	\\xdf9610fb9b9786cea1465b583a15a25e78c3b544897db215c3031fb35fdcf0cd3e9efe6e9142f1411959e6491284176b7a4ea931ee5c60dbcf6320e43fafec0c	1686505826000000	1687110626000000	1750182626000000	1844790626000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
303	\\xa1963847a464d555db315bfc6cbb19e337ba28a5ae3e0e16763ead2eb2e509eb8a7e778b2f5ef8fb6f5fa98601ada880a4a61f2e8f3d6791dcc64e70f6c0aa5b	1	0	\\x000000010000000000800003cd68d4a32ee7bd54287ce8e823521b7857972554deee4aef31dd3d1a973afa14683b36b9cc302b13a80933374f6f25c1ee7cb09b7d06a16e7447bf298b478138741d02a6a2a54269ecb1050c08c7333a506f487483b9dc786d35ec625b18f3afdfec460c435e185dc5c3cd61728003e86a397eff6e40c1bc627e90f68528f0e5010001	\\x87a4cdd00c845866c914d179f9d0602e733d2b9bfc26faba0c191056d876befedcf546bc3d7632d01e00aa02c7eeb78c26f0cd3df99406ab7477fc575ba0dd08	1675020326000000	1675625126000000	1738697126000000	1833305126000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
304	\\xa40ea04a7f84964c7d7971fc234bb2eb6323b26645c3581e7079a93a12983b5caa45e7655e30f2c952657ad62546b023170bcc4681dd8b0dbd2dbae2fbe6d11e	1	0	\\x000000010000000000800003a17eac180d8bd185f99b50ab8b2a638c06d3676b197e1b0e013807ce28e84a64c649888f722e58b659c563ee0135f447231dbca80d3503f34be4d575f3399b16f3e7294debd733480ac4798adf2714eb99fd5db415bd6fa8e1761ee9af718b9b92e1144df578f800185a5e4ee5a59e985a1b45a6f87390b810aaa9d966aa3f81010001	\\xf1fa9363c20d7bafc93c7d9cfd8a21b2567b23cdde25ef7a50af191d9babc1ee48bc124f8265b7208616017332410d49a37c351eb24565b8ad5854f22973a90f	1666557326000000	1667162126000000	1730234126000000	1824842126000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
305	\\xa7b680ccfa8e167446cd240229c28bced25699d912796c64da1da76039f2695ab760ed18eb01635da8416f331851226716e2f41df3055f8b088ed8035c10be30	1	0	\\x000000010000000000800003b350cba70740073a7eec454e1976e98590e92c526c1751ff670f1c981bed36c0100522d9a433dc1e9640f6496445cddd566ac600a19270ed055f856283531cf08f23f4ada4bfbd48009f5084db88e7b6e2cf5b3a63a4a8957d5484338063f0445cea2073f24298540196d9ec78b0ebe2d3e898387578cc4b3087aa6f0a55fb75010001	\\xcdcaa07d93ef4eb9accac55787f076adc33a658fa8f44bfdeabfbed2454ebba40aa8749144a1f3aa7890149cb821e04e30eb8fd0c95b043ad587ff926bf1e90d	1687110326000000	1687715126000000	1750787126000000	1845395126000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
306	\\xbed67f6d43151836f6b7550eb0a2b96ac8f874146471ca8e470df90bd0eb9d7089d01f1167c18d987ed48b881925d10d61b7b2286b60ab5f878b6abbdeeb6072	1	0	\\x000000010000000000800003ec7927f64d56befef3086438732cf7a1fa38a4d6c81c359bd293d2a6a606638eb8abd35235fdc6358b1e7596b1006aebaf69a0243cb3d2da5bc1cb58ddde09f479e6762a82896fd4947a267902d4d593dded744da1db4ad495f35b81b5dfc353439c30c53db8d5cb09c6b8d6a556e730a1ecd474a10a7ec2a917810091de8187010001	\\x8422b5586e1fb3a7bc4cb9671ae629e5eb0ce431c31db6631636d168f3ad5a93cded54399255666c8fbcb5d2a3afe97b71be7b35c5feb0ebf056dc11ea4efe0b	1673811326000000	1674416126000000	1737488126000000	1832096126000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
307	\\xc09e636146c93fbf4e6962fdf2f50063e7f13620f1a09e24e615db0c7bb720ec523641c82c98a54117eb7588c4b8b6c39714ee8402ea20fe878c969f283694d8	1	0	\\x000000010000000000800003a8ddd5137ef1b60a7785534e4b2830be9a5a2c5b64158e50d7bb88d49044b53224bea5e1c25ddea6c85f1ca21a89139ba485b5084799ac3dc4587f99de55648463dbab18e054e2b6a2721f88f247b14cfb07e296aabb87b13daa0007f2dd300b951390e9e302eeabd7f1db9647bc6fc633d07490a0493538e928c59eeaf4aa5f010001	\\xbf8a0359070a5dacd3bbd1259bbb80957b65e38f9a7e78fed16f83470d3b19c097a609a525832f203ed7ae731b1fe75f57ae5f38d6ac4775fdd2f17bbbe5770c	1675624826000000	1676229626000000	1739301626000000	1833909626000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
308	\\xc50e7f975af31a0eadcee16d2a6fb2779965210af1a8d1744da240182d9f7808e9f8b0faa766d59b6911fb64a2d4de522e323dcf39c425d06ca7d91722f4cc99	1	0	\\x000000010000000000800003b472d098c12483f065cf1e6ba1a3c731d247fbde4b8b752d99ec4a7d5f5cdb4970ac74910395fc08a85f919951b799333298f2c43b3b3bea162706a7997db4fa2e0993913b1725c79680fa7ec8c8bd9bf4c98205e42b70f980aafb3ef20287240cdb56474e4155c9a202d2395a116c4becf9a2e1313248dd07e32b5829f929f1010001	\\x27a563d2031fee5ed2a3cd2eff81d6c509017c0c630b1f8b9effc4550959e6a7c5fe852129335dc062be4013d192c264a9df7a649b90b19ec5db402ecf804a00	1671393326000000	1671998126000000	1735070126000000	1829678126000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
309	\\xd22ea06d277a6c6f50aa96256e749265b814fde99b71470f8e15b43d76798957f04f38da0249b81385d393f952592ad0460a0069051310d34fe9ffbdc36a8827	1	0	\\x000000010000000000800003bf3483eafac4c25b42f3a7dccb58e077fa55a30b46b938955ed6def58bb2fde61ec9fd07438095122613d3fdf9c38e846cbd43123a0cfa9aff73ec83f4424a69bec2470f69aeda2dc5ea7d1db4afebf54a215b38d8de1cbe8aad99e38970c456ae7966f433f88f6de8437b36208018b86d5799e58e762efd5e3ebcb008bf7071010001	\\x68abb7fb03f81417eebf8658ce4b8c43d65dcf4650d3f41d6370ff7c6f85e05e2851d6041efe3550ec6baaf66364157be0f4059b702e431d61c5f49d86559a03	1678042826000000	1678647626000000	1741719626000000	1836327626000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
310	\\xd4caa942a26571264df12fbcbb31a20c896f8fe97dbf5a02081687d8e78d79956d03db62975afc872d37bff15a0a8f494b65b8b73d76888dce7a415cf6c63476	1	0	\\x000000010000000000800003b904aff128c02a70ab4db0fea90aef84fdafbed15a76937809900c2f774b55c758202f6bf0a2c7661c7a251f5a3d389b64ec9ade4b966eb324b3a9d30545ad338368efd25339f5a8a04c640f3e0e58f7d2f95d6a75349ab035db8567eeae6125600f8677f0d0f3978d46bcd0b816298e302a3f6f45e8f48f2742898e4451de91010001	\\x4013f0138814890d58ca8de09cba51352b8b164e4e8dd13b6f7759a37b7f580b5ec38b25b545bb1497a4343ad3b95c9753262583412190dbd83b0021801e910f	1680460826000000	1681065626000000	1744137626000000	1838745626000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
311	\\xd46234fefdbc5b8f27edb45d01a520a99911a3c7d9b251c76f03e100ced614dde12230ad55b3966577d7dffe18c67e7d7c610395396fe2742c56c4b831ed5573	1	0	\\x000000010000000000800003b11a3a3593f33f6bbf65ed22d4bc15cd27e4949ab611372f71de5b3212148de2dded2b6544bfe9a637612c345ac27e96d13c62bee6784043e6495c45cd59eebcdff59e364065d722d69f9065f28ff8153aa18ec5cd4506adf85cb207ba7d75aaeed29048bac4c70f231b72c7360201d9749eab273b34f6f7c49b9ed5cad90ff9010001	\\x1b3243450dbd97f66459f5710f855d7179e607a35c23979e6030869a6cd806c24a9914103924f76ef64888be0accfaeee2b02669fcbbacdcf3ea3dd461acea03	1668975326000000	1669580126000000	1732652126000000	1827260126000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
312	\\xd56672bc06592e23f92193b6f19e2b8d34c5cd2bbc968b311ec4feab975d08cd2ebd7ad30b56f01d5509161d9c8e26496e77353b17574cd3863523552ef9f42c	1	0	\\x000000010000000000800003b3d4e91ebc533ad4652b55449f0bc800399ee5617b48ea099bedba66873d97578d4033f3a388e77e37d9824094fa83501169cb7a960633dabec73475c9e098a05690b798520dacea065a34475e3e8c555ea0061289c6081c589cdab20902fb196a98787145c15fd4552d163da44edc679a538084cdabc5426bed7acd77ffc391010001	\\xf598cb2f2aa52b9854dae947dc3a185c1ca7cfe69466d09dc543db1039c1e878e9b9e398f4310e37a42b069efde50f02fa6a35bff638f8c6a67169adf599fd0d	1668370826000000	1668975626000000	1732047626000000	1826655626000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
313	\\xd67a8752677bbb63feb4f374b29807dc048c1306ddc82ea17c15d3fa383d59ffb23a20fd4a159ccca9131b8f05d4de184e48442b519b05c40a8424da75ef6d1e	1	0	\\x000000010000000000800003bece8400d9009b584518195cb21de39346da001c2f96172add11f13c73ceb5a13692e4973e220b7fce981c1408af9285b7acaf5896725b69aadc6513e8f058d693e7db44993dd20a2f7856c5754a7b892c68d45a2d05f9348d2c80053f0e38f226416cc8e93bd4ebe3ccd464a2f877d5b6e06e5743ad64f934adf1b2c71c42cb010001	\\x9759e386a58c3cf888545dd2f20133a46b347f54ee8989664a90023b97348d0b0667d1147828ccf28ffbac8b44f17095c1e942080dc8c59dd4353d4ac6728b0b	1671393326000000	1671998126000000	1735070126000000	1829678126000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
314	\\xd966ba803cd4fe144cc3743ad8164fe291fda8008fc8744cf765a60f350b25cf60688c890c58bb1a5e9184b4bfb12b5230b8adf40a082355235ddc474ecdb4ad	1	0	\\x000000010000000000800003b2f886041f3a9f06790cb0de5a17cac369b99eca29f3806389de9ba6c55524648f35de4134437be051a6b3da33b297ff0ae0034f53d6f8cdc1ad344ea3fa7251eeca54c8d521c3822a23275e3ba5d2224d1c4805e9fe7e9009b15f09b86af0a4a981ea760eb8dd0dcfcda1deb62a05e778ea2798527be743931bcb2f2d3b457b010001	\\xc2df5f331df0141e75b4dd2ed3d66bbfd8ec4362e4daee464a045ac3d85fc21950905d5c7b07f5286edc406b202e1b340f05109766453c5ee613ea62d876690d	1668975326000000	1669580126000000	1732652126000000	1827260126000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
315	\\xdce2583aa8585a989a2140d4593ad9d360b04430bb3d81e4f8a3e86a88111dc2b27e927e405be70f9a690cbf8b949e6db9d45d712c29ce7ad7efd37530e523f0	1	0	\\x000000010000000000800003c3472dfc8de3687610e1c4864e189085a1aa8a6acb16522b9136bd5adc8498b2f49ef913c08ccd648268ad93ddbbd88d06067fd9c93fde2362d7e17e954e85fa02ec67af3b0ee03abf1c251020b503eb9de7b5f4e40292191860a8ee99ac4619148389a1a8dc3d34abb0449ef6a1643bac1f4e0981d335148a0e5943c4848773010001	\\x9667a2bfae89934d40357a1ab2932ca9f18d06ca4b03c65a2702b194ea0de318ff3bfebb646ae652c0b54a92ed13132db9be25565f03f218fe7b96aa38d96e09	1660512326000000	1661117126000000	1724189126000000	1818797126000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
316	\\xdc7e08a4f6d9ef61cdd87ac793a7c97f80d369d616a666c844ae879f0ccb74d15794a9cc02554074fc5aeab6f0c9e34c522b80c39f0520d6b60a845e6320a58d	1	0	\\x000000010000000000800003ca0b9002277c4b5de06fdd2c82659eed9f5ba2127e0e61e7a1576e465484cb9d02553b822759d51318569b9d3341c9dbf99cce731c31c230dc91cf17c08bfc076f49f6f99d44e17ca53e4814be08b504106538686022db9e40ffcdc6e4d8854a72c6a15feb337b94b5a7e4e8516662d40a4ef8cf4cd2b23b38e96965f98107f7010001	\\x74a4176fc8f78a0c8875a7454c1b0df9ae685599dde1f4d11991a18541a59a84d7ee45ef0ff3281f05b7e91303dbae1873f8011faa2efab7401721698d5db009	1691341826000000	1691946626000000	1755018626000000	1849626626000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
317	\\xe40a743f02329b7a07db8dfad32af46b6ac64aedd6d7f2fed1df2576101f1ba9ec80ce55d9c8c8cd95c8917cf5114a9b127ac4d6a99d86a4bc35ca66a7141977	1	0	\\x000000010000000000800003bf94ff9e87ca373baf2be48c0429cbc477c862a38eb71dd1e06dc8157f0ad403929af2837ca2d0e5521da5c8072912f86041351ae12f95442ec08281289f574840216bd23ef608241c0850af623cf108387495abdb828f2e48276a9e1d88cdba1432057e4cf2d2fd2694328750852932ed3210cd8dbd426607fe713828110b55010001	\\x25e79bf62ec7e3167430f6187c3aed5c52503c2830f7bdaa7abc009a818bf5f162d13667d55eea30092b328d87199dfb4e63e7e69faab4f234f6be3c35a1600a	1671997826000000	1672602626000000	1735674626000000	1830282626000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
318	\\xeb16cc5d21f8c49b4101d7399d8c34ac9a9965aa1ba0fe0cd2007f5c9e2e5fdf9a933675f607626656b8885bd9f1ff817f8e8ce38076c4efd0f1ce6a3640ab55	1	0	\\x000000010000000000800003b7bcce19f708303e46c13e25d671853ced963a3569907838b6c6846cd2b074337ca0dbe0468c5d647ec99b76d6fa0dca92541930986153758ce25acb870fdf47298717bde79aba92f97d239f76bdde174f4b80a8d070eab65e5c25eb57a62685e2e34e0e2e8621513d92191ac09b33254bad8086fc792cc41eb6d3ed19fbcc8b010001	\\x5c953a0adfe600478c9fbb65d597c8d220484e35f84166b6fa39c54e4b2ad4488868b2745a0c85863b6e525d25cae7511c65e5ace3c32d5c62daaff79ae0b807	1688923826000000	1689528626000000	1752600626000000	1847208626000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
319	\\xed32fbd10e22d0e4fb393b38a81adfaf9832c26a467c3ca1db1d831d4bfd7f343ec26ba9d424416a48567548315225bceff0181a810d6c170cbde75c9b6e0748	1	0	\\x000000010000000000800003bbdf6493d367b557defefebad4bd6eff65a861933683f830dce726a49e7aca6e20655d54d7d6bfb3ed0dd56ea8001481485b0c3b8b771715c5a7cc751bf78e5fdd005518893dcc1dae116dd543d6fcfdbb7b2fba0ff7ca055128a28bd2ef654c92470a9049aa2c5db17d3e344a4a42d293ead66a79a1ae9f605d9fc5bbd14097010001	\\x832670e1d2ab765010cfc18a914f233b2ef057a8bff59fce8149f0b6df243a45e958cd2370ebe62291ed309b78cb287d495d1ee8cae0885cfdbfc3564aef520d	1673811326000000	1674416126000000	1737488126000000	1832096126000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
320	\\xed1e99c11b493de53a855878700fa37610122860eb0d1d1d1a358a13eb7ed97a829eec96ba534030b79e12bb4af39b71d92a6bf850b64784e1a2a7a8fc93cc7f	1	0	\\x000000010000000000800003a8f5fb6a44e2e0bbbc60f092eac819c5296199ab69ef353d9079ab0527761029e1d5a65f1d807cc2e0119890ed1702354b756e3b565a7909f6bd39b0950dd79f6b343d1207d9f05f46d20efdd9cd451981a72523f66de588a7bc7b6f57ac3f707e026cef6dd6e39593aa970eb440d24fc35e330353b63127312dc2d4af4822bb010001	\\x86d302025314bccef802b247e306b5b7988045a85bb928d49827f79d51cc765608e7bd041a73e7feb7d9ff64d5a0669beaa71453274e9199f9974f59f36ec908	1668370826000000	1668975626000000	1732047626000000	1826655626000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
321	\\xf7da7a93bffc7b2967bd23c59116c8e79bc29ff1fdacf9887e674764807cce2714f2daf5aa4e5f25f527f45f5c1affd914689114b87f16677818ad8258e564f2	1	0	\\x000000010000000000800003e83de131e4ee8fbef0747a8b2377c1dcb85a3cec8df121fdfa01b3b7043e4f96d253334c0a2ef82969b1f7feaf01f3f99c5a9d64a9929d3179835f080d196d121fa5c70b7e01015ea79bca66585cb7f3f646fa385dcd5d2958e9bb8fc72ce3126a99fdb947f4801af5efe46eb439a03541b17642331441b74e06d65d5ea86a6f010001	\\x8b33870ae4a0ef1522db6c02a1c3cb2ae3976867362e39b42491aa329c8dff549d59dffb2abda7046acf311f8b9fb342fff612d1a664722f266711e55c4b060f	1668975326000000	1669580126000000	1732652126000000	1827260126000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
322	\\xfcbe20030f11cf1f049c4b6802a3c93772eced94d9c40c17490efdc68b0be1638e53b3412e55f680498448751bf572cf5e0bf7072e000d5d43eeebf623e1a3b4	1	0	\\x000000010000000000800003b85e78b61e86ece7042015aec22132ffb571e3c839e36305896a503ecb3d5ea4b2fde86bd4f65ba6772565c5f14390789ef5b77f2b8addecb0789a7413d61a970d422f80bbaf03f4726c499de243a3567bfb331db5404c5cc96cdb73bbd7ac8de0de3583917eaf9d7b2fb583857f71cd5fc978ed56c592147738742231c11051010001	\\xfb203f25a2fa64b04c4101d2d5a9bf330462723c3a8cbc89dd920ac05f4c421b7705f0a6a4c05f1dd5162fe056391265596b985aa075d63920e23c4c5412e80b	1667766326000000	1668371126000000	1731443126000000	1826051126000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
323	\\xfc9a201a56bea6dc27b49035b48bc36ec375663121518bc00c5c56456c7a656d38b532e7545ed8e58e304e9821edc27e05eb07b32026a1630c2e2a915a6b741d	1	0	\\x000000010000000000800003b5518508e7593fd9b381d5c06e8b2c42da184fb30dd1d41869c13829b593e158c63eecef82dcfcc0342342abebccb8fef16097481a6f555188ca95ac513190266d8232ecc2a1fbcf8f3608ae081c8ada830a8d3f35cda742e097435a7666561b2686c04545dacc1df333dfa3f4446016c5a0a04a87282c9142f2f3e90e36b7b1010001	\\x89825bd480d0c11dbbf7104e5202e22bb660f3a70abc5b7c512bab5ccdefa859e083b0633e81e8248d72f135f9178fca9b687ef86616652bd479ab1744528902	1679856326000000	1680461126000000	1743533126000000	1838141126000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
324	\\x005f6f51e56a8636a0f2d86b0787709d489c683d12f96ab989c36a526699176d72985df51db6b3fda3e1db8bddb109da149dab81c776c746a97db26c55122b88	1	0	\\x000000010000000000800003a061f2da31977e7f8dfe11f6a67889d245312b526cddbfbceb18e38eeda942d13f8d18f0c55ac957198500c13119d517f29e555186d332b05ca40d4782176f9e659e14c5e1c9ce80507e56af5a780c0e1d281ab7b9e2c03684079eb41dcf339f2e30fc612b34ddc90d1fc5f5c44c2542e80475d0eebf2bb2623bf3a80456cb2f010001	\\xa46eddcfc4afd410fa1dd511eba1c008fdef70dabdafa8934f7322afb49848e07408f72707436d0c44abf5ff591e7d3544932f91272abd1b77ba87ea8d7a3a09	1675020326000000	1675625126000000	1738697126000000	1833305126000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
325	\\x01bf936ae9eaa55b18d1aefbce799034e680208eddd852dec9d1db1ad43c879904f7d9a41e16e930b24f6aeb4d838733f46f39b50b5f0aaf51581e35dd9b07b2	1	0	\\x000000010000000000800003da265e8acf15d1d8330e28fe07547875d17871701ccb64528b5b4404d46fe6048bcda933c400fecf2186ee2962c7824efce8e2285c129d631e03d50ffaf6160d34301bbcd81cba6a4a987816e41f64ac02e19bc7ad5ad3ad5427a12f68ea15edac1c34cb7e008f6f3644d3bf6046fb90781e357494ba0a864e4a47dd203bfa29010001	\\x80975f5f39bcefd316f7b81f34503509a775be29663539bb8ed846bcee5a0101084ffc8a7a16d7674f11ff6cabd19be5492e9af8a99d7392b7ac233b96ed4e01	1684087826000000	1684692626000000	1747764626000000	1842372626000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
326	\\x067fda502971dcd9e1b300c3d472fc74e68611bbd93516ef5608798dc8e3de0258427b57c2efee01f04b42495c14e005558f66bcdc6c2f024b782ca367a87abc	1	0	\\x000000010000000000800003a0263c96cfec13d451d3f116e3d72d226e48faab61d484b136ed0fe5ebf5ff5a2e51dcf312bde50c8bff62fae1bf336952e03c2fee59e162db0a64c7aff9ea26cdd2544d7e8d754914b0f7887e183b15ba14ebe3f24d4f2510d53e171a25a8563088353ab6414cc4916000aa8f6ff4c4233d25dbf7eeead340dafafe704f06f3010001	\\x4b02a0ca8ff4188fab565b452c4ea5547b16babddab5f20f9048478131f36a5796eff6fe00b4cfd735dbe55f35146526c9dc494bbd25f9e1e1598a6a7f121308	1684692326000000	1685297126000000	1748369126000000	1842977126000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
327	\\x07f3fc1dd2f518274ac2e58f11524d8de14679fb60a72dab5dff1149b1ee5635070a91a5d1c7543990a6b29adf2664d2ffe7396be7dbc8c448674d1c217da1e3	1	0	\\x000000010000000000800003d5672594598835304617a1f8f168c038634e3a2de5995fdefa24130ae14f4ce69cf5532f656835a133c5ded038ef27931a0c1d67822a52b73fcce34c9f05850cbef55dbd6ff129a16147d66599ec0247abb0f19b060ab320b2d1be6eb7fdae1112e92854c1695aaf2029296788b56b7fdd80f715ea8d1402911c40e629f56c43010001	\\x71a578fbed26787c47fc383ceae8fd49fa6f688aea906a4ab97e35678730490a9b83ea1936928c7fac88e6c1d02d109f73536f96b1cd8618cad4c122a6ca8000	1660512326000000	1661117126000000	1724189126000000	1818797126000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
328	\\x0907a1f896723ad19267af162b027b7b0ed4bf1fcbb6639a8d97e0587c9eab8e8c9c5a7d92abfb98cf10d8a2fc8a44d1e24bf547f6d8940e8dc8b107282f4cd7	1	0	\\x000000010000000000800003dddff27a64a77748b69fe03c904a1c367a20c1a6f6c4dd83e79d67ba6a06e0544da72c9297aa67d1087d0593a5fcc5a5884689ff0d04e0072b1d7e614336f36483d38e65d7876afa6e8bfe7407eb4c2d831acb77ff9772f93cc359f5888a386a087c1ef2b815e10a6472cdac9fdef83cbc950254c5e647cb1821764d89c57137010001	\\xcf3bb4ec683db9ad5520c7ad0482ac0c4e9c88dc49b4fc0eae1992274404cc30f691d784ad80d276f20d9a155f0351075583a3935b64bc12ee168a1cd3f00504	1690737326000000	1691342126000000	1754414126000000	1849022126000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
329	\\x0ddf1bdcc28afd03c286f97bf615e2257bcb06fbbc449de92c41242c4885f04cf139cc1a269dbc689f8095516b1b183399b0af56978fc27721cc2f5501370a81	1	0	\\x000000010000000000800003dca7fe741b4814b06dce8023cd83ad736f434a3f6d2f5623919146fc97373a2094f195df5e49780904296892c4d43540c879e8c8b8b438b4f80f1d84ff440a9628e4bc73300e0587d999f06d82f28d9e1d2215b8d2c866e04d8ba4c2f411e9e1820330382c43f04980ab8e4894d4ad9392bb3006a7b67c9d2e3c77ef23d16edf010001	\\xd132dae2331d87f418819efcbe0e1c19b0577913fa013642e37961a8f47de0e381b7139f365875572ee5d03bb9c943cb27055765ddbc1aaf14ce69e4be4e3407	1683483326000000	1684088126000000	1747160126000000	1841768126000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
330	\\x0f3f1bdb78bcded9fd7f2a5140c103269d2fd0655b10233a4a06166ef896cd669f6e1f7e4fc57a566dfd26caf91b8044cdd69073b2ced203faa7aa03b0dfce31	1	0	\\x000000010000000000800003e19e1e55f6324d72481af85c6a646ef3d76f6184e621aa6680ebdd7b987560375c8b3a4f0c09acd9598311cf368e73600d96c303c330ce1f05748f41cff8c8583188f01eae02ab3f7835e6eeb58362a516ebdac3f2d86444dc556a14b77e312229245e06489760adfbf0be709f4de9d390de62639ef1974a2918fb4481e59fb5010001	\\xa6882ce3f97ddf6dcec36037e4da4f73b5a9840d4d8e814e3183663988b25dd0896d742f390623acf347b092e24654cda3235332b3f6eb69c1de2e4d8159600c	1683483326000000	1684088126000000	1747160126000000	1841768126000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
331	\\x114fc949d48a328477e71c038e8aa6bb4021816895a634ca1db9c969cea511cdfdc65bd48cd1d29de2ea98b5e428874e8c060069c15668585cf1aa35dd4586e6	1	0	\\x000000010000000000800003e186961a70d5621d52e1d69f88f106cf933de882797b368719189b581ea63eb2191de98a9cedcbcf1ce69519a98695dd85bfbc98ffd5651fa02069078624ed5001c794283f4b65d02f1bb4cde2a3affd20d0491594fcabe3a7e954b9d96963572801be54172bce2b1ec89dce676523ba62b4a2562fe7c18cedc2392a2b724e4d010001	\\x633dc5e59d0f8c38a98a02783b0da234c3294c4672000f16843d582dcc508f682724d93e7f61235de2f36bf22fc30a010a8712c196adb31b97bab037197e440d	1678647326000000	1679252126000000	1742324126000000	1836932126000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
332	\\x158747f0bcb6b90be2eec169bd9bf739290a67845ff00fa515608bdc83893de4064e37b58b985701a984ddbc86ee429bd6427af960e5f87fe167dd883f308aa7	1	0	\\x000000010000000000800003a6daea413b0e6595d550e18033ff9038219235a41c2ddce446f1bfcef6648c20583a8e7361ab0ef436e0717d5fd3777f11c293194d5b527330ac431208c1747f0cecc73ca6ea1adae2c50eaa9185bd49e8992f16fa1f97e94facc018c07dc916cd911e834cdd711d45cce2db923efc66cdbd677eb6cb435cf5492e4883c5224f010001	\\xd97bd140ccfd48a985988077f3f7b35abd8341eb9cea12fc26795bfb41834894d9244e68db797c7792cbb9031dac7a9cb72dca33f2032f9dee3f1075d0ec7101	1668975326000000	1669580126000000	1732652126000000	1827260126000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
333	\\x162fc79ff4eefc9d051acb68d4828d381facd2a2033650df0c8651fe65f0a767c3b019ce53b8892baf3e7e5090ddf8ef7307a422d586f8acc4e66550a917f2b4	1	0	\\x000000010000000000800003bb8839af63c37b2b98250e27a7f58861644265b965dc1de427a098e6804c81dbd01697eaa63ff94b7d7cf1d4adb784b69c46099967c04edf5efc4825b14a54f42f41007a276db4c5d58a82dc3eb51132bfbe311245cbe21e6d6796068670a23845750944a0df8f41c94f1ca5c21116b842b5683d0071fcea80989da582c497bf010001	\\xc5b9a299b51305759b9dc5058c53328ab749883e13108f2a8d4b64ecdb491ff5e33e0cfd97b865df9a0dbea2d30f04482d717a02ec8790dc45cd1a9999b98f0e	1672602326000000	1673207126000000	1736279126000000	1830887126000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
334	\\x1713f85f112138a64f2642fa75e0932be3e6a1489346a758b28164eccad4690a97399a3fabc1072ff278c5fd9b9b3808397acdd6db6ba2506cb11c2049602493	1	0	\\x000000010000000000800003ccaf11b1797cae4bf460fa89288c1afeaf683a950c63b6c70aa62ed03e5fd36ae2e6ca99be99e2303a23994b76fe5c395e8af3c29f7f601d359924e9bb3b2880a72868d7fd62c214f30802d05a88a8ef9f20577b623a3dd3380c9ec9bb8e7ef0df78ca20f41d89f2064b8d355869dc02c1b858b1fbdbfab3eac6805c706cda1f010001	\\x040e6c4391f43403044d104453fcccb1af3dfc40078fcf7d959432be36db119cf9229a40e27f109d3814cf586c83184ad3c98e07d84a5747947c83cced939b0c	1672602326000000	1673207126000000	1736279126000000	1830887126000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
335	\\x178f604b959f00cc8073703c25203e43b3f6bbb563d51463e5d7e167cca7091a3acd4df48f4fee9c601b6277043eed749648e0fb1875814b55089890f7960a4f	1	0	\\x000000010000000000800003cbcbf81054f9aa5f2691b1f824ee37d5b491b79ec9197cdd2e86c62a75b021b9d17fa3ea2f3d8b69c6da6018a32c1a37597710e541d90653d8e84c5cba1a1e4f23fdff584a7858c988884fb5d04ff6f682f90a0a4a769690df991d8ae9a62c994aa7df304609d3c5a7129e3ec9f5ff91b565ee898d2c02ad85dae1e4726f6925010001	\\x832ed35c7b036c59cb627badf522674d185d5a5232f36bd171a0d41bc94178d4ad4a3854ece5e4d0aa021e54f5a57e5b29fa414d403a1664a3b4c789cad74f05	1663534826000000	1664139626000000	1727211626000000	1821819626000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
336	\\x1c2bcc00f26808f322cee72456d705acc9f0764acbf02f56022ef769e0540a8fcf953fae8b1e51a603ceda4a8186d849e9de65302a9869b1c828125c58770bba	1	0	\\x000000010000000000800003c75fa201a990ffe1c79471930f8bc40a8a5f0beca8c2d0fed8fc381c570722e137f5e30da280507829f2cf15d66c54c8d8adba19a0fcd376289c7c2c7b6337a5c526fbf5ff2e9be0f0990f0b3a6768b458ecd3198f7098ed5cb7dd4266591e79e06f3b5ba37eab36e478652c819e35735e422d565bd10a9a8bd4289e832420a1010001	\\x9684c0033278c49bc7424590a3c94230a9cbbb9408b7702d52ef5f4d329a7d6029c6339305341cec714325ea6a04bc2198e3fff0bd3c415a36edea3d2febf80e	1680460826000000	1681065626000000	1744137626000000	1838745626000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
337	\\x21cbe300c34e5d8bf190a182b177c40b70d4cd3a8d12f03d29489871c3001e661cb13b6afac3686a68f628658d52ecc6b76dc3d584c26a7f6289841826f812bf	1	0	\\x000000010000000000800003bb2e2cd869c8ed7d10099e80aafe1eeb6bf16295a0d6e6c078154167cfe73d94b7b9ff7a1b9850b915acea1d246858ac542e403d232ca0ef5c423a82aa106b993fc2090a0ad8a526a647687277b73d7b976d5397abcb197c185b263e54fc57f487b15e273cda9ce022a6344d6e26a8c199a82e7af132cbd852fa94a3f66883b7010001	\\x591c201939a5f9a0f0d54dd3436d1ccf5f43e374e0eea550cbc4bcd077df6fcb5a1ab749a7fb5df5999312a9c9472ac23a1e6a13812d02648dbb1a53e3157e05	1661116826000000	1661721626000000	1724793626000000	1819401626000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
338	\\x23fbcd151fa4436448eadf8b474e278347a45f8729f9eabb856f994cd7c3fd66d6bda99a67d543b967973c18940b67796bb555eb239a3d5bfc594b6a64a0cd8f	1	0	\\x000000010000000000800003c0d308a4b9f70c0a2930bea3a9783019433b118ba51191093f16b325024a949787aec553ca798e7e273e3a3b93a6d19d84c265d4c38dfe5344bb38ab2816aa80eb9e6d1b8ca2100517d499546784d41a190466a93afb973e57dcb9562808c80bf986cf289338c6165ff137670395dde76ca3f578ce8c44c7b8b85e84272c7673010001	\\x037a0052931e0eaa80d01b1313a3ba529ca496dbefd637825962f98877b1e3908010f2b901d379c506c18a3d8bd58ad7fbb752f8b8c33e87c27c91033910e80a	1679856326000000	1680461126000000	1743533126000000	1838141126000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
339	\\x2853f4c5bfbb715cf795b4059a7aedaf8b331e9929915204c5f06335e91abf754c808e8898ad2feac1ec7adff3a5b81ccd36e1f283dd7a5ce0d7bfc414b220ad	1	0	\\x000000010000000000800003c7497b5d951369c393a7149e82baa2cc815458edad66b251209309841e62f4e47bfec7f2b82365617b8b389b86d9b3f419c1cb8df0ad1f08c43308d6074ad19ed6c0a175a8c77067bccbeb3aa2a38bc78b462fe1a22e8ca08166ae221a16f0d42d424202316863f636cbdc306a47ca6cc93a5874ab8a1784219521ce78da5b3b010001	\\xfbe2763aa1d11bfe056e7d8e41bda1c8f65dc0aea48b37bb006364135694f5e516ef6a13056fb4fda5dea655ffddfdd6bc678d8c634727211429364c1689e701	1668975326000000	1669580126000000	1732652126000000	1827260126000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
340	\\x2ad73cd16a99fada1b12b3fedb42b23c85e353bfd2e820eae0e84577933865711307b0113672aa2e081b94f636c22cd72590be25a0bd38a1387a987d164ecb80	1	0	\\x000000010000000000800003a55e065f77289bede52743b6d324c12f2376866dc99ac9e25fde064462ae2f89c0860a84fc1f61fb9cf08562cd9dc9932d03b991c15b800ad1c14ce7a7efecacd77dfb15b1dc98a91213adda9bb5d4ac96358c81dc745910a17b8c479e9dfa9e36f46d6ec3e513a8537f45ca9de0a506d51fa9b55ec009885f0115855dd110eb010001	\\x58b12164fabcf66b5cf1098a85ebcf94eaf60c631811ce710dd0e2a611783d47429447e9ffe933b0237afba5312c16b8bfc5fdd97d9916c0efedddd0b9157b00	1670788826000000	1671393626000000	1734465626000000	1829073626000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
341	\\x2e538c7947b6b0c69c040777a0ca27e6a95adf5bfde40a5788a8baae759fceeb4b35270866959de41fe3e125e045c63609e02281d59ae25f5627b069e90fd3c9	1	0	\\x000000010000000000800003cd330463522179c7de57e93c4efa4c26bf3f64b52b4ff19b4020c6398c62aeed4bc7f4b1555b6240aadf0faecabd640a581c097dabb31fbb598204566709ce9b6e333a9e24e4850c71a3ae49fdf2ea38e1c4b3aa8ce1fbe6627c08b99eabc9de2e2d21a9c9652aac28d0b69505439640e2562b62497f0b6daafb7d50166cdc69010001	\\x524e843d1bbae42025ea320431f7c16202e89c0c380894fc36cd4237eb4b258cf257ecd6d946a00d3e6e994f3eafec8251eac70fdfd231c78c1f4d6f9964ac08	1684692326000000	1685297126000000	1748369126000000	1842977126000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
342	\\x2f2b2ed141e25e2f35a3245e6576d63eee3eee43a995952c5621cc9435e0bcfc8242d5d44343c0ba9a673f09b6dab8301e336c1df6d38308fa8e62ab22e79365	1	0	\\x000000010000000000800003b2235a72330e55c3555c2a6dd7651dc073b1bf49f9fa690a2e15db207b1802d128254de75751b7f9d139701ef97c575e5c26d78e027a61586a4a0e4038efc59af1dacfae284e9540739d16f79a18c69e073350d5ff1ea1e6f3aed1cc40e403b3819c19c04e5f422e954db202af21cc237bb7d946dfc431972f6c685f10ac92bf010001	\\x3849b846e51cf36104610c7d6843d801661803ee3c1a9e851f70859e61dc1876b2b12a3482c3bcf57064f3442bb048cf4c7eaf42bd7ebf06331dc84b4c9be002	1679251826000000	1679856626000000	1742928626000000	1837536626000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
343	\\x327bf97687dfc59edcf64bc4967c9cd0972eccce91efc822841862fd9e8f61edc1d62c4144c4ecba5d0997296b064aad4f00943535229f5983e85dcb1aac6f50	1	0	\\x000000010000000000800003bc812da667a7244b499c04caecec6c8fade35e7294639cec0af7a43b812739ef0244202e2400935af38aca34655bbf9c6b6b9ecf1bf49296b708937445093d415ffa35106ebef4a060f55bc6af6f86449da6c98a284003c0a3edbfd68eb06478f2dcd0195d993a161dc447d1b2b46b123b7b751c9f07f96b4d8595406d491447010001	\\xa0baf9565ae2c7f7afca9d6d4fe2097a723a33e8ef5c1dcb939e99b00bcaee28f993f597f0e3a24d0d07330c5bcc9ad7f3d25d83a3b1311282c072e5c894e509	1681065326000000	1681670126000000	1744742126000000	1839350126000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
344	\\x363f86562351932eca1435e9528e0ad24c006a462b3ec03cd650b8c8564bd0b56e98d3b96ae6591241708cd9934a8eca69bb2e4e233b6d2925899d8a6d750adf	1	0	\\x000000010000000000800003c779c6e12db1ff344fcffe5f5a674924bf871bf73b41bfb7d046fb9bc89fcd40bd855dc9e55dc91f151920980a12dcb3b8beb6fb9e314c3f9974fface835214ec357fa11f6f558fad37e02dc614f8630386817ce6ac2a6f9b2b02659ffde3a03b6601b061dd134b9f4576501fea7f9c3ebe16f1d60da6669d18b476ca8c038f9010001	\\x98e118d7678fa89226078d0f27c68f54784539ef64f981212911b74f03937512317dd2585f9fde7c8b179f751fa0691d65f09ddaf434c1455937b2b06e03cc0f	1687714826000000	1688319626000000	1751391626000000	1845999626000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
345	\\x3977f2604674c0b3d6a7741dfb74086186d9c6168773d39f7cce3dc6660c9eb9b936249555f1addf41e7443874d7517f94bb3b30aa9bfcae61701d4e3bb91262	1	0	\\x000000010000000000800003ad7639d4ef017eb5bc0eb230622b73b1ea5310e4e88daf18a7ab7c7dc056cd22d098b251ca03a879673e490e073000ba5582fd59ccb38e4d21c54868e408842a3de7dccd1e92ed6d8107dd23deb60f1f0fac6ddce329102f9d888967b31e4af57e120af39e6f3d5a323d3cbf3ae7cc219566eeb2ed3a0c7241dca72e95dbb189010001	\\xdc79df61ca397260e884fe3bbaa52b1308402e595871f902448ce2e8de6dfbcd048011af05d56846998679e7699ccffb6d82534cc5a6c17d6807c01f71cb3503	1662325826000000	1662930626000000	1726002626000000	1820610626000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
346	\\x39ffffd64e03329d9cd2beec9252007357a7df0053138060308ca43d705630ebc7b43e784c68bb62ab8b23de62817c54ff514e79493c1eca5a5ff7b350b1887b	1	0	\\x000000010000000000800003d49353d4f282455689d8836a46c9ccd0031c1111ca087899a914b6cfdc8fee3c0e08cf37ed7d0215cec5e911a6f1a099b349f09ea4c8481b95bc5eec26e89a61174dc125c250d85af73952d4489a507360dcd75c8f9a0bb237dc943d4eefcb83c41b12873ae497c6358be2ade14848054181b2cef887fdc07cfd9245474264fb010001	\\x13fb237aca7c9b473683321f166080a19ce3f5f1cafaf0714c076396e2bccd8bdd1f22f0b82aa0fb2b867c8827396701bd5f1fcd7254a6589f94a04e7e0f1808	1661721326000000	1662326126000000	1725398126000000	1820006126000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
347	\\x3a4f74556cf44862cc0077d8c4bbbd56e3f85001ead603b65ea815e1738020e8707815b342b553a4e1cf37f9e540ddf369153957f0ee79fdfb0b6def212d4f41	1	0	\\x000000010000000000800003cf76eb56cb355fc2c707767817e5076ea1e5518170a424c29cd797cdb29192aecf00b09d4aea3da059dcca5157bacbdaf7c4c5dff27fd7f141a836bc2ff6d2443fc255cf17dea545a2b2224d6a4653bc99c92ff5c32336f0961c90b3eaa832beca9f03d2a7b112045976f8ff890f5b818c0880d473f262f9220960aa010c0199010001	\\x81bef791d310d948cfcc5286092ce87b8ee929b3c02a6097e590c4adf37475bbe1435ae13cb83487201a0fe70053ca468d6d1a20aca73f7c63c643d824285f08	1673811326000000	1674416126000000	1737488126000000	1832096126000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
348	\\x3e3b25cafa498045330dbbe461be6e1cbc151894ae3a28099a9b897a98027eeead8e3b06b7d6d77787f20a57c94d9aa6367107afa27acdbb3ba5ee93a97634cf	1	0	\\x000000010000000000800003c28497d26c83c2c3fa84f1ddadf2a949237f7ab827fc961cdddaf6d386ab5348f7d99e84e2d74fa783a6d2fff22d04e76c70e31c35a278a130739953a1962eea7bd9b6a3cc719cad28d1d3efe47c53285c0faad8689559e360a3b293840f097550841a99a433dd5904fcfe34758d782d2ddffeb359df96646d4f420bc671b6cb010001	\\x5cd55fcfc278bbd636211adad51251c1765b99a67a271db68073abafc7ba7ed502e2516b89711921ae34c90e7cad5a65a254040fd52b5a29833c0756eea6170f	1686505826000000	1687110626000000	1750182626000000	1844790626000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
349	\\x41efb8f03fe0e7f6c7ce6c99a7d0593ff5d04c9f45b127771f2c36e8add17b718e3bd60a6f55341ace8f69686430f8d8b579375193559e8bf6f56aa8a046590d	1	0	\\x000000010000000000800003ad025b03595cf8cf45b2f8730eac3d6925de0efe9ae28f79432787afb13dbb1183f6178d0c5074a7fc924aa7babbe3bb142826ad8bb6416d4ab1e9eed6b375f6c4a0a9ab5207bc7dccb4b6783fa79145c1cbd21ace0d179d53e31c8e8aa3780f214a767abd7f6f528d4e31525e3e6b227ce1e1a68093411a3bab2c551f8a2a29010001	\\x142a76a8bdb2e026e1b5832bedaf3da19326b47319619ce066d804806cfa8161f01f21a4d5d00315a40cd295d1ae3a05cda264692c27163da356c73f3cea390f	1682878826000000	1683483626000000	1746555626000000	1841163626000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
350	\\x420beac67a3cd07365de826423c6cae2e4255c64ae87714ae53b9bfe47c88658869e38933b953ab1ca3b73f17b5f09b6bb164b69ac5b242d56939e1fb8940e7f	1	0	\\x000000010000000000800003a568b9fe1b5a796c1e4e7413d2d2999fe9c5a44445f020dc565a6439b0a2b32516d519d731ed8063de288ecb628a9c580bc66d1401c8232b120c4904d8856f557009677e47161f4f7deb02404a4a41b9009646d638e3da30553756fa7b5fd6778eb866bb4933f068a4b1589462eeab998a0542dae3c990b68dbfe15d81220369010001	\\xda83799e7fa9b410998ecfdaca1d5413fff7821aa6fa7929f28c03402e9e41169b8ab9322563e7d226d2d0b9727919d975c9b4ec58c3935a9fa52d814c77ca0b	1662325826000000	1662930626000000	1726002626000000	1820610626000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
351	\\x4a332685ba5d48a28185c19b27a26589b095b51cd96d96c3897423da6b29051c93c0ce6960c8e43be8e2f459566426892a49f000a3b92f32184f50a141d2c46e	1	0	\\x000000010000000000800003b68e3960701a1c6e6910fa712bd4f01b3e4efa046c42e87e685d2b31cab76e2f814cde90b092f121b7ad5d1dbd62b2af9d0b79f83fcdcfb5724b69d24eb16f88742e590eca72f3c5ed0fe2b878684dd4ad4d6e5fddce04f99cdaa869cea56c51f0e6967211a0499c8af3ad529aeaf6fa5c40a8ec409e554642e1d074d654c173010001	\\x9aed9334390f450a8054ad133c266a08fa6d7086f9f64952f405f574d754de3d1bc80c16f30b8a0705f56c12df7a4031c35662dc302f36136d625e3797f3df06	1681065326000000	1681670126000000	1744742126000000	1839350126000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
352	\\x4b93536fc4f323304e0dcbb99dcc5f9215307a7d425a019c96a01ff0e7911b9982e333b64a1756ffcd6b1529551e3c3a023c077d111ea732237f93c74680644b	1	0	\\x000000010000000000800003e96cf6193b9a317ffcb5293cb7c42a91f5b43097772093565431774a85e7880003e3b977cca7ec914a5048d8c308b56c1b9b265d92459d0ab235c15003923ba60dd1be650294c507c1fbf4f862dd93dd7da7bbd41a21d8d89e12eec821f683de4e3646c0f634cd91824c924c8ea3252bdfe3b0d1fb6c1af5e218423c676bf415010001	\\xdb6c6e9f3a1f41d32d5df6d28a5d0eb9ba1a0487c0286b42ff83566f1b580660f48aa7499a3ee1e5cf7e92ab2e3705cd8a89a46943da119c8bb244d32f31f10d	1663534826000000	1664139626000000	1727211626000000	1821819626000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
353	\\x4c7bcf33d91afd7689567d724563eb3113ffab62109a9e5f118fec770838fa59c653154c06e794f2ba76128a0460d8392844a7454e6a1634970e9aa4a3519109	1	0	\\x000000010000000000800003b9c300a347bd4ca1f6325e9ad3c9ffb3241c2e7203a6b4680dbf1f7e308308a61bf3070f40a3c948975ec673552128430a022c91c9a7ff67d075770208a0f12e602f4e2ff9f5fa905d78ac0711b36b962eda307d70114354f610060118e6889953b5ff7a6da32e5bb01d4d60b2a2161cf84c67b039edf42577c15953da8c250f010001	\\x27c73540ca2ce4e14b0fd94aa54bc9c692cce88463c6084457703e3339df36edab0c6eb679e3f05846c6adc5fb3bf175c4d26bf443a38496b7783fa7125fe602	1691341826000000	1691946626000000	1755018626000000	1849626626000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
354	\\x502bb11d782172cd477c98f603dc28f65651d8af6e0a2fd2e03619336decae0d2f1750babde5301d32c01049ffbd2dea420cdf7f801a43f7a121c3a18c44c6de	1	0	\\x000000010000000000800003bbde32fe9e4285ef18467380397c9cfb800a704c107ec790102135386953ee4c9c5ad18cde4b4355f3d8ce39959812689acb48aa2b66e4ecbec97d4b61357fec5c6d5d4a56220ad41bc3bb309787dc050772f4f2bd96e241d9628e8a7e79997a8b6b3d2ed6d3b45bd869db0df069cb22cbbd42d0dbde3f467547a9fd793f1713010001	\\x4b6ee2e2faaea82d07fc3d8bce875e3bf47c5f44e2ced810c9fe6aee251945f53aeb2f6fc757475f7133e4f79215ad213675a30fcb1f4cc57c4e78b7c2430104	1664139326000000	1664744126000000	1727816126000000	1822424126000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
355	\\x52abdd778486e2f4e79f1b860364498e98fa698f54f914d1a2de6e58d4472e6a37b6bebf5dc08298bacb380c6dbed62e661b7f08b583a430f0bc9551a3e6ca41	1	0	\\x000000010000000000800003c103a81a09788bb28ed4582b64fa75136d64f1f7a5363b4fec99d4a2d2c8398d78c9db4d9303c602f43ccd419465fec5f3adab1e78608d6c69232a333d981663af4b288d945914a29ebbd1b3ffb81bab6d99b1429f5a0d9992ff5de0ce2d133a176c704a41e56fdde3c145f8b7317d54942a798467472a5bbcc0882300eee829010001	\\xc5af4e02fabdb0c6f38d689c6f4ed3e4485e72cc601cc953c81b9e1fad5ca1b374200d9168e04513394c103c651eb0fbeb0e6709a163235cbaffe509673eaf03	1691341826000000	1691946626000000	1755018626000000	1849626626000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
356	\\x55cb8e8d89817fd73b5e1de5ad3a719eda4cfc95ac7fcb414b9ea88840bf58ae52f4728d3195a5c50cef0b10b5eae22b21fee9d4712779886b5f93c5d57b2705	1	0	\\x000000010000000000800003e18614abefa465b1c6b9718c990b7be60f871aff1414221ca18e09013fcaef78e7f092abd817d8acbbfdf0dce95c799c50f80b9eae148d809036806a10a95b8599740531fe1a8444b732642cedcaf0c2dac3a429bfd090e097f1e0a3a948bb8bb414f9ac513a3f192f060e5ba1bb7d05f1c9df8978304b326419c428129cb323010001	\\xaa5ccb7184894d223d02db57a61c9006c5c8c89ddb7b95b5e681c58e0cb176a331e418523ca319cb3399e6c22a3e77e006752f1442d0d0595d9b90f246880304	1688923826000000	1689528626000000	1752600626000000	1847208626000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
357	\\x580717fc26b717c9d35bb2f64f47d9afee3c66cfa83bb75de003fd0eabeab556e479a081cdf9daf167252bfc681597dc49894944bb3a87ac307c35e8c3c09a1a	1	0	\\x000000010000000000800003b40d1f678a7351bcc658a69ca6d285f3548f19852022ced741ada901cdebca08ff190a809f13e11982645dbbce368c05309013496ad3ad7b9925dac8b581071c787697e1a1feadedde7b5ccca94c46e3d3ffa23df0e41a6086f5ae1ef409680f54a326341f087718be4b15f969c5053c3f03dcfb62583fb2bf458e2f5b85ac33010001	\\x0319b2e3c8fcdb31137e0edc24343403470f50bf3ed11015b008d3e013ac25a9df86b35d44ffa35c57c1259c8db97a2ae3390a6e25cd83a51485044a5d8f5107	1662930326000000	1663535126000000	1726607126000000	1821215126000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
358	\\x60974c8a5f88e924f3f837b73451da7123ecb815b0467db1923ac9f59f140651d6158cdc1fa2c8a65aa53dfbe820d257ea94a6c4a320790a46cac1e5e2b66471	1	0	\\x000000010000000000800003d5dc56eb493b2c845cfff648ef5be5482b97a46b8d3104c984f6d896093ad254a5ee13cb2033654040219e2c5951911e94cd358720c606a5fde948f39bb569fa202b7bb2e807c4d21c2989141e026e09542999ce95fa3ab6854f80b2f7081750de9badf2ef668b8b1df7efdc356f6f8d814dc17a4d076d98950f9047d41d6bcf010001	\\x4943d91c4ccdeb7310494e7ba975f5d45a8fd41445b248f4ac61335eba46f3542ccd09162408046863bf96f22fa9069bc9c81cad87c031eb8e88ca2c91ceb90c	1679251826000000	1679856626000000	1742928626000000	1837536626000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
359	\\x617be6a85c5cc736e8c9dd88977c42965cfddab5697d652c94f078742975ecd8f56f810154152eb0d77592b30965e0f06d389a2a9b3783e0a547049c156ba20d	1	0	\\x000000010000000000800003df9bf0ffa148d40a61ece73e0f41604c0559ec694a0dd262222adcf7f8d4519059a59f479cd33c0dc3d7e88dea4faadb55541ac8aa53e9b9a1936a997dae00c2220ae9af016619f668b1776de575dab3cfaffd1ab35d201bb142e290d886cad8d9a45426efd3101c54ae2f90693339fc4d2e0c9a83ccdb72277c10e30184fe17010001	\\x13d76029d14d5c4a00ba3e5cfd99d16ba8cd353a38ecf403b6f2ee738654616a284c8c0a569eb7676627b221c5e871fb7e38e48eb049690aa980c29e1f39a10c	1666557326000000	1667162126000000	1730234126000000	1824842126000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
360	\\x628706849a15b32226d9c121b4b54a303bae9e469e4c53be2c5461ddc55f59cffec1428d5fe36005ea0b91636631ee8c7fb898598a63b514a719e6497c6ca5d6	1	0	\\x000000010000000000800003b2d834cc1db840a0e6b34051cd65c2b26f7726b36e448866b1260cd6a49f4aaa417d68369bf4eb38140b9b95d171764b2aae671f04c1074620629e5680c47ed255072d5ae16e86de08e8a749496f7960ea05d376814da02fb02bccd98aa7f184589bc36eba3dd4699c6224d20855e54bcf4e73d5702b7dfe81b5beeb5c78fa95010001	\\xe4340dd26b13ed07b96fa1c1be54f4e68adf430faf6f931b962bbb1a013eb95cf5084c88157394ce2dacf36136aade293534e46d047a4e91c8231a7e2db44002	1676833826000000	1677438626000000	1740510626000000	1835118626000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
361	\\x6baf098d501e61bc7c2a0213fe46af8b926e2522da2d0b484cbe0c239f4e9fbc65c3e5662b53a9846ed0aaa6b17e64880c170501188c0c39658d8b5a1dfa3af8	1	0	\\x000000010000000000800003b5ef720a26532424d297bf6ae89e5e6454f9083eae67b1fbdf69ed48bfacb9149e4e8a89b708283170847b39d74006ef8666de4b8c787a2a6ddf63d8f5571c6125da9ed165442473f86de4420f90595f154cf3cf8c8c13beea0365bb3638f14c686517e77d0eef5d3372dde9f3a38d6395c13fd4ef0b5b0cd9bf7148dd67a9f9010001	\\x6b9dc2a2ee83583fa20e7cc2a824dd39143e890564d0ebe5586615d2823506c43847a090803b829054e5f8bcd0a4925b80599ba3954316b5b604b541ec7c690e	1675624826000000	1676229626000000	1739301626000000	1833909626000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
362	\\x6c8fa5a9d6b19ef6f6c81ec004aca02c464b24e70514336f0e63747f26ddf578e5e81f5d907da9555587a73cc22031808a36f7e63c3eff0413bcf438f89c84f9	1	0	\\x000000010000000000800003b3ef13dc9c356bc1c3b69013a45fce277fbc8dbdb0c026a41815b22208f16d8afb3d4eff94cd13c08b77a8f530e7a9c76891e87244a815a7796d04438a14413e2f9c3f3ac3ce9489f147f9cbab6ab14425d30fd8401272f94b7dd80e76aa22a95f9b6e37d68a39e25f7b5f4e5da1dfe23169d43a523ae1120fd6cd22c1f76b9f010001	\\x3d0c273e665474bf772ff75c299ad617585fdc9d249c2a8b4d94dd45d274bbde4c6e9b89194f3abeaaa812e2f57c5fc57e5a23864ece954593a00cf3467e2c0c	1676833826000000	1677438626000000	1740510626000000	1835118626000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
363	\\x6e43f6aedffd338d722bbcd6a8325c9e2ea3c051bafcf13a09b8b97befe018e2f97255d18fb23d5b0a0ce0a41e0118320051e92516f50762e4ed32d09ce54950	1	0	\\x000000010000000000800003d61bd5d99219681641a8cd3bf504d0430c00a73576e1ff0bef676283ab91b5e7ba8f2987910cabd71597ab9908d917fbd3cc5cd2afc8914bb0e90f7416c2aa132664ab343d3c12fb668e87aa8bdff5e49f7ed2f4c7fab499d98d4319a260ba1a501841e7de40d3d7b5c16f96c573cd0c995ddcd8f04fdde50bac4aa584f9cf89010001	\\x380882767774c754d4124c988332edcbef76988ae2ef00095c83861206dd0bd7a3274d007531093ffc04bf4570ba2ad89f260df302ab12b7604cc2b452ca260d	1687110326000000	1687715126000000	1750787126000000	1845395126000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
364	\\x6e4ff96e999476ee34f85eba6cdaad2849caa9fa970139c6c1577b54520d556bad9e17de28ecc90081e3333a4f62db90b64d167caccb6fb9fa59c4752ff1e117	1	0	\\x000000010000000000800003d35bc33dd06c3831e27f35438a99ab08fc520a813a95d817ff0a6aa13f882db858bf28ccc381b0dbc8086ef75189e8144bce8489fec5494155403a95d4e359db824ebd2c8def1fd6b3dbc6c36b349d6f746cba5642d04e970444d290b03a47d3c0a8544dedbf5c010388794b970f0fea1f2113f55f91a05bf84aeac3404702d1010001	\\xbc1e0b24a22da2a8c13b29f787c93bac95d234e8b4e8526f9040872e3fe9d58dc722aef641d3cdd0833fef86e1cc43958fb2012f3caafb0b69078ce4ef825104	1691341826000000	1691946626000000	1755018626000000	1849626626000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
365	\\x7b77342bddb9e0f89ae3357076c2a80b7972516305ff3b5e9307feb973a967e381a85f1270f3b1b56591a5cccd12d54fe879db1d40fe2738be4fa6d8db6cec2e	1	0	\\x000000010000000000800003b53a02ed9371fe31d0c31fda24dbb83f991895608fdeb370e285955e57aa06a04146a876adfeeb4ed61f7bff7f95b426e4c879fb6668e3ad73cce326e44594a444afa2506e2221feaf8bd60a9b1633d859da1ee4467dc7bdf70316765f8583f960bb782de6b5269e5fdcac51ea4c2a0952c54bb43f96e89f57166362f086ef49010001	\\xa9da88cee1d4472fe7429f97a2f5e487eaa9156dc7f5fdb69eeb449e1db9ce5e4707193145fdb6eb9ade2f65d180c0f3d93ee7353afc91740f0103ecb60aa102	1663534826000000	1664139626000000	1727211626000000	1821819626000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
366	\\x82a3886e3c175da0e9aeff23ec546d1135c443732b4ddc7223cc78ca510367b0e93cad0d8820400aa4e82154723e93bb9b9cafcd7cf589f0626b9d609251e3b1	1	0	\\x000000010000000000800003c59cc592ab5c315bf92153d4209183c69927aeee27e928f7a4b6d1878eae73e3ba96ddb021e868b3c66d54e4959d7190d8e37753d0ddcbbd58d4cc306f1554d28da4c4ef584f1d76e0764607bd84e3a3bbfeb1eac12037b520e2281f8726463d08e454ca93fad745910a1040c4539b27db89c7f5156f4e2ed4291b63fcf5f34d010001	\\xa91775c98a658006ce4e0afcb934523740ffd1937f78082791a201874927a839c0ffb0c0792b19b4076e9bc30700a67f6adbcd52c9275dba4caf95edd4e47a08	1686505826000000	1687110626000000	1750182626000000	1844790626000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
367	\\x8aef82cd7f610747e8cf2c0e549f05d2d89f0031fde1b26f60f8e32de2834d69495ffc3a6a11d2b12f64c23e3dd4ac17980174d8969098186241f01d3113a130	1	0	\\x000000010000000000800003a461e4423d80574f00544cf3574037b94420d8a914850a1eed2be8d6ee4dd09dbb9ba52e2e96e6c71861665fc9f87b7cf7ed5e93e8fa1fc30d332f0a35aee6687af81d69e33e17b3bde4b5d946297709675b957d260bcf650fc9d3e847090183f07fbbb9379b964ceebe6c17a958531703e8a97cbd616f5845cc57cc2c078b6b010001	\\xc1b4c5676f78a6ad2cc24b3b1e29a36131a7d0d66650f12dedbd18b93763f5bcf1c4157b0d55071825de469d7cac870626433f3f01b4c2a684e4516e4bae890c	1685901326000000	1686506126000000	1749578126000000	1844186126000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
368	\\x8cf715ca467b2edc3683b394e269a036e35eedfbbd4c41aa2a21f8ecd055fd57c61f49827883edb5750ca4e40a8b639f3cc9fd53a03f1d42bcd2d362f09c79db	1	0	\\x000000010000000000800003e09d193267c6c74fd94155fa290ea94027186872b8e8f9744bb56b650b3cb31ed8dc3db663c0d87d3735fe73b7a771391649e4bbac429e1a12e939fed152fc7ba2c3387cc296b4b8f49674bc7bfff0651b7b898150d99dbcd7794d06f85716a9bda7760db57a5c9baf327683a60675a8bb0d8ddca2858d65bcf31fa13bb7639d010001	\\x73ff42bb4922a18b5d776ca06f49b578717a234ef20f16233514eb7f800e440f15fbb03f06a19c881031fedd17342ff540d1048a590209e3a035344ca160430f	1691946326000000	1692551126000000	1755623126000000	1850231126000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
369	\\x8fffe5aed787dba7e140d4e007124d3a4b40432fb5be9deea38cdeb166596d5f1d9a8d0b39228eddfc2b4c7ef594c68af54a6aa33598e39503a4a596a903a332	1	0	\\x000000010000000000800003d9ee8ff41243b9f2fb28972aaac6db1c3a1f6c432a71bc737d45c1fb8a63ba43b13b6917e3ba0a3bb56a23ed34b1bc3b35c33442b748b904de22f97fcc3adc9a95699e78363f448bdab68977988ff7561d51b24d1a1e64ee368b8240009178062e78b2ed5de15ed9c56f1c448114384a5ab92eb702f84325f89f564276a0589d010001	\\x167a3542c3de0dd8f5f22eba99b239ab8a991b73fcef010c3c5812dd8cb888684522ecb7541e3d14c2cf519b2be3bea0c3ebf9663624f8bbaf31074e34772102	1685296826000000	1685901626000000	1748973626000000	1843581626000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
370	\\x90db98fa0e12e4a6f3f1e4ce1a64bdf111ff36ea222b29d11c57900c0e867efc9984d036b1ca80723e8bdae2053c5ae7b9b9c8c44b2c7a09eeffa0b552895ed3	1	0	\\x000000010000000000800003bd64a77377e83572249bf39a397116172256fa03806015d24d1722172e0f8518e456b8d4aa8703e96ed0ca241af478d9eee68419c8056d67aae9bd40795c50340ff8ed75b18f49193e12ae8cb47a5f4aa27c147a514803b8572905eec8f4be9fcabafee64abb61ce9c661453c5231287c036806f370e83cca732ff4e9199fb57010001	\\x9b99495166c28f12e0c4ccd70d726d4c6884e7bf58e4d94613b54066c9a7367994722eaf2474b60397534f66d17be0136a0b62b4d9425bbce41c605d30dfb601	1667161826000000	1667766626000000	1730838626000000	1825446626000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
371	\\x91034f81a4a23f59c1a9a256aff575a3d3a6b92db2b96c66fda31618bfcb3fcf2b727c6f6635db1efb842567e7b9480e9012902bfbe919188cc9b774691dbb55	1	0	\\x000000010000000000800003b12e9a2fac38c045e865b6c5b38c7ef06987371c2d7ccecbc28f50ba08b0bfa63f3dded7eb75ee1d21d8937cf250eabf4eaa7808bcb2cf9ff1fe76896f80aee2d3367d4d7447325ab3e3592c1f2218ef31b2aa2a273e413630d5cfb178166a88a85d3b845fd877f4ef7af1188866064d6825a3fb514bd2e7077234023d30c267010001	\\xa97f63b19e35f9e6d84bb6710581f7254a5c3c534b026a5f14e744bab2e2a45e2372c23162bcc9f5563bde47cc043a75ea42d542841660d08c89f77103564902	1668370826000000	1668975626000000	1732047626000000	1826655626000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
372	\\x92dfd668059f017bc3d91d5a874d6b199b5d768e70a5bf2db56592e2204421fa8785f2eb19e427ac6f9ee76e1ee5e76aed01894e017b2fd002f569918dcf8032	1	0	\\x000000010000000000800003b9fdd9eb76e51a6ef8eaf007ca850e92557d30ec10603e4dea62c6ba831ab476548fa1942e7246f4abb8814a1c70a9ab98051cefbe2c67d2b9f1736cce7e7e8bd14a8edbf53bf2b4f94575483b066452958bb56593c0a4788aa124c0440e2981ad246c5acbbde70b41e355c49ffdd8f4dbd5334698791c1b7b5b1f41931fca87010001	\\xf280820d26eee31e07ff92c243ee313ce3e11374257aa26fb609bbde417b28d7c50d01048ccbb19a2e8cf65deea4670cd38a356e85e1d7f565e6c22493bdb208	1677438326000000	1678043126000000	1741115126000000	1835723126000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
373	\\x9373ef1685d4fc63c19bdd5b4c7c9e094e3d1ceba54005096854e3d04d3d2ca75561ebdfdf176cbea21310fc5dd6f67b5bbe53d66bf37abcb976409d87595b81	1	0	\\x000000010000000000800003ada3588aeaba318097481c0499b2224d1a3645f7382fb21f9d0cb13129f589afc6debbb6b22bd9d8989b9de0fa96ccc826c7ec99152d66eb66de920522d36cf524f1eefde9be91f581d1e5ac33b9ebc8a9e8fc48bc8989fd02b05dab131a5990ef02b1d51d77c8f2b0f94f471fcd5a516dbf1b5ffc0bc72b800f0812644fe371010001	\\xb51d82cee8978c7b803ac6b4e0dd8439d4eee26d35b7401cac7624fc7be054874270a4145bafa91e8e99f04c03462e88d9763a2844cd21b5aa5983e09e2c2a0d	1671997826000000	1672602626000000	1735674626000000	1830282626000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
374	\\x9cf3333538f62f6328b34faf9d2df1a7883aaf55b3bf04312532af944fc1e2d4b3e5ecac80cee2747a08d03ae112d02c6ad717f32508f458c096294eb622d296	1	0	\\x000000010000000000800003b3de786883c57224db571908246bab2d3b7b45265d654c98dfd9c48734be5cadb605d65c66d91170f58d46d82cb06bd90bb2548c1b11f07cffd0c50cef08ceeda0dcdbb7223c6bac7547e6e262f2fc8c83be8cf5e9b07103ca99d010df3f4c5897795a76f6b41061af6207708612739fd8f12449e47268028c8e589cfb0e6dbb010001	\\x2db7c370da3873e749c7ea04c0d4dac81dc68348ccd90b2ad397eb8e65cb8413d588f80607000e5f784c48db8fd941c53ae9a4ed839d877c8c29feaf98b6400f	1684692326000000	1685297126000000	1748369126000000	1842977126000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
375	\\x9e7b37133ae0dbdbd3dfd0f8f38807fcf111068054cecab1e167184db19a7b6293fdb5827fba3b14c610e91a0c3984c765b42469ad504b641a3b51101f9ee9ae	1	0	\\x000000010000000000800003bcc8a6940d2b46e6b40c73cc9f171883b9d18145fea8103c29f923f346fca494bae8e4b5cc42b454ce1970e39fbcb3b37d8dde07daa10a4aff7817427c21fc7493a31b66631d196a1af823befe6b8c7f72c00a854d4dbf6cc8a32574e99526a8594e33ad23ea767ae97669533567fdd19efb3a4967ad30b9bd0c103a424a7e45010001	\\xc0780d7043fdf53fd3dcd8151b16cf0b68ab7ee64d16c037aca32750a0b0b46918211ef02aab22515d48f93a49a21e047efb72bc7395c106f2916cc4fed0c30d	1661116826000000	1661721626000000	1724793626000000	1819401626000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
376	\\x9f63e5367d7817ac2eaebfbe6ad8482d85487a04d5a3c6cd1d601f6d50c37147ba0c677ee14a649ec14043f4478ad35037373989312828dfb6d0d6f36f0926da	1	0	\\x00000001000000000080000397bcc6988021367e4014bf4d852f1f018fc4f41a18623b4e7203544053a571580d6722494137f677a05ccea0906f47fdcb02bdc82722ecd627229c208df6e2ece5c51906bf5f58c722bcda2ec384330b391e7e9c8e73f35539f9f4639807bfbfdc522e4a896e3602fe432b4beda01b8150467e30a21e2a640116114cba374f23010001	\\xec9d7569b86472b64a1bf3efbf04764a9f29d23b52ba3130dc2bb264311c47170a08fef3626b70cf450b1e2d09d7724452485f11ad87edc1e932d2ae0683f101	1688319326000000	1688924126000000	1751996126000000	1846604126000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
377	\\xa163008f83be46f6f0245a2ceed37ab2be3cc9c2b388c8fbcdbc2c3f01f49d1292943bf1f4ad3a96160bad03da902a1d17382dc9d13a998a004bf23d30b57ebe	1	0	\\x000000010000000000800003d8ea402b5c41cae023fda3a517c87183cfedd1fdead67e56c3ccf8be492024ca2509824a45ced9283e79477af06bd67baba1d42599d52ed0a160e4c8b49463d95ea77c20157efff89df6bb7adc606deff7efcac26a6747b5c862369cc1a078546155aec4d2929c9a594c5a6713102f74e15266512c9f0e889f2b6219a1c0a529010001	\\x939214e092d74bcf045213a6957c0395bd3d3555dbc64c5b726a0cbebc8e3c693aea0a82f919f6b54f86f373d3e9ea1713fef3dd2d61f18fa5a8aa94fde23d0a	1674415826000000	1675020626000000	1738092626000000	1832700626000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
378	\\xa1a3224cde622979fc4e665cc00c85e67d8a7dc81cdd68a59901846f4dac1a29fef443a00ce8e5177fae87c156eccdd11e30b344f14f112e1ad872b919b4d727	1	0	\\x000000010000000000800003d1ad13aeb656a640e66ffa97cad76ef4c5905c8f263ddf3ef923226738456424ce1d6e38856b725c92fc6d7ea2a7e8319bfa0039e623f7f53640472c494e14320203e9610029de949afdb848bfbecd239d388b263c0f1839e5c254ef233553fb8278109113ecafb576e9472c6f3adfc1e382610b69fba22ca40b27403eea70bf010001	\\x8c68bb5f695620d00dbb4117cd9e910243898802e6c72d63a290383e7093bfe1f9826d2ad72294e787a93d8c1981dfac186c04845bf8ef787b62d54b6aec900f	1674415826000000	1675020626000000	1738092626000000	1832700626000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
379	\\xa2ff0a496a73d5cd7da8106aab3a75df3a252677757e4279e9f32fc6c76ad48a926aa62fb3064af89a8e291182256f40b0081415e372d3511788ab8b52479e3c	1	0	\\x000000010000000000800003bfcddac6085080c6089f0453dcbe6e71b0b67772dd4b7af37a26c878e37d32ba1525711c66eaa81b7404d88f6a04e019008f2f3d40b4e6e9c98fb285186611e50eb57e667448b968c522b97c8e910f929e423ccda879642411e1e6a9e3d41cbeb67afae908cd149cb6193d019b2d4b87914db909c78f636bc9341cbaf339dfa9010001	\\x0cab4fd04fc09bfedf518ca96cdfe5138984a897dd1b5895f834b2832e8086d3624195d7230fca32ef513dc0e6182a1d22ba31ad6af149abc749a28fec91fb05	1678647326000000	1679252126000000	1742324126000000	1836932126000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
380	\\xa3ff7b1e839fe83b5af0e471279bfcfe78d67625f4e047783d482f7447d70ca79cecd2451e4dda6bd26e98d3fa17569990780c9decbbcf85e8fb3902d415c477	1	0	\\x000000010000000000800003b749fe28aeeb439c61bd04637e8ce083ee43fe7b7be9a2746200389145829abfc4fa44531e730d5e60d2c91d97b2fe5b1f1ee0c376f01fc640610a3f72a9f4a1769764b93c3ea80d5a466c82eb8f43503bdff56fdafd696ec75b969f0df690e6b24afa8154760c195b9ee8c3ede106e83619afbf0b59eb83dc2e483ff7d1a135010001	\\x5e4b4333551547a97aee900785b8a7a8a3f130ecb4022bcd38db53fc66f1dd0d59812706271e78c02aad3e0bf8d704db7b94994b02475652ecdc660852723808	1665348326000000	1665953126000000	1729025126000000	1823633126000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
381	\\xa44fbe726e0e98470f230ce4341d2283a9bce10448403fdf0179f1ba5aa15981089016b477c5ecd4068ef04a0d1557fb7625f608db71298df18a56f1fbc8d175	1	0	\\x000000010000000000800003acba67adc15fc353ce9f154741d10ef1fe8d63d6802cf9c33fc13479df52b040fa4f54d8a0d4f3803ab2725d1cfe95cbcdc03bc5ae20a2eb362bb1e0292139ea549908131ea946726e54da3c63757da2db65ffb5ece49d9dab7dca67f09854224a9acdb5dd69553f3624f2c822302d2bae9c1afb5788ae72ef5c833e4e4d6207010001	\\xc479cbbab99757a6eb1875d2821b94c21c0f80dcbb8434f88c1553ee5da003c9fa266e0d3231d504311dc986466c47560934c40581c33143fb16d77d82b1f403	1673206826000000	1673811626000000	1736883626000000	1831491626000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
382	\\xa8c3494c2bba7e468f1ae58ee372a27d769d20f49b76e39a23eb9a92208b6b4d5741addc3c1b7b799b157344557a30b6a9a11a47479248e9f5cfbafeb76ebac3	1	0	\\x000000010000000000800003dfe4cfee38afbaeae95e2a429283492947efbcdfef4386f89fc74fd2dbcc3f7d3c2b11b61e322364b8deb758d4284865d8dc457aa2dbfee5af1fd735d60f595b8dbfdfbe00ee9a312ecc4569f1ce690eaa8aafbcd29c022e2bb637a6632002dc5c480667ba8fef54537d680469ba96426551ce040675232a1118e98ededbab37010001	\\xb93aa743d8f456d703d0593659e15b474b2c262466b42ea326b90db6fb00cb0524ed706025a56e67356fb02b271aae04f7902a1c9025adef09d51cdf36eb2f08	1674415826000000	1675020626000000	1738092626000000	1832700626000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
383	\\xade38c1e82ee0333de42cc965b501058c47cb576d570f42e4d470a211bb280f35169d4810e24b511560ab16f793993eeca2065010bb1ee30079f439e159855f7	1	0	\\x000000010000000000800003b3f99208dd4398be6255fe3875081173f4a31d0db6abbba76bcadc3977ce739bd648806f355d0c9c8b1e3471f1412e0fea698c4c155ac63ccb82261e015cc1a85afa0264f8868dbeb567f66474d892b6c0948f41e712014e7a265f57bc0025677d4d3c9ddd6b21dd4116a11c03b7845a1b4727286c26121a5e2739d960f5b65d010001	\\x856a19eed7dee34f8142eb197ecd7eb092dd53a44c6bc146c62ad24f3166579d659bf7c5cc0759cbc01b1d7e54c47a36aa982e24da721ffd6117b2bb9a8e2008	1677438326000000	1678043126000000	1741115126000000	1835723126000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
384	\\xafa341f8c0d149eb145b118ecf3be5c1b49a4b336f197b16487a907871067017f8073233f373897e0b5e15e2569975f363d4805d15043af52ce5960f3b55b405	1	0	\\x000000010000000000800003f3293646998c78a59cc053ab1c986a5ecc86385fd8e26b5253ddd645cc88a685462a63c453a396224e1cf8a9e883050d852762b083c43758a8915abdbd870261daa8019a7cc5b574c8be99aa3de72654776bfbeb97eefe5cf95f19ec60e81234018fce13ad5e0c10f3d9cc9e3e17045599c4e34546258e14fadc2de34a3c93e9010001	\\x98dc871e36d365e95591aaec5d245b0122ca3eac84c129e9e1be9da43b8e0766cc121453815fb44c96ced0f12c3e4a1624f908a123804582d0cdc376112bbd0b	1667766326000000	1668371126000000	1731443126000000	1826051126000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
385	\\xb983bda1cb169e03322183f82b670612b065e1275dfda0b8a00d1f7349de2011e71f7ee0207395a529c8586fd2ff9c080c64c46cf6bbaa44a4128bac73f489b8	1	0	\\x000000010000000000800003c796c5ffd6567f8180eecd07d07a71a48d714b709ed8ef035893e15fe727e48ca9e2857be523fa5c0ad25453044c921f19ebb2ea8f105a54f31d3cbb8c1948115b80022c3c6e2029078bdd8338fec7f1f031156e942601c41d84d7b7aca97fdeaa4ca710e3d1020f3bdd80402a7d5b260ddf9b8ec3db24f067675355ae6f3711010001	\\x44a396a55cc5add6915f7a4c019238f32379ac9264ed2637e634c5e1e7edd22e99481fc357b555e21228836b9f0bd85aa1450566d7db18f8968498c4bcd0900b	1677438326000000	1678043126000000	1741115126000000	1835723126000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
386	\\xb91fed5c54fa7141fdd27fa7ca223c63b1a2555184c5b432f59f47630ae9f4b1392968205bccbd95af741f672afb00d9cd264155bfae8b066e1ab0e80956ca8a	1	0	\\x000000010000000000800003ddb8410dbfc8e76dcc6face01136d817ccc7771807b62b614051d9bca00ac288aa45db19fe32431b93c09c8db298a015d15dc186af5c8f12b98f30d6b639a31d021c69ccc0e90ec852ae210ffa6ff8ab3ddafe141966a3c4cbb78a62c8108997729240f5f7d67f12b6f7a0f8a3e844e5861b5d585ba72697fbf8425212f9232b010001	\\xc2323afc8e84d592d4d5217ad5fe86272ca0359de2d14ccc6934682e773b628b84c0421933f39d664a1048240cdc3d5d084a4be3ea46a406f86dd492df2bec0b	1690737326000000	1691342126000000	1754414126000000	1849022126000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
387	\\xbfabf8cee693f532d84b2001a0c00b53763775f6110cf98a8e2d535e4d7fd70d25e894f54ffe65dd61b3d251281f25dbb997020a347f0a821017712765b02b4c	1	0	\\x000000010000000000800003cda390e11559022f28f5eda60bca5987e259b9693690dec11f685e44bcb8b35091bb5f5f5d1f296454763417d9418e4c24a09221b121d91b01b3d787c7de59e9643a11b59cf67ad1447b85267b625d810a7073d85a1d1a3aa310473fbc2b9fb87e3c3dcbb1a94290b5a846c5847584e0fddfaeaecbbf2cee22fe72332655e70d010001	\\x9245224e4cca20539dd648fa40a17865d48ed4b3dc6c0611c186e403517a2eea180330f3543dfef43df2c47cf25aa961ad7fd9be3ba2b2c20d91a278423cbc04	1673206826000000	1673811626000000	1736883626000000	1831491626000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
388	\\xc0677a97ba1b2a16b20aafc1aea357b8480daee24da3832e5a8e9f6a13434921bfb47e5099900f7e67a490dc31d659312cbeef23bde18a95b0c75da328686e40	1	0	\\x000000010000000000800003c730e95f8346ba8621ff87b2ef9bf89e8bba73e963e6fa81e0aa9ee1faef03718fa52115c151f822aa6c971ae0df5205cb7f5ba6093fc21dc2972d2f15f1b4a664aaffb9ed926ca763ae07761a0ecc02560237bac782454664025400de7c1584bc1ff790c09ac5e828f21593b325f5f771a4f152bb548bfab5e5bd3799732e21010001	\\x7ca2a89def223dfb9e715732d991b2ec14d1b1b34afc32773210fd5e401d563711ca1e9115720cea6cc768daae9bfb38afeff7b42477d5bca2dbbdb6120b1d03	1688923826000000	1689528626000000	1752600626000000	1847208626000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
389	\\xc0477e0ff82e669b28907da2c3a5e26e2c97a40365d9b0910b5030634227372a5e6a57301d5bfd0fbfbf06955dae77e39f92d4e8be29c624428df0857384a468	1	0	\\x000000010000000000800003b0df6598a82d1935df4e9ee8a1c3834146f329ad15f33b500672c1418b1ed25b5582e5b5bb463275d3beea08700ffdb83cfe0d42f1506e659c7a4a08fa4b12d7f11de9b092c51cbd47bd7aa2f88e89ae8e62f9fe2f21dff7c389f950d356787e05c2d283f75f898de882ab03759bea1afed1e348c803dd74aa822ac5d8a83303010001	\\x35fbcd0ce90021bd602d802d4acdb12d543a519e1b059f63a5a09df7f3dd19fbde6e86e6ecbe4dc5a762515fdefaf4956efc44f5ff562ad70002f3ad4fb05a0b	1685901326000000	1686506126000000	1749578126000000	1844186126000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
390	\\xc54ff0d9e7bd092fa59c8d8ff5bd58c978cebceb27cd103470da7a97e55beb6ff95ea9594ba2a4e31da6eb32417890b7174ff75dbe3244824ad5e3544682d32c	1	0	\\x000000010000000000800003b8cccf1f41a7c6f163387faab66a482a84140de968f077e48b074b4c8bd1edc387851c66609c6d8ca7b4ec8f3dc4f3cc0ae03bd6e5faad4fa7f4188e9b2f2a66077b569a6f74f91f415f2c935b5a68080f1953bb5b09ba8619e6c616eb518137f1530cba51718631c5f82fb1372f06bc32496295d107bf99909bf731454ae1f3010001	\\x3cf07e9ddb2e6fff2d22f5e419813d38bd4dcb975c68fd37a92b39496a1854a7dbda8951f1845a7350d9224db2f75f3bf210dd68e3510caf73aaa6ed47e1270a	1676229326000000	1676834126000000	1739906126000000	1834514126000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
391	\\xc67badd458e43b0ee70f953fbbb14b5d6f9b7c61fdd09f837f1196a0a102e126f4cd39909b7d280a1d00317393f9e42193e6026cb369bc2939ce4cc92208c8e9	1	0	\\x000000010000000000800003dcc6b7f471dca41889d771ada73ffab64a441b79dad312d68fc1d07b54a26efc88a4370e03bdb04cc1e2515604bacb70205743e0314987c9f4c06b0bcddcd0af5a06eab93fff45a05244ba1eab9ad4af1cfff3ca5659f7672fab903a6f4682aff5a75929281b12d4ea7ec449cd626ddcc7edb217e081c352da22a950f15a2571010001	\\x022814fd2f3ad16895168d67365158381d6a0d67db3ad63e6d1b5a1722efa51963eef380a5e22b010d434bab5e096d1aac72c9d6ed6c3637c13c9f156e84650c	1661721326000000	1662326126000000	1725398126000000	1820006126000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
392	\\xc9939ae61dcb1be19578323cfde3e5b3bc4714f2015bb88a43399d489080cd933ed07a201419cb897ff88763b3848be8d6af663aaabbce8ccaa2e6bcec751106	1	0	\\x000000010000000000800003c7f9cf9e7551d9c99d25e8c149bff6993bf6e0188cdb186db5a94b2b5d869e632cab09ff8cb1fc7f81eea768a89296c03629c6fe3a6bdc8d951e2e6f5d5a62bdca1b4c5f256611d3caf95b94b5023383f334417d4025df686114ae5da004b5c34d952d4a7b6a4dd945ac8dfacdfb380cbe9085e46f30b597b541aca71470a1b9010001	\\xbd37bf5d9c278a6a2e8650424e39aa62011ea38b9d160f256741013de23dce575268f13997fff6a19ea99b4381ff8d5a70bfd004cd47d1b8abe20dc189982f06	1667161826000000	1667766626000000	1730838626000000	1825446626000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
393	\\xca0f22ed8e5023dc59ad7092023905faa442a186a4e91de33dbb1fbd43df16e0a2436fe05d250a3dde7a942003e2c882e5c6f5325e78b5465caab3624526a58a	1	0	\\x000000010000000000800003c9cacdad0543622e666d6a20e8acccbfdcc5bbd18b33567e7e92d617948b1577647c9873dc2a8f3223b1b88920b5a93b7ff322f7377151aa61235fdfac0e502ace49bc2276fe7e1a5ab6e5d9b3f4adb4f79e2265edd7a1e95e385f4d7e01af95769b2373cd7264a53a3b9e8288d761a9d68f3d1e1300caa9463feca1a31c4a2b010001	\\x21e93a43a15f378a686ff11195878bd22d58190f838b5f5bfa6b8ade7aa77f15fb445f24f064629481f5f8a119529f447823e5a7dd5e136905fc6fa259be9d09	1685296826000000	1685901626000000	1748973626000000	1843581626000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
394	\\xcb27f74a627b393adfd29705bcb02548195e417ac5ffb78bc925918849eb5a3e93d2701c311ffbb5908310cd41fe52597b5bc51596b2e53808971ad36c28c94e	1	0	\\x000000010000000000800003ca7a47de005ca9be16e1b79a95738ef0c347959be5995d0c0315f893cb3ed43e58e9f97cb44c316c614c1f8f21ddc22ce6e42f10eb1a3bccbcca009711875f18c04b9365c5d1e5c704f6fbe1dc75de01e4b85980dbde7427243b220f2c2d8e27929a8bc04c2085dab0bc8a0d8f1112318ccd22cb345a8e43f41508b56cd92427010001	\\x35d350e3cd6229c74106f0407446621102c17fa36f716674c689b414c35f26a76e4e7312bd5b1480577af3cffb1604e557b13f7125c0009b16fa58bb532bf903	1687110326000000	1687715126000000	1750787126000000	1845395126000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
395	\\xcc27f3a7b640d95864072a625d848739afc719de9b959ca431c2d25cd2b40834aa1b4eb5d03e3ad132d03050cad17267c8a2ea7af42f6ef95ce48e6d50d62194	1	0	\\x0000000100000000008000039da50b3aeb59d4c04f85c3fadc3067ef1a50e48b3182a45c19848263e05a97681fd004b54cba2d8a83650199e3adcd8c24e704d03b6fe068eb49ed0f0cad7b1761d5abac687005a7bd5c78712ca5dc217c59e716549713b785d167984aa3b48043acc903226d5777e16c5d83c4d1541c838a797d565a9f9f6bd9958058aaa60f010001	\\x0a8b1e6ea128b82b7bd899847931c190dc79283c6de6163e80aeeb578a2b12a6ea5f5657499e593488cdc808a5474273c9e7c1738bc18828a866bf0d55ecba07	1690132826000000	1690737626000000	1753809626000000	1848417626000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
396	\\xccbf18d61032f337a1fe25801d1729b97ae9d35ec65ce6ffe63a4739b2fdd98063de96cc256219646bc166e85b74e031ca3a1926d6454ddc47e0c3df6ef88820	1	0	\\x000000010000000000800003bcc5501bc4cfeddf8ffecfdf4e0535a20db53f1ed543f551b22c0cd7d4c35eb036aae12a9c956e809bc4445cd0b66dc81a413adf3de8b1159e3cfc62f76be9f235c1bc3274a0220aaa6bb8c5878b2ea7d17966e6b38bd6935f697a10fc86c240d27251cf0aaf86156456fff2de508323c0c868e8da099e32f78faa98df3ab5ef010001	\\x785eb90a29f66b4ae83bd8e69d4addd56d9d12388798432c8f043009ab5c3a33827359e8f10d0e8541cce83b8af35c689b5ce61b875a693811fed1277f382209	1664139326000000	1664744126000000	1727816126000000	1822424126000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
397	\\xcd4bc501014948cf59888338bf0844682afce964b71aaa9eb4a60072b6c04cca5809d2faad5847fe6a20ffeab66b768da31240cf93961b4eb0c769ea30aaeff3	1	0	\\x000000010000000000800003e87bc49de83492bb5741badf91f6b438a75f2f1ca2a72d3f7b2891c62df8261634549cd8e7144caa1d2d15ed11eda6808b69e799c96248d9d215adc33d1cfdc96991872ce112df682aed75a0cebc63365166b17ecec2ee6742031907a1d0b1467cadc61890a6c501184fc5d52d8a5cea4e02eac82aa43d79e1f6d99a9773c803010001	\\x20975acf815625a0cd31e67e8449118403575db50376823a809e010e601f8e186a0731cc7e1304b6ccf71b177102817c8b9a60b9cae2a8d3f0b30e704cb0df09	1678042826000000	1678647626000000	1741719626000000	1836327626000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
398	\\xcddbc9fff41f31a6cff81c869c24e4d4ff42ddbf11fca7a24edadd48cd1ba4823df1f1942e4c0f54876be17f9fd2ecf723d68cc4d31bb9805964984eb683a19c	1	0	\\x000000010000000000800003ad3c3e964194684153895308171a9361e1a597603e18f19d00e0afc0744bf24e76fe6d531c9ddb76c21ba8e7d7bbd8fdcc8d4ed3a84d1b956661818d667a3dc6f7d0ae357f2a22e37b844f2f917c53861ac464bab206ddeb29f5bc3f128a748228003ce5445072dca109afb46e448b3246084350cc2031e494e3403e5171229b010001	\\x7693a3a36c32355782d40e1ea83ed7bde263c4735914bfb1c33b36e674aa9ddbb6d1fcc7e396ac0bdd8c19faa39cb979f13c2ad1dd67ce0073914ee07c347206	1664743826000000	1665348626000000	1728420626000000	1823028626000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
399	\\xcfe72350e9e2abc7c6276306ca74f9aaf8556a62592a45ef320de693cb048a024ea7943c96b424ff2229036db002b63d5d14579bc10a5bd77a7c918c5b89f720	1	0	\\x000000010000000000800003e70fc3320bda9b37ddd01695a6d2f12bdaab37bd22551046f05ebccd55f81f0020618cd96ad1db420f958e3a9550c2e40b44ab04ddde8eaf3be08257ae89ac5b590c4de46816423d988c6b73337634c509cb3ee435dd7eb2ab900b65303167c9f60d20df9e56157937aa8348e483e871f6d80777b90abb88c2566b008f6924e7010001	\\xa6c600d23b49bad56e3163554b89b0a4a1558206609af0b0dbf8b8ace916a3afefb03f06d928d15e42ac9051584955a1f2b8a5bc0d289d42197785e7293f520d	1675020326000000	1675625126000000	1738697126000000	1833305126000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
400	\\xcf23aca3d160ef35eeab53e074e62e00b98167eb1886f5f179868e392049ecce94b78bf6a7b666f19e9c0534cac45e9f3894734622e116c66a16ce78701ed078	1	0	\\x000000010000000000800003bd9f45d99df954d27522ed3acabbd6a510f2414528a689f00ef32aa4173c2331f563d7e438af81e51697704868b8a16b5aa79b26b4c40f795d0a872eaf11302342da27fddc7f5fdec360b5014cd26f1aa6576f083f9396ff2b7f628b982bfd59fef3fd5c02f81b76bb9c8cf1025d8238683ec7ef17e8a5d79d426393aafe2a17010001	\\x06d4ea7824b60113c2a111a8437dd8f11a801ea5d7fbde8b533bea5b5a215c8e9064b2b0fd9f41f79fec3473ecea076cb43b71657ce832af9d8620bfdfbcc000	1662325826000000	1662930626000000	1726002626000000	1820610626000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
401	\\xd28f9904cf057972b5fd2c5cd16c46deafc449565c86fbd71595040f0170f3782d0c1a97178b3a71b3039084a3233de5d93be75dce043c3b5d6f4aebbe9ab46b	1	0	\\x000000010000000000800003e772edcef34f912fd18d5f750592caf113c3580cfdf9d0e0acbcce1772cefab61731d1c0ab75f91e2a2ede8cebb36fa6d3cfd2b43552b02188e90b26d3fbc3e810e7bf7c527904f420e13eb9bd0974a1a01e148c9bc621441cb46ff09040a0c6c3e1a2b7903f331ba29bb4373aa582e423e8519c4d7b256e0f9e85352647786f010001	\\x14ffa7919b9b032a3a96ce26d8f8be4311b41817c538aa98035acbf925d39e43b4389047a46882188d4fab0790768198449233befb2a648cbfb308eb8e274901	1681669826000000	1682274626000000	1745346626000000	1839954626000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
402	\\xd36b00afb6f6aa8310030c5ea04fbfd2e823bd741dba00ea073749049aa26c79898cba2d5b10b23c0498e0158ff6f9c27b203b3ca94c8bc567f50b63e6f7d322	1	0	\\x000000010000000000800003cd2da96b2ea92f9b04a487e29693dbb6bead15cdd1527f5656c3c6c1d6c3bbc6f590f7148b9f656f387de1f1893ae8ab287196ec02f2f5e5f69328d7f9b8e93ad3541d6c13e6a3500dfa9dffc398c03586b2a63a04739e5ecc2b22c4413ea2047b00d1949af85d90cfaf7f4798bef852a66adfe0c0e1b7c92ebcb6da7bf66395010001	\\xabfe556ad66e8607b0fd4cab7abbaf60b89a4e15b48b31f694e0da181847ca7a1b1a9091f7bc7a723bcdacc76b55f70405de26d707f019a3fd9d62fce1d82b07	1670184326000000	1670789126000000	1733861126000000	1828469126000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
403	\\xd48b1065b8e2845e9c62be2b30c3b808540cf7fc382b2bcc83e7cdfdb8bddb505cda1ea775659ed35e6653be5254e93730f649bc9de8dcca43965d94949befe9	1	0	\\x000000010000000000800003b64c62ffee8c0213c551c94c94fe4425c33aae17bee504d83d2fd3665ede50d02a6df0ffdc5f61231af95282b38e9a6a5cb00a2890b9395de903341324567f42b1fe1d73f683d149eefd7344617dafbdda25ac3c3771075100f8e2ac477f02a4c6fe24a1a6f521456b989381752d09495843ab215d62b76c5e7ad33f50b83db5010001	\\xdff03046afe547fe01f3eb2047ee6947475dd6686937e965fbe2b4697a05daa36b817c18fb664685be61a7993ccaeb5c3a86bbf094bddf790f293eae0c8d650e	1684692326000000	1685297126000000	1748369126000000	1842977126000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
404	\\xd47304855d24ad984c059e91807c8c7e0abfddf5583c5a76114f7f8b0bd3b38c32b4a3e3ec4b529960a337fcda1f4204921c14a44f7857cd8ea32dfcfb1941ba	1	0	\\x000000010000000000800003c6a7d7fd44ebd2cb2dd4d632e121dabefbe576cdc4e81ee1e1307f67432c0d126b396157d9560c56848e8f6ac6e318cc9d3a7ab49c5f2476fc1120886997b3b3e2f63d39650f73d448cbac7e62723a8d59136d3fd7010bc2594eaaaff4734d7c5a77c3e28f57c0af7eb21389595e7b43d58fb7e4611b4c36007790b17dd396a7010001	\\xf56aaa04d1f317574aff9ede35ab3533246ec3ce0df77a08b3eb05aaef7e4d91629c7c6fad68a06ce2db8451ccde546d766a645ffc0427db44adc58280f8d10a	1665952826000000	1666557626000000	1729629626000000	1824237626000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
405	\\xd5fbd3e8bcda801b988ab894610f4354f680c8777df776ee9403fc94deedd5b7e20c83d1154b800bcf84a1f93aec87080a0354fb552db3742709f08b2d12ab63	1	0	\\x000000010000000000800003c02758b79eb8fc3a2d82a10c941374234cb08a86ac15962ea22574556a8fc0e4c3f2887ecb0b7f7510f8469f537397e0dfd6a38cf64a4d7939c03b8bc4ce64adb341b654a87712d70411abc89e0d66722b756101705420d0db07acfeae3acf3f1d3f9ab44665d424cd22dc2607f85c31613c76d570ccc5b849b627276dd12eb1010001	\\xf6293ff3a57e5265e2cd92818acd465ef17bd2c351bcb6fea4090ad23e2c14ab5ac06eeabf9af32a1cfc53f4b4c34deeffa609cfabe01c1dfa4793358de17103	1690132826000000	1690737626000000	1753809626000000	1848417626000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
406	\\xd7e762337e52d7a00eaf3724bde5e6c45b1fb2bc733724323d7947b96886051383739cbb3050c6635b86a5501624891ed2361d940b7d7385b3afc4e5e8275389	1	0	\\x000000010000000000800003c535f3a2ceaf8103ea6d4ddf5ade787d420485c8f29c54a7a9043b8dc955c4899a2d64a63134c3270a044e88da24e6e356857e227dc507050a33db86c8384c7f2c3b23176d1c1e9ab806ae5d3dfcc43b83b991c3d466f2609bc6e4d6ee0b371de87fd8111ad22a5de6d256e13f7db8470295e5b789883d18a91952441b7611d7010001	\\x325f4b7854990c900d171bee3c613e749b30745fafe849a9b4f5a4651fc2503739e33893fd1fb24da04f341b03ae8e644104fa4dc8b5e237c9eea5560cb3c006	1660512326000000	1661117126000000	1724189126000000	1818797126000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
407	\\xd9bbc9beabc45996ef829e04eec2a64c8b66c2ee06543dc725f06c4f00848dc5bdaa84acf949adef206ee6fb3e25aa47f96f610dfbfba5cf6a5a1369a4056bf0	1	0	\\x000000010000000000800003c3b8b5991d5dcb0455cb51b372908ffeb62b7ad2067cbb8d9b5389d1f9d443a854e5be5c4c7bae07bd62c4ec971708ce23680136aafdc69c8147811a3caca034665b8f652a7d9ea8b8460e8cdd7e6df20d7b55988fa911419bc9e48e8a5564d4c2a3a1992fc1c5fb49c8578d559fb83ee2891aad22f1ac166787d904b4a370cf010001	\\xd2585b8d19d270f42374444e82d37e31a0cf9cc2904e781cd2435e93dffa6ac7b6e5836c499cc9fbea61d1cba1a5d69174f2007bf18ac6f9164fc3954f782607	1691946326000000	1692551126000000	1755623126000000	1850231126000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
408	\\xdb7b6ecc96fd7c61274396cc78f584f3432d6ececb7a76454ab057bbefecbc7990b1d7d73bb47c733c80372056738a2dc6dd98ed1fea0eec55ddf03d6fc607fc	1	0	\\x000000010000000000800003cf4ebb9731061af811894bf7027c8856c34e4f76dae210e406dbc36778510a48054bf9fa9d3d16515d75e50bd391e14c3c9cc99f14f4f0e318fbf233dfb84f53ac660205b158fc687a4fc670050c8fa826414a5f16358606e95ade6cfebcab9c20455216c4f737d8d2b1518b226bdf3785e1f59f68f4910916ed313aec25b98b010001	\\x3365aa459f5f9cd96fb00cd7c0e4a91f507cdf84be113a576645507aff3bd957f476a879c011ea701d98dd1b6840804f43c053bdf68c7401edd3fc90ff81960b	1671997826000000	1672602626000000	1735674626000000	1830282626000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
409	\\xdbdb0d3e7f70d4e4ec205e6218a12970f9429f1b273004dd29996eaeed495513163c11e4a5df573304d2fac4bfd72e8d341ec596f35884a8a3e6e2788e4284da	1	0	\\x000000010000000000800003bef976e8a06f471f823d1fba047aecb90781012d79a18020afb94478fa866b0adcced16bb743420896615f47ef3b241ec842a8fccc11ecb4ba72f9489a9597c8c5ac1178522bd0500abd9790f0e42975d8420a4f6b919f7c3671e2d943a5e2290e85ebf5b23ddb89947c4c6766ad747804982e9b6051850e0d65839a616656cb010001	\\x30f5c5d776e2b26207ef76eb084f97bb225108b702052e2188490bbaf9fcc45a97c63b0c96eafccf529ce6a6a551be76ba6abb0801a5a8a7567a06bd570f7003	1662930326000000	1663535126000000	1726607126000000	1821215126000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
410	\\xdc0362f9a58edcbfab5fe9106f3c8c9755cef2e69cdad4d5ff7b8a2951e9a834cd3669b01ce2bc9ad698ab4d21c7c3e2c5671e46adc91cb8d4ad033eefaf06f8	1	0	\\x000000010000000000800003d466f9e6727de63ce3f0722878c74fdd8565eb411ba3c4c11235ad93424f77399b5b288f097756dc011309949f18972971c4d8036d09344a2f417626dd4199c223521f4a9359dadbf86574a1f696bbf9fb1da61c94b2c3a222e06ca0d2fa0d65a2c513f3b5db9d34477cb575e7a7252eee6ae6041bc9869d3e53e47ccf5e5121010001	\\x276a36b1d18e71a51c5f5a4c9eaf58c884ea959774efb3359185610aa93965a71ec50fe141c56f3024d6c7aff210c77e008f37b397907196e664d13768340e06	1674415826000000	1675020626000000	1738092626000000	1832700626000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
411	\\xe1af86cd0769df4eceae2277fb36d336cc9576947a226d75472e789d64a06a89752692e7807ed17b4c2c4895795647b9c279ef4f1a104cade7c356d64b72f1cd	1	0	\\x000000010000000000800003e77ff44d86b6c10304d4c74f8993b02b07d2e313c3017c743f99a88dedfdc06d761eb6499872230c4a6029552b91de4ff340a2663bf5c55f7651fb13b800acf9b1f7b4798b550c69090a6216c9bd58bfe438fbe4b5238f30cc47447797a5fe5e5a7d64c227e8daed7d5790ceb651793c74cb2697df011e7e491d806d08de160b010001	\\xff70d092449c7f4f2f6ba7bd5ef41d7a258734592c46325482c86606d2e198fb032b102b288acdeb685d469b5d3fe50cd684a9686053f79ea1bbdba10bae8c08	1690132826000000	1690737626000000	1753809626000000	1848417626000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
412	\\xe3bbc9a59bcec0aef594dbad9c53f3d810d6445cca0c2c1c85d9b885c37d2aad6ec57034793a6f66ea464944ba0e926029b0e9cb014cd39f59a3736e9afa8c32	1	0	\\x000000010000000000800003f49d6bde3adeee044b54d6e4e4307b1ea274bf1e8e708ecd680165c85c1340c1bb4329cea8c1acb965097ee610ce063bce07693dce56880054d4274c4e6ca924b0371231428cd295d712470d944686e3e8a3a61bcd1b179a96163a59ab41fac44bb295df3541ef71d7c4e1dbfe825d2059841787319579f9b93030b9bfb79261010001	\\xb893ccdad4933afd77370474c2d5d05339121dda78effe9c623d4e4c31d0396a613acbb72e65f311181568812da55ed51485a1f457d8e771beac1b9b41540f00	1678647326000000	1679252126000000	1742324126000000	1836932126000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
413	\\xe4eb38af149754e9160ba67a196a075d1374faa683ea862370ade78450475336cc9184334a9fff8cd7fcb96ff8f0620f54b855140e317e3b0b3d1537ce040535	1	0	\\x000000010000000000800003c5c65bed12e736f8354cee3a193e4d48dd0000d30f38d90073ddf9729ba522d125c348fabee58e819b4341829a2b25947adec735a279a10b9675c1f5db5dfca3ba0d6e0a5993d36302d22c6ce82f3675b511524db89c9d38c5264139e421bd7eb82cc7d15242eb90a2f2db3e82f72a9d94d8a57f6c688c6f4a3fdd6126909a4d010001	\\x666ec0034e63c9b16135bd1e6483b2e4cf1247c922144e85f18f2aef11d1e5ac3721fe0210c5f4d339b7ab3381246b50f3536214dc75b4d4677c271dade17309	1689528326000000	1690133126000000	1753205126000000	1847813126000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
414	\\xe403c139f16432cab61b7087a10fe972a9f9315eaf1d3246d23a5291b36d9ccc885f86384f656e74921fd1c0613ea2047a13ff31b7a7f8d8148cdf4d109de23f	1	0	\\x000000010000000000800003b671c826cce7c15e43626dec5f38f5d9019c9a736e3192ac470843b2826a2f24ea9dd44914b4eb5b2c7c692275602e22771093a1071580cc2c662b39f4187318ecbab43edfa6611b89c07023e12a4e8b8bc553dbb76cbf163f07297fd2f0ec960cc46df190df63ea3412e66f0e40ef45152eddaaefbb86a33424f7fdf6111413010001	\\x1533018046c7584c4e330a76fd37af26b50ab751e14c953d9f7d8761cea843468110cf7b7931c66dd8f9872cbcb9ad7f15014eebc3d93cb652274f8d222ef300	1676833826000000	1677438626000000	1740510626000000	1835118626000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
415	\\xe4bbeefbe463e2f0e1c80c4bc3b899688bc46b1bbc72d0d84a1fb0aa8a6a8100f0459e109cd3380ba27d638180ecf2a5d9aacb572accdafd5caeadd3a9cce835	1	0	\\x000000010000000000800003c402fe0aab7cfa7ec1b5a9d45f737a29cc2cd7edd0c3566ae4a889a39fb1b180ed0240a655cf379555ff98b47b8f71be77ce6e475f1bc1a5ad706e4ac2fb07aafe18dd8642799d39896d31580ffac31b8d81db2e4d86ee10a069b7ef2a0c3618a103a07180df467058bf82caddfbc6997835b3ea8a4d80fea583f93c6037fb97010001	\\x53fb1f72ad02ff1cbbc0e2131d2b88afaeeb5ae8f2444e254919875c2a940f2bc6006e492549ffa6590fc9a4bf3533a04659b943283ad018c70735c8be9d330d	1679856326000000	1680461126000000	1743533126000000	1838141126000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
416	\\xe6df4af9a0cccb86cab533a1927e99858db8a397f80781c0131cf01d986f04b693060ef4f56fc63c8d9cf44253790d0709c9e428016d4b217e1b24c77b1b396a	1	0	\\x000000010000000000800003cb61564ca4b4d9a088278d857c5643032162d36b04f81035f171bba220025289191b10f786db93a39530f70676f5eff1a6d4f0bbc41e70c7a584c1525403ae4ab586be0d7687096b8778fb15ff46252187c8fdd92d7b9b7c184dcfa4e9f83e805698ae878933e05d0a1217a1a68b3c8a8481569fd50567a57a0ef1dd5861cb5f010001	\\x4b0cf0179c9ac8e6a228a5cd671dd3d1a0c2f337c0859bad1e478671d280cf7b46aa828f1faa37ba66e2f002a3dc29f4592fe257809d8b30f390c26e7ed32408	1688923826000000	1689528626000000	1752600626000000	1847208626000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
417	\\xe8ff82e1e5eb668cf871dc1dff98f071541aa5810522eb31cecc9779147f01952963f8d4403ec9551eb897d7273148fe876475ae338d1e816ae37e2b2eaea498	1	0	\\x000000010000000000800003e3879a516ee178f7ec71822fd8eee81be8812d6eab776843c4da9cb4f531a4f8100f1d31bf0182a3a2240329ecb953b6a45adf5c3446226ab07d349b6eaefd3ce88ef3e8e4879691c207fe4e85429066e2a2212e05e0b79508980d4bf97e771e33214e75a4b8e77c4388f408912d2e5655d03d4be7154f39cd1a15f64471fd2d010001	\\x23c07fc0c98665a50abf77aef3f625a1a2d28ca98c977b7b0c4f75255b162b78646266621e777459c12ee7b971851545c84788268bdb5e01005732cce3f85e0d	1684087826000000	1684692626000000	1747764626000000	1842372626000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
418	\\xed0fb9538a5e447f8cb76764afb5b3cc1314f1ce7b6a5b495c1a8280a4abf4da37e88b083a11ef31470dff017b26c3060b281396fe643543db44dcb541f492b6	1	0	\\x000000010000000000800003be51e1a746eb6fd8bbe1c879d0837c131526a5ec8091773a8f04ac8459ff2b9593fa0ddf5ba9dd0d8d3371c0b3dbb513ae8939fcdbd31f0a2b0cd81697ccc8cdd4f12f5377130643f02149a8f81133426162e6228c983ec26aa76d335a3b718ecc4ea03ee5a5a39345efc2cc408a1c38b972347ed38d1bc8bf395715c5c5007b010001	\\x9fa620236dfe18d07429272767be57749ff70e3350b7c86132cccea914e31f78ff763935f8fa9d4777112fc1e670fa43444044846db50d4997dbb24bfce31504	1665348326000000	1665953126000000	1729025126000000	1823633126000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
419	\\xed8360d716c3b005d38eac3b1d7ce7ac57fc5957e9bf6fecf4a55b6f901f93233d91ce580cdd89649fc6f21e9c7c613c078f2b5a5dfd77bd0089af7738e6a354	1	0	\\x000000010000000000800003bec10a9be51d413ea4f9c020fa2a8d37318812dd468d9a3adca7bb0d57119dd06b3645da554ece0f217e07b4ac884cb4a56581fe21e9df0a6c342b0a8a5ef8f7d85dc4844c471a5c45117873e841f075bbfd84745cef8771aedfe50a6b6831a23b0587e67006788c98f554ad7b5a287bf586d509f4fb5635ff4d46df8f04b087010001	\\x4dba2353017eae38598b31fe9180eabd77836f57e6dafa65df4225270e603897d5ee2db3cea6a41982a8416be2d8cff438fa20dbff6ca89c30081ebccf1be300	1660512326000000	1661117126000000	1724189126000000	1818797126000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
420	\\xf0ebcf41864262885b3133d246bc6be83f630602b2a2de14271da8dbb1f7ecbad4d45aa502f19dd397d5c6af94bd8f603f72b0b9df5403d0acbaa6ead2f8f251	1	0	\\x00000001000000000080000395c8c5c23bb290f7c305f34c8a5a758fef40b13f2e4b4c88456f97b3a9562673eebc1804d1beef94dcda7169948d2f744e117e3998bc4fbc4c41e44c4c6d193eb51a1d8ed4019f6c53df68e81ce3aa8d7d6dc32f91a4ebd3858bf2985fd8c97c6f56f428462178d3412f90a7ce92b5fc8a1d4c79107ecf5ce5e74832f9b0fe9f010001	\\x909fb2093f093647e15251d29b66de8caa1d3ad93a2856430e49d874a2c507c102c4a05ba3b994372acf71b7a0b6219212122415670dd5b4b587456b1d49b107	1687714826000000	1688319626000000	1751391626000000	1845999626000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
421	\\xf3afdb3273361fd847f6db66ee1aa3ab6e4a5b366957efe0981183960999606145c7698b13551c9e10ab958466777c4f1f2fbb0b593dc4dcbcfd85be31440c4f	1	0	\\x000000010000000000800003ec1f9b7ed7a36e98f8061c0f408d290719d61d3d4d1dbecdbf27fb2539c97adc367190443bfb4f9a7274fefd82a0e3e81aa1f80a3688150396732a484b0548a99e7ab8860cf964a53ed2bacefdba0915c0f4459c40edba2153dd36836ab4bc0b2ede3156f9e55833117cc3c91a4e7a4138b2f3a12eafaa1acee570d7ba4ac115010001	\\xcfe89f726f8cc41056e0117fc73fda5003fa2c9feacc0ead4bfb58ee5cac270eaebc3ad64b8463ccff31b0506d58949c5f8864762ce5120c01ca899433d82a0a	1677438326000000	1678043126000000	1741115126000000	1835723126000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
422	\\xf7137263bf20176d0813e234a67fe8d407a69b274c070c5905334904951f299cbcdf7980045a6a78e2a2437908dda57ab400cdad83469b2a23137ef934e02098	1	0	\\x000000010000000000800003a27a6af37a409ee835a8f5af4c39e9ab676a2dacb2b2dd29a0464640b61c03aa387b6c0826fef49d23dce5fc4fd7efdb3c8339d24d85b28d3db349bfcd8a9e7fc4a0a7c3faafab390058149a91af6f9763a16c484ee539e1eefb681f54a9f2b1c55b941f435067591ddd0b41146ea36641cbb26b7eff909ec7afdfcd9161833d010001	\\xfa7b9d43c123d3759f1d4adb9a9531f3a50324f2efd135bf2febb50650d8d36db44bd8d7d2e8e9b33bdebd4f1ffc2c98f470702f6b25605d617aa528e5049d0f	1679856326000000	1680461126000000	1743533126000000	1838141126000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
423	\\xf86390accb4b06e2ccdb314c3d84becc2fb945ea9ce3f9ece69f14cc2b6f13cb3f64c9e5be894a15fbaa9074a64082bd1aef9d739e9d8788a9c51af2579759cd	1	0	\\x000000010000000000800003c9e652c2c0928ee1c8b6d06ee5cd410d5ed80ed1b95506f5050e485cfd9226d3bc0ebcebc3d569b7461959d629408cedc51634da43ac99d43470c0ea9a15d6da1d6eef19d55da69f745222ec2c9c6fd61b03860b34ef23e0531a4ebcebe413e47e8b5d91423936d2b69166b43f843036ebcda301b827ad30eb617a84f8cbaf77010001	\\xf4878a9873b50611612fb3b43103aadc7d9becb56636070be50ae0a4376c9102fcf5c2ce6d75d4f248ced191c2c3256d274f24afb77abbdbdab7969b6aec9205	1684692326000000	1685297126000000	1748369126000000	1842977126000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
424	\\xfee3959fd95d6856d9e0661bd629e18b0dd97fe53b1bf71747737c895db6e4d5ba75fb0fc1b3dc9e6784b5faec00ef4cf3d841c8fb1c8741b2e5337c167ce523	1	0	\\x000000010000000000800003a9a37fe5f46fd85b6d2d6100942f2e9e6c82ea5dc37bdd6c308050f0164fd1ccedfe5f5f3497d4790567dca0a5acc5f48e291af9f16d67c0d24ea47c1594dfdc854598d0df4e6b4dfe20d56f29bddc5b679a13e6c4c0bafa483a9b44cd25dc715a4df3301f3641d159865d1759d1ba46eeda753730021cde3ad3341c58a6a44d010001	\\x91be9c0d982c7d0fcf87062611afaaafaa062552e7bd128ec2f5ae9373781b313f89fe3d8e30459958cce56fc56ff4880ea937323725756005ddf1754d20ff0f	1687714826000000	1688319626000000	1751391626000000	1845999626000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\.


--
-- Data for Name: deposits_by_ready_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.deposits_by_ready_default (wire_deadline, shard, coin_pub, deposit_serial_id) FROM stdin;
1660513242000000	145568385	\\x2b1e50c6417270e052ecfe4cda4a7831c5cca061b59b9cccb0163d6f3ea46ea0	1
1660513249000000	145568385	\\x4e35a55b7764fb8f7f612e274a53d196543db4c5faf347dd6994502cfe098caf	2
1660513255000000	145568385	\\x6936d088922587535a3b521583419cb22e24fa8bf7e384c6fab77d826ecf155a	3
\.


--
-- Data for Name: deposits_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.deposits_default (deposit_serial_id, shard, coin_pub, known_coin_id, amount_with_fee_val, amount_with_fee_frac, wallet_timestamp, exchange_timestamp, refund_deadline, wire_deadline, merchant_pub, h_contract_terms, coin_sig, wire_salt, wire_target_h_payto, done, extension_blocked, extension_details_serial_id) FROM stdin;
1	145568385	\\x2b1e50c6417270e052ecfe4cda4a7831c5cca061b59b9cccb0163d6f3ea46ea0	1	4	0	1660512342000000	1660512344000000	1660513242000000	1660513242000000	\\x13074fb0cf0afb2d553acb2113c69d0aaf62b3d15ae83b7c812dfc121c060aa7	\\x1dc78c0db550fb6dd5f6584331beca9f12a6360a01bf320ba171764c323e3eb954165ac652eafa48f616b71d21091a3b5c37bbee194fe0a4ccc04c45cdd13d14	\\x36b3b8c40f2a98d1ff5bf93b6d8f6d4fd87e7a98ddca9a179780a2f38aab1276fe0c82559f63a189666fc7f450e93bf7501716c9d3e869329dcfa3977ef23d06	\\x9eee741ed059a5f6622bbbc1394a6a75	\\xd31e3f48cb5318906dbbb7948326362f41604c7a728323230ae82aa995f27400	f	f	\N
2	145568385	\\x4e35a55b7764fb8f7f612e274a53d196543db4c5faf347dd6994502cfe098caf	3	7	0	1660512349000000	1660512351000000	1660513249000000	1660513249000000	\\x13074fb0cf0afb2d553acb2113c69d0aaf62b3d15ae83b7c812dfc121c060aa7	\\xea76029b68f01208d37a9546ecb802330bbd2f754612cd6528a3cf97a6431802fddd7f52eb7455493fd0bc7de53af1ee195061b124887804652084e05fd0324a	\\x220f819e9ae9edf87e4256ca0910cfb5884da7a5ce1ce1c4c2296c2e81b92c064012b3be2b6459ba89482a966bd8c2d3ed50f66df9dd51d98cbb71ac60cc9206	\\x9eee741ed059a5f6622bbbc1394a6a75	\\xd31e3f48cb5318906dbbb7948326362f41604c7a728323230ae82aa995f27400	f	f	\N
3	145568385	\\x6936d088922587535a3b521583419cb22e24fa8bf7e384c6fab77d826ecf155a	6	3	0	1660512355000000	1660512358000000	1660513255000000	1660513255000000	\\x13074fb0cf0afb2d553acb2113c69d0aaf62b3d15ae83b7c812dfc121c060aa7	\\x7025824934f4bfdccb0766a8eb445f80afd82bc969eb775ba9a637b0f4767ebd5ebb7cc01fcab0cea3639759047856e14a5ba97d620b5da2d0b6ab3e8b0ebeaf	\\xa337e0b957f068e0cf0e585925b3a91adafc85ab01a0e4bf42e2885cad5008b052609036689cac8eb2236e5a1cac178280e0b4bd0f597965a56e7e43be2f260c	\\x9eee741ed059a5f6622bbbc1394a6a75	\\xd31e3f48cb5318906dbbb7948326362f41604c7a728323230ae82aa995f27400	f	f	\N
\.


--
-- Data for Name: deposits_for_matching_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.deposits_for_matching_default (refund_deadline, merchant_pub, coin_pub, deposit_serial_id) FROM stdin;
1660513242000000	\\x13074fb0cf0afb2d553acb2113c69d0aaf62b3d15ae83b7c812dfc121c060aa7	\\x2b1e50c6417270e052ecfe4cda4a7831c5cca061b59b9cccb0163d6f3ea46ea0	1
1660513249000000	\\x13074fb0cf0afb2d553acb2113c69d0aaf62b3d15ae83b7c812dfc121c060aa7	\\x4e35a55b7764fb8f7f612e274a53d196543db4c5faf347dd6994502cfe098caf	2
1660513255000000	\\x13074fb0cf0afb2d553acb2113c69d0aaf62b3d15ae83b7c812dfc121c060aa7	\\x6936d088922587535a3b521583419cb22e24fa8bf7e384c6fab77d826ecf155a	3
\.


--
-- Data for Name: exchange_sign_keys; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.exchange_sign_keys (esk_serial, exchange_pub, master_sig, valid_from, expire_sign, expire_legal) FROM stdin;
1	\\x737250befd97ce34923bfd60b6e079399068366216cc7b8c23df57f5d8bcfb75	\\xabee491455243dc924e13003429c9ae67ff6c9f56b93f080d2b1d2f51c2008b01538ff2d84fdd053177dd121d20d11afd605f39101c23791c7845d085e889004	1675026926000000	1682284526000000	1684703726000000
2	\\x551d4ea4c3366b58fbeacea996f29f6b073e80a3b0cd40b789e55bd562ad2503	\\xb6d4f74655d963176f33c13f422d26d3d877dd916452a6b8b4d5933acecebf62d3044730af1878f875f46fdd3ddebd39d57b21c633a568e2616f3f6dd39e0e08	1682284226000000	1689541826000000	1691961026000000
3	\\x36809b1d0e8e3bc73409c53f8b51476e8e6b746888ab73ba02bb4b19d700aa77	\\xc50db63ae1578123fb70b3d748bc0990174faf6cc38bc2bee33b0c4260e14c4c52e785544043bdbb7e465f50e822259a13f622bba3d29dc4d8316dfd9af43408	1689541526000000	1696799126000000	1699218326000000
4	\\x1df9dca4f3f275574e04772b2e6e9668da515b19237961bf91db87270f577f2f	\\xd10f5a792e354da672f87675f5c19851a7c3d862543d74ae3458f6fd38419e36cd181ef76ab0eaee1efe7e3c2d03a49cfd8ef27b80ed946ad0a2561c6f05150a	1667769626000000	1675027226000000	1677446426000000
5	\\x3e6f96219a5496cbeb7505d5a3681d2e2320f472a5e6c66051e2b5ac7433e8e6	\\x40839256784eb80ca73d436caf4494f82eaf0e85ac151127b9e5cc0f10f7b0e6d54403bd395126008cead15b908aad1cfa3af61bc85ab1668c43598ff4b1840e	1660512326000000	1667769926000000	1670189126000000
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
1	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	0	1000000	3600000000	3600000000	31536000000000	5	\\xd14ce0277e3ce203ac3c0fff6785f003da1f143f0d92e48ad4356e6fcde5150f7f73ea95749f8b16b2802ac68578f405c041b5227ed26f7ea7cb2e6a19274907
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
1	315	\\x2b1e50c6417270e052ecfe4cda4a7831c5cca061b59b9cccb0163d6f3ea46ea0	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000001b4ec4b1608882fff4c1b9d39dee3e760634ca8546ab95547250838c64c5700edfeae1143305086030ee18499d641c13da9aacc149d57974e80344fdeb61fa03aeca7625b0ee00a7af52f2c34909e9e698de1301d12e4bd01545d2e5b21e83a576cc09b546cc6849b2a943f72af30d7a5f23491b9114d1b26cbce5707437758f	0	0
3	252	\\x4e35a55b7764fb8f7f612e274a53d196543db4c5faf347dd6994502cfe098caf	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000003a943f2f7255e223a8395bdfe13fffde769b9a42d12c0b41ff21266b890a3295c2ec8195a6e06e639d270cf808fb692ceeaf21e4d1727a2e9e6156b20bb543fde4e9ce7d935dda0d557edfbafb20a77ffe71be4593c39fb84b071111e01a5f231d38d2bc0b6a3fd39919d908b65f1186abb0abdd699aa8dbe5a3470280455910	0	1000000
6	406	\\x6936d088922587535a3b521583419cb22e24fa8bf7e384c6fab77d826ecf155a	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000069496200c8840631c3f9c577e4e848895c5b7ae56a06d6ff67dbebc465fc82f1b565ea38f1456b6a848f09a0d1c8c7359c6f20d2c498bb3f09823e96ad32e6cd73295ad4c73ab0fe6887a14bf62f0e55ae8ec403cd683ed6c9bf66c77ada469e24f055b18c989b9cb9fb0c9aa7e5420e55c0d179de6901cb0dd722fd40c72b87	0	1000000
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
1	\\xca26cf29e4c9677ef1f3518b91fab76be30e859ba467ad3e18785999312c71988339c8ff2ae24a2aa9408dff503ce1ef3a8d1b5baacc2ba4251ee60c5444a263	\\x2b1e50c6417270e052ecfe4cda4a7831c5cca061b59b9cccb0163d6f3ea46ea0	\\x07e299d8480e298703c77f7d30b3608d2c349475d25682c3845a98ca8520395187c6e78e03ec8844dbc45045b219565284d686a0c4415a966e8045ae43e79c0c	4	0	2
2	\\xf7b462750a05b9dc68e3161b3629fb93eb1bdb4d57a9ccbdac394fffb5eeeb01f2de36051dfb34629071bed28b5a8004347fb986abc9234b7d150b170abff6d9	\\x4e35a55b7764fb8f7f612e274a53d196543db4c5faf347dd6994502cfe098caf	\\x2d09dce8aa257d4726ea6973e539d6ff0fe574aac47b1b1ae2c4e0f750775d7a0683b33332b1e755509b606fb47d4c8b88896cf091771d17dbf3684903e71007	3	0	2
3	\\xf78421d0dea6fd91a6a67227afc5163d8ba741e28054889c4775ada057c2a4e21657092a99ebe8fc73c860ea4f4c88a933bc485459fb92bbc71d5b58b21893f4	\\x4e35a55b7764fb8f7f612e274a53d196543db4c5faf347dd6994502cfe098caf	\\x01859b2f3e48934f48b913cc921ca8291ad0272da70885e82d251247302cbc0c30266427948a2f511602fab7ebfc5a4a27c4a3fea528a29fcc9798a50659a20f	5	98000000	2
4	\\x5e7d6a797ed4e26f418f17739d01975a319428d89fdf97a3ff6edbf36f9bd1aa267644cd347dfcd04a6946c5c632f8db05021a60a664cc6cf18041fd4b6fcc04	\\x6936d088922587535a3b521583419cb22e24fa8bf7e384c6fab77d826ecf155a	\\x1bc2eaf0929f9992b06913c0ea55394188f736e99489fe916b15d5311323a3d7c2563d754c1c50f1636f2582b01f2083f9058beaae60c0ff91e0ae6bf650ea08	1	99000000	1
\.


--
-- Data for Name: refresh_revealed_coins_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.refresh_revealed_coins_default (rrc_serial, melt_serial_id, freshcoin_index, link_sig, denominations_serial, coin_ev, h_coin_ev, ev_sig, ewv) FROM stdin;
1	1	0	\\x1612437881d1d52f8544af93e489e5c0f6dbcba8aefc5feb36e9bad3cb06d102cca03be238d04252005d05907bf46cda5af85c143ec08fab38446e9aff03440f	130	\\x000000010000010075464241b0b2f851d6cf96117baee1e3d24ecd4aebc935ae259678e2408871ee49050050900c54881dc71455614d0fcf7c62fdf327c4dbe780e677a00bb6dd366ba06ad49dd5cb25f6ea7fb28c542ce55be398e06dbaba50b05f33f9f6340e9595e2e16266dd4d351a224703d834b44089d84fc1700d3ee669e5bacb11428c03	\\x9393cfe631e49e83827ecf89f0f91964042b2c4e6742a08100806c7f4dd3da6f5c658116ffad5833e274cd961545df1af2151236e48fca86c00347dedf5c2fa1	\\x00000001000000012e1e8d47c87ee829efb93dafa92ad031dbe270abe903e31e3a86a62bb2c9204fddc9feee93cabfd74f33a0a057476faf681da1792bbf883fb82e094e09b3098ea88549cf47fc71585a6864dcb2518c85613d7399818fc55488442842782811bb3b1b7004cd389c00bb2ccc30d0604c085df1d85c4468868c7b1d82772df5889e	\\x0000000100010000
2	1	1	\\xa0e878e6fd40cf4d0a81f7c5cff1356d4703b6286af69d23a6efe0cbf6ea1f5e6e61972c824803811d92362d08a62db904b0c0e1ce78666e6fe7cb58f7ef0a0a	57	\\x00000001000001006ecf70d66a81f46546c99eef71cd8a15aaadbbe0ac90ad91a85225d898099398aef105b960f7c2047fb440a582272d7f4a2748c0a35a1e00237397601789c6cc541ae6c40e271055a854a60114c5f37030b7184840a66e24ac019d79d038fd24ce780741acef7bd6250a244c93a28ebe1a04b730a4364db11b7082f7714e6d83	\\xfe4293b4f3b4b2a98c11a3c995b67548f44cc4500625b4f1e9d606ce6dbf26074d0a459c1ff6509c225f6914907f5a5834e95992f9bcd7f29b061622503d7434	\\x00000001000000010fc05f55e232d06a46f07ba9f096e92785c077d7495422dda9b49d288de178821b4ec84bb9a691466acfcf268a87b3d86518a8f5acb4ea2dfb799baa23f6de4f7c08cd1f9dc19e7f8adca2fa9cf98023ef5552b1626ea75b06d5ba469a17e06e0a5eec1ef5bce25a007b251e412612ab8bc47a12aca701c51209a2b202d837a5	\\x0000000100010000
3	1	2	\\x8671480615d0d9cc7fc2db39b2a29740279dd94579b0d79fbfddfc33112deffd926a530e2246df10d9dd864c1de5ab7b7e4e2929eb6b3de1884c8c2c9ed6b002	23	\\x0000000100000100c676b705235eabcc57bb7788fbf9aa392898cb822a39ecedeea7b4ec38fe55156ff179b7a3032540c082b87d34916a2026433546663f816a22db64480f634b6026d839fea3f2f1d8369889b7461ebf974e676d448e9d8852a1bb33cf4a81d3df37931a6a01eaaf70349e6645d45bf52bb7cab54de60ee739f5bb333ae26470eb	\\x808265cf765be33ed7cd3d3868f33a80e49a92f06a24af1a87a1df53aafdd97c804086f53b97c0a2b0d2cd578288c9d9c3ef99f77915ff28a0e47393f2aeefa1	\\x0000000100000001b54ea8f12f9d60be128d1da5e04e39b25254c4f2eb5083b01557e4a0adda10c9d32a27e3414648f8a7b1a727e2fde0ef969a6697e1348fc098add50b4dee8d649793346a54d6b9f0f8c6c9651a259db7bd89e76f3b9431bb6226e98cab09dc5cb10cf8e9d7e50579652b3fccacda5942b684e46c676a60f9f50e94071c2e7676	\\x0000000100010000
4	1	3	\\xb11b65b2540558614875325c6b52abf410074bd85cf1344094d3dd350bcae6827fe1cbb0ce3518bb5f0890ef491745edde6b531cf6c93a68f6228d7cc2254005	23	\\x0000000100000100a6a1bd4e3c448e0b396d9e73ef91696c03cdec65cc39d74607718795e87d50754aade9033d892bfc1adc985252e5fd811ba6e4c94f73737a7b13ee622257336439febd45a76733f5b9c1c761a2d6b260bb7ad54f2c416978d45bab3609f1274ab9aa97c039427198963342a2fed820f60d420f56dc8b3bfeba216fa1014e8af9	\\xa6ec05ef0178708e24278cf2aefa30db48aceab601904f41667f474810460ce7c778ff48b7e5fd29b89efd06cb8517228aecf2279ec80ecec8d36b67995e3142	\\x0000000100000001644a6038535ef357e336e3f667aa245524a9785e00994d9738c3187ebfd4a3d182830d36a37bd39cfd65820e51c9073c3558c4f9adafa992622d8f16142455a2d34f29c23a0d1932c217ae6d7d7d2864ba4db3dec047c458a92f89741ef02c33ee04f4c5861ce83034bc1d1e88a527e3f60d60873ec633aa8b6a63f531cc7a42	\\x0000000100010000
5	1	4	\\x80e5789323bddb6f17a438a17887a73f6138097286a77bf935d2f940b4c31b27247185105f0881ecffc96cb75f0a18311b3e5d2c48cccb80064fd4b22872e502	23	\\x000000010000010003b5c4ea54016126346debffcc539bc9570b176b4a2c92a13a483f648eeb6d20d991eeeec453fb35b46638f15d3ee61b49ec7410cab9dc44cade704df68e8e5e949b7eb3acea663b5d29dbedf45bfac3a2d86ee1888eceb78d3053abc2fb534a938ed758d980bb28c2d4c2d2e05dbf85cda15617528694fca6bd7d65a739f0fd	\\xfcc3e6c534bbdc390c9adf54e732d1ceec647e421037d710a4383364bfae94a635178b16f89c753206b436a1e204e04703434a9f3b655a2dab19a593b32d986e	\\x00000001000000014e999ebca5662f9b39a85f49aa3a936d917e180c943e0f0bc0e87065801887f0fd3af1dd0038f124b82bb954252be97cd515b1566fa2f3ca266d5142d48f2062ad5536e62e9166df86960e54f160d7371401165086af205ecee621193b383ee17cd7ffaa4643b19e4483d0b8374dd34749034998569877118b5377c4d86ff997	\\x0000000100010000
6	1	5	\\x2952ec67233add93d425ffbe4505759fd7b1b7e98b62c13f4b8df7c89385402df010a09df08e58e963ea3baaf2752b28ca04d33b7343925221297c23496fc20f	23	\\x000000010000010025eb738229f95df8f964a71088af29e50ee2feac548e6c48057f6f989e8f7759302f1f612281857a5c682a984becace1d21820898f065af0d775a609858246324dede8f35d01ce68e918b96dea84c1368dd9b9787a77ee26fc53329ba0c926b2f58a93c756318c00cc265f8251e76a1774f901b2c19fa2f848ea207f5421af51	\\x9c5f080841980095f2becef0d06a85ae4108287dfa9b1f547186c5a79932367bce580ae9c2d7f6ec658fe6304d397aa23fe86132f91940acf53c0244127a4eb6	\\x000000010000000146146ca95f742d118054a0b9ab003f605c354f92191457410a4d72e406c80f77f5b123f6fadd2ac41ee148dfcd7c0c78537081108c418c01ce4e6d335bb4a256e290680e30e24ea6f790d7f1303517553809bc299b18903a502651be03a80035082e376bbe4a6344ff795160ab4bda18c2947bbeb57f0940303f845d64ead46e	\\x0000000100010000
7	1	6	\\x0d0588118833950bfa4a4679f6643c9a195d5b104abc43f5736d8e8422f90871ccbc74cf8f13403badf90bfb013fec3d8c6e32db5ff18f7a6c050ca2277cb806	23	\\x0000000100000100d5a5cf3abda2dde28fd77f40be4575f20b2a0abe31542f32bea91132d760420c6abe94821c9b7dea61e6bdf4257e0f4e7ee0c3d071b52a6d8fdc098ec9c4595e24f32b42942723ccd2f78384af3fe6da7bc12b2f542d56ddeabb91be9aadf0248aa71230d6e5f552e60709c5b559e3bac00f3e81c6d3fb689c60ef61eec0094f	\\x6a7aaa90153cfd9f4c5b9aeda3bb613bab98601870045136ba73eecfff46f215be2d5210aa1dd7aa6f564777d9d5464db40c907657961ef1f32e8f18baf7ec8a	\\x00000001000000017706f8f36d14376101d11284735b6dcd0ccab6ed7e61f645ef7dbdbde491d0bb446de6cf352e8ec28a407a3fce1b116e31b34530902faff9b55c9bde35a86eff1bdafece7dbea4e1c22aa51a19e16a125eb871be1af9357f1343ba8be32dcabf21dc4297b51271bb9f854e5c30b127aa902680827be8462df341db8294ce59ab	\\x0000000100010000
8	1	7	\\x756c36ca935e54fde710d78a7c5dce13821ead3f8392b4e54188f38bd09de725e7168aaa9b9012dfe18c560f8053548627b261f451f3d78d460b13f1e2d0d707	23	\\x00000001000001003bcaf0bc5a04bddceca69529d40aae312c78e8fa39baa0550c3327c529262305988b417b4d3c06fa15a205c496f4ce5556ce28309f46ca16ebb0a4dee2cb7e0f9be63fa3dd0b5b57f5c2f68a9f2bd68add89ae26442a3a16dcee21ff6a91b0e7e3688a5ad799a575e340e10c92686482766928d4529fa3db74589b1599610e67	\\x3660671a64118496e9b41a00795fc4c00f77bc92a58d8563b3ee3dc8789a7ecc780445a47e6dee3c4dce745e5502bbeee6fbef4591c008925e8a3b9dd324bb55	\\x00000001000000016548837c9a4f13a576211b3d830b60984a1da3fa748f7781f4516fc7a005e04fc4e6a306e2887c2b977b8e86b7f651377db713bd3dac2063094dd2c9c4476d826a8a3bb88284be42a9c22bcce9f3bfe013a8bd423a0e19b6f0493298d10a97ea06f09e6470a1c19c33ab191dea107e3b85231599e2a05e64ae6262175452f72f	\\x0000000100010000
9	1	8	\\x4dfb1a73b858b316a3e0edc3991cc608fad857325f3ef2c1083f3a9e048c920b9059695502ba1080a99940145a2a1695f893629a56c1785fa2ac82972e253600	23	\\x00000001000001000db8d9b011c1a912f901d38dd228073f5f74b1c79a4ad7be5231bf2813124a1beef1991c2357cab60428ef0b7fc5d401636459f9991f0f9b535daacb2f89c15281da2e35e954297d101b05d13538428b706fb5a9ee8e34de58c235688a7ccbba225a0b4831383963167b97f90f5bfd296fd839dee3482942ffab770dd9ebfa8d	\\xf32ecf4d0f18bb401833202449e69f335bb3bab785d27484616b00b0e1e0361b166b63a88462c7ca8a4ce6a3501d9e22f163a6224f4759b101f96be0c348fe5d	\\x00000001000000019e23449ea8e2b6d615a0462e1adf2c163b165b49317232b169c7fbcd2bd46bfd00bcfbd1d7d534160c5bf788c8eaf8a07ed699e28da5fa85ffab5287f580ae2ade69f7d1221e27af61c6c18568892cff606889401c1923b85300fb7c13be73e017b3df9d1c334b5ea494c92d07e2d49c65e2788f74c001531d90169365515b59	\\x0000000100010000
10	1	9	\\x59e7995506ca4faf8177d3ea5379facda32469e9d20420bf9caed4f95eefa7077fed54920e943ee1437c301487f6762f809480f4a674f7261c226cb61a819c02	23	\\x000000010000010084484db7b08924c0951feb8fce7cf9ecf3061892f4ba417106286956e3024f06d2234c8b0ead4c405ed1794ad1040452fa8ebd564ed39ef5a964412e7f9027d60470ac51cb7bd777b7b8b61d22e1a2a09c17e18d8f9caba5b62111297875d1387214843f1444e2a7860c2b010b7828cfb427a69dbf822335f4f2de54f9cda65f	\\x478cb81ac971140c78368e3104ff49aeb4fcba28622cbe947622f7034ed60c67f8ec9c56d371364ce0a38d209668834344b3511b7be821bbb754ed516749ce48	\\x0000000100000001513e991a4e91a3e3b4f04723aace08886eeeba7d037340a6ed3ead2fad8762bfcfc41e6b9ed65b42f17957f8cf2b6e8ad680899b0fd05b51c1339dbb92c17cf49a22520ca6636822d3f8806cdb9c13bd237696ed4e77ad7820956975ff9098ccadf610c59a635cb191d2f6edff891eff734546092f8a8af1b046b905a4004ef5	\\x0000000100010000
11	1	10	\\xfe7571e9c373329a920c5945f2a9d38fc97242e7aec7609639d1e983baa959f2d8b2fabe7d7fb4acd898cfb520bb28c1da8c0484b936f35a9b821778f080180e	327	\\x0000000100000100a2d25c6e7668980ab89071840f203087e0f0bbc5be69922e602fa57f771154ef6c4f86c57d0cd2486da4c9b4fea81ed0820207a861a30300cbaaf32d68d147bd0bfd969b8dfec3ac744957284213efbf4646a3ef081bd9ccb24c9d92b82f3d2f98233ecb6613f37d7362a8e763f30cdfe3853e6bcf301814e0bee3bfddf432df	\\x794ae962fc23c2853ba3f89b1c1a4918bbfa77854666aa088a265a77d7d4090f7f88e936b49aece057de01f4c66cd07a430b43ef1dd51970f83ca51d8bab7b93	\\x0000000100000001bac5c37c6544b7917009433832c8d4b16e05e6a3abad8e5390ff37de614a3aefe0a09a8c19850a61090fe1d3789ba4b926d6d3515114f3c4acd115e075deea84cbec4d1838687cf2fe08e24b12a0d7c1817fe75a1c0128b6bf0379b67214d4720c3d17a5e5848d43dbe94fe883791d12cc5b8ecc43aa492efb1d66987004c51e	\\x0000000100010000
12	1	11	\\x1c42b3eabd092488a6118022b61fd7ba571f5ba2d62d75899703754c06c1b7a3353b2a6f7b3ef0dc739c875860182a64930a82292b45ca696fb5ba9600f8b60c	327	\\x00000001000001000e31a0811fa4f73d92fe18981d18b081c5ae5221e785bd4613a1636115cc9a52d30c73e1bf9e79651ce9e498bb3977abc1b6eabe17f09433a7633e766447677d21cab2fdf1efba58d56d312c429d278ca09f6fa9b5111a34f21b35ee6ad78032fee9ab75f88a0dcc497134d6aa1fca6d2ac5131f4489f834e9c95bc404b1d801	\\x456890f9520a4afb2dd3f1ec8ba827a0a01d6fa1e113904ebe502c0eed2369f27c69df37aa9361916be76e132d79cbc3f2e58adaf9a11547dc4351c46fc4b7e8	\\x0000000100000001abee1699aefbb0d458fe7f6762325c49786034b3dc01ccd1fe8373987f3274a308fe1710d017c3781b1431d87535b3da04586ace57662be4c530994d4ce7475f8b73d67f619579320ca859c53dd2786b25f0d501b2f9c3e155c7e68dd38549dfa7723dedebbc3e8eb4ebb6630ceb01d5ffeb3af27eb7e908a1616647ac429675	\\x0000000100010000
13	2	0	\\xf67bd4ad4e611521e9370d6bf38e0faaf00ce579462fa3bbd48ee1e421b1b00537c96b26c9f98c696757745b122bdf0c46dd33b71a9be4815b20e9bb33754808	130	\\x000000010000010002a76a2d2118faa48639ec35a44acaa89d915f5ada9bfdcbc685733942adc00fefa06011670b8d7864f29cafa2bccef0e5fa6db239620a94ef2026bfa778efbef8b0f39b36a40d3dc86e518dabf9385d7c7b63591bf36e87469c13c7a0b005581f858dbfbdabbf21b7f4d24cfc348e403411dd7299c9cc724e73d3c87a213f00	\\x035454e13628e43912ce149a15357ec2b1c4d311857f3d16df5f8b69daf1741dd489286bcb5d242a3ea0d29537197f03037ad132b97faa2825c60873847e5a57	\\x000000010000000123ee389be9a087ab799e5f2c3e4686d54388d11e1fafc2ab795b6334508b120fea7d06d637768d73e20865a532cf3f8810f698db0252209fe47e8a771187d21e9930563ed877f231a5489c66fda95e5a37df051fb0e0bf332f5696ff4a29442760826880361ad3262a338cf4ad8f1d58a5761f06ea4032178ff2571eb1192405	\\x0000000100010000
14	2	1	\\x422e5af4967faa8e23c5d48ddf90eb9607dcaf6056864182b2837a511315b7967f9bdd127608660f3ca895e179b15ead9938d4c8c4180e14248080c11db95501	23	\\x00000001000001005485201f57ad8beca3f26a6d7334f2ba5574bea3d73b9f8e9fe4f67b075baf54ca2f10210bb04918a3a783aeae60556117453bf80c8179128bfa00b23adbccee7f61f47972b167e5cf405831447d9d3b94284cb1a65b2a03a4d51ba09bedb3c703ea1d9496c50eb830b2ab7401d3a32f884e9075847165eaf7212610d796b20e	\\x445f37d70ecd55602cf5dd7cce0a6863d592741038ff387370e750aa3ab1a209efa5d8631c2f716b42b0968eb4ad05e128a605bbe31825bf614ee72c9f78210c	\\x0000000100000001c06e1267bd0b73e3f460fb5e326c336f2b14ed59c0199778227bc451857012c6e8135c3d89d35e7f6c8b8f4ead6bc98b1171f8f97bedf6b50d8c24a42fcdc49c8afa3a9fbe1261790589fb49ee393bccb03b3a2a7a41be8dff2ba94035536c72c46ca9a8fff736c7ba8b545cce465cdf4c16737d7a9649eba7ea022ae3b0ff0c	\\x0000000100010000
15	2	2	\\x6a58623b871b937e6010c4dc104b305f36a11e20b261b8362e11f4c10d0b78aaf37e6eb0a92359d9bff683ff35d2e6d1790d139786491440d0d8507b39a03d06	23	\\x0000000100000100129894fa2e4465168397757dbf80cbe5ad29c960823543d840b13a30e4ba47f6ea74acee32f5847ff61952670737cdfc6e65908fc6b4e4e27a8997eecc52add558360758c9079f8445d6d1f3fd12cedba02e71fd8515290b5e8aa78627bd97b0c167b3ef706a7397ca04740c3d19e1e19ccb88eb1c11e7aa11eaf902a79f6189	\\xb8a97b17c0f6b5aafcec77899e685d4fddca1c58b5a639c1b66ef400e9e2cba6726ae6c437b1b79af83db42f1096eeb7ecb994aaa35c81c0d8641c41464e5da9	\\x0000000100000001600ddfd2a314c683619885b12c908a8dffa1093e24a5015015534fd16727526c14b6dae3b3cba8c146df82921fae9e6df6938d32ef1485dfcb47a0682df796a1d960125a0a63029e8e0d3a2c58a5c42e47743abb31db54a1e79c225d2d6aa30092f55be14127173d45260871bf1c58f48b2105aa8c98a687ffafb68aaf97c91c	\\x0000000100010000
16	2	3	\\x5ed87cee3eccc41344a0eab99fdc019720bac7489084610e77052dc55d95e3b9e7c831d79a2ebf405a146cfbd7fae87be0501befc6202ad44b5bc43dd358f10c	23	\\x0000000100000100a2cd777635c694c62eaba11fb3b8eac66ce0d63e599c7a1f5c2c5f45ecb596d8db917a68c1b17a056527916b161f8fe4ce8aff75e5545e2251c6d22bb9d98348d9b25db46140abd5b7241b982feda1f637be2366a4633d515a16fcb542f8f1429a56aa81dae0116c47caeb844e4a44b49b11566e5d070a796c00e6ca2e827ec4	\\xd6bdaa81521d3b7abb1e3bf9439be4ad8709116cd60d59064337420f98d2d05695a90d2b5cda67d9cd1e917d018895f348c75e85db10aedaf84b08a1f5fc4575	\\x00000001000000011688b093a36d3624409dc37cd322171d5a09fb619c10e201f66c63edd13f4df567d93b35beb83b72adc945eabfc7705e63635b89ee85ee01516ca1f0bdf89284a7766a98bea379bb8ed542834b750d2de95268729798f1952f81f252a2fb5ae01c7fc7deabb236bee369c9bfb89af7a53570f045561dd314676d54be65141c35	\\x0000000100010000
17	2	4	\\x44ec933336bbfccd7114ff1c78b39b01e7ed68885dbdeb5d7f21959cec24082ee84601f412b0267ec268f4b20f8a34f7277aea0560b5da69f7259d2c78eec907	23	\\x0000000100000100985bde2c4aa21ed0253cfefb475d5b576879da28c960336a0cdf31734cb2671a82bf5fa82513799422aef2f83a01406a2469ff4ebb288bc71043e87b6c1681b1fbced4bcaaec7ecdcf6bd8ca6e94e5a65c165b6d16543081f606e30c3cfa21629cadb2b17daeb82247899264e12f648e5ddce1d345fd85196ac5596f21bf016c	\\xf63f420e58dab78df9009a7875a09ceb7547c8c837f206cfad273c6d2b18cabac187778f70d793e356c6cb950a2dd65f8f072d7bf74cd7e8b5f238fab439a6d5	\\x0000000100000001b383eb8167e2538e3477a72f0589800bce42bd781fdf0bd0b959517264db16697f5747c1f81adb6545c73f6e6ecfc889f0da20e04739f23495fe36d4b3e375252e668a26eee75869b1cdfc02d8507ed0ea24af8121a4f094d6b315b35f7eb9a4bdcf82b62a1c64aa7283596e98688e416d743d9b3cab642cdabf48c4b9657f3e	\\x0000000100010000
18	2	5	\\x8e7c92c08d5061c96d1e136844feb3af7136a8b7bac01ff34b313de15e9cefe1f496c55f57703db8fa7d53cecfba385e576955a0e2141d2300fda9ea25771b0c	23	\\x0000000100000100c9e8fbd2a4d24f551d5c18a199de2b89c3482d565471ad24c602dfdca5f86d9e8558e8ab7032014b84d7e400219aab757f6a19ffa7e0fbdd0b0eaee9937428db6f97e260d154bfcc41a6a718a754b7cd6fd92f2ef0395a45ff46e7651eb69725acb1ce117bb07cbd2147d5481cf5ca0d40e48ab7f1921d98cee5b4862a22e482	\\x6346e650ed4b18e7b6cbf107faa8008523d33ad9b40577025d75c84e628d65699ac46adf986382f43e601a6d39b83659e9707417f90e47d9f5daa2de6b148307	\\x0000000100000001bb244a7abf6929f04b55b19610d685afc15be1fd7b9f720ef6018eafeadd37ae6d9ef3235817748de3040dd47eebde546e9ce18a9027a4791db1fc86bf92ed0a63076c84920b7f7f9368940494174508e64751d70f5c79fa86154d99aa6effe27147103b42b24a92b5e47c36c129a51a7badbe9eb4b780642f4c61f848b371da	\\x0000000100010000
19	2	6	\\x3358f35e0c6246e275450ace1b5349e0f8f3646e0c5440598be01c26ff37b4a63809a0e48646d37f9b4281b083491cd67bf4195a487268638c335749e0d98a0e	23	\\x0000000100000100203c28f982ffd23beafceaa60e35887a84b4f307f0eba7925a5b37483fd2e9e9c52b19206e8c59b0de4fc2f802cc1ca4c86fc7c1d9f3543991a9c53d1cb75d0eadff06968c76479296ead7147ea08daa696d43be9692502a087b3c9ffa79d50cf621794669df0dce6b74f70fa3674fe4dbc7e38f922057dc4d73a4705e48515f	\\x7260a80290f60afd61176e3230508dc6c8347663195df35b41250632d4a9b479a2838c06ec2e6a6a6904a63b5624a5548e338a5d1893a0c3741265d157d7844e	\\x000000010000000171b2c0070a415c5b508f1beec02d39a509e5965c522b4831799bb8abfaf33943c724142aca1d8cdcd1c070653fd76558642544126074d2222b465045e9a3031a6cbfbe31255eec26be3f496083a73d4551222f373694cb5c2bcd21995b1c8b501f678fc8709cb8fc57c2f3e9cb2c68d666c2a8e51011eec9980f17a8bae3bb14	\\x0000000100010000
20	2	7	\\x5e1c0daa1c7e4d92773ecedf48aff3e86564fbe8966fc1005b8c069d6d8ec67cbcda234d41ceb9d5026a06d113dd4a2fa73a7ba350b5b1fda6487d23bef7b00a	23	\\x00000001000001006f912643821df0e65855292dfeee0f16d2bd9187249fb854603d9f6353444146170cb4e975d1caa9bb72daa783d2b31bfe9ef9ea66d2303e37072f0e1435a4bc01d9b6f51257b5d78d55afd3de9779cc1a741f388a8db7af43cc70b4eaaa38b055d0ee9ef6431b6680a46b9784a6fc16128a34a55d99092e368fdc90c3da0107	\\xa8eeb5a99e56e625fe086a1b66515d3e6e42ad2e947e91671f5bc921d48c12078506a0cf44c60e4d9f385416a24aa3f7bc22442bfe5f37417925d3e716abcf87	\\x00000001000000012645605543accf1e5bdf4adb7e401858563145abe9c65e05f8b24fd1a36cc8d9775aba6ffd074a78e3fd13655d7af76544665fc835b6f6ee1eabcb9d96b1bd09f9626ed81d479769581bedcc901f4c1efdcff7dae20e4e59d5b1b30d6bc386ee45cd64faa27ea4dc7cb28e277151089efcaab6d7cf93aeab1b8c7813cb1f80ed	\\x0000000100010000
21	2	8	\\x2240dcee9fa754b3bee1ebf8a74998657a68805bf6b685c99da71e76e499bc0538fefa9130dc67b84a415e273603fd22d3a3c0902610910826785c88bd6c0606	23	\\x000000010000010078e41a5e75b14d30791fdc8edb9f1b0cb4bc6928a97590e02f321c980158052394e39830cd4e28f6a11007b88e10677b8f0c3f26487cffb8bfb0d522d6bd80b806471fe3b1fa0f98bd5c5581c6c1641f76e3a47af986a434ded1ed011758997a12459e650e7d3b2be061d01e1e486a87ddc962a830bd00cf2a4299eb0cbde015	\\x85acdfc8622eff1ec874c98ce125180c43309bc742eb041c98aaf1f8d60184f2563a723a30ca6c9b9c1cc5e37a53d0c8f738c33b212a5534e20d05d1398ea1be	\\x00000001000000010b32f72f4b235e5a8e14e65c3a2a1a65fbcaff8becc02dc9230c9e8bc90b87590b7743e15fb8d213196abba08eed2d5742f3d9c99c825db0b2049c9178a066a2ccd568fa5ac28a6b69fad6dac3a9b4fb9487bd6b699f628a7a9a5880bdeda1ddfc7878d67c594b39c81d8ae546901cbf11e55589ff5dd931cbed6152339f01bd	\\x0000000100010000
22	2	9	\\x0eafc4fd27abaf03a6d040df8fc26e11d446db9c546c6539e9f6b8e0871b2e5bdea00cb76cf6c8f21a02e2a07e0a79502d59acc9a2480b6655b12a454d88340e	327	\\x0000000100000100471dd9fdbc2a565249dce81494feed3d885783dd0b7f5e7efa463bed1be8066d1fc942d7ff9053eb038002a6c468502407d5b25bdbfdc486b251af033a46bb22c6bc79b300f21b2b7ac018078f03ab7a6c92a95a506757a637e81a25ea67aa63b29c97a4201f1047d44d801fd74ffbdbf20ab45b1cb52354508f3b8529793fba	\\x976fa3cfeed7bc49eece4569202de5483f43219a2aa90b946c056dd214d719be813ed1a3a7be7a3694b96a5fa8d909037acfd9fe4ee43811471c18afb84f8e84	\\x000000010000000125adef66dbc9ce11644dfe5d4cf653c949b7240358c4c053fe77bd53f58fd52e10ad38596929028494d899eeb3d0d52d605f845e7708fa7f270c3b148fd4d9ac5c2a6ee152d7beedf81ce5acf00f0129a621252ca1725a933943a917d034b235b8c00bdcb27573ccc2eaa6b395c7878be63f97868b2a9502f9f81c662e7a8d34	\\x0000000100010000
23	2	10	\\x349f0c3fe774bd610788d4b862fbd840c06a9aefbd78240c75aa46f41cc9067e1334fa1b26b7b367cf531b3e08e2a6ca8ea5e10475b7ec72aa6e01d736fd4708	327	\\x0000000100000100d0d780a5c591bf08c05795bf45d4beaac17d61aad55e9e88c7c7b01573deeb17c57c319a852607e87c2b4e411b95e1c8baef8dd4c368966ddb82a64c01e1ce39208e6573653be5dcdd27f82057ec8b7ddaf18e139a57afd900fa7badfc7747163cb23bf7b13656a299308aec65951997e821bb7b6c2c5e24a6a1ac856b5a847a	\\x800bd0350e27196467da6559fda85759164a412bc98c7b81c69bc35dfe4aa659f8860281c31c1265be8d9602dfe0708527fb1fcfa06374b5c072094942933547	\\x000000010000000135c61e9dd96f4cdc20dc072705f6a1a38df93e18e3f786fd15be73ffe4ece44ec20c3eb0fe7f8e1f8a393b8e862aedb2ce44084e44d9adf05127bc8d90255323f2df4e0a4545f475ff7a41da44460979ddcca2f879596def36659b37bd098c2758d812050c518c41c8aef443954c2c61311460da77bcc2558663a1b2424fe721	\\x0000000100010000
24	2	11	\\x81e341ed593c22e60a87bbfcba48c306cd697f65dea768168bf4935728afb75883d4dede9de5eee173a623628ff4067810580a6c508689058b6f14ab56c16709	327	\\x0000000100000100adf7405842f5dfcc407e53dba203e20b954c270d47aefc0a64affae5debd4f660725f3045b7710ddacd0f32e12ba852d11f928606463d6177824c4628ab445b013a4e163ac62b90c3064efe506ca1602611ee6f5a8ed45c2e065c140ad33ec4b1e53004bc3088143c5aa986c9e32ed19116f9680e84c3c28f0a097e7b57be65a	\\x6c7ef7f47c3fa7811fd8f84c4dbcc7c27573871e8c5c7cb49f12c7c9b44b2cc39362517362aaa2b907c454d1fc671663dee764559fb57df81673a2f568e7f6d9	\\x00000001000000018c438e17f4c4361381a21ab188e0d7a56d86da031ce3af2fa992866e92b59ff222b240bd2c8c38b2d4df9576a439e4e8ac760a61eeef4eba4c1dfa88bff8362a74300d757f123b0acdc9d53be72bb539bb425b03be8e7f05daec4427f18cd00ccc02e8ddac7a242d511922fb2d6abb02484a002b5d79eb78d770960e30d5d1fa	\\x0000000100010000
25	3	0	\\x0c4a303b1e80284753b92d69bb9a6625b38d5916658cf8e254d5b45f9730c879a75f4681c25200cf936ca5a9537b050dadef8a97e230eacdbe932b04db7c6d09	406	\\x0000000100000100a1e3af77a991bff4aeacab3d7f14b0c96bd7a9ebff45d9e03fb21e8de672c8ae346e2cd3e38278dcbcde53c2e642289bfeeed47553c64b9745fe458b7bd2b0e1fe3d3ca76b821093ec1262fd39f20a82e80364484ee69d82440fdd56c1789926dd7894192109c369dce8f45281152f58ca9f9e413e142d4ed36c934d10334520	\\x72f2cb80c31ba608985635ac6b025cb807406b2b46a7f9703691f8a5a595f3c6a8a62d6dfefb928e0178fde3184ec79bf8ff58723755defc7526c4ba98a1175c	\\x0000000100000001475fdd79367e63b7a11dfa2bbef6cd64984c4df454204c50cb55c88ac1e0a3b96d51066289a728a76f6d5e7699babe079ba28fff6801623f22e7de5fb4014a1b7785fbc1343da36a6e329c73774ea6559085d5ec2c3d6c7cf2ff35856c2d4c3a05f6c7caa9b1c387324728f67ad2f2e658088dbcf17ce18f115d79993a127919	\\x0000000100010000
26	3	1	\\xfd456b7ec061504a1fb425459d78a4d8b1d97423e0e58e424e60cd39f9a87faee2e43897f7a213068f603f44cc6d809ef008ff0049bb69b3940e42b7657ef207	23	\\x000000010000010053fae77d9d4558ebce411d80b579586b142c844d4aacf932578c919d3d7581a21c010fa96227be3cd369fe8f1b32ad3dfb208f9f1634b12893d569b9f73d1c6b23c1fab3bcf370c29825fcfa296ef747e2451d60fe81926af8ee2effbb8372ad07f7ca1c1cd2ad9f5062c4da0743a3e60c198b0e3a86c1bd5a40d72a4088094c	\\x34e8c6bd6fb86441b3bdaabc23c34784d64af58b5cfdfc4d0bf69f0570a4684a9d3be8fafe2f6923c40996d576105f5205f23f11935d40d08a68479ada684be8	\\x0000000100000001cdd7e9f4f991752b51fe2d8533cc3208d46e82346ef56944981e86739bc731fa5c166312fcf86cbb29b4bfdcfbf63c347019d905364e770a474012655a71af30025908161a10eb6d438350535c6c48128656ac4b106a6c3e77d03b12940c5ebe47d74180dd98d729c30f04c013fd588d2b207d4d7f66c64364bec93a1984f6d7	\\x0000000100010000
27	3	2	\\xf919d7e1b32398d8d9fb4efba1ea657e394ebb6ee204a922e50a9a94d3a5154c5fc31833a0eab524e0f486f9b6cc2de20ecc2f435bed42e64a9fef99dd511509	23	\\x00000001000001007a5559ab93f4a9fd6cc8952d7fdf25104e3435efc9c8f08a681360afae2aaa83e97e29a18b0d18dcabcb3b1e58d0675d9dc45cef71b67d7af421cc82a57c780efa8516155e1cdf4a1b9608982c2ba004eca7250fc48f669a8ea969adcef97481db72f68675e38d18d49671948bc4c73e2e354e9e4e7fcbf9d2f0c0fb7469191e	\\xd293d639e940b9dd1c21c9498e59fc0638e847e13cb1c8c19adb7b6bfde3dbd919827ebc6629a0ba2582a8d8a480f5675fa72d10a627b7657bd955150f0e423e	\\x00000001000000016bde9104f1920b73777ed735b1a28e573c11d1809f16a80a399fba0db99cfd00674e08da6e6e0263364bd65cb301a20db3f62ee701860612f16fbf80e6af8999a1340f339da1610bcf8751534c5b7bdd1c3a9fc6bc492fbc6b7084d7571d6537e4417ede21c1b30eb82768fe650cdae45bac14c376a554ce69f8fbf130e6fa32	\\x0000000100010000
28	3	3	\\x1a447a7a4e008a30f9e498eddb4b6b492d120c69a82ab356daf2e3ea5db8da02a694e09ce33b4a0bdc2833af54a8ba9176c77e8d2d4f011048de3bfa71b5550f	23	\\x00000001000001000792bab7fae87a6bb16b432a385546553278749cf65eb4fe74cd309ba23657fde56b518d9677b33458d4f8ad174eb76ff9a9aa9ee83be4a3f013e74a4b6a065aa75358ec16a66535c7ed185258eb246472ac0bdb7a96cfb0924f1014b55f00d9b96dc1d54e9e20ce4333258bfebe478c76e677a097c7bd6ddf897566a76a59de	\\xb236a22b95c2ee43030ecccd0762a9b88c41e835dac81af9cf5f2a7f6106c0760c2f679e399cf16e4ffaf6784d139b9872b143af5b7c228a30f723aff61af69a	\\x0000000100000001599af208a9332051f79992b8e72524534d82fa9df325d7ee9d85f35a8e59d6240cc72e3bee93660397e2d24683df1c11b27e523c97e0ce7566401a5b397e3829fae23c814f33b73d603534b157b55a232bcfa8a28b2b0bc54e25c4df2052e62681609923276efbce067d01b560d93d535aa59839ccbaddf1851ba330a793d578	\\x0000000100010000
29	3	4	\\x6e0e2dd26c7d7324cb833c3c3ef7c3ef27423a87ecd6d75c4bb29c4dd46063b55520b3911664760dd5a048af20de9ccdc1cd55101a086647d6d7caa15c4a950b	23	\\x0000000100000100588bdf75458d2b7e153f1af4a728fe6c2ac24fd8c22ba21d6e2be282c3ef2b9ca3fd999495a2c69c1c38ec9125c62c1f05fade1566a170576cea08a8a6658ae2c7c4ad668e5968a441864c8f21a196ea80c01cf7c2cbe35f314a66410f418305ca378f710771453d863401ff4a863038a3e0224ffa06bfbb5cca8f3daa297cc7	\\xf539031fcb03c830dd724e8327694491f8d96e22a7ec0526de6c22e9ccba058048e0dcc4f5c376d0591194e6c295cc14c8eecaac1611e5bfbbc40365a0b0e30a	\\x00000001000000017963f48b8121a85df06a9a6406a217a4dc958072095ed0d968c40e2c5286e192d68d86e4ada17c5b0ceb63ef050132a343ec628a1f7a49e0286e58ad722d1665a0d33528e2a89e2aaca55d0c9d8ff529c8e29010868c48347ff857652ea5d8753a8d8ff240201f29ca2f135b11a51c63d2187af5817c51bce77c33b94e117459	\\x0000000100010000
30	3	5	\\x7fe9cf524755e75e19ea72380974402340054684f19316f1f16593a890b9bddd8522ecb767e3282b5abe03455d95ed50dd70fe638f49d6ef9ea41ab87751b104	23	\\x0000000100000100708fc01e9ccb13aa95bbd9ce8d551ec688dfa56ccfb9820c3c2374c6dfb652d502b5dffff7d4a6769a01034033d828db1cb9cccb4514c3610a61a5a9b193f761d14215537c88e3e0362c8e70b14c7a0c848fdb3f90060f5e520a1b16982d0922d23facd6c1d87584d63663bb27d2eb180485169e34f16fc628780cbf3a1d925b	\\x548eb9830c34b4d616f01f785cd3d37c354018f4dbe29b4d49c0106b91b2a55d2a618c14e7cfeaaeec2cbd80b75056cd1c62e66d89153b8a0b8e9b40fca66e65	\\x0000000100000001cb3416c809c9b25392ae44557fa68abfbefae56209abb4d5fdc0fc047e965a8d49a469dcd86ee275be24cddc35f7ac1d1f689a912b854ceab9880494272b67bfa2b00e211da028d3c35455b429eba1ec99feb8ac4ca3f2d68d5b7930569e0376cbce7788523572558690ab46eab695d06d6f83e69d771d0988922fddccc0fb2f	\\x0000000100010000
31	3	6	\\x555bb2c4d8c0376682bee77b327270c0a01d9ec70ec9b40d8271bab70a89ed56192e123fc14fbab74acf69cc2edd33658af38442b81aa3026cbf47100d561107	23	\\x000000010000010007971c014a8c73f5298e1ba3b83b3541b704edc6a6d07429e517f526f7277dc99876eda8bab49a45b6c71c7a1075178d7edd41d51cdcc170af05bb60ead57677b5d0decfd37d1133b74dcaf3be07a02a807e2e021539953af84186736eb13977afb4e7f7b322b21d664df642ad6bfe45077c63b69893e2c64dfcd92aaeea27c1	\\xe2fc06a425ca9e224a667b066c4360887a183095e8ed47c05fc0d453d0fe8647011f9023db1d5a00d43490bb311622d4a0d3fea6ab8a624e141e66be497af1a4	\\x0000000100000001621ae6045c76c020332e4e4559b57767c487484bfec5d127827e8124a2069ac980819ff758b1032e3b2ce0b7bc00a8fecb3dfecc94c07829d5607c0b8bf5cf2077c62ff4771ef729809059d48e82a028b7a25b695a3bf31100f016311b868686ea40aa8afb1c7dd77b3a4f12a5208b28942946acce9614e34b6fd01b0654be4a	\\x0000000100010000
32	3	7	\\x0f8d575370778b59257381ab8fd98c9cc920b0ccc76a252767abb46c41e26251d5fedba45986f4488843e9ced8daf95e6d8b39afcb0d558b9ca2ea78875cc001	23	\\x0000000100000100313771383d7c64e5025b102ac550bde81d57278a60783599957379293ef015a3370dbbf51d8ca6eb2e2a1a57653777f91f31bce90aebb4036b9ee7b7eefc0dd66f82bb3e4c69b3c6b5a0119738f4321f828185a9546f7e326077767d7c6f6deb02529dfcec284a685e728df270d29bac2275256fa36884d0d29fd4658f119ebd	\\x46bb8b0c8df723fd2612a5d8daa01158cf38826c0db78552a45da7023ba3f23c33a1cce84765bbcc1926dd5c156f66b9caf2249a06ff8dcee643a207a337c49b	\\x0000000100000001a9ffda5ad85944e1d6c5fbc56dbda331397f32df30ec0bf7a3f19ef297f4f0f28709ba7f38cebec862b3e5c55658ac5c5478764f00354e41d0fa9f73ebd234fffcd3a71482dc70f59ee83a66549a301df7751d925be5140690edadaf9a27cc00ed7b3d53997a450c80ee99f17561676bce19370cfbd20a361847fd5f1b5c29be	\\x0000000100010000
33	3	8	\\x0767d907029455c72460ad01158a172b8900c3d1f53434ddf41bb920cde5213f8e2cca5641232d5069fc793dca93390793d45921fddd3df24a4ee533c5137405	23	\\x00000001000001007edb1940ac4914a3006244e4bba9900c802bead09beff9bcb78ef36f4e280cbafa7b1696facf8fb07ce19ada4788de415c83993dddc5eb7016b0c3dc4b59caa92eea0c69895847046d105a728817d770f831e48c613478f99cf4dc0077e644896fde159e234f052a12f14fb20d09ae0b43aa0edba6a14427d6c9614fe5a4dcd4	\\x70b618e7c4797990048b029b3842c2ee6a9c665a2a10ec1b046950f75065f6cb24f8917ef868feeb789b5aac123be9226947d34a3ade20505b822241d2497c6f	\\x0000000100000001d4f69fab50587bd4dfb476d63841d1d8382a927e691815fd71308638bca18afe1f8ea3a9ec5e0da577a439699cdc8a4d3952c30f435bf5e6932cdab1dee3da6886db2698db25b2402d0bc340a2e542e86b47dc66f0ce17c322226fc21088e70be023dd952d3dcf9f31460f91e01e57957b74d1aee41c50492bca6ef72564ff33	\\x0000000100010000
34	3	9	\\xecd902eb83936d1285569775516851878e61aecbed0ca38f75e81078748a2c74c59fc48c9cdfdf21986385944338053d8d6821ae8ba53c2ffb1fe37ddb97f209	327	\\x00000001000001004d93eb44d76e4a59c77e687ea03c1e1786fed611de09681b5d60e672d3036a502627bdb41a12ef577c19d304719bd5102fb3e778bbb9576a43847b66ed84f6fe02bad873404a5b027049b0b2051a59c9f7980237f74a1719f6f892e5675c2a84b5ba286d62e62e0a2eafb2bf8db7d28adf28b0b2e29f9f8f7a1f27573f4a1fe3	\\xabca2735012168cd12bdaaedefd1ac6972e1f08dd06b707217d37b13a9aef76b74fea2045a2fd3d50d99e339b4c84cc27723a5c6a9e3f26eb6e802fd17a27213	\\x0000000100000001c4f5519f6e1de25aca5a9e7b569c8479657d2012331b74e8d35d8fc38a1c7107eada7f5e07f4643a072dc4b966c46d43a5fcd6bb1f682c9f3e5b3dfd9e22f38009b094e630f07d15a43e6f285a3168082fd633fb32647dcd4dd3ead15f49bd2e929f7061ecfa38288a56057f276778e995071ceb8c7550e21b2eafbe76d9e158	\\x0000000100010000
35	3	10	\\x8192303c1f4e0d87497e5984845f7c639e18f082d0caba721ccdbfd5c31a8c8f472fb239030ccc527fd9be02d0df7ac8aefce266cb9ea001453af664239ee70d	327	\\x0000000100000100b9d8f68e2da14d5c8d84a9d9a1fb2b7f441864584145f896d1989d312f0ee3354a3572210641def71a59cd896c7578d498b2c237d3d8dcf059384a97e3a272ba3aad01db07421a7c99956dcc629586411468cff30ba3cc617cf9c044704891da38d29f6ab8dd87a5348f20181f1b740d67817e69f12b90eb3cd723f1d324e9cd	\\x510dbd053a3d97a6fd9e9364406a6d152af7417b13f6f69643d737c0b7fd9ede211b342248311186e8dbf24eb3a3526e430500983b623371a5e5b73ddb3b9842	\\x000000010000000157098b328aa6fa3e7b05c4bbc08dd308ae5711efd63d58efc855d0a91774fa936da899eee3206d3270111e708a91e2328f1026c4a429c80a9a0acef5ff7ff180418ff52e38705a5c2e4308031d3fcffc3f0cb74eba30876d1d9073221caa381884a89bc278d879b467c7693c7172c7149d3fac6a68e8a598a162f0ab790dac0e	\\x0000000100010000
36	3	11	\\xa24b4c7f4d836c31c82a36b99eaca4ff864114da7014c10d54cf2ba282d8aa82b2753d0101c24dc1441354013d14f55087af2ac6cdbd1b60d17d8c918d532e05	327	\\x0000000100000100a1cd89bd95366612697ae003e596c47d6fcf057122c442466ca65c437ee02975adf31450f3ac6bb1d2f96001187131cace91fdf2bc90b8de8b20d44500f921772d9f53373e1547a9df9a3695b524b7b39861a5ed80b15665b2630a2feec99a53cf0ed68addae7c443a6af98336215a87c93e08b0c0aff13d3d316bb622bbbad1	\\x81975286df1e12df9e4d96e3066329c1958e7706e0ee9e5687d225e13a94c7bb6e75045a4b1cb0099e2fa3f6f1036f429b6715c27b9a45fad71745a400e6074a	\\x000000010000000198d72a8f8730c612ed7213f339b34d98dae2d838ab0973e8130c3399e2f9fc6574adfa258f4b5deebc0669040abb03f67f5143c86a10f19ce91c947892291f1e0f182a8cac74a89e27714e204b370d1698fcdfa312598c819ff8a488bb43867a7a0076b0cf5d3123b673fb97d9d4790fe06af1b0e7a741dff9c491d8a72496ff	\\x0000000100010000
37	4	0	\\xb35834e44bfdcea96852e1bb591264f3677ad9ffd3d4b27485c9fea238ad272b21ab3566c21d3df7c87ff1b3db093bb130990f2dba2a85f25b54b3336908c808	57	\\x00000001000001004e3997f91ceac68c076f7b1b85f9898947577ca706a7f2a6899e1d36b5ecc19fa168dbb31edbf010f5b341541f1fd852114b524d7326f91a32e641691df656241cbf7e24b4337fcf9c66bcb99a0d1f0c66f453646bee61770b47e7cf6960c3f1f4f9ec35d21eea6ecfff8a9244a12c24c4fdb4ed4f354ee065e89d6dbf8c9021	\\x2e1d380c49dacde48539aee99164816445e607beaa51ba779b373ea017d3a751e6b114599f4bfda47744df2247b926889401d26468e7855eec6e0015bf045691	\\x00000001000000012b18077f8491d75b7e36c8cecb1bd740f36e1b538330325bd08ead047b9dfe670c64eede62e592f4284297cbd270c02a4fffbfab0173a1e4353591148b29770fd1410e6a208d16f2edb0ff6cea978b3dbf94e572a45dc576613a745e5fa4da7f5b024ed7fee6bb1d24ffd7e72429d6fb18c9ea08ede5aa7a1434b549083bc004	\\x0000000100010000
38	4	1	\\xc4130dcdbf634505a8dc2e2eeb5b50b2cd52001c212b5443ff427f56d82c4d1d0fbbf1dbd167163da580cbabc9e979b3b2afa29c991a58a5e13f4a75feb98a01	23	\\x00000001000001009f249824b60dad82eb4d6d0f4a5153ec7baa3fbf6c8c479f92f1ae4c8814ade621faf0a843b9951406ae43f9c4595ccff6eb4ed58fd9faab7a3b1ccba904de17e1e91168d2b3e2f2340892cee86ec1434a1868bcb97439e57aa56d7f0dae6562b8c856509160fc6041c126ab35afc4be67085ba02dbd707ef12caa223e5caeab	\\x93ce024f1fe77fe485c196f3671757ef263002c4138a0855fe3e291db53c731bb34b70cb2b79a606e1771cff1898f905ec8f06a34424fd499aea85a285ef1b0f	\\x00000001000000010d7768df5cd5c52aa7e8d22adf5e1a9265c881168d81989e939a0c51b50c86819b19c1da6cfb9a69109b59195f52996d9b3dbd2452b3fdd772685da737c757fd9ad095f5668dc3a68a39e85e37cefb89ecc43b7454d9a9d0c63bf178bda85ab9de79a8caeca01df2857888670d78c4fcdd08cccb7f52e7e1bd54041f89d6163b	\\x0000000100010000
39	4	2	\\x2db6f3397cad232e23f2838043407ecc278d6acb5960f7178566e348944a9e5218037a7656480c322985185ebe46d4298bd1a4466a0ddbeff5e1c2fad45b770c	23	\\x00000001000001002e97d6adc8f9b920def37af8a3b6686de015200e469b5c334f2505f6d1c34ae6880b67e9af6d4259930386930b1332e42d8d0ac42b155cbae104a155676c31f6901310c723d7fbedb74629be2706a079ba93320537b180e45470d368657c2fa4159fa99fb9c3a126d2776edffc8a713195b3412d06b5285c6df3598474bcee04	\\x304bfcf8432945df046dd46bcab0be131b395ecca80b29f5407d6d1eab52aaad40264c76c829b2de7a24f7ae65c518de865d056c9f8923e4993e452aeee88445	\\x0000000100000001482525bab2256b6f37f48e9a78b33bf75d30cc3964355d52ddcb8774ff46788bc612b0cc96af03b80b7a421e1e14d73d636971a5b8f0cd38e9082df6661ea3a5ff31fbee951ccfbafbffa67bfe6676f7de1bc09d8b566090cc4f0188ec9e9841c1a8ef092611d0a22cfe99c9f53a443334893e2fcc7c56059e1c604dabe8e22a	\\x0000000100010000
40	4	3	\\xebd79d7e08e3cf3d8c098b90b1bf0726e77708ae925ec79a872a553a680c5770b7a94eac7cd84d4e6515864c587f347ef1faee0696a4dcd305493e002daa0008	23	\\x00000001000001001f97279e98fc2b2c5e0520453e909e9dfcf8e3f5fa00ab581b92786e567e02982f112b9c80efd5360f8c2437f53c5c9e048a578754bfc61ab59ec4b06b3fcf9afc5e41d086ce7fca804913aa4f665ba89271e29a21d631ec0dea65ea39ebcaab7e4f716116b0ac2413a8feb042814c5a7f4cf2d9779d99fd7e06931bacb4b778	\\xfa14b50af629c3915f5c3982447f5b97fedc33661e291bbdea5f80d8e1bd120dc8f01caa29dcacb60b3fd15a1bc08d075c826179916aa8fd0a5002060b9d9d03	\\x0000000100000001673b2fa394cc81e5f5ed1744bb19ac52c0c9b167f36b9fc6efbfd5d570101960390a66c794528845ec2480c5fbe0fa9416c6b0caa5943c7587e1484b46f9ed3754a802f22e38a71695ed47464cbbb4f0ff0531d9002bead1999ee9d125ed475e42bd24a185517811166c2265bf2c87e561ceac7cf6505647b4f6193ca495f5ca	\\x0000000100010000
41	4	4	\\x5f031212d7303524497d4e53c8b5ec888d7984c180260946750042819040e673a4926646b64635f90f92d479dafb5e48f82795b456719e66850bc37fc75c2c0f	23	\\x0000000100000100b205e933e92168a2ab6b3472a4edbdee3d17be9f0d2fbf7c787db536da3deb0f678c09c1e814133db1e419eb6c159de8b9e90de022d0ea972889dd335cc685f5a5bb7a44c5754fa5ef211f3cbcd9be13355e14a4c59e5bb00128d03c7d5567ae0ef33cf31173b34aba0835ede16f025b2370e28d0eb5b4e8f62eed40b8e2fd72	\\x665eff01371fdcc9b43f40c89098a4a24644a42344d052cb0b6df4a9175b8721a64ef510a0e7f4f1671b93015c794d31a2153e0d0d19f2736600259609e81463	\\x0000000100000001cc118dd9ce888c3874d8f21c56c29996258672c1f02670f839571722208acefa4f18b4c1495047b95103e44064506fea84b01b7ce70980917524726f1c0a8a2541a874cc95a6780d6d0254d75e1e77710d4b1f7f6710efdcf041172d797e657682abed4492ace9d56f45e1b150e3a8f25e88e087e1b2254014c0e467f5e66af7	\\x0000000100010000
42	4	5	\\x91d21a9151b1163778945d24ce4f9440565763ec878fa23339ad39009f62f2a62e73670e3b5fb2ba138c3cec3064fde7e34fbed4d8f9296c9123c2e3cca13903	23	\\x00000001000001006bffcf2d4a4a42524b01752fd90163c07ed24f229a28c1d766e30c2e3b94a78872c43a556db24fb6a70fd64cbaf5358341c03bbc7f1080f964cee05f81987db6e9054dda3cb282ffd4df9fe66024f3474058bdaa47aabeeb1362cc54f27f60a1c1c865c4c5a8ef505f460f18d0613b1ef4113282927101b92b38f11b6c8d54d4	\\xbcbd29c3179047590683d9c71dece2b14a2739243100355cdcfa1d78ad613352e55c11e246e97b859c52e2c12b8b14c7e6aebc5d4b636dfa3e872d0bffd00ff7	\\x0000000100000001c30ac7f960ff0aaaf164587f62701dae6485d9f915517a0558a693f77d91004fdf8d9f0f1aeac8185d1f88e5fe6d3e3155de6ec91a67d3ebd428108948ef9b201982836235c9cb73dce66bae35b5fea94fadb66eff82f6c8cf84ac7dcd2eda94516dcb6dff0066b9aaa425481484d079ae563cb5e007bdc68c16f2537514c01a	\\x0000000100010000
43	4	6	\\x9ff87b6750252bba2a6f7662b7dd84098f5b088292f4265fe54c4c8aa3cfe33f15ed8e59ee5d9daa629b9945ed6df346e2cb1e7bfff59474724f5a4c54877c02	23	\\x0000000100000100cd12c4df602f03992617e6dde4ebb28713dc134bdddebae87909ec8d8389a6a102f64d42f223b68ba8d969a05efac76896b7345f90ecd9ea4aa9fc79b1da2e12519472c8ddb0f53ecc0f98d4048949ec488896c2098360f59a757f77ade7e54779e37a50e408cf299d6ceb37219ad6ee3752bacfafcbaebdc2132f143b28d32e	\\x3b0d0db34197fe5939f6b59f3bc6193f9724c20556e41ca1820e742769c12cef75f8437d6fe36bacb9eb594e4bc8bad1958c0c1e90097d97d4bfb9a55c36fb01	\\x000000010000000118361fd4849d483f296a660966434a63c83e874dfc5a3cf2952f57ad25e2d7e6fc274886b815efb5ea13d4050881e9b098712b1e8d58b02b77bd2d2ac67ab3e67421a52b60c3c0cf077e5020db0c2271158b91b7466c81a37c3507d25d41b609bb03a6b0c10ceb7426892389f841d9390e23f51cae63873a848a434f7f97132f	\\x0000000100010000
44	4	7	\\xe752a54da94f3a4748c83f0ad64c2910bba0617e4e29e4341384de51a3e5fc40e1eb0593bb0d576f73e02dc63d98293e942d75b47b46fead4553d3fa79fb6f09	23	\\x0000000100000100630a7dbf7fdb755c1a464554343adda23b84590040f762ce3190a41e617e18cb2cfb8cd7c8800249b6465caed403173c4e710e90bd496cce280c3f17ce1e1c6def2e4b27b4ab7cc559c3c796f35f35fda497aa0c883e63bb8cf04db48deb623f6a2ee3c2326ce731dd5d40e21a452dc274489b9b755b4f6a151ef34ded3dd640	\\x65cb6781baa34c6b93fe72feac0ed4699189aeffe36c5953c1d1216f92ff31fc7e41750c36fe25c903402a6658cd05c154f0e7b515d9ff4c6a595ad84268e31f	\\x00000001000000015f01121c39f1f47e14c69f5faf7e8da2c02d76bf24b6e49e9bc9aa89601c670f81277ad5bcd89070b7973c0e14b038ac65e0fd28b5070a75b6be70811cb03d2e025a466060b26fe77c82870a81eb29b464257a5fcb8b8b502d30582f96ad380d52978058670b463b1eceaa36afe2423c99d0cb8b7f6fe4e3aa8530aaf282a1ab	\\x0000000100010000
45	4	8	\\x2aca62b6894811538b33fa0bc7247e299524fd59b981cd6bfc596e5c30146d9a2cf85f8acb304820a05ec9581c66bc8bb5d1d5662b407ad9f617132075629a06	23	\\x0000000100000100c3a59a0b7a27f762b4ad9088161ded2483c686f986bd4c9966574dc98ba39b2950fa1a2294a2b63b68ba0bcead4e4ecaaa107fe39de92dc0597ec87f334da90cca95c82e6df749364e75efe3d73bb50e0abe80993bbc474385da4914a5c6fefe17cc2f4778718bf437b8f102e4ea5f0091ef40d635bb0fd562fa69340f46a87a	\\x8544f58d254fa277763c886169e69fca12967b3280856a25bcdbed4ba3e481cbedbfba0cf14d21a690f810d3bc53bc4d3607b543ddd337ee10ecc8c47c38033f	\\x000000010000000136569673857b30d66aa91ad3d13c30ebb3f3fbb8ca862a8d43d642c670d22fd5f40a9254d462c68fd6f2a04b328c7c525530fec42baa7ee68e099ec97cf74163a49ca8c580e47946f76504d6b9899404bd8fd2a48178d6933dc66b51dfff69d48e51c30bfb282d0516c3f841db9c26c590468a0cbb729dd478ace4fb9ad01d97	\\x0000000100010000
46	4	9	\\xf330a1102e9b8b849ac712c78cba9f5d63029d3d26853283ac1d46a37fe67158ebf2522fda0e8c358d46d7945fd998f86763e9afc0e5a2766faf8455cecc5100	327	\\x000000010000010098ec7888c672d2a1c99fa912024dcc0a2ecc635f11d010aefe382a268a9cf270a8f552897189c61a72a185f95b741f70f403c3d4d1e5d0856eb66691b60ac312e0bf09cb70252521427f2827b47f5eda726c13cb8ba0cb1296c2d6ff0be15c06e9aba913c602c8fb6d5b5bed2c095aeace54923fdaf89f0bc118b5881fbc40d3	\\x432f25384c2be197cd9ebc9511a84b7b5e7b955c1d8b110cc110b2d2f7964ded1c122bcadce94459a9273d1d686d271b1f4f120f15f3829027f12f0c2710f04c	\\x00000001000000019960d98e516e356353ddc4ac4bebdbdb547299315378074d4ccefe377fab71ce887abb0f5ff2199ddec0b682b33699a5a4e67ea559d3c26685b9432360d3bcbf5ffe0a8d8f27955a91d292e8796caaa1ea4a210580d0581152d94671d2bec1d56a02d41863fc598f349f52d04cd08dc36d15d2228e8a13fdfda80652f1c860b7	\\x0000000100010000
47	4	10	\\x6c38efacfd1ca0ccebe6dbe077600f563856737537a4c0891168b466d7bd8bc87659268ca827287ed5acd0105bb635c7f020fcb149b6d3b64b22efb0774dd504	327	\\x00000001000001008cadd49f083e7ef0b327fa2b6a4547fc91bde002f5a895336c2d82544cdf61986f42572575c2f301ccdeb40f6a83c02bb10eacd7c9a5bbbbd47abfc3a7bf741299324bd7aece6f0a420a649aef690c18fcfbe97e6654cf1bc4e45f9bb6ce4978b4e2badb37a4bf214727c7ce33119ac3b10fc0349269128c7f0771c59d2e3353	\\x02ffc232f1f87a0e50f177916520f03924d3fa7e9400c652c8326f9edf73a3383c0497d7aecd635233d9a02c842f127b6e9585e5ee0e778c509e7bc16a4b12e7	\\x00000001000000015402f5d470faac4267d9e00a45e13b64c0ea36bde63bc192ae5389f8f8f766ea895c61c016a5bc588e087b079e03a16ad92661ade21936f1a5893ae994d517f86dfaa00c8d75ebed6480cc1f4243f4cc7be2678d840d7bf08e6e349ff95de6caab48af57e8da80857fd10d80e198459a52c83e0b1e1bf4cf6280be2271696e84	\\x0000000100010000
48	4	11	\\xcfe9ab7a7281c01d97327a1c730598b76bb6dd77bc2ff6b280d83a0e1f7c52f05ffbc4aca60796a9632c8c077c4604505a49db5f659a512ebe42a0e89cb1170d	327	\\x00000001000001000baf0ff43bbc85e4c902f7b78e31d4b9395394d80e7a8f671c20a2411a75bcdb5c4e1b5ffef455ba7059045834733dfaab5f5edafce7acf2dda483403a8cb946997dd70c3cfd5b928fccc82439de9d3e2bb05f7065f837724c79d537af863f2e1de9f2c132b68e42903aaf9a26eaac993b0937a5b68b7c09c47ec3b0d4029312	\\xc3d8059f9a4a5f7796bc3e619e1b55d54a88e0c3136af4ccb5bc073c0b649fbbb586175546902d4b7136c670b40b0a70ff0485a5395158c937fe147f1dc76279	\\x0000000100000001176e711606ac85ea3d41d313cfd25c49ea830189375f5e571f64454c36e1021e52d0076598052bac2d22b5e3677c2eca7f48959268ee51110d60bb72faa4c719cd3ba99d89b3832e7d138831a410a6d7f6c6673be7301bccb48c1c1eede509a875291354e0062114eddd3f0b33425160936d9b75361b784286bd54978f3590e1	\\x0000000100010000
\.


--
-- Data for Name: refresh_transfer_keys_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.refresh_transfer_keys_default (rtc_serial, melt_serial_id, transfer_pub, transfer_privs) FROM stdin;
1	1	\\x466a20a0bcd1d0cb0eaa52652d4e14e9782823698e88fd30fbae7be5421c191e	\\x7ab7958abb1b1238cfd0b02f9fb7cc2a6a716072d413284fb9ce8ab999a47d833b7a3eadda8648636daf0237f29659d51d13019af6ba4953debd27c8767e3ae5
2	2	\\x03292b8e52947baccc23ed961f1b3bde570f3effcb07f877304a99c5ab13eb71	\\x127094b0f3aa960dec3b0a04b39b41789467be1b91de7db974fe64f04a6d73ef8f8fae4c2389bfd17fd699a8d6494c0b2a7d456449a957e33fba820aa3241fbd
3	3	\\xa3b17a9e70a933b22814e749e1e08f0cd65f9ef7aa4eb7f0532ee83ba746d779	\\x84a6ea1be72ee7841c25d8e4c11ed7906f068e55ac1468b17f98eac9248f143f6f24859fa156f69cc3ec25d64ddcb70445113bddc63ef3258fbb7ee0902e5b1d
4	4	\\x8e8a4900e7136d19e539c136703c168fa7a4fe846848f3bbb40b18c0e5ab416b	\\xe4974afbb58ef5d066f3faa9ce45855b9de9b880f5b6e71609df7c426c4db610f31258860261e5acdf4ca99a712e1291ffe681927af77a3a44f8ea7d944893e9
\.


--
-- Data for Name: refunds_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.refunds_default (refund_serial_id, coin_pub, deposit_serial_id, merchant_sig, rtransaction_id, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\x4e35a55b7764fb8f7f612e274a53d196543db4c5faf347dd6994502cfe098caf	2	\\x4b831ac904367a32446796c8b91e28181b56481ab9dd04d8ab46204944f2c21c47e93ec40f2e8e6f6b7eedf9980c3d8179ad63b44b48cc35ddb0131ab06e9d0d	1	6	0
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
1	\\xf94b96513c71c2d7190b281a65c13fdfc5ec641da4da82aef2869265da5623f7	0	1000000	0	0	120	1662931541000000	1881264342000000
3	\\x521e8d21902c153f08db4e4b97ecf6b311c339248d709bc7a365edeb3ee8d1c3	0	1000000	0	0	120	1662931547000000	1881264349000000
\.


--
-- Data for Name: reserves_in_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.reserves_in_default (reserve_in_serial_id, reserve_pub, wire_reference, credit_val, credit_frac, wire_source_h_payto, exchange_account_section, execution_date) FROM stdin;
1	\\xf94b96513c71c2d7190b281a65c13fdfc5ec641da4da82aef2869265da5623f7	1	10	0	\\xab0e7afd005033e8716c0cb3001b4bfd9e4ebef886ab66d25a8bff9065a01cc8	exchange-account-1	1660512341000000
3	\\x521e8d21902c153f08db4e4b97ecf6b311c339248d709bc7a365edeb3ee8d1c3	2	18	0	\\x18f6a81deaadc4f7420e1c6d0a7656e418bf1ea75c52c591e2516fa9148deac3	exchange-account-1	1660512347000000
\.


--
-- Data for Name: reserves_out_by_reserve_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.reserves_out_by_reserve_default (reserve_uuid, h_blind_ev) FROM stdin;
1	\\x86d756756848fab43b4fd6290e44a7a5575562712ce89ecfae992314f6c151c713b360aff9b94340caa4289106e9f45649c5e238e71d6ba942689517181d66f9
1	\\x8e7b90b9de08d733bc2053c124b30d7b86ecdaede4e99dafad87a433a65c5c2ddef2c15c1cc03309334ec5df18dd7bbc106c1b706bd44c64d3276bf96339a706
1	\\x4b0570c555c23bbc45f66246eccf5e89e82824f80ca5243ea7d82fc75350ecbbb4d45dada0fc3d0d7c87e926f34303ced4d3ade1504f1552e236cba8aaa52711
1	\\xb7e673244555c6da27df22badca2d7fda323ded834662b1b291a487aa6fa8dcfaa8a9c7bf220e16ec18bd06ada547dc5ac64c98debbb72c1c7e42738a1f5351c
1	\\xb6176074ab76fecf18baaf578dbe0ecb5f07f8ace5d3a88c514e1ab41d0d0be53ec8b6dd157d3343c30b0bbb5d17f4444ddcbe86d0e1f432a731b41b08a07a84
1	\\x22f92b517d220381fb5d4a83ebde5be3ed9fa41a0fdb7ec220134291accd14fba6c47e495d69795890ddee319daa382546ffd2b1e95c06a9ac0c0b516980d53b
1	\\x12bfc1c25b8b2d78d8ecc7480909194cacf60fc203c2a6e27318e0f5c3e3ee575ba8fd936b7cce5fc89d9fd30587191630fda3681ff856ad97fd15cb0869c5e5
1	\\xbba47cc0322034e97f65d0bc51cec74debf11c282dd80cd49c1c8c054aab4190e21f4024d6cc456465c705824b2c98883ac0e87b0246f8dff853554df8928d1c
1	\\x7915fe42f9309be089711f5211c372d585b0a2a35f22056d46f7fb5b575b98b65a767be8fd2c71d5b9691198bb7dc0cd546037d5ecd38a26794706573534bcb4
1	\\x8fd7baaaf777c50340a3e766fedee17e3f1cd8e3e6846745ad0ae31b18de40e37c0c7c19124c0d069d5253da995c3b9950d1a19a347ec24e8908c9a48748a269
1	\\xeb370330979769f9a081db9e3ec02aedb6c7482810d11e3d2625bde86e60eb8b254b6c7527adc4805845d0b9cbcb092a082954cd03a941a8bbab69bc7e7ab80f
1	\\x08de67acdc7f1cf3675a1bd300bbeaa0a83fc0fab1de948d3f4f02847b0e9579f10ef8d7ea955b9c5dda62fd559f3c775e824f0bc48522c269398189f8bd7b3d
3	\\xcace29d3c4c63a9815b74de490f88ffe94672af13b213e9165a6f7ee2a2888cc8e9358e8ea5d85d67fb5f2042eaa64fed54c608949fa8d8815ab77c65564009d
3	\\xec7f07464507ed08c48f17dcf8d09e7bbc866997959dec111d1c89b5302c2cd622a481fe59f938355f1bf7b2025e42963d4ea8e1d7db2dd1ae22e3487eb02435
3	\\xfb5e11fc8667e0b8bc54c71b805e2e8b04a80b16c094d20e33f6ec0d9fc2b243163cdc330c6f3efd7b9b685a5ae8e812e2d9d27740cf42f1b0a5cc4bfbf2b6b7
3	\\xecfe7ea6ed1e2ed9464e61cb12a59c76e3a04e19316b21b9db4e5153a749b57f7c9dd35576b11f2bb6c40296fe953ba2213aa595d069a6257d068bb9d46119fc
3	\\xc364643309ee156b6a3cef1b170346cfc80aeae85e05c7a7aeb91d4d2abe1df24f3b10d19b9f2c4f96949e3e6eb65fc26df5bb529b7c2579c5f6975f3887947c
3	\\xcfa00f1932de452bb35ae99cd66dd1a85e4a85e4aba6b7029119a26a4c464cd0552e5c8761eb9b96b359a21fa9c3f22948f9a3c06ee7d6c78822579b4d9044b3
3	\\xc042cf17e06bc4afdf30f2f29b2bcdfe0f5d7fbfe1a61bfcad88db31e445b610599de46ab36ea5426a5e5199e13d3af5b9440df36af4f258f8b6e04ada100512
3	\\xc4ba462fefaf1fbe1ca037a47f94cc9787cb453933a7834c80d998b104f4a13f57f36f7920235efadd1fa51bcb0cc863420505f1275aa3b39920f87451cb1af0
3	\\x9d51e0b46fdfb1f8ad70785f4d4583a09f179707a2b88f8a127cc4bd511b2674fde08a3779f754188f861023cf446bbdd02136612141b49fc40489c5b5029519
3	\\x6d219a7dda396ab98cd9d15272f8347e8337a6d4ee8cadf4f917b91e21e627c9258377216efd06242f0000198ac8fe147d853bb8eaef8d890ccf7cd5d3139705
3	\\xf0a15b2de150097e16a99a40fd8a12be47c022fa9b413d877fc16126cb1527a1f3c61aa1b0ce90b8c68e978edbc44546d30749625799e475cb3f4386c4dff15f
3	\\x57da8820e2f8e844e68192e66712732810a8700938a13f0fd8b430ac6476191ffc66b26aa69a61a25e43b140cb660117859843555f0df9bbe3223298e8fe7eeb
3	\\x0b5c31f4c34120059fc60716b226bbb4d9c8fc4c20c2badc61ef9bcaed45f631296cc4efacb9036e1fd87dba0641b33d7a54bcb3011d90934282bff2924ca6d4
3	\\x8471fa813ec66b5be5e2327294642827af91c423c7feb43abad7595051162c78c9cd950a38d466233876b3c866d650df7bbcb25a9ce73e495e6c333ab170af9e
\.


--
-- Data for Name: reserves_out_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.reserves_out_default (reserve_out_serial_id, h_blind_ev, denominations_serial, denom_sig, reserve_uuid, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\x86d756756848fab43b4fd6290e44a7a5575562712ce89ecfae992314f6c151c713b360aff9b94340caa4289106e9f45649c5e238e71d6ba942689517181d66f9	315	\\x000000010000000180dc2e685837a9b0f6d1bc6748c3d1904b90bb23ca8d8ec4345ff9f481d9baa792b8c9b6e88c856b00e089c3d46fe242c4be712222eff0b6b0c0d1f2d3e8c4a5157cb45c684663dcf25c109c989ee71fd31bc70cebce9ec5cb59ef6980eaad0a2ce387b374c33f205cebd9c21d92c6c69227515814f77d4a9de2707ef80a7446	1	\\xe5701e8876a0f6ece1f64d023a91c639108847e40a55f3ced2fdc9940cc976a58551b2d83ec14183711634d2eed3618fd914f15339ea2ea81f47a6eebdb9320e	1660512342000000	8	5000000
2	\\x8e7b90b9de08d733bc2053c124b30d7b86ecdaede4e99dafad87a433a65c5c2ddef2c15c1cc03309334ec5df18dd7bbc106c1b706bd44c64d3276bf96339a706	57	\\x00000001000000013848318bf396fe0279ef233a7737998d6d2d643fa3f4c647890f7671ef169c5edf8c00c4cf3400225708576622280da199fb3d1f0f2f47dd82cf80ad102ac1ab1df84a4d4f653415e35a478483f38f16177d4b4a7ea2da6b18d4fb1a8d4b1884114064191d4e459bcc5b1430e88ee56bf5bf4a1a847aac5d7cf6778f6509c073	1	\\x9dd71dd74ae2e40f24101c27a1792f23fb88fc2e41318721994bc236d1dfba6c4345f0696cbf919ff029e850b16e48cd2993a331c063afac20b796f56d0e7401	1660512342000000	1	2000000
3	\\x4b0570c555c23bbc45f66246eccf5e89e82824f80ca5243ea7d82fc75350ecbbb4d45dada0fc3d0d7c87e926f34303ced4d3ade1504f1552e236cba8aaa52711	23	\\x00000001000000017856477d3da21ba2471f40a4504996100a338ba2788845ec98ed79c32f85c1c2927da86b8059c6ea0f4acaadac7c563df4e52945e7aa064904e6634872fa1aee480ac082501efe010f1844058a1c072eeb6502708d8f07f51f8880f862b65ba937e41efbb97563c52d8304c543f685c1c569afd06cbb563b7e5ab09e50721f2a	1	\\xe800777b65e7b5734da847730d38af2b469949569776fa189b9497feeee48009e3d6f921bbdd06fd8ed71178ed49ed2eb2de12241573c4bd37a1db6ee9079b01	1660512342000000	0	11000000
4	\\xb7e673244555c6da27df22badca2d7fda323ded834662b1b291a487aa6fa8dcfaa8a9c7bf220e16ec18bd06ada547dc5ac64c98debbb72c1c7e42738a1f5351c	23	\\x0000000100000001606eaacc190c263161e3e98b3493386d39d1f3b5d51205c453f84e57bc1368470ad3a8b37d49ff009bb98e02f23ae47b0bd715fb77ab0ba50cf3828758c6b690037f0e0c0f7f30ff8d9f056f5d69b060c282e27df466ae3ec1bbfe4dc90d3717327785b90d47a975d292113819728c6074cc2a6cf9726ec86b51ecf12c719005	1	\\x281ca9eb97de16c9d4876ad5fb1828e23726a327d20c7eafac392f2c6b4c3dcbd3544206064c5d94eb6102cfee8180aec986975897dc33124a4c3b39a78cbf09	1660512342000000	0	11000000
5	\\xb6176074ab76fecf18baaf578dbe0ecb5f07f8ace5d3a88c514e1ab41d0d0be53ec8b6dd157d3343c30b0bbb5d17f4444ddcbe86d0e1f432a731b41b08a07a84	23	\\x000000010000000182230edcabbfb229a91b050b7c8f083566c87aea32de0766f293c0f25e5261b32b0ca45b1a2a71c718207c895493b09e1874bd20b621d7030b75222f31bf87a28e8af93722e1e3ee8a3e4f42a29087fecf8ca715daa553e13d2220a0136b7332661d6640b8bf0318de47bea6ecbd7c807219e13bcebf32489ef0335f622b363f	1	\\x46d998c62f379e9309c9ead2ebf571a8d3e7e5d0d23a15d0ef82945c96cdab2f42b60a1153c8160bbba53aad8640c0a21dd9305fd6fc27807a562e75248f7109	1660512342000000	0	11000000
6	\\x22f92b517d220381fb5d4a83ebde5be3ed9fa41a0fdb7ec220134291accd14fba6c47e495d69795890ddee319daa382546ffd2b1e95c06a9ac0c0b516980d53b	23	\\x00000001000000013a8de305462336f8e440c54b11a48e13d71ceac102893cac9e81076bb76e4519785959a334a97f21139245aeab205e4f892214d4f8dbd463c2f3c4eab54407344d5365a904f340385b926e7fe83aa725ff1610b43ef7a1d31cb254560b9a306f5c18a77c7be4afc7002dc66e3020aa2985297fcb8cccb4fabf4a90175ef8e988	1	\\xd4834f13cfa268ee7affa3dfcb8a50d281dceeeb01a438b51d91510143a64d4c927cc148d33b2c1afae9810a961f24bc3505d5f5f0bd3577bee8155e1ae6e707	1660512342000000	0	11000000
7	\\x12bfc1c25b8b2d78d8ecc7480909194cacf60fc203c2a6e27318e0f5c3e3ee575ba8fd936b7cce5fc89d9fd30587191630fda3681ff856ad97fd15cb0869c5e5	23	\\x0000000100000001d28a42ddeecde57f5efcf875b80f384138ce5f391aed19c7362c1b66f01cc2bdcdfe495a9da10c102c7d91a763adf9f8fcca4e894743f36dfed0604291a1b11679e9e934d0aacedd688141e927afc13b1d3edf86ea60280a5faf64e71bf7184bf7194d5bafcdf4882699587acadb922283ff11e78a4d18f48daa5e9104e93333	1	\\xd5dba470f8d98647cb4bf44f01f3fdf3e35a3b0979256e3a418d3b5e96bdcd2924d25e99df9c357b315db29b2e6a8ca6e72a81f59a9190516f480fcfb7cd2a0c	1660512342000000	0	11000000
8	\\xbba47cc0322034e97f65d0bc51cec74debf11c282dd80cd49c1c8c054aab4190e21f4024d6cc456465c705824b2c98883ac0e87b0246f8dff853554df8928d1c	23	\\x0000000100000001955e81c35e021b3265e6a02718a2bc5ea2ca0a0b413be84b3ffb36d4b5c4ee0fb8a966ac4cfb56a8053697791bf2991c2c282b7b24e762f64beab2d4aa6f345c10f3603e54cb78fc350af9fcfd1b2e40346b57c2478c542836efccaf078e7b2f74011dacf35ab1e352853b43b754c7e810c4f93c8e522d1702958fae4dbabea0	1	\\x52a4c6e46bdf7a6740a28a74a0a767b9ffd6eff3902fe888b99409d06ed1e5b8311a80911b2ca1468231bebb8fc0c318bd3a24d2c195907a2cfc031ca0588604	1660512342000000	0	11000000
9	\\x7915fe42f9309be089711f5211c372d585b0a2a35f22056d46f7fb5b575b98b65a767be8fd2c71d5b9691198bb7dc0cd546037d5ecd38a26794706573534bcb4	23	\\x00000001000000017f8fc3b546d4f3d927f2e3954ac697597b7f62c58a501fe7ef9f9ec2fb90769304bfea894c1810b2bb4d484b97a83b0f68a684ac520878a9e11bae8e79a550455a466d7523dffe96dac28b632f8edc8f16d71b7ea632cf5f7e34d74d28f3c579f0cfbd270b4c0feffafd30ae50dd31f0323ff8e6181f1d39d052ebac9423b96c	1	\\x35d048971c97bcddceda78e0894ffd3dc9f11049593c7c84232e1829b301a49ca79b0537b642301cbe9b62a8fe0bd77b46c74c4fa5fff33b795df51d8a3ba406	1660512342000000	0	11000000
10	\\x8fd7baaaf777c50340a3e766fedee17e3f1cd8e3e6846745ad0ae31b18de40e37c0c7c19124c0d069d5253da995c3b9950d1a19a347ec24e8908c9a48748a269	23	\\x0000000100000001b2e39e351532b45856e4062b506f4988ba6102f65de712df76d063cff35fcc6d29c263aef012202768379a69db24e50132f50dcb98befbeba625d16462fd9c683133469757cc2da6cef225fd64cc4902aa131622c719d3c57bf269f99717775c52e087a14fd8c85a9cbe711868ab3a4f13cfa4a9ec90e2fb672e8b874bbb53ff	1	\\xf092c4caa834fde4cb72ed9da4f8f0c5493fe7d383b8a4398e7048575234efa5e0d9236f429bd949bd183c31ed0026d0d90aa9136f325c944e2fbbaa4de3090b	1660512342000000	0	11000000
11	\\xeb370330979769f9a081db9e3ec02aedb6c7482810d11e3d2625bde86e60eb8b254b6c7527adc4805845d0b9cbcb092a082954cd03a941a8bbab69bc7e7ab80f	327	\\x00000001000000018d1aa1a1f6ab9373640aa7d513bf17574004e991907bda408d3c4685979f3ae3a9aa9d960e294d87a2432139f6c9507719963ecca957bb8833c4777502635082aea6a19c2a53b9ab661c7533564bd7c591ad96073a5661e2ac8a6b2ff055021aa79b887b3a837dc4af636445f8cbdaffd520bfe6802e693138d1ebda00ff5d60	1	\\x4f7d102c2497c7a8478b8693d434e0a2596512e9e9ccffb1767ce6f1f563b1ab5568afec8f1b25309bc74cae41d95c7a5e11ae6533df3a12748829024c3dcb04	1660512342000000	0	2000000
12	\\x08de67acdc7f1cf3675a1bd300bbeaa0a83fc0fab1de948d3f4f02847b0e9579f10ef8d7ea955b9c5dda62fd559f3c775e824f0bc48522c269398189f8bd7b3d	327	\\x000000010000000134e97f423a6138d15ddcd045218608d792f3f9d55da9134ec83a461c8614d8fc102f61cb3300be906af727cdb8456a3593d27a4fc6e03caa5c0de4f16acaece57b05f98a83f8e9bb17373ab2b62775854cfcaef865b3472207f3e2e1c1677cec77524ff9f0f2ce2001605cb316a456a9a83f3625bfcf3c8fd1e2ebabb5a4063e	1	\\xa04fc66dfbd2b8c6713a7b5e496ce389d7fb08a032525fbc32e944cfa31f2426c3a8eb788639fa8e6d099c3d63b04b4b524ce4bf00e0b2ee2af9c23fde0c980c	1660512342000000	0	2000000
13	\\xcace29d3c4c63a9815b74de490f88ffe94672af13b213e9165a6f7ee2a2888cc8e9358e8ea5d85d67fb5f2042eaa64fed54c608949fa8d8815ab77c65564009d	252	\\x00000001000000018a15e907cbdc4ad8059b533578a16e7df33d9ac7260726304c0f56bddcc758d9f1035f984731b423b061216805c3196cb809e58d8f15c349335784efee4c81556937ae6b75f33e34c67343d8e28d3fb63547d9c86b8dae3c27826d71b02f6af6c5018f675ce6e5ae23c0abd99e65ce1c730906ba4c9fd8d9a1508febc8d17450	3	\\x8cac99255654bdf039d49f22778fe7e89e66ff652cb083df4c8827979ca3215dcc7280be97b05def75ff00705606a42344be1ef8fb1e529fa02777375cd54804	1660512349000000	10	1000000
14	\\xec7f07464507ed08c48f17dcf8d09e7bbc866997959dec111d1c89b5302c2cd622a481fe59f938355f1bf7b2025e42963d4ea8e1d7db2dd1ae22e3487eb02435	406	\\x00000001000000014a32aeede917fb837a8ebc415497e0aaf44bd6901f467be222a91f78b16cb728465e024ea2c432d857e13651668e7eb95bf0b9b8693f653a4bad3ebb9dd22e41b3238fd12a2ae17e1b39a6930b1434b5030f9eee7c47dba1edc1f0f66ee56fcde43658aeb6607a046e7f2a6cf2cf3eeef25fe6a22eea5aa53f586dffcda4cc90	3	\\x7d6cd9696b3d84d09cdf6b351dc21f3b3c30f0a9f1034b0ab19975802d10900c73cb0d80505db77c041d0eb12345a0a666d429ea9018fe627befae2ce8677a07	1660512349000000	5	1000000
15	\\xfb5e11fc8667e0b8bc54c71b805e2e8b04a80b16c094d20e33f6ec0d9fc2b243163cdc330c6f3efd7b9b685a5ae8e812e2d9d27740cf42f1b0a5cc4bfbf2b6b7	130	\\x00000001000000016b100aa4d011fcaee2ab2a01e36012e308e41c6c42171bd502276d03dfe3d6e3951adda34fdc6ca16d46fd0ce0be31a4614bebbbdeb677f92bda54f214617dd575a2fb544d5f0a2ff5f252d08a266da41efdc14c305c98fa827d39daf5dd1fa17a0ad9a89d3d49cbf90eb57c2163bf1afab4916f08f0ae3f1eb2b7da6bb8b84c	3	\\x852c4ac5f7595b7e84e046ba9b62e66a54b6525f4849ff2f6233e5ecb0098717ba76cd04369e602c9f9ad6ff7e48d067b9f8f61a3b0606ee360a8b6cec63750c	1660512349000000	2	3000000
16	\\xecfe7ea6ed1e2ed9464e61cb12a59c76e3a04e19316b21b9db4e5153a749b57f7c9dd35576b11f2bb6c40296fe953ba2213aa595d069a6257d068bb9d46119fc	23	\\x0000000100000001c3a0498897b853f8033dcb1824549895fea84db26b5f2fa9a38aafcacfa53eb8310f12ec432cf87a81a8efaffbfe329fbb86e9d134ec1fba3b684e45ae04c338675cd7eb0e7867ce36f19aa36c733b04c84c823506b72698d9ebd6786b5a045aad652117f515c97b565e01adebd6606c2e870d7cf15c6399899aee9311d3f9ff	3	\\x1140088b9b170c42146e84a50a03ad65e8b1e59d75571e4a02b869078a39cfb01b8e291517b2916a56eb474e3f98e6246f5d626ab3ede9b36a96e15437fab108	1660512349000000	0	11000000
17	\\xc364643309ee156b6a3cef1b170346cfc80aeae85e05c7a7aeb91d4d2abe1df24f3b10d19b9f2c4f96949e3e6eb65fc26df5bb529b7c2579c5f6975f3887947c	23	\\x00000001000000017114728f9f7a85e7d1fe73e84ceffe1e2e44d2d6b7ceb425cc22a0f202e94f24df1330f033529f0575920657fbc6d6370241fa1d62e63d8f366084c83d9815d112d96072fdf4c27297ff1b39cf5be431bdec7a059c70fe3ccda3843fe4c5fb8682f3b9b6edab0624f3b721186e77d84ae7a7825498e1e7a6a3145e95fdbd977f	3	\\x3cbce27c0040692c5fbde71a978b9c407107ed54f7e6c58329b2bd7af1557c5fddc52188277561d1aab95c0315abfdf5666984cae57edcc930f0b49568ff710e	1660512349000000	0	11000000
18	\\xcfa00f1932de452bb35ae99cd66dd1a85e4a85e4aba6b7029119a26a4c464cd0552e5c8761eb9b96b359a21fa9c3f22948f9a3c06ee7d6c78822579b4d9044b3	23	\\x0000000100000001af440e61d1501eaa9b89d5403f6fadb6c901bae0437d5bdcf0c0cfbf3d5101c64e1b82f96b59506495920784ea8a9647f7ad328ce83fdfe178e3888cd450b62b4ffde7aff4fa4e99b4b2821fb6403b6a352edd9b1cf302db4dc67d4d9dfebb1dc05598e76eccfbe5d996cc3b8fbe50674210364aec0f24ee87870cc37b154357	3	\\x7158f715fcc68c332a5db2759f323887d37c1f0ba339cfbb0d2017e2e5bc328bd34dba671feac315400b13f2f29e43b0640855cd6142da01cfc2b70799b43303	1660512349000000	0	11000000
19	\\xc042cf17e06bc4afdf30f2f29b2bcdfe0f5d7fbfe1a61bfcad88db31e445b610599de46ab36ea5426a5e5199e13d3af5b9440df36af4f258f8b6e04ada100512	23	\\x000000010000000133d4d7f9d14bd09cf5a83d515647deadc4b253ded4cb8402a8c64bf890d1a7e3a8ea58c51d2bb6a8cf513a5162a511ed40dfa8c8774859b665a98797b9983867095a911595fa3e5f5593873ce97997533e3ffadad92163c771aa28d419bd5d737e5858b4665396ff76c1c5a8d11491741da994f312db7e02b4df5f98aeee8bd9	3	\\x635d613c75bfcf50fd9c45a1658ef425576c3a7851278cce7a04decdb67d046d3743775aa021c01e1dc9a7666863964fb85230068f5e4698fcae5a1d22698a0f	1660512349000000	0	11000000
20	\\xc4ba462fefaf1fbe1ca037a47f94cc9787cb453933a7834c80d998b104f4a13f57f36f7920235efadd1fa51bcb0cc863420505f1275aa3b39920f87451cb1af0	23	\\x00000001000000010749b85204574cf908e6ca95e0f2c24331a500e3c0ecf0f40a885df6300d7e129fbcd9a3e748d1f4f14e2aee88e01f78b5b3eb621c7f5e6d75fea3aaf8c30ea97b7c7b900a2e5c47654b3163d4335951a85ee80fffa7dcb7f1013a24cbe1d4397314994cf24c14ea7b796a874abcca1ab914a7d915648f92db6cb7181d776586	3	\\x33ae59af88eb02a104b29b72770502ffde5f46c5288e7186a263ab3464db45e2e0fa1abdac7254fe7468388b5a4836bc889e317bbfa3d0102a7d662c24a40101	1660512349000000	0	11000000
21	\\x9d51e0b46fdfb1f8ad70785f4d4583a09f179707a2b88f8a127cc4bd511b2674fde08a3779f754188f861023cf446bbdd02136612141b49fc40489c5b5029519	23	\\x0000000100000001d6889feb5411cecec3ca260d3e2f14cffe3b585cf5c1b1fb002a1c16dd4640549ce7f02eebf7fb8b9f6535fb42ea8da0de65885739a7892f157004d0d3bb4bbd9da3348d8a3a8d788fcea7b1b36a2d99f2ef5612ec5e899aea55546e2be0df23696cf3afdde152d90f980028cba7ca5410c6518e69090335c34195b94beb53b6	3	\\xf50b801bbfacd097f4362bd5c3afb7be0cf05d82579d6abd1c12c7443057010434fc9efd586a90c06d28a8dec67ed3885f22ce17928a0e9bf1e7b79d16cb780e	1660512349000000	0	11000000
22	\\x6d219a7dda396ab98cd9d15272f8347e8337a6d4ee8cadf4f917b91e21e627c9258377216efd06242f0000198ac8fe147d853bb8eaef8d890ccf7cd5d3139705	23	\\x0000000100000001c26010d64dc99bf901d1c0bcdc0195689ce80dd5e7416bf15742e8b22acdb68069da9a85ff62647a73f3b337d963e073a6a4a4b2624b680ed98cf89423b04ab39ebf62308b1e069c9e9a1712bf80cb6b30f2e000a0b4c4c7c755ad348fa0b4b193c618bbe82721ea513436d3caed544b8fac2fdde8760be7b56528e4efc51d4b	3	\\xe251f8c74176bbf9a056db252567fae6c824498d35bea2385f24e6799ca2730aedf5de4a8419c5ee7b6aaf9a35c2c848184d568d1560f352250421fa9fc9630b	1660512349000000	0	11000000
23	\\xf0a15b2de150097e16a99a40fd8a12be47c022fa9b413d877fc16126cb1527a1f3c61aa1b0ce90b8c68e978edbc44546d30749625799e475cb3f4386c4dff15f	23	\\x0000000100000001214822543d53c4ca905d1a36f9fb34f9aecd789e63993598dd1c533ed5ebd9418b9f3d0199aff0984b88237117f13bc14e58db3eeed5fe1b0d02e046ae66506586948dcd97a5f73e8b593c843f2157ab2ca58ab4b189c112f55c25f2a421a1885e4a51fc6063801195dc027155afcd5e13c419f473dcf024332f2c15455a5aa0	3	\\x59147586d9683c506937052decd5514a0673d0a38fc6d5db6f521ea47e54ab2db69bd5349ca734ce2cadfd1ad7955ba00a4a83f04b1a6f0afeab92f8fd5eb90e	1660512349000000	0	11000000
24	\\x57da8820e2f8e844e68192e66712732810a8700938a13f0fd8b430ac6476191ffc66b26aa69a61a25e43b140cb660117859843555f0df9bbe3223298e8fe7eeb	327	\\x0000000100000001215d95f9e141646576d17381cfa9810e92ee87032d4dd8aef2316c52b16aa8e3197f85db14740487d8c2f187f1d677f45b32ba24c19468acc94b01a5750222e850e65d63153191b30eb5c28eafac9b38383e01e5bd9faec6db2d0de4dabcf1cfb2256065409ad70e14d9e6c44c17ad0b65a9e6450858be276cb1a6d28a0d4bad	3	\\xd99cd396ad351fbbd4ad59738dad5bf948587f7136f4458060bcb180ee6b0faa71c9df8593819e7e6d06a1f0cf6aef42bb13f1b0df1b7a683ea104899b9a430a	1660512349000000	0	2000000
25	\\x0b5c31f4c34120059fc60716b226bbb4d9c8fc4c20c2badc61ef9bcaed45f631296cc4efacb9036e1fd87dba0641b33d7a54bcb3011d90934282bff2924ca6d4	327	\\x00000001000000019773c19b7cb0c446b16069e6ad3efd6f26bb663c31fa73210fc8cf44b5c4f723232542306997ec65a8eb8abd49d81b3da9e34e5198a5b4b6ba64c32b9c138f7ad20b7daf422b5f26d9d7f58896c403a27baa25b09a25d791afac5701f001f2d3994f89f87d5b01865237d6d86fa1d7e6dbf933f3e06e3955e294076185d127ab	3	\\x51f0918ce99654b96169b20a5b84468df1d51ce86afecd5d7bdbbcaa9e927f489bf1e34995e6ce376a5924d7c59ae41c111bc589ca7acbfd77bba8c66971ef04	1660512349000000	0	2000000
26	\\x8471fa813ec66b5be5e2327294642827af91c423c7feb43abad7595051162c78c9cd950a38d466233876b3c866d650df7bbcb25a9ce73e495e6c333ab170af9e	327	\\x0000000100000001c864aa67f82a51e7cf2860e3f318ffe55dc74734da6382ffa23c638cee84d005bc7fa64d55ddaa29846bd0467ce062879d1e49b61044e09d036ad7998e1fb59bb6f87f8c4ef51e689722736f8ea38e09e4d1dec2fadc9c24b424fb4db872639cad739f8f929c40de669d259e432c923915a6ccdd8e2eb2381cb137adc0b6b979	3	\\xdfa93cadb45c2eb06c9c8a0363b382e1693b40bb6507d4e755b1c57e7428e71f88f74b03269654ec0b1c6d77c571f7e56a384a56d3a6af7550539decbe7cfa0b	1660512349000000	0	2000000
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
payto://iban/SANDBOXX/DE220640?receiver-name=Exchange+Company	\\x91f4aff5bc337861b826ca90bed0b3d7f202ebe858edbff79713076d955e7ee5195c190d56597ed88cc40e3e51b6e5b77956aeacaf5ba7e21183259786ccc50e	t	1660512333000000
\.


--
-- Data for Name: wire_fee; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.wire_fee (wire_fee_serial, wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, wad_fee_val, wad_fee_frac, master_sig) FROM stdin;
1	iban	1640995200000000	1672531200000000	0	7000000	0	1000000	0	1000000	\\xd2652c3385f3dc243586c91f6f2b36aef7460f6821bb42a528f6dbfae0a8cec0124d07e6c920404f813cdb2b6b9c0376cd4ae71c5d8ac1a457b079335aa50701
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
1	\\xab0e7afd005033e8716c0cb3001b4bfd9e4ebef886ab66d25a8bff9065a01cc8	payto://iban/SANDBOXX/DE885272?receiver-name=Name+unknown
2	\\xd31e3f48cb5318906dbbb7948326362f41604c7a728323230ae82aa995f27400	payto://iban/SANDBOXX/DE474361?receiver-name=Merchant43
4	\\x18f6a81deaadc4f7420e1c6d0a7656e418bf1ea75c52c591e2516fa9148deac3	payto://iban/SANDBOXX/DE531343?receiver-name=Name+unknown
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
1	1	\\xf47970a8b8271fa73af3ca50f28187ed10632f8fdfd96cfdc8beb9776e3aef07232a6533dc58e53bde4abbcf6f77741f510b2178cfb011abeb70d4898d5382bd	\\x9eee741ed059a5f6622bbbc1394a6a75	payto://iban/SANDBOXX/DE474361?receiver-name=Merchant43	t
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_contract_terms (order_serial, merchant_serial, order_id, contract_terms, h_contract_terms, creation_time, pay_deadline, refund_deadline, paid, wired, fulfillment_url, session_id, claim_token) FROM stdin;
1	1	2022.226-01RFDGXS6ZXY2	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f73223a313636303531333234327d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313636303531333234327d2c2270726f6475637473223a5b5d2c22685f77697265223a225948575131413552345746544545514b5339384635304337584d383636425746565a4350535a453851545751455648545857334a36414b35364645354853395656533542514b564645585431594d3842343557435a4330484e464e51314e3439484e3952354638222c22776972655f6d6574686f64223a226962616e222c226f726465725f6964223a22323032322e3232362d3031524644475853365a585932222c2274696d657374616d70223a7b22745f73223a313636303531323334327d2c227061795f646561646c696e65223a7b22745f73223a313636303531353934327d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2251574d56574e375157465659584241354b57325433374445485141344647483637465450454837373636584b4b355a4b34423047227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a223243334d5a4336463142584a544e39545343474837484d58314151503543594842424d33505a3431355159313437303631414b47222c226e6f6e6365223a22514b4433334745485135324e48513438384534503458545448323643345648544d4d3041475650485a533056335a354748523547227d	\\x1dc78c0db550fb6dd5f6584331beca9f12a6360a01bf320ba171764c323e3eb954165ac652eafa48f616b71d21091a3b5c37bbee194fe0a4ccc04c45cdd13d14	1660512342000000	1660515942000000	1660513242000000	t	f	taler://fulfillment-success/thx		\\xa19e82062d3adf1af63668b17d9dbd63
2	1	2022.226-01W4GBSV7PJ9E	\\x7b22616d6f756e74223a22544553544b55444f533a37222c2273756d6d617279223a226f7264657220746861742077696c6c20626520726566756e646564222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f73223a313636303531333234397d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313636303531333234397d2c2270726f6475637473223a5b5d2c22685f77697265223a225948575131413552345746544545514b5339384635304337584d383636425746565a4350535a453851545751455648545857334a36414b35364645354853395656533542514b564645585431594d3842343557435a4330484e464e51314e3439484e3952354638222c22776972655f6d6574686f64223a226962616e222c226f726465725f6964223a22323032322e3232362d303157344742535637504a3945222c2274696d657374616d70223a7b22745f73223a313636303531323334397d2c227061795f646561646c696e65223a7b22745f73223a313636303531353934397d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2251574d56574e375157465659584241354b57325433374445485141344647483637465450454837373636584b4b355a4b34423047227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a223243334d5a4336463142584a544e39545343474837484d58314151503543594842424d33505a3431355159313437303631414b47222c226e6f6e6365223a22534b4236353433585a4e32345031314d4b323253465251395a30324b44584d414a444d4e3131334a5837363132334e4159535947227d	\\xea76029b68f01208d37a9546ecb802330bbd2f754612cd6528a3cf97a6431802fddd7f52eb7455493fd0bc7de53af1ee195061b124887804652084e05fd0324a	1660512349000000	1660515949000000	1660513249000000	t	f	taler://fulfillment-success/thx		\\x4f52e909763847c877beec85ffda6067
3	1	2022.226-01R3HSTE72E76	\\x7b22616d6f756e74223a22544553544b55444f533a33222c2273756d6d617279223a227061796d656e7420616674657220726566756e64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f73223a313636303531333235357d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313636303531333235357d2c2270726f6475637473223a5b5d2c22685f77697265223a225948575131413552345746544545514b5339384635304337584d383636425746565a4350535a453851545751455648545857334a36414b35364645354853395656533542514b564645585431594d3842343557435a4330484e464e51314e3439484e3952354638222c22776972655f6d6574686f64223a226962616e222c226f726465725f6964223a22323032322e3232362d30315233485354453732453736222c2274696d657374616d70223a7b22745f73223a313636303531323335357d2c227061795f646561646c696e65223a7b22745f73223a313636303531353935357d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2251574d56574e375157465659584241354b57325433374445485141344647483637465450454837373636584b4b355a4b34423047227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a223243334d5a4336463142584a544e39545343474837484d58314151503543594842424d33505a3431355159313437303631414b47222c226e6f6e6365223a2238365a4554373031545445334b3932335a30584e4a594442345834504252564830355a384e363947584e544e593150544e4e5047227d	\\x7025824934f4bfdccb0766a8eb445f80afd82bc969eb775ba9a637b0f4767ebd5ebb7cc01fcab0cea3639759047856e14a5ba97d620b5da2d0b6ab3e8b0ebeaf	1660512355000000	1660515955000000	1660513255000000	t	f	taler://fulfillment-success/thx		\\xee8051ffa681bec0a40dc7fa28421479
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
1	1	1660512344000000	\\x2b1e50c6417270e052ecfe4cda4a7831c5cca061b59b9cccb0163d6f3ea46ea0	http://localhost:8081/	4	0	0	2000000	0	4000000	0	7000000	5	\\x06140e8bdf036034320d6db2ee2b133a3dfe83f1f0a2ecd0fc9a1e35f77fe9e64a351fb3a061ef72c681c011398fcd3c46865df317bac4b7b515e95a095ad506	1
2	2	1660512351000000	\\x4e35a55b7764fb8f7f612e274a53d196543db4c5faf347dd6994502cfe098caf	http://localhost:8081/	7	0	0	1000000	0	1000000	0	7000000	5	\\x2f4683e2307c63c1b8eb152179d8466c04f4dde7971a50f4503264e3696c01fd10d24c6b3d7364fbc8b5ffaf7cf495ad88b75d6dcfcdd7a337cf276226591504	1
3	3	1660512358000000	\\x6936d088922587535a3b521583419cb22e24fa8bf7e384c6fab77d826ecf155a	http://localhost:8081/	3	0	0	1000000	0	1000000	0	7000000	5	\\x903bd10cc48d3a923697b3fede90b33f93299bd981c2a7c80896ed395a78c7f91cfb58703ea210264ac176782affa8097eccca2c019bac0dd6833bfe9037fe02	1
\.


--
-- Data for Name: merchant_exchange_signing_keys; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_exchange_signing_keys (signkey_serial, master_pub, exchange_pub, start_date, expire_date, end_date, master_sig) FROM stdin;
1	\\xbf29be54f7e3f7eead459f05a19dae8dd447c2263bf56744e731bb3997f322c1	\\x737250befd97ce34923bfd60b6e079399068366216cc7b8c23df57f5d8bcfb75	1675026926000000	1682284526000000	1684703726000000	\\xabee491455243dc924e13003429c9ae67ff6c9f56b93f080d2b1d2f51c2008b01538ff2d84fdd053177dd121d20d11afd605f39101c23791c7845d085e889004
2	\\xbf29be54f7e3f7eead459f05a19dae8dd447c2263bf56744e731bb3997f322c1	\\x551d4ea4c3366b58fbeacea996f29f6b073e80a3b0cd40b789e55bd562ad2503	1682284226000000	1689541826000000	1691961026000000	\\xb6d4f74655d963176f33c13f422d26d3d877dd916452a6b8b4d5933acecebf62d3044730af1878f875f46fdd3ddebd39d57b21c633a568e2616f3f6dd39e0e08
3	\\xbf29be54f7e3f7eead459f05a19dae8dd447c2263bf56744e731bb3997f322c1	\\x36809b1d0e8e3bc73409c53f8b51476e8e6b746888ab73ba02bb4b19d700aa77	1689541526000000	1696799126000000	1699218326000000	\\xc50db63ae1578123fb70b3d748bc0990174faf6cc38bc2bee33b0c4260e14c4c52e785544043bdbb7e465f50e822259a13f622bba3d29dc4d8316dfd9af43408
4	\\xbf29be54f7e3f7eead459f05a19dae8dd447c2263bf56744e731bb3997f322c1	\\x1df9dca4f3f275574e04772b2e6e9668da515b19237961bf91db87270f577f2f	1667769626000000	1675027226000000	1677446426000000	\\xd10f5a792e354da672f87675f5c19851a7c3d862543d74ae3458f6fd38419e36cd181ef76ab0eaee1efe7e3c2d03a49cfd8ef27b80ed946ad0a2561c6f05150a
5	\\xbf29be54f7e3f7eead459f05a19dae8dd447c2263bf56744e731bb3997f322c1	\\x3e6f96219a5496cbeb7505d5a3681d2e2320f472a5e6c66051e2b5ac7433e8e6	1660512326000000	1667769926000000	1670189126000000	\\x40839256784eb80ca73d436caf4494f82eaf0e85ac151127b9e5cc0f10f7b0e6d54403bd395126008cead15b908aad1cfa3af61bc85ab1668c43598ff4b1840e
\.


--
-- Data for Name: merchant_exchange_wire_fees; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_exchange_wire_fees (wirefee_serial, master_pub, h_wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, wad_fee_val, wad_fee_frac, master_sig) FROM stdin;
1	\\xbf29be54f7e3f7eead459f05a19dae8dd447c2263bf56744e731bb3997f322c1	\\x21e4a5e9d5d17432fa0b1f7a02f8047c7634c1053d6aa1f6456ac134caa8bbf3da7776a78f85636af980472afd166b4edad654979a89d92c49a4ba992a7e3571	1640995200000000	1672531200000000	0	7000000	0	1000000	0	1000000	\\xd2652c3385f3dc243586c91f6f2b36aef7460f6821bb42a528f6dbfae0a8cec0124d07e6c920404f813cdb2b6b9c0376cd4ae71c5d8ac1a457b079335aa50701
\.


--
-- Data for Name: merchant_instances; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_instances (merchant_serial, merchant_pub, auth_hash, auth_salt, merchant_id, merchant_name, address, jurisdiction, default_max_deposit_fee_val, default_max_deposit_fee_frac, default_max_wire_fee_val, default_max_wire_fee_frac, default_wire_fee_amortization, default_wire_transfer_delay, default_pay_delay, website, email, logo) FROM stdin;
1	\\x13074fb0cf0afb2d553acb2113c69d0aaf62b3d15ae83b7c812dfc121c060aa7	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x0000000000000000000000000000000000000000000000000000000000000000	default	default	\\x7b7d	\\x7b7d	1	0	1	0	1	3600000000	3600000000	\N	\N	\N
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
\\x8441aee660d091b72e24d16f31751e91801f597fe7276dd5bcbe43806532c662	1
\.


--
-- Data for Name: merchant_kyc; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_kyc (kyc_serial_id, kyc_timestamp, kyc_ok, exchange_sig, exchange_pub, exchange_kyc_serial, account_serial, exchange_url) FROM stdin;
1	1660512344000000	f	\N	\N	0	1	http://localhost:8081/
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
1	\\x2465d98c7a89cf0399bff1afac15d3ff40a54de4b389f5c7648b97f6dc79c1f6f50ccebb946c9de18d2799d7ad453deecdbf88ac1cff5685a43a0e8096c5fd0f	5
\.


--
-- Data for Name: merchant_refunds; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_refunds (refund_serial, order_serial, rtransaction_id, refund_timestamp, coin_pub, reason, refund_amount_val, refund_amount_frac) FROM stdin;
1	2	1	1660512352000000	\\x4e35a55b7764fb8f7f612e274a53d196543db4c5faf347dd6994502cfe098caf	test refund	6	0
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

