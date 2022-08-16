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
-- Name: exchange_do_purse_merge(bytea, bytea, bigint, bytea, character varying, bytea, bytea, bigint); Type: FUNCTION; Schema: exchange; Owner: -
--

CREATE FUNCTION exchange.exchange_do_purse_merge(in_purse_pub bytea, in_merge_sig bytea, in_merge_timestamp bigint, in_reserve_sig bytea, in_partner_url character varying, in_reserve_pub bytea, in_wallet_h_payto bytea, in_expiration_date bigint, OUT out_no_partner boolean, OUT out_no_balance boolean, OUT out_conflict boolean) RETURNS record
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
     RETURN;
  END IF;

  -- "success"
  out_conflict=FALSE;
  RETURN;
END IF;
out_conflict=FALSE;

ASSERT NOT my_finished, 'internal invariant failed';


-- Initialize reserve, if not yet exists.
INSERT INTO reserves
  (reserve_pub
  ,expiration_date
  ,gc_date)
  VALUES
  (in_reserve_pub
  ,in_expiration_date
  ,in_expiration_date)
  ON CONFLICT DO NOTHING;




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
-- Name: FUNCTION exchange_do_purse_merge(in_purse_pub bytea, in_merge_sig bytea, in_merge_timestamp bigint, in_reserve_sig bytea, in_partner_url character varying, in_reserve_pub bytea, in_wallet_h_payto bytea, in_expiration_date bigint, OUT out_no_partner boolean, OUT out_no_balance boolean, OUT out_conflict boolean); Type: COMMENT; Schema: exchange; Owner: -
--

COMMENT ON FUNCTION exchange.exchange_do_purse_merge(in_purse_pub bytea, in_merge_sig bytea, in_merge_timestamp bigint, in_reserve_sig bytea, in_partner_url character varying, in_reserve_pub bytea, in_wallet_h_payto bytea, in_expiration_date bigint, OUT out_no_partner boolean, OUT out_no_balance boolean, OUT out_conflict boolean) IS 'Checks that the partner exists, the purse has not been merged with a different reserve and that the purse is full. If so, persists the merge data and either merges the purse with the reserve or marks it as ready for the taler-exchange-router. Caller MUST abort the transaction on failures so as to not persist data by accident.';


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
exchange-0001	2022-08-16 14:54:34.489951+02	grothoff	{}	{}
merchant-0001	2022-08-16 14:54:35.567276+02	grothoff	{}	{}
merchant-0002	2022-08-16 14:54:35.998201+02	grothoff	{}	{}
auditor-0001	2022-08-16 14:54:36.138069+02	grothoff	{}	{}
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
\\x187042cb50680b02368d046f96ee44aae97cedeb6516fdeca2f4d3223094627f	1660654489000000	1667912089000000	1670331289000000	\\xc32561194b4b6682cb7029e149cb59c85de1968e440502f57040754b2a678892	\\x7264213ac164de65e186b021d57d7cb94ec27245ce25c0caf460ff9dad3463d213f644235699fd4cd0a4150f5f3d92c99da5d6d4d873ae93dac4407775bb6d03
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: auditor; Owner: -
--

COPY auditor.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\x187042cb50680b02368d046f96ee44aae97cedeb6516fdeca2f4d3223094627f	http://localhost:8081/
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
\\x187042cb50680b02368d046f96ee44aae97cedeb6516fdeca2f4d3223094627f	1	\\x00cdc96040fdb55b71f39af7132cb8d53a818197207e1160a403edf2de1588e579dd07e454b85706ec6df8f07fcfe773dfc1a5861f8eaa7b90e20ada26986c50	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x4e5560fd6aaedc6a128debf56db7f43664b46eaf7a1707c518d899179a3d7cd4d3c7da4e984a05978144f9d14943fa4a1ededd44e4be39ef34a1d81afea70050	1660654520000000	1660655418000000	1660655418000000	0	98000000	\\x00482e972a0e5c2d91efad58eb2f298fa5604f7879e9be37657061e6fdd5e53c	\\x37e1f963450faee0d8a56acb6aefe95536fe65cc8b5accca1924c6093a40f6cc	\\x81494bb48a83f0f03d5d0c86d1e6cae6b2b3713275415be99e113d1ff4eadfe4529cc7fc87e739ab13f1e0c9f0d1b8c709dcbe5b11bbc0f2626a5e8ce6d4a202	\\xc32561194b4b6682cb7029e149cb59c85de1968e440502f57040754b2a678892	\\x40127465ff7f00001da97e72d85500002d291374d85500008a281374d855000070281374d855000074281374d8550000c0b11374d85500000000000000000000
\\x187042cb50680b02368d046f96ee44aae97cedeb6516fdeca2f4d3223094627f	2	\\xc322b4ebdf16614d1c5a72ba91989486cda1e26b02ef26d105f71bd952f2f22b9f798dab19b98bf191c662338f571a6c295caf24ef961390262b67f697a5c7c7	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x4e5560fd6aaedc6a128debf56db7f43664b46eaf7a1707c518d899179a3d7cd4d3c7da4e984a05978144f9d14943fa4a1ededd44e4be39ef34a1d81afea70050	1661259354000000	1660655450000000	1660655450000000	0	0	\\x00ffd8756285c382ec9c7cbbea48a2d0daa35ac810a8d23f126ed758eca99b8c	\\x37e1f963450faee0d8a56acb6aefe95536fe65cc8b5accca1924c6093a40f6cc	\\x585af5eda8b3f8b06ba72dac11f599f6cdeb4996814c59096b018dfff955571aa2bb3366c4fdf4a92e56b9f97f92db2483d5b6ecae4b8eec1e4d4a767147b20d	\\xc32561194b4b6682cb7029e149cb59c85de1968e440502f57040754b2a678892	\\x40127465ff7f00001da97e72d85500008d591474d8550000ea581474d8550000d0581474d8550000d4581474d855000070281374d85500000000000000000000
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
1	1	53	\\x4c4f77bc94921b6d4b36416bb72f48dfd007196cbf7f63789aea562be867b0293e3e7e1f0675044bd9030822e1067e090224e832ee753138312dbbac853ec208
2	1	188	\\xb6419a9217afb165fe8d76551f1ff6126ca7e9ac1f35a3f750faafa32047e896ad3c76965d6ee186f087b06d3e9983c52210bd59dbbee3b7983c8d403ab83a09
3	1	235	\\xe7970f69f7de28f1d40d4316ca7e93e6d4ce7d658cb6f67ac7fd32957790c9c603439e5f4bf6e9c0e6e2e23640069eb85ef59b0fb691cb09e47d6df48cff670d
4	1	73	\\xdc72947120cb534440d4a71fc7ecf9ebb81124854e6744cad13dd758ac432e23dc1dd2816b357eaf254925ede3d0fca309a038a02ee5e5f96109ebdd9b806d0c
5	1	122	\\x39d00248c92e8934de06e2841255bd40d1d5648a26f8190168edc1280a8ed9a580caefd42a970ba39a429f7ab51ea4eef1d384a4e8e499c643261e1953532605
6	1	130	\\x2967414d578a310e89baf62c9f93090580676f7be2af9e1a0c890d2f99d6d723abc7ad0f7bfc2c53c9dd888fa867ffd94ec1598b7225af55cd528e56eacb7701
7	1	154	\\x1012cad01868c8c7b91e2f0de7909fc3319cf7634a73b29b777d04ee1dca4134297a31e8cb06d7dfefdd23bea3f7817d928b1ab21642ae3cd002f0fc9cac0105
8	1	307	\\x654bf2a169b5e7965fdd31d535c554dbf75bb0d6b61a20f51aed8357c52789945ac5e9f5727d461b0c34864db06e56d9ddb32650b92f99361ea198c3d92cb80a
9	1	146	\\x9d355ac4fc8efeaf4208a9be9fc3ca3a2c14cad52ce7109e5175ce895464e26768456c32c6efa867ad9e17a574d703b17568ad2c964d4e65accdab6fe356c301
10	1	60	\\x67424679473907702e34a0cfea23136922232479fe6b4a3c5c63c197288061452f5c49ad0a537e460f600bc43b8b5d8eee9663b343a3a8dee56c576747f7b80a
11	1	99	\\x96f4345f54791d1720fa24537b0e4b93afb2f4bc1efd112942c6e4a23ff248438322e581eed26ec14ee54e883b8b149bf6c34376affdf0d57d2ae24c961de20c
12	1	300	\\x16f42ac5697c7e7a3a763b37b83b1ed18c75e5fc1ddd74b34a980e7b115f41602130c2d427aa9fc3d7e418ece1f8c9ebd1e2ebccca3392ab7a672fc7dad02d0b
13	1	128	\\x42bf41de89ee5164e903f8de18d9fd40884c3be360b843903485d67cf5334c0b273fa6570339105a121e87347c47b6c467169ce80ecf6e3e36e8b476c8735201
14	1	416	\\x2f1dd914dd3c5126560285df5424a54205a16d2c129b67b7988f77a74fe703cb01d0e87fb7f0838680924ee3c67543e61481070277455d21576e6d548f0ae30f
15	1	219	\\x593d58832520a809470a273dcbab695bee86005c06ddff6c5cf3d3f5cbf2d5e59a5f4799de25380e64ea1d6e18bb6020e71274125c8aea4757e60f7ca2bf8e00
16	1	4	\\xf64d60cb74156f70eaa610e187d9a0726bed94f65bef058384fc7c81f9d0ad63b0faf148ecabb89f3584de95492b22b86dc1dadc7963ae866f05dd2b5dff9701
17	1	313	\\xdbea3d147468a1a416e870e16c862734ed7e18b4b8158784e9aa863adb6724f407e1d7bdc074f236de7e9cf69f3944e974fac1b60577b313ce5f735647f0cb08
18	1	380	\\x2f467fbbd6cd022505f62dcffbfe5b19393c441fc99f948e2eb51d56ef0b35ca3cb35cbedcd2881d94b8a545b7f71889d5d9f72da14cf447bc80e2ce8a842f08
19	1	79	\\x276b7a10386f95f5866b09ae341d558e8d1e19665cae8aa89f80b0b0f59c76b0c9b057b60e3306ab2a9b5cf4aba33f2dde043db9a1dc0426f24f881bdc38d90b
20	1	327	\\x3d6fdce891597b9a9fc0fe661b406b605859fee79b6b9302cb59e6d9441e68e35f9c02e94e76d42eb57e54142290fdb1fa4955ad107896863e50cb7d65d90d08
21	1	408	\\x349a338eb7fc190c674bf7286fef803df4f15c4b31ebc5fd0a940e37e9391aeb2d5d4a47954787763d45ccab0aa345fb7ef94647a5492576e40650e85a682408
22	1	202	\\x2279ef08f36b417d8d0955a3826ec744f7e2d6a88f574d3af09a9605d808bfa7fc8d2d315eafb51f00d61d082b069dbe361c367c1abc5a44f4ceefdc65e2440d
23	1	245	\\xcdb357bfaecf3998ff7d2d3df31dd34b14f08424a29c91f51ee4e29497a02b9ef79bca598e5bf0fc93c67554f986fd45bad43bb3ec3511fb5dbb6eb8bc31a108
24	1	279	\\xe0b14ef36ccab98640fe28f943d21828ae3b6de38f9a2b89de5f6cf05f31c316c1c94ed9a2ccb768991f5a38b9818d57748eda2f8f2631425fbbafd9afd5b307
25	1	240	\\xa3c6c052e2f7c574bc49518df2c6d74991cce6b4c4dc6e574dc88402ec44220206bd7d094632f487c65959967263f7581a923ca8ebd50c61c04853c04be6f405
26	1	326	\\xe94a30ac6b4c505aafc8bdfaa31e789ce2824685fa84c9c3ea950d33d5b15e0e987fa75c4e400b2f7cf4856d36d78344c14d343ceeb583b32da562150a23940d
27	1	120	\\xaedae874a778212dfdcf9623df4c95e272a014d665385dccb9876bfa0b1443125dde124a18373210ca436a373d9176a8c246bb1dc3faa89536460bab2d5a9f00
28	1	54	\\xce340e000f547e4c759f61ce610448a89a7da414475188b9dc7d4e8454e8dd3ae95d57a50b28188a06f5b7d7a44bb7ea59669a20644b5e1213670f8ac1b60109
29	1	320	\\x8fbcbc8bc2dd02b8e92ab91caa5596bf5fdb651fc5cccdf0f9e0899e890696d28133fd631dc7623c0a368331d9af508efb13ecfb2cc4dc91c3a70b1c2e264b09
30	1	177	\\x1cf7a4eac1c7228eb8dd3cc965cf1d05819d8926804eac0c3f3b16fd9250e7a789a1f06e5932bf25142ef5833082adc1e73d5ac1d66a156ab3d216c5da39960d
31	1	321	\\x4f6c3912947eeeed495fe987b06105c9a0b340c057a641f1fb57e0dde3e45d29479d4bf695aadd70264bb4c7829c472fd8a27c2ae48e40ac7ef304fcc66b0305
32	1	115	\\xcb6c9729de7ceee55dc89109819074dff030a7adaf7b7ab17d3a2643d03107d3b87c1c79ba39ca8f8e0b68df55e6ad787cdac07936de27cf262d170bf5fcc007
33	1	26	\\x4038511d6aa4f3c9f3a69f0360078fd0b2becec0ec798a39b2e47718255e6c9d7f94a9f8e2bb4d7ed5047e7639a690bd78c09dfdee87eca03cbcc1adea9ffb03
34	1	399	\\x1d9a5a34180426b9dae75de5ea716879dc57fc29e1e6e4ee7439d7f6cb7fd44cadc869d91844fa010ed1a90cd3a6f2d5415cbabfc97016fddeb7e8d8e8e79a0b
35	1	220	\\x07803f3a6e3c1c17ed00652bfccdcedfe847d8bf3bc081b9db90821339212a4b60b62734a658a5481f4ba46aa6d7081d6d77316d4ef515e051e4a9aa2f025d0b
36	1	232	\\xbfbf2c5952bba44e00712dd8ccf5f974c5bc05d7f2d1598bd8329541fdc3ce2040d9a4d2485553fc5c0278e3f16057a4ccc5fe90e610519a7b4392b2911bbf03
37	1	342	\\x67d065c8d9b9ed9a5831e7dd295a679788afcd0389773acf8ba60b02b5716549b4d33fa45fa52e006e53c1f5f972bc6bb1def854f2881bdd3d7badef56271606
38	1	273	\\xc3ac2d95d054e45a18c6130d7c16f6820ee0a2defac14cec580fb0c92a4d86b941bb2bc890133f91db05f63c13754121f749ac9c38a310e7945b8e7b30ebfc03
39	1	347	\\x29e5cdc40c5187d4ff3cfbeda899c1a1a04f68fe7c3d19c69ac66972f3dfb1dfa1df096b0347b5919b71d0ef7be7ace81791325468bf4a713b26118a29d0a803
40	1	190	\\x6329fe5316b2c7650c0c4853750c3bad50726202e57bec8080600ea4498efdfe457703ca58369a159ddf2627f02e9774580a1f379be59c41d2fbb5650ba61602
41	1	324	\\xf841d341f796fc34470ee2a7225445e976df4a244b9919eeef2904f5f9029cefbe3e42d961c3382b78a678c079eb8aa20f542a6e5eec6ba2876a9a9976e0320f
42	1	82	\\xf342abfe1464e4942082686ca5e1ffe6138bfc142e609656c54f4abd509cbcaf23c6a47bbdcb3b5afd7e4292ad6448dfb74e9e7e372828bfbea079e5ba4b4504
43	1	422	\\x995ccac775d53f8d53bce5c991cbf08f5b1123a0042d67301e0d9790c263ff0b3a8cc6e138f1320ea7361f4a9a90d9347f88734b885ee2188d9042d6dde1040a
44	1	216	\\xfa141b8f45f6d5fe3ffec005978b1f381d21d90f45a4068d06a92278106e9a585b934d36d6fa7987255e3c006f2023e6a88a5076491a220e02926d266a457d07
45	1	78	\\xc15565ba53a0e7bb2e91dac46d91936528ef8a3cac9931f0093f87db0a587cbd03a9b98102d68757dbc192a41dc434acde771eebadfa2815ba09f93e52e2bc0d
46	1	392	\\x008f28ca38e33cd5d3aa0258995817e81f86425e58eb16eaa034fca1aa62456c5aefceb4c261549ff22b88e689d42ccf62f6d6878de08cc3a7233cb08bf73909
47	1	49	\\x3486460fa6bd6fe8d4f6d2fdb7f5e151728283581e679ed255602b42e9abf59591c2cc0da4c8a6184b2ebd2e562d22c775d60d060f5afb6438e6f9537922c604
48	1	40	\\x584e06f1accaeb58a066f2a90d5decc1f1d490ad5c05412b9b3f8eace0f20f44438381b4d903461534e7d25577779af7edd7eb6f9888e10ab3645d4e14c82c06
49	1	226	\\x4316f7530852e995d2b5c13d0ba622e896844c8afcb95d7e8af2725437d3a615f548fd06839d2d3ebe388e498b6346e63513021331fcb73c15415e3bac576503
50	1	83	\\xa21f993cc7bd4008aef4087be2672cee4124d9715248485d8401684ad67787a68e3cc38e0d901f38cafb6e82edfaa87bf29a0556e23e8d6edeba2bd2102cc10f
51	1	401	\\xe63ddaf736a36a789304a0d68a7255186efd69673e6c370d48dde41cbb1fd919de83c439f807041e046848dfc1a5c8a726716a2a0ff829cf6f791a0ff21b570b
52	1	277	\\x160a21896f8f0fbce1b290f4d8ff267e14168a3381c0fb0c9f085efdbc0dbeca931c1eb7ed5656c9160e4c50dd087b69dd106439bb1b36ee9ae10a4f34fed70c
53	1	368	\\x9e14262a6f3422e73988901c7773e473fe050bdd5628a91fdd235ec551b8e28e0062ef8fe05d0f85e529fd9592298988b69ea7ac4e513d063a5bca1ed207bf0e
54	1	251	\\x6bcbc2a74959e206fbe0a2ac9589e2cabd54b931fd3bddf86124da39f6ce0aaa44372e25d307c57d64a6c0b9f54afb36877d20c955869980251e03aeed24140c
55	1	227	\\x221806fa78b3a4f8a1ad493e5adba82dd360ee088bdbebd60e700ec7f0391ca88db3f98788e468cec702113b3587a27a17d24322d3c40edd5134da431a044c03
56	1	389	\\x3d473ff8d748547b2db5fc6299773f411fe90ac869520dc6668fb4f99db3c8b80538db0298825954e5d99005d3610bdf0a3b1d54c966b40d2b6ffcfa5dd4fa0f
57	1	27	\\xa12f3fa362efc945c2c302fb54bfead972ce51d61cfd46985d9630cc18e4ce1aa3170f5e014dbab715027ed55faeb0e56eeed7f614f02f38fcecd062b380190f
58	1	248	\\xe02ecbbdb0b07c82c33697c181c53e30f858e131255ee431a6c1693f71fad142e63328b825307a5a12b33a6e6a1431b85e75d6e0e8e2f61f1b1e1002398c8c02
59	1	335	\\xcadcb708d07d74515f9b709f0fcb60575edaf72bce1e30a41c93e283df5a95544de6a416f76b8133942103f2461c1c561e8f48dbb8e4b3c99ad15a64b5259701
60	1	413	\\x7200f8972ad6788a49ab9677fb07accce3312a1ca909d2aaccdfd5affcf7fae86be85bcaa997f97f2fca5fac6c5a1472cc75514676a2a9080e3b1c3f46347706
61	1	58	\\x1224fb4812c96f4bc3c92642fcf6cad284f5987fc601bfb5a70bbc358c0ac022849778e9fde647ef16d1a492bffeafb04590a5db081ffa16067960a09b28b20c
62	1	168	\\xa96ff1920490b887c52f8bd36b9db5e948846633da517e362387260d3ebe6f5bf3eead0c5fef0f86374c39b64370a59bc82299fa65990a0de3d6a8263e97db01
63	1	97	\\xedac6d7b2477b0d548d8ece9c193940ff84774380967f5f7b271ee86405b9aa539da2097eb7fff97ef4bf04155e238e38030576817e25ef19fc6eb121b036a08
64	1	370	\\xa45dbc3a983df1cab301fb251003b08ed7773a46fcdd59232b52b63ad1156e348376daa6b6d38276a8f5b490bb4790d569fbc88588e59690583ec43566f4ba0d
65	1	31	\\x7ee4d20dd710b4006c7b24d6ac515982f6aaf1c54632a0f66bdd607da047e3a893f910b83ed4cfa3b127fce28e37624d4701c2dc1ff05991926752ddc631d907
66	1	7	\\x7801e1e0f11e76b38beb091b2e190d39c6b78582b85d82f23b8f60ea7fa8aca4feb88103a56450bab391557eaa1da69b91e0a6762cefc30bee2619e0da8ddb04
67	1	199	\\x1a3a5364d6174cac29cc427163d0037e6ee5c0e70215dde3f43b67eba902412a648cf90875021de6270362c02f7331f7ec737792dd78de49d6237b1be06d4607
68	1	252	\\x5b1509ba91769b682ee5880a1932bb9e3955f3a9b3d64ac9c087690a7c850ec842ce2e4c9e4806f9544366721a41544b4867b951b289288d4526b00675a09501
69	1	209	\\x71cebb36bad4638ac9c625187c87ffd997bc3d23753f461d1cc9b226f6385ed9006fa1c2f80297bfd10c49ef02cd4f03456d5eae11686051de2c96c07a496203
70	1	253	\\x142c81663bdc42ef08485e86a284d00c763acb3ed808a98d83f903acb07145af7de5f08406fceebec59439a3f7659c0bc1a236fa2853fd134abed9507e3f2905
71	1	341	\\x8caf5253319635284cdfdd5bc295f1aa15eaa47e809997f294f4f69b64a98ac55f1d3dd6ac8780fbf15e1a550d73e7947cb0632c455873b8ddc4cf566500e206
72	1	156	\\xf85a84fdb46a631f2fbda5e287fdf1fc2fceead3320ad5e7d3001be0587051a02803b0d05c597d3f81401e79f0f1e9f5010f348e19c440f6936f8600e297a20d
73	1	96	\\x8c94b0a326365f591b9dd0082ba20da105f691ae6ebaa506ea40130187c242e21f48c751dfcc7901bf71ec9c4171849930fd11a1c1725b43713028deb0200002
74	1	424	\\x2406f4e30d5bad7516c4c9e685784b279986e9b19e193a4b3ddb09dd6899066c1f03013e7dd808c787462cf8b5b845b9704858d06c09207e5d7e908e79841d07
75	1	237	\\xd0e062fce024ee2820f3b0900b623c7e0d5c6e25eb47a80ce3dfed57477c6b3eb969e64dea8ed91002208b34627bcd2433cbab3252c5fcdf667b9b0733c7890b
76	1	403	\\x1b72f2976e9f4519c58bd82e6619f37221c9bd9eba167141e901e2010911fedd266ec77fb2be2e161f99f82de3b2e2ca7ff765416ea1bc2b785cac31816ded01
77	1	244	\\x59aa6351b5e5d0d955ddc6c3ba7c75ec58ec027b263782be8d24f145714434ff3ec568f088182e9367e8ae94edab7eea7d3162569bdc22ad45fefbf0b6abf10d
78	1	121	\\x55e1a80f3ac48beb4f9a0b1630f70045ebddd2fef99ff83d84df7ac3e474e70b200803642eb1631916105f16cd3aa5dc0401e62fd44fee31b5247bc6a292d904
79	1	161	\\x5fd281225cf0e00440aaafe826435492b2aeaaf056be0f10c0a782aeb98da00693b9a50a0c4e68636b6dd8057b15cf9c31054e3deacc15c90ef3d681297e3f02
80	1	387	\\x7f8fd658e4258a322731080a904293f391114716fea8ec9c1717301724e7afa2d35df99534e0e00ace0611373410eaba1a40963b3749f469c54183299e2dbe01
81	1	28	\\x1ef888175ce54df70a33c67ce6f94faaa8d1fcf22e7abefe2abc9c81dc17f6ab7ea6d6201c7a40aae85fd0ff7e6acef7eb200290afbf81eb028bb24b6f8fe404
82	1	283	\\x4060596f3cbb4a2d3cbceb620e975b37ae03ea8ce5f3d7b4e3c933e9502f4767ab4abe20bc3a19ba847f30fc9c5421322a781b930a63eb5bceefdf7fc2384e0e
83	1	288	\\xeb8780b1d57cd86303db8ef431954ec7c36ee32d13813c300d3bf2965124c99096dc51743d2590d4f555cd4ea1b9221a73d52fccd9e5ac94ebf96f16240c700e
84	1	308	\\x1c9eab03ab01761143685e08d50f1bae610fc5dd5a9a34a6fb14b4e31b0a328a3dcd2d10f4ffdbec3ca2f9932c8c87ae0db2d1f8adce58e9d8815ba75e326108
85	1	317	\\x643a4c6a4cf8f5732251b1f4a4848d7b948f57d453302856738e0d375f5ab1ca9c4018e63f4625d759114581225e0bce63e609b33403ebdbcead2c80f887cb09
86	1	345	\\xa22038d0db05aa0148f35b9970d8fa6b4f84ba34021f8c21ae2a76ca095f140ab3de3858e85f2a02fbe904d72a40acd8caf8a609221579aae8f7c95ccd381105
87	1	359	\\x3768baa99a696860a732e12b2b11751ea1d0729600ae9cfdbafbc1d73bad27902f3907c753c4690a46a4d4c6979b47a7ecdb66218beb04f2aad4690d4514b90a
88	1	101	\\xb02bea281314a37fab55142c8525cd1dc48c8dc6555dd298ef3620f2ec0b96d432db905c8a03316a7f0f03df7693fa78b74e49bbb7e1e9d103caceed0eb60409
89	1	390	\\x72064e7f772c743fe9ddf40912cabfe14fd6ffc49c47d899c8f80702405447fbc808ac13581316c342492ad31c3e5af16f288d51d2faebd2c9a11c5dbf3b2309
90	1	2	\\x6c1e484b628aa6b988a146228e60e824ccb3f240b5a311c846368924a1f8b30a6d0db4aba9781c8f4f7d2ddf52cc943494472bf4fb6038cfcbb56a0118a0ff0c
91	1	1	\\x2f40cf862fed49ac7dcabd9d117a55cc5d749adec51cf27eb49738e801533593a8c8b6e7aa76134c1949a900db730065b39f957c7793e28f11c87a468a40de06
92	1	222	\\xdfc499b44904144c942818ad52a5d12d70d6a92192879c1aa0d884001b5c39e38cb43a3b026c480c56648e7c965ce9940351eb463e79cd75782a6fd7b92e2507
93	1	211	\\x4a5219beb499f156dd2590ad7adff27e0adc3ba9add5850a4a24468b57fc921532ea54b5ac74c344eb7135a0fbd3ff37b644a3ef6bd82c6c9f4b90b46fa45706
94	1	19	\\x0e804d1e76186a649d32c42c7c60b975c632489ead28a276fd90ca15b785d123c67cf456f78b0a817559490d5aaa5d8ad14c49b326cb2a344b10b0638503ce06
95	1	257	\\x24343877fa13abea9143f65ff1dbf42dd43255151ddd46dae6cba21c2364ba4906169fae96d31972883b33e3e5342ef8d9b290fe487196d39d0c00224a0c3b0d
96	1	155	\\xa3af41ce2ffe8236d49be56a47190686a560c5f3259fd56bfd679f2ea1c43070a4d820ff198a4658c4ff9b493447b96d21281e327bf7572eba6ef39ffe995e0b
97	1	131	\\x44797f1b787b7e23998ce6cfe0595a622df6effd0545ac39bd47740e986b50de02ccfc3729e19f4406ca660fa26c7f3d0d03c9cff4db0a39043c107d4ddc0a0e
98	1	136	\\x95e87561c022a87fc82cb48a2d0bec7102e4b9965506edf4cddedcec04ee1e173a3564ec3e90afdb2da8e202b658fbf9135ef2da1585157472334e16bd756904
99	1	103	\\xc42651ef5e18df07c1765293615e95b0e4865d2a13bf6b2f0527ca0345589001d977b08d55cd674fd566fefd27e9eb72d5953c6d688c9e43f45c6385c05aac0e
100	1	289	\\x8d489996740e4bf2e78d89384e4e232636ed23d1103f76843f585c22e65920738964f6d8dac1e9f9e5b8b0d6f287a73831a22587bccd519e1e25360ec3a1ea0f
101	1	296	\\x271d574284da0078754310cd4c9d23d030f55e59e41bb47d8b30a183e88f64619a7e78835dd76c1ba48e32c29c271fa6ad1d861f73fe7677b9a31f7d7def7208
102	1	105	\\x85a82168db0e3e9926508663031b50b0dd82068a105e4d8f4a14d8fdd5031bc6ccef2aa7593ba2754b2ba0ca90771dfbe3a9aa859274448b16a4561653ebdd00
103	1	276	\\x428e46af1df1939aa83cb5edac3e7be9a595d9adba92aad47e646f2fea488153324eb33d2e3a05cbb17e915d51ec2aaacc51caff5720cac4a9b1ca8d703a0109
104	1	64	\\x8c43de44a9286b845b14399770672c44d8d4f0248c2df89c79e4bbe827ce9b70a3960fa8709a0ad740b42a9a7a91e56c0735a26c8e2c65a2448a44e3903a1a0c
105	1	46	\\x527fd5d3d6ea0903d2a5df4c7a4bd07c0adb051b3f4da063f553cee75aa6a701bf01e118cd3b270f00734d1737fbf84a5b514e23716ac4c83e14ce99d1b02f0e
106	1	113	\\xd23a8413c9e1eed2dd4618c0fd6d399a5a0a7f7c0ccf110fc600e25a9a6976fdf1e7437c4994da9c306df6c43be7961025aabb379c7ca6e0ac6bf67786664608
107	1	135	\\x9aafa37ac7f93b98f95c9a1bef53946c79ecf8d3a3b19ff8c15251d152872d9bc3dd15099717eb5ab212525801ffdc680dfeb09e56ec702e4aa70f2f48132100
108	1	89	\\x5439f420f0b37a5f01e8f9e5528590343235c58630df74f7739615abca3d4a01a691855e70866ffb8e3477a1c9569b854f2f7e0058b7c4f2175f6eb717512707
109	1	166	\\x520a594d262ec37021a77a248f72c2d40677c742abaf4af9b9a517436764f726fbb8486b8a72db8520adfa1fc779167ab80e5103487c20ea79f717c53b51700d
110	1	309	\\xccfe33f46ad032f07dac333005177fca570252caaf5732fa9be8cfcdce630a0c2973fe94a37e4a88668820b4ce1429e623850fd8150e3702cfc63349d2f20e09
111	1	129	\\x25593036580fada162e6472791fb61709201ca3434c7387afffd2e52e220ed27f53fb689bddc521b1b185d4b25dbdcae8e6cf48d7dc7beae8d3985795ff1b608
112	1	107	\\x80e9d7ef1ba2fe62139751a71cb6b1f524dc2a6a57e18e6fc02de09ee205289a483dd567aa7f17831a33d4af79b44b78a5a790a53481ab73e6c4c66dd468a201
113	1	92	\\x1afd24e9328b35ad9c8097cce573227883982937d5b81d06a8bfd6b8f9b93ea65ed37f2c92b226c219897385c447d4807b571e41d44f447ea8f9090346c7f805
114	1	293	\\x0cbc513206a57f10a4b8b36808cee36f1b6477c8df31abb14c3255b41fd5438645eb5e325f8c6294850c08c301317431e4cc170d34488c49d70db159d575dd07
115	1	59	\\x21edf8876dbb0070f9b58589bb7ffb4ce964b9e2eacf75889dbcadcf29528397eccc34109647d73bd1852a85b681a89f4b816fe6f63894625ef2d495f7cf0d06
116	1	42	\\x1d0eaa6053d867103e202b3ba80a9136cfc2fceb8f317a2787b6d3712271beb3303fcb372929fab2b9453c87688d57784923446b7b5c45b62043ba1f0824ed0c
117	1	303	\\xa658479802be8fcd9d0ca7f5e0f24840f9b6e9e90c5e937af1a0cb707acc1147d732fa82f243a8a8eb9fdcd03ebdd1f2a7798caee24a449f81e9f5638a0da309
118	1	271	\\xa344792a849a45b67a73cc0e3b2b8694e1edd5fe1d823ca5dccea131b2056e0380b6a52c8d59727ef755e2c29acde5719de2629d865b2c1bd2f78c5cac12620b
119	1	20	\\xef38c5d066d9b828b8ac1953a303ba5958d9f3620a8565d46ae84cdfb03030d902c2aeac5474c847cbc903cea2f34fb7b39c5e76e836c94b0da2ec98ebcd1008
120	1	369	\\x5b89eb8a51b7f670f89fb00a07e26d8386bae6bca35e1db0871bb5062cda7cde8e5b222cd3874229d2e05bed2a6748b6ca870149e1181b86002b8048c09c4c0f
121	1	132	\\x621b397884398e962a2ade46250969f7f718587971d3ad37fb35f3bf7979715b5fb01c4fc174ad7cae5177eddb69d8b32ecc01fd1ccea7da7a227c5015360a02
122	1	119	\\x41f2297dc3b605e5fcef456298c62b8b248b7da6f5a1c72f68b509806008a85c314b14b8b90373356a79ffde310e6c61210b9dbf47db51d2f1cdc08b8ded5709
123	1	282	\\x81b08fecbb20e800de75ac1e7dc372d8c9f12d7b235dca4de45b351f3e21ef67b341bc8188798e5bba59cf937fe780ceb21b1fa41c5848a2d4077936a65c710d
124	1	63	\\x085671f7e1f7402c65be3ab384873b866262b53320dc661987c97a1579dfeb1caea451b86234ce0867bdbd8ec24d9ffaa75f6483c3b446baa4cada3c920a3f00
125	1	81	\\x93e9a41c682e0bbdcfea28f05d03ae2bc3999037599678d5eb8bd0e2eae020163e8ce318949edde0afa2f7ef835cba2ee1600c117ecfbd73bec17976c912f606
126	1	414	\\x7a727e467546420aca395c788eb720c3b422b475c40e60efaae1e05242dffc8774a9b7ba0a7a7e2e1e0f5547185008404647a9bcf591180851d409e1084f1808
127	1	192	\\x9bc48acae4d46ae792ee3e62f04b3b178c746a43aab29b53e48935aed196cb230aafad74d19a2f3816dd09c600bbd605705e9abe1acb59181f8e0e086861fb05
128	1	195	\\x3155b20450c21776b642cd6712f1883333aea3518d70f9ab9bbf0121293ecdf7223120cca6efb731ccac678424d8fbf11427a158a06012d1957882c11726aa09
129	1	238	\\x68bc3baf76709f39542459d89d8c9ef5101a0b06af652fefd353955f4b4d4525694bdf20d94183877c70de5fd46fc8666cdac47f4f0146d7170ba5f4baa28705
130	1	80	\\xcddd221abd813be052a97c92b90e93af2ebe70000d94ba828e3657123bcce88e84f810d9c64eee6933ce8226d5ea49ed8f4de303b486c7ddf5b42d74ddbd2803
131	1	310	\\x325588970567b0afdc7668ff8681d27e47f663e3d5c62a17ff1cd4863dba06da4c5b1441bb015cfbecee0d47d7de79cadc783bf3aae798f710c21af8573b520d
132	1	125	\\x492f9c640923c0fb8d1e18c26e9c57e6788d98d5bdbc6309da2b2b160cbbd4e9c564a2bcc99b6990decfcf3f774c5fc1517d32bc2474dbce42f6a71d60dc650c
133	1	44	\\x339b9f4cafb6f332ec07265226dad8a5c4125aa5ba0982f658f59d8bad21e00101d43bfb77a26d4296e46a234030cb5b2d6c8d76633affcc73e47e47be7c0b08
134	1	48	\\x191978e7413b529e4b81e64529d77520679b311c98f1a6132e407c1f4db11ce26f74eaac6949beab9b898ff8acfbdb5193a1c29322a2ce910fb358a0452a0404
135	1	367	\\xd5996d14efc2d4eb0cfa5d6afdc66210ce46c7f98bd3d0a01e409df5163404d2d482e61748ca534e6b83581507bb65440d1a739d6d64f42bc900709b9014e90e
136	1	410	\\xaebfd5839907d6149f7fbcb4fd7b912b971cde1467871255f5b64293bb113cc4fed2724579b9793e876f0c0eb95e9c5040b8ef19a3c1a0f8b21958be6bd81906
137	1	360	\\x144ccbbd2dff5805033a46f063185e79386435eca2f916a2a6534db35c1ea75577e82e3ac66a14d38ddb94599dbb304c96a65bf5024febc9d1c660a686c4e60e
138	1	363	\\xf9e0d67f0ae01b45012a8d11e739b4bcb4a46a059e023c9b981cb53000a897d22fca10cd94a6ab9c2d98bf67fe85e95f0cb51cde19492ef67c7f8a1689258806
139	1	395	\\x4546cfacba7d11d41a1f96c12a255508157482f6d98fb0841948d647cbb2cc14c110890317dd588b2edc1191cea2b736b031a51890dc5ddaeeca2c7df8f7420e
140	1	30	\\xd4173c06d6b1966925cbc25b0ce0c56cb10cc317e89c5ec799d1746fd3e1355894672aefa4ecf282d0dab0f94aa7e8435298f7b225653e0ea358e3539972810e
141	1	126	\\x9cdeae5b905fe8229b9891e128dcad6ed81afb4de16957d2be05a0e5d7f2beaab929bea9369799e556acdccb56382acac0c198e1fbb8d067395be64d47623109
142	1	275	\\x152c6c3d7fdbcc2cfd73acd5cb80373dcceef5f08a120e4170a192742deac4b92acdaab1c6ec18926592b2824c83ae5f32907c246014d55802e8fe626947400a
143	1	247	\\x4220df190ea191b8443c4e2bad57955301dc6f0c4624d0ce5b183a24710f05f9b50d7430873ead1088b9dbb46f1cecc1dfbd404d6989b2d5228321a863eb0204
144	1	176	\\x0da560b48d7e78809d915c5c2171227ad0bbfc643b4fc4ec6b08d3d194cb1752cf5a6615b7889459dd992726d12405a3d60be59e966da2a878dfc16f8e36610d
145	1	332	\\xebfdf06ddd0bac34a1e2737e2d02815b42381e57248d0f2d8e936b05ea565961f10e16dd8147b2a7c75bdb499173404e33ac8ce609fdec95aa5d3dae2a2d7f04
146	1	396	\\xd2a50a22765d7bd6fa13abd633d2dabf438988dd39b1f9a3f53f91be496ee42f99cf1d2ea989fe440d55ef2c70fda2afded8e031e0d89c5182772147b7025103
147	1	17	\\xc4a0a6f1d816ab4591aa23847253730cf3b02ce718badf22d7cbf603014d21a99f30e853444614bb5e9e1e9ed62f78b41de594398c448fa81d4d1322fcdda604
148	1	259	\\x8852205e7597a8e668f4a85238d6f978172faf5eeb8c14b526bab15a63fc0b5ed7418e7774e22c049160f926f84f468b6727cf07661af13fc6e50e3606134905
149	1	149	\\xc63a5d9fa4a410449698038454b7f8525c3a955e3272da45cf5016882775433b3f1a184f39b572bde2531dfd7835f9471011edaf8d2b849be2d02461a873790b
150	1	336	\\x9ea9deb1719070ed4edc3fb79e38527ae79a31ade7329521fd0122524148b550f806b2366fdfe829e21241b32bfbfc757152f4015dd58976cda46c78fa087208
151	1	108	\\x40048c178fd68b9ec4081c15b6fccd8d2add6312763c960ca11427224a3d8c9bf581040f3e5dd063222431f24cf04b4e2937c06dde190d7db501172fbdd59e03
152	1	225	\\xe13013693de0270e616f2326b3ff7f0b3153ee0fd69a84e1b3b774c02884540f23d651804182710abdcb630284329ad5c175be070403bffa227eb7078df3bc02
153	1	333	\\xf637475ed929b04fc77cfa411264ab0958bb62acd4dda12692400a3029fff3689125153839d5a8ee6a792a81ec7219bb3af31e00b18ab9275b7f76dcf8045207
154	1	200	\\xdecfef87d29459bfd0322d067a2a323d306656cab85dd100a2ddce92b73f0911e5c191f7c04b4c11b2986118955301ff31c4dfdba3134d471dc0dbdbf2f99f05
155	1	39	\\x3a7d50972e403c2100294a4e7de731cba62217e36852882d8d42f1bac6a75375e339481b2155adf3fe574c1171aab6233ac23bee038ff02a170ec16e02bbfd00
156	1	205	\\x3d69909619c0034be5196403c516fe2f575d9575c7882362c2bfd7865dcdd2adf21f83ba0d612bba46c69ec8b37fee58fc4c5ab6b8f794b951e8ba445829770a
157	1	322	\\x654b379a5d409bd7c1af70078a53c0924c0223108e1d15a8c19faf341a987d5bf991fb83f93570e5a123270f50f14f8ac4c9e0952af49874778a64562f82380e
158	1	100	\\x5823a4409e7ea7e34edf152a633de8d6e5d6f173031b1e53d14eab8f99e6e2b7451deb0d5be839e6d61f2a17de513998f6d14b6bd17165f165992d160e90870f
159	1	270	\\xb7d576b38b80127377bbb3971d3a6f4ec9c0fb5fb802ae3a6e8413fd1fda55c6f45f5c98a72cda88f821dbb964f71e1c583810533384db3fde6770a7f26f3207
160	1	246	\\xc54309606f0e6744ab324cca818894b66d3c23fc1c3efdd5d3ef4a5fc8d5614bf99f567c1448eb3047cfd59bb0ec483997a84a45cd60fea183314cc37a729c05
161	1	400	\\x1ec77290ced57389fdc531d7fb9af4cf5591e16f0ed7f6ff6e444cf9806896d67d91348bddb2b2bf5e4fa1ea3527798a4b4504abf3b8ac27ad72b1033191da04
162	1	153	\\x20f1996060dcdb039bb2da77dd5611ba32a004f149f4940636ecc10316ee5c6b432475ea4b607c11de3c213d492df1f24993833370fcbbe8f8e793e538f88b04
163	1	213	\\x4445205aece715895ec7c55daf5156e44e354aeb4e5bf35f4e3c668cdb76ba0d71fa043c83e65b8df98fa0d39512fc798ce1e41af9c9c246d02a2407409b2805
164	1	386	\\xf9d5d8dc3ed7326bfd3fb7e4bff21b16aaed4262d06c03d63c7ce73261c34f210b0d63d9f93954f8094fa50153bb96c8d777cfafdf108573995aefce28b23b07
165	1	208	\\x66ef9ecae4be4fbb2b6a67ce1221ba2f204f32e490c6c8e001a0d418440305940a709e95050b19a7c30cbcac804405e1032d003f53fcf1c51ae3d673c011770e
166	1	143	\\x212ea014567eb1cd9d7544621d2f50eaa745a5dc7a3ea47dcfbb4b2d6863198c4886754f67d290731e66c68c98f313ce87dbd039138e3774f5fd20888c364606
167	1	124	\\x57990f1f6bdc9f4b4248458eedf9d84deee9832e98e00427459883ff05d8de95cd5ad4bfee230b5b6f4b3de4d7475cd5c8641fcda82585e4d584a1cbff619f0e
168	1	311	\\xa8d918afc637b68225c919b1a9c3495e45be0073b94f3bc7a9d939194aa6b593faee826ac3cb3a5fc31b115863b899e7fe6e7024af3746062814f0364fea5501
169	1	183	\\x17ecb0d143a3d5b8029dce152088e11e15e65aea6a915592b1a0bbf74f04ebf4071ad306f9901a0b6752550199682a8601a6d1b17e5206236521ca358781a506
170	1	106	\\x329741e716291637752fce3ebc3eb98639ee4f4fe1225fa331086ff9e4ee11a30f4383db829558c54d20f9ec7b27eb171c6d6d2dbc252b6e87a2eb3f1634bd0f
171	1	140	\\x59897e55ac78acabf5f99a6b59229c431204fcba91e910e1caeccd2adfdcaa164e687751b588053bb93a854664356e7ad70b6e996114eb702b413fcb5a500600
172	1	214	\\x2678a9096866266934285975952e920af5645dd17e42214e75629a216ea59045ee7b1b605b93bc7087dd90a13b9516d1a9d19dc0c7bdc61a65522ac7a7842108
173	1	138	\\x41804b310e6d9d97bc99b0679f2c76931e76ff5be01b9284bc5428488c3a1ed88f962a8da2eeb892bb4352216c38e0b1ec75c76e145ad6a694824c2aa299220b
174	1	180	\\xa025c214a75121591db78105225aee9fe6f2ca9190e85c2727abdd387250c04666f85deaa7df5ed17818a59b2cc86e4647424a58f5d346170b221062afa54b0f
175	1	373	\\xae7c3a52722da88d9a35e33935d3613f37640c3993c9b0153478df5aa671fb0011e485e028e9461d11ce305caf6c5a3823d8c47f09059e1866a9b44d4b398806
176	1	139	\\x818eccd0e74ec8e57a879cd9097512ca7bc93156237cd50f13aaea1d01787b9cafc132e032f4595cbec6d30792075475e046bbbd85b52bc5b3d8102cd78f270b
177	1	110	\\x0170c7f8f84bc6b1294fa8eb0d24d97c5de395bb2bbd7683a0765f385316103d1b5a309901565f9d58e7805936c876a1fd76325ec827cb329fefc712f8dc5205
178	1	102	\\x686870875f263361b2db3c26ae84888d0d35bfd79431f17a07beb51700e786cba76479113b8374fe045f5eaf4fde25bd1bb60ac500dcbb960773875f85636504
179	1	374	\\xe1188b4c042a6aabff9325d82b16b8b31ce090f1a57f77245ad76dc25b66774bcab3f7babcc1b91e7919d48ba302c272d79595469bd37790a0f01a7a34674002
180	1	212	\\x61d07ce5127d1fa1b423f2cd77c942f0dd1267efb87b205c961646c5d2e652ac1ee059183ea88002013002719a90faed487e60f85015b14ce1142eb7f5895a05
181	1	61	\\x656cdad6c820ccaf05f6321e2d1a484317478294961f3371448ff22eab75623e7e7b97e3e439106b5c3fc9ae95cdce1fa169841d334bdee528698505e1c74002
182	1	281	\\x742766933a5fff18094bf834f5a9206bf7d7f80e7545771b5ca613d81fcb9d38d1a68541bd17381b8bf2ca2eb021f045b39893ef00b9ae8c123cb4d087947e0e
183	1	37	\\xfb5c026f8d6c457686258c68d2a384e1053b4138dd54b65de10321d7b667eb99d249d0c300bbfd9d9bf6df20bf13ba098cfbc8fc42c650998668ccc73a5de00b
184	1	302	\\xa7e0633d78308575c28418d232d4295a04ca78c7a6128f63a49d17c2ece39f2d9317a73fb9dae24ea8057218fd4ed64ddb23956814214930aeb3f436b83dfc01
185	1	170	\\x287ba99205efa07a33e7e6ca334c7cf415dd03a95c0845fc922701dda6db3d46f18301a85e874dd76eedc3d95d6c9e5ed9218528e246f5b8500ec5ef6c45b507
186	1	423	\\x54b18c7d4556c8d83ecb294a6fa9b0fb3e2d2dd1a9701415e799cab168f500ceababcc758b02e26cf3331c0a880732b9bf5029bdfd5b819648112f3ce3011205
187	1	398	\\xd98f408ceca3b59ccc835f9a02d6e48d3aa6211ed0f43ba256a5d9f249b111c0ce7cbb04b32fdf0c7cacaaf8cba93d16c2c77d7fb67349ef91f7138b03d4c50b
188	1	158	\\x5bb0ed8006ce3151d67b00815688e529dc4b0215acc4b1c0a5cbc3ba61c73b01b2e7930e1ac9d111259321c6293c7f67e2553c006e6947aa033faeb669245405
189	1	249	\\x2ee9961f2f5aa86010e99f385877a737840d5dd99894cfce596ff801d360d1315e0bf7cf4826a9d853dde973a72ba9c81c6623e6b3c1419a6e59c97d3953b503
190	1	375	\\x2e4ce05db04b30432248fd2e38231cf8bee89c8844ea9030138a496c2d70cd5bde4165e3aad403e16c5ab5b9fc572fc2916b2fc93c48dc5b61491ee0d1ca7f0b
191	1	52	\\xac362a15948508490aa3bbb00d9373dbf43933da588472957706483307a131b47f4f4cdc891b1c04bee81ef4df6560d4848e417e12ba647c5a2e8281fda6490c
192	1	292	\\xe2c7fbd0c528cab2a53eb039680d29b710cdddd598293fcc4bc74100e351da45415dc3ffd334dc7a517652838a3eafc50ac955d09b34996afc146d4e6450bf0a
193	1	198	\\x6632a71691c92ec25579af7a803994273c3e7afa1826860da57d59fa0c9586a7622253fa694cd812e640ab403c4a441277d8d5932430fbaa9465ab1e09f20604
194	1	207	\\x0f0ce7ae80663392f16ca9c136c793f5199fd7ebcdaee8039bb85476e0410e4032ea05f29a56981a745a8a0106b9c6d241beca368ddeacdcc8401eecd0d2fc0d
195	1	294	\\x45123aa83e99c8fd77188be20a5accc5bcff3c888ce17e75f0da4488b89c68a1275ff21762ce3827e9c17557cb46ea10bc9babda8ebbd91509a294e6acb5b40d
196	1	256	\\xe05d255a291cbe1d0eac6f3d397612bad7db98474de51ce26c26742d44b5e276970f9b2a6f3e0cf509e365f6e70e857a818eb74220a854b0420f84ec8ffd760a
197	1	163	\\xf9de65f69f8957cd9c74a6e3c070588ddb85adf902584954ae6f31a523bf493221422e64b16055961abbb32c74edc975b95a94c5feaba37b24afd5610ca2950f
198	1	376	\\xc5ff88dcc439cc610a96ed5e2ad6f930050774f558a0adc4cc3bf517fed5952c02ce132bb7a7d57d490f18047cc72a5fe3ea6f7039e9e1ca5630eab8a45caa07
199	1	117	\\xbcf26fdfd56a1906f1adc5662edf1a5c5044e25ff1d8a4432667efd48c9e86d35e3dc37a82e0b4c730f8643ab54064762d54e3b50407e8de7dced0ebd1b6cf09
200	1	150	\\xf4fe58ffb75b2328dbfae68fdbfebd322ebe159c3686e296c3f9c36b61d21d11e66240fa54f6b109983a8eedacde2879a4e45753998fdc0bc6d391e1cd288f0b
201	1	137	\\xe8277cc5f113ae47e15e00e3cd14314c0c55c878618d3aded8b5d568e305a0c05ced0f1b5f33025b43d65fbd1c5b3dee34a0f89604dfe3cfffe064c8ace11506
202	1	285	\\x6c884ccce13280db3fb5d3ef5a91e3c5f9df3ec27b1a014a223bb759be78fead6915ac12d557afdead39d229b6227518afacf0787f4015a5e3a41077da3e2f0a
203	1	383	\\x5c4f60601d83f8fc5d489a5e2f7dfcc56010593f7f1759d9b209e3811127afb0469fb1da9d9d1c18bb3e7a488969b8b613297977059bd0a52600e8b8f4e66502
204	1	381	\\x6c7549a2438ae6f01046fea4886c7a9fabc0e8d0afeedcf344dd6f8dad10f3fec45cc9f6ff7691ef50ed9a1f559d79130cbec38bf8040f26cadae7b3e9dc7b0b
205	1	407	\\x19d894bbd172823901fcb34f94b361fbf726b6a3fbc468746f1a5de98cef7e77580fb80d5e2a6d6d42a4bd3fd7905975e667c210ea8299be76d9d6df9184b408
206	1	305	\\x583344196477b02799119f9d527640b7354c641df0f5538b4c2bea750f800515be805c5140f8658b8ae1fd007e381ad541d7d66ad7244afad921305a8a0bdf04
207	1	74	\\x13e2c1dead06dd485751176127272b0660842767a67b55658aec55ce6a6e012feab8a3f52ed10d56167d1690bde046e0240b1163d762e404f1ecaabc2fc6f101
208	1	365	\\xc6bd40dd47aea1125d34139e3584ac178e530138af3e511ef1e9c0d8700018fa80721efccdfd5e865cba339945ffd72c0c114a88c7b3d929ff1aac046607430f
209	1	323	\\x41981b5ba651d7ba61cd4361617c471296c875224bc27dd1dc2374b2e945df6f3eb21bb538d53cd036eea0a71c062df79a55ae442a66d8fcee446208f6eb460a
210	1	337	\\x06b44c1f48329091cf0c3e6f6cfa133a733085c43dbdde6a1bd9c9926032b5d3f11c90fabb193857cf7ff0fb69e18170bc9bf48c995ff1a76ebc3f34fdd91200
211	1	179	\\xbc2ed7fd3b4796d818bfb274f9b9e4290afb8a34a4f70861b7f2963fa8e1c315138c80d0814026d3d998c0d9111e32eae1b98e78ca13b561f76ff782fc31d503
212	1	98	\\xa026bd161890dace3556a5319afcadd8337fa9f0d4bbd73a1aec4cef8169d50fab6ff93fe072251df1f0b3452a188cdb363af7ae9bae9437b48872b9613ef40d
213	1	116	\\x1ae33e1ec5814f1a66b252252f0e00d218cc86ee9db5071f7f29593b914bd038afea34ba02b5601d7470bf369f7ab4b4e36434d83abd0481937e4107eaf80d08
214	1	382	\\xbd3b0a79634d2dfc64542e1b1b5d0bda883e206a4c206eff91ba365188ce26d4214c92e202ee633921028f76cd596f3d98122150ec8d784f4600cc90d8ba5c0d
215	1	355	\\x220e25a3f07f70ea5f1200511b30d29b60be2c467f49ab0df2baecac4860cb1bf22d9a8fc912fb8327c0abe7d3096a7b8c161faf67ecba21cd6f137029bf5e0e
216	1	164	\\x8f4bc7650a3f9bcbfcd33861f9bce0ff937fe4979ebdee90fd7b38e396208ed682b29b031f8c2418c7674517a299d1595a0f1cf413d400ca801143ffce7e8f08
217	1	299	\\x50da37e55939cf2cc9d040784b8f52ec2724d293cfb64f7f80ba8d5bbe12a3e0663812778b81ceec796397390e5438b7462fa2bed395d049790e629ecc5c9606
218	1	402	\\x2c67c7f28d4b5ce291dc0bc48db4e3be941b0d6980c07ce588f4aa8024c876c1f498db19133e7eade281b62c07354df716dcbc81c74cf581dbedd472ac9ae108
219	1	343	\\xb24bda960f49bb7a3c6c6a601f1c34c1014547a3e7565d7857cc077d66dce3d99c54fc89d1b7c365640b6d71089846b7521e090c889e701714cadac0d4bb940e
220	1	215	\\x2d0dd16b874272187a7b4d7c67dab9f97533b5ae942e19c97bf3d45fbe32ff9034bf3ae22ededfcc8cda31a54f305d661696c73a658042ef28213a5926eeab0c
221	1	241	\\x3597feac4f2db02d0e4a470c4b7ff0a4de026b17e6f50da6c4dda4f59d53feadf272db2ff4c741a4172eceb49e69cd1aa3ee28e0a0d38096c4d1d55092b6580e
222	1	301	\\xef90d97716c648bc615a92b6f0acd97a4273a745746935e85b8c2355785fad463cccc877eccb0ca336060bf7a90e842dda7456dbb4832a279a07424e48674d0c
223	1	118	\\xf1953fb98f9e70dedd4114e2a2a4b36cabc62e178a2b88ed03d75fed4b8d3f6493e0bb257b598050c1f821af1a62cd864d80d2510dba285bb23329b1c4e80f08
224	1	412	\\x251e030b9c1c1ba21996dac7c48426c2cfdb5f6143f210f7bc7eadc1108a78887e6bf327f2b5713b29778c611e8ea9e1d8920eb2f182f4fade0f85dc9d29f802
225	1	404	\\xdef336dcb4fa8699ad00b2c0457faba323ed09cd0765eaf034c892efb6d90e2e828804763c28e7178382d2bb2cc5a5b07a4c918e314aa6d4b9baa7e08ffe2309
226	1	144	\\x6cceda0605a8db700ce4d50d1a26dc3f1db30b7f85af249e5d5169e9bff373df4915b66a60bac633104d7227e8de32b60fe43edf6df59429d90a3d1920de9204
227	1	134	\\x4ac6a7f5c2b384be6e6fb814211cb652a653fcbc54e7781ebaa55ff424a615d6a40b4571449974b6e1f42ba086f7d755300da4b2467fe8341247014ba4f2540f
228	1	406	\\x083658431f90ec4374711d42d8a0b4466e237a27aa9e04682a38f369481514bb6ef40276ecab879d81bdf9ba3ef584a09dcd004e2c90013d1d57b1f2e7a6e806
229	1	8	\\xb2ae761067a328266b4d07bf97031311d83fc7e8419de0fe389ab4456636b19496cd574945cfc93aa8d0f3d8dc560a842292b93ddcafb67e9264b2702fbb3c0e
230	1	304	\\x142e96e5555083d4dd0d301918382a77526f757d62a5f5a66fa2faa3c520e16877f36e9238bc815fde869fa56abc27a261e818d94f7a0cc7a70c1107649c8a0e
231	1	242	\\x0c76ad1d5b22ffec5b497c2d52a9d59d02de510eb5092fc4d4dec573c14fd423de969a779a8563ad7ebf282bcef846021db551f3192465525e2cbae4c4738500
232	1	397	\\xe65e52a15d88ec2d8278ce0978e7b6f63aa347d2cca2823ce737d7b4ae49030cf5f23786a0c9690a0dd24f56e6a5c4b667921e89f396c0f0c46b82489790440c
233	1	263	\\xbe73e3a541eb1060978cd9306f3d59e62fd664b45d89ec16acd99e85f0b198e136a43fcf05a65005e77a5a4ff1383682f874a94176ae24e281d44d084a984708
234	1	357	\\x07dbb350b1ab249a81d29add38edc63741f5106c853e055aeb3940586bccafeae06884c52238c1ccf5828481eac6aceaac4ab20cf1cba49a90b274641e5a2f01
235	1	66	\\x8fcc3f51e3162973d9d5a4dbb574a2f952897d9f32695b3e9cbcea66fb47c3173d0dc210846f0ccf9be44801191f4b0f0011704ba5457f7220dd196c21cdcd0f
236	1	56	\\xf2be19a5770e7e6b39331981b70727e7a415e3f72de1e816b6bfc38464501dfd431029a5a4a34412e70f7069d818af01b7951fedf1a65b2268dac28484769e0a
237	1	338	\\xf9c670afb19a43363b1b0ce4ef90f08f5bfa214c810de92cb97cf53ef4c89141712b791727354448b5bedf533050b7cb7ab0f888e9ae70237b8f37b3c9ae990f
238	1	14	\\xe192eb07cddea2d95d1884401df9a6532ca8d9ee1a94ee99096a3fc6de3c62a34326d508b9155872e11597f4fceff90bcc4ff48efffb97a2bd809ac701a5af01
239	1	286	\\x135542c739f669bd38d12152aa1ba1bec26cf2f6293476b11aba1920952a16c139b5ab55b4443ff135da9ee5d8899c5da55c4d608fc0aa78db94067c8ce8a50b
240	1	91	\\xbb17ba7cf9cf409476faaf4c058a1deea6da472b47915931b4e5113c8e56537f75f9bf741cae6919e4570332f71167044238a2e5655a7c4747bdccd40126e50e
241	1	94	\\x3218cd7827f0e1a19cf3ae822c8e6d87986da6d43ea4c21e882d26f1000812758cd0d872f6b5650b95a651caa36bc57fd3e53d2bf8f815984121a9e133084f07
242	1	274	\\x29a6d9107709d8657c81298e53a2e2e75a0d1972c1ce335dc3e87ce733685f95df59718b7656b64da201f9d4810d45db4ffb2b046bbc9c4047e15ceda968880b
243	1	218	\\xbe1f2e28d44437841360d765135ffd800bae7b4d06966aa7d08173f3bf1ebc5635694f3e66e0928c029771e780fefbdc8594353f5502cb6ba7e5697ffd5e5f04
244	1	47	\\xd68af42897500e82002ae67c5a2c950b213b58f24448669fde8dcf8a8de783d2dc0553271408820fc8da5878927b7525c7890bec96a0bbb3fd46bbd806b2be00
245	1	417	\\x64dce0a165ea61a016c539ef8d777affcb992a440462be338fc640a93fa535deca175c59570d301c57648f0e22ad9ad5aa456459dc5d5ca140c8511d0a9a780f
246	1	233	\\x239c1477bca84d875e8ee0fffea0e30c7ead9aa74e1777d5cbda84d3a2251afc2f427a4ad8bd5c9a53c247309194eb066657b5c6b5830e9cfc81030ba9722502
247	1	11	\\x00cb2936da04b7f94ee240f21543a7e7cdc28e7f1d741a9590a48232d0e9115242fde45703545a7944870a39a889702382c683ba229a192cf702ae1c41950a07
248	1	230	\\xd4789f56a4e32dc37938dd0e68f42e5c017535c1a1deb681e9e79d288af9b68d2c7820d5e7d03821bb7b99529dc7ea9a4806b2535c4ea495257d9487ed45cf05
249	1	15	\\x815b75509dd33f5054035527f76b4bb0f4f41990d68e946e1957b228e5346da2818583e8d3425912cdd59a8f79430a427b134a41bfde20bb0cbf2e75df2fc301
250	1	217	\\xb75916ee9077c97fc23d8646e80fe0c8407cab8a5524abed87490e9736442ea8ac5ae50e1177acb2e0aaea2c5e4f58ac1b7169e7d7c21c7890d441a39e8b9007
251	1	87	\\x51b659b371670dfd8124d33fda8ddfef1c7be71e6565598cfea11db3596e111f076c1faa1036f13af365a200c4c7c368c5f8986e0b71e10734c780db88f14907
252	1	169	\\x62b7a3c3c17c4f353f88be1a033faa9881b4d9a4799f41bda68b2d0b34c591bac7d5a193cd88b09794a7f4518e829213db3dbb7fd3668b77673fa9405f7a8802
253	1	148	\\xa9d9b94e972a8da4339c68299651e91e8feecec163f73fa4d8da93bcfc7c245ee0f96147082e0b162c5137c71fd95d77b3d3158a7e8514e96136f7af30854a0d
254	1	90	\\x2ad00b438f4f060e21cde38d46452cd7172940b3e822cc9981c1fe6b1674b19342533e5f82f4f9f6ad1b55fd5a60c0708c45406edcdc781ae8909885aa0dd304
255	1	196	\\xa674d0660629bc0f743bd4a60fab5b98f16154f5cead885a91bac9ff9a3d676040d16a9d75e022f0924b4bd65aea85de6de532c97fb98df5540894bc36ee560d
256	1	261	\\x8d8786080371a2b4470c58c4e28bd24bb7fcaf97b723fcc014079785314cb9c46656f0b30a63488e3739fb3329921a6684baa83b3f9706bdfbb2b79386e6f209
257	1	9	\\x252d9cfd3612eee8224a5f250d05c3f142c52dcafce6d88b8807cea679a75f7c3ba4975961ddbf62c2ce01b907eb5b2f2731e177b09f2a2a8181f13af676b90d
258	1	243	\\xfb5b8038ed56eae2cfca52d10259750ae8b23fb95b0faa63adad17c8326f93630a1b54303a363ff26ca30e5970bec17777e6a420ba3a01a6239562776b8fb506
259	1	172	\\xb1d34e32bb172f96b2e0ed5804250dbaa36cc644eddd795936660e56a752ee43c78058fc3c3a73eb34234829d2e862fc148aab6f4992c4523e5ec76ea4197209
260	1	265	\\x8001cbaac48fdacab12b2f81d97cd124ad5ec9224f913dda91f1cd61357591e6ff92900cd59577103c7903072c0e09d7f012116f039a8b9a785b896d30c3c702
261	1	127	\\x4c6d8663014cf5d4b5382b6b83830e9e69713936f4e7ca980a0a8f66713cfeac22dd5e66b63bd4cd4c90631788366f223c915ba05e565e14aae511350b7c2b07
262	1	224	\\x95767f807f322ea02659eebcfac576f0654685c641b4785d350108eb6388d521386094ea1e32d755753456ab5865ac137af580bac87a9e5e5e6a568ec498e606
263	1	18	\\x4d001facba407347ef05151483dda9c0cd442e4844838acc0044d252f2073c93905961e2fdda96bcd137f0c4ebb3e578a757a481fdb4abd562a30467f5ec3000
264	1	206	\\x8526537014dcaed885ed49e35e7b22e59453f59c7c8d7f8eea321b63b1ac55840b54c9cf3441b3fa9a68f94f9f571e5d82057a38ac150d18837291fcdb157d0a
265	1	32	\\xb27d4ed4c2f55c442afa750c82e4283442abc2d2c077fe94362ab6d8e5498d5477d3a8b0e483aa3f577416221f228756fd2a0287deff84f69b1e78c762681804
266	1	34	\\xb03cc8612dd629bf724f514a2a6cf1529267316923eb581528b4b2ace2768e6697e9ee54a62f9dc3fcd86d13a70ab8d578870daedb2e84641bffaf1ac0fc8803
267	1	312	\\xe1e05f8afc4160ec51c226e80606a8052b2fc4e12fb329bf6de6ef173b2b7f3694ad4b9a6e4fc7b9991ada15d2c3bc7205c9201f8f6b40261c0f3e303c1e110a
268	1	260	\\xe486c3b4eb562552371a0e3753567a84d748fa758c5e6e3bc73fb818e633e3543af9ed62fe006c77fc082a25ead4c6683d3e9b335e1875a62545d0f278adb601
269	1	415	\\xb4de5776929e0f39b81cbdbc41faae8a40d02c82324f99481d181ca1169e9eea81ceb01a03b3018a3e0789817be2ca4809c6ac44867e6fecde9ed2caeb4cd20f
270	1	362	\\xc7b2d2587c4389e19c6d9bb0d15a3b00a27dd0d0c6512cf45e681292783f0a22fe28455ce1ff836853592a17cf211c2e713a158ffba8b91462e960bc0173320f
271	1	111	\\x5658559898bf17d2f57d602c2e6fc47a9112fd3cfcf88f3abc4e65458871b218ccef665ea9743376137a8c3c2ec68fe6b2e310734e47609d7e4b8b578170a00e
272	1	152	\\xaaba09fcda06cfc017e99c25dfd2b7bb03c402d3a09bd9c6a45b85a497f100a93f41b9820d012d2ceb363fade3af98560791b0e4c924d2115a5d629b67955503
273	1	354	\\x34b2ceac1f1a1f9b1be35621e7c1b8cbbe89058ca1f2e9ecbe2cab912302b7916c62408c5e1d66039a70bed617314ffebc47cd5df03f7d3795faab759b25fc08
274	1	314	\\x9684526b29bffa86a51b607f2d10d48746935b9af4eca16b50b9a89346ac134dd6b99152dcfbed45eb04b3dc8a2f7a4157c3d2dafc0c5baff4446b953e26bc0b
275	1	348	\\x9b37adac2e32c541d145f846f0d3d29d8d0d0a4560b48dde35b703b521b7379211336d5993d6925e53c41b0ab4b7335daee5b640fa1ee5f9c2c30315809faf09
276	1	5	\\x716d7418fb8491d008315f0f58e84c5d28f4e3a60606bd4e148646c58919ebdbfdb8a32800e6cf5c5be79a113c3abf0d88f76a51e5217b34afd9340af84fe30b
277	1	366	\\x1c1a95decab3d058f3e1ac84de2deb7718d96b8543186a941ccef4871947b7682136d7439b0f431d81bb247a1717915bbbdeeb6c1a4b79f95e22abf917e8a309
278	1	185	\\x8c90084795c5b04e2e39f225f982c35707b58cafb3ab5e3a61429a886957f376deaa318bdaf8aeaee3a3c243da565b1667aa63db08ecd71738b8be2357802404
279	1	351	\\x1082780d998e6bf3f65d7e6319faa6a33c9bee9e2d7f1c16d3cb42017f32e304942c7a4c6613468308dbbc1f938ab3135fa9309cb1d644471cbba056f1a81c00
280	1	268	\\x16677376387165cb95c6f64872aa1ef03634ba86866f13c1235273a5e7454fc0ae35d14ea327565ece6482302c0d10942d96f3ce86e025af67b0d6142d40600b
281	1	38	\\x69600c01cf7eca2e1d05f1317b653a61c3981b3cbe73e15a51d2bf6b2a245b19cf70bc5f2f5951bd2e53cb9da07b30bdfaa614c861c5f747251b4b38a13b720f
282	1	22	\\xb27a0e825c5203df456bf9c85a77e27316d558a3129df840fce3851524a4cb24f5844c75c37d52b64600a36d8568c5ac4a02630c85b5cc936d7df4da3cbb0c03
283	1	72	\\x75903fd7d7fc0034d579e1cc43b6c98aef39a17a874792770469ec57cbfc70968436a817ff5fa9a350f0917281486e158708edf0bbfa6e6546b8ab6eff10a10f
284	1	173	\\xb49e18f83a9d9babfc683b4c4f11be877a5d54452bd8d7a8f8710646a422bcd8490da942aee530acf0667ef46a3cda5fe36dce9abd29c65998f073832b105d0d
285	1	186	\\xafff9f847333998afba4adb46dc13538fe4ddd387636986a8c38034593be1019d777e34f31b1283548ffdc4fb349078ded2a4a00f88003c1325fd13214b42c0b
286	1	330	\\x33756c9114944bc7fca8300273a94a1c0341378c9e08e3ceadb9ad43f1dc6d089fa3d022a53f7c1644b6c903cb95069c804417eba41608d847599bf5017b1e0b
287	1	95	\\x5d211bf6c7b2ca11f83b48dd787e391298eb873987d4974ff32229745d9bb891bb54085cf8fe41856147124f0bf0d015429bc8bb2826d3d8d2bb1f5b9f1a4e05
288	1	67	\\x4f3c3620ef7b853eb0e9a9bfcafb65fbf2d578a1d3da0fc36e2b0c77a6d2074e3513eb28a0a2a9cee87666c36262314e27502adc84474e1380b19e06cd5db108
289	1	57	\\x1303c0941c7d905ce2328638627eadf3e13408f1ca7b765fee25fe7c8512cb29a132f51cbf7a1f52fb41a6fdcd12b6fbc97ed307d348e372eb4f854cee768306
290	1	358	\\x5c127bafe48c49fb77958781cd7719921a273f0da3d2209a7277dc0962e179c4b3d22420464037c7d977a994cadbf0f631e9e543d89eaceac4014f5283539b0b
291	1	306	\\x18fba33635379312bf2c7b7c833c37792683644f651aacbb4a6e4912701400d9be3a2dc44894d206369c604cad27418f55c31ed0d8d41e5127143a2beafc5600
292	1	165	\\xefea07899144b46d6f69b0ad0d2b8097f29f2f8a9ffa759c15c8b66fa8835936323ad74ada4cc6bb993913e048ac5c5c678d770802f7e6058804466c82641608
293	1	295	\\x17a83e65a454f5634645297538a867062b4c0533202f10478d50e60395cc8b5a6bc3684b138cbda586907cfc2b2ee7d78e9bd12f989500127547476cadfd6803
294	1	77	\\xd0e49d176db6ab3b762ac367f76f89163d34335e010e672c3c8513c354cf760dfcd8557d2a4afcaf70f65bf6da6bf9644b69725d48fb4ab3108919f3bb69bf09
295	1	379	\\xb5d500b50ca6d62b07d5615caef60ea0c73a2739b616ac953de089a2f0354321ba3ccf8f278d54ea610b3919d594010c20e94121770a14bee9a9a567ab58790d
296	1	191	\\x53fb90b1d90eb8fcbcd874e108665399902c3e672f5bf74b64d0f8891d6911d931c897d6c9b29e5b60f5a7cdf318f3041fe5da9cfc68a99ad14e631b880d510b
297	1	418	\\xc44c514018db48fd578663c9292456d40c00340c3c62d79534172b579e76e896f7a2c26c2c595afdc6708a6e6698e6f950d5439273c64e15e11de3ba8f756d04
298	1	378	\\x06c04862688f83e547324849667625d378291a87ffe036f4d1fd27eeeb5cbc4837b53cfa07b4ebc1046b2a103274ef8203f75e292ac05556590b7a34ea3bcf0b
299	1	62	\\xeb5fe2f02101af74aac3dafa375687bfcbd787d4ab3f05ead326b1b42101536e037f4dfc66857bf3bb691300affded88df75a18a42181660a7c517b72afcd10a
300	1	189	\\x73577ad2330ce275bc851756543dea9312893f9a05ca15e0ec7f921ecc80ec72487a08cad433f1213088296160cb5b2c2d7f6758efc14557a9c221b739e9df06
301	1	391	\\x1de5c55796db9cb2020c27a48ec7e53fe30d2d5bc94d75dc71abae04f00c9ea77e0d76a550e2d523d460141b5fe3517036178fce6216d7882069479da5fa9d07
302	1	16	\\x58893025ba8ed220275abe7e1842a9b5be5d76f42102bff7e487c3f6dedb597aebe4345b386bcb8a054879e225579a569ef4ac9c7cf54b24d91058f9b0c9170c
303	1	266	\\x46304d5c0174f685ce3e05234cd1c68e1144527dba23de578fd44e8529b2c67bbbd1d5b0fcb40cee11b5f094517dc30d051e612fae360212cc7b376754ae4807
304	1	394	\\xa6eda72eca4620f7f2e3fea6d89b23e3d9b8fd34fe59909d06736aa1c4cb0af304ae5d2553b952e2ce237c2ecb3c87226852f85645b46fcdc72357542965370d
305	1	231	\\x39ead56256e3d0eb177a59a3c06effe30c11d3052effa4eee7d9d0a23f1ef3f6829b7198768fa135c4d03b652703df9bd5ef8e2f373b04eb3821197e3a80ff08
306	1	151	\\x26b4f71f2135c3ceebd62f97e69d8404b84824d82fae7b5222d73f98c19d54ff11d674b5e560f6d5069ea037f0d94f4b09cf90d0329329ca824d15289fad580b
307	1	204	\\x8799cbe1a33bda2be034a30734156fe11de14827e7f8a82f93b89dcfdc0250ed1e0425b28a9b933905280b09899a5821b724d3e95c850948aed743d1bf4d4a07
308	1	201	\\x5437d3248b0bb177d2962d017059ed9fcd408cf178b4839fdfe05f08eb8e54ea0b5c86e8265ae6dcaedccdb92b835bc91ea1de9166f11d3d4a4f59c632e50904
309	1	197	\\x398e50db69607abd37afd52cb9aceea6f8b865a1668eaee57110c3bf1d5e7cb4e395bb93e64da6fc7f882955d7f3d0dfef1b6f6378c5a1cdb449e09c1a1f730c
310	1	388	\\xa3407ce05e4b885bb27d5e4ac619d4ee0735cfdde5489a5fe46a9c03ec35995745d701775becf6318d1d1e12ba3e7d35537215e605d8240becd874cf85565a09
311	1	221	\\xe40b7f44a279a5b1fe59859b87e06e2d1d8cae36c9593160752d2413ced3b33cfc7adab3198e39d20b2f80485449e58481a9e69fe11e960dc6fc8872bca4ca09
312	1	290	\\xba9e30d48fdb1d7b60f952de4881e928db00be360f21dc1a172df38b23a37261c3d78e219cf74ae62fc92cccc935b1cad63f32147b883af4ef3e6c7200e5340e
313	1	182	\\xc0830788d55f9470e4cbca9a24b015867482dc86e33f2c53670d2fed0e8de4c6b17ff916b7859a853f0e4cfd3d130c22570373e77ab03898277ada36e0944809
314	1	43	\\x81890a41db2a282a1f5d9649912603658cf71f0f8ed376a68d9df3e53b7144760af00077cbd883963dd2e8d509a6c4c61f527c4dac33f74fc47956154cd5b709
315	1	147	\\x62bfff6cf984156499833c397cf32b3a32e86b81575a0c20f30b7cd811cd1f7e880059be19f1f367fdecff9086b86a62defb9113a18f218d4cebf1b087010901
316	1	203	\\xc88de98d30693835052e48d24f48d873d7e80cb9a5814288b1a1e240bfbcd2521d2ae455ec4ad32cb61c1ae24db3dc62fbcf5ed5e57d8e9259ff53e64b421b0e
317	1	29	\\xbbdba22e34fc713c10a2e6c53420a7a0067676bee4b4a80be6ee333a6b0fefee64eeda498066ccf85c0cf8180289952dbd6e9e2aeb86f4fc1fa556c1dcbdcf03
318	1	377	\\x007040d23ff801abaeb812c4d0efdc3eefcde0cf2c590f1a177d1078a5b49124b3599e79e3e22388213190b04fc3a6a4b4b9af69e2904417cfdd7692ea0b0609
319	1	93	\\x5424f708085705d9bb68c9dc32574eac0b1b54887201fbdedad77c5f126390dca327961f9644ba015fb7da7799b697ac26455a71c9cfb5a061e30983da14e90e
320	1	421	\\x418f353d28636f409ffcf446a332f12b4da8e79c0469137763ea89b5b053905ca159f70427334f0f2d7d5aebe5d622c2db7e1e47ce0998b733c6f91303d58f0d
321	1	141	\\xa55b727a7096cfa681b90e880acae5750e8136dd34e1e7cdc73dc9ff11bc3dc70bccf8af7f22c4d60ab1cc2ffdfc53b1c33914e7d05159be83c3eba88a988e0d
322	1	385	\\xd7d52fa4e336fee988908a9fd40aed5cb9d991fc37c17d589eaa70c25499a24070f713dd280d6f11f0a502a1cec8c94bdcf3d03b097212dba97f57c5da708c0b
323	1	315	\\xef45721a58391ff83fd574478ed79b05e6e543fd68324ae9a347fae9229cfeed13dc974362bbc34c9ab681e91f3b08f718164ab270f0e58b7c5d2096b60d9100
324	1	10	\\xccba775f41abfe74a96e1e8b72d457eb662fb0d5ccbc7eef7925937a08f6781467f7b7f393be893f357f03f135fb8c41459a0000c60433ba51a83485187b8803
325	1	287	\\xecd2135277669f05d6b8c309554616b22bbf37e98a23f5be655b40a92344359ada0a7a29738a782d6836806edc700a5ccf4febf6d4586ae6bbd23f3147c3df0a
326	1	255	\\x8617f2ca41501b964d85fba8987389cf869627d128b390849ddd3b5ca8df854fb969411cf0bf92c008788532b035c623b5cc2fd1710a82d2398e546df97e090d
327	1	409	\\x34af038f74cf01ca258f6aa8e1884ab10ddbc9136f1d7c02c0fd1a9d0b80b3e0b87b64e71de5bd93c6ef27f7555423cd6641e9f0aea6220955f9721ef7e8150f
328	1	419	\\x44a3ffdb5d8f8573b4785f6dbf8b0d4402c6eb7b68d4f64b6817466b8baf8c05f159139fbba5cf86496deaddf53d93579c3dbd45e308980c317f33dbeb033409
329	1	267	\\x0eb3950269c34241b66fec934e714a50764ad0aea935a60a9f6d5c142dd1663f8ae19ecb004a87345294f755ae0d21ef31f74b39dc861d8737a1fdff71ddb50a
330	1	84	\\xd8fbce046212f91e2ec882791c4e5fe94fd73cb8b71e87ce36d9247e8e533d7f39bc07d702def69c597685cfdf62719a5ee0290de3c3fd25abfa5adeb4593e0c
331	1	328	\\x21cd86c1a1470ff257bdcc6b871ac2669bc48f26fa0b3edd032a2494b21dab51c0d1fa554c143bd7360a4209e3d48415179b47832874ee2924800bd31a4e8702
332	1	65	\\xf39ac32a6b6ae9e96346aedb9081b2aa64ca669e5cf656e0960876e6b015956dfbd099a46b234433ab9b9f9b07fadef236c361d8513b2b42ab36acead5e6a402
333	1	160	\\x96ab2043ce76418c2ada58f344addaf50e30089848a4587ebb29f45c8f4cfe6aa0c3b318033340f04a979a60f1c023c3b0d6f28a737c0483d20b14a9ca084504
334	1	319	\\xab90d321e361bf80a06ae0d4f7efda09da4fc73494177e0048914960f999491cda1d807e95d99e331d191efa68fe2144a1ead59024fd6b28d066959a9cb32403
335	1	194	\\x602fbab68486f71baf5538be91dd46853f70c4ba1b26e62231cf5fd802603439bcd2842b4b5c4deb071049b81c0702fea85ce6007023ca31d387de46e1ae6804
336	1	175	\\x257cb8848b448b21d18c3f331222e58973429affd3b56ffda5904af59f03a07dd01d89fb97b8c6e596bc8a2fa29f2ec5dc5bc9b5bdd4ab697fdbbb2f2796700c
337	1	269	\\xb0e61d4fa0da87ad70355e2b83bb610438da62d8d52bb212caa7452796f10e7c37fca08e0ae885a0fe09c9ca06799e6ce41c1cc1229bfe7f804c787385eb6e08
338	1	142	\\x26bd7b57667e704bd0a4067bf1663578a3ce94285eebe317a4c27f898f46e37e0e37578a7f2fd5dc7e76648d078958e52065309aa860a951ba6f7bbe966c0305
339	1	114	\\xda00c4831befd4ba70f97ba5cc1c6ab462e3a4cec76e8a2aeee00d6560ff702613abb26cd9c84fcda4a195c559ace9eb9a317394a323e3a25b16b8aae1b4370b
340	1	157	\\xb06e0727d606c7151edba2b82a2fec8b80301dee48bc9235359783e7af05434c7db7ec5f7ff6c1957a5343c81392d61e2ea7b8be8b10bb11123de50ed26d9f07
341	1	411	\\x9c2985debae7454be39b39ec87668979deb7135907b1bb1db0e94dfc3378aafafe63d19946c4c6f70a9af80aacc8c21a254b93e148154bc93e38d345a3790e0a
342	1	254	\\x48c9dbd67332de7bf3be715d72f1a288d52ebbef04527bff1cd7529eabd96cbee5f475f0b49493d2c2f17c1a3d923f14ef12882d76ed0744eeb5b6c5ce119d0f
343	1	239	\\xc6b0ef4f839808870c40af24208ad8157262c628f572a62962300f69b96c548d0cbe9e3a5ee805027825421221e38f18f2a3925415eb1bf9830fb16c793bfa0d
344	1	145	\\xdf3e481e997e5bd09d272c54e49a4bb057dd062bd76df90cbba8f94d27140c8537764ab30a7fe14ff6cdd2e2381932e06e309054e3ee683ae93b37f94829c303
345	1	364	\\xd7950c003c8c2dfb71c237a7c0d2f8923aaf778dba6eda9077fa77474add14791e7f4d66021032989a87e8bd326bf62eb5c275cc63f63542bce9b57cc90dbe0e
346	1	250	\\x04e4711b47270aade5d59df81b829103cb43162a89e205e1b869d9d9feb4042d52b54a0a318b3ee2866375acb46185f5b69602b8fdbfdc623ecfe7609276f60c
347	1	349	\\x35cda316a0d8d775a3295774ff9f1898520a3ee84076880c27b435a41f5b8e3f43e9513bb7838de7a05885d79b5a5126d7274bb7314cac346286028ae1855d02
348	1	280	\\x4f91aceeb064ac8b2b89045cb2c923744d34079be86cb81114bf4a242d1a79ab9c4f7120868a4cdb6e350052ae8c42647b3263e7093520bf237e8bac9bb88c09
349	1	159	\\x2707668bb95e5fc7d47b91b36af0a4bed72b3ca8612aef8f8edd3307589aae97249560a4c424b55d8da53f18cf5551c79099e0da3ebef1fb9296b3ca6ebe5004
350	1	339	\\xb1047014cd307d04d19624fad6ccb16aab0a076a1a2d401d0cabf9e61325852f8631d59ed7c3915d5d4b205ccbcd749b939a1fade276d6b54b564fc41ac86503
351	1	76	\\xe5a37a7bf911e1ec7a47043b10ada7b9456a07ef2ade58b824ea6afe7893625d0b742681924a5d01cc26fa725a11b7da6183aaf52265bf996241a9650c41180a
352	1	12	\\x4a2c4c85ca02364e6c8165bb9c29a61b139d1ef721d78882436b63d801131b1837d800958449165cc206815289e28873860462893a864a51773145eaa1e9b90e
353	1	184	\\xdea7a8e808b88591b19e44bfeb56839f7e06703dfad61b51817676a637c971738df179e02730c0bcd25155c25a095230689db5bb02e38b0ed63abb77656e000c
354	1	55	\\x9ddff88029dc803a29d89e549334e14293a3e5c463129a1d9e1f34bc8d3f5c0d8c21c7b2c2790be441db4eb911a9aeabeb1aac3b83ebf09cdadfd566d1ce330d
355	1	291	\\xa6167b8ffd1c17ec551e4773e2bc75f806e51d9444e775dc9a5e2060a5eb5481e562d8adeddbfdea57f2c1d925f2481833bae95d54c85155e7b1ac0271b93200
356	1	262	\\x00ac03570efcdb60bb9b2e2345611ae20b1c3cb5e9e01f28889eaee99f90d5655ff3d71a43167b30d831c051d5ef0cada1a5176974bc5af71e35a246f2441c0c
357	1	325	\\xeac9ed340c88965ddbf92a74f3689585d2115901522293dd7eef591726deb840237ef67d3948651e3d34c474a86a35e5d7ad72cceb548f8c2f93f43d5b35b303
358	1	223	\\x3d7131abf2add93b5a41fe06eaa82af8135adddb68abcc365778c807a8f51d40403fe2939a9dff556bbead742adc2105573df81944d15254aa21de485e13cf0b
359	1	88	\\x6bb4855f2eb100fcc083bff6b250d9ecdfa24a1f6e9457f46fc075d93c3fd33f7f8df67d3edb564ef7f5fee427bbda65bcb4a625826f58387bfe2ceb3b5f3109
360	1	272	\\x2bbb52489acc3723abd858f82172478f4ef5b5545c2cbbce0f3ba4bfbccc747c917b5dd87eca27f5db0cb44c55477d561baaa012cb868574b0d8d37b916a0001
361	1	229	\\xc4208038a86df0bb5bdedb0d746ffc0fe7a1facd0ecfaae2b81c1de41fcfdd756d174edd6ccb2b2b4839afdc5a1b20984707f857df9ebf8ef883187fcf4fb00a
362	1	352	\\x4bfe981f78759ee6e8f652a006e953ebbf6b7112cd0d519a391a19c0fb42cae320cdf7dc1a754d8f331ce41c6bcf189b013881fa254a96b282cc49ea08ec5909
363	1	36	\\x5d742d8276abc616d11d0ef4d0bb12db5e848e93726362b71e47a4490abecf7ce171d99d89fdea14692db8d15b64932d20564ca0f3bb3e0c0ecb64d75fe78a07
364	1	171	\\x84c19caa9a030249e881bb724da9f07b24336964e5b4b957821438c97decbd74a8cad5763762171a448a1834aede2a09ad1ec4523d3d4f97945392ef7351ff0e
365	1	174	\\xaec2b134ce5acc667216e4510d5a74b3955fe571fc3af918212008e51b9310d2b727e2bae26cfa5d4d49272855446d288ace8b5f3fae7aa6c5d1616657841608
366	1	35	\\x7f484483a667b1c7f178585fdca8961d2a24ab550c2f5425ca1db5a50ebcf8447157edc0c1270d97ff8acc37d3441819ac8187ea5cca1d9bceb2f27678be6d03
367	1	234	\\x1bf7c2d065ff8118de71a2e202f0339ba0ca6273edf727322b7bab2a3850212ad25d778b0b5f79b8a434cd7c692b2e94f5b68281fc697377b715ff6338324103
368	1	340	\\x5496c3be99a9ac561103ea0c43922cb0b979a4b5a5105187588625cfc8cb417b636d564c17d57fe4389f57cb445a2d0031a4e5b4bcbeef04aa324cbac402860c
369	1	420	\\xd0008d6af26e7ed789ae7a1ca51f4508555333c74542288be7dacb56dfdd8ec234c6cb0e3efb6644d704718b2daa718c8f4a7a2772ecaac51548ee2b0b925c03
370	1	297	\\x3f42340b4aed77688ccc0360af19361d4265656629dc4245b587ca8c33495888a7562a9603ebc76ba033d8af8e8ed34f51b637d306283db3fde76838f4b71b01
371	1	316	\\x4affa12946fadf2ed30f9a0bfb200a2f2697c5c578f0acbed3455b25a5c166509d1eca373d9ffd369872e07653f28cd3e147877ce006b2daade19ae66ca4620a
372	1	86	\\x28a00abd3ebf833c98ee866aa6a6cb7f9d4b43cf731e03372d726d6794f11f849102bc3ab915d3523c399a8addaaebed6b19da91a7e4d9d480b15ccdab4fa009
373	1	112	\\xd229b39fe8cab14d2d38b657d5ecac4200c847d4be01c36f6900d871381c6f06763c5ae42e507a9a78ed73bbd18c1b936c135f4859f7178b83a1309f4d026b02
374	1	24	\\x98bddffebb8e5597cd781f358ce8673435ff96e17eac81800b6ca61eeb57b474955dbe86186a5992f6cebef12061af64ae69404bfb24a4e747d9bfa303ec0306
375	1	258	\\x31a2f314381d18c88d54ac5e6088f07a48a08cca272dac2ecafb1a6e7ac1cdbe95c46d8cdc9e0efcea4571f705f1bb267f21bb7dae7dcfe6968a36e9a94b270f
376	1	133	\\x9fa7b9a7b662d1fe1f64ba99696a7cd526e75bb852959ab74e93df46e8ae831a17abc1b340204da9ad2aa58ec2289786ce8d8b26dfb9442ead78e37d3fa6870b
377	1	50	\\x46bd49d52a2ac12de93881cb3ea6f8e079e769cd5b171f3e300fc4911a1e11f5718f082dd7fe940c4b513f858f77eb6d8ba4d9310ae45bd10038e34e2dcf1402
378	1	318	\\xf96058a8775f7b60187f5aad2875515326cd85349c22ba8ca425a2be855a1ce8b51647cdbf40854c7ef647054b27e43cfa9fbafc96039230281a2f4f8d831e08
379	1	350	\\x3559bc9a24c2b11415d19dffa1084d89f27f6f8cb3ba5ff70cbe9703050c7357aa5faf42af100ce0035aaa4f0132e2cac7d1113e54354c080301728981ff4806
380	1	85	\\x8a4ce8dc1afa094ce476859894127c4c345f42d727462cd14760b7e5bd55169897a2c24e6ea054297ae468075d141199efb2197fcd602b33f1930e01cf315808
381	1	356	\\xd195c44d3f918d099a4fd2587c5ec89eb8ca0e9c0d92e7d4ad7b59e74056e4947a976ebf6a39e7f49273a92103e700ba1cc5c1a835624c59a890e1732b602c0f
382	1	75	\\xad88f728b5926a4052e5d29fbc217c98ea3ab43fd0a3896cf25cc1483db9d941ae954cea7f516261e9e56121571b8519b84a229d3c21e33103899d01da326809
383	1	25	\\x19da6c26e301e2f053571eff66beb9e15f0bda89e828b2da6c5fc97c01b1b0745261f51534dbe7c1ec3ab3430df3e0a59970c62e374779990d416af86036b404
384	1	162	\\xb863680bce4996b4351cfd06a21fcaf793e15141be305ae9c3adc504d9fdaffbd749649819a7e2e32728868026dc3f4113fd6b77bb58d05e4da61a8184355b09
385	1	23	\\x97dee425fb4fe1660b652600adae8476ff95f2d214d475596c4b4f57297ba4d02eadfdeb96fc19027cc6b4bdf5a876d5ec5c98085f721d30fa676bac16ba3305
386	1	167	\\xef8024c473b15a6b2e9350ee1131eca532db700b7398384aba1ef1d6beba1378fb6ff9011ccc1596680ed3b9da4c6836e0a20cac73ed770dc02ff31070581708
387	1	69	\\x48e882b6cfbf683656082bf213932b18cd7e1743f43c9f13885b811d374e2b353ed1fca7121f846d0f8c223273dc559410315d0d3445fe84c44901c1992d430f
388	1	21	\\xd84a73467c9afd868be62e6af6785a2b187e9064018ee8cd4cf48d96bbcecf976374b471b64d5fb8e24f4994518f5f17bf814101e7fc3446ecd98602cb8bcc0a
389	1	187	\\x04c23692ce92247ccf7e2497ceb1f08357be3bf2f59aa0753764bec27c65b2c7453afb009b58c427c658edd2f1fba7fa0bd71fec7fa12cd216c5ee335144ab05
390	1	298	\\x71b8b6739759ecbed039dc38eacc24429798aa7859df51c5da1d35335cd0fc6f48287cbb8261824fd412a31e7347beb7ffadc9a7d3632319afe1837aed8c420a
391	1	41	\\xd9a91103c20470fc6635d7cac1cd91b5c38d0c779fe241a2c91d117caabceaf8111395f23904fc79b7f93f09741d6e63fc5fd98e038b786944401420f7a53f0a
392	1	284	\\x906d6f735a2f910365db4259dd985d70d9a100a79a25a0a652a6a9f2ba7caf70a5f244e36815480730d9ef6032fcedae37621429607fc3cd24bf9e893cc51e02
393	1	13	\\x1c38f990b6ca51445f282d29a3aeeea0e304375beae241098754c31ff79831057300904194d729522a0ca68698ff870fa177af807c569717645f2b8961eee203
394	1	393	\\x3fc74532c46a9ef452fc6448e2fde18fac7ef522effc04b1adda4fbd9e1abd4415ae88b8a7de4d68d75ac1b36a08a82e1ef222187bdbb60050c25fec40390e04
395	1	33	\\x00886a87ce5ac00e39a4106c37dff86303b45cbae7ad1314f9d069fdee27d1cbf99d6f306ef2377ed037aba650c8618fcf00e209ec7f89460b0c3f686a2c920b
396	1	361	\\xc09272bd77f666fdb1c9407aa803ba453c50c35ad95c9b6638d549ce2dc0032e83c9c47c6ad181c6c0ef2935619113769b31faaae28df207b2abc69972e65a0c
397	1	123	\\xe0fa6ba192f291d304569172955492d71448cdcdbb7a23e5d242e75471b3ad28f2a42d215ece4247fe331ba2cbc9f907b665ed5bdfa6adbc06c325657eef600a
398	1	278	\\x27c58b48213fffde7364072edee20bf012d0385a780136d8203462e4b11771a9773668098590b9868883a7a65227e8c730996fe30aed383881f7b0822832d40d
399	1	344	\\xb01d7318b737d398d5813f820112febbec28917c7820bb0612130a159c67bb2925457ff85744ac76bcbb163f0efaa742ec59f6669b4c73a33f46e01c8d645701
400	1	236	\\x89509ac5536c607638a9d4b897649e8c6da815276ac7ef8b8b2feda0f401d716bcb95bd9e542b01e31964ace8e4c74595396960646e405be5d3529fb01304406
401	1	346	\\x5c99b6d28a10aa14a68df9dfbded38f58d1dee2e3f221516af82219d9573e9a91ef4eb7ad85c204d4016fd50fb2a7204121ff1a47e4b53002b83b566c73c9d0b
402	1	51	\\xa8e2b71d33c049b2bd141102f989c16ee779e985ca1abdc00ce0bb4e4a58abb8949b58572ffd2a5a9f64341ef1d46d18fd94a1df5625fcd68fc10a8310ae320e
403	1	331	\\x258e728676298ee106762a7ec721e467208dab6f8a202998e3160d0fae7e2ec152e9577b9d6b799272ca25668e1da753ccc3733281d3ffbe5cbf49db43c38403
404	1	68	\\xf27942457702619602dfd5afdbf79ef6449815e39667edfcf1414a30ec99a73fcd917ba52d046ac3dd81ce25ca8bcc1d326b5c04e46d82195ef850c950e4e704
405	1	109	\\x904eb0b8a28b79bcd8f4f7f8e4dd9ec5c138a94aef59a802bfbf07bb47cfb4e6df6e217a839c73bf1e561610eaee02d70291ca52d6af3f72cbc01fee32b33e0c
406	1	372	\\xbc4cf164dbd3e59ee1930dfe91d06e7b5ade161f937a6e37f448dd8238da46f089206eb9973598bd11e53009c5c72aa8e293bef246a663dd5c0982153889000f
407	1	178	\\x9c7359f690a2895ed9c6733e55e34a9482715bd290b6845146982acb5d1ae9c5923fd30b8b32ec06f3de69bd2e040a38778a35c235630d39d07cfc993695f906
408	1	371	\\xadd7772ac703c96d2f7dc510fb6f3b4eec9de204422e2869d27fdbc281d155d4b4727e9fce58f0bdcbe70e4027cdd3c5a024232971159b912af3daefd06beb02
409	1	405	\\x40441de34136b61f8ce5eb7b24aa83631a3c1677d4c4889465306ec46b4a84e34a5b24020953ae1833702151e4a5300e284d173ca28ecd26ff4b57efd56bb30b
410	1	71	\\xf79f76a215e01e0be2f1d8976e24d039197ee3478c82bac777503c65cbc5745e9c8572a97d92ba4deae3228d15a5ac406f8c476e1d085a81910afccd3b163509
411	1	329	\\x37e9464680398ac83d6577c5bcb2acdb7c220b4e288d30d83f3bdef935e5b2b87cb7b5dff99a6eb181e94d225331d96a6a9f5331dc1413ada1a5ed8c0841ef02
412	1	45	\\x27c2c09db09ef6c2f57653b1b65e51f3e12c9d0a1b0e462973c7bfe6594b017404dec41532032fde8672a300cb2bde2db1c18919310582ec1cffaadfd8273c03
413	1	193	\\x63609b16149e10ba0ea4b07dacc4ff748c5700ca80cb0a2cf225662754ef74145dfc5269f7dbaa20ca8b1627507b0b3dfa68d18664855d5ff5d585d11645d40c
414	1	264	\\xfba30d5183831e4b6cf7c673c379eab0e9e5dabe110cf69923707176d338aaf4397ef83b3c75feeeab3a7e0d5415b38c467a706be915a43f5a858390c5e7e00c
415	1	228	\\x6918b6a52c5ce89f8a2611ad5efe9c9ae082837c9186d39f7ea857f1eb9baf125808120b27d9dd6eff9731a9b452bbb915e81e652ae9557e63e20493ec361e0c
416	1	334	\\x1e7f50b8a8a8d03394ad0c0e829044cdcb4a0e55771bddff39cb729b558f800f2e5bf4ef45fbf729317214d8e49f3675e3df602f69bc1254eef7fba1c17aac03
417	1	3	\\xac9945ee31669e1fa4c6e7e84d0446e693a63aa73c5263c1dd5114fc5e0ce55a377f9db8220235d4c3cfa38f18447ecf66c3e132eceaf748db96f85c74f09a07
418	1	210	\\x1aff25668aa9962d6bf0b06729ce9f2e1373106d4ea8a844c01427f0b35d4c79eefc7d8e4458ae0f2f12a4cb7dc12b5784cc709c1f6aea64f9391f48048b6e0e
419	1	70	\\x6a56757d3ca6709d02698e35e8900a6905677297e8f42a8652cfb30acc4e494e164de94b0471339e4dcc4cd7b10f03297b279ee9ea5e2e928a96247db1daf80e
420	1	384	\\x8024621a4bd9310aa016ec170f4339db733b9866c54aa46c4e54856fee8f17798c8c366e5babe75f31160b9390f628a3fd83cbfad46eeb88a1f50c80fe616206
421	1	353	\\x4d44e0a39e92b51030ca7c051ea6a79367aa584914c79a81612d974e8d0199fe1b50bb5bade5e9aff81376ca9f0cadd32a8b8d4b9c2faa73ea3824d0f1c92d0e
422	1	6	\\x712589007d765917f09bb4419698942d2210bc0760b8a0d8bed468300ed3bbfa083e6dc28d8a785a1ed1e89b11c15b1aab5531e6cde80c18f0cff8cce4e05107
423	1	181	\\x6c0a0610c530bb5321328a44e2246fecd71e3fb58f21fb125260d3faa625a91a61cc12d42782b9cff809554fbf412ea8a14245acb06941f2bee72d1533402801
424	1	104	\\xf2684c36ab39e85b2e3c456dd71a4d70f7447798999c496f317477cad43d093fd9f936237e0730da684b833169186dc7f0900cd0cdd34dae1428860fcfce6b0c
\.


--
-- Data for Name: auditors; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.auditors (auditor_uuid, auditor_pub, auditor_name, auditor_url, is_active, last_change) FROM stdin;
1	\\x28c303bd44cf2932c4c07648c472632b09ea70bd26d3fb442442d4f16d7976d7	TESTKUDOS Auditor	http://localhost:8083/	t	1660654496000000
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
1	3	\\x607d26e58a91bfb241dbcf01f99ea2a512b16a12681573a42e814ffb721a265992dc958947d47d60e581f33a7255d1d8ea7d1798c95661b3e5474c947c87580b
2	228	\\x522b2f1b9ba6505e5ce4275c8294427043d82546c7ac0e6d5d3db7277e4385efae67bcdf1392d69afd1cb4375d9f71dc294752c65040b4791444e03039986901
\.


--
-- Data for Name: denominations; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.denominations (denominations_serial, denom_pub_hash, denom_type, age_mask, denom_pub, master_sig, valid_from, expire_withdraw, expire_deposit, expire_legal, coin_val, coin_frac, fee_withdraw_val, fee_withdraw_frac, fee_deposit_val, fee_deposit_frac, fee_refresh_val, fee_refresh_frac, fee_refund_val, fee_refund_frac) FROM stdin;
1	\\x00b06faeb6e532e151b3473ff1aca08cc5666ca63e2350152789e84515cc108392238c0270b68d988ea9eeef2906751ea923eeb9572a501d01724042f7f5eeb6	1	0	\\x000000010000000000800003dda14c02893abbc149ce0da89e162c036ad9e8e67eb2c491f9fd643fd855d6698f0b0f1daacc5671f9d30dbf430967624bc223d28a46caff79f27b73353faa4758c6e25af01f8d0fdf9992f7c5941cb76e86ebb34f9b57b15c96eedc026b267fc6780620ff32c20af2465874a15d5592a7e8df9cece207f513d6d230d666612d010001	\\xf2501ccda29d5785f52ba5467afd949afd0ce9180786e0d0c9f9a111dec83dc1b42107a4a5253c766c2ee614ecac604e48018d0ec599c792af921ef4ee1f130a	1685438989000000	1686043789000000	1749115789000000	1843723789000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
2	\\x05748f14db2f6ace8f06c2325b5f69e51ee4180dd6002c13adcedad9a4cae4bfcfca9533dc89ad7c56d8db73197c167b76e8c0beb3b19c37111f8f10c2e79865	1	0	\\x000000010000000000800003b3c8f5418eb645be454cfb78109f1c825f8a8aff73ae006def491f90ed63334fb8c09a549546bf17c36c7e3ef728c0cdff98794f0d8b6eee05db8288bf0ee316f8ee7953e5ffeb8dbb117556935264dec29b79d85af57d6cb2bb960b530e1dce9b6edc915861010ca347d0d4ddeef7dfdeddaa18b413c0890a6e9a8cc6ad55db010001	\\xc942a18ea2980935644f8aa08b3fa6a399ae4f1467019e628740c37016ea642e387d1edf1662c6d706ffc38ee3c7af2bf93581ccac6891da4a2091a83d386d07	1685438989000000	1686043789000000	1749115789000000	1843723789000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
3	\\x0560e21036d3ebefa8ec29de004cd164623eebd00ace97f014520f79d95466a55f8598566286e831033865f53ed8f61a9743c56a4196b9d84c59ed96952e0830	1	0	\\x000000010000000000800003be472fa3940d1d42f8143f93e62ac271f3adff8b0a9a91f5003139e01053d4609e9b27ca769104649fc9dbf02b91aa6e0a7c02189e7413343c1f5744a07dcd29383b3f2cbc93699505621b65568209cc270c86fe827702599b197b851bd5c800209711dffed7e663e020f15a018f2bc9c0d47644e8cd06118368e142725612cd010001	\\xb226bc05c3c3fe8fd3d895c5dc2071d4293d17790b663154382243e5aabade050c5d23231066040e7e8efbc6b5f171bd1eae7f777da63658bbf07cd5c2fd8900	1660654489000000	1661259289000000	1724331289000000	1818939289000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
4	\\x05001455a02ed1f93d00cf44496715950bf588188d9ac46a2f24a630208e444f847d95caa299754b9245d3bed06a568fdc5391f75a14cc668d86e0e09c65804d	1	0	\\x000000010000000000800003db38978be361449dbdfac5b6a62deef17b4da7ee5dbbfd72a6e985f4b02ab65bf5c3ad7e90099373c6dadcfb38147069501c52110527ebb07999b1987a777c4b172e5f6e3144c238f45d4b2ea106659069d644b5e6c6d468539584c3387d5fbf7fbb652f13f9065d175f0b3e4cbd6469165aef931a1749aed2188384e0a66e03010001	\\x3392e86e21b6d344d4e2e515497e5586171a23ad8a6a030e55645a0b8312cfba78326fdd44a1245ca5ae81f13c80aa1b9765ced788f5ba4907d7529ca5559b01	1691483989000000	1692088789000000	1755160789000000	1849768789000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
5	\\x07b43578bc643c89cf224bbc05ba169ad60b93c55fd208b5d89b20a3d636164dbb57c522baa33c69d154bb423aaf38b61dc43bf5d195d71dbc9056a415408284	1	0	\\x000000010000000000800003ca5eec68201017629da7a6e86377df4e00933313395e4628004c28eba84ffb9cbaaec17c3a4efd2f9e133d090e375444741753db3fda008d128e9fe6b343564d9f4c3a2c30c557bafdb69c01a3c45d758a317eb7c7256dcee195960c7ed371981a4cd243eab9b22c4d0a883cc5cafb39b6c6400e22cc635212635b6a29e5dedb010001	\\x55e52571dc9747287fdacb00b451fefddcdb710a9b728dc5e0be9afdbec89782156a03ea1ccfa6bf9d7d5750f26275d0c69adda37c9efe2f7e8bb74efa970a09	1671535489000000	1672140289000000	1735212289000000	1829820289000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
6	\\x09b019ba4a0a3088e5ed64c73d1b55f41e9fb6d3b7370f702a22e90d52cf0521f9dbfd052ae227743b09761338ee41389d54403f087e95d1d429b02d803e1e29	1	0	\\x000000010000000000800003d12deada637d84225321891cc7036352d53039f74426c63945f7f2655be59bfd4ec5daa54f23fb56e604a5ec71c877137df26c9e6ca44725889416147cac2c0ee940251e7746d3218ced499a8f464ac2f5f49eb62f892dc19eedec596a8dad08366a1f8d144b5f36a9633e522bcb5354dc9131e5e4c6fa46a9362700c455fec1010001	\\xcc9534a7c125f80364cc9afe55c3fddcca5438cccc289f42dba777d0cb3cfe68661136dca1673716242707356a03db6970c0a7a5082e7a4b04d14f54a6978900	1660654489000000	1661259289000000	1724331289000000	1818939289000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
7	\\x0cf4b91cb0201e9bfed6bc331b000d11a73b20ae40e9eac38dd901992281e45dcbfdeb67b8453cf6c66f2fedb47a1c3a3396aa5f743f0406f96d5fcc3eab830e	1	0	\\x000000010000000000800003b6f7f688fe8a233916f7fd3344501a11237021d15d7b99e29d6b3803a628883ad0b482b516db993ee65f8a9e654eaf1368dec93f5d6899b8fdb14b2c920e73dc726e6f04e417e2a140a288c50b00916cc9a45fa9c42e8c5a191fa5fe9373558e0b478844b43b52d7bde3c8118d6414c9a9fcafbd0381c40ba5feab32ace83175010001	\\x712b8e696315529c2a26028f443d056d72d99b327f7faca72d8482074ebdc8f7839b9ae898d395dfc96f2cf096929e9e58890f989fa9df1e955d3d9171d27301	1687252489000000	1687857289000000	1750929289000000	1845537289000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
8	\\x0f7010d16aade91b92edd4c1edca5a475ffe5cc5b88427072cfcd98a576d63bf2eb3cf4cb8239da7c528f73cc3087e85491da59a6873985c8f6b0eea9adda7c3	1	0	\\x0000000100000000008000039ee705789c4e0bdfedf672bfc0d016495e4e2cb4078656bb6dc6755a1bd71c66d0341fa67f28ac60f81522c3d5292212eeb7247af2fc7b17b5002c128eda47bdeefc4137c08ad2eaf066d709fdd19092468bb2a85e2dbba492295647473a3fce978a8af8d2ad86db7ab7533f162c7b45d4b67b800839d2be649101a8c1a79e0d010001	\\x10a413e31ea0c28e937bd7dfc8f92e273cbbc83d92be39df0d1d25f981c777d2c8caf2f9fb459a8f1386c795eba130421fb1a4a4238c7aa1d531c7abdecd5a0c	1675162489000000	1675767289000000	1738839289000000	1833447289000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
9	\\x13bc52a51bcb8fd54618da17e9cd306180c72a576b0ee3a69ef1aeefb9a7839241beb2a0ee6eccf6396279f91c3a97e9e1d2f61a3d8ba7f8776dd6eaec2904f3	1	0	\\x000000010000000000800003d165642c824d80828a1a4d2b027bb692d6c6e284572a9bb252e8605cbd9c98abdce01f9c64365d800139a93c3424792a634e18cecb0fd4b13adb670008404e2a95c738401a5d0b016b6617345847011f8fbb3e625d1280950bf202b5f6901d40a3af51b7d8e95c72fd21ebe2665202c48c82456a0965cae0f90d0f1b2e7c4237010001	\\x90774982ff88f5538f6005f4d3f6d9dbb9c6f74e79e035997fdd83264b97408350ce2d0713f3cc632056a7f8a743230408b3f8ea981b137569a9289d5c491506	1672744489000000	1673349289000000	1736421289000000	1831029289000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
10	\\x1414bcb4d095eddfbe632130ffda1218601efd7de1af79430286f67fd9b404b59df165c3e40e1cd3d6a047961ef902b32a3db1a703f8ee6f759191d8acb62c43	1	0	\\x000000010000000000800003c10f0e436989cc8f5737fbb6f4e4c52c9a8568f70665585c5b5b95bf34784b1b5ef2f28116aaac363831caa5bd8f85efbe50b72c02d5dd5b2800f4edbcc26a7349b5996fd09b9688c85e9ba607b54941c0f57aff9072326b984aa30b0630262df2068b501d48befe1d4b0445f846ccda2d9fa562b0545b8a7edbba329fdb8ed5010001	\\xa63cf5507bf135726144da968633dc0fe2f2605d83fc8ea6694c6a8d44a3d513fac76e23f31328e4792bf899b641d53d3194bf1a9809167e6576d583fc379106	1667908489000000	1668513289000000	1731585289000000	1826193289000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
11	\\x142484b969d0691aead192fc2466ebea93e58a0f389880be2801155d0fd32b12289891ae0aded390dfb60bbd87d84cc52d1e9fc421772f4da80e42b0dbd4eef3	1	0	\\x000000010000000000800003b87f65dbe7f3ccec8eae9e7fc3ca058992485a01a381c9063c0e6e792ac36ff8e0939bd0b0ce0c774837f2bf1bbc51a89b497ab3be48484182b74aa11413dd6eef4f3cf46465413e3f2b97d59c4b912d68d1b8e277243a8d5d0d0563eb36b7200ba522d062afa114a298ef948879b03d6d55f47355b60e0a66237ee2c6463bbb010001	\\x6830433ead6b27f9f220292ca7324a73dab2c3d9504d4aa9ea0c900b2085ebd59c1a15eaf8d00eb7cda6b17828d503f774ce32e0b3dac16bcc989fba5ffe6608	1673953489000000	1674558289000000	1737630289000000	1832238289000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
12	\\x15f4f7c6aa625f799be25c5e9ea2a88ca6b2e52fccea1a67e9118423305613c8054d733c809a8f6c7d536eb1d8d76af2b5e27b82614db6ebf60168d26655dd13	1	0	\\x000000010000000000800003ab699bcb69d0bf72b91e880eadd42fc6e84bf7e47cc83afd95cdbdcdeeebd461a9fcbe32889e4d3c4870b756e2f447cfe8e372e4a0f6ec3b32c90525cc901532404b49f5a6f3c60f3b828caac29b6ce1ac5dd671125917b5fbaaa1adae4e9fed84e495c3b67b1ed3fed05c95fa623c2001704f3fa6b7d66521670abe06800199010001	\\x6cf35c2551c49d0c8cbb4319987db25c787950688447a5e4639a653a6774131020502e9cc23d6bcccb55dada6e5069d36d2ae29f4029c65815a7b290c3d6f000	1666094989000000	1666699789000000	1729771789000000	1824379789000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
13	\\x1764f41a9244c00dcd4f6e2f1a61cfee7dae79c10353751bb0639b886b6fd879e4f395b69278ccc6b07f54b968224caf2c0d65d4d43c25f6830d2f01c32e1422	1	0	\\x000000010000000000800003b582ffdcfa7ee50761be0b417d0148d0eec2c93cf65ac702714e33502a646a23062fc5f3403ac6bec5875e0016dffadc91961474e437b157b12a6fbc0474c48497d3ff5ba59f7927993d339cd0407e08ccb6b65e176ab5c5cbd30f0f3eeabdc5d74c976c927ab9a5e077b4b9014bca133f5630fa4ff53ca893c46f854ad04749010001	\\x9646515f49cb5237f32b3c7c5a102b2b5d316c6303f6b3d4b2bde0cfdd8154078402d88fe1d8d062b9e12b2c44a22885f9c093804db69e23240a14dc03b38603	1662467989000000	1663072789000000	1726144789000000	1820752789000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
14	\\x1990987f985a95f05f09bf4949dbed8b1c9a03a29192ef46958a140fb9075948d1922cef357aea660eb7aecdc087e2debce9065c1116981697df5d58552f0b13	1	0	\\x000000010000000000800003c270329272aa3a5114c8117efd90d36eb71068a9e9957c9bf42246689955868795be28d4621b6d346104fabe0b191b211d221c38bda6d97ceca4d376d4a0e1c92f33168a4293821ec575f2150bf393d17230edaa19d2e288b7c176dc530202f13a80372b62dcac5c2b5d9e3631fdb8a09e38ccbfd80c7062e568ca5ac1f03645010001	\\x33508e25937166e27d05c5bb721ceef25051f2d7a54f6b1c7d0ebdc52a74a5b5b8d8a5468107534d8d326e855bdd9033e26a13aca095e45d30fd58fe9295680e	1674557989000000	1675162789000000	1738234789000000	1832842789000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
15	\\x23bc55e2dd4cfe8c01ed92102ddfdf25c466eb76a07fcbdb0b2a992512ac48b3c567df3f7cab5299f57a9b8fcaa77b8bb94f160a98945c2f1eab7b021981cacc	1	0	\\x000000010000000000800003d3945e4cdc833ce1ec1203dec2c79d5d5c7643e3fd677d94abedcd364075a4895c4df324e4248d18d01e8665526a1bdae2053fc47062516f04051b98378168145e31a0b2cf3d2371216b3f8332a41563f1f4e5b61386932b62dc4ff7a85b86833b90755691e6b682da694f153106ef1a91223b5fd83f45c5e0b9c18affaabdad010001	\\x95786d8c9201856db6013dbd13a2e4283ab15f8326cffef5d8f266b86c04f0191591c1a0c14f9f93b37bb9ffb50c824a373c4de9640c2a1697126a486e877b0e	1673348989000000	1673953789000000	1737025789000000	1831633789000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
16	\\x24cccff66244c384340bd88524d582f09127bf09e3d0892423d1a6aa799dc09ad2206e21f767636537eee75ca1c5885ba50f0a67da92bcc48f7d3e54ea6189e4	1	0	\\x000000010000000000800003bd62d553d5af7b09659186a90e730cdeef5f1dbe90e77e660d37b8d357cc988895acec3a90ffdd8262c44cf7ae1ae281a4f835727060a1aa261bb74b5c4df344c86772c6cd37a0780f1a3bbd3ddbdac6942af9909db58c1736892b0f7d6d2e65c1b8773d211abd8ba74eaaf743ad997172f891f530a3493f5774896c4fddc3e9010001	\\xa7eba54a3dfbc43017a4d3f0f7c1d6d58c133754a93de35c87d203d17fe04542f5f370c87d493383bc9ea9630c4dc50c369b603d90aa6ff37fc5d66ba423fa0d	1669721989000000	1670326789000000	1733398789000000	1828006789000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
17	\\x25d4bf4b60976f16ac27fae0c7d4ec9de21318b575068b6f76a01911ab8ba323cda6bf1a61de7978c6bba60a7d82de884bd20bd18a34608c16944a5d147afd6d	1	0	\\x000000010000000000800003d2dce87303007e9d1fd1cee7eb6f155bd254054bb27dc7109ddeede53caa5a1abe60cd0de7d3e12e11deafa1c7a7a4a0f44bf99d2572b5bd451dcd54795c7997494a3357808155aaa9fbe4e2c6ea68e3bd9225c83f02e8f5a3880d484d669fb526cbb77a5a067bad51cf66414d1fcf01b220d17e6de7193dd10aa67491d54f85010001	\\x1460cecae0ef05557f173f9dd4c49f98831fa824b61ede45b8987e8d5372cfe70fa0adfaeca2c2ac511f26709b536f217d098f432fa6c8ac3f3611f89897f601	1681207489000000	1681812289000000	1744884289000000	1839492289000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
18	\\x298497a558268311a412cf7aa8409cc2a8ab114a9e4c314abcda787ccec174c154f923b54ac324356b5590693e249860b9be9011f68c078e4b3cc015259b08c0	1	0	\\x0000000100000000008000039d52d6740ec43726cccc90d57fa35cd05dc91b5cd8002d713612c0b3a7e6bc10ad5a4f3dca97b712a2f12487ee94542877542b40eae485e82870fa29e0599765abddacd2f81f191b44c300e7bae38b6fe0175bc5fe26270b4d3c0819c6754521343ddb0a547c8d7f5dc832e4ef76ce1ca79c130ffdb408f13590c1d1c5b3afa7010001	\\x7b49cdfa5387ec501566738f270c48a9bc13b2816d23866ff33d3fa49568d7d8a7b8f39b4eaedc483a422b6ce6e6b38b6ac24386b6d03f8829a611ecec9d0208	1672744489000000	1673349289000000	1736421289000000	1831029289000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
19	\\x31a4c19b1a7e6a1aae752b3a0e6fb7e2dc4ae3daab05090a06809ca809f5740f590fca09ba099ed11baad9d7cee7f219b5396ce0433907c6e426c8cf608c34e0	1	0	\\x000000010000000000800003de531caf80c94d6d927df689458b9aa25ea03ade54cb2e9f65119e84ffd17446fb4649fc4edd003a03be53d2a9deebc8eccebeb45bde7c3676774bcb67e3a15c2fe6ab6f3665223c325c979b317b462cdbf3c929620b484b98110a3a8f4021d1d3d7a13f263b204c69343230e1122e6ba49899ba6ae5d48c9d39f8a5a41b1747010001	\\x133f16c411aec815ea7cef032bb5cb4cb7574280a9ab47978aa130abd214493c51e887bc5bae322e8defb140bb8ecbe71b808eb3da6b01a57d8c8c6de9687503	1685438989000000	1686043789000000	1749115789000000	1843723789000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
20	\\x326435c799170acb2b2c3872a4e62717b920566537d70f57e4bea4f7a8adb6afac41c0aac900601e722307bae3bae33c622907a28d6d353ae2546b13e3e66c8b	1	0	\\x000000010000000000800003ba7ecd2c23246a0ed3dcf3fb59148b9bc9d7274f3d2c85a9bb72382352a57ff3a11bc3cedb0b8c41221cdf34b56053c13cbfb91b5084fb142a305850f9c98a3985a94604200ed0378c4b023cc6b8226817492113bbe3b04b27635c38e8c1b31e840f2f443024c14bd5c61faf59241d4c6dc00077e920459227c44dd3fd4e72b9010001	\\x74a7524b454ff6f2d9a91459b84f3a0c43a7c63e932cc4328a24bac52964d67ed6849558b9f6acb6aaa48e0f55ec1711a0ab247da24c48c186f265dfba988504	1683625489000000	1684230289000000	1747302289000000	1841910289000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
21	\\x364067c0248c1f09bb257af097a0cae754e54722464a06aaec638fb2043c77c9104233a8f62622a23e33d20d6c11012160fc8a1234cf1c63fd1e74f0d517247d	1	0	\\x000000010000000000800003a8b0c27caecf32585d4736db7d659b715986b7958338efb34b9e28f6ea81e43f6cbd960b3f46e213233457368aa3b0c7fefccdf397e57039d92acfa88f8a0dfde84e3d8c6bdb6e0aa69f84d7864ab13b4eff8c220a5715fea769d9af68d74c3eecaf3670013127e4c7c736394d0e57414f7140a6d2ff6ee7c217be25af49c213010001	\\x8885d4150e56e065f8c1454791484df38d285ecea635c738f9276141aea09fe2b44b2d299b6738f1feb0d8c6e4e60c9a51a1fdeec069055a2babb53b3a89a000	1663072489000000	1663677289000000	1726749289000000	1821357289000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
22	\\x39dc49df328b52382a44bbe572de2e37b789171e4ec39a11bbb3704d3731786688016fa79b029dde4541ba630f88c3e5de495d7c65998a8e92bb9275572f3685	1	0	\\x000000010000000000800003b0ccc2b28f15f75d8c663b49a417a916b7776767542bcd3695f5cf59993b8185ae8927c648ebbf6036293713c767be8c62a12cc3cbb4be7f8741e1479bda06a5ade53934eb8efbcc8c54049a7bc3b79fcdb2cbdc2748eba963d95719f15f62c849a34f146fdb382b02967c47ea99780852ba6088f835d42c616175c784cee3eb010001	\\x362174162db88dd4a2fc54a4d2d8045936dd95278af75e2e47e259f744419d59f4a947713368237e3f279158f0f4b0ac94eabfa140b33f4ecdd39a85acbc5e0e	1670930989000000	1671535789000000	1734607789000000	1829215789000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
23	\\x3ad8031638f3273fa756a7ec35f313219f3747c0ae27b4050dd5844d87f38b5001b14dced86fef8bb6d84256497a9d0aaa20eee3a7dfc7c47fd9f5e15ce54b7a	1	0	\\x000000010000000000800003ce1cd8b4b59c49ffc2416abdd2e0acb0be9d2e9c37b005986a40448fbdd4a878339577036c07e541b3524946ebf2b436692ddf5b90aa49eed29cfdd4a07c55358dfd32a145829e71875723ef544ce1fcd68aca65d55e8e667bbf7383741224300931d367293e460812615514996da7314c20ea811ed7d1a8e3ef984003441e03010001	\\x7f68a2cedbbdb369ccde87d5b8c2573b123b4ba6fdd946ac0b3bc912c0578b56e42e53e402a90444e216f4acd5879db6c0c18c30d62dceb0feaded4296e3d703	1663072489000000	1663677289000000	1726749289000000	1821357289000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
24	\\x3a8c2ae755179d485522c2dde89af64840f46ad46f1bc4b555751131bebb1e25125c23c1475252843a596bfa84deec34ad769430b04caeffad8a40122507c13f	1	0	\\x000000010000000000800003a2410207a49786d4211c144c31e220a557cc31f746db16e990ad72b9949c0b82a4e2f934f1cc46f37015027e934b9d55e509bd1415a973ec1d7a0cf43ac6196ef58b56d47621b750f06faaf0c8f3af978911ac4ec2f2967e11b6ac0f8aeabf29fa88f63d46008c9483b1a6c56f97951b5684956786d8780bf7757eb6c6d67771010001	\\x1d686a74179b68975ee9a439da484a6d116c35038e435b1c05528c626e01498fe530feea860b34e4cf8224080c5fe858dd6d1e8f3dc409cb5af6d1dfbdcddb0a	1664281489000000	1664886289000000	1727958289000000	1822566289000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
25	\\x3b2c9f356cc0adb895683d2da429ea359815198e471d661681980dc9026adc1a422c0e3d95364aed9908a4a2aa882fe88614ddd4ec417b48cf8a4cdea35b5b21	1	0	\\x000000010000000000800003b36e139b8713ca6e22719af18081f6a7ebc93ec82c87e03bf5e44d598773f3f729fa668e1dea6b68ca86dab0a4dbe1f1298efb50b0a8ae351ec76afdc24df8a84848b792afc062e5f60f669e34f5ea6364e7105586f59799aabc6dbb8bc23cb4540c349d505ec856264481dad6830861d83b4e3cffff58149ee5515771d6fa87010001	\\x112f59e0d0575af163e08e613e83de8a184091412475d1b25801d1d791e1077abd888e565a4978ede636ddcb0dbf0fc89d1093ee4b3325112f2acb84a80d5006	1663676989000000	1664281789000000	1727353789000000	1821961789000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
26	\\x3c70f8468a74c2e948537c90391c1155c4c22645dc424b0344a5df91af32c7cdff11a67a666144c67116c567e09d89e2583c5c316cb2937b3d01701bed3def2d	1	0	\\x000000010000000000800003c2c00e7b14358466b86587cbe7043bfa5a5776e5924f8eef55aaed3e8376516b867b73c33ef791061a0e8940bfc26155e87f778cb5657688e8288a10099e5b5b4083f5000d436a197d492be9d6a27ecd717264da5b4991fb5d4a8f21ba55bf11677f87d36af599939e19990fd0a60baeebd7d624afecc332f13149f7f92a627b010001	\\x1b22befe7cf8960068bc78fd808c47574c9c785916353436dc18983be6006cb467b4d4181e04a0d3b3dee7ab04db1d84deb129884b9fe2763f388e0fe11d2a01	1689670489000000	1690275289000000	1753347289000000	1847955289000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
27	\\x3e90be0323fc3e4cb9d9f1fd8ff7bee6bdec055a0bd546ed2bb5e7f36ca925fc92d70e7257fb43e7db07c9b980d1e994ae5284acc8140ff7976767e162bf4964	1	0	\\x000000010000000000800003c8e5522142ea58cdb3e06de0a7c50a00e26162c79e8bc40fef5ff6e51042bb9a070a21359918607df6c82303188881d6b1176ad3e5aeb6d1a7cb279f04417d865c1e33d5705b6997f6c66728c8b658044a44ecb8b7123e9a03941ae674d09282e6d3592cb8ab3b3fa4e63668fa7fc1976bfadef9a1e40b9b08a797abb1cf3c2f010001	\\x06481e842bb886d3b5e9b936d79d8fca41fe08335b12743ed9d3681a6c67d269dccf834a889e47de75715e650a6959eef11ecaf6c700b8b4bdf7a7f3e11d310f	1687856989000000	1688461789000000	1751533789000000	1846141789000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
28	\\x40a8bcddd230f0416d348f64c17bda0c70e80519939f59b1f0ac64784bb4a8560227b198b58765721b5f44409e9394d923b27bf2d8e9012292db52d3715a7a24	1	0	\\x000000010000000000800003aee96a211afdfde0b9c742f65646b340fd3d6ecc94b8e9065b47e34d8d6d22e2fb32ea17a5721c0e12124e0135b0119eb99268a1904d2231feff897af702a0a35172e64b22e83b5575754eae854900475705bc312d4404e1c39f99a3b0619696f99e76c8a51b875483288067e0f9fdc5db4ad0a72886efdec580eef436a03f6f010001	\\xc64558cee47cf3d0636c1a2e6d1e66aad5efd878f6a56dd3e0cffdaabdf7269c980c73083dcd1d5c66ef1dff3a87d81e0e6c2fc109e824487b9bdcbc4a7b0f0d	1686043489000000	1686648289000000	1749720289000000	1844328289000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
29	\\x41186b27451b29f3edbd0ff0745d8623bdd0a76f1f853b4b04a30addfd5bfb1e1b03a503564176389214bbff206888d1640b7a3e35b4f3024e7b7254b48d5f94	1	0	\\x000000010000000000800003c16fea64614f56ff39a06be38af022b94821cc55e4390574b1a1be84377e0dd7f6a34b47c41a15446ea91995de5495043ca6a51174e28d30476cc3f65b7da1c9c10e7996ae81fd8ac843a03f54eb820a5d7ca81a4637c3f089321d69fc20ff7d624a47f87f08b11bf7e09d92a3dea19a6dbe360877aa3471ad49d434cfc1620d010001	\\x77625dc720d8cc2a123c6be5e477c083170bb56265c90f3dc35d68ab6104edc833f7758e5562ed2aa0aa2f276e609c42512a27433a9a72b7197aebb93e5d0a07	1668512989000000	1669117789000000	1732189789000000	1826797789000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
30	\\x44848ebdd494c89120f68667f39ac017fba65f153a21f658a0af35d19d35f994dd9a74b35c5a7a5a6e2dbfc8cc56385961bc06da213fe08ca6ab4d209557baa3	1	0	\\x000000010000000000800003cfb0c7baf5d6b445757b98aedb3c74cbd5cb08f71d4edaf09de8f7b5cbf55b73aab9b0882d8451aee6f3146189e035d587a44f869ae45c3dd6e7fa3843cf9d53430c4b97eb06bae8a08afc02e6aaee628218c0c45e65a5b4e2d463f573fe3f19d26ac3d2de0e250065afe6591c2a84381c5f9f90bf4af3c14becd88e41f94207010001	\\x8f31a5ac3579149ed4ca75d18c523a5b8d4d9d45c45f84602a1d7aecd2e0cb7d1578e26521e029bdb8d709ee2d4739a5bbab57b70ca0530468eceba1da0f5804	1681811989000000	1682416789000000	1745488789000000	1840096789000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
31	\\x45d8b8776b1804c3a02a249d8cae851d3150057f0f218388fb59cffa614669e2d1e811a99ec81e16a97c0f0d93eb17f6d1c1a4f5a65633b8d3ddf9db267b2cbb	1	0	\\x000000010000000000800003ac4cf88da530fe076f35d2dc4c6395500a7c1b7b9c7b34c5439589cf3e3d947f9144c90ff3ce72a5ce3516ac49aad1ce99c75b35731838d4a3ea1dc1b95a6e30180a3d909f7cd666c0892446c49f61583bbf637a74b253065f08817575e38aaf1798db5ed88d98973ca9b0c8184411c0f1b3f7fb0d71759e7efb864e36979643010001	\\x66cb4a8947e17f709131c8ab68e3dab00e547bab32d43249781480d22b8ab7c27e883b77e3f74cc704859cd73b77a06944f2b1f9febc8f89ee0e83a37b21a401	1687252489000000	1687857289000000	1750929289000000	1845537289000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
32	\\x46c0f55c6962f8df01fada202b99c197cbbfc78526b888020b4a7aed9fa17edde5c153f6e49e716e1ffafef1ea0d752dad5ca07340116e7debbcab7d8099f354	1	0	\\x000000010000000000800003a344b7d78c040172a852de315f94dfc6028c5b66857c0ef1ea59b966cd713bc6cd19239f3ed161f16a52353a27fde160a4f4dc539fd1951cc4633c6dd05ee5a464b4e90395db80d01aa8c6fbae2015dd777b32821636fdbff6d7d27d343241730ec134e87928b9b29db04aee55d7a3ac2031a4b7f5786bd90c58aec0ce1f08c3010001	\\xb89d97172362e291aecbf6bb61902df352abb2d7077b340d7d27c86b7fca37b109d2b28335876923f103f38aa86fe58f68d5f6f8ce4f6613c0c5341cfd97a807	1672139989000000	1672744789000000	1735816789000000	1830424789000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
33	\\x47c069716cb002cae0a4790c9522bf5c5b3fe0aa565e6a0ed85b2190923e2c5ec3545973d1c94a0134d879717205b5b0be99884ba9821dd93aeca31153947866	1	0	\\x000000010000000000800003ec334267fb41505e3ee1bd81cb5c5064768881cc3d7de91ab5a9b62c591eab3f1c9ba0d5435e4dfe0bbf678a0ae7c21d66709b925376b78be42702708fe48575254d5764e439274a06a0be4e4786c0cf7deaa53771ad6862c90a2261ce2f8c4f993b4253a393aa38c7140323283d06407d9e8644df44654dfd5ce529a858abed010001	\\xd83bff9a5ad3ce348165d3a2a504d5a2cfcacf9920bdb8a18fdb04ef31a33d07a5fd9bea0f6f64006243c6af460460e83015136446da9cf926a1f0b0f2e9ae0e	1662467989000000	1663072789000000	1726144789000000	1820752789000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
34	\\x487c76b6af732fd34a0589304964ccf5016df78441ad9fe2bd7d9fa9d0dee01ae88e5e31b1cb56554d75c263049423d5a5939d9ed6006fd41ee43b443441dad2	1	0	\\x000000010000000000800003b9c31d8f72976fcfcf549d3fcc5f75fa07174eb70fcbcc7123fab1191d3e11a6a58168907874d5ab9fe7930e98abe140d45ef7441e69c5813eb93f1bd4efd85c718bd9bc0fa0d5dbfe467146cdbde07bbdab87ec47fd321ba7b1e2ee0b2d8b8260fea5719494467f52697f790df53966bb0b62398a6c63b8991c7c575098f759010001	\\x7a898f9a95790eb12d2ca69e9ec33b58475b1c19e7d54481bf71a96070953a92eb2766527ff806e6583375110863f3ca545230179e3aeed2a80eaa3d94e9b401	1672139989000000	1672744789000000	1735816789000000	1830424789000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
35	\\x518cf0d65524719d0eee8856188ca67859590d6ec1b3b7113ae8a0e0b59cc5a75ae1d912acd65553db94ea90f40413d20da0788b13e338063e670f628ef08d18	1	0	\\x000000010000000000800003e34952fd616114f2852826ab5bb847a934d17417da9447836037908b2837b0db534a7aaff3ca298c6cb9df469c6b08a0aa22caff21b77631a80d27399365da771dc74ca9efaddcf720f71348b94447611ad4d4570a94eb260dcc185a110f7da2a35594090910384e2cfc2f5fffeb47ae02b4dc3082bdd17554ce811f98ee5925010001	\\x6b81cb1bb351107acfcdf9e5d12b9d446b8379bfaba1e40e63da3bdda70feb59fc15172b913d23baa58bb9988dd070a598aa6904c318f54ee4eaff36ab923505	1664885989000000	1665490789000000	1728562789000000	1823170789000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
36	\\x5894e67e1352b388226a0ae1813db9286de57fddac29789edc9bd3dbd0b3cb9fbf4d2ca44edea1c492b475cfb2902b3873f18454ffb408e6be2d553f4d74d361	1	0	\\x000000010000000000800003a9fbcb42a3370cb1596c78a2326ef5fd9e977730e32b1215d109e1400deb8289e1f1b46cfe064b2766ec409f76a2ac53c8f42246f35f24c6b0305ee21edaf5a5d9f06bca260942b7c0ebab0a13b6f341014ba4cf4541f667843fe23ebe16e37cd41d4b876d7a9bc8bc5d353fd653aea73b12c03ca9ea6d78b8af553deeed773d010001	\\x8377f03bfd1aed926fbdf83641cb858d63b9428ad32a9524de4bdda0ac7a8fa7b477be4352fd4046c41912b7cbd8536f18849ee7dec44607b1f45d4ab718840e	1664885989000000	1665490789000000	1728562789000000	1823170789000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
37	\\x5b5443c53abe35d153b3cc3d2e59780be684ec92095a0dde3ac28cc43bbefb67e5a6ac98e02e54edb508de23b3fb71701b33d5864748049007257bc5184d2b67	1	0	\\x000000010000000000800003bf832c79f1a8c484c7bcd400676ffeb700f8819f6fa9bb40733e9e076a4d58588bc3fb4e548a703f7ae766d73ae870fd8ca82b09e113d8dcc1e8ee7df06ca72cebaea1cc9a08d9da03e619c5c54c1ed401350345141e343b43728921f8804acb4c5c5818ec637b097d4492670629da7cb11e31bdd901553a276b24bd721e4d1b010001	\\x857a175558877d65c26af7b135e1e98c0d56974e73d6ab3d1db5a1deec0df23cf0e4cd3bceee011ffb2fd33c6aa110cc2f4afd4c032b63daf97d8d370341fe00	1678789489000000	1679394289000000	1742466289000000	1837074289000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
38	\\x5dece051dc64f651e156eec85effebf35f2b6fbfd60ac6f8433548d8d55c0e3391ff4486126cc39ebaa457ef5e3d560f88ca6426a5068a2e0b908bfccdfab768	1	0	\\x000000010000000000800003b9e0ac46b121f6289f2e82fcd6edf950d56a2f97cbdb2499b4d0f4999798d3fa8915a7931892b37d83acab2a59e420c295f69acb22205b6623408c9aecf40bccc12e888901d76c1bc218f57945df782b47b7c2f890fb3b324f3997b2c616414b7064cd9f17ebd2a1102290919188128fc3953af20a34d32b1f285c55fdd58c25010001	\\xfd996a0957e06eb510daae298814ec56165a29effc65ceab5ba49d1582d65219f5115ab586af9711779dc010e3f98bc274c049ec716ec4f138283d6b72cb7d0f	1670930989000000	1671535789000000	1734607789000000	1829215789000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
39	\\x5ea8b54cd81d002305f1aaae15fe99afa34d94da4577295f9a24060786a89f926f850a747a88407ae6781ff80348659c56330a24d31bfaa48f879d7aefcb35d5	1	0	\\x000000010000000000800003a79a8fda653d832aca7d764be08d3ec2d8837a9d480a4d4cf4a9109ca47f0a711575551c799ef85ceee17079871fc1e72722d016ad68f99c997f8a6b4535fc675f8c46e9cb62de82c8a983dde2711c190cca66f72a8c5a155c3349f1bbbe83b3fb601d908491cd1bb059aa8442dc5bbe3b8e49121796f419d5d3c80c6c95a7b5010001	\\xf25994852bfcdb6850d405fb8c227eda2d0c95a9248c8974e7c87a0f756dc5a519cb67f6b196a304ef32a8a9cf4d5b77a63bc21e08c4232edb207b35fe363007	1680602989000000	1681207789000000	1744279789000000	1838887789000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
40	\\x60447f96ca50becf5a2a3162f9c3db5e23c01a4684c4f0a28011eef545ef8905a37ffa72daee5baae35608356d883b95a5c51710c5e6f8d48fb5e28809e44d63	1	0	\\x000000010000000000800003bf6c99a2f14bf606b8fa3f56e4d6db9454888c11e8316df3ee1d3bec7f632d8a8c13b2ff4b814463d55f460d67276c64dba9bdb714589c9c319cbd70f3ec0c2131ce03a18bb736a3f87b6f0852bcad48263710cde24621d8ea934c384dd5e888ce10f47ce9e9c13c8f95d6cabf5da03401616e765099f572b235303de35177a3010001	\\x14b0ecb85f39af6be94183b8ea481fdeca1b4b8ebddfbf2ff1b726b9d36e57a0682100d05ee2aeaf9b04054b81bfdd785f3a38236f9bfd1b7298aedf84d94f05	1689065989000000	1689670789000000	1752742789000000	1847350789000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
41	\\x60388b9fc5d8cb29647422517f29768d87b9ceb224f96b1a35d2db5707e9b444927c959c4fcf0e0f2c6d7d780d43913b69a9cc0fb4347383d80df19047125ae5	1	0	\\x000000010000000000800003bebe0b49bd2d5d25d4e81ac15de8cd5579678317438ff8e67a1ac3b20f9eaf1078c534ac62712b40314a0584f43c1152890121fe42504c93b99d4f0937249c24b3309fe320c145d3cb43c0fafb8ca0894b93388d57c67321ba081e114a06ef939c72d2e6188befc6900a9c1cfac0f2e70d8298cc0bd681b6ea4feb1b5eb09d9f010001	\\x1680bf8a65db693ab54b83e6aa8a597f0a0a55906647e11aff46dfb82a9fa076689f6152c52c7a558a117249e9e375befb99c24dfbbd9ea736c87f465ad8e801	1663072489000000	1663677289000000	1726749289000000	1821357289000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
42	\\x6254f4f91abbfeaf6885c8c7ba3874a086f68c30fed583b7f663c137c6860b9beacc2dcf82d8582a5dc49ee023fc0fca0bf7e4c07ec51b54142ec873c97382fb	1	0	\\x000000010000000000800003c8ea80e170d436f1250794ad78a5c94f2000dccb04a1116669331a5382f0f2b385e83667b91f04027a090a972397c15fe4ec60b88af8dc2d6951438c320298f393532f58732517fedd7ced428df706813fd66b1e5a6b4417a0aa085bd28b85618919c21a73e59be1875696c7e755f76b421f46d4fa9b6607d3848e10a10cbb41010001	\\x343779b88291cafbd3857fe3d758d4a002e96e910d3b431997a9447916184ce42186de906bfe13bfc3d8063c3edf4f0e22d9fb159197b13b0110fc21f0aa850b	1683625489000000	1684230289000000	1747302289000000	1841910289000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
43	\\x6328e49bafd3986f02dffdcdb806c804e1e4bc8114604149e44230a8c8f2d4d0354eda6f3e253b7ca5789eab5b64b3acda02fc4e7f2b8c7267336acd92230329	1	0	\\x000000010000000000800003b308ef716bd60db2623f48e3dd2d8861c536dbe15b084604e95d0970a0dc6d308d14e4e31b71e065330a5f039b40d2b2c085d1323d93c23e0efb8408214a956e091b0af8ccd1ac5a04ef5257e28830db8e4ce14cbe5debf58c7b55277c75f6a6c31aa66431472c40cab2380bf38cf066a91d6bd9466aa2d5e8b8230c6edd15cb010001	\\x62678106debb39b8451598c48b77cf12e6cbd0ecf56201996031d126bb85377caaca4467ab3034f3b39560081d38b1dca6ccdf3a5bc21d5f4d2e3df0e6973b0b	1668512989000000	1669117789000000	1732189789000000	1826797789000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
44	\\x64e074d42b76c8cf300c1c02e8ca01ef2af6f96eb871b9a92d738c83a42e072d45c9b1c4a0a7644ffa0638b83636b0cec7b5b8b96412ca411186a8ec49f0503a	1	0	\\x000000010000000000800003affbdcaae40aea5f53c5790e6528b89b998a27396e11b2af3a5525984a65a067b9b163ae8ddfc346868b6310bee0ef58250023174bf5385326227e7605330e6d6b02ffc1ec81d597d646944c29dc053704011cc213522cc3f7e1a5bb02af06f0852b0d02f462b8af62102f5e988eb4d68a5de02d9860a2ac980910ea0fc5e02f010001	\\x6f62f495c792f7eec269c0e0c831c1fbd7a027cc81ea6cf7ebcf331d4fb5ee3c7de5ff62533f82bea2a23d7e9debddcca6605bcaf5e891d33df9caebfdf9ea0d	1682416489000000	1683021289000000	1746093289000000	1840701289000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
45	\\x64845e35095a3916de75baffcf00ad73fa842ce321ee86128f16e6cc17abe76ba32c69dfd2e168fbbc565f2a9261c43875646ea3f47e0ee4de9b8d7e0ab763d0	1	0	\\x000000010000000000800003be48f3b49fb21be31a5a5ced731bed6f824b2b2be95a16fd273472cfe719957334242242eb7eefcedf16b34af1553c59ad4a6e56202dd3a0aba97ad601d3df28e92f5104c0eb6a853f2a20e5276fb88abf33ac8d8352dcf257d4f0f28159a59a387c23962851f282b426375d8ffaf34fe84e33bfb5b45b16cd84333335219917010001	\\xf599ee4b5f10de625810bf973882120496eaca769e8af3a01ed33eb2517de3aad1e672eda7cecff0610729158a07ace4cb5325ecfb2d50669d8b2e7e443c0208	1661258989000000	1661863789000000	1724935789000000	1819543789000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
46	\\x65304b98169884b714c74f2e147024118a2f8dc7128ef3420aca179fecc7b174b89796adc20fbcc88962018eb1256fcf7c346b8ebe5ee33921599cffb3a011e2	1	0	\\x000000010000000000800003e3cea7eca1778ee67fa3dfd9d8d9476a925b21f63a8dd2631860a9f8781b53b1d65f507682325f3802e98d43f4ffa704ab40e4e77413f909b44580724586822c2dfdb40cf5c06ed3f5b496575ef57d3e43e84565c768fd5a812bd4af4ce60a136b9dbff93210e2887cb0cf60dceea45a09792e69944b6a6c571bfcbb5f5151ed010001	\\xad889120d62c487aa872ab6ac8878927e25a24a1fac63b470b78ef48f58d6de954b42ee86a8c753f37448dd174af7575027eee4fb2a0309fa7b21bd7954bfa09	1684229989000000	1684834789000000	1747906789000000	1842514789000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
47	\\x6624fce8b7259ad7808a1fe0fafbb9ad80b2e5673b8f8f5da3038d7baf39917de06f9a7ba424cca26a07dcf80645f19043f827d0e49a945725bd334e9802779b	1	0	\\x000000010000000000800003ada6de6ed5456d916f4f4b16ccc17f658d4454445a670e21f56087dbb80a6ea4ff61f10647c7dbd308b7bbc8c78c2b64ae405b1d74b21dd624e21f64788bfeb911830b9cee89d9092e203afe21db6a3b81c18d88f5a7cf4f395822be20e3df24429f7befea66ecfaba4fc926147e88864ea81bbb5b376f98e73f1ad581f89c9d010001	\\x37a094d95e3cb96f1657efc8221559f319956eca8cce52441f57f029872dbfe69edc91f8eac828c90f1117940c1436616d82effeb50d718491622d7394682409	1673953489000000	1674558289000000	1737630289000000	1832238289000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
48	\\x687893c60273c2d11ea5e35893ba1c9548810d542c4f021f5dc162cebf74d3f38ce9029048a2e89479b8338e1ede1d2f8782a0b96764abc5130790b106d4b413	1	0	\\x000000010000000000800003b7b65dfe949f2db635c3f66de7b670b003da53ac7e309ddd7d0051c7834fc62ef517421fea079f893a0a6be68de82052e182de9cafa52f0dcff8b0f9c8e2b4bc58992f053e20150247d29c76ed3154141dca060e1d78d2ef98e7cd9796e0e55c2ac9eaf14791408036dfda0da237fea93a24b139438e39cef801bcc0ef6b21dd010001	\\x652a8dd86bf49afa2d7e502ebee71e399e6afa5e6c7ffd4868b24860b5497e14b9ee212e85d50939d5eb4523a88fd9bd3c037249fc3b1c95e44948fb3fcff60e	1682416489000000	1683021289000000	1746093289000000	1840701289000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
49	\\x69040c899f056127c3ce94480e61bd489f4ab2b6a989dffd2c0d51dd3290f740d8e25602cee611c623dc623248e5a02b7154fa790816465ba2e68c2c57985f8d	1	0	\\x000000010000000000800003de7d358ae856d42e239105cdccc1bae18722ef2a0f9c8bc1fa5e23f4f0e0c983ba7a2d325ca144fd5402632b7c375e80f68717aa824a07144f3b358893a333ee0990c11969e00ec702d319654d3356a074b3c5f5fab5e5190d4403ab6533a276c75b97dc37de5b0c3b249ce2c09c863b9b1a4e4d5bf37f612728e78af5a2e4a7010001	\\x8daeff80b4f62067af0e41960456f14d83b41131606666b23a7d47b7c4bd67e8f996ddc429a0fa83f601fc012f5e8ea8d74c6df921d358b2c29613ef329e7c00	1689065989000000	1689670789000000	1752742789000000	1847350789000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
50	\\x69f8bf41c3e02335c9d88588cda8e3bec8d42c5089f86d5c8a21de368e852285b5d42b12cb1804b23881eae6598f3912c65d6622c107d677591b210421351d59	1	0	\\x000000010000000000800003e89b7efd9c476a2481fb4d21bd5c38a2fe1fffc0c32cd6eeef86a5db5c81f1bc3321e67ccc3bbd1980a3af2b27f864fd866d07cf2638be37fb1e70df878c163896340b951fe3cb1588d8162e38b6d22cbf3ca92ee325b98a46f62dd6d7179852af6f341b23a06a484b45b2e5a6ac1d900e816d5402044a3cdfc792bcdfed227b010001	\\x115308ea4cd1556ae7e2cdfd96a092095908a8d96fbd292e42f5949bf02ebb524325962ca15697f8185e83cb1f743f6297ae56d32f0172f6436c90285b3b1b02	1663676989000000	1664281789000000	1727353789000000	1821961789000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
51	\\x6aecd7f555725d078e889013bba5b0c571e6f87c02676f8a321c3d12e5b409f3bf0c223fd00388ec9a8662dd000d384022158208153f3cd7555b97093fd374d4	1	0	\\x000000010000000000800003b6dff1063f401d8b9303f5d5554e2db8b7994380b5871a45aa27b4bed87c78eb1cdcaef95e5334838bc39f3b1334fee1e4e4fb238dbd6329dec16054fdece50e4941c519552ac781b1b70f5bf08c36cc1257f042a3383e9e097c7ba9a275b6c27a890efdc5fd7b07e983262241aae4f7bffce177585f46d40b12a10e8994a777010001	\\xb29dcbf9fa643be460f7a26a5423d38632e84035595b6aa2b941002662742334afdefd4813f727b67aea2e73e844178f1a888f88c724cd5747ec0ff470b97601	1661863489000000	1662468289000000	1725540289000000	1820148289000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
52	\\x6cb05ec1305ec2ad488794f5faad976df5923f061e99eec7917db82721eb1f1ad83c2fdc52b8cbc75e5ecd9bea67d737df363dc2f06c8ef241238be0e7564b49	1	0	\\x0000000100000000008000039c43cc825b89a86fdeedebe784fb0c6cafbd3fb4691e2c407445a10fbcaaad9b06402d896fe0b5082d997b4244789c2a0f44c47d4a041c84245c9c9c5474a937a0b7662611141ea3082d4dbb52c0834fa3a43d78f7a1b5f7a3ea7ca47ecba7fd7ebf74c3b3345b86ed1e3ebb4ad7fe249752b7861fc6f118ebaaae04d66d4441010001	\\x5f59f2108538e7ef97b9b52ddb8595b36cb6a70f23a3be2121d5a31996be498842c15b6b4251d37e44e664c624ae6d3fea0976e0c98b2813166b360390a9a109	1678184989000000	1678789789000000	1741861789000000	1836469789000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
53	\\x6e5c7edb65cee56787e405cf5358915435844aa0abf3675b23c208de82ed1c22ba6c7ae0c27a5c8d19679c7cf27c8745ddd6e5b6a5b4a2ce4d09884c92739ac0	1	0	\\x000000010000000000800003b7236d920efae147a95d2910f564609766a3a599efc98a7a49751bd87078cd71849c8d243ea18181b4aa15d7a0ca8437424b0b638fd999967816fe3a3915931702c64af539c61cb483568382f238c2cb6ca19c4d64e976ca8314e29081548669ce211277e44ff3001ab8b35dd8242810a390406b11a72874c744f4d1ca6815b5010001	\\x2e0654b65f1ae9b91f743e434fc1889e26b77c57efcbc416e05646460400105a75117a7f4ac11f56aa8d80265f59e73bcf0cf5e31ec24db0d052befe1bc71902	1692088489000000	1692693289000000	1755765289000000	1850373289000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
54	\\x73f8ee4097b366bd67817ffedb181019409a77fd2c99d6468877fe9058128de336122f0ea1435ff245100c51d60557be6fc72f80f935a073e601e26b1ec6f703	1	0	\\x000000010000000000800003e8617a4c785bed0931526951337b5a42e5cd9a4c0b51696d349a3adbd59354995988573306789366c04bdec18874b2317f1a331f30e0a294bb5cfe99dfeace6583eb85349b44f35c16b7f3186a0d22db04e1b2549cb84a25e0779f0085ad361d6bd05253d14e58c08a7d34a83168d6a30e2f479e938cfb800711ceffefa6777b010001	\\x94daba5092637f59069014b567843ccf55f942f0d3b282e8c76e082c960ee3ef021916b763fd9ca0955cd79118d8a86f16829c539f7f2ded8deb25be2d0fa500	1690274989000000	1690879789000000	1753951789000000	1848559789000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
55	\\x7750c75ef75cbf40ef25efa7bcf7f3002c62f557c939f26e8daa20ebb628c767b0ff684d47e2bf82bc46bde55fda137586209fbdc3dbd1ccff36be5280c2ea0b	1	0	\\x000000010000000000800003c94388cd2fcc21467e2a25d67f30c34e1c5fdeaf22b3dd412edd192904bcdf66712b2440c12d4280350f1a10d2d2f0103534a7a1d65fa56ffdc2e052fbed99f4e45af9cb1f1e50cc19690fe4d1db5ee196a266be20d00623a885f173c2c503d4c9fb107350e7a2dfd3f17c36dc25278e8c36a732e11f749cbffcf1e2b8285287010001	\\x3d32d12b9c92403001a32db9639e88d1e904f9d420b2725afa0fb41414ef67ee434789c53f2394b3f81cf96e6d1e69359a5c5bb2baca13d74c3f74c4631c140f	1665490489000000	1666095289000000	1729167289000000	1823775289000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
56	\\x7714d4ce3b1bb9117ffcef1c93a316aa0588298cf012beb4faccc1c3c75645244c1a7f1f608ca045dadb90c4c6e5bd4a0ece75f2a9fd5027c6197fb777c8abe5	1	0	\\x000000010000000000800003d5fd4735d7432a2f8327360e0649a802c80be119c42262701b41e26d887565deb2a992f740f53dc81c3e11bf34091c4f53e0889cb69c7807966994cabc25d8b67e5e378464e2b4115aa0ab83d2d439a6bccbf4f50179e8f9627234da0e4e1e6196c805a1ed7614aa5108027733a181d1071450bd31b2228a4b8d73cf6fab82e3010001	\\x36bfcaefaee8e27a0b847614eda49f4a3c8631bddeda059fdcfc261df5fcfc8f9a084f8181fc5ff7b4d1fcdab5220df59f1b4e670892e5bbe3763fe8a593a002	1674557989000000	1675162789000000	1738234789000000	1832842789000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
57	\\x789470f487bea612d30eb89451401802386ca52a15f2662d5b401bda120a917d9bc99304aa3c30fcc2e454a4812832c767f11e72558f21ca75b7bc5c64cf12e4	1	0	\\x000000010000000000800003b804c1ab6bfc74e6b3c84cba8ad6ab9234fe80d7d12a3fce1e29c049fe10fe7c869ef724b1258c841aeee13cfc0dd3721eea87db6345ebb5345cbbf1887e839663aacf9f7702acee5e2bb5dd44c5df40772d713d768c0ad2d83642bcd8db68d5b729dc428173eabcfe0850c909dbd458ab20cc5d7d4521e96ae366f4dca9c6a7010001	\\xe836fc2afe40350538f0ad818a5040b3159d863ee39312e7d864dac4c0e1e594df1045f0b952c33fabbbe05a740ec6184d4655a9988d8073cbfdbcaf7cd88605	1670326489000000	1670931289000000	1734003289000000	1828611289000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
58	\\x79f4b9f8a78ad8c481074d465edfc702b8a0e2a0ecf9cc516d3f41d8862a7e86025747b68858c3f2b43c4bfb4557295f27bf95c23d9cdc692aaa29e8ac82e8e1	1	0	\\x000000010000000000800003c84b25d5bfd0ee68c3f299cf43945ed53b0b57d63006324e8fd914fc82ae45ec59ef7aeaf026e50b27073585d4a6bd9f071e88009f40bfc823c75edbb4d01b0ab6fd9673936695430d2af5e75495af696cfba4c7661658aa36d575f07f85355cdf4f1b4b94b56d87bd4f25fc8a12820853b862bbad83a58f4e7c23c7d89e28b3010001	\\xdfda524e64672ee68339612e78d6de9a13601daaf449f5e57fa8856f76431bf675faaa4ee6db992df750234c505ba9688b54fe84ce9b1765d761127e5a8f430b	1687856989000000	1688461789000000	1751533789000000	1846141789000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
59	\\x7b04fc81ef60359d631ce438f1300708f4ede1936fdd556cbfd75f3d07ad95f25c5688654b9b00a8e64fc39ea6560d7262edfa2766f7522b9beea6e2d37b10bf	1	0	\\x000000010000000000800003d2ef221728fe9244685f57f39c612d12b847469aad2964ecf7d0ff20c3d1340ef931bbec4fa61dd6f31be65190883efc2d9ea51f62c4fb2c115e259b4579b69c9ab8acd5001cb3e6fae09341b9e1d5cfe6c832f86b281e977cb63a56e14a5aafe2a12fb3be2ded625d39cd257800363be9b088e2afc121c5cc2b73c2bccfb98b010001	\\xe6d97bed0709306d32147066951633b66501204ebdc0c2f52b40c72ae971ae71dad691378a857670373d3bd197bb8250d1c0093be91426080c57fd520f8ddc0a	1683625489000000	1684230289000000	1747302289000000	1841910289000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
60	\\x7bd030363390d78a03c5a3f2906a922b9c66fbba3dc0de8b01dff5c45af7751cc74be430fbb62b0182adb3e9c594c2b7499767e0219b4fa6f574f90f823d8988	1	0	\\x000000010000000000800003ae02189b011b389944f5f726d3cfdd749c700062be9b4059f3194f770d28453281241e8cd5b2cb495dd6b6b043222f996ad243d0ee9088e78ddb2d4366c8341e83ac8ad6c4a992e453ee002c5acccb33bcd6b6461d66f812486f25b1478361236902a60940d7154b823d5946cfd6fbac15d07b30931d685d0ae377575aafb87d010001	\\xc625418e483a0edd12f566d1ffbdd74d095e71396cd8b88f48c3cab2122930fcad3b855e42bb3acd79beef5aaa7c8acb97ad9e2a25bd8bf4c24b83eae126aa02	1691483989000000	1692088789000000	1755160789000000	1849768789000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
61	\\x7d1c5b1ad8dac9be4a79be5eebdea5ef81f1f0e1e6085f0f371c9926fea7e55cd4c0408b1d7cba3f7d8e1a8d2db447b37f6fe802c0e37d1280e1a4a834ab0c2e	1	0	\\x000000010000000000800003dc0087be316faa7a5914633f03c239509d2117f2688e35a4643af001a50434f13313902a2090ae756ab874717fc7fa184bf5843e6a33bafc70b7cc03b936c56e490fcd627d87586d0479ef5c5a5affbe88b6f8bdb20f39e805481d40ceb1663db5d4c7d6efabc653ff0944b4481943ed82bcda03b097c79d27a4559b62e81a0d010001	\\xf93d6dec103a2f5c86c2388cdbab13ca69597696f6de8653d20a3e9c400ecb6c3422943ec569dd0ed5ad4d2c63216966a6ca649be75fcb12fc896a772dee1b03	1678789489000000	1679394289000000	1742466289000000	1837074289000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
62	\\x7d309e16df33d7f6f3b1a12e12c21bed5156be95f70e07af9314866e05b307391a75aa4c9aaaa959d44581dccc31be3861b70773e259ffdf37fe903268379192	1	0	\\x000000010000000000800003caf92544523bb201a86ec4c9ca4cd2b2e4c4a3852c5066722f48848d759bf59803be7d6211478319812324acffb30c232a56b5a5c4042f72d0aa6979505e9be43617f3b532d3d7fbf4976068386db25a41b7aa0b21ea8ffebe92e73c6e38c2acd793850aecfc2b9331591e94f1a81cd8162a3c84b0ad4aced85c847b6a036317010001	\\x7fbfdd53c4735c251f7c2836fdd3f22b233588253e2e7766a0e674e13b1d8bd83d7bbad9a515f8761d53e1ac82ddfa80644450d6f634b859bfc0e5ee1e66b809	1669721989000000	1670326789000000	1733398789000000	1828006789000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
63	\\x8168d47bdc02f8e5672ce16ebcab4784789e563a2f86c42a34b323c9f1ca960f5169f9a729af453107e33c2872314560c66e2e891a3ea4b039c8672f8a635118	1	0	\\x000000010000000000800003c5fed91cc627e9b2e03ca61fa484866dea704cb91490efa8b724fc6be1ab41b255e68dbdd0dc82e489846c2be31c0127d6d27bc55215058f7e68f7423a85d138a1d1cc90e30fb00263164331e0f935bc54387e1ab353fcbaecf9cfc5ee7de32908613fffb23045a4e6a8e8a15ddc265ca499fbb41272f3364144f6d73c697f9b010001	\\xab0cf7b97354d3c256ef9f48f0a946cfea7713ec44b2e10a62c580c0125d3b4b26ac237c0e8a2a156b4430855ba8baf7b8d57cf0beb16fac81d8bc56a3295403	1683020989000000	1683625789000000	1746697789000000	1841305789000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
64	\\x86781c80b56dde0e7e7fb060457ae27ab0d1cb905e08ab2d9ed2ece45a0af7f750a9740a0f9002065b829038b2aeffe1ff50a4297345768ec8337096453ec37a	1	0	\\x000000010000000000800003de494926c48fd95f10f1a323b788b863dc9802cb39d0d679620641978d4439db41f74989c58e24f8f34cce52ebed52e3546a58ea923042908fd86ef341a5e2d9e092baf3eab692df1b57dae703cb5330c217abf312576daf99c5b55697a30b66a7d75d290cac940d5668b77985f3f714d1484e6b1adcd299c8b6157a4a3fbccd010001	\\x3eb23ceea76416474f47cdda548087d5fa242cf8e5a60880476b1925ccba3d924fb2ddbb4ca5ebc72095b75d20af790da85f30093e9c0f7c357179c4310bb306	1684834489000000	1685439289000000	1748511289000000	1843119289000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
65	\\x884475a340547de5ca8dc4c1df0214ef4cd4bccaf674081b8f373c25aee17929e2c3497791565723020e5c0aca34221c2d2ded6a01bac1370fe06c5932c28d9a	1	0	\\x000000010000000000800003d650c6ade4cb370ca600a95e7233851b32f4169d9c6bc7bd492a9d40927a35e215106159cbef3c4bd382d5a9c2f5e0ee29d58ca4176270a332014aa506c7fadbd82ac979d6272abc27f0903d9607d5c0c1b3bbb18416341a60d7ac1256394f774eebd430f3dfdb03e96364f369c3af88602c7e82678b57d985064f21085cd8ff010001	\\xfe2b98045ce0c5fa5f82fe72653dafbd7dc07d82c2959e1f7f4a455f84ce6ca4e8b14442e2e1ba5fd1689fb6b56a5a61cee81009a1d9e3ad71479536d4f2fb05	1667303989000000	1667908789000000	1730980789000000	1825588789000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
66	\\x8c68711d64ad365a81539d33cdd71e50963553f8bfe4d7208fefadf3f6671f861e95212a197d401c65e11c748471c80a148b1ac1e82cc11f0b55f5ad5401e98e	1	0	\\x000000010000000000800003be2a3f3ca8fe4894148e1872aa07a3dee3f3cc2a5647ff152a6a37cf6f445547f5bae0a4c7646a5adf3c346319da16f498f9bdfe9662f52d49b7e0b5e8af5581f58b9b12c0960b8c756b9e444b1225c5949168689bb998d0aa275bd01b33df3c9ac7500da66f4a8097dcb60ca9b53a9a0c22ca42eb7f812448b700b39b016999010001	\\x0dda8ae946ae0f80682587bdc2845a8d0c8a7141f5500d6301110d9ff379652529b36061c50646490397cf527adfbdec4e4a5bbc7d70a04548f453cce644ad00	1674557989000000	1675162789000000	1738234789000000	1832842789000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
67	\\x8c08bd737db52cb4fe263fbb085f1f7d9ee7203511aa4f8f095f6c1f28c378a35073c37cd4f514e12239ea4b713666d15ff6826e43e8f44bb16622dfa67e773f	1	0	\\x000000010000000000800003b395287abb99d4148f05be1517ac9e5daf27f3ff9a82af5b2567088cffa211fc28c32b3f7b3821276fe46b3b57d6abf7b70ef585a7ffcdbbc2c9f142dc26c5c4d4d23e703b81b65792c2a06ebe6bd377d38091b639698dc9218aa936ab9d3fd5b2711d696fcb4770c8b4c2e7354fdc39e3ca70d4aff2ff1800c7145bf8510a99010001	\\x107ab7bf86932b8138530f3587a2af614b4088bd4fd40e4e1d6be62cb57e34c4206955db7d119c5cd03cac902cc15c194e597f24b41d1bc0dc2aafbc20271c04	1670930989000000	1671535789000000	1734607789000000	1829215789000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
68	\\x986000cff56586a07ffadfb76e5b58cb115e783acdf7d4f3e397addf460262f48c805bd8cf52d2df998fed180ba7b7cf62855ee5abe452d97e0e38bb2c9adcc0	1	0	\\x000000010000000000800003effeb7c61ac24027caea63ae579ce913c3842a7f7c3ae00fc4c172d9caa6e47a221f1523ad65fcebade5d579dcff285b73a29f587daf1e99ada0d37723fa65912bf5d23e6b5f85c47df7128bad364bbec3976ddc55d6e881dc6a020a7031f54e2ad82a38c6cb444f2451e25458a23c143b946fc73eeab83227b5d68a97a2b621010001	\\x617a253c6a9ce566f9d36d06838062e4483db5cee9068e7856c3d7ec15782c9c47fcec7247ea89929d11aa444270402fa5eaf26c9241ea7a15fd2e0b81f29805	1661863489000000	1662468289000000	1725540289000000	1820148289000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
69	\\x9e4cfe072cdab40c22811ff5635354dbbea5301dc73063bf8c5172b9c5c7e169412c94a23177d2c5ae82cf512d174e5e9f78e65e2336e94bf417285fdb4e06e9	1	0	\\x000000010000000000800003bb99232a721e7a342b4458e6d73065978a12c6acc9af84ab5b50446c347fb6d8b3e73fc1674732d745d127e077f4cd55f8a77a520be62e37a46db7e66e1b03ad128d17a6c5fc81edba7dcad9009a1fe0a9b156488e7efd1d48fec502494bd75fd037eb68e1b14077de536b8f2e79df268075e12587bbfdbb0e522c7f018d13a3010001	\\xa955fb80a9d87bbee226c52ad9dcf3295f7987c8eac597802b16ed38d0d2955856400d1a919e6872f800150cbbb7e6c1bd57d499ffc095bb61b272e8b2203304	1663072489000000	1663677289000000	1726749289000000	1821357289000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
70	\\xa27854c1eb0fef36dfdf8b1079efe00d7a8ef83a8d85b41a8041869aee1295dec66e28cac30736c8bbad4c716db5ee5e55bbfa9bfcc67e366f507318c00f2b94	1	0	\\x000000010000000000800003e964bc454d00b14f5a52c5a1bcbb7d3f6513e3750cab2d3ecfd7bbe8e5760d4c32b1e8468473e96f48b16dfa98a11d7ab1c3ecffb5c9e534594cb76bea6165910c2f3c78ab2739fd6e30223030d82f268133a8c27c4280f972467de5125e2df97aeb3931a161e178e588284284b660eab965e7a4882db4f16f2bcf2922a92779010001	\\xfb70687491bf3c1f3fb9a5867a16efaf3e7421c8c9ef4dc6787a4fb9dd20433691dd767cc5a0d5a32e51dfc5b8094df1b709f2d606815d983ad53ffd20c9b40c	1660654489000000	1661259289000000	1724331289000000	1818939289000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
71	\\xa2584c191368887b1328d32459ccdabb36b8e6b3dcc1c6bd0b6dfd3ed5154995fd9aeb0a24dd30c27eba59e2a4eb4b66aedb251856b278f1994f837789520903	1	0	\\x000000010000000000800003c7fb26567e6717bc5bd324ab903a84d6462708692a36d065ddaf4deff6ca8cf82a66e6c2effa54cf7a5c2fdd54d7e947a799874d85607959f441eb53534de2e93052bdba4096ed5e39701b1ef45871aff6c6da2037171b7188d5daa58fb6cb72b87afe3a5a4f64bac084c4226c71d6173e6196871d505a42de22800539c74ad3010001	\\xd5dc66a509fedc9b80acc7961fa0d2db212d21b3954e3758905dbdc7798661d8234763bb8121644040a256889c74972a3375c4680fb40d4bd3c7db1c16c32404	1661258989000000	1661863789000000	1724935789000000	1819543789000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
72	\\xa744edb264643da72255f9833a3377b78429231dbf3dbd33d433f2bc02f1580abf9094556d6755de21fd6531d377d2b685713587677d2852ce0dde5a73a5a615	1	0	\\x000000010000000000800003cf7a2de70fa5b1a44f63d50efe9b97ba39d31925207b2f7deaf6643ebe6901e6d4dad6e9e3d3106a0640254406f8ebd37c97b092257586c7226707c1341725492add5414b6c3378ef58bbe73f05197b428fd7cd593523601d2f63213ffcd6be7d28ab6aa1dc9b12554d7c5aa783399ab0f2231ec259a97fec32102fb04e11a9f010001	\\xe7a91918fb2d669f49e3dee094645890149c56c4a4a454000180a65c3a361c9266a1b2c94cc9e9c54dfbfe4b413851554bf0a7aea1519b98db62e636094f2f00	1670930989000000	1671535789000000	1734607789000000	1829215789000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
73	\\xaf9cbaf5119640227296a865a5cad37b364d44cf9576f932cbd9f247977ba570cdc7eac327bd5dd104096707e54a976d8579bfb902e421e1553a59172524e0e8	1	0	\\x000000010000000000800003f01a31ea6ef206ba8472075c05110f66a3839d1ed93c4b4142c9b067704ed7954b3b75199526053f19c1da8833c9a5468a50da77aa286bb49d16fd02a6ec363c280f4a6f92b2ab86538ebd8f016844ef0f4615d4fd64abc3daf32134eac2b82b2353bcabf43451acca66ea5b849033ac20945426cc8150b245307c03fe65b333010001	\\x7f0abc524cb4cff9ae7d9f83126f874624e23ab008301de6f381f23c2e6d32d5c2cf6fd75126420819936f354d5131e22ffb3f41ea7e520313b90581bf05e800	1692088489000000	1692693289000000	1755765289000000	1850373289000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
74	\\xb10c9413d230a2d3429d8e3598017f312d229b552f4ff0989b90dadfe4d8982d60b8453960b4d307698582ade6b15de9a469ad7d58fbe4ba1a4969d1a7a45491	1	0	\\x0000000100000000008000039a21a9729211b6a254683cd5bc0d8a27074c837aa43804f19ee3ed3aa21c946606ab9250452fad17d988467cfd91ac479c0ad7026454a50fb34ed4203479e891098a1e28e06722b19406a66c1ad06761730e80ff232d268e69c425368876b976fe2f4ab0d0e0a91e5d7fa17582f5121e803e396163127253fb38abda70ac572f010001	\\x939bdab968609e1fb1894feec28eb1c12d02598726a0b80dabc5aa41de28477b33edba1e278e31f96f4a86d9735b36cdd6fb5f94b970735ea8c7b4259bbf750e	1676975989000000	1677580789000000	1740652789000000	1835260789000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
75	\\xb698c42d060ae7b02cbc7f4e07790adca61bec33d5938e664eb422c3493158d994898a7c9b5742c463b681a2666e13dd95be730e0005750024ca04f9df1c9c00	1	0	\\x000000010000000000800003df63d8aac4fb5bf5583ed9e6db4ae7719d983b0bcad63c5fc6e543cfee7da1c34f4395e8a2f0d5526b1155f79d0a85295e98895955648ddef792d62e25c3e789e76bc747d6152fd8a010595c8cf5e2eb584512ed13243b5fb8ebc195d5c2d2d0de061d6d2d73e66274247bd214a63097baf3d52478eb4d64f8fecce14411b8c1010001	\\x597463c5b8267dac3c5af8a42e67fd5880c18f7ad3c9d06afa6082699b71d05bcb406854f246ecb9b1908c4560874dd87e6035a5833f5743402188023926bd0d	1663676989000000	1664281789000000	1727353789000000	1821961789000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
76	\\xb74c635dd1ec677ee5f56efb8c558199e03636312e7f7a527476a93caf3af0bcaaf99db59e719b0c6f0190fe597ead3bff6b261acf2b097929f6b79b5b9480f2	1	0	\\x000000010000000000800003c491b1b3cfb8fbfd4593a46df2e2be4edbf4a0d3bda6fb933a4ce3b419ff7fa3352167a073c9e21a5279c56ede21d35c4350acd9ff3dcbfc6ba04a8d733dcc17e9abaebc829e8056f863184d15d7f7c36de4b1d69741a61f508c82d38dbf735a4400540b8dbb92395a9650b25cf204ba1068671f90e296f77ceda32b399c1eb1010001	\\xd89e472e04cad086a4c7c8c55aa46e5e06ed2e671d8a4ab198a70aa0833bc4ce839ac5ea8e127a25503a671ddce01b3cc4f9033e9fadd4fcf1debc557888f40b	1666094989000000	1666699789000000	1729771789000000	1824379789000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
77	\\xb7b0f8d8eb21a477cf21038fc724c7f0f68efb383ed4980ced1360d761a17a17c71f0f2d7189fcd3b4e8115fac9aec502955e42ddbfd034fad8b0f88af12f88f	1	0	\\x000000010000000000800003d59059b66f2e458ecace9c4637fd19e7cb244a4ff81ec61f8769abbacd94101dcc67b4093dd8b0fd8bcd39a8bbc643cef9319059110b082300dfbf09f5224877b259e4481b3d0581de43c3ffca4a728d3d39b6f39e3639df53258487c9586ea3c8a1d53eda284abcb864898df59870795c9dc25335ae679c87b34c86e2e6f2d1010001	\\x9123179d0cacc220869d25268e7ea9518e6746d727ca5487891e0857fee7facb83b3bb7e3b24fc6e566cbb2ffb24bda58fe269e0e9211c5b484a06e542d4ea0f	1670326489000000	1670931289000000	1734003289000000	1828611289000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
78	\\xbc90e46fc0148ea9b1c111eabd7b0b370b480f5def539ad4c6a75c7709e83273a83d689549bfe5a0362d82425a543dd15e5e66486bcebba69dd1712bc9a30a2a	1	0	\\x000000010000000000800003b7125628240d63c66657815ddb099f949142f6e0a73874108c41b9e334ed2e9e19e793c9584db3fc49a8e464d7b8dcce3370e90a36898e8dde8ae912c94fc3d54c6b9a38d99aace219203a06dcd3b5455c4e0556f6655e8bd4c435bc9f7935ccdc29fb625f3211bf0a24ec83eb46030b5ca88f0c71af3a841a25167320cdcf2f010001	\\xe06ab53043762eecdd75b7d531e553b4ed273a496afe6914a08df57a4492049f592444b660a4e4f424b994c746a0cbff268355566884acb87fa46b35e8f91b04	1689065989000000	1689670789000000	1752742789000000	1847350789000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
79	\\xbff8825f39835e2eec5c5b80b9a7fce18fef459ecca6785dd41294381160d9bdb89696c66b3ec0c7fb722a3c2b8c12cb3e68ce990cfac5b278a9ce96f61290c9	1	0	\\x000000010000000000800003b65f2d0c12b143911d941088b968a8ca42324d11c8ddf1d52e7135e431bccb430eb27c5ba2ccc77bcf6fd63b01c6992e54806272f4397c6cf7c86be6496444a62150aea0d7939278b65ba301bf484e3e57ebbdd4e69ac15398ed9d60e74c129159a2a17be1ce45e536f0808cc72b5f5ec2be78e933813e3b9a505f65316f67ad010001	\\x3c39ec6e06b472b259613f2a582aae2ba6c4c4cf0e83df626e822699ab7b7385e566419c89d0d9ab1abb6d4ed7724b1f4fc227e488d0ab96ee46a3f970afc006	1690879489000000	1691484289000000	1754556289000000	1849164289000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
80	\\xc6b44fb0222e0bbc6b2d65045cb9fc304b83458ad1d09f7a5433564bc7a587697f8ae1f67b6be16a01e0b5b7285fb67b11ddaf70bc0a959dfc39894b1c316674	1	0	\\x000000010000000000800003d02a660d0140e2383f9cadb7f2da09ff18471823616c4de290ad618bba33ea63afd58e46d71805c128af550eb9569d74deeb4ada61df029eef57ea18d984e4fa53ea929bba7012843e26349e34a66369b3bbdd149ec8040f8c7b140a652d467a0aabe9839b4af57ad525e2d228739227937ba43bf5b76f02200de7ee4ca2e9dd010001	\\xf417c6a45d9c8500ac13d5fee0cf22aa82fedd50eb981150364c2bfa733be49d603b710f29702bb101ea7a2424bd7b6c6ce0a28ec51ce25e5d432ed2f7ee3c08	1682416489000000	1683021289000000	1746093289000000	1840701289000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
81	\\xc920ae42a2b524095d0802330368e04134f33ea0e07755ec5f2f0a69a39d3d4657a9a34845412390dd8b36d5df8ad3c9e7e5bae17b5156b862c2e291b3734180	1	0	\\x000000010000000000800003a0aabd6c1b897b7708c728c3ac358320ff97382aab6e355bbe6f54279efe1bbf481a8d87a8b4b2ddf6aafc9bc78a09c478b24fafd51013cbc52296661dfc8be426daf47cfa9ea2b1ac355868e8ccfd5020744aa94fdc68d130c7ad93b65b54b6b60f90250bb5cfa5fc6a32ef8b8028655a5c0b5376f4f1b02279cea2410a5179010001	\\x2d60f67fe3c6ff43617462779e644d3da2f02f1520ab857900badfed3f82a0c0615f0c28d1c71f96c499e26190bc9322bf75bb95d96a937e3e8fe4896a13630c	1683020989000000	1683625789000000	1746697789000000	1841305789000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
82	\\xcc0460a7612d410f475a5e0f67f87c56b80844d74d4fcfc3b306576927a29bea378c1a763e993bf821f131adeac1cd9045817920858203e900f134a2fab269d2	1	0	\\x000000010000000000800003e303da977dd4d7c2fd43f1651178d30f4cfddc3eb361d669cf88bb94e19dc56575bbbb48478ea2c0d9aa2e5e75311713398244f8d9f09f75de4367a20b5e471f9235457d02d8e50c1db12d9853258fff8ff5d3f618318b1368a2a26c49be802558de2bc3b6615c34b3e04cf984fe8e6b96c08ca9424ba93c7d0f00df83409d7b010001	\\xfd6685f01a108e55188ce082407752b4d6e727aa77882eafc57572b39debfd132213bc0ba4742c82684023d7515a728bf7941efbc500ec6f25ed7f5c84928e0b	1689065989000000	1689670789000000	1752742789000000	1847350789000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
83	\\xccd8f140db776dd5f342b20e8217ed20fd1efaf596ac28118894e1c5e718ff7e489f6e4892ddc0db0c1b660a04a83bc614d746cf80fcf036faea5e9a808ad0f7	1	0	\\x00000001000000000080000396334d49a28b75788b42052b8ffcb579b96354b2d6c27e7d0b92cfd617090e41095b8f97a566dc906485f646f2f77f44f5e7219ceb2f7c0606eafc75859673675b21832d33ed23068a94de913976541fe2fbf1e7431c63acf94a07fbfa85882beace16af910f3a5321bea4420ecddb74127c89859775b31e01a8e419891a95e3010001	\\x8e6688fa0743e43562ca47c97756e93bf2ae8df30e954d139021fb9a4e04aa6f1642c4144f5112fc98b547f2e978d7e735118f7e63b6adf14e70358e85a45805	1688461489000000	1689066289000000	1752138289000000	1846746289000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
84	\\xce6851e9414d423e18f5b25f7f3fb4af801bb8f9f37cb1b8e6843a0ec0bb2daabd138966a55b3002c86d87b03aeae152b00fa2a19353fe5a2fdc037e288d7389	1	0	\\x000000010000000000800003dd63d1a32e284522817826e9884df10cf77abc9f0899cbd6f49823aff8af1d96f6f6e45093c4edaaec0f5346e5523cd784d5f2ae31f0388f7a7f5eddbccf296f12076648b1287f6f40078f65c828ade5b601466dc98c5fd3a1f3181eda33d7f71d2c6832bbc9107ad7c0e8a4d6de9ec8b28b1da967f17fa6dbdcdcb606a48e49010001	\\xe1400da1b6ec01186819088118358dd7f852cb28104bbea826b112a492885a2cda07a0be6f93fd2ba0bb70d6578022890fe275d24fde1d05ff5002ac7f5ac60f	1667303989000000	1667908789000000	1730980789000000	1825588789000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
85	\\xd048ed61c39231eea5185aa780b07a7f46a359b9c68ab2e771a3b276f66d1ecf5a6b443d9a5728909133a4a0bda18ea4a84c88427cffba8085e2befaae439cd3	1	0	\\x000000010000000000800003dd184ccba05bf893097115378038ecf9602803c2f0b02ea216b5828da22393ba440330aaf76fd83ccdf5c603756021c62db2b8d4e5963ffe9c4f575642eb77d4ff8908159522fe2a2fb15516c351d26827c7a752d2e01d5ce822029b5d7faa1f6422878693d3e6c93d087c5cdc8546ac188f3402aa79538802bc119323cbee17010001	\\x5487110c8f432a07a0df3ab4c0ff2f3027ec98bee545abae4a476022225042e0f14a486024ff8b3fb6ec3434e9468ba5f209b211d1fa215b72f0d2d044170806	1663676989000000	1664281789000000	1727353789000000	1821961789000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
86	\\xd1a41bf9a5e625321799ff8be56853bea8081876f9b892854d216136710e8fd07260356fd82598a141c7fc84a4c16470cc9ee74a52756f24b4301cbebee7673e	1	0	\\x000000010000000000800003aa144b5220fa57ceffe198e6f83a189ea2976d8eabd7b8d9e992799ff07da5d745dd56039c3c39e0b5b6ea302fa13ed731451e7dfe3ff71417a4b2c280b8af0d23035c44da8269fa28045629689d792c0a961bc462b141d22d4723db421b2533d9ab209c898624f9f009ff800d26f8d43c01d7db9cc61c0c9894c40d9d74af39010001	\\x04bf9f27751faea902a646b64db80eb559a89bc96127e6e48e017c356ec2b69f2753de30ef51586a35aa419fba5b35e67d13f06ee7f5be8aac1757a24a289201	1664281489000000	1664886289000000	1727958289000000	1822566289000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
87	\\xd1f42cda7c72b9e3d249107d4381ffbdd588303a72e0b0811138776b5207a451688c986c6be463687ee97217bd69f90113ec5c0bfa1eb8b8609400be0ddaf4f1	1	0	\\x000000010000000000800003e94afc660b32d11e05dba2a39d222528ecdb2d18ad3ef59d16536365e0b614bf8d833115692b67b8e6278282ea00e16ab9f1df84ab0c68b6040084bf5ae65960d58b0110b50d0669687b76843fe3787dbccfe15aba58510349eef496cdba4d7b190d56d81b7562fe1c93d93c87a5aa8fec1b943373fb3553374d45042b359305010001	\\xe9d64ab4ace45c377ff033f8d60716bc0fcd5524ac065e84a522ea02b002acd005bff2dd576e6cea9dc7cc14a9c3bb54a5904735b5c0befea055f30d9540920e	1673348989000000	1673953789000000	1737025789000000	1831633789000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
88	\\xd8d8b9f84bd915373bb5403052ecc1d94481383cda2d2c0c75ba2bc095a39ae7c44146c08f798015eb7b3de942328f6987c3fcfc5b6ee08968fc0cb9cd125015	1	0	\\x000000010000000000800003c2f7c9b1d8ec981d17ef08aa58a2e24e6cf20e82c1c36cffe420fe1423a5c3467fe51c00b261bdcdce9c6d19e53386531ecf920f61d196ea440ba55712c0bc974e48d896185213191e09d3aaefb99bf7b6fac5459443e0d3d95f5b9c842643994a887b3856ad21bdfa2e93e64c25eaf643f19f036d0cabab293e2d1e2826d8b3010001	\\xe302a24cc7deb26777daf25f69ff3fc8415dc8ec18d602fc260b34a2ac7f02b42901bfd0652297e7774ca2b89847e03d504d637140aa6f57d9001abefd137c04	1665490489000000	1666095289000000	1729167289000000	1823775289000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
89	\\xdda0f9864dffc82d43c8df6cd2718b9c400f3359a86252a44631820341f3c00f4d0776db9c45508eeb8b8eee2e2f0f4d1ddf92caf7c41c97f14fe6a95e19961b	1	0	\\x000000010000000000800003c0181ceb64163990c3e8b9336809079f353ed24088f7b15cc2f22443a3f8e1d509874465182103585798812b2b541dfced58e99b6d8cf149d3b3465cfff82e3f8225981e34aafacc4c27693c3df0a875d53d265df55ad024f5d6a0e5d9ed5390ec891521267c96f04d0a0f4f7e36f5de42ac628e52d839cb47148c958ad976c1010001	\\x5a3a973547d1155cc4d666c27ec37a3a825f8607fd92c70aa02192c23f03439828b559f2cd30aa6b61afa41c97d18d474cc4773a2510c5e53c3f5cea733bc603	1684229989000000	1684834789000000	1747906789000000	1842514789000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
90	\\xdd8879d3e40e0946e88dc8db83f137bcec6014eabd449cd845cf17849271dc58af0228587575283a1da43986eb98ce12683b5875bdfd3afe58cc6b9dcfd6b9e6	1	0	\\x000000010000000000800003dfa4c6e2ae538cdd614455e929021202476cf21dbf2b8614f242412b9d9178fed7e9eb1759b782415b077ab6be6a9b9eb5f0615e870588b55d07f8aa3615c5416afd55f9c00c11dc99c9d02930b2f67a73e89d163d993d5c92c022f85dae688de1f0a518b5bebd39cbeba75fec3e69dd20103892529fa44d140597f0b67cd967010001	\\x57b6bbd231ba204487377b0471530b77fb5545db48f20593a4b81ee51d0c124baed96b71332923975610ed4013ec7e4e3eac84994aeabb00d15870d0654d1b09	1673348989000000	1673953789000000	1737025789000000	1831633789000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
91	\\xdf28ceb2d0c0cabad0c608986107c276ccd82c328bc85e0aa9ec0f4fd904fe46e0b0d5f090c669aa312bc2492eb767068c372a0370002ba56c60fe96d94257c4	1	0	\\x000000010000000000800003dec96227ff0ec8f476a4d9e6f6bda8f6a9083405ec06cfc14a5d712177fe170d3580be9f7faa0be88db1fe9769749be2e6d38bf4dd8b5d9ea5bead10b6be736ceb59020bb4607c30e016bf69479d3c7fa4b9b87d2fb4626564c266f39c836bf869792ff8c51c79dba4091afd0fe7a928082c93e0ea795a94723f24521c9c5053010001	\\xb0556b6cd1bb219435eb835ae15208b5c6753d75e82d7cffa08b5d2ed2fc194eee2caa3b1856532c42c780a51c9469d84a90eb30be743cd13c172e4eab514c0a	1674557989000000	1675162789000000	1738234789000000	1832842789000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
92	\\xdf24049b9da25c55cfd5897da9581208233d5875bb39a485ace8285775057c47f5cb0542182528e75de69f3b6df53183531b790f92bed0d588c3777bb46e9efd	1	0	\\x000000010000000000800003be740cb4311d3830a5359b066086971b6f8b1125cbaf2531cfd36e90e2b429b7d11de54ea828c2691c90202e959cd2045a1200f1fdca02494f6ec560c3739c72fc031fbfe963b161a74e99317c423d75dda85c98ee6a8d322041cbf3dffbd7e0e85dd23df6208e1a66651538fb038a2e979e80feb837ef482e4f88c14de61d6d010001	\\x4a425f1bfcc47d1b711b5037678544b402669e3504566ee918cc2f35da3edeff0c735718f1b6c36fd7d54f8a1e5a58500638776d9920dc2200f6d70fe6ed0007	1683625489000000	1684230289000000	1747302289000000	1841910289000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
93	\\xe1dc4293b45a53788fb7613b94cdfa2af989d78b40d585f019d59253e66ec6015882be52403a17ed8ab3682510772dbd508fe38d09a169e54f4d951f749bedc7	1	0	\\x000000010000000000800003c430e34bd169fa019e9a6d9b69141914f5122abcc6a752cf8c3de31ac47ba0fd9dd127f4397177c91b85c6d9e6e5da36937f82a257232a714cfd8dfa54be2c668b10dd68d1f54b997b20d69e316c59db776af7b854a2133099f94dcd70923188f27e15b5e3441876416801ce4d889d51eca96008658534cec53dd6394213f7c7010001	\\xf96f97f00f7356ccb800829eb680eb969f978d919c53289c4319e623694f767b6c2298442e446389e077070d32e400f48a6768e26d529c5a535bad353473a604	1668512989000000	1669117789000000	1732189789000000	1826797789000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
94	\\xe5a41a7e840325f3cd6d077554027e9ed768aade1f9bbc249271b25e0d81ac6c6ee92e13957c6bdedd65051c033385f35b15f4cda6ce700635ade1af8f644acf	1	0	\\x000000010000000000800003c27a18309f2ce3750bdc066a438258d966366f271824a9f3bca65694016450933ccdb6f2c7577a36e8a5b700c6d09da6b7242d66ef0c4ba23e276b371ed27addbd3cc69e14724639faa74ce55fb0f3da78c2edb06f2cc538414568573049f81ea7e96e3dee29766658bf76ab1b6564c8a0ca23e65a360dce9c1104d87546af5f010001	\\x33c3f6c55de34bbf567f820607c617f3a49214e11b16e7b1675bcf03010351212fa735f6c8a0df5214b6c22f561322452f60ba1c563e9a7335ff13eb0c6c0001	1673953489000000	1674558289000000	1737630289000000	1832238289000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
95	\\xe5e0cebab42c75e130067967acc2ebcb11dcea66328235da0eae449f323bf8a17892c10fab90a4dbf00863fd8dee941e997d03c91ae0a54aa7dfb1ca0aaeac20	1	0	\\x000000010000000000800003a1f8a776def4c673355f1550594c5ea20433704e6c380a5d7473ebd2c043a29b3cea34dbd3ff59d09f168b9830f7c1d658d4f2853bae58ad72478b63a375716d5bc368bc65616a3e0759d0eeb591bcf72f3762f4b578dfce05d7350542b92727f20a34c09473f208ead781efda4e2617d4af3fc7dc4ac2dc2cdae2c901617105010001	\\x3d4826714f2cbb7c205d4b1172e125043e4632def40d2660fb0d1ea2b46934eea71bae55c8709d0c3916739718039604e1cafcf096f5c9de5bbe317a9ea88907	1670930989000000	1671535789000000	1734607789000000	1829215789000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
96	\\xe7e00ee825ad64e756b78c89dba8480a0fd6a67253d2bae0d0560ae46aaa80ed9b21c3e4674000d26847f261de745cf7b20275e352aa6193d1a78a3ad7b6f956	1	0	\\x000000010000000000800003b9542cf0d31b3cd204fdef6c9de8e8c9fc6cd67d25dd27ec639d1e1915e27da7a0dde6beeaa7538651166828e3e469b31fbb7508b9f31d364918e94c19ec45e67378369b0c693b392da06a34a9ecf22cda5d44c3acb374f13e873720d40ef72941307f6ef494de14ac23fc2c73b58c0cd851103f81d5985d99b030c51b68ed63010001	\\x091977053c3ec9943fc0ad13e23540f0036f8baeeaf4b29b212e68364dd7c866070d6be741e8f072e2cc7e3ea242941bf0e7f92c6efe6725de40d96b6311220a	1686647989000000	1687252789000000	1750324789000000	1844932789000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
97	\\xea3cba10e26f188477e2abfe507265c48ddbcfc087b679f1738e2d02f79f24e57a671fc611d13a909289b80b515786ca90bd4dbbd4a454453cea3561ba42c60d	1	0	\\x000000010000000000800003b50ade26fd4378fdd8d595714cebb6337cac9646da50d778b9e7ad67ea0f1b70688f8fef8f3c95f063df5ff2b71f8d06993d71cc99042b290b4d3c268c9f60f0721c8822270c3f4e0c8f5de43121ce15ba35ee3161d44ae68c392a60b0f0243b189dab033a77bc31852a1c8f8338d9b69e4728ddb732648cb4d3076d2ea62729010001	\\x0b8719ba9442336e004c3a5a658dfc1d9fe11535e8ce439dda725d786c747748ae0853cdef6561c5dc6cb0092a10463b183147a27fc8d19b550d3ba48a69a90c	1687856989000000	1688461789000000	1751533789000000	1846141789000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
98	\\xecbc7ea91aff381c8d38bde3596c49ddff0156543cb7df6842ed6b779187a18dc566d259c3f7884e65bdbe159e74cc0185f95f265723e40d08415505c15e6f01	1	0	\\x000000010000000000800003d6b947257f92918dbf7f253858bfe04063b094ba26f7148c2451da7aabef9fa853daf7e38d0ff96ce44ab58794535d9d9fdcc6555e37b88a87c1868395d300f518d1c9438ddba58e976bbc69d393d82164c6feaef6028a061e17222900c0de404c467cf7eb21fd3f4e23f1f141d95dcd4efc930bccc8d6ecdc94989bfbc1e6af010001	\\xfddd51fbcb918c83a1ad985a5abbf5c20d90374a8bdb2e712b750023fb3c383a21bd9c4d2e55de5e6a517b608d6b22b439d4fc5b0839ca81c7e40cc54ad72909	1676371489000000	1676976289000000	1740048289000000	1834656289000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
99	\\xee74a1059e35cf60599632fe5475bab1c01723278df4d0a6f0e80a9943a397fdb3541f54293e8c6ac5315427610de7de4d6ca3555099674e20db2f83276bdd7d	1	0	\\x000000010000000000800003bd592e70395cc506e0d5f61ef9c6f6352f2b984c51ee1be0d52abb1f3358b58265ef08a0308ca952134c5def4fa44a58c99fa4c218a21a366cbf9af28c1a6ce471eae5448752595ff2cd9c59bc9abbeaf31632e6c0955c40a3e5af76fa8555114c77b4712ecf9cf65d6fb6e9d6641181d633db93e0893c8cedd0c59db3ea29d3010001	\\xe2273f79824478ed9d629558ec5e996a48a9c26e0f34b16c90110000768dfbf9bed55c6601fc073ba44dbf6abaad036bb4fa866d59248896b6c72e3aacf52c05	1691483989000000	1692088789000000	1755160789000000	1849768789000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
100	\\xeff0537151779669538bd3985c5c8528779a29bc1c219bf2d424328101e8ea4184872a8389a79f34018e8d3b0e6e35029013480bbe3c381300022c4398c925a6	1	0	\\x000000010000000000800003a53d3cbdb5cf2a978661f2d4b9a5c3ed7e1b0d667b96d41d9fdfc9776bfff94e4be123e187353e6d169d0e0eb6b9e7e07922c8eb2d82e078f513f363b252a21504060e5eacc83f773cf3c7c434d50eee8f3741d7aebdd23150efe24f9db82222980d23dfe869ce65e43a0799e3200a16d1cb7964238fb46858be5e75099f7c3b010001	\\xece5c513354286ad73a49e72021f7bbec8c2af29d8ff72250e317ee05e46222479a2261ec3b7d1376a4cf2ee62278614174c439e7af4b29a8dab59f67231de09	1680602989000000	1681207789000000	1744279789000000	1838887789000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
101	\\xf0aca35194b8b06b148bf31c97d79c8d7aec225ad64e76d33bd5200cbab4d8b6694fb35a4ed6e335309b805f03fa885a2ce2a9272865de06e40b02cdbab5908a	1	0	\\x000000010000000000800003d4f4a541e6a4e305e06b89505928ba8f12024750f15602f01640e97c9cb47fcde3ae4acec65cf8680af71f6d71dbbae8b34cf759edd3ed606b7afc9d6a006e5d0b912cf55d0df9a9caca7ea0202eb35b0609d14979f88dbcb4565f9f29814f5493df5776ba5b918ea0cfafb07915068e0dfd4722cf2b2acef47a9ec770fc45e9010001	\\xda4d11a4904eec452bb15a21b736727a485875c81637535bf1e1d38ac9f026a23376f0dbfde1868a9a7255ae58acb9098a7bc91269a81c4d2fb5904efee24d07	1686043489000000	1686648289000000	1749720289000000	1844328289000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
102	\\xf04883aa3756930452a3640703608dce16f0d77c2ec6605abe951a4bf4097a14e52376ed024bc6558ce7dd31cf68a53d1a39c7b4441206837ba8d4112d475345	1	0	\\x000000010000000000800003db65ac5c4f7185b9df5281c2412afea8533674480ca277934a02cd0e6d91bf0cecec25bd9d4aa14fd23373a9dc9f334a986927e1bfefda4d97e952ed2058cc8b7a2c7ef72ad57d9377a134d62ffc54cd8d90e4319a7ee7096b150c0228fc5d0978154d909919624af540f68c775bac0bdcb382e1ee1618a98c09c91be65c3a15010001	\\xcfaa0724d8c24ea025a87dd914c2a4a968809122628b9642f360aaa6fc6af8f13dcf6ae0f25868a10e6a5a8db54fc4514143526769b260720b2ff2be60350206	1678789489000000	1679394289000000	1742466289000000	1837074289000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
103	\\xf50c62c17ad6de86a08d3ec47f8f5c58926df9e5f7a72e05362a9fb232b997e71c1a84ceca4ed30702c1b0ab65c46755150a8c99b2f3fa481b56d34886c04c61	1	0	\\x000000010000000000800003deba660dbdd13fa7c5f456b44bfdbaf57a60a2481dc4b2c1c7f641c8eb28f881ebb6536f36c869b25269e59b78517fdad30dce2f62e6f097c702b00be4aa1f645aa8c958c2e4ceda03b3b21a93f2da4103061e766a7a35fbeb75c777a470eaac3e8123b449eeed255fef0122d3d2e6edbf9eec3b8c4d2eafe70f0cfc59803c3b010001	\\x6afa896b1cb71d064060b8f23ebeecc1bbfd683415f783942e96b0d51f7b30df7e2be067e64e0faa30374853ec1c65681fb3f8e4be40993cdcb27dc410e4980c	1684834489000000	1685439289000000	1748511289000000	1843119289000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
104	\\xf738380fd3745e2970d034791408e26018b4b23ab2310a96cf5e2a7be9f223ef187cda7e6b5f1b91c92637257aebde21e7242479807c8a1d2c620e36d1f0c48d	1	0	\\x000000010000000000800003b5a76226f4493c8340bd278347e0eb0723fc1c697827a66cf7dc3ae5546c7c388cf924bc15e86e2d070666eed17c8c9362f0dd814f66a6ab51125df784bd2da83a19f1ecc2d8b45e189b41e9f1831ea9ada39114a92eca71817ababd09ca07e69550932e936211d90d3e2062e311f8565ec39d1adb6cbd4a8d0ccf870fed23e9010001	\\x95a827c7010b0beed3fa7877855cba86f3bd14aaed9045526b201c7dfa14b5bce380d471e22bfe4c8059382eac8345c8f86ae3f4809e264f01876b32e77f7200	1660654489000000	1661259289000000	1724331289000000	1818939289000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
105	\\xf850e782601b856801bd1e425764add8d8fe9650450f6e8cc3b8e4a7b3bccffa847df3680f4e9b21642e77b4dbadc5fb594c593965bb03074095bc126f2a3f07	1	0	\\x000000010000000000800003e01b0913bbb780dbe1de266162c0844d766b37e7c8d58219414c44d1e529553a1ee644697cc721e0ef0381dd3764091b431ed4cfdb4ce24d4cefa94842a9271ffe48e8a1cebdafab77cbe4be34c08115fc2e5740db5be056f3eac4dd7e5978e036fb1f6df7c318d04fd575e01e7aff1288d488482bd9199305fb87434a0c83e5010001	\\x9a38bb05e65d99153735fb9630eba5a61628f4ae1c14cfecf55f403f740fa1308ff87cc8af78457e744c6ba6f900aa0985dbc0e14ad62158699b8ad0cc185f01	1684834489000000	1685439289000000	1748511289000000	1843119289000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
106	\\xfbdcb006eb7a4b67a79dd32c41d8e8a67965ade1126e9bc889fb3a574fde84a25125a8a5cb708655acbce2e57ccd487bc1d6c915a244dc81e43daae8884bdb92	1	0	\\x000000010000000000800003b1e41f7cc27c35c34bd9bf685c4f5f172682be0dfcb8404b6f0c9ec93119d86b03b92826511834668a5c93e3b3170575f6cfc4888a04f94b147fbb4e08601e0eeab18987c699b82f40c6998d778341aeccf2e316796c26ca0f5b9d97205a05edd9420b5d300aa93cbc3bb4255a137198a4a99c6abf51db6e471f5fcc4bf8d687010001	\\xc25de3661d8cf6fd8be61051fd27f9a69dc9e92fc1c7aa33d06bb2deace046cb3c875c743400cabc8eb4a2627241638f5235e8e9971c6008dea7cd930a293307	1679393989000000	1679998789000000	1743070789000000	1837678789000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
107	\\xfc88f9fdf180b5c7ac2428474aa359362a8cca050bc975ee6a625c4c79d4f8c789248a1ec2af703cc08bad928b2c369b2ee2e5b96a0260bd0eb6e8d6a65758c9	1	0	\\x000000010000000000800003c574be67a34e9a8fc6b7f0412e701ab6893aea5479261c650e318a7a103e0690504a57941dcec87b82882f4ed66ed28a2c2b5d276a31adbc2d5d0ec90c1a1856d6ebc8ac76090777a1f8cb6f804315bc9451dd2dc26345cd47d3dad476e0523ffd5ff560b042c37a5db89695e63fffd92e2fba588fb0fa70563be731a72b1bbf010001	\\x000692cb771836f0df3d59373d6d420872f8f0201a333a07447d372081c57d5092ff6b3adb71b13d857a7e90df9136f62157d87c8a3f5ffeb90bf5c555f67300	1684229989000000	1684834789000000	1747906789000000	1842514789000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
108	\\xfe14bcfd9d4df4bced9c314b93877c9c4ff77b2ca713882a5fa67634ab94f68ef6bf4c1f04d10459a43244fdabcfd89174029c9bd7fbf9ac5a5db3e5d512250d	1	0	\\x000000010000000000800003b98f94b43314c9d0bb796b21e77a8f43f0caff845231906604ca00339a706aaf4a6d5e05d72c26b99ed938864f4f58310c906371ae39bf1b2343b555f92fd79096cc310f5becfb62faf121125d7dd597afde2373e4ee6a389fd6ac7c66df526df6dab9f5b285c8b5783ed01e4f6c9f24c9fd3489c11690f59cdfcd67dca03a7d010001	\\x1daba977c70b899ce4c031dbd66cf62649042b395c3565b0881a6050d3ec9534404da94ef27623b43da2d65de62ac0a4086ace140244e1f9d5f1e0bac2246e0f	1681207489000000	1681812289000000	1744884289000000	1839492289000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
109	\\xffd488788075949413ff853cc266223a77a6eb43b7d646b575bdd8fedb2bed6ba93376f0a5c2cc25c2ffc79da325d780fb948c6a0855ad55783e255e8f9571c4	1	0	\\x000000010000000000800003d8049c275469464a7f7596bda32b6175e09696027c7f5a49e2c6b9ffe7450adb9ffb0b61698348f1d972ae0e2172a01ef5b69a2493258aa3affe65e40bec034b5f42a107cfc60008c22d6ff2c0405ae8f670a66d2e5450e2dd8ae34243ed4e41df8d7789e42509ce5e86e5e9cc56be1cd8894e6509b4ff0de11a742f8938b717010001	\\x4601ccdeccb0b2e6ded76642a117dbba384396ff119ad272590833f8c58af3bc1cf3753fe76b47f60cb29788564739fddc084de2997424343e126ed942c88a0a	1661863489000000	1662468289000000	1725540289000000	1820148289000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
110	\\x01f1a524b845a3a0e1e188526c046ab003a56dfe6aeb1a16b805f7a789f3d6cd0973d205b7c28364003d876d00b166688f3a8daa8a9db93d7828169af25d34c0	1	0	\\x000000010000000000800003cecb952333438f97de1f26132c8474d680b3cbaef4de390dafa5cc741d6d8f8aaddb821ab3ee9acc26245cc1224bd4707796fff4ae59327f138cf41086e0fbb55c77dddcfe5feef3f7ef519fa4411b2ae35ae969a959b32845ff0e94d87dc057dff259fae53acb9b05db79239c3a359d4f7fb21f2bdc2b2b3249830d552a597d010001	\\xa3ba88a0956ae3d83330ce18d0df8939b8bfd6f073d25fa89586b9a62c9e69c79bd36023ace19066e10d9db34ae501028a8457f65af8480a9d3a23d15fb81900	1678789489000000	1679394289000000	1742466289000000	1837074289000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
111	\\x03293f99780d3ab2f8620ded35b1ee34d94ce5080131f8bf9ee51c94d29b7e1a25e09d7df471b227fd9ef29b962dabfd4fdb3149b92caa19571f966350b8b263	1	0	\\x0000000100000000008000039ffbd92ee4658f6ee90e6b50aa6aebbe4b9121fd329ce254911702e4478243793612b3a9ad45a04285d0e8da6431c5f785264a7c9f72dcc76ec1bb6f23c60b0df7fa720edeb731aac5e6f4a4547e638a1b15382af8f516eef9e45d15b9f80247ca7877d1178f308719423390b52d5426dc090ee4b7bf8926df55f6c71bb3aceb010001	\\xc14cd29905827021ae6bd830fcdf57875ffed66a4af049e867430bd0f7015745e34a66eb11c0a17a1cc960572e8d0458611db7cb94ee572359089d62b57c1000	1672139989000000	1672744789000000	1735816789000000	1830424789000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
112	\\x05b17e20898557abe137b48584ca7f46aaa4effee693d9556c9f5474301cc94d5d0e7b880448a7f32b4c9468972ca70bb5ed341486eab8cd493f1e92fb27a5d0	1	0	\\x000000010000000000800003c5d80c7dcc6de2252b98b63dff89172f1cd8964c0308481383acaa0f1bb32d42968c85f50a598b33268a33ae9315373ba5ff484f10c35b633cedeb3d2cef8756a6ad1ef1e68f0ffd0d9d7cbb518784df3e717d7ca4b3e669e692dc1ff5da9f58e6403041adbdc9c2ab2e6bb79d96d03c68b110600cce7dd8d169fccc0a5b34b3010001	\\x0af63bbdc856d5548733284b75250b9374ea6356737cf83b0357f5fe5cd22284b4b02f471ece0253d35b9500a727ecca0f442f84befa56fd4b9e87ce18e5a208	1664281489000000	1664886289000000	1727958289000000	1822566289000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
113	\\x06c9efc4c98330307f3b0d9884712f4c5b3b2741e65ec28bef4897ee57be7515191e84041b906518ffb399d4c10e81de0b4971149f317e28cd1856b7e5350d85	1	0	\\x000000010000000000800003d4ec3b32dca3d11345e5cf82154c7ff31e9553a28f1d63cedb35bf5eef4f9f42109e72962d625ad39ee0bdc9eb4d8e57a5a3b08c660c7e2f13cb29d44845782f965f187096682f3c8a11277c38e83207a7332f44418fedef0973e0ba01d78f97fb2644a948f38be28874dd503dec1aa4011af35236999d303c4161461b1ae7eb010001	\\x29a408cad79e9aca9f9ac01d745d2853959f75a8e8df221fc33e967df65ec622debcae61870e02de95ff911923e4b24f645dedde0cda3b67a251f15f52486f0e	1684229989000000	1684834789000000	1747906789000000	1842514789000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
114	\\x08016a0f301be86d02aac28ab1376430357cc36fb13d9a04d0181413d22cfabb55f5d6ed444167549b65c1fd9a0802398f29503e5d70a82a3ecd647b66381b24	1	0	\\x000000010000000000800003b67ca25cd9035c365ff185d3027e668bf63685a0bbc6fe6939f4a8870b84ded7c541b8da5e735686659ecb2a5aa219c0a303c6ed662faa4a0056818e01676e476a86a8bcc4a09c4d528cedc5e1f48b1ec7f2ceaccd705baec58a71e4c732af05c5691ba76371c6031c14496ea6a90152b443882e8583cf6a44fe2ae890f40409010001	\\x1ba4147e7fa861015a4a80a5efa0d11f59c0ae4e82d95c9fcf8a61b8b6b6d6e5f3f23eb8b1ce104db0021a9d6770e3caee2f55ae76a67651aa4ab0f211c76a01	1666699489000000	1667304289000000	1730376289000000	1824984289000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
115	\\x0c954204b5dbece3792c04001fb65c1a9a7cfb654bcb30f2c6634bf32696afdff472baefed7a016291165fb2a0039ad4ffbab929b989e7c01bd553070dd97b3c	1	0	\\x000000010000000000800003a29b4fb846ba2423c95fccecc59ce32ee96aaf23b2aa5aeb7ef612ee95c230d980548efcf19e87ad53c720eebf5568738f1d280c33f9d2cdf6b67ba1295c942a882528679279ef88724b53d6f55ec22236279823a518dfc5d2e1614f01909abc128ea20a364cda6d16f64d7b883fd9e85c6a9c11365627cc68f3ea52c69679e9010001	\\x53e6f19691e97af4494712abf711be1a7c2e3e9e93a9396afa7bf090791da8f99650c55acb48ec7750b5f4e64c9a1580c37407fe42f51d6ff8257506fe9e950b	1690274989000000	1690879789000000	1753951789000000	1848559789000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
116	\\x0e854e874d53c36c3da0af7e3ce8bbd5fb7a58c8168ce93933e5b0ae52f7b914f5803669db34b60a331686b4bb5f79870a38ce35e18d675f77d6917c70789b7f	1	0	\\x0000000100000000008000039b98bcd2bdb84b19545cc157e318064e88a2ade36fc1cad09260dc3bee30a319e4dddac1fa1307b0ef59897305d1c0cb3cb80c80507cdb81843b5c610fea8af22245df716c17cb0875f74a848bc06e6418a4341345e6dd4d15673fd0fdbed54a4d47802c16e91798d348823502568ebd29934e1daf2936dda4a54d65bec3d8eb010001	\\xc4c77d2ca203340a930038c632b8a2cc99ae8a5a07a7344ed58a21bd95aa6c4c106d6f3ebe58066afc484118352213f4155abd84220140b28d7417cda04bcd02	1676371489000000	1676976289000000	1740048289000000	1834656289000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
117	\\x0fd1b475743f2226e2462e0ba22d51e77c5561ef1fabca46c280ec8329e0ea5bfabb144e7009a6d166c9bb4cae8d5611d42a1e75319cb774aff5b48e117da9af	1	0	\\x0000000100000000008000039e6f62c067df541f257d2144bf09b0f12aeefb531b550e10ec4cf93bc4941aa0573d87925baceacc866fc2b1fefd0f6e0e0751a083e0f7945164d86b807638434c43ad31e07809774f50cefb14c0e26f916bd5c699c27b3596364b17ee1072396cf9be51af93d1b2a188f6b1cc30565c7596e517be5840cd899aef891c376549010001	\\xb11a0842d8d5ac45ebc23d1ed86e6eb60b473e6e1e384c1ccad6ac9cbb5f0c019731ebb4c0e057ebc92d9ff4645a6e516129b75704ce96b18530f89ab9b5920a	1677580489000000	1678185289000000	1741257289000000	1835865289000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
118	\\x111d4bfc32cae68bbff763334d038bb62e2655af9b1edd35837e69605ca9baf06bef7e75a7795cb16c713d29d489a3bcbcc835df303e9340ddb34d2533d2ef2f	1	0	\\x000000010000000000800003b00de7525b17b721a4c7f4215a487ff8aa6f3391d468f20142ae0ab5347ccbe1e63ec47c527fd814f63420351679c02839d4a9625d72ca5fc8e123e5b481ea7a75ada696681433ca30ce701e82199be7ee587c221b50a80d2e80fa17553c01381a199424d7b6ea9d03690321c9190b99609e017a253f3ead428a3c2563202d49010001	\\xe98d4a863d0147ce16024fe924c27c5e193516ac82475e057a6d79b05bd0057cae90df75701a656a26aa00294a005e1f81207605e913fc61c698096ff52f9a00	1675766989000000	1676371789000000	1739443789000000	1834051789000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
119	\\x1899c30f62754e685d79bedcc5f37267aceca650176172900cba697881d4d541006a950ef6d2c5bdb57675d6547ad1dc401c25bc734ad8f7239032a16b2ed9b7	1	0	\\x000000010000000000800003cb283c2810adbb7850781084a313b7ef9129bebc278adf0e9c9818d3c80f9eecae6f0db0e9d2ddbd3563198b5c07255b64bd4a5dc1c9143253ee5e25689a316a8d3be35b27f7d6f41f90a2221313e6f1ec28fdfd95aab7d873a49b4c0524825c77d2479587e020cddf2213e49c3e9233cf573b74d4a5667a89468199bdf4970f010001	\\x9c83bf93f29c50d8bd525024738923cdab3e5c38ccfa6ebc7636187dec4fe401714fece4079d39970d7051a9432b66012e51b0894171fccd6a52f9353537e006	1683020989000000	1683625789000000	1746697789000000	1841305789000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
120	\\x1c9902e6b76c8c6734f7d31e4eaa1434b3c54b2d5cad457b51a470531acb3cb0c368cf213b45a242e9e1e3b0985c6fffb5c27555d0b9a1126fec25b73cb11ee5	1	0	\\x000000010000000000800003bb026fe50a674899533a3953d3e0eff56c77c24d7425e01c1d9d3c019289ba3c021228497f3865c9f194d6cd1c24790b593643a7387bebd034b3800c28b757cddc9cd3145018b8120886df673443664c84747fe3218027452426ba469bd2b7e788fccbde8940935c86a1b96867b45e1d0cef80d1afd3ac5dd4049192808db391010001	\\x23663230d00d6c29ceeb445fcd847a28f7d446f276970e7f1f1eb8b3bb5b66940d4b48538c273e3b22f4fc2dae30fa9e35dc4cf9e064ed957f53f6934b339804	1690274989000000	1690879789000000	1753951789000000	1848559789000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
121	\\x1f653f9c068caeef8dd88ef60d0b87aeff63c1b640566d6c57b2a3442489d0ded2f7e4d698df5b56bfa3955412c1e870ddeed1c95ae6c9de08fa687d64c8333f	1	0	\\x000000010000000000800003cb3e6fee6f8680c6a735be7071386960c3e97519106ce0349bafd992613c87533fc5c135ca9cf36a007948645a3166f7668a6e402e0b4c595cd90f68c6d8d6f8e9b4dd4c5990792ff3f92ca054c6444a0733972fdb0fd17f4139ecf504cf0c386e9cf8b63742e348e56321783df99fa34cdc0223ca16e0c3526e956f96397355010001	\\xf6e678b9ae3771afb1b7c78dd754de67781ab330e42bf506f6485c78c169d287802f2d11c03567b2245fccdc96a99398d900505a1c2ff5372e59338d9a57e901	1686647989000000	1687252789000000	1750324789000000	1844932789000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
122	\\x229135271ee9e34f4126927f4dd59dae89ddc10a5b7547d445f2ea8ab3476aa1aafc61dd42dba9bab649040502c64123af2325650053c066a8ed579e3283f94c	1	0	\\x000000010000000000800003e599c711585c74eec7d6f0765dd3603ba4f5cf09c0ba79672aefe84277b2eb9203420c96e4f1cbb43a349159e099f8baf2228169e6b2843ab37dfae43025b8dc3c453cb603b6f5fba02c29438453df63401d584a63123025f753e34fde67b98f23016e690df708cf5ae87c462bd1a45c6176243b61ecbcb258410ed9a427fdd5010001	\\xb69ad95bcfe3b15b35f136209c8c029d4c9d903c04010b82f57a7fb85a70a6f941ad3175211670f5f712c7c52c2712371bd9fb74af191a4513a2e9ecfa523909	1692088489000000	1692693289000000	1755765289000000	1850373289000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
123	\\x249dad5066c3056d41c18930cadceaefb54948cf685709b255cb0af727c98c89e53a714d9346ca0f8ae895ec9857055f4850bb28278f813a156e456972a3f0ae	1	0	\\x0000000100000000008000039a0ebabd01da3cc9403fb81057c445af7b96dd865c1eee19c6f0f18b47560c313e98636240942fe5be8143d31d4113dcbe208f32f9f746be11e43193095b5160d12f68e60a69c086c8a81957d1de68549bf5a9f6d2d00811156cfff2b7f5936d34daec51f04c464e54f22155180a3f63a25b8196c2e57c51f70b5684a3c6d297010001	\\x8e59ee1fbe22a95cea05a3242199aa4f656398e330422366d4bf9f9b5abf1e16b8212f167224c154e5277424fe843a58a0540d3e56a5677982d3a41fbf4daf03	1662467989000000	1663072789000000	1726144789000000	1820752789000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
124	\\x261909e816633f96804547419bf07f3cebfa53ccc3480a16125d47943910c3b248196dc70cc1d4bab263a5da6ba757f614d3f94292ccac7d707cc8af2b276084	1	0	\\x000000010000000000800003f61624ebf0ecccfd3506a150cf7ddbdca4f7ac5f983e31efb3c6808c7b07ef7be1296f2c77386fc0b61f06b009bc02d1763409748dc7ac72f6f81aeebdca8739a9c2ac3adef32e8183244ddb72fbf4262f38beb7e7d2dc98404aceae48b87d0aaf35c163971ca319e2a07a929903616a6b2e317720ea86a1dda112448950d817010001	\\x1d5994ed7e22672158b7db730ef923698055548b98a593a077956366796f2f24ef05297046a0bed82341406754dd862f2c94459e7b6bacb5e27b59994e6c1604	1679998489000000	1680603289000000	1743675289000000	1838283289000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
125	\\x26398967212d681878c1ca0d410ae7ab655e4955cfedfc30edf329ba5d2532b60faa90594fd7e6a4b6617376031bd1ff04f7dd62296c41bb964d892906193d6c	1	0	\\x000000010000000000800003d72e5b5c4b919b0ea590a230901bedc61decaa6e29fe7cec5c0448f471cbc37f1606d45116501598a03dfb0e618b493207c346d25cf233c2e4679895faf6e1b27850531e7bb27d5c26f00003e7ac3a0ed8653508e91c9ee6ad51613a20ee34dbeff6dc6b3ca4a35dbcb951b1207b7b6314e476dcc05d0bc7be154e1ae32f85dd010001	\\x070efe186323a77f7857ccb1cfb143138439cd713dace35b1fba845fe3a9b9b449060f184a349fde0a4d3d0a7a66a846ea9675e5aed56e1d3e17a65acfd5370d	1682416489000000	1683021289000000	1746093289000000	1840701289000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
126	\\x2bb1dc2bedd29a61a63b0e535a8a68d86f00d153a9d00e8602ddd66f9460d02fb997c0c6a8b5337fbf42ec88e27738bbab87b8c311b13ee830314523d87bf7be	1	0	\\x000000010000000000800003a92f04a31f546d53150a1ef89d68e962786c459853a7d71cc8d8eb1ea1c2b95dc2a1698fb70d6f203ae119f26c25d748de17a6f8409d663840deb9f26496aac8945701ae2ef5798c57481b6375a84188683bea99128d6793f1993f1bd40939489aa7f1e46b09f8efdf472d728073b53e7240f1f9806f1450e65341ecdf8e602d010001	\\x8d50f759fa4e6dff56538cdb43ae81b4111d248c3237d6a4891f8470a984baf44e3b7725a6a8568f51c4f2f4f43638eac47351a0475c9fd44a98d58a093dc106	1681811989000000	1682416789000000	1745488789000000	1840096789000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
127	\\x2eb94d7ba5dc027b186cb675e8cb328e6ab74b45828c8a47f20c9b87141f58a53b08ae631abafc470bee0c63c6bcdadb067cee18d07354603125461d95772b02	1	0	\\x000000010000000000800003b465f312a6a0f93837856d6bfb47f1560ecd48e33cbe167a9e498f3c85b60f11f100398f7c888cf590af68821d01b528edbe873403c206551d6b377f059232ec740e02e0a83b9c214f44b9700cd53c9c61508ee76c2913dc85ca5eb108fe6a671e10dddec92de93d6d000df04399cc44bbca4cc357e8976868e5494df08665dd010001	\\xa6b45e413fd2d187078197b7d5513ec3d872ddd16928e5b5a06ef6ed1397c05a91c6d0efa81038f998d8a734d9b6c5c787211ba6787d7e813075ad1cffe1e507	1672744489000000	1673349289000000	1736421289000000	1831029289000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
128	\\x31fd5f619d7cf668d33dec106801f67d849644bcb7639f43616f46c481f7d7fe18de78d930dc1c86411fa0cec9dc018d4cb42bebac07dd4835dedd554f2fc95b	1	0	\\x000000010000000000800003d48fbc281fd6fcbe32ae54e6e98990eaa2aba1eaf0ee19a0120cc69099e1593953aab6da1cadddf0134ef08991d28ee20ac185d2cf9f65029fb1ad97f35555fc8ac6c4c0242b98c36462dd71647c26902da29ec54da9f8e742c7c4d5e1a575405f3ebe6ed6f357e9ce7c4c04ae8afe288347dc96b8b229c490f86c61978c7889010001	\\x71bb21c18ee4d8e9500b6e5a983489d40cc5440d84dc7eaa589e687366534a030f448e82fa33f76ecf01311b8d407203ebdc65899f7865bca1d1eb9017542302	1691483989000000	1692088789000000	1755160789000000	1849768789000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
129	\\x34916402d938dd19a927fde7bb51c2bdbeff89ed8e5c8bbdf34fc4c579503a25ac9c6923d6f487221eddb3344c7d263da4db23793a43717e062617720257c171	1	0	\\x000000010000000000800003d1b505e2ace95848b90d779d231af2841603c0727771e2fd72a0dcf611099fbc6d9c68f1872e911a403d01b37c2b6030b6e483235e089490b3f4d16b46daae834c9f32244ba14a9f509928f13965648e90ee7672d177f95b85b348b228b57b35fc25c72fb7b656ab496930fb58b60cc69c26f3e9cfcfa1a094901be52d127f61010001	\\x7b1226b4db5abf5b12dd2b8cae2ff497caf87f7b2e49b63df2b96b635c07cbd4903743f8b4b556caa421b324edf9066b7f37d609984b96bd14d563ca0325d200	1684229989000000	1684834789000000	1747906789000000	1842514789000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
130	\\x36cde1d68e1464b3cf74dd1d9db135c27437824c5438284128718f69a0b515e65e13b7851d9608ae0f0edc2bf2ae81a1f4666bd57a0f9e5b44565db90e6acbe8	1	0	\\x000000010000000000800003bd045a48d1c6ea98259662b98c4cc71947a271b71bc7d03342f61ab07e8098e661f973dcdec9e1d34b37782494e9f687e9f9d43d70828e9ed19b24a2409debbef48debdb132093518b4d106b9983f0c80e9c7129bd90472793ed457a28658b1fc6c2fd125cbad15ad46024c668b86fcfb6fe6a67a9e0980999deff42f5b2152d010001	\\x8a3ad67f0bdb6cd549bd46877eac55445ce16c61054df44868d35b34023d0969934b3109e976e40fe6ed8f95d5bb4568991fb26f25c60557c989ae181c69fe02	1692088489000000	1692693289000000	1755765289000000	1850373289000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
131	\\x384dbfaf459f22b74f319b0bade7c72004f20d64d7889a94ab57c5a5ffc411be698a370ba1ccb65c3a2d983a3b3fb1483630b7cd9bfa1d19e50f8b7a9b6a2d46	1	0	\\x000000010000000000800003d8ea2cf687556fb257dd5c9ef10460639d9f13e85c79488a143e51feb5268823b7478be722aaf82c5d9bffdf77fbf76b04efa71a1c6bc157f581feca863490ea727674fc41f6e9af996ae98e21c47a10c19503843c0c5574ece7cbf8ad2950fb3c8bc6277fad00562c8489ed7d8b2b30f5361452786a42596cb07e3d844c4abd010001	\\x32b07251160040cb716d7184a4e08ef4d75a027e0abdd43b9b9cc259ee58ab7c9934fae1a7ef51d6086b39a77b896d682708152c09268aa61a53cca03e7d1800	1684834489000000	1685439289000000	1748511289000000	1843119289000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
132	\\x407dc8a07af9917073e40472afbba9d9b73ea9ea6b7f571c9fefc0d2e799fb69486f475a3f8b6c167339ab7d9310c3e5409b5c0862b4429b7d7de8c103a5d66a	1	0	\\x0000000100000000008000039e23d5e706ee0fc7494682d9ef85389d6e3544618c6a31bc2e74f5eaa0b4cae5a951e2c4586df062be8d8d58f4e9ec74cdebc35e9708a9f44b39a9aa988976103799e697bf6b4c96f1b37011be67e66a575272366f50e5c75495952393624ef74f48d5a0cb3c9e7cfc0739b34a47b04e1c9fb097fc0eb1193b9da05b6c02cb73010001	\\xf6ad4cfdd4948f5196358a4752a80e4d1796f65fdbc0de7a93f5931733152c25656b9dd8698b6be1507afcc3541fc002b5eb541fb2bec0a74eb10e414bd33006	1683020989000000	1683625789000000	1746697789000000	1841305789000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
133	\\x426d6b4d4c405f6bb904ab35536bdaed14009282741008de82200a5a3496c0c3df8d2f459a6233c9dafbec248376d13105df738be9e8de6a6bd8059e10ffda19	1	0	\\x000000010000000000800003ce9bb6539d23c180fcd06612582acd2474cbcc70f3b48a2236718b8b533b8189e60dd0ab013e65a2efbc169ff9a3dd4e6e29d01ce73897cc51560698ca22e10cf0004ab24f5bafac70c12b9e2842c6f6f16da6ff73929f0318ace2370d3302e8f957f6d3fa6c565de890dfaeb9d87035bd90c0e477637ebda7a093d434ab85ef010001	\\x017f9581040b3dde12b3cd7350db5364d9589cf1ee5fa766d6ee0680ac907ec28927455031d5079e4bebc4ca588df7779d0b83f7cca8ecb5f6ad1979fd63e605	1664281489000000	1664886289000000	1727958289000000	1822566289000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
134	\\x4325afd338fe137fd63bf8fc5653875679a0ab08fdfbb20194f005443a928cf8d7961638aa0441e8c7d0f1d0dbc9f9657686e4679237f95528bdc6b3bcdaa899	1	0	\\x0000000100000000008000039460eda30f15221ea746b005dc339334af024e4f82084eb0d3c85529c2b020a4c1c504938222a65e9735b391a34f13ed74a262450a3c263b5807781f869ce3876e83a5c95713a85857f549dffa0b9698989a1aa4051c02f0c140f2705b21e6612cac604086f6c9bd6fd3e1204bb7a22f5aa6c0f3466b1a0b09abd59228916f3d010001	\\x72959d085b84e6f1bd0a78a9b0137a3e96c24f16996d148f93e29b5e6a40bb3f81c777198d08b9a2a6830c7ce806544901d3e4ebdf653c24aa3194db8097150a	1675162489000000	1675767289000000	1738839289000000	1833447289000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
135	\\x442d43c0122143bcd15fb6d6c6cd9e2505f6168c494ee41302212f48dcd1485767226f45aa27be0ddd224fa931f162430d962edbafb8ad577539a157d2f60db0	1	0	\\x000000010000000000800003dd2b32732b7b4245925dbd600d1095711539a86fd2fc8f8a7daea127062e705d0394194f8ddf208467e1061b5d5676c624d5a4d9b3c1170a38f4f971265056d08ac58ba5cf8cd8cb99834d1f1257031124b2b0c92e6001886dfc155774da831bd8e9e878666202000586fb79099edecbc52d9f6e485f0a4a4a29b62285c69afb010001	\\xc3cf9d0d4274b0b62ba530c9db2759558629289bd804c24d25eff358dd5c8ec4dd8f75b72f5896e51765ff6a3c7e24b6b2d701093991318de192eb6f7e40720c	1684229989000000	1684834789000000	1747906789000000	1842514789000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
136	\\x45b5d1384555cd292edde79971f804e405bf6d58e51a47137e9457cb87d9d3ad80fa86791b044baeba75f2a91ea0292b1bf01067fd320903db71f068d4c29c59	1	0	\\x000000010000000000800003f4c4bfca0cbe326e84188ec6c60eb02f3f28da29d466a8e4bb6260a7aed7025fd179bf741366978d0f30d5b47baeb38704d17e306e8b05ffdf67de8440fb5dd08260f25cd94a21ca0c394a36782fa2b44b379e1abe4ba46e0699079fca9c3d93cdc52f2ac3f05b6c7d521897d28703ae14c07c4b853de242b202c9e63ad92073010001	\\x98a9150277100febf3e138e920ba5b9530cbc50056e438273bff21a229c7df65ae0b7abb02086805521caa8d8613205b430ffa4260f0a2c9b3d502877825160b	1684834489000000	1685439289000000	1748511289000000	1843119289000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
137	\\x50c1a933a6f6e6550ad97f384f96524d4945ae2e32acd47588b58fc6c6b46125a4a0cea4432a26e54c9c936aa01678f021ac00399b845d871be0e61101ce4394	1	0	\\x000000010000000000800003baf81055ab9e47039526790f824af0af2b1ea430bcc1358270ff160f73342c4d421830cb34e2ff6779ccae6a723274966000fcb81f5dd5ec62be437d97d274bf83ca036108d6a2115a59dd78d31df510a90aeea779786f00d0d536f5cf58a40c3cbc144e289ce5700d9e359d06e311f0b4fa9e5e6883c50f34bbe846fec4a8e9010001	\\x3a8c07f042c3d3c04751dd3a59a854c265a4559f630a9f9732b460ccf03380103b8d805b29a52587f2b8d28578c312c32c65abdb0af75208f51635e13ab6d40b	1676975989000000	1677580789000000	1740652789000000	1835260789000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
138	\\x556940877f83da6189c512c6f2f0be556c2cbadf655954bbbef00b48b8ef3689b7aa66818e937931db7e6889b2a5e4dc85e02b18f9b56a18b54cf9a00a3828cb	1	0	\\x000000010000000000800003db318e69f6b4d051e913855e85fcb009d5b5760414912030bdc6c3f7d9023174523381999820eaea35c58aa25c908016c9fa13c4b06bc8da70ff0acbf699becb2b81eff9392483b39ecaec97cd6c516fd4a8365e79d65b02b6bd964612d8925da23f160dd9dce3e362db0d2826d51bc1f14a921a2c685308c454604801f9ba4f010001	\\x63ea29dd37c0f8b387862ed6ef72a8e2f2a75bf03702842fc5c3ed0cb3e0ccf965fc62dbf9814bdcbda1119cfda8a6a826f92cdcfa1a48429ad4f6a7862f310b	1679393989000000	1679998789000000	1743070789000000	1837678789000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
139	\\x57112e59920847c83c8ecc058fa690b30a098824845b2400efbff7ad9a08686a7e438ddc51c24b5a385f5f8c7b0c8f946a4aa4b3e525510601cbf6baaa1bd8ed	1	0	\\x000000010000000000800003d2707412f7046e8d02192fc4930f209f74c3cb47d2d9729f0e7cc4d40d75b550b86010986c942394962d51b5cad3c38e0d131024a70fa55faf23531d555dfef24b838c51f7c3a0bd1e36da2ab2296a8a53793172c4c314d595ed20a82334bcf1ddbf0fd18b0992596ac11fcc4505fa83264fbdf94542cf621abfe1cd340dbc81010001	\\xc05d3d7aafbf372f37fc0d395d74df5903425ddec856ae7b46401d65841b517d9a830ad246b21677af24ebe3c5d43e8eff62308b972a95e12fcb6b05a8ef2d04	1679393989000000	1679998789000000	1743070789000000	1837678789000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
140	\\x59b9f49d8b942d4e8d8fa3a16d9855c0318ef67f0c9dcbf64d56af65509dcd45a8498f2dd119ee8ffaf7f74e5a38430b3637f73db80ef81f68b719acd7a6ccc8	1	0	\\x000000010000000000800003b7928a0e1a40f022c3843521353e28b3b379598daed068b59aba1226940eb02368311eb033a6bc06a0084bb85b75c2708a68c0507777584f389d8cab03c35b7bc41a6b76e2c0114911855cb85672959455430234d038b0ac365651cef654912b0cc9b1afef46362bd524d071b423e27a602994eaf00ee2e6e7df22e5e08215ab010001	\\x7bdb4a883c89ef5c84327a9a5c9e797646f4cab32ece5de3c4e9555dc02391977213c119747bfe25ec877ccd0c6cd453595d180394a05baf4b38fab2768bfc04	1679393989000000	1679998789000000	1743070789000000	1837678789000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
141	\\x596d32e609d7b95cd32b1b247b4757e47f8d6be046f080e749f4db1d09a45e612d01afe17a35407622675ded1cb4e167f0eeffc256fff28afdb3c226f444c009	1	0	\\x000000010000000000800003eadbfc8fdf909f0402a352a6383bda9538f44c3f9f0632f87be671e7b712223bdced8670dd16958bb18d5013f359245b2d48f4991bd7fdf2720fe63cf0275e6fd8657e92611b37ffe333ada0dba129ba9805e56ea99cb575946bd6b3571e26fd862a48045144663aee08a30cd9c75ab0616f69b8084c4b51c957b8c9e7c4d873010001	\\xbee68c876a3e904b3d8d28e44304fac3530c0e9c9494990c9724897058f02ed88734355380c9cdbae6b6b1a729c341bdd7ae3461740b50df2653022262cb4801	1667908489000000	1668513289000000	1731585289000000	1826193289000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
142	\\x5a9db7c943586d89aa4a306900dbd7e1915daf7701068a4a397f9a31fed86babcaa95717eef396c67866402d2a0acc5ed15637e4b77260ea76228a63fffed20a	1	0	\\x000000010000000000800003c130305a0dce7136766cb50ea46b4ab424d3bcb5697b212ba06c32338e2d27cddfe207ab456e605a5d4efa126ad1c6acc8bcf47e5fcc2a92091727dc6e2e20a818af9199a43b8b4429da44d7fdc448f972a36c493a1e23c3c75410cb05f2f23d5fc2b3c1b0169e417407ce3a2b05bbee6830e52a9d793312e35403b6ab50f85f010001	\\x0300e32057f333d7ef83919f9b5658018dbc1953f66f28fe327780daf7fb262b6a3a97addcefbdd770ae00f0e6758fecaa0ac399fdc0616ee32cdcf7f562760f	1666699489000000	1667304289000000	1730376289000000	1824984289000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
143	\\x5b859bbb4b06332e740bce24f2529ccba53a56df61f396ddeec12c0c855a0e61e037ac3fdb5aede6c0e112ead3412487652ba9a8f5037db471e2eefa8e59d3ed	1	0	\\x000000010000000000800003e5fd0698d0081908d5d74cb1414ac796a1d2524b49bf278ca2f4072138956e198690d1c0c6c35d7ab6be8e2905f3948207a729a2c9bad4c4deece527e648ecb8b88177275fd57227e15d544a8bf5aca782996e5d91af65a38896a706aa9691e39f682c2f28ee9bd22768147fd7c3c8bb0399ba4f82dc1a0060bb7535967be433010001	\\x487f5b33af313e54f949be484b9e3b52b8866a09fc1a68bab3ebd33d7e7c07d7d6013499c602c22df4ae47417ff892da382f3e1640e545c0b98db8ef63996006	1679998489000000	1680603289000000	1743675289000000	1838283289000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
144	\\x5f3d87d68b46b03a6b3858c8fbb281319232ed9c1786c33b70eae477cccec68f3e88c4d3c6f042278850529e5ebd4db3fa95f33d62b9cbe63107e2235fdabf8a	1	0	\\x000000010000000000800003a460247a4f8e5722446213ea594f79a592a5142ac0245655b730b87043f9f44bce8dcd5e35f66386b4cccf068ca47ba94b8e01198af406aa27c1d94390a6ffdb22c5cc5556f39f8263e90aca1817a821cb4850fdae34e00e0e147cc7a16c9c86936a1ec1c838f0a327af89b1c89172ecd3052bda864bd0c11297fae15a9162d1010001	\\xfe86bd29a1c1a43c9e776da28a2f7152e6fb2d728095c98c32b17cc35643cb914cddd6bcd8dcb44800ffadc7278ae9aa1f98a4e1396764fa85bbb1771c49b400	1675162489000000	1675767289000000	1738839289000000	1833447289000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
145	\\x60594c7ef0238a1ddee78b49e83b1f9641f260df66d827e6d285653136ceab783a25f0a80e6bf8683cf16fc0c534bf71c102d5ac09a609435e756b0aeaead663	1	0	\\x000000010000000000800003cc9cb064aa297edb65f4b8c4bb27161a7bc18aa922563082320c5915fd693a5b93331a72de12d8faa43ac20bda6009b561e292b952dc76195396a27b276e5caa73db94a06a6077f13b1e0cfe957ea23485f15eab5bd1ef2f72dd781ebc2adc06a86fac4668bde129120eae43ff617198c98660b81c43348939954677cd84cc05010001	\\xafac629e8f4fdce38b8f4321bd1e663255a72ceccd9625802858187e1773626238bd4fc9431fb7697614c44954052135f1e265478111845908198a0925bf2801	1666699489000000	1667304289000000	1730376289000000	1824984289000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
146	\\x6261c911c1e9eb0233c6e5aaa19d681cd70116d807622cebf3b9702219a689fd61fd450fd4e84df599165eb8d81e2f614ffd969d8dcad7b0b1727121bc33182b	1	0	\\x0000000100000000008000039533e8331dc402d1cabdd4d03c90df85bb9338b903d2db9b9ad681e1aea2460cb99c7ffa9687b230ca0440f622ff8b2ba19d8896e49970d7696336fd68065650c698987093b4e5af8d45c29235bfb215a5c595c6a48629f8cf6bf6cd2fcbf34a61c82ce2fba1d450fd89d3d9afcaf911d82a79ac0f9fd83b9a1d4a2edd7f9469010001	\\x7ec68f6475bdc4ffb3a6d7b18948ebdf30c76d0995336825818fc38684fe92ca460e6632b5ebb4a5b5f376b5ea1663ef945378f21a2123e6f44b86c923c4750d	1691483989000000	1692088789000000	1755160789000000	1849768789000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
147	\\x641d2881d5934bc9a612bcf5a5ad36187909febeafd9ee7502c03c4092f6aed0bbec2c3abe45135bee6da1f5fb158dad1446ba1a8cd1858e8556871d55b196cf	1	0	\\x000000010000000000800003e8545279cfb8e626aaf498a3b54196978d5623805e2561823001d9a13acf6832c7e0ab836e0a4f9f3a541e9ac61cd958f3db21abc03437805c46c63a93b352605460fbebbff45e5201539307d0d6b9266a93984d7968137caf9b813a522ad2976c976f44f24bd3ded041a654aa80f8d72a57705b833bcea7a82f7c3b98bd8909010001	\\x6632600162f2d946068f42033352a9c4bdf164d18d2d69fa05bf54391ff64e010452144cf826331969b034384dc04e90cb3181e15c496d11e86438d26ff3d00c	1668512989000000	1669117789000000	1732189789000000	1826797789000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
148	\\x6561ab2a7e166b87d12c7187ff50214afba79309cf2e5cb9c165a9ec6ff6b266185b1d54a9a4690b30b4d717c2fcad60b4198ac881fac2623bc3caa6ef0e400d	1	0	\\x000000010000000000800003de3db2a17f98e2968a0620b672c255e4a2e904de5d01677a8fd13da4b5b802a3ba8e135bb3aaef04e0fcf4bd4e471bffa0cdd348f5680d37b0ff692d7f7593360f85562de03c1613b5d143c82eb5bf9032765ece385a70848600ee360a757ab10e78d5381cd9b19e71e7e7e0fc15930a56cf3ba48db3a6e9c7e68face464b39d010001	\\xd2cfb93cc4d8d528a3a4d03613f59434911f48643516ce157d15fa611c44ae93cac6a265f8ac64e96cb50ff29ee258c846612a27edb6da37e509aadcee606e0c	1673348989000000	1673953789000000	1737025789000000	1831633789000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
149	\\x66ed5a3868e76becf7e35af3c6a2d15163e61d53194be7f1f8bf0a304937e65c5607fc7c3f3023e51aec3ce598912322c59a7349c10520e69b207d220188a0c7	1	0	\\x000000010000000000800003bd20dc8022936ad6ac58986a69c6073b04bb657b3d4985f262a21d50f2e31d2fe749fca8577ad7b9c7a3419436af90249da2b82615e99128de73a6ffc6ace4355519d0b841eaad9a9bb7efb42ab3e1f4a3e1e75d7b9da0c28af9eccacb2d2d18c4e96dc827e334836004bfab2ce1524b9858d39d28c761e55ceb902b0463734f010001	\\x7e8a7d002886e455595c64c607bd9e30563dab83cef648fa21ee6a51631e51b091ef35787ececf899a053db28b070a97b347b2452b74b9c6be4da811086d8e00	1681207489000000	1681812289000000	1744884289000000	1839492289000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
150	\\x66c9fce491287303dc094463cf12f5f3bad6fbf7702342d5ec44e41182002a9194e3518d6dd8724f8e98d9b877fe04235cccbdfee0da5cdc0f15c371bba4d1db	1	0	\\x000000010000000000800003cc1947143722cc73c0118a5ee7e4b06358e3e2726e8e8f1b8c8b03cb39bb7d460224e82005fa000e994373aa37892a3807bee8c031b25c7ad85a49ddafa50d4b9792af96717c3366528fce76d39eab41fd0779b8d25494a7c09b322abeb987f13340e8ce2fd6ec8831f1c582a02b36f81b11723fb483181d5dbe92ac7dcf3bfd010001	\\x3af2cc9b3409be9474ac6e70789db149ca28202394a324ef89f41441f3163680b59f489dc2bf1a4804a3f2068ae5418bccec946bfe75246ad5f3808288510c04	1677580489000000	1678185289000000	1741257289000000	1835865289000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
151	\\x6d09b95e99a9c9096e125d08eb22ca37c07744157bd03e3f8dfef35c9c904a334b687c4ed2bd83f06cbfda79a3ccef77a411c813768d8bfa7d92e5ff1ad03523	1	0	\\x000000010000000000800003c6dac7d2429f4cea52884f19fd36b823c363427edcbcd579e494e1a5eae99b77f3c7dbe651af8f4134cbf5e966907a2407e621bbe5c709784a77673a2bbf3c5993ab4c9308bcf4fe5afccdb9b064afaa5fdb9442b8bee9566e3a1c43f1437164c6100741c27f1f1b7b9374792ce7299e7fbfb8af8c44894e8cdc7120f180f49b010001	\\xbb656be49361d564da4209df22de8e66d9ab23b2dbbe836e52f27d8c90d276939ff2ccf447d8db7a2fbd6273addf7039615963a2dec855af76208db671d75701	1669117489000000	1669722289000000	1732794289000000	1827402289000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
152	\\x6e8511fbdb26eb2199df877d8a0314bb2b033e1614bfc9a15ea8f34641dfde11b564857c92a528cff1a52dcf9ad244de3cf303980cfa24146f8f329b5498b35b	1	0	\\x000000010000000000800003ca5ea9721d23d9676fa3b5c513088d62da64cdecda10cd7af9e9c3fbda9d9eaa9cfb7d68090964b18b7f246421c5c703c67784f859208c5c0a0c5726dd61c2c7e19bc7e070f5442b63caf55716cc727e6b80883dc713f495549f6cc463c4d491d7811be35870df7c2dbab6c79ceaa4e822decf3772bbfe50672158372692abef010001	\\x1231d26c1987b3f7cc55310c1ae62fe7114f70e37153d40b5653bd67ffe35d81bde201bb92d8d3e18093bd98efe081f8171b26cc575387e9c1bb5b418192ab01	1672139989000000	1672744789000000	1735816789000000	1830424789000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
153	\\x73a12a87bb1b5f8a068eedacb14034819b61d1682e0ca20afae755a7e60b55e15644abceedc8e35e34029c53b0889afa1ffe7bfd0b33da4b25db4931c81d8bae	1	0	\\x000000010000000000800003c00437c0916bd6e09c57a722f93bede5ea460fe056bad65ef25923605e293bbc58eb790c3d3aad33b4e9b0e32efc27778252b8c816beec7d89c7769a77cd6438eebbf70c38881e0ef040f5ef4d3018667700ac1919cc8a4427ac98c77cfc1a9e663fff94e062ba8d26a458dd89982dfc819c8d9d74ae0b2837c7d6a873e40f6b010001	\\x6bdf50ea4e379bd6c4ae2b65020a521f690a3a4ec670be481aa3de27f258f4f4f47c0eb9dd459134d498f534c7f9f37240fce90a9ef31d1155fa99461a772a0c	1679998489000000	1680603289000000	1743675289000000	1838283289000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
154	\\x7525e3f1f904adc65e6ba15274caa8e332bdd74750b6e39f23ee2fdeffe778607d8acbb515ef670015b6375517738cad1f49b0d100242d6e8889f46734352004	1	0	\\x000000010000000000800003bcb457c4c51375883e5d184286e099c572e09f7e70155502065a930dc402d6d5d562691dfcc1e7d4ed8115f70f0be82709db574df4304c603a9aa5a6220df61009973d25639c8e1d4136fff9aa70405bf2598eacd74a2c3dc997c78924a63f2358dc7260ef6adf225fb320d854f3cb93c4e4fddb17702375735b7e7f2c12f797010001	\\x6cf4d8dc61f25614ac16e4ceafaee58574ec343a2af767e8cf2fb636a27af18b32a3734d9c954ff212164f2640c6782407da255e5184b7dd1aac52ee6d128806	1692088489000000	1692693289000000	1755765289000000	1850373289000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
155	\\x7d75b3b7ecaa8bc0dd319de6c6764b2d7f620d63cc3276fcb152f9ac26a0b33ca8105e888473ec0b0ab0360e5cf40499dccd174a0eea1eae98a40576b3196cb3	1	0	\\x000000010000000000800003bcd2a384809043496e17f37a2b9d792c7c45283791327ba49006aa04b40baaed0acab5937564cbf10b22cb16795834026dd2ebe7fe6755511bf42184b63cd5dcf0e2d5415d4048811e386cd6dd5b7ca9374b0adedf753611e3223eeb09f049ddd21859adb0b9a71cbe3353fdadda1ef273fbce2c0f0007a87619b8de96068879010001	\\xe0304a6fa808bb74d5f64c356bca4e3b67437e1574f6ac0ae37faf67de2a6a67e1cf6b4d7184fb812896e8e64c19382a931072d7bcf7a80a364d05c5b319a307	1685438989000000	1686043789000000	1749115789000000	1843723789000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
156	\\x7ea1a69d2f97219fecc889abed971037001567f4ba29abe0bb114db71d522b9a33530d99b66ebc0a9741cee5af2d4f1c57e379e9d174b8bb28b769704635dadd	1	0	\\x000000010000000000800003c1d93fc6be78a6a8b47f3cb96eaa8d7f3c5960a993a92cb27a0a1d3c35c40ea90eedbc1726e9a747dc7aa06db31e8d28e0f97d1ac1691fdd1d4ac99d7aaea7fde3540cd09e66fc32b138eec242947a58b8105e92f93770bb390777fc98731a1c58b21a57d4521044b131361d009c8c13d24fe3e4687c48974b0420c74b1ee507010001	\\x0d991d28449807d6e5ea1e9de16bca541d2f5ef5f5863883b43083adfbfbed9dd43fe78f0e118cdffbbbf9a068ad6d604f22bf5ec1db2c8c08907cb0279daf0f	1687252489000000	1687857289000000	1750929289000000	1845537289000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
157	\\x857102122da26a523e7ba8666b532d9a58d05f83983a20305369e0f281be6aefe0a20fba34ced7ce4df549c48461463e2d31b1848b20040b6ea1cf263c8a2aac	1	0	\\x000000010000000000800003c25ab84620548c206c044c46b14ef0dab1a9a4759bd09422a5afd4c88e46f91f59b3d29293d103189342c6b95736e4304ff741c97bd9fd4ada4859169a5f1e8e23451108c00db0e28e136daf762129eb2b1cf898ab16727dd30beedf481cb414c5096048b394162271da581b3c24c69ac9b3ad22619df9e787bf63ebc0622e0b010001	\\xc81b6d2311f9f73a5ba4c3fc5acaaca4f8680fef05c04b000947fe97f1cbdbaf54d38ae63c354ac2ea3c55e4a169951281e5dfe91ec01481ce7f0117a28b0c0b	1666699489000000	1667304289000000	1730376289000000	1824984289000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
158	\\x89c1927be33cc824082e98e512e31ef9ee2bcf3959b6227f254f9f5b4cc85ded5e2404028e54f3594e6aee69083599fe2af30e60b59b221b74d70f96cc8a1a7f	1	0	\\x000000010000000000800003cc3d77a9ab5e031d43cab881e87efba1317a8e8c61fde727241caa3bf61f52806d2829fde91fec93bc857ccb0e8e54ae5ba388aa11e92a3b643dc8240ece6451032f58b5d94a3ee89aada927d6cf99d9af49bc43250312138a9cecffe73209663ecc55d01cf071f282dbd901de82f933971f287128c60af1c39803920587cd41010001	\\x60d99f45008df0f97ae8da8e6e6b18ec7bcfa44f9d14e12478219819705c6fe9245fce2b7f5f9f58aaf52bae39678b766a8d23871453c7a45771fbda59171f0a	1678184989000000	1678789789000000	1741861789000000	1836469789000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
159	\\x8ea51bee287471e8e9bf74cd93daa60c1afaa1c4f07e57ad53151044fecddeb284ea539d2db9ddb691ce2ceeb5eb58ab24f4bcb195fe47310ec4d8a88058698a	1	0	\\x000000010000000000800003aa8bbbfd52ad0080fd425576faf126db2361d86621632e96d34e30a5b98b6ac92e96b6ea5f1aca57c1bde76366ec5e28e539990d61d557aac446bba6431e9da444950bbf2a5e0fd361504a1fa35d174af8d9732a83f349c9ef45a8516c9141ded749b64d8ef3e7494612f3b72613fd574ae8b511436d43ea724f73d6de8162ef010001	\\x1732c157a5111aaace3c9b823e35d2085fe19598aa6358ab791dd1f318d24d87a560c94f203f384be0779d62ecb077c4bfe62a2d4180f139db270fb644cd3900	1666094989000000	1666699789000000	1729771789000000	1824379789000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
160	\\x9809c4f9094afb896df7f2bca3d2a8279eb6096f81da326ed088b06680500ec944134ebfa841d26750e1113c1fe490e5932ba014fb4f07202aef64ead84cfcbd	1	0	\\x000000010000000000800003c643587b770f8315c62a8c8cb50a7c537de734f066b0789605602daa19ad17b479b6853b10238f03ffce2dd003bc5b1dcee1d921e1f8360723c98da2cd8a9f2863384f7c2f1ae6a77402921d37b34719d0c7915c2f4aec7990de189f5102abb0d9c303debc7587b538120ab621c571ffad9d71dc9f0a76a8d6b8852691be315f010001	\\x1158d2ea53d2c95dcbdb53e81e61255dd72c475fe13bfc4586949e9cdeb32dc5766b22f27ea20bb24a457be2a6e00de78a0eea698531cef17350705c2093730c	1667303989000000	1667908789000000	1730980789000000	1825588789000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
161	\\x99e578f6f84b6b87903db041a5661269265f14bc33c36299d420170f8bf60705d560a2d05d931608dd5e5f097ec750542254c7b7df8309ab17ed0ea008851a91	1	0	\\x000000010000000000800003cf6ae11da447fb2d3091b361065423824f57f95d6faab7ed8b37a38ffb77d713c6bc0711a7000e084542f7466d388bd51e61cf6a005a04cc9dda9a29cee172a6f897d1bec350e1e2205e9fa3be8f695770279f6130641fda5cddc904165698a31ea32cae78cee40184c2d5784cc805447d41fdacbe2d9299c38640b528ef4bdf010001	\\x04dc4bf9a9b276f106d58166ea92dd379d8c0d42f8aa3af5e2133fcd2f0b75ce2757df00f1966d4dbfe489faabf420383adb2d7f7aa4286a498e86c11c1c2d09	1686647989000000	1687252789000000	1750324789000000	1844932789000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
162	\\x9a8d54ed9c3ab691a37c9a7f07cd6024566e203cab2a07abc579d53137a53e9f177c63d1fd3952f73d9a5b81cf5816755aac5c15c0690e9149fb02e1c8f4788a	1	0	\\x00000001000000000080000399e594c63dcf0d14f6184e5c50ecf3c64d0e9abebf582fd316e61bf7b48e4a9a17d8db55bff0751a0afd9d72c782ea92a8bce33eabf09a7fc100e8aa62e14b99726b60d8c2e2a5d251ca9498d7cc825964e3073ca103eefe2b0a8034587662cdddf2eb29c89c675b1bab3ee54864a553e407c730b2a0233b9754ed5eaa213b6f010001	\\x3eb7ad81fe5c3d8ca4784ffbea963e06115ba377c0f767d731887e42efff9b02fe09d6623286be9f79055b99299c2ffaf3c199c056daae29bbe0b390cc2e200d	1663676989000000	1664281789000000	1727353789000000	1821961789000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
163	\\x9ad55057fec085cc8878ddbbecfff09046c434b509200dc2ba74f93eaf19cd0cfab6bfb9a2fec6d7a1abe1be3a129f998f010cfe7644b6a4ea2aa94aa326354c	1	0	\\x000000010000000000800003ac264f591aa837820c52c5e71818ca8755e0249c2d807182497ae12abeaedb67ce360cfb0bd92cc7170bc37e02dfd90824276e1620d56f093715d294cc756bc6b7becee061f6d2b441cd95a05ad91de70f4d0e758a0735238d396a579f3f1123212e57f6518b056fb42621e169d57d5c9962e38efa9f33432d50f553d4fea371010001	\\xfab1ef4d3bfb6b3f3d38aeba464388c3ed1f32034bb50f87f4b6e1da8943d4aec7f0c195fc0e272b2318a3017d461d45e7767d7cb411c4413ce53b01d0b77505	1677580489000000	1678185289000000	1741257289000000	1835865289000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
164	\\x9aa171ca35648e9a80fa73c1c8f2d0304ad9a9c4f8b81af95a9a7149e7fc9d9597a7b7caf102ad69689e598754349b6bc13dca114151278c8a3dbd741a42082b	1	0	\\x000000010000000000800003cc2f145a2721cdef29ca707381e7fa0dc617c55812403497f5b574f2d761e21b7d4dd02e4cd61b6594223845bc968b0b938f74e682302fb71c72d63578ca227a89e8127f6728dc3d6356ef5810b42a937dcf71d060b3989c5685a90e0905931cab4e21fce4567f3098943beba1d056374a2feea455334254c5ac205a7d92af51010001	\\xa3c7207d2baf59606867ab77eefadfc2a98b9ba03aefdc8cf6f4c050cec6365d8d74d7bac76b95cf7ebfbd1fba00556ae3fcac613bcff67399e1fa46d011a20a	1676371489000000	1676976289000000	1740048289000000	1834656289000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
165	\\x9bb1ebd7c85c1a9f792b26ed20c4a9ddf73802d0756d6128c56491ebc5c50517fa1f34ebd99ba75c7f05657a1fcf948f52d55e9b2aa5f39359d1f9a94b162c8a	1	0	\\x000000010000000000800003aea6d3584d56a908b16d48675d3a9a08ab65fc42b9019cdf921096fd701cc7002b63526370a51a3e6c9c4fdabd196133369a6dd0b97c066f5434f5015193012d6b9679956cd39354b08c4b79e87a3d222e5977defddfb65913fe9dc65defe5e5720e732ea73606e1d984863bbce0e07b8f81b4a72239a9aa3d4b5fdd29f8fd95010001	\\x265f58f034339918b1cfdc388498a076657dfa35274e19a9f891a70997b2b25973a3d34b10c5ac9129e2f02229cfe4f3598ef5bb25e8d03d148d986d57395c0a	1670326489000000	1670931289000000	1734003289000000	1828611289000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
166	\\x9b2d3bbbdae726a65b84d1290398a9c5c75cf837a7885741d0bb0226e10a83cec5a1f7bb119dec93d466195464cda309c8feca4d51d684f7e2f180423cfc8714	1	0	\\x000000010000000000800003dff996c8302d63802ba4a337c750e1536f9b7090988f7d1b85ebd5c52816c186d6742b7d0fe3b9e999d34868701eb0b4b76a8f8738345f7f2320675e3efb515c80c3fd2f8359834c3094abcf6f581f3fa622151ee3ec004554b3f18d29a9f971c04fe336ca3f87ee2edb7443b1a5d9ee769fa3882dface4abdef49b61b0353eb010001	\\x106643f3b7500018eb3c314755c3a570cc9d00f13e3904888a8ce5ecebd271f4f4c7128deb286a31e2120f0c66fe2862fb9460b28c3d0681b4ce1edb37059400	1684229989000000	1684834789000000	1747906789000000	1842514789000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
167	\\x9d2d829c9f764decc00274ec48b298c938ce834bc5560b85eb3fceac4b6fd21554b7ed1397ad2e324ead34a7d6d0d1aa460196a2d2ac15bbc4e1e8a49a99ba24	1	0	\\x000000010000000000800003adf5ef28280bd7314ab7d73e443088d9e98c38716540fbc15a520dc09eca228ec6e95d8e7dd51f7ff3352a3e93e3a34b0deb2b6133d990f9d0229309652c0138de47675a2d7da24a2b1e2fbb26b25acf545cdd5f3f75c3be49ac30f5a73a9eaf367010b427e91e32a99a57391500bdfaccb3b8bb939915675fc7c9546c25aadd010001	\\x04aa8da8aec86f681945ae4396185ee0c8af47450dcce27a52368f5a79bef0dfad86e49176fe01d0fba58553d60b16ecdb09a25d0b7224a31c7f87fa07dda60e	1663072489000000	1663677289000000	1726749289000000	1821357289000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
168	\\xa239cc0217143cc2271873f2b6083af91518f0975e565d44e0327f8a6dab6bf3b274e2e40837350f042b099a98b6dc198a8f72fa00c4dfb9af876d87c226f6b0	1	0	\\x000000010000000000800003d58e4c07955c76ba2cf6736fdc890a40f38b6532c2ab57306a64dd541fbf5a5409d3b0ae385e019bf5ab232a6d953482c1f538985e84ba3842ddffc6e5419674f2e12d0cab792a251eb717b570d1a1d4f005167e76a5bac0eb5be2521f6c38be8b4c519dac65590c7fabd418013add35d1c1a71a55c12e8d70a87ee75f762439010001	\\xb273c3a6be91db60c0d82eb96188c2aaccf1888e97c56ff1b861ffcae4a204a4f93ecb9249dab2c2c761646a3fc59d26a809d5b65803e436ce2b9056b653490a	1687856989000000	1688461789000000	1751533789000000	1846141789000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
169	\\xa609fab5ce330fbb6c45ea07cbdbd59636fd132e36e3c9c3fba69147c3eadb84a0099353207595d9d3c5764826c1c7dfce5c516c1142d7b50a5a5f59ccd53516	1	0	\\x000000010000000000800003ea8e520f9724623c2c1bac9945f658cbae7d1b27d37cd001f0515d4c1a453041a7437e9dcb09472bff16b024fdbc5ee45c8e43321f4ba8062b990735a945bd4418c1bb88a05aeea02cda3baedfdafa99086cf8122bbb677f7e5f09ee3d2c3f19e7b3717658c4902355bab1e61ff670147e6582997bbe95805c895c8552ffc045010001	\\xc2680abd2a609d4cf90b2ae4a5c45b60d34bbf163c30a80d5b604502109c1b01795776aff4742125bcbfa38aa993ae33e761810563d50de4921505c07eb3960e	1673348989000000	1673953789000000	1737025789000000	1831633789000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
170	\\xac519ba75e79539f02e53d1b184e25079293d42dbce7d3f7fdc9d9134a6b0ba242ae683772935c3db00e9f53b9d56c9c67fecfecc8a967aed09e47760d0b9365	1	0	\\x000000010000000000800003dd258e3b971a6e9368b7637325822f87afad42131f25ffd6c53b722a2b7c9fcb0aae403b97c477e5e409c37e70130fda857aff6ba9874e20b80894906fd701f235e9dd8e2e2dfe0d47612805e97feafc85b909f220d686369b9c87348c3d0f8dfee41b9edee7093008fe014847c80858cf71043ad9f6ddbf9053b5b722edda45010001	\\x97bd6bb21a9a86cdd287777b5b8be19085632118e666a7eb9acf8927ad626a5e19016f29a765a6f20dd26ff86e467d3efbab61ca618661cc43caaeec5175cb05	1678184989000000	1678789789000000	1741861789000000	1836469789000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
171	\\xad312886b765c052252989535b4d2a07af7fca4bf046ba7b20349298670a029b951b3be7f84afc55f0978e2f3766f12b43d0558562090cdd939ca3a6a921094d	1	0	\\x000000010000000000800003eb9fad14d1322c60c10f24414ba686984d99406e704804ec7d1061eed8ff1b7419b1dd14e7f24aa9328d72a2a2a6e1cbea9d4b6efd54005fb5b932e10b35329d0e5607b8686a9e34f68a25dbe4dc95d6f89796bda8027670178016f50cc7c367ac8f39864cbf5725ae11809d0872650c815d009ab57d88b3fed6ba4a10b36369010001	\\x211e8758d7dce9ecc86ef4108e966c4c7d084afc23d3579c06475f6545686aca17ebe7ce7984f8149dc93dbd3aaaff44e63a6db155f52214299071a90fe6250a	1664885989000000	1665490789000000	1728562789000000	1823170789000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
172	\\xb015fb1629ba5def49659ba101ef92498f3e7c33c6a052a3c0c28292d2671cc23f1a62be71be9e45eca842553ceaa270c1a080883fe3458e852b58374127a291	1	0	\\x000000010000000000800003d764d4683901a5f9cb9389d80ff06c791c3745b0d806accd4ecc84c28f1a8ed7335ff91921c820c7ffdbf843550c69bb9e31d6be24422872e8b65824be1e8f554f0cb8cf954dc068f77e3181727285aea6e2be32babc32dfff83dba7def4d55134e643d63e88c2919c578bfec41484f75835d2c7812c0b5e4580f4c6235fe2a7010001	\\x0dcb921741b62636bac6f1f1bc7a2c165aff01be9ff7213e741d4017bf86fbb4e6d8beca21d64242ae4f90328b88444a0b693b5a89d1192d90c34f9e8d576a06	1672744489000000	1673349289000000	1736421289000000	1831029289000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
173	\\xb13d2764ddc4cfb4c76d443a693c338b153acfa391443e0587bdd6b4c2743618867074ec5245933d94f99e9d3efb0ebc39da8e4c0b425816617d49c0dfac0929	1	0	\\x0000000100000000008000039f2db593eccd2c676310f65a6c90d15644753df975f7b3936d239b3989acfe35dc2c52695ad0e5786a7fdfded8fb6c384bf9801a11dae5dc7f74d626b62449577dda0754ecbd7788219f035bd67ffc91d58fb134780e8480629aa4cb79bebb20a97ddfe7318e295907cd00dace28eb1950072e4de1e4aab9509f28f5700dbacb010001	\\xb3e6376f38e23ab93f3ba53a5e9ceb07d193afcbf1feb4ea9b1b7c02bf88fa91f8fb49c8fc51ee912047c9cefd21f183b5f62b4cf2d1287c2b28077bc317b701	1670930989000000	1671535789000000	1734607789000000	1829215789000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
174	\\xb5f17758ee6cbb01fc7f9a532ac03600772d2d00d7df51844f9cbb72755e24414da1e16be61cff746dbaba66d9d70635428a467d39a496f3519f450e4fcb4f39	1	0	\\x000000010000000000800003bb876d0f851a44cfdcc284350a233e885c41fd458be025a0caa35ef9afd7a4794973eac0fd9ec34228716ac1fb302743004a578b54a5f61158641ad7ef598d2dbc95f4bf90359051ae692ae3ef4539b24df34af20b8a3ddf1d8417361b291d64a79adc499d518a9deea77ea865aea1ba52c5fe578b45f61d3dcf9b2116764d33010001	\\x53e33702b59720bd5236c3b6bd485f792a1b21bd5953e370a3d3f60dc0a443aa93e1365a7d824d17ea61bc4b74587fe3cc7f1243e9a216217d2bbd3c3fdae200	1664885989000000	1665490789000000	1728562789000000	1823170789000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
175	\\xb6b99c56704769dee85b7bccdfd4ce3b7a45ffc9ae5596b046fb3fe756902ef986cb72c933e9b8e35c3dfed5d2a6cca445be609c3d2ea014c5898b68fbbb0f60	1	0	\\x000000010000000000800003d3df73b6283b2dec918312394ff538741a4ce98aae77bfe90a5da027c4e1446eb0b7c4c4d94eaedae9de9f137d19fa5bce0db65604d3ef0b141c24cd097a6a71d7e01b98612022ff070dec44fefb8d19ddef7ab4bf7d491e7f1e945cc30f2cc04372b91d70abcf47b5478e9a87aeee48755e718418bc445ff917e4914dab504b010001	\\x712261fbc0610a19c73860036b3f5a40b47d824a23464d93577c0fc2f752a06dc513bda276a6fcb10854b8e1b21484730e0037d9c0ab2fc167d58d692ff6870f	1667303989000000	1667908789000000	1730980789000000	1825588789000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
176	\\xb6b1939314cabdab75df8fe22a1f358e49acb24709b6a21f72c5dec2e6c405f9ec82a4b91a659b1815615ecc4469bf7ec73ef8af60a955ffd687d028d51a9da6	1	0	\\x000000010000000000800003d7427aa3689eddba1ac67c7e7c6b6c730750dc46c8f4c6989808307801eee26133ba59f5e0f63662ea4263670948a2854df4e1c52358f7cd314d75eca63d6e1cbbe067fec044638d879dddb6b7e43b18360d3cf02455baeca1e0f610a0c51bc130038f845f02f2376ebf6ac7d3903e5052df00a8c3968d1b610963d546c865f5010001	\\x096b43cbbf98836b3fed7c283a0411270fdeef4ee9bc21be643dcd3c11f9789f95eabf7be7238a3768000f4706f050f387a83a96c59739b9bcc835216e80ee02	1681811989000000	1682416789000000	1745488789000000	1840096789000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
177	\\xb775631417c3a07c8362f27ab64e364ef51cb79a4aa377d764370c3e8219a370118b519992a8c20cb53657be014d778e718e5e84995d6e1fac05827f7e49b391	1	0	\\x000000010000000000800003cbceee820542c1d88045c5846c54c6afc7532876ecc20661a0ee6da15b831cb535b0242300dec47d047d1d9dbcecd1b3dde5aa468e9fa12a6d7cbe9c0c6b1deaced6cd40406024586a8ccb8d77a68e935b334506a35ee2cbab964ae170bc8fa6fafd328b818994a81c51cfdd5746b3ff3908f159a4a0519455a13da9bcc83ba5010001	\\x141161ee3548675f021919a0ca1275fd53bfe1e47fa6c6f39cc9c18f9d8b65f226373453079fcbc5d42371e0380fc7dcd4e7287ec12d6b94343322df3091bc08	1690274989000000	1690879789000000	1753951789000000	1848559789000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
178	\\xba99f20d38ed794f41615ab4c04478bc375cebb53d67a19b06d461e4f007b5d67768577a94864061f4952bd1a903abf4d1ff55604d22e7e7bce44ff494fabfef	1	0	\\x000000010000000000800003e1640d3ac9302591b485f3d6d2713a98923a9f32aad81e78a5486edc251b5e895b3d2f08e67f8fd04bb88819d2770e69ad487a4e3a8e6ad1998b39f8ab3cc9950323e736dd50300cc32a8d176d68d0baecdb1a84ae2cbd0df37e027af3271756332e3b3f1f028084b2f6798ec3e786d21f5b7606d0930181d4f1d97eacd47603010001	\\x8b7e8282e83063a00d0650e26be1b5384ac219b7e44d0cd4f187027ab1ab2c139868d44e673a639eba1e7192d7c90fbcef450020ecbc66f970e3b946b808dd0f	1661863489000000	1662468289000000	1725540289000000	1820148289000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
179	\\xbcc9902dd74180f288254ea639b3c3186485a1fed2816a83c4e2e6b9ecc503d56c5a1c52d959d66944e527a5ec9f877aa0c7b407c4d0162f9542d866a0767127	1	0	\\x000000010000000000800003ab5d19030160f87c95e2815985a29a8317cfdbc8d60400097e05fdeedac399e2a6cbf2272cb238a62a8d3b63ed974cb54e38560dece88e4b5cc149aa7af3d4eaa679fa5a0026e9a7e885702ded2b6c3468c83c01358af7463444b285cdf5d334ad3afcd8f734a591e0a6d0a2e26e9e8ff52d581fb6498bbd62891e683ba8ad07010001	\\x0d2b047d2dde9fa645974fdc83bdcf1ae3c565d0c2d3a21858bbf629a75c77c97cdfee96c3627ed1335bcaff9c84bacaff90687c053af5f7811648b344a7b10c	1676371489000000	1676976289000000	1740048289000000	1834656289000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
180	\\xc03de76ad5f3e95cfbb2214cca68ab113b5b68aa584453818da7d1659b79452810716130c29f2c06f2a06ed623bfa59c332fa37e858e866785b00d8aeeb03a96	1	0	\\x000000010000000000800003a763e885aab2a4cd91c42a5da6ea26b2adbca516e712b341d26852d3a9a66fbe431fe52371024b6b109bf75268bb120386f6ee9110cd41debe2c127cf90b9b1b0746cfc79ceb7ea00920fbc20e93c79a19684922b2fbf0cc34f4e0174cef148487e65e14f9ef704be61a68b059fef4779bcc66a62075b1bbf14d374b5ef40b67010001	\\x6c54aad5bbbbe147c6e723195338e799a0b94f169ad53efef27d1a2764b3ed407d06e054c60fecf2259f401eb21073573f65ad873064072df0c2919d9a50130d	1679393989000000	1679998789000000	1743070789000000	1837678789000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
181	\\xc0c1ecd3077c9e8d970c22a4c433f03104ee5f5598cbe8ea070e57b5672a2e1be9a28b9b6b66aabfb14829f351c7a51ef31307243aaea2c8f28f9838ca084da9	1	0	\\x000000010000000000800003a9c407e91590a97a46b7e388603cc1856de913f1677cbd11ea4a4cdaf4240774ee03ac98df77bfd6e29255e8e242c8b8152fb5c22a9ed966f702be682de6762c203f1cca4e634dd0ea10542e36fb3985f87ffdcd48825dddf22dfa41f8d7f511d7d44db6eebaa6d50a5546b4d4356a8dbf3aa0831bdafb987aa694e5a9091b8b010001	\\x0b0a980496c56711b2a777f4d7443cd807101b71b831c16aa8712ada8c81acd98554b2bf5bc90c58dbe7f20b1ace292e2c3f4648ce3ef672be951e3cc4dc2101	1660654489000000	1661259289000000	1724331289000000	1818939289000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
182	\\xc1e10b954410c5e1bc50168a5239d149e95522b0fd4785828bc7b9df36f70794343a476c7b58a5212c56bb6302d2966309263e6d152141e7964cfba28f9a511f	1	0	\\x000000010000000000800003cb053c909b2be20d2f7d593bb5a6e6044d8ab53d1821855a2ab7492e582a83448593cbc413bd8df58fc3cbfab7b240077780d75c5c9b3ae0e4666442b665ab9a980ce2273820125b55b179f9fd204e685cdc19b361ac7343c0f1c77fa024eace60f4cae44b64663099b6cc046000f6b21c8679016235b74d38ce1663a7248635010001	\\xbb3d2240d275cf8930b982097da751bfb30dac42033e3ab3dd060984a2129ae94dfc60bdd9fc73ab6f15c223eb0c82c8b204d5ed89efbfb8dc28f67abd6c3309	1668512989000000	1669117789000000	1732189789000000	1826797789000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
183	\\xc219299a6e209d076131eaa5896b67edad3de4151d253bba75a4b479cb9f10ce3dda750001b232e3de7fba38fccd9d3521a7c4d0ef60804b9d02d54afa9d8572	1	0	\\x000000010000000000800003cc680300d677216381090f06b3d5b50f42cab019382da67856a1b86accb557f7df5878dbc218029f68295aee021afc917f043e79565c7160d35fe7cfb1ebfe4ed853c74e3786648cd332aae8bb13b9544a2dff45605fac7ab3e9d8b87ef63b2082a1758e1910fc555572a236d7d328a82c8af5e8637b68c6e339d25a9fa63c71010001	\\x990574cc27b3b5771d86e8a85e998a88ef5f070947869764e967253f0e4131fa58bf637c4225fd58e3f2f5a135604b11d2ee3ee6ac8059306d175e4d415e2e0c	1679393989000000	1679998789000000	1743070789000000	1837678789000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
184	\\xcb753673280abef1d396179f15b9342cef4886391edb854699f3aaaae0edbb6cb71a394eace3fa750fe9f7628fe61ed6589ed0a06fa7b1bdffe7208f82f8f6e0	1	0	\\x0000000100000000008000039b151cfd886325bd191ba003a9bcec17d2226a885d92a3cb080604b54534da3a7416e526afe7d9f7105ee6e4c2b9983209d71ba791b9c3b3f8ba03f219dff93f7d5a6e8fcdf51494059ddde3d1913804d1f5303eb0659898aa8dd0dd22f5271bc0e924dd58155bc269efc55c7372ab16863bc940524f6bb207cc883b1eca1f27010001	\\x553ca0f634668bf8da2c50a16da71d27e9f9e2d4be5d0a4ffbb4972be1cb13895751755293faabce17787c6037797bf97e723740b71be31a7c97a1a300d24f00	1665490489000000	1666095289000000	1729167289000000	1823775289000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
185	\\xd5f91223b6f18fcadfc3ede031ae46706ac947212264300bafb5ae1417a6f738606bb3c415c57012ab24ee2933abb68bcc5bbe2c5dc426e7f2ba33fd34bc0706	1	0	\\x000000010000000000800003d1092f783a3cf31a4d7e15bdd392c999da88936bc0f52c76f05c1eb2b0caa11ce80a9b18751a744feb85867fdd0cb634876eb17116e0815dc48d957ab320164dadede5fcb1dbd8d5ac0ead02704865a0b83e59528a66ea9d9657995261ad99cbc3309aabd322e2cb116266558dd208ea3ddfe169e6e144632db733c0bd891165010001	\\x36bdf33e9ecd3caf3484d32368aa797256def5541ff2d25cc0274f1d0f435629507497401a60d27f15b86f25eeb91a5c17a4f69254d5961a6c775d101c3fe409	1671535489000000	1672140289000000	1735212289000000	1829820289000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
186	\\xdd259de9c096333ec1d92e5c539ebd700885949e9c7f06d50739a9a9a989eea4761b65dfa110ad33f33db41da0964a04b522c00eb9e85f2b23b97e1617d1b233	1	0	\\x000000010000000000800003be28254f5ee473ea66670ef1038c7cb85a6c295fc1cd47f44f8999d77f5166733704bdf5255c3f4af80d18e337fa8ff9602b3a60e7e859362c2e567286349b29a96f7161f901d7e48312638f728f00f10e7e6f8b4f0d2ca5749a1945b3986a384e8fe244a3d8682943cb63150fc0679e74055049eae2e3f1d6b53a00b9079fc9010001	\\xf9ac76db10fcbc5be5819a1b4b1e6d326d32b02cbd7d6b6b1f3ee2132a234322fce8e4a4137e2572eb99c439ef0958e9cecd7964b578ea5e70368acdd563da06	1670930989000000	1671535789000000	1734607789000000	1829215789000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
187	\\xdef1ae8e0cc832d9cb08e3d578bc0ce77eef297b92d367dfad7df7629d37d68bb762bce44cee8f81af544fc6ff27f1ea4eaeae2c2ff44ecae37ab50d5e08dcf7	1	0	\\x000000010000000000800003b15c9b1504220b780da3980748fdeca8c0e1b64f2ccc6a066bf352c9d30c1c21c23eecec91e5784f73b11892c70f88a56d8c32bae90a3c7faff6efbe598067ffcb562022000078b5fcec971f065087a7b7f6db47bb8531fffa60923c5c02a88bfb7188511eedaef7c59490095cb2858dd7bcb1a420fd9a9aeb7699b70987d167010001	\\xf748ee3c40bdaf51c836db4b3235a707e64402db5af3d05ef6b948f5945f4407d6b7d65e4c60387387f78bdd55b1ff9d5852833309232c49a4298f49e277a804	1663072489000000	1663677289000000	1726749289000000	1821357289000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
188	\\xde318f0b7743b3f794e89bc71ea71b96afb48e60c1b7c03d9cb862ec28eee8bc570289fa8c89018e10a1d62bb4d137be73e13ba0cb979bda77b918071e7c10c2	1	0	\\x000000010000000000800003ada44035f5091e39ed034042340804cf4535fdeca638748d3b17e20fcb9e5d632985d6189feb0dcdb7dbcb64c6dd9596adb6e91629a0856125ed436bc8126c83da02f712d9f4eb951603ccfb9e7e934e8d2a91872e8d6bda3ff6e35871bc1f7c615ca2ddd323f25824523e6cedf99acad9d9e22df88e9e17b7d4a0539b9bfd73010001	\\xec29ca8d0fc2336f2b5b8b92074b8941fa0a0f2e3a795ae23d72f8fe180ce588c020d41f92df51c4ab285e308b26a16d858102fa6b25acec223d4519be87bf00	1692088489000000	1692693289000000	1755765289000000	1850373289000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
189	\\xe04dd2ab9d786897af835b48a3e61582e24b79bf4f8128f69f171f999ddfb060066549e62e8ea7a8e4dc9f193050d2649f06f82a8d0d823c498639cdaf7f6df3	1	0	\\x000000010000000000800003c49ac1af8b86f5b69408f52702e2bd86a5f3c36f786e45b97ecf71e35f4d8542e5ab42f8188745b30fb0adcd0dd13a5352efeb9db5c81bf2ff042f0137330fbee7f56839a3d316bd2656a0af2211984e6b1186f6ba003245b672d12c1de5d67c65f5e0d5d8a1d519673fbeb599aee37c424814be6de9e430c700f1626c04070f010001	\\x21993f4af31849cb1320762192d01b34f2945d3e2ae44ed4cc25cbb7c0feb38336536cfe8cf34be2a6de5568d875404de0427552a20eb0c33d1b5033bcb15900	1669721989000000	1670326789000000	1733398789000000	1828006789000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
190	\\xe2297a3399b84ee0eff9082e3e234795246c7e51ac2452484deaa204cb5d81cc7c1a59c08d778e36f235dae334e58e4876e141fe8fa78aae0612fef5232f2434	1	0	\\x000000010000000000800003d0f72ce3ede2b5975febd094491a10d5117f0eb92b5045430ba45f87527bcebbe349662d2e7de8e3ee739f9d70c65cadaef73e5a95ff24df56b810e92e2978540c1f905001d88d9567b0f73e0e8607b6d1b8eb15c2d28fa0906c17ee22e96bf59dbce7802ee828cc5568dd6d006d7f1189beacfe0c9845d86d2115e5108cc7d7010001	\\x5775c62eac2baa12d68509ba409a3e75f529601ce9e8025a05ae2d163125de7057eeeccb07befbb20fa263e1155c56d9df6b609b10ba51fd584c0dc45a703805	1689670489000000	1690275289000000	1753347289000000	1847955289000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
191	\\xe49953152d7d344f7ca812745b329ead89f563be640e8664d7a3ceb13b5773dae4149bae3836f8778b461593ca0fb7d73de34db117df72b31f052348b08d6759	1	0	\\x000000010000000000800003a427a5fdab8c25a31ed1ec5c0592da2bfe4b27489856311904d7057cfc1db9b635e03fdbeedf3fd8083b9426331c4191ef1570f9e7bfdc9c2b41c7ae86fba582957b293e93df247ee2561f3d40a5d7071e1e73e3fba9f50ce7fb6e7817ffe8bc9703754ba6500121d1218233c0400cfbb5e6840771680fff27e655bdfc888f63010001	\\xc7e6eeacfbcfb49e2d409d4fecb52bdb45f235bceff6924718fe032aca45b64cfaffe6a5d3a1dc47a9244bc2ed4252af4abb6cc1067243e03f2d3bdcf9406d0a	1670326489000000	1670931289000000	1734003289000000	1828611289000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
192	\\xe4d9d21e9b07ffea6adcd99994926285f143f798726b48281bf7a5226442fda18a5c88b583e6aa78f332ea14aa8dcf3b19627f9bf40a32de7c8d46c5bd57e5a5	1	0	\\x000000010000000000800003d3f613680322c778ca4fc132e548c7ed21419b52ed605c323b8a1d1ee94e54de2c4aef8705c5728bdd2270fd6801f92fbd62d52c04180c0d473eb8b0b90ba0615f6dc4c5b21679768e381598b929e34328bccf1b2ab9a27e97c1ff72d177dbe8a617bb71c1a7b9c3ddce2527ed505f1a1d10c638f4fb8c1b93b3751c9d80739b010001	\\xb8db2f979f3affc7733afe743fe924277fec9dd1ad9e372c6ae96d82807abfc93ad9492fdbd2a6e50c147c883fc3a52af58c99169489f8d722ba425cb377a10b	1683020989000000	1683625789000000	1746697789000000	1841305789000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
193	\\xe84d4af5520a55bff91584475f8e11bfaec0597f8e2e4d429498d97e57ef849a83e1a21cfd651a4bf280a0cbdfeea39416f5f964d1921dfdc32cba458e697bcd	1	0	\\x000000010000000000800003964b289a0c51f9c57afdc30adfb068b4cd0147bff8b55da5af66d91e5b4650a6e0b6d8f358f04f5f27722cb78d97d9c95edc41cb16fc51438c1af3d6138483b0c79e225991014d19c7803d7677e61458d3c5a3b158b83cf40138b3f690299970736c895ecddfea82e8ca104ab1101135cd6e0a4ece6cfc55b190b96e0bb5a4b7010001	\\x84dcf88385a789aa1876c982b323a4ee0ee6f69b9313c86de9bf5ade400ea9ccf5b349fc1ec585d087f525c78a6bac561dc1f8aeb1f60794177f2048ef3a7508	1661258989000000	1661863789000000	1724935789000000	1819543789000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
194	\\xf259555f961283ff5fdb6c1d1703877b7b6dfa30ed639f8744e62b3893209c34d6253969a34ea1c53668b413a1922b1fe43157ca2d2669652850d7751a8afab1	1	0	\\x000000010000000000800003a7827723b9cb91a1a1f8cb31a75ec1869bcbc96ba3bd0d368b5b9de8be45138c160a2106329fd9a00ebd285af9469041603cbd8134fb0010bc40d7b4f430f882965e073d95521464085fea649f67e5b258496d805c6bbd9c357be6059e678e5b4460bef62bb7407d4b8f8c5b6cacfeb51ff5693cf8475d0a46e46b63c4d17ac9010001	\\x7ce3308eba9f8f74428b46ccb485eb3d269e1daaea1984300a698fb28707bf08a1c66e7779916b9be5bea95c14e63fa579a72db848f799026bb9419e1d73b60e	1667303989000000	1667908789000000	1730980789000000	1825588789000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
195	\\xf81140623179e31c5f82ffe933a9181e3f9b06101601635c9da1978dcaf432021da4d9b53c9f2f79ea723a5fc849ef3db327c433f014a35f18da00ff8bf169c0	1	0	\\x000000010000000000800003ac9b8f7c5f31f8eac59b59076d271f68baa548fcbecf070607ca230ed0481130db3ea7e1e6b124bbe4746c954074eb600a611b0e6dc3fc193a1a9444396403d6755abfe0fe9fcbbf5ef039ef6063f3f7e9c09ec92c72fb8e39f1de469cd696984f2bafce0a532025b1405cfddbbc8ff56ea93148ae35fd5aed9e7fcb129ff7f9010001	\\x7b67c42cb5370ff21981a68242d09f20ab880a0bdaf16b1b808015960d5d2eb57946659e6d86a43a9bf8e34c3e1c29775039d3d5eb8c18bc7b2e4ca58eddcc02	1683020989000000	1683625789000000	1746697789000000	1841305789000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
196	\\xfd7dfadab608b8b77e263a0590158bf9c6ff4f1cb67c46db36c41fa2d7171fe519a2eca247763c237e0364a5e33eeddc021562988895143423681b2bc2410a6f	1	0	\\x000000010000000000800003be31ac268af79bd15329334364f402b5dfcdb36106ffd5ef438384fa0ffd28d527e1fcf94179517641fd95a6acd08b0e7cf5e49838e298001dd772687ff8b587e943a52f55a9a95dfa1f3c9fa54a398f8268a8877b2ddd09232455c980330814fcf9f52dc3201d35be48f26b86d59d2f7beccc2cfdf28c7ee09a4bfe66cbf439010001	\\xda16e388506824a3f2def772b96d8804a8dbf7a992e64ef0149a457bcfdc1549574f3a62c3f93328b236a39ad4189dba043f84e987f671fe656b1d907c039a00	1673348989000000	1673953789000000	1737025789000000	1831633789000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
197	\\xff61d4675fc4c46330cb1ff06fbbe9915826a86c06ccd7b9d83f8e29cc298c4469d9f043159a728c8309d2571e070808db82789d8c8e1bf61868807abef318c8	1	0	\\x000000010000000000800003e0eba8f3c9f082de42890de74fe4491d3cb5ef35198d8dcdd893957db62bd770c4629551f6ba7644e544ffe70f05ee284f0c9ab228d448f61a43d2a8f3ec6d790744143bf3d61b2f8f0559a1bcbd34d197d56ec97979514ab46c68268a2d51a1d5d0152458c5dddd043fbe47b8c5b56808ccff6c389a048dfe51303c9c175317010001	\\x7e3bc54bdca8eaa9f0a766d2d3a09ec611b77d69293b263a4827c838a9c9f2eb3467fb6d9dd3171a5131f94d67194d65c1609a58ce9f827ac8e6cd43cc8f0804	1669117489000000	1669722289000000	1732794289000000	1827402289000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
198	\\x01ae0c39e4cb844d93f9be06c2fbc1cee79e24927a7e6d8de288018c2544ae51d0d572d8229bf78ffdbdd8cd1176df49607981c464672f255cc68db7b4a9f18a	1	0	\\x000000010000000000800003e95b3ec896fb91dbd38c9ad3cd6a6b8e12c3c472ee8ca5676ae206aa7cab36a286ff9cb11bfc72564f634f3da9274988d403f6651da79660f4525a125686cb09b79cdf197cb0914725654e8c58cb7e2495655e6033e70c7bcb356dbfe0a76975175a946c90a7936c416fadbd5314792c1375e9ad90f3544bff98c1624843de01010001	\\x50f4f7c0415af0361a00319d60fb77d0735814cc397d54303b448f6d28aa66d85078054a8256005e0c6a187e4f31fa1b9633c06d3378ca9ec9bc02977908ed0b	1677580489000000	1678185289000000	1741257289000000	1835865289000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
199	\\x0682bc6bbdb9b65961e24a76d8daf9701c3d37e3d14d365c669621edc15bc2e5140364520a0c5237e3dabf2199632f793ddf829973aa3fcdba0460b852efe92a	1	0	\\x000000010000000000800003d529e58ecb8a4f069ce2fa2c38a07440f10b75a93154d1040be92f42599698a70e2167ee05d09b833884cac94e838dd884384e8ba733b371746eb679f6941fe43f6712d8b2b106ffc4b2b346507b96ff3d761ca016494c36f814d9662b508301dd5e468cdd12d3c2cbe0f06d223b92bde872dd15c7eef76309844e4f151e51c1010001	\\x9b332bf204bd465f6847677756d099e3a4a4de89d2c7f9237d0e193e61f472aa0526beea09b9b10f903aff7526938da262f4e68fc07e382ef76f3d1b081fe408	1687252489000000	1687857289000000	1750929289000000	1845537289000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
200	\\x062ab33e15d7defe85e7ead97b72cf47f1bc74ae11beca4a5de4ea1db47022d9ff29285881a14efd94d2851fcc362c90d9f0ef2c4faa14954437f1b7fc8839a1	1	0	\\x000000010000000000800003e883793808c36af821a6213ca47c615752b3cc7348ea5cde821346455f428af24e5f170d59d9eb932e0aa55089136c567c8a14ea6d2aff99456e4f518832b0a3a602d6e6b72bb0a8f74c48468a22b43f547ecb8b0e56a24b1ff7060d92e2e13f8dcb772bcedfbb1a32de7af00b1818a83569d553344678832e93c465b05cecc9010001	\\x00ff59f926252af2511240e404ae8f38b24ea7be830797dea1a9e50f5268f3b89798d6d5e9e25918e1d493d1d4754d034da2bb1e7afa8a73b7378f1780f4e004	1680602989000000	1681207789000000	1744279789000000	1838887789000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
201	\\x067a54a58b000f713764db57909f7d34aa3a98aca22754570b687a0b62ef1d13d31f34428fb2a63586eb6f7863a6f0345b302b2d39d28c2553a8b2392a0c9c22	1	0	\\x000000010000000000800003a8f0b277a34df5dc17ec0d7da38841acf8ba61ea9a16dc2b66c616682becdb6a696ae9e3a310269109818fdc62e4ac23d26f4b458e57e883c2d1fcd8567cd4196fccbad2340a1165d631d0f44ab23aa46f6a7f447558ea6f94b204f064a480a24a229ddb799c1bea7b153db473ffc5d228f62db4f2cf709df828186f22cb9767010001	\\x7dd4e0f3f5a8e6620e27cd9206376acfaa8a5456c0c9a98ccfe83d9d67c55824f94667d9d923bc5a111806246b1d09a24372832d378b022fdb6c0312a357340f	1669117489000000	1669722289000000	1732794289000000	1827402289000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
202	\\x0a2eebd6d8f1fb2716cfe368297da97ce4fcdb381166bfc5999af98dfa005e9b6baaf6ac9171829188b4e556a224e40a95827a0bbf1e856bdea1b0986b546e06	1	0	\\x000000010000000000800003980f100fec9d95a9ce315f0d4a16f8a8074c66bbfdb16e6b31820fcb6f74465051839679bb40623d8cd0d4fe29f02fef0d74bbd05a9d97c89ac6af06cf085857499b9691604bae84f1149b4be6454129d894b2afacf73c4b5f3e8ea728ab1fa0c7c24c57446944cbaf189f4c54d5a10f5925042790b2182776fa246b4b091523010001	\\xfc28d84d004c296ed51d99f6394b7dba0c8823a60dc54d100f9c1b7721e21f12c0f71a1abc11b3340f6ee9e4f637cb046e16627fc0f2609d74034c2365daef0e	1690879489000000	1691484289000000	1754556289000000	1849164289000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
203	\\x0fd63fbd7179598122e8ca4452961807e82c5a682b02a191c6600837061650a73c492dbd220d5879e8e2c90ae3be564471c2fb6cee11dff30f8e903a530a84ab	1	0	\\x000000010000000000800003bd08dc96c54fe7f7a43a3b6ac79c113e4f9d0b2d0da808535e0b625b0bfe48ecf498fdf683321356575602f83c2c32630ae065fe87eee73231f3f672a1c6f91e839e371e36daef752a5c3c1b5ca54432260734d784f1938bce337b8990a7f21a1ad675308da16ded4080c5d27b1827aadaeb92ca787084e88043e318b7fd2af1010001	\\x1cd17d686758fbf45bbb5d3d6e7d9aa32acfb0b9e314df63f74e9a532b72636ac0b49ca74dfe36938e162ecca11e076147b5d759823ac42512ccba5705396207	1668512989000000	1669117789000000	1732189789000000	1826797789000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
204	\\x10fe56a70e4ad1d1f0ed2c1af39efaa283b6827be812daed94806ce0112e5273ca2d8170df975330be2c0ed0f754df0187999cf6f79d9079b4a23a0baa2ed8eb	1	0	\\x000000010000000000800003a4a3da544df487b8561224da248f0222eb8721659bdda2521fb8649d5695e0a2ea32c2870358e35b274ec1ae7868670b2993d0a73880acf399429bca29a48f7cb043a4ff787ea27266a304146854e39322587eb4f63313c38c9bbd7d5cec9a9135c64bcf2aab7f296affbdaf0c49301b0a90677f6e8ff17c217cc286fb08008d010001	\\xc100b843fd011bf2a3ec4d064e91aee9c9708206d2e495617995dedeeac59e57ffbdc088fb356162784b436b6d41365b247aa2315d950f0b6291440ea7ab5b0a	1669117489000000	1669722289000000	1732794289000000	1827402289000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
205	\\x10fac7b8f69513632d5d28c5e3fc3b89aca5d50380aed07f97066d431a63164c7ab6e38dff6124a1a7f5e12ca27aeda56b5a2b4b70d2752774e72f3a7b506399	1	0	\\x00000001000000000080000397cc0dd71ec6a46a79e45d68bd59395ca935ef852b78107a6ca8539d3941248a3e4c7282c41425fa436e9439039656ddff755f95cdde901f2c629707b5f50c5d723a70a13b8b7f13c66089c137a3349c508a88caee70bc3f84856ad0503be2532f3d7b9bce0af47aa43c797a3d6ca421a0cd9486fcf166bba9b5984f59ccc345010001	\\xfd4eb553dd96bd7d71cd1ec5d57f38ae55f02e6ee1af87c1e70a717c52070607f8f4003254132b1f157e737c82d0d35c41eda7bbc6c00642a50983eb97f2f00b	1680602989000000	1681207789000000	1744279789000000	1838887789000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
206	\\x1692ae0e79633dfc690282e0dd3427d70c34b2ca8001244c0b7b6b3367fd3450944221f3e78e3c5e46b2e8039f71ea827c9dcfd32541503a4a779173badb8716	1	0	\\x0000000100000000008000039bb8c3519da7175bd93f80f5cbf9f06adf83f9bd3483419360202fe61bfd01f698e080d8467a5f0857733197b97b9b728d99b2cf044034d0c1759c28b6a691f18693ca2c8ff1f0fe1fb6d3c037cdd73c478a7c7ac818e1003c31893ef70b5834b717cfb3af98d38021720a629402b2903036ce76899fdee8a90e6a9e976bbd31010001	\\x28eddc784db62461aaae68edc4edd4f78c8781f99cab136b10da0a19b4aaa65f8e2d0e7022816cbf3c8192d7ce2ef087e7895d96b32f3a804b189728a25a850d	1672744489000000	1673349289000000	1736421289000000	1831029289000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
207	\\x1796fbd95c3d5d54b5da550f4fe38f53390d23f3aa27434a2252a14e769d30bbdafedad9ee6f6fd0e90ceed2b17a193322fc78b8763b962d386c157d31ef799d	1	0	\\x000000010000000000800003b9e23d765f410c155c3469f7f25cb2e7331593f1da914fdf6123f7cbc756097015483501a590ee923082ca13315125cd5281e815571bc545fa10581910a6397e92a1ec148ac078adec1592cb063d9e868aa9018f37e49a0fb39ee83ac9631b1d571946a12654eb0bc8f804a6710e6b00fd724f2e795e26bb0389c67fab6694b5010001	\\x3f6e075c1a5c88215f4726ea09d7b2d5df3a0348bc16e23755f1d4700fed3f9b8f118102837bee66f4b7e3cb6129e71198f17158c30626716513e6ea01887008	1677580489000000	1678185289000000	1741257289000000	1835865289000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
208	\\x1b8e176694093b2464aed2fe42ac33728ed0a462a75b864939b1aba2cf3e97eebd5534e6b4eb3839a514c408025541f2b81abd5a33b3c09ecf3602cc8ff1efcc	1	0	\\x0000000100000000008000039b1fadf2204e30eaeaf66c3e0935d9d9b164682d680525cc995b21c7cfa1c1fe69a7b987066ae1d52f116e2d66445b4dd5bbfa14e987912f8ccfbf901e3011308b8e590d25cc03cd6564d21c9bf2673fd1c99a0b1bca59c369a29c4ff4d0e64a8410e684a7dd2beb36e1338fb6dafbae45777ab0298e74d0d114e9f1fff6e6f3010001	\\x212831c080a4e0e74512abd3134786b86e729d43e7bef0ea60dac45b1ed87e7e4565539773f7c03bf98129693ac209039021aaeff3258e87ae9ca9aff6d56303	1679998489000000	1680603289000000	1743675289000000	1838283289000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
209	\\x1c96848f7366c993ccd281fe27a034978a14f6f6594530f807d713733a5dc23bd1bb73e82fcd88a69dc3fea7b11ff5cc9e57aa60b5b5fa5f84b9cb4719a3d31f	1	0	\\x000000010000000000800003ddae530282dad64bcf200b524200488aa99da049c75be1cbd4e1eefac5ef191307df810712d1f6a36318cc026a579a2f544d7b5a9aeb097aba5be636232768de401ce81680d2ecc5c30a4b685aa43f15994d395f75bade0c3a5c315b1b8a8f1c003330a240efbf9a441d2142dc8d3bfa9c821c4842e994016ea6d5796d775b21010001	\\x49e99686eb41de2954d3f14ae66fd0221c5bee6a485929511f11ef933ae2ffcfd5b8faa93ffe9e37b4e8fc0bd5c7956a001cc235b8637fd3422fb715b859b502	1687252489000000	1687857289000000	1750929289000000	1845537289000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
210	\\x1e02ab7341ffa9cfd713124424c9cb56650437539f81b3412de50f7afbdc1d542d2314ac9fc6e0b7a8eeedce676879527669e2b9b04c1434a93cfdff1b00a2ce	1	0	\\x000000010000000000800003a99c2fce1a330c4180fc39bd8187538356d0169ae6af8e69e9c744eca08e2e8f7fa027212505a5e532ce99b7ced7684e5591344b69cbbcd1cbc0034ebc8bc0cfb8eb5c0bd3e35464056d7769fd1121e71cf1bca2bf0cedfeac79e3705e288742cc576bfc9ed1bc7eaeb0b0d3f11fca98b2eaaab47c7a95a7190a4a6b80df74bb010001	\\xfbf5da1ac559705e08f466aef845a103095c87e55cc4a91bc4587293cef5d9d11dc062c1f3d3e75aeef3436dc18de31f22b1008ae71057f2c55929bb10e6f702	1660654489000000	1661259289000000	1724331289000000	1818939289000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
211	\\x1faad3bc6114840d17b358eacd07911e959fe34735f90197cd0113e247887ff614621ee6a93bc9cb4f74bf54418538bcd45b323766ce3ecaf8f029b8603a3ee2	1	0	\\x000000010000000000800003b7786da675b693d02abbb0c1a5c1cc91490ab51adc64ce295ba2c7e91f59c419c6eeeea9df67634a084c5d9ae23c29702a606e384e158c6d412a604de0504e9ad263b8bec148ddead2b7fbf05ac747d6892ea17840c80ca43f0c9fe91cb881d3200524ef6e0b5beccffe02f2ffbe50437152f2a6f4ddea122c6d5d8b2d301737010001	\\xd968a7cebc0c4e11f2c14ce91f0830086085252737cef9a3c163f6daf95bf6320e2aca8ac386fb6be95b6b2b094673b7fcce46bed95533d250a231f540eb7f0a	1685438989000000	1686043789000000	1749115789000000	1843723789000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
212	\\x20ae619187bd6ebda5ce9f38a97d1e7a6ddec7bb4bfc0d72000333de4b7352a5b8c287c6ea3a00f3f5ae947fbaa56758409837ba31c9cefa865768acdb19e9c6	1	0	\\x000000010000000000800003a9a068635d3bae2641aded73b7b50182b7e9f7f2c4f8c49e7ff1aeed8c7b2f6b0e7f2df6415a440b65c82d3d3d3613673ea26e07126ff9923f142ca5442a3a3a86ec0c9d8efd18cc19e4ecb99c50acf97d997f69ada186e02f527649d77f213a8d288851de5b22c0ebf7880df751845419f22df85f5434b810482aa26da6b537010001	\\x0cb62ba966d5a5ac1db60097072db7a489a79183eedb772c0576df90b0d4aca36fcaba76e8803b5aaa489391d0a27c85fb97412550669d6cf509ad6737b22307	1678789489000000	1679394289000000	1742466289000000	1837074289000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
213	\\x2136dc5224dc54e0ce5250ca8f2975dbc2773268464b83dabcde836c0e0de7ba01b74eed7ce63dda46b1ee614417719385e97cc9db638e826daa4337fb1eeb0c	1	0	\\x000000010000000000800003c65e3a28df2402750030cdd7662494202734574145fb503205a4813c083278d33e73337778ffa7fae03651e8a0aff129b9c2eb2af5fa41bc4cf3e45a078ea9939cef05de1258b7c685d89842cf54b6761270c0a177de279ce4fabf66d1014244b380939038df0b1e6a03be65a09136b43a29bc2a9cab74fb62812c4ba0c8e41d010001	\\x70ff25173e72414895bfbd41c8bde41ef288dd2e920722b65fe458502d5cc0508277db87a661f9e64c23394b1fcc1fc16d2e98072ebcf8180d30c391684d170f	1679998489000000	1680603289000000	1743675289000000	1838283289000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
214	\\x2776f705fa0dd4c45c0b12d77148fb7fe4d281564b0b1230cdee7ed71c0d7ea48c7d5081c2c6dff9358fcc14d794af5f5d9e314691bd232d814fd38b6cbb0051	1	0	\\x000000010000000000800003b538d6417e2519c30c3428c13523d7b2c77fc123642d42c8f8e63ad240cde3ada8e55876cd21ed27d5d833fa2933f91a8354f05b54336c2dbf75d1f079927776b71a072909ec78ec9f81ba80329d6a5a7bce5d6dff4f5cf1d7c15961e889a1231462b85e07bb7000522ff6b798d8c9e9c87675349f51711822c6a6e9272dabdf010001	\\xce9a479f7120b656e4ef48b83eee7ca1a9f064d58fe979b1f36ad7d8db2e8998f1d8860ff22f2c4821ebe06c573d05e1f4f51c10d2bf5a429b37fe28ffddbf05	1679393989000000	1679998789000000	1743070789000000	1837678789000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
215	\\x2a5e3b96ecf4ea210fedb38125cdda007bf157e9502ba410b34b3581adcca35b508e80639a26261d885b180b0a449aa8c57006047e6970e6e966a62d7bc566c3	1	0	\\x000000010000000000800003d618fe69b99d79b6ff41368ba935abaf2fe54795001249458a1745023be89040fa790bcbfa66517a005cdcf02f53d5f6e22a7d61862b6ea9afb87402c4c17631884f7bbadca7932b080a77913fc26e5756fe402ff335c4b42cc8d31d0ea48a48e74e811bce32dc77accf14bc03de17fbde16ab6db926f77a9132fe72a299545b010001	\\x45f2f7305dc17e5f887c2d7c0d87e4ef871f7e88457afc47e0637109c1cfe623881663d8baa09a7eebb33acb04c4eb9a6e1aec85bb12006b9f6b61822457890e	1675766989000000	1676371789000000	1739443789000000	1834051789000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
216	\\x2b7e43958477c73efb3f03fd1b2c02305ea5d3eb6f261a76061cbd9a57ddd4a641045b36acd901c1eb64a9513af270e27b62ebe9f3ad7005d67c157d722e5264	1	0	\\x000000010000000000800003e6667c856c49cf8f27a4f32e806ed64793090204879fa2eb0bb6419e0e84af30d0d7838bc0f1d7073b6e8ad3a381d318428c0dc6c4a7e2c9103b90a4a37e599605db76fbfb9151df8d24e023ea919834fd19a5230e8139229fa6e2aaa2eb3bdf9041d3d1d40c00c63c3e06f5b79317ae60e61860a76b6a80f8f36ff4734e1fad010001	\\xd2ccafa6f772f4e9499aad5dc86c835bad859ba58f095836860f09736c440f1b2aed4d822aa2b363f68bda2985337245ffb5bf5e8ac250c1fefba101dfd56e0b	1689065989000000	1689670789000000	1752742789000000	1847350789000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
217	\\x32060bce4abb1ad173e39f266e37e3667294c298a22cf039f78f94f508b41ce62a01a21a4ea6b9baa3485a0f2980743fcee100bb7e9fd9880e8ea20bd8d6882f	1	0	\\x000000010000000000800003cda08834f4f28f384ce25813f4a8d2c8f730ecb178d2bdef94d0f74685f3c51d4b0d8348a1eb6d905adc0045497e4dbbbe4d841c56b190264025b20f864b2c0e38c2c6cd0e9bf5ff1ca1bd49179ae02f2e50e33efb5adfa9c1e76fd890ed2c0a4bdc835147a8dc92b7453e38c2246e8a747cb069819e906e00f72ad6c21bee59010001	\\x375dc2508a1b6104471955c09d75ed91a947a9d2cd7af6fbf5189e4668c21895f4c6ba6a18df5c4ea474938fcd91595964bef74b5362319c5b8bd507e15d8a0c	1673348989000000	1673953789000000	1737025789000000	1831633789000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
218	\\x343e23607bae5f9dfaeacd549ce67572ca97b707c7fca0eccdc637bdd620751ac6538deb508a5322b1917279d65b542cf7904afa3abbcfc33c745359ff610bce	1	0	\\x000000010000000000800003e99d208d92a370a6e068fce3ffb3509e3f02d56800083acf8430409bc8d19206ae44ff7aceadbf005b08f8930934e029f4e7a6a95f432361edaa9053bb3460c170063d2c95e602effc350ca0c28b890dc9d7f1cdb2af4464d2f45da4ee2f318e1e01f9dcf44ab171ebb4c8a75637c495799a17aadf5c1fe03ed647aac246dd49010001	\\x2ec2183f3c3f210becd80a321127fe08ef698dd4c0b4d6441c446f6e0534ef35a3970deca185cb06978fe33993da8da9cd4f3e7121cbf65a76032ed8ca54c006	1673953489000000	1674558289000000	1737630289000000	1832238289000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
219	\\x3976ac50da84a983b388421f4cbc42596ad828163f025dc891815757e832acef1a8c69467625f93157a72f4ef7288de1610af21962d569d7293338ae6f3897f3	1	0	\\x000000010000000000800003e88346be9911c491375b8f3e7fded91c4df00227f9f910eaaee1c021f9292ecfc3e06236296b038a9cfa01bc625d84d251ce58d48c328caaaea9c62bdf9f0e81547c76c4184ea811580643028e05f3d2527b7afe9c49d9e622d272fbfb423803886467d45c3906a9a102ef3ea5e673bf093ddcd523c93c79405d6f6392e6519b010001	\\xee5c542b6548d3b90974396d5468e803317914af392c3d3df5daf95a3a103b73702a2d56cf5f1bc778cea3157e2d523f7ccbf629f2cf004f2306f1b8a52f4a09	1691483989000000	1692088789000000	1755160789000000	1849768789000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
220	\\x3f52b9d3ce6c749b45b1187fac25165a757b68c619358c510bf4546496def0840b483e9a94ac8dac86e4f36ab12d1ddfe8f7cae1c091b7f5fa427850c0a445cf	1	0	\\x000000010000000000800003d81ee71679488d82135f236ec7fa06ea8fc8abee2d84b9d81c6fe482c49af08e3421d0c50a7c732e97579740209b6da83cb431d9e911e275e8c8241c654db2ef677d2c258e1a927771bbf684b8af256d4543c28b568745ec21f1a92e8bf42b390d185d21588fb55af54d4bac1f1d47a0f71f0863a4b809ff15e834413b120af3010001	\\x68bed5d7f76542977e2c8640ba6a77cc5d0293538dd6f77713a21982a035809a6050166a076474cb6b77fd0fd5ca9271172bf10682382e1a12178793e909950e	1689670489000000	1690275289000000	1753347289000000	1847955289000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
221	\\x40f67b45a63f95b96e5ee2e4909a3f7b486d633cae11bc7f5e4b663ab8393000b272827edbe0ab3453363695aa7777831d814db364c656d7ec8167e2babc5567	1	0	\\x000000010000000000800003bc23b2d02bce34a850744b758c875a9f5b6a88c9f9a824b179fd17f577354470ed6b3b5e8721f52f9e2624f4afd001f20d24b5f4cb666b2c90c88f2aeab8ed13d0435f9e34e0909cce82fd961593d48b4153e8d82e9f9c7fbaa078d74223b51f94b2218e30c43f9588c37c8e07d63860b3f47a973a484053c83f37fbcf1a5a95010001	\\x7175a435c596a97733c2c8445663d52cc5dad0d9837be04c010fc18276061b4b67fbe23eaa8ad226ed03ce108bdfd48095d176ba274193a649df219e05e86803	1669117489000000	1669722289000000	1732794289000000	1827402289000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
222	\\x40b6bebd9a1fc6b519f6ec0f19c7429db1251309a539b88867b6075022bd0d39cab125328c704fbc1db86fad041e32d2305339037aa54c7465ddb764e6664731	1	0	\\x000000010000000000800003ac54e2f9b01e25539e81bc78fc86c6d69403024378cf142b4453df938a45750b2dde61515a2ea3a5ec27f7b8fd3080da2855f7027890d88d505ff295b0c54834183d72c46ddd647ed51ec6ab9eab5a517c63bdcea755492e458a90d1c1c167a52c3801a312ec8c3716b67730499fc560e09cc70ee6cc9444f4ed00e450a62769010001	\\x46a43d1e121323c54fd6fcea04f3468ea444e1823a1dfa10d134818484ea43a86e7c2d88bdb94ff20f856c259baba60f535729e6ae9ff1b131e68e0416d4b30f	1685438989000000	1686043789000000	1749115789000000	1843723789000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
223	\\x455a9166f3670121599a7bab7df72b9518f03b4c933960ed1014cf8017b4509f0dccf8b1d377152f47d47430a5471d485b8b4de6bf28c6381b340c2fb0ab9781	1	0	\\x000000010000000000800003d9bd58a421d47fbd3c52f59a45bf7838518499583b417198359d2322418c12ebfeaceb58f11e6a18ff90a84c3dce2800873fae0bd9262eabd699626294287220d4b18b50a6702529f0f20fff62549ec5de2847bdc0c11d9635430bf9f0200f926112a6d4a0ad4837f1d7dded1a1490c4488a5432b370101be87c852a36e0b3b9010001	\\x93d61a36dc8563f1810a85c445eea9ef4ae172f694d9b6ae57ae59a1a0d3143c1da20ff5a98c5105ad97ba78fb7a49d055236ea5bea12d9b533018ff35edd100	1665490489000000	1666095289000000	1729167289000000	1823775289000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
224	\\x4ada44d26b4040cde77f361b9ee897672e3bc1a28ca14284d29fe5fdf199275018b43576e037536ab9dae26f074781b314575d4926afa320581a956d44b6bebe	1	0	\\x000000010000000000800003b90415aaac08661ff84caa645987026dd174278f1935ef64554f7847efca510c5983c0f2a4c6e1274bc29dc104d58b59c0a5bc43b76275d749f7f9f4eb25ce75a1f98299148a3d87347fce84ae38e5555a3655d5630eaee54da039c7ee32ca176309b01884ee28cbfb5c15d3c22e0ac2154b596797f96be6359f97d5c5680781010001	\\x17b3e1fb55898802f6642c9a7860409aab450f229981919a067375e37c0c8742f13aeba1ace7de73ecfad39f597eb40c9e08ab0cc1df67a98749dc2551ef330f	1672744489000000	1673349289000000	1736421289000000	1831029289000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
225	\\x4e322b01eb2971ad22d78f37e4b89078a1fee8de474c6540ecbffbb0d48323f260d7d7499206c47d75ef805f149641ab8de5056da0486f4fcd7fac07fcc1c5cf	1	0	\\x000000010000000000800003d4ed49fba10a9012828d221f54d20c7667aaa9521145d08d44816278a5c0eff0d416f5d4d8ab5e21f2c2d5dd3627793192013691463fb12b4c113b565e88f8c876165958a2500819c1df4b34f7e3873f3aad8497cc1e40a9522642b9c3c8de66465bdd5e5d2b518ef5384d961154c227819b874f35dd6a640c9335fdf7ac5cfb010001	\\x30d511b07780d4ebd88b512982f394c385a5ec10edce192f0a0e685e9ab881bfe9901c926f43cd038a1048dc79ce653b3cd8383e43ce04eb9fadfce443fd360e	1681207489000000	1681812289000000	1744884289000000	1839492289000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
226	\\x4ede90ce872844c0be7a018130f3e333283ac61d6a8f7ec76a26dac10ea197fd9dcb5071c3be7a546523bbe60b2a90ded00b2b770256d8a81e73eda037d932fe	1	0	\\x000000010000000000800003a80b9743d758a14f5ba592bb8e6af3b8fa47b738a83030037b250c2c955e3751076611c7c2c0a63b55ecd333ae0fc5465c2d8442e46c38d3c82ad96fb695c0e10b87dd649c801f47b5227d656b3456017ad6296ec4aad383cfe97c9c7522c7cf0b6f1a693b09aca5c45f939f9536efbf6d2085da06ba4ca62f5b4054adeef3f3010001	\\x7235d94c9f2aa26b16e654e286a4f7722cc5b9a2688a89ae2f948cb873f3d14637a2d8d310d0d27df8df7b36987fbb4626220c0fc0584e32f7d0d5fe03e1000c	1688461489000000	1689066289000000	1752138289000000	1846746289000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
227	\\x51fea8332bb98644d3625edc70dbeb78e0456c7467247c01a349b3b25664df0359026052818bac3f0ca452c6dfbbd99e4c47e30a665523044187ad4d2376b399	1	0	\\x000000010000000000800003bc082eaecca6bcc631c47eab41c9aaeff1154bf75b1a0fe3796230b06064244e97d361e3af38009202f2dbb4571547896b2ab9fdeee1949d9a9ebb5516802ecc3f4fcb63525db66025c6bf7542987bf93d76a84fd57839a5251f12f0e8ea8e450a3fe316bb8b9c91bd6ab74b5aa476b1dbf1101d690ff09b081bb9cb1d14f871010001	\\x7d0218f44ad9e02428c855f83dfa1b6f3dc4ff365b7dbca183dfe246de6bb200fa80d86de646ffc828fd8c54a0141356dced2d465ce5d3a58e37262713f17504	1688461489000000	1689066289000000	1752138289000000	1846746289000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
228	\\x52da17462799e559833f7f3ba7729f889976b3340c6fb921fa5d4153ddabb82a3cc38047f8906216554087417d55ad36a785a26b5e91824f8a4a301256e2fcb6	1	0	\\x000000010000000000800003d88c59128c08af1bdcff7bb3d312154333ca2558b8a75a76e9917868ae126390476cf65cbdd4ecee6fdc37eae30a73fec63b288868f2a08fc2f97dbc47f6005b36818c1935b93e06cfcfd1d0f232168b74e22dbd415855a563ac862d4d49c96e83e990023d17c4089812849079c5b7a9cb7e7c55f766dc886f75588e4e4280e3010001	\\xb646ff55c9768b742794c43077606d5b614675be14ca1265b7fd6765cbe266b710fcae8a6173bbd7cdeab4e12e3453254f845378b9ca3f6cd8c55a7cfc9d0a0f	1661258989000000	1661863789000000	1724935789000000	1819543789000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
229	\\x52be6a6725e9c4d87ec6bf847637db5ec1e42b4c073c74a1f896911262577d9bdb91dd56310e20b0af3ce24f238c4d476300ceb8d28f87929cac16adf59d44d5	1	0	\\x000000010000000000800003baa7dca36d2e7d82352a75c1e888d2b4b4fb6d4fcb670b4a8f5020d67677d6f2d4c5e2256d2fc28e568241a728b0d1c86e199f22c03f3da653881994f9575dc0e58a8b08918cf01b5de69fb8759a0c2e8eb08e47cd62193ebd7eb340075ea8e2d65fdb5a07e2007bbd2e4eeec65cb22eee781217a7850474b78523e0c12032a3010001	\\xdaf498fb1d0f7b14c1e5582ddccc315968814ab3fc409a62cce93be345b46c7c3a2f95cb981a89cb29b2b19c433d35c838309f361ac29a10a01df96915d01a0e	1664885989000000	1665490789000000	1728562789000000	1823170789000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
230	\\x54d2cd1ae059d603a4b7fa79257e58adce2a6d4481e3d463903185af74d587c7a5f998f08a8a20f3da650e47934767bca04a3100db845336845d87c3a908c000	1	0	\\x000000010000000000800003af7cfb86af0ca115c3430aa9c9fd9bcc618c888d9117e3c4ed36d06582cfbc07bff97764bc1da3dbbd793c0d5e87650fce6db84a9603f1cf3a2a478c4f1f4e2c98d9585ac1dd9ec8de1d2166ee129ae3711520c33b3fefbd336dd852fa061f54b717b0e844f03022a4ff34bfb0ba30c4e34af6336db627c5d86b27ddd2384a0f010001	\\x4f3d7587ee2fd996307c2496e3483223ed5c88f5aaafc63b6c98b8ef9170d312735273f9fa537ba8da07eafac244c126cecb7892982e0558297da6b59f88c604	1673953489000000	1674558289000000	1737630289000000	1832238289000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
231	\\x564ee75efd6f0fd02e89d8e9af1cf2f7b9d51a24ba4738f3d8f2dd667e5aadfee6403a9f0471fc220c708774069dce347844a4e765bfabbe06d50bcaa5897e8a	1	0	\\x000000010000000000800003de8e89b819be205e87a0ab05585a8aa7ac8bbacc564ece1fec77e7c01fed051521d5de5bead4a438fb82df97f9ff82feaac534c60d4fa0f1a1aa87ecb6906e1dcfbaf5027b4a41c17a1d0bb9a2f8a0c13eaa574a09908d026b1aea8e153f1c7f50364b47ea9451dc7d5077ddfd95dffc06af3c4d933aea4cf371c91428bedaaf010001	\\x6aa9a17b1131710c46323d2fce0f4ea71d24ebee8713a652af69bfb203a68b49f9f0432c53a5c28ba3f7389b762808267f0ce330185261152fa28e45d1ac2d04	1669117489000000	1669722289000000	1732794289000000	1827402289000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
232	\\x59421ffc1cd0864b59e5daa85ff8e7f3876f2beaf94b6fcb519f3f40dc7fe136461ccc594ef3a0c8d4b52dd1fe94fc30a4da095eed8984d640b9d639211be565	1	0	\\x000000010000000000800003c4e6b85bbec45dcb20f2f35ef98d214b861e4ee6b322b4f6d02cd7f115b90e2ea1d6ccf6fb6a5381b85021f8f01dbc1f42d95c1525b96b9f7b74bf6be369f6f29de8212a9610c46fbedff151c887e869858776473b9467aa8d834336c9b6e0077a1433eff9989aeb33e0885fe81359a04e0e301cbdcfb8a1cd839f506b06be37010001	\\x4d6655f4186c34300853468b6ef793d3f7e93919dcd60b5996e92e29970c1eac76db41bcb6f9014a90c1aecd0ca20bbb334af6e303fc3f718d203d5c50bd5a05	1689670489000000	1690275289000000	1753347289000000	1847955289000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
233	\\x5ac232391ddd38b0e02b4a1a63d7add4c8d5beba3a37ef211bbd9eb72e851df9d4c8ff80c3663369337296b04a23d8efa56ed4d367e5cdb5d68b6a7446b6f0f8	1	0	\\x000000010000000000800003c1abe8742b8ec85487738a9e08e29e832972584499f4881e3a16877ea72edb70013857eab5aa1c7531a338556c7d65f834a4f0553e41829e777b76f1a5b6fee6fd05989e59a20b14d5c9bb228324c419de9099b0748028c07d6e11c2ceb25ff9e87fbdef0c371c83af0be2adba944d2773e8b19bf5dedec4fe4a01348a3044ad010001	\\x3b81ecf15dcea9220aae583ce7fdaf456d2b6362e21c4cb48a029de5a9b6d54f275768488411d7874414c594c00d3bdd80327f03c11e30d01d4b674a1a2dca0e	1673953489000000	1674558289000000	1737630289000000	1832238289000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
234	\\x5b9e5a832553af5a91b79fc4ececf74e4f1b1a104bf7de7ddf287ff13a2f8341aeca333497026722da5e393730ecbd06b24a54cd987f1deb3d99d4e38b4fca01	1	0	\\x000000010000000000800003a921ac68cee9bd478a1998e65f1abbe67bb5f722b27269fa4428eeb2e2a72e8c7a6c8832f9dfb909306705c32644fe2273a0358dbb2ff4c36c1d8d422862114afea16e5e3f13f06fb0eb2ad595850bfa56e6718dacbd424a780ddb2e1212ccdca8782291b32b4f364f483a9881d8212e74897f5e7ff1417916aab1c76ae4c05f010001	\\xb4d953e80ae751e7458a983f0da4799c874fea8e0b692c6775f7cdf7a733aa6ecd5cb0e7fe19e7aedb8619b8a1f3210b381757295230f014db08b096df57a101	1664885989000000	1665490789000000	1728562789000000	1823170789000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
235	\\x5faeb12ba4e1bdbc13a83551f661d743c63ee2502ed55880c16634a6f04fe9d5556248ad7a8d1b2a7961ea04643a1a929b380a550722a5619c8faddc11e5cd42	1	0	\\x000000010000000000800003d04cf7c411babe83a0115a4dfcc0a0737d199aa7c9cdaf9e68433abf699a52964e25b25e985803672d195ca87cc31da98b956a482983ca6294c6007a538f70eca027d3780202d542dc43521a26e5a5ca549ab573cac4e7c0123f9ebb574d4100f0b48e6082a8205528501dc95284ec8d42f67f84d4bddc64bf243cf4abca9e61010001	\\x2a9b41c5a4749f4837b5d81f8f8e577d8a03f9aeed13d8a76771b060ca5af11b08f68b5cb9d94681bc6d9a28609f96e67c40710c8b16310beabe9d4dc54c2a0e	1692088489000000	1692693289000000	1755765289000000	1850373289000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
236	\\x6272d02290e3e6ffa44fb37536a15d20e3c326f16257dd38489a3d75b8cb99763fb5652c9aac7389da789ce4044e14feb76b3f50149c22292940d2daaea73de6	1	0	\\x000000010000000000800003b366e7dd8fb5344ed344dd2d1fb042a0fa0660d3c814e9a432af624d4606ba2906a7a2d118a4f96514cf0a5ba8e04dd9abc0332c6068ff5ea2e0d5834c3a5f5962bd1898194b14f2bcf85c4971b289984b2dff7a511e71cd85ed0e2139045cdeb75090975a489c08df39d0af0c05374ca3155c068670414c7006f09748b74a93010001	\\xe30520f26d9d22afc3033ce9acaa05b5fada049bdb59b1f18dc596fbd5b2063aa01b0ee21f94622f6a04bc75dd1decd9602ba245d84defd4265e689f6794c80c	1662467989000000	1663072789000000	1726144789000000	1820752789000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
237	\\x64ca830e1e1e1b0b53dc293bc3b8d66295a6185e06871848a872c99f329e2a54ad4f8c84fed61d997407d6ec3e84bef41d72ad2c7ac54303e701a20896814863	1	0	\\x000000010000000000800003b25493e2dce996eabe67b4122bd813443cb829cb7d581a847e5eb7d4ee439fc62f9f2840a93a28120b0136ef7f822861ebce0871bb0a877399d65b67a153cfe780c5b05f579ea5669bc7d40b694769edfd5b7f225f750dc88f0d98391c7bf8e785d0fb4ccecc8902e03da5c766f54b7c708237663f633ee92f1cc65997c1e63b010001	\\xb17917a9cd63a4334df9e329e269cc8bd1908e1eee128b183b8f1665479f4259f727c0144b21532a3201cf40c768445e434f0070884f83d294264bafeb1b5c04	1686647989000000	1687252789000000	1750324789000000	1844932789000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
238	\\x6592623bff43c2ff0f566449da61ee8b513b5645ada4e6fbe9f934708fa2ebc0491bf7778421aecf3fe2325ad8e5bdb68db3cfa60612633cfb02f99b38bfca90	1	0	\\x000000010000000000800003a24aa38b21b5a430aab3596a1d7b682eee201a3f6f7d4d8956a91097d4806a18dc7b62d477311a4ef6e3797c023bbe4db2cadba9e05a418d57a10f0fc0c63b97971e4e14ab1752592b88f54027246bed88c358143c5d964f7b83e1437d85a8dc2f9de65e3432157001bfa210406d725412b018c0752593047406e4248350d265010001	\\xe4da96ea8a28d3fb0e424ab777e223b4d6b25d81a99747e17da8c66cf0c5638e24086026e3baf093a05045580710f6ba5e14ab36171af29fd1c1f3f19b8e280d	1682416489000000	1683021289000000	1746093289000000	1840701289000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
239	\\x6656df1fb2c008a705b4c05261f38f5dc37d18110ec8c633a284032e6b8926c4b342676e2c285aa4e2eb68f9f821285859c531f60c16867ac5c964637052b7d0	1	0	\\x000000010000000000800003dbbd72da5eca3aa710608ed31ce70ceae69244432a9437a3c3e483cc4d6dd7e8c1c4468d0240cc38acee7d2278b6193f57cd3a92eac8f9d1cd0d08e05d63c7da5efc6bb7dc47b3dbcc389697a000f31f6dc0cc2644fd5d1655caedf6c353d22dcc3733d2c2ef28aa9ab7e91b8aa09472b24394e4723b52cf964e24707586f6d3010001	\\x43f9597c43c98f715cc9c2e4c929f50e2cf058bccc8089fb55ef56e62f2e24eaa17bbd89edc5af22c6b3c4f34374cb2a1c5c2be8664a1a5b8ec7595621a1f40c	1666699489000000	1667304289000000	1730376289000000	1824984289000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
240	\\x67668ef31d96d39a9d1be6cd8d9a9f0adabc70f7c4611dc5f0ca998983ff6a498e8aef564308bcd2915e9366008dd9862057098690cf2373fdda156307b32d2a	1	0	\\x000000010000000000800003b27c213da35154d5bf2159b45d94e6cd4b998198a7e59a429867adcdfa0ca59252a7b857cf22c64cc27d0c3c664178b63c948b0e799a1438b4906f3ca31aa109509f96b4ae5123458acbc2593f2ed139c47922180317e2dc6516b6cd6bb25a466efdd5b2b5c7ce5f26fd459463a8404ba9d34b52cf01c91dd8c66bd9e1017e23010001	\\x0c562baee3fa1ba18e3b147588a48aa0fc6130f44946524797c1c66823cf80341ceb80ac5da0c82ee406b3dd7a257fe4461315dead1ba2f2016c9b4888f2e50b	1690274989000000	1690879789000000	1753951789000000	1848559789000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
241	\\x67d2d61f74464274eb54b0052ec68ca3335c295080eeed1e4f8f1fd94fa377e90eeaaf8e3c1613087e9712dc55e02982f8344efd4c123cb2953262d8f0bcaf1f	1	0	\\x000000010000000000800003da5fb029febeb9ea916b1efb873dac746958f95a0887b9cc111314c7c3229c5379ad79d3d069d9798b11b5f3f3e71693b759fa1ec3a26a93c6e22124739b504240c135df434d627d2ebd9ec77b1402beece66ab5e55f16d659131bce020e9e823a3db040b86320ee9745491a2bd42b3876d74c5df83088abe0d97bbad0077991010001	\\x271fb153be91baf1a46baa25eeb25e491d92071f1640110eaf9853cb1dee9864e93840bb8a5c6b8b4760746902a14327bef136374a5dd06654fa594ab31b8d04	1675766989000000	1676371789000000	1739443789000000	1834051789000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
242	\\x69ba457283b75baa4912a2e23b0b536e61e76b9ed086d3cb0d07192a3962fe42f9bd32f5a6895da64923d4b4239c7997dfa2f9ea9eaeb42c5fff40477aedeca1	1	0	\\x0000000100000000008000039d9805b493cc6f5e3fe7d93fdc2c209529b1cea9931dbf3bed1d56bea7e3ad270d35de4e9e7a1d25eea4c600eeb40d4c654fabbeff0bdc6f6aee73e4dae6adecf756f182f3609d2496e6d5b3e7f7eb8703e891fac7a99af4dfe591db2e47af0bbe55916494f1c788b9228149fe728bc03972fd22249e4b69169156b32232a871010001	\\xb87a83859d9825f6ae47643005187519fb5a71d8ada6de53b732ec398db1b9d6cce95e70e47e8955b2450474840af7459e238791401b2c53c6bf61e9c489dd08	1675162489000000	1675767289000000	1738839289000000	1833447289000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
243	\\x6f22feba482a503849f9c92922fd843941044630a465122889d23ccd4165ec2cd121ad176eb4bc2705d821be5b3c9aa1877977ba4e197c85cefc20e55b784758	1	0	\\x000000010000000000800003bc8dad8a806514e0d853ff103e97b686c14b611702616a7cbce71705f72daf3f11dff25cf861986bda5edb4d7d6f1ff91864244c76a1741fe3f1ae149de0aacf770fdcd60a4ac9dab3e586330e20458da710866b0d91f00b2b0c0f3de050696ebc96378098d4fa000e65b6d3254844afb22c47efe8e9e03879b5a2cbcb3bca93010001	\\x668b6d6659b065c70edd87d428d9293fc1e566cc80e15b8fba7397822deeabb50761a80fae9d12e67d01a92d661abc458a5a0376b1cb965f4e56a6a7ce6c1200	1672744489000000	1673349289000000	1736421289000000	1831029289000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
244	\\x6fa63ad2a58601be73865f207269cb4f54981820e42514b398bca3d1855ad271cd719b87e75366bdecfcbc4c0b5154b705b91d6dce70ff9eca07af6f172c6a6d	1	0	\\x000000010000000000800003b9daf78dd11bef7f323d1f38f71e784fbf4ec457492b1f01d24e2be6746b5880844ba2074e0778ba98d3f072073a96f4a6954a0278b7226f43ce809e5229fab33c32e9facf446515fec5bbb61147062c4627e7a58690781398d3ee79dadec4be81bc474656bd80ec6b8fbad0cbbd5c9440cae1cc185e5aaafa582ff0b3afdefb010001	\\x77e6adda0eb3353ccec6d8c27fe6f805951649344ad238f64bcf8f2f26881dabec61a135b67108f9521082a3668b28747f103f2eb1d4a447f2e524af0383d808	1686647989000000	1687252789000000	1750324789000000	1844932789000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
245	\\x7516dda4bfbb53d2b8930fec07e8f65ba8083b2f6a1d94b793e6983b7520a9bbd6277213de1fd2fc3a07194f3971913a735810ef8887f2587b51372f3773b948	1	0	\\x000000010000000000800003f0ddfb234855c6785aee62af66cb4946cdc293097bb2d4291120c16f0252a563217b540fa8559e099b18a6d3a4b86ead0288c361e5145bed197b3ea12b9b5d6c9eb0995c6d36335797dc77fe1740cade75bc866a593651b8136b9ea43d9d3b0815a33bf06a670149b9aa9594bda2ab135c3f8e7056fc28abf13ec9b93fbde867010001	\\x4720d1549f9138790e7fcf8fdafb2a781db80ab79d5b0605d2baf4619d9d403652b2ee17f68ac49b1c0a39d800e3322470ccca13e84c812990a1637e6cf53e0e	1690879489000000	1691484289000000	1754556289000000	1849164289000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
246	\\x7986f3ebf1c80fe4d68bd6cb1e6a2d80150ddc350cf2768eb86154f2481683f579a7ff60a54ee6301f6a1fa9faf1ef54445e93671da3adfa4a790ab49a2d5263	1	0	\\x000000010000000000800003f12141a55261a80c698e2bf9b3cca4ec8e6a28a931a3b6781e058645996e185e6a033d7cac7bed31da4f2a120f4835c3b15fa01f8242622345e5f3d6babe0830a1f729a2f300e48b752cd945e98e9669c915615b714ad9aa22c5711a431a08a88721075937498ef15f6bc115fb79463996af0cc8601dfe13787c41d29429dce3010001	\\xb345d0e429d5257a82a61bec087ba395ab557ea2cf7d9884fdbe7fc9b212c778e8afedbbaa36204460ff6e97d5ada43c8a40538ae619c73e3d6d228303c82d06	1680602989000000	1681207789000000	1744279789000000	1838887789000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
247	\\x7a8eafcfc8d2df7f3cde44d3808417e3d280c7e76960b8dc9361ed8b19829ccf999e269b1114ec71a8d337c9cd3e02e3639bfeae9622e0a9067b878736fb7f95	1	0	\\x000000010000000000800003d78f3fffa87a5bc60093c80b3420c294afa3e72fd988787190829e4e36a6704de47cd6413487beb4f0ab8911cadddab3cc3e144e7b958c43bfc619e6e05d67561d8f061ada94418d49234a4eae800cae5cbb57e102032dff5d5830290eb7e978f6d4753235c404c94a467e67bffcf3617f90d2d20eb0ea8b9af628e8c7443aef010001	\\x120e2f1713a6d0692b4b14d78c8ae67a26fddb190e0df3df38e1ffcecfd3cd25a2f8bac69ac3c50278bbca3571bf884d04e920cc87ae7287b91a17de8cbf7006	1681811989000000	1682416789000000	1745488789000000	1840096789000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
248	\\x7bea6d55dfd95474d2bde518c89b8465574d0b917d990391a0151bbb02fa154ae47aafd745abe23929f15d716c09f618fbc47bd8cbd3a10e4513cae1b2f71433	1	0	\\x000000010000000000800003d41ffaf9ab250292471ca66c6dbdec7c36c9810e4431878ee7a90f5a573d6ac7e23dee4e46cd42711d025b691ac379e8f6b339804840e0b64a21b129b44a5c53cd0fdccef4e0c5514f20d36d28b23902e28457ee98614d1ca092bbd1875c6c70a991ba852b9799fe447457e4d115e8109880ba5fc42e5b2297e75dbac2ac96e9010001	\\xd908927d3f3a66226dd473bd0051e923ad376e2df68ed73b2e557cc584448f2fbfcd6696b6c9a97420ea551ce551118dd8d64c31edca6b400af699a60e4ee50c	1687856989000000	1688461789000000	1751533789000000	1846141789000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
249	\\x7bd62ef4b53ceb3f254350bbba70a6d5cc3f58e02336e6e536af551006d442f6111560cdf52a856ce12f0030c8a61b9e3907ae817b1e468c262e49d14d3202cb	1	0	\\x000000010000000000800003c399ca1be975190338e2dfdd8ed483871000dd4b4bd01aa973de6d7c18368e8d2ae46ad0a00e85e4dca026af5a1f2da7edf8e5b6315a6a288021ededeb6968b50f944bbe4da39a9550bd14d0bca3e58ed6d0cbc46ea495bc570a9e3d8ba53260616083e51edbf9ae26b0f17b36808db639cac5a994417fa2ab9b2e576456576f010001	\\x421b1a3ba062173943406e942b669c90c726ba95e31f7459be82ee517173af71b7431cf2a4cd739f7e8c025342b6bda97159e25a95cf706e822f9f8a74429101	1678184989000000	1678789789000000	1741861789000000	1836469789000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
250	\\x7c32b89592f1e80d6084952b3381b745fa055b5e010c402f9e92d8dff944a4b9c508321f7d9755477e5ebc3fa9741c9ed4c9ddbd153fa32c6ba7d95cdc9b9cd6	1	0	\\x000000010000000000800003c364f3a6ecb2244271b4ba2ef8b9d349fd0879f0b3e6a8a5af99f78931d64b27903cebf53e1be09e52cf0f8224e4b50a54d79cb4941f073585ab5399c8d50b49c37f6e760510fd1a9c040e34ba82b3f85367df09c70d7a0aedd00d7e25e54d783e722a117b2e19d053ebbc6584acdf732ab45699970418e77c29aaf344fb2f27010001	\\x5bc7ea92da272b996482abecaffa09654478028f48953efc3a249bbf33a24bd69fcee6e0583c7c4a8cb5cd2174fce3f7701d0a3f742446db18dd05057f588f03	1666094989000000	1666699789000000	1729771789000000	1824379789000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
251	\\x7dfa729b2b558ea2cf66128d8e0d727ff79ec46b6c4712c2d4d6d38bc011388496e5910e2618b654394f9757ec148a7e79d5ae40b98226b9a0ea00e3fcb071ba	1	0	\\x000000010000000000800003bfa8bc719ac14425773e0886d2bb99a1bb33f824390594415fc238320bdfcc866cfe2c47b783ba0c939321b11021714a1f2e7f09db09ca873794a136445c78b102fc5985cba9d196e7057c0fd40df65906c60e7f6e632ff71c4965c38b0c68f96f36de9f3aa0c707e33b843191d87492aa3561121db27563f237de6bfb07cedb010001	\\x32766ca8f63e5e41e0eb37f44ced27f31cca1cc5e6937ba43741c84afa39bb7d2073f53c8dda406a81ec47753d38564f889620e2eeb6c14b275eb46b61a66600	1688461489000000	1689066289000000	1752138289000000	1846746289000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
252	\\x7eb6fc0c0467b3bb5945ec8072597753c87c19f743749da090a79bb9ad29ce84f44e0559119cd4fd3b2a263414752fa8b8acb6f8c8ab03428c78331a15e0aeab	1	0	\\x000000010000000000800003c52c8d8429761351af6242dd9a735a5dc0237d6b188e0402b4f88971b0531f6dc188b8b7045189447c219b5212957d4b6ca5f26dd9a1f4e7005c829e20ca24628d024fc59119910a2a7fc806e7059ca17ef1337347e8fbdbf7df52ca34cdb26064877306578013614c5453bfb33e9a2adfe2c71810a6af510015b7531d45b141010001	\\x163c12639d9884b296daa8319bbb6a51cacac6818c0addcae3c8278059fcadfc5df097788e6ab7780eecf43b0c92acc8953cfd4f5981d58f91865d5372251600	1687252489000000	1687857289000000	1750929289000000	1845537289000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
253	\\x81eabed9da07b46c574f08f206482679de29bfc499a68347fe8502a71f1f1d3e77322984948f1cf32345ca58fc893448a0b1efd3871089fc7d99dcf9487cc400	1	0	\\x000000010000000000800003c725708ef9376ec8d40e6c0c5386cf7ea25fa9cf7141db08c63eb60346b845becdd0625f07662ca1e7fe0090a6dda0f8f843e941afb4eda75efc9cbf0395fff2e686fafd15e42843da267faa5e97fb53a8651cf83c9e327cd0cfdf21fea9e90579c848184eb1884f6fbf29307a48ab3ad677e96d6cdea9e4dcf0ac95b548cbb5010001	\\xf111715e452f3fa35fd4c4c5fb55f6bd62f5debdefd2188cd3b9a4f8a2af06fd92b7be30c11473e548c121019f7dc365d4a81a0ed47eba1709af2a478d05c305	1687252489000000	1687857289000000	1750929289000000	1845537289000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
254	\\x8156b5f353bca4441d8cca23553dbdfdac41917e43252e621f1584c005dbd0e95fbfc475955f4a066d80630f67e21cb19bf70e28bab3ee43ae95f015221861df	1	0	\\x000000010000000000800003cb4b2abcd80c85d0136d49df7e5cb4ddff6ec40eb5112db1eaed68521cd36afe142f2c8ac6a9993cb6a33c7c600a4bc58ced49c7e416d1282282660ffe2a5b9c40beaef73106668381cee4d1d640928f519f5acea9753eadd7c16503ada62392d235890feb597ffcaf3d557f90a5d14cf1534b83785e9838df0a149a130c8621010001	\\xd78291afb8029926c837072c9ece52a556e3a598056f50633991560828a73e76d22f6b22923064312ec8536fa7c5bad7416b41b83d86db0299169db554166705	1666699489000000	1667304289000000	1730376289000000	1824984289000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
255	\\x83c6bd3fe4299da697af59574b153750868bc7b65d115418cd37f4946ca2ee08377dd6d21b897fcfe14ab6cc5a6f23346b90f9999c11b6ea5a63f1157407537a	1	0	\\x000000010000000000800003bf65c64d9fb8b87ca2f71c6f11de04ebcc0e8a26165b1b29fe21081cef4089fef48a35e1f0b79dc7142e03b173b513e0e52dbce08cd6492be11a533890bf53da31a53913d8f1f88f9fbdb95c3371c966bd5063acc049ed38f37f9ae3111440a266e80128f5694c06bce6570ff4c61123e385c2e7a747e17c19a2dff94dcb785f010001	\\xf76096f7ab7e3af36decf3d84307619ee954d61ad0e1f600be782f15700964ba0ae329e0e4020cd57f67cad1aa9d912a70fbf9358d577909e9657dcf38aef70d	1667908489000000	1668513289000000	1731585289000000	1826193289000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
256	\\x86e2c6c6c5ab47909cbc39247cc86567a477bf4a6dfbc2c8a0569ebd7d9d47f03a41bd6b162fb83bc4867e6d366012c6dcca64e291599b849050d068c3266b9f	1	0	\\x000000010000000000800003dc3d3dfc429dc54661f2bcef510dd6493b7545d451c288e6060b9214a7502ad7a40ba0570ee4170e4a08f6b2f4bb4cfe148203fa8160af0cfe57f6430eb0eb14595ffd9f79545b72425ce4f872bf6736e7b51cd2438d99a040cf30d643e7228738559611f3e3f0b52f8028813ca78d5ffa6143b3f9142bcb9fcfb6a485ab92db010001	\\xfa67ccbfa09b02e72bbffa2271d64f4352af837e88aee38d7241a658f1059ec899fe6d901b10de1829355487bc007c61a0cb123264fe4adc57b786a4c9aa8905	1677580489000000	1678185289000000	1741257289000000	1835865289000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
257	\\x87e24a8eebc4bac0e2e00338c6d98bcb03892d45c6a1d0f485c66da9843528704e647f70a62c5683db751ccf34a617644645906be7dd61a50a33a5513edae6f7	1	0	\\x000000010000000000800003a84b48081998600ebb2de53dd1259a31dbac767b960cce5b68858ddb67437ea858553feee415dded6d1437c52b555a63ec40ac739c1c4535618f971d9ca6fc2fe9daae3a42f0590e27aa91c7170abf2e341b4a209891d2e1a1e73a27b95323dfd9cb8b14026f08a70237b9462a858d9d0121e56feb3790a1fce5dcfdb157fc0f010001	\\x6595eaf02dacb6535a3ad205cff4e8fe218efafa0cc0ff6688cd71fce8db454f19f8f54405eb8ff73aea2250d3e025042866f073be7183b937c1ef8b5631a907	1685438989000000	1686043789000000	1749115789000000	1843723789000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
258	\\x8956d41eb50420fd0280876a10c6b9d46abd2cacf04500a5eadadb1f5e9c9033e0e436c7151e69e3b7af897705f5d82e1b8a26d2dc6cc89060a67fe5a860afe6	1	0	\\x000000010000000000800003dcb8ca85827bb48c8feb9346900d2f24cdbf3505df86d5d04d7d17d16026fa8cfbbaa6ffcc27279a7958b10ecfcc15e19670d652d8cf620a08dac7a6ae155e8e9507287d957b14cc06602f5432d8677aefa771277c3c7f2531d202c028c92d9d64cf64df442ec0cb510be837099c4c4023d53ce6a8d1057bfbdffa4aceb0104b010001	\\xd606c21bb23d0e791f0290190e5db390c79fa0653a9f3f4105a9a714a01b15b1ba892a1c36d9aca1797d6aa06cbc8441e54bac60ada83d15bd8c99100adc2001	1664281489000000	1664886289000000	1727958289000000	1822566289000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
259	\\x8a828d7e93bf1e1e2b8f46ec8ff672d3417f0be455a6079de895542a97fc35a6b8f8f266615c1929fa51a2f0783b4130e41754d2d77246ba352b06d43d36634d	1	0	\\x000000010000000000800003d1a1837c611fcbe2f99872a71a80ef6efe17a00751c6abde346a9f8aea27e58dcfebe60e70342c6fc24284cfa7046d0b7e0cd14b4e8c3e26ac900da4eddde6d904742cf2d54ebb0aadf196a238067756ea1d3c8ee7ef498b2aad3a76e354666397ebff089b32b42af7154ff4cb1225a75449431d75fe17433a88546155b014d7010001	\\x7fad1abb6d62f22291d6ef4c2e843d9d90b3331645226b87a405a892b035db8edcf79b2882c87ba4da47f729e4e55ce179496084968492c472321c4f12e65b04	1681207489000000	1681812289000000	1744884289000000	1839492289000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
260	\\x8c1a9656f9a3f742915c87f2632da70e8943d1285badec4797a080f997a99e6feb167ff45e288c325c3f1e0ce96b039edced996f9884efd25f0e9fb0fec5b44c	1	0	\\x0000000100000000008000039b069627e29541ebc65aa925b852314fd4959deaea73185688fa6d23dd6bd140650a7df79f7843def9c20831b5fd69d0e037428eb34cd200b0b00d9338234496231c79876f612f625238b4490ddbb9bc813cab98a9181a3c13ef5e9bcd54c33bc58ebca8d01bbd36f2a2e51e49a61cbe53ef5f0b282cd774830f4339b132871d010001	\\xbb8ee45c06ff46d91771160d1aaf906efc89fc291d8c9933c590d1fb75b11eaebd29e0f767c0914aad574b50db05efe1e4326004e7d03df01f53fb2f7954520a	1672139989000000	1672744789000000	1735816789000000	1830424789000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
261	\\x8d728665cfd3614aa4b70b4148bdc3263b6b5338b1ea521161af343bb51d530523f2dcaa3c3861f7550a9c91f94a414418851f1d624c30534edeeb8cbfa8f10c	1	0	\\x000000010000000000800003aefbac69af4b43e3940ba039f12005b740cc8b9ade86e9266d3b3fdb483806143bcf2426a5325ca140fa9465d6c81eb591bf541570a3d0af5e11f8bb893015018f61ef3785b62aee0483b529f7a9868fa728b7c016e01154aac1202fed1ace657216dc07688d2a5756178a77d19e16ecff7cb1b943d41242466e7adf2b2e84c1010001	\\x4f71a3c1c93cbcf89e60817068576605830a5f4ee48460a58462813c165e1208b045ed5511e13fa14e7006b45accd3c458819b6a1b591200c06a73daa4e5cc0d	1673348989000000	1673953789000000	1737025789000000	1831633789000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
262	\\x8f42f3a425d02d6c4e6e27b8b107f74e957ec7c429c776bb678d26aa25fe9a70fa13d65a187519d9b34bc2b3370aac73be3d8dfda1b87efaa25830835e096c49	1	0	\\x00000001000000000080000394f6efbffd122901a99aa009b05b0624e26a6d8e4ffb7de719f8583c53a4e3ddc6bc22dc76ee653f5f3cb71a812b9302a83f1e733b2e8f9e152accecca47926f4121a7b6e516e9be70b928f5c931a3030f3990314c54727cb8ae89db7d60771d8ad08486f7f2b17a8c338c4dac6804543fd47e785cc734b27ad3f671aa34375f010001	\\x26426b4a762625d25f41313dd1053b369238364a5b652e2f174dcfdcb452f202babc6023f4757f2130f96b605cbaeaad12c9a4e0e945b3a24eb8854f4830f20e	1665490489000000	1666095289000000	1729167289000000	1823775289000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
263	\\x905ed360383a2ea5b41edd0e6efe23c5f8fb3f15cc14b17c9ed2dd1a34ee568dc2ea51321cb93b3162b0246f39aae44bdbc80ad8e6f9d1856e3dee8df405fc82	1	0	\\x000000010000000000800003b23e884939f46cb5403eb7718a06bf724bbced3b5bc3503643d62c9771381cd657605d91abd791eee570b9e36124570bd280aad3d0323abb6c68e8c16b11ee3d925eb9dcd64fee70d06053148a792a56a4c9471a2b31aad1335fc00bef0f4cc8e33fb9226e954f25c2ebbc0024981a9f2726d7029e37a8fe2f3fe11f92871933010001	\\x32f84166223ceb9d822437e07423959f80a1834b8c3834684b01331c859ff82833966a076649c93c8cbd250a4ee24b7a88dc6cef1ebfca641ff3ad11bac59a00	1674557989000000	1675162789000000	1738234789000000	1832842789000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
264	\\x9372083145889263b712fdf1cef692e71bbfde2b9b64afe8428c782b33338f12b90186d53765563a330b95edfd510664f2d9169fda36cce95f86d265daf5e6a2	1	0	\\x000000010000000000800003dbbbb3e2c2450eabb007b8dd0f7df43b1261982a6e2eea7f4380ca470b03b6f36cb624f165134d6a0765f6456a5cd67d160246781c9cacc17819d478f39fc79f0882ad1b878425cdaddef6bc5b08bdf0f61b894d32a0c88a9b863c5ebe9fcdc2636092205388b0025fce04e2ba2debcf844bd35c6611d50e6fd5ba2a23628075010001	\\x0c069c23e614a986001b012a0257233d66c431a63dac37cef5bf3054354d135334483096eb25a78c991375bbd40b7266a108b4a4e48cdbfcaa21ee098344fd04	1661258989000000	1661863789000000	1724935789000000	1819543789000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
265	\\x9446c50d94032053dd5b5ffecd62f61ac51cb726133e76730a09dc7236cd6393c6e83d36026ebb2e3202a97decc77626fd149f45654d5a593c21df860200df8b	1	0	\\x000000010000000000800003aecab8b5f123c07b703796fb1d2b34f37ad49e9efdef7d67872babb42476d2bae4d5084babfc27a5a9354f37c745284b0e6f7b6ee87840f8a37bcb9cc26d523cac297a7c4939a2a45a24f67c362be026ec50513c8a5ead44b325f023edda9874fea8a8b7148b3e4621a7e94254ff13a7f7fa61099576011fdb4209265c1b86c9010001	\\xea0742a0d7f3b0fe875d4413fa83e527b133f7e6356b5964319a893673ffbfcb2cfef2794dea8434a0a6fc3172b326b7d34f8fe33771d1fbd4089e647a330c0c	1672744489000000	1673349289000000	1736421289000000	1831029289000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
266	\\x94462e10397cadb87727dae2b16c628d27f96dc75c3d9b97e14a2a47c13a338b46614acf892cb56fe5e03bf9c3fa59cb60f352a54bc26796d78107876c1bdca4	1	0	\\x000000010000000000800003960ac253a478c1493e753f28bc6d16cf839112d4269a6a93a6d3a0b09c5d08db6f2877552f3bf0ca2fbcef85ecd73a6b19917aee7f8efc4812dfbfdd7c5ba85b44b05d89fdd1295993d84d71d0415110d3b37bc66c517d9fb9758eda48c62db5cdaddf61140203298a40bea21af068961c67bfcb627adb093bde68e788b34c6b010001	\\xe17cde44b1ea1a089056f62eb8ff26b5ba2a8e77e45284f8cedf1370bc0e421881ec061c09f9feb06defd65fcbb9993d5c6ae02a6896ec8373c403b189b0f600	1669721989000000	1670326789000000	1733398789000000	1828006789000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
267	\\x987e6576889c4aa5745e8da2204afdce38df41b218859911e58074e7d49f810b95288655796a318acedfbb2eb93cb0806f8a36328d9a18690cf157a9e787c63a	1	0	\\x000000010000000000800003beece97babb0f12f9f539d4ffeaf5a85a3d3959a8f9ec07daf9a448553ddc34adf4a9be54b2e0dcd0708f86f97710a307fc13ba60fdfdf0af514e09ac035d4f1b6b9f0e9f4dc2b5dcbd861f97f6945b858cf3aaa3c2b2ec5eddac9835df3691069d1607fb3fb239f916f8e96ef76fbede086bf77d3fb4a829660bd0a79eda631010001	\\x27ba63b81a5d13b0f1c426e06489a730b8b2f4a9d09084c9cba6fa9353eb66fbe0e889fc7e20236cc6d6431d1b8c3b901092fb5c72c4080e69d745eda429f804	1667303989000000	1667908789000000	1730980789000000	1825588789000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
268	\\x9af6b59fbca49ee8d76f0aafe853bb677ffabb7602260680b1b4711d92bf657b5eab6c822d1a54a69b28ebdf0499e9fe08a2daa77bf56ce1137ff4561420e6f6	1	0	\\x000000010000000000800003df908f8bc7a08d5e56629f8221d44a82daf0fb9da80ce82650ab5db748caa9153fe7033ef1072b232780483d0e776b37c6bad334b4357334b633dd8e3d12d3436f271474aea5223bb6a91e392f1422b62746f22e694f04d9e9d702e3633553e21afa8e1287495d166a3001b6ee32e7f6c1165e120731a5d0cf6eb96cb3868935010001	\\xcc0f969e68cea509a587b9a03c1d32e2b7a11768c3c4060eb03658eb25a2fb41acc8bf5c86b60f6a1f49d44feab2ffe342ebba61ea37497e136e2f0d9af82801	1671535489000000	1672140289000000	1735212289000000	1829820289000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
269	\\x9b3efa1ac707fcf6d881c8b3adf1ad36f9b61a915a742d0f1e9b556e2a0337e1de587ec8c59ef4b1c10fe128cf127b6378332f4a61bab078b6e59d9cd18c01aa	1	0	\\x000000010000000000800003df85e2cd3545b773f98b12cc7de02b619a68f36182d2197d49634771f2718f6c5ef061fb27dda16db85ceb094e6b9ea25a36eaf142e84a8e4cd21fed8af38aa21e6cb8a37ee24a12752a53536216082bd9982b545e6d671b1208c47a012039dfa126634fc74843c9e2452e1ab03df7ff015cb5de6c81be054470583900a09915010001	\\x9a9ef842bd5ce01eb29d0825bffc3ebf5411a2c6b6d36100612d3f9bc64e677dfebbe3c73fa52855357b185530b084c0f0ecf5a67979756d2d280ff861dca80f	1666699489000000	1667304289000000	1730376289000000	1824984289000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
270	\\x9e72c2cb58f27133763b4e56442dcbbae6a17dd183e1debd1f4ba126b0b2efd47b3db02e9dcb0bb02a90ec732d40bc8dc2557e099c002aed338fb9d7ad7979ec	1	0	\\x000000010000000000800003c3522301b5c87c11ba2017432c92da721df636648849af4dfef27e996337a88ccbdfb93e7f9e9553feea1889185703ac9a2e2a8ecaa5ad54a2692b0aab178f88fcdf8e7a0d02740b928f751e7b3d0baa8b1debefa24ca8ced1534776effd6bb3960a51bf681d0e1a0057910e358b60821a6e09ddee4502a172f8ee4c597eee91010001	\\xe7a4dda3ccdbe92922878a2812be238ee0b152dafda4cd8a60ad7833de5f99dd43ba6d1e63fe129015f1c192bbf2dd69f67759438ae7b098111911c59d87cc0d	1680602989000000	1681207789000000	1744279789000000	1838887789000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
271	\\xa36e429ecbad2687bbf6c7fcecd657437c021033875de88d4acd08726a71ce03a4c7e49364706dd7fd54825bce225542171c5be102b95043dc2926740e4bb383	1	0	\\x000000010000000000800003c6d5d3f4fbf91b0068594801618eb75f900c1fc355f455386542ae875ba1a5bd1d1197d3d795193afa6d3874854f5fb3232172cf2b31f3d2039e942b3eda319236e3888b39af4b995a7b16ba634636a74f00e649b2e6f1d8ffdef73c2676b8b9561a08f975f0bc70eede4b15f7bc2e341343552e13f7d5b4ee98cd4e7270abed010001	\\x2a25d45294d5e934c6444ea67b25cf15d065beb2df7be45714c0e2d9fa6dcaeb48970680354753d632d540889e06d481c68c52f46f63e546f08a1f00256a2003	1683625489000000	1684230289000000	1747302289000000	1841910289000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
272	\\xa6963e7443987a5d9701906628f0e6f3b623aaf66205d4bbc225a2d0f04d7be71c0b46a2fbe3cfc8067e0175a0a801678fd37f58f31589268707228798d0728c	1	0	\\x0000000100000000008000039d5bcad7cc380c5881ff1479211bcd65d387d9a6dcc2a2099def50a9557d5eec51cdfa0475b0a942b3cd158b0c222ddc2dcc5c06fadb521cdb5d75c9569e786fbd4d53ae147c71cd281a6e5382997bc819f0effc7f47b9b8492c902c6c420713842876125886c1a459a70e853a7763784ccdd6c28ee06cb2b0b3e5670a33cca7010001	\\xae5bf88ffe4631ffc698fc5d4d6e7ec8efdc3bdf7553584daace28e5a608fb9fd0247e99b21a68f6c0d9df1ca5dfd236bc0bcff93eaa92c826ea42c4b69fc206	1665490489000000	1666095289000000	1729167289000000	1823775289000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
273	\\xafbe613f9f3673c0748fac88a2246af0774af714024f74bbd66fb01563c98261299241d1292769be499a9416e05a0c1a8e2655ab2d0df873106e63388bb7dbdf	1	0	\\x000000010000000000800003ce0cf13924bb4d6d516f772278afd9a1e53a32615cd545cafe128484bec702c12799e3caca5d369ba06d80d582e3e53c9ff2662279a36bb589923c8cdf204e7e4a5851d9cfde3fdda484cc9b6f0d169dd517acfa38d7cb37c04d76def6bd0ed9b8e1ffc23de21babe07c1c5221881709cf029136e90721b63235b0334526c845010001	\\xf7b6abdadb49fe3111e9bb9a29d7f93b545bebbb94857d582f1b437ad5381be75a8129d061c4447c6ffac3dc85a963bcf4f9115b92cebab9d9992f3e945f720a	1689670489000000	1690275289000000	1753347289000000	1847955289000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
274	\\xb4aa247132444f6fef5dbcfb5b9d191133be79b1eedb0018efe887a9503e9d27087977530d03ec356057231967fa8c2498a41d1414dbf9ca33be19f11d28dae7	1	0	\\x000000010000000000800003e0bcaacf0530f63c16de2e89614a783fa52509e32f735a262bb6440e5bd9b50845ac43f593e0fbe97f42d2ee4d299b133f2a8a8e5dadac82fe11d7c498c435a47138fbf650aac2f88a1c31af4e09be21b868d2075b380edd50374852ccc283a24f4ad19e5e11cf5ad5ed3694747e14e0cc66acdd1d1833338ed753a2d4d0c2c1010001	\\x6a95f60c5a3ef24900a73e7d0408265a0d871b5e1d6ccac69694d60d8c6757bbdcdb787e7759f80a31d3e5d2a3f9d25e4aa35a3196e369f1e073435e8deb2607	1673953489000000	1674558289000000	1737630289000000	1832238289000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
275	\\xb4fe682e072402e2b2cd0076da41219359b0ee2028f49f3623693b9f7a72f582f9fd67f3c42d31db32f4b2cb13354947f2a32ae19357e5c93ad1fc43ceb7d6ea	1	0	\\x000000010000000000800003f0451d4e19d70af8392ceab4c186256a790b247df590d0a0664e26364a3e61e50d54dc7b2363cee7dcbc8bbc7e9930a81531fb69564cdede65e4955cb229d202aef1fad7930030fb7da7e5b2b0dd7ea3eaf8e7ab490f18671017b99b601402c1b86c04bda4cce014b5d74a7aa6f8f482b108ee47d7ed7c70a1414052f82a6fc5010001	\\x5467815ade52e627ff4b206d8534fc1835db44773aacb62da381018e648de47c756197c4934ff4e2f81ec6cc0a5c6119a9ab0534daa1da204831d55adf1f610e	1681811989000000	1682416789000000	1745488789000000	1840096789000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
276	\\xb45af6fbb20939d9b4dcfac70fd40910585a491641d4870559c12d7fc59f2cc23f70e3f3edc85eece973e01ddabc01ee72b5692eed5b8255cb04bbcdc5cd7ef5	1	0	\\x000000010000000000800003bbcbb88039f442300dd960c97d655b249e5e8b036a565e40e3ed36258e4dfdcc7a1668d185948f40c8d3fcf1f086a1525bf58fe8203c8153c25cde8575cd84f86946a2c72cda1f21f69a60e7c1e30aab4957865b670bea92ab9504d66ae1f652acb694d1f15d45411d7d74dac63bbc2d66a00e92e95c1357b616fcd307461a5b010001	\\x4688b5921399833ec6347d88094786846cf3a66375d1f67c67928578d029d4ad706225e42a6f2477b46eac15c364ff820361961579a4da69b5a159f1984b2e04	1684834489000000	1685439289000000	1748511289000000	1843119289000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
277	\\xb74e44ccf4000507fb7138bfdd56418ea3ce5ed04e746ea37ebf7718615c779fadbe35582a14c06d72f436847e3d1c5c8a6ed4f518e922e09460fcdc3de507c8	1	0	\\x00000001000000000080000397edc2439baf7a091620326400aa7275d600ec517b25a9142879fd41cf1f91653969e28ee9868241d5ed5b34b2f5ebb55c5120740ddfaab7cb9296e4838dadc07ff9d0e15f53bc0c5dc33d931638eb3cabe53678592a7ad18fd5d2fc7b4b7d6e82c562ace4dcbdc54dadac355fc7a2e0eb1eb10a50bd6288fe5136d3e7283e03010001	\\x98d1f3ce3ba77bc0736866d4d657febc47407d052f578e33c8fd46902d214d2142c17d694d23f6cafc77a4a1205e44712d24d19051b964c8e16f36f9e1d3a50c	1688461489000000	1689066289000000	1752138289000000	1846746289000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
278	\\xb932b5b2eff1b671ac98b0016ce1b18902c208f83e29866fa0596d9ade823bbfc75bb744b9dba927a8c636916e724e888824cf7c5a89d5a3a5a5e860320023fe	1	0	\\x000000010000000000800003c01fedc84603b5b1df9d3b7fb80602f9572e1f890600499720fe9bbdb31567d1b4c320e33b6cf61a94ec9bab679ab170a8b9756ac8ef032e0c960df92a2e0ff41cda7a8430c5b7af8072932222d12c8a342d3b4091585dda6f49a7e6271cbae45c1e841197f54e045efd027b8203dfc6aa8003c08beb5cb653ff2d131ac8d869010001	\\x949d4cb5392efcfaa11df25c6a211d23b89b556fb119a24b504d0624b6787a0ec65dc256424b36fabcb1ae1189a193f415180b1378713f08bae531d13b873704	1662467989000000	1663072789000000	1726144789000000	1820752789000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
279	\\xbcaa79787332d50aec528a7c53139d912d19da153b908bbe204a722749456ae8583318ade8c5306eba814295a7fb757384d396f0c78847b02f4e347affbb2a72	1	0	\\x000000010000000000800003d6a815da56b5d9edb6e2453f0173d3f6852f487831237d70dae63ab4560a0377677c1f5d074ddccabf83383f01e64b0bf6e2f478b9ff978f47fa8cae8ee227c5070ad94852b682dca8982137e02d57319e62d141736de3de0c6cc48db2d72d26b79818cbc0ab4f9a9faebdcf64d9d951ce852ce1ba86d9d25c1593659c5abe43010001	\\x4c7c0df78e2170f8062cd8de4bfff7177a5e4a89989c8f5f0df3173c54a8e7dc98607dba120ed8cac79f5643699d8fbeb7d150a4744b1c454413a565ab75d20f	1690879489000000	1691484289000000	1754556289000000	1849164289000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
280	\\xbecab4cc170e3a1da913421d58eccd30399fe7917f87dc61a620060911945a442aa190995cb587ae24dd863f26dc2beba97acb20bff147b46452c99110b86a8b	1	0	\\x000000010000000000800003af947788f6c022916cd0032fd556963f39e611d4d952bb258d00b37d8dd307e87e648d13ec4eaf55df20fa76574ee75ce134f77539ae575b466e87f700bde09feb618a3cdca028fcd2ca5b8282f61bfcf7f82b0a2befeb54ab6f9c8d7a8dc253feb8157e704f0525eab4529fabdac96b6544343438e6250014a1899290e2e167010001	\\x60ef9b60b045a7153b394b506c7690da91f6436fa8f20080416700cd37c4f1e56a262abb2498092a770cf2e2059b622e272e48220a87e2b38c928127ccc68704	1666094989000000	1666699789000000	1729771789000000	1824379789000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
281	\\xc0626730ce5de0a50b11071dd7eb2d0b30299b4e9483350e145608afff9533d82a7affb032a2eba63097a00b83cec923044f03c38fa3ba73915c7dc58a785291	1	0	\\x000000010000000000800003ba922ae75233135ef56a7e2e043c6dd13f15f0f505dbaa45d3ea32e0e46a07b5b0d410899f740263f4b26f6e0e53e8d6804d09ede10babe0a366b51fa741082346a923b2a7af263289befc10e0c95c716eb026eaf3513fba5c2e13b19271e8881e4d4c13b4fa5382977ffde2ed9c4e063da08d779a1dcd1a2df4316b9bfaabb3010001	\\xdb1642e445420777ae4e69ea6892084938bef1672617482a20873842249fbb55b137abbfc0e03b15aa524ecac142d752ce80ac8f48d2ea0062edaf3ae6dce20b	1678789489000000	1679394289000000	1742466289000000	1837074289000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
282	\\xc34a51faa3a05da48d2611e24bb5875d0e80693e708c5919ceab8ecc1970bce38cbf66191a6d7d3624379f037e7097234bc6e966439f962c4112ab168600689f	1	0	\\x000000010000000000800003d2bfcbca026eac1085f3598870bccf7f5156788527cc0d963551745c02fbdfa9e8dd4724360e241d523592176fd6d235495e05c3dc99661b82b7ae88d10a63fc472251a74f309b3d28c26632688133cd8550613defead4ecf945cf89a3339238867a3cec7a8abb838509b0828cde55e726107bff6aea089aa446de2000b6c3dd010001	\\x7033381cf6d49a785e7cf6e4348688e5a557af8a6f2feac671e3648ff34a4ae6adc30e29c3e033893fe830be763d4ce33249a945233d97f2e42f813f317f3a0f	1683020989000000	1683625789000000	1746697789000000	1841305789000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
283	\\xc6ea31a4b700113f031e4ec3db4f29d9117b0c95d097702a35fa6d693afb830ea710c98bcc81c41b08b9c1e7e1cd042e74f542cf7e483ec6c02f8bde22460919	1	0	\\x000000010000000000800003986325005316837b48513f64741dd460c0cb6e73529a445ca88edb761894f4eecbead523d62fda0e6afd75525cded8a775293f6e9ebbe487b36a4850aeec74cac03cbe1ae05f6e6921dcc53774573022a648792460b5c3e9f94adbe782694105e3d5eafc4b724508967cc9b3047df4a37fd593ee297ec2fe06060489e29bcb45010001	\\xd13f395a06e17d1236c9c06b0de5f284debb65f729ffec03ba102ee7b1e610ac9c501e4394bb0df26ae0f6fe920550c65c623138c6d5371de7b208561b86d60c	1686043489000000	1686648289000000	1749720289000000	1844328289000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
284	\\xc6061edb7dabc0f56bf22ebac1163e5a4e1f5c7de394372b4b0729142b87e2663a567d90fb4497a4cde046a9ec92daa7365399cec0690b8103bc38c7878c7ce2	1	0	\\x000000010000000000800003e7e46d8a9bc15032c1e3dee0feec63b81ee05ffaf0ea653d7102a089c9718e1fda2979c282df245cafee37964272ff748a629b5e9a8cbdcdf97e07dacb7a4fefd358ba7ee709b1bd659c13f7ec69f06120772af7232529264dc2a04c3b44db46b9d511f7882907343a826df953365388e8710542f06d058a74dc87ab0eb3a9a3010001	\\xbc4569ec9d1fe323fe58797d2701dafcff0900631260df3135cf1ae715c6893509cc3a029e053dbebb56e1abe14b7ff8e68829e06d538781136beeb23e64370b	1663072489000000	1663677289000000	1726749289000000	1821357289000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
285	\\xca8aff94b6ecb5280569424dcd814f11f5113648c9dc975f41ad70236296af86d0a566186e4122b04510b472030976a255231d706e904d041b50fcfeb5ed445f	1	0	\\x000000010000000000800003ddb9a0757d870be2d32291cef3d3982669525c598180e13e2b4e1c9cd8a280cab4313ec107306a1dce814411dd0d1bf3a5e46d7d91d8abca8cc309d937ed93d183225373631a0095175625c48d2a95f500d65e9ca0273acdd29525281d5844eb0e1e1950bd4d42fa75ad2a9545953397dbb28582e0e327e8ff97113b0f7d5e6b010001	\\xed9f5a1f6f15ec597ca5b04268ba88ec8e20ba0954f4fead56558d6e38af0ead2af2c78a3239d3bacba94103b49d951fa380d680f0c4e87f97affbda69afae0a	1676975989000000	1677580789000000	1740652789000000	1835260789000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
286	\\xca868414ace07b78a75062f0c38384dbe6aa9e681be5d46d47eda5b031ee39807664aab40afa487bd55bb8a50d527eae0ef2c56f936a8ca6203b1c9faf8d1184	1	0	\\x000000010000000000800003cd629607f6aa79b5b11e67258c4d1d9aae013463b7b6d7a5932ba60940e632b730cc272ed95197c0afc18a935f89c3ae82faf036710401491c00f480a5078ffd51923412961d3038fbe87a5d13889e97c9cd7b397d55e1a55c5fc1e015831653ed8e46e42debf542e7a35daa3cc8bc8e0360562c585395b2b505f926ac742989010001	\\xf4c918eb88ee252863b57ee8bc8353837d631174f70b204a5e40fb015eb4e4cd57df9a1881e0802077164a56a9b4d253c962241d8f3d29229ed45ad1f17a3a02	1674557989000000	1675162789000000	1738234789000000	1832842789000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
287	\\xce865bbae90e33817dbfa5e442046eca0593bb7ece5a4349009cb821f20c6820f5091f7c4e05f5ec5bb61e6e24efd9c9007bf065bd13222af6b4df9ddb66304f	1	0	\\x000000010000000000800003bd97945ecd58a318b100a56b70cea8d0b363089d7d431141c17d15ba0351be6cc6d0ad89dcaa331cc18987f7b08b03b50ea5d2fde01b5d58c8264495d47bbd33d80bdaa1bbe5e4450c0f0769d0c8d865f842a9e6376bc02a59dc08ac011c5286a50905baab5299f7c2dba60cfbe7a51c022081a300e90d9c87ae0210cf742441010001	\\xff9473c124a45712f8a2528671cfef8513dd0453c6de3cf40aae881c9c5018c0436361b3d38792396d2005807619c0cdd0dee1d3bc0e276ad444ae137133b302	1667908489000000	1668513289000000	1731585289000000	1826193289000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
288	\\xcfc6fd9d56a9a8a13f6766985e35eab85c2e171fd6c85d206d93289a9fea1e3308d748238a43348766d0376ea886067cade557dea6a1c2d2167fe271de47cd34	1	0	\\x000000010000000000800003ba311aff1f2e83c97202a0e0f2bd42228170ca549afbafa8a3b34a992338fcbb2cb8e42b630b9347c0bc17657a5aa05811124763a4ad5268f2162d4c10227ec1198edb50c3b825d48798a2aadba2371e09654cbd4da448e84151d5663ca32395dfb17651375172b5b9c193f13fddc2ac842d6324e071fa222d58ecfd6baf87c3010001	\\x0a33573a248179208c0f2c4c8a68096ffb08d12b537269a651f4a2216a679c4b9cbb66467d64b65ac9182da222a4e876072fae381c9490ff50fc0178786c810c	1686043489000000	1686648289000000	1749720289000000	1844328289000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
289	\\xd0fe2f7cde9718c5040525736b47fa40665305fd591adc53974732a4d8230c59c6cb06ce17e50f0b9f6e9ed1818492c40305891bb6ad1612385f5aa06dca9417	1	0	\\x000000010000000000800003d4f45c65dd117972b4507f7cc56ad5f784cf5061327ef47109f57bb5ab1508ae4c71b7cc7637580640b0d249448000c9f78f823802db8178da43c5e14000bba07ecba010a448f6c0c7a7bd4a973e4e536eaa6ba8d93177439766253ef583dd087d9aeff4e3d7e15adf6531c3993915d93056f485537a836ced0547d8d482f6dd010001	\\x7605fbd01bb42ff1d9a915b4677cdc16e9eafd83085ec64f068b1f300d573f54f4d1e728db74c93f87768989e7c9de6320de8af169104cf09f782b1f3d60e70a	1684834489000000	1685439289000000	1748511289000000	1843119289000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
290	\\xd4d6d2542e02edc832b08c1544447733fca976b26092ccd5ce235241656a519fba52c81d6a363a139f7816b3f04933b51e43c5d3c7a40adabea36256ef49c1be	1	0	\\x0000000100000000008000039a1a8ae91db2c42c0344bc523e1a93065a5a2ad0060b7c711ab2d7a9320b43126d88ad708b9ac6fb629012fa26947fd5efb010187ba92e0ced4d0e57dfc701adb0bd7caee6ff2bb3bf813edcb558841b22a3ed36fa995d66d12ba4c8191b764827e736794325f2741dd4573c05693df8145eb369b891483a9c2e3cd75b0aadb7010001	\\x40d27ea22166770c65d18da8e0cfb3f623d339f0d9c785fa5a5a9b14c8386bb4af30b852bcc94462e23551bb4cd5b5a3db534695712cd2972021e3c3d8b50708	1669117489000000	1669722289000000	1732794289000000	1827402289000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
291	\\xd7a6ddd11169b72d249b5998116bd056703b32427b9197dce447665487556193f352ef7bb4a8dd9ecf9076a9c79302b11740916bd7f50d1c5e2abfb56248353e	1	0	\\x000000010000000000800003b7f05fbf4e3a3f30b695ff187859414e72c5c23629cd190d600887cb8c4f46bfe72d3bae50a7832f90e92db8e53b9da744afb91f4aa31bdfcc4bcd65d39a67e44fbca6b4469ae298b8371e18ac4748ca32eca1df5d6c9b04bb9e9d49ed023a115d88e4e68b8cafce6be581a8f2f7b8ecafd1f2c4eea5ec3aa87b5c64d8b69c43010001	\\xb6eb724bb2a948dece9aedc3ec42dbae5326096b70d509763a82b1bb36a0e963298a03e8c8b0ab5af32c7759632a3f86a9f46579ff69563d1fa49be8f506690c	1665490489000000	1666095289000000	1729167289000000	1823775289000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
292	\\xdc2e4edf3e610cf2b7d1f98cbae924bde003b68090c29a8d43ca226948b344bdd6b3795415423777f420e6643a2c649781264f150728a4f6f64e3053f17e9087	1	0	\\x000000010000000000800003c4ca7ea2db9f8f07070a6b195858ce9a6bada44bce32e211ad7c5c5e31c62bb088dbfb3bde5f84aa53c49820c5fd30a1a77f681a50b57a6597f539378b702f3e63a73b35ce9daa60ea4f3f5fa2540e65d22981e4695107f53d8fb0b8743c67a34a67f9dde3061efe2226fba4612b84da0c7665719ee74bffd1f22a68b13be62f010001	\\xa91faa443b321b2cd736fa8c971315e59ca03f0d5a8e1ab1b7bc8c5095795c0b0ad93f3331de14588d6d7584ff1194594b24f813a0c872a98f3e13a2bf7ddb04	1678184989000000	1678789789000000	1741861789000000	1836469789000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
293	\\xe1561456d3b3deab92bbf1d1c4d59d524ef23ab6f33b9fb3f6ab7d80bb9701bef3ea7caab93793b7269cd7ec3e67678fc21c2f3608d7ae2373fa4433a4a65c50	1	0	\\x000000010000000000800003a2c516cb2f85add45fc17c84040e5f003e81a1fbd3d3b3127feb0bbf0f49e64a589ef4b0b121f17a1bc3d2b6720be2bd1e9f140fc2794aba44a3c686087a4824ff1f4ed67d7812fd3239b6f01350e5a8dd2029d75f6122b9597a8d80f0ed4849f45a20cc0e351c0791481bdf24b5556d8838228fbacc7df6a14ab5ef9cc95db5010001	\\x153ee3c3c1066ed55ff7d3f24095d56292f3f0fad1df5568c9db863b227a2ee83069f980929b3a2a494358fec6d660b5aa0a9e123c0765e15fb89ff966b4dd03	1683625489000000	1684230289000000	1747302289000000	1841910289000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
294	\\xe36a8feec18a1dc233fce8392761942760db4850d21ca917153acb67ab8652dbe74c3b6c02d96230d2972de2e5b3bf45933a521da152b766fe34cba715eee3fe	1	0	\\x000000010000000000800003ea490b411e6b21ca472e4c029754223480547ca97729e21aec61917875f7608108e84bee4675c2f43f9c9d2e1dff4f6cdaa32981463c678308ec6de8efabf4ce43c0a582a18d8ed9ee6fa8d963bdf3314d27aae0772995c5ddc9921c09d251c9f23d6282ddb9ff2c70c1287ca20506de4b37a8a6cde67dcb1b774e565718355d010001	\\xfc9592d56a4e4256c0028133774b32e6c3ab4768630a09722c5a18ed0e3e0e4a5a5673aab48ac3a423e1d94fcf14390e9de3f2585d544b72b15f0e7e7c14710e	1677580489000000	1678185289000000	1741257289000000	1835865289000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
295	\\xe7c27ece2b76e5370f0f8891d7e0811054f4d6a527502fd1f4567be32e87343aafd0b9971a2591636b6919eb015332f7354e429ff90ff5e8eea7d35966f7677c	1	0	\\x000000010000000000800003ba5cd51991cd4ee282d762854c9c98487c765d42d10f47789b94a5df6a61de73b0a06ce2efaeadacf993147056554f508cff4b31823a4970151d4804730a42d21061093aca9a845b9576628776c0d587bef25892d81f044778247c47540ecebb94509efd5fd8fc2ff3c60a1699b23cdb69b32a3b12ced3a955a9859de495bc55010001	\\x35153ef47b809e929962b103ccca7f2a8cf0073c750d2f36ca3fde12972d72baba4999d315f1b8935b95ea692b95b1e1969cfa305be8cd6f1dc39d42a469a70b	1670326489000000	1670931289000000	1734003289000000	1828611289000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
296	\\xe8023e53b0e5f9e8ff9de040cdbdce928da4c76cc166cc80684d51d4a6e99c8659974be4d0410a3a8160b4be1ab97b5386dd38bfa19ca06f4de931fdef62eedc	1	0	\\x000000010000000000800003f4caf0c7464b3177861a43331d175a281396e9481b7b6d87e555186888ac6be8210152f6fdbf35f5ecfced4b3f50737551840776394d2dee1c0c421b305c8697516171e0ef025bb615ef4a6e3d6c85f5023b0c461a4777878b08191994004d8534121f71de188177c895ff94663c2ef90e6cfadb6f2efe669cab3de924a05d89010001	\\xb4baf29a5d6f31cf90b6a99302ef112289946c428f06aa1405df8597f33a85dac8125dfedf4dd748a75ee37ea3e7889d54215ce4650158539a1ba0ad94c54702	1684834489000000	1685439289000000	1748511289000000	1843119289000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
297	\\xe862b96f1e26607ceedc0b7da59875319add2b86855c5c8ec18595c386aba9984e6c159cc1a0a0ec7e30be19e9cad2c1e93d2384f980d4e489d05f641d4626d1	1	0	\\x0000000100000000008000039e81ac56a1bb4e0ec583e3691e87b968b94c396b7707ef9eed20b452d013c4b46d37852b5c1e29151977e560c73bb8fbc17be52c0aec81bcecf94e18527c9218e89aaa29c1b25a33b89cfae2ab1bcd50845dd12f849371a2e55048ea304b4dda22297f4e237bd8a5bcfc42204ebef70da685d81b199ad1b0379e64d790b58cbf010001	\\x4ece21a978dc30519c44713671d51a7b55b1a1df5426177bfff9efdee748cce8ee06bdcb9ca3ec67fa25265e198734ba6a0983517f72835a7fad8be14847ad05	1664281489000000	1664886289000000	1727958289000000	1822566289000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
298	\\xe92e2569cb398be38328a9a71c9af98ed3a8a6bf77e42b253bb83c1e42e19ca1ff8615e891eb8ab219bd81195ed6b4ced86284a87a83a253ac76c39b4c0b7ac7	1	0	\\x000000010000000000800003d22798301ecc962e28bbd935c7c9613bd0060c72889f3cbf9c7ce231535095ce598c01358847cebcf055f14424f36343059f31b583c254ad949454fc88df5ab3c269c246cc597d2631395bc3a2c07bc86428f0c0485c660e7f55dbc04b141da6ebd62ab7bbff5887e111e11cef5e545f48dffd62a86cfccacb8722532c2d5a19010001	\\xaa827048d7a4444b2497ce69999906ceab9600a8928a2fbdd3cb2651e7bc4ee8950e2a77ff002e512e5b6582e5e8bc7cae8b1c2dad3174c7b1b22e9cb4066c0c	1663072489000000	1663677289000000	1726749289000000	1821357289000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
299	\\xf07ace7fd29e500cc983339c742fac67e23eddc781411d09333faa7093484e3f5414197fa6462202425aa0f20f08626c07741a4a25a9aeb38220b186a8c1d5a2	1	0	\\x000000010000000000800003a87abea5970047bf2c6de511b6973563945cf47eb0bde47bbb457bba97c1b338005b1dda6967b3b9b72c60ed5e15c440d3a02de1a11606b74ff279866093c27ada6d3afa02e70ebe4076352a2a2e6010244bff27a48b2dbb86743df719fdbecc35c4da4e2cf1e924c5be3b00ce90d567f25699e58f1be6d778c8d8f92c14c733010001	\\x782d8820dc6b8a1a5c4bda70ceb86bc3446d17e762850198edf7c640f4cc0507419c1e3fe244ec3af18f8f9ea14b5613b4826d02e793dbbd05ec721e0fbe0203	1675766989000000	1676371789000000	1739443789000000	1834051789000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
300	\\xf10a33d8ba0e514710941cfc2810e45ff85b7e2eb03b3972a0afac0bd19fa84c3c3e74571c6c3b3c753e885fe4a81028b602bae829b3963a26fea49a6c02d45d	1	0	\\x000000010000000000800003c069e11460b49cb5ee581d5ee1a43a1c13716dcfcb37326c687465470ff32f59ed84883dd216b00cd0049c43ccac528f2027c0999a08a1c0ef49811336dbaaba436bc22b2787ed856230d8fab931b23bb4557cd540b52623ae07721916b700995db7b6b12003f1652b8b893758d9509f7ee9a8e30bf5a99a1887a40ff8d168b1010001	\\x6681ca5950248917a3537fd0862296b0fd5003f8dcd7906856bbba42548f1805e35d85f9e50cb8e252dfe62d143d81a88db263d06c0b4cbb7736326a231c9904	1691483989000000	1692088789000000	1755160789000000	1849768789000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
301	\\xf5a2720f96c8af1762beff543eafa0a33febb3888fae8ae28affc1f6f34feca92a94d267cbd951ec039b24785e6b8e415450dd7bca4c37f87a5a668f02e5ae96	1	0	\\x000000010000000000800003c4e65b2a5417cb623059ea93eff95cbd18860c92d7052784bb32d11d861280b478589950fa660313aed053ab296f1b0bb9f026b5783baebf9b25409c640b24e465b0fb72d6b3d804895f14708a7a87ef4226c38cd2dc1d680ddf06801519f5050e5c417e1ff4d89adec83073ec1c2ed62ec0d0dbd03cbe4523904512db3aff53010001	\\x5397e59448ca57fdb624206569816242d33ec325ebdd2b6bdc62ccc0404cefe59fd7115bdc0f79033e3a0a056fde3a55d93c3058062d7fc32b0a5f63b144510f	1675766989000000	1676371789000000	1739443789000000	1834051789000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
302	\\xfc2e7628db79eae8624cc0ef2a7e03bb29ee8c9a9faf456b3fa98e51dac8f634c9f2d8cbb0423529dee70116cb80fc732522503f61508e8fe1273f64cf96f31f	1	0	\\x000000010000000000800003bcdd7edd49d8a0aea28796bd2b9f5470e6a0a565fbb7e27fb9b017aa1a3feeb8edc24c3ab83989ea0e9b0a2e7348ce18d935d37589e70e1d9ed8c0d629293c31e21bc9d6f1fad99a0cb8514724b5e1bbad787fa344557d0bbd06c29106a744edf07fe60046f3dbca09c1d4a29dcc1b8d5ca9d9848e45fa62884ac3630961eff1010001	\\x52a62ca19702ca2a81b8f8b69b53ed4166b9042047904fff664507967d23c35989a8f6f35eedec62d4eb9ebb8bbd484a36d5ce28c02013eb5592685abfa6900a	1678789489000000	1679394289000000	1742466289000000	1837074289000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
303	\\xffe2a49abae85ed33dbbdf591a7c8e2ef848fab86e3c68ef4c7f25549a686d5b759ee1ff268f563a3bb3f487aed66f6f524d1998eb32aab65addb0213272b2a4	1	0	\\x000000010000000000800003aa4a26d845ececfad7cbc52177b0ee80a89d1fb01ce9118e4e6e662c19b7e689bc5dcbd6864fdac03ed2b62a403a9638a689d488f88b138fe3d7c698705f1095700ead65164c71d04557a735d01bb5b43b5dd85f3b5ef5b1865d554edfe46826379251c5faa9346b37d64afd367329944985465790c970d347d1f3f450c23535010001	\\xc9c2cf57dfb463f110f6e813dd789e8d7540e317c5d15e3cba947ef0858c04ab4d4743f1b948fd15f9dbfc2456b949e299482e00b2595c467c74b3efbfbca10d	1683625489000000	1684230289000000	1747302289000000	1841910289000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
304	\\x008fed598bff6fd35526be5b08e3893755e36d205411b5f6b4083f840520241260ab83b042f4e1ad900a8ad1bd3f11448ed461db3134cd7b850d41cd5f23496a	1	0	\\x000000010000000000800003e239c89748c5ceeab4746dcbb98f3d1388041cb8c904a34805fa33d4888b9034b5dadcced7000c2bc05fb313cc3669e5be333874526faa6e0bf9e1d0ca70c3e7a01c89638ca135fbaeaa58dcc062f6f91f3dd6dadb09b0334d99cc75cfc1c7f693001f7c4e9513869374ab97a175d7f755c0d5c3c60b915c9ef60d76777f1081010001	\\x218ac5cb420c9a4709f40c7e393adb63bcc3610e7654d3cb7bcd30ff2078dab336333f305f8de66e421ea70d74ecfe8152ed757cd2443cfeeb4467b28efdb400	1675162489000000	1675767289000000	1738839289000000	1833447289000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
305	\\x05ffe69e3d1f484481cae81b0b57e46e537e7b50f16153b3944a3a86e22ab3a0f65d670584b92f6b974f87ea4dc4fae7a379dc73034421fa9b2eace8c55690b8	1	0	\\x000000010000000000800003ba933f21f00b7fb02462ae66d30fcc40e26fff31f483dcb69fdaa4ade6a7048d35ef79af77ee58031883c7d3635312b5865e5848b1f3ed1980bbc9b4c19a2f022a6a4053a2861c456219519a67105d464a97ee3d72bc676224fb33ec803cfe6ca2c766dbf05c99a31f093b385b572e459a5c15f6396737d6ddc2e87284ae407f010001	\\x55d76274ba0a0bdb79ac5f34a7b91bd38060755c2b8272bbd7635020b5d029598dd3333fee8b228766d2317a01217cf39cf9a52a7b79a8fc02de88d507675800	1676975989000000	1677580789000000	1740652789000000	1835260789000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
306	\\x074fbedb64500118fb1988e332f686165e73095da6e82cced085f87c5daa1931f40dbde3481a236262dcfb2c98cfa0b3ddce3978a0eed68a5b3cb2f353bcad11	1	0	\\x000000010000000000800003a44cc67202ed6139c31b0cafa6a93e09b9d7fd519d38424fc5bd624ae9b29b3cc6b3dce5cf8ff2ca1837ee4387a9f03f97428d43b72abc8726ab140d974c3af735fab6fe8ee3937ca38eac24c971198739091306023cf436c1e917e059f9349d13f8358c21990de6e4acc1c0431e8096a458227793d8e9748d82aed18bbb24cb010001	\\x2c6317090500ab3f09dadf17fc2a3d490e579474a8b9ab9d5c1a6f148a3974b27b2cccedc20e1163ee74a0ae5151fa5860c1356b891155d013d495d2c2d7d70e	1670326489000000	1670931289000000	1734003289000000	1828611289000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
307	\\x070390e76f6e4193db745ee6763a20c39944ed474218ea0432f0281473381f162ed5dedc3406157ea5eb9b2893dac6ada7a7d6097e80b3d9e78f07f12a7346cd	1	0	\\x000000010000000000800003d136f8bd85a17fa1369daf370a7872d54d234bc7247869d8b1c2194e9bd51cf01e0b1c16abee297b170b357247d03e7c5bfa853be4ceeccb9df297dcf544bf269a66afcccf94108b7469c30ebe72df7c34e0824de204dd878f062b7153553a49880642781ed25ede9d6eeb2429ad49bafde5dadf224da85e95912206dce6871f010001	\\x0fc4865da524fbe7f6958710c0b6137072dfb5c5649ef22e0c1c899ac8d6aaf1354f2574110cee1fd8e978b465d3240250449a3e93a538e292fcdae06059b507	1692088489000000	1692693289000000	1755765289000000	1850373289000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
308	\\x0eefa11161020271313e18d4cff1a795219a57be9d08de859a796c72bc439242abfac770de1c96bc191e3ad27f16db2c8ed3f81491669c3f60f40cc8fb3b6e2f	1	0	\\x000000010000000000800003d87f8e87d2d045dcc193d42800f9c71afbcb720a7ed357cd3a7ed59aaddaa4b7fcb3dff1ae1d40d209864fa037b159284e036389ad1db55582ec3d0954c9cbaa67c236c00ca550db8036bf96700ef75efc0a7106f07e4fc8aa17bbf9e8a53e78b0d1edf7f0863078c06fd28c1a48da1f8d634eb75c2b90f4cf0421594fa46033010001	\\xc435e59806b1af11a10b9104ebf87f3e7ad1d71557cbad83e053da611220e61c5ce4fbd565fb9cfd23f6aff94ae43f4bb2e85d78c6c76c1a392386053e025b08	1686043489000000	1686648289000000	1749720289000000	1844328289000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
309	\\x0f7b605468c9fcc30f5fc2ee623a173f9b7d8952b295a3e93fc97be0e2bafeec916e1507f4d30743f5ca3376be560f1b565e2c1cc0388bf4806fda1b843f68c9	1	0	\\x0000000100000000008000039e1f83aae790d1525fc17a9b9a333276e6c2a0af5d21036056dce86b46c776bab0a571191f2d8d96f0ed0ef5c0e364d8b1dd80419967052763f81c71331770410abfa9e3f6285f52428c308dcbcee4f4decc6a32fb0f9c559fef5d888bea39ad08ec3abf272dd6a64e9245f1e62b6722d806cdd654c2e7544d3a3102522284a9010001	\\x8aa93a9bbe49d109e8c6b72ef639c226c4389fc57832d335c4a0d1ca137076f6d92176e33b40b07208a21bacfd1eaae743931a50cec5ce7b18e0f6448af3800e	1684229989000000	1684834789000000	1747906789000000	1842514789000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
310	\\x0f5bea0749aeaf19b288797680946fe64351e03b09a2b26c2c92cfb54072af58f2a25311b340655edb5524c2ca3202a7241d68aca2fdffbdcf40183ac29b6718	1	0	\\x000000010000000000800003b206ebbdc3cc31b458bf6876b0577a4985e454d3a42ddf674ecb394d53e219b87855be48d0aec8ca2433951486d2609d7009e75b8754dd27031c43cc431516d555a8b5feeaea35720c2712f642817b94c0d7ee5a9eaeab5438059f9bfc9e9cc2de3da05a2519f47638d0dad6bd868f19879b68adc6745be00b4dc028c86bfa7b010001	\\xf371bb3a3b84a9c4e873a2fe9e3ac61946157e0b356695dc19a896541984a1f979dae82f3143588f7dc3cc50f09a0ba68846fdfdc4ceacf389ec4cf5ebf0e505	1682416489000000	1683021289000000	1746093289000000	1840701289000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
311	\\x1073c1ccff7be61507a48b9ee21ae0dcf2dfbcec0a90bb4a692884d4388ace665335d64632ba3beda2b1c243f4bb8f88417dd3c22c6c39970707136bf0e1f359	1	0	\\x000000010000000000800003c0a87230a5247a4c9696fb69f95fc8fe004c8f4d1ba8e0bc581525ca6ae45ddc854300b93e909f45f9a84a3851be79ee4f22a781e0dc4471f34e1cfceff3baecf7eef2a30c1c305aab0ace47ef7c3ed0030da730bcade15d417e64b339b575143fdc4a56f52baeef7cdcbee7eba5032e59ea63e69f7552ff717f4fa314718407010001	\\xb8d4ecade075e17ceca177b4dcfdf6f130c1fb403dfba97f6e61d39935230e17faaa6a6fe8362f61f4ebddf2ae3ded24d5484fd330b184d11a78a494f5c9ae02	1679998489000000	1680603289000000	1743675289000000	1838283289000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
312	\\x12bb0f26f60bfa1e4c1593496de80bc010bbfc950ad2d6d1b1afe0d7ae004a900eab2cbe51ba74468078fcfa8488ae66ed513ff0c72f28eba0195e89a11d7d11	1	0	\\x000000010000000000800003bedef47109112e29ca5a08c096769b8ca315f2bfe87b9f70fc9165e2676ec9e96908b3ec0b10ba09510e81e6ee8ffa6854c23826a87bc02389ea3e82478bca6e8720abe011a04b4fed63ff43b8d260f88ae43a3f65ab55733ee5c3928428fa94f6fe8ac0267138743fd3567993a0051490e75807154f6f6fb1d5f8a2aa35ffcf010001	\\x07376c9ac1b08758dcec9d8d006ad4a5a7911ee8a4927e1b54b316193da588295ee955e36925878c59140dce466d41e6bc30a1868d1fcb3de68e7e6a46065004	1672139989000000	1672744789000000	1735816789000000	1830424789000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
313	\\x178b9b541ce3ff4833c1931c074433837df3345ce07023ac8c0f192947b945b89cd883c4964a7f7410e2ca37e453ab4b4ebc38d303fd1bbb9f2b4575203a850c	1	0	\\x000000010000000000800003e03198ec0979f56d9cf35b339512a7a522c1884b6a141144b84f4cb1e2790b0599d431c43bf06b4ee73d39f7aaaeb2b7c4c6b9612edde53cdbe3dbb367f3237270e2bdeea9d70f8a49138cdd7c783a08bb0085f6fad595fe65427ff19587a460109c4ab9bb4e0060c671c61f7d48210485bf2b9afa538df491c83931c1a77329010001	\\x6e230fb4dd454b41925cd0145e24dbb2a9c3256203c65bf0b8e94742d15af53ac7d008f8ab8bffe7375fd7ed6181d7f75ba06b6c6b6753c1916b9f3ec5a36a08	1690879489000000	1691484289000000	1754556289000000	1849164289000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
314	\\x1dcbc28777322f4d1e1ccbb6ae70214af876d26fe72a2fe87452efcee4b903a91ea2fc654fb0c1c01ff51b577ecdd7b7d6c8751a908824c9dfded3d71e82d215	1	0	\\x000000010000000000800003bbc4b8c14e1ae6f0c99f33ff4c7848d8341dcebbfed6815ac9c1c530463c8ccc882d6606728e135af5132437ba609078df1dcda5ec343dce22c9941b26b9b91f2e07106e5301bcc344050d2c542b0696ad1b1d651505ccdd3c0f7579078232b29fb74ee24910cf8a1ba15f8a83029502d7f4a83672452fa629c6d5a8446b8065010001	\\x45703a59fe749323b132b10f91b18b3a15238ede33d80b3269560b84064cd5dd245771b69123ee1adf4d7b9cd4da6fc48d7f2478c63b184467004f3abd238305	1671535489000000	1672140289000000	1735212289000000	1829820289000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
315	\\x1f17101ce49a7844f520bdc75fea24f62386a9a06c7cd5d08f9408f93ddacf41ee133abd289e95ff1efe586944b2b475be89ccce7485091e13c2da9023d24dc0	1	0	\\x000000010000000000800003c05ae886b306213421869214982a42187997acb1838762416bacb02005f05339ff76873f41405dfe6872d712450df6e1cb2d03e03b38cef5251b26001256400a51e03174d14a713a1ec88833cc18d435429f976336ad683417afe0111f12c692dda91274290eff0b73074f6939782d77564ece7da6004ca6f86f9af2f61c72bb010001	\\x6d4962a92f47318de2e4a867799d6410ab4e78630943968be43c66432db90015175d15c0a87b5b0214c8a9dc1cf2c519a477fd1da47e5cbf1ab24116881e1d06	1667908489000000	1668513289000000	1731585289000000	1826193289000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
316	\\x2027469fcbbc95e40d0df7ae4403470f3abb58ff58f94b2adb69d5991434a682e521510ca20605d46ae815fb531ac263ff6a0345c119314037e873022d7d1404	1	0	\\x000000010000000000800003d7c02074e5f1cb9895cd5bc3eeed0f7de894c3f76e19e934fc4ede448c41466e22367a7f84504ef8d2c9fcb8295cde9a17b2201f63b185d47fefc4490ac7cdbe84599a8a1146efd6a1e6b28d09bef3a7c42ea6792b5eb6136817c497453583b30fb1b2f94bf3470be99fec0f89a942672a289db6146509b1d12ffebf605cabb5010001	\\xcda9cc3e0f254b1b1217a6eacc624f462f73d4eee07409d0c25765a601ea26a138faa81442188b57ee435f179ad0acf5aa357fcf5cd418da04a065762269ca09	1664281489000000	1664886289000000	1727958289000000	1822566289000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
317	\\x20e307c8416a955bf1341972acf0a670da2b6ee32eb75441cfb47e0e6914dd511b048068a0c571d13060b50e34673b4a6972474b8d689170aab8a1c7203541d4	1	0	\\x000000010000000000800003cae1dc3b2c6228012fda440e0b1314e27a2f62c8225aa0f6da263ba8d169af473401c70ab1323d00eee3b0b87a46a2f17483302c123812d65d31f573c581108447402b36e75edcd734e59e75b66c19b073e4129c6c37c4fea53c9a0287a8f66f75fa74916e3311802aeca64d6a57afaee612d64ac214c265d126d4d953cb91c3010001	\\x59b9490a9f5fb805f2050bd919b63a13438d40493b1d9c75b511a14bc14f0fba903847a940b29be62bbb4595de8d3afa3042882ee989ca9088a95d5b8f4ba80b	1686043489000000	1686648289000000	1749720289000000	1844328289000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
318	\\x248bec0e9ae357ea23467c45e54fb0dbfbf4ae3ac3ca352bf8c308848af96525b0a579b7a077f6ca70fe657489f660e2c1afe80657e405c2c060c504fc17a70c	1	0	\\x000000010000000000800003bb6f83c160a360aac75d9d4e517931965dc73e1c2b5edb3d07f4dd34ada1a9784312d9f1946fbeafe58532a681d8c89428be852c5f367563f2f7bf28bc31d8b12b8502f53c4ed95837734cb5d13da3bf8d66f7d631bc1e7351e237a41ffe55724ec45d3b5feb312b2acb1147c9d548ff0596fd45596ce56de10cde5048f8513f010001	\\x7565f68ac11f6e5610e4c4db9265c359c9d76b5f3b10ebe7b8a8d825ec74d922f1f1d61ea2237f765d1e92433435ce8c19e3699423f7d8a3e611745e9682d50b	1663676989000000	1664281789000000	1727353789000000	1821961789000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
319	\\x25f7d6eeed4c65e4cb17f11a8639bc6725fc42caeed70c17decb91ba5e36f5c0c396ca3aef5f03e63d46a619a6495741a4c0e433f7c2f20af1c1f07059b170e3	1	0	\\x000000010000000000800003dbbeafe80385753eb23a05b9e6885421991e4321a1e495234410fc1e095c6026ecc0994a36e7e02f4fcdf2a2023b5ce99b86cbc4e995fe5799849060a4eb283f0466ebb478929c24c85817f4c2d2b6166c64a29c089f64cadddf56a4218385597ad535ef5a7b16a4720c4a6588debbcdc3ced366ccbcad47b012f99735d2d2b9010001	\\x141268241612948b97087fa76e7fdad1788ac87374014263a919ee854d4bee58f963585088838de3b99fb2c3a6c3d42e28e1d58f32a5f3565ef34fceb3da0909	1667303989000000	1667908789000000	1730980789000000	1825588789000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
320	\\x26eb9b4b25b12842b9a721704ccf328e91856fb18963f0b928be0b11bdf858854687ff6b05c335643cac68b3a6e16adca83c78946e770496779a17ad2d8da689	1	0	\\x000000010000000000800003cb780e1d51e269de7688f9c1e083346231d067129d58c424f3ff04d9d3a5e5b29100d8bd6c3118a10abf2c4f2a257ee29451a74201d48966ff11cf4d6bf3257077383a72a9b34ee6dff7368c01508f41445f4fa560b7642ed5beb74b5f2660f0ccdc3b686af4c6af76900d61bfc62057cf7948cbff3f5d2b472cf53beab59f41010001	\\xbbc6afd7a84391bd4b7ddf45c03550a2da3ea7f380c64964196ea9a8af329447187959cbc8860ca471657eadb3110558450183ca80592879b23c4881099e250c	1690274989000000	1690879789000000	1753951789000000	1848559789000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
321	\\x292b963b73efaf83b5d35a5e21cddbe238fd52216e9d6d5334ce01bb20d4a3ab88e02ad2fd00068a2502c77d042fff7aed422adf5009b2cb60954270cf4aa0e9	1	0	\\x000000010000000000800003c54e2d5d8b7ebed5417cef6fe1b29ca3fc739116fd70206139f8d27bb6de985dfc8538464aca402bbead467ac8fa20fc2aecfd72872eb241dc964c4833ccb2f37c98fd6fabd51dd71dc1c1925dd9b9665d97f7859157b663f4cc9a5c14d27e6b5470b376e25ff3e917b56aef36eef2af9189e0d7da7c3857ad8df831a7709e01010001	\\x4f9a08e1fe7ee416f8409843df3128f5f8b24fc08f3322f4aeedcc6d9623403ebd7391ed60cd29fdde11ffcf5b0086f1f01e01d98c94a36a9eb1a130ccb6090c	1690274989000000	1690879789000000	1753951789000000	1848559789000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
322	\\x2a4ff1e6ba8e630a90d8e558540f2c4a8d341bfe421c3237ed47d86f2778eacbbd7a56f07fdcd9f6acbf21a87dad6eab6a64de51325f8b663494637de8778155	1	0	\\x000000010000000000800003cdf7e6d6d5845115c049b151210e9cf401bf9c744e3c93abb23f9935f45981158b1d64801d417e60ab49b8c4e784751267f7cdd792c565f53b15f5a02620a8b447619e93b7daa461d46ffdf4751ab95fccfb1afd89bdc275dab64c6f28c4092bc55de13c764306d069f8d8b765c17aa0d0e3255806194b8c2c6e3fe226fb3a49010001	\\x0e4bc2844b2df348f3edf9413ca380f5138e2290e64fe6281671bad37a2e8c37facff58c2c898e3e9b15d312b847e2cd72774e339a1dbcd29a2b285a99f2cf03	1680602989000000	1681207789000000	1744279789000000	1838887789000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
323	\\x2cbbdfc75d73223b861ac701c62ba8f89c59106e5c45fb8a885eceba1606d4dfd2a4f278f4b45b859324c557cd72d43203c467d0bd50be6b07435d82f59e1df5	1	0	\\x000000010000000000800003ceb3d91dbd8881030fdc3b040a745e48756b27d57054c9ff8b47af9df2cf1f999d87d46cd4a6e5453cc9c748f40839595228009a6925b316abbc8d8f470a16a2f6e0c8e67377cfd64d1762d4ecec64ddea7267f4f9696f1ba4d3b2438eea0a4cb5a37e50784abab3d93f85f5b2f08f843d418afa978ee92d6cc6a17a31152a6d010001	\\x6045d2a2f1384ca92f33236a7b2713d6441b744a6369649d120dbd9688f216a5f4786e39a13460eb1c0a61720b76b99a0fcbe9e0e1c8c668e34a5da1ebd63207	1676371489000000	1676976289000000	1740048289000000	1834656289000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
324	\\x2ce748c2573eda3430b501efd2ee6218b2f1b23c7cdc384f6f20b88a9f96b622aeff6b5b102667b3762feda3bec480eb9cd0f7b779718a9e357b3eaccbbc4ea8	1	0	\\x000000010000000000800003cecda04bbb33331420cbd37799695c0eccf1bcb06685218acba943a04c6343522510a096672fa69799d852d713bb2d72acba4f401390a4185ec37f818a4a90208fd658f04267b587d57a3bb2c3d73fe182110e5bfd71be7af7c26445ebe1c5d1c7f07e5cee8369f837cc8af61b5107c087c86108eec19cf12c29973107952469010001	\\x3814ef79bcb3bbe6c2e406bc30cef90e63a70ddfe53cd117ff695e8a9bcb2ac81b2bdc2d0b482308ab4ccb971b6326eadbf2af732e865c1c6235571a1ab45b00	1689065989000000	1689670789000000	1752742789000000	1847350789000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
325	\\x305710539f2a34e4f85eaafece7923d31e436756590918e5bad4bbb61bd92d76469520621c88a8d369b4ccbd367f1323ae4039df7d36fd852230fe7293aa0e74	1	0	\\x000000010000000000800003f7fa4ae789a6d4eae617100ddc1374509d6aa3229e83bffd03f31a041870b71f3d24e3dbc77d7b795315418e40ec313b6bdbdb1a991323bf526baae9709ec58625d5128377b383a03b7e00796b5ba13147c4d21749ce186a41897f7f3fd6457e554f82b39e70c9572c7f0782d452a139820a1998e7196f7097065fd29e1cec03010001	\\xf9d9b0adb4ae8b062b0a3ea0b637955076d83eda6f40246e1cc457b5432b2f1b70a1b0ff1a0a339ac3bcb86141ad0dc48f54f1a5dc227bbf50dcb2215251e901	1665490489000000	1666095289000000	1729167289000000	1823775289000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
326	\\x33538c0358c8f605b04dfd1fbd5d9901be20607a8074a41a2a0a35e03086469a77c7f77eebc0024d8206401937f1a6fb1214219b10c66f31d8dc050ce82c72ba	1	0	\\x000000010000000000800003db7077896f7fd91e851c491d2050e5cceed074cb2cd4d39b89af3948aff69f5d7e8b5cc0b08dabd6a80768c249ac2ed9b9ead235dd4783e3450016b9aabe2014666258e6778b48d86cbc678090e4cad0f144c86df511f7daa582b22949b993c35d825cf3a68bfcecc07fb63f1530cfe33922cf1f632c40abd3a629c2e6fb9759010001	\\x7d4015be77f55234318f5eb0783f8a5a99fab075315fff9e221d00f2d318676035dd6ad3a1cc451b8d51edcedeba703038f7bba3c8c3476fb9b291fb7c1de20b	1690274989000000	1690879789000000	1753951789000000	1848559789000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
327	\\x36d35c1bb739a355d97a7394056723988e3cd30013a5d45d2d9776e6989deeabed317e401ff42045b05471e50c8dc2488445aec826efee24e0a06980d50e1577	1	0	\\x000000010000000000800003c8e15f95627bc25884afe2e58a483c9534573c6bf4d9762e62053aba6eabc7cb145de15261df72210af7409abb7836c5648564693724aeb47f029b66f4e4f52ed70eb3805bfec53ac05f159ebb8a48f37a113157c571aa4e17832b75df7387eb73ca24cbf01963fe38d35a73ec1a7728562c78dc15c96d14a10ba330c93f4f63010001	\\x5c29badb3e5732a7be171adec24d86724eeebe8522b41617394fbcc352ea14bb51297e592b162809652490dd0a9da118a3df0fefca8ff54d6797614dedad7802	1690879489000000	1691484289000000	1754556289000000	1849164289000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
328	\\x36f78008eccee1b1eb07d95089718f8f9f223708025729ae2fd1b46407f40abfdd70374c271b17fb56c32cae20adb6f4b2fc0fa2eff8582ec93a7d865f1d301f	1	0	\\x000000010000000000800003bd118dd021e176b7b3d79fc7bf9d09c5f388d849ded1c19f28312a44cedc7e14ed7a3bcb0768f9f1e2948ecbf9654b4df54be315cf533683374fcf08a6cfa82665406af1416cb5758c84ee47eeb736ff1c6004fcf8366cb2976f5c6a582043b6761b7022ff0b3a5dd91c81ae2d4c101ead14ba6aa7274d82853b8bc181e95427010001	\\xd5f1c9049e0e81f793294d9325a90b870f6a8200cd3570c220e9a32379eeb447ea20f7bde131a850ef8a8cfba084ef4e229570e13fc86f05d601d1808fb6a203	1667303989000000	1667908789000000	1730980789000000	1825588789000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
329	\\x3bc74614ed7fb5ee1baf55a03a7143fa003471ab14dc586cbd296bf7ec98b31faa00b438835c728c7f54754be75bb0fbf4b956ae1691980aa193744293fc30fb	1	0	\\x000000010000000000800003a3a0f59fcf2727cbde7c100acf559664385cc07afcbcf49ff2a180c37880b8450a7bbc7a4e3502b1df52e7794f58704ce8749b6faf1d6df446004b1f4c1e920e149c34bf10913752e8cfa2bc1eac113d1699a27cfa0154885d7e59d6f1a3b5fd2b79ad71b8a4a84ae1d9220947ca4378219a26c898ae1c79625631776dfb91cf010001	\\x8f384b4b5fe60e0f6491dd621b60ae8ffa2f4a4cb58811cbe8639b0e23425ed8d792817f6dd84176ffdf69e3c9405898b231c8eb663259fb9678f8d9290e9500	1661258989000000	1661863789000000	1724935789000000	1819543789000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
330	\\x3ce3dd08b0287d6c26bc153f8f4bc4cb6305f0b91675d48b1cc62be3fb50d4cc2261a50cce5b48c810e54c49a7ee8032b165c0552edb6d0e41ec68aa59c51d2e	1	0	\\x000000010000000000800003de34ec1871b54b04fbae3d9efd628ec0169c7780cae39a58bf7a0d353306e54bdfe4a4dcb12a0b66292431af62a4149422eef825bb0396c85e383b955900fddfd7acd86f3d6bdcff3656c7b46b20c804a3aabdf739072b15d9f5607749d17c0d625b521b2fe7cc8e6fdbb9ea48754ca6e534557441b0800f421b26811a5fbee3010001	\\xd45aa21408a27ce59ced5b153dc09b83ce9780a3ceabc12f791894701cb4500f369f585be911410b410402aec56973b2b92af25a52389d32a0af348d44b8bf02	1670930989000000	1671535789000000	1734607789000000	1829215789000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
331	\\x3cb7e1d9f7f5e6f482179670ef63ec0a2bcd78bf32bf87db214b707eb77fd76e1b8fb4323c77f3ea20e1dcc6264b7a911292f46e7868ed7ae05aea73390a31e9	1	0	\\x0000000100000000008000039d18049fd9ca665cb996b923ae6bc8ae7515b3419532e9e93271b37f4e9dca37a15bb6d31ef4a244af2ddc434639aad6d7f460e1699ebdb1b8a2764121caa59cc4bdfddcd77cd7e84cc4db32316ed6e087b7422136fd20decd3a23616f740089f2578bf581375eca831f886ca378f93bb4b7c72c1ae7356bf4937c5a10fac1f1010001	\\x89f39e1e2b95b163bd858cd65be5e2b3f6ac60ae1c41685bfea3754a67f6095790eb81d4c96401226f4ff7e0fae43ff89d7d4d6f84e73426b6a447405f789a05	1661863489000000	1662468289000000	1725540289000000	1820148289000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
332	\\x3cc35c971089b3577a45c0680b4f99faab0894993f87af1051611437a1119aedf716575c390020cc7af682cd895a5272c06d312c0a9922bf234e41e87505d4a5	1	0	\\x000000010000000000800003cb5e013b0435e88ac9bd8fcdc14f6b81b9d1dc2bfd02599dadc0030216db891dcf8e5062db00a92dee8c46504d60a336a915928d044466ef883014ff61bcc189a0b69b3242de4d22a388a9d8c3218968ae93fa624289a76d29d673738d00742c8d2ea0328a741658cb18fdfa55316f50629b4f50123d68f3deb4d20bdfc33d2f010001	\\xcc7bb1a8927a01703f5861353f00b53e0b5776218a84ffd33fd8e96a00e9084e7a3874692ac6a8f5984f0596c0b08920bae805f0f009f3925503273599008109	1681207489000000	1681812289000000	1744884289000000	1839492289000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
333	\\x3d63a91ce89892a205502806fb447a4d5d0a7ed57ed810c3fe2e32d9eda9e56015c9195e44e43015616ac69be4a745c3fdafef7ee03809f514f59118b3396b1a	1	0	\\x000000010000000000800003ca6ea90d0e7c9d3ab35bd376b21637e8558f9a5d83b3fdf07569f5b856868b56360a9b24385c466a96b548dc049c9e698b4549d67037924f29d354faaf2c2fe5b74de6015bbdc5d47e0e1d1b3898218382fd12a26906fcaf7f0dc0ba7c09557b009e295be04e629b7c058cb3d56645bd2cc1e11aa01d63810601da76b5ff71df010001	\\x726df66a9196b77daf59b007d91df1431139a38aa5d280886b3c87c52caaed199326753bcafe62e05636484fee8b2fafa60e46aedbf77c295b2ff9facbc8aa09	1680602989000000	1681207789000000	1744279789000000	1838887789000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
334	\\x3ed7963a75af26d7e0cafeda1bfc77395a6d58b0629133bab125dce9a854aff15d434865df7d0774e4a28fe5dab5e05458fe330119760b4157771f79a27b5257	1	0	\\x000000010000000000800003ed884a67f0b2c72cbca77fd3685c0b3e932a7bb033c8b48362996ae79e8d431b9dd5a19abef2d707aaa251d335e3ccda2b185b94dfa6b12be7604c1f7d22cbfeb0bf7abcbf9cdbb33930545663316fe1239a432f9d24ab1c2a09aeef94ecebdfb3fe09d24f6fc0c9ca17e28ef4df4c4c96394823dabd93cf86ee1fac1bb3b0cf010001	\\x1cc3d9088239d57335e70e504d12cab3c512a195a7aae27f4f6a60824f4a5e14f8e2785c8381446912709f0d3a2a36481251cade142cfef0dc6ae30d6b89180b	1661258989000000	1661863789000000	1724935789000000	1819543789000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
335	\\x3ffb390a5c9b2294d4b4a38653c72972d4495b0ccc3c7b04c3b082b8c6598565fa182730a79c13462c39550b1028c6a24da1508a2653451af57277c3dc107b06	1	0	\\x000000010000000000800003e2f8b893e40df9c1e4acefcee69f83fc829b02b24a666009652455a8bb10f3232749d98f02732a98072b56156e37df89cb9c9f1860770a6d96f3f3cbae9a72dfda77df5de0df69aaa6faf39a5eba315dde260ba6920c89d0d44cb06f52d507e2ca4d0a90418b7544fefbbe4f96715c1f7768a01571b87e9e13e398490c4c059b010001	\\xddd22a81383716080a3bec8039cf03e979bb2a5921980a9fa584fa0430a96fc89b68b9b1573ef0ea6f7ea3dcee87832295d0712e344cdfb23848b6eb39ced909	1687856989000000	1688461789000000	1751533789000000	1846141789000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
336	\\x40737f6db6ae06e48d65aee09007f2fbf0ef49b623f9c9fa3e85caf7835b790f529191fb2038cf05a6c7dad24abb75791440bcb0296c14cdd6f30aed142a89ac	1	0	\\x000000010000000000800003d52c79e143c5f17861e3b5d4f2234fa935feeb3bea14fab2a6ff299b8ea22677edb4986fb05436051fa62ed092e36065874a997d671238bfa2d25960f79f7f5565780d0e3a64e77d78d7ad88c320730942bbd9e3416ea0a7059b711eb16265879ffd162fcf96dfeb654912409f4dbc6050ac328b80dff2f9d43c10eebff9de55010001	\\xc1e6420c2258c6d6e0c82316e42f7bd74141050d06c518a9268fe2b449d852e1f5f3a1c94a6dcb2725c4d0daa6a24fc70f59bd63059c25388813f656490db50f	1681207489000000	1681812289000000	1744884289000000	1839492289000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
337	\\x41cb0bc268ef09f23d1c37911a4fe8f9c41fb5ff0dd339fdc962596fe7e7d8e933a12832c171333108c03cab14fcdda519d8344b31582e129c554a5f6a33ae04	1	0	\\x000000010000000000800003cc0ff69cf4e7dd7a9cc901c2a2089eed99fec18627024291d6dbe65626099809cffc0389c1f83fb8f1cbcfbd5b4475b63f0165794aa29ad54651328bd501a59fea27e1cee4a318b8a7cd3c37c93dd7ec7327761c81c8313e71ba2b7b70c9e782e707d29365f1fbf051e28e0e288721276054d5ac48c6aacf791a58d22bd5babb010001	\\x617fa47d19ff683644fdaf0679200ad1c20fe03edb7c5585a7f5ebf95d220dee20902cdbac71cfd7c4be9b925dcdd3cbeaaea69178f2367eafd5f305c208c909	1676371489000000	1676976289000000	1740048289000000	1834656289000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
338	\\x42ab9d36a3b20e9a0b6927fa5fe53ed46393807a59b61655fbd6962483226e50efdd1c69a7d5092e93e81ac89aaef238cbe51f891e47918bc849b15bcc8b816f	1	0	\\x000000010000000000800003aee0adf0c74979f8b3f8446a71ff19f1cbafe672beb17fe7b763574272f36b60ef0caf34d5d7d1a8b99eae142281342364e852ec32b470eb96031b2dc6adeaf9ec921546d39bd48d19b2bcfb58c2441101d9002b7ae037088ca58d719c37c5000e2a7a8345460cd6a0a2d58dc7787a9b89f221593209f69f0138f96851a42041010001	\\x7971fbb519421dadcab8cf34e9bb6e3b7894646e4b57e815ec78297d78a83633c11772ff52eff53046c6f7becb100b84dbe9e1954d0a3e20941b294055d83f06	1674557989000000	1675162789000000	1738234789000000	1832842789000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
339	\\x43d340f8f59517b0f8881a161024528224353f10dc5ed02546d06f74338a1372e8791f4cc25e52b06b54bc66f7f94d548000cfdbebe82c898ed626bc017936d7	1	0	\\x000000010000000000800003b7d0776b9430807bd9afe232af1440e9e863a35ea74ab8a253806a1cc3cb3ffae2766e311f44a1c348eaf0fd82b56f1516e6cf6c7482a79c2319210c68bc0327444a06953a46dbc99769b3433f04874f2c65534e82ce5c760c9bdbaf81dcf233dd5239077dba62b0060f5cabe2a2d0db3fff2caf9c8512a66e3cdd6076cc8831010001	\\xd6742f03d54a814edf658671fef898894a6327d046bf09692ae70bdb39f97aa0943da960e2d8c1ecf85b3496d68ad3a661a468b1a0e245c186d9a4f5dc670908	1666094989000000	1666699789000000	1729771789000000	1824379789000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
340	\\x47e711baadbb542251ddd253b9eb7f59c946f3844cd8530b503e3e42b80ad08c966297b075df4b648424ea6890a7d4f6163e38168cffd8089de6dd8c14047613	1	0	\\x000000010000000000800003978678cc0ac423f424d863cd2fd77b1ba7553c41a26d4d58e7c3377079916bd7c59af47bcb0ccc8742f6f6f029cdbecffddf64a6de90fe05cbfa6357170debce05df08e4ff889d973a713ae4a18dcde26f3f6450ee8710bb29b4a844a3403a355e7af78ff5bbea404d3b02cd631c3b91220ff1ac76fe9d56f503aecb4691a8bd010001	\\x090194a2e3fd2189341971eca7444fec95c0ae4a7d12214e26787ca2c38c8f5741bab9b720b3d191e3afa87933b9d3c443ea634d75eefec91fe45c46bd13a209	1664885989000000	1665490789000000	1728562789000000	1823170789000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
341	\\x475ba0527f394f9a2d78820cefef8665e8fea1b9c5752bbf5d2731d6dd2837330385d64aafd7373378475c3bea68971d9e687c51491d495595885840b9e0cb55	1	0	\\x000000010000000000800003f83c4b4dd83ffadf0bc2aa44d918806d4e0e7c2223ccebb64e8ba60084da458d383772ccc006325132d9bc1131894a9abd9c38010465d8bff8e53a4e5ee5badef3412d0c5d8c0e68a1f5bacab59b75543f0f12a056148d2598d801642c608c99283ebf9eff6c6e50a1851de28d78cf8426390595992c10e58746484d59cede09010001	\\xcde370e2e5f6cf7cfc0526b57846ba69f10e4f2a05098c93fa2c740a03f0b319e9a2ce85101a6a29ebaf07f4cd45f1f873de1cd0599071b650ed46a3d019df07	1687252489000000	1687857289000000	1750929289000000	1845537289000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
342	\\x48fb3032f27cbe09e473c0ec9acf4a534e912187d9706c874f8f075cf9279e6f5ceca6388192e768f860bba9683b89b7dd22867cbbb0b0bf2968dc20985ab976	1	0	\\x000000010000000000800003e2c5a71c4894e4330820eb66f41e00c0736d2cb6a5181790283bde16e4f0eb220c57f23a99ba7856a2660a19e7269f3310599e8a94665efdd38a353a12e9c207562de729ab6541aa6408b0cc8bd7b0efe03800bdcc12575006612e3e5f89dd8b586a15079a0f28340ceba659cf892432a4fee3330df3e0f4d355f3fb81bb32d9010001	\\x540070de25975d3a335ffc2b80ca3eeac2e36c5ed1a8a831802d503c251d5a2792c407679d4262bceb53dcfbe8cc71c06403b73f5b2e5d2855e78198cd3e4d06	1689670489000000	1690275289000000	1753347289000000	1847955289000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
343	\\x4f6760240da24152a330a82cdbfc330dd8c995e04402137c04e4f91cd829552ac1e0c2d38cb1ce1c31ac5154a5ffa3c6321d67788d9e4a9ee7d986a46705f3e2	1	0	\\x000000010000000000800003dba3612ff0c3d94b4a503d9a2f7cdcafd8f04d0ca88f8b4f5af13e728015b2e268d8261f646c86e2eaa8048fa1f978c9e0137164af99cf46ec41896b6ac0dc532d25b2469cef2fc7440643cdfab1dae43c4e3f0c390eba79aa44de83ebe4cc89f398dcf718157d730caa4178399d6ca9adeba0b007b0b0c6ec32d3c080409f51010001	\\xd74f8c27fda67bd4fc9d594ce3cc75fcd1969426ccb39d25f036c524dfa6639a6c10ce126e9fe6204e0efb949221af262190f8adb36df7b47a4718a6bf0fef0d	1675766989000000	1676371789000000	1739443789000000	1834051789000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
344	\\x5087d2721709543a72a5327122e7d94bb2da9a84dea735caa3289bc3b67ef0b3808f33208738610b22f6eb1ea389dcda8e253f0e22fe3914d70f038168e44f9f	1	0	\\x000000010000000000800003c578ee71879615e432465474814646df70b6b7578734e16917c052994eea0b0c70bca311683724bf68d7d9f1f368ef8a03146ba8137985768746507e6ba78036fbcf90bbfa78de391b45a0c83b927b24c5980ad8d097d0826a8651d2f873e16dba7b2ad40d1866a483395998c77f40564bf52df61a4752044b0ea3b9702f3a11010001	\\xb91f703f58e6888ebcf08c7539e5995a48dea194272640b898cfb4e232e44ed7ce4d6a3b20c1178312f0fd09252d8728dccfcda4ad19877cc82e5517e0d6f206	1662467989000000	1663072789000000	1726144789000000	1820752789000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
345	\\x528fc3734267ce3ecaca2984d5cc830126dc98e6e1fb7b26afa1ef742347b49a7acd3dbafd28a46b54662776bab2d58cb131631931729c00f2660d9851a52d7b	1	0	\\x000000010000000000800003b7d56eda74e42c085925530aa144d404d44446efe7ef6cb52c693779e09a3995ad943f419ea7dc1a9bd55fa9174cb5f9826a3833cd816419206a10bbe047dc2c863afdf0af668f5bda560253ffdfcbe3460fa3d1a938402641338ee9753e3eb7357d6c4fc971410657fe5074719a06e420f170b4178cd1348cd9e6c93a393cc3010001	\\xe67730affd5fda719efded47df3e968ab1512fe244c5f1aceef9a72c782323c53d4fc6171e7b3e1c25c143d9f8bcae175dbb23db9bfe3849778a33f61318ed0a	1686043489000000	1686648289000000	1749720289000000	1844328289000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
346	\\x520b0402ddfc082cb200327084e5404d08efcd98107391ae1ce9416a280c8aaee2cc295fdf99e39f6edbc8e839c205b3fc07296ad07ef76f908dbeef946ef18e	1	0	\\x000000010000000000800003b933f29ac4f53007880ad89349ff7da8017f89a6e2d20e481417fd37d8b612df48764fe1260ec9af1690749b8f65a0a180a1021413b4fe87605f8aaab4ae980f0e7c5300bf8549b6d92828a604a40c9e8c557a94034b4033ed3535530bcb3be2bb1ab2f67250c61e767acf90a5b0000758b1091a519f1b768796f93ed787706b010001	\\xf9284541147fa88f5a58abf90216ed838ac1c73d9b625bc88da3708c600fda189a23acf2d1bc87cca251bebb703dbe36eedd329ff5dba0faa387d58c60546402	1661863489000000	1662468289000000	1725540289000000	1820148289000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
347	\\x5b5772cc103dfcac073e9f2d1783db611896f3d7c6279d0d41a67d7a614d3ba95b4976d3d88d5190488faf00b7ef89d0021f097713e6a75cb5b9c185a65f449c	1	0	\\x000000010000000000800003a9d8bc834f3235740696fd622e25e76587deac01b8a89626830cbc5e771104965795c6be6607e65ef129a75574000a52403dbbbca1fbd9ff22bae6f2c0dfab3767c78745b456565a7e08e78bc872668ab63fa881627aa490371b945690f69fd124ca4e7a143c017b8a2f349a9f6159263a179303c502a4a8fda1949b5d9fa321010001	\\xca64e32278aaa220211666ebc5903aa534a0e0ce9746c6ae80c449556f5b4716dc3cc88e9628af4c75d1303dc09aefecf9fc6a6e97097941427c3635a04d6d0d	1689670489000000	1690275289000000	1753347289000000	1847955289000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
348	\\x61a3f3c0d0983a6f2d09a4cc166d7ef0dceaede391c4c09e8697b2190cf6c9583fa6bfeb94506c7bf048c47e8a73eedefe6e89879b9205f54c1890343ad78e4f	1	0	\\x000000010000000000800003b2518b3c5fbd5f3d6532a42ee1ec43d604e2d7e782298df0ae504a9ec102a59d9307ef7391acddf3be7aac691534ade4ea05beb75a3dc9725fc2776f55bd79709846eea2462d4621eea83ea9bc5c4d5b9d47ca6dbc06c36c42a01218367400ebb11340e7671d9d9e3e58569cdb4f673269988dac6aefc49c31e83d9be7ecf5a9010001	\\xa5c644cf3d508bc4d04066b6f07fe78dab1ff3bac28e4163bd3eae47b075da0adb18320fa6daa5885320f027eb007ee7df12726b19dfd3ebb30ffed5feb1b402	1671535489000000	1672140289000000	1735212289000000	1829820289000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
349	\\x64b39a0d8a96426554d9776b0e50c7d237b99757d24f89563cc2baf404204a0ec4c6bd2eb6efd5fb9565335224e00968d020e924f46afd61795a51d71605da68	1	0	\\x000000010000000000800003c2a0a7b61bc2f4eafcd99a9ed71424585de6b99d5961e2b3f56bc902c75b48b60e23c67cf1af7f0f52d0b6df9a1c2c8d051c5e21c9c5ace1f9ef7b1e8d46468add451bf3c65c0271426900e880dae089b4bd4ade8b15f6b56acf821a4beaae0a66019e764621149f5110350d274d1ae367815d6f3c0cea93dc2eb6846056fb1d010001	\\xbd123cc27bf8a8395f7692d632fba2c2d4422d9746aa8e84b04df9e2878b0400638561e2390a0a0edb49ccaa2230a503352f952588c6638e2e67e5633247500d	1666094989000000	1666699789000000	1729771789000000	1824379789000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
350	\\x650b0b6f386af6971c656cfc42585203abee9380beb55e5401f4e9b7ef381f6ce3f3bf3fda29e741bca4f3d3aa9df605ddabc3a0661c764e2c5202bcd6727ea4	1	0	\\x000000010000000000800003bbe884189bf315e645092991e0ecae3979d78c8a4297cb233f42caf451f9b8c2e265bb9cbb4b9e17dc47cb93f2b29cd04a47fdca9b9b8597e5502705488024b97b67cac21a34a94000858e7ce3376b0ffc0a32b0251232299586a92565f961967aafbcfc91d1482c90640df8326eda0fd730361c8c771ae666b53d313b1dd2d1010001	\\xc7b280375f537b46a64b6ffbd02b2e6756363a9b533ffa7c05bafb999fece9adcedc00a7c65bddb61450781fd3f6fdf90bf2a27d1974e237a5e560568d7ea00f	1663676989000000	1664281789000000	1727353789000000	1821961789000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
351	\\x65db16c8405396c489f5a83077539570958fd4d4ae8ccf952cb7a1daab91148c77b329f515d1fb0f4d413f70c67a3d9dbf49d06d90997aa038b38a8bfa40ba34	1	0	\\x000000010000000000800003ada7be330c98ed9167ee1698779ab1b770c8359d784239a7712df3674331e741c429ed1b0919ea520593f069a7e3add027ea6ffb0fbcdbd17a259cfece66625936f6192744454bdc2d15f1e8a926c840ec9b2d10d2ca83f776ee1c990c572967dbeb8c9fa200542ed7cbaf1e3c8deb2bc284d2f6104780d2610eb40814224c1d010001	\\xf63f19fd247f385d95cd45aafffdb6a1d6f248f2a248ddcaaa802ff2a4c57b8c70305417efd7bff9d1f50f92173f24fc24defed09d914a507d995e463776f306	1671535489000000	1672140289000000	1735212289000000	1829820289000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
352	\\x6747b25026bcd226e248e14e8087ed33bfebf48a6fcd5896e96c57aa6a771360a78662513e0aae06a480e9ff900c1a9bd18cf46699528dd3047c3ced0d253971	1	0	\\x000000010000000000800003c76204faf781a6988963777cb313b33e2a6066c0b3bab4a5c961476d5d176e4d4bde0c0672c9db48be163486a4ff55fcbde16dc4a1dcc8db3a0eecd4cefafd72061d231245a579cc2d5091422344bb304517d39b0f8a13dfc16859545db94f71dac7f42d6eafb87b2a112e17cf31bd601ee2563f6cb371c6dfa134e21f3c4ea5010001	\\x0224eb3e2b5e5b3f60bea58a7c00ca833e2a3b585e5130d2939a2e7b4acb3badab54399e6110eb228f08757e91cbd82bcc4800960d5edbeeb8f514454eae5c0b	1664885989000000	1665490789000000	1728562789000000	1823170789000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
353	\\x694f8885e57982cd7bca4bec2350e6839e90fe5e039d8c55553c5e8c40f59b90116d248414eb8dd696e9cb083f2cb17f96cdc0931f46785978ee34177e1f9e6e	1	0	\\x000000010000000000800003a54239630eb90c5c7a86f33c02a75e57534b98068de313a612e40b33105256ad22deea510dfa35080b338a995bac0817bd7b1de03bb0e2b7d37de5047077ac64c30b86a5ec9a321a57aa4910644c562add7007b5a3265f5cfcc4e342938fe6a1cf0adc6e225846e064267312a3b42ba7fc3786002f7530779bda0ec18844b3c1010001	\\xf90b7e0c30812fe2dfc911007b9250519ef9915e9aaf48b38d483d98f5daf810bb73cb79d5c3bed7bc490b834cec3fdb19b6228fadbcd0abd9fe41aa1f4bcf0b	1660654489000000	1661259289000000	1724331289000000	1818939289000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
354	\\x6ccfdefb28cd9718dfdd8126241b683eba7e51bf88994f78d5da37f78a801eef19eeb7e510c5ca4aaf70b5403db8ba7615118dbd5ee0ed72ae22d0cc0fdf7a59	1	0	\\x000000010000000000800003c2140c08617247639a5458e7db79d9b3cb5c402d3028b96ae5475e08444d84b70658dc54805dd4126407dceac19ae23490f4820264a077b72704e3df04b4cebeb38ca835f972a31e04eda92cf0528292ad0572a4d72e53fe2eb6e43b123e0a5cadb05034b3395dff4fd9cdc372b860c5e7aefcdb0631c4656b84e9163ea84acb010001	\\xb208343a361ddf8e931ca7cd1a402ab8ee97480ca324b14f3c05fd7220593d414f14b29ebd4e6f238ac7dd8d5a0520dc4b92e8b2d3f01ce26b91cb5b31ab1508	1671535489000000	1672140289000000	1735212289000000	1829820289000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
355	\\x6deb18b52679b8ff16280ea26819748b9452f67880dfced5f5335c68170b168efcd06f19249ecd544cac196e9f5a4db05742b46711582c6973981817507322e1	1	0	\\x000000010000000000800003bd42bdd43c989aa81b6de84953bee8a06de662972fe09807d1f0095b8412f92ce41163fdcfe390bb3fa1ec76fe89663f3419557875430190fdedef368b62bfa631cccf7965523b0c3a915309f8ff5de6ecb1ccb9cb95b8ba84408d8371dd1bc806ad56cb986aec0889ba899ab10390f0e8b5d294acd82a71226d855d21a8317f010001	\\x129bc0470f091739e8ad344b1cb3714c0090b72ca85dca4a4e5d20a1fbb4ee19ed8c979744338792aa4f74c7e5ea8c35d56c935e61e18e6aa551ea40032c1f01	1676371489000000	1676976289000000	1740048289000000	1834656289000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
356	\\x6ecf3f677212eecaf7886541c79236c4dd3e515dbf4524c287dbf29cf8bbb133cfd23d5fb9b38a4f114d27cde38d8f329df98cae81a9c14b8b440f8fbfdcb088	1	0	\\x000000010000000000800003c237fa8067d41b2b371eca57d975239c5ee5cd9daaf655ef301872ad1a65418ae4fafe846f7a4973e3b6ab8cd4f067944d5f1c2c2de0e5aed6f828db27469797a8c96f5668464efd3375db79f362f9605243ba9ae75d3ac43ca27e4162e34f0b4c8f9d6e55a8a07c4b7fa72695cfc0f6d9f6b130e8bec5107e1db4ff142a1917010001	\\xcd620fe364c9c07ff072a3fe37ba8344a8de30b0af6ac94514c5e9c977415943d24802cc0dfd739c977a81b6b53e20f15f4a9ae261f26975f034d799c9a1f805	1663676989000000	1664281789000000	1727353789000000	1821961789000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
357	\\x70afc7ac6cbbdaece25dd1d48d3ea60f07e490d9d73e4f008555480c5e3724275076d0878edb34a14bf2f181d9ab6f4ab5eed2556e26b949ce896f007fc91163	1	0	\\x000000010000000000800003d202e5dc6fe9c395407e3aea8b764b61db688d1fa51d0c38544b5fea8d0d179f8d46aa7b16ca2900442f8eeb7c2a5f42eb89b62ffba4dd4d734b9fc3cbcddfcfd8297a550e34f766bfdc383603432f7b09336d29325c71ead6c95cdf37770e45af3a08b40d1caa4dafd76568b919bd2cc2050aee344afbc54dc2f6effc97c71b010001	\\xccf14a62bd0d2ee6796270b43abcf583b7a8cb9730b9681af08bd65ba9587ed28c5b9c141c62547e25d13cf06f83c869e229494046c3877ea40b4ff77bc4010d	1674557989000000	1675162789000000	1738234789000000	1832842789000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
358	\\x755f74c7881b94e9f154c43bdde40936c37072e495d3d43efd25d26f7c045e0488557920915eac3881b02da8573a39a44bc7800ef610c493adc5516ba40b11fc	1	0	\\x000000010000000000800003aa66acdb6ae854d6dc0557eb65cfe53df9eb4d10e3f0e35943569803557fde7f4f7ac04f05c1634bff6d8693f9919fa6fd35760e8ffc16817ea1d35ba55e7f921a1d43c986ae9dccfd881c0d8948e94e82d57f7bfde1ebf83b7bc55688eb3209cbcca4c0508f8bedd6393cba125c8ba765b5ee99421b8c8fd1c9e7d5983be83d010001	\\xb7a942a168dacc6f63e5c84b9d31f884139fdff8d3cb0f23449fdf57819b61ab9b5f380234f840d68d7baf50ab22cd45d7e47401211f547b3a81c570af1e310c	1670326489000000	1670931289000000	1734003289000000	1828611289000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
359	\\x76d7638b5a29298001e05e9714abf345ac0f6bfa6171fea717d9f1b969fdd8f623890c01627230738c06ce83467e500a0bdb62fe16f5e477da2b307af3643085	1	0	\\x000000010000000000800003a9e94f802f4e1f08f3ed880f4e4afeab29932fd2443785c749a80e9cc4b7cb01006ada37f7360685521027c4d6479060ffd0dd8d6c661e79c0b4cfd84d0aaa65d1e17a10b590b78372a9d6dca434dabd11dc809cd87d94ee1a9fca1cc94d7d441b7195146874a32a10109c17d599997afcd9906321a652b304e7818d305d39bd010001	\\x1376e7df5a9506d7bb0fc642d77d2692020d8dd8a630a87041a90d5b9829c9fd150a4c42e7071960abfa2f77df27d4532c28116b45ec3c2170c361b29a38c007	1686043489000000	1686648289000000	1749720289000000	1844328289000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
360	\\x76f74541ba11194b5ffe4713b3df7aaece19f6fc8feb8b13668469001c13155cc31657c97857692454cd61416fa9b761cb972d869c059fb0f40b9d3186621ae3	1	0	\\x000000010000000000800003e13db25f19f610a802deaf2291352955c99da4c8e6824760785d6368e982aa93b66980219b4bf242bdd7137d769a02ff8b4f21786aa619756a05636782b1163e02bae970b1021f5e8da90e6ba5b05097a7858bd15c4ba37bb585e08c6f7324f0ef57ff4f665363fa37db178ef2b296f4286e6cd9629bc212634f75781e0617d1010001	\\x3fee9641de767caae59855a8a2648ca90c205432ec8cfb9809cef4f2c442f74c099fa646ddb56342916bc0d5a9738c9c85894ee02cc1d338326e876106bdda00	1681811989000000	1682416789000000	1745488789000000	1840096789000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
361	\\x7893cb7b628e126c0c2883bbd6a104aded6786a232811c150e3afc7886fc2799d3d6e5128e695e2117cdb1bfb80f1c3ec663f710e47eec22738aa02c6beb76e8	1	0	\\x000000010000000000800003c105a598af09faa41f82110f6d5f4ee7e4b0b07a3f1fe33cf73ed4ed1f598c7cfe5fc0d6bad9bd561bfe6e66ce046f040df102b19c8c5b3ab3abc73c6a1789478558bb708b7cdb9e46a40f2e4e5f9a72df17ff586658dcd0a628d96b085ce81b7fa62a34b6be2fe180ae3db6440742e9e0781e42627477243a01fb7e71c68ae9010001	\\xb57228e2738bcccf3246d4265eaad9a2bb54519116dd08caa0b6866411b59331ec61daaef2129b6d7348191b61f44b560380040ec1a475249e663e44b189d708	1662467989000000	1663072789000000	1726144789000000	1820752789000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
362	\\x79dbf4617e9ddeca5b5f70963c4b39b75b4558cab3251d823b4a2571d59b61f9c4b767e7369ebe5d132eadba731042c069330de856358343e8a8e7b5add3525f	1	0	\\x000000010000000000800003dd1bb981dc2358c5cfc909e57459b74fa5628a919b6432390073c14939299e7b0184291abe2f935ac997e5e4d39c762648058cad990b3904372246853dcdbb6e1838a665dae638cf7b9771ae23ed676d05f1883620479228947ab20006e986b6549d2f4704482868d1cb6ec283142d1b60f90ce27a50b1561e232d72d546140d010001	\\x72770917d82526aae90c50f16a29f68c75a744df1bb37306bb58c868b2f112b194753780dfab092af9007ccdd43ea566abf24ac03368b3d72e2def14a5b6fe0b	1672139989000000	1672744789000000	1735816789000000	1830424789000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
363	\\x80ebf7bdfa1743bb2f6777f4ad96ca6fccc1127fc35b7aa127afbfa6c7995237b171c2efe676281d3912b8cd52b51f52d4821de14c1ff73e7545776b76989186	1	0	\\x000000010000000000800003bd29f9868cc1b871a2d48ab0d7d8bd2732e1f3ed6f5f5fd2a8649ea12cc8d04045010d3567c9f369187553b003e690e1a7c8870b8736c5ce90810dd47f76086a7c5c90578ae8fa6f6dc633e497e4323d16f6b29568bb389e1a06ce5b1f7e168b01e0d6ec36ab47f5d28ecd9fad787c686ff92a10929fb86fe7ff1ca4e3da1c6b010001	\\x5947fc356997afd5e1a231c5ca44eda007b7616afbcaf6205adda61295d5f32ca97a3529d103a80f8f6004c222378e97dd20dd164c4ae2244fd9dcececeb8f0f	1681811989000000	1682416789000000	1745488789000000	1840096789000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
364	\\x828733b8170dd7e0225b08861e0c88a4312a5edb8c3e865a0be2d66e878072ffac5c01f7dff995648715319974902cd204b00356895da9999c06e7e1dd47fb4a	1	0	\\x000000010000000000800003c6bb38da7e1e34f2bda2c06ef23bb1d3d504f134d52c1f1a4af31042d16a5fd75bdde94846ef54cb6c2d78446a2fddfc84416db249a57414143b0e7e4b5ab505b5150f22808aea0270955b0c70c592a6affa79af7920410c05561f3abd0daab02334a138d4c4d6776cbfd4251c44c41736c3fdc26fcbe96186a0bf26b88e5917010001	\\x41b0c6963e56cb75da77644ad1771c8b8e91d67d47e6c5f1a5b3d4f7d8baf33bb6f6c46773c9212c6602e393ceeb0447d303d981fce9ee15667626a905e7690b	1666094989000000	1666699789000000	1729771789000000	1824379789000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
365	\\x849bca82d50c7168cdbba5a07e480e9e305884549c63fe394cc2a147d3925ebbd51a48883c4e89e07fa8c1f5baba3a443b41a8a51fc1243ed888f66130af19e7	1	0	\\x000000010000000000800003cb6cd87a840d15ce0473f380c7582adb3a3841cee01cbb001d7d58684c8b41582a08568627c1d626bfb94a632600191ef0a5e3f324ae3e18536eb6437e372436a38e725f5059dfafd9406a448e6b3949a3191dba35b84806a1ee94f97a5b9f3aab4e66a8701241cf312e26bc95ddedaf6f8b8e9d051ab37868223bf279fe18c9010001	\\xb824836058c237b87f78fb3709ea14dbb964d1ccdcc9d8dd9041fec17caff5c980a43415bd0d236a6ba42733eb49bc8f38fb9a781846e69cd4fe3f179e67950c	1676975989000000	1677580789000000	1740652789000000	1835260789000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
366	\\x8407b503db94257fc076da90260715eac00506db81374aa1aa42c268dff06def74fdbf65da7ef91d7211a26773f555f737370c0538c72d13f36117e33217b1b8	1	0	\\x000000010000000000800003ce3c13999bcaeb7d136ea036d47541bfedabe63285d4df7a885919a8dbaee1254a78a722c252e2ebd9275e8408be59876780c47c2b6dfc629f8892daa6c869dfb5ed12fb653f2eab7268fe62e46e58fa6232287271182784a202580320df72d0d1e46ee5d2ec18a1a1dce99e723108fd9942004117f503a4626f060e653b16e7010001	\\xf3530765d8eab3f5d99d5f13cafa83ccd0509b04e1008e76ba50f1e953e98b81fc3ac48a6d005c6516622cb8ae86dd564218b235ed5a171268f9a21da5147208	1671535489000000	1672140289000000	1735212289000000	1829820289000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
367	\\x86ef6ef52699ac74539ed5907173dc8ef2f259fee71c054ebfa561f4bb483ff8cb4c39f6696ca7ff0a68a58bab71043e28a71ae7324389459f5aea31f5e63f2a	1	0	\\x000000010000000000800003dcf3644e7d2b0ecb731cc6e723ed0874bf9378cef0fd61ecf410e36af7b4e18e0ea8e5dbd8187c5b2e8fecee461917d8ac642fec0cc5278a315578dc25f883eafc75bd95f37d65ccb5d2b580d5892e95b7b65edcde9fca2f5ff5251351aac3716728d1ef427facd3729ab740470fe27fd262db944e7b9088779d25ce551f327f010001	\\x206c2a5c90a2b7191cda6da6b2b3b723b77cf4436641615fcc82537e5e7690d35d7636092392737a66ca021bf4a049f58aa818d5fd3cebf853b81ffb975f2a0a	1682416489000000	1683021289000000	1746093289000000	1840701289000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
368	\\x863b645fe761c5927cfc254fba879467710960829e2a55eeb0a7733eebe413ba61b30cb1907195ed5caf1ed00ebe3fdc2cf6166d221a76d0d7507b5beb727443	1	0	\\x000000010000000000800003c353a034f7cf2459f4e3161e189230403a110041c0494d41fc5256573b3df6b365bdcb2179f6514ca642d46221c70ff19042c30efa73b36aa2d321e055fe1ec01de7ef32eaedf858dc2d8d1425da0478021d9415561cd5e0eedb18b578d790915a252bc24e22c7f442e01e7ff24ae9a3b90531fd21a7554bcd9a71274d6c17a1010001	\\x36b54628e7f39dda1df87510db41981d70089117acbf81a05c089c69cfcd72181adae15bb0904ad2639c518d8bf2c651219e44103234c1d84f8ebbd76a786a0c	1688461489000000	1689066289000000	1752138289000000	1846746289000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
369	\\x87a337bdc75e9cca00672209b572235d32b03d8d761ac5fa578c7296653474190877dcdae37ac8d03cc751706e1d371a7d3f4b1e75f024ad7f3343285743c970	1	0	\\x000000010000000000800003cc4c6d5764b20fd5d440551f43441a657b64c07aaddca797e01d820e862d9382a02d5e7add481ecb92ef920cbc247fe76af20da06868b065c7086fea9afa84b3b77eb767c85c17b9aa13be00618f85921206c2a1f0e2a36b1b13d382bd27f27875309b5f7077063ab647909e80735962a422e250bb3d3e5bfd4fec1ed44addbf010001	\\x2654f2b7c0d8721d4fa1f9d44431ccfad99c9a35bee44ee7e27658c4f0f2b262eeffb6b663c9372c219b90f32a971edd274b01d254f1d48d70d3db9c87e62800	1683625489000000	1684230289000000	1747302289000000	1841910289000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
370	\\x8877fa64267f7631c79a01b3e770253f432a097c18810dbf5455cd768aad0bdb969265209ff954ed57904b6cf676750ad620db9b18d48363174ca74f8601166f	1	0	\\x000000010000000000800003d259b730f76e8e64a2185c0f354a5211317c5f11f3770f7f047b03934e5b47b637a8a8bc08653a447a582400f3f480b86a5766ced6de205c8b881c566aca195870dd8ec503cec3f929c9287af475aa0092eb8cd50f0f12d93b00b62c579a99370f103bd898d676e207242e7bddb1a03b50f7d259fa87384e09ec9e61afbd1041010001	\\xdaab740c1fa1ca76fe15d762a7bfc7ed3c6b5eaf594d8d0e8db1e3b5b9c3ad5d7839a1d477cba72a5f898393c7b62e9d2b0e985e58939666c98e92b699cd610e	1687856989000000	1688461789000000	1751533789000000	1846141789000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
371	\\x8cd77288a23ea5210da4f89f16d5fa18e25849e336ac13f5c49067b30a66374471a84e5f0af1c9783f00a5776d336fc7aa72775259e888322f49fd99d75a001a	1	0	\\x000000010000000000800003ce797deb6dc041104122b2bb8ee81d68e5610a1945745da9181158c652ca4eb77cb01f4da4de19e1f2f9870e4694e33cfe9e0ab48d76c0d1aaf878cb3932f0b317de797e368789719507b0818dd2e7c5f5331555f0d19428751560e043e401761414755b358249d3e6c4c98070071530783b7c010011b16bb2eb4d3ac3c1e559010001	\\x1c858a203096de4b2de5e7bcf3d5f882e6b9dcd3b0701a4a7b0ed4449d4c605a6b7c0e94c6b58ebb66a582ba9d72608c8a982f35a038f4642e917dd18b01cf07	1661863489000000	1662468289000000	1725540289000000	1820148289000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
372	\\x8c4bb810e0a251a0070eb6f762c70ab2450245bfeeeda49523b83f88d8ba07141edb3a8ba338e0fbb4e34fca9b125cff19678db758a1ddcf22d78001dfc736a5	1	0	\\x000000010000000000800003c14ae889d62931dc8dd6fc4b6e55173e758ed922f90daf62dbfb8aeea2f77203b8a7f35ce5ac9520db9eb09fedce5142395fd102dc6757f7d08c35bbca40a535f861c552a4107f482fde6141cf224bb5e68f6207dd0017e25efb93cc7380860983d3fb78ad3b012c27b53d8a742f1f5e9cbd9e33a88b749d9ded3dbc03a51a95010001	\\xb655f55789fc4597e1a9342a709f44d145da44c723bb50ffa11a2ccd1382ea54df5a7c20e15a7e7c5a99f1d0e937a156813ef9781b68eb1a4499e975f0fc110c	1661863489000000	1662468289000000	1725540289000000	1820148289000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
373	\\x8c6f43e328c1905644ad088322f8e00aa6712db4f44d152b541cde0b1b36b19cc96f5dd6c6dd28a69c9c8ead674e140f18dae5a45b77a159d96cc78fcab993ed	1	0	\\x000000010000000000800003a154760c8de37558883aa2d617a5a7a1ff41ae14395ac0376ac2f594f269bbd5b10eeaf66ddc772bb309ebdc037b9740137ce54cd337d8cd26a72bfd31f867746ecbf9393f5d5733cae91c07eb895704c1be13748d387df88d96d7bd5871a928425c9059125e7a542034400c4ebc9e64c80b806e2011094b82aa58113b2f2443010001	\\xcdf0e12b47747b64e0006cf898866514f2f9a7e60b2b5398868ec4d65e01114816dcbb2ac107a72eea8ab01e54531dba2992aed4a0096a3a8be3bfef011b5f04	1679393989000000	1679998789000000	1743070789000000	1837678789000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
374	\\x8cf7ad417bd3fd62ff5134003517194ff046933f31d0414aeda53d0f57644329731e88c18a7b14b87b4fcf3cdd80878505d45ebae408a1dfb79bb4a85cd1a9f9	1	0	\\x000000010000000000800003c17bef01b923e94d15971d0a22717cc2ecdca7f4db6d6d9a1afa0221918d3ef59583d4c01beada8793ba63aed111921c62ccada116ca8c93126a2771d1d40e3960913869f1a6e8d8eb83455951569136f4fe36d9d617b09d227690b07d60599ac0e4f567eda2fb7bd987bb4367f4d8a361b7ebb43a6a85690732a74fd5e2b015010001	\\x141a0bda938c267775fa6a3b54387c4d0748a411d9ca1cee23f11123602ad9fcb85cab97ccecb105c8ca7756308a87cc76f3ac0f73fd131ab89d9e48ee0bab06	1678789489000000	1679394289000000	1742466289000000	1837074289000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
375	\\x8f03a54bdd6c316a7b91592ef398937f4dabc08c55c95b76e09a2e6a3cf46a0571e5715a9dddfbf5c553aad5af2e6171081159f16baef867f67457617e9ab8e9	1	0	\\x000000010000000000800003cdc01ce2fbf04985f18a619b91e24f9526e1a2d4307223812f8becb1c70173c099a8a575a3e5899d627a6213c45491d9ea31f0d500a1f3149bf7e3086194175b81e6ea794355df3e1a4a8303ab3ae0ef537c211d392bb74d63e7eecbade61e0ac179cff4ed09f81a6b59163c402b06fbdc07df4617ab2a68a5672acc6096f0bd010001	\\x24abbc70972ba81da0ce4669e262c7df9e2855e4534e4fcb19f1e6cdc0d0cd06325557146934dcec6b7b989ffdc5fb025e709f1b4c7aeec11c0663521dd94a07	1678184989000000	1678789789000000	1741861789000000	1836469789000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
376	\\x94073432cc2c791370a7a84535be9c7210fe0c8da8db7aec1e704020ce2e2b7d57019b4f9424613be1c6effd9969f2798e2a15055e96fd6ba285477e73387218	1	0	\\x000000010000000000800003be22b100987263c387c6d7b5295ea96a4f2dc1dcf8f8cad0df84f4af385c93caecbf9b317c59b43e58c44ceb126451dab4c99038c360c04b56a8a199411929911ec420f5175cc36a9d478e61c976303436b93b243cf38cbc081488c69e92475b897eb589fe93125bc45fb109734041d4541cdbff6cdd663f28e36247cf759ec7010001	\\x31e148e5457692207744bee8eb49a12fd98c9b128ed41d3ca096565b93845468e691116c09f5a57d708c65e2069ab0e695ad139b66e181221e51f12a1dec2e04	1677580489000000	1678185289000000	1741257289000000	1835865289000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
377	\\x9a433b76ccbfce64a693680029c737ad740dd2f78bc84f954d9a26793512775a22c7ff3b0252036b1e13d5e7d83b4013d869b3a5b5c3fb01391b0f100c467b1f	1	0	\\x000000010000000000800003e28b2dac0eb4d9cc33f8bdad662c72b99bc5f912b5b5e921ae925ccbf1e9133e21b4a9ddac639bf0c892fe91b37e58a5096da8b8f8c9d2386270e35f70ad684a7f4ff9be253df1347a168c96cdb9368f3aabf0a49e6779273e3826268348e58c5600c9f067bb5a66bea8fb33a40ef5c4876895ae62774b377d35d4b545abc381010001	\\x919d5f634a6a076f79aa537c4a8ac051a1b0fa0263b183d84d86355a48b23c7736358d2be6a5264e21c969d43140d99dff160b369e92de25ac102439cb9cb708	1668512989000000	1669117789000000	1732189789000000	1826797789000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
378	\\x9e8b6da794bca65fa9c1bb95a22960e2835f97a40609e80340f035168f46dedfafd067f4c93f80b3244d9f344f251ddeab954fc8c801a1eaea2506cbb0277b8d	1	0	\\x000000010000000000800003bf3eec96e5502ffa55218e9985a480b8e3a2d959fea45ead02ccaa77c15cce0d9f86478c2d74900a6b7b2bec81d3f133a48510ed5f92bdd98f290725714fc30b85790e46ba4f1d122d8db6f6bdc9a923f9e925a50eff59d54568beb81ca8c9d031a77d197e5752ad9d45229dace78a9db452da12ad6f1dce9a8b404cb37489c7010001	\\x65c40c67d7cc3aac21447751fe96267587680ecb468e5ad2846c7b7d6c62045513f2a76881c22450e192739e310075690f263d1f5f5069c9eb6869254a60890b	1669721989000000	1670326789000000	1733398789000000	1828006789000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
379	\\x9fb3a6697e804ac6499be473d9ccd2de22377442781b1710c6fe995b7f9011d2a1c62ce5d428f08b6035865799d0f52a76254b392283ada738f870f3f30e6aaf	1	0	\\x000000010000000000800003a1c7ed96a40457593289dceea44990087e6f78ba2792a82d271a309acce7182d8667d6b93fcad00ce010b4154935a11bc7afdc820fa638d11f6f11d607789612ba8c681bbe1c1ece4bea6d24f3c6c2fb22fd57e685e6b37bdca1641167af528373ff28d8d81ad4116287e70340aa764b0ea9ec929f807442de6efdeb979ee87f010001	\\x80f26441f26a24c4e6d3c123c17915c9f094f2683e17e6688fe55d7468ddcb17c41015546a31544d03e320e646a826d8fc6117e6c0c76a5ec31d797abe42af0e	1670326489000000	1670931289000000	1734003289000000	1828611289000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
380	\\xa2f7c0d0d24e5253ac6c440f29bf3f0c4ddccf30ff71fcba7ed8e0272ef3ed9c0aff04f1a0cf0a252dd9d9533ee5f4ac642ba3d5262003c945c4890160a913e1	1	0	\\x000000010000000000800003da60dea85859c0580ca76db874957411a20d9b97577617d6e1c5a0d575413a597050b3bbd7121a0d70f1ebef8056f54049c3f3236d8037f221ea5743031d52317d222cdc09ed97f0bc1378a95f62829a04e04c1d9651ad82f0b8c1f4169802fcbbe5934089cb7b5b499b2259c8141f36d419c2d45a161bce3c1209d3710cfd29010001	\\x518f421862a389c4e8fece1c70a51ba6f9cef28e2ce58595817f99db98afb8ed20a98ae63901aa20f4790ed5dc667ce6dfa8240e3859e6a0d085b1981c3ad109	1690879489000000	1691484289000000	1754556289000000	1849164289000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
381	\\xa35b794ba20ecf9f6773de13fee390315c2c98106a8959c3405bf1343cf9b3716bb501012ed726945f251eb3cfdffd1ed85d85b10c6e102661ba1b41488f5a45	1	0	\\x000000010000000000800003bcbbe7090ac2d795139c80518d92442ad30f205d95f27515e79c5147a62417711a71a20fc84fe10eac3a42fc525c9a286eb9ad257e732855bce2337d0f7ce8072ed368f174fd55d41a636c5ffcf8e3766b7256ca415a02798603547ffa416e55ab52b0071313a23255a2bdaa727a8f1d9f62e425fde82f21783b7073cf748e9d010001	\\x566f65e3337beddb2a11cb186178c171540ea1dcc1bbe169b3c7f18f119ff41a87dbaf6a4515f9622002ea5f4c36d5974790ed66c7f2ea4347a2975158210904	1676975989000000	1677580789000000	1740652789000000	1835260789000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
382	\\xa433d4b4152d52978383aded3139ca97b13b914a25a25beb210b4905a26d490d918a19a180150373e6db4f31b16f8f9e2b8d46bbabbba877448da9ba37786ac5	1	0	\\x000000010000000000800003e16d7601bdba5d3c0c70b293b5d863e66fe94ea5875544d7f3bf2d43e9974919cfbe494fba7e6b572033ee98dd907bbb37580c7bb5528b938ab93e8c8abb9dea9de7ee8894b90ed2ce28db58a8f1298a0218871a5f1fa5354a446ec4359dae696d4aac5b9479e304a76dd815a57433172b44b5992af30e23931f92374f25a5b5010001	\\xf0da5347ec85bf7be585845afb2cb5df35c727b735ffc4673915787a9f4dbc19a3e6d92867358074215045103792eb8cdf2e9db3f15f5abb9c2e02f1f41df204	1676371489000000	1676976289000000	1740048289000000	1834656289000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
383	\\xa7ef97c237be3f8f4fdac7c8a69f44c91cb9c3ee3a039c158427fae08a6fa633ac383856e47276193964bc0617d98c9d7b2cf728ad25818ea6a441f76f68fb12	1	0	\\x000000010000000000800003d107824847f416af5ad6aabf847e7e415b4c177fdb7a7273bf160366f9aeed283e2f30f87f2909c3842778c45db1b6181406d5472840706d25df5f2d71d8a900adb44055c71f5797b3f05c775b469a6f6396c9b952ec74cd0b6d44554d205120bf08cdd112d7b5ac9c6de624195c7ce360f475214b184206466ae9baa71894f3010001	\\xa58d9e80c80cc4b026c6ff310a1c44bd665c9bd208c1acaea5f7c658df51421bebf7173ff28766ae543ad44b9e43c120305e798768f9c97a58a900189af2d503	1676975989000000	1677580789000000	1740652789000000	1835260789000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
384	\\xaa077bb176aab233452ad7c37ab3242a25ba006884819c1b916f27aa2d087db7f2cc37fccb63934020cd69e73ae8638d414642d9a43cd967b2fc045d4c73c335	1	0	\\x000000010000000000800003adc4985ee0f7d5aa77470686b021590fbc8f8b3854522213376830c57011cb6d0b765cc0062ffded82d17a4f2608b49b926a1894b45312b77888ec5b1a83985849c7e022cf7b92af61f8e61075d115992392171575b981b66248d9d496089c60552d8eb1239fa70bf2fe06e94c55ab574bd5ef81fa4421382ae20a290035a39f010001	\\x6fee54548a96c2ead4fd8f787e46d9b8e9bda4142922c7181a909905d4f2b2c4fd810a1c7079af5670ed5ec4216a5ca0ab535f2abec4cdb0b1b9383ee13a0e0b	1660654489000000	1661259289000000	1724331289000000	1818939289000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
385	\\xab0bbdcd6b331b906800a9f931466bf021b614790e96923e9afbee6f84b7bc5d5cf8096486a313fc45558f66f69e9072b2cde89bb1a89010a9ecac8da0c78df9	1	0	\\x000000010000000000800003aeb56217ddbbe252b4437735aad7b30f7432cefcbf51a3c695e73cc3f1a55ca17bdd3e5a9085c6fbbf15f090967b7065c174327359f7f055b01707dc0967f6e0cf49f70d25cf05b974e3dbef2979ec6f3a64000ead1bb954216bc4af3ddc6aefdcf81e3acc0a316667aa4298dfc9d56a15c0076bda07473c28a6445924eb540d010001	\\x789e1d8c0789066df17f99ffdb5f1b4a13bd62e86663efff1f3ac9778748b53a5fdd5f229672e6624f9123ae784eb23cf9be2051a1238bf0b37b8b77127cde07	1667908489000000	1668513289000000	1731585289000000	1826193289000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
386	\\xad83422ee4f1c565998b793596a7c47dd333cbf424621933e44f9540cfd89cbdacbc8173f288e625905353740377df698f4e018e4b038f21e7d3172a01eb13d7	1	0	\\x000000010000000000800003cc45d62448dedbeb9493dc3c287defe3c9990d038d62f9365f86daef6b31faaf1a4050a2e250afb51e7db4c1a6ef864c30cc6be968f59f181c83ad28acfcded3e608ece0aa86dd468a507d0a4501e9a2ccedfdc772aebf42489670a7e454ff14df7138581a5350917721c29cec0b8cbb96458b55d468cd6f188c5b1ba160df35010001	\\x05911163b0bb64eed6458423e68f32d92032f115eaf29daa39029537060aba62769c118aac4bc77dddd3d0c24eeccd47b2e3d4c7861cd79294d60809ea68d30a	1679998489000000	1680603289000000	1743675289000000	1838283289000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
387	\\xb2878327c70b74525fd1f0114b1d7e3addb7251371e51dae43e212004ff79ae6fdbc0095f60006e4ca3b32ac0996ee9d0926a8fe6204eea96ebc1a5dcaf0bc63	1	0	\\x000000010000000000800003b7b3fc3d0e4ad9f458100ca2c7ecbb7747d7f203faac13af46de461675cea3167467115bdb5c6eb8488cb57d2ca59b576871511213e6138ab75171b44dedfccae00d151b545f9bb9a6f7c5038c7fd6a8c6a0e48036cb47499f6250094d3d6a48cd322dd49675d7204fae175a9dcd61f3f9292d24a647a016e9a336577c454553010001	\\x8818051e54a99517dd4ee6a038fc930e93c4f1c88f498085a5df330c7dc9635abfde6e3ac2607fd4deb2325c013ecaad61c885040e41bfbe0c4573bf14c66308	1686647989000000	1687252789000000	1750324789000000	1844932789000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
388	\\xb2f72833712af812e7e27f1409995cc9addeb9c9508d45770858d442b9ae815bb5beb17b23c4e452c1fe78daadca7e03efdd0efd3da139b6d18656f2fdbab9cf	1	0	\\x000000010000000000800003cf98fbbed4d9209f8e40fd629bb8bb16e20b1494f1056bb252d5b71a86d7f33ac5933a6585efe88a3023650fff0c4368332efcc1e0a3717eaa4280d2ca4e10461376003222214a3bb1bac8fa6431daee07da5ce52e3dd2967681ec9a46ca1ee333d4ab99743ba25acea00b0cac01ef3c6656ea855b99df23a8b9ba0146aa8681010001	\\xc9f4258b0db0c9176ec3e5ea0c01695b111e062f40de13067d16bb854166dee5aded7422400694a1338c4a09b78dca135042721b8a5eebde20e2e2d4ba87190b	1669117489000000	1669722289000000	1732794289000000	1827402289000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
389	\\xb4cfc9c2e6773080d6f781e7238d55a1f5911282f9774b2385f13c96316236856e8cd1d63b95dcc0fcff2fa706d8e43fccd08a21e295a972fd807ce34cb8cc99	1	0	\\x000000010000000000800003c3ea652e4a78e65355cf16411ed995b386b23e5150f7d8f17fdc7ba84586fd1be87377083581e1710610bee44c412eabe3bb78d379cf8a91169150f87daa613aa0e67ede3deb9da60166de7a09d1bd7987c19945fa19bc0b2eb045b2dfa47fc3db29fa10653f39f92204a81f5ea9880e3a9781a90dee87bdd24919db64940bcb010001	\\x28e4bee33f4d0955a9d1635babdb2fd6fa9c74d6ee971e81124a37b845c2e61dc66d6c5993eb4ba97c47f9c3722808f21f4653d8b1b77e55f7fa97a420c9740f	1688461489000000	1689066289000000	1752138289000000	1846746289000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
390	\\xb79728d94b215522ad5868972c36193f3125c7bc6335c7697cce38c5fcf26c86e2bd672d020cdacbef6def89e1f29f0d04ebcf708afeec8f94025ce5ca68f708	1	0	\\x000000010000000000800003b2bf86d631b6e166da6230281fc1515cc5bbceea6df50ab845aba09bca6c21d57a4e70d9f0e73fa00b5ffb32e4c546778a7b065ed1a2519f85cb4781456124d51a9dbcc56d57ef0a30124f6dc2c291cae6ee3d74755dfc58f6d07ae38f79ef88b0821bce42fc2cf926397a0cb0c213464bb2033ba9d278936644f8ee63f307a7010001	\\x5a716f7642828a39efc18a3884d9857f46bf5924e7f3ecc2bf5a1a22223a56a3402c14a986f703da9ea322185efcbf8c126449b46bce0361036807d38304fa0d	1685438989000000	1686043789000000	1749115789000000	1843723789000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
391	\\xb87bf4ba9548976de41d728be2d852f365bcd7fb610b7987070226b11faf2f2f8a24ad7680a5ac809c40780332e2f837e65900fc219dd004efd7be54c43f7583	1	0	\\x000000010000000000800003b1ae548eb3cd9d95076289bc53e7a7d51981679138cea507ae2a0d6808afd2cc1579ec5d4126264805dbd7a096a62014228bcca05967731caab2cd37e3d9cb13c67635659665300bde2765a16ef2b38cb32c1b55ad572f90be44aca895ce51635e2e8811dcbd98399e4938c93900ee61f60a2e81bb3cc09946ac648825fdc143010001	\\x65c0fe48eb3be9adce4adb5b4b563d7f038a18f16ec8a7cc16ea0cf3018797501b5a690e9bbd26ad152f207c8fbb9b5bc7fcb53cc2f91e1a2f05ab456143e206	1669721989000000	1670326789000000	1733398789000000	1828006789000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
392	\\xb8af15fdd2de88e3bf48df04ebb0511dc8547aca7e59963ba2c0949551d398bad60b4ba7c3e9a783cd4bb631b1e7fb3b8d23317418c05ffaec3336166b4e889c	1	0	\\x000000010000000000800003aa35f4c7059304967da7a7c5c6ce44e2894926afe89303b90cb84f0bbc5e8adab5201741521f42abeab9f29b107671fb4cb841213daabc33a72ebdab11f557ead0ef54f35006a93ada052d182c249b03d013528f45373a84a58887a675c104d53ae7030eb725660342ce940e5df9760b4dd6df5eac453229b9ebc26c91ae08fd010001	\\xf1e18a1bfe96cccc0408e86aa0c3b5cf08cc230869ce4ff4848742012fb0fd2ef400e334ec79dc6e85cb16a7370a98c027934790fafaaa5021af7912816ed401	1689065989000000	1689670789000000	1752742789000000	1847350789000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
393	\\xbdf7a5c74e45af8aebd2c3782337d9eaac70f5fbdc3f29106183cd00135651ff1a61ce2bcbb9e0a12c529edbad2861a9bcf5201847babc622ab8b0714ea863eb	1	0	\\x000000010000000000800003e22559ccfa1f3fdc98e0d08483cc5d4fbe6c5c764b0efe70f4097d985dae05fcca5c34c34f965b20c313b3cc0e899269c4e9e6274068d971669699ed1c537cd4f4f5ddfd1e2a5d300abe33e2c399566c2ef62fdabb2a52d5b4e816793bd48ddf0cdd930a445851ec42b7cc498366c9938a2706e08e49aa2aa66372cb9e8ad4af010001	\\x04e9adb3bf820e896e3c734cae17b758bb22d48cac973c9c09de22354a65c055e921b1f16d77c6dc29d79a69a4485d410d4c558bacc2a13885588e1d0362010a	1662467989000000	1663072789000000	1726144789000000	1820752789000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
394	\\xbe73f5a2a5d8abd5de773969b556048f251bb122ad1806ea4eb570d8b5d9af4ae5e0a68b0fa06e3d3a820306a5aeaca31088813f03d92635827b52a5655d34a1	1	0	\\x000000010000000000800003e2c10f704ccff556602e10e4ee3405037e04c9173802a6245f16d3142c1beb234447d809489c6a4aef2ce0452ed688d731a852b16f9474516bef83d82e0e839c29cc13a65a438ca2a5e7473b63f3fc1dd84d59fc1110e45746780083b45b94cf4de431a2b6bf7bd00f88633d010f090a3e3225fc6304cfd2a411d6759ee65847010001	\\x8e29a088ab9858a5392d9ca0ce531629591d15ec5b937c21f659785e2c8cc45065b67185bd8a7aef539a739eed569e61af2c9fc8509f4435719319b8593ba00d	1669721989000000	1670326789000000	1733398789000000	1828006789000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
395	\\xc17734577a48c1eb0233412d56c48c4a50067d67a08b46c5318034d11004d9c39859ff783f778445fc960098edd0eddf5a7729e3923f3e10b1c7d626e1c66a6a	1	0	\\x000000010000000000800003ba21dd057d43414f294592a3fe3a875bd4c69839dad00f1c39f24d06f833b795931334176fdafe92f1cc669fa41df331a096f2c7acbeb05afea4b2768e4d5c95fa36fc2194fa26f8f64a0dbd88d2de8ea5765b9b5da12b3e2e87ebccb3481a346eec6af2b450268fff62b50acecdc159edd419e4a7174f1efee1964e8e443393010001	\\x93970c0936e1bbdec1eaeadf8f5cfe956e6cbcb01b3ff7cc106fa27f19f727d8589758f1548e4b769ad3249d2423978af5685485ef35996baa879dc089324109	1681811989000000	1682416789000000	1745488789000000	1840096789000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
396	\\xc21bb8cc58e1fd52beb685de9cf255c6aac6a5c723ec9ea1b3a264777883d0cb2c049134cdf4829ad8d5d7ed7bb298f8a1c143beabd81a6714714dd964f1a8f5	1	0	\\x000000010000000000800003c098678088e15b022b503af10e838c577c868f3b7b7a373d9910170bf52fba60fee6c4954f2e603cf7f05d4863d759672f9a71cf2f357a5667bee5d607f370115b37b989622bcd2e5199afdd50560e99c251ea905b3a04843a5bc86b59651fef71b67bd86adb9738c63419c39818179181c747bd413d2d84a4ac9a626dc9066f010001	\\xcf0ccac8460835b179a2e729be9d8b587480b86969effb3d380a36e5534d0c1dbb92ba9bc25573c86499fdee9ae277102234f96be3031d6b5f2c5eb39f1ad302	1681207489000000	1681812289000000	1744884289000000	1839492289000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
397	\\xc98ff2a87e255862152a79c293dcd2fbd0f38fd7f87af2dd9a69b070d3d19611e549428250b53112307db65bda920556e5d76f228a6d6ead9786ee94c9eb1c35	1	0	\\x000000010000000000800003d0ac027078ce45f342c28c7aa1b473077c6e4945438c7cba42abe383d208c2d59cb2cd5cc084b9788832483a3a88a4eb292915fed2be7516ecaab6379470165a718336d67e61b91b4c79f54e79d97eec52a747635f7900d11e77a31c2dfee673375e34478ebdbafb8776011517dacb80857a24d00b7b0e3e47a7b3db5882260d010001	\\x174aba72d84ded1e1e4dbd0808669ed699e7107998d3092f8ba6e514d2b37cbda3c314d3517fcca0f911be8ec33ee6843657d54aecb061e5514262f0c91c5606	1675162489000000	1675767289000000	1738839289000000	1833447289000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
398	\\xc923f14535e4022c8c1eb48f8b79c05edc14631defcd2ff26d4d038476488ca9f6ab66c6f0e14166d7bb84d49b0b0e0b4d3bde37bb4d736678bb11d5e8f4b25c	1	0	\\x000000010000000000800003b83f2e1ec2fd0163b1a16eaa408380b8cd21d4c9359202878adab817b26978e72a5e6f7fa344388d9dad87b3dc46f0dd2c317c89ed6fc54b43ecff8b8429ec0855f366af0d24ccbd65a2e5af9c6ca422939e5fbeaabc4631cc695cde6700f882c40ab257188145072496e4d51f76bfb88f9f372e6a2b763191a2a8922fe769e9010001	\\x5adb72c5e5a975f0768520f7ad4d73df48bc1098eddc01ef180b4751641192ab9c4357d01d0956173ab1c1e3952dca66df6d533c690fb2ab1257b06f9be3f70d	1678184989000000	1678789789000000	1741861789000000	1836469789000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
399	\\xcaabeb630653d248c5f68550221eefdf5ada11b9626b31a230501cea3abeecac2b61eb2c30ff74ff819fb008555d6c23a3490efe01671afbbf7e911d5e1917b3	1	0	\\x000000010000000000800003c8719d37d3416365a718854a5c40b8315d22d64de6adad0eae147abcb6808304bd6bca0eef181f3c11b5489aac98bab2b278f720064bc97c0517c3dacd9b96fd209784ec22dc3e1fdbc43691d8c71d0fe2742015ae3b09afe10094267eff25fe0dc150c144ab49fed6efcc9de03428e5371c44251dbbb8d1a54d501e2a4f5935010001	\\xc39b979175b9b8bcde4656e2fd0a3477a47c7c844a971215b9caea513e34eeb0e8445427ebc4cd3ecd852523339aa1ddf47e5c949dd1712c42c040188832d90f	1689670489000000	1690275289000000	1753347289000000	1847955289000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
400	\\xccbf38aa6eff3e3e2cbe7e59f96e0f143c1bef426639a2a2b87209f4ff280645b06ad55cf0b4eff407a0edbb972ba17d60325c750c453f65b61e2117fc6b3f3e	1	0	\\x000000010000000000800003b38ed97a9d4fdb071baa6feccc81933f924d992dd91f843221ddbbd99b515f0f32e16970b13069b9568169dd3094e25c6c64c8c982d94644e6e2144f917d6559886b5f281879ec3efacc759438d0d41da381b05d33a5f6e2eb1474354cd90965b3202d4fea73f35667a7f7dd9bb638f2a2396ce1fdb5dfdfb492072c1c15b68b010001	\\x0628ffe46c712d24931bd82a71063a4e67cb6b094c4640b11c72f510cf2af1662c9f1a5efce2fb31ca6ff0a7db7e4492b7c067e42646abb38a10523581a23b00	1679998489000000	1680603289000000	1743675289000000	1838283289000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
401	\\xced750421ca6b72a1f0226ce06b4d816db19b369897b4a53a0a599e47ffe79a1ce8bf0f445cb36171275e289341ad4a010968c5b9021d1019810180a035babc4	1	0	\\x000000010000000000800003d71d0bc0fe7a98cedce5bea9fef031fe2910413448227f8ead3bc0acb031fdd690fbc3e711bdc43a6e3b11c60d9f5859856657abb77e32b3e1ebb8b1c8659245493b509ad5709ce6d19fa967ceb5b359776d3dcab62bd2b68c59c16d34e8040e9a308e2515958ea6b6ae160fd60023f2954b40e00012027c546aae9d4b1ceacb010001	\\x36b59cb5fc7134be556b5d80f6c257884e697beae78773b1ef81a39d0a0d5bb0f990a78de60a9606dd02fe5dfbe5a586fc17de90a98cbe351554e7fa62790303	1688461489000000	1689066289000000	1752138289000000	1846746289000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
402	\\xce5f19f9e5cf8e3be91e2f23ea018c431d77d44a5d9bfc94f9007a0480bbde2ada474418da15167eeb6f58aa380b3c374124cf5110849ce061b9f1d28b79cd7c	1	0	\\x00000001000000000080000398ae71daf2989a0846091b2646522c625fdd8ecbf46fff18276f2250e138c45ad23523572a4f0c6ba6a3e087b727087513821c5b6b0b03f0313bfeb560c19ef87c411ea2649237f2b39d7c1e0dd9d799c430f554759ee47910ef3c32d327a6c805e586316304c411759f101e94536b54e4f4cdf09cc1f009e615a5c9c04877dd010001	\\x289c93103158f4c147569109beda1994f818247f157a64dbda44e12d7565dc2ddf22766790f1b67ab8a845906143e439ed6dcda9d127c2f217e6aab4e5deb40e	1675766989000000	1676371789000000	1739443789000000	1834051789000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
403	\\xd03f891394241eed12b12eca284f0179ef76165f3a97bc2551c9deb2f0d4b25a00ad3ab63347a3d24598ebb76d64e7142960843abbdb95e14c9b5585e890609f	1	0	\\x000000010000000000800003d384dfd4af8768321b665aa07527469897d7eb48bac485c98674c6edd2d4010700ff5a696e4ec0eb76b9fb2d6e7c082ca82f3aa3960b40c642ae178fb4fabf5c3b912af15e7c17181523978803c3c7d3802bfde8a0e77a83d6fa28db05b69b3a462d2fb26ddf6bf851b80cd3bd3ca09e14bbbc5438d73cca0c3183a23948bd71010001	\\xd509fce5db1759890bcb238e5f3b40f036665e29a85a51d1a076c6962140ff93310fa88413712278b3bcef74783acf7b664e4078d5d200c3a1ab93382248070a	1686647989000000	1687252789000000	1750324789000000	1844932789000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
404	\\xd75bb1bf2813d8ffe3cec9f6cd9d58f26220b31fa0999f97ca3d02c86390f0612d309583379c60b7ff3bc6bc8bc42afbe7c297e3e83301dc67617e5325ec4873	1	0	\\x000000010000000000800003da2cda908d2c01feeae779403b7d5424d1e0c50636d9b09daec40e25d74e9fb7050093524071505e8c14042438a8065e97309d335fd6e7b6b5b4ea6a86b922de0e7db47e83089d4398ef4862abc0f3353d160afcf750f0a91f76dc2f76a82df8d44d16ff1869daa88cca9bbeb4008b467b4bcc94595daa9075eee77ad422447d010001	\\xc067306b1d8e1ab145d5f11b6c4ee78a578b7c35529afe4f8fb717ac493b228ff25d20a5a8c6d27a053df2b335be50dcbba68022ded2d3255ce08e4e2a79fd0c	1675162489000000	1675767289000000	1738839289000000	1833447289000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
405	\\xda8f1f404415f0fab653f9ee5e52370661560bc839e18b4537d490561bb4db5ad956cf3b6403a55f9908ce37db3f2b23fc31341579408d2de3956be8cb7c689a	1	0	\\x000000010000000000800003b9a5dd6122901b9a9630f8ca979d228179591b76acc787e76827c8db50eee6b7916e1c76f22bf594c259754fd8a1da26fd5e5ebe3fcad974da0f67f6b542a3bdb8d41440a759accb0abf12e2f7d01443c3bbe992a2e010cdb5a61c0774f6babf4ff7cdc0350128174d47830af30fb92aa951461b01a5937d25d6020448f9092b010001	\\xfcb4d9cab7671fc97837d7cf22c901af757ee2a7c8affe73bf392f75bc76aee4433a206f74023240b642da4d88cc2654c046e4207165ca2565651d521a56af08	1661258989000000	1661863789000000	1724935789000000	1819543789000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
406	\\xdd5748678302f85cfc284772d38561adefb84f1f6ab38fdd0644de2f95b8fb91edf1a4fdbab788fba2998f3bb85f17f07fd93a141231432ece779e1c95c2ed8c	1	0	\\x000000010000000000800003bfde48d1c3a20b6c1c0fed24ef9b09d6981c0adb70c48da4607b11f24109748bf5955eee9f61fa8a65b82aeee6c8e5c26d2c6b613542c7e7730fc38315487b4684e035e08ab6615fd54b3f56e661bd35dcea04b32f6f92a24bd7fe9067359feeeb4f44dea59228c7fb2100cb46ff2819e6e9ddc3abef065f7f5acd91360dad83010001	\\x7c5c52a73a2cae0adcd52ab04c3f44cb008bc304e6ad0276d5ded917ca85071827b643eb3375699a17b1f26ae4dc72e49c643228ae9face6e66eb79d2033be07	1675162489000000	1675767289000000	1738839289000000	1833447289000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
407	\\xe30fb6ce11d70ab8f5c936ac40dd46671fe6fdbd4621917d3d1503207a68ea5b60d9e3bf390d5cda366f701254cbda1375a329138de8d576c96b2c33e0519154	1	0	\\x000000010000000000800003aa192f11bc1b3341b3193e757bdc7a671db4dc836a0d5b8be836dd1bc7ae7d85018006a802ab2c10f442afd7de6cde9fc19cd5bdfb79b1e376f2a6ade9b0136aeb75095d271b61f5b568ccd0a4b15ff0dfb5fa52e655d013cb8b32e875764a12aa77af9c866f26d9662da169c61591e23321f8828bd5f250890f7b78adead211010001	\\x799b7bce285251934cabb470a074e58e6eb409fcf953f41f4ae2b3aa65c1317944ade7fd323fd837c3b7a2fec4dae5384e93442bae74a5ea3e7fbcc3336eb407	1676975989000000	1677580789000000	1740652789000000	1835260789000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
408	\\xe5bfb46526093d9df8f01a75b430855058d90e71c20577f18c33d30b4f7c20f633b9445b1db22fd5e33ee09e0fcf12b3923b492653682c96f0b0b8a127de343c	1	0	\\x000000010000000000800003ca858d3edbcffd77885a2891cd79cd60e98e918b6de58380281028fb1651bcf66f56c3f1b49f2cfe95880235b729d2c936d20e00f64468db58ee087b656a9f2710489adf97a21354f5e3f5fbdd6862a46b60c8f1bacb92ba1bec75a165cc176b9e7718ef6bfbdcf8bfcc2b6bcfba9069cff56a0c077be13be77e7556bba5452d010001	\\x7a320e7cafe3210291fa21074dfdb18f01748c19e6a5dbad5ee65505e3eeb164ce003098a749670a847f072f0dac61316a82489e48383810edfe1daea824cf07	1690879489000000	1691484289000000	1754556289000000	1849164289000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
409	\\xe6871793ffe80d5cfce9ea19dded3ca01ec23e95cc0d7373acfa850d9f21f59884b896191ae5c83ae5c772a7fabdc3d83a9409c2c02500408e68db595b62ef94	1	0	\\x000000010000000000800003f2c3dc38df6c124a76f79aecd53d87d8a37ddcd98b580a977b87b21fd1202ca95beca2de13790d9d47b84f928610d85d46d6407e48fd7a219381bcf3e51fbd1c39c2f111aaf5679ddd8916ee95f6db5740e2a5064e3ee5dbcd2fe22dc13c8916975407f46b87546be982cc46b9dea2fb6ab9ce3df1dec96c24f0092d716669cf010001	\\x96a8b1e53a0c9b35cf28acdc24f0a929e06e54cc8eb520498e74f1628eca458dc0dd1818d07dd4ca27e8c42311cb36d88dbf17b59240c574e21d31fd0767ab0b	1667908489000000	1668513289000000	1731585289000000	1826193289000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
410	\\xe6d7eeab9af49214d16d911ceabaee06e3668ff0d6f9141d7621541032537b195800a163587a6bde35d4ad5147681f20946fa72d73fcdf5c212e3056e30672a7	1	0	\\x000000010000000000800003b10ffade5855437445b647e896ce5ff17361b89c8aa289313ccc7eef5803ba5cc53061fa085f0c17b427a0fc1cf3b3102a6c00c9ce4b2521b46fc7f790b67d87a4ec92171e3f29d7b0f572a8bcb6bf284eeeb6a180e983667a4914cf9a7c3237dd4b73d1bd7746966964e21c4f56b4b4996fa0d61c2d1cae79838d792d72f803010001	\\x4a6c14fa5d1eebc96bf940d8e7d74e49b970d3bd1c71b5df794f3fcacf302d4118684da3511db77e276ec957afd40cad0b801aa203bc4bc8914164c716bb7d00	1682416489000000	1683021289000000	1746093289000000	1840701289000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
411	\\xe79f57339151e1e4a64dc73b1899eb51f5a3e35216437c44d6681332a4157fb9b62f37b752bd5f818c59ffac70c0e32b08601d69463b1c7d715370978611d56b	1	0	\\x000000010000000000800003d9a62db951d9f2c7138c5ee6ed47e280f85779211a9ee63084c914e98c02f7905e9cb2eea5c81d1ea2b3ccd681b5f2a53138973c1fd53e0f18d196ebb6576dab861678fc789d89e42bd2dd3af210d9becb837861aebf9eb18273bbc11f4ec133433cce59fe9ce67a3b9d50f38aff911fb2a2b42f2d259325b0416b9127191cd7010001	\\x47c4b69d75e22434d3d26b1ca34f1725fe55aa4b35b316b154ffc8df8400c27586dae5bef013a83b011956e68084b8f13ed6406e2bd0cc7a12d1345b533b2904	1666699489000000	1667304289000000	1730376289000000	1824984289000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
412	\\xe8e7260f08116ae3154ca3ca698206e9bf736a14ce53b855a63f266ec529cf75bb1f8a3dad4251d02d5b8c3d6609136a8bd691ae7c53f1e1c8486a41ab91600f	1	0	\\x000000010000000000800003e76a9acb6fc16afeb14552eff8cdab7256294560d7067f96ea96e87857d4c48e7512f4cfa8b06de7253aa90ce23d8c4f40b15d34168894479090532734aa306f417da4c526340fd0ec2d325c3b18b643fab97df1b0eb694121d6654de78581f1a80b7dda3b55c9803bc7a0def85de4cc096ae95348a80eb9e3b983e05fbbe13f010001	\\x1ae413a6c9f360c62a15e3bffadb9a89c0a1e5e18a0acd746965c83401be0150c3f1dff290ca6046aa3f40da5853fed399515bf3bc0eba90f13c129b64a27906	1675766989000000	1676371789000000	1739443789000000	1834051789000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
413	\\xec1f5f2efb4e2b8d44e03adcfd3c229a17fa6c5447c53859e884cdee84a1d5c83b14dad49adbd1324a4979c7ebec2edb9059ef8f5613adb9275cfdaf201a0098	1	0	\\x000000010000000000800003d5396beaae87bc0564a9463f3748f4e15f755e3943f7f841d450b9d25e2d7b065764c4426b8e1c08aa458b36e6dc3a18030f0e13f9dd037057cf122308b96fc31e404cfa0989f83b277179f9d6049dcefa239fe55a20eaa78b88540d66183cb9bbd007b2a9c2e936b5def898e51f1e63acfd02a1ca8317f2edeb9edcc28fc427010001	\\x693b44ac621ce68da56bd0e2146f3a084f582592f5db4f30a73e4b2b63dc8ca322174f957c0f98d43929927a5493f6c6a3ea23587e391ffbeafd0f0a15d39a02	1687856989000000	1688461789000000	1751533789000000	1846141789000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
414	\\xeeeb6e7de5178032a4fd8215324e0d6dc0e1d1c67de80c93a875c1c953cda0d51bba48b9c8053c227363e256651ec4a5e1b693fbaa82269a7665f19cf5c08ac6	1	0	\\x000000010000000000800003c7a96fca0a95e79bef38574ebe95caf203b927a89f5ad33a2e30f1d1e562d4b02b6495dc92891bfb9c148e935a07c6cb6be124e7da6f3783614fe27459d48e5d4e8ec28bb204462b6569c56c79689ac496cdd9de681773d4511a7ff58d72f6572ed4b13ad8f08d87692d212a270f4ea1b7d8b10cf0d65f964dd8d71a5c759907010001	\\x962276d335b986d5e7e7e1ff58eda174b07c2796cf5ce78e4407035ef72ab1c3d3c6aadbbe3b24e36cbe9c891eae2775983ceea3621f6432d93b23e68d366407	1683020989000000	1683625789000000	1746697789000000	1841305789000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
415	\\xeef7885d12ea6bd13593239b85de796499a149cdb70823d2f5e8497cbcc74c9fde6a7525cd7887c2a935f53d9219752559e7e2feaeaeb5da2ad962a074f6aaa5	1	0	\\x000000010000000000800003a6d333e6558976397f720161848041ea0cbb47e75e300e1f051cdf1a6143f5ea1699018e7cb82f67ea664938aada4362767b3704006bff667af948a0a898e6e5b445b53cb026589284b7d3e4b615a3b84259dc64646677947412c0343820e73f9e94d77e23dd7d7d42c045be1dd47645d54b602d4b498beda41b3f75364be183010001	\\x7c8942682ec3c75653a8b99a3cb27bc85b3a65e0cac19f206e466d2cde2bcb55e0cd4e2e1cde554522fe4d4dfb3b0643a16f93ff23b8e83898dfe0f76dfa0503	1672139989000000	1672744789000000	1735816789000000	1830424789000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
416	\\xef6340c6a696b5969bce507f0fbe123e0ad44b9e08b5512026e811368a87807342fde1d99e667cee1df571157e70aa7cb420fedc03a8d7403e0baf82ed209fff	1	0	\\x000000010000000000800003b71689cde19128e9abd909ea11e0f4b8aa01539ee45e3dbf75a5fff722949009804f0fd3df94fcb23efe2f0996c49b389530c5ae2d5b1ffaa1fd50693d9a2a4b687591c3baccdfed8f9035ab42d860efa4cce45c2100af44722cfeba2a0dade6f420ed5481b1e8c15cfbf4986b6ee05d8ee821bf4b120f43cb970f6fd2a559cd010001	\\xac13d6b3394a32c64ca3080ba37193d055b38a571cc6b573d55b11e3aa4b75fe83fb7a60da50eb8f2e3e834482788e1b575acc88003325bbefeeea1b7c58bd0d	1691483989000000	1692088789000000	1755160789000000	1849768789000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
417	\\xf1a37222fd8d4e84b1d24d14efd945acfd0624370dd0c81d8389a742f359a15ca5a8a0e065013ce9c0e1e285927b76ee56ccc19d42441bdb90306b8130a22633	1	0	\\x000000010000000000800003aebcb99991844c3f95f54ba167603df4b8122921b8c86695ee4cb4db1b61951797f92618b05f0738b8421b1137f8b70da290fbb9eabfe8ed4b9afb8b191f5d0e92f407923b475705633ff1068c273f55772899b538aa66a4ec50ee3b5a42c23560945b79307caf35d0d73c2021c93d40f8bb8c832a852c773cc1e45c655c61bb010001	\\x84644086d89242221871ff1dd33aea8741ea737c96c1876252b2075b79e4fcb75e7be5062b20505e09b4fd254a3e2809b3aabbbcb2e833b71cc7790ff78d2c0b	1673953489000000	1674558289000000	1737630289000000	1832238289000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
418	\\xf2b333023b3ce79ed1deb60f9f58df2e6401ba01af22af070b42e0babff82a916bd6256e54173478e4c25da036943eb5260fb5424dbf929d7636494f3ab904a9	1	0	\\x000000010000000000800003b5706539afb5133fdc5c7023621a1527bdddb8aa53da2bf8abc21b96fc947411f085b4b8a61a2c3271d4eb65479126afe4fb9b1dbce84c57d110a905d0e4febe7b34e4ec0e13e6cf056db805853b5e6b0f83638da5a1659e83019ec14dab79d6af6820d3c0fb32a9e5517893af1a124f5205654747f9a9ff451da080dfb6d429010001	\\x06d000297c73a4912e7d7e7f95eefa965004afa6469a13c404c26173ed848227af3ae9f4919c1402a795a2c4ca0c90f70fd5c98b717232fb1a9ff30a9a6de404	1669721989000000	1670326789000000	1733398789000000	1828006789000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
419	\\xf6e75de99e0047b919477952a5a0fbad2779b958c14adbaf6a0a2fa057cbdbb29999043c1d83b901ae8ff5a3822ea3c23f7b23edff90722fd32af8077a9ccacd	1	0	\\x000000010000000000800003b0f71ee891427fdbe8ff6088376ae28420471abcccea02a234d428a978d55bcc23b1111dfdfa7a11dd1fb0da75ba9975818a992361b453185643d627f4ddf42d4f195ce8e930fc0e1af845880f8318f85cacddfe898b6e47f41126c549603da1fb5159a1c8f60a50564f20bba68b3fc9301dc4def9cabc1599a35048809c2429010001	\\x69fe4a31b252d33a392e8e57528cafd3b272c3048be4a04024d579497958842a250c947d6c16b86877e3f462f656e7193a3c994a20a5920d4d8401861039110d	1667908489000000	1668513289000000	1731585289000000	1826193289000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
420	\\xf723bc3d3c0754ccdc976bd34a48b7a4da1c96290ed1eff61b49dafaa3c0b09a8cd3bb45b1af0c6b6fe3e31acc3dc34248ce6912079657365c37ca4e78f1f3f7	1	0	\\x000000010000000000800003b0294c568f7f33162fafa9e3d71be42615a5cb45a20464600a5c288253051546fe56f0ffe20483135bb2aecf8c8bf11925f597b96ff6ead022b3e45e4c7b6459dc916f9f0814e279bd753568e3a378bc50244e982044ee8ead2fea7a830cfbce5e36554f82ddb0a7082657bed01a40437791b79e87ae72492c8994f9500577df010001	\\xb7aa7c5081408c98f7306739758421a9923fc9e3fc73de84379647e70dd9e36a4014efc141886da0ce7aaf81553cd3af65a16d04ccf41186cd76096cb4fefb00	1664281489000000	1664886289000000	1727958289000000	1822566289000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
421	\\xf87b10d117daba6cbf20f3d980130234d322141e505a8426c55b328d02896c14b024505a7a3cfbe5b7711ead87bce48291dd5e3ea5d1c2df93442e80bf150672	1	0	\\x000000010000000000800003b346c5169b5400023a73f948f88fdffeac7853301c4ae3c54fc286bf117f7e957443bab79c7c1d030e0378411724d0fa455eb71587dee235b64cfca6b57039f898098113cbdbf68096eef445c309255dd14ccf1f75834be52592cc20b5b4415859d4a828626a1dc9eaab2016dec870d484e76f21222c615e80f62e44f7262d8b010001	\\x0b2faedbd78eec96a5414fea2553d62fe96cd3001a5297f60902ae83ce4cc80b2be3c4dba69267d4a79d03ee92481be324a3367914715881ee3eac5d25b31905	1668512989000000	1669117789000000	1732189789000000	1826797789000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
422	\\xfadf36733a826837a775b9b2a3d3aaccc958d2659f95b264c4505dd17425487cf4cbbf18173177e3ebc67da8d7105886aace28e573b311fbaa56c6d058bd5594	1	0	\\x000000010000000000800003abdec24cd2d664f9847ae99b988df7674ad98f49b1f8117702fb19dc3bb6c7324c68c0b154eaf754297980901eda5d8ad52d2bb7f3e1bde1469622af4375530bca13bf44809cd1c4283d71bc6ef798b61f0ffa23fc25395c42fdfd60c95bcf171cf04cc849db21097c2e31c5209a50151d56545c1420fe877154d21b4db407ad010001	\\x17d31c2dc44c9d55641f067f8a185fd1e0446cd1e148586303a3e4bb0499a64374518b3da361b5253d8cd1e5ac22b9c6a36b7e241f1987f96554ce9aff1de208	1689065989000000	1689670789000000	1752742789000000	1847350789000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
423	\\xfc5b3e069a61da03a68e76d8be66849ec4861baac04d3dcc9daecfeb8cdaecc59d1ae8c822d3342948f5043e689cef1029920ec47c0a9178e4294f21318fcfcc	1	0	\\x000000010000000000800003ca6875dcd07652196c8155356c7f632ec93b89f0f10f4bcc67fcfc47dc5f0e5dbd36c6cc327b821adaa4ad81591edd52dad0b77cc677e79773fd35096e02baf6c81b53d366c5eec25b57a136f81c5f31683c089a5107f441120bcd38864051eca42622312af616c247fc283e5e025d0f1ad846fd1afb418200e725af618c4b57010001	\\x4ff18d7ab7c05aa6b3497c9babbf1c2fc7e96d873df79c12e96e1d4a926b036b65b2689c22c213cfc09d6114d30e2881e74ac72f24085089f8a77393f118bc04	1678184989000000	1678789789000000	1741861789000000	1836469789000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
424	\\xffd723d689efc566fbebed594a21a06a5fde22826598d92c175a36a3323ac9a131d52e54b7ba8688b4c7b5f8007f5727c6b0aa5927a24560cf86ec46289be94e	1	0	\\x000000010000000000800003a769252d8d8411e8b021db5705c47bcca1f4f40a5b7d2c7bc3c7c4b48d57ea695e7e341dd1b0986dbb04df64b728d5feaef62cdb42166b9e8b9477c69fb0eb3af1dac305d15c38885522aa5ee91901e14d47669e93c18594f58621445873d82c0119764778c53caa8983011c295f4fb89049eed7384c1a42c19593e7d4df4de3010001	\\xec7c1a702185e06e5ea994a715f28fbbfc59038f8b4b2165db373b4335880d6235b1d2da26ece0fad4359ed790860e1bef5ae2f926364240d7d66c03db848908	1686647989000000	1687252789000000	1750324789000000	1844932789000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\.


--
-- Data for Name: deposits_by_ready_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.deposits_by_ready_default (wire_deadline, shard, coin_pub, deposit_serial_id) FROM stdin;
1660655418000000	1286140963	\\x00482e972a0e5c2d91efad58eb2f298fa5604f7879e9be37657061e6fdd5e53c	1
1660655450000000	1286140963	\\x00ffd8756285c382ec9c7cbbea48a2d0daa35ac810a8d23f126ed758eca99b8c	2
1660655450000000	1286140963	\\x08cbb6eb28062d0ee4ea289196cd77b6fbc825bc6972624b88c5512be2e55fbf	3
\.


--
-- Data for Name: deposits_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.deposits_default (deposit_serial_id, shard, coin_pub, known_coin_id, amount_with_fee_val, amount_with_fee_frac, wallet_timestamp, exchange_timestamp, refund_deadline, wire_deadline, merchant_pub, h_contract_terms, coin_sig, wire_salt, wire_target_h_payto, done, extension_blocked, extension_details_serial_id) FROM stdin;
1	1286140963	\\x00482e972a0e5c2d91efad58eb2f298fa5604f7879e9be37657061e6fdd5e53c	2	1	0	1660654518000000	1660654520000000	1660655418000000	1660655418000000	\\x37e1f963450faee0d8a56acb6aefe95536fe65cc8b5accca1924c6093a40f6cc	\\x00cdc96040fdb55b71f39af7132cb8d53a818197207e1160a403edf2de1588e579dd07e454b85706ec6df8f07fcfe773dfc1a5861f8eaa7b90e20ada26986c50	\\x507bc5d978ee1b4a2c0c032b05aa91ddebbd8eaae1c26f8e53d02c5f685ea9322ba2547c930ae4e627ba91229ae9e363ec7b594900cdb1db004b4475da13520c	\\x08d3af20dd4f3192c2b79040c703b7d2	\\xd31e3f48cb5318906dbbb7948326362f41604c7a728323230ae82aa995f27400	f	f	\N
2	1286140963	\\x00ffd8756285c382ec9c7cbbea48a2d0daa35ac810a8d23f126ed758eca99b8c	13	0	1000000	1660654550000000	1661259354000000	1660655450000000	1660655450000000	\\x37e1f963450faee0d8a56acb6aefe95536fe65cc8b5accca1924c6093a40f6cc	\\xc322b4ebdf16614d1c5a72ba91989486cda1e26b02ef26d105f71bd952f2f22b9f798dab19b98bf191c662338f571a6c295caf24ef961390262b67f697a5c7c7	\\xfee8fc92bdd8d0f189f27d7978ebc2219642563e0af5856095d7f4b7a15cd14b264d389a58006fc52c8ab6fc85d59828b9a3f9ec0ee2016bf8bc4a9228262d05	\\x08d3af20dd4f3192c2b79040c703b7d2	\\xd31e3f48cb5318906dbbb7948326362f41604c7a728323230ae82aa995f27400	f	f	\N
3	1286140963	\\x08cbb6eb28062d0ee4ea289196cd77b6fbc825bc6972624b88c5512be2e55fbf	14	0	1000000	1660654550000000	1661259354000000	1660655450000000	1660655450000000	\\x37e1f963450faee0d8a56acb6aefe95536fe65cc8b5accca1924c6093a40f6cc	\\xc322b4ebdf16614d1c5a72ba91989486cda1e26b02ef26d105f71bd952f2f22b9f798dab19b98bf191c662338f571a6c295caf24ef961390262b67f697a5c7c7	\\xd7a6346c5d0ce0e6b1cac5534bd7d98c025b2efb5ae6a35505ed54d4c7e53784f267478feac143ee5feb629a2f7ac1bb2a85b6d75753fb92b91976311efd680b	\\x08d3af20dd4f3192c2b79040c703b7d2	\\xd31e3f48cb5318906dbbb7948326362f41604c7a728323230ae82aa995f27400	f	f	\N
\.


--
-- Data for Name: deposits_for_matching_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.deposits_for_matching_default (refund_deadline, merchant_pub, coin_pub, deposit_serial_id) FROM stdin;
1660655418000000	\\x37e1f963450faee0d8a56acb6aefe95536fe65cc8b5accca1924c6093a40f6cc	\\x00482e972a0e5c2d91efad58eb2f298fa5604f7879e9be37657061e6fdd5e53c	1
1660655450000000	\\x37e1f963450faee0d8a56acb6aefe95536fe65cc8b5accca1924c6093a40f6cc	\\x00ffd8756285c382ec9c7cbbea48a2d0daa35ac810a8d23f126ed758eca99b8c	2
1660655450000000	\\x37e1f963450faee0d8a56acb6aefe95536fe65cc8b5accca1924c6093a40f6cc	\\x08cbb6eb28062d0ee4ea289196cd77b6fbc825bc6972624b88c5512be2e55fbf	3
\.


--
-- Data for Name: exchange_sign_keys; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.exchange_sign_keys (esk_serial, exchange_pub, master_sig, valid_from, expire_sign, expire_legal) FROM stdin;
1	\\x811bca6bcbe1bfd86f768d8f5917a0119f9006bac645b532ac39076b6e540453	\\x2a5114e54b06bca1ac06f218b69dd18c418d0b09dc73db5f44c61c195515d6554b5ee765c4ff151aa9421a2b0b13e934c6f26ba2fe11fe12bc823a4f640f5c06	1675169089000000	1682426689000000	1684845889000000
2	\\xc32561194b4b6682cb7029e149cb59c85de1968e440502f57040754b2a678892	\\x7264213ac164de65e186b021d57d7cb94ec27245ce25c0caf460ff9dad3463d213f644235699fd4cd0a4150f5f3d92c99da5d6d4d873ae93dac4407775bb6d03	1660654489000000	1667912089000000	1670331289000000
3	\\x50c01d5134ad469925ad877b9d6866ae23b0655c41705b44880b2ad4e69f946d	\\x08c294b061c552a32f348aaba6b55d03f0d1c188be276e8f3cdc0e4599fd714730e25b91a785110240e5fa9e8cfc6b2432d27fc68d1d84f5ab2e083a42fa5a09	1682426389000000	1689683989000000	1692103189000000
4	\\x70dccf9873559849a59c15a45dc39949ab2b6432936a14148d0a8426b4ef4230	\\x9a155de882455e0bdb4f8dc71954a88eb6e8c318f3fc2a4015a33dd682c23211fd7877544e5b72cb4e1cce17fcff876abbf34cbc1720ce869ec9d159d02cb900	1667911789000000	1675169389000000	1677588589000000
5	\\x92b6657d3608b9e13fa32373bce1aed54098deb20f173765179fd32b3e7aac71	\\xd10e81652ef36461c2a69d6cf00a2d4628eaee995b63aab78147a163e76e609ccca4cb28637b76e87f7b2f2a0309bbd87e093b9e7e39a0a264e237ad52d0570b	1689683689000000	1696941289000000	1699360489000000
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
1	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	0	1000000	3600000000	3600000000	31536000000000	5	\\x52c2ed8fda0bf03a86a1289c1a2d3a30f591b3f97bdcc68fb0d7b7c82614af9d20b998478bcff9ce16d70960df7d971d6a413db287b7db6f0725244478b2d805
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
1	3	\\x81e52922cda56c38827286da06915f63d0680b91eec0d8562c692c484879e1e9	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000af4329dbb51890fad6fc5fb289d6980ea59725a245d2f5b75bcd001b84b45b6ff14f63899abcf8e4d0f8973986e38f54c7c167a19cac9bcf323ac4d2706ef66f757af1c6d247960ed4cc5344490c985da9500de54865c9799294b117688f1fc58d0fb8fe916b48fa4d70e698666aaa4244149512f5e52fccc2e254959d123365	0	0
2	384	\\x00482e972a0e5c2d91efad58eb2f298fa5604f7879e9be37657061e6fdd5e53c	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000002003eea973fe7d507355431568a07060c4801081c2bcac30ac171661fa2ee1e8061fc649c59afddf02471c0164ca9f4f4ea40909571ea81ddb0ea0f041e2adf505cacd9a89b788392b32c215fb7a12d91a96a434ba47eda9bf2d665e4b13a3c8f6a1c6ee6ee4129a5156d4b229f551c5d80006e90550d28ddd2abf87ccc79d90	0	0
11	228	\\xd4ad63ec6d13117d9af8e2b35950d334bdcff9bc2299a1af23837eb81624d4b6	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000333823b7dc9dc8bbba63e1d4508c402239121b75e7bf421bceba01bc7dc947becbc1285d6025351cfb5e64b50c8e0f6bb74472d316b86ba3b43fb76f8e2df8e28daa7a851f3c2b8cc0ccca4a2e9dd7e08f1ecdd182f096d4be255605916c54edeeee2656449c4228d620e5e71ae497e294144cb189fe907b7c41c40c75db110a	0	0
4	228	\\x3e1bbd733c5d49f118fa8e1f37200e469f903282520956f8f2e1dbaa38536b94	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000035b038e0001022ec54b9249309487742793351e642446517949c1e4d19e32bce74c470b88c87e5f35469b8ad907746a3711365898ff5e34f8190d22a2b422db26c3ca75e7b3da792f180ab0c55aaad8d024d9c428cb03a5aeb2b6ec1fa6b6c2b96cea79746fefe17eb38d21a49cb5f6326798eebcf2fa24dee96b730e27d381e	0	0
5	228	\\xf12e19044b7c6c87ca6e2c2d29d4e032863aed6e5344ba2cfca87c2a4955a90a	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000061f84c655f893d126e0a17c5cf49f27aae622a9319db3e6d0ef78912920f76927f320f06b36a2dd40519901bfe566c308f69dac16cd3dd2e4d8fdc505ceb886f86c43192a5a8a22be9c0852b244fa313d3a96a07060e25adcabcbe92bd4ee49ded86c6f142bcccedf6db011115a3afb5be654d96de79f0acc6a3328f9b46c3b9	0	0
3	104	\\x13f3da5dada4e71d1d2705680f0949426d5729b6746c3fb9297ae081706dd2eb	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000073c13ad622193ee1f20bd6fccbd75db4f145502e13ce648d13f60041ff21cfd3bb868994e46c497d52a8ac576d450ee05b5bbdc974be286289adf6568dc0a1bd434a6e4dece2fffa5082b7942f2d22a29725cb60ba08f24d3480bf08f82e360c8ebbb190d9502fba630862e2fbddffb21c447dad4e6a244331328282f12d0310	0	1000000
6	228	\\x461655a76851395e6af54470944918c03004e5e0ac6c9b2eacc43a513ca37e8b	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000004be2a747e83cf48adabc27e2807fd0fdceea81c972981eb969ab1b714b6e3a3b47175306db5468de7857d160116eec5a5cdbb78d2548ac151270009421858395e779684be65b605c0155b56c463f8421ebf26d53f6b8866ad3514aa890aede01f64b3fb82cc79b396ff31f645d1cc222c75fd58eb948db9fb9f11871dac65d5f	0	0
7	228	\\xc149761685a06e3c38e9cf97e352f98891130157e7d960e5ed82c525585b4abe	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000d104b9ce01193f5d63376d944d1807283ec5929750df99a6dd19f803ab6f012b1b884c930d9d9d4e8c406423155b4704a87d8f4816dc15ce90f1c087492ed9879c5268f17e44e61399f9cb81ef1fc5a20898622fe5b0df98f5ce2a046f55aa365d36e64db9da0d0f5a5486e19b36c2bddfcf3ecd95fb9f715d38738440e8161f	0	0
13	193	\\x00ffd8756285c382ec9c7cbbea48a2d0daa35ac810a8d23f126ed758eca99b8c	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000006fc9be5adeadd985672c46dfe75095bed8687dc79680287b832adcd9c18fe9fa7d25be2abd9123587027b88833a687dd2d5cc8b229339d86daa894d9c4c7ec6a2fad493e6f65843b8c50965feeebb71b562ae4a4db0250d2f09c3e91c8167dccdc6090918e2b21c2159ce3e131de2f22a4e8d9ce3ecb620c2317008cab1ec2d2	0	0
8	228	\\x72597e88734b124f2b6898f990dfe4968372e066a71455f0886f141c219abfdd	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000057cbe2cbebfaefa3532514705b8acc58c0101966a63cd1ff8a8bad8002b58b389225e6c11c20711afa7536a302fdd648094381a50baea6f8dfed47d44f26d96c0dcb19eb27f202a181a9dd3387dda8bb6bd1877dd31978bf4c370c3e3e67d46eccf430e9ddb0e7461a4129a0828e5a7f80b58bc10ee8fda061986fd072ea528d	0	0
9	228	\\xc0e2f5a7fb0b4b8c461c50b95e995bf3e0e7928b4f725c8cd94d1244d8a9b1fe	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000004c579eb7084325a99b9000d5106843e59c58bbdef6f145745e3a23814238add0f4fa16bf19833f33b703b9e8ad25bddaf6efbc791bd60000bedc337544e67a8fbc9c862c321bd016923e32de3163b69187dd469f985872929fabe182b9906441de85a308c95ef31d566652e1da753e210c15507c1543998d92b74ed0a3eae35	0	0
14	193	\\x08cbb6eb28062d0ee4ea289196cd77b6fbc825bc6972624b88c5512be2e55fbf	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000004af6bfe50cb21de99e4adac02c1befb9b0946dfa791da29abb456ab14f9da509ff0149ca250a762ed67867f5a8e932e97ac5801fe20e05cb2dc5dea283c49845bb4e8552df26adf222254a0c765ea287880721d9d2156426c47f9b9b34a88f6ca37011f16b08100449a50adbab27d7b313fe35ff58b91bbbbe89dbfae8876162	0	0
10	228	\\xd27fe1d9072c9f90945819c6facac13c61841e64dcd18022fc0bfb7dee6b8f31	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000010c13b9b59e63a779cb920e344c412ff9d1e50d3de37d66a5dec54c8e24f358464e501367c52b0969caa4924d2bc2b6d4b1f0b2613f36395363bbd1fe9a33e3116ce5f89a6e4c9b7917bf927abf7210c01859a4d5afad045fe8b25c64b45b43fe75f720adc6e2116ed095f3cd7f38b6938289a3f7abb6ecaf5824aab98aa2800	0	0
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
2	\\x81e52922cda56c38827286da06915f63d0680b91eec0d8562c692c484879e1e9
\.


--
-- Data for Name: recoup_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.recoup_default (recoup_uuid, coin_pub, coin_sig, coin_blind, amount_val, amount_frac, recoup_timestamp, reserve_out_serial_id) FROM stdin;
1	\\x81e52922cda56c38827286da06915f63d0680b91eec0d8562c692c484879e1e9	\\xcf5d423ea05618c32afca2ea30bfc2fde08880a1a9982c2de1015f9cbdf621ae1689ed6fa98a22200acab26842c3eda03b13b532f17ffd48b7b5d01d270f9405	\\xa3860210e63cba08d0a291e8957dbff4a47ad39198ed020e1bab7f51bfc1c393	2	0	1660654515000000	2
\.


--
-- Data for Name: recoup_refresh_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.recoup_refresh_default (recoup_refresh_uuid, coin_pub, known_coin_id, coin_sig, coin_blind, amount_val, amount_frac, recoup_timestamp, rrc_serial) FROM stdin;
1	\\x3e1bbd733c5d49f118fa8e1f37200e469f903282520956f8f2e1dbaa38536b94	4	\\x3e1f3b1b70d397cb7fe954e2f5a16cef376e1fca3d4cdcb2b792a315039f39b0bd72b75ea5bb56cebeea8eb4ac2f84977eeaf40137deb947046d4ad93cef8f07	\\x236abb5510936674b9ab58fcd355ef9538bf0e3f5e0440acf0d440af63c27ac5	0	10000000	1661259340000000	6
2	\\xf12e19044b7c6c87ca6e2c2d29d4e032863aed6e5344ba2cfca87c2a4955a90a	5	\\xa7464eb62afbfe5b1a5831ba3afa2b61adfd5fbe8743cdbe052ad22c09fb4d90f820460d77ac5614325cc2b4b23629041607c091a2b04c572958fd72e842050f	\\x50a6315c8c31cf90efbc033fdea6573f67b2616444bd932934f0336bd2d73217	0	10000000	1661259340000000	5
3	\\x461655a76851395e6af54470944918c03004e5e0ac6c9b2eacc43a513ca37e8b	6	\\x000d053af630cb59f07e948223382401012622d5b0b57ba42ffc8df75ee1514eeb0c0532ce9b3af21059a0b2b50fd1fa39b6d7c1f4fe5c0dc82528fcdd70c900	\\x1b43bb106fed812305df958b0e0132eebf58b3604b7cd1a7ab0563aa84d70343	0	10000000	1661259340000000	4
4	\\xc149761685a06e3c38e9cf97e352f98891130157e7d960e5ed82c525585b4abe	7	\\xcecdff48850521f110f59cfb1535c5eb814b783df31ad65e9187d4196f70567a7d05a1a8009395761e4c00a3c750b7f4d26ab9ba9748039f9ce1db6592de140b	\\xae60a14e98e263c0d3acc7863a3ed91ba954d407f2703f5d96ff929aa54532b9	0	10000000	1661259340000000	9
5	\\x72597e88734b124f2b6898f990dfe4968372e066a71455f0886f141c219abfdd	8	\\x4a88d44bc054648e32b26a2436223e3724b131b1e98daae7b198a942a1d6a172f1451d8be7175207e5a53782d94ee248f82678753be64ed4a270ca18a3086509	\\xd782724e11a4807f322e1634ce8973c51e58ed896f77b96ee65d93a17ec1f455	0	10000000	1661259340000000	2
6	\\xc0e2f5a7fb0b4b8c461c50b95e995bf3e0e7928b4f725c8cd94d1244d8a9b1fe	9	\\x11b522fc4cf99d2cefad528e56f768c02b14ea831d6ddc1b9a2cdfbe789cdaf9514386d086e95f6f5891e807cdb580ed175b3b241acae30cc171e0d82b2dd907	\\x0fcfed597c34fdb287c396ddb1b2823255e57b7b29d9dc5b779532d9c136da48	0	10000000	1661259340000000	7
7	\\xd27fe1d9072c9f90945819c6facac13c61841e64dcd18022fc0bfb7dee6b8f31	10	\\x37da6cf6b7771593a121320db1f094090b74bd3cac7317232c60bdee598a90c0f8e2c6c309fc18a4cd6bed05abcd868af0133b0f2a0a36a9a6fc037deaa77904	\\xe8d9b8f6bd77071a7744ac00156541eed9be4639ecf6962ac5dfe18f328934fc	0	10000000	1661259340000000	8
8	\\xd4ad63ec6d13117d9af8e2b35950d334bdcff9bc2299a1af23837eb81624d4b6	11	\\x3b0a5fac6e708fc77a688db27cdb719a7c8a68f435c100db1bc7779bdb587e00b9e514b33692466e188ed3960701aceaab944c1c6924004d668fc3a062c38307	\\x748cb06c2b7b640978f2573a0925ae78013988b6cdaf5e6702df675a442593a6	0	10000000	1661259340000000	3
\.


--
-- Data for Name: refresh_commitments_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.refresh_commitments_default (melt_serial_id, rc, old_coin_pub, old_coin_sig, amount_with_fee_val, amount_with_fee_frac, noreveal_index) FROM stdin;
1	\\x7dfa61890630c1563d825da2270b79dca235253b0665551fa53828df09ebbd915f47fcea2be19305ca4b9cf84a6300866a846b80f67efbdedac1d1a512ea4542	\\x13f3da5dada4e71d1d2705680f0949426d5729b6746c3fb9297ae081706dd2eb	\\x6653f438ca7596dc178d56bd8de798ebc65fae25f0c4aff641d8ced762c1d2de8237fc28b2ad12e1a8562e639c8fad30200988aa1331d2a2ad030435492d690b	5	0	1
2	\\xf971a58369c49dda2c7fc11f7bb5ceae71e920adc7806fb45acff8dcaadc5f94855a881071e677362824cc24cfc92d6e0da65b6860d53d19174f65246dde33e7	\\x13f3da5dada4e71d1d2705680f0949426d5729b6746c3fb9297ae081706dd2eb	\\xf05a319098d99b1e80ed37d99f4df9399d105b4f02e2c202261982ff6eb5ef77072faedfeaa0b854edb4ab8efe75da338f035a1a50f7d35721495c98b5da4b07	0	79000000	2
\.


--
-- Data for Name: refresh_revealed_coins_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.refresh_revealed_coins_default (rrc_serial, melt_serial_id, freshcoin_index, link_sig, denominations_serial, coin_ev, h_coin_ev, ev_sig, ewv) FROM stdin;
1	1	0	\\xc2595d50a864d0863559c6f2b1e7796856dfd36d42d4e4524721b5397bef68e8059289f2ee51cbb4a0a3d030b7481c8d5243e7fbfe8c4368efaa600c8a92c30b	334	\\x0000000100000100182df2646043677f447aaba089625a7889e68564a442e4307c543a7d87444a3e5a5e1b32e1351ec18a3db5a8998c5c7f673668e4c06b02892fb20f43026b5d8bbb20744e8ba83317813e896e5a0695a4e9509302322b9047c1efd64a97a06500e94c029997f21ef3f2f97bbe1ec234e5c6dc6c70c6343dcd322e0385baea7dc2	\\x7176da8346a1bf580dbbddaea019655d51ef56698b461ecf4f187e938a1c45ee37f128fb12b6eb2b96c96c6232cde5367da460419b89fa571d71661828655f9f	\\x00000001000000013d23068316985355e5b8fd8263e2d6483412c11c87143a3b24a2f556c8ec0169f31c5d0e4c2afb62d5efdfd0e2a25b380dc9e8f83304555dbd33b37bd212c9c3681782ec984120fa814b5680bdbc89aa4f449adc605e98627bdb72433d0bb772be9787bc15a6045d778a0dec84b6a8ce3f977f240655572057a2e7b696d8b1e9	\\x0000000100010000
2	1	1	\\x72cc0b2df77b5309cfbec4ad17287bed2271debbd23842b0e8a670415c186197122add58eb0b7a07d58c5251adeab56ba5cd2f4fbff11457ad66a522d76f9b04	228	\\x0000000100000100d14d300dfd9d0590d1c355e7fefe3a9fbfcf808fa8a6bc2433deff6f04ffe8a60e38cb91ddec61bbaaa5fd05b9be67b93d28d9cb13559dd8983846c3860e598c354496e1cfe01e6371026fe24ab3c3baebd2e09b045dfc973046a5ae00bc3a21ccad9ae1f69cb777d0038486e66d881804370b2adfbc28f4ceb2a11bd1b47c1d	\\x63db95eeb0108b05566e62296cf1cc40c6cdb456033e5c4db8e15965d8b06b7fbc2c1daa2b24181adb16cd9850429525c57bb69bb3469e2afa56983b5b6ff51f	\\x0000000100000001917ef0b85e1482b6f3a7a74d9cfbfd692c7ebe24fd68039fc4c69079cbc239f5498ba5a993a7c52fa15058b1ebc33403605b9bf46ebb1c71a9bd0b47a0709227071c75c4ab55da83306644d87ded8c0e48b5ebbb7640407cd62194b4b7a86bfe3f099d23328cf9efbca1b41509860676eb82f3a430276c37c9486a319ee2bb26	\\x0000000100010000
3	1	2	\\xf77b9a9c09eaa18c0850fa578a84617adaf1e49502ab2fcffdc45bfd641dbed21e7396b4421f79c6eacb2ce732f50af0638eb2e61c626d1cc576c631231cd604	228	\\x0000000100000100c40c09a2d38b0a30924a86fe67e1c5a0c4351867ed41bbb76e9a5e4f1454aefad647d49113a11730b731463686c7ccf87746a17d1a495000b84f82b53199044b92ba37fdc515795d5c0c6deb091dd50eb6c71175a1027de81ef39d2f6b225e93ec75a63fd8e79244fe09fb8d77e53b8f3f6dc0633cebd00a136b7d2300d11abf	\\x166dcbe65af0a6337e16ff58f5a73d3bec4dbfee3dd74d052e27748c1b4843ee8415fff245a4731d76009554fbe9d3ef5a53a54e13b93fc3f28f8f35f497a4b7	\\x0000000100000001313faeaf74b82494eb48b1c48fd3928d018d1116cab1ec9e5d687311b39c902ab6871bf5fd5d82a1dc7ac09004d9d5c7c8c08246a8ca0120fe63ccb4d75449f32aef7b7cc643dde1582d346ff807036be25514dde7d2eac3540c2d37cc928844544c3dd2704c2345ba3759126c94292ddf91aa2caa955d4f041babc171430872	\\x0000000100010000
4	1	3	\\xd0afd1ae45146278319ab2505db10f1bbfba0adc17df32c29536e04a0a41e7a289df59ae04778c97ab1ff06b7de69ed0849891129c1bb90fe535a6a9f045720d	228	\\x0000000100000100193693da45837bec75908f7a580136c932c490c6d92c51da9d40dcfd3a5a21a0dd1b2c55ea85cb06e43031ab41db75e806bbac00eb9e881cc864e234444f7734c9aad4aaa4eb9a164105af74044fd48631ca273164769cea6eee898b58305005392531d5ecf6322ada8c2123ae179f22e98af020aa6853a2f1b07a217d8b7e2e	\\x02dd3dafcc858f32e8fec3af05ed50a27994a2e8148db0877f0e90ddc544bbaf312d30825bb7691e96172f6837386a17ac4a86a5c9cf235f7d5bc874a4742957	\\x00000001000000014517ad5406ec677bca9e913ffa294a141d29af1614178f5b351cc67604401053588565a89ad842bd6651dc1d2a5d90710cffa3c9287f055d6016fe377d89bed014561e40b9842052a21ed79e9f2e7aa71d96bc9d33a84bf72be0fe5e61e525092c6710361dc4b8bd9696d416ed17cdf19938995c5e3c026d12bbc68a03bcd82c	\\x0000000100010000
5	1	4	\\x647fe96c4784d3324fcac4041e1455518be7aaae403130be73c9ce3e23f9172bd724addaf358e3313a6a2f04c8e6349f94e06eb9bc0f5f9f728ee6599f3b6407	228	\\x00000001000001003dda6ffea5f9b5685d7c53fc6f0afbf16f635785f68f9a0ebac37e06666e168eb500220735c4cd408649dcaf774cf0f18f7e2469679ede92ef57a86b36bbd9bd1bbefe0d079047a412a5a872a8bf604bb6ca53b46647ed588a35e610eb793acadb5b9bc0766647729cc962d2c9cb0f5e18e60c71abc92638548e5e29076a9502	\\x098c0122a9f8d99bf2230abbb716cd0cf276144eb6d627ca285032b14e45c61d9d64c3bd9dcae1ae3d72601c555bd67acd387ca67ca38a9ecc673227d3730f80	\\x00000001000000019cf59e9e2384d52c63167d29c5412ce8e28722650c2edce0a889a21e11d0bc7c11135853f3e6d703f4dd3f3a9f101981241134c2c75500dc242a36907db72d459d4e147ff1cc4222a4af9bec97f04989298bcb2e24450529143308d2d4e65cd29416cbd63c3c9f175b80746d561f4c641387d7137d0456bf8f166cc98ced444a	\\x0000000100010000
6	1	5	\\x54dec43d6dd6ad0b815d66297c3e282c1953384d163cff4b673b859fbec8f195439f4de8c2c427689a3d59da0633d1b6914de4e6df669dea1fa4aac9b5416f04	228	\\x00000001000001000822e69c35523fad484f2bd4fff0e197ec74a5b50a0846ab8130b415bfb5f970d4584a8efaaeec03950c48a32a005d6be83da5fe5199de20cf4263d9091e8353cae8d4f79d7266ef908b94abfe6a7b8ca92402f7b87f1645af4a7a9d01f3cab77fafded31627e7a4f07263825973bbb93827b5a2b87939c716afe79fec76e4b3	\\x0eb36463fb1dab97c81493c2c491bdec5e52bd85791d1f96dd04be50759a558708eca0c29fc607e0f0a0f0b728a1a97f07b9ceb797791c930fe901bcaa02edc3	\\x00000001000000010c6f0e54f06e277d676492d0ee20c46681d7c04db58beaa04c18b69d0c70c5dd8e5dc55ed3e7edb0489a0c7ff02d1088c039945974ef27502e2029dd7ff9c94e001132a8b9dfe4deba769763a51788b925375a280073e0626ffed2c1f70630db8b5932f6206870794441e582ee89a21902fb27883e63a4921aba51591b3febaf	\\x0000000100010000
7	1	6	\\xb6af1992384bed07833370e22b68ff6c388d0c2ceac150f54cd7b9310897e901dfff4cb7df931531c9f7e930362576b0a665cab2cd156756327a2c3c86ee0405	228	\\x00000001000001004846b59b530a6b8fe083d99b632da487087053fa97bfedf81a8941ebc206725a505d6b41fcb97254fedef6754d4b1470b657263f01270a8ffa359358bc27b15bcbefa7ef52faabdc2987721f9dde98800fd07a0a6d9f3ae936df21290ad2e6c776f3ea80902a84ba372cf5de8d5c1e34c26d4d441a97cc00fd71ad938c73023e	\\xf9d847faf04f38e801d746e07156b0741ae66b880676599d03c0fcc99e6d9ff92658bd406549e672c7d753ae10622a329a1401415faf337af7a36c8040877f8e	\\x00000001000000018c346ca92e48455d2378977210093077a03953243e34025bcc49ef154b773145125dc03c51dc975526f3e0cbb89eba75d98399d555786c8b59a2b2febcc078111b4e7cd7eaec30b25da36cc9e73d72dc0e758b51f9c6f7dedd5fab68fbf7674c13c5a15ec261de159f8efe4690434d4c5b1141031d634b58a6d994a6b11eee60	\\x0000000100010000
8	1	7	\\x8d15b24ca56189d29e3942e30d41d13bf325942d0616351456247082abfa625d99fc4550259ea0b3361d1df77f9b7ea60350ee8acee56b80d72bfeb441a3fd03	228	\\x00000001000001001a88f3563133a22cad804600db0eb0df1957f3b7476a8e7a1770a46e10301191c7814016d87e21d6c75113160e72022a27a0166b9b70ee07c682112faabad0c1b2927a4e7f39e21f97ba33824cda715067df59f1650c7582741488164d7c2d5b8710947c235894d4bd9f1a27b9c0613d327d0d139e924f273c14ac199d45bd45	\\x887bddcd4c407a74450efcb653cc37d9b48945b25207004513cc5fe79eefe8a08976f0f24369b4e373c44ad89172c8c7326cf8d4b9e6b62c17f0b0cdf2a270a8	\\x000000010000000130b9b12ef803a5535944e149054e0c28f32279ae5048d74999623d0380862e95447fd7745d9a9272b268c31862e8789842c91e59b6ec67bcb1d729a0c621ec0749a9a498e7fc2ed2a19c9396458ca098104a9c7dfcf9c024435c7dc9ae3d9b3d07a63d3bdedc9ef162079ac67af3329876d7b8e11633031fae0a032a8a677fc8	\\x0000000100010000
9	1	8	\\xd6a9ac66deb4e84e00a09df369d931b8379f84ef189d5ce4d9dcae6d15174c5cd413f2151f012d6b6a3cf9e63890137bde13569ae73f14ec5e223a2f86369302	228	\\x00000001000001007c199513323b92a73bdb9026cf6fb77efa4cf976f8f23c6f608df9bb700bcbe7e010057b268c2aec1735c2da974d22656c350e0ab21bc1ed42902e9f15aba6c32a8d83dc4deb0ed541ade428052cc58fb2bf0fbc396698adf420b0ec018134dab4980568dd9c465b16d4b9b0057ed7b44f3ae900ef8c6555e4ea63a6adfab864	\\xaa67e85a0c93d2dd5b5712c3e871feb99514914f96a0752286aa4ee0f9a5de35e29bcbb2a7f976a218d5dac506e82c30b7a482298d431945ce16100ed96455b6	\\x000000010000000155f345c5a2749ff451093e2d285a632ec1b95080622972aa5d98eb505a964c97b9e66caa8b0faf08d940ab267821224cab5317c401c2c4896fc7b85b318bbd84e8faf232ebc1266c982df1dffd72273889f6a9426ba41e75ea6eff84fd8db29704ceb71a56b2e5ef5a18e0a160b9e30007a71fa189fe2f94b2627ecdaf8f9930	\\x0000000100010000
10	1	9	\\x8437f8bb642ebb088c48dd9ddbd3efeddeb81d3a132c38051a4de6f7eb8896610a15a94cdcaa379e3df0c7c9e8530590bc7e6df8c4619e5091b31b116096c502	193	\\x00000001000001006fbffb85bf9da92c8698e3994cfb9bdb450371866821aa11f5972ed3579580683876126116d9eb613123871c7204b6d33e33837e376281f43b06ac2c93b88c3d9b0367157ad675688c832ba37f865dacf90f7bcb3e321e39ae6f57b458fe22599f078b279866ed5f054e95108111357b73108ca3e62f6426fc52a998c873f9e8	\\xb96c98d2d2b1ffb22f66b48e65ed357c17e313e33ac0e21bf90f9f18bfd9a1273a34d36c8dd0df0683d5c830604ad45fd11e17308de1b29a87cf884adf4f7456	\\x000000010000000117c4bbfd535268589d3cf98877c4b233a0c28677d2199e80d4bf605f912f4b7734412f3468985c3941f9bba419ff486858f10b8e69a4d451ba0e10e3b812105160094fc167aa1a26769fd79fdbfe3404754c587c2985a40f982bf6d502622b9b7e04dbbb30946525d3d5dd03dc3fbe4cb12ae5b09848201d1b5656778105cfc8	\\x0000000100010000
11	1	10	\\xf1c12764382cc1f273984f35e426d612c844ccc88387d8130d30b2e1b6565c247ee6cd650b672ade5e8afc2b7ae2d9c75e283e3d5401ab49f23b5897e040ab06	193	\\x00000001000001008e88539381e8d4d07765f8aa84ad36510570e33b42276604701e296e3c96c3bfdb55cfcfc97ae99877a952f831384452669406bd17c2b441004043f19fcc945c839682f6ec5b2f7cdb2309ee28abd9f9a5ff99615a6afc7c1aadc6a61fb66145441ec44f9869d340913f8ec94554f9e9bd342bf68a0eb498a45e6057e404cabf	\\x787d14ebc12b74d97cf929e1d27e038fc700c7c7ca3f1d26dfd05da0e8831ebd321306165d0fab9adf721f858ad1bb00185bffc88ec1d2f89fe3540dd0f63d19	\\x00000001000000011bbd00a0e30a0b6784fae4ad857d9d77bbfd4872d745d7c8a9c2517bb97360bfacdcf7e612824a856b31dee391ca2676e628f53cd51cf3456a3019bf635b23ea65343aa4fb560aad3e0473945482f77f02878ae8a90aeab80cbf387a139536d1109186255d5e1911e90bdaf06f14a0706218a4ae6a9db372d15391fa1c6a0da9	\\x0000000100010000
12	1	11	\\x5f677da19b9569addbc9e984c8c969fbc1ac51e6d87b59fcbe9dff7e9d981d2e91a4280f32fd3076fc1c6a398ef29ebef9e8b26a6f4ff3a68c9c71a8eb3ccb0f	193	\\x000000010000010021358f9ffbf6b34193c4bf17f2365e3a97b444cfe38e647aa4df0efd95e495c731dc589d625c3fa9952dd995b055ed7675708f2585daf16512bc60a8d36cd2e3c3eed66502c0fb4575f2b151b0497d70b6dd366f558077efd8f1b67eef46168824e401e1ffe5705e70a91fa25b97a5f7e21a47dc2fb8eb2eb9601882adfa2d4b	\\xb1cfcbeacb214a7a3cfc3ad14182d2cc9c3755d120dbb01d727a2cf0a3e413bd957d12f7b9826cf3abc0eacad75469c90b8bd6769cccfe21baef875d35fc4e75	\\x000000010000000169710a94aaf1881ded9c405143d7d0ebc7be76ef5ade7ee417295419b94cf50922cf9ebc272812fdd9f36a48077055e92ae55e2771221e53bfa16d79907962ccb1ecdae5d43edfbfe31cb1e7faaae50eb3bfea522fb2d16a371609e5ac891dddf18eba01fcadc2438f81e259435b97bb3093d3220c4d13c0aa073675db6ed22b	\\x0000000100010000
13	2	0	\\x7dd0b9c0452b13e2dfcde3ecf3f8ff50ef4f390df48d7a31037c3bce293f43acb567be09304409acce2f2102b8ff60758af70c27c622e5ccab90927bbce1ca0d	193	\\x000000010000010065b00082d0e32ceb9f7cbc29b6df3d188f7fd12d7f9e6be4cd0a748b203fddb4c8795dc0cb0db43d8c8ed764dd78ac211bd33d98f8b035fcacc51246c070e66264ccfe9ade60382819a325c42d6101fd61a157cef54aeaa338c4b89938eb883115fac140c6b7956c74b7c9728e9496c6c95897c8f758c6091750cda45d238f17	\\x4646049b74e6689337d192bd09567f29edfd4edc42f3cf2f865bda4dace3f11790893480458b868fdded6115879b1428d58cd9149dd1b09218559cd3a2e54f7f	\\x000000010000000191650a572269100e24f5ab4f9e6b6c709ea6acada72f8283ec4465cdd0f9ac3d2074c96cf6ff00b161ea0870d56b2b27a536fee64ef0c6c1db548aacb11f7d45037cbab82d566e71ecaff6b8114f08de6ba3e4cfaff7d261cd62f776cb98e8f3f605b734e737cc49c74129e4000707895f184a328a45921d0438b933ba616c3b	\\x0000000100010000
14	2	1	\\x1a350893bab0452e951c4862f5aa3a76a5e079c81937366a98f0056f4a902e6494ea8cb0f1628a3f4f16e9db89c6e03b1f25f3603c3f7833f19ea5d7f9ad910d	193	\\x0000000100000100524be79104fb3b5d1208d0b1e418d0822c83578c7233a4d4851a64d02b43ad9bb612f550f890aa6e1538842fc1a0201e8b3f729d779663c8e21af3450cf0ca8d987d6cf21b796d442bd8cc16b8c2bd5e1472fa10a773754f27b927c977fcd8921ec9c20d38684a069788a8e14e74d218a71a65f93ea4ff51d69e24f954d71f92	\\xa7d4ad7fef69ef766c899c22c8395e3a410f998e9caf4c4fb9791d05b19d327ac12c41f8eec35036bdd10273facd3baef9b36ecebd142e76cd2d04a387230e08	\\x00000001000000014af013d009ea4f622fd67adc1f0e4e6f050f3f7ffe4234f2fafb2e7c7940bfa88597a161b925324c4fcde4a3a7a7b8b5c9facc3e7fc3461b9693c40cd341a9106f73c70dce751a348f51aa93053201f87651a28bea26046ac0e072336215399f973362edf1942937ebddfd7ad0a0c871571a0eb0c92bf56c559df040e90c05cc	\\x0000000100010000
15	2	2	\\xe1cbab5c82b3a0fdd78302674ad972565bb10173fe71d2fc6b49391de521535512a72f66de509cf109c376bb9e78baacef7bae1dff5e1616a6deca584433a20d	193	\\x0000000100000100813bd7534b935e6ecd7666583aa73f29cd4824a371799b6b780a931c453b8645df0ebd0c675c20fa680a13edcf965c8dc3fd480cdfddd2714e47226fcb74f466d8e52d12a0caef2d63b5c2e6bda3f69f3f29464682a2fd332d56a89e8db89d4a21c67b7d724c967cafada6122847fec768304f123c63edf6794deb7f0eef4928	\\xc0a1da7c68e32d69202b6e2f8bc2c98f971f828ea2709bcf26cf2b8ac6e473d6a113bf137760aab57c1f60543929be176004555c809c43f4e27761839c71655f	\\x000000010000000106a3a716931d7548e04bba437bfd197de39db8bf92b1373f72aca93f16d4cb808fb6ef6ef0d449562662097381d518fe6ae749cc93d855a83dfe51d70ea62da71df33e65e24753a3a7e5679dcd83ea614c89bfe002e00ce6d34f1b975ea5f4d5f6f035214b363c6f0f8f83f122e7d916b208476c670fa6f070ae79f29b24f534	\\x0000000100010000
16	2	3	\\x28f8ab37e32b83a2d7a7b51ef6fb3e3d3ecce2fbd40fba9131f757e4056867b9dc5077e090584b2202b3f24714baa97bfa630f82ee2ce165797c067a3f2e0b01	193	\\x00000001000001000803590418bab2db14997afb43eccb2001f3ee4f6b3489b4cbbd5ae57f7fce6056fd76c8573480d8c3bf96578ee94de1ec417a85ab6efd03ba3d1324624731a78a1abbd3baf1735a5543aa95e4168da1b26dd001bf3f7ab32a837acb68c9212f468c97999042de833f63e2c5e9055e9247a266b23fad751e0939e044a4422ded	\\x350dc06501349dd93afee4386cff50bab1a2f367c2cb1bef0bb2aa7d3b813e4f570190fc64c45dc23e717e72e5760baf0059530c847496b1c39320b73ab54e66	\\x00000001000000011f11c108dc3c45defd358b97a8b08d0dacb61054cd86e244f464b23dbfb484cbd28a7cb075fa2752a514decd2de8f81ebfaac9ab3bd55cde12da6c00ee1b3305a1789d240bbde29eec5a5d0c46219c1b8897f42ef5eed1f51b95d2ca12affc8d52d450f7eb676d465b6552ccde1ac03b21529ab00f0a9ed6d2197b4a721e0b88	\\x0000000100010000
17	2	4	\\x2dab387837f43dd3fc6a4f84e53f846616c54da31120aac44fbb1dad4828d93b7ef3d30726d47e3b047eff6fa9884c54ec50d4eed81ca38a03477efb56442704	193	\\x00000001000001002afdc5f074e232d7fc1e90fdcc5a5526e31a4abb5f1a84def151178af285ea9bd05d4622d95e37d32f9fbea4bc9d85590adf8911ced13b693b109655d3d39717346c5fe1bd2e563b49456705017501f8b42350a5db0017d8800609d98b09fc4f61e15de2aa296c89f3bc0ca10d9768786016f575219db93690cbae7027e6e6ff	\\xf4574f52a817146a7743e3d1b4777cc4f8015241f67f918cb388c3825e928a7a81676930d19654c0360f72beabebb5bb2ee86d05c2f4ae4749d88776563d27a3	\\x000000010000000165a9c02a4409c446a006c48cd928f1f4c0c443c793d48e15c9204cb4b9988be5518f7a6b4dbdc71bcbf861b9d992e2c7b2cec55ddf1fe4b30f9f390f2b7fe6bc73772355508002c4e827c76b8706066bdfa68ec4be58b44b8cef5a42df45d1f9aab03c3400694f862fb4618d10178dc92e77ba1d9f680d5664de13cc842866f5	\\x0000000100010000
18	2	5	\\xd7ba624d04ddd3d80066bd96145fc3506f6aa0751053b28bd5fb70197133f611f406667b981e9426250ae82af96c3ee5101d2f5aa7aec50d82351c1c9901cb06	193	\\x00000001000001006a03db8d8dbddf42a5a02d1687cb9a3dd166507de70ede4ffcd63eda959b60b937a8a70cfd931755f750d2dec8faaf9a4ffcb25777a0c28801e339167c904d206f1d9d7ddb0fb8955203ecbfc459a0538a659e0921b65f07a363bb51026d37c47c5359f2007f23b08e98d7e00a75dc1a778b570491f762b7b28da7f1c657d0b4	\\x20d0b9d521235f128b9764bf072c88c5e05905cb4db7f76302ffd6d35d8af223e76d4697c06a54cac2320c0806d5772cd56926eed558be9157b7b103bd252467	\\x0000000100000001323c5010860365019a47d12459ef1303bfc65f12782a9eb3cc2e88e8ce3d6e6349baf11fc92e9052c53b323fdc6d72879fce8a83ffc6c64c9885b1e914aa5357d6dc7ef4c2aa4c522a847bd4c78e316067a7c2cfb2e7b41a48865528cec83545830511f979e412017c2c8b668981a75efc0c3f4ce9b03d6f511add7f03d19b11	\\x0000000100010000
19	2	6	\\xbc89055d431a5033d1da1d16eac3582a523d786c46ff904a2538747037241aa3b7ec3fc78e652d348c275d026f91abcf4bc1f467c0eb3565e475175c85686801	193	\\x0000000100000100790393b291a1f441730a7d113a9699e5bee1796840f64a66e667f52800d6489e4612446bf896b7f5d3fce038794564ce8d1250540a4e15da5d652429a841942e734a962ff62d569c51a6ef9904dc30bbae16532c6eb0ae0249e115c45463b029dddb6f89df3bd44c8fb697e612f1ab97a37d71daf64f132c299c75815de7fcd3	\\x385e80a528dd40c138a95c0575fae0c467e1a86c626d8fe0aa77ff881af255f7b9e13a7f25e9539035d3544dd57c3a7b12311df79f3e859f726f3e82dd7b8191	\\x00000001000000015bc0116c13ec60bb1d4a9926ebba85aa8c804701b824be4cf8d7779e1349b462fe9e0ae0f802a2788a01b93abd990567f85b766315926de1a5db70f809d5bc6b31fccf90119b742c50dd06554127f76d210f5136f98a9a18ebbcf231c7fc8bc6577692da1c9c50c2ebdbead6452d0d91d4b6e01eeed1be66ea434bd4672428a7	\\x0000000100010000
20	2	7	\\x29499a821230091bc189e5c45a1c7f4f7882948975a6c29e06b487ab8d2bb8b22878c3aae7fba749f1c07837ea0aebbe700c31a6fbf156884d13055ad8fa350d	193	\\x00000001000001008f288bb298e08b67c6f022000c90b519250c7cc4e53a3aabb896600622dbbea368035ff892d6bdffaa5b395de5447a308264aafdc2005d0569f930e39f5138d78afe40d95e8d90f6299c64270ea4f746fab3489a7950e4fd7574e857318338813d710c2d3e5d0f333b910dce6312b754cb0842a401be0516d413a76547aaf4ca	\\x7829d664f38f14911d2b2e0385519e113a7b4668a9957db4a4de3ceec497b9c41773903d3eaac7caeed3d3a66c327e138b997cec4ceef2635877a7f9da4ea7c2	\\x000000010000000112dccb323fc40a66d6813966099dece4d544fb758076ec6093ba5677baab1a1ba4631e31f7ea984286d19de5c9a71f8f89900b0301257180c95ecbf3fdcc336bac464373f7634ab2467777683b33f2e79f74e418e02a7c3eff41cdbb54ae563dfe2669599d4be7a30df184ac95b27a955afa7d6f3d943e9250e5d4f9cf1b0b01	\\x0000000100010000
21	2	8	\\x02341758cb977d693aed94098594ecae7c511f909651bbd865b2b4c6ea4f8f86f171f67d20f85039088f20e0bc742b228a958d90d3bccaafc660a084e8813e01	193	\\x00000001000001000687b7d552edca13be96e2cdbbcd525048e46a063c1d948a7cd37b8d0700cae73d0630eda6125966c1ce1577581f4f63015c7bf73adbe493581049004a10a23666ba593409c76f389d5843b49ca643acbe4540d1aac2248bb164ae5b6b3c0647126a48e938e2385bee2762c45fb19dd13c17aa2e523cf1b7c3688b1445636a2d	\\x6bf9537d76622d5c2d837f72002bd80bcb818dbf153c8eb31dfecde284496ec8d2a97eec852f1960a578ed9feab9f264496ba7f9e8ac57896f3017e7c722e0bf	\\x00000001000000012d7a8c4427b858a8fec015e9cbc80e2e79539bf504ae415e4d3ba128717d8aa28bd67c13dcfd951b5a8ed6f8bb9fae56eeae631733817417c93ef22ddde6fbbfc19adee84395a3b8baa14af2c59e3f945bf7050bcfb779d68fbf3bc10d556fa2981b40323680d4570cccaab77d5a0ba953131e1648cbc978b5346bf034ef12ef	\\x0000000100010000
22	2	9	\\x9a3413a3ffdafe35916bf0066d3a6b5d39e56b6725c5dbf1099168371f4a17f43846babdca86a4822816d64491a7124c60c92089b3019f2b18248fb91ea81202	193	\\x0000000100000100651c8fac01ac5cf9c6bd41e5ebd480de8b673f70c535b1febe848c8c3de290babb99b678c96cc671c5a4ca3e463c6641a619a32a18511adda5e80953d5881287c1fc3e767c7177c7f463071561398fe83605cfa55ea790ef47fe7f2fea73296b1c1c984510e547a9ca5dc2acc838d91432314ff29ef0371977d057350d34031e	\\x689f0bc058fe521961a6ded930dd34f948ef2e9331ee58deddecb97e0d6368219eaa98674d00d0ea7e7b0b8e2cb446ff5c6756bba7a0ccd9bc4bc5ea4e53a03f	\\x00000001000000010e9037be5839ca75b461f259bcddab067b7a95fddb7b51ec9c6ed272f1f1911c925d8598a24d0918d7d19b11ab70785c868932bfba6c0e329eadcff431e3844af16849da93fcdcfe6f40ac903f1999a9796b1b16c04df8b50818f6445847d93783d296b8f92b8f2f4ad69d0aadc2199743ab2db1c21f544c0b4e634469b9bc9e	\\x0000000100010000
23	2	10	\\xe959f3fcf396970b35cbd3b0e92c705a942a91575bf0cf01804a4b3a9568ce69cd09b0d0870feae008e3ac53a76f3aeae04eebca531145b2d6c140bfab7d940d	193	\\x00000001000001003f521a3b369f84f699f281ecbb53f5e33b4a9f4202f01852b7b32e556c45b58506eb7b309e53607dd6afd0c26b15cb0840f65e8f178105cfb8946f7c2b6b740ee1802323eef9be50bb0294f2c5cdd14646b87669a27f1af7020573943a0b3d7afd4746787b2b965ccd4be5fd8c446e949612472a8fec6784cadaacec9150a2b5	\\xd65cecf58fba700275b50d89d2105862da6332c25b3fa32460139e9f97cd39a0bd8a5fa0b4fdc7a5edbef99950e4e376905cdc5a89e7d451b958d660a1391cdb	\\x00000001000000018b82845eea1e24319051f868bb3c96c855083ab9cf64d758dc2e9e25e23c505b3afc91516579f80fabb7cb3b0a4bbf0cd3f83666cda2349f999cf202ce5e09b57b87137b4ceedbade13e1cb12abb54e1eb2b6c58fc2f8e4400ba1387c37f4971819d7535cc080efe2835f5e1ee64a600cc22870ad0dd920cf77608bb21382652	\\x0000000100010000
24	2	11	\\xf17eb238a32a078e26ff2d6ada340994f10011cad1573b12e2dad5dc504e2b9a30e2f57628e2c505f29f0e89a474437ad452e9276b12237d7a56b2d8cc554e00	193	\\x000000010000010011294f73e40f18fbd3dba37129a593f94506520fea96c664c4429076ba479f1cf13bb78896ee28f51caac3a88bb5bfee923b75716243879d2f04364e09de1b1da25841d4bc9b0d25551383dce3b5fa88de4642e16ac3b289e974fd60754a7c707fb21812e0af63ba6cda282b79acc35b40720f62f5be30339bdaf4ee86c7c1be	\\x37c0bc6efe52207b38e5fb386c426dd8b2fc261794c2b73035591bf7f0404f2e46d059d8e900a288d37296c71fa6babed02fb9fd1af39aa33f38e8ca43408377	\\x00000001000000013c8b5f5b0bcf9b6a8894a3f3845080af1c34a038fd1e23027d2182b950d00fda8520a26339d74cf00654ef90a794169f3ad2d7fe144a180766a8f4626d7a4bec48b2b7f6585ab81c397a9a9769ef95ccd76cee558dfed543c41ca0ec08d90b495956cdc435f00bf74a396a5f28bee59959d046f2adab1c4dd51d33a5d39d643c	\\x0000000100010000
25	2	12	\\xada71c5ac36257b1c34321eacbe28c85a9359a95c900dde6854ca2679113e58ad58a8df9faa6d6b1bca9e3881271bb9ce27558f326404e9a759bf00d97fb980b	193	\\x0000000100000100181b696f37f622abf80b7b158d4d9b7b36f2fc2b7e0f6be0f3422d37316be28366c0d50b36559d04bdce152b938bbcaa10662a776cae47d4662d8e62206d62276f88b701a1c32178cf53713f02db219e8b573fc28cd039c32f5a707274dfe2bd62613f5e95109e5484008143de311e7ce59e02bf9d1c65a948b2ba4fc2ce64f8	\\x5b57a545c437b6f88484f288875e5a45f79e27d6d0743fb849a7855840b1416b252ec87385d6173c243bae7edaccf48d007793ab873c6b99912296385c7e18ee	\\x00000001000000016c87791ee16784d3698070096244688f37e91bb6ae7f9376ecebe43fb8e201f46701ee6964ca9125cb5884d95f259d8af301c3b8fd1dcfd77a771fc0b5c83a86321222550ccbb59c62a1e2c9d57975de35dc2d991b050fab95b7d3d5ccb59893b1ccee16559361c798932dc85dca47b9e49353890e8c1ca42444ec2fed86a3fc	\\x0000000100010000
26	2	13	\\x1957924af2fce317653269df5f00dc329d513d612a88246f13f21bad87d84768e40d8f2f2146c4cc06be2c6cf59671899fa00b3fd9f031a698a192ebeabd8e03	193	\\x000000010000010028a59546fcace3d707f9ee634cc0316a16272d53cdfd8fc95a07b63fd0d2d75b6432c4150ee70a57bcd343c732f974d494c444f7bfb389facf7dfb57b6993f38c1870ad362ff38033ee7d2c4daf6808fba600ea82184467c23132b0c58bad267723f338b3993c9e3c32d0d90db88a8790a78114d91f4648835e1f50de644f16e	\\x99f0077bdd79a17fa8bf3c30bedbff5ae1b13b6ceaa144f57650eee9618a34990f9a35a03584b98ea9058cdf86fcd75d61455bf882e9c63ebd3d18978c9ae2f8	\\x00000001000000015af4652d87de3b795e1608eac36bf70bc0208378f216a9a65c377357002f922598cc68eb0ab27cbde44ec356c88bfe87ad84c91c802c7879adfaef10baa3982ac7236b4892329c529070110d4ffd74e148b0980da0600a46e1d67b82aaccc5446ad5aafdb02facb8709bcec2a5010a6ddb40b39c196e54dc3f013a1529664a81	\\x0000000100010000
27	2	14	\\x64c319f655660503074ab2388492c57920ee5e3ddd9d2f951e1b68bbd740b1f4178665762d8420168facfc93c257567882ab12c3cd8b563d60add6272a49ea09	193	\\x00000001000001006e8e496a84921861fa5a93a646d6fa5ccab521fda67856c93936c32dcc7744b76ceba00ddd94792bc1afb37bf2a2c7e4fef6502f370d0e819b15c289d367027648cd2dd776799068092f74733a39acc18809eff743173a6adec62ccc1be7b603714e3be5877fff7256748c3485ac1f70be28972134805c14ee676b55002aef90	\\x045dc24f5337749c3a2df36a5dedbe446d718174cabf452e2467d9ce9644d33133a5a116ce813b7f87a2911582e72e8991a09c78167a7cf5969607275b93a3fa	\\x00000001000000017351617fa1d63f07538792dd1524cb6042bf9260f0a1e04566d3a84d47705ae979186b34ea197a10ccf151934c40fdfa86d2e628c29416f9259c2914c6424e1ca5b6e6b138474875cdc5d83593d91717a1eac91a33a47df2096bf2197641f69ef049c81b5c4fb53d3c7d7e8e92198b5449aa453abefc3410cf6685c9d769c9f3	\\x0000000100010000
28	2	15	\\xf7dbbe1b3c4d6b5ad973f8ca834adf5bc2f073f9f4985858cfc251855caaf1b430c416f536d0c985ea1fdc2ae26089212072952de026515f928a2a0a9903ff06	193	\\x0000000100000100869fb3c02d54795e98d108de5e662bbc88eb714970fbf60f847028fdebf969b45eea4cc3610bd2a62b27754463c1e6b7c81ced406ff9b5d58555dc61e64852ee2c7b1beff28264399d6a4c6e1d75cd96ef64daf9619bf61c9897451a90bd64c759377278dca0a63f7f3eab2552da331299eb86c7d3bf93398f15ce9a545ba7a4	\\x77e0ce1e3e9673f439abd53a4f1dd624ab71368f87bfa56475655c55d7ef9c450a9e1df391801da07c4a8b114685d8bf4043e91f0a8281c6fa4333433ab000f0	\\x00000001000000010824de93c6b169ceb6fecd52f24923b884f70c662363af91e0aeef87d0698b78c67a0c2c707e375a38c65136833e0d9f9492696b29cfc9b9cad227e661f18469a65b94fc409b5349cd23784485abdebab80d89c74fbb7d5a920afaca1066f9466583905560803963b1b48425c676b28058c728c546356c408dfc7a68e18ad6b9	\\x0000000100010000
29	2	16	\\xb4029da544edef50015d0ef65e4dad6ddab4ee5ab4d951ff83583ad6be2b16e8bd7f94d81c1f814909f7621342ff2656eb5bb89a60ad0bbd55d31d187a12270a	193	\\x00000001000001002664ada183230dbd556df4315dab00ee3ec6a9515409ebcd679a884bead0891dc62dacc776fb11c6a7bd725375c3de6f60601f6ba2b3700f8bd19404422ceb685c7008dc04cc2dd80bfc48a2d3f1d64449e17b2115dd0f5b53fd28bc481a122e8f53e7fcf0a1375a6a18a6ef86400567e3eec0dd56843eab85f3ee65b856719b	\\x4c7eea31119110479d9117495566a382c23879c739b04e1eb405ef1b35535b6aa96d0f6ae80100bd873cca711b66efe90717e70bd41a97d6fcc3d0f6e6c31cbe	\\x0000000100000001432ae001408cc190713c19c5e1fe48f7809741d4e0405da83eb12a4b90809a6655ae193eda0d2bfb83f14103c2b91c1d58dbb3d07b5a82b08d9215b32b817bbaa7f51a0f666ee6a4a4b0783acec6a29d13b98294f0deccc5a5883789534ba1260b0ccdbeebf8a97bbf53c537e0cb17c0481f9c2d6b7cf92528215ec1dd04cc5d	\\x0000000100010000
30	2	17	\\x50b052d95f556d228ffcb2ccd1176108e2ac32cd3cfd6c7824fa02c8a75279e54ba4abbface53a4aa0ab7f5d4f19562b05ef359e80635a6b54aff4a4dd71a00c	193	\\x0000000100000100886d3bea7dc9be82de68707b6c0ad603eefad944a357fa2ebbf3f2a38e8761dcaeb9d68c6f77dcdb8ebfc22ea1cb52c61b07a483f0c745a5cb29c6daf457c6453cfb4411dc751242b38b88b8985c1d27fc2717e707b79fe7dd8908ae7fc5263d939766ba96e79e4817b2f5dae5f459350f65af83c5b3c107861d60693690d659	\\xd94390347ef4ba4f72199aad4967d8721f3f6ca5438713c696c667d44738758784c1b1604107b33703fc4d5a770722c008f2c1ab0bad6a14956abf66a9967eb8	\\x000000010000000145223d93051603a6e9cdc7dd4ddd25753203c6fb597535d62589875ace72cfc99d3dcdbffe6146aa9acbf60cac01b33388d0a88f7af0d27de670de4184c40c46cf09f85c51564b9609aaea1562b8cce5292b77b69f8aaa3cd76b0a2b313536d0e92b002da5a297562bb4ab49444ac58e6be21582d57897d97a1716352d175cc6	\\x0000000100010000
31	2	18	\\xa53c8158d5d5c11745b034d7400f44da4420cb84dc4d2569d9f16823ced4b120be87dd989e0924ab7718e98ca1079ca69cf4f697b0404f2f0b7a14bab63f6103	193	\\x0000000100000100859d0c5cf2171f7fbd0f858d9979c15b4a2db3dbfe5ef55175c308d041cccfc3cc22033d028ed6a0210dfd750c58e12a3cf10774e5d8fde9d9eb2233750ff5c89eafa78cf6a9d0e62d1f33e8046d017eb92585b3338664d8cfad80dc6b86ce5d4b9f4954e987ce8cb7c3ab54f013047990549c113416553e6abfa9d719ff5abf	\\x963dc532f7237b0df22a92099ed72e23ae5ff3580a4a92e017a0abc8ed30104b56dda9a4bb05b00ad896a735d736fc79dab7ebd7900bdac911830f10c4f79f10	\\x00000001000000013739f7d02e71e1040ec40cec6da6401a2b5d0b8d9720ad010dc1357d0d3df1b9de23c39845303501fd1bf021cbb9ff9d6516770552fc5ce0567f4f444fa238134de0bcb2ebf12f36cd595339928302355e9d68e7a2bac02b78b6d4ad80ed3859db548a4592310a4d653532eed23500cecc5a3adfc8c5341e8a133a67f0015c66	\\x0000000100010000
32	2	19	\\x16f4bc3acda90c50f93fd2ceef15c0f943564292e1890a51853069f309785538a8d0e827da92671d6c711186574ac5f4f9ef3150c61c73fdc77ba1e6237a3d04	193	\\x00000001000001001ef9d17d60c1da738f7284332ad533e1b4cb70f5c26a816b3eeadf63a40d3d316f1eb382e8995f3e22a250fccd68c64055505470ecc4fd0566a5129703f4cd2b04d8a5e5d8080481fbb97cf67cead478986a55a477d7e981f44213c6e161a95f4fb82854fd1920465a97bedc165475d06ea6ca7528b95e490f4cb5f22d45080a	\\xf1f9e5a579dfb434b8c1c2e62c959edbfbff3da1265cc2026211a4b9ba1f39b0f7a7bb1d0d36b343e574177dd1b8e5a5d982355c6c30eef3dd83ee138255b115	\\x0000000100000001120c1b868e28b5df6f3d5a0431ff54b54d766bada9fd4b04ac63d8dde1b0c621fe50aa27ff8d52deb90fc62ccf5790722095a4020793a8f50af330b1bff06de7b8e5289fea33ff0ff83056a88e354c058129a333a473f73b74f068e6ce57aba96c422689825710b67ca52fdc17523586b3577548e470ef49f0bb1f9a982fab8c	\\x0000000100010000
33	2	20	\\xa74ec6bf072dde82abb1efc1c54a60a3d7501e5ad424a31bce0937d12da550949cb13f53419b1d6851d8c66b7793f39f1c12849d780f1d2f95994f202a956505	193	\\x00000001000001003ca71efe805c5ffb2c9ce33f3424259e2f04db4c4a67bb76cfc4486833067785bae9aa000cfb3c7c48ca256bd15511384cb2ce6bb5472860199a25037d2a2760d89d3f9fd8348da5aefe0edacd77604ca12ec29c303d9bb5ceadc4fe7d0b23ccb25c2033066ad10c3ed26a4c2d528bf1fbdfaaf6df0bb33d0726162382b40b1f	\\xc08a986964a8985943ae987ef8a61bd60b1f2adea89336cb7d3c020d03897a60e68283603e959dc99b873ccdb9eb70497b0fd0d249f36d633390d51d9a0340a5	\\x000000010000000171fb9ef9871b09cca03640063402a1b5d1f2450326247410f4ee3b6a64aed0aa0de3d85153d49f404e61e7560089a51ee4c1ad45294d22ab4e78fb3fa02dd1ed6ad27faf110bef09fa84d2edf6ece544d16ea7416091af1737e498d721d6c68bc9ccc330a45d0f9a00bb5f7191d0893976da87ac181034f29a1a14521afe46db	\\x0000000100010000
34	2	21	\\x27a1014cf7c26e2fabe33af852248fbba85da613b6f797522e10abb8070492c96d11216018c2437c371ad1f0afb4586588c98651725c7b245faea39b022d2709	193	\\x000000010000010020abd5dc5b4a13951407817fef3d3beb1518f7e99422ee91c97d788192bd9d4f31ad80b7a754c0c957e3d11151755b3a0ae6aaac0ea85eeb1db27d28338d2f0dc6e58822b5bc830456ce069910e3834efc0b7d950f6875f1b1d69fac727fe3885e6dea84ab8f4d9e5ac1cc26b3b8f5da07663e5099c1ee3d52cd6f8ae579473b	\\xbc504f3443c65623480406ab9c5c83ed299825227b1c7a1bb97d9765740733ef1d2a15190c29eae886e5716c07c32701795fa426f0b0c5801eb3c1e2e283cfdc	\\x0000000100000001709d85906140bece9a22b71a896b4da2e639095d67a3063837625406a5cacb653c7835bcfe5b48b874cb3151b5d904914c324f2876e54fbe27e1e378e08e7f886f918fbf66f02ad19fff954892078b8b7f2ab557eb38fdd110ce28dec3814763728f71ca088d8d388611445233e9b803d228fc3a19fa22cb0178cbb514fe1204	\\x0000000100010000
35	2	22	\\x3770d63d879aff91fe17ffbd4f79487ac875f1b1f755a43631168fbfa5181b139cb35ff313983a0158a8cc2814e5e3181b325ec18678bc9d81b76d0c6a14d301	193	\\x0000000100000100386d534321d39891f0cbb6cc8dc9520ffb168fdab0696fd618ef08c21d10ef2fc01f2a6ff6f3d2777aea40689d44af7a58bdd9907c6d4bda8228a76209ae06b6f2b381d3c8c024b7d92c8e21ba3306779f7eea1239cea8e560303abb6298b0259f978799947c6ed631dfb36d7f836aca36427b4c9652ee84f7e1085b40e3cad5	\\xba9452b2f59f7b31af7c2ae3d8e550a696c0f7a1f4067f8e06b2d4b1e94c126e148d5ed3a0b762024e7e13ff34c29389584588c1d57df768d94daf851bb0615e	\\x0000000100000001739dc484cd73bfcec9e5a208f23020d9f7e5830e3051cff8f8602ae67960de73094eabf124b0995c0f8f1e5fbc7fada679dc3f15597d53344bf8b8489bbb884a394be7d74fc939d3f2dca8a127bfe9221e02a463385bdc6346cd68e54595c710fecf39303ff7f968ff2c5afc5457205fef3639df8064bb2d5aff3a89cedcfa39	\\x0000000100010000
36	2	23	\\xf3c52140fc7e71aefc902849888120867a081f157909349b250f7dc1c8cc434ab94172a584e180b2d4a07c01b1e2b06aad0a1fd4f3e40a161d758d922867050b	193	\\x00000001000001003c3b1835ab22e133430d373f0fe2b2f8f1eacbcc154163f8dc0e52700416ab8d5428fe9b1a63cbd24c9bac04fda2c4b3d769b5396ee3c25be92f598cd5fe619f9c746d504b3521f24830f0d3f410b9981da1c62c58ede3441b11bd6106b300810ef72bd7c22eaac845a93f0d0b9fe60a4032c3f8b690119e2cface51ca363dcd	\\x0782863a93e5afc8db33ed45f8dd3ca73ddcecb4e7a6a07d4d0beda5bfa67f2e0b29ecfb3afd49ccbd7bfeb12813aa5b24fab644bd85d2a85b78755ebc9a16b9	\\x000000010000000171d37b556200f615a3c1e8459a85f18b2b0c2b977b306f24b6b2f55809fce6748ad951323d3c395da8fbf8b200f629f992426e71f7d4f5073db9c74da9e259f3e3e22919177ce91dfcada4581885b07881057ae7832e80eab33571f56a2e967258ad3c7e0286e1ca9ab0a7e5055d2f2ab9081769f3e873c3770f2f88a1bac970	\\x0000000100010000
37	2	24	\\x7711b601b4d478c0fe47afa44c589f91370b4c78b4bcf44718a7b95c0c9d1d64854f6638beecd8a99ef543a6f31b27ec41f0573536e84496726730f9bdf88a02	193	\\x00000001000001001d095ac651c8016c4a03a012ee63fd533c67e8beecef00d4970cdf53a41fc731bda7e78d8f83b9379e888d3b1c06ca8edc0dd9ca45dafc278ee0e9353f2e39797d6ba0620e434249f802817a97ed1729bcf4bd2dbb65888e8e7538886f8d105856a80006a8c55b6d25ef22eb4bf159f27ab8cfea2f02a0f8bf4d331e21177a20	\\xa90c991d63ae7858c24413bf71afb7844913f6aba9d8848664bd3e9c5b13b7680cc30bc32bef65d782ae4b97acfda9e76add075f3033de03dadefcda2f26cc95	\\x00000001000000014c1fc00f3cb97c69754db7b3e45b93d9455a074adb607a7b45cf692245eb64be1831701bed7b573a974fc4c616a84b061de1ed9c0e48e03004f669a6732960830df0ce1a7dd304918378ef5195335b41e75c501430b4c091ced64285acbf5505fc70202c5fe4eed3179b07d6d5b71437ead528c5f65747e4a0cf2711f42c2e3d	\\x0000000100010000
38	2	25	\\x961aedff0d927d5e59284043c5fc5acbdbd18fe2b14ce415ff0658ae696d233d68e1dcbb0c49e2254fb787a3f2a2dc9fcc192b43c66af899b9f46ef54eb26f0d	193	\\x0000000100000100305534ec9e4cc070cd5face7ad7b569c3519ffbc5baa933ba9704c97c10b837845748c4203c97d284ed575abc2bec693d2ba300ae004c0bb5156e5caf8b5d6b12eda602eb141858c2dfd739f1e6545292b8a5303b372d38e5c7c919a747e8f5b674fa0a2535c7518d2efb55ee7e7ec628034b5461d78896dfed12e7c275c8b2d	\\x852e7c13f3f80dbc5e0cd648b7be2881394949d86d8c11d8d4f45ce4176c50acf97cd4153481479d53e2b155752bfe15ef7753ebd5435e8d7d5704f62ab1225b	\\x000000010000000163e0a5c1daf533c2f6d4120bc24c7e445a1687e83ae4f96889c90c272f8791fd179fbab4649d7e573bc6c412028ee674dde991be56abe66de523c4984396b433f0ca369059b112da5b450bcd3039a503bfa40ce76f09ebda60755f1c64a5e03b52927c909177f92c4dfd9f99815eb181ce9482f5d23871fc51eec253b7045096	\\x0000000100010000
39	2	26	\\xe14b76fd6da69a8036a2eb8885c931720a0fa929f6e0117aa08ba41406a0dff6e72ab326e0c6611781b4ae7a31de860384bdfddece576f6e1def4fa0baec8109	193	\\x00000001000001005e0aad7f63a33ec1fa6233c9f8b1536a87bae787b6e97fbb3a5ea77167918df6ad252345f2eab9776836016ca4683151146796d0ff094c2b98193be48d9684e612e15c50cd73519413cf85e15f10e62cdf32e62e9fb979af67c965f766241f9f3c7dbdd48984161f257015cb3e89253d06f4ef9cc9fbcef56c42955b45f5d98d	\\xebd7a0a57920d7597bc18268015334c1b07e88f3c567998425dc87219dee34dc8c88d72982f9613e7381384c3f71af025fa1b85f390906a7c879af54bbb6dbe4	\\x000000010000000109a9245731fd25b24031a818f66339a787b95de1f2b888bba685d42d92cd824db3260109d63d9068b18a7be207b93ce87c292de2b7dfc1efb96ac131c6017ce09f8ff4c12116d52d0d61c622ed1701ed15e104a18c529b9f652775daff6ef454aede309867c75625caf8885f5dc3886dd455e11c275e5d498644e003761a78c0	\\x0000000100010000
40	2	27	\\x02fab3166d7347342db6162aab11b9cc969a5d25aff741a0badc59487c44b315b848db145eaa2b389e4c14b27b0376710ea4e6846441ae073da5d08513dc6f0a	193	\\x00000001000001001d22a6c7cfe1ce3ca00ff246daede623f00e87ab9b1a50cfc56c386253691a8757f6e719cc5ddd1c4f696c70e8f67c2268797ce35df535fe256265f0a5886a8b84f6d1e521b7167d7c3b18ed55bc7277324c4f73d2afc444a1c44c9c048829913486364ee4f12d89122215695356eaa3cc81d6bdcfb3ff243a075eb33c5e11f1	\\x2c056a7fece6a291b6f60a121057eb8770c1d6b8721e2f2c8de05b00f02a3ffd97657ef4e6354c7df9c5418f8b5a465feec332e1cedff40c59bfc93384d1bce2	\\x00000001000000015978697139b9e71a86f910bfa5176b03232ad5594cf473697e773f281803a1b77a5f58f352be57649cbcbd6243606b1514284a1de94a125d7660055337936b988c78592d1ad67888d5fc372576e256762271c69818b8a552552a6b3cc034b5beb414a1b1a900d5150c3d1a22494b36ab8c416aa959a69c38b3366329e760d7ca	\\x0000000100010000
41	2	28	\\x82d5a47527253abf019033a3c9858ea5a772f786c0612440d2085a5177accee835ff34f67a87d20569f9ab11fd5302c1c9a2589f0b9d822e7b177abeabdb7a0d	193	\\x000000010000010082a21f6511308aa6d18a12eca761d53bfd44e0c7c33201313a51ded97bfda5f0f7d71331ba0d6d11da75710331f87fe1a48c33c9450f58e02a3ecebec1d562a2cd4ce972792a2c970a8f0aced72049b774f51c82abb3e6249a0da7d288d2accd8b8171a09eadb3b30613234eefe0f5bee8dd376ca5df8a528925ed7a2de6fd38	\\xfd2ef57b530b59bb9db3a67f342a12f2b4553acc9a220e969d5a656fd25501ad48c9aac6769e4c8ab64cb16acbdc4748587cf7349f36c1f09c1da184d81c9de5	\\x0000000100000001068272d5a32a218fa6cb4ed55d693fa97724f5d210101700ed27bd08dc8f482d6be2bdafc787d165d229b40ea11dc1c11a83f0480a6e822c432ad02a269ea7b4fac3d5713cc42fc241058714ecfabc376c3932ea278e8f93ff7cac7e2bc81ad00796e8bf20205dfd2cc4e313ae188d996b0de0a689180247261325980d019e04	\\x0000000100010000
42	2	29	\\x1bf7fabc5e6ad35c201969f0361b28cd699ff7475f9d88c81aea347c47e581cb3fafce4c9e26991902e1fe9599aeebbb31642c551be9209cb03015ca34eb6501	193	\\x00000001000001007d4fc1c2a52987279c6e7ea0b6c2418456575d0ae90299a5f1f3ae297b3159913c9ccc3f84913447fd4bc2a9079fde9bd76d1b4a8cd6b3b879445c90c22f6a3cb0ca69ba2eef14ab8644bef3a0a6a37c2bdee3e580797c2d7c944d6c5c050f494da6d4a6ab1249422db7e24338e2fecdc37add60913729a17573e7bf24d6eaad	\\x354acb980fe554f40233c7e86bdda6e8e8fdce6926e0fb96ff8a4937a6241d9d2f1c08e0ae1eb3b0ea99274741689f9d24151614f8aec89a3bf74b0dc75f642d	\\x000000010000000130578d7c039e39c3d80de7abefda20d375a77906c1a7ae1342a678f3d462bf7a511a6e1aa6d026a6587361234e18c1c9d2d37c3b0514d81af8aeaf6313ec1c26c7ae0b663c109e0ff1d45835d242c905098656632ce73a240134f2c8a9d48e4b62eb2258bbf235a9aca40a8b459ccc2d701d2c65d819bcb92818f933b5791b86	\\x0000000100010000
43	2	30	\\xcc036535309dc8e2a91ecf05cf86c0ff0f3d0e0fcfc7a0b22c8eb28cb5e03a540eb55eff8fbe376b665e5774bf720c30f29ce55d4259b33d74f0bccba99af30b	193	\\x00000001000001008b8f77b0f9ba55fe463a93ed408d4716184021bf1edbfe0f6b966a88b008a8deab619f8de16701e2c2d6ce0af9b65e7a9aa1c87d4f804d92bd05c3c16e3c94e4ba63fa9626afb3df6ea2f50e70e443e1abcd14a5f669fc482d791fa72dc5ea08758aa509307917d0fa5651335ae5f652325c4105afb9fc8c0911c9b5b9e3b175	\\x2d35c5a410989beecd749ad9e3450d86c9a562cc381dd7ab8cf44a4e6f3757d230b74e383da7079d85c5017a617dde13ede5f89de3331c8d741910b06e88817f	\\x0000000100000001258d6b6c38a5c5c049760c706b5e3cb2afebd87144a9a6685070edacc1b6885d4179d3696f96804f00f8b56ae9270bf5aab650c5287de41b97f0354b9ec6e3c228c44aff06815a21fcd1103e6eb7167befef7e339e1b8cae6cbcec47afa4d324adaf530bfa92dc7084875687f2365669f5d0344d6e2d619308d2690ff5226b33	\\x0000000100010000
44	2	31	\\x112ff1f7a2bc83e5f3e375a2864fa2d9aec851bfdd5430af5d187e2b20f5b14a56074b970ebbb68676dfcf9bfd2fb3bf5c770374a69b19825c8585fa8734db07	193	\\x00000001000001001bf265fb74eec598cc897c331ebbeff23dde1e1cb1098205eaa480f892a12d4eb6ea6afbdfe38620bcf09b05f432934e418c069f22e8b4296c1df5157d9d13a6cb45d8da9143540446b46a4d547c88328650aee5be03e5e3b52a021d67127874622059a117fd847ac9364b738110319caf7dee61a46a4e2eec62fc47b4dbbdef	\\xed11df4d684dc8484fe5e66e85234560719aa6982237cf55474ef787bf208fc4e08b61ea2b8c0a7bc38cf727730bffa91e6abc993618cf8ebce4ffabcdceee25	\\x00000001000000011f412ec88eeee6fcffb428f507bce0194e514bc43d0d6908537597f3d9549dc181ca29c52a203d1c6ea7a448aa0a017afb5ce23038f2486dcf4fcde4fb28b6eb8811f45d882c224f992f8c5e0c667874afad1810745bd7952b29ce0abb3cd31c15f4ab1623b4c746b855edfe9e9b6325b8ce486df537d646c97af7ded17381c5	\\x0000000100010000
45	2	32	\\x8d6e8886940733ce9ff3cefaf4a971d59294fea57d91bf4df9f1313b9aff51bb55880411a742b521d797c2727c60aa34fa48334a27641128734b02cdb250a702	193	\\x00000001000001004d94672334fcf26fed05af12e5b78b3de8a4aebc3ef8285556c0899400a42443d34529e6c2d94a6099993647b65c7ab10eadf79fa61fc08a43d326e844d5fef7d26d770919fd587ee4ae078282bff5216fa446cbd3a225b607a46735e787b665c35d20157227e57e64db1761960af0ab17d20f5fe7a285f32763cef595e7ab5e	\\xcabeea29a25c1e817714f8ef8e538cc1f8d3a89829d6e6986acb166dde8dd67880edf25efd214458bdc9c945284ae22f95ef811689a610fe71b5e07e2905a9d9	\\x00000001000000012864b38c972855000e849ffcbe60d7052b17ef9d3864de6219765f8753894740af35ce63fe034d957ed659b7aab7f4106044ddb6285ec29c82136b4d1e3c9bfd1854439f922632cb9f4b4fbc9adcd8cea017f53c00987cd1486aebe921883ff36e0c7d99b67cf0bedcf023fe247b82a0504493ad50702281bbfa666cd91ad5a3	\\x0000000100010000
46	2	33	\\x8ed5a057bb9b24d92ae2deb6927c9cc2243af008088489517ca9eafe96d7acedafab0d8f4996730da0ff6b21fdd9f85c6ecfac1e6551314a0d0ff1262188cc04	193	\\x000000010000010082d357be44c053b5fedd6a37df0dd77076e3c8b9f4255eb54ade53b0671935c0f4d38bc0919d9bdafa0e7a75903376faca7feb4beb18b7099a5cd34fd31be984df780cb4e99722cdf945d454c67a814e3dfdc334b881f7201df9f064253d8572f374cdb51082fcee59812d5d4e8b13575d1d2b748089315acdc334abf68c11ed	\\x00ee3dc5dd84948b74b7994fc273c3c11ec4ba5ae517e8c34a6ce7be0680308ed2402ea5c178c9f10cd00cf138fc632a362a33a305f9b73f1c6dcf4a7139a18e	\\x00000001000000017120c437a092dc3d01138665b527a6ade27a409596b882b6f7060b14943f2de2ef68c644800086114056719f8429769cf1554e8dab1eca6aeb6c7be6bff9f769868df266ea1fb7158701faa8a08b5c02e7a610932d44c7271701a1347c074bbb94f714cd2f421b4fb4888dca2bc98d09daa19b30676e75dbe8e9c7114eb3cd90	\\x0000000100010000
47	2	34	\\xbd3b9e60e05cf29c32ac98d0ecde204a9231b528b5c85ac01724d2188630a33a2c2ba63852cd9512581899792ffd6ce822ffa36dbc44b658b8168f940963320d	193	\\x00000001000001003691308377a5fe547c1d2754003943e6537ff8789a9f059a7e3633f1fa970079704195aeaffb459379fe2b398c257166bf407d29b358bb80edc2a9242585e900bd5e9c6c7e2ef50ce01f4e4fc417d1df7d2365330c6bca43c877409b3c9dd3215c3896e7df43a05b39d7a147ed7a7e891c8d4c9d853360b9da3358f889a10d2a	\\x756c6ac0a8e6459b0909d270eefd8dbfe52dd4e2cb6309d589ded31310664bd4914a84796fc0840b569685c11119dc9afde75c7e8ad52865437c5a7d3a1a97cc	\\x000000010000000142ef88794c9db47df2c4cabb35e8948bf7bc2c240c236c13d1efa5f40b1ab3e8767d747e28f200dccb8456fcc997d6f9ce59faa88a2a39a51ae386475912b5cff37de226c21a38163b8147684285d367b965baf33e134dbf029b535358339bdf70a93bfb8e25a7be0b3efe2468891fbf255475ae9b775d2c274d06e655b0c8bc	\\x0000000100010000
48	2	35	\\x6c7c5e734a9775fed52f7b906829cc8b61b5051ee1736a26631ecb3167515129b7c99f10e0aa29d67a2038d290d5b50757980844e8c601982414880b91b82e0a	193	\\x0000000100000100484a23d1ee56bdc46768c5b49543ddafc0fad3d44173e5d46ab5e280f8257e01e9105c9d2596fba89e9530152d92aed4490f0c561bc17435cdda081c2b1d5ea65314d968cf747f4ae07efb37de2eb141d0108ad2abc74968895ba406082c04a25e445add82ef1ef894b9364e870452036c2e4d8ba57a409a108445c6955162fa	\\x4692a28b642a43f374f8178d1b0317e8fa1ce4aca21421843e2f94147a32b5d0ed8ef5b743e038e9a89de614459c9369fcfa938a05ec1256d23c83487a974b4c	\\x0000000100000001689bd9ede290e3f709724dafd92f104f90a46d6844b8a51bd224e06012ae34b70314a86090fc724d4ed777b24c3f2799944404f10c068acbc23dbb89e4f6fd369dbb10ffe53385592fdecaa4b7c5c65e2af65806e4bfe41f531a0bc022397d17211a7968dd79f63d3d2bb96439908f6f0b0f0d7800c0968e9ba4795670ff9525	\\x0000000100010000
49	2	36	\\x91bd0be8239ed1bb19ea85bcdd60f83c21bba291999d95e9078230bb73a0a871928ec05298ef4c2117562ae8e8acb538b944d4d33dbd2028abbcefd6d30e120c	193	\\x000000010000010056905c945712690bfb7fa49b86df5f5652e2eb633e7e25130eb2207fc4d557dbf97ca162c83532616c6737feb36d14ed2269786feedf96ff19e0a78497b140ad3df3e74b06a80eb664efa401d6d74f2eb932b678d2975f254fd3fa3caad1bbe1595aa9d3856a8edd32988bb65c4245041c26e2111d6bf80287f36202d91691f7	\\xd31b6c8232a51b1c92b0854afaf88d5d7f1c27b66be65be838c51589dd41559567b71889dd8ae63c15808f830852e7dd6cac12e6a95ba1edde0eecc07f09e59e	\\x000000010000000121b2065c26873e413a98d1bf74dae59d7f3d3244b4542cd836736471d8ee893ad15f714e209458aa2e559578fef85c58fdf740f6ab058f78f6c744132bf4721f352890c08d5f576a220f95ea91e8ad4e162b5fb1839611b7d6c8bff72131a9c5de4d58403b0f8335dfa6abaeede4dbef6cea26fb64b3a8b8593711ea77a8d14b	\\x0000000100010000
50	2	37	\\x0fc4984701700fe1381e1cb0aacd8fdf8cdd6ceadd2e6e492ebcecdbcb0bf0ca0247fdf6bfb72aa5456ef949e07dbfb9a1ddebf708876a9df4573e7424d8a001	193	\\x0000000100000100555dc6f7665b96639ec5ee7f1d1af81142638494367ebd6e77ffb1ab408c5de90fbaa997c886cf015cbf4eb86dbd667583134d538d45e9f7a3d3aba53b72fd9d6f05d3edf841d4f46497cafab576e244bf46f9a55ef7730040c78ee470573a90be112e728752ab3bfab2a634d3f5d2740159d13daf35fd9d2c49a1ad82054d49	\\xf906cafe98bc9396b0bd6201e3ec47a5b821dba38128bdfad53576d3021c3bf60c89092a77ccbe17c9f8a60235e2fe422d10652c8b386e82fdf53a938254174a	\\x000000010000000142b0c3fd76cafe4c8b23f0b2ee9674a444b8f6855771d763ea602de2ca8673357535bfb471063bad9032b0a1b40753a155ac2956be3423ff4b593df3f33f3e2b4bfec08ce31de86aef39aa823bf7fbcda3664058b73a2ffa939e2d494c372178ca3d63edfd57763778faeeb9d53f4d66c2fbd1fc525ef15a40b14d69bf8efe3c	\\x0000000100010000
\.


--
-- Data for Name: refresh_transfer_keys_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.refresh_transfer_keys_default (rtc_serial, melt_serial_id, transfer_pub, transfer_privs) FROM stdin;
1	1	\\x68c4d95084c6e6b102c44421e4f55920a251c51bc69023efa718b4525d4a3459	\\x6e44aa480cf37e533054b62baca5cbcde075816fc9c452b94ff518aaf3f340cb0b1328908761c5587c55f5ac1f38ec190c7c9831a1c84277a9eace90d90b7045
2	2	\\xb41c0282b7068ca252daa74122072f90d279872d3f4dbd211810a9fec38d920f	\\x37053d6e739545adb81b681baf1ed53c790cd2c863d24a8b9d7b628bf182e5712783303bc89a13f5f6e65de4ddb28c084451807919cc7515204478b34b606f30
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

COPY exchange.reserves_default (reserve_uuid, reserve_pub, current_balance_val, current_balance_frac, purses_active, purses_allowed, max_age, expiration_date, gc_date) FROM stdin;
1	\\xb9c28a718cc5abdedeb7188a00523252945905d1d33765de3e045e7944eacd4f	0	0	0	0	120	1663073715000000	1881406517000000
\.


--
-- Data for Name: reserves_in_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.reserves_in_default (reserve_in_serial_id, reserve_pub, wire_reference, credit_val, credit_frac, wire_source_h_payto, exchange_account_section, execution_date) FROM stdin;
1	\\xb9c28a718cc5abdedeb7188a00523252945905d1d33765de3e045e7944eacd4f	1	8	0	\\x3c942b03609b3cd8e4fcb95abf92bcf62aba6303da0902b5974643a4369fef08	exchange-account-1	1660654502000000
\.


--
-- Data for Name: reserves_out_by_reserve_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.reserves_out_by_reserve_default (reserve_uuid, h_blind_ev) FROM stdin;
1	\\xfb7df559cd80eefe8e0eeb2d543cbf5452ad8813eaddec8729298237a7630a58e8e005e2b6886a50bdab4ea45af5f03109a36407aa95dc45290339ae9e25a778
1	\\x82f34489ab9bd7cc9b0aea11f482fee85e5b7117a9d08fb40d17d38daa232583bbd8de38a793d9534bce1bc947f2269dc21e48548d5d738ced886d5747b76e5a
1	\\xf217ddd93dd5e5b56e9053b592b7074163f5dcfd201fbeb6448ccc960412c695e65d80878501d1211c2a0236fc11c70e26c2297ddd1fa6425ba8e7c5739b13fe
1	\\xe95bfa18c21740bc74ba58f7bac783757bfcf2bcfabc12c079df315f581043687adf8a0df22a0600cc87350c8c980d2e8de3a36f167580e6fc8276bb2f4120db
1	\\xd9bc709aa6244f558086fa9a7c8c9a9b298da53a8446a5ef603bd8a0cc23ae8c57c2c9ede64453fca1456bb0e4b8ed903ff730b68bec8a9a8614aff8b91acb90
1	\\x04b54ea86784d13d36e8f8bb3bd3350e3a60c8d48dcb85da194ecff705105a312e9fa4cc3ce700dffe6ff48470a6318064a91c6bced22697d2709192656a6f22
1	\\x19517ea7372037addd0b41d65809be55437e59acf707523ba6a5480999e5c42dc144be0d01dc4e406c765ce2aed43f914fd79b0384da7a39be283578a286da1e
1	\\xbcdbd9a12a731df1453a7ce34260d3352de6bd35a8546b9b70e6aca54fdb17f9dec0aab3d5df1cc9c767ad16084309d4128952ef34e8f483c6943f44bac313c4
1	\\x670be3fd9f5390aee57dd22c90602adfabd29b0247e34a83805d4fe79163ed73f1a337bad3a96b133de8ab99bd4977338da3f637e072fb3ea18d15e43bbd2aa0
1	\\x99f8955c7978aaec80539014d32a0f07a3cbadf51e16c4e9bdf486e6fc9424894ed69d06acaaf46840469531be26a757ee574f90e37db976444954710bec1efd
1	\\x6ab80708d1a6c1a96f1aa4dfe00c497e06f9d99814c472d2404a65a1af0469d8558f628ffc68d9e339915183e9d3d4def1ff74cbaaede65a05767f04da94fdcb
1	\\xa0a0673431d0815b330b37b0ea1940655ae0d61126b11d2c357df35a8af90277c6e9d381febb4d02f859d8b67a8de9847a7680073c33da9d8f94f701894435ed
1	\\x2f9009c32b821a2c0ac6060d90d8c708e7a1cdc33ab418e15e88ab8010991957764961ba8f6e7317d4b89bb1bebe8387a9084c0d343213f70d2f5dc2539a0770
1	\\x0fdd9bc851a1de06068d9b854855fdee5b723493941f5ffa2f47a27fea8138fdc5a9ba496172f309b8aa47d1a5a9ed173389316fe2bd981cdf858eb26bc9b515
1	\\x5c54df85f84c61053e53ae959bea3b4212713cb87277099ecb38bbd30824f3f9d50b9c272a44b0338a384a790b669326262f518b977746fefa93aba09ca45f3f
1	\\x000246cc7711cbd4a3b1e061c5bf4de97b2f15c79a6a74d97911b5d7291e9fab367ef534f7b051a0e057769a1f14be1180f435b9937fd4a379dbd3e6293a3931
1	\\xc1f27507c1e6498b9bb361b280d1435d88537dc7b373db13d414fddb4a63d4a3184c83d04215ef19f9c88158f2d7938031e925859713d33470e39a977be5fc37
1	\\x85bb10f5fe500ee33f9c1d59eb370508fe3d8f875ca9876a7f61f48b4c401b2ac8ea96aec9ed3b010b2727d6e30b221c0d6f7321e003afbb12377f603342777b
1	\\x707bb93db6451b111f5dde3e791f0320cc95e74ec30da07688d56a2c22bb5b278f1f84309bf7ce92394b9cd53650a90cea042afa9f6bdc3c997d659e919d3b92
1	\\x3ead69a4c8ce2232470eeee25d88a4c7bc88946794d6b3d20abcd56f5aa22cbbb9cd29494e4a94f81f2cb990fe7d00a09750b70f55d6a52395c762129a5b6514
1	\\x8f3ec6eca08775f517d9adfeb334fdd52ff7b49a42b4210dda3f6b6da286731bd8a88ec9420c11c311b90b164c85f92f64775c8f39ae3d4eb55d10326642037c
1	\\xeb2d4a22e4d8537b8a7557617fcf9f85b54e204ac7f34eb2b0dbf521a35d92c2fb6e7641603446f7ba4522a7ecc0015df8a3f555d18681014cb61aeec891fca2
1	\\x20281e845c405ba48f4b5e64f7bfd8c48c9a84c046f517a39472939fe386f942cb2b961ef5b7b49710fb5ac9d5769d0310ab7cbd903976ca0ec3335af5f1b7c5
1	\\xf2ed97bfc10b7ab297c28ef06c8086dc217fa9a1e775f05b2c5583c119d8ec77ad89bec0d457febe9b21d718d89f70dceea6aa0b5967ed08fad6ff8927e12232
1	\\x6e36686d7b83bb8332d9e8eed6ada2224dea7e8ab8593dd2ee1dd0614b2e0820edf4fbce91efe6a95d7ab08e25517b4e6a51245117240ff6a35135f77c363854
1	\\xd96e6421db4885471054d373878cdfe6199a8a607b19552df66ca8331bc2dcd1107af728077e35f54622f6c63a04c4874badaa78e7dec89cd93de274f5145af0
1	\\xa72488712f26d754f26b2f1b7070ff09c67199939d7f76abe3eac354ca0adce78695d05f0806b2103108c0726372d1eef95a3c72bf3b7141c661f731cda78ea0
1	\\x97ae4f6b79269b256a12262167428ccbd0822bc6cacd5bb937fbaa5f16b9ba3f3d8e3d622422f3b0077be3c84872c22cfd61d35346c254c45924ae8eef55876b
\.


--
-- Data for Name: reserves_out_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.reserves_out_default (reserve_out_serial_id, h_blind_ev, denominations_serial, denom_sig, reserve_uuid, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\xfb7df559cd80eefe8e0eeb2d543cbf5452ad8813eaddec8729298237a7630a58e8e005e2b6886a50bdab4ea45af5f03109a36407aa95dc45290339ae9e25a778	104	\\x000000010000000104a6c293e6f27b6c2d1ede04f04cf1630854f0200a5a1fea3c35d6ffb1931431c869d1cfc2876e4af3a051e2b034acfaaaefe33882f15ba35de5ddfa0fbe8bd103b25d97117c59ce0642d15cfbee13e6b8f3a532812a8d53baed9eb7434a90c4ef9afa9967bdace136c19bf0cbe3098c0e63879a23ec3c3755467feca1f557f8	1	\\x5deb764cfedb946a2e49dad70c9af08988b8a94871a2fcd3d500e8641f25bd32034e692f7b12a8060ad3ddd3985f648b9a5a616f6da5ce79760e8e33a21f000d	1660654505000000	5	1000000
2	\\x82f34489ab9bd7cc9b0aea11f482fee85e5b7117a9d08fb40d17d38daa232583bbd8de38a793d9534bce1bc947f2269dc21e48548d5d738ced886d5747b76e5a	3	\\x00000001000000016c2f4f2571bbd9c24c034b97231654a8ce3e0adb893fa5d0cc0a83fed3c819db14695920b7ea722a5ed80844cec6e20d6aadf45abeb500581c3a8cf02f07e35f54fb8ee253ff443dbe365d4a75a7cbb69195a37910c98696dd18f8baf8495073866e35e25c0a1da16c1a284a4a6e7ed909a421745db3c141f06c7872901b858a	1	\\x5be36f6ddb1630aa8d3689bde73ae3a15bc0a47bb3c9e55405abe4e45cdd7db9bf7c6551ef88aa0fbcd21783b2f8dec5c5a65feccbdb62d51a46a55a3423aa05	1660654505000000	2	3000000
3	\\xf217ddd93dd5e5b56e9053b592b7074163f5dcfd201fbeb6448ccc960412c695e65d80878501d1211c2a0236fc11c70e26c2297ddd1fa6425ba8e7c5739b13fe	353	\\x00000001000000019c590b88e7150d2b635ab7a92b6929b19916d5fdbec626e57beded4088b67d84c676e7a4bf088ebb75cb2bd307cce826fef8563247f5bcb5b731435baca8827c9595cc3e27239bfab7914ea95209c8090340c3faa88173c0811602b2d84e32cc8c5733da6a1c488a89fe5f5e76c69a755f413c149aaee8534c96764a8518ba13	1	\\x08ee00edc19858c652665bb0ad54f7ff3f7303c4eae994e21e43bc774e14ce43f6760e47fad2ff80dbb3d7e13128409c0bb5533e2cb3029a7ecdfb2b1d8d2507	1660654505000000	0	11000000
4	\\xe95bfa18c21740bc74ba58f7bac783757bfcf2bcfabc12c079df315f581043687adf8a0df22a0600cc87350c8c980d2e8de3a36f167580e6fc8276bb2f4120db	353	\\x00000001000000012e22fd15882f8d2a36f1172b87efdcbb026a1c7291e74d3a3e673e335f441e0989cbcc76a6eb249ab6d6ffd7b76b5d0b370b188341a6d4c3781858dd7cd96f48105c041b8a0d734cb1c45948a32b209af71cca42f307c8a0c1a787499827987c6f724186570165208f068173d12df4d2e386b373966ac1745687d49609c85813	1	\\x327732f2d6869b4ee3f3d608b34a1b4e9a28ba2d91533a1dccbb3e93216fd042f0ef2332efc78040b2c4a51530211e5b0ea9f6f9ef9fee151e03f7570f8d6a08	1660654505000000	0	11000000
5	\\xd9bc709aa6244f558086fa9a7c8c9a9b298da53a8446a5ef603bd8a0cc23ae8c57c2c9ede64453fca1456bb0e4b8ed903ff730b68bec8a9a8614aff8b91acb90	353	\\x000000010000000123527a395b725bfef6a9d1f526702ec39273c538483757b522611c0c95fb92b8b8c630328602820eaf54b1fad88a49fa1f6ed4a6e0bd8f45cdff00ce499c8f6290e8d917091d340f2a4ad50a701ad449be1b01e934a20ad66371fe37e86e76db15bed9742928c26a679e3137bf6f16af115d7ba96ce5f2dbdedcfa9f2ac2fefc	1	\\x38dca2b165359584f6c7a43252744b9c7930cb5c4972ce41adaee9baeb75c7f114be5c398c0850ac076b8fa0905cfe68fbdf8833b4d9ff5104de80664dca5c04	1660654505000000	0	11000000
6	\\x04b54ea86784d13d36e8f8bb3bd3350e3a60c8d48dcb85da194ecff705105a312e9fa4cc3ce700dffe6ff48470a6318064a91c6bced22697d2709192656a6f22	353	\\x0000000100000001505002c602d566bbdf56d72b405bf0fc092e064eebfaee033ddeb0471f251bfcbd157dab4b45f34588c2dcab3b01e8908c79f00899c920cc16c0f064b22f63b6d7a4ccd7e46d6f6156d6f6da1f51fdf815491c18083c723a94c4433086b466b7f07d6e8f95829422ddc2958b5142c3088cc95b4f1b5fd62b205b50f341f47696	1	\\x3e485fab3d21c903d5d406c2bb1046fcb99915c6faeefbe66c6df266b363bd736a8c31bd7437987107f0288e79b465be47774c2acd2e86362a3261b702999404	1660654505000000	0	11000000
7	\\x19517ea7372037addd0b41d65809be55437e59acf707523ba6a5480999e5c42dc144be0d01dc4e406c765ce2aed43f914fd79b0384da7a39be283578a286da1e	353	\\x0000000100000001846290ac8c45c3738d7eb004b7a1e8ca362455248b347a0148089b2c8bc597a5c5dff0d0a26f1d3141b150b913b36762f2f68e64a12713b7ebe68b3f51fa9b7805a3c4af38acabd5104a946ecaee27d6c5ee9fe6c343e6b3725ac21deca0ed1b3b944ee8a4d55d4434bcb013b87058ab67eb13658f94a9887f610da7febb4ba1	1	\\x451999a9dfb0212dc25620571bc96ccb65980926c065098ddfdcb43428170baf0c758034bf243d5bd8c4059217f7235aab11eb13e6e965d008d3b0b3f1b55303	1660654505000000	0	11000000
8	\\xbcdbd9a12a731df1453a7ce34260d3352de6bd35a8546b9b70e6aca54fdb17f9dec0aab3d5df1cc9c767ad16084309d4128952ef34e8f483c6943f44bac313c4	353	\\x00000001000000019a90f58b285f2979004238cb439dfe11d41a1a744867e378ab776370006a8ae1af236e291ec54489f3fba1f1f961ee1333d794974e6085661dbd80d85a950864bee3cfdec9a61dab1c991767d4df2f989142d29a8c7a23eb7f0c11c188b9f371f245664a1b104284104a3df504b7b182f91d7a43287f8714ad714c8de5c135a4	1	\\x2f375e6ec69f29bba33913174df3c64031983039cd6ba9710c82fa48294a97905ab0ba6d0dd4a0272fdc31d1068b1a4ad971baf8a5fc7821b1d23983af6b9608	1660654505000000	0	11000000
9	\\x670be3fd9f5390aee57dd22c90602adfabd29b0247e34a83805d4fe79163ed73f1a337bad3a96b133de8ab99bd4977338da3f637e072fb3ea18d15e43bbd2aa0	353	\\x00000001000000015a52ceddd227f2379d31eb87c6716bd1fc51822b33db177c2fff270d3de8244a09da7a7417be2974c8935c6f720e5f1d0a6c4f4a8b53d950b97e9608a4338c2aecd490a8d6f5b28699d9d88a1422d477ce6021e949969b8a1610aa748b60fde0206f39764625d14563d838ad92372a8a9ed6c513dea68c1dc041bb8b3a9940ea	1	\\xdd884503eb9d3ec92c68345ef5fd1fb2ba3e6ded677c46bf14e3a25bef8c88608e451a605900c3763643f0eee57a946f8d7d640096aa07e2231529880a8df80b	1660654505000000	0	11000000
10	\\x99f8955c7978aaec80539014d32a0f07a3cbadf51e16c4e9bdf486e6fc9424894ed69d06acaaf46840469531be26a757ee574f90e37db976444954710bec1efd	353	\\x000000010000000190ad8dbc0167bf88cc25a626a6188c09693f5aec237ea223428390f3b8c68839568c0a429dc2fbcbb0963ab1a0937fcfc25357f203163c1b3a0f9ec77f8aeac1a1e8ee8e936dbdaa5687f4993c1476a6f77e1e5a00f44009f9cf24d18a8ac266abc5d30bb0c609f53754573a2312d7a8e560d8e199cccdf3f995a65dff2dd269	1	\\xaa1a5ade138e350226ea2e03176a22c88e9a270a5f6536cbe7ac9f016cde0f1b71cddc1ca7d8b1307a808af0be9edfcb58fd3e39f1ba7cd3c59b1bc3e487c804	1660654505000000	0	11000000
11	\\x6ab80708d1a6c1a96f1aa4dfe00c497e06f9d99814c472d2404a65a1af0469d8558f628ffc68d9e339915183e9d3d4def1ff74cbaaede65a05767f04da94fdcb	70	\\x0000000100000001d008e73ce266080b0a2b5b137cad8f75c75e9cace0925652db4376f70f3ff9dff664da9852e3702629c6cce7345c62614db94cec0633471c0a54eb5dbbb53c6e63448dce51854207db2bd3e8cf4333dbb23b06a7a59256a04e97310146db1e525ed4e0803d14f74f3dac36c8654e211038c8340f31486cd4c824614b2f98d8aa	1	\\x4a151b22d0b16f2b6a77093786bd42385034f0f917975839dbe2648232ff8f6bb9b3f3614c202e40f0209271d86062ca83748038e5f2fb041f9434d6fe2ec008	1660654505000000	0	2000000
12	\\xa0a0673431d0815b330b37b0ea1940655ae0d61126b11d2c357df35a8af90277c6e9d381febb4d02f859d8b67a8de9847a7680073c33da9d8f94f701894435ed	70	\\x0000000100000001643399cabbd76f7152d22942bcebda1290564a8f91f8a20284e95e94443ca88bcf3c73d67247cc44c4fbbc9c491052ca19684ab65427a042e2e7a646bf75b823f44ab8b6f4a4cf14b1064d3f978ac4c2b7de7f1024b236b92d965650b47f022626657086f46d9584a1b501ead6881d90ee87de074a0cb55a7355bdbd5a0bbe13	1	\\x13d385b081837cff465685341ff2ab4f87f909e1daca2354d6cd1e5b6558a3556b006aa74a1ea6ec524c737a8fb36f7753f3b888b2f07cc8baad35ffa4d3b109	1660654505000000	0	2000000
13	\\x2f9009c32b821a2c0ac6060d90d8c708e7a1cdc33ab418e15e88ab8010991957764961ba8f6e7317d4b89bb1bebe8387a9084c0d343213f70d2f5dc2539a0770	70	\\x0000000100000001d223fd8de7ba306a396e62645fae205ad701858510c9b5325ce6989a2594af2bcb245d5af622ddbdd35a78f25871853b078f948b8628a72c73baca195ccc447a9cffb76dd9e910869535bb6cb1c87509868f8de4b43a95c975fbfe1fbe95511d3d9b318992732a0c7b8620e77b19d0d488981a7acd02c0562459e3594f3a285b	1	\\x0d8b6da0dfa58224685b3fbea583f7e3c059b2cbf44c1e437f68b7675e5dd9467795a1843cb5c229e81fc7ec3b99651cf08319a8d0f5fe89d8a31a47e66bfa0f	1660654505000000	0	2000000
14	\\x0fdd9bc851a1de06068d9b854855fdee5b723493941f5ffa2f47a27fea8138fdc5a9ba496172f309b8aa47d1a5a9ed173389316fe2bd981cdf858eb26bc9b515	70	\\x00000001000000019f8b86d68a5937c3caa4290bab54ae893a8b47bb8977faebd40b63f16a0fa533bb64c7752b15b9994ce6451ec588d3d6077c6ff5199a416d029906b40a53245b4238405288fc016fe35cb483b44bd588466971868f3c625423cb366735cda1aac2a3694d8ca78e2dbf2997db3a9daa9fdd2fdd95d5b2b4651f3b8b9e616bde46	1	\\xdfc820525c0e1924cf3d71b3972a54b4ea3c0aae999f8c3fdab8bc4c7236555e5ef20f249ea159545355ad83ea8fad48ee92661d7e2f9e0ce8d50d4f32cbde02	1660654505000000	0	2000000
15	\\x5c54df85f84c61053e53ae959bea3b4212713cb87277099ecb38bbd30824f3f9d50b9c272a44b0338a384a790b669326262f518b977746fefa93aba09ca45f3f	384	\\x00000001000000018eb318688b93097f1c28b6bc36ea56aecf0dd57e89ed8ba777d674c462983662d74d1d47d67547d5e25eda04f84ec2510e987f0b9b8b345b54c0916578744cac1d8dc29c3b815746c321d420c7979941c1a33c64f523820bd314b25dca01b1be218a2e76c553d63133658ac465c0425edc0befd93c55107488d08c765ace664c	1	\\xe703c6b6ba80bdaa9f63a6e85b0bb2d2351e0ba976512570f0aae0ecbf5077f8ff7dbf11452fced7da5fcaec6943f6d7073f8fff0200ff496712864a753d690e	1660654516000000	1	2000000
16	\\x000246cc7711cbd4a3b1e061c5bf4de97b2f15c79a6a74d97911b5d7291e9fab367ef534f7b051a0e057769a1f14be1180f435b9937fd4a379dbd3e6293a3931	353	\\x00000001000000018cfc4e6242ace0d546147e8836a4e4c64db03bbfd2ae65d6c2a1b04cce10caa0cd96f70f89020a4f44466e0095b61659f7fe82f385e03c4f64fe2e128af9903168e18be6679579de43bc050a7945b001a5ebd565f7495a3045b947771100b40bc01c8545cee906780afe6eb2d526a8a3fcbf2332ff6be5b3b88ab1b2ac63c850	1	\\xecc07706c7d3748005d371d63096b2a3b2fc12d6c390beed2bec84d6ace71d6dce476b18279d31b6d202f1f1bb223ad24b689c9f5ba7cac65fb0994b9a94b402	1660654516000000	0	11000000
17	\\xc1f27507c1e6498b9bb361b280d1435d88537dc7b373db13d414fddb4a63d4a3184c83d04215ef19f9c88158f2d7938031e925859713d33470e39a977be5fc37	353	\\x000000010000000157df5ebc5c4fbf109665bea6284ef124c336012bf75404526b35e69aaabd7fa57859bf8a832adf37da1f4ada1f9e014eea39b6c74702942bcb278c1c24dc0996c44da0291a40167b4483b78a495ff9abd37e11e84da553692fe0ba75dbf3aefe140a9eb59eb96676e1a7389ae0b60346df511cf88f050f6f92d12590422a0d01	1	\\xf1181f4d1e4abc505560e167361101fd7345ff151a6935f8a67818477dbda3ed7849942d5ecb087462aca37b7025e54661f2db7e80e7369cbefe64666860bf09	1660654516000000	0	11000000
18	\\x85bb10f5fe500ee33f9c1d59eb370508fe3d8f875ca9876a7f61f48b4c401b2ac8ea96aec9ed3b010b2727d6e30b221c0d6f7321e003afbb12377f603342777b	353	\\x00000001000000015ed6d8e28f441e4692090479717ee0829e68ea537daa9e24e7b04105a2d524012f86d76de93cfc090ec0702906118d2f41073f7b00fc037123c597cd66932769f3ce8694a6cb7c9d4097cd5d8c337a011197e5ec49e8a062721924bcd16eaa3e350a095d5c9ec05b45f8c726755ccb93d3b61cc18c5648ed46d664740f67f873	1	\\x4bcb5c8a86ccdcbde5ed21f5ce88c8e428504d1dcef21d5eb7c712e7be762582af66abd99237cbacfb6800efa0ab8f56c8caa42c968724b42dcd46b858e5fb0a	1660654516000000	0	11000000
19	\\x707bb93db6451b111f5dde3e791f0320cc95e74ec30da07688d56a2c22bb5b278f1f84309bf7ce92394b9cd53650a90cea042afa9f6bdc3c997d659e919d3b92	353	\\x00000001000000012b0c23c559b0b95a8b2ba8f4f34c36270390f29dfe0adc0670d1535be3d12a662a7de8761681e4864213550e9d6b1b3f44979592f77c0c307fe0ba0f7e4ea7a0fcfa6af20ab6ecf809b8ee69f36896112608f075078ffe1d354ed100ee1deb12c5b0278ac68202ab8221e9d504fe93d0ff1a37ff53c7e2b439b96a315d37611a	1	\\x1054231bb98fe474bad40455f5008e0fa551fa88bb8dc867ab115042b082810d002f4587abf98b92383aff1918c96dc83d384952ebd9c92cc941e8ddbcb41b03	1660654516000000	0	11000000
20	\\x3ead69a4c8ce2232470eeee25d88a4c7bc88946794d6b3d20abcd56f5aa22cbbb9cd29494e4a94f81f2cb990fe7d00a09750b70f55d6a52395c762129a5b6514	353	\\x0000000100000001121df9f3a4bed74d52ab486e00124a0ac3a1ea59b0f9dd5cd79dd865c95e871bbcc8aa424cac63e81ec0fdbe92d64a578d04df26c4c0b9b3f3e1edfcb821eaac90403d392bf790c79fd1d285576d60d23c3ee9052dd3288a93042076fe3d3d58d048a31d7a15e8ce99042823809f90b3276f2fb63a6f7e207b36a3388bc119d6	1	\\x59e57a09f1c46875b2bc1fccb4a355e5d046982fd91994a8efcc8ea8b59e3faf39d2880f4b445129515b43a1e6121da7be93cde1cd49ad6380a85f004330a808	1660654516000000	0	11000000
21	\\x8f3ec6eca08775f517d9adfeb334fdd52ff7b49a42b4210dda3f6b6da286731bd8a88ec9420c11c311b90b164c85f92f64775c8f39ae3d4eb55d10326642037c	353	\\x000000010000000172573c14a05e17c5c173ccee255c4220fa6e8c04eb7e2e3f6393cc3518a00c5386c0ce41751c746f91b41d28f6f413746d45df606b50d561cf2d5fe6f4f3a06b0ad547ea18c7f00d5d0556428543d31dc1540bb249a03aea42049ccafeac7e49d81c39f2fef401c8838893f20b84e620ce2f790743d28aebaf4a932b33aba60c	1	\\xa4334a7c19e0bd01b16f07e147c6515bbec259f21535aa38c0ec8997886c78b33848cccc049e52986787a6ab99e630fad1cb4acac283790694ca6979dbd06904	1660654516000000	0	11000000
22	\\xeb2d4a22e4d8537b8a7557617fcf9f85b54e204ac7f34eb2b0dbf521a35d92c2fb6e7641603446f7ba4522a7ecc0015df8a3f555d18681014cb61aeec891fca2	353	\\x000000010000000166a3d5e3f33b77d9458204aeef1be4986c2bfd9f1b6e9abe250281a021ad6642a6f06cc167e7c915774c2abb9a632525f304b955425422e529d124fdc3d42b19b2e633de6f9a5f30ad21b8bdcbc6e09712f5d73d437f286d84048dc1f079f519fe4bddf038fe780554df2d41d21029d3a297b94aeb0c72f5502dd6d9a2529427	1	\\x787f85417e11d37b3f282ff6a689b5f9ac2b63a26d75df56098610ded0a8cefcb8352c8be66766782b4b1d0e779a327baa52dddc6696415d01698f0e3b108400	1660654516000000	0	11000000
23	\\x20281e845c405ba48f4b5e64f7bfd8c48c9a84c046f517a39472939fe386f942cb2b961ef5b7b49710fb5ac9d5769d0310ab7cbd903976ca0ec3335af5f1b7c5	353	\\x00000001000000012fa0543ca4e283c78c7f796a1bc274f8c4e169ce4ef1262e791a3bdb03b6c839e080290aee053711dd904dda73c06085198580c0296e1bda4be11cf0e3d04ec068b029cb222a62a1e64a996552cc22b7c8d7981dd429f9be547e61ec839aa37138c620fba1269f9a706af3c9a6a45e017cc812f1b641da4b51a2fda7d129e5df	1	\\x20d3aaec576e704731db67c8cb12217d01c5b948c642666b3bf9da7125a13bdc9bd4f5cabdd2516c0c687b03ae2a2044431b38836332972b934c754706e05e07	1660654517000000	0	11000000
24	\\xf2ed97bfc10b7ab297c28ef06c8086dc217fa9a1e775f05b2c5583c119d8ec77ad89bec0d457febe9b21d718d89f70dceea6aa0b5967ed08fad6ff8927e12232	70	\\x00000001000000014787bd8284b950055a29fdd9e51c22cdd6401fdc077b0237b1982f94df11385e6465da71115b2d0b45c9a284709ea5d85a336047911728866e042a6fadd91c8ad876a21f67e604b49bacd5683005f3706a4932761ee67711b79fe8ca83c8ea3ac59876365d9799ea0d8fce3b627db85bf46bfeaa2eb9d3b4aaea9dc9668b34d4	1	\\xaa8d1e67b1a8822fd0e7a0038213534c02f24ceff5c281f583a7c3fa8448855420171125560ba93205275f786bf1a5a4010cc18b094fbd79270b8e39d445a108	1660654517000000	0	2000000
25	\\x6e36686d7b83bb8332d9e8eed6ada2224dea7e8ab8593dd2ee1dd0614b2e0820edf4fbce91efe6a95d7ab08e25517b4e6a51245117240ff6a35135f77c363854	70	\\x00000001000000017c0d3f3890619ed9d34cf0658c16b2b32549d0add4bcb71bd5c5a7c4e2ad2bcd2bcf6e9a3807e1a4d6f2818d6889e8e2d2b424fc19b051b2449dc1e46b1097820bd6a8b32768ba59c6cc28abaf4436934b53345dc898f8df89f3ae22d77473c631bd525240c012826be14a9a5f20d2e85ef4f84642e3c1ca68c0f509e8d2a583	1	\\x5a6aa0bb98a2804c773fdcdcf0bc1a4721c41ec50756f664e19532dfd9d00062405db273ee9ebf804c83fcd48669f4a390494b1b75f925262539e8aa6f6c0c00	1660654517000000	0	2000000
26	\\xd96e6421db4885471054d373878cdfe6199a8a607b19552df66ca8331bc2dcd1107af728077e35f54622f6c63a04c4874badaa78e7dec89cd93de274f5145af0	70	\\x000000010000000145e591b5a9988ab84537e98f1b5094da1de58fcb8abc935ac1c39790a168054c28074a029de59c8cd0e97e5e63809590e51890260897bc4009c119de376d1ea4a7eb14cd17e05eafd238ae76706fa6b2cbc23c5f572177958b596a9f146b87bcb764f25b165c89ae60e05ed8dc3539a46e76f77b2d079905cedee3a10340c5a1	1	\\xb799dcd744f5884582c18ef8c7fcd58168b29b9c237c0cc0f03dd205876cefdf0ace2f4e3f64798896f5e625955dc468a70810bf305d6944797ffc390bb7d203	1660654517000000	0	2000000
27	\\xa72488712f26d754f26b2f1b7070ff09c67199939d7f76abe3eac354ca0adce78695d05f0806b2103108c0726372d1eef95a3c72bf3b7141c661f731cda78ea0	70	\\x00000001000000012aad4806582910070478dd77779ad8a18d95867ba1e6f8c521a8391e48b6869d68e54498e9780d77e886f5a4a805af633f6df5229008a0c96b494cdaea06fbbf6deca51bdad860e09e15119542193e454b67fcf3b881f3e707bedcccbbb46416bb0f5bff7274703b17e410c9498d89260c6defbbabcd6ad70e49d4c1660c831a	1	\\x7f4d7a8a6fc8a2a71b29fc8cfe7268f6f5f387de219294e948a322cf1280ef039dd9874c6038f94446f2861c932800620db2202167e2c215c6c07acb0b6ddc09	1660654517000000	0	2000000
28	\\x97ae4f6b79269b256a12262167428ccbd0822bc6cacd5bb937fbaa5f16b9ba3f3d8e3d622422f3b0077be3c84872c22cfd61d35346c254c45924ae8eef55876b	70	\\x0000000100000001ce7d58dfcbc25f33dd7b19ae21d427b3f9129faed751a205d9b3dfb690575f4e341e078a1eee7fa04a11049ad8b62f363c24d679f14fbc8e4220d3725e9641f6ce4aaa84336dfed36e6198ab5d86c44617760daff3638ef147c33fd9715afff81e0af1dc1d393b828c92ac66468f8479f335542cb8ea7cacc6c2c323e197afd6	1	\\xd732a53bd0ed1f202e74f0871b65020d66f1ac3d4a9bceb1d83f5d291a12a26118d1081175e4b7077f52891ae02193043eb5ade36f9903ec3131876f6bfe560c	1660654517000000	0	2000000
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
payto://iban/SANDBOXX/DE870149?receiver-name=Exchange+Company	\\x1c64d6c284876958e0a5b6c1612b8353bdc06a84b4b598dcfa534b88576801f4fbcf29fccb4e2f55d53ddd20681a6e5b92c9a2caa25f99f4736d0f65b012d507	t	1660654496000000
\.


--
-- Data for Name: wire_fee; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.wire_fee (wire_fee_serial, wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, wad_fee_val, wad_fee_frac, master_sig) FROM stdin;
1	iban	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	\\xa44fc10beadfe76054b7ce38d899df6269da7e291fe99b668d57165b9e50400f02d9a62ec0dc11c85b685604e20d0352fdca034e2ed0e1e700afd23c57ef6c09
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
1	\\x3c942b03609b3cd8e4fcb95abf92bcf62aba6303da0902b5974643a4369fef08	payto://iban/SANDBOXX/DE886824?receiver-name=Name+unknown
8	\\xd31e3f48cb5318906dbbb7948326362f41604c7a728323230ae82aa995f27400	payto://iban/SANDBOXX/DE474361?receiver-name=Merchant43
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
1	1	\\x4e5560fd6aaedc6a128debf56db7f43664b46eaf7a1707c518d899179a3d7cd4d3c7da4e984a05978144f9d14943fa4a1ededd44e4be39ef34a1d81afea70050	\\x08d3af20dd4f3192c2b79040c703b7d2	payto://iban/SANDBOXX/DE474361?receiver-name=Merchant43	t
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_contract_terms (order_serial, merchant_serial, order_id, contract_terms, h_contract_terms, creation_time, pay_deadline, refund_deadline, paid, wired, fulfillment_url, session_id, claim_token) FROM stdin;
1	1	2022.228-00C4509K1JGW0	\\x7b22616d6f756e74223a22544553544b55444f533a31222c2273756d6d617279223a22666f6f222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f73223a313636303635353431387d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313636303635353431387d2c2270726f6475637473223a5b5d2c22685f77697265223a2239534150315a42414e5645364d344d445846545056445a4d36534a4238564e4646384247464838525632434846364858464b414437485954395443344d314351473532464b4d4139384658344d375059564e32453946485358575441335030545a544b47304d30222c22776972655f6d6574686f64223a226962616e222c226f726465725f6964223a22323032322e3232382d303043343530394b314a475730222c2274696d657374616d70223a7b22745f73223a313636303635343531387d2c227061795f646561646c696e65223a7b22745f73223a313636303635383131387d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2233315234354a54474430354734444d443048515344564a344e424d5153564642434d424656563532594b394a3443344d43395a47227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a22365a475a4a5254353159514531503535444235504e565a39414d56465753454348444443534a4753344b33304a454a3059563630222c226e6f6e6365223a22433053544d33413746564e4a4a383545564b565148373035393548534e475030384b46344143313733475232454439414e4d5047227d	\\x00cdc96040fdb55b71f39af7132cb8d53a818197207e1160a403edf2de1588e579dd07e454b85706ec6df8f07fcfe773dfc1a5861f8eaa7b90e20ada26986c50	1660654518000000	1660658118000000	1660655418000000	t	f	taler://fulfillment-success/thank+you		\\x2ab6dd3d3015a474e9342c0db4bffaa7
2	1	2022.228-02W6JYRQVATBT	\\x7b22616d6f756e74223a22544553544b55444f533a302e3032222c2273756d6d617279223a22626172222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f73223a313636303635353435307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313636303635353435307d2c2270726f6475637473223a5b5d2c22685f77697265223a2239534150315a42414e5645364d344d445846545056445a4d36534a4238564e4646384247464838525632434846364858464b414437485954395443344d314351473532464b4d4139384658344d375059564e32453946485358575441335030545a544b47304d30222c22776972655f6d6574686f64223a226962616e222c226f726465725f6964223a22323032322e3232382d303257364a5952515641544254222c2274696d657374616d70223a7b22745f73223a313636303635343535307d2c227061795f646561646c696e65223a7b22745f73223a313636303635383135307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2233315234354a54474430354734444d443048515344564a344e424d5153564642434d424656563532594b394a3443344d43395a47227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a22365a475a4a5254353159514531503535444235504e565a39414d56465753454348444443534a4753344b33304a454a3059563630222c226e6f6e6365223a22514d4235454a57593446584a46504b41335841594846465757374b39454853483734374a41334b475147414b544b4b5931363730227d	\\xc322b4ebdf16614d1c5a72ba91989486cda1e26b02ef26d105f71bd952f2f22b9f798dab19b98bf191c662338f571a6c295caf24ef961390262b67f697a5c7c7	1660654550000000	1660658150000000	1660655450000000	t	f	taler://fulfillment-success/thank+you		\\x855908c98bc7a7905ff2ccb317ad6503
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
1	1	1660654520000000	\\x00482e972a0e5c2d91efad58eb2f298fa5604f7879e9be37657061e6fdd5e53c	http://localhost:8081/	1	0	0	2000000	0	1000000	0	1000000	2	\\x81494bb48a83f0f03d5d0c86d1e6cae6b2b3713275415be99e113d1ff4eadfe4529cc7fc87e739ab13f1e0c9f0d1b8c709dcbe5b11bbc0f2626a5e8ce6d4a202	1
2	2	1661259354000000	\\x00ffd8756285c382ec9c7cbbea48a2d0daa35ac810a8d23f126ed758eca99b8c	http://localhost:8081/	0	1000000	0	1000000	0	1000000	0	1000000	2	\\x585af5eda8b3f8b06ba72dac11f599f6cdeb4996814c59096b018dfff955571aa2bb3366c4fdf4a92e56b9f97f92db2483d5b6ecae4b8eec1e4d4a767147b20d	1
3	2	1661259354000000	\\x08cbb6eb28062d0ee4ea289196cd77b6fbc825bc6972624b88c5512be2e55fbf	http://localhost:8081/	0	1000000	0	1000000	0	1000000	0	1000000	2	\\x2bfa4363fc9ef8a7ce881760f335892bdcbac802c028b8ce4ca78c8cc153b38fd9d6638cda334c0b3f411c0c717f897eed6f0b3c0370e8655bf3e47aec765305	1
\.


--
-- Data for Name: merchant_exchange_signing_keys; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_exchange_signing_keys (signkey_serial, master_pub, exchange_pub, start_date, expire_date, end_date, master_sig) FROM stdin;
1	\\x187042cb50680b02368d046f96ee44aae97cedeb6516fdeca2f4d3223094627f	\\x811bca6bcbe1bfd86f768d8f5917a0119f9006bac645b532ac39076b6e540453	1675169089000000	1682426689000000	1684845889000000	\\x2a5114e54b06bca1ac06f218b69dd18c418d0b09dc73db5f44c61c195515d6554b5ee765c4ff151aa9421a2b0b13e934c6f26ba2fe11fe12bc823a4f640f5c06
2	\\x187042cb50680b02368d046f96ee44aae97cedeb6516fdeca2f4d3223094627f	\\xc32561194b4b6682cb7029e149cb59c85de1968e440502f57040754b2a678892	1660654489000000	1667912089000000	1670331289000000	\\x7264213ac164de65e186b021d57d7cb94ec27245ce25c0caf460ff9dad3463d213f644235699fd4cd0a4150f5f3d92c99da5d6d4d873ae93dac4407775bb6d03
3	\\x187042cb50680b02368d046f96ee44aae97cedeb6516fdeca2f4d3223094627f	\\x70dccf9873559849a59c15a45dc39949ab2b6432936a14148d0a8426b4ef4230	1667911789000000	1675169389000000	1677588589000000	\\x9a155de882455e0bdb4f8dc71954a88eb6e8c318f3fc2a4015a33dd682c23211fd7877544e5b72cb4e1cce17fcff876abbf34cbc1720ce869ec9d159d02cb900
4	\\x187042cb50680b02368d046f96ee44aae97cedeb6516fdeca2f4d3223094627f	\\x50c01d5134ad469925ad877b9d6866ae23b0655c41705b44880b2ad4e69f946d	1682426389000000	1689683989000000	1692103189000000	\\x08c294b061c552a32f348aaba6b55d03f0d1c188be276e8f3cdc0e4599fd714730e25b91a785110240e5fa9e8cfc6b2432d27fc68d1d84f5ab2e083a42fa5a09
5	\\x187042cb50680b02368d046f96ee44aae97cedeb6516fdeca2f4d3223094627f	\\x92b6657d3608b9e13fa32373bce1aed54098deb20f173765179fd32b3e7aac71	1689683689000000	1696941289000000	1699360489000000	\\xd10e81652ef36461c2a69d6cf00a2d4628eaee995b63aab78147a163e76e609ccca4cb28637b76e87f7b2f2a0309bbd87e093b9e7e39a0a264e237ad52d0570b
\.


--
-- Data for Name: merchant_exchange_wire_fees; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_exchange_wire_fees (wirefee_serial, master_pub, h_wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, wad_fee_val, wad_fee_frac, master_sig) FROM stdin;
1	\\x187042cb50680b02368d046f96ee44aae97cedeb6516fdeca2f4d3223094627f	\\x21e4a5e9d5d17432fa0b1f7a02f8047c7634c1053d6aa1f6456ac134caa8bbf3da7776a78f85636af980472afd166b4edad654979a89d92c49a4ba992a7e3571	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	\\xa44fc10beadfe76054b7ce38d899df6269da7e291fe99b668d57165b9e50400f02d9a62ec0dc11c85b685604e20d0352fdca034e2ed0e1e700afd23c57ef6c09
\.


--
-- Data for Name: merchant_instances; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_instances (merchant_serial, merchant_pub, auth_hash, auth_salt, merchant_id, merchant_name, address, jurisdiction, default_max_deposit_fee_val, default_max_deposit_fee_frac, default_max_wire_fee_val, default_max_wire_fee_frac, default_wire_fee_amortization, default_wire_transfer_delay, default_pay_delay, website, email, logo) FROM stdin;
1	\\x37e1f963450faee0d8a56acb6aefe95536fe65cc8b5accca1924c6093a40f6cc	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x0000000000000000000000000000000000000000000000000000000000000000	default	default	\\x7b7d	\\x7b7d	1	0	1	0	1	3600000000	3600000000	\N	\N	\N
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
\\x5953e7ddd7430ba42c1a9f121365e500b5314d8bc2813046338abab6475a9cc9	1
\.


--
-- Data for Name: merchant_kyc; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_kyc (kyc_serial_id, kyc_timestamp, kyc_ok, exchange_sig, exchange_pub, exchange_kyc_serial, account_serial, exchange_url) FROM stdin;
1	1660654520000000	f	\N	\N	0	1	http://localhost:8081/
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

SELECT pg_catalog.setval('exchange.wire_targets_wire_target_serial_id_seq', 25, true);


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

