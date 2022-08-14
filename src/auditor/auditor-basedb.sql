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
-- Name: exchange_do_withdraw_limit_check(bigint, bigint, bigint, integer); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.exchange_do_withdraw_limit_check(ruuid bigint, start_time bigint, upper_limit_val bigint, upper_limit_frac integer, OUT below_limit boolean) RETURNS boolean
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
  FROM exchange.reserves_out
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
-- Name: FUNCTION exchange_do_withdraw_limit_check(ruuid bigint, start_time bigint, upper_limit_val bigint, upper_limit_frac integer, OUT below_limit boolean); Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON FUNCTION exchange.exchange_do_withdraw_limit_check(ruuid bigint, start_time bigint, upper_limit_val bigint, upper_limit_frac integer, OUT below_limit boolean) IS 'Check whether the withdrawals from the given reserve since the given time are below the given threshold';


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
    kyc_required boolean DEFAULT false NOT NULL,
    kyc_passed boolean DEFAULT false NOT NULL,
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
-- Name: COLUMN reserves.kyc_required; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.reserves.kyc_required IS 'True if a KYC check must have been passed before withdrawing from this reserve. Set to true once a reserve received a P2P payment.';


--
-- Name: COLUMN reserves.kyc_passed; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.reserves.kyc_passed IS 'True once KYC was passed for this reserve. The KYC details are then available via the wire_targets table under the key of wire_target_h_payto which is to be derived from the reserve_pub and the base URL of this exchange.';


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
    kyc_required boolean DEFAULT false NOT NULL,
    kyc_passed boolean DEFAULT false NOT NULL,
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
    kyc_ok boolean DEFAULT false NOT NULL,
    external_id character varying,
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
-- Name: COLUMN wire_targets.kyc_ok; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wire_targets.kyc_ok IS 'true if the KYC check was passed successfully';


--
-- Name: COLUMN wire_targets.external_id; Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON COLUMN exchange.wire_targets.external_id IS 'Name of the user that was used for OAuth 2.0-based legitimization';


--
-- Name: wire_targets_default; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.wire_targets_default (
    wire_target_serial_id bigint NOT NULL,
    wire_target_h_payto bytea NOT NULL,
    payto_uri character varying NOT NULL,
    kyc_ok boolean DEFAULT false NOT NULL,
    external_id character varying,
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
exchange-0001	2022-08-14 17:30:27.000205+02	grothoff	{}	{}
merchant-0001	2022-08-14 17:30:28.034384+02	grothoff	{}	{}
merchant-0002	2022-08-14 17:30:28.446261+02	grothoff	{}	{}
auditor-0001	2022-08-14 17:30:28.567417+02	grothoff	{}	{}
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
\\x7456d3e785378b36877a3fb79e4874a2cffaab3d712b4741c813518f90238730	1660491041000000	1667748641000000	1670167841000000	\\x984c4fb720a52825c61287a4209ef9613b83d64899a087cfb8035a087a06b956	\\x57467a297a789c5cda4ca565d93fa956cfc0d0cb8cac9efe16fbf59db5659836a17197738a2085d558cdd392c2c114955c7c91e5d05957f5c4e96819783b560f
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: auditor; Owner: -
--

COPY auditor.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\x7456d3e785378b36877a3fb79e4874a2cffaab3d712b4741c813518f90238730	http://localhost:8081/
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
\\x7456d3e785378b36877a3fb79e4874a2cffaab3d712b4741c813518f90238730	1	\\x7bb482ff31e4c110c5df76992783d436d27502966372065e8c842c869146d35bd2f01c6fae3c691cb7697d3385c6d57d752233c0f0c33e6e92b78807673746f9	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\xdfb98cb792522377a6ebe11a680c45ab3fc5072b412217ffc4937047441ae1c58d3797353244113f1b8b8062833eaefede373b9c708888a1be6dad568ab35708	1660491059000000	1660491957000000	1660491957000000	3	98000000	\\x93bc00543ac62e3bddcfc7f9d774a144366080c86abd5286a5901bafc1645a80	\\x18e94bb55d36e3c6ee4466b62b874dad943ac8cfb08f34a0e038aa103fa68234	\\xba223f3847fa482c20892a262f8e2fe2760decf777aad28215abf38ba8d74ee208ecaf6bbc63a804f4ab875f3f137b90fd362e21494e640fd1dc78c01e77af06	\\x984c4fb720a52825c61287a4209ef9613b83d64899a087cfb8035a087a06b956	\\xf09816f3ff7f00001d3906adde5500005d7b7daede550000ba7a7daede550000a07a7daede550000a47a7daede550000e0fe7caede5500000000000000000000
\\x7456d3e785378b36877a3fb79e4874a2cffaab3d712b4741c813518f90238730	2	\\xaedc874f4eb27cf94b0e7d7411c7b4b8d456fce3356cf458db561dfe18482da07e2ac9d15128d32d4ec20909b3e73577e66cc0a80cc3f12bc25a78185a22b498	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\xdfb98cb792522377a6ebe11a680c45ab3fc5072b412217ffc4937047441ae1c58d3797353244113f1b8b8062833eaefede373b9c708888a1be6dad568ab35708	1660491067000000	1660491965000000	1660491965000000	6	99000000	\\x97c9d64d2343c7b00b1ad1f3a9baf4647b72a8ed358a7ca098cc04cbaeb80a22	\\x18e94bb55d36e3c6ee4466b62b874dad943ac8cfb08f34a0e038aa103fa68234	\\xaff0d6a6783b40fb2cd0651049b1abdb42f799c82f99c6a2fdf196fa7363d22ef83d9ac764daad889c2fa53f3ed643082812b82cc3432aad4a1b935475d31f0a	\\x984c4fb720a52825c61287a4209ef9613b83d64899a087cfb8035a087a06b956	\\xf09816f3ff7f00001d3906adde5500007d3b7eaede550000da3a7eaede550000c03a7eaede550000c43a7eaede550000605c7daede5500000000000000000000
\\x7456d3e785378b36877a3fb79e4874a2cffaab3d712b4741c813518f90238730	3	\\x12b6d6092ae75562297bceb4d44f4f7f788b39c141b5dd1b4e725e01429e32d2b6439bee7ecf1f31d95a5e871f2b36a0ee2141f8339e38d56bbb9d9016185aba	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\xdfb98cb792522377a6ebe11a680c45ab3fc5072b412217ffc4937047441ae1c58d3797353244113f1b8b8062833eaefede373b9c708888a1be6dad568ab35708	1660491073000000	1660491971000000	1660491971000000	2	99000000	\\x336f8a0de6612a61308d2b4c759f3ec350ce2bfd8dc31fd6f1f097bdd1afe9ac	\\x18e94bb55d36e3c6ee4466b62b874dad943ac8cfb08f34a0e038aa103fa68234	\\x6518ffdbaf6c38001256f4a468840ed9d53c4589d05a1ef2e937e4e632d661fdbae2a98c54af10583524b92893077cd5e3c53c95797aab984eb2586496e5f208	\\x984c4fb720a52825c61287a4209ef9613b83d64899a087cfb8035a087a06b956	\\xf09816f3ff7f00001d3906adde5500005d7b7daede550000ba7a7daede550000a07a7daede550000a47a7daede550000c0697daede5500000000000000000000
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
1	1	65	\\xe9a6cdba3b53744ee9faa6d95216e4a7bf9c04b231c43236c90f747019cb6bd9902a904900ecd4b592f3471f1bb767fcb26d1666d41797e266faebd7d1b72005
2	1	210	\\x11acdcd7efb8e35acf64f3441d3171b0bba76a956edfbfd3895f82276113250071e7ec3522bd56203639405ad73e2bdca04062982539ed07d4009306ddd9a403
3	1	307	\\x12b052855abd54f8add43599d72b1560c2e042934f010f30a19030334987ab99038b2a2ef637129ced7d3c0f14da9c1d6fdd525eb0f14579c6dca0290d58e109
4	1	96	\\x158e2ce682ef3f2b099189c27bb68e610f022f5ed2c26d5444a04c35037b43a514c07b7bc5df4a2339efaab77e6aea00019452434ba2cc2ce05e9b6c18b10e0d
5	1	202	\\x009744bb66f8232e7a2e5905ee503297e9cdf62c78686939e2ca43143c771a355107e1605ac2179eebe52db788b7ec0a800f1ae187f70e56acc316b019b35e0b
6	1	184	\\xe163478f9bce2165b7b36a6385cc1ec43bd3730dff73925fd6d98b6b6654731ca22d8878171db7b3651f70a2398fd8dc81c5e128018ca14edc88cef726caed05
7	1	242	\\xb5fee3ddeadf8887abe122e3232f3f1aebc9cc5f0ab57a451cbea835e5f112eaed117f59bb20ff8252fd7819e51fee4e8cb5fbb778a33d23a8f79175fed8c509
8	1	370	\\xd01519eba21666ccaa3ad0ace57754f7e3f18c3137f0c7af49a25feaa47fd5298ae36b40b8649219796c1f1b9b5cbf2a9c5c7254c334ef93a3b05a2993bda003
9	1	271	\\x96064c58418396d5522b93e57ae753eef60945b1cde0b0aebb68e384bdb6e9500db0745ef97a4d8dffc3703c4f84c6c059601cf6f2388dc2f40cd5274eb54c0a
10	1	105	\\xa157f40cea7dcea480ee47e8c601b14d0e728a67df0d7f427e03b1d5237b3c18646806c1b4c4ec9af3105237b86cdfc62e109804b21a4dd91038925195526302
11	1	164	\\x73ff13d99b73578e5ee6b3672d5a4ac2848ba9ea58d1616305008f34b8fd0779c18e4776b9b903e452f8653e3d0fa626104225bd257c58ef62c36ee16171b40d
12	1	116	\\x9f909fc3728b3bd9f3b0727becc253f11cadeac967ff70b28f30e80037cc5ea39d6ba644b1eff0e8dc16353c7f4747269ce29f067a38a6e56f9d0a055dc03b00
13	1	275	\\x5edd785787997f4cce6fe1fd630deeb751779aed715f626ea60e7547ca795d6c2ac803937ab3d60388121d7a833391a488f7b897628d7797be0b9ceeeac14305
14	1	1	\\xdb25be88c593d12ca7b3189fcd651068000c17bd30149dc8e2e94ccd876f6fad1db00502705564548a1210e37e7ed5183cd2ab6038bfd30f22f505249b83ae0f
15	1	53	\\x3ef719b44b9b544d99edd50b74c7c0e7fae3ad176ddb20b9e5cd6f95b70853d7ce06d2c76d76a03c555e1fd6a76d02a8ac3130ff1f5d5c9648fc6417d8b44c05
16	1	170	\\xd2762b89623a0d9bbc40b89bc0e30c5a6b0eda54b9a576d98e3bc835785a63c096045b092ae14fa9a8bb9c2e011b8ddcfb87731efdac6d996ec39ba5e07cc10a
17	1	175	\\xfab24fc918c6cc540dbb737ac98bb015f32e51773f6bfca155de2c2dffa14ed4e98827f25b36b77a900b4a817e5e7a1aa6ee5416f4507c1d40e7845dca7a8805
18	1	147	\\x2bff5e1bd357b4e9700ac071872ad6a7bdfc382a3948499858a5926c9868e372a5cd5273d79590a8f55b9db8811dfbf83df6a4607d8851cd52fd431cbfd80807
19	1	279	\\x2239a894ac1fbc358c915167126a617a71e4eb9978ca0af915afa03cc71cb17fa73f51b501b780f30282339902f720c2ffbc8da4d45cae31a4ed4d386d04df0a
20	1	263	\\x58dcb40dc26a438749fde2c292e66e68d9f80c104d654f894b4a191fd961ae565530c66b8916988ba8b32a754a332b68771839a0315c25b6fe9565fd16c1310c
21	1	401	\\xb3548e58a1cb6d2a6339381f516aaa32ff8863d38c31c1c2755f6bc929bcd20dff72bf41cd79630da4562f77bb2c7b048af3107ebd844b074e58eea88ff65001
22	1	403	\\xd5e7c34fe34012ee949ef6d4f65a7e5c3bd2fa7fdbaa09ea39bb9c9d119a94de8aa776f8279cc447abab41c045be4c08d7ebd2b149a761d0ceeec13ad5e8c500
23	1	119	\\xa7098e14d867bda6fe79d0b5d739a3db572fb9b94bb19001d13a66d959b14ac6a8b93642ad222d52651318f9b51f60b874fef3125ea19f4facb6d3a10061b304
24	1	122	\\xf79f897c830d655ce9b517654e0e1fe51111ac553f1564fc5d088b1f56992a7e9cdeeba1ed89f1d2624d2d0ce526ef23c215f49652a99d54165d0c864db06d0a
25	1	112	\\x76260a538cd64ce1be77fb57161b311b7d45d0ebad184828a74d052a1d0964102c29fb4eff2ac861aad1bf318ada78910ff5049de9a9ef033d2b808ccba57104
26	1	97	\\x0367023bc6cf2779adbfe5f94a6e622879eb101c84632492e30eb2a92e571161db9b0bf31dc5c462481365f34deb553243fd0813945dcd579bb090e2e6511c0c
27	1	387	\\xb6b9bffa76ff0f61e84ab92f94d55a8b2823fa6464e48321e54b04c8d93455929738b9b999665057accdad778ea994c64c3b444090aa318a66bc90ce7a2aa503
28	1	206	\\x0065479b8dc9f238c1d5928ab4907eedfbf373ed71f2a499a6b968f460eea82aa66205d40418055c55204e6b979337bbcc198e1914b2465cbba799f6c5ec000e
29	1	255	\\x7d1b80a93cd8b6ad36d7aa11cdc8bd4f337f02fcc0dc6fc66efd2141919b71b74ddf1d7ab22d0c0dedce64d909ddcfb94b6b300b715d65bea37ab3430dce280f
30	1	37	\\xb08f53117b261b90fdf0ebdf0142d76edd2b4c927bb6e684bd2c7fd5dc53066938bc5dcda013d0bb7c7b197d6ef1e085e6cd8fda5d2b995c9fc44bc208d04a0a
31	1	45	\\xb8c0d28f8c357bb971abdbd044dd16a25e2503f96bc08c129cf0ecdcd8c9da9f05313c8e45c0fdc50000f01a26bfad3b348a146e1681ed993df19133203fca03
32	1	64	\\x7c6b054ea507b74bfad5e2497ce2146f490e0d072d4c011ec2a08937cd494fee6df79129cb25e80a38edd4740b5dee2a68930e4dd4260804d1ecffc53583d60a
33	1	131	\\x93e64f1b2ae01a36b1183768001495a855d1d1bc6bd442858780a78b230eb38e3135f09d7ebf263ab01a8367e3f7c556590636f216371249c91d22302a64e904
34	1	84	\\x52b33cbf70a5ce4eda0ad69eb9a182bf7a3c2ebf1978de9093fa7ba5bef79109d09de774c58a92e3cb4e7ea464663eab4939ebd19bd50dd32ffac99e06999204
35	1	15	\\x4ff77ea1da82e3d5a952bf3366b23dcc89df737dee8793e75b827e1e12e5fdddfdea86c91397d988eb152b35268122e0f7025fdb1cbe9ddcc50555b501881c06
36	1	283	\\x2caa31223e1aad4832ec8537163508f8150838a668f4903e0cb44f89d34e8c835bc69449bc8e7ce51209ce84247e1f42745d2b006f28501378b92e70fef9b003
37	1	234	\\xe926ca1e6db1b52d8e80750ea6ac1eceb675192e92adbe87e4021f111168a8a732ac736e6a744add18fd32a903688b15bd8a5b3fca34d8dc369597abd5907703
38	1	381	\\xbfc2f4c4a01d1eb93dee4282ed1c59d1e096869b5eb803f7c04b59177ab507ebb46ed507b27175109bbb5f487b63d4ccf984335aa925de5dde5e0bb55fbc0505
39	1	17	\\xa65c9f768e92faf8decf55ee3ef1b2abd8699b22f4ba2f1dc47cc7a4a52a61d7e2935b8ac851faee08fd359a0f597c6b8f9bf79f42e54549995aac39b3db0809
40	1	215	\\x592aa0b708627ebb51ed54cd2786e526a15751619dd4fb14e964437833d6f990c5116a7e49aefd308193b80f80faa260b03c2ca8c930d552e47054e1c844c601
41	1	196	\\x020b676a59ee8d54b6fd14dfc13da5ce930cd1e87c5a04d3520e668e00e73e133d4f147091fea648b4eb292a6c52787d273ef22bcdfff3f909905df597169d01
42	1	222	\\x2023e4e11368dc2b6771afce35bbfdc4259be958a429a9f39efae57a7abeec908642af3817b460fc66b7687cb1f16d378b8308bbc6dcc1ade7b0b3b8af4b580a
43	1	257	\\x60e6607c6b2d4ee01c39c6ef8e1500a3b4f76cbde338a174c2262fdc8030e367b470d070741aed8a28ae0250d4e00ee147618cc268c1a27ad91afedd4228e303
44	1	152	\\xd331d3c7d5dfc3c4d529be60ea280e61eb5e605593d66cdea5970ab8216f8516b85c0aac47f8b7a881fbdf757177a59d1003ad95428ad2186bd232f7ad54e702
45	1	249	\\x1f709b3e83bb98bae09d31decef35498bd9ad91eff28ce17777f79dcc39e783f3810c2e4d184de73378207b39467517662454121af98eed9aca0e2861c4b2e08
46	1	291	\\xf187cdc030d83ad7d9d147e19e749f58564fdb971f13f8db99abac1c2a82a5139efb3275112dd1ae2717b827a2430d56a6ba81790edb737f4ea31b4e20fb8201
47	1	295	\\xfa0526cf5a4de0c48eaae569d32414e705be0dc9270bbe6f6d19c29e8198cf11a8e5f0a9da5059251ae719ef4415917b09cd1267427c84d2cef14997b7c8420a
48	1	12	\\x9d2f18c31e04c0dc2ee2b5cf7fb317452ffb91a17b1641cdac45870e55d14f14e97e5c06a0bcf5ad158e8a9a8ffcbfeddd1e1d7968507d12731a79155ebd700a
49	1	146	\\x8ebdfc3cfe52fa9734791af828468164d599327edb35e47d508b628bfd85d6feb6e588d778b97cfe615fe6d953d7929a2d6a9393fc9bca2f244b45eb2457e508
50	1	195	\\xc97a1dc91e5c913b2bfef696ffe5a86986cd2d37fe8b03eed0f346304987140ffd659ec849f3cee409d615881b8835cfa7f0ad6949146a973630bdcfa370fa0e
51	1	32	\\x1641b1773079e9b2278a4fae015ea11cd1f73de48ac9edea240763bcb0138a9c5f48cd63e1f5ebad0017b07f415716fb95c6b29376ceba8b0efeaf3e0acf940d
52	1	113	\\x59887f365e879e1b2c68c4eae1ccf7c7cff96df211f822255df7ae8721fb5a36ff64898e092e89a9b777cc2927b4258a97427d734474fd0692f75d935828630f
53	1	380	\\x28b1a8f38e1e14873737467814b39ba63cfba6fe53acbe568ccf308d5948d15529490eec9d15819a66105d873753240ea421e6752aae338938dcb2c96e3a0102
54	1	327	\\xdd4f59778a238059afd9ff9823e3a41cfc8cd7ec8cba29bdc17842f918dcf8887c32eade914a5b17da557523ff94488e46c6898b08b60399b0fdef477004a20b
55	1	230	\\x1e2286c1ac5b106897b285f57d2dd8948550a72d352121a3d37c2dbc8d7054956408cfb8b59f69a15e0e548c1b795aed2e715f6b315ef999a3761c552563c606
56	1	298	\\x8e9ff27303205136f4159c8e52b40d8235162d2fc9c2c9c94893f832062319c5856b782827ae398c66b5c29caeb5c10f16f509c1acc99fe08e4e36d98ab0f10c
57	1	68	\\x25b3d644a218389aa6cca3f19a5f5e8805eccdfdb36a6277c0a3e9ac4ff1e96ffb0847a0bb2b13830317924035f3088eec95abab7e7f0ae98464ca4de3d28704
58	1	320	\\x58b6f5af35f5467fc9861012d7f1475b56462903a0c81ef4d28f585de5997da8a18eba0c61fdcccfedbee342c7cff2ee9f78622109f8f56e618aa98a633e060b
59	1	28	\\xa24439fd63b6f8dafa708169664c5ba34c06d04d76d25ee36c5aac3704bfbf5e822f91c923dd470f5927f885421d7d788a26265d3d69849faddf4139b5e40903
60	1	50	\\xa0435f8fba8b62dabc63855a8a6f718f01a1c1fefb70d416adaa4be54e82527e5e1fed06eac4de46200fef9f5f4bca9008a1fd9899660516fb3633ca8a704004
61	1	60	\\x0bb8de012cdc99bf2e17c9e033a1fe702bb8f429a522e0c8eb70873ad12d8a880f9c9d46260a84d0704e3d27df49b77dc1da775a2d6dc167bfaac96c0f7bf204
62	1	212	\\xee1cb3206c89e4438ef4358e64a98d5ea6976e81e8948950e6b5136678d5360236379491badc45dce3c7578879530d276d71c591307f6e8004f9e85b7341bd0a
63	1	59	\\x09268a96386fbb76f24de1c20ee159f5b450cfa21b71e8c450d11ab5cd46194527695cf023eaed3bf48538e25777d0bc12c38f3ef0dd3dbacdaf729b52018c02
64	1	142	\\x48fa6b5ae3432ab38422811767e40345dd93f5d4e95f8a2db96698d4ea0efee402b55c1358f5c4b02c79838cac31c453f4faecaf06c71dced0d6952db3952509
65	1	314	\\x708a658b798e0ed669de723fa6f790a31b83b4a903dc86e21105ea69f57850e110de13834e5bdc2cd5bd598f8da324d3a4414c170b8d2ba2dd659be2c0034105
66	1	286	\\x9f8364ab837d984fdc988d232d7f0dd91b0b48012d5180d4d87e4e95e467a9a31c78f26868f417f03e64f75e196ca2378d17b65dd65b9aada5d45dee49b78705
67	1	176	\\xbfda913a51d26c7fe309f6a267fa75dbfb64a2bcde4491d81f422d275863c114bddf64f0a8661fc11f86bc307365de2c84ecca7387706dc846893a7931cf7d0f
68	1	29	\\x797cfb9bd3dd753cd660588ff8dd4cf2428656ade51c783de2b51e90f33a92d005b26d9ee16841761d36ad385ba45e11a787e0056cc66453e373e90f9fca5e0b
69	1	354	\\x1dc4fe6d5d96668f0aff2902931388a70783121960f35b1545345e78212429010a8dfa79493cdf970eb529dae800f1eca824c21c067e4b55c82e062dbc7b8608
70	1	259	\\x35c33ac467f110804e9e640d4739480c0f730190fb506f683f35eafddcbee01dfb56b7af04a344ea70359416e1ed598f7494a8d2689a4692ba5898603e2e3406
71	1	31	\\x9c2b396deeca506f40154895eaaf0b6a55493ba5481d5bfafec9d70660cee0d397ec6d78a990b5960d9d2058031a74e9dfbcf97111e0a6e2531a0023b143aa06
72	1	201	\\x6b03847f6bbb9ce1564af8e0c52644d9619524c4dbb78b49fee257c1efc781fa80d05362a24135c5a22a45c57714a1e00153d3e9e14f79ffb7cf1d50bec5c100
73	1	20	\\x29127ec47bbd53f6f40166b9c0a68ea3cf8a38d402d076a3caae99eb478ede1c4257d2eb28f4f3598d7cbae33dca1d91fe2a57d8787ce7e56c009b1ca2fc8007
74	1	165	\\xa5871d9503f3a5d71bb1f41ea0afd0e20934b920b4ddeb4c60476d0e6f45f9d229804aaaaf907081c4cbc3cc1871f46cdd492ef9f0cc763af8d66d08845d6d03
75	1	420	\\xa92f93a1fdff459ad4261e96465f13c523660f0615e693f53e78c60f7c783cc669cf87d0d5eb66c55a819168505d127099ea9f059e76d38b6ce618fda3501c08
76	1	417	\\xfe94a16fe6c7aca570077bfcb26d4272be8d44d2135290170ab6a24660d1ca3dd4a73705826964c81d8d3615e8e57a650e027d9e96ae67e9a179e6454a9d320a
77	1	27	\\x40b61d29591fab907abbd0eb449035e0454ba5c31e75489208a69249d8d6cd0e01c585412f0b9415f27134aff493836690aa1ce0193f895b6a619bac18817702
78	1	335	\\xb5bd7431652452c2ac3c4614bfc92c0f184c275fe8c0846ffa3dd65edb570bf93b55fd3ec6652896680190d4ee8346200918daad650b7399207c8be470e34006
79	1	139	\\xb38f031312c1f95a995ec82dfd5c67bf0cd82b78e45b4eb21c60d8b685a0d749b392bcda31f6ea2a444f6f9e5af431e63e3699c2c6936ce118917fdeda81c108
80	1	368	\\xbe363b1683472182ee4f0230ea33dd0050d087768de0b68f787bfab2165f671f8097693807792ede495f6f21091edec389a9dd8b67824183a771b2d2321d570f
81	1	338	\\x1f269fa6b963524f87623f0f56aaac6a61e8a4cc83aa9da6f1f67207452571d872c3e7c431add7067d1dda7e8010a25a4145970933395856ecf9f2b022fdca0d
82	1	125	\\x280ffc363d81a42536129fae1b6900e9777a45e9e266809121223d0d84ad813acdda6b5bb47dee3d2e1922fddf67156f08bab7964a9eb6655e1a8a9ba7ae260e
83	1	54	\\x625bb6a8d6a29e9d387abcce863fd448b8a0148a9d9bd437c0c7e482ed0f2e1aedf9557e7b4437f623d391aae13f43bdd7ca1dea6b6819e3f7d834e3805aa602
84	1	3	\\x5b9e945113cd7a70580f8c2f80814af4920255eb4f887668010b9da16579e3ec2d72f59213b1cd9c1a96a6a0f5635e288cb295c9249ef993559ddc5d9d77380b
85	1	328	\\x3654157a0b7f7fe8c3b02359a2641840bde567acfe5942497f17e1ecbbb7518bfc149bc92ef831c0b73babb85bfd728041ae7d2756e17b50aa9955462bc45100
86	1	89	\\x8c34193fba43436a2a72bb01baacea02ca768a394cf8880ff7a105d4eaa02a88757c2e6b4f9cf2e50bf3ea690ee8db6b4f707c1901fff7bee7bf4ded6873a40e
87	1	92	\\x61050ec242e0a4eb6e4c91e6b86d12081138620a35f330622824bb6749fd4c91f44428ce6603ef0c2cdbfa6ab8099aeaecd9ddc5da81492e4745cb88f657cc08
88	1	348	\\xaf96a8f2e5a6097536afb47d73dda794924174f66fc9df982185df37e2385f4d3ce2108f092ec5ed1bb863c1060a2880da7ec681b5add881c8988d382ac7cc0f
89	1	221	\\xfdefa858b0df28a3987d3938aafe40954e769ccb1b97cb63aa0d60f4a6c0ef3784bd6ab66c5c6dad654282bd3388af92b8f2e7c5711c16153ee119add18dc80c
90	1	258	\\x8997cf6766d986f7d50f6b8d16cc585f78a4c62d702d8def3039da3ba0bf1c03a64021e64542480944887813cc359d12c2a3cfffebb9897ec15858a39152bb0f
91	1	158	\\xe357e6457cea48576d27facc25eed53e189ace8ba102a5815352bd6e0fe3290a0e11c4ce7b41af9defc57352c48f712dc084c583743bd99b8e312ed3d2489800
92	1	8	\\x39c2e6fbe38824982f7d3fc47100014f917b524143041a887b57eb925afd2b1d5b43eeb996687aa6371fce0d5f6c7d926688fc22f0408442ca7cbf1a29bfc205
93	1	4	\\x32be108843c039e2c7a3b8694ed1b15a0488f4729f141e454d95f2258890317f990919e1941eb2d78a332dff2dfa01aeb8a9fa77f4dbd0012e3150aab09eb206
94	1	353	\\xb65c624c96a11b2d5dd94fe1f15d0d9244ba53919ebe9f3ee1c56fb59aeaad41fb4986d20502be79ab85614bc41ca216038c9e3d482a43cbc16c3f31fc1dc004
95	1	333	\\x3fa38db197f2833f324afc1c1c62ceb6b5c92be5357299566011b28c7f9478829192471888cf7b03282960d3e5a841c9a52ff0582bf3ea7bb8d1bbc3be89ad02
96	1	141	\\x606374a32c4750ed73ae8e60ff8de760a8f17fba10ae40e794d1684c14b5ed568b3eaf9d2df4501b6829e7c90867ac28db587f3f6fb6b051b2e9e740f4853e00
97	1	133	\\xa4d8ac9429922d6bdfc1c761243b5977f904d2120000e5a45346e36aade3fcc380a2b433af9f9167ebdc585e7f7240a68ca6dd0dddf6e0d6a68631913ed5d304
98	1	200	\\x0cbbca8f632059ebc53021f28450fcf14a76ccbd8a931414d6ca83aef886980f8cafedd3d1a4db03fbe2ff7816851c59d778b0d3ad8d14c4b9c6771827241d01
99	1	362	\\x3c8f2767847345139517572223c1ad665e25422e23c9fd4a7213414de94140458a481efe292155a86081ec52d33f026b8b7b2aa6d2f49beee2f8dc28d478fd0d
100	1	415	\\x6c8f8b81c0a678dbc74ce19658992b3c5460e8d40a6d19416471391a61d4e84eec0453a1c7c68ce034b3054ca46fa54117cca8a4f47384d9aa24e6433e9e6a04
101	1	169	\\x9b2231da7adb5e0dcf3038e73de4a6955fbdcc2f22ed135275dbf541df9c2c1a8b9b352100fa795f917dcbfe3b84f076ee7c28b016062125268ab5460964a401
102	1	134	\\xc27161a056cf9b69f3875614fcd165778f81b340178aade4540906b6de4fe0b8b84667f4723d1c9b6ac36ff1296b31665176387db14ad8f2c21ad1c2625b9205
103	1	148	\\x728545de80f4ce848c248717713065269f7c783d23a62309b252546f83b0c07e5173224f8972c71682cb309b2eac87e129b4dfc57ca0c6d958db895acb2fee0c
104	1	397	\\xb2ad5616adc5b5ab76048db194e089ec5736ee73a6a72615c9c4e82f557436f6bd12527dd26677739322593a429745f325ab5361fdb15f3c6065a5f7d3454007
105	1	33	\\xfbef979b3cf659af5b9334153528077aabac46ceab10c64e0a964318d980cb8cbc2b852cbcd622c02baf1a0c2a4086d11faa07d463b76f14d3e4301f3e0aa408
106	1	371	\\x82c2c71528e01270ee30fee7c38cb16477c21e77172853e8a3df5daf925537153c72e70ed5d0c53943c494f466982714e572793018ad61f264fe94fbb54c0c0b
107	1	94	\\x0840e33aa40ffaaf830cafabd3dceb3ecd3c07bad2763c5f9a4f4753c6254d4d54d860a011c2bee61f0249faa1f54c061c5c51f66724dbcf414da1d290958109
108	1	193	\\x8237041110a3146c58b5c9a5012690b9d207aa33653bb2140c1bc5bc8c938e91b76394b43888b1b36ca786beea03b6022f367a73ca7c7b136fc948462ab65703
109	1	347	\\x685f148f04d565c3dbb3bbfef13d242725665a86a93f709c2e2da0428726bc971843e67529112c622ad25cac1b44fa20396160bf6a8a73a989fc0489bdc45d08
110	1	130	\\x2829bbc5175ca8a1027f2e31f05d1efa7b42dd85a6b45268edc4ec877c188b6b7a599685721e2576b7cedbb2bc18eb1fc3c6ce0110dc85e2b17b9e47ce51140c
111	1	7	\\x9338d67b2d576941f9c77f64bb5d4a4b2bf078d4c255bef23cd557e53a77c72104f596687ad3f2a92403b4b5dbb9ab58b4f7f74f0de2af1dee9f6261d14b7803
112	1	39	\\x19c57525d1d843980108b9018aa536271f8115cdfed51159becad9ac930edd6023d242beff153b615f621ee0cbba569ee2f86d43ab365bc46523dc736430d502
113	1	203	\\xaa99960e5194fa6a937b30eeea6b25a297a4008b67b4c947d838b9143070dda21139e5de5f5492e993137da324811dec4883215ca9683d87fcb976ccc07efc01
114	1	247	\\xb413fae2dc5a3d15e16917990a3f0afe6d7fd02719ee2f375298c7e8ee931d4fa757a12f97ef00932b9e38d79b1e96f586c5e4d906cbde8108137d54d4e3910d
115	1	252	\\x4758053f57acb6d0810a15862b7b051617bbec8eef26dfe2f99b653a44938eb2e6aa3a1bb5a8f656378e3c7a6ec9500a8d7237de4e630d1804b47e7db71b120d
116	1	268	\\x32ba9f260d0c3b476e5658e0eda416eaf348e23caa84c385cf4bd29b0c403f370a1162fee179f657199fc0f4f3ad4f066507643cb55ad9edf04d70624b69aa0d
117	1	384	\\x3fedab9fe7cea138473e6a7387534fd65127332df03d060b6ee2abdb31b82157ada5fdbd702c7f326d69a2af79e90a153c2d461d6555c33dcab4aea20a3eec09
118	1	232	\\x3b6f056ecb6ccc123bc10992566631756b54cb98e05cfde9cb859896a41a25d465a060eae5a3fa4580e76f55bc21735c293ee9389314bf0dd380c3acacddca03
119	1	127	\\x753a4f5d960af92b7f728135fee7eb475872f309d0787f58c97ce462828edc96ee129542d269d883851c4c1ee6b51a2907524f11ed18bdd28cf6f956843d0d09
120	1	72	\\xf5ebdabd7024816bfaba81558e3f933f33a2ccf433819eefdd4c709fcbdcc5f113438166b3b11a342d9d1e1dcb3da5eac1a8accb2794c5463e42adffeb68ec01
121	1	311	\\xab40762521b22ad8ccf0f43cf6d29d4d85691c3ca10fa07ee99eac2d54eb0e80b688b54d0734fa794d9e4d2a89708614520fe3ddaf3a6b16c191d663c3450a09
122	1	87	\\xa8d522f8685f1ca102fe2c2b890759466fb5fa38a05489390fe75e2ff2df57e37b0f39870b5fc2efa6a3ec17b9a698239f94f9e97740183db3fae66e629f1a0a
123	1	379	\\x4347fe3fbbbd5e89d806c1b937c83ee7742366815e8afbb4fdb9ee17b0731157cbdb4d88bd093bc1351b9dbf0a85eff573f8319a50fed3cad6a2ee2a40110806
124	1	121	\\xb17bfe58b2b7255feb1d516743507265ec9b8440473dfc2dd2d640780bb884a4bc4c40d55951da51f305b30dcfd1bf796b7a1934f8f8a1092461f4cc2fbc5b0e
125	1	326	\\x821d9646e631cb9ef0ddb3392a8b6cc5fd96e87ee555336784710eb5275cf9c8dc2081ef8583333b776a751f69568ee881110af94a728ad5f0399eb005d29a0d
126	1	241	\\x47079d2db53ebf1b7418dd9fdb5241a00f26932befb3f3f6a2d7a4372f6f93c027c839f06786e7c27a0746ec6c26b3cf91ebe201d86e22ab7055ecc436b58807
127	1	63	\\xa66bdecea54ec0cf8b1078c591239d95e5cf19cbb1e1b5126bd3ec81ec87c71ce08bb25bd1621ffed1e79d4b74ae08d5deaaf47140a6472b96c594a51b318c0f
128	1	136	\\xa939d6e0cc23e16ac9c2a165049e9a2fc2220edb9020d97ea5850851b126b512af5cff3606c95716dab408068ca58b06ec68044b7343f5c4b4497bcd6d4faf01
129	1	344	\\xcd53d34e1ba89ce78bf8509d3ae57ff787a379ff6159885d8f5e2f11f093ce7ace3dcecece5d6a64fa6b43507b25e0017b5cc3b06506967a9515be7988bc000e
130	1	398	\\x22b70d899914f62593976696bb8c711a4801b252f86745edaca12280ca5b7a133685e5044854edcd71071e06e619c989722dbf609c54a63296b5e3182847e106
131	1	126	\\x2698d12738b18ef5c0dd4c14e86d873e783fe86573f0b33e2f714f961503cf4a75896abd3a35da507e61f7cd683ddc03e2171f41becbfe1856a89425e4bcec00
132	1	290	\\x704948d30f76dc34fb4d9325a7b36f6e38eedd028690586c795f2fe5850abde32c9c8a6f7657fa1799b5d8db2d13c6fbe80bf0fe47476ff92e85f29707f7f70e
133	1	187	\\x0b7478e7688acb2568729c4d3806156aec696ff428bd28200c8bac5a456c046e30cb3b26ef8a28f3bd11452ee785946e496cbfc1b0659c09b223b488ac075201
134	1	216	\\xc09785e748222aa325810bc760553b9f9f246458f19412b2e83542441a19962e798f992d4281ef3b8c92324a621f69e2c20d6221e75250ba320d3f8a46a1e506
135	1	289	\\x6055a2083c112f303819bd211a65bacc641dcc3506a491bfbb14c6f2863948fe34ba3027645a00ca3e8562e4ac1c725540358a21e8e142dae7df9fd6bc5d7103
136	1	102	\\xcf3a237a32c7b31bdc35e786682b0237608d221ddb0693fc5ce1c98ae901265327e9b3bda112e4e17990464b58934ac5a75ffe791e96e895357367a38bea2802
137	1	137	\\xb65f13743204849c809251118dcbf23211509fefa60c48244431d5bc2450be07c32efd7c6daba448538e828a061af03c58b5885028ab1e7ca6d0fca070ef2e0c
138	1	373	\\x3941e64ae830f11cca550f80dd96395a654496cd2a9c4a625706dd3c3adf8c5c321cfd857347edd742f3b4392b0b5e7462e33af1ceee60ae0576c467a1623c04
139	1	317	\\xaa5329bc4940cda6fd3a902ceddbde413e06587804258ed3bb443108a3a2fe0a08309b45d2aa769aad25ba1911055058fb079ff471e671c53246cc956560e00b
140	1	6	\\x0b38df838700c4f69378851f04373f6c5a6bd3856d0b0afd099e7ce232280688b2b15752349e30c142d7d28d64bced2290cce7851b0199b5069d0be9c3d1da0d
141	1	264	\\x2c81417974c13dc4d8b62bcaa7572cfad9e561b0848d74a5d4087ca854b5eb695d669347ee403b6fb80b5aaa3521e30e736d35d025c80c8655a3f78f6868cf0c
142	1	395	\\x575a76a466419557d5ca6b420345695ab6b8c556ac77e49cd06a5f2428af1c1891fc89a55668d5be70fae78199272c0de3b6b4ef1203c12e26e364eb0440040f
143	1	382	\\xdb4afca23d0745d7834637e7a9dc89652457ced60859801523947ec54a172e5875eb88a4ee2ea8040e2b44240680a3d90bb620718d4487d60247f326b35a210c
144	1	194	\\x5e725f7e0141d7c2515a27c4ec8d7492253efa061c1315a9c5efc2db5dec9245dbac8c6ba898fe55489fde8ed7126bcd1fa5d329ec0521130eb4ab1572583708
145	1	43	\\x3bdfd37b1fd18aa5c43fce75e2be2f8929bec45315ec1a0f89eed63ee2ecb61edb42c5af4947b1753c6cc14990c07b644195114eb130e91c09a7e43890c0de0b
146	1	189	\\x69a8a1404408fd2aaac056daa510327b4f4031fa4efc6f7d63c38b1d14cc910463b5010cc771c04c6649d8afbc988a7309391e9d8fc0708f7768f067ffe51d0d
147	1	85	\\xd9a877185ddb9167af4e5802ea2b6e8793b120986fe17deffde416a131b28f6051199405676b54e84d465e667a183a224c5e0a200aa284836250b57c42d67b0b
148	1	83	\\xe1215de415d4a8e7fcd1cede0099823dc71def32bb237f91d489bec4e1103cd8fcf24fb36445ea770bfc0e9c82e74ab71c67a9ee5323b89482526abdbba93102
149	1	406	\\x40c1e08c399c42350b4a3b3945440ed66bae377e933aafeffd1cb383cde038f1f6495120b2a263b0d34b1f4f3d572b2f04c81a8833883a350a27bcb7437abf0f
150	1	407	\\x32732a611f71179aef9c6b70f26145e8ad0c141096480c7dbec04c661d81b7279ba14f3878b1546fd83ebbd3ae0b189d06822f86a244eb5bbf1dc85df88f4001
151	1	115	\\x0b0204bab0677ae8a0713a8eac9dcbab42e1d4979522f2fb4d28891553eb37909dffda6954e6a1eebf988d24d5b0c999ef146d64e27f1248a213208e8b01f704
152	1	62	\\xff4b4e8a948ef698f9249c7f07c058e2940a9a0b35065286d952f0ff0faecdb8780a6bfee4e0a4f6a68b6a4bab32ff1d8aa0fc87d177b2069bac5907b473a903
153	1	34	\\x2c2b1b9547aa59a976b325fbad66e8ba7c3cfa412358f01a49fad41a73cb9f2fb07487a9e56b1123d1421b350fd0e25a773e1dc6cef332285460b90ae6834b03
154	1	309	\\x6b344b94f1a549cedd68aa08dc29ed6368205b06bca34463e54c0abec853833762ad66b8aafab1fa29d6114ade8eac699fcb3b25146cf54a83cd8f6f50968504
155	1	219	\\xf9f8fb39ed3cf24b52040370ccc30b71ff0d0974e4431478cc6922ed9880595c4f746a7a3b536ca2f27fbaeb89b5c1076fa5b991f5d29e37d973401475a4a20d
156	1	358	\\xd0b163e5df6da54d3660d07f56833beb2385d57b4c5606f76fb6132be3beaa0f059d6e3519eab0a45b014cd76909e7b5e1cace5196d606ed562ff3b563647d0a
157	1	226	\\xa3fd1d2959ed0f78e0327a3087e6689b61cb6c9c3ddc598b5b315f831dea59f4685ff540a4aa7011b466771afd05142b420eb4dd3a84611df6538b31bd55270f
158	1	108	\\x03f0221ba083b266671c30576a87000900b6d3616897c28f69ed52566890d3f59a1c8fa1fda4b3720b2e3d0ca81712801b2cade47c5d5db755a645f56f258000
159	1	48	\\x32f3b71c08dd957105c151e99cf83917366b9726da20f326e1c33ae4ce31d8111b6b7c88c1a3a1eadddf5f4733afde42544a2697c9623f05fb0e9ba65651e801
160	1	177	\\x39725ea25042007e445e1755d375df77dac711c792c69fa384882cc447f0b7a346bfebe970c548cfe6c2171b94eb7857d2126005f259dbdbc8527ecce5efff08
161	1	388	\\x7033ab4c52aaf6738190e2b5f5d51ae295d7736b01c977bc34a6257db2437ec8934db996638e30592a609bf22dd4836c7e13ea1bf4c54a0dd8e587951eaad402
162	1	236	\\x9f321c696c48156a3f54547373f1cc73bf1e958c9de072c36479c0b4bfd60824e749c3c9e7a7a90c7ff54488a98a031bc25680d3695a449be43f5cd781e06103
163	1	181	\\x8e882c3edbcf933ce96423787a8d4477c68dce3d2d13f0a2c4a69f6512bc0b7d4047f6ed4b373de60c095b7b95b1ddfa5a20f94d3e19084c25c353e8ae148f02
164	1	57	\\x01a6f9b0d9d5da396e0f04ad2d35769376dc5a73784c96838e2d5c66151663a880fe52848d7f6e6097c1a29f1cc74106cdc1157db31b510451f0623101d98a0f
165	1	237	\\x5e7c8aa20c653ba576e80b2b5581ef27e0244a8d4ea9c1f1559ec29e641505cb97c665bc542a61bb662051ef80b0c648624b027f79254aaf6d4725b6bff8ab04
166	1	402	\\x0f4bd2d968826cbf3530426ca774ae7d1ecb76a5d1fd548fc4a0b03bad66f6f28830c32b1a12fb609dff26050b84e9d6ed07f60a90ae67215ef06258a5c2130e
167	1	107	\\xf7ecc46d4f324e8b484c588e24fd2821defac2603811b29a7a8dd808bff25b4c7adfcd24ddeaefe0e5bc146e5cda079e51d6c55ad8de8af237527abe58380705
168	1	47	\\xf60e2ae775b4751a0b59051669441a63d987cf6d2cb29f66969782f86f85bd883f1c2781ee25678f45f8a8780daad8ae79a85cfa39166eeeb78cf590a2b6f304
169	1	389	\\xc89b2b1eb5b0327c2a715c4a6dc68235e85b9af569cf7f2b8efdee067dccbe2540e9b9730c121c3c341a84f6efd3027277eac648897918b007d6b5e5ba5c8f08
170	1	296	\\xcb4e7f8bab321beda998bebbc2cd3afe6d7242ad7d3e1447f06722bec02f7cdbef6eb7ff5658db7d155416daadf328baabf13df8b5006a820914144451e4a605
171	1	305	\\x978466d79d8664764882bb4c035dc035d53b2ea0feb31cfe0bc59cf6151eb3a7ea6825698941145d03aa63a317725e4e36d9d7cd0bfd1495e8a56f7179ac0d01
172	1	123	\\x7b4fb82c765a9fc8f88d8aea82f8b3fa1fd99a271d5c0e5eb3614891a19186946dbda18d62d4b8160aac5895d0df7ad983f25857774f6101c3c0ec389e4dcf0a
173	1	228	\\xf71d6a8aa763a613ccf81b207ae71c7f39cecf51503e46229e8138172d1a9f8f044cb35159987800cfeacd048edfb9ea86f7a65824634191a9738f888a841205
174	1	160	\\x965dc04554694c004b88fd74ab0f3f34c2206512d4a0ce2d28ff1e04541c197db257d70e0675578ed0bccac7ddab7e7307efb7d7315a322542017e2338065504
175	1	157	\\xbcb6b67a70a2af1853b5fae11552219c5a3182a4973ddd411ab2e43cf09434d6b44c0f6dc8ce502f965aa13a3dcacfe319ea3044d8fe6fd33b68202bc08b3d01
176	1	282	\\x78e0e902675cfd2cb17846f01863c3f6e6fe16d9690b971cf68ff5d22137c21b61ff46efd5e6d637b762c49d570302744b96e68b808fbf437fc4a5e3b9230f06
177	1	19	\\x3d489d8521e4f081d30eb3031133770c3632327eefbf109e9a28916d6e2e7a9b8f37cb0957728c10ffa7865ce37914bdc7b0094951a3939b10283e7f02ca100a
178	1	182	\\x36d656d4336b8ff893bb9063e348ddda9182f1445e821913fa157c58ef8f0af22cd64f0223abf1ca68ad22856f7749973abe4368681bf7268a27a1d5b0318c0d
179	1	9	\\x86745ff3285bde393272446321f181eafc39f5dafb6f6e3cce0a945ad49b5ab8160a53c0e66475ea4563da90754d732db920cb2b49b1f7e0ae70dce81e266803
180	1	414	\\x0bd5092d3188b81ef3a9650f3af690fb30a9b76ec3564b1dfc4721f82bc78decc1dcbed855e0bf5db38bd26e9a23588b748a83033fcf49e1f1580339ad566201
181	1	238	\\x07dc22993a9962060815fae96502b36d25de970f6130a0f7e3eafce48604f7dcbd307ec131986b6e5627243bb586e40136a39157589b9f2506231dc3ddc7b805
182	1	35	\\x7c18f10e9028f8fba43f944a3a639cdc11131c99e82cf40fd65bc8d4186f0edc5fb7cc1f2ac3c3fc91887f6589dc5336dfa91532fb73bb1f4b9c24b4ce4cdc0e
183	1	78	\\x44a05d20a5dafec24b7c379d9440fde39b952543ab7630880e99a9ec8ed32cfde0ad979495a8e0474a3459fc351596a7eaae4af537da63aacd3c20531d7be200
184	1	163	\\x124847932c64ab0ca2c1870fdf1f0493d5de155379356963ee4ed6100e4f6770581553ff86c51d419d4125746c4eea201129567ef9a07611f58a0bb84ed5320e
185	1	81	\\x5f1df7b3a623f323cf17e16e58c9ad38c12cb96f370e5ca1a7c7f12a3c7d4b1c6e64bd5acbc1cb89fb128c9e1b4da80ce551aaae1fc23fdb3ccfb9901dd3c907
186	1	374	\\xd340e9cdda9ff3a663d6058403448e5ff87cfceb1de63da5f6394d0fd641aefd371716b026a218b978f05ac010891bb7a109bda465bac457ea205fa85e2dd805
187	1	162	\\x3f304e476912ce1abb02fdb55b658da68afef7181228735e1a30bfe9c39a464dbe8828a493421a7e8c0c374477c8e3beecd2915dcdc1186d64488c02650b3b02
188	1	424	\\xbf48a898f8b0ee2096b389357933568f226e1e45edce72229c9647ef3615dad1bcb8cc2ed9d393d5c394db33b1b740981655aeee7a4ea737ade0713148379c09
189	1	79	\\x4e64b05f8bc0593f388bfca9681cf93eba3b108f80c8ca53dbe3b8c2f0acc559bbc3139635486c4e67d3dcaae816fcf58c6c06a06078145a1b30bed2119e090e
190	1	199	\\xdc8e8a7f683793127d16fec591d1e123fc8768f1ebd1a3ea8e597a7240282457d76cbe8a383ec292b56f044104d3e847070fdbab52d27fbb622a531b17943704
191	1	239	\\x2b41c8f6ef63a70c7971ba2b099de37a3898ba49962d22a4c729211df6a677a6987ca8cd897aa7e4c2d10673ef8a798818248b8f5fc184524e5881ed1806ee08
192	1	324	\\x28736c49b9d790ca4d36e651171f05f92ea83abecd23636079fd4a0f90070120905124fd8614a5a82b08917cb91222d5efdc92c407fb1116fba4c0f7a65a9b0d
193	1	292	\\x99fee2db5f0f0ddceec5a4d33077747de33ad9952b4a6ca7612b4ef2aa001e7b0b4fed9f4cd85095c9537dd82bdc1833617479f96a9784f2d5bedf1e0b39f607
194	1	151	\\x9110b8749809e40ff27d648d87d7c12dbc36f21cd2b1f18aa63dd9c276332921891c5ae2403837931e3df3de4999655434a262d509fb118110947c5fbcf23201
195	1	188	\\x9f3bf49e3bff630da1b4dd6d71904aaab223dabd2076820cdee1e27a0adff9233887ec52a5b5f3718f870d1cb5c39007042a8984a8b982d5bef569bc9c6c3d00
196	1	98	\\xb7bd5d07ff419dc7b189ab5a202890fb94bb461c1add47fc4457d88f8ee03b579fceffb6304915e6d99db869f3ce798807caa0296746384f19b42b637eeee408
197	1	114	\\x9386f5a01ce7e5d346c11eb4d536f16678d6feae5fe96ef50b38f977177ad05527129b91659e0f9eb8e681150050b845d46c15446e016f2dfff81cc94e9ab80a
198	1	294	\\x7013af8166e3d4724e121d51d5385ab7c873108b74ea1c5f8962c227cdbea72b222781bfbeaa97052c60b6a2af132188e504c6c6aa155d34b6779b6193fbf30f
199	1	191	\\xf243322e99c8e9b1b7a001b2729a667a5ac2799f8a10865c8996409d27d9fe6e8b9e70fe5a96791e6e96d812b157f4f65c89c051b45f7ba4d39337f796a3120a
200	1	11	\\x339c711d773cf3c36ce93f8d6114cda2a03fb25b3ab8b295b0c5984620c5eaaaa6c2fa407524a8f2f8435d96be58cf090f3c78e84332ea25d603de8b7e00e203
201	1	288	\\x1f944c80b45fd524ec1fbd5de68f79288d933bb6132f5274bc8439bdc3e48277e00f99e751a2ea835d731e2f4e394bf27e0815f0897b74a6596b81f7a7054e01
202	1	394	\\xf9cbe26d3074aac98879d3c6117e944bc4824fbc431c068ca05ff616415bc298d0760ec31ffb50180a7277627ac16628d9efeaf5378e122224664d308335dd02
203	1	40	\\x116b9bc8aee4ab8fae27b8ff3ce45f495e24ccd9edc672aa454f41f5757167151c0f683a6421269c4e5584d443c685991411f2866022ad1273cc0422b5291d02
204	1	355	\\x72731cf1ae9d6cf97da2a93ae0c7c3d96b6f576674da7a0a83bb4e967c372a889684863409d25b59e01cb2d0015e809be0cd695b427a529a2ca7a5f161553b08
205	1	173	\\xc111b4418679762c2aa6765a9374e68aedea97e92c08fb3b70ba327174ecaf3c37ddef0c1ef55de0cc87b0329cb884cdd627a73fc164dec94dbc3b2cbaac3800
206	1	418	\\xb58b835d10b249a0fab283b92648b59ecf9bb9abb1ae107b7dfea758040c71a77c4a7fbd6d5a6143585b59e0615851a7d4925168e87cb170b70838f283b76b08
207	1	225	\\x4f358e851e3513285ec54061f11f9b140ac3418a33a7ebcc8fa3b51652bbb975d1c55932874df59a07098236548190bce4706929320d7b0b4a81ccd278da9d08
208	1	269	\\xb90235dd4ad158b4de9d80ef29719db81604e63c9a44d3d92bdde502f3a66a24fe8c28ce3fad2083d781c1f8769297df0292271e03bd91c6dd8dfa47431ac601
209	1	198	\\x49d8586205aa41009c08938145384744d480264d8edd1747fc637fd12a62b1d6bf6d4a98e2417f23a3f39fab4c6f6e5eec924f946ecc41adbc73c4d2e1000c0d
210	1	73	\\x932c2b2d251ebe11cb4bc7f178c9a8d957aaf81ae28335f8e0ec6a25eadf840bbc665585209aad6549deacd4a8a3164763b68b646cedac8fb2971669247f6803
211	1	356	\\xf3e45227fc46f9f17c83fb60399427c3044ac80ac94ef2c705e1deb7ea46def93a92b4cb5fc0db31873a0f096fb4f508baba42a10015b914bce54edb71c69d04
212	1	390	\\x152ecd9501840267acf034abac381e191bb1545d565eb35765a9bd37b42a6325886244d40e4da3228b314ebea6cd91edb6f16a0f056536555d4fedd8cc9edb08
213	1	318	\\x4775177b5a1530a1b51d9be2a92ae95944512d371bcdce7c81d4c4e9c2706fb4240ae6e6fc34318d53e375846c48b4ecff8db9d7aac3055684157007bddd250b
214	1	52	\\x5c06c8aff0a7f5168d2f6ebf51354250c7f9a0042059309af1b387d8f8d7633fa3d7fec6101af80b292d3a42ec836317bdd26617fba109ee5983d96915fc850c
215	1	360	\\x19e8fb5694edf1c0f646b327d37026d2971dea256e5692be525fb75460861f3713e216bca31fe1837ce7cc5a585a5af6c141c12e49513685e275663b523f4405
216	1	372	\\x364e75f09c02b98f7df100f216e0ab337007c3c05c379850df31bef1f54c843007c15097a8e987a853f7765a318a3b27dddf4674dde0829df6956875dcacdd08
217	1	396	\\xa55dbb4787a3056cac79557ad343ae9ea174866219f4b61b6dd02483bc32e61991b5978c57835558282e9bd79407b46c3bc6ce84d6d7364119f83ca1a0971107
218	1	332	\\xcae445df481b69ef7c7fede28e5145ec1e78078051d5641f01852564b20c0f92e5c55b26359b4b433625d43bf1342d15f5c253dc310c1a4314c16f1bcdff3a09
219	1	186	\\x0ec77e09e7be39711af9a77471583e09b14e95d6f856f605613fbea8f088e5ae6204405bd9a08b7c9eae57e0a652fb30f0e3aec9f3b15f20b387a0049f9da90a
220	1	16	\\xf4f2d64315b086a04e6bbddd7901f789d1783b766235d78cbf6b1d47874b94a1d8c97f59b42702c0a366d9edc5a30dbceea1f3d4ebaf2034bc808b1be7f8be04
221	1	243	\\xda4af9b6a0671640ccf2b9e353c49ad07c632fe46fe81ebe401c6648f783f8dceb04054465b413228dcd95826d1df292fdcddb11e6860b7dbd9f26696adf2c01
222	1	260	\\xbb565f7902b1518496fbdc7a37ae73c0d9563de56a6ef520a7a311e64c59b20165751c05f71e5da6ea4c8ffcd6921d8a356d3c6acc0954ce78ea8a7d1d223103
223	1	261	\\x83da6c0e0b99f6737d2a5161981b4f0a48b44b2fb14de7df2012c259114f3cecd1de085611d5ebc36ef9b677b16b3ae495a024d1aded43ed39337e0729a2180d
224	1	214	\\xc75903f84d919a551c9f4851b5ed69df6e9224a04eee77d8eddc949325654b6c4ef69949dce72ec70f1ef2ea4e32a9a022d5ba15b62414f0603df8e9d3c4f302
225	1	316	\\x5dad0bb867fb25e4fab19a7129c6b704cf50df6f6ca484ec1b76a10c4baa4c722db5c5c21269e47ae0266dbc3a91642030b93fb21e52e0968b14a24d18d84d01
226	1	135	\\xac83c272e2c3a1278fa7ba48a2d8b5a89330b21d82a7b192e5e2e735d5950b27b069aa122ca4330002aaec1e3e19ff0e2d3c6328d8e987b6fd5835bcf9dc8303
227	1	143	\\x6d82e7b2e21ee329d2c01f95179da0e0e3241d7f43f4c3266e51badaf920b08e915f7b7b470d18f16bfa91e6f724cb06eda2080fec57f7e74cfbb99f68d74c00
228	1	93	\\x3bf12f9a5669d70b061e4678c0e487b7bfb60f0c8552be7a813ff0a101b8c3f6029980c4fdbdd24d5e0d1c1096397f715a4bd260e88de18e388b2c2e7f788c08
229	1	273	\\x3720f39db0b68e974d9ccec4998b3e26b521fcc5dc88dbfcaa94a6f24006780c467ebe6c87c4ea66a942afb0ac28a13082e54f69ac5eb638fc62311347ab4b08
230	1	340	\\x4522247438f3c6454e569be7f0b4f073b5b7800245f33fe029a79cf5db1f9f27280906441134febbd875558c4a9d08b48c24f3e365302d6bea203e2841d74e06
231	1	251	\\x7478d68791f1129f29d422be135ea4999af5a97ddff8ea38c3d560d14336a738455cf5b9f6e8ae6c4e080ea239c8756e404327852e577262239450766589db06
232	1	70	\\x7051a47b19061296252fe9bda67c33c041dee583ff57462dbf15d2df9edd3f117e9154e6a6e9aa85267d8b9c6541f31af157beb78428286bb500b65a93b49508
233	1	204	\\xb1949ce2abf48e71f9a661ab3dd70f72e104a9ba81cd9bb34541613980681115aba4e80608c57904e0b8873c61cc9eafd9e9e98f7417a431caeb451961f35201
234	1	369	\\xd910edd74b217b0d1a019b7feee52c9ce0283f7f0540525624da6bfcddc281914f3f32bd341c79e66d81d1779a9fcb3169d202a1e4723da6c4e353a1892e680b
235	1	91	\\x797ca4d58f82007eea96496cc9c40c18daf95ecac785dc65413ae6cd07fb0e0e685b004b53d13957f516f7a2bd76ce3a317fcf4e6f82981dbb268d3256e93a02
236	1	10	\\x1c69c6c54406de2d3d8b4d39ff0763b6d02e950c292cbbef4d595a591f5b8345e40f37557ba026e23ca652a08564209418d1f9d6b8488efb6bfe1bcd479dc90f
237	1	46	\\x7b4fe84403b7e2e04cf19f64008581c217a1cc9193f83532324ef3f2080c746199bbac62a4edc05cf42fb929a0266f25f6743134337583923e4f394f05bac707
238	1	342	\\xe5f469242bf8cb41d112f9e2e3d59ddf82f501214bc1d0b368f2b15cf10c05b78433b0d75aaa41eb891d86812634e09963bbfdcfb6ab0227e9df85dce9ecd60b
239	1	167	\\x0af5c6a281180624c03aaedc81652a35c5cbe179a12090cf9e1d4ebb4250b7abf4c93cff88409bd190b04a810517f21584125bf0fbb8569166f2872919b27b00
240	1	56	\\xe5e782a10460b079d3735d1742603bb65dbdce678233f711d3927498fbd8036df7b2591a5566a41ab8cf28101563403b0ccf41b166402115e2a0f7e0164fcf0c
241	1	276	\\xc3c656dd8169c7b68209a337007c70f9df2b4da4a8fb8664032e6ac906a350617067710c1434e79ef46fb486960a93e76a7322ccab940c5011352b94a17bdc02
242	1	5	\\x8fddb067aba87bf15348cd2cfccb4a1908c8ad807dad45fb48a2910f570e433a10eee6d71c2972723c0e86fc7f5858e90f7fd4271f176103b84a987ba8c8320c
243	1	166	\\x067383d3db2bccc2a9a5bbe9caa07494961da80e36e6a2b7fa284b859c3357c7a03554b9b04c927f1be835a917abb594457963c35f3a73cb6413d7ef33152503
244	1	111	\\xc89fd138fbcf106c8cc93ff0dfd1d29e6586e9fbe1b0bf63f122655b0a49669f94c548ad0ef7675877bc91cbd5f99d1067299d7fda31f81aed5b94e06f3da602
245	1	13	\\x8ffcee53bcf2b32897435fb7ad5469ca86cf4bc84f53c43728972fccdfaf4cf6dd06a3742c2ecc1ef2dc7c8b97b52384b87818c3909afa35896ca73c8d83f809
246	1	95	\\xc5ddb6da063c3c7b10532f0cad97176f3dd90adb5d4f3748389b5fd633dec68264e55f82f3f0266d140cc0fd94181b02b4cb73b204ee8631ed21112c462a9705
247	1	220	\\x6ca0b84168fe343ca2408da1b369d7aa6976af850e11c58b1e3c21b7a9f68bf57d5284c55d9cbbd9363972a39f87c6c01337734be2b99eb8ab68d594b4659308
248	1	299	\\x7ce6e232c612019655f19ad7bfb8326df2377d31079479304721c970022bb2eb246029737732c4f52c32e05114bef22276d5eebb5d46f3b5e8923fe5d7d92107
249	1	284	\\x8cd4f3165f42ead8858e1497f502dfbac3edfd9968273df4368400f7db7434e094e5ad61dff02be7124ba0fd95966591e252726219bd0134f34536fec47a6100
250	1	74	\\x7d8445d0f2686a21f75273dd4e15386d0df3a12b8ff3ccd29b538016cd3d8d9309a576e781c9c5dc631637e7406a27c67806162ba7ba97fdad1a5a3556a8560f
251	1	118	\\xf7503d80445cae42eefb33fe7aa03d218853df116e2badbd1b5ee3021e098ede551bdaaac43d2525685f6204dce97185c773cbeb1db4b7a51d9d40c04ed5cf08
252	1	341	\\x05c59ee721b9715cfa2dec66cdec1420e1ef307da26280f5b362096a8370abbe52d9c3ebd2be8a5a2d8ca3cc16ff8759711b8aa2dcca8a8344ff402bc6dfa204
253	1	23	\\xf862d394d0fa6efda37dbd9a6a35100e5360ef07f9dfa37bb607c9cc6fa976c1f7bcb6bfd7f8f4afb22acb97900996b177595ea08267d04e91fd926602a6090d
254	1	376	\\xaf6bdcbc71c7bb3dbd8ac1c110cbf217cc04c747e50f5c311c1cf6432cca7c46544933aa2069d673d84e8ad3cf9433becc541a4d99c37025f8bd7136ed14e60b
255	1	159	\\x73ef253ba1f73a1b89571c5343ae299f22751c7d6c55add9961c0a1f48c911a33f90e4d013fe5bd65b1af28da412ec6b06f0c5dd12d8836e1432eab74286ce0d
256	1	322	\\x65da82f84da7ba83c0e3269cc1949ce66096a88213d36270f530634e82a08d0abe8db5f46e9677c3cefaf1ca2ddb89ec5cea43980f377ffa6953215b7f19c303
257	1	77	\\xe8f53281e94c66caaad3b81210a464c4fa03ac719f36b96f1e784a7ad1da2bbdbbd4d8e7fedb0945158280a0ae01014cf096f372f67d67d02091e00a0910c302
258	1	421	\\x53316559c699519638b259c781e338bb9e77339a61c2dbb322b72561513932728dfafd679669c3375fc4673209ea7ac8f9a17e6241bc2b21d4dec3a5d1d42900
259	1	274	\\xfd39794fca9d7c266b6a260856562640af1194007181be2c9bb3488a2b5950ad03fbf79559110ce9c6983e7164f646ff6d4c6520090361dd863e9a92d3d7d10e
260	1	330	\\xa3b4297494c20241ba25cf907af66bedc9f7d94ee0b42d851fb6b8e26d9b6237acc6919181777c23b39de4baf82256087b4ac69a204a57f042f8f2207e31c00f
261	1	253	\\xf861d48ed4c413330b6a1994a1f83371c82d02b8410c550aa86b202ff66511baccb818bb9f0d31007cdbb5b4f36adb05d0149ea70ae01ee17873f4d82e891504
262	1	161	\\x5bdf1d040981fcc1956c81db6cb5b651b4ff33f2254eb6d72b838872703410411b995cc5367f7ec6b3d6b453531957857c261793b2914634a765abdf7595640c
263	1	419	\\x32e33e094b0271076bddb9323250a33467ab5c593942e4b58c58908060658ffd224b745383b68fa46e34b3fd4619c0548e1949bfe57dc7adb796741b60bd0700
264	1	138	\\xa3bfae08ecda44178778467f1f33ceace92f45385bc63fe5e61662bab08c45f14273a2da423255fde9cc81a5f3132b8b2fd229f31552921ae88e29f62657f50f
265	1	69	\\x910c0fcbda6789941f6048b6c52e60569694c92a20c9da1f1983aab9550fb0604f128b9e6ecc0ad74f3d42f8e58b64c5f592b905681bf2784ce62387d7e80306
266	1	129	\\x5835cd6f592dcc34f1f52b617982e858820fb7984d682c39868af318b2dc4387c5ecfe3b001c38954928225170a185ec603c79e6bc398ae4f4cdecce01a85607
267	1	412	\\x6319b6148ce9734e88df0155f5a791231998836d7cc1db8864a69f871a5cc69c3af7905898e3af35ec90a9cfb1dea77bc89b6776a2d70bd7a24c6e92f0fced0f
268	1	409	\\x053ed5e8d3bca31cd714651a2952f0a4899871f1d286534c209e7e9112a97f554712a432e6823f6e1dfd75f871fde17dbd4175f2a649a949275eb1b9a0c1f40e
269	1	378	\\x72d52b1d4af6db6b9b65735e87f1bd90566aba136a538b077cedff6a9b410c0001ed668b2ba139c192e5a3caae988ed4ddc2dcba5d5237fb18bcfa1b75acbb0b
270	1	337	\\xafd048e1995283442da8665b1d045ec388fb77a43e3b401cdf2a04e752307312f72061f66f2aca00f17301bbd1c28e6594ca3fc801b4ca5a36fcd8db5daf2f0b
271	1	179	\\x2594abd1aad897322e13074c3b3970e1f9346dc56557eade338fe7ab314af1ac1a359c5ee3ab70c30c02487551d29e57fabac4f9558084ffb995d299c22e060f
272	1	319	\\x3c2d1e5161ebbaa35b44317d4fd7aeb6f93bd57e5a910986973e5df26ab35b3cc2844f88ef6c3a1a8673010b986e98d0d97d5ddd0c621c64872b268e08b79a04
273	1	233	\\xe4ea1b54060e1b7a8483ffacceefc5348ad2ca06d838eb2e7e78931657866ac07bde89862f902199ad101b3314b457243f75fd870072c99739b19df447d84503
274	1	174	\\x6d3c59675fc51ea0436badcebd676c1809302fce29fc542013d758ec1c134a21e886c1799e3679593986e3e7aa4bfb4b5b78821e76d02774343b5ac9f6d0a805
275	1	30	\\x3614ffa49b3d9160a2bc17b89e92a67a6e9ca5f26387539e0ef55d36321800bd8dd4c4982fc8c4c8dfd63b3497dd2ed314adfbe731fbb2b1ac68106fb030aa05
276	1	293	\\xbe026d5d1333d8ef6cc30c48f005e73d2927e6e31a9323c5874339ee4e24d0f4d7bcc896770ceb4c60d31e9f32da1deb805e410a060886838b32d0748147080a
277	1	106	\\x5110479d45c0611681d836e087632bb9b6b9adfb25601a033bf26853a905f727b12450167b0cb4d426a1debe194e187f2f5fc53b42ff3f7ae19504eed00ecd05
278	1	408	\\x0c1423b36f35f20e42bbff83497690231ba5441a1c72b5636865a1afaf6a2e616d022e00da247403ece1233bd7eb58505cc3115d56e7ba3e807f545ae2054008
279	1	217	\\xd3ec6d738cb8f5875ca56e35d6685566f1f234b970ce0744ff73918bfdd13dd7c36f2a6a80732235d5f4dd5a9edd306ff11f7dce1b629af867ddfc9624a40703
280	1	404	\\x3f17be0887a82ff1a222e590cbd2cd09604c92d4bfaa28fd69016379ab7eca223563b1dc2af5bf5d9618a60b58ec38536dc6f71770d43fb498b9bf5fc0fcf40b
281	1	223	\\x1ebb0b5a48d31ecc37be46e4b28343f3c68a579d64edd8eacabfa90a504c2527875b593c32959911277bd7536137822eb1fce92af289306e8abe827275fc090a
282	1	365	\\x0c937644b80d4869dd0f1196da1f67f56cea944fd3fa377c0b5e07139cb92101a3ec4b70cafc04b4cf2ba5119b186acabdd7933d71668d5da8e0e3adfc0cb708
283	1	383	\\x222eab9297847da0aaf285f13fe98b7227aeb971e692d1aa97b761ce2815a675d35c1d6ff72effe844023cda735c6ed22620d405b8bb868c2e309a1b348cd702
284	1	343	\\xd37a6500fc90855d93b4599e966ae8a2c527ec2b20361e1b2e8a5c2316beedde042470de2140481647ef34d8b588c071337c505c19bdcfbda09e53004bb3420c
285	1	315	\\x119c04f53dd4e50f5ab20e0f6bb4bcc30b1d7a5150c8d683dfe6f707b1641a5bfc19fb29a60ee65024b4d2cf0d25a8343d6fbacf13872f7e15f1c0f170436009
286	1	183	\\x6ed8b7fdb4acaccf0de53ecd53c165a4e27834ca184b172a0e519a3a19e28c8637bfe675f2429bca1fb64f16a46128d2adc6c2111e29f238ebd07b1fd9aad70c
287	1	346	\\x3bbcf284a84516eae50117648f5b38834d1e5780b1cb092353e97e3ec2fbafdf027e83d3e0d3690059cbfc71b79c21f67709f4f16d804b7593ce68f1ead97d01
288	1	350	\\x96653bbf80397653bbf891546ea78f6f0c02c66d5b8724c2987f0e1d2736a9bdbfe4643f4e03a32637d1624a7ee96eab9c00e1465924c95510e418e798a1b209
289	1	331	\\x432df4fcb41fe2fc13d9082ec1b36cfed879168f595374c94d154e3861fcc8a7da81529c8aa2f6be3634397144fe501ec3447739bfc7793771c9e9ba5bff390e
290	1	156	\\x6a2a6915c2069b5f681bfebccee580481246ffd66052eef58ccad2b72e0de02a85b2175436c8bb670b3cc487adf95bea1958d62386b313c2166ec455cbb18a09
291	1	218	\\xab52014f0e4f701e2441736b81487f19f45f9e2c3a6323102c76102ee96108290e5f48763a4d0bf5544e656d0fb2ee4fd5a732239b0dfab80471c8bc54029e0a
292	1	240	\\x1331cf77b4bbdb1176217d5dc46f25db6c082efb5bd85d5dd86333f65724e4a29791ca718ed2cf192b17763798b1621e9e4bb112f377bffc0bb6223e6b4f730a
293	1	80	\\xb822d30e001b4ed41a867ca6c8b2d8b3c8d4a3b7216237a0de73b53a10a95d8b4ecde2d368ab4a40dbfee2dece82231ba4d5f279242b2e75cc6c74be2ca84c0d
294	1	49	\\x0cfb283f02853243e00f284afdcfcf88e8110005a190acdfe66b14fc52d403b395e68129294f547950c9edfac2c31e5d832afaefbfaa27598e4603517c79c504
295	1	110	\\xc333eff57784e6a253ca5aad0d92c7e81356156ac763079385cbf4fa06213a2efb18f7b2b8cbb96f99a3b78cccec39acf6f1e8047a9e461ca525feeb935e1e0d
296	1	301	\\x1b43facecf3a5d6e5d0b77584262d0a95b22826044a2ad2cb6e59f28de0982be7e827e0a623832a0ee90e093383ab95a73511641f57999a834857faf8de1fe06
297	1	2	\\xc6836bad5eb09fd429dfe0d3f9b536327b81c560659242b53e0450d4cfc8e0d130425613ba5e858ba7ab7f162b8fdc8832abec41d251f39edfba3b97d7bcf909
298	1	172	\\xb9450f1c7aa57cbc31b1888bd2636f93cb73405bba7de589fad8207bfccb7074a10afbb1c54889b269f94ee3fb13845c0e9206b076a959fcd33106d96318470b
299	1	392	\\x986278e5152fb8e5b2a7372a8975cccbf4b2c8fd6a8035aa9402b1db537594d314c3586eda4263b412876dee54489834d68d643588b93b98cf492fc82b7dac04
300	1	364	\\x4e577a27ebe3c88123089800601c4365302fecf68d4c0fdd0b95b186caf0d993a44bf29b325a7fe2599e1740dcff80f65ea3014fa66fd42ec699cf147f029601
301	1	117	\\xf6f025f03c0b7aa59efd0a83668db9f2c70c511e72da16fc6ae13b9d0898ef94290403d81be3c95f8b2c39422aebfe39833a99a63354615da797234ffe28a608
302	1	285	\\x0ceb9a3038624ac4c3f0d67fd70cb440f142fe0e03f09a3e4162f29f3b80a8ee52bdb2b732f5c3251b2197f1ca85b5033a8c9f6a82d6c1480f171b3721197100
303	1	336	\\x9dfe9c1d41fd193b286aa905484edfc04944f07232844cd7d8c57165d5b14d8cb65860a07855b6346d47135d3dbb145d352d29dc8f181426c038ec0fade04601
304	1	44	\\x2dacba91ca767eeacbb5beb53f406a0c7209f5e1070901dc1cbaea25081f24b25c8bc6abc5fe3f1b75c7b8d3869fc3b7693bd53601b4f5fc508733f7e8051d05
305	1	422	\\x3128f032bba65a98b214250ba7a407049e3d9c8d18f7dc506e8d669d0db24d70c20d980399c858eb8e6d235540ddd3749e491dbfab2d9a92da5065dbee004505
306	1	209	\\x09d65bc752d8610fd30ab77af6309ec5ea4e34cfb56ed588a44efeab44157bfe2d466fc703dfb30ab55b6f0654a4c129d40a01d6da92e3ee695f11576f2eb907
307	1	42	\\xdd2235db856b61fb7307bcce70a24ab0e2edd1b90526ad5afe4315645bcb48c5ac6a4dd5935939ba47f8d7a3783cfe94e45f6ee0dd4959b45046b263f433a905
308	1	267	\\x0a713fa0d94707ae9a290cfbfbd2f08bb864ec78c4d075b367cf49f75729802416ff47c07d786361970ef4ec6e36d166255b573b2b483676e7ee550c0eca8b00
309	1	306	\\x91dc5f570447dfd5b2ff287831b6d14b3eee170f0c39ba4b7a7530805fa3f0835a6e2995635139486fd487ddb4274d89f4f8bc4d8b037f4967373923c3220f0c
310	1	357	\\xa7ebbe9d7449ab4d0830ee752d4e1beea395e338c3f6b9524fe6c96dd7b9e6132bddf309c5afa39009edd6f65339299c0d3a168c561c5ea784280bdc7abb1e0e
311	1	154	\\x3cf06e275a4bb702b0c05b3cf90248610bce1c754ed5c0e339b120d09d29addd343e088fc5a78acf4903e044d3fa8ab4816b087c5cb644d46fa0f014235cb70a
312	1	302	\\x14287591ebca6070f56cd90c3e6434ad87c10e380888c8c728a6dc08d54ff2a09cce8370d843cfeebd9db4d3f36522bc2c83e890dfa41e5d3d0c3cebcdd0c302
313	1	399	\\x4937bb9a6b5bab9c160d7bc24b48196fb706cfc9bd8b40abe298100d138fed2dc91a946cd01ac78812a0763c83ed7e7066c4ab81a0b2cc4f0d1393dc72cfb60b
314	1	304	\\x4d8944759b0b52be156e9c66669a90d9639085f61e712abe0efb51ce494a6cd1813947b1ad56b677e608995b5757f7dbd649e2e9d4f2ca61852401b12d57660e
315	1	22	\\x7bad2e8aff1f35f125db612437612b806ae8d1d0ee15396c207251c933d7f9d64574697296e48a344e1055f54dbf782b89e12a97a475f949b546aecebf9c9801
316	1	168	\\xb36619bee0adb7d8a1e5433927f3d18cc0ef467dc24618585ff349592eb66770b2ccf6e85c3162e87bce6b2d3cdf6000db645307da7c8d2272f12b04ed00f601
317	1	391	\\x6a504f6a859f0dd05f5c633444c744b5e9ec0ff4f40447867622c464db1ee81add8553eeeb7c94d19f45cc15879feb4d03345ab657e749cec13bd64e25683700
318	1	61	\\xf87db0c4191b9344b334880062f48ad1a7732489b8fc15ced71efb0d1cf9d8167d2d8c8664e7bb4e3f8138099f70e1200ddf73aa8ca52d3ba137feb88d872e0d
319	1	227	\\x1ed6a189b5c2526b45edf4dc97b5f8636f6674b9d6486bfdde763bdd053836ccb45547b341249d943c58c774fffde8d02bc458cada9d1e8a4d353ed5f241520d
320	1	14	\\x478f95be2243816b6732fa2a1af14cb47732d38fe93037c00629724d35f34ef5e45055a4ef327db3daebf24fdbee0d10fa47cce7d9bfa2405406899dfbfd5203
321	1	262	\\x12968868ca3398ddeb3d6a85a386b21ff5f5c3943d8695e1a8f4d123475099f5667a557a270e3db9291dc770f113f348918f7acfd2830520c9e2f59f73f2a40a
322	1	67	\\x533ba2e1cae0f903de7165e9fa846d9d1c5d45f6f4979ffded5b83093f21e22c400a9e161e85436dd3372588a3817ff42fdfdfa2cc731d11a7dc8c6d61850903
323	1	75	\\xa5579f95441050a4deb7ccce051ae0b02ff9a8aa55a56edb1d6734e914c413109ee744087bbf1f5902c1a86856b177aa035525152b444b2ea238ef1721e5e806
324	1	58	\\xb8840258d0a45f6603a9afdc823cdfca19cab4fbb6357c7963bf042e321dcfae98c4aae7257ae2abfb85d4bf4891a224e5b063ab62941ac6936668ab9dc95208
325	1	86	\\xe61e717a839b0c69917ab43ce058675a30e61147669769b6369c87955325d7e6417aa559f36a1eac669c9b60cb8034e1b3c37d2e9a48277af5b5a5fedeae8b09
326	1	265	\\x63a7a54e95b6c12c2841098964004cb3cfff8671a1991e1f5de4ffc62c50f12a26b7ca7584fc1292ef4fee6d86a9959c1981725bb9f0b62d3947ed2dfb3d7e0a
327	1	140	\\x6178414218cf9a0159c176a7c32ad836862f5b1064f0d82a6c03eeb6956f72dc3befce04ede1722902f3047be10b706f4231a640c5319543809b330a23210c05
328	1	99	\\x41579a7f8f0d73d62fc4fc312c205c73962341c0a9e76473ff354fc0dc9d94daa2385803c4516ce40d7b10a45db31dee65d761398554f2bae2a4ab1275e39f07
329	1	153	\\x1192757c398e5187e8343733a7ba0a0928b1e556e5cf002259476fd9b928b46ad2f3c49b2832aa62d41bc755abe05fbf9e73e530c44e13cbcf88b8ff47cd200e
330	1	310	\\xf150a529c660e200da3fe67729249f3f6b2363f88d44ae0ecf76fa0ee3c95e2d3220c02a682abf84a6e711a193902d4d17289dd1b633803c491db2de509ecf0a
331	1	393	\\x6e4dbd9b6261af779933e4a6ee43e98c563ae18ca4e927636a0bf3769a663371fbf09cb067aa086834a26d2ab2c0d643ea48cbf132a3c7eb184c9a6777938007
332	1	124	\\xcc38d3a0d00cebc21c8590517f301570a563fc2ae4446ced1f715ce7e88f9adcb5ed37767e3ae0de1279dec432993f5f42ee74a7fd8bb9e7823e2d4e15e7be0d
333	1	55	\\x8219223020486ef9d5b27e5072823b693c2881656428c37d13a78a32f4a86af9fc52bb54d204c465666e8f4d2f4b4881e407019f38860e88504ab962433a3400
334	1	51	\\x8d8c8560246034836f4aad3700614feb42816966f99a15e39919daf163089be24b520efeb7534eae201f234139626269993abf1e19b4876d7ea820c1d6748800
335	1	149	\\xa555cdbc56c784c8b99cd2ea755b50bb803a8bd3bcb514fc998abf8c2e0413dd3d003b0d3f5faf41306397ddfc7e3b49a73c225e47ab4938d0e5b56766351202
336	1	400	\\xa8e4fa359dc76c6d514045778cea5e325bee9233c6318d20353a6c73ff9ca44b3767228ef81666786e0cd2354c7ac1510eba727abefb16817ae32cf637bda008
337	1	132	\\xfcce346778cef383692665b57490afb3550b33c6d042c9afbfe4dfcf52cfcf84ac4dba379e2c3a3adf26700eef5b4e5f2579f42b77c6e8bfe91e220fe287260f
338	1	66	\\xde6596ce7fbb734b0c974410c70b4c78f812a922fef2706f3080acfd5ef047e3552df715244ab8e41d37ec255b9c4d3aeddd1640820eef81883385b77c46270c
339	1	312	\\x29449480699d9a6524e824fd06d28a07ab996f10b87d125321362b39ae4fddb975b62aec3318c7ed9f7b376a870aeb8d8d93dacef0ab1fd3e3d4c1ba2f745904
340	1	248	\\x6a597a799c909c43b45dbf1b9df632f6cd37feebe355c27180d767eb322b432dcf5bff189d8fa05c949ad3a65c2cb9128eaa6ee471ac3c3f0829f822eb558204
341	1	36	\\x84934a89d1a3dc0ba9c9c208a6e105558ad7f949cc3f4559e6b7691581617b6e11011e206fa4580a976f2ff1f88baf57b0b229cd50aa5585be317ec5ac03c801
342	1	18	\\x106e49437e103bd07b62cd004f8129c972291732f0f352c8fee6e53a829b81cee9cd35691637d3320c041b28f0483ec6d2e1da098897206c44755c050e1a480a
343	1	145	\\x1a041cf84f1d498d0df79e8da663d6aec415d037f60ebc43aa496dc1607e0bcfbe1840dcf870b1981d6e7959049f34fa55b5e2d90f91cde8cc33ccece4535405
344	1	231	\\x4f8aabac4aaac767518aa2c462cfaf9005d566e59a1bc8641aabbd7254dadb17d1087e9375f884dde8aa0f6aba5cbf07cb59117566f02f9de2553bba97ffa20a
345	1	224	\\xfde74af8b4c3d41b31635ed07d0323aaf34fa7da00b8b1b5644c7d93f359470a69249f46d98a947242b01f67f9ab3fe0849ccb60ceb37c3621c00371a7d98c08
346	1	90	\\xdd94e0b1053d20ba54dbec8908e3755fa70aa32125949985c6d66d8f682fa740ec22e29632232c9ee549e9251a24d2e526aaa50694a85fc154b4f6f694ae5104
347	1	277	\\x276e21f3a1b7ed3711d0026def8b59fa3754161471626c07a60dc34f044154f8748310b1809bd5ddd4a82a1e39f33959c36a28df9371715850928ed5fcdf9e0b
348	1	303	\\x4fbb1351aaac3e54a379aa0ce8cb04445c326ca57e0f1af86400e05bfcfbb16642800dcb87769352d4360743215d31579540963dc0f3992313e21a62969bcf01
349	1	416	\\x5b4e6ed2d1eff8cc7310eedd9d8da321a34f0560cd36221900be9671c8734dace64adbc85c13b1128365e1762d102e2daeadc2234e4b7ccc8be54b1c113ab80e
350	1	88	\\x253ed0f165cc8a5d2973b631ea7c1d5b6465c13003e91cf9e46308ea8a419ac3485e0e97489266ceec599f54245011d9b0fdbd20f0aae6000884c53334d1d40b
351	1	103	\\x07fe68c384d23c4ef4c4a91dada842df3c22126e1769d233e941b45c2288e43b15d87ba5a2c4c75579df70496f0a45ca561fd525ca8c0883961c7d2b59433100
352	1	287	\\x98d0fa9ca68b3a35b3aea0cebe9b0789c6292dd3f7c99b3c2d252592ce56cd3f14dd98c7650bb93712cf93a5fb21913e2456173aec89f3e3e8291c8649d0ab07
353	1	100	\\xfc190130c9ffa096b5813d2f6664e47b41d1f416e31f09829aea9adc727c178de31095248a16138f40ba3256b590700a4198f7a1bea7f292e064637dae0deb07
354	1	297	\\x75256ec6fa054dcff5d727dcbfabade4cf1a72d728a591023211a90dc71944e5aa1049be00a6ef939316636de37a3a07d0cf21a938a16bf49eac4270baf6d70b
355	1	213	\\x2aef99fb2fb11ed3924d3512b9d68a98cf0b5975b1dc04824ae3b3df052d53e88eeeb8082845c1d0909bfcac8c498766d16e787597269bad87630da6c82c300a
356	1	325	\\x919f8e9cc218d806de304368616a689bef5cd1e78a9893c17e8ae4bd790e8a1428ec22a53155dd7905a913578fab0f92f930ab42d4937fe9840c46788af85200
357	1	229	\\xb48bddc63ca3a47cddde6092e39ac40c745a88390a36482db15c434c64b58b1ba775bce8f3581f0a1ed31dde305846962b64af0e0dfd5a3a4077c430a3833d02
358	1	375	\\x8f9b5a74a9fe0b0508bef0b1031f4d448875fe422d6ea6f07afb90965ba0fca5884c4c8279803519df70add83e0f54ceacb73ea6fba1f53945f0ed898a1dff07
359	1	41	\\x0aae0961c1b76a8412aaa469b813fa158eace45f6a3acac9074d464a453ba64f40780ff95866696c6e817e63dbbfcaebc5b2fe6de3d445b25eadea0c4445800e
360	1	38	\\xb383de628f86298149137c8637d8ec1a80d36e73671efb8c33731b29e324f22fe3a23ced58e36ba57946bf861aae3f87f4eeac033be5dbd05d4d301a64d67f0b
361	1	280	\\x4005b07ec432eede65121a5da1879da8c365579cda7941ac51cb7559d2eb458aebc894a2d51219296adcbd9860d00c6adeaa1f96f699c9a54bb7bce6210f7405
362	1	76	\\x8ef8589a9ab73d18e44a355ab379987b5faa76d90f2553ba3bd670fa162f03a368af50e4218c1ac51c76abfc1a8ccb1f923eaf99351f34b658fa28b81b346a06
363	1	349	\\xc88dde8682b7ecb0541d35a0c03dc44d02f52dc768942d73d96732ac72b70d7892f6c53a0ef094789fec7376a2f3315382fcc99f27e8137097c34213690ec703
364	1	405	\\x9b66ee30d5b3ce17a3dfac9dae3ea057bdf004e26644ddce29a81ffbb97607841f672f68ea9208d97f960f01574407809601d4854d2ebfa6ba49789d5a9f5c05
365	1	359	\\xf6a112d1c17ea7a835a6341a3b72ad9b954ce4459b473d5f96a75a45c56dc24783b56040ee2580648cdc37e28f1fc8273542db27cfd5b35fdbf36df1da869d03
366	1	345	\\x7dff1797b6a5d3361a5a61791bfc623d6b54c64b70054c43b71cc652095a6046c7fbdae4b34ba5983a5424a0d101893c94204ea9fee51df6830ca94dac0a490b
367	1	423	\\x809a322938b8bd1777d55006dd5b0b4c833913796a17d489409c98583917ef153bbe77058aecde511ac318a3929ee26ec68a88be9147aa8c3fb9ba4ef752df07
368	1	266	\\xd03520f13c9bce90e5992b934a21eb5eb08a1574761c6afccf34c256e6bc7c90327a12339575e36fac2811305bd4df9c59e75632988637f1aaf7b1d0c8a9cb09
369	1	24	\\xbc47fa61641e9fb43316d7966f339de44ac308b1626acb21bdb698cd32a21a2a4c7313560164a032253734feb439f6e75b1a601f5f762bf6ca2c634931c0e901
370	1	385	\\x3544ce87e99adc3d85029a0e2c6ba97d8a9d01f306c66d33f61c62471eea297e0d28e20ac3797cd540fee3aa60a7b21314de11b5b45d720fd0a32fcd45fba80c
371	1	386	\\xe281356e184cb666bfdef020b5aff2905ef68040e26a651183d231c6458c4fa4385dde63762b12c2e46d69cf501181995e9b1fa056bdb88cf5fd4b2fb2706109
372	1	128	\\xa8453161cac9e553b79abcff269e08cebdeaea05ec6a29a868c26f126275d8ad201f0d2a44e32606da5e83f43f106ec6bcc529af122470a02efe060607297009
373	1	308	\\x8e954fe865931e59f3c9382c4fdbc853f9e4b73f63aab6dd053533dd8d5fe285b2f9135d6316868ea5a7dcbd2eb3fb59182304bf1431cd81394db2a4bd7d2804
374	1	250	\\x04904abb158cf7a9f872326c1fb8b2249028a52720e037f11d9a436fa022f33a4653853cd12a21eaa0a3c40325935ba09288c3b69ceec889977ef55a9ed6a001
375	1	339	\\x7bf19ce407f7a3d790b75efdbec628c96077c154255e4fd7bbd1434ddd280c053576ad5346a393bddcd54435a3e95311d6cb849f22d4cc26c9a57f5596efd80f
376	1	197	\\x1950efb4cf998290842cb663d643fb19946668ea788c5f3f584beadf0c21da3d0631c99a4df114e797291ed29f8da8f867d1021a36f4195297d56088c290740a
377	1	245	\\x59c47bfad3aa79f3bb0715f6a3aa456f9f54aeb288310a2429312230779db2fc9fa36330d6ff8f90a453bdd6ee231f9409fd0de6a6f4eaad626341fb35c9470f
378	1	272	\\x88d0d006b336e9170da4052d45f9f618e87d2cd970036e8a40c3994e87eff0aabfa07fe63d47e4ef41c4d5aee8a31759d4bfb8e22d02dc0a06a4e2a7e5a99e05
379	1	367	\\x51c3204cca16f8ae5aa9abf2370ccea3216c0d590287db323ade3f87fb5794821b7ec2bff4999711f728c97654458cee28c54afd9faf1b09edffdb167936c007
380	1	21	\\xc853effd0b5da97add2dcd9398d6b4896a84992904158ab1728d4a2a97444c3e7456c64e3511181783fceacc19275a4d8f50f978b58801568432c541c1c5d80e
381	1	109	\\xe9aa868ca3e90a19599b60b8173faf36092f67756b70b47d2483c256843f8788e8d5d80e0b95d31d9100107e823bd9ce3323dbf770a66f0eee0fe9335075540f
382	1	352	\\xfcc69884b1fc870cd42ea49cc30e287dbe6912f60fbbd6d21bf3d0ea1ee6f1de33d1e153e75fd7143d54a3be394b0a7cf20a10eaa95d7e505ee6e36953153c06
383	1	207	\\x7ba378335a55de2f09e86cae1d75c619f19666c34a74711035cc293e907b25d9e15d7bfe18f6357f52229077fb48cf186970bddc869695a6ac917c6d7458340f
384	1	323	\\x43a30fa86f6a4acdf97c992c0f6465500eeabe6638efcd9b622c36244ad9a0712ed39b86def236b98adffcdf8b771624dca590e2e8b3dd9e008ee994e78b8e01
385	1	150	\\xfb217e01215fdfe37daff2a5937339c6ed8ce4531e053b6a0e5fbe6b49e242dba4f94720d346b43646c588565fcc3880c5242b0f0068c46f322ff654deca4f0c
386	1	192	\\x9c05d9f91b1fc7b8e94353a4c31af337a647908e7146d890cefd85592ddf98f6f26e0ff6da4b46b250c1f1cec437e512b2ac483c287e58207066e2c099524e07
387	1	411	\\x8daf677e60efedf55dbdfcede2e71e1c7563256ea82d617facd7839595e5e50df85b2fb55db51fe1f1e4bf79628efcef0725a72916fd630f7079568e0c0d8e07
388	1	178	\\xd3bb55118bf6e4059f673f9fe25bfeb83feaa732a166fbad0b9cb3f7cb8e580221f388e86852bd6570b2ef4d22cacf8794a88824772b4fbabd1ae1fbe22d5903
389	1	329	\\x3da4070296812b49109410adb4dc894e707d4ba5824a9105560d0d619547e7d2b96fb2e57304cc9ee0047d1347f4d065931ba062157ce2c5ed09ce8462923f0a
390	1	281	\\x2dcd3fdb2ba64d21009570a61c16673e9487f15555b988492865cfc2060928b63b365d65bf36167746ccc87eb53b8eff002eac406391ed9234dd9d1a0f9a3d0a
391	1	410	\\xd39abf64fa5ffab696ad42865a6da8f5d4d098c1454ea83931ecb3056baa0ba43e45cea183d26aaa6ca3aa241a852a26af5bfd64f664e108e0546eb72b2aed07
392	1	171	\\x376aa65586a20fffe12d1365a127f4af27f1b05830ae82d1042906d457dbb6de95894329f4b11622de81fb63819acf9b5de80eaaeec3a581b4e16f2a64457407
393	1	254	\\x0f3584f5a0a2d5d05644d91ceb8e1d6eeafc881cfcf407eb49678d6e31d13163b20c6f94f902fcefab258a2af47f538cfe654f78b9e3912ee8e46ffcc503df0e
394	1	104	\\x791c01b201a57d76e67b47894b35d84643384f82b50f41b35f186a771014d92d7b89966439222258427beb510037109b13754ec408411ced2178117b7c8b710e
395	1	155	\\x16369977cb0b2f616a4b4e126e962a2b0f74205a269f8c6f63ba69e4b1eaaa27c2365bdf5929354d22cfd783c492a59026ac2a9c1c74068496dea28715b4270d
396	1	413	\\x7f5430bd994a70048bf371d9046b83c2794330a8adbb01743e4e7fad8016ec80226cd29f1a1ece40d014868e538354bd46083d222b323cef870d11f96e229a03
397	1	361	\\x511b94db78607065662492ef57ed75d657faeb61ef1220848059e4ee679ccfd6babde015d6bf2da0a80a000abdf20927ec093cc6e30db03f0d66dc7c355dea06
398	1	246	\\x35fd7ed337711740bf04637fafcda70fdc54b990efb09d77c73c3fb2e71215482f7aae3b037f28102966dc9d5723b04619402a74506faf6b63f49896a0afb304
399	1	351	\\xc2a33f851a54d34d4566dc2d4af38105824f672b145af6984d00e381fbf74183d23ee6b556f00e355b87918fa8d51c9b9234e5213aa8fdea53ce374dcfcc7f05
400	1	334	\\x974950d5ad1dcc2e7312e4eff4f59442ad990b156c6b31e668a1e8154ce89d130f76cf8e5d9234fdf081f5d1ac05309318bf69d2a4fcf9830ac0d337301e620c
401	1	321	\\x1e6e273077c444591f367856800be2d4a987bb161c36ca0a33d116bef04be4401fe88a4afd40b463d51588d52925c2d982da292884cafe50f75c17cd2e5c1407
402	1	377	\\x82c6993e58cbbab8c10f42707167cc86ea7d27bca1954b5f2fda141a65dbcd8b8cfc0b230524572102369005b81c9c13d5ba164da090f97b7152a04fd7740c01
403	1	101	\\xbd7e98c602fde55d44a0c39705517bf77e70e474f4cf2289a675c0e7cfbb3821041fef9deba4fbf41adff2c354ae6431cc0be051ecfc5ebca5c064b4a1dd5d0e
404	1	300	\\xa9a6eb45ba4f4fd37a762939e433c508b3abf6992a24749c04d7a33e28bd73a24e9ad2358cae9083f64df1b83600492f3c7f3d5b2706d90ccf8f023c6d920c09
405	1	25	\\xe1adca3775cc9b0caeaa6681b18659f0d95ebde716098f0d5a57a98bd0c4736456fe5ac26548d26a1718642d7e8c048ffff7d3c44479ad730cc6f58d26b1cf00
406	1	185	\\xf970e25a35491b111e6c940a5ff17994c5f2c8adad9763e8186b2ee5cd696fb407d55edc4a77aa63251f991e59efa62b8be1309d028a8ff23addd95673c37105
407	1	71	\\x64e0826b371dc50a8fc9ed77293e9b23ae8c3867e4ca09b4bf7a818bdc7b57841aa9776f3ae40e2d88ec2034c95468dd4e9c50d22512e6ee6934d6533c24770f
408	1	211	\\x6b67cef10753d11f8a61bd19ddb8206e6546db5e90a3a3a2948fb17bee3ef9a9186772505a1d9c7155410177cb2a14c694d9e4e79df8b701c8f3c8439bfb0604
409	1	82	\\x5ffd33bc4d3b58c8b453447ae628d9761d4e97ff529e52db7193ae214a4599f44b4b33b9bb2acb7c4f9bb405b0e886287da65a702c2ced5920b38bea6120d00c
410	1	235	\\x375c1a86b8a169d6e7dd3c3b7df1e4f8cd0cab877cc3538f0c4f41477af969a4591f02ac11c258baeae7b17bfc77ce9a6d3d33766401240c5ed415c6f7fbb001
411	1	278	\\xe01249e8d20394c0dbd56459740c03e16f071e17c55fe90a2af0a06fd9d8bd4c8b40fc540e52103c1632435796b8604cbc629dc37b82e8a37510936264252608
412	1	366	\\x171d9a1b38a2fb612860d74fcc1718b5a67276c6146d851992cbec969f81e949f5fdf4bc3597b23ab669eff9361640212e5d9c7da831bd1197353da04a83fc0d
413	1	363	\\x178bfe65ded189d4a9b6838182ed9820230cbc5ff1355cefc2ecda0827b6280b761763ba86a2ec6fc5d0355dfe3677a6e31aae507b95d9455ea1bc4e5c0c2302
414	1	208	\\x1f7529e17c6217b531e6b4b9cc99951be47fc5523a1824934cd2b8edcdb187c848c3835d01cca0f64a54495e2c5f07499bd70e5207e02f33242418bd43b9ed0c
415	1	26	\\x3161d89c75c2a72bd827b05b3bbb6100c3e6324c638fa603f50a3d78bffcbe7fb1ffcc20260ef3544b8426d39c449b427a85e853cdfb16ecb79f02dfadebed0f
416	1	244	\\x0fab2d548c2d13d65c8a2cad5c165b73b92cdd2a71132dde534b820bfb20ef74916894e9e6e6a2fd51fb5037f7bf92005b7f42927fdc99c36f4cd0fb1af7bb0b
417	1	190	\\x0cd20e445ed89f5ad66ba2d9659b56c3759bbdd7da516315238ad8ed9fa443d75d2aaea7ba0d6356d32f8cea9526ca1e8bdc592a551209f8a1e26e07694ff500
418	1	256	\\xf6477e7ad215246539a9825a3117202a485c91b15624da0ce21149734065fe6b2ca131d79e4984d08539ca527c72fb73476e3b15ffd1575e3f4265c281668e0b
419	1	120	\\x75137b341d69b4fb96c6013510234cce671016971cf44fd59b86c76e9dead41d28ae82d39e8025810616c803e5fd44c53cc9b255034c148c8acda90388ebdd0e
420	1	313	\\x21d13c319e7c55fd10688407df27400b4201973d8db1c2fc51c540c606c8cfec58bd77c3a4ab12c6ea3fba0d4ded6272f0e4849574e706f246879f5b408fbc04
421	1	270	\\xee3cb61ecf6a5f3e00813000ff551ebf0be11ae3b08cae817c8f5d4a5c39ff97b77fbe0b731edd7c3ad133fc3314ecad77e5ceada5dba81325bc4ef4d413fc05
422	1	180	\\x7c4be7e104f694c7566e7903b2aa097263d09840125624188d7f2627ddb4cd6679bcae352ef7eda2957acfb7ff78e4e7eabbe66b378497fa55d355da757dff08
423	1	144	\\x9bcc3d37ec87e64306b2d56f286ffaf7328a25f4aa2f35fefde44de1bbaf55714e59b34b12e5f0e50e1ac4238ab78a41c891b9f8993045567a122a4666e63600
424	1	205	\\xfed3217200586433b14f493313409de8742769a616f6c00910f02c147d4786eec9c035d57f3d941e45067d9cec2f25adaa591adca0da8d487aa91c5905c57307
\.


--
-- Data for Name: auditors; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.auditors (auditor_uuid, auditor_pub, auditor_name, auditor_url, is_active, last_change) FROM stdin;
1	\\xc596aadef148cd22e4d73054547149c245c9f6cbfd7dc7fcbeed7eb055fb3a2b	TESTKUDOS Auditor	http://localhost:8083/	t	1660491048000000
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
1	\\x018094441ea3ceb79f7c04494a0ee843ae01b8acd8e74ca9b3bf0de6dac1c105caaf328d4a3a2b310bb0720dade1e45cc4ad3da15d345432503aef0b8e9eae59	1	0	\\x000000010000000000800003cb7645e4f5bcefd1175c3210e5bb6b6fc96f267a751b2b79b16a9ca2db5e65ba2a7c620913f214e2f0ed26e52bbeb1bd045b23b5bd013edb63aef30ee04e6413c6c768dd303b1b113b489d1e6d2751386db3d7159792fb21642d7b4e0e6d53bba863f4066c13828513f3f36021829ce7dfc2f71a9cc551c0d4de00cb3f784695010001	\\xd6ee29c291b4ecb71ba5180a2ef380eb2e6402111a5c242076edb1c23f243db9264d3f877e790805578183c34c1a7659f62cbe0559702724c0b3123360d3ba02	1691320541000000	1691925341000000	1754997341000000	1849605341000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
2	\\x01004fb1ffaf2234f0c41d61bc50d0aee852475e98163714c0c0a7a54b389f614c9bd653452f13536413e32c8495ae4b25ec33c0d282751b70a6d5299ae4c9de	1	0	\\x000000010000000000800003dc1296012883a6d081149c9f050fd680c0af24ace77fce970a3b0ee97ec92bd33538749171b9ef4a8552f548afd479eb4eb1cfd221ae27f330bae207180b066c14b303ea3fbf5bad806d1cec8d558ab6f14ae96de5c2d426362187bf93807c54a3a0953daa172caed5a516b7685f02b2935463e035e88b9808adf7cbeab01963010001	\\x63d0d20c618a82b3c7e5adb40ef243f796faa74e2519505f27a9d5080eacd0218b19bb2fd4a4e0810a737047a93783811dc3239f214bed4b24ab68573f7e3809	1669558541000000	1670163341000000	1733235341000000	1827843341000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
3	\\x03dcf11c2791df143b622ce06f6b9a6fdf377f8b66fd79a446d939c17693cf0c25db0aba73cabbdd5c6301de59a14a9011b65b533bec187d11ed467f9829da2b	1	0	\\x000000010000000000800003ca378c321813c9857a160662eb37235a408586063a51b7cca83b93c1b8d9ea5b71e600d77eb0635e04e9ffeb35acb382207e0bb61139a63498e0443a915ce5aee7d6dd5093db2b12dc477ba166f1616cdd65673a7f4712b11e63f537ee3d7e625e0fae3307ada00b67218f3d5f62007a87b8b5b550866a8ad343296c11535c4d010001	\\x6c4795158fccdba38c59e8edff6580c6f5490a8071b7c1bd3b657925e8c56b9d84e34403db3d63a98f5b7d282216b0187293128f521cb8c4e03fa0215666aa09	1685880041000000	1686484841000000	1749556841000000	1844164841000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
4	\\x07645181b4f962c7d32cd871e6aa8866cd288197d1f0c122b955d2b36aa2fdbcb1c5f528c61f15748dac5597d92b30d5b4f7e62b5ffcbbfceebb62c9fb4d4d0c	1	0	\\x000000010000000000800003f2927ac22028795c97286127625975ec139e1acd2fc2be90bdfaac6f109df62758b19ce5416d98e162974baa5ab04143fd2e27c7ac7a150224418798fd8d8495bed16dfb7d705e68c8cfa6d5d6ca43a3ffe2ec665adfc37fbdcc4fa79a846285deaec79655b8739ce5825ecc4d16607f57d1340f5f8a80b385697d1711a24ac1010001	\\xf2d2f3ff871acb0685b77887798629fb55fe9604d6f8220ce22fe85cfab9bd3b90e3d9caa55c8303dd0e2e874e66648f2aa11d757c62233c8de23826b718aa07	1685275541000000	1685880341000000	1748952341000000	1843560341000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
5	\\x081032b1c8430d5c4b9e7838aa450dbe5c6b15b98bf5cfed74fcd8b43e7b0bb1471655fdc61333f39eacd4ab941ff5997bb2f40b86099646e34c71b75032249c	1	0	\\x000000010000000000800003dc1831983f51aa055d1b63d88f508c80518947f2704a286447c29236075c02f04227632be4552ee771a56ac9e09073d3b08e1d669d23c7f1bb20f8f9d3ae66ddf0ff053b693c390c9d3417ff26dea09633925c888e4c05c1ddb46913a8c0c5188e00a2d07ebf0dc28a3f3105b770099612cd3ba8ca290de0057ceef5ad173dfb010001	\\x83f8cdce65366bb9d4a49ca7bb216b5d454041bccf210fdd789d98705772b1f63642145b7478e7bd1b087e61eef7895888c650fe4d74e272305f29a1240b0e0a	1673790041000000	1674394841000000	1737466841000000	1832074841000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
6	\\x09347bf4bb8e02e4930fc404251b59ae71e1d42f4e90f482cf30464c351df551de2f9c4f1fa0e3c7675bbc5815a06d5c2fab36d1a746a915057e86ef87d339f8	1	0	\\x000000010000000000800003bcb84e5f342aed9d4ecd95b9b486e0897053554da538bf34b1b2758a76a5c4ada865dbded1f900f038f6dbbe55278091c2d5804627646aae061acda67f29fed7b524dfca55fd19f7f5a74f23d249eef9e1692c62a7072d69d892ba18155a462a21349e498c45784ee6788de5f10044817ddc19b441cf9e2a50e69609c4e95393010001	\\x9cca0a598ecf7e9da38aa0d3a975a48791a751179f25edd7b8030a1091d1a56809522ca4cd767ea05b2a3917c285d6fa563bd8db350fb6244a470a5803283101	1681648541000000	1682253341000000	1745325341000000	1839933341000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
7	\\x0a1ce949ad2601a27e207e3d5d8ee6d61e17ea176be0c32716ad38ca1c9a5c66986bc39a99e28fbc15c0eea7b787a61eaecb64d568b9629b781f2d34af9a0807	1	0	\\x000000010000000000800003b0e037496ea0ac4981ff3309467d431109d1d770d9e81cf1deaab1041282b820d4fe5f623f1f13888a089da3a9842608bdc1809d1766916923e5317a67dddd50fb3dddfaf7a76430d65e0a096bf230a272ee9b9d2da2654b66cf61bf87633144b0d66d742b5f5b423b92a428eaa9ddc7df48c893905671752dd7064d205aa767010001	\\xf46db8d3494fcefda28c3227b0959a318ef1ec079cc533408a9c70dac08edb505edeeef7b04c60d7269aad082c99177d3bee5ddda9f822db47bd02b03b3a780f	1684066541000000	1684671341000000	1747743341000000	1842351341000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
8	\\x0b7cca64475a46ec9f5fad4916b9404da6ef6119480db0018b83bc1e09d17ec9db0284095ec85a937d0998d9b836266e53b2c0148173d2b2956a36bbc4e2cedc	1	0	\\x000000010000000000800003c7133cb5ea62060206be8ff8b9377820a757bcef1943b671b5fd28d9bda015f4a1cc3331170c65260f00142d914d2695af1df0932903ed5d02ebdc3381249a393fbbc9b9a26999314f657387374d816c8d66d9890850903e5d2053cbcb6299f4aeefbade62f1137157f48b194df0902736c5ada37cac08a092fd8102fb1b858f010001	\\xa6fb79422265b54c35d6b1070224d7b073c6613fa075c94246d8d76b012134fcd29ca0c7f744b5a3c00ebb58c289ed1ce39bb75cd8242d5b6e906d6e1fcdb706	1685275541000000	1685880341000000	1748952341000000	1843560341000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
9	\\x0ce00292cab80d51157adefe0d45bf05595003ea46958c19b669f4c292db1226643a8e75f003a47b927fa653da36efd77cbc163a838f10374365c847502a5825	1	0	\\x000000010000000000800003a860fa3b1f6b7d3532612bae866ecc40ab961d7c49503f6858962b171838e973036018bcb2d343a60ad9a34ed6106af08a4c0bb2f33e374fa43715e33b8dbeaf0973e391c0061a54e1756c78c7c7b2bbbc7ce9c4ca40967aaeeb200312c671a16f690428cb4c8d7914d1603897dcc9621e4f9d6e7edad32960d6421e0d262af3010001	\\xd1024443647fbf3388df7d18cd8d021cc4a423cde9217802d5cff05ea1d6fe177cd45903e67ab75ca22066450ea4bc98d7d88a977eb66992f18a65d2a43c7f00	1678626041000000	1679230841000000	1742302841000000	1836910841000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
10	\\x0f2c8320ad75fbff8ac49e8bd77a0200207b2624c561eab18b7edfad96d9af8d858a4afc48c409431093e5a4fd527fbaee1d995b77f313731c1b9876d979cb9f	1	0	\\x000000010000000000800003c809f63f5e783a8a2a6ea28888c756671614249329b02c0bead71ac7beb82b00c485c44ef3ef238623b1f92d0485f57a606036a4d94d94a45cf8f89d6a40727120efe47b9a6bd7418963d9ce7d8a862879c230b6050ba8f80f5e78867dc22e0e2fbc9131b414daf6bb4390fd027d5f44ac6d21f591279da04a1aad3e9c0725b3010001	\\xe9d1ccc2b42a25cf9280cc4c8f2a746621b2cae6ee205afc0f6ba8aec4949632b65ca9e8d51f49c59c4b632d3cb85f0e01cfcba0019b7754d391c158ce277902	1674394541000000	1674999341000000	1738071341000000	1832679341000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
11	\\x11e0b2b559596b9e039d43e5b1592112febfdd7084ec71d6494ba2cd5740fc2bad4cf5094e5610f1fc930aab03548a59b7d7cf0bbc12897b200b7a0cf3f41bf8	1	0	\\x000000010000000000800003b3f2c37c94941b16d9c5e948bfa2e9608d50ebcd626c7a8fe0c1a44d55b3fef889bbe53ef4955de01a07eb42a6633ff5abdab3e9f4b300e8f85c96099a07b398a8a1ffc7ff556c4c8f6b02053307699f6c49647135eb6f9b2cf513e142436c550518d9420536e40fc15bc1afd52a0eb123a07104fe9783045e510e0143e453c9010001	\\x570afd04fa9122c328f8253c3d5205218a6bda1ff77e0d03c2c16f93d27e68ff3cb969b3f63e8ba555f386056668f43f0d1cd30e19f8495f2c0c8b0cb3272c04	1677417041000000	1678021841000000	1741093841000000	1835701841000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
12	\\x1a74c1f2be60299047687471f25ef5c0f036806b3da733f3c3c33506a3cf00b119d50ab98bbe9c03f733656057a735b1a8f57e070a1e24af36f05c2185082029	1	0	\\x000000010000000000800003b54af6aed87038621a7a3b830ca1a8f76e7708a3ed871ad974dcd27a7a57ec7d8f3a3ca073095c450113a8ec4f87a40c35e6ca263d5f834a6ea8be09aeeb573b95b96b078bd76220a49227df7a93bdcf895af94878ef34d03710e13100ea29ca98bf375c8954cfb43cd189e5fa6502c7948e1c42a45be175b0562fede43af42f010001	\\xb93078520eb7d7b359d9b0f52d8e8545224252ac2315d58e0729a2b6720bccc54fbc15ddd42333c2b0023e714ae3939624b751e64c9ee0c0393ee1d4c93d6705	1688902541000000	1689507341000000	1752579341000000	1847187341000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
13	\\x1bccec189fa8527db18e110b75989567458cbd58f41bc00cf4ef338cf0dd82d38f56b1dbfbd023488490160a140af3786ce3c15501cf60ef2c14c695c7e77fe6	1	0	\\x000000010000000000800003ca27b9a7dae9f9085d5bea544fa00608f6557cb43e71408f7f4bac288123635988bb9f26bd33894b19277d3ba3a2bc0c6e12ea430b9bd27f766f0f435fa49f68e208d4b4fb0547f8672bfe4b369bc7dcef008ead470cae145a85cd6e66f868e8512cdb09054ebe47b4d47c255e5a8486ed58beba0388029691b8986cdea61b77010001	\\x88f84e4ebee9c87bb6e48663cc11ae6aa9ef766da0ccbbf101366ca0e6d53ee34bbbf6c8fb5daa87c43d294105ea9af3304cca3109d8e3d24843d6beae1ddb01	1673790041000000	1674394841000000	1737466841000000	1832074841000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
14	\\x1b747c973d664f4b1ac92ee9a51358617b5ec94106845305cd1a05fb0dc4d53473dbad748767f7a893ed708e80ee17f65d38e5da6d326410e5a1a28fb08c830f	1	0	\\x000000010000000000800003a1bb7f50649cc9095f555bef6bd5a2bca383adc77d59026e49315ac6494b8096668ba0f4ecbd37d4820cc286f5995d1eb0ea865e19666384268ac536ff58857a339c76f06f0014a3a812539bd443074b29364b9364c2701b717ff459ae5338717c54383f3da715b7ae05248b0d0b751236c73347d2a52589308c82ffe63b5869010001	\\xe77e0644f91f8860b2be4d86ef0871cfc8192f9a9fab808082e6f5b45ef3a12b921377e9f4efdbb8dbde9b59e48dca670ca905c5f675a2495a6fe610981d7c04	1668349541000000	1668954341000000	1732026341000000	1826634341000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
15	\\x20e0d4ed0d6dfb11a61daa6b37e04f5bb6d0bd0539d29c024e3daae9057567829e7a1123ac9a71ca178ed08b4a587dace9911d83795caa2209c8249941b09f6c	1	0	\\x000000010000000000800003bb0447f94986923ddd4dd8794d7823a3d7b1773169dcf94aac536ab1fd6f46f7158ed56afadc77e36a132e4d9a3b8d6208f5287a08429aaf63f71cf9099b40973b4386f0fb5f58f7b95bc64282eefe0bbf01c6b615fc7ae508f0f4837c4c56708b7eec5eff2e2fbcb5a294d8c54c6732c2b0ed9991503f3338562780af0d28f7010001	\\x8a1959c4528fd0b6a1f575ab5fb2d13fb98d179179d9b9f9e80619d2e5f99aa71cfbbbafc55195ea2974fedee99deb068265e25157c347df3fff60455f5d8202	1689507041000000	1690111841000000	1753183841000000	1847791841000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
16	\\x22b45f0b63df3a9201b4ec3bbd7dcdf9723a9a16089a71b099980b60e4793977e0d81314814d84e897c884ffa933fead3da7857e189803614acf9407216ba63b	1	0	\\x000000010000000000800003e759bda542e8159304f950f90b52dca1baffa93bade8f3bd316ad4d8c66aeb99a98b8718ca6a90fb484798ce9b7f35e631277887a3809fa619367d10a5e86e7a88ea0fb752f4821092ce96f14ace18ce0aaa2f5d77c71c060394f60906e7fbd52fa76a5ed5813c2f67c13089538b14a631cc27db54d165a4aab72db374acb795010001	\\x00ad09880932c44d78a03398c22ad74226471a21c16980c10b9af43d418b2fd1cc1b0ad793a3550da84f4b3d3da3471ae852cb34b78530092724aa7baa58b000	1675603541000000	1676208341000000	1739280341000000	1833888341000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
17	\\x2cf825ddc5273f7fcc12f01c42c2c39720f19501931deb1c1d49ade545a9dbde813e62142b4a207891b63c5f09532e1d673a22ce69aa1e3cac826dd34dc67daa	1	0	\\x000000010000000000800003bf26885a6a0a1d724438119d84eebd28bd8d390ee82e5deb3179a55ca6ada2f6fa2fa291a8f2a5001107ec72301776216a55d89a55f308d211a33ab5dec619e37aae93cfe10688b4c7ce40d76da4f12d967d3dab467d8d4f6c102037030c87d021d00e35b67e368540a022d5da7951f8a0b38be6ee3710c024f148736754843b010001	\\xb81a54fabd75950414b5fc67c3292709b0b19c995c38b6bc01fb552ecc6bd9718ae7300e9d600161a2425a53c682929573780cb15c268e61d004299a9f6eed02	1689507041000000	1690111841000000	1753183841000000	1847791841000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
18	\\x3194fb7730e0c0b3a027b59e14e8d505a7b48d128feafb737b0f50f7d19e079085a523ba927558890ef1b1877d2256ac9587595bd0e0144ce1efc53f5e8c77a4	1	0	\\x000000010000000000800003cf8fb6f5a6aa02f8cd667100e5f3d25dc728d623f717f4b6d03eb6cb11be0db66d120661f4f6aa7ed06a59411d89850fec4db91a8d664a9f052575d5c744eb46a73637d50153cc6e82696d9ee5fc07b0303786574a3ab77e533cb96361f3445f8aedf1811229e6a55ec6d558e58d0c4caa0fe28a2bbbf7ebb0dac2a2aba927fd010001	\\x0c0e8f0a7e5bcc2c7ea93d1af3ffa00434bbb9e38253d4b1c0893eca53936cc5da75cc786057311885442f3f9dabf40f429d0305acf3f7d696266da74d741a06	1666536041000000	1667140841000000	1730212841000000	1824820841000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
19	\\x334483dcfea167a4d79258e17ca6585b271f81f3b249162bd0786d3340d94582c47557ec54777f6a7dbffe19654828f83542b9dc2354317c8ccca29a178ddd6c	1	0	\\x000000010000000000800003c1d3ae13eaecaa4460c6f6c82a8816c40c831df6fb9d0cde5e13b3e1fdf57f581889afb63fdb251031c98a11421aa14deddbc85c1e890f96c65e3dc5f7759e3ff281f3ae906c1d6429dc77407ae26d5c7ce77187113f764ce88cba47609ab533082e15cd4cd39a0a0789b82aae8d9cee8f6277fe82e12d761e2ef18202718179010001	\\x5c333ab1ded3246ead1a864657f33b260a97c2c0fd8c2961b86fa7256f6c427b48c5387ce4c35cf9f04169c68d10596b211eb7f7510f936b15435b028e98b500	1678626041000000	1679230841000000	1742302841000000	1836910841000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
20	\\x38d0e6e52541f5312f8a4e7d6f7f29a2f9296bf8987f5c37e87d0e4891f98ac2421050f6598d10390c4657145d6132541d43b6387a91ce118edb93ed1cf83d28	1	0	\\x000000010000000000800003bc16df99abd28aad9bcfaa49c1b2ad42b7750a3af4d16296dd81ea2848b951c613227ed97dc033ff38ee166fed59da973b045720d9d103852fb23d3d4034c5469720f51e33094af7196744a51886995c409971eddbbdfa2ddc309f2158152b0a303ac412ab372780672337f17f3c9acc5fde231fed3a8dc5f778e181c05fe49b010001	\\x5a7698f156ebec8f0dd27c6621020bff4427d6a587c290ba8e4f5d850b05f5e2104bb417b731acc87a7d7bf014658ea04bd8e410f288125227b927662297c401	1686484541000000	1687089341000000	1750161341000000	1844769341000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
21	\\x3e28260017a45ded47bf0b4b7b200dda0fc0df52f808de7597555107c9e0c1d1a47675a04a4bd462dcd3c08dd7e8d1a06e2fdcd5e0a3d62bd5d08f0ebbf04fc5	1	0	\\x000000010000000000800003aabbec35d881e0e771a1b6b5f97b33811d0342b05460b0a1c8633adbbd8175785a29fe602020839b04f98aebe4e986f926cf03671f75fe0a26050877e94bc3502dbdf12d8d095067a0dd9b85e8525ca0cc8c30c5ab4f4fae154a475e26703092a50caf3618466766a910286c2891f5cb8319358f2194c997405f9a743ab53321010001	\\xeed274e007afe0afc8c7cbe8615c0bc43adaf408ec223c1811ba7f4302fb4e1ba4d60d0d7110d42c5c3575dab66c745fdfe4dbb8c6d36ddc3b03255551f7a00e	1663513541000000	1664118341000000	1727190341000000	1821798341000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
22	\\x43a4401bdb95a608ec875151347d3cf80e625f467e98f62377a771ecfe4c1b2260d31abf3476a663650848d216691ff63ac16669fdb25c19d399b894e8b26384	1	0	\\x000000010000000000800003cc61bc9e2a4d8efe04ed0854196d2990390bc2587ef4efb29a07e856defd9aedf3fb001d8623bd84187a201560d8dad2a6165025e20bae88928d7d942847030f0c5982904738dd25e6e7512db8056982f590055763c6c32b69fd79d0434f66fdf5ac412359bf459bc04f49ed609022bf8ddd5abf17b9842f96af4e0140ee623b010001	\\x52789ff40b2c4f8ff2f205138fb1b0a70e6d786f5fe589490baa6bdc2e04779a8fcc150af495893ef82001565f18ed4a3556d0d39b586879f637bd63cf75bb08	1668349541000000	1668954341000000	1732026341000000	1826634341000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
23	\\x44b0126f620266d53271c335ada3810f507de4f7b5c30d9e2be93ecd396b4d5c199029e615ac25e4372edd125f67e73fed321abe03b6a06333c96b9f3cb0de4b	1	0	\\x000000010000000000800003f9fba863abf8b3eb557396574a967ef1f1c4f4b469b9e32836af7b6b5958a0008d7fb08b6f1c2e996220fefa31c9b5e586bcbcd6f0a396b6b52d1b89eddba0a483307524d21cf2ecfe1c514a999c1b91e5b6803f331c9dddf4e74a7fe6f537eb6ae874907d37db564a4ca2d1050318f113f5d2f7db83990095cfaf090c374f8f010001	\\x49c2b7e9edd0c10db59e2189e3a3272e970a34fb403a28c6e8d84c634f735496ca3d0520f732a7ca4858c171e6669ab180335890e438f3a3cedeb3858327bd0c	1673185541000000	1673790341000000	1736862341000000	1831470341000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
24	\\x49ece8709aa1bf1f7d40317f09ca465ccc969a6ac04a251a88618ff4383aada271cfee8fe257b84b6b3087e339ecfe1bbc786fa13e28493ebb2aca57faf84e48	1	0	\\x000000010000000000800003d01ddfb8049637e1ac78f1692c02647f7a6fda4e39c103f330a231b8e0ec55f5cf36568267d80f1e9cd9e730127d04075395fc3036d31d7940f635469014f243ea75798715f7453f2441492d0c0710c62645221509122e98cc5062681d4067165785c53808234fa61ef0af2ff3e6eb6bb8cfe7c65dda5e9751ecfed2618fc251010001	\\x9cd6bcf9416d56198e83b0237c2eb5e19352a60b49e30ab911bd6af3549b096b2ea62ca75ea52f7dab907cc8e7374bc86b8f301a7b7021e114061dbc04369607	1664118041000000	1664722841000000	1727794841000000	1822402841000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
25	\\x4a1c149a256b3b0c7bd23985b9230f4e41e6cf7443b45d43f147f5b040fdb693e3cec7d9d204a14010004645cf83aa9754c9cd5246b15dff137b4b1c4205363e	1	0	\\x000000010000000000800003e45766fd286189818a8b65c20a3d7b48795532e94734b5cabe6e10f59a617fabf54646254c0902484e273b1a278b9d5d23edb5d0f3f0fd078550e1985782a64af9852ca609e84fa3a6dbd7da27b8b2c121bd2d065871ed85adbbcc3c1c5a9202e817e3ab64b2572ebab892a55eb1c4266deeeddf63a09d6f4b2c31f9f480d595010001	\\xc18ef3d291266fc79e5601225d9c7897b975d433cd1e88f12f6dd7ef9f25af2f631be0ff751bb94638abf27fba54e024563f559a97ccc27a2a6f6a3553fdf206	1661700041000000	1662304841000000	1725376841000000	1819984841000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
26	\\x4d502c2f621d9f3c07384be3e15b25e534186f2ce4e99aaa6b1ee4db1fedebe7c240d7616ffa3acfeda13bc992a7d94fccf413756b7ee767a34fbc780dc8af2d	1	0	\\x0000000100000000008000039e594e705b6d38aaa4d72748b563aca7136acc88284882329a552840e7f9388e9231c32adef5e78546dbec735f30a4649a415154c23354580e98b66d77c8f620216680296027c1a393bb15edf810d44fe861ed0426b97809153f76547721ea9f4b13d9bee5a3e1537d115db8c7e796b8ef9375d8d840df2602cfbb1626b9a7f5010001	\\xcceb2cf44655fc0648572cc65c0e93ae1d70e440b30c1a3b0d9372f0c694a486000c6bb876bc94cf5449a461e1d6afe71cd44dcd7e674178214760b3ae3ffc0b	1661095541000000	1661700341000000	1724772341000000	1819380341000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
27	\\x5098532dce6885e677c04543116d1cf28a725d4a62efc22c6787fda644b21f8504ff25db74dff64616a978a4fc3587f83f96ec094287ef3ccb9a72359ac54f31	1	0	\\x000000010000000000800003dd4eabd0de3a0b229b2373d728721efc68a637cc698ecd87bb8af9174a3ff7bb790bdd5eed0a8041b81323e0a9f0448704d2603733defbd7acc98621fdae58c393adfb49b0d47568aed45062e9f8e7629636a37066f860abc14e4b45a65997e6d88502edb42fde2ff8d14cdb160f20c075bf05df38f16e9788dc65d15c393d03010001	\\xd2dc0bee7f1e4bb6ceb756c447d52786a4d6184c71b4e0f58297bb97224be7d874c018479597f06156319fe0ce6e7adc1e0058251b9f365d240f7c4795f9c903	1686484541000000	1687089341000000	1750161341000000	1844769341000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
28	\\x5100525a202a1a84c4f62b0243c7bfb4361df25962bcf8b97e8716f2f3a741f0f1da79239f203f3cc5b96e6b899ef7d6c3c74e7a58d5f40d8cf0bf39caa4050d	1	0	\\x000000010000000000800003e216182c27de2a8d5db6ba41b818b8ecc5fb54a35c0f0648ef7c5c9a895af8c81f1b86e1a221f06044ea288892fa25f447cdebd2345db291699869edba74a274ea85b7a2fb78c4e2f747d9b85399c491dd64ced29051d10b93dbe2c2ac884c385f8b0da4484ff0ac4e83142eb162943e014e4b7488af9c31e7966de9424d1eb1010001	\\x721f6445658bc44c8ba7ee369f316b6b447b6ca0d8438f05432a4e64cd4c45c4474d64e1bacaa66ed26579dea7126726b40f2ffa831940497fdc34ee3b39a301	1687693541000000	1688298341000000	1751370341000000	1845978341000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
29	\\x510c83108d5f4a0f7433a8ca68dde2c38b16d694e8fea7b309c73fff6a5d628425fc35c0a2b0670680100cd51c1748d888a6c69814b218669430f14158eff53a	1	0	\\x000000010000000000800003b906c08307f9bdd33129090678263be586327ee2a00b1ae987fde32ab22ff80510055a8056099aca1dcb10c86ea36539f59198b5873f53c2c535d15de8660dee27b9513f01c4c7c124eee5030a037de58ab34a53fd618d78097488a501c55912517bea366cab378007e24e605272add75bdb4dee7eba5f22f617d648d296a7a9010001	\\x2211a256a5581bced3b664e2e0101986de1c212393071412f2a8c02fb179a88899229d348eb008db91557f57672c18dc4d52693d4bfe06ee1e18607c5d85ec06	1687089041000000	1687693841000000	1750765841000000	1845373841000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
30	\\x5278ccabb641e86676ff25ab8bae639d7d027828d22bfae6a816f9dc233ad5ef689e64af085077a8ec26985612ddf58dc963a26dc766dfd2baaabc8e3913117a	1	0	\\x000000010000000000800003af5594c8ad889dc5011385108c1206b44725b8667812de2c6a608a2090a93b6e890319f374a96c3ca13abd80b1af263e0990855631fd4792cb5186606a95d2737df3753e02a4febd046b1d693bef1f9241feb4d72f59b87ace141830c2c3f0139cb647b3b7a071ab357d0a7efa35dec0a0c44c34844bd4eb0707ddf5d5cdef45010001	\\x7476995dfd190ed574afce2923f83a6984801cd3c3fb1a7e30317de8fda00186d39192e84832abfdb0b77e43c8e500cfbd9dcf04d21d0bc49b4acf908d88a303	1671372041000000	1671976841000000	1735048841000000	1829656841000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
31	\\x55546839da517b92851f59a06eb1987ec33c3638734e76552db05360f150a2bbf10d65cc555a90b53c463905d4418e32e471642029b360a125e5b6dcbf405cb6	1	0	\\x000000010000000000800003c63671eb32f0934136cd278f21cf84ecde06a7a9e8a96133124744b56a88ad7f2f6cf748ce131513ad1b38bf566fb0a02069c4dc7126f2b40e692b22d966e0342fdb625815b2d92fe55fba6778d6b44b1d299eba571f0a877005d22803e92aea8c1e9247bdb4bb4c42c9a6d4ce49f897e0977618f36799bac4b2ac23d9f1343f010001	\\x21d71c5107a3dc8c30632aa22e1a59403b27a752f0e0a4dbc47822d69b74b78a0fc62484b0f140f77f70a4b48cf55fbfc60ac35257b27030e990ea70af120e09	1687089041000000	1687693841000000	1750765841000000	1845373841000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
32	\\x5600f352cd13574ffc7d40c875536b2466d3874980e7cd9c3140cd2f0a66793e6037d16f29296fbbab115e1ed0ec6dc8ea0426f53205a0734c790e21c9ab94c0	1	0	\\x000000010000000000800003be1cd59cb7b9120b549eaed7c3a60146a3a06e7695dec40d20120b9baec6d92f8c456b9f6a60addead9d81025b288fb3da50d71d717ee57332a80c1365f04a5ce5d19175f367f4eedae3d8e3dad5bfe3a73dbd92791ffa426f4b2c1bbaa274d9e6b0b2e05dd778ce9ff7101cfd0cbea6a53b3c791db2f198348c85c055cf0267010001	\\xf88c4dbf30df1735a0a242b047a990664fd1b774101631f6cd6ab2e1f5f905871b09ea51d2c1b6a0a49f2690775b4fd85346f4c24bec844971594a521c15e80c	1688298041000000	1688902841000000	1751974841000000	1846582841000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
33	\\x57dcbeffacef2c57fdef3b33e6fbef20d5796f24728cad6475e7ab7112c6f5fae080d20da4347fbbc98847fd14de6c644bbad75d181c311badfc24c4e753f3e1	1	0	\\x000000010000000000800003b24f63207876163a8553a30cc7a833965c1ccc5881b3cd8186e34ab67d82e5cfb515e0857b8f10f5998ae3b31627c306a721fad5e8dfaab9a2f918c62a6fd0945c0e2923e11b7c6017db8f06ec57e5c715d2f693db176d4a3e85c539562cc4aaed3be8ad76fe9d50af3dfddb21760d35c6600dc44a22d771705fc2801b25d6cb010001	\\xca76c5c1c45937c9af794a7abf5a60a05c1debe9e3fa569339946f42c697d4fd5373db44c936ffaed698c703e19b81575a7d762fb69b4088c141f5c0ba43de0f	1684066541000000	1684671341000000	1747743341000000	1842351341000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
34	\\x5ae0c87a1bd6e77a6864d298d4f6b42cbd8206c2a85012b3430a3123aaa10764f8e16d8af58950cdfe52f65195c08fd7a68bcd12fc0f7e131bfb615e789fe1b6	1	0	\\x000000010000000000800003a76c8d6e8c0f92ba7f556450a420693df6c0bc5a071904865c1d2dbfe05227a75d9d3b03f3cd0e0a4b545bcba819e33b5b48d16978ee6a32595ffb6f2d87647d22c99efa61c46985ad3d7d456e9e1e624b7c62e3317cea3f726ed49c9ff814b004cb49110eeb9704915aa4159deacc1990723fe51901813cf621fa98cb4e064d010001	\\x542a2fab32bd4b1fb83cbc13617764b4961763643abaeaa155a9483d30636a5d18b5a6e349ff2ee9724d812ce2f482c2b38465b39f5e0971cbd5c1406537b60b	1680439541000000	1681044341000000	1744116341000000	1838724341000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
35	\\x5dcce124321617ddd5b4396478027839abd15845114accb66b7d8e9ab7f955fe58a130d827fa1bb50c0942cc60a71ee4ec5a593b4ca7f696037ee259baa85c4d	1	0	\\x000000010000000000800003acb211d2f16b0913ec9cefa7f0a237ebc45a46fddeb17e5fe7f09923e4e647d4573c21c74d652513b59cc390bb32945bf8f3a758489f94e1d6ca8d7c6ac117b30d64df313636a8c99d68b0089f7be435437e9d6c4e3b4e41a20a40638ed564e3b36aa7ff13dbc21132c381716694b5dd55cfc61e9806236726b513fd98ec813f010001	\\x071c8f7faa6eb6bd3ee5ad39555db5e64bc089908e11a2e8e60eed64962eb5586a89728f1dbfcc30f493d8b74e5842d91bd55a2f66f5fa0c454f8554f6e16e0d	1678626041000000	1679230841000000	1742302841000000	1836910841000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
36	\\x5f44148b99fecde561873f76e2dfd62137207ebf841cc0ba43b1c882a2dd522fd030636579883b65b0ba3b0f80551b608e367ad8fe7b54a8358b7927366ea47b	1	0	\\x000000010000000000800003bb714ad558a5c8aa0c83f83b4f16dd02feaf8c2232319e59f176126b7e5c93ad3d21c24d2d2e6b9fd2f42795cff66f21bfda7c3916e1ffb3a6e7842ee8a8ecb1f3dbb2fda2e77dda24a06305a29af57fd2320b5177e176681d2632aa5d685b47440d1f839a193576982017e97a7c301c4cc7f08c86f1b5a2086b3f69ea585753010001	\\x1fe5697e7930bac9ff025e4faba3764652c20bd9ab941c92747ebc41354ca5feee2d2ea6f5b8448fdc2997121c6cdbdba741b386cea64a3c1054d76998a91b0f	1666536041000000	1667140841000000	1730212841000000	1824820841000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
37	\\x608824eabf70bc935982b12389217e31a14535a232626b3fe485846b70cc213ee2078b59e03836b1ba4c70827c091662592b9db078cb462a8348492e59f2d97b	1	0	\\x000000010000000000800003c5f7e84a9b4b9f58df4102b2939164f4add06a41f952c6e913a973740bed18b85aa9a1f4164f342817c3465e57eef05d72aa8093d92565db4b0f145ace10f6d39d017c695963adb245f13fcb24ebe18afac8b6533f67227fc02aca0a8dc02a209e1013b82609d35b45748399072ea16fe1c7727ed43b7bff10c2b76e35d8ea43010001	\\xd4f9cdba0529747772c06d66f9d3e2bfd3d715e56c528cc6293f82be339f463898a78b3dc011fe48c53ad44c63fc21294346ff43576a6f1a782f409aecd78b0f	1690111541000000	1690716341000000	1753788341000000	1848396341000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
38	\\x60004cbc346681f90848c24cf491c6c6d381179a758121f91ff1e0f4e84bf5190a0202e6865f6a3eaafb663782811b40329627bd9c73715ed4baef8a9ac82364	1	0	\\x000000010000000000800003c7280161fa6989b063d5891097f7db4f01885822427dfadbc86d19fe5c6e503fa3ca08a5de88cc48a6b9c5669147dcd65736832948b737f066b5ae4de84e2fc55142632ef60176aa8da31fcb2dd4060a19e894914d7e7053cf23a2807ab0078fc5f74f1f8a35584c12ecffa82dbce7f80fecbc227cdf386b16d2595fcbbf5023010001	\\x5c947f38bdf354b8d97090b4d25bf8bcb8bf8c46c67041a4afdca3f262f0de28ca0b16114433f4b1cc697e5315029a2d3f6bf24b9681d4a79c84456f30cef40e	1665327041000000	1665931841000000	1729003841000000	1823611841000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
39	\\x64b03b8f85296e47abb3e2ac62961b0a923807e206f81de7bf43ffb2b6ec82541c3f4165ceb70f8419e24b0efacd8bc4f3ede2f8c5131f8735440c6be28bb468	1	0	\\x000000010000000000800003be7c6e381dac892886489e65a7aaf81505c0eadbec5c2dbeab7e5c343c58b6a7ae9a4f408d62c470ecaf97ce1b62a6d8c5821ba2ed779c70e53ff813bcc8459358f9f3ee266eafe347d0afdd295168c65df13dde26f928b4f817589cf1b227085e7045b332b1ca4200883fe7d7c5e673dcb3bf4ff02df2ed869146298f066213010001	\\xcc5d0391bbbd9936ddf00516dd865570cb5b99e92c6de06c445ce676b9b45f8023205f275df924885f5595619ea178f7fc94bfbecf3ad253610062c05133f307	1684066541000000	1684671341000000	1747743341000000	1842351341000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
40	\\x67d48ace9189bab0d6f62d38412e6abd483ba6a99e4fc3c352f3d63a6b278cc4909350c91f14e1673572665ee9b0559ce649bae215b64697be2116cee5cc56e5	1	0	\\x000000010000000000800003b59bdb41e1f46a73146a46028f949bbde56b193365560717f9e1d09ae718b2bb94b74787bd3ca278b8d0019632c7f398c734beb74348d8436587d1f6125c5fd7d58d7bf7b489819332e6b4bfb6486119168d60ed24a28feb86c9fccbc212917a8d02b444138ae2c2dc365477062a2039e4db595980a3359d43414efd063df56f010001	\\xfd848be528f55cb0e76e47a1a94e4dcfa53a0e269b654b3043954a1fe61677180faeefc9d1ac4ce11cbd1326fd01332f5d394e3ff57e345e73a83a3741d80402	1676812541000000	1677417341000000	1740489341000000	1835097341000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
41	\\x6a1c4d5f779e1e909bb0e0b26d9a51f79a8d047d3939514cc57b516514d0ef90b6256ade1ded1d11716f14258973309efd448bdce6fdda0de848115c3faaf343	1	0	\\x000000010000000000800003ba9b36e6f38432d247d13b1e11ac8c7bf040b0bd068ab0eb53ffb756c20f2effc0aed6f5bea424f9c61841ae03d2c4ebb6285ea0faf209c5aed8fe199c5eaac1b562b691c136d8f730fb492f1fbb17ab2d8cdac846238f6ce98fb56fb661c1fb4f5bf012ba73295d1e4779babcc28ce3be04030c129436430c74ccad49e12ad3010001	\\x27b37ddfb68f8484e300fd0bf11aea0d33d56dfafb95cd4dc4d42cc65b628c8ef7881860cadb8c9933a224d4fd7acc2ecb80f1af8230f17526b91b9025e58206	1665327041000000	1665931841000000	1729003841000000	1823611841000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
42	\\x6bc07d06999485daec4a07bd0d177fcb8d937a3b19b41458f1942fabf74891bc607a73739aa6c554fa86298cfb1def0ad8cb0c225e6ae751dc20282180312a82	1	0	\\x000000010000000000800003ada8a294d8cce43e4aa7ffaf5fd22419d62e9edc4d98ce623eab3f330595611f680ff603207cbbd5e4f3f40c73555c466a07a5957815bb057f7f5c62dbcf20adb43a98a75f8e12dd2c9e66909ce914956e9421e4258ce85775bf974297836e2636336a3ad7ac84db0e298550dab53835261296da904abca0124c64d112e90129010001	\\x0d71c5edf2a62b32f51579c91c61629d65be8a3683d96b92842b6178044872b38c706dc412ea181d3dfdcab13af7099965e5f2e741d438eb05ec709af6bd450a	1668954041000000	1669558841000000	1732630841000000	1827238841000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
43	\\x6de0c1323574744a4a14115f6fc20bad86cb2be7aad433993ddfa827b8c6a54aa9b89f0a58e4a7998834e5f7c457d87bfdfd55fa78315f392d980036c59f6cda	1	0	\\x000000010000000000800003b3574343bddf92de226c3fb2009cdac6644cffe27b24eca0227b344db653e6c68e48f38d7f04a926942683b1e6e493c6920810815dd6585cf5e83e59274f433e9fece184b702e9908253df2e311821f2c56bfc7c2861f41e4b6353cd993ed9c104448fffdb064b0814db183523ccad0518fb4b06a420a04378ce9cc5ab2ff5b7010001	\\x9f90ddbd96bdeeeef0b07be4da68731eebc6e9950b4a3dadfeb9b6a2d1b374a998184af9834c2b6bf9de8ff1297c887904c0da5311e26c93cdc8a8d15e27720d	1681044041000000	1681648841000000	1744720841000000	1839328841000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
44	\\x70d4705d1923ba7e6eb8984b26927ce340ba22c98d7a486da09c8c021e9fe518de13e98d31a1d9c739356c559d0f5d126e7e78998d242c67e569b5fb0f4adb3c	1	0	\\x000000010000000000800003bc299cf8d92c03ec8e3cd9414d5628e091742a1616195fb7a8ea600491153135ecf2b30cc061a87991f769e647947ed262344f37e4525e9aae7d9174900e7f3c0bc324de8328953bc5142accd03e6b257664b6125b90fc3078942992c26b3d42ac4064fca83455f0968608a752221361808fefaf418d5fd24c71925b026ca7fd010001	\\x2b5611317d2f2a5c6e24892fc0b5fbee541477a8823aa1cbab2eb5a7cb526ecd5fcf53d599316873147d2067ab120104915abd2f2a808aa37f68def4a5dd1000	1669558541000000	1670163341000000	1733235341000000	1827843341000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
45	\\x71f8c44c0710c95df6e5d83b504a8b53bfb8ec67982cfc60f15f0a8056996b8347793ac1622ede4e165306f9117307f6966715f258e7979be0a2d1615f32d0f6	1	0	\\x000000010000000000800003c870e0cd74070761c4a5207ac7f996f583b5f100c776dd4801b0761692b98e543dfb3e74bf88edebc42e9a6cf008e96a34534a7674fd36d1ac6d198a6232bc986b472da0cf46d45b745309c517d15846a34a683fb0f27552034b60b9bab535a631210eeecc98af9bc39d1bad19cadb6bdfa05b26e3ff009a2f8419b3647e7833010001	\\xc8cefde23598e21e078d25f3efc33717adf60096d5e9117b457cff0eb2a662c38b7ef02d466259ea8b0eaf66a7e107fc19aa8dd0071761e6a4be7e3e26fc280f	1690111541000000	1690716341000000	1753788341000000	1848396341000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
46	\\x75e0597f0a2860b68f1cc58c88c56bb2cc6cf3604503b43dc83b3206cca297b57300cdcdc0822d46176a3911093470e484372e08d79351f6588d1f7bdbbc8cc7	1	0	\\x000000010000000000800003bdfc53726817d215bbe1c9664047eff1ae41e64b876689c3c50eb3478a0e5a09cc2dfa0d53d1c92a13d58e0434333916d7041cd882bd3cc423b6237758ee5279e16ecec553f7a29489349f98c7b7cc5037e640b5f8002d4e4737b8132b53364ce368e668e9a01584ee611124f60c05fc213b18079be12655e78a17cb1597744f010001	\\x3884873cae8d0997c64464ddf4106f5379ad98b408d15a5a0e032ab58fb0688e14adb57d702f91ee41ca44235c799b6b4113fb3fee4e19c11136f0390c9cdd04	1674394541000000	1674999341000000	1738071341000000	1832679341000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
47	\\x77b46464ecdba289bd5e8788106c26e5f2b0e01a0678cbdbab265179b8c7bd1a49b2e6775fe41abd0b2cef381dfe465560c69c5025e3b757454c82bacae7fc2a	1	0	\\x000000010000000000800003bbe236e03503faac713a1ad65fab18ea2e213b51c04e7650d5536419963e7faef08e63b37177e84d90762b865f4cba919fec3fb1df5624c140216d11beab84e65d6c3c26af1a8c0ae0adf5eb6469369521aa09f8c322823e51013b5c437f9afd7701610cf0db318d82e9d978f42cb18872caef38c4ff089efc059844dee6308b010001	\\x7639c6d987ccca1e6018efdaee41fadcd581667939db216b8031efe0a3a2a4b531c79e34aa48149dcdbb03f4d46bedd42fd01e8c711837e6689306a7c218ab08	1679835041000000	1680439841000000	1743511841000000	1838119841000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
48	\\x77988e9d8a4d3b96979cba3019fa0babb65544271edc8a197ba8b9e237761554d87bced61819065156838f96b76e45dcc6d9e7ccf6c24302c3167bc5c8a674bd	1	0	\\x000000010000000000800003acf171f9f6dbbc7c785f43f3f763f4d93ba47dafc9f81c60318b9a0259da3f7eddc5ea9abfabb5a3d721a1bb118710aaf221542bba37c993cd08755b1c06bc29dd0bc9048708f74e04e12c29f8e8db8c18a21bb42949ed7d4c91362fcd34e1d464882065862759443922669ee59944691bd76aa86111162c8f541561f98a1d03010001	\\x6fe390170520dc531adb7573d9ea68caef271684b984cfc44bf63677526e48c1d3eaa2f5fabf7e2185d281737d3dad8d4172126bf06fee8b32b6a25921ea1403	1680439541000000	1681044341000000	1744116341000000	1838724341000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
49	\\x79a804a0a2dbf64283742a3f9970cb8080a54be4ce66d226f71a94b948e1f1665dab1c9bf7d6f406a55a04e3cfb3e20b09d050e3b9d1a55838faf7b82fc7a531	1	0	\\x000000010000000000800003d0efe1ec5658bf3fdea41530cce9791dec74ab0cb5707f1bb713dfd448c497e6d5dd2a0a9b2093cfa13475483018e21752d4c3c2aebb134e7ec88079c5d4049ed7deca82244748da7923f422e947490c0c10ac1e4784df13636e9eda8d50989d84af32b5623984ad6838e45d484087ba960a2fe09237d66cf68b29f46eb3d4cb010001	\\x6037cc326877c2bde03eb19f8b7f7c2f331e194f98a90ccf96530b7f90faeb18a1c375a58eef7c59d92429a8471d7e1bbf0ae666e2c0eb073c4f0ca8de9e0d0b	1670163041000000	1670767841000000	1733839841000000	1828447841000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
50	\\x7b8cc7a2b4274565dfc8450f88571dca3149ad47cc1d64b0f572d4ed123ff2a2a49c8d19cd9134ceb50c8c493799c5a741ff28c72fead26ee0c713021d9466dd	1	0	\\x000000010000000000800003e4d39f7e37761b212ba513ac1817d09341a2d0da2a06624413859095ce5b6a95822cd666a1fe281cdb4051c22f73522c997b44cd70e7cb7bf35f8a2b746ac53d96ddc7d518d9cb5da5cb26e83ba66542d85bb3f8aa4903cf9e2a7d99caca59eb510d9c9cbe2a20163a4084724280c9ee83e4aaf9195cd339ccaefbc6c83bb79b010001	\\xae063bb1263d576def63185bf15b0e0be8c2c5b5394719206f4fa393536bf245596366854a20c9815fe74baa62c1758791105d1ce7505879942f985812585306	1687693541000000	1688298341000000	1751370341000000	1845978341000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
51	\\x7d28e08530d035f968cffad274c4976df68328de974b41be0233e57d38cc75b206aecba29fcf2be57f8cd110e5be7ffc38cc9e60095caf32cc9a3f4a3df9cebe	1	0	\\x000000010000000000800003cce866f70efe12f66ddae4e2205a96d25f1a688d9e8b3af0c0bbd23e2b2d3dc4a89cf1b1bce87a3b282d380fe35ad0662fa11b0e1110adc2746130d2fd2048e2cd1a45e96203ad3a0a8bc415f2e8bf665b2cf687ff6abf985f31711f52762d0c12a75b2b84ecbbba5c992f3345f8e9cd9e27d40f5f722e68ccb869339b07042b010001	\\xc87443f13203e710ce433f9b32878929a424cb6c8e5812233144976b18199fe93d5c4d40e6e63062b59d19ea59d0972d7c2bff99142b4a361e769047ca17cd0a	1667140541000000	1667745341000000	1730817341000000	1825425341000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
52	\\x7e0ceec2f40c5d32fc13e46ebe4fd843fbb2f64b5483c1dfb221509c547a939704d7a89aa6d5e4c0c1b35df2c66e9340d133067daacea21a1f524d73fa2830af	1	0	\\x000000010000000000800003a13623e5f2821276b06554c28b4f690c94f677093d7aecbf928d07602a2dd7393d8c5c3b827cfc70fff99a4c7378d1294259ccc42f5df2385c906bad0bfd492881acead12330b74ebb450640de989b80c763f23b71902478bbe19e3cec02bba6570df9bc93c0ef2f68f6a1024dce2e809bd5e4d2d3dbf8d6fb9da187ce84a61f010001	\\x9ad790a0cb096657732e789a485fd4a40de2da2d11717833f0812955d595c90ce4ffcf8fdfc8bcb7e5cd094027f070feb9753240fcd0bcdc87d11efa8d62460a	1676208041000000	1676812841000000	1739884841000000	1834492841000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
53	\\x84d4e192d7ec98ce98de075d9e51adf0abf7d55fe1eefb25d7fd6df1c4e05edc9abf95dc64520c8bb51d331dc123b237fc4d9b1eccf30d3364744a5a08e2420e	1	0	\\x000000010000000000800003ce878fe6a995aed98e343ff2d9df15ceb8f36c7e7ee59546a8434782986f2a6fd302b008449d5941efcea4b7597c68e5e7c26064b5cceaf2410d54bb005f075711b70b1f584cc3a9d3b51702be6199d8fb515e71f9941c7ae532adab25c5655d70e09e3c0d729a8e10a22e11db1460da56d7050a6bffa0b5b1599caf2cf72fc5010001	\\xc2c4decb1bc7f193f4103e87762242edf55395cd8fe8d316658ed13bf7acc2194912cc68063a8b35f98efb6cd80c8f137df3ab43ebc9f1f44af729930666d406	1691320541000000	1691925341000000	1754997341000000	1849605341000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
54	\\x85b86c2ce1f33e31bffe4a2dc8150a1a005132eb349cad73a7dba673b06094379e29e7c42f1f2aa639ceaa9ddc3bc3ceaa75a02dadf9aced333101aeacc5094b	1	0	\\x000000010000000000800003a74cfa918abb5ee686fa997814dcb35f54e9f082c4adb2fedc4c55c220ca2e47a478e9f03c7fa0c4ab449f82a54752e16d77eb7027ed0307d157f0dea260c29e93eb1bc8972be0dbea9fa0ec1ee2c8d0c648f6307e85c1a06596512b1581e83ff0e53e3bf10e40f811ee138a32b3d97b39c4618d18a0d9c1fb10e9500b8c64f5010001	\\x5e333097614a11f9900b7eed16a3c70b54f26e29009f2f634b1b852972310204de6b2f3d42176162ba2bf438a3006477d151e316ea82b4bed59ab09282845d03	1685880041000000	1686484841000000	1749556841000000	1844164841000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
55	\\x876077d4dabeb0aa0a5cff23962130ded07c7f5df17a6dfa48b7cbd37e7ace8973ab1140fcfeb2ca25edec22cf614ef5368ff203fb27c12a9a4c83882e39c3ca	1	0	\\x000000010000000000800003b7019ae5bbb9311a1e6d341cfa28e2a86ee4d74ad7f22b1e1a205e34d04d421f2122041820d5970797531463f64a8ecb43efcfc466f433007b2c7638f9ee95f41a78cc9ddda81815a74391c1e18dfe71cd69fc512265b1bab580f49b0d2c2adcebdd48fe62b241e5e34c51a518efeae0d79545e454ac7e73af89064d306f6f37010001	\\x4ecb6a62a78c8e633e7c62216a33f0aab3762659f4e1e6ae533eebb2a6b5c0d96cac4d70254ddc9f2dca669ed7d7e1e946c444530ec0333a9a0cd7aa6f099001	1667140541000000	1667745341000000	1730817341000000	1825425341000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
56	\\x88b4d7b8dcefae9e2f1ca6fc2725e17709e7b025b057a834facb569632a262ed24cd2d8f69c17da50a96381883520b4481abef4f3093bb7b221f80699db2fa8c	1	0	\\x000000010000000000800003e6dc645a2b3e0b9556c0f167b5095ab3ca9c3088e3fe3a90e0514c73c002ad4da4e57da319c5c39352d32abf6407dd32bded898e77a8a5a1d5ca79bbe53d1b0632330d9dc5e228ec60d43ccb7ac0198b28dfc6dc5edf1ab5f163741360c26e9d6d27d8a494e85b5d32d892bdbf8029f0280b62ebdcebe1dcd37215a77eb9411b010001	\\x88c1846dbfaecbac9506b3d957fba146ce1f82073fde97783d43957d1a9719cd28d06f20bec8f408eebcc42d770cbc9693e51396e8d8cc79abb4167bd2eac80e	1674394541000000	1674999341000000	1738071341000000	1832679341000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
57	\\x88d011e9f05f235d15d786aca6732daabbe30a1b7d70d439c58d4d9ceae637e3ebbfac69b7c9b664cff21f4bd3ddc425ad68a96607d9105801b8c925d5734766	1	0	\\x000000010000000000800003c0e1e792b87b95c37eebb2a6190274f2201135d5e70a7ecbf375a7ba34a2c2df9c3d056924bf0742bbcad20fdd35dd5191e6bea8000900dc42610973ff32e1a4c36b86308d5a4c19108579b7ad6347dfdb8a0de467ebf67d5e5dd2c28d15cda4a7997c8aa3c88b7ea5b0425351912da27dce0e62161ea5752206cb9ce3d6c2f1010001	\\xcfe7de5bd8cb599e9f8349ecba646056c81944f4948a6af8c329223644d45ec11b188bdba91a7caab0df8678a31db63575c7fa86b72292554bb808a2d508a804	1679835041000000	1680439841000000	1743511841000000	1838119841000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
58	\\x89702f5821f5fa134cae380ac48b468655e7bf0b6c434ecf84b2bf2569b88928999837cd227288102601c91f99b8dcb19800cb6d0784e52ba74f18c07b3a86b4	1	0	\\x000000010000000000800003c432448a1aba86d9611765f34ea0746924e50e0b91def22907c6edd144593d54f84d8e716b65ac46a88987a72d5eb07fbbe05689672d6666abeafc19830edf97e25d4a2be73c8866913bf759fa7756af906b7b645ac9f5dd45651c9772ada2afbdd56f45d05020d852d210f7285608c6541167cc720f50f7e74d669b8270bc7b010001	\\x7fe48def0abe5394ebf4bdeb7596b39053293487b72e3107cac1b34430757aaa98763809373343a66ae71b66d279390c1f7a5c05575115c97ff619e9d35e1602	1667745041000000	1668349841000000	1731421841000000	1826029841000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
59	\\x8f107678d5ba6c07de97ab47bd78ed645a193d394bef7ea7d27204c56220dc6e322c4cc1622f9947d602e87972beed1b9895bc6fad376b70572105adbc75cbc8	1	0	\\x000000010000000000800003bf7bd396c536fe69b9f76cce9ca895a5d08c17a46ec84ec696989602e0a32536480f8478bec66836f961951cf83205383caee7a62672aa9df71d02db29f4658c94cc21713909a18c7781a8180ec2556d9798a86024e7a30dfa1ee7af68a66319cf9538f23bf374ae1d03b6207599f68fd4ee5d5247e5ecf680846215419543bf010001	\\xe0d0e3f1c9161afb3fd2074b5fa36c01cdba893c8488799494779797659fd257e4568c97083c08db4658c8cd037fc5f469c4b73c5a84d6590a077de4d4d4e10b	1687693541000000	1688298341000000	1751370341000000	1845978341000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
60	\\x90ec1f5d395f5b788512734adf3fd9c1865596c683d6e79ea2e27beee9176dd469269b48810ec5ad80cae4312bc3a492719b5c71dcdcee601d23e05f1062e08c	1	0	\\x000000010000000000800003cd3dc9026c49e8be66fa42c7db3e02a5e8b0e7db1e37d2af7c4afa176560af02556be632d94d9020573e719f17c0ea9384962a8e6155960d6a79f0607d7d26ec2e9bbed20e3380f2592ceb6d5d596c6aef997c83a3f7ad6f91cd77921eb324928ab3f47f91213f855c7e2c39bd2803bd126b295fce8f82d9f22c452a0c38ca05010001	\\xd3c55483e06407a239d0eea5b96e7cb2b09ec68ef869554377912441f21710a90c9fff5e6f2285a993c9f79d9af59d38f877b9dc52fa133facf359a73d918c0e	1687693541000000	1688298341000000	1751370341000000	1845978341000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
61	\\x93f8b012d95f419b68010e178d3ba4c5f06264a43123c7a4c06816b35c59cefa19907aff3d1d481dc69d59be659776f35c719195499090601fa6e4c99daa118f	1	0	\\x000000010000000000800003e9bfa81d0d5878deda6b907ae3ef223a5a0de86b05f4663230aa308ececef74bc2d5743e98649bec6cc3c74ab6f23ae6d8f062f21addb7fa2d435472fa337f3ebd12d664f998f9b664a257b760011624666fd1a736ff88eb3cd13e5e5bff4fab41fb899421e77cf549c890f18532756264a04456f12013ccc903706bb575bf93010001	\\x13d260506e09603bc2e5d44babeb193e337b99edc42ed1558370ecdb34f414b810354552a0d1dce015d48991e801c57958d1f4393e6e87f20b2e866d4260060c	1668349541000000	1668954341000000	1732026341000000	1826634341000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
62	\\x93308d21b9bec13b1b3580afd36b718d62049c53301c709d034ca52dda0fff1205f040d710d6385c371739595604a44f8cf73a23c71d9f48ebc72104fe8fa9e5	1	0	\\x000000010000000000800003d5574e21807502cfe515c0892c82deff2690dc0cf436cff9cbe56a02e2f809bb9b026533b8b20793909023320b90000846e3dce7eaff66b7afe97afdf68c2e2b3286d7962df33e2027516c4a11a7c1f0f4eb2e3ec075c05900768eeb7e8e253ffb117ce66f09b60b0cea016da3003ae0003420e126c541d314108f8ec43ec6e5010001	\\x2a31940f01df4100fc712bd757010d25eccdfcb1315b8065ed93fdaf4971a3196d6666c4c293783eb0332ca715a10b54b8935a07b56cc2eab072c9e1c316f903	1681044041000000	1681648841000000	1744720841000000	1839328841000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
63	\\x9600b5dbc17118ce9fc249ba65d13946e573f085fb96627d6a886628ad847597c63ee26f874153a894f2ee0305be61071cbbdb1e260855a3053d7561a4badd49	1	0	\\x000000010000000000800003d73d1ff00b03481c77c1657b2424fca6bda4ad9d36ce416a578f68129cbab2ef1a2258b71146a686853159dc69b9d68d3bdaca2c22fad739ef7d588393c636ca086bc9dd812dc044d56e2ce8667297e876a3d427db82d6f3270e4d9e0a328d110825fb56cdc33005d11c95bf88259850d10ee32814bf68d5dbab630d4c206f79010001	\\x8f52dad7e1f6144e517fb905fa256244ab994e1161f05e191003fb0d12985e9a3780113f1d1a05d60325fdca987bc8cbb46c4f03b49f037e030416d886be580b	1682857541000000	1683462341000000	1746534341000000	1841142341000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
64	\\x9ad01a07c64fc223c41fe3f668b185d97ecddfd632cf3795d3627b2e31632ed69df2e16f3c1337d7d6da17bcef1405b5b67e89dba1c53519479688cac57a149a	1	0	\\x000000010000000000800003c38d8f01b773a77be8d24386b8e77d396f4636250023b074ddfb6e8cd641e0197594c04ed231e098c09fc1e91475505a2904a74f300d43a7f806866d7bcc06b9bbfc1d4c4e8c8492c40ae4b604fa0b4123186cecf7cce15ba83cf85e002b939226a9bd12e1d239301602b89453b63f4af3aba2b4627862c1d772f96f52fcf81b010001	\\x91fe787134442eacf1d2617c871cf9b00717347d4a1db9734bf2e289609f683530410ba66a99f49dd9a2dcb3463f7d7ab0d161d3141ebc8de6b0ca05a524f403	1690111541000000	1690716341000000	1753788341000000	1848396341000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
65	\\x9ab0e959b03f8c46b35a0d8ececd8fd0a2847a9193b907140b6a59bfda25fef6a59f3e0bba7c2ad67045c74ff9690af47610fd2cefa3b5d053f6542e7877ecb6	1	0	\\x000000010000000000800003bc2f7b07ce77299d0eab8039a29445c02057caac9002317562f99f2cdc3fe140dc31dc5c89dc8413fefc012f4714f02ad51e869a42b857b66f3491f7e9887528198ad5cb63355b8e6d581d3ca1e1db52e0a926d075aa30862813db96006aab922b358aa4899bc4f950a64487ff3f4effe39ee6e18cdf6208a54ae301f07d814b010001	\\x2917431b1086a412e3a6e21c049eff328060acf4821368fbbfde54ab5524c8b59daccd981991b8d2c66fd026e241fcc504756e7fae012c10b8261efdf7fd180d	1691925041000000	1692529841000000	1755601841000000	1850209841000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
66	\\x9ae80dd924c7dd18a7506187bcb611467472a219104473119b71653293ad56d5a7aaf211b6d93f3b125a9e1ab8d6880352b029ce72a379cd94476bf0fa9f803b	1	0	\\x000000010000000000800003ba66aae4449b5efc2388f7cb9a8d432663587474fd987dd03922c53227129fb574a33989cde9eb6a45a8a75d678d3cdfdc2db2fa19be282dc12600103174962c28af21674226952896860c84f306d668ff2ec20a4b198848f33958894e2f52663d794640b27045ae70b54d1941cb03991ee05d0563ab1bd4212bcdf9fd259011010001	\\x960ab452f80ccf31f217af26d9b4b38d3a86c73f4df413872158793fb23950b8f3ccae82a590f7743ca9a9bd697c4021339bc2b08dc6e559d274fa447d31f403	1666536041000000	1667140841000000	1730212841000000	1824820841000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
67	\\x9d9409e0009a7b4e17313c54b01323df3925d3e39f2e07d04b0086f23a72819415d38894dc949597093b3ddba37e51191b468d23072b770205e714e9e51eba27	1	0	\\x000000010000000000800003c746a3d91ae2c9d96354ae77120376b1aae7f7c17b9bcba9434f4c8a71c1be06fe1ff24e3cac72a8fcbaf78a6dfe94bb5710dbf4a93b52a1fdfcb75a5c77a519d5b51464a00d6493a6c812701be228db689a6da625fcf0fc426705d55d37a0c835e35aab35f684576d29599068d6a736a925e90c8db6d0aa43ce0734d8b3f191010001	\\x37005f69b865ec59dad84e8968352dcef1b13a58b57a4e755bccf77880ce887f5c54f1f7becb3008630476908b0a8d9c64d17cad458c35fd868df73057ef670c	1667745041000000	1668349841000000	1731421841000000	1826029841000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
68	\\xa2acd34c9e6e394625d7b77b32c9c0f8c2feb8886559d4b3dad32092f377acd8f1e0dd8e0bcd10b6ae349b391c514a73d1960f2c277733c28cfce76a9fcf3551	1	0	\\x000000010000000000800003a9dbb9d21cb44adcb49f76a9a8aef413d14f06ce26cb8daaf8c74a1f398577d7fc053891ebaa771cf0b7eaf8d9b10343a98d7153dfdd39ca14d6963787a9806a2e6a78f64623109e13807c96e64043c9614f4ba376a92deecf1fdd7ecf021268b577bf2c63f692c1fa7fb6d91b0f87d6a60eb53f1bca0c19c531e9b1699f8659010001	\\x611a5aae8bc9c1dd7e5d6aafc2b070dfb3ab3536ae78f5a02bf91b247a4b040a739ff23a2bcc937c6de8346afc4d773518ead6d1bacc10ee818d34cbb036490a	1687693541000000	1688298341000000	1751370341000000	1845978341000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
69	\\xa4708230862a7dc5d8d7a53b5f1d2886810309bf0f6d4402dacba3c9923e6928f913dda00bc7a60dab2f6a96bb604c6df2c356beeead13163ab036a11cb43367	1	0	\\x000000010000000000800003b4bbb4e05364fe94860b2c677228496ad08ae853593ab57715ecdabb27f0c583437e68e977e1fc528bd5afd8dccb8f5c55580bd015883e5a02ca355a0e6a80ce3aa02fb2541a04d2454bbba4201a1a45e8af96cb0a1767fa1eac2a1dca3d2450f8192a995887b8be1f617530dff589b0476021982254cdbf418c129baff94f8d010001	\\x5d7a82881554968970a56417e23fb1984bf6ee02d2727c9e2dcfc505a3576faf32a66079693d16b3ebbadc20957a027764351145080ca63f357bef9d7328e102	1671976541000000	1672581341000000	1735653341000000	1830261341000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
70	\\xa6b4f856f2f49b8e7e151a3913a8a4f82274994ba5c15c1fecefe5001839b4672532b9fe260791ebd8573dc54a5c2b61ae0796d0aeac77323aa9de60bc0d876b	1	0	\\x000000010000000000800003dd2e514cda51f8a19ba447a33e6b81e509970d4513f0b1e11c7b2527713417d9f4028f44a890d22ef9c4a5ceef7609df96b10cb18527b99f00e32782b623308adcb2cd798a86c090e7ffeeccdaaa5331673ea6fc27bfbc6074e6048b99064221c81a7363e082595ad21dc4364814c354e91a9164070801fe04a83633b3036e91010001	\\xcb23e54f32bf650bce2df17f911ffc19e96d0e1ffbcd77e11a76d39fd6d76f859fe71963ba7c1837e18f8c7d1ba79ee91fa223de62f02cdb81228c2d4db49f0b	1674999041000000	1675603841000000	1738675841000000	1833283841000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
71	\\xb0dcff3e1d9bbaec9bcd9b6e29d2cd22a75eeed5053b68d0d7c0ad2ad7cd69dcb4ad50599afc9ed4182f38d14654c03a6584766545c729bec5eb6b0de5bef9ee	1	0	\\x000000010000000000800003b83921d0916e0791011cc8c150a6b3f204514a3532cbd9a7d1bfff42516d5e32fa58ae021edef633e7111311fd4f88c8d31fc0ef6e7ed5d1edcd9a206312002081af9d90621c3e473ccd80ac383cbd724df275b02e524be3bd8861cb5ef794a353f8009f78cab8603ed24bb6596679c01b0d9bec308bd04a35b55a4317403c11010001	\\xac814768bbc794f6979bdc2efb8a161eac65d10b7663b1bdf2ace6311905e4f5f524e633ec8ce6bbc5671f6f9b30cac84ffc5f2e7e9ddb26a8b6680818e5fe01	1661700041000000	1662304841000000	1725376841000000	1819984841000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
72	\\xb15811a0ea35519f9ef57eba0a09650c54b1ef92f5000d967a1bfde3966e6430bdeb197149d31f3cfbf6cd15a8c7e905b5c102a2d1bd6e2cc376551330b7bba3	1	0	\\x000000010000000000800003bec53601cae85cbd91f84bb1b60a89a087d046a92b09640433350aceebb533ae7c582ca5905dd7ad9faac4f7c28cd00b81eaea7e7673b369bddd7792b35adfa47b0ada0ee840e86497d7a7e64e8c31427f04515f26eddd12b1d3539861b83034ccdb1dc42aea12a79740d92a9155c9671b7d1599656186ff7ff1a150dcfcb1fd010001	\\x63258a211edcb0c035dab3f6d5d11c39be0d51367e9c4d751d4abad819d0738b7aaecf2d25b7063e7b28d1b0c6f37431d78199a28a17f33ca622e2a8642f880e	1683462041000000	1684066841000000	1747138841000000	1841746841000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
73	\\xb34479d52d6d627e479f79942cdb39ceb5c7c1ee4dbad43e56a3aa4608316596bb950b29157d4c803f299eecc8f747be5eb265b409dd7f42cff7787dffb4c4f8	1	0	\\x0000000100000000008000039ca4efe58a8b3ebd2304a66f3914cef1be8fde2a237baa9e7a04be03a1c71538b160ce48d57dee8cb49b65495ec00f6f1af770059f582c1c955cffb0c1881cfddb41425ad3f4a6a823befd9303fd028eacc1bd11f66d07ec8ce413a11e7491aaca1b4ee2c605c97284a3722282e59d6c6d533105d331c63b511967af5c42b21b010001	\\x3b51e20d278811be90c4d4b79f6c5d40a64b8667cf187de70ca5204ede28af1cdc26eeecb97594848a116a992fec2654b0b7971f3433a7ab211b633a18afa701	1676208041000000	1676812841000000	1739884841000000	1834492841000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
74	\\xb5bc753660bcf635a9c1ec5bc42233e65bd1fa15fed3f7b3767409a5e214aa69a18fdb94f308fd8b477a90e4cc77f4e4b0fb2ab8b757cfb592082fd1b6cfc717	1	0	\\x000000010000000000800003b2c791263674a42d4cca216015d36be850c3867b33733f934fe598f73273088439546076ddd970e4a6cca408091eeb995e30d3dcdf31d05b31e6413eb33e62ef83f83d515f63d515cc376a520900d8560f55afef76a9617614a444298932f6bfaff18b7b0166602a7e6fd5d23e01e0e488735e9b9ce6363b55f73f86751f34f9010001	\\xb4f21708bcc2f525078e3c6ec52194771a1edd379903b0bdd045066638f3a8a0ff76223c20cd6f97997626b07b443eb989924db54364b518f605f5b0a5067d0c	1673185541000000	1673790341000000	1736862341000000	1831470341000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
75	\\xb9c873ff38c47db7dbb8b308ca3d2eb6cdeb2f68cfccb3d4accd1e9ab96e3f11d487f19840dc5cd242c6d67a6684f072c69d452a435afc8cd3b3bdbd7fe06750	1	0	\\x000000010000000000800003d4e83ceac35ef6fd6df48bcab4d5b1d02fd86943d74d6ea28006feb10da76a616090a4445c405ad060e1c5578a4acae71120d1254c0ed09d3979b073d4735e5764bd8eee7d91b4e8d8ade76e9e7f499564e28d910d9b1e9a15353b9cfb227d3c2b74fdb33d7e984c4f42260c05a077fa0bd8f079231e061a372727aeee8f9be3010001	\\xede915e11fce4e594b38597b954e6bd0289f14281a2627cdd7ed6438cb86eaaa89e3a9be3553de9910d12346d2be5fa415c6351789d5534bb6faedba13877b08	1667745041000000	1668349841000000	1731421841000000	1826029841000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
76	\\xbb90fb289858ff4e31fd0c3db7a074024c587cd010a7f10df6c43fac6e19bc76c8e06da34e2030fdfca4e129b3cc59868097c351e265304cab0c12973a7a5704	1	0	\\x000000010000000000800003af2c3b65a30f29dbbd195a5131838b705d2111db3060260304128f77d06e727d962b28a66ffa59761ea1b7a8bef0ca046ef86a8cd5dd824b1e386eed195c6cccd966cab366422389267bca2d61c73386ddb8b7c58074a141065d477a247c40b376474b749de357d6af52b924d98486e0a5178101bd5f6e897a85eb3553e49faf010001	\\x47b40ed51eabedb601f82b18f61c9f5cc5173c9166ebb71433e7929a115bf69b233f09e2aeb29f44c69f7afe1ebcaecefbbbdb85c8a3c506f8abf99e236a6f0a	1664722541000000	1665327341000000	1728399341000000	1823007341000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
77	\\xbca461c843e211c68010db4b0ac33a415447e8690ace04a3e34232d70e7182de553c4cef8527b6b6abf18f106de06d63df063c216ece74631e9f6842c7fc4ccb	1	0	\\x000000010000000000800003a2c7375f6f0bc87df9dc62e73ab0e12fac68badae3e6ba491f380402ec85676685a433d96e7a40641a0dd6349f6723ce59e4f3c324b505f41911bcbce39026239bc4af4da483dcfcd21a91f7ff1763b8939b132a2a6c674f51172628270dcaeaabfe2eb0ae0bf6c222b7bcb40c86aa999b49078c62564139e757b5142298d93f010001	\\x1b72772e3f6c969a8cf1624780fcec4920114e2342ccb0a786b1b29da6f400a841f90f043807cea03a50d833f65f88dadc251e0405af18a82a5344fdd74e8008	1672581041000000	1673185841000000	1736257841000000	1830865841000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
78	\\xbd80b89683462f3ab6523145f0dd568000f7818e5ffb5a0a123ef643c04d093c144ec723ce0719cd9a20f286d1477e7b979f94ba1323e9bb4a18906d9f1dd73e	1	0	\\x000000010000000000800003eb40a8ec3b5646a21d630a5863577e14a1e01bdf69b9dc25323ab20dc3ff131209f621f604d9a11cd5c1d2f7bceee750198c31201879439c31ff67d6a383818d8a4fd87db58c660c6ce5d12f097459b6b733e5bef0e1976d10e85a9065de40a01dee90436eec90c132e6e6c1a2548e8a7e080a48d434c798c12afff272b6fc2f010001	\\x021951602b3bee4182538f63e8102fa1455122f8d1947f7695c2ce8efaeed36d3e29653ffbe6d39a0d9744a71200763ef684f0af34ea34f27020d950719de404	1678626041000000	1679230841000000	1742302841000000	1836910841000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
79	\\xbe88ff948846f5b1f2b67fbd09f2dd3d6f78e1e1797acd5ebc4a04094145c2e6f5b043a48eb5fb5007354c83210c59e77ca038bd7aa429a6c4e224ce0b7567d3	1	0	\\x000000010000000000800003b3d4117c0d00ae711e894af33155287dd413b3ef5e7b69874619fab82a8b1397551a9f331cda2e908a691c51413c0e1bd0becb59bd2733b9c37b23b7fb63c89771efb7b2beb255bb7a0497957b2b072c592b3175308167d99c2d5d4b42c81a960f14d6f634c2224f10b06181d00da7048d037789ad0267a84b88daf7ecb368fd010001	\\xf33fd99428657b02394b0aba9ae22b9539f7894801728e56be5a2aed94e7ab183a1c2a24109c8b09daa6bdcab83f819fe80dbb527423b9bd2c54edac3967860f	1678021541000000	1678626341000000	1741698341000000	1836306341000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
80	\\xc1b87afffd4c409b95b77f9e51b081fdf0f29b36a57efec51f5c6b0e29df263d06261e9322a7806f63c05b19426ff0a71c66f1ae7655220b07933fc219cc3d88	1	0	\\x000000010000000000800003beb348b56a9130c90841db1b0e7e650634f5e27a0e4c10d75d6b7935d2c49ea967312e4a64acc5e33ceed84caf3e2365d4a0b5e159527c1e4dc420847fd15af265e761a992fe3a2205f52c6016b400ae33a3229080141ca0c8e8294c1aaeba35a867aa1fd7a81adf2dd9a854a9fb19848dca246550fbd645abebe801d6c3c2a3010001	\\xcb3562adfcbc2c962cd4f9031b052e4cfb7b22e21a484cc23512d6862498c6e350bdec36d6dbbd363ace32f31ebbe0c64225b75a38818c6fcefff60f8055b302	1670163041000000	1670767841000000	1733839841000000	1828447841000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
81	\\xc964fde578044dea725717ea31987201112d7f699e6371c512a454c3ceb7f134169166a964c2665c94cb9109a9c7b2e8bc3fc57f7d54e80f780802ab9458d584	1	0	\\x000000010000000000800003e324546e7a7080ec56e718de1fd7c6de423d9a0633adfe2f27fd38ba2e30e5bdfdd0a65ab49257826054a2431053ece3d27d1e0bee681a1c22fed987e2cc7b0a65ef37f2539b859517d82baead646c487afb9728eff532e2bea54f5163fe31ee7045c1ee7cf60a6062a955496292839db43e6157a19800826f65a8c5e9ec14c1010001	\\x0fedcc1800f5e42a7d2fed296e5f87834978218b2767d57c57b7a41387b5a5e2c34cc6ef1941546dc990a028fd52257274d80bb4944a9df1d9278974dc2fe002	1678021541000000	1678626341000000	1741698341000000	1836306341000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
82	\\xcf0482884cc0a7561deabb3235b07fa5e02744e9e6dcea267d407b2480ddaa2d618612f809b2113b4fd8724de63e45751afb793d06b72c3e74173c3094761855	1	0	\\x000000010000000000800003da8cdc13b01041f4bd21db62f1329672c39c6bad437ee804d57c96c10e457e04747cb43686d03ffad12571f0bbdc246e7710e360c5ee75521c452a60bef0f9b3f0827545a36ead648dd00b3951b6a87aea53ef553e054383c48ea18cb6c4388531ba47a8e85f4e9b16e1d7725402da19e206e1cfcc7b9542cf794234930548a7010001	\\x980058c78ccc7eff6e5514a336836e6524f4af0eaaa2c78a88d9bed2d9b66f711d6291449d9fedf56af09a0c9c25d97ba574a6d8215073dc3fcdb90a3c5eb604	1661095541000000	1661700341000000	1724772341000000	1819380341000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
83	\\xd17c0affbfbbf04e4c2aa47e0eb127c1e291750b23b485fd58b72a929835b7373b45f1fb61ca485bb53b7004ecd5450784903cb9234d14279485417daed24ef6	1	0	\\x000000010000000000800003b682643f861f21a8572ca0d8710ceb370606304436ef0bb85f24196346d36e0739bfade96bd0d7f368a08c2afe748491fd0a780fde5bbf4397d8c2143adeb5e5f1dd8163a623c9120bf6addb5b6995a56496415938eed724e05ffd916cf636f3db5e5ce5bf551ffca53b78bb60966827fdce0efb10122d164d2ddf198e06a261010001	\\xd222c9b5969a19b9b4021dadeb6d888108f07fd98691fc03349ce29ba68245f118c9dd408efde887cd2d7efe418e1435043f223b7b6a4f617b71aad11319ed06	1681044041000000	1681648841000000	1744720841000000	1839328841000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
84	\\xd1c0e15177757721ae4d3d3db2ecb642b007e397c7fbbac428aa6197763c6dcd128fb13650428fd16f7b21049f333c1600ba0df7db533ed7bdc290a5dfa14117	1	0	\\x000000010000000000800003b2a76e8ea7ef69fda511efc779a932d4d7b389853b1edebe92c24be6fa106c1ac52647dc5a3702d7650129debbebaff46a017a8f6547fbbcb315a6edc1dca60af203470cb9ad40e3f8326a5581ac0c4554554aa937f8579eebfc9bc12a14c4c54b2a65667e01533a4864505834b6977bf3d25ca543b717b101f13d5b6b35db4d010001	\\x0d247eff82e982be6bc3ec12256c9b3b6d0d66143dfb0adced7408c9eb5d8ed3d1dba9111e3bb0c22f5785387d3d6f619a064ea04ef91143b1d016b5230bbf07	1689507041000000	1690111841000000	1753183841000000	1847791841000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
85	\\xd2b0eb131d73ce64e48349804b2c1e4bac69b65b5ac41a3c883571c20fca3a663c531c9339ed453d623f871347d94c968e0c3488981e4ec4c55e23d27688364d	1	0	\\x000000010000000000800003d92e355443b14bb8101e51df1fb60618266801bcffd3f167ce80c8aad47688fdd1ef6b9d5effda22e7f777927c682b70969ee3759448e0200e03ac68ae84db146687463d83b3c02e090f73109f53bb9e19430c84928760cd6a087dda35edc9db7e93c011bd3e21b84dfe390d35c81be9496750bb222f1859ba89cdecd0bb897b010001	\\xb61d5af199eff6961e3d099d9636b87fa7d6ef3fb4cd7112ba28cda61dfe4a44c4b5a33b25305ed26766f2a690ad35f9c744300a190aa599fe70d001dcc0c505	1681044041000000	1681648841000000	1744720841000000	1839328841000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
86	\\xd34065e566a63f51382efca30159677113027be416b20631adc0ae487d60b744b6438603211e223a37faa4cdc287fe572c67027ebdbf295dd991211cd839eda7	1	0	\\x000000010000000000800003baca660bcdbda790a470a13928d3a4ad1f457d0a409cdadefeab4fdad43e567f481611084b2776e05ec9325c8df2773274c661470662938caa07af980bf3c4c1ed8fdcec26a8cefc7b6bb1ffa2e0823c6e049629bc41e931518e79cf1da0174e0e54514ffd2ddd9884d536daf5c3a620ef0943ed92cc252eaebe80c173b05775010001	\\xbc4c73d6e426359f4493f6a18c6319b967114321606a6cb371e0d026253c680df1a78273b02d5b0ac0872cb44af83b43279a5b19c9f8915268ba5d3f625c0709	1667745041000000	1668349841000000	1731421841000000	1826029841000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
87	\\xd43cf5c674b97c3388863b3357b5db0b683a528509e28cea1f1c7f7896786b8d491bff9ee3cc238b7e2bfe12672d1c5f60f0d6835eed783086afda0f54a54989	1	0	\\x000000010000000000800003e2f28702206ccd5a8f44496f11779dbba6bf504e19f77e95abddb0d3147e8559a673f075e0fe9de4ab3cd8d72c2fbf51ae11653c28bc4436e93d86a00948e9f7fa24a79d86d819925fa23a5ad6d9dcef72fabe6a23afc84f5ce9357882b1f48d65760fbb6448b0155215e6c3a0ea4d4edd769f44a4f0e1d997869a49d13ab4d1010001	\\x9f3d974560e9e326a54378a71907587944a26b964e88e0273e8f1399f24c075f47b59919eb5ba2e96bfb6b6e80b6833a3c37bd94c1af495ccd3b31c51315880c	1682857541000000	1683462341000000	1746534341000000	1841142341000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
88	\\xd5703e522b5335234426e123dcb8944ff100a60e0021cf565a7d295ea6d3f21acc275c1fd84d19fbdfd0dac7b9c85d7e63df2cb69872f58272aa5fa06cd6442d	1	0	\\x000000010000000000800003c84b1b67dbd4788483156ab7e1c9c0b17112abf4e7d8df6ee0ad66121884a13f04fc881a9ad7afcd47c2402bea2a60b9a3ff43567ae4615b1913f54b8d3315da3e84c7f2ae6127f6afe24fd59f3e954ea444a7814fc97a7fd8aaefae3f595a79e1aca127609ab391df4da1075f5c0715a3e168d87f9f95fa3778826fe6e5b1f1010001	\\x7100a4ab732bcc4f043762e37290c5a07993c3f31e5f57d956c86868c3d149a3481aba952f256fe6251401c0b1bccea98c2173420dd108f6ad73befefa42f302	1665931541000000	1666536341000000	1729608341000000	1824216341000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
89	\\xd6b40bafab512075c95dc538f364443b06e69b9a0476c0a4c6b1c86afcbb11a58697867e4058c80f237ee250c8ad18a97fa540300e0be909cfd8793960c4ed90	1	0	\\x000000010000000000800003a1c78b2139c51f808fbc8d14d2456cf49abfa1c8b7fad9c87a4f87279d3a8430938ec2293c504f91b48d1e728386d712da9393eda98f75d158dbad505f01b6b4bc8b985b3f8157cf92b403f9bc58386f5c7c122ce65a9b2c3a12d2249d087a28b0346aa42b2588f3273aabc51bdf34977f86b3bdfd1f30ba7edad2858485ba9f010001	\\xd4b4ffa878faee0b74243c9ce4f66a5e031f6ab36cc04c6f453ec603e14a5ad68c12b8876fad763575f8269391305a951c4d7e9f373109d5bd902ffe3796850e	1685880041000000	1686484841000000	1749556841000000	1844164841000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
90	\\xd7b89ec5954599c0fd4668e4a8dad8ed5a254a2027503628ea9a23d8b28965bd6e3658be358eccf00006e5f505cf8ca3daa10a66990cb6d09c58b4e6e136005d	1	0	\\x0000000100000000008000039c8be21bb8f382a4900abf48075d82dc5a6633ee6e268cd12e9e6816c2a2acce341743f05250ca54a33bfcfa615f5f64bda821a45768a815deebbf9c514caf1c551d668c00c0d14bddc0bdab21d315cf7dd0af0729494f59fd4f55a5a2578e14af03d5c206a94f20357d473bee346b343229479de12e1f5ce9b16a7d8b32c8f3010001	\\x932da917185243b5580554b1784ef79b2283c8c7e01285d5c84bcd141baf88dff9637b5f573403190c9d76266c65b6854484c955b824e64b3797c74fb7e99a0a	1665931541000000	1666536341000000	1729608341000000	1824216341000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
91	\\xd7b87f540ae0c61d09493fd27c6d86ab3cc6a23be5a8594d62b2935bf7fa27b6ded023a35a643fd651a580b811a16385cf5c695f679716fbdcfdef4908466451	1	0	\\x000000010000000000800003c710361e0989d97b6ac05266a61cea4a3d399dd0e74e62ee86da21ea44d6de757e0b6bd9847f06891b4a93885462043451fc91aa99c765bfbb612607426080fa767df7bc0a9c054d80026210c9c1d9b68c190d00a7dbd56eda5a2d74a95bf32c84335a859a1bc26ec189fed9f5850fe668dc8f06905a7c176977d94cff8a3465010001	\\x32827ee10fd10dd2c1ec3976b7a44e80de2dae4be4136e3a181f4e107cd5e21cd0e1805cd346dcf8f332df7fdb6572dc6887ee788daeddbfda6ab592b8ef9a0c	1674394541000000	1674999341000000	1738071341000000	1832679341000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
92	\\xdab83aaeef7e1f949e1110f107236d49318b57afed7e6152b139d5b5b4e2505f99ca3328d4b95de134e0e49f4388eb55fc57ec95b01c3cf6734a53195799c1b3	1	0	\\x000000010000000000800003d12dae07a419f6bc184122ef0601681c375b0c892aef8767e275a3f85bf8c690b7910e508e65b7f8e7793216ab5f0b10f23f53f078077c0d94e985b9aa4074be96fa6d33046779fa75510c6edbde929d1a4e3f3eedd4da262d93552c06a6cd7355c6ac0d3aae101990fa025b50acffb9ae85c72c2778f554d345a4ca43b6accf010001	\\x3ec4778499d77c905c1941cd8a15f5c55237c55518d16b76391057660699e1c84255d9100f226613ef81253905deb844215ff0714ea6522656ef00116a89f80d	1685880041000000	1686484841000000	1749556841000000	1844164841000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
93	\\xdac42d48a010a6e18c4c61dce00282737c3424c202ea91e49958e7fdd8b4bd1eb99465c5d3d20f35f122756e8fe10ae0ef15a564d433009133ce3204d84b526b	1	0	\\x000000010000000000800003e234c867e4c81bf3bf9cce106c0bb3667de38b863d52e275c4becd18534289773bfdc70a375472935deb650ae7259d8298ac8366f92368d687b702eb13a46667456896f3e1cef965bdc6b148f4b147afae149293a990c9bfaf71ccf3847b3aa67701494cba10daa3f5d112f6dc2c9274907cc3e160e75f105828d8a97b4044e3010001	\\x6983ebf4fcbf21907b3d6f5f663a18fc5456f537b056b95435033886d2654ca3fb2daba70aa5fa52224ce28d217547c03e76d831f672e66aa9d8429f5d801f05	1674999041000000	1675603841000000	1738675841000000	1833283841000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
94	\\xdd1c0e7fe367341cec09329261465f341d5c56b4207208919d9ccd0852888272b9101b297696ff0706b074896e96ac1dd0e67d60190442bf4079a1e9e25066bf	1	0	\\x000000010000000000800003ab3b4a95e9008797b899332d5278f3d146d5c4ce8032dc834b60cb403abcf853bfb9fa9bc0e5331cfa362bc519332ece158b4b3692344d320f5cabe50b438d84301881563a8c5d2403e5711a506810480ea0d624e8883831feedb064b71ac6316b4b66636d7881326fce8c3f75708a84b8b5319b14f675b5a716de2f169280ab010001	\\x930506cbb2585f0c1b965619142f6f31bb9ec3fcc84b1836a86d3c8b023190a75dcb4fbe1bc3c5033a67c7b064aaf6312c60ee3fb3aff342411e1657d77d580e	1684066541000000	1684671341000000	1747743341000000	1842351341000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
95	\\xdd08c8a96cc0efa7199ce59daff69228765b04b331c5daa16c77582778801a89c349b35f96836020ed447a49d32953b3723928db6501950607a3337877b0abce	1	0	\\x000000010000000000800003be18e506925304517aba8020404261ea805ceccbc5e966484a5c5963c0c890e580b79827cab8c6fdbfb3109daec8d93a32f4bd20180230bbd66f50faa7b9e9182f9838420577b01609a37365779eeec35e26696f390780c4494c1961fed3aaa3333ca0877ec273524f86cead311625820f587ec5983ecb9587879b36548d32e5010001	\\xca810565a5310a6030fa2d65c3a29999f30463c898c552b6ab33b66008aef3d1eef3154b4ecaa083b54c856084f2a88ef86177c63d9aba6a7d462b2c94d9fa0f	1673790041000000	1674394841000000	1737466841000000	1832074841000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
96	\\xdf547187a66b82f6c44f077c7b5dd79008307bdb792484da6cb46f7ab97a092ab4938709370467b71592ce0a96f34eb61c29e4bde2b687a4d3e3e32193fbdb86	1	0	\\x000000010000000000800003df107f4dcfb474de29ade3c808e836c747b8a400f2571c3e5bfb66b2494265697d2f47a87f1a1ab461a41228ea088efbc9de5967055ece55992fb6d88270a67dfca7474b8f07c76b9d7777ed17c88e7d182552d1c7d509ef17c1c06ea0ce0ed022e4aeb1397f73ffa802217d2d787e3b7c055f755ca6a9cb64e8840d0e7bed7b010001	\\x2cccff3ab3a42db397ad4d60569d53fe0636e9605369e4bc4acbc64a6556741601e1ec3f33bd5e2eeddeb74dee60f29c8e61e68c12a702c3729fcf86f6b09b09	1691925041000000	1692529841000000	1755601841000000	1850209841000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
97	\\xe10808370ce4e4558c85fb9d34e4fded72632131f4377bc0cc8a23cd0b1407ab9b763214756b2f6e7f700696ade933ce604befe79f71b933237621c8f9286bf1	1	0	\\x000000010000000000800003c76f74c6a1749e29723eb0c9a6018ca34b3afff950a040890f5a72c51c6f501df110f337105d952084c78c40c8518be8596980125578854b4a06630ee043d75026bf05e05aa85308b5504b9599f20922bfc1f6374995002ad21979854c9ecf7f26f881046125e00ea1d437758abfda390970426327baa211dfe20e69cb175953010001	\\x208e51697259271ac267ee9ec72905ba3e58f91f09a8f56110a04db052c01b31584569fa328a82ff6eb6fef3b3026f03fd6ae4a407c485a7f07f0daa53b5e206	1690111541000000	1690716341000000	1753788341000000	1848396341000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
98	\\xe1f0ad432c9086a96395c8c8d3ac5e2c83c4aa1e0eda93dd45b8098883a450895119d87813a400b489a24c880161e2ae4fcaa6de1153714451145c71a5c8d006	1	0	\\x000000010000000000800003e615f526aa3b83e208d31a126ab23623baff3446d82a3c99f47b32ae95a75a76bcc2dfd44f4ce1ffd0ab4cc976980f9828e0649334d20ee20efee9a1fef7cb50d5447a3e7eec9f084ff8ab9ec06ab182c38eb9cb50a36de85a0bf16f7ac40e3e1cf618511a9fb3c5ba080808e5aecd23a13c3ed1424f049cbb4928bf384f741b010001	\\x225a92b69ab4d5d0d491c213385e253732424cc0e7ac65f038f44aa3bf9fcb54378bbc82a84f6bf6c9f0a0daf142556c4b87eda7f9e5d027edc7c5ad48e3cd02	1677417041000000	1678021841000000	1741093841000000	1835701841000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
99	\\xe4c07a65f2474d88167c7dd3ef3b16a432917512a96b56ccbc583a8fd5f7e0bd8c34f8c35aa5d1f52c3dd2bb9a5be878feefb21eb39b2b084efed967801cb11a	1	0	\\x000000010000000000800003dbef3a7535450fb54abdccc6d257f384befc73ac52bf1f1cdb4389799849577560fea87eaedc3d33d71b1ec6f119431d6f52e0a5b9b345f8fa12a4708c0d6293c1b5799d587972290bec12e25d50516b29223ae11814edf471fa018ea7401bdd955867dcadb99317fc981fa4838dbe70274733460111c9a58332caf9d1ced14d010001	\\x629e3ee8d7fcdebd91ffead78078c07e196b2212d8e09b4e552f97a94e69818b98558cebe1f9dde339b8550bb666cbba2d671127cd4ea54d5d9975b156f0f808	1667745041000000	1668349841000000	1731421841000000	1826029841000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
100	\\xe680a017cf372566caaa58f3ae3746f40c644929c935ad1667fdad9a24af49cc57e6d710c08e9f4e4cb32ff86e0e91739bfe6ca3f3833d45c1ecfe4509a985b5	1	0	\\x000000010000000000800003bdd85d248ce125a899ce14db83c4e717f44a26cce19f19d9fc7eff25c393a5d4f78e2ad6006e522f682fe65c28757eb9756813c35ac05d3d401292aae59ef521b17431a86b5a2f2d27ca62eccc7c5144aebece67c7d49d8bd689ec4ab32a16af7975d2f7c2a8224d539a2d067bdb95d7e15bbe37fc4a5aefaae88250b9cc4a49010001	\\x9034056fbba378cd252d45e7bd1f861bfccd07fe7c3f37ec7218fe7391cdc81efd402749f3c2d18b739ac4a19b1c7aa049911f0f9b9c536000f290f84335e609	1665327041000000	1665931841000000	1729003841000000	1823611841000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
101	\\xe648d9285717d9139d027df1fa1f2ca86c7b147834aba8c2bbe4f9bb246d727471a34625106b82b32ed3cc25ff09d6c23e8559408bcd108267a3c638e6413977	1	0	\\x000000010000000000800003eb0f2a24bd7d6e3946e608c0b30870276765c968e8553cada3ba36880de2dd241ab225c664928137450845f1a7df7eb60ff2da6b228c7645b2c2e065d69adf8b2737e5df5e57210708d547dd74beccfe4b86abe9d73a92bae95157e7ece57d74fd94173fe2b839bd6cab432ad5ffd5a337f3fff71de4631bd58e0a06d30d6f3b010001	\\x0f8abe08a6bbbc9a03ffa51440af6555fafbffa8f61cbcbb71b9228f99eb090a7b0f9ff8ceaa60dd1b5188c832299b2eca119d9f51176bb1aee173d2cb7f4804	1661700041000000	1662304841000000	1725376841000000	1819984841000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
102	\\xe82410ed8dea8806c7d79d737db823356f32bd6cd0ba7e703910d44839ffcb64ad8eadbf4306ef7658993c5f19c79afa4eb9e8e8859380ea3821ffb73ac6d8b9	1	0	\\x000000010000000000800003f0106f5f67df1e9834e65b51bf11a6a1e7e041c308448cfff4d60b2cd6bffb242fd02a4d12252b470586474f73b63184be0ad22e9eee48fb4d94b2bf647d830828adbf4927938849b32dad0caa5d117f90836687f31c9ca5382df6d5f5c2a292183b4a153d588145a8b3c71f4daf44309f308a1886cbd43c29bbbab486ea7c01010001	\\xaa6f47c21776e970023b4c2dea5234a3c777e15e68fa01be86033414255e4e0923e7f65164c93daea7bb0d3b3997c69f66fb585198391ab55d99e797213ac608	1682253041000000	1682857841000000	1745929841000000	1840537841000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
103	\\xe870da756fc8735ede8427514a914ddde71562034b353629db143316b7cdba78e0934f92c0f51a8008fe8b3aeba3abf05369369bd945843a3d2078a03e36a86e	1	0	\\x0000000100000000008000039d19fb74d11be66e22f0eb9ae7eb816dcf11c3d0b25404dabec18d9bfa18f9554df0ed560ad93c94c20265d32d720e78e4e9e356b04bdfbf710846f7153c129b456d5c35f8fa8f422c8656a329d0eb5c95af8a466fce1c93f84827159988e6e8fc242bbde85b675d25f5d69953bf0094152c351e15f52e3b119635a8cbd1fa05010001	\\xacb0e37546c876a2612cf9ceeff46e8aa2fcb3c6f1a38263571bc333aaf08e0f3f9222d5b1d28fa6d3d77b3f3c9865c83dc215599cebbfa62e897b90bc115a07	1665931541000000	1666536341000000	1729608341000000	1824216341000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
104	\\xeabc3455993e78f455b1e810d1f69e305fc38f8ac81ce36f639c367961ff10df13ac6cf2a0ac0af03eef4ce324b7133036aa7f438657546a80ae2677d95c7f91	1	0	\\x000000010000000000800003f065179f005139db1c5c2679e084fa7c4b0c9319fe0a1474f76731608795fce7782956b2eb354c5bf8934fa8a1864e770d3cdd3eda546323f2084e561cd8e3cf6b9bb5556b63934fc570d39dfc5e4c8e34993f912735655bfadfaf8a5fa00b98cc6243da4c72484c068bb39719d6299e18fed3ef68bd351c23f73e61e515739d010001	\\x5d1642eade38d3f9014241a676a414618c69e00e334c539aeaa3028e722c314d4e080be7fbd4fa332c2036146fdcd9c8c487400f7aaf1fb048972b8f1ab12706	1662304541000000	1662909341000000	1725981341000000	1820589341000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
105	\\xeaf848d8515b85ed83a0f2a6366dce73f2a569e31a46de89eb63a8437e47d0b1c187d4eebca2be52bc5165c03543b85cc7a5f3ac523d707a6e5f96df0750b4d5	1	0	\\x000000010000000000800003c2860d7cd8a9448c626b0de99589c458633274c2fbd666b2ab3867c468b38a04c25bb4edfeed311d719de4024da294a86973ba3521530c1a32af90a97ee8d85ea62e22e6240d231356df99a3613b046267203131febcc3acf78b2c519891944617463c8c239aa0f978507bf6a3d47ab7d6512c76c35a68be0b7affeaa086db77010001	\\x1f6b2a38caa1b6517f93733b8c8048870971d072b7d95808d51b8136dcdaca98f449efe24540693a56b655efa6a940c646995646741f9968101700b4885e6601	1691320541000000	1691925341000000	1754997341000000	1849605341000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
106	\\xeb04c1203c28be6b1870340d78915b47e8805744310fd1e2d7b0bcf6f62ea6e0f8735e7e0cc8a1cc61c15f67716d10b985a1cda523732ba56ec96932fba6507e	1	0	\\x000000010000000000800003bfc8ea52d1cb3679aeb1aba8e03d5d6c4c967685728a837507a100b254b943118b5b632d01302eb8d3a9866d81a7514742b58f000c928f9301f90d010c9141e632ce22ff534fb3df05c98cea6f2a7ec58508182ed85f8e06cbf89d0fdbc9a34533fb36aeac792b3b60e96ab7a172a64a5b26ef67408ae023f4a10c90e9ddcf6b010001	\\x0f1464a077a41289a23cf081eb3d6e0ba5fd63eb4a4d27faae15d69608f0eb9494a62c620b827751b41f8177f1917b6e924564be4380c1625741210bc419de07	1671372041000000	1671976841000000	1735048841000000	1829656841000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
107	\\xedd071d54123c681b6857f0b47c625389faeef9877c6d0a52160760f3c32d1369f3da095b031bd35c00a3ce90df43987e9c15ac057aa1e79ad3de17ada881f50	1	0	\\x000000010000000000800003b39720c60b02f46763c27909985790b0787624b7113f0ec6517e2beedf4b854c2b9912a8962112e8018dc2894b87dbc378a5e962633a3681eefed891ea290172e4cc37dc0bb57805ea399bcfb15d21f3636151ff6ae5e188867ef3ed569d6770d6df0ca649da6eb4b46f087613f1266b39279ffc02ee8f60ab4a9ac2bf48f75d010001	\\x1db38024356ab3c32c2ef0034bbfa0b5b16c10473ee8711a83875c1cc4eea4eb61cba3dcc3cff8506dc13e82b59c42a73031880a065730e6f687b5f2c1512f0d	1679835041000000	1680439841000000	1743511841000000	1838119841000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
108	\\xf2c4559891f4992b52dd60b28d6f4607e4879b6143d239bf301f219d470a2ed2c0a46b8d5b1f54d700d0f3689320eb84402c19ba7f5463f49f4b297fd7e253ea	1	0	\\x000000010000000000800003c2b04ac2e19c3c823ddbd8f96481820bbd51fb4554c9aad2b2d382f9eaea5f696d8ba5733b5fd461f8862c6fe9fa18ff7ad740b4a5b30c555bfe5e4e57d857752dd8aee91a7d3bea5a0a3ac0c40ffa33942c06a88de7aff62a926811200ed0c539191a335c41b36057fe5b90c6f9a8db5f46d73c82d822354ac563a45880ecbb010001	\\xfec0fe84a98a98c24d3c826e7fb597ab7bf01a1683d760fb323cb46c6296bf0f546187039c307ae701c00b53de446987b9276a8fc21a84d7408df450cad1ca03	1680439541000000	1681044341000000	1744116341000000	1838724341000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
109	\\xf610d97ba415887c90536bfcfca276046233fb67b7a844e34f1d51d0275518c6697ec654382a56536b9cf43865fbe8c9e60b4d36e169ba6fbfcffab51a802979	1	0	\\x000000010000000000800003ee32a64605c06ee5aeaa1da0059dc04ad2044021389fa7b3762ae7e114d3cd0e2f713f9b2e85976a90218c4f8175caf0a8f1ef795c4baab2506b581be0bfcb7440323813788ec411eeaf07bcf856ed05ea5274e3d85db1982386cfe3fe5e206de844ed6a45f79175ac1542fece0c031eebac64a05e5c842b72b0a3f94c82e12f010001	\\x97ae49abe496576a7740eeb3b167f5fd21450ef079af9132840b65d7e3409bd3676fc9f38d5ae5c0e3ddb6f70f26e2d6cc0610396f67235d6e41744cef14c50b	1663513541000000	1664118341000000	1727190341000000	1821798341000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
110	\\xfd18968dcbf703a8c0c287e6149ffc8099aa8ee843a2faa2f30c1de2c4c438042d8b06d6842a0e2859138dac217ef5e6e99f5ee4e77d1a48f085655b5e860287	1	0	\\x000000010000000000800003b3b65818784c3c7f765e6cb00b41fcf6a4a7dcc2c6127c7bcfea51a9bb88545d24f8a527e98cc14a64a4fcaba3f1b26b7e63f271a8d950604a0a2110f92270fb609119f63e0bc8da06282a21887a7cd94506238b919613d860fa84da54ed1b9aad97bd61f28b32cd1ea809db6e201382443c28c174ee6a67e1c023b5ba223243010001	\\x112521a4552d42ce864aaef168215a454b74f2183fdfca73563141c5052f3aeeb36de8fc13fa8c7c83f1526cf66ee63794db489ec062446f35f1081160fb8001	1670163041000000	1670767841000000	1733839841000000	1828447841000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
111	\\xfeec2175870bdb5bb091a4f48d2773c6083cef4f48865cce23a0903a229cb95642febe4e6c324a94125d9e94e351a919a5c359cf2ee45760c42c30455d428f68	1	0	\\x000000010000000000800003e8e3fd7d34e88250fdcd20192ba9e39260da3dd45151690432b4ece9d46e72f429624371b2b34767d4808d32897376744d36cf830f0e02bab6471d99465489ecc915f960bd1b940396d0843d8bd0434baabb8ef52bd93c892378b1590567b7b7aa77735574c9441d39e87c6256aa920c70f70d9eeb709bc2cadff55a6d920183010001	\\x1e83bcd07ff3ae21df4be05bdee31a6246e60f52d28d0d196830cb5b25b32e545428351c082f630b447537036fd136473f6e42c40e8109253dac58675072dc03	1673790041000000	1674394841000000	1737466841000000	1832074841000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
112	\\xffe03681d6e1689c409fc53aa52fb1682f81e45f3e9fec637dee97dda6c7e4cd87b35fffbb4ae8be1156b76154b06c914d2ac5af1f8b28e4dd2891557ea82097	1	0	\\x0000000100000000008000039b6ebacf9f550d7ce34ce9e4a6813b89c89e9983b83342c1a6c3cc61d7f6ae2a8e2b2fd771c5d94b83e4e03dc2497cce56242f6b2bf6f69d9705fdd458132f8d4136df6e17b4df143078f23bf92eb4c46c289a42620bd12463fef42bc463a83fd5f21859f311d97bb767b4de9ed18c55578ce0ce349797af4c4227d059b67ba7010001	\\x2917cae99b66a84e1b334978a50bca5e7f8de9be627b076ba288573ba23577bb5a5f807d1a766185547141b166762f075d2a8d697b05be0674a15581ae5c250f	1690111541000000	1690716341000000	1753788341000000	1848396341000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
113	\\x0149856b733eba5d18599a21ffea6a2ef21a8b270f0a285af682b590af96d9a0eb151f14ecf97a5d37eb426277b079ddcb89485d792200f32fd5868e80254d35	1	0	\\x000000010000000000800003d922589e64054f65129a8f1fea43fc2f407adef6bc759aa8ed1f54bd88f0aa8467890cf07076cd7e36e53f79d4d590cda6ece3ab1d2ba56bc9635ad3db72528b31982165d97eb857f733b64a9cbb5250a758da4b8babb3d0203fb3c7891e49c3b6169772dc196ef988c1f7d6aa5ed28d1e6a0eaff6ed7005057cd11d1f155347010001	\\x00a92db7bf6780b99a8c6a4c6ed905085d70abb027982339e7b5a62fa19942bf87201cc77cb9c1b254bcd40eda9c017ca1ccecf3745051f71a78fdec1196280d	1688298041000000	1688902841000000	1751974841000000	1846582841000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
114	\\x139d354ddea1cf76def4e744cde8adbb4fcf377dd7924ae5c890ee3dff5f5d732c5b897eb3dc06f6fc49711274546fc0935a6d942aa00dbc8c6c1c57a7516877	1	0	\\x000000010000000000800003cffec600b5987373bc780a9f00eb48f1cb1ae92baaf5b1da899799d8d968dbc37feac095ad3d9a51181bd4123759fb0b94c09882e7478a608387e63a7aabd9755ceef61bdb2ba63b8690416df88440d440a46049c9ea66943cff9e25819d6269e4799a3bf6687d90c599c381e4bd0babb7a5d3ac214c84a3ddd03f3775001d43010001	\\x5dd1fcb2116a8cb117bb01b7bfabadc4067c3eeb996e95c82387a21c71d89026396a6936f08efc6e89b45751a265c7f96636b502f5823906e9c94974feb63e09	1677417041000000	1678021841000000	1741093841000000	1835701841000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
115	\\x16eda6f594cb76f04f1954559146d9fa425290fb4b272d3471dc742a2d9881ad6a48d75095077c22ee44fd8941c52aa62e9f4f2f41ed6175b450f6a807e68b72	1	0	\\x000000010000000000800003aca243e4544c8a91f80be748df596fd9367717c414b77d033ef982fff1767a7a400611ac9ea11f7fa0213fa8fc4451ca953af79541ca645835532aa6cd76a0b5ac7cc3b4136de473649402a4c6c37631f2b4cbce6b854607fda9cc1a8521cf2bf2c5c4e745d5e4c992fe2e2b596c942bd9d0f0509f7570a009239ea6bec936ab010001	\\xac6d4c3586b8730928c4c719e5409e69c418f7abeac0537d5c327eeee6ac430f38496465ef482da14bb6fe9f1ac57c6ea9c766a3ece9c95536f58b3d4d577f02	1681044041000000	1681648841000000	1744720841000000	1839328841000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
116	\\x192dfb88d6c8b96cd87148410f360397f7f97d48586bdd1ea0c7daca8a6dc084f4d31ad8cc6b2f2defd8f854cf14f80624d969e7538d82ac77f49d9f44c10205	1	0	\\x000000010000000000800003c85337a91bbc7110b5264b1b7776dd65dfb9953a65b77d45141a20f8fd95ad46680036d29f93f4bd440fc7b94dfab835ebb95c9cce581f70319392158e0e7203fb5c74021e81fe29c701975c6fca402f39015fdb062aef1db966293f6f7cecc9a6fd0b0fb3d325fe323de9776938ec7c211f8ca3724a2b42ab01ccd740ad156f010001	\\x47d57e9a8980785797ba8b0187f0b3fb4040f62537cd113d62740b93f1836771c6db15b7005326d81aa410b3c21dd77ef783d6c2d56c0bd373aa05d1c883700b	1691320541000000	1691925341000000	1754997341000000	1849605341000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
117	\\x1ca512025f582ce5fc44333c9d09f6e978fa003de5fc0712d2860e0a9864c12f98053458bf3f7f662bccd0f9f939d02eb369617173cec6c7ab98a9610e4a1c2e	1	0	\\x000000010000000000800003ced9094c211041c082b3cd4f0ce5e2d5110dc57ecffe47f562670e99b7e414efa9586fa261aac48eef81e3f83ea6149936320e946c9cf6ec4742e6761482b26118b1674f6356f04df959f55d6751691a1e246d64f597034e6a640f6f954cd4f8fe01f13ad2cb58b1892502943d0446504e0a1544617d42c81348dd3a4b4faafd010001	\\xfc202fc8d3d5cda4e70fc7894a0356114d033ff561ed143b1bb03883e07d43db6b1ff89db32fc6882417491c4759c31d27d484201f32f8819fe1611891b2210d	1669558541000000	1670163341000000	1733235341000000	1827843341000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
118	\\x1d6d471e6ab498f5ac5a80cb1b6d5393a5951225e916245fbe1cfc9567b02341fa0553e8b9ebbef0e3c39b8425ac97b849fb47ec443476c9934500e8bf81f683	1	0	\\x000000010000000000800003a1e8caea418141a3379810f5bfdb30bf63a07de833c4b76a6a29d2d1245cdc083b55d39f5836fa7f19dbc8fca542091ba800aec485b717e89859f1e362a72aae1ed8dd075be68ae08fd9396878bef3b9c50fc6e14b065f0d4b95de50e8a376eafd13e396f8ed1e4f4f4c8e010338cb6dc662bcf5d54ccd549ea5faa023b15c57010001	\\x372a8c61cf5caeb04a23e6ce7d115f623f3404212271538d639ccdd669be585e6b689e74e918aff07408369a1b50a705e8527e2a6f23afeb3779ee7aa9bcbd06	1673185541000000	1673790341000000	1736862341000000	1831470341000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
119	\\x1ff97999e1f39c70f3cc65134579a510b50151cf0b856681d082c451bdf703a58b3a6187a4b03f79951718961a35be59db68664577dbdcbb805239dfd6b77535	1	0	\\x000000010000000000800003d05b53bc78f15aa1a45ce664d957440d7b7b0d6ae773c81af2437cf712b7ef79f52a617cfd8655f7a347b21b50fd7c7593e2b25d013b96619ec93310327bd56db708f514e5ff2ee102ad568202a9d3627f4d635435c32b1bc5b47aac44fb3f423d654236fbce4ef485224c4a033b1e431456c7905e0d15ed01387e1317dbae95010001	\\x89d5104acacf7a7b405f11584d4f92ddb584cc17080c1669fd88c01a237946f4b114b17280a923df2640b4809f36c8f5d93a2e6ae3797061e4287fd4ed569a0a	1690716041000000	1691320841000000	1754392841000000	1849000841000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
120	\\x2061e3cb7077f4965315120bb4a518c64534947216ee2117472735bd8e73e5e19fcb468c17196e2de8d18394b7715ec6a4d77d4d22eb5432c0084ea6eaccdfb6	1	0	\\x000000010000000000800003a62090054139fce9840ce0226f026ffc773e519a66fdab7469c76105096a1c5ae19d2b1d5fb5d0c0a4acc18dc85d719ea32a19a71b1162b7ed76045ed3224ec0f7f71471a99135da303b22fc439165a4b10d93656836933ce76296e1cbc43a57b95c224d1f3cb877d4ee42e053af7b7cbd7a5ce3679637962a249e639aeac1e5010001	\\x12d2a8652d68bc7bc5da2e39e510deb81b515b9ae681db77f03c3d676c22a398670fbcd30b7573fe8a9cde8e2d43b07683e19b4d62ac55a65516266566bd130c	1660491041000000	1661095841000000	1724167841000000	1818775841000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
121	\\x213134a698fc1b66733d612d7be76f92dcfc950b78b707b4be1fc4d269d66ab60e6246a548757dbbc2c982a037668ef6e7b224011177cd318e7109616fc1f54d	1	0	\\x000000010000000000800003b4d319eae2157a9ff080e93c00154f827e447264fd26a5a2f4fabe71990ca92963c9c2cbc1ed650faf2dc78e259f65c28157b07a9d2c81f4d9073afa22bf7cd55ab85f7376a638309d6e6b3c9da0734376b1ed3bda9905e7ff1728a7e3d844d2fbdcbecec42b7bec186811a1a15fd18f4854357b2dbd9555d97f6013e34f2061010001	\\x4184c5a99f48e88cb5b06bea7abf44e0dc3c45885d0c4b3d758811408b5da9f7ed22491916146fa2a196a48081109859cbc1e4526af69c275eb9ed65097a300a	1682857541000000	1683462341000000	1746534341000000	1841142341000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
122	\\x2119c7058f8d0dcd3c1f063ee05a60658284879cbbab7dfba355cd576143049ee89efd487ffb09b7d0f1754a3dd98a6942f68199e7208787fff4b8a6217396fd	1	0	\\x000000010000000000800003c56cc026ee4e02677c7399e90210a11cfb1a7e601bf9ee3095ac19f6d80e5ce4e1257714170a0a7780553a52ba674ba7921634b243db257bea6e69ad89183d9ce8b8da076d62fc1d67258ff8ffa60533b6ec6cf6e78c428468dbc7a8f8a297eca349661b42c92ddf597767dcf7896a19f2a22345bbb960898affb14036ad7bdd010001	\\x85c1609e27a600a274821319ccacddcc852d4ba73421d4ee0223501cc1c21cdb2de764434a198eb4a5f3de3d02837ecbd3c94bcc0c0ad26d7abb315813f0390a	1690716041000000	1691320841000000	1754392841000000	1849000841000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
123	\\x2579725b447d36df86e3fa54b294967923f988215f280404def2939a47c85f1578c10b12f4dc39b193d857559a78ee8e41266e4ea53463b547f6bc87cbecc0fb	1	0	\\x000000010000000000800003c9cee64825291f14f12e4e46fed746e9cd31c99705539995229cc8ff644e6c04b6b7c762542061c263dbdcc8945ced2b428fa8490cfad54fef33cad570f6a56a9a7eb368e0c6b4a4233d867674f15b47a8d61159e672cd620c0a8351ae7969ad1d86574bc5af4c7d666506353f0d379a7bd0e79fe9f6a58353ca4c6c292db62f010001	\\x573eda93e4923efeefef426471a6459a526dd9aedcc14fe905fe92d5a1544a4de940d8d274ccea440bf5dc2097d44f4c535485a21aa67ce8b7646e1be920a40b	1679230541000000	1679835341000000	1742907341000000	1837515341000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
124	\\x26f9b6d586634a83f6dc7b9fcb8ba74209564e00ee98d16b306baceb65e3cbd934f40b7b47b2e262e705e384e3253f7e8231325e5ef34366c8266c2818ac1f38	1	0	\\x000000010000000000800003c79804f06331fbd1ea73c9f372565bf10dd0867977ea8c092a759062848ed76cb3c9d8d37be83a2af96eba893d1247a8338d14893034f2eb185669b9a8d66d91e9d328c4c955830a83f7c56a15cc39cda3fb21a76d98346e5d5dd08c9a6f008f625148b3c39a3867e15361827118ace9cc4a72b9b96e653dc38bcd510675da37010001	\\x02a9f9cca16e38471c8fe54ff26cfc899d36b1f93362dd3cb0e374582e4548c2ef06706a29415601596f2751220f0e70667da42368d0f68d502dac396ebc1302	1667140541000000	1667745341000000	1730817341000000	1825425341000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
125	\\x283156ccf62e8d2566259d847cd5741fa2004183574cef7ddbfa8d9f933477ec962f10244e4612c7251f9110aba89c35158cef5090b368485a59d4405199bb18	1	0	\\x000000010000000000800003951c842a07e85c253f61a1e01b97da39326f016aa1f3b583c7ab28295916e0cb793a83b9d7e115b3a09eada1430a36620f0b92f4d53d15bca96ee6b082cdf385cf1020cf9e512a95249573e1ef6d4da54425ddc17c1cdfbb69e7a17998e0a44f6f1c546fb708e1a8e5d7253ab3ee1e489233fbe9cabf3bd158791b6409d95449010001	\\x6f6077d697977291925bf2fc01a134ab6b56f75a54fff8a543a58dafd2711871135fc0762474671857d0d684564ffe0de502f5c70c2766ae5d352fead735b803	1685880041000000	1686484841000000	1749556841000000	1844164841000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
126	\\x28c55cc798bd0c6d1aa4a5cffc14ebb28cfffead901729b1cb2917b1515c387d7f871a7c9d1919e6f76b73199aed8befae1883d13bff582b1229229854dd33d3	1	0	\\x000000010000000000800003cfd0ab846a9df0dad47f4f8e25699eb040a43d87d7e4d3a94a85825142f31d5c2efb4072ec2549fa9a8ecfef2539b047f95ad355ed0400b5800e9c15b970137495f842585d5e62cd8d93057cf6157b945a58076b40e038faeeb481b67a97e92b45657058862b7a3eed7c5aaf73b766616a4ef0ca5cf85532c5908031011bc4cd010001	\\x33670d21259e4266750eeb0edae579085df1425e9f74a1334a3c4a64610d389fee81c6f3a71f723131e454f2c39f9f174efa0d5b980e8036b773c5bfc534d109	1682253041000000	1682857841000000	1745929841000000	1840537841000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
127	\\x2fa90b1eaa24461986972cd2a991d717dec3fafd751f097509c077130e1d95d4fa189a32e46fcb8e326c88bd30fbf3f1b5078c80e9cd7c6c71a8acdfe105eefa	1	0	\\x000000010000000000800003cfb3320d26b28543e6c0f63e23a8a36fc1a7d5c77a6844a2f552fe111ce1c0ccb0c5f755b386f670779ede238d6a6a4439fd5a393f45c7862b701e1420bed75850bc719cf176f951ecdea5591ec621007f2b0708a164427d2a10dc961b32c21daeba7e059a21a3594cbecd11c0dc0f98fb5b155c2f144086873c702c9356391b010001	\\xfed68225a87f94084608938ec491ec6532100d7fab5e72b42724fb5d8bc7687d2af8e36d14e7af7298f233e4f8be63b60edf8df3b2cfa8c475753a6c10aad40a	1683462041000000	1684066841000000	1747138841000000	1841746841000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
128	\\x3041a893393d09c1ec0f8563d914c274ad405e5f1e7ebd79010e93bcf45b0bd69f34f817f1a40711307a4c2b829b70c96d50fc7b6db6e4cd13e54e1877f037c2	1	0	\\x000000010000000000800003b74972fd6652505a7c81e3109b9abe6c156f5bfb10e14f4e17452d7b5c6e183e79ddbeef0c62bad154d9db0ddc60646255564956ed53668fd9d291a10de0b96c0b1b83c28776c626697047fa313739e38f05f16bf8b1be2b87d9852f56ffbde1329df4b00e5757f58778295f0ca1b8e1c06c0944a30670172d496c29f0ad1789010001	\\xc259656c7cd8bc3f2e946f59dec2f7784521c3c1b37bf30c16fc2fa60fb9012b5d8b643aaa54d701c2ce1531e2750adb8e931a3731f3908c92d311920f410804	1664118041000000	1664722841000000	1727794841000000	1822402841000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
129	\\x344d7e0d70e27468392cb83a338bc2e1dc3cd239e11e48951e723733574bac9cc0ba5d304ec34a13c6ead23cd60d5ce2a8a1cfb517a197b61bb4f1af47b598d0	1	0	\\x000000010000000000800003d01236a4aa748d95d8b84e68d8686151a24f88fc990363bccd786449384f01a1c49494fb8ecdd40d2f6b54739c3559ca69fcc8b8d15fe1ee57ee38e95e5fb074c9f12427391550afd974b0ed988544169c46dcd941a2dd382a1c3ade2f005cb5b796284b21ab6e917d0df3df2dc15ce60bc5615fe7eee5c43d73bd379ea82799010001	\\x02cf2018f31c829bee3761cb2505a01a8e18d162fd3b1ae4fb407c15fdbf2ccec467600aef39b703abe787d6318f90c01e5b975857d3fc927f0881e47bc5da0b	1671976541000000	1672581341000000	1735653341000000	1830261341000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
130	\\x3585d4244f8cf38af4483948f296e32c94d1ee2b2793deee121f7b17b42d6c0c21b452a915ddd504288b193786aabafe166df27d4cd27fa6d25dd246b77c2e5d	1	0	\\x000000010000000000800003e61f025aebcae4f84c92d079083a51d15fdb0db31824eb59a57c3d2a941d462c777e35d825d58c37426dfcf83e951e2656312967f958bb61acb2ce47ceea565caddf19a00d42d1fa518ff192eddc37d55293e270445c187d5288d10e7b47f2e66433851d490062ea43bf96d825629286dbbd0e9d5492255ccd987f8317096383010001	\\x1a622637314e94ba1cd0a031f9a6be0ed185951ea6a6e45192067b524e253827bd6576cd533ac7f56cfe6b8d7942e0dcd41a5a0f292913bd1ec22051e7acbc0f	1684066541000000	1684671341000000	1747743341000000	1842351341000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
131	\\x376110e1f20eb931de7386131ed7e92cf3720e263a0fe13c5bd5050b5292b8a69590bb1eac7b988fc9944097ed8c12709650420edebff0bd9fbca3180586c1a4	1	0	\\x000000010000000000800003e0cc90c88e718e8326e17d3b099ae7724269b21b2b4acadfdfcf0ba9bc2663375c153ef8c795899decdf8b48da020612dec1e21432ee6e4131d181b9019e76beb1b00355fc8f603f94d64210e361a2667743a90a7320e17b6ccd2449d40309a9d9313e3c479ff8d21dab5658214022c33cccd21ec581deee837a59ba7f64af3f010001	\\xe5ba6fb6863191748156cc8a9164bc81135d246b12be2ac8d0fb89ae195ebbebf23cdf5c01984a12ea3a3ab370ad6fcb1b1d1f64bc3a9cbd1c24b98c05ce510e	1689507041000000	1690111841000000	1753183841000000	1847791841000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
132	\\x385527f821174b456290e2ad1eeddd469c74ab67110a66ba1bae329b1b4d7438482bc4da31cd912c6487c47a3a6e64a30d85ddd4a7bb1b5ef01815e500870a83	1	0	\\x000000010000000000800003bbea4a2c383500aa93eed3a6d52b5ee56d17b4df42800810220a7167ee4bc2eb23fdd01527247ce29341f9dd5ec490640325393ad95fc6aa0d0fad17533a760b50c9f21903dc29b6e4e459ee29d259c78dfe1881f8e05e88ded05296efac27d4c95d7fdd6fc485fee2400ef4daf2d069c57bb573b39d433880350675d8e4fdd7010001	\\x4034ab6db31d229651191f43a9bba2a0be4a7a8d9b515ea20b2a8cbf0f9e0a769a5eca990729af6e6e6300409e9facdf62ee79e6fb331a51d27a12fa8d321b06	1666536041000000	1667140841000000	1730212841000000	1824820841000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
133	\\x3ab590ddf1b3cffdf119d9d63686e191756803d9de78ad9a07aa818d8c1f191e0c8b6c9bb9ec021f1f48a7711d1bec0c1b8448b425198a2c20b6fda22b2d0c11	1	0	\\x000000010000000000800003b8b28c7e0da996d8c1636bb196ace868d2a5a2e67ba3a487b9662a3ef47a976eeac4fccdfbd2c091cd874c0be8ac121418d02dd5375be7e51eade44d5114af941ec01c5b0dfcd2a76dceb58011f4223d14a6baf662b43cb987e2d234fa0487d5e4781df07441f5c91666fc816b750cf86574f2910b2da7c19f120a32c8574cad010001	\\xb3a2d14b4f275c2d5e7d9ed86e1c66a589bf52c8be9c3583760b244b3b689267637619630fe66c1a59316d3c3319e301492f25485d4de62e487d95b6b1cebf07	1684671041000000	1685275841000000	1748347841000000	1842955841000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
134	\\x41f9e10aa2711418d7679a9a8ffd6bee02909cfa844061bd43122908b770ca5dbd519ea2098a8a5ca75ddf6935a1596e0f9c35423e3ac9620110aabc7ddd2be7	1	0	\\x00000001000000000080000397e467076bb8b515aacc6f3f000db1afea208b78b2cf44769f7454db4086c919670b39d785e133c2e62b4d4351b5561a4fd6468528d8f00ddb6af5c77fcf0c23969cbd526c451a22c437c75724cafd579db9ec0a8f59edc0ca466c7dd5d83cf3e931a55b0f6425fee21fe1de0dad2d6ab58f5c259cfde74d7a843ad27bbfcf1b010001	\\xb14b7e6cdf643e05c75ecabbe17d1c2b673e9b95330070bcc592bb18473ab9292e3fa55460b4e1d0bc3422b47676c065c1052655e0686b11047f607423157403	1684671041000000	1685275841000000	1748347841000000	1842955841000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
135	\\x448533f1382941e1def4534b62bd4ae4094044d64847c71fe9d6afe11e9894a44861a3647984244e5d4d0203bcafffce2d0d866a45941f47efdbab32fef5ea77	1	0	\\x000000010000000000800003b672b0948c09a6aa613247fc7304f00a18278296f7a9954231c3f0b2d487aee868041cad4470017839cbb25fe5622cd8b6047606511bfccf2c24dfb36a6021efebb3d8de0e4719ea38c9002062befdd27a56ba45ddaee3de928f9e30a5133bce851227bef93e0935f655589fa74e5ae31c0d3c67f9a6fe204d91af8d185d019b010001	\\xc85b528f393fdf20804364684ee0c474e178add90a72fa5680d4db7063f35739a90e865112e34f8e72f0f2d4fa5cf93ee82b967cbaf01cf4b4e50055f7a2ba07	1674999041000000	1675603841000000	1738675841000000	1833283841000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
136	\\x47cdeb0391ff9a5040c9ed0eb953b8873c0e7309060f50d50559d526c004655a350c2b59d0bcddc7784e7c617b882c83dd24b549f9f4e06ebafffa2abc5be731	1	0	\\x000000010000000000800003a2b4bda96e7da76d59afc0ec367d2e404b91a864de85dc6058045b7b64ecccac0348c0b2a3ef89036dd97f1c1ed9c0bbf010fc079e4ca32b9797a01a2475ef8505fefd9a3a56a01f0b3ca178c8d75be076f14543c23200884a3cd032ab995da00848a73120d95781019042c11519d2c8934d944d645d62182f0cc0acf862f731010001	\\xc24a0a4acf00dfa97fd93877744498cd4418ab2e9a11aab8985a7778adf829820ad9fbf9b22ebe3eaf5a8b55340249c87069eb6175433c27e70bf65a5462670a	1682857541000000	1683462341000000	1746534341000000	1841142341000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
137	\\x49316330493e3b63da2e3facc0250993c35487e2ab7939c67b9caf927480e07565d700281ee071e3b48b38ab5ce112e595d8c9571fc989240cd703e27855e569	1	0	\\x000000010000000000800003f087053a3973a5218303023c349955eda383cacc52a07e2713fe5743f7172161cdaa63afabd988ee2b21b8c30adac68f91be3e4118bdf3319bd0732b55396631d69ecb3d497240e123ac7e48d18f5d873d20c96f43fb3259149cf549141f0ad3f7371095f16c25289c9ebfbc02cdfb5c7679c0cd7224960f7675ef0a3799797f010001	\\xcb858816524cdc5e3cd481dc88f428b06fefa5383236f39da8ef39f41addc4434ddadef399301da31d293e324d29ee9d2d01f9b5ad6f2c4f8d493b193578780b	1681648541000000	1682253341000000	1745325341000000	1839933341000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
138	\\x4c39043eb5f9a84c02a031c9821d2f4cef93efa8ed2ea015e988bf5bf263dfc4e18a29f53711a2cccadd582328a84d21c1dac97f0c773bd366a7ab10efda01d1	1	0	\\x000000010000000000800003abde75b1a5aa6a76d2d8c5754d283cb48ce99fa20ea4bf35ba2a216b01b258c99c57fc3e05a383de914ec47a7d1b0f1464f619bea1d52f35dd3aea9c0e71a2c4ee1b1d7586e0f853a2cf75afc439b07d9be13060b730c51a4c0984e499f0940d0f835c888b26a758a70545a57cd3b6f8ac1194b45119fda1d5d12546fad05091010001	\\xb26de45447b64be3fd9b6647693caf27492df0f48f34deea01146e505604ce7e56bba92c6448f9a64484acaf3397d6b44ee50f4efd506e22adb06c0052ae5b06	1672581041000000	1673185841000000	1736257841000000	1830865841000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
139	\\x4f51c3e753b18ca2326307c46dca614f41ba7bef5e395fe9b63143d614f190ad1a3906e2349cb390dd6f7cc7f8af629d409c8773bcc99ad753ea108cc67ae168	1	0	\\x000000010000000000800003c71e416573a527f2a2379bdff576c2970c619d6cf746af0fbc9b14f78c373620bbb0914402888634c754eb5ee4d0214cda0d1b6700c6da4fcf434e1533287786e47d9c0cf77c26a26a67a803a72e6b66ab6110b6fe7bb359b1744e6f0b72f167f745023b30eb7fc6e5daf6e79365c3745f28465ab95430102c868f9ed42e7429010001	\\x8ec7d4e8f0a205be92862ace8967a5fc373251f95d723a7612ce1597f7827d42fe168f19cb86798d2ec422d7d1515530a49dfeb14d8b8e27f72f7d9dada7a20b	1686484541000000	1687089341000000	1750161341000000	1844769341000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
140	\\x51754af828a3b44d92e100a51e458f819bbf23ed0a71afd4197cc06ea4c566021c7eeab83698db47a46b5bca302cbce5899aadcb63d0d96d423ce306b23da494	1	0	\\x000000010000000000800003ca00798b863abd9eaf51234c59671461a83d5ba37c3c26bc8d9ec8e7cb9078a81cc02cae6bc72165db868f57e1fb7aeaab81743a71cd6b764fcf6f845faf2bb9c921b00b32fe9c60ac5604ad5bb3a293139e24ffe5cee14a21bd0c08955cc95971fcaa9a8cbc06b1b72eb2c2b41b3b2bc590e07589e47b6fa7a6106d36a0066b010001	\\xe1ce0ec1b6a5b69e712ef3c5933f7ced92f24c70551fc2e1c73905566746f322166a03f8e3159ef7509df2f1628bb21c596965f1aff4d863a6d1ab82e94bf100	1667745041000000	1668349841000000	1731421841000000	1826029841000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
141	\\x54d13d4c41a920441e6057c92628279f2ae4e18b64834c524d0f87045adedc525afc10476ddfaa607e8307f8cbf2a8001d6fc7ce42007b7582e938458e7ce64e	1	0	\\x000000010000000000800003dc9af03275784afa3c45e846f3ef1123a5c455fb5c1e7a4de14db3f306e84d70d6a48cdc963929ab22fd9252f51d4070800395c44f394fda265ed8e8171cdd3954bf6543d7910eca1560f4e2f5c5f66cb5178ba05a9db3ef2aaea49ebc15d8d43c2cd7ceae06bda444724e7612a3231a7844a600b79fbe8db246686872973e9b010001	\\x21c6bc61b292a229d3974979c42a63bb174240e6f673bc53e19d17f25d91f2e089f3adf1965a44b6ed6a65a53b100353aa2d537ea172ed56b4539c6d362c390c	1685275541000000	1685880341000000	1748952341000000	1843560341000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
142	\\x5869c8490a26f1dedd250afcc787be9e94e981b87c87464f0dac57a804c6cc24277958c550df4f289584d0b692d441fc9b2bc9f63ec6fd30820bf068187aa93d	1	0	\\x000000010000000000800003be7dbf8af2907e3de812279751d9caa301abbde5f1df337eb7adb6e156c835aacb8f08b759e349c2b5074c565d1597412c7a89ce05e5fa979e56ec7e4b8fb43b6ab12f7a3e2e330fc46e2faf4a372c685a505b140dde0cce4eeb96a0e4541c193dd33358c080762a357df9673c642ec8d4432dd3a875f75094a029e4d5095d05010001	\\xabcfcdc5704998d5e6ce8ce7430a50e93994fcaa4b4510c446e908ad1e526c4943eaa037d3df26b5ec646d6920d6207cb278c4dfc413afb2d752b69a7cd97209	1687693541000000	1688298341000000	1751370341000000	1845978341000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
143	\\x59811a5f7c3824e5c5a24458b856ed4bc9f12b6f96372d30b05179fabd66c926eca41bcfdaebda820148b94636f80b3ced16ca64b256676430efd77682b45103	1	0	\\x000000010000000000800003a7f25da590bbcec8788edb55bb0b28441940cc4de25c298c56fdd5b50e329b87dd3151240e98b146cfa78a757d5128e284e982b58dcbde689ce6c658bd2199afa692ffccc28b011b242b96667c5b8fad2010422a381e5e5ad3fcaf9ed334939d650ddf2d358d790d4f7aae97dffedb206435c76194747c3287b196d7f1f5663f010001	\\xbf696cedeb5d3a7b0a7ae7089becd95a2d7b69709b448a4a677b6388d4e58a008fd5b6c9727b8fbc72ea962458f281b12f91b4324a051a1c71ead57fa065b100	1674999041000000	1675603841000000	1738675841000000	1833283841000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
144	\\x5ad1548f3c7736987b21f4096275129f57c66bbbc13e36d34ac586fe878c3c2aa27526334e54445850f00d84cde24b8e545e9fb996e3ed661dc014931d39d790	1	0	\\x000000010000000000800003dc0db3ea32f35660b67622eb29395b97887b2e78acbb3560bbf9c09ce03d055650e849dc8f8586028a21a144fbbe421e3450f76a92dd6ee5339bc703059e023d8e315556f201b3d616b3bde61e00b7d68260df8dead34678578247bc52912f4b998db2ed1c4bdf4697fc462f16413e987a2d78c319ad81149f683c0b16a3b925010001	\\xb30dc436278139f0038883fa6f322ad99dbe9f0f589838cc632cd30ae8730b79d653b8adcc2edae4d5b7653f73c6ccc5eec7ea7f0a5b8cfad5007a5baf007c04	1660491041000000	1661095841000000	1724167841000000	1818775841000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
145	\\x5d6163a03d0e4e9e7d885659f5656ecd530e1585b821fd5b7bf670a28ce73667b933b646aca9bdbe9369734a973196f55467c767903beaff60bdf5a3e8d06a7d	1	0	\\x000000010000000000800003b25d02b616ee9ce6e876842f93f924cc779db26f84424c3033001187adad2f60ad8982ca2f1c592910a1eb83c1eb0c1eab2d0fa700c350462ff7388f90178ef3449fb388d7897de32a546a6ce4914d5db50b9aae5d003b7adcd9b430125ce60b348bf122e10b2f368043dc58fb342e7b0a1a3446545bc626533a935a4233ad11010001	\\x0e4b0e154d8d18433ff874b7ff04f74802f02f8c900b2ade6eac9acb68348f534147be216b09c6b52ddc6933b8b7b7a1424e08c77afd89edb048910a0482090e	1666536041000000	1667140841000000	1730212841000000	1824820841000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
146	\\x5ed9efc3f8786b8fda984c91ba9208c7dbdfc25ef4b43f265156220828c7ef10c58c0e21d4de0302e32bb560993e7770e64f04b55ce92d6423d976de65d0de2e	1	0	\\x000000010000000000800003e6ccef335a99672735b6aee9424a7baf4dd43317374d8c6ccc0e8c028c5a806ab9eeb03de64b65c08a7060867640d88c577159733d502612c41699cbe6f2cedbcfe6f2c4fd9cb74a33df4231ed12b9daac0d9682dc9e98cb7ff7b0edb58796c9cb6b756a4ea022e2489a187272455296c66dcec73d1f9e3cc42a05bf41f51fd5010001	\\xfd6d0236397bab63774fe08eec58fe5fb35cbbfae67dc8c1ea1920ab711d89ab8f2b3486ff808b6b4a21703f8356daa6b3d3a16e1421a8c9e79c4c1c7a03c904	1688298041000000	1688902841000000	1751974841000000	1846582841000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
147	\\x5e39d8b0a112ecf8be7a5b77821d4cf36ecb5435727d8c2a2207daf67abac6fd3638af659c9b65ec611298e84d98559e7db8b143773df415693b52423adedd1d	1	0	\\x000000010000000000800003f5f404ebd762a9bc86a2301d68e7f8583864be5566b76c8ac4f8b3904bcca8c0817ed1730a90edaa9fddbf7054caf0f144a6841717321a1088e2b341119ec0427063c3f27c709057c2c896bbc5b117bf417a6879c2fddb25d48fefa02dbcc855d4e00e0e9e08c2928f092e627aa07ee6a6fcf7afb349b71302acdbf094031921010001	\\xcb61dff21a4eec150a3ca87a17bb1eaa59a324459fc3de0f5a7c191377260e17d8aa6f6e68a056bfe5dbab2e23c3ef36a5fc4ea2f66261b0d4d888620a9d780e	1690716041000000	1691320841000000	1754392841000000	1849000841000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
148	\\x6069355ca721d5fd90585f61a058e752edb16df18b5b35b82ff38c8026b96ae9c8352909056b6d36d9d377684b3bf9b709c3bce491901aa7075bf8345a1db2fc	1	0	\\x000000010000000000800003d32a7cb82812bd312eb93b8285a10a6c710c24f3d7ef330277504cdac722ca9039ec9f962b9406895cbfaae12992ffe3b37792d9868985cc3c4cb0b75f0545638a82a5a3c011137be18904ac58b6af2bd69bea74237d7572517bcea36cd76910f541a4880046323e8b538ee5518943f84f0c79440d160d10f669bc680f936337010001	\\x6b33b35b291365b2a8af6052277812d08c0869bd3e1016f3c96574ea804b6fab53c74b10b3a03335274ae780506227ef7391889bfd877eb25d6748e55c710f0b	1684671041000000	1685275841000000	1748347841000000	1842955841000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
149	\\x643d9c51be5a34a11382157342e994d996853d00a319a97afa148c08770a16a4fbb461cc3cda5cd9b3841ee110cf29cc5e0f436e96bd2bb524800d202f74bb96	1	0	\\x000000010000000000800003c7355e3c007af93a78074854638e73570ad4c0fa7a94bd55bec554bb2b03c6d87fbd04b6853ac9a21f367f27190e90a48dad713196c3f6980d2602256c0dd673a97630fd2566e2667c1d37f338b6f09c3a798230521d9412fe39b008f70d9bf06c6563ebc203bb34737bfce1b5d5cd092e5daf9a1fcdd7c40fad65e7c344b2bd010001	\\x585646b57f3362274d58a15f187b30cc67390ea889a10a700e25782d96555bff3a13b0165b47ab1a7c8962b97b87fcc8618e60d7c2c3f886fd07699d30de2809	1667140541000000	1667745341000000	1730817341000000	1825425341000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
150	\\x65c117c97ea564c12d1455cff0de942dac16cc5febb6bb6cddaebe68977dc3e0faa8ed0f0c9ceac78e9323d3f2c56e7198ad44a94a2715c5314f913a4d3ca02e	1	0	\\x000000010000000000800003cc4916e76835af32a03b247534292bbe8707a2e843da91b2e3c0ddbc7ba109b05380f227ec3123771929a6e4cdacbd14d1071241cce56a9db1da5b2d86d59a6fcee408f9a5697f45c8d7e2b86358db7d1a4aa9a57a3a07e055c284744004ff741d82b85748c5794a21a6bde3958fd18426120b9d89382c4a79c6ce3f872ff547010001	\\x12fbc7444ba1b2060486af99afbfe91be98c32b015e225a475a8e22c1a1a1c7fa9a52800f2d0b416e08509ce16b08c131b39996d59e712d832de76367c0f590f	1662909041000000	1663513841000000	1726585841000000	1821193841000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
151	\\x6b2925e6fdf0b8d350d0398460ff0237b69a607fa9eaef19ea977135c99b4a85a39f482265ed313e77a2fa538f11de5c44a052ad34a60be994e926a06a4d97dd	1	0	\\x000000010000000000800003ca193a5f45f43261e1179a5003b9f1ee890289636a684e6010ef04d5c958e6783bf8d4825ca9167a46a7b1cef9fe645ae46cb18ba05aae079a047bc9bd789c14797ae56b0f10dc82d6b2937589aa6051d69b6639b5af1afa3d1ef5b0fd26bdaf667f3c7d90b6947771dc91c301afe480defcf965502b1ecd1832ef76e77e375d010001	\\x22b83cba117f106c76087e6a4e7d333311238f9366f2c56ca946818fd422651c2052a052218e55b6e08c567dc9bf618ee2150785a2d7021674a2081bad888704	1677417041000000	1678021841000000	1741093841000000	1835701841000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
152	\\x6d8d2a203fe41b45dc888130e432cf9b332c74762efa8049b218d9608912392ec1e8cc827fd9e3a13f61f696b4fbfc38d6d49217d6259d8affff6e2381724865	1	0	\\x000000010000000000800003aa4be67ac5730bc1cbb92e8b0d2bd2c64aded78f37e2845dfc427fa1df35118a8beaa04d7f5847f2600b4a831ea26a4a4505679c256bbf1c3d6744271ca0150c6745b412384a6fe69ec9f641d8d1de4e49cc6876fb9e618092ff8de360d4d0ccb25592b0fdec7c603bd50bc554c1f4115b88ef8058a9ee6394786aaf8e7d31fb010001	\\x8d66cc853db57a2d1065a0425e0b4e20ff7ddd4961c5f08f575269e5e43079a11ba469294633cfeaaa26f2cc97a5f3a5723baac248d8021c0b7c742563adcd0a	1688902541000000	1689507341000000	1752579341000000	1847187341000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
153	\\x6f2554fdcc7040d5e03f3d3a67259ad6ff754b611d97295022cbea044aa4c89917b4c525c8822849e3ee681938a852b72786c6b420a3ef6f84ee86a64f68fda7	1	0	\\x000000010000000000800003dc16d50b4648651342fb9d4909e48ddbdf6eef14853d5a4c122ec3d1fa5edba78c825794813ef420a089b20b289a609aa4b8865a4363e3a1b2a858444cfccbecc50fed7f22aed66a210b0a31e0b68b794e44f1032b6c635f96fb29551dc488fefb43227593f680a14359624574aa7779e03bca60b17118a2e06ef1bd32549627010001	\\xf14003a9111aba7f431747efe9eab5d8f819707742d13d5fc70c0ef9ebb08036b09bad14027f146d84e9bfaca3edda986775fb62dc44334b4f10e56b43f0c609	1667140541000000	1667745341000000	1730817341000000	1825425341000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
154	\\x7081bc939afc7e35f3d6140bc2ee2032bbac7b608314eb7cd13c6343b6db0b43528876ba87091fcd8cf89d2ea7371bebdaec0d39f259ed4b00f1ad6781e0a949	1	0	\\x000000010000000000800003b2d0babcdd2ecb2b10e5a1bf58a9d33b707d7c890948d13ce72c6ee9f68362f082f9b581489b7d98a0c13f58de1e6ab8b75f39c74a38902c19c43f4428b1d6d1f6e4770f7554e4c1766cebe196a60f73e4306431440d312a01b0c1b33224e80fe1afe0cb2d6fd611a18564b2c1567d495e7da988043671a850e947df78472643010001	\\x3ec09196c64eafef5a4defa80331a89445e86ebfb7a29eafb0a7f5e25df27e003b6c33fabc1b1646c4e5f60b2491397f97f13742f6a0df6d3ef0c5b41639930f	1668954041000000	1669558841000000	1732630841000000	1827238841000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
155	\\x71f5204012877c34541f0b57c3f9400f1711b1f2c4dc6ebce67fb94f9c76972218bb446b18fd23ba9e6f7966549b5c07d94d8d98e212f1fd7fe7bb7a8bbff59e	1	0	\\x000000010000000000800003c4b48fc2998e9233f310eb5a4e146d4237985b53d27f6072c6a248f061644ce1a1ea2d35d7cfea73ff02b416d9c241a1d5ea7ef468018fe57b187398897d39366aae72ada23b7defc9aa87098e14c00e306639e002e8b5c0c949c6e8f5366a9d107ff40d906bc0b1735773ebf2a612bd7eed3f5aca9b95325bf53f1eee6466c9010001	\\xb94e1fc04503651c6a21aa93fe42d3de16b5f41f8418423741a871f75e4e0b349fba2ed9fb14b720cecc18d055051494410628806bd71aca8ebccd9810057800	1662304541000000	1662909341000000	1725981341000000	1820589341000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
156	\\x75e9aeae17e0ffdc56175ea8f5127f426cf610acd11e96f6ef839ea54c246c90a0259d6f6809bf6e4fdce9235f52d3c6159396764d561ec795d1d4884c97001e	1	0	\\x000000010000000000800003d2078ef469106ef9e51fcc2cb710b6dd5aa354f8ca9848111a220ee28d9a801efa8c201deb7846a44971311220951f76996e2a6e1bbc2bba5d71e7bea2aaa5c80d1661475296913f5a54a3a987a94272c62f577f394ede357dcd678903b382b154f064cdd3f13eff051bc43ad19340ab708393f9d3d9a37cf0cd0da3ac5971b3010001	\\xe38051514f3a7730dd23531a931f28a80b6995c681dff6d04307698b022ab6357c405aa85e60877b4d3a25ebc44f67b88656a12a0fc4290afe6c4f37deefc80a	1670163041000000	1670767841000000	1733839841000000	1828447841000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
157	\\x75a57a366a435f7ac60b2f572a48071ea057a2ff8582c45c773f8799943a7fb3692fe5b45e24e9c491c012306365ed1e369dffa87a4bc56c26a3e5bdd4a34089	1	0	\\x000000010000000000800003ba2833f354409e0163e9ab2539fefdcef310d2dd52fab1d40c3d1d17696f2a0cb8111122f002283a743ceb83b40854b763b458ac7a7ef40e324b20a679be8ca3aaac8d657aa8e917eb93bbe42e71f4f3dadb71a7c01b05114a2ba273aae8a93effc0a2ed695045dc33a60e57c6890aa0b39f9db4a581a8d1c2a6071d1ddb902f010001	\\x6636fc5a8217f31dfa980d8f3d471f4260fb924c8c2dcb3ff5f6e0c1f948169e9387085d4fe5c01ea5b62ea2635d275d0b6fa4420b19594a42ec13e248a77603	1679230541000000	1679835341000000	1742907341000000	1837515341000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
158	\\x76b90671bb7b960139f09c0dc470fb67adf999a115bdcef70362adff49a429563b86e07fa73a08019b2f9844485ef60495b064ba669c4394cda02a22f8c985b2	1	0	\\x000000010000000000800003d3a35ae6cc682836dd8bb890ed6d26a755173b718496488f17f5096033f9505621457bb1344ab4ea2c77f5f3e9ba146e280d9cbc88de47a5fcaa151762b32dda5871fb577762a60434b5a10cad4d1fcb5b669e186a47272182823fe45ab1688d6b06c2771a7464fa9bbf7d67a6a807f64efdd756442a18fa86cdd5539cb6ac41010001	\\x0f80004950ed7b84cdb689e0f53f592178d579097c81c3010af9fc5cca80409d23647c7861e82fd2f17d64d38b52664518a212c98269f3a4459169034aee6707	1685275541000000	1685880341000000	1748952341000000	1843560341000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
159	\\x7a55d8e781038798af7a869a8446c9c8cc2fe5e7a000d7a16dce9df97ab2430e5148adca49536b99ca6c4b3692939054118d4f7de8e02cbe74dbf0551e91affd	1	0	\\x000000010000000000800003e9a709a58d62c14e46d827e76102943f1b97c65629b95a053336f8caca2f0a18ca2278be1ba07467c941d7fbb90197fd8a73e4b73073e100b42b581b9cd5c5a19cc64dd305d715902e107af33922618aa89f471bcb15eb872fed5803d6baa06e32f009e24f815f54026899eff50300c9886e8d5d088d9443276170ffb22e2bdf010001	\\xb964606f70f625b4288aa773a975e78ac26d3f0a0b2520260091190671ebe41dba8ff5a03c841f988216fc4b74a025a9425a4939a22f8b2f754ca9b472064e02	1673185541000000	1673790341000000	1736862341000000	1831470341000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
160	\\x7bfd74523c841f7b1c2ae705add25f9ebc7c5a9198e7a867a27dbf30c7f6437e0d180f43617bb6ed50ffbfe1d1690a139b03a4c42cb2a61da870f4b0dfb69d99	1	0	\\x000000010000000000800003c9a131e3e91b24c2229237afa7f47e80cc473feff27da220f62461b97edd7ce1aecd2fe14228d739b16dc229bb15f9e36da24b837732267ccd6c2937cf21d7db23f946f0e7f42e11543460d8ff49b1f2a668db54e9e1e7c5a67646639bffb540942ea8add635c22fb84469e669155a1dd1f84e4326c2c3de62ccb6c75c97bb25010001	\\x95bf0fb85b27de05acdeff592ced857872f2d5802007cf72df91da7c965d30624642e132e2492426c1aebca5bb0797776c900ee5631bb897c2608e7f3a13c406	1679230541000000	1679835341000000	1742907341000000	1837515341000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
161	\\x7ca9d5e1f7e9320877891e084c4a3612efdb9001607eef17dd9b27e518ed5e097adc856183d39bcdc9d98fe21b4c4f37e47cf3b9cf86f6c9acd66930e7161792	1	0	\\x0000000100000000008000039c4615f3de95066ac984050dcf5c96858a277787129047bbc9582b469c59946d500ada6655392bc29632774303d92fca574d73fbe8a206f77850fb0b16d82e6395a2e18e633755059263ce13d7b44af85a4519416fbf448ee6f3ced8ad372a100a263e12260d24105ab0cd1e8d81dc16c5268130ea1d7a1b5a66d76ea0a68221010001	\\x172859d9263b8fa8986e1b55920147504f982045e7dec5883b0fc204675bf1c83d3beca9dac9afd3637c57bd9bd17f29bdefc1fb4b30321fc883ecdcf03cb205	1672581041000000	1673185841000000	1736257841000000	1830865841000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
162	\\x7ca5f00092b70e50b6e2c2ade704461c0e2914904f178ab968936f0d71bfd24d083973ff59b1cdb0dea8eead6b5b48604c035209c27b68845c90e7abd8962d8f	1	0	\\x000000010000000000800003b5bd8e5078c2d23f2c852eba2bb61948c68bda46cbd2e5d52b237b5ae689da929363bb4249a2bb8a3bf1dfb379a0367d03d65a154cccbc3e18aa3c7f52cb1920a61bbf86634af5831276252e360b48a6cbf6b0267195e86493c36c98f4885b0935ea9e69ac741e9664e52d708cb6fb2a1e744a81cebe1e3e2808b7e015edb5d7010001	\\x09321ad5702e9c36a059e11e2d0fc6c6f271452dc12716582615c088b98a89f92db0c368570b9de8acc979b25dc2ec675eb6cbe75b6cc8ae260be0192eaf3804	1678021541000000	1678626341000000	1741698341000000	1836306341000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
163	\\x81212c7e57028cead785ff4fae8baa98923f817d83aaf63a2019131022b2cf83f8f5ec81204766c7f233bf5b7a53265aaf2dfb6ee707edb2e57d89c422738130	1	0	\\x000000010000000000800003b8334c7976a62246aae61999f2b7a2582c7234a2585781ecb708eafbb53bdb77d19ae11edb5d9af9b42de6ee21a5b67dca13a7460981ac6c33d0a6269b2e799e9756a7f13468097b56c70719db541dbd76fb2904f45af43568b7d865312a8e250040dd96109fb1dcd00bb57575d3eb0087d654f4f4ba0981133db317280c9adb010001	\\xc170585e2821869c141acc2308628ce54852bd58fc8302bec23e082cd9c002c4c8bbdf44c871a0f60430bd0bd61739338bcdbba853392bc501ccabc838e88200	1678626041000000	1679230841000000	1742302841000000	1836910841000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
164	\\x8c95872e73a5084422594dfc7afa7013d919ddf26c1b48f0e6a3a9d65c3b2a3e7017d569afb7679cb90d1e758cd71f0c1711759adbd878da090cd1b97fbf7245	1	0	\\x000000010000000000800003c2cca8d2e9857820bef0fc2af8755f454b565155438fa6dda864d455f05dbbb010659c66109fbf3bfff6f5477ac534efeab5db303a8747ec6a692eae845022608298776178e7bb33379ea69c937c040dfb33c77d263352e9866173bcc56591c455373f9456bb259932d2df66e2827ecfbb915299aef5fa063537cfad0b4379f7010001	\\x0f2fe62f34cfbe146bf5a9eb600cd7f28370f8b232011b5ee95d3f86c10ada68525010c870912ad200968423afcf0c6514bc8a687f613d3ff579e54ad4070607	1691320541000000	1691925341000000	1754997341000000	1849605341000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
165	\\x8ee5755b7182d34bb8831db752bc71758542658f7ed4ab25535dac4c357f805b5717d7e609ec352756845fcaee9ae29c9b449a6aabd25d2bed6051c9554fd396	1	0	\\x000000010000000000800003c9bd52cb278dff6c6b3d37745440eb8ae936560c38bf98385abe12196dc6849871a9bf6134bf502d57a8ed7a6d569e267876e69045ad1bc1cc8b91ce08ea9f401326f61b6407e755d2a7f0d02fd31dccf4917c4dc10fe72298dcf5e97608aeea464a0b4ae1f52a4f35448f76665934d964d8bcc1fb8547492495abb6b46b46a5010001	\\x2e7ba996614956e85bc48afa907a310476077225f89b49b1c47a629064c9d9c28d5f2de1e07d88d6ae60832ea5b43bba89b0409ae49e2c6aebd3cc39f92c830a	1686484541000000	1687089341000000	1750161341000000	1844769341000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
166	\\x8ef5aafe4c0a63442307bb308108e48ca8716b97028b54a4c7398985593dfd3e060cdaab09bef6be7ba662a48328e3d498cb68e11c933dc4920616de6c8479d6	1	0	\\x0000000100000000008000039eaa837c6c42c898198025df6540bab5a0a6033d2e2663281cb570c6bef560ab539d0c568cb28f788dd30c14add643fb9c4436f07d7f0c83d056faaffac46a7fa800f3866030b6b632dfb50374e389058bcc2b1ff78b4709347efc04d3d78aa917d45705ec8c595f7b957c81b3716b9b3e724ae0794f887879c0212ceae31e3b010001	\\x3c373acbc12c20f4e630d569fb43d648ea3479e02e131ad0dcdc8324fa532a7a0440b6990b15ee48b8d69f1f023364fece0d24a758efc3b256e5b23926a66007	1673790041000000	1674394841000000	1737466841000000	1832074841000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
167	\\x8e11978b855f21679f125fb9954cb48731bb056ee9421f0706a11d2a6ed2e8fedcdc1a8134752b4e6dba657c5945d240458415c9920e799fa539cf3e02745960	1	0	\\x000000010000000000800003a88e3da37a38d8b9a093fcb8a04cf57e5ba8309042cd9ab978d3287794eb92502a54bbe606a1edd388fe1b8571cf6400583f8a29d4d545d5dd02a9f958be34c7229098becc40a3abec38187404ae19c887b0d093dc911a69ac47eef58e29916832c267339b3e6f22cdb0a5106f5251ff2dcce59f4adcadc3d80b36d535ce8ec7010001	\\x8d9b2fae5672de8f136051df127a6aab4af355732913bc6cef55199d01bf98700f7b6837f699ad9b09c632e9c31b1787a12197a18dc399a35a0da5c7d2a88201	1674394541000000	1674999341000000	1738071341000000	1832679341000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
168	\\x8e81e22868f90c6114ca39d1696e0273cbb1b76c2840e1e01e897482441381ae19b2ca00df62d803d4f9165df13de4b988db850199ca416a8f425b32f6203ffa	1	0	\\x000000010000000000800003d486daa33ca15945d31cf4e50ff2a5190d5b649f507a857eab153bd5a03674c129fe94385bd4f3d6ae7cf72524baf4df924d7b05581a08ceeb68cff1233f7c8cd591d6e94f791b8929b87d57403cfc77188017a80ffaf2fbf2c4d137428b4fc6d0717c4fbc63603bf2dcd71d7ee439b582421dcad09731c7146775cd4c7d7b7f010001	\\x6e18d36f1a8f79175fe6ca83a171dad5c679dc6caee7e1aae9ffa31c7f3c64e92bc7ee2f8f4e42ad07964e1c3e8a9a161bdf72b6c9c0e1a3a0035478ebae1308	1668349541000000	1668954341000000	1732026341000000	1826634341000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
169	\\x930d58e837574039c5a226f528b7e24b4f6353168a7d21fa1589b3c87e479e45e6e7b0042e1989827859e1cbd382672bfc9099cfcae248208246d27f90b55ee2	1	0	\\x0000000100000000008000039b85b7ecd579f97cbecf9e657b4fe4023f3ca699ccb2440c9492b7996aa593800deec6a92ddabce779a4eede2d03eb5903225d00fa0880a6cbeaac38d452a9335072758d9c60c169dbfad3bd77710df5b8cfb3b903c5246c09e51f25d73c2f26a792c3a72f1aee1ac9772e6e0d90b5d20af9c5f462c52ff7636e312b16473f3f010001	\\x77a587d79b8f9dae7280f1bed4ab0f8bc5abdb1ca80b8df847808f1f09c1feafed7da851f25e2a534bea32ceb4bdee7851f3f18a57b6057a892547d234014d0d	1684671041000000	1685275841000000	1748347841000000	1842955841000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
170	\\x934ddc076c0fee5e4bfbedf71442aca00e694b9701f559ecf54a5578efdcb27724333201df8a0e61c04c3bd0dbf9ed7b6dce12ece17b842d83e5ebd1088e0de5	1	0	\\x000000010000000000800003bf0de1ac15ea012a04984a4f8a4d68caaac83e1ef79a2dbf88d661e4dc7750094cd2789925756fa1ca6c5d823359ff9f1a6119e3a0a7b6623303187370617dd5d83f16cb3d25e458c63fa2380d5f6b12e21f5cf60a43abb8de44b9f63647a3902cd8c781c94d0fa432d2145ce01687bbd5faa23bbb2700e28682a77e1c12d833010001	\\xa6b97591be513cbbdeff86f1114b8b489def50345b46f4a531d36c4d65d55dbc782dfe88631900f68dd161f5289d086d4f9c87ba5f33563ddd2ab3eeec58dd0f	1691320541000000	1691925341000000	1754997341000000	1849605341000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
171	\\x99e54ba5e5dd96bcf8512388f444c9173f544ec5f8319ad59df40b93fcc12a4935ee6787a378a5156ec8a4b6d68c8fb813373d7d8c74121090707f166674050c	1	0	\\x000000010000000000800003a52e7beef99fa75b3a8f2cf033ba4c094519dd156b8c61c6777c68de9fd5c836272b4b0f3475903395846f73d2437dd773f398113e125bfc1fec2157dc10f33c5e757dbb54484cf7524665eb49d3ea71865962db0dcf9367c2eff128027f514ed25851766c0b6eb14a012196afd1ce9ab977bfebc8ea56a8afae2a0ef4517397010001	\\x8a43714b09c9faf0d74ff58aea762bf4815d324788fb19b311da6a08a10184c39d144ccef200150db0cb204ae9b1b9e13e2718bbb60f830208b67ee767748e05	1662909041000000	1663513841000000	1726585841000000	1821193841000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
172	\\x9b45c8dd1831615d77a6bba65aaa27da1bcc2103a40109c8ab3ff290268362883fc30f4250476c5bd1890e7871564086d93ecd9b4fdc9911653112212e644e51	1	0	\\x000000010000000000800003ca2ba1e9c93d62ea0c44999a44c285c138100407e713a1958431ef6df6a3b9091c1f23346aaa3c29fdd988c187a348d80494fc12953a3e3df7654eaf051a754cc8ec6ad9b829329692abfafd52645f3a363020142fb2cf53f6cea621790597b0d483d10f44d6b0f1f5468e44ad1ec2d16a4085c341097eb0a0bf5ce2da3fca5b010001	\\x6488b0e90ff182e09ec3dc409548f66650dbbf02bcf62572d38ddbc7555211210521a080ca683af539d5b7e0e09cb23e02b0d7a18efe950eaf442d23a087d10f	1669558541000000	1670163341000000	1733235341000000	1827843341000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
173	\\x9e89024a0ce11694542176a918c1911c5a58e08897b9d05fa20d0f51c18dd7059622d56b43c8dfaecfb7a4b5a6ba0651ddb85f35c14659935eabeddeb4503bfe	1	0	\\x000000010000000000800003b1622e930a0b35e34edae4fe45baf065b5685ae7c270f2ac8e26eecd5c1d928f80465259ea9dca886cbb5ea11fc3f132da8571b1d987049c17d6a05993097e5ef92d5222ab2f96c30202390135c46f28ba8b9ab5fa123390229c73f7c1278b41c94175a9e9760e0c830fda4f662120d8b81e5acfd4a6a9d8ca076880e69aeb73010001	\\xea36f0f9b7136ee46a333ebeef3605221ca56d23d2e0b3d1783bc4af883cab6b8b33eb4a2278f1ed67cc81192a01eaedbeabbb60e1889cab0b28cd8c67067707	1676812541000000	1677417341000000	1740489341000000	1835097341000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
174	\\x9e092f7928fd5ca1809aed273bc56ea6c0c84b531813b3e1039d90fd273237947b2f5a1c47dfb37c8e836be5f9e2adb5f99513f22e9ba0e5012e6f9dffc173c0	1	0	\\x000000010000000000800003b20d71024cd4b6c270959635a962c7e18f64f7fd405615ed10c8128d965cfc59bbcbc880aa098ee4f7238c7fadce4dcca172cf4899f5de4d745cb2336e62ddf041aa6d24ed95c82c8361a6be22cd1f8b57f85f628624ea92651d698ece16539147e17910d2481bbd020a0f055df828e92b189360b50903b5a809f4fb29d3a1cf010001	\\x49fdf7ae3d0637d5d378a703c913a7b693b9be3a7e869dcabf61868351ba44cd5df3d0c896bdfc5f62709536a8efb6ca16c8fe470bb0750136d9c28d97261203	1671372041000000	1671976841000000	1735048841000000	1829656841000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
175	\\x9fb5e2aca3d35ae31abe7644297b6f0f13d85adcd60b1153a938cdd6b9884a9c2bbb180bcea35b78bf07751608d984b60a93fb03aa3e015c72667eda35b256d5	1	0	\\x000000010000000000800003cb894b66efd9d3cad02c62b4ed2f44e4f9950b768221132ca1756b28c7595730220b228a20787539df462645f4cc81b23e8eb042718c646e3f8e666591cac7185e00ca67486ec260099a8a6e1ae86122b12512ce14b966c0b6ae33f0e3ba959c2539396bcbf0630a03591b04b0426599d04f09bee25e7e1e32620ea1beab8b67010001	\\x4a30cdc5fda167a55587446bfca6fac98266be8bedf39414e0d6374731fedf4e6abc6d2fa7ffb62033683c9f9043687ba93c1230df3cf21cfc0dba9d41f0af07	1690716041000000	1691320841000000	1754392841000000	1849000841000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
176	\\xa405197d2b4ec0a7b00dad6cbf917e04fc27e8ca0d2e828a3f683296070e49e40cbe9cc8c2d213eeed791f9602bc08540379592e84950f63b2bc5a2721162094	1	0	\\x000000010000000000800003d2a757e061b29738cc4260cd607e89eb2a3fa781e816ab340f2a1a2768b834e7d5c66e2be3611db1fe5989c8b44bb59aac2da05a21e7ae44368c6f0a3a42c2c0bda250b8ea8d064018a14d832b0eb9915f7bdac873031778ddda69f628e385696b67276184478231ae759d6053b5d1a485e831447a2f720e15b3754d045f73a3010001	\\x30659e36cd2a29f24674daff4a8b9361672f442d51990f46e5d79fa8ad685d6d1083164d5b4160f369991ee6d7a06d36f079ba2712e7eed305741dc113695309	1687089041000000	1687693841000000	1750765841000000	1845373841000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
177	\\xa5e1d2a928b2b6407c0f1820129985d9f0274bd1ec80ba4150277bb3934efae628d7a9e8cc6691d7e2aa48feb6377241b3ac68d9fed8fbf368e47700f7ff2f93	1	0	\\x000000010000000000800003bb91a70e998b37ec3a676bff0301005ab813bf8c299dba3b3f375da8a7b8a44090fbf94ff5f634bd6abcccbbcfde67ad99e5f9cea17e431d013f5bdf57d5451b2269a42699c252fd328221d100ca47102d1c92bce051a85d1ef4245f7df2c7fd073c17b471b140d3275675121ee3c055fabc155068e5bf384443496c8d24f8e5010001	\\x7b5d6ddb028f5f7e60657d45435cfb98469b1b0366ed229d3f6eec43381d6bbeedda04e2f95608fc303fd9822a11b1b0945b70561a8f64b1593157732a027005	1680439541000000	1681044341000000	1744116341000000	1838724341000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
178	\\xa6b18ac0d5eb75361049bb74e4bbec484f46492eb5f8668909074bcde9a4414c0e3a696818b7a8d93d19049a8f0510a376f4c662e4c36c9830d0324e01967143	1	0	\\x000000010000000000800003cde5074f57d1f9a25ab135735072eec773d426cb9456fa2d42904a596c07347ffd572ba9a97873b850d5c577b4a397c549a0bd6ef3534b68bd9cf75dfd1eea9e84354c7e5c24557926eff983499d8daca61e095bd3db25be4e04e66f28fa81948ad7b41906a6e25ea91299cd985e30b267d08c9a016caeba1f5b07d3a7afefa1010001	\\x1a7f48ba73c4e13cfaec20b82bdbc69a7da0f829a26c0d15a7162c95334a5cce7b449636e7d95224580534bd5fdd6b28b8208d61560001a1915a3f98399fd60e	1662909041000000	1663513841000000	1726585841000000	1821193841000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
179	\\xa8ad3ddfeab9273fe0b1cb94f457ba1c3f66178984515b8cecb6abcc9cb5800d0cc482433a8398c3355cf0048c2d0a887b45bb15fc1229cbb81fdb4f34eaef9e	1	0	\\x000000010000000000800003dd9cb4eb04b167b0421fce79b612c42a6f4d4678d0af68d0264a0b000296ed493ca213125aa7fecdad685f1719ffb58568beea7252f3cd47ed40b4b3fec4c9511f22129c33dacf709429c4cd58c1d571c8a943d863d857ebfdd41bdc4525069080ce79eefbf58c1a16f1742decb19f7876678c577dd82b7085b28a6173a0d773010001	\\xaeffd4507852da0aaaa3039e6ec518bd95486d9d9a96c5932a0156743b7eb6d84931567ab51e1cd9e34799f3355fb9996bd0d57f0445ab7d9fa2814884c17f03	1671976541000000	1672581341000000	1735653341000000	1830261341000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
180	\\xaaa9904a42851f3fd2d5ac1e449a877b7563b29c1494438cf1936ac9ab08891fb9223a1e5d55c56ebf7a9229e32534b25de1ec76b1f91b95843ab31eb8ccfee4	1	0	\\x000000010000000000800003aba42d4a29a1bdcc9aa5bfdc334bc6d45d44a86c556febc78d5a78cf473b77eae34dd1302d039377e577dcd9dc5d1420e39bf87c575849bcc137332146b1b3cf58537a917162cf7a1239998f6bc66f81797d97b2c3045283fcde3a11c5f29fd670553b125ae4d4cd4777760438f9211a8ad813de443b38b1dd90b66efebe9179010001	\\x3a7116776780f0d3ae58e6635aeff7f95c2f1e37fb38ff46ab54a0f74da19be3ae417a2001d4cc18e5b50899089bdfe2a5f209705931d37184d8091b1e531b00	1660491041000000	1661095841000000	1724167841000000	1818775841000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
181	\\xaef1ea9cad2f9eeb3ef68de26d53c794bcf132bc8cb14aac8f041efc2551ec1b7f18f49f3bca7b5db2515c5dba5c0c9fcef25145be7898513368f442d8a27a32	1	0	\\x000000010000000000800003c6d8305fe25db9044c7147b61847a71dea6a8b154587ba8f9a18d6fd96dcb3b39c5de6f3ad53fae4f3558a13a2493f3317f485d364311fcedc8d6ec454c72b0477c42fce580c01a1f1f76356613edd6be4b9e06d0d99cc163d7c326df14ab93bb4980678b8988a5c8301cc36ce28eae34505307dea837c7fe8778d7d0a583d81010001	\\x816716be94325f9179a0bb887f2126ad9917506c2db51b330e3211022591747a24b5f9a752d9b2ff03dcd2959b1260837786a6b768ca0b045af2674be2b8790a	1679835041000000	1680439841000000	1743511841000000	1838119841000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
182	\\xb1656176c1f8593974c11bec62a85e86e91d81e7493191de34bedbb537ffaf5bf5d3e57b34418f04df6cacd509eefa9cf5e864dce97ad26a1e71d1670f27a031	1	0	\\x000000010000000000800003cecacc458ea16f1b5c166118f888b27057a22699f05042d0ab1eab2024110b3ee93c1d41edaa51db751be590108905ead48700e81abfe879b46e6844a5250b727d0acbc29a8e537287428fabd3224be1b525741aebe4814e4cb3aa534741634809907d796d1619de5309c31d39e6d7288d75d2d8afdd6ab5bd7662a19b1be725010001	\\x55d2dd3fe67abcc034e832df09b4b96cef030e6b703e2ce1f10862e9a16edefe428d61095733155e579a311dd4aef8412f09bad1862b3649df38435816e41f07	1678626041000000	1679230841000000	1742302841000000	1836910841000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
183	\\xb82d03e194f6f23daa0c78990252e38685396f41f4b070a86cbcad02f39b52dac575dff64f05d8c4742519ee32e27c4ea603ef5a8bd3fbb1591b56b8e332a661	1	0	\\x000000010000000000800003bb4c859a51ed36848c6daa9d5de07d15830a5e50c4eab0e821d8dde16f8a35c72120fc8fc3fd9f58fc241bb565b0b476c88370248529fbffc16094d32d8d77a02588cfeb3b45f9e4b7db962f1625cac8b8eeb50b17ceaae81cb62c83661d6a0df9995197dfb38c8d394e37cfb5345b1e3dab20011aa8e55a4a503744bd2b493f010001	\\x82e826691452c235f6d74c133ba6b4de6f5f32643122c98899d8652d7dc45e3d234577ef8231db609a5e95927af0d7dbe7569ed13f4900088622d849a9eea700	1670767541000000	1671372341000000	1734444341000000	1829052341000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
184	\\xbea5b0f084f770ad16d8353e4193ca64aab79f47881596a4afc47f782f41466bfee4f94b8cd26866417047fe0bf717a40d053246cee2e0259183b8e3ac600014	1	0	\\x000000010000000000800003c3e1ca57a9e5803aa9b0e6f135b4c609cb4a968d8a0aa8d157435c132ba3483f59d2095a46dd46726e989e229926222ac4061afec0994a8a7b1bf8c83b1c4784805106ee79c65c8d14eec83fd69210d9dd3c577ada801088534442e1f9918142ff2360eaa8a19cf06ab17acc8ea17827b6f0e24fdeb3691857cca3e5db70f22b010001	\\x441b7a5ddb382463397257ae30b7cff933c5e4bc611d53defd41c3c301622098ee2d3062d201a5c77cf68d6e934d74036dffc7a75089f3f5719cb21ebf45c901	1691925041000000	1692529841000000	1755601841000000	1850209841000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
185	\\xc189c7a95422bce14032bf06f4f00d3bdf05e78336bd608bc4b26be219cb9700e809579ccaa65516e0c584989636acadfe5e77222cde7a3ef6231574aabafd97	1	0	\\x000000010000000000800003a276e2f27cfe329a60d944bccc5fe95b4ae19983151d5daa3e9ccf8612c8270ff756d28159b204079721b0d0410bffcac40a8d9bc2382bf188dbd9ae425a881f551ab102056d911567afb979215d81cad224efacbcd74b44e0dee413da0e9fe2478e49f8c35732c8f833dda7f3f73c02fa5db4dd7e7480be3d456906171be72b010001	\\x526e114364f51cbe8d411d2a7b9875c8811fabd1a999bcde44d449a6750c97bf00bf91e3ef5bea38ac906cae053f2e19ad27c5ead43c63ee6ddc68e4efbd310f	1661700041000000	1662304841000000	1725376841000000	1819984841000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
186	\\xc1910aa300f3acd7f4c678ca422d8f2c19f37b3cf47c46bafd32edd099c76d9e1ac37f940de383cdf9129525110917a8c45ed64fb942750d83f56858966d574a	1	0	\\x000000010000000000800003cb811b9b2297955d92cd65d18bae92f5ffab002cc00c3acf3aacc2f1620122054b0c275422d0f9c464ba9178cdfd84fbec8313f9f5d2d7cf0bc511abf88b422e0375e0245ceef21c899cbb1900b249153a792eb1fca0a8dba638864724e9681eca45e9e432a6702cdd6f176ebe693c568f15e5c2681bf04fd8abc5d832ee2da5010001	\\x43b7353c578ce26a3f3c22fa0cdcc0b23cdceb5805cddc2f2d8bed6b72b705bd70a4a5eb532338c3f13e31e2ded48ee686a2f3b124ee341fe3f2921e48baa408	1675603541000000	1676208341000000	1739280341000000	1833888341000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
187	\\xc2b9f41976b59b859744e95c15bb4de2e11fa1b4deca21c6a9bdf915064bfe518a5a3706345a1881a861593166404f16fdef34761e55fba2033ddc5ab8b1735f	1	0	\\x000000010000000000800003e1e54cdeff3810f41bfbc2aeb362cbe4c7c8cf76c02500dac33a2dfde8158f9d8347663ecca9f0605f633829568a98b8a0bd9fbb716efa4f3b0c305a4db637a8aecf6292e3e27d7e28b5c085cabfd31174cd355c09091949622f3bf30a7d45ec16b430abaa1baf6eb1711a952aebc579a1be78793bfcec87f044ecd5cb9e0175010001	\\xcbfaa86e28a93f919050d55181f8701bdec033a4421562d741e98b63b7f169422c08c42a22a36d2f459f29cecd9d28ff9415720b78d62001dc6a21d76277770a	1682253041000000	1682857841000000	1745929841000000	1840537841000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
188	\\xc2392f55a74839e4e03eef2e28aed100db86d3b7bcfa39562c14fc78e1ae4085161d6607bee28b64c14f97d2773f21a85b8a598702efb73011427161daf68953	1	0	\\x000000010000000000800003b5fce238521cf2525335a94d930c624d74dcaad6643c327954d8f32d548940756616aef3d1d77d9a1c3040d1978c54ea47e26d7a1f440fa2a7c16a73d75be69b0bc8817f00049a67875a2f4f854b52ab76681261b467da611f26cfce9819a41b55fe6f4dd619a8e263850769440fcacdabaea8868c38000e4e9e7905d9a78f17010001	\\x957c520055854e44a24d9747963eb2ee24fe7dc592656551c2092170378980ce28e1ae0a15fcae9f844e95f58c0e5e98b7834d9671ee2e694a35b8a3ef130f03	1677417041000000	1678021841000000	1741093841000000	1835701841000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
189	\\xc3e9f67342ac36b2f9fcf132f2ce400c7c6440ab5130f3c6dd3baffdbe7a29e61b5860cd2bcee4411aeaae64d5693bee88dcefeed85a367f62c19c39ba07e0eb	1	0	\\x000000010000000000800003d6b6cff03c28b74cd9fce1f98e40c21448902bdbfc343cca69c5ced2d00829d6dc38df4952ea85249fee2c273255fc62c11b58afa75e9903d6123f8036039716e97341c41acb4460ac366fa40e8661ca9e6a0265d1f11921b517a077ae1b0cc9ee40c079c5a87cc3219eb7aba5483838c0bd5296b79127340007a0c8d422f253010001	\\xca40a4d03c18e2ad35da5ed47ce9aeab1f21065a3d8c9e1da295ce28b09dd640b8c3877ff29cf31e3dc95d722c999a1124b99ecdb9fd9f0005b69951cac22902	1681044041000000	1681648841000000	1744720841000000	1839328841000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
190	\\xc4c9c2cd75037c0737eb97152378d68ec5b843ab2f13485b811c27c177af3a7b866520c1fee8e5f9bcfa3cb8cc4a343fc4b97d4488b8e981c03d038e15e1c972	1	0	\\x000000010000000000800003d2f878c8fc94353db35a2bbde3e3400870890afb1e6ca318a8cc21d1e29bbd0a5b54fc788ef1d9a23521c35eeb755e22f582ada874fa759533324867862118158f44053dc22b5bd123886e31191efba5179c820ad4c5c3338dc5e480ef95f0a9e2851cd72656a478d4360f6b2d2f755513c25da003ab1321a5c2c27a6cb8bc57010001	\\x712796321e5f34712bab81a2867e1b513c631752c65f67dea63fc7efc469866f1bbb39988ab7f3e690664049b0c8f4c279e74187c3c951f4e6d5f8b4b1ae5301	1660491041000000	1661095841000000	1724167841000000	1818775841000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
191	\\xc521dde4acd9bf3f0f7b5dc166baf303e88d865913ac4f875e096dfb7f487d91b5f2dc713b7da2e0af4ea85046d0516069c95174da7f64f822af0069408b34c0	1	0	\\x000000010000000000800003e0bbccd9f3bc6259d70c704a4fe836cb64b0b1c10bf3ab5de8c01b752183975ce74bf468866446f687e38046cc6c570353e445961812bee0509bff6adb127f13b37c015b8a708eb3d7a4367aac02ae28e100605256f1f5af6906f2fe78b094b991287c27d240bff554e8f2120ea2e5f75d0a537014fbc9166ebe94299aab5317010001	\\x1b65368d28ee9462deb23bebf95076970c98ed96600334aa573596747fdee62d143402446a7004a2c86481cb5db272a809aab43c68b5457e6178a2cc52811702	1677417041000000	1678021841000000	1741093841000000	1835701841000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
192	\\xc775e6d79f7d7e4a75ba4ac6c6c6c6e1c9d92d87bdb3f618bed698326b39f9dce128609cc036903f4e8ad2aea213886ab4c5db322979d10b85a1b3218eec668b	1	0	\\x000000010000000000800003b588d3bb7c23765e8695556ca856d9d04b5fe990d6a07a7cb3d0f2c004d3e9a6353945946dfb5ec1b310fcc736339adaedd17f1b1d140da41bcb1a3d93f9619ae52745162ee8765d303d1f2d340cf724dc8a7ae33248b6d24b431bc7f548adf3e4c8fb1208e1281a6e1e8ef9e48cf7b6bec0bcbc16e85d98a819d5b5f17fc185010001	\\x4d586dd6bb37fc964f68f81a99be0fe28b1814c3c5d33a86e5df2803f9c74cceb853aa4ed2a074f23a30076744d090001c32254dbb8b5ca2777b82e7752ef70d	1662909041000000	1663513841000000	1726585841000000	1821193841000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
193	\\xc7a1b8c93afb8a3940908405df3c3948903f4ddb6169c265610a08074af3eb58858c8111ce30c071d214bed744b09674256cd4f2fbe30fb7b999e1e28449f624	1	0	\\x000000010000000000800003b72593b99f4a1825486acdfcbe16ce794c25cf9ef3061b0e69997b6facec5a83d99fb48b833cb7bd67d615c5a2b6eac966d58b23fcce0a246b0253b458d0f34ec39950664abb5052da78607d3930cd43808df393141028cf9d57e1b0517c6a0e0fda5d9a83a052444821886c4260a47a668fbeb81e4adda2aa629d17e9ad94b7010001	\\xb0b2a52cf69cc388a26dec23749b2f876b2b0f3d0bf0aab54db1ebbfe7e0281745512b2b3cef433a7a13ed2d039c63124db92ceee2d9b4c292e4760676e7a800	1684066541000000	1684671341000000	1747743341000000	1842351341000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
194	\\xc809c4dd758a9f64c50549a61710c2f9723297c21a095d1331ce962914a0a6e5c00d635a160e357e105a009406ec9733edd61c7038661890f21162a878a69ed7	1	0	\\x000000010000000000800003b839e07b4144538e1af127ca5f64d0a856a01a9eb8116d5a5516630706889139fe9374394b174f8e05faee81f222ddc12d55288bbd093768cbc12c7d8bf84ffb962428446f6742aa10e33a3740e2b1b2336f9f8539d7f458911a5f65320ef61ff02f33cfea32ea1ce743685c976a2aac7e8956a65ef5caeb0e9e1e067dde8d23010001	\\x4e325d5a062e10b7ea9c81f2e037a32727ec0b6ec9bf306d058a8fdd57912ac434cbea7591b402c921a91e7606c7f865dbd41904c412ddcdc10eaabc4b38bc07	1681648541000000	1682253341000000	1745325341000000	1839933341000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
195	\\xcebd5304a33449bc131c0c6f62b294e5b9182003b2ea5e9980c077a6ff7f3cba954d713d0c3c64551e5f042a1eb9f476010c1bde25eda914c1c1118d459a68a7	1	0	\\x000000010000000000800003b92e1b57e7a2b2830a17fa6e48949ad0833077646c0ee4f609551a067f5dc6a63e6df30851e0f7efd7c8bda4e01d8b227b1aa93b5dc34d8a19deecff836689a582a1d937a0594a579f2ed2344f6ca39210393f285422be1902196be06e1b4b8e2a8ca62fc7d75db56731736c8b3e6c569d2380c0c34d896b55a4f55420cc491b010001	\\xd41cad8f866ec6b19c15483c9ee6776568eb467480e0fb83e68cc217bb6708f29131e5a8d22d22405de12d996cef14605308bfaa764c693f5f47538453d1c80e	1688298041000000	1688902841000000	1751974841000000	1846582841000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
196	\\xcf3148d5cb6b2122cb1690b388bfcb3d9bf5e21fce9505fefa9fbedafbd2d1fac4c97cfe6c010d40706f78ed1d823d8d139d66f2c5fe27fb17ad71e3ab4b5d18	1	0	\\x000000010000000000800003e2fe6d0233ae84f0b9775f2a36cfb6e127b8409c0c3a5d41b905df29e92567eaf14f5b118c84e4fb627e4af370fc748ef2cf941103f5fb8803c06b6849ad8dccb74a39d0a27b92e29389313d2bd171d813dc346d1ab54abbf1023626426c8ad3a40cadec4f2077b4ea312579fb7fe41235f76b9ed4a5554f99fb82424f941b77010001	\\x900f56331bbffa258a4b464bf4c4d8c36a7412904397ab9e75bd3168ff02ec4f984abeba5ab9370646243abe113e355c698947448cd5287b3628a4dd8e1abc0d	1688902541000000	1689507341000000	1752579341000000	1847187341000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
197	\\xd63968d3a81f12b6053fd2c2fa4bdc8e0974645d54bc3c99ca6b36c1649ce97dcf337d7e9b598adb6005f50fd601e994ccd47a46799dfbd5a6e925357d4d71fc	1	0	\\x000000010000000000800003aef4e484e49ecc7b52c904fa9eb749dafea5a12774ee4bfa008b565c61358fc81931960786a3deb539a383b37f2e5ea03d1caf92541e8f335fcd3801b29c983b6c70619e5cfba59bb407171dad10f8425043ef200c619c12dc0d7b196a695e4c45778ede289509eaf0a5b11027476fb4e2a129339e5c09c2d646b187abea904b010001	\\xb9f92c8cfb69131d8f4a7ee6820fa3b9fdb9df75575deadf644537187671c4f69b222a555c35dfb39b280a671eefa725fc18383768d71b073a735127d803b508	1664118041000000	1664722841000000	1727794841000000	1822402841000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
198	\\xdc81470119928893cf3ef7833b5902458eb478eb5818df9253006a851ff47a09982f847c6c5fb0f5b4b4afd03aacfa7da678aee09f702428693a2c7dfd5ac8be	1	0	\\x000000010000000000800003f14e1a81bef19d5284d7195f3b87d690f4e3c16cb076bad257a8e8a7035124e390b993b7c902c98db2fbe1fc1bfb14100c7acb600c1ef8b1a83439cfa692a7aaf0714956e9899b92098cfb4e02b478575eb7a85ea6365f6df65df517622b55860b62aa0d2ab8f54d54bddccda6bb091dfaccd503070e2b3e8b8d0227cf84ff4b010001	\\x79009ff37cae3852855addf23ad8fba33f5c1b1ee5f2a0ac42ea19bce2fe10b1a0ec73ea45148bf4b8948d4fd97d885840d34e78aaa87904749a48081b4c4301	1676208041000000	1676812841000000	1739884841000000	1834492841000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
199	\\xddb1b37265969876f512e1b723e592c6b5f38b1d823aed6993d937de7902aa18ab5fafaa9619b79c9e9a46619f8a24076ee8be0fe75a69e21cc9a333fae88886	1	0	\\x000000010000000000800003be046e26aa576f1837e52a6058fff990c37094609c9b549d4e226413e35b865bfc1e72f3598c7136e7a76f937c07882c3453fcc5a203b67dc5832eb1dc9ef753b13225da0c5a6e149fdbd539c105f6ea80fa186cdc72765abf2d273abfb72b93e3e6e5e3e390955d2215cb102794d8944c32374d8b42d102d31d8128a6fa31cf010001	\\x2a32f1c4ae917c2a8bdf7465e8c4bf5896143e591a340695206269908cbe33cb3903e9855d49f57e2817cb49ee8970ee498b57b20d1287e0608b49ca73841d0f	1678021541000000	1678626341000000	1741698341000000	1836306341000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
200	\\xdfcd7067f6ab45848c1980aa1e0020627b00025ab546117fae5f286a8bc3f1840392615f67a2fc4d62761647eef2780fcc057207fccdb88c1ee0fd553f131f98	1	0	\\x000000010000000000800003c36f1eef6700a2066a2739bdfb95530fb14de685ca22c17f0e5dd983417fe702049bcc139eee900c274c5a6a7e403395cac3a0b631f5a54ff97dc4d5f8770b0c5183a9c435cb7192b07074ed7971349b6dbee242a63a0d7ced410ae6d39e6c19776a9927faedfead9be4f3242071db258fc1e7baee453f7ebba41afe256b3ccd010001	\\xe77b006f94e0b2ffa60797594981e595a28c2ee8551c4a0f0252479a5483976b34fe7f11e717c51bf98bb6329a8fd06bc4ed6552babcacf5ec56ce521b2a9306	1684671041000000	1685275841000000	1748347841000000	1842955841000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
201	\\xe0018634c3884fa213e28027eddec69b43ad816b40e268a504cf5567386e9dbb1518ddc9c27d519972bd8ea963b200f51b5c6dd842b2c49560d1a0251e32a51b	1	0	\\x000000010000000000800003b898ab979c84d7245769292e55c46ab7de7269f5ef5b11901844c15e4acece353fe7667ed0fcefcfb7e4ea9f144cbf9b177309ca3a3bedcc0e87748a4781e09e4c2b27ab3feb5031ead84cea91b0a303dfab371c6039b43011ef1da1c727426520aae2019663259f777bd90ea5fe8c1d7a687f12620ff605c5ef797a2561497f010001	\\xdd5c7d8152b91d1f9aa40ca0bc79c2ec5bc8ca290b2785d37f2d44107ebe193697a1379106ab72b45716a5c1b05fde6ed37f0ce35eca1783b686dfd07cc69e0f	1687089041000000	1687693841000000	1750765841000000	1845373841000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
202	\\xe26544e001310d6c12d34e795bf1818a1139c90dedd768eb09e7fb6614d2e9fb3d000cc0d05a5f5fea24eb5b7777aff0c7595f383d86dbefdc557f11eb1982d0	1	0	\\x000000010000000000800003b211cfbb9742155fb3fafae2bbd4fcbfb105e9b19bd209b333e8d06bfb9e10ce2677a308c72574a2ac7e63628a018341dbb6360ad4e9c6e92c657fd978f6c3cb23cbeb6825bf28830ac2addba40973ee0de2516c89015d5bde1513325a6e1b23375659c9a507ed28c225861779d825893e4157d853037c34b76a185e45a27fc3010001	\\x9de67ecd792fa98447abc5bf5f7ab4a505c97ba094ba2cfd5bb83d189a51342e361b0767f1341e67568f35cf9b8e896de7819ac80ed0d48bb6e9b0f456174c0e	1691925041000000	1692529841000000	1755601841000000	1850209841000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
203	\\xe68dc15f8b164f5180ad4aafa2979025047e7577f2d839ac11cf4637848995a3b2b1e9fa31f218519263814287669351a751a5cf2a952d35d681974b70b36f7f	1	0	\\x000000010000000000800003b8788ace83b523727c343d49593aa2837ee9cafd20ac03bb2985bab65652c3075f9dc5d3b07fc35d3a14efd4d2557f89d546c4999a3216b38faf409b48982f8013725d57dc695f1a179b05afdb0bcc2511a94fc9731525b9a8cda919d3906de9aaaee28a657842096140707021f573a57f5625738f7e9f2cd692e772973b29a7010001	\\x6cae7826327bba8cb5f01b4058935a165cdb5c5370bb711fc79d1e80c97cda7c49fc858c0b6c14756110b86dd3a15588cdb5be2f4c956cb3ea36d2d9019b7306	1683462041000000	1684066841000000	1747138841000000	1841746841000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
204	\\xec398964aca4e6e0312d1b76d131def7a971738d9b63586dc4790dd3775e818b108da4b0ddd84df9d11a6b758cb8e4705abebf08b72ae59cd93793345fbaaf7b	1	0	\\x000000010000000000800003c44a2c02c1485997f0a068c04767e891c929d5d0db7659d6f544717326fd2c195d56ec2f8d607c2b581bf7b67d2671d00585d75c5dece506d470c7b1188aac3efc2a82e7b782cc66a5cd85632b2d84a6c07bf843584909e095ed482b1aa018c910bdc6ee27719c9aa78da1430607ac67d540a87deaa1a0a9b1beae869ffca60f010001	\\x3ec2e69f4886a6ec8b18d4bb9db3bad620abdc0d90c5ba81b766cfb5b82f511030dd14752d5b3ac6d3c2b232944aa3bfec345b0952c2147d6eff720969d68f02	1674394541000000	1674999341000000	1738071341000000	1832679341000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
205	\\xec2144c7abd9bf875510c95394a55e7b39d497804b12af5dae094f401ee6f32dad4ebe797883cee2d473d7463aa8e28ce7390fc5214cae72b33cc1ef6520fec2	1	0	\\x000000010000000000800003a91f40228447f732d5922372bc7dc077e542ce12c01be2241a82acc21a3263de1048f1cbb263302af6a34ccabd9bb23ab371ade2ca80abede2d9a2286e65402843a16ecf7148cef9b05504e1eab59bcdbb93b08931f55c9084e845ec52d1dc410d74e33a4777a533678dd898930c41dddfe2f17cdcd4fe7badc5e792d26d5c8f010001	\\x75d03223a107eaa7e9eb873c051aee55691929789e3061e0a27cc2cfc67f326a1a905c72042241e63b9356c1ba36ec0df96584be908658f725e938e44efdcb06	1660491041000000	1661095841000000	1724167841000000	1818775841000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
206	\\xedc5b0ed9d2d4a2699bc290e45b3bcac88cc01ccdef0714cb5f8d0f0cd71e22cff1d81da7bbe892533438eb1be49bf61c2b2e2b7a780918a5ecbceb4bade614d	1	0	\\x000000010000000000800003b5381232403310bb5f53a3b8e54ed16d7d7a6519c782558a7fec2e61723f9b2b4eff54273f2d3f310fc8cba5745702f604aa44f4d40aa203725ec2177b3062e3d2f3525f6ef070aa27846e34bc2f079f0c4a6e9fe2a50abb90439f5c9f6c9c2510c3fc07ec8813ce0c03a7b268bca30d7ccae1c44d4835eeb0d0bae6e31aa587010001	\\x7c0afee7587fcfa408f5e5182f5953c8dbf05ece2c499bbb083a5ff8ca521ad505ee2d56d8e9c48447acc487e2157345e77425d9248023223f9badee6e7e1d01	1690111541000000	1690716341000000	1753788341000000	1848396341000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
207	\\xef8530f72cd474e6391a01b16001512e5eed58a270918462e780406f52eb4b588fd90b57e595bae17c6da439efe5f6724eed06f921e89a96c86352fe1247bd4d	1	0	\\x000000010000000000800003b6638d5d681d727ee5abc3dd959a8cb856bd94021d3c50d5da8f6399a567520cda88e5adf83f38928762b7cd9a0c711c2a110bde410ab474ab855665b1602422cb622f61ca8756e861057fb970fdf7c9e3947111657932339ee0a1ea9c69e0118b4d39f5474d1440d79bcd99e216316ee4bddbf063872f1cbec7ff2b34351661010001	\\x246093715df40b87712010fb4d4b5522109de0c2d533d116ced3bdc2532df91a76e801c31ed390122913edb65aac172eb2134d37dcafcf94f4783400535f1b0c	1663513541000000	1664118341000000	1727190341000000	1821798341000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
208	\\xf055b832fae640f0d3cae42ef9f3bd528762d21f179fdcb89ec02895cb71b58218bb59deb8f3af13fdb33e6ee59026bd5c6a84423f55ecd3859e3707121233b6	1	0	\\x000000010000000000800003be0a32289e003b6247defe0eed28884f354254975aea584af2914ab573399994d8de57dd70346ee487948b4007f6393bc5ea43041c5e2878f4b2ff6bf6e675d27a47a1824d66c6ea92a59d360592c4b55f9ef5832f6594f26f9e688c069d3146a42543653b3845d2ee97a2981d2818da9155d2cc7b96c6d9c79654cda159027d010001	\\x63d85fabdb6036a90b3e0ddc790f988df20bf4debd6999113a8e65f3bc242257f05e4d7b662e068cfa2df597a7481848c57b08287d8129eddf35ce2d66833605	1661095541000000	1661700341000000	1724772341000000	1819380341000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
209	\\xf2b16b853326bcddfc245d2cc2a2a5504e4e1eb665ca20297fbf4d1826c7a2896a3dac348b1ef41d3fb8e5128ad638f429af59fcbf839c0b2a14889f36c63993	1	0	\\x000000010000000000800003ef4c1416e037824a48825a675aaa1ab786599f7d6539151e1c7e59528378080133353432023f4097a0289308af92f726fa2588eadcf372558579c3472b447f01c884b80406926d52ae1ad4a797fc250f254f6a035fb2ca25613ddab064f6328fc47fe642b6969393f65d5738504b5cc752d51df50c52d3c4dc9886920244f5ad010001	\\x011a702e543b80700dcb9fc7fa81daa41a59385398f619954c5924e48009b1f9632b07fd3e7f97d437f0c203e390a4b339637ef4b8befed860ad18fd13df2602	1668954041000000	1669558841000000	1732630841000000	1827238841000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
210	\\xf229a97d97cf329910bbd5d7a12442c23b51e2c1db599c7db6229ace0cf783f71708205248e802c572cc3f264009ec6cba2402f95081d37be0f93870ae4c94c0	1	0	\\x000000010000000000800003cec98b3cbbcf0144a3f467abc02156481e3b4add02fa02670fdbd9ba130684c4e19b3d592845b9735c508ac6c7cd29285575569508fe7eafab48b3aa04109d1ca700d4035d9a1ea530552b6b3991d78c0a39b4c2bb0e5d4aea8ec43f445163bc3751d1b6d355d1ebaa0a60e88dda68f6776ebd0fe62e45103b79ba583f23ec35010001	\\x4fc8a9cec3a85440d5fceb596838fd8f83b806a2c00b14abc8af10f19839b4c7e6c9e7ea178298f78ef0f11c0f35bf725f082ae5dbb5b9e506c306dafac5e80a	1691925041000000	1692529841000000	1755601841000000	1850209841000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
211	\\xf3e998ff3de5afaa8ed7fd775d63d72e9245b749b602f6cc3f37fb6bd17b35ebd48879238aeae02a9fda5374afb0cf8b72b09cea509acda1f60e831238199ce0	1	0	\\x000000010000000000800003b11706673535928d6df7a3e95c3ce5cd500b571bd8c8d9f231627ad058077beb005245317602f7cc446a073e0f8f4b2ffa0a1bc0d033f23adb323e7fa6e564acab9c3e9aacd2bc0d262e0184f056d61de5272c92cfee4d98aa71072092e01ed4ad180be2d40c996c2dc3238e34f964a74c2fd76406d8358be4218cab019b1335010001	\\xb24291f500d64e30f3f4c625a9abda123fad55beed55b45f2efaf0cfc36c320c399a9471dc6129040cafb56069aeeff0994b45d4c8d30b009a1db234dea9be0a	1661700041000000	1662304841000000	1725376841000000	1819984841000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
212	\\xf4a16b1cb14adc8a8c1a748df5db6c05046a58e2ba6e35fc5b3d055f1297b6d4ed1771a06caceb38ae7ef45b15e06f74f80dc3b2affd93def426e64e79b3092c	1	0	\\x000000010000000000800003e44067415a7494e8d4e5b0797f760dc4f482ee179dce837ed0c2dd12a831a04e0a336a52c02a637e8dc878f571b784fca701e2a901a876f6d748463ab488b12ac0489ee7644000ecf642e7ab169a22a47a4698dca9e2f935bad2d8a1279b543d90bbbba80d7cbcfc2c3aed8d1216bc9c692799f32793d300eac19584bd210c5d010001	\\xb4386356f66d576c26ea8031ffa626557aa57af1d335ef1bd7dd3952e99f12a087127dd1750c8a1f6195cbe0099e675151939eb7ff87c2d395f0c47dd56a9b0b	1687693541000000	1688298341000000	1751370341000000	1845978341000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
213	\\xf781c35b6e6be535b44ce281acdc39d0142de8e8b2ed9706f322e18171ceacfca89bf764564b2fb3ab486ac547d898d8557ecc8062da5d6a21b49c0846b64a9b	1	0	\\x000000010000000000800003ad93fce23d6d8dc2a2a3d1785521f4b4b21199e29e278b48561563704c98964927bfd44474e2b5f299d38352396e1a75b11c34bb7ea16a50f58986886e325bdbf62fb5662ae7a2189820e42a7e9f5424f5674142c8b0d294b0004efc7b57c13880382eeb95adedd2e4e05062b0eb9baf130a4d59b9bff5e964c32300c2e78485010001	\\x50038035c5d5f54531f513bd4598ad8b162394791208e23eeb79988bbb080a86eb34150efe3732bb33030b9a05c2f0a64a9118937621f16fa399a663f942710e	1665327041000000	1665931841000000	1729003841000000	1823611841000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
214	\\xf865bbae1f8110e4d2628615092758ce558d7bbcf087774654701797038c12a6e30e75fa88d15b7e1c064b900b5885ffc6b7a6a401ba454a3e7a2f5397ac9e6b	1	0	\\x000000010000000000800003bf781e801e00e5585c42da6e24dee76c7e81f52d2f66b404175ef94b167059cdf74503f64c38238fca6318a32cde375c08730a89e640c750597b64181f6490e1a14607e953d15ec4b4dab80466b5e3e4bbfe3175bbcf03fa12a0a140597e08144bd09c514b8f6b759eeb9f648e73d72fc48493837908c0e18814f758660dcdd1010001	\\x4753d7c31ca093882b455fedde58350a3683c423b20d02c13a92dff2280faf282617988ef7b5a74224ea2d11743534869857fc435deab9bfd48b88cc8b969c09	1675603541000000	1676208341000000	1739280341000000	1833888341000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
215	\\xfbdda93874c6f78bb30616c43adb8be631f378ee320d9fe8b0143108d6303bb776ebca602c2f5b221c50746aefd3b93873c35d1264c1200d62b9a6dee6ff5531	1	0	\\x000000010000000000800003a93558043012472110ceb617ac0bc702e1cbe8727d57278251bc55dbafaf0e7c07cd22d0db1a162058d9df1469a1103c91f1d285898845a8307bb2afa947e65e8333398fe5db152a37861abe35bfb092b773ce84d365c75fc9f4c6f67306f8d1cb930ce77a994e9039a0d1a56578c1564b63fcb687995140895ca77a9621d4bb010001	\\x39751c63061470a460d1d8bb11bf659d502ef329ceed2e4ac48990ce06c0c7aff1fabe39965cb9e481e93ed639f796c8f63d0e1327c734d11e854062989a5a01	1689507041000000	1690111841000000	1753183841000000	1847791841000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
216	\\xfde172c90a4d02d6504fcc96e04c4ac866d9176e3e1c1a4c9b8fb438ce0b0a8988793a3ac89ef733d80190985dcf6ff48c7943403ac5b1bee09c8474675fd892	1	0	\\x000000010000000000800003a75bde52eed4f6e8e69700ed399db984480e8bbf14fb3aad5876fe6ebd6c13438f1ce68b25a9cada1ca8924e0b4424901bc575fed5c5ab4a546ef532393904e70a601e3e58a0bcd335e54a7e9c355e1af1bbe961f9fc64e2d30ae684bd394414dfe12556de6bdc1cab8d03391d2d9431d1826aeb0a799eaf37e0b45e78ef7739010001	\\xba5f630a294c54dd33c752a0139461a0a626222c99fa558490957e477a867c99a58d0681917a9a2553e681963bd28244949087f3b2a87fb269b19ce81f52c204	1682253041000000	1682857841000000	1745929841000000	1840537841000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
217	\\xfee9810e77a5f5adb3e4b6b91b6fba14c70f41b804cf9258dc0113c2bee0cc6663d0bd87a3adde78a902d8c9b131001b4ac675b20f2b3b2ab7932fda425270db	1	0	\\x000000010000000000800003d81d812fdb303d2fc5b6c33ffb82433a5baf40fbd431aef92526db54c1c61636556fa6aab3b5c3e95909c58f9755f56097330f5e83aa7d66b6ffcebbfacfc9e40ff2755b3aa53a498b631538df41e92b3b43897444b498f23f22bcbc05733f1f0a56fc8e11158e413697c97221c1184496478747ae8e6cba82d99514dd8f63df010001	\\x6d26aff513bba0e23731d1413027590fd8e29b52f807d33afc67ea38f23fd90d795be471c1cbdcf08097365af01482e9456773107d6424c90e2f685c2c679003	1671372041000000	1671976841000000	1735048841000000	1829656841000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
218	\\x00cadaf86a98ea272cf89c815bd1fc433c584c7a06b7f444c81baee67c1d0f2cc9e7678e0c302218d75b5e07de7151ce074ceb3d6ce9e8882ed13edbcb2ad470	1	0	\\x000000010000000000800003ed35a99d6ceb277b80d37ba0a70b2f83fd0f87becef03d6eb718da85f601ab937276bc99376dda7ddee74d6575fb86f6073559121ac8043837d331cf7c69dfc0705c33d97bfda5cff644ffa6714050361fc6180c22da125351acaff378f9b634c5c59fe241ad9aeb05938a246ac84e2b78ebb7f26ed7371f0048f70da9fba6ab010001	\\x919c3a87f6e20a1b435abbaedc8adf705d81d511c0f76ef366afbf460eda80daeb831d0bf77b7610ef6028e47cc6979a91e3647779fad9aae32ef83e396a2605	1670163041000000	1670767841000000	1733839841000000	1828447841000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
219	\\x067693e94ec46e17b3f7438938804a0827d68c784543ace3c462fd1bba2d1d11ec995117a96989179857e5ff050acaf438c896236e307d6ad6ab18b0816b74c5	1	0	\\x0000000100000000008000039a60f8382021f56828bf88268522f432a8186818e24533f80cacd1bb7a9f8d9d355d0f8eb40d69c03161b29ae2e143f24f87fe1e59d13eebb8ff09743156330b031c0d4a86ee744274ef6e2aba04dff5a42197db9d4c8e2dccf229474c877a9354b61cee44e5fdcd7f42674f7b1a4fdcb68cb506636ad59739c299d68ebd24e3010001	\\xf52f8d37bd10695860adf9960599fd4a920abd39bdc445fb4df0c7b0b75d6c64d8810b142550f5464b74f5ad1e283a96d4c2842f7b19454f76837f25a251260e	1680439541000000	1681044341000000	1744116341000000	1838724341000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
220	\\x0b1a1874431690ec87e571227f510a8f8191641995e188680b0610dc644b77e6791ac15f9ea633780329f66c9ae7c422f118550eabb4c85d5225991b71f078d4	1	0	\\x0000000100000000008000039ca5aa9263b4fa32acdea739d2a38f0abe738bf304f645461996593230baf0e93e9de11a32216eaec8c87bcc89c3e720620c4c0c6b132a5ef2a4923c83b86d10aa3aa9388f4ce1cf2b57d5d885cad870b987d005887387c7f8fa6ecd957a77c349af09c72f9df96af0437b6f597d1f6ffef9744421e0eeabfce5e846e54a9f93010001	\\xb71246e94ece966833d7fc768dd6c748b6e366b39d18b7278eca55ae4dcc0e035dfd8f0998fa40501225321bf86364270fb94f0ee1772c3c6ce3dae76e52fd08	1673790041000000	1674394841000000	1737466841000000	1832074841000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
221	\\x0beee3878e822b88a5850476aa1ceee8e774d508b1e0457c3f359a762ff8f856f4aaf17791896aaa068c9671eee8d19be93b8518d3d992dcfb026888477916a2	1	0	\\x000000010000000000800003a7b04d4bd5eb4fb1bb0ea9f0c79471c713fa7326b6fc134e65f5a01dee4b12e33b4e280b81923d495c5d7bc8288c7b44ff4380587b6776a09fd1324bef67cac92bcaf9c25a32d754d6dc72fbd46f2e201368cf4ee7e2ff58fbfae224b441ff4f8f6a08a791999d470a0c1e91531e0bf1545633b5791626c9915f2ffde53f0953010001	\\xec01166b0b1dce50a6c6a3e9a5c7d7c2e8edb408ec0d21e112f8de4ffe9b6d769ab717aac68ed98208a13ac8db86dddb7eaae8f7014661cf7af97ef504d7050d	1685275541000000	1685880341000000	1748952341000000	1843560341000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
222	\\x10f2a6fc75853ad8169652c3a82264801f2de3a55c300fa6d7dfbc66602067e029dc5c45358a59ba26901f5df756996742498ec7b11552a31ffa4826463d3f20	1	0	\\x0000000100000000008000039966890e4948f0abc39fc199591207cfeb5012d9d861dbe482b388c9a1b391764d9ad4e26cc6456af39869396b0b4414a1bd722209af1a92b1ceb37b420fe945dee4498b58844c419278fa4625ff2ff112e74521397413cc6d8ee280f8f2cd08813d494507bd386270ba7a9f96129d58a06d0026b3f49dc9844c775646244409010001	\\xce289705859dd038436eb00dcf8008c9b2e79b188f828ef4c9b43e62d6233ad9b94243a2a11f3ddf4a6bbbdbaf6c4983c15b459afece1bab70ee2d8a84a6230a	1688902541000000	1689507341000000	1752579341000000	1847187341000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
223	\\x11cab6e45aae7d6b7fdc37eef6581b180fc6d985c1e59545da4998ff1ba3007c99215efce9e45d5fa394e1dc5f2cf9e19704955f09bc333f9d9be051c4793015	1	0	\\x000000010000000000800003a77bf7a20b23f40a6a84044398f6ed15f691eca202ab1cd86bad57438c5b486948d3e83cde09500b5664dd20f44930efff347232300e72cc68d1e8dea6a4c5609e064f2786c98b2377ac072028f5b54c028bfdf1eb2cfda31028ab49cb1496f7cb2bfef6b33b588ea41a3ace3e7158c2c9c98bcb0b27d96447f107937daae96f010001	\\x2dc7e8765f019d3ab77ba38a66a72ba7a9e3646f915f29e992687a0722f9c066623ea709a76dc5230a7411a16897f6b04aedc8c6c0b004d35a75ac5b9745b405	1670767541000000	1671372341000000	1734444341000000	1829052341000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
224	\\x12769e77efc0125ae5f1032aa0f93c09438b4ad936d0624254ca01695cb8caf9b2ae1829235f9080cee4523c7f5ac4b4d2c712cbbe57c01f0179d68ee9a773c1	1	0	\\x000000010000000000800003c903cf6ac9745a2c7ae48a917b73062b39014f537a7cc76a0ddda44ce5ddbe2fc1570b2959240a0ee61f6c1aaf61a6087b1019ad15d1154336927017aa638b2f9fdfd7fd772078a7b21dd70eea4c8a9a895548089f5cbe8d83c4560bdb41a121aacaff3265077021686bb2eb9e8afa6cee3cdb8aa621c956aa0deff6a25c3103010001	\\x0f39a3f2c7b66d2894b95c0822d95ce10745b769ca015367e48e0b81176bc846fe89eeb0b53283923818f96c60c786a588072cc57e5859201b251e8429e8ca01	1665931541000000	1666536341000000	1729608341000000	1824216341000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
225	\\x13f27d77838c05c29b7aa620a7ccf148fee51221b35cda483e634aa1b9902cdcfabe902e57d6170e6fffa4f2bae3c834a990736128970a8c900c6b1e82ed3aaa	1	0	\\x000000010000000000800003af23d9bebcb26a4cff410cf19cfd21e8741838fe50b4277b76ebfc2b5f511cbcf4ebb6010168a5d31341ea8b7d9ccd9d85b1b82c65ff56fbcaa21473f088cebc207d021c532831e4da423ade6c10a90df271da852c19ecfbcc46dc540a93877b965f14130461e691810e2b1a438dbba27fe68119b68e49c83c80b82be893d7d1010001	\\xe8457d3c6b8d88afdc88f9910505d471ae64832855f7e984c3bea0e51b35927ecc91904116eee82b1f3afc41cea54b290e4ab35557d9a16187338e2d40b85606	1676812541000000	1677417341000000	1740489341000000	1835097341000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
226	\\x155a0b03e4b4a7216b62e153a76ab37d1fbcc2ae4dad1da09a7131da1dc9d38d409035225894bf28a5280cc8fca601aedf64dc57ffbab9afbb817be6516951a2	1	0	\\x000000010000000000800003b65578b6e338814a594a9b1750a1388a8a92a9ead800876c351a5e64f07d60ce803ea0e08150168ccf768d13309ee160891ed67f8954b0aba32d84b9651111fbcd4335439768553c2a421e54638d02af5a125884c0dd7d2b296535de46d3a9c08136345b483dd26d95612c752496fbc0bb49f89aa9c39598eaa0cf5f95ec96c9010001	\\x3ff91dade59aa2f550edbfb3103109d0d90bdd8dcd0b47d3b1e48e93d30e954a38ce33551538ccbdbd9fd799e22a22abaad88cb28271455919590c09647e5109	1680439541000000	1681044341000000	1744116341000000	1838724341000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
227	\\x181ace0ceb608ea1cb7fc92a9d6951ed264465268073734dcfa44ccdb676ba08f4579921a84f5898915696f8165927365351274715aa3de9f7e911eefdccb7cf	1	0	\\x000000010000000000800003d5fcc4793572b030c92d7d08797f601a7e514cce2d941354141a25e7c6fabba2695f3d68f5e7b67bb748617da30c3b7b5ca1b061119eadcf690b06588c074a65c886123af597e2c840d69cbdbba3d73f62c08a6d0c89c1698e74ee7908fbb400366e03381a87a7bc38cf1d77f2e16803dc1f25a55591e0d497f3906b60ccc03f010001	\\xd66912bbd627a63c0f2b7299e2e7ab4f90dfcbdce054fa783a39609a8ebde0c2c7b1da63633eb68040846dd2f806d036677e11a830d77e046c2944c6d9246001	1668349541000000	1668954341000000	1732026341000000	1826634341000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
228	\\x1e5a8a77686443665060edc1a5e3448ed0a31956171a0311899f5dd5f2c3079c2a53a098bd7c8b35db171560d8454b47a13c84fa0dc64e911e16e8bf668f5f87	1	0	\\x000000010000000000800003e6354bf41f88e00d1548d79801ee0c032bb1c5d8d25faa327a964e26cc1559552856345ef9a4d8846e8e2d0a71dfd270bccb9dcb629678befd44c0d105c7dcb261dd104e909b2f7ab7ddae7e8461d96213976a0d5d876911c1cd0b0bbdc7fbf65e612be5a1ad30b6b0505061623a8c75d4840e470a24bc1fbecbaae2789b4069010001	\\xb7fd05320c4abcbf71b98667815a99efec2b5bf70c11b9ebcf589804f9015779179752d6858a8be23a1309b020aed72640f207727d43440e17956a1f77986507	1679230541000000	1679835341000000	1742907341000000	1837515341000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
229	\\x1faafe56431bdd32b100e15bbc99b8063de4bb8556cd65e01113f606a171262cecd29391589bcc6a1424c9fa7160e8a4275dfcecdc9b1e4acf4811f627ed3ac6	1	0	\\x000000010000000000800003d1de77f483659285667ae2b8bc28af39dfa632b89729e58321a982bc752d073316870930c8350a90667a2be96b1d5ae94644025a9bf007258b22cdea38a2e96c3db52e942ef73b043d70285da447cbef97a6aceb43cb7c459bcda4d0e631623ba7eb471d1d9747abadb3cc025e0aea40e8acedd57a112ba98c3759b953794f1d010001	\\x649e23025345d56bdeb0cfdc9490bd4836fe02ce24058a9183bfd6ea6ffee90b50ecb8ca5b6342e9e40791001ef0a6365014119c0e7a43126fb3645979aff10e	1665327041000000	1665931841000000	1729003841000000	1823611841000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
230	\\x1f46be0157b5bc690217b7c22692f95b40329ce2cdc49859e7fff40722afd4468d20e3114d99caf48e86bcba336fc51d11025b1970ba7a30b7895ff9634063d4	1	0	\\x000000010000000000800003b42c2c7d1aaea87f239824aed2c37a516ad3a6cf89aeff627f7a050eb3c2d385d07081056ac4e6669f126499ee25ea94597ca24e0d2371860489821cdcfad7bc97fe33a53201fbf74861125dc627590b66ad925e163fcdbdaed6d1892ef301529a56fe61651798036cdf80b92721d975a3bfd65a8ea4d6d1305f9a6e784b5c29010001	\\x43dc57f095629bbdea2606c9b7704376ab1e5d9b522b21ffbeb3db019d1e006a542e633763e5cea0e9b45e306fbdb07473bde8df2519d37fb1e99a6576b7fe0a	1688298041000000	1688902841000000	1751974841000000	1846582841000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
231	\\x213efa93a971f5c433e8408fbf1fcdabafbf7ab7b344d57df81aa1423dfd1e7a6d7a074494cbca8aa51bf1c0e1790565de7091775aabd712860d32a9fca7e26a	1	0	\\x000000010000000000800003c27616d2696d732166bbf3c0f9b600c3a10274de345544a5b792c59f203c22bea91ec2e07ff21bbd78b1e6d1b00876532d92ddc400bc7c7f7446a2713a096147a189cee285879c60efc6acdd9f8b645bd0739f9915042c464008c9a70bfccf1e4383c908786ab841ceccaa7206700d9e3260e47a3347ad61aab3de72ad472ecb010001	\\x8a093ff3245adfad373896d4c40185ee8590b5554163032145de45ea04a8a4d4ae5740c767fc2115cbf97e6c211dcc80d22a1abb7f52fc6998847d9c835a5f02	1666536041000000	1667140841000000	1730212841000000	1824820841000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
232	\\x22b612fcb76251305f41cde451590d649b50670ddec4943b783f9424d405b5b698ae6b42ab8fc02dc0b60a2f940718751593f071c6c5e8cf11306ec6ab013ce0	1	0	\\x000000010000000000800003dc9aa8f366b01d356b76921c5bd2158cf60c78643d72efbd67a9fcffaa4ffce60904015f7e3f35566dd75987d5d8905a1fd75c4ef3d30c90e9178d1d8ef8b951826a254d727f02642a8ad91c323f6be9d951f9e41a814aed530f7efcb75f3c0cf6bbde5490d6b16f9e7cd28692dbd6b703d29b0c0f621120a64aaf21352e786f010001	\\xf9b9fb479697b05859e3a48d178b447b2e245435b46357e81eb8551618ec0d3edb81e2ae307a8245ec177eb33cd6cfdbb5243214a305cc0f8e44bddae5e2c901	1683462041000000	1684066841000000	1747138841000000	1841746841000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
233	\\x27daccc8b2bbc60de4ebfc5d287f643fc6b7ad46d7dc2cbbeee0b4e9f4abede5fc447f1652f9c9470463a97ad2653b75fa1f39c06159611c63afcf451f8070d2	1	0	\\x000000010000000000800003b2ca499934e6a3d987401604415a2ad0d977bfce2e7e8dd5d06958d18426047bbfeca3389a2729d34fccc9e0fb8955b2c33860ade51c4af51b4937e7450a3f791d6f47ed1752248cc62b18824c10c0f8b632481b415bfbead91229e10f0277ce433d0ed7af454ef71075f1b2e13f25c0dd9c1887de016bb2fa4402833cad035f010001	\\x4b887e043677fdfdcfdb525ea0d494c68fec90744216c00fa1df639e0bfd90fb7fcd80001544af1cfedd78ad11140f588f7fe880f109b4a3650c6038fd49320d	1671372041000000	1671976841000000	1735048841000000	1829656841000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
234	\\x28ea51b8a515206e96ea25fbbbae2291b443b2d119b068e585efd764271deda8c2721e2af16ed1727a2f11e5fb2e02f63c9a7541090efbcdff8cfaf0b42dddd8	1	0	\\x000000010000000000800003a85fb7b370c35ab756c5f49c7705653822a6930e94e9155c06bef5e65f731206a3db8133b18d9c597fc72f293bc51f508ffa71827cb4efa31087fd6ac7558d2f0be3a4ed931002c048ae66511b69bffe04d20a6de4025580bb003987484d3fe04994d88406a0b7f9e478c52479a926d1f24dc7789b9cdd825ddeec0cbe9b0f2f010001	\\x2b164497995b44491dc562f16936fa9a0601ecee852519a1b0c92920f272516d1dd25a32389d2e8019c6e35b5fe83a7e79f679162c3855a40512904bf54d5505	1689507041000000	1690111841000000	1753183841000000	1847791841000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
235	\\x2d6e0fec38ed2d3cbdaa6954a674cf885360dbed05ba639c36f070330cf3e5074936226584d49d4962007e9af66c53db1c435858ab881bb292a714bd4370135b	1	0	\\x000000010000000000800003b5d06a6ece693b3543654484533e3990597ffc8f227e282c3689d008f01701fc7d321e2946e8b48cfdc12914b00af18dec9d88364645687c8093c4eb3f37e9eb63773a099f1f599d1ea76a39cbc8721f559b2fa66a168e18c810a9ad9dc91cd331d9d4baadf9b1e58a31d9f03bd11fa8500e349b46ee803190496307b259d493010001	\\xedf8e2b7f30746c1f30985364bd96cca57bf0cebedfc3f87a45883f2114135af6a298c8b26a54fe6455559c66001d58b9afec17aa0452b365d44890f449a4901	1661095541000000	1661700341000000	1724772341000000	1819380341000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
236	\\x2e966c9e94104ed253450203ffda930f8b53482febc6c843285ceabb845ba5ec9dc9e820b0e72d925cd1181d0d4addb503982e62d45c79561c02c6f21e740cc1	1	0	\\x000000010000000000800003e6528c642d86e1a4945fba357aefeb2fa67e11e308966476f6d3843a04e9b387d1ed62fd014af623335da7e65c716eb7591a48c827e3343ae92015a9610301692b949f177736e47b7247b2f296883c8ab8323842069b97362217c54eee7a0408f68ffd087609df07d18970d4ffca6ff699db8b8e0d8b4d69846b2028d3c53571010001	\\x6809e308ec3972315f994eda325cd3108fb88fa8423f58306b502abbeb51a255615a19a572ae6273450e9c728530bdc91bf1ca679f59a86889379d1c7d77be04	1679835041000000	1680439841000000	1743511841000000	1838119841000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
237	\\x35d2d70a01d72bc132e2d2ee01d1285f402078500bb1ae8daad81727ada58c236a86bd21294132ecb800ecc06ca0e414bf9b6ba9d318248b1b5760b5343d824c	1	0	\\x000000010000000000800003df4d03a672b35d80a698c903cb13b5c0eecd0853c80a2c5e81e050e6ae49db24c61617cc690c55271fe7e8ec9485234b686dbe30b974cff8756eb350803a73dd581ca3db81506bddb7b0d8f222de91ffd52274636efe8c6fa6417658a6eb852f36f6800f021b28f4fadfc5e69290039f26b92200ab2bf323732f6ef78e4c4fe1010001	\\x3cc9fd44ae28c58e2ed506a1e9a5087e539db12070709a306751590e3fb2b640c807f889de6c1d6c9f67a618b465ffb47b228de772e9b3448f5f74286a921f03	1679835041000000	1680439841000000	1743511841000000	1838119841000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
238	\\x375ac90b6779f297543dbfbc67f43d6635ddf0649f89ddd01a3b35bedf5ecae1de3ead18eb7ae97bb2233370fb9ad9709037f66ee590288c25c94bac9f55724a	1	0	\\x000000010000000000800003f49186e8474de8b86caef2451dde99fad240703b75a1717cffd670b14c211d80ba836ca30817311e3a1040448f5cd679c47a14312dd271c6df9a8ed60446c67ece7db415d7f79b7220e0afd5c99f5b382bc3cdd122285cf70f4543d8e892c854428485d6e79f17c699a497ef462b431cea23266ebb3c4cec626f9fa90cbbc2f1010001	\\x1feb59031240e75a2c0768265136c54caa7a7f5237f5af0eecf0ff00be02332229f70074c686783c1f2784a5107dbb220627966dc380658e27fe248994dac00b	1678626041000000	1679230841000000	1742302841000000	1836910841000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
239	\\x371ef4e0d2c4724f84ef550cd0a2cc048f945f0b5c57f3cba80f6d81a3fe145f4f23cbd32b14b7620c90c01beb1b1f58843b404e7d9fdf0f93026dcadff4a556	1	0	\\x000000010000000000800003be508a9628c0d68ab58c3765c5c81e9ffa3b0f9a1084f3d3de675b247eb0ef6e07c24194ebd3291f1f6dd0856541d0e2efa5ea3e302b66bdde5badde1469ee12cc9054ba1209cac405ab305cc2cc67af77941d8b043e3d7bf8435cd194b92d35ef4e029172ad9a682b5cc0e4648be2dada7913f3e837050c1d1f774ca849588d010001	\\x50a60cd0d4a914f7f3a6cfac610ed9cb8bd2801f6e3a12cac0facf0574963f96c7fd625a2b0a1bdc5de9adacbecbea128613f2cb06e0dcb98e5023d6d2d69c0a	1678021541000000	1678626341000000	1741698341000000	1836306341000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
240	\\x3e66bcd90cd0783315c8c9b657e68c5d8e7f14b037c42687a8d4faabb38edc37c77b7d378d9b37a060c3ad48423e5a0d5ea9d3e7a1a1236586a5c0c0475ba4b5	1	0	\\x00000001000000000080000396defc76bead0996a5b4575290dcc703dfab731487af62b9e73555ad2fee19bed90e25653b0d8e51c80c0e8df9e896c161da6412f36068d6f1f758c5ead1af56fafa83a839618e8a1a02becd831cc13cdf60dd2d795cefb58973bc9ec761a866f205200971c66773a7d64ba39ee4959ee3b475e73881f72d3f5698bd62928c51010001	\\x2116194255fac21f03e191e11bd19c1ab2911e0799665f46e028e475b3f2f93c3bbd16f703b6294d0acda3b84bb7d4544d3036226b3d3dbee4c161652a6a1e0f	1670163041000000	1670767841000000	1733839841000000	1828447841000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
241	\\x4086ef764f943f0a95e395be2afdbdf4ec17929c459f4efc6b19700bb175c8514512d0f2715f7874b1ad8de3cb3bd9de5989689e75f05a8eda608d016c20e170	1	0	\\x000000010000000000800003c73c12abf15c12d7850db73f6990d4eac0b65d0508fea7e89a2e8f6ece1cb5edd391146820aa6b8c9208d32643a2e5efab39dcdecff08901791f87ecd830c90cf5aa418ef790eafe3dff2fe9e3acfce411f271cb4feb2b21a640139f9c0609b02dd63644b20f0ebaad22df30cb34b8b70f3e06895f0c5fd9a8007396ac275425010001	\\x9d0067664d2383470744e20e67693b1fe746f66133cee06c683c52b1675285c3f05a1005cd71db94c252f395400bff1bf7ad368381b5ccd0e5de9faf3217690a	1682857541000000	1683462341000000	1746534341000000	1841142341000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
242	\\x42561ad08476f0a40f89333c622f72051e9e5fbec7423ecf51984fe7a0d4dfdef873f9dcb324fdff5cd6390c853941ecb74266bb79dcf6502c6463d2cd64a29d	1	0	\\x000000010000000000800003b4c4faf373903f232c14ecf36756a6795c877601cb59c9c481bbe9ad6458f86b3ad5c47ec16ed0a963a80f7e7c253a94930a9a5421f8380ad68f31596649e92e0133b39b98b149abda5b131876ba31f9af8df649598534a8383a8b21193367f31bc97463b6083118163bae11ac79f314ea99945d09b8ca50bf97f7631b35111d010001	\\xfbcddf6122d9dee791e9a9a534c3456da647597e66ae138011db62c41f6e0ba68b861cd5761b2b8e366926fbfc514c39ea11e51bc6d1ca6997917ba1ff96ff06	1691925041000000	1692529841000000	1755601841000000	1850209841000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
243	\\x474286a76fccdbae6b601e32f79bd2bc49360886fabd88d23752479ed750fd7c9afda41bce23e2aee04e311d2d7e76b68e4cd94302927c2d99c74e2b899780aa	1	0	\\x000000010000000000800003e1f823867431b363cb7e790b12230c543a8db79d62b6adb550c4ca5d3cc875cef623302ffb0b4773e927de65aa0dd346c0d69dd4fae24caf3c611500141405938931569fa49c9973720e0b4fee2e46e33df397120f04c21b2423e94c588d5806b4d1ca606ace0c295b20c65a69e305a799897798c97b207b01eb671e910a4ec9010001	\\x98d83db5f3370ba1241ff187d072afb32b170418bd67c627aac2d4a92bb0ed87cf2d9110683ed95e62cc1ac845e9aee7576385d2af05f1b1be9cf020be6c3307	1675603541000000	1676208341000000	1739280341000000	1833888341000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
244	\\x497aee1d1c166c01f952580dc5015e8dc21cdc09d07d311b3ab87bd3195af842bcfa848672f6d81b1715988b20e5aaee1efaa53b03c694673b1b656f4aa13b05	1	0	\\x000000010000000000800003d10d0cc04ea9df492fda349de58a13be1dbe4539181eed58ada3190f55bb5e74b4ec3f2fc77f6c2082b41511850630a947ef9f95fa55ca9db3d7d32eb4293c2de7d3490fc6799f5db0305363efdc383e54be0d9e5ef6f147ba8d6c4151a2ba3366b694f183fe53c8fecb16d102debc8b245f85d5cb26656ed274a1997b14f0df010001	\\x90658b6ae605f079b6ec4f72743b8a54224d33e3635dff9214da5c9eebc64bc635084993b8b0244c60b8bd980055f1d1e1725e94fb711ba99f0d9712f012620a	1661095541000000	1661700341000000	1724772341000000	1819380341000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
245	\\x4bca104d994490629d8d30534d224dcf83614453a6a064681f06d1c02844c2c9a9b70efb2dc90209761d4ac18ffd53629f732725ea9fac2f3e860566e0324ffd	1	0	\\x000000010000000000800003d407563ec5b5e7725dc0f6125140b39b50a2a5b1661a743c304825ec4e0cae271a9bf64bc5ba2e70528fa5153b4f43092a38d0211ef942872d4b3afcb291f4a57ceacbcb7ef4bf052fde490e5bb7e1964c3a40457cdfb6e327ac26841ae8f73d56b89841ab57e13f537030ba602e8b6c58969b1c729addba82d0ad0a4efe066b010001	\\x01dc1a8b9d38eaf0744d5802421f5de9bd2c26883c09cbb3269d2eb3e6f250326390a737c82d12f3fb7a5a4be7b84500eba9e5f2ec6922d2ab73046a9adb7207	1663513541000000	1664118341000000	1727190341000000	1821798341000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
246	\\x4c2a38c81011d161b4e96a1639bc321756ff07435d9abb9405333e61e94138134033d47f24ec693733378388cedc9b4ebd900ffe1560e31916cea0c7c0ce973d	1	0	\\x000000010000000000800003e699f8b6dc333ceee88ff5f8012fdc07d617060b76cb519ebf706cdb7a31e321211a32d9014d880d54287e3ad7f23395aa7040f7f7df070b495d2d4eee3d18ac976b629a30794c5b50fbc65e4aead9c1eed6a31e3c19b654c7c0fbdc3a0504a0f61a94a4766d040e7f7d89624502a2892e53ee9788cc6a357fba7a788170be8f010001	\\xe5ff2856f34908a8b076e76d2f1c807ed07fa3d067cb7529a81b8ece0761a9054161329348b267e8e4f5b829e753a6d6e2427b0dc297b6491fff0038eebc7502	1662304541000000	1662909341000000	1725981341000000	1820589341000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
247	\\x4d3ad560be522632d9a9d1524da9f62921672e78254234ad63d9a4439c4730788105388bfc1ca9e54ef52b2a46bebc639e3affd6e08b285248ecc68abca057df	1	0	\\x000000010000000000800003b898a3459f9caa0aba406124c91f15ad787b7e3cc736a730b16a7a3d6eff66c2b31bd6153786b374c94799b74cd0b203b5501f9b481e7eb6197ab7d369550519763964bf74c5eff853d693a27f1a6e0e3fa465ee4dfea166ad519015ee1a9b2d9ff3b999895c7a07b7fd2451c5928c656bc951289b6f66692fd254742f1c5c2b010001	\\x9f620171fb9e01c92f7239b6159a8baea9270feb79f163059f315668df4570cc0a953dd21064be13ad3666280ca56acc69be22981b0de080cac67b919a1e5500	1683462041000000	1684066841000000	1747138841000000	1841746841000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
248	\\x4e6a09c896feaab34f605e23b3d7fa8b16fbbab178d54f061f0330ed794e0e1fdf4da18c62adec18e11953a79e8dcd9da85542894172e7401d4d28edc4260043	1	0	\\x000000010000000000800003bccbed5d3247a150176e21be545ceee7eddafcde3be22f5b6d7093c524b314770f637444df75cc077a1340f152aad94444095563b2c89fb67afc326cf6e8d676f1efe60bbce0da8453a43bfb8969a56c4d123fa74082b8b13837d37c0c6a13b23f81f3f8ec3397d90a9d353ae13cdad3141c8b7e3446803d71befb45d054b283010001	\\x672f00324245f32914544399bac5485ef92db238c3ee03311c9b444cabd909355c8209cdb85ab16823a8d0e00e78bbe826969e2bcfccd7b7d5edf9af86ca3c0b	1666536041000000	1667140841000000	1730212841000000	1824820841000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
249	\\x4e0e5da212770661b019e783b2844db1f958503aa2afd1c54b22dd80cb71192492c2a3102e208240f51abf94e9dea227ed9fa9253e8156908db3c01588a60f23	1	0	\\x000000010000000000800003d9ebceeb7a52e4e0961e996347d956c7fb9da5f284636a6ed924df440b772e63fc723fe22e918ada18f6eb9a00d5a01516887a0b926deab0fc1d1fd0742ae7f1328c6c3053a7601197434750a1cf0bb917cc63edb224bd9f2c0604a54a8af756789988faf1bf379df57b6bd0475009fc5de7a7f2cdb0d55fdd968cadf1e71ba9010001	\\xa3bc9a6f3cc37a214486af6b2a25ce794bc998e6ee5671e6922c58695d9a5aa0e5945ef97c8c7251a81a99256dd320fffd7eb0dad7e92b73dfcefd7189719d0a	1688902541000000	1689507341000000	1752579341000000	1847187341000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
250	\\x50a69b1312b8505493f3fd8adf38047320e8dc405f71a67ea58463e1faf29089d03f3582e1c488f4875755987ce6c6a5f11a8381eb7034414ad8638721a84b2e	1	0	\\x000000010000000000800003cd9e0c3251cafcfda3b5bd211341b885edf9d8fd59d073610a2b1d63dec4b8e0df5d85b8fadc6ba221552e9795f3a0958d38b3437387ece499d9166fd15226642a34cb85b90db35501e2bdcd80dd94a6717e4fdf16f21014b9ba375a957ebb6500905bb8620fca679a31f2c7db9951059670bb3e5730fc0dbe49cd21ee6b36a3010001	\\x554ebc9f7569bc6fd4f6a44f2c10863eefaa000fd248901457b190d8bf953bd8c0279e50346a360bbfa11effb6480278753c6bef394e2cfad57329fec1f47503	1664118041000000	1664722841000000	1727794841000000	1822402841000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
251	\\x61161848d6bd06d5ac7d2230fd7b11a92c4465f2bc8da478d34508d7679415307624bcc73739b9a6736d644619829056e9537d8d7def5c480f55b2569b0ba591	1	0	\\x000000010000000000800003b22097ce477da6328dd798dd7510c27cb94a15990b0414e3d5a0f200d4d82387937ff029c97845a1621339d3517d3f63a168ffbbae53c1c66bef59262770afd1bc65e344fa9e2764620d55be72c4effc92fc878e9f0f50d4a7bb47c5073add071933705fb2d5f8818b3b30dd26bb3df3590e6410ba8df87f46beeda82f9777ff010001	\\xa52cfd50069f767cb23b169a7adcd9ea89a49faa6e6cf59c3110a3ec1efd75ee522bc09d9ea1277efcf1c19e1a77ac3cdcf774230c41e95c58ac9e3dff48df02	1674999041000000	1675603841000000	1738675841000000	1833283841000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
252	\\x619ed5d127dd285140110301cd2b61dfcb0696b420e130102b0215d6246421850a1198d95fce59222804d6d14605e41c15fe7ef24e7af31130a5f7634301bbad	1	0	\\x000000010000000000800003f61baf2631c381c845c966543217e3c3cc6cafeb9226079e62cdeb2549b5157ba9201b01641195a5505bb0b9ee734e1cd3fdd6fad029788a319808e09bcbd512a90f7e0c385d9b42b609efdfb998fbbc2824b83078493211cbf75258f739aa8c2736ed01b3a6397fe783bb2b7b9382716117097e347d1f3bd448762ea8d143c3010001	\\xe89d5a9f00cb0b37a984a2a4a090f1948777c5c86733694cc8ae8225bfa60496ce1eab5ec4f995f88a440a24b91d65a2c651c1777dc7fdd99e9fc9875c0a4403	1683462041000000	1684066841000000	1747138841000000	1841746841000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
253	\\x642a99d5cfaef24fdc2f2c2743fd2b0641f2de9dfea17bcdb37faab74ba271467850a4c23578d2b96afebcfcee3154f046a514b0b18d49ecbf3f48f2fcefb2d0	1	0	\\x000000010000000000800003c82b7b4f25ed148c1035fc1cad95609bacf2fb3939f34c898e6ae72de88a473366b2c63accf73d99a69dc864c1003b5f10c1bd5bdb0d87b7d35bdc115e151d3acbf6ba52fcd6ce82811d2692d7b17beaab4361db5b767ccf31dfcaab29c4799378a4e42758bb06c11fe213ecb948f5b4c0223fa52106e5b7eb21425777f04c31010001	\\xb5eb6316c7746c28175701a548ceb977446e7f78a190c9763618b9918c9c5dc6d429ceedcb56bbe9fdf7097cbedcea5000819da69ec2346bd41ff3fc04f88808	1672581041000000	1673185841000000	1736257841000000	1830865841000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
254	\\x64e65d78384080c270bb608498b9864ad31111985328bc2da5aa37ae0f30c14cb93c9100757ac702f7abf026a00ed31c8b604e72b4636af6b395164854b0a600	1	0	\\x000000010000000000800003b14bb893018b88f672ccc9d0258a9ca763bbe12332445eb30c62aef68a6cb031aefd3b43844ed4933d1259a4b47351ee2ceccea7a306a72c61f5496794b8cf3cecb78258ec009ff428a00ff6266b29ffc5b4143c35324e453b3f2d6a6018710416f6cc92b9c8b4d6eecc4689248f1294ff46fe388d3d9ccd3d9fd12a7e40ac03010001	\\x24b611c06e2c6f9973b724eea5de98894576951edc2a3e19636c11058c7e4525f679cbbc1d8f1e3fd8376ee96b4b88f580a3d9fc8ac2559e527439ed9e341f06	1662304541000000	1662909341000000	1725981341000000	1820589341000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
255	\\x64b2e8445fe69561233ef8af2affd223017511351a0abd95f566ead294e0df4f1cde907ec988e9d61e20ba0da1512ac57a5708c47cf25155020d075229c6e748	1	0	\\x000000010000000000800003acd357230e8e4127a19e8a45c2f9b00bff856a283986aa422236edb083728f2249cca0ffe20aa341f7f9c471fc2f971d4ec6c887145e003c69769c992b918a23004ba065b58fac7f99ce0e4ee10685452dd7059f3d1c05af0fedddeb71ac946ef59446e7a376239da273a43ef1a4fb9736a298e60a97ad7185c5aeaff7df0387010001	\\x62d78eb51bade5d5bd921fda5819cc9f41f76b9ec8e02ddb4e5124eaf60743b96f9f35a8dddf725ff9463cf04e4dbdca489774ee12c5149a231d4afe58514805	1690111541000000	1690716341000000	1753788341000000	1848396341000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
256	\\x65063850b7a68a550cdfcf4b585595a3a5c178a44ea7fe1f7aa9faf2bd0278e7c7ee9ac75675dc2be4e96b356f1cd99022047e22cd48400e5e358daeab2e711e	1	0	\\x000000010000000000800003cfbc03d7d3ba51a65e42bd6e6aa8a3d7fcc9e07d67c5a418dd3aed3de18eca4a6bef6386baa2c16f64cff38e886e5c01b917b27816c10effbf94a8d4dd841e020521a5e466d9daabdc9c4a371342eab32b1f0ed2a5046c2fdb0b7edbe94515b25da9ea2be9e1a3fa87d950beb1d1ecfd95879fb0a3ee50caf93b8716b194dd35010001	\\xff8df70a0dad3e098cc2d31bf066f2dcd40ea1ff336f34831872e2247855380a467cdd97c94efc5f2767897a44d6981056d9ea30c9c6f8f051de7c93b2fb3302	1660491041000000	1661095841000000	1724167841000000	1818775841000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
257	\\x662aeb8e613033b7bd9582f9de5e2126b6243821e9ac20368ba6138b543de943a14b17dd130175abdb99f6e90c292c35e3cdfb6a0f41da2d632e344e345244d7	1	0	\\x000000010000000000800003c8c5ddad5b5beb2e06fd1670709f990c3ac8c32629442dc82312972d5fe9443eabd14873a014133f65516f33d050d09d1e7ae3d56aaccab6b230dc0d14ed32916fb02b7a52ef70d38b047a6679c723d8c1e48c809a314e70fb83d5ac75b3beb49c6fd2756d5c4377a2984a7b76409731378972a1bc39fea7dc77240b213165c1010001	\\xe84aa65e733927592a0a21114271ea2e666586927c8763146019fd3f4e53b13ec1f813f60465cf2e405acbee5334f43a008ac435b6d7b0a15ba5d93a1aed5207	1688902541000000	1689507341000000	1752579341000000	1847187341000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
258	\\x67b6ca19a55427d550b2f06d5ec72a0cfb6b122076100015010d98af95117319c60cc7afda655d5613b630b5ac83800f1e25e122400bdc55b62c0f4fbffc7a3e	1	0	\\x000000010000000000800003b6cb03f5cdee1b4e60d7a2ee6fff62d48c6b8670a94041a4faf3de7d9ee91466dae6a43e1e5d921424ed7d1a78e3a6ae7817b73a9d9a1e036038b35fd210235d883d8fc1ed50a907e6fba78ea25c70425633450b724130a72e193d09dd36ebacc8fd667bc7251c60270a2a7ecb2f6ace26300cf4078dbf167bde40cc317a9fe9010001	\\x166d3e8ded349a4d7faf335c1bf162b65f9134c350a83d76c85267aa2f8be70457416f963c1001b8d8ae717d0d0245c883ae63166d3ba8d9e35c749e70cf6e0e	1685275541000000	1685880341000000	1748952341000000	1843560341000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
259	\\x731e8e4566b700475adb5de5b4de9f7cce85d8e0a3c830240cafc2089aa4f6b7c172685c687346599d15d04ac47ae43ce51b5c59c0f765b9f3a584a702d23609	1	0	\\x000000010000000000800003ad66520381ec8dfe3aa40703251b2742d88a4ea377e7e1f633859def7a32ddc19ee70c70d1c993b56cf7652eeb8d5b9529344374cf7669e18fc0c7e0d728d183aa6196e276b1843ce459fb4953e07b24ff7987e2919cf83bf28a6b5e8c8c64862b4175a7f70f660117f7a8fccf121b553213fcce899344ce34a83213136cb163010001	\\x12f4e1a017ec72e8195f7f97ee8834aa75bfb7c44937dcace3921f424d323995b61b0d75446a143c7be39d3b7f460c99b547cbab80a1dd15116deeb27e184e0d	1687089041000000	1687693841000000	1750765841000000	1845373841000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
260	\\x7742db27f9d8580efe7fa1d1453e738b9df3e2b9f86ee2a24be3b553f7806f50f8004fb013b67f00771c6e9eb9a0bff8bcbad8543cb821ad3e13fd573cb041e1	1	0	\\x000000010000000000800003d90a21813de88ac46b85a4f4422f62de35fac04dbeb1d0721c6bd8073987e41b196bd1a9b37acdc9fffcd9322dbb1286002ee8afa8de5f5ad115924d6874e1a1285eb75be7a06edb40de8f188d43f76fe6ca84e131e1ab8c94e1722244ee7fa60c3d9f42465e659c646f566502e458f0d76df881b0403230c34ec937faf58767010001	\\xd0caed54e8b09b48f3fc4b3365dcb0564d6c3f7d08428230c539895afc1e6087aaa2ee7164d136dd8ecd0f70d02a30479bd4121557d8e20c8e117862dd9c5209	1675603541000000	1676208341000000	1739280341000000	1833888341000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
261	\\x7916338643b9fb886871b064f2d42cd2900956a06e05ddf15a89fd153b039325e4981d7fe2415c303f5d1ca6cb613e10bf2369b65f127b8270b8f0476edcc86a	1	0	\\x000000010000000000800003d3366b36804ae53d069b166b4a89d25e367d05ca1c37a60af0d327a07167e6127891c8629a715324f69f7cb6844f97bcd12fb17df4b3c843146411c3a74b337cd851818f70efa0a06c5fdbe68a8dedd61de75026f20f1db1bdf6efbe334b59737fdae81d6273b04dd507222e561112a7b78603f5871b03c6e3ad6c194dc97fc3010001	\\x4752c5de9cac46df14d7d9ec346cea60ff68e2b5e916bf6cb2ad44c252f470072a86a8dd0ad7083ec6fb382c1c3caf6e8a25170b4ca747e1d23447c30c099d0f	1675603541000000	1676208341000000	1739280341000000	1833888341000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
262	\\x7c5697bf21ef0c0a088b48c0b1699464b821530e24d323bb0b21dd6d8b70c1ad4b8e6335ce7c8419071befac0bcdaccc4d2e5bafd5bb486b8ee3cf60e0617a32	1	0	\\x000000010000000000800003a4eab00da32bf1b199d2931cff1d6e7f1636c1a9cde491e899fffd3765f1a0333df9cbe8c313db6588e784f8dcb12b67114c751ea0a10ebd8a3b64a272b041a66f925f0e093fff35918fde2653181b4f1f1b769520620af701b77a121ffeb5379f5fe7428787ec151f122b803efde0d2b42e4e56f32c8eda16e8ac4729b5445b010001	\\x7c4b83f5226426003a63832d20c1b93d4a3ee0bc1a4d0ad21cd7e7c63aa38e7ff58d4bc984097565343d80497f10df3ab0b68949339c725aa9b0932bd73fc60a	1667745041000000	1668349841000000	1731421841000000	1826029841000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
263	\\x7e6ad02491b714e48260fed6976e4a00fbd811a07596f32313187d8bb97ccdf81f657c6b9bc080f959ce3886384ace78e43a5e77753e977e2c90611185011a39	1	0	\\x000000010000000000800003bd9934763c17cd7e3a4f12c32210d701c6251b997705eb0597ea58de7d9e02d42de605fdc28866df64af089e2f4cf25b886f4e22127075f3fa9388c27689dbfbb07a8466a8411531a5e47877f43d49b01468c6b29d2392185da74b0d0292937f7d974638841eb2e84a5900f192b0be554fc29cb6d3f2bcdb46294610579d2361010001	\\x405eca5e521b36039572935b29b6e7a14adf5056229e83293cb005a07efb5e4ee9b7b5530eda6d624d9b5de78c4e8420f95cb9002049598434d4661b272b3e05	1690716041000000	1691320841000000	1754392841000000	1849000841000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
264	\\x812e86309bb277b195d6bee27517b1bf6c8677c4515dcd41cbb3749af116388af59def184b988303cf24d5abe5bf5c77d39c79c6cf31ee8fb23bd45b208a216b	1	0	\\x000000010000000000800003bc7ed895791f6b98e349a5ed062d51a1bb16a2df9b5c138cd8581a5768f55dd0805b11036f362de9939b8f5366cbee02a623ef5086f1255769602bd2735efeb8de1b27bde2744c7821e43d4a04160b2eb234be04e2c4e31c280f859f58134e9ed4033b48089133021873b1aa07261300dc1a70c66ca60b69f8c0935a6bc71b85010001	\\x45b6dc7133bbd6e81ffaffc808fbda62b324c49e0ea45f5ac538027d9d70df0c6fd39925ecaa84a045188ce831fc1a11f078d53b82cc12b83e7b0df9ef59e60a	1681648541000000	1682253341000000	1745325341000000	1839933341000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
265	\\x85b23e6120cf4a34e12e23b798f936c408d27f126ab88820b7e8d01a1d13a1314ab122f6ad206e288358b2e01cb2d01937c36bc1cd2e855e9230ef5b7f9dede5	1	0	\\x000000010000000000800003ea09850db2648324c8a4af25885b3189f8db74ec5ae011f0785c6d917be33b2d18dba9f67570f9c8fa3aaa8d23c6fdb9f0c6e14bc07a48531dd7cf7ab191875c5ea2b7bc0d11e7ffefe1eaa9b9ac6ce0f19fd91e7b326e5423710f58993093f31cdd2a54d62da120ae211e5aa5dfe45eaf404c38892966d36fdc3bab2f8d75dd010001	\\x55f576a14f9554c15b94450c52174865c0ba345537ab58a4f33cf25b4fb9d887fb77ca4fe7aebd7a74de8c581f85f472dc697c0d180da7a543e48ec0c8c7a30b	1667745041000000	1668349841000000	1731421841000000	1826029841000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
266	\\x87b60e836d0622ee5d59ffa4d6b1c66e1cb75f6c4e6bef5244101dde7be3fb2541d4260181b63b45915c56265dbb6a2253ab41cf22e5ad4d8ae25310c1739754	1	0	\\x000000010000000000800003ef1281745868ca7a764a4aac48faa7e423a88ce6a29a31377240a263bbf4892946a7c591c0c7eabaa7de7717882832cf41ed10af1ea216bdfbc7d2758cec65fe7cae0d07ef962a46ad61b1ae8a86cf682550a7f11880914da6b95164642c664d2460844184dae7bad142df08e0c87efd66d1333829043108ccd15db56f888d11010001	\\x06773114458285dded08f026d5f1914ce93726a3dd5c4ac65c7279d392c8b0eb7275b7f8c788072e803b8a5c0a6bb4584450e3bd4ba42bf8a0ff19283431f104	1664722541000000	1665327341000000	1728399341000000	1823007341000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
267	\\x897e8c33f710c1e31e99cf2a963dd9b19c8cb68d6e52c1fff546697c975c2263dae7d9f13936f672876209f6adda923bddf0e8678a41dae74054a40481de0805	1	0	\\x000000010000000000800003a7855dfeb0c54ab7581dd0b9b45804501f086668cd5944cd6060799fc377b94845d21ade71db88c8899467f6c8b6457dda8f5f52ac7717b176121bd1968bc53d8062e8922d70d6c145900ca5c9338cddb657934d399fbdd5e5a9dcb019112598ea53a5328472db63f02efb839022147939da313d0f43a50c7f39e59770a0c6db010001	\\x7e31d78a49d34552fc91b7ee0740d0718b64cf342c367609894d927e787bc374df6d2e4a3714722a584ee251c3b9c3d4f19765ae7d58800a0f676b3bf9b45b09	1668954041000000	1669558841000000	1732630841000000	1827238841000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
268	\\x89baa6c3011823e4177426213a656003996e713d451fd8bedcfc17799bb2500c243b7aa4ef960fadbde400b3fa44da74ba871dcae3cf9bee15bbf39d786d099c	1	0	\\x000000010000000000800003b33eec0f5e45f03f508bbcfbdb31b72ce390ce389e475fbc89f9e65b76c774a10da07b23d163a253dc54faaaaf530441d4e3e49aeabd9c2fb8e297354adbd803a53bcb69ddc63bb202ed7cea9ea6e1a5aca6c17ee451c1fb7dd75f1ba265cd76158f1aa13d46d0861c53bd2ab5d65655965fb3d86cf618ac133c6e599d4fd3a5010001	\\xc824b3756b9e4b2d9f2dcb4773e3b67e8f4c2a0220dda75e522f7abc6b2d0d036a80f0f420aa89ea407b83c65480c44bea989a874ea082ad2330d3bd7280970c	1683462041000000	1684066841000000	1747138841000000	1841746841000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
269	\\x899acbb498df2bcaf9a92c569350b36162aa9bf5c2577091baf9abc51747bfecc47662038328c3889453a69fb74488c4f8aeee74b3ca842bec8b8a912775baef	1	0	\\x000000010000000000800003c0f6575f819cb2765fdb251272dde14ca2aa36dec3162b0a71b6f1b49599a3c6aa801c646a38567136c75e26cb1741dee50cb4bab0b5d1f79edd1e5d230c43756ed284198a0b169b8393de0eb95e7775844a4268c222899cb86a7327cc557127a92ec1bda8199179eb4046e6793fab039baa80cdac834be9b729e71c08966807010001	\\xbf4358a0097bcabb653d89ff444a0b561350ce9906e988d1f61dd84a614f13bed137b0226e626286a6c005b65b72f146247037a2e41c4d4974ff7698e8a97600	1676812541000000	1677417341000000	1740489341000000	1835097341000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
270	\\x8c020b9fbc212ffa68b0a8523da90290dc310c723a7dd420c7cb7a1c4f025ed89919fa80cfc95d70f4cb2d98fe51bb2661fd52fb6e07f7fb85b0f8d17f5aa8f5	1	0	\\x000000010000000000800003d2443f601cf828f73073e70e08f48f3d2004b52b04068d7f1fb5642edf487972517129dba0ca538a841abaf1f12059012f5c2e0d0a5604e0f1fa0700545dde5321703eb1bbc1ad928bcc366a77b9700388eff1a718fcdbbc3021e51cac004c0c76f18a67edb03baeb3ac69207ff5d1ae49fc6606b9adbdfa46eb800566b4c0f5010001	\\x49701fde2cde15dd0641283c34f612c8b7645b67672bec5dc598c5700d272a60d22d7215fcdb002754a5e2997fc6a3b79c1fe44934a9c87b414e6d27facef307	1660491041000000	1661095841000000	1724167841000000	1818775841000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
271	\\x8c0652774341dc4171ead1edbc038432626d207b4836f8f3f3f32065acb0c23cce18f8e3c5062dc1cea591c96275bbf492a58f5f8ca48138f1a73b531be9711d	1	0	\\x000000010000000000800003ca39531bf9899f8dafdab9b4ae03da6b972c068f0e2b4f7fac9a139abf4fef336603d108eefbe795a4310ce4db54986b62ff140cdb83c50ee2dbe74b3e78b9823312b8dafa485d89393e00e95b5dfe6683a847631780fce8a5f9fbaa32c611656c5ed7d51a20f0a43698b0351e66c399bcc1bcefd3f58bc29040637a292e4ba5010001	\\xf0df90e56bd6194c1538beb6a00194ae999e46ffc5813a8cbae113b39f56fda3949ab3a255955bdd26d4a90f78370abd459085b850e8a945212c1d35a7f2aa02	1691320541000000	1691925341000000	1754997341000000	1849605341000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
272	\\x92fe63f2ce70a9eeb1081c35ea51dfbfc7e3465a6743c2f49520ce37b42b864abfa53c10017c72b8ca5a1fcbc5f9436bb1932af23f9edc79f7ac06475a0c9ebb	1	0	\\x000000010000000000800003b4cbe7b1c78bd44fedf2deb49a1ba49f432737372e8a170788293da772b32bc843a242eaa6d266a540e11413be64015ee90cf0c174fe10a6e6e61e42971e2ef9688d3861168026e7354feec870708969228e0fb2c2e103a3520616ada19f5ebf2db32fc2dc5bd688a9d4690490417079de5ac34d25dffacc4635ca9fd9a1de59010001	\\x0c3bfcaaa555ca5fc267c0d46e86d54576b4850270fce789184bd32f82476a029e786cd0c5f3ac95cdd1787ca5883ab8f5166e2f2dfd2ba7519a41751a4afb07	1663513541000000	1664118341000000	1727190341000000	1821798341000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
273	\\x9a066ac2dcab056f2de5fba1c6a9e4764bc5ecd36fb949004480c15659e3f305e372b97a4a71e66ebdb57b07a47e91d004509b92eee4e68aebbbc0939f98f80d	1	0	\\x000000010000000000800003eaa7ebf8060e8184dd3e8eddbb30429c17645d91f2fdc8b62df48624d8ac651f29568795ae562ac3c800a1648907d8de9a68142aa9a0b8f5fc8de5a57a57f7c28acc6043e0fe93302f9d529427f9780564992c7bcfe373bcdf31ccbb7910b9f7007be977ef8e5a63a468144bf532e4009192f065438d9b01b3dfdd5528a4228b010001	\\xa8debc6dbfbc0f2b3755443eb4dbe0f08284496db458c0ced83c953fd23432ae208d73ac2d344eb31fed3859346ef0d8b73af9563a3a74f59af268aa0053b902	1674999041000000	1675603841000000	1738675841000000	1833283841000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
274	\\x9f2e2a8670d5a1c7043f9d6b704d8fa2d8702353623a47e77ac507aee970a3bfb2328e3b3f6294c15825603e50fffa50c86557fa1c7e6c4dafa1d750256eade6	1	0	\\x000000010000000000800003caa2c1278fc7adb0e3a4d76c3d6f279b1fae705502b10f02f241f0df1bf9260996aed4ccd28975f43db418d7d2d82122006a16194a5afc957e3e084bf19546807ccb8464483bb0660de5776def878cf068f7415086bdfc24d6365059363bf774a4d9a1bbe85fe51b5047d7121b8140684190a1e1910c838b0ced7eb1bdebb3d5010001	\\x2df57409bd37a4742f06c92b3eb15cda87beb8a40ea74e8a257b0dd8c52d6094a7d8ab453cd47822b5b1a9777a4f02ca28f28a907b0d9b4cee3c06bdbe8b3401	1672581041000000	1673185841000000	1736257841000000	1830865841000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
275	\\xa1aeab41ca8631be487267ac207669af8b22a6c8a196f3a0007543a5cc94568f9be4986ca5e5076fa01ef540388358185e7abd00bba76b641f58b38f8360da28	1	0	\\x000000010000000000800003dbd9d295dbac01a8643a8ab1e572d847f0d839a70bc5cd373c192ad9d47f5aeed6450a252d3cbd8c39f8bc99dfc9baffd054e05b0b0e518b5b1dafd61107338f9971b834867b950a58f28f312a8076f564b78e9e17ddb8edc447103abcfc82071d621882ee96a3816ec473e6f0a47bc85669ce1427f923f1783e85b9b5ccea8f010001	\\x27ee6a2237a7b03cd703d0fd028d0def39e80617510d31e216ad41c2b14b409fffce9508f04c4a816b98ef7ba3b31f9b930e7708f28e4fecd1d3f27880d8c10b	1691320541000000	1691925341000000	1754997341000000	1849605341000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
276	\\xa356c4543d442073eda49171553e21c01a31ebef440befbd6e6cc303f9c6b523c4d25adf03f05e0acc2575a2bdabe1f80344475a56508a35e0c9b71d9a45b049	1	0	\\x000000010000000000800003b3b03f2c0fd0f58850fb68b7d3e9cd9b0e50b652bf304778c29a986ab96a2e542ee78217055c0f471994f069374a4c52a55065008522cd36aa52b7b87ba1e9005963f6b8e3d68ac567917fe5cc01941b7f4844033afbcfcbbe8b25bd1ffa6f554f9298c9c1362dcab21c234d0969da0ceb315ebc32cf602bdeebe60244fa80ff010001	\\x579f094fb27e01160e1b0f5a3905511009f440a1f350ee826fea12f9dd294cb497a148df2d70a29129f7812d4170442e139143971e0f697fffb89bacca4a0400	1673790041000000	1674394841000000	1737466841000000	1832074841000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
277	\\xa4f6ebbd1b8f0b395fe4f0b65b80a5f6503363554c03f13783cf5ead17b2b12f78bf8943dab6d84606b5900691e3d5a7c6a8b549d789130678a3cdabeb64e4d6	1	0	\\x000000010000000000800003ba407588383a927f23952980a8036554f85c851f972995d62ecdca75484b9ff6bdd3b5a50583963acf20957b581241c24a490e5815072d08075c0893990bf015f2b7903e3fc849b4f997479505097e79710e7620e0fa42edbc4e4a5b27736d7dd865cd970176129105041327181552f851a05e571e4a569b99f83c1e1f454099010001	\\x4c7a2cb66137e002e525c66021d08d3b597bef256773f48e20224d0c6d883e7cea75ff5c71b85c3b248015ae091f35b5124a436977020388f90dad1fe5f07202	1665931541000000	1666536341000000	1729608341000000	1824216341000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
278	\\xa5f28583fc8da90c0409dcc651aee05959e5eb432c6e9482de47f464403dcf45a175c60d2520ed8c95db34866d6fc20ebb78a10893e7cdf334a394601838c71a	1	0	\\x000000010000000000800003a9bf2df0edb037eae9b9f4d7a091763b568f0342ff421f6adf3d319cec91294acd2a6946fb5a9600275780a115f852a878f9753b84e2edcfccc5ca105392cd2f35fa12f6aea6a19dc705164ac72b0b7464690f60b3c5ee6a0d772690500eb275bb997e03f58cd8741bfeecbaf58d41f87eb97821bc17fd8c029e5d9ece64cb31010001	\\xd908d653aaa5dbb4b6f3a9e3287674e19601b4390927708d46a17fd12f545ac63f7d6585b62b94471b59f0bddc45219e27c1d34cad1919824c0a1b2a2a4b2d04	1661095541000000	1661700341000000	1724772341000000	1819380341000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
279	\\xa9b2177d136837fbcc76502d641d19ea8af0352e8debc67519abd6631c3f13907c2cc6076d0ce7897344f7e22c692762879e7c44444ad270164af0ea66ae4569	1	0	\\x000000010000000000800003e398dfc6ab06a8ea658c44b1b1f7732cf3405a40959b04e590d87aa1719aeac39de2a10fc4d70b90736f33e1b54e3396210588caf6c84e787d2d61da6e411e68b59834b96d9dcb301521d114d186ced763f61a225e8abafbc000017e22d445bf0799b98c2c8781b93dca4fef291bdb8d68b5f2d9a314459009351ebb55daba8b010001	\\x4649adb09f23fc46bfcd84e46562c0a795f17f4b0dbcb6aea371aca7cee9b782ffcbdece2f5cff081121e78aa0574a95c2d956fe46aeb129ef8a707734f6de09	1690716041000000	1691320841000000	1754392841000000	1849000841000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
280	\\xab66a559e2ded090f35034c3dcc66f2059cc1767485785768670bf7effcc21760b50969cb7caaf5b452b2c4d657315a9c21d6f2d96f55b443203025e8d82d206	1	0	\\x000000010000000000800003e51977dde4a7968236b170b83e2e70b9a071d536ebe3e5838a4cf388491e4e337424ce0fea74c03ea0d09bd6c33c3f1ef92be7f0dbfb527fea898e4b78e17300b6a99d6cf25678cbe483c7861ae9fa8118968d4626e149ba245068c9edb0e1f3707d56fef4c946d7d5ac84ad8dde1464d39b0cfd6c06a0edf7f6e018bff8d37f010001	\\x46d4ce3d78b5d3fed1772d839b42fbf8a1efc141e953342139b4c4d20849db357e25d27a74b52ac715bbb55d567c38f96f9e25ca7f2e5020f9a93549b511a80b	1664722541000000	1665327341000000	1728399341000000	1823007341000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
281	\\xacfa30c0ead243cb742d80a5227adf30dcf07d0a4f7f652d8aa1ec77b9aa5ff00cfdf27cc0ddaa79b17e51eec57c7a8b4f88112ce604a1f678f95df9e093721d	1	0	\\x000000010000000000800003b85b680d148112bc74606054ff9cdc04af46975bd19424b7a2f0538d3395baa534a8b34008788ff6920b20b6609d1ac35325bc73783610f3445f80dad594194c5f31a7187615cfe70b060cf82d7ce9f0092f51a05480b06de6d71f6ee866bb30efb76bb19569fbaac066913e02bcecaa60a183d7b428f8963a33b586e2a021c9010001	\\x47807a7031b50296f13144fe02f354385f2ce433a806b46457f6c57727b2e04cbfd560d5a30173dd2ac2bf344ebb09e51388705a0f2c4db82a85bfef768ee00e	1662909041000000	1663513841000000	1726585841000000	1821193841000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
282	\\xaf8aaf0a1e8fa6893e325b4546559c261f0b3bcfea2f9973671411bdd884fac848da6453310d016afba30f8f3f3fa8967aa8db29a5b8a42d1199266cbae6a3ce	1	0	\\x000000010000000000800003adb5e26e2e15efa65c31c31553f8d1e5e06fed15be4c78af2af0d7cb793e2dc2f508f61d462da0d4748314f04b69dcd84e959e20f83999722c2a45a451976946363748d93619875063e6c4a6b38710fe186575b9061155adf0d784865aba9f2e178ca17aeafc4731e1143c25baa7a91d9fb53e82bc97b65515689bc08d622421010001	\\x7bed052c9ac008764c349560d4e9917d883339f5ad3810ed0993f3b97b0807e99b1c124e654c454acae19da75785fcb4420c76014527454f5a5db2c4f7fb8f0c	1679230541000000	1679835341000000	1742907341000000	1837515341000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
283	\\xb1520815438e05bcbea3db18522e8ed7f77736fcda18e12b7acf71f6bb7d19c941361d1a0b87bdfec3689d4a575446e84de7183d74c2a518fa068bfecfc21466	1	0	\\x000000010000000000800003c6631dc4e67dcbd00347426ca1241e8d4693e2cc76c41f898733cb2e35954737aa6d2f9d803f3cabff7534787de99bc5376fcb46e82d0c33b4b14679b8161781f50b87d33af94ff4c62453f4ea586cdef559e46324c468bd4a955ead859bb4917b97c71bee08f660ac5cd565413a6ae0d395a674016315352230ff3223c2a057010001	\\xe9d85a28e3c4610dff35bac72d2bced840fa1c6d9bc9047021302599a4bf12704d0276f15c661c4940a24f77a3f0126ee764898dc99f5ed77a9bf0c50bdbcc05	1689507041000000	1690111841000000	1753183841000000	1847791841000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
284	\\xb3f2ef8c93a4ddbd1b3aa51f9d88ca443d9b18f76179404c1556ccfc30712001cb0172544879d52acd9ddb08a28a4d041d7159dfac00eb94aa215f60a81ebae7	1	0	\\x000000010000000000800003cf85022f93d6f8abbbfafaf24b5cc409fe24fb08a03e606e7ae266f2c44a807497deeb6cbad8b1296ccd0e35f486a8ae5983cf345eee439150af87f752d342d0b353c7c62f87363a91facfcc6a7aed4394fd1c9370e2f536c97c8b5c9344aad6885096ac08bd36bfff95d8033d272fb0150553e84536fe93a45ae0e9e33304ef010001	\\x73094f7d9ce2511d2d473fd4d52d0594e9776eebca2ca728f4c6a7e71c973de2dbfbdfc4ffc286d4352caa6e4ad76101ca4c9ff17be8347e757410221cdeb409	1673185541000000	1673790341000000	1736862341000000	1831470341000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
285	\\xb322a2763ab616f19c87f0d812da1d0c86f70cb3c98dcfa967af37b88756bbcf3e081039cbe41c6de6b9cc0f36ddc11247a810075e738f1ca243bc21fe1751d2	1	0	\\x000000010000000000800003a9606dd22aa716fbbf3f03181f8654462375ca801e42caf70974897da08caa37bbe5157c98b9d4928119e1dcd0a5485faf22e499001a42360ad49666d83eff2ed2d302611f657876b1a1f6f36d8b97e5c235cc58fba31e31f0d8cf1ecfb9317d86d95c5cefaf86e6f67bef027e5240fb4cc24ab2c13bac59bea1a4cc204227db010001	\\xf94a306cf0798a9e05b3372922ec734e20065a101db6c336f787546f6b75fbf04024f18ec5202f8669babc73c4a38e45e56a1b568c3bd3aeac8fa25801853e0d	1669558541000000	1670163341000000	1733235341000000	1827843341000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
286	\\xb4623c16c03e5687235018287033d731a87bcaf9109226d49cad3de99e23227f62639bcbdf8888fac33e6942f3794e46949f677cda8c1350cbc7d5fc559ac1ed	1	0	\\x000000010000000000800003b478dac2ddcfe967bfd759c69cf6bfed91c4aaa68b69c34400716f783b31b69bed41b3797bf36a6ec5c5f6ad22f3b3f2ac50161429ed246e21fcb29547e3705355c5b87002c8e05a4976bde355849cf4ef67a095cb6311035318dabcef41c71f2b57ed6b6e6f25ddfa6d10c80e87679039c90d9c8f04b853500275adb1b637e5010001	\\x078693914701c74d98bf3d570b5ec25edc0d9b8472cd88bbd00b3c46cd23809a5cc24f17fd8a5121fbe4618fbdb22177019662387cba1a9e74638870f0536007	1687089041000000	1687693841000000	1750765841000000	1845373841000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
287	\\xb50e594f3825dcc865737975a917664abdabfcadc4f6b19892ae2c2aa95d3365f05b8334f6a81c8d94bc55b04cfaa358756bfe292bff9f4fa4aa91725711dfbf	1	0	\\x000000010000000000800003a2829afb5b2e3dd64a404fba21de5bb6ad96322ddaa9cce992ef977dc641b5509e050e5bf169ee98f0ccf111c543f03b2474d914941f47817dfc66276db5d57036d0243ae7e424394fe3df00f9189c1a098716e491fb16f0e60969ba3c0e0f1c265d41924ff468af34f8dc4d600d5a90767c4654e81e2f8b26d6f93b8b2453d7010001	\\xeb2af5d412248f8a12a81fd8973efe1a87a6ccfc35d5c5561b8829119ac05e2f9628f020a59b89b21f600272918228801a3457e5f9b25405be501d0777c0d205	1665931541000000	1666536341000000	1729608341000000	1824216341000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
288	\\xb6c2bf20c16342ad1bc252aed5d574d7c405236ebfecdec97e03291045feb97afbde5603d54e44e5f499d02d92ef89f0333ce40785486c62cee5a2fb6aea5bde	1	0	\\x000000010000000000800003ae303940b244f0cc669b11d10dfa92b70ec53fdcfa9ca4c9533d1dc6de9175f3b2750b026494f4c69514a46b9a52897d652e1196eb4a6461a82559a212dd9e57fcc017098d362af56fad239d8699dce743b8efb80dbc38e3166924f52b6647a0fe0f254fd939c2092ef6fef7b04d3e370b45757de2313bd87e5f0cca74bf9aeb010001	\\xf95887d067a94fed02c8929fc55bdd8e5a63255fe12c2c433a5305ff3638459c211867e20dbc707fd3879a9078953d11ef62fb6a4784c770da412516317cef0d	1676812541000000	1677417341000000	1740489341000000	1835097341000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
289	\\xb8824d2b019b0f20008c32fad52b26e64857cf2631b6ec8b08ee4f7c96b2224365f11b4fbc14a27bfddfa1f9920a629e0989b2edd25004ff506f5ba2d90c87f7	1	0	\\x000000010000000000800003c5db9a6fcbf6491462a1637be4dc6e5458e23e772aaee3d743d07fbab6ad7a54999c0a46a673ecd1edafbf40146529aa40ef121a2076622148863afd0f5eff31f40d300ed36a88af046a282c05e345b08bc34d25ea018b99f7550b4f848df41d854c501b4bd2a87a5748b8d471c661dc14bba5be2e80c1397bf1fc541828f1e1010001	\\x57ad02f0fde3f4dd2ab70d8e58dc9e938ca3743351d5e3a6dcc6b9b8117d0d05b7fd9eb880d7537f759fd2c8c0f4506aceee183a880383d3a2fce91f3018b20f	1682253041000000	1682857841000000	1745929841000000	1840537841000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
290	\\xb952ffc2b10c9be35c447a6456343a3768a916dc99315d6bfcbed90fd9495f9956ef18f044e6c15b49a7c59d48c3dbfb6415b43c8721439ee213f3e886f3f836	1	0	\\x000000010000000000800003f0e0b59d5951aa9e4cef74d91b53f37d608db088799efb976772d15849b93221bf04eb6ad2184f5c14cc9da9f85fc7d02db10daccf226f79f0a1a8dad19d62caa3cea4469f524bc2dc7ec28ac8cfb015ffd9683f19547267d200bf6ef9d42625de89935fda091d41a9b1692304ce65af2a7c7554f85ac1510b86d644520ca18b010001	\\xdbd0e2b50405bca688faa5b0b8d556caf5323b14dcc7e2a8cfaf66fd558a3c9d55435d394064acb63b9bcd45f3ce91396025591df629982c3779e088b7f73402	1682253041000000	1682857841000000	1745929841000000	1840537841000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
291	\\xbc8e4b6dbcf9cbe906b2a28c39c803204436a081e3202463f6113abe1f7c36225553a258885c1186a0e812a86ef404c73beb8eebf9cdffa08bedf11840308179	1	0	\\x000000010000000000800003d09440c2a21a9382a243f6103147a172d0a2aa3f321564e39787f17737546bf32d4834f665248b56d00eb86276dd0f44a9cf95eb79845a9948dd318a2d0b6576b6498ff8fca82b6724e9ec8f32592765819294448a78fcc44e789494f65ccb952eda51a2f77ecf6d0c70a685e8f4c65fa6993c74660161f5404077f587c01b37010001	\\x15dc9d2b87f1cdb3cffb8932ba6d437ab14c114f45bfeaa08adfd08ef7dc52b8445240d2cde4c5ad220204f5d49deb4d59b06e37f9b069dfe8e86fcd28754604	1688902541000000	1689507341000000	1752579341000000	1847187341000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
292	\\xbde660503e631f3b3f31cf1610f739b249b6d894174d4fd674227e632b302f1482eada6521d1b3feef72917fb252850451ac0813e38318e01392189155e753a6	1	0	\\x000000010000000000800003c8b4b4a8061377b0028faa010fcf4d3f4c283753bc624acdd242ce1621eef3c1c9d17c74afb7a43e9ddf82280d2e55e0741c53099968a9b0062e059d35b73020993059871ee7ec67c7205f1b7ae497b51c03dbc974d9ab34aefe7dfbbf0a1af9e09158107e81600f5431c4a5f9df4b5b02b12fd4664a7173e4537ec7705678b3010001	\\x1c55820279f6a15abcb00d745b24927f993c953c06b97d854564d7b72cccb08906ce67d6d9e41ae830e78c45c050b9c21949e22dc58da23d6e48d9b35b6e3d0e	1677417041000000	1678021841000000	1741093841000000	1835701841000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
293	\\xc16e540a7ba6d2b73632821fa57ecac5aecfb1c932779fc45103780790e5c75a4baaf479f9021b5c68a3a6813c0b84190e80fd4747a0c858a76c7216f5aed8fb	1	0	\\x000000010000000000800003979b1da62e378ac9f0fcf17e84174bb63a9d2f6d79e80f0f001bbd3f6c5003bf9cb3e57513e7aeb0e7d9efa791cbedebdc4a7938cf23e4c380bdc397a7f5aca90224ffe95a491c447dc48d08dfb2597df73c52b27522fd19b4bbc56f7e817686ade0bbdfaf3c58d46142595ff740a2d7c9fae42474faa6024849aab61a462de1010001	\\x7ae53566cf86e8b341b4079ed25cd526f852e1c18407366871608cec943937cae26d1ce261648f2a2f3ab37c438b8d6c0eb692b7d731dcabd5746827d2310705	1671372041000000	1671976841000000	1735048841000000	1829656841000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
294	\\xc4f2098172c5affcfcf3257f139052774a89f8d6655b834e52765732e01fa1d61f89ad4a7d7ae302531e4c4b00b711b3b0144bb589558767a69aafa3bef1de9e	1	0	\\x000000010000000000800003ed04fbc81973c28535045307dac0986ecf814140fd00dbde8ebfd0e20690f3a093842b948629f423a4c2d5dda4321dad201b9058e29fc13bb777985ba1b11c7e58a9016ed50f78fa44556214fe64b424c175d92e414310e95be04e83c8d5578aec5f75106914c25232dc63d2ef1e5e16858d6b8cf65775199cda95ea9f1a15c5010001	\\xcc0980b5ac2636fe9dfe713eb7bfb96bc473bb6a00c9cff40faecec4aca4334f1998edc1da6d49bfd5c130eb41cd038af7de726dae112592abdaadd7ad38aa08	1677417041000000	1678021841000000	1741093841000000	1835701841000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
295	\\xc5ae0dbe441fb2a15d4e05582563d9b6336572f2f0f670792a50d256e58f697b01f7404d628f1d402c612219f2adc59d56d6373528eabb0108cd3cce62fbc3c6	1	0	\\x000000010000000000800003aba131ffad938502a54e385b30a801ed01317c9d28c42cde5945a7268f3edfc3dcbf2e76853b8af7bf276e9e7d338eb0cbeac4b9ba6d3f9c720523785979ccb6c33854ef2e2672d4509249320850b44485b6ea9c11932b6a815ce5012fa76d2b5d21bc2bf4a7ef6fc3a2a0b4d52d2d69054ea397b7b0f5a8d958c90d23d16dc7010001	\\x9a6da82b2cf17c19d6075ff3537ee036ac2ac4e61b2f42ce208a783a9add29c2c72e32c06c5912bb0125c93497b6a85e9f3e2285f7d52294cfabbed42c63c702	1688902541000000	1689507341000000	1752579341000000	1847187341000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
296	\\xc92229cf798fb051f2247519bf3d9acf4977c5eb54a76343ae26f07016720251747eae9511f0c08b2ab92bf4889865334b13d699544950b633af257351207699	1	0	\\x000000010000000000800003da18fd650882a55f6aaa31183bfb80c0999ee27a87339480da295212f379a8528846e634d0b5e9c08405e5a59ccb282df896365924be20958eccec7b3e8417ba86200d4b9eccb86c4a58490b8eaf890ba0217e13964c5038665b529137bcd71f57d579e30cf6b446fc279ab2aefffbf881a96e134a0bd0bafca726138b606b4d010001	\\x385e6512a1a0000a5b2d9bca8eac3e537c7ab9249db486d0dbc7153c3624bb4f49fbe48c8d503de7b4a8c69f2442c8e8d2dcb4959d1994d59161362e7f5b230c	1679230541000000	1679835341000000	1742907341000000	1837515341000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
297	\\xc9066cf258e81a01b62b559a1a580747845b9c9abd0a672f6d9bc1d013029623949db1369c571154fe2dd9a14b4510bb840d761aad12210dc24eccaa1f40a2e8	1	0	\\x000000010000000000800003b0cea8c71774563937d23e40ee6597f7ba364e86d2ebe14ed0caa9dba77f53ab80f73c578319e71f2df1079f28703f5f7bc193d9e4fb078b310e7f2dce72420ea0949f5047a42e9a42195c9d2ef81660255595ef60eea8928119858c3941aed5527d952d64ea7b06ab1acfb830011676a4f3df68964cef727069afa909365261010001	\\xceeb58254ed46c65bf8313e029ab17d2dc3f7ea345193e262dd8aa1028c6af9356def68c4167a9760fab27e92ee5e7b025fd5bcb5c2568cd947ed7166b262b07	1665327041000000	1665931841000000	1729003841000000	1823611841000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
298	\\xc91a56fee25c007d9fca6de2eaee84b5bb7bd0544b90313c51f91516c1cf21ded51422964844dab1e21cac3e0355d9a1a3ee825e021c242bc917d474627f4813	1	0	\\x000000010000000000800003a4b30050181cbbc51dbbe39c50a7dce0ad07361e9a60b12ce3a5cb9784fce663b55133ae975f2ab01c590a2d51be17ebc520becd71b985e242c55fe5e794c11212643f5f36b3f85e9a0c314ff6cc72be90ea3f8cc860703f3d27911211072fddc68cd211badede6fab329cb1285b4f99312bdec2e150ae8ec6f3e834860e8b5b010001	\\x9367bc8e64c7240c6b5c79e05f5aa48f767dcf1d4051ddb344776c8bb711958e8e8b71b1c01e341e3869958a120f07bd9b782144584ef1d57eaee75045301007	1688298041000000	1688902841000000	1751974841000000	1846582841000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
299	\\xc90ac0b0561e29a52b0a3431a2ef16a00596681b94ae77a1c40c9b7ca9552c34dfe5071fdf051445c1a94a0823136745e3a9fe4278691808eb6b9e2e9acc4279	1	0	\\x000000010000000000800003b4c49a6df15c09039ddec9426ea7b852919e492dd3e0c8747194127831d35ca208f165c83c913edec8a27dd65098e7c0dcaf79e4b93e5af1ffb7666d50c5e50891e4b1925deb1c11aad40622d8034ef71b47c8e1f845b258f9997f33ad8e4803c7a81b52304d50f85cf9f25f7849be0454741717b8285707bcdb2f7ebb400d0f010001	\\x4cc7edb467788bcbe3d4ef30d8ab28c001084fa357279f2ec02a3fc2a0f7b28a748fd4fe270ac4ba9c5952737cb90dadafafec440b436b8121b9982fe4fbe30f	1673790041000000	1674394841000000	1737466841000000	1832074841000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
300	\\xcb2a570a12ca1e085266100598ac93e857218065e1dc0f15ac8d688c63feed1d1c46d097bbfe3737c07bf2e7d24304692c896d219ee9b9670a468a075f47e334	1	0	\\x000000010000000000800003e455b1d2a34fbf0f7ce75229864a14b4e922fbb17522298752355166e0e0d959c69b5e8e40080f78ef30a5a0819015218b862c14e11e4bc3c306323851f08b5c004f6aea89dcfe5a86d3763bb172b5c88d391878d57a205c3dc29da532f02e033a8c96f2834cb6e025f78b1f23b8f37f9b236413fea22346a3410ae601b51f31010001	\\xf17c260537bdaf807ee6121d9d9e22adf508f192625a95297b7294106e79991b70b92faec0182b8bcb5f0a26789c0282f84c9d4b4c8d8712c2c1cd0735ef7e01	1661700041000000	1662304841000000	1725376841000000	1819984841000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
301	\\xe17e931106472d9bcf2a4867096e595c604e99a84fdeb31f42601eee1677006d99374443334be57a579d917baee98de39a449f3a32d0de8ca4f91b6d5cc91872	1	0	\\x000000010000000000800003c8e4a464198a7a3ba34d9402638939af62fe226e0513167ed1103e922c986d208984dbbc05ce50917b33bf00314275dc61fc5b6e8a93cf696838f3ead290cab3d6db3b895fde12ce7f94ec375f32d90e384ad793677ea8650444f6ecc21b820f2fdcaffbb49bb97974dbe27ec641282d42805dd3c9617adca7b067de817eb855010001	\\x0bf2073ed1042bbd6db03f0f73f69bbefe31e6330696e1298733059f5cfc049ca2e50debd88250735686f307182cb053763776a6b9c606a58774725fd46fa506	1670163041000000	1670767841000000	1733839841000000	1828447841000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
302	\\xe9e280bfd4ea4e87261101eb82432b338c5a9b0337f7e79ac161096e72c8c19f7afe614d51e05efe5d25f2e8b38e1fd32325f6a99bf27b884e0ca753f2b77f85	1	0	\\x000000010000000000800003ba1ea93591f3850e487612b907770149dba94fc5aadbdcadda58b89afddd32e6036ac2aa9a6e420d2fb081b27be5e5abedf78da6bddc5ab54ac071ff9a6a29e03325962a853d0b1ea540ce7485f84378eac26ec1e9d28e036815e3c91dacdcc058cde3cf04cc7676500bc295c9fd4dd0d09a188a5806071461e0f17693ac7975010001	\\xde7cfb18bdbbfb0604cee05463164c88032248ae2b2f58df1c8021d204b0be1283aaa8d1b1aa8e66b31c4366afdf99ce168a8f402fccf9676ce343378fb83c07	1668954041000000	1669558841000000	1732630841000000	1827238841000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
303	\\xedeaac71f2431820b13fd51ec9b067a6b62708df858324868eebf21c4653eacd7c60ac63aba206fdd316f2bc862a38c1fa5097b70d7acd68e529946fce6eede8	1	0	\\x000000010000000000800003b66b6670e92d4c44881eaccc8a6b76eea80a7737cf3075fa4057838b88aba4beae5a41bfca662eb606c0e976b23b39bd63c82835c851f138308378cd15e602b9be85380895151a912b44d302fb563d0a32d2a7aad144534cabc8ece607aa50151c1a61490b0af53a4a0f66dbe323bb8f3a604b238e7dcab06a389175a23e2491010001	\\xc7709f9141b938c2c83b05e798807f1dbcab5c7cf40d2ad288272230fed30b63da9a0506f3ec2d612c00aa5f8e09ca5a5174c8ba143be8935dc80d5090e18703	1665931541000000	1666536341000000	1729608341000000	1824216341000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
304	\\xefe6650ad663aa3e9a811eb6edfb09f2891933ec57d1d71dcfac0345bd738b5320daa208e5580ed5e44c82e574cfce7b4be3b22e8ad7bbc167639c9dd6e3a9fa	1	0	\\x000000010000000000800003e24722cb68ac39e4c659b77c4fff7483cc2a8e414fd4b69964fc7eef38a0b4e83794dbbc4d947dc5e8ca9903a1fab45a536c3f99043dac60561b5b6b2b5124863b64cab79b8975e0c7c33d5537e8b0f2be557748f80d52ddecbe4f14e76155175d647bf10064634cb64dd765f49b89c32993af16ec58f171d645f3891b74d715010001	\\x67c91517646b6ee8c2b3c54ad6ae0fb22bb063c41e636fe4edb18bf40c50728a01cd4e0a9076b7b668f4d0fc6b62450d046aca395684175602846996af8cc80d	1668349541000000	1668954341000000	1732026341000000	1826634341000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
305	\\xf06a75ad7a80dd8e7cb67b35b5ab26a3925f3a4d116c246679fe4fe9063802933d2a4c5144d6a9ba800f4428f7cb0ed666112e39f7f468d4191b46850ee32dc7	1	0	\\x000000010000000000800003bd2b2ad153cd18e6029229408d1920d728992168f6e2d896050c9a1af623ad29e6309665f28c4ea90568f092e6c300acf71818315ae8c85933fe7174832380f8c6b421e725bbb64c0b88e4cb32b950b7dac12902577267c49fcdc17635781dddc41ca88fab07f2d0909a8f765ee227cc99626810032593d4fa903277e8a0b103010001	\\x75ae763d0f38dd496ad40b1d9e168185e81c7df1e40f309f0daf035ad1907f118fbb843293df601ee8d2aee0e17d5a9fea480e9a6ed973b9957d91f1c567580a	1679230541000000	1679835341000000	1742907341000000	1837515341000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
306	\\xf13672516a2a9b856d1e8ade4c58398556fa58ea22d57b485d178a8e7922f37d375666a18f3b9f2b8601484a557429306e1e013a7694aa4d15b76697eec61106	1	0	\\x000000010000000000800003cd82e1827190ba050b6d7575192aedf6ae1c832129800d7cccb0c8b9cf3600d76ac0a2458650c7efe4fbcc278d35ea888949353c46212e49c6b8e474ed87e0c0e879d0569bcd3978616e65ab21714b4a4349fb27134a37f9bf63f078a13e1a058c8b9656afb9da6058cb1316e991ed8602176100ce5d6118817f2215c743526b010001	\\xd0dc38f007611296708f94bea643b2a7c6d9d33114a236883ed3b816a1c45cbf3ea02c95063b112cd400624c33a5c8420d8f2a18e92d7098370f49c4de3a4506	1668954041000000	1669558841000000	1732630841000000	1827238841000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
307	\\xf23e64f715d79422e42ae1055fdf6e48d08108979354f9ba819678a3c4cc24fad5d4896f3423520d9286ed6431418c28cc9eb751c27fa98d705dd3b2f8991f6c	1	0	\\x000000010000000000800003d24c8ef815e5fa1486c5fd46616444c642d57ad3b5ee9ad29df4e41a31ecaae09f65168279bd5afdb025de93cff41f086f7c24d5113d69c8ac37e98894d08bee908067505440024710def0412e22c4c1fb22084b38e921e3a7597bd645abf9db8643bd5b759346e342caaec282780a3a4556d4b8e8e1325a9b1a01540f914b07010001	\\xd2c75dd4e6954f522722f0c3113e293161a19f7b8f0bf9ffef067e989e1d283c7e339bf1c7d2aef6f38a3ac5f7ac67d053d5b8e4a6502b9dab3063aa762ee901	1691925041000000	1692529841000000	1755601841000000	1850209841000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
308	\\xf436d90679a5770610f976a9bb7f2756587ed69223147d94cc424d4e027474f5220cfb074545df15d1ce6ce17733463b2b3d68dc1113492d9563138bae30c31e	1	0	\\x000000010000000000800003acd0a90126fb74cdc1127570abac194285b9a4f7e56581e1d4eb58f17aa96640f158681940b7dce6f6d3b206f818df383288e644f1ed70569a3591e0a3b82b0e06668f212e0f81bd3ebde28af6f19051e02daa410d2a3cd2ff55d50d4539f9e504ca6d680012e785d5698b76d3c64e19d83ddbcf2016f8f159fe70232261d11b010001	\\x1414a0f746f4f1c0963ca26a36606ead5e0ec28f6c40b0ad9de66d25570a4bf038ff2a4e33ecfc6641e0ab568796935f7ad0361d984db415a2529df7885b6004	1664118041000000	1664722841000000	1727794841000000	1822402841000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
309	\\xfb7acba4541691b581dd48e68a9183258c4e0857a4bf1f5407b7677b5deab81b5ec81b75c1452524f96ab5f829e87a383a935b60ba9fca9fd789253c8e932888	1	0	\\x000000010000000000800003d20cc6d3713a0ce00c4be05958d10f85994eb4daadda65c8bdd9e63f32f0f71d6c670c595b1f02b23aa73f8cd5b5a2c73e785ccb0c8482f3abcb96405f7fa4a0a6575a5862f9fe8be0f676ef370418fb96472fcca0246b79e4f13230990f59ff09f73682c8181fb80e49dd4024045b88475896212c9d97442cb71d1700b7e31f010001	\\xbcf3aa69297a3fa31c0bb81219976867e6de7a393c1605944ec2a84ae4b83ed817d13e873478bdcc2fa8d914717c94bccfdcdb79cbd50bea347ebe05ef2d430d	1680439541000000	1681044341000000	1744116341000000	1838724341000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
310	\\xfeda66fbe98f3022b07aa55e0127b6d5eb9029a6fb5aca11f6a6238fc986442bb312263fc36d2c874da676e1e773d975a6388c59a4d05015bf950cc1401f5294	1	0	\\x000000010000000000800003ce134276f69dbb641ae732b8e02a1f1b6ccda0f56bb02c1951622785b2c878b602a451d21141404b0b01ab745e64ba0ffb001acc35b75e990b709f9dc44e01ecfdd59022cc4ed35c93176cf418e381daf5a67ad7f9715cff3907ff19753e94953069285b4af46f984dd3e4513e9c1c31c3f495486ee565b165496fbd0ead4e25010001	\\x6c72f52d210e1bf0a5534d6ee82112b1c044544fad811ac177f38cde5269fe6bc6dcdf74cb7cdb06f6a6f9ef8b23a0792c911a85888f3f3d692b5134c961c301	1667140541000000	1667745341000000	1730817341000000	1825425341000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
311	\\x01eba2aa9d774fe93a563c752651aa5ee063c1214c5d43f3d8ebdef3139198ea5d05b57b23264fdeca4a916e515e9abdce09ec6a4dfcefa48a875b752c639f1b	1	0	\\x000000010000000000800003eda3f3d76c3db7b8f7d54cddbf178676c874376f66094601a19cc502a57984bfe5d81ef32f59e530004b469b96afa8ec892c55b66e2dcf47d1eb98e5fa07b5c252c4c00e1f4f4faf82a2f538564763cc9fe3c9b8216c950a36d021b2de27ce8142c10620e1cf9679ccea01b863f3cefc3114d59c3dc8ecd44dadb55e3e490013010001	\\x9a03df69eab3d40135b49ae9b9cad2fe00d79be994b9aa3bd87cd2332a965e4c1a77da4b6d4342d0499bedbaf169ab6bbc7da19eeb81da95dca6c43a3b4c9f02	1682857541000000	1683462341000000	1746534341000000	1841142341000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
312	\\x0193de7c51d6c30fd91c12638a8be26682132fd074473455ebda3d01af55649d6ca45196285457f2e93f10cc5c88d1612e57c45d93e134c4e00d565836531667	1	0	\\x000000010000000000800003cbcbeb42f5075555a2fbe7161f2cae1dea286a26210548b3e9256fb9285f0327de7f5b3ebc88c9ad6b638b5cd2dd92957badd5b4e53beaef67cbcda74269d18b5dfebd5f4b55bf2ce96958344301fea403f151191a3248b0c1303270395a6d1b5bc9018ce6331b646395593afe72c39f0c511ccfbaa969ef90ef932177b67f49010001	\\x560c360693ed2f239d6b2429cad9a35a4babcbc8d7407589ca2da10f506b6f01d47c39ef9f156b95ab3572f156d2a304419d5d9d930176b7877120194f4c6202	1666536041000000	1667140841000000	1730212841000000	1824820841000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
313	\\x0627c80449f8549c634502078f87861cc016003fd57bd4a90392f5618e636c317e43a80a48e280f90ba738ed274cc9ae65a0c458ca0db8a48b914845a0a221b5	1	0	\\x000000010000000000800003e4b561592e96fd0ee3e09dd39f2959bb96ea8367d1319a23af47af38ad0a11977ae30d95f1764eb334896128cf12f2d11371937b055eb4077d7799cd80aa89e1062a72ea41e0ed4726c4ac3b1407528f52a2b51ec0d1891e2187999f9eb9bd1ed407f6ba1886fdd625dd667eb70e870b8784268ffd554a06ae990e06933270ab010001	\\xc944e950d5075666414f27557636aff8add65c79c514607857f74080a75090a70b2e4ca93947075398bc53e079303f531de1ae09188963eb6ce5d6824372eb0c	1660491041000000	1661095841000000	1724167841000000	1818775841000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
314	\\x0c97eb1d5ce739aeb401da9699f922f02b464ea03b2a1c1bff76b211c7f5a2fd3a1f53169252505f74863d7b7ed02a7cb7fb4e15592d8fdc5a3375573598e41a	1	0	\\x000000010000000000800003b6d66b58149a834ba0304859b8d662af25d57b707c7622f7753b3a236f8fb37fb42a0a66cd43caddf86c71c1c6f3ff85501370d3951964158a0b2199d4c37dc5c73eb6554182522b98044a0f678f308c25e71df29e874fc24b8e2957d401766863454acb37f10303416900dbbd811149f571730a17f712570eeefeb0fd3cd7c9010001	\\xcb1545cf097b0bd5288febc6bcab5dd0d8993c9c8730170399e1553cc617e308895e6e0aab45a0e6677ac509355efa5f135d4a4a472726024dcfd22acd7f2f06	1687089041000000	1687693841000000	1750765841000000	1845373841000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
315	\\x0c8bec56c278d1fc38898610c65ab8031dc901b0d80da4b5aca7ebe004c938dc5c103c16dd7d7b4fe3187c8cfa57c54732cbdb3e7da1100aa2690e985ef7339c	1	0	\\x000000010000000000800003a909fa6289b1bce17c968979d47402f9fb61ac03b685d02e6fb6e2a89ce9244859e93a8d688f4c66b1255248d6f7319b3b4ee2b23f29600fc64278bbd318e1f510733d94061acdbf2099296dfdb50840e00e0586854b506bdcbaa78689b5bb36d64709366568537b90e04b12b5952cbd1ac7a10acfcd414bfe0ea54d7bb5c6ad010001	\\x68719e0313a0e95e76880ad4eaa6c6a43ff1cd734fc53645b366bd2b6fc2d49eb31ebba99bc1951d925784d1c26de28624f50da619a9269b482e147be5117b01	1670767541000000	1671372341000000	1734444341000000	1829052341000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
316	\\x0c77d67417a5c71c32c5b848f91fa342e52413ede2e77950726501a472afbeafc029e404ce7a8ea29c410e5e962094b5536e8a8fec699d159725bdd2196e0069	1	0	\\x000000010000000000800003bfbe8c3b3c68a75482f2ea242134b4c6810e832f9a059a9ed7d65819a0e1691fc145beff3ab043b43f95f62e7af7ee06a493b427cbccdad43ba62aa9694c84c527301cd4df34052c383ece862eeb990cc57f17606b48ad8e8b728a0a15662b3bf7df95838e65544b1d7c510b89e6bc4492566931033d6eb31f9592ab3c3badad010001	\\x5dfb3f790b61766cd4967c1b309477cdbdba16becfa07533d55c7d55f387c8c083848b8d051039a3022107eeb3704214a7e76c1b99189313206e7d62b68fe60a	1674999041000000	1675603841000000	1738675841000000	1833283841000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
317	\\x0e535792f12489361267cf65aee582ff63cceeb6f524db6b8565f5ad446ec0ee1ce4fa1128af27a66ef7069e646c4a40d37907ad17d6bf4ad3a43b4376da828f	1	0	\\x000000010000000000800003daf2190610701d0817ebb7fafea2e62594e67c286dafbcba0ee08ebb8a0bc17c9f0d9f54a20764ec472def2c7f1d2320289c69a0e0df548933c985d92cbfa0d6a517a8797c3728e9ea0e1b67a979f4f3f4ba0a8ae8bf69b152e8923438d9b62df988fefbcc52415ba46bb3db32b47e83344f4d7a2f802ed036cfd18ca4389a31010001	\\x25515259ed4e0051cfce7f0d3ed9c7e49fe379eabb0247ace9f949a449ee7c12c0e054e4c60c3d340b7cd76c42da001aa8d79bd8ec27857f5f6f7d28e344a10f	1681648541000000	1682253341000000	1745325341000000	1839933341000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
318	\\x116f22e99f5750d0140d734c91cc4c254dc0235a27e98a1518e8fe4ae6263a6c1d0dfcf661e7b76c0a840674b8a9cf7139534ec50969f79be8e88f8051b02112	1	0	\\x000000010000000000800003c8c4bb916605dc44f45da454ca5d201981f00fe094f9be2422f0748821a2f167e395e5c350f864b2e6ab16fec4d0c6e1a1ee0fe617bb33c3b0f13240ff272f4e40663dee6807c0d7879b2be0b9305354b802f44a571fdf3c7ca714d6ba2935d1af5f7a28d14b21c8214b9e637f8ffc09d0b1339f9e37b12abe1014af904ca8b9010001	\\xa76394d0b2df8d1c951e9e4dcb82a7b3a441c4d55a356b11b494d9bc883631c68bcbec4981e0a9a3eb9f758281244b0d141ec0739a45b9fd431728c6bdb0ac07	1676208041000000	1676812841000000	1739884841000000	1834492841000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
319	\\x14771e77c10c04fd8c349dade950295ab99262297853d76e604c2abb63d38f9587925fbc00f90fba3e18c621f84bcb64584065133aa0e962d9bfc5dca86fb9c3	1	0	\\x000000010000000000800003e6af8b90801a19edce551e7bdc6197ea9b8de18a278e4182d5e9d943ad2160aa7283bf47a6e5bb1a6648aa3a73a5ed84824e36438264c372b79a3fb2595e4fcd1cc423ed83078508a2f4ca9eb13cc3e8f682bc16694ea1cc7144a146c408ab530690449ffe61330e57da620c608c83298f5cbf4518d12c95d431c6f139d0ab05010001	\\xc6012af6caabdd6dc41fcd5e37d0e09c0d3c57f3c6593c1a7f0fe0c0943aff35bd22bcd595b36ddec4678b96e6a0ca2bc0c861ffc9c22769c779c1a6ea8bd20d	1671976541000000	1672581341000000	1735653341000000	1830261341000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
320	\\x14dfd34b0c2d27c1efbca56ecf1c232804e5719b538e95a5d272d46878b646f952d2b2999c1e3c141fdb3057581651f8400141b10b37049634e79a3fb33df65f	1	0	\\x000000010000000000800003ad2dd503db15fdc681a013c6bf347378098e050a409e988b622d097cb52bf02d6e2b7d7c6787a7d523db2cc75b0d519fa2f41b1da6aaa3e0eb74df88febb99c18b313444d26864329c67e956ce5dd56914e9de68f88f5d0fe6d9f76028aa43c98aa61caf24120a5232ab662962379009d369984b2c17786d1077a45604de707d010001	\\x2b940f3d462f4e64992e7a6f9a38accd954b2a659a49550de275a40adb40d9e3834686a8bf4fcc3a14f4d80a6211946d34c9138857f52d0f077b73dcb9803304	1687693541000000	1688298341000000	1751370341000000	1845978341000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
321	\\x163363a4fca9537e6e5cace241ed4aa7fd61352ff0f5e1f6acdd3961464515b83c9a1f69363040320a835535e3ea5df2edf26ec057a3a49081fbac9fd5291bc7	1	0	\\x000000010000000000800003d81142f41d8343850af5445fa36fc24d8370a5eb41eb05186236eae2ae2491835ec47424b671f0813b29dd9d199af8a29aa91a23847189aa45e6b94662c5e89e6ca3588776e8794b5a153650fb37f36f3c5c8ca1f7abb1132a128e26bf239127d3fe1932c13e3e8197da905a822fb81bc1d80517a4e70c832ea970e9182fd6e9010001	\\x60199564003832149a38dc0eeae25d9d2b711c93959746f37204fc03c323124f37453f6a10fd91e6e22b0fdcbe0104a2167511ebc351a11fe74817aa7b3f1708	1661700041000000	1662304841000000	1725376841000000	1819984841000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
322	\\x186318ed1917640f3586d617016f2f61a0338518c9c575cf6fddf398f97a1cb752cfb37b6f25d7aa6c38796171845ab57262ee6046925743f4f1d60e8ed6f141	1	0	\\x000000010000000000800003be4b1b8eac3234bc2755549580aaaefb9fdf677e89a90cc88a74df3418feadb5a05be7f4902bda1ddbd7e92dc6a37b5f70c6751a47ffc36776f2e4cabdd96c2adf962eb3ab1efcedaa8f08417ae78d457ef7a4500f4be7dcc7a778f1398d03cf214c59041e560df03f4ad531c9256784ec4ade46458cad65a4199409ad9ee27f010001	\\xbf8788a97a091f170edf7444ce101fb99e28fcc9b7f8f5adc927ce05a830db57cf9286e87ae4e905554c421ba4eb4dd35744328c32c2161b2493e711240fca0e	1673185541000000	1673790341000000	1736862341000000	1831470341000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
323	\\x194352048be9eb90a468bcfd5c468104eff155ae43cc85c660123d484ad350f57d5b8dba4fc1b701a928157da8189ac6e56f2ce7863e2145d1ca2317aa85fa92	1	0	\\x000000010000000000800003b1756c0601ccedc6559bdeb9a14a77f93387ae0cbff6043084c60a7cf1bef1fb4d94cdf78663870992f8991f2d15720888b0d4c180d0de4e6e64df7807dac250361ca60088d75e610c4319e287e26ceaba6d279a642b0c504ffc18b465348ce42737fc55eaea712c66b1f34b56ee90e351a0521e92ce4aac655a18b523e80af1010001	\\x2ddf4f990bbd32f119abcf68cf5e668a9abe0e9d857d764fb04878f8ff65a860d0eb1efa73b9d198634425117a562c1d911a2dd9ac35d58da5879fc60dc14e09	1663513541000000	1664118341000000	1727190341000000	1821798341000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
324	\\x1bdf34d2948baea46c1bef57b915c032028fcb421070aa6e31c83a8172f73e1563288851cab4cad2b541fa5f659f5aba188d49f691ee1c7d681f4741ab27e112	1	0	\\x000000010000000000800003aed461e7da8b6407fe8b6d4549effd09a227ada6e428e3b493c49d593fd924ad164e0270021a099bbaab60c1b7b1fced3ce97517a1b52ed2b6eb812786b500701b0f6db357f3c1298dfd9bf58a685a35cdbb0b2f4dc2b65ebd3fbb7da90e0cf66d00c3ee88650d3f8da48f47c1d89018f0cadf3832620e4d0142f6c6f09bb321010001	\\x1993197192970dcd459d2b3bba0fe1bb32ce07af60b07dabc9dd2ec3e7ac212fa15f9bdd2c98b1ffa737ddefc760996ab94cb688d078818f874b9aafd6762a01	1678021541000000	1678626341000000	1741698341000000	1836306341000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
325	\\x1dcbcb64e0e7b1d54fbc035d4f582144992f1e4238ea345995a1691cd75399c18f1d5930c562b6ce97691cfa0dbe612d0cd3e20c710a4e7e599385651f21eeb6	1	0	\\x000000010000000000800003ae82533c70d7cd53974c6d6daf1f751c25e7f2a2602a4e95044e5de4e0b88b06111a89ca72847da0f1238083fa33011d5398df4a659272328afe47d6a2b008974c494be4e2cd0e221d4aa6128ebce974826ab42ae70b08935b61a35fd92280870a837e5aff8d7ac6b7a442fc8657f9bd61dd31cb0dc8dd2e4c4991c63ff844d9010001	\\xd837ffd7f1d1dfc7c0bd7a7bc2f0911771cc22f6b38d2d1b8a82c71b1f6ed486d8043f58e8393142313a64d904ff083e6d261dfaa9f65ea7fb641b3e98f2df0f	1665327041000000	1665931841000000	1729003841000000	1823611841000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
326	\\x1d0ffebea01434ad903c62da99db738297870672e6f04270bd1d66d6966447ae5153e4356d9c2b0f203eeddf7599a3e25ed6f3388e83144d5d2debf6f6cffaae	1	0	\\x000000010000000000800003d7379bc1150e8b6e411891ea712ad9256b695d4745840e96238f4ce84fe0f3e8907d22ef7f94e37943a55ea3f3e65fe6d04eb2529dc6304803a07446621f80311ee2dd1568b5cbab29ce14cc8bf66a9fac821ce3b689f7ceca22d3f5502342b150fa01e2b179a99ca59eadf7dbdda2252585a3bed87b89748257da7969ff816f010001	\\x1339bbd454d34f21fc206cc2707da350af970267235b32e088ec00b23dd0d705db9b947846c4ffdf3daece1746b0cfd6dad13d3c85c82866e733625dabbb3e0a	1682857541000000	1683462341000000	1746534341000000	1841142341000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
327	\\x20b7a1596e2c2991aae06aae304e569c673cfe76aa781c5830dcbf317f2c3fb1ebaf6dd3b44074cb74f0d82966dda70d485d4dfe6abce6a2aad842b68883260c	1	0	\\x000000010000000000800003d66fb7d89f7b6327693389ce3264903f3bafd088605fd8cf00f8c32eff470d0555aa12bbc12712e529edbed1a3d3de7e864357f3ca172b0437bc7f7d7d1ba1553d5da8d40e5c049f116ef9ce1000ee775b1dcc9cde1763c76a000e84ebb72daf5f887bb55d04f67d25d096ee0e4d668d8b4cd96f372bc73f2412e0daba1d4263010001	\\x079059f72e4954e02c1397a0045987fa3db4380a6d9ad40486e51d0e2cea3991eb087b445895d148b336ef3453f6ab6fee36714909b7a7198a236f8e0628280e	1688298041000000	1688902841000000	1751974841000000	1846582841000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
328	\\x20f3ee38b21b9ef113e5e87522e0778171b2fc7f2fc3434420bc41694ea709ae68e457bb4c4c4b88dd9174cdfade0f727629279b0f46b4fa1f5c57b3f22e785b	1	0	\\x000000010000000000800003c082df45b73c8da0fb00e01a36bc949186d9aea56680238fb32e460877159ec50f3f156432ca44a478224b21fea36d5133f9033d320f354204b71324fc9be3338b9e775b6c15a2d7d197737bff916406c410825dd9ccbbd803081946d439cbc5f7df7f98fe6cb1662c15bc0718099446c3bb359d39574df5b90eff2d8535c62f010001	\\x6fa907b1a2ad0102be61fc159bb5f24ff44356979a8fc2955c8a5be5b74e605b041cf56ea02ef3b0bffb223fc46b541b72b340061d902c1e18ee4da44ef56e08	1685880041000000	1686484841000000	1749556841000000	1844164841000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
329	\\x225bb5a804682e6f39de7f128929a577ea7f6a33fef4f0159e80341c1e85eec2211b88d59b221b8e7ca945d3de9823a3eca2c5456746554ad68999dc716e4c68	1	0	\\x000000010000000000800003ed1da65cf8f638cc3eaa5739412b7f446167e9bbdc6f35f99c1df80cd0ffdc741e8042d6a711eba6efa647bb4d44b9b1cf20a2b12a40cc62e7e080cbfccc01122a71b0f7d25ced8c6836e43f395775eb279fbf752805b3e04f702d3866943e289c4883e3d2eb502fa057df0b1bbf9cd2907b24f04f42c4ee9fe34cb9df059c25010001	\\xc93dbfb8f8cc46b0ff80f8eddaadd49357ba22474f568d086e01c096267dcca86744610b14eca549f7d6ff9a3c3cb97d56f8118b9eb02ed94c53331eddaead09	1662909041000000	1663513841000000	1726585841000000	1821193841000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
330	\\x2443d138276126b3e65ad3edbf336c113b27dc70b5cab942511b51ddabc30055d17beea2ee39a98e7f840a5de7ae1dede3db64572b291f8413396068ac83bd1b	1	0	\\x000000010000000000800003c51ade865885377b2f3f24fe83274ba614bd8f326e296917031d3abb7a9ca80cb26a56b49fc9f500ad23398508ec47b02570ee863ac8007a88c81a82f30e73feff84aef2adb66232745cd627d863da2433606cbc2ac6accb773a8745a7ea5f2efece535f7e5a2779e7796a1bf6ae0a49b68758fb1d6fe28643fdd7fea3fb1b91010001	\\x90e1e61c9764bd75d1ff33e2c810ddc6e15b65cb4d18b6126117745ae0aa2c3808175733728352cd4c7bc9fc087a77fa084d7f1fb6816eb8afc7e76bb467d00c	1672581041000000	1673185841000000	1736257841000000	1830865841000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
331	\\x25f758a23e99aeb138d3fbc0e6199985c2b31988c4b7e86369de69ad9ce1a89afe14a3ee1de2facbc4082249bddcdcb9a99bae8a2bcd6ce8839e6f26bccd19af	1	0	\\x000000010000000000800003b994038584ee892698ce376cd278cf90209bef0a98d98e20c7e965fff1dda7d0b0b205c7ddf2e0c802dfef6d3a4d2bacb228fb29c58f67a17fb1b08f4d90e08dd6c339cce5c5033bcad938d5fcddc2f9f56242cd2941c463f2f0c1a4f853c01896dbca6c4bb43a567510c70f53600f2ee3b480fc9f09cc97765c3891332e93f9010001	\\x08bad2c334d079ce2b5c4288f8230fcb39198b7b2fadc21d4da41e3ad1178071aa47fbefc752467e03563800c83c998c1d8924ed4526bd13e0008f826a74d405	1670163041000000	1670767841000000	1733839841000000	1828447841000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
332	\\x28d343f9ac6200c706655e5e2195e7eefc4aaa56916400930c6842fe8a094fcc84ff5477642a23150fdc6fcc71d74e5cbbc84b71cc940d489b3b8722fecfe544	1	0	\\x000000010000000000800003b78f813524fd8e531c5e039eb2afe27b699fd385bae713ccf7be8c43632fe85bb2c3b4e846d0809900c5f002bf8a80b1a874554485473776a5ae18a163e029202ec4f0e5a67e09bad8a0782104973bed89b8b11a52a573365e692c7ca0661f5e55aab1a2d13cea7e721277eb8b75cc8ff103daa0733697381ba24b11de0068b3010001	\\x4d3c9554f7495bf94ab29c374d489786f0c01a49f81835add46a81958f386b9ec7fad00467f24e2003bc804971e51e428efc64dc795badd7a396b209d2086f0f	1675603541000000	1676208341000000	1739280341000000	1833888341000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
333	\\x2a67f5e9d0f512c11ce2e0bedb3512f43b93754af75a87e5ed511b72153328ebcdbaa477ffe8385621537b50bac56300b6abe8cad995084ae18980b6be01d50a	1	0	\\x000000010000000000800003db59de41e3b41e22b4d3545ac38879d69a674d3e73d1f27b411329b7826eb7707e4abfeeb693c2583cea4fce05008164514e647b846d42c44d5a4aea078a90a76ee30e85fd6f7a7ecd8aca1785a8bb21c7dbd6b1eeb61193d3cb64739a2e34134c6dded48f784c396fbe0a14f8269895cfe7555e8016dd7cc24cacedb159581f010001	\\xbbf937952202cc31e1a5aba56e74483c2a29a511620e97aa2d7dcdbdf31957d926de728be0f3b641bd3a107af6f607aece7b731bed8b548d15de79968db8e608	1685275541000000	1685880341000000	1748952341000000	1843560341000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
334	\\x2d7f0d645e7ca624b290da4a679eeff006685436978fb2c3d308a2d9c62935c6cc3bf326a44028829a322cf2edbef174326c43475157458fb4e02d80bf6a5feb	1	0	\\x000000010000000000800003e1110c6f8b462b2c983a2f6866f6c8730eea9c84dcd7a1db9140fa052a3a64fc7624c6108eeab29ee20bf0f9f097cc58c4bfd5aba38a4aedeb5f4ffc139bafdfc7ed9f0d53d54bdee7aa811867bcc6a3f3969390bd0e33a1827668da30923050a2715ed6db369ef9122951f40bf0e2db4c12c1b7f36161a4ef9708b33692e82b010001	\\xcfb1887cbaec06f4d80c2bc7c0ea1170ca950c146ef3102fe09f54e339c901769cb9fdcea743b1b54f8b5f072e6944f46105cb4a185b44bf175eba3cc08fea08	1662304541000000	1662909341000000	1725981341000000	1820589341000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
335	\\x2f43c3b0a67ba13c07c0f656ed676de8823f984cb5feae70aa2f75cfd4129f129a5a3d492238261e2dc4049344533c727fe78b61b150a7b12f6805baa544a553	1	0	\\x0000000100000000008000039122e5c7e47e6cb65a7ba4ed9c2717bacbd49736c3379453c84be2668adae05fb8250b475f24a2561154a38e9c57b25e1b4e5b0ebffb3387a7c046c60672043b495e0d18f88f725aec32b6f56c631ca4826d6db2b3fcf4755846c5490e2789e742dd467937608ad54d22defebab281901a638df720f95ba2f2162508d93c2d0d010001	\\x91a3a71de66e71cf6bb679e424a84a682efd1170cb5d0a2aee90ee9dd0a33025306c040f6ff778cebe0887f6affee3892167bd8a4a1c0d58a88a1170db7aa307	1686484541000000	1687089341000000	1750161341000000	1844769341000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
336	\\x30f7ef8a61e5d02406ed325de5b5052ac0b1fcb4dd806ada9a34c4655fa5e8b3499e9dcedf264d406959405b0729faa83ab765b8579a7a7a32853f342e836a41	1	0	\\x000000010000000000800003ba74606bd43fbe290bf7fcf93b3e9ce1b9b4b6866d49f4cc604a9c41ce459bfe1a5805bea3a0916b004140a2cbe8352312c0c24ed06d7456388e8d36dbd71457ba7a27b4263cfb6c8800a3a4de228ecace3a0c3690abb86f8d31d048fcb15fd7d1cc928bb658aac31ed83827905f11a98693a0492ef67fde846e7332dad9bb67010001	\\x266ef3d1b821cfd262ebe6796e4927de6144d713f43de8bad16ac241f561423d2205ed6080f982f25b5cdc2ff13e889db3c5183a80d4c136eb594bef7d544c0a	1669558541000000	1670163341000000	1733235341000000	1827843341000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
337	\\x35ab18dd3cc9fb378320bfb44b11337acfade239bc69ac37cbd7fedcaf8341a9ad473d9bb35a8da176d18a49be2aef18c80c456c74a9184395bf4d171b6c9bc6	1	0	\\x000000010000000000800003e837d75fc08074e20e0dd817fe07c1d47ccfc1a7a33f6781424617df1b403d42a969c25922be63fdedee1efea54f1082971d0a9730cd1140d417233421586e454a942f1ad0a40a2e2ce7a151b71b5d237bbee180c3861b58840c6997aafb2e3a24f04dc1a7a3d76ff7ac5e462a1c3bafc54cf9b6d8ab905ae7706c581f83185d010001	\\xe7cc4bc74668c88b83c042a9b087d4b4de4f572f90616dafd80a6b49276ffb23316127be1da22ec23a480af6466c021fb4e5344e22d4830a644f97683d2ca808	1671976541000000	1672581341000000	1735653341000000	1830261341000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
338	\\x35b36bd244961863ee37c6ce36417e6f66521ac5f02f1a02820927ee9e18db63ededc1ace189fdb626e1df85e4fc1428ea64f4792dbff4a9269ce02e5a3fcd60	1	0	\\x0000000100000000008000039e1ac089a59c39e4a8b197f43bab1589c519d31dfdc6f0f90d3c2f08d5fac5f436bea25af21a1c85c253b5bdeff18e58b605e150f3ae79496cba517a798daa32a5d500a61a5f54174d45248ddb92eabc8d2008949819963d0db2d3283d3b043ba592bd0e31d190ccdc58d9d741c8f2f4fb915726da81f2bb0500e6a0520d0b37010001	\\xcd57498395584c89ee9740028a660d7812cc87e21941d4cd8a2b33dfd2ec9958bd78ef7d7f53f135c53e763a3d2b9efbe3eb1b930b86aa59c877f72a2143630b	1685880041000000	1686484841000000	1749556841000000	1844164841000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
339	\\x397f141e298a2fa86a96501c404a6bbaebb4b7ff1699c8d72a9f493de47657531d02b581ba0623c922b4ec35c952bc7cc6954171bb884fa266fa594a0aabf747	1	0	\\x0000000100000000008000039fbf355eba71c14ffe4b6777eaa92c5e7bc1d1141c9268943641b3cf747c6585cb2f25df3a2e0b35c98a154532224b098c33bfbff0e836ceb2f76709be9f6be36ff815e6d9b3a2c2c4defe59794d4828d6abc6fdf0add426453c485879c1800f738451d50427fb70f5c16613f3e09488fd10eb82c7a0f717a4e1710f42fb73c5010001	\\x64e8a790c2640d1e5f81bab43431888c16e08a02daa7fca52c1f8355cb74506803aec43b3810f9a103b0594f75eed8252df83b72d72fee3f1f8c7412824f0900	1664118041000000	1664722841000000	1727794841000000	1822402841000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
340	\\x3bdb1f654d5f85c7cc467180d12dcbab7b1a427b345842a4d0fa56c8fd039bbccd52c409195d65bc08ac5d9dae9b61a1a03d11bd80162a76b2a3061d2be67d91	1	0	\\x000000010000000000800003b8c35f317c354b23369f826435faaddeaf2d930e10ab57e1e670115f6b5667ffc60a417c7c3dd247b3e3dca40d2e33f71f50c56e67ce4ab55965104b41ea177dc9c88de41e43834fb8e1c9c02b2fc4017ac3182c6b94f8e36ac7fdabfe6e52435bca679be1777f11b828142d6a2aab3f909a20d154765095515194eb60161725010001	\\xe9f2db74a2f36125098fa06203fb16e853605ff9a00c2689d48ff157150c3bac90c9f188a4626e5926aea8aa195f9fa8542fefd5ad25fd91850f89eb686df100	1674999041000000	1675603841000000	1738675841000000	1833283841000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
341	\\x3bcf4ecc1fe398c35b8d9a926f1c8c752d21c92a8b2a8b1ab68057c2db6dd68deba488c8f28f3b86c9dcc97036b3fb16cc0597283e4efe545bc1157b12a65d4c	1	0	\\x000000010000000000800003975ed04ba7ccaf7f6bf91281188f90c2172281e687de050d06d880c8e5a361ba2c584bc2568800990028cc7b068495416ad6a6bf8e77e04b3ac69d247b7af27f7496ee123a973c46dfea72bfea1dd5dd3051e73fe27894a3a73bf3fd488a812620d17e7c36a7f715d6738a2b0719a978d76170490dcf840f553200cb33de8233010001	\\xeed16c2cd6243fd080cbdfd02ec4ffc1b507b5bb9d2cd7a2a40636f3f3c48f46a8e19c17816fabce265e856ef36dbb2bfdd88c1fea2b378843448e0e6826b408	1673185541000000	1673790341000000	1736862341000000	1831470341000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
342	\\x3c0338ac271c2bf1d100dbf4e2cab0e98546be947f69ba873dee289d095763c6bf173a27d871f18bdb4e539a44e181a3edb447bab092e01803ecc16e88274424	1	0	\\x000000010000000000800003a990a6734e7705e3c587d155a2950150a240da7499bc65840dabd0afa126fee0c32bd9cd0cde2e4f0b9956f29fc09d3a477b3cf78d7fbf8a59ba648834b8d713726149bceefa8e9eb14023374b5b9cafcea500f15c3aca78119642207b3401ce8147e02a7d2fdd571ed590fd1527bbd123a2aa8b472dc2376fe3bd72d007f569010001	\\xb326e95b54f483bf8c90db4e7040f03834d6c68654e3314c88b5370fe83157ad3849a497970d51f63e9cf1a62a991ab5703baaafe8a8f4f1f0c6c6814060950d	1674394541000000	1674999341000000	1738071341000000	1832679341000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
343	\\x3eff50200c7ecdef0ab785aeafbf3ac7cf35a1304dbf4f3f54c86825e1dd014f101d66b6b12591db189221f062f758b13c2cd9cb24617d3edf71fc4974b63197	1	0	\\x000000010000000000800003dea445314f6d5c09dfcd416730f3b85d162824c9f16f039a965afe123cabd87c33b626bf28d680bfd4679b4152c424bc5ca5f16bf0f2b624e7fc42f1d218e447c58d4488906dad28d78438c23d1c8dbf057e3f4603639f08ffcb68ef16e7f0149cfb6255e4570035df15f600659c9865e80b32ab917b9e239e46c3e72ad9267b010001	\\x03c9a184f6f149ff31e4afa0997dcae9b0d48a2dd310080c2dfb72aaccd6d6cea6258937cc5fae6256f80b20e69112cb80dc6d557487beff5af5c3151aa8870b	1670767541000000	1671372341000000	1734444341000000	1829052341000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
344	\\x405b5fbfe769d0737613835b679d45016a5b4cb1c3fbc762005c2ab0a2749edf7ca0a201e2cb9afb8e238a200b48d5680210898d5573537005f22f42fdf53c27	1	0	\\x000000010000000000800003d9e62164d76e1107e01610b424dfb9c390958e6c2a6a4b409d7ba38bb1c4718cce48a61a23c1634fea9dc482afbf231022eb75ffed07112d17cff888137b0a3e6469e07916c162baf0b6054487ac0e4ff47fb883330c4063cd593f796b3b768fac37060900052075dfd111cf45471e53c91dfa930d7069bbb62dcc9efe9391b9010001	\\xd6b85f794e585ccc5e291a779d662af6ecfe0d58a036470a2590b44417d1ebb606aed19d0598b0fc1bed1d35811dd403f54a0ef0ef9311e370b42b445ea06107	1682253041000000	1682857841000000	1745929841000000	1840537841000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
345	\\x414bfde85e79cb3b1e5d22517e06d523fbc3f1bc9d6758ff3d25db117af8776be0afeebf4857e6bee19348dbbfcac28c590304f97cd73a3090398554c90b2d9a	1	0	\\x000000010000000000800003ca883235f9fbcf63a5b6ecaf2faf315d01edd5afeede9b3f27b37b16ee84d44086dafbd1d47f3c4adea1fcefa207eac2404b26360f21d8f811f729f0603b3e4dda3aac4f1b70b76647ed4e940e4147a7fd4e7206e6729a48b82fd04694a6ce6e4489a6c94a53a1e7a2bce27f3ccdb2c63fdb3520322628ca54cf237c263b8807010001	\\xfe94207dcaf01d9866121af2900f6152543915905a663ef5b5e76f6a2b26352642c41747da18cbd3464bf6a7b1489720598c0d17060438802ce3f3e28d9eaf0f	1664722541000000	1665327341000000	1728399341000000	1823007341000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
346	\\x4403ce766bc43ed3bac3992ca56c55f11d393bc37426ebc9c3ee57e26e774ee678ea30d08ae645685a407648dd1f8f9097ff3af2a92b6a58303a68d078b40898	1	0	\\x000000010000000000800003bf66d9e8ae605ea4f3b118a5d2f0303bd541051298b4fca1e8e2d7904282b6233b12bda67445d7f88773eccbb4e924b1541d9f7c58a3af3d9ff98617c8b05a796af27d854ee6a3a728e6f5a11a5533dd13bdfabd189becba5225eda21c9c23e06396cf9aab090ce26837b09a43112df7871bfbe1f7d99525c88dfbfa8df9110d010001	\\x12899a0241aa988b59705adde01ec57b7d116e170512bf327a431af343fc53a15c33951cf1b01074b5c829117fe67a958c7a010a27118996666b77c00ef16205	1670767541000000	1671372341000000	1734444341000000	1829052341000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
347	\\x4457766c470b94c7e1875e694c7e6ea3262800f3741595da769a43dd6a5a3eb9329f35e8ed0c309c6a052b3fb0bb70e7b3bbc45ea5e875f4f679b4d21c44d329	1	0	\\x000000010000000000800003e051a8a3fa47d8dc3b6fc0bcae209f042b210a8a719ab59da61da75a0ee1a7378b49101e34e073313ceb8cfead43b41454e6440c372f58ae6fdb40f04a1852d24d0505e6baeb07f273e9e3ef31d09bf6d6a01b876963488d5e87b223068b29545e517e181f72f780b4775536f63530000681d15e7efe7c34beb0a14a2627623d010001	\\x7b9c6db7eab7e3d243f98d4b4e3a96548b8f989b54e85cc39514bb148968b52d9b9ce0383a9200b4f8c95341fe5f93094bda4c7960858065a0da9653d61c8c00	1684066541000000	1684671341000000	1747743341000000	1842351341000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
348	\\x4647083b8835b02c873180bc92c02444bcab430143fbda59e1cc957a6215d8c5c3f4497ab1797b7aa397f4dc7b11cea10ea8fa3ea166bbced210d930d77f2236	1	0	\\x000000010000000000800003ae4100f0ccb1f26bd1f0c8509cfd84aa87083e92ce24857870be92740cb1323df377404ad383237bf8a3012b16a9918237b72cbbbc2f0b9c9bb287eb183998b2a310caf07bd255bcd23ec7e1f3532ed4c70391a651deed71e25827dbeadfd9915e1e027c0431ae03d6e7cad0cd4d9c5ff758139ff68638c97484225ffd2f122f010001	\\x80aab6af7883f0c0fbb61235897fec288a569a1beb25cd02402ffa674ce14380b53716ad9cf0d026f888c57e75343f23ea82331932eb846fbf5a64ac5db03d04	1685880041000000	1686484841000000	1749556841000000	1844164841000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
349	\\x47af915fd3f1cbc76076f5275f2e5dce669bed57f59cbe0c08c9a6aab1ebabeb4ffa9ee23f1aa9111c7345c5a0d672599cd0bb4e6d56a59eda4a828931d4a30e	1	0	\\x000000010000000000800003aacb10b80da853ba74f2ce942cdaea3f430bc566b0d138486ba83945b9f889185ffe3f5d046ff609d62fb71fca7df070c0ddde7273565c910889b88204eae270214b7d59290f0985af797c5772c3eb83414e1980728946d7d6f4d94e220caf3b6c235cab06f06fa3871a011675720a33ec31910a7f47c0ec4c4176cb6a2092f1010001	\\x8ad67f7dc1f35518661f4c3b190a38d0b095fc6c7902107c4ddab45b45c15b1c77ac15d65314023de44956ce8289d68cadc0376cea1f6e6f346251328a19a902	1664722541000000	1665327341000000	1728399341000000	1823007341000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
350	\\x4adb569fc36f2a10235567ab96d14f584671343e2bb061f3e5f5fc248ac580f5b5f4b1d106cc7a4c05d797698d628ac81692d8be2c72bb347ce49e3af90c400f	1	0	\\x000000010000000000800003b7695d486206fb190339d1eeca7ebb268aa4823c1492b27a0f1020d10a64bbe96c84051754e9b60e0b4044349134960cda1e0fd42acee14c6badaa746ad5d2a9e2df92190a10f271559ff8ced4fb0a39fff8c5b87c9d31ecff54fd560f60568de1aaa7eafc5d00322fb6338632a7c6543e86beefdbd6ef8bc88be4b67ac5750d010001	\\xa0f02ff87ecce6bffffc36a0c9caac8c2bc11fad74031ee73884c262d83f7296aa229491565ab115cadbb8455cda927566145c091386bab027f1756ea1d7240f	1670767541000000	1671372341000000	1734444341000000	1829052341000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
351	\\x4a8f7626766e53aef8747002e4fecf576e36c0b5b81677a18ec9cb96045e59839d8d0c0a911fdcc5320e9d43b47ac6c65cc9f7fe2b354316e3016719cfb03a3a	1	0	\\x000000010000000000800003a63990ed5dbc31358f82dc4c41320b36f8ced5addeade8db8850fcab185627ccd27e2c799894bc6e35082c73f2af4449874736e3d42c33f0171571ce4923f1c75dcf7c039afbc212c5ac4fbf8c11a60a66466005443edf162a3fd37167e3243e0ba211d8fa946c3a46ce74e69b2a2f6b13bf7d47ca6093b4f135dba653f413d7010001	\\xd76f7c91049ac1ded1174ef1fbea44bf5bfd51a451ee8b4d6c4577d6a20204c84c9e223e147625c08b0167e9d92ba4e0e5c6c0e8e47aeff31a3a3371d68f100e	1662304541000000	1662909341000000	1725981341000000	1820589341000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
352	\\x4b57132a5ef65c5798347df97773a94ae22f0d0c10ace49a173d8a5d20bb3247fc0d8cfc0aef6b42ac6c0e26f819ed69333f02f8ccdd7213f1ca24f39e1b8543	1	0	\\x000000010000000000800003bffcf08ad542ebfd11f3fd3edac31e489fdd6ea1bdfbcba9b93747d79a98c1d11fc49d2276f76bf8ebff185b5fd6e127f881b5dcbefe34c70de07ab9a218733dc69316fdbef6cc85b59a5fa1daa555b29a6b38f69a4bce6a363ac763ec16c1acc80aa44fd22c659f0bc70dbc98ccce5a44685a720b05e5d44edd3a5f0b244257010001	\\xd4aff9306a2a5b836be3a3bf244a4aac16e9a10e2915ec592cfea9af107484481dec97737cc49e8c6cebeca734cb4ad5daf25adf119e70ddb38e4a1040991505	1663513541000000	1664118341000000	1727190341000000	1821798341000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
353	\\x4eb7dd850e801c83016277453d6c040db1f380fd7817dc28a66b35e07042e7b339551b9b6dc7541443e7d4bee1f37a1f9b545618d8145f235d75afdbf4ad12c1	1	0	\\x000000010000000000800003c6f363c430584499f1dcca161a1ff6837b9f25e31b7ce074948037e3fa5f052396d0daddb317a6a40c59fc2d91d4b09d48e39af6c658c56f93856f780d35394e471d22867f695163f4458512851ad70c1df7b2ca26fa166e289563bf2b13e4a1006d9ae6dd4d55381a0c7b90a26ab143647cb4760bc91959e24e70c670b76c6b010001	\\x1b479b948f9bd597a9b5ec5759785f7bbead7cd67c65efa4a58ed24bda0fb84ad27c25047e7a96ef8a1259c1e58c8da0492ad31e8656f95fe739746143ed7009	1685275541000000	1685880341000000	1748952341000000	1843560341000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
354	\\x4f23815c2cb97af824e6276ae5c3a14ec8b92d0d260c1db6e98dd93457ec56e934298d8474370cd66869a73c9b6663b08e7b8802e6d6386a5efd4e09ea6fc31e	1	0	\\x000000010000000000800003d7de54d3b55bb12715f1a4eb15d4cf36068c6944c03c9e1169171b001dc810b3483ad5616a1ba0c5b5e59d5d3027c5b4188a0a1ce95f2e6ab288685cd7d3c42a16941aff1d022b9d0247ba5c155ec7b4337e8f2222bf87e298c27550414f8ef02e9ab5dad66f82d95085a916a8ab1148a55a2146d538d25e460aef355186fffb010001	\\xf657ba33cd5fa000b5fb2a21da1139971ecac6603a95200b4e30d28ac2835d9588bdc6836d4181863ef166cbd42e91e91e6804db7e4f3ac5047afe4b15053604	1687089041000000	1687693841000000	1750765841000000	1845373841000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
355	\\x4f9ba295583239965a23939513766a9442c7da67041a54718d7414150eb0fa8ab14de6599936315869192f58f22799045dac6d2e652eb15e9c29faa1ccd2602c	1	0	\\x000000010000000000800003d3d7ddf556af3a454538b13b140319506ed5250f474ce771795e0f6e0497e33374e7b902c2dd34eed72781d27c365512b4d017c4b0324b66a3bc06a42d1c44ce1815cb55339bf7589fc7e21cf0560e05f22b895dd3482e7585980cfafd51215f2b28e35909ad44cc41eddb917f796b497222f68b4692e29d6af5780cf3018cd5010001	\\x84e92a44732a35421b8fefeb973d619c2a5585c7ecb5fd1a3f07d5a620e318ae2fcde7fda876da76dfddb64a03d865ea5f7809912be2695efbfe4e6a57d0f908	1676812541000000	1677417341000000	1740489341000000	1835097341000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
356	\\x50bf6fcb105fabfe41c5f0540b6a61ffa36dec02071e523bfee78f1cfe42467e55dcf9532079f65165aac393698934e06ad44fb085e0843ea221767f841541ea	1	0	\\x000000010000000000800003c0d05afbdd8d7154c01cdd5e6a9b54ec3ec95d5fb1545f0b443b580de71393f2f05de687e4eedc9f2cb9e47e7a62647d49d55a15e0b596a40d09f56edd870f0d437c2e6d2067fb17d2ff8403d8473a943de366cdfe85a887099aca22a875b905bf86f9a7731cdf7686bdeaf64bad972254f091f18ef9d1b8be8f31cb8586bfc7010001	\\x995a0a321604ac4211691e31c95e358a52604cc2f6dc2b71f75c0031bb32e7759dbfd11bc202ac2004f929f31d5b4353fd614720383a4921bfcb32d63fa2bb00	1676208041000000	1676812841000000	1739884841000000	1834492841000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
357	\\x51cfc4adfe4efa00d99e9601fad6ea88e70199961f1e9d6dfd81aeb823e41f8fb9f72648799ff1db2827607e4e8a4267aa42d6711bc4c4ecc7bc4d582e62a81c	1	0	\\x000000010000000000800003b5f41ecda23f3e441dd7cb34f016a5804e025de6ea88090bb282f83052d199a5b0b32a32a6c22a112e6071e6442462a3550e77e3c73316f8267ccb89b958417eefdcd53842c8dc9b04af93eace8f96812cf571fe817f002fa87fd57cb2ef247c265f1ce0ea1930ead619b4791d63062da32059948e09c6fc05caf817079f1b39010001	\\x8d5a82cee11a29bbfd6c14e946fd56eb126deb22fcb6589a6042c2104f2f1bd6810d6a8853ea3832b6ee680f14be1384b8bd30c16383fe4c0d2dabbb2d8a5608	1668954041000000	1669558841000000	1732630841000000	1827238841000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
358	\\x52a7d32eac6ecf4495f8e7a21c2868949cd7c72d8c2e1f9a38163a80bee927be770fae429e629502022d140cbc3b392b2c9fe4dc41356dd881e15ae1e3e0e7c8	1	0	\\x000000010000000000800003b9b9f3683c254155e4b63ee0709de2a843d0b921bc5851bf114ee138b2608ccdb7aa10ff5dc21514de4474c2762bca7a02870e3f72e9841d6f574ea4628339b16761124d6f86cc74dea78f035904ccd872fda7e2d4df539a776e299ac22b1095d5e7579e9bd4caa8bbaa4c991fdf4de3b07465a4c0a452e6a0da1af3599b25cb010001	\\xa725425fb1895c8c6fadff8e5431fa3a510dfeea7c361d762140b2fefecd17f9e62a857893dbf44e6d92b8ac4d7625434fe7993fab41e5bd79e7a1fb118b0d0f	1680439541000000	1681044341000000	1744116341000000	1838724341000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
359	\\x534357a0554d61b3a733dec3151f832f2f37598f0ae8f25dade907ba05c5e31101cf68d6411af121ffe2c13c136deed1a62e21ca6980a881226c0ecbf4ae504c	1	0	\\x000000010000000000800003dba1fd41697b565d150689173f355712895fcb9f51ef162835eb9084e8e88a9a1d3d174d1bfa1c63f2cf683f400aebffd7c4aeaad1fb2e7c1d1191d984dbb3d6122866687f7d00e9314d90e1cea6b9d96ce54213a5f874db12224ed3b548e7c7b84ad8ce68aab375cb9072b97534e9b81e3b52e49a8b956dfa90930edf948be1010001	\\x17e022e77d17f87f7acea1ddc2459fbac80cf464b18aa491e6752abc28ca4c9f17e5381672dbbec1955b0ffe44701f5cb96a1d4efed3c8a16d9e220a392d9b0f	1664722541000000	1665327341000000	1728399341000000	1823007341000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
360	\\x539f66e94cb8a628da724c284c55a8b8435b72ef74534919efb6e5ee1e8167f39c9354f5a65e578d1c0995c130594783ac2855584b5b13a16e32acf9da8de99d	1	0	\\x000000010000000000800003cda68d0b8d543e415a2af1d0d355642b77cd3b40f79c5392d7e5019301611a0c69b15dece9c1df8c920f16d9d4d16bcdd32919b7e8696890253f05d9118e5c59f7a586d2a00b11fea535af5ada4b60933e8a6218bdd41bdf21f4ea94624039a155a5391ec4e318d538c8242b57093527a3e9396f5ab9350c4d0a399b6c9f63b7010001	\\x5fa7852c11b3b41563eac3f121daa02b844f9ef09a470b28c96a5b3ec4d3bb5b62afaa3d9dd479dea5a6a97fa8512e4df5c49d8b72bf26bb84d985f965bf0d04	1676208041000000	1676812841000000	1739884841000000	1834492841000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
361	\\x53cbd717e2e60775356f15c72a161957ddbd8ebd06de0c73230c0c20c463fcc3485850926d97a1f53268912cf8d9ade60cc489d0da5e81669e2bb1ba50033f95	1	0	\\x000000010000000000800003c8026fb1480d00d2aefa1f0bf55faf73b66dc230aa9d2963d13b0a0e5a88073b4d92c7eae51f7f3fbb7896303c1f4b5fffb693631e6c3847797693727646556f47fd7c1f88bb6dbdf130a9177c78ac509b175c031c0f4284a88c1022310347c51c2079c3613dee581f837192484d56f5fc2c7cb2b8b7a5cf15a7f7db602e8809010001	\\x336347ab8b094365f4b314f3159e83826535eb7d596f09438af81f890839d583436785f20b5fa60073fc860c027739b36685b9de8b77f30aa62a7b2dd0319809	1662304541000000	1662909341000000	1725981341000000	1820589341000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
362	\\x55cfdf04093cad34dd2a96c4f5e407943b396c906e39dd34487b11f5e893b5df6c6710da5574b0ed26c36e8c072aff5ed60e3a7fd61140a88624b2dbf459439e	1	0	\\x000000010000000000800003ebc9f15f33d8862702444b160d964671a9f8d5d9e5cf8027b64ee7bb395f2532e47c5b36bd34b60413088db2134d563ac1bf2c702c5fcdcbd4333c4d62126c92d79f9a966c4363f65143a4aa4e9ee64f34c7030635547e7d5301df0fe59f84d65785a11ef5d86a80fb252fdcd8a64ca05739549b50c020fc6238f2b70dd2e603010001	\\xfa244bd3983f7fec90191f36b46d6f73d6a0ef5d1eff5833d117b74adad715eb3e5a0a35e9e116ec74ded0cf1052221f376bf0720a30cdfdf0261f9ac6094b00	1684671041000000	1685275841000000	1748347841000000	1842955841000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
363	\\x5693d58a2d4b67166e3023f34ad033a5c766fc6dc690b293b41e5e874fc3df2e93bf2c1d441907c6572b39bbf0b8cb24e7f41513d7c9998fd854e71f4df1d0c6	1	0	\\x000000010000000000800003acc5a9eff50c16a0e7359874c58e2bf5ff24c7d528445b0d828ef7a5e7b8ceeaf73b3590b32b970dd29db26e479d287e6eaa75c5ee571e9271507bfb5f1ddf87084b20ec15f1def0367df3feaafded8dacb1a1555cf1ad2f09529ccfc0e2c7a4dc87ada72d35b63d5d118090d139b3005b3e3d890eba036baf95a0d0ccd5d0f1010001	\\x60f62c3a2c9a05ca4b511231e198756ba6e2f51117553eee29efe25abe6d933e087e92d887b5657d22041441dd9db90ec0d0b31fd7fd2d39bc86a9a2f3d73403	1661095541000000	1661700341000000	1724772341000000	1819380341000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
364	\\x57f775fdbde2f04990b7d52b8e7b45c64279d7d527f687b843f6e8dbc5df543e9570611a0e72d6fcde8ce56d3f451ef757dfdc44d185d9a83a72ebf286198c14	1	0	\\x000000010000000000800003a01ca6c04d6544dfc116c1e6f49304c59e67c8ba39409aac25fc54133696093ec0f0fa3797b4c84061957739b7275df1cc52b11147b03b8e0c7865f58c2bb3c7c000ddd341f5e9f4ac2b8e183abd2d632d5d3d1140c101a08dcce1e59ca4017e5e9b9b526bdb2c7779f7fdd82d2cdb2b825d58d8df7c049ba9bf60a4c287a08d010001	\\x31467b465fd97a977bbadf5497622996e096a3ec14abbee2f9a388da8d2b037ffa5ceebd9b060612111642dcc38889e53809729be540eda3d478bbffc1b7e50b	1669558541000000	1670163341000000	1733235341000000	1827843341000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
365	\\x5a5b993a0513cd3daafee2b55c0db52b56aeb9e6288749bb5240828e7f84aa8723220fdec118d69d4ee2092896287ea26bc40258c14ee4af1c714d9750870e4d	1	0	\\x000000010000000000800003b986ea6bee98cf670854eb08f68e29c65013df16bf063f3f89825f861cb15ed2e74f6e9a6bcaa46891bfbd3ab8442c54426369f0bff37363e5c48fb97e70b392b053d0e1b8d71e18bffdb3145022c1b727e90519ed7199c5337fef03fa803bfb17d07e19db62b48f0f1ee29fa42ff606b93490461ab3aaf04c344e030741a11f010001	\\x78f021b96d5bea3d3ad82782abab1794fbb882b151bdc9e73bbfab94c7ef67c8d880b8d0c92237117fb015a0581a26a83391b5224ef0b7dd212a35923bf67a0d	1670767541000000	1671372341000000	1734444341000000	1829052341000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
366	\\x5b3b9cbf3bad250ad25009aaf4bd1cf576361cf95211c6afe2a386e90297793f370fae90efeea19251cc4b07eb578a4157ba6aa12f785ee1e8943879809f3646	1	0	\\x000000010000000000800003af921f3766dea72f4e9195ad2c3efb1d9b13d2912879f182c559c8a0c61b858d9e657bc1387c812703b3aeebc9e96e75304c2997030f179e0adca00aad3300d3ae48bf8feb5591c1a6665df348828e5a547acf01bbf70083c4e91c13b1a1a89c8665820b6395eb28bbdb67833b060d45a816843cc5acb3ce88025b2b7b29eb03010001	\\x34fd3cec5a8ca5fa741ce08a96729511f9d114353b29c89a22b6914a4e4f8c18a50c58d21670e1ffb6a40681fcabde9a10c3c3a1bc4190758a1fbbf0280f9f09	1661095541000000	1661700341000000	1724772341000000	1819380341000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
367	\\x5cab9c17edf030b8b428e323e460ec896fef5dabc9a722b234da083fb446a41d6a01f5ff70353d68ee4691f537bb0aea20717b8d4218160e694d6eb5f4ca9056	1	0	\\x000000010000000000800003abf0a550279134632a7a41dc37471cac2479bddc763c168567ed0510397d7b1d1a3441ac9b64f4a76f6635350920c21cf0af7332839497fc8d2f2fb0ee7dede3fdaae8849fd3035db35022680809a8b89ba67cbce3b687c45d417113473fef1be9cb0e47a8510618efe8f98091dea9e8ee9eaab39923980ddade97bdaeec1d0b010001	\\x346b4d0dd155b44653c1e09db4593ea22b7b45d181862b6e6c7dbcd803209c824e15e94aecab79b406da8feaa739d8db76bf3fa14c300f174dadf848d4d30403	1663513541000000	1664118341000000	1727190341000000	1821798341000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
368	\\x5f93ff5bcfd22b7f39a87ffec3c8844330f4ef10a50778f521296cea06d65aec63989ef26b995b689cf5a9c2958665fc058ea2f10e5f796041f80de33f818842	1	0	\\x000000010000000000800003b30b56c9968ccb11e9e2ea13054480dd2a4f63972a9ac77f0d691a47884571f10b10bdc1e4560f3d2c28aa0ec079815c4a8f5469e44e383336b4111263b57c00e278219442f0963781df3a3b641154da66ccb910c1763ec165b64dd330fcbad8b681ea19cb6543fd8de5a1531103cee47c72139275f7498fc7e75caa0b5a0407010001	\\xed47920fcb6a74fbaf284b082fc53b1f6630399b6cae50ad2fbd025327a43c63c69e73900fb231f496021a0d008eb0159ffb4b8987ed608c0983c9a9ddcc410a	1686484541000000	1687089341000000	1750161341000000	1844769341000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
369	\\x6033bf42720170e3728427fdde906039029bd76c734efdca536cf0732cc81db68f2a4961618d716ddc3c99fe4da2133e3b7affc31efe1459fc5c1f1f4d5620e9	1	0	\\x000000010000000000800003c44da0759a39b4c02d1269ffa10f5ed2910c1710fb76271768e910d577942724feaa00f97d0280a2f4bc4e03387a2edf2026618a903bb0c1cd008d5eb4bd9620e198d329d90fe7e0dc75cae8c44e5e08e042ef888d21c78699995b41be76c06ffead95da440b69f6da905024b09889be431d98fdd35ac79ff27538434d9e9557010001	\\x4eb695ae415fb5ee22b92d8d7efa3d2b03bd23228f714078a150f965dd98ae27a5957bb8c6f26022ea70f3ad2b541e5f9a7edde9ca4612aa170e6ee78730890f	1674394541000000	1674999341000000	1738071341000000	1832679341000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
370	\\x61138e027bef38bfa3669184a6b1b84568cb68dc65c0f43ae4763079f018677b3ea93d4db80f1cddcdb8cd7ac4c29383563fb0d47383efc26f1dc777ec50c0cc	1	0	\\x000000010000000000800003a389dece1eed445e0156c3419e411a06156c1ff6fb11b6dba852944e0965fe23a90e35252fbdf4d8e5ce725db7021d05d677640ff5471c6e8b747c055eee84d1de58b5104f1fe265fbef5a8314e408c362e6f40fe3a1e9be83f2641d3205883dcb7bfe3dbfa957fa812c87d89fc5a58f79b8dd1f2de7478e04d2ba075ca0d8d1010001	\\xdb1444d127e0a9326c3a27170cfd2ec88e8c8575792aa026bcd9985d502da21d7f19721bad5e0a320c96466aac457cd667b8f8f03c72b0e6293a506109256a06	1691925041000000	1692529841000000	1755601841000000	1850209841000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
371	\\x623fde7ff679282474a23c87c062ebdbf39b79270e15b43364a8c3f00c0745ddaa1eb2432bd9dc3990c57d10ac70d6ba62f6505172425f7b336f9ac6e8aeb28a	1	0	\\x000000010000000000800003b8e98f84d697bdeb012db6e488929cc61e566dd84db5760d87ae8dc650593cbc19a2eb3c42ef132f384d125c82272fcdda867b919437c9d42450682896702d44dc8c31e71b988003792d566a1c0449b7817f8696a21ee216f06fa4f3a2e8eab75b4e80b83f1dcc77046cb7d855391347b7c35c0d423f8dae1ae602de46165a9d010001	\\x219f4a70971af69e303b54ca3ff643d56eee3afab51d54ea7e2aea8f6db8bb92bdf57a0472d6672381c3c87e44d6cfd562b6483c5e770cdccbf8087ad514f305	1684066541000000	1684671341000000	1747743341000000	1842351341000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
372	\\x64c3aa7cfdade945590bdc1a4df701a32ff14c033f91cccc8d0de2417f2ad9b01cc98ded0c5db9d7928e8d87282e8b53d926742a91bf348973225c067c8f7c61	1	0	\\x000000010000000000800003aa789d8624567ff777f8c0c7a335d6ef7b35dbfb2bbd6a194fb5badc496a0950ddca4db250f08ebed2b087448627f252f13bbe5a0d5507f3f1e1f34a4470a57c52c46a3d0737427f59e1ae6ccf7ca8353dc4ec38cbd06b01b9d85e1a29387e3beae1f51ed2cd03bfd3897724903e55f6296bf27c30496249449b6edc03c9cbd7010001	\\xadc1c63013b5fc2d1301fdd8f2f2213e667d40098f342c90d376c14407f89b2cab2fdee1d4edf4dc9cd8448144a00595cebef3475e177028152ff60460de2308	1676208041000000	1676812841000000	1739884841000000	1834492841000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
373	\\x658b59e4701d6a7d5fb4f2c94683798ea82e0e9a61b47af8b01b931d73d6ab1ba221f13430c66dfbbc4735db8cea64d640097b89f6fadb4678423a6a47b70deb	1	0	\\x000000010000000000800003bad137414def071714a05a51eba105977e260c23d41b8af9ac388e196ba79ecda9f30c517b49b20f8bfd4892f84d7ee4ad08969e71ace6be002e7c8e2c07e85c44e0cc1723bee0894273bcaa40c24d139316b76aef15a998b8db147de446abfef8719096d3584eaadeaca605fede53942dab59bbb1479df2c35ce61c208e0bb5010001	\\x185300682280aeaa90b309122ffb168023ec5b221e75ca8d20e2ef69f37cddce46973ddf54e7357a6b9183ff2f3c801dec759fed33ec277acec68fd818d9530b	1681648541000000	1682253341000000	1745325341000000	1839933341000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
374	\\x657b83cd62ae07741f34cde34c30c3463b57b6fab1d84b7b10dff1fc58701247d1d20c154cac5cf0a83099409bf0d914fffd3432807076c503d915ebf8747abc	1	0	\\x000000010000000000800003d612e1d83beca5b9f90d5d5dca09a93c7e9ed6bca915dff3315521aa4944f6bb86a62c4fecba7cb32d27df7e934397af7300ee46b51471e2108b413b74006a95b1e14403052b22d2b53c5d5230d0deef092b220e0eaa36ee4d7e3c952145e9a7374df60ae1db002ea4c373ffb50a9114aebf18690f54f671d5746a3b1c228fd9010001	\\xcf5804f33dbc165904a78bfc3702556459851a9e59128b00fc2d9a074a5d3be6f16954c4f973eb9c3d4faf11e334f9cf61a50bcffa2cbcb734cfff3e140c4d03	1678021541000000	1678626341000000	1741698341000000	1836306341000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
375	\\x6783fb8e3bfd67d45e95ad18964dce9b1d66e3777b2a0495534f4c5a2f106b79bc3dc1e0b512b0b90c5d066448c64d03af5bb067316dc34b9ef0f8e7654b5106	1	0	\\x000000010000000000800003cabd11eea8cec938137ea4841d0a8c6425804c662ad6502439ac3db19524ea12f250834ce4defeec90728c4f439044feba5d9478bc31ad8db2c19362b77c3edaab25dea75f00db6f4d59af13112b5398f82b832e3797f44f72872a6901e6d7641a060e6ff6bc552aae1c2e97ca8e735d789f9aea1fbe6a8c99e33ac65c3971ad010001	\\xd6286554bded657cde6af6f7f40a3574b629adad1c7da7726fb08940b4439d18654da92e601e2bd8ec3602b1f34d33cfb241689b456f41685a86c96134fbd507	1665327041000000	1665931841000000	1729003841000000	1823611841000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
376	\\x6fd3dbfd62bd7ba0a617219920b47481db32972f3fcb55944772864048a7257810ad0de44afacfe53feac524e817e23c7448ce6a49825025d8a556faf12646a5	1	0	\\x000000010000000000800003d972c39cf27bfd90c667c8efc9bc7b36bcbe9ebeab3aadf58f751d69d12416ad94f4a0252ae4a4c122118ed1c8d029a3a25b539a1d2fd81d45d7ddec09dd5862160262c0407113de73e50876a37831a72a39350dccdddfb1f9e26bc38a0ffe992d0ff8fc6cec95a26a74680b8f9c52a00be88b4369f607b1944fe86d01714bc3010001	\\xec49a5cc718e97944a59d093411b5cd66ffac246260328ab000eaa09f605f07cc34ec52369100f80513df16a717d6a4945fa905c86ffa671640e2f136e2ab60d	1673185541000000	1673790341000000	1736862341000000	1831470341000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
377	\\x6fd78f6b9eca16867bbc4e56d422c70a140dc50c58003b8f14ec3f2974cc7c4f15584eec5cbbaa3d935d3113eca0280f04966b326072951613baa195274459a4	1	0	\\x000000010000000000800003bf335df65511fef3615112220da18e9d16e0eed578d51db1d1d1450555dedd51f4a6df70eef0afa3a3d90771f1be47f8281e1ec0b79d0e5ccf2d27926e65bd9a0f56b0e5624a8db84bd005ab9e4f3ea53083856461132ccc571f484bbc08921bca495ea2de21ef68e8fbb9a1e668d8a89bb34aa4687a408cbcea0ba2352f46a3010001	\\x39faac73c24b729eab885a81ef55dc0c32a491ec9e49e20a2c54a7fb27d5189af5964c3a33104238c5cb50176a9fae468cbe3450faadb835328aa950e4212308	1661700041000000	1662304841000000	1725376841000000	1819984841000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
378	\\x7087106a0a42bf17ce03674c26e6722836ed0cdbfd92677ce90b3cb06aba98aca2c78f3a818eccbfa71e0bc10c53bca5ac2edf46c550133bc69f502fa16bbac5	1	0	\\x000000010000000000800003b351d2ef33f18125a002f825fc757faaabf63010680a6726ff2f9ee663d7dbb0df424d1938c11544909ab55628ad95cf2b94a99a0376cbfb3c4321cb46d8b1e181626003b4189ba7c6c59359176b885254e3820eecf5af2b5fb0c771e183c01746d1ffada913ffeec6c9f5e04705004d2e024f35bcfedb2a058dd587c5bdaf17010001	\\x5a94a482adff76c2ccd2d386aaacbd21a38328636049c90b8919c38316b7a31959a2c30bbc209e1990b1fb5f4e48049dd2b688aa8967b12cdb1c9622abb27505	1671976541000000	1672581341000000	1735653341000000	1830261341000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
379	\\x7113e680c48f6317c4b49b3815fa210aa5cd0d11c0f91ecaf1767dcea852a46c8fa422f0bd7a42f47c157d87f1b5e4e2fccdda36af987643a8e4b934ca706ba5	1	0	\\x000000010000000000800003a51302535cae8919c5fb7655b5a180111dde773419c25db3cb8fc9ebe0847e0cce69a8106ba5dfa445fed23d73fe0991b7a9858faa5de2ef90290ee410539494c3af961301d23d413d7c9c48f4ad3c1d6b3f7d1f01c17cdaa95e9f04a8c9f0421be56c8e51d2050c4dbb6daec51a2e41a4088d0e2c2731927e427f57aafdcb0f010001	\\x39aedb45b658d02e3bdf8646010e1850085c1ebfd2f1290777fc2429a5b877ac7cf07a7d40d7817627a3df4168e7dad0de39deb015fed846b5a52d9c48baef0c	1682857541000000	1683462341000000	1746534341000000	1841142341000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
380	\\x74bf97d401e3d7ebc8327660090d709a3a45621a958115a010153e053e568c2175c9c2748b5938fbdc46be09ebd4ef33165c2c74aa00ffb378ac8ee1339be668	1	0	\\x000000010000000000800003b6111d0a0e82a10cb53324a66b97e529781a5ef1e656babed9027484b115987b5a67625631675d3ff6661cc8de7cff777e3dfcd676707e1dce88736eecc5cb69bf5976bb4882c02c13dd1d26c25f96385f41e814fc07f02180d5023a3d60b4fd331a24752173c019912e7f9a16e57eff775af734160fbf557eb2222ca20146dd010001	\\xfe1ca6410aca36d9f11ac0b4cedfd6ab970877b3ce2c3482ca5875def26b4343a2a97ccadd95734e96936f6e2da9102b68ac0ba6199cc820c3d18c42dd16a108	1688298041000000	1688902841000000	1751974841000000	1846582841000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
381	\\x749f3ee1bbd839228d845820741b17ab5fa5014885a4e2735b690456a960c249cb0ae0e84e5ff87df92704944473953ecfbc3f6002ab4e0f6aaa177c005cbeba	1	0	\\x000000010000000000800003cd227a0460351b0aea1706f5d0f3f067af454052c0157597204e34ff042a102797b2f276c27040ef0e1e4f3b82a9c4cf91154c84b6390d647525367a74d3b055a1c3fb8d4964311a14421cdbf5498d3c993680f4c41212e93d5413a60608a7558741da38738ffcb025b458a03461d3d0a3034114fc278ecedf304a371f8c0777010001	\\x7d587266fce7996a5ad80ce0a4e36f626892db9ab7ac005543e682a77cddb0f68f9015e0d6f26774ea08df5548e7d55500d81ddade1851e5dd37fbd754d7a60a	1689507041000000	1690111841000000	1753183841000000	1847791841000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
382	\\x7be73e5442a00a816fa90c117aa98d30e06acb555754505115733abcea522a2c641af48155753336f260e64efbbe7f62621b1e370fbf709be793d9a34f4fdf76	1	0	\\x00000001000000000080000396d029b64e66e07db63cf4138b1e2420eb255067e34fe155b4e41f17d7009fff9947eb2cd3bb4be657bd05e940629137ea73ea3297f230720e36664af708ae9bd8fde906435b73f8c30feb390ae6f39fe570d2d678554e87fce43e0985717fee9e62bca81ab97421d0bee48f099119bdbcb1f80be20e796243214406b4db3ab9010001	\\xcf40762b9281138d20258e87cc3ab915726b319c8c75d98e8ab2a9056aa31f8bd95429ac962c8c2bbddfd3e82dcafee1182149d09c281721e73ce6f919cdff00	1681648541000000	1682253341000000	1745325341000000	1839933341000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
383	\\x7d23478bfc121c59826b3208d9886b40606914a28b6a5378a291df9aef7686b2b4daa1444789e8f3d9da31fd7449ea8da62a116570ca800a0a4f86b006ab1c9d	1	0	\\x000000010000000000800003da3e091baa6f1a63d0338c1960de960112b4fbdacd1aecfebb8ea02316d19d6b1470437cdc1ef1be331fc6b528355c5798f283199f734e073d845778d2081de86009ce34f3cb494e17ea77fcdd310b998f8a13ca9f57ddd0784330bc25fe8e3223fbd1ce0c31b7c58ea11d1f355b6c29cc391ab491b44f1a8b40558552a07b33010001	\\xb0f9dca43cdc79623ae725bb335f693c2115c57fb6833c39f57d9ac4c625f9c6c4a9fe9fd9cc5d52445e82c219be478d2ba768f4ae5ce0258fe322a7edf29f01	1670767541000000	1671372341000000	1734444341000000	1829052341000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
384	\\x81677c6fc1ab73b1813bbe8cfb7a08c2879da468de45e8b99bc3f7358c90cc5174449e95b9d986584f89aba3fa38a9012f7f579bb7d9691463b87dc93dc43c05	1	0	\\x0000000100000000008000039ecf49d3d7c611f6a7ec15c46daa8fb43682203b393cb6310715e5ecbf0b2971944b266d65b19e0cad90b42c7ac580df11eeeb1dd75bb92e177f81ff235bdfafb1dc3e182fc88d7a0442a477479625e379d9f48aafba27f8f1d9fe5155bc4288b8fb24a0e09edc7c5de71e564d2e6d3c2e787b4fcfbdc0bf5a3df8bf7ff8115f010001	\\x20bbeca40ac052e222fea9bfdf8f9b9bce0f59facdde193004f60d0db1dfd47723ea797cdb747d0f393a631c87e1675c8422e0dfa66491822cfa6bc56ad1da02	1683462041000000	1684066841000000	1747138841000000	1841746841000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
385	\\x81d7ebdd9c383a6f10d542f1cdf6dd92d54847a9761d0b856dbe92476757f8a305b64ba4dce8e0ae24cfd32c8c43979e7ca96974d559973f79c9c26a280ee1a9	1	0	\\x000000010000000000800003c6be89cc1e2febcbd48cb4c23ef524672437fdc10a02d0e389eed540eb4d51daa376fed67c06e765d70be9afeb7a5fe4b5881bef73e75cb9eec65148a4d49370ef6da45e4bd883550b49b0e37ebed4d801c878e9171223cdb818767208096cf083807f95dc9dd0cf9f883fba1717d693b387a839a8a61b414e6133a17e5c0ed9010001	\\x73f0747662d7ae1653135c828a2dd74a54544e50f04b60d3379e193a3cc0695b73043964bb2aa5241a65af9ffe0eb0329cc4dddc32864128d69ee05285812f01	1664118041000000	1664722841000000	1727794841000000	1822402841000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
386	\\x8717871de933abe62f9c9f04646eed2a36a161f3f383b219b3152624c9fbf6c9617495dbc7b089a4543fa45e16133a85a03edaa14ee646041189aa223e2400b9	1	0	\\x000000010000000000800003bc19e241ea8439625f8b5860c0b0f167ed5f114dff6c7e9216698e08139f3171eb3e22f158ce75ddd326811727faeee9e552b19b24aec4f9b1f87bcd19ce8dd9f7f976f3e890e98f5fb12398b94961e48bb9b38dd2bf0165b6169990281fbd514e9017927a7fa9aadbd1ee6c0ee8849c5a06f0238d3836aeead0a9b395b6007d010001	\\xb33828018002c81f9b8ecd8b4f52b6644d49acb3b03bf4962a3d8c1b6e1510d701fc91521d8ea2ce73d14915f57dc5a866c58631f8f508202f424c64b88c5505	1664118041000000	1664722841000000	1727794841000000	1822402841000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
387	\\x8fc324832dca162719da7a94b989210076c92e7a4bfad3340c55bd878bb3209ca2a1fd51daef02fded753028822471621db06f9bfac14abf67b5e5fb3bc966be	1	0	\\x000000010000000000800003ab757a621dbf652a3726755fe5f698c54820e0ce8a59600addeb4cb66c104c2dc4666215f047fb2f5cf809301fa03835883ee0d41b9db84e03214c36b31eb275890cc6c46a93714b2116d835cb66861596578c4d72642fdfe77b2845dfb21663081a9cb23779f4ae70d0f03af8592c05c331fde9ae17d064534da32366f548ab010001	\\x4bee79775d542c9c7b4cd20444f8b189470d4be5a3d7dec2cdecf1d099dfafabd07ab5eff99c37d39b56037a70732c93552bd16386655fdfd730b351776af807	1690111541000000	1690716341000000	1753788341000000	1848396341000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
388	\\x8fcf719f46e25867d040c89a210a7c9df16a6129b955832070f0abe2e90a8fb6847bcbe9f5d4b6ada175ab89b32c433f8e5cca9142e9f0ca26482c1b870f36a4	1	0	\\x000000010000000000800003bf17f2d5210c3a65c9c6c86d2cf1cbeab5ade2c05854cc826a28b747ec3e4083fdb41aff45e7e812bc529b15508f7878d0655c843cc0c3eaa9451e2ba07450cf92ded77009dd3b08004ca634061c97503045d703cefdc9087ec49e0e9b7a8fc12a28cd043eeb3976efed879aa332c69f9e76e93ca58f1ad509d227c46465001b010001	\\x2b12e6ad45356e93e6f83f425912b5f28ad79d22cf1675723dc387d144d6512519c4b196bcdf458576134d533d7fcabd480f96147ebc70847c955477f08b4c08	1679835041000000	1680439841000000	1743511841000000	1838119841000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
389	\\x8f136bd4dd9c6530d6bc4fa78b102cf1b18e9552556281ebb677118bb75da72a2a785adbe40e4a637738c90f4a93f9d359cd2b19fc4222dea3cf1192b3843cf0	1	0	\\x000000010000000000800003db38d3b5740532d53d1f01f1243b12ad6415617759ba78411b5ee889ad17316a338a9cc3b2971cdb5fe33177583cf7e5fcbb45a26779a4f7409861d551265ab39d239af939ddd4d9d8baf62c6ad8be145c7c37acc05c847c48271a2d6b038123e8e12cf66421976becffc5d55a1d5ff53d4569a1aab933573854a64a6ad91195010001	\\x74a1d2693ec8af2a9044628e82eecbb75b69ce249c1fc985753afcc88f79a3017199c02966489e54bee9640463745f4e8224f2cfe760bbd66e809e02605d280a	1679230541000000	1679835341000000	1742907341000000	1837515341000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
390	\\x91178e93d43134e1cb9801c8d6e3cb6d323da776ab8cf1f92ad30ab3596336844dc5a04e1ef03007931bdf8b0e5555aa98060204bf6a9a48e84ad45a93a3c2d3	1	0	\\x000000010000000000800003c0d2b6762363782fb56c661416e702a4d604283853cafb197f7d7e48bf1bb3e7e285026ad6fa03e2d0953ddc1ef6f844d7babbedc5241ad8a5c5885aee0cebbe1b65a65a34bf4ef72e06c049b458ac47adf298b23de05cbabea2e5c271b532a8981798f84d6400ece2cfaa75a3b22946774fdf6626cb35308e0592e3bdf20ac5010001	\\x1cda3d991055b452f93d629b04794bc26bf8e34454f138896d8dd26931f923a6e68383e8298af2eb3b5c00105a8a03578b5d4270e71d11c1fbae34b7a7fe8902	1676208041000000	1676812841000000	1739884841000000	1834492841000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
391	\\x95e3dff9e5b4ca6b9c684dbb91d490a21ed35147fefc59891a2eae23444a266668525d79bd01465f282fdfa653b452ac20de1abe78a0ce2153ae40854ee76de3	1	0	\\x000000010000000000800003abc91c54ce83f28cad2bb7ff5764d5d1e24fe22fca0f3a26897b5123b4cf2f03bfa01a5b9f37365827446c4975c49699d8232bd941e931e807ea1f1585796b298a9c9ead5975c1d9a7ce5ced975a93af95163e12e8fded33042163a83fa698a56a886d660104d2c9cb2b2eebd58fb03247426881b3263b451105907afdd301d5010001	\\xdbf51ddb9af63f24c66d52c7ef866107ec64cebfcf558da56ca612b485fbb7ec4f926e411330eedb5daee15aaacbfe8b77f13102ccf08a845b214c0a8017770f	1668349541000000	1668954341000000	1732026341000000	1826634341000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
392	\\x95b381cfe59b3c500c2494ecabc006d99672f3d1c46fd11c50cba7496973a83d22447f3d1a49031dd553d2a71e71594c1fb279a1e44ec2e903470154129e9e0d	1	0	\\x000000010000000000800003c1593e19366308fffdaf5aed62b81e0ff0383cc85de30ca336c2446b34cf6906d326daa12f1313ef565f2359460e875cec8696ca517e6006e0cef9c0ac081fdb0fbc3dc1454a12c7fb8e282a6562b1f02bac35436671920bb46ccc8885cb1b3fdcbc7a750f93b571c7f92d45b7a1b99e5307deed94bfcf64bbec49b65eebc4f7010001	\\x91929241c21dc5f0c981aa6b0faa0cdd565e38799899cd69d98393cff8099ea5595450ebaf91b0f866601452e4887213c46eaea619f084cc8c42fc60fc05580e	1669558541000000	1670163341000000	1733235341000000	1827843341000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
393	\\xa18bf7b656839bfef213b86360f0233d52291adaefc60f94fa96f99fcc5336faa0cddcd89b8d99b7a9e859f933a3b7780c53b83f59f67ffc5ec9c3ef1dd2fd0a	1	0	\\x000000010000000000800003deec2c6e8a1e909bdcd700cf918500c23294fb2f62452e0e53f33aff47a0eb783565c4908c48620fd8bb94f223cc4f4720238380de3e4989f1204fabf5a4fa322babcee27bfd5eb54663262dcb1049133187681bec087c7a0389235560c220ce2cda499921d9cbd17492763ef9ee4aaed1f9a3119f5da3767f67a3dcd09c3973010001	\\xdd3e2b7e827dd63d3c1c03e39fec7038b3e0fbffb2c05bdf32b8e4d397228c459f29a94ebe2c734ba50bce3af4159872e76f53fa3f0d41881eec39e573bee909	1667140541000000	1667745341000000	1730817341000000	1825425341000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
394	\\xa647f893778fb1f01d9d46986e05113dda6b5d12ea35edd18434fcacb1876d3a220e6b14693830d4de5588d237f41b0e651950b8ccd62e122349324b43b41046	1	0	\\x000000010000000000800003bee57330ff13f6f096348bdfc1ecfe1031bfa00c62242f54669bde57f44447ddbbf1b1d5c63f4c2a9f6ce42c7a7d553149cebe2c5d2a7e2aa7e6be06f099fcb0931c33c907253deafe8e423936fece87cda9f3a66ac68bfa861bb398b94992f1269b9d832177a982945507331627a6fe6b99ca8b07abe5b2ee9375e8a962751b010001	\\xc58132a80388007d488b33a549ac8b29eea697be7b927c854a954adcf79b3db66efa44999662ee65805b2aaef90a410e91cc195ecd5ee918fb10b96ec60b7401	1676812541000000	1677417341000000	1740489341000000	1835097341000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
395	\\xa9437557f7bd87617e3ab752f71d98669f6427c65128c7090d5c3e676bcf7c0c7cce6dfaa12356edb7a510aefd0b22143cf9d09de1b40f80db0082072bff9c95	1	0	\\x000000010000000000800003b400a8a6f5c58ed6969e8fff8db1dfd4975db067e07345eb60ba36c4bfcb79405f2c63930bbf10338c2e179274fd847dfe3127a1f6772e6fc7014b96f57e897ea90debc362ef11e9c8d0f8572ab6fb534fb07f639af4c54a246032f58ea7f846946347162778aa40a06536d860a37981ad5ba8b9ba4324799b6e485686d294cb010001	\\xf082769dfb8143ec410e68c74ba404d6e14d52431c33e7b1d6e5466f78f6e59a1c446b14d78720b73d98d0c0c80bf58904616535c685d56f589a953e4710110c	1681648541000000	1682253341000000	1745325341000000	1839933341000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
396	\\xaa6bc96d10e8a22c37a59a540b2967bded02d7d0ff9ac7140cbd0d87ec30e2e49de1eb0115290cc5041128fca40547f08e8a4508201a0293ac00f32ed311dd6e	1	0	\\x000000010000000000800003c052bc95bd2f3d468ddbe1faa3c1a1d880431444d218c3c7303775f39ffe408df229b50fc1b2937f18f675a8e63efbeccb1d4e2cb1890479e798497aa61c0eae2d75c5a63dc9aad30fb0bc8af926f6c7cdac94ca5b2788256b0df0efe2a8df0857657235b6a43c2ec1b57be830aac4448f7a1e6375fff35bae321cd8855f2177010001	\\xb5a67551c290541f7fb7729b07dab0fe25ca6f8bfa201f4f0afb92dfe00402b0368a6b9e0a680c065fa56d89cf4d3c78495f2fde6c1301b9187eb00a7fe77f09	1675603541000000	1676208341000000	1739280341000000	1833888341000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
397	\\xaab313a544ebeb63fc2c57de8e47dcb8b04ae5417143bdfa21ed56a4ef372c516ebdb9498c433b615a6fb8e17e2cf5069783c9feedfc6b68a6ddaf708b10d330	1	0	\\x000000010000000000800003aeffbe2bc22a48f7b4e89c7ee18d26e7a9aae4b1ea9873cf736ffc0df82dda40fdbfa88c9a8021ed94a005ab928b0ee3b8e7924706d673161aab1c45101c4858f40ff098f09ab2029acce93c21da34c7f153b08606b57c0f2d6a7d8d231bfcac84f03c51283aa7aa91c97707ddc20dc568cd768348a05e5bf2c6510bac216d63010001	\\x6554a9c44359db574ccd60331ec8b58c6285796fa713b4c5f1eddf14ce6703ccd18b2335db52255ccd680d54693daf49e958180df56184d3887be1fdf70deb0d	1684671041000000	1685275841000000	1748347841000000	1842955841000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
398	\\xabb3a3960ecd7f175d4284c3b79c89196a8d83a23c1020d2705b6191064ee414561e27ac2c92140c73cbdbcb9cb8c06b4b6861bcc9568f558afe68c394201496	1	0	\\x000000010000000000800003d225fcdf695e7af06f6db017f445e386bbf595eaedc5324029ec4b95c38e4809c8019ccf2b81e8698984ca9089dd1998ffec296d90780fc828f5bbe43d223561fe5fd180b077fcf697fbc846b5fed29eee317444799c6973856ceaae20b67ee32623d0fccbfd6603d4e117420a00820a8b33df9028758fcb81fac63f5c72ff97010001	\\x8a79c60f882d18591ab353c4e9f12b4a71d9b1ff6d9ffb3fc5611b337cf1a8bdb66a4a0ff25e90ec6c2d7dbdbd0e635c6b64888e839385c9e4f2555170258c03	1682253041000000	1682857841000000	1745929841000000	1840537841000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
399	\\xab339a57df5f9e285d371a86193b013eab748e5245d41e5378647ede1281a069b92ae5ac0904937b082e51b6a856de7d502c0276fffcf6120a836278e2a40323	1	0	\\x000000010000000000800003b8d15b0d059ce479bde90b1a8d82e6b3af1d961e72bae71fac9155d169340ae533d7fa63b7b24b4c226248ee93b0f2dac84b6133cfc98dc6e4da72d228c01f440b2eb5aa5eec253634a80fa9d6f6ba78df8fecd5614b3ae12f9a8d9021985cebdd1d0eccffab6ffeb37b6752657431269c0562b17cad2c47cc9dd77888c28c01010001	\\xafb951948aaaa1112ef4b9a1f81086431aba9e68ad075bd2cdfe4f6d142362dcde3e8bed4b1bdae2caa877c1ba034c5a60d9ff776713f890c1d07c254cb49800	1668349541000000	1668954341000000	1732026341000000	1826634341000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
400	\\xb197ebcba7877876441539cf3e43166340439a20025c8d1f60eca0545dfb69df23a930cb68f15ac848786b70fcf05a8488126f976ff2dd9cd68ea6db35fec396	1	0	\\x000000010000000000800003c35c683cc301e5d73a5ef184a28d922602114bf0370054b3dee1b9b70e2730950bba964da496a2637f9aa88d94a8d2fd6af95f48697671aa2032fdcd0edfe89f968041889c881ba565c41770c08d935b4cafeb2d8e8d0e52d0b402c572211451e1dff1c5d1bfa5ce356415fb287bd28fceb689e08f4d4f6ce3749f03136d19f1010001	\\x278a9c8495d1db650fefee6b0c13fe162f46495f747721e2c3d8e10b52aaf9e9a4bc1f894c88a714405f1162f8b4ab1994a88b8df66562e45d45a6eab044be0d	1667140541000000	1667745341000000	1730817341000000	1825425341000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
401	\\xb457e58c9f022e83f2ecc05731e5664115f4dc69df60137b6b65d9afa4540ddf8b9bbd498b56a1a721e70d179245151d5c50cfc60d5b964c32a406e64d4e1a5e	1	0	\\x000000010000000000800003cf00ad008c6355acd28017704a695e1abed242c46baef3f2329d8e67dbbfc85f16d0656d90bba16555e3d2cc76f6f620261f60269b9072d4861b0575b193c24d2c9b2b2d76b29f37d86103ed30d8bc8d72aa29362c632826e273ca49308d71337c3ddc6f241cec5b2e355407c020e34659070fd53bf56800ea836f9019b03401010001	\\xa821d99783fb6e3341fba4c60a9a0580cc454814b18edc1a482cd3006c471a46461aaae3935a136ae8c9dac9fbb87ee1e8b2c20778e92a9d42d5b1dad8074b0d	1690716041000000	1691320841000000	1754392841000000	1849000841000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
402	\\xbdf33efe4e024bd1ece80bbadbba7cdc251e92c9fdfb02a0130088b1816d2ad6c7218502fea3b6281918b7425d2360d8ef54a4c670606897b9873dd45c068361	1	0	\\x000000010000000000800003ac16f7dda936b9601505f07a914c95b8943f6aa3fedea3c87d3addbbb27e26df5b99560579b521b91ef360d3d947200522d9dd9fca9407b04a3848037116fed2237da17e9d04ff4ade9850e76f33f777de1e5655efe0785393cc4ad2c01a6c1e97f190e8a6a6e795a90ff21902f73f8c084affd1f078422f3cac57cd5a2ebc7d010001	\\x34f2ee3e5294197fbc786fe2d44c6b526bfe189ea4b86f785ce63597bc844578711b7bf34bbacb72c59c58976f357350df15612975c0a742c82a47013715db0c	1679835041000000	1680439841000000	1743511841000000	1838119841000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
403	\\xc12f9ead7563e96fb5eb20a18d892a1f9b59b04bd958d93e83a0e0c9c13f69284a79d399d2f610ec7ce9c23fff612b6da462f3dbe0d277701aec4e87f4ee2a47	1	0	\\x000000010000000000800003b7a9567d75e2cd25eaddda0d02ed9441bce7013bb2a38ddf5d827f2ccca698dea2a8e5a30c7bd8c3e3327c5bc5ea32227943d0a045ac9179d6ce9dd32dd8bf19b8cdbb1acbf5baffd9ef026b67c40064e785de2f3c506cdf354beca64b36fa5c8ea2215af225e2de4ae0e5b837895dafa4c363d99e1789f3d42671b352c955c3010001	\\xf88b7ebc9e0a6d0f0a84dfb77b155360749caefd150deb8f902f66fc039bac20c8afabde8301c1c0c6323faf168ba70f9fdc5e991d3e57c80ffdb35eb490a209	1690716041000000	1691320841000000	1754392841000000	1849000841000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
404	\\xc41b8ea84269b88087c1ddd47d520cfa081c9183c29a7287bb6cff0e3d06ac7685d312fadf819cbef618670fe1f542f951526cb08a4e8c743bdb3d581b3986f0	1	0	\\x000000010000000000800003bf5d7cbe2abe7cafdf626e9c4cef80fe6d20532382de7162529dfb3a2733c33a6e7992deec60f16be050931349e050f6e1bc9259b910a3f0630a1bc689d9edbfa1ea030eb4e08afbce594e88a343b6acaaf3b5cc0a3f50ca3693deff95fba3acc15df140d2327dd62bbf638f9150479ed71462010329c70a624d8d96667e438f010001	\\xd7faf7867055be05e6afa8845b4a54d248ef5d6311ee72d111d9c1fdf4df0ce336319f11defca5b84e4b6c309888f61b36f86457c75142a4aa6f09343d595e0d	1671372041000000	1671976841000000	1735048841000000	1829656841000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
405	\\xc5ab4dbb845f8052ce2b6fcc8d57afd2dce2aa52d5c9b6e0ab1bb8c4a4d286e11241a71a28c0e1acf12b07c5de53acd2c424838574abf033b8bd8be8596e3dac	1	0	\\x000000010000000000800003d9082c0512652d0b20c32dcfc3e8225d2bc105494968c483164bac1ccf62a77db1d41049818a1d5a2e7c89a770d5c41db768e0c1dda3502473239978489878cbc2d0321a597229b73d68ef7012911b8b55ff228224caf599a90b4b652138a1c12b4b12954fc743d1cb1564447c6aca9143bb9a3088c0ccde6ab0262dc85f7611010001	\\x0a151ea1e556c543fbe16032f374cca241f721fb3bc8910d4867cc3919cc24cfa548afac2f986df9cc1a3fff5fefcf116477f2acab6ceb2d597aacb793d0460a	1664722541000000	1665327341000000	1728399341000000	1823007341000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
406	\\xc8fbb47bbe12dfbe1b4a5633e8b822a0ccbed3b8dd603a48ef63dbb9e8851f4f7be8c9ed284fe785a17c54a51b8bbb01afc3466357f8ae49b755ce23360b06f6	1	0	\\x000000010000000000800003b56338d75d11fca78bbae4b6e80fcbaa3a602066c62942a9dcb95a47a765f8ea528e9e04509263a8d085850c533cbd17a2d4c72d93c15043925d00d1c212ee95ec020285e621985b02020ae3abd19ce9006df6b782fc3e780e058723ab5f82d72b520db27ba84df3bf8d000a4a767cb605a42987a5a453cc93e75af2beefb25f010001	\\x1fd06c37ec317ff2b9f1bd2bb615801b68bf78cee8a31735d2db35de24feaae8da9be328b3b407cb3d6a3586b48256a66a3d4aadcdc65cd33dd7c7b68607fc0d	1681044041000000	1681648841000000	1744720841000000	1839328841000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
407	\\xc90745be8b93e88bd8547404bdca4a6d7205fce4723c6e5b38582f7f96653dc958cbbbd59c178abe0ef3370e79845a3c2ef203f50e644ef30a0cbe91ffb543d1	1	0	\\x000000010000000000800003e170b6d69d12232e03367a7c246a01202b627664f7b0df847859c7acb24e27676d8ea88e7663f28ce69b73bc3c9d6bf195c0628a34b934e3472ff3dfadae66a76c39c632ee056f4f629e786997945a2dab8ea2856daa0396469ec730fa42ee8d36a1bfe31a671adb6ac749347c32a124f7e7825b2e158cd3c5806f87662552b1010001	\\xde8bf8c1470a2c658c5a199d3a2ec0d91db3eace3e1575299a21e7c47d4c0f74e4b1dfe4ad85566f7c39b142a4e78ac1a1704a6c37e3d51a103deac31cf38506	1681044041000000	1681648841000000	1744720841000000	1839328841000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
408	\\xca578de50608695dce443eeb801768154aa21af17d976161791488d86733a4bce6a01da18a11a8af43747e1bb20482cd24a149e200c4c3a1ba41b5b24ed73a5e	1	0	\\x000000010000000000800003bee8121d2ee9a0ec0ecd514466c47839fb555d85c70359115b85b6300e17cb63cbdaddedf06fcf220497563bcb241829f40c2ce7ca1e4ee19d5f48bff0a0d21689b8914b033be834f9ae9cc26f2f194a8789fcf84448433f3238399aa612f1347226a4ddece04206c31ed97283e4e911eb248306ed2dc30474b20688599a89f1010001	\\xe6164830829fabd21163d02e124a7474411f8f361933cccdbeefcd8820980ad19c9f4e08c6e1040349375023eb2aac06f309acd6740b4604e3465173ee0df30b	1671372041000000	1671976841000000	1735048841000000	1829656841000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
409	\\xd2c3654d6099e896fa82695e0bfcee9052cdb2a12a8af2ac545da26a3683c56d00dbfc412d69bd5a000f48955d65959e4a33d394592ec8f5310035d54ba5ced7	1	0	\\x000000010000000000800003b1db97ebb7a9c8a0a9d65eb6c8e9c2cfab68dab5c2965208b22bdecaa39ea1501d5afc66e7746d5f1511b958b63f3b1ada30b48300993f623d7c39ac8d3a899cd12516be2c0a9611f0dd9cf05cab23f365e8072d5e6a22df19754949221da12241a3abb90cf1fe17d030aa7df871854e2599e3aaaa57adb428c2ae2451c823eb010001	\\xef4d29308e2cc8a265313cbdfda739338f0b73ced2a0434af969c17a5ce56259aaf1b66f49aadc0da0da2c194b9d59381415b87c77e1875f02e4a0615ba6d704	1671976541000000	1672581341000000	1735653341000000	1830261341000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
410	\\xd2efeb7e457cb0cebd8c5451d6b5c66dff794e2ea71164a3ba212c2482b8bec7c8092a23d28f156bd4d8e5506e0112969f7613d6ec024f3f1d89c62cc0834bc6	1	0	\\x000000010000000000800003a4451e76446ef7cc49489a611fb4ce378481aa69499a4fa2b42538e6df8afd3fbca26fc7ba21af6e89ee674fc9221a7ec8e2a1d7b07b5c61d59fe39ba918bae745c05ed75401af7a11cfb01c4b05433ae9a33deaf0e01ae99150127a81af62158353bfec8107e3283026e192fa2d54b955d23ef3600986860470b70b62e9e9d5010001	\\xf61970756c8b54c2dc9d5ceeb21fd30903e88044f989af06203ecc26d7f544c4774ea4ad4a0bbc7d68957659b719f39a8541544927113ed484b089c1d69e9e0a	1662909041000000	1663513841000000	1726585841000000	1821193841000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
411	\\xd54b594dd1f6c06e84615a7495a56c09c3187813890eddc0f7ae9bd919b7357d507de65615423f56f1dfdc909be13107697c5c0cda4d92a2da8a64f44b643e3b	1	0	\\x000000010000000000800003ca49f3bf0cce6dffab1e08376bbe8d95669200d8613b25e911b0aaaefb89de5aece90e0e312e2f9589f0196b793616305ba2db8701a0cc0004beb7fd7fe486e477405e0185e559f9e03ad97ea4fea50e0b4b003dc97403a1753918de7b981a6ef70c6400d80112f9771fa079c3e7db2c5b9d375e171a0729e902ce794b728ae3010001	\\xc975edbca30588a1694ba45a11012ea48197efe3f7b5b8f208b75c3789b53397f9d7271f158a98f37347ce97fea0a8aec27fecfef44b1c09cd2d4839e9e81f09	1662909041000000	1663513841000000	1726585841000000	1821193841000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
412	\\xd6bb3275bd2bee487533bbcc340b3742937f623572b15717279a4a0090429dc7c5a0c1dd7f2873f253ce7e6efd36ab156b2275df21bb54410897fb03c5ae9bdf	1	0	\\x000000010000000000800003bda5d2f400e34364c8a62d4d37d90d61ff3466ce39f8f4bfdf6241ea12f6780eb11fe383eb113f3b8683d8f5e74da640b1310891ac43dc09ccea1e28c14e1b7008b92fbad20f51439950744218ba5e97c52ff57be3f2443bfdc2d8aa00759c4d7603018ecd3fc241f8a3849c03c9d1a5a26c94ad2f87777967d4339a19ec05b9010001	\\x732392a552ee95375a16bb7b551153c28e2f5497f0554d21227ed75d48bd60155eda7d019c3069b524c452bd914844a0a6b4be2dfaa3a189da03790af68aa90e	1671976541000000	1672581341000000	1735653341000000	1830261341000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
413	\\xdc57464356d2b929e48824a3ef91583cc634eed013cfab387028edc8b3763759b743687673cb723c84a0c90ce7c892074855eda54be3876e7d58cb881ae5b4fa	1	0	\\x000000010000000000800003c0ba57896fc55323af57e19cf909be75487c9fc086de92a4876d5de2ad5d23903383f96903879ca1fa0444aa759d62645dbf5d35ba1bcc9a4abd233f4a0c778cdefd9f104165242f31fc1e0b7e2688ce09d5cbf75e7c3844ec5a7602693b1ba5a24b96f1e6b2546d397efcf8f0aee2a1904f59951bad6efec0614ee4bfcecca7010001	\\x21c553ca527794894cf06ca97df8cdf66fa85eb71ee51165bce35805ef6bb0a8a4c416ba14b3f45433357a787932bd370dd24bcc313f902db5cf947603d78f0e	1662304541000000	1662909341000000	1725981341000000	1820589341000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
414	\\xdecff601aee8e1df7101866d41bce32897aa377b0c46e497162656d111f7d47709436c6a85429361e5ef322e38456c631f566e9d3bae07cb3887d38f9d6dfd12	1	0	\\x000000010000000000800003d56d85264128e30b35a836606f959b7781bd0ad062f5cd17b1257b9560301554884db701b637e4c428adfc896b8fe0c41016d3acb7d4f969deb2927ef27651d396b8e60932f29ad52b40fee35035b2fdfb0cdc4cb6c802cfed62c849a481d59ec481e67f399f293967c65f624b6ca997373b13259a815d2179e378c9826c2413010001	\\x454bcc1412700040f7aa7fb77599fd190efd37ea1e8deaa1065ddf06a7adda86d4ae491400a989eefd3ee4d754760f0e4f13651912c4f0d7aa571aaf3ddf730f	1678626041000000	1679230841000000	1742302841000000	1836910841000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
415	\\xdf33e1959644c244983703d2ecfb58170a4a3374902e74483d61d6ed42f5845ea95c804f260ca66d4002bd5bcf3eaf40412ef51a57fe9f49e52ce3360af9b53b	1	0	\\x000000010000000000800003b762d5fe9205413a03d36ce7634370e22f0194e897fb97bfb9100c22fc02a1f75d01799cbc6fd284b2a8249e53a4c7492eee03360a8aa886bb251fd4fcf0ef426eb1decb721541307c19fc20abf8d23ca1ffa7d63f8df0bec5f866b9e32c75933089227fe12b608f4d72bbf7e54339653079a3b744c5075e633a9c09b559d19d010001	\\xaabd3b646f5866e42d3917789957943fedc057c9c58265b362511ef324eabe443e937e183c54d72dd98926e3c4d6bc985f9f2929ed2dcf4f03757232ace4a70c	1684671041000000	1685275841000000	1748347841000000	1842955841000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
416	\\xe103d8f34c5ed4914e4935d2746b1b2bc1f28fe6a376de434c6665454c316045af6a754e5332cd307ad57fb8d049369310c0c920de2efb6c3be523e1a5a89273	1	0	\\x000000010000000000800003a0dd617335c81a2c6ef6c11a23df685e3311444dce968388f3c15d12462aed18d842008ffb64edaf757946c084df5428b1687ae046914ed2b27c4d857876b5fc0aa1ebe19a3ede9f5ef5d84fd7e965ef86b5163ae2d32957e5e30ff43108f0c428bc7d82aab070595c5f587ecea50ed5bb9d17a5e2dbccf2e75221ee87afe719010001	\\x0e94af6d114b9b52a2fb2f5e8bdb07ecd62b8a2294e1b1ba04713b73409a4a3466b8187fcdd2faa53ad537fd39c5f1b25740345b261d885ccf84050699a8f60d	1665931541000000	1666536341000000	1729608341000000	1824216341000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
417	\\xe2bfa7d655838cc19fd8cb2cb011c80f71865c2fd5a868c9a93a7fb17b5a0c2e9babfb4edef6c2e9da7a10c0d597e21c30d2eaa906fd9156611ae2c896649461	1	0	\\x000000010000000000800003d132fda8b74883b429514bf07ea6ea599ccf269006ea437c0b496b6400c3bc03a99ac71c8248f81dcccaa9592934bca0a03845c0f49bca94e346a0d044c6338260748bc6a0b362be17ac1fd5ba846cf65eee92ff31fcc59d3fda3ea959e0d73ed4cac91975b7cbf3a3deb4caa92863ef07887a9d3c3a7407d432f2c32b8e1329010001	\\x9832b5519012d4e2946b39d48f83129e9e6c19ebd623548179a22a6059800ecca26243815eb26790ce19d50ea48b9e42e950f29231091d3fbed90ea51f947d01	1686484541000000	1687089341000000	1750161341000000	1844769341000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
418	\\xe25fd51617a69c111b42b79bdeb8370dc1f0ebf602d6f3f62c5c6ed018fc32f6e7407b6b354fc494ae79e062fe3c11515b28203cb238639a3c259bbe5eb5f9fd	1	0	\\x000000010000000000800003c5640ce20c86767a47942a16ed649a23c68f31c8401c64bc39ae82d1e9a8a6fb7706f76531c50394452f864c18311c1f3a53569c3ff4b5265d08d7f981494de1e7c44a4e0a7b05ec8af1853d31902e2b3d09388a763156819227eff1e3da5b4d5424dbad99a6aed32ae27d4b4c4187800bb2574671027352c91bc8a181c3f5e5010001	\\xc9b2a443bf18911442ed6fab216a9b3ae9171838faee525aa79e188a807064492547c5000351dc123c63cd0fc043df256c9a14e291007d801d147401c8d06603	1676812541000000	1677417341000000	1740489341000000	1835097341000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
419	\\xe66715b84a5cd04d7b2a3973ad977aa26b0a219885a077e9456b2844effdaf54d67102b32ba8ff6d203d64d4f4b01522bcc0f53579a072557c37349dad1ab4a3	1	0	\\x000000010000000000800003bf4510ab005eec07785fc0931ababa5ff07a9d1e48f2b3702ef6c057a6110fa11f4573aeab1969030c0da99f4fc9eb03dd211da6cc556927371fed55608d4c0071740cd06dcc4c3f5efffc6d8e5df7fc93c548ce9aa40d550469f18b854b20cd817f99e0fe2cc8c33468e6a71a80e72e4244f5966ab94553a3f2bb81195578ef010001	\\x32387e7e4ebc5c632c8d4f5585ac5b88aa4ad5209890af7757c46c9528f8baaa8201e7e6a255e85571993f9a090485c5bdcfc52383e66c184e1eb2c3a78aec01	1672581041000000	1673185841000000	1736257841000000	1830865841000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
420	\\xf16fc10525786f8b81ef19c369cab7b4a27703dfaa8b9f8f2fe362045918804e6f0ac35e488c5dc0a039f5d2adf73eb25ed1f38c3f91a75ce0db49da153d6bc8	1	0	\\x000000010000000000800003b7bed15e9c65e9961c4e1885109cc30c48dc99c009ca3c7a6f3a8b8057860e0564ffd071f1fa855a6835f0f714add4967e0bfaca836a35d4f53fcb773a8622dac71cc2e36eb0330133071d0833ab0840405ff1a7759a41a8ab2e67225382c718101f3d724ff99444b058a1110a1a0db3a0a8dd08ce5671b893550f36cfffc2d5010001	\\xcae2cf3e20e52f802cb71beb77b62e59c616c295158237603ea03de72cf27dc520060e2fab90d0e0334f46ab970c655e30d772126dbcef1249d373b741fa7803	1686484541000000	1687089341000000	1750161341000000	1844769341000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
421	\\xf2e3f22429e76f4a014cc8d6f70c24b984ef6a6c502d5d79f58a877ef50eca7708cecf076c1780ecfa672f4b85a128fdac27324b18c50612e6583e853f80b76d	1	0	\\x0000000100000000008000039b1cae5483c82dfab2c6bf896ceee36e2e146ccd03ba916055de9f63cff8b11aaf82a72c4c51e8e4719dd675e494951c4640021bd0d6b020dc37d9788c5e053c31ca3679fd4ace9d442f0474c240eb2c95c435c67ceda43939a90529f5fc13ff1fc70e55f0f82453cef648c80a000480fa0274028a5876fead13644db2467bc1010001	\\x36fba64033bab136165a4a94218029f29cd57cd08a676e43b97479702467b344c9018f347b25f98772cbde0879e16a56a2202bbd0284300aa6bca9f1d44be70b	1672581041000000	1673185841000000	1736257841000000	1830865841000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
422	\\xf2a7e48c3492268021f5e2ae5f3e1bdf49158807fb4f1804d319016d5129fe2a7c16b45226800a8aa32f5c1e7fc33b02bfaf6330d561fce375b7842c2fd3af6a	1	0	\\x000000010000000000800003dcad2ebcdc4953ae1250c1967ff122b5ffa0bf68709a2da0318d8d7695e489447e00fd60800b64ba3c6ccc6ce8f1326a051e7557b059a51c000865d42650a008180f150f54f1fb9a9ca124ff3f8ff6f20d9832d105abdafae3475ccb2d9d80fd412e79a82a08438b9b09ca1d6fa88a50c9ef2ae3633188b369efdda839e27373010001	\\x61b1c875dd2077f0c6a9ba3d6a87a252f2d0ecc57ea16555aa7eaca499d09523548f7e8349807c359a84fbde5391e51d85ab4ef43ca5cfc19b29e122ffdc1c08	1668954041000000	1669558841000000	1732630841000000	1827238841000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
423	\\xfacfe0e76b6078e7c68ca3e86008cd84792f58b93a93ca4cdf63f2cb7fd99e98717800db65fb8c56335c768aaabab51f9aefda2ee21c55fba024b1d0d66c561f	1	0	\\x000000010000000000800003dcd18025950e69403a9b1e35c82745357cbe051c93147c0e983ad4c561e604bf998c5f9d1200cb3fba7eba771db5d302aaf38e972315b21af58608ec3ef735f534f99cfd177218ebf18ab73bcb45b3328dba9843ab362b4aef4f9f8fc37dfacf6740fce94617922943566deaf9d306b3591c5cad155c586020aa8a07b8d17f0d010001	\\x603a81c365ef5ea6fabbbd6829cfa10c33806c972b446a0b29995970a1b7d8e7bfe357c0f873896829aa74b97f34c8ac72dcdaa936f11137700b691771fd7b04	1664722541000000	1665327341000000	1728399341000000	1823007341000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
424	\\xffa7b62a176469666a0da9adee1c8210f81c39ed3b059a1afe68d0ac2af298989f98820fb4922fa5ffb3d4cf2f693c5d7bccff33bbc9b2da00e3b2c6be52a34f	1	0	\\x000000010000000000800003cc33d0f80c35396e0f6b0e7155a34888f853c58fff12f54777418c16583a4afbbc937a3a2c104f810dcd835dd5eaa6e0d8fad22994b344cb26685bba1845d989d5ecb992e942a9f2a43d8f111355c32593ee203f8ed0887356a97559d3188a6059b03c70d4af0912c909827d3f800fcfecd7effe1712891ca2d6f9e53c4a3043010001	\\x783855cd0f4c02c4113a8838cb6b5ae0d7960c610fea1c131a49e3c00701404d203bb3f29f2927bab65064711805188f3d3d252902515a4f4302b8ddf94e3602	1678021541000000	1678626341000000	1741698341000000	1836306341000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\.


--
-- Data for Name: deposits_by_ready_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.deposits_by_ready_default (wire_deadline, shard, coin_pub, deposit_serial_id) FROM stdin;
1660491957000000	164843509	\\x93bc00543ac62e3bddcfc7f9d774a144366080c86abd5286a5901bafc1645a80	1
1660491965000000	164843509	\\x97c9d64d2343c7b00b1ad1f3a9baf4647b72a8ed358a7ca098cc04cbaeb80a22	2
1660491971000000	164843509	\\x336f8a0de6612a61308d2b4c759f3ec350ce2bfd8dc31fd6f1f097bdd1afe9ac	3
\.


--
-- Data for Name: deposits_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.deposits_default (deposit_serial_id, shard, coin_pub, known_coin_id, amount_with_fee_val, amount_with_fee_frac, wallet_timestamp, exchange_timestamp, refund_deadline, wire_deadline, merchant_pub, h_contract_terms, coin_sig, wire_salt, wire_target_h_payto, done, extension_blocked, extension_details_serial_id) FROM stdin;
1	164843509	\\x93bc00543ac62e3bddcfc7f9d774a144366080c86abd5286a5901bafc1645a80	1	4	0	1660491057000000	1660491059000000	1660491957000000	1660491957000000	\\x18e94bb55d36e3c6ee4466b62b874dad943ac8cfb08f34a0e038aa103fa68234	\\x7bb482ff31e4c110c5df76992783d436d27502966372065e8c842c869146d35bd2f01c6fae3c691cb7697d3385c6d57d752233c0f0c33e6e92b78807673746f9	\\xadc6006e306c7b65acffeb3d6c0c9071e05ea65b28858f200a9c77c7a8fae5c6e29dff4d8f72413f6d7e60fbd15ed64799aab66dfac62c68a56436969d066b0d	\\x07113881c944fbf4f103ce7aa7d7a571	\\xd31e3f48cb5318906dbbb7948326362f41604c7a728323230ae82aa995f27400	f	f	\N
2	164843509	\\x97c9d64d2343c7b00b1ad1f3a9baf4647b72a8ed358a7ca098cc04cbaeb80a22	3	7	0	1660491065000000	1660491067000000	1660491965000000	1660491965000000	\\x18e94bb55d36e3c6ee4466b62b874dad943ac8cfb08f34a0e038aa103fa68234	\\xaedc874f4eb27cf94b0e7d7411c7b4b8d456fce3356cf458db561dfe18482da07e2ac9d15128d32d4ec20909b3e73577e66cc0a80cc3f12bc25a78185a22b498	\\xe92b5849e074535a3b67deabc6e3575b21764a6efbf5438ff54a976548719c4173607b475333dbff7eb49974e289457d4f8eeadbe77d9bf8c52c77b35fa7790c	\\x07113881c944fbf4f103ce7aa7d7a571	\\xd31e3f48cb5318906dbbb7948326362f41604c7a728323230ae82aa995f27400	f	f	\N
3	164843509	\\x336f8a0de6612a61308d2b4c759f3ec350ce2bfd8dc31fd6f1f097bdd1afe9ac	6	3	0	1660491071000000	1660491073000000	1660491971000000	1660491971000000	\\x18e94bb55d36e3c6ee4466b62b874dad943ac8cfb08f34a0e038aa103fa68234	\\x12b6d6092ae75562297bceb4d44f4f7f788b39c141b5dd1b4e725e01429e32d2b6439bee7ecf1f31d95a5e871f2b36a0ee2141f8339e38d56bbb9d9016185aba	\\x4d6e7c8a7a52b63c4936961523a2867b6b6339f787c04eadd85e067612dbf183125e4867494387994f462ee12e9d623ce0837400e26e8be16a703d6b0949ca06	\\x07113881c944fbf4f103ce7aa7d7a571	\\xd31e3f48cb5318906dbbb7948326362f41604c7a728323230ae82aa995f27400	f	f	\N
\.


--
-- Data for Name: deposits_for_matching_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.deposits_for_matching_default (refund_deadline, merchant_pub, coin_pub, deposit_serial_id) FROM stdin;
1660491957000000	\\x18e94bb55d36e3c6ee4466b62b874dad943ac8cfb08f34a0e038aa103fa68234	\\x93bc00543ac62e3bddcfc7f9d774a144366080c86abd5286a5901bafc1645a80	1
1660491965000000	\\x18e94bb55d36e3c6ee4466b62b874dad943ac8cfb08f34a0e038aa103fa68234	\\x97c9d64d2343c7b00b1ad1f3a9baf4647b72a8ed358a7ca098cc04cbaeb80a22	2
1660491971000000	\\x18e94bb55d36e3c6ee4466b62b874dad943ac8cfb08f34a0e038aa103fa68234	\\x336f8a0de6612a61308d2b4c759f3ec350ce2bfd8dc31fd6f1f097bdd1afe9ac	3
\.


--
-- Data for Name: exchange_sign_keys; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.exchange_sign_keys (esk_serial, exchange_pub, master_sig, valid_from, expire_sign, expire_legal) FROM stdin;
1	\\xa4add2d2b5c8483fe42c8f4117b9174205d51eeae03890a9caa0df4cebe85bb2	\\x11954245d38fdc2b3685b11a5e0eb4098c99af6b3cb93bea887f67f8624b8f2cb0234c30f457c08075880a1f1e0aea30cf2df2fa5682f51cda854fd0bf56d608	1675005641000000	1682263241000000	1684682441000000
2	\\xf1393852d69f2e4ba6685d4c4871fc86cf0890112eb792098f1d189cd462aa04	\\xeb009a00a47b94dd4f9492eaadef2b47eebfca8b69377292c536216c99420776b60da0fd5afe4646e9610f6a55e924fa3e0ee59bf3a66a9d7409f04a78c54907	1667748341000000	1675005941000000	1677425141000000
3	\\x53bb828fde927d2164092835a5544b8897d7a5920fb83e1c6a906caf40d26767	\\x568111a2e362807abc7357d7d07b0472008afb20001a1952563ea20b9802f3dac3c87f288a8320a9a4e423db027b351d612f73c510b72b8c22c68b9e3f9c1402	1689520241000000	1696777841000000	1699197041000000
4	\\xd4603c590f1e51a911f1b289877208db5550687d77c4c212b6a395d1bf3d385f	\\x832091a952da688dbe9b754e1dc52dbe3bfe826534ef8a8ee8f4203c317c8819c022b98d706f849c3af234170a67d649648601136e798fc4ce46d97db35cb008	1682262941000000	1689520541000000	1691939741000000
5	\\x984c4fb720a52825c61287a4209ef9613b83d64899a087cfb8035a087a06b956	\\x57467a297a789c5cda4ca565d93fa956cfc0d0cb8cac9efe16fbf59db5659836a17197738a2085d558cdd392c2c114955c7c91e5d05957f5c4e96819783b560f	1660491041000000	1667748641000000	1670167841000000
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
1	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	0	1000000	3600000000	3600000000	31536000000000	5	\\x572b7260035691447382b47c1932fbef83895bb28156335ddf9e3595e5d5b4429aff226814d626103e3c92efe03c84cb0d08bf5e025069aee21f06be728e5f0e
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
1	313	\\x93bc00543ac62e3bddcfc7f9d774a144366080c86abd5286a5901bafc1645a80	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000572fa3668353b2671435a18130f089c047ae1866944236a6c6180342e613b5ac8332085c490bf802b1393f24313495556e92526b0cc9135edfdcbe17ac0c5985b0de086dd8f1f6c8a0808b59ef4069963880a90c5400b41d204525b543a28a3797b4658c8b4f63f2cdd6a62a8c0d7d512ca3c97aa9ce959f226c072a9c899a29	0	0
3	190	\\x97c9d64d2343c7b00b1ad1f3a9baf4647b72a8ed358a7ca098cc04cbaeb80a22	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000039c89e4ac847e3a3777795e7cd716cc6e8197fdae73e7d531017ef1dca1f1e8ea8ee9416dd0348f20a0371849ac7c60a187d8e835fe470a1e4e9d8a7ea229f5f82e0a57937d0542a00aba082c64419bc7049f89086f80e099b838d8722a6e4a30761179ef53af6f4b153f01b22f8661bec287a41f84cd683f6c7b999f79ef8ce	0	1000000
6	256	\\x336f8a0de6612a61308d2b4c759f3ec350ce2bfd8dc31fd6f1f097bdd1afe9ac	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000a12d93e16d18d66252caaa2793d430a836ee7b21e16fd0157037a404d2fe44068d8f7fa05123e8057b745d477c7208a101f47b88fac77fe662ff74c25f2d13ad41e73596e51f29ce46bad14efafb46460dff719304b8340d2285707f6e713034794eb98e82d07a5b96a186ae58c4ea01866ccc37785e29e8cc7bbff64e2bf81e	0	1000000
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
1	\\x3cfb9b896824242f4b7019d797194f03831f59b9faddffcb7d69b8f2aadeeccf2e63657537f644939acf8252c81b09049a814789f663b6753be5ec4a16013d9c	\\x93bc00543ac62e3bddcfc7f9d774a144366080c86abd5286a5901bafc1645a80	\\x93861b5c7e66f193e10d6bfd2788e475456d374bc1dd489c9040868db466249070682bf7a8d2d5cfce364559ea096e5f67498094045d8bd9d266858d0c4c0501	4	0	1
2	\\x07ed8411d874facc428daeb1f7616be287329eb9a9f623c907aa01da30315ac70283cced8f50ab2eb05a27acd9967546636395bf575fc4142da87d6c0907695b	\\x97c9d64d2343c7b00b1ad1f3a9baf4647b72a8ed358a7ca098cc04cbaeb80a22	\\xd6c642c92aed4d7893fdc2dc2c1d66f179d447f86da9009cf458e4ec8614ed60ca6f07d4d607a49c97a610fd1a171a301516e6553c5e043c60a4d00d8d30b200	3	0	2
3	\\xd23a88578bd7a50bd44f4714a94f344bac7f722370554fe4efa800a076da4a590c305bc89900331d6d24c3e5167b31040481a53c67efe53040440fd9f48fe849	\\x97c9d64d2343c7b00b1ad1f3a9baf4647b72a8ed358a7ca098cc04cbaeb80a22	\\xc957b4c2fdfc8cc4cfdd20892ab8a5b6ce486157fb81d20fa6da99d9fb8e8f1b41fdae3072448d1bfb06c1c6e8cf36d7038671fb4447562f519084e83678970f	5	98000000	2
4	\\xa261e1eb6087b1c7a4f43f014915538f98c00c883af3fa5d4b366c8ce5f5eaf2b88c790b478b38ab0bc4c421a8e19874bb76cc3ab1b10d742bacf3d06a667d92	\\x336f8a0de6612a61308d2b4c759f3ec350ce2bfd8dc31fd6f1f097bdd1afe9ac	\\x22151ac0be74cd1a40de07771dfc66c0780804dcecef7a59f20963825d111df9e9b78d6f87a282c8d55885a743f67f1a0a81399ca3aa7a854e62e3741f9dfa09	1	99000000	0
\.


--
-- Data for Name: refresh_revealed_coins_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.refresh_revealed_coins_default (rrc_serial, melt_serial_id, freshcoin_index, link_sig, denominations_serial, coin_ev, h_coin_ev, ev_sig, ewv) FROM stdin;
1	1	0	\\xcbf83c34e2fa77315139702ac94ee3a0c760fed54fbc5d690e93cad0181362ccd4b412fe81bd91d743e0f964166b582bf207fdb33147849cf86e18cc90ac1503	205	\\x00000001000001009e5a9393f4b33de889648310764bc03b1d848dfa0b337f2bb9850a7e9c2615ddaea2312cba107d41c17646d450155994c62003803838a71c80c8f8a81c254e0eb12bd00327b642aa62c65bf5bc6ee03793300930aa2f11a584c1d9fa0b85f85f8d28b0898003bf1eaaac9f9604919af5c66cc4a10eb6069d7ce796657d5e5149	\\xad670d581fbb76077bca27baa48d5dc33ccfdbe3c51cdd64acef41684807ec4ada4f689c43dcf1924027a15aed9bffe710eb252be9fc60007f62b654c4e777e0	\\x000000010000000195d45f996a39273a5ddb25ca0c765fe9b5959f925491ff9575093f6648c127c4dd373f0ed680692ab2c210ac9f0b857d36ac5f6e92f6ebeeeb19140d76f63f347e00533cdc39e60e467e400fcdee312a8c2fed21ef20639bf79190b4f8bbde4877dfa1963d9f22ab9634f6582478894b70965882723d0b30e650f6ac6cc2e39a	\\x0000000100010000
2	1	1	\\x00ce58788ad1b6199f2dedd3fd21b74a5f8d79ee4c6365eacc878244f8093e017e3186b371b25d673744dbafdde85085ae81e2b6ae71b937443cd4b2ae66da0b	270	\\x0000000100000100382262b27f5ddd1cca0e5c311f4671e44b79b2c6fcec40ed7d737f77040279362e8caafce009e68c5de590724aea7620ba3928e1f5321eb465c9c13b1e4a98274318be16d21b9d4eb80e64ab1ca380e2ab5b798b3ea67424df869688698fb1c8fad46595f4ddc20ae8340d4213d690667152938e1819c4639afb5f7f801c2072	\\x10f0c63e2584293c407773556169882befb92acb16078ece230b28bfd266952518ce176b2a1dd3806373e4ad0631ff0ae49063d5254083ddad9c5cd1387d3885	\\x0000000100000001b619cf77693e98d787d4c073a1fa7a5744b4e29c4c1a23fb1772710f41f11184ed21e9e4a1db3c9e924056aeabd467c878d9bf426cf7d14f53447ce99a54adac53da8d20fd61cf04e18d10c5ee4b113a7ab863c6d6bb166dbb2b087f89771a7c4d9e44fa61b99e1b6646807eb4f5a7557ca73d7b1cf8b1c8012ed6c2c5bfe9f6	\\x0000000100010000
3	1	2	\\x263c0df4104061a84d0c16a7390978e651000be920ceb21579810527d5e5e65bc25f1cb4fb986401428d311eeda995504d2e4044e680bc74c269054fb87c4e07	144	\\x00000001000001005818b97236ff1bd300544ee185b7f9890ad0ff3c8897fd37d9a7ad48fe0e11670b4729c650cd34866616a545fee84a42693d552106d3b5a78b898c4e92109c23e0689737a5b7166ce6f61bf471ca4cac79b3057b5380fa90ba2eb8b15f156b226c698af5965f7fab89f24bd4d849d3f1b78152d356ca72a32168ff19ab336ce2	\\x8c7d111130b0f2302f0364d6996e6f2b97f23967baa4474d3fdc086c74bc4e18121a01391b45a9f2c32555349edeed252dff73c906c0222e1897ef69e0675457	\\x000000010000000159bc7055a59c67cae2dfc11b9c973bf54a0a071452b042b0490b20a1d82e427cba20c5c8602e76bc663020f6d1f3219745f30899cd1903016bdd4c9c70173d8bec7a8bab70d40c3709f7aebcdc1c346f3eb71990764099fd906d4b4f9b8ab9223ff7f62e5968bf71bb92a0bdfa7f53636640474aff559ac5afac5203135b03b5	\\x0000000100010000
4	1	3	\\x1fa55b2572b016fdb7d7d7fa00e3498eb47400168b8f28ce6125d0b22093cb59455a6a9c240a61df5782393ed530dd2b001c3f146d03b868e1519bd63eb2e309	144	\\x00000001000001001aa98ce321dc018a7b7fa7ac0fb2872032367a15952b3d3a6876edf21953d747b21fd4b370d1f024dcd7fe178d09f1180c85bc4ed571d9805ec7f5d15bc34b84fbe76c5c5c20ce6d018a402f33423aab924e08d16e54d58e559bddb73210f493322fc9a15142bdfa87e9ea7da5e197c5513a915c82fe95007e8a32ffc7997dfb	\\x28b9e2ed468e7e9c786c7f8e6da5e641e5e14c4bcea3a8613379821bd1126bb54b38a35b6c32b91e6019c4d0309b5473100d8516a6d0a4c68bfbf04295fc4b42	\\x00000001000000018a303a6a90c09e7e9a562b9208d290126737d0e04a3902b56f5c5630eb2299f597ba56b9dc4eb71090d34782723e74fda27a5121572ca5d4b3eddd4f66bc872e28c438ced296d0519cab1c66f071c96cfaa5b365e6901ed8a3afa4c01b2d4c12adbee04521d8286b4e4468b3d77ecb0982a3b12bb40ae27bcd721ec04e113993	\\x0000000100010000
5	1	4	\\x3f1ce49cff3738068998cee9462eed94eec4ba8721e0bf96a216aa71e915b91efebeea6523742f268edf298877d9ec296ae083089bae1c525a22144c833f5f0f	144	\\x0000000100000100295700180ea652aa785d8b7e4f16f245b704e0417a3f6bf7a382bf60ccbdce544932ebc8fe5047dd78a3455ab50c163ae7a97228da61281da965f6145e6b60537361ceae63e96c031930608ac40a7adc79e34dbb8c17da1889c5e264a67fba48e42d015693a7b835a4d8effe3f6343f330df38072aa597f79edc41581c3f4668	\\xe4f0af3b6d7e5d29e913c1633584993edb3c807b462f5d79c55a8267a3b93979cd0de0653a1a606f7dce690947257bbca9b5fcece9752e2c9af3e4d3599e963c	\\x00000001000000012d8c826fca68ff72da9e8a33282857ae31482b8c6240a9668dcc88dc1987b56d99c9c559791d6e022561bc38ccad2efff7a50ebcc2414d0a2078c8d0ef24cc9ea06c4859eb8cb744259ac942116e3edca223df6a92b9c7881fe3950c907e5648180e9beb81000389b232ceed988ffdb3332f949bd85bf8d8e429cfb1547afcd6	\\x0000000100010000
6	1	5	\\x288ba97b7baf11e8d4ee0ff4f827529de77ff0dd28a6c990040e54f294a87e9cbec7aac78ddfcf3c7f1fa8c59360a3b3b5ba4c8fb01b5d3bd896d4c33fbaf204	144	\\x0000000100000100a96fd15880947514d8cdf6eb53a499b18a119411680f167a9076db7ae4045955f64a368f64f2566b9925ae10f0c8ea42e591ce8b3b42f324c07d7cf10eabaeba68446760d0f25410c23a12638a6efdf5e9e35c8e169b27b7f567847a2be3f49f1cfb9138ffbcc6669d645e83a467861dc32c3c62583cf77feaa7929f29604bd6	\\xea98d8546ae8dcf27255a5427a640836efa2892da624c85800e17dc84135b763dda6952b9ca39bb3c9251067d5534ac55fbc4b386413368b98ee63608e5a6c82	\\x00000001000000019a95cfb5b476977b1fb79f5eae3c581555fbdd564c530ca9c410a74dfc9e59974608572ab9cca39ee8e25e0326a053db6741116fc6a1fc1dbcd8200c4107859b70e28e18a00699f52771b5711508708aa32adc8b8e2d7e77c072e02771e320e78eaae04b5b4d7b700a1543a59fe5ec46d8bd19dbf565097b8ed6167354039d4e	\\x0000000100010000
7	1	6	\\x4d9d779d32a3357e48ecf0fab68c036ec12460cb7a7582f98cf7d5e59f343d3d3cb2b71815013f2fbd99f26f0b799483cd8531e8b8205d71869277424e00f100	144	\\x00000001000001003e9ca7b981a8e6f4fd42a64b984edb3ba9a800feedde5448efcc57df4c27a6391b688619d428268414d6d07536ae376caee057240f72b8c7cd146e476d720f51d908b956fd868beddfc8692214d186962497879d8046e97df1150caf21a2baa96321c3d7498493da6a0d598e9c0243b21cd07125dc262e15559d341b9ba0ee2f	\\x015e6632955989942b982be2cf1d6fda45fdb0f8fd2a0b1014ba89288bdc412a2ab01a1d9ecb0514d63487d142eecf3ed0e8adc800cd957d7c66288a846eb821	\\x0000000100000001a2590df539e3ae7b3655b46f3766d518f2911ef491cc980a815a92da00d3adb9b23064432afd302efe721e64f9252128bcae819e9401a987ec7a939a253866a63de0f694f113f9e793029c5ab3b1797909eae08399283d06de535a6368f2d2d81696596bf2961a481f8de9031a9e95666bc4d30b7e8ac8cd917ef7ae8aed1959	\\x0000000100010000
8	1	7	\\xed63405094a012184095ba8aa1b51e5c0d48d81c7b8485f4f78cc948e3af368ac2895d659e679b2e4f26956df67c255993195b44794d146d9f23eb83d4ee3e0b	144	\\x00000001000001003b7bc0048b825e97929e00f46bdca0bc1f966b7ecb2c95b2da34fd98030baef78dc97bbcc2598d7b4e23d68d25a8775345c5c43490b27c20c18aaf0defa052758e76556d491230549743e7bfc0bd6a8466c6c229519880f71cff03e5135ab7e42a36e55677379b69c3a90c969720982a09881b0ea6c648cec1dfd51a7de8fcbc	\\xb5702a592b3a1e50da444c6d2c7d59ec2c0f3b202db99f3a8e8c91ada5a60fcddf490460a6e45d2b92f76830115db9a6f4aea4fca64fce015ca0813f316c93fb	\\x0000000100000001747f0684b0819a9c730b2fe9dd762e05257efc7fbc6454f002e9abf1e6ebf6497927367c1425cdf223864c4b7ce0d6e013aa3900fc350e908cb3e95642e364558f33827d0e574562e3eff93717d6092b472a968618996304d02f5a656cea67899823dad17604082a16eae8e1b52a89122a4bfe6d2818b1cdd61d5cb5ca329563	\\x0000000100010000
9	1	8	\\xb8d3e3e936d5bbdbd4acb267327b52d8475aa04492301eb802092c734dbb40fb87bb82d904f61272846f88ce908bb9f2500628bb5e4b82d943cfb9822defde01	144	\\x00000001000001005d882926a30d07a37dc2cbea6f400e705ae1c99ed32a1fde51ffc084de2c82b39c7eee23ae654dbc2bde5c1835deb5a01b8c8bbb26ff1436a346d2f67111e9a1e4eb19ba91419ab0785d5b192ba721b9a2827ce9faf772889e6ee01664f7d4eaf4e1d845de7ed9339e8e671e21a70aa5a3ffb6ed0970a198765ecd1d24c2ddaf	\\xd54b338e45c14c2c9ceb81c115d859f0e08b9d1fbb7a56937f9dfc95a42991f54333d05cb90c20a5dc07e50403b3670102fbc5226faf6e5afb529cc645356a5b	\\x0000000100000001052df40c47f308141afe663ced8ebba8b1dd78e9159452de6b9c12f02c76f469df524aaf5ae0eb66281a4eba5e891e929e84a2bc5e097853293efe097e1bcd560d5e96e7d1586b799cab6679175bf496c0a049b7a719d0771bc7a093ee416ab7b7c1f15006616c973b9bb398938d15d5eef5f8f024ea587182fd6831d3033bc5	\\x0000000100010000
10	1	9	\\x3218e5dfeffe2543c4ba352b3bc791927612b1529931a9b5e188b0a33bb49b116ec06eab3b827390cbe87ab351459ca25057939a66f032f6198ba69248361a0d	144	\\x000000010000010067069aefff5d54ce0efb0fb29a417a277555402c5e992546c286f7e4d54cc1ffe9f5d8ca62c200e1632ba4e407d3dcd5961416d45c7ca4d16793643d99dd775b52f349c6c895efa065a9cd60de4556b4ad7ae54b5b260da75282063536568f898c5e6d5abb4eaa9f47891f1714d40819202aa40c2c573748916a4cdd798cbe48	\\x014fd8d4fb082d036ebc1febdd6a9595912bc3d469b408d3ef3a891616cba30feb64977a32a5ea253dbc5ee55047e3f5472e81846ef19713d01153067974bb39	\\x00000001000000014441af902804b8ea47949ea83af2ac7f2e24a6427c6647b2241b693e98d5f4cfcc08e9c2cd4249e57222e8011bdf5dfa44a809722ae5a4f5953f71f2e2e8b509a923462ee21ee93465280f6d42d445d05a97597b7a6d35e5791245e4ded0643862ce755597504e409ab75464023a5b889f4540d5a8be48a65eebfa8f228a55c8	\\x0000000100010000
11	1	10	\\x9a5b8a61fef72453c858305d182b8df84c0f967aa1faff2cebc3ab47346f8da424dd7408e2e592e3410204adc15e26411de1fa0d32f9ea57fbcb451e24930809	180	\\x000000010000010013116e1fadec80c81ab33cbda1a989895ebcd1b75426dc642d6443639e48166259bfef89594562feeb584e4bbccac7e2cccc5f24dd99cc7a2a2bfc182f1a870cd5c883e6ed5830dd9ed54e2349ddc0fc66e0897e49170fd42817bdc3f7a020ddb9b85dc3f162aaddaf9420c98438da73c928478198aef080b3afa092394307d4	\\xf4f99903b7e4062f41db36c5548177728fb8a7ca47b2c28900e8e0199785d2b5780f11090f773976d812b7c23a7e68024fefbed60eff37bb5b6ca456b95eccd3	\\x00000001000000015ec9e3b86f4dad44ba92db9637f036e32c61e668196e656cc1b865916ea3f7acde54f30d128876c52f5cd0e03143fea1045057c42895748ad4823d583680ddd691a4443966efaf69bcbceaf25ad7b73d28369162ef3e9e7b16ad9a5ba65197bc9fffacc130ca9344f793644168f0934c737eea4495f4656269944de15657313a	\\x0000000100010000
12	1	11	\\x2ca26f84dbab30a48741031bcfceffc21271de21304f467b661a6c81d90f1bd056d3b8cdd9de134795e5fa8433edce43915ee2777785c79d4dbc9257d5697003	180	\\x00000001000001002b62d62939709133532e2564b7d0f79816f291744871287c824752e9ed7f1057ba72064510917da62605161792a85d39dd60eb729f5aac580bb38b70b5b39c5331a796c11becef642b7e8666098334697571d86b51ff7ee8f5f74818ac6ee59e969abde6d8eba3ddf06e26aa3f654fbde2bbb522a0bb1aed5c950e6f82eb1d4f	\\x4fc84b0d24b3ab13994be2b794e9ec8228555574698ea0733273a1b25caad851146a8875219498bffb4e0012666d2b412b23fc342f4bc0353a31434a48b78f39	\\x00000001000000018459ba5a629f4a23c9973d06bf4b8225a869c245cc49f9ef7dc8d338b8a27f8e8b969dd340b73db9f31bf35c2b1408f3657de91384ba39ac1b8d5f798d0f4360341e3364d12740d8cc444ea9d45c4966846074cec195a38f5178df480e1d6cb32fa8fb0dcd4b8f94b54c14169a084e7523d030fcf699cb19d8119a0dedfa66b3	\\x0000000100010000
13	2	0	\\x8ee5e98af6f4d62c311493a3f0fb94c07455f2a0e70dc979ca027d310991f7510ca46937b84a7f702b877d5a3d145d8914c686b4b1df92647b236677dd911c0e	205	\\x000000010000010035f00d825778b21129f28c513082c30de5520586450df9f230f11bbedcb6fa9134d798bffe8f9c9a1a8a9f031ab3998fbf1828577caf7c67dbb6988db3f4d06bcdb35965b0fe8fc53490e16e9813e697cba775cf146636a80fcb8e100452446eaa1c21a4eaae2c8769ea54d1e12c0d9f7793676ccd95b567824522dc2bdbbe3f	\\xd89122f1849e42519fcf16722eba39932d8be8423f5280f4a087c744d590e341d5990483dfc8d05fd5ae51934a898fd5e543244b30a1065ef5e109e53ef560c1	\\x00000001000000014dd7b2e58dcbb9afd0d9e318b7947b602a338db391d65d0b2b7e3694f86d5e630c4f6811a39a87cd80d8de91904d721ba82d4bc98ba270350000082cf760281b98fe36faafebfb70f0b14e196231162323d8745a17cebcd075db88a544c3880ffc7694737f29142d42370664ffbeeae006bfce11265705c982202567485b4aee	\\x0000000100010000
14	2	1	\\x505db21ba29fb671383839d330602c73011328a21a522bae68d0ea01fe402e3ec91b9bf03336604b7491cf3131bad25e1bd93e26f7a8e5b7db90b7dd40674c0a	144	\\x00000001000001000ccf7fb2f91cc4d8559d78c261f53e1660edfc594ed1c0fb6996e86616035a5400a79089c7400533cd858f89edfcae66a2c718d418ef33d37338c6744cacf6e2b0d831ea01dcbdd2f95595d925ad5068e2016e802d4cb98c29bb65d07027b93c8aed4b801d2fa856057731f4ad4c2b34f6ccd6ef4ca2b4b81f353b538ea00ac7	\\x7cfcae7cfe96d80aa851843d67313deb5f57b494c4af8fe0bf6ba1e4b9ab62da29fd8a458c7457c7741ac09997bbeeafa501fe4943fd09c5b07b981aab906826	\\x0000000100000001c33b043f1bc48f5761f05786b3e1e6e4ded82eca79b7aac16465e6c5f14e85434247dab18b0423b335cd0fb1a01d43123a0357c445d63d85cf5091cda20b7162891d814dcd0e2cd8f7582adf681316938e38e844bf3ba979bd89b0e4061d59b692ab9faccb2374328344fc101c1cc399f8d3bb8b6bf4d0891e06dbeb6c678793	\\x0000000100010000
15	2	2	\\xdf4de7abf6b1386c9af4e2339d1051b6443dc9a7b407781def43f6cbfb81234eb4e87813aa5ea138be19f8c21815eba8259fef73261c3a407bd52c2641cc2301	144	\\x0000000100000100874a400431fbcd35d03640198230c02770d955d6b7064ed8ec737f96eea1a0fd6edae76cece43d482f71297d9afa9ebf1817adf539d3cb40d3be92c10b6900e5a5c97bea67a8988af6411cd1d653d617719768ef5b2cb0aff5d0de0607e5037a76438c1e00e4cc2497e258a0c22b7fc47f5ae1f06720bc6c16a8f078257ae946	\\xd6dfad7de3f849eae58420e256a190262c984e452ce77160f3ab4c05608e2d17708046fe98ce90e438514f8f8bcd7113c7d13e5410bcf9516a09e5feea670496	\\x0000000100000001cfd1f00e333bf007f77a34acc297d9e22eed23354c0b7702e80a8b04908d80054427ebbd58abdbb030f3300f520e4df38c0359d308b0328fdd69f41e651e8a19e2584b1aec2b30fe79fbd2c6c7ed4d883af3a4a628334344993eb802f8020808bb3dad2a0a677c03d443b485e9fdabea2125c5eea9219936ec8114a0edb3e1bc	\\x0000000100010000
16	2	3	\\x93bce46a74e40b9b7ee49f9050a87516fce5564bab516f73f953f584ea06071c0d3f2e39e5b951f53a869955463f2472e60ab5d9d25ad05583a092e19ac9ba07	144	\\x000000010000010080bd160d652dbe3c2e853f2a26a1f6f5ee5df2e8182252d693fe3a565f6544cc9fc9b89432d8c3bd3cb0059f18921689bbae20940655d8b1596ed674df68d0c0ee549bf3219a57f091dddc78aec6e20857c30a4b78b13993f4b7422578d4766848a804a006ea5c41f65e57a6bc36d5081e1bf44a4b21ec41180c752c9082f430	\\xdbe385f472e11d1a863476d1e82e565142bd2ad57bcd5faa3f73b3615c9da179c1d386585c494952c2bbeb61eba079e053edd3558408417af0c5e8cc642d0476	\\x000000010000000124762195d2317bf54dee084eb327fb73a02f19032db77244ed34253551d5924b528bf06df98d82cac142c23744eb894eb2a19eaf68b2e73772cdaae4195922ad96f70f0f7c435ee47c3db058712c6360a42c447dca087d2d81f5dac4c52bcddc67fad7f7ab67d0a1ab559692f8d1cebfe42af04d9e03a57fb757b3771d7af3c4	\\x0000000100010000
17	2	4	\\x60d7e81da993f408873b29335d30061d59a6b7cd446bcd6f2e8c2a64267135fbc385de8c77143d23534a07880f8bded896c26e28e966bff6fbbbb90046f8c508	144	\\x00000001000001002c5db66fafa9779a4087d2749a35eb4c8329f254ea70ac83a918d5bd64fd96476520b0c618da17e9ef8e196a98977ddc10f4a5f41289639663523261bc43e395871975505fe1ec6f2c178521ee0b34159d0f8154628b04f28dae7040acb6748166d19c5fc88e8ff25d34348f2178d5ff407b504dfb7bb50aaaa29a1971d6069b	\\x4f8d41243344616657084719ee8c5a7f81f4d9ec11b6ef065962af6f12bc97cb7af0baf5aa894f0d493209d924e16a47c1fc56c5a91007f5abd482083ec081c7	\\x0000000100000001501b4bc844d2dee63b39ba9df9e10d80c9f336490b144e60eb7274c6dacdc6e10f012b64bbde45f6081dd8a6b52f62917ab07539e00e431e42b8cec4c91df44622ada6e96f4d5318c0555d983c5b0aab9f45c70d72c27d3f1663103dff959177000ac723b54c562d5377e8592f5fc24dad793b03a6e4ad2cc888d0ba62fd0c03	\\x0000000100010000
18	2	5	\\x1116ef7da04a45be82e2d8db01af94508270b143c1b709c017531ccb079f40db17e94f299d516709ad0d97bbefa7ff9bd25f3bbac2f195230c095cde371f0808	144	\\x000000010000010069d08806e954fe222fcf6086bee36e7bf640f129d40ad0b062756f97a54ec246bbc5a8103b3973d38f095f09190ff94c586d8d4f1dc85b9342d5330fcda5e0945dc0052864202b6abe07f24099e573d7a8e16f5d4d60d34ab330a7b9156fd9bb549203367934c0c90fe328ce42274e0df4ff7efc85b1a3396ea63f25ecf72731	\\xe8bce01b106d6b38a30448c331974ec3441ce09873e45e25860a7f37ea3f10ef85ea2c9629c40e2a8eb849bca020a06b6f36899fcb7f2dfa059a599c86058f12	\\x00000001000000014630291e1a71dc05c1c2293082a1552d816d2170c1c90b4c9efcd541d96e25ce91cbf0e5c31197397b1e5eeb73a41e42332d2cf5eb5745e9382175fb9281c0e54a2ba071a32b5ffcab2f0080f02038df3cb2ebd26475e410cca32ecf0b9445f1cd224f7f5b02e3451d60c61db0a6a5fc655298b8d42c047ae47bb8baed11cd8d	\\x0000000100010000
19	2	6	\\x10750a2cdf394f89f7f582123d97a4210fb5bf5c9961afa12b26da9ccb17cc96c1158e35fbd563301f886f4a208764804796605559640539fedc45ab5f63bc0e	144	\\x00000001000001002cc8c8cfce7399b74d1dfb50014d944f63ba2aeb332cf7a2a78fa533dfd65151641bd68238ee9035b0cc78fe40f1175904372a9765437fbd47003eec8185ee6aeda97c979505781619d57313569a5eb12ba4f41ca177cbf92f632372926eb2bd15c2faf1056932bb48e9dba99f15152863bb1aa56efec1d28b89135734ffbc61	\\x7fbb0685f687ceba4f0786cd69167d2bb5d7542f93ce0473ab3f0c366ce875b53814270e8099c8fc3a6c546ec097bd7899de03dd692d72ef894d7909e35fbdb7	\\x000000010000000131fb98bdb6eedc9b01c2d5cc808b4ae1785c074dfd658b7ff1a3bd190319c4556b6e792bee76e70feca7d2ef7e34a846dec6951176d4ec06c68667d8cda89e2ca8e2aaed4ecb2b577e00e8a3643c5b3da85073a9507a565c8aa7cd6a7e0d1833b8c29a3563b7432b5cff6dcb53e377003e62102176dc735b0a2ff2e20021275e	\\x0000000100010000
20	2	7	\\x5a196e9443868f264293fbe206113c80047157a2f3d3986d9a84df2b89f34c817afb2ecb60e1e53d37d11ed7840f50ae1df8555193c527085f4cd89c4466b20a	144	\\x0000000100000100b19f755754a3788f9565f6ee3e0d2d79a71977df7bf7dc5e3cd710857e538e16285625b41f65bbb4707fcdd0ea4740f8f855c62c151264c01b865a689244dcba235b08f9508de437649fa6a04fa75a9d8b864d7212f6d723b6e0be1abf3ce094c26dafd717e8d58f2a309e722b9b480e3a0db4180098e9b9b593b6a452994753	\\xe8fab01365d8e9eb3afc80f12fd0a8a2dd1dbf031a861b80ce47935e7b8c83ab569628045a4b8645aa0d705b5d566421dccfcc38bc93c981839d2a2a3a270ae3	\\x0000000100000001d2261c03e639205ea80fd93c97ce8935937ced3921e314adbcd4ec4586608d45427664a364948645b7d470d0df182daee8ab0d74ab87f64c6ca5e08dedd3f4cb439edb47bca00dece3ab381cdf4c17b18cd038c5d9cd98f1fe56beb1b458eb9b0f3e6cf4bc8c83057236aee2cdf0ce2bdd65d6f84e845debae073b4de31cb94d	\\x0000000100010000
21	2	8	\\xcd55a1d1e3879252293c26a381be9d959a8d2f1ea7430a5bf3d4fdf718b547f59dca0cc4562273995e555275e7d8a8b48eaceb61803de66b68e5f10d786a020c	144	\\x0000000100000100221609f9537797f015c1b36092df480e86242d37fdd4d3ceec8a7a070a915e549fe77260ea6e085414405d55b0e76ca0675cc3dac2f8bf7ccc19b26dfa3f8aee347c7f3ae06f40302d63843ee648acf25d59125aba72eb2015e71ecb494503bb8472401de2916eeea2c406dc7ea40e40901404819003c41b70bd90ffa653b79e	\\x6df40b6fc5814b223227981b0d3e19d12d71e23742648e142e3cd7ef0a496973ac839a3e60d62d7e4c2114aa7ec020a9b65a89b0a28e63e01db3c9fbbece6cd0	\\x00000001000000015d11fad8e4ad4eb2b703bc36192e2db095e3212239067e7866a86440caa9b7d6226987decde10e169928402f16d190aadbb0df3bcd09d5abf63ac1dfdf878a62b56761cafbb01872c933a209d79c79fb488119b2c0a37d199d3009afaf285ab5bbf58254b7b1a75487179f3cde5090eaaf3d7ce3736183e46fa01362e58e8c9f	\\x0000000100010000
22	2	9	\\xf7630a6485c898c6df72810eee2f8cc4a7a5e6b8f74273b240d63e2aed798bb974b43310519fa70422d9456b3bf8922926a14a990087f36ad3d4ee4d222b2d0b	180	\\x000000010000010047b33fccf2f53ab2c104e7933d873e035dbcd00cd1621ece2ff0680d17ae85354ef67530165ce7ef958bb4c36fea7ff9613b5e700209a7dfc803d20cf150c8ff2e87fcee52390028c60a1c162863877f6f4ea288fbe5f9ed2c3bc1b68cd8771d75340f25a490d5099332bbba89ce4f8fca7faea15de888fdd759825f077b6d48	\\x82040a9613fbfe14eb15ceaef0c9e9c9caad63895c24ef4cbed746484b371c34059f4269fc9c1062bac94c9cb6923a044da80677ec03dfa1f0a3fda4dd23a50e	\\x0000000100000001920c7829876f4cff73087696d2b4c8c94a4e62db9cedb05e229941358d8d2cca870fc263d6b41cbf07fe86d183ae18b5b9dd2d81bc4b48e702bf509eed011a646bc3202c7821a1b87b348e8de6f4b095e0e5e612e742c5b5dccf9f697b2d69b54a511d637e46d3e782382742acfe00f9133b6fda5de91591f6f3415be5c4fe94	\\x0000000100010000
23	2	10	\\x179aeda54f414ee6d4cff58b1be2c8a259d919b9315a46660bf38b62cb3f9dce6133d021b573bdea99e76b0601a6e261d5acce655043ad8ffdb7cc55e14d6306	180	\\x00000001000001008c290b294d32c1dcda7a2e452def847b64fdad825bfe8acfe5c7b43c1a81a3674a440cfb95b6b0f495a7e20bbdd3f7ce07a4d0ce8b35c3317d71e8372e2180672915659caa401bee9b53b47f2f258e06680832dba8b720337465a4f6a01eab470baf82faf7a3b806565d16dddd0f4abaefbf039f17774ef7f8349697d43c93e3	\\x1b587c17596efc0b231fa4546423e04357372bbc68671e2cf7152d9be205ea2bd0554660668d6633c2d6c36e096cf562c860a398b9626769c9745d89580c37b4	\\x0000000100000001668cb361abbe883f451b65649cde7631d066d9b50db58471a932bac732d60f9bca0de5b02efe1ada550b86c7479b79b4e4e406625530ad4fb49bf917533a3914212164a9717b1cdceb562208c160f12bcab2dc43e4d44c47b5160ff160e04a5d1cd1ef3850ac2e66e7b5b21955d03e80c6fdf895acc1dc522f7e1e3024680139	\\x0000000100010000
24	2	11	\\x3fbcf0d5d3b251829c25435aef319f035815c56edd0c7b67660adcb48adb55dcd2640d6dd0c3d4625d0948da4122caa55da1f9df826e165c052e0ffb4e590e07	180	\\x00000001000001002276ee375ee93d581dc07e8c5de10ae0ff8ec4e774d64c1819052d38504939094f1c95a967289f4b9f3c9cd1e0b2cb620d7c3417a491c57cf0b142c1bed18690d93626aa3945e75e8a5ee8969bb552b01faebdf64361626b943e80c0a227840e3b09e51b21e9ef0dc1e3cef2e9e80a426a969d98eac9508fd74c8d8ae71a5e09	\\x6f944e2e3e8b02e3b4f9a0789ed23246f26da3d247ed6c8c7a5fa7489fbeb2bf8e8415fef7a0177a792ecd0fde76658ee3420cd7feec61bec4080ccb40f089e1	\\x000000010000000199dbe5849fcb35b2d78061d3a9e64a4be2ff674810c882a15f8459a3acfcefed9faca632e2aa7cf7709324f059e996ac1dfe81d4957ef2c17d8d8f9cc65e0214e2f41939ef3ec37371bc8e072946491616ceeb2f4baf222d412ec35bb43b41348683f457de10b4dacefdfe3d39e3ded5db121dc3ef01a7bb2115fff0f1ea9861	\\x0000000100010000
25	3	0	\\x14a9f74b5a68ad16c8c43320bcad92ec37d8a2a5a5d841779ef93503a1d19279582ee5001c0b42a0e9c157c42396854cf1cf7c5733223c3e3844037a2b91a00d	256	\\x00000001000001006dacfce3ca49be93fbeb0688e1406b922e77eac32ad3f04eb816bb6e5df723db6a75db897aea1c536dc1630dc7f5d5c5f97e0ae7f4c32b8db52940ab05bc3180f3772da132b1f8455bf36088b4577d91942006fee86e4c7ce40b6830c1ff8d7c6f930e582df7eb13d6381622bef74e2a03051209ff292bef8b71c7f2ca50bbc7	\\x7637025f2af711958a1beabe4c8b1f5d84ef745440a9932d055e66c5422e0ad7b1667508732d235181b32e1ad163d2c193bc8dafa80dd01be78b466e9918d476	\\x00000001000000019fd23c02d565a9c832e5f8abd335869f0ff8c370779ede5e1948c96e7403e94a9ee9c8f96344837d436de9231d4f89572ca65d8c4b04052e39ce12d2b2aca8462b5927f1bb86eb057143e7fc3fb0d54f347012ddf4cf60bbdc4682b18d23f8acd331b63e2b31d0a88bf0248461feaf464e70b8cd8de55c0757e8f36a3e9645e8	\\x0000000100010000
26	3	1	\\x47d2fc6ca4dcbff2285b7bf34539f4dfaecc14fccbf539d758884ee7cabf180e76eff2d4446126df8a395cf53b66ab1c05b79e503fad04c15b75b85795629302	144	\\x000000010000010001201fedd25fc4f96b91b1d8ae929c9fbfd2b64ab9a21cf985d07ac59f8a913a4c403a6c0f3f172130b493176cb35d746e132b1fa462e8c6b888319cfaedb8d4feb0608f9b5e10fe171c002745c6a1ae7df42d3c79519bdc6b32688c82c04c4593f3a7feb303b304be999109c40cea632460e3bffd8984bdae7e7552120d35d6	\\xf5e0967158723fa913688dcdeab1fd1c99a590464d68233e7379822a595bfb2e6b310247dba7e883f591f12afc4a420889a53589d1301b26d86026142f999a1d	\\x0000000100000001d69f9938306fb9d2dfebd3e787eaef24bfe905a13d2ed19600971cd971c138cb6090c62b765b2061426cf4e9f077c0d1cda76835ce8eb9c296dded1e8375ee770315fb60e7f0c1555ead19f9d1c8055d6dfe93f371cc95e9b6bd93bf946870e24c6c89f7f9c9bfeeee74180d05e9cf84dc8bc90db4940233e00dfa9c2bc746ae	\\x0000000100010000
27	3	2	\\x6d2f590512e9badeccc23d746f2dd44bdd9558c9ec6544e890caddd23a2d457a0f2e9fdc01863e9fc81472c50fc2cabc3778385924c355eace1b73639420a206	144	\\x00000001000001008dd63e484bb337c08f58b292e40c11d8afbf01215b90e22c45e0b576dd62bda56d7d32b3f2035e747b20462e514cc6b00c16ff7967be6c781d40c98375b0a937edb1aea06996ad475442b506622328214e68acc6deead7ec7355376df038af0993675d39198cc426ce507f5f2a7567f24744efc6e1d259af0b3067977948d64b	\\x70954275975054189fa287581976e40279f4826e3415d76d050a204dd73ee98d36cf68a3c00f64fd2f5b18d5d4e6c55f2d8310296bffa1c6e591cccbfd0bb563	\\x00000001000000015dba1af68b70856a8bc28c2efd4a75d9343ec7619682880223411c9e598c0e60d7042da84120220a93105ec4169e22f989e0e0666c3a9fb7c7fa8fb8b9ec370f42e6a1380b4fa3a0a0af834e845e9c5c3fe1c00a3ae30c5d1c5312cf709634a12a17340d9f37f0094b5b18112de1693c9bea53d3562d460ceaa9407b7abcd0ad	\\x0000000100010000
28	3	3	\\x46890ded6cbe2ac04e837862d06d363f06707fa141f209fad448861c0f34a74457a1d87b1815ae4c63964b985f3c659caaa05369ce1aadd14c84f6602883a104	144	\\x00000001000001007810bd8c617bf59dbde027f43685febde465de91081e7e7cf3104578775aba03594214f6a4358aab2febcc9071d5b29ef38ccfca322345d9808edcf8ff9551a7f8f612e7d134f7093a7ca92bc46abe508e2c1de1edae1eafcd22b07846c347b11838e8e090ce61e3c51a16412afc8cbf029cd38bbed5800d8ecc0d55d7ad2e8a	\\xa14530daf57ccc0e2bee6d0a0db9dead6482dde4ae74381d1f66c2efb98f783e98fe3e2d2f51751b99e26f85e6934a03a6c9671774dff4c8450cb7d0b1d79dab	\\x00000001000000014ae84de9285359f2804c1f814d3cfb37c1844a3603f52af57e2b5eb144244ec1c1ae47d640a8aad5dbdcc4ff053e97a2b4323d00ccc5a940e9c71c098ad2db3ccaa2c4aa9262067d91ec212751b3df0279a33e39a0d48980abf49ff8ac8f9c5de714b261c6d57b79297f75669aac596d04cf2a59926409c1e5bc5bb010f0a1ce	\\x0000000100010000
29	3	4	\\xc67088ea2672e1b2db51056093820ece94e73e596f8b466dca63c193efaa7be6a9fe8830d29519a4e9a107d6bef9d0d71a61e305e194b948463230aa4a647806	144	\\x0000000100000100681b0f2d1da3129a10c5ea1d73a1f0c96ace54bf1192e4c1c353669f41f28fac1b74aee82ee440b42eda6f0bb5671db9769f6753b5678f9b59caaaa0dcb51dc044f1d5161aaab0703d19941fbf75ab1bbbb48d520b55034aad6adc21db094a16b3fb82de4201b14abcd3bb658571e4f2d9400f40360f7996350992d9ccdcb865	\\x1f87b0c45194053fcecc708f00845e254de2a4f5f1d93a87437b29c2efbce737661e4b4282b0e076cbbbabb996bbcaa26e5b444d83827f388ae275b8e92e4774	\\x0000000100000001cbaf36630f8df13e7ef6e356fdb09a8f1e18c914cbc0a528173b91c027be17e41e88abe665a230ab124a56e63a005c515b2abe0c2cebd1fdb5c6e4950aaf449a191665ddbe07fcf3b2b39b4b6b51ba36c1ee8e7004fe75e0b7077ba528365640d785da6b09c4c887dff69418a0c9c20f0c0a02fe7df37f0017abcc7abd87bc	\\x0000000100010000
30	3	5	\\x76f2cf962b733e35f52c523e04a4ba230724a0a8462682353d6c2d427a168044ff602db7748ee387602de3470b3c1519c3e7dd5b5f082ce5e9cb5b471159400f	144	\\x000000010000010020f984f59d3c57a60c994ca9bc0ad0bef575616af746ac643aa29ecaf6580ebc7bdd9716a2da6d78724a74c917852665f672b4dc9057b865b7f6c53008a62e0827e96ca6ded6ab44253d54b3f29d1e02139893b2174e41ae4dd32e0a3ada287fb565ff521b1eaaa32cf562751002078e2fcfd7bee1ece8b802807bc9eb97072e	\\x3de651919b926dd4cda3cfd7d06112e91fe4f148eadf4aa35bf2a88e747e08fe19236511c47627103a1258690d482ed4162f65e73e6b101111b20a19dac61fbb	\\x0000000100000001d33c73998d9f72395c91e5eedc23e1d6c3d1c12ff228a545cfb339725fdd0cd4cbb9bbfd0a23c5462c952b0bd9605c7be6b165ed552f939e50e982f1e0eea5cdfc3fa921b99ce7a2e1661a269a9296f4feb05235594d60d9fa02c466c1ffccbc71d91e39db703af56fff5267896b07560ddfe63e6e25860ac7e79ba4c180af00	\\x0000000100010000
31	3	6	\\x758b09a5dba689d1a772ead5d2a464c595d7276fb54061fbcec4a0b42ffdee127b7ce9e74ec41407d1ffe470e53463114354b8970d08da06d10124a02a53a20e	144	\\x0000000100000100b2a5772b37bd23830ee1c6c0ef88c3fc8b2caef0c5f83bac98d4226e7ac3c62f1ca023a22f8480536d2fa8d4066bc6309d15ac1646a0277648ab17630b140590be6afdf65821cebecc6eb7a8e174d4d897cb69a530474b0f063113e54e3b269bb3d8c595ef93bc60fdef7576220bd6e1303b2c32a3e8e8ce6e7809abaf9ee622	\\x5e49f2f7bc63d9a47317bddc3d42d648af0c094fef6903a04374bb23b29f62905278b070c8e5fd21114f627650b7a3c97da01630014e2e57ff8199475c35ea83	\\x000000010000000184443e6e9d4eca57d52c24677844608d3902504a1bf4a88acd884037d91a9d879c10f7561d7e9fd840cdb69ff11d3f74cf7058bdb59e1e4dd1ba8c90508ae38d38b931df04d05109445b93ab3c57ffd64a0e3b71f7edaca955144db6e5fe6907733e1d747d0a6166cb8fc3d539121f01ac7f8646f52205f2f49265a2a63a488d	\\x0000000100010000
32	3	7	\\x7a85222b370477dc71efe0e28dbcb8476444d5d3a4a1956763ceac6e1db34efc0caf574c40e706a3892fd53a1c7fc773aa68c84e1b40068d240f5fd398aaa209	144	\\x00000001000001003647bebd9911d5d6f19c30d3efe4a5696a7ad0b6e52a19559bbc8bba967190c5ef26ead30935d44fbaf282fbd07a4d13f4ca986b9305fed278fda1ac540a9c042f34739f2c5bece2a8497808bc667a3d83420066a5b63064949a2e85ee5eb2a4ee7914163d2c4914fbedafbc828ea68115ded6106d420b0c49b1fb3484c34bc8	\\x8ff22a140acf64738bf040381c8fe8f2d6b20db2785bc041bf8b3e18c1923fcac1c1b9234c64aa97e2193e0ab03459604d5497ad497dcbc4e592393c3feb030f	\\x0000000100000001d24ba46b3a311f3ae880195ef8f57374f4e6ea530d3158bf19e351c22b47e14740d185e3208704cf1df5361e51f7e1f23c60c8f0ac315622c1724234f5466a7671f2eee7c658e6d5c8fe9a7b655463ea729f6c2e3ed23267c5d2cadcee95677a423bda23e49099941750d0c447ce89bcd3b170385be3c08ea30c9c490b5365ca	\\x0000000100010000
33	3	8	\\x9246fcab94d866ecb4990237319e680377a25d278f06041fa280dec7400bd138cc33ba58f75f24994e419b041f84de483094cf131d1aaf61734295479fc6890c	144	\\x000000010000010086897a7eca628d9ba6a3c5c76c079aa9fcbf962f3251eec9f07d9059b567437926bf786294dc18721a64f4535bdfba97e8b11295ce70e08514d6cdd476fa2d9ea752b9b935c6a9d56beabe5bfd1638ba895194ba7dd317aff8d88b758fb711b80ec4bbcf44683473794740bb2d1905197b2903d4c0473857d0e858f534b6b447	\\x95a63f78c4ee028a0cd516b310f8fcdcb2ee67bec6d8c6594104a7126d6d8aaca929251f98e4c8ba1a85b93cd3f09597251977e52bd002c51d400c0931b4010c	\\x00000001000000011d10b50106e93786509891435143d910aaa1cc1e45d9e783f22f2c03328fcfcdef86966f313660a69c7d4995e961bd4f1ae5e2af5f15f910df01cebbfd011357bedb6a3984cef33a63b5b4c4113f5a9603f8002c7bf9e29d5d2fe5eb3acd0d1e5f024961c1edc8a90a59def7dea49a95757e33a08f6ed271fd07eb1d6baf7d58	\\x0000000100010000
34	3	9	\\xd35453c71d2262c2d605572131eab1d3608275d007a7f96b0b019bc5599597040288d9b62af864745d3944216eed919f19bf57c70b5d6886dc990e02121c2205	180	\\x000000010000010047eb47dcc0f0f0dcba17765ed99ea22712fc27796cbcdd96b1a003c972b7eea569715648b28afa55873ac4d265b73f7b7eb1cc01d95615155b45006131dcc6bc5d2e7a68f49c70880266628f138177e59dc7b1386f35305645edb9cb01b2b639789ffc29481295a5af7da986c0e92850328ef83f80879fc89ab8580fd2ab9091	\\xfb4fb11005df35a46e412b4a9e1ea5f583ce844e866f95604d34b4e7bc93a3cf62d6a462c694353dec280638ff4269ffda56809aa667656624df6ad70529b467	\\x000000010000000184aaecc17ff4c3aa5cc987eb04298cbdef30943df8e706842c738d8a6f47f6ced868592df1b5c51a743a05899040d8484eb38e2cfd51fbd0e6f15e86c7dd19f35e3ada204e6715043a24f4a7491bbe1f7249b568897171843c3e55e3a1bbb2e5becfa6d77189e97747e23a4b2f8b929e4caece46c4b3f093762e028d40212a7c	\\x0000000100010000
35	3	10	\\x1b23c6856535cd9ee23d05d63b0d63cb96b7bfafffe6ff6010d09bc61250a30c4be6acc204a236131d246199cb0baafeb387c2bf1fa20d023867c03d447bb90a	180	\\x00000001000001004cdcc3904039d4e07b64375688ee68b77f87c095faacd894d116ebacc0f2ab98b7d65debb05fcfaf81786b33d490c2c0ebaad87ff2178599888d9057874ac06c8414b1079fab5b9a4560843bceb6f1e6ed4a9ab3d45b97770b9d148cf811fdd9be5d02716e4a63b0133deb036647db2cf25cf417112ebfc80c1c82292fdb5dca	\\x7df2a54e377bda0406c1422f4a5512fbdcae19881abeb55df012b09a31f0dedc472e4e81e491dc68972419b62d0c487dc677d0da785731805fb51fc71e332fcd	\\x000000010000000130a6932bc4d45c99959c88da3422218f6ad397073bfaa9d4b820eef1aeb2dd6177ab76e88dd7ae11f9f3ed6278cb001fb79bde4a57cc7f5c7fe09f6ab1274991269d046e1ad9b001727f269661389520719617568b9500ca4c93cef97fa1f25ecbd37bbb4292cbb1125b8154bd539cbc8cd72b81627530c2a75a5f3e03399af3	\\x0000000100010000
36	3	11	\\xde62fc8c68ab0146deb13100bf75d024ff31e2c26a43ab14290599385df875c71313770cecbb8c09027cfeb19268383237588e21103b23d022d0042c01e55e03	180	\\x00000001000001004f0463b79de2542b21d9317029bdf5d02e6498567662005c01190b542d1a8c310c0f032d83e9f9587f84116b2f094e4abbd0bcbac3ce5b4e5985fd53013e622270782058a1608f71a8f8aa80786cc55fea3d3a021758cff278c0f63baff647c328b892a1ae0a2758b536afc78a739203d5703796c56a849c8ecfb11c4ca661d3	\\xb9c947fcada4380850b344e22c7fe0ef96736bba4b86109ff8808534d2fa08e5c5cb86188823769dcc0c85b9b6f08d5b3ea2832386768aefba5a4a1ec57f05db	\\x00000001000000017ec6337b789455ad3249f8b7b1c7c2e0fc2226fd0f818cccd924372ca91894af3804c87872c63c6ac7181e1768c011ecd1a2bed8ab5557db212cbbc30bdcd2ca1c49c9648a9cd91ececc5c291a0ac39e4a6dfcd7a70dddbdb13174b6fefbab3f11fe9f893c7e65e1d9b3ae3844d153498b9b434d53bfc09d0fdf43916d0aa308	\\x0000000100010000
37	4	0	\\x853bb125723306cd9338a3fc79c595ccb9d4b4a95bb3a402a7d40ac9ead913797c6f1d338d30c885a1e7a7d57e023e7d9ae46ec30a2bfd3d6f076ab8c0248506	270	\\x00000001000001005b140718b0b36fab02142959f43b62884cddab2cd898f5083608b2eb8be506653a5e94343277aa7f27126a4444ae30b9dcaccdf5fd2c6c8f91b41a30debc763f0906bf5b7efa2b0d840e9ac2e58114f9981c4a3bf3f5b842253b0dbbc5a38cffaf40357df22edc375eb5fbea44f891dc15210cf001d18e8b50f5c1afbd60a8ce	\\x04491f24e76686c0cde74133017a23313289b55324e09c29b5999c2a88a6e4b444a2692876c83cab96c7c806326ee7a67c562b007e98b9f843c5dc79bd37cf61	\\x00000001000000015733c821b997820b00d476cc64ebe4ad1f7e018c2ca5d01c4add7bc8c1df3e883defa1d38fe6acacb4fade35861d845e58c7e6d91cad7b52dc33082aa48432e0d757a3b3241c9b7973198057278d67b87f092a3f7eb239cb58ca0ace7d8d9fd55bcb13e0f29106825b6ddb88d1f1d0eb4c6f71b044d446e11eef26697c2d488f	\\x0000000100010000
38	4	1	\\x1d6c0a54565f1a8f1a6603a0fe94962b117a2703a185e6bd865b62f640e4ecedcf6af1a6372a009754b1d80c60c04be388d5fa7d58b3806a4361955908dc3304	144	\\x00000001000001009d7e48cac01460869a0073abe6204c2c43e02338400148d3a94fd05a378e4faa7246a333f33a765274658785c7cfeb3384be2d8eb69e8d6f5c1d95aa27b8d882840f16bfc03eca15f1dbf821650e5641f6db509480fb42ca773c746a914eea4e0b263231665036d4362fac36c8f3dfff9c5ec1c83c25b6a91b0d4e334fb7a53a	\\xcdc0de4457f2dc197c4ea641bfeb508385f5499407cd939a7b48e558b5975d5cd4120aeb53d6daba4585c4144867ef42f11def263505a27cbf6a9d18f3fde630	\\x0000000100000001b3570a6f9514dbe7bad3a10d5fbfc919a85cfccae2b309ea26c6ec1941adeddd591285d6eb5ccc3d259a5f7ac15a0c9521e6ed98979b9854ead7cb607b20875035e0dd92464bbd109aa5b4fb236d698050ea485925f53b96ea2e87013ea5e0cd906309831ff5f991e0a46259feac516780c614ee5fde3e7d480859a1b5703770	\\x0000000100010000
39	4	2	\\x44cd60b38252bf7b8e1ff33270254a0904201896666a4022c091e2bb74a8572982f8c52ca35c3495496e6cc65ebe89c1829010b18aaba802c07b2c103454e30c	144	\\x000000010000010062a5c03e354765a20fda81038af8c8ad291786847a28caf18873cbbf44755dacb43bf88a0c672435f562cb9e5f3109c55ee2070e729780d7dc241cd08e35a2dbdea639265cff66c644b952de973e2ba8306e7072efe35b0bd1a36d24efc6a63110e4c4455f0651287f78afce33fd35ed5a3dc805ec804ee60495c808289da892	\\xdd3c3491170687d31e71e6ff285c9376fc658783a30b3b4f77fdb6abe77ae6dc12a76847f45ec60da26ed959b00e94f43ff1c0371efe3eb4d75de335d52f4f6c	\\x000000010000000120ad4ea27910d5bb38f62812b28ff213d20e8b1a440b1cdff9d87bc527109a46752433b971c75f2e3faf2b1ee9fe6338abd1f55bc6a54801b7e90b8660bd4deb6ce948db125085a59351532f8e7d170b689038f690caf8d7695d6a3937fcf561a610a0894fd5dfacf763d4435a8d22144e816810b7f6fc34cc94fcfabaed5630	\\x0000000100010000
40	4	3	\\x09a46bd6cb6e8532a666283c2ef0c665fa97c3aed4d2cf6e3ca2f26c08ecd0274a342c0bb43cbf9040b917b90096de2c0ca49d15cf0b1fccb7ed0fa554b8d208	144	\\x0000000100000100a6461a76718e4ba17feccc357d75c4078d7b4706e799b5213864238064fde35836cd58f2c37256b71a99e4ebba2f33a8bb3394e442fa66f20be394f328df2423aec851214524b5206e3955bd7130626bdeeb8ddb7f61d12b3c95cb7a9b6b65a967da9af02ac50c2afdbed7e234a75276d1cf88a1213e5c19209e5ea1c510afde	\\x3a1358258d68e37b3758e423aa034b8b2c59cdff2b73b9ecbeb609173595f19b237a00a102b639c9422bfa006b720bb44a6fc267ca9e1792eeeb34b93024ab06	\\x0000000100000001222281f08b2c6b14fc5cc5608edc20de0ed1931427b1d827a2ab67cae312737d9d56785f03f01acaf3846fceade9266a04ff67b08e179bd145bb80a2b5b77bd9ff38f127f79a6b0858acdb502af1d39a6faf8f7e8dc54f4d3140c0bd23372689baeaef5f2218f3ba9ab0a47bb3fc57bf97b783c4dfdc804366cf3a983ddc7ec2	\\x0000000100010000
41	4	4	\\x5687b7d0693a75334197a0e9854f2fa27ba58293f4cc032a19fcdcd45968035a5c1c0be0ef5c8c7c40313d80aa7d8691559d5e6997880e3591382037fcecbe09	144	\\x0000000100000100556ef4178e8a44e220fdea776b24ab5dc56e09830d0f1a3570e6f8607a3fe1b46cb35864750f29ffc88e913dcf19811b82f7455852c2a9f402fcd2ab62459b9907285e8d8b4993acd9be7facf809b495e8c3e768e4886755ae07f94bfff95a57104e97190db3824c000994abbed68720331ecd17f93d5b84dad87f127bb48f90	\\x48747ab516cd3f76291f515066e083d70562de7922d0d65c28ae8c82d5586406c59be530993e978da69a2987dbdd27dad3afa3276ba6d0f518fb1f6c187a6d5d	\\x00000001000000012947b8472624fd8448e450e63be42d4ae7d4a40ab0f7f876634756588dd69a1d73281f4e36e1a442c7f4ac6533879055818f882f2770416175a15dd22349671268d734b12701b9806f4365c8f243a308d97d3bcd74e4d5ba9bca38df84fe61d78c77ff795f7d30dd2bcd0aa640c20bdd6b387d920d04367e3cb86123e4fb833c	\\x0000000100010000
42	4	5	\\xdf889d64f56d5cdbac49ed55ed8ac2662b1b182760b86fd549bf2892e3dd5b283266b4215287507bafae4f9ffa4a722fd7e17317ed413322da8384586c07de0d	144	\\x0000000100000100965892f5bed2815f8a3ac49c41607a02097d2f3aa3f4bcc10a068b7dda980050c6398bc35e3b08cc9b6209a5948f922dca934ed77ebbbe3a83ee163e75bd389a846e907c575a1024c590a2195d9f7993c130316b7d85e23ec203405df73a451847c3554e12be0af40a074c7ded82a88754f3615a7168f8ecc1cb2e51bdce5e8e	\\xb378294cd31f7bc17b813dcb25f8f941775102789b4fd958b6e9dd2bbcf46a4b1c64da2f4bdf6499a18f7536c5b0d7fb56c367a1207728a7f852dcc6a8109a64	\\x000000010000000127250c2de1865d225bd4b9e4b74fb3f371ba117222786e3f8ee9d8c4de766d61e8b585b056dd635094b08a14b48b1c2270b7ccd40dde1e38a64a70dcd7a0e07f775f2e5a5c4bf8ad9cf5c52ff1ad9c880795f63e27fb70b71a074f72a7c31407dd5b2ccab12229b03af0f32a13b1c4441593391c9409b894f34e55739cc95e78	\\x0000000100010000
43	4	6	\\xb7daae974087fe6531cdd7b1cb1cf1fb4d60378a474169b363e4d2f05bc5ac9d97fdfd97f65b22a23eb90b984998ce883d3229814ed4fe809ec1db5293abf501	144	\\x00000001000001000669b7c7e3dead8c9e7825486cc923fcaeff5b435c97c53039fa2685c2ad36c554f138de2647f592599f620bf7b821e7be9961f46eb84808f113f5fe97cc153df329e89b48a7389461046976c703c5d64f5a27cf7be4dcafec0d0f5033a04a5e43938a15398fc7246b3c619cd7e3980535bbd45cf5e4cff3bdfa9b6f8c5038b9	\\xc2ffb84ead1c8019e7753f0467bc64d3218454ce581eafc2d19d4be9dc0b794e9528eed663b22986581d1aab33cc468c29aab7558513df4e259efd9a934b9f22	\\x000000010000000142604e68a217b8e9cba653ccb22158da5caa883b6398e44d0346a7c3056f12f24ae06c25c19bca94891a2b63d35462e6b0f50d364087bbb1742c5d837bbcddc59fbc5c7fb6aefb99aa1d16688c01131b240c62c79b60cd1d915770e8d5569d5865521a7a1e4f4fce866e963140c041403dc8d25bf58db4dd39ddab9c4ab73f3e	\\x0000000100010000
44	4	7	\\x7c801559c7c15a34799da70218730a8a2385a5e0bc00027dc417083b9040290cc785e14f49f6bbd86da60c1f6e874fba56fbfbad9f4e437917c91c791a59f306	144	\\x000000010000010034cd065b3622aa66020b575a8dcf18961228dcde1e27e2dc05239acd3a3b04b6c9c40eb213346a77d11fadafe455f2fdd7a527d86fb99925def75f5b467d024bbaa74b41febb55432373c52caa44ca685d9ee55123971fc39032b96cd8aefc8d67d7d01701311c577745589fad25f8f28b6975753785abadc93e6e4596d76db4	\\x346feadafc89b6c47592c5b04ecc9aef5e92fd395917a10ccc654f9ec861328b4d2caec2d0fbea66fcc74270f81f98184303c3730d370f4bb16d38d8176d30cd	\\x00000001000000011f3e56cc50f2f42b0a54ab0f426b88a1846b1c667ce35dfa7b3b9d938eb4d8cde17ad8e35b059f1cfdfab7c69eaa4119c4afc1f49a18c6226b7aeea4b06e3d5b424cb4aaa0144b01b8055777fdbd439118fb3d0051ea696cf90118ca1de50b8e351782700bcfc41f6b04f559b2dc3f2838887efefcb9dc251f98a7094b585d92	\\x0000000100010000
45	4	8	\\xb6fadea0ffe3bf778d1a5b1119e2f1e212839c4fd7b494acb2a9f269744abe65de226daacbfc5a7fcbf94297a4e064758d39a883da407185071b62c25cf25a04	144	\\x000000010000010099347f5c0effef2ac43f7d8f01679e020cf5435caebc08f21d09a28be84b9fe8f501cfb6fdb62b31198e359986a6331a7ef3d1011edfd87b0881226f5bbfaaefbaa16232543aa25e76adde95a17749a7ea4b2d0ad2f89ea0be5e2c63b3360121695b2d6433fd0ab2fae6ad94db21f12b7689442522bf66838e6247e2fa15dd2e	\\x78c66d1441fca54523f7585e3ad61518877fabfca7e7590e74c3e49decf52a1a0b55150b91eddcc896abf0e62b502188e30a60b74f5edaedc62c51dea670644a	\\x0000000100000001b58cb249369c435e7696e1f7c33ae9e16c23ab0a1c7e81cc141ebbbb60f33859a9fdcd841dda18dbe8c214c0c6b33f2862a2e7a7e8ffe85182065fb9f86cb66cfc44a732ddbb984f6f6e0447c1013bf25695f95f7d03abfc6dbae6003c054a05b6a6c160d769b2944c5d136958688e7b7a23816d20afa5c6069e999a56532e09	\\x0000000100010000
46	4	9	\\x0a986a5a9dfa2e6066833088d3482e2f17688b92b3e1d511bb39882f2cf7a91b31191aae2eb3df0665fcefc859dde42d55dd299ace074f50f245919a1b2a3f0d	180	\\x00000001000001006ae93a36fc5762dfc0796b95b80e3e99b3185cada8ba8eae9c518b82f9d085ca3a4a77d61b8bc7b567d00b6613f1a67d21200e1ba945c2ebbe354dde78f995a60ca5576616f23019b8c55788d8d290786f16bbf917f4fff50e767fa0297516109e044c49ed7f7b6fa7d6b5807d954785f14e5520613c0f553eb706677d37441c	\\xdadf893cdd4e7994c3ddd7eb4a8741190cdd9f5b475e981c746ab2dd50ea98dcaa8fd3d0112378b9a4b3b8e35c33b3e3634bbd05444b575a5beb15bf407bd8ef	\\x0000000100000001810acb81f99e9425b658326fa191be22dd74ef9ba566024c1f935eaa9b7a299770a33787c56c873c2c79219fac3b3dd1735bdd77f1639dc9f5a94e4b97000fd8f1623c94d22b8188183e18e45d81d47b08e13a7582545781b39a21b26693f3ce76a5cae005b048c0133e5303f2174eec4c743fa7c95e87a8a1cefd114b4ffa62	\\x0000000100010000
47	4	10	\\xb6c6838209318f054e9536fdb36197763c92363ecb2ce8d25ccb2e85fb156f481825f977f025d5fe8a84438154ea9eb3368fb9d2131568d6bb516f2da0586b0a	180	\\x000000010000010010f43e20fee12dac41acce81e76a5121e694e9e1a0dfef604a7bc49175c699df3f14e79e0496234f07781cc70a21440718122e930fcdcbc08b168daae1391a54996478318ffcb35f73b5babd57c9ade7225aa4786c9c46350405d449053fadcc05a66a1f82dca9d2f36263e3a5604f4e2cf9e5df6ce53ae666df023f196f23b7	\\x67b250ef1fb8e2ed66361ca96433a3184c57ffc07086fc6c1c86b6beb21e8728d3c3564a5b594d52255a66fe4389adf8269af0a6bf5aa2db492ed4445c48906b	\\x000000010000000187157f5c0816cd2f96fff9b504df4bff84a44ef36f6e12886a0598f47860a7caa7444548c6b64aa61f87cc75afee55890466ad2fee0a2624c01f5ab4b5f0a71d6fa5a3f591e6d5daaa5e790de7e7ee770abbad15352036b8048eeaa416f798ff6ebfeae9e871504490305884994224a9a36b7c150e69ceb901bedee0101a9741	\\x0000000100010000
48	4	11	\\x4cc55ff3d2b5e452df7543618fd8eafd26ccf78939f9cbbbbbb06ddd3526d2d740aa48313a357b3aa9d8ab98425297898f0313b8952c66d1bdc490fbc2b27508	180	\\x000000010000010025bd1bbb46a762a04ff1076c83e9bcb261a426c332c7de157e4a02aacc1fcf0c85a99eae9c220f0f589764fe7cba39cc577824720368a02fa0724e337dab6f80503ff275935f4ef31a8f96476ba58dcac89383f8af78f06c65c35071dfea392ae4b8214d4ea69d75c007314664517ebaa5b31a51f4f32149924e444f707f9079	\\xca12b460bbc67855358ce2526862fbc23d9714649b68301a072f24ed27839e206498ef33645074968128925cea11eb348b77c9e16545e7a61b6b584f9836c3c6	\\x000000010000000196ef585f9677f5cd17590765c4553554534645b55f93e47e186bbb185eb06b294123e6a6fa485b8ccf5d9f51bd709af8cbb9e7bb76cde0433f6f16bc0325683152c4589e39046f709447906a35ed7ed6c0bfc823c060752f833f8e642e7d34bdf465390034527756f5ad0f5e850e40d13d04d53814a1078100817ac4782fb04a	\\x0000000100010000
\.


--
-- Data for Name: refresh_transfer_keys_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.refresh_transfer_keys_default (rtc_serial, melt_serial_id, transfer_pub, transfer_privs) FROM stdin;
1	1	\\x3e6617cfa5f7fd5fb707efeca35a1f2819dbd04ff163a1fcd498756161cc8754	\\xf42a592ae013f73e0e23dfa5d291541daed1ad9064bb814d753daad942c79da3e9bf1c01f299a6e08d79e6ff82cd9988572b4437ee3ac4f5f9f5d0e2dc0549f7
2	2	\\xdaabc661cba865e5986efae9bfcf7bdb8a2a4ff8e6f91f3684a6c486c300957f	\\x364255bc1afbf5e7a67f9ddd25dc3ddd74b3d5ae32952b74cc498e2affe0c0efa8bf2b9cf0ae299539ac90f87f4971a7c58e747ea06f0cacda6efbeff67b4a1c
3	3	\\xfd6db2f71bda6981354b91c4fad6a8b8a18ba32ec7a3086c76d69b303b23844e	\\x186755ce7202be068c7bd825d4d7a297432e22ac6c30cabdfa2860c6fff113a5cbd51742fac7ff154e31635115a16f2b9ebb56bf76f3b153828b17a86b15d0d7
4	4	\\x0a1db88f4c686411a85f8de6475f233a12cf663c5e90d46d681d7fab043d6155	\\xae7933fc135739af6bf8254cfc20481a0040756ac3360765d13eabc68556fe92d7a34e0e157b1d912d24ea7003fe46a35e00aaa8f85cd9213a35e2a890c74a87
\.


--
-- Data for Name: refunds_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.refunds_default (refund_serial_id, coin_pub, deposit_serial_id, merchant_sig, rtransaction_id, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\x97c9d64d2343c7b00b1ad1f3a9baf4647b72a8ed358a7ca098cc04cbaeb80a22	2	\\x4a02514a1c0a9e10360b9bd914bb5c8d9cd1478d91913bf73381506205d864f980e1ee5c2bb9944cc1b4a8261c31d3cadb690fb6f90c86f4135809509412df06	1	6	0
\.


--
-- Data for Name: reserves_close_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.reserves_close_default (close_uuid, reserve_pub, execution_date, wtid, wire_target_h_payto, amount_val, amount_frac, closing_fee_val, closing_fee_frac) FROM stdin;
\.


--
-- Data for Name: reserves_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.reserves_default (reserve_uuid, reserve_pub, current_balance_val, current_balance_frac, purses_active, purses_allowed, kyc_required, kyc_passed, max_age, expiration_date, gc_date) FROM stdin;
1	\\x2d6f3209ccd411a35ecc466174626a16658fc4271bcefbc4b4dd5d905d8a07c5	0	1000000	0	0	f	f	120	1662910255000000	1881243057000000
7	\\x9de5702966633a84914d39a60c59c99b659bbfa89a850260a38bca9a8e539716	0	1000000	0	0	f	f	120	1662910263000000	1881243065000000
\.


--
-- Data for Name: reserves_in_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.reserves_in_default (reserve_in_serial_id, reserve_pub, wire_reference, credit_val, credit_frac, wire_source_h_payto, exchange_account_section, execution_date) FROM stdin;
1	\\x2d6f3209ccd411a35ecc466174626a16658fc4271bcefbc4b4dd5d905d8a07c5	1	10	0	\\x9a1d2fcb4940524ded1447fa70f971afb1e47ea8dc1b28a9efa3ab2c601b3d75	exchange-account-1	1660491055000000
7	\\x9de5702966633a84914d39a60c59c99b659bbfa89a850260a38bca9a8e539716	2	18	0	\\xebc0f9cda39160f801fc3dd02aa4795eadcf3e014cae56d12856a186b0edf90d	exchange-account-1	1660491063000000
\.


--
-- Data for Name: reserves_out_by_reserve_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.reserves_out_by_reserve_default (reserve_uuid, h_blind_ev) FROM stdin;
1	\\xb820d9df7f667de9d9964d19a7ebb16c1878667133ebe50771930fa7f9f6c7b6b9d26c949d52f754783a449b536d963e37fbc6709710cc3ced17b7e0869d1752
1	\\x9d2c65230033ef742cd191430400a476bad6c88d3d13e930abeadab5ec25b9d239c519d6ab4fa2757930b73067f42c9a02012f08b47ff3d3960d8eda02eb0fe2
1	\\xf713e140fb291306a23d67c60739da95bad98328dd7957e8db8c9e0f34b7691138788e3cd6b4a06ef19f8963583ec6e1bfb341f94b44077174699888bad560aa
1	\\xc7a9096795a357afe0256ca2e4ee16e22af034d38045c5ce752b91ab41b551dc07560731b38c385a7b61e3c152b0ef31cbb4e6ee27d3e2e092dcc683d7734087
1	\\x517cfbaa2c8b4f0cbe1342ee721c52a9d49db6a83bc9465eb2c4266416b59b5787783ec7dfde957dbf04a7be6cf1440da50e4cfe72973301f2c5578bbc2b58b8
1	\\xf6faac9705731e9cf62588ee0f8484c445a51c66733b3c66c157a65aa10959b251745c268f88dafae5dc3f3df9c63acdbfb47dce16805b0ceab6da5b32ee5697
1	\\x63c3943c3b96ca16fb82fee5696d716ea3eba58fef8ff73431352aa60cc99e7c2995343027d72efed7ddb97556bda2ff1a21ee018ea2f32262ae793649bdb65f
1	\\x276f0da4ab97dc11475be40bb54e299bfa25fefca5be2dea62aa874cdaabdd108cec537d92913149608acba218947aebdca6ad479418bd564a6a59249460dbb4
1	\\x5e289e65c94acc6d4142852a0642de037bb9b988555323ea53d78f9b13072898af55eab6aeaa4dcaa8ca4ce952dae504252b4809466603beb0e010c94babd409
1	\\xaeb9de225399d68df653cd441c7110caf3a18d34951df70b48ac0f90de91be6b00e60224d6973d005d12e25046438418c9769e83a3d46ecb4c442d8c51ca791b
1	\\x99ae0ea82cd3b37861a5c04adebd27efa691aab900850a4cbb2c7cc8dc4780490e881f494ef97c12045ec7a215cfd0f85a59e1d41cd0fec43ca4c59c268d14b5
1	\\xfa977cfe8dc8e57e74d462b35515204fdfbdb85be5065ea90dc957f595f2500cc73427c476f2e50cd92869c182d0b1bf9d9bcd35935a111ce2bfdef72872b0f3
7	\\x3b0971f537ee6ff8407e0cfe39dbebfba458d782c5666d27a54ce887280be91cbe456097c521845f08cefdccb29fe1b10b2db3b48542988fc2a96641d84dc980
7	\\x453616b972433d9d3a101628c79096b874627ccd537a4392342c1e099bdc2fa8a952781c15e5490b0e0fabd561fb31e463094f92a378ceb1bb5e0c28cf1ebc1d
7	\\x54b34cde2dc2a0df0dd8f49b94cca75be20716abae619fff0e255d26a857e807837132758522b7a459e9b1780e4fb117e8a4ea3e6b026de208c846be7423f99a
7	\\x3504c39c52bb1b422b5f5a1df4bed0f580aeb426c89923c073272b63c373350e95843e2b1c01f877f8964444ba09e8f74f215d6276286fcbdf6eb1e2d998428b
7	\\x3e910588ef537898bed2fb2fd4d6691dbae0e4ea45eb73dce00b5626c983498934f1eb6902628f376b50c9fda24a7e454528b1db27e4ed97be1ce018803afb3b
7	\\x4f4dc75066f36a574491bc9aa387181b82276e8db1d31f82adcbf289afb1b10dd4055f844d6aead4a19666886d7809ec2d7a3e9774e7fc0298f640efcbc04798
7	\\x06e734a8884f00916a158ab30c80f735f9f50692f34d68a0cc536d2129877c354adaee272b5bda33f6f52f356df16ff8bd3c926ba07eae448e619280e2d329fe
7	\\x13cc6447eed4079257a9a9ca7ac658356ba5e7d25c196c34646746cbc68e0e69651a0471b2bda26b84ac262171b6579c6e694b2c8bb602ac8b275676d23d349d
7	\\x2f3b1861bad96f2b7749a1a972903ccf4de7066a113580d2d574361162a7a87c1e124fcefbbe5c91f8ea3c88c03b6e7405b06de5d040f57dd2303abc90ba1472
7	\\x262be7e784d95d486d39d285fa60b6d620fba401ac0603cd98b1e950579041b4835d6ad531f7981be7722fc9cad01e1022c29385543d67d10ce6d42e454a3b99
7	\\xc6bcd74fa1246ef173494709020533c5c3d30146c693271493c52168d3079e59f5b9df49e6a36f40a57af86cfeeaedd7c399dfc4c0c0798ee07a1936e0597c9c
7	\\xa71c8844a5031a14e12fa5200119aaf871fb5f8181dd9d8823cc5fa72151e18b6f5c38cf1ec9fd0bc622b873ef391e60ec2b84504811e8968cf5a32d87c0016f
7	\\x3908c3b01690c3dc724c82ddf9e94961b6dc4681c595293521994d22daa7c4264fd51b9772a91820eb8a853f96b7310c137ba0ca06392a0c4bd6a2d21c8d75c1
7	\\x4e70bc39030666ef46121ed49fc17933573eafc29b7caf9e483feaac26c73d3e93000a6c97ba745ef8c990d7514e7a222ec4e45517b6f66ca5f8aa38c59687e1
\.


--
-- Data for Name: reserves_out_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.reserves_out_default (reserve_out_serial_id, h_blind_ev, denominations_serial, denom_sig, reserve_uuid, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\xb820d9df7f667de9d9964d19a7ebb16c1878667133ebe50771930fa7f9f6c7b6b9d26c949d52f754783a449b536d963e37fbc6709710cc3ced17b7e0869d1752	313	\\x0000000100000001b7fdf01fe91b24498d75f227f568f57799fe7fae04290535c510634e2c02902c3aaea760eb12727caa1f6b87714fd2a245cfc89045e1d429c0ea575286a1292321fa4423d801b6639dc41b5c1f6edc5e5f1ed8d5e811a082b04a7e0303f8078f6904c11af2d7cf2a6d17afd7d1c35db4aeaad07aeeba0b6a75e926e61f9ca190	1	\\x9d76822b9aaf6349d40edc4c46aaab3bc96d96f3a271e6cd3699a44a1016fce627b077211c048c6951f7a7eb693c7a14103044fd82cb0eb82eebb88621e05006	1660491057000000	8	5000000
2	\\x9d2c65230033ef742cd191430400a476bad6c88d3d13e930abeadab5ec25b9d239c519d6ab4fa2757930b73067f42c9a02012f08b47ff3d3960d8eda02eb0fe2	270	\\x0000000100000001787974ee304dbfb805c7aac6114f6bbe2cd2d15225b80d86e264e18821eac71c137568c7204f4a40502ec8583eb019f8f0b41efbed5b249058afdf74bafb12475e1347f6d8905a8244682f1345136b2ae16cab698f198cc4669a898d07cacbf91e9b8ed77579e7221356c7d8b7f8fe3cc404fb909a360dabbf89abe210768bcf	1	\\x96ab0176faa7879e20f4495305dd4f2792b66a56587dcce8ae558d1e9fb550e92835c13721c324cf5449dc93a058ab6ed37f33b3954ab5bcff0402b1ddc97909	1660491057000000	1	2000000
3	\\xf713e140fb291306a23d67c60739da95bad98328dd7957e8db8c9e0f34b7691138788e3cd6b4a06ef19f8963583ec6e1bfb341f94b44077174699888bad560aa	144	\\x000000010000000117ec75f8a8338330b7754d55da48fdcfac8a6b9139591a5ff36474ab86f7e0cb6c98fe7a25bceb9b90fbf181373a68bb46539dfac5e3c656f466c29eaa6d633c6fe3938f1e4b39cfe44141dfc58a7c773e32dc87c703b4ee262e91dfc9eca2147eb04a2adad4b215ace3c6554547855a55300956b78550aa81ee1d364d651025	1	\\xbf878d9b1812247919375eb892941ebdd53544d7e182b35645825770616dda0fb161dac1a435297fcf6b8a1cfaac1b97c0d302ccbc5c57fee7ea060196afeb02	1660491057000000	0	11000000
4	\\xc7a9096795a357afe0256ca2e4ee16e22af034d38045c5ce752b91ab41b551dc07560731b38c385a7b61e3c152b0ef31cbb4e6ee27d3e2e092dcc683d7734087	144	\\x000000010000000155a59b8414935d99a18adaefbc3518fa425c039d192efbe13da524d35a5f07e70f8878e6c773edb98fd647a167cc5df0a61d64a857f861322416addecd719f0b50febc892feae02a5ecc1e69ead5c02875fd36b32f655f72e69b171f5c70e7e023e708e4f9a1b8134d54363e343bc309df94b3789978b1479a47aa1744b7a3af	1	\\xd10c31c007f709d25bbe4f38fdc44fc310ac2fca3af4872dfc3b69ec511af155fc5271ba38d7412e495de603cdd3f03b84c2de19017b36735509d8ce7c961e09	1660491057000000	0	11000000
5	\\x517cfbaa2c8b4f0cbe1342ee721c52a9d49db6a83bc9465eb2c4266416b59b5787783ec7dfde957dbf04a7be6cf1440da50e4cfe72973301f2c5578bbc2b58b8	144	\\x00000001000000019431b20b1474e3852620e9aa12e3d61317b9d3e4563571e59ac431304abfb1dc1563fef47e69e4722584d44b3f42ea0da089930beb287ae0f59e963001345792093e7936f1c3a10252b3ffce0d36c47a9837b1d360895b9db20f321afea7fd7ff158616e7e170cd77b7bda9fc512aa86a50fff3fb9410e34a0917bac6e786d60	1	\\xbcd98d34eed98a00c03b8782fe5900cc08b38a525f7d6396e3868749a830e485b5cd64a7719c942cf9783f704c280b1c826e9fee721dbac2b4b47d8c1b5a0106	1660491057000000	0	11000000
6	\\xf6faac9705731e9cf62588ee0f8484c445a51c66733b3c66c157a65aa10959b251745c268f88dafae5dc3f3df9c63acdbfb47dce16805b0ceab6da5b32ee5697	144	\\x000000010000000110b610ce49f147622e1358a29cbf57349b6e2621ffbee57c55e1ea72f161bc26676ebc0011138fbbe924786c15249fad48d0bd95728c57ed9f13b6e6898cb5edb938563863d5b1408c3030722c43cda5936dfeac67692152721027ddfd6fb136fb90fc2b60a8d80bdddc23a589286d7a3b82ecb948beef4b7b4de2e0946f2ac4	1	\\x852f3be26e29eb4d36e3130ca1d1df44e0449479a544da609a30e9bfa98b426322d103f373b606727a6628ef5cb6f8c95744061fd46d8f2cc6dde805cf492b0a	1660491057000000	0	11000000
7	\\x63c3943c3b96ca16fb82fee5696d716ea3eba58fef8ff73431352aa60cc99e7c2995343027d72efed7ddb97556bda2ff1a21ee018ea2f32262ae793649bdb65f	144	\\x000000010000000172dd15ad28301d6a445ce58f79114242dbd8ee956b6f3fdb24b85a8101b685e598127ef1b1a9abb4b6d9c3f18ff2790b4dae9e85797bd5590845089ee7bb5656f5b868638ceffd2a896e03f8606f0c48f0a53e2fe10b698efe4faf34450f9fc4ec83c6fcd3e2f862b833a0749f04af5e1f6292ee579d2ab3f58e1773287a6217	1	\\xb848e27af486f7dd8dde1688b2ad415387af985b1c421473d2902f901a65fe0fad86f01926bb7014f858a3359be73c39a8a00459c1931f098991e167c82b6205	1660491057000000	0	11000000
8	\\x276f0da4ab97dc11475be40bb54e299bfa25fefca5be2dea62aa874cdaabdd108cec537d92913149608acba218947aebdca6ad479418bd564a6a59249460dbb4	144	\\x000000010000000126874c11f4720b3f2af9b797dc44d1319a4e44786f069fd2d1be2d1dd0468a8cfc379158cf3e52ffebdf47dad9179ef4cb97ccf09965e70243429b67b9570dafde97ac23da3c60feeb8b06fb28abbf0825a338ae1dc366a61ea75a9d1a17ad74d4e5710a246589a981ae32754911fcd4a8d6b3dd745414178e93fe492d091161	1	\\xbc6cf6f37bb5a551de3230668ddc9facf1f5c85e4a9f541657c3749db659f232fdc74ae7af5f2ac58e9a492dc5f5385762e514fb95943172d65f2dd8f292ee05	1660491057000000	0	11000000
9	\\x5e289e65c94acc6d4142852a0642de037bb9b988555323ea53d78f9b13072898af55eab6aeaa4dcaa8ca4ce952dae504252b4809466603beb0e010c94babd409	144	\\x00000001000000019332afdc1a520ddf04942e4a50f067286cb4ef4364479a44790edb54142d39a0c117ae9fdda4aca8093dc8cc3546b6159f6a2f9f9c819a08aa9c6c5ab0e2baf822d7a9d80479173154eda6268a4e7c8e58a398c1721aa6757d2de79951b7aa7aab545a1b5546319d35fa179b098884824d9163040f54549a4f716ab8ddd0f532	1	\\xa9d5ccfc3ef5dd8aaa49777e81cbc2c5c9a96f3a2aa0eda59dd62626a2c4df786a6d13e5c5adaff541eb0fe2139dbfcbcc5b8a22bf6a694f1cb718383264950e	1660491057000000	0	11000000
10	\\xaeb9de225399d68df653cd441c7110caf3a18d34951df70b48ac0f90de91be6b00e60224d6973d005d12e25046438418c9769e83a3d46ecb4c442d8c51ca791b	144	\\x000000010000000119408b1b12614257ff37298e1a9b6866edaee4408e95e43d8509db5bf0e99205c732aed212eb22959e91b1aa67e0aaa458d7b70cc7d902cd31f27084eeb7b43f9dfb6ee3325fc0870dc756559aaa8fd2a0d1e02d8d9c754c062f8d003f2d5991452692aee6c81453792750b7deb41bc768ebc0db3084d57b1e9f21ecc07fc635	1	\\x9c913b449daa99284569c247acbe70d51fadea166ed0793b260e24fff9379b0eec9049371886b748db228ab136a88b889ab10b1ee9f282609146645b8e9f9509	1660491057000000	0	11000000
11	\\x99ae0ea82cd3b37861a5c04adebd27efa691aab900850a4cbb2c7cc8dc4780490e881f494ef97c12045ec7a215cfd0f85a59e1d41cd0fec43ca4c59c268d14b5	180	\\x0000000100000001603664e02e5a20c0f30c336a33840d26c786b03081a9c650ccf68c07614446814dea8450596429b87f644369accf63b8ee3460eab0672e60f81ec30ba46f4716dd1a610d23543458e58473d1054696868ec72306f2ff606233901b179b692c5a3e730d41db45b78725fa15a25e74902a311904c6ffd47fa1a9edd0b93aa2e702	1	\\xa8ac4448e90d66b407320cb1985d388514022e308a0420b1ce683d9b390641a37f6118000f7ece39ec506796ec56cecabedff09e28930261e2fb4adb02edf906	1660491057000000	0	2000000
12	\\xfa977cfe8dc8e57e74d462b35515204fdfbdb85be5065ea90dc957f595f2500cc73427c476f2e50cd92869c182d0b1bf9d9bcd35935a111ce2bfdef72872b0f3	180	\\x000000010000000195ae0064e1e0f54f48c24e135a14f5412a5d7dcd32f461bcbaf0f1e07e31fc5ceb97f7d595de3ac2295f0c445e08762bdf8fdf22c1e5296c147458134c52c20e0684a6326e5fd73b286a2a6f347e8ffb8f4d86a856125a133d7c81711f87b299d31b61d471cf9a6efd32ba06f41c9bff3971df8f141f26cef17a300afc1332d1	1	\\x3b94070534bd60cb0acc214cc7cf2f17108ad7f90fa282f343599422b41b452945dcc96bb66878283eced8bcab2cc706e7b6a5a49bdde27ed8642cb002d09a06	1660491057000000	0	2000000
13	\\x3b0971f537ee6ff8407e0cfe39dbebfba458d782c5666d27a54ce887280be91cbe456097c521845f08cefdccb29fe1b10b2db3b48542988fc2a96641d84dc980	190	\\x0000000100000001a63387b589c3446681120c4a8cb252adc04892a8cffd05c223041bcdf88bd5d6117be7324ef7bc0cb38455ab2ae5d335c7fd6fa8ebb305b07af7ba6a9c3a509b8491ba676ab85071a4cd6c640699161f5f57f41a235af1daa35705b362d92915fc74fcef540a92674cd9905f353a8db7ebb1b5febe45f9af90c8f35df4dab327	7	\\x0376bd047a7e0e85068652cec24b13049b214d1e6b1ca01d273bd86e52a582e6b697f03dffe81c6eb2015fe7ea6c24ecb34fd1cce040662a436e7d90288bd008	1660491065000000	10	1000000
14	\\x453616b972433d9d3a101628c79096b874627ccd537a4392342c1e099bdc2fa8a952781c15e5490b0e0fabd561fb31e463094f92a378ceb1bb5e0c28cf1ebc1d	256	\\x0000000100000001757a899707c8d3508c7c042586686d3b95c5882869194a0555658defcda50d79e740bdfd35c0aff6ba431b49e4369cf38ec5635062333e86239b007f8cb704fccf3a439f4ae7a10a8dc9128feff2829a7c56da4899f53031641467e488a31de7da80a59b9a3a1aee9a7acb2db5a8a2c99a8437816e172fa4b50e4c135051faed	7	\\x1310a37ee3cf58794a027af485219c5e6741474c9e4dab9ca6e27700b9f3b1c3072588d4e12c4bee6fc0630de8e56564687edd20c201591c17384002224c6805	1660491065000000	5	1000000
15	\\x54b34cde2dc2a0df0dd8f49b94cca75be20716abae619fff0e255d26a857e807837132758522b7a459e9b1780e4fb117e8a4ea3e6b026de208c846be7423f99a	205	\\x00000001000000013122287eb387ce5b8fb2252794f3c32ed875a2cd0f56438766fc55cf9ba1fd34f79a3506184222ce3194e9235bf69d4a60de751582a5cde6e7bdebb9dde64ba8e8da68d5492d30e4cc7b30cd814b5f1d062c504028a7e600eefc8e2ac24b22f38dd5f18e6abecd1e1b5091ba37230b07f819900182480a3ef18180c9c498fba3	7	\\xd4c515925b040506d19850f26e590c4ffd8063f4b513cf5b688434bd52c3836ec8cadae33311293ba448d44bcc36cb725e3f682b9c10bb254069487c423ed704	1660491065000000	2	3000000
16	\\x3504c39c52bb1b422b5f5a1df4bed0f580aeb426c89923c073272b63c373350e95843e2b1c01f877f8964444ba09e8f74f215d6276286fcbdf6eb1e2d998428b	144	\\x00000001000000016d88e400bd012e06be89815bdea30ff8bbffed48d547e11b3eff610848f94d6d58d26cebeefbfb3b08b8239d163ebcd9642271dbeb1382ca384e6e6999df87508c447918c445b021ea2a9a7a544869c78831d72cccb9a1613745b8559aa586aceea922b623b9029053bf11e588df2f8d2e62f480f1945ae2192d4bcd18c9bc7a	7	\\x4b338254133f92626348f8be5b7b32e1fcef1f2e5a028868693cdb35e0a1df633894e9fb5a84a20aface983e97dc007ee79dea9e2676c7c6984917b0934aee05	1660491065000000	0	11000000
17	\\x3e910588ef537898bed2fb2fd4d6691dbae0e4ea45eb73dce00b5626c983498934f1eb6902628f376b50c9fda24a7e454528b1db27e4ed97be1ce018803afb3b	144	\\x0000000100000001779bee1bd362775d47e0369e56583ee358b3fb525c1a5156ff55d146695285023985f339641106dc64e85471e3c643d66b09271fbd2be188fb166d692b866ad45d64baf383cec2c691c1d8c6a788346aec3e6d9f366bca7a59a96bcf18b31c16e1506b46f6ece0dd7232a04de18a82f087e54c200b24dd9df80628bdb59a581d	7	\\xe461bd901440bc612f5ebf2b99d387f4fa3eda361601bd8e44da087c27f7cf2777d8ef5e4bae7db4662538f41006eea10dccc6dcad83f5546eaf2dab95cd640a	1660491065000000	0	11000000
18	\\x4f4dc75066f36a574491bc9aa387181b82276e8db1d31f82adcbf289afb1b10dd4055f844d6aead4a19666886d7809ec2d7a3e9774e7fc0298f640efcbc04798	144	\\x00000001000000012d97182f81c7f46b06dc7d2e07e587cf00ff17033b5b090aec44be35e298d4e1a0e2c3df19a6060b82df5e0c0fca8f11325a022797cf62453bd82d582d0fa5d95fc4b12ed8be74697838f198173de7b948fe04f0ce75d86fb5c05a4f7d1ffa0d53a5dfde1dd9fc96d49378eb24b31da2b4f244bdbdd25ec4cd8bab4f6296193a	7	\\xb44fe0e18ab9039839ad942c549b08d13d21397d1f90efe4e0b90a248e9d3b297822591c5246f68e23746aa83dcb88cefed3689661edc2e1ce2f93480866d00c	1660491065000000	0	11000000
19	\\x06e734a8884f00916a158ab30c80f735f9f50692f34d68a0cc536d2129877c354adaee272b5bda33f6f52f356df16ff8bd3c926ba07eae448e619280e2d329fe	144	\\x0000000100000001953b789c8837a28580d8e2bfcefff0a756cc91d5057e4e5a3420d7cebc179d15b6148cf1eab7c2590e38182ffd1255b4fbe786ab618aaa5006195cf730096cc3cf3485436e5d0f4ebf3e9fd6f41401db9c61cc2588198ad51d7502f39557bf4877f04aa6301e85e9ac34f3bed0143d2cf19c84cc8f91e541cc2a8461bef95693	7	\\x5774cf7c0e2ba9c939326c155323717636f6bb8d2168d5b247072bd835ba5322cda6d748edd3c28afc32611795044ee0bea039d54aa76587e3478964eabd3a05	1660491065000000	0	11000000
20	\\x13cc6447eed4079257a9a9ca7ac658356ba5e7d25c196c34646746cbc68e0e69651a0471b2bda26b84ac262171b6579c6e694b2c8bb602ac8b275676d23d349d	144	\\x00000001000000017adfa3a805777e77e7f7c2a0977e14f406399bcd98381fdd244312ef9e4574e2330d2b1b95affa0174c2d5fd503e13bad89c862fc510aa56368a2a62d5f922aa98d9f4824ec73ac0ce51b3ce8e9eae0395585e83c71cfe3a2a91ed03f8502ece282d770c89ba8618d653a8f6cf807afab826e81174c936c97571283b39fb74ee	7	\\x2aeb6c931ee89b96deb790f872e4e4c231723d5b429dfa5b4da3383289f551fb8cf722c9f2952866417283102152c03112c54218e498977d2fab6691230e6401	1660491065000000	0	11000000
21	\\x2f3b1861bad96f2b7749a1a972903ccf4de7066a113580d2d574361162a7a87c1e124fcefbbe5c91f8ea3c88c03b6e7405b06de5d040f57dd2303abc90ba1472	144	\\x00000001000000015f7b8525c4c65539e859b73c6efe970b5e35e3f993837e5712d25507d7655d5deacf182055d5d5f2ccd85f04e12a39b148b60386e4aaa0f3eff187a6ead5de7b58d0039fe219d1814b2a9dc848baadcc92b1f9fc4abee3acaf577d98b4b9d6bf91fbb2339112d26e91dc95eb6997e0c42e539368ce3aa210d40b7c1c1ee75ad5	7	\\x7599823c2351b962733be2e9e4120b63e71cee08853176bde7389d98f6137a35f3c5bb25b60ef370e45626b42f34e1a7115c8807acaef3e0699aad2520cbe90c	1660491065000000	0	11000000
22	\\x262be7e784d95d486d39d285fa60b6d620fba401ac0603cd98b1e950579041b4835d6ad531f7981be7722fc9cad01e1022c29385543d67d10ce6d42e454a3b99	144	\\x0000000100000001cd3498127a94f8bc646062ad35cf16108b4aec3fb443d7d5c2a6b654f25a9cb3d6deaed9299652c9f13b6f5fe22a5827d64a6006478114ed6355d088ac1fa1a4ca4873ce1ba8f857fda0df41fbbb587e37533b9966daad874c135e0e746407882ebf5a09b3965dbaaf72b2da3b1f3d311c5af75a6714e7997f45a59f4cb76630	7	\\xa58a8c5538a34c72d273b49c126785a687f69e338c1cc8d2d5e22811567e4ffb0ff48aac5fc5f78ab050d81013289a012535d15fbe007f61a9e7300cb09cec0b	1660491065000000	0	11000000
23	\\xc6bcd74fa1246ef173494709020533c5c3d30146c693271493c52168d3079e59f5b9df49e6a36f40a57af86cfeeaedd7c399dfc4c0c0798ee07a1936e0597c9c	144	\\x0000000100000001091ed6c06fc61b35ba4a09b33fd72d007b9e0e03bfcc64b1db53db732b47804e9975962c4fdf6e18a78c49f55dc95a8312a1aa241bf2f37ed40d15c35618bab60d10342dfbfda0a9dd8816089001e1df13a0dc4e43177ca5f8c1904f910ff199e721161f32702a2ee453932d0e7fb0121ec40427d8e7c3f683975fe49c69af52	7	\\xdc4979b528161f88b061c8ac222f0094a9aba5ae8b7df6a62d55b75b18c0b62e6b5a1150ad055715466c946ef96805e07cdf390ea636851d1993c199d6132103	1660491065000000	0	11000000
24	\\xa71c8844a5031a14e12fa5200119aaf871fb5f8181dd9d8823cc5fa72151e18b6f5c38cf1ec9fd0bc622b873ef391e60ec2b84504811e8968cf5a32d87c0016f	180	\\x000000010000000158c5758b41429ae53d7c1688015dbfc46638e0c88074f9c2918ef59a6d489dcca3ddb684944f6da2b4e9eb0911554a9404822e24f548a27b195c68a545bf34d23953a3e2b8fb14ee86ec9f947c1f1721fc15a47cef59ff9394fd75e560889482ccb901812e84c35a712b946ee884b3d619a7ba5d4354f5ca4bab9cac98a82de7	7	\\x02823e6ee00ea28d1c175840371875ca09a0b6d48d1bafa0856f7150891940c11d25c706cbb323be0103a7695557c61aa7f4f373daf50246b6cfa3582eaeef06	1660491065000000	0	2000000
25	\\x3908c3b01690c3dc724c82ddf9e94961b6dc4681c595293521994d22daa7c4264fd51b9772a91820eb8a853f96b7310c137ba0ca06392a0c4bd6a2d21c8d75c1	180	\\x000000010000000193b7c58a82a3520af58c48fd9bf78b4727f7e9bab3d9bb6e28a2800e1fd062204dcd5dd249f8dfb03e0f78e645dec813c70681213259a0da4907af78198d8809bc421301c94c594070fab4db9e642b66376285e9224a4ff7fbcc1aeedf0e138eed8c0a12af0d384819eb386085e3528313541452b9f069b0ecbbb638340d0636	7	\\xf917c8f24b6165a3894534c52fe44409d244dff6cd67fd7e1ede6ab0eae173020bd7e5e0a41dd89f8a9f49735779a983d4509639d26aa10975cf168854773c02	1660491065000000	0	2000000
26	\\x4e70bc39030666ef46121ed49fc17933573eafc29b7caf9e483feaac26c73d3e93000a6c97ba745ef8c990d7514e7a222ec4e45517b6f66ca5f8aa38c59687e1	180	\\x000000010000000177c80a07b59f131220d4f7da086ba5fcfff6b484afa2faabbebf440ce534cd3294b3f94154ea351cf8d5718cf96baa9cf572b40db9d8a816a84d3749edcc0ad3b44bddde8e483d7fe5e742aac6583a17240b1ced4f0aecb7b0077a760baede434c9cf6c06467924e54b41a4a3344c7f7f272499763bf67359b553720544b234d	7	\\xca5e31a9abb284155f7322d1e5a19a332658b5414ab5355685872467483b89eb02332ff4837a2a264eed558f550f52771ee4750cf40c8442ee392610bb460704	1660491065000000	0	2000000
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
payto://iban/SANDBOXX/DE128580?receiver-name=Exchange+Company	\\x849473fcd5e7a9d1a1cd38d4f8d2e168ef82f9d5309c25a186fe08ebdea9291e96c04b0dbc9f655c3df63d34628bcfee16a58bb0014cd2fc5d327f51ed53fb02	t	1660491048000000
\.


--
-- Data for Name: wire_fee; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.wire_fee (wire_fee_serial, wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, wad_fee_val, wad_fee_frac, master_sig) FROM stdin;
1	iban	1640995200000000	1672531200000000	0	7000000	0	1000000	0	1000000	\\x9199e6475462af17a46597dce863eab2c070b2141279437ff4f354e2280424de76ddbaade8efa2258a47441f4b9bff7257dda2469693abf9d4169cb53b1c7500
\.


--
-- Data for Name: wire_out_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.wire_out_default (wireout_uuid, execution_date, wtid_raw, wire_target_h_payto, exchange_account_section, amount_val, amount_frac) FROM stdin;
\.


--
-- Data for Name: wire_targets_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.wire_targets_default (wire_target_serial_id, wire_target_h_payto, payto_uri, kyc_ok, external_id) FROM stdin;
1	\\x9a1d2fcb4940524ded1447fa70f971afb1e47ea8dc1b28a9efa3ab2c601b3d75	payto://iban/SANDBOXX/DE540064?receiver-name=Name+unknown	f	\N
2	\\xd31e3f48cb5318906dbbb7948326362f41604c7a728323230ae82aa995f27400	payto://iban/SANDBOXX/DE474361?receiver-name=Merchant43	f	\N
3	\\xebc0f9cda39160f801fc3dd02aa4795eadcf3e014cae56d12856a186b0edf90d	payto://iban/SANDBOXX/DE960957?receiver-name=Name+unknown	f	\N
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
1	1	\\xdfb98cb792522377a6ebe11a680c45ab3fc5072b412217ffc4937047441ae1c58d3797353244113f1b8b8062833eaefede373b9c708888a1be6dad568ab35708	\\x07113881c944fbf4f103ce7aa7d7a571	payto://iban/SANDBOXX/DE474361?receiver-name=Merchant43	t
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_contract_terms (order_serial, merchant_serial, order_id, contract_terms, h_contract_terms, creation_time, pay_deadline, refund_deadline, paid, wired, fulfillment_url, session_id, claim_token) FROM stdin;
1	1	2022.226-00WE1ZZ83FR7Y	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f73223a313636303439313935377d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313636303439313935377d2c2270726f6475637473223a5b5d2c22685f77697265223a22565957525344574a413848514639514257344436473332354e435a574131534238344831465a59344a445234454830545737325254445751364d53343834395a3345355230524d33375451465851485137454537313234384d365a36564241504841534e453230222c22776972655f6d6574686f64223a226962616e222c226f726465725f6964223a22323032322e3232362d30305745315a5a383346523759222c2274696d657374616d70223a7b22745f73223a313636303439313035377d2c227061795f646561646c696e65223a7b22745f73223a313636303439343635377d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2245484244375357353659354b4431565437595653574a334d4d42375a4e41535845344e4d45474538324438525a34313347575230227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a2233334d4d514441583656485744564a3443545632513154444e5041334e4a36465032374b3938373037324e313046583647385430222c226e6f6e6365223a2254575a4e4b48535338325a4a565339455633435252374132375a4b43313439353652453653414a38475953534b564b3338524a47227d	\\x7bb482ff31e4c110c5df76992783d436d27502966372065e8c842c869146d35bd2f01c6fae3c691cb7697d3385c6d57d752233c0f0c33e6e92b78807673746f9	1660491057000000	1660494657000000	1660491957000000	t	f	taler://fulfillment-success/thx		\\x0047ebd5d84d5bdfbe5ad9571fe57657
2	1	2022.226-03WFC4ANFKXRG	\\x7b22616d6f756e74223a22544553544b55444f533a37222c2273756d6d617279223a226f7264657220746861742077696c6c20626520726566756e646564222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f73223a313636303439313936357d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313636303439313936357d2c2270726f6475637473223a5b5d2c22685f77697265223a22565957525344574a413848514639514257344436473332354e435a574131534238344831465a59344a445234454830545737325254445751364d53343834395a3345355230524d33375451465851485137454537313234384d365a36564241504841534e453230222c22776972655f6d6574686f64223a226962616e222c226f726465725f6964223a22323032322e3232362d303357464334414e464b585247222c2274696d657374616d70223a7b22745f73223a313636303439313036357d2c227061795f646561646c696e65223a7b22745f73223a313636303439343636357d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2245484244375357353659354b4431565437595653574a334d4d42375a4e41535845344e4d45474538324438525a34313347575230227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a2233334d4d514441583656485744564a3443545632513154444e5041334e4a36465032374b3938373037324e313046583647385430222c226e6f6e6365223a22484653474a4d573737445151344e34523657365041583944424b48434d59593848354d5448545a315048564e394d384158464547227d	\\xaedc874f4eb27cf94b0e7d7411c7b4b8d456fce3356cf458db561dfe18482da07e2ac9d15128d32d4ec20909b3e73577e66cc0a80cc3f12bc25a78185a22b498	1660491065000000	1660494665000000	1660491965000000	t	f	taler://fulfillment-success/thx		\\x97bcf182aa7d7c72e57a7aaf9fabe664
3	1	2022.226-0087ES0SH0XV4	\\x7b22616d6f756e74223a22544553544b55444f533a33222c2273756d6d617279223a227061796d656e7420616674657220726566756e64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f73223a313636303439313937317d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313636303439313937317d2c2270726f6475637473223a5b5d2c22685f77697265223a22565957525344574a413848514639514257344436473332354e435a574131534238344831465a59344a445234454830545737325254445751364d53343834395a3345355230524d33375451465851485137454537313234384d365a36564241504841534e453230222c22776972655f6d6574686f64223a226962616e222c226f726465725f6964223a22323032322e3232362d30303837455330534830585634222c2274696d657374616d70223a7b22745f73223a313636303439313037317d2c227061795f646561646c696e65223a7b22745f73223a313636303439343637317d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2245484244375357353659354b4431565437595653574a334d4d42375a4e41535845344e4d45474538324438525a34313347575230227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a2233334d4d514441583656485744564a3443545632513154444e5041334e4a36465032374b3938373037324e313046583647385430222c226e6f6e6365223a225959484356384251564337324b383541475a4b464751325243513454384a5752395043513748445233353352355a304748423130227d	\\x12b6d6092ae75562297bceb4d44f4f7f788b39c141b5dd1b4e725e01429e32d2b6439bee7ecf1f31d95a5e871f2b36a0ee2141f8339e38d56bbb9d9016185aba	1660491071000000	1660494671000000	1660491971000000	t	f	taler://fulfillment-success/thx		\\x4ab6a6a9348574ad99d0df5e562e5353
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
1	1	1660491059000000	\\x93bc00543ac62e3bddcfc7f9d774a144366080c86abd5286a5901bafc1645a80	http://localhost:8081/	4	0	0	2000000	0	4000000	0	7000000	5	\\xba223f3847fa482c20892a262f8e2fe2760decf777aad28215abf38ba8d74ee208ecaf6bbc63a804f4ab875f3f137b90fd362e21494e640fd1dc78c01e77af06	1
2	2	1660491067000000	\\x97c9d64d2343c7b00b1ad1f3a9baf4647b72a8ed358a7ca098cc04cbaeb80a22	http://localhost:8081/	7	0	0	1000000	0	1000000	0	7000000	5	\\xaff0d6a6783b40fb2cd0651049b1abdb42f799c82f99c6a2fdf196fa7363d22ef83d9ac764daad889c2fa53f3ed643082812b82cc3432aad4a1b935475d31f0a	1
3	3	1660491073000000	\\x336f8a0de6612a61308d2b4c759f3ec350ce2bfd8dc31fd6f1f097bdd1afe9ac	http://localhost:8081/	3	0	0	1000000	0	1000000	0	7000000	5	\\x6518ffdbaf6c38001256f4a468840ed9d53c4589d05a1ef2e937e4e632d661fdbae2a98c54af10583524b92893077cd5e3c53c95797aab984eb2586496e5f208	1
\.


--
-- Data for Name: merchant_exchange_signing_keys; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_exchange_signing_keys (signkey_serial, master_pub, exchange_pub, start_date, expire_date, end_date, master_sig) FROM stdin;
1	\\x7456d3e785378b36877a3fb79e4874a2cffaab3d712b4741c813518f90238730	\\xa4add2d2b5c8483fe42c8f4117b9174205d51eeae03890a9caa0df4cebe85bb2	1675005641000000	1682263241000000	1684682441000000	\\x11954245d38fdc2b3685b11a5e0eb4098c99af6b3cb93bea887f67f8624b8f2cb0234c30f457c08075880a1f1e0aea30cf2df2fa5682f51cda854fd0bf56d608
2	\\x7456d3e785378b36877a3fb79e4874a2cffaab3d712b4741c813518f90238730	\\xf1393852d69f2e4ba6685d4c4871fc86cf0890112eb792098f1d189cd462aa04	1667748341000000	1675005941000000	1677425141000000	\\xeb009a00a47b94dd4f9492eaadef2b47eebfca8b69377292c536216c99420776b60da0fd5afe4646e9610f6a55e924fa3e0ee59bf3a66a9d7409f04a78c54907
3	\\x7456d3e785378b36877a3fb79e4874a2cffaab3d712b4741c813518f90238730	\\x53bb828fde927d2164092835a5544b8897d7a5920fb83e1c6a906caf40d26767	1689520241000000	1696777841000000	1699197041000000	\\x568111a2e362807abc7357d7d07b0472008afb20001a1952563ea20b9802f3dac3c87f288a8320a9a4e423db027b351d612f73c510b72b8c22c68b9e3f9c1402
4	\\x7456d3e785378b36877a3fb79e4874a2cffaab3d712b4741c813518f90238730	\\xd4603c590f1e51a911f1b289877208db5550687d77c4c212b6a395d1bf3d385f	1682262941000000	1689520541000000	1691939741000000	\\x832091a952da688dbe9b754e1dc52dbe3bfe826534ef8a8ee8f4203c317c8819c022b98d706f849c3af234170a67d649648601136e798fc4ce46d97db35cb008
5	\\x7456d3e785378b36877a3fb79e4874a2cffaab3d712b4741c813518f90238730	\\x984c4fb720a52825c61287a4209ef9613b83d64899a087cfb8035a087a06b956	1660491041000000	1667748641000000	1670167841000000	\\x57467a297a789c5cda4ca565d93fa956cfc0d0cb8cac9efe16fbf59db5659836a17197738a2085d558cdd392c2c114955c7c91e5d05957f5c4e96819783b560f
\.


--
-- Data for Name: merchant_exchange_wire_fees; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_exchange_wire_fees (wirefee_serial, master_pub, h_wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, wad_fee_val, wad_fee_frac, master_sig) FROM stdin;
1	\\x7456d3e785378b36877a3fb79e4874a2cffaab3d712b4741c813518f90238730	\\x21e4a5e9d5d17432fa0b1f7a02f8047c7634c1053d6aa1f6456ac134caa8bbf3da7776a78f85636af980472afd166b4edad654979a89d92c49a4ba992a7e3571	1640995200000000	1672531200000000	0	7000000	0	1000000	0	1000000	\\x9199e6475462af17a46597dce863eab2c070b2141279437ff4f354e2280424de76ddbaade8efa2258a47441f4b9bff7257dda2469693abf9d4169cb53b1c7500
\.


--
-- Data for Name: merchant_instances; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_instances (merchant_serial, merchant_pub, auth_hash, auth_salt, merchant_id, merchant_name, address, jurisdiction, default_max_deposit_fee_val, default_max_deposit_fee_frac, default_max_wire_fee_val, default_max_wire_fee_frac, default_wire_fee_amortization, default_wire_transfer_delay, default_pay_delay, website, email, logo) FROM stdin;
1	\\x18e94bb55d36e3c6ee4466b62b874dad943ac8cfb08f34a0e038aa103fa68234	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x0000000000000000000000000000000000000000000000000000000000000000	default	default	\\x7b7d	\\x7b7d	1	0	1	0	1	3600000000	3600000000	\N	\N	\N
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
\\x546a1d3946f1e2f027a7b669f40e6aa3654295fe0f20bf79147b4dc4d5da164b	1
\.


--
-- Data for Name: merchant_kyc; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_kyc (kyc_serial_id, kyc_timestamp, kyc_ok, exchange_sig, exchange_pub, exchange_kyc_serial, account_serial, exchange_url) FROM stdin;
1	1660491059000000	f	\N	\N	0	1	http://localhost:8081/
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
1	\\x47cf6636971defddffe68ece80d1caa4135dc3fd5a0097dfda671ca5013c934d94a3fefd3adc2a91a85bde9af63b26bc6b68ff76716812da9e39412f682bb604	5
\.


--
-- Data for Name: merchant_refunds; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_refunds (refund_serial, order_serial, rtransaction_id, refund_timestamp, coin_pub, reason, refund_amount_val, refund_amount_frac) FROM stdin;
1	2	1	1660491068000000	\\x97c9d64d2343c7b00b1ad1f3a9baf4647b72a8ed358a7ca098cc04cbaeb80a22	test refund	6	0
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

SELECT pg_catalog.setval('exchange.reserves_in_reserve_in_serial_id_seq', 15, true);


--
-- Name: reserves_out_reserve_out_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.reserves_out_reserve_out_serial_id_seq', 26, true);


--
-- Name: reserves_reserve_uuid_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.reserves_reserve_uuid_seq', 15, true);


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

SELECT pg_catalog.setval('exchange.wire_targets_wire_target_serial_id_seq', 5, true);


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

