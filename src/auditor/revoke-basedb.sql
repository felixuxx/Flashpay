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
      ',h_payto BYTEA NOT NULL CHECK (LENGTH(h_payto)=64)'
      ',expiration_time INT8 NOT NULL DEFAULT (0)'
      ',provider_section VARCHAR NOT NULL'
      ',provider_user_id VARCHAR DEFAULT NULL'
      ',provider_legitimization_id VARCHAR DEFAULT NULL'
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

CREATE FUNCTION exchange.exchange_do_batch_withdraw(amount_val bigint, amount_frac integer, rpub bytea, now bigint, min_reserve_gc bigint, OUT reserve_found boolean, OUT balance_ok boolean, OUT kycok boolean, OUT account_uuid bigint, OUT ruuid bigint) RETURNS record
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
--   FROM exchange.reserves_in
--   JOIN wire_targets ON (wire_source_h_payto = wire_target_h_payto)
--  WHERE reserve_pub=rpub
--  LIMIT 1; -- limit 1 should not be required (without p2p transfers)

WITH my_reserves_in AS materialized (
  SELECT wire_source_h_payto
  FROM exchange.reserves_in
  WHERE reserve_pub=rpub
)
SELECT
  kyc_ok
  ,wire_target_serial_id
INTO
  kycok
  ,account_uuid
FROM exchange.wire_targets
  WHERE wire_target_h_payto = (
    SELECT wire_source_h_payto
      FROM my_reserves_in
  );

END $$;


--
-- Name: FUNCTION exchange_do_batch_withdraw(amount_val bigint, amount_frac integer, rpub bytea, now bigint, min_reserve_gc bigint, OUT reserve_found boolean, OUT balance_ok boolean, OUT kycok boolean, OUT account_uuid bigint, OUT ruuid bigint); Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON FUNCTION exchange.exchange_do_batch_withdraw(amount_val bigint, amount_frac integer, rpub bytea, now bigint, min_reserve_gc bigint, OUT reserve_found boolean, OUT balance_ok boolean, OUT kycok boolean, OUT account_uuid bigint, OUT ruuid bigint) IS 'Checks whether the reserve has sufficient balance for a withdraw operation (or the request is repeated and was previously approved) and if so updates the database with the result. Excludes storing the planchets.';


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
-- Name: exchange_do_purse_merge(bytea, bytea, bigint, bytea, character varying, bytea, bytea, boolean); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.exchange_do_purse_merge(in_purse_pub bytea, in_merge_sig bytea, in_merge_timestamp bigint, in_reserve_sig bytea, in_partner_url character varying, in_reserve_pub bytea, in_wallet_h_payto bytea, in_require_kyc boolean, OUT out_no_partner boolean, OUT out_no_balance boolean, OUT out_no_kyc boolean, OUT out_no_reserve boolean, OUT out_conflict boolean) RETURNS record
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
  FROM exchange.purse_requests
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
    FROM exchange.reserves
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
-- Name: FUNCTION exchange_do_purse_merge(in_purse_pub bytea, in_merge_sig bytea, in_merge_timestamp bigint, in_reserve_sig bytea, in_partner_url character varying, in_reserve_pub bytea, in_wallet_h_payto bytea, in_require_kyc boolean, OUT out_no_partner boolean, OUT out_no_balance boolean, OUT out_no_kyc boolean, OUT out_no_reserve boolean, OUT out_conflict boolean); Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON FUNCTION exchange.exchange_do_purse_merge(in_purse_pub bytea, in_merge_sig bytea, in_merge_timestamp bigint, in_reserve_sig bytea, in_partner_url character varying, in_reserve_pub bytea, in_wallet_h_payto bytea, in_require_kyc boolean, OUT out_no_partner boolean, OUT out_no_balance boolean, OUT out_no_kyc boolean, OUT out_no_reserve boolean, OUT out_conflict boolean) IS 'Checks that the partner exists, the purse has not been merged with a different reserve and that the purse is full. If so, persists the merge data and either merges the purse with the reserve or marks it as ready for the taler-exchange-router. Caller MUST abort the transaction on failures so as to not persist data by accident.';


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
-- Name: exchange_do_reserve_purse(bytea, bytea, bigint, bytea, boolean, bigint, integer, bytea, bytea, boolean); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.exchange_do_reserve_purse(in_purse_pub bytea, in_merge_sig bytea, in_merge_timestamp bigint, in_reserve_sig bytea, in_reserve_quota boolean, in_purse_fee_val bigint, in_purse_fee_frac integer, in_reserve_pub bytea, in_wallet_h_payto bytea, in_require_kyc boolean, OUT out_no_funds boolean, OUT out_no_kyc boolean, OUT out_no_reserve boolean, OUT out_conflict boolean) RETURNS record
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
  FROM exchange.reserves
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
-- Name: FUNCTION exchange_do_reserve_purse(in_purse_pub bytea, in_merge_sig bytea, in_merge_timestamp bigint, in_reserve_sig bytea, in_reserve_quota boolean, in_purse_fee_val bigint, in_purse_fee_frac integer, in_reserve_pub bytea, in_wallet_h_payto bytea, in_require_kyc boolean, OUT out_no_funds boolean, OUT out_no_kyc boolean, OUT out_no_reserve boolean, OUT out_conflict boolean); Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON FUNCTION exchange.exchange_do_reserve_purse(in_purse_pub bytea, in_merge_sig bytea, in_merge_timestamp bigint, in_reserve_sig bytea, in_reserve_quota boolean, in_purse_fee_val bigint, in_purse_fee_frac integer, in_reserve_pub bytea, in_wallet_h_payto bytea, in_require_kyc boolean, OUT out_no_funds boolean, OUT out_no_kyc boolean, OUT out_no_reserve boolean, OUT out_conflict boolean) IS 'Create a purse for a reserve.';


--
-- Name: exchange_do_withdraw(bytea, bigint, integer, bytea, bytea, bytea, bytea, bytea, bigint, bigint); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.exchange_do_withdraw(cs_nonce bytea, amount_val bigint, amount_frac integer, h_denom_pub bytea, rpub bytea, reserve_sig bytea, h_coin_envelope bytea, denom_sig bytea, now bigint, min_reserve_gc bigint, OUT reserve_found boolean, OUT balance_ok boolean, OUT nonce_ok boolean, OUT kycok boolean, OUT account_uuid bigint, OUT ruuid bigint) RETURNS record
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
  FROM exchange.reserves
 WHERE reserves.reserve_pub=rpub;

IF NOT FOUND
THEN
  -- reserve unknown
  reserve_found=FALSE;
  balance_ok=FALSE;
  nonce_ok=TRUE;
  kycok=FALSE;
  account_uuid=0;
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
    nonce_ok=TRUE; -- we do not really know
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
      kycok=FALSE;
      account_uuid=0;
      nonce_ok=FALSE;
      RETURN;
    END IF;
  END IF;
ELSE
  nonce_ok=TRUE; -- no nonce, hence OK!
END IF;



-- Obtain KYC status based on the last wire transfer into
-- this reserve. FIXME: likely not adequate for reserves that got P2P transfers!
-- SELECT
--    kyc_ok
--   ,wire_target_serial_id
--   INTO
--    kycok
--   ,account_uuid
--   FROM exchange.reserves_in
--   JOIN wire_targets ON (wire_source_h_payto = wire_target_h_payto)
--  WHERE reserve_pub=rpub
--  LIMIT 1; -- limit 1 should not be required (without p2p transfers)

WITH my_reserves_in AS materialized (
  SELECT wire_source_h_payto
  FROM exchange.reserves_in
  WHERE reserve_pub=rpub
)
SELECT
  kyc_ok
  ,wire_target_serial_id
INTO
  kycok
  ,account_uuid
FROM exchange.wire_targets
  WHERE wire_target_h_payto = (
    SELECT wire_source_h_payto
      FROM my_reserves_in
  );

END $$;


--
-- Name: FUNCTION exchange_do_withdraw(cs_nonce bytea, amount_val bigint, amount_frac integer, h_denom_pub bytea, rpub bytea, reserve_sig bytea, h_coin_envelope bytea, denom_sig bytea, now bigint, min_reserve_gc bigint, OUT reserve_found boolean, OUT balance_ok boolean, OUT nonce_ok boolean, OUT kycok boolean, OUT account_uuid bigint, OUT ruuid bigint); Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON FUNCTION exchange.exchange_do_withdraw(cs_nonce bytea, amount_val bigint, amount_frac integer, h_denom_pub bytea, rpub bytea, reserve_sig bytea, h_coin_envelope bytea, denom_sig bytea, now bigint, min_reserve_gc bigint, OUT reserve_found boolean, OUT balance_ok boolean, OUT nonce_ok boolean, OUT kycok boolean, OUT account_uuid bigint, OUT ruuid bigint) IS 'Checks whether the reserve has sufficient balance for a withdraw operation (or the request is repeated and was previously approved) and if so updates the database with the result';


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
    exchange_account_section text NOT NULL,
    wtid_raw bytea NOT NULL,
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
    exchange_account_section text NOT NULL,
    wtid_raw bytea NOT NULL,
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
-- Name: legitimizations; Type: TABLE; Schema: exchange; Owner: -
--

CREATE TABLE exchange.legitimizations (
    legitimization_serial_id bigint NOT NULL,
    h_payto bytea NOT NULL,
    expiration_time bigint DEFAULT 0 NOT NULL,
    provider_section character varying NOT NULL,
    provider_user_id character varying,
    provider_legitimization_id character varying,
    CONSTRAINT legitimizations_h_payto_check CHECK ((length(h_payto) = 64))
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
    CONSTRAINT legitimizations_h_payto_check CHECK ((length(h_payto) = 64))
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
exchange-0001	2022-08-07 13:27:34.257707+02	grothoff	{}	{}
merchant-0001	2022-08-07 13:27:35.312558+02	grothoff	{}	{}
merchant-0002	2022-08-07 13:27:35.701271+02	grothoff	{}	{}
auditor-0001	2022-08-07 13:27:35.849526+02	grothoff	{}	{}
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
\\xc9376854021790518e25f22b0dca328e246ea793c8b02143b8db0c7afb7c98b2	1659871669000000	1667129269000000	1669548469000000	\\x0c2df27e9e00661abcbf6f9a6986568e211eb396d619b2b147d6d52c30f6ab82	\\xbe9dd7da6fde8b00dc9b016ec044f682adddcd0b61f92fdea10fe231515ec0bed8281e257a56333a72759ebcf008ac2632193319af77cedd9b6afecda1e9cd0b
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: auditor; Owner: -
--

COPY auditor.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\xc9376854021790518e25f22b0dca328e246ea793c8b02143b8db0c7afb7c98b2	http://localhost:8081/
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
\\xc9376854021790518e25f22b0dca328e246ea793c8b02143b8db0c7afb7c98b2	1	\\x7722f091ab62c51e855e3f7ec4c484d25bc2f1fee5858fdf9179f3784a73483c30c5cd3840e75422a2dc3c908edd7d6d498bcd0b842f1794aeb82f79c03a8e3b	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\xe51ebf3a33f7e5e597805e476c1716d5511fe5398713f3f5f23957710d459ae87a27c64f6125a67818954017b8890f2547c42ecc3eadedd31550ddb3c2825e76	1659871701000000	1659872599000000	1659872599000000	0	98000000	\\x42dd78f2c728a422df6a57963dc060015a00e688da482f8f36d3d3eb902379e0	\\xba2089cb2f17bd91e30f4e6d20dfc2b10515a267db1c03d758b37805b0133d4c	\\xb0a723ba0b0580c5dfbe59fcdc135317d053464bfda74bc96ee4ec340fe436b932e842ca574ac36ba4e267a35910c419907d0ed922828e39334fc86e4aadf809	\\x0c2df27e9e00661abcbf6f9a6986568e211eb396d619b2b147d6d52c30f6ab82	\\xa046d427ff7f00001d5970fc835500005d3daafd83550000ba3caafd83550000a03caafd83550000a43caafd83550000e0c5aafd835500000000000000000000
\\xc9376854021790518e25f22b0dca328e246ea793c8b02143b8db0c7afb7c98b2	2	\\xca4d3fac6409eb06709e4c59ecaf6175a4f7de9db0acfa399532abcc35fc33bf2030d930d00d2326f459836ce4fe5e8845abe38817d8cf658ab1239b16eae0fd	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\xe51ebf3a33f7e5e597805e476c1716d5511fe5398713f3f5f23957710d459ae87a27c64f6125a67818954017b8890f2547c42ecc3eadedd31550ddb3c2825e76	1660476535000000	1659872631000000	1659872631000000	0	0	\\x08a01f5dc004bff630a90d20196c498e1f24ff66b2888931f1d751a67c6a9314	\\xba2089cb2f17bd91e30f4e6d20dfc2b10515a267db1c03d758b37805b0133d4c	\\xb369fe9404de8a72c71a35b2c7102206c07ae62b1db7d800509a0d2216be0e05fd2d1919077cbe371c1e165a635ca9e1f2671d2713ba383ef7929c731598be0c	\\x0c2df27e9e00661abcbf6f9a6986568e211eb396d619b2b147d6d52c30f6ab82	\\xa046d427ff7f00001d5970fc83550000cd6babfd835500002a6babfd83550000106babfd83550000146babfd83550000803faafd835500000000000000000000
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

COPY exchange.aggregation_transient_default (amount_val, amount_frac, wire_target_h_payto, exchange_account_section, wtid_raw) FROM stdin;
\.


--
-- Data for Name: auditor_denom_sigs; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.auditor_denom_sigs (auditor_denom_serial, auditor_uuid, denominations_serial, auditor_sig) FROM stdin;
1	1	1	\\x62a8205c7654969499217cc40b0f08951026740141997510a89ccaffc8752ba3f66f6bd16e5beffbc73fbc5a1fbe897166ed92c6467b6b7af2103d6660871b03
2	1	25	\\x77bd3e2e97d16dd89f2f2e16003a08d15cc5cf85fbbaefda65cceead170b4a01a620380db41ff28ec74c0fc016f5f50307d729eb0e4f73aee9699eb3f1412103
3	1	51	\\x56fe2be825ce92a8cb72b511425f33a6d6bfa02fba80224234cbdf94b4e59b484abaf5390a43442d80dc540deca6d0c826cf5bdd53b021dd42531013eaf12308
4	1	85	\\xcd5e11beda81eb155f8e3addb781fc9346df60ff9dcaa1d05cd8133edfa43db2703d541d1228f34e0d786e499033609cf57b0184ded137bc99aec021c091b804
5	1	49	\\x5d615d7b2e8a0a796e9ff07c72c9dd274b7188a5311b16ef31a0c73124fd11a41a7114ae3411aad60176c0a0b0a5e2f808829d574203a09912d9d091cc511f0b
6	1	94	\\xddfc9281db280d5384447585774db7358889e26a348c884a04cb779819858ed614a819222be9cf96370ae39884ab7c8319307b0e889e835ac40d80aadebdcd01
7	1	381	\\x74a4036486b2ca3129259d4d58d3c2df0caf1b472fa9c58aa4670681a6986322b4df6a66453b21dc396d3c8ca59abe14c8a3db0675cadbf138acdca030876d00
8	1	199	\\xca1534f25845bffd12725e8ada25247c59489b46c17ab3f1f8f29a3c8ee4a57160f9578c703d954d1839aa045682f622c4674bd889d56b2017636076c9880000
9	1	87	\\x4e8d20aa8a9a05525527193d7b42ff2139ef1561dd72c6b2448facaed83334b7c09dbd7845668272f03add8a4a958cd89e8f80ed581a669baf97b8065ed3770f
10	1	198	\\x5a57be70e7755ea0eed493b8638b0b0309cd6aed97dcb734fc3b9f1930928d381dfcaa85b54b650a204c62a1c83948ad900a631cb78d105d3cc4d3facd6e6701
11	1	210	\\x369d28c8b10d0f767506f1a111d4641b30ee4ec36aef9da2462a6772476dc20cd1f5ad57fcf1b00ff9b649f179daf1dcfa36d77734086a8a08b2ecab6151e100
12	1	371	\\x37b538ea4d72cc06f59cbc529bb0a541e8e2eb0b9e462066519ea27dc4a12584c3477f41b8a1fffabbb2a29f9b3deb7df05587434f55d901a9e6d79c113ed201
13	1	278	\\x9d8f617b53050d7fddddf665bf92a13c88836e0251dd59265ad532043f2def212f9337d9117eee60e9e69d80a2b64f523ed27f9f529d95f8d0656e7606e2e201
14	1	187	\\xf264cb13fc4f91b4d5883a16b07f9b6bf3985fa1ef535d21bc22122d8f471007d008eac1527dbcfa2be3f7dd9e5c6bee41bb088edd6df236136c391ae3cc820b
15	1	300	\\x6c5f6d3fde010075fd87d22e7376131cb043af79a43b629c21e157471f01ee76d6ed18fb500d1a2a48e4833237b3d0fb6192afaa3b56e2a2aad8f64e34a8b403
16	1	325	\\xa13dfe0c2c8f77a55cc16ea4ff58643ac10a2b2b8935ff8b16da348b5d6a0922c5b3e9f6f7b3f0fa69e1df430ea578418695e65f7d64116529675e9b4d9a9106
17	1	366	\\x66daeb6a4ff7227ce47bd93ebc93d19b98fff6197fba088c2536137c8084e8a5d86dc47b2b91ba88033fc4c226f2cccb681f6ddf1cf2d9df10739af7850b800f
18	1	335	\\x3967313ac70cbbfe940fd4ade0229bb2ef51ce8fb619ee334abcf88655be2423ad05077df0c3254ee24440193723b3e385d33a362aa46cb6ce0ff6fa21027003
19	1	18	\\x0c2f465a23aec39ad56e84b6df0962a8e5ce537d8e3bdabe6c5be2a6c24fb925dbe87f85442f4746aed57e4b2b6142277a948085c698ff7ae00c99576b250d05
20	1	264	\\xe0518588bf3763073f5247ee0c8fe9b81ccab659f38d88d30d7f8c24213769a3477b45f4761f1a493335766a474cfaf8a29b098ed2dc2d676a43c62799a84f0e
21	1	36	\\x1dfd1632144cc8b04b679846f526b98c5ba6320dba7d2e689988e40bca44fcd0380b3fdec4e87f709a636f39ac027c0937a788799f31ace7d25af1687a1de90f
22	1	88	\\x3bcd78cef45c806b967b85816d8da2e72cb19c702547b4b36821f9779fbb94692f0c3cc4062f112f2aec76e6682efab6d2019714059a997a4a990b48981eef08
23	1	43	\\xd85200d9e2de59acba284dfd009c4ed109d2c02275cdc24efcd8504fdf1ff85ae9e38700a4dd8ad1e6f1f6c6f973c6ac3fd02cbaec724e924e99c4ab8e406703
24	1	292	\\x87a312f197d897e39571fa79eeffeb3a68051993b827005c378cf681624adeecfd21f2e420ee32e30583015c7c20184bf22abbe69141f6aafd081bd901a6d30d
25	1	69	\\x20efce1d90e0534d1fe3782a59bd39078ec659b469acefaf06b85193bc8a21478ed93612a355fccf66f5606a66f3439bba1d222cc8f9378c7659d075f8f08c00
26	1	362	\\x1b1afdb462b21b4650f8eb32942a78cbcdf4c0707c29ca963d9c21b0d8ae6edad6236bfa3a3a197ede93bf953ee7a922eb338d1fe23180cb2ba2a6f3b60c1a04
27	1	312	\\x365c03ecdd0d6fb0b71c3d91eefbe392346d79038aacb2283c946d738dd42d98ee609837927fde1fc803a2a3f832051a7385ed1141c301435908e4082f3d7503
28	1	229	\\xfb73a0eea10fa66529bc4b1fb3d6550ea0761aa73950bc250dab14efdecae1d61b30db1de0eeea34bcb34a6c106e9c3c3eda900c8e0dec2b4c56be4defb7570d
29	1	86	\\xf15adde4a691a8ead2e4065ae545d84b0d7bc3d2bfef1f9a31c247fd342eda2591ac3618735c4cff32b3b9ef41e242981808047a2b7ba01d08de3cb00102a404
30	1	224	\\x1a18371d4b4f1299799b077fb9e05b767a145cadd38846e49e2ce90778bf54412db4393d0a79987ae3b8fb731535a42642e345588b2892c4d8e4a06b06e61601
31	1	4	\\x508a7a8eb268e59fa0379e1182e5e2e634c22b31842ee373834bcddbc207641aa4275dc45f02c7d8fd524419e8802d6e4f657dfccf35043c0bce5db9d9766608
32	1	214	\\xa46470478901420b170233fd022d4c31efbbf91d117add1b065c157127f0e13cb8639873c077a7b5ae3f2df2a191474745e85e730e1068c78ec9c5c22ed65300
33	1	260	\\x89f6475aa3c64b1dd8a1414860900fb7cdabdaf3cde0e2f28bc542c70f6828c48106471f411cd979dbcf5cd7bae71bfa92d61a7fe26bfe4458fd1f5b306f910e
34	1	60	\\x839f9274656a2942b8fa63e4272c9052862792fdfa6dc6ef078c18f25c93bfd4dcadb6fec883863a32b8315362cf1373617345cabffed8011c309f8d8b52cc08
35	1	195	\\xd7e2263ec28da742c55a153a2048cc668edee926e68e42f78bc6079e5b73dfca83c3c5c2ce1141e5540a568c7b1ffce172297efa80ff0456c5d3e9e87f3bc10a
36	1	119	\\x513fdf20a478839f47a2c44f64ebe85b42a8b4ec89e9f1d4b915aa89ee5f18660ece63092ac36335ef1d0fa819e118bf586def0a0b10fda55ca3b50cd7b2c605
37	1	360	\\x5ebbc32946cec8004f56c3d7f35098bd387051a5c2880cc199cf6c7569d3da9859d1547fd4121bcaf7319de294849e149aa05caecf8b3dd0e13527ea28da7706
38	1	302	\\xad10a7d39ac2c45129407b09b3da949c563962d845527516e6c60e757110244f038ecacb28e0588a3b189c3b4d0340510aad6b0c87bb448df4bf98bece9ad50f
39	1	103	\\xf57dce15e9413bd1e4b9cb3a783f8eb62d0ecd17abc9f97644788da54fb38d7bbed570ad54ab3b8a4ecaf0185d48c3c34ebf7322cbb9786bf4dd5ee244b99b05
40	1	352	\\x55cb5c150bc2d1df5858e5081246a1b668b0d59aba8603d9e70c04a028139fa97413e181613549face230bf47887ae0e2e1efab32df03dcc80b1e20bf27f3c04
41	1	38	\\x5fd7caa5324034f803fc6ac6d1b148fe7b3018b2610540f3a60e96731d23c0704399da091918492242c83afc99e9407205fbd349beb51500744697319e0fac06
42	1	8	\\x4822fd5d13474a05744a81b322d0be56f9911b3bd0a0bf61e9cd06ae6174246a42d5250ec4fc7f977005fd7729d201e589f4c1b639b7723f8e02405105b69f08
43	1	398	\\xb7d689a3d2d9d889748376e2cbf1715bbcabe706454c2c8393e0762d3dd2e59f81cd691a2f99264a3273587be48ff89f67363ed213044676aac1d0b76ace1b09
44	1	355	\\x9407f3467d788f3a104c83ab15e311abfd66e32e7a5a5dcaa4def5dc2620a5c3bf01698f4a5f7a7e68d369a9f0637dc63c05118bcf977c1c754894a22a58c508
45	1	124	\\xca9ac4734283dac3e9fb11f1ab33c702fe6beefd93b6fee321594185bc0652b3c8a6587f67d3a6de9f487dd58728954c63f5a19765f495f62768336b776b3e0e
46	1	185	\\xdc21bf13586b2cb9a9f57107c9178b38dbf9f9c5a1cbc4cf8190c13988281b64ac1e4f9c5bf4b876a7e3112e51fc10b0f1d24099168be6c098a093dd08344400
47	1	349	\\xc3b0af58f9c7934cd0d865769a2193a7ebe00d1bc5b2241304cd1b79790361a7ccbfc0f7c7117e9cf91158f2f9676ccf892e18603d5ff7b8d8e603993bd41204
48	1	190	\\xde729b996d5409899de4326b71c198edb907ece2e96d28d24b60587a7a6781df67e4e06fd70565ec27f271c7fb51fb9b0a1811136b1c3bdb2de623ae1ad00405
49	1	372	\\x74e02d145242beec84ce6337f68039e0687b6abd3fe765c1ddad842f106f6abe7035a8658379e9c98461c9ddb85d7946fe660d6fa16383be4f2e8a5b88b93c0c
50	1	231	\\xbb2272a23bacd55e8852961f4335675532c58bb6d59e708f9b20faf68bf9136ccc62e8b9d27fdf1e281f5a3e46c6cebeb44686bb379b60990f8ac7e50d333e0f
51	1	327	\\x2b19055c57c42092223c7e008ea9ff09eee8ce1ab72f29db0fff3f762ba02d92823fb2e97bec27677f3d61b2474e4fac7cb88269bb90be23eae93b63a7b3e501
52	1	365	\\x156554d00ebd079a328567be95b9ac84e627d94e72a3bf6de081a770621cafe8bcfa26c0f50c089f027847db25544f39c9c62dad9833519e4792cab4adf9690e
53	1	274	\\xaf90b8ae0ee54c2637560917a166a94009155c27199486200f9592031c948ab79324a4a79ce9752a5a116deb41a230e7c7a0528813ba6e717123e32a4d885605
54	1	65	\\xeecf38c82b78bb21c2a4a303152682cf4edccaed798e6d1f87acfdd86e6ceed5e77148a0309c6038dc386029948237fb2f6bbb286fd59f7bbc4731ea955b7207
55	1	163	\\xbe0c70a55e3c4b1c01c50baeb9dbcc23d440dd57063e3bb12ecfc31f83ea018ac7b3de8884fec878d7e3b2b23a020c69cc6e6d9f0e32bbade07a75e916fbd907
56	1	213	\\x02668ca41393e56dcb19b4760b8cfe77a19335195a9114139c479b469213bc3386bb58fbbfbade22d072cd899ed84abadfbcf7e23bd1056b25874d7b376bbc00
57	1	356	\\xa26e18cb7bf11b9394ef102c1e299249e26396acdffca6625d38ac59e41777fd93f1ee503c5c7c816eaf224bb5db88fe95b0a67773ae3bf7238ba6d492a8aa07
58	1	12	\\x7983ac6eaf8d620bcc2383ec38917e4142dc0a4f2917267499b50c012c6c284022621c904c5c3441ce336fdf18ec7c25cdcfa5f80ea45f97f24b4431d95bd90c
59	1	383	\\x91d81975d784b6560accf5923f4ffceb5bd60056586ff0dbc071cf87aea029d53289860dae3efd09250f97680dfe5dab96ae6cb5f77d9356a7a1f2e8bd551b09
60	1	164	\\x423600a9da04da965ee7a978e7d0e1ade60e8e04c3b8368d5993f92c2e525e404c1c6a768a5a6d6c0e521265f0743faa7f7955ba9779fe405b590e84138b9b0f
61	1	144	\\x2921b22dd4c3cedabca60f1c0d34f005df9b9c43fb4c097eda59be636751e6dc034edd12d232aae9620ab973e22778044bf1cdaecb35b8b356863cd698321806
62	1	419	\\x3ab9d735972fc31a6d5d69ca32a992b4531b3c46dee9b4e2cddbfa03aa4bb46a34f068ba7b8e9cb330958143179052c59145c80622b5fd4175436e0577000403
63	1	423	\\x06e2cda2e66c0a4121baec9ba6479bb9a6885ff148d0b17e6f8b71dbc0d2d749565c2ee61980d18b1a410be579406a8e8ddc531ab7312d797932dde6f4797703
64	1	221	\\x6c2876ef918292addeb7e2a23820b0d6064bdd57b61eb18e31b2d7053d6103b772c7818f79b2cf204430618a44b946e28d65886316f64105adeef715f903470f
65	1	385	\\xfd37375c7cbdd79f829fe659918d23230f8784dcf3d2be0d5afd0f41cdf230204624b307fb2a7691ea155bcbcca7dea045bcc2fd8b4a3cbe1cc0bc2a7700ba08
66	1	30	\\xe55842a45608d5edd1317012eed821e2a6a6d5737f1c421b04a7d27199c4a63c2dc33b009fc4ad0778254066c3fc167b647b41eb3a13f46b9239a0cde1d7310d
67	1	296	\\x861caf4081b1a211e2bd3209c68ea799023b3182356ed74db3e9bfafa06f86ad9b8c09a77aa87eb924b957c47f554e7cac6b92656f1ce6b7d85faabf85ceaf0d
68	1	154	\\x857aae7e6d58d2024d895a953da02435c123f140a227907135f048cd8444055a104eff1ac769786ca5444a01ba1d0b2906abe5cd81e82aa6d52ac7107461b509
69	1	122	\\xe727f8950e53055c467a36eb32115383518975acb3a6987aa274a571abb61e251e7c6d3bdb2fc7a9718fd2cfeb07fa567f4153df945214cc658f6550aa75f006
70	1	133	\\x93da5be9dfec97e42760fa69d17cdf33e6f535b1527f958c7d0162fe087aa208e3943a99196fc752795d6626a6d43b53b18ea73bc9b349a6eef801feaf777706
71	1	307	\\xa42888e7e1c9f67c6f135e1612939420cb813bab29b52f0b6405e0f2d89b33ecf035697da6e24395798c7abab91fde84b7c5adb1ef57bc8430d731094e87290e
72	1	178	\\x1d4c5c4c8d5615872f12f1929f6a338e1bebfcb4c532cc0dfd8c12cd2faafa12c7e363fe48c11205632c16eaf196029c5219603d888288d1c12539f9f12a390a
73	1	139	\\x3dae9bd7e8fb99c7bc66fb5a79d2421347c9475a2033325f19afcecd7b291e6bcdcb5e0a544292b1a16b733b487305405fc37b3a5c4e59f45b5144fe42aa9207
74	1	13	\\xd6d1c5b07846bd2aa6113ca003f32b5fa854b7da01088f8adadedab4fd2a9f44b1bb9b415d2470b0030eb74e0415b695f7e57f5f3d7b77b7765bc1e6e33aec0e
75	1	97	\\xcfca8d8cf64a2d156c5e1b476ae5bcccab81c7883c78c1598e8c11254e8850f66005448c5a40718b07a32979d280f6b16e215e6fcd4f28151ab55021391f7907
76	1	74	\\xab561aa687b469ee68f69c422a5cc0904c398b52a7275d3c654b6cf360dcf2e5dacd7d029a5ab809d9d7195cc9b1cbfe6f8387680d6a10d75937ed9b032b1003
77	1	205	\\x4b74bcb0fd45dd398bed0beff4e11b10e598dcb9db29f4418207335fd81a6c1c70180b12c51c3a66e67f74b14b66fdf4ce4009afbda7d55573f8589dceb9270f
78	1	211	\\x728f2449d4ac24ea56cdb90abe98c0df9173edb3680fa452151a356be0ebf422e39de7917dd7a6b45c2e346989d52efd3698e19e47fadb0f153d64c595ec2707
79	1	138	\\x346bcd24bb542d3d757971324587c5d1ff094e4c93dfccacae861e6837c47c1fce4b7d4423db9ea81f066a2a6a674905259af335e6e1b377d17a481e75c6fd0c
80	1	331	\\xcf16b9d6cb36a027be3449a4de66a0f6d86257ae9894a04983cd789d35899611b2fd5c682f420d0ea0f0a547eaa707df89794d615b6da9a6099002efa0e5160e
81	1	208	\\x83f9ba0a318ca886657194fd37fa868dc4f65ddf2fc3a776de9905850aa9f736f6fae7952517266ee83c7285e06e513b2d210fd5db68f99f05096b2d513be008
82	1	194	\\x582ee7e9b1f6f0af627b582ed509123525c9527ba11343cee2500c9f85e6642e9878b3a99191d31a1a8fd65f1e6134d33bedc680f37367a98325d27791128205
83	1	336	\\x1ccb155cb392923547ed9fbe81c31f8f3c05fa8de691c9d3fc4c0ffa8cb34b41965468caddf1fc1ca6fcdb0fd4f0fa9cad308aff44f80a415d76d59664359e0b
84	1	369	\\x997856665ba9273e83837a35b94c199ebb9bea029dbc91b8697a5a11f691d835f47bec4205b246d6f3d4ba89078e8a8716d3f3176708fce23a98eadb232a420f
85	1	413	\\x05128d5d90d37a8bc64d2c9e1bc4351fd03cd3b56f0b84cede85c53b0ff010880bb982b9abe84c7a0915b155d5f95367e2f461e85b1ed56fd1a1bc4bd1d2b40e
86	1	16	\\xd894f09b770579bc7e37694f921aa5f77d6d6950c8b8c3f69b168017c12711bbb5284c40cc09a7accd5211d1b86549ace2c4f9a56d4b78ddbf3c4b67f4150b0b
87	1	416	\\xaec47282424184982acc4fcb3611cb0fcbab755d6a9c3581c7953001e40990322c52bd512ca851923fe9d409a0d654bee09dd6513e7a5a3af47438bf824a5d09
88	1	255	\\xa100017242dfd9dc308022fa6968889c034796e45deb77c45ffbac0a225d05ae0c3d9728d03db6a916d3dd31ce6b811562f9152a03fbdb7349fb8b5ce4ae4e0e
89	1	345	\\x6e8a9eb7655ba93a2274bc7badd83208cb43913aadf82b44ed69f14a0ebb977b684bc797f373c12900ced508471fac7f9f77eded0e7165559516e5f03b8b2b0c
90	1	100	\\xa531697caa711eff0aab6705ed2ae5d63b020d4dd72a74655aadbfa9f6b5baba66d8346c5e12871f6469884888048b49bef5f700c0d738012024650990e19403
91	1	318	\\x1b5d32a65e652c8d27a31cae9733108e9fabb2eec6bfdb783e3441a44cd4d8cdc55695b79c72a2da8c321ee14d78b557e51f07d351205f1249f7a23e94951e0e
92	1	101	\\x27d3a27a8340aaccb84a9700b8e2d27a784b45c4d07a1833e11593a36e6ab5d357fef98e659a5b4c704b048ab10d6c87601ee0ec70d21f8cb27f7037744a120a
93	1	226	\\xa41cdd277756d0b8d5b30b752601c530055cd734c56c5893f947948788ece3f58c573dfc3c2c73744956f6e803f98a941e4cb2f480195fc19fbbb3c19364ef03
94	1	396	\\xb706f4530280bab503abbd79f6a6558d0bb2c5399c2ec4c4041ab2f483f6a7816c95ed26349fcb1688425cc8807157e1c26725fc1845d4b2e54e1ad8bf370b00
95	1	143	\\xa2b07e35f6b880264a88f43c0617911bca2f2f8819c4c79bd5f048e3c1f8fab72e162b57f812381d23d8d8e61deceb874dd3e19b7dad51fb9fce21812d51c702
96	1	176	\\x6dfda1bbe074d7e7a8802f7a9d7a1eccccb7d9663571a8b7517c1175c00c20350a9d5149d1033c3c80746fee5d88a3faa4780c8eb1cf49bd808c485ee4ac6300
97	1	286	\\x27f1aa0625247976f0bf5c0c073404f846b07a305273590f44caa103beeeb69eadf5f885705480113831e5d63c6b6e20aff50bd74c24de5668e14a7bc6eb450a
98	1	183	\\x6f5e51fda433fd0f914bf209ca3fb276fd5a0a93dd63c6c3c99d26d2959bec9374782305e82a193b9e16d2b4c914216dacd74f23f03e689d3f49d78f756b5202
99	1	225	\\x2637f3cbe3c60f04535651fdcdee70486ccaf9ae9427625df062295daec449b42c3b2664a89bbe3a5826b0c0dbafe103e88dc52a23da285e3c094904f211cd0c
100	1	266	\\xfef0cf3dbd2095b7767805733211c122dff6a712b8ee062666d342ef1175d285e46efb054ec6d5aa32da62ba2859fbc5356a98f5f3109284f31a38645708890a
101	1	160	\\xdf2c4ab6549e6a73bc28146fbee81fe894d6083534e24b84f4d1906cdb4bb6eb64e22fe8929d76e63f6f31f5fe93d3915b03b27eaef6052f4d719e78cefbc805
102	1	273	\\xd3b1aeaa8d4f7c509d362980a5aa64ab48aa2fc93983986f9a1ebccb02296be23c0047a45710afd354b0ce3f52c08737177a9c8b1dcc1659d9bff34eebd6cf0b
103	1	375	\\xb618ea6f1faef5a6b5a5f1ecab752820024c73d716d08db682f895451a6279a3e6b8feb9ca404defe92ed4a9eb04c269b7ed9d43b81c2da84b0fc19ae405ad01
104	1	98	\\x503d476a484b50f6d3f9bf9bf4a3f324e0394ede1feb8208ae8d5619069d80012b6c0ed396c83382127592c84406ace1e02d986b5c6b47fc6e45e7add94cc90e
105	1	236	\\x799bfee7f644b6078ecb1a9536308180585f5e50835b98af16f90f9957f16b2d0b13bf602c79717ce4b4291f29fad1a9df19482ace0fae4f843c7da94b558806
106	1	315	\\x6ba3da27913f2140a8c7c95ca5cacf03b3796874c0d87fcd24e8f12f592d5514a22e76b0d0c7ea8dd1291f4ff514cc20d0bb3f9ffa54b03dba7b2b8d6d41d304
107	1	217	\\xaaba4b002fe9dedd95db134a0fd518e6976c5ad141fc6d946989cdfeb4a4c589dae41b311c4db22c4b958be0ad63a3a2d4718209a3823624f5bfc92dfdb7b109
108	1	121	\\x543626d46eb81b7eeba26bcb045564678d6d0a23955c99ababdca25f85574ce19554944a644b642187ab83cb19107380fdd766ebd601091c2ae6c699ff5f8302
109	1	58	\\xe4242fb5d6fe8a03fb5684d3ab7bc726feca85d527439e667827b4e498a783300806cb09bb867f3391ad7dd51d007af9e0c98c24f4a3a924b9eef251ae895b05
110	1	317	\\x7461c69ae0f87347ad0f887e7c43fff0e1282c6f2bd2239eb7a3376132cd215f82aa41aca0eb5d7895626a0d3a4d76e6141f9844fe2cd26a00969dec525a2e0e
111	1	53	\\x03afaa902ec9959aa1dd4c025ddcfd526305a812669937b145526ec8c0fdcc83bcb84f90691e495e58fe5e73243c29705e54a72185f8562189b9195235471206
112	1	370	\\x188e1f14ae6fc8d46975319a3f38b1660a4470618b6994fb6c50c7d80575a795c9332689b6a860d5589570c4aad12b99f62bc5e4ad0047ae40c4a7baef10d90c
113	1	112	\\xcb4edaafbe3f3b84779d23241360c5ab37dbb64bad04c9f2a04ec6764feec0e38ed945781fd7ecee59d3de24fe2e3cb917f66be0cf4f12fc0e5f911a88ddde03
114	1	91	\\x86ad80786c65c1ad473576adc26d6ed4765065a46d326e402f93bda2d8db81fe02f39ae060a335fe45d7a1068d18e39ff264c6b8f28d630d23da20e5ef4af302
115	1	368	\\xe36c858f80278fc5b8d4d8e508eb178c1e8790878898c081d7cf7fce6f31c6899b98ccebb4f89658690bd2be1e5c94705462d568ea634a9e5faaeef4da8f5408
116	1	93	\\x622a00284e497be96564f95679bb6d59bef88ed73dc58548204cb7b65d20cbd76dad7a283757ed6837070403842dc454e2c1497e193401385cd934ec0d25d50b
117	1	41	\\xb49d7844947448b9b74dd637ddcf7b0977f01ea3e155dc0756071bdef98bba8e4e04a15b648c513a8c026b7da36516772951381250e20f99e39f1164776e5606
118	1	357	\\x955794d51ebbfb144b6a3a4ab3d0b7c8f8b6478d21307c193f49898d3698ad5694ee62847e3faf97097a40dd79dacaf42979b4332b4e0fb8456a8e41c7547300
119	1	289	\\x67eb019b01f8dee00fea832c0ec2537646cdcb08d5da1f0d7d6078f86e5f12a9cff336dc4743f22c1a90c3b7f77c843b45a367647c256124ca47bbe427ae8800
120	1	66	\\xc1c05a3e52117d6a8f36ce180ae11f16ca790d5ecca58ab72219d82099ab10094c8cde11dc4d9b791bed1f496df4722881a81a0906793d7638ace7d71ac6590d
121	1	256	\\x22a87554dbc5b277991852a3305ab67fc799a4813965c2414ce272ccb59d8dd15c459b0c6e89e10b71af06334d7d03a4fe619de786e1a83a9b21e0f2d67ed906
122	1	246	\\xba7d63e7226cc49fe6560117d953044da06ad42808781ab7d089d38e4cd039b1c35a59296708cc5772bccf50124db90908a9b0f9fe10652c7523e1c566c8b008
123	1	280	\\x5d862e330cf1d49fc043ae987103020209bee8120c94694e7e6db9db0b29618f7874d4b85dd72b841f1be775c849071e3fb97d89de9edf28e1f7f576d60b5a01
124	1	70	\\x950898a4a7afbc2b6c08fe5ff27fdf5bd1b525bd489fc4780e332a9b72129052616f6200f450687ca94ff5e95ced0517048f601ec4119c5c0d8ab707f76fd90a
125	1	290	\\x81b392aae175413a80af061420deac0362d16caabb4b993f17c309c2d550255d891c523949e87aa175b5210730245ed60d09c6449e2326a546c1d88e28d1400b
126	1	350	\\xece20bac095a39b2ed354db2d51c971169bafee707ea0412e025ed5993063368851c394340d4328e73da23598f1014cf52358982aab7afb26a0d6841ab08fb0e
127	1	188	\\x04074c0be2ec4ecb98f2881b905fdcfc37ff690f4a1bd4a8730fdddca79860e635813ca210b2937cf9725979c85f13fce3a2f28d7809d4489cc851e38acd1f0f
128	1	267	\\x60b508211df2c25b98da1511c1e54198d784b41e7c38c8a2cbde20b979ca8e4a48bf9dcbe7d71c108b6632cfdb2b4aaad592428d085ee406715c540304bf3406
129	1	113	\\x6acd515a741d44ac265acec99c7de16968f33bd1557e44bd177b29e9ae68145b14deaba3acebfe5d444745523a329b99a93fc164d4a3e437dd980544da70e305
130	1	339	\\x9a1ee322a9ccc4014e8d5539fea08a1fb049ce3705cc32e19803a9b89d2283711862317ce9011bb930673771e6fe895fce3ad52875baef868e81f8907b4e910b
131	1	228	\\x7575d9f63929cc38a8b86b1a8907d696c1af30a1cc5627e61e2a707e1e43c7835e043547fa51e3ad2d1572086b31dec47964782ae56293b175750a0edc1b350e
132	1	110	\\xab0459a11efdad79017cd8de94f72b6a8173421ede967f016618547bd52905e614259e35db4ffd7d388ab5768bce5a97a4cde9c35a03facd05b2b1639bea3608
133	1	376	\\x38d442362364ad7fbf3bcd7a9bfcad97acd9a1b0dfd59caa7514cbf57fb9f1f8eafb73e82786ee994927a08457369dd8db746845ac484bc2f62d3d641954d40d
134	1	172	\\xed7bcdb084224772cbac6b3b2be294d18829f60ae0dcaa9eb13e9cb2433636fe1dcb7e570364cc722092a94eee02cf57aa4f2cd2fd87859c513bd492fe222907
135	1	334	\\x267ff2f6a7ca05befb54782a903b5bb35d544666c3a8b9b61877413277d261ce7534c1bc7646d32cbcc01c5cff095e05884b133ddd6bb507d338b66c05abf60b
136	1	410	\\x13aae29c33f7c31e0f000e5093cddee1eae6523013853c83dbf41472b7b1d69552a7e3f1112f5dce22cf487c4b3b0e3b0e7a780eb2ade91f5271c07f4a5e060f
137	1	10	\\xe8134451c92ccca243a51275e82fcc85627403e638c3a55737c1cac91eb116bd31e862bff925b64db113f15e04adcb3929285cb88520808d4d81ea3b70939207
138	1	387	\\xf672fb04a1a4506d7a76d71a7a8cb6fafe810bfab8977b5733a6d9b900b75c91ec86fc9d0ef3d144b36e384850ff7a50ce1e3c5107ebaa142a9a546da4f4fc0a
139	1	17	\\xee4725f1a147ebc0042ae72a8117be678017c261192b9ec43f4031f3b2e4aa8ea738518311397d893822f8da1d82006a90b4479367a79d4bab3e184f8fcb440d
140	1	390	\\xde3b16e305ac354f36c4eec01188a1478dfd1865cae50726e963595cd356b3efb6521170fe164232e9c955c66705c7386200af533c863717c142507d7031af0b
141	1	237	\\x7cb50efe503ec6cc3472ba9c0e4e2b15da1a14df83467f616ca27345bfb148d8ea52b8dc695074da9aeda97a36346bd9048168cf7970f2e54c2ae436354c5704
142	1	254	\\x11aa6cc6ba31bc1cff347b57c7a7e31fabc56d50d8c928752c8c071f89c11e985ac9edff7a0bd213998107debfc7c9fda630c592c3452b49bdb93a201e6da10a
143	1	261	\\x5c5c90ae8b81853d9395c3f599b71f727a503270bd3510c080b1d3255377d43b788cf31643c66ff1e6386f0aa1a38f4fa5b57e5aa7a248e9a2e255d6c6306c00
144	1	197	\\x9c7a8a0c3841f320e32e64758e5a12a8f078a03e2bf33ad0a189aa936f8eac25d91170e7b9d72be61a4730e371c73600657010629c78bb390efb904f29ff1b0b
145	1	140	\\xcdee599d721ba5999c172558be3177d3770580086b22bcd83937375480811d5095459f17806496daf4635c22df6522c0a8798a6cfde68b06cce0097f87615e08
146	1	402	\\x38c8124e4e9fc83e99f07fa0b648287785cf0aebf17d915dc57355e81a3f451279a94e3d2454272a0a5b6e8f870f9dd05cef59d576e82d67e062c713f67d2e08
147	1	319	\\xe6bdf6bf5ad7a0e1a7fc8371fe9d61dee810601c693d0e627c0598657506e90a696d18127549f5bc78b939dc02b28f73592c20b52955fb145c9da46851c0d00d
148	1	354	\\x17cb907d06f07e72d559231b8d87d302ab12b4e5a7c73eb8d921ce8ecd084bdcfd66e7d034a84cbc0eb50efff0035b9c2a00e10c644dadd254b059e2aad83f06
149	1	137	\\x5c173d3c637d7f818febe2a2aa66284f67e8a377f4e4906374fc8afdcaf3f4dc3ac5b633b6fa802625a345852c3d4f4c0f3e3005aa4ed5244d28fbfd7da9d507
150	1	92	\\xe1128bf0fe43cb1175a2a4c7f1bac9ae8effa5326cc49301b543cfb2f8d763141e93cbea939bc32a5be046348a8df63ca466326b0c0f2ab77c2a3da3ee34100f
151	1	105	\\x552e4f9efb91b3016f1a2634aa6e4e810580b00aab98ebd0aa805b2f099a13a658ca51bcd6f9c2c5c5b8bf988cb711f15046c7d1856b59b2f93b6a6cb736430f
152	1	310	\\x575e53b7d8f8aac0e69bb3e0cedef7d0bc16428d09b23dc48feaf6684f7819465bedb5268a41a378cb67398c9590cea1ad7e5da12f453eb432bfa99aeb7f4d05
153	1	141	\\x980e64ac9289efc823506075097b6243878d05fa3642cba7009bda7a8331d093c8a517f3cfcb553e29b142ca18105e7ded8b2dcbfb0c327746018b16d28b6204
154	1	32	\\x2b137ae3a83613f99fe830c54a4adb7286ac21f3335f19529ed73f44bf639975ebfdf4913517dcdef8c7eae17fcef49e4a6438994f08a4f8ba059bb7cb5f950e
155	1	145	\\xafdc364453844c828f19c7eb5a9974d12719c8f96e5d8579dda5fc378c55770fb3419158e8e664bd11a2cdb6842a7af922d998d703dd347339824a9ef27bfd0d
156	1	311	\\x23bec55f78e9dfd55e56b2346db1af04acf7750345a0e778facb4d864c0fc9932f39893d626b9b95cbb76dec84b980fad9be063ef0d8266f82d6be01b6009106
157	1	135	\\x58c0fa647b2a52f041647be15db1d21ee296ab905f55a3095ee828d9027bc54c7cd1db9de3de6e0f9ae2915a2467b60c4aa6a328fe915936fef97f57e4a9770d
158	1	84	\\x190b607e6096a33b55f11686a32ce1db7adc8923686ba386188aa9e6a87cb6f8dfc0b66f72ada299f6017e9e7caf8e954dc8ea8d8cb4842522bd1f91d5280100
159	1	297	\\x1a81e91f029143d052a7e523bc3b0bcb3a78ee31edd1b0f3f6915d4b89b43c27b08ac23aaa359f50f441a9afe22fdf9f8b27a7fc4b07e7ab71c9d0cea4abf908
160	1	71	\\x3f6bab6c2d98a1a2ac18b1e806f0875d631a7ed99d652114c766a8ef340147d9bf6656db8650721e4c951e67d3ec5be893bf52491903ee9643d1769f1f304a05
161	1	42	\\x8b24acd6f58914f47cfded807cb5392340cf1a47b07eef3ba1a06342eacbe3b591902b5ff7a21671f1a74479c041a3d94ab7f10bda915b006005b73231c72f0e
162	1	367	\\xb2bc1a3be1bd7a48a3444123f42c4bb5fa22b023c49d0b550c68ef7c340faf9ad5edb351913f7216d42e5dc1c374850af44a4e69fddce6a2d8328e26c3beeb06
163	1	380	\\x94f48b4bbb67a22505d9481d69e1c58580ad5987e5d059b4024ce35b6432714e2d6336e652fcd723fcf99f13428504bf25d98fa8e19d7b32c048f54b9f94940b
164	1	181	\\x91d5d65af9bfc3267f61b7a38f27b0a1fbdbdfd103c29d04c0a192bc27972bf522030c04deb310f9e40251924285e1825c63be67a6231f9a774a371380aae202
165	1	99	\\x2d332435afadda4fb22ebd71c205f4d2f16c66c432541d10a28cc66a5a9b3fddafce7a9f5292c53cd6702d800cc6e22ba2635ae24c9f168ba52065a13bd9a90f
166	1	134	\\x6a2bdab85b43e0e974c8764052dc07c451abe193ffdabb9f94b6682f7092d686ac54ca43aec8f8d3f513132d7da027eb778d42f12e3dfc3b8514796976d11006
167	1	47	\\xa36cb5d1026caa96e06b6018db601c2c2dfb00eaba4e772b3ef84e04cdcb14ef06cce0b3136de7ab46ded57770ffdc9c7852d7d4b6accf1843e9110a8d0d3b02
168	1	328	\\xc6a69e2d87b5a20013044ae4a4c34e094f22f71e926fe550af04f4eac7956b504d4a99246b3a5866b1dcdb2f7a95749d08ef6ba06cda9aa932abeab0e295fd0d
169	1	251	\\xeb9c1e2af522a7a8497de70851247bf25521a5fe8129fc1a1236b395e8c797e56ef78abbb591dd3ceb69cfd7a88a939dbd79c5cd77103775ca5e8b611473ec0b
170	1	272	\\x1421690ce32f78a5e383ac6eb06171b7cbbfaec5e65b25b3d08de93f1e5e82b0ec03245312058000ec868626f5809527342af6d77c06a9381cd3a5c59b772505
171	1	304	\\xba059b69cc309df0feab10e8d7d1ca7baa10fd61531f55741b89eebe45b5043026f70d84c209abd741014a7cffa1b8e883a2b45df94950e7cef0ca05851c0307
172	1	89	\\xe6e9104d6c90407aa9b3826f56cb18b57e44d7118b82263f835826ffb923803078ec7a43d5bd8c3df3cbf2b5dcbc9630d5c426df1d0b7f362b09763efcfb4703
173	1	343	\\xe9b366981c91c57cc2a50a0d6cab4457c26bcf99648f8c2253326f244811b243541f63b92a4af1ae97972842a2821deb46f3f0b298734695d918f29423afd107
174	1	341	\\x5c84ebda55f9f91c91b47e7cdc4654bee90ffca739015420603df7106d0b69a7acfaa35faa4e95ef43953911fc0c6b5798ef956247d619fd87fa9e54e8306605
175	1	76	\\x59119cc980e0e91f997de83037849c7db06dac39597c1b91ab10423e51112d9540321997e5a0a2398de7499891b6c7174f2f46d4266bd9d4359d968dc905580c
176	1	35	\\x0215fb166d9af2fd98a91bd910356fbf47dba05f2a870960d878088dc134bc0f7195563474e14d86676c747e85ad9c62f314b527d70bbae6f333942a42d4a300
177	1	358	\\xd224914c03fb708f0fa4b9a3e396e533aeb70454c45b8dfa0e0532bdabbe70a681b56b51e7ac31e23d3de9ebe194dd99200b75162f04f9dd2082b221b244f506
178	1	394	\\xffbcc4c3471a6c0e7b781e5ffbdbf9341503b89442f4eb3f93ac92c74d1c9cb6e085dd7e06f402a700cf99f81463dcccf6431093affa1f882ef1543d50894a01
179	1	2	\\x2e67b21740be9f931621cc0a3685d5001e5a062ba7db9e595a5205c2c83d228459f7b4fd417198d634078248e821f6b18d07c5b0de6ec21ff0ae28ca61f09c0e
180	1	106	\\xc9d124b12c34520d4a94a33aed20796fbaeb6f45d0b5166a214ab91711e85fb85a484d67093411efb50e372c2517572280b1f148559150af7d568690d9bfb807
181	1	153	\\x97ef6592e6ad30a27e8444e45ab3319e118ee9d2aa699694afa8cf94527df0960e8d8e087be1bd14ae04c8e093abcb7f18754d04d7c243b5bb8bb321b8f7e00b
182	1	384	\\x0d6a4ff4879fb2c6102ec8c55f4abc1f8dbb6a72089c838b8089b1fae4db73c16663b4cd7e9039486be4ad6c68ab79609e3b5200c990c2eb6888d7a43100700d
183	1	128	\\xbf2f6a6cb8b51a2f22148f160b677061c424977b70399f4d42c4ac98cefc40eaf4b62bf4fa02e4ece077b480aaf48a8685ef2a5261889105926919e3e2b5100b
184	1	392	\\xe005d5c2650249292fbf753adc2633bf0f6fc0e573a0689270a0ee09f8c4a4c94541a53c7d6b56e4a6a2a154380583c5137a9769fc0cf09b502b0508c7be5001
185	1	309	\\x58a4010783342b0c845a424942fe82d8e743c45ab1bdf491c76f95959a946c8d91acf9c3691e5c2ed4e50d13b14cc214c6bf72e3e09c37dfd12a39e98158b10b
186	1	27	\\xe6acfea000baa35d16acdae7f50fb0cb577d99ed555b78c0136a536ad439036b51e5c82fd4460b1243461f266875d23c7653f77e8e4931c5733f2ccb932b6d09
187	1	379	\\x8e8fef5185f558906376961ec2e807bfcc2fec5d86e0e77edbeaaa03f03d6366cd4b68027b66fbfb9ed5b5eb6c1eac1b9ac1e01ee285586cdbc930a8d45baa0b
188	1	192	\\x4f92cff25e75484622b16abeb21d5a72022d6138b613f4b0cc48fb3d9ae8f55519920ad546abb2f9935a8213ba76ef29ba24689b3d7a8cd73c98435088bfc106
189	1	293	\\x01b7a6ee1ba6c03dfab8bc90b4b103b5e78b1facf353ed817b28a52039880e65af5068ececbee7233b63ef5cf3f135d49c9ca1827c47d35a1db903dea5116400
190	1	313	\\x0cc63d8f00ba6fac175ffaf2c8622fdc22c13c702b261fa60cc65c00007288ee2ff7d84fc9dd6606e94878b2e853ff740545905672cafb162100835c56742c0a
191	1	247	\\xbab59e39f888f77abc3161ce5af601314ed0d03d26f3210ef0fb70d8ad4a1e81f4de91b3824c06bc1e9d2c054d905241f1aa43b24e4e4b3d31e73371083b100d
192	1	373	\\xbde2c52da2198e60affa03c7625459f589180035a65da382ee8a1a2f83ccac4c2460b241d8b7c0e1ae28933ef187aabdf33c34ae64d501725d30f02a6121c303
193	1	227	\\xe0950b0882b9e28e046e43c448c20d5cd9e011760f512bf0cd26d8fef1b13191be5dfd96af579accadabad9eea360633814e133ecd78f934efee0eb54f627f00
194	1	281	\\x3affc939117387149a091b90d1e7538abe0a152eafe37e83b94cb1215e7cd78bbd4de3c673cad38a47788b395102786aeaac1aa2ba96b180cd996c6062d22a02
195	1	90	\\xfbbf56db46ca42fcb8438aad913e0659a99f9a83d120a61cc925baa313c8e6c38e6a91053d130f121bd10609ac07d7173deb1f735edcac3d78fcb8b477807d0a
196	1	346	\\xf13af61fc9e7879305917bc8d80257b0a969c8ca66a35844d08436ef4fa5232a5eea91aa8cdb642985e42fd50851335d4e38486d60d8540d1d59183373757e0e
197	1	294	\\xd804b062734250477eeb41a2c45a68c17944f49a5df68dec1f0933c16cd6eda1d0db43c3c29dbbc06b7ea130b7ac972ec1aafbbf8283a4bfbb92487796672208
198	1	82	\\xe0d9e02eaeef90e84a5fb1d48fe9be16c4f56c8d636de83063708cc02f916e74d5fee0976774ae6f19b205a05a817e35b6615b1b1f9ab05fcfd61bbb9fe2d704
199	1	269	\\x0f82a596bbab9586eb291913a6ac1ebdff975f9fb40ebebfcb7ec492fa796669098358cda3ef75630a015f08db1e148e26e4d8416aa7380b615f2fe0a1d9b005
200	1	79	\\x2fe3d9f1770ff79b003610ee8b82f4892784518ab8f8aed0c5f0733d188126433fa87e7ca8d4d1c4b621cf897306c505b9bc80aa9ce50ef43ae091e776b1c20d
201	1	241	\\x6f28ed363a4432187ee589319e03f2b8700801a35a543af13f6c0042d3bb768554126bc93218d3aba8acbf2ab4c52871706fa427996fc2b795fc68485d995906
202	1	378	\\x62b1f2867305f916e1ae7fc78bf39d39ab99041a4183750ced7bfac7dca0651b2415a65c91880dfb620f444744029b34fedf7761e975267dfeadaaefdd14a606
203	1	67	\\xb10fdcd0ca9ac67730e7a859573d2bf9eeda7f3334af8e041fe8b20899a10d998ea5244e7faff86add63ce89c6387a733ac2127ba0361bba2baac0652817d703
204	1	24	\\x02fef1f5008d9a3aa2d9ea8e65e9108c6f07a14ad4308a8c31a5449f2e2a54da894aba1563652e9b55e0d7e61c5a76e31a4f3397aa6246efe1a4580719d2f909
205	1	186	\\x16d1f84cde3ab19436f2a523b2c4ec26f392ef259b102437c7d01f62c1929dd5965f7c700334476ecef62f808bb13fed754fae07efee2c33c3384870549b0401
206	1	412	\\x8e46ecc0a557cc4521922a2bc7b29270101b2c91c7d4ae11a007c2095fcc665249fab43a9c6dd6cd51fe12f3222ec8f92768aeee1ffd92d22adbfe6d5d253905
207	1	420	\\xdd8fd9d3ba80b96b5c2c635534f82fac9241d25598053807e34f0c5df40423c0bf75d02f45b9ba0d87241a369aa90d33bfc5961c31dae380abbb05cc0460a500
208	1	374	\\x04f7c373f0cd39749a8aeac0bf969c1d6ecb8d0dcdb5fdd62d3592fb10d67ad4ba9739f9807f100c9edbd543ade7e8e6e9685a71ba5d2fb72ca46ecff5c1e805
209	1	258	\\x28608f3c4361a9611d77288ff0426831ea5079322dd5d960413fb52440f7e10bb9807764c944ce121c72210ad126514d920a7b9466a1f02c01778461cb39fe0f
210	1	15	\\x5040bd7aa35b755f3a1c009f172792fa6595bc542ff6b59f656bdb7e81e9559255a07a5ab46359dce465a96e20a24a412ca8f3b1eba268f1c410933053d8410a
211	1	235	\\x9dc8ae9f1faaf8e9b97a4904f4c0ca66e3690354f381fff43fb8cf40f366e6a1bb7d17b46143dbd01fe4c53b4ba70971562f4583bc62060bf2c6a61cccde6308
212	1	391	\\x02854488ff0f13ed4dbca5d6f71159070e26e0ee4424a90d985ea2c13e5f0e148cb6a128f658f73640f8715e73b9513aa7859524f2af1c94b05ebc3e07391206
213	1	351	\\x761624d9e2ff6b054dfbac9d3d5303aa1783df17a14f92b2872159aa1ef132d04466ca76dea868fac9cd7da0e343d8e3630255f18abb7e20bd0a84f0c5723107
214	1	238	\\x7bd39b294fb6766c5dde81c6cab701563f1f6f457733e93511a12559f351806ebaf4aeb759ea00481d7e5265689d5f428110be3abb19ffd1020faaa2b97a1a0a
215	1	62	\\xf9934b77b0fb98b3dcf4fbd21cbbd748a2621bddbc6140507b89beb71a08ef03f98ede2e4e97d6b974bbe5cc6a2624f6284f4374a7db69dd4458e76526520105
216	1	152	\\xe3113b8ba2a02d6665aff9c979d716ea5917295cdb5a65996216acc1a16a081a545a0417e4aabb8819d01d9a90c282c9d2a4a35ea0368a46776f63ea94ee1a0d
217	1	73	\\xad36c24cd650097fff13787d2180fca087cfae9306d870c4e8db4c9e12954a3652650780a57722e93d43a4cd5c54a7818c82b3cac4095aaf79ae7946c3457d0f
218	1	284	\\x2e696a17ddc4a40ce00c6391c8721d7cf99e76c7a835c1aafdc34246117594784c8fe92b29ec207777d0c3977abe70c2dd4a898ac2f2ee0b888f6b607e6ec001
219	1	253	\\xfa037456c3b572b68a4a528d6a42a7294a241be486fbf7bea8a4260b8b412aa3698ccf97f0c7b72faced1fc29715c3aad4e8a859713272713c86159445af3106
220	1	250	\\x23f119f20ac07f362d902a1198e7b118a35a02e520ed0447bbe4e770f9562f19f7198c447ee77e95b18151617d0e1a91f8187a21594b952c6774e69b7974ff0b
221	1	298	\\x0fc19100d562fbc6bb28a61a6736dce4414bf543241484e038b4ffa321bbc3a8f4a6895fedf7ac4edaefea8c0d6d0058f861b1055e4d6b854614b3f72f6c620f
222	1	63	\\x65de0c256e25e78ee56a69a1e24b7f7242f110e274dc5a2cf06484443d0f1f970b871f39ad5e257270b7f63be7766380ff3cb19229673cad73a2aacf4e92a108
223	1	320	\\xf83c384bb6e5d8bc24bfaca8ab521b39927d338228a28f1460e16fe5cb9f3cc1df41cc865f7e0e62698ad863dc207513e7b4292015202748f0385d2105e0ab0d
224	1	202	\\x23db262d424a5ab02cb103215efd88e55a46497acaf76af9c479b215b9cc6fe425f10530eadc06c1b78a41e0bc2e13acb74a3ac3d6e6681cf7a5eeaf5597fb03
225	1	77	\\xbe5ec499b993753d752d385a5afc70432ae79132fb2af6f817b57aff46909f86bf8ed309a69b9da9b773c94bacd181e5b611cb3cebfcb2a1cb8cd38052d88c0b
226	1	11	\\x930c94892dad95bb2554f239a994025f3a51922b841962713351fbfb53f9bc947c673eab810086930e00cc95e2d11ca1b0f01a1a8ee06b824e342b98d179f30c
227	1	46	\\x6c134e1b649a3b5a16c14360f11ed69dc2219346d3bb25cb42ef9ed1342fb0ea210d1c8d5679b5f5d08702bac2ec6d0a8144691d4d74671bd226c910ec710103
228	1	22	\\x3a25696bd84b22ca23b9ceac1aae13d65fa69bc4aef97771dada9f20ca113b50a8adac03a8b04b38635dcf144b61918291bf8831d6cceb3de07916bb4b4d810e
229	1	166	\\x8eb7d36b780194f8b17eadd5d23a3c49fb128cf52aa385ec1474fa3e4d61807b582383bd102ba1501267f1b239be7deee3a418fd1e51a62542090f36456d2e04
230	1	61	\\xa9e2afb06cd10ecfbc78b0760039afd5a8e7fc7c331b5c3f3592d11a9ce29c3b954fda23bcf9d99357bf44075b7c6b3989375760f3cba16c7d1642966515f007
231	1	116	\\xe08307c4c6edbfd5d4fc7c5eef2dbfa93af9d2760a51986ed2331648ff93a3ab0aa0e0b9452c58ae7dd504ed9fe04b66233c88b6a133fcc063f3c779795bce0a
232	1	78	\\xc3e877e3465db8ec2631cff5e77c95c39b06ec127b92c198f26d7ac3d895f10beab581c320354b08f597011febd955b1c3f11832abd85ea9ac4d93d4439d3402
233	1	239	\\x47f1a3b8fc599e9060947034caaf51b46b3b9661267c72e6e62a09a13121f52cd2cfb448951884a913a845a6acc67aeb22206445e5a6f294a8885978b34e450a
234	1	21	\\xe126265d24db28f5a6538c5bef20f531dc80890d703df1e1aa5dde16604a6dd1e4076df6fb9e491c2c665ea3d0bbadb815711712bb922e688ab5c90e64b9e502
235	1	14	\\x3aff4ac20a486a0261431d9e52863d4dd3986616d15c8b7e9795f0d6164c14ad8347ad3a5fb711b967f4f6ee99a1d1edfa8641a8ec4f278040d8dc34cdc41c0b
236	1	102	\\xd191e7ed8b8cb05d8e736c595a440bee2c0317b8b80a8117d49cb00ed66dff1fbaf8bbd6a76ca31bfd8ec2a932dd99da1158f945420727b043e1d65163f29600
237	1	171	\\xdb5dd3dc8517e18201b8bad9328683d34e72a1a33693f95fadca3fe44be27eefd5c33c3e6b7c216cba036322c3fe8510b1ceca8810cd8ce10d994fba1125bf0c
238	1	170	\\x405920c72ed8645c7b2f7fcf577469aed228b77685e2236216f45d9036c8469b80773fbbd16b16435db808c595b7e37b7e7226f5df2cdfc12f520a1d2aedbc04
239	1	329	\\xe46153cd944d8e12db6aab908ac6304d813b6dccd5fd708eef7d2824e699b73f1315fd220ee72ede162822040b39c82a762f65398b3d5d3a3052d8a969633a0c
240	1	159	\\x80dedbe6745daf90bf3acdb78dc076fb56486e9a353f2ad4c18a424d9a2eade19b2368e04a33a98793eeb7fa9278d89ebff2d73ba81792cd90a6c2e931758205
241	1	424	\\xb5939a67ee338624e5403970e9bad45a6cd6358682c185594d7b1e29f5bda1fc5d13bfb1d5a71f5a030586a797b296ca4119a52ab1ea3019af47d575fbed2b0e
242	1	3	\\x2a9bdc5e40a165715e6960d804ef086ad35038417781e66be5dd020761bf6c4abc3451a16b3a9bb70185744b5ffd8faaaebf7aad9b62daddac6cd9e466441a06
243	1	56	\\x0d2c8a8343fba041075149dfdd1045e40fe660f07348858c6bad9c9f418678a3c2889c891efd0a55bb79f3bef0c09ec4f6b8774a756972a65cd170efc1c49c0a
244	1	109	\\x15ba9926cc97715d05efd4cc88ce7a4e10661a3f353963814f8ea0a9031eb659e4fa048f139d2df00fc42719fa91549a926d9d4e7d37f1b135190f14872ce100
245	1	230	\\xd74ab754cce810f46fc9a5819369a615565c01cdde5e21de887e0eaf207acbce2c556ebee8015efc11f108b0abeb48d39f3de64cce36d88f2d686986c7fff109
246	1	80	\\x2328cb6412556b3d4270b1fe24b40011fe83c44d344d198dc480bce12622006b02d08869dad5e7219ed585174453689b96ea4091c9884084ca5f77c88b09910b
247	1	270	\\xae78dda1f3b06d376b4498e7c71c90ef4539524477797b93b4ccc3a3ab4fc69100a1ce91a084d7bf707de075f757cdb5dbc770b257799b77f347357b6557f004
248	1	240	\\x6b81ef80964d477112f035415e16d23616791b91db75d28e70333ccfd81d09475057bfc8f9677652b8623a1e318f4b0f48286cf91a6d347776bb545c0dfec309
249	1	382	\\xca01f2759b9279acd5405f475bd2ebb1b78327cf0c5e90f9081300c4e35cc4d79f5506d8f8828ed55ab0a161861cfebcb2b94908a9591e61121c475c7a457405
250	1	200	\\x9fde08de2946e88b8b8aade9685f0cb8248533e0ca1d98b0f3092507bbc3ded1c9f8426f74738b8b4cd745ea7365d33d1742868763cf0289ed7939294d0e9305
251	1	421	\\xa6208075758f6c444cca820a961b0af7b075a12a08b05e948ec00fa696c4e463af64e7b14557c204a229d1312fb821859d8d861f098803e9205b73f070d33d01
252	1	417	\\x91f7510236da73dc032e57d18d61a6d2f1673cb99833bafb1dcd6e4f80d8a8a4201cf895fd762d9babe2086ae255880103fc02e8cf7946eaae0478edc70ed506
253	1	107	\\x29013d470f8c35943cb6d14f2c31f431c39dd120a9354f63aaf3a0135ec19076ea494009c8a70f867a0ba85958120c13faea79a051ae5bb3b056557493122a0f
254	1	175	\\x625e26b45db207512d58a0731819fb5f779f2bb2036b9c3ae2b71417e848e830439e8c74a04e59b725e15e96b17ffdcb6d579def6702d3f5ba006cbeb7bcb203
255	1	257	\\x818b246ee07a12a130138053de155fcb8cefe83b4a1753943f193c8df2ca550a75fbbdcab27138c8f8755df7e63d54efc4d2421644cc2a9c8c022de12f0e5901
256	1	301	\\x60a458e8bed8180f86a1af4c0233687316bca799d385d91e73177d3eb9e8909a8b8eb4683508309ce48618c81e50539b5b6b4bd53698700b5a7b0288269e9809
257	1	248	\\x9898b04127aff20d8ef5c4bdf9db60dfcc0490ec8dabb24346b82dfec408073b4efebd0934c92a7b07b6dafb7678a0dd5114ee2edd5e7b93d8ea2371fb6d7909
258	1	146	\\xf673b094e3c89a75cf1908530f50b5f853d71712dad0b5baab36cccd59826df6ab512c1fe76f2eeee088c5235cf976d91ffb215462b76c0456de9561adc3110d
259	1	6	\\x8fc74d53322747655bdef5c535f5af63b8f84df4f1803c9de7fcff5940aa9350139497192cd1fad30fa65bdeebe9bd9a2de775bf8989d5b844ad1f0d9fc97605
260	1	28	\\xa9ca504f3145890aeb0d22bfcf68f76de7a805e8a7248ecc2ca7648722443bdc33460e0c4e3f444d22944b28775d3a3263756f47d4c90ff44ff28405f93c3702
261	1	207	\\x0880940798f3bce2908342c67412fd7f679e294417c32f55a08b084818ac6c0a5d1763fcb2bc01a8cc9b083441890e6372273c985b1b9f0c8c6b4e7ff506d30f
262	1	50	\\x3933b7621cd564a4dad4a09c82c5b30807f7f1d9d56f8a14a44879bc97a77ff73fa9bf7b2268cf5e49c3d6f77b2feef3c047e53fc9564b740b929f9ad941aa0e
263	1	243	\\xe859c3df21a43bcabc2b4178a6271b89053b05f3e728f056550cd7882708dfd0c95b8ed215239ffa434d0e7a154f1ac18ef8927e006bf30b9f1e43c4acb56308
264	1	337	\\xf5e2e648b0757145c52c284725203c4b844ddb1125ecce5ea2427f2d5bc193fc6d48943f37565e51e0e4ce62883d7d2a8e0aa4929405c68049121c368e2b3100
265	1	118	\\x042e9a237e565c6fc15b9d848f9efb37121aa880333b4142966117c4115125527bc64be90e668d5cd7f53184f6508d1121ea69f59b77a09ad31f12ff8e913c0b
266	1	19	\\x9b7cc39c06e7885f0cc077183aaad0f9ee69536eea309934bd4f298989a0e3e7de29a6e7c32a7384068fb6e0674767367e2932214d0c82b8ec253ccec7124903
267	1	149	\\xcc9f1cd47d95407c33c3e95ee426e6cb5b0d833e157330d736227dbd5d9dad2e63b581b215d4d0608503ffd432ef194e905da31e96c02bca35764a9bceb0e60f
268	1	295	\\x5215317af8f508757ebb9543c7ec9c24621a80f21c6e690a131fb58900119849092f1e03aab9559e924d9296ce3a21cba5661d02a8f058e7a9665c90206e9009
269	1	5	\\x2ca59ecc8bdb982f2e9a25c1ff5c0ea8378dfdc5d90a0bd55c952453096eed57b69f7f9f5d14f262e24f93b18f95a257cead83b2153e448346b6c83d5c357402
270	1	342	\\x5b3172053488ababaa2d8d8751b1095ec89da7f0ef9f33725eaef7c6a047290afa2b54e5b0ce13bcb68cbc12f8aaa7f038f416a76c6bced1732baed48a484e0b
271	1	23	\\x7c8206ff917776ef699c0ef5a132332012e180b90f2fc8ea00c15374532328e42d0d86a73c8fa054020a9f96001a7dd9086943618e4c1e97269a3d95b401bb0f
272	1	282	\\x98caaef262907d6a76c12c1f7633fdfa35c44e43e1814cb7d7883d8b03b1c17094ac0b715608710df0388d3d1bd688fe267140c9f36e2fd2848b80d8432b3a06
273	1	75	\\xc4a36139307314c2c0f096e03332f322ebd9740cebda05ed3f8400022497023017a32c16672d9ba4e4de217003bb6f9c2eb8a22f0e92574c3ed4f1cc05bcea07
274	1	150	\\x90bf6f76c30aff8fe86c3f3a3827b78903d60fff8985938c37e45b1517f0b407f9191bec4c71685782222393c4f9ea02328186d055330e4d95747a52a9b07702
275	1	222	\\xe1b30e388f9c52c786d7cd7382cf797c87036fcc613447cde4f1139833209291d1a452adc5848e4d6858396ce5bd1548a95c950ea97f8955c01e92b089483c01
276	1	142	\\xd6fca745a91d8d3d1859d148e235947c45fb52198a1770c58e8198ec6c7d6e7078e30f66e45e25f01fbe4377a37dd8a658de008b614227de49e2abd504fcf50b
277	1	7	\\xc4a3ad633336aa69d07b2714f4d1f589cf415549380c883aa6ef2b9f966cf5ffbbd0d63f171e07783230d02c636b1acf4723f5f060dcde90c8a1153540cd9d07
278	1	136	\\x79cd4e43e9231b9009e3d4be3e3a15e13940523e37e676633ceaf7ab8841da48b1d48652e0c40349711d19e5162fb8433dbb878c1dd15b64d86dcb6e5143a906
279	1	303	\\x3cb57e40c480c6bdfa848c10e8b111a665cb2e1b6a03dd51aa72b38b500cb8e91c9a1bad8f4bafad790c86d8325e2bcac1472993d1c5bf3eeacfe4a752934e0d
280	1	55	\\x99541a622de9b119cd826a80068fbeab76319b69611f6a49695f8c106ef4ab582c5fab54266b823e5a22adea6642382ed86b1e8f6424c230ac5272fb2c83440d
281	1	120	\\xf0ff727815e9f4d511efac36b4a3badbadb80318bfff7d5a58fa2a59275d5353eb41c582d2e192622b11889d0c08a394ee84bc7c22236b4e05f764d06e270a08
282	1	204	\\x1a88a50bcad65a59fa6e08116dd35301b8e923cf40204f2b2c14d9558a77c6f97f4480cb3fe0d78b70f3dbe29645d09ac1f5aa439ec933f210e9f7df3fb9680c
283	1	316	\\x391311d9b6ab3290912da9a157bf2711a0aafa6b0cf8100dd3e253846681db512e7a46781f178b908b9924d4c5d5fad47d6d35266d17dc6d572913d460be0b06
284	1	223	\\x447cdc843b2e841c071bd85a23201e8bdf232632659d318c680f819e7d01d4b1b8bdb28cfe83320b619ddcd298b2d80f5e4ca4fd8440ba8e23620989c412d305
285	1	174	\\x6f81c3d2b838f9a3de738928def0afb6798c6c26808d20b639290be2d93d169881e71c349930583bf24b7a918744c6ad3d0214af2001cec730d81945b0e53706
286	1	299	\\x2b8203cab5840cb296987dd0599a05304928303f698cf04dd1353826304f25cc68991b48b73f9108a11dd841e2290a22d32bac402aef89f7c9a6f6b7d679e208
287	1	330	\\x2c731f7210acd2a82a9103660165aa56f3934113f2f610c9f06e949b7a812eac7af50bc1f31eebad564c623440913eb190d59d6ec0894dbb9bf78ca9a28f9a06
288	1	168	\\x44237daa22eed80258f96c90dccc364ae82b856078a0d791562577bbcc12eb1c4a24ffdb4d753babdcf32cb26136a00c13743e6eb552c247176a8bfaf3a3740c
289	1	132	\\x88ded0207ab02e27ec81df3db1cd84114f8b3f07e5281d67fe05fa57f0297ae13058ce1ae22e03465bf3ef676505b722f452ec4deda54bef12940ab74427ba09
290	1	157	\\x057b21c85c67397c9799826530db86a4bf0122ec6f0830fc0fc35793bdc7664661c5fa5b728b6423172d2f1e3e5e237135fa4be9dbc4451bec05d6b892acb70a
291	1	244	\\x627f54fdcfe570591a1d8a346131aaef43c2c2167876f461c1f2fc534f5a306937a81ec52fdb06d0d3341cfc504eaf2df017880beafa7c375da7c9c32e64360d
292	1	9	\\x0c00bb2fcd7b2501a6ad63654284dea0f0115dab985bbcfe78181171d1246e957c7d158effe08d1605ed2f90effef17f89f3a7a2571ea1298bd522a862e4f504
293	1	388	\\x85378d06c742effec68323c9c498c53a363dc7b800e54046871a752287613399658024a027fddc97b5aa714e282767bee5a5ab68e316da025620c1b54d022007
294	1	395	\\x4e7636ce70d44b6ce86ee8f3674f9549d06824594f9a1987549ea1dea0544b6082bf9ba3b244feb1c3fedc5eca43b652f3607b9e57d1842d36d67f5293c44d0f
295	1	232	\\xad041867ef6bf7f57cc229757a7b227d7d14bb857b8e070130dd0141fd06f0900deb6df4296d88359bab59765d6d83c68cde84f6cd4f96191fde98d585512d02
296	1	180	\\x44c1a3c4ed1031f05ac7fc711084f3c9cf4e36cd81cb356c3a8e076917082addd809c8da8bac5b3d77164c41b86498a68dcd228a770f8123d57374692923ae05
297	1	333	\\xa80debf5547aeccdefa50b1060994319d62289a2d5512dc4a28789458640581dd93b4b273db847f67dc13c9ae8d5749e54805345e51a81067d1119eab213e40e
298	1	156	\\x8da88d91a14ff2bd9397447100d9b8dd4672246f1a7024359bb9d446351c544add8cecc31f9fd94bdd1da9a6761314088356d99c68a528e15d012d5bd90edf0a
299	1	401	\\x402fed6cc81f0432bbc6744faa40d029b77ce53a704ac589b1e36de4a3f3c9adcba7bcab77156a5918aa8dd01f1aa089dea76ee28419ae39859580ee8dcd2a05
300	1	275	\\xe5970a905f17b77578b4729ae48eb82092ce4232abc6d74571efbd020e051fa4fbac47edd5510ba9c9aead3fa793b923082df18647d6fadfad0c7c32bfdd0005
301	1	323	\\x8159c33db8a3242f02a69cfe7ba59ef5c8c45ea4b6acef967e0b79b1265661648b0f2f7cdd8f90d3b2cb613f2a16ab1e9c3f1e9a20e5cbba0aac376d28d6d601
302	1	403	\\x3ad7eebcc1accf0c9ddfeecd8d6c740997514181684e3365879f2874a385f67af5833df9775a9f4e554ba3d0877b71cd7d67f6ac12073f1d823dc54da9926802
303	1	95	\\x72c2c6b6d370b1c455a1f6aac09e427cdb2a1d9b313a38ff351ab493347c6952cddd5ecd432580382d7acd569378d0645adb227afba43844d9b415c45f29ac0c
304	1	399	\\x47a61b75e356306a7c9d36696a743d08e9ef12aa21e3c2382af330bd9cbfa8223fab795d04acbe41c4b7ae9621c765b4d5b17de767b710bd5e2f709178361506
305	1	262	\\x23c06ae2cdeda845580eec59fd5a22234f0c8fc005ab471101c3b2a5bed03243a8d05cf3577c51e6ed7c4c302498dd49442ea3cda908912f9c321a0a07b17206
306	1	191	\\x79e103322920a8ebf4435e7fdc24d2692325091e930776044ff690a0923fd28d5b3ec5107da39c0300c5776bfcce5891c010a7c1d55631edbe9aefa5f368fd05
307	1	151	\\x010c193eb0ec9530d64a303396aa7c714a6282597bdd5ef07fdc7687979a3577a3be617cb1318070c803940fc69460fb4e91ca225742719727c175ec14208d03
308	1	377	\\xc8b2d29ef92dbce745f1dc744a8250aa8a3602f8a020877861e908219cbf9163b3ce4c8729856331eb744dfacc2907843bdbd1ea75c9527e264cad9430744a0c
309	1	265	\\x03f198a5c21370fdc62c355651f33b29e2f9b43dd1d8168e2740887bba33e857b4dff347b31b28813e042d1d5eb49ec3b68acef5eed1208524d2b07dad02d701
310	1	196	\\x56cdd5deec15bde681d208524efd97d73a6e68198ae4a206a204b95512565a1a046e3f5e9f2721119b287ab1cc5a84969e60790c5dfb881e77b4619c14c19b04
311	1	332	\\x75d140da36973cd58372a4d9ab98edf0141e8c80107e2352daf496d2adffe4c52f380728bd9c885c78e8fe42cb73c83ab8da7f54010f995df9b712068a4e460b
312	1	104	\\x045553bba1d0174d99250a9f290987e2a62d52cbe339c88b153b4e14184203946c29f67ccd2485095c232f9ef46fc3c2f1822bae2c616669faa707dd8c026e07
313	1	308	\\x2c79f2944cee77d6362f0dcc6220e2312acf57ff853c78a4aab0c5f70a4228e3678bda5339ffd70fcab86f7a2fd2f27095cb69657adaa124cf5c27ca5121c109
314	1	72	\\xd202fd4f740c7a4b21f94d61f73c6ba2aea3260fe71e7845ba863e40c2213c422b53b5876c180888af0d00a475b77036763404a5ad4d56d3817f0e996d2ee105
315	1	404	\\x9b5209ff6e41fb0be7d85ca36446bb99af9f64f4bbe0798755abd2bc974cd9aa0977719e68a0cb692819ab84e8f5db7ac9522c56dfe967b457467cce2151ed08
316	1	306	\\x1e93aabbfb78924a14f36b267fa023537cf339c015cc31fae8a9b88e5d92212734accff83e6521aea6448cd8cfcbee404d4844922495d4e93fac4bfb0c891b0e
317	1	161	\\xab404161a7fd1e91f953ec3a97c376201616a270db6476707cb17e6362f390982692a5408e9a7571a9706184120f79c54eadc84829d997dba83c2d9b5b71b90c
318	1	361	\\x991e7eba2683f7bcdbe70ac1d4be38377b2c055ac0d19ff369b80dde3d901d9113251a172db0ed70991163181aaa338624cbf89bf44e1fa87f1a7bcb9af9660a
319	1	117	\\xbb3efaa340ca1b3ba2d1d92420f0e83c1ba6df3395222acde8826a7828c5bc5554cfef225192bb921b170c08d463699c01add15a1308bc693146e96e43947402
320	1	177	\\x81b0340e09a4167cb64df0d607e8dbca0958bcaefe37329c5e39179e9b5eb20c913026a6918b5f26580ca8a5d31108e3ec297ecf6ecc603da19b496f67f32801
321	1	148	\\xa1cb710c1d7b532d78ad0ee2b92e8b20235589234b552d5d306fcdda0da315e85f7fae67a30d82fcb914d61986b14fae8d8617d33ac5e62de0bf4f705e267e09
322	1	39	\\xece00abcefaa59f0d64e7b9beb548f750cdc8417ed043188610e08217956876d932b842129c5efdda549c7158a25187e8bb4a0a801805940b27e7b67f3a0010a
323	1	206	\\xd27bae293f8555bcdb251206264277498e50b123c1e5fb2a70a80ee9533490d2267e6f864763790729e136e38f51dcbdf386c3dead1edf69e6931304809c730c
324	1	131	\\x8ed5408deb0640915d4a837a0667448701752751a30fd6d0115a9d58f8b6e45cb030e3af8b2b611663af0fb360c182e861a86bdbcdf5c7c5b0c76ba9eb0d130c
325	1	52	\\x57121dfd029d5a0fa784525e1e28388f08f019108b5cf360ed8fa1960ca7eb3fc2d7d33f71bac5290c0d35ef0919b10060bdf9cad74953922d129310698ff703
326	1	400	\\x661c202b9e9c19d53391c4c11d6417a29a00a2d40c1721a05f34d2e809ba069c1b0bdaee540b73e13531f8e800e75e7187010a5236bd2ac6ed9c82d435879b0e
327	1	54	\\xca00e5b845bb3e69507e69706de5bae1c098cebc4f76ba16fd5b11d6cb88cbc724087e095a567d3bad01efd244a558c6bf0017c8660a54ff3c43f95dc9dd5508
328	1	411	\\x191721b3e37a68b7fb4114e9afa3b025f6dc0813f2b20ad9abef6b6c1e56ee7a22a3917105c837881c6d4c3e2c20f01bd23e61a2c00d9de55fa28613477f4b0c
329	1	123	\\x74d0d6c308dbddee450148d7b7bd9fd8e4396c8830d76691e0ebc16b41281c7602088191eb0917179cd2e6fbad3095732207267ee2140628366cdb3718b99c0c
330	1	353	\\x3ba8fa14ee2aa781afcca7f5e2c632436de5489b3306808cede0497cc2d3f17cb361b12028ba17131aecf4bab6b7d23a311b855ac8c722ac45f3eb6802a4f20c
331	1	407	\\xb7db9d7374c9cc8827ea5718ea36b147a206f68c4c8b748dbf61f540c7f2c62c6bd76011b0ac61512c5a57e9ee5ecde8aaa422af19437f528f1423f7d0875c04
332	1	182	\\x9c7e9b0c3a8bf76be6435111539ce06926b6fc5c85c7a0728b81790e6cf96896adaf2344c803dd95a1453474ccce50348dbbabbd7330e4451b916b57b4a77c0f
333	1	96	\\x374f4b58427f45d0762a6639e94867f1a2a418cd59502587784696dc3259eac31750157dbb141263898d11e46e1301e5241c3d40e338bc477224dfce64c63e0e
334	1	422	\\xed883be28a6e5b4808ced29054ea3f9bbd3ae80ab13061990ded059e678d5e82697123e28a8fb5ad5cd6d4cc7851e9065891849f02d8fd80a305791faba87102
335	1	389	\\xdac6adf56e61befbc80bb9a69322da7e0660528ce47885c7244d50e71dfbdc99cb232b7f94313f7f648a10d14c66ac3aa090c384e98deb1aaa5c96d3bf9a9404
336	1	340	\\x82153513341daa57166940e7c9b2feab4837a02caca62e14cb1162bca7a47a9ed49c72f0bca58118955043c70a0d602658653fdbb29f0c6c086d9ad524612802
337	1	288	\\xf33c99c05a590087dc4ec3ec41fb58d99274af30e233cef3b38a6b0f9db8ee835d175eed92f8d9b5ec0074fd0f9d44c1372976bc85adddcb2a541b7026414405
338	1	276	\\x6a03821746a662850256401bf3e7c9ad54b6249ea0f55f53cb3b2a601f0eb520e4e586e98f36a3d175d9a4f708deab49e3a827121494c622fb481912e074a80a
339	1	29	\\xab5d263753a962db8ca9293d41142a5b7e1da01e58e236caaa15efcdf9387866bf7c8618254c1d71a4da231f7a925e2dec60930a5b966c108075bee69b8e370f
340	1	127	\\x18123657907960715ac7f4fbb11e4332153dc9e073d452acc9aafd3986b5d4bbd607399cdeb3fc95f6c4825f26a900d4042a53f35e4137a3fedf83dbc8246507
341	1	37	\\x2999e34e1813f163c4acd7d41ecea0e040cc7f6d47791688feeb0f31b40cb8af3c5aeb9c27d3f4b50e922317877e362f8a7c1b08b1b2c114f950e1b0765d8c07
342	1	249	\\x3dceae5ffafa530fe24c6692aafbf9c92da565e931e5ee350c770bc31db2d0b1f7c24a2936194c4e91bc5ba2f0ecdff2825d80f3e37ade12f5b1768fdd5f6e0e
343	1	179	\\x842fb4ff8d37f1882524c1a8bff4ce12161cf4559ae18a9b66155cbaf2e273b7d6252679123bdecb23b6d66557c771b235ed475d458378c4a15055a38f205b0e
344	1	234	\\x4079c9b1d0dd42db154ad71350fdb945899fe6b170a1476ceb0cb4e1034ac4f6ae1811ea9c2e34edc08180a624cb73e9013ef94773a7ec3e0067f3c5ee41c309
345	1	126	\\x91af0cb15fc3a283b622b491f9c5f55dc059d826c0a921da60c430bbc06a2dac64ff7a266270cc81d409ce3ddeb7b2cbe0d10e83f62e257a4efcf11d16477305
346	1	359	\\x9612166a729cfb698cf846415ce6b38efd558bc9f2ff4d49b4a8540274a877349242b86c05ff5adb92f5f85f47951a842c82bb6f993900d4c3170fd6f947520e
347	1	277	\\x4a29d3eb18384b1cfec9add8fa95e30db5aa8326ce823bcfeac0791a1ce78e6fa30f437652cc48079a6fee10323fc9fd5a9ecff3a62e841f8fae5f093c1cac01
348	1	386	\\x28ffcc1b4cf432f5ddb8e8ce31d793af15441764273ff8c9a08809b656c92c3d3aef215f2851e484244d16eff47a9cad9bf3fb4b3a51c5f51b54c93327e41404
349	1	414	\\x239869f14e8a9b8e924c042323813eb394ce5c8fa403d59df46666e868561f642f694b3542e54132ca5c157ee9a9b958baad7ccf61ad89c8e38fef63ed6b050e
350	1	305	\\xade9a92a839723ab42e82bc9584e868e81e570cc94514ee078a6f963a569c914c2185187404be066458df04e8edac8f6b03434846702ef257d1f0431391cba09
351	1	169	\\x11a304755a9b87a35f123dfccf8a4889cfe44c215a6234d5948b8390d139257453a8aa4ef1a9d8ef4240b034ae393eac251b7f430777d309010a277475acc100
352	1	347	\\x45b1391f3d87e68222b72da61111eb140dc28fb1b6c8bca83dac1ea045b050e86dafab1b97815fc40b30733399409e490af383fc5f9396926104b8bed6c01303
353	1	409	\\x901dc9f236352480b935d5eaf0f33d01d38cff832507db043749ca5df4b6d3fa87dc3beb8e1fdc362f55d52ed9437b4b59d5e7c089272f6635724a0ceb8faa09
354	1	40	\\x732d07c5afd62dd12cad0dfdc5f0a7c4652f0023d9ee4f500837943072f00a0d9d60e244ca2c5c2c815541efb50835609e5538723bb3178a4d4f84d28e4c0702
355	1	406	\\x297af028ffdfc455b077e7205dde2ff9820672bb2b1216f7f46e184287a29c9ce6d58bef3ba114e9ddee44594bcd8772d19f57fbaee4d7ccf5b55e2d559db805
356	1	268	\\x25ce5e8ce0bc63857368d2d0ccf9d576d1abe0d871f0f53d99e4cd5e9d12ad15b55bdaf7294c69388003a067bf450c6a7a1f60ae1c40441ec29e17d0e4ddb10a
357	1	218	\\x9c8d467fff14831f250c11b2c628bfc2b82b5bee40043445b04003d7b8ee09820f38aba6f9979e4f049304847b17b27a75b09c7ad7c7722e6e3fb03b27bb5e0c
358	1	364	\\x2377ca7f1a6126be42aa9ff0aefaafc70d653b321057ad41bddcae29f9c88ac555c174748c060132a4f815cd620ba63aa461edb7d3d770385317edb126522b05
359	1	324	\\xdbf6bf39d80164feb0734dcb60a536ab6685d145a756b0898b3be11cbc712daec5996fa7851fcc701163a770969e51f78690dcc084dcff0930522ddbc00f890e
360	1	203	\\xc3ad5cc1815a11da9722156c8adb3274f458bfd9c525a965ade48b80cae9bb64b7a23ff4be8825a1b53e90b11fc0e1335793dbcc75794ac84c853232d9948809
361	1	287	\\x382e63c3494a622fccebe789828dc3fc4265613dab05a15320a643657b147c9121040a31ab545bc072cd3b40fc7cddadb75a2b8c3097e6fd656dccdc072d9b01
362	1	233	\\x81b161f1c9251797e50e09852887ecc2b272dd56fd05a8eeff0dddd485697e67b63c3792b7776ecd24835ad9101b248be62e2df0066e0b338ef13a8315914c00
363	1	215	\\x772f864aeb8ee035bb00d41bd4abc4064469f6a8d06871c69f06e38295764487542adf46de328bf24e324075c26d35a50addced1ba993134f6607dbfd3e30a0b
364	1	279	\\x0928307e86b2ae74cfcc67470105ad0c4a22f8cd16c69ad5de3061ebc6696c043d0211f7032fa423086b82d227b387b1c04eb56828ea1fb41bcf9c6739fb7c03
365	1	314	\\x69534b7444072ee93a2d88bd8d1395084de8576c3703846db7a797007dc1f349a4e6bc54fd1949a6377e2900b9287c451274431bca84398ad6b6176af67a0b0a
366	1	34	\\x157e9cf692763c27fdc22e2d99ce434ae07c918a5f0750b59758bb10dddadc92b74fb1781691145a25407fa04f80fe78f79296338ec09228cf765e72c2ec0e02
367	1	271	\\x13ae834827fea16e07e7efc1e4d3eacf4a2f2487ddeb790c0160d2515477b716124183ca7d4d7530498bb60e755935b6f084b18e0f13befbf1a713e54f8a420a
368	1	108	\\x4c1fcfd85004d0406a5391d7bc930eb97510dc1c76a5a15138c95674f23bbbdba9bb34e1c2ae8246264dbee0a137b145364626342de548a279079df8ee58190f
369	1	405	\\xbdf62c923bc824c46279711334955a8e0b198a465a7b30b408d27e2ba37416a2fc079d0916329fd636c5d11d548d4dc3eeee9f34aa56b864b54dac846d3a8c0b
370	1	338	\\xf6f8e2a3a898a5410674476e73d48352b917aabd50bf3946512e0f89ab17441dca05c795938d41a0190ab34a7974e1c250e06ea82b06caeee152bd05d5d57c00
371	1	242	\\x807e3d0bef85a9b456e8fe27b31b5c621a5f5062a0c53990a5f42768d3dc350383c1258647e3513c01b103f036ad70e888f90bb7bb26adcbc2d336b516460801
372	1	363	\\x8b6ce4551a6cd39cb092507a84030a21b59334cce5f2da42cb803387bc95f21a363d8a3c4278cab275ce74ebf35e43383c14e15078c09ef0e90e4f134880c802
373	1	220	\\x87734f08f26770ffa04e516e3897a54248ee84721cb067daf676b79565a1c61fae9ca05ea669ba9e2a5286516583d5e86e9f8039113c4ffe44c2d781f7893405
374	1	59	\\xb44b398193ddfdbfdac0f52b68c627f4db4b4abc1b5f0253fef9705c8bdf0d229f6efd940ae251b509b74ca67b775f6809a6f6bdf5c6aebe753b82853d32e908
375	1	326	\\x026e67d1656743e161f186f3ac68bcbd752cdcc99d92f0d2f9bcd61bdab98d94df7b0333d4377e2a31519078865bd3555ca80493383d280345aadb36f7f2bf0f
376	1	285	\\x6d172b8642192a353c7e4ab81166473613ac093c45804d43d61c7877f37aead6a1d849b5bf1708a8f87a27f62f2a89ff38a46f619505bf7447ad38ba97762f08
377	1	418	\\xb37853d0f7a37a14edab5dc1aacc0d5290ea19622cbfc8e80815374d43f49d6ad1be1ed69096edc147ccf057af6af90681f594aa3b789573fb601046d7cf2b05
378	1	114	\\x18bfeec96605da69cba0a243b588f501ab6d8498514bca3f36a61a08e7bfdef507840eea84118c3452066e6b4dd1722f05ed58e03bb2323bcc166fa07458c207
379	1	155	\\xcc71985b39bc5bfeb7cfd02d165a0ed6e80a28cf30ca31f930d7c1b14ae3a442faad1484ab359ebcf1b4d7b9ac949673eb105d048a22d2d5e135c5a687b34000
380	1	129	\\x414519ad8f57936f53cbe87f0fa578aaef141533a7358bf08b4135bb226946e31b1673ae2838be3e3292b7b3cc6b711dabe76f02e46e4144d02105e04f7c7104
381	1	26	\\x203cf6c476b07284e0f0c6400569ddaab8700122dbdfbb045323211633983c03085c8bc5ab445774baf51cd51875899929d2274b7ea8a77725a9c260be04670f
382	1	291	\\x41e8f83643ac452251379fa22b393be443da0b24f9340d44e1d760319bde7cb020987a6b42c02570ee499ae7012678a7b9b1e44f5f16cc0b4a0a55da89940b0d
383	1	263	\\xa1bc4cc265d1091aaa6b77081d2cb3f176b41612755118d39092bd131bde156b9fea2b2cd5e489965c85043b295dbe4d23a2f3d3715838903a3a3dfb5143d80b
384	1	167	\\xbefeb11bafec456b7523c59e1d2a1a08c4859f6f912273b67f4b393fefb3a5ab6c96a669f5c60034affa31c3c9fd79a8cd8825f97eaf3d94aff6477d8c65c00a
385	1	165	\\x86998054f80c8d9bee8c2547cc7320b58598bec846953657070d727bcc4fa601fdd7d1b4993c895eb644947909c2475966780a98af494b9f1e78c33544aabf03
386	1	81	\\x328da642f36b8308914606b1320948b7c69d6c1781624efb258b53314ea33fd0b5468e8f8bede9c6d62185514236d83b3138d626fd1e37d687454c1dcdbf4109
387	1	31	\\x900e2559481981d5fd0913d938cb6ff92bcb0bf1f6d5fbd3ec3eecdc184478b1e03300bb40e7e45e4aae2af284610095af371d7c47bf880aff2c5a6d24e3fe0b
388	1	115	\\x5118fe2edce30718dea137f237378de55e6dd0efef9fa4c2d6ac7f169e8875e705b9e2fae3751560aa28b32ba6ac5db6cdad5cf1ee03bba7a9e5aa45d8803f09
389	1	393	\\xae57e558814681fd94452b11ebbf85e90c4865f4aaf44fa5fc8a37f01e3a5126dcdde4106549dff7c29a554404b66ec8a308f3d86bd76881908622b4f11a0604
390	1	173	\\x846ea10e63ddc6a39cf2ac74aa6832691d2b2f495d76a7adcc632e2d68cf28dd8a24a9c34346cdd984e3d951e583f243ad04f61e1233e72514d00e66c91a140d
391	1	245	\\x52011ec4abd7845f25ff2b45d48dfddea91a2a5aa7b583cbddd69d4f0d5f132391ae43167ea82c4fa40b517ea60b2f926ea68073c1484200d89cf81444397209
392	1	212	\\x66717b990cf84e65637f98d780fe78af358812722b3afc8f39a44b7826021800f126703d5f94c28192fec657c97fdc7b5ee09facd377e8cf6cf951f4432ee20b
393	1	147	\\x93a7f8a381b75b3b40a0b991d64af1bfeeb6092d9f4bef30e82cda911d02aeed333f81c906df37e41981a0b498204a684cb103b4f877f2ab55d20a45985f230a
394	1	322	\\x8b2325612fa473597bd960e15dbecf2b7c8b4ad85933aa2ada41e8c6ff8830a70a786834a60fe612ca29e5ca110145a97db8bbcc456cb8ca61af5810117e7e08
395	1	216	\\x98f948ee315409e5490e75d94247657dd06e62e2e703018d11261cbb8a0ae7ab19dabb18561f82a72bb703d83bec4f435166a227229894721141bf34841dbc0d
396	1	68	\\x0462b06b4efaca3e3e519239b01c01a6e3b403f1d9e108adee109b8f74ea57cec3e63ba4c55cb28d77ee5506311503fc087a2223966fe8cd049ad69e3b69f804
397	1	48	\\xcc4257661382583e05da7b7e11fab72145abaea4c9879891efd9db83391e00b0208eb67d8fc6c3248eaa4ba95a6d3aacecd04262632a27e85d6e7d428f136905
398	1	64	\\xc84d4617823cb25c280b3a0c92f05a1ce6ab8e6fda0c75aece65918563175111e1afe95c58dfd7bfb081d73609badc7a65a7f149ce765abea818dc859e807005
399	1	83	\\x7ce241c19c310807832f1fdc1291df6cb246a23269e3909826b5e13b311e90db739624916754d1df5b5651df1b531af7a26501c6a2901610c8edc1ccd40ec702
400	1	344	\\xa8c8868fbdd840352a48286f1036d5927d240a7a393407d89612e4dd789fc8c3647276c2b7bf7248de91217ea9ed7ad50cff7fd9a609b4ace620caeb9024780b
401	1	408	\\x0b820e2e75f61c1f5ba8885c026163c3e39c3c9ef8af9ae9e4655e91a40276e5dcc9b23f7732125979f5f4453f8b9639a48e6334705305141a93735e7b80780d
402	1	130	\\xd168b7cbb362cdce03810f66343a24cb59e7b30404228b67462d0c64b3b004f8365475fbf5550b902d8fbc96f64cba91038056abfc5c8721a40e5624ed834309
403	1	252	\\x310f28ffea4a2fc939e27c5834ce9ee9882923eb80baf3644f4980f1c860cebd6ac5a9f439b7139520e4f627652e9b34e470ed5bca95a7b90df7bd0b91911103
404	1	45	\\xd6d5a0aada4e182992dbfab1318bd882d81d1fb73dfea7db90b12096627f64686b6485a56248340c59ea66af681fa72f432f37ce12108bfbbb84fcd1939a9102
405	1	57	\\x72e8cbf9eac60b1c815d8669dc975ee2bd214ebe579dd4fb604c693d48361430fd81a540e8d49eeb7e8039e7f9cfd2c1ce23400b3b84ccce324bc89cb1be760a
406	1	189	\\x80ddac4ae9ec24bd6688c22e43f3505bb0effcdd3d742b210087b7f594b7d94acdd8fa5f8e1c728406a5747afa4302dc9761c70111483ed1979b1bc5ca890400
407	1	111	\\x5edfbb0406a7f8a69e8f7bbec7f12f43e090d386904e2c4ec9c5be0e27dd496c84877b60edf10652784e85537501c9895e0e8d3f792419e85c604a59d9897409
408	1	209	\\x9cb41201d43c1ae6136707a40368e8cf072b4db025a7310d5243fd83a8fbe8ffa3a5997416d2be207152197bf6f959b6b045d20d50d38569be716c6d5365a807
409	1	193	\\x6e2e21cebbf598ff179a70ec3332de995f4c9db5e72c62a12cc34742b59d87833ef8f998ca933dd1c3fb6469ad0b3beea8f0551e803c337c04d637bb546e4102
410	1	201	\\xc6b2e868f299d77dc8f83a268679c64cd8f0f7fc2f09177efc2191e37186807d3a5fa5d276f326746ffc9dbaf34987c52650798da5485edd5570f0216a954e0c
411	1	20	\\xcd6a46cedd67d00b60766d6989478b1279f9fb2ce6d0d7d8296ba029474e7949d752329dd40feaa7524310876551c49612bf15e57b445b78e86b92bb98302808
412	1	397	\\x61b134f077e770dd5e338f2467becc4db4142d7fe744304888707084dd9f3a402d6bba7cf8d45d48aec45a5c8a8bc1a1f319f010a5e86bb2227602edce782a0b
413	1	283	\\x6da6ad7c89f51bf00ce45f7518c3d9310895cfb42e82f00df8bc7dc07661162f61feb51aae0d002784897e1fb0acd3de64837a9f8f1d724c0deddceb1ccf3907
414	1	33	\\x61aa51664a6492373c3a6d6c9f43e395765de8ad7095407d10852a6972719aebc8195e953747078df12bd4c195c9ab56856404e946f9805caaf2b7db49242406
415	1	219	\\x85acb6af6abc52bd1078a41ca98281e4354fe2e341ac238c21ab9739a1503eaec2f3e83bd91ffa36cdb4298f719e789a2f6b3d6a25e61d12fc4172fc56b36504
416	1	184	\\xbd1e8ee2392735d01068dc1c913a42d6dea07a434ceab75334e0cd0890c9d2b26b3702852f8fc411b64a0517d8eabd34077ac0b201dfe8b91d50e4dbbfe35709
417	1	321	\\x95337fdf52da13ff7f38ca92af5955c5cfa3d769e2b2b02dd0a73caaf9eddce29e3f34684a92cad44984be2b6aac2b5a27d4bd0dc655ffcbc514dd24ab27fc08
418	1	44	\\xea04cafdd5af5cabaa4a394ebee5a4aed11b91c7cbb8a53a6790830694c76d3aacbd13a0b81dd66cfa35e204cd47c7b50f11c611023eb29d8c2ddbd7ee58ba04
419	1	348	\\xdd4ecbb7d3250c0ca4ef59bd3d731b3ce9d9a0d96079876642cc19931a7a461bb99a4dc78cda13209427013cb8afe8a1d6c55b060eb9bb44e7cb2c11d6adf603
420	1	259	\\x17b31bfd36e15d661a78b0df7810b0e30135d9bdce2a5ec88ec2da0a1ef5276c565d9a696273f58b543b90a4720abe0af7d197f228f8f98d2cf73b30ce22cf0a
421	1	162	\\x1a1b3dcce0e756e9e05ec26f29f9abdaa41d7658b6ad401d3c801bfed38dc79c146b4511123ffb89b916caf97dfcc8d1088510873b1767a08c173b5c4bebaf06
422	1	415	\\x4c6986bc1d5800a17138d287a48f5e898bd8a3eaa107c8a92c8ebefcbd308d0ca490dad30a199e3405f51c628994328728bfc2f378387a7ad13a23b7023f8c0a
423	1	158	\\x9dd7fa6f1af4321eb031870d31a9bba817130d74881b7a741ce72f97d19ebe71205e0115ccfd999c2e43cc68b1e3012b51fd57dcc780ca99f72db588b902f80a
424	1	125	\\x811b1c1a1ce7d8b222b29d0c74b950592f2cd781b7230107b826a706e3c895202c2c0238d5d60c8e39e47e118c17d0293a7df603f450e48d0c01434360496101
\.


--
-- Data for Name: auditors; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.auditors (auditor_uuid, auditor_pub, auditor_name, auditor_url, is_active, last_change) FROM stdin;
1	\\xce06ffc69aab89e0478aa34efeac4ebe8dc0ec75001586ae333b9de504938b34	TESTKUDOS Auditor	http://localhost:8083/	t	1659871676000000
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
1	162	\\x1fa0666d60943b08472a98ccc8952db86430711f7fc26cb6e07b0fd47e38d7997edfea4fae8dd62f987588c2f4d3138e43e3a95934d1de0cf60dfa1272a4860d
2	20	\\xc347a6592c3e1c4a7854d98b33fb6751abaff0a8f2df3b0ab128ee500929abf9804fa83320aa83965e5531d222b8d791202756b255e5c164e9347dd3ee31220b
\.


--
-- Data for Name: denominations; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.denominations (denominations_serial, denom_pub_hash, denom_type, age_mask, denom_pub, master_sig, valid_from, expire_withdraw, expire_deposit, expire_legal, coin_val, coin_frac, fee_withdraw_val, fee_withdraw_frac, fee_deposit_val, fee_deposit_frac, fee_refresh_val, fee_refresh_frac, fee_refund_val, fee_refund_frac) FROM stdin;
1	\\x05f4493254c99bc162c5b22c7343fd6eb0b5764b1bf476474df9d8544fa84d78fd6223a158e64b8a725061f1bfa4fcafee9af21b962067ddadbd8c07d759cfcb	1	0	\\x0000000100000000008000039d1e89362cb5f6a5499fdf4e58b1de56de48e090a3013251de062c26faef49f11be5cd164cd7dd0cbcae35a2bc53dc81544f4b5fac13da61593982f85a7423e7e43e692098cb1ed2438d98fa251937c721294da0daf4fac70392d2600fbe0da19ac33b8b7918e4a6e7fb40f880c82ba5f67ff8ec09d3e97920a2dbf1d5dab6a9010001	\\x9615fcaf5f8724f1d344292e58fdf09431bca69f32537677c287886ade165710c488249e4f32a0dcff9ee54da79efcbeceb77a96fab8df5ec9c3089bbfccdc08	1691305669000000	1691910469000000	1754982469000000	1849590469000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
2	\\x0630dd1aac10c9752bf60f68dfd961fb092684da0f92eb4e8219a911766cd5564a1ef8f31efe6d5ba2299387c4c200495ce2c52d944ca4c93f28f02841f4be4d	1	0	\\x000000010000000000800003d3a2688a4bd45a68211bfacef00d0fb9a1d1540dfbe843479adcfe4d06829a233f685142e39b25ab4db722e653d133c115b9a1bde65aaf8ea77e2dbc51d40c9e2bb1ed190f248288694b6cb75acc7d3ddf094beefc6f62b52428d591920d1840fcfc7bf3236d0861b6ff73e24438a32318b18082b1ca0faece0bb865995f2bab010001	\\x632568e9643531e1a621a2f02d2b851f2deac837b8c789a37f24eadd4564b4d04ca4d732a95673f99dcec702b2c7b78ce234adb244dbde080d10cf7af5961a09	1678006669000000	1678611469000000	1741683469000000	1836291469000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
3	\\x06043c896d80168c13db1e3716bde419f99d5ae22026fbe2bb55eb91a4c08f0457c53191d15fd4203cfacc68bdb097713f09346408a472ffa968722a51ff91a4	1	0	\\x000000010000000000800003dbb9641e2bbaed12967141ae59c89232c3cffb431fe2736aba893597e0b7c7fe8ea8d04217bb780d397abc5ca14646edc6b8feb21f153b596332d87638e4720474fe610a67dce267737ae27e4be8e2dcc0c2ed74173e4bc2aefbafe62a96affc27cef8b3191c6fa6f0a00b4ded21e3320167e8c1dcd6b7f825611a418f3a9619010001	\\x5e7953301c58d7a82b000313eef778209f2a74ab4f5d0abb3b3a6ae4c4ce67991c047424d9476263193ab02235d6cb0410bc7053c2341dd11ae7e3f41153c003	1673170669000000	1673775469000000	1736847469000000	1831455469000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
4	\\x09145713e9ffc5bab8e3bf6b121aaaec3f20c2174742897cbd9c1e5ffadcaa9ede50efc614aeb06faee5a11d42111eba5d5fb54c3fab6c08ddbec53d0681e330	1	0	\\x000000010000000000800003dd89b443a78ed34ef1901a4d5610dddd8231f53b41ac7ba70b9eb19dc01a7f8fae0d282b8c8773beed0de9b935cb06efebc87f7a1e2d023b23e4fff2ba9364d798b01a0fb19e794955ed8ad7009e479310e789bc5913e24b88959a3d7bda4c42c6d812a36a36abdf45e3ac44d8126858eb7f9aa3bcb275ea48732c7df0ef91f5010001	\\x581a0a51d05f7d131d610c2d4cdafdd045e3013517d6130263b4d2421255ecd4d50408e076c5aab5b572ad5e3965a2371e7f37a4e0d49f6031fbc125be5fb403	1689492169000000	1690096969000000	1753168969000000	1847776969000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
5	\\x11041876ef57655752f871f5c17fe8635d46c12b57f651f27d544ed1dee896d90df13cbca677e68a9ca54572d35491f17b482650b5a94a0fdd8c64eb21a6a9c7	1	0	\\x000000010000000000800003a9ae9d5baae06de8609b408616a1ba808541bde6ad78ba707d9f5982d986303514e3d9724ffe3d5112ea49b1570828d0650264437a058e7f86bdc830002e94cac52fc4bad79c19eb6d422b81fb71b7d38ef7d26e20bac199e4bb8de560e418b736a709aca0df564cc60712a17df3a7fb8a36257336d81ee2ae73c791d125b8b9010001	\\xee05ed0f6d1b1a25bb9cbd34323780dd6f147680d74ebc406489bcca5f33809de1e6f4119d9353fcb57d9f352f9045b4172ec73508e61ee2ea34241935a8b902	1671357169000000	1671961969000000	1735033969000000	1829641969000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
6	\\x11d86ecd0440042d7153eaf4f479c7b91acfa317ef443f217f8e3d2e1db6a73a949400f6475dede9c77f21fc30a1b48b614a4828d6dd99042f593309b5132a8f	1	0	\\x000000010000000000800003d6909906d5c4934f7539c94b4b09820ba2c4fd493bdf934a7a5d118e4f7af65360059fbe375765c02842caa313b5a90704c179277741785c4698af3d32822ec4e735ad9afb01091002516a63c1cb0b945924d450feead28368d3f81cda0690e4b12e4e2911c0355c8f889e54c8f2a0b078e47732a651c0d713537e9229a0c4b9010001	\\x51e287d096df8d88755ebc75dffa94839f1c6de7faab98db7043b3961ef9a6c7bf450e78a55cd8585f65fa4172ece6bb388f67778c3998cc81784a8c25f5560b	1671961669000000	1672566469000000	1735638469000000	1830246469000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
7	\\x1310373e1cc41c1e99a2a98f12d8a383a3e69afd0915da5912f2cacfc8b35e8aca960a413c0b3ee3d9ea09818cdbbcca6b3571fdd338f32ee83e197f20d79c99	1	0	\\x000000010000000000800003a6cf2d141f6e80bc6bdff495f92a84a57e1eb9c30f982a31f1c4ce1951e350d80ecd91729d01bb07f8bad4d877c335d4ccb6813b4e53aa8dad4e700d0cb3b0c806cfb947217ebc28d4d5754d04e6a0f9477ae4db2f729a34a481518f819356a4827d6ec23cba4420894186ae2958cad87427d7438a0ddf42f6e6161d4912d319010001	\\xaf53bba38781f983df00ba6bb5d58eef2c51f0e38f98bfb88f1dd6a814ae05e03dacaddfcc366673d8fadfee782fb44d21c6a2b380527d151c1e6d23e729b806	1670752669000000	1671357469000000	1734429469000000	1829037469000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
8	\\x14e0538a9d149398bcaa00c14c8d00557dd0f5a4bc86096fbe851bc0280ad344c9ae88756f94b5abba8cd19664bd9262f3e26da5e27fec8273c9911914b8519c	1	0	\\x000000010000000000800003bc78a27bb99a13b004cdf1ef2e2941908b7f1e958ef739d76b145790108b87221c6de7b58babb2fa5378b477c33a46b693db9b05080d8b8b70e07795d7b800a2661cea2aca6bb5b29198e1680e59053d7a6d301236c78a09b4572aff288274b8aea8d1a42a064f37d03c5e9e142c54c046ec23c8a13d75f10ce3668301c1e6e9010001	\\xb763a0052ec8951956399c9c46bf670f40fc4fe93a92ef4608cb2ea91dea710d315235eaf6807da7ce3be0d650e780c921033c6127746daf2d5edb791f7cc509	1688283169000000	1688887969000000	1751959969000000	1846567969000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
9	\\x18d820026c436aa87dc65f83cd520e3f25de89eaf5877ad8507fa5df896e4077339746c896d279d6fe31053f762ba03209f6f3c71822fc6f120dd3ac08160c8f	1	0	\\x000000010000000000800003920d2aaf24e40023991e905f1789ea9f3e02e5582e9b741febb6d693547d2a92e9b91f00dc906e8bf918e1ce22b0ce20ff149c8a28fc0c2436e88975955a7edd0e1b69651c1105a1b6c6e4396ace4cceff7c89e71b7e1f34ea1b505bc98dca82de069b242ca45b67cd661db7708b2cca10f8647132e2769b708cff277add7f4b010001	\\x36232b145e5da2e3b45d11ab2616d197340900919aef03d471d0a5bc5cd239e19e675bf2da885734c975e64037899a47946d0069383b4dd4cc23f755e486580b	1669543669000000	1670148469000000	1733220469000000	1827828469000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
10	\\x1a98a29e09fde57f3a8e6c381ad9a01ec3aa4394d7a8f77db88eba7075ad3abf24ef80afb231be809ca4e18fb10a895e4fec899f08362189aefcb31f02fdc642	1	0	\\x000000010000000000800003f24f2a918a0928580a3d4e0fa7199011ee00034e91d5d82d6cd79df93abdec492e22f16d9e74ba99bbafb0d4fe9663cd5d848456c6add11ca8e864a5acc5d41a4060bb7b2c33adc26929044f8108509b086365f558e84bba597c3f2f169e8050606c170b274e76de12d4e75c2873c45eccd0d77bff921827e540957169b1ec3b010001	\\x7a22b6ecdbf7a776f09a45953e6fb96a15e70f4d88df23ed5fb923d01837374271f2aec20d6dc42283712d6daee698cdfac39ba64356d0b7d14fdc0c1d390804	1681029169000000	1681633969000000	1744705969000000	1839313969000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
11	\\x1af467f1c1b4b2e9749477deaabe58e0b8c2fdbc357b06a6b68ec416f0696a43f0ccdfdc320804aca75627ea8a51a5ca8aa7cab330e80442cd3bbd3bf691e502	1	0	\\x000000010000000000800003c83b3559b63bd304c70c365f8e56822635988b6b7360c021a4713818e38e130780d84c178cea7ab91cd82aec64b950fa02fdfa09c47716dc21289b4dd8c06a5cb23fdbe2de0d3edc564d10fa6b5746f6290918e1720c4768738007657254523e0bf6bd2ef717c3a07b3badb4ab7d6f0caafc9e7525e7e9cfc87334bbcdc8e52f010001	\\x24ac5f478728f8f61c96d98edd44b08235d530b9ed30904cdc1acd4ff3108936f12d157a7613b08ef532221b15cccfcaf8829252830eaf1e17756e777d22e80e	1674379669000000	1674984469000000	1738056469000000	1832664469000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
12	\\x1c44173817650954b6ec03a179442a6ec97db601fa12a7fc5568faa9a1345840308c4d755444a335869627af823af03ca85f93eeb064b2dd912965a43b3458da	1	0	\\x000000010000000000800003ad34579e52e7f5975f0262546579457d7dcbac795c92afeb84fc35e1d411137160661eab601b4e2e8f4cfade31ae8f14448976905e9532b919051cbda758e6662940556296a13f08695791c528150e182e22c4457c81d52b1732cddd8de8f16bb70909b76d2e63c9bf32cca01062dfa6adfb3f4c736adb0a44b2a154136166a7010001	\\xab08c0924edc03553639f07ec1868e7751df9f36bc6550ad016edc92ca49b38cd4b5a77644d2a1eab48942f2deb2cdf47b3fb8f4ae17eb421b5752618c027208	1687074169000000	1687678969000000	1750750969000000	1845358969000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
13	\\x1db48b3b389ec0d4af923cd179a4627e1a96466518cfe9e5fb62442648bad02cf2e8ce13c5dc3b7e1fef1a3c5189251234ed06975bacc863ce88d3eb79aa3384	1	0	\\x0000000100000000008000039a8bfecff1b8b39d93a51bac674955b4afaa2ee21a5017c60d7fdf117f09c68287f4778345e52758a704766412135366efc85cbdd106b25f5f43f1d3fe2f6f031c74d03af0c4e1f87b560e08b4a866784bb551d60634e165be5e955d91fae8008d0faf609bb26eaa6a79430926226f14af6d48d96b04113deae25789f9334625010001	\\xae32047c639cf8170f6d587540b243dc06195c6e005806c88f162b7a30c45cb011c545a148353a9d5181d35b1baf60735c40addb6f1d58c66d5c4ea335108f0e	1685865169000000	1686469969000000	1749541969000000	1844149969000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
14	\\x1d9ced292850f91884db8b8c69b6facf8e615a9ecff85797236713448c1118b2cf9fdf6ca73b6ae5698d26c23c6f77f5db26ea84c9902f845ca4c64d5c153d2f	1	0	\\x000000010000000000800003cc406fe0fa187b8f54f49136c42b510619e73e77624d652f05de57130f472fa4799fc98a32277cfd9c1dd6a716199655c4756520dba731bc34e56fb6c405ddd00b628abe3a105bfb8ebdf26e2d19a57a71155ac51a284fb54fe2b92e93652d4d6a7e0b240b7dbfa94c10aa734255a2ebe76609dc48423f44aa6cb1cc601c641d010001	\\x4dda9c8909083578690135392ee95c618640f99869a8d57c5b3754ece49f4bdb09ed64b35ae6e13d940e704ad97a35bf4a4085c86b3732869f052f4e2ffc4901	1673775169000000	1674379969000000	1737451969000000	1832059969000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
15	\\x20d02b5fb3d9f041b180c5933793c9bd485be933cb57999b1d3012337f46c3142a2c4f860ec7245135915abe3963fe7429f16ead9620c1d0de93f71ac02dc988	1	0	\\x000000010000000000800003f121926847696782dc4cbd18d3ec75464837934240d72b0b9cb5715b59ccbbf2a5790bfc73a8c8ab8c5b0b7a7d6d2172db42ceca62d2c7d26286e27ae68d0558930e2af617a02e9207aac23feefb2dac7e9a7c51460a9a1a30ef29b31025b00cc953c1a817028543d70faedd8b99495703392739cb44ba8b9098800d1fcc7ab7010001	\\x50fcd0a7efc7f0ad4766b604598ce5812fba80fe295e5a5f236eb8be39876ca35453f332336c86674e1282923b89c2d8c534d2fe9e29aa94601e28412324cd01	1675588669000000	1676193469000000	1739265469000000	1833873469000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
16	\\x2314cf2a9f6d739eb56905d5828692c0e7478989314d772a1fd16e37e58fa9a4192026365e80d3ddeb3495effc7d8c72a89bbab4c58f39af4894a07480cfe248	1	0	\\x000000010000000000800003d223223103526a068246e50a4c5d9fdc77c493f9c508cf47aed60caab740ac4ca8044194153557b47221f8360c71502d4fc2f62461c6c43e18f1156dfa152313b712f47e58f442e9b95713f2fa12b469b79e1e71df5ee36ff6dba2f6223d82f348c9a1f9e0c568970f3710625f18f1508cc9dd6bbfb6bc8259cbe48894aeb6ed010001	\\x9198b790c21e557280cfdb95aec597c48bad7834876dcb29dd4e6d76f799b7bcf8f14e56bbbdcec5a44838cf090928c6f594996722b65c0352d668cdcb881e03	1685260669000000	1685865469000000	1748937469000000	1843545469000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
17	\\x23087d09ddb0e7ba9de6c984e4cb7770b6f32f4287b173b23d8af1426439d22a39dbd30aa6c5431dfcb2990fe7f1bac0bf4247cc6388097f5fd8f1c5639d4ce1	1	0	\\x000000010000000000800003c0e8a5df235490e39caae60d09632b16ad2fe9ed93777787dcd15d27689d754c5fdabd1402f36d5ff3c88b1257f6f6e6d27590bd8b78beba01f578586c6c0d14510643e226a03e871f9c0525e64b591adb6c80c7fbea617b10046271db9145e6b85d3143f5aa477b9ae0c1496677deb8bda5ef3fddd62201f4b8c8b51798efc3010001	\\xfe257980319b7c9824d4cf3fb9f8c35e49918e593cf2420a93653df8353f0301b395c2eb03fee3900a3babe4bb127bea75ce996f789da616711d7784f59ac40b	1681029169000000	1681633969000000	1744705969000000	1839313969000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
18	\\x2474fb667d905a2fb689d1869032fcb29446660836c18dd6eddc8de430852e696808ed4a86d43b20eb26501d3a11fe3bfe713c035ddd20e5a6fd8c097477757f	1	0	\\x000000010000000000800003f3cd15b2c767f758f90f247fb06e44b9b0aa807c48d34b6952ab7a2a2d917c4e6fa3c2365f81a62764884eef2ccba8cad53aa9780da646c212c996b791f0c7b1e2203c0770f2353c7e724a182b812af45a3d728e5d398206919dae3b6bf2582a0961a60088155c576cecb34111b48dc2bf502f0fb423b409219db2eca0cf906b010001	\\x0a1d450469c7dc6e65a23b9cddaaefb8ceb35d066bdf2a5f1b73c6b3ca758b5182e00fc8993b0d2caef11c6e48bf4775e60f0f65948b9fb964118584d946b002	1690096669000000	1690701469000000	1753773469000000	1848381469000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
19	\\x26b87257aaa093717e509fee6cb136599442c0cfa135e8bca79edd16532c6d6465fb95c2d33ba7371fd1d8221342c036e7f793f2143394442f135acca7376d75	1	0	\\x000000010000000000800003a848f76327bf020622dff259e3a860b7194c406f356a3f5bc2672ea1fc775588d0ead673c317156ac5a3bb920c168ef642187cf97103fcba76506f3d8d94a1dbdb50b9fc226f245393b16a4360f215182d99186fde10c4b85a7642e2a4aa7157826edc16d14a56c3172e3969daebbc28350ceb81b55099f5a4331a5634a552f1010001	\\x37c284f4ca21d963ba50d213e310da51160157bbe697d6e7f7f9b876d754e17aa0666d0fac20cadf0855181f39ef486730c0dd3673c7553a19c2f7e86dba5302	1671357169000000	1671961969000000	1735033969000000	1829641969000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
20	\\x26943b0d78991fe8a173aa62f260d16667faa702c2362067cc0dc08faa5b84608383c06a2f8e80c44fc1acf0996a5f7cd5ce21213d4e91890e4150c4bddf79a5	1	0	\\x000000010000000000800003c2999aceacf8d4bc3f3d0452dbca7cf8afa0736d48c039e1032643bed9d1125e61a22a0cb7876b5b83270a789d5d3c310aab1f152f46277b8bd0fa4c5d1e0fd2400ede0089d7eb3708df325fe54934a39128fc6003baa24deb01a64371fe92b15505d1d62f3d431309e368d40ef238110d6c8cea82e2f3ded04ee336e06ab865010001	\\x9713462c2f62285bf31e9b76372e20badf4359f3a5badf58b52c47da84a7f5d093e310f9fdea7b8ec7952e8d4dc761feaf3b1e26b7ee0cd40af29f13d5bf4d04	1660476169000000	1661080969000000	1724152969000000	1818760969000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
21	\\x2ab0ab8dcb0a43ac04a0216ffa563c345e6db3554b6a30bf735e27e51bda7c20788a2bb6a3dfc0d241e34ac2f1e00cbfb15ce933940150acacb8dccad13a7dd8	1	0	\\x000000010000000000800003bc068fd4c543fd8c1617a946e37035a2e79e9f921508fc371a5462ec2f9f65c8d25e5bb447929eda630e573c175d24fdb0e5cbd49e906429af9fadf82f11b8a273368934a2fd914a0aaa4352958ce0d289e461cd476de98ed5419f231d8ee7e70a84f528af6a97661a5e862126d28d3aa4d9776a9183a39fede2eb495876b9e1010001	\\x1f8c04c11900326ff5adac92d8d1e34cbf2822e7d9233a84413df70a47ffa141f598570bbe78f4ea769f375f12ee9d3e885dc23f2962fe811471380db40f6606	1673775169000000	1674379969000000	1737451969000000	1832059969000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
22	\\x2ea8ce4917f3e63a3d941abfb6e74e55a35f95aa7cfef50c10a062a5e2bbf701a7b35cda39d814e091fd9a8e0a3bb0faccac19087c67aa766328953b438c141d	1	0	\\x000000010000000000800003b385c1b075b52db7ba24f95f784bda8ce4596c7f265de0b629f85f99dbb42c4c19def252e86b1306a772bc1e96cf3ba41b0ddeaf6ba6be8381cddf4a3456466c9b58b2eca1d2a5acf06947fe7764f01084dabc7237aad6d243ce9a52b2e11ac8517f4b6cb62e2753a93345a30570d3ae00ff3f576df2d06946500ffdfbaaeddd010001	\\xf538fa7a4af05f420408f4ffea9d64d0e2683403327752152994e913efb701d1c6661c615378d7a2a4f3e838db56b8d83b4413fc652ee0b96968b90d9910f203	1674379669000000	1674984469000000	1738056469000000	1832664469000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
23	\\x31a49bb4002a057991357ce71495eb7c73a55a238039b9be174d9ab87142e2a8eb722e19d231f08d3d7b490b845311cf3c693640e4a931be5f8060e9cbe7ae27	1	0	\\x000000010000000000800003b6c7f784085d1a5289335936b4d6b029326bc79fc2a30980da75ec33c8d67783dad7169cfaac352060823f7cb318fb9ee423ab8973aebe6a9980b6cafb6551e5a39b1efe07d0290c08311fa977ee4865d5baf069731cd5b2ef123527bb3025274d07d824f05843ed15eacf1960f66cd8a66ca45c092f9e09cb172a840b4320d9010001	\\xb104af80919b89c33eecca68d3c2765962905ecf4144d0c1d133bfc650262d20548f86eceff82dd657f6ec7d3a086c19ada575923c80c0d398dd3f56b29a6b0b	1671357169000000	1671961969000000	1735033969000000	1829641969000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
24	\\x32581d4fa06e4ea221b693ceb09653cc32910a8f5eeba9e2f6a536e2b24a760cf5e241d4ebafd68b38298bd8206c3d794e191f4fcdc416d0a54af08d05ebc973	1	0	\\x000000010000000000800003c85654ddadd5a88325066c3e1be0a9d719586af608a090db086526ef26b8f786581cf7eafba154108d2439100c2baddc70ef15e876927b545bdd7c5328b2633058f8a269a575f96506e8c0ecd3718d3281d1a20570ca88ac0d7f02e064b7fe1cd42b673067aa542788fca510a8ce0ad53ca1f64f3d68eb57548de1f2339c7f35010001	\\x6ffd6f7a5510bdaeefd3a328a57626c7b1072e522a01ef54b293e74f844bfe5f47ed98e9bab61774fffb2f9a89db1fde433cfaabde17f5cdc8f9924b4d39750c	1676193169000000	1676797969000000	1739869969000000	1834477969000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
25	\\x33c89c574a5b3f0a683bc5896d7abf4710ec2cfe7099211032903c71878278af2ca98b560cbaa475c4596c78904232fb35ddd3cc7fba0ca8e5e549e91d745868	1	0	\\x000000010000000000800003d6d4ea1e7dc5680a0232b3149690fcd4f389738ad2a5d4820073977ea94340c9916a01d6d27b21970fcff2171972a04e655388d80f54084a52f6205af1575355b2b1200186c3f532e0328b41e1097d6beb135481005cb5084beaef3725329be356396c3bdfbce0ad388650699841cd1ab5d1a111004cb75f411e8ed53b1a98b7010001	\\xd78d0cafdb20a278ed7414a20ece3e9ceb317dc050f95d0881bc066de7571a2ff0b1080bcf6e8e1c8521c0ad6fb438adf4da995057668b33c6d3117a33d9c103	1691305669000000	1691910469000000	1754982469000000	1849590469000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
26	\\x37e47d1cc51bee9aaa4071e14fbf33edc12be733142c30d255ea1b0399dac6d2fbaef5ec14afad38ea532a914980a023f72783a34c8db4dc70c6fe728b12d116	1	0	\\x000000010000000000800003cd3622c8feffe6f99979d1195f4efb534d612f8406f30ec62c1d1ce9297e4c74e5d365d963e2a5da123c16eca70e927ef805f38a93d162b4cd57ac22f3ff1faa69f150f75303647c56d5e87224bc1a3c6c88b0e423e2adf8691f72f6bf751dedaa938668b4a1f24743669b3dadebf28ef6ba980107ca7139fc055c7d04ad4d2b010001	\\xb59643425bac4c05d2f5b9ddba01cc371bf2917fbb1d4e644a5d3175ae6084d890827e2227b03efc05cc4a2a49ad769d9acf5e2fd330c11e5e1285baac552e0f	1662894169000000	1663498969000000	1726570969000000	1821178969000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
27	\\x3a58254691c0eb6dd94a3ca1a6af0452ee07f8ad2dd29ab013550d934317f8a54b3f220cb2d840fcf1f746122d08d6a8b0841097b58f1e1b9490c6a1c4e0e6ba	1	0	\\x000000010000000000800003e1470e3c980e9acba1c2c412c1a45f683326f831e2c8ff6169f05a5ca98b30eef8d231f0a56ae0bb4d1538178f43efaaab4302dc32a893365f6be615ddf060654e388658abe9ef616eeec53cde2c064359faccdc50eb23636a7cf74992c2a74e999791e0b85fb1b5096692def072e56c83822d5bc51e3bef816edd5ecd6aa1dd010001	\\x8409bd61b8b1a1c93fe86c92458f2b1b1a94b56e78eb9fa2c2202e56a14e9791c8cbc4cf063cbd8bbc1e1293f98796cfb7434b0f3bfbf2e5de94a4ab423eef02	1677402169000000	1678006969000000	1741078969000000	1835686969000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
28	\\x3a00fe292dd6fb41f05c2c6d0b3e74d938fffdc30b6645b30890d19e45a04bb04ee7ca76a6ea56414c86420e772e61c9c9be5b73fd4e1c9ac3fa05a4af80ca54	1	0	\\x000000010000000000800003c4aa1adf5d03a183b6638b1c68f2794f10ff4bbb42414c6ac88c26d60eacf89736389a3e121df6f5402218cf3a0315cea459a3350d206b3a3a8ca087cea18f237a8505eb82579eeeb5cdd036d45e58b3a0e1ba3b942323243aeb5c7efefefa1f72516bab527884f59ff90f57a66614211e6e049486af3c1891cc21989b70c04b010001	\\x979a85c32a2b63aea33e16dee1b8fceaadfd5a998f72ce56af201b5d31c3b59b926eda30090aa317ae1ec51a394e36f8c822d120d8d92ec68565250c252fa103	1671961669000000	1672566469000000	1735638469000000	1830246469000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
29	\\x3de066807f87bb0a338ab7b1941b2043c0320f22d0ec4bd71c3ead3ecff50e08dc22628a5d04956e96efaed5e540907bd1ecd94259bbf57db23c678d61ccebde	1	0	\\x000000010000000000800003bc4015464354738f4dd693cf168857b0a624ae5a0b3f35e73edd19764f4c23a06669837675c2a2166466f2c61115713ad19a8c9fb5f8dda2b6c02f16ae06ec422dc7b2226a3d53654de80b5bba0225b30da7045ea7ce66fedea81231e5d47b140710cbc7e6272d7da18d02243dbbf0128e494fd4854da556a526007653f65e7b010001	\\x8e2cedbd8df45adcbd2c106db8f4d35893d7a1a1b726ed6ee94f41602b7d0ee0ba18cd60b77cbf72456574e7ad05fdffb22cc0857a8fe026b3fe2dafd29e6d02	1665916669000000	1666521469000000	1729593469000000	1824201469000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
30	\\x412062a5a60cdd4f09b58a2b265270fa043b89d2db439521990145c6e2253afa2538d2fe00964b52a03546e3586d3faa94905ba01ec363be943413eed138bc92	1	0	\\x000000010000000000800003b9a8b38a845da61eccaae52781592d59ac1b2656c923e0e5be06dba05c6664696a083dc7f64f864553a45d7dd2744b4661c4582351bc64cb9bf7068fcdad0ad74073935f797f6a4d31a8bb3d4b6b848d2f2b3d00d346656255590b20620a76299c1d4b88d82c33b04b70be29b336731fbd8e60f8a6a6a56ec12eb7b1a0c96de3010001	\\x3e349fd0af9e606e46ea664a6c10ea066030fc3896f0bdce7d2f82bb3f5c60167f52135b1365fe262d6985dfa7e2a5e2cfbf35fa8876435a2f61599394c02406	1686469669000000	1687074469000000	1750146469000000	1844754469000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
31	\\x4aac3c832cab2e3d9e91153f9be2b13a9dff8c9ed71df8f986fea99817086046215259e3c1f8153c306dbe99650895e445b76cb408869d84fadd5cd75373b8f6	1	0	\\x000000010000000000800003f654802cc9eccb046d66009c241c825e5ed9c715a57713f5fc019f267db3e50bcda0a76ccbeae5979155505a044e07a94899057fd8d312627508adca7d790b5c38a855359e6995b46c28a7206a2945894c7d74a3cf18a2b1418937f7ffc110b81ba52387235ead989da0d180af6f34634b0b5fd5c24af25e6b6184c0749f998f010001	\\x4cab68bfa91afd5fd3739b499096dbba9178008c519e1b2095ac2489535a9a2fbfabc7d0d2c54a3d876bd03e1f403ba6094b3643707b3384c94fc7d02d2f3b0b	1662289669000000	1662894469000000	1725966469000000	1820574469000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
32	\\x4b842495a1ea00e09c63098a4aa4b3521cd9d19b23bc630b95c6942c998fe45f214c5d2da78e4e469cab28cd26d4c98505b8d70101f4ac4481d4f524c89e58a7	1	0	\\x000000010000000000800003ade46084b435295e40661c3e96f7e7fc4da630774e88aa81758dc75d08ec114e17d99c343b4d26cd3178809c07af188d115a93368113c4de8d9331d1271813c10d8560fbdc7d4602190d75fd6b33272d04737802d9b016629e188c0290fd9df3f1100ade2ed8b56ac95f6bd5b8aef905eda5d734f9fa844c4c03ef81cc0dd87d010001	\\xd09f808fa57930fb61d3cc4d9054ea10939c681a70419730ab62e33602a437e008179181fe1f86d1bcfebbd70d913a167c870bec64eec40129b173dbf1585c05	1679820169000000	1680424969000000	1743496969000000	1838104969000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
33	\\x56509bceb99143e2b7927145f54d689fe426ee9924d61815a01e5058dcf9f579f118ad524d1fefda7ec3d20d59949529afa4f3a1830343fdd81edd0ff37153e2	1	0	\\x000000010000000000800003c6fa5e166785f3ad65c0218fc2ff00baf8a8d2f69d120505e3afbdf2a19afdabc812bd2d1a08f40090b2a80db866504933dde424cc78c9d15bc3b1bc1df2c4729ad1fa99035d7bc56a1c4c197b2076169e614eafb95beb91a8fe79517f8d06021d10d3eb901cdef6677f09c6bf6de8aac8f848560b3fa16da441a5082f375597010001	\\xcfbfcb8bbb7629c662c2b6b0afcc5f2986e2beeec10762386301a2ac796fd9264daaab4f2f4291e545150324a97590d4763697dd86ff8ee306259402cccb7208	1660476169000000	1661080969000000	1724152969000000	1818760969000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
34	\\x5768419e335e6b8f108de31a427ab39fd435421c09635f4d336dd55e390be47dc46637c575ba247a2fea4a76e61450739d154461ec6dd28ba072c9d1b8fc8221	1	0	\\x000000010000000000800003dab07a91f129f8ea0036c161b4ed69e881400644f0c3f4e8b0ffc83de0eb1bbdde68cebebc27233401d142ea3a8ced8473a212eb2fb36c87243391ffd73c700d0ddc5d67810aedd4a4ec2713c086ea5bbf5f5ae98d4f3aacdca56234855a36d7c51caac7276cb246cf138db754dbac30a09da83c3d6a7fba23509da4536be7f1010001	\\x0a89a60c2ec5823dec4843be80ec713376b688a30f7de26a98229ddc02a2994a80bc3c55ebd612cb2e9621728557e544fd6b1b0ac60f909a0adb46ec92f0ee0e	1664103169000000	1664707969000000	1727779969000000	1822387969000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
35	\\x5accc7efc3abc683d64b45138cc50ede452e705928be675c81d4ae245e25b505c8db2ba8dc0b3a3e0d867c4cfe66858dfb49726e36be1543b0b02e2ec896ab6f	1	0	\\x000000010000000000800003bb13143d3ab9d94d933d881764fe903169d18407e13cb1a12737c086fe310df85426bedc8f93f8974eb521ffe52df4a8472273beb804b6e4629fb71f8a08da6b52df7676fc03bd7e05ae4fa271e962e653c6799cc8bab4e7ea425064fc3bc86aa46d1008f38c2094e45281f170845d656127ebb4a592eb7be5c18e0f7afd972f010001	\\xad27e082c251a97f95d5baa23dcbc9d16f5d18d0caa91b5dc4654316eccbee3a06e90995d6411e7c071a7226c9127c7657488ae070354f66e05f4d310d1b1808	1678611169000000	1679215969000000	1742287969000000	1836895969000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
36	\\x5bd0128f4b1e8a57db03d92ea0eda62d89b5f12a5b69cedcb54964a56acda77affeba43e1eefbb0f56969ce85611c3ed9c049cdd50c48784d0c7f45ec1650ad7	1	0	\\x0000000100000000008000039eeee87184d3b3e859d45103dd15aa4ac54641a3bd179d636a48c5ba7d0bce039cf29ed3d7e9ebdb58a1d16abe98e1a6fda5399d121be76fb013b5e7f6e005ac47956dc3b7155ad24c46c8d7e9bdcf2df015ad0ba35c248b4c73e81a83db047d3b7ea87d31aca4dd3082809df2b07fa37e9c1791500f1946a452cd26c6b2e771010001	\\x67b2f78da77dae790850b8f13edb10b6d5c945cb1fc18b0f559ed59df8b66a698b20c80c4d911628a60c566958712fffd22a7d59ed7aefa6581d0cde9ebf2307	1690096669000000	1690701469000000	1753773469000000	1848381469000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
37	\\x5f141fc2905b3d780607d8b3d955574eaea8e0633fab3016ce5392bcc43ec49b31e690f59c396fe7630c19b84d76f2e2f0bfd8608288775d4585c6beed032f61	1	0	\\x000000010000000000800003b7bccdc9fe59088b4a98fe2b4171323806f75f8babf7a25ad20c6ce376b49915f44a65b9ce02b0805fa9959c4ed137fcc8cbc8157ab38979a050bd679e8c4844ca08810d8083e9bacbb36b2c99951fe6c96275a140c89ab0576738a43c7b9b443c2105a10e018df483c13a26ed2f8f624d24556b1d7d963135875627a13b9679010001	\\x6326f33bfe12467a97127aad339c2234a02a4c7f94da049b8175980dd2ec749602af84f11a7a91e835d388397040091b1aebd96629b177044e9efe6498707b09	1665916669000000	1666521469000000	1729593469000000	1824201469000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
38	\\x60b8e290b385ec180676ee78df0f743307c3ed7506fe11aeea254df3ecb2da8ed726fb51ebfe7e9028d875aeaf7b9c65fd637882854926c1a23e2cb4f1b56174	1	0	\\x000000010000000000800003c085f8242724983c7e472691d38ab16c117b03c8e3e916f15a5a71325e77d63a1e9119b2c50636b6c3debd9b8d864e7c3535441a9990ed84431c90d5c04c324e4915dccce36a859bdd29df7bc174b5f1d0c084e07e22d1c03727b8a18ecc9d9a0d80a36fd899c18a49e1d4b431b528e65b996c3e8f992f05fb8f4728848315d1010001	\\xf677162327ba4445a14c423b5d27d25581f75240d8d1eace4538cc6b7e8af5195351eb26c66df60e9be5a96dca9771c71de6f55b0e71fa3e49223de6e6e9180e	1688283169000000	1688887969000000	1751959969000000	1846567969000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
39	\\x6208b434be985e8ac37218cf51442518f58c074748007e7607eb68498b18a18725f150caec8710b253bd87f44635eec4e7b105c4250ed54b45db0a5766a4bb8d	1	0	\\x000000010000000000800003bf090ceb35a40bbd143c01c1e191c0b03a6ffee654123c58a3b45f9511c298a47810c3de9383ca5c65eacf286846f35a17dfceca37cdea32d7475e1e180c0b6079e148c49533933fbd09b1fc8b64deff1f4bf1997fa502612e079b103c92f5f86e08119107f493f8709e195afb4b5397775bbcfc330b111203c180e836d07e91010001	\\x3cb59f48f1fe7f007a43e3a10ea09d4fcc15984f077a8b0d006cfd7488741c99f66e4a48a56ebe8f6ead43158c2cc1e07a71f8c0a5bac13c417ebd039eff9c04	1667125669000000	1667730469000000	1730802469000000	1825410469000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
40	\\x63c0514be726ed9696c438096972054b32e9fd931a4b3903715d295be1809b54381dda4b9016419143453d9fd7595b629d75baa132149af65b7ec9e14304f990	1	0	\\x000000010000000000800003d69940a50a0194105d5fef82d7b83205d0a5a93267676d22582333f72ad3b47293ad9c1b3a4bbd4ae89d3c274e2f75bfceb96ae6833491518d62a7a98d0a25c9ab102d6d0871d3f2e852a6a4dcf0854a4a75d59c49819dd7fa56521067f636f296648c72b9f95a2e274067f087bf0f17e7563e593a2f5a16ddca8128d7766661010001	\\x4a8183e657649a9207b5ed6251b506c8c075662e6962936a659a96d2dbb9dcd1a0b1b09ac4b3660f51d3be9a64db3ac612c60131d3b71338a808fa7f40262706	1664707669000000	1665312469000000	1728384469000000	1822992469000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
41	\\x6738271d60ce659ad05e85a94b99ed23b95f468fe2feaa34fe3680f1509e21641ad9e467bfae426642b6a9fff30b0dd4b0ac4cceb82559dfd49ec2b6209faec8	1	0	\\x000000010000000000800003a687b57ce8f464572ea140aac50e1ab146efc8ac95e93e784bf8df7ddc8561a5c45f02ebe2f48378834edad10816342316d90fc51bce70e2556ee4f2534713fed6361fc8a7ed6bbdda7ab90f56229372c5c293a8e002261819630c32574b6b16ff30ac5ee2cec24db1d3d6da6a1b8af793646a7019013db8e648ac5fbf5076bb010001	\\x02807dd8d8201a7259a1ed0558215b25d643009364b9b3cf498297016532c997a95140102fcd42e377ff3eee88babf12a5a25026a8d6621c7254a2f25b808c09	1682842669000000	1683447469000000	1746519469000000	1841127469000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
42	\\x68a84d673f5f5cee8f28e763ee588e1adbd0959292c4bad48fca94b8d8d5a269198121ab87ba08d47c0800afa15b2537c77e3498c8e24ed9aa0e05b2e0f073ae	1	0	\\x000000010000000000800003d2575d183af648fdd31a946528813cd76fdfb2cbea867615e06e1336d04060ab5ed00751c3f80413b2d5e0b9b42b4e150a4a4082f21f1e7edb5c7b57f0db6fde4188cf9835b174dd3deeb06bd61dcdf3ff9a15471abba222bf58745941cf2cbb9d67b564ec9c28d0bbd5c48f55ee6cf8c5231f5236be4899f36e8ce063272263010001	\\x8587fe7a07bb5093edea8ec541a98f35aae171f8371743552851adef46feef2f48113e1b3cae4d7cd3865133a6c0b7260bda8f2f0f20e8396a9bf2c5a046b70b	1679215669000000	1679820469000000	1742892469000000	1837500469000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
43	\\x6920d886280aa24d8c80b4a418e2868c0d933439b1433772eb7a0ba11639d357d11900f51af8e170a3551d5b033edf27aa0663ae385a881012dc886cc3742424	1	0	\\x000000010000000000800003a7f8a76f57b9931f117077b75abeecf12e04dca46fb894f2744d0d9c1b92b1f6da72827779238c0830b2d317e6bc053b8559aed0f84cf163673299a160dc8678dad3b02544b77f4e67cf9af84a635a6dfbd1a5d30ef7382b8abf86a3db558c9bfbd3889febbc55b799476e77e2ec3298661e570fb8633ea1de8ad2becc783263010001	\\x89f869cc97e0ce3a8a9ebc722a31ee8ed4a4b975baf5779a42a04a32e43e9bbade34d5fda21c6bb772240d5f7329f06165de973f3b28192e643544eb4d3a6900	1690096669000000	1690701469000000	1753773469000000	1848381469000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
44	\\x6c606762406a5ed94227862a43cca2a7f4d5911a6a31a63fee058e364ce4428b882e7145ec398b4cec8c06fff0f147ffd0b1d1c4573f12100795a107e014ae95	1	0	\\x000000010000000000800003ec9958c201973c086677da5cd8278cbd24ccc2428cb79bd7224628c81f11e39ceaa9ffb21a9eb9633cd19c0f66e7b1810814e259f4a30e2209803de491c768e9a4c561d06b7952d7de8619c1987a8546496dc92fb59fef233af85f541308d30dba78d0bb31667efed74deaa69c9592be273fb72651a184f016b580eaac0a8bf9010001	\\x9ab55f17b1d557378804e70bceb5677dc0e0c7a4b68fb4044d99bcabd0a0fdaab299304c609956cef01ddc5266fc9403e232d490b546701cfeac72b8ed241c0e	1659871669000000	1660476469000000	1723548469000000	1818156469000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
45	\\x6d4023cf447df72cacdc4e8f824f7bc48763443a6f8d429c56e7dd15a01019519f72c0b2fa18dba6fad448274bb2e9443826a1f9f66b65e33b18c9a7ff342293	1	0	\\x000000010000000000800003bea04620de4819440f83671d285816ce46796049a8796aa6583dde60acc390796738ed0d5b953b7f8d991068b81d832101a8db54ad3af9876c6ae2d219c46b877710dc6c3c9a0dc9be4267846ea176252c9d81186bebc67f00f3d61a416abdec3c8db5a6a04b84aea2da411b233c779c5ac0edde2841fd876636d03b8e6bf2d9010001	\\x32540e8215f35026a6d348b308f074cbe966e6018e6bf14d3acf6d1d69c8feb9a5783de33de93740d8532e22bc6bec8be9dd0940ffc155a9d59e7accaa1a5c0e	1661080669000000	1661685469000000	1724757469000000	1819365469000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
46	\\x6e785b74e8c3be03781617002297a458c4892b34f5f34fc5a48d0c3895dd6affddf85820b3cae80822c1fc4b6e75de07ca5194f3269453d5e8d843852acf83e8	1	0	\\x000000010000000000800003abb80e0c37356f72c90ed0826b55a395a9f802527ed556bdc4fa2b3ca184ddd08f6072f22cad19774bd55edce9ece8bed44a9adcdca443a29e0c1b11dc9ff7dbbc1416937f63b7b20702295278977fcb58e6c4ab65f335c78a0388aa0b230c0bcfd51007d79a2f8d7cc6fbb5bfeeea4f5e1ba5484d48e42b58c8e6c190d4eb3d010001	\\x628f16b4dd853474bf7b93c7415405fb6af2b00b6094e4d7087e14ed2c592a84d3a7430f0a9bc3a634c21cffa4e7f9da40553c418c1d9456d789d5d9c728d40c	1674379669000000	1674984469000000	1738056469000000	1832664469000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
47	\\x6f88e9159158b52bc4bbef0ead1512b21e6fa55a6411f4812f0cb72a6719688d20d2640954f83e610b5466abbc2a60ddb54e4a9de56594c62b3e22b543892576	1	0	\\x000000010000000000800003f721b98be1231dabacbfee099ab50f06cbc6c01a4abd09292ec9f535fb33bc88099b08b7b9b91b53e2331fe1f440de5cecd41b7793728176ff1903a2c8f345cf7ffdd0331b61bbfd849cef2c65d5ccee56086cb3c743b0574bf5dd040d60aa00225f3ddd73f960f0bd980f1e72df37b442d038d56cb68e6eab35484fcc18f067010001	\\xdd5221f226ec7a327532c9754710698d7bf85b86bb28c6b945f123fa7bead9ac384776d9e1f5eb469834482f4bc5e2d644edee11cf3f4e4f1f651f7b00ff3308	1679215669000000	1679820469000000	1742892469000000	1837500469000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
48	\\x717ca7af1dfbeaf0167f38a3b8896e26a32e3fb630a32d0ac9fab302cdf1b30b8342d6bb536d2f254a816de34b5136bc4122b8d4f14e6ee7492de1e81d3e367a	1	0	\\x000000010000000000800003c63fc6b6b2b97f50c0f59a43fb10f2888c5464f29dde4469c2fe1ec610b352e2ce193a315165fa77cef0e972ec0e4053950b883498e995dc52ec128ad889e746f83499adbb101b5d7ae200e1e076758e2ba1eef6f4ac4f2c5a463bb12b26fc59ec64346449bf7e0ba4d63690da2ac1d3be3b49e37a536ec55d2b0868ab680721010001	\\x3d49110d5a64a82fc15ea4ca73a6a69d635b9040c684491518d31df4cb94450b36897393b1fd3ab10ee30a64e241a434635cc61b9eb300c6d8b9199e69918104	1661685169000000	1662289969000000	1725361969000000	1819969969000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
49	\\x741c6ba8aabf4c8f959d6c52b99426e43453b23edd1ab392a62021b04019700898e0b6450a4f56faabb46fbc61aa9111d4d5f7d4958ac2a9408d6211d0f9d494	1	0	\\x000000010000000000800003a1c64bec84010a1f960a4e733294a30ca7eacc550d2a40719cd8b1e117daa8bd791a77b16a40be15dc1a60ff6bf4cfd609e8beeb178f89364534ff7f876f2cbeb02d1bc7cacfa011fa56e3356bea3f9dd3c67c50fa8623d2027abb61fdb3a5d67bbede8c02972da728e05bfbf76136a7f1c69613a4d2031665becdcb6f6e5a13010001	\\xf2656f78ab1fe90c4a6aadf7ef992962a1f92b8c0639682f1a3fd6115d2b83b108fe4cc81d7b3fcb195d6296dc34e1975598df2086bd5ac1c5fb55cc2945b906	1691305669000000	1691910469000000	1754982469000000	1849590469000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
50	\\x74dceaef8829e9dec7e2e231ec48fb4cbd46271c7e3d414dcfb1ca3340c8dcad514bc92fc889c7a0110f543b4865de1c5fe562a29a4ef0b98c501c51cf2916b4	1	0	\\x000000010000000000800003c135d56d4ca9d21d19e4ebcb4265c3afda79d453cedb119861b116ed1a255c8c0f6c926e0397c521c8ca29d4a1563dc25a4b3d09870bb7339cea1f06b8154fd9d4d7627a5a6b29c2b0fc1b16825dc1b19c7bf7f1633be7c314767ef5fe92a62be3b71db91a8d0308a5f2b93f537298616e55b3e312069de9d6b6c42bb332f48b010001	\\x8740641ff39d73b0d688a9d38a889b1c17289ebf89937959e206a30a72231abba9d491a4122d1f791a2b8896d165ecf9ae138cd310811e80e17bb3ce529fd300	1671961669000000	1672566469000000	1735638469000000	1830246469000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
51	\\x798c8fcf7044bfa750f340eb402a48cbc49764729a0bc22cc36e1e11507fe031ac664e0d348a3bcdd0fd215d4a8d175c71dced448b0962f8ac489ea0ab15a42b	1	0	\\x000000010000000000800003cf489ff7a2c6d1a91827fc2774e3c3c4aeb43a4c4fa9bb9d6cf1f6de81fddc24dbe5cf8925ebda1185450f38eb53a3a1b12a643bf3da746e9db65944270e51fe19b436ee89e724b271aacca5b60a5c3ebf5c488c70a137f6c89d8c3385758028c30d8740cc9ee7e90ac5b47fd2c5a751dc74824f37d4985c83a11dcb8acd930b010001	\\x0b46b46c3de99dfcb5fe2fc573b89522dc77677c28e5bb9f2da38a4bbe045e327edaa159e50b280318f323a6d243c73fec1620d57520ac0edbf347e6ce8e3e09	1691305669000000	1691910469000000	1754982469000000	1849590469000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
52	\\x7a90265d7d53971433759d5885b8f8cb0cabca53dc9e0a0cf342b68f82021f8fb2142f6114c8c25a588ec7787741a0db8dd1351bac4b1f903393fd17b97ccfa4	1	0	\\x000000010000000000800003b6d2df11299845c427271ff1462571afc92435cbabb987728775ff188cc3cd6e7fb4a27ef87b1775af3c192b4331c15fa1e4d9f8ba5883a89d47970a9a9af962f78732cc6266e39c9f492100db64202a1dcab377a45db968562a8c4d19fd2048822a0b3843a648ac8a6e3ba0aa197d9eaa48ef51705139b9b2d6ab6e4042d747010001	\\xe68edc1a38e9c33b0979908f9fcf5c84f6119aea68a27f83f8292e94974eee905aee660148acc6cef939378576f74ec58172deaa0ce6616b9a8ad9f9fa170002	1667125669000000	1667730469000000	1730802469000000	1825410469000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
53	\\x7c34307cde24d88de15ec2379dce7bdeee5db95a2303969f623ae854670814118d911fe3d3226c8ff37dfa348d48f1b51b3811f9a26ca2bc3078a59820b26e47	1	0	\\x000000010000000000800003b3609cd8e337b5d45393ce39c8ae55303c75ef218f9d096cf2559fba3c0465188a65e54e2bb527d4aee766edc09782edc044ff79d1df47212575782cd8a79551ca2d0b3fb2ec1579a3e651ede0ba2e2017a0ec871911d1642fc70b855f435400b8e391650865497b84270a7207a343eef8229e46017eff517bdeb0924a7cbcf1010001	\\x80b4de2eab392c719fcd99ed3bd5cd52162010f77590b41ed27f10b751eb44efbb681e8c5065c7624b1da7982bab9ca216abfa31e2b5a41cdc80cd03d752c605	1683447169000000	1684051969000000	1747123969000000	1841731969000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
54	\\x7c0c3c27c426d85f865b5f93d73a3f613942a6bb3b98092350b224e4115990f57933cf35a775dfc10d061b38d35aa8cbfbd05969fa72fc3844f5ec998c5d913d	1	0	\\x000000010000000000800003def379472c87e6616bd475093bb1dde255d059988266054164f62bfad4b952e12e6176f09454413b0532a897719b26338312090694f185ab4f8b56505afa3edf5c3551c85601b15fa59e5d3507f8612b73468fa9c872a7b5113dde5f38cf8bbb853d7f68bb47a87f5f472f7620b52de946e9ce85b5017e3e4552e7e6464ab0c1010001	\\x5e86385e67b82933f45bc583684be59a1e808b0616a9881fcb2194095825a35312484d07d49527d460c561c563c5626efad29417f326b95f1eb040bcb44e1307	1667125669000000	1667730469000000	1730802469000000	1825410469000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
55	\\x7f68c579ed80036dd4d1fc9fe1f7569a46a8ad8a9bd432a2074a02e02dd58935a017b923d3042f13b5606226c8248e465c533f6899287687c77b6cc013b8474d	1	0	\\x000000010000000000800003bf1d6635b07ff0c7ebc9d18aa7906452745ae49d01da55263d3d6d875fac6c8741c5e2a964dd2963eac3e9cf13ff5390355d1dcedcbafef15419d4222c7265db5c592310af64be1e58ff3bd601ea48657001a1500238af1a3fa4260e4a1b75f6236351c2edaf41c668a1ee2287228f6eb37e7e7a4e282cdc4218066ec750f5bd010001	\\x0134b38daf792ecb038a6d7c31052cb3c8a2d9b2fe129d228058ca7286df71466ec26df03b59dc69565afbd90928428441a17f34f12b05d18e859c25ff68a703	1670752669000000	1671357469000000	1734429469000000	1829037469000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
56	\\x8124aea05fb0a93ff3e8715b419dcc2f7edcee82633e966de4fb41f44a3ac1a6106d02337b274b8388007f6719ac7ad3ab079b9a84e127cb065910e1d5f6e885	1	0	\\x000000010000000000800003a9de08318d43cdd99899de32809b635e3c29908b60bde9583a2091e0660e8541aa01f6d05d2543755525a16b047703b85fb70da0f24b53e0590a68fd3e7fab8c1e5715a7d8d3f6ed3d4e840a5e742e3fe8461a33374461e36a2d8203c84c52ffc30e7463389818a875341236229572c1340bcd4487789319951a2b09e4350b9d010001	\\xff7432ff3029edb080685784c7cf5ddd8a75b20290fcff57db136cb4a1989a467896500b01e8002afc8b07358e09fc91f44af8cd94070a6e01313d58c6bc6202	1673170669000000	1673775469000000	1736847469000000	1831455469000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
57	\\x84d4f51129307b89b8b15a039d970a8baf7e426f4a7f2986671aade65e11a9ec3fd71f120d6683cd4e2d40e78cc71ea521b799a4d2e316a1841f999fabe7d330	1	0	\\x000000010000000000800003c0ebdf7f838296863994e0b3ca30dd09fcd2dce912e325c1bd00ca0192df50b7b7bec366f51f554a9bc57c9ee45d9fd403a4529d1c7fbf76b05273ef5c76b7ad39c7d0bc6a8051a0b6f1576cbc400552912aefc85aceaee279bcd0f4b2d4340bee93af88209c2e392c0bd9a81548efcc9ef33f7affe4971e5a021ed285b3b4c5010001	\\xe9a0b6b6438a5f49772de569add46bfdd38259e8187a5bb13bec9efc509caa3ecd7bed88279590c5244a30fabcd99bc601db556c373ce5f19c97b3d534e83a01	1661080669000000	1661685469000000	1724757469000000	1819365469000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
58	\\x85ac440542f0b5b9ed9e32bc3dcf572cbc35df20d3e8be2835177dd0c6af4a789fe89394faeb85d19957bafd8d0b4950c43762c7403ec4914e575fda483f7ffc	1	0	\\x000000010000000000800003fe945463be35d6d8634daa1b6204841965fe59515e6d42ea15aedc9ab9bcd473309b17912316639b1e180ffcae461796d7812ac9cfcd40acfd4a6c3ecd20f8b8a0cfae5896b4ef771b5b9516636064de8e75984a7f64234009e6e676a466aa1e43c1d8edb255bf70b83113b9213f366e96dcd78d0aac3a6c4b7240c73f34a7ff010001	\\x01786c47c1ff793622cea41e6fe314de59e49467b63a1372c60c2b1ceaaa56011fb1c53db80aa2f27e42e469a4e77584e716a5745d975c735f559da63d15b10f	1683447169000000	1684051969000000	1747123969000000	1841731969000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
59	\\x852838a90091b537d96bd13eba89f3620462756b1fb224a78993436617f8012e9948a6e0173e2400e4f63d1c8f360e1d88a3921f6d570a3911656a3371d93c37	1	0	\\x000000010000000000800003ca182f8ee145d0ee0e172e9666be98163a2f81df87a0cd281fd353f264fe00ce581c1d079b10488430a11ef67206f2b8cb457675ec0f51e84b5954d94e6755c38a58aa02632d0acf7e34f0999ac1f9f3390bb2fa5f6cac08479b27928c4e9e87a8864347ef8a4558dedfadbe5bc94ee7468131050b4aa05f61f1ca751f3285a1010001	\\x97c3c4964bbc10fa71d461e0c375254c730e1fc869f20f4ce022b1f70ecc9b709fd1a0067a04bb72cc44618caacc4a4463c0775d4d6de1f7bf8b7b673a82d40a	1663498669000000	1664103469000000	1727175469000000	1821783469000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
60	\\x87ac87c47df8c8158704441c4c63e6ecbd253a5bc5f21496a850d94119ffbbe4454a29f40a0a9d1ea68b11197acbf1781b238f76bf12ae794ba5062c5e313228	1	0	\\x000000010000000000800003e0e4ffcb1d95265061531442f160887d97ac21d25abd9d5ca711045bf99836fc7b7c6e878934ed530521084823b93589bf42ff4c6ba11703b09bf11c7c63416668261834a2f662868f8e928f97a29e506c2b9a78278e2b8fcc67055d6349a4a76a70e7c5a88d35ebaae499df275bbcb6be31dca465d988231f974522459c436f010001	\\x1aebdd75d0c3c109f13007e94565bbcb69f616c2d0d98766801843b582de14b5abbd3abe06e18eccd43d6d9320a153e88ca5d095ef0ff2373e922dfe6cf5ce05	1688887669000000	1689492469000000	1752564469000000	1847172469000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
61	\\x8a04b2435f11c6f4041e92061ada4c88dd031932b5efbfd834e7d3f8c9e6d80bff548cdb08d798c93e13a3f3354428996ce24a88485bd883db90270b9bd997bd	1	0	\\x000000010000000000800003c90eecb416202ba59075998f5c08a166420a229514bf6078b52f3ba5a5e6eb5575ecd0cb8517a92f7cc0cf5818674ad9e7d25a8e6f5226949a80bb555c53fafd905de20b97c6d62e67bc17d9892958a4d9d1b9969ddbb72ed7bc965e232cc6ddcc16dc7e86004349c15b873029ae9964ee136fb87fae3a70cd423b1b9e43ac9f010001	\\x5c347c977a7fe2d135a65cd560d6fa642172f33cbff95d1d9a09c25de527625ae3839938f347a314a4744c0ee59888b210b50eeb209d1e98dea5dc45f27b1404	1674379669000000	1674984469000000	1738056469000000	1832664469000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
62	\\x8c0446dd20062e64348c2e1b92494e0b4ed65ff26c8926d20e7510b1a8d0fd86efb2bbff1888f4156af30cbfefa0643645790f4a6f935734d28854bb418af291	1	0	\\x000000010000000000800003e7af50e8f7af5528ec5165dc707853953aba725591883d60e541f1361b6fa5c700d4aa9d56c9e06d5cf13c94c242e9e41bb7d5eee16409fb3359cda61dc0a551b74635429f228e236e60f5f1aee8890e1bc3b8003ae51facd71e41b77a23366763f85dfac5d41df535145adec4ec6f180e59733fd0d0dea9aa76a5c70423ce77010001	\\x29c545d7497d2b28b7d2985e5a4ee6113d8890828ca8283695a5514626bb517a7ae52a8acca2f01fef16287d8d4235fd1573cf2a8945ecd0d2a38738921b6509	1675588669000000	1676193469000000	1739265469000000	1833873469000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
63	\\x8df0a2e49ba9fd6d2911fabf828e98f7bc30ff55305830b471ea14d2714e5c5e330c530c4e76b663b416334874b81d9edda771927adc499264a592634e02cc13	1	0	\\x000000010000000000800003ce22c3cf984adbad6e4c76233fd5989980318e829216027529ef1c989c1c604760e4c529d9a1100ba84648bd9065bc75370b13693743b7a8bd0cb2ab5eaa9dc9455513c7c0cf5f19c06d8c12fdf81ec44e95c27e1deff653c867498bc4b536de802a5e5c5602b483807003920e9066a9119b4fe2ab64303ab85392780512a533010001	\\x9add3f142f2d4018f1d0af06e4152e39ff9c5ae61b136503cb2afb460cb343f06b0b56c0e4d525fba58e5f6dae3274e1ed3ea45673e607c26f8d9df7a6f1f803	1674984169000000	1675588969000000	1738660969000000	1833268969000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
64	\\x90f4556ef808ce6216105c7384fe90ca7245d2e77eea4c03c0e4f9c9a8719941e0bf82cd1ddd0308a616eb29219f36586917efcce9b5bc0ea015c7ce1f575bd9	1	0	\\x000000010000000000800003b8b744598b667aa7482cb2848ba575e9f91e9722d101a368dc45fd901ae4155b79f9c8e42c6321418c63b3cc9e39212958aaffebf8d8bb6a18c43d4c372d28a1be026b132281c6ebb92eb5e544cc1e4dd90c0a28ade7d943c561584b040ab8b2fe57c056b3f9b1f27a5c38846f568f4db3a31e37f2dfc4f171647ea88afa04c5010001	\\x58a99c2f81c224abfb3d6d0993e14cbdf2d1ccb046a9e4ac54b9d687c85a377192f74381ca48df80ccd27fe36cf41b1bd4301cbab5cf731e1607cd9bc5d6e109	1661685169000000	1662289969000000	1725361969000000	1819969969000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
65	\\x904493f61784ce6b7e9fd4cb74f496ce19c0f79897073df49bc260622e17994d342a249431dbc6f6983573714456e308cf2c475e9dd05fee1fb55b27028815a8	1	0	\\x000000010000000000800003bf2aef471eab7117a7374c4286e7ec61c24273383d681d1b4603c7f8adf1fa6260ea19430f3b2e160735d6145feda33f66f7d3aa323ee7c437ef3a4dd8015649680cf7705e68b23914698e89c63a0a00ac7ada5656bbaddac45ec306e8c97665cde57e004d813f545d47c03e8041d2591e54e3ecb8adfb17453d38a754ac27e7010001	\\x78502380d08d79baddb7b6b195a6d4d4c6447bdc5a76c8ddfdd17791ce721373ea101ee2db85f775d842a3bedc928ba53ce205ae32b72ea71b195a52cd9f5b0d	1687678669000000	1688283469000000	1751355469000000	1845963469000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
66	\\x92a44dd252463925601079fe1ee94b6ce8ecc318210519b3882e6f07c32fdb4702621c94d5276c2a5e268603a117c16155491d197eb2e23dc82c927ecf785361	1	0	\\x000000010000000000800003c7cfaf0d79d91e30361473e812b6e02bd38f0946195b1c6d81c17c458b1e5d014e4cc93bfc1532b3df12faee51fe7fa3ea54ffc93815a121702d76fc8b3e7656ea716111ff156cab009041866709502ca1f448294cc2b1de455df0bf03177578085c6491d25071741b2b021a368c588462bd499344cae079532c2320fcbe0e33010001	\\x8d4810fa98029048a6791ab7f4d8c89a3947d2d6a92f1cff8a84ecd03295430b0c6d823675533245f18046ecf0f5f35ac6e8dd63e84d6b0e0ddbb49e2b917204	1682842669000000	1683447469000000	1746519469000000	1841127469000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
67	\\x95841cb88ba1ace09d71521810682921b7663b62621d457408b645af590e661fa284a73a655c2deabb3540b3e5422997c0d3a62b7bb54acd364d3df222ed731a	1	0	\\x000000010000000000800003c8b13b473bf01c7f8667f21e5240b385eb0a3fd12f1f50970d24af807dfb7ed57f1cc8da095bb190be5d034bba874a10a2f22690c03562b3ec9c68656f4e61df2c4522fa73b4307e2e15a3a9f30ff62244c5f9d58e3aff015edb599c3594cc2418b716d17de1ca20f8236f4bb8eeb3f4dc44d03ac806405d0a2f7184e0e0cee9010001	\\x720e0ee745d21471f80686fd944d5a46eb335b9377a0c2e3868241dc572dd9f3ebcc5115c15dddfb6034359ccd3e6ca76f1a679b208a63815de415f254464a07	1676193169000000	1676797969000000	1739869969000000	1834477969000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
68	\\x95c493b05a7ce314b7068ea0d7a79caef180f7699bd89864bc959f7148b8a01791b826861995268f09f79d7a6ac61f4aeaf451679eb9b828483721f3b23a6a4d	1	0	\\x000000010000000000800003b616ba82fec76b5bec08fbb1d44d85e2ceedf401f39818b16b6dcee93553e618bd7338297835cc4b57fc5bf65db026998c89d4cc5e044bc99fdf64a17d4f113d6e2877cff87806efae4343174d9c3a0cd6c99799f89ea4bf3017f808c03057ac20cc40b6c703051a1aa6dd0f687a2c612da0460530a0b14a8595ca31e5e44ab5010001	\\x6946717030dd375588b6263cd0fda1e119939f372399be35a07ee5c406e681652749d363a00109d0c4b0d9b05e09bb3de2ae383e294f419f0541d7163bea3e0f	1661685169000000	1662289969000000	1725361969000000	1819969969000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
69	\\x9ba0d7c52aee2bb18433892e44ab55814b84120081345c71d92ba40a1aa8230dd6bfd240f76bf2246139f10a3d511e32334492b7cee5e19ea8fdaf0cb55d6585	1	0	\\x000000010000000000800003b19aee39567e02493be41bee04d2daa228b3db7ec660d8f51ea0f8aeaa9b9986638ee4df38147bd172f7eecd82e42356b9a668ec3608a223dbfb8c138993891474bd5d2a9a1e670322a07add96ea21c88d489519e58402cb7b3ed7c4bbb73adfc98d3ef54cf54a3340a7ac644f0ec0835ffd1ea4693bbf449c79b168d1487e65010001	\\x0abdaa0c7e62b666e90603395a1d0cce6d1fb70c281e5e3cf666ecaba6fb6fed2240e879bd280087c1817825085a2d0f469ad00074f5bb65b091d3e480c7080e	1689492169000000	1690096969000000	1753168969000000	1847776969000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
70	\\xa030848e4c65a15b0d1d2c789f1934710c77fbd3e86155fc4bb4c85a36c2c696e49c9d5128ef9de83a6015bf8313c009a92d0a93004b03ec28679fb5665f23a6	1	0	\\x000000010000000000800003b4ff799bfa7046f5d7de062505488eccbb8f5c854fce374a4bc3a144bdf0d92fdcef8f1b20e4c4632643f14bf8d5f30c68aa2a6941c7d49f1a708e8bcc3f58d632dc4c5d55bc553c8ecb8e202fc1f086f7d77b6f0955bf74791a751329fd83fd45fa8a278a61aac0957404956604705ca592ca69dfd8afb977953b4830c1a793010001	\\xf39e39e5a4e6f44d67e1305470a3480e6abdf92145daeae4e20bf3ab5ee7f44687010e07b2ae1d31305bf3da6102bbff40261f5d44c3c741924a9da8b3065305	1682238169000000	1682842969000000	1745914969000000	1840522969000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
71	\\xa37ca26fb60f789af592d42c145702c4ddd2cc2e7e66357d8a8bc7b9c6951003399c0a34872b059edf5b301db73b0e594edb85f99d4ff3c4cf90256f3e3c120a	1	0	\\x000000010000000000800003b24e7604cf58f945d39eb709026efe4e24f7067833486d415c6a6ac5d38c1cdd308cdbe2ee0787e8f9eeeaaa847835b56e3648debc087c986623bfc314e2b14b21cd09c65497c0f96d49fb56d000cd00e8f796145b41a039864e33d2e1ad5bf425b1b7a536d6a9752f2c27efc0a85ef592d11a6a935f744fbe0ba564820e7c21010001	\\xc8c722bfaaf02190c0bffd82056afcd193a42c11a2e01793b2b96abbdeeeb75a561ebac3106abc23314de3271a1629e97ec8bcffdf0f02817f298907e12e8902	1679820169000000	1680424969000000	1743496969000000	1838104969000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
72	\\xa618980c8472cb9ea763977e76543df3491648e1af2e3b22b8d7864ebe49646a12ec18d01bcb62a02a578a0e0537a440a67539bbea078c658d38be601549e44f	1	0	\\x000000010000000000800003fc731fc3d1bc2148d59db2226e6fdc6fe891e60d261d945d7f08e681141222fef9fe2eeecbfbfb9034817a239b46f844f681ddac8f718cb1c4c6c3d95783ede6108b420f35d73a90f069f310faffc1451f25e9ed9d3a80a83828bbc4e2292efe0d186cc61c2f925b1a0fa766d3c7678a789d3a4758ca010bb7d5817d6aad39a1010001	\\x3f8214991e030f67a85aa1d3bbb258a02ce027207e7952985f316c5e311d41c1750140a60c228857f26f83ac8ea95c399e954ac74d5790fb1baf3a1329901109	1667730169000000	1668334969000000	1731406969000000	1826014969000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
73	\\xa6109fb105630c4abe339cfb31cc44d5d5b681b6dae8a59e88ee1689c5d169726a8ed95ba860f8e5f3d3d23ca84dc377f20c8aa699ed188fe17607e13d627829	1	0	\\x000000010000000000800003d06a4907592ca1cc6025a5393e99a849eb0ad7fc270c7d122fbd455284dce0b7e11db2970f56615c283d096915f3947bb176415750007edc3080e07e9a2279b6c8c388777ef24444d1b875b0199eb327db75c1b0ecfe08abd01d929091589c0facd693cf2d51219aae90b9235fa12ba6698e4bd272a1bf168e9638d3fd049327010001	\\x90603344a4ac384051091026fb98bfbe678c9bff05b2db07422c50c186c5a2fb8037e76a6bc940cc11066f194acc320ff6d3342bc8dcf3c8e3a5e002fc443b01	1674984169000000	1675588969000000	1738660969000000	1833268969000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
74	\\xa76c3181e430994431a5ef669ed67019c7f9694daada6d2d40a44d7c08080b1bf1e198ac5bfa79bc1cafb9c9e04b1c27340e53b9f6f6d2f5b635d8da30618c81	1	0	\\x000000010000000000800003d9bdbcfa0391124ce57a10b231837c3fcc5ac1e5ea7c1277b87bb45c48095a90114c327de23498389f787a7027265fe7caa77c087a7a2a721ae7d4e467cf9be74898470d16107da4ce8cbd1ab6a187f1ae213a9e9f8bc46248f3f486f23d032ae1bafd78bb312f96c6a47c55b1b313c0d1e7f7161eada56eff074a0d73a151c3010001	\\x84da461714f3ba39c097fd388916d60c788eddd0dcd98976278fb2016029903a0b1f6378cf77972541271cf5c8f651a478092b8c17ea48112befdbf6de1b060a	1685865169000000	1686469969000000	1749541969000000	1844149969000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
75	\\xa878ff0beac5fbca238e7fa0562b5f19755a3ad7b9eca9c6ac96c19bed7fe68c58586ba905c3a4057bd83ed6f7d11e040008f16ace1c80e9b38686443c576f7d	1	0	\\x000000010000000000800003ade8cf9f62d7977c75d98ac3c05c3c9a66bb0bfb5ff54825b83d561f42a68b0048510db2b912c46e1109c8f9d4fc544a684eecc2148d349daf85aabc9aa84dca10e8d7a4230390ddb5eb42da4ec3daf15baddc47b2bc83ecb129eab7c8f126d76916d76f5c7f3d35ef0ecff009841d21a53a7fd88e0914ca8bea86bcae7ede31010001	\\x02606f764bc6f770b65a2152c189e24e6952f50be895236e0979fb4a5da2d9b8e69087c83ea0420caf937f2218cd1f0ce05bb9aa57f18616aa21691f317b0506	1670752669000000	1671357469000000	1734429469000000	1829037469000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
76	\\xac64d4f59587e5feeba1de99120ff803169981adde4993b7fecbb5f91391053608c2041dd9a18c9918262074d07d899a3ba6af556f9c869f697fc8994c2fa54d	1	0	\\x000000010000000000800003c0a2719e00e50f0bb873dc1419d6695f576f6052f884df25d919a274a4163accd9b51c264830b761f23512141b03b0f41fb88d73736c3a3208242af3126d690bd9bae27e7a33ad76ee2d865fe6d1201e6c22e73cd3b69cbe58eee063ab328f542c934a1f047841346384e9dc0d9566de69dcac4818cf3590446e0abc5725af87010001	\\x3b363971cb25bc683cbb233efce4e1bb74a7c743433fcc7aa55b3a9c35250bc82fe1fd10f84ff5d73f5816784c5516a95a789f56f15af9b55270f6fc7560d30f	1678611169000000	1679215969000000	1742287969000000	1836895969000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
77	\\xacf46865d212e53909a7a6eee503211c88e5cbfffe205fae0f20f718774c01fdbf1c364994adf372c88b490f48b4b6f1b5d980644f351827e9a8652cc63b8376	1	0	\\x000000010000000000800003d2f90136cb7510a07a0dc355b7e4916c2da540b340a36473b1f551fa450d7c8b20eb18b81501e97f0c66e1ca8c9eb8224fc0e409b175b8de101ef1ed578734947bc888ecb08c380d00f91de200a77fc18e0973af0a25b211a5ae0b20818cf00863cfccdb2fbdd12b23b82ba5bcaca46ffb53f3503d75b7933ec0b1d779ba6593010001	\\xd335df3dfc42baf2cfaee674b0d447ae02f75623d918ba81508e4d6f4c9f4e42524deaab7c9ab0422aa69a61160e0b856e5eb7a1551c5b75a7a608b450d3db04	1674379669000000	1674984469000000	1738056469000000	1832664469000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
78	\\xae44fa026bb2fd65ac3e4515484fb876163b0c41376393a84aa44926654412f868a6d1fbce9fd6248b34d49edfb58231b6c00430c2eba09491bfe411773cca07	1	0	\\x000000010000000000800003e964966a6f46890418f5a2646cb54318a5152e5f8360638fe6a30ae5fc1c65125465b7e5d17e7eca75bfc1ed583713b1caec4cc0bcc57b4dd8d96d880fd93c17a6dca10e2892fc5aa9e65e7a60d663876864d69eb97b200d376dbdfb018273df303577edc1093e62dbb06a5efc07905d49f545a99f6946ee4f55594a304a62f1010001	\\x4ff1186fa7bea27a81409f775a89bcb27fdd2bcf5a04a0a2ae7c9202e07e148ce915007550e00d2ead3a8d4fec3227342f66c296d17277bf868042e79052370f	1674379669000000	1674984469000000	1738056469000000	1832664469000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
79	\\xbc1887b87197a950a31275813b54d2f0cc228e2f1fad4e72bc2ec7654ff5ab0c17a42811cb90ceab7095b442d5cc079aedbeed3dcb91e9ad83c64fa05a5de5fc	1	0	\\x000000010000000000800003ae808b9c2d5151f0a68fb60d99e470386d03322cdf7f04d1008902a1199707186dcdb898a2d150315418a0002e8a2be5c5af7b3b177a18273c87dfca08ed5d18705e5dcb2c911506bf9fab1a721a471657f72fa478be7f03e47d02503ddaf5526998f8f6e0c11daf016f762ffb1561d8ce0cc92f078312e5870d9921a2956741010001	\\x102e1be8731de3139201abbdb8a0030875afd1aeaae737e245cd57901bcf375144ba9aea5d4cb98534e8a2cb7898675fc98acf4a5fe00489a45d451e3c87a20d	1676797669000000	1677402469000000	1740474469000000	1835082469000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
80	\\xbd2411f504213e61acf6fe8090fe7b6aa7237b3d7fd009f59f22698712b0e24fa8b9888f494b0f6d7335973eea2afb459afc49bd64e1b2ebfc8211d074e66889	1	0	\\x000000010000000000800003dd93390f45d7c535645b9277470acea785b7c78d09a5ce13ea14907ef9dfbff82b0f816737af59e4c6c0db0cf5fe1bcf1db41b123e12b930f01acf4b260ea56a60e4e6ceb0ed226ab6dd6e626e10fb2aa2458da7b1b69fdc7c55eea791862e72c30729d6af54e627ff57979866dff06178ae30f771ee7f885ff92c95130c5667010001	\\x57cdbee0b4a98d3e75261e4ff98433723c7fb56567120ca2fabb7088f37ad974ed662c46d1c5b7c8ed8e68790b00915ef230ae836df5e2e087cee786f7990a0c	1673170669000000	1673775469000000	1736847469000000	1831455469000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
81	\\xbdcc5704db2328d16cb550ae64d60bdcf94ad5c6e68d74667966201a11411ddddf808e7e9589a5e777b9e1d7af54e982492721e2abd41df88bce0aabd7d266c0	1	0	\\x000000010000000000800003d386d06bf645b397f42fc8a971d54805c9b1a69f43e81df961163c19b346bbdeb5deca6905aa49d7212ba021f4703d945f02ce9c0559dd157c81863c87ae658e9b6773317f446e871c4377dd24e1e091704f5b82904d3c24df69237f64153c2c09443088c9826c7d83303eb3a6db361504b9e473287865ed0e53c88041a9bbe1010001	\\xceef206fac27acb3b9dadfe47e1666369ddc587a6706ee1d74a3ae9b3d92f28e295397fe7703163afdfefc7ef6084c6028c07a013469d50894ac9a86db289002	1662289669000000	1662894469000000	1725966469000000	1820574469000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
82	\\xbe40f97c52459774f4a174a9b1486b423ffb1ccb14aefcf24e3ca831fa09688c7ae60ee93186b0715ce4c070582eab11dd80416443450079ae20c93578ac13df	1	0	\\x000000010000000000800003c781ffacb2e72a62f366e59ccc4ee76d5f88471c2fcaef7232b9e8bf9451adbfb30dce6167861877ea7ea4238c94684dbeb8484190bfafa9e60e259eec2c5daf754356b958a234386765dc9dc683c05b4566802da4d8f810d65d9ef2aa7cac5fb29ef9070daca9e2ac8c8205d1baa1af756c452ff478b68b08cf183aeb4ff279010001	\\x4bd44014a1a7c42816246444b53c5f6f99268c7caff431d227db46f6e1daede34883385e8a1e6206b2254442a2f698d35e4b1ad37dd11569f36045a1cda2e504	1676797669000000	1677402469000000	1740474469000000	1835082469000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
83	\\xbfac54007607c5045bffb4a7aac5530242e46ac8b110d7f29638dbb604aa175dcc9a9661430c9e09b6a123fc29d46d3d24b30b96fe24e4926df9227524155dff	1	0	\\x000000010000000000800003c95eb94f620acbdb810f5e539c86bbb2e47a43f0613165e335592b252cee94b1871c8f136052e464695b3dfb35fb4813a867b9bfc76e682f7e15babb24222cc1da370011b9d29c8f78f3a8bb72ac82af2561a4d67d80f98dc80c9055428f3e7e723c9953886948ffae4d9c0fcd85651198e5c2ce9da2512552c4e66cb1388f07010001	\\x70dc67ea861b1d86460e456537e77fc6ddf8f8beaeac072c3ea657d9e061ce37d28a6af1bbe8c87da6ede27519329d7e4a35c0c778897a30537683492962d505	1661685169000000	1662289969000000	1725361969000000	1819969969000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
84	\\xbffc34e5cece3272ee187ba2e60b85060085df00a59004f943142752df000cc1f1d87410796298f8b06f801f176bd441f20587c20250f7e23f49909e2fff324f	1	0	\\x000000010000000000800003dedcd28a6c80b0290f23400eb696aa3e51bb29851ffafbd7b19085d4e61252b95c6f4f727ab6cb5f95fa6e30a45d09fe99c2522451130a5479732dd8a65145eb1ca0262ffb1fc36a0b0d00389fe3f5b54a10b1b23b26e08e3485f832217a88797e035b6a76ec02b2e56b1e00d352abd14c1f2d9950755eabf3a1ad68861d9037010001	\\xc6f2ebd719a4a0ea8a913d0eb5ff8f5f18ab1f4f8cc52b0d055bc3281d4bd3af7201633e95570d037aa1975f66a39e4d25d10535697287f883f4301a9b5d1609	1679820169000000	1680424969000000	1743496969000000	1838104969000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
85	\\xc06c0e5922d3ff1859e7e38667871adf0e25bb13a33a01184b92edc9b0d7604b863e151ca4109a0e81a5095988637a580a129b8a1fc47561c638d9a25ecfcb2d	1	0	\\x000000010000000000800003cac13124abaeaace6e471ca39a6f4dacdf2da87028514befc0cae25aa3dba08cf59a9ebf2479c453a3e538cffad07bca9afbcb98a56f988f268dfbf890f0bb3b9cad93687e495084e05e102b7e4119f9bca206aed08e6c3a54c6dcc41b3985923ea6aace8e808d3b0c4b4c925f617034fdda75a5dc71b796efa4f220ae31eb03010001	\\x65dc31e49f95b1a22f150e3298c8883204643cfbc11bee76e88b9573cffbe72090463593e05d800718e3646a4f8af0d24b6d404eb96b278c78fd594dc0e7c900	1691305669000000	1691910469000000	1754982469000000	1849590469000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
86	\\xc494d916e8e2f7f8eca806b29cf59ef90a2e7126fce91f9152d9ff975a29d5bfe8b87d7f1fcb3a4c3c090cc9a0dd20bc3d24ab1a7c133b8fa8366b5dc8a906da	1	0	\\x000000010000000000800003978323949525e65805b3a003fc7e30e5999bc957f69443d8a875e937f67f2e06d8cc3ca1c038367753d49502de1f4713a4b27d2b9ee8da394411a876785d6a6bb051a0f49d783e204507cc529a65834398e56a9ceff09b10d856d4df9bc7b1d51ded1606363dcb4543bc0395873155e50adc60834e07c1495e26c9c3b733c377010001	\\x0c89b0bbec229bdeed4357a901f2d5492cc80c035d48348a3f0d9b90a8d4bff287b05818d1efe366f01d77e81c3a854150535b51ae61e90090807fb9cf5bf40b	1689492169000000	1690096969000000	1753168969000000	1847776969000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
87	\\xc53cfbe25e8e8d5dcf1f5915db68f3044bd6cb60b5fbf74238a104f91586c636b50d67599b163a8182a944f5f97c2b2b850287c8a43dd4befecdb4bf12608d66	1	0	\\x0000000100000000008000039d01cd94b54023635dc8b2d268d5c8553018ff7f8e7c9392aa245e605a29977a830e19e043bb04a00fd805f6354ae07adc0184390332e54b866496cb462677eac93b22929bd3548727070a4bd30c1beebc7d0dd40e222541dd016ab80018a1aff1798dcbf414fad5ac316b1aca23c9384c920e6a880d195644e273d0cdfdc325010001	\\xb850af4396164c1ea97491be696bae1005ed2dcf4deea9faee638ec7b5169595a0c2f2ddd08b36a046f7b709a9169ec6bde16d8ecc6c48585608a202dc9e3705	1690701169000000	1691305969000000	1754377969000000	1848985969000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
88	\\xc5744936396ae36ad09ec7805a97f591daca7c878e8212a6bc03c01308b2d2e45423163c6250927acbdafe3d399516e1909e003ab87cf22db40d1c2ef2b7e613	1	0	\\x000000010000000000800003ccf4317dc0a2e6ae1faeea4f963506efdc9acbe71af439f5a8d7be84367be4dc03a9a24d71bd1f75045b460f2c1660a7f4630c9931ab4dde238f3a17dea1376504f90643d72c1e9266a06c7719c53cd8a8b7b17b0ac4e3de326300c027c1799b16d004a90c3358ad4054be3229b55f8bf7452cff344148537d44afb54bac4bf5010001	\\x374c4b45a7cc7b5f745aff324781e526b689289ca642353e2cd4d266a8297d5582fd6ae18c79c1469a2a0bf878c8f8c3832b8bebedbb0b0142dd44cf6d0fb00a	1690096669000000	1690701469000000	1753773469000000	1848381469000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
89	\\xceb49261902e813b5d757f5768b7a2323b0a4a5abb6e268ff24788b8cfd5111aa31719ba8f6344032f6eb647a8a66397c4ffc2a39982b7f5e04c8dfd8543e1ed	1	0	\\x000000010000000000800003b24a4acf996e302857b56786988b57e25d67c68e599ed2085084babbe71aad82b724fdcb9f26d9c11cb5ad9eb57bfaa186a5b389d050b8ffaa12539b08b2b1d5541ded59a7275e214fce3de9bcfb97429c94b527944fe788e5caf197dd110ab51c17cd0c4f0de6709a84c6e0edbeb9074b28da9ab89a539f7ddaab1e8ab60b8d010001	\\xc3ad49f8ac146c989d1888663749a2e7986525af673bb3e490790b1745394507ab5f2a318612a59d88a384de73d278533990220fac154dc7c9708c7499c3460c	1678611169000000	1679215969000000	1742287969000000	1836895969000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
90	\\xcef077f84da3f030d7ca1f6fb32fd5a88e3df7f96538564cb2525a632893ae0356407bdbb00c24a691f78c8a54c2f1c07dc6775efd4b75ff1f8b40ad39f48a36	1	0	\\x000000010000000000800003b147600c95cdeb86663d99628a015923c5760cabc82652af128784a633d3259afd17edb1f3df0d9de21b752eb097d32da2b920707251939be1d196ac841d0fbd2430eb5f982db226da7e18a4ffd5233bcad010a46be5ad6ada1747644684b5d51ea6e958baae2cc46c4febdd86cb9ec877cd38be6fd6a8a1322b3975acfda0dd010001	\\x201388586a3cf395c23673957166f8b36f93de8db85661d32e6c9741a984dea84aea5af3c8ae94c678b49fc5f626e75c2c50d8c43539867cc5d8d603c20bd901	1676797669000000	1677402469000000	1740474469000000	1835082469000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
91	\\xcf0ca81aeaff16d2257094684c7e57ed3ee9a0851fd7983655035b8baf503204463d20cfdfb8649c7dd83e260d73e41370ae35767015ae7c8023e43629c7f5dc	1	0	\\x000000010000000000800003b089ac13b5eb397eb4adc6965d59cd57e33ea8f291eb9fe6535760e59274724852946f5c4b34a64d0dc327547b6a633ce6c59b903e5e8ebca58fb69e774462241c25cddbe428f12547b6fda863e653a939041fbee2aa50606251394e4fbae3b90a48d8ae63c2d38cbe4b8b77cbab3545f7d855e434326dd5cfa16d8e01f8c867010001	\\x0e86322e102c674dc80030095b7b11e4cf4eb39f403a42be7f4b6434ff43c0f265383f7205f08e60dd006fdd91800656f9ce65443ca510b6d669ecc0f7e32405	1682842669000000	1683447469000000	1746519469000000	1841127469000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
92	\\xd7a0bdf769438cac0c43a8f9db56e6ad5c79730170fa8b0545b82fde1d499d345c998d0c88af0c4fb8366d438929f8c503611d838ddf389b3a73d0fd051139f7	1	0	\\x000000010000000000800003aaa8ace03d1d72733d7357cce66bcafc584de49ff44c7e0d43e5e7db045588d99dd2a35db0c9a1a327ea3e7c6474b2835757a039300328776f1338a1a77bc37d88e42b618d15a973190cd6bd5cdd1d78e15ae5b389ff38bf93e1bd2e442fa9e46ae91452d5b9c4e14582204fbf7b922bbbe13d35736ec7a688d4a66b9ce5ea69010001	\\xc407b39bb94c33609239b8b275458912637689cfe636093fda188ba768e78e72c81e4e13e2609257a63969493dd1c93b14d2a533fb615e600e2a93150d01660d	1680424669000000	1681029469000000	1744101469000000	1838709469000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
93	\\xd9c04f97226b026b15f9ae31882d594cc37f588da6bc51db0d7d7a1a1098dcf8eeaa3ffb4d37878bfa9f0427e18ee66349ba7e78f9717485a0ce30ca217ca7bc	1	0	\\x000000010000000000800003a7ba7fac7bbd5af6c91404d47e24b75ea8b2e40c016558811f83a1c3c9863ddc3ed0e54c5be2dec865493078370ca5aaa138cd16b962f68c81a9e7c6f4c7cbe83d9702f2b0138c1ee8c2dac7757e6eccebbbc5dd67af6452bc9f97280206896aa8d0e3e5a27cecc9b230d9e98e49e7a3481693f1b909f4a89a415a33de877fbd010001	\\x2b8842eb7e3ddb14fd98e06ecae16a666c077fa727d59c3bf565d0526f2e8d4d66a6daa69da64a3110b2d24c99cee4c85562390245ee57436ca8c7a59c7d2a09	1682842669000000	1683447469000000	1746519469000000	1841127469000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
94	\\xdab03eec80e25c538b4be2cd936abbd05ee00dc7a6b3fea21abdd36668ac503868569b236cbbc904f381b56465b3c346bad5c32494c82d8cdeaae0f4e2d9fab4	1	0	\\x000000010000000000800003d5092b32b81df216e86b0088ed81a70f53041fbb27effebf9e225ed364f12d8ddb42c72770cf211ad44db813b40de61026006421512fbf60f5f79da4881d66afb728425d5d56cb6ce55e1d9c359f0966dc4cce7ec3d4b8b844944ef9d3aa9c5933c3e16e48c6af5cbee0e9abe7ddf5f7ee404053a58e1c28e16a3cc5bd50497f010001	\\x96857a2c4f052c378f71e5dfcfe820ab73af8ddb86c76796fc6dee3f13d7e42f33716983ca1024748f6fd6d93e05c07d253e149f17bb20bc07e6b88e9aa54b0c	1691305669000000	1691910469000000	1754982469000000	1849590469000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
95	\\xdbf87d0665061b38d555ffcd631201b44e41ffaadfddfbbf477617be4dcdb75297241eb72259f1fd7ae3c9188c1c5a7e4f8ffbbb8baf13362eae622c6c7283d9	1	0	\\x0000000100000000008000039e6d3ea6ee9ffa63cf1d9d7d1752f5f7099f507ec5490c884557ebd04f459a79b838f93137f053e8215d674708ae002c61a41a17c135678fcbfd68300fcfd6660cf0fb09d52f5b56fe4f9b521232a58a7dc3ccad12474328f90355d5d331fcf9f85a8f3cec5d008153e83c405ecdac495cd45980cb6981506744895b85bf6d47010001	\\x40a346608c776ba770511626c62c6b5d4db38459b85ace2b5f14ca8536e4e5bf2bd6253536f6b92f62b03798f630ad1c2c5afbbdeba45a4cded9455bb884d20c	1668939169000000	1669543969000000	1732615969000000	1827223969000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
96	\\xe004e64c19da7c224031f98146c6e1eb329375cf09cb9019940a7ed50a9346deeae640dff42cc1ca79ebb6a883fc8bf8c921022ea279ea6f581ba26bf51053a2	1	0	\\x000000010000000000800003aa06dd8a3e5caf8438adbbda249223a17256d18813bbb04332a040c8c0ba20085e4473b128721f478da03eb0d10250a37ce7d700435aeb02212f345832f4948f4f0ccefcfb93f6aa2ada6036c64072cda91def3e09ecfcc87d687ad194a132ff390bb0aa71e8b6c7d003efb23bcc05c221407dd3e626dea408004e6cf75ab29b010001	\\x833923ca0f3f3599d91f9e5ee069425c46aa2269ac09ba86e16710c9adce65594fb74f05ce49de2d30db5bd0c8d8e0e16d1e2164383179e76689b9af76b53208	1666521169000000	1667125969000000	1730197969000000	1824805969000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
97	\\xe4007ba3669ce634f319a529f09d0425838752a7b0aabc3ec85b1ffa0da413066158cdc9b9482b62e16c9429ea79946ebd489fed255dfb01c3600c975d0db642	1	0	\\x000000010000000000800003d03b6cb86c8e425df8707ada620149e951265d9ebb7cf36a7ac0c9bf2a00b6ce82c6a91767cf9036c1dc7dd679f89dd0269c2953de4b182b8eb76896d98540922b9b76b879956bb32261c4c1ed9e7655a5a45e4c0429c4f7790945ca7913eeaf6388cfe7c66bed7f181f3577338a737aabfa747c9fdc30d59f7243e19691977f010001	\\x2f2b8afc0b440f382f9a249b7253cf8ce8d3180860236e7b2df4c275694749637afe9ebb7187c9f6c13d275f536b75b2bc3a89b8af1c71f68ddd8487c45f0604	1685865169000000	1686469969000000	1749541969000000	1844149969000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
98	\\xe894d2cd014108313b86c2b4663b05ed7d17d4fdd89c9fe6b5567a3783425af4a741e429d27169624c6f52d1e08f9c28cd1ca8325da74dc02006bb92e44f5c4d	1	0	\\x000000010000000000800003e9b0d3e8565f194b74854d53c9ced0294aa86f97754d3f4ea64ff29d8c2d9b4f9407c9b499da9233ccd93c07df3959353091348008505392a03faa9076afdcbee530d9745717efda98d43a48b75410f101de3b66f7a02138eec0be5f04a771e6854722b773ec9da3c6c1b9a54834922ee47d31c5c339bf5b20191e2862d2d619010001	\\x2fe4a514fee1ed9bac300b8a913e8a82be8debe0583408ec932231f37ecd0a65b73ee140b1f60af6560a261795f68d2894f9cfd2ae26ad597db1da7ccf291602	1684051669000000	1684656469000000	1747728469000000	1842336469000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
99	\\xe9c0ec6f2566c530def8c34d77ae572a924cc5030308face0dbe27846a75e0f11da34fb254848e30e88eb16143e97475e870e43639283d265e2a55ba678503fc	1	0	\\x000000010000000000800003d754f8a7281be6e70c75e85080b84377846db2beb919f0e722f86950e4d822474305e662272b953f7230cb4ee8bfdd0cbcc06b197568ccc3498b72722372046afacfcedfba1f22124940f91bf09c54cecb068fe860232e236fdf5f78b363a53ab95fd36f27d6f9e0b551aff7da0b084fa6caff3f752aa583e3dc80f94fa8c323010001	\\x15f7e0422f04547b275b06a8a93e7684548e893b44db00b8415be0fbc9f1a531e585deb7b46b2877b466b206060b41892330da02a1e6a7a41db1564f5a58df02	1679215669000000	1679820469000000	1742892469000000	1837500469000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
100	\\xea0c8be964eca229dd490983d9fb80b5ba21164a514a1cde34213dac9c81dd298908ce3976631fd355b263aba6af97a703c407269c29b9c5b6d94bd093c7870a	1	0	\\x000000010000000000800003ca6c4477b6e06f51434bd795a95cf9e42cfe6f561aaf464f438b6d55350b3f217d0136a6861dde267fd12da03e6303ebb615f03ed2b7814a4d795b4e12d4e5809126a91f4d25a988e131e245be84ecd20a47d91fb286286a6706cd4e483f5a7bffc7b037a60d911798d5b6430b6cfb9642b8ba873cd030b17d4440271d2d9cd5010001	\\x9bf4e062c47f1c20631d5c6fca9223be498eb59e813ca93da4cfebafec6aa96107f7db7da1861701e07f1d1c28a4668bf517f54f394cc8787d79c720f3eedb00	1684656169000000	1685260969000000	1748332969000000	1842940969000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
101	\\xec1c9f7ca202d66dfbcfcfaebba7f00a074284857e6cbb475f136fb8adf154faa4c46c024cd3aba4a31c6bad2949910b5721853bfd502088ee2ad4b71999c8e2	1	0	\\x000000010000000000800003b28ea1ca023db2927d509aead15922660c611f2c87fbac4c5790188ab7881acdf03928f65b45ec4511419b2e2ae93d26ca8f5827cdc8b8357f8ebeb21c4f28b9801acb505cd41507fc8792bfbaa7561ad0dbcaed7d22a84eaa5cea9277c2204c3b5e3eece0d9b0d4e913c7af0c85305a31cdebe96e4bfb65757d564742e20365010001	\\xe91c80d342924673a4cb2a5a2e330b50d7a63f2ee8ef68bae3be7472253d7a8fe8c75f3f487ce07678778f13ed7ac2b8c44ede583f65e51d1b196d67b4c57f00	1684656169000000	1685260969000000	1748332969000000	1842940969000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
102	\\xec546d2e315af224782d9494344eadf47137e3c4f9eacccbb72c7c1b4f96294aa26e0f70c7e7c9c7d1bbfe83b8ad5fd5ea1bb634616c8199f7be0109e2710064	1	0	\\x000000010000000000800003e3be775e2cc74744695d1da634bcb937af39e5d2f7f688afc3da1bb3716d510791200e125b492f68a476f9a71673955c1e1391c3db2769f9a0da2e36eade55bf3e93fa2f023189d7d8f38992f406861ad3d6d85ca20f605bfb9156f028a13e45079a3202021e01614fbe4b777269b0e23ab2bb48c754f0310d9c2c9275bc0f11010001	\\x97421ec6e3009ceadce0dc222c121a67a8406f7d553186dbe8b7f6c5b4d022a779e117346321d11677a95ea3a65b48ec1e23d46487958295323855d35e63e506	1673775169000000	1674379969000000	1737451969000000	1832059969000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
103	\\xecdc22f5b177a273c55ee879584fbc776d97e67fc16abb939f51b5584a465fc7f8d7bc32ffb529a5daded01c91b481913ed35b04569737090a0678c2c811b963	1	0	\\x000000010000000000800003a83bfd88d65fd0384170dcf5e22dad20e0621db2c3ce4153db8fdd0d536011aa477b1fddfb628af03802ab3d1557674674daf0387801c3d9184f69ad1e2bfd4f21770457da9ed99b4ab8af21d59a961106b3b0272e6aa165709d7cc34de4a6ae251878ddd390d8eee299714e7aa87de958c6cabab7523b825299f26b827a0025010001	\\xe0af0a881844fb9a0b8e82f4d1467f4c01574247b474b10de517435a1e3772c81eeb2f996cc9cad4a11b4440c5cd37a3bb6ca7caf08e4263fdf89820a95ae40f	1688887669000000	1689492469000000	1752564469000000	1847172469000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
104	\\xecf8816d79bcdaec51ea682bb6bdcbe8377a46949858abea95f34b717411e6e04acdfba0a03cc0c8a5b4aa0c0f1e838afc643beb1a343c1d95046e48c0cb4fee	1	0	\\x000000010000000000800003c10197e8f6eb4c15fc5da0874e44842a88d81deab91fdad995e1d30d58c0a1cb1a7ad92ad3efb2641e4b4133ba3d28114961cd69d74cede10ed453c5a2a0a41284a9ed992c15b97fd87952e86f76e3a332cf13ab61f112343ddfb94a4580a92271fa9898a5294b9b6c5500bc82b423cf6217945b58903242af10927399063adb010001	\\xaa4245d44c606bc075b8acf7d1e5dec0c4b8fa878e3520b1f740a969225bc05950e12f7ac59764299b102322e224fbf9b24e762b1d271b1513d7759b55288007	1668334669000000	1668939469000000	1732011469000000	1826619469000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
105	\\xf208381cc5b3fa79e7e8a5eec03f390f8e5d280fdfb270de3f6da136c8a75486e28ec7fdfebfd555da70316e7c7f9c9ff1b3118a2a0e7084071eec13b3a413b1	1	0	\\x000000010000000000800003a72604a24324f6c320075e800a18eb612ac004543fc3138567e536a475576325a94341bc4f97de94eadefe8f5ad4a99b1756f373c136b9072ec18c7697cfbb93981abe660f86a753dca644c12ab797f8f0f440e97f568c020ffc5caa0fc7dce144c7e49b0db703251c784da6fa226fd71c059817d3ca7604116abc219df58643010001	\\xb1fe196e5e8f5f092eb2258c9eaab5df9b8d16c77e571348dd1b485ebf72772c6c3cb603ef4f8fb530645e259b2e1da742667ee365b7a0cce23c731cba9da80d	1680424669000000	1681029469000000	1744101469000000	1838709469000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
106	\\xfae8876faf559fa49321f87a84edf6a8ab00c9ee491389473f3264ef783f8dd402ed335b7159e9b1a807063f50a02291b1ad404e2ac0981c61600ca3d13e4524	1	0	\\x000000010000000000800003c08fcdcae566fa0752cdb4da612ce1f03cc622dde67f735f91ce33ba97568c7c6fe3ec3993af07956c6736b18ee799c96f473537355eef8fe97920021f0bda143a53ff9973ad9eb8266a4c60d84d08982b3c798388737c79d61a96a537b523070fb78edecef63cd7f863204f933191598566561fec6840ca1a08db4432c550df010001	\\xce08617254cecc15839eb306cb5be60b7d251896cbd61b4fe9aa8eee4096f1a0a4a91550407a558460a4dfa2207f78117d2f7292baefea3efb7fded0f163d109	1678006669000000	1678611469000000	1741683469000000	1836291469000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
107	\\xffd87c55d8f1a3293cc799d1570f90afe38dbfcbce0e5eff378b10a521b4446d46e70ace1b4735b8e94cb6eb97f2813cdb2f910282858dc6bd62898e7719394f	1	0	\\x000000010000000000800003c24dcd4e58bc98fcdbbe5fa31b27e685e5960fc663e14a499ad8aac7a3b7474fe34bc1dac25a0004556a0fd468ac5b54cf0deaefe3c3e9a2a60a837d99025fe6a2f895db59ccd3c65fd31ed5774b76c6eeff7f71eb830b7aafe79704a3629335abba521fdf3af8f963e6bb69edc8e16c7a195cefe1c32be42d32b5f67e49d779010001	\\x7d1b8ae0bb657972cb4f2652f6347caf4cac7864f0154a83c960f314b1eb98abfe20e0692eb5b5fb73e61e4967a506478683067c955a534605956c10c3699c09	1672566169000000	1673170969000000	1736242969000000	1830850969000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
108	\\x01b16b18277d760fa931cc6a989751822a1a4edf64fac9c322fcaa82cff7e2700b142dea8a30f54c2c4b4a641230a19a420fdaad006852cea66948ec7c3edbb4	1	0	\\x000000010000000000800003e099b8647509a51b7bcdd7ac48c75c2780d6979da90e6b9d042de0fba25932ba8f3fca048b013901d085a277f1be1aa13f9e0798bb1905f07ea49ec3964d481992d1060232c41752b9187abc0b611e05f87851ce19e719a9a6c4ef2fada5fb5db59a7ce240130d8125c16178188d0c03eba7e263f6edd491576aa2f3d1db35bf010001	\\x41f533134dd3cf60f66b52eac5d02ce448f768e5269fe8b2110e0d0a30bc9c29c43bf405d7a602762c667e7d2384222d33e1f382a7f0ccfb8e44b25f0495c901	1664103169000000	1664707969000000	1727779969000000	1822387969000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
109	\\x01cd081ea99ba16d58e2695801f757d1c53fedd5d62b7d18061604f7b111ee58a5148608b2cc19ba7c8b1a0ec3a7f364f08535ff07b2538f9c9e70985ae5fc92	1	0	\\x000000010000000000800003db11a8be6a5976423846bfcaa52fdae710d12fef632897ecc38efdde3778886cdfa0c15791c82a6eaa5a8c27487d558fd0bd110a4edca5ffb5909d4f59cd524bc82eb580ec386ef31d721b8841f3e15c72e21129a4e9b8f8dcf5ccb1650e3f82d7dae452282af94bccadcd63a8c92c69ae7405a85a46ac093c18d1057c28718f010001	\\xf70d45a8a6d22ec60b4ed86d18288da6f16e8a401245ad864baf1a88b3655de0232d232935bf98ed35d4edffc150cc41173e2f5290bd3d376a20fa347d5b6400	1673170669000000	1673775469000000	1736847469000000	1831455469000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
110	\\x0779eda0acc8455c9ea59ef2b26d5fa6fd436892b7f388205377f3c5aee13ade916a29ac665c3f7eb24799b8ebbe2480a449095fa15f652b6c27c10cd0e89926	1	0	\\x000000010000000000800003c197923b17b363f2f63981823ebc3f6636b8dae937dacef475d4a0094f3724e1b977ef0f8209012cb876d77228616a9a80547c4aef0fc1d79af0a16d100fc83c6b3354bc7890c68782536536c17e91e17148db7d2a9cf29f5be1f4a3c284b68b53c2876471b3ad2103a0abcc3285b40677ae0fe3d8bc1fcd31815dcb9266f009010001	\\x382260841585732f6df5df3f2992a48c0b0fb313fdfe5aa77c87125e7fee896d1bc20233721c75950822fda380324ddb9d3d33bf53e864153eb4e10dbe1d4102	1681633669000000	1682238469000000	1745310469000000	1839918469000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
111	\\x09c10fb11b689b57dd891dd0ce9c7fa8305e3dce0c8277a370209542764f430975e8e16897fbfbc4e81b708446b205f0f20c9913ea788d7035ef55b7ac595908	1	0	\\x000000010000000000800003d6786fefcd30e5069bd41cbb3a0e7e70e415497a089517c38580250fcadbdbe418c591ed7b4c4c482d1f2b2e2eb8b7b512000eda8be04524e53c2326dfc6c3fe3d6e11da3d72451353a5368dd6a4ada5619463d09b504aef6d90f66d559dfef76202f5298fb02fb7afdfc04e147864d3c2666a9fe51ae93cd96f0cac38959b2f010001	\\x5d0370f7478971d0eaf94552b0842ccdaa53fbb4bc568836db682938d273ba58a8750207d8eb24a1b150352b7b8edf1bd65bd53979da2b8a52ac727ab4f57408	1661080669000000	1661685469000000	1724757469000000	1819365469000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
112	\\x09211c3b2b65412a32cd3b493a96a1fddfc32be27d856e095ec400f95de292089069d29377e8611265ba229af929cc06515eb12c5e8af985dd1cf2525e3e3149	1	0	\\x000000010000000000800003e69c87e8129a7df0480fb7b19842c0a2febe7a5cd0457973486473860ab656bd1ef3ad903095ee08f66db5059870f02ad0e4257ac91d57345df9c651970694bd92efebb0f2ecd80659246417cecbbc95661e17adafa6c488496c568f7ede69387ab37e2fa7b82812c5a7838adf4acfcc9dfbadce91741003a6db1dfbf21cbac3010001	\\x36ec344c72c045e34ac6d9fd29a5d8111dcd122579f562bc20c190d4a3d9960bf9782b52e665c03a7d2b8dea77b1ce98959ead436ee3ef4048ddcc785643c703	1682842669000000	1683447469000000	1746519469000000	1841127469000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
113	\\x0ab56d85880324820c5e6c210cee23bd9df74df38589ce7d2c84d5e4cea47d768efe19e1d566dca6e69cea600290cf21c5749613ad6933f6782144131a99a774	1	0	\\x000000010000000000800003d6f5de1733b39f5fb76b5a711b1c0c9431649672436954de499f693e25b9a75217f634ac7a32aeb2254738da60c1420f613e5807fd4c4d0676ca17e98ba0fded6ddba81e7b256b3e2a448fd0eda6378f28e8c2b0da52fee74382ddf57ad7bd531adccdd3e88b03af1257c8f20b8bbb9b79c5f88372e51bb15efb0c9f842b39c1010001	\\xacf55067c07b292d29358d9daaed774d12b9c70cef6ca31b9ac20629f8bfc701e7f4b3a91231342a9eef3356a7c5cb3aca8e2005423ee851ad3083714448d306	1681633669000000	1682238469000000	1745310469000000	1839918469000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
114	\\x0ad50aa47b8c691618bfdfde70660dbb84b1afdae65c64054cdccaac186ee7bb91ef1d3f39a22ed9184654b973088613ed4d4d0caa572cae2a615c865fafd8fd	1	0	\\x000000010000000000800003db883b6517be012050d4e90b0917079948a658d7c5fe68beca5e7cc7dd8234594e209bd51666fb43350e1c009bcecaf9ef760bd7e1ad7e2ac558b01f773d648e7bf5626ab948ab05496b833f1c4e335cbd41886cfc6ce06a687e837a40b119a9d1d4439143e15a7791f2fa5e4aa364997835f92c72cf3985364b254e5933285d010001	\\x672cd2f7e113be539264b1f0314d18bfe7d09e7e4e9115758794a8eda4b3470c6235ad80a98b79907856c525d7e88ba0df9e80f1de33198110b7472747c41f0c	1662894169000000	1663498969000000	1726570969000000	1821178969000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
115	\\x0b4d36c6b9849e72b620ed31ef8d357a2b66380f67bb64394b9cacd5e8b348ce940b979139c57b3f858ec175672535ffef4f75cac336448a7158daf47763847b	1	0	\\x000000010000000000800003d063490f6fd0658bc5055f3af686ef4f759fbf40f8dcaa4a246effcc5c9ca9eaec10c560924a292ddfa4fc51253676916100716a055ada14bce711cadcb730afefa55c52ec0e271e53c2072a19d277f5f948ed827ebd58faab21f1c2b274d3d56c410ea81d4bbcfaeefcaf5fda23d1911225e1c8abc9a765bb58b112f2654bd7010001	\\xec273af90338e47bbdf74451f634aba3e3a2413b334b811c831fb406f703c7026143f21cb8f5be5171ef0ce6195792fc792f02b9b3506923d94a2f2873422d06	1662289669000000	1662894469000000	1725966469000000	1820574469000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
116	\\x0b0d2a7a2125001cba013c4ef104a74d8a2f9e961600218bb532326efbee0a8802c83ff167a9eea9ef32fc74817f85bd9dbf702d080e08fa1197e3a15449d1fc	1	0	\\x000000010000000000800003c89f4af9a3b0894da1b958dfcc30552cf6f576cb4fafaecab9572df445763623327fcc58af323865abf5686e5678de20338d4c1685a74116a06d4d849d45352bc000c7c119f1419c5f588fad70c40b28c517595682647965e8dbba8441903f8e056b6ce7629c05485892e6b0f48a600eee737eddb70ea49297b0a89ec3ef910f010001	\\xb47f969b09a3d029e2f07078c2a9dcfa460813e0d65189ab0b5f6f51c203c8465e936befcafad1b522d38e0b3c06fde5f859be88d513fb759f640fc27b700a0d	1674379669000000	1674984469000000	1738056469000000	1832664469000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
117	\\x0eb9be51d26ebcc499c227a58e3e2028711f304719c9e1a086bec52c5681ca50961303490e299733c87d416834385e78b6fb51aae5f5fb97e363764db3c4e647	1	0	\\x000000010000000000800003abc94c4ecaf27499ac83e6ef90ca07347c8879c58e0b3f85b998a84b1142d6e86a457cd664fa2a79a1604b79df029a26cb22586164b8cbd52ffffeab113b6352222cac21bac3f61903c4880d46df107824132dc50744a4394f2ab8f7f1603d17055dc9cc05f7ee79fa71a78087cdcbb92c521dafe6961354340fd0cc645df65f010001	\\x64e5c109959de65f2cfcd8c22b169eab77f14b622076eac1ef4994d94773bf46391aba3458630a39f8bcdf26a9f51f537eb20e8b7580ab41f9c0f1c3e00aa909	1667730169000000	1668334969000000	1731406969000000	1826014969000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
118	\\x12e9d2724226e13fa64f7e7e878bbd406ab6ce9be67c34a197be5cbf7d711d889df8c76de0c4318bce2a01672d94e1dc0a6f1c15298ddbb125f000879e5bbfb1	1	0	\\x000000010000000000800003c64a3db1ecb6cb53bcebe531772f54c580cf2d14e64c1646c70c095276e11a52b9732a9405a3146d39fad489ee03cdf12fa0c3da92ce01d9eb127511c59fe4e28ab3e8a9120616b14dddee85053da01c9ddfdd5d81974af93bb6a6aeb34cc622c61be842dbc008863b6b2a52b43201c81025a400669665d27c3c81929843fb43010001	\\xd33b5ce239a2e4496d422f5621f269b93335950c0b2ff184d61b5ad2daf674f673cf6a398bda2db97cccedd7a2aa8aa89df5f7350d3b42f9b4cddfad2ee85400	1671357169000000	1671961969000000	1735033969000000	1829641969000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
119	\\x1441c739910dc977f2bae2c5027c70444c50a987b6305660b9fc105673401398b07a50119a8de002b3af4fd2b07f7a2f00ec54840df43d47f0dde0545c548e66	1	0	\\x000000010000000000800003db31dfe1b5315deafde2f4a49356df003c1edb875174b1c2f1e9adef537ff9c95e4a983d9b19be7ecdaed4f1cea91546efbf2134132db073f1a68c845d6b3d845e15d063a9d5c511c6c8837b9406a66c0c4a062c258868530e69e2fa4be31a988200c0e7ad61665be69356a8697c77f19c234644a965a7a4457e9b72838d6cd1010001	\\xb6da28289675338ff56365bd27983ee1004a6a507939cab2f5655bec81e821f252c4c32482cd79c0008f1db59b69e5065a93aba5791ac023ee286104d059f903	1688887669000000	1689492469000000	1752564469000000	1847172469000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
120	\\x1425755e1ddefc63b99730c539d576c7dd66b0aa7703add2095ff24a29f785ca56f5e63939c04a95b5cadc304a5c0b5a47b14b3f6344a4332526908fdba5a940	1	0	\\x000000010000000000800003baf04cece2b423f6d0698445f2c1b163cefb607b430ee714e1d4e016ad8729abf54073bce29402c02e2b130ca57a55c4b3dfc4222af0e2955b8f47b34252f737c45cd6b33a8593a82252248ed600268ccac2d4289e8761f33cd6ac825d1e8e459c34a38c236fd96e2e17347898f5f49d431f0b330d2ca47c44a6e81ece756e0b010001	\\xcaa1cd01d1416d2bdb996e148641f2b0b9291841f1a8f152b162831bfb31831b8211e92bd7d9c2f3b30e7163751786cefdef63847f66659621a8f04c5228b303	1670148169000000	1670752969000000	1733824969000000	1828432969000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
121	\\x17d980a866665066be40303c7c8ce7d27828840bccfad2f90dcc52d176b5fcdadf5e8c021147ebe08aa09a80b5a307c455a79b31ca5e7baa8dc248ba3b270f63	1	0	\\x000000010000000000800003ad803bf11f89aa51822675b2e6c734a286b9e074f75483cfb8079bcbd296ffec39721e91989cf8d5b11f0e68468d19c6096af631253487383a0fac6edc6c7d7083f6ac90bdb58d825f9f22a5f0ce18f82ec0cc26477282e9950dc16e563558d8a0ddb16dd3ec41819580e44a5ff3c8d46c2f9fa8cfc22ec7d0981d12f5d188f7010001	\\x318f69bfa5bac2897fcfbb45bb056e28f46b6ecb4e9f9c762bcd7d696f6deb35c8676ee36de8584c93682f4be557eac9e6685ac8b18fcec058233b76b6e67b09	1683447169000000	1684051969000000	1747123969000000	1841731969000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
122	\\x19b12ca61434e2762b6f00fbf10f9fce88549a6ca299162b2dabb03d37edda8176a594fa77881d8e931e21a190483612bd7c1d0e52682f3c1fc910fd49522f78	1	0	\\x000000010000000000800003beed77362d33b7f8d21025c2548bb3c4a2f9157792e5ac2a115bc78e6dfd426b23e15ffae072d6b67f35b322434dc6b4489506e28cada124de50142092f22a8b4f13a882bd317e27478b130b2f03b6191c0cd85ee6534c2543e105e7fbccb3faac7eb77783f1f7bfed3afaa21d27b78b0a552d5fa5cc81d619ea22d0c1dddeb5010001	\\xd19fb5618d5736937e9d8ffae48632d1961c508f102b39f0b721ae5bb14514c6b5d0795f9fcda0fae733496ef4e20ed13b01fa00f8a5de086aa4a76c15b4c104	1686469669000000	1687074469000000	1750146469000000	1844754469000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
123	\\x1cf978e524a6e3a830d4f02a6809e1604866ca0e3ea6bf001578ab30a8a0839625d89272c25834121b29fb785588e4c89c5c78ac2c8374967b7a9df265a76519	1	0	\\x000000010000000000800003cfda26ce87b5fe19a8fda97da9a4c55fb23bfeb0f72e10b35415eff9aa6c3d154799f8c3ea10030422bfae63c6573ba76bb75a2859cfa18b12897ce01e723ddbe6af573b5398abbb6a7e0893e32876c9cc7e2686d55210a57642e057ea98d3a795ca1d0d4704d2279356dd750602c119d393ce10e10a50f98a5a035b637200ab010001	\\x713038ae96990ca1c4a87eb37caa8daad2ff66efc93d3a3f0a2e4135dd32476bb156acc13aee488cb3d233b4963e4cab7725bf980d74acb0c1a3364cd9621400	1666521169000000	1667125969000000	1730197969000000	1824805969000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
124	\\x1d89c4b3abdabf97f97a30c4dd6171f73cf12640a2a231c9f5273d40ba556abec4670aa801df8357f237a1ed2f67d5d40992075716bd7447ff2a409d96d7b944	1	0	\\x000000010000000000800003a65cbd35f4b359feb95379812d529777b135c4068b6b39ed3052d20c2f29a1d3c0c8cdb5b5d67bed88c4ec9addafe11a0592fb17841831c62a4642913cddd2cef39bea44ba5756f9daf4b537292476af9d794df0c8bb6ef4abff2d536b0bc9ccc41dad0edc6b6300c51ef2dd169cd9391ad9a4ed0143e9faf00f37a94e32bd53010001	\\x1598d59dc9a1f9baee1abd3e066b9862b78d80cf9208140dccedefaa05dddf96e0a936de182eaa09eabcd865ac75a32b3ce5e6c037e34ab2b91df993216cfc06	1688283169000000	1688887969000000	1751959969000000	1846567969000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
125	\\x1e31e51263cde1c6d0481ddf837620d86142914ba24ae238b134507c56eb9fcfc1089f2a11086b06142d27af26ce5d428fd415a281ea7aee074d9f36e7293aba	1	0	\\x000000010000000000800003be67ccbe33d40a7e4a8467753dbd2317a9a2da0a4e079229bcf24e5d1abfb23f8f069c1fd884c3496300533e18ac0abbf0368771f7e02fca8f4d2439911d64a5b6343ce833b89e155a6b8f56ee27098cb05ffa28f46b782c0bbd0744f4b11daa7e210c5efabd5524abb490a64ffa25878f832aaba8cae149415edd83610ce063010001	\\x34abf8cfc00c1e29377d98887841fbb9eb58dde8617c123eab7ac1e7439cbd42502fca7446ede45432e6a298af4c4da11d27cf3e55d0a240b24442a803148509	1659871669000000	1660476469000000	1723548469000000	1818156469000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
126	\\x1e812ea66b3bff93ac85a9caba8bfb3fdb8e78eab082b20e87989056ba3d7a13aaece95fa91a4d424c65323cc98cc4623d1437ba075a98c3024a12d8a9285f66	1	0	\\x000000010000000000800003b19628269c37666433ba2efa3dc3224b3b4eeae9000aad103c260f277881127d829e85295438e6735af022c814e9076316bb129d2f84af7fb63b45e27edb718f4e44dda359462e07c069b051d3a61dcd44b3d80be59936129990d2e6a75b55b35942dc15469d3e6b2394093c977daefb21b292f08dd7cb4bd7b817663151b971010001	\\xed3abfbd3ee136c686410f17cedc9a9d4a2ab3460e0901a505c82b3fb86b84065927ccd287f4d320395745136994aaaa9221bf9c8682218fc2c10c7250c9fe00	1665312169000000	1665916969000000	1728988969000000	1823596969000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
127	\\x1f6994ed3907524b026c14694de338f419e6e8c1cb6494040bbd670a4a0a458a5b46fb8e9320081bf66fb121289c0ee1179766db1a1c7cea5e99a9ede9e8f959	1	0	\\x000000010000000000800003c900ed546518e9bea1822b96f31f72caaddaa48648eb076e4185ec1f7e8c312704665768e8f8144511c00a79fa78979795b5f75cb98551e30235663d0dab989b0d336200ba3f5c022c49305cfe158dda8bd9fcdbf3bbca686a9ddddb4ca0019dd2711c8378bf63b38024417c1282f1eb6a3108766b98f95d63e2c74e04b13453010001	\\x24e4ca37c414fa07b63ebd84ef863dcf55171a02df78d1bef5c6ebe053f9c12c924f7d647cb6771b04bf8875a19677c93d166c1fb388fbdcd58f9b7535c5af07	1665916669000000	1666521469000000	1729593469000000	1824201469000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
128	\\x20bd5f9bc20ee2d62ceb0a6ef58b177c67869d8fdeb1ece680ec54d9783fa75ff351019194900999e00e534273afbf98505ac68931e8c275e3e29e9e98a3eb79	1	0	\\x000000010000000000800003dee53dedbde932cb51e2c9e0182ceb122d7c3a43927d9f00567dff2246f5f6e6dc3c2671e87baa544c20d440d6119d9948a736219e8aa67719c2cb463ee2103478ebeb406020cf53a60ab72877692652b13263981dbe1100d983c8521af5460bc1b84b6c30d4c2972ff2458819e8dc338643de320fa68f89544261d14253fc87010001	\\xa1722adb87df2f1246d7f8945504dc260bcb3c965385078378ae5793ca29365aecba680a52b8ea1353d46a1b6125999efc321f6f0d9adcf6c64ca18e86703907	1678006669000000	1678611469000000	1741683469000000	1836291469000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
129	\\x21713892f771c83e155091a778616329568050244d98664cc74686d221462e79cc131586015566c7f1f45bf0ca8f44b623a9c28dda939131877388408a7d3f9f	1	0	\\x000000010000000000800003e2ce9c4160e6f0ec22e51104ed3c658929aa5220f563657aad36f74f3f2576e262a5d8a4c9e6c67add3e1add47d369ff990f04ac2bf185d764185b25c76811b4980b21fbe7f40341c56454f0ba647267f4b4450090da85bb971c5fe3e22c9d64cce50989d9067b84efb59d7d56636626b31cea52595a3465d44929a589bdb0e1010001	\\x631d1922e1b56556d8a70f35205ec6b36bf01ed48a8074d6e1f1bbbdb5bcec8e1afe7c2ec0c731c4107a31561d77380e1dfd4f8264c9921987f49fba3ebe3a0d	1662894169000000	1663498969000000	1726570969000000	1821178969000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
130	\\x21698941cb35f9eadc75a762835148c06ffdf34aac6272c35f612b7ebf6873297b81c8f7173c629b063b490b829209f0d964245a1698497b709fbee201e8d4ae	1	0	\\x000000010000000000800003d2f52d121274b9e0a41143ae069238235031efc01ad559a68ab6cef1718bce0f53e40757b70eb806ac210efa8a5c7802673ee80ca1114372ee2b22b5b65f8abd1170abce85ad3b26e32529e50a0f017be4a8aab7c37b564cf09837b5414de3fb932238dd178c499b1e0eaa549afc54c2fdd7d9953bf83c7159708cc7ab3b6279010001	\\xad84efc77e496cd022f46e279165d0a70222a2bcd0608d4039f07539ea970222afcc4397f61c6affd4c1e951c8c2f4a88bc5d4b55ed2224df3608aad394f3209	1661080669000000	1661685469000000	1724757469000000	1819365469000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
131	\\x305da99faff5627e2e86e27b9b83593754f6ca011fe7df2c8ee64e2e85127b9e3d795ddfe739c5c46433ce2b366fa01ee52d8c76695613a096b62c951eaadd81	1	0	\\x000000010000000000800003aa3fa1d4affc70b73665589ea50ca8a85e2053c100244f6d416d2bcf65f5dfcb3f821b9dfbcb1751662ca141102fd387ac0dc7206d2ba2372dbe81bbba574ed0e1d94ae60dc90813ebfaa1bd9ebeffd9b934c43d4f6c017f543fc6afd4c283438d0ddbe05a674d0bd7d71d9d7e75c9905a8984f91d0caa950210c2309956c4fb010001	\\xb4a2b0be6c5a7a7457ce03ed19f9e32eb0e6aa5057639a9aa1aae20516ade18039c5bdd2aca7877344ff14e6e125f21f70e040debeb7ee40f0af89a59e566507	1667125669000000	1667730469000000	1730802469000000	1825410469000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
132	\\x36191d074f55950a1d3752455333b17007245cbe97acf5a56e3727691df9717a4ac1458016ee06ef90c260b3120c732364cc8b7659c78d8a28754483e9b99beb	1	0	\\x000000010000000000800003d92bdd32f2b9245d3e3b578b866cb41c319c0b8eb5d004c8f157cd63849b072ed7923b75d383b88d1b8c9a59e35a664574b67812e5a84ef3f98a8d60558c5031ef7e29e41103528a91db8d86bc38686623e488a15f65f733ed83d2d1f4c23d82cfa30689e8db194490acd2d32d9c7b2c40b4d35ddd4401f5a9fc3d90ac962a81010001	\\x9a190027f85ff314d7f33c0f0813058276c9c81c5abec22cba1bd14c6104ecbf5223b0d1a333c411c38acd5c2e0ef292f029ceb6e2cb779286c0f8cde1bb630d	1669543669000000	1670148469000000	1733220469000000	1827828469000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
133	\\x36adca78fb1452413a7f1165abda950c618fbb2df8b52a95ad965c3874201031b7f6865f93ea4cc383e5452e0535b43071e0413d9f8c3733efeea83a2957a46b	1	0	\\x000000010000000000800003ce0ef0883ada765a0e5c899fb0c340dd5604c7b47e1b1e764d4277ba083f058bf08015be37fb14cdd76d31043cc4b175a3e74a11349767aed27227ca80b2dd90e5ba2a8ce7b724795c6019577aff876bbc29ec115475170aaca279271098f52a797a42d21cdcc7f8e93ccf7f5d4b69af3e69c7ea0a5daed6ca7c38a75b501e6f010001	\\xcf7883412f711946c7cc7fb7d8f9fdc2967370e736171c59fa54b25067b1df4e0031465436d5dec67ddc6642df4ed167cbb874576f58a4c59c052c71c05d6b09	1686469669000000	1687074469000000	1750146469000000	1844754469000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
134	\\x37f9a759aa479d0fd360635ecfe2697aa995482113085c65401637683611162c32daea4d119687578993b9f2147263ed6d94f1f2a2295285fbf7f7de5b1b1939	1	0	\\x000000010000000000800003c155cf766b0b4916b87dcef0306af2e0d2ad99aa7407e3b5d326f713db38586b14418f7d606e57c5f14c992ddd7a4a415bb9b35ea28e59e31f83a51441f220a3da53e69e17c1a9bd6dc9290338fdd71e5c2245e6346150851bf268ce16be9dc676a10372dafbb6d92b8aa2111a8ef0c0d4b18c2e49b666789c6aba814e387217010001	\\x7a8a74469c7048d087db160d93ab6786cee3342936e952d13357f31cb54d69e1c898cbc38e1ab7e53b6b1d513721d220b1ebd9ff46bcc8a00e731102ca9c5d04	1679215669000000	1679820469000000	1742892469000000	1837500469000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
135	\\x3809ef43b748b399491bf0abdd62fb80fdcaf773c0ed3b0ca89f2fa331fc38086b979e34c6d595399fed8e10c312eade7ad6ff96efd4657ce6b8dd5ce2d5f585	1	0	\\x000000010000000000800003e4db76e6360a7e82388218c5f748ba725c7ce124a77a590ea85fd6c79e5ade95ddf93c591fe7a3d6a27c3efc533b4c2eb4a01f5d3c1d07c6aa4eedd6dff3d980ef188b872feae80fb8164c2affa2dcd3cc9e991a53c1e4f3e5f6fd38354dc4f90f277fb82fcd96c640f0ce50f934199e05452a266cff6b851f47b752522df401010001	\\xd45a641f11d227d30e1725739dcc3ea646da29cb822f3eb3a77228aa2d4751a5b9f5e339619d231cb1a443db0589e13c60319fe3f0d3a56c0abd892ef8db7306	1679820169000000	1680424969000000	1743496969000000	1838104969000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
136	\\x39b5821c126977a3405ade48adc49d81b4d1e2901ada1c9523bdc09f2103e17f25b4e1d172bc6dfe2a722ace1e012755d012493ec9c54d60ed9ef64cc9c04da6	1	0	\\x000000010000000000800003ba6e71058ed3378dcabdd8c836630d630925e9d01246f9d81ce3cd88c666da522d357fb492c8e7a28194f757efafbe632e71432c3bd6c8fbf6fe3c1813f89d78721bc5e79ae728d61401a7871789733cc0411d57f11a538ffa6616b3966ecfda6965da011082e6bc3dee46a25b032d8bca47c37b25f1fc5cf3538f5bfc17c9f9010001	\\x967fa46fd235994c725d12cdd35c4492194840cb9521bbe8b111315fbe9ad5d4d36afc208a5a51d1d1c32b5b5f82130683ee8355564d0dc354573338fa1ac30c	1670752669000000	1671357469000000	1734429469000000	1829037469000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
137	\\x3bf1e52aad779b6c64098a01bf0c2fada5030c8a3424b060baa18b088842f7e9c2f772ca59ce9e56842c63eb64922fd3a8c79cb2f8094bfd6d7a78673db32775	1	0	\\x0000000100000000008000039a5d295b698f7f64b7aa9822f4917e95192b521d9d8652866fdbebc25d95905a1994f4e03396f03f5649eb25f3992f5c3fcba1295eb69f2c062d5bf63ecacfd393c27833d52b103ce7f3119e6c5b2330333dd901f3f7eea9438a83bdcc90cbd3662fdfd2e8146a0f936857298ad729109c0437915d028e3d71404c0478b4662b010001	\\x0728df52ea111cbff79e4e6ae15d02220cf9bb5f5e129deeaadb40600fb9dad236efce1b0d8467bdcef2d11a6701cf5c0bf6c9a8481623aad32141659d233508	1680424669000000	1681029469000000	1744101469000000	1838709469000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
138	\\x3de949d8a797edccbdc1541b8d4e4eddcafd1ad84018716116d97a3a1b8418eefeaeddb3516879584265d6e53647e22b0cb4cf899541f21564b324bd1f749d6e	1	0	\\x000000010000000000800003d2c1954de472be96200f7e909a61deb0b24d1d44bb0cc47eeda792547323eb8cf647c0833fa4d20279f4a0cda3ffc929ac81ccb5e80dcbcf457d4c3ff5de58fe29423a272a6903a5af9246cb1e77edaf1e14700d615f37dc0974f98532614451704098c9127feaa2583fd67d1047d325693a4ebb9aa1b9c7483d37df5da043a5010001	\\xd6212becf6c91e95eaadc0439ab661d81c94da7069db400444c7df0ffbb1f6e4f9f6066a6400c620702fbbe2089b5f3f9ef7147abe639702e56611b244133707	1685865169000000	1686469969000000	1749541969000000	1844149969000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
139	\\x3d1dec3cb4425c82f36080f1572fd0b615dbea168449bad75e74d11d33c53152635564a747edb185845e6f780c343c450bc774dde7355679084e7c0464e94d13	1	0	\\x000000010000000000800003c2846833ceb938049ffad1be1cb53a2e9989437c6d8283fed0543a81c265a4b4ca266d4ef0e13b9a75945683d38cf9f4f15bf499f732af2ac6ffb40ba367fef77758e3cf36b22d4898ce912308940f405f60db18c863d69966af2db50a45a5abf4b6dfdd07e54f010d3f4206ff0c72472d09da0f99856c928f261b3f0d997a13010001	\\xbb4b3f7f78bd05d684618475216f9077e2ed4b2a6fad377fdb81b354df7cbbb6f3d529a526482f751479352f5fcd36dfcd8ecb6dbedfeeaea35dbe486423dc02	1685865169000000	1686469969000000	1749541969000000	1844149969000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
140	\\x408907ff4904ddceedb65c5d0017e48560571188486495994f751062bad66803347eaae5982b2c56c34c9ed1434aaeadf92be65a0d0d1bee902a7bc1d17b2cb0	1	0	\\x000000010000000000800003d002bfa6e7db813b4cd3aefb1ac5ed8083a4e68995ded6038b28b8ac7e3de6ba0d65daffb7722288fd63e4f48a52027607e0566462bc4eb369e08ca6e1dd87b6f28f014a8d6f86b8ab81c459d7c44a2fde621ff5857a5b4824acacd4f0def0e2ac1ef77aebbcd7ada68de2f7aaf7dacd30ff77cf5b7608b322a490afa78418af010001	\\xd326918a66487ccaa6efc9fca327623f09b6d1b97cb1649173cc0b45da183154185cffb7ff903fab8fd24241c08652aa8bc30119f99bf01dcfb1b75992678e05	1680424669000000	1681029469000000	1744101469000000	1838709469000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
141	\\x4289c699735088d72a14464a9d0e02ccb49d3323b3d6223c07fdd66ebcf456663a7a512c2beea038d5d0014588bd487af93ef3f5aa8745d08a87d5e5f5856da2	1	0	\\x000000010000000000800003bb15d43ea0a832c1b0e564348bc711c5451aab25a57a9b93687c3c185b24219aafa5b9e8eec33f2ae71d8fd2aeaa46a67bd00ec89375af077abe2126c47293a9b8421926866cd84a327369f27317ac1da624d6fcbce5fea48c2d32cc99ca6c8fa5ef5ee56ef1d0beb84505d85544da28d50a64fde65de70cddc33100ab534943010001	\\xbbf63d0f2ae407ffcbfff590c4fe08222b53fa4a0d02526d1c5cdded5778fba0b0058e9b3006778e9423833e5d31c10e0713c2f7004832622fc13c0e8f3f9c06	1679820169000000	1680424969000000	1743496969000000	1838104969000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
142	\\x442128046f781e4b5373852e618d5d433bb4e030d5304e5f1e1960990cadd096ee723f0741bc575b4805c3beccec7181b99db9fdb432d491bc8e90cff03903a0	1	0	\\x000000010000000000800003b646e15a49fa3a6dc1ded311dcd1d8220ac07fe5255429ba366af3a7004b20a891dca2e52fc594c47e5895a89950c27ae82016937398a1298793af053cca9245003f5c48d1fb6848746e248f926d630f7b28cd0b3b5d331354632ffe51236037822759711f99927040a5bab83f029d14771c684d10b951997e8880474bdfc5a1010001	\\x0ead9f6ecb14bdaf49d7636a53cb917e7b7814ab5bcf06036b89d144ed0199a9487bb603a442de0e03681f631d55d0454de2ec19990928e9e6f8760bb3bfa107	1670752669000000	1671357469000000	1734429469000000	1829037469000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
143	\\x49a97a474ac366a57052c08341fcece1f710fa90302d1c37896a9d4232df2ad415b67f9cd126f1f37364eb1b9e323582dbade45f10ae26136fd86f3ca1e99622	1	0	\\x000000010000000000800003cb3646b6fab198b2ff935b9cdf80f5a9086ec057b29c6c2a47fa10c8291911b7c0562801941d9af7b6c4e95e795ce3d36c8014b7bdbede8e48fdc20abb6385b18814c9e93c3580ab81107ed6a61e965236f17862730287bc112b99a9515da16734ab340c95667221dc089a2c32e15f64b751bcea50a3badc3394460f13110a17010001	\\x4279e315a0d763780dc43155dd47a3ba3b09e4627c0707d32ed9c3cb3493817297c51422b9b5e93c97f59e117572a85682ab4ed682fe3cb653be11724dc81707	1684656169000000	1685260969000000	1748332969000000	1842940969000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
144	\\x490d4177baef06e2b3df173192a067251f5f071c786c677371ad17609e9f15bb08c065424b2ccc145a40292bad06085f785ea0ef75433177b9ef91a66c852002	1	0	\\x000000010000000000800003c94796ee26d7bd2cf6b55e1645be56cd75e06f212c53bd6da62ec022c7c738c3b57db43f168eb7b864b05f6d8b9e18fb809a8b4a19c8b2a93dcbfcde8905400748839d6c7f1daf328e680d938bbed88ede920f068b0e257ce623ad0eddba8341cc2e7464fa2217b752b413441f19d6b0b75024f5a56e7303304414a55666f3e1010001	\\xeda0405aca35f8c1cae88d406b61c43934511456fb375b7ebe634b38fdee8d7267f64bb397eae880abeec51c6db3d9d34df9aee8ed73ee59be16b83a9c65a40d	1687074169000000	1687678969000000	1750750969000000	1845358969000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
145	\\x4ee5ff4b4494195acf10d8286dc87f309c657dcd9539a8e8066d3028beedf688351266ff37273b747e3d5ed02e7c71154203baf0e9d3a8599c3a13102de130dd	1	0	\\x000000010000000000800003f120ec51530107edfb1d35322dcd825ffb4c81df745437a0c388700f95c7975b62dbefe76778bdf9a4d02b66a987e8c6e04ba6f20d2624ce5b896c739aa126a60e0d3540a30b744371679288176b2cae2b8e5fd02a75d20875fbbbc5bde2a14c575339eb3d1c2256a44f28fd79deb86a0bd65b2b34975933921272c26bbbfa41010001	\\xa72ff68de6fe859d365272d75468f71025690bf223fc7071e042fce06ff552af86e24fb26fdd77b444bd6c3fd9a3600cb8e018b46277165aa2df3067d3f8a407	1679820169000000	1680424969000000	1743496969000000	1838104969000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
146	\\x4fb9d2976879c9d943446b61772d72fd6c007726a21cfbce442a788e5cb34c2c78c1c6a1ca10bcfc8d16aa1ce6ca97984cb0403025cb64c9caab084a4cc5bc1f	1	0	\\x000000010000000000800003abe45a89eb80402902c289dc7680b8d4864b8d3860d3980ee1b5e5003bee1dff27812e34b385b8b0d7a38cd9ecc447367173b9ab981253ce00382944ccbeaa5c220fc0502e3ab3ae77de6ccc585065ed2ee3c9031992fed391f4f4166367df5a17c0331531620cd04c4b08ad538501ae16fb26a0811751b3495a8aa19e22079f010001	\\x2d0a7d7a00c1a6bc03cb56bd7b5a95e1d9ebc4c1926a56ac2d74c947af88cbcaed00810755313bf6ca7e48a3bed11884c34ca9fdb4b3fdcb6ddd6c5263f6780f	1671961669000000	1672566469000000	1735638469000000	1830246469000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
147	\\x4fa94eedecf17d76bb0a8f8e8031e56468c0ad1de90115e2802b18e6bbb3205de85acdf990447370dddcc2860d27e3d231c0527ad2742f95a8890b2de5d531db	1	0	\\x000000010000000000800003dfd58d06cae17edbb2118ddecdf1e1a1fd0b8e029e982cebf94b7b7ee15af4a403812333c4c2dbc2ba4941d0895df46d8b45620671e6fe2c9b1860ceb146b1cc12170ffd01a3567c60dc59142a75403a45b0502b1d720f1aef4bf0ea0abbb5dba395991eceb4bf2f0580edddc6638ef4849091b0103b555620dff157a1712769010001	\\xcc5e331060212669dbdf8603a82d304f469f335e7a8225089eba8b2a0679d8e924e0546a7cb68b678b64ef1bd1e6830e89cdad8f4783aba53541dd1954bb7f08	1661685169000000	1662289969000000	1725361969000000	1819969969000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
148	\\x504d7e51dc763d7c45172b7e7e4bfa99039e84f5fac4741c6a5d8f384ca6d34ff40f1451f6f943251a71d88656d16f724e0f915a00d5872ae0564f67315d19c2	1	0	\\x000000010000000000800003e11f8153a1d98a8b9c91a14cd8c1cb23f85117694969daa073d80c5fd735e48525395f5515de3331c33db91d03ff9203d3af30daf7b765f36d93e7954cf8f120c7c01068ba2f1c6294475a9c8f4186b8017228851cff59ea79a1a7d8c9e0fbc4f33cca0300002f82be3260cd35f63b7fbf6732b0575c022e31a365c3e10f1201010001	\\x658341510b062093a1775f3fb131f7442fc5aeb15353cf52f17c132a43222a78decdb6f42ac0bdaa65f258c7a8e58fa660e96203d839bc7907f2e3598e31990c	1667125669000000	1667730469000000	1730802469000000	1825410469000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
149	\\x5079405c355722bab5b4b0793d89d8bfdd60905ce1ddd455fd13777e43aa150c7d99ba6626b51b57b515372e8053eb6463b07cd69304a2eeca0976aca63a8a45	1	0	\\x000000010000000000800003b3c6f84abf2e910ca09f9eebc92570caa2fdd1f053b37e71771a287dd4a22eaa3f0135e69b706a6409fed10236e251b2150f527dd255f188e06076a97faa4ba8b4889012a5ca7941f49e87770ddc8aee3c8289bb0739fe760c588452413fb78d87809ffde3195eb28ccb81c455ae05526a23a1a57ff2e400f8f5a0c73735087b010001	\\x907e8350b1e701a786b8117eb55e11db975e472272ba01403ad5193e91ff68b077b1827e870d81afaaa0b90b8223cea2a47335f46d30d6203c79f8840e10bc00	1671357169000000	1671961969000000	1735033969000000	1829641969000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
150	\\x51c1fa7610e261cb5bc6518b8bcb62125f880003dcffa6f991a7548791cba816d5940c1445667dc4a0ff8ba6dd933fb39ab1aade68a04b5320c65386a6a9811a	1	0	\\x000000010000000000800003c354a1a846dab5d0d0c915eb9dfb56c62db62b96fc8d805e4e4f9fee2fa93dd17e5763afe660cec4f9957221a532312fc5b48e62d7ad629ae0205ec03fbc3f1f2dd2f4a59f4b3bd08f19a9fca6a31dda503ce9fdb1426144bece20541b9f412c47aa3c8066332c137286fc0190405f8b032014ca2cb75f074cd8131f2346393d010001	\\xcacbd0ba401d743b9901403e90483ea32c1a24933ac2edb6d6bf51b3d8362e8bfcff0fead7bb56a7ac0c93ce7d964a0c0d2119b5d3abc543fb8286aeff294e0c	1670752669000000	1671357469000000	1734429469000000	1829037469000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
151	\\x5a719afc19954ae6e3b8951b683c67a52fba5336ab4aa30348db9b963a9f830da43bb334f80e365eac1f2f4b3a094082f47c8af2d7a3bb75ea3813888636a8b4	1	0	\\x000000010000000000800003d174f0aa766a050759c4d5062ae4d8e91c495d2141c43735d32d5cdf7cfa6dd3df88918751c9443eaa80d97f96daab7eafe5d6d1624ee32ab6880e4f99e11d9255067a8c0102395b133e98b88101fa6ed5fc489d67eb90f2febf77e38fa3782d450604d915c96ad5814397db12bd28907144dd41b7c29afe9d9968cbd869af2f010001	\\x0aec5a2a2bb850bcc8fca5c38f0abb2ac7414377fc5bc4f3814af8370a87e487f10b6e583bccce36d2fbbe4f7dd2a7709ee4e9cab63b26d1c972236f5747a001	1668334669000000	1668939469000000	1732011469000000	1826619469000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
152	\\x5b797fad48ea9a260db8e5ac0d8e00498e3cc84bb6e11c1d5571d2465ecd07a6fc68e91d76e726de41cc78c1944339dd762050fe65537458366ec4de72a6a850	1	0	\\x000000010000000000800003a2b493afaabf01f0beacd8d05488529689e6c7f4f32d59a6e5e2daa3f23ac4b7038eca63b761de69a40a1b03a505012a1ff09629346a41470345c79fafbcb1ca17712d4ff9171ccde4535de4336e8132652866f76e1898cef2e95ac638766f0eedb946b941fc058fed26c92e327bc9d1c0ff8371862607143ad4d7c590a920d5010001	\\x09680df3e306454647f4f08070acd0ebc412df4d8baaf00ec2ef95503b541a610829a03d50fff72cec7b5f50cb95b20851a6a0d51132b5521bef773da2f6800e	1675588669000000	1676193469000000	1739265469000000	1833873469000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
153	\\x639d85e4bb9be29a7bb3f31225a91d0d09b89e0b8aa15b1e3d2fd6869f40e75aa0139cf868b8c52abeb0fd9c2f6c60387b11b633df8addaeb4ea0bd35591b2cb	1	0	\\x000000010000000000800003bd93a6027b9ac11306f55ddaa033a5c7904be943d3e45767314e8f3d0b6c44c2f9c08cc2df8918696c37972b4b423ce567175e1db8d5310a54920f11e693e2193212c1ccd01fa44429829d904e3533f2cada8dbab2b3be1758e69eb900147bc56fa3d5102691a101a0865043b21e226f45486f8bd2b8596e6a117b919e312ae5010001	\\x59ac445f87ed7779e1addd3afea410076e1d12c6e44b0569c9debdd3149208952ebf580ab56ecfd8f1919c0182da3479a1193148fcb8e8bb75a1a454c230a906	1678006669000000	1678611469000000	1741683469000000	1836291469000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
154	\\x6565fdda74a5642d99bb4b86bca84ac0eb0e598e91a6c42bf08030b364798e6405112e34f18e2b45231f81de7c7aa50ea252f92529a3559e9cabb5dfede4d28d	1	0	\\x000000010000000000800003ac3937b563a93472abea618b69e431d38803e5cbcf9b315d20b62f4a252e96419d7f7686134ba3213b4a07ae744479daaf445bbc304b51e0cf2323158384cf119d6203c3db1607c01c00d8b64e802cb9331bd502d9305181493e44a97b653c64c8650f8693150b3ce484de1d3c772d3160b67982c5263299a3d44007d4c173c7010001	\\xf6c30700b53db53820c40e8719a9a8421754c089dc0e17c93cf042df7a2271cb7c3c10a641de782e3b937ea7e233e2cb21368104470ba17c694b99b48cfa1d0d	1686469669000000	1687074469000000	1750146469000000	1844754469000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
155	\\x6689b6a3149b23b9306406480457d059f0d13bbd039bcf498568a29cce8c90b3a10379192daf3b5ff2e2d5b2134e9f411a53c58fce1a42fa18b3ca16fed5a96f	1	0	\\x0000000100000000008000039efec342a024d7456f6fd19a0cef05bd2c5bcbeae2c4d2a162d4e51b90c6920e01b35ff43dbf382a5ee831751bf95f482636f68ae4fc8d9faff3437890d586cedf7e7cba2ba4ee5b20e90b48d85578b01a61d300a9c46d9acbf1da6a6f413ea3da7e42d21388e5fb428e3a98292d8e1e97243c88f9ad5d50e504d852d00a9951010001	\\xddcde73c8f046878495a2b53f8cbc30ca52238f3c6e8bf0a781b66aa69fcca043eacdbd69e9aa25e3c1f1abd6e9f3a80ad8252c7ffea913bb3bdc9d886f08500	1662894169000000	1663498969000000	1726570969000000	1821178969000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
156	\\x67e5895454584eb9010518d03ac9f8237805a37f322213c30aa593204dc7d7b04cbd7e1ed91d9b34588ae0ee01fa8a52468f195c55e31fbea492c469fb14e2f1	1	0	\\x000000010000000000800003cb58d074296fa7ce3a36b5a2aee4527ec847c2e1eea562983a2b0a45629f98348009355633f8447eda72a3b6f957c09c13884febfc18517b5f7f8e57fd51d2f87afd15bb0806bccdc4c504bdad94893060f68235019c277caa0d56c51bde5e21745991c39a61fcd7641c8c5d61fe3c03f3b8101f5a486243e6c30b86ba37daab010001	\\x72224ce7880b033988e74de242dd9c028018443c6732c7cd12547f18e66fb32fbc2b65599748897ea84b6d3b0115c7368ea9e50dc8839cce928842009e32260b	1668939169000000	1669543969000000	1732615969000000	1827223969000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
157	\\x67115f51b3b6fa0cc13fc7ce4f63d6bce5dbfe5136e90eac6d5e76ba1bcdd98a86c2bd32c4d44a2aafe29d8373cecf833c9f5177b496a576c96464c8f666f46a	1	0	\\x000000010000000000800003e0602dab6436fa77abb7deb0197b98a6145995fe57485c987fb07a131410faf3d54fc38173b90a617247a41dca8243d7320334102bca2ebf954f8ecf17509730f8ca9708d4c4dc2a6fc4c820941eabaf1e0df5fc8dbf5ccbf5c9a1d8f90a50054430de210ce394b8a25581cb6b06e4225a4a9cee16aaa68753ede64865c8598d010001	\\xe296624dc132095182c28b27c4fde08ceb64b3aea0e62dec3ad8bd28ac8280a7100675fca64ee5e3b19ecc05c761d6a4fb14edc767b5399a121504a6e748bc0e	1669543669000000	1670148469000000	1733220469000000	1827828469000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
158	\\x6a3d282e4692920b9ec095155ab388c4a65022c29b3f6409275a7c72d53513a41c7d0168be282102e598f0e39c06b5fb858ddeff79cc54870c4c5c60b0cb94ab	1	0	\\x000000010000000000800003a7c5341e4facf400cc57504a3c98d6dfdf1c9e7098d0e15c547bccab476d27518aa45917667f7993a3f780346331297efe99a0f7dae9570f777d9123a53b3a201d95eff1a8e94e436462f3d46faa71fd9e1feb109bec80fa19632ac01bac3460d747240d5297c8cf30f31d45f9e929991ad34e68671626908bcad84e93bffea5010001	\\xfc4f48cb4e89ec5d65df17e5144fadbb6b546881858ac72f07d137989c5f45c0a34d376ea4d9c8bac37f8bc69b4055c78c47dd3fc98bf717e5b85499ebda1905	1659871669000000	1660476469000000	1723548469000000	1818156469000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
159	\\x6a8d2466336dc7eb8b05ade39ce0c5dd3a10f084fcb8be4f89fe6ce997664c6524667f11f1cc285f35a5725d06f9674fbc3970f2886022084b48adaca33117a9	1	0	\\x000000010000000000800003b0b836d8ece2b114f69f9286e937725d2bcb4314ccde8e66e683a564a2f5e6b900883f158fd1963145c9241526f79f95929d3647e32ac04fd90dac0eb924d014816c610be7828da56b98a7650effcd7c7a8054838d26cc2642c08a12762c82eb327f468b62ba53a744f5d14d1b665abb8533e9e9137fb38f166a46fe1c36832f010001	\\xc015cfa96c8563b70f2f4e13a40bfb63c6ffcd3eb154c982a040968ac1354bf689e1606f886fb5cc33113302d5d35f1bdb806b450e1cf144903a080e9f238407	1673775169000000	1674379969000000	1737451969000000	1832059969000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
160	\\x6bb9a67c89a127693305280f7b7abef87284b14369ef0ebdf2fad21eb7577bb3dbd6f5ea44b2d8b52fc59a829a42f5568b5dd731e414965c5d80936ba609da4b	1	0	\\x000000010000000000800003f1562e4b3c89830f5f1f654c3eefcda80203af110eb2d55a480e33918af47de1f8759324f1e0451cca45013bbdd08ebcc1cb85c51b2822ff7cd1708d7a16500f2fca17f039c6aa97e48a14ad153704c49362330e2f00245b086b14d1a36db7567808238adf3a9045ab1aec04eaa4490739983ed8b99310db53553cffab75624b010001	\\x4f9432c807ef3a6a69af7a24867fe2ff1cd96c6f0da790fb7082d62800da6a68d5d6b10064c5a89488878f3598a443f5648160fac24041e0bb342518175ec90d	1684051669000000	1684656469000000	1747728469000000	1842336469000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
161	\\x71ed63188b7c6d1917c5a8a9b98de0c83dbf827b46299b078532563a2b9d6f27d509cd87322b71b094d82e2e908c3ae2141d1a14d2adbb0cd838cf7802277499	1	0	\\x000000010000000000800003d9dcc3074aa8f55cecf5b76d461936029e96d99320aa6596305fd363103c149bfdbcf18b8cd6bac85bb1674633b49ded2c1a4490a22367f424de9ab4ddd80a6a6f52da16fc5835d9fd2cb51e27e086929bad8682cef5594f9918b39e5b846838ce609ea7c916f13d8766177ded6b71a16d12a5e9f4232fb5788d8b24ebb9108f010001	\\x6410ba71d6b615fe527bb2786a448043fef2ed211ecc3fabfefd9080585da09c77d040c192107d4e4e9714e7aeb7e96716d2f57af461d4da25a8dc60c9b11407	1667730169000000	1668334969000000	1731406969000000	1826014969000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
162	\\x73cd1d59ba38b46f3f8c65f0aef6a4d074e26df13031075e8a60446bf0167081a9a08744403788384b3554b2b4837330a07a0997771eb35d653d03a94a65f3bf	1	0	\\x000000010000000000800003e406668963fe2349f739c5ff7406b4dd1f8c75a7991619112e818261cd65be82f5bed3c7810d6e5b14338ad15e1dd77d8eb25abdf04713e055c6a8247a59da9af53ee39805d3f3fcece4037d7606e4dce467ab74193869343bb6cd5f904d9b4073b2c2d3e45bff2c3170e68490841ff07c2743aa0257f31285f0627b4b4ea7d1010001	\\xb08cb05f7e3a8b887f8fa054335d8ec068d1c8613d91aaa4cab6edaf5a92945019ef4baf4c8fa22fdb61af1e6214210af6bf519195b879d494525dce85c77f09	1659871669000000	1660476469000000	1723548469000000	1818156469000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
163	\\x7679c63d0575d1b1dfb84f881b864410cd65ba94cf70fc7c9ad08b753fdd9d83790debc6f715697b02ad590b853700e9a35efb5734a2466ed036f28e5e63f567	1	0	\\x000000010000000000800003b735949307f35264a092c9582126a1687fba49f4c06e533aec19c4941a00cab4a1a5ee5d02f9ec2b54a9bfd03fae700d3dee05969c2670b183e12e3dbb7f049b3516c3880cc25e15a77999ec26c7ded7cf9da0ec13f8572fc15acf265c56d571f71c63c66d05ae3a2a0871e3edd24b672083628dda5521729681192803f676f5010001	\\xd13afff7600ce6dc6d1814bfc2e0cc69a5d1498e6b32d6b38f876f388f28f835ba686a40a9efc363beac1c35289f271f754a265e22fe2dcf3fd9f8940d50e804	1687678669000000	1688283469000000	1751355469000000	1845963469000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
164	\\x768999600299e7392862bc7ae13d4f1b4eca65c59c8d410083a92b7b4a37a59abf1a85add316f4868cd29ca7bbec2b7e4387f410892bc5750c4555d5bcf8b57d	1	0	\\x000000010000000000800003a28fc18b53693730f03003dd51af3208e3a6c32801587b2a24b6be3f8ce683c268146c5873aaf7b6141616c13c005b9b96492968206df17cb255b0d583077c229b5e4ace209552ca6ec7c83c519a35f433b7790853910ce6042d3f025b14c08747542f0a92de9fd0b1919eea121e5fa163d80f894538195220ba3d314aee6b95010001	\\x0be8e285c7a60ed5416fe4f5489de7140b6a28a9b6e62b6ff487cb52400a50e2c1f2dfa21fd4efbb2af93402bc2b77e87d1a68dd0dc7b3a7cc128ebb2c94c305	1687074169000000	1687678969000000	1750750969000000	1845358969000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
165	\\x773d4d99b2b356935b7c9c00ff450fb347d156efd0f620f3a7d8523f9424c4fc064aa6d8026636a635ce482c4421a8ceb5b4f0a4619c9d55b4d581f5ea9617c2	1	0	\\x000000010000000000800003e93769ff3137952da834a764ee727970fb211ed507f7855d0334f2e39368db63f9ee2287e8b599ee8deff93317c7812da41dd66ef8069d4ff41897aa8704a07dd38f4bbe89d4b6b735b8f00bccfd3404153b8034a85879d68c58a94e3d64c15f6f354cd192d3a966ca715a1ca4913b7ccd79bb24563d68230c43a602f2d4397b010001	\\x42a7131bebcb2f7a2021e399b65a26f43ba7b504802c0d8bdc2623446424691551d247458c593968ab39fe4676e8b964639b561061a291f769b1ed9592fc0c0c	1662289669000000	1662894469000000	1725966469000000	1820574469000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
166	\\x7821616e9911defc9aade321bcb49f18994961b0f2abf853ce59a5a461e0b19780700ca9e2bed0ab74d11016ce67950ee0ff12c4040d37cf100e9a29bac83f8c	1	0	\\x000000010000000000800003f6482f92c56369e338a1f5551ea1cf4a254f51d9fcbc129d6d154fdd9f10e3123ca3bea681c69e2380b92adf0e78914950092574bffd8a067e3b719d81c4a7f565cf09c96e38679e197b797e89d67345c9d27b6783289e5b0866bbc50870526a60acb9178752d9de7355d3ab24be8408daf291981b3bc6061e874f35cb379005010001	\\xb8fa058fa8b14b42a18f24d625e4e3104fc62b45ea007fdd5f908c4e40f95f9ead40161715ce65ea9d6877e206034dd26e80311013c2292a3b79c2e64fe80f01	1674379669000000	1674984469000000	1738056469000000	1832664469000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
167	\\x7979a48f69c62dd484970b45e402444e6f53439ee5dc51b078467596ba0c1c16723345700a8e0a117eacbd9af4cd6e497616b4c09b7b1cd1f3fc74c427286c7f	1	0	\\x000000010000000000800003b2a3547dff0e0d2078e7cbbcfc773073f78281b3ad04ee009c16ac5b81bdce9fea80af2f7180b52ecd24aef13b56ed28cb08f2faf2d5e09f5e582e8d8d470aceb6ddefe509a6d3c820c4217b06afb34ffac693f9cb0844c53a16433d05128c2054888cde8571661b6f2bbce8897c966321fca83700532f71f371471b96ed9fe7010001	\\x122cef26d8d4a4f1ba84ea6b24159552dfba6a15db0ec296a4cb88ebb3407f074ea737ca844f2aff97c0c454c41d4d60857f8a408f53314c961be0bfbc379802	1662894169000000	1663498969000000	1726570969000000	1821178969000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
168	\\x797d218f8c7461b1792ec519cbc686bce2c80b391ce4064ac94a35d31bb212399c72da89fbe911889332ebb52ae0b40c7d7d574d5b4b9ae40a69831d24d225f9	1	0	\\x000000010000000000800003c00bd828c7aa34788a90a5c926c074b0dcc9e82cd73c70fae4e5362f15f4265c01dff5624367e4e3ec51bcbf49dc3223bb43794f534bf9a4a166acc21419ee82d9719a6663105003450c2464d529134a3a56967494542d7d15adbc34410bcc3fd0e6f8abd21a30e4c89208345776a4379aa0b6957b54cf5314af748bc3eccb4d010001	\\x13bcb46b98febfd2399ab4c43b20e3e96907cc9e0b12bcbdfe3389edffbc1dc335f9d9097fae793e4c7eaed6abec65b4c2597236a9c2363949597fa210d17006	1670148169000000	1670752969000000	1733824969000000	1828432969000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
169	\\x7aa99cb1102edb827a7e1abf50a51d294a05e05ed876ecf1f1610b8ccc4ff3d54760f0d5414153855a6cfef94bfb8fc450fe1821089c9f92e950f70f99da207a	1	0	\\x000000010000000000800003b374f4085c535a4530b6870fecc4d8de99cd6fc866bf65e2cfce1bbcabf9c1e857d8d359e31d5d06c773d93b222bd442332db309292a2e83af0c48338bfa76e70ef43ba91d8371b0bcf0607e878032005515b837da13d63be121b1ff71f9d9cc6059a47324ea47ca9f36ba0d63cfe658e6489ffa64557d894d70d013cf9dccf9010001	\\x439e9f5323481d2b347ec81ea86461e9d4180263aa79bd0363c0125894093d9ad5812234742d4a78e9dcae274aa4f2a6ff8d0f51795f2c1e50c635b11092260a	1665312169000000	1665916969000000	1728988969000000	1823596969000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
170	\\x7bfd9858f1543166bd7cc104e26ae4374c163599f48e06a75d32efe07eef853cbe502ca86f5fcfe6aefcd2da8b67fb1742ef1947e725dce8da2a6ea67882727d	1	0	\\x000000010000000000800003c0931c9749ac4bfedf398d45622676b6f7c7daf902f0efebb78ef2e38dbfca33c819f90883095072ce8cde10769cf1c2752320a6061c5931fafdeefd209ace5d2607775009004336301e89c2f91424afcc62ff4e6360d151ae33cf4c1b5c1b33a33b8557b016ac1a2972345b7d9360800e15c271e29c544fd87a5413b1d35fd9010001	\\x8aee165a81f3082702209f0c5a72671400e37068c8d360bffc64d77fbefe88eeb3421a7bc269e833319760716fed14608ff4dd4a185d2b1fe337a310682f3501	1673775169000000	1674379969000000	1737451969000000	1832059969000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
171	\\x7cbd48162277574f1298e7e0000b870b5b499aba7614c70923c613a8f153e5b7b3ba122fd4b1f44993fecf16b81be1ec3bc1d3d99ef2e63703b99f76d42b1849	1	0	\\x000000010000000000800003c78e5137618757966e8b99849a48e2ae5e89b5f203ba0cc41756965c461fe4ef0f047c3c5cbeacf990d4e40a145c2c0616ac70197fa2c13cf9a49af99022e93664efb062a1091b5c03e0671f57d9d4be13b8963fe10b2848bdb017a7d01413898f6e03eca06374a3f8cd2c1cf2d66029def18637088168bf4664e652126e5d0f010001	\\xf231895ed9c8c520f726350ce725d5d549df52ef2777d793d2bf8937c4a19eaefa7a38684c516e4e2618281069a14128e7ecacb478c6bf7b88c511adc4b4c606	1673775169000000	1674379969000000	1737451969000000	1832059969000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
172	\\x7dc5f8e2f0bae8c74d30de7e08cc994b226760253d78baa7522907370cfe51929352cff6153fcb4bfe53806c91b7d4cfa9d2dddfbb300f15f782dc01e3c568c4	1	0	\\x000000010000000000800003dd1107c9924baf158ebe5b507b87acc7baae74292fd7b5265324eb1cf11f94cac3e20138184686797b47ba9f29d63604edd2ba6f77350fc93a839252ce1113aa39cacd17fc37d2af329710a24a481c2a1778a3d748909239a7a72da9d77abb6cf7cb5f3f665a4a517df16d66c7bb9916ce710f8bbd21f31d93ce8ef5b4ebf129010001	\\x8ef0657a26bc6f55840f9e580ebcb97f7c39481b3be0734fb501a6a07624d4d8e18d782ddac53c0ca8454cb670c930b2ebfc9d71b54656990900d884571fd505	1681633669000000	1682238469000000	1745310469000000	1839918469000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
173	\\x7edd2a5decb293f398aef9423344042d061ff9b04c4821fe058f4c51deee7a2dc823d418166640a473a4e5b876b974a1bd92c6fa629d0e38161c99e4f73d4ddb	1	0	\\x000000010000000000800003bc89e48338219c02196b6626b48808a710550634172a19ebcd680da9ef8ade82ef83dc3b6f5370fdc917c52598656c7b8b515af42848a36e42245fbf15556f6bba4a2189e8486cfbe91ac10ede8932251a91a23ffd531602d2d72b59946b75e65d55b31c1e45af31954e0e1b4a8434ea20d098e5522cae343c530ca2030d4e43010001	\\x1c40431ce778bc14aa6f920783a427677a931085afa79fc644266aa8279527a058c0bff5c8a19daaf60835768c2fba6666bff5b642deb3f0625176bc2d78be05	1662289669000000	1662894469000000	1725966469000000	1820574469000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
174	\\x8299f32d213cc929099f49fb57ed430f92fcebdcba8134005457c895febb8fe630bd759ef26bc29ebdb1b51a4649aab64f245c81ec9027d3737c933ef118f950	1	0	\\x000000010000000000800003c8ad2e03bc9dfe90478e5703806d59753c762a685c25cf9038d6b19fa1498d993f95162549e44f9489aac781352c26d9e0f38ade976bb1c7708e0a49b22645904427833c6bed0cbcb4f26686e9869517d9d62ca76020d5011a2417087a0043a60e341fa4f715f4b40c7aba3ccf17f9ae8f9d9ba705e8f340aac9bfabbcc79809010001	\\x27b2e2ef2f7dd8aeaa7d40040525caa7bdf26b97ae29a9a19a402bd69484af08973d3cee811a5f904991b427b610d6b3328b3a209243149220a76cfb1617e00d	1670148169000000	1670752969000000	1733824969000000	1828432969000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
175	\\x89d57361562d297121fda8806ef7915499dc5780a0ece40ae92c8b046fd940f10b0c0430ab878cdbbb0b958ee9edac1029ba82ad167f104f04d91aaeb64c1c84	1	0	\\x00000001000000000080000394d63f12e6dda4ae383765b760822847e36b9df69905a1eb0ea4579af6b80c354ddf5f445d5ac9feabe208872d12128a8a705ac043b05e30810565f79b03fca6153d9a3059812e6dc748bc10cef8227e8b6cc60de5aa5139e573d1496db0444cce9e67f0437302b2f1197f3ef4aa116bdab4b866f8ab03c613689a55b1feb9cf010001	\\xdafd6f61e7ac59e20f5e9f87fd25af1728b09ec7abc2b5d8cf310155004df2d6dd2c70fda0f471c0080336720b2aea501d6aa224f1dc5a4fe8caf848f3047b05	1672566169000000	1673170969000000	1736242969000000	1830850969000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
176	\\x8df9b5d502e0f8bce589652a5fff983bf72bbcf55af82bae084039d4532468e81c0a0ebff507465ffdb13552eb1a036ac52bc8d4118df1e7fdab8ed56afa48aa	1	0	\\x000000010000000000800003d37dbeb62e4136635a8b9c4bdff9cccdfbac85a266e0f2f660dfc29a11930f75ea930fae2c208c6b124d9326270363ed7fc5ced649353b9560cb91b7659f12b976af0dcb7e2857e0bb4e1a6c538754cfac9a536effac334c5b170a83bd0b5ecef21b6b464dded800d22fda5639b3d61a059d4091d86a67bdebebef8f9523108b010001	\\xac2c33df45ed8c105aa5a3cbcbd5fc9a74d17e2ca0b50fc9dd838435da55021fab5da91fd605e04fddbe25577b0c00129c385e8b728a5538d83ed0a10fa7d903	1684656169000000	1685260969000000	1748332969000000	1842940969000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
177	\\x8dd944b890232f5b0f4b0b9d46a784e00236cab3884d4bfc1f15263e375660c61c4a411706412ae60127bc68c12b5c1180dbe90381d16926b89811be0befff7e	1	0	\\x000000010000000000800003f07a3ee52f10d6c0d28b7d1e626dd615be99f4914f94c7ab5d8b130fb90c3fae2f4fa7f4d1b893cbdbc0d78bb8a9a0f81a33a70acb72cfebe153c584c1513bd0420bb7b5b9519bce1d7b78f8d9268f486e19d4eb4a8f7ec738dc3917930d3adb5ef119e0ebb52cd335d80b1c79fd965380d56a846356684dfc4d6555afba54db010001	\\x81ce0091a0b0c7c917aaf36414187840b05da7996d8e6289a583823c73ec1c52cdcf43b763de8100a7d7e2767f42aa548a441ed3d2922222c8082fc18040f906	1667730169000000	1668334969000000	1731406969000000	1826014969000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
178	\\x92194ad69725cd0208e6ae94267e6497a178c720be88276ffa7dfc0a89a6800e4bdff8d6d3d8c6083ab3db61e79bb0456a8ff1829d2277a0eb9f39a7a7ea196b	1	0	\\x000000010000000000800003cd00c3983bf5bc391cbf348caf33e110da837dc87e59c66f02ac0e061649f07254da2b6f0a86232e678c485eb72116ad8edc06fca34120a4cfce802d106b94b0c88d7dcdeb1cbffe87e8930742ee0894b55a0422508ee344943ca807904cf170397b88e2e9889dffc9c044a5a1c1dc6b94a09ab54c18a87e16018583feb9476b010001	\\xfdc920406fcff06b55e08038039df7dc000d2892b5659c25386b9a1b5e4034a3d4f7fa966e63581449324eee5a27347c98c345e60e789fe936e3c8f181d35b08	1686469669000000	1687074469000000	1750146469000000	1844754469000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
179	\\x93193cb0a32db844e35e1544c51743844b96847fae9dc34a15a7309574688a35946e3c9970e766b1ca0df5cd5cc2f67b2e97861fd3434dd075dcd5f1aa09f8f7	1	0	\\x000000010000000000800003b64850c2d07d395e5b4cb39bd70b76845a4c154f3556f7466e677182eacd5d0e2ceca7d2ef00d307221cad65483b025b3bae64ff5b39fb06275e6b86888337939ec93f1683c8f674745d8626b3b15bb6e2df9471aa21745efa6325a575ff05ab66e46642633f0176a497c790f88217cc159976ab15663bf2dd2c3d3cf505c51d010001	\\x6699371d80c2f600b6ee40955370515d01687614c67b9d44f925d931ca3e9ff602099d897e864a840b06e78d90a33ba67b83a9d05b01f0fa2214668325fcdb0e	1665916669000000	1666521469000000	1729593469000000	1824201469000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
180	\\x94d15baaf6a0654d879ee4241d30ecb2d6f2661dfd74e37566356c918c2137a2f9d39be77f6501a4d965b9bc610ab59f987862ff4e88a6eb7fc3daccbd38743e	1	0	\\x000000010000000000800003ddb9a652056eb15d365bbe4e930bf2ef721e47ba6d4f3a0a587b09494e736abb0e007cbc69fa0586ba329949e22f282daf0fe27656d7ebdc3a7cc0dc52b60303b08bf01d9a5a7043b7aba633b202c45d5e9dee8c411516275d886a14e57479a5ea01f75d565e9b767126a11f6244f2db829b0353ec9f3cfd4351edd8346b0037010001	\\x1404d7013843aa7a7e43d4ba3db865df8f48dc6b03ed0c2d82e859a553eaf8f2a78f4a873083d9141e9c7a09fb9347cc290ea0f499d0f258927c401726aa2f05	1669543669000000	1670148469000000	1733220469000000	1827828469000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
181	\\x94e5ca2321968b162de45fd5e0431f1f5db8159113d650083b90ce1f2d02aa937a3faa96badd25c7e2124c5fabec1bc06654bb7a46ad948405f4f810b17eb18d	1	0	\\x000000010000000000800003c67e6257791a7f57e189cd1432ff4a8a7623739092e102d49036f9bc4d296729414f35eae9ed594a7d0ca02223fbb7c1e15bfb8681a2f9b458671ea5f21cde818b57dfbef4b7b6b9617423a28ea2bb0669c74f3a5588e61ebdc9963999fa97c4adf57aaf4733dd22ed0430dd31e067149e7f3eeec17ba6c71e525b7d731472d3010001	\\xad61790869104182cea08749a9530a25c5622b111a05d654f97046b6050efd47fbfe54e89fb29da16e48b664f86a66127c21dbb26f66698fdc4bab90a4d6750b	1679215669000000	1679820469000000	1742892469000000	1837500469000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
182	\\x9ab5313b0814d26ce6721d0423ac60968bd2fefca73b63200c824f5fe6af28971c98e7bbff7bb2dfb334ffa4821b79072023854ef1ff465233455473ea553fce	1	0	\\x000000010000000000800003cf9b8b271a9485b41c7692e745f753ab7f5faf32ef36b171eda22d2c9d940d15fa91d69638e9f3c271e91b0a4d6b3025477e7007f5cccdab3cd3690e52def8572cf3560cad5e484bb737c7e876898c87405456708578c57584197a0379a7b47be7c2735720ba6caf343ba1c03a6fb27f54b4e028097f6568034ec12056cce8a3010001	\\x02867ec859896555456012770a30bc71aca7465386764d6edac36e038173af4523c7f4a1eaf9e3d4f26334b97d66eaf624fecc2fcd4071df5dede4339f6d1a00	1666521169000000	1667125969000000	1730197969000000	1824805969000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
183	\\x9b95ff7c9a818128bcf82b93b5c053ad97f87fa6a710115657640cfee3d4e0c31483fe165b26ce4582c4078e8e7db23e7cb5eac17e804d98e3e3aa307384e385	1	0	\\x000000010000000000800003e2fc8f455853ed66dbc1ad7b80bcc5c53c42750f1e92332c1d8ef076bbf7aee6332e36600d48f043d112d0595023490473d6287545b73682bd40f08f9c4e1dec4d684466315a4bd063152a9d4c6d84b5e16f6fc67665eb3e81c4591f364b76644b738ecccb0ec40665394ef0765eb1cd2987c38aa47b4c3f6a66741bd58631dd010001	\\x63dba54fb658ff0f32e2d9a6adb52a448a7f459b0604e5ace559e56944c8e4a77fdb8f2002fdac70ea347f16a54cf77dc56127e675c6618cd4575d81cfdad107	1684051669000000	1684656469000000	1747728469000000	1842336469000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
184	\\xa69173a09696d30ddf4957369eff94815c65b40afb8b598906087bc339ce371cbde805484327a5b8347682f3b34bcaf7e8de1e066115aa43242d09473991e38c	1	0	\\x000000010000000000800003fa23a1640a00b1b3e6df901779be95fb10002d91210003d78a0cfff4bee4533aa2326d25373e1dedfc8ac3a96fbeb7d3a97c647bbfb7babda4ffb511beca33dfb01e41f60f966b79b729d164384f871a9b3891061750fb74d49aca1434958b08189d96990490a49969af21c078563b9a4504d99c8ea1cfdd0dfd4f584a8ff4ff010001	\\x8dd4cd01771263abb4cb8397af88ab48e5b650bf57215c1c6e4c708f9bf09f0602914c2c6dd8c1c83cfcec9ddf1e5a3d52172bac0db32de7d42b2db996bfb603	1660476169000000	1661080969000000	1724152969000000	1818760969000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
185	\\xa6799174afd261776a29ac1387dc9e50db19efd4acc69bac295643bcd5a8f3b46981daeddf6bb5e16bbe3fd9169318d3d10257dd5ecca0810f3ab6d232376380	1	0	\\x000000010000000000800003e4c569da06577b5ee0de9edaa2f628c2fd0ad0cf2bd728fd3e8982cda0edbd18058b53c07357e671d836339632a27e96cec46450422a2974ea8758f9d767492f8dfa3d8086868e0383dcbdaa9a6a89b9e5eea97c03919514158ef710429947de1449005a005a8be202be32299ccbe7ab6a8ed882d5df6897e0931c3d6c204d01010001	\\x09fb7ded0129fb7fc53c7675a6b1108c18a134f925845198d13035e3a84f4f8f6deb4a974783ca9a3931764cb7f2f33172bdb3182badc206890ad5160629790b	1688283169000000	1688887969000000	1751959969000000	1846567969000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
186	\\xa625eb687243f4d899c4a4697d111f8c3ed6c0616178acf2ab9d8a591e49f21cca4485c60929773bc5ce6265b527de0ee1a10c8421640db0bbfa056f8062d83c	1	0	\\x000000010000000000800003ba8c93eb5bfb32b197d9322ac0a7afd3b2796654affa19e064531356666cf91ac3cfd12f283da9fc95c2ea7b6e63c958b879d9fa8e03828223d7636409c76657aecdbcdac68592422f206e5de098b64be9cea9302100095c99dbb88155c9f257d4c9ef4d1ed2b1714dc6ebe56970e007e6d117195eb23b640fc4209d19aad783010001	\\xbd7c0c3fc56811151f050971c78905a798756623847ef276f977cfb7d3ad6bbcf93f28f8e7cb4e166f3bc61059113247c312fdbf380b83a7b3875b9f9c5da80a	1676193169000000	1676797969000000	1739869969000000	1834477969000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
187	\\xaaf1dfb552173806e76fbe3c01b498f58c83ab9e8a64a2a11b6abf07ee609f618a80ed3e1d8f87e9519fa92ea947ce4c29778eb5d080bde42458af6a3957a086	1	0	\\x000000010000000000800003e327d165c953f23d560150747ea35f1bc776812e013e7d417ceef8910f1019a9a3125472a1c6db88a7621fa2b8845949c30aafd2f429e381231f901a8affbba9ec7a37f9ec20174b8e0e0f2784ac611d4fd4e4db44ef1b4ab9058ebbe5c539868bdd13597e2e91db83d0cca71b43e6570bc63dc9128105f31918b2d7c9254857010001	\\xe2f9e49db31d8e0968e86b7e9cb1e9889816646ce9fcd64b216b754b269d620a3c8bae124d3fa4b764e093dd221b0196f608696665690616b4fe18fae6ccfe04	1690701169000000	1691305969000000	1754377969000000	1848985969000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
188	\\xaaa18d0f5f8363c8c3ef39f659ab4ad9630fcb4fb14fe4b3d62a24d3ba2e5c089e6820dbbe634e825989443d4e684197c78cd429091bd8db34a4c149fe5c35c0	1	0	\\x000000010000000000800003cc5a15a513fed24b5c9ebe25f50ce2c687d6153ea0a3bf6a4ef278df24c1c40a87bbeeb54594aefa3fdfd42a0c2dc1869d5fcd93aa123fff239957d8b08ee660987ec2571efef9474a3edc17d74399db414b149cc031b9b862be1b7b2d9c152755bf30b359c5712990b6b43df4f654b567a99b5770046c384d06e95ac67fa509010001	\\x12dd2bf2aa647ff0e1cc406bad26efcf1127b2e5ef4867f750a77a3f9dc92ff326a89e2c5cf01315a17c83124d6ba2fad718c17bf3fabd62411da56064876107	1682238169000000	1682842969000000	1745914969000000	1840522969000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
189	\\xabe15ed8f8b730143022c375282574454e436046cace33818ba252004add4eda3056884d8520107c85f1be8e432b040a06ecbded71b871ed6689deefd3142044	1	0	\\x000000010000000000800003abe148d106e134e047580b5d37c2b517ee4837c9dddd613956d22a5b015280fbb5feca160b4b1fed48a53e3be7df53d7ea5af50883e0eb1fcff46b3e118b52d6d1ce92cd76279d578280ffd8d83c318329e6e7b303211a05ffed2cf336b12ca0763d528c056a2c5818ff74f87b8d5fa5812cac19f88cc413e2b7da742625d2b9010001	\\xc68d273c1e48f4c104c3fdac259828e8613347e6d2c31c625aaedfdc7a32c50b2e7e68e52fc8dc16b3eb34c317924a810b1776a83ec1b338affae0d9d7e41a0e	1661080669000000	1661685469000000	1724757469000000	1819365469000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
190	\\xab05bfe71686ff6c0d1ddfda66f5ad4d2bf3fff8612fe9f2a0514082b41b396b035eb3f1693982fd57fd413c281c3a2f7d5f170f66e6077975c80005b1cd7be3	1	0	\\x000000010000000000800003c99c457b49b7940fbf50a2dcab1bc8ae9989f12db6620ab2119a6e7b4acbc3108ceded18c23a7e6e22ad0c46597eec73d2f26d0d516795130019e9da8367497b538a92e0df95b9b9ed9759ad5874d7d91191a2eb1ce72d847970abc91571e1cb02320aa2c97e95a189a42ed34f2611d696400df5a23fda73823b150a08abd58b010001	\\x945802c80295b95936a37afaa321875819bee4136d98fc3e3d26a719b5a37fd1d3dc5a9d2f8800dea965b9ad3ae0d5de6563152ef5ab61236f84e776d7fbd001	1688283169000000	1688887969000000	1751959969000000	1846567969000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
191	\\xac255623dfba25774575b8bc619140c08005c56a974c0545852f723c0e8d798c2718af531eabdf7e93b59fba36e8c4ae5b1e325b74136ffded727ddb2bdbede4	1	0	\\x000000010000000000800003cc8c7b53ae88e1c7b4b0ad2d816b248b15f3d0aa70b8df7dea3a0c6f19a0564462fead7b2388c65e977549ae340139de822fb33aabb729f9566a58c589b769a200988051dda25af7897be952af9c1dfa98709199826a62a2df42127918995ec5042ded3186cd579fd23221810f434eb7b3dd4af24367fbfcdc2f58e2b9e56aed010001	\\x00ed210a629b3437f285ead3f6df3d88ad57cb1a66592f0be57cf7072b6de9e79a9b855fb3ac9099e2408769b04e3284f3b1a1bfdbfa93bc28426475469bd208	1668334669000000	1668939469000000	1732011469000000	1826619469000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
192	\\xb0f5daa52011250d99f987240e594ac7da7c45d94ddf835f371214e67a7123ccde3d8b5f749882b6f99ac8d69b14084f998460a0800f5cbc26e04f2688e3b440	1	0	\\x000000010000000000800003b53ffab6d336bfb484c8dfbf6b44bdb1d2bfcf88eb18e59cdaf4661f8a6963605b8ca12dc08932246e23c6514509071d50ff2b019aecb2f16cf951f247136fbfdc0e42c4e5476ed46156e325730cfa8c29f4d5d61081ee1e57fd35e9bf82e6d0a198c1ec29f13005203e2cb18ab4129c2c9dabd3793c6806f5ae48696a4a8465010001	\\x724a48e321c19b597bcd211b702d17fd73116d1d359837434028983b3a23c0a67a3cd24c27f4e4aa83c63ad33aa3ea44a755aa99aae7fd0adf0e518be2017803	1677402169000000	1678006969000000	1741078969000000	1835686969000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
193	\\xb059436a5a9aed576d4898cacc44be4458dba25bb64d2c9fc999b5d107c915e67669bfc442b1f319e09bd03b0697794a97d284c1b46608cd4eb2e6d08700f7cb	1	0	\\x000000010000000000800003c3ad5d065ceec4c9e8b6faa85afe589e877671b7fbfa1c8d30182c0c6b4a22c0a72c0dd9ef0d46c0be331bd0a916283c125bb46c87357dcf8c1131d31b74741c82c20bcd2d3bc4b68c2cdb78f6129e5fcbd9d32792b66026bece641e83b89c74f7892e3c1e66817cdb321250ae3ca6ddd804523205221359d9da304d2377ed41010001	\\x77714a9e4f5595454e847160830eaa6613eb50849bde9bd6f87e97530e0945c91cc9238d5203f1fe5d7fc7eb404f2e3da664010fea241943ba1a50fd5a78ff04	1660476169000000	1661080969000000	1724152969000000	1818760969000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
194	\\xb03d10afc8385c7be2d8d00881cdaf8f1ef1f43d11da52b44b821366d5109e7d3271f02dc642094671eaceba52718eb4b21d238ef8d16971a623627ee949e64b	1	0	\\x000000010000000000800003c73c6b6a857b7d3ccd0f62c87d16695a95c22e7aebc3774956fc751463cc87cda9d80d2d2dbc71a94414384be6dd5932957bb0c87598e80db07ad617fc093fac984e5211f8573719be5a63a70774212d09705407b3ef124aa57c8dcd4b450efee6f07f05b62fce62e3b66eb8c5a896c7eaef0e12dcf567b2628aa10d39e4e1f9010001	\\x210f42954b121dcd9b32a1a3c3906521b0c6cdc159adddb7b310bf9b4b892c6d8734cc18d8fb772edb80ea7121db4309254363de59bb2c35f667bfadc82c0608	1685260669000000	1685865469000000	1748937469000000	1843545469000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
195	\\xb749e03f1f72a0f797c659733a5c9e6f2545242404294bca23d1776d738ac29b4827c049af74db5acf81395c06b5b4dd0cbda24d63dd758b70a4abdc916bfcfa	1	0	\\x000000010000000000800003e1bbf091a1382836a62593ec455e90d81e17cc77bc080ee741732980492d4a894ec7a8af092992dc163adcadc182bbb56aba99920aa556bcc3e5917a393887dc5a0ac51e93105471022f6d08b1d107077cdb27f88c939ef09181a50817bff3c3cd659b3d9b892189f19fa16f170ad85f46798c7aa7d09660f47a57d02cc2a4a3010001	\\x3011a6a085fbd7561729229c53bd3ca74737a48195564bb8cd16d8978546926a99414a4deee6ed2600f8b6bb9c7961b27fdb8e2afea7f2f14327e446e010cd06	1688887669000000	1689492469000000	1752564469000000	1847172469000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
196	\\xb8b905e0b68c28e44441b75e85789e06a358bcaf400ff7a9a1684f9edada1e7cacbc64b1e9e8d3a19ac384f7ad979dbe898441b27ba410a78cd20cc168f5c470	1	0	\\x000000010000000000800003d9473cdf61089b37999a9acf29b2f558133920e773ffcac311be9b04dc7e80bd806c08378887e4930c2e39488b46e5cfdc36cbd8aa8d571f0df28d64fd92941f05d4f5f727e0d0348c82b87a2be3f2d3e1fd68fb1e39e3439fe845c0e13365d5769936925c7426523de7441db60ad916666c4b9585f38be8e8375153607bf5c9010001	\\x627297be78547f3a2302daab8828ad3b718f6388b90cb08df05d0d7501245f5aeb66486c96e1a6aa643bf5762dc5e403852101ada81567fb1d912abc60a00c07	1668334669000000	1668939469000000	1732011469000000	1826619469000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
197	\\xba55d0b39f5ccb92455e306638abfb70add1d36656a475349a4bbdbeaa8bcb8dfbd32fac4f459c30561bb60f92c13585cdacb1af3cb56503d0a1d7ca12e1e8d0	1	0	\\x000000010000000000800003c9006bfed6f74ac0d594ba11000066d811b4e66f703906a547deffc0e99335cc3d2bb4894b36ee1f5923aaf2afcfe99f8988cd99d0ecbff40a5773661a3cabaa13d2d0382edb6e474def5bd78ec23c6b8463732aa414015e534556dd39ba40d5c7549b4b6404a6a428b2bead58893fec1d0811e9c70a54dbbdd72a05e6ae9481010001	\\x72a57efcc2c77043feb43870abc8cd6db08ac9d36efc10589a313c47fe151e2a895fc1527f6d87e7f3c4acd2e83e72f426487bde978cba2ac3e1da35e744fb03	1681029169000000	1681633969000000	1744705969000000	1839313969000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
198	\\xbba54dfd4a8297c3ad6ff5e34530fbca0c2c551544d80109dc24230d4bb8b5353431cd14a013c29f2df41efe4ba3946c58563c00ee4c39cf60aa90c0b54a096c	1	0	\\x000000010000000000800003d4093122042aa566dfa72a6b0193c9067443d3bcc9fe51a688d99ff4416c7ffda62753938f25b13bddef23e509a784cd746b09122e13f49022bfb21b72eda2a80f145a2d592fab2731a53a55045221ad5bbea4a939b0bdfd74189ba4b7b2bf0d9a47fb2cc5213fb1c57619fba0fd3efbe84d8f06083e8fa5696115dc5ab3798b010001	\\xf000d5129d8f0393ec9eccc5276e49369a68b2711d1e0f5f62e007db9c478e6cdb1da1d1ac21a63028a3f93023923dcea49179ef9cf31fcb2a3d352b1af7620e	1690701169000000	1691305969000000	1754377969000000	1848985969000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
199	\\xbd215a4ddfe724b38499fcce6cc757eeafb8fa0d6be8caaee2151e977737221e6e1f037edcd8b5a7b4cadcf18efc586688688293cda5f17ffc15c322959efdc8	1	0	\\x000000010000000000800003e2f7c1c9eece38e0e2170acdbc0ecb0fbb79720ed65fe8884699c3f2fef5c8f750a1dd5cdd262816cd24bbcf8a31a81ce4fddeaf61e1409046b509ae559e7ac43d539116535e4f2c0944a0cda7507e8b025a5fd6995e4d815210277a8a27067c3765667b9d8a94ddab6c798ac785025940970628b4f71db486782a03a00623d7010001	\\x9aa06b71bc67e0afa7b4566c4c9ac678c8fb43f2c832dc32154381ea72875a2431ebfa9e4c5fca20417d525ec573516732d3074a1a5b73ff530016c5a9766c0f	1691305669000000	1691910469000000	1754982469000000	1849590469000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
200	\\xbdb1fa5284ed2d11437fe7d519b32ed3b824ab45279e5b60c6d862c305f10fdeefc2066fad3eb13dc3480bf8407850520ee7dc7b11f2fc349547a39567eeb9ca	1	0	\\x000000010000000000800003ee7a73c9a96c97edd3ded9b4cab6520da68417b681e49b84f14a5ad1e1108840be174c28316bb8efd8f5b612416eba0956ff36fec1727bd2576dc1561f3851924f1b9068a0fb9a07509b4e257d504c31e06e308ca74d5eda05e3015989a5faaea6ddf78bd51331ace2db383c29e5174dc12ad9279a8e88190a46995a4a5acc9f010001	\\xa3e3b46d07a69b42ec3d8e819ad3116e8a7069274f5a07fd3419b0a1e9aa8490aa5efee9a97bf13b8fa232e80f4defead0d7208d240cac98899d6dd5f45fb70f	1672566169000000	1673170969000000	1736242969000000	1830850969000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
201	\\xc3d912dc6cc3469ffd611811db631aeebe5b9cbe0afb44bbb73408c6ffc110e8d16baeac2f242a0ab7877365d20aeca28b2bc4274b3f22ed5720ac6843afdba0	1	0	\\x000000010000000000800003e256583b18d7117af8c56df6902309b3f7804153a13d784e7f8a327f58be198c23ad555b52de4a7f4cee48df1d044c774a5accdc17eefd6da341ed1de39e43804dcc0df17fec354d0334b2c5a8d006b3e42a46a85fad5450a38be0bf0510b9d391cd0b6a72b9599cb2f80876925cbdc208a4e821b43b5799e94b6886420eb367010001	\\x3cea613347ea849485c09c1e7585aebc0fae104ffe304a595c0bea5a4579bf029692a31adcf54b02e6eea319b393d8bab0c90ef88fc08f66da74b649a704ed02	1660476169000000	1661080969000000	1724152969000000	1818760969000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
202	\\xc86d6858c8e065e55a831579a0faf1af62e61e141f814adf90ce10a109b78ab112082a849c49e5e17fbd845cfe0ff79a4720ccda9f9086134d1a246f30e10c1d	1	0	\\x000000010000000000800003bdbd7a74017aaae5fca9fb673a1e98e9bd5d10133065b890ef562118ec3b5967153c6d038fcc00b7b45c670d2692896af1605c1b1a190414ef625694e1c78674efa5f5f722e2eb97c00aaaea98c053318be25b7ed3dbc8749d36f31609e5b204f472080e15c3488f33ba1c271d838e5e3402e6a7dd731e79d7a9494185bb2f25010001	\\x08aff7d73e12ba4e89a3e396d856805ac10029f4317f825201f08ac9b4961534f0bbb6c1e83f69cc04eb564940128bd3ff39e539667daf1e9bdad65ab2b2660f	1674984169000000	1675588969000000	1738660969000000	1833268969000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
203	\\xc975aad1c9dfda6463878495210aef256683bbf5cc381cba00b2e1556fce8c9e97c1cdba4d4dc9554f0b8149c3dba07d0e1fcdf9cf733e17fef7278acc7c19eb	1	0	\\x000000010000000000800003be116654dd799e9e3e872d44237d80b84b52b40d52feed843fc7be3961d86cff6909f55b083f12f26f6dd8176bd79751d32247b97de2c6d8fd5e5e034b49693378192661268bb23e6d5114969f2cd2501c7fdc5a911bec3191d3a91af9e5ebf95e1413282e1a1cec6d969eceb470206eca50c7e352264fa37c5e2c3765f886d7010001	\\xebf6512f619c49efaabce319a68bb9101a255b9c14245194c28ff9925576523be89a49090164b11b1a8afe7f8a89d7698afde0b31301a14f1827c2a9caf56d01	1664707669000000	1665312469000000	1728384469000000	1822992469000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
204	\\xce15e9ec39e5dfd74237ffc0fae463120c1cdfb8ace669564187ffdeb3535010ee12d313af411336725241ef789274ae8891ba8733361b1bff32c0a79d2f64e6	1	0	\\x000000010000000000800003bee3c2432a27dde90d026dbaf27ebe66427503906a3ef97704b135f3ea9bad2342ff93d07029f9267842ce2b79d2c90b127c16a749550c1be58a63d30890f0a93f85cdce9c32326e8ed65574fd123cf06993d8c244a1c3a6cbd0ab707786b94cb70c8e3ff31601287648d5eb410e7345e82c50efdaa6ba9337fc1eb4b58bb6f5010001	\\x20b8258d416081952a674e16251c7719c166fd7e34016fe26cee90a5600f36b198bc0f0d3e53604a9a293728db1f7106904670fdf86a75afe6d1e4292a10b50e	1670148169000000	1670752969000000	1733824969000000	1828432969000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
205	\\xcf01c909a25ba3ad2ba8c37b898cd61f8301318d90e8cd8a3f23b02607eb49e2f68b518406ba21e85a2deb925b132d9f961dba351d075c0f9c9f40f0a23a5748	1	0	\\x000000010000000000800003cb4fd17ee00fb93d22d44654e1aa07ab580398170f28d2004e28660381d48fbad66749c7a59910b3812de62c0787bfe491add6fe110a3a5d5c14e5e758972de51e06dc266eb44c306beb892f3ec11fe19b74d0fde83e9b42bf36d1034b87272564384532ee15f8910962669539e8951b09812d37122b88a6eb250cf796b88a95010001	\\x97abf92408e80b30c516432d917add9b6a68a44578b76798f87facc990ac1159d81b72e59498f54ecf4b9a9429776bdae571e5e2c90f66b5b11318a4a984ca05	1685865169000000	1686469969000000	1749541969000000	1844149969000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
206	\\xd4d9d80451e839d0a9cf311ce33a388026bca3ba74ad945ab0d7a87ef0b45b4d7e060c402f4f36bd57495bdbc8f85f0c1b493c80a8d632f3f7d015daf998e9ed	1	0	\\x000000010000000000800003cdb00564782a79414d0458212b6f96d86339035765227595a4189310200f5d047cf1d9ca15f539a449878806e78efaa1e31cff8ec9c4afd7b1a028ac640ad58c00aa8346ef68dc97cd8e10c1344a33b604b69bbc829b5ccbbff766ff37650c25cf77cc8a1608247e503b75eadf6db1f06c8f457a9d4cc039168c10468e736a4f010001	\\x13f27418760688adff815c8a618cf75a6884cb3424c944cdb6fb6d1b0705d8b0ea77e3b05d078143b46886ee5db0e1de563ea0793b5453fde7416bda3ae1150b	1667125669000000	1667730469000000	1730802469000000	1825410469000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
207	\\xd5155fb797d6788741c4bbc7afcf4db2d58ec5a29338adf2dda40191e1fe5414b231a7c72b193d32e9fca6f9b3f2833c595c6c50eed56f78f9ebaa0dabd208d3	1	0	\\x000000010000000000800003ae083334d9443ecce81371ecb71b2dbe40df5d02da6ec8a43d9aebe8760bc9595785c3ba37e49cb31856081d188572cda4315418b0982531224cf41dfb6225d36d9b3c6617937aa88518f54e3604aef26a0f7940142b4d5d82622cb5bca5954b449f95c51162d737b78e7e7ca138400c6534f545441a11257ae71ae85c5567cb010001	\\x850a9998fb1a58f91806676e9a4195dca4805e6456d608da3557ee468dea6f1c9ab8a02487f53d71127301c2d6b1dd409a3fa5fc49292c19f6b9b1dff45ef905	1671961669000000	1672566469000000	1735638469000000	1830246469000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
208	\\xd7616191282b06e21441fdb44ae9c0f1ade48ed87e60b2b27531b3d4c13e492e08dc25e9ec759c83e9e65df182dd47371d766c29d3f393c0323d9c63614e3891	1	0	\\x000000010000000000800003d94b76433db9e12311205d356ceefbf6858e68f3b0fc38daeb943c396f32fc588442c2e48878af05ec6acb0c8429faac84dd4f1416a318d47efe4f838b9939061fd5aec2e8ebf2c699b126687558a7274ce121eee8324633aab4bb60d705a1e67234ef1c3a68788c2ba8f1f3f9fe4fe4f9af60c2411a702d3c30c2c55587b155010001	\\xa9b04ebbcee762682a3204488727660abf9b1cf074ba29e3def063a94a4037e3c6881bd8ab6d2158f4b14edd8ac7add073c62a132c0097a399c27e8844068206	1685260669000000	1685865469000000	1748937469000000	1843545469000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
209	\\xd9a98261099158dd1b59d472f747f8dcf4c2df5580ce8c94096086e6be5732b84ac68c2c8e473c1bfa41b08360006032503a8fcd3f40d288ce7066312a53fbd3	1	0	\\x000000010000000000800003e33f930d68ad8017b38b6b61e4b846a8852250fe3ed0e5cc026aa251ecdac7b18c18494025ad7efaf919c7468722298cdc26a04e824b7c56630c5d2032416f30cd127c2ecfabd09ecc0aa76d49e387f9a64b39ac267c9f9fbf655b43ceabfccdbb61a96409653213803f319864e6abc677d28e8a8cd50b2c3fd8da7f37886c69010001	\\xf3515b168dba88b319edcbd87c56eb782b11403961b67596934567ad128ea55721ef3c14fe6b904e6d78cdb7fd694a47447d436c281fa797762a1d765dda5301	1661080669000000	1661685469000000	1724757469000000	1819365469000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
210	\\xdb4183632fa6ea635752f47e3a61440133ad25746b4c3b97992d7456895fd25b978c7420ea20fdd63bee38cfc47aff691fc8595266e7e7b5be57ae051e9d76c1	1	0	\\x000000010000000000800003c78429e58f26164e860519f0ea4f5916236567a171f8cac4497211fab8338a5a35837ca8166e39ab1a73156058918d856ef27910ddc616ad1a4b42fab5fb136284f96e174a1ecb781dec8f1ea83b320062ea3da75a63e7f123a1f679f5edb984adc4bebebc303ff54047f410883b14e219abaf4dafbc2bbb57e3f13b9d8924e3010001	\\x83b67c8ec0879132a401ba30ca006ce85e908c61778f6f4bcc4d736fd3d10c20870677d3053de465a41bb375001c160014023d1a0196318d5de2a1ad231a2107	1690701169000000	1691305969000000	1754377969000000	1848985969000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
211	\\xdc49a1d7da16bfbd3a91e77531a8fb442eae1fb9c6ce7d22f69b877256aec01626eb3b8c7cab293e785f08cc77229ac21b1f0fbff65d32438cec3f2cb9e3f70b	1	0	\\x000000010000000000800003d1dcfe3e677b0775c885a123d7b24ef8cacba1ae0e23c86abb4a2855220b266a3d9d2258d4b42f8bdd03894d8b7523a0ff696c1716146f298ac4bf15c93fb3838805ce0cc16e28161557d5bd13fbfde494e36f246ccd28f2352f3eb8f2be728cd0c5cf29eabdf07bc0a28b5477a97209619d7cc55c3af75c3dc3ece20ca83fe7010001	\\xf588eb95cf16e71b0429aa782d287eae6f50b8bb60abb402f3b6c486ce58b24148438db7b07713d9c72c1c629c842af0dae3b2754e122c268fa1cd3f3a4d9406	1685865169000000	1686469969000000	1749541969000000	1844149969000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
212	\\xe88122f92dc46df3ba590cac3b7d28aea8497bbea374c31dccef7899032761baad1b42bcdfe4b00bf2af29d02cb3f4155600e81ea0ecd9015c19d8e01390931a	1	0	\\x000000010000000000800003c0ca0f714a89c5999f7e388240519cb9115b8d8efc1fa3f941d78a9884e16d51b3a84b3e1dc4a47b6e5b2dc18053bb5173086f3350828d80904a2f1d8d0381952f1e7219116e441d487b82186860819492c7bf12eb493fa7cadb729b10fdf781269df75feb65fd675a6744cf0893df50f9f180bfc12bb1c506b47cecab6beefb010001	\\xfd3e6f7129f37cd1ef19818e26b8e95ac8897512f0968471edd7590ce3d41dc27503a4d25b402f0c2b9ae3625beb9e98e092818368319ee681bcef1eaadd7207	1662289669000000	1662894469000000	1725966469000000	1820574469000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
213	\\xea6d134f2c5ca1581777ba18cdf701555e45c7a29dbfab6063a4e38858294d3b23cf04b1426ffcf1e2de070a413fac794d557814adfde1c851b85b9431661863	1	0	\\x000000010000000000800003b08a22aae6dd7552fd831f8a566a05589e9df62f073f8d97631a97e5e7d7732ef8fd897d452289f4b8f9192d61010db156f1d93484b977ba6425c892b5798c3761c8f0fdf3420d59c4d589d38e24bde88870e806370e1997df02ffeaf16ebfdcdca768b353c825b217071f46f0532910ae57c9ddb4c3983d2e198a56fd651ea5010001	\\xb723494299f5add98d5ad42eb9df991fd75526d2d740fc6e29661ef7f2d6888233214fc713e31a85a54760e5d4846a74219f3ebb2eaa72c88ea4a0b5f6458d0c	1687678669000000	1688283469000000	1751355469000000	1845963469000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
214	\\xec99d6944efa73af050ce4b6a08575a8aab9cd3c1a69c5b2a30803c351de0088cb44b90a669d653bb3ea49c0da0b1574e9805bde9e386724509cc16e99e01de0	1	0	\\x000000010000000000800003c24b7b041dd2a234949094a74a38b8ff0711abf63a6fb6d8b351af8e6451cffd68e16bead15c721524c4f663ebef72c159a00d200be2170731813f157f70a419c54026c64f97545df41c7a8c738e6295875357406024c707f0eee5aef40b1ff3dab2c0ba9a23da1105eb9c3b6fbaa04460f8968c4e01941906fd93139807c7bf010001	\\xd5c842bb15f62ec18fd5d2aeaf8ad7d93d238d38d2df50a5c20bed51cc4bad40e5559ce649a97be8e55248df2ea31f75d2b8250fdf0997630bb47adb04457e09	1689492169000000	1690096969000000	1753168969000000	1847776969000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
215	\\xeeb9b1f15d2aa5d1f482320354594092e31043e734966b3451bce52793547baee6c5841454ee786e0196319b9aeebf990906adb979d3c6cb911c2ac166c10350	1	0	\\x000000010000000000800003cc4de605e67d34bb36d410f10288bba9fe289ed26102e2b9379eb404c40c26768b3556b06c2c73990576554777f682e14514609772f6e2cc965dffc3a49707e71867339cea9ac193a1d346da1f439ad285218641f83a83d253e49e71ceed8d80a71ba08c3563505d3e374920b8738cc65773c3790d78eafc5467f2e94c92f5c3010001	\\x12b143a5f4c10cdbdcc0ab099d01cf1d1e58f129c9ad2ccc59bdc84598d2a27bfad280948d8e271bf415c5212946ddd622994bf2dbeab505f8dcee40cf50f00a	1664103169000000	1664707969000000	1727779969000000	1822387969000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
216	\\xef49f14a380393f005c3f938aa8f80c268c0beb77f4ff1e374c5e9dc0c610a827cb6ffc982507e82b1d66ac57210e42d697651462dee98db233e7579f63b99e3	1	0	\\x000000010000000000800003aca75097f59bb396296036838362654d9c04f6a835138dc945dfa5342bb45b13896b32cc7346e2eca5f10921832a2936510cd58a794c9f815b5147042620d5a80c7bc9c773312d332e942fe3d3d470fed0ff6e9d50fab2f2d55d388fc8e9011e5eb2e14422c2f6ca7ea9eb5b9862e69ac45b7d73f8cbb9dcd4972ff3cd6e0c3f010001	\\xda6603da02c5da6fb613f6046a43793abc788f053e871a1030b1d4bc494df1fa6be65b8fb66a9962106db78bde414976922a6dff4e6c795c47810ae4cf80b80b	1661685169000000	1662289969000000	1725361969000000	1819969969000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
217	\\xf1fdc432ab0725930c2fec62cb41bcb91209b60dd007baebf34a01b874d1cc1fff4f37671528f078399e76ac0cafda42d773e3f03f7429415ead2e3917879c44	1	0	\\x000000010000000000800003db110ee6d01b1240a75a7b42b3fd4a006e4016aedfded02149ff952313b919f9ffd50613358bee5d76a10fd8f0d2c884967cfc072a0f41f7d4feb20e64eb344e77ecc2b1ead579eca0d9e8a3b78090bf27952002d2adf77cab4346504031174e1b53ced2ce20b81fb2cd997373fef3db5c860d5bde153b98ce2d84db1162f7d3010001	\\x2443673fd42da4b4916407a3f1fa6ed021c0a7c05f7a8669871867ec5c78f7f3944f775601e00f773f3dfc4ea77fea726335a2d912345cc020d7a9675cd72201	1683447169000000	1684051969000000	1747123969000000	1841731969000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
218	\\xf8b1bfb6cef917f23fb3a4989c0355992f54ffaa997cace6a0ee23ab0ef02507fafbcd820ccd23b18d39732efbf1a5d5680cba5e7052ee4491ceec69c8a24e62	1	0	\\x000000010000000000800003b2f369300823558fdab7140ff5015ac3e21833ad674a8289f4528d8afba5c67425685034fa08850ba0c8c38736833f06be9b2830a5addee3052111ab131654990909dddcbb7f24611a0bdb2487d62ea91b060e85919bd356436be35b61cf0660778f938fde0f2139ca32997037e1e763f19e81186f863aa010d4dcbb143fb053010001	\\x3f3d84e70bdc184e6cc33a2c88acedafde74fef13fcef965f572365490b3e7ff05dfd437926e4273410507d03a68fae8a4f017497bdf8f33d1d4cf1b0ccc0b0b	1664707669000000	1665312469000000	1728384469000000	1822992469000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
219	\\xf9912016bd90aecce99b019695b609c37315df0ff0c633991c5141fd110744cbcfae43c6cbbd6447fa048e11602192723d3bf95a77d8a258a7b0ca6288199251	1	0	\\x000000010000000000800003b9fb64b9250c292bb060217fe42d3eaec7963994db65b85523390a180008c5df7b69573c94ad306aeefdf13e61287dd3e146b419b7f5a04cedd9adfc5fc24999b169ca42f1650be76b14a2a3788cd9388c2829d18a2af7e094bbdd15061fbc531ab7b9850ab9ed6b60f2de867ce7145c066f8b364787bd16966f4636c8182ecd010001	\\x7c6073890e4eb06dbd9c0d31f44398de5c7ed5e6235a1e29c0e1dcf153ded2bd8cb8b53ad54af912878ea1c357e228c1debb4ae214f003ea2ab09ee8bc4f1101	1660476169000000	1661080969000000	1724152969000000	1818760969000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
220	\\xfd31793abdbf3f520e10294c861994b4137a16b119a357b9e383e2adc5527c0e0c066357a4985e9be03db751dab4e98a0c1a2dc5977715c10c970684103c8610	1	0	\\x000000010000000000800003bdd7f9f8dd1dc04d2120331c4b8d1742c2f7c36ac3923fb565db69d630da693ab8f97b15ba30e781f0210a47f2c1200ac8da82f458fa5cde7fa9bea4f8fb54e4301891f1e5036777a00a43729b8bfe86655b3d1b9296ad95e6083fde11e7853f284a8360a1ffd033a97054d2d70ba1ae0f4f059e839b580ecd575ed9c253585f010001	\\xbb55f618ec7be3381a0739a4b994a20ad20d78505367617072f456a0bde3872f7f7fa32f9df894d0f6dbbf452f95a2594681f35c49170a883c01765a6ee33e09	1663498669000000	1664103469000000	1727175469000000	1821783469000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
221	\\xff351989dfa93ef13d8631d66fbf44b3c4111a5aa1c5f9d05804ec7961aff2b485143d0c30497ca1dc8fc36c18df0bb243d9c04c3f40a2899b2f07e452dbcb99	1	0	\\x000000010000000000800003c4a83a8ae176a37e53269ccf0788f674c7dd170298a50bab3c32b27b38976c9293ab376bce8d204d8b60fe25bb95f88f5ce40b93d4737fb9ef6f2aa35a5cbffa6c3d805da699e1a06968b5425d8924eada331cbb7056d1c58254020fa129dbe475d9dcc1703808a2ae45af2c922a5c10560744182b02e4068ca787878df0981f010001	\\xc0b14fded39be8e6c92fd853ee078dd5b63788a02fa5a8cbbe3dbaec5599eb90395b79320b3c63380786a38b3043775d6963457d04f230676bf6032efdbfd208	1687074169000000	1687678969000000	1750750969000000	1845358969000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
222	\\x00be44f1063a5170d4fda817e6db4ea44c78414f232737a5f4eb035af8bc65ec7d187208e8a69ef96d42271b5d2f558310a98922c0aa5a8fb6bc1e389071d4ab	1	0	\\x000000010000000000800003ef21fec85a574f260ab0504b6cf4ac9abe597116a73f6203d701edf109c2c9cc04bd27d37d9dd85fb492cbe290057ecd4ff36501a170c4b6390b83c116098a434d62c918128ded00fbf1920d50a836564806ee8df3d58f540c930017d93dd855bf45aeb8160ca2a852a81140ff6ca177bd6924a785df8c4c65ff28a2d153564f010001	\\x967a7cae162113e8c86d99f383397e08aae01109efcf80f94b63e0ba522748c0dbef00304b14765067ac6fe4cb0149195d8a7feddf60a255ab03e190f5cfba0a	1670752669000000	1671357469000000	1734429469000000	1829037469000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
223	\\x049ed5519f055896082d3af75e048875d9750ebf15e6d8569de38c1e0f486fe6a6d204c43acca1cc3539eb86eaaab27255af52f7378ad547376ab946b71d739c	1	0	\\x000000010000000000800003efeb748dab3c16f7fbc32243fdcd847f41de318da25041580cd446d4de5488d4378398d60cd59cb1b0d2f2f599027d3ffedc1552212b03f8178bf24ce66f9842e775513d284b2657c09cdecf3a76a1b53442d197f5e6363c2372daf6dd1fb228cb574941e5feb2098d088ba2b4a81deb4739659c5faa0c197e5bcf47e6236d09010001	\\x33ff1ddbff405784cc7874c8264ab10290f23fab6ea7cb65093c05b8182de363542617682bf613729fc5500243d6bb2a7581a488d377b621e2812f8b430a9c09	1670148169000000	1670752969000000	1733824969000000	1828432969000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
224	\\x09528fe4fac39c51f9c4ccfa7b3be64d381597a16b902c35d032a30f3a9d4fb67b7452637d5c4e176dbd801ac03e589c2cfa956d95cd46d014a04366a3f4b279	1	0	\\x000000010000000000800003aeb01194c80b577d8bc1e8a63a41d31e1887cfd1581d162c9e2b7d2b87cb28e563253dcce3e4f70d90705262a368ef9f15031cca882376dffbcd243fe0c10e772daa69680c29021581667bfc84d4430cce07bb189208db7ab910c035dbc619f4e4dc10458bbf40787fe12d77eca06d5078a0578b5b0c296566a8ccdb99fab9d1010001	\\x4f498bccc4eae277e99bc13e943ca120dd065cb00b8bb204c50f9edbfeb802d048e794c7f15a38515d627d9789c10b05a4fef0454c53ba7363d782b6d90eb806	1689492169000000	1690096969000000	1753168969000000	1847776969000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
225	\\x0d566df1e1bbbb2369a3c9eecd059555e11b6ce726bc27213a0e2ed11e0811a6a17b3028763db4b1e414fd15a7da234534861d11f50056f18caa1469ea29406b	1	0	\\x000000010000000000800003e28f4c48d99294ce9621ac9d0690a7802348af8b97bf8dca0180e27e390fab80b25cee85cfa8a2bf342011c47a40c26af959a4184f03e493e7a4024156681f11aa17323d1dd17ded662f963af4419896bf145c0c12407fbda2d5943aa22dc12ab848d576edab2778f725cf0a842795010b795a55a6b12a4297184571e92cd8c3010001	\\x0865e52cf49f6fcff359acb7833cd61ff1c586cf09a239a41f6659483868195be7030484f49e686a67d894d935d3c266ce31ae9a74d7cc3592f24480799a4c04	1684051669000000	1684656469000000	1747728469000000	1842336469000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
226	\\x0e768ccf9101a1fdbfb7949a86d01448ebb9346e266b14b3469a35240c7f6996a983c263f7a1edb7873ec1ff49c8bc31d7bf99a8d03a19ddf01d6702a533f9c1	1	0	\\x000000010000000000800003b1c3142bb9d636c60779dbfc06a5ce3153d39d46794c50c6608844a70d3d5db62d4e31a8f7378bf3aa4c5af6c3c40f597df545238282f57727152d3c07ed98c54580bed3403fdd2939734ca7bec2aab78e5f8ed9498da3bb44fed01b9e2a2df914ad55b55b71d5618cc4f1dc3e748c69e9738d72c2b82a1e94fd0d987efdc419010001	\\x5cd50d27783b20e22a6a72a5e1a786ab80b88066bf1e4b3c5747ad5f35ae200346ffacf9ff185d6801ce3333fe3dab4502aa90bde889c1e4c5fdc51799938f04	1684656169000000	1685260969000000	1748332969000000	1842940969000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
227	\\x0f0615729157ca737afda2037764f17b0c81da74155eabb3a5edcc8bcd3eb38303c1c48d86e7d668149eca61550fdc4497e44b2d2c33268a612bb6ea169dd552	1	0	\\x000000010000000000800003e9ca8998c7d0959f441bf7e1134c202d4c78d4e049740fc9b925a116e9ad36d0d35743c7af9473a8124d034c7521e3d63c4d0806da869adeddffcbbad25a3f5c9c94b169ca6d23bdf4a7f487bd41e3eaf7d4a4a5157a2ecc8b6caad5631b6a1b73f64f009552c8bf8bffd5aa1cb980f2391d531279e4892dbbf19092d5075d1d010001	\\xe81a341337326b493d28ebe35dd72f9d9d3e88f266ef00b9f2ba91cb66b98f95074ccdf77ee7841e356fd50a314631f6885012b79068cc04f2423e3ee8178b07	1676797669000000	1677402469000000	1740474469000000	1835082469000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
228	\\x10dae66026212e8198b6c4a3c836e20f70399e37de394c6a2f9f7a2e5cd366fd59995c2a632945b284d4fb06de0dadce26b70e6ba9205478f65183841f0a3ae5	1	0	\\x000000010000000000800003cbe60457bca9ea6d14ea54dc1fbfa7ec517c1095a2158306a1d8d75689aba31e40ff6954b0d6639c09bcc6e14f99a296154e09ee6bdbeb12f12e26f7c46eb20dcc73a38a2fc247abbc4361c9a9a060ab27c6a6439ae036f5200cdff4717797309308f007ed1d609ad43a4ac36cf6e12a157948c14bb49485045a53f9bd2fafb1010001	\\xa0646bcc9c4b0edbd4bba030bf795789be8710d4bb046337707e6dac427178ee4d3666c0b3ab6dcf17f1d2b9f1a3db455467021b69487d46ad2f6f94c1a42909	1681633669000000	1682238469000000	1745310469000000	1839918469000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
229	\\x15f64f2ecf78933bc266a12db8fc3ee6f3907012f0922022d6a4624ec3c4d2e84c7dec3e50d2488e77ba6ffe553c4e052beb57f5c9c410e0bc0035069c42085c	1	0	\\x000000010000000000800003bb341d0bf217c8fe8e172365a06b3da6df9479daabe56ae300ab80aa1d2745e18bd50dd783a8d5c3a200b0f1d5ceca870666c055e9cda819f5e43cae74e53741ecf389348d74bc472edf03d0aae9335eba99b3d03d5e29c9c95fb56b7e806350e94804243c74ddaeff5f41c6c7a5cf5d94b15d73d68c5e1de100d1dcc868ce55010001	\\x16c7ec0ce62ebc44b11099e516ae1d55a4bdd622ce0d08db5c9cbe23426258cc48ac66afde7522cbef701acb353ef5a12ed80956f1124df8cd18d18a1a5f9503	1689492169000000	1690096969000000	1753168969000000	1847776969000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
230	\\x16c6960c88786ce99eeb907b75d9666d56f54223adbe3217f2936aff62334303d43aa3cbf5934d24cad30af5f9c95f5ce78307a98a6d7b4b5b101ae5683e853d	1	0	\\x000000010000000000800003b4ed3ae810563e834aae38d0379c4a7b7a215971b0b4c91d0560265545ddaf363b9e024cfce4b86e5268f71c626766605569180e3b9306a46b808d98f38128ae62d7e0e3810c0cdc0db693403c4a8d4d09ff8ea743e1320a59cff141672da331b939583d50d2d4fab84fac7b3fb3d6538d9730795b4d1f4deec082f024995d05010001	\\xb1cb541048e25bd42188a075bd8337bb62f84e9fb1158ee1aff7caf5cb880c1a36e3079a586e9be175c8dea1eca9c90463b92cc00bd82dcaf0c9d7f0042dda0b	1673170669000000	1673775469000000	1736847469000000	1831455469000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
231	\\x176af5b78ad53f28b9cc669f32ff06a862e108b60cdf04562ea86f49882f56d0f7a2f54139c8504a551bee839fcc51b092b9de2ef1fca1786d4a8d98cadb373f	1	0	\\x000000010000000000800003a71717ba278485b9b60fd1af9619c02be5d462d747b3c6e0b0717a902bf79cd1019ea74f4d70eca548b87e43c58a1e76ec65d0ee471ed3274f2d70ed2927938b014315f6d7eb8efb481247414c4f01228061ee456144760a0935e5bbc5c1228788c577231a6001cf6c0d8204529892338258aab7f67634c2156530df14314a25010001	\\xb57a3337b7c3aab528689e4f7045398f28b09091aff492c4368f974158f98537412ade4155cc748daabaaad202b554fa03bc4cbfee06fe1f71eb4782f610cc03	1687678669000000	1688283469000000	1751355469000000	1845963469000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
232	\\x196ec6925734305bed317d36b1d96bc6685831e44d1592eef5179358d41da9f865f8da0905ee2d03200f37c99354f6b2e472d726d5dbcb2e00d55303edbba8f4	1	0	\\x000000010000000000800003eb9ed7ca5c4c9505d9f4724b81d7672c7016652fc37552548405c9374b1b285d91f70860a5baada5dd470a3b5763540d54003160d66ba97d4ae325a1949b536827a3ff67e0bcbcf28a85f89ab12b9c2d95894f9cda3a29c1bc5bb487856825d81109bf954fc4857cdd9a86b7dae54666a85fdd8d5d33e55355c65deba54d2c35010001	\\x7eae35a9fa001797bbace382db5ec320ef8297d0a14244d50a2ae5e04dd510ba36a44c861d67660cf5ae52f0bf8f7ef4f03ddb76e42a08a8b3ba193fb8c6ff0d	1669543669000000	1670148469000000	1733220469000000	1827828469000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
233	\\x1c167bd6f6347100dd55bc3d7457d38f3614b158984d0ddc655bf051e79f966318682e58a5373b54a8d3cf6d870cf2e190cebbe57d7870bb18221c4a3a59c6ca	1	0	\\x000000010000000000800003ba05ea5a8cb007debe47d3b6c41b865bb0518062810727237200724c48eae40908e48d35cbd8071cf15c76d40cd3b1b81460e0a7380a39449979df7e5cf160da307130115cbcf5127b13ca2ac348bcc6143d49798f9af903e5da9601f67a96898f50e1a8e67b0676d4593b5a96414d3c88d5594defb58f18be3768e225a11f31010001	\\x0938c04cc9aac896f44fff13f677d10fd611cccb576e37f16838ecb60d0f6f770ce053780b4a0c912e9bf511ba6a56e6ce028f4277147c617f1fdb8349a9ae01	1664103169000000	1664707969000000	1727779969000000	1822387969000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
234	\\x1f4659cb6651bedeae9a7bb47080a1362298a188ae2c16bb990a3de41d225a3fec752135f5840d388a8963e43e58a0d111a2649a8c32b604abd2362f284c82ee	1	0	\\x000000010000000000800003c313995b995e4bae9413c85a86e3e1714e5407ad770380f13a40be24e9d7a8dd4fcd54c6bc11422a428f7daeafcaf673ede5ea4e1d1bb81aa6abc384439751089a2f5cd85638575f35e5fcc7c79ae99a4bf08fa7890e2f475bff4b22e45ae48b513edf93802532752d7a6da4e8fde7966ad230fa483396d2e31889288e73f1d1010001	\\x2dc67ebfe5ee18a0fcd2a98d74471e693818fe2a27e95a2f287a4156d1fe3473d31f4be9fdc822da1adfa76fd290c4ea113702ff9265de426ea1c5d5d63f1b05	1665916669000000	1666521469000000	1729593469000000	1824201469000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
235	\\x209a12800a13d9e9485ef780a27d4117ade2a19c7aff0eddb28b17c405bb943ee081d82fe48c002c9d511d26de0234695dde11579adbbe9f2cabda53f392fee4	1	0	\\x000000010000000000800003c8c0281203813f6c1ccebafb61bb12b8b75b3680703920780bd200e48ea7f1fd7196b7bac2d9a7e1d66e8e0341f9ac532fdc5eb2c3ea6af3dbf6c5b2ef3bfe5845300b91c0950b04701c711de4d8a70fef6d1db9ad3972b3761dd7c056e58f39dba3d0d36cf79622378c4ba979e10c7ae9799db948bde49a9bdda0a499f26ddb010001	\\x3db9aedce6c742a60e52e25aaf12ebdf3fb4a4ccd71a25298d31c89fa1a28d41b54191fe19d4451969a310db87b6b8077100b4ad0d5810fc35d2a9409a3fa208	1675588669000000	1676193469000000	1739265469000000	1833873469000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
236	\\x2116028713ab3511acdade6e846d22a511652d4f53c63ba34cc98bf9c79008895116cbb26f45526f4de176183dd6bb89565723b005bb326f339b6076a9d04862	1	0	\\x000000010000000000800003a426602d1d8308715117986b6eb6687059a93d6df16f6f9b9736cd42098e3da9af357af3e7c303be9aa615cc1f009a92bdc6cd82441d0cfff24497aa957180448292548edea5dc44358ec256f353d3efff4203b4271498faf7da8211c6fd03e9a1bf923267be4f019ae3fdf251c52612d2d8de6cea19aa8f9d0ce974bb1321af010001	\\xff3c006b21075be7a971a5889fd03958a1014dee807be5cf76dd42291d35c0bd94e5abe95453e84d7ce7b84c964f23af9dacfc32ef742da88342f2a0fd4c2503	1683447169000000	1684051969000000	1747123969000000	1841731969000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
237	\\x22b2ea996a7dc2a0e0bdb9a4122ce02a3e57a2dcd2472072b8267cb8f2b29bff43de2b62ec829fde466467fde335ee8581ac15dda5aa3f07a5649e52e32155b6	1	0	\\x000000010000000000800003af5d1198b715eb9879ce8df3e6718a2eca5c18295539caea938f5f2b02392efff4815de48c9468fc786fcb7fcd83255933d50e098a7cef76e1152adbd4455ee28b3580a83d2cbac975debcfc8a864fcf77ccdd7c3e120e1aefae874e63f1c6c61044f2fce7e3bfb93a6265fa0e36f7ed11dbb8a1fe5fbc7a1f8cf950f0535ad3010001	\\xfc521de954cf589638081acb348c02379ea549dd34caac0f278bc28afae5999a04116ef627edd51a34218027987d8e1307934175a982cec3165687640eafac00	1681029169000000	1681633969000000	1744705969000000	1839313969000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
238	\\x26e61d7aba53b9d15d2aaeeb481d9ae5a0d19cec50351337bc1d15836ddc607d6737c3ec8a41be52bb519ee15513cb5df645fe6fe6f26962b1047c4b873c9cee	1	0	\\x000000010000000000800003ddacc971b128f54f774d494c9dd29119b2234aaf330aa74da6d994d85852db05189b1916baf16d2ed5cc5ad0b2496b2ebe512cfc44a1fddfcf4d470736299d3f81e3ff17aa9ea42715fd09173b019c4a5274654a0e1ce792b015d58345ff5ef778744c2348a7b2a11a00f8fba65d945ff2e504668b6dbce4d74340cb0e2cbf31010001	\\x2c52c36492f67cab4a3f7d2f87f5bcac890ee6d2e14d01e9402b4a6f2de4680f9360e943fa06a001331daee49d8b4cb26663c0fc6c18e86bb765e3fefe88fa01	1675588669000000	1676193469000000	1739265469000000	1833873469000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
239	\\x262244730ecc9ac92da6539e8600234254544b816a1dc528f9f380dd43f01099c3780b124b588751f15c18ed4860b4967b499fb3afcbe5728c11746a5042cf5c	1	0	\\x000000010000000000800003e26e8a585131d556d6ff62451e2b0380978866df54e10c689c1a4cd8eb2e88e5cd89e698f5f5d7fbdcc73a21c6a55e9f1948b3cd410545a53a03c770809a8eaed181c2779f22559ff1aa6868d9da8b293132e92f6964d00753373947a4b933066f18f8b9f2fb399886653646c118bbac619992f2f9eb99e71b701ea3f706d16b010001	\\x532ea6c322b123a8d2dc3eb1ed9da19ee36023b6342f17986197058ff169c92898d0c44c45cb1e8caa06c8402b20e85cb591141669140fee877a9cc75894b405	1673775169000000	1674379969000000	1737451969000000	1832059969000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
240	\\x2806bacf74d7a4a4818616d167f13ee9c01df21b5f8b3619d441ab65d0369489bf1038695205871d78334164fc9ace7b6b302f31e2d74d9754bf1eae0f5c1dff	1	0	\\x000000010000000000800003bc632ea47857d4e6e8bfa8574f612b3b98f8ee4fd5b1af839e536dc31d03381a05b60206397a1b1b78afde2d2fb43e738ba211c715141feff11da24a0e0449c59c073000b7cafee9b2be08fa1865a88799aa01566e08143d1adf64d20dcaca88f854a6f5f5ccd56bde71531b211ac25ecf5702e10220d1eeec2aadae33b7e0ff010001	\\x85369d84c59fbab6354885774d8a270038a0336ee3fd7bf5bf8d12a55ca7091350539b4a7e6b3a3f33b24a5f087632f3e9f03265d146d1e51d79df0c735ff800	1673170669000000	1673775469000000	1736847469000000	1831455469000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
241	\\x2aa6ae9129ab7f0b1d5493af9649fccd083b0022addca73b96b0e102551880d92277fc1a50c5f4d27fcb415f93ef8ce2cb9254f2f7f2dad061b5a78c1dc370ca	1	0	\\x000000010000000000800003bee62808ee9c4df742384c402335e0cb54e6673902907bcab06e0f252f1c4901de5e022de301ff5ea87f848eeaaa9add172a84ca74ca548366304e4c778804400f88d192930587836b5ab80b7436d21aee6b53c622da8ca046375a0e9de969b8fd013c71ca2347921cdc2f9549ed42eac22261b250e244af71700eb9349fe39d010001	\\xf2cb3d2d48e63209af6f1cf869e34ae5b88c537efb043c5f150abe4905466600bcf249e2c1add1419cb36342cc173dacac6f414c1fdcbdbe2dc12571786f6601	1676193169000000	1676797969000000	1739869969000000	1834477969000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
242	\\x32daadb53eddd0fb7c7e37d7ebb6b9693e04b6c419a7ad64123f1a842cb482bac52470f750ea4b39b0f6422aa0178911ab5a7541c556829ca4d683000e3763ea	1	0	\\x0000000100000000008000039eead60977cabe73427289e163cca30bb33d368e68f3da9bf042243c3978735d4f5b6d45f91f8829873ab70603b216a62c0afdc1d2a502b041bf0a14244cc51d82a337ea73dede0ba1424ca22a94896af1d8f660e91dbd30bc49801f77781028d63c5d2c8f7d2a4b395e3d7b2481af830dd5f41c31d28a1f73ff684a6c56744d010001	\\x2be1838bf95e3a8f9368a70b4edb69fee9304b8d2d9d9c39a6a95a9c26ab2250c71934d0e7a479a65c1d76746dbd2b39d30bcd7d9f537c53888422485087b60e	1663498669000000	1664103469000000	1727175469000000	1821783469000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
243	\\x33ee95772da8670298fb736a185a806273dae8eb2b70b7b0f292f70e10807a4565f901530334c930c1d8f52f8c965e7cc18b54202e22a224a2f25aa70e4998b9	1	0	\\x000000010000000000800003bcd22250887af46e4949d72d70834b6506357535ce3c381268be2e9831b31fe211612956ddf1cf9498779f3f6435f3d4b0331e155f173846b8a308ac9b7f153211cb1d0721ada712e9c77d7e9fde9e499aada6c7a3bf15ed3f28949443e5dd0807ba7df387c9087b57937e85357ecabd6c2772cafe889a89e0fa370fbb1e2423010001	\\xd7e1139fa151c6f0c4fa35cbff9f4567ce6bceaed21f713ad07292bfe89e3eeb01102203f419c4081ef62df0da63baa4b7581fdb6746cf9ac7766e369f4d0000	1671961669000000	1672566469000000	1735638469000000	1830246469000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
244	\\x33aa9fd17053e6bbeba4fcd4e672c1c0fa87f4a3222edaf58fa94732713acf651a5a619be386bacf0b99f1b5876dab221dd0d1af19e682f7c208c8e63629aea9	1	0	\\x00000001000000000080000396d8998428cc91bf1411fdb6d93575523ff521e4a3cad5f294b579e0980be6e87fda453b23781954f102fb7fc99a6386e3875caa2ee467f1a6447c775e960e737e2ca577d8083d5587a300aac985ec6a984612bd2893df8ed023b1e6fd441720daea37dffb4c51be64fb4cea020e8ea2cb31138f9d4084060a091a4c56b33c2b010001	\\x4c1ea10d62e3c212d44a7510d36d0ea4d09130e0e4ba6b48f24c3fbf5d360969ee8397fe01968107356a4d982a47c6d9feb4cf77a5bb91a6e4329551224b6e02	1669543669000000	1670148469000000	1733220469000000	1827828469000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
245	\\x350e2dc943cd50e065419d37d5e56268776b041ebb8ab5b203a4466acfca10d521be07f6bf18c18c05620054eb375f5289d5053802143ca0f4919fcabef17b61	1	0	\\x000000010000000000800003a029e46499cb5c7e538008ba89d9e7c7787bed3a3ec056bb4b1794d05b70f03bc997f8f8a14c4af67700a2a512a26032c8538167d613869bbb1f9343ac2114921891863e638f9e78ccc5497667def3dce16926238608f0796f58d31417917825adc4c77613e48e44d2afd05f30196573fc295ea1b22f80b8bb4c66150b504ca7010001	\\xdd20512829f9d2b2c7c978421d5c963bc141448232f5f88a916dd1164d9eb3673efc935ac91d5d9966b6ae280de338425805525f95699d8f15a1e5bf5733570a	1662289669000000	1662894469000000	1725966469000000	1820574469000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
246	\\x389adcebc62634376751c98bbd06461ffa623bcb72d911653a452e4d542acb8d8c04717c7b528d92195db855a8899c4faa0b605cb970f4374a9211266674ad2f	1	0	\\x000000010000000000800003c0a03862ee35c870c89044185ec07dcfdfb81ba14d06aa6806e8c62069a9127653d2fca22246811f900e380fbd4c67f538ac2350cc9f3027392f10095288cc95af90ebc42979e3e8950c6176ac91d1272090b9da149f31ea0b08a22df794c19616b5967bb756b9acc087532f9bcfbfd4e4f3a34529683bcc29f2bdade8dd8617010001	\\x634c7ea0a264d6271341dc311865162cba47c4656b42d11277ae3387bb9ebe146cc111a1a8b33e2ee8bc8b579e56ed732c1c31489d9ae4849cb72dae96110200	1682238169000000	1682842969000000	1745914969000000	1840522969000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
247	\\x3fd2ce62a94d2bc00b35ffb68e2b5b74f8d04135965364e129d7381145719406026a2f02b0c6da78cb4d2ff6ba8d9755d9efec3f55aaad77a2ce0fb6b8026d47	1	0	\\x000000010000000000800003e4639fbc96e9a7ad996eaa2fc6ca7663269002009eda30fe9a71be3630b20f595d496d0e6f5baa9d9f9d20f0b3b76c49246c7eaa29dfdf104dcc8cb520c2bd53732db88f902d672ea99bcda0ebe0536a999a7a686c501e3b24e7b19badda0d88e9d794aa4cf45d3534a412e10fa4cc79643817ca8739407df895a5bf7fa2ac5d010001	\\xba1533ad9771dac6113dcb03b797caf501392e80d06d911267c1f60e87d55f4ef7f144f8cc74f0dfc329c9d5b26718beeb862d46bd382e85b48ea30dbf37e000	1677402169000000	1678006969000000	1741078969000000	1835686969000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
248	\\x3f4ec8bc1637ce08414b9f5e0627a1eb66cb3f76ba7dd0775f8bbeda14b86a2866ba432c332c9165c7ae6c81ab4e3a503eed9123831551b19cd68436ccd4844a	1	0	\\x000000010000000000800003c4870398d7bf2d75f14b63eb2ce1876d5506a08b08f9f6d855605514ea0c26f5305686bfbd17e37eff77d8905277430b779ecc5d69d6b2141723185c6ff2bd863bceeac7a1f5daf9e92502eb9d111ecdecd63f7439a54f7e0cb9a0539511016502c4194393318f8ba9dd8b67001e03e15d0122a4fd9887f49a19bfb18811a3e7010001	\\x67f033c92b97383f6470d68ea7fc53f14eeb98e24703a3315a7a9365b40f71788f2fbd7e558a8e8546ebc762b9b2cb0df484e655e1ec898797e8036f4a2bcd06	1671961669000000	1672566469000000	1735638469000000	1830246469000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
249	\\x426a23e8a71a194ee27449e3801d3be95cb982a76448b37940b0d51340eb8c5e44e3950dde05fb6ea736015e0e032a5d369af2c1c984ea39836cbf42ab5f8ecc	1	0	\\x000000010000000000800003e7d0f808636ca4047fd7cd078b4faeb5766447087679ddc386b5b479c88cd73376f2a0fa8d2043594ba35721a7286ca67bb24565a7645e26308a1249f17e4af4cac698d8945e4f21cfc6a060ba013490cf37718e3db9b917b88ff79abb6868226c2f6438b9b072741d2230337835399d79003539854f67052cf1b54ce0842a05010001	\\x0a08b11ff33be6d068a150a4a575a3636d1fcfb948b697e1b64e62b106024365565bbfbdfb827ab9317965d5bb4ee0256b1fac5d0eed4689f9c9af3e969ae60e	1665916669000000	1666521469000000	1729593469000000	1824201469000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
250	\\x457a237c8cb98d95f181c19238ad43fd9a3fc7971995d2586c6645cd6cb50a0ebcb9477e9508cd16c93a61c06e0ab6182a86e3b59663075b8ed88ad1e71d50ad	1	0	\\x000000010000000000800003c771cca3ca63ef00ff3ece6ad331958fddfe62423e17f75b750e4a88b9b609b31ed252967e072ffe7ab4a5d24559e68825dc4c8b32cb25e5ba3d185db4851c90f5f946d6a1c8926558b7087e153c1504b2c6636362487e7267e3afda64120251e46576b7d05735e3bb28ff0feb2a1aa62a525915701076a5f66a8d53e5db8dd5010001	\\x03d7f403944e29ffb8779fe5b5e439af589d27c126439f0b5f9d7d4cf884a73ae456813693e75e43264663beeb9dfb68d476447369fa177626fc6bddfa4ad507	1674984169000000	1675588969000000	1738660969000000	1833268969000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
251	\\x456246b51623f3c7ab68e873adb5860de79af1a6044a05e62e29f50e77bba4fcf6dea2996ff52954681e3b7546dac7c5a3a6ed162af7ec8a974020c6494a83fe	1	0	\\x000000010000000000800003e158aaf3c96fa38d0657411f227a24ab7e7151a232f58881dba7053d666192cceb43848eb66fd0ce2975566b26a413c6204d22a93de51665fc6512e28b93019de927241cfbf4eb9fe09c9d7c1abf6c783e488dca066b373d0ecc8737b42955cb75b9c2118b1dc2bf4f3b3d9c81408b055980b70caf4997f941fc1cbc24391cd7010001	\\xc33bf227d863edba3f39bea8432b8066c2ed60de736d216fe7de9d3947c15dc8e684eac9b074dd5ebba8f926c370ab651917fe86b7a3527e07b50dea06ab5507	1678611169000000	1679215969000000	1742287969000000	1836895969000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
252	\\x4726f777f90e42c763b67ec4e7c97053598b587572901f54558a2e57f5c25b109144eb4f07ec7a43d09680fd0f5f81d1ffdb2207d5f6eae70fb6ce0c231b121b	1	0	\\x000000010000000000800003db598b5796c2e7a58a2b4020c704cf136591cf31a600ed784e69e51d60840f93f132a80f3ccef7fc1d101959328bbfc9e2192cb99bcc3317a7ea631067017226a69e5702edc2366ec548baf3241612097b469e32a7b709ffb7349b558edb0ec45f7c26b8b730c3eb6078bfe6e5a48a43f7450686658c3a1921fe8e2a5d9c7dcb010001	\\xe9ff55c567abfadbc323cb88e40c36acb98b38c4c5d67a889179a93d5afd65cc7ee03555e1a69020c9c865f782c58e11520ab0c620faefe832f0aec79d9cf703	1661080669000000	1661685469000000	1724757469000000	1819365469000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
253	\\x49ba16ffef5ce843eeb530ad92bbcddd64fdf58392a85f2c1c253854eb5a2e69a515e003c79065f37fc7fb6d980a805fd1207770d13aa7d7f20ad09fb4709507	1	0	\\x000000010000000000800003da8a625b2356cf775471004ed070c58ce8747bdd2fd59ae541ac19e1f536413a4d6f86617bbae45980006bf6b9070cc95b5c4a899702c75ea908d7eb171ab0be901dfc15f6708a7301513af4247400bdeda1e5a74f4361a3a2ef254be20a177d9defc70abb9872ed9c2d2161b7f96ede4a3fd85d69c673366b3c471378b55b43010001	\\xda768b69fd4e60aa8739ab891204999d70dc734889c08ab0a5871ab52f2f1282ec81587a1d8859313e45e1378ea04e37b78a1b1b665b2cd06986afeecd740509	1674984169000000	1675588969000000	1738660969000000	1833268969000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
254	\\x496623a4f3400b4d01a8f006ace752b056a38b93c549ad78945a75180825265ab1d5d4f9c39ff509227eee997cacf70d2aeb4c0c36ba3b1c3cebd54c9b71787d	1	0	\\x000000010000000000800003db1d85cbc8db6a4b78c0c5ce96fd4b5619fee4516b316132d7bf4ef10ad0fa1fbdb8fe49573747a89fe59217d2258cbf58c4387050ea82cace61e19790c1f32af796313f1d1010c9750a0941268f14225583372f5ba8dfdd7156ba5a4431dbfb9f0b40411ef65c9b12080d0585cbed6115bd128cf67c69c13994d400236ece73010001	\\x871e3fd50a3de8a32718ff3f1a17ca4e0bd01f80a99668ec90b37dd3a8561c3c4ff41ce52d128d4fcc5811a015d2ee502086206cc032cd3c1d808c7654a88707	1681029169000000	1681633969000000	1744705969000000	1839313969000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
255	\\x4d2ea6762e776528ef627ea570131cb6e7e7c2d606b0c22a1aec3269e4e76298fd6dbd2d72f3af5944f2c84cb8baedafdf0a4f04dbdd77de177ca2b5f46b8980	1	0	\\x000000010000000000800003ce258b82f342b824e0a50eeae41e05e1109264ac65034f4d5155ac7243b60063ba6026d368c5abc078721b5ac1e409f6e638842add33769a804cf2d7493181ec01da9516e7c19403a362c0773ec4ae359ff1ecbe85216225608b5d4601a0e67c8122c7b0b5d3e80d7ff3467295b5fa1b1485e2f07827bade2b931864ea782d5f010001	\\xbea7b4bb3bdcf2dc1ceb8b3dfc7a73c97d47481428cfa29e6ca250db930e42c6262af14de7cdf04f0cc920855f58b59d17316d738eb1e546208ec4da61aaf700	1685260669000000	1685865469000000	1748937469000000	1843545469000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
256	\\x4eb61cb168a6948b0f25529ed31cb624dbdac414ef8e10d5bfd0a170a64cdaf988852ffbb530e3ce5b381241a258a561d73e6708b2b957d2306a74ff84e4d6b1	1	0	\\x000000010000000000800003b5a4c2cb7c588bb363b5c1a9159ec9471db355abece70f250c67107aaf67a412be1d69569230b20acbdea47fec499d9a55ff93355a1fdb7ebb1320dd0e722e6aa73792973d7f779b928fb6d26910225679e282c1813ed93b4c7debfe7f3fa9cadc44d327b96187817c56a953009998ff677ae121339942f5637f2f0c13870259010001	\\x64c4e4764ed69c672cd4e14e230084630152532a73f337aa506f9c29ef4cccaeacb4613fb448ab9deb5107ad5b61397f5010ca821b917bdc5d430f89c3428604	1682238169000000	1682842969000000	1745914969000000	1840522969000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
257	\\x51de1f25fc2e8576397572b4966be56b9166e991bbd578e76fb084a6e8bc76a9b7bc054f81ad04281e9876f3324f9c07724a8b8d3a490d880eb762d2a44caddc	1	0	\\x000000010000000000800003acff877ca90af33e11ff3c89571bde9ea4840cebe7f1fb5ae4fc0026239b9d826fd9431b528211b94ac47ee001d92faed283feb121493d5b330f3d349a89f95f0f343b8a72a31386b59683023dc01faa04a5d1c70aa41ae1bc6cf54fdf3e3597ecd3f644a2709a7d81f003e3e2fe153ba27af9c02586567f7994d9e4e3a344a7010001	\\x836225283a32b72079ec699d8d3e013191634bed65dcad1beb117bb63babe64bdbe774b47a4f9cafbe659e5f87d52122245de91bc0e5c332b0e9ab51d5269600	1672566169000000	1673170969000000	1736242969000000	1830850969000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
258	\\x52eefc8cefdc7c99083a8d3c1b692b49985dd995f09dbc0ed284375633c8e9ca69a90eb346b3f98f0532bab9079d073ba6e3236e1945db480e4a9ce5188a09fe	1	0	\\x000000010000000000800003c5efd89c940306ceaf3b6de3d87954a012075ba02551ad886d047137162804db8a6c8e652182eec293be8d4df3ceb51179bbd65d9ed1a924767f7181966aaa8ab542afd2eb2df369cf4016f2e9c82b31cfb2e32837c346a91521f769c10d32ae1e2b7bdedc208a4e04a6dc41030c341dcb0f5252cd6c2b20998ff92e85445443010001	\\x271b5beb8dc0e6f62c8c862689b0db8344f5671fcdb7927a724f5ab8692223beebeea532205471686785aada6d81cc1f62d00417f87175e58458271ebe19680d	1675588669000000	1676193469000000	1739265469000000	1833873469000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
259	\\x523e5c3457f887b6244e846ca69e2ee2c5c225e3c59486bbdbd395ff60c6b74f0f99ed18d8c9e16acc92cc23cc6145309677a1aac1fce9f56bb06d5f40095e4f	1	0	\\x000000010000000000800003d0f4118920c5dacc6b9843e01fe20eeb20ed9d142413c7befdf3d67a23e97e0562a0ec4de74c79172531cc12d7b60c27c63576848497d46c3ab5833e23f78b336410c8a1411e09def8197bf12f04e45b35098b2dc36dd8ca2116128d816c16a634e320d93ea7aa62777435281e4eb6bcc4262fe30f5e8031ab9cc033217acd91010001	\\x67532c722c4d0e59ce3f6448d5fdddbdeab18c49935086e3dd3dec876ba8c3dc7275a9ed95bbb29399fec38ff1bb9f86b2e85792f4d8c96802857cce720d4d02	1659871669000000	1660476469000000	1723548469000000	1818156469000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
260	\\x55e6cbd566c6a66ac52ad2e91319cda24624b5555915074b57211e5d1047f61c03534d58ce0c2905f4a36ee24460ce868ed8d36abec46173374ac9a0b399bd2d	1	0	\\x000000010000000000800003bd0313c97f6e79354f62310e8e18e4669ba2c57ff1a8420168a9d9d7ff9cb66e3bbe3aca4053c51770e198cf96f93a42e3ba4228f3edcb3b704e6ace45137439935515999cea9d5d288e9fb6cc59548215be62ff0930b02683c2c8f9db1fd82a6794407005257c22b81d4f717f91760b0aaffc0653df38fa3699c2e7ff487783010001	\\xc6859cf7c10206fa07b044e63045fee67e23b6d16dab428b7840c6ba84c6610ecfbfc4ea5d5dc1cdeaaf70c15c74a3d91f78761181c77239fa1244ec2ca8330f	1688887669000000	1689492469000000	1752564469000000	1847172469000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
261	\\x5696718db64159a43c55da2eadfbcd5b6c6d5fc7947cc4a66f6f5dd56b97dda561b80cac7fccd74687f7acd8328fe19faac84a5dfb318d410db4c654fa4020ae	1	0	\\x0000000100000000008000039969453c7818e6c33f6c07dcebc458b9645ccfd918b3348516b74164725366e3f02925dee793ba8728ed18765fbd8ea52e9ba9a3c56a3769470313ce558060ff00fdcb39fadc8f9eb9ec9014a9cf85a80fe675fee08fc33429c6eb0d2721b65c8c9299a71afc4ae24767f1682b71f6e4ec9eae8810974ee69138a5db411c3e09010001	\\x7fb8ce757775bbbcd54babec43276a21447ecf7bf030ebad78a74437f38fb9c4ecbbd96447737427806c0d77ac18d25192071bf5eefe2e8e073ac2387a35d805	1681029169000000	1681633969000000	1744705969000000	1839313969000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
262	\\x5dc231effcb5c71e61f5a839ef95d15ccc6efbb289a718a1499aba38ed13e42f6fec90918848daafd83c408ece76cd50576e960b035668228e54bc847be5ef79	1	0	\\x000000010000000000800003c63b7f479d004330abd20c65a6b52b1b6821c5dfd02695cc211c04b2f390cdd33dc387b5e57184bffd9ea94ad7f07091feb2e4ab564d80539c1f03efd51fadcfb25b52a762ba26c8abd9dd0ffdcdd7ad521ef67ddb400de7b3661844a91462ad51b88f957b904b405006ebee98f934016f6eb3ee49f7cc008c3dfc3dd2204063010001	\\x6730dc85f11fd5ddf35ef2e3476e38f0f405a65dff9734b32f4f88dab5cdf516fa714c92bdba5bada0b21dd4b5e752bc9c6381804e3cac9f660a71292b73df08	1668334669000000	1668939469000000	1732011469000000	1826619469000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
263	\\x5ea684958513bcca235846ba84089a59803548df72c4e495e7ad4796bd3c8076721a4d6726cf1093db6c781f7d80c0798eb39e07c57393ea747ec28657a2bb1f	1	0	\\x000000010000000000800003e9e8966afb3616906e896ac00d30724478de5f666d579618d3bd0a00666e490cd6de5f42941f6d5c53319194b2964d3d9a968d3540796a06c9a50e60ff362b2324dd2bd2d1e8485281a2bdfccdcbbad532a7499dfb1a47e411fa40b190ecbee10504718592d2fa44dfdf0f823b9a5ecf59596f7db250c42a7916c3822c0b477f010001	\\xca2cbad5ca168868a4f03a81117c738be5bca4ab6165edbc8c7988d91ecb56fe65ae2ba6a8205290e87d107cf7fadfc557a3262d5ece051fa258f938f504040e	1662894169000000	1663498969000000	1726570969000000	1821178969000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
264	\\x60c670a1b7229e0ac46070c42aa31d9773f0af1f1fb3a9630e260c94e7dca116d27d20108ae57779be86498536b21e2819c56ea727529cb71c007de9c258828b	1	0	\\x000000010000000000800003cd62a785331f33a3682cb0c5c72def663e96dba52217e5de5957112e1b471e40dcd22915eb2eda8d4f93f2629d0fe265a5fae5bc9e442f0533e0969232f781cd19408ac2394afeb23d1c7b3c42829bd29a5e99d90e3366cd488fd16599ad5d5bb7c4082bb72be5c59037c217e10f3e98ff1bff31743ef148d980079fef9a6bd5010001	\\x39923912bd85513d46a44993e43ae8db4ec9cb0de72f243826eda0626cb7cdbf62121a92b39a744cdff8e0328204354a12ffaac1b6d70e6908b0d7b81275da0f	1690096669000000	1690701469000000	1753773469000000	1848381469000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
265	\\x615aa9380b1471770f503019df9478475bae7d315f484a6539dbdc5ab28fcbf85203e38ee7628bcf0424374dacb13beef17a14bfa64d04696a24a3291aba5663	1	0	\\x000000010000000000800003ce19a9799991aa4db104a63ff530f5c57c36bf968dfd0c2f94331eb5d82b6a52db2246bbe33bca8247596fc3ea7afedb46926f3febc69397507cf5fcbaea4f5fa13852d5a1dabfd115ef1f8c64bc499355516ddbee30149e240495c89b7d3261086f737c70f089b10384573b695f1438fd247ee9d182f5d1c3b7874cde024bb7010001	\\x309375ac1b86a066f3416bcd30e5d289eab85caa1c2faecd4994900a70ac278a272d4676091eb5157404fc9355cc2ca6f2eed4dd9bcb1145444b1414350e170a	1668334669000000	1668939469000000	1732011469000000	1826619469000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
266	\\x6432f4bc1a37503950aa87417bedb1e405a745b60455365ec124ff7eb5e9deeccdffa6b3de02a208a9e3b417ba802a19ff52e116e5209742ebf015e93a951f54	1	0	\\x000000010000000000800003d88948a9ed5d27a699ee77cbd77d8dce6183060ea8d72577506a34604865d8112c39969d20484e65caae47f038120f740cb3e7a47a49105ab88e07b55804f6d7d1b1fa210aa793b261baaf92ceebcc4d803e87402ce03af0296199904dc1c6ebec0093c812126675e7007bf953d2a94c0ff3164e10d7f0d6633351e43468de07010001	\\xc16a1ed91663efa74c9a63944256d731eec1849c561ea211f2f8be80de16de0522c8a72ac353bb34b110634099b3264a900b5ad73d64754fcb1a994329a92e0b	1684051669000000	1684656469000000	1747728469000000	1842336469000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
267	\\x6502cd1e80c623fd45fc68e8f1e0523faf89f00f785b065a451c064192bda1f5833fd42549a8e542d017b54387094ef0b16edfc3f7ede24ae1401871c8cd223c	1	0	\\x000000010000000000800003bfc80c285854ab96604d86652ea109e2473f6e755b4dcd4863c7fcf039e6e16e6d5752de91fa92a27beaaa133b4999e11649823138e02b3d8550969256886a3e934874b24cb3154fd4d81e0097f0dc472a2f5eb85b5ea816ce458f40e9bc9caacc8843db188d2b9f635211a27abd1cc06684d5a2245f71f868544af6cf79ba39010001	\\xbe7ce664beed3c2d8e802463a5b033ea48f982335e235b7ed409ee9bc92c38d2eef8c211b2997afbc5859bb264ebb60785ac6eefe819a1e042b2f32808d4ed08	1682238169000000	1682842969000000	1745914969000000	1840522969000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
268	\\x6926e767c6bfb983abbb272708431a50aee09dc0990f597fb5605c549e6cb459c3fb6ac6bf451144dd66b07e0cf3216ba2e4475f62dfd3808fec1e1496e46cab	1	0	\\x000000010000000000800003b5dfb9207c400d93a5a3981e187eae731130848a9543d9e8b11b0fda162a82521b328f18868e600b1cf194aefffec23a1914e19d2a49c92d1cc4fe12a95340ad1dbcfaf53912c21d8101d276b2590126613be320344edc0053dd1f44d9f06e2cdf5c87d7d83cfe11c080605ede8d6ccf63ce2ab23a37d8dadec40d47a4de1f19010001	\\x0573b68747279cf10dc0b0fe397ed546ee690104f7e8498f9afe98a44da9b2a5f254e54b70b2c06458aa2a6367dc89bb2f9f9729024af7785341958a05adae0e	1664707669000000	1665312469000000	1728384469000000	1822992469000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
269	\\x6aeefb0006d79749a554cb91886333ffd2feb30a84ec40320440dc6b2475d4436672e8354bcebb3c4e88aad3e6efa89e80b68fed78ea0121b1d8f0c66a59fda9	1	0	\\x000000010000000000800003acd78a446f8c1aab8c6e3fb1b519dc642e4423535eb9b830bcddce5dabe033b3f84779f8010c9801807f30781b814bdf9b4cf91da7df557547ba5f8256c7c184b418620389a12c99865a7e1ae65b5ae10a82937ec8ade032dfece1d6139c67a6c51d53e8fc4db0cf668722045cd93a7f01939e844e3b6c2b84f9a1ced44d1a9b010001	\\x063580b28eba25368594d94ca33a133e16b9a7b8d174d377cea5d3c9ecd18adfb2a810e5cfeabf80818836af1d68bf643be0eec87e9a13267c735c2b9ba59809	1676797669000000	1677402469000000	1740474469000000	1835082469000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
270	\\x6b1a75eb3c52acba32518d2f6c42db170b4cfa9415ca3aec0ea1e5e4dc5b67067ecc330f6b52595784b2c2f063ced901074ebfdb48dcc16be9b5077df812283c	1	0	\\x000000010000000000800003c1969181b8ea030752e4a5157aee0c54138583fed9732b0cedbec83ec6605a9aebc7b73b14e019f6f0d861815d1b88193789746b79fd8fab0c3f54fa87e3c9f2d37340a19e07cf498e16d714c2711bbce4cdb5c075970dafbe831a012039b98a44fe451e67c28382c5c5e00533716b8b9f4cf6439a5338f80e58d74cebdb8c05010001	\\x811f90391709f195d9bc053a9bcfca829d7541a50f3cddad344f26d90fc7172968ef4e58930732b6000b17b8f60bb89ac6d65a5f9f0da6f24484dedb799c250b	1673170669000000	1673775469000000	1736847469000000	1831455469000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
271	\\x6d62e3b0a1c4f1eea24e17629ed9490d17a25bedde6f4bd3853a3a39cd2c77d33d9a19b99c279e0a80a6ee174907c36c7d4addcc84dcdf3976da4ffe3c89d9de	1	0	\\x000000010000000000800003e2ea128035f5c9e686b7d5086b205f23a5b11317553442b7aa61d8d9a09968546899b002a4143b4281e60c6b0a15fef4007f25e2ad8290c646b31b155d347db63f6a800c59c746bfa16b47ca32426a95e09c2c7d05529b9a59e1b905e676777b158f56ed2b6efc9121a121e83a35b30a1b88bd8cbd2dcd7b4c141aa77bbd4081010001	\\xa1d453e03beb8919ff46a80871c0ac036e2094377f86f4b3d42b9bd2390029e7f95b29fc1f0ac6fc893fce4d7381ec9f622b37cdb8b4146195843fb3ec1b8f02	1664103169000000	1664707969000000	1727779969000000	1822387969000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
272	\\x77f6962a786a6a7105859e93cde52a7beaf85e88cd04a869f8cb6d48e0ed15606206d009eac04d570e31be62c052f4f68b15c43168bf9db43e1e7faf4dce1b3f	1	0	\\x000000010000000000800003d9bf9a5fd157930a53f2b2f51218bded5ac12f232386a596d118fd940adbd7bcf2a77a5db050f47100c2e69699b8ff10f4ecfbdec323a4a8debfd30d845e681ffe45404235729a2c4aaaed8199e9fd4a634b53cf67950d6bf8094ce910a1e7fe7d41f563154bce54600494ddef5f79a0e7f016905401599cc92050a3024efc95010001	\\x2ee708f0bd5af0fcc201b04d58a20dbc77409e17b3f780c583b7d1403f05b9e4f18136bb582f7b7d4cc7dec2c8ab6dababc54f3b1cb845a4f862ea1f5abe8d0a	1678611169000000	1679215969000000	1742287969000000	1836895969000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
273	\\x770e08a1e021d0517db0da3bce6d364ca1f7861776943ff046a4ce0eea0d701e133cac6a79883d4160564dd524840d110a2938dcbbf962f93bf929fc65021bb8	1	0	\\x000000010000000000800003d0cf4f683414e7a0cfb951ccb7ac5b6656229a0df713647bcc43214bf73d62668ddbef5ca14052e718a02899388bd2f584000ba79b74631ed28b2e5c805ed5676fb4ad926c4d6aab8e25b8405ab642069bc2b62b8cf435b2c6e1d11bb3fca8b7d2fa741f86c9b0d5539da9ed99a7c518a6fedaed3bbead3b941d0b6a13feedcb010001	\\x9de3ace63d06e542021074284e3c14f07fc5f8d6d0a39afaba89122e0221eed1f740929542ae1024415d03d3586ec61e3ea290409d375b2c2e95e0d4dddc0604	1684051669000000	1684656469000000	1747728469000000	1842336469000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
274	\\x7bf67551429125d75373fd132ec63fe0ab6817c5234ecf75da7fb8af650b5f439b3c04ea09e9de1353a4c0cdcedaefeeeb8146b32dd3013f5112c7fe0a98e0c8	1	0	\\x000000010000000000800003e0c2e5d4ef2c0c104f7a7a67c43d97884571ea43c852f166148286e10542a998d946046de8708abf16d82cedd3c65c9b11a3e8909b00598f93d6b33a9e44639bc1b3185d188fb11748b01326d04e9c6e1743fd843640d408698320ef495e88fd573c51bbdab54a69341c194831771c0fe4f31c5234a66330f4739268a863622d010001	\\x2261e0978826438b0112d8d99e4b20f36c45bca6c492f8443b0d0234f4bfec08de0872746298a2573c62d68bbfe1aba8fc095e393c0ae2a05e9979f361a74d00	1687678669000000	1688283469000000	1751355469000000	1845963469000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
275	\\x7b2e4be8f6f49eb2234288db4242ee8b482bad3b631d433aa693bbcd71dc4ed3683f7d6bf0b50e0dc09867b1456d0dea33b989ca6cd93440a3a92a78250d7727	1	0	\\x000000010000000000800003b58b5a8a7ba27e17508a05188a632ed8a1112cc7f31252ba1bdbbfc24229dc2c9d55edef71284b7e942a927df96e79781d74499a300da8c3c6bb36449cae48fd5ca90c3c1a9b4df5e190079a4e4bd728194880c55b93889e3d624922c65f5ae8b5b804535b0509647d7c479eb7802ed85734fe938e1f4c061f82447a8f3886e1010001	\\xc9072d95da124a0551ca5331e002f61366bf06600360e215863f09cabf121a1561600c5a4de013ba51d3be1387ebef4e6927ba31cb7f92eacc7447d47f032b08	1668939169000000	1669543969000000	1732615969000000	1827223969000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
276	\\x80728f0b6df6fb8191d1883d7dac1867ee011227c2393ef5f9f14df7e59362bb02e1e0efd28bb17822cebdc035735c333b36c17d7d10a095b73c69f8585bbca8	1	0	\\x000000010000000000800003d37f58ce429ce711470b85c74e405f82d6fdfae234fc172093f3a59b8905c2cb731f5b451671f8989301e1621143729cfa3d16a4381de2366e9bdd7b24fc214cdb4b5bbaa5e7fef4112a6f8c1126ee6cbf383ac11d79d893826cd6c912dff99ecc6cacfe3bdeee82774c92c4e0e4d14d7ae4c0108db9de5241a1868f8709122b010001	\\xf61d1ab9314ce4583c891909f48b5dab56458888c069a70eeb413d0753af936c00cee7f312e3de3927e339378b39865f8e4b8fbecc902a5277c1a26de8706e03	1665916669000000	1666521469000000	1729593469000000	1824201469000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
277	\\x804a95f709fc2e7cf0fdc2c9d5cbcd5cc8616772690b85f37ed4249541d7471979f7248fa0092c03534164869ab957978b948a6fa0578bce2064c01e5b5951d0	1	0	\\x000000010000000000800003a92f33b55c5f9c4ecc603cc3ca02beb9d18d9842bfb95fb0aa81f71712019e7a6a28eebc28fbe4fb1c9472b070941b205f415a6c34d91bd0c43248fa0d15bbc680db71ee7a00cb4449c436b0532a4110fab48a9a56eb4df4900e1989a88c9ede599de2889df57439ed9eb855718d6ee02d02a11d45fd71a74144c25c479f873d010001	\\x461658edddc52d1f9107b2a4fc8e83829ed1932cad7314bb459c47a432f79e79c62ba89ed52b17ede34fc79fb0c7df9f6ba3057c4fa06dc1b2adc1db1054a60d	1665312169000000	1665916969000000	1728988969000000	1823596969000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
278	\\x8a6609b1bd130fe7916e44755d5de40a9d837092263f251a9f7cf7751b2739208ec54a6b4245e35ffc4a09785a64245d41f3231597ed24969cac66853ff0c608	1	0	\\x000000010000000000800003c14d40f2a69e736371ac2e5202af9279218fc0c0996f8e9e1033e52c14b9569d580c1c9249734284f462e24f82e85875938663a972a28827264336471636d5ad5360fd119e6bcba75e567eb8aa25525b93ec96a5ec178b8d7d761fd5b1c3b6173e282f80d32645e2e7b3e044fa2a64adb4eac8a62220ef70dd73c2a994c25827010001	\\x760fc79cc70a0ad1f45e618b1fca4f006d8750a2902f35a719d8d38a8593aa6f7244b3b923b308b58aa182d2e591fec2b5fc037da5c879ed1abbe8a8de1cb008	1690701169000000	1691305969000000	1754377969000000	1848985969000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
279	\\x8e7eaf2a2035b614f040a1085290fd89f89d52eb2a206ece0c0d212674af4ecac6f91b822f9bf03bd803829e38230cd9c6e1fac272f53d65d460c65db8572ed9	1	0	\\x000000010000000000800003b33dd3fab1ee0a89b239cf25ccefc875efbae1c693b5de3f51196e4f23f3a3f51d6cd70611ebcf01e84cc70c90642ba98d47678abd4be7e5becaa9660caed7e94d6dddfc0b30a89a00774b1f0e268023724b98949c45f45d673c3d6517ace5302195ab1bd6bdaa159e5a19dc3d3149413d8294a0c5fe613c9e7b4f7d7069a66b010001	\\x39977fab0d499ab9b0135aeefe369f56c9074b66dd5e50219b9d44c2dc524877745661369f2f7b52f941b9642879b9198a580a36aefb3d12f0295370faae3b03	1664103169000000	1664707969000000	1727779969000000	1822387969000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
280	\\x8e360c1da6139dcec17c8eddc2fc5b0416889e78756f33a9302aa9453617f2bf013f6614e11aaa0608021bffaec3a0bb212026aaf7b8edab84f0f855ce0da557	1	0	\\x000000010000000000800003bf4bb6d3c2ad31a0fe2a1cb1ad9bb7dbfe645347c4dbe31bde26fc2454c56bd9fd0611d0666792425ed3f322d60f158a5571b33ab6ec246bbb55ebcf8de8891e38a4bd67a7434d21a7677a11b6e8df146b5d911c751d397e7b55dcc0b4e429fa4db674b1d58db86ab5ce64a0ce560a5de0bb643b13ec9c55d8c83077d384ca01010001	\\x0bad794422bf529dcc18f37dd84a7241663a4c79fcc7b1c87d1f22ae03f68d48ca6042ab0f89a34c93c487cb915d0933140f6873f45ac9f740980984d0827907	1682238169000000	1682842969000000	1745914969000000	1840522969000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
281	\\x9002a99f727a20bf5c0b93fbfc821a6209198b0a3af916a79415513d8849929284b758c3f910411955a1dd1d16a3728d38e3ffa13548a04e9aeb6e4846216d39	1	0	\\x000000010000000000800003cec1a321a23f6899eed8a6f97bd771de2a77a4ce873a47fcf4a7c7ce90034f87959ce965a899f1f29b0fd02ca8f42907726beb61f7fb05d77bae9290c0cd992e9e5fd9c9fadd90c87b7a45d57dabf4799e66ac7cf1586459f9e2a30fa59df4f2ab62510cd270f542efdfd34b744735cf371a890e6df6336b128a3a85a5c76f79010001	\\xd81c6639f33c615ebcd46581ef9ed6ed2ffdee17d8c0770878e0f73f2ff7debbc5af302c4c9a7ab42557562fcedd075849daf21db3c33583cae2db9ed8d5540d	1676797669000000	1677402469000000	1740474469000000	1835082469000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
282	\\x9196dc63c577204b06b7ceab23f644386ec1aeecbfd38bfdf75bd2aa666dc61468349d49486dc7a96db6af04c2bd65bd3192dd993c8452a175d6096985b1f49b	1	0	\\x000000010000000000800003d8aaa525d331b0d6c3fa45357409c4462f7443090d73acc434a24a57ef8569720455947535d41fc8e18218d4462fd49bc17f2f6f14cfad6e5e95bce16d97b0483704af21dd7b01f296fb96eff4ffa2b707191dce57739140b6422011864be8589bcf11247ebbcc51cb7df1adf3fe330418d4afe12bfb14154156ebb4301a8109010001	\\x50b476bb4e57c05bb8f1b60b1e9362fa23057428bfd7382d7cd7a18ea789da247589c189aa0f8d1671207690c1636b7b34b8564e3ae70ecdbe777167416b6b0e	1671357169000000	1671961969000000	1735033969000000	1829641969000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
283	\\x91a67fd3267f3e2b0420bb21ac1450fb27000cb88879fcd3aa0c57f42f86478e864b6fd17b559fec640842ac7c11f862a90701a21f50233523c5f454681c9031	1	0	\\x000000010000000000800003b7f51193add343926a09e26b250a4e5233974f14c710013ad82b931dddadd6c199ebd665e7b8897c3d714b88a3070d0988c481ee9fce10f9bdd3d2b83b7ac205fc2ab9010747bf556261dafcf6d1b455ed8f227fe824184aac77a4e3c7f116829dd6459c3aa6ad96fd9d5277f27c12f2f41c8a7814dd2959de7fcfa8b4132c39010001	\\x85844c27a4d82716de868cb7c7b7de61ab67e57b2915fdf417684c98c231a208ed72bafe3c3b5b14a6156993a05d240231c12e39fd426191f676295c2c022606	1660476169000000	1661080969000000	1724152969000000	1818760969000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
284	\\x9796584990a424e18d12c700a5d9aa43afcc1cc4d7fa07e7ae4cd58c26c789a7288fa2de677703288a05c3fd2cbcc7bdd0ec7ec3511e335a711e18eb3a68997b	1	0	\\x000000010000000000800003cc984a9bc07739ce4597b8abaf83cd6f9bd74a5a76883e36c13c039f9e9d116c6e4f918d9579f14dcb622b64ccffc9440e922719b6748e1c4af1928d821ce4bc16d14dddbabcf0413fb452bdc51ab79d004ce2ef209bcd0677893b2d414cb44dfe355405d320ff676c84f24bc810aaf572f4fc4105736c500ef6d5b5093ed99f010001	\\x93ade68f1fa10c881f557f603708377cd15420d00789aa3705ccaab0c8b3a7dad60cd9e67ef7ef77a0cdd6b0c226ef57c4b8d65d3c5b645d707ff96e19c5ec07	1674984169000000	1675588969000000	1738660969000000	1833268969000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
285	\\x979ea897cd74952e82d51703837cac7886830ba930ad08e96ead7027eb51656611e457839e85a6a6944c6255ac5e1348aa8bd482c9b0b77addef62235129abe3	1	0	\\x0000000100000000008000039f0856327564eb591825bca29cdcc5ed36bb9f007eccd2b485f340a23e8e9b7e884e8764cd38bca03255670d8dce469e2179b735b6661c9aa4e98310dca18ad87b8282b64a3543265af8998c84c5ca3bb37c799dc03030a2418c63aa32c9183ff1514e0a8cd4b3fbf3077b72868879cf38ef2f6cbd292b79b72fce831b1fad79010001	\\xfcd3752cce3bd30be183498f0fb7df98b7ca7e25844ecb50fea9460eafb0d7b2e678caf5823f01f64ca93a0a0386f382e2bc1eaaf0a0bec1f0670f05d9e74505	1663498669000000	1664103469000000	1727175469000000	1821783469000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
286	\\xa3f23082ed571e405a967556fc2780dc548c156c0b4ef30ccb3a33d7ee8b75452087ebeff6abb5553f3c6aa9d4dbf4f4a8f3f32623cb3d6bb5e88a7c927979ed	1	0	\\x000000010000000000800003d969e5ac4cdf3ee977945e922496bafb51c624ef151028ea811323f2dbae40c3e36b438d4634e91bfe2036900ed889bf7cc47dc075ba21409837f130481cdd9c084b572b65f14acc446baa059f5aa6221a06178b7fe1a0e3cf4e3b9e33d381fd35cd251f4c6f4b9586580cba299f64f38de6fb0e77b802ce9fdf5c1746565c27010001	\\xfe80bfce7afc212edb094203dbbd9b9ade8ef7c093f1d1e5d80a52c48ce214ce9bee65559b2a0f4d2cf1eb953ec2a22c69cfcdc43c62052c843bbd97aa74820c	1684051669000000	1684656469000000	1747728469000000	1842336469000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
287	\\xa5da19e616f630569574ffaaebabc8c39e0adec8d7159c6d5ba72bd6036f4c50ff7f38bac8e2dd740660003d2e234623b783285f48fa7f10c5102504933f7388	1	0	\\x000000010000000000800003e107913c074f0c336ec70ba0308408ac612c69e17abd7390d4401457fac51b33091dfba7e05056e484078b607bfeacf0cfbe959f12fa32d70eb3d0c90807a78e2bba683cfd8f431c1309a229d1cb91ce9109d4bc070a8d9ee4d4baf47e7ffaae57c22200d873e10cac223a81bf4b460e318312f14cea5ed4fe70b3486f440f53010001	\\x4c1ed95a22188d4e50654cddf411e640944cbc1b7c32677adb397164e0c92ceac2c95663d32b1cb6e25df74c46c24d312056da7568986d1791b0f2aa49291602	1664103169000000	1664707969000000	1727779969000000	1822387969000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
288	\\xa97e069af60fcf78009e9a5e025d0e4eb2afa7e637b469c55a676b75d12424df4e3f45d20c82a55694d82b832bd55f590483edc0b4e9c20544a73bff1fd6175b	1	0	\\x000000010000000000800003c43332379118009d381f499702a2da2bb0fb128dd623bf36f6aa50bfeacf611cc6c8b17131344343662a0c1e35f1d62300b3db94aa643a93b4fb92a7bce7a1005caf50b299530884f11d04b24d75d751626a02e1606520f8d654ee9457b05f176273040cc9bed6e0cc3bb1c260326550971a4692e85235894111b5f4f7e62fef010001	\\xb415acd8bb9cba6f00d698b943858287ae9ecc6ffb4b3686f63e84f5e968c0a826e1abc66f81e11c1e7fbab965f8fc2bcabcfc10220f3fa892c99b0c8dd6f40a	1665916669000000	1666521469000000	1729593469000000	1824201469000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
289	\\xae02f80dc0396985f8ecf803b582bbc53acd40395bb77007e4c482810f5d78dcbd2dd377016c515c901b535b7ef8b62f7d040c925b72aadb4a8e9aeabb094205	1	0	\\x000000010000000000800003c67d022b64d687b3384bc9a3ac9c3af31c3d86798d9f3929adb679fdfcbaed52de8899aefc90b841425f48c9787d50be817e8e55f9447746da539e78333c1899e0a2347350a15b5cd5d1b3e81345d0dbb8b2be38ef81a86c60432a918f2028661bfbc7e7705416efaadcadddd03b7ebdbf7e2c2918a86328f48f1f7c1e34f913010001	\\x0c1366f31732918d645de315b5a0729d3d7c09d6a0c4e89f7ae83298f4c0c5e11db5762d34c042dcdcefe8ee6c69a316cbc4a31eee3e9498e8eb439d11f79b0f	1682842669000000	1683447469000000	1746519469000000	1841127469000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
290	\\xae02633642dea8ee08944115ef93d6c5e5d78cd7e40f209e6b474a69c20687c579351dd45c3456b1674e79ca2bd6fac41699b203b6557417b0bde61a8e849af9	1	0	\\x000000010000000000800003e08eb659458e04155834ac112bd8c5cb1fd1d7498fca165d12ac3eed48468217493ec7e4768d443955b43303677271227d2ef57c969446b01e783381a2357b1bc8d85fb01888f0f0db0354425eabad1c9acfd09c548cbc1f8243526fb243ab3f216ef4af1108ed102b752a80f4cb79ce77307a05108e286d858116d7f61ef171010001	\\x03648460224d686148f8bca606eb827e1a0b12dad1a30b3a9ef686a355e6ce1c868946d7e348bc97154f1d5d0a5f4a38815b955820990ee26c1b65a40237b701	1682238169000000	1682842969000000	1745914969000000	1840522969000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
291	\\xb19a53bda5595d1780528d45de9972af2c972c27ccc5c1f09d6b51367d65dd67ec9af354d605a05e446c6250b62449def8e4c705351905ae327431f1c653aef7	1	0	\\x000000010000000000800003c52db1573522610cce92ca7ccfedd7c8ea5c6ad26acd802a945065802dc4a97871f04721c02c88514282df2f1dd07be3a272b01db5b842cf7f09e7f99514b40421dc4ee83397a1150a031cae6578d9d1dff0a6bb8423d4a94f4eb328f2a43297b7082f25ef0e8e634a0a6c3bf16acd4ee1e5438230be16333a71ab68f3e139e9010001	\\xac51a5e7e8547cf56fb7935640085ce1955f663cd3e831b14fabb915e894bdabca908cc61cfe63201dff1b8c84341ffcb52f59799a04b476dc731ccc47164c04	1662894169000000	1663498969000000	1726570969000000	1821178969000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
292	\\xb46aa13773cf80c01835e351f12583f87c2ef4122aad18851778c1981f83b965144128385424e71fd3f7ffee7308fc4ceba456d63ef466e636f30bf7a70811cf	1	0	\\x000000010000000000800003be2acae588a2505490bf996c8a14f061b294464eb6efb6e12079242b3d9e5f42c71b4e2833eba95f49b5acb2e3f35c8b7e93949b81f690729e81bba70ec65987e92bf707de75f5f1710ef5af52eba8390dfb29c610ef345888d688adf63d6c5d47032b2e1ee88700270935b19c75a7b4cedae24360a7e5c4ade911e05ae0b61d010001	\\x655a3354e2bf019b3df808c465d8577e4530da717b51e2706366f06e5e01331bb381de57b74b34eafc070529fab727e8ab6cf9fa6f87b23a361d286a99b00e07	1690096669000000	1690701469000000	1753773469000000	1848381469000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
293	\\xb4b2a5df2b44c72243310d2a87141529b63a2aec8153f9cf5db270e9de909cb4903d4dbe4aba315928f042a21d5df926eaa53cc750fb4bfda3281b42e2f904a0	1	0	\\x000000010000000000800003f1e64551569d87d2a66d8cdbf2976a78fa35548a9842194db52283a2e500a507738abf232741851c8c3383c1c46bbcb6275d94c6dadd0d67fc9c0d934c4c1ce41d46a4a96ceae34873d9a29049447e14ef72f61350b9475fbd3b30b877ff494e15a3c0114f01d8be3acc3d30391f0cd92dd9734b61581cb008a2fc245f944f55010001	\\xb8b8588d2a315e3989518a1947dcb55c489591729aff83c855b8b3e86a14ac052e0a8e300f5e97b2e267cb8c992d586f678d4d37fd17ee56d844404aa31cc306	1677402169000000	1678006969000000	1741078969000000	1835686969000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
294	\\xb50203b0eb85c8f27aec2333dc3984bb2e52d178b2acc1c3d82102f6bea1be5b55dfe0b1fc6cdc3016d60db40f2052cfe7fbeb6e9e812d9e839f57e8bdf722a1	1	0	\\x000000010000000000800003bfb3e914f832ae599df71bfb11cfaec48a33500fb9015893c847ed96df0e2e09c34bc06b50f4caa5b282180b422081259ff7a42c1528f8eaec26ef0dbbfa9b991c43db5b619716780bb6c6f05440dd442b2300466f4f04efb7c28c3350b7a0914641c769c253405a15b40546595470abfbffa83ef50ea827657612524189af99010001	\\xfb76b427a1c7cf54774840847793b1060b45fda56ab80527e42d7756d1ba00ac9b231053cb5895b4aec3f1f83e036b7c1bebe821ed0e4d2d3c8a1fae00347100	1676797669000000	1677402469000000	1740474469000000	1835082469000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
295	\\xb5dab2ff8eecd0e6537ef3bc4925ce72b5f080c727b2c1b48fc93cc8da5a57b083db2ff6cd19b7ae77c08e265cadbdd8b02efa6be47eb4a0bd77ebf64a2d4cd8	1	0	\\x000000010000000000800003bc4d2e2f482c91970bd9dbddca84859bff75710c1cb3dc91f790a470375804c9f9bdbeceb9ffce43ec1354ffdcb6292140fbb4279bf80fd1c9d980ce154fba1f446878b6d43f972457ce57a48997296d1d2040b03b05fcee6c6fb5078438d5cc9561b7dd888a09f0184adda68107a5c6b5efd7c23b257129079892a0b8104691010001	\\xb3f8639f97507dee0ea37ff7dc4e64e615cb9c15d23916c4a4a49c619805c047a9bdd3bb7990b061db98f1b2c6101cd366ec6f96d90261b01fb6b1730e330207	1671357169000000	1671961969000000	1735033969000000	1829641969000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
296	\\xb59a871a8351dc14ecf036326c778997f3131b863ae5fb7a0ea9d1af8b62062aec1c12ef5196707393929e76d7ba0f09fc0d71caf84749f3b7688a2883571e88	1	0	\\x000000010000000000800003f79528deedcc63c771df232efe784d0eec5e956703b5b549807ad8625545ec2acc22b1c8641bd327b84a4f0b4a265059cb6447ff9da3cef53d5553c4e30d8ce05c66835c932cff3d40511b94751af2259c1707a43ca7920d0acde5d5909e1f52745663a036d04437024af085d16289d796dde7314bab207f5a4032a3bdb0ea0b010001	\\x6798b7b2f0abe01cdf9ecc9accceab9ab1420f99fbaeb54f68844826d8fd5bd08cada868698d750a5d3807fc0e67b57c60786bbf39bfd10c448ed956a58c7109	1686469669000000	1687074469000000	1750146469000000	1844754469000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
297	\\xbc5e71f77c09babbf61c8c907f5cefc0ea1d25a0b7c3cbca58c8a75ae2bbb308a3b5bcfff04ca3bd951c731ddf36012344ce63816b5b3edf2adf0d41a3891dab	1	0	\\x000000010000000000800003abbd8fbe12c5a4343a7e72aad2dac2241c3d26a432e9c99af1b37ce23eb1e5ef7db206c95ee21e9c57439070ec83ad9e4f0526f24dca5ea02c5cb50489d122eb2c3aaea7d74206d22d63297012f35f26286337465eac841a466d5207540d4f128862083e0041cb9e16f90933aba8b2f3236a84e8d919aac3e5568ebbb867bd19010001	\\xe6bc2b7e34b832163907ef5fb3a239515c378d487208eac535514544627b081b9eb4575bbaa36921a492f13925cb96fc219a4637f51f548f047e5e6c7840b405	1679820169000000	1680424969000000	1743496969000000	1838104969000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
298	\\xbcc2b6ed572b03c264ec60d1e578472c9605a1e744b5588e13f758512e4a86f53af2001172f0fa2ce5a7735212ea78fb47f523a797555328920b7976714422c3	1	0	\\x000000010000000000800003ce6ac51af8bc155e721403ccda8ed338cdc53343b58c38f60c83b85fc369a0259e834198ea4cb95d43ecbc75ac1d33fd7ca396e6da71d0dbbac5181f09d18e375087a3fa5f174bcbed44015ffad388fd9c47df04a1a20f6b839b51ae0b1b4a6b7d1d7d1aa3b69a61c3d40d975d09c8db57070d9850b2797e0661350c5b39c599010001	\\x553050e0afe1153b298863277bbd6d4638198379720cbe1dbf7dcab25511b5ece9607fe41a6d7adb4292b5f49e098c32fdee33dd1f80fbee4c0cee926fdebd0c	1674984169000000	1675588969000000	1738660969000000	1833268969000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
299	\\xbda625117d6435c9df62db4dd5628a3e3e4ac62af3d03beb32ac00a93b4f4d14475eee175a92fb023f75b4a6898add35db836e8a131f5ddf8e229f041cecd8cd	1	0	\\x000000010000000000800003ab88831837d41532a0f5c74f52feeea40d24b391eb5cd71f10058bb62445aa087acb2670aa53bd47328a9a63d054408af422491d9ebac62ec9c44a2b37bfbd0844dda0295da9d82345a425a174a752894d22d7028aad8f89e7cd36c3872aa795ee3fcddb1a30c5a4893221398ce9a1ce23de824069ad350e94ffb9fc79944d75010001	\\x068b09f782b4fe144d66f89276b15a498749233ffc5e6b274cd3f8cb6adbdfb9b04d06ff32ab7a665595140d8ea078c62425226a0c88fa129ca1b5fbd04edd04	1670148169000000	1670752969000000	1733824969000000	1828432969000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
300	\\xbf6aa2a68f7cd3a959ec4a4bbd856f8b666bc2aa3b3fa1bcf44994451241bb6e2014c901d9a58b06a6a07f9bfc2d04d7ee0d0cc474d64dc4ff10bedbd2bc37b1	1	0	\\x000000010000000000800003e673460b3457ce2a14a557380aff20c10ce08dc8acdd1471f3bb7df07dc192a57289791c180d7116691bd2b5b2a43e4fca7a5eaa8405ef1d83f155b7d94307e125f749e66040003e0d86991daecdcb2bfc3af617adf58b354f69d468e56976f99be604c78f8f16d4bf5926c358eadd02f05386f7505b2985d460936d328be53f010001	\\x2055bece4101ddb5a9cde8b465ee189d519990a47e97dc740c7dbcc9ead30cd03202a55d1f93c55af44920f1fb84a38f66ae9673661c25785a6db2e6ea58d501	1690701169000000	1691305969000000	1754377969000000	1848985969000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
301	\\xbf7abd7b037b049b658209e9237841d333bb640003ca4a1235a2b6e3ecc9b9ba2b2ad16b2edf357834e2f56540a81aa7d5131f28c7928cf17816f89c2edb4e42	1	0	\\x000000010000000000800003cc959bf731db85fe8b7c11efb0131b9cacab8fa224404039d6098baa72e6e18b8f2837d778054839a66e4ab703df0ebf55a1ceed54cfaaae8be25cf1f66e702bcb46f716876945d2aaed37b9d75a59a4f613f9702bb3c6e71620f220c001144b5ad04137aa133c7fe9331bbe6d0deab398a1608db7b7722440ace234c2c3799d010001	\\x562df70fbb20eaf25ebe45d038d16dd91c58950fc42282a43454347c62c873579e94f1da77f07611997a23db5a3986b291d56d09ff66cc8710627ccd6d32a103	1672566169000000	1673170969000000	1736242969000000	1830850969000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
302	\\xc122a50e2d15b0c19a90da958e6f1726aa07346456d927f77b9f42a7ffa29029eb0386e428c4d3ad670ecc7e2b2508d524c6385703683d5943b0ef67532c5750	1	0	\\x000000010000000000800003d47a5bb25617d4f301d7b8aafbe68c456c3c33378bc905701306503a54cae161bc5e082c28fb014cb34e9bd35dc46e33f04d31ab254b6558ebb49c2369364c8bfe67ea9a3a65d5f8a13864e854641f506a0f3937406065dc0afe4937fe012115194c9f43f363128fa78c188f615a0f0bf233857582f137de826a5f1826679e67010001	\\x1598848ff938e26942ab1cce4288b7d6aa37ead4fe295a69fcb3654c9973ee313b8305d570ab8a0f43f84d1ee64ce78d4a37a5987a6b26b90ed4cd86e8406b0e	1688887669000000	1689492469000000	1752564469000000	1847172469000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
303	\\xc3f2241ff9b38ea86b02fa93aa7b2f002f5a09e2cd11322cb9184e81579d0a1bf4ab1db7749a51610428de06ad9d553a20e069a0de2a68c9f6b5780f7eff6d71	1	0	\\x000000010000000000800003d46eb10cff0d5c6e2952c920f7e3abe7bfaaba861853d75f17c4a4d65537875837cf484361b66cb58345dad3275121e52c39904d144cda3b2a0a895b64cf6733410502ec797c338b4df705b8954b3dcb2dba0cfc656b9aebc0ccba7324e4e2e768bd7bc6bda302377bb4a85f2dabd1af5f4b6d67ab5698983ae280fff019a76b010001	\\xe49a8c474527c703e843c46ba061e5168118fae21c3277aef9d8bae17fb92bfa21492df5c2730bb3477c8193fdeb2f6998f5ec886f4d1e41a3dd7cdc899fe20f	1670752669000000	1671357469000000	1734429469000000	1829037469000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
304	\\xc592468dc747c2746c2d820ecca691667ce4bc900ce002109a4c5d6406f26b7bb087626b8649d109bcf128c95f16badf55b19611399393429247662ce3f1d12d	1	0	\\x000000010000000000800003ac86556c9abeac672aca07835033af8390d0ce016f406ef74cd6d2a07a8c1e66fa4259c74d1fdfcf3d0ab456c58b91dcd7dce1bfc567662877131d0a772798b6ae99d42f44734cb0578407d37a7389ee53e7ba2efe2f467ccf30f608edba15aa632d88e7e083d5a172c4def911af336fbe7db83122170636f68de879e4dade67010001	\\xbc08576be4758d5a109d8455904567f8a400cf55302a8787dbd8187890b01084cac52fa100ffcc5aa9eb4fb7d74298c5c5caf36fe6549a78aaab29b38b15e90c	1678611169000000	1679215969000000	1742287969000000	1836895969000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
305	\\xc8d666122f01fc9225e361de11238e73c9082b542556a260902ba91ab1b17fbb3616d902cd7519ff8d4be0058c150500f112eaab787cd0ff93aa1ca3a0476e83	1	0	\\x000000010000000000800003bb16febbf792df7e4703d95bf2b50ca8b852d7d3d742066c7c7152409f3ca8f1b8abd1cb5bf21a3d7b36cc1e2ca8bed20e3e638120313da0898e0b68aa30265a329ed7ea667d886bfb14df204aaac642c76a280324b3b94443e2de801cab269958f5e47de74f6cb9349485e0655e0231a4a39f3429762d7fab338f053ce02ba7010001	\\x76077fb11db316c501816cf78444034d322002ecdad8921adbba00a14ea7d26c9da6c46c4b14ffe2cf50d368e21952d40f232f46cb208cbc324e7134e6dfd706	1665312169000000	1665916969000000	1728988969000000	1823596969000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
306	\\xc9f251e1b53dd953519f541a6bbd2c1f955929983850bb2c248ebad521ce9d450680d9ea755a246ddc64fd8eb909c544fe8d1cc078c168f3276431e2dafbb8f0	1	0	\\x000000010000000000800003dabae47e2b464414f7171d12b040af8cbd1fd045a941ace6d8f6bd5ed67b9041799ba92732ca753d9fd3fefe435760a0df20e1b16112e54cd308de8de7120f8132cd295802176ef3da4e69eb9f69e4f01f13dbe1047577712090e036acdc942d24cda6ebe5e550e373e7b0ef1d9572692287a0709931c6f3d3a167b7b9fbc0f1010001	\\x8396f2db04b1a06be39746cb94c1b20de8408c3ecb4c3eb6ca54388323e28181e28e8d34236d5a7700e62f4a12ff508bf583ab81189d5fb79b02f8f25ba6450b	1667730169000000	1668334969000000	1731406969000000	1826014969000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
307	\\xca32a24bd105ec644a6b56aa5ee809d8d7c1350f71cdde3c2a33dd7fa82cf42cdfbf982826057fc68482d6f6aef55cacaaddb96e3bc5af765c421c9c3c607b0f	1	0	\\x000000010000000000800003ac437eada31d68ce02256239deca6599beea31528b2bae05500bd23dc5009bdd7ef97f69bf0ec517f6dd087d5807e9b65d430e69f6a160d15418fb96039e5f696d82f13aa7143135de49013661566a792b9b225d1c2cc404a62d7d923c037b6c79b068cda719e815bb23e39ee4e6485f5c56dedca33c47bc3ebb0d4d329aa1c1010001	\\x238f1f016dd4ac847be0315b7fef99ff92693e08a2b9e656963833f9c62f03e65324c5438ada0b84fb330e867d98a89a07b41497d353c391675576f46443bb05	1686469669000000	1687074469000000	1750146469000000	1844754469000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
308	\\xcbe2f1d02c44bcc16400c0848b2d0ce28bf795afe746774ebe5aae2e4f1a3e45a8a63dfcbea704e41281a64bf35e17c83f3ecf35d59c98d7a2760b6bcbbdce38	1	0	\\x000000010000000000800003de728ae3b044fbe41e8d15aedebaf2430f28c3014c5fc200ea12633b4b9d0f9a8dd72c984bbe87d2c2b675a471995f954250e848cbd5f05e7c83547843b9af0cad21cd8f83d8637fba8a94df2f8676c49a021175c49c657c3ef8aea354fd6a2473bc99a1b825ca57ff1beba2c222191546ed1a8e0a7b66ea390764466b28e9b1010001	\\xe314e862c6b8034bd3ee653fc9947a374bf91497bb12d6f76b613f60c09f6164bc4df6fbf0254e03c431472549d98f24aa6b673aec7513a580dcaf6b2133fe0e	1667730169000000	1668334969000000	1731406969000000	1826014969000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
309	\\xd41e96ee9785171baa6da72d965a67da24d1c250bb208bfc11d3d72da9ec9809e1e084a109591968783bbfcafd01647ee79fd63fb8b414251955d8b38234a81f	1	0	\\x000000010000000000800003e76077556c4f9925c3810fadca312a9572c13fbf9b8a706696bd68552ee1eb612cb95dbff796fa21d082086988534fc66d6b042f03fa9369694a7832a8a21322810fd679cef2efea4c555551746338fd14519a7373265f738c2519fab9d7a24955f567e9f93d5f3bacd845096bbece15c1884956bc799e4e9977bfc5c2db4903010001	\\x631c0b4b530a64066707948c1350360b77300608fbad2079d02a596a4eab3141e596ffb9c40211c36f8f0d0caf75efe1d1701bbef52d1e7afe8a53b87fbeb808	1677402169000000	1678006969000000	1741078969000000	1835686969000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
310	\\xdb6a20465f19311115890c493b2ce0e83f5fc7cf30fb0dcde27b2dabaf0e27e24906789c958bcd3e0309b91c46cd42242bc85b29dd2ad8e13b572ae144b374c6	1	0	\\x000000010000000000800003a98e82dc8b6dfe59ad1a40c18179a8d0d2241f341691cc794811cda19e10e6481d097f32d4681087f34e31b17cbdbbb5830f77c426f6d1434a5111edf161fc4f908ef2eccf9940f89c15b65483991d6b5a144bff9e99462679dc9e0c78de8304879da63cfd9eb1eb8c318bd8e335f12b9678ebedb3d04d52741f8bb131559521010001	\\x9dba07d47bdd58523e31050b67d1bdf868f548d48c10d595646a53f9f6993da669110887544eeb9fa0547da89594b9d30b8150ca179a3c992ae09ba120d3ae09	1680424669000000	1681029469000000	1744101469000000	1838709469000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
311	\\xdebaf5c4e821bb9e51eeea1d3d407a994e2670ce91f5bda519112a3a15991c967148f110750d0c2863c33e4c16c292e4efc415f283eb022ba47eefeb30961d65	1	0	\\x000000010000000000800003ab682d32ae75daaff54afd6e925afb4b5e3ddd11fd156ca73add8cf7aab09dda05840b22e9833f492cd9d5c464cac8b0088e9477821b24234f7a5881fc5eaac6ebd267bf10d7608eceb4fd8fa021e66a226c4d2e8ebfab73ad243bcf70ea13a47cad10dba24cb211289b55fca390965b3733dde2642a7ddb8ae9db8d4f77cd67010001	\\x8f512ae0bacfc1a49613879f9ea1bb8614cacc4d331669c839996ff3c23dbed444136368e2e8bb03dda3dbce4e64bfd963ccd236ebbda1a26dc9134d54d2560f	1679820169000000	1680424969000000	1743496969000000	1838104969000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
312	\\xe2d28c4304942f9a33908d1ea7111597b7a70317ad44b9232a22816d41d84a3ff5038da56564213c329a06ffe65af2fe876d5bfe4cb018e34038a0235102edd6	1	0	\\x000000010000000000800003b140e732b70ad003a2c7e2572d2893f2349675a327af6091c8bdd01e2d293b0b0a8b56cad0970881262a2412ee0cbc145e334d807d46b408873ea510367f7eebcc65ecef4152594beb7b4e268a70b16f30aa2ded940a07111b36ce690fec185ca7af4195db6b8304222731919f196064716183a2b7124fdccc7eb5929f924393010001	\\x911a56ba76c738e2e6274154fc5fd8f883ec00b1f036729618e71ba05056c5897f9b22c3c89867ec6c93c4fafca5a5cbec4485b17b25d882aebbc5237905e20d	1689492169000000	1690096969000000	1753168969000000	1847776969000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
313	\\xe2e22d164ad9b93bceb3819a7b1e7c2d94b19d4f765397f1c657e906d93beeef76a3831f021da0bd37c3470cacb802f2af6cf4f98bcc8df0cb2fa83ba8cdfa15	1	0	\\x000000010000000000800003b6f9ffb5b41a27bb9f416180c8ef5c4aff0460565716b81df3e2227f9da9f440832ada042783ea2bccccfc6e48a389292cb3d474a20ac17ed2fbcc90d15903ab2301da7f3bfed778cc8f8b1e2c1de94f7b559af627a163739a4723cc6577cfbd64796f41d1e1cbfadb7ded3ab075430cc03fa29102095ad03b002e7584127a6f010001	\\x86ff73fff9f45a888e85ffa2ebfdeba67168d150e17101b54554e9b693a988437e1e640b8692624b4f91fbabfd3adbf132d4c9eba41b6709cf8e00e2acb7e704	1677402169000000	1678006969000000	1741078969000000	1835686969000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
314	\\xe5c28ead426e8dd8f562eb1c06ba1437d435b9831d8e8b51b4ff916ffad14e7da6c65160ca8fc5dc47f1027276e2b2beb8f4f10f757cd02ab653bb71a9d4e0b7	1	0	\\x000000010000000000800003be5ad063a1a1e65e0deaca6b16f3aff9bdbea362a52bea482ac98dbb79000ef82142072dab0294ae6c39a0515ff5de25f071a8c7e9a4d93cb760e19c09ada9aec2c2321374f1b30122d73763d0e6608bfc3a930f290eedbc96648555a91bc6af043d9dc7d65f9fcf60f917e7f98f92dedf87cb71f11ff95420bcba00329d4c59010001	\\x2988c68a996958a4c64e042b0f36083e992ac4eaac85a5026beacdb444ae3e6e16eea47ec5b1b93f3068ca7c7d7ae441b020a46e29f79eb142dee24be0913903	1664103169000000	1664707969000000	1727779969000000	1822387969000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
315	\\xea3258650ad46f3641902b2365a76a96be31fe0738fd4d68464b832ee9930bc095a6dbee624cce5d2fd05e7710fdd4f163cf54012b525baa6ed894cb3cb176b6	1	0	\\x000000010000000000800003c6a62dec6a05276f28f20afc489798440352512e33d310e21a114d013567a0be600a057443da43932e7c2ea7000b007a7e548483c4a11ee5d43534f511daf1aa2cbb63e9ad0eb3a353277504a0ad03b8f583a27e04e9ea1e1f74c8a6e401bb854379e4e420a8933036585ba60bd716b1057cfd959d7565c0b5c584bf51b456a5010001	\\x87002cd8b2e51ec9caf418a501b4ae4757e07f2abd94b62ffbb384fcd2d0baa4918b54e8ae6ee9ba47b3d892fc8544b1204a0b5a716fb76c1a2a8e9715644c0f	1683447169000000	1684051969000000	1747123969000000	1841731969000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
316	\\xea76a8fe89b91fde47a3b17ad8b28aa10160a742d09f7d59d4bca355089d351d6fabafe161b35d3115e9066dc8c198101212c56e386ba317ac2df06871023ee8	1	0	\\x000000010000000000800003bdfa1a20b376a2db6345f5c611ffdc7cb43048ae64a083ba1173de0c92652a72b8b07038f3f51a56ae4f7ad46ff9f877cf399c9f89a7c8095f087f9c2ff27bee96fd3c5589dd279656c2a9fc36098952d88a04d5994631468c067d80e6607655e0dc9cd077c68eb21aefdcf8d70a658339877961582897d7e7b5d6945f018583010001	\\x00b80df9f5cc80c5bdd5021ddc5a3bd295cd4fcb6f800ad7a7db6f11d4e9b7a63260a119caba324560b0ab27af5bae8f6dec0bf3cbdb2e6eb80420e85957950c	1670148169000000	1670752969000000	1733824969000000	1828432969000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
317	\\xea02297dfb911a2292a578f3573541d1f8e26c2bc6bcfb5f43cc8456dbe9bbd3dd7078c7ce854cc00a01ef53d6a56e384eda19f43f45c5714c9f6a08aa751eaa	1	0	\\x000000010000000000800003c7c6303cb1705ffac22d9d3995da39c3852f059c4a24f6a4edba37684a361833f9e941fa4c15f31d8dc7db175a15a0eb0523c8f2d637e5e1a33b507264caa041d3fac50f68aa32f53e4f8973e443b02ef9a6bdb8d48f51ae75961ba0f1a90907e3c596094585fc7028a59aa4126d9237aeb15dbb5bd912e1dd213d0a72819a47010001	\\xd6382784274a3b3a1ce371a8324f5f2a40abbd0895f8cd092bb99232ab217364520c2e1e103d2a7aed6f51687017affb409486cb35934949a3d3e56b5c42fc09	1683447169000000	1684051969000000	1747123969000000	1841731969000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
318	\\xec42d300b3c0eafd841b6f88920136d87e67e88f251b39afff89ee399efc1b4e81e2d39b04f75be4d330ba580a68dbf5765468737c4d2f332a324e334489b00d	1	0	\\x000000010000000000800003bfd4c301b39192afb6854a0a01defc3d4f90f83538456da241f22aad1dd76cf1353d2275c590b1fa36daf8f377140f78a37501ec13344af050cf88019457e8c038f37afbf56bc960dff40a8d1272bd51665fedf5afa2878738f92ee9b2ddb6aff0bb089e1acf2b9d88c3a01a53c237b9a0209679e3b9e61e7b2f8d6ca13502bf010001	\\x6de0c58d168b04efd0c2e80815333ddcc9c95549e83854c1fbcc0858832f105bf1e320fa07ea7ddc0292a4fb181066e3bcf89fb08f572bcc1a2d7722a2fc480c	1684656169000000	1685260969000000	1748332969000000	1842940969000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
319	\\xef36e0dbd2e1d128cac41b5db71b80a804ee5dc7308496cd634b70821efd377d1257c702cc5d4f700ed6f89febb79b511386c927a3df6428a52e9ef3f502373f	1	0	\\x000000010000000000800003b554406c35cf1ee8beb1b4268d0b39cd02438b433b1e715d99bdec3eabe1383198d81dcf8963d1c840bb96f5f862a0926615ed91745551058aa971dbd2edfee8c8945c2c4df22cf29a23b6d2440ec04deede143730e297c78cf35d5ebe75437278dfdd0f68cbc6d2e2c0000ab8d098fc9c9a49d000645a2ec4585002a98961b9010001	\\x5715da5cf16d87ba799f5eb57ca97035215c3227e228880f48f114a0b25b36590f027cde8f77b8cb6d26ace4b8b4fdcfd5e3814ec737f85b61ad8472fc1d7300	1680424669000000	1681029469000000	1744101469000000	1838709469000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
320	\\xf8deb3694a31dff4ebfa05cbe2546bb373341305e43aa8b7e50051eecd5b25887f1baf493df939207662f9aac80150114c9f7a1a24d577547203db1746b1abf6	1	0	\\x0000000100000000008000039a45f889107be31dfe0dbc463a03dad32421262373f49488cddff86085040019a78e704414fe067cd92914cdd804b811f3a8d21151f64c739499604630ecf7c318cd9cff09a75b8f5a40a69f4566a282be0dbdd5e1a87660a604eafa9f9270f33889b63bd4bf9fff94bdb02ae1a458a9b057a95e419e38c445507413c7746e19010001	\\x4c2e5ac22ce3aa721b3fcdc14bea6095459aa81dd4242d0804ef3b9a3bd34bce9dc339f3069e49692b40a706eeab11e0976ec206119c682c014cf405ff6cf003	1674984169000000	1675588969000000	1738660969000000	1833268969000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
321	\\x02377c5421523a72e9751a7da67ca78d469cd6370b4a9a3cd38bca30caabde76191b94656751c21f8b42852981fe5ba05c78b986fd95c57644d7d8420637544e	1	0	\\x000000010000000000800003b42e3eb74a083e90285d471a7a289cc2654a3a4db2374651f57b88ab1aa48b2323cae779e717b74765dc5a49b0bd87e1da774e6ec24afc74ca47be9fe32ca48febdb8336f3992c714c1694840fff32963de49d001d46b4a83f5d07f849a527334df92eea729438ec989761d547f23aef4e609b8b1ddc4fa116d597c5448e3a1b010001	\\xb370e0981be700e5808da2db3da5888050fc7a1dcd3e6826226d17708f2ea296a1d15fd858c01772a76e00768e4c04a2a99d00c945d18f001cdbd9d69da42d0c	1659871669000000	1660476469000000	1723548469000000	1818156469000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
322	\\x03ebb4b266f420e103358a15e15cc13a6c5b80b89d9318adad73cfefeb29d66c2d4cd34aaf5b71bfd5dcaa082c97c2d83f4d219f666734e9a670718ff6602e3b	1	0	\\x000000010000000000800003f1a764887af7f29ffed0ab4664982608b6eb1ca9bf6cb55fca5b746e3d17442453af1d59b6694f0f26255dcf73b804f078f2db3beda662f55d6ee6628b3de647a466eeaf35a60a1765e2516835bca7e90209f9402580fa6346c755134b1cb457db0ecda29cc47129c63168704bc9f892829319c3b7a4b956aaa11c0839fc5481010001	\\xca4dab2f619f97189277e2c2aa6092b08203188511b4eacc9ce2a311f70d32cd3133449bdba70392c381c276ed487c38f2f8bacfa7173646146f2b0ff8fc140f	1661685169000000	1662289969000000	1725361969000000	1819969969000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
323	\\x07a3d50fb551f0cd3705cd19d2978c62a0b9bd9f23115edc4de46a8019a29b43cb275d816571967c39b4301dc0303e76a13c213ff833c3edec7ac0df97709b0f	1	0	\\x000000010000000000800003beba0988cc5516785afaf6a111f9bf629a820383853a62f6713d72d97a94bf0dedbec2ed9868834df89369c196723caaf9277c06c231a00c462b8f5a065950a913f467190c8422e1f49ab5994df37d3a82bee7eea7122f02de0cd226b5099478935819f4f06ea0d2c9830f92d1897ee5e5c31d7bf29c05593088d57b26cc023f010001	\\xdb9a03b3d3dfd7d0fccae4b85710c7914c17141ba80fa28cda817c923bbdf654aa3d068a97f08e3e6f503a865bd5696fbb59a9cb31f5c773765e4de296bceb03	1668939169000000	1669543969000000	1732615969000000	1827223969000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
324	\\x0be7de63e3426cc4a47b3954380c9fc778df15b959afa31c8d6e69f0d19278b04b23ce4877ead98917c0cd6784351d483bf332ee7f9db8fa7011f6b51ef3a255	1	0	\\x000000010000000000800003c743bb034ec451cc7fdc5556cb32e8e70b8648677cd1494cab21e5dde20d5e09949de6cf70ac110baa1ee9226c7959a752d431345ea9f908480a616721cb2dc25591bdb07d2b60478bba69889dbf58b4598bfdabc19bd785939cdd57ab2567cd92bc81fe1fe3ada99468b3470708f043c335b686b8ef74adea5c1bf506b8ff95010001	\\xfd2e4dfbf99e5919433ecbe5f6b229871eeb644cd344a3642db32f5e5c635069112f5acb866d8dd06c4096822c8e6d2b10143f19b21aef4f33f443b2a851830f	1664707669000000	1665312469000000	1728384469000000	1822992469000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
325	\\x0c3b72e7f576ab97becab0f3666b8670963f697841d2f9e94cda1fbe2337aff964b140763575ef4a9264c50f6b4bbe00189c16df6a32995a9f7b2dbb1a308fc9	1	0	\\x000000010000000000800003b0c75890f7501066ed839844d296faa96a6985eca028c854c143a155064381d79a061d94c6cbc5912a49e08b1a43d66106d73b0543e136721995c4cfc6585ae8c9ec2b6879fb4657864e6b4ec2d84aa50e8e0c1e7adabf923ede8a2bff510bb3db1c34c877734e13ffff36a7e395f8263365f55231b7d13026e32c08b6609e2d010001	\\xcd1d2614275a324303c8e6fbb37fcd39826b1e1df3b6573a7927a5ae65df229073de4e416ce9e8ba0130ed119df4ab85855353755aa8aa8a4a0fad5358a7780f	1690701169000000	1691305969000000	1754377969000000	1848985969000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
326	\\x13db75257df154af75372702eb0f9891e6b7845f04edc798c0fc2ea570e83c797a7ea2b89909a34232199082ed7c1edd58f5341bc64e48e00a6114610f747441	1	0	\\x000000010000000000800003d5b77e6129dadb6c0d4ad6c0e0977789ef3556100613c9286b5b6db3bcb8b94b5446474d574e3ccb85ac1a1d6c44794960ba2b9eccc559396cdb37618a4b777a5cafdde591c67d204d96c55f447e4fc8ef9827bcf72055dc961d7c05dea24a8a55c91a3031ecc0a0d7082415aa366186955e24501ba65eb4d34f2af92b71fd49010001	\\x52fc94d537a1e39b3e55b2402686aeeec256e98ad912097823b10b19a9da3ec5fc735124f35f221a2a8b0027422a2df1560777b335939e0f309511f49f23cd09	1663498669000000	1664103469000000	1727175469000000	1821783469000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
327	\\x13e72472dba30381866d61147e1685959c4d9ff1faf3a94d11fd48251f43ca9d9b155034b69149c0faa028486be3215e240bdf217e490d912a3bdda651185d51	1	0	\\x000000010000000000800003dbc91f6d686c912966a5375f6dc939cb8f36865cf0e9ed35709d55fcee2915be82c4f19acef16929f1f4421ece15719abbc5f5c22091f9a3b0e22783bf9d470ed1e54d5d92eb8af1005a1f90fbe32ba3ae11c7d4da0043c8080200ce15e37bd813220becaae1010876bf1e65bc4ac11803a05b72793c313bfc59f2276f617d77010001	\\x876a8347e0f26ce52c40c853ba5296b49789062dbd5ba05fbf5457f4ab06840c2d65aa6d5a2c3edea452da2adc7e88de1e67e67904b1afc26378e2658889e000	1687678669000000	1688283469000000	1751355469000000	1845963469000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
328	\\x1553d4bbf91cbf89be76b64a7db86637f191e66ff558b8dc6601c73edfdbb4ac48c443a3f38cbbebc7adb56118b5ad45f41613d66dcf05b904e3be5af4350669	1	0	\\x000000010000000000800003ce7f2569d69784dcf5b21a7561b1d22d565282244134c89505392630bb0065ed4b08dbf94c6424659e8e9b91abb62b607f4c452f62ad4b1bfbe132a7a7da062533c2835c9edc91cfb6127f068602b7eba23af89348ed4631e71a790fd88b664ccd2aa6713c6908695e10281271632fc5c1c2e209fb8b1ee2cc516d4a52715249010001	\\x0b11b5fd5b4c53bd1db3772d822ca1c829f1f0393ff1e55b3594f502f7bb76f3d046a9bcaee8fcca384755e3e36b34821f1474e753d467b7936393fe53b1c305	1679215669000000	1679820469000000	1742892469000000	1837500469000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
329	\\x18c344773629a8aac8df987f252136ab39927cbdce31f5311a9292880d6953ee9e4f3bb907bde03785277bcc8b5f6eb6d7965c25d54974f03ae68c95f84e2ddb	1	0	\\x000000010000000000800003e4eb8c141842924c4df2550dbb6a036f20aa14e89561b60889d0ec402bb39b582898c6f8368e4a65cd86cf0c281da941df7b7a830d64fccfc3d08497f0dfd238b53d7c21732d1ccee8d2781a2f0c8336b46dee2e0334ff82eb14da5d252d2580d614ff7e344c6f31fed01068ef1509bcfc79a6111724f20a289c0048de0b9215010001	\\x1e432a56150ab5403238ea033f2b89a504f0a7d11f6b8bb04ef90c25aafbe01ec9f23dce70502e338524f0543436b7a669e568404b95188e43a5e4044942ae03	1673775169000000	1674379969000000	1737451969000000	1832059969000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
330	\\x1cdfcd93e19fdd8be490bf452cb41d6072d2458bbd5cc161dad65462ddf08a341dae3d832ee9692febb0c7a12b7e330456e4c9c03036a57a6884d3b2f90c46cf	1	0	\\x0000000100000000008000039af34138f305466e0d740dab8bfc59a6ae2aa54d6a5b606864a2bc92e96b8846ab98f50ab11b3725242e65de380df850d1269b21e1078b384a5d502adfbddc70fe7258ec0af6a96943877f20a0edd1ca52238f5c33fd46adcdecfdbd94b7567a2130207cd2b04f07abf596a470a930fdadc6a2d3b373fde5c2a1f634bf655567010001	\\x9144c54d131839598497924b7981c4c63d440be99d36799cd0cb85d5076cc32e33eb45f04e6d2352641232cf74c1a00775693c5ffd6571abbeadbde0f5b77d08	1670148169000000	1670752969000000	1733824969000000	1828432969000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
331	\\x1f0b04120ab2a64defee12f956f55f667d55247ed597db95ebbf07f69676ab8e05fe919864147902b1be32689adcae2558356c0d4231c3bf3f1d15e5e0895b08	1	0	\\x000000010000000000800003cc2ab15825813e4587b25dd69b828f0ce1a81d013cbe41a4c560c7d069de5f49bbc371167e6b972fc4073eb237a18a1cd21b22cb7ae0323e300458a37fa168c703e2870c095ad40220b2cbaaac977462d38353e0957ae398fc6004003968e4c3212066b03b606860a8d5088197c51a200b15a2225e339761cad3945237f0b3e1010001	\\x5af312d23eb2ed76b0b1fba8684ddf4c0754cf3415d53c31a087f85cc4d59a65e06b8ee20f495b44ab4960172a16a5980037003ebee90b98b6929a55bad7ce0e	1685865169000000	1686469969000000	1749541969000000	1844149969000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
332	\\x225f9cb9c763db62dd1703e36b8fc93a320a5fb1f09162357a2aa7a47edd83a5bd08202fc181df4468bf09a06eb6cb6fb843036774348578f8c5f55effacc9de	1	0	\\x000000010000000000800003c5f837d0eb18d36280fcbbcdf3d0e8e7c5fc9b829567e030757e891ca344fbbb00a73f19f9aa51e93c57da2f06098bfd584e13e92250f01b817cdb4d61ee5bffece08784ec330729ad3c524d3565889954cd5848e988a1ab3a62cd71fbb8686e89762e821a2c2c3a0322e2d07c9d317868ec76df431eed6f11e7da962bc50269010001	\\x345b60465758802faaff23b1189d68466b9671824a9410a5fd7d1c68e05b2835aa4acf02c86a32f93832f14feaf55c70eb242d3aad0b063144774656b32de80e	1668334669000000	1668939469000000	1732011469000000	1826619469000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
333	\\x2387fe529ff171fafac9248c84fe26268054805d08c0656163ba57db2d44d41b1ab04a72160382f14c29faf507aac0881cdd597de976972e59e7e6ed84ac3590	1	0	\\x000000010000000000800003d38f08aa7cdc8632756265b9ab6c19f80a8092d93c00a021a40fe8f1c9ff3d1f0b0e09126e27b21825b01c2d2a629d31ecc24e43c9d21c7a92237247600d8fa6323cdec3c23c1f8580dfd6a9864527cd9210bcec872aab07932f21309457c16f6eaeccd870bcbdc60a8159e306838b469a2a0e398895fdecf79b1ac7619c53ef010001	\\x8998a9b1897fa2e3d74e75868f75354869937d8c6ecdbd56f8e56f15ef7e01595c349030d2fc40a9b112cf5adf44fdeb9db11a535db73c1baa1ea6264b390409	1668939169000000	1669543969000000	1732615969000000	1827223969000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
334	\\x29a383480407989abefb13f7e465d84b531d02ff28c7f1e3c1830cd7c33a0cead9d0795599619ccf6412f408f5a35e1774c2e5aef066d6c2d39efd3ebc46da1a	1	0	\\x000000010000000000800003e63147395424f2f14b469d8e9f154b642ecc3d83e9406bf3ca98d594b37e4b98ca5a67003f8e7a75ee36bb4380b23c8b22100add79604e562d66da6cd243a0ce18713f5d637c39b76748062c353ef90ffcb1fea0d08ef6b4efd37a51c9c75a0f04a29cda23da1b6a148674233596ba656e82ea65d38318bb99b497964c20c0db010001	\\x862afefbfab30e3fc8a96ed1096a78194265d5462b15a73dd4cf10d056ab87cd26cd93bffde75c88877491c233e877e53245fce856a1bbab90bd70a97ff4540b	1681633669000000	1682238469000000	1745310469000000	1839918469000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
335	\\x292f6837d5dc87581b19a00b072fbe4ac88b457127570f97e0fa5148031efb3f08f3594149d8bca19f70b089497ae08f21d17759c50efaf5283d1663400c7776	1	0	\\x000000010000000000800003bfa088a4daca5d5dd07b639f41b5e77973064f9412d095561d53315d4c9dc63f5e8e9b8a0abe40665db884ba0d53f30a14c1ab552274a2dc2b1d3eba1c7eb44acff6732ba21b556c72fbb5eea009686c5420095f4ed6b9eb08dbdc70fb441b85f97de58db49912f57d4271241bc32b229ddcd8c2e614c790d59d8e93f2e7ea37010001	\\x5fa9ac830cc113eade83a5ef3366a93e52142e8262a2eeaadfa3ec151ca103aa2ebba9e580c0fce8ea8b423ed69b96440580d6166cb3a594f746cbaf502ae10f	1690096669000000	1690701469000000	1753773469000000	1848381469000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
336	\\x2b034b7fa09050b3c18f08ea07e5ab1f01f3cb4fcad810c19526419e3d42b4d3e2404f722ce82f89c5bc01745c1a42ba02a7f7afd869290f8c8828e38ba253b7	1	0	\\x000000010000000000800003c14426c7b3c35995ec7a9b84f36d1d5d841c057ae71dc8c47bd931f6b1d096de83c297a202179caee8d3a9917ad1f87a50ac55fb14c53ad6cc9d5effb1d9379201a2f5cf60baa8ec2ab40743c03168d1ec00fe9790f3773f4b4c2318653d11d998893055444bd947eaf4ce024d10dbb93eb1090368ca896b4addc16be6d0c9ed010001	\\x9f15bb263edea62a5df377552a3f15b49aef23d795a873231c369d70be14858fb6b1b24180ae9ce30febe4ed1c6a6cb80f277d685a6784c8eace435d11b06c07	1685260669000000	1685865469000000	1748937469000000	1843545469000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
337	\\x2bd33c2069d824cf5c7c76644371e7a83d29dc77c9bf0c722fdd6eec9304d892369987bc26206d3b87ef0f0e0c0fcc4f6a8850120bebf7741775eae251df1250	1	0	\\x000000010000000000800003bb836bbb9ae824ffafa429b593adcee39147e796ed46e3fe82467162100630cb155f14caa69c100a76a317decae26ad7a724e72995021b14048d66b6af0daa4718f234e52a86574f036bc694d634e8c197952ad4fe9853347e41d5304afa83366a02e9fbde2b98f0055c9e28e39a971165a8ac2c86656d5010691e123a0f4025010001	\\xa6e5a29194f40db76acb04b052f449efab7572be870ee115655d4f588f1c27de03f2a9e77e571f590aa9538d320e78f59101a939afde9721b2ca4a952dfe6a0f	1671961669000000	1672566469000000	1735638469000000	1830246469000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
338	\\x2f570f38e4a4e836cf2b451458ee5ce4ba39f628d6ccf594f71924dacc16536bad35be3d8c1528da9d015eb8f2dfda899f0f1c71f2db5fb553aab6275b30ebd8	1	0	\\x000000010000000000800003eb05b9423b5aba440c4f690699bd13e0e67cf96404099d6fce1c0265f46fa87d61c24b5a00ca9dfb7bf37a2383ca04fbcbe2086ab36be2dd321cf113707a62f44645b5d07806e2d21bb3e4b728bcde5a8ab2a459b6ae31b4fc6a6189ef0983b094a3efa2ab5f7bbb1a542849f5e356683c45ee5592542ca4e3a0f9aef1e38b53010001	\\x8e1f5de8a1a0a9a6bca4274ff7830914345a201966c42f6a2dbce936fc11daed4d51a063c2afbfee22858a1ab410afd8099ab6e29c83e54fb6cdf73e4653d00b	1663498669000000	1664103469000000	1727175469000000	1821783469000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
339	\\x34e75a7442b722f9e439f6129c4f4cad81043f28e9600db4101f082083d4da66ff7e8e7ae94aa19a3fc7bc96b45a4da7d1b3419537a0dd23eb51b481dff19fde	1	0	\\x000000010000000000800003b64364c6f33a0d94caa19d40f2e2a30c0b7c084e09b52c8aa00c935287a1567e07b715194ff9a27d343dbaef186ac7bc63092734309253a5c26bcc91ad25d0069efdcc595e63b3b6878b6b60cc423c57ba5bcf71d37fa352a3143c6b7faabc05edf591e6ceab51585d4b4ef0a9762ade671fc1634ac08f98790b7ba89300aaf5010001	\\xccded8190db46ae0e48e1defe8ae300c3d4075eb0471f38c17678ca44dfbe8a8031ffa7a97b4a93ae528e658e8fd86edc4586f2b49f170d42242bcae28ff7401	1681633669000000	1682238469000000	1745310469000000	1839918469000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
340	\\x35bf283ea0fbe99f8cd6a91d07ab2d4df51033957422aa346e470323eb10f16bb1ef437730f4cf98462fbca7e5d20d9569bbcfdb9ffbe9d8d898f53a37ac07b5	1	0	\\x000000010000000000800003d0c99c65637e71bbc02d12023b877039710318203aa2dd681ed9b9eafc55d33dce79c53df86200142a228741f9a2723e5ab07242e838535841711a77717c01f19e3633e6bed1c638e8dd7c724659ced9f79faedca1d94688cb43f011a7e0c55778f15649019281128542532ec2b9b00fccf5753958a49735b09b48cee3c2d3d5010001	\\xdb5490cbb2a595dfeded7885763f414579dd22e2acb51e234709932fe277aa723bce4b38ef7a70c33e24ff8b86db022be9d5efb706fb363e6a8381b1224bf507	1666521169000000	1667125969000000	1730197969000000	1824805969000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
341	\\x370f6a4041a07687f4e2cba99ee2a64af6abb0de7454caaa52dca9652e427182f01e9ec7c71170c88bbc86e7b7da58162fc769aca9b7524eec67535e9d1c291e	1	0	\\x000000010000000000800003b8cc74ec30d8c6e6c6d7bb0cc9bb3982996c0163bf4a251aaa48efa61910a0d826556a1714ca2a8c2391b27ae014a715425e5696f8091ba67a7834f93fc4f11d807377583149ded56883764320d6880d1deb4f2c89e59b1b8f7feed1026539c824eeaeb34823a3949b2e217a8d6535952b4608d02cccce569a3499b40b57f979010001	\\xe8e72fc842dc91cad51ec1c47cfe79a162c7a9ff2814deabe13d71642933e62c5627212053661612a494a1bd49f207138eee3f289f79bed2f377a4dcfeaef906	1678611169000000	1679215969000000	1742287969000000	1836895969000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
342	\\x37670791e869b5c602d7b5535b10e8de7dc170e6ca7ebdb4f35d1e017ba0b97d1bc80f31ccb89915c10fe4c08153620c417542a8088ab3fed21634b819317fa9	1	0	\\x000000010000000000800003ec06fe085c2901bfb1646bef241af7ad5652ba8f97cee9b2675b39f649a406138f18ad042840b3169734212bbc01ba9970fc62afe16cbd839d06aef91c140a0849a43bccb4b21f8a3d8ae758cc6e11aa422150a7086d6f7e4f56726a3621578e63061820d56de7c7037062881cdadcb67f6cfb9f064233729eb0f9c5829b6cb3010001	\\x995aa7502a43f7967b64ab12bc9d1e74d7492d09cb7d8348479a9129209e73953f8cc36ce40ec7b52b35e8a3621e517e4a3c134f043066712ee31175dd967704	1671357169000000	1671961969000000	1735033969000000	1829641969000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
343	\\x395fa10b7d98879200c80e516a4aa809b0f458ef9c13e6762e6a07a674d0add436f43da0a48e29bfa9f9c7b7daee209934dafbadce27bb6e822b9c70175dca20	1	0	\\x000000010000000000800003df30a46f8070e7ebe57211e5ebe64c2c8f3d9789cb69c049ed8d73f1614d507159c18a01a48d2e97b7ecf00c6d9beea7963a199994cbf8d62d975d724db612b54ebcbadbe025d30cb6d3c0f96fe74037c96b6c92a39e1e19b6ef955ad0e2b680cfc79fb674f0c444649b27924ab44520e41c41c0914c928d4167c42fda0c3a05010001	\\xbff747c54e3e73ab753cac2fe47c3f83cd57c87f5d6edd14e93f980c48a7179e5eb1880658288100664612b6820e59530fbad094c6bc78300abfa4ec1f57d803	1678611169000000	1679215969000000	1742287969000000	1836895969000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
344	\\x3a9b44668c1cb128f51f7113cf0277f3e5a0d2bc1b8abc9decf6590deaecd5082f703cc2fdb0540eb5c324380fa5289c44b6e99e804e8eddb7df00cf86bc20f0	1	0	\\x000000010000000000800003b38bd0ad5d63c91f5f48f4d3e8e349a63cf24cbb86ac89ccd30c307c5d306bc976f0f46d9894f47950d12f2e0e75045f8d043ccdb5cfa1f181379afe3d5eb402f2e3fcf1086a24dab2a797cdbabc695877cec37d188638a765a614eff8768ac737b54c4b6df44665c392d23262c98769496f4c1594ee76ac1c25488fee7ff753010001	\\xb71215350d0f1827657001983b5f0892a35f360a3facbe1411a44d753e66bb7d02277363a49aeb97fa2724d86b31285bf65eff414ed12f0624394113167bc206	1661685169000000	1662289969000000	1725361969000000	1819969969000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
345	\\x3a6b84d4ec1788fbad9d96c388f4c06cc905e14755e94086fcc1aaf1385889d8b4e8278bf2636076cfa9fe863bfc37cd6f763929c4312b29bde39199053988dd	1	0	\\x000000010000000000800003a48b38184308d7044ce4dc1ae4923c5c2a38811a2e35872af12b0ab2c366c6b0abeda7add72e77484d4e0c4f62e4d568432a0523245bb596bdb233f6a019dd05859a72a72f966b7639046763ff4c10a057d12720093e32c087b97fa990a9d9e268b720009216c8d87efe70495299b1c9cc71d5f2d8c2bd8135ee6de2c0553989010001	\\x41d025a042f6abd72df47acacf738844275924fcd40df4aa65db2b8ded81427116728db7d52f8dacf3c8d0b6b6f8ca9bc5d2da57536198ec8ac3ec2d2e6bbd0f	1684656169000000	1685260969000000	1748332969000000	1842940969000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
346	\\x430765fcc2b33d43f7cfe9d62a185f59e2382392202da12b3f425e8295344ec70dface90856d90b17597435b1264d3708da2ab6c9f04b88a94b6652656e9ead2	1	0	\\x000000010000000000800003be3caf5ed99f9f4fb538b8f10dc07f8b5bea615a06bb3fcd402efdfbf2068cb33bf8694c6d13b6577ee04208cf719816c744ad65879afbd2764c5c1813e28331b6742864e7bcb634d3f09cafd2b96020c55524e69ee02c3427f1451a2f8a1635ba48b7709b9a2d9294a4f8f9c54aec90171226a59157c2b97aa5fee26c3edc1f010001	\\xe213c49591d0014d0f1677e8a85be2a6995808ebf05a456002824367c484c6c3ad5ee8b591ff64d2ddb23a6a29dbec0b3af08ee98516706864d52ece4cdef10b	1676797669000000	1677402469000000	1740474469000000	1835082469000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
347	\\x44b72e143146486cd91de4f3fde63ea4e182ffa1a0fb7bb942408e14115608c6171f13f0d9bc717a16c8717c5e557de758ae2e880fe389d570fa36b44303eebf	1	0	\\x000000010000000000800003d244981dff480716d69f7227f87dda2f6f0ec884040fc53b61d0f40856d9cfedaddc5c39f11e4865b45df04e24ef40a1e45669d51d576ad1d9031ba0006872c4883b18c7f4ddbfb629679f6c80d64b4dd58156618b221d390458c01abddd3e082ab215a858bffd6cd876241917568748521ced1dec3b2ee446812d90eb842e5b010001	\\xd719a0297dca17c6fea988d1a832c1c51ec3795eb660190638ba5fabb1ec1d99a078493a4b557881af37a242f3beddb7ca05e57e48c4e63cbfcab282b684ac0b	1665312169000000	1665916969000000	1728988969000000	1823596969000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
348	\\x446787fe1282ad01d5c8697e0dfea44d0b5a57bb8c872b14c72b06a677f074da8debfd347568ceb8738660eff637a85d4a9c1c255c4ca8c1029cd501be05e5d1	1	0	\\x0000000100000000008000039ed0935c00bcb7018fcf2502f8f560048df315fea29cc545b9f2dc55b1338429d00e2d1353f71925e05d606cf41afe2e204510147a92775828edc6698ae20f87fcd9bdaeb19bd2eff4bf408e158728fb240dc0f52e276fea774947b9c20f538e76b349bafcad1084a9a347d7cc1d69ace28f091ef4bb2d475997d1dea6c16857010001	\\xf686e74305df6e12e20c75d1df0e4686c2b33ae20db1687cbfa2f42dac11641e295dd451b33042e1dc242309ba7cb918445d33615615029e5eff117d327ee600	1659871669000000	1660476469000000	1723548469000000	1818156469000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
349	\\x44371efc7bbaae5640af72c5b70ac32767e9228422f44db5323793468594f27c15d943a763bde9938127dc6309604a559f7af0b5dcb40268a538e620acf242f3	1	0	\\x000000010000000000800003cad44da4e6f8f47c6a3336e09b0acf94e50f6cab337eedd49d636bb5cd7792c692e3ded226c551a96bc2e76c6d6ccd03cb0c2f093de995e4a2b999df4f094a7775e46b27e41ef9695c2a5857f221c104296236f2a2f1729ebb470d4574d90b2e66887b945f32e175a353dcc58cd1d9d154dc3d0aac9db285887ab176421fabcd010001	\\x713b5c70a3cf699fb204f0223bc73ee8565ea1eeb3ce262a8ccba489f8e526b28e0f50e4c4d325d4d4e3a156fceb7d36ec66feda41f7bb870630d46df9cd240c	1688283169000000	1688887969000000	1751959969000000	1846567969000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
350	\\x453f387ae0df2203373f3eb0fe67717ce8719c6792e431eef4d3f8e896cb0bb314141525e7a0b8e6dbf5d5d00df6b5f93af4b6ec29139c9899a56ed9c32df8b6	1	0	\\x000000010000000000800003cc89bdc4224a16a7570608553207e411ae9b0466ac1458017d59ea0e0df766f191bf01eea011d081641dcc906b388ca5d921878263296d43ceb23b8980f140d6c32c136a09ace229a4a81605960f6d58e8d6077db7b202daacf0b3908596aaa7b8ec26898a9486d10385c2f7497b63b37887de3975939b9a607f395b14964d23010001	\\x72d77b4e7a0d589f127bdce6683767695a0dad4a91084b03a83ec70982d366d2bd2023a2aa1165b02661ebde5f465a051036650d14b804f21635289e38bd8e0c	1682238169000000	1682842969000000	1745914969000000	1840522969000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
351	\\x47bba2c0a48704837d9e71a90870d4e32f25999e50815bd8e82961a4d046dbf0917ba1de04750698d9da92e03eefc65ab99ce87eeff22c09a77e65d7861a253b	1	0	\\x000000010000000000800003987eb78b1466a36fad6f9246eca93a58a9740a088a4da41830643f38e057773945bc2eaa44ccd9ac303d253a31801816666c4b4cd10efb1d8ba6a259c5a4b8d0958e4f480d64de5350801ac57eb839278dc369830a687949735b3083716cf2cfec02eb57d31868967ab324d3a372a8dcff1343533b47f71c6199f8299ef71fc5010001	\\xa65e36aaa9ca7ca9de017e150ab42ae589d627ffba3b4cf1f1981401f2a3e6cf52c494b1f35705c336d08cb8c9f69d30285e0f02262911af35dea84bd1f7610e	1675588669000000	1676193469000000	1739265469000000	1833873469000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
352	\\x493b34e852e74ffdedd7fcc90b1a0d5ce8cf1e7a4d915a0c5b48b5a505f4025eef60b73350cc1c0a5278c889218673c06c075eefa6689df5cc2ba2e134243b68	1	0	\\x000000010000000000800003c658b0d07e9605b5e8bdeb451a50890c964224847cd85994b939e70d5d330667890bf5888cee8a4012e5b6271582e9160f2e18296bd39841210e7f6f8553a7098708d8055460e6db19df2bddb396564128e82af9df1400126ff4dbe160e0df14e22cd467ae60e7e73dc56729b9386f76a85afa1d8c7cd25e8881b35d21211e29010001	\\x4d28981a784c01eef7fcf8976db694a3b2b81264d150f3c08f045d7c6ff50b11ab06900b1701be9312d9e8618b8319fa2a62ce2acc4377f64d40dcb67de40f01	1688887669000000	1689492469000000	1752564469000000	1847172469000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
353	\\x4b8be708f42798d2d7fd12cb55a6fc24afbc54f88a52b9ad1af007f93e764d3fba61090e0fc2ff7798ba8d2551fa4aafd251538634675a30f0165da8613f1c8e	1	0	\\x000000010000000000800003d176342a56e704dbfdcecd2c4fe91a90a13de76ac12908afa55aa9214e3819d97ad21969644ef9db51d4682f24812751dc45a0db85b9e7f43a9ef6f51e5daa8ba8e2e61f5e326fea1110b9bd3109a88943c31c67c8bc1457492ad02f207802a57752f0e9f07c0fd6b6f559fd695449b4610257c108a6cf3715e842b61f3474a5010001	\\xc60088520cb87e75fda09c3801bd6685ceb9216a5d147daceb45c1edd03a352c7416061274c25d5dd7f73ff5bd233ff2e13fb735cd182f4fe1e77f60c7d34b07	1666521169000000	1667125969000000	1730197969000000	1824805969000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
354	\\x4cbb42c043e2192765dfc820bfe68baf336b74ba2eced266e007797e96d508a1c22ba58aaa087369465e37b2401d12f9b6355ba175e5d9d190782c4e9e623956	1	0	\\x000000010000000000800003d1bc03db140bcac080cb078e3a4a70cb7633ee0e29ed3d09e00782b0a7dc622b27e9f9be1295f87fb689ca9244767b4391d6291fa927915c54bd48ba7d8ade6523d143b32f388f71c9b07fd44bf578231d06370b670f76bd056f50694c64d8c88fac36601fddca89c7360f00712f5ade912c0a3fb2b24c66d3f8cc5fce5df2a7010001	\\x9bc870a1dd96d4be7b36aab6a213f99136d6a652fc2caa6630f1569351216ebe205d8e77684788d9dce5295e17d77c826fdfa934adddd7e3428047db7c38dc05	1680424669000000	1681029469000000	1744101469000000	1838709469000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
355	\\x4f7f0e3fae9364db21634f2ba9e9b36155a03ccbf3094c9ae6fe0518a431f8c2caf4a9893975d3ff5021c1ac3ee3bc3c0edb73550dc5155a2195c1deb92bbe9a	1	0	\\x000000010000000000800003c8e1d37a2b97b97ef258d24c2016bba5153db30d33c46525f54e069a612c7846702226d17db8b6dbc93005d93d74ddb41807c8555b6ac6ad996ce7b972091f91b735089a342dce9a5e826a66912183fbcc33719adbdbc9c803b1f40e9eaba4a8b38d60b123e98d18dfec8a26e82a40b29386b92c3aa47a7b101f830c8cc17fa5010001	\\xf2ecf9a97a0138874f26c6556c1e7de33ca9008656f662a158385d472e5629a08de6f7a858fa01ca9967d7574f0b3f6788b408d5666690cbd274ff2180b9d80c	1688283169000000	1688887969000000	1751959969000000	1846567969000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
356	\\x4f27f7fb294a26677685c1e0ae2e9fa45ca0711164a8cfd7d9087c357cedc3e21e1d0248c2e214b7ac1ebcc2954a38a0ae365ab11b9e6be324a082187b7dee88	1	0	\\x000000010000000000800003a5502c018e80a7e48f73c463ca7a3bd1634320d5a0ddf104ca668f7918e6c0badc5a77e41a0d23729a38bd30e1ac1d074e41eecd739bf309da13ee39a5186583e0016f68a2bddb1c169c451a07450b67293bad93bdeada53b2272c9fcd4aa3db72cdbb7b1e5db89491b924d58100f72c812aca72cfec6969a78cd4c36075e84b010001	\\x46e835ff8479fd57073a2f470d663bac1817cbb5edfa4326fa0742d9569ff43d135517a2b36cd753cfec85ca8cbe8312e7f0e426963a59c74f2447cfe65d7d00	1687074169000000	1687678969000000	1750750969000000	1845358969000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
357	\\x504b9fd5c63c21c0344796bf1d9963a79ef07ff69b36da00f533975242cd8e346612ce3d1d76698cd60688a5c36f304edb214b98289fff9c426af1fa6b2e59f3	1	0	\\x000000010000000000800003a9b7b46f3167a3035cb11cb7d5892546c291f7a42ccab5dd5a1fdffc82d2433dc2e3bd23eb03588af44ae84cc4bf4377a4e460db60cbeed8bfeaa91b34665f54b5a6bc8abb7d39cb4f329cc32697a86411f3f76c6b875d6076229b02bb27e32a22de6f04ac6cace40bf4f098d472cb58a331ec84b117884bde7106d8e9c3c171010001	\\xea926792899457d3e4da3cd17523d2cfa178df30f0c2af1974ec3278b2b6c99cd901f0ec8cfbf1716a12b440a53b55136941e7b8d998ce51196eb5956a42ea06	1682842669000000	1683447469000000	1746519469000000	1841127469000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
358	\\x532396f25568532968b981001dd73deafb906bce0ad9fbb0332ebac760f8f16244ce69158266a31f35617925426944c08a772a4817334e87d08905075f4c9239	1	0	\\x000000010000000000800003937588874de76a1b5ca15cee29d2cc1b9ba2e0346acbf59d45a7b6671bc8b20b28308f8d094d50f4e18939d637fb3d9658e8cbf85e22b88c35ebe3bdd237c7fffe8668d8769c755d4f8c6806af8658b660feb669b7b458f9cad67e52f9515fe344c5d0ab6695af053d4a3e7dedaebdd74d682701483ac21815e75a053b3a5483010001	\\xfa8f3fd9130e36270c9e0386c09948da8f343f3945d383219eef9118f60cb933a41845959335e58f3983cc39e0b592c47bf44333bffe592dc05bbaa33ef6ce08	1678006669000000	1678611469000000	1741683469000000	1836291469000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
359	\\x5523e4fa77b6b4368a405d26a456c5efb2fb90f7c890d4d466c4d8e0855ba9a2683c1c27ce860851123b2c6f9adc341e85932846c58570fac6f81e67b139684a	1	0	\\x000000010000000000800003c7f213f7f6505906b8b303f19169070c600b969c46320acdc8db06a7f7e99f2883832c7e37c026bbf29b010d2e2e76a91d4e7d56a5f2517ccc8eb42f22befa3f15f444365d2bdbffa38e78530062fa53faebfe4504be8faba524013a63d8513b97fdcbd2cd3a914ad2528bc080d07a02c3d246e5bc0c09fd077b5ed2c6145f95010001	\\x7838847e19828ce9b5ef4aea1a8c2366931a4bf0f21891e1a64796d024ed846ef9bf7ef9e9164a732ece70d8aeb5bf9b49c1c5356bf648a175a7c541b191650a	1665312169000000	1665916969000000	1728988969000000	1823596969000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
360	\\x561f4a5e0901507d8a2dccb04d9b260296df81be0ecc80f305e7c074a258881d54a76580483f55cc8cf5c50c2fb4081b4366e3d20256a501188efbf9a8628808	1	0	\\x000000010000000000800003c2bb0c990b98f0bf9f819f1bcd007608963a953fd8c4f911aee3793a0fa057300fffb8d86f6e522d482d881be5dc16c75d2448ae5828597ad8cec5d55674c596de4f93d93ebec343fae71d513e8d6f5c5cec5db6b31b968f64a4e2b2f8d40816d53d2f91d52284c70f86ae9c5d66e289e9b355cea8795d3b07832066853206f3010001	\\x9103bd5163894436f904a639a598cc8c0dcb378ddc0317c9bd2f74fde0af68100ab718368bdb66a471948bb2701db8b800accb6951ddc6e9dd8ec794ed312d09	1688887669000000	1689492469000000	1752564469000000	1847172469000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
361	\\x587b4d98b5701f0d53f81ab0d9192d87fd9c89fedcedd9bf6dc2924e8cb2c44765d0e8ba4305dcdcf0fb4d7989317489ab9b539acb8937c9c5e8d989f2fee6c5	1	0	\\x000000010000000000800003ba84df3352a0aabb73a741f197ef052d3802c80bab94b6750b40a8beb348350c2d08f6ac6e602f343a5508fef3bfb45af5ccec19948ceb6e82e3d1528897173f436000c99a1731250c903772431556253e3a8d8edd953c0803fbd4489e90b3cc20f698c64840848047e6d215ae05fe056ed7c28fbb108b83beb66828cd60dcab010001	\\x72e3249b0fb7998d505a89d22db8c9141ca4a5531dc0d481044e2b38a2be56d8ba8a334b835e2f4b165960410dea6e1d8cb54039ec12f1ba6cdf094f03189000	1667730169000000	1668334969000000	1731406969000000	1826014969000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
362	\\x59df5bd467638b159dc2945ba6cd796528ff74ab3cdf70ca3d252e35bd0e3d6af8fc218c696c1da28fc25c15c883214dc770cefcd68a41f416e5716f138f323b	1	0	\\x000000010000000000800003c78bb4b229b58e40c98f619862f778c2f7d079bdde7b9a865651db971be247765f7e8dc3c98e8d5fb91a013d4044ea7d99ef9b51df3d7a8673deedf0f0f04e5d573c295cf68cec4a58624a9b3f3825705b77bb2722fa615d6b0cd58e2da52e90c7216b7525d293209dac75897979e893ba9c1d8e8a4d264bbac252658e300b9f010001	\\x4baaa7bf0f8bda52c37cb0579cc1cdb625c1693530fb0c02572f26811905e6ddc46507b629270c664462c14adb5b125d1d000ce379fc586430d37b1a06994507	1689492169000000	1690096969000000	1753168969000000	1847776969000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
363	\\x5917ea32756cfe444056cbaf111e09d3e328b8459989f7252ed9ea3e4a70feb4f7383652787fe0bfc40d580192e5be8175d38bdf862a729672bbc40343c62fb5	1	0	\\x000000010000000000800003c933241a35abf40877cbbe04daea7edc3b010d9861dedf2bbe48a930c7272da61ac734dda0321f16f4ec0e2a906baf68b5c73c285282169861d7091cf8c221599086afc6f0923873a2ffbf41b3da5db2d8b31ed595d687b0188d5b24f0920b878202c949c17c2bc33a73dea56987a0ff78f2cd2df1a533a8ac8a18d9c4e3d5c3010001	\\x6185f5acd9601ae21b5809717ffd88c665cb8a5177c53478ebffd108288ba93dc02e3471684bcc62180c01d794f4f7f55a9b9a990b458c81fb751b468f74d608	1663498669000000	1664103469000000	1727175469000000	1821783469000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
364	\\x5afb8abb8179aa73796f19d94d783a1fa55f412864b367d019dc76868ecf6ec04ef024ae8a2f84d2e932b1de99acdc6149ec03a57ff769e70184f9f1398748b5	1	0	\\x000000010000000000800003ccd955e22c28b41911aab18725b0fc937559a3b4bed6cf31ec452abda3a61018dc9bdadfe9d7cdc09a9a519f580d6d3bacc5b0bba8acbed1b79917f61a11beba6afb3b371dd8d8cb9f27d67acee5fae40201eb7dbfb6825fde879bb3df6ea28bc25e756f50a2c118894a3057f58aa2a079c02a8aa488c00593f366cd5879c053010001	\\xbcd72e3484a6b36023e13668398b2bbcf6c43016a3a4e4954b5ed765e715e19c7e9406c4bb26cfafb57a544a6c80f6be657e64f5d0cf9af07b6045bd8619c807	1664707669000000	1665312469000000	1728384469000000	1822992469000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
365	\\x5e1b6016189fee4bb5e6dd74f873f72b4e876f03cb2ad9274581043028b15cdeb9b3f8d73172ba832fcdc0e113d0e5e7ffe86948511de14d2d192d2136ea73fd	1	0	\\x000000010000000000800003d0bc74b54d74f7f9427d78b13a869988b36738b7a121915644882a51a5606df2f72b20aaf6363ae2b5363c8bb21820abd46c5540142b3cc9a4196f8ccbdf3662435679b740b8cac9be9abc24684f07aa8e1d452639a66a59c00f92c8edd52af0c58ef7a9e58fe8008dd68f7a5a983d6957b08b374bc062d10470ec58eca0cec5010001	\\xb86259a4102ac02c462d524f0ae69c665db962322b79591dbd4dbb6a15511eda1f4b28d47fcc80782deb722053e9118584fcd49a9cc37e63e0cf580742ea330e	1687678669000000	1688283469000000	1751355469000000	1845963469000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
366	\\x5f272561d3eac36f3f8b7ad4dc9b72a9ee135e76c9037f390d5eb1eb49e751385b3292e27d200900e965aa7605c1e6892af9f565ff14aae2dc9b5e001b4d43cf	1	0	\\x000000010000000000800003cfa2ce5fe7e773e1659ebe5eafc46d1d6717797e0569e4f550b8fdb3f5e0a3c2a9289e0741ac2813978600101c8f10c94db5b3d492e833ad82aa1b448b8b4988e0dde8ee68cb7b0676e46d023df3b859ec02f11b97a7b63fecac7ffaab8ce6c69e7e2aa797d753f890c67e3aa2e28b3825c6b8fd31d027289272ade85802fd13010001	\\x6d87d56a46ff31debb0459c48e3be3a4cbc86da3307c788a3a41d44c789e34108086b17619a01d77fd3348bdcf4d213a6b51de07338332f675340dd64b013500	1690096669000000	1690701469000000	1753773469000000	1848381469000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
367	\\x60630d83bdfdfd14ef9c37e73d555939c2e012855912a7f80f8d9592939ed5535de02a5705852a1bd0626815b882ea1800cc3252d7e5997f161b6d22ec89ea16	1	0	\\x000000010000000000800003b27ea78f8a82d8f530e59be6d5ff72820f748112ffc0f7c262be039447549d505054f4a157d91ff430fe5967029be6671111a11240404843878e48d5d474ed70b35cbc02ce3f32745bc7783f5e55f27467bd871cb530fbd443fb9eef24b65828f78f40a14ba95bcd26a0e4a9a8cc1d8208fed8b09f03a9e46b7a9b8ce3eccf55010001	\\xccb4175679bc1b301064b898018a2eabbe9d68ed4b18a610d78f5db910dee4b52e016f39af931ce0f707939e5b26f8005388c216b4f39dd6e1d3f4b54919ba0a	1679215669000000	1679820469000000	1742892469000000	1837500469000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
368	\\x63df4344d954a20bf01da0117d9f3bf2cfc83ca9f8841074e0374b5b07c18dbd75e37c782a41275c5437c05351e8b908a987902d025c66a4108728df709bc5b4	1	0	\\x000000010000000000800003d13761d15cf4d0808f771cf4e780dad0e9ed420fd1d99d2c749fc35383681005596a38ae234b2009cc882cdd8e89c0d9a98f64adffcd9751f866bd6c4a02bcb6a83063aba602aa7ce3aca95079f8970ddb7c7f244fb6e2b6d9004f024e271b015060ea7f0944c2021907e7ac28b8fbfc1dd58f7637df05204f5f633926170423010001	\\xc51b5311a5b43d23638769c4286ac1581816aae65951b4dec1ceaeac4cd18dbc16af8c1cd6a719a25adc2583c03a1e234b287cc4aab81ebfc3921d498daaf60a	1682842669000000	1683447469000000	1746519469000000	1841127469000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
369	\\x645bcbecd1d30c61fdb1e9ab1e97068d492b366d57d0769614bd4b2b27315751f86021fcc22ad3cc9bf4305091a05fdb7e231a94f7e488d73e9d40809dfa5911	1	0	\\x000000010000000000800003cae38b9cd17dfba9d03d6412b4ca1fbd776b29d6b7014568b7255bfa6a02e815399f1374017585e88246fc9de62a2607c22e708d88c7222b92d8d03551cfa4c66ee37c031a438920a758e5a5017c674294867e7bf3bd429e6413be44811b8b887697d2c94dbbc360090a456beba3536c8d59dcf56beb4457a5410168dd414e67010001	\\xe510749c2bae639c8ac1b44a0fe0e204f0112d07dfb3a60d99facddaaa8acfe2c0921bc43967bfd20be62d481c188b1caf6fea2a5e8ee77c06cf06013be51c02	1685260669000000	1685865469000000	1748937469000000	1843545469000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
370	\\x65f397b4d298775f77ba46f7c57ee6af029640f9aa352019fcf48d8e7ebcc0f9002095a182fc7020b4e4bd013ac22473edc88d750b3b553af2b24f4905bd8157	1	0	\\x000000010000000000800003b01bf4d0eb2d434bf9f982f4a37ef7c1a6ca0e7dedf0a1cf6e023ffdbdd09d4e133eac5cdf67f49768b18a3edcfbe04358f314041e1f2294a264d64112c7d65830d392653d93fe2c677f963fe04e299c4b727565ad92d0859682d186f86ce8e30d8f3204d55be98c0edc8c318d382e582220eb22c1f9e905a9a622bbaccbb4b5010001	\\x10fc6396b35909e3bb75f46a5ce6d13675f6c184bb960f4703cdc6f40f2580d6801fd87430f0037d6999df458b442c49c11d9e952e570ce0e400fc78cff15807	1683447169000000	1684051969000000	1747123969000000	1841731969000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
371	\\x65b7d19426b3b76297bd9467ca21a967c0a208d4792b5c58e28c7e7d44754284c399b9e45745e80d6e6b0d845878e1aa6ce3c43b9de54080311a6fcdfae1b77f	1	0	\\x000000010000000000800003bbea2e6909985630fadf5bac70d4d0ea88d2eda41a331ea070b6080da2adf8be3f12eeff4f03e277b5906631724f182320f389d2d99bfaa201fa3eefe5cc28af129bfb2d7ff1e6159ca9c403971a02a6ac3de1f5b91f5b051550ff8d30f6cfbdb443b803167ea029f829064b3dbe8641de98c4b8e3a01f8aab66ed48daccce59010001	\\xda670d52b95f0c2feeab13665a0072bf798ae698eb57e53bdf4ca7fc67dc5dd119c183ed79870eac5b06abb895789bba7e7871830d39cb41f4ebeee0c3eb8302	1690701169000000	1691305969000000	1754377969000000	1848985969000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
372	\\x726b6ca28b2087640fe5ba2943f1a1abf28af799119e26b379afc54979112b23bd9ea8c1bdefccfbc79a398cbcf83c0a00ccdb04689085d4ddb91ac783aceab7	1	0	\\x000000010000000000800003ba2973feb4db0a98eb8abb9a4e7ab3b2db2037b4bb6edb4df9a16788d369a9f70b99f26afe09f180ac0fbae2a6205236cb5d8fd44ffc340414027d90554efbf615c2ac18af93a9413d0c66cf627bedfa5417c06a11406896adf5bef83d5dce45415c02dfccc37a30424bc557acb8ce1ebffb060b56b61cdd063ded1e72f4059d010001	\\x46d29fb24ca21edb5550e90bb2f5ec4af885fbe0d23ee02133914d6b18a4a5fc7c8ba016e323efa737c9ceec17a3294986047454856eca62d12799351b54ff05	1687678669000000	1688283469000000	1751355469000000	1845963469000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
373	\\x77fbbce104da922f2a70eb6d998151f1e6bd101d40543abe31f76ba0a504e952ee896af6bcb7f00a1026fda697a7a220031d729d90a0b427b046714e1505818a	1	0	\\x000000010000000000800003e9691cb743b8ad70680f50da3c5d48f315c1e21b4f70c7d8f11258f2848d2c2c95a65bbb4cad58c19e1c334d4c546faaf889b59916e63cc4b587961e44170dcf8fc5951e87b99b8150e21ea344b9f21f1ce1a35587563b4c0f5df90d27867882e4d8e27d34ce3fd5aaf53a75cc67298d127e70da5057a4463188305e2d6d5321010001	\\x0e9579f3ce893d2aa8bd597998cd12438116d0b485c5137829133469f006f402f09308c808e645b350c230c49b99a06805679dac6b2abc48c99fc35dbf38e60d	1677402169000000	1678006969000000	1741078969000000	1835686969000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
374	\\x7b27328d33e0568e81ff04144ed399af44761ac3f8ada7cdf1cd13d9adee05c6653e6a605d363adc89e0698a7047bbe55dd7b21aef68291233e278e41d6e542f	1	0	\\x000000010000000000800003bf662898cda12c026e5b86eedda4f52bd207f75e035feaeac468e38efeabe8f959491b184aa8c0d5d01c2b9a07d79cc34d2166c1dda457ca0d6e68a48fac7fc71d687d01e4842dd005e7ef5fef61c38f12fa89687643ed2ef97f19d37c10667359f94804a207f9378a9a8b50691ab959426045b67bce3fede954bf092d6df1fd010001	\\xf67db230e7b186ddaff91d46d26ac7623c3295be034466b9a9e1cf22419fde9613759b5b96b8889d67c6db161031ab99d27ae7be841c414e21fa571565ed3a08	1676193169000000	1676797969000000	1739869969000000	1834477969000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
375	\\x7cc7de6ac25128c8664b3e5f1d9c9a18b1f5eafb121cbd2ae70dd653fb335579220a8b31ca5820ece0199ab373431524afd93156b6d238ed678fdab23b66348a	1	0	\\x000000010000000000800003b52f57ec381751e299a5af611220ad32d5e6bd5612a68f559265a29af79a6f4a6d582da4188c8b42bc4007785f8392e5b46e6295d34802e66a1007dac842f0ab5be3b07be995cda4b6495c2689a3440dbe98a13f1140443bcd0583f2268d5171c82e466fd9f9f2cf1960c2cc6efde0df7e0c982a0eb51437c61fd0daf3326609010001	\\x215676889b0cc6436bc5e03a59b4f99d50fdf877237d9e9f51e4c5223bbb6f8d6b1c13bda8f6cbf51de90bd5ab86aab30cc3e8a61f097e140ca5d86f4f9d030e	1684051669000000	1684656469000000	1747728469000000	1842336469000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
376	\\x82df61c12893ea4bf7c20105d041b37ad5f33e3a1cb328339b12da8c500eeda1666b4837bd0b8d28e32e40fe43fe3ebbc763cb81000d6557e77a43160b5e87b1	1	0	\\x000000010000000000800003cfdd43496b1d5b531c646fe484b4ce6e873ad52285294b25f2efee525e693624bc3c85060f566dd08adfba93eb6bc277ed74628b9538b64c964e84d9e67d5b746ec087ee542fc1f9df680f0604e8bf640dc8979d1bfde99807bee40ff164931238cfb13368ea95a6f7516cb96b53a437bb4847af56ed12dfa862fb8dea2bcf35010001	\\xf6aa0515404f3337eb2d417f271d4bbc494c81f4da03d38bf00c3c3352a76f24009f5dbe5f5bc80287d9d1d281fddcd8ce4f9401b03d7d8197f03983c3a9cf06	1681633669000000	1682238469000000	1745310469000000	1839918469000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
377	\\x8423447d695e3e126c86468d6e0d5b27b94b53906b60c0104f3bdd7dd15c6581cbf84b55cb9f6a6e00025e76decced55b19724c40578980ac49662ad12dcab90	1	0	\\x0000000100000000008000039c0ac3fee58090bb2e32617f2bb65f4580216435f89bdc63b5d625e47f77f69574926d21db751ab16cd1aca38ff1a8722ab57670fba0516b82bc9f99141bc6a40d62972c73839938dfe51929a01973f43572a03dc25888a28e3e37d7949aadf4e2af442cf0127e7fe8199fc996f91d37fa81c607d2fa6624478e2b5087e4f32d010001	\\x2b53f2274558d4baed4d8be7a28c91c106354c19924b747afc902c42ef84075132e3fd654d77222fb7e181396e7869daf2d5476bc39f01a276baee776f2a7a06	1668334669000000	1668939469000000	1732011469000000	1826619469000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
378	\\x946326ba9c7d8a1abccdcc2719418125f5402eef77f7b09f5bf7ccfbee4b9f0f8b752c991192df06e28fa6dae187a10a1f4b6d075c7148ef2380f58315dbea8a	1	0	\\x000000010000000000800003c0517f42eb3a769b81fc382be0d9cfb342d037a5b9ed8b9a450ca006c043ed1645df895cafae4740454ce96548bd0fbb23b4f1eb2a932c89e1bafb02e9e8a806df2e3d6da5f967a64ff99aa151a52ce90fe6159794a8a20058630ddbc394d0e66b19519f58ed655d8fad2485cf75ae73b243becfee5bdd66f4f5b287a5a5b919010001	\\x4539c25b9ad806b4bad3e040034d0cf9b8bd1688d87e8e55ac942ba9a6b40f37d73346f34274a5e57c6b5a5eefd9d69ed3c0d913212c669b7822389f0dc86b09	1676193169000000	1676797969000000	1739869969000000	1834477969000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
379	\\x94bf133a80c36936167c0af6884e9bd44d890738671f477feeff061e9f6fa3fdd1b1e2c690163c1f611be0b547d855a90e9202a0e9579b78099f42f095377b0a	1	0	\\x000000010000000000800003bd60ec4356048cce50017b2509f98abb6fed829afabc37bd83aa54cf33799fe1e1e5fd4c33b210b98f7dbb4693d6ae6f98d9791c8a7394a0ec3ee9b830675450f0b779824d7beea6b24d53ddd66fcc42995dce137697f5edc1ddbfd030cff38c55a52f776ca3bcfd24b3120ccd359069910e83e221e211452b22f366e203eefb010001	\\x2f1acfef57e05e35f8a4248bd2fc2b6047dcf7716b0cc2459fd85786bccbf4a959d50db2a3be7564dd3f1243d2c8c62f2fca2e94f1a5c1dd90b04dfc56270b0b	1677402169000000	1678006969000000	1741078969000000	1835686969000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
380	\\x9bc7c47af81823ba4411b53edc9fa4d7816e7b9c5483d2447722e27ee8a870389e3df26e4522ecc294608de793884cc31dbb56425a9be4891d30fe0b3578790d	1	0	\\x000000010000000000800003a96e71a063c73f8decb226576af7f8ee6b0d244295b0bb758911956b9a9387ec2c7ba5e78715eb0ff929a2cda9eaa29a3e93d9aa57f3e938e3bb00fc86c27e4efc766cb66cae18809fbde00ab94870a12a316236ebabf6a9a1770d4ab930410df6a14e879d0aa44d3b8c0367fc7e7d8a0f5be2e5821d3d5d72e743f6cb14d3a3010001	\\x1d4a0bace14d088f4ba43b63c98c13441e87e7e4dacab8b08817ef0a5c72f64e1c075bba81d775a7c0e5f7012149e7ccb442e1aa655e9a85ffb1eaf7f2ded105	1679215669000000	1679820469000000	1742892469000000	1837500469000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
381	\\x9bb39ac473ce9f3838cbcaa3e52f4474abd1dbb56993afd15baf981a6b6384febe0f1f4d7a6e9a6d166ceea94878f7112901cb1bd5c0f03357dfc8f3e7bf6fae	1	0	\\x000000010000000000800003dc2b2e0d346f3c77e9ddea462a44fd4646d4eea75c493a77a5f44765ba986ee363e7c672c2a29149acb26c95114b7a27038bae1c2470b9ce336ebe279b50495009a36ac306f2273694eb0480dcc9f89cc210e9cec9b4d293b4b5354819b9efe5b19e77a3b1bebfb8b3e5577cf51f46a4bd69fc889056023d1387326fbb73ce27010001	\\x890c460252b37b0316d7125df81bd1ebf5ff17dd59cab385ee41f173016f6115a67f29983ca5e78d3361a536ad223584edd1ce06f35631218ca8e8634cea5006	1691305669000000	1691910469000000	1754982469000000	1849590469000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
382	\\xa01f4bddb4b7d11c5d401fe129256f8436c4518ce389d5f81c6cdeb7d52833212f456b409e6c39f9bca735709fe01aed311948296d014093e5df8ed9e5942e15	1	0	\\x000000010000000000800003dc3ea8c480c8e8c716004ebceef0bd838ffe18677743f7cdfb657db1fbae3d40058b95d4d21b74c7ee75d2047eabbb5897413cfc3eee7825cb1bcc3e574aaf0355a820bcbd4e907c7ca91559645b152206c7899bca6eef0fb3c829496ad9d27a60d7cc2c49a0c44c5e25856c19e2e8e38ece1ceada3140b7b7410d1d9c3d3489010001	\\x6e56fc5799f8a91d3aa56c2341edf5e0ff8829642491f317b8a3045f9b66978264cf89c19477b9ca5b0561d0028e1ec4a5374da7bfeee652ad0e919a9dbdee08	1672566169000000	1673170969000000	1736242969000000	1830850969000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
383	\\xa35f642fe8960e9d02d598956fe12639e0f35f85f1711faf1f171d6c3f266599a6eb4d08a097c051dfdf3ca21df04ad9257dcf69ae7cba4994b7b0868cea08cd	1	0	\\x000000010000000000800003af4784aa9c40346b583b2ed12ec9f8a93d196693ce56cdb3da483b0a80b8a5d85a042728cd0a2fcd50dd2f356dfd569d36d5d77368d91acd3a7c0fd221ea63922491a250f57ab2fd1d35b5aceabca408781985d417a4f072b1184f22aa6b07e30b103a5a1b7dac24bd2e7ffeeecb19a7c811fadb58e4444b0c129a8d10d8000f010001	\\x2b298a6e438374f772f2a1c42e623047dd23601c02c02bcc64002ff845968439274c04796b90c17363e72fdce8b682042499c807a5123e05d3ea1bdd646aeb01	1687074169000000	1687678969000000	1750750969000000	1845358969000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
384	\\xa38f16363fcdb6d12e4b22368d38ff5c723e156d9375ba4a86ea19482158acded8e5c6cb37c42afbae979d3d3b5a6f83e0af75b684aa62b9d52cc7bfd203c2f9	1	0	\\x000000010000000000800003d01b2acef7869815f9ed14a0406fdbffacea17174642f0b6232cbf84a0ed20875913f7701ed6635261e04066b611a6d49135e42dc1a922969efb9358db0abaf5610dc56ec80263762f8f9f78ed4883f2ec2840c7ee2d8f800cfb890b68f9f6755581d9b2194302084c155782c89e8b655ea8f6e077a168a1b0da6e3d11b83e3f010001	\\x3dcd6b9e517fd7dec03f3e59ae3059e285987259f79581544b44f8329d44871efa88d982a47a96bce19d47ce783d8d7b503505a89e15fcd68b5e930f2d9c9607	1678006669000000	1678611469000000	1741683469000000	1836291469000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
385	\\xa4eb60961a155533112100d6a349ad0cd8f2d48adcf294bd95180bbaa6377fe1f89b26f18b75e49566924ba2fc0bff48927a5148b26ebefa0dded8190d5cd3c7	1	0	\\x000000010000000000800003cee17d85170d995283a6931c1e70db4d1855898aa6911037c2d6bb7ead53ff2bfda8eb4c996be821d4592ba4ef743cd1c08214a0f99cf36bd8ba9e1ee57b8c8f665d6e5b352bb4d4e365d1591502db9371b9e392b51f665e3f6d125781351d2585c17ccb91269b0c663cc69c0076a7e1cb017835e6fcd7db97dc7057d9bdb919010001	\\xfde8313dd7f64f2d3a7ce0142940da09ebc201fbe8d753bb88d02a21c47ce079b6ed152a4b8ae634b854e87a011962bb325ce51e2f11b8a150fadd42cf83e30d	1686469669000000	1687074469000000	1750146469000000	1844754469000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
386	\\xa74b30a8c446b17243e3f9e69309bcf1d5fd337506a5092b7da4a853e99d0241dc05ba15436782dc906964cc5229a05fcd1e824b5d7cff0b5de2cb0456d92dfa	1	0	\\x000000010000000000800003ce747fecd98eb0959f3f0d00c97fccbfecca54f0f36df8a97ab5b4dbde976f42d1d94d199964b3af457def6e09c298e5488e6ed1358a81dc0686dee35aa9791a08a2dc5bde9ce31bfaba7a1612b60e39d35393d5a089cef397d835a8be79f45cefd9d273d6bf2f24c6016fb255c04aa6f322fc08896dad1e172c3689b5edb001010001	\\xfc4c7acbe5f9e7ef736009e4658d763321f3501a8d28da86a892d390dca17710361b455269177161c4b5bd9b9e872c7270711ec52fb1691c0c697eab17905206	1665312169000000	1665916969000000	1728988969000000	1823596969000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
387	\\xa7d785d66dc74a870fb220b8688a1193998d4762aeba11791c5c86d43f2a2ad57b6c3d25e71e4c22de0b9e08c82e4b88383fbc65a2cf0bfa4d03818540efbf87	1	0	\\x000000010000000000800003e702d2a9a576ce603cc154d76958b0dd735b679058d9b3ff4de1c5cf6f8040901d86fae6a74510ae83f3cdff5e4601e8c8d17f7687c58eb786a5eba3fe6982d697c1f5178e19f271bf93de55fae3ece4b0e8f6039d46277445a20994a4cdc95e2cce88405ba0c12f2d358aa9c6f735a766e3fcdc89f60c0f7259e1a8ecb71ea1010001	\\x823262b995b8de8022f4c41d9847f7e9cf4d4602a106632debb734638279a2f44c8c92c38372fa9468fa14bfc5602580144cb5927896038e9b697469094a0b08	1681029169000000	1681633969000000	1744705969000000	1839313969000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
388	\\xabafbed812662bcac0f8032cef5ee92538eb2db3a7df2a915d8c8e082bd75a6c7fb3d29c72e10a31ae57b2f321e8e3fbd6faa401069d8788d39b2031b153bc8d	1	0	\\x0000000100000000008000039fbd2c4eff318d1608eb02023abb76a4aa4856c7882533d6cdfca39b46cd0e58ff7845a56c5970e2ec17699f9b463b1fb9b5590e06437405418ab12624949ab8cfe9154196dc8a71b5a622586fdbc8274d3c192b779dfac8bba14d03a11e122769baaec4f11d6a9ec45f8a4a26ef96819b2955bf04f1bcde225fd5c1d25e6587010001	\\x1e4ec96352f00dcde5cf4cc9d3e5342729c109044aab1b7f6523e28a555a342c1057a75617caa4f6967bd85a55e8016dce452dbd262e1cb16eea46194c7c760f	1669543669000000	1670148469000000	1733220469000000	1827828469000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
389	\\xadcbfadc8c71bc21f8d58542bb622142de16f5738a59eb74fabf36feec38d908a073c11c2b0546733f69f5ef039619de260ed5b599b4a224b7346139f6ac6315	1	0	\\x000000010000000000800003bf7e80a0f45e637c327f6215778e1dcfdf62639b6631061f399b9889ede2efffe925ab2c5c3df8847fc942571b8fa5ecd22ab576f9954fa04cd0b368676a87c98a79c51dc767124a46b19412cfdd1cd938149c1d904e2ce09363b98bca58af11a646aa35813c110213bd140b57a89cbe2939a3ddecd612b9fbdb8f5dff869675010001	\\x7cd1ed5d4d4e54e95d1c23697db164c1d9798184acfbaa56a90f8f69c26de264dea9cf99d4d141702422ba36b35e8cd98553c12a31069810c0f4eb41c113af09	1666521169000000	1667125969000000	1730197969000000	1824805969000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
390	\\xad87a06a0d8d81a8b0f1d83186a31b3a3e04950054e1d03ed1fd4047529f43b7c6d9ef1022d64c4481110be16c7c748ae82f9f32dd1d29555d24a3f9dca227bf	1	0	\\x000000010000000000800003c068e1f6189ca347eb08e398fdc3067ea79df85135e856027ca579782b0eac15b9453835dfb35d6cc048a7b45b4b9cd8a275bff2eaa84611969e3c036b8dc36fa37f99762ba3fbc62980d41ee4a19917a4ecb955dda86595c1e35cd99fb2138a2e067338690cef34dab3baa3cfd0fca373d4a608542261c79d3e5d61c740c397010001	\\x6f2bad4362af5a99f4c538569f834a59832c5dd56746ea718dbbcd2d3d4eccedc2de9bdfc5a67904cb7c9800f7532c2149454e704ffb38b707bd0f1339671e0a	1681029169000000	1681633969000000	1744705969000000	1839313969000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
391	\\xae4f037ac04ccb9b238d2a2daf48bfddf5bf6776dbf9ca4398d78b491a2fc0a152fd55de4e66ea8d87594907494237ce9d3bcc2535edc26e7e5fa2adefdf3cc5	1	0	\\x000000010000000000800003c961d5701d4d2d23f0c5779ba0a0378d35b1d24e3bd4d21803c46fea74c30d5ce54453bae57316d84f73e31d7fa8d852b70cc9eb1bf621a8de4a0fdfd06eafafdef49105904bf6de096c00e3594aee5e8567c8c92735e5f0d23bfd1a638f82be6bf382129ad88cd2752d2a54307ab6512677c1e0a09a618ce20eb26aea83d163010001	\\x57a5258917ee967a95e513bd6faf4a44502c198733f4e2a714c7f4ada411676420a714caef8799360720f24835219bc95fde4445a741eb871cb606787971af07	1675588669000000	1676193469000000	1739265469000000	1833873469000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
392	\\xb16720a5f99103bd6a119af31ab69adfe7320d1e8fc442b105d337fcc453a059c3aa6f8085a7145314e679733fb99c6dfd8417f50872783a7559f30462522474	1	0	\\x000000010000000000800003d3845fa11e454ab5bf220bc563ef273a7fd3c52e05c5aaa36b739e5e9772ef7feb834588137615105c03021ba0e8ab75f7605795deabfa629b3a54d9f870e09074ad409f42b41d8319223ad28baeb09aa3c6d0387e07f8cd3f29ca231553bb0a2026d10d2495d76f5c186bc64b0461a5e79fac5fcfcd5321394dc2c1a7eca4e5010001	\\x62989414bd7e21bb2b3fb037fcaeb75e74e624ca6cff5d879c22cecc4f139280c5fbeaa371a9de8a422b5a67cfcb8644b0060742bf75328d2eee2469a0cb6100	1678006669000000	1678611469000000	1741683469000000	1836291469000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
393	\\xb2535e065a2579bc788f1cf187ef1f52ab818d773c7d756615a4a1b9c62ddf5af3e0e9d1e42562a13e65d8f29658081a83df076bbd52db8467e273bf28fcc72c	1	0	\\x000000010000000000800003bba7a2e46eed127929bfb79a0a9cd320cfae0b6e724d4cc029a23c2cd7211154b935910269ab6574ae4aab32a34bf59de168f790b99eb50ff72ce2ede4157a21412baee0c31c62e5dc594a5e0a345b288d517f2f1573317d1a0f66b3301b3ec5056282d01946a0ae04f31132c683cb001bb695ac7328cb04ae559d8b5ed04c35010001	\\x085ebd6f05d3a414aa1563d9f0fcf8fc8a3b8494d4fbcf584ca100ad7bfed0cf2fbc619925165cb6d0354fe3760612c5a15cf7b93eda62d1f8388b0982e9b103	1662289669000000	1662894469000000	1725966469000000	1820574469000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
394	\\xb743191407aff96b7bbb10f737df35d659146b392b0b6ffb2627148de019f76241a7d017fb7327277cf6327989665835b97f9d1bc710528e0723dcd57986e4e3	1	0	\\x000000010000000000800003bf81e2b462a9320c89b77debd618f7fb0a68a33b1592fbbd7c4c7f5d61766d827f360e717eac2649b8407314a110bf0e60bac3991b023707bf3ec386d23dfff27e967652d4fca7b4ae1c260804d093da441a7772e0972b67f624615aa783f9b29ee8e4136b22a5807a9e9b13b2d6f7de5395d45c8b5a95227fa5f1b505e50ab3010001	\\x8d48f766b6e4c89685b51ce73064de223eb599b6f765995e945bf3ac42543eb9a2db54eb60acc51795d08e04f8a226718380b8db5468a76f08ad243f828f8305	1678006669000000	1678611469000000	1741683469000000	1836291469000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
395	\\xb81f27fda10e999c55f4f6c0ab2267549335de3c253d1a9edccc08d9a08c31077bb78d59056f52b855d72a4228cef64918f75f1a8cbabf1e94b530fc079dcbbf	1	0	\\x000000010000000000800003dd157e1932e74a766e3335d3c1000654b67693c3095aa59cbbd89154aca419a0bae80912de0a5652a468588cd33050d1a2d398693ce58459cee1b15d43fdb9d8f180a927d9ca85ebd0922f1b855518bddc27c83afc0786118cdc77c8ad4b412c101d4ac67ec343c2af107666b8a6f6f6ee3f3eb5231674bf4af9fc2d4dc20691010001	\\x6f3f9d000e5bcaba89a56f44c58ab7da16229be233ffad82314a524abc2cd42fe32a9b369b6e608a29d816e0f7175cb5f211ff367318e48f0b38b87ad796fb09	1669543669000000	1670148469000000	1733220469000000	1827828469000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
396	\\xc1836b4d7042a4b6594c04cb9d344baafb6b888af9c406c05033aa5b580ad9c0d88352ad7e73037cf3ec83f27780867f1be0d3e7f3e16a32dcb45ea034cc07cd	1	0	\\x000000010000000000800003db19a58d0bb6e1e3ff2728ae2205a12c7e434e4b83e9bd166a05a1d7ae60fbfdaccbe9dc7ed2fa526994d77c36048aa6ea8e189c1aa9df25f0eb0bb201d61dde29aefa66ab38f33cdf7c110eccaf7986a8f16b7c3df4488b80c8ce99fe2d728c99ca3e1d0e5df950decf5be07fff03cb61748f820e473dbc929f08d7abd4dbe1010001	\\xf32e1f123d79b98a8ba177ba5cb7e7813b3d68d49055cc02ad3e0c3f9acec5908e48dd6cc56755207ef3ff86548e1be5d846d83ac50e39a47d1c4cfb7bbddd0b	1684656169000000	1685260969000000	1748332969000000	1842940969000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
397	\\xc1efe93c1b13e0a15cc247ed8eb020b4896296a51988e4dcd0d906a3ae4c6f9fb3777564c8b9e672dfd90b57be67842dd06833dc3556f9a3016c4b4b3645b5e9	1	0	\\x000000010000000000800003b3d1566bce7b8a698ef8012b1b13abb5512750758a5267baa3174df6758d38c7624476cb4feea5abf332a7f563927266d0d1f107a6bc3bbd4539b1d674ddcb0a108a029ea966456e73796fbfe37845c0174cd46c27f79a19098383438b85efbeecb4f92072d39bbb46a36d36ee4ee7daec746cca1237a251e7387bedfbb32493010001	\\xfd9075faefd92ea4136dacdd3b700cab85b3f0121dd6dd1ae79d23f75becf1db2f8e7b06efeaf25ce395e9019305a361e4784801e3698ab343c33f62941eed02	1660476169000000	1661080969000000	1724152969000000	1818760969000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
398	\\xc2830e0492a67465a5d961ef51ddb64776735a4df3ae52ebde77aa0ec0e4b6859b9b7e42996f86ef93adb34198fc804f9bede70e3aae0e8394809572912a719c	1	0	\\x000000010000000000800003a42180a16018f07bb0aae1a0ee6002a4f5fac086a49d343d70960a42866a115df1fe8612e33a8dc4b0f42ce0543eb374c7c9e00bdef92b47ea72d6d56814a506ccab5cc55605f4a85a0bc1e09a195f7ebc7d5c7bc2f9155a99a5f5b466800da5d11725248c15bfc6e587064156c07898a8cde13a756a05fca45fe5c53e52128b010001	\\xf3927dea94c9b210d2c42162104fe05fdad119d213204f61dd5a55ada34cadbb2031cdf97ef3a9093fcca55116db614fe7cf1e98bc0353853e5e513b3b41c703	1688283169000000	1688887969000000	1751959969000000	1846567969000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
399	\\xc3a360d663dba2dc43cd52b8848d6a83b735b73769365879a4591351595c3b1489c84b4324e78a4c585b01a7cd0d2b522eec4476fff31a056165ed98f03db873	1	0	\\x000000010000000000800003c250aa12af83e1b3b045470858b6b1c86083a5847b204bba4f2c78aaa82ef7edfffee5efe9aded056a70315eac84bb70bfc018b1f605fd02154d09dbdada543107477031a8046b5496c4d5a3a66eaf66f51799db1d5ae7fb24f75f42723931002900f898895c807e282c1859bd5062ebe856ffa64b369c70aadb92a1847a9085010001	\\x0f21f411955955ba97a2e92ec827b8d2ae7f360eac5545b13a4c0e043236975e0fcad46e5d47e11bf4ca5d1cd53cbacfab026ca908f2d2a6e3f517851935210f	1668939169000000	1669543969000000	1732615969000000	1827223969000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
400	\\xc36f7dbf422d0d032472120e654224e6ed27bc125cce43b60f23761f8cda52109ee5514b3cce7530e8351ed4602ac7b0f53b49c40021ba28639160ea7e24649e	1	0	\\x000000010000000000800003f71f499ca29d54954e96f4faff34cd2cd3dbea9a59d573fd776e938929fd1fe2c799d0a3315d74136ea7a9f9962a0560b20668300632cac1a68dbfb8b72cb3f5adaadfffff47820b17fbf7e58a80e7de1324a32915e413fe2aa01e5fb352ac99b32321bc356f43a07e2a49159efb0b5b764ca1a38e5d534d2017319851b474af010001	\\xc2a5165bb039a6b3795b2b07a8445a4db46d13d5897747b894e216d11f4fb1b0138867a4d7cbaad701cd9c6f8e5df61d690944905942379029e15e288652470c	1667125669000000	1667730469000000	1730802469000000	1825410469000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
401	\\xc58305a467e2b7ae725a5d26249cd94667335730398b0dff1bc9bc6416dbfb9094082ca7879923b4af9a932047be2e1bbde90cb435c6a163f46c0eb150472c8c	1	0	\\x000000010000000000800003ad3c3d93ca83dcd050a1633fb5810ab4a77a60951a6c80929c996b9b810bcc54534d9cbbfed4f6ed4e7b8ed1dd5699a7b166d84155a6c5c62c0ac7a47f698f715ad79979170ab627ccc83ac2819a8a1e1e18c696548d3b77748de612b18b271cd3db6ccfb8524e75846be69bcf1024ead252273288967881af9c3718cd23e627010001	\\xd0f369eddc31462be07cb9456cb386f01c71f6ac22ba66a8f915b5b319f00967c445b7c8fc18aba9015a18d335e305b057cfc6062f557d5812e8a9cbf1705f00	1668939169000000	1669543969000000	1732615969000000	1827223969000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
402	\\xc60b8cf39d4c87688ce818af260f9eae6b7af04e3c49bd9c9515139a974203dd6a8a28de3461dcabd4442b69ada7a67e139cd28dbd44db5a34ec83dc1ebc7f3d	1	0	\\x000000010000000000800003eda4ed90c56573f167c52428c3987ab3b28996f211557010f1a20607169a871c06f202786dd2c1c45e03e4e7e6d33177776757d4dd21310a2678994597f5305f2cd7321451ed3d7c342751f15a15e42a444b45f3f6ff61737782099601646d0f787e628006de5994542c4e5401554d5d7b098a3cc50dead197f2ec0994fd9639010001	\\xe17870f2bc7924c8dab1bfda7c19ac7cd4e5c63586e26fd036f748e97a80443cf3e01d372b1fd669a5de2b09444a243b59f25f4965634a1040c77b74a5bf3c0a	1680424669000000	1681029469000000	1744101469000000	1838709469000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
403	\\xc7e76866a25090f970188eb48defe78566c7b26f0b780019d851b31dfbf60984cc4f73d3422fa883b660e079e86b4b86846eba1febd0543ec1e886149112c803	1	0	\\x000000010000000000800003d279244af20f1933aeaa07ebc5de9f869e83f9ba97d784c19e5dc7a88185ce73c3d6443fdb8803c63a30a56aa242cda088f42b69fd692fbd2ab32b3d16a5dd97a000e5462ac78a7c98c31f83a4f086810e2ce319cfdc73393f1e20817d61d6c87e0332456506128ca49b8ad2ab94d75454fb29a9f0cca9a1d9ad7227e2d1c573010001	\\x16c0f5e98d3e0bf4cfc05aeeb8b3a45ac56537c40ab91aeabf6ef60ea78aecba05ed59234a903803ff78e59fcb1856b9638600f37d92e2d016b2a0b0407c7e07	1668939169000000	1669543969000000	1732615969000000	1827223969000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
404	\\xc71ffaad2869eec1aad7b5896d5dd91e838ac84c6a600a7ff2b241494376dd6122f35455ceb671b2f3d0ea8af0bb4e1a1b2f89d83b4bcc8bb33f9c886f41a4ae	1	0	\\x000000010000000000800003e58752a339149ce2387fcdedb36b2ce0ea281dc2c1886e4f5699dd72c8d0c86552d50e6fc6e4881a6794dddefddc7b7e01c01c7e512cdc23172692d1dd474c2716ef9bb0ea880e2dd53971bdec452b8808b3bbbc22e2bba4900891a54c1fda0cbf36ce9aa2a03b928b9d51e538ae6bd15cef9e975a8a127af1af37a1c11154d9010001	\\x578cb4891a192f27a23c14cc92be65597cbe5896ef607e0ef721f6661c4505f788d787207ef3d0b4b8b5b5da8a2f5d5c0655c8037b3cde5b634167bb6c293d03	1667730169000000	1668334969000000	1731406969000000	1826014969000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
405	\\xc8fb6932e4f78ac4e359c5cc1a86230f78b8b7dcca68d5ea3d8dc2c96021903d0bd8bc9ebd9e8b9bb56e4935a62db1f28ef9d8b28ecf4f3a8751d51eeba7ffe0	1	0	\\x000000010000000000800003d367d428c53509e6829c05cb2be0ec6b804bf81aa24545ec57bd43d45de7f3457a4d8ccb27a37bf1986a2e7c9e32104698b8cf91ba0281fe0d3c9ca09f8441b40ce03d55252e5f5a29432d3373a6df2b1ff86837f99e0282285e8055196fa48684ff2268e18e7e856707cdeb63f8e33d10eaa1f9593a8f0245c0f24a07d2a405010001	\\x265debaf5e22b45538ecb1d564f5895f6bdfd194a3c59f4ce9aba1015055a18a9c9d86939fa8ba61c94f55c723cb990428ff0c4796b5f3b71a90e023e165de0e	1663498669000000	1664103469000000	1727175469000000	1821783469000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
406	\\xc86bf95e8bbaa2fcf715f485646dbb2852f2af3f01c263e01c8b43247be8be51068812858907a8c005c89b927b8a0650a2612a347b2fa5a84c47254ddf794eda	1	0	\\x000000010000000000800003d0d5433c33d7c3f341d7972b8421d00dc9cafd210411386e0066f46b8e8a15da5444ae59161d557cd4e43f645ea661cefa7c3be33e5bbd5fd09ccfa8ec39dc3a72acdf8c5c81cf2632d7456043ba077b1e4d3446c3f0d048b352e806b9017cbccde54641205af40c4780b325f03ce188650b0c06c9222c59411667eda0f141dd010001	\\x0c22297d1ab5a191924e008bf420d73f2657a6a1873f2eedd6c6b106f59e8a9f0fa0d2aeccb8f722779229d35755eaec21d54c910ac6ecc2871aa32ba373e500	1664707669000000	1665312469000000	1728384469000000	1822992469000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
407	\\xcdbbfc458a0f2410f816d9caff0641a9c1902cb0b56e4e087145d734cf6ce64ce7be3535ba901350e3a4d015514fc0d361b3ff635d927610df11e63c60985699	1	0	\\x000000010000000000800003f3806707f2430b1a59411755d989976049f1b76c37c62018e9319839b7a7ea7d3bd4c3bf0fd9e5ec09b788227787865edf6723649ae79e424b117f9712f8f1e6ab07ccc1ec3b3706722ce277d53aa8c660e596261698f29cfe2c23087bd89c377f4c16d466aabf9e42f2cd1f53749f96f73fa7614ef0012e541d02731f7c30a3010001	\\x20c1478c1f7fbbd9d3c1cbdbc7fce4511819c32d9d2b5851b82591aa860ad1e48f1382ef574200ebc54046d061d7fcef69f867ec78ce4dbe4fc9423eca71600f	1666521169000000	1667125969000000	1730197969000000	1824805969000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
408	\\xcfef012e4f4bf182c5e7e1b708df6b938e04362770ddc4fe887b1af119a25d34bf510a8387c4e7ad105d85e2bc832c33a7e251ef6845d2b166941feaa7487149	1	0	\\x000000010000000000800003c4c12f265c76c77a17b7860e137c62edb753401f01f34b272bcf47868521607bbb6de9c72b34f21569a6952c5133ee060f5aa1efaf239b374fda2dd98ae5bd0e8d83d8b7da2c112354ab0217b507c2a4f174ada07085c8eaf70fecd19a5a4d737a13a81f4168efc9703378688f89d7b4d6ffbc7e0cdcbd1812256df3b0adde03010001	\\x3d256339fdeef1ee4486fbf2516b5654acfa6a9d93338ea76f814a7ecb4d0ea05ba7593712635ff0808bf40797731addfdd44ebc6e7e7aafc0d8f0525c02c40f	1661080669000000	1661685469000000	1724757469000000	1819365469000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
409	\\xd01bb1fd9c277f21e65875595cb2fc019e7b3a70ed05dcfa5ec579aaa2e25252ae0aa67785a179a5e056a250250334689969c0871caf5a529ebf7c066c17e89f	1	0	\\x000000010000000000800003e48e4b7f3aca1da9cdf6d8e169e34fbf422b0cdeffd4cc4d892373f65c77bc46bf7e9e6fdecaf48ab7bf4b8d4f6b1038554d2a71c538404a2c6269473f0edcc66882f297c952320eb9c43ecd838f06d58c256e08b13c152d9e0a93150fc1575ac32295cafa02574cd26226fbc5e7c4b4a97778266a0db21406b1a37afd67d5d1010001	\\x64bc9ea3f3acbd80bded8e0338eac9f034214d0c5a5a2eeab1ae9de2a2c80ec3fcccd2367ef35ea03a1fe89307945561c1fff7fa5bfe5dafeef2f574f0ba6d00	1664707669000000	1665312469000000	1728384469000000	1822992469000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
410	\\xd05b1dc5469e78e1439749f7acf8dcbe16e80109a332ca9ab5c5d3fbd7b676b10bbf6c316816c606110410b8a64914d3a1f35e939ff2298da87c2002d3b2ea06	1	0	\\x000000010000000000800003de9e18bccfaa69ea40370c077b570e3e5b8ad922a2a332bd95ab4af702a31611d1c1d79d393874d2668e37dd69b7965110ebaee713f65d9344478e87ed766055dbb05613f958794164325ffa419e8336cc899dee2df80e7509cb6bf78a57cc7d62e772b95039d1ea1b5cd74218de722f1eeccd663b34a76332d98782f973ead1010001	\\xe96bba27fb13d61f40d37f9a3870c6abd80b13a1707f9a3a1648f1a4b7507833000699cf3d5d6203d75b19ee9d8ba02dc1c34f5cebdb7277c8002993f3d7d400	1681633669000000	1682238469000000	1745310469000000	1839918469000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
411	\\xd2b31ce3b6dcf1a597a9f193b5241af4580bfb3a3af6bb0c35bdfb87352d4470d8b2e58d705953a330b0926983a01c74fff8bb4b477b61eb94e65028bc520c07	1	0	\\x000000010000000000800003b9250421789242d29b9141f57deba11d586bf6db7b68ae970655213d15ac39b79de730a55141e952a337176dd2528d4d7483aedac4f0a09fed657510fbbac0e7e226de43c9576a7c9c7112c9f40a7a1727f46d3fe856fb53c6513db2f26d74f1d0745754c75f1cf5cbb2205df237596faa7ac626ad6e70e4cbc6c1c0215b3ea9010001	\\x9090b0267c36a53bff522040b995f4987edb529e706b202dcf3351239c82394ce9e7ee9c0c62db25ba9da73a26f1f7c81bcbc9e2da39af76d0b989f74011790d	1667125669000000	1667730469000000	1730802469000000	1825410469000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
412	\\xd24bd3afe9953d915d8206159bf432d44f04f659ece8d0ec26934f3397b152ce36a326ca46d8c2caf0de7f6953e65f351d2f9e2be8117c36b4fb399ca483b128	1	0	\\x000000010000000000800003e168af9ee7f22ba8646f55b04b3e0e371a4547b2289a5aee59b829195b6858aeadc10817df019c14d276e97ac5c9337ece1bd8b4110df4445c4c2ea916d1576e81bd6901429324cfdcc79ca073d4c661ecb9a97dcfa8a617e2996a471fa1736a212649bae53f9ca224e2f597807c37dca6d3cdd77816a03b841f2fe7f10dc2d9010001	\\xd56b92ae3bead9f0bc9a408e918231a6de2041960a5c2b91f3d198b7590bea137b6c1cefd2aca24536e0cc68ed115eebb99cf6be439cb94ccc16d524a952e103	1676193169000000	1676797969000000	1739869969000000	1834477969000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
413	\\xd2b3a16710cfc35c9ddd924b1bed427b2f988b600c8f08a08a44511449fe49c380d2abd35c81b06607f15f573a74306393f7ba29abf90ee146ff48fe11575289	1	0	\\x000000010000000000800003c6996b91925eb0fa3cab50648d1b7113ab9dbd1d92a313715026cfcd2fe14a66e74d3495eef5a510e6e87a7d5ea46cac1f188ba6a248a7bb9fb0dd70e2d0635735f186090f12b4b3670e48aa79c2a5edefe297e0f0b7adfd9708370dd16278e5eb36b0eb802038f60301e3326f39a1356e5534ebeca7a957df7a0b6176ca971d010001	\\x9ff93d5f7bb073479c23c071f248244471aa472d21b4b0857769269c36eb21f81064b74574b36592457c0d86b0c48e8e221d6436009af1aadb8734dd9bbf2f09	1685260669000000	1685865469000000	1748937469000000	1843545469000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
414	\\xd32f97170e9022d2f7116a2727067eb097cdb488ef3bb10b08f0377c97479031403ad6ff1602caaf944585970df331a514125a71101d0c18f222b84e697a9560	1	0	\\x000000010000000000800003b2bbb4904d2805658b9a0c146bf6aebea5684f5c9265e1b77cba1e34c650a8cd96572b948179784435a07ddc1efa8c46aea224fa113c6556af059a62926ad24fef745dce9f26f2515f48698253be4b5b7e42a2f94bab2c0161f5b7713a1ea802891754c0a2d5043eeee497c68a5e1b63d901b4ab49630627b516717d2222efb7010001	\\x6e020b37fb0e967819d7cf023e4424b3880469af3302c1fa2fc50b8af21e78c0ba68b9005d7280cb1a4725795fd875fbcc49be3190765ad748dd6ba26946d60d	1665312169000000	1665916969000000	1728988969000000	1823596969000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
415	\\xd5e774731ccad526608337a11396896de3241ea48f2a22637fa41a840f6c503e00da3f98e36afb44a33a80827cfd02de2f2eddc70f50cbd0ec908924f6288304	1	0	\\x000000010000000000800003c0587087a318bfcd27c9c20db22a2aa51cb422a60f2f1f665f19042a550f21cf1a5a1a92aaa2531eaddb88a5aaa5498f6e71039bc08f7a99ba2f15cd48d2bea264bd34ef035721797b7f200bf65d5522b0437926d6d930985129c40250e1e31132a623c1252a90d563e1656f82cd2eb593c68ff9f082bf74575532d0751fe68d010001	\\x190b4325f01c231e2839ac41ed7367c28917da8a13c86624251970d93634634d01503cee4ce3bc6c10a94f2e6e3a2adb9766f1431b799793f8ddaca9c32e6e0a	1659871669000000	1660476469000000	1723548469000000	1818156469000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
416	\\xd7fbdba5502efe02298999f3489cd908b1381641e428be83d30836b4dd323ab2423b91426b7af721d1f58990461e8610cadec7a9609ff821af658f9b4d9b0cf1	1	0	\\x000000010000000000800003eb515c8fc755ed0ac1314964446856561cacadfc85189442f9b978eb55383f41a115d8474b7ac802349bfef227a9f4b6c873bb843d4c6119b88974849b9856a7f638179848607eaaa5c535b2ce2d729ceadecdbaac523fd8092f5051163451d5fb013c45ca4de53a052e633f78c6160fda66d96ec0efe990468c6d844ff4ac41010001	\\x34616b787c2e0fa4e8319af2d7513851177540b9e4fbab642d80225880bb3ac193b11ba07dc8c9c149892d075368968d53ba10c7a3a6954e603a91b45a8e900e	1685260669000000	1685865469000000	1748937469000000	1843545469000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
417	\\xd9671bca3f88c11162ad9ed463e1ab6d5e4b31d948bfbb2e19bbce96a795c12a95fb1283d19cd4c6627563b59b9c2ec73e5727ce5488f1d19ede3d91ef38bed4	1	0	\\x000000010000000000800003ad642a5fc7bd66cafbf64fdd90cc833354040f6d1522d4fe7ebe1d531f6154d2dc012cde292359677810520d6cc2fef89ba528dce44933fc8fa47677ad4287b143c2ea34a562186aa1d2b7e58072595b7f5f488c47847d42fddfde8685a5740ef98a21cc889bc00c828cedcc9d669f74f9ed077e815c6bf4ed5ed148f119baf1010001	\\xe144a641a1c4280abe88afd46273b65381ea709b419083b50931a275dff5196fda74ca00a498d193df08bdf74d13116eaa0585a3e2dd7e22ac72546134a30705	1672566169000000	1673170969000000	1736242969000000	1830850969000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
418	\\xe0e38da6067968b9a34ded1f863ce8f1e6944673b3e7b0915a1dc4aa87af28d7749af05a792026116e0e52e34d8537b722972eea54ea974fc4b77ac14ebf6bbd	1	0	\\x000000010000000000800003d63b1b9a56d397fdddd1af5ff460445669d45e438eca52b64ca1cdb7bc874bc1c4ea9d602dda91ff907a43a822ad5dd68d606142361d66913422c9f1f6005fe432864028f5b71fef0d0b778b2279cc4b701c47b97cda8964cc8efc895cf1a2a1f98ca253e3e742442562aa6084ff0f04940af8726ee5a75cc45673d560dbaa27010001	\\x8cf6849b28e6f40bbffdc3b20b46f5c0aafa2c4da6080b9cc51fcc9e9b34394f9be2b60ee108b8a75dd47d3500c688476401b8536378a71fc226572bd2449f06	1662894169000000	1663498969000000	1726570969000000	1821178969000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
419	\\xe61720521290cbd557773008c11a4ce7313b3319babf2f952857b856013648be9ab1367aa4c8ef3255250fc0b8d914d0c30244201cbd5658a98401ab3b0b9f9c	1	0	\\x000000010000000000800003c4fc2a12b90a6772110f697fd076e1f9ba95bfcb25533b8d8c4e3afbe3d483b31be589bc668dab199978769c75d3c8e4a84103f568f480ede095c2a136b79f40cc9e85645b6a1e886240a66eef7aa9f05165e8e0bcc39e18746ed8f1306f41ee05197ceb9340b9a378cd8e30a203ce6ffdf4a367c3f88c0bbf6871cffb22ee4f010001	\\x1883d335b7581e8ea3944c42bcb96ff8e6f558740fd02840a2e32089386beb15414f69bb5376b46cf5d550514f57b8b1c0a43e494419aa129f7b09de566cf401	1687074169000000	1687678969000000	1750750969000000	1845358969000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
420	\\xed93ca842e9c2ad0b5d7ac22b34a536582e780231c9ee9678daac4fddbd7bf7758d41819494fdff9a30e04e9bd372f9d9441016f23127837eb220eafb6f74bb2	1	0	\\x000000010000000000800003beebf1efb7f8f1e5f782390bdf137735157d552fb75198a1b1828c5b7f76c3009fb07da5e7e2e5856552f9532e953976ba13ffa90b39029b5da21d5816fc96498436eb9eeb4168b04e9a7d923c1d75674cf77dc6cb3a9dd88f107ddc5d03aa9fe10edb877a22b067468fb6c6fc1232fbbefcc75721e243d9b3121ec8b4b940c1010001	\\x9a71c09b9c0df189744bd7e834d1a5f897df2af5a328cece9cae3bfe3cc97053f59d8dba3f10e5193ee853ba63ffa4f704e1696d8721226dffffa4f6ddc38f0c	1676193169000000	1676797969000000	1739869969000000	1834477969000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
421	\\xf1cb3921a3aa7d5681001d7e2ddf22807c902e00fda71566a00b73fe9450a95bbd18583844bf33213dc367da385c4c2605944d240fd96719c870747efe612c2c	1	0	\\x000000010000000000800003aac1f104a11bb6a006c845bd639d477ae376a350415f9a5dbb461789112bb522274241226dad112fdda819832ef49f961a5fcfbdcfb8a8d6a26090c11740f2d512805c67f7d568094901a6836f7dfb1ec70822def87148eb5d675e7bd105cd056987dfa5655c41fb61d526067172a58056055b2825aeceec489aca74b3ba9aa1010001	\\xffe8e0bf27bcbe75e2baadb000e293d6f0edee4e5e5945f08e8007ae426e9531bfbf63ed3443293a54e828c54fdd062bad45c69e7c67617060cbb991e6d2c609	1672566169000000	1673170969000000	1736242969000000	1830850969000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
422	\\xf34f0c1e338de59442715ff5a93592c47a01f5e201012ccddb3e33353a06e9103ae2bf4c938e7901914369a20ab4458290501fa5393b88e637f7e4e77c39a68c	1	0	\\x000000010000000000800003c1d54a441181ac77b1b4480a5a04b0567df1f1e00b73b58e4af0203cd94b0e613848c6129d769320c03a414b28de2a3eda322a10542d8c5e476c851ba762c6c37c36b39b81286d89074a2dd54f799ba617bce70e6cdf59880b344f2c2f645fb3ff6c3a78c8f36c264560beb83c7c72c6d1489e8d8d93cad68a49a3897843a267010001	\\x796f832db58dff1d6e2b67dc7b8a09a931be510c7acc58258b8f668ade14339850610b474d120f72f02d47aba0a18308bf50ad9cd2e82b8323d3a9e2c8150006	1666521169000000	1667125969000000	1730197969000000	1824805969000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
423	\\xfeb3c8247ceacb6691cfa8af4e0b566b59c27d89654380f13f63e46eb21565412da5b74a034a2a1470d97ba2139432bf1afecb881e1ee64422cd139a9dba623c	1	0	\\x000000010000000000800003c209b60cf3524a52ef77081994cb315f6ea8ff7c1af8df7fdbf2c3b8059e6d2157e79e63785d9607a48d3e5bc43c56f988eeed28eb0c736077c3a4b3c2b60902c323314ddef74e48b81a6c1b398ce0f31f69dbb53d7798afb6d2f5cf022f3a205db1368dc5c92ebe5e3498c14ac59b3e7e96bd299c7759c2cc7c88ce4997cd0d010001	\\x3a67caab87343737dcdb0e2eea3de5291f4378cfbdfa235478165785d74acefded17110751ed660eaf17cf02c6ef0db4a3e2d232ee979e7f08906cf3ded2db03	1687074169000000	1687678969000000	1750750969000000	1845358969000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
424	\\xff233bfc2ff54553b141d40a8fe40fbd1580b7e9c55a4d2bd22cd1f74b1c0962dec8dc4e358fc0b2435cbc3c86666bb2c5d50af6a22f10d371316651807533f0	1	0	\\x000000010000000000800003b8375d9abd4cf7a35f03cc1ddd3fc634a1f4f9b4ebc0429267ba95e2ee295b2ec7a081d27746d57c895594245a8b99efe257954194c7dd3617716f79394bb39cee84683056294875db46a69a23b7763a3d5521792aed526ad2e717c99fa05005a6d9fcee74a56a9315f163c8c99d0eb88d258d62e1191aa3c0af17028af615d7010001	\\x7005198d802fea55101522536cc8cd4fc4f5ba74eac2d4fe3d823fdfd4b102cf2ea2093bdaeccfafa28e2caaf4dfbba988b3933ee83cf57c8a7fe1ed3bd8b30e	1673170669000000	1673775469000000	1736847469000000	1831455469000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\.


--
-- Data for Name: deposits_by_ready_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.deposits_by_ready_default (wire_deadline, shard, coin_pub, deposit_serial_id) FROM stdin;
1659872599000000	896507727	\\x42dd78f2c728a422df6a57963dc060015a00e688da482f8f36d3d3eb902379e0	1
1659872631000000	896507727	\\x078f0622928a34c823cd80a419ed70708b38af4cf9eb5e53fbe63f9b0fa4eb2f	2
1659872631000000	896507727	\\x08a01f5dc004bff630a90d20196c498e1f24ff66b2888931f1d751a67c6a9314	3
\.


--
-- Data for Name: deposits_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.deposits_default (deposit_serial_id, shard, coin_pub, known_coin_id, amount_with_fee_val, amount_with_fee_frac, wallet_timestamp, exchange_timestamp, refund_deadline, wire_deadline, merchant_pub, h_contract_terms, coin_sig, wire_salt, wire_target_h_payto, done, extension_blocked, extension_details_serial_id) FROM stdin;
1	896507727	\\x42dd78f2c728a422df6a57963dc060015a00e688da482f8f36d3d3eb902379e0	2	1	0	1659871699000000	1659871701000000	1659872599000000	1659872599000000	\\xba2089cb2f17bd91e30f4e6d20dfc2b10515a267db1c03d758b37805b0133d4c	\\x7722f091ab62c51e855e3f7ec4c484d25bc2f1fee5858fdf9179f3784a73483c30c5cd3840e75422a2dc3c908edd7d6d498bcd0b842f1794aeb82f79c03a8e3b	\\xf4fe00da2b348c4a82242d99db3a14509e7e2dd1575378991376b8fa051d13dd5c1057a324b3c585693236da1dbed66d1385d76c37b2be42ee5a6f19b83d1102	\\x8eccb5e74a640607cc6707b719f94ec7	\\xd31e3f48cb5318906dbbb7948326362f41604c7a728323230ae82aa995f27400	f	f	\N
2	896507727	\\x078f0622928a34c823cd80a419ed70708b38af4cf9eb5e53fbe63f9b0fa4eb2f	13	0	1000000	1659871731000000	1660476535000000	1659872631000000	1659872631000000	\\xba2089cb2f17bd91e30f4e6d20dfc2b10515a267db1c03d758b37805b0133d4c	\\xca4d3fac6409eb06709e4c59ecaf6175a4f7de9db0acfa399532abcc35fc33bf2030d930d00d2326f459836ce4fe5e8845abe38817d8cf658ab1239b16eae0fd	\\x9682dfc19c784ddacadea5ede51872117148882c957328c9e74c68a7a8680d4291a41252d2660a37fa230400904b9df2213c7d08763f3f9a3151e81a7b906c02	\\x8eccb5e74a640607cc6707b719f94ec7	\\xd31e3f48cb5318906dbbb7948326362f41604c7a728323230ae82aa995f27400	f	f	\N
3	896507727	\\x08a01f5dc004bff630a90d20196c498e1f24ff66b2888931f1d751a67c6a9314	14	0	1000000	1659871731000000	1660476535000000	1659872631000000	1659872631000000	\\xba2089cb2f17bd91e30f4e6d20dfc2b10515a267db1c03d758b37805b0133d4c	\\xca4d3fac6409eb06709e4c59ecaf6175a4f7de9db0acfa399532abcc35fc33bf2030d930d00d2326f459836ce4fe5e8845abe38817d8cf658ab1239b16eae0fd	\\x8578c6337ba21d9c97361e7f87b0e71d84d155ef49c16929953f9f343898f139d4d75a4c20d7220bc35957bdd42a9927c7777df4604a6673d672feac12e0a40d	\\x8eccb5e74a640607cc6707b719f94ec7	\\xd31e3f48cb5318906dbbb7948326362f41604c7a728323230ae82aa995f27400	f	f	\N
\.


--
-- Data for Name: deposits_for_matching_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.deposits_for_matching_default (refund_deadline, merchant_pub, coin_pub, deposit_serial_id) FROM stdin;
1659872599000000	\\xba2089cb2f17bd91e30f4e6d20dfc2b10515a267db1c03d758b37805b0133d4c	\\x42dd78f2c728a422df6a57963dc060015a00e688da482f8f36d3d3eb902379e0	1
1659872631000000	\\xba2089cb2f17bd91e30f4e6d20dfc2b10515a267db1c03d758b37805b0133d4c	\\x078f0622928a34c823cd80a419ed70708b38af4cf9eb5e53fbe63f9b0fa4eb2f	2
1659872631000000	\\xba2089cb2f17bd91e30f4e6d20dfc2b10515a267db1c03d758b37805b0133d4c	\\x08a01f5dc004bff630a90d20196c498e1f24ff66b2888931f1d751a67c6a9314	3
\.


--
-- Data for Name: exchange_sign_keys; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.exchange_sign_keys (esk_serial, exchange_pub, master_sig, valid_from, expire_sign, expire_legal) FROM stdin;
1	\\xc3324f7688826888462d1831b4b57552f614b47f7fd756c6ae66074e17e5d195	\\x36bc27213f27d2b889b1a601c46cf3f50b4081710b0fb78a64e5df2f8deb668d2e78889ed93a3d2f625b08c157833c196e45d1a91b424f7bc11d406fba7b2c0d	1681643569000000	1688901169000000	1691320369000000
2	\\x47f07598d3e34ca96441ad2d9d863ef19a2814fc5494326a961519f6ff3836f7	\\x437698ee2ae6a2a992cd8201a6aa9da2cdc7b01416fc2ad2db23d05493e8c69f17d5a3cb78dd68daf15bb1419619560985398630553f0e7a6bd555c9bea91607	1674386269000000	1681643869000000	1684063069000000
3	\\x2b2c11bce0f007314cc6e2feeb837f91353866c4c0e71ec0f22d3752c7bc188b	\\x449a1bcce10c09835445048d24ac0f4f89d14e12d099d0e8383eb9827d61391801ef81cec947c8eaddd573451612302b9e96ea49de618698a7d7b88ec40f7404	1667128969000000	1674386569000000	1676805769000000
4	\\x0c2df27e9e00661abcbf6f9a6986568e211eb396d619b2b147d6d52c30f6ab82	\\xbe9dd7da6fde8b00dc9b016ec044f682adddcd0b61f92fdea10fe231515ec0bed8281e257a56333a72759ebcf008ac2632193319af77cedd9b6afecda1e9cd0b	1659871669000000	1667129269000000	1669548469000000
5	\\xf30aefe9e02a0763a7fac40a1ec2b001d4f5c925e45805b799daf859e7df36fc	\\x3d7a456ffd1f510bb3df18b719aaf928c6aead7710adfdc1c6808d10019d570a0adeca8c2fce93b08e4780a0e666376b7a160f4e7767eeeed0248a7825866e00	1688900869000000	1696158469000000	1698577669000000
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
1	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	0	1000000	3600000000	3600000000	31536000000000	5	\\xf241496dd79f7e75584e37535b04548668a1944fd6d3ea210a42f0da7e49eae9c58774b0e465132700e5c4359c48d406143fa9234bed7b9e58fdc197bffeb400
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
1	162	\\xcf0841a7b568941581a12d9eeda95fe6dbd8c6891f7b8a427c4fa69f49cc5df3	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000516649e52b6979d89596138fb7be48cee44d389ca665c0bd943a428cb31994deddd1dcc133728814bd5c51cf3807b2b16604dc9322cd4e582d241e35ca1fc66cd9000ae0c26c6aed86f10b5ca83e7ad3f66a388a5a235fe4dd97e3330a6290a65ef4ad032aaea35889d956a1b2aaaef0f24f78491ae433fd11597a304be1ddee	0	0
2	125	\\x42dd78f2c728a422df6a57963dc060015a00e688da482f8f36d3d3eb902379e0	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000b7d16ccf8954a188bda856d580c8f417a713f88c1ac6ba309c9d5f884e9ced94c610268f86f1aba06dffe848f3d2933409f7630694e3fc62aa56715bf171802802f0dd4b9e9ee5050e31a2768d1c6e770e4951b02ed9ad784e8228cb21b2866682fdf931bfcd734849d53b54255095f8d269b03c54d1440041ffa66573dfcf58	0	0
11	20	\\x9944735e0ea45e8cbe2c14483a949ab1dd793cdb18294e7953401b7d06df8c3d	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000b3dbbfcd46b4e339b769d74bb90079dd5c8694680f3dad295e8e22b0196361e69c47287b0f56de17bd4faf278de6200c672ae0a0859944bacc603472a84133acfbeaa3cae3e858e0af651a8f1b5b2265c468c9b31b83f31c35d2a064867e973f3dbb68ff529536b3fcdefc7064c841460a37beb83752f6561ba4b48d27b65e76	0	0
4	20	\\x2235ef0bae094727c4622a027576785a8840d9271c350aae32aee2fc9e739a3b	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000003b09eb7a7df176ec90b703f0e64abc4b280b25e6edd15c642c8a510fb9cfa80429d183523c262cec99a5ad672f020dada951b86b303417ccefcc7ad55d9a23ae32938d122b2424801b9049c68f8286851b73d1357577f0480f41ed9f934f680d7e69d1fb79096730e3a6ea4e228a73b8e16e615771bfa9b3d9d2f8f4a05d56db	0	0
5	20	\\x420593b442c005100ef8a16b05d42ac42944f4a20461f2b1731d7d3d11170226	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000008c62727fdfe2c7f2c2cab382020038bdf8064253bd2ae644c1067a3550deec95d15cf048aea61f4d67968066c6f3b638ce6c31a5bd28b8acb71e454302dd1f035faaab43bd57e3aecb9f4126e39ed7974a0d36e96c877b59243027b4db352eda55ade3f8e953550f0cdace5c5cee7a322f8b60c322063daab6c2346436c8e6da	0	0
3	259	\\x314d97e19db91a5fa516609e6647d5e3a3b3c31f33159fc15a9ffe9db68eb12b	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000356186674c54555e9011d24c18160259fa544ac0b6f70eb9812d875e1d7ed217f9cd6e4eefd00c0a675414bdf433cc7e2e0d64885f327753349998d9099a0d1ffc55f4f7502238d9dd047095c129448cb763adf0dbd11b593c268d8d75778e2d4fc845f8b2b7e095d98aefe081a8e971ce4fd4beb1517c6acef2dd2cc2eca61e	0	1000000
6	20	\\x7f528cc9d66c920ec429c8552dd46683187b56057a91db76e0caa86bf62e8320	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000096445adccc8f46a4e5268e10e3b0fd38f2706634644626ac6209713d3fa500d933b3441a848bf3c1dac2bc1fc4664f96d891e59e3a4c621482fe5f196889b13e5b3d69a8a31bdb16907b59140b6139dc65fff2444fc668d2b614eebeb17ab8771d4888ead71a0320e72c7e9bb6d51dab4ae9927a31142299ecd7868ffe00821a	0	0
7	20	\\xd04380337a4ed5e791692b8d7ba7d6f741c07ff446a9a92e0f2413434bb48c5c	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000043084d415c670a5cbea6d1686e26da600beae3c96c8e89ef3768246646c18f50237c60c2a573dad7afc3a77bf61715c7ecc337db3df16618d26d862d48c18c804fcad2c0aabb2aa366af7db2b1238b0036fe25ad9eb995af48fc16d15363e591c2513c2bc9d1a8d32459625b4293ca79ad1932777cc279106ed1a276f2481684	0	0
13	184	\\x078f0622928a34c823cd80a419ed70708b38af4cf9eb5e53fbe63f9b0fa4eb2f	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000d902782b0979dc67003c11d4701f833a75dee5c536bb02acfb0edd2ba7882715c6a763960fecb465b2a45da2a3a25d2321b20a539ffaff3e4e6fda684932ca1bb2a662d03c1eb22ae75443b3956a223313ba9c940cefab5529d76b58562d23aabdfa7f0785e3616fce4b23be346997373a88fcb10e4952b6d09112240534514c	0	0
8	20	\\x7e843331c99ef5c37a3b88cf06db9fe98c10644d685bd2fab403d580e90a6772	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000027572ac9d829d6cecbddd9f2068903c1ce0089d50e439ec4114ebc91a63769f6a8d7c466317d14b08abd7cf3e9bd542ffbb1dc06c7c48c4a2e4377602eecb92e57dac5cc9097836afa9bd924f0a677ca8031d8514c26632ef95a7825e3edf7a5b06623245576ed636ce48e3bed87ff6d7d633951a63d134713dda3d6f0c49d54	0	0
9	20	\\x80f1489164dd9581590cdc24367678a693931011033cadaff6cb09aadf64ec8d	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000b99ad2bfbdf3f639c00afb5f51598551f485216c10908c8cc8eede3cc70483fe3ef0fa57c4609aed5a3f5a8dd8db2ceaca3909358da51e7881a4627781a581c810f8085c5b4ff03b5aa8217c9822553607ab846b77e167b9da77b3787412aba5d3faba1425b71c49ef5aec97b176d42e04c0aa5e877877577a3c8ee81c8cbff9	0	0
14	184	\\x08a01f5dc004bff630a90d20196c498e1f24ff66b2888931f1d751a67c6a9314	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000009ec86bd4319c1aa90a6001dcb494e11b059c6891f7aedc7171c61cffba8e02fe1bad41df5d9fb1d5c08fe525a8ba77ba3041bb9d1ce51a41e06d8f1ef5bf6e79dc3827bd42e750f61967e9e2130c5409979c84409d0af05a87c7a58c2dd5585be9084a425819d48f6eb412b9d7ee30b6c4d1ef52cd231e1d6e2b05fc3889e867	0	0
10	20	\\xf16731f9afe2c19d0e40f6c114f16c0dc460e3b2c254b75f375b03752a6091c2	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000b182b5251ed2bb380cb816c6bb38077748c03a26884105d9d13d56c38c8be217d1e984fcc15bfab41b379813f22bd532224022492000de6073619287b636dda12734e6b8ee6c632546d6701e7f7557826eb45a9bdc3e0aa7d9bae21f07028df0aac2ec41e7568dbbbebb9bc05f13bbe339ac67b8dab9f064cb9bd0995f118c	0	0
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
2	\\xcf0841a7b568941581a12d9eeda95fe6dbd8c6891f7b8a427c4fa69f49cc5df3
\.


--
-- Data for Name: recoup_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.recoup_default (recoup_uuid, coin_pub, coin_sig, coin_blind, amount_val, amount_frac, recoup_timestamp, reserve_out_serial_id) FROM stdin;
1	\\xcf0841a7b568941581a12d9eeda95fe6dbd8c6891f7b8a427c4fa69f49cc5df3	\\xfca63f7be449b2edfafb4e175771d564c8702243d4180d4d5532750e77a18e89619c7a035747035432e824bd55ca80fbfdb36bfc8c1852e1b3c62cfb30cd0f04	\\xd539dc6b523149bae45adde20e2bd83cb8d7fe8f3a0dcfc5764d35b1edb3e4b0	2	0	1659871696000000	2
\.


--
-- Data for Name: recoup_refresh_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.recoup_refresh_default (recoup_refresh_uuid, coin_pub, known_coin_id, coin_sig, coin_blind, amount_val, amount_frac, recoup_timestamp, rrc_serial) FROM stdin;
1	\\x2235ef0bae094727c4622a027576785a8840d9271c350aae32aee2fc9e739a3b	4	\\xc0b24cfe2f4360a0d2a58771594eb75095218d52db120a2ed1c74eaa56c3ed0efd9e0b717291e306e0d16af26311be7ed8967b294ff92647e504c4254925c20a	\\x1e7b4708458b531ec14e53b902262e3707462ea2f393088710e5d2fc30fe4d0a	0	10000000	1660476521000000	4
2	\\x420593b442c005100ef8a16b05d42ac42944f4a20461f2b1731d7d3d11170226	5	\\x044bf985f8c1ef2ddf3500b0689e0d315907e80e9a97ef834b0455989a7ac9674d41ae04cf6e6cb625febc9dc4934ceb3099b4f9347f708db74784382abab902	\\x165c123d1a71fef35a58767a9bf1806478a1aac9e2d7e8db6edb396f9d496907	0	10000000	1660476521000000	8
3	\\x7f528cc9d66c920ec429c8552dd46683187b56057a91db76e0caa86bf62e8320	6	\\xf09723762b467c8bea69fcc3730368ecaaac1f001fdaf79709e30e7b8ee3dc822928df84efd56948ecc1535f969db9dfebad7678b6db0ece884515452f3ca700	\\xbfa9eff10c0f48cad510845b076bd8a2ed333786d397303237a0c038672058bc	0	10000000	1660476521000000	2
4	\\xd04380337a4ed5e791692b8d7ba7d6f741c07ff446a9a92e0f2413434bb48c5c	7	\\xa97b661e2bf0816c6d944f33d9d058bc228ef32e8a7c1acbffe87ec479b74d1d4d7cc025f8b8a6f6f112447790b3476c50e6c5430c8db203c479e88c3bbc2e04	\\x8c09fbc7de2e1acede93b127b19786aabeca3ffd92ef928dbe2a5dc3f80ea9c0	0	10000000	1660476521000000	5
5	\\x7e843331c99ef5c37a3b88cf06db9fe98c10644d685bd2fab403d580e90a6772	8	\\x76538366813b1e3dd5cc6d9de04b1ac7b22df62fd956f46bdbbc27efd44f566073e5e03ff846c0da1a9bfb18bbc3aaf6043826be73a64904d1a66cfe661f0008	\\xba3867deb120a4ebe442b495894e2969a041ffc3dd250ea92f30ebda860827aa	0	10000000	1660476521000000	3
6	\\x80f1489164dd9581590cdc24367678a693931011033cadaff6cb09aadf64ec8d	9	\\x184b1681d3ebc82dde6c30ca8e8e6d8050e8ed11d311ceed38b4eb9d1fb2286b799e8da6d0709220ebc61769bacfa8a6f6afbda9cdbd1fa8b1a183f11ee6d10e	\\x59463b10b1c21d0da8f4e330d104691b2f34da5a3a1c927f95bf4e44671cda7f	0	10000000	1660476521000000	9
7	\\xf16731f9afe2c19d0e40f6c114f16c0dc460e3b2c254b75f375b03752a6091c2	10	\\xe4ac9c8665a3ead9fea8fba3ed502199e52d585589256492f0a6fc6e55376bfbc96cf28003cf85ad60b000d2a1c535357d904f5b4a3c4b2d36dba60a250c040a	\\xbca087812517f4d608a95509eee2e4cc36247d37ba361ca7c8981012cc412a5c	0	10000000	1660476521000000	6
8	\\x9944735e0ea45e8cbe2c14483a949ab1dd793cdb18294e7953401b7d06df8c3d	11	\\xa2d991c36551081aa05cf6b27a908ee766f2a0d0d17b65e4d83721dce3320bea20b930c0003013b408558b5fa4ef7e461bb80ffdb1c7618cbfc40da9c8ce4d09	\\x438867d034c7d237c272cdf383aefa519b86266409f41c1f150afb04f70e4d6e	0	10000000	1660476521000000	7
\.


--
-- Data for Name: refresh_commitments_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.refresh_commitments_default (melt_serial_id, rc, old_coin_pub, old_coin_sig, amount_with_fee_val, amount_with_fee_frac, noreveal_index) FROM stdin;
1	\\x339c485090703efa747844447cb0f3cee7f53769ff55b2a6e02d1e5201929eda09ddcaa6685fbacc1db8f476c21311ad36eec3219a618de7cf14e8cd199eacef	\\x314d97e19db91a5fa516609e6647d5e3a3b3c31f33159fc15a9ffe9db68eb12b	\\x3501500ff178e808f669d7317922b455feee8ac9f5d47d627755db7e74b0767b620a3120e38dd71b3f93760aa1048dfa671d6565a4f71da1c9babeb5079a3f0c	5	0	1
2	\\xefb963610ae8c4d0ab45994246ef287a7544f6bbcdda238175728362c962dd65d045755aaa927dc86b8a61b1189466b0915387ea0011b068c14e2e8dd3687a96	\\x314d97e19db91a5fa516609e6647d5e3a3b3c31f33159fc15a9ffe9db68eb12b	\\x4f7d4e5263e5fbd77354ab457f5c024740d092a3bff2466f4b516ce74239a79e70e8ceb52b58ded3927742c6520b212f2f112a32ae8c30d1105ed11dc918c60a	0	79000000	0
\.


--
-- Data for Name: refresh_revealed_coins_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.refresh_revealed_coins_default (rrc_serial, melt_serial_id, freshcoin_index, link_sig, denominations_serial, coin_ev, h_coin_ev, ev_sig, ewv) FROM stdin;
1	1	0	\\x696f874ad1d33ee53936b2e951d75cd4eef91f4f56b0b6e2428e5527ae83d33a220e9cd742b735f492858d565423545a5afc71f9ea3269badfa9687914171b0c	397	\\x00000001000001003fde6eabcee49868de185b0895c037260155f1689b170e9e2467afede9257dd9d3f502792e6216304ec5bb66869956a926dc7f9d48a340a965bd07ff9446858c11da7e8f892be2a6478994abf0da522fabd19dfc199b071ea4fbced568b3addaef5dc15fc13bcfb9d64cba7626d8484b5f4fb215a815b50be421cd830e3e4ed9	\\x828bd20963d76a3456ddfb4919c9b09fbaeb934763e5b4eae23c522e8524ecde61462d1665c1a881d32a163bc8c0d2b124c60e90d905a7a6257439e72f2dd84b	\\x000000010000000193801916807860f29220e1f3b1e5faf3f39b9e745b252c74e5777d414cd71d6ed66f1f0e308cfb8f06e54e104431719471813f2d5da168bbba0933826ad5ca81cf1debbf68f07222a2a97b903a99156b2eb1ca07e13bc870898a300fd60eaa69e069292c9c36ccff520223db509a29477783c1e3bb9fb48e633f8a2e139934f9	\\x0000000100010000
2	1	1	\\xfaed6d928a71af089dba0b791ed62ac85d1e34193370bfe285e4afba53c69e54ceadd2131d4a5515ee9c270e9b0c6b16758938bf32d67739caadb256ccfb9407	20	\\x000000010000010073cb39dafc1bc2739482a92fc17cacd4ef63fe6bd6ae6700ed466fe3568c99512b57395762669fbda179de62fd62248147550557aad898dba8786a201778c87380a347e6970bbd323cc5cf5d0166ea637e5b2e4548bf959d558a3958c1968d792f78a406c44f186c143f38dd772139ec13212ae30fd75b2de29c4949d181b4a3	\\xd9d6507ae207d608ee3c6757cab1ef5f65be77021e95a6fdfacb8d4d008eb66750fd4f766f28647361189b0fb220ad17a26bf520c844f50eec4d543b4546957a	\\x0000000100000001bd1f2180ed9284eeac9470f0aa6784ecc1d6c3b055af44f1fcd23778f735d7a8dfc1e3e08ee4d344190936defffa15cdb7fb257e3cdd7a30cfd80fd0b202d099ef7b8e19eeab613f841474f5ef9fd85b9011cc1c8a36cb7b4028528483b2cd154b4928c1ec2ca7ccac235653136fc864d775c96da260b92fd8cd512e91ef8893	\\x0000000100010000
3	1	2	\\x3b86ec29b78fcfac2f7110189b1358c532e3b63d37816d2f1d121d7f9ffcd2e111c643042c69c68ca0a77bcd0aa425a77172dcb80b4636a6cb6658a6c6d84a0a	20	\\x000000010000010003633d47e8c9d4c22e5ae45ab28d4e5a94ba536f9ecfe30e902741bc193cd86e6dbc4599c99473be82b5cdfb88527d491f62c9ae84566a17c0d0d7b2f96a2dab5f08b52ae91c5e7915ef12c987a66c4545b4175dd6d2eb2e0aaaae84c00a44fe90eeabfad1b7cdb3264ae225795db3e55d9f01a1b9bd23b7f3a4fa0d1444bd2b	\\x8bc79afe6dad41c6ae5b75d7af80e80337dab75c64f2a3d2ca8d03931a9e8eefe2ac48ff4b91d6172d8b1bf1bc4aecd1f7dc6e33ce7c446487c5e4b1fe4f4474	\\x0000000100000001386f6abe2e5af60cfbb9a96f6ccc43a04d49f306b5ef7ac14019236276a9595c5217ae2a2bd13c20bb0802e871c22c053c20b8863b78889c8dbf127f31ef2576be7ac667a3fb7f0d767d8e6def26a222f0febc9c922a6fc3e4e1b0004c8c20ec0b7099e6abbebabc3d62ac4f25a170905d3d186edc114c73793d095b5cf709bd	\\x0000000100010000
4	1	3	\\xdd91e0eb7cd918952e7bcc9f1d5884155595c189fb1bbb0278348f24e0d96103db4b73f538eef191033c87d4def1c4ad64406a3235aedc5ae350c9b4aa33720d	20	\\x0000000100000100b8bfcf87807513c185a818b8a4d9eda5786d0f94d38217cc7367fd9ebcafcdf5a101377102003f8d48b1e17ef990c675df1bd94ea8ddddf424d91019c4694f9e3f89b7437d864d9210897edf9dd1233764bb95c0ccbe92b52a9534165b5f4ec0556e8300e72385526018f6c9755612f218541988f6152ba1555c9c4922e6056e	\\xb87fac1dbdd7b49e83f1b97f434efa9d0ab674361235c57c7e07c4d9dc94b43ce1894b76b0607f06d7b2ec203054534ab97525423d04e61c4fa8dac78c07365f	\\x00000001000000010741d2d82a5f39a27b4cda87dfdb862aefbdbf78d01d72d9628646a6d33408f92370bd01db303fdabf9c950bdec0d2125ffcdc3e5c697f6ed1770d0220ba4a55ed213fa94e9b53afe13033cf57326754b04d1f1659400ba071e6145536930eb34a19ba5b62cc3f5b2c8ac41908812d924113acda69efba068e416d0e3b91e4eb	\\x0000000100010000
5	1	4	\\x6bf506ac86f6a152cf12a25a74f250bff82990f4da10f8b59337a5aecc47fc67a91f5c95c71d6056fcda1a3b5513094cc618f67787d70b4eb7b9769a1859ba0a	20	\\x00000001000001008fdf1e5ac411c9714a039114b234d713cc2f1605a6812418eb194037010905226bd55f539193689c0598fe1be0f888e8161829eb5fb3387068c4791f41110854d076f4a7a7aa297f89da849f42e93aec7b312416fa26aed5e745e731eef1b8b7a6e20361bf7377f5c85e029b51897d6c440f584f6114edbf67c5e6248e1974cb	\\xbe1dc500766200f49b095dba8017c0a3c77f6114d24fe90e57826c6a91572a7fd09f584be1d614eceb65cc1bc9abb3068269910e160c2b2b8ff785e98440936a	\\x00000001000000010950f9e3b97669e36e3769034373419c1b40bb7731ec98c88f82223776c96544c8a597ab1a951b8099d7bf39828cc2795ca820aff60d72fc49e7195ac6bb6c55ded294e2d4a2ec8a40ff3760193d72a2779569d83dc2659202209fe127b115388f9f1a6e210c38062626e4fdd703b81bbedded1516cdd71a9e5ecd54e073f411	\\x0000000100010000
6	1	5	\\xecde881bdad2cfd89d75f490ab397d527b200c85b06a7ff8d3738ea16b575cf812e01c09da37ca3b424fa8c6061758caed82be99d109b1e4f3145cabb9cf810e	20	\\x00000001000001009bbcca772edb478b671460cc169fb5c46d4da80f385918d85e830857ffa2227ce2c2e6d32f8033f11c6a22451df3a3193fa1725215a86d53b4591b0052c627b6ac70edf464d060a05d712e2d118b69e17d3b43cfad34b80fa39185dd7560c7a78e761c707fcf062f23d155af557a72f17685948a69010d192f7e76ab5ac91888	\\x6750b989416ea00df6e8d5c2d671a7fd4fc97ce30e7d9e3487e4cc2f3551e4d099a9915078a42d1b4223ed1980433afa90533c995b663a2e5939fbfb24a8d763	\\x0000000100000001ae879af57662942d077c5e48a799a79e3c2f3a3ae62e73157d6a52c42a1b6d76f24e8b7d2656fb3df68b6be3c5c65a53b986dac940d2b797754735d8ccde16abf984001bfb4e9317ba73692accb8d20f6d70673c6dbc4311bc4be5d03c6f694a2a0ed35f32b2a29a192b1caa3b3e189b5d864e1c574d31b6521316910446e399	\\x0000000100010000
7	1	6	\\xd408d057fa58b46100dcfb472882907108e1f962693b65d3ac9ad3395b8f2dd2064ae8c063d406d2c53212ceab8173c93b6786e61eb2463907d712fb6d55c60c	20	\\x00000001000001007245f48cecdd3324cf86d3ece45923953f592ce483fc7e5d55b9ac355b26c2be46c7b9375000d049f84d02ba74637da7730d988ea020a2847d39f609aaaa17748996901b90b20b6e6bc306d99b295a944fd8551f81aa27056ec6078575a2556180a3673d3bfcc45d7968f4af57fea8d17c1185579a34f99a0a440b9b76d64613	\\x6a293ccd1e57f1631170eb204cc326e256f1b2249c1b9a6bc7ee8a8e72eca0b5ab700f029f7472140a5f9be06ad4f7e3c1066f676cacd2d360e6c3d7a0192a47	\\x00000001000000019752f3411caec495ce0b6ee4f67ecb416e90bd77f65cc78257d4d932ea878e5b8639ea0c650749df6126c83396c1bc68f722964628348ef914ef13c575ba0ff6482d078d9fad4da15863ca17297065f2687f2fa4ccc3abaede437cd4536f40b62e6eded6d10c890d5fd91f35613ba47edf253e19e586cfb23e598f166c05335c	\\x0000000100010000
8	1	7	\\x97adb5af5ac1f0bb800cf1dfd360bc9e4fb842a670c865f02413330054b2a3b3f83010fe1c2b8f2c1f114af2a6344337775cd581d3ad4edffe2f5d4566f0e904	20	\\x00000001000001005e3213b103313c75cac1cfb51ed1d3d1ce6fa7315dd73f208908d9b2897612865dbe1be631d88c61b93176ca13da3aad4f5ea17d72c7dad76e459f3bff450f63d7835dda639780451127cdd33dac115aa79642aa11a163898b2826f5723a7f9d5f556e77045eae11f15ca6e118d209efe693ba2cb66ae2cea6d000cdf4b3c3c9	\\xae2b6fba743229b99e64bdf03c15bf67e8ba07f82b8539558c0990172aa6852d64c0c71aebee7c6a1b76c041b8622cda1c0c6907f345c552f6e3e2d2fb28f1b5	\\x000000010000000117c5f4d4f932b1d351ff6f02342929fa96a778d07f45716b07a6867dbc0a1ff5028d7354c923098233a40a2a4494f1ad6a97ed716289313d742d45e0f1d2d83704a96c52022c8afb0d72a8f433f5dfd786cb8b3dc939126f4115ed4b8b0d1a3f3b52f17c84717308f6be08b5a414e6b6e5dc9bd0f27c63392465ce867a6c1723	\\x0000000100010000
9	1	8	\\x7e9376a1229ac001a1ac4e91fd79e55fc1b952a691be892cc09f51e44868c13187833d2d0f2bc4aa140f3dff3cd006942bd33e5547edb9e6a8e8f04eef4ded0a	20	\\x0000000100000100b07dedfbf7b666b5177abe44cbe58db6601070ce9793aff7a68e5bb5a20dc59ee26e44942cb5bbae758625c4f0c74e451ffb1f4104207bb379d0644b6bdd2a47264a415402dc09b134eefa121f44fc58c72d901666abe77f3db45cef4751b4fb19b5992b97972d8a65b212f58cfd1ed638cdbf916eba6482376cc90035af1d1d	\\x24b6b26ed06454cfd2b9821a93563ef7790f5a48669237e3546c49ce3b28a1df76e76659f37e9feab26621ecbdba694950c43560f8413265dc83114a5566ba31	\\x0000000100000001953b614628a3451f1267e6ad2df99b8628220944f68ad32d11dd89d26ae513a2b4ff2ebe5fbbbee961024e9206dc7dc40a0375062ad82f61e8216a413d69217cf71d73ecd07f2897137c0283239491be0bce4efe4ea06e06fdc382739ea77e347e37fbe937ef2357768cc88de73da3e81d48243bd585f12a139df88da0d2ed23	\\x0000000100010000
10	1	9	\\x03b5b7e1dcf32d9607b3a05354504e398317473ade6d5d4d8749e2def78222296e5b9c406ec4c661bcadcfe0093c194c96e7105a2086123b7c68f5349bdf8b0d	184	\\x0000000100000100ce31d89e8de19e56dc962025319e37b270987ee9aea174c151c46c097bf67b1b336c4bad2f90733a1df5267df0121f5b133eb54f13545396fe70f11829e3dfddc36e58d99678a44b04f301b12558565cb7f9a32f1dee223a430d6a18838126f822f59a98c8a35b07bc667692a06b0be00bec9bb6801d5f0ef7bc72fffc8f61c6	\\x80548f1bd92f9b94411947c5c910f77614f0fd2d01332781b49441f2f3e4450819d9c2a48b00efcd9f32e0d5e143f58ff3a0ada83a448a0bda2b9b1f7392a75d	\\x0000000100000001374e13a8470cbe6e6ed8dc81f651f5a2c06990553b4104e419987561fcc311ca6df13e8212d9b6051d6e03abf71eb92944a9940b2e1b566a3289516c6ffac49dcb5f13f483733c79dc8f02034b41b826708dab6a64b31b4998ab7afe11b277504de08d2f9f4bbf94da6572f82afbb4de38f07e4e57954d953a57e159160f3b33	\\x0000000100010000
11	1	10	\\xb31f1c71cb8a80ffcedd66b84b56d593ee2f4e3f1ea0deab4e74a40010eba32bc0c89e3a28ee5a7366f291d75ea4599593ba148fee044810ad591c170b591903	184	\\x0000000100000100f468506b1811eda91d0c0508b05257a977eba268964ccb7669ce81c7794e3cf6f318319584f300d50be3994f0ee819e8694034c9b63528c18ab343473041c5299ee19a7fb60ca07d4bde9b40d4d021259246982b9bc3ca6b6badeb9bb9f82723a19671229b98952d6e2e49cf9550b8b3bc9a6673b7d365f5ccfcccef9db50943	\\x038918d1b290752f23598fb9ff5532398e69ba6292eaa1909983f589d8ed834cb52fc25415f774eee9a86b6f9b28e6bf28a7cd2837d170b1601a277028fde5e1	\\x00000001000000013c1feb4693d49c20609b1c4672d95ee4ed18155b65bb2c188745aae4eb27f9de44ce6fd2b01f0b5ad9e76c9fb5fda0393df15d427d2e919776c379289b12066e6609c80a4474e523ffdfcbf3928a63f821156ae1ae4bd869c450304223e1424c5b0c782ec6ff29311eb6021a3dfb5886141ea62a24fde482ae74a88234c3b21d	\\x0000000100010000
12	1	11	\\x05c8b6f535b9a810edd3ca69b54373c392d7dd4b4599ed21ed073952e09f4ae7ae4027e1222a63c3d174b0917dc5522405943b6e8adce34cc9b9a2e851cc4106	184	\\x0000000100000100c751a4e5952c15989f76e5be30992067c7de97bb6de52644cc9ecc9bae92ab9e58de0bbb3923788e942c23b5871ab92aacfeaf27a87b0fe6c81fb2cab039a0bf3ef853d06f076a0024dd09999d8dbc5139581cf55831399bd9a1782dc1df87f0818b699c31ef20629d1fbe8103b6725e478d190f44817b06af9653f81a2444ba	\\x786a85895e3089718802fbdda394d08aefdde2a5ee4f07a59d610a1bf577bc110ed01d5d91070fcca0e5a196415c4d8e75038f39978f87d7bddf13a01b7662e4	\\x000000010000000167db7d5105b76f68d46e51fed91bf4619ba4b1be3cdc8fdda97153c90b67dbbb6a9f7da6508adaae0311ea4be25abe78a9b9903983a00566cb69fb428d379be39c2b4ac5ed02757bf5f58e64ea29b3483bf31eba395c73437794b11340fa88f6ba62b26a642c1ad4043400107fa1b1e9058e33c5609675c6a0cbc5f10310cba8	\\x0000000100010000
13	2	0	\\x5b1025db07e360e1dfc12ccfb631447398a760368b8e854851a12d56c7b6d7191805e52cde4e7999e33b52544135a1484ae510f0d76013809576dc5cef62df01	184	\\x0000000100000100602d69f661451cb5186fb6e122d128e74aa75024a80690ea26ac8842c592a6c087133c3bb1e22295dcd21fb5c7117b9d38d3fa27f556895a33fd44bbbd36d6fa51aeaec8467013636c83696b0662c90df78605e763995ffb7013b4299518ee4833b999ca6b8d1442bc0569b82ff61e8341b2e79454b6052f36888554881331c6	\\x8528db2b5f0b89bf41f11e3438203ddf04c2091947b0f755e900a4b79f47c7bf4a7ca60e61d020d71aa599042aebe8a124bde7ddef11b1cd9175b490bd5493af	\\x000000010000000128b0dccdc06da8b99a5b213bd21f003a43f67bc30a28505794065ec085c9b9905586c3128c3cd0a48a7e6f7a9930386764ba2e2b0e3c08a27d69ce2f0d9d696f6b3223b30732c1e0160d164784d1ff775fc896aeb5906c6a8f2ae4de687a1e64937dc78d39a005a01b75ce34b43814e52441acaab1dc76847a6b91ee87995887	\\x0000000100010000
14	2	1	\\x44b1d5d2ac3c89ba541c219c61a07853b81ca1e04a737056a9e3b22fc26072ca28ac3549561545fa0b09177669ae0e618546732cfdc795071573ad0c8bdce608	184	\\x0000000100000100560b11dcd86da2e487a51dc17c7273e15939732817b5dd7db17542b4c03816c47823fd986aef67d57364c7e6a30fa98e1592b424afe825a27ad39bcc7a295acec58992a0fac809c86734abfd3b8dd0bde5bf54d679f65c57ad043eebc6a655ed5e0cf2996134c522a364f5f40834e04601b44fb648e0290ab487f33b167079a6	\\x93007e8bd7de49e3b1b980f8d64ca7346ba81725e0ec48d6d4e98c66bc5e669767a8846f9d999928d2d626b109399704401f88b6cc7bac2deff8ae16f533ff65	\\x00000001000000016680902ee12a776f518919dce2bafe117dc37d60218d80de425d0e82cb8223628dd486cf592579229f6da1e1b32a7ba0d3611c64324a47bc4c6425681d0b3a335bf49c6824888abb905064044a723ceb4131e609a4abe0aff828d713cecfe046c942585227ea0cfa0bcaa10ac1528fab8c0b33f6eef4469f3252ce4669e15dad	\\x0000000100010000
15	2	2	\\xbbe732a0fd07351b44f7397782e20531b729a4f1e9f54c4a441882d5dc1e99ba6f46699c634893143afbdf3b85b0aac6b1a969d3aa29ca9ce203c0fea39c7d02	184	\\x00000001000001009c9d8c12571cf417de5e74d7abe70da83fecc7cb70332d13e258f2c5d22b174d9b0c4039b7ec476603a77cae842057495ca61245fbf9487466cb602d999e7f4a688cdf1ddc336a36ea018605b82241460cfe5d97548e6c4bfa71a3685ad5fe7427765abe11c38d76b5b0e28fd857a63b7f19b6e144ddc8d71beac0d8f9cb6dcc	\\x934382e7d1c66e6c073f7ea029a0f8c0f319809b0350e59e194913b8575006856942ed5fa08bacae154f8b8959ca685dd2663ed52dc5dba32ffab67308941643	\\x0000000100000001a200b49e90224db61fa53abfd8dc545232faec88c17ae9b8bb0b6a73876e37a01a94e26c85fa3da62da4c661937c8ef0ab2f9aa90cdb402b16c6248745f8e95d952cb5cd91495b41887f8c05ded37817df09075bb88fd1c5e952358834dde875546ccb2d0a53ca6604fd7b22ea0acc027913bcfabbe5d7fb6cde9cea3010a06a	\\x0000000100010000
16	2	3	\\x290da41228f5a2e52fbf0a060335d181089f6e738505e3d23a65aa3d3bc7f05716755419cf4f1fdbded690a7c0614bd16ba8d954c6b8405d5dec71547553390c	184	\\x0000000100000100d5083d5d2d7b911235c336b5889710abf2b17a1f68414b08ba0c2c935fd14c8f54673632e0de6eed1382b74f3ea9664f533f7ef59d06859a8b24f1b987e99faa8528e96d2a28305feec74d7ad3804dfbbc69ede9f2f31e5c3cefaeab95578f88f587f458311ade6ac5d972f3c8d6e4f63e074b83e13dcb0bdbed184a0053228e	\\x7026e3a4d313d3bcf7914ef64ed3f1b6737a64a3604e3d6ddb3e7aa6ff92e50756900e3ade287a0d0c95b841e68f79be9a1e36dfc951197e857f1d932e4d977e	\\x0000000100000001d2a16a2d04aaf1824fb06752231e46292d4b41c414736e559a3197d0db04c00637d31c71c24bde5caf9e4d0f6c08036ac302282529ed1daf6926063f3592f02e1616008ff48b5377d8da610ca9ae6ab683a1504b12a10a0c74e13102badabd4845f802a2a61d9363aab8fcd72f22018be2c98239ec62e9b9f9fbe96d75ee0c6f	\\x0000000100010000
17	2	4	\\xc98aac8172641b2a8356fddd0226de796a03ffa06f41f134b7c389f07b9e9411230aba0dca7b62d1ed337708b818d3563137824f00871afbcc41ea0709863405	184	\\x00000001000001009f011c3c8754c38f3ab3a0e7ee2e2bcedcdd82631887536dc6b9e9f7cecbb3f79d18dfd2edaf11740955e136faed0dbc9cfa0fd6a3c88730f702a808a625a0f1f9a403e739c3ccde8fbf3d6ca6a6e2c3bacf99b015325ba89755e6962db9764c9e0589331e8d6ad180a1b5549bb614fc6a58eb7249ef5b76ebf0c28127f19962	\\xe2f80847d2ebbc62ec8eb9fd8d068cf35be5f8557f3d9a185e5969f1bbe66a52d35775cb7b1b11c5410cb3b0571747625d43b241d69cf8bdcef32c8d171d1bcb	\\x0000000100000001715ec9025b94b42b4f30c4a9dce5dbe71ab7277a82da4da70b8cb14e665cf449fecca7d50fd270b61158e06be70af6958a3f1eb9923e60e0d136287b187b52955f94393ef29d58be637ed00e1b4191e9b3e96fba02b9ea74c0a9e17df445ad2bfdb88056279a500e9979ae128f1ccd4d58f6edb9cb12315e8dc8ffac66787b42	\\x0000000100010000
18	2	5	\\xf58d2cb6319809ce89b0b0bc8f7b3b9c58bb58cf50fa93ddf4273a0df8a656a2f24151d1c7494b6da516b57e229988aa55b7ee30b9f2df9a9adf603020140604	184	\\x00000001000001006b70c0bccc3369ff3a1925e6046f72017cd5099e6fc021e07189f93f34b75165bdad600faa46b367c8e7e583e3b732c99600c8bdb8c1ff4c8f0e9d1f275c3a0b574372ba7bfe01d3c562ba1e8bc818f52a1aec1827e8d53f132c8c3f8a1992e5ce522238372b1a728a71aa70e3c0d73a73f66bb8b1bd3c1b51e94e996c05d609	\\x969bfd700d6ad45e3a78364b24737ddf109550fa8a79eabfda20806030cfb48772d27902a56fb958dd56119cffe5f80988bafe08a69a38438d1498f580f46c1c	\\x0000000100000001054783f8684a9ef01599ab79076d9e994a02a32bf4aaf58b1e7779712671b73d8619f8c5f010b4b4d82c6fffcce356d3a0950e362e138e265d8afe5c6ad21e1bb08932cdc7ee6929515996f53c5656971597744866109c8d38384091ee2504274738d168ef6f7265c28e6133d385af033bb7a7bc7341ae4aa2e7f093efaeac02	\\x0000000100010000
19	2	6	\\xe229a4845f27ee8a0bc847d04adbae83a6c32a1f05c21426f99436201d7f8f7bdc063434a681f687fe8f7958327ac62044519444b5bd726cd001cf1607da4108	184	\\x00000001000001001641b16382e49157329954887fc3d3f8d559add34d9a0c85dd217ab3cfed21248c7e7a5fe518ab23f24e4ed6a1b74539102de64db534da5c7fbd1e52599aeae9608f36cf4f1cee2e1566910a19c1638063631eaa74b79aab440116706a543cb5e6656f6d4a1b24b5f06e0da472aa881d0b8ef56db0e9f7a55cf9b8b98121ebef	\\x19d53b479d2c52b1bb5e2b31b61c9f3602f893fe180f76947cbe9a5284700eab52eff8ffdde782a0504f2b2e99b041898ad043844d140032c145374b36fc257c	\\x0000000100000001f23724ccf1879fac45e6f9a2f38f5def4e3cdc91a7c9eaed7219126a79f49f9f10f06871ea67e78665a57d08003b09da3d3a0b9475db61eedc9ce95c13326612cdad0b542ef4876773fd9aea25abdf1a5d1c0a55a9c9d74a65e0c796481279699370438c77344ac14058157cf7a830da681d03d2522584d975e59bac531a3c2b	\\x0000000100010000
20	2	7	\\xd4210bf4a23c1cf984e0e0d0f609372ff66b2149a5204941914b1383935110a82def15625843d310f03c4c2d52ff3e19e000275976c6fcc94b4041f6056c050a	184	\\x0000000100000100ba858a705c1e5fbfdb31fe7ab65116e6726acc14c7d72fe598719df9c59300b06abb8a215c942cca15f233d6ecd1a65866cfd879966ff2695535f623b1e75b5c677dd71729e7a05bbd88571cfbf7ad672322181fe87618b37278b8e334b84c397720a0d61a507ff38dade17f11f2003afd14b3e4b89c324fa9bb760bbca6d8dd	\\x58749c018a512a8febf9d4c908b1bb131ca6d8d49ad2d5c1455f17e296b34064953d6f06b43a81912e94d8f49569e6e575fde9b26f925d841960f5cb35eceac3	\\x0000000100000001c3efccb70f720d8fc861d81b55a6bab73de48de36eb0dde5487546798124cacb70f3b69f218fb298eba1a7ff692f1d7b081f95d7aa2a46525e5fcca94c8db45a1ed7bd6451632bdb17bb281ec7b98f42f3aa2ad959c5d7f22381067c9d5085322efa4bb3ab71db71a9edf282a02620bb545603273951d09c948190998809a69f	\\x0000000100010000
21	2	8	\\x1a6104926ed87d1cf457df435d07b6960e8e47ef156d1e427ce54ff107187b86abb2fe207b49ccee5249fd32fa72389cc944fe1ab545eefa6caad605af0e8407	184	\\x0000000100000100c3a48bb68fb57df2eef9d7b2c1e12d9038c8f164dd873ff65ae8e781ec27fe71bea1fcac9e6ddcf456910387bd72b16049b357932023a871d93f782129888ac23aca0d121b3cf6065b875b546d0ac077725eaba546b4bd0abef3ae683374662e91753fdbcd8bc84f31b7636eb5f8a896c5556c99ce2a69231d59965e2818a27d	\\xbbcdee0fb222a2c1d38766741869a78d7f88add13c2d5b4e79a6587f2f9503e5d72b498f947158b38cc10ae732e1489a47c6701cd229d41d269cc6621a034c85	\\x0000000100000001019dc9e8f052692dc91fa92d47c0809265dccdfb5998663548ee754b186ff4d749e155c55e554fd00dd0b883c5f8782cf5f97d7ae6cbeddc14c53d11c6603c8528ca475fb4ef6072925439cdb811af623dd385b700020c12bc583659468060f5cc9d9f3d9966af5479a5d870f04c54105cc47b5cc45469a2d4436da7c798dfc0	\\x0000000100010000
22	2	9	\\x15529ea8599a3922733c52c392c1b47f73c4b41b2971a58cd786c56c4b29d0eb2468847b267b02eefa14a6fb8de7807a96c409a26929e3123d67f5cbe9effc07	184	\\x0000000100000100324f25a958bcd37b6e0dc4814f774158342ca48ef5be9919ba2e95a63d1f3360ebcccf4e0e2397e30638f3bbe2bdb6708f09d1beb2339468ac6f78461c0261ca847c63f8d354648a9723f64004dcbdeeab974c697f49036cab8aedab3bab98b46adae60d9de956f341289b17aa055b80120d70af0ab9dbb2420e1557fa6bd115	\\xf89fb6e0643cdf5b428815100c0a522f5add11a1f6001032895056369224434c484ba093479d91ffc8cad81cf6bb4cebce6abdf2939c9e92845b417ac5bb8bc0	\\x0000000100000001e9adbd42e0b82b52c2b525ebf6ca00ca229a4159f7d00128c29ddad85ab4b11c8b8b3a4464f8adfc1c63da1e1a1e5324f0b9b33383a032d9d99d3faaab5578cf9bfe71467e7c77d6bb8b57801c1cb8360d9c707570411b05dce542b69c3bc644e54fa1a4a30ee165d8dc82028af8314dcfc50ff0f636e315f6e714393b6798f0	\\x0000000100010000
23	2	10	\\x5c3917b48d9d29741d5dd36f29529eabb5eb8f072b64c46ba2a0f9d44ad5d3498841617028af7673a79520651e550f411f07a49d5cf3db254655d17937904803	184	\\x00000001000001001a53ac8c4fe9717a1253f1bcadc5e46f2b907f649e49e67bac73fef6649e765212c33f829e45689002cbde429e92adc0f9d0e594d0c67429b9886fa8b3711f954c005aa3ec10045327f65c0b217a72f2c265c9b8a26cfcbb2a989dcf0def5ad3ab25ce412f2ad7aacef395c1f10f16d004470fe1b0566a86b5ca5a2bc6b1717e	\\x86e8037b481f1ffcbf5879bc1193e8ec6497d62953a45ea644409c8bec930485a144c94a7d56fb6355d9f34a0a146627d24cddef6adc7f02d2ed47242856ed26	\\x0000000100000001d8beeac760d04155ab1d34a6724d8290d3dbef36d743160b6539483fec4672d167d75f609d3e5ae338a29304b12bdc018cd2284777445a39a10398807cd2713de93dbead9303cb7bcae35c25b7d5f9735752bc804eb759358b3a59b66516b418270f3216fee0b0c88085d9804ae3cc6f4763d965fe3a056a1037399a19465769	\\x0000000100010000
24	2	11	\\x4c6f08199118a5ebba813ff22d358d1450b7b6e6586ae129cd9baf13bceab151271cb1b8db17daa408beab1cd4f633a3c6cc6fdd28c1fd96ee74cba2eb9f6309	184	\\x0000000100000100856d8ae40e48fc7d4e68d693dc7c2eddb44b9ca7854b9ae07219cb024521c366640caecf8e9e79a00058aa915de12e1dafc86d0200ecdd517d999438516433e03abc131777e94accf9e084d0f8cd3aeecc8d70dbf1024dd1d11d47b7bd3810c09799d960aabe2272dcb3374645e975ec0d29b1dd72aeea0fde9885588be76f12	\\xba670761010c613e868751b9253f59a7db31620be5688911dd1199b1065a3ed05833c17fafb0bd46fc87764fb5550787f3c952585f61c4d27a7589683a47c7e6	\\x000000010000000145c517d662401b789eee2be58077144d22ec8b6b250c133ec187f63d48df6c20b68512afc23e3ea8d62753ee69abfffeadead3e0304dc988838023a95a9dfb5b5aa06abefb031a348bf6938cb2dad6f2ff84b919c17784fa29ee0b8832f0e9d8ba6a813408839457f0ede99c8246c043044933016ec3894152aa06d9c894f804	\\x0000000100010000
25	2	12	\\x898de1df8e1810f98f2dc9be05cd3db7949a7dd30ad3897c6104501b280d0a2224bcb2be18dab2782f1ad0002ab22048529038a5b04d66304bc1185e030fe80d	184	\\x00000001000001004adb163a2c5270844b4f52bc5a8d7de83f4ffa51c3a50e866890e01614a26a583ac06c16c8e7bd0ae1eaac8c886e4d96f697a1f03c42e3f43b50229b8b9e867f1d469e07413e47a523ab4150b155b028fd12c78b1b658d03a7bc90b1124ef47881ad013997c3b569a308c0d995b4d26d9abecc809bb2bdf703d68d1c804edc73	\\xde612f703ffc8ec14e5a6de7a40c67b03e4dd6404690b7c6dcf5bf1d9d369883f771ab537502e10d93e29827cf311dddde1ee2fbd807b4c0e4cdbcc97db4b3ea	\\x00000001000000012fd1f5ffe10a45e0102f9286b4f6c4c723ae66fceb8b58d5ec3db6755d246f243343bbaba30f9bea153b7bf740686ad9d5f5bdb8721ab8d05b7ce1e44e6928dd332963c25b18f60bbe99c855a0104a8da2ae5a1dbc264cdaf1b0c52414a50d84939368312853b5963d823ed60779f65c1e1b27352a82c07045d14ddd85489e7b	\\x0000000100010000
26	2	13	\\x92ac3a8aedffc701c07aca364852171d64d15b6397f211c06718c790d542f3ab16bcb877d0601e583b89d62019eb9cc3c3762113dc7837d660bf519c3d378408	184	\\x00000001000001006925f8573291b5959c98f1f85b34cbe125feb5e88ccb19e96b236f7dbf5865d4643400c46615c8a774a7b52193f09a1807a5bc4a7e8554964894d2afe281b46b60de397f1c6962e796187582ecafea4914a85ae43ec9065067681f3900807b27bcabc8b0731d6b95fe211ac8d20953331cefb6b295dd7558d6fc0d8eaf5795e3	\\x0cf462e70d758085c3e152c92ab7febc13d12b752d4cf18ede5737e1df6fa6f2336ec48fa580db8ee80c4ea1ec1b5cc9d9935a24b6c2fa76c573aae4495ef6a8	\\x0000000100000001c418ca699f47873f12667c7156ce30848ca90d9b235d823fce06ecf66e113e6c5d13dd325c9cdd0cfaba3aa537d037f384a52158a4859d8bbed2eb553df3ee19359b24a2d0c5c8c365371018507c7e104fb7509a0ac12c1300f7859c2ce46e3f88138829107e6ec47015821cbfd92d4b7a141aa45570c2e28446ad9e384e6107	\\x0000000100010000
27	2	14	\\x9a3c625f95a4eaf766e70ac23890c47475108b8bda6fe19bbd9fd434cdbd53d75ddc88efa753c5f8f281f8f85cc285daa1c882a251f4f90fbc1c5fae7890da01	184	\\x00000001000001005d341295c3684de3db8a44f746920ea0805fa849a66497ea00bcad207fb615bcc81ac346dfd0ff7644b58986f635c2661348bd27b229e0c895647691938f82f4267cb9b0be70fe1636f538d310f490e4b5387de716c197f4593db2dc5163df109a45583b0225049e3f608c5d28e6173aeb2c894811e0cb21964e67ccb1a6e2f5	\\x25c9c6e050f1d4de4b5eeb8cc0e684406b4615d22aa76324bdce315ac6e5876bf6528f0ff548f8aae84eb34695ba1e237e9b2080b81a6c492a4dbd34fa6695df	\\x000000010000000178e8ee314caee50307819942cbea63624d382c6cb633917acf8196a186ae9cb35491e368cd6a5506bf897192e61108bdd672b179d26292eace87fb37bd845f3f64478f9f18597bbb1e6437f217c959f51bf372c5c3d6dc49048a65ea1d69e6b50af733ed3e773ee9f2526b9ebdd30c0cd8f6cda5155041f91e1801ffa142a2fa	\\x0000000100010000
28	2	15	\\x6bf8ee0b65c17ddc0d01a7416cae8cfd2b7a1cda298372c6169f6304003d3dadc2900aedcff219a733568f3aca043c4313c57bc8ed09ac7434305ea40d8fe201	184	\\x00000001000001008809dafe52764d74808df9fef383e4b423e47c55aa275e19de108aafef17b8d0020c386320ac0b8c4dd946e9c66e948bd77428ffcb076906b2b0728ee40a79c8b2fef5aa9dde1a454829905664ed2e0be9cf4ec63371f2f459fc8dd94edb6974975e6a2d7d6b84e96b7797d3ce0c8e8e10b4ac72d5e834c123da343689891a0b	\\xb9e2a98c2007ef8e0f515eb47913b633420b78008616b9fdb28fc7a98c784b630224eed3f0489da0d443ff809e69ad32655856c1ab2b69c7e8469bc27dc9f432	\\x000000010000000177c78f278fad31147db4f7d02b5808dccab844a6bbd14993faa81d20ce892a2d57cdeb85a73994e505e08fc9ba98c9c5cf4aff56dc42860c33c66727ac1e2ec3352543789a99b752f408d309b50edf60f4ea629bfbc0b02f8d65a95875b4463242ccc03d846121c15138c0bd168ca42a88137d65c1b88a3e3b9d1c44b600b41b	\\x0000000100010000
29	2	16	\\x6961588fd2e9d957c86f5ef829996180aeb86a8c59af39a671b480ae10454d4512c18b997a778632ff55fec45626ee1f99d766af011126b052d63c9fa7326100	184	\\x0000000100000100388dad7c6471a56e4a66816c397beef69ec2088c50393d1730a48bda8f0067e728f9d144370f3f2c485f011cef8755dbed498d55a932b88350c22d87e84604a7a2b937559afc80b495f09c7aaba2cfb515b29703c6324f5305ef7bc35af37f3e6c996d5000fe05554d4c7004abbbde6b9049c27a16b4e65d9e4d5e032a79c3a2	\\x930b777d919ac081f0b8d38b8f000681cde2de5cd7453c9f2f7761cd96eaffc6213138ec5b9d7322f01e2f6540d13576aa692a7f60d1eb7c61db8efa1427b21d	\\x00000001000000012cfc16f282afb982ac1d62d46ca68588800c074ba446dfbb126d3cd54a36270a061c7182ce3c3e81d168ca856b6c7155543c26f6a00502b4430a87f1a8c00c2433b9686fd55248a2e2541df484bad8ae72fe153eebccf3c61655ecf9ec52ea417af604a48480091facd762793714eb81a6c890a98015785b509dcf3dc95e2bae	\\x0000000100010000
30	2	17	\\x0327e30075a483e84b5be8240f7c8c4b0fc033e8881b12c5661d23271fbefb94ec1008325faaba3e63988cf932301a6d9eb4419ff0d52a019594e1cf3198c506	184	\\x0000000100000100074c198a7f5d9bb95a74b6d2fa2c8500d59d6330f78e095c39aba71d0231d121ac7956643640277bb2fae130a084064a9578114e665c0ffd9d2239adb79481bd43c987627ef1881bc17179bb5ed1616d33bbb7da87e656b1f72b6f8058b69c39e7ca617fbce3f602225bb4841e2cdb06cba7dd9991eb5d7082a9f8c1a1973341	\\xf52ea6ae882d3f567c7600809738d375bf9e3a8427ef6561c1a75aab4f2e3cd68b82768e1be38c8884e181c003a3f894aa5e56988deec27ed87b95a25bc12389	\\x0000000100000001c92d1655a98f75c44ae75630e5e3f00fb5079d3c029e69f7fdf3f10f48502d825828237d23b21b18cf96207d7f5c6dc87f6d3e5d05e7f35cde45ea3713025b0c417cd0a89503d59120bb5b6b3c5bd89e06b0657731a55ce8bc8e11e8228aed8d53debe210d1001a44240115502b032913ba505a89093879e6f2831cbe9880260	\\x0000000100010000
31	2	18	\\x0921fa6935fce5362de123267196d2b918e3dba27395781f902c29fb4fc22b8e26381955f613afa48dfeb39cfc79dd6b16a3eee7144c108b73e3d8b10a3c9a0b	184	\\x00000001000001001aca1b881370b74fd33bebfcbe68cd056ce6aa5716138289967d55509b8d0503c43c6631564f17bf50987f555f9e389a76a58fc4b3e42d85747615cea8ab91d53733f92af200f92f34b3cd933eac11bde67b8012de17934cda7bd162fbcfe6c6364617fd227831d0e80493d602be6b34c02c2a1181f7b7dd34190c7a883e16c7	\\x29337f8c5e2e36e73344477278189a85b6d9a334dc3dd46118e06e7654e80b0d21309f2115bbb50b4adedb474db2af1a82d901b3a7f5a476d8ddfa7f6b061eff	\\x0000000100000001e320ab3c46780610a948968eafe400016f40c21e2ae0af1fd2c6f49966f45998e5fbf00e4385ab8859b2fbf229c8d27de4a422f9a4f4a4562d2a06ed40ce95b131cc87be6ffba36a93d70c18e1d3691f8050381ff0251ca677fbfce5b01e5effa669348aea1da33b57a5a560af777ed175835ad80b0f100b25f97881273e2043	\\x0000000100010000
32	2	19	\\xc51daf60478d83f2b133b1f043dbd0d5b0ac615887cde53e5000e933c1c1a2599acbea47e952d98a2954886adc13bfb5520d2000b0579425bd5152214d4b420d	184	\\x0000000100000100b15ad1eafb34409f83387023ac5d80be35bf4138698bc28ec6729e8e03f229e41a212516a759fa3a509d873bff91de08c96ec855dd43edd0c1f7188410bbfbf491e947c65e51ff1ae932f68cacaf1b8a3417732bbda140353fbb7a8564a9142caaf82c5c1dc04844e01947775de45cd6dec128169db07e28db81d0e11c8fb2db	\\x86d784e96de9f7ed3c2a877466a5852fea098e225d68217e0c2be820f8cfa9816fd1dbdb253c72161550df6cdb9cab3fb07611dbc8c2f94248933f86db4d8813	\\x000000010000000151419d1421193c26310ec92596b4020a50d09fbf233993042123bb0c564b56fe8d715dafb69e093e2bada710331a38f51d658596817d871b529064471630e7df4c99872eed01b8e82048dbc04c217849fe5a7aca12c12c62cb6f4cb101a0e30dd14833f2bbded371fb4b77665167a2f079c1dc271cd91051878c478234c90c90	\\x0000000100010000
33	2	20	\\xfa2d95dcba65d95de369a6f3bc17ed145fd0b88db2a28acd3c63f2942c73647ce443a541e867cf3e33d6395aab6b77dbba551f36d4752316752b85f60f4ab807	184	\\x00000001000001002a5bd951d78320509da1e21a84ba39ae998a5174f8dbc8d5683b5e32215fd86f6b500240dc15f317cf0cfd0b8d6b8702b54af3adb46006d94ca42aca51120b578c2b7d8cb74f796604b40987a7643ddbf23cb7e7dda01b059fc189093292258de3c6b3261b946d490ad5811a672ca13ad8e12e97e08d61485257f714bf381597	\\xce5de58da7adcc65e85fe72111e0b15c8c75e1c9f8b0a09792b7c5aefb7b5487fc0ce5c2bab208347af897476bd0a2df803eb56f9bfc5b0c8496b124d1268448	\\x000000010000000163b073a513fd6f77d0d9bc789f6819cf1262bf15bee21bdde00097d005f3a0b3f7b709418a9c4121331623df1451ff37c73b0216a04d17998009fa1783aaaeeebccc1439012912ea051ac72be70307619631208c0e13450b6a3b335c4c01a87fca9af706d09c99c8be014481f42b79cde58970765cd66708068ff1dc8b98713b	\\x0000000100010000
34	2	21	\\x686229f819cda22e60b9fd30f6865e3656063dc10efa0373ac3e1ebe1a2a9baadfa3ae8eb8a2516cea66c903308fce55bfe168e59d8c201caebe4348a068cd0b	184	\\x00000001000001000a407b03b129a4bf9afd6ca9e154ed32433b58b966c6b54a31f17b679cc25dfd284d3e76869b40615aede0e5a92b11fa75aa0ea94c95651678864984884b3c0b7fc5498405e7cd5dffeb99fa5f6867d73b166d61c4ac16edabea68f23f42d002c1a19fccc410b696cac79d72d93b2c0821d5b8675ab174ed3374d8ff98e664b1	\\xff45d7aa7ce0e8ac62d77cc026e6beb4d735955b846e34f1625ab01d204feddafca0f65f9196233dcb02f57aa6ca2338da7011e4e05b80a175f1d6af876801a2	\\x0000000100000001dc2881f51de8cbd11aa1587b87fef800ba6ba77efb8ec7eb9106b8404e22898d1e44bd94068f40d00db57095ef4731267b93c839b69e2a41bb71837e8dcc61772fe8c74ad9cb08f779e7a396703771decc161116a128fadef449cc36dabb3f8b8075f35afff9e23285b3320613f0755313dd2b125cbc8f8eee705e20886b5390	\\x0000000100010000
35	2	22	\\x03187285eaa9a91c51af3b5f131e0dfdff0e4955bcf37a95ef8c9e501db827eb84da0b9f860e25ef48f4feb9310f4046bac8f74d463a27fedd5eaac334813f09	184	\\x00000001000001009b1b44e7dce0b94af7fee43850a7d525616f790ce5280177d82db5dfd766100ac7aa530f2de4a9f1cf2e02308b456012acb4a34add150eae6830582d7412788ea9374a4d802c57386da4badd074ce68bf2891bd8680090067ce67ea3f7bac80af9a1c78e1c45ccd4ec0ed5676fdf5624116686f4e13f29e52c1295195fefe3fc	\\x5c206ee86470d8562850d601d4fda4eacdb9944f8fd95dbffda2e04abaa213c1f99c59024f2ef0d0969112072e2300bf0dc369b0bf0e5c675b34c81119728f3c	\\x0000000100000001169ea35b512438a1664359226dcd41e6d184de52516ffcc57989406936e203634eaa2b560b2ccce4afb05928dbf2ef979aa8714cc6f69b195084e0dccd007dffc8a4e177fcfa34281b8daa6ce655a71718d817626c40c1517323661898b2c9f2e5ee8770becea663d700183db55bd09d7b3086ce2db1251268d918b889a18047	\\x0000000100010000
36	2	23	\\x7934e4f22ee8ce00e7db9a2d9952407635e97ef5dbef9cb854fa502cb5b8f3189ae52bbb5078eb8183efe616e85c7f969878a7b17874202bb98dd1401bc24d08	184	\\x0000000100000100eebed940cc789cce862826d05703a220723fb1decbb40e944b46ea249c7758e3cc171f5a0d2baa4ab69edab2938fbdd8a8c80b0778b44fd5bc1d6d883d565739caba6e0dc9813801a4d22e1f6aa5e7957e7d7830ea66d2ccc707e4c1be34fd58f9f19346e8477461c83d5213889351ccb9510405ce2d9f62e02fa7311bf1aa01	\\x9f3a2f7268d7ec5ffa6c4aafebbf1ad6678ee94aea43a99ea1b3329a4091be9aaf0fe196ebfe73ceaf0d24d96436972b7d61fd2bb45da5acd9a081baa0f1f60c	\\x0000000100000001b4d93d883b03494dd46e0b05c83c9d00ae98a2b49d293231fedbaa7d0feac203b95c5fa0e497e0e6adbf56e564d3b2940359f0ffbaa9cbdb3b0244e1cbcdaa73338745ad5fa0e43f2bf16d209ed817af593a8ce1fa832d1fe7127770718e3ab48d51fccf0a147b75cc4b822909f256ad7ba210e5967da7d0645a30002d026731	\\x0000000100010000
37	2	24	\\xc8dd279699428cf898f818785ef2f7cbd30965d1263503f6ec1ff9ec26980ed2d3d7afdd2d02352d578996c4e49b0d660f79434b5bbd4464bf5a455629675c0d	184	\\x0000000100000100f6b9e640fe2a3cc80b315008db5dca9fa5d5018b37142a5d3b93558584bacf5a1d5eb473b5bcaa8e5b10453fe0c7fe2b3735fa8898bd308d7e9ce7c2b942afcc404573a6bde03f71613b5dce571210f3e4bb4664ec1e2472d1bc9d91733fe166c151835f23b6a3e0787a7a96594f1e345aa84013fe9021e0a13923115374d3da	\\xf4ea135c6e34f15d4295ebd50cffeeaa50c069467e7af5e415b2e69a0a39f13819cac4ad8f18d68a29a1fe50ee49abd2b106a50bfc01117bef07e214805a2c91	\\x0000000100000001cc45c25b31aa6542b161e08806dade9f08b6405c04bb3a1dfd3b05adaaa5b666a5fed42f368121f1346ec2a01b59d3e1c6f5b4cc9f812968ea30780358afd80d7d5bbde933ea454c58c0aaa71b7099451715fa82dd7e1b32f4a934f499c8f7b328c581107887ca1038e75a4679aa346a8fca6516ac2b85d8230bffc86cc001e1	\\x0000000100010000
38	2	25	\\xfe03b60c05acf95f53ff59db5f21653ce445a3a541ba0b035ca83ef8c83252416be2bd8a0614822dc11754ca012f7170fa349b3b1f4bf69456dc248830722e06	184	\\x0000000100000100d18dda22917f524b1e1db7741716094c8108b174abe738b3735c1c41bc64e0d3de89fb709f32a022ee96d0e78e1f53f316cd133591dc00e39c3ba6b2ca2cad77e8216c15583ebb9c797df0410ca5f55c679b91028e3356fa17b73b2b7076bc7fbb8c715783a15e62b29e732515a79932e352593843052388c59a4eb1df69652a	\\x8c7b3884bb9978205bb7bdcb4fcf6998b3167595842ec5f367a69203503d88ad4bc22c0ac9fd7a317f2ce8e8902163d5f4ad1f2e988d7ff6830e8e4a23516047	\\x000000010000000130c21de1918f617f3a38d03a8a8a974dc5b0db070b4f5cf325620f72136b5a0c37cbec8b909f60c4b74fc2589594d5b0348a8fbd7a32777f3bef384d3dbc8a67d2058f3f39d6eaf5cca5b71ead38381366a26a7d4815acc993e0ab434874af1c46bfeffd4890f7247ee8cdac3048d8132ccaccea898529a4e084b500f051cafb	\\x0000000100010000
39	2	26	\\x787fc57c7f3800be0dcfa78f9f83ba977d3fbc04e2592fe832445f85b4275183ceb63500111f79e567720b260d671f45ca3e910dfd31d1ddc118c9f3e95ca10c	184	\\x0000000100000100f9d0cde0a68c427878f8d48bdc86e7c9914c35b83ab755dd362f5e13a6b125c5da7043755a2943d2cc0e8a15112853a50da94f990487e3fab9aa34f549ff6ba9dd8f128ecb679ee339ecad0a6711c6100540c8d459e11494e24f8424ff1bc2f439b4a72c06c370ca637651709ddf4d2b13ab1abc93e8eafa9beded3113d003c8	\\x210af9dc1beebe1b95b3a763ff70ea488f06c88189eb56214d6322066558ab0fde00843deed168d5116bf6bf2915faa86bd7aff99e886a9ba3132d29268d557c	\\x000000010000000141daa5381df888a77bace6a48e0b95b8497e3ad80894471908498e9997c591cd5bc59c5776a39913d620269ae19f7138c1ea79e510d35f1bc149e8adcfae7df40018cba96ff5bc234c544bdd91e6a15aa5db086aedf2676bb7b772ee610239c81b49538e4e38deb76a4edbbdda8c586e73abd7e7a745247b86a2c342c5ddf8db	\\x0000000100010000
40	2	27	\\xebc84f5742ecc9dd7f72772e9212d4eae228d9e1bc4da33f3dcbc94a6ae163c6b44496c81a2b38b35c36bad7a19caa48728530b2e4db5107e9f55ef088237300	184	\\x0000000100000100226c172f8bd2f57f3fdb6e7f7345d2b10c4f70a1739bc02a1aa24cfc3def61df4559bc0319f3f6a41df5fe47855056bb9d681536a78527cda99ca65a00c9c90f60f32706e3c4f6cea522ca02dac9a19a15c1490fc972da77947d4738e7ae2b3a4df1ea9be46bc9c7b2814084686c11d492894afcff9ae441bba43f1609932d0b	\\xdce49eb2a78136e55fdcc1dd7d34e6691259110ba1acd08e4d4ea8b1ddd268140483880edb61015fbdf780cdd5b4afe5391ec23037e70f623b2e768c4ff2593a	\\x0000000100000001443a239d964ac9317efc0f533b6715064c668fda7cb4dc096d04ed8afa942b4f90b7f4ea760fe207e058daaadbdbedd7ea83fa01fdb9c07739c0ee11ee4257946d10694b694885ae1bb9664664845e54b3645630669b7493423fc83dbc159c1ee7c2eb3126d3543d1fb90599ea89558120716485ad890f0dd91627c932d9cc7f	\\x0000000100010000
41	2	28	\\x4e8e0e6cb45d11bd51685a68f1ce4ebb215c51d4c600347e0756428fd9404f9b24645249d630b3c6672756685a5c5c5a89ae5cea4f0e954e4922f97fdf16e00b	184	\\x0000000100000100b85df274ed47a94d10a60324e1f6d002802e60a45b1068aeb3806c345830195f15e28380f867b9ac81e7f74a13f8ba0b3ba74a5471e0971e6d4a267d0948579cc85d445093801811757661e43353bf075affada100a4891242a50692a9ecc14635bfdbccafa9635ccc18fd93834fa53cef3ddcc26408e0660a99541b28bd3fbf	\\x0069466646630e4fcc9432b4e6ef31d1337860a79a2ca61677329212b5f9c37e827819afbe720da5bd3cf4e62eb05f3c81616468b1d474a8ec74dce4e9024935	\\x0000000100000001c734bf5d0a7f77c24ad1f7306af9a2eb12329c86c5d516def030e86c6cee59636c2bdedc7070cf05e969963f02a3498561af685678210f1057efcd34e5fe1ee282005d6ffb7059ab9e074c4adfff9901eacb0f8542c658131c111c3498eea35cc9f5a26654d2c943fe94c915d559109555cb629b5f3cce8eaac1c9275acb9707	\\x0000000100010000
42	2	29	\\xc5ab1a8231e6a08b9fe0d53e27b5085998c15d770b81e28047fc73d488eed51ca55ee39eaf49f868b9a551866512cc26792024877be48e59c9738b6984e97b08	184	\\x0000000100000100380d33b0d31384c50bdab75566221c979619bedb8e3f6689e41cabd9a1987569e5e68fc62abd81d29a6dd4dfec065273664c6298a2eb565486d4e9d0127c73a53e3d73e5665fdfaf35a92f7bf8156d880e31b34c802689dbe68637dc7890e03f998ffa638bb4c885775e206faee2944d2e1af97845bf57cbcf22e5c667b79a62	\\xef5320425b95f44f3634acde0e3a01ba127f67ae57800300846f4cd8514e39666e43c3c2c9806e4aa1bdba1256cb29784dfbcc8c8dd79f4a952ae00324250a20	\\x00000001000000015fcf5b9a8c99c486e3e9dcabaafad47d9597a1b77a6f36ed01fe0e1f03b8b5bab5ee8508b1fe151dc4bb5fd866cbcb943c6bf63ffe4e538b1466ee56612b08aac80401d638f2b665a70e9324832c762120e12f16a7c1226865ca2e48746eb94e090ff061c532533b549f9adbd4ca6269949ff9aa24d5a58d0d26d78b586461a1	\\x0000000100010000
43	2	30	\\xdc446b56bc2f71f3d86b3be5154930e1bfac8e6f9674a5d765526ed3597c5dca67195fff646119ccf498047ce511bb9bd428adffb93e3f79932a97d34dfeab02	184	\\x000000010000010099e02c315a963659e0ca141993dbd4419a2638e0bd68f5cf924ce486aca4214a4e13d8f69c069d5643f559cc8d24fb42e37f52d7aa3fd9a14cc1d40c38a4ae4af8ead6ca95e8ee57bc1dc51815f38234c4903ce5813c3099d7d7e4626b7bd2a1b9fe1d248da847bea1dc2193018ba35504a9f1eafb239421fbb2735719054bbc	\\xc78e759029c792431155e304bccd75b73580dddaf881a85cf01941ecd720fc8e1fe055aa8c60622d27da40d0cff6991a3498a497be8a20c7dcf2110a72303a6a	\\x00000001000000011ae151d766653793e15d33ec18f120421e24bb26948cb0ce8c5372185fd7c47f3e677cc25eb759bd1b065cda929a16f41847caf8f1d684d6d4621ffdb7b063cbddf2090792da2d222654badbddb37a1851d9c0fd75c9096c7cf3a52c84395d306fc6fb0914c6cf9a7ddd432b03f9e066303f1d29bbd5a4a02c9d2884bbbaddda	\\x0000000100010000
44	2	31	\\x1709f0f3c013f9e050d7c3554b3c4fe43d46348c72e42076f33cacac54a858811152b8355d05b3eb60d57be1b8c5df4b60a5c2dedb7aaade4a76ff28c195300a	184	\\x0000000100000100d7819f8c8d41a3168698351e83ad11f8f4b3e013c91d39a62b57cefa6a6cef1e08a204eb61fd41fde518af20480de867faf9bf458416173809ca9d1fda84ac1bc8c18b570ec5552cac62d1003f96d83f9af4edb08c88d7bfd79f73faa116519cf59851e34e2dbc7bc7341e015620d964a42e47008988521e61515d00fb0ebbc6	\\x180e8a56b993df43bb94d8922a6b22e651cef75f505dfd1417ea5346e82600ff1b95db2481fa7556a1dfc193c4b8e83552c4d4ba4339a5083dcb818fa9365f48	\\x0000000100000001e9f88aa386a60b91603f636ab68cd62b542a13574288563c217ad83f9a0d29754891952884f01d52f74b86037bbe84c07658eedaab5108474d219c587111ecfcd2cf2e2a8f7d9c06e4e25fd380d041dad11a4b09b3773ea339806a52b125bfa42fde67884a064f466c743fd25d0209a92bb4146339cd6be65baeb3b15ff0f0ad	\\x0000000100010000
45	2	32	\\x5a9fc050d357438bb0ce6d486a461eb9500856fc37fec9d2b12c05abd05eb67bb6778bf1d025e3a78bc70eaef5897d8f230e129167205056e45a1394b3d80b03	184	\\x00000001000001002d0d98ddcf6a407430bd197fdf050f3f51b6599764ac46ac26d4e92cc0ff619c5458f530723a88dc7cc6ed8bf55b230d2e2ab72250d9b7340be2baf5d247748b4667233a5e872ab0bc91cd8b9915430f777fad63446e33ae231c1788279d4775a42e1e13a379c01b34f14e9efedf873faa3b3c52d020588f65cb443256512e5f	\\xfbb2af5d94ab5f83ca377e5e919bae7b576794fe3ffcb023ba89ebc6d5dcb4ea9a3ee75477c6273f1953031f9613a72b0d2c21e8c2a15ef94040ee023f25a0b0	\\x00000001000000017f411799d2d7f70dc3acd37d1043c84051dd51a2082b0068eec4c3b35bdd70fdf31ad68b7115e50cdad572c34f4a3f9adff810661a1d8dce3580a7baa951ebb1b9058c079ba7abb626343b1133cc330cbc0b56285f6a0b86838c8ef072054f01f98e5b8bf7eb8c19b572004472ec6bd21dea3c71d8b1c7ff33ada7094731f9b0	\\x0000000100010000
46	2	33	\\x6b60b66af4a44aeb400393de3b64a0997830268d9c4ac6947d43c5a5a3018fbeadb1e22bd3fecceca9c68178155aa8ea2992d8f9091bd80ca132e9b4437c6f08	184	\\x00000001000001009b1543516f90077eed0bc5fca2a8d5a2d9d3b1596d83d0091db31b18a0b67adcc60dac8d1687c006c3ae4cc2bee66cf9a212453a4fdcebba1e76ef6fb0efe993e7f69a04528a65a158f37fd32013a50d2776656111591030d64099736168745743a46faf59b56c9ebf70b5dfe907b8dea5fbbd14779000a896a3c6bec1f5de28	\\xbf4300964d53fdc76b8111d19e759a1c173a1cc0a0b64bd496d98c70740ae369a509e25b832cea306da77918e7f6b791ee82df97481aa90349bc376be64bcb28	\\x0000000100000001e40c155f0b2b3cc8305f2f67d9398ff5a77422026c190d88624e15c6255f58c9875a548e33b2148f8037508f21536f8e2fa132dafaacb864444c2707ee5f6228545384c13fe97718f046d19900f3897e88918acfd36b2a8e77b9cd74a6be81cb5dc4023e9122718264e6fc5b144010574e67bafcfa4f8b44aa64cbe4905f5acd	\\x0000000100010000
47	2	34	\\x62839ad6b352db4e6fc764b790b68fc87052a4660cc215ea12d226b7a6bff0fb5756164c4a1e58ea4d95a910bb3922c37235794eb79d8bcc92c716788116ec00	184	\\x0000000100000100800665d35999099e59a6e1f16b22feaeab23e2c6e4782227f9328d7de89c2a7c489f0f4463f6af2640efa9a6f52778c261d6fed3ecd0ad07aed98403311a72add30867043ac22b285671277e37b38df113f3e059536224104745d20069af16f4d9c663ef45fc13fe9a669bd4d3581f6e124d456141a647a0ccd91c17f8ca1bb6	\\x82c8a4a5be54fa68a0b413e97490f92d8d47d4f0f9dd82e8065e0a58653e9009a8d5bc18c80182fecda1b25f16794e3e41dcf3a3cff2afb78d473c6afe68184b	\\x0000000100000001dfd14958496b84f1683e134c2a8f9ce0bfc497b7da130e7fbf41a46bf3899c31df6b8a433475dc27d96a182a79cc811726129ca008cc31b56aa3108a3afacd9edff950156d78f3191b7c2478081d959fd7421caba0f19856e8a59e77b22d85a520b8404ccca62a96cb06438270a941b62edf3f0dbbc0a754332e392473095fe1	\\x0000000100010000
48	2	35	\\x7c31b91dc3f91dc23d1346cf5944e6ec99dc5d968c232d3473f25bb60187b0a49caf5ccdbb5663f55bc1063248420b1c2c04a58a84c27453de53521106da410e	184	\\x0000000100000100a83cd81e97e332cc3e7a0a83d8d870489f3ef7ea885ce8517693959d0db0501e3e0d2c6ac63d873116ff9137e4da1f5ee5a4d497aee794731f74073a3c75e452fc5b15ffe9980c82c9a200fde369ee07108a71b05d8dec5765d9467ee9e638848af355da318f1af2da58f66f94486983bcd2a99df89698a72e9cfa738de276b6	\\x90b2612d386462433c17d978073e493f5b25e7bff57247b44084326607ecbac08518100758e72cb11dd16b20315a502c6632dfd9778c28560880fe6e4bb2ef42	\\x00000001000000011c2c9d8d6bb7e0eb5efa7d3b720f5bc377d132203f3a1c9ba1281b336de8b95ce66c502f58581f66f3995d28088c15aabe9980e63d4a85cd16077f516e36eb62568cf80eaf96173f58e7a9e00d0e094248c9086a08e113a2251cc8272ac9c518e2a3ecbd4edb82f4943e7145900f770ab277231ead8e75043e202b5f196b7748	\\x0000000100010000
49	2	36	\\x7801a97d764c9edbd2c7deb942b1bc2b5283dd9f9e104d55e92890bc187df79a647f473d8e318106972889ebfd06bf25b69ec8b8a0f04fc2b50b68db9c214b0a	184	\\x000000010000010056252b5da8c015075dba764effbdbbee800568cf9be67ab169fccd20b3834c234cff9cef8000cf04ae0777cc9c4d37db749dd69e68e4eadbc431bb54415f4c236ef488a1bfadd333bb4d7d28fa710cd16697084b833b5982164b7aa1618daf701e8ee8f2978b097d4f9efda481d318543a4bc6c6899f8f81ad9462ae0bc71876	\\x68eb6b1967b1bd7deb98708af604cee7f110a6700da5e7fc5bdc347487e019195b44917266fd2ff5bec16bb631ed05c5b2dd0e11ca6433b021949b5870df4e0b	\\x0000000100000001c20ca4214cc18c761d157a671f8b93aaaf963eea13cffacabcda3da73a1aec692735e6524da91efa1bf4da38c27032432c265eef5f62d37c3646baddcc1548eb1063ba8c8eb5f8f7237185362682005b4bfd8e8b8395aed830aaa7c61c0f2b2916ca98ede29352efbf6f5744f1d043ad1eff6a711ea94b01f7a5e60c8d24bee1	\\x0000000100010000
50	2	37	\\x065f5b875102522094f09a178fa3959cf9bbe1e181dcd60e16659fbb6ca2e02143dd044ea50a91ef96f9f7ea25eb00fbac7eadd87107b5b160be900d82802e0e	184	\\x0000000100000100e8a90673b112302d4d43e00074550d03eae73c47d21f57d0e515eef0b2165dda0b3eb598b7d6f4502dcfb5b29a55424380702acfad3b52b751b99d428bfe3fa330a5544aac2789258c8a2f4c9b4796174f9ebfb257fd879f429f1bab3873b0d97d35945a10add5f2bb124f988ad6352c1bbe59effd86b6dc5adacd90e2361f2b	\\x542b5a423a220da6e75932876be5b778aafec95defa6e72637e13221dcffc596ac214fa7893fffdbb6c3d823e710a9b726b4bb609f92fb8f67d821124e858bb3	\\x000000010000000127032209ca46cac57fc46090fb87fd3981dc51424722767a19d79ca1326299f53768ddcb913c98679ee4b3df19a61af493f4e919ccfe1036fd826536131d2b16c0acf0b3e1dfb4eb2846ccfbc6f0645e9eff329891b6c0ab72e6ffe225c9add7e9937f057b63bf69d7af8fbb97888b676e50fdb9f43433ee841fac4a780fa6da	\\x0000000100010000
\.


--
-- Data for Name: refresh_transfer_keys_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.refresh_transfer_keys_default (rtc_serial, melt_serial_id, transfer_pub, transfer_privs) FROM stdin;
1	1	\\x228a2b672fa4f5d983690ef32520ca37b471047d6e5f9ac303d93d729be28b59	\\x483f79f0e1aeb5ee7fe1d57bd1eb75bca03e655ac35c54cc48c6c9a7e75c568fd0960ebdce3911a7873c477e0122441fee7a5ade0f3394fae5cac7bc20b78300
2	2	\\x78a31ff7591cc4312201241b5cae3e86beea5e12e99cdd22705eee8eb29fad55	\\x95a13998c0984f10cc8280ef64728d532bf92c5f08133d13cfaeb845111741cb5e3bc2fddaaf17cd31e7c4b1d1c01b31355742ca9b83f584d12348a2678c987a
\.


--
-- Data for Name: refunds_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.refunds_default (refund_serial_id, coin_pub, deposit_serial_id, merchant_sig, rtransaction_id, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
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
1	\\x69dd5518b22cfbde0134ad3e152b40e5ec1ee84b704ffe9a468e494bb7166abd	0	0	0	0	f	f	120	1662290896000000	1880623698000000
\.


--
-- Data for Name: reserves_in_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.reserves_in_default (reserve_in_serial_id, reserve_pub, wire_reference, credit_val, credit_frac, wire_source_h_payto, exchange_account_section, execution_date) FROM stdin;
1	\\x69dd5518b22cfbde0134ad3e152b40e5ec1ee84b704ffe9a468e494bb7166abd	1	8	0	\\x4dd5ed62679bb7885026bafa24d03d481b609b1a0c3303d6d5debd6e0e991f09	exchange-account-1	1659871684000000
\.


--
-- Data for Name: reserves_out_by_reserve_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.reserves_out_by_reserve_default (reserve_uuid, h_blind_ev) FROM stdin;
1	\\x355918c4c6153654ca32b936820542284d06e140bc9c2f5a4f6805295425a79f65da268136b536cc1828c61b42bdaaef5722b9ef4cb04ea6876d7bfc88475af8
1	\\x9b2c2b520381fab20d9d9bc01e3bb9c84b23e8974f02265fe47e0a8f3110c5b57ec8bb5043ce6d21f0e684989f2e90d6c2ad5e76407ccce2e7b9e53b49ace4b9
1	\\xac89828e142798d82e1aa1eca417277bebcb26134e7ab117e01ece14c28e0b66fa4e2c4318dbd7961b3dd58482144fdc0ec57f736792673bcfeb50b650804f47
1	\\xacf6515bf0acef6a68e071c79241184156149a2202881caf5cdedde3012b330612441824054a6c2f2d2e31ca701e987f6fb0e3b62d9b615f06cf99a4358e3d5f
1	\\xd52cc36377f2c2fb3ec302597650d697192ee1e58085003a18a086682256e1b9b0943e4fa4ef28453e4c03d10e5a45fabb1d339f8807a6e3edda4d021e380bcf
1	\\xf30f61d44ab76f5481edc1c1d08f76d1e4ead53f8c1df36c45a62f35ca5108b3796fd223a20951ca010a656deb04e9d723f199606c87d7c0df127f78e7fc80e5
1	\\xebfaac26be521f2c25b84ada659c42b778f48d91c7f3b91ddb78c1c6d8f907c76c47ab7eda3e8df707366494063b7e499b27c17ba2f9f8391332c30c0370c480
1	\\x6ec123cbb1c6afc02349b9d8701f437054002ce53f08fb1778649e749b32cb3dbfd27a72f509f05da0082116097fce21f119db8ff0bf73699a239826ec735d52
1	\\xe8e5782d1cf31e87c341916ccdf5327d96de0dd7a00116bca16d8fb63cd81ab8c954d3846c78fb6f9949360ba518e9610ce81067e200c506090d012786a4eebe
1	\\x2c96a13e1b58f27b568fe9678984c0dae651a66e820a5ac6b7c9a1295e7eeeae4435cd11589104af80aca464789302247b1e1bdd9fbc344dd081472e8ceba371
1	\\xa02cbffcd44bb00aa5a0a0a37d4dc627858eae5b8de0563608ea34298f732f81c6529af59ed578c70cc8361e204e30515ffeb04861abf2d0188fa77840e7acb7
1	\\x84ddd4a28414025a1bb61e767c88b83ecd27648c095f5a79928e4581156f3cbaa6b6cefb2975d41bc06ba69b8c0f3d740571646c07d4b4cd3ef51f31fb16e049
1	\\x22ba89170433749442ad9435d18adfd9e94be5ab32f7e8835f77345e9da722b94d18d9c6e33d50fc2be6849961545ca521789667debbec2be73c0b0a77db5ef1
1	\\xea5a88ef2ef506dd6e94f3b0dc8eb02eff135ec60a903c3f50799933861bff5fe45fa276be8061594652a6c6153d0907dfa774bb914efaacd6e720734c09e4e9
1	\\x151fa9e4073d6e994a943b29820fe61db36fed70e5bfbc134cd8a940dbd764e7d1ecc475046d89338d903b1e64a4905f0095b754d98028aedee62e58f56cccac
1	\\xbeb930a96c64d4561898acaded45957fa2530dbe001a6aca6ca231174e8bc9653ff96c432759925a30aa1c2c035a971d7a3016cc11382a117d509d56d2791978
1	\\xeda3cfe0f9add3ec574ae5d63814b003cfdcec7ce769f2e096cf18f20202a55b72d36176f993b1b7e1012747b32ccc95520018d3ce9f64176dff28c7953573fd
1	\\xd9464b8e6e3e920cddf1950665aa617d64829709c8c3542c7c5b1fadf382f08df1dfb0d390d07e0f61d20fc4504e5e850bc527a4482a5927051eca26c92047b6
1	\\x4c2aa937322637880f9d90c258f63e27f2ae495e1cab4781755d9836b47a2a9ebb819a4f394ca02a4637d3a4374c80ed8d98c55b5609d8fd9751db1b89ead062
1	\\xb8e761812c4c66945a386fe9eb9d97a238021cbd46e50f70ccb89a2c37af66d20ba256ec7eaed43c14eda80dccfe9a650472203923c673f416e538bd4268aed5
1	\\x445ed1511af524b6c28ea0c31d07488f44de59d245ec72d8243dda0c80b7d59d945dde67079679a6df4bf07b57d9e630983c778519e3baab2ea8408cc3dfb775
1	\\xc023b486408d6c7e52678774c05dfffeecf0031b05bc080271327b892780beac32722a7a2846e6e5a103ac8e5fc6b686864b45ca9a5d1fe3cf40c5c9b32c220c
1	\\x51bc9b534245fa1af76834e8794ffa6edb55bdedf59e1e3bb3214ad6288c59bda491f4520ce7f5075d93c77151a032d367f4f5240e6aae6df8040038c593005d
1	\\x15565614dc6584e5f48f407854019fb3e0896c9d7fe78192997756bd29ffa2a7a5b0310c8a88f572c4892199f9e47c7b085175dfd0f011590fa34a21a981edc7
1	\\x18c358de4efd0c5a7770dd48ca0109a6aa25d3d723b295ea74a1161faafac4eb355ea6a1fbee9c7be5dd362de86b114c55c8312caebf2d77ea3e65dfa859fc8c
1	\\xf34a856478d2d008f167c8f223778a47a30bb4dd520c0e93026f2ac30d0d5a87ad7bc5a6eb8214ffbdaf71d4166fae4b11700e398ee27ddec53b4c4967cc1efb
1	\\x878964756e001e3dd629f0889a660b84cf11381ee5790c053c9f874ee180a058dce73809f9d6ae5beca522a89fadd9d438bea62887b689b20f55393fb6b5b1ca
1	\\x512cd7f3a8cfc7b35fd10a2bcd30c19b39c386874793af5b824d2c3f2afbb32c7b4b7d20b9fc225cbad3b085cae9dc6ce4f700cdd8016b9b08ab86e481d50d5e
\.


--
-- Data for Name: reserves_out_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.reserves_out_default (reserve_out_serial_id, h_blind_ev, denominations_serial, denom_sig, reserve_uuid, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\x355918c4c6153654ca32b936820542284d06e140bc9c2f5a4f6805295425a79f65da268136b536cc1828c61b42bdaaef5722b9ef4cb04ea6876d7bfc88475af8	259	\\x0000000100000001856bfdee7de72b45c0f58a28c49641ce3cf15152c281621c6a7ea90e4ac32d75698c48f7e829602751557413a45abd9c2f44b5b0cc426795f42ba12c86a2b765369b7abd1e1da88c626e68f2b6f72f487d7ab4d079be5e58f3b18f6eaa603524ebccb1ebeee441eb3dea7889a7f15f04343a18d1701ea50b03e085111cb5b623	1	\\xe52d9580cfe4c8ff33c4d0fccc4d4c08725ddb30b7a4a412a98ddb6be10a86721770f07f336204f280cdfe81daf1dec6eea26c94e27b2f74dde360c9dbb6fc08	1659871686000000	5	1000000
2	\\x9b2c2b520381fab20d9d9bc01e3bb9c84b23e8974f02265fe47e0a8f3110c5b57ec8bb5043ce6d21f0e684989f2e90d6c2ad5e76407ccce2e7b9e53b49ace4b9	162	\\x0000000100000001c1006506c1762b88cf9bbb2ef3716d74757589efc3f2440de5956470050923ba2cfd43d72640c0a2faa6960cf5e21e2df87c6af94a6527625fddfbc539db7be1fe333c15113905bc92b4a292e361b2e828345324a48504d39fdbf15b63a21b5c1c79dc6f32d17df817dc1eac4e006881bcd7ab9fbaf0c8ea306bf0a913849bde	1	\\xb6893784b436932a37891eacaf57b859ae3983ce3933b6592869b2ac54f7f656855c5e19f9d86118ec33762dbc9f1fcf4ba8bd3b626d510692587a58179e3a0e	1659871686000000	2	3000000
3	\\xac89828e142798d82e1aa1eca417277bebcb26134e7ab117e01ece14c28e0b66fa4e2c4318dbd7961b3dd58482144fdc0ec57f736792673bcfeb50b650804f47	158	\\x00000001000000019063fa7f1226a60d4753b62f2c8e570eb3b7f220bdb4c1a822f6232277a5550e1caa65c116bdb32335e8554d117b27b3483e6161ad684b9557ffd7237c96b443f8dff3700591a43fb1014ce71881775cdba1ddfef925a2beaf42d8a2fbc0234172f4eae0bbbd1f79773fe86856634e780febf3226e050b7092ef5f3f6a1008ef	1	\\x5c6807e09b81d2482856e9f090fd8d75e0e9ee69dbf09b1921ef205100ee483cf4244851e79128b7e2a78647ebba835571d20e6d1338a9cd8c936c03cfba4204	1659871686000000	0	11000000
4	\\xacf6515bf0acef6a68e071c79241184156149a2202881caf5cdedde3012b330612441824054a6c2f2d2e31ca701e987f6fb0e3b62d9b615f06cf99a4358e3d5f	158	\\x00000001000000010db99a319784529a5297eb7da5337c143db7a358c6796b7de98e0217492f33ec8b0af0dec24fd5aa69b4a6c1d26e42f3c312aa312a65f17e2f8a50022d89327dfd66c432592b8eedd7f7cce740186c6005a61621f993b181d6ce86ee5a6884b7f0cfaa6449d012a82327fdcf13e8b247893cb506cab7728cbc9dbb4e369f86a6	1	\\x35ed63b286439cf4706c4eaca63ecfd763cfa31eb35697ea9f17d149b43ce38cfcf124cc019cd1e19a3fd5213cd275c308e48e213929fd47a1dbaec6d27a5b07	1659871686000000	0	11000000
5	\\xd52cc36377f2c2fb3ec302597650d697192ee1e58085003a18a086682256e1b9b0943e4fa4ef28453e4c03d10e5a45fabb1d339f8807a6e3edda4d021e380bcf	158	\\x0000000100000001a0bcf73bbe5038c8c8f1d2715d9e59ff5de08525c6bf864d5f30a53c8d6770043e89d7b4a528c6f5c66ad2bd275c1ed1ae6d6a9eb0b75e8ed0de2228ccf540fdfaf8a3552724f4acfd3818bf169f0cb8cf0b63e60872a0d9de5098aad89d647d0dd1811f2c7edcf89e347ff7f145e97377e26c4db56ce0c221c412b358e16d15	1	\\x1febca03e2079670c872a2dc60f362473cc2d27103c6e98b6c5ec8c8c97c4ebae51ddec2f791a942e9a7c8ff648c92ea0b1656542aca1b56b7ffd8b8f485d90e	1659871686000000	0	11000000
6	\\xf30f61d44ab76f5481edc1c1d08f76d1e4ead53f8c1df36c45a62f35ca5108b3796fd223a20951ca010a656deb04e9d723f199606c87d7c0df127f78e7fc80e5	158	\\x0000000100000001506ccc4d27a4b292f8e6efdd69643e1736cfa377b9ed19cd3655aec24bbe0f7823fc83c93b1997b06ec137a50436d131b9bf22efc0404951f2470accd7d0575e1acc395b4011c741723271056bfa924a0bad59cd05208f3aec6535d0ff6033367c2b482aeedb91502714e0b6dc84ed6dd1202f5bc9de8dd0679d9028f844b859	1	\\xb1157644830478498f4ebf155c4411152cb96fb350e4283564e5ce0f964f9bb92854401a1cea132bbfb4ddb80914d9dcea8419bbee8f2025df2beafafe95fb06	1659871686000000	0	11000000
7	\\xebfaac26be521f2c25b84ada659c42b778f48d91c7f3b91ddb78c1c6d8f907c76c47ab7eda3e8df707366494063b7e499b27c17ba2f9f8391332c30c0370c480	158	\\x00000001000000013596419ce07ac6a53ccd6f4626e9b0a0976166af37ebe8fb979284665e3b8d4e88f8f8c6413e830a71dd8d50292201cdb1c6fa58748d688ab428b4cce1753774c6a280fef2e37761c82b1817aa0870bed35b4108efd614915efcc0bccfaff3789ed08b499b9ebdc4efa4ad9d0a7ba74f90bd9f4c3fcebcb047197542ce710e50	1	\\x04683f340786f0cc266a1429e1b91a353eae2973d801a4a1492036f71a326cf8cf2bb400d57ddc10b315e592b18809fab4b6626adbb997fd0c98ce687be8c00d	1659871686000000	0	11000000
8	\\x6ec123cbb1c6afc02349b9d8701f437054002ce53f08fb1778649e749b32cb3dbfd27a72f509f05da0082116097fce21f119db8ff0bf73699a239826ec735d52	158	\\x000000010000000144a0995de8ed77d014947c4261f72344bab4e08214dee41f252ea0948f46ca8cb059b396dd506ec232077660c7fd830f942ddc77fd8edfa3d69525d9612a837d6b44847b21687877c905f192f7a7475201be614199a96f017d9a63445c7f355abe41ccf4373601a69ba2e4c4bd5b7361c8e2711184adeca0477d32a399f02c1c	1	\\xd032818597f67b9c802dec1f8f0d68a80fc4520e7c557c4fb09955448b2daa814f7bae1e32c84d3cba8db1cd16c7a36e608de46242c7a8ba1f7a5ec3da2f2307	1659871686000000	0	11000000
9	\\xe8e5782d1cf31e87c341916ccdf5327d96de0dd7a00116bca16d8fb63cd81ab8c954d3846c78fb6f9949360ba518e9610ce81067e200c506090d012786a4eebe	158	\\x0000000100000001459d0f3faf12f347104567976a37a0daf44acfbf143fa2b79caa08ed0d50ecfa48bfe42dec120fa5c4627ccbafc86c80926cb8c00144933797415ff0f2354523771f07ad12165e63481d38656a66c4251b7e48a8cde494a05f459554ca6a51a0a898ef2c60ebb3b9c3a85cfc95893b2401fac5ad2c1b18b1a8fab610faff704e	1	\\x3835dc01e7b7b67cea07d17181beaa2e2a998960276b79389629771e7bff014c3ac77688879de30a84641988aa6655c583a1b4e53c4fa3cedd2139c9402a0506	1659871686000000	0	11000000
10	\\x2c96a13e1b58f27b568fe9678984c0dae651a66e820a5ac6b7c9a1295e7eeeae4435cd11589104af80aca464789302247b1e1bdd9fbc344dd081472e8ceba371	158	\\x000000010000000189afe2765e77b542d94dda20c6cff8aef5cb4272b840310106754e6d6b4e31d22c031818dd279228d53a6ac33e6747d8f081d0fb3927c41f5ac35c88a502c675d6edf6ca5785bb397a12ce27ecffe56ebe522c754b6e0307b14d4133e1fac4979138f2ce6d9e4908bb3026af546668fd5d192a66adc1ab97ae2fd5f2f441f179	1	\\x3e640a67975ed5a0dbc40a8ff02152a4cda6b139a2fdd9636f5bd6335f521c6c31e2099ce24d3c085dfcb45c6947214fb4365602cd2ac31e0b3e25f24788ed08	1659871686000000	0	11000000
11	\\xa02cbffcd44bb00aa5a0a0a37d4dc627858eae5b8de0563608ea34298f732f81c6529af59ed578c70cc8361e204e30515ffeb04861abf2d0188fa77840e7acb7	348	\\x000000010000000139ec0a879941fe9d5491c6abcf01ca09a53bd711f6b6c211cf41fa5b65c0f51a68897c1be4a8ad22ec5b5e80ce3cf86855a747dfda8b5454bc351728f438cb264281ac4844bd91a26056582286d9d15021c8ffebbd756a8078767537aaa05e0ce910183fd49a6c2697903069ed7c4471ab1e0a3f78ad92395981af4387b35027	1	\\x10c47075a35f12ab83837b1d1a43b3d2dd1c5a0462932a12b2620ad2c8cf202deb5e52d05b671d202eabcfce61290673807a8c693ae922a313bd8ff469f06108	1659871686000000	0	2000000
12	\\x84ddd4a28414025a1bb61e767c88b83ecd27648c095f5a79928e4581156f3cbaa6b6cefb2975d41bc06ba69b8c0f3d740571646c07d4b4cd3ef51f31fb16e049	348	\\x00000001000000017355ff19a1facc3df0c420e1f3db2cb43209e27d500b26f1615cbf306865a684bae4d3a169fe55bb3a1cd3cecc0a7aaa0d8a2e384c25bdd8b5c38d627c0060f9aed36947b64dd35cc30f9b60264c3c66d597dd43b8b1773bd46b98d7cba6ca9234d50486e35e7e31b7bcb76f3251738124528731a291b1b50fa9ff90ab90a2b8	1	\\x9629a677f61c1e91f57ada75871036ae361fa64aa342934a161b9864c113d16485ebdcbe1d9291890f048bb19539adba5d9fd705be1a0f3a6f536aeb38205606	1659871686000000	0	2000000
13	\\x22ba89170433749442ad9435d18adfd9e94be5ab32f7e8835f77345e9da722b94d18d9c6e33d50fc2be6849961545ca521789667debbec2be73c0b0a77db5ef1	348	\\x00000001000000015b73fb7e80b0c48be8b1b4cb1d886eea3707a2e0d12621161cac7cec968791a19ae94b3feb7f5120e8eb7c2fae2a0d076c4fa7b4c65c4ea223f0256378bfaeea90c5480e9d0ea7a598c67a0dd9de7aa4e8949689a9d2d92b553b26e87122d2b222634ba14a33b7ed9abd02e7aad08b391a3de6d1b6ecd802af715f091a993295	1	\\x98c5309229a11b6045542dd4bb151d6e132142bd23cf857324c80fddc0ee6bf362da2cfb76edb01710f3de2877d6b601beba070d7b1a24df4de9c29b8ef1dc04	1659871686000000	0	2000000
14	\\xea5a88ef2ef506dd6e94f3b0dc8eb02eff135ec60a903c3f50799933861bff5fe45fa276be8061594652a6c6153d0907dfa774bb914efaacd6e720734c09e4e9	348	\\x00000001000000014e541e4164c306e8f86d6a678bf9f0262270106ad6284522de51198ad19230cd6771b0424d3d573de20daf590baae0f74dae9ed85644de85460928cfa53f0c9fae29a73abd7e890aee1735884cd5dbf5d20c345eb903fd7a2cfdb40e73d4e48a504250ade8d2947cbe1453992336f69f1f946cf65831fd197d457c732fa68f73	1	\\xaa0ce0200f303fa161f2c52628b2689bd350c0c024c34ca14ad2ac661e67b1905ce028f0801ed3e00b1ff5c089bf1ba9bc0c138d9c16e6ab27dc0f023975390a	1659871686000000	0	2000000
15	\\x151fa9e4073d6e994a943b29820fe61db36fed70e5bfbc134cd8a940dbd764e7d1ecc475046d89338d903b1e64a4905f0095b754d98028aedee62e58f56cccac	125	\\x00000001000000011696b3fe864cb49c576badb8aa1bfad184b2088d1c3e8e96d6a1baf9fcb8e6404323123159c63a8d713402012572166f1179ce8fb615f66de87ecd5bf4282124017cd6bfff3ff044426b43f02c8838506978085cb05c58cdae8297d265b2b145ca4741df47fa88a228ca8c98c3a0f48e72213ab3355c224735e01b3f4adb2267	1	\\x7b91a1cd3cd1c49d17794bb9ed0ae7bdcb2ca04a5bb029dc64bd51162a4458daffd915bd0c56a17d972dde0bc6da36b8624d7dfd6d0512a05cac4e9cb1a05104	1659871697000000	1	2000000
16	\\xbeb930a96c64d4561898acaded45957fa2530dbe001a6aca6ca231174e8bc9653ff96c432759925a30aa1c2c035a971d7a3016cc11382a117d509d56d2791978	158	\\x00000001000000012f44a75905a5d4bf2c13a1c1c4ee3979e34876ccecffc3630ffdb330488e0735eac334b4ef94435550da0bc88566817cbec8634232703660171ab78fc0a5fa0d141e71813791f55e398721d2d6e384dd75f08e4fb2945c017ef287df7cc131a0c5ef971f0a7d6172ea724f0987544ba662fb629f9f374518c0f39de36b87d5c7	1	\\x095289fb62f1b0bdd3ee606caf8a117bf69ab39bb383b988e4ed5037f4ca11bfe55188d8a6aa4c45e1c2f4f825fcc4374f9cadf373a246c9e62cd75c9cc8dc03	1659871697000000	0	11000000
17	\\xeda3cfe0f9add3ec574ae5d63814b003cfdcec7ce769f2e096cf18f20202a55b72d36176f993b1b7e1012747b32ccc95520018d3ce9f64176dff28c7953573fd	158	\\x00000001000000019fa4d35551f294cf095252cc74337cd801798ce728474723958fe1e025349ec20165a5f58deeb0fb2d8d83fc17bb75724ec400072a57c84dc3050c9d706d273c11193811a747a65e51856ea0c13297c6ba569f39ec6517df1683b0c242a642e6270c65657a3ab94945084afc2149777f6482d7deedb3da8c0f821c74fcf7b9f5	1	\\xd7fccf5399bf953089b7a0a6ab12d3d5b8b6d2782e0a6e9664ea5b54be97ad649b7227b7ceb6ae8bbbe355b3705bde2c55f818a62176414129bc6f5cb8515701	1659871697000000	0	11000000
18	\\xd9464b8e6e3e920cddf1950665aa617d64829709c8c3542c7c5b1fadf382f08df1dfb0d390d07e0f61d20fc4504e5e850bc527a4482a5927051eca26c92047b6	158	\\x00000001000000017d3f302b49127b014246c691b238b0bab035fd04b16255110113c5155cac1e31a9a7406fafad4005600a6247c7b795e41aad995fc99f68f17a0b63ef94901586008eb0a185b96ecf827abce285904946c99d95277e0286ac0491084bc2f62f055a9dfd3119f9c84bc054900610e35917d476cb9cb96fdc08e9c18eab3d18d95e	1	\\xaae794c8c88c5fa6e61805d495fe23c38fe245051b3c4329cefb932df919725ef103d415e537140735aec0ed28b5c676083c2f76dd25981a9976d53b29b03300	1659871697000000	0	11000000
19	\\x4c2aa937322637880f9d90c258f63e27f2ae495e1cab4781755d9836b47a2a9ebb819a4f394ca02a4637d3a4374c80ed8d98c55b5609d8fd9751db1b89ead062	158	\\x00000001000000015d65cdacec5773c19fa79e9f1c4b0d416816e14cec2a6ba742ef2797a8cf4c7bd230d13dc64b507cb01995ce1a00ffe42678f596a5a000f02c57c0e71f0ca7068eccf2809adae69973648bc03354aa5a9563bc8ba368d4d1c850a2e90d3b637d841f1bdda0422de363626865132679c8aeca95206c1dd78d5fecb55eae9c90f8	1	\\x9ae6bd1d98f729b5392dc081b6dd4c4280439999bc9a4e0be0598ef1d57b8dbc353cb8e35f230666808f26498290b08dae5032a7883fe7fae6de3d1b455eb20b	1659871697000000	0	11000000
20	\\xb8e761812c4c66945a386fe9eb9d97a238021cbd46e50f70ccb89a2c37af66d20ba256ec7eaed43c14eda80dccfe9a650472203923c673f416e538bd4268aed5	158	\\x00000001000000018c4433ac07ffd549460bf6b1cf501f40affadcad1eb962499a1c1e27ea2befe9c60b7821ddc46f25ed03c6a18435b1c4a6c8ebe9579978eb51b0dfda2b766a359a17be145a2d16e7df6a4eb5c58a7db8dae25e268bd9588319fc95febfb9c616a97a1796d3eec929d5ebf15f03b09e98ea8f3cb1463563e92dcf1d6a8f6aa5c1	1	\\x061eda39bb480d4cba67d66b1fee4d92d4d4dd97acaa1f6aaebc744da5ab3e26dbf5404293731b83645e62c4b414556295f57f4d8f6625bb08c9c721f8fb620c	1659871697000000	0	11000000
21	\\x445ed1511af524b6c28ea0c31d07488f44de59d245ec72d8243dda0c80b7d59d945dde67079679a6df4bf07b57d9e630983c778519e3baab2ea8408cc3dfb775	158	\\x000000010000000107b21018e1c68091a88d5384e7deba183d599231b06c3cf29785e4632bff7a91ddea6b8ac8f6641504a13319ea7fbcf2cd2aec79466901d8e8e94e90cce55967d11ffdb498343e3d37f9eba46021e0d0d84792e55f806b00e0b8e4a371e231fef2b3e285dc91bffc27b78d75c46413781979aa95a0527c2ec1b944abab0f4497	1	\\x8df10454c2d4c24878875de63a658e808fd99dee1a3e29ef37dfe9e26456f846cec2704190238e9f74cb35ccbacd2e1bdb67048a6d420c1f71ed7e9cee8eb80c	1659871697000000	0	11000000
22	\\xc023b486408d6c7e52678774c05dfffeecf0031b05bc080271327b892780beac32722a7a2846e6e5a103ac8e5fc6b686864b45ca9a5d1fe3cf40c5c9b32c220c	158	\\x0000000100000001533bc063cd179b6f87e9a3cc91045ba134cc9177fb45aab547901a9bf130958cf19340ded6322289b56cfb980ee578cc78db0cba45afd7f7059c46a3b8a29f2bdd8266c30fac050fbcf30dbdf981c4a1753f888bf36ed95cd78bc8a7def1ec68d5d5e37458f113e43ef045347bacc46a770865a151609e4987f7ae71cf14da42	1	\\x3187629a94c1b7a231f00ef4458e6ef3d62e4f1294f1806a4c8713d5a454b5d525acffa4a1bc60668058ff62d1f32c0143e53d081ccacffe4b09bd0f3e9b830c	1659871697000000	0	11000000
23	\\x51bc9b534245fa1af76834e8794ffa6edb55bdedf59e1e3bb3214ad6288c59bda491f4520ce7f5075d93c77151a032d367f4f5240e6aae6df8040038c593005d	158	\\x00000001000000010f479eaca3d85292cb965f13043e8f4f0f63928cf484444b212830c1458b69be6420ecd4e2845d259971fcb57e9916bd9feb83920e8d0bcfd755d63d49150e96827e302ff4cbfe522b82ef361fbbcaac4e411f2f97e747365dac824d60d5ec0d264ccb76017650a024695a6f7f449ca0afd10e6c8cd5a90e8b1cd68f60b37f2e	1	\\x7f7cf984effb7a3b7d31bec89c220be7755f7aa91eaa563216994710f6e4d3e69e479bf007c59bf30ba57ef4a134aa0db5439ba8011104b964d11f680f02790f	1659871698000000	0	11000000
24	\\x15565614dc6584e5f48f407854019fb3e0896c9d7fe78192997756bd29ffa2a7a5b0310c8a88f572c4892199f9e47c7b085175dfd0f011590fa34a21a981edc7	348	\\x00000001000000017d68766d6aa990d5ae22332fc5272ac75ddc50f60b6dff706a91b99c02c2ba7466d3084a9123d24bf76d334cb735d33a0343cf13abe1ef64b9086049e2a2e6801d1ba2f1934c95325cedd843c21d834b1c4ad38ec403b29ed64fd11ca7548599817e47005e66169183d971c6f7842c0b41f788e8cb10484bd3f0b8838b55144b	1	\\xef447852e3914e2ea4774198a0a0db4d2a612e8bdd8876564e2fee588801c6002daca254717c9a6801b7927afc1cc7ed5f17a25a3078d127545c8aa93de6d20e	1659871698000000	0	2000000
25	\\x18c358de4efd0c5a7770dd48ca0109a6aa25d3d723b295ea74a1161faafac4eb355ea6a1fbee9c7be5dd362de86b114c55c8312caebf2d77ea3e65dfa859fc8c	348	\\x000000010000000194f198e07f3faeeca1b10ad9d954e2af3838b7620ab5f132bca41c9fab6562c06a5157098a1386960e2e02c4894977f4f3c7721de8f8cf85baefd5dec6301a2eb9b94dde56ee59c98b1c719bc8146b0e2b92d683236a7501632fa7ea097b905ee1581b33cc31667a00edd9d606986c9b49a1126adb8212363ab7ef981250b1a0	1	\\xf403209cc16ccae3e26bc4c2ffd47c2e127cb3a8db4be4c70d852e6f6915fe6b543398324b3cc8413c3cd67c71a3129d725287f246fda7d7d96d90aa5752d90d	1659871698000000	0	2000000
26	\\xf34a856478d2d008f167c8f223778a47a30bb4dd520c0e93026f2ac30d0d5a87ad7bc5a6eb8214ffbdaf71d4166fae4b11700e398ee27ddec53b4c4967cc1efb	348	\\x0000000100000001694fd4f7c8bc4d952603bccee20a9a617be927acdbe9028a1cc3b1751c43c5ea060e963fce13c30953c9322adb4c5617de46b632ce13dc07e55a9f1ac63fd52a2461e6be3d88b32f2d3dca9f00e960e04174ab68e901e3ea89cef99bfd362a7677a1aa8e56a637c91863757d697a7879834d40ea9c6cb1bdad5221bc4bfe08b4	1	\\xb532e7679946eb469e53cb4ac0087309e8b0a9b81e3e97fffe2d28db54ad514c1b0df9f6da5c921820442342fb337cec0c2599f46073542d597ea6e8abf5c203	1659871698000000	0	2000000
27	\\x878964756e001e3dd629f0889a660b84cf11381ee5790c053c9f874ee180a058dce73809f9d6ae5beca522a89fadd9d438bea62887b689b20f55393fb6b5b1ca	348	\\x00000001000000014d1ad77bc30c01f33128934a6a1d65620837670177c3c92e4a3027e4aceee64c527339c7d3238fd865e4edba35e7a1b89f2e76c9f070e9591ea0fcfcd9c40cfe63845a18a0c87e164a7835d725cb0371d01065d9d3b96c3d553acebf29ba76e65c8b837e5e897a2edc0edccdcf1faf787bd12c6b52b5c0cf3bdf9ee3b5be4696	1	\\x8d2549a0ec9c180d66fdc21aa8abf8f157d3e69c765f3be78ce4331f705f999de9e66b93a90b802e4974eba8f4465b6fcec3b27fa2b82641cefea4b3b31a6d0b	1659871698000000	0	2000000
28	\\x512cd7f3a8cfc7b35fd10a2bcd30c19b39c386874793af5b824d2c3f2afbb32c7b4b7d20b9fc225cbad3b085cae9dc6ce4f700cdd8016b9b08ab86e481d50d5e	348	\\x0000000100000001385ef823174aeda8e9c973665443ef8772732aaf18d2f40c6fec367818e63900890e5aeaf516c732a99eab6a9c8d9055bba1e2536a73d0706dee7a583cd64057b2e1af68dbbd511a9543cbc4f28f2e535ccaa3c7d71e0b12b7e64e846ca06019fcbed26686bd6122ca14beecaae26184027665474c39747ce7155f111c34be46	1	\\x1ba7d1e0e41f7d60165b2b2b57722bdf84b4c8a2f7e6b5264e42496aba1748747800d44eedb5ffd925b1004fb4d57e4430f64b0b0d0fa2ca22c0bf66f65feb08	1659871698000000	0	2000000
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
payto://iban/SANDBOXX/DE655298?receiver-name=Exchange+Company	\\xbb4a0cba386a5e654c672278a2d32b68a6aa8cec6ffcfc24dad80a4b35fc04bfe83f2f35152fe75a55b816b1f71fc7120c1d104de9514272d2870b4e03541908	t	1659871676000000
\.


--
-- Data for Name: wire_fee; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.wire_fee (wire_fee_serial, wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, wad_fee_val, wad_fee_frac, master_sig) FROM stdin;
1	iban	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	\\x25eedbf7cda8c42ac1a08985134244685920e0c61fbaf9ded549c39d4c73b91649965bb7aa5395b0d77e6b5955c5562f553de7ddadef3b642ce03ac999b7b90c
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
1	\\x4dd5ed62679bb7885026bafa24d03d481b609b1a0c3303d6d5debd6e0e991f09	payto://iban/SANDBOXX/DE235375?receiver-name=Name+unknown	f	\N
2	\\xd31e3f48cb5318906dbbb7948326362f41604c7a728323230ae82aa995f27400	payto://iban/SANDBOXX/DE474361?receiver-name=Merchant43	f	\N
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
1	1	\\xe51ebf3a33f7e5e597805e476c1716d5511fe5398713f3f5f23957710d459ae87a27c64f6125a67818954017b8890f2547c42ecc3eadedd31550ddb3c2825e76	\\x8eccb5e74a640607cc6707b719f94ec7	payto://iban/SANDBOXX/DE474361?receiver-name=Merchant43	t
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_contract_terms (order_serial, merchant_serial, order_id, contract_terms, h_contract_terms, creation_time, pay_deadline, refund_deadline, paid, wired, fulfillment_url, session_id, claim_token) FROM stdin;
1	1	2022.219-00H36HTAJ6CJ6	\\x7b22616d6f756e74223a22544553544b55444f533a31222c2273756d6d617279223a22666f6f222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f73223a313635393837323539397d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313635393837323539397d2c2270726f6475637473223a5b5d2c22685f77697265223a22574d46425945484b595a4a59423557304253335052355250544e38485a5339534757395a3758464a37354251323341354b424d374d3959363958474a42394b523332414d303558524834374a4148593435563633584246445443414e3151444b52413135575847222c22776972655f6d6574686f64223a226962616e222c226f726465725f6964223a22323032322e3231392d30304833364854414a36434a36222c2274696d657374616d70223a7b22745f73223a313635393837313639397d2c227061795f646561646c696e65223a7b22745f73223a313635393837353239397d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2253345650474e3032325938353333483559384e47564a484a48524a365839574b5332523232475852564336374e5956574b325330227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a22513847384b4a534632595953335252463953504a315159325034324842384b3756434530374e5452504457304243304b374e3630222c226e6f6e6365223a22435a3654574353594b4d4437594d4638544533374e4a48503848374b41574b3448535752585147414536453752524b4557365047227d	\\x7722f091ab62c51e855e3f7ec4c484d25bc2f1fee5858fdf9179f3784a73483c30c5cd3840e75422a2dc3c908edd7d6d498bcd0b842f1794aeb82f79c03a8e3b	1659871699000000	1659875299000000	1659872599000000	t	f	taler://fulfillment-success/thank+you		\\x8db92684a552bd72da0af43f7cb63c82
2	1	2022.219-002D2D0AG9M1M	\\x7b22616d6f756e74223a22544553544b55444f533a302e3032222c2273756d6d617279223a22626172222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f73223a313635393837323633317d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313635393837323633317d2c2270726f6475637473223a5b5d2c22685f77697265223a22574d46425945484b595a4a59423557304253335052355250544e38485a5339534757395a3758464a37354251323341354b424d374d3959363958474a42394b523332414d303558524834374a4148593435563633584246445443414e3151444b52413135575847222c22776972655f6d6574686f64223a226962616e222c226f726465725f6964223a22323032322e3231392d303032443244304147394d314d222c2274696d657374616d70223a7b22745f73223a313635393837313733317d2c227061795f646561646c696e65223a7b22745f73223a313635393837353333317d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2253345650474e3032325938353333483559384e47564a484a48524a365839574b5332523232475852564336374e5956574b325330227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a22513847384b4a534632595953335252463953504a315159325034324842384b3756434530374e5452504457304243304b374e3630222c226e6f6e6365223a22465438434a453332335a5751524433575a46473952583939504e5131474357564756344137483054415858425259455831314630227d	\\xca4d3fac6409eb06709e4c59ecaf6175a4f7de9db0acfa399532abcc35fc33bf2030d930d00d2326f459836ce4fe5e8845abe38817d8cf658ab1239b16eae0fd	1659871731000000	1659875331000000	1659872631000000	t	f	taler://fulfillment-success/thank+you		\\x662e23561b208b3668bfda6b5c5b7d3f
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
1	1	1659871701000000	\\x42dd78f2c728a422df6a57963dc060015a00e688da482f8f36d3d3eb902379e0	http://localhost:8081/	1	0	0	2000000	0	1000000	0	1000000	4	\\xb0a723ba0b0580c5dfbe59fcdc135317d053464bfda74bc96ee4ec340fe436b932e842ca574ac36ba4e267a35910c419907d0ed922828e39334fc86e4aadf809	1
2	2	1660476535000000	\\x078f0622928a34c823cd80a419ed70708b38af4cf9eb5e53fbe63f9b0fa4eb2f	http://localhost:8081/	0	1000000	0	1000000	0	1000000	0	1000000	4	\\xb52b477cee213cf55546c0f89a562b50e7175cf84abb2c34c199e64a2965f066b7f4430201ae6e355c6cb8ba7084ad0cc540ef7b7f4cb96959834526eeb0b205	1
3	2	1660476535000000	\\x08a01f5dc004bff630a90d20196c498e1f24ff66b2888931f1d751a67c6a9314	http://localhost:8081/	0	1000000	0	1000000	0	1000000	0	1000000	4	\\xb369fe9404de8a72c71a35b2c7102206c07ae62b1db7d800509a0d2216be0e05fd2d1919077cbe371c1e165a635ca9e1f2671d2713ba383ef7929c731598be0c	1
\.


--
-- Data for Name: merchant_exchange_signing_keys; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_exchange_signing_keys (signkey_serial, master_pub, exchange_pub, start_date, expire_date, end_date, master_sig) FROM stdin;
1	\\xc9376854021790518e25f22b0dca328e246ea793c8b02143b8db0c7afb7c98b2	\\xc3324f7688826888462d1831b4b57552f614b47f7fd756c6ae66074e17e5d195	1681643569000000	1688901169000000	1691320369000000	\\x36bc27213f27d2b889b1a601c46cf3f50b4081710b0fb78a64e5df2f8deb668d2e78889ed93a3d2f625b08c157833c196e45d1a91b424f7bc11d406fba7b2c0d
2	\\xc9376854021790518e25f22b0dca328e246ea793c8b02143b8db0c7afb7c98b2	\\x47f07598d3e34ca96441ad2d9d863ef19a2814fc5494326a961519f6ff3836f7	1674386269000000	1681643869000000	1684063069000000	\\x437698ee2ae6a2a992cd8201a6aa9da2cdc7b01416fc2ad2db23d05493e8c69f17d5a3cb78dd68daf15bb1419619560985398630553f0e7a6bd555c9bea91607
3	\\xc9376854021790518e25f22b0dca328e246ea793c8b02143b8db0c7afb7c98b2	\\x2b2c11bce0f007314cc6e2feeb837f91353866c4c0e71ec0f22d3752c7bc188b	1667128969000000	1674386569000000	1676805769000000	\\x449a1bcce10c09835445048d24ac0f4f89d14e12d099d0e8383eb9827d61391801ef81cec947c8eaddd573451612302b9e96ea49de618698a7d7b88ec40f7404
4	\\xc9376854021790518e25f22b0dca328e246ea793c8b02143b8db0c7afb7c98b2	\\x0c2df27e9e00661abcbf6f9a6986568e211eb396d619b2b147d6d52c30f6ab82	1659871669000000	1667129269000000	1669548469000000	\\xbe9dd7da6fde8b00dc9b016ec044f682adddcd0b61f92fdea10fe231515ec0bed8281e257a56333a72759ebcf008ac2632193319af77cedd9b6afecda1e9cd0b
5	\\xc9376854021790518e25f22b0dca328e246ea793c8b02143b8db0c7afb7c98b2	\\xf30aefe9e02a0763a7fac40a1ec2b001d4f5c925e45805b799daf859e7df36fc	1688900869000000	1696158469000000	1698577669000000	\\x3d7a456ffd1f510bb3df18b719aaf928c6aead7710adfdc1c6808d10019d570a0adeca8c2fce93b08e4780a0e666376b7a160f4e7767eeeed0248a7825866e00
\.


--
-- Data for Name: merchant_exchange_wire_fees; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_exchange_wire_fees (wirefee_serial, master_pub, h_wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, wad_fee_val, wad_fee_frac, master_sig) FROM stdin;
1	\\xc9376854021790518e25f22b0dca328e246ea793c8b02143b8db0c7afb7c98b2	\\x21e4a5e9d5d17432fa0b1f7a02f8047c7634c1053d6aa1f6456ac134caa8bbf3da7776a78f85636af980472afd166b4edad654979a89d92c49a4ba992a7e3571	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	\\x25eedbf7cda8c42ac1a08985134244685920e0c61fbaf9ded549c39d4c73b91649965bb7aa5395b0d77e6b5955c5562f553de7ddadef3b642ce03ac999b7b90c
\.


--
-- Data for Name: merchant_instances; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_instances (merchant_serial, merchant_pub, auth_hash, auth_salt, merchant_id, merchant_name, address, jurisdiction, default_max_deposit_fee_val, default_max_deposit_fee_frac, default_max_wire_fee_val, default_max_wire_fee_frac, default_wire_fee_amortization, default_wire_transfer_delay, default_pay_delay, website, email, logo) FROM stdin;
1	\\xba2089cb2f17bd91e30f4e6d20dfc2b10515a267db1c03d758b37805b0133d4c	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x0000000000000000000000000000000000000000000000000000000000000000	default	default	\\x7b7d	\\x7b7d	1	0	1	0	1	3600000000	3600000000	\N	\N	\N
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
\\x4e9be3fb35509baaea4e82d7f5290e5009de7dc2a2a1b52e8e88fc4db3059e51	1
\.


--
-- Data for Name: merchant_kyc; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_kyc (kyc_serial_id, kyc_timestamp, kyc_ok, exchange_sig, exchange_pub, exchange_kyc_serial, account_serial, exchange_url) FROM stdin;
1	1659871701000000	f	\N	\N	2	1	http://localhost:8081/
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
\.


--
-- Data for Name: merchant_refunds; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_refunds (refund_serial, order_serial, rtransaction_id, refund_timestamp, coin_pub, reason, refund_amount_val, refund_amount_frac) FROM stdin;
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

SELECT pg_catalog.setval('auditor.deposit_confirmations_serial_id_seq', 2, true);


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

SELECT pg_catalog.setval('exchange.auditor_denom_sigs_auditor_denom_serial_seq', 1269, true);


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

SELECT pg_catalog.setval('exchange.denomination_revocations_denom_revocations_serial_id_seq', 2, true);


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

SELECT pg_catalog.setval('exchange.known_coins_known_coin_id_seq', 14, true);


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

SELECT pg_catalog.setval('exchange.recoup_recoup_uuid_seq', 1, true);


--
-- Name: recoup_refresh_recoup_refresh_uuid_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.recoup_refresh_recoup_refresh_uuid_seq', 8, true);


--
-- Name: refresh_commitments_melt_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.refresh_commitments_melt_serial_id_seq', 2, true);


--
-- Name: refresh_revealed_coins_rrc_serial_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.refresh_revealed_coins_rrc_serial_seq', 50, true);


--
-- Name: refresh_transfer_keys_rtc_serial_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.refresh_transfer_keys_rtc_serial_seq', 2, true);


--
-- Name: refunds_refund_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.refunds_refund_serial_id_seq', 1, false);


--
-- Name: reserves_close_close_uuid_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.reserves_close_close_uuid_seq', 1, false);


--
-- Name: reserves_in_reserve_in_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.reserves_in_reserve_in_serial_id_seq', 22, true);


--
-- Name: reserves_out_reserve_out_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.reserves_out_reserve_out_serial_id_seq', 28, true);


--
-- Name: reserves_reserve_uuid_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.reserves_reserve_uuid_seq', 22, true);


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

SELECT pg_catalog.setval('exchange.wire_targets_wire_target_serial_id_seq', 4, true);


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

SELECT pg_catalog.setval('merchant.merchant_exchange_signing_keys_signkey_serial_seq', 10, true);


--
-- Name: merchant_exchange_wire_fees_wirefee_serial_seq; Type: SEQUENCE SET; Schema: merchant; Owner: -
--

SELECT pg_catalog.setval('merchant.merchant_exchange_wire_fees_wirefee_serial_seq', 2, true);


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

SELECT pg_catalog.setval('merchant.merchant_orders_order_serial_seq', 2, true);


--
-- Name: merchant_refunds_refund_serial_seq; Type: SEQUENCE SET; Schema: merchant; Owner: -
--

SELECT pg_catalog.setval('merchant.merchant_refunds_refund_serial_seq', 1, false);


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

