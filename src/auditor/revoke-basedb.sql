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
exchange-0001	2022-08-11 23:06:00.102085+02	grothoff	{}	{}
merchant-0001	2022-08-11 23:06:01.190116+02	grothoff	{}	{}
merchant-0002	2022-08-11 23:06:01.583736+02	grothoff	{}	{}
auditor-0001	2022-08-11 23:06:01.726936+02	grothoff	{}	{}
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
\\xbcdd74a27891f109afe27e780c83c03c02adca8b6c6df10c094498538c34afbc	1660251974000000	1667509574000000	1669928774000000	\\x672f96a79906416c79911983f7f421ea7601768c5682b00c0182e6127c394ce5	\\xaef46bdc9c4d567dbd397ec55797c87379aeee60d6756af2c0d32ace59e32f0afcf671521ad58c69e92b2e06c6049f01793c7b539323c438483be063abed8f00
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: auditor; Owner: -
--

COPY auditor.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\xbcdd74a27891f109afe27e780c83c03c02adca8b6c6df10c094498538c34afbc	http://localhost:8081/
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
\\xbcdd74a27891f109afe27e780c83c03c02adca8b6c6df10c094498538c34afbc	1	\\x8441fd1913c230ce67352d8eb45d6c172a1b5e5855d8b46b4697557670d81e8dad19fe10cb06f98c00112665d5cf514100ff77d7319c87709f638c1a91092ce8	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x0678b2516a6a03a07d769bdcecf7a468774ffd8d9fdc71dd9db51083b16ec263f2c97333baaed167625c522e0b6498f54c4f522a1e78d307b5b99550fdb12e8b	1660252005000000	1660252903000000	1660252903000000	0	98000000	\\x35290936b3298c531f7663cc352f52328dff8bc55a888c778a6a5f666ec72229	\\xe1749079550dcc6f91897dcec80be08033963a340b41266d8bfecb8c8d2ecae9	\\xd50dc64ca5b7862a12c155e61b64594afc040a31a2be906a362afdbd8aab7b3a5170546d859add936f63fe8355da242984643faf82de20103ab5eff7c78bc606	\\x672f96a79906416c79911983f7f421ea7601768c5682b00c0182e6127c394ce5	\\x206ba860fe7f00001d59ed840f560000dd12aa850f5600003a12aa850f5600002012aa850f5600002412aa850f560000c09baa850f5600000000000000000000
\\xbcdd74a27891f109afe27e780c83c03c02adca8b6c6df10c094498538c34afbc	2	\\xd7b5b06be021d66ce41c6560f4717a47aa0b555d40e5791a644bb0586713b09286338aa317eb152d53e5f01914f565c98294bd0e1c75a9844760606674fd4a07	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x0678b2516a6a03a07d769bdcecf7a468774ffd8d9fdc71dd9db51083b16ec263f2c97333baaed167625c522e0b6498f54c4f522a1e78d307b5b99550fdb12e8b	1660856839000000	1660252935000000	1660252935000000	0	0	\\x093fb1065ac13f3b0c67e86c7c62fd7a7b70fd2cfa8aff5124f90179d4107648	\\xe1749079550dcc6f91897dcec80be08033963a340b41266d8bfecb8c8d2ecae9	\\x2224d9bb7f6af8966c5f4eaf1041a3b8034a5ea9ade16dcae7a330da5d455afd94f9b2436372bc2c2031c1f5a7d8253caabb111ee71d44f2909cae0c0e71ed0d	\\x672f96a79906416c79911983f7f421ea7601768c5682b00c0182e6127c394ce5	\\x206ba860fe7f00001d59ed840f560000bd43ab850f5600001a43ab850f5600000043ab850f5600000443ab850f5600000015aa850f5600000000000000000000
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
1	1	16	\\x0edc8505bbf15aada1bc79b9ef37abefdc379c685ae92309f6b3bb3cc5180d42ab92c35980e7780b0a31649d043710b71c6e428d640c12a515bada5c15d1c609
2	1	33	\\xfb10e64bdf7369347f69f590870f4d4c1f35f393893e763be9e5ca16e3ce69aa9045ecfba5c72d0815566830ed1c149d31b9c6b9978dcbf488c9812f3a172c0a
3	1	399	\\x8d131404c33775eeb279c83b2f8a89b0c5ec17f69bfc61e5308836b80007b1ce0909241882e0f5094fba3cfde875ee6cb2bc8afd3885d8264341a7accf805b01
4	1	43	\\x91303fc99ffc4eb349a3d50884634458c5ec722e193cd7915470c0d61fe30ba3d1055a6f4d411c9c6a15c27961c17ea49f131b7faed8e64667f0d8637111820b
5	1	117	\\xc8728e301d44815a3e914ec0fa24141a9745b0af0f44000322f8dd8b17572522a433a7ab913d52f3fd2ffb5ccb1654226c4873a9ce54062fd250c59a05cf8a01
6	1	51	\\xe30280a983e09a60edc401d546f7f4c311f834f65d6ba789d29d66d6c2009fd33abfd0a95d333f2094b5526fa43e5c1b9ee73203936eacf940221423cbb9d104
7	1	386	\\x712e1aa79d52c3b7ad1b4e63996cb3d542bbb6df0ee5669ea830a73ccbf1d6122c30779944c579f1f9a21fa00a3304caed7f54e784fef0daeed94660fe2d6b0b
8	1	213	\\x7750a67c7925cf4dea6f2c82473ae701f2457237c182707e76957661a9207bfef621144b28ffac6ce04d968ae614b8889016b5e70c82af55238a557f914d0908
9	1	188	\\x82045fdc85b6bc1eab3ed0fa364f2826c0cbbaf899d542e5c4781796e57a17285507347cf58fdd4271359b44b1a4515e7d24da0ca1d80811c0e0b061418faf01
10	1	194	\\x88e1d461d8137386b6b95a9be109a346ff0eea4a9e880ce032abce74e0750881f7bc5d6f552c0ff633a8797ae22d98848cb433815d49754052217e023acfdf0b
11	1	171	\\x38747f8c017456b849479f5539fbacfb89c1e5fd7571991e2a92a6e3aa3d1cc67216f7b4399bfbfed5cf5eafb1a83d34dd1e92222b3f1e6479b149fee9740d01
12	1	204	\\xa94aa9b2262d4815c0bb81f8d523417efbf400450daceccf6985efabc3c4cf4e2af0dbdb0f2c6f7121b67e350052427ecab74d67d2e0b08347f8834aca29db01
13	1	224	\\xd304add810ff4a3601e5b43d90446fb9e9e44b697f5d9c17a533ae7030aa7945cacf2f2eaabe952bdda043bb7f2cc7090b33600e8ac6a8a7e88635e8c2947807
14	1	263	\\x5ac0a957a299aa06ce9abfde927a5426b1aee3bb98f3380b7ea2607dffa84887135751db0c83946451d9fc7e1855036756bf57edaab96d7fe1297546e2b74e0a
15	1	248	\\x811d1972c277dc3ef10dbaa43d90c1a97f953aa720a4a0789edb552bf257be76bdb5e6be723884fefb1fc38c0dcea0958e87c31a700b2ebb14088335843c9d05
16	1	310	\\xbd272f0a01b275f3ede018a4dca9a2a46776be4ae868487c812e1ca7ffc4493331a79334b88a5a89d55583bc62062127160e215e4659679b2f2364eb44d9ba0c
17	1	327	\\x9f2a661cbe2143492a44c6043f57b12ed24d0f6ece3366307df0b5e262f0424293b4da5d361af7a3ff34f94fa7bca3bf5a2cd12d34980a6eee9db382d8dfd80c
18	1	304	\\x1a5de6c44821ecb35be173f9dfc5b5723a3d62148cd48fbeb8b14f74eab80c0b137748c12b82758cb1e767fe7c899079664c022d1e47684d42a1646f44960804
19	1	256	\\x4e23bd5ff742a027f3987f5bdb493331163e03648708434db96d68aa7ec9151efc7e5188dbcdd41b1f03a97747fb6d456356cfb21b6051e238a561b78a2be70c
20	1	98	\\x8f70ccca770fbe04f30921631ba082febb0a002b21570766c26ededc6bf4ffea221cf5bb53fe7de953626a4d5edcb33787bfd35af8ab1a11166ee513792c3c08
21	1	361	\\x8c3ac60cf64ca563eaef49fb3911b587fd3468aada1952876aac07ffde06f692c18f22a7de5dbd3be6faa484d0a86b65dace0d4fa01b1f68eb46ad707f492303
22	1	20	\\xd17bee01f58f5241958534ff7090d18f0aae5be5f22eb5c233faa276e4b5d149654c9a7cda33aa9a7b271b69b66357082ccf4185be9d3478260654ddd25b3d05
23	1	110	\\x3f9eda69d7f1cb8a69c9525e4a2aba8e36867d096feb2bca8b15d99fe151c36d2ec720269d28274738cf6ed43b7cdc6e466aad67416a477c5193078a3e99b304
24	1	149	\\x49497771ae6cc30a3747271ec7341ec69a8f800db713558b2c16aa82d660d6dd7354a454ead41bf656fa7bff453f11e6d92cac218dfeebb9e46ca7a75df1cd0c
25	1	18	\\x9b0eb799756527740783de8abd3d291080df4ff6c9b5025b1e182c0f5b69b8451bd41a32af35ff7f7a7bea94a71afd784586347893e9be634b14c091eaa74c0c
26	1	92	\\xe7963da484ecb925881119f752834c782eaefae891b05c5ea3d5dce9f0de3991d6d8735859d65b6bab8db5c61c3bc6e4dc1b8e447f71da6ff9f38d9dfef4ff0a
27	1	354	\\x1b0e13b16e4817aa95492f020e1da3c2bc0f3952c623bf67c74b17aa94d7c566502c39722b61728e0a68337c9a5b054c28216acbed61987e5732c54c4afe5e0e
28	1	270	\\x68adbf4b874604acd2b4221bc19cc3cfb5b7f1196f5cd2250f9a34378038e7764c79608453827c530dfffa0a2fac3dc3f628bdf796ec958244b7527f5d54bd0e
29	1	413	\\x76c856fcbac8e7ec06fc0924c4d600d302bc3b1808f02bf2ad9dc0c4d2f9f681a8d2f030c4ccc00cece64a0469acd07d096033b4ac6cdb63c8ca1c61a2687006
30	1	296	\\x314680a5bc8567a3d84f0fc10794eb0cf44f2d5d7efbaa5bbb83e37ced0ed80bf8b6e227d60b58c51b0e02eb613f9781bc525de56e5c1c942f2c77bf34d0a708
31	1	19	\\x0deacf6ec75753a4b695c2a31e3bba907a8c98ddcc04fddcf1f344079e23b4129c84ce1f9ef83372bdba84325f936e59f0a42eda1112e245eaa952c05c62a10b
32	1	97	\\x6c3a0a1580a7cfb7f384fea8620bb5cc5a754ca9c31f7495509d970963613a6f009d1604447b780164d5d64c329d01e329616e9983564ff4017b5fb8b2acad09
33	1	38	\\xa2eb6bda77bcc520f4d7ca535517e08587addab9a739ab0803e0cc525ac694aa73f6ef34090ab1f55c5792d81e2f84f073b7ff01956ea015dbc796e8f9313806
34	1	362	\\xd185bc51a066c618b35b4b0228d868dfa2ce3f2fe375f0a4c5dbda1e61198eaafb6b7985e3e0a7ee794dea0152e2b231f04dad1e9190647c85bb89fe869c9403
35	1	14	\\xc2c2d8cb3d3e8f3328043b18b52a895d0410e99968005cfed186e403fa8fbf1319bb857c31baf8a0645e825b4abc02f496ebc65d251918cdb21a88557888410a
36	1	383	\\xf9931bd6b341b0b9d748c3a4db74b16e8a18e52ba73ac2d24aeed62f79a9597f618b75b10a57d5a16c3325d59149b01c23177b697a50ade916b5ce4fcf46670e
37	1	72	\\xd404b22f09e6d47ca3ae0c92edd7dc7727203bb515f9673a6697ef4cf5d0008453c6ff754dbf17e9d138600452341ed7d3fe0ef7d05eca9716c6535c513e2204
38	1	208	\\xe7955263a9e36ba3188f0965313d757eb26a0d185fc52142e371f75f1c3dbacd3d44cbea3da8997650937d90e0af06f56b12164ad465c3129007a817c1a6ef0f
39	1	273	\\x6381077c88c4745837233f97bb4fe4e0e2a927621b2b20a6677f151d1ed29d4e7a89f08e07f716543d282174f896a6c1830322b948668ea1d97b7bfa9c5e8102
40	1	319	\\xab66f647160f7d82e49d052e21c795f8b0ecc60b0b9047db6459666cffee0b74d721854c6e7252a2e3431ad363140a850939f6d2bc06fbcfd129597fcbad4903
41	1	280	\\x5b4bba35956fcc923618fedfe631e22d153bc6fa7ccb53318feb00328f6b8a6492b5771eacf79488620f09b4c889fe80f01c4f4b83b6438dd5b711b03d244d05
42	1	415	\\x6cba0e5b348e4a26464688114dac9bf51ee0765749d3e7f715bcd1b93c441d1705eb93998372c767c90a7a0b7fd4cfae7fb2cd91d7f4efea2962f0bdb6d8e00e
43	1	26	\\x81f4a3d09c9292d2b00be72675c4835673e8343f74da22bde20e42818b590c8e44579e9a37fe0e838d35e7be4f553507a776834402252512dc746e5b1d078705
44	1	391	\\xd95317f30f49f95b28e9363ef9c3fe446d48e331b58a33bdd90d16466aa1a41694385cfe3076a804ea0b68133aef510a0be50819e8a7be6b76006d4fabc63208
45	1	180	\\xb36ab310034bb29ff688edf09df38f9b9353e7a14be062f11727ee54e39a519b151ff0016ec01b720731e26e354c5a0ddfa8a139c6705d7b79269521756dcf0a
46	1	411	\\xb8b0c0ad888055bd3822d4365da34b7e7efa0a5b47ba3233953b344d1a08526dc3ca1486e01e22ec44e373cc1e268f64911b316ca6164259858992d4215e2402
47	1	359	\\x7bc70a79a1281012c7ec775e3063e53404473765957df3157b5d0521c5e79590bc45640131dbac47cb55d77a0d7ed2ec605cbf8f47a226f77953582808047f0c
48	1	239	\\x4e0790ab604727e554aca82a36205b6d64e2ff8121acb1f7fd5dfde668e1c6f2b6e61038f348ab76ef9ff6d115e2a0cd29885445a8f43dd23fc5309e57704b00
49	1	66	\\xb7b7617fe45f1e2b6c1caa8d84eab6f7ac75b56ddd5109bef79cd14281147779060cf806a931bf139ddc019200f5b966dfbcaaddf991fceaa2f3624ff9e2af0c
50	1	382	\\x1564ba7fbca959175fd6f7bb52c9cd0c42590d703b87f88bf83461dd9bcc564aa1a16051b380530675c5e9be684bb4d9199d1e35b19ff0dfb2413c51d73a9507
51	1	153	\\x3971a94b5d1201569a95c6d3da4411822a8df6dc11128d6eb00ed56decccf088edf6fdd99f2d18fa8fc0934707cb70a18e3e2fcd548b0e5a0cd79b16609c790a
52	1	220	\\x86f6c99db8f6a76ff7764e496989330430af1e06b2ad5f05154d2913d74f429f98a21c3998b4b55824cd867570f15ed9787b85fdaf84caaf3bd59861f5077600
53	1	423	\\xe24985badb50740e6e65a4c15619f9051bc373145932c4ab1ea73e45a63a9f4d867f7c6a544f2ca0374c3119ed22f22efa1133bd34589709fc1fd57d18a9c707
54	1	259	\\xc1928fc8082d67bf599396a10908a263b3e4b7ce6ba0d1acdfd9f93e97a6f46e931290b70c3de7cdf042faac98768f5a4893e00e51cac8c459bd1f102736a70d
55	1	283	\\x7422d7951c55ad6903f877fdbbf4acfc4d2a16d8255af6ea07bafd5e19ce5fab6da78445af32cdf452180bdcdaf50f9e7425336779b1027ddf2e0fa0b90d3f04
56	1	269	\\x1abe586be1ed8f121573403102c44c4a962828f83766a8019242e351e47688bec8bef65fa7e2ae6ca0eb58493d38883e8d44de047b6ed453525b54802e082906
57	1	157	\\x7c8032f182733627134368df08dfc7052a07dd0ad2919328839dfc2111f0d61d64f5197f780059f66ae962736db125a90d268da98256289c3b83ede12098bc03
58	1	240	\\x044e9ce045008da15e4b658c7474e068724397fc54ecc25cc1db12dcea0a6138dc302e054c5d808affa475171f2bd8a1fdbdf5dee03bc2f7a75f0d3644d11a00
59	1	267	\\xbcc79bf1cef2cce3045c62b8ec73fd86e109db740bf8d1ee8ee07f0f1d7ccf7b162c5cb3ba6a06cd04fe790ef33cfd3808529c1e6dc220cb35f059e2ab467a05
60	1	196	\\x09abc0bcc926f50cf0f35d079afd2b791933c307fb51e252973cb378065c3e08ac0319aa9a4827f57578385ef33780677b960046c492310b0657faf2c324e80a
61	1	236	\\x94e61cb6bb269a7c1646eb2326d18c5885b1137239e6f078a6c1f1f7a3f8a48a0c5784f8f58c67ebc073c0745acd27794c254754e36c07a1618f935cafb0c608
62	1	294	\\xba063965fadc83f5d425c7609fafd061f1c5b8d4eebeb8f4b4aa8c53b61ea4f582b44fd446d8cee08da4c1f374a851be6a3e760e32d58a64638f7c7844d9e60d
63	1	370	\\x3d05fa167eb648d2e3f8dcfe9d27a851e71f0babcfb70cbc181a6cf370babed1035a7163d2ad7ea57aca92ea8ec5de384738198815af182da2788a04133eb605
64	1	218	\\x1f931623a3fb3f55d9bc3f4619ce58976823f74e3612f42e227d7a60dc6e6938f78eeabc1d703d1ce02f7b54b8ce13dd6c565d625d34c28f59dde0cc4bdcd804
65	1	214	\\x6929bf680e9570174011f81a8ac3126dd326dd30bf3630eb73fc7cb26a4ed109c9d38a3f340f76d78a62b1d057049998e8958df9c7e3b150924afa0bdf37440e
66	1	222	\\xe80a115127ad4dad6501224fbb5ad437bd869b7874a9bccbe71ce2602873236364ca3781dc1603846a90d8160391ec4715fd50655bd8112fd2490d647f9b2007
67	1	217	\\x486ad81f56e23b839f7763d43857b8d2249895a702f35906cac06cfc4135b56115172cd11b40620e422c6b3c2eede2b8ba7b2be1fc263140a2d77aad77f47d06
68	1	119	\\x203c641d0bbe495cb34528f2af3bc00b3269a5f8d150dc0f0edf30f5192029c7120270996a7bfec713534fe8ea2e63df316bc216b1c7ea05a81bd1b6cc65840c
69	1	190	\\x5333b2e570cbb39879540fdfc0abb55d69c49739f94bc1fb65b0c059cf21092339f4649b336afd2309d592b72dc186f17a7aee7917365391670c319d19177503
70	1	46	\\xa613d67ae48a78dd78e199d11e40f6e2276cd1b0ee7da36e861b5bea0bc421525347ca99317fa64e9a69517801c93429f92d3d18fe850b813912d00ea718b20d
71	1	290	\\x8aebe72125fb7fcd0e34cc96518f23f69c0819c0a640d4469875283f08728b5a7b7822290e7ea7f88d8a22025e5e40271ab87e14653329abebd0d44a85817409
72	1	71	\\x517d6f5f57bd1847f30764d81ede75145cfbbb035ecd1effcfc38c171794f85e5a0f284b97796e77e4f312caacf285168fab89a7df8393757dcd3fa6d5642b07
73	1	88	\\xd02b95ede6a452b52dd3faa1529bea3d76f1a79c3d1c928f8e86b9d613dd59ef495753ad695e13481a140c6ecff2c45eaf9706e31bfafa74ee3d7d80b929e906
74	1	126	\\x096d7b2f910d84982332bbc0cad9560d6c4816d01c48b44242de34134b6c63cafbe210f0bd2f7c568ff77a4a4d00f93aeb702c32f2c9c9df09a6cfb310db1a0b
75	1	151	\\xb60ae7c95194c9dfecf4b5251315332b473cfab43ce13fdfb83814494ab1f7b459871f60a376f1a095ab770b6f263bddbcc039fc780c5dafbddd6ea21b046e0e
76	1	421	\\xde6cfa9eca2a583f5cb490184f3647ef53dca0224fe899e70a78624fd93c4876d2764af7a7559c968b3eb44a5575782d4a3f738d314d7ce7483fc85c2feca60b
77	1	242	\\xe77d869615c278db6af6af5608ac93109cbb5caebceb45b6fb9e90c100e69242b7bce3a232d452b982a00ade84822745a1219a4e573dac4627f432025ef12308
78	1	175	\\x8e395f0c2e9cd42b232aa7ae625a8b9f416f174f5c0ec808cc1a6a072d4aba38ea1281dc5c2ea5d0994614ce7751c60232354f7dd22b511354388bf2d2eb220a
79	1	187	\\x328b69684f6857da9895c4b08103a84f0bf99f20998821c6e24cefc51fb1f87173b9a774a64d97fd53f167b15f88fed953c9d162e23f8d9e65cb9eaf38f86506
80	1	136	\\x6ef067375f80672f03ef06b4d3e4ce52384931b25743f42bea017844042a6f4076b010097d2f09e4b6fc9ac55d33c6755589c911fa5c6617403ddbbc97b2770d
81	1	15	\\xf03e2d6a535f893eee4f2b6f8ba445700e787a254e35d4b80efe26f1de2cb4b912d34a57c318852e0332c29eb17491ecc190ef5597e64e56168aefcb64aea800
82	1	49	\\xc2f5ec7d5ba44b9d65d45f7336c251237972650633dc2abfc4f897b364779f6a9071cf158b130c607b9ff7e95686cff098d410e8e8efeb9e0558df519834e107
83	1	123	\\x5d0f2d6806072b41e1b09bd0e08221501b4c8ee713877b65bb833bb4be9f75550630d117ea7496183803b8cf326bbc08a66121abbc2cdd2ee15d730222b15e01
84	1	380	\\x6320d5c21143d1ed9e4689b77e17c0789d9f132c123c3f0bf9610b959a9c0a75fefa69c0a194ba33899c598d19149de73b4ff459288d4b0051c18b5fa1d0f104
85	1	223	\\xb7c0451200066450d99b5a4e18c435b7d84393f3c37d794797a7a828e1419a989782f6536c7f35efb038584443c4ec89d546c58d2c7b4e5ed2741f828c5c9d02
86	1	114	\\x32552fac16985f060d7509746e9607ef5c90e733d73f14d619527a83aa3f3f5d3476e6222c5003a9844e26b9dcfde0df7321ae423e210e71ab9ce944d9457b09
87	1	332	\\x1be9bc2f58f5f98dcb63a8d1c3f6548fa25bbba9003436cb4a4c008b061143b72d16f31b05f939eedee37bff572635ddff875ae07df2da20e7a3dd0432e19a06
88	1	40	\\x8a44d0f92cf88925cf12899ee1d8c229598f2d6ab718acd91f664f69e5c043b9794cbae470deaf47b832998c182d0f1f2d590b584c98c38ca07f3c457207400b
89	1	28	\\x0daa2556f44e7a84eff4dad58b4b793b4d28146645cbd7b2dfa281ba2a1aa7d964ca863efa30dbc5fb9c361f18de180512abfea9bf577cc4601c1a0637ba0407
90	1	408	\\xdbfc62fd3b94e3ba13b9789b81360650644566f3b9126ee7ae8c4960ba0ac903eff2a6cca8545460c4b083afe38bc659d0b5a2059031e6dae931c263b46eca00
91	1	330	\\x53e1b851fe4d8d8dad8a67deb9b9150a17bb4aa98564839f7f957e00a4e9b21546a696e47eb2ec95039a86d84d4e3baf54902b730bfa3fba6f7c82e866e01b0a
92	1	162	\\x9a7dfc72b06e58095c151b0707e52a0c921f0c47dbdc901f7b4f7b4bff54ffcf093be70317299440f60eb02b0c03a19009686c1d07dc4ddc7c9fafabd4db1508
93	1	324	\\xb815d7e9d6ba6d81225764bef2dafbcd86ce1a7f0812c881c27cc4f27fdde331fc6716478acbc890f1b27217fc3c3cd77697783e250162b425b753415bfb0701
94	1	275	\\xe85e6b8be1f5473f89bd5f3f2d1ec12631e24794911fcf76a3ee81fa212069e7f74bc1e5439404b78b3afac3cd16c7caa48723414345dd7c6dcbf137c1fa6401
95	1	347	\\x085219db015a705c6d58fc0b51197d3d0f46b7fba9eef364ff2845a24cb8863ea2b63229b39bf4acb0e06d8466b66c50e20589f2d9a8606b1f1b290c53da6e08
96	1	133	\\x00ae1fcf489ea4e13c838fbb3e0a759f468f2149ff4a477e6076364014d53e44d31b2d1520691a63bb4290f4406ddbd3fbd4d7da6e2f8556cfbc47e7eedf8d0e
97	1	56	\\xe6360c5efaebafda941f5aa0841c83c5b574944da730c884db7e65d2571728a7beeba1b2dab8ab50df24503024c6cf9435f243c0b411e0e360cec6941d5e2e08
98	1	285	\\x3bef2b38f70e9bf47b524e19afab3417c7c5674adb9e54c80ba3898994fed15fd32674914c451c29087da131f777dc4fe266891bc1594397575368fbbdcae009
99	1	1	\\x1192740e01af574b937c971c31236a4699c4201a6847f07975b154017eb1ff441d98bf1bd642f424a0d2278861b40889bc37edc4cb1330e12d175f94510fc504
100	1	331	\\xebb2d659444d702482c46381f85d4e09aeb8a18c15938bb1c5594d6a1eddc6f896faaba325af8972c3cf0a7f0353b3fa88a0a3a60b31915f09d52d89d43d840c
101	1	389	\\x13a9c94d9bc2a40c31a1e9dd07ce4703a6e49331aaa5719640234a068fd767a3bfa4907c1b945df459b24c02542c899c1416aa6685531874161b52c36e5c3a03
102	1	313	\\x809b336b4f77d1cb76bee48d49a586adc236ad154fc6facd20398c302c7d4b5d9fe1625a2a3e7958e1a9fd8ba7c16e752f7009c610f44a80b4532f32b3c43e06
103	1	160	\\xa7a3490a4be5e4d37d848d6f39dd91dc7fd84aaade62a746586811fa0b498ac1e91a598d382e792f68ca4a651de41431ffe82fb8c84deb80cf99d64f7307f203
104	1	164	\\xbf8286cfa929aa66c6f2424e032f1357fb69dbca922989d277c1f0b7f5341c0bf7158c402fe7ef578b7ddd181d1c32a939f58fb3fa4120dbe65ac1780fbd4002
105	1	385	\\xb5398bdcc85676c6b07aa123b27e525a14f5c9111c18b7c4f66382e3545e48df8344650bafa6c55dd28b8960386641d843d3ff3ac854925632c60d0e90b25a07
106	1	209	\\xf435d26f6795c2da7b5c585ebb16c82196f4d17def36eb0fc878592e0ea6216095656ac723a74a7ff1ef8a4b190b0ae7ccfdfc2bd49d62414aeefd5280e32500
107	1	281	\\xbf2b2016196e7c73210d331eb42f71e1a871c53c2e320776b623493d78837b49c709554f853ebaf6d294e005155de70578b88cebada037a6a865c631b49e1e0f
108	1	318	\\x273b62465280c34acf764ea1e4c455b990955578bfc4273341501273767223e251d3c53726b93d2490b1af38a386a67ccbc2cdc7d9fb50f095e55d49ba5d0f0f
109	1	101	\\xb0d811868d29f57ce20d30d5aba8bbfe318e230df5812e47fbc63983223846d7370bd1515bf0016b067b9ff6679ef56f34f02b573cb56e623c6d56e69f27e60d
110	1	10	\\xd3718c14ad067a318c655253391c7ea3f468f609c2e395be92c88be4bbd81ceb6981a994f202de6aa67c1750364ab1f34b5db94fc1942ec735b99257fc75ef0b
111	1	372	\\x2e660ef63f98ca43a4687c8bcbeded0a6c780446895ada0b9ecf5b6dee8e690701ac8b2f8de63c26f2eff7cc67fe24f0ef2c4fa45ad2d1b39cacf8811c038a03
112	1	156	\\xd0aa4da24a5a9bd578886b17b38fec9f466b225e1bd914a54c53af41100d27d43a559da544e675dfcd6a03d097411d6aa263b3470be8c8e8888463621ed2470e
113	1	325	\\x156321cef4b8b28fd25689bca42902c6f378358ad159ce9cd23950717b894479eecd597309fbcc83600d6568415958e63ec5c728159fc6fc3d8e97a4ce595d09
114	1	75	\\x3df10e0c42f56be6542919b9eef5a5e177328036b621d642873c9c2c83bbeee35a4643e93b31b6c6e186325a8575a8fa16e76e0e9bee87eb1dc54ec16dcbd009
115	1	253	\\xe9fe85d2331cbd102c665511e252c1bf7eb28f57c17cf68c86b89adbe247ff791a082fc24e1704967e0c4dea1a54193db7a061a5310e82d4ebcbcf0c912e1002
116	1	234	\\x38d32e3d9e1290a7e5ae7a3512ec381c2b8f26ab1726ae1e345b42eafc61dda3c90ddc8cdc26720547a61441d218b0da86b77281e58a8c73bd2bc810165add0f
117	1	401	\\x01d52df9eba288a61230030b7bd092714c9096583308973a977dcb4df4c64fc04188001e96196565580026139adf455ebcb01594676803f8d9baf6a969b94704
118	1	182	\\x11f578ce0f6594fca8f44c1f794f841dbdef2853f099252f33a63488ad64da6c2798227664623e782487317b7110b8200747f84fb3a68fca3ba8888ab9be0b0b
119	1	35	\\xb7225aefbab4480e795287b7bd15b93262aef15b29baa5a16eedb007ad6f80cfd3a80ebb2e43c68b3f10bd05283bdfa43f5b79af9012cb954911f2fbded31502
120	1	9	\\x8e4c45f4f1fb4d9884f54b85d241d9dc72bf32c8d6db8a0cdfa82c251b995f16998c1c2f248c2f0a66a60b942c45cc7bb6d6d802a26938297b4195772962f50d
121	1	189	\\x9c37d3a8f0b98eae87b60fdfc2867103bf87abe6baec2f56eba4f56cc559dfa4e1462ac4a020128bbd85c60a1a89a84ed4fe1d56483524ebec2e226d6d0ca003
122	1	353	\\x8de6f457b99f0f7e34aceec97169f1e21cd11dfbf97a48ac5eb2b9105df367fe52f6750077e3b5cb85adb0ac2ba1b8f48d849b7f0c7956dbfd7045ba03adc20a
123	1	316	\\x1c23557236e804086b4382532bc7be9d32003123e69d2b82e8332fcfbe0a76cf72c15f77ed04ce8d414d4a277b8d1d9cf282b1d61471a448d2616d75eda78801
124	1	409	\\xf4e0e1ab4b1aa709813959a15d2bfdb6259fa677a25f16402e8aabf8c52e687793dabfb20d6b593a40e9cf358b86aa175280e8ecfd7d997117cd9d93461d3c02
125	1	78	\\x78f5a2a605e8dbe478e9a6c5ee5cac4bdb12378e5d8fb58bdc9c6b1a6154fe815742590a6fde48458e6ac25037d22ab3553242c5a76e46b770ab9f090a2e1a02
126	1	167	\\x0bbcb49bacbd80c1fefcbf09ab9631b154d88859bcd0c87bde0313083da851edb37604e371ce9b16642089dab167caaaf63b6760a63182ebcfe99fe0221b9d02
127	1	63	\\x9d4f9edf4a15bb9dc0e6aa774f714c09ee2e591b8f2ddb2c6b78615da5b3d74bb0e6b28574fd8416b6317a84c162ceb38b94cb75b1e2c657a71423cd936a6800
128	1	25	\\x98a64d5e9d908a0bcbee03e1de6f8f7b2b322aa543cfefb3bcb2a6cb7fcfd52ce30549dc5c931afb5813b37271377776b00cff365b5ab5dde137133a8f7cfb01
129	1	45	\\xdbafac38435aa12e490a1a686b1678a5648c27e3889dac501ea05fbf2c2d430ae7f3adf14b6c523108b584ff1ac685e31658c1fa6b0306b3664ce95b283a0202
130	1	410	\\xf91de1cf54bef436dbecbd9136fc47da132e9c3349589543251e590c5f8333a128e5004f4d7ac52596ca3ef028695e3261935eb8d55bb31e3c702ef23d51bd08
131	1	141	\\xc53e981610496a6874d8c3f522e4d4664e0a0f12c5f41c4904de648d002326685f4e68fdd4b1337133d741ce3cb7e587aeda4c5a2a984d8ac9d63f420913890b
132	1	90	\\x3e2a90a32cf6d3def7e7c6b6516155a655c1aac449245448b2cbfc74ea3e26c138cff1444e70423f0bf4646f384c0e7fb9ddfbc0668476c56bc7bdffe0067d09
133	1	335	\\xf4ba73d881deeb354c0c3d1257fcb191e69870bac8ac846701b3f067c6be35e6abd0af28500869fb88596ed9558f20121a0e7535faf0aabd30fd7bd34f539f04
134	1	37	\\x99bb42adcd346e128940f05b237c145c6574a5880fe5f51eb50836868ad69e0bd2dfa7cafc02384df7300bdcba3b5f85d61bb16faf8b419ce28d0f5ce86fe90c
135	1	315	\\x39413226baa7c8d232afba87e261be9f75eae2ad8b0301e4b9cc8da138054c2a86b56b01a992ffc73e9e5ec2b38f8e3a7646d02ce80c2f24cb3ebbd95b1f1503
136	1	178	\\x823fc00fe7f15609b0c29c783761f31cfb33b5a491e38607c1b269aa869f962c2177b36969022e4985223427ca8d14048642f61529b1c58c3a701f656fdfdc03
137	1	250	\\x7da51c95f0867ae58bd4893a7dafe5a3834ed5a88fa589b29d9662502261711e0d671e44a99d6601333969536123d68b234f46f93e9bea8586649f6272f30b0d
138	1	6	\\x90e530d9e8da810c5a978ad156a6c852416b55bf042c7426b28c5739b90ce74b39ae7e5ee9c32e1e9070b9d6940f9b52bc02fad196f302b3e67f95f049aa1904
139	1	150	\\x001f9da2054dba2ccd29a320d592f41ed1a3122a8e1d53695ba5d84118daa4bf7f71c18ba0a982b9c796f91c897be8db79b775bf3cc46f95b9a39ffab3ac0d0d
140	1	152	\\x6b18d2ff4a7e753e918c718fbe2b1e07c8bf4cab715ec53fa08f65c69867790c4b42253a27aaf17d7ea85fc36ee1e043cc459db9365c313bb9846c221e58400f
141	1	232	\\x7fc28887af7bef9d1b93dd8579b8b914a70e20235d03159ea70d833beeccdd685207b1928c5b7d556ebeab4dac4d074b3111e7d1e0e6d651b2a7ad6f3d9d4200
142	1	115	\\x434e03bead41de7fa2f7f8ff1e350cb3701da4f3531dc62c860b0fb02849797b427a32065955b612642f6408370b836bae7e6350ae32f26ddb5863af4c9a6208
143	1	23	\\xa45c15dca93e45024cbebac1ceaff049201f619e71756ac204c5c4f34f1c0ce9488745a2761bd31f12a5e4f4d3e768434135a18fd63b0f87f26c2514d77ad10a
144	1	374	\\xdfab8cbbcc254134557a595036cbffc4cdc21aec39e64a00dec184381a746dd869e4d6b56b2830e171e627046df448fd7656cc4b75aeec7e1b4ac40bd1395e08
145	1	176	\\x710ff911783b30e68381ea65ed783b7022f8c6f8f8609c7382a90c3b989aa981d0f8b5a98ca3f69f53d4be51d2256f4a9373eaef28f51b99e7f79654711bec0c
146	1	197	\\xdcc5ec383af1949534571dfa7175ce783574bc71cd1286c818f4422dc5683dab472738498328ff978a20440fab7f58b64f3876fd546d1a79d191388ac220f60d
147	1	402	\\xec05fdf245f9e7010e3447f8e20461cd193fd43e508b4cdacf36e0c0ed2a8d12a0d5b7798361db217524cc8e8e824546856093afe68efb8d9a3ee95d2ac83d03
148	1	128	\\x6438a2e85149409adee971a14f7e2e511ee440c368c7a0cb88d33645d4b8aaffe35f9c5f561936466e6aed69b7a6f8fc30ea610277b2dd4604ecbae26087200f
149	1	225	\\xcfdf24a13d7d61422f33ba51b9789a6887ad36f1264fd8e4e00f906c11ea8013bc0b0713fe16fefb3a2fffb2433bf8dcf5bc4f0cbb03c54fa6bac319d59ed108
150	1	369	\\x2eb2d318b588e49ec3070a7267951e77764bc62f0ea67a5bd3aed7e6a22cbc94ff0ebe78e8d4402a4e8198e348bbfe84583ec469b0e07ed905833bee67a36c05
151	1	215	\\xa959dc72531232d22ee274208cbd6537a123d26dea1c4249c9748deb974fb52a1ccecc6c56e85a94ee3b7936baab4f9c60d4d2a9d0c158c37a3cc3e4618d2b0c
152	1	60	\\x3d9399a44e6d334ca92db81f4674b4b6fc2dc90984846e6debbeccb254e0e9aace6588af63a7a807d1a0e75f52dfb33317b2f327a88b4bfdd90459612bcc640f
153	1	148	\\xb957e6fd8dd23f94504ce194c506bf79b2502c623a8127047dfee518e6da685751566f1519ea34d8d50276214653c2c9ee18194b9157e4dee6f19d12afdafc0e
154	1	30	\\x0102d8c7a768a95b62ec87e4893ca40d27ebf57db38d8fc7de8f06c7609e69d417588c36d1b6dec89a9a77dac956cab62e1f872222723c344a1aed0898b65400
155	1	29	\\xdea19d7307566620f7a497a0a0e2c86123c8c5ce5bf0b61b21938663d3f47966dbf5c7af3b912c995295a1693e3bc0d610a6c7ebe175ccbb1d581593990b5904
156	1	134	\\x85a54da598a3533fde8696b2b600461f634aeb7c96eab7b890cd52bd59c7d60e06536dbfecfc2cbeb28695421e8baadb86939bf94f8e45c438943f37d470440e
157	1	252	\\xd0f5501a3c85cb825b0a2ec2977ce0ef467fce1c803fc5e7e463641d9ce3ae9e8e8877fa5fae0b9bd55d9435f9de492889f4157d1fe6de099e88fefe37694907
158	1	96	\\x9e5eb870e8ac9372bbce0b90bb398c0a21d0054d7b4ccfacfe67f74a2070fe2c3aacf0ec86cbb8741db901fa0c204da7e44012d4b893ebb8f21114c755fefc00
159	1	303	\\x8c17ace4c445284bdc142ceec67095963030bfb1c39ca45e71e9ae6c63fe3df1c6a7bb40efd7aa5421edbc7dbd53c4c9c72901663c06f9eb458e3e57d8ee5507
160	1	358	\\x989405f8b331c9d7f2f5bcdb8b984299ff56d4de283b9739a3985fa6c062db06b07ea6f1273b099b94d9fb7e23dccc93c220db69bc53a114781b73a14106b80b
161	1	158	\\x797a4017c3ba03259eefb050ce01de7fe0aee10f5fefc8c37754a92b45d2c105f4ede04faadc04e60137f23fab0481bcea8308fb1af827fb27642b2fee7b7d04
162	1	292	\\x6231e93a6b6ba628c417a03bcf729ae26a4eb24da173fd46277fa430bd42ee2b972583b210e644f8043b78d250148610ae57d6fae557ac47ab5601f433f1c00d
163	1	84	\\x99994d6c74f5c59b1d52724d8dda97d95089d3960741f5f04a223e98c35047d009e35f4a2b9f003a0d6b8d62f57486ec1dc5dfbe5f0038d78d55630da827340e
164	1	36	\\x57066b2a262deff8663102b2bd7e76d582ddebbade672da0c1302a44b23af0e33a7b5c5611896731cf7d3a4d83571ba8a315a6396a65f1c4a4593ea72e9b8a03
165	1	62	\\x6e8a0bf6faf44a0fd7940982b79be99dd8bbc3f118b369fb8358264be9c1b19e3b74e8cb34517a85e16f59449de5f8f8219ec3b57e3a55a8f246a1ddf3de6d00
166	1	293	\\x10d63dc95d712f4b93e770f356473779c1bd839033c4cabd11644a3b7e50d424b72a1419710cf3af08c7ec2a4d0fa9fae7a7d55adaa60828e52b946d50772004
167	1	103	\\x7970dd54481f300e87cdd8d59fb340419027da69dba8ac05e9429ec82fe4a1c0219d24c52011b9ebe368b271c5610a036cb53af2f73dc15f4e3cf74741193b04
168	1	205	\\x3c7ba9ea047b72a989e3ada54456e241751ffb70be47462020c5759cf9593da675a2b804ccf5d24491444cafc38060468fa85c33720a980ad39c31ac04bc6e0f
169	1	4	\\x16048d4dd7e490524e1b51c4b8c8784e27fe4032265c866de1122c6fc52e87d2619ef61f97999e96ca98dc2e94777c7eb8dd4fb1343c7a86fc1329096040e902
170	1	195	\\x92c0b8c5efded955cbd19adfd1128ebf15e702fdc11785a9ce1c98c5ee64b51f42a1f5cb21e969aa411c2b64425d578abde414c3a1512889005eb9df8ae9e30e
171	1	235	\\x56979d5f5596cb2969a8e4e3d65853e443786d8025f1cb1e205c22adac3592e849349b890872f03c9ea8025572c03ee59077c026dc103494c9caa83202e5100b
172	1	201	\\x813b433ff540c61e87a37b030227e8f988ccdcf6e5650bdd9e43a1f06b2726571b68ac43030b5c36d5d522fb6d0f53bfa8b352573d1645db908b0cf17fab5105
173	1	360	\\xeee680e8b5379c4f0a26820c2aa1ae95e036f2ffa3741a949da4cd5aae81ae5535235d85641ba541a90251349f605d517deaa056a6f31c716e8879d9ae4eef0d
174	1	108	\\x180aa5b8ca3a264fbff82d2dc47accb8831444f109e8485b5d264c8484be0e8d1f976a4f6e20a13bef46dd0b29b88b26910273e10d0f6a7fba97943941bcca02
175	1	186	\\x686af1b68c0f411597de7009efb5f1c45a049c629c5f0b5eaad9f7446ec27861a76821a771ff87f93f0e77652e06b0f33d3638395684994e009a607dcf781c02
176	1	288	\\xd4d866917cfec56fb1f2092fbc563633a410379cbebf464f7ad6c47c3c819174fc1241635c95c880b8ca6c09492244f4ab967fe3c06084fbe643e9a5efd79306
177	1	212	\\x329e4e0c571d631545047e20c031f44f8448d1a07dddfd322c7c5a46d0f1fd82fcb624a9e02a1509e998441dbacc5f7a4c5e90bede8454a95a05cb32c425ff00
178	1	143	\\x640380a28150991cdf2e734f1f6b492bd48a477bcafbf72e45cd5107ce1649b504edd894495d578b1ff5f207d25dd7f07c739faf7e135d2ef497141450b1590c
179	1	95	\\xd252bd15f7328b1bad9a52a928df50b672f5e998ce75518f225bce0df778fd25a6d2cd502bbffdf064ca924e87c0f52f3e7ff72ea031c4202f0128fec3c1820e
180	1	262	\\x894cbc6a2c718b0def3efdef8a4674df62314bd61a51e4295da11f9ec8c6dd7d788a3c66d736efba7a30c3e9a281e7690cabc3f1c36c92ab501b3ba2b8bf9708
181	1	412	\\xe827a0401b3ff3895c541720e87a079364f0f7e89359b4f333a3a853c77e5eff7979a76de5377d254dc7ef7e81d609fad14be74c27721dae97adca5a6baee401
182	1	206	\\xf8c597ac02232753f2e582cd0c789a31cee69dcde950e4408561b242573278f930925b7961c032cb68eca53f01b39b4424cd9895b046ed6f9835ab4a50b9600e
183	1	268	\\x7a2ce348a509672eb3e2b88166f927f44d8fdbff73c7fc69080af709c42492255f25e544ed34d35ceb468136a024ca119cbcc68bde1d00e7a05b099428b62504
184	1	396	\\x93bf8122e1913c976aa418165382b19f3f1186c888ab4d88cdb2fadde7d90b54c94b0935ac82f58332369fd66d8cf19ff246b98c110ea62c3210e74dc23ce509
185	1	264	\\x0123765df441bd2898c50c8df0f9bf226f674c3ced41509706781614579a22263748d441fd74a8632670ae084eded7b93d4239fa36ac93a14ecd06827e594f0b
186	1	211	\\x64f4531accdf72590cba735b63bfca421afed1451ecccf961f933f50b57376d4cc528d2f46106808502ecf99ce877b2c0a8480b43494fcccdf992d7948b2cc05
187	1	173	\\x53eae3d2590a1784d4f7db122802b0bec4d4e0e2f292ed192918fe1ce870947141681353b506024b4752d970fd334332c3bf8ec8b1281486b00b4a8699c5d50a
188	1	350	\\xffb4af489f4386bc2f9375a5e8eca21fb15e8ecba686c76a2f03bbffa29c3a80ecfde4df5b1ecba0d38b25e5d9f4aa87c64a9a63e8d9216f0d921cdd68662001
189	1	276	\\xf00abe239f8d3ec5f3868b9b9cacdebfbb3a21bd0e396bc2ed7b7bf43c8432a955a0d306ea2d7a0dc7b98f2f498e0e69418ff5abbfccbf1db3e6d7f3e70d5f03
190	1	246	\\x188e3d890af094a49ab858ed166e26d1e218650571bfe549ae1ed56f0186b893ce696e08af3ecae23cbd02c59224068bbba523e301e7fb940f70cd1beace9e0a
191	1	80	\\x135475af7e2ddc1a50a946dab155a362a07482d7cd576231e4e481ceb2217a68bf65e2cefeb7187a9d3f93aedb5ba0623ab3df0a5fe4abed9c5606fcef24020e
192	1	230	\\x9e7c53bdcc85f551b16392c359ab5a0f7affa5c377e228f80b82a528356c0ec2143bf521f2e57ae6b85af4d811c7110d3098a7cd9234e48dcf42217afe33760c
193	1	238	\\xcdc55900ae750ab22d3f280c6d588e70e163a24d78f1edfbc517fcc35694b1f7861dcb9c838af01ba8fc0d37c0e70fbefbb83fa0af94b66210664dd7bf50cd09
194	1	147	\\x1bbdf590f9cd1b5a99b4bfa1b6d3e15d446962762f08b6764fea6c341ced6ad9263053513d4935c13f87e5a459620a4672488b2003acddbc6a278ba57fc70500
195	1	61	\\x599ee83b296e0a03bbda361b988a004722ff9132ce3c94b766657131118e8acd1a64050ed764c399b797af4b991f4e36664f5680757fe7d05a94eff6586ecc03
196	1	161	\\x2c3f778693144f9977c7836db8ebd358c5cdbd44f859871f9707e20e700c74ae764c32fb13211a7dd8d4f10a1c1edd89c3feabeffeb8f0d8a0f95e3210e3d202
197	1	287	\\xa147bf9be5b60c44d53c40edebe6bad432bbcf0c22250fdb28be1796f2c9c8c5ff3ca65168ac107a43ba216ad9501558bf81aac5e35464f5676f32056e400f05
198	1	52	\\x59ccaad2dd3625edc3e5bba9b8343854ab51c763ebdb18257f51e53e63fdfa99883bbfb5a534832e4366e8a74bf254936e1569a08195694d38265122f76f8b04
199	1	356	\\xc731dd40653f6037af8b3be6777c542e967ad55dec85c185fc203335ea7eeab516da27691b884c34a34184ba8851fc998c0daaea93b560e36e10828209f5d203
200	1	198	\\x456a60332fcb0eabc7296c3124dd4eba2ff39caa7ea652abcc84590ec59a96796a0edaf10ed9dac3908e8d5d4cefa661b253b36ad07edb2f3aa2aa838f2aec00
201	1	179	\\xff8be143b91e0b524505ecfa5d0fc87a3fe1890c60c5af7561d115aa70db3649593db9084bbf3e39badde22446dabf2f7bfe244991cbaf5d693ea96ce3b9ba06
202	1	342	\\xf0f3127353c0b0e2b80d1d87b234909b4a6da6568cd37cadebf316db2619ded0832a93a400739f6242550e3d5a07f46811a98e21ef7ae4781c8481befbc72609
203	1	67	\\x7ae488dc93ef8f730fb61d79cde111afec231bd8b9bc8f774a85860b8f07fff2ebffc83267ce656c67efd9c544702de8d9466f65f36ebf27c68b117368ba0000
204	1	305	\\x43c84243a2ce5541f330ddd7271a227a23cb185578b82f88d4f89e9cdfa4524246e16eb5cd26c422db10e89f93658f8f90f7dac1beb7a40c49836d294269b500
205	1	339	\\x62685b055f8da05002a9a58239fcb2113134286050912afe6d3e126c427bff7cc4680eb17a5fc5ff01fdad8998aa34f03ba2a51e8c2d06542dcc14d53e120a00
206	1	229	\\xfa7bec56bca4f1c2f2c559ecd3c8a24cc9feae9de10061d7873380f778816ad799efe2ddb60f3e0fa2c9894e2d47cbab2ca89121bcba3737d75466dc793d8a0a
207	1	244	\\x293e76fad04013fd5a190301bcfb5d6ce0f5fd935bb969a5324603e8b43529f198f84b9c54c40586badd853b83bac32085d317eac552c982259b40597979220e
208	1	8	\\xda0c792dba50c7ae0433810721c5dc3428909c2ac12d83f2f02a3b8772f2d28de7f0668accd7927a9dd97c838c59773fe625445608f8173144e3e13ee620130f
209	1	363	\\xf06a5635f28da838e2e0b8dab8e76f6c48b4be13b240930ca2782d7da2d38a210739be8b5eff53c45eabbbaab1f20f7519987f3ae66f63db9f82e4ec926fd20d
210	1	345	\\xc9ea299d3bfef3d62f33979ae84dfa9a604d9a05e62e719ab7c9e7e5160e49827e2ee645bff518ab634035e0d275d8737460124043f66b9a2246c68919bed308
211	1	44	\\xea56265f038597059ad867ffaff8d2c9db37c65533f8c227deec10a6939360a23712006fc01c5da7e6d6b6abf1cf8cd343e98e7e24885895c819bb2c969a160e
212	1	404	\\x0df8d81cb1e6f180cc7ee9a76d605533c517388715453b0c0e4589fbdce6ee71ee976593607ac5d19ce9438899a89db8f4a9937a722322484257af014b654f0f
213	1	422	\\x4f0531bd111b83b16d394484b62d2b5dcc5c63afc20c36584640ab608a6ec0e58fd05423be856c253517197c070c84613d350f720e940583752077c3e1817f08
214	1	91	\\x6ff48eadac032b4758546033688cfdba9587c908bf5d9e7f4d99fcca6124adedc4540cc2e6a33da97ed16e3261d35f4ef4f60ea3609a84956ed8a40b09960905
215	1	390	\\x44aaf666c3c7c3cbad76f62e7aeb013d03c9b5387befbe071fc7ad9191fe16e8377417df4f154214b043a842a96c85b48257673abb9cd4e5ddc108c6f0a38005
216	1	277	\\xf226dae42c32e949e0c5104736df2a9f6f49ec4ad75de0c08a3bed101d88807a141130c355fe7b81ebb8b459d2a1c90f2f69cb873bd2fa0eca029b9039453a0e
217	1	392	\\x8e1e253d1b84e75f6262cae999b4b6d2880bc8f9f03eb498ea2e246a242e691dfaff60f9768a4ed4521180f89495166713be49648945cd1bcd1ad143a4e89f00
218	1	181	\\xe855edd68a6f435273613a1f505cbf611f85e0e6539e83156d9ecf61aac807b2071addb79334f75c89ef026daaf004ba44752a4301eec5005c93694983678a0c
219	1	12	\\x0f9045376d35f270d69f1e3ac43ac1912e7acaa09df55dc00e9a2b71cbd7c2ed594ea76a0b49d3bbc26d84732254ad74f029e6df4226d03fb02a5ef501a92c0d
220	1	364	\\x50fd907255f8d28dcd795291b0ded3096e8958870a1739d871735d5c2aa61b83185d294a547c2499be948791bf52657302fb1d9d0695b056144f990170d86c0e
221	1	398	\\x0daf4dde11afaeb05b9f10a761134999cc69cc36d7e1f4ab3bf7a7a00bc0c08c28ca4e9d1d87c2a66eaf9c3e1caca902516221c5d21f013eca2802a40c35e107
222	1	142	\\x9aa86a84e395f80d4ee3683b498e8c7812b82b7fc9ffd771cb786b430bd790bb809714d22140605730a06f391f6d5d3ffdee358b855f4997fb62e154d49afa0c
223	1	155	\\x38a2d2103e7da0f53f9e61e1a0c98b38e7986b99d53621f7850a4247b1f2e0f0c35d07a0d06090a3d8d47acb03fdc21dc3286bde9c27b5e3ced21b301a1a6204
224	1	34	\\x3ca427695c778541bb04cfbdda476a95242fda9b541a7959b6f5df608a2c8387577f0026e444296533983775a08c73a9389f340432edb4429e8b4814a26d1505
225	1	113	\\x07462d679843e4918f7644cbfa2b419fc235be88107ea7056d95195471613c75caca9650912bd1fa6c318ee01cb276d768de4693e364702986e5e1ea4dadf709
226	1	368	\\x50a815e72322bf501bc75b196237a9f8c4d92b3802534410e89544d326c5b9e053d0bd716e04e89cc63bce87c7fcacaad50c5c81e549f88105a96c3dffa34d0e
227	1	2	\\xe84fc96cf591638810188c0306594dd301f85134974904b574b11244193a57e496f6c66d74cb211b20bc20d08f887325a3b6f3359788ba98165eb9a27f18bc00
228	1	340	\\xe6b7437de02566ca639777df2d2eace105d8fd08d1f7a5886b62b34b03d9461ee5ad59ed73bf9a10aed1a45d49acf954d1736ba356e232c9f17d1c9c17cdd407
229	1	260	\\xe544134d160775d192e327a9d4029b29ad6ac770f5973385e7f8ef3cdc48602a25fd8607a3fd6f5f8bc648ac798f8467a0b4574ee23194e39942e0fa9c580a02
230	1	299	\\xa28a445cb29ad7a45b7b806c03d49067ec9c80dfd1fcc3031cfd63b1a4151686fb4b6be26a166892fd8c00d5df186ecb51b1d8e30000fddbe627f15bdab7a308
231	1	365	\\xfd8288b75c2b974999d2a0d3925db3e03d9e0fcbac9e61d8a9b4229f755603a9b13accc58fbdc6bd1d92491b778136addfeda45f37226c044ef316e22c5dd00a
232	1	192	\\x31d2a44efc4ee4ee4749d2f9af642aeb4a30bd15fd761c4cf1e465c281fffbb8bc1163f11df0ab329c05441bd56e3aa6136192ac9815cd25dff76bfa038bbf09
233	1	272	\\x9922f91c154fec68d75dc80a8ae7c79c87c1f6bd6220d8c08dc8b2f5dc623eb7a7d80d664074d142aef1cdc4bc3f38c62fd2b09529b77e3132b75b931711b205
234	1	373	\\x87b0b580603cdfea188beb9e0fca728ec466496fd17a0909480454d2c0f124f08d0b45eeccf122f3f4bc0782dbd8f70fa143ceb1c9f11c1afdcee49a3aea6d05
235	1	414	\\x60997030f483327d0fe90f617a4f6e70744e0e179af08196a8966a53c1793dcd4fc99f7e9e20e21c552ad26f180569a50b9a0226470275603ae71b342124090f
236	1	394	\\x2747d595dd4be393c490a65b3b28236e40680a4d3698d1b8239669438480f5bafe9b0eefb06e5f79f2e69bcbadce8f7a33243f61f6cc9cf7fb5ae8cbef00ba08
237	1	348	\\x6e0ae20347f08f574dbb797234ea48fae4f2ed9ea606ea74cdbcb400fa0bb7b161f8ca85072c64c057db60787bb2ebbe6f7d6836714581e56e8d235a09ac9c03
238	1	337	\\x1aa7dc273ee03ee79faf24f65ff3fee4c776ee7f333729c7d9088f5a887e7552d5ffa9b276ad0b0a48068a6265c135b98d2bba7c47868b6200b2bd3b84383f0d
239	1	351	\\xcc079083435f507110cf4cb09ed89643f94b950b495ed63585e02df72ffc83cba9250943419af16ad05d5192613ac8248f6b722de1760efed18531861696fd0d
240	1	65	\\x83470384da4f60c4060d60a468d4c9d7098c251808f2f1d8170ac173df54379e8aefcbaac43efcdcc8fbdc89eae4ac317e5dc9615d561ec4ad6acc98d710f103
241	1	397	\\x4c89fb8e3469bec806bd0f443b5da50fd2fe563de3493b16cb07c6b48c6ea04c1453a3dc85866575d561c46c8cf5a3be9ee48e8e7d403792ff2d2da8277b1907
242	1	420	\\x267d9c6bfa5192a524d7be510a364deb85a9a13bfa00cd7cfa6bbc54f44486067cfb4383e60285026a67ae0ba259ec2624fe1b31ffdb2014e1a8157e36592506
243	1	58	\\xa6e8f41965a3c28a2f204380f2f3166f66d4c9d43d31f9f06a1220571420fd3212b352f7aaff0790db5ebad74ca38b4d74af4a138e28e61803984974764dd500
244	1	124	\\x48b91bcf9b6c34f0a251ba5eef49bd494bf0f9252db8f533c6533dbc818e7da3c0a104e3558849b5c7e1ac14f9fc9a9c033307bcaa1e8261ac00742e42228e0b
245	1	226	\\x66c42649ec67b617479a77c8bf7392e816b406b2c142f025c1471d7106636659fa90042970374e356c41d7a774fc58967e7551498d4cca0d7bac02abb52f6b0e
246	1	343	\\xfc7d38876d730b33b0e92fea8cd6175641c818f372488ff6f66a5e7f13257f4a1810a375d7bb1c4fa5357d89618582d5d7f9d73fba9a27683be36f37af3cd702
247	1	210	\\x96d36bbc2615eb2fba4a36636eef6831503337debda4740dd8e0e3c753783da6a9b99c2ba5dd74eecb9b2d2813744f93d768abaed3874e5e76b3bcbbbcf19a0c
248	1	375	\\xdaeb047e0a5ea79a9335d8a14c73129571421d4ed81694d020155ecaaf302b349e341dce057eaaa2e90154989ae7d02b56f09cc50900bdedcacf5a3f467a5409
249	1	154	\\xccb3e9d36bb8bf7e5ec0d4787b8d57664ff9763f9471a2c6c7e3bb44b3a2586eaa8c50a95fb1df6eee42a3af60b1aed0f830d798dfde6aeb71f79e19ad3d0703
250	1	254	\\x0929d29ad722278f40a06d9b1bd1296d0ddf5f68a9227490695fb0132642f20072c285bdc228846f831423b05635f447cdb959d9d2a8260069ea7bb86f635608
251	1	295	\\x21864893316741c0335c4c4397e3cbf79ed7fab4a396a077614d4b723fb04ab13b0832460b92fd7993fcf2a1e24227aac64708fce3d0b7887a0397fc5fe36200
252	1	333	\\x0a1275aa4cb0e474eee7fc3bab87bfa83950a511a00bbfecfd41d87bbf3b6495ac6871baa139a9653e1b7d5ec255d460dea8f39058348fcde1006e9716e8c405
253	1	207	\\x9c6deaa532ac351162fbf4a765e3808d49929da4fb93ffb715f15c56aedc4d8eb6863264c67f8bb8fbb078874bcb83decc700164628583ac6d4aa3dbfaf7e303
254	1	249	\\x54a8f45960d143bea541c2e24b9b617952b9809acd58b76c0ce5e24587e9f813e9b3f4b0d445fba756f09210cd28aa62dba08e4bb79045d106433fe193d37609
255	1	320	\\xee1db8eb7266bd1e8fae1520d030aabb9bf71adb24a29383503628b28ddfcabf7febe28e150e73b41a82da9d8521e96eb2fb0bbc6279fb093d08c414df15190d
256	1	311	\\x770321b335290311f2ab09a806cc9d4e273695445ce110aa189ab9847527e144a1484b5f0a953ef754b3cf8c06eae22905b585a6325992f0b0f8e7b55ab92302
257	1	202	\\xce1dca013bec393161a380dacf999dcf854f2ee1b04670e19cd271168eb8c5757a3ed5af94dcded31930e86def29432971543daade8997fb51ae16990da9fe05
258	1	308	\\xc5e35e22436221cd25b61c14cb0bf995186e8ea8141ac7a3aab9dd2b4f6a2e80408f34051be9548d50d0878caadca330d66112b3303bf95177240721ef9cc808
259	1	163	\\xbc27c214ad1f036e18a66ad798de49271793c83c4d766922e1ea0076e6c7e93b3dd7bd0ed422f5f7113f3bd2efa51b352617c6018362141e754c18141287330d
260	1	317	\\x9a9e13a2af8024c7345400ef850f508834503e122299178a43203766ac160e59cc604a9135fc841cfefaab2c9cb60483f3d3493770605b6f774ea028ace0910e
261	1	307	\\x6908f1c20260f8d6e6cf1ee29dc7f91c61d3c51424f4390da7806c23a7b13f700992d693794868f45f4cb32ad811778dbad1537e25b6b24c6ae62b4b12acc900
262	1	172	\\x77b0ad15e759853ed08318813ee798b217e4434b1ecd9ee09cf821d92702b0eb97526e7069f29cedfac2c37e986acc32bbb443ef89606061b0d97719d1b23201
263	1	135	\\xa119a1597c19d2c8c77d5cfdf8851f7e2a95d9740859cbe4d681160c38db743d6e7697e8754a6d2b0fd92dacab10b36fadac2f310712107722a288b411ee9100
264	1	302	\\xab3282f65cd359c7f8323dfb87e61ad255dd2161b2d75ecbbd581ab1c27664f8f586b7db63b0fd353530fac577b46bde79c713ad324a212ad538732cb9e7ac02
265	1	86	\\x506d4e0849e25f32b23eef690b50e427fa0a7bbbf41ca14e12ee8a361f01928ce4eaa8f34ee0a841f696abf37b2e6d47b5b4cef5eced1f666a6ad965649ba303
266	1	79	\\x0a472271ecb10caf296f0c57a5903e9bbfe763c7962eb22ea062cbfdff86837aab1851a13dc6963e43405e2e1709ed274ed6800caebdcee586aeda15de764f06
267	1	83	\\x9e92fcf7008a4e832cb20641e29ff9325c232269def8727caf817056e8f940a5ed891e3b75b2e7f78a9b41f624d96f25eeabc6b9d6a1d4be95edd4e86249220a
268	1	300	\\x5f88e21886db874804f0f6842c656c331957452e67104b93f9058066ffa2956aa0799238507eb7fa986d266f53a9979f562f4c42be2149d9db33416753d44208
269	1	416	\\x02ec681de856d45a1cfbdcdbad57ea15049c631a581d63a0bcd72e66ad07ab4de44fcd0a096a2a95bf4a4108f16091f389aba8cfcba0bfccb26ece83f5572d03
270	1	116	\\xf3a41bb27ca1a40a66cad58fd6ea170a0d86c5e3d86aee917d1f018ed3bc3380644ca69073f3f5e68f0103038b45981aecd35534d745939c5e6a093a401f6507
271	1	41	\\x81632c4cab2303ec6c291d7cbd57760434447fa4fb26710bb18be6a66cd90ae56fe070703b54aad4db692fe26334852c5e90d77f5e5217b01c481493c3de2902
272	1	395	\\xbe04d1de72dd7861139e87d76bf396b17ea4f7334a83816849d4b483ff41f7978bd5e7c40fad82edac411ee8340f6608350ebd6ca4cde59962272756e12cbe04
273	1	405	\\x907dd1bb77e3bc557409a718c63abf11bedc468038aea024c547a40cb1eaee44100ec845740a8aefb9b35c262ad44fe1fc8d7af35aba286878c277328acc0205
274	1	279	\\xe67a5d88868d41e265cdc4cf8264541ed54f040ab596183c2eca878055ce3c9af8124b9070d74f425914a79f6d91454ed3e6fd37e99849b6dc6d977a757cd302
275	1	314	\\x29f9daf05f000bbc23824a309fad0cdaed02c0edd206a052e7353402d3b23d2255d783414e7b7f88b17c7b49912f12fe323a3e381f30973a125b20e93ed50007
276	1	57	\\xa2aadd2f427b280548592b69941534c06e22fa9fa30810d827ee6c0b096c2f9eb84104328e121987f3a7f413649f417e5bf20dce058cc7c173227c115f86240f
277	1	424	\\xce5b83ba5e31c656cd08878f5fd1eb113938d6b8660f80d82597c8c6db05183d26634f388d6879d7f1b734287c9a84806df08b5e6be6c05c5293256c3ea3f603
278	1	406	\\x899526fa9fc93e31bbfee50905c1f36e1491b8c0dd33cacb074efa1b2c0bb9da00a0076b8c1485f3c0895ae78fde77b9a98f596cc74be159c9b82d64795bf709
279	1	344	\\x2d55e6665ec8ad01a118650ed9c5cabae2fac52781e1884f9986ec0bf647fafa04739d9a849b77e424252a311c94d3e749e265a2944261229c6657d8f5c7a70f
280	1	177	\\xeb78440054975b42f262d5f853597df3787165cef6a69f830433e6104cf03308a8fd5a19ee458ec52f114a76125517f5e37203c3169ec7544d9e15aefdaaeb07
281	1	278	\\xe640d960076ae5bbb46f9f5c1de89cdc4aab19cc6f913fb3f498ad497154def4bb57ff5f9602ec9cd778c91abaedb048b1021b6d7b30162b0cf23673e89ff906
282	1	233	\\xe065135bce930b042172bfceff15fceed5ad4420e3fa64d00a1eeae2d84378b406a6e248fde3266177140be9f8d8e353b404ad7d431f0967a334b60aeeb7620e
283	1	228	\\x4dbfb9820e9064e97a0e943bcac9cd427846abad522e250157f6ab5d4f17973591a641fe0579bae899023d39bd05bf0409b76699833fabfba8e556d45e6bb503
284	1	130	\\x0f3777a40b79eb8447ee2e33805f503f89408da8b7d174ac5f1f626f24ad62959edacbbde6e85871a7756b3f0102744d7404aeb7d829a7fbe04aab1bcb922f0e
285	1	247	\\x557bd010d519af7a0ea52fb3f0c80a01a15bbb46d39e2d1d4e1a7ad515ef44f3408a0ad27fff04d3b14ca0d88d59e45cf6df861374c58de045ddd012dd7f4f00
286	1	322	\\x6b94f5e68abcef781a8389dbf754910920ce420ae730c652ce60b9317c973ba8133cac333715d8c39bcaa1ca9190852ace6828193991ff383958f74ca7a4a901
287	1	241	\\x948e8fdfe28ed35d76113956cc1126d0a5ab1032e56ea7aec705de8d16dfae8aa06bfadccf290b117989b2edf1e3bf9e897df7c7b52e90119cf8fd3dc3fb690b
288	1	24	\\xd1033c5de9efd0e023ea80b030bccef1864ac321c6031a29935502e2561add7ccbfaf58076f29c9799a392e3f7ba36a095add9b262236d024c8c04c1562f0a0b
289	1	168	\\xf1dbd6b9e9f479d2f470456a88cd21263093f0d6e232a55ade36b3805333e329c9480fbb01b862fe8b34c89a8bd22db086709d8546888878862127afe7a73a01
290	1	352	\\xf59982852273d2313561790fb2ca1f12e1bd02bf3c121de0be3bdedf86ddd0181ed4eb0941b426461637b080d77028417fa45b58bc8be56a7235be105b72aa00
291	1	203	\\xb9ca7d103b1f6bce86a10f64cd98f9d8dab66a95118e8dce0026a7352c6a2945aa8467d33d33af6c30f50e7a8cc1413c6d1edc451e8a11a62cef09bb2dd9c70d
292	1	82	\\x11ef90da490edd9cf787660b1059070e596b0185528113a816c3e40b8a1478cf5f64b79425cf6eede420ffb285d6c6bc285818658df2f3d1cb7acdaceb680e09
293	1	13	\\xcad1c8ceb109a3e4e2910283bf0fde3b8310cde9bf3cf1e099638867427bcb9338f34e5a359c2d37d79e57a08783f7835d4f955398725db15abe270da06d8f09
294	1	298	\\x7ca5ce128fe008c7d4ab274f01e9914bace704d39a26ab3b274a2651cd83dea659356d7d9817b3dc42c6f5ff55f19ecce99f59e6750cfd36d36f71769a2c5f09
295	1	245	\\x536f07c5fdae1981c3475071e5b4592a913c2635871bfc9559d8e6602ac11e2e7b6502207a523821536f22f6347094eb0509b01ace1171be8ab5980274eb2d02
296	1	199	\\x68eda76ac6772a111e0f161f12585e2d523cb52d5f214db8efadd6bb858b4b5eeb9e8b21ecacf76116323927d0a8dd93ef7a3cd81258a010f11c738b1eaad10f
297	1	388	\\xae5a79f2abd5060230813fd903186ee0b6ac79a66e76199296e0cd0358700e699319533bbd7a8c8ebe5ee758963bd2f535ab0ee0a47ff4a023ab23b812dfe80c
298	1	309	\\x4fcbb0c244493ed438690b534a92ce61b1ab75a1962a00dd7c658352b376d1ceb78a2a1c2a2594053545e9ce2813886c78b1eaa876a20b6960a9886b4f99b507
299	1	169	\\x7d03aa73a28347918a8600298fee438acae1bc15c41aab69ab240a78f599610244d9066fa1c9a79dc47da2ce168b87baeac644905f6ce084a19eaeee98045503
300	1	73	\\x1be6c198fe853df4e149e5ffb4a4c00a2fa936369cc9923a293df9d7011513fb55225427dd6e151f4ddf5df91b3ea932109d3aaebf7561ef86bbbebc215d380c
301	1	55	\\xb1eee0205d477818a1d2bd423a28ce676e97a3809e3e766d36a4d538a3f33ee7752f22e372e6ff2296edca169d81037f0de980cb1b6197934fdc61b32bc0e501
302	1	144	\\x52bb5271513b3e22e5f30c5eb328d4b603b0ea0ab98545036dfc52e9e1e6a730652ef5fa241d683c55eb770cdb5fd437c97fc0713d50c71b708066f64ce6c40d
303	1	77	\\x6109d9065308d6b2b39482c12d29a01588355f96c458a7a535578c046d243189e7f8feb7eccfe421da599ab2468900b52af849a69757129930ef78b1d590de08
304	1	105	\\x5f3132ca23709013f8c23b9f1b8a584bf92f6f95ea65f73e7ac68a0064058987046d51c2a9855cd80e8889f29d36585925da18a2cf5d96a448f7ade291c6fa0b
305	1	122	\\xc07258da81bb1ce070323ef00f5bcd1f0df6e4d6afe77eeaf242a8d06b3123342a57342a11902befe4d958a8f8635057721e77642b74ede4f67ea51019825705
306	1	47	\\x567e1e238e10c2b19bf8d87965d38bfaab578eafba80c386c6a3549ae253b46c99e84f770eb010e47f9a337b6e4803af3c7f676d6f8cc073333c1de6a0066800
307	1	112	\\xdfa29ff53a6c4c14148968d494351d5599f2e28e1cd26d72812949ce7cb5d95deb090b6373d4383628d55b8fc03fab42b4dc899154c71c02792e774a9d10a803
308	1	243	\\xf038f5580ddaf7e20c335f729de29d5948e629126d4e5f161b0facad4c59be401ff0af8ea01c721f47856958ccaf13131819bc635be0d0010b672def5f27d003
309	1	371	\\xda80d5ad676ebe06c477ede34e0cf2de3f0564cda2c370c354b001dc32e98992e76d0dc16ee43ce5f242cc975bd28cf5bcac0b62e8bdf8dce9bdca767de4b408
310	1	31	\\x651eab817e84e8864893f188cc2b19e1082fe2201b26183560be6ec845ee7b7b203e83b4441ab334c5f46394ba8cc38a2e1e01f7a0a55ac383f28c3ddb07280b
311	1	94	\\x35ed82e04457f8480ea007d64e488990e37bbc50ffa9cba226e40a2903bf9dd5236d8ee55e20ee8165374c4a772c9fc4b30c85ef5bb950988fc527d85efa750c
312	1	11	\\xd679bc40e3dcd0b3d3a12f1a061a275d2c24c6ea7c46f721ccf7ba2c477524627dac90ee0d2a2210d8c60b8b609385fef492e60080bc0c82ec59dc5cfe5f030f
313	1	89	\\xb72793a7426e9995bf52f6b3ebf30155def72ddb6d50ef745e3f6315bdd8466adeb6439c1d2af4982a59dc4fdcdca25b5884005dcc092265559168655f3b1c09
314	1	137	\\xa82b4cd4369b5ffcea8e85148455a0370028b1cb5fd31af279f87194209122821921b4feb574bf7e1e589c2b53a0465a764dc838a291e46d6319d2dc36d47108
315	1	284	\\xbf0dcac855d77aa222756b1d836b2fec9a3a2dd0ed1f9a621b3ff7b8afc2944fb26bbf91ac4311725241dbf2afc5bbf5205bea951d8672d3fc9e28016f163e05
316	1	387	\\x0a63cb13d77bc3a75f85f0ce2628688a41c48ccc1d97abd428931e9d92aac9c6e3d8cac2196cac074a1a46508de1ce138a67b54b790e5f1de5e1e9803e70fc05
317	1	237	\\x19e2e284e757e1f8e2e344c8ffe39a4bca614d48c3badd7d801ba9b32b480ad052b41547ff472909b54e58cf150e8f1d16746efd3c654da0dc61fab517979703
318	1	323	\\xc0bd85a8ea28d73c5611f5974565476262e25ace6aef017f7aa83de9864e4b7a0a8cc84628d7c690869d3c214277b1ec59733247b8e14519dd9dc693c7414f06
319	1	3	\\x12ffc2a166b11476e383f24790588cf1045e267bd952176fd013d909c02103d4a4de0852fc6e4aa8176603ee574d0f6f1fc239d39f7e0f0df887e84baa67050b
320	1	376	\\x9710c2b76fa4ae5c26a4a8a8eff0338742b02c83e1c3c590caa7dc6b3bf810cc94a56c46e6e4581842d7300fdeb69f3702703d8b6e74b12f843c582f240eee01
321	1	266	\\x255ba0bb30a72554b07142842ec34c9ba12c6ad4c01c1d8ef902d2a1544576043bd070eb81c534b1de0f2aee1c444ac387741604d39ea975db7a73e015ddcd00
322	1	48	\\xe9a8aac1d5b625242889fb195490404673e98da8c2ccd549115cba79c08d05140f9b3c75368473940ee3a50062d625aee9ad4d4ed4a968a55082bc74fe94d80c
323	1	76	\\x9080e09ccfb55f531f57847da3ed5df000a5c965c3c152eae5b584f54588ca46eb1525162d1e33da1fb2837edb6fb74073a0b10da4757f041855eaf17e124500
324	1	301	\\xb227479c87379f65bed8685bdf47e04267165c0824ea074705bdaff7ab16fbd3cb21ab42625d46dd882a0053e5e115bbe55bbcbaee2fa07446291ec0a019ce02
325	1	111	\\xe6a0e7a8ea2ce69a77eddd0e0e76dbf2ba5a48aa901b352a6a4fc830a9e382ccfeb0ec20020368fac96c3010d4477edd16c695d2c1f14b6ebdf6e32b5710990d
326	1	282	\\x9f47eff461e65ce720f4fa95390c59465f3c78ffa2d645a4a5b8a0e0d84e2aa622b6ebd3b12ed08babe71d4201b8367c525e25b684b98e7ce7ea2366c6c8970d
327	1	22	\\x0b954c8dac0265afb200af04ba111ee91911cae06daad1df73a31f6637b6a18071f0bc1da726b8627723d92faacb20700dd45d8ead0132cd8559a8f2bb96f601
328	1	102	\\xe6cf2f9054d46afb15eea9681de1494ddfb86bc63a833b2498ac9217aebc0ce4f73f242c0ceaa795b292751b845e6f5c5dfb83a1a38febcd7f9e7fd3ceede309
329	1	384	\\xf58b987dd0657b6f982501cc8bf877ef55f0df52e4a9467375b063f73b554bf1d1279809c62fc6611e6a2bddad006052824c106c0587601faf91d47ab9c9de07
330	1	50	\\xa47b801bfdfde82d58f7e35df81df9ccf56a00c69f7ebc850b30c795bbddbdb303adad455ce8b1f57e6ff60be41fbd4b38123e2761c7ac9853b3ca5110de6f02
331	1	261	\\x5387b7404cf983697c8e1d71e5736bdc47826deba32e0426f6a24e6ff131c52228fda931d71036448464903ccdac02f56833b87f5ee00206250d67611438790e
332	1	68	\\x943ca1aa274e25e09b1a7a87ea0c88809ebccbe165b0575ea641ce7bd89fac44cea682d0fe880eb42a20df8560dcf8daeddcea478e939515be58fe54d448d10f
333	1	258	\\x9a1e93fd0c03e82e4f015767d9bdde71ef2c8596afbd36b39edb2c063fee95631bf78dd6bd1ef52114dda7f73a4ca21102ce29868aaba2c5e5419b71b9f90701
334	1	145	\\xb363d6b4091a947d36272f3efef1906dcd955e9aa2f5b4ef789abbab11f69152b2989535ef0938c76b8a31f1220de3d715eefe2a2d419503ba9695a23b11ae00
335	1	338	\\x8d9d52a4a872994d3e41ca313fde1a29ce58b040edf9bf3798983f984f51acc8606be5defbd2e2fb57de02b466db92438a684e5c91025550b8a2292916d6e90d
336	1	166	\\x84c9dae5d7903b07ffca1171e1b81691854823f1b939585ef4ad41f4836b5ee515e9e565dc6ec28fa22e6553930b8193604f86d49d229c5f55f218d811a6e303
337	1	418	\\x64820d4a01a997900f3c947ee6038b2a43df728f586dad2b3f3c005e99cdd4d06bbc8cee338bff8ef15425d059ed968c49055285a6f03b995645f9cd23f75304
338	1	104	\\xb51fba555e7f1dda78448e696e49d23a0df42558d19a5270f68a71756608f0e07a00ed5b5431d4b523d51565a7c67c11265f446233454501fb9ee9c4248bc004
339	1	328	\\x67d2c565188ed527977b1adb77566501017fc38f0484d15d3808c38116129ec07881bde1b2d9ee47567528393ea635bf30d5c526364843848fb1637efcd7800b
340	1	170	\\xedf01df695372562b79c2b9fa2b9da1a7fb67674d3994b5d5c4eeb2e41bb1f48a29cbaf6d4dfb4eb1780b8f103c4540831a3e8541ae846d3f933dec2a41e540f
341	1	357	\\x3e3188fa4e3dabab545b7ade1db9f2d1079cc0b30e14ea5d40b2ca742524543f8539f873bea49160e8ff71735358fa6c9e9b2b3a2b22bd448d368391f0978903
342	1	64	\\x2c11938d1f6d5a1ac16db0965d52d56613be3e90fb47362a4829ee3fa0aa1ebe6eaca4406f67aa3037ffa12fa398dfb3cad1daecefdbf311c868fe3d0d1a3008
343	1	291	\\x8a9a49b44ce67b7642d9e38d63e213bec65efc2fd9a99ecdcb48161e24f5fc70762f1daf743cf0b8045f2758991dbcdace3dee60caba6e222bb8c4a648920e0a
344	1	99	\\xb3f903aa439683abfcb77d4d496a4ed1292561de8f7da3dc19e395a4f4ada2c525c71d1a5b584dca2767e48ab7a160415d41b4cca7e7926f6a88513fd6537400
345	1	219	\\xed5aaf218be3224aaf647b814d2f4d0c3f30a4da5a2ceb1fdb17b390eb683f1dfdb4f8d40407e4bdca4d99fc3a9a4ab7065bd35fbc8aef0f25e2d797710d430a
346	1	419	\\x413f0902db5a87184d4e4765f3a086d8b59f20a1bca0a6ee996b808b69d98635ddd16530c8d1761a5f8370c4171464ac4aed33e72d47d333a226fe5ee660190b
347	1	131	\\xa37f6488241b5aad7f6a47656574510aee0046d18e896eb1b75bdc537e5f7c8d0877185ea6c235a1fb12cf24dcb8518f527ad577b1563d317c892905ab1ce50b
348	1	378	\\x5766fb304c9723625f68764cc83d67a95111fb9ce95914bb6b9eb6054505f3d766dcd32232c0881c830bd7949cea0964ac52268aa65efb968f45430166e7eb06
349	1	216	\\x8267f5e2640de289d0260975e1befca5811d9730253b9e985bda725797ea38ff04e528f3ab9ebae80906ced130e1e93a399c8862731799987de81b7010904808
350	1	286	\\x8d24080fcafebe5e932ecc4ee56463075195eb389c4bdc56e2f4de39e7127b3bcd955ea370bf00e3b5f347cbff818936f0a4057fb8028774d8d6fb47a58af007
351	1	381	\\xd079faba7b6de346704e74df2eac3d84925f0d506a008f6344706d87b065f6abffa70d4a5025f02de1952e4a04920e2a3830a3ff3ba072b9bc8be5eae6a62300
352	1	271	\\x86471d82147369ee1388cbfa27dff16e0589052035f77d0c2edabc4e18db88c4d2d7b6352e8a88434d118b121f07c1c7a4f902cfcbf8d323f4539ba4131ce30a
353	1	326	\\x0dac2f3c814202d50521a8d5c2e3a8bb7dc416f0b34de4e725c5c818341f6b1a543f6fc7aedcb8598d6c1f5a0b1d0b8a33f20e109a1099fcedda1794cf490506
354	1	231	\\xd282d0f27c9a84f12dcfa70ffa554d01f2bda54ccfc2e25678bb1d0633980f915c01ded2dd10544ee8772fb590c5eb46490189b88c086e9a1331ec0412c3810a
355	1	54	\\x572a7212fdb28eb43f729b09d086cfe2ef8cef00681d6ec4b7acdc739c1eb7a037e08d8b07fbb9e40f1f08d343982ad59ccdca8887953f259d7d34b01e97aa0c
356	1	321	\\x7a17662585f5c58716b4406076555597f64188ce1ff84459201a4667e54793d10cefdd6a4e8794bc25f44be364c21c202a7a8ac477a815a433bd6dfdf5e70000
357	1	355	\\x688adbaf3578cb333aa22555c7d5947643eddf340b8d73c01d116cd9ea3a704c7ac6856a678cc3219bae7a24e417150f6fe545bff2a99dff5db1344811342601
358	1	393	\\xc9667caa0e160efbc0c038827ebedb9795c04c8945e89e5b095f3fd54dc80719608e2e5ff9f9d763584d2007cda82f761efe5a441bdcac309c7817701d6a5308
359	1	200	\\x0fe353f9dae49d80ada92b1149657a0671734556a1d0ce7826267cbe907af5bc48b40b5e127a52c977700ce442bb75b542eda064aee2fd016e79249c8458720c
360	1	274	\\xd8c8884e23d5d826cf560c1ee4e61387d90d04d248a96da61378d54a027767f61e32dcc27765eb03bc6a43450c21a2c0527d05c650ad4969cb0f643c4c4bc203
361	1	400	\\x34f2d763f6fe64ab5faa520a458cbadd21b867ba90e5bc6e97e3e0cff48a642cc9252258ec355d61b8a5847c1607eb3f6e1075111ce95b1070929b681a03d100
362	1	87	\\x8d35df58a73fd549b44c3a5b52acf97d4c9f8eb5642be1e8558a3eaf853a24d5de7e0e7fe448f752e6d26956c4c179fb7fb03391d49f6757f80940111a13e80b
363	1	39	\\x5df0885e3738fe721941efbaacb9b83953b14a151295bc61f062aad9aa26bd3979ab1bc7dcf6c662116169a8006117064ffa9f921800013a05ed16a011b8510b
364	1	138	\\x96979deea8ed1d4d9e113d7208d2896a4489dc35313c353513d4a7117a41de401b36bce000b1780e075c4772caa60ec4dff77e79911eaebdbeba907462e4a40a
365	1	341	\\x8d4236a330e75e906029cac410d7c1b6c077d2a889c8963b9518293193c1c9d2a0c7fdbc6871532c0ba60e9821b4527f105db12e09504afcfc019e48da87ca04
366	1	59	\\x503f0710e57d6ed8c91a70a00a274e32a907bcd5c4a0b7de7404771186b4972078d3a4992af5e0c2571f6da623c8a6e9c06f2dba2b009324d5c8b3e1e8a2e20b
367	1	69	\\x34ee3d35d8a18dab8c00fb702db0172dad93a8776eab6d6d3c4e928535e6a8b17faf5b5f91146627faa387d06f61ae2248c139da5df6f41da723b9ba8281c10f
368	1	120	\\x9cf28d6971d9e0a32b11f08160c37577b650720fbe1697b2a9be1499e92a2be2c28e1ce7924ab8c206ebef7b4c95159f7243c8c2b00934a3b4d71043857bfb02
369	1	21	\\xd6c486cc7baf8ce78fec7b167f0dea21d65d1fa30cef64b1fb5b98e4db7a87a554361a54d80eb8ec3d6cfb0f99202a02db4babb8a1ed3427b436680790bfb408
370	1	129	\\x12d3a2c01393234f44252c7eac769ed7f54d4ac6a5e70598d7b887f2231dd8de1221f88bdd9953d0a02e10e9e0bbb58f39b99f3c69ba3e7264e7bff06c490200
371	1	221	\\x2c31b17ab0f46a7ea6f30ef0a4808dded0b7709e486b136b4210d29c2f89a71ba7e7fae00dd5e4ed24047488d86a45c98cd737fe28872cec01a5da2555182a02
372	1	5	\\x3596cb0f6bf7876810d9f19f2901bf5c481775d81c36883f571d65f383693ddd1abd72479b5a60e7b1e2bf91b0bdc1fb3426954ccbc354907168d4476b35410b
373	1	183	\\x9e8139ef0bfd736fd934422a56b9e5e9b9fcf044beb667c9fb65442617c1d3ea51b4c37e2e5bcc4383c0e346ff2a51828151db74aa5bc418debb5750cb557307
374	1	139	\\xfab5e0450b22aceffcb13cc570f2c84b93989864e0555dda3847f6de9e6c8d0a62b52d19f3f51391274c21e86444a4b715fca69e911fdcd24b5eb8217626b60b
375	1	146	\\xe1b65e96e673a1ba8f384f38d80f596ebad7a134d3e25bfbe8fcb9a768707d69729bbee4ab3a0e2978e0e284446c5c662ec0d79f0299aaae70d6a68b51a9020d
376	1	140	\\xc9f98934637b966928aa7fd6d3ec963527b1022119c58e805e246e78dc555807e2bf0032ae0fa2a746bfed4985d08fcce9eadf409473a0752454309d4528910f
377	1	93	\\xb0082f7e428b1cb212aaccbaef303c7fc2cef5a8f9742a56e694daa47575b30fcb9282893ae482192b3ca5e9691725e3d5959ecd7f19056e8872fc73ac4fd40f
378	1	132	\\x26ceaaaf89b0914b18ac7cc68d510c65c3bac52f46525322dc73dbdd3286bf7379a61084eec26317273fb9dc4d65e59952807aad274e01c707d60fcc5219b306
379	1	366	\\xdf3098ea7b90215a1b2ee0b72ef4614c8b1e84a1aa328d6ee1e0cf52ad6f065ac973c01b571d39e48bd5cf7de4876a46e96828f4a309d95f73caa754fac07e0c
380	1	185	\\xe20d00d841f8bee884dcdec1e1aef0f953ca9fe4887bfc1f7f4ec8f257eefa6df8a7c57000cf18fdc8b7e55013b3a373ae920d2a0060a6a06587e3674dd47005
381	1	379	\\x56e1857c992ecee9e6df040f5031fc5e0ea5b59ba956c5d451a053a856eafcf4059e16a95035e833399f44557a89efd763231708257d651d8c66e9ddb16f3507
382	1	251	\\x04c4d5f8e9cd2001745ed6c94b346903ee0b11ffa6643c684687f0005428645844b3027028c8f1312a3b4223306648db4905ab1f39307bb80a85f8b34d6c6704
383	1	417	\\xf85e62cfa7b506e40184134b7093a3a0985c4761bb82228fc83266515c410fcbae08a3a4f8b18e250d35c0f273e76ea4f676aa93b09b76c515f028311dac7a08
384	1	184	\\xfb77d88c14d9631dc1543743de97b39b9c79b95d7640782ee2aea6a20c6e2e660cf706fd7be4ec7e31dc342269524c102c7ba2a051615b1ba6711cd99b360706
385	1	255	\\x332b0df53828b74eeac105b0083543e5beb3d24f4a4d8941e4cf3b7b2a00ac604e774838ff82cb957231cf080cdd390eb571cc3860edd93de0a4493aedef0f00
386	1	81	\\x73c8e7b6a8457aeadc47c1693fcfcee7f7d5ad43b9e3a489411a13169394ded87109a8f05f76098e8ea3c0fe4b6aa6b741819bffb2131923b159fa122e34fd00
387	1	118	\\xa74f04eb588e8f188fb72d8040b145c845c6f87d5c6eb074d37e045334427344d8cb17adb7457922e0e7f1e8724e2049da8afe9ad81833633eb13319b4f36e0c
388	1	27	\\x8e0d8d6e73966742b861375f7aa938e0aa3c9c14b6ae4a91c53247383b2650c5ef57d90561654359db81bc084a40a8b4fde2348b621bdc7b4c0cc6fcbf1e7408
389	1	289	\\x294515beeacd6bfe5eba9461db8ebcddafb4eb57d9340aaa433a3b95f2684ed7c60311b1417c190573947f273ac3b663487005ea76df7b1cd975ebff38732201
390	1	85	\\xd2fbfd9b2b3bca20cd73a7396f8acb343fe35f3e2d7563e2d49aec17d2ba24678075f0156d86eeb01f43455a14fb2218921d7cee848131345db942e250c4460c
391	1	125	\\x49120bf797d27b237a37ef0ce8afa97602e2899c2fa60c34521cb20b0882cae50fe48f50fda18e8f15763d985501ce6415b3d572fdf8df627358835ed005520b
392	1	174	\\xea9c4dbebc5f2d1be88661bdbe153e51e8cf3cb72eec725d03ab83669c011630bcabce359b3aebfea43415b22e56b1e2f2e5c20cb4bd101694b7e22aed066904
393	1	109	\\x0e217a20bd736836c9379ec6011d55fe3e26e752e9c1271e22caf63052c97079e873c909a674de9f05ec1be3a4a7f2db7baa13f36ea1027d864929f1b6444e0e
394	1	17	\\xac5d905ed93e0f3005b065c570f1477fbd3b214b3a9956dee4f531395c6e3057c23b8ee611869ea36dca05424c763c518dfdfe446e60a0e953019cff618c4c0b
395	1	32	\\x90f48d3dc66746660ed096409d65d25ecf43b7152339a878012e59020dbe3708c13c38082609415806d86ba6a1768e07cdaa6145b8070d53821ae287ddfa8e05
396	1	312	\\x08505194920ac6fd9953294e1e51437358674c6d0df38bcaab0e2c752f85abad4595747228f14d3bee01d8cf874ce70c57dbb12f087ba86ae31e8463073fef07
397	1	329	\\x13c616d2ca79b350e7e42a44a5ea8dd1eba0f69cc13444a608a3ee46899f018d05dab6f9df2a32d3c7f54b3c024bc467bd1a0f19ffebce1da4f207e8ea42940a
398	1	107	\\x3458b386584af4e3fa98ebbf678684612b3f3b8f6d43b74b8eb7f5f207265da25846264691530b35b3163f2e2cc2d8339fa3b724e41f32000e02cbb9765aea01
399	1	265	\\x15090bc2a5f0a889d72e00dc3ce89f0c71c7ce923b22fe90af7738bd47d37eaacc8ba5b9b0aa3b6d3aff7d7d7139a9615948ce56260b18e7b2c4254de991040b
400	1	297	\\x69d38d0024958fde8d4c57d35b98c8231d7ccc0f2427fe0d09e9c21b4476cb260609cba0cd9d0b1251f6a7fb1f45ff6789468f4b3814167365190b705cda360c
401	1	407	\\xf46286fd69e2cbc477992a778dd0c416f768afe6120ebbc1bc537cb188bb35402f33f171ca96c3ed5b149256b991c1642d8f6f0fdf4ba0898b53309215c3630f
402	1	349	\\x7789b44edc5c05c5abd062824e8e39c90f61e4310b0052633d40d500e7829d48393c1ddb28809a93070b321ac1a8cba3f17bfe707c19a5700e8373e7e3550406
403	1	42	\\x288153dfc0e00f72d3043e486ca79f9691f31382e884a77a600923980944c8ae2cef7c39ff5fe4a9a6ff9e80c8dca882cc633bc7fc40bd85a10a890775fdd60f
404	1	106	\\xfc4c3120ee9a50b9d464c7b942e25ac99b2f5b057b4019731afe838993a5c830916bc44736cd3fe7a20ca16a0fab0168cacca5647d74492d8f0b84a590a0dd07
405	1	334	\\x43d88380cfa12ee213bd72a99fbbbe0f51b64db303bb10e4c8e665984cc67ce4975c3b17f7485ec073b814617458b4484c9ed3e43692f51dbc96dedb0d15bf05
406	1	227	\\xc1fe23a2522e8556d883af20febd3a9e66c2f6368a322413dcbbacede7b1b5a9184ffddb3c753483eb1cb3a65bba52b0d9051503a44071f07936098f12f3ff09
407	1	377	\\x06f85de91c1cb31f556dfeeaa95bd1a680cc2e3f9a71186216854176b0d1a8daba23c02ac24c2a9a676f24c013d4579c3e4fb4c6b355279262c33455cd95590d
408	1	159	\\xf269426ccd96b787a7729e919b39b563483506367425562e25767ebc4b31f58a631a5519bbf0dfe5ff4986fb6e83fe435e79b4bd7f0b32a9705ef52b4458bf01
409	1	74	\\x4e4b9f33f97dc7d74ce3e750884b079cd8184a108b20e6dddb6395b455ae51674c56e0ce28cb7f60f55835ffb0d846a5ca61df4ce285ebf5ef80d2e66ffcf903
410	1	100	\\x843566e83fe460eee05b7314d6b98cf11f07b8a0d4153dbbe94ac4b0bc736a5989cd327dfea5a07493c3f4ca8cc5c632bdfe0215e85add1436494bcbfc81ad0f
411	1	306	\\x2c6d57cc70f33b758dfe130a00174ee3cecb59d73fbb5ee30c9942f72f22d8f8772c4bd6d1d67e5af917d775186433c5156e7e8c14a3c4172705b36fd0f5170d
412	1	127	\\x0b40e375ae380615af08ce0ae519c7ea4c72a24b7a5e98cd571d544679fe534171b1479d7812eb59e267f370cef4902006e5e94fdc1649538970d7f186759a00
413	1	70	\\x39e09de43b6a0589eab3696391d154e951525edfbc4f12359184158a391c41bf79c7dc04f8d96667b9cc4ef70167bc77a9a97453e408542405f9aeffee539c04
414	1	121	\\x37ef585ab7e4b4444d8a98df1ebb029471b5e625e6888e9496e6c580bc8ef441120d9b34bfbda2e05aa194ed0373a4701944c410174be3baf39fe5ec46b3250e
415	1	193	\\x9143146e7761ca7c1bf5ebea15c7740a6f072f684a198609b2f1506aa54f73541514aef542482e3b622cb3f114d36067e255bb16968c7f20329c7e9d790a4a00
416	1	165	\\x31e84bd0f1492a643bcf977a38647481412e8c81d922cf3a298df35a4908317703a857e45b260f5aa6425b5c66edfad9b163178101ea74e2c0935d849f144d0c
417	1	191	\\x9a7a1bea0c31d55c0029effe10a07f62ec86a4e5aee04b798ce5af58506c1295ef93279101e75878eb047b94a30b92ca7cc0fec6dc82c8d5448b50c4c7457c0b
418	1	346	\\x31486ebf0f736ef92fec91c0ea89331982744deb007c45f49ddd1ecb482fc093c8291b7e15fc4a0fe73b9596c929b44a7bccef1cccb093940f786761bdfe330c
419	1	7	\\x7500475302cdff38ca2446c81f59e161f277c69bd53e94df092ebfebb654b2c2594570c5ef0c68a5486a4495698f973508ab6af77ba0d0bdbbb81c29887ce801
420	1	336	\\x509da103b5bf4a45f24d3ae3605d200c9bbfe2cdc7d97ba3360a5e539c576ef4affa8b4395ac11dfd233265b47a4d46ca83da3d234b9616dc92f9fbe6efb0e05
421	1	53	\\xe332d75c290ad366f668f62036c51048e7f1d5c6c513cdffa457f8268b7df8e857880125d45319edc3606ed9fcaff9b8417797764b4d3e386d418edd1e1e7201
422	1	257	\\xb8c66e1e38f42d45e7c629e21c730bfc7ebbda8e2f82a598825c029cb8847397c13174f2411e85f9bfd79d020a9daf50e1ec56a5aef68b77728d4366cce8e80c
423	1	367	\\x36e46bbcfbbb825ddbe81b3bac4b0990e7396dbe2d573bda6a5ec006373e5109d8d91535c42b983603eab6577c7d9f3f01fab6bb0d6c1b5c9613a768f2b69703
424	1	403	\\x34c46ed721520a69f74ef1167e6441ebea461ba29f3faf26033a721e335e347751cbcd7cc42d071d324b2087d024d1cc3b8927ef62f7d4483cbb906831bd0b06
\.


--
-- Data for Name: auditors; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.auditors (auditor_uuid, auditor_pub, auditor_name, auditor_url, is_active, last_change) FROM stdin;
1	\\x4eb9807e7cdc3e94b223b9ff2cee1514010527e9dca34f4162a3fda3caa894c3	TESTKUDOS Auditor	http://localhost:8083/	t	1660251981000000
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
1	7	\\x72702f68a7f8fe933dccb46537476f90137b4ce7feedc7048244efafbc8f7f8740b6b8b18e922e9fc109037ada55ffaca1456963d543bb35f8e902fd40982501
2	193	\\x259bb32c4b2f70176d1f22a187f52f7a085097dd9b5222a475b1b9e4d0f93304d7737078303b16a37b08a0bd1e31a7a3df94079393235ddbbc8e8d3614c78107
\.


--
-- Data for Name: denominations; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.denominations (denominations_serial, denom_pub_hash, denom_type, age_mask, denom_pub, master_sig, valid_from, expire_withdraw, expire_deposit, expire_legal, coin_val, coin_frac, fee_withdraw_val, fee_withdraw_frac, fee_deposit_val, fee_deposit_frac, fee_refresh_val, fee_refresh_frac, fee_refund_val, fee_refund_frac) FROM stdin;
1	\\x010cfca8cc9e5b19d075cf60c68d536a23b703d353ad23dcad038cce3cba282c5ddaea1f18e6c188151d9c59cdaa4404bbadbafb86cab94641a2208ef24a7b98	1	0	\\x000000010000000000800003bb7e607be2d9d1a3f7f7e3cd7ff3c558cdbe99845d261590a6a2b585d6f63f4a6ceb61fbb33d828234d6429503cc0f373e7c3e23e0170bea653a8c640474532b582b7cb2e651107d658e2b721283bd00139731d04c5c217b662632e0c275ac837d12289fc741fdaa95d182b6b1adb2f5376fdd8ffca20cf73c6e2c11924fe499010001	\\xdf21316827f2decf525b0b4f29ee142dbfc79e7fbb47da5e9eb708d460d657797accd1b7d51a87242b07b1f67bcc6b382d5e4a570b86d6a6dec72e40926e8a04	1684431975000000	1685036775000000	1748108775000000	1842716775000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
2	\\x02dcc689811fabe69203f6d1269a1f1f8dd5c9d36a2540c856a0ed1bf9af1277e733dbffe6a906ccf062b45e4d0ecc01c64adcd86d88acfa138a6f7a0952c1a7	1	0	\\x000000010000000000800003d4e5205e979852869c0266b74661333bbae907ddeda3553dfab7224b4b3f4e6135c84313570e918eea206bfad8a3a4d97282aac77e22d524d7b8d4f29ed0989b8f5804ee8a4810902bfc01381d2acb4ec567d94526fe084a72e71c4dadb9175e5115cdb7d767c7c17fba3ab1a3a609a4f1767c8d84bb43118d4b7228537d35d1010001	\\xf9b8b2425c601c88cd4ee8de108838c3a7663a2cbc39faedfd33b1a69e789a6c23d3f257302bf0c9418d00112136d89dcd35f1501c5f9e6d65bd182b0b562801	1674759975000000	1675364775000000	1738436775000000	1833044775000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
3	\\x0704bb7a3583f5166565d1646472c6a8bb4a09772d3c788d8838841cc1ca526a221a013e5ddb4ddb9509074e023e24235c86e735793a56e39eb0e239aafd2ea7	1	0	\\x000000010000000000800003b33768fcd86ff082b26194d56626269acd9f9d1475642fe0564ff1ea3d6882e54e2dd32814638bddfdf6fb22b84b4136a8f726965d9a2f7e2e16c6fe6d55aa176666c7c4e8b97ae1f48c612afb13c7893e88f0a157def419539a2f984dd0e41694f5cb205bbc4390f4052c956494c242881026b551643fd17d590ef1eb513a09010001	\\x4ba71388f3a44a9a026fb5fbc4ec5b7fa06753b37651029e02ad193f9c151b6645b3ed7fbf9ec793291f9be1455b5630f2c1908848d550028625dcd5528d3c08	1668110475000000	1668715275000000	1731787275000000	1826395275000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
4	\\x0a88f3672463775dd2cff913deca8d18b401bb7f9683e5ed36404ec39acb18514c098ed291c74773b4ff7bc5b47a9d1ffe17715a9ce829c9a05464a1a2223ef4	1	0	\\x000000010000000000800003a7034d07511048892eeb8eba607713407433304a94ec6f19c449e616f4e42c328d38031be9cf75b787bd1cca889a0a520e5087b7870d6e9c487533259f91bf2330d783cfc140709e88e662d2dc70c3f87ae95ad3f6802c1413c877ebb108bc1336930dfec1b5cb5cba136652d561a85515ee9256a82622da315303ff0a469757010001	\\x92daed943297df1909df60ae5efd4ec430f58c2b0416f4f6429c17b55ebe12fbabf79ebe64fcc3b6bbffc6b49a61db78445d40c1c097b842fcd666688547160c	1678991475000000	1679596275000000	1742668275000000	1837276275000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
5	\\x0ca070de9ca7adedb93dc5d2b6731f3f8113013452d7e270517cab2094a75805f022c236978c0fcc2aa1c3b35279e53006a55ce67ea436a7f6324acf07b94cbc	1	0	\\x000000010000000000800003a45649c63a4707f794caa0c50663286b999c9742a5970fb9c46cf161546c521831220c0816c8be42cc38750534f5be93e48a29c8e693cbb0b43ae3c4e612ac13e7675cd6c239404492f949edd415de9cd2f7e0b106658dc7970f3b168d7d0fa1aa9788d6ee80d34db53717fd57a5e5deda70febdd67e9100d5b9734a168e80a9010001	\\x6146e6fdfca08b02193f3f733eeeb520be5d3f15c2df511c23c7c4a144c700565c7bc577b029966117494512bb88191789714c685d517f05de5547f13d46500a	1663878975000000	1664483775000000	1727555775000000	1822163775000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
6	\\x0fe09fea8f21bd1c7935a8f1c84bc9f3921c106c30e56a82e9458dda9b5de15e9fbc463b0aafed9243bdd2b32f9a923ae9bfb8d7fced94993342984818aaa155	1	0	\\x000000010000000000800003bc2308ad45996bd4235481e0dad6366d6f635da3111df53ad8a297537283a534da21f9f154b4b79df14bb2d0586a50d24fb8ff284c2cd90e4e227af4b17350151c04bba95515a0947a361ca0262b853de65bd3e726c4702c3cd124baa0133040d2eb5cb712b62ab1ea1c2c60d572ba38f182c1b378ffcbbe584c19e6dc4ca645010001	\\xf09418107361607a9abdb673679ce7b3c8f4f90b273762743a02461e2c2cb862c448464f3364e8b35860958309cb3b1da7513a5c8143e3121d39f2ba93dc2b06	1681409475000000	1682014275000000	1745086275000000	1839694275000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
7	\\x10f882592bea44739e872800944f8c69369bb916d0263958fa465193b67737c8f0473a63825492010b0f2434b48c20fe8fd64c5478710a6ca72f08ff365c0a14	1	0	\\x000000010000000000800003a03fccd74f61971c05f7f3a14810b06051020c39ae8e0eb92df36ce9ad584cbee9e0438be5cbed1bdc75cf519f67fbcaab56ec93d6f6cdd76de67f11e13882f1e783a0a969c3d09e46bd230c0f815484b674b2dd7cfa8366a5a90698286b81ed442ed28ffc4c12564727ee86854eed89d05a9a1c6143de6cfc56c89af0609af3010001	\\xb30a2e2fd71fea4b050a29d20a5fb2631741b7083e3068325dfba8af04ef5fb3ecb391e28a38ffcb5722d209ca3145a0e5979b5014e1c826463062718e9c0b06	1660251975000000	1660856775000000	1723928775000000	1818536775000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
8	\\x140c1e687a912e4ec61de5e3904ffc3205c05bb8dd8e7f1f3908f41a8b2558593ad0e4ba1255946363f41b58911b0a0e0d373dbab90764d14d92f0cfbdf88f25	1	0	\\x000000010000000000800003d6fc68e924f7bee7edeac259c821cbed1b34a0487f1f75558be2f4305eb4c357a22757046ec58603ec9bff65a10690042e29a95d505780ca46e994553745f4cd2444706bb7a61c89f551f1e72271ccee6dc4175f2f082ac841264e072d096dada91a0bb1c3db9ea13c8c93c393a7cf153e10a4017bde716aa166cc575b579213010001	\\x1c874a2a7a55340a06f9a2e167d629c46a9b71987aec8a913b0bfbcd0d85b1a0ac21f1603a725c2bd030b271a50edacd2884fc17a89eee3c161adb3d4f51ad01	1676573475000000	1677178275000000	1740250275000000	1834858275000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
9	\\x1524ef50e8629cb62814faa6003ff4f87ceb8d9538efd80b1b1d5062ce797d8ba6f9cb06ccebe82ea28ab10f0003b169d7b58158e3205e8b4f0ccdaa514f030f	1	0	\\x000000010000000000800003a9e03b40591fccfec3786018a5c18137ffea6ef41eae0cbca2292d29625796cdbaae982bd5debaf2375b08160fa8c57d452282da114e694cbc568e337bcf8290877b0c0108b5e515befaf507a830cbabe741744087c547363202e63b4fa32627b114ea6e0e4e58d2a8dbd0ac78853d5e829aec4065998009e1d2180905697165010001	\\xd9a73c698a38947c3df47f8ed4f8d9f8261a9d7e21378f6165825b22b4a96ce18d3a5de10d9e014fc6176891a647ef36c9c2050222e55f3ae5dc20b33fa7350f	1683222975000000	1683827775000000	1746899775000000	1841507775000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
10	\\x1acc1395f6139d5a25d8710f0c04ea5c5d7268e5bfa7877c731c2a27308e6965937600f7543907e6b14882ed2746a25a2a86356205db1cfbb24b5134ce8ead62	1	0	\\x000000010000000000800003f66602f28ee8371e2904ea0ec5221b29e2d2285e8c9c9a23c25200bc824bee8675175b7583d78cad4737051992d280f32f13a338820875b95f7a2e82bebbe18f23e66f2878d25bc5d8dedca97a5ba150beb618539657fc8d035083f862d30ab03b61bcb0dff9dd9f7b1311fa7df30c023fb8f0daf4ba1994e4fa71ab749cc0c7010001	\\x96b8cecc165fe3d25ed780f7f625324b8da6e9edf24acc4efcb8d906ccb4585d0dbbbf3e86b4ee9550a78acc9f21cabdf148306914588e73673a14ce3dcac505	1683827475000000	1684432275000000	1747504275000000	1842112275000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
11	\\x2098d1b90b770bdbdd53766f7792f857aa37efa543ca6f41557c5b50d56f8f68eb475158e35e16db51aa2c1c0300c5cce91a47f0af9b47767f4d539111418d28	1	0	\\x000000010000000000800003c57d117ca632d7a93bfe28a9cca5b10ee5620db8334fea17cad035dcab5f0fd6e1ff8f3318116ef5276d8ece9718ed5363dd46bc76df91ecdc2266b37e7d8783b8d64881dc874cf05be35e2028d814f0844272af55b412369acfa467c55bf9de93be52c7e792d32df2caea63de574820001c57669978883f8fc301c146a03145010001	\\x4cc49eb3cb8158c440cf30bc545afe46812c5c69eb0672e9a0f9b3e5d5d90421a8c33dd2cafb71920ed29638ee8a4d558d36da88fcd1995d3770ab8627d01200	1668714975000000	1669319775000000	1732391775000000	1826999775000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
12	\\x2868312e96e0f166537a5bf96981167181403467e8755e3ebba04afb31e7c6f7cb4c1035eea601224b63d23e3ea3543bca0a554d2103239e5649065df02c011e	1	0	\\x000000010000000000800003c2f6bddde4506dfe8fefc39dad9cdf53e49e80c8678731b5d1215428cc81684c3b6f4b35d1267fddc8b96613f6fdbc0eb5d9df6c4bd2f22255f2743f4918c2f86427cf80eb601d6df99efdcf945f8e31cf93d4d34c72e65f21a5a01dadf2e18652b194b21ad589614cf4fbdde39142780e446f855ef783343a2f9bd5120d7a91010001	\\xdd1765b5850465c6b44bb8dcf9aa333cdd17a7fc4a24a492ff7e98f2a08968f149517a592377c8cc241553abfff7f43c46e82af44b69ba4a553f6f9ceb1f960d	1675364475000000	1675969275000000	1739041275000000	1833649275000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
13	\\x28983a901a1278d5c6d04a232756b96155b2fa2634c65f953aad0a1cf0b9da712056e5d0b1ff49b3b221e39d7228c41b872fb649a246f9cc4078454dcee43b00	1	0	\\x000000010000000000800003a084b1eb46da5de3fde2dc7b2f355d2bd2e3bfac8e0040fd99d6dbbfd0b3357ccc5c11d3a6e1729d417523f8281447cc173441120189bdaf98d63e5679264105707e0f74d5479b7141039feb3605bda0309e756d5d30f015880ea8c15d796b798dd311997f37512429dfa526f9da608b7957d92b83a877990acd0fd82899a19d010001	\\x9817300963ce98d7ab038484c9302a269b0e6f47851d37ecfe0d202731b3972a1ee689256129a7fdfe8b53d127371477ed1c7ca8c9ecd760696959f4a1ef6e00	1669923975000000	1670528775000000	1733600775000000	1828208775000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
14	\\x2aa43bdd4739f4d106377286dd364d80dfba897a809f434104b148f3f021b17f5b0198fcc6559f933c698ef328932ee5afca382e45ba548ab076bd58bad177ec	1	0	\\x000000010000000000800003b23966d22241f4935dd30f69ee8f62ab78a834da7be9c22eb947518519533f160718ee9c009f3399079ecc0ef32f71bc086dad1841bcae8092cd7cbe503c6cb1f38d5be1c699567cb01997993e0334868fff8b312602b2f06493b38a078928be032f4a62c0ee9960375ca5182a12545d87cfdf27ada5b0ed826be791b9c82169010001	\\x5ce0046caa77491affb5c45da1a6b0dd29931d18151519b66a241f2c311534bd9f0f5b491ab933ca0bca9b1eaf39b635a9c635f40c6c6920140fd1a51bb1fe0f	1689267975000000	1689872775000000	1752944775000000	1847552775000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
15	\\x2ae4bd6ca14a7516dd28d7b2906dd52e2472251a8791ad41ad050823a36a19b34a06f16a4ba57cee31a9db925efb3a1d030ab23261f616071834f63da18313cf	1	0	\\x000000010000000000800003d4ffaa32f7915c1483cc57ae339f94777c748e4238a5971974f3761a384a97fe1ec7e9ca0809a228c82487866433fb9fe7d50066ecbf6d954c3611a8e384993b29a56b2550bd4dc8d403d462c43681ddc10ded8a6eb89a57cbf3a445901818678bb197baaa9d1964b4539f750f8db12c5852f16cb22d622c1ac3fb773cf1b493010001	\\x5823a5d75087bce9d464169141c40eb4782906077e2c5bd9b41e7c09d7523a85501da475453d6bde8d1d20b638b237f74629bb4a87eec5b96bc9cf476ab57a0b	1685640975000000	1686245775000000	1749317775000000	1843925775000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
16	\\x2e88b3c8bba21adec67fa9ee14d226057c7ba5d6232bfb06e432e4d1da3ac1409143f529435265270e369b4dda8afa4151c92533556c4c6d939ccbab3ca0beeb	1	0	\\x000000010000000000800003a7ebf7cdf2da4a05826e7237f5cc3d928529a0960821f19834c85540255b8608320429459257be064bd70edb15c16d662499db87bf125699cafde7646d50fbdbf88ae8c3b5a4b4c29535cc38e6073fe3d52dd0ebe3b41e2f8602a2f399ffe0bb941bbd9b1b2210adcad9e7db1365362517c31a2636d7fb561385f99b519ce423010001	\\x54977dc535ad4eca70e1915abc1005dbad86dec3b6af530540a5d6f533ea386966adda31d45a11c8ec8727162f3d562dae513b9eb6496150dba05abd28a97f0c	1691685975000000	1692290775000000	1755362775000000	1849970775000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
17	\\x2f6012d6a231fc5f475894aaf693d7d95eb13759a4255cec34c90e61e616b5c7cc41c484f25c5124ef13b6894c180115d22879808c1cbc33ce0889d66237755c	1	0	\\x000000010000000000800003dadbb4ff97149e85aa77bf75499f8d77279af94453c3abe1161f843765741f8ceda4541780ad511be267748fdaf65c4e211146a8567e253365fe701aa36d60c8bbde75c5d805ed1501b422b4eb77d57363a1fab5d8d750a69ae75697b2c0865b507a8a53feb92b393c5f02f702b71a1d45dda2d351c0db74bcba6af7c3ce0ccf010001	\\xda8dd843d5f4266818328228d06d3315abe47b84b3463d3e663b06c707e2760ad02adbf5fdd69aed03db79785e9a6232bf549c3964ffc4f1d438fce98917c30f	1662065475000000	1662670275000000	1725742275000000	1820350275000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
18	\\x3008984489dfd2389c6c6e9e0e0b11b1848a4088d32fb3455b77efcae7a2de0b4ba6d4fbfcd7bb0d232d6df820053f3f844f1c187a353536356c7e556fa42a77	1	0	\\x000000010000000000800003c1c29d65a20b0343eef4b9602b0404a2504ce8ad47c4d7f8befead8b2fee98c1cef4425b3b9a0c26336ea7e521cce532840ff0ec1bb8c081589a03422aedb02b214b56cb2635879be4551ca1650b05d8a540ca316b45dbb63b5722eda41c49ecb49d5f80d49a8f1605dca4f83350e4eb4a005c96da33be04105679b286055cdf010001	\\x092391d0b81421c775a2850b5910874dabadea504d4a1bc3d20ff1da60fccc3ee1db972cff7c282ff7e2e44fc18f7c97ddd7a4f87cbcb2bbdb58ed681b7dfa04	1689872475000000	1690477275000000	1753549275000000	1848157275000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
19	\\x31fcf21049b45987cacb844f6f8a8297f3a52a8adb12970eeea8ce84540fc43fa217ad71f3bb41db4b2750b439795b6e5e1349ee65f746e27325c57694c21324	1	0	\\x000000010000000000800003c47798bf4a9f39b0c36deb6c693f1ad07970a1c0120e97d3381bfc5c7d177d333155d67ee51e5dc22367ae1b746a28d701741d628b3639ac7569dffe858475609cd59376f416934cfa9f393cb0fee23db69fb1ed1342bab5546d5f5788e7fcf8a3d7ab1c7a7c2742731fe4a811d6d89703f6be32907e361a029d0745f822be4f010001	\\xfb9a7b5cc1e3bb362487841cf1f5fd252ff9cf7edf54085bb8f5970affe92bdd81bc2959096fb78338932774efd121ac5bcaec3f44db1c52251a1bb7c28f1f01	1689872475000000	1690477275000000	1753549275000000	1848157275000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
20	\\x35e4dfe5b70e61b9360c0e3d97f7747a065dfbbda93f67ccc5fea8e1feb8734f857e235e4fcb1541784964eea7ea85b65d05409bb545a0261894855c0935fc33	1	0	\\x000000010000000000800003bf1ed314ecc996a7078ccc9fbe2cddd5c10c8ef80e74338aadec31e06bdbbdf4632292829f2cab40d5ee774a967549225bf3e93b7b6b8bf2a06ef316bd44473a33eedde493905f3fe9ebdf052c49864172cee84ff73e3297f33e1b4b3a6711ab81ca536fb35bada8134d85fe8e338866499510ca6cba814d294f90364c50b015010001	\\xe397060c25acbaef622c0cf12ac7c16ab551a0b73f4bff12a1bda2c3696d64970c63d5867bc0297bbe96417ae0a76734746c5bae4600b713596391e40b597d09	1690476975000000	1691081775000000	1754153775000000	1848761775000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
21	\\x36b81ab9e9a71e75f79cce1772b4d70396a0082fd990eecff54dfe56c94373e247190952b938ef05a047895283ade770844c64ed72848fd9af6289dc7e2ee48c	1	0	\\x000000010000000000800003ae77d361126fd26629bc49e3485da801581fe5af18befc9de5d6e9e463060aa89d91fb5a413658d800de11bd49d6f488ea37bd58002ba462a3c08238a23a677dbd580f3a9292668271685caed5691d73b84393f18a6a63948294427096a196ff273e6750e23d949418e48395df85507289ee1ea493f0c985013e8ebfadf97d8d010001	\\xfed4356958b896a91a256bba5038472d618be7f50894b956ea2aa8e8f494a6bf646aeff1dd125496b6e5d8d403f0dcfe4bd32f2b027e901ca03d912977243206	1663878975000000	1664483775000000	1727555775000000	1822163775000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
22	\\x37a050b1adb41b20f50713a2a2da01e427e1e3f1bf54399647dd5ac993e6742e6ccefd75d441d6f724a6f41d3f705bb8d1050a32dfaefa12076d062e82c279b4	1	0	\\x000000010000000000800003d5bf1ab6644d6a3d66d2dd9c40f25e6399a6c28a4506e5758ce55d48e82d954135eec776ab0a5f6e9fb0702e411ce6fe5eea823983220b1586928b0e98fbdaf7c230fded6dfbecad6f932c610799045bf135e18400717bbd33e0d1f397d1276623da11fab1a51ddd38467685fa66a6674a4b3c39a6e9149662fd34a82899aeed010001	\\x5b2c821940c7322b27b07d5ecaf41965f103289e945bef9df4116447e8884de6914d9ee2ceaed6b26095e1000d120df8f9d40424341de6b483ecf6666fcf4406	1667505975000000	1668110775000000	1731182775000000	1825790775000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
23	\\x3a4ccedef256fd7a1644b9b1f7101471d1605bc1e39bb3aba295b090196bba1b53785fa7fab87c96e8693d00471a26c0aff14e51b7fb1b9049008ef9ca20b5a4	1	0	\\x000000010000000000800003b5a7a13df1d4fece7b3d93bdc9cbb1b8d82426b79e278e07846b6cf67162255652565561d191953ca126ed52b592953f688bf14ff9417c27626427f5295761d038e3b962135e82baaee523caa2cf56d5bcb0deb21936d320fde753e32957890315461cbada77ef622b6dd0178310e10e8bbb0c0b8221496c2ac6daf9cbe12931010001	\\x0f3610f78432298d712ab55c788c64d1c094854f60360288e6beaaf5a1dc84a74687f10bfb101357b4d2501079c13a9166d2f6e682a8957b3a1b97908d94bd0d	1681409475000000	1682014275000000	1745086275000000	1839694275000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
24	\\x3ad4ec3ae8e2d81e521a0efaabc32ea6ebedb5e52b663876d565c5adb6119e24c86dcacc6aa2d64677ea26c5274b22b067fc019b71b02dffc4b602ec1369021e	1	0	\\x0000000100000000008000039cda9f752d862017de6df76f1bc1b247c420b42e12cf841d3bf84c600db7d0391a74e1fa457db40a2c8ec2a7b0201105a20bf66c4b9d1442b887f6c0fbe52daf70d2d171ef920a94946c6c7bf2cade8575ab0a835e63580725a1e1e816d8a97a3c6149b8be8fdfa75a8a14266c01132efd6f9272fe2ee348e053d23ac4dab6d3010001	\\x43fbdbfc25561a440ade86b877b2e6b022e4a7e00fe455df5e4f8e66f1d69177d5f83678be0045d9625ac36e56e4d40867055b11ba2e148db5c322f676682408	1670528475000000	1671133275000000	1734205275000000	1828813275000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
25	\\x3e90a896e744010344a192a4aabc4bc10cd54752a7775d840a7ce430db9fd086c546fe89d83b0772a9ed0300d6e44e4ad4f39a79cb4d60653e4c2814867b9434	1	0	\\x000000010000000000800003ecb970743b29f34935d86cd4d77eb21698fe4a9fe533da0127da64125ff5293392dd2584862fafde631dce2814031ce8f15ebbe2fd4b8b3661ea7f98beea39b2d79c2b5350f917353cb07aa2f375845f7e3f00b0fa8b977e9059355b9f199daf5cde7e40498f25276553bfbc8ee59b65b754aba727d0d2e43b8d52d617ae670f010001	\\x2bf1e885fdfc3bc3a90bab63b24adc0cb3f1e26a700fb9e795f8c8bf320c5ba23386245a2bd7c10b9bbad0baf617e74e025719fd5830428ba8c549099d10cc0b	1682618475000000	1683223275000000	1746295275000000	1840903275000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
26	\\x3ee0a4c16881700bea6c7d9190f83b8105b121ecfc81dd560809c410ed81c0dafb874da317deeb5a05d2feaaed863101ca2cf68381d560af23a0c7d350eac1cf	1	0	\\x000000010000000000800003d7252a6387ec235335d9ef3e142eb9e1cc068341fe5c2acf1a8214f9f07e07468f241c730dcf0c7403e5f6d2ffeef3744ac59a319dea722c7501061d7a6d4bc2e5169206c08b562538283609f3c7d70085361e282ba407a3ea4f97dbdcd215a388dc8c1779f7b17f20175c17ea4f5ae2f3f221607f05d23ce4b971a383fdcfe1010001	\\xf87c2a42639e1fdc5bb0150def5d44bb59326f8271cdaf1d4b32d047455d8d3d92423f93d93a15f143475ebda68704ec36e96dcb598c51ff79bb224c88a7310e	1688663475000000	1689268275000000	1752340275000000	1846948275000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
27	\\x416c27ddcf77ba8aebc27d06fd132c0971d70103717fdce2dadcb80ee391d533f016dbb29e26cb423b1bfd6fce71eb563ab8bf6490dfd404f92ca7e6e7835c17	1	0	\\x000000010000000000800003c8e0a36437d03ded00339c62ea8906ebf24ecd57a7d8b9c0d9b9488bcfabfd59f9b1a02f4dfd2fd0a5a5d931ba40a3b1d1209871c9d7acef899750f997ff852e01a45201572b3547868474eeaf055f568045de0905bbf8b4f2bdf35cd42c755b00e875d7508ed39823dd70d8de07b74d13c6b779115d73c5b2e87302b0f918dd010001	\\x8c446d92c9257be6cd37c0d4fff98d86f51600ebc6cd79e1aa9d8e82c8294a1c3f4797d22f56dfd3a39fa79cfd89e49b2dc32289b1efda7eb53945b45f83670c	1662669975000000	1663274775000000	1726346775000000	1820954775000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
28	\\x42809848342f0fcb16e56bca752d3bfe7305d727c16b73b0171944918a0425c55c11001effbe527beea99a5aa8ca0d2acf051fbe11a0ede07c0ba93d74c7089b	1	0	\\x000000010000000000800003c5f94d58394f613a12d08c56c673dcafec5f149070239a7d13d229ae9f086b1fa7d1da2e0bf60c924e050cf9f4889ca468e8c3f24c7a3b5c5bd49912d2b50b1836e306ce2af8ba117a678d4b1fcf64c6ecea0d541ba04e24bc6d61e6ec3ad5b77a84fdc5421f543f7ae079d66057afdce98fa503daf96f083e1483dd9420fe5f010001	\\x190a8dd4e8ef3c05a848320a9caec44c304eacf4820fd9f7ccd58f616f08f108e5e426775021b730967e5bf24549f61ed14e426a748ce47405c8bb35e3751103	1685036475000000	1685641275000000	1748713275000000	1843321275000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
29	\\x43685791c591dd797fe39615a65a2d0b60485db760e40af5661ba5613625b00c6c35a234c66f31e5f306cce80ae071800ca68389d1270beb5967773b15d50db0	1	0	\\x000000010000000000800003b978b9c02541c4c6c2c9daaadfd7d7c7cb19b225dbefa26594571d28285914275ad1b62edec5b76f6c2437a7d0c26822035d529661757be1dd504c9e5471ccc8f269011f8e63c170037722916bb7ebb1b472e74e9645f136b0354298a37a99f6e7c85b3c46aece2396504831187c3866741832dfe04da6151060c18d43b98987010001	\\x2699aa6e074438c8649c23c2b467747a195e5f2997031177eb3b816741d89f39992f904ab01dee8fd449c9e714dc73e0e01d1effbbf338d2239c90f6e2e7200a	1680200475000000	1680805275000000	1743877275000000	1838485275000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
30	\\x4450c77926e3c5d37055ac8e2d3923bb7cdf4a42f509fd2bf54b8ac717117c6e3b05ce7098940784025eedc237c3224bea6d4dcde375870a05b9f0cdabb8643b	1	0	\\x000000010000000000800003ac1c3df8a683b0b84d3989d764fbc8f0bcb309d915230ca72db64cbd12cd0b2fd86654615270cd33631902dfc85f00457526f35e637e3a7868ffb4e2ef755864f0d52240e8c87386b208656b2af3d7941d67dd1bc7d7d4ff73d665abb5b5f9fbe2eba00fda8759815fe203ec55891cdc9c22e57a92a24cc37528c6a0a542e059010001	\\x16bc4c9f1513fd117541a1625d67f0fa08ccea46725f32d3f87f7f967fabf9e39f160938c9e52eda4beefce591553f50024bc423a90ab275b756ed30b35f400d	1680200475000000	1680805275000000	1743877275000000	1838485275000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
31	\\x44507adf34939182e741d4316b52d1aadb5d02ecf977b6beaf4d929b34b3c91b9ebd853e305c89b144073ee1018aa19d889b155fd561afc625f4195238315465	1	0	\\x000000010000000000800003b6f9881dd2bce7311af3b25ae09fb56d8fc445f63022c938a690dcd3a7ebe15bea14ecd7896331e750ea60c1aa6d4ccb1213ed68f0d09a3283f7862149d738de929d4ef647cceb299bb6ebea1b4c007bc8169755a3a79c5e7a3b7ec6e17ab156dac55563e99060cf1fba6f786f26b663aefddc5f9c3754ba9cdd768aaa97e525010001	\\x326c8678b265b1a0fd6efcbec6a3d627a69d2f073e2b13a2a76e0aa82e6d88ee80e2e19331a04da4e0edd347bc1d37305c5aa4bdd68e777b7742e9df9be32b0e	1668714975000000	1669319775000000	1732391775000000	1826999775000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
32	\\x4754464af2cd2ae2a5bbf949e7b24ed59548618560f5328bf58935f8f253ff8e207cfd9b58244dd8b052d17fedf15900dc8d454307eee8725fccf2679f7f8822	1	0	\\x000000010000000000800003a4b4f2da41266d45f9575fe13451ebb570ee564bd3ddf848b2553da31e4c574fa5df374222781f33aba0564c1d347301ea70214348f0c6cff6784ae5eab42b43c191fe380280d957b0854353402935a9b70e67d6d995cf707207ffad2cce7a0ba852933d6c4b5d9950dcc37e501d4f31ee9c63291f3ff12cab329736dd936a2f010001	\\xb4d9cc676143d5097fa4c498cf352d2cb3f7403f7763a6927b37438d4b3afb3af9af77a19abb83919d1e25ed7cf0c050865a81f180b0afb358acc21816ac8803	1662065475000000	1662670275000000	1725742275000000	1820350275000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
33	\\x49f074d824cc7410f942b1ec2016b92f19bc5c5fa5d3f6230e2d07ad722e4fe304475538e523ba4678394ff5f1c4a7ec14a2932bda44a28c462a36c045a09a0c	1	0	\\x000000010000000000800003b7dd0b4ceb68fbd21565f75c25c2133cec70a89db42dc3586f22e10f3328159d38db0bad156a98dc607b698227a815ff7d05fe4300269e9e4a073d91b7ddfd2a8c7c24f9a0785981d649029f97130e5a656237cf3774f0d7ee665b7a23fb1f764c8bdd62efb3a0fcda0984eb8418414bfbe7f11d00f84063aa39aee82716bbb1010001	\\xbf43e44bdfba3df64f8827230ca01048ce5e779da096665b6352ba342221f9ce04dc608cff1479652b28249e867cd1ddace74214ec4da4019cf88a3af13d310c	1691685975000000	1692290775000000	1755362775000000	1849970775000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
34	\\x4aa8a2d156c82e8809d39bb38e0a09d1a2af344c399b57528582fb804465b7d8e1bdd0cafdecefc240f302c4ec59a1efac9bf97a15a838f24943e839a94540cd	1	0	\\x000000010000000000800003c2893ccf70cd63707e628f89d05b77844cd721971de0086cf205f50b6b5be6e26861ce5ad67fdeb692ccf151698ff5ab70e73d9a5014b82914782ce054df0c5354d7780f848e76af505bdbaeab4f1787d20e81b3bf526692460fe52c76401063fb01f8578ea6e482463267b626cd84fd5aa28bf1ec61a2c15c5520b0531fe907010001	\\x79b366dc3fff7eabaa277c6045212c1b509cb9f7b845ca45de70c1b0fa95c7fdb712c59a14fc2dec6a0b8ef361bc024c66b6de537366bbd24414dab80dc1c405	1675364475000000	1675969275000000	1739041275000000	1833649275000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
35	\\x4c2c2afa406db883f6ddf306ff8e8f2c38dcb123b378d28d1ed213ac24704621632bdc31d32805162d2237730ec0007d58982532c28f5cace19b232dc9a617d5	1	0	\\x000000010000000000800003b003e7bb95da90e606f4ea5e9d28a107a5c0cbf80eb804936b6be40bfd3301f3a9eced165947aa1c30a663319a35c431a1636e4432d3f1caecd691957363ca6ae30783c88777159e5dfc9bd9a56a587245a2c0bc12301660d8865e67e2ce66bdb2baa939d9eecd69c0503145758b6c803c00c62c1e2d97ffc9794eccfad7ade1010001	\\x4857480cc2682c3633813337aea2ecf539f3eed1927423ea4d9612e2cb9f183cd830d950ca8f8277508c18bfd5a1ec98657d08ca9663087ab9435a74e6a06d02	1683222975000000	1683827775000000	1746899775000000	1841507775000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
36	\\x4e4ca197a649003e09e1a792ec09cd6445c37186c7d0f48c59fd726a4e9d268616f3dc685b19d08bf4617c631e17f58ce935014eef34d11269c9e0d36ee6acea	1	0	\\x000000010000000000800003a315344dbbe30f2d451152e95128d509457420db43aae82f96bcb62b89e1a4a6cb4896107e8e13383a1af4654ae628e103c35056858bbd7b7c3a53e2cc627ed832e1f180e3b42026b8bad79790f10f65e977f4e3ddda1f5cd48589f547e42914740c002b5b20ef350c15f14775aebfe0eba6aa341473f7504f82d9617dca569b010001	\\xef7245cf2687db12ca9203f3946b6a09126516a6ddeadcd476046a2c7f6b2f0c35257459e9874b9af2e53e3be6c0b491fe3f5af7c74e42de4c1dd07cce6ff10c	1679595975000000	1680200775000000	1743272775000000	1837880775000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
37	\\x513428345c8329302a45923a9f031a0f108223bbb6a5a14934ee2c4a1e4acab1286f3d02d4ae2830c654016007ab7dd91a1b1f30e220d321c9bd60be784afb81	1	0	\\x000000010000000000800003a97637e1cecee92437746cb0fa1286c900dae35cc013a7c223a040caeb5b94d1462cb5ef06daafcc51d56dabe4dd7819fb48d619b9b0d27d0a0b154a21c56a95c0777bb5a097ebe057701bec4e4c996e946d76c0864ab3b1f919dd46512453996ae85c190e9f79f4de853c86474ffab8a3908d35a7571f9f44a1398caee80cff010001	\\x7114d83070af023d8f3b9e5931bb541e7d3b9fb943e955c999aee21079fd4a823d544982650fe59902960d7cea2afb5e7efafbcd59f5aedac4765b373776a70d	1682013975000000	1682618775000000	1745690775000000	1840298775000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
38	\\x57304f3578d4c550ee1623b4557f2fcb6419e41702e968f9d30d5bbf7e99b39a10d44067d54f15fe641ae0d7ed833941810c89f66f875f8f731ec4d1bc6014a1	1	0	\\x000000010000000000800003d54b1444b11e7252a4ccc369afdb3e604029670cb1e7f37bcdef235530ee8143d40cd9c0e17a1fc5873a9ea55377f258dc3ecf6a9e61e6e214f102eb2c25c1929ea5beed22dc3c53e2e80c31d5c99e555038d58653fef9ee74ccb8c58afd87ef19bb2278bc38f3fdab0e91ddc8a7ccf783a95190cef765885349f191aa85f3c1010001	\\x3eb538014d3d518e37313e3c8e26364b6f59071104ef82bf7d6857dd6da904ccf52fabe00f264556d714d9c87ea529f6cb5f325063fda423aceaff50178d0800	1689267975000000	1689872775000000	1752944775000000	1847552775000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
39	\\x5ff4e6af3272a4cff7e34289f1a979de9d9392ca1f14662dc995030f839dec06a40ed9fdd97dad0bb08a63d1582fd1eb20c6a79d42d8cb15f71ca0e07e0bd7c8	1	0	\\x000000010000000000800003bc73dbf041e222b8c7bdf3fccd33119c52e19a548598c35e358c23dc292e48d7ac66f2932dd131b8a7133531b856eea4e04202b11cb21b9ac9cc0727f4634c454a9b4b79476da8bfb87097aba7bc27246f905003ec124692a9935736da0deb8d68ac4451641544e35293102c90aed69cb0fa7a88426c43046d16c0c41cf16305010001	\\xb5fbbcb2f2a859a4c33ca98f9f80aee4aefa2b87cd2d60f6b68fbd9623a082c149b14c330504c43f313af1e8a8521879336958c3ca8afa41a21971522df06d0d	1664483475000000	1665088275000000	1728160275000000	1822768275000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
40	\\x6068fbc6777498e8d240003ee16098adb6bd66c045eafa37aeaeec312d44101208966b07ff2b917c1211792637a6c9f02369a1b944fb358a068c9c5b536778a0	1	0	\\x000000010000000000800003c49a3049b2247d14df0c304e1b87a21c0878fcc62de598dfcd2693f8d907a11fbc1b047c18487c653e87edbcdad9ad6f8cfdb21843f73301f0a994ab09a23def9fb5a2f1c6adbe9f9f67017d274bf3a1f7025baf53f0dad7dd33299d661d637d0df4a1d67ee81fb08dfde20922dfb9bb92ced3a6cc8364cd5a94b5ffb1b979bd010001	\\x544f48043525a72d4dfc982cfb27b001d25d99a7c73e33dc9df637129e7f3a24dba878c7d5defe87f037eee1d9ac0cf7882df81c0824f3d797648799b17ca308	1685640975000000	1686245775000000	1749317775000000	1843925775000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
41	\\x62001460d6b62265b466bc3da8c12f6347c9702154e5f4fc88ddccfc54aedebea5b32d787e6908080b06023960eacd23db7ab8b5cbadd947b5d80e7a0e061e4d	1	0	\\x000000010000000000800003cf409be6dca8f7789557384eeea025e40b501779484488f6a00b9c1da10c0d4be1ed191a7132e32fb7aa578b6d2e2a9c4d25ef84405a51933b39cb1167f949107cbcc87766c4a8f67c18693a0813e75091e1105e201aaa12f9f64a1be8e12f6ed0132f024b3131f34190890a1a4cf2562c93cb9937dc80932d3a26d9903dfd7b010001	\\xe4079b28a1ff4afaaddce7e0c5abcacac3f4bc87bc9f85264fdf42d2da7e9d3b5c182429b35e6f75395dd62a4f0fa2b80db231432637c8edd930b1778c370a04	1671737475000000	1672342275000000	1735414275000000	1830022275000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
42	\\x65ec59e1d91b66f76049b615a8efe10d53311b87b578e96742a1b29411b516e0c9b238c572e361a2d516b5b41d613600051c205694d263543ab6977a9d3c7ed4	1	0	\\x000000010000000000800003ddcdcab1ccb84f1524accd2f3e5ffcbf144ded67f815d0c2acef92c747d64b7460dd74d8250c8dae35c793034cae0fee1bca92d47f5e6fec2bf81c590b2d3af140e472f8024bcf0d5a9e1d9c35237c96bc7f740566b0c6f0bedeb16f9a655a165e9bcbb5da771c7ae01c25346fcf6d84bba38808049c464f36a482b16a002813010001	\\x577995f339d82301709ed47c3c0860ce6b18413d74cbad5ab823e9e616eef0d8f9dc00cad91a94be5d467571a2fd1ff60893de62bdbb88959b5694bcdbe83f0f	1661460975000000	1662065775000000	1725137775000000	1819745775000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
43	\\x6bc41718d883ea630dc2a97f0313484210f91c21fd093d5866ba98ac0f631ffbe5cda81115dae25cf1fd552bc39361e5c719cb05fc39770d9a55eaa330415057	1	0	\\x000000010000000000800003cee8f481f33550e07409a8a472014bef059d1d80b8e88dfece2e4d7247fbd42a23b0fec92ba54f3701ae027508837813ec3ed1d3427ddd9e208c36bad539a590be76739352e52f07dc7e141ac782fe0fce7336cc4516838fe21d331b595a6e4a0698231d8f09f0a96ee39fb6b25dfdf49c0ee02123403058b7a7f15eee28905d010001	\\x5ec680cd2dca602ab846e2e25b7fddefdaa60307ee02399a2c6348de98687f24065f0c1e3b75b739c651202a361420647b5d413f0edd50b5d1015128da21510d	1691685975000000	1692290775000000	1755362775000000	1849970775000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
44	\\x6dbc4c04acd4a3d2dda006e46bd8f3e51b01b1ba6b57468aadfeae97fec3a694aa50701d96dcda6dfe2087d0bb79f9f237d83a8562aa41167f0b00e5bfb7dc61	1	0	\\x000000010000000000800003cc851c101643f7910ff4cbb67928eddcb48d97b818a9899ea83e67543bb13bbd86a7e29e2778a43cee4eee17366bbf453e78b83aaa150835bb69505edc096a75546778afcd1d48b41def5e971478339f7d9053833d73ba4077e1d528d63fa1158762c48611976e87dc4e8391f13d8428c9530cf0728c876f09f5b3e26a15a15f010001	\\x9af0289c3f976790bc1f4cbae7f26d86038055d7c8d44557a40771dc82d6fa4473e2deda1e0d478447418a8f2cd02bfbb3b1dd0cec2e23057e90606c05cf0702	1675968975000000	1676573775000000	1739645775000000	1834253775000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
45	\\x6eaccd07aa907f601eebd638a5fdf7b6136f8fbb6959ab111993e85a26e8f1e0245db33e3272920c2db36154a9aba0882fdabb5d69747e6e9590bef1a7a6cdd7	1	0	\\x000000010000000000800003baef8ef23ccd5ad96dfbaf3279845a8017a7b7b54dfd056b9e53e424ea3b86e2ffa07a6c65e75580c3de197083d9eb625d958f7b236f6488734892a58ccf30266fa0df0ea094422e365eff17c739290ef9c5017690bd439721fb00df5fa1114611f08e3d72aee987c27734dba61812de988ad900bdfb3f02a13f68d374e4c653010001	\\xf830d89b05b290fb18be7a6cdf71ac952423efcc17f83ee1b8615c6650ef4b49b28f4e1ecc4b4cc62624ead77f824212ac87a585a539273fe5f8adbc978c3e05	1682013975000000	1682618775000000	1745690775000000	1840298775000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
46	\\x731c8c916876ca4789e8dd1e9286451108e5d27b97eebfc094869dbe6e3f476421a7e4ec70c55d70b60d4a6470f418e3f737a8c3f76b4d390e4ecda1682872ff	1	0	\\x000000010000000000800003bf48c4dcaa1756f4a1a8dc9c12cd4ca0d3351de8d7408b382c279403b2c4e2f065e5fc3cfe9ed8c3d98fcd43e383a5b36f7f0e6763bc14cd46518a9d6c9922193b472fa10644e9a8801d712f4a80000b9f224dfd062adefaa912d10f748c555ef65baae5b799a7366acd820c1cb65064c5a97cf68d9bc73131290533f9ba213b010001	\\x5a9fca7e3b51c7d39ad087251c6442d0c109856ca7a3812fae4d3db6fe41200eab883fdb3b7811fbffef80034398ae867a3c2c29d970dea6ebdb7d31dc776103	1686849975000000	1687454775000000	1750526775000000	1845134775000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
47	\\x7524a31a34b7a4423d1df79b1dc984c9621db60c3c851764d536d500bdf562c50231f8e2c959e7d90ebb3f7d0830b47adeb77e26c4e8e46bbcea8388b63a7a4e	1	0	\\x000000010000000000800003b6321cd2d159f25141e1d5770a8aa7eca859c46ce3ac6fa3ea60b3cd54165ca08a47251052ea99625dcbfd6235bd39eb340e87dd06b3f4c715ff429fba7a1cc43b5663f8ba48b95da30965fe508caf717ad24ca2037fddb0393a005296e3c70d031c6bec3ebccac16925877bd51dd35b4075aa3289bdceefbc812dd959c6432f010001	\\xed8a771ea673b4bbefe4bbef6a7252336b7493be531aef6f7d1fef1ca9352bfad5403d333a92d8301853ff306118646b9269a3619bc1181c98c0eaef96a5890f	1668714975000000	1669319775000000	1732391775000000	1826999775000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
48	\\x780037c3985523e08d722ff077e5bf107c9b0be7b95dc0a7865ba0129b786fad914be29834a520d71b19615ffb59a4941ee10472fefdc807a1fe924f441dd036	1	0	\\x000000010000000000800003dda5e251796824f410f20559d67f2498a5f812b29309f11ee89c310bc26a4680181c5e7aab7664152e12cabd14c7d9fde332281f0d5f114d65613c917832b98aa673e3d5b84bb5018936959bdce50d995c356466ae6dbf1c12c8b2fa9f9113cb23a144cdc6614786aa0bd703b8460d1a69e9d6c80456f1bdd49ae9e5de953433010001	\\x97b92410ec1f4c44497e066d495e37e10838560dff814ba16b5da96fe527e10d51cb6efeacedfc988a0145db48bfdce1e3ebdb8aa6451ed7895e93a56c7fc30c	1667505975000000	1668110775000000	1731182775000000	1825790775000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
49	\\x81003cb767570c32a1618e7dc0952bfa1023bf7fe127c928eb4d50ce85a0762b04b93fa9ef43edc2a16c2be2e27b8180aa02a0e465f08e276324f5c86b536991	1	0	\\x000000010000000000800003b8740d89357e9e04aa5682d9775a260b26efc626b27ec05680f53da2f1d6934ab9fa5554eb62c1b6a1287991e1c263c3efc47a948e7337329316dd05f9a3418f46a6a88e7feb7414d94cc1f34667e61eeb28b9a23b468c4c4e1fb84bcc12e30a2aebc6b92439adab5b50fc7df20a55c2d15b759875f9878cfd1f7a406459ccef010001	\\x987aa42e8d2d2d3fbaab6aa9297528510f22021e55155cb5d41dd908822c0391302e9aa2715ae5f298356cf5cad5f357cbedc43aad75c5ee6727d277da473907	1685640975000000	1686245775000000	1749317775000000	1843925775000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
50	\\x81e030543087de282877f3f35c4ba4fc33cdd8566966f7307898e0d3616c7b4bfc278f2ce4cdc97f9a4a7fb4474130ced3ff317cc6360cc5bbe30ac0845eba9d	1	0	\\x000000010000000000800003dc7affc3ca81ea7a719f7406a03e19142238b3320164629090a0ad53bf38a5a490793181154daa08440f3339d43936f413002e96f8f5335b513bb2be7ab74d873e0f7c207f4a192bcb15f90596d7e1afd3364ab338b4eb157f6d8d32a6ab25aee13d06780393fa2e0dc007e357c617a1c28adeee77a389a60c26e82c31314aa1010001	\\x32c96ac5d50f30a863b6eade9944607e6e6bfb94a5d21f5e13e981bd89effe1c02f490ab19b939eae66733662f8ee2aff7c0e8d38bb35e67fb8dc519027eab0a	1666901475000000	1667506275000000	1730578275000000	1825186275000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
51	\\x8284adc7843e114313536a6d0f3c15556e7e2db6a5a3e111066a57175d0882ab3b7de7845545c2a6f6904c60c659b731137b5fe39d23040bebfa64618fbcff12	1	0	\\x000000010000000000800003d26317ae1ba4eb6a6896591dda066c7c9e8af843a4a5c95e9017952f10fc94b7fce6053b19ecd90829b12139dccd3cca3cbbb68650c156ba9f805d44ea152039af291295714cc879815c384de06f8d684d8cb058db1ee92f54cde22b8530e0253ad9ce3b3fc0779b0408c65d64f86e39eb02f3a3e83815daa279e417540b3f4d010001	\\xd232d268498c5fcb04a4284b5a4c5ab7ae477d6326aa46db5011b62ad77b6ca8cc588b94a07ddd499db567d4dc71ed3b39f29807c3bcc913ceee5fbd67e5df0d	1691685975000000	1692290775000000	1755362775000000	1849970775000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
52	\\x82986a8f3713037e20d818d4127ef8b47725412f3a1063a0d219b9024d877a41a953a812841170aac4e9806e829618ce61dbd95d3ac1017f3a7b6d3439fe685d	1	0	\\x000000010000000000800003b87a0322d62d5e783ef9bc73f294440c9c0a453705d52b947c0db70361c3aa4684828b4139c8048faf7a72d2c28d6cdd9e73e2c7be73e9f0425ed2695f4acfc190b4bea4ac544744eddfffa20e0a38fdb8bd0f4d3cb89c1f355895eec62f55e56361745c80f5996fa54fecb9623bdfa01d7060a5c792ca2be28434c5496988eb010001	\\x9e7c1a6b1625a0fbd6f02651ca671cb69cc82eb643ee42fde507670f69b49fdae2727b155a8b70258e2532d229e8dacca91b266f640f2822e59af9a82cad3c0c	1677177975000000	1677782775000000	1740854775000000	1835462775000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
53	\\x8208d57a28c789393c72effd06e3b8d1c51881a13bcac347ae7bab9a5beb515506db0b4a0c1608a308bf280a7c8340b25f1ff3393945142d4fbe392a02448938	1	0	\\x000000010000000000800003c2e4265078ad23ca293591caf957b38ef4e4a8f9a592735a803c9364c2595dfc1fd7059ea5bd353fe4b3b34ac09b3950d05dc693b318630bc876c9cba962eb9ea595f29c95332543a5a72b63d2d8a0d11ea6a39150010c3fe369e3f66a9c8229984d1476b7b8439ed39b257b2d6fce0aff59daee8a23208708aaef18f3bf9b3f010001	\\x57d9db202bcdef287f36eb9018eaaf38ad0144905fb129f03024fbf7b46e51d3a155bf62610f12fac21f62c8f710e516258420bf95bc8479b1804b43f0c8940b	1660251975000000	1660856775000000	1723928775000000	1818536775000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
54	\\x84387225e471ce2538cd13a33f82ba53a5131130bcd57f90eb8195e2373ee70ed52ccda6d084f21fdd7a26dad4e15f6c857f39823aa4c1954de2acec922d2878	1	0	\\x000000010000000000800003b135b90ac2a9e9a31756293486ba9edf32b364da00f911878f8313aaa841b909ba71f31fbf5b5d1b4316619e4829f22dc0a14652eb6b63e3d2e9bd2741e24ef734a093c30564b47223ec6a02d77a8e96e0e1b2dd799c667a047b09493ed8c4a0cb33e4acb086a1686df700738858b48d260739dd1a81c615ed2d1f8382a14837010001	\\x902ab74e0ab9a075795a13c24e89931b8a2f8b72bf2985fbca5f3e49334af47dd822caf3df61f9835ce7a04182792b8e549f3e95f0d10a964a1723be052c7000	1665087975000000	1665692775000000	1728764775000000	1823372775000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
55	\\x87406dbddc0cd833e4a3ab928bf7bd51ac22e57d64ba25b321bf75c369f49eaefa29a39021947fe9d7ebc0fad75cb1b452e50f1959f512b58b7a91d694dd4923	1	0	\\x000000010000000000800003c9592f68da215aeb9b64f041c21d26a3ab0cc8a1b34b00ae4a622656a090ba42f7bae0b82eba104bae607b847fcbc2db0e9fafd82ccc8d7fe125e455ae867983a8225c1735ce87c892fe4a3e9996a973a4dd33c92b3401fc96750787eb293e7995adfea16a66e062a6f64cec699f2719c2b10709e19dc175d57fec50992710cd010001	\\x0be94c1b9e5a8371a144568e8b431828ab0f3449ea2bf396f2ce075680655c2b9e00c591e6b88c569c7b51e669902cb8f3b0db41b7c6117fdec9a621820f6f0d	1669319475000000	1669924275000000	1732996275000000	1827604275000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
56	\\x89d8d03fca3619697785c3ffbc04ecb8c8ecc5a08e57d33e09311cc20f5198129f583f4b3faec31d22516410c92dd74deeaab84cfd774473ff483151c16cb2c2	1	0	\\x000000010000000000800003e2b7c0806505b45b4a40c481971432d144f827a7e10a401fb5fb3f6a78c3e039086606ef34d73e256e8218114f2235cd12998ab37fd6a39343d5e17f5d70657f893961bb333bed50b0d077f6fb16f69d6cd49af79fa0d8286f62a7f093f8f65041dbb22d9df01b4abd839f41ce31326e6fe9740b244a40ad749079df447e51ed010001	\\x0b9d1cf54bf9a075c809660045f14420a5cea4f500c0f0d2c40457180082b6330877a8985fdbe441405900e00619ee4e4d67c070296898be3666a81d0e1c4101	1684431975000000	1685036775000000	1748108775000000	1842716775000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
57	\\x8cc0703cf641b079bbf5e635bf02aedd2c9c70bbdec4b05bd0b56c527d9364ee2b5e6e2ec731aec2b5134b2551824dd6b845bf206745c80cb04af2cf6880336e	1	0	\\x000000010000000000800003b0c27826afae518d2492deeca180bd119c6ecb7a3b1a05a01aa381e834f6e30e3f0e47fa3956341b7e56881c2e9c865a581d8a466b2a575c882629327945f247a18634c76acdd6ac1c8f6c70885ae3da4854ec68d0d496f8551f28f87e952fdc63b570708c12d7e3e382ae6fedcf91f8079b3e5404b01024ba0a0900c5f15d6f010001	\\x44dce2bac8b9c831436082e13c4abc62d3b4d3eb2b735d71a5238730c8546173974712889daa3063397ef2f908f7db074b4e204bd0a67f665470f15527558c0d	1671132975000000	1671737775000000	1734809775000000	1829417775000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
58	\\x91d0a323f7a4e8fe40e8a9c696b2a2e79a7eb949f4f060ef5ae6209227f46afe9d4e24c9bf6f36608832f3126299d69295bb80f9829c59016bcba6b0bf85aba0	1	0	\\x000000010000000000800003a1798b7143ea7b6a1343e9b833a170584cb7969b9dd15776603a6cffe69479b59feee1d8e9f6b48c3f9400b698a89fc31b368051c3c7a40a045f37666ac8f67a669ee68fc384991843d576d24f0076dfc2442853eef31954b7027387c6eb36f3a19905070f65332c243ce1044a26fd1735c7ffea9f0c7c473a8f24b1cbc92f15010001	\\x2bc51ecbaea9c610479aa1f73eeecfc1839263bf767f0bda15a1951b49c4b4c16d47a7af037f3de0d1676a993b862e501afb883324088e94cacc59affd0ba704	1673550975000000	1674155775000000	1737227775000000	1831835775000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
59	\\x9238503ff5f72a870ab0c304b0a18aeb7b42a471ef73edd32df280b87212c40cf24b4cf120094fc4e1ba668cf8ed668a7dab1ff4ca738cf19a69cc54bc66d3e2	1	0	\\x000000010000000000800003d6887d93b9126310766d6e975fde568a657bc8a6fa76aa09faebb629e1f85fc640847a82129400090e0338484ca61a47382fc3f6532793daada319ff0f5f761833be882b7dd35b968eda62b2bcfa8cbfad73c4b81ddb93ca820ce7e3dd1550e7d8f5c3f7c1dda024278c47e1e0aafbf99902c1f336d0b6ba85dcdf907dcb4317010001	\\x5229b4f6f374919ca60a5fc9f70dfbe448f68bc0d01d37ff0e77821bd86ae031f3f962de47fce903e8de4245fe68d3af7ee1330a998a10f307983c68df25f000	1664483475000000	1665088275000000	1728160275000000	1822768275000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
60	\\x9300669d4c25693c78bc83a07f37d905cb0b7831fa86620fa00cd91f4279463cf5fd4396b0d73a737b9d3c7513c4a7031b59d4b8739cd5e9b817a92325a023eb	1	0	\\x000000010000000000800003b0853548178aa9fad297ecca46318e1dcfbfb30cc3932343a5d53c04b9daf672b578a088cc43841b1d49324756c1f2dc643bd90d48b4d425a39e62bfaf7726530d513890a0009573914d7f696bd49af8ef23b1e84aa5440ce2b073c7e1c2808f6620975f228af36dc0efdee196ccd604603fd6749a4cf2f1c786be885c0be887010001	\\xc436e40c7fcc1833f4f3172414eb8a193c18ae6f1aa9c1bbde5b67bf95f209e09d1fc91941d195ab38220e896a06563de0d6153410d54526c57d4f011525ec09	1680804975000000	1681409775000000	1744481775000000	1839089775000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
61	\\x9478b209f5b39c993dfa2cdc7a4a027ddc1e21a01dc3e7192c82785ac59477879fac9fc16b52d3cea5ce6b2d08ecf46de35704daf572be8ce9512ba9d88c2b2c	1	0	\\x000000010000000000800003b78f414858f368f2094c82251b14b2dc76350b78c3bba13de639aaab75c57608dfa2b94d779ad89db3c9c3dab14d8b0e41a3eb49e74124df7a60782158dd332c902671d1abb416a38752b729fc43b3cf744ed3c42b62ca9bfe070fe34340136fc0f24c7d630578bb48a59f91353e05f635d25c174e2fedb7c946544b0c2781c7010001	\\xd400fafe7c94ad7b7dd205136b5ea724ffb3fb4637d8f062772e9a03d5c475159030ff8ab6810c031e9b6a6270d5e80f26b76bf0c2faa384c15ebfa376ab8005	1677177975000000	1677782775000000	1740854775000000	1835462775000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
62	\\x974c753b8b30c854d838dbf27ae226a214bb3672c22c2b1efcb09e887ffd25682a3ddff727935e78e0f001e7c06dbd50ff0357ae0da0f583459c61b3e4dfe44e	1	0	\\x000000010000000000800003ebcc122cc9580e12e579f5ebd835238c8466ac2f48909c5b5e2d1908cb0335b7f25ec8758b948d5a4c564396e384b5521abebecbeae002b81957850ba4d246bba8c4905a715c03f730a76ed91322efe77360eb0925df41c37f18429452a9e03e4fff80e68e530e2e3e04bd467db7c981b67bd1cb15ddde72b058a4a0bd90629f010001	\\xa202aa2b5dffd9b3f885d75c989665d9a0c9d824fcd3f8e0ba71bd65eb1fab4be5d78f09506b69aa2d4b822751c932038549194ff1494d9a873532d9c78ade03	1679595975000000	1680200775000000	1743272775000000	1837880775000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
63	\\x97fc6631d68b07c46b4500b603821ebc855455c74ab2ed99960e9abccfe29137901f4f7198e5838e2c27e9ecca7d90c9b285538a7a13a94cace64668f9ab0abf	1	0	\\x000000010000000000800003de431f90bed2ae40aaff930c8d839981d64dac64ee9e1a10fa570779db592fe4268f0767584236af8d5c034bfce400bfffecfb1000f1dee8b2db54de5a942b73e643f4507fef50487e347a5ff98b2224e5c35763c2d5f6f643340c10586e082d05ac3d645a1acdfe0e51d87b761e3f3efc09ce5c74f90ddc85e20d7f920e2a31010001	\\x3329566fc84a572180532efe1860e4fb2736bef55a3620b20ce621d914496f49da2ea17be249c01bd48bd481413928374d7082c9dfa0c1ed0359c69091dd340f	1682618475000000	1683223275000000	1746295275000000	1840903275000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
64	\\x9ae0ae32420dc1d80dcfc8b6aea8aee846965343d57f10a024ceee441f576b6be02fba4562753d0f6c395bd1cf555b1057df8651ede897fac1335e16557240f1	1	0	\\x000000010000000000800003b6ad314ce49785d788ae5ff02b4eb0cf2731ab29ed4c2bfd25fe39b4ab5c462999a8bc71db4fb7bfe15787677d5cc291c37818c9077be22c5bb07e555f277bdbbe60c9633f4a7b943b9a7b2271474a527c711175025ba14ba23eeb8061edb93e6def6ec0a49c20f4d73b5373f3e84ec2ebd6554da57befde1b4db9770e47f195010001	\\x3c1cb6c541abee4992a423da141b58831548e48bc12aa310434f67834280dfded5f9f93197dd581900c1eae492ce9190dcd848a11808b342054eca98edffae04	1666296975000000	1666901775000000	1729973775000000	1824581775000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
65	\\x9c584eabee521f571951602918e70e4fd5a777e25b7b5da8a43e7dd273a73c3b774650cf98510d4120d31d10b7f686eb3d711db919c8a362318239b82c7bf6ff	1	0	\\x000000010000000000800003ebd5d0280f9715cf4c03337e9e97279c475035a1056fa740b4e7dec298950eb2214aae47c5176cfc1de779a7e15d903360ab39348f5f21bc60317b6dd046e4ed7696306cdd9a80b328f67062bd9b8318063ce5ac7c8c4bd62e271c11f9d0423eaa00e6eb8c65803dfa38dd38822a18e406210566eb941c678d43c7041d5267a1010001	\\xd6c9031134842b5189c84514a4b87bdda8a6482f71d62a13137f09903465af3e796a721ed7de9ae7175f275c78ffcf4013b4e72a98f3131e84f4a6a4a177bd02	1674155475000000	1674760275000000	1737832275000000	1832440275000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
66	\\x9f28e975d560b24099094cf43a7f13e294f4ba0c4b4527150f80631db98182635883d873264eefb658b7d93cea77e2c49a4c2388d46c5f2a03e561c22cf8c0c2	1	0	\\x000000010000000000800003beea57b56b22c0509351c9db5ce0d2833e3e18d67e11ae606c01de954479bbda974b76c777632f5cb05785cb910fc01ef9ec21904e2ee573c76e60109ad708f06f487d10e11b1087a610e6ca5f42ca366ed7e30743750f7f747724c6acf2c390f18f8597864405b83f9f81a49e8dc485503867b190c06469a9750a279aed80c9010001	\\x0d736118870ea2ef6cd0db4e3031023c68157b31563ca0ee0bf570c80ab7c62ebe157b6dd8e13f4ccd3aa29c8027f3a09142e909178db80ef996f1e7e58cc601	1688058975000000	1688663775000000	1751735775000000	1846343775000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
67	\\xa268aa5644b341ebea4f5491b091f49f266046bb2e9a601943c249932c8f6997e85976985e30694148152ee2ddcf4e0bffd2a7ab991b4f5803be97e22ba36d25	1	0	\\x000000010000000000800003c7f6f064f8e8a308e848e043065582afff63edcbaf8339f3693394dc919f70e1b2171fe3aedbc9d9a03d9a46d834ade99a3a71bc65b97178835b4e0ce31f333567157a14633a13f22617797283decd76c3d60488f9dcdefd29cf30f5ac1f016bbb8808db282228b743d681b721196d20cee8339049b9fb8c14dd7e333fb421d1010001	\\xdc86f63d27ecc299cedabd34cfdbdb3e65ca23d5cf6419d4cb4ed3fd6de0f41e6be3c332572ca6e9a6989ee49d5df1ba49f6caaa55aaa4e50d8d7243c9aa4705	1676573475000000	1677178275000000	1740250275000000	1834858275000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
68	\\xa2f8445eeab9a8d13b179e6ee73ad4d5109372b6ab5e3bda1a839e82c9e5fba5a464800c069b507682fbbb669abe903ac1878ad6fe6f6a7fd7fa58f83347226c	1	0	\\x000000010000000000800003c0f18216e902ea31c09f579f36b5d4ee36ca579b9c3a789cfd2d88bac41c0c0ac967c359863e8c2c0103af701e599b5bf7c1d3e88a40fe6137993ee13751debae555570d38551f8b46d06a079514bb47444dd7be67ca1e3e70537ab5fa5a93cfe0c794043a3306ffd55b664050016f94ed3efbf0d51696626d2fb0a3d5fd3bb5010001	\\x81a648512a58ed0c9971611947f9952af251e31a7cd337eea1b69f2d622717c6f78e097be6de94f62b931fa72e1838278a691968eea6c256876c985bdddf470a	1666901475000000	1667506275000000	1730578275000000	1825186275000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
69	\\xa5944a8c5821a7a4a6b969fa21b9319b43c3bedea4abd4fe7560e7020eea7c55880a7c1a6c20c4deceef6ef40721027daf598ca595aa7cf58ccf6ca93e4becc0	1	0	\\x000000010000000000800003d76cbeb027debbbb35732a17dcfa3bd55f5dfb9a3a5f9f90e34c68960268200d47f0f30a64ecf893a66402fb9136d7b6cdd2ced6ce456d2168236773b8297e850109c84c9cb215f1a1ec0b235683769091a4be70f681dea3974d626065b406ab48c0ca6925f30c780b818e471d7f9520e3b37454f9d209693c562164383b0a79010001	\\xb39191e907b65ff00eabc15bcef3857b50ffe00eddfcf6ad7324ec421840fb8dc8b94737a67b0e6b727e14d5e7dc6b2aa3807fa5b2c8330a4c137ca078867a04	1664483475000000	1665088275000000	1728160275000000	1822768275000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
70	\\xa8904ddcd6dfa34384b5b5e1f990a1e8f8677e79522f6efa1075c04ee55f59bc0857733fb3f56a5dd89175b94e442b7527432e05c2dad09fc31f7fdd5cf08828	1	0	\\x000000010000000000800003924cba96198590befb1ec386986d18d4922acc8d22493da08ce5b430490737b56589d4548eb83c80919b0a77fb85dcfc96e42ca0981a755858d2ea6a921666587424b0a85be2759d7661cd69cb1469c7fc85d8a34264f670f301d82bc09bab0fcce61bfc81d2e0b2ffce5f7aef7e9460ef44611fbd3b9a496877aa4bb1430303010001	\\xc44e0842556b0e509afce0da136c2945590ff1730adb597a1e12f2ac4284cbbf7ef320363ed6569216764c552f3b6e16f83595c87586857a3f3c4d31ce069002	1660856475000000	1661461275000000	1724533275000000	1819141275000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
71	\\xaa7c53a8f57fbcda6ce27a52a030b3e82960bfede632bbdb41889ecb823d0b2d1e47b56f6ac5cecd78c427d138cd1f86a56d3c7ca4b46379df2fe190c95dea7e	1	0	\\x000000010000000000800003c76d393d431f5d53b100d14933100a1f2073581077095d6cfe7a669a9c58e8bcbbf9724c776ea34f9f9bdaa07c73716a0d825b8430cca8cc149f55669fd4a97f3547fb68e12056c2a2fda4440b7f31f0c7f3a0633ae8321270ad83bfab471c0c7945eaffa5ba519791bc4c7db9b7acc0eaf64a809d67e9b6e209073786299f79010001	\\x29ec1c78015c905d760c8a761b5115d1cbb3b9e3c5c0af6e18c9eca9df77bbf1da3a379510eee0e9c819314e4c5a7c3bd3b03d56a350d454d324b018c0002b0d	1686849975000000	1687454775000000	1750526775000000	1845134775000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
72	\\xb4002da99f411e4512007caf9ded359843e16c9d525bb3dd97ac215378191cb86ee2bb66c1afe1249777f37b938ff03fd9680031e5cdb308c1cb6627e6ce7173	1	0	\\x000000010000000000800003a1656fd6b846664f26654d4e0e99c7cf4c0f0f282415fb617bd818507909a558f42ac068604478ec540f6dfe9f4d85e800f7f537442cebeb28ff22b0716e068e36638070a1591ed77100a81172ae73dd96a2e632149ca612d15f91c51a15fdbdb9bae6154d53e1fc77345e1328b246102cc24048c63bde7247977d41a75af92f010001	\\xdf8f9c937468e6abffb04d92479e9b1cd34c24c7c47dad3c14210a6cc0b43493cf341b499ac34ebed96b461d81e123aa311a2eac769545a0140a97ad73ba6904	1689267975000000	1689872775000000	1752944775000000	1847552775000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
73	\\xb6f090812745ae4641529dfc2bc7dfcbe451fb1886f35f49f521043d844ae8af62f0ca3af8bfaa358fc864f1869b4a45334d2c14abf577681ab2fe6bad9624a6	1	0	\\x00000001000000000080000398311a468d45c01e07a8017f806c1261a29b7f2352ab2e520e42e2355ebd23aee48fadc189a3728ee418f3f1f3a91e87c60fda1f36e16545342a88e098bc09512aa8b88f23b7dbe5c05d52093cc1c315ae19733e3189842121650b7b82560fb6e9781c5931dd38edfef2845b770de8a6ac2f4a2cc080b5025b70072b5877640b010001	\\x160f42bc87684bbdf95b7f9ac61be08ffbf5624244c0cf1314ed694e528002d5ecb3782b5fa65faf2e538b5bb9c5df9aa5ac79e211f0fcdf15ee97cd9197930d	1669319475000000	1669924275000000	1732996275000000	1827604275000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
74	\\xb8cc1ab48750a9d991acc6cb0ebe2b7a216d01acaf29d74e7aee4a2a2f89524e38027c17a556ff041585b690583da0020b0193980bbcb623ad0ba385a4e4755e	1	0	\\x000000010000000000800003fe92e85864494ab045ea64cc4b6b33705e7e4c122b18c92cf0ed1845624b96981769b178c4f31182abc28f668ac8d8a3f1658f03928aabf85449209ec11d49909246f190e296b5a5be6dbb183905470707524af1c4bc62df25893cf187eadc3ff0798eee4b8899a066268fbb5cd2c16470dab9445a6dbcb38ff02128feb31f5f010001	\\x22ac68af317093073f7b01a056bc2785564aab7cba04dcaf7aeb13b2cb58b484316a5e0b863a327c667aff2733476af65509fdade54c61cab3ec51fc7db9dc06	1660856475000000	1661461275000000	1724533275000000	1819141275000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
75	\\xbe0054a5992d161bf29047882486af0be3b0529c66343dffc6c285937afdfd51d85b234d1548e43e1155ed0f492cd0ea7394a8337ffb3d18b47648e49b7cf76a	1	0	\\x000000010000000000800003e558e96fdc52ac56023e9dc3a7e0cf6cb2f864461142aee6415086f9a5c3902b660dacbfa8edfa7bbd850d07954f1e1a31ff8bf12506ad79552e58df694913fbddd17ed6cff62c795d2e785104fac6905e1583c390fe819ad36ec1e130d87139ff4fd2bd2c4c0a98c0e20279e20bb563f98376a15781c712c8c0dd9dfe7a077d010001	\\xb54957619583b30b6e3cc37c846c572709693c7a289da22788c70d504be1d51fe8b7f678f90cfc4dede649778789cf78af602366752bcaba52387c594ab94c05	1683222975000000	1683827775000000	1746899775000000	1841507775000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
76	\\xbf70f55fb6cc40ebae142a001277930fab9f570daa913227cb02eae783470f1339579c479a1e1dc22596b077018dc72dd5f9dd7265f2e371e419d02913ab00e6	1	0	\\x000000010000000000800003a9795b09a19140a01fc043c89be7821ffeb2c132728b1ad5652a028eba5bba028c95fe3c85bcc76c62cea7f11e7e0342d4f1063425188d1bb1e530413a24c59e64cfa14828ada0facf7d59210b28c674842228afe144ff146b7e8a0f0c2e6a9238fb71a5de312dd26b5d7b904ef22ffc987d833152980b5e5d8b16e32573d5f3010001	\\x38d92cc52b718a1338b03023d8360e0355e76000c3560ccc22d82646f20640fb5f90b13027a85e66fb08b6a051b99bcc6821f47eef5c98de181333f89c12c00e	1667505975000000	1668110775000000	1731182775000000	1825790775000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
77	\\xc428251bd8be134f714087a93406ab3372c9b21b8c7940f14244e32a515941052175273643ad8b0d30b7cf649d0c8396cc3f767782cff16d4d7a8033681593a6	1	0	\\x000000010000000000800003dd649ca8e4a4c16fd1a6edb3e3bb0b313938b2ffbf6607d285ef2492346c6a5f846b850c698505a49fb062625cc52390b0072c77f143354a3d7a4dfd8ad3c8d400b8c025e144cb1692826bc3f7922add2daf08516977bb7741d72663b1890eda26b2ae1b945f6e6c5e77d82f9c2afab133abf935f148044fda976378fe9d0a55010001	\\xfd2cd5ebc03c48f0eb740a7117016484c073bfb5e4305a7aafaac552bbba5bf1feaaac63f85377a19ba1798f648ade68e18d89efc73644e35df5b548e323230f	1669319475000000	1669924275000000	1732996275000000	1827604275000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
78	\\xd104c19beeca0a777d5815d0272ccb7a640d1aefff782de75fbb0153e37a42af089fc4304f504e92bbc47df2e2f08ffa4eade7d9edc19a999fd8dc6b576ca52e	1	0	\\x000000010000000000800003ca1e3b2749b1d8cebf0a03e3a01400e012d78a5b9f38acbcbe451976391526effe4ed1071aaf50dfbcf52d1a40ba66c0c83193156fe0da39e074e9852f6abab8722adbdbabd8052a27d703c9e6398b7f5617dbf698d8d266b808c5a76850cada1a65999ea7013aac0b728c799f9db9cbf7358fc3dc5a5e8b0fbffe9b59c99817010001	\\xbadc93c9afc5af6095a0858ac7449f3b5b76fe205eae99ec6fd431ae800e2d19960af5f4fe7af34743fb2db89aeb03dfc78b70795ab826282d5aea8242d2530b	1682618475000000	1683223275000000	1746295275000000	1840903275000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
79	\\xd1dc3814bc9281f93a361ed49c5a15779d3d62a4a60de7e13d733d9ca7725fb3f73286202799c780fb43d0ebda785eab299b98a116dc19b2aa4e1f4f4ada8acb	1	0	\\x000000010000000000800003b595f22b9b71d0bf0a9b1296bcada81ac2bdc77e99c8bb9fbe211aa5946dc68f57e03a404b6d914f702dbdf7bb5177e62f0b82cce84c508622c60b64f1e4f7068185135eada8f51a4fba142acfe162d01881154e43af5560746e85ae84419228f4c4ae739bbf6c2e2bfdbbc6acf69a3b1202a717f75853dc62fa3b0f20043e43010001	\\xdc4bbfa8cc73665f7333bf47a99e51cb1f8af3661b99f3687f49afde4bb2659d70b66f16e2403c49384363cfb24adec5f9ed9ceca1957997a34649ca9eadcb0a	1671737475000000	1672342275000000	1735414275000000	1830022275000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
80	\\xd258272bb2134798f62f54c67a91d03e7a603a2345ae1431f0e2bdccef72d366bf5c7a266c70094d36c8c6206e3992008ec2c07fb4542a5fb90524fa7675ea7f	1	0	\\x00000001000000000080000395dc8f8c2716f84437e758112c489d6ad68004847697a70a9e5c6fc12921b202833f634bc7b25180ac79fd28448f319629d501384df4de172ee382cdb410a8d1dfecba0c5e81440f957d181430cfb294ab9d320b8a352080c456abf872a29bbaa2a2c4d4b1c03e6816ae1c58b8c34b70d79a2d0f233cd7881d3bafe36b6678e1010001	\\xc364b07d895228cab65a586ff27a797df9c7edafe4b0cc42f41c7c378ee006a5ae3b3a2a575d9575d66ffdb3e992ed43b45964ea2f27feb3380b38615a9f1a0f	1677782475000000	1678387275000000	1741459275000000	1836067275000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
81	\\xd27816acb0a161b913996172d0a47603356a9fba40f9f0f2640fd4e44ddb309c90e23968d2bd4b500d65a2900c3b55388b91964e2da4d012c7dec4925da4761e	1	0	\\x000000010000000000800003d14f572345494fa7ec69933de63f0791c646f649cf1dd5e48642f69c4b492feed350ea7c603b10bc26a4685dca0212000bc7281c30cedf69364a296f278e701074ff0ae3c57e64472196e2f797475973a8d87f179646117c78cb51a48e5349d0a01a45910d759e7c3bd316f6f9cf8de0a2014eab770a8282e37d39acbdeb43c1010001	\\xd031389c037b2eb936a8ca2a1321dcf36d901dd75457bdd2df5684ee217b897f3525352286db15f52fd79224e7a01e8aceaa5910e5ed57ff89d3c894f617b101	1662669975000000	1663274775000000	1726346775000000	1820954775000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
82	\\xd370d35b3bcec83607bd4f310eabd34f576bb596d564961bd7407228b205940429fd85235187801a5b64bcea447f2770904bdd1ccd09c518580501a47db3db56	1	0	\\x000000010000000000800003ea73e5937b7459e14d8422462695c8cb8f9c71e4282b77319756b562e647d20fb23bde9bdc15b58e5bb38e3266e16de8bbd879bac48b2ee794b0d86f30744cacc1f5a3b2ce25ba97169d7b6b0c7b2bc4ee293bccee8c24c58a44c3bfec233095d13ba1b8f43da6c326ec4ad1a90243321c875a8f0367efad9bed670830e32d2b010001	\\xb88610529fd30a4c60c6f4590258d68c865fb5402ae6f494a32b972d3fdb907f0aeea96b42ea2a10e7a17c0ca87e0ac2fe8e82d6e9a2ef694e9c81090ef5f40f	1669923975000000	1670528775000000	1733600775000000	1828208775000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
83	\\xd4902b02450d6eccfac452ed0078fb346f7de40a46bf3b09fdf171227e43409a0891a5c866379a56b0dd37fca65cb5def4de849a5819359187095b62623ce62a	1	0	\\x000000010000000000800003db723f237e7de983b888df66c5dec29dde3c63917e8cb4a174780cbf26f5de2f69efe55662c63e18551e68995bc6b23ed08e3c3f1b65b26a49dfea68ef3eded9864261c6a09a2eea12fd6ac0c3ba51529208a1212de4b6576abef93d6009c6ba42a6697e92ea609b7b71c9beb5afc664042258bde1902c60408e888f71e8afe3010001	\\xc6d2784fdd0d71c52721ebe09a7af487febd16b549a8edd5ec750ffaf8fa7a5ef5c05bae22a58718765237f51c4189d45ff33f3c1e62f08c8214d606ebc77c0b	1671737475000000	1672342275000000	1735414275000000	1830022275000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
84	\\xd8fc325310e82d52e170c063f25311679e64ee685037b94a1ffac275de97baab152a017f516be01426cca242b11080394c0bfa735de0960e9ddf99c05e1df01f	1	0	\\x000000010000000000800003c475c35467df55eae3fdc0411175fa7c8698c232081edc4579eac94caedd943ad78ad8cb256f977d49f36b5ed924d9713f92ed4ec2ebef86a64f5cde45b7fcb7191662c2c1cbc020459e8074b5874ed5e63cdb022ed95f9027a6fcb5369159ffcac85e57e6da994f7f94e9d1e8394116542e79f12c1e02bec77e3bb0287c4983010001	\\x7ade8d1fcb1bac0be0a5951a93dccbf4f867bd8dfd08665a125a535b7e3f5c3e063bed1bc099197ea9d4fb384ba55f9c5c00be57aba5b22bfd58356a0919b20a	1679595975000000	1680200775000000	1743272775000000	1837880775000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
85	\\xd818fcd7aa92a639295b1278249ac4748e51fcb0f6989bbf08f67ae5dde8d6d789b17fd8775672d356fb804513adfc8a41432fa011e2525718b4642e82b515fa	1	0	\\x000000010000000000800003e1b22605b65adb73b3ed06719caedea682f4a7060b270752d889e5bef49a81d165d8c594fd8d40db62082dcf38bb329693a2e92a60a3b2cef23218927d77435d745ec0159a92fbdfcfbc747f43f97ab8cdea94f1f9d6a4cf7e4b3774d43fd182ac99fdd0f478d357950994bdbdeff86c0169079644364445c46b3416dcf99ed9010001	\\x34c82333438021be7a3479acced43fa6aff5f85192b0281ae746c422ea194bac40a225ba2e0562095324ed7f12515e5594bce169200c6f2c3e4297bbedccb000	1662669975000000	1663274775000000	1726346775000000	1820954775000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
86	\\xd9844aa089968c4ce4238377df4453a2f69e54ac82d23abbc30d7ffdcfb691ceb47c9d380ff6de69ca623cd52263e100fc3d22b446f6ec9bc95959b5f42f4772	1	0	\\x000000010000000000800003adc5f48e95cccb4303f3a10605b27bec1d092a8ef60ed3cd70514640b505fac553326bd4036c4c1b357a985e78957bcf8d370b030ea6d1dc807fe6025ad3b47320312ffc912b22bad9458096c571dfd1814e22076b87266b89931e17494caa9b48cafc784c1c6b113b1b15784f236bad43f6c84fa48fdc94558c23ceb1f11b83010001	\\xb4fbcd10fdc64e6802463284aaf732e0f4fddb46316677c03af5603030b9f9510f5ad67d2930245a7ea116caac97a2bfd58906c5f6fe7d799e172e9516f24506	1671737475000000	1672342275000000	1735414275000000	1830022275000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
87	\\xd9f86b7c30582e1090fe083a0805331540c0173bf99fa57128139373fdd0e9f137689b2b598a2270820cd6606d72e6b2db14292ca26956100843b7fd0bfa3837	1	0	\\x000000010000000000800003d51c72250c78c462cacee714b7f7c7df8e235cf2682e48bf68bbc2807905664d4a82c08796a6be749d70e3211977a80ee7145fb66fe25c6f1913f0530a1c0bec0fe43814b7dc90cd7236209b102c86feab17519336182aa4921d84cb7b76ad9a6e11033424440142c4083f0380487ec93bcb19b508b250845f955c6600d4186d010001	\\x1af37b21a7cb1f98972d74209aad9d70f1146bb259b55272050f2d4804eabcbb359b13db573b195b206735533ad3c30451545e6fb1acfab43118a6e88691c101	1664483475000000	1665088275000000	1728160275000000	1822768275000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
88	\\xdb74fb91e62bdf1ff67802d439198bb036ebbea88f33f3a794307ee57026262420d204a7c27bc6e8d92461093c7b7485e071213946594da67a3732b59c13b985	1	0	\\x000000010000000000800003d64384604da69a450079ca168508f3421dd298722f68d2843a7d4dfb5758728e2438a31bc4ebb75ac6cce5e09d2abc8639c9f8921ff8efbc7f445643790fbd4351799d685301da7ad15ae42eb63180afcbbead21daf57c0a0892bae08cdb2dd970239a8525bedc88586b467c88b3df358d9ed453d98bcfe29d57e1bdcc8e1991010001	\\x18e371a3b31e1526ba3a3ddb507a77fdcd3107d1a8d66f1e8191c5eef049497e4e2cf3bf9efd0c604116e57db89ce65434393c9367df06d14ea3cea214d89704	1686245475000000	1686850275000000	1749922275000000	1844530275000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
89	\\xdb2ccb1b56911f621d27f0a01a1c8af65297bf42dcab2b22279aa90609a5db6ca969b378032456909231863cce17255a9ab1beb9a6f1791388ba4ca146570045	1	0	\\x000000010000000000800003c5bac520467739ea86d7298cd130be2a7edf41b878bd36c3ecd36b63def64d921047556947fa61eab19b5ae8372b869d899de8a1a0367c297deca6d2a486494875bf2967800611e29512480b8aa7fead2d810db7d0e894ef71a511e9a79fd9e20734c29d2a9101cca6c1c0948f01b6a2380bb7d8641d6a09c3b9380ca5508aef010001	\\xf8044e33385ea2ca6b327565c0f07a03e074e07a393e38276e1baff4a02e2e97bee59b0c742a102b0dadf2b84bb6cc2357c611ca31bd15bbaf53453a4b5ed70c	1668110475000000	1668715275000000	1731787275000000	1826395275000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
90	\\xdcc0ee44b05f56a819ff2647c6e5cffa45eb83139c14c4d5acb3433ea8790141303eee4a5f2ea3b8c3c1f88115fd2d8f9d89e4bfb79e8a697044d3a1281523ad	1	0	\\x000000010000000000800003ac4e4104084e6eb0dd4468255e7cd31cf394bfcd226f8e760baaea40417ea2d1d523ae1137751d83d0638645438ce151fbf9264385996cc7a45866437e4ef67b0727faf7bcfbada51a682e99ff22dcaf62067ace46d02be54d5c0d24eb7bfeaa8352cc32a759d53fdca185beea30c3ce5b179b73d2150acc65de1d181e09bdb7010001	\\xe726e0f3af9a31b5d0664c24ba41191b4c56c72b57899526e667caa18f49e4ff59fd81dad66cd2dcd9da4eaa2254c43f0ed8a2c02786c17abb9ab9c0cb7b6400	1682013975000000	1682618775000000	1745690775000000	1840298775000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
91	\\xde58dd19e0470b60345c71619e92ced3b4decb091052843dbfc223a418ed1c406afdec0284f0436e5650d9fefe185943e83f6287da7274f182c28d27558bb75f	1	0	\\x000000010000000000800003db05c1e8f4c85da3f417e020c2e46d5528875020f270ad21d448c076e15ceb6d4f80d749e97353b4c6123296c5b440e1a0e016ff7072a2fca3c6da40f41ae49199e6e0c95920c97ad43e4bd0cec6ecdf20d142e8df622bbb13f7b193a99aaa45e922f729e19ddad2ace305fba6ed9ce200aa055965885318c300599c1be14681010001	\\xd98cd7b95704fd84d38f554a0c2ac7fe28512a44c2067663bc113e9674351ea99f2206f90d69961b882358db516435378896ad997c8e327d8d5dc08b2c66fc0d	1675968975000000	1676573775000000	1739645775000000	1834253775000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
92	\\xe3d8a0f90f350f58223542a49234fbbc54f6158a8d90723c30ac9b095ea242061230f58c571eb3cb419eb7b6fb34973223697946492fb2acf27d7307200a2300	1	0	\\x000000010000000000800003bc609eabe41125d201ce69c111ef38d617c9b086e3bd8ef3ad177d5c03246e25c05db0635e99b4fd28bec7ee7fae018838079c92244d29f61f9f783a540fc58dfe3f574ddd294963a818cea0314888017e430e84d46d7eb89bd5da11a102e7859e63bdeb81bf25183082af9cb10bf1c491a56184698f2e38e5eb2797e99fa2db010001	\\x5ee16a2710cd6583b3cf8508e8b236f9ac203190f6119e80c3041948440cd6cf5be348dc0d8108f317fb7d9bafc68e96646038a74510cd2cc7d9a5832d31550f	1689872475000000	1690477275000000	1753549275000000	1848157275000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
93	\\xe74cc997b950783814c0b8725d80971962bf48eeb5e692c86f84b595a9f86942dcea5e31aa422ac17ab56592e14e41f0410bad86b717f2eb3e778f4ea39d37c0	1	0	\\x000000010000000000800003a53ed377b11e86a4f71f5d67e16456cebe8e856d510c1739f0e4e347872a0d191ea4d013f4818d7ef0354461b2019d21cfa9d195adce6bbe79c03a988b3075133f137568ce730377b212cb5b42444ed15288b514266f952a83f82f9b5762e6c53dd3d9c71c12ffab8f3903427199105d890092a25bb8ed97a569c69d813fb291010001	\\x3af3c6e53ca575761afea5b2ef6630bcc08c61707fe8ac038231f6aa4bf1e10be8b2b9a79b1417212d65f5e24a16a27586f4ba5de7cbdb19ed2e20e13e4cac0f	1663274475000000	1663879275000000	1726951275000000	1821559275000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
94	\\xe8346d913ad0745ea91b858226adbac121624b16941f60f3e8a8a30c802f4b6e49712dc79a5467a1a21ac2ad904f5a2daaa7c6ead48407b46432aa04787e225c	1	0	\\x000000010000000000800003cb5b6f0eebdb74ceed4cda070b3ffe7b2f455691399ed82b0b385ad80279c8541b223bddd552ebc51e5952085e0c59a0d64663638e47237b9861c6bff13ed38efe370514676f77bf298bb35875607a3f6b6a37ef2c0d1f6c717681932f0915e00350508ccfb040e2e518349e726714cc952c3d68d6bcbf321925a394829130a1010001	\\xecf31982c0537e966d4999846e28fbd10f79575fc67ff9d5dc5118cc45f51b8e1614e533a8d9e714d81c3377715d8b0d61a517c7693dba8b901c61fe04da280e	1668714975000000	1669319775000000	1732391775000000	1826999775000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
95	\\xeb20ce9d975b6d369f3a87c89e42950baf1ec2fdc825e1a0f2b851067c3b8102c3267e67d0ae776fb4b20602c0852dfdf7e418b962ffb48641459c9c18eea5d1	1	0	\\x000000010000000000800003b86a842831857f564de815c4299835a4d3310cfa75d5491d7d27e1e04c10f49cf050251f7325ffe19f9abe539a37a02de1da7f0b2d2f80fe8e5ec65c7485ae1f24f80ae626c9e2ff2fb9c0f7ba37d5e6c390be0eeba1f3b020317aa209f51fa181ee3319905fb5e5c2e1696c22ff531e89770d457f4211dd8e289e8107b6a7d9010001	\\xcdf6ce50d3062a402ee70c60529d9660e201e91cfa3c187d0c1822ed7f01d8be5aea3ee6e9b56a6fbe98ad9d05142cef24713a434bef98bf3aeabf82dd21e70e	1678386975000000	1678991775000000	1742063775000000	1836671775000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
96	\\xecb4c3626dd0da07b9061c03f3111d83858e01d5ce3c0d2b3f138cfad31292d024c10605a4124e91826c676312fb6fbc87416bee7b42aa2d423a5493c151da6a	1	0	\\x000000010000000000800003b850ba9589b16284b7a3b02d463ad4054a21e10b51a7949767851509cd68529294047e4034b05940f836bc0ed3464cc13e1d3fa3a02bf46a8c13427e3de4fff20915f21af4cf6867198281a9f5f375cdce396f3ab613afd5cf4f33a96fc466c202e192a24504ee11ecd297e33396fd01380ffc157d8b5b948657f043b97bcf19010001	\\x5ff49a716abf725b3faa7fa6d0c592c285e84f67fde3fd754456fa9aa1ef4617d6540303cea8508627d27a0d72c8f9d70fe7c03757a3220d9b8b63f00ced8509	1680200475000000	1680805275000000	1743877275000000	1838485275000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
97	\\xeed8fd74533234c388d25558450ef20cff66bb4406248bfd9c640c20eea521837e770b2d9aa10b26200a6903a104ecc5f8b09b6f188a05118215dfb60b912a03	1	0	\\x000000010000000000800003befb3286b4d218bcc3325a7f1bdfb852f1dfbbcfe298f1a1f72338282592d714f98de3be311b9e5999721d24327d9893f1d4419f4b6882da8d5e487f15399eafc0cd745f0d8ccee91f9bddf10eacbf46437ee1788068eb8e432d63f238d480850b6d71bd7f600f1d72d5e26ec6f050e7ac324ee50a6cc1c142164bfb717e6dcb010001	\\x4fa965aed298a21b670a697ae90ee9606e4925abcd68daaba9e3e3f5445f230afd37917c27e418a5409e36d58f83d474991ddf0a15618e950a8482198a78d206	1689872475000000	1690477275000000	1753549275000000	1848157275000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
98	\\xee0c5f6b8367245a8215126c6a062181568b68a833e1dd3abe37f4b05dd858c9a6e8cf4cc811e10752fe05b7873a9ecf82b06eef77cd0bdd82d33d93d46ced6f	1	0	\\x000000010000000000800003bbf1a00ca6c5955ed54225c713ac56cc092c298c3d0c162f9259c2858980dd7ffea99307bf6c9cbf6c28f7472072aee3ca20a1a9ff96c1365edd4f1dcd6a8c363544d8a7553c2a73d833af54623b19d1ac6c4a35020e3b4de9ef09a875f5ae3e1324b17a7f76f67e96b74399c719fa874311911803184b651aaee4c0f6ac175f010001	\\x5504c932097e0576dda585ce8fc42eb01a89e17be6b7eda0e5b71e7db6739a66985941ac0b7408fcc5abb9d76ae2c5b0c9b09f67243c4d712f8696200e77b007	1690476975000000	1691081775000000	1754153775000000	1848761775000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
99	\\xef5455fc5ad7922e96cd4f916e9f3fe5845ba75c13c892c72d32aeac740f03131ad992c49d203a47455be96f4257fb9121d7c6e475e5c92e0f4160f2ca8a174f	1	0	\\x000000010000000000800003d8973c130eea343c43f84dddc6592b38a35bbb7bc84016d4dec0e664bb7e833597dc33f3695025253fca5dc18c81f967a5169a50785d378406c0c10c5afd447335651c00f5d3a9608e99ae4725ddd44062cd4938d6f71238edf03bf976feac6999296d263466ecc931e7cdcbcbb5333f5d34b861fe343db3469f4b17ed500c2b010001	\\x00d480b70c5aef199279293f0a3063d8231b93787474ce42bd20bc61a2802c26bb0e5c64ebe6f1ac54c4476ab3e361a4401f0c2cfc3bb3d630af1c8cfc4f0c05	1666296975000000	1666901775000000	1729973775000000	1824581775000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
100	\\xf2a8aa4633239b4236a7af1b15bc273faf9adf27103a771a107d42e009769a5c4646e55c3768b3451ce1c30b13b63d58728202053c524d92af3ff2682b408f01	1	0	\\x000000010000000000800003cccc9fd359f75e03d6823c91292fe9eee2eee36c7cc7dfc728b576fc210bef9c4f61c36efec4b98bedfbb6b2b59852cceadb0b321a7470abce64b62850ee3fc42b185a67ee356f337146e030cf2ff5a1d7006584185672ea54356a58dd5d494a7667f1cfd242f6e3fb77e81acfe6ac8c95f84fe76f192115634e40f44c48262d010001	\\x516c9bddffea095ab9944eaf51e721c7ba8cf8ed47006ff3f1076aac553417fd91c313990bed5bec46cef62e1f7c63521132e4ecfc6613aff1e6bac6b326ed03	1660856475000000	1661461275000000	1724533275000000	1819141275000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
101	\\xf3e0784038f04948db44bcf43d47151d35d12a6378297399a21a210b10263094de33e9cc9f117591f7a6d58362330d830b0eb1f2459c7a2e5b73c2f3dab875a2	1	0	\\x000000010000000000800003990f0fb4c53e3e08225a812b87a51af2b92f202c2f0d833c3747a66017af386c49c2a53aa5beff1848fafe7ed30f82f3756c9c92807ba9c5422ef78e062bd1bc4cd4461d799912bcbe876d38a43993e74c65833d3b5becc4749b54a4ccf1216cd1bb9abe26b294f90a0d6faa812a444cbacf6725d28bc7180852e4b00af5d72d010001	\\x5f22b3549da15d68964297aed3ba0daefa7184cc385d429eed325d7a70d851aa1a09114f6b18c50e86501711ef49ede19fa24e809df227133a439f463ff6370e	1683827475000000	1684432275000000	1747504275000000	1842112275000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
102	\\xfc38f87aa8a3edfb5e899768f38b086e7bb4675dd6d187cb35948cc8d729694d5e7e406a4a52a379222bdebeccc87b65d221a01e15c2d2d0c9f701df89d65b36	1	0	\\x000000010000000000800003dac3b51b919e24d46ac7c8d341c7a6dc8d950c53d5a305817267cd72c2b240d05a4d8df6ea412d2ff46313ed354850b14a484b3fd226242a0c1e3ba0b4f7d0737444a65b35936b91ada3988c69acac2fa37090d2700434dd99d71652b3e031ff3c6a800d2046a73a1d94f428185e4cba14886b370e93c5a5f0b7ae2c2256a9d5010001	\\x9b0714b5a765781fa68fa9e291fd0723a00309942fa7203e178a7a79163a8e70ce3686b778d8a16f3e5f6b1db6409023d9ac99aa802d094d83995dda4ea3bb0f	1667505975000000	1668110775000000	1731182775000000	1825790775000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
103	\\xfd0465add1d2a609645c6abd4a8ae91954c0072b2005b363028b8bb53f40aa4523deb22c3c2f99fc8a44d8a75df3dabdb4a4fd5c8a72a72cc6f9f5f38942a142	1	0	\\x000000010000000000800003c0bca180b4795786c6a883fc1def6ef2428f904ad6e843a2309dc01ed13a5c23caac7719833dcead669e930708f914e2dd0b5e50b0145340d2957580f47c329c6febf0569f5aae245ad0875c4af02b4c18d43f17f47eb23f3e5772882b87d139153f08014afe3e4f349cd088e8466cbec539f4761cd9fd395935afafd2c58de3010001	\\x72cf997b4ed7634988cc6d977c818221a168fbec998c6293b0b50fca2cbe016ff1c6c1250e8a383d0f2ddba3f49ee4f17389a570e3bf573eff3f3a139634ec06	1679595975000000	1680200775000000	1743272775000000	1837880775000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
104	\\xfdcc175e2c649c4a49f5fbc71b196d79e2bcdb02276a42ce55e5a09fc78c98831ef396c83b86ef55691d74d3d3da874d2feca14bb2e2702f5d62a52f88e55b72	1	0	\\x0000000100000000008000039d8b41265270898a75ca42dbaa36c1bf6615e947755f5eb0207dc169765c862758cf7357082835b455fbc194befad6a830c770007d5cc0b144e309914ce9cd40d2bdefbe4324127899a7be6ae3c8b6c9f0cffbe31f8fd5afb1a388e42cfdfa0da3fa8a3df854c78c01333a9c01c61d3b91c30a54f314f235c60350ecb8a2b689010001	\\x7a98e2219737ae8ec16c68eccbfa142c4bf6e8d55d299a846bf5c066405e083133662944fca4002858247591f328f3b4865baa1c8eba3e607147a78be2315805	1666296975000000	1666901775000000	1729973775000000	1824581775000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
105	\\xfe44b9abc9d5dbefd903f44d2fb356339c3d9d0cf53916802219ab51bf2270e8d45ed827061829dca3aec976dc56984c0d9889110b8193269f8e7d4f5c065667	1	0	\\x000000010000000000800003c2514b3ee079515bbeec8fe7f5e51782cdf3e742a76c6d67f675a18cab32e9b4941ac250705700885da5ee46bb6fa25236ecaae840b6a516dd4efa9c3dcfbac8bf3283762bb1cadb931e52f7b08dad9554fd2d467397b53543df0b22f4f0f8e1dfc1a137caf8333bcfaa58cf6dbe5fee9859bbb63d8c6273dcf429fdb09162b5010001	\\xeddd330c4e2b97ce2450e9e3eca267e3981863592902b3ac2e8a5c3bae5b9e961f86dcd6f12460c346825d0cb290473e58d6879f29c2e9a8330a5bc0ac88bd09	1669319475000000	1669924275000000	1732996275000000	1827604275000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
106	\\xff3039f4805d96d49a6f77d7d5fc9a5e053caf7e164ac761a7fe5217097dc7d0b2e354c5989790c341e64e53a866e4bc04a0b7390272333c5734049bb91c3fe7	1	0	\\x000000010000000000800003d71337899cd3f9f4a20436840b37382b0b360c1bbcd38cbaeb915bc24933528f27781aa2b0b7fa3c0dbef719eb61eeefa267ae23dfd6ed1a2a9d2013ecdf49dffd6adad7915f6332e3241abce1da7c18f533377c09133ad7b6057259b81e4013e70dd8a6af89a5658860fb89f763b8f9ce07aa7be04b9ca297c17acc920d9e95010001	\\x236fe05bb869c7d5ad2e225ca159120357a59369c237e2b6a65a0e06c4a32be2ca8b46ffa02eb24800e380449d18ce7f607360c85b5edbe56a60f445006a6101	1661460975000000	1662065775000000	1725137775000000	1819745775000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
107	\\x01110cac6427398e830ac50957a0bf5167cf01a6f7e51a477728acacdd31e2c79be7552ac4bafb83ddda600b205283f30e413e7ef51d14cc63c27968fa6aef8d	1	0	\\x000000010000000000800003a3eab5c816ef2c34473be929e2594baa5ca1604701083eae012c78a3e27e3a7f69ebf2624ad9ffd094e266ce0598e78e2e61e461ce1130530858523281ef49878a440574bb2fef10dd9102644b8a505c27d2f8f110c9818c146c576c71cac3ddca8c469391fa5c1345d0a4264848c3f6c2b6f941159699fd28fcfe73eb9af909010001	\\xfae0f7162c3dcea065e6858f10b8c9e04cbf0f4058b3b6a06d8cda0fbdb3a2f8a3726257ef0fc6f0305c09f9e53e6367d051f4751342eef3bb3c1b43bf104806	1662065475000000	1662670275000000	1725742275000000	1820350275000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
108	\\x02bde39374f54927e5957ce4f8bbf5c231bdb0bd0bfd4875a61c459f5ab7daa4cd3d25ecb4c8dd305c0dccf5c15f20e6d084844764ddaf238e56b1bbe8e7c33d	1	0	\\x000000010000000000800003c329f9ac53467c9c70993f1be46a70ba3824d3ccdbedd031b6b9d3ab8d353ee19b66007c4b0c994824f29d270ed4eacde7f8b007cd494d3c5b47e3bc1074b52f79308f2e0cf44e5621f85e7c6e96c49633be04ec8334f9ba54d2f1aba5139c3bbbc82ab4868f66108af9e6593740592c533a46ce776eddb7810f776bcd8129fb010001	\\x2395e9af40983cc2b70dbc57c736a55438cff9085ac61f396808a5276d6a6c5fdf6097f6d5b4d3aae68795c8c54a3bad6c6b82acfa800114dd7c6d48d1948a0a	1678991475000000	1679596275000000	1742668275000000	1837276275000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
109	\\x0225d8b8c42b47b474277c9abb66187fad14a7039815a834f86e116f3b99ab869c9a0e5ae07b2974346bd931e46132478a743c5b962973b21efab3e147d7a046	1	0	\\x000000010000000000800003dec95c9b9a08d30a1727f8e36dbf5dd3e7cf4afa019bf18216ecbeca4466beb068097090683ad14c24aaf1bfd64d6ddc5b3de138cd2104d4b4ef1a12ab5fb4edee78320b1c8486e09e56c5e71ad778ec3a32d5d35ffe54b921dfcfac372d6295cb962a00f546b66fa5e837bb29a272420f2ce30a19d33f53ec417240777fad35010001	\\x547a889c0130d563251e01ab894e8a2a303c04952b8ec9ac0f7125771dd5b995ee7f593970aa0006017c259fd6400543d35a5dc71a883585fce8a78db03de209	1662065475000000	1662670275000000	1725742275000000	1820350275000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
110	\\x0379490464a2b867f9fef1b96043221f83d23612c001bdca8762cc28bf95fc056a9ae78ce562b5add73b9cb3cee0b1b4625be5cdc0a3ff20bd633551bd606586	1	0	\\x000000010000000000800003bdbdf3eb30b61822eedb3ee57df344b70f858f54dbb65fb5e76b89eb7129ae6ffc88318c05147b7d1caa2b1497061661f6241d1d515685af6a01f1b1cde5264f450fabdb99872ed61c2039956631fc63c76a0ecac0653fddae784d04eeafa66d6bf57d9f1800f7abd01ea036a077cde8358cba4f94ddcaeb24188da97335bc7f010001	\\x8be8d53cfbaf3b7ae6c6c14ef79efbfbd917552311941633e467bc6dcc9f2889de7a0065572f73c6a442a999b8fb6112c5b412e5196167d853ef7e4782d4d80b	1690476975000000	1691081775000000	1754153775000000	1848761775000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
111	\\x040d6f674b36fb05978be0c5f80a4ebe6fb907cf749f513f825f19028e43c088b8bfe14988c7c10b65fe6907fe2475bb7f58140d1614d849445fea4a447cfade	1	0	\\x000000010000000000800003b397b4f1e0d20327633467ab5f09be0efc5ebed2f3a1465b8526654d068d18f233e5afc60aaf31e7e35abc0f4815495142ac88600920105f5b4b4bb756a2be113f7316f19f4645d88a55f309b8b7f779cc87512b40b43335e1773112a320dc67f8fbbce503036635a540bb16306efd9821282a1bcbacdd88b70d0e170c131bf9010001	\\x379fdb60090a6347e64ca10ff5b2d9af63117a404a1a478fc36f81bd78a163b0740a017bd45c1cfe7d212f3dce2e5fb27a2859095e0677cf9f4bc96917721709	1667505975000000	1668110775000000	1731182775000000	1825790775000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
112	\\x05212f9f995b96c2796da57d61efdd18b6692a309e985494a8092959f18e6a3e60b1bbb64a02674553a0b936757e54bef573696563992ef421df785d65fad52a	1	0	\\x000000010000000000800003aee3351c3a8a6201fb94b3fbb224bf74009a2d803b6ee80e317d84abd8997a8d92047a4e6dd1b334bfb3c4f0106fe795372f98e2ff18445a5309cd6cca9078ea0434593460d0a2f17dcfb95732e5d7830409ab4e44c332512ef74796ce0e9e660c5e19c13b39f5e5938253c66e3b2538ece319e84b7590add13e6d7132dcb37f010001	\\xb8c321815064a6e2f495435aa75ce36f9df73d6e616093d70504c6b0e15aa515b886aad3ee4e05b5b3ed1a6960d4d39aeb21c25cf62d8be66068d650d6ac290b	1668714975000000	1669319775000000	1732391775000000	1826999775000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
113	\\x077501cdbc7ecbb04e3927e4607783c57a8f92aab39c3390e72fa3a21fe430df02ccc5d452eed81a101a6f487f505165aeb51598ce57283ac7af23b6d1e10d0d	1	0	\\x000000010000000000800003d1aaecd5bcc209b8f19790e95d90ac03c0f97eab88da6ac1039bb0205f05e2776fd7cd56c11d9bb351b049c7106b65dbb22ac7ae4c14d8ced86631cb1fcfdffd0c2ba6db388dd96b065670f2f75c742fb8a3d444fc53583dfceb6daaa74a5cfe2d6385f6344d7b3cc336a2bf8db531ce48ffd2df09fa267b69f2e5ada64c426f010001	\\x96a96040a509c0454659d834e49ee4f464061b03c02d2db1230e005119ac850c24825446ebc650466fdeed89e3b6bb79f17afccaa4dd1c16f132f196183a610d	1674759975000000	1675364775000000	1738436775000000	1833044775000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
114	\\x0b953ef90ce5e11454123a0b83b5609a0899992292b3f812e48a872f164375df2b631ca2dd4d9a171d7da94f9782d96cbbe166167ebd07b06cdc4a9943f1d32e	1	0	\\x000000010000000000800003c6c9aa9c3a90745ac0b3602cd91ad58fd2a7c711de8b1b1ecfd0dd0b17d699ed5bfcb785b73024873a5bd7bb1a221cdcac5c6610093f4a7ddae3b8c235c0ab435856422f520d889f60bdf55aed78fedea628a924a5bb07c391fa1b86245ef624b7f34655e295aefc76d6ee1aa5d4bf005137bfe61f24e94fcfb7037c95a10995010001	\\x892d3edd3e0d2d85d634085443ce800752b6904f6e0709d19a2b42b9f30422e4a6c2d80642fadc20d8b5f0dcdcd292ef0c91e96dcd04fcc5a6324cdbae1dbe04	1685640975000000	1686245775000000	1749317775000000	1843925775000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
115	\\x0efd853bb51cb32aafbe19eaca62ce02ba3054f58576ea2449f158f6de50ba9a7e1f7bdcedf1b3c985673552eef2b54fc896878552496ffb7b45cee24ad38435	1	0	\\x000000010000000000800003c3c681d8acb00d057aa7484edcac55a4ea32a6ed2a53fda87500508c889d2fd2ce7ae5d26ae1f977e66255b948c11cf54ceed06b5fc171f6dfb6068700bf77a45d1d95e8aa908aa11ce9e1af9fccc8a32a63fd7a997f7b72d9a4a0de834aa40f739bf3524a02a90b46fed5d2b83fbbea16f61b44c0d5465ebe7781600e8a1e49010001	\\xe6369c4a68956f81981b74c80320f07938251d6ade6f56cbf2a17d6b634aa92cce9080a1f7778b21926510df56deb77859d97f4be9df07ef76464aabba046908	1681409475000000	1682014275000000	1745086275000000	1839694275000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
116	\\x0fb1228ca57827840806327cd01acb144f0b54dad91bcd6cf68aca8be5d8a3070d7172abfea0debebd696d2d0423f2a3c4cf487f9f57ef290ed7158949d05e85	1	0	\\x000000010000000000800003c7dc78fa7fce94fae380d488d232ec8fedbd2b9cbaf03e75ba48eebcb9eed8f4419ccd1f1ddd76d00d66029bbcb13af1711ed529412ecee8871154b2fac486f72d345898fa1e53897b53e3313e3733f3c48f253643c4f8d248209e618587ecdaeefd7417048481a5d9947a8866ed509780f25b3387faa865d02651190a60becb010001	\\x862349cdbb362c536702a00b1ec18be57e96fc0b87f3b192e2d0018ab8db82c62e1cc01c2dee2d409c8393cd678ca8cc04c4b87e133bcae1d5f55627556d1408	1671737475000000	1672342275000000	1735414275000000	1830022275000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
117	\\x12e9666df8fbe36bfe2adc2b1f6188c80a8c8022b70436ec2920e30a171d22684284e7bb89dd46052a56f996889425ba5b37d2b142026fea96776caee753ed04	1	0	\\x000000010000000000800003d142eae6cc9ed3e897f13e752a2cd490203f9993d02a74ffaaa530c155028daa0ba0d02c7d8a60fdfb2d7fcfaee7c515a11a2b9c4427cc5d72c675ed1914eb432972f250f9d45b083c5c35719171e9b311012f74b3b44c961294f78ec6a8ba0d421df49eb207fbc3a1a92fea771fdb4d45bf5a76298c05b88cbf6ef8a0f80031010001	\\x9976928c8d0567b0d7022fc54aef5072b3396036f94a9c6972614400db0b676f3c323317bb1eef735904aa4867c914d60a9b38432f37bfafefffa2aee4641102	1691685975000000	1692290775000000	1755362775000000	1849970775000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
118	\\x16fd685190ffd2587a21189a75d822abf08cd11fa46ef205a517ed17a626df9c7ab906dadf85d1f80de2a02f59a098956d8ae96938267ae7342864d2827a0375	1	0	\\x000000010000000000800003a271c666e2f9c45f14beaee9850935f9f43f6a9c096cc5191f9eae968177a6474c8fa57db135cf12cb217e5bd04cd29d429f33f627f51b920cde43bef01f1020623d5773bf3a6ca44ca6195696e1633bfb56eac120467bae53a49feaa24ab9161d64fe68748b7623270538e6f332a9d2c3a725e51fadb23b159fb315ba15c653010001	\\x013d300c78be74c0717f5dea00b376de59b29de8bbe2c35e808633c4686ad86832b2649208a6805d6d3b3a9b8eed091b5a49bfa6669d810f659f44e191d5f005	1662669975000000	1663274775000000	1726346775000000	1820954775000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
119	\\x16651bc226bc4865cc66d0d907514cca1be11f7d27337a6ec8ebe5aeca11cd81087052c0636fa615a8ef0686ae9606a2dc5abab005426e7d4550313bf6391e08	1	0	\\x000000010000000000800003b25bb82a92b10f4feccaba089927120a87f9e64a9a712a264c84e16b527e1f601d56b6ce9c13bf814993785ce5b8b9a48840bde968d0cfc9b54bb030c49daab6f9c6bbfe09a6cf237e855d94db7913050400c42b3b97f854dda53a67dbba3b12d51d2e1f2178993c83336ca0f8997b2509bd209050473e45c178c760b995f18f010001	\\x2b3614f30796cd9b52c648878630ebe8d87d50aaa814f4e0e2d9e6c35c7f5a549609b8ffad363a5859731a823fe7aa167292c299359b2fd987df8cedd4588a0d	1686849975000000	1687454775000000	1750526775000000	1845134775000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
120	\\x1a71e967119d968938fff2b4ab47a1d72f58fe7941562556b27e42ae5c6f370f51e4c9702f26f2e7622892ce7caa97aaf56fb72587e3cfa0080776045715fcdd	1	0	\\x000000010000000000800003b2a68963d4e5a709cef2c497bd483b2e32532c867284036cda3a2976623361d500b1a9aa8f744df962fd97bf8964bd5023f45e6052e419be62f355a16e42c28f990de4314f85ab66f10337e8cf271147d07853d5f98fe0f0b28ac9f4ccbd85372abdcfab8970a0772dc292c908cc2bbd4e29adb38eaced4462dd42c5017eee17010001	\\x2967bdf7c409d24a69832f1a53d8823b20fc3e8bdf60403031321c87bee957779dad8ecd8c49ee890e4f775ab274790f232a75e1898caa817a4b457c7b371e0d	1664483475000000	1665088275000000	1728160275000000	1822768275000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
121	\\x26d9fd059951002d2f2bfbc8fdc821d968eb567ae2d67603362bc73dc3ce94746afe9c29e457fd0d3b37ea5b8436457827ca15e53446d058c69be3dd5f96e1f3	1	0	\\x000000010000000000800003c37c3ff0b1ec97fc54032c9ff4021a825ccf3da8df6e1f208b3557d928882898e229e64d33c54752eae6f6aee69578debd2489760c7365ba7c8f4b45028cb922926b4d14508720901d47951f1cd07c773473d92d3e776fbdf71e0b3779cde195a9d13cacd3b7586b1d35611e79c07d6823cc0aca85e489457af9fef9802bb5fd010001	\\xa229d4ee834b419877be707d67960e996b53334dfe0d249cbb4d278558247e2a503720a27a4dbb1aa87ee2fc9a6e39a55a86be766db47b162f9337c24e1aaa00	1660856475000000	1661461275000000	1724533275000000	1819141275000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
122	\\x268972d70950526599a8639b8f024cac833022d817dc4297ea7775cb522ce1288227998e45953dee48b2e1eadc33ab1bf731ee503ca494eb39fe3d63bccaad9d	1	0	\\x0000000100000000008000039dc61ec7777696534c0d63676700fb519cc88bf8a86aabef60cf551bcdcdda2845572e9ecd0a2fea61da9e05798ead3524d5bec0aeb3ee68a3d17e2c5536b49ad749c455fa04eabbadd6f8e6f0195ef2c39c6927a87dea684e61b2821768f54cf116f7c2120dcd0240d601587d03c784d67b8b67716c5ef98bedd20547a91887010001	\\xd573ec7f4cc2d60aae8df4dde0706c2551549946f72b97ddc62ed8a76268262c03632b9570f3b950e04a26b1a5e1e4c15b2ad9435a316a5727fcbd6819d5380f	1668714975000000	1669319775000000	1732391775000000	1826999775000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
123	\\x277d42811f50b70da9c10fdc188348deca8fa80e16bfe2a242bda5b403c1f997bb0a578a2359bd8ba0b1b73424d0768810997be0ed69c49a520139c11b1999e6	1	0	\\x000000010000000000800003b23b0cccd458d2a913568f757d9f127223c57f1339645543de7118e63db827bb09b88fe6c6c5ad66eb389f95b0580994d793ff15a0744a4a35d04cafcdd065b37e088c67eefb94b4a8aa0f948acf309ffcd1f6a2be8fb833204548968ec7a1eb8210aabd69dee839ae6688f16c7ea486ad6e1805c795d5f5a7879ebc0ba35437010001	\\xead4f1bf13c54fcdf23e50e020a05a6d1e81cf09d3a0e6360c7073c2be56177292142e6210cc3661c8313db023030ae394df601d35f32b3828d438f0f968f40b	1685640975000000	1686245775000000	1749317775000000	1843925775000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
124	\\x2a990169d75b234da75109c5a3fc0435e989375b0381d7e87f2bb0470ca3e1958f97214db2b67bf889a56727e8854fd74c6528f0090b94a3586fe95cff468734	1	0	\\x000000010000000000800003c8b30755d5b8ca75b80b660a619ba5846c91da49809c3d5ab199acfcef6ecb109667c39435834a0eb3da68a3b5e005b85f99488eb748178e714bc6c93adfb086b7c11e9e891e8fe608b16c3ac045d3db1106247db6fe835f92a3b927b0c403e069b084d4ea0a00e26cc7b5e92913cd72a7bfa80a34b532f5a8170ffc404e5a69010001	\\xae9058ad871e3c4473d898525b5035057a8fc0df4794750fb233ced777098db853d35a96e01b9dc2bfa65b62b92997246d32c9166c842b7dc537cca97627d202	1673550975000000	1674155775000000	1737227775000000	1831835775000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
125	\\x2bed4b44c726432780b4012eb758c8a89ee3a145a162054b56e9fd668724cda8b10ea4732851d5831ca2b30d5eadecdd6f1589a3a41829823a8dc2fd76983971	1	0	\\x000000010000000000800003c8e58b7a37996148b1eec631d62e17c3a6685038ce7e83ea75e1b3503a72bc4077f39da7d5084bfe94134a31f781afd029ab6cfc4195d53a92da848e6c710ac6da46f43aa872339ea7c7f2de69dfac6fc1d94976502d7b7d59dbb89e8b856789db118b8f81ac8a3dff1dda59203ea96aab9975b03798ef6bf363487c5e74318b010001	\\xa40ca3e487722a2d9707eeaf0f28ec99afa089ece3bb5ac4d54de8bc40930a0535d667e317c9041c26f2957b7e6be169344d36d0a4572e543195db41b4622707	1662669975000000	1663274775000000	1726346775000000	1820954775000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
126	\\x2f812fbcd243d48505835f23645c60360877e3a41883ba7792bf292eae0f401a8df8b4578cbc6fbb611f5fa44545e33eed0174facf347b4783b72228f85a1c66	1	0	\\x000000010000000000800003e4888826413987413b0725fbc19fc0d76cc9324e46053ec557742a921a34d1bd97c1d6b596bb8aa38b9d98557573af8d504644661c4853c4dfa73e6f6490726a19332fb37d0ae2899a989c0f124a1d479d6899691bb7e5fd1160d2c63c9e3df512dd4d543ad4541aeab67c2cc7176058304fa86db7e8fcb09786bc80ea141fa3010001	\\xa5f8740381c57f66f6de5f7a6e9723eefdfec9f3833ce8a939745bad1483b72fa2ccc27117d0f90413f4876aeb027773645f3e13cca40e445d766782f6b86f01	1686245475000000	1686850275000000	1749922275000000	1844530275000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
127	\\x33c92ab32b9bed4612b26653deca4b3712b40564664892df113a24eb0741a041a508fc14678415b6f5cde207a0e975d9e4810103f925324a1d3898829aed39f5	1	0	\\x000000010000000000800003c701aed38bff0294e074d065005f19c3bbdac62b4e02cc20bcf1e52a5a8fbad68f0c2b4f1bdbfef6fa4a04b857545612775b065a18d0525539abf63cb80661d670ed67556e1836ce7d8931f66a99938cf8658a9529b8422ab072cf72389536e030d0f26d8b6855719c7369a791f00dab1a30e93e0f4569e40a9a6be278170a79010001	\\x537c671327e8c33045281047345d874247247714822ffaf03a0899e333a156ce4bec9aafa6b0b1d0be90d37a42d23281e40491b503735f172943cbfb7328a60d	1660856475000000	1661461275000000	1724533275000000	1819141275000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
128	\\x349dd87c42786a1f11c5c1ef3d002053c26894f50a0563516854ddac638f2df1d91201747aa5a71affa1cbae667e6778288e397aa2e040add057f449e78fd7ed	1	0	\\x000000010000000000800003a4520011b962e1d9a4c9b55c2486574a6eeb90287292853326e77adf2bc42c65f63f27bf6866479801b1341ca047db3e42476bbdc2be2d2c8c09e6615b6cf6d8216afcd4b6272505ee4f9be8659c4e10ccc0ee81b53ce7a56edbe5987adcea2ff7aedb44cbcb3c473453e18e01a78476aac4c4f412ffaaed3a06826897a34b55010001	\\xd2af7d483cffc98508c2376408bcd2f425d7799d077265287cf392e9bc8275de5e7edfe0163fe79b9b4abf1ae13a09a8c7c04c6b72f4707ce8c937b613e38d07	1680804975000000	1681409775000000	1744481775000000	1839089775000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
129	\\x35f5d204759a0eac50ad5cf635b4338c526049ea23f27ac3aa6096ad7cd201cfaa66d6564a1ba440397b6f9623ad1b167038b24ea6dd70aac4c2c2e44ae8ea9c	1	0	\\x000000010000000000800003d50ab560aafd9bb2d66c7a655ee2a7a5ffa608df4e8a1b64a82f69d3ef70072fe262d02da8a15dbb454167a478476f36e075bad16a08eca73e0cdeb00f10a41735064190092bae48281316d622c255cf50de9ad3cdecba176dfe26d7960e2feeb7f6d0fab63d423d7b92235d8c992ebf65d6b27c222123dd787a1149a76bed7f010001	\\x952e95242c6990df7df61c2d657877ab726f3ab734fc2997ed69046e3d811a9600b32366ab1e343d6a2d81c2f81fad0307968c787f74f18e0203def3b740dd07	1663878975000000	1664483775000000	1727555775000000	1822163775000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
130	\\x38b1041f15cdee8fa37f9e97deac5357e73f2ba3c3c3e68a89a82b2330403796e6bbbaf74e288ed6b6a8cf773f376d51fdbbf287b0a3a446acd68bede5047168	1	0	\\x000000010000000000800003ccd7774071c9a35264e9af6d14c8591e33b4aadcb57376467e75ffcc2db1e75ed59b2b4b18381fda5a3eca5989c9704c9d99950200896eddee6aeb6228426f8c142870216ecbd2c10d0c0416180e2dd71b6ed6e2dc41b0eb997508493540f0a3c132f80530b1b6bbd24ea4ec0abc392b7fe45da67cc07382be876e1a761a7b99010001	\\x2c1a8e074acb7dcd5cc0f96136efc3819dda1fc098b875815acac07bf31619bdeed5b1cb9d4ba2ebcf9f5ced937db54ac6a232a4366142eacb1336a36bc1e10e	1670528475000000	1671133275000000	1734205275000000	1828813275000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
131	\\x3ec530feba09edc33f356404f43dd39d929ef161c7d044f50d7b731a4cf106324fba1f816119e390ffbd9de4971430e01f0d0ae0bb28894422d9aa60098d56dc	1	0	\\x000000010000000000800003bbc397b29931c7f5053124a8b0ff02db485aa22255beb8be91ee59f068a8e7577fb135cc10fe896162a03b169c71929b320ef5db08acddb5a7e87776282098ee5a46a1ee5c60faa3af99ce0b477bb369742d897c6cdfc00ab3cb7c8bc8f48076d95d086f97eeaeeb2e8149cafec7693fb7a1126f282eff9aaf35cfa6b5ee2b09010001	\\xb384990b5c00b4b8534ae11298093d99ba2c1349188129a750fb680bbeca8093241a1faff66e626e969138f14fd4d68d4e1c93e95193cb3bd04c75094753d905	1665692475000000	1666297275000000	1729369275000000	1823977275000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
132	\\x412dbca79e7d0c579bc8e0560b99bf117a7d8d108b4774484202d9120af886ceccf176b3a25a0c8e58808c6746c95f6d4f99d00036f48a8652c84bd8435b8141	1	0	\\x00000001000000000080000399517e981d26a8479f2265ed21402d832b823f500b5876a3b30879c56e37b6642c5b7c20a9dbbcae3e94134933f430655d573c5818c8f2018e738cb1bb0e9691ead26b4c84fbb4b64eaf56a565fb5319bbe5e6b8a996d8f911b9987bfb5e641d495e38987ba39054d34406cc74f56792bd850e9fb1f818e1261ad3a63050eb45010001	\\xc21627e91290fae282ecde67991c64869ace278bd70aad28282158758a3a5a46c8e8f0e65aa53f9ab1cda53d9c781fac2b64883879cba340481e8525f4299902	1663274475000000	1663879275000000	1726951275000000	1821559275000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
133	\\x418d47816152233252da50b486e17b42798238e9ba27f6f394271eb4fda8c3d2c02b0fcb5aefda1b4c9f83e529529ee6346603b353c0e54bba9c3a1824753c88	1	0	\\x000000010000000000800003b419563df7cb0620a8a65f7277d38a0f0971781e3048bf302ed60b79b4d083072f784e819ae8c1adf0bb2e32f60914aad3ca8134295cdc3c7744aee5dea92b928687afe88692ef23e0b87e2d006261f73860701655077859d62ad41a6763cf6653740ca5ae2ed44bdb6ac66b16ac7594a51cb9dd9a46ddae046252bf8c6e6bff010001	\\xa00f599b31f36e44ef15cc3f55b6ad7e0cb5a6a18e1e5a0ac49d165a8021fe8222a6aaaf2a4d5227b2140bc1e7fca84ca88d552f29b00fb204944a030d6b0900	1685036475000000	1685641275000000	1748713275000000	1843321275000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
134	\\x458911c10be4d2700bd90e071f71531ab6ba37173205d1803989a9a3e84fe0a5267108641842d6c61ee3026802ec5f090e26bf3a073f3d7fe9dbd646ea99206e	1	0	\\x000000010000000000800003d79e3aee2610cc1ec888cc44c0a8fe99189ae0a4b178e027242f83b6ef27c708f9ebcb1b738153c648b36d92cfe89c2d9976c28b29ccfb1ee3797beed21a59795ad53c0216a821f2d7377bcb14514e94e1beab3a6c2dfebf05f63d59d529b4e01571a0cb0ddd107790d2aff6fa7944251a732a53fa85d0021fbbe91b985e3447010001	\\xeb45ee26de2bca822bc96c660e60841753b776665c07328f5c4dd302d73bb86c9f1cd7c36c0359c98a9980c0caa54600ee9d6b64f6f4b89dd98144b2dc3a1c0d	1680200475000000	1680805275000000	1743877275000000	1838485275000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
135	\\x4519b85f788991f7245272503fed1367558a10ace4053ac0990b5e6eb8dd23cd1561376a5a113c04cc910605bc4c9a8f2c592cd3a099f94494dcba48858509c8	1	0	\\x000000010000000000800003a297ea31476970db6c780f89ba00713a66a3387da6ae186368d3ebff55aa060b66ed536fbe8c7c1261ddf5044a92393e2bd37c4687bfcf6ba3acc47bdff8e149bb61366eb486f6614bd50a92005fcc0d9d3e98afb754ff6fe8123ec1ac05216a081c36258ead1bbe04df2098004762a0877f97ca522a6f2760dc45e609075e59010001	\\xf7e63d83c3b54d1aa280c9a88e5e1d14cde405c9996167ced78ac6333fb0761cefe59d41e7f0a6af9e163a6516e627cba686b323605bf23cd4a790353a12ab08	1672341975000000	1672946775000000	1736018775000000	1830626775000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
136	\\x4611a6f76d00a0dd13ffa1362694d10e5bbe0d3e9873671229fcdbe78844abb77dd9b0f4ba7afd3d890b3e82fe9d02851688b41949e69e4b36d1c614e3c72a62	1	0	\\x000000010000000000800003b7291af38bd9fc67fa1ad574f666f165869bcddcce332e1b0b36679a612cd367e613639fc50ed9ec9428061d653b1b91d75fb8b7a021f3052f826966020701bdf5e342a5ff96d14f2c48343bec8d7472a5a3fab619806cc6b9f6fc77dee0c09690636a9653af19a1e003d3f9bddaaf9de773377bfe09290cce74e4e0bfc4eca5010001	\\x8d0603c529b8bc787880d82af4fc57e6679b3afcc07e71df07ea7bb84190e959a8aa5a59d0bd92a138b0c78be4a7bfb0c0bd79dac132387b3a156afc3068d007	1686245475000000	1686850275000000	1749922275000000	1844530275000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
137	\\x511dc9090943791bc6820fbd21828b812232100ce08350d6401b3364e2faf9e806d9840a72b06de0d75c06a263c213be887b867df9c6dc3b96e662db49c3d016	1	0	\\x000000010000000000800003f241260d45e474a9507beef8606fe13b29d850ce9b09d5c38b7d653a97f953c49ee01265fe8abd91b506c98d8cb7eee21298b3df69eb817e56701d0a88be498fe8f8d6ee2d7ed4af21daee5bf7ddab169051295beacfe3eb7e860d348e94a7626636d7ef434623da6017b2691e12085320aa94a04c60cb25fa40784c3304f4cf010001	\\x9f9c5d0b99527c78d406fe2147ec6c5a13a49e098aa9979504b4684c9e64c4e6db87240192bdd2938668eb815f63d263aa464220933dd7137685b66658013600	1668110475000000	1668715275000000	1731787275000000	1826395275000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
138	\\x5219a9340e0cd351b7fa6dba4cd754bee805b8873276f245be609cdaa2eaaa86f40739ae6d4f26d9ccd1191aaf9275c8bcf237a642de0cff902220a14a401f04	1	0	\\x000000010000000000800003baff5192b4a62dd0b72073f5288a058d6e7e5ae10b5130736284854f6b9727a9f737c4378f288ef20a2b9f4665aa5e00339c29e4533142eb8798f21d5783d9c0a7268a2f9da1c33c168f7a2ead3dd4f945297b33ce3d78f038e7c2493e504834305197aca1196eb6797e37a65c1b5ad6552a6273ff503447bc4d0834fdffc5e7010001	\\x7489f0e9cefa1ef9f9b2095195eb4ad45a2dc26a8c3607021f9203bc015da12557ba204ba44056f504f0d330674340fab7264802935d3ff153989e9ba228ce0e	1664483475000000	1665088275000000	1728160275000000	1822768275000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
139	\\x5221b3342997d2567b6e854cb200ceb40553f603aec4981eeb4d84d6fa4024c87770a89f8cc7e5ace98b82dca2c8f5bf2cde34429b620f1e1a414ef8ee1c5ad2	1	0	\\x000000010000000000800003ce64265221d5c6da34c632b09dbef143f7a83976a165701d224a728e98aa6baffde132f5b8b41268770df536b7b4f7cd25a0fd1fbfec557633a10185f4db2791f4c9c32dd32fba42e825e6d7827b5a2f2b3af08cf6d0fb187a07120dd7518f819f0137cae41d05bfdc72ac6b544ec2d1b85defe96a39d289aef4c61a82081147010001	\\x61a03c9f4411706bdf7441c2b88bda889f5c1944af4884cb85671064e2935d2b47879c01721c328a6a089bfb5140d61db9725ceb27886310d74d177a93af3305	1663878975000000	1664483775000000	1727555775000000	1822163775000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
140	\\x53597ceedbd44e1847c9094f475b3ce3f6fa024ea4bfcad97c266a6e477bc8e0eb70f392c13063329fb837fb2648e097305e3ab7ac0dbf2c8bd2068261feb8d4	1	0	\\x000000010000000000800003c772fab81300d3bfa83092e07dc2311f9e45703aaece634bdb550721959c8bec055f0445a0123a8a9e59c0bd85dfeb270224165f39da0072f38b2bbf20b823d350a02e593136194ff1a3a889d8a2d8eabcd81669cddcb218d0102b0fbffbbac173f01cca862798ef18e8790e1ccb91a22d87aceac591d26038a0d8fedfbe1671010001	\\x0b5e41ff5ce9d89f743719b90c28fb3d0a89b5d4e3d6252021b03a2d4e2b986a40a785ba2d01276f1c9fd5bd4304b566d5b79c66bcfd454413b779dc91702d03	1663878975000000	1664483775000000	1727555775000000	1822163775000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
141	\\x545dc4f81ca0f9b39d6a5049a46bfba76c06f5f9df548aa0250855f6d126ec0031b69f71756b25bc9438fcd73eb9293760f6c7bf94d6329340eae399891510b4	1	0	\\x000000010000000000800003b9844ecfe2fdddf41bea7d5c0bd35f6ac06640c3eaa66e794ccef43a449cd8e50c5ed32b3d0aec57de82b81b71d933e0254426c4004018f1db6dc3ad113581040d1ccd6c255b2e3f475a244967f39d51e4ba1c402569b10384e1987c0e1f44b6c9caca382d2b2f027a72fba09ffcd29b13815e1a368ff9967fbc3c2104b5a4fb010001	\\xca7ff33950cdd587e87b46b65d185e0a8cefdeb0a59e31b2fae7d01cc75ab84efd093abb77ab64046e128af9d298b11177112297187e7bea8a988ae6f6a4a903	1682013975000000	1682618775000000	1745690775000000	1840298775000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
142	\\x56f195f7201cde164df84da899056bc0be6cd1efc1ed9a34bff26488ab74fe82385bd478199d767c45a9ec1ae34f33e00715f453d1c0863fc2f7f9358e062f4d	1	0	\\x000000010000000000800003ddb127f0d9bb2de0b506bcd3858722b6c16c378c4581455c4080266fac64b74c6795e1b2696b1bf386b44ce6a9b473cd811654c66773b45759d047553820d0f22ced13e62f14af9cb652fc093b9a62203901b78ae3bc915ee2c5ddd0bd19fc8a4aac05a85367f8b37e866d27d53217ebed5863ddcc0b07d4c5baac04ec841a33010001	\\xa99d96d375270308bda3dd27be166aa516e85b7bcf4900fc42d472813a0a185255333cd3486d4a969c543f0f577ee27c6c249dfd452b3684bb2a6291b474aa02	1675364475000000	1675969275000000	1739041275000000	1833649275000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
143	\\x58d9bef3577b9a9fbfe18bd2d74ef7ae5796c326435fb8f9ff3a91c3723a166dad174be5b1661e6a9eb9e348b31060ef4489d7cfe0a906aa46f9b0360e9e7cef	1	0	\\x000000010000000000800003b618693535c2da63295da37032ebb301466bd0fa96389eabd90babcc0f17d86d8e2dc59d0afe01fdf05fdb9911da951f69c8d3eb008280773a484bc1a19052c2e83c85cb8d08a4a4d48f541d0633dd6333f357e20d467cf9ba87ea5a562d1e23282587f7c187988d67a738814109609491bac8116299cc37a7e4dcf46ded8361010001	\\x31037a0a5df661c3f6751e6c753c80de6b518fbed68d497ccaade28198247faf56995e882599c24d19c6b4616c1a6c12f2f339c484c2002eebfc0d7fedf8d100	1678386975000000	1678991775000000	1742063775000000	1836671775000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
144	\\x5a49a746cc1680faddfc3dea767688e4c35feb025b995d76e2cf8378d3b95bb799dee8459ec6d0c51e17213b9e814002e103a18742b5ba25a8ff69f77d3c95fe	1	0	\\x000000010000000000800003bcfebda19be614d1f80c45bcb4e6b1f9f85154e8b6d043303441afb6114251f206700be68a903977353cf734e9a0941a2ed97cb77d056d8b18df818eb2bbe7e03dffa58366b8594ae0a3590f01b9324728f19391e238a27de4798f17606400c212d99761dadacf4a75eb3d626e6653d30a32bd0cd48e77d6940a8f5066a22611010001	\\x8f911753b7f3afafa5bb75431c33826855b257ab81f49b3cbd56be646e7777696eb1954f6dff3b2b43c1d2d905baec4edf28543b41b21dd2411cca2417673704	1669319475000000	1669924275000000	1732996275000000	1827604275000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
145	\\x5c1df5bf385e0998ac34facea431cb063fba5896e26096dd90013c43ad710f35457be2573d927064dc7c4cd9f070d20557ed1a2971c713cd32a3938ed7bb15d8	1	0	\\x000000010000000000800003be6b925b58cc7ec421216eef8bde7f866808155193565ff5848a3f299232fd3c0164e44e43dc317201214f482e23d776a3cca12472bdb7402be0be9944c61d7a2427804cc29f4a3a97101667e155e434f1303fd7fca9895ab3cbfdd771afbdf71270ed407bfb21f6d8619867c52f2a03293dbbe41c152b6a38e823bc6510db67010001	\\xf7fa5ff4f7c96e0fa4ae45afff1cdd9cb31f32fa1ac469581beb4c6478626859620756e78cf59b8449c26842770f751ac142a96c5f1149f442181a602243730a	1666901475000000	1667506275000000	1730578275000000	1825186275000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
146	\\x5f2128555cefc77dc84342dc16f0620581a8e39bdb0cc49c6308221a8254d942ec2daac2c7ce75f46259d5717961fd48b1f94f071958bc16b798108ee29064df	1	0	\\x000000010000000000800003acf4d190cfdb5c77f669beb60927e09238edd5ff616301f0bb4f536dd958cdb806b4660e78ce7d297f2164331e33e0ac56a7ec05f8d45748efa51b9f2a017e74539eb12313ec05acbc9b87057bdbf2868e7be30e05aef3572f5f4f168223389814523c533627a0e2a62b23ec8d38d50c7955ad2106a639265389cf712fdbf363010001	\\x4b6c9f0b6f9cc5c37de0d38dc181342a3f4a1b18da30e6efba5d3b8099aabfc9cd898cf74f9b21899cad3d8e5630d9fab6916b2d586f0c7c3789da6dc463380d	1663878975000000	1664483775000000	1727555775000000	1822163775000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
147	\\x61318abd50e913cdd4af7c866ce4a7270548cba54b93f668303997fb964ce0f364a0be9c55a0d27cdb55ca59b4a3b94acc70e86615848010fd6925d8647d3275	1	0	\\x000000010000000000800003d910b3b3c94853fab55559199834936dbf05816b670083dc43bb3e21953e296152441f38447631c181c9d3c1578a8ea8fa41800d8e1870efaee42adeb7f71e2ecdf8894ed7ca86feaee4d142f31d67f7de473ea83dc9b38a633fdb4fd271f4b03dc0564c6084a0d662a7e366bc997286fdcf738ccc1ba7ea4e9c8bf26d3e33bb010001	\\x9c5a423f5b7c6dab1a01453540767fa505a4311be4ee0d6fd4379cde21ba8f9e1bc1a22eccedce431163c1d44809a605d479704fb7a48ee42035f13385e83204	1677177975000000	1677782775000000	1740854775000000	1835462775000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
148	\\x6541b166347730865924033bbd7dc85baab849fe7dafbed52d0bacd7808c4fc7153a34e0fe2e873d404ad127cd9d2637648ecb20925df3b111cfa1e5d37a2b1c	1	0	\\x000000010000000000800003e1a8a1c0c1ebf963fe1558e74932de4690b27da72f5a96467eb680a155d75927a22a499279470f99d431c76bb32caf005fef951a781cd77d7085da48de3382377464cb4e35c73a7b5ece9bf5dae60c2552c67d44e4fd9a98b9112d47d95511ca8ad2218fd17b3e99216e2d8d3e869f04cc321d0775f6f3d1019903dbd61cb63d010001	\\x5e958dfc436747fe8a30b6c16e6341e9bbdffa1afa0b5364d9d00beee6a6d01701bcb594ca1551596bfc4f17ea750fa99a2ff0dca09569e8dd5db6da13876f07	1680200475000000	1680805275000000	1743877275000000	1838485275000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
149	\\x682d7c93627af0896907850850a5f02fd520ca2e00f9f1003b49b0836e3473018ad03e49a6bc18ca9f06d5976737429fa44c7b44c61d8270c6629bc60e726bee	1	0	\\x000000010000000000800003c597e111bcb745e5c79a376381cdbe37a1302d80e755b29064ca987f6eed82e9a49836823ed29cfd2fef1e9d6f66e3bb15638de9bbed926f5d6015559c7bae0650cce97e2cebd7beed383cace8de5e8ab1543120d30c21876658b268abf1b5a1086ebff535d1da0cd2fa2fa5a4adc086fa84dad03d66b20d1b3af65ee2670011010001	\\x6b6a35538f66805b4418277fbe76fb1d8e588b281a8beadd4d3550048069445ed980304d9057d945ce4a0b1047aaa2f7c0ea87993d1a91f0f3d9c8e239d3990a	1690476975000000	1691081775000000	1754153775000000	1848761775000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
150	\\x6865b16e3b0961b0009e166b304ae63e98e453bc76d712b41e6dec931d5770282783776933ee4db754b5c97831509331e5c512f7d2f5e12654879fd0e4540d43	1	0	\\x000000010000000000800003dc500dd187d77c68e8430a28dbe90a002b9e8d3cc0be1e93fc5fb74a566dcf3bd794cc115ce8ebe12f46863ddb34f7ce942801c37fc3e4cd77d9d9a54617fdff36206e0b8a0d3e726d3293f0049bbbd402ea598e4c80fbed5f10dd04b16858221581dc65b0a92e7f74b514cc72a0b086852a25dc9ec03b5a123b3af18b16de11010001	\\x79293f654e6b4cceb6669c8605c19c2766eb691ff955f5a4a39756bee6eff5fedb884c16038c63e8b8145976ee0bb4061d3fd501bab43e7bb28ef3ae4ecb2509	1681409475000000	1682014275000000	1745086275000000	1839694275000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
151	\\x6c314c5b729a2164a24c003b42a015f792861e49188c6999f4b1d1f0a519646479eb1d06b41e819489597e4c790b6f49777d2e211b766d2cc7bbb9cf6369579f	1	0	\\x000000010000000000800003acac16884818e7039ad2a64724dd64ffe0c326ef68569ebc0935d3d5a9dfabb45cfac59153255c1e58bcaaa8d84a16a02f02af5ee97b1ec000788bc46a2ddebdd5daa29be034332fe8df89527d27413515b9a1545245cfa2a93977399754c5a6cc46f990c191b4129e67a03690048b5755d866e78c76602cf284e76c676c2657010001	\\xa3559a1acd58eb2835d395ae8c136005ded6b187bacf8787c0808b15c19f1f932f0c35a1b946d24911c08fca9fa827b3444e1a220bee0868e154f1b706f8e30a	1686245475000000	1686850275000000	1749922275000000	1844530275000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
152	\\x7171f237570f165fa0fc575dccd6bd6008905fd522b69e0d9ec3b85329b98629eb59fac0cea493cc36bad205633dfe696a20d6df180ce247a44fabdad492125b	1	0	\\x000000010000000000800003ad3afd23cfa2cbbba19f549a4fde735f8e45f5252462fd7a9cf4519fdb6cdb2701f558b959eeb9d1b0c2e97b668bc1259aa5424519a39af051d2836f23ff8ade3af2a04da4f0ca6affe086de5a72320fb1ceaa1b488f552da2b4c27543bcf84a3e407ef2a22325119b343b3a9bb529295a6bcb4a77eebb2054487ff838042f15010001	\\x746cfa67c52e2b2ebf810c89e4813be4180adc4edafc3cd1ae1363eabf58e0838f761389cccd2ce44f0a5db7dd1191ab300367b882013b64d90dcf0b3b49c301	1681409475000000	1682014275000000	1745086275000000	1839694275000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
153	\\x72818f741e2512a5d82abd973dba0471c6872ce16908c079bca7d48853a335778c6ca53fe45d605fad10b512aca68cff071aa57bb3af4cbc8cad4f5b3c9c26bd	1	0	\\x000000010000000000800003ed7dea848c572cbf23d6603931b04e82c33b166a19c449588ab88775cfb241e6eaad6d3bf339db909ec7925812ac1895a89da24b9a34c32512a40213ecde69c42058757c4fbff53074ea9cb5e385bb8ea4fde23a51b3ff2f2033aac5b65ceb32021ee8745fab5444795a5db3769e91ba6aa4d75fe98c00f216cbdf8e793f1163010001	\\xd39c63c23803bb343996d1547ef3d43c04b90281ee4d31c7cf29d871768179cd07c633dfd6336c23ca610733f6c1a946428e1e49ff85a355bffa7c6d5470ab0d	1688058975000000	1688663775000000	1751735775000000	1846343775000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
154	\\x74c530c9a7eece51fe91ecc3008feff2d1b3516c23d51cf24c5e93a05fe83e858984520500ec8c0829a4108ee21654768ebbe83992e51aafba2dcb3f49234d46	1	0	\\x000000010000000000800003f587104d9f0f6b3615784595fd2f25195798eeab1e5192b2ef22ceb3ca2b7b605e73afd023925bc64484759621e705ed112aa63ffe261c229f9ce288368fb0c7a88816e25928936c40f54d0825cb48b637270cd5e646b5d8f59018570863ddecb4c17aab6f3878bfcdba40538985c6ce3463ad22a8939cad396ba3bc88ce778d010001	\\x4aeb39e6b03bca58937d1f5498d57e1ae8aea8935c849950f63167628362e5d4da65d8eb087e0cb70abc34a3a3ca5737c3959eeaa0ed8e1908a5b4277202c60b	1672946475000000	1673551275000000	1736623275000000	1831231275000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
155	\\x74c1960f459b742b540c52aa0f59271cb1f30ae4881691c6ff0ccbd1877fda2e0fa84763effaddacb45699b096a4c4efc885e0a0d0c5a3294d6326957c767a06	1	0	\\x000000010000000000800003d42d63c5849d6715f1399625663d65b947e19b30cf5cb7b23ca9da19c653b0029d1105567edae6347d697ac1b4d0fb60349206c6ace65295d17baac35c99edcf760c65ced14a909915fb58e6b8c3510acf9c25c2c63cf52deeaea16201cbc2f589926bcde66be545c0b8dfd6e51cec639a1f7664da2c1ef8f54cf4c3e6eabc67010001	\\x102565e9688f697bd20fba8eb3b18ad240c2d6ae946094dd2d7596680e13b75a7a11f6122647e0dc716171f42e959490bd4620029834d07e7f497fe812c8d200	1675364475000000	1675969275000000	1739041275000000	1833649275000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
156	\\x75bd7fd7b191ffc60888b193e8a869638a1645f1a3dd54cd2bfb6f9ea8f0f69b7b7ce8ccaad13171c296f1e2c4edb8b1f945ee6190154ab824518277d55b24c1	1	0	\\x000000010000000000800003e90969102ac02e5e8d9591669584f6267cea9b3a1bc0d31285b4aa97e900ddfa46d78cfe8667b2cd821f6b1217573f89d7e39720d150d0f35f649aab03aa014c57523d14024231a2a3ca52262a5bb332c0d6f28622116215b6124d2e975d3d8e08fb196a934b494abfb346fdbc74883230087b2feac3fac5fb3f43159e06a679010001	\\x3a0bffd21974edc821103199481980d21bb674e71563b47bd3a385af272fe6c8681df389a3640e8fa0082f031f33b23985ef3c37d9e2c557a14c1632d9e2b501	1683827475000000	1684432275000000	1747504275000000	1842112275000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
157	\\x755176a4b5e35f78f330fbc451933f2a0fd83c7a6aade82b608752ca1d767177fdc1194785883db643ffe8e48ab702c5278a2429a8e06a0932e52c9b3a9dd57a	1	0	\\x000000010000000000800003e98b52587cfb767a352d12ac712ab833f4d0b6d3022dd6f219bc5fdecba8c54570f48b3319ca44f17dc0177486f42665ec41a11e71644b01ec1e3a621eeca66fc62f8b2b77d75f7eb597cb53207582cf31f6f289501647f6500cc288da2da319d8f46f42ab02b2fa5fb313177e777616d64d712d34f38c6ffc2e1c7aa2c65b69010001	\\xa4cca97b4b1bcbf723a6352ab002c75e60f07068510a3bc8c1848a86225ac315fdd5747bd95f4764c4fa3a1b79b90a562fcafac054793ee669dad90b429b1e01	1687454475000000	1688059275000000	1751131275000000	1845739275000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
158	\\x78a130d1d6cd2fe2fc29491d9051ef6b1a688767c059c77205308f6db9267255498620ac67f2b265f2d1b57ed1a26e8367c8492afc561b1fd3183cef5d91525b	1	0	\\x000000010000000000800003ba4d9febcaec7ae6e6df8db67430df9ac38c5f92bcda4eae422bd34dca308fdd1faa4592d50cfc722025534879121b113ec16dedd8e5c8400c5814c6497ba528eedacd0f7a8afeea5dbbe5646eceb969c92bd30a5d4a98e735b6bf22760d153de4ee1d276d0a51a33468dd2d8ef1a76ef49b38780d2e9aae73ec5de4c51c442f010001	\\x4428cc66aa01751a5cc384181cf94b63f9a7a2e3d8a59f741e735493e01d0e1525ffc2fa9647c90f1b5b4e9701ef9fb31ce038435b3271826333f37b00ef9a0f	1679595975000000	1680200775000000	1743272775000000	1837880775000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
159	\\x7865b6f4e3d6c25c15daf2c860d9cdc6ee3808e5b2531c961fcf19d4d2a19c433f059c4c5eae408afd271e21dfdd77a996aa2c321eb5369198b20f6c6ce39de0	1	0	\\x000000010000000000800003df4beb99d8bc0d8fe0a8f4e7b25580ca9cb6a00971cb5b8401575e803778dffd9d458c71f896936f941d3b1853cf809536bb196e9025f396c9ffd3b6ec5865f961f8ba7f1f15d52557ca5972a23b0e4fd024ba0378bfba72fe36c74d69ed51b385cac7f633ae8c213d03879e81aa2d339db5c2979ff96bc7b8508183a4179e07010001	\\xaac2628ce746451c91bacf4fb5dfb468d2432eb8f32173d71470054f2f416e6db3f306b65a906c4bf50d94fa0018f908796b7f3cf0c9940e70039b009c02b200	1661460975000000	1662065775000000	1725137775000000	1819745775000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
160	\\x7c51c1ff54619e224703de0dc6e98881844242a1af8ea4c69820280ec6b988fc4620acfa0f7ab8c5f670e388ebb2e7b98f7690cf46a72fc98c042e303b90afb2	1	0	\\x000000010000000000800003d84f86be0f6f1fda709263aed1dd75a669e50076c1622ed5d95af72f66f4fd27a4e9ebb02b199a255d7db83a3f84a931daba1f6c7053ad6f17e641cb90c571800c1cb3f2f279a8e8d27638f33819b88c293b0ec57533587cede8fa12cd05226992ef19beeb694a1e2cb217351c0311a63255d4360608ae96954aaadb3e4ca597010001	\\xbae2bb16807cbdd1b83c1e886410ca4d73361239124e1dd3c7a97e48f5ef1b147702ac6ba5eb2ba094d2d71f326344903468a3fee9af3c045f264ac14fba8504	1684431975000000	1685036775000000	1748108775000000	1842716775000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
161	\\x7cfdc2e85304e189b85b891deac40916e47e2815dc615892b1b788ec433cb92af831123d152146a95c3bde5671253a96091f075890f0f9cd3cb331445b739435	1	0	\\x000000010000000000800003ca8a2e3262f5aac326107bdae4ed849b6cdf4339aec58b2588db54b3ce2d134992858a791e0e15ef17e2477ee0cb5a59f24aeeac0194b4bbcb6544cfafa9d998b4c5fc33fa8521ea957c44709149ca891c2e9c686b008431dcc8eeafe57c8f1ddd38b4fc55ff0191463be659b4eb93acf6eaf6ef4965bb3c316d35a08293ff99010001	\\x92180cea1a63ed79c40f680cad4a552ea9f25821bc7cdb92640263f7a5303fbd8383c0d15c39eba938940df132a9aee921564b3541d867eb0451d42ae239760e	1677177975000000	1677782775000000	1740854775000000	1835462775000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
162	\\x7fa12a45cbf687fe58fc6a159c960f69167a55dae774a71fb46b51f5f05030946ac601cb5bbc9689f4b27dce332436c4e7081c2b534100d6ca3320353b629e9c	1	0	\\x000000010000000000800003ea2f19fe46d775a9b401fe80f427ed3a97578d8e931024a9d2775d3566c19f0c903373ea0a4ef1a0d8280589c2ca4be7939c27ec47cd423860974054b6ceab04c6edc51b001b6f965b335401b695a8f6607611740d84bf15b3e8b986ccac308d862d670aa4bbf07083c2d0a3cf31ba6b2c4e7e23723eaa86b441855367d82635010001	\\x00a3f2c5b7431ec32bf0df490d824a3916d464e51f5b637226f69c14abda099c633808db1e9473a15684853362e5ac00360abde6e3f6b623cc5112d1fe51d705	1685036475000000	1685641275000000	1748713275000000	1843321275000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
163	\\x81e199c30822bd59f73a5c7df2893fd6ccaa416864653cbedca1a031208bb4358cdebc69db4bf44f56709140b260ec16d062d6ea458273d3e8702c57b74a8150	1	0	\\x000000010000000000800003aef4ceed4f38052a7a7c03d7e10a9f10f1fb4a940f05712c1ae40372637c5708071b51bc3c207c954bb2bf0a4eda8e26303950c963312ac565e48394c86bebab343ecd0ae345425dc5d147fe5136f34a5a25240e9acd9bfe338b4e0330e5b9497f4ef00d96e0f3c1598cf579323cecf331ed6e0896580098ec9e226e9bcfa731010001	\\x8670e7d31229f186b4ce3db604fae10978418d5891ec7902539244cb717208cfaf1865fdc5d152ce6b6f57006582d250262d663fba49f9239c5ba92795303004	1672341975000000	1672946775000000	1736018775000000	1830626775000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
164	\\x81e90ff6cf7f9ba72ca5d44804073834d4f1bc897f1bb9e7723b188d1127888786b8e74121a93e5ce1608ffebe539100132fd881524a5312c2483d40f56b39af	1	0	\\x000000010000000000800003b84d98a011171dd37eeaf28048623a782e88ad921cd39795f791d30b2c4e822f905f347eb3d142d3b44bbb77e994cad03cdbc7bba68a2178c8ff83053555fb87fe166b0458f0bc7eaba7747b22a02ac961271e8c45455c381ced3acee9814e95798b06ae04803b3b5357a856b2374fca65f674e4d4cb2c7b15812dd410d11335010001	\\x4290ad20d40cef20ff3a5a4031d2241ecfcfbc275ddce478c7f3ac428ee4517761cf29a1569f278d3c8ecec97482e308fc4b45cd80293b2efba899087760b605	1684431975000000	1685036775000000	1748108775000000	1842716775000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
165	\\x83f538344ade57089f7aee31be19165aeb5a0cf26af7a83256f5ed75e539ae70402203a38f71a195a1424e7a577ceb4ec5e4e1b132e0992a3d66252c4582c66c	1	0	\\x000000010000000000800003b02124c51fcc5a9673e1999c24300cbdf2f56760b81811c1a3f6b2fa6ed38d4e5c6ff795f0d5f9e1011f1471592959c3bdfb6739af91bc48fdce93d27920523f023d9a7ebf92aad26e2c83464d5887afdb7e913a5515483acf04d16f96821938fe789d45c46835fcef7e3e1f194f3f2eb774abc13cca1b04030d2388b13023dd010001	\\xedf251d1563b997eff1ddda8c19d340b3e9755d84df733f2f4e3021dc4bdc0468629a48e13702c64d817d9303f970a30c1308c289e3b03b4794322227eb5560d	1660856475000000	1661461275000000	1724533275000000	1819141275000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
166	\\x8519d31a4b903465fe60e55cb1ad8c34ed8c4b7ca96851084f7d50a9acdb91d22b5cda380f62b14931d7eb6986e10bc8c7f0b01c8c1b4d892a76d5209618ec14	1	0	\\x000000010000000000800003cef1a2ebf7cf996f7d11b08a3aab478a3f42230f3e3e1015a58cba09b8848cb9f17ae2465464eec1d7f4cdf81d9b6afb9ce01837857b847ecd0a03f691a5c7732271093cc4b36b734fa0ae64468ca7d9088943143fbc22800f2413df7ed28c862924cc77f07f01f2c3e70f9d15714b4bddcf9b3f7aac169dd6b4e37e0d6630f9010001	\\x6bfeecde7d94f71511fca565cde985fc278a20752d6b99558fd64e5cb08f441e2ace6c66c558c4a39d43c5609fafa32baf49b66f09f43687af3df987121e9e03	1666901475000000	1667506275000000	1730578275000000	1825186275000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
167	\\x89ad27664e7e37bd684345c88132227d5e65fa2a3eb250f365cb7f0e87f5f899ad8b44c0a8f9cfe1e16b67818056b2e1e750debd0e3f08e7927856251bc4a6cb	1	0	\\x000000010000000000800003b91c83784470ed39a2a4dee323a2e496b60455c92643b757c89c65907696780de992ed62cbe961e5a70215b773a4e1d7e692a7667d6594fc282f3469b74e84f98d1cf402178a0a43b40608ae905e405c5ed220da89dd22be7d9ef55d4211e4c93b2b186985f3ff11b84ee6f01ca890be5a0c1ff88b30ab6f5360ef0ac95cbd87010001	\\x03863cb6bd5ef48433efcc3ada04724342c2b0b416d484612cc71f1663655c3c4c842f1b1ec5a026c3f809d01f34d5282eea7c3440bb8abe887eb5d31a702b01	1682618475000000	1683223275000000	1746295275000000	1840903275000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
168	\\x8acdafb48b777ad40f18d29f334a9d2c349bc5dcd991ef88cc79b82b822597a87b28f4c26a321ed4898a569c91e75a708aa71315d0d011d615a546b5b7c897e5	1	0	\\x000000010000000000800003b5be70a39c3fcdc3d58eb8ea0e0b84b336d1610c402c08f5197d11bce9aa1513a609cba7fa196d0674ace4dc1736fe2ff98d1321e2689128103841e8ad7c80e112a533152908dc58c824361c3970a2f9407d3b96dcf61c9d90d17c94d90f700f09e337810ba4f5ed79a0b68f6dd97b0ed15269b76f724bb5ab32b7ac1be4e381010001	\\xe462189147aa7cddcc02b83fddb98e23b2aeb4ee4d1e12d977ce68bc6958f8f747bad28d2205f8eb0a11fdedae1737f69ac4ffd151bb29aae83133833af4160b	1669923975000000	1670528775000000	1733600775000000	1828208775000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
169	\\x8c4101f7a0ed8dc13505c91cd30fb766da1c5e2a9eaacd9313e0a90e5d0c6812e2c4815d484cfca298b191846875db7e7418a6499c0e0b3e21f0275e992d7e89	1	0	\\x000000010000000000800003e0c7cb6980faa009cc588c2a934003174845501dff7e5d1a8536788df530815afb4119de93efda5c004cda8b70b294b9e53db1faeb7f65d2b975cdf94c6a3878996105e1ffbe043bc18d22b6914f01e84efc2ca62a1edf4ae95c5816e374d6e63d2e0947e665d07e8b3aa54793ba8a5debdbd818fd88e1fc873e948d225ddfcf010001	\\xba8deb80d023a8cd3e0d6a553fff0c5367953ccba522bc90677e4a67be84714434321877571ee40b5995546dfa58702d09378ed46133c42f00559bf92f18c600	1669319475000000	1669924275000000	1732996275000000	1827604275000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
170	\\x8c05d6a28f488cc247507f8a8779fac5ea8a35a880b96d024c2a46dd498abe53fda6d6e377d85459c1efb1f63d0f1699d299e8c0517ce9299a2404bcc1b973e5	1	0	\\x000000010000000000800003b4bb9cedc5bac807e4825fac5300463b4febd868177bf0983d1fa518a74f9ca0a580dc74d067eabb874b9f14d429a8938e03b7fca7a1a0c0e72d761311b667a0255e7bcbe7cb67843f1972560ceee074cf356dd085c9a2a056240e64f969f61dffe43f055454985ac96084985c8f002eaf250f3b906983e17cbfe61c2e948913010001	\\xf0e67651956d0b75c45c81ca3c3e4afd639e0d07cdc65fc5456e506992b37b4338c69c83b3175fba3a790e99b4b7c6179bdffeb8a36e7e9740609750e5bff208	1666296975000000	1666901775000000	1729973775000000	1824581775000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
171	\\x8f111189e050f33a8b821a6993c337fc05c5006b0a65f7c63e688e3870183d07dd65b802ccabb15316f211f0ecc525a9ed3e9255038e7950bc3b786354a6e957	1	0	\\x000000010000000000800003cb9bccaf59c95158d6da0d801cbc76c637a02ca70fe7fb05db9f5872081319773cf0473b5cabb81bd87e03a6ef40ae2066d7bd7654aa7bf615229a90457fe52002684b42aa585ca34f1f69eca33e1338469f57a840793ec2cc30eed77b59ecf8a6a83c7ec696a41844545d08c16fe69d7e1c2dee52ae81d9fc471d438d2ad1ef010001	\\xef9974005b0f99dd62711946e70c16be8e8987303fe9a8fd7c7b8696b6e16ee3fd1d9ed112c5e2965a4518a85d52552dcd50e2eeefd7fd3609ab34ea67dcfd0a	1691081475000000	1691686275000000	1754758275000000	1849366275000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
172	\\x90a9a527fa42463d69fb746ab90a48ba5e589a6a429494b4da4d731720394898f2c7eebf8a2fcc42dfe916d3eedd6c4e82178bb7b0a987277ec9f91953ca0040	1	0	\\x000000010000000000800003b796c500fcf1ce28943c4b3335b48f871e6b6412ca254b99a1386813a2663637f979897de22809041898f77871ca90ef8fee38a99b0b434555fd6fe00a8bd76cabca62798730f21eafdc62a8e32d04df935a7f68517567cca026db04ff8ccdf7f62ca8598b2aa2347296f972bd92f38875c86b5ec9a44e3575658ec97d8b3235010001	\\x2fd11f6917ec3979274dfeef87e9590d324d532ee62cb49aaa7199e845d829c359c0f1759ce21abc08cf8c89e7621e60facaf86b77ab0a00da505f6e95f52403	1672341975000000	1672946775000000	1736018775000000	1830626775000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
173	\\x937d8cf375deecf3e86bd78f4e04d3ff29caa306b133e25cd634d92303484eac80a7a29a259dc4267730b82196768270d5d6e0fb7348cd64a1c2fed577078ff0	1	0	\\x000000010000000000800003e417b17e7a4b85dcbcd8850c7a75cad916c1624c0524202262772f4a21c3043e9c01e7558941c954053c27675ff5ab95b26bdcb6a469366aad006bd52814271d0dcb78d1e32e90ddcbf0e85e5289d31671a945c103cdb6f497f5c515322db125c488ae69cbc6508f54f5de039860e879f3bd4447b200f4a0a029fa9088ebc80b010001	\\x6620525c0f2c9ff4d36ffc2ac473aa5cdeddd215b836791cdffe44852007cff7451c2b2312e161fc74efc55f7b3a51f5bb45920c004ec58d4efaa59d78e4ba00	1677782475000000	1678387275000000	1741459275000000	1836067275000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
174	\\x96cd5133e8ecebd11c4ae2e0119e29640f2897f8b69e20c33ca6815faa360eeedf2bbeb239cad025562430f5811fa987b3077860cd447cb4364abaff1515122d	1	0	\\x000000010000000000800003de2df94a03ff851da4dded401480fc5e42bb9be794ecb739bf350981a9ccc6c355b0c38323a7336dd6cad6d8c310b3f430eb92e99a136c77fab75821def07d6894ef970475a326d45e176eb36855d21c637d48f1e2a78cf8f9dfe6fb59bc5809a370a927e640595d81981b219009974b47afb21ee68e0090595cdd246022dda7010001	\\x3cf7d421c48d7187a87b33c00692b877e7e151224742562c8fb4a0133107bf9f7cdc5989b9809234dae921ff554a8d529e424cacf7c44a36f652c776b7a61404	1662669975000000	1663274775000000	1726346775000000	1820954775000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
175	\\x9919122be2d6965c411bc7db2a3ea09ea6583c5f11c61aefdc811cac7ffac2b9e3125da6a89809b651935edcdbb834425ccec0f80caacb25e9b0803965a8d139	1	0	\\x000000010000000000800003a6a3006f149cb39628d16f812cd82d64d282afefe769d5f081f9f24cc3da4d30040d0691812cc7cb7553c7cbf8d30a00b444921bf61e17cac4297043ba63bb41ba1e77cd0f36c00911968042ddc67de67f26661641aef9f6bba5707677089eeccd4464c18a895fa792754d139baea4604b03fd949d25f074259a4b4e285544cd010001	\\x435b68cd6485ec0640b146bd92fef5b296834316d2ba602e1a8fed93cd276d09713e2c9f29a6ace01fb18ec263921d354d3abb75de1989dd5004c76241af2f0c	1686245475000000	1686850275000000	1749922275000000	1844530275000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
176	\\x9a0d47c238b82ce4985bd32e31bbe70c8b35d009b6fb2c7fc6a8e4fa2805d15a59b8530ed2326e4ee7756feb4d9d0ecf2918549c07886e23e5e3890273c16d19	1	0	\\x000000010000000000800003a794d512df1f0cde5ca0c9fb73e318dd02a4d8ed7898a011d2ecca19c801401174a9249cd3a81958874806c9c906aec838e307868ac13ae5e85d0223f166594f1b1057a6da42b92f7a310e747eb0f076189dbe2907bfc29a183bca36c8a11ea9babadc66b3e2f23b11a96137753b3798b48313111821260ed69347dd0ecbf535010001	\\x9c6b714c73989490966b3b2d47613d1e4624e1f50ba4706275188dcaf280a80f703d5e8648af73519fcbf373e00e8b736b4bb3762773031890a5af033af0fe08	1680804975000000	1681409775000000	1744481775000000	1839089775000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
177	\\x9bb5e389c1815d3ce96c7c3145e35ea88b31ab1f2acb850c79fac133dd5e34fbdaedc3feb327ad68aa0a76cd82b0749bdeeed78335445d4f534a57418f452066	1	0	\\x000000010000000000800003eeb43e1b31081f7bdbe7fde72af4ecd0e2f85b5da1abefe1e1fec53d5e7aff2d59478693e20de048f38f24d16cf1d2a5aaa8802e1a5a7935ffe97ea315d62cb9e93fa21596010e1f660fdff137e688024736ea2f73d08092c4add4c82f06fc93cfce88c060374eac7e5e2e6168209d06a8f2034eb864db6527ce877335f5b573010001	\\x4acd0ced2a3e1be507bfcaac4f7ba83c41b5a0e007e87d639e05d6627aa98f8294e780987aef9dd9661e0cef7a485b95495081d9851cec3ae743eee64425840d	1671132975000000	1671737775000000	1734809775000000	1829417775000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
178	\\xa0dd83b994a60934bb9ee448601a81b34ee0b47d5cab4d35b285d5421cb58b7bcc7d43762ffbfa12dd6ce0d013ab6266c32b81440bf1fe5812b2b57a6b6f7de7	1	0	\\x00000001000000000080000397f19e6286040e0ba5ea2c16848e843ef655546e7b4efc0f78a6a640568212caaa66b33abda0f6fdf9f1474934a37c6af9522927eaeb3ce7c205487c4345235ee7beeb92ea37298aa9a1a9b1a9ae89bf1473374d0638eb2c5f8197b41597e359efbd82477a0d5747146ff8f57d4d0c0f9f6cbb16e5755e82b15f20aea12be2c3010001	\\x0f8e6d8eb3dc794a481b7f0e6485a1db3237ec39d496613043584d77f1298be802cccea2a49c274e736f8db9524501ef5483a75ff132d3ed9cc9572d6fa70205	1682013975000000	1682618775000000	1745690775000000	1840298775000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
179	\\xa2cd6e39383b5020700d40350686dd054a6415e1c76c2e6010dc7ea130cbfa653a856689c1893cd7c7604c95e70bce2e5e2bc7a637410744142a61a9e9484e40	1	0	\\x000000010000000000800003e99cff4a63d19842fbca2d521da68d5b201bd51901b5c7804b3300dfeccd4d9831028b22d5c4be1fd949b5ea0a326aedf66ee59b42dd759ee0236ad63b733123a4ae5999abbc14b897e3f8774442b1457b43724346ba156261fa7d9d6cbe2fdd0fe82645c7a8f038bc47ff555bce0429a79bef9d01811735c7eb2b3c5602e54d010001	\\xd35139a34631b9d947752ada1f3b18ea687f24819dbb8995d8fd8c39728e6cad151e162eb602d6254a8b641a806d4d953a4b832a84482b69f403a5a64dd70e07	1676573475000000	1677178275000000	1740250275000000	1834858275000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
180	\\xa449505166859713aff04ffed747368c2faa1d8240e048b5c7340f32af1fdca01160fbd32fd956f111d1b9cbbe69157f0304eb39c3055f8b44c0a9da4a8b1554	1	0	\\x000000010000000000800003cba52020435b21ab5b33f307b2caa1086a24bb3ae622af427963ab712bc1010f9f3cf15d4595296130d594dc21360c331c3c97e898db233d1e277e36bd90309ed9c40f13d5893a77ded464c9faaba57c4422dfaa2da5b3efae5ff76fab28f60c7383b369125755885ea701028584279b39435585231632a8f82824892921a7ef010001	\\xb6f2a9636deb9ff214539e5d11656cc1a1dafc6d049a598bfae37da56c5236d58b97487665a39773e77d466ceb70c473eae260432c87e27178186bc5c8fa3b03	1688663475000000	1689268275000000	1752340275000000	1846948275000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
181	\\xa525d177af4a7c4293b96ae4b3d07cd54c38bcdf766550b6dd24aadaa5b680db825308f9604e5f6ed82f84ed37d9d019b20aec1e419ccb8943bdcc9ed45810f3	1	0	\\x000000010000000000800003bf54cedba7de0c77992ebb1a390bc639b894da11ded64803e695876da80550447501e1a5e14bb0ea138926beb6e5f9ac06c5468335aaa5a698abe9ffcafe62577fedb0d7bef76e6a5844e4c1685ca76d8abb280a2ec06afcb6b15b3a015f0450edda1a94d6a05d82ae74407b28152a4a2d978ff5d72eae41d827e2e70dc7e9e5010001	\\x7b88d79518b3f13de70a28fc1b07c1834eec1edbbf761f71adc7f664e3e27bed5c1128c186fa19c6c2bbdcd12c8afde71d51ce8b24074a16505baa9db9c73a0f	1675364475000000	1675969275000000	1739041275000000	1833649275000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
182	\\xa6219a21ea5f507001cf3248e445bf4e68bfcfe741e60838e97729af18f5735740ee16095866c787b49de20cbaa4f5fcb4430653483341c3226ece48ad46adaf	1	0	\\x000000010000000000800003c27c7e88b238a47c6e13d67b4d25269b67295f7227a8b6c71bed616739ca18eaa7e107455eaefc79ca47eaa8f58ac420f707e485dff55fdf5a9667c2c496e2596dddb4479ebad3718b0fb7b14610c891ecb8a7744018c4e39585a7b020d6bce9a35e6474b37f352dc93e6149fa379d4e9b1b2ca103d5c1958a3ac136cd7d1ef7010001	\\x43b0620cb26ffc5ba9e1c6dcc24e6f4cb71bb690e9531967fa807a5d8c76537359eaf7777599603a28ccfa3394e32bf1d48accc72a26a7f5af58fc5deb9dbe0e	1683222975000000	1683827775000000	1746899775000000	1841507775000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
183	\\xa7193e2dbe1ec7e1ffedc369819575a068ee9f6147bc2e1e9182d18ddc00db5c641ad360a6070600f6c1cefa714261c69d83253b8071afb5f3c963d7a56819ef	1	0	\\x000000010000000000800003a8d4cb8ba73d339ed754a509a9b42c0bf23562d8dec461b10128e2a5f4967aab6f92b93770d59802ee688a853eee6756fc4430097060562e25bfcab03d82c3188fd895c2f70e1170bf3289cee7112e933a92ded94776a9e75c8c2494085e450ba8080cb50ca97434ca7277bc134d3aeea256522462de798464b8d65461adfc53010001	\\x33e969be5d1f26bbda6df80f69a8004484a86e2167b9fa4ca1fe886c53b14361fb46fa68b4302554279b6a65e3c39c3fddd229f8fcda43c46b9c79feefc8ae05	1663878975000000	1664483775000000	1727555775000000	1822163775000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
184	\\xa96573d428cc8a0919f296c9c1f5f56f87819657a3523fb6d3be893f41c8313ddbc39428faf207b7abe1e07ca6378eba1a1ddb6ea3af571acfe09f2dbf9455ad	1	0	\\x000000010000000000800003d1a35aa42f80e863befe442da3df5583b8cba216d7c3339d16c2846d7c8e6791940c878beaa904e6e43e56123a47d5824df5310c07793015c055fbabb7c894248f0ef21c05ea9d746b656d389bd3954018072a0a82e0df652f0daff2e9e0b5a85d7a7bb50d788850d772df37018c72ffcd3b8f16af174b5603bc76a3bf7f42eb010001	\\xd33c3f751b69fa4ea28d5bca8d502b4c2210d8c2a385745f9de86254e6d22a2e6f31ed0928cd633aa7422f36b25e865e04b4f9393f793506c6fe20f4e3c3570e	1663274475000000	1663879275000000	1726951275000000	1821559275000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
185	\\xb0911e149315f045173e51d6203a68011904cb1f6e7ad35015901ddafedbbbaf1b7e23ab8e0fdf48dfac9d24ff691b3636827410cf64ce5606c2947f676d7dd5	1	0	\\x000000010000000000800003c6f18c0820fcb08f19f333fb5856b49e75df08db393cbb918d334912ac5ba2f6a7021cc092039041c49ce66dd910fcedea70007cf4afc1e342f19126ede65a166cc6f3de7fce831f41287482d9f2d85f46c3c9f556a01a00b2a58119247859ee5a422b7c7d3772e230e6048f7bd09db6267378232127613ba973a60300009a93010001	\\x5820758fa1273d532d41f2db5d3e4788558346eaec44843fa94757edbc11374a5bfbc291c12476285b89d01053c243dd81d33385d66ef4f91eb004a5bcbb1c0a	1663274475000000	1663879275000000	1726951275000000	1821559275000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
186	\\xb19194421398855bb2665ef03001dd5ae8f66541d6851badf38b1469b269245965479f41da2e0f873aa065f97b9773942d8b1569543451c9b30d7a886ff24091	1	0	\\x000000010000000000800003a049cdd7ac580476fa5418aae154369c02127d281524786186a8746a8ac9351bf5803ba01603922408bf0b15ddc05bc945699b2694f2a55e4694b3d89521ed6237ecea03fb110629c8b4cae4fd8146a16778cff307b82ab6de3e459b89eeaee2cf8cbab9dad86eaabb4fd7f6183d88cde54441b459a27420765dee30173b70d5010001	\\x5c580fac840fb665c2859ba7ca99da45c3386e35e7007f0be2edaf6ad0333d8c9849314d1fd38d6653d4b7811afcfb37dd23e798bcab8d39f1fe9eaf55f26a07	1678991475000000	1679596275000000	1742668275000000	1837276275000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
187	\\xb82953d9058def9307c32cdda219de7362b5d0cd1279ed9bf7d4c8a2312986365daae41bdf2090a9259f32c4808fad5ed1150e8ed38771436b5683b97b8cc737	1	0	\\x000000010000000000800003dfb652677ed347d2be813e9961fdd7ce5382b5229aee69925b81876a6e17c74fbd65c478c11d83984cbb5de1049d92671a51d193469871ed415a3e8d9473da7a8120a5905d8a65b19ce91f63f0e600637780dab304f72d80f88059a9d595417cd956d3c95e668a230b0610df0a43b89d6f3bcf39f19621a5dcbd6e21931067c7010001	\\x8f41abc741183b541fad0699164691a4c9c1c75c167756624106a8b60c72c5faaf8041db01b0759af9f2f892c21664fbb9e93820e9f6d8564dfeff34e6205908	1686245475000000	1686850275000000	1749922275000000	1844530275000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
188	\\xb95d742c64d69486a7a1d1f1f690418deee27426ed1f97d4fc399eba3bd5019da1c3526b9deb7c27115cb6ab50dd285477cac27f8b18a4530c6af0630b102d69	1	0	\\x000000010000000000800003b2a74eb39afa89420cf6c59dc2ee4dfb9298474269964dd08937cb1f0e704ac0825e962c4b6f091eb6e30c4cae2b7d122fca2e336f588256430fffd27c6a704d20e816f67c680dfdfb78532a308d983b81956f99999575459d74da1a02ba1d5bcc86e9aa0182a0ffe108cc0989c01c92702367907608d83560fe52e46c7713c7010001	\\x3fa7ac199f8239de809a1ab1f66e38855d85b92c229d229a6fc7393023057d3eee5ab23a3348e32103d85d493cdf21cc81cc25cae39fcc5e8cae21d0ef3c630f	1691081475000000	1691686275000000	1754758275000000	1849366275000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
189	\\xb9f973113d5f28dd0ce59116032816a3364b0101a3126efe09a973b476132609fa03c12dbd3b63adae5f8fbd4e882d4b1ca6b0b8f22876552588e8c1a57073f7	1	0	\\x000000010000000000800003beb42b6a6bb512416aaf2264e5098d58296eedb291e7e91974b8538c28efbf9914ea2ade020ab57777b6fda3eca172c73c177e9ec8ff4e9c55662580fe01014112edf2665dd854570f0361ec493ceac0e01229c5489206f728ef6de128d7872f02aae39baf2fe13850af8e0449c17eb9613d7368e4e19a5df01cf501ab67db5d010001	\\x120d0b383cb2ac5094df3f9d89d200e60037c4c4441523d8ee9fd479bbf3da2a739720d47f1f7b073c2791fa57a3f17fee3a719e3396efe62f6c04d90795e309	1682618475000000	1683223275000000	1746295275000000	1840903275000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
190	\\xbde51e6bd9bf3d43eba8b19d57aa70abf313bd82ae26c9cc7dcc545d1def6870078000cd46ae87675db809d1fefd01e7903e7d1aec071b42cc0bd2fc361c0cf8	1	0	\\x000000010000000000800003d448640c85e5a3c486670093b9e876be7a47b5c3b9add1acb1f30a42d689fd8a393036f48fd6fa375eeb91c63d986a28a49724cfce773811c2eb9e5692e742ac5c4814067c66202e6158d2cde77ed696a3ba12916ffb9b3acc3edc6d0175345fcc01807346e37a77de21d7be521560e83426e41b7ef0a656320417c422eef115010001	\\x284283d5eda395101fbc2506e73fba8baf4aba384932e42a72e06b216a856b3eddf3421a7d74a6bb363259dadb97899a0991be6e6a26df1f24c7567c4d0fda02	1686849975000000	1687454775000000	1750526775000000	1845134775000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
191	\\xbff9c8b9b00c8c0d4acc5a1abd3bace475eb5a859403d87e0d39ab2f0234fa27f7c6f4a52192048fe2e6a4fc992b2a8da85e0cf805860731a385729bfdb08d5c	1	0	\\x000000010000000000800003c8d5f84a161ce988e98807b2bf5a604a54d108b5a0c572cfebeadbc7435f81cc285677a7dca852ec9b7b3f0b82d2a0806194b20e856050eebf3efad3bff98152308f0cac77ec3e92397a63afdb15f8395e58ecf53239fff387b530532b9fbbdde08f5e7d2828ddf1ecab57573c8762a797fb9663319f9185538a1036a730a459010001	\\x324640fc0fdf50498492d8e9b743b9861485014ee4bb9af26a4ce50858a0d6e6da8eb9ee131865cf5cc24c2b0f0140d077d3fbe896b1c16240051c48f3080b00	1660251975000000	1660856775000000	1723928775000000	1818536775000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
192	\\xc285a2222805b9cf44a832f155284c6892410a0e0fada87fe3752920efa83c0f29ab4ddece6a15920b6f5249f501b8f9765e8df2b4aa1bfd0ffce0156f1bce94	1	0	\\x000000010000000000800003bd6f01f9b70c71e759a857be3cd5793bcd6296b7c9fc67200e48843f49e336f6994fff9735cae962e5179dfa402ac012df0fcbe42dd7e3671043bc3d9a705010068cf46e8bac0f94622f5f200b831f906bb37aae10ab922dbc19543103d92878869888f38efbd2c535321cee05a9120cceb7201c7fcbd5b9be37083bc35816cb010001	\\x3f0c17b3e528d795f85f15acca06d469ded053c90e9038481161cc9f551dacf1b32e98fcf926ef1feb5d9cdc0fd1a5cc0b746abe9faad03b4345e90ca86ffa0b	1674759975000000	1675364775000000	1738436775000000	1833044775000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
193	\\xc8edb3da9fca0606a5dff1c594aa2b68c04050e935b64ab18f66da1f33fc67bd5c8fdeb0ce930a0af17ef229be1f65740c1f2c70dc00c292023337c8af605a59	1	0	\\x0000000100000000008000039e8dd6c5e10ac24523495f15062eb81d370cad8900dc95bde065c3c7c9cc5c513a7c4af1941561de2ce86f8f82a90cc8d5f3cab30dce9cfdb6dcf0c5f80eb3addc456b6943023f54b17a4db004c4838ddcfda66fdeb1caa27ffea3b0f5199dec24daf63aef5109e743d9c2f459cc9316666161c0a50470e13586694dfc12260f010001	\\x85d9009306c17e859311f42b2c1741e4511231d2d0b305ca247b064472534ca37204705db993b94f6b153adb4597bc99a7875963081c70bf3dacf57aeb883506	1660856475000000	1661461275000000	1724533275000000	1819141275000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
194	\\xcc49c2c4b3dcbaf98f9e4b9193438668dcc7f8f2e539d8fd8770ef097847695571cef10311676a0a9db58efec632cde528ac777908f070a77e369935355c8d0f	1	0	\\x000000010000000000800003b837c29ea16725011c0b11eafc35a240d9ebd4b8236300250b138f417a2368200d187fb0f746d78dc6fad7520e2c421b26e2860ef0564b1f01db1b1aa6678356d8a2c64ebaccf700e6e401d7538ddd1ba957fe127cfa463cbd03212c27e612b3636986922a95adfe825b1aa7ec4fec463e9b8f8f3f48d80e3626919359e4654f010001	\\x05ef7cd1d14c37d85517d7f4ccc10f51c7510b44445501ba8a0ee8d49f32c7f5c9696d336299a70ab3cd6231080c1b9b13689cf0808972bc7efff6eb873c4106	1691081475000000	1691686275000000	1754758275000000	1849366275000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
195	\\xce0554e1bc8bbf1a3516bfdbacfdcbbb7923bcbb2db6178e5344d3bc45e20b6156473a06dae0d7fa3606c17ba812f833490e8ac6eedb24edb62946600912f627	1	0	\\x000000010000000000800003c5200630546fd1b13e6bac17fa4ba1a0e7e51312bb03ff74244962ea0ff0e5d63cb7a2b6fbfc55ee32a2b2bd75020711a46e4ff2e6e3c984d1a26c7a4273b62fab13c004ab3ad47ceb41951ec14f9bcf8db7d65841c29b35137bff69dd833ac2f95a7abdcf62ef73bc257e7217c76517de6ce4ca4b9f2b1331063ff54c207b59010001	\\x98d32ddbfa9aef99d5c83d85fd953845a6983d2204e98ff9584ef7182fe9ecbac0887454f725d9f91419007fd10d4f5a66a3e21e5be76e68fd36ce4b6e7bda07	1678991475000000	1679596275000000	1742668275000000	1837276275000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
196	\\xcf6d74e701f1dc2268c9d17cc7a1e0865634bc8fb75c935cf284e82d6e10f7b305f9c4461f674f3795e754c43b2a74f8749964e280899408fd3c3bfa0943c033	1	0	\\x000000010000000000800003e7e75c6a2298010624eeb2e703a0d0f4fbcf41b13a0aed6dffa83e08ac805622523ae91f4af4a5e90dd672874fdd4bbf00a7cec1d940ea0ea74dcef0d2cb598669f60252479ee1752490ba14c682e72d27d263fa5780a4cfcee40de9b368958c171640c56eb3350bbb9258ae7d178319c6a98a5b12e0df2ab6a370782a4c1b19010001	\\x0ecbd3e9cd2a732047ae2572168752beb6cddb6005269691ab57173ee31142892a6469cddae45e643d6bac0c5fe4c048d4880f5a7e8f6cdf7ac09285d680ea08	1687454475000000	1688059275000000	1751131275000000	1845739275000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
197	\\xd1f1d9db2594dbf7e7f78de19c3dd3812b4c73f3a0b9a211ecdaf99452bfbf95247c70311e475ed97fcbf204b6496c41a093dc044e3016b2208f56b896319b18	1	0	\\x000000010000000000800003b73e09b1bad7982b70a17b648d606a626554eaea8a82e6f1b14f93e5b18e78acdcba41d2cefafd36c797d29877d3781010eeb1a5898be39fe03bd2b4952f2ded9bc0928756101528c1b987814636814ce030a548a76513f098565e6c8058f0d903080d9a35b1c80d725a85365d44b869e14d720359d5aff0628c6dc2a8eade89010001	\\x0743f865293515ff3fba9baa4f5346de0b92801d5c39d64378b98808aeaf9142ecea0f37e3bb9df687c956c3b0273095bfe935385cf7f8e418a9288211e3b008	1680804975000000	1681409775000000	1744481775000000	1839089775000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
198	\\xd3edf635b5f67cf29aa317ebb3e142e8b4c6e4fd2bf05088951a21f81694e81603cb0c06a8bea1a7948bb1ecc522fcc99d10d3c702f7decff89280f1b543134b	1	0	\\x000000010000000000800003ea0f9a5dc56178d2b054ef1d022c1c23fb5dcca830cab528d42e0cc34f593db167024d8b4100ae60588c9158dddaa171b94a3676b897314088018b99350dfd00c9dcd41074e38658cbc797d568b23475c54fdabeb1be4b9e24a017660b9d900d4772c460490f9f768bb4929d51c7b083f5893f1ad571e47e9b609af5f999772b010001	\\xfefd8f8f8a8d810e0e9079caf91a253c4822fb9a6868cac8d17aa4965a5a40f845576d533f87975d4a2dd8be72c6cc491469410d49406296df855352b62c6908	1677177975000000	1677782775000000	1740854775000000	1835462775000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
199	\\xd36180657f6d533fe163f2c7e34e5a5c986a4e78f17d9e677326f0afc198c64174a81b3be65818bcbf9576d0794971675eee25abd7736ea23dfa72d275f0b46b	1	0	\\x000000010000000000800003e3422bee3cb04afcd466e8f0c05eaac7ab6a6908ebca57655d0bedc9b1e6cf33fbb72ac0b10f00864f1a5bc25de438ed6bdf943b179b0c50c3a25f30893b4d72d5ae630f82c6598cc72be19bb8cd8b41d57433b538e870679d0ac53b1df12e6462d7c9b514c614a74b3489ff87e5cc536c66faad9d46733c8deece9fc18d5b15010001	\\x251ef5161a8113af6902600d17aac8771afac019c20ccafd35c45b449dfdd5307cb9bf590e1b1bcf56282a2abb37383f830df20021192a9dcff4d83827575102	1669923975000000	1670528775000000	1733600775000000	1828208775000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
200	\\xd425ca94823a46be557ed79cecc57e9c6f386422f292dd3d46ceab5a52b32aa1074d516cb51113d7ab6164cf995186081a4d31ca8b997461a29be744069c86ae	1	0	\\x0000000100000000008000039d482a8d4e2564dcf75e88f15b2325385c52a48aa7f8ddbafb4a8bd71d1333c5ed3f662cb40ab58db46beaa2f8b37cc29aced808cf10310811ddc5ee602f77055ac8a6a73c85d91c0ba4b7b6e5e1ff66e51db5ddfd9c76b7d730127f5f3f6ca9fb1f0165c4028385ffbbfe7e577e3422a396b86b183c0b0805728b2b23118375010001	\\x4c8566fb5369ab39950d6cb3c076467972a248aeb764477472b106af3404faeabe61b2ae0616752eba63da37f760f2ae76e8eab580b513b4bb116df3f9f3d404	1665087975000000	1665692775000000	1728764775000000	1823372775000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
201	\\xd529fd5002c25b9463df39942c783d4dcf4ab6b90a1cb4dd7b68c5b8ee41701e8bb6d4ebe2fba5d6a0bdc64820f026ea434eedea14d75ff04abcf33b7cab6cd6	1	0	\\x000000010000000000800003b7635733fbd9384f0f319ce87792c4c8efaf0cfb2507088b35c364ea3feaa925671e5051b162e300c184047235cf287c6c392980b25e096cd822a99af65bbd406608bc0a44d74a6bf6d1c2d199bba5ffb83e188107b0ae14db0e3ece62a657d03b2a81da52c1d13af63cad19c66ba69a93107d13c652e9fb5b074551563ff2af010001	\\x23c012c69f49031deecb8cbec2c1b3f6dbfedc389ac480b18dbe80719193d7fd4ee718ae262c2807f3725c88b54423a21b63e248c7931e410f5095a21a821308	1678991475000000	1679596275000000	1742668275000000	1837276275000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
202	\\xd5dd933da98545585fe958b0fcf9a5e83403a977b3b22789ea28a3dd6d2d0a76d0e2899bfacb4b07427eea933ea7cd9cbb5075f44b79579952d68f9996332152	1	0	\\x000000010000000000800003af6f488c648d9eaca718128ed5799191543d9884bf20dc3b5218e3aa58b735b5c7de9fd50ce837bb8a7db3790b2840acbf4728f4fdf419369e36dab32e04379743f5665116814f3aa8df4c6c18b120b92fa89a60455c3106a6870da5ee9cda26c4f36e79c587ad7ffbee44d641ef790fe041535a058fad92c07b0e37acebddef010001	\\x8a45f03a8cb6446b71ba660acdc29870a2b10253639dd87bc6e6b5b8228044a4a3b697269b433543ce44e9a69d44ac8ace1f85470f0764a0acc7713fed449c0c	1672341975000000	1672946775000000	1736018775000000	1830626775000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
203	\\xd65d3772f9dd8a03a8f01dd3b5fa2f0311a0e916f8aeec0e6bd55541dbe723b41d548c5b9f73e25366ea90e282a6ff4a5190d7715a0e87c576d035d8a9655c47	1	0	\\x000000010000000000800003c3ab89fb66f73cf7a8b14d868a0f97912294fce30a66628fe28fce0424aeb41c780f26fcf432be002972d5f223a3693def319a9f2e08f6a4bedcdcfb2d3db7fbabe561bfd23332f377b51fd62cb8080ed7a9a828da63d94fe8ad517b570f8ae331e2f75bdcce8ec331dafbc6c54bacb11c513d4b8e6bdcc08981769ef2151329010001	\\x9f430ea245bdeac3eb05dfae862986075aa76b016042783250038753def300eba3da1d807c85025639861f8d4fb49952947e989a672b8358471c191e9c8e1c00	1669923975000000	1670528775000000	1733600775000000	1828208775000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
204	\\xda29ca9c458b4f8e79dd6972adea9fdd481f79cf7e6f9aaf8c94f7ea1a9e9a365a27f8fc274c26b366bae196caac979ec761827abb73476b05f8a5eed0c59ebf	1	0	\\x000000010000000000800003c227aa1f8f2e53963521994cf8de0746ea42e353513de261308b96ae698ecbceab6c362f5bfb5ecb478076c6a13cb09013e0f5d6a1190ab24dfb44187bba9469a28d372f15f84518cff9ebd471fa9c0c824be93e60e6935e9af12e68c2ecd0663fc1bf4d4640398ee87de4368da4b034c8ed357bafa8c26cb40b0bdbc73b64d1010001	\\xfaf37129cbc56d696a118560e66f5528a1f5acb2739d21606f9aecadb62f8759e01cc772a44bf8497f04dac877c76cff6e18f14882a31bf39e8729bf98ac0208	1691081475000000	1691686275000000	1754758275000000	1849366275000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
205	\\xdbad77f4c5f59c608025e7faba6f5ccecb20860b19caa98a0e5fafd039eef26f9117cf533e73e65fcdca091dafe01727de32b1d542bedf1f80432bef2c9780ff	1	0	\\x000000010000000000800003b7a014c22fdfef4b1b62511e6f8f17c2f2f272b05963d3a72b39e5c3c4bcd4356540d8406110e1332ae6e99c3cfeaebc8efce5814d3bcce914070567ab40a0e982133edea31add6a196bc04fb41183b21432b4603aa50857885b5cba0c61b77e69f451b3f63d4bd2d34f4b4d18af613e1fc227a8badaa0a915cbc1e7357534e9010001	\\x835d00667bce24022032876a5f6bb0ed01d010cd2d3e06eedb3fdc2cd13b48cf7746e5ceb370f6d81022accea4fefe0458c68e0b3a2b7f22a52e03555b1f000e	1679595975000000	1680200775000000	1743272775000000	1837880775000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
206	\\xdb61ac30d718a79c92074b96476568157a1b4c23bf52179f9b1a06afc639020a9a60d809738a382c2953b5f238dbc12bf4fa5b775d9d865a20015adc11ccbc0d	1	0	\\x000000010000000000800003bbb2950edca6d89b4a0eed89d3a5de6e77abe2d9e8e1c30b3382fdb279b6a76dd7ca8e5fb6937738f67a30ce38f285aacffba4cb7037280696a45b2890832feaaff6cbf2fd9c99b96a917478cf65b7473388937c78ece61f411adfdc852c1b24b779f54a41a219da4c5f7d0a07ca3d259cbd3f0426ea708a4ed484fd6bf808dd010001	\\xe9512b8c6dedb26f39321601b99aec5f2e628141d3ba98a430cd2ed36e0325b3eb0fd5879669bde9db2df94cecb96b2a37885c3d08f4265917ff8804df253a0b	1678386975000000	1678991775000000	1742063775000000	1836671775000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
207	\\xdced92c625661c1f19a2a59ceb8fd3d74115c45068e55431391a53d1ad9a23added035454a15a213d52b9276a623c15b313445b9446bac36899203a21c4d6a2a	1	0	\\x000000010000000000800003cbf62fae5ca390ea2c5e36437ba07a7d233b65ed982305a358ce18d68755964d8d87740e54149a5633a9304baabee893ecde70adae6085c09f8b51b67d3e753a1c094fdbb91a435345c9ffb8fc98abd128ad4ab999c8892fb6c99e9fef529e9359a1b20208d53a2f6534b6ebeaf1cb1a6d1d853e7779175e24358eace559b5a5010001	\\x7a41bc8d3838e230a323c2c210062b414785b9e607036ef54a2072e34f5e342cbee7ca5194a05e2e1378b12e3006cf867ce412604a55a211c6350230214ab008	1672946475000000	1673551275000000	1736623275000000	1831231275000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
208	\\xe205ce2659eeba06e49891faf14b8bfcc0915dd7d359a75d05fe4e944acec761a480ff34e9a9947ecff44b57fb1e02a4979337cff141aafae20c5e061426f03c	1	0	\\x000000010000000000800003c3e02d466ceb86986e0edb63f4e4e7626eae6bea6e2b44931b4c697e993697e1ab2dc3d1546091ca9b02fa31cc6049c8a8f11d544ca821025b7985d81acb67449a83e043f9da2482c9bc180c8234766d386e7da822a1c481319a86a53005913e6b82365e7dd197e4ed787a6cce250359a5698bd8bd6c953f261fd2c85f694e55010001	\\x33cdc6bced935f3f81d7d82428a2c1601cd02c67fa1ea2b3f950fed5cd0761614f67d364a1a550dacde46382d3b22b8080da3f1c6a09c1b21832f93dcc81700e	1689267975000000	1689872775000000	1752944775000000	1847552775000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
209	\\xe231b6566d9df511574bd71e1a0fab7d91e3f8a7bed003c43b9df4dab335ea07375650f5ac3c50c792631df146ef14c8fdee62209f6c89085583bfac254c4159	1	0	\\x000000010000000000800003f77939a2c37c1b17f36c5ec20199859892021249659c39f3c81d0fdf9d7e7830dd57e83d6c14bdab441a0e349fd03ca4081c1f14642e18bae17aed7f6118ba877d9b11378d604eced24b4c28c630886d85f46b0031a3850f1671dbaf46f834010f8ad88836747986de9455592a4e8b44ef1b82667868cd9d23c15bfeaf773fdf010001	\\xc21056d3060144c60e7d177dd1c8d38008961867779d4a67c51edb32f6f722800231f4fd7ed5eb4f04f621ea264a13af899a24816bdd3f74dd93acae3062a805	1683827475000000	1684432275000000	1747504275000000	1842112275000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
210	\\xe605bba963e355ae70a36b6fa8f200449be4f35cadf7418f90ad139460ba0e20e381d053de3d1c699f2807f3f0ff7375d7bd8654ad8bdc86554627f29da91bd3	1	0	\\x000000010000000000800003ca453c8d8fd235a66a5065afc979765d7e70f2782c09cfc0c287241f917cd81a5ec30f9070313c496bcefe6c5e16f719d38853aaad936e3986aab2eb4e66e24888dbfb886cff9cf4bc3e6ab770e077651f896330bad909c275ce2338f85605d9b1f176154b4b5b748fbc72d9cf2c1daa096f0b753da2f232149d00bf4b250d7d010001	\\xaf3a2d60b372ece17aa0f83614997afe1f8081cfcf543aa53cb5535d3c11b83da6788b41440cd6c3d64735bcfec0b7da5279d4eebc3411f245af7cdf8d028d00	1673550975000000	1674155775000000	1737227775000000	1831835775000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
211	\\xe72da500b2f51a4f5b1f6dd720cc772e58bd5df3714874a0f699d3866ae751da5d6040a4c9bf3bcae886793af17f06c706c7356988bc1c7497c50a17dee38ec3	1	0	\\x000000010000000000800003c47b1f16c56bf34111caa02cf652a3e64d99768249dbdccc058e74d2642448973bc81b96b6c3b358c821088fb5174501b72d3ed7c9541fde1072a4e5413ced58e03a9bdc9371af4c1d031389477ef17631b69aebcae2fed46c8249e02306b9189e1a6c62f9a5c70ddb21da1976f90d3b06a944557edf284a809c0f1b0c8a4bdf010001	\\x73a39d62b6cae5ec97def25d88a567b2a5d388fbf83fd0dfef1806a812d6640ab1b0723f81edc6446c476b1c1330deff04424cea9297370c7c36a95c0c69fb01	1677782475000000	1678387275000000	1741459275000000	1836067275000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
212	\\xe9b57422f08a042f45d756d09adcdd7fef9843799623903cf2d5d6e42f3de7aa2d1772ca7b044aa837647b04b8f4fd664f925a460689578d74a8a7604aadce62	1	0	\\x000000010000000000800003ec647710d4bdc7c22cbab4b6427b7242c322c039b48ba17ef17db1dd3924f5e612098cd4dfcb2baf6b37532ba337d64e5437a5b7290c12c81c4b0c173a28fc368539e97899b443025d9c728867dea25f6528bed97afbbd9670df33b4aebf0da9efacf0e1e8765e9f229221ca5f8fe1de486f26fdc65528920272b0037c8fb839010001	\\x2a83f53ad4290fe29d4c82e706bf611b6db522a8adb46cd16a5589ff7cb7d8df8ab9ca048faf6fcfab8bd6f0c7b29a6ef28607fc3d0bb0fb9f77aae010ddf205	1678386975000000	1678991775000000	1742063775000000	1836671775000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
213	\\xe9019eeab6ab2bdc0a739e4db6e445f95aa3c1749f87bd00ff10447d763b252dff2f6626fe713b7d33301c4176ad8684f06be89eb2feca4c7825782504960631	1	0	\\x000000010000000000800003bedae7c1459f0159e1ceb9fca409b2366ddbeb80cbe16dab4466246084477f60c4a7243f2b3e4cf507851f3312f01e8d2515595562bbf7c350bb52d57f9aec9183934dd0c05811375deea231e35ade789927c625f577748845dfbc96dc127acd9509af40ee2d84510ab75349cd858653c8663c6b4b083cdb2111e6cb0b726b13010001	\\xee6efe2a362f2396ec73366fda0c82a4df9de277ee913c151c97162598ba7575067c95b53c9e46137a0d83ddbf3b85b4eb967f77b4c003242177d05d0cbf7d08	1691685975000000	1692290775000000	1755362775000000	1849970775000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
214	\\xe92d0de47cf0ee74e582d74ec71d7bbb42e7f4e942daa12eab4532dbf96a356aa0ba56ab9a2afda86163070eec7d2817f017c742cc4e5f4b3cb363de2121991d	1	0	\\x000000010000000000800003ef23d7dce7706096d5b3fc287ac488f1f3e5c6ee047d7447b56a70ec29cfa9c73bdef287c31a2273bdeae8e8ee7c1b386f983f516a82543ec0be14c5dc7a76c8cff1a7c9c839ea803d001c9c22df6937cfb86e501c5f1417e1526886389e15265c0851546640f86f51048dee8acfb804045b4b1ee14986e1b2eaa1cb54569175010001	\\xe6efc44ec0021f56698ca1b028fb9a2b570bbf5ee5f6ae522bd4f9a32cb5ca8f22eeacc23ee6268c9d04446afcb1233d8ca87fabb9641930368b2322d23eea04	1686849975000000	1687454775000000	1750526775000000	1845134775000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
215	\\xed81a0b5c66129212504ce6692fed3850f00f2d9d11f7bc77e1c98d0281b1488470678c92b1aa5418157cb263dcbb8148c0e6e013e6f39597bb86347700ee7ca	1	0	\\x000000010000000000800003b5cd5a1216b7a481214397f2a9e656b6e11a98df6f5ea80e6e74af76211c57e41f0b47aae8799f8b224a6d59f2398e7c67c0f86c0b328dfb3888efc9505781d6c59c68d147ce7aaf23d270ba65673b2f302e7ebfce517524cb9ee3a8fbe9b3c8fa5e9a9ae8f3db53416783fb3d21c4fa69db4b35d6c479f605dab0656d792a49010001	\\x9c1f9e08014c8080c22055aeef5bae8b1d38db069bd96971745d9b1b9b85dcb635a96be18165c2e00529750245d0ace6388d47929542568d2981a6e3b0337c03	1680804975000000	1681409775000000	1744481775000000	1839089775000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
216	\\xed490291277f4f63c1948ad1cc5b1da351f6d6fa20f4acb8eca8932b3e73cd35856900ab3221b5c071d6c32ab34db0a51086158f3a29af9d1e9c19b322192dc4	1	0	\\x0000000100000000008000039a7621a3de84da6fec63741300157ed84f0368d2c244efb0eec20de231ce26783004008171aaa21273037d52095271c2257297c208d67447d56e36af24da36447f42221181af234cdd08a2869ab9ce77614f508f0f93220ab4a466470d697037561a8b9ef40edc0c47e1cada1c0dce3c8bf7cb81b8cdc56cc2b55448830f0d09010001	\\x3ccfa9fa660d6fd596cb78009890ff78727c0d3d9137410bd499fe1c19d7c853d3d2e48cd7234e1e6290809da1afaed1dd55394edd62a70c6b622663a02df301	1665692475000000	1666297275000000	1729369275000000	1823977275000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
217	\\xee45aba5d0d531ed929c61b60a1f0a4cd8ac7b0ac1df741b95fc1765765eb317d47e48c5580385ba7cdbfaa5948fbefe1b443ed31d8d08a61a05d0b244315364	1	0	\\x000000010000000000800003d42db3d4a5484813cbc15508a3ab9147930fcdbc773ddddc784be029cc0692bce337a4a1b25752613c5ed6c2565860f2d12d235b6bdf923ec6bed5ab70ec3de03cde559a17af8a7155e29706420f48eabb8a4fc81210ea1746acbd4513ab6bac7b2947a800da2538d17c69d053464cbb0bf49e08c50e8c47a367fddce178df9f010001	\\xba2f9d01be84d83fe8e49b3f33bf9c7078d94058883f41214de766ac3c5ac8e47c209feb778cfad720cfdd7e3509078e7284fc91cdfaffb63b07cbe2b946e30b	1686849975000000	1687454775000000	1750526775000000	1845134775000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
218	\\xef89413463ecb16fae8e9564c5e6860535215f4ee5f350064a08d33bb963b5a409b02ea76924eb5ac794e92e3eb9fe7695349588e234c73e017d1a23c43821cc	1	0	\\x000000010000000000800003c5645221829cbd6d39959c9b0aa06b7d30f939189e5cd7320db2550243a43fce102acdf9da39f458a39cde244cd5d65ce776cb9490f53153dd0ab3be0b759ece7d25a4e909947e262da727732c2cc875d16f4ef8f4626e72916111f26299066fe20fd09d575b3b9ba8199e5f1593d602f72b2b96a6442ec67546f093da5ba7c9010001	\\xf590a8265ef2baa333e42e0a62641cdb02449e532811cecbb348ef91efd7e2fa888ee0203d73e66b37aea10e42be444e3c0d9ba8f5ecae5436e5eaaa5044d90a	1687454475000000	1688059275000000	1751131275000000	1845739275000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
219	\\xf1c5dc00539250a54d01e1d5d3162f7be8f5ba1c0229e2f8589e147e53fc367eb619f7f07daa893b00796e94fad83d88188c6eac2baed096f03a292de8dacef3	1	0	\\x000000010000000000800003a2b510a5756d7da2c191f26da534c3f0c1fa7dcdf03387bc59a73faeef51aa2e37f1003a3bdf560def333764c60dff1589860f0be5c76a944484b155cb083239c3fbd104fdd061436b8b20d393648a4c6556ab8b36c30ec1f6ce33a2fed243795d58a3536c5ef6013555a86ab6398bab06ae9c1d8d5d2173cc7740aef40d5d75010001	\\xcae34f0d1c7e47839ea37075722b1f2871d3936d113e43b449686548c978af8a2acac7386a721888fceecc9c67c0ae4430bc862c05ba6015200c576b552cf209	1665692475000000	1666297275000000	1729369275000000	1823977275000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
220	\\xf275adfdf9cfd46a1ae853bf38f2ebd9fd90b0240aeb1ea8702e2f7d070858923648e66fc2bf51bf3fd0be42ffd0a92f432cf2141a6d5cff02adc9118cc7d919	1	0	\\x000000010000000000800003c57bfe8eb5016a818a95dd3600dcc366f9e21d78ce59bf3105c108577ee2d3e991028f70b02d6d2adc4a237694e961f9e57e4e4dafa3f0390ebecde665061b4819a4295c1ccf785402bb5936b7418a3b04f1c8f9f59c7389db01556f1563d9904e9d4d8d17c7231d1fccecd532ba864a0c16d6be32f5175b6987a8774b45df35010001	\\x8b158b7b131c00b4d1a8e233c7fb1ed4180c3e2d2ea7cbecb2e6ae3be1200398e406dba75901fa25e1787002c5aea17c78b7810448eaac97e7c2e276d5d3e70a	1688058975000000	1688663775000000	1751735775000000	1846343775000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
221	\\xf3bdb4e2a5ceb352c3be09768ccccb22fa1fa74ebbf274d7a918273232191485d2ba4b8537cd53653bd8cac89b445c03ce349cc9344111a9611c9f214f79d78b	1	0	\\x000000010000000000800003e0b6b76e0114b7c228522f2183da6e26a813bce487bfd119e8691e0a0500a02f71008836751f865eeef0130f212eb6265718ee03575b3f856a0f5c80f6caf0d15dd3be6b90e61df5aacc630e5761c4c94127d25633ebf815181e7056c66dabec5d6f90cf4d5063d12c2fb73da1c984c3dc2b7ae766c2eb65de5139cda8b10f39010001	\\xa988f064764cf277329b98c5c1cb56c320f9501a7a6fc851e0d721a281ead879da9d069ed912728bbe1279a365bf1008c198aedeb21baef116d903fb92165b07	1663878975000000	1664483775000000	1727555775000000	1822163775000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
222	\\xf545da086e6fb8e733221880fc7dcd8fc26ed953e598995097185fc512a98b3d601fe571927d78d6902ca14194b39485dc416937cead2f3ac8a03bf05f005702	1	0	\\x000000010000000000800003bbc97d7b7daab06c34bbfe698033b0c7583498b6fb37252e852996ccf6800abca89af80d5700c5bde54731088645c3aed07ec3dbca806f0d0cb08c13fdd4d94e705782bfe466fc805a76826a9522877ffbfac7369fd25c2700cc56e43fc551909e94b272f78f7156cb2f24b89925eef09bd68e5f3c85287f841467a575150e2b010001	\\xe6353c6d7e08e77f23cc7007a7447ccc4abbfd17894aa9c00fe60ddd9af99a58f73c74bcf8e5ba4aaab25060fc3bfa9358fb7248cf0aa7d50a8fb2d5fe120108	1686849975000000	1687454775000000	1750526775000000	1845134775000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
223	\\xf74dc2e8b8264f703ba3b518b0acbc6b0f037fb7748898a62b4d1cee345b71b518d78953b5e20c2cdc44fe88724ee635748f0b1ac3df076df9d62895e1152f26	1	0	\\x000000010000000000800003c24978b21c8738e0e9ccd5870bfe19d6240d7ad83ac355ca2d8d9ba41bae721267bc0d74d51a1c973536b7c1e30b9c6cb7c680a0e0a136944fd191e3ec38062529692981bafa6e37299cfda65b3c6d87a7a942a90dac8e836fcc28bfd9140dfe77519ced2a32f555c5ef304e75edf83d9e5615151859aa694a7ced966dc8cc47010001	\\x5f087f4d029a340ef1512716fb3f600fe345a2ab2cfdc5c72df325f2b95451e08f5f1df8b786534fff9992fdc49134dc8fbf004440ddc28e1e586cca9e418c0e	1685640975000000	1686245775000000	1749317775000000	1843925775000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
224	\\xfd9113ccff9fabe206d1971f8881eb8d84d2fb24213c9f7c156bc374fa42b106b4fff12c586e4f54e980a157ef815e44b6587f6fe62d4d068d96d906a4eafc9f	1	0	\\x000000010000000000800003ae6bf48d8a2fa405a7218181babaa4fc67c596cb7285b84854d5e50ce706cbeedc3b1348b1749b47b897f454f0cfd202fbcbb1c6957e73cee6acbbfc4317ca2879bc9c9eb07c12a37b0066759a0a5d542b00cefa07f7235854e00b7a38c67e762149a22bc70963c2c4f23ff948f0d23a1559c110c289328700532ee07d327c63010001	\\xe68d2344372a8137ceeaa55e5e454773fe790639ab475b97ac6f0c1b3a9b312ad66c38ef0ab7917857157b0d7fca76af3c531ea0004414a533b586d20cba380c	1691081475000000	1691686275000000	1754758275000000	1849366275000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
225	\\x01e6540c89a6b820b6566e6e25228219241b87cff7f46707e594fcc2965a4f354aec2455aaf019b1dc8e96cbb8b5370d780ceb4b499215cce887c638d16f198c	1	0	\\x000000010000000000800003af2631cf9a9ea277cc5b58896580614de06cfd37561a2e75d791409c6c4f3713a0bd7be47a3ea743a6e214372b48477dbb82dc374066cdb41e2ac022431b0e060bcd780e0d5930bdb3c423fe0fd383f44c42622f0bbe7e76f200f88272971c155a3df1cec44741e3d7642e63631692174fa3f39404818ff5c5b6f55bb4ecd11d010001	\\x3527561787fba797cc65fb8ed64bdb7b9af020afd94b1a0a97d03b4522f7c7b625f712b07880b253c2d23fc9f74075582dcd7833071f9457260e823a7642ff05	1680804975000000	1681409775000000	1744481775000000	1839089775000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
226	\\x0622f09c31dc2025280b91584c31af0804abd6d6f63b484a48e4d9c211803f29009c8eb9fc73c822078ec217839fb4b94cbea0e07856d60de00c1e28f903d365	1	0	\\x000000010000000000800003bf41e5155c1fa1ddcf9c260cf2223d42d8558f0a56947a48bb6b7f50ee35a93b15b749ff59ac4051bedff0b80fc843fd49316fddec58b0ef6b0cf6b66cd192d4164854b46c3f12e5bac17167c1068f4b749b63b4fe92abfd2aa21db776d42e0abac8a31e5641227b708bef839752879047545006d95faecf90ba1d9a40601d67010001	\\x7ab29aa66c4871674f5ff2846d485c21be6fec1ee1cafd2a4c85c3094d126ea0eae565f5b5b9cb9ce286a1d62a455238f6c2ce063107970d1a700ecc8489e00c	1673550975000000	1674155775000000	1737227775000000	1831835775000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
227	\\x061e3858b536f183577cf1b0c88e56e21d54ea0072c772f0a27996b3793a3eac5784aba5568aab13d3f57396f76561ba44a2bd297ae005f317b06aa99521362f	1	0	\\x000000010000000000800003d6b7231db5e8f771a3a5e8b069c2f15102f4786f202d1db2b22451bb1b39741b2e41ce3e23b7ed4f5b2b3412dd7f14d6e048e24aeddd0141759e41621fe9c15df22dbff12b47199f0e28821441b601f4b5daf7c071fd220a2ae3cd1dc888f0284d6e403fe417c32d68d5c20d205d36c82575687f3afad9ce55fbe18c6e6238cf010001	\\x2ba4b3a6dd995fd82375d450d03b0ef33910346d62d4a646f5fb5ea91cc80b5c73d80388192bb657ba2c500138d73d4d5812dc0207f694233e079081c64d6b0f	1661460975000000	1662065775000000	1725137775000000	1819745775000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
228	\\x087a574336c35fb1cd927316cc023117b559729cec02b64cbe9201c6da1b7db2e1b2186c77bcffcea2758303802e25aa81de417cd6595cbe020df2e7d4ec0fa4	1	0	\\x000000010000000000800003991e7599be5771137bc7b58e0dbb88617b339c17f29248e6dc3ae723aef0b947775723d5f2b8b46b19538af3d9e0b7b3556e89a69b5bb8f158e02fa475381fbae59cbd0671143ac8ea1ec732bbe868728fa1e6add5ce226f2df92b6cb2d7941ed2c1b2defa87e5428854e495b367af59f21a85052c7a3cf4f27874de07acb9a1010001	\\xaf9857e169894d90eae64d4d3432cfc0fd7cb4d7ffb86a21a304b4183399870e00a4410a47ba3146ba5f10333e05bac420205d953a0623ce7187e53bf03a4205	1670528475000000	1671133275000000	1734205275000000	1828813275000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
229	\\x0f62d55a33d778539a491c21a6a371c8156d26c6df1a739248b8e0b6f54236953b4ce0156f7d6747b7ac77095264ae0f9e58f41f71d44870b7ea52e136fa7cc2	1	0	\\x000000010000000000800003a86d78eb92550df9ddd201e747faabc5e9c609dccdd73b9fb5b131240eb49d76505f5465bf05806de5f26755d0a812507aafcb44a5e840c453f02da3d287b0f6b5c75ea33a0f4ca68bfe9df18f02cbe6791fa4439f064a8f42ba733d6282c35020c19443fc243a141131f83db8b65e45bba24287e0f4a366705ecb37ad78f52b010001	\\x9b232a830dacf1dd074aa123efa65a741270dddd7018f2a0dbc60f4309e90588bd9cc706c6d88780278253e415d8efa7c1e51be9a68f82076e386baff64c4e03	1676573475000000	1677178275000000	1740250275000000	1834858275000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
230	\\x101e97e0e36ac01f274587098d2cf9928e18d07d5b8c9020ab022f016cfcae7a9dd11bd8e4b1b36c5455e8640b91f114c70a7813b948194d939b8cc97e690765	1	0	\\x000000010000000000800003be46d66f9ab0531f552d94007e51579e2e24c84620addf6805860641c984b20f31b0cd7f26f99bbda9a494a7f0c1a73bd9b5a36bcaa1aed1961f00fa5fcca26da8fa062b95048118c6e163d3d478f21170f0092100078829c750c5a6ee85084a5658ea0f30fe295c485bc1f3d002a3993132fa59acea8d2faa7f69b6a42248e1010001	\\xe69131a12cff89ed87180ba815833e8056954de969d6f23594ba2bd9c127c3afa90a00644b8365eba83efa3db29317cc39eb28ecf4ec73f12d26951be6bd5b0e	1677782475000000	1678387275000000	1741459275000000	1836067275000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
231	\\x107679a22c74be2f7b147858819bdac4b46a7f7b88807ea3753fabb1944812ef532d3060fee61256af5a2747ad74ed580b2e0ef0df53265aad61fd9f8c3626a0	1	0	\\x000000010000000000800003b0c5874369bdf4eedafcf023d24de0d4f8eb5350511131f62c47b5a8bb15c27e6896dfc705d1acfcf2371d0e0974a1e2dec840bac9fe498c4ec0e0d524495e46188be40981142ad25b03fdc739859ecc844a7d3d8fcaed94fde9929e8e0c86f1ad24b855176bf9724a054e0100f0ff291704b1b8355cfade3711365c1d209233010001	\\x989685f38aa221645b8767236d42b04c84676a823c9ab9f1e76e4fb3dc8ecdffaf16cc0c233e09442aaf21fc509aca330f3f687a83bdb4dc96b4964f8be90f05	1665087975000000	1665692775000000	1728764775000000	1823372775000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
232	\\x11fe155da9459cdeab5a0a53b897dd2d3773463edb9802e42f7f2dd07b8d11d4a8747d9756b5a9202913595391eb32a7122e7e904544e8d83ef0f407ce883abe	1	0	\\x000000010000000000800003a804d3c02ebe6a7eb5ea60f92505edc8e4f3e1978631327625cc4c27c20edf631e973e4018b2000ce00b1901a39e14aafc5aee4bfcc4a459be1efcf94f4f67c410b3c6af430bc77c290c65fd2bf3066e8c9e52ebafc459478ac5f9bfe4479e1eb4e4546e8eae8d6e31aa0e86368d411a42cc74c5a9202f68ec20b76b519fbc59010001	\\x4db7a7123311f77c162a543b678d57a0d9ba064a4862a30cfc87bfaff532682137361fd63e269e6ff990186c9dc955c9138e59acc979a97075e425bff85c7503	1681409475000000	1682014275000000	1745086275000000	1839694275000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
233	\\x1256782b5ef077e0b1ae3c76e17b1ed4fcfb32095e688f014d0f1f1e7250ecf8c56d22f9c4116e9cae40e8e0341c45db996fc97d351e91c48e2e6f93f7d0fc74	1	0	\\x000000010000000000800003e65bf52969a02c665a0ff86a4655098d1c601bbce97750bad082aad704bb9fd0e1a755f025418a88f78bf865e957bc8fff5526eeb197c99f56ad047a8932b085ecc5423a7c85c4d0eeede79e4d523cbca8e5d1a44489f73d5e44a54b7ed7723ae1a99c9629f4a1840162084ae6cdd73ea0796ab2943b6daf0d22e99c2eba619f010001	\\x344294244c77a45cf716c8a74c327fc14c2f3358c435897154dea5da02135f079ea29b5382e25be3f803f09c4c11f2af765b3b6dd464081a8f6fd642f146590a	1670528475000000	1671133275000000	1734205275000000	1828813275000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
234	\\x14321558f79d2db56223884f787e827a77f4d998a2f81bbf5c7f38309c62f5435c21e30406da4ac608278ac53da9aa9d7900d4ab5dcd6ea37451e5621bf101e6	1	0	\\x000000010000000000800003db7793d260286cc70ac9f5927eef043477bc2fcf804e28b1943b564976c6b6c471fb1f64fdb77dffb3e2c7f9afe05c9dd131c54dd8432891523e4f57ed6f0ab8547bbaee68fa28780c42195635e3a329b18d3fcc1d1d6361178ba7443f336f8497c679d4c7a573478293f8c16ebcd62ac4fdbef0b49bff1e0a08ec9a35a9f3e3010001	\\x37003315c5f7909f12d91016d1f473a3fd2f95ff3fabbd12791e563f465e6ce7d4a8091656ff53d476a186e9dc1cd456124809bfd7841abcbee572ae00841c0c	1683222975000000	1683827775000000	1746899775000000	1841507775000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
235	\\x149aa5d09bbfea8457c510f73d07b48dd6e00a9ad0476a21316863aaeba48cd555e2722d44dec1a92c4824f4b19b6659e140b9b3a0b59123d2244eff09fd2cc5	1	0	\\x000000010000000000800003d7409133b1aaa4d666ec686017042cbc4c6f52c096678ea544642cf8a180f4fa146e2418cae8f78f9e66a10fffe491b13df96b58f4f31b60877db8ef21047d39e9bbfa5b43f63cff330b112208dc48898984760e9771e183330d60cc45ce3ba69f97f26afaefbbb2d965e59865746c6fe46689d7714421c36307bddf67b880eb010001	\\xe4e0920a864c6b3ae1eec22ae84887d2df2783ee8d16b7b713f8730b4b7b2521990971ea36e19e6d7e2df62c58cc50157396ecce90a9bf53f213d08b4f0df80e	1678991475000000	1679596275000000	1742668275000000	1837276275000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
236	\\x15d605964f7f48966d7724bf4c2d42aa339298f411eae73055cf9db71b993b9c6fbcf825e0343b0b648c3602c5649ce87bbfdf9b66cc86e283ce71aebf852da2	1	0	\\x000000010000000000800003bc8c2996599809bf21ab35c794fe84e1e9a7415460c04b6d640297977968d209f00935bedd02cb567747e1fd8b736ede1aea73b76ff0d47f54b345d6e63ed665078c590c4e62496fed779f03e364168e9cf2ed3e7c5a55556338c69845f864e5c33184f1aa25131caa97ae6490a8425bf7667156fe3cf474c60e5b953634b7b1010001	\\xf9cda76de2264ffc00be6e9401af77c33cce1e3fc2b9f618b3087119b70d7414ae6e5dcfd20581cc8a3bf3b557657aedbf6a9fbc4a132ab6c26240724c97680f	1687454475000000	1688059275000000	1751131275000000	1845739275000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
237	\\x178a4745c0aa9e2e6a326816a47dc5fb5324e5011c09366e7e8fae575cd8fc8ea7e88c9aa0551b88e6c1bcbd71f9d72ccba0ac601c5eff988a8499eb3ec19553	1	0	\\x000000010000000000800003b0ea447f712cb221f6e5cea20c29b04f8b01afdf3b9e1ec888cfe1295448d215588022c385ee4a4be035e1318673385d319f027bb4956012416bfab45b2d88eda7209056e07b00314126cc64687f9cb69e9fe066301f0070c3c0758ddbb4f8fe150faa44f86565e8ddf537c1c056a494f7b39d31ed613707310694217b69c519010001	\\xfc4b18eab6aeb4661191223442627f2b5660a3ea37e1b56bc0d06812edbd20f8c70f58234e5793dbcd25e18831309806fd4fcbb0c078f6cfa02b1b047a47a10f	1668110475000000	1668715275000000	1731787275000000	1826395275000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
238	\\x1a5a708182e2b3be3014466dd235c52e1a98efa6e9b75df20e6f3715f3483f034c25c41769f699b9c52f2b9a1f489137e4b7289cbf32a3db9669221b8acb6f82	1	0	\\x000000010000000000800003bc84058a18ea75e71a18e11fda69f840ad6b4d739a85eddab983eab82be29389b3d0a6a1f5a6949be0bf31bcdff77202e2e1212d3c9c65f5840795a1e1611eff3d0a5bfd08c7251379420d417ff7fc0a2bd90a3589e2f58d76b8eba76377fe9989a9dfc0018b7872a4c9264f1d4b77a40cff7054512fea234f1553b71d044b6b010001	\\x3745dec54aa0a7c718e0d1edf6a7f6a0cb9dc0a09a28f5866a3a9b57a3c65e3640c21f99e52c55cab8da869aaf6c8e8463038d3ad0c1fd3c72a47af8f59ec706	1677177975000000	1677782775000000	1740854775000000	1835462775000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
239	\\x1c9a8615991a718785d785da0a3978561c5b2803d15f3fa6a3b2d70429b9f0eb76e72c28e8eb21a93cf26f323c8631653801e2ccab5736dbd1290e05c4dfdc7e	1	0	\\x000000010000000000800003a2e69436962a80ad61c7c7afef47ed45b385cf8224ea5562fb2e57945119d4b31606d115876fd950f09fb6cbdf72a376e2d03a20acaab94367b58513a9073f27174cec870f62a9d0a2fb64f3fd469be1342e41c560aeeced36d95e655573afb6f386b024a87384f035bbc0ce9489cb1e2f088d3db2618679fe16fee2380960f3010001	\\x915644179acc543dfb564ba94a9eda838d6cd96fb38747f90abced36fcef9b462c6e059ebf512ec9712f96054f5484accef9950b8000b93461cfc86236351c05	1688663475000000	1689268275000000	1752340275000000	1846948275000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
240	\\x1cc2bb00e304e144b7d19015f2a6db6aa5eb504d7bc758702163c3451358544404e2917e40a241b62c5759e0ce6db44ce2854681aa11903bab6a5f8d52648669	1	0	\\x000000010000000000800003c2c31e8e46b0af5fcd174289615a28c46134dc080e846da58441972298eabc2f3fd3b13b1ccd8ec3e47d19c8deec07fbe77446c404787fde780472c1731b617e2e36e9d18145f5265e24ded446b96a4e83ff8375d0ba8263744edac6330728280629553e03837ffdac3aa2d4dab0eb3f0035ec6f9e07a9cac63f8c5f503c3b21010001	\\xa4bfca5fd0595eb6508d31d2704f4f2cb63a33e7780ed2764993fbc673ec50f46e5c5ab3769cd88ca990ab7b22c75c1c4347d042359fab92a72386714ccfcf03	1687454475000000	1688059275000000	1751131275000000	1845739275000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
241	\\x23fea179f7c35f1a42024017090c241ed9fe77e90ff5f0396032cea4ee6cdfc1e1f5c6648fceb986ce2692bf7cc79b1465562ee19d17a32ef4ce6237129fbe68	1	0	\\x000000010000000000800003e435a95993678029c7fc6a734d680253bb1fda79bdfe34d18c2765cb1784ba6ca51e38ae26cbf0762a4f34c24365dc9429e08781f4c169b7c2b180d8dc47de2e8dd964655778b556ef58532552562a2fc134394c523cf3b996006d70322629f28bc82580b1270f6b5d0e868cdf448d72b4fbfe0d94479a2ab47b7551b22e7175010001	\\x23b67f431075acbb0d455ff9180619b606cae8eadb9fbffda6fda608ea066507cea8f507af1a40f849c06457feb816f7d9acd4e63399828b1b238c68a6d2540c	1670528475000000	1671133275000000	1734205275000000	1828813275000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
242	\\x24024a86d2ce90158e58a69649c39d421e2edb8ccbe3eac1fec6a927ca2b5e27af49c4769ae090172240aeea42232058d6d27520ec28d0c30c6e877edfcb5181	1	0	\\x000000010000000000800003c036f2a3b1cc6f8ee61aabe08c41cb48e2645cc9d2a80acbbf1b83e4153661ee058d707cd8cca120590fe285a49434b59242240bb27fcc32bbddd36c1481d53ac0fe7e47738d9dd9fe655990a091b9021dbd9d7ca865e59ae84c9bb3901b1235aa138e3e7604f88cfa911f8f2ed93fde57f726702eae48ba96ba85047487c93d010001	\\x48afea8f65eee7d43992ab482d9112e8d46f12b1e44709384aae80a1c574acb5bd34100240914c3dbb21431de67eed46b37e3e31c161ab33c7874717dd48c906	1686245475000000	1686850275000000	1749922275000000	1844530275000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
243	\\x2482360c2ac87bc0ad55c3f02adff8b7c3b84a7e6ea9551e30ce3dce9af5d0df85e20785484f5056aa028133f279f070c8c2c9c06f9cf5b8605909e1bf28fb40	1	0	\\x000000010000000000800003a5646dd8836d55663ebe42fd35b24c8c0a534802990d1d2e8b969afe8733b43234a22e4e7de7793f744aa5985aaaad976d4f4859b74bcce79cc3eae22ea7366e21ef51b4a097b55df5329a31faf17519e6d867731bfd4572037cc0d276546f42dbad3f190e440acd4eef3c66ad0834579e071391958a0c6232f4c72254523441010001	\\x449a5673c703978be2e7a14a8f05564c7e9d8f3ef271dcc21169b4b5020acb4dce7102316611b8f1f298c77f6ae2af8b5f315aa66e656b28b5900cf79f9db60e	1668714975000000	1669319775000000	1732391775000000	1826999775000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
244	\\x253e907a58bf409ee4334b1b21850c12d513a62c62d614a419ce69047a97f5acbb1d3d12dc452ac63d5e6b46a158d66e6e74e48c0b61a88d32912fbef3067629	1	0	\\x000000010000000000800003be64da69768255602b05af02df41e4b6f330f661b814fef1b970c44872268b2af2284fea2189295658edd1c07213b425a0683d5a1c489385adb7955405e387ff248e52ac382d329ffffb54c499ce3a47da5cd42048644589c61182a61be48171b503187c399967fe11e8e4def2d47926b359e6380228f4d9e45114d46f798deb010001	\\x14e49acedea322d17cf948e8621d1c68e53277695055eec3d522af5efeccbcda48aebdcf11cadd11c635b9b8932a1420670e53e68bc280dd9c8d207ec95d540f	1676573475000000	1677178275000000	1740250275000000	1834858275000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
245	\\x2a1a6503348470528ee775faf3133accf458529d1e9519614a3d7144753e5c1118e6a93d1c465ed56dc4cfa752de3c9e25a03253e960f4be4b63c10a240454bb	1	0	\\x000000010000000000800003c892ce9045740ff192d9b5520d8f57df081a316ecc083b4082d6023491431ef3de9478e6a9320d2c367c865aeb2826e83c9f4667954693257352f167e554548c28c4192f98378703a2995e82afb8d1980e4456ea86f95295aae607057ee0fd8aa1ade38b8637b1bd3d6beacc016b3345ce2c2164cc042194e4993ad68e1eebdd010001	\\x78959dd30dbf70709140890ac5357607780ace6e141fe4778ba5236afa9c448707c35a91001ec071cf33fc5771e0715bc7659902307b0b9f98a8b48a32197c08	1669923975000000	1670528775000000	1733600775000000	1828208775000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
246	\\x2a8ac3a8322b2bd628f1774f029635a00cdfe731792196c5a95a7f8d721973e0d8614771b857f80fd9ea337bf80ac1aa463ae2ae26a67c40296005b285bec7c7	1	0	\\x000000010000000000800003a7ff1a672e8df2004f15d7107f83871d8808359ce27dd7c21b6fd956944fb2335f4c3b0977b2b54595e44c37888f8fa68afcd9ae96dfff6d7e0c0cb09d8a8cece9ecab20a311bb2bddf59d2b0d5f605b3a293703579919712f2d7852e5ce26bdee5e54661cb6d07d1c719d0f60e9b236bbb8913d5d5131c5576c0737cf185b35010001	\\x14fcda147234892f10b670e35109a5bdf619943a4fe6e1dcc3f18a82b5028a32e627b4984b025342f42f53e25f0172d774bb77d901836b120b901ebeb5d3cc05	1677782475000000	1678387275000000	1741459275000000	1836067275000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
247	\\x2a827f1d5b24268b0541cfab581fc52534d723b9bb4227417d8f222fad75061d4f10b2bfb266a720da3ed7145a3d32183690e27215bdefa3aeceec04692d9fb8	1	0	\\x000000010000000000800003c8c2df630432bee80d875ac8c598bb8faed48a106359f92d11506b433c3a37a946707c6aa795a535d5e74544d22d3c8952459a369b62efc3e72b4768dcb48a7fe3657aaa2f787ee551b2b9d23a7d19e262b7bd569d2b6f22d7be077816f58ddbea05c52a3be1d0eafc87de79315b43186b632abea60fa1a86058379ab7c314d7010001	\\x7adf50b39dcab8bed1ae2dd5ea078e474111a6dcbd1af698db1c1d37d68ac21c54075a6e9221e3029d835597483dc0609d99df11311a2eb1573687034718650f	1670528475000000	1671133275000000	1734205275000000	1828813275000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
248	\\x2b8644f12ddb2574786b06cc36f4ad134fb4f019c7ce33019b020dd99ff85a0943ef9ec00951676f7717c549abb715321bf25a69d3c364c0683aaaa942974598	1	0	\\x000000010000000000800003b6745505e579efc2d95c17d9fb614a66a66e73d47819c601cab68c8d8ed7ea3816d0cdf0975b971b718c6cc78893d50b54cbdf9575d041c1e2f51f0d8ab3df4b30257b8dcd1fbcff19aba8c1462cc66020136cd5a6d9cd34ef275c623eded365d7b936244d3ca185fd0b6704e44d4482d6ef4302b2328ff2901bd2d62a24e711010001	\\xf9caab74c3cadfef26768a795822179f950ec7b6ee3fa6fb4b6b55a1fa32acbbf8dd2937c0c5a9eb102794b5cdd925d1fdb2591a7a12ab33ebfe9d92464b3409	1691081475000000	1691686275000000	1754758275000000	1849366275000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
249	\\x2c92ad1c2df8d157766e785de6007d2fe8a1f4b721449c4952b061b294f51e4ecc4d574cdd3a288da311cd6d7859653834c6da414d6204446d0d578516d12df2	1	0	\\x000000010000000000800003aefd83a508edecb5caebf06dfbf4f871edff2a0b16941a16a2f1af58cd2ee702d447fb9303fc374facbad1cf594c1edc52b218ebf3653f0c3a254f3ecfea73a61f8c37a14291fd9f90b1b5608cbe1a649084ee3e9cdd6a51ab36c8dd15984cbd0dc11e5d7071a45a235c99c863d71ab0529729418e9ce97efeea05f8797788ed010001	\\x883f09076151c8b83557602abcc3c36bc5838e744a504077c5d14e69f809d2e4aec884fac161a631af625399c4376e115f6d396498bc60c0567260665ec49500	1672946475000000	1673551275000000	1736623275000000	1831231275000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
250	\\x2f9ea516531f53c620ef0fc02e3520eae9130958b150bff3586a80cc411fdceaaed475ef76b69c70ac4c2838f378b7e5f2630905f65242098d98a388270bf76f	1	0	\\x000000010000000000800003ca9d02560288c83065c8b2760f98ef10ab07da77632808777baef315af47f13bccb70fe82251cbac784348507ac7740fc8b2ee7b594bce3478c497cff7c9895efcee11b7a5fbc481e17bb9c1fe357f372b6909e5284a9a1020815d3c5f0a4f015fc1f273caefdb3e0437ac086d135bd4d6f9f9975af83f0cf7135a1259000ba7010001	\\xaa211813b8c3d2c9163b1d7b3deb5084d3ea05641e31b496acd7af6718bb2e017e5f0f56c07d1e266226367582edbb7ec5dc39f51548ab50c9b4b0c6d0a24805	1681409475000000	1682014275000000	1745086275000000	1839694275000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
251	\\x302af7316fe581b53834348640193db4a10a716c5dc67b7d694d58c71a2c19fbc845cbd2272d070a63d256545cc66be58a3aeb61ebdee1fd43902fd3b9d74e8d	1	0	\\x000000010000000000800003c2b752aac3e782ec3b15677345eee8ffb9baa2b92f7bcd3193f1ca2c7957228f15bdb452ee8ef3e1fae7976b60b7c47fea0dddb77daddc4b13d6addb123b79b697d98fa52b738cfd6794b832acf6365ebc9ac4c57b9cadda36b8e05a528eec9879b60e33a90d8ec253ae627d28550959b2c6875158ec9bfba3dfad5e8a940cbf010001	\\x36b0d79f490454608726bde49fca168d3130320ad496267af140e60684bbb8bc2deec84606ecef515785eb12b3c51fb083407d2a2d37fdf551d89625b14c0700	1663274475000000	1663879275000000	1726951275000000	1821559275000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
252	\\x346acf2cd17c4a53a2646b698e71825ecdb8238a0904187e1caec71189e33f4de126d23bfa25321712f9279c83a9d275365e584e6f769024f3b469da129ced84	1	0	\\x000000010000000000800003bd0a19738892c6b7d4be9458133d6d8ab465b40917b3e2c2cff868acb1ced012163b9e2e9ae768dccb8cf04864b271ac0994a25752e8b612a419570c8f93c41dbbea0843ecc67b8bd4333e3f7008f3fe2f384fe10613f781d032bdab9ad89ee47314b3ae2cd65b58ba22e6a42303268c97ea24d1613f0f168d1889bfba1388db010001	\\xcb5336dc59576b1156dae8f7ea7e53f4c06479323ad6e385a3cd632625be6897bfa58316c147f98580c74b4d086b1767e51cb3969fa126aed5c2290bdcb34a00	1680200475000000	1680805275000000	1743877275000000	1838485275000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
253	\\x34de9c5244262c3fb8565eb2200ac21cd9e03dfe7310708e0b1bae21cf250588bdaca884af4282d3f67d53df5704b6e7e94bb95a5e148d5e6a97639572093f0e	1	0	\\x000000010000000000800003a3b7b495b859c37d7e6e29bd41bd4a84513ab8f22791501d9ce4f8d18a6876efdbdca4a32dc2b8628c945624ea7dcbf47821ad209c113c1479baca9141e7a3f3db7c120b20665c06c10b78d93f06cd532aec6a0699e5a5b8d06174f9b4f7b4cf900932fc843a182c29567c34548779dc360ac96560b12e2dcb6105c3536841bf010001	\\xac4b940b371e9d0827fc063867a5bd8923a1c124a5ce1782230d6cf283ae145178b4de58915808cfad6070c30111dfdd84a008081dc2662fbc9063972d86e007	1683222975000000	1683827775000000	1746899775000000	1841507775000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
254	\\x3616bb6d3a25461e4227f75605d39896e8a80d22a87d286b0bccacad0757053cd86ccaf7c4516fc2edbe6f8c758eb15a5871b1a7952b9594098b2dbf2e13db01	1	0	\\x000000010000000000800003acad00e7c700733a8df847559ca1e1080b6466d58f01069775ab0db9bbb7f5b1f9c7bfcdee90a1d8a1669d94d2dac18dc0a19674327d4050046a970b81bf7ca0d275c89b114a1fb6db7fa263336457b96382b5e8f95d8d5a3f65b51a3346cdac8c2829cd0482bc65250cbbc94d90dc56879635b7a634dbaa4f2cd566c0696f05010001	\\x4a4a00f29a8afe5baa64262b70eb26bfcfeb7344a72110587ea5cd1264cf72850e84e7f46da4e11754e269e9d5a00eff9a4dbee42bfb9024d215fcea256a5d06	1672946475000000	1673551275000000	1736623275000000	1831231275000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
255	\\x368eac26eb191c5ec906a2de905a0fb4f9a3c56560900b3e78181c782d1178dde54fd03100a1251a9da451ee1499a6d9940b24766a05256fdd676a7963f25af1	1	0	\\x000000010000000000800003b62502b4c76b68b91c3d3072c7d5847e7a3cd835afc09c5f6089b855b5da817763d069c5f830ac1f3ed9277373a315831590a261bd271f7f1a6a9757fc7ac31d548f5601ba406a88cf9522476b9a8f1eaba9494ec82f6f94da46b3818a938a074fc38cd9d1e02feba509d70f9a96a62f973e5aee9c5f6c2f8677e0125ddb47c9010001	\\x5cc02d41e24cf06da730d4173df2e113ea89e1f423aa4ae6a3954ae01e2c38a75296610f57c075109e3b6841243464f91d2f4e21969d21655b5a4f9093f73b09	1662669975000000	1663274775000000	1726346775000000	1820954775000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
256	\\x379248b4cf089b8c3550875d47b20d66fdc0a6efbd285b5e0b0d25b2bbe5307fca5ae5c2f10b22e0d0e0304461839397d81b97b159043d2387277bc2f1c21718	1	0	\\x000000010000000000800003cf3a1ee725aa4d4b63833ff6a5d5ccdec71c3b31e6efd203cb50f963efb6d2c41475b7a10033d8522a38d356bce84cbed8943c204fead5889aab1c9d27be49a8ee6d01b3c7f9a64a2cd3939d9ca850aef7187bcd951060dcaa7b7a77a9398433412d40031899813006d079d4510164d9ed4481c67f4722c4f6e245472a036889010001	\\x595efdbe3022102dac228fe1353553625bbd7254c9f08a6922b4b23de4884933657e80f50d2ea983eb1076ae078ed1ad1ad11f365a2d785bb0ef5fe6cca8660c	1690476975000000	1691081775000000	1754153775000000	1848761775000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
257	\\x3d92ab9363c9284c88eaae3915e685bd6bf850026bd578b3fc6f464700cfaf16478b5ce3f5e841a691676f4605d95de00efd4a82da227f770800718fd9435d1f	1	0	\\x000000010000000000800003bc65931b397bb3986fe31f662e89678d5442d71ed88d6ebec3822a22b3feec547253270182d1eabeec48f69e2dcb73337facb6569c61721ee8a06d5c4b58ec5569fbf6b66881e10e4f5ad6ea1297921f61cb6562794509fe38041a34530b34508257013c9b2477938842c971c3cc52f8a9d134d490aee926eee8ed85750120bb010001	\\x85433ce2bc889cbb3ad0660590b76f14768024ddd0ac32ef7f1fb8969fd2e892cf2c380d404d9d7af6dbe9b8cbd47c2b3d1f0150254d2527d6f6b4d9fbce8606	1660251975000000	1660856775000000	1723928775000000	1818536775000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
258	\\x461ee55a3c35ba6e57bbbd870ea1be96a66abe8752dee6d010a3cbf676115aa2cf2a4f9be3e963b3361d85c1ea171322334f5008369fe43c469b546d0ec9878a	1	0	\\x000000010000000000800003d1cb215834bdfc9e53d51f779c798552af3de52e0fb5286ea592592768e787346048eac5ebd9b21a9636a2d423d4ebc2aeec53b33a32fb58c962d3e29d02594e39a76c13c0e45543d39735ad56ce63d5bc157b2690485bd69d8c95c60678c57fc330965897453b70573275f07f58ecb56c6186f853d047e0e551dae825af114d010001	\\xf4449e502cbf21a7e56a848c9a51f63eec52a320f87a73860b00f5bedae27117d7d516f8c73cef891f194414936ffa6b5063aa134339fe0a1efeb6024c7b4601	1666901475000000	1667506275000000	1730578275000000	1825186275000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
259	\\x489ee709fca21646b24e131e2e694071129fc1f939651895f8f5b2a95dd32f24c0b0c6b146d510f165cf502ea94b95de814b3469eb1707ef322a611ab42b5108	1	0	\\x000000010000000000800003aa5c246324e0bb15124e26bb71a3510c8f9ac0b732b46901eaddd36efc2ec6c6fda3eb47a5ae3c3780d3a5fea900588f970f9342af7f07d49c1eafaf68aebce4a2a6d4d54f4be2487ba041b4c83ac47ae834cd6f223275eaf2a58357321ef1fd1e30b548d076384e6aa5b0055cac60d89f297734dafe8ffcedf8e2735a482bd5010001	\\xd1bf2e4aa5ef888065e1cb02df9af50c453b7a12feefa93e11a02a072166d789121175ba009b016dccfa3f0bb272cd85966b82ecaa15e645ad1f5a0781fc0a00	1688058975000000	1688663775000000	1751735775000000	1846343775000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
260	\\x4b0aac54a5dd4f9f2e6bc1e4601fc5c2c843e9517f28b00c14cc76d0b67dd04bbe3c9d198a86352b6e8dc394481f2e1c4d70d5b7dfc15da2034e6bdb2b77f78e	1	0	\\x000000010000000000800003a6993e2667caf9353510b7c4790ed532a58ba92222fe8b76feef6fc388f65e345c6d80fefb9b19e6c62ea6c9ce3d06f854683a88c0de47dade511abede5d7ad2ca156ecf8ce6cef6ed2bae9473839a3a616a3a9c6a433ac7c63e2317bc3b1e9335d4254cf99d4ffbc5ae0a36e8b6fa5fd655d034b6574f06f4e2c1f60703300f010001	\\x0b6214df873d361e82a43ee0bbc00397b3bd49b14815e0172ac9249bcdb2b1f730f07d2ec563affd22acab46b3ca72ad7c1d1ed8e3040a060b0fca80db1e1904	1674759975000000	1675364775000000	1738436775000000	1833044775000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
261	\\x4c162fd32c21fe1a26c44712d4570baceb51bd22abdea5b019ce41efeb2bc90b29542d92949d804c60da3836970d616f80e41290eec2f39282a3897f9fbed471	1	0	\\x000000010000000000800003c13015b78f5040382c9b8946ca83b39d3c2245c4e9015520a6544f7673535a72593f3ff58e0101e6b5d8fe31fce9e3ec3e34c17b506c5ebabc98464dc19310f28b494ada7e0c3fe6dd5e8371ff293c0a38a64172ec8fc207c6078bf1c9680e2ba2fa1f864fcda5036b551b9bab680c64efa54fa237af1f3073032c3d207f50c1010001	\\xf9870c6299dc330a8f4cd3445255f47ae070b69d2f67f9c2ba672898a71eb8d8b12138fef885a17cdc7fb3e05c180042845268d5b116e7f744a16f541f13b704	1666901475000000	1667506275000000	1730578275000000	1825186275000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
262	\\x4e3a46d33b851b2366fa4e19dca4ad0528ac994a4331793aab75971c64b5d8c67b612793d230f23f86e4cdd5eabb6a9d1fe242bd25fd85753c7267103b057c18	1	0	\\x000000010000000000800003b46699f7d7dc4680a248e33720a14a0ae3ba25d2169f24c2c78311d1532c060a333520023db2bf824d3923ebb697836a0729834cb42f212dc1000370d296da351d7a956e0fae62599ef75b344fd0f17b28a734bb4c2576464761c398e4cd8cf87f6f7d2ac27eb9d04d44b2bca5792045627b3609c895a853b4fa05e7ffaecf87010001	\\x2670d96de919ec08da6d126d762ff9ef69a5cb1c00bbec5daf0aae024f1b70967b60d3b32739538dddbae8271d5f288fce5425291c35321d1d7fca984fa7fd0d	1678386975000000	1678991775000000	1742063775000000	1836671775000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
263	\\x523617b351e293cebe6f587705066ea4a8f5c8ca71c10764e3c447d7b9a35954bcccbf52652904f0d9bef72a42b50507a995221e8b8e8e7c209344b625ee0fa2	1	0	\\x000000010000000000800003c0228d97cd433622cd2399db1a1236e7060b39422f43b628828df8930ac2b08473fd41034e20b1ccd2ad8a8ddf8848766b43776a37dceee0cc183720bb4e399a8369515dc64d8b587a392383271420bcf1ead9133e7e4a6bf9682fc1bfa6df6956f88ef2d8d6b108d8e5c8b130738321a6c4e8e133eead55bee14fcbe467cc65010001	\\x46af7255e737cf18a23b5b54c34fa229a98a87e986f740d44d3c8dc8906b0f146c3c52ae89c269e4343e1b532b75ad06e8373a3553363418711ed2636a9c3504	1691081475000000	1691686275000000	1754758275000000	1849366275000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
264	\\x5296da1531f247b468c434a2831a1f16a7995d26d195d6ada5ad406a4d6f74453bf2fa7c00c007c0483706b760605a59117625b5540025e4bb7b1fb7fcefd7f4	1	0	\\x000000010000000000800003efdd6862938f0049b03cdfc61ce23194f788505eb9d35b4560d03dbceb41c098dbaf94ed007aba187886ec93f386e9367a560ee6ef1219668d4b35a71e96e5fffc232760a7e8d1f06f15130643477e966db9fd8df610102ee10cfce6161a036d7bd45e07e330c92b93e88b11c43956747dc892deb3a7c633414be61a6efd65dd010001	\\xb4d893b103cae7f0bb30840c9ab8129cb397271455be91dbd8e29aad207002b17e2e70c8b39ac6c14e174c73d3f846a88db15d4f48e242abbac52dcc41e46e0d	1677782475000000	1678387275000000	1741459275000000	1836067275000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
265	\\x54fa81fbd00b3f432f7ca58576f62207d87051898beabc82116d7d439df8fc4d2edbf26356a15a51537ab5814d2d57611003ea0490bb58d4be8d939d859bedc3	1	0	\\x000000010000000000800003cdf944fb92a04712f602da3327b565ee6534f88a635bad5d528fce42723a2b55f459be84fe0a0f04970667ab978447acec1d63096daffa9882834d6ca8b652f4624802d44bcafc55556fc5c0a23ee3dd3f66904107806d817df5aed8a9f83830d0a02b0d25f989a59a9b6a78e6cac455a7d501128fca4aeb0ad11eb8592865d7010001	\\x19c1fdbde99f615e9b5857b2219ac6cbc4651c68e73a692478b4ada26331b264d433197e869983d0d9b22e58d62cf18e80b7a1594c4068687fb97a670d0ec106	1662065475000000	1662670275000000	1725742275000000	1820350275000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
266	\\x573eb74ece1f885f23ef61eeb7c03352f79cb6b4e904956de4be0e561da06d02d931722960ef83ca81245f957b730985138ef90eb889e0f9c7c889b40436969c	1	0	\\x00000001000000000080000399adbf0db7199dd79dbad30823d5a00449521819d1a238ccd3ff93fa12ad23e060b3e8190a8f5f3c267ef81f1a8a35696ae01fcdfe4d96920916eaec15f7d9adebc05e2e28d0f1e2db16bf60e8fea9b3af7c8873fc86ec8067a9c71f4c2b820dcbce82db6e93cc62d04044497b5a8b2950916361329b5392622863f4983dccf1010001	\\x31f2c56476906be6748a3c641516eac870192386dcd4e367e0f87e727fb212d259cbc1b04a10211c4b2a3358ec2a895cfe406db4bf62ba539904c33da9a6f60c	1667505975000000	1668110775000000	1731182775000000	1825790775000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
267	\\x5a8269f55b3370039666487367a97209b2002b2137984eb136ee50a9b55909e63e6b6f96896297bdcfee31aede4231fff9cc8ea653b0157ba3383c4dba6bd470	1	0	\\x000000010000000000800003c2eaca6593802e7192719318f0c809224e259c69b1271c9fb51bed9d8315d51f20438fa986cabf661e742e74beb7ec603a68e0700eb21a4765747561d3f89d18a8af3ae431f2407fe6d43cc92bf358d5a3f717a0b4cb69f4b76989e410ed6f19b8d48c04630da37fbdb5291c3f7e934040355591e6b6481d5492fd8dcf397f6b010001	\\xf880a73e0d72bbbe4f33c52925c3e14dfbc55e56acc334bdef17bcbf7a46a45c7f2d7b9c8cca396b7b1a98a192442fffdc983e8fef3d6e1a7af413a92512cb0e	1687454475000000	1688059275000000	1751131275000000	1845739275000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
268	\\x5e8ac1976761eaec7f665f36a6a64a99d57e281937ff3d79b71d88646c6e5a09cb0d14dab806b4cc36b7f06a20cdf7b7c9d4d1a167517e121b1b49d58b7db263	1	0	\\x000000010000000000800003d2c7e02852cc50c2f57e50dfe52173a715b8a0f0c8abd6ccbe2c114cc2aa4f7869df691b00ba0faf90a30bedde30897b567d0b3e3706c1c48df49d6078663669d7fee265a6ff4f616496df5d1f4b2af4d681bf19629f7ab1bfc53e96c88d808917c23b02a6a2822dc00b41435794a089e837f49256dfa9ac1283f266b0284bf3010001	\\x9800d68cdc87e49cd044373f7f2010565a6995be2787b9352f980df225b53f1804e1fb86762c491f4d9345b19b1c06f33873c8d353fb4708e0b2310fae7ee00b	1678386975000000	1678991775000000	1742063775000000	1836671775000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
269	\\x64c6bad91ad79e8f3534b670f4d327b10d7f83deebdd10cb31836617935622aae020779c58f7462649436bee883ab13c02e53fe590b5c2d0b941e74b711d114d	1	0	\\x000000010000000000800003aa0418e71c407504d9781e872951a9c297ed3326d6aee16bec18e86bf23208c60fdd0379aa331831ced5dc8a682113fb3d9f66f7ad2d7e6fee5f115b55028300df9836ace88e85227ea6db7986a7dfc15143ed3421347d48066d69c924c2fdb85da56a0a9a82876f0416dd888cce1c30a41c6ea6af931d5195231c952504032d010001	\\x302c11ba7227121f819461d488207e13b42f62d540d9b63f8e25ea4cbc2a0315109a8021e72a648fb1e798dbeef2bf655d62f5fba8246863c9664da8386e5e0d	1688058975000000	1688663775000000	1751735775000000	1846343775000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
270	\\x65ceea8921b08269fbc40e2f78b315fd7ce14087a3f07991936d4e155152ae41ec801e77142cffb8153374fcf2bcca8dd48fee6a58b9546080320a42af617785	1	0	\\x000000010000000000800003a8cadb1e10708ff911aa699ebce309041dbfc91774640df1c3de790b2885fd5cfdd17a2db42983ac34b3f7719896f812f1d201c66870b215263207fcdb6e547609b023270f7eab019dfa6e729fac8588aee6fe87772b7e6327f7f54f2f3ddea0bf939dd0bf23d13906bb305ffdcbfb698856e7359c541da5865f3dff86507abf010001	\\x27a541d0ba379820e183440a0324fef49dde355978ff9b4bf6afcd902e7af8b6da2ef43bfbb7b25b1419e17bcf5a5382085d9b234f6adab7f27d5b62a8675d00	1689872475000000	1690477275000000	1753549275000000	1848157275000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
271	\\x66be9b91960c56e1afc753cf67b705702e8f66cc7004c8600756b3e27dcd4e4b4c50907b1a22832e1bcac257ab193cd3e55b1b2a3f73ce71b604c72e5ae9243a	1	0	\\x000000010000000000800003bfebc556cd912f88c1d87abc77ada30c6da355a9073aff951d51cdafb637c11093b0c073b834ad8c5541a97922ae036ce75c78e90a29f82a32282f9bb8990848b90d3cd785f32e801029427a4a7eea8dc86c3948434c33821fd8b6a4909b9c748a769390599c72cb8d79cec91f609f8cffcfc353686c56b138f5e56cd4c45495010001	\\xdcdfeac811aa32e310ed22488fab6937d733811b138b3b1b4eb91785fea23a2319e1383612c021c2a3807acea4daf990cef06635778764ef81992c7bb29b980d	1665692475000000	1666297275000000	1729369275000000	1823977275000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
272	\\x6afe0d411818f4db0e4db777783984b94eb97e928b23eaf42f2a731b9326e3dff94e05cfecdad2cc3796598dc4f1d843ffa093fbb56e792938f37781b920df6f	1	0	\\x000000010000000000800003dab8e8ec74b585f69b727b075f0f70b9aef92fd2d15d4c0095c4bc724b72a3eb12f467341094eb3027ad1ec8cd7debfe4327b5dbbbacecae7a190d9c117a214a2375c5ec5b79957e0bfab0dbf00c57701c1a8c147d69eed3959d576a807c7967c9693a501bb2f2d36770e262f450beeb229f86e1e1c12b26934a547bfd2af4e3010001	\\x64d39a570f281bdea6708a2ab6c54b2b065b7ef2c470811cdb265b5fd27166940f4b8dc7a7a5cf5bf32d559dabba984bc22e831a3b13b418cb3b2774193ee009	1674155475000000	1674760275000000	1737832275000000	1832440275000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
273	\\x6cd2c153c39b57f77062066f689d05645bdd5e2951e42776fc65ec9dd81a8fe5530e0ff232336315c224dc71151773b725349a724791ddd81075b2feb29e94b8	1	0	\\x000000010000000000800003bfa594d49f9ccabe191b4553ef2a43f1eed362dfbae7695250cc3517e413b539fd40b3fe07dcc479aec61d7678f12d0a30a5a1e55fbca67d86e9f21607c886ba33e5efa0a9f3e74ec201cd1228f80112411a5cb94dc1f7b934f527f9d7d6b82a95c6f37ce22b7ce84ecfc0879527f60ac259454e35e278fbbfa3e5f951181f3b010001	\\x5fb1dbde675fe774d5655ab3959410913dd808fac0e232644c8ef21e2d423128a39233d3ac959893ebda5dadefe34f53092f44afc849c0125e602f66b1288e01	1689267975000000	1689872775000000	1752944775000000	1847552775000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
274	\\x717ed9fc9bc368b2c19d327d6b7118a4b294875bc2ba37ba5777799f4a4e3845ef47a4f1547a9e1de2a3bc92c1a91b2a7e7ad30aaa5f5b0b469113b636da3be6	1	0	\\x000000010000000000800003bbce074b05651844414ebaaf788c1314384951974edfa81c47e7cb9f3664a005ee01eef9c87fbe98932c1a6fb90a6485d26791d749f7fa6db65651512d2965e3a502ac997819fc567dcfab9c02bf4a84cee10c5a4ed10a2269234a22f41b824bcff9551931266e10b441b52e40b958ff06fcfd12f9e78e0e7c7588d71a0c75d3010001	\\xad589f10300a5c76e2efa8913cc075b4b30d2f13bfe383514f610215237a4f26a2e6616ba1580a11cc6a3ece309aade9d74b2140960ee436766b84100074b104	1665087975000000	1665692775000000	1728764775000000	1823372775000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
275	\\x7bca0411997dda5e079a5018ebba38e5807b5f39b293870b973114a161d1238465815cd79d03528902fd9399aece33fdc8ea9c25e9cf935fc2f55bc28f584e3e	1	0	\\x000000010000000000800003d629fbec1d17960edaa135f8c42ea1ad3891ede2628508c59a1d9b4e3f57013105f44ebd8a0a211ac62fbf4457c3896d48aa2ab0b41b3cf7d417f2c521388e96c058a1b1923b28e601826e2f8c6080f55c4df0b09f52e9dcbce6d0964bdc816eec315a8bc8d8ae9169104152c64ee7fc52ca845ed6de53689f16687e20c2ace3010001	\\x8524d17dc365c7024f0a044b3154aad2d099cbb7b724046baa442da8d9649830a2dc712eeda4a14428dee44798e1852cba06c160b1bbae65850b1acb5e800505	1685036475000000	1685641275000000	1748713275000000	1843321275000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
276	\\x7bc28712ea47b1455d4afc19cbecf25a7a9735ea8e110de0ea479ec258c27b1e282d51c4c446a6a6c25d7edb8d21f906a3717116442e18bc185ac098196b348f	1	0	\\x000000010000000000800003c686747119c6fde0f60be8ff1e0f8a7683936164f35c840ece114025179b871725db8d39baadce87307079ecc3d6e72c8c228b1f045c035f8ffb8a09f2decaac388138bb16aecb0cd1eb8eaa85f8b988ad11710f2973dbe889c2f560a3ccc48a9f2009f9a21551bddc9f8f8ed69fe3ea6b159356014a79a82d2a4c240f255467010001	\\xc5a121bb712d35288f5441fa04a0202454754e1700999dadbdd70ae13367d016cad320665a0060b4012484da82d55ac3b2a49a52fc012ce0616d7166886ab200	1677782475000000	1678387275000000	1741459275000000	1836067275000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
277	\\x7c7ab95bac299bdb9308b0fb75028c29776885fbc6a070ce646992fa08e50e8704c8a7caf48dac6b6bdc7da9f210f64a5f3bf8f1c9fff957c65a15d041bc675c	1	0	\\x000000010000000000800003c3f03de75ca4b025f88e54ed6b51506ce76624cee31214ebd4b9fb0dc09d6d0232793766fe7b743f6e9d4ee719d9cedcf38dff49c8edf19d3f6122d43937c537192bfe8aa92721d65e273d2134bf7971ce917ea2498f9ac6a64589e1e34b9880bcc7ac4d20bdc633e33cf140848f71850887d0228cfe70200f65639daa82a3c1010001	\\x4ab6624fff4d003d5ed13b5b0e229123faff3550c9ceb17ad548592d6ce466215a42685db9608904a542dbd2c1f33cafc0398bc98eee65783e4f40351014e802	1675968975000000	1676573775000000	1739645775000000	1834253775000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
278	\\x7c62cd2933f2d6baf50fb2e46ce9225b7fc53a1decf7885fdc66fa3c70c79a2e9f3352a1b037305b3c564ae60c2685bf7fa4dead1bb7e499ce11270ce924736f	1	0	\\x000000010000000000800003d3c5052b0b5df99a2468d73891363e6dbd8dfb6b1e38f52aa685eecda7826b5d16ddb3c02c8d511c7155b58c870b773c68f263d81b702d6d80bb563981dedcd7403d3ee13a330786773355cf234f70cc730b568f1cafd0169e544a195eda100b4be0d56e5a3940e22f80bc544a29a6deabd5646e8c53f08088090eb01add7d9f010001	\\xfa9ad8a69996e06b8881f252e31e4d89876f157167c36e93d78a22685c1adebf7938e0fe7561df71ad6d7e0b4979ac806ee65be82f768e82668e2cabfab61b00	1670528475000000	1671133275000000	1734205275000000	1828813275000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
279	\\x7d562efabbc5061df62e162b69391fbf62aa1ac6bb4ba6105b36afcfc7f790d2b7fab3f41b653ede8e31a852c3746c9acf0ecdab4ebd6ab51c8b3c27748c554c	1	0	\\x000000010000000000800003d8e4e958b70bd120d560f91d567dcd6901767e2a58d7ab80c68e851e149b33688e1d22a5aedbc289c8d2c0ee229055c873941f1a53e6a00ddfeb0f34a14b7f972260841893195b6b95b511d25a2dff42a9adc29d9641f05e92ca8cdeb778bb7b1e5cbc12f328220d5cc2d3d9513a85a16742bc1a1dc18177d638e53f8e3dacc5010001	\\x1f12a146e8a53ee6eb3adeb47a64f47bece2fd3a6a51326f6ca19f81e253132d02079bfdad1698ea5bbe300de87b61071a1c0d78d6f1a8ab28057b102752ba0e	1671132975000000	1671737775000000	1734809775000000	1829417775000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
280	\\x7eda9732196690149afec5c12acbf6a325a91a804da02bd6ec71e24f88e699d61756068c2e40df5aa9d7492041bf9151b5b1f63a2284948503d0b9d8d35d26d9	1	0	\\x000000010000000000800003f10dc540314309118fbfa4c2f37ff8758c9e134214139549db268a88fcd771bf1f2fb761ca0e5623b54b51bf1a406c4a057c7be2fb249f65281f95a5c0e867f6bc824b1ced0478263e5088b17076926fb8bb59e15f272e251a22b99d23d2c869ca2c67db8d7eac4286c47daaf2c7845170b19fafb9f7143ba9768fd08de3ae85010001	\\xe9a6724ec0682cbe6f70c6ddb4dcadec715def0516d30f45ab75b44faadab077732243ff9de79009189b96bdbed8eb068081529d00715bb4d3861ae2d2bfcb0f	1688663475000000	1689268275000000	1752340275000000	1846948275000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
281	\\x88fa7b671a77c25d9723ca58248f53212ea5e0a39ac6ce459164dfc63c6252d394ed4b20c41908930b02602a39513ba53fd9e3c57498ead70bddc03514c49c21	1	0	\\x000000010000000000800003b471f16eb0bca4d16d290b208364dc946ef86bf6c8f0914873c337f94b635580cf4557b941ca6ad757e2fcca7309f731d33b8faa463b830873cf956cce6b7b032a2b43fdde168056512fbe849b7c338bf1eeb9a26be5597aad739278f5e3496fc3e7bab46b949607926b1e342fc6b1e8113a8b8045a11a41fcc503db0b269ec7010001	\\xe62b0a8c57552f265ba158095a75b7fde05a245a92f8fbfa2838a5bde59d53c597798e2d376a03fcbbb126b93d3f9d9c142080efcd9c95acbfb06dca0bc3690c	1683827475000000	1684432275000000	1747504275000000	1842112275000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
282	\\x892ae00322bb2b194dde129980b40a991c61333ed2faacb8679e30e8596c9a3e02b348bf8b40f384c5d0665d1189d56c2abf75b013612dd9edd1a96fcf2c8ed5	1	0	\\x00000001000000000080000395f7f3f1231ea566afe131fcdac3c4eb3857cb4cef17e029cdceeb55993b1d72fa778037bf00a3e6a4fba7b67a9e1236a825cbc2a333d74fd60cb7e33c0cb3d578900aa728b35337a4a2a924e56f4353a7be163f74853e4bc2e4ec5e37d040cd9200b20db38de19b874d75f13ea0d764951f0af0d01631b4c4c4fc347fae7f2f010001	\\xbbcaf3bdaa8ba6fb39202c6449eae9c2150666a8734de725c4630b6a45b5235f34e841bd8249a562bb62fafed245e0cc80ed5c532a9694d3ef1637b2fd0c9c0f	1667505975000000	1668110775000000	1731182775000000	1825790775000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
283	\\x89ee63d24f2c8693204d9de5c143fce3aaafedd5d4f2f678b20690a650cea64dfaf89fbfd4f35b3a9e2f9a0a1982c83b82f9749f401f6695220d745d41d0b6af	1	0	\\x000000010000000000800003ca13d0a908579b57539564e58d32b19c8a3b36f4a31b06386aed0bc81558019135fce897e6f14279a9507d99702a8db7f4b23fc8437a4a235b8d4132d16af9be558b3143cc1376d6f45ce896defde55855efebc1e1e9ec7d9b94d17d9f42ef8c6fdc4759003b9089e307ae57aa8d6059faca4de8369d11df92ca6769b5ec9677010001	\\xf58dff7d42311def1e84ddabada5fd10af4d4f6ba346b2b74b877e02c9a736490aa810ae9272f8804e325e10fc5b6300956ae4f7e93cb06c5cd144301e771d0d	1688058975000000	1688663775000000	1751735775000000	1846343775000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
284	\\x890e7d9d60d97e520837b09305e7dee526c9a91785ac62685b220ceff3dfc5db1c1eb972d9ea0a75d5babd23eb6d34a28b46e5aa0daa0b1058ee3efc16f15613	1	0	\\x000000010000000000800003cce9fb118daf1b5ae4da3df6febd31e1243780c3be31bde9a414be3ffc874619d87ce5922645a1fa779f30d055048b3115a4c7d394e8a1a8db4c8d8d6cb88dd684471726f026b8bd2276d08e1dc1ab7c478ceab5fe2dcfcf1628e3291667731bd4e674faaad72c3ffe72765fb720ae2392266a3167c7cf1ae75fd2ca105993fb010001	\\x902a9e6168ca7fd9d816562383e834198e3ffa665164a58ac56892f1e2986ff3de66a14b858489d33ed1c94e7dfd703b54af866cdda8a889b401a99d32c5870d	1668110475000000	1668715275000000	1731787275000000	1826395275000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
285	\\x8a229da64f0b015dccaced2f440cb1805a840dc571e13afbc8843f186dfd7c65c08dff4bb4096d530df2fe2925c0f3e8da283aa3bfc66e21f6aeeb978f415037	1	0	\\x000000010000000000800003ba14c437a25d13e559f3572ca24ea69341afd53de44a9ea4a9a1aa1760507bcf85e9dc03127a78a00fa6eb47aea22606cd0e3f55cf933af677d6c9cf983366471303cc55d33e0df3fb50a8fe8121cbca59352d903bcc1adaaea55a3b5ff3202fff598c75b30d8c3514dc18795ece3c7563aa2339ae98be7feb7081210e8f102d010001	\\x2ff60ff74d1ac37ac5f64206277f47747687361a68577dc562519432bf020c00ca22d8248a227853c9c7706b4b74659e7f361ba1d4f42d3c7bb82465c9b56a0d	1684431975000000	1685036775000000	1748108775000000	1842716775000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
286	\\x8b6ef37244a20ae57c1390959c48caefb2eeb40976a9f7b377760fa3bd62f277e225b68fcf2d36b1153c8a9ae1c85fca03422b8a455967d043fe83637d61adce	1	0	\\x000000010000000000800003c31b3b612c596a0fc61f20cf2fab0f68a0fb23f48da9a7f40ff9c90d5254411ae7cac68c9f7e3c290a54d04b201e0a254620878787c0670adb29fa72903a39895105acaeef1b4e8463b941a593d11b2606ba9cdc9d33587fa8ea387e8e4c12b37b3a1d8bf685d5730d5b0f104a3475beb306fba9fa09b275e40585c4de56e2a3010001	\\x582658c08f94969bc17c5ef0fa264e9e1cb12e614d3a62898530afb454644fdf46a870083ee54dd6d069ef93b37690cf6af5edd2b00bfdcf3d0912586b49170f	1665692475000000	1666297275000000	1729369275000000	1823977275000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
287	\\x8d86c62adbc2b83daf8de592cc7abc92a873addf6539f40179382df3f8663bb091fcb3fbb219e1c9d6bcb99dcb2c3d6f9d417c524ba770f875321d39e6ca4980	1	0	\\x000000010000000000800003b3d020cd42f965b9ab2a0fa38a32608b4591f23844a15911aec4640517397e535bca7b2269e61193c730350aef5178bb338a9eb9b6434ef7746b566db4d285c471dd858a9847e9bfed40f02345cc3b9c08a6842b4afd08551a1240363d2407168a90c66eb96077de8f7d99de259e1a4b77aa47cd993bae6ff5cce28b86c67305010001	\\x146caddaad5a1a3476a51912d15980381bdb8619e6217fffe7184f7b9a828228a36ac5defc0f1c3db3d1a66b5bda41a4790f7dcedcf17c1153996937f2bdb606	1677177975000000	1677782775000000	1740854775000000	1835462775000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
288	\\x8d76f713bdb14fb4c382f23be01c469816882dd6d56da462fc7a8e04fdd886fc6f15ef287e1d2e0f01bf8035283e9955c43f1011e62e6b58bd04ff9637ef22a4	1	0	\\x000000010000000000800003d40b250a816534c0aaa25bb06d496ef40d2258c945d175144ff1bfdc540365468d9739537fb3b77056676e1b0a306e88c1404b2683d211dcebe7a9fdf5ce16ba40512a8e30196b6f1e27d8a8c22af671403138ecccf156a74778e9cba7a0e7845e83d7ccbf736f28e3ad0658566647fbc971bbfd0b3a773a79ac2994b8463fbb010001	\\xdeed7f8b87e60563411a7e76183c63e7e681a20deb5dd8caeb0d09c2e7d7bb59b376e1eb394a6c429019c892763ec2b548e1f16642a3b953fedabd4bf7eab30e	1678991475000000	1679596275000000	1742668275000000	1837276275000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
289	\\x8e0684e0a5a46fc93a6ed7ed990114d2680939237c82fdddcd515d1cae959c9b7a9cef5b91311a40daff2e0dd6176af512dfded4265ba82c6eea3796ed42aadc	1	0	\\x000000010000000000800003ba591b6617d5d9ac4904f849b00814bc4fee254ffd071f6d29e9baa927e1fe9b3414b31d6b15e887f18442d61efcde2b34bb86db9069f13ddda4524369dfd91e17e81c52c270adf6914a16f85d41e93e68d36ba33dc5bccbac847dd659d2fef6181f9f9e4d5749893acb1ffe37bbc4002298f2ad7cbf61b74c8d8d0199dfe987010001	\\xb2f878d426b15461e9bc92ea85d0fc9427538f1f886b26e7d18b8f789261cc1a3ccefdde97344219bc2bf7775bcd8e5368c91e975e031e980d78b6da03c89d0b	1662669975000000	1663274775000000	1726346775000000	1820954775000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
290	\\x8f62ae8dde1fc7596bbd4b093bcc38b50ca6ffeb1d654dbf3cdb99ebf2fe81c1e0d1e8a60f2ad46231e1c9e817f40f4c8ca08c6f488f66d415445f6273273ae1	1	0	\\x000000010000000000800003b0104a6202f76dda74b0356bd8021d106d28d793d16fb07d281c923a5d724d6d833dd07914cc9a8df0803e04e81e35acdc144710470b09089e8cdc81517094e63fddabef41e56ec13b4536b4f3f16745f1871fcd94d1ad05bf5a1ea43b377dea07908c112bc3ec370ef362eadfd5d76b438489a324d224ca2688e79163817f8f010001	\\xd26272625fce6ef94f669ce833928a694678d2d5912bb877b292e23b14c11abf55c5a8507c6ad47b9e4c48ebb9a6fa673dfbfc72e2c6c3d81114a5fbb5fb760e	1686849975000000	1687454775000000	1750526775000000	1845134775000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
291	\\x90b6623ff20ab5266d90cc319c3828f5d739b4f6f8510416544546cdf283d9de8ddbb478ad8f62bf28b13dda329bbce92385778744c642d8507b59587bde9ee4	1	0	\\x000000010000000000800003a8363695f0ee35048f3e7627b55c0613bfadb85f8b9be1186f3cc5c2a40108278da64744d6e96673d1e454326bf1bf7c9d87894e722fa780b392e5e594eeff51f95f9d03a7b48887e84c834c9077cdf01f11a6c5310e228a72980c93d52d3015ee7151169ad855ece58ba74ed2dc15af8e74bb5bd244da21cc8718d9cfb7eec3010001	\\x564be39f153d4a535aa9ffd9c86b972ceccff11bcc90c6d7f54cecbe0b93b91d3a5f2d891ce78b3f2bad5635f84ea12c4a31613875286e5901617aeae04e820f	1666296975000000	1666901775000000	1729973775000000	1824581775000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
292	\\x933aa20653c318c7e7720c9ccc5c4f2833d060c4be2470811d19d61a89506a7d1d8dd75129b87e9d6505ee183abad38918213abdebb1b24f5842bfd4de2d466d	1	0	\\x000000010000000000800003b80b07289a0c083ef5742eba3ba8376c53aa66eaa9d05922a63e3042202890d0a65bc864f2662c3d1868c580f75db93dd864fefdc385c368e8f63a89cb96d3042d250a76bd8ccf7ad7c820cf18c4a49c4d271176d8a5421a2f008657856857780bfe69c014d90dbfd471cfb10b7410ffad177bc3e896dbf9a464c2c2943e73c3010001	\\xa5bbc6cf73e8c8eb1cc5a78f8ffa8c22ce58a1c2f76808327756d92bb48365ac255c334ca40909ab8515e27008e71a9ad7a69357a366ab9f129d2bced0dc4f01	1679595975000000	1680200775000000	1743272775000000	1837880775000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
293	\\x9a2e5ae6beb599ee41a2cddfe019cead158231c2781b3fd276026823eb65cef4ddf6ff9899aa5226920c6aeeefe76d4ffcde569bbad7de833d80ae032246542f	1	0	\\x000000010000000000800003bfcce646190afd3737a29254ff55f9ec37a55705b405942930539c3b2b9e96ee9d1d4b0600c0e2330801685c718992edad803b4fc4c3fec0a9ca160479b4ba66804351315a228cb116922f730c79ec40083adcc0d424b625b9f2c12576e6a905d63529f638e91d0dfe4a2e2ba75931934e50c3345df16a7c8c85319ce9d82f9d010001	\\x1739997d9c710aae382d23f896ef89d5e119b819eeeb8d3032498ddb9e158ab5ceab181ce3d949793ef914adf3c160a257b3308313338751176a24373f18a409	1679595975000000	1680200775000000	1743272775000000	1837880775000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
294	\\x9ab63478926149787a5023b18461ca880faf5cf5fd94b1828e8a2a0883bd8ecf3136bc2a18565ef2233a96c9d9e7043c7d0c52d4d32b90614c9204737a53ab2b	1	0	\\x000000010000000000800003c284400e03a1da6693571540125519ef46b58ef6f360bf0b9ed5f7de4388ee24f80f27725d7dd3cb76375a13dd150f49d9420c0442240de5a597adf66207d812a5c7de07459d93a6dd1e87b7ed742624170ddb1bf4e81f84fe40f3c9d7480fc83149453cad9479e1343261144065b0ecefab5d5b71c3afb82e33d0ddcf8fc92b010001	\\x1adc7bff23c012a7eb2f47a2de893e6a580e9d412ead5623ad9e021b7c6c46f170e7869bc118d0f03beffc0f80bf303ef41f85efee09051dff120d3f7f5f1000	1687454475000000	1688059275000000	1751131275000000	1845739275000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
295	\\xa38a7e2a5429e183afd19577c8a9f3dc73132dbfcdbb98b8b1a3d1172419d8864ca603a081bf6ca1c944f7e598a68beb77253232e3a3fc427aa69bc290d647e1	1	0	\\x000000010000000000800003bad82de69b1b491d131f85bacd9b81472201073f96cf25eb85b3ea10c6bbd680e98ace63afa200a63891bb7d2c834c407a71ca0b0ceb89d7c15eaaaf5c0dd89739611abdbc73f23a0f385785f0a24593e92f04f04175d7bf3358225c01e5557eb61cd061b37edc85573e240c0011aaf6b0cb5eb154d5f506761c9553a53aa393010001	\\x4dfd3172cf7788c12404d6c9df98e9f6c3ca0620a7ab5abd4a3b3c33ec870688c84fda3509519f42300d2acf51ce13d33be61ce802188ae11b0c5c81dce9c609	1672946475000000	1673551275000000	1736623275000000	1831231275000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
296	\\xa40e9bf42bec58399b710bbd8a9c9dbe1aaa1a3262385ef9c01a7ea336a56ef69706e66cee853c8c95ec5c8331d1c8155c7d22c53bcc28b9c9f20067015a2cdf	1	0	\\x000000010000000000800003c3771eb664382b1a17936ecb78726ce772ed7183129e4f062d2565592e6e020b8d0aadceb26034bcbdab8604eaf15e84604b1c4c8b0ba5570a1761647b0894bb97f8a056d5584f96676f0c923233b52628e8c585d42894bb588475dbab8ad0064bf6e64821345c989dfea58e62b040d2f2e73361daf559f2b69f9636060aab6d010001	\\x871fb464283c5a6b316587a9b57bf3eb8862b1ca70766cc973e78b2f6cc99473e7a5968de29a904f23368b5954432644c0662a6660e4592aa7e2ba6d8e9abc07	1689872475000000	1690477275000000	1753549275000000	1848157275000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
297	\\xa74ad58f773964f8260590f395967ebf115cbce036320f88742e6c9a42d3fa541c2de056d4febfa7fab1899bb431680f0016cd183052dc79c40c909794e67f5c	1	0	\\x000000010000000000800003b22995706f538a13734f3c0e0f2ca8c09f477139b4ac1cd5df176bd99cf3d6102a7f2b4deec68fbc084e55d8bb1518850d497dd253c507fb7d74dcdc511ea4c2a47a688b0bb721ba68c2d78eddf4b643e8bb49993dbd617009c28e8ceae9fb0f1b1e11bcd8dfacc46eea967b30cd05db5a6d67aaf4dd2e0f7dac2089d7c1da85010001	\\x99938ad22252d0567fa60a360ee05a33661bb76e9f32c65270d5b36badc924958912494af53f0b832b68f2bae0f0c35b3412541d541540ae736eda45bdda4806	1662065475000000	1662670275000000	1725742275000000	1820350275000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
298	\\xa87605b93b83303485692b63ef638ae71e9694a775335beda1b481ba169877a4ae21c83efdacec76bf997ea4343da4a72fac9aedaf9142e34e3d9210329b9440	1	0	\\x000000010000000000800003c46152e5b4fcecba4c440531e8275e5ed7b53de190bcfb1e0405342a0da2be8c492f4dd4dba02a3c6bf763728f5dc344d3119401dd032bd5657d33840e92b578e8a8d721de8ca12de62de92bbbe04845e4c972bd7cbf3fa8d8a52696496d7666a8ceb42347572a831813fd48e53eaa4ae52e589e8ed7e039007f0012741c1fbb010001	\\x03c486bf8867d426932f11a25737969385ec0edb8faae7dbe2b2b0e5fa3571d5025dbb7a8888b556b0d4c4c65e4ec006759aba58b2c7559d74291ff58dc3150e	1669923975000000	1670528775000000	1733600775000000	1828208775000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
299	\\xaca66faddd764d176c6a64d6d2097fc6488a45cb7e945bf80ee81cd9bb06681607581841023bae7969285c3b69502c05b142bfad16ce128f3dab7eb5b278530d	1	0	\\x000000010000000000800003c0524778f87653041f9425a50f4d927a6208595e00effb6421c6347bd05fed133f8c0479d5a32932dceb20b6fe766149cf8c89a3e426f63778e4ec4e008bc8be66f3cee69bf3813850df75b5a34b9e80bd206e4ba6e130c34f2430995fec38b6bef6a595f12a6d24a09ca9ce4cc59a82f12c11dc7ed03d330356036509c750a9010001	\\x1141eb0cb778a1d5be5c1995eb0d6014c1868ee907b3beb057d60667d2047deb3929a4dc4de4290e633069d15e4ffee1c645a736771d67044d38aa6f84b8cc09	1674759975000000	1675364775000000	1738436775000000	1833044775000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
300	\\xaf82f1b6532153b00e4bd508b92696af92df2a1cf956f48f8f71f34065868d80b19488e87e6210ce42b17b6c2183fc01dcc4d913db68d9dda8ba6880950c798e	1	0	\\x000000010000000000800003cccb3ddd1bd31f56d937449c352fefa9d6b95070e499f152275372a2bba870d992cf82cff254da189e381488982a25b18e480e926b817a17251e77bab5ff042583f57b3d24038077a114dab64ed63a85baa7d8416867fec6f6587cb44159dcabfe6f6bc1e39032e7697cca43ba2272d68381a1c246a430b65a9a431578877eb1010001	\\x193f74702ed2791c1b7cca7cbc8705952912e59f9bb0821ce54ff730dee9a0b453382a0fdc8bfcaab0875191fa97af7eb881f22c734fabb0f7e826b6154dd406	1671737475000000	1672342275000000	1735414275000000	1830022275000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
301	\\xb212204a1495128d667fef26d784f8edd1463de35efc03ec8483a51d8c350a76e6d4d43ab37775140eb82398a4291aa4fb56d61225aff099dfed923cafadc89d	1	0	\\x000000010000000000800003b72c917a753f7bb2c5b7f90749c4a239b1f2cf3f856cbd4b7a9811027a8cead346902997a3009c340d83c356293f40c7e105d87ef49b6bf81734d92ec8cc99ea31412d12134ee3b06b49e9b0cb9d97eb4308197d913b7e262c47313964576764add5e93c7ec292680599ab8fecac7359d4837280b5a5a28fc0ab0a3331db9cad010001	\\x938f5b13447bb938785aea0276046f79b1ea1c2d5081ddc02959b7d5abdccfb7f79d7ae2f243a92e04fd0ad641f2996acd1205d0304466a668380b3c71f83504	1667505975000000	1668110775000000	1731182775000000	1825790775000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
302	\\xb38677d6ef3d61df2dacf8dcf668945e6378ab913f5bf36804a69b5e8668ea9c999f021c391961bb04e46603118e009941587353ba889748fc0b6448bf89e083	1	0	\\x000000010000000000800003be2c00218aff9e6b50ce26fb28e37c7521c9789ee1eaf690b4a918bd8a367a78c4b91c94fbfd8d05bee35e2100781af8cfa3ce6cd934ccc2ef7e787360731e25e5b2860f9d43e66c10a38666d718201217ca838e050ced2cf5b057a8550072eec0c32e158e56fcdf3a6153d41b667aea7ac8e8287ed6198b22042f8ceae8930f010001	\\x5149b83d8e92ca73eb7703e576b8a2d7498b4fdbf22533719323ccfebbde07f4add84fee90b1a3a0ae03970cb09a9738fd5ae2e9ca0d3391d0e1e96c0701540b	1672341975000000	1672946775000000	1736018775000000	1830626775000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
303	\\xb3ea5e7877cc97a7428cdb82757ace04a9181d14b6c14f41514fc4519f48ced5ce347596bb2d4ab9a9763713096eb809af8833b2c19400031ac05668434d13c9	1	0	\\x000000010000000000800003ca07dedf2c9d520877162639d9849df67c4b2d10193d3030133e5c10b57662e228aeea959bdff9a23db09e3986ba2bcfdda82658aaeec7a81008ecd8c91e0c9dc4da268eb3840470e66352322a43a36bdc4d5283c8ce4125df16b5c369f8aa516058791a4af81c0dd825a88262106a378b9b731e0f82d2da5cff33ff74790617010001	\\x6a5e6177fc025fc416d9488cb42e55178b65e84ed5ad1afe9b646325e292217a5aeff87cc08df12c1d89a5cd3cc0a296b5d638527e8020976c92d26ad0488f0c	1680200475000000	1680805275000000	1743877275000000	1838485275000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
304	\\xb6722db82fa71d199a3f05870a3882f0129fd073762a3f5148160a8eb311744e63ac92bdb78a436ee5917b68293630ce3c76ccdfcd9781273e6a92ebf5c6f692	1	0	\\x000000010000000000800003c4283fa3bac50f0ae157b40fb3eddce36e882b1e9bf49c5c77a63688e65d4f19a6248af774d256f651d6610b0111978f89d45a9340f376089c4a44003b6189dcc78efa30221f68140eeb5c41df04592e3f0557e547aee7c80ee8a6ef83a3712de76ca89fb031c5b001acc3c756442a1b7e02908ec220004ae776b1d44143a683010001	\\xe93ad9c377ddb1084a961bd97f3da38b01d125525dbb0bf77adad93780bf16ead36c3e4a1526a2b0df9d978e567a0feaefa178618f2bea1f5d518ac23eef0604	1690476975000000	1691081775000000	1754153775000000	1848761775000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
305	\\xb97efb3fd76f22dc9b41910cc01dc53954581504c4c74b97f491e9b270aaf69cee192c2f98e366ace8a48041a8ab6efe2f6a35b51d1ce8257ebf80f9478f2466	1	0	\\x000000010000000000800003c01d3a7cd9641ea27463d8b0702bf9406ed3791e5d4818269ba23d5bbb10e81cda73d1217403fdcad618d2306f3687f191919fb68cb653de860401e685a49cced269611b676fc3ad7355b614c35825e252c26dd32414a4f4b627fff470abda163a5a2b124631b1f888fe3ae6c90f66a49f86674233bd44b2a602120ee715150b010001	\\x8c8af91d880a9388da47a62db73cb275c23fc979470f47b48fc4d0912ddcb7901b98d4df29640ca5b2c89d65421d044a179f58ac3633e11d10a86fb7072f2706	1676573475000000	1677178275000000	1740250275000000	1834858275000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
306	\\xbbee0212baa0fb68dcf6f877708bb3ac8df14b37a559b05346f0143bf402e029e0e2aac57e0bb796c13c8d2bfbfd8baf43ffedf4abc2c69517f9ca5b9d956406	1	0	\\x000000010000000000800003c3f7036c1b2fb4fdd635c08bed2dc5a70385889ad3fd53ba3efc55f9fbb1526be753f670e8751a7f2afadea1823f3b77e87c514efbdb12407e9361814940bc3f5e57a70f52c6a41b422cacdcc2805680e04020c4257d0f7f138ef22b112d1f20c3a15fc060307ee9183f5e886737e8d71d1e102374b221ae04b87abb99e68419010001	\\x568f639d98c4a94fcef5fbf84dac3764b372188f83f29a2bf5beca2e6dc09ac26343e0991344e57e3ce28be4d65edcba86d3cdecf085f5f1b88a6223c656db06	1660856475000000	1661461275000000	1724533275000000	1819141275000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
307	\\xbc92502ceda86763475a743747dc2cc2d626490a7c6cb1d4a6bba08b688eb86ff0b34960d515a05686c18b9b4b56044f13df5d82fcb7fb6244d589eb75176f44	1	0	\\x000000010000000000800003b0ff1321363e8062455ab72f77805894417d6fdc16fecafe91a9751d7b6205a977f6ba496afbe0439207ade2a880465ccea61bf26f9fdd2880efd08117e401fe6cb4d1146a22edea72c320952aa2a87ea59c0767d6aeb5058d7afb3cd8b4d25ce761065bb24f9dc2531bc412354aba0e750ccaf077f9a77632308d89bf093041010001	\\xf0917e76fd25611ce952c4ce5e0aaed0f298713edbd38040d1d56e1d29c98899e6e6f954cc36fa5468cdcd108545aa6121078a6aeed0e83fe459abfeaf8ffb0e	1672341975000000	1672946775000000	1736018775000000	1830626775000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
308	\\xbdd2da24c2840f7cd709d8ff53aaa56723ffe95309a4e4d78b99ae554c9f51f48ec62733bd9c2a2ef3551b45c991042753c6b68aafb02d97fd8763cb237f82ad	1	0	\\x000000010000000000800003cb08bcaef5ac39794919a465507100445668ccfe0c1bb01750e45a42b21f29efbd3a95a5f0367a868d58473cf8bcef0aecd1ebb44953ef23d7531548b4c11cf0adb30539bb6f92617b206d8d893abd18ac553a68a9dd854223f76ee1b0c2ae3b22bcf1ad58846a4bc45ab2954b5cbfd4c9207a5f204ad8c04dba696aa3cb9ab7010001	\\x30952c3aed40f963301b91927afa0aec81592bb6aa705499bf9499b0854358bc1c9e8e740b2e51d01c27de1283f0ef2c947391a358d7a6d63eac0ca1dab70807	1672341975000000	1672946775000000	1736018775000000	1830626775000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
309	\\xbe8e1703562a41f3ab51bed38b822808137ee1e4b779917df3e0ac1865c8b5a40277ade8a813d634892f875e0109d8e867eb34818d1294a9d4f2beb28cad837d	1	0	\\x000000010000000000800003a1729e1d937ae4837220e88ce610aa39b32d3d4cbe7d731b055bb0a6272188c2a0bfed3eeb0c7201ac5ff240243b4a885f6c1887940e503eba8d6febe7baaad42a65e3e7b9583ea8aa3dc5cd195b32fef02105da2031a0b7799b3829b1c05fb04d46c21bc4d24c34b5c696b5aa109e55241238db36591bb12af54e7f75d6ce17010001	\\x2940a1105daebc4c565b3a00bdd4383ac93f31db7af3b2a2e657afe4ebe4ab8ebdb9104bd29e7f3a274d9743f7eafd3204e1339c5bda38cacb39fda258d06a07	1669319475000000	1669924275000000	1732996275000000	1827604275000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
310	\\xc5c2229dd2823a73d3ab4556b213f9c77b11301f5c61db6cde16b4bf95f93f1a924a93fd3e17ae0fa38f1ca1ce79d09b8a78a559a3ea316aaa91133a28830541	1	0	\\x000000010000000000800003c0c9b70bcd6c6fc61e2212b18c730f19ddee2a29795cbd85435536509d95c965a45256b85a2f519c24423740fe739e6003518fef35b717db5da4295f60681e6e5cce8dbc2090fe02ca7df791ff74e605d16147b01f52b73c191524e6078f2507b5a30ad406c042d2b910cc7bd93a6e410696564642ce40f30b7312a3a2e6e87f010001	\\xac0d414fc7fdb32405cf60ea4efdd0d828482bfff90dc746589e8a17a1b1f507b99e43139a9db5dc634668711a6265983f578125b2c50c455f70734696355d0d	1691081475000000	1691686275000000	1754758275000000	1849366275000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
311	\\xc57a4646893d243f4539d43e5f5e98d09c99fca39c8b965b06a2597c1633a69cb80ab44b9c7cf1959e75d59d9cac85559fff8858c70bf1ee50eba0c49b699645	1	0	\\x000000010000000000800003bffdcc328ad9c17306e535c65e236d2037ce1b26d5c8dc1400b4693d405c0a2ec5b03b695d0103fbf8c44d8e3e8bf2d41432280b80f41fa57ed2dc2be87583187b96199400a90fbc80b5825ccc0ff5717711dd330975cbd077b48e32279aae0446a6b93128cd6d9c9a9f6e0712d7be830a74f910fda2ef090c942c5afde528f1010001	\\x652c81728d1cfc1feff718d879311e477ef85bea74066498a41e66388c28975d106a672d3004456dbd487530ca8c2f54d05f2f5e38f77032fcdf3855d9ac3108	1672946475000000	1673551275000000	1736623275000000	1831231275000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
312	\\xc8d6de22ce220b84ae5f7b4d6552ba6a6f28be0d816bb2a09cc244b0ac4a249d6e4a84af651585196e259fbdc292820079cdbc5fe309ddc09fba584f3f907905	1	0	\\x000000010000000000800003b993d3b03fa2a409b4d40f1d27fbb0447c88ad897d160d31a7ad8d1a41a3557b8dc1c10850ad1131d90e651ae9b56acf823a704f8fba572dd7f5688a3cf8bf46591a63fc5526ec1764cf862e59996aa144219a2da419aae66228ef318cff450f754b9671c390be1c5bed4b8d9f1eace857d24749d53976e9511fb854079a6de5010001	\\x6bea3006bdb1addee5ed91c9baf2a474415458e19cab2a2342d1f0272d9dccb2853ee1df02c4bb5b020bff65b7eb86c48da3337e0d5a7432a751e5a8317d8b08	1662065475000000	1662670275000000	1725742275000000	1820350275000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
313	\\xc8dea77fda95a133e56b0b0b04c103e7dd1b37f772f07c1e06a4de289aeeb56d3f506f6098b002b0277a76b5c0491450cd4acf4beaecfb77a764e75bab2c594f	1	0	\\x000000010000000000800003b3d1a57d07234933b017c14fdaa25b997eb6dd1a5142895c7a354f8db1f863e50de9f879bc3f76008659a0fb5233361f9c09e8a8d093ce0776fa4321c5951e6b4caa1fb1a7662744cd1754e44727a5dacba5872421c14935ba46626445fbe50cc82d2fbc98404b55aca434324e8226f0520935020fb973b085c3ef3f6ffb0023010001	\\x2a3f153183ca079305c8168b5849ba49b53dc11c79900d7a279300366e32aa38d395de24ed0de0917550cd77be16fc67c3180aeb83194862e7504fbd8184c50b	1684431975000000	1685036775000000	1748108775000000	1842716775000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
314	\\xcfda17ecfcadcc3ed1fdb9f935b679585dbdfd367713651b78c5afedef122cc8ff129d9d6492f4c5dc837525708d930a9c4875014ba54e698665dfaef2a98278	1	0	\\x000000010000000000800003d2df8788307ac105b9461ec7dfece831c833548c8992095debb7190a757329c7cd1dc36f8353d7f5291cfce16c04c9878849a598bf92a22f757ad7e2b0a14ff436f7e2197b74fefc9718ef8a6def34f1b9b9c2636bfdf33391e70f479e6ce075fe670abbef393890de9f28eb4390b94f74bbf94e4d7f12757383615ab2b9beff010001	\\x810203e95cce94a84fe608cc16cf83a64516cd8f8a96b1e955579d4dd401e49b87bd55d551220cd10b6b9d33353c233175833c8a89d91f74d8a5ddf1bea5820b	1671132975000000	1671737775000000	1734809775000000	1829417775000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
315	\\xd242f604e4b6e206fb94e821ecdd887f1132518e2c365fe32ac28e3601d570b0b57a94e69721fe10e523767db032c344febd2d115a29325947dc30d1928a62e4	1	0	\\x000000010000000000800003e75253f86cf220f303f110a511229ec632d949ad33d3ddf11185c7abe709ca1e3918d4941feb32c89ea3e72ad5b0e97315d2372b9a4569a21754200feca18c8f6e85a55d231434c90559c9c9f452e1e992799612762be16b6c7239b8e6be4a8ea162cd98008b162dfc64128b8613dc9d356d633aa1c8d68bd900fd7ef3267cc9010001	\\xc4aed40f11acd8c9f981f5dcd5c217b081631d543f0c90031aa65a6d7a620c1493ee715a20b5efc05327172871b580845924fb3ea42af1a609d4ed237fde070c	1682013975000000	1682618775000000	1745690775000000	1840298775000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
316	\\xd94e16d174f2074862172d8fe436a9084abf4f489a622f57db0a6ab0308d270a4ab5fa21600affda5dafed529651bb90c972509c0303fed3d4d10d0c1ff400ea	1	0	\\x000000010000000000800003d61e8dd7e5b907129b4e17433cda95ff18e7871d63ee8bb180fd74a62ba0a7d477ea95d45444203ad6d51d73544372e8498543c4dccd4206f3553c33e7224d85c1a43e1e4ff07bc52fe7fe80184df5cb65d5bf16d37589149c82d2629700dde6a6a17394fad2826781669096357f600d84b7c98ce50cef697019b4b8af9edd7d010001	\\x80cf64beb8fc5b38df6ce15b00474b4f9507e1ca05e30bb8b4d6b7e571a6847ebf27c2773be513496e81e084ac4837ce12f5c67233cfc31a79c5a4eeaa34c702	1682618475000000	1683223275000000	1746295275000000	1840903275000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
317	\\xdce664676e0470aa4596d21a338a25c633ae045e4c26d2cdfcef3a6ab4a89f80916b2bf4527be245cfcc9d5f58afd678930e9456b9e67591fbce977462eaf4f5	1	0	\\x000000010000000000800003a03dc395e2288c24639edc150ec31523ce36978f83e2ecc10412cdac9e36420c18ffd2f87e300fec5b004ad750c4fbafdf27e0b7b85fa2334a8bdb727df68cab505a2832972488ba1b2b5d402e0aa59e253dc11ac8bd8787928ed40ec740a49419c1169535cceb8daae1af9c6d73ede2ec7dcb9fce6896c68475f05022b82775010001	\\xa2827c8ab4ea15b018797ea3b1919087a138d19981dbac1e64e2983b5e54828216fea96059ea956402d78abf1d340c0a41c6d1bbcf561b6b37b4db8bb66ad602	1672341975000000	1672946775000000	1736018775000000	1830626775000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
318	\\xe7badb05e13e27ac1cd15385e489a045f2a5d517ee04b61f5244fbaedbe18f7f0640609f1b50d74e739cea432a64b60175b6b31f4101bdeccd7dd7b686c31276	1	0	\\x000000010000000000800003a5f05ce656e18cc8ab25537f654bbde2f045639bb4836e33179664a9f5b4aea1f72707f62ea6ea689ee5dd8855e2796726cb496ab2da6794aab3082639c146dfcd76b0e33a9912f322876697f7d5602db5b8ddfa356b93c579cfd75d397b882ad33345a0cf806a0f1f9e984c8c59bae071b8956dce16537162bc6315b4da1477010001	\\x41382c6aac79c312f294b41314dc08151f2999af6f6c71cc00670c1bdaefd2758ed17293c39e6c08c19dbdd7cef2201528db1ee738dcc396ebd61da770e3d105	1683827475000000	1684432275000000	1747504275000000	1842112275000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
319	\\xe936515d3054db891b01056a8e378993e5185e2d6911077a3e7fcb0b746a242c647d767c399ca28dcd5ca52a9f4489b08d32d27ec70332e8a3eb3b9a65c95a44	1	0	\\x000000010000000000800003b9ca3350050cb762d6e83a08e04cc25fb7c9c30546c02fd8a8c72a2ddaecb844a930e4c861a0d412217f0d5bc7a546ce7017962dd052150c39105a73243e5a403e0792f8f09a92384f0327056c49f910957fbfaa0538055c4fb29256915d9a42ae349d3509b60392c617b6401f450ef737323b86473109155d741171823ee387010001	\\xee644ce1ab2c5bcd5d7954de898f7a8e91dd6b6eeb9773aac19c3d4bd565053962b7b5eb8320e44eb8527ef0bdb31850a7587bc2abb21bcb2298674530646e06	1689267975000000	1689872775000000	1752944775000000	1847552775000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
320	\\xea4e969f01f93eab1b5b5f6003111f13dd5d0038edd8452c7749dffde5e016ccfc112572370745095042af02df059e5351f6d9c1f9776aa9b439eca535bf2d47	1	0	\\x000000010000000000800003bc5aca721f6bee671d3610264cfb063b775d5724a62e8c0d9d5bfa895e5532b89166ed001a7a0f826cb31ced0d00ba398f4d23dc0c9e1dcb19270173c4eea641ac3376a2eb2bfed9d171a8788416257d6dd2cdc161731f34b276b3c5c04ae9b7c4cbfa3fff2992ecc3fb675182f7d6962c5063fbb266117c90924f13be17add3010001	\\x0c76ce34de6c0b291e7a00dbcedd654f2648028f64409af7d8e7d05937bbbbfdb29c26fda73c62fcef84597b28d6fea4a79f6c98c1cf6eedafae5d0dd6382505	1672946475000000	1673551275000000	1736623275000000	1831231275000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
321	\\xee3602788d53cfb18d19328d77ae672e37c721e408a37fe5530c6fbc86bddb68e640997314fb33d89ea6e471726125fa840aff1197b22ff186d500e9d58ae24b	1	0	\\x000000010000000000800003984b9b93f74e147d8aa94598418606e7e519ef628ce0b28fc10d92a7274e86072712723ba7d8c0bf20751c475818c2d285b87fe1e85be99cf65ee19ee175aff82359594913ddb44ce9f53d13fd05e326eed4b44970439aa315c3dc61e43fff31f154e59eccbde572371444f2909d0fa52ca06847cc1fb8afe0825fb3770b804f010001	\\x47436da69f7ff652d8d2420c99a94d888a94ff20ffd978a2dddb2cc06a78b5e6b33b6be5b202671210f09b96da4e43bcc7684864a6f575a29a2a853d5f547508	1665087975000000	1665692775000000	1728764775000000	1823372775000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
322	\\xeea23101df6cc76f91e16b5c94dc71c7fe9bfe53126e4a3e95950c2b5700aa939ff231e8082e241a231d355e691c895d94a7c7a1b703b4e3291caadaab738ab0	1	0	\\x000000010000000000800003c9b4c6b05f883f9ecc41590c255a748315c120608ee286e0308c117670099ea6b82c1c2cc873aad2d75787865e7a9ead22b003ecac970211ea4d1ca5cc1b5152ef737b295678f1e319944df1f7cf4bc404db6bc4ef1ddbfe4800dd0052b5893b31d1934f5ce83dfd20ccccafbd176592cf225e179b8ab09c60a3907c6af87709010001	\\x3befea0924cbc95c0f6aee78432a0861dc3385d87efb9ac580ccaefc414158d9e14d6ba3391b4278d1751431c7b6e52ff38649c6e89129ae5e22ed70a74e2a0e	1670528475000000	1671133275000000	1734205275000000	1828813275000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
323	\\xf07e3454421cfa918b71232f7c2147091c839b7f5fe4e7c08230911c3cbfb30321cd3a8b5236f14685826194f117741174a7a9229fc46697174eb4241fb20e3b	1	0	\\x000000010000000000800003b86cbc5d7db8c63324cc2ead35e109956165e6e32def23131359e9231269745c2ed9c688c36cff26b5d5494035417a8a85d36d8f10b96183163a22ee9cb941b31b776186b7e905b68aef868be09ec3a265d07ff8c98b39ffea536297079e980bec853a88c55469f661b9f49f4086017dad69138d3cc2d81a1939335967ad868b010001	\\xad9ac7cf29aaf505303cefd04e25d6c4f64affbce16aa3268cc517f1e6d330a3842484d24f248845398d3aaee7047930a51c6a61d5525e2572803407de2a7407	1668110475000000	1668715275000000	1731787275000000	1826395275000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
324	\\xf016b7a5cb594630c9e0a5fc3a0d35d550fd9d6342a0fb87adee80f28af7ee8c0e5520d04d5ac55d62bd6b46c7053129b583dbc23a4b8a09c4dc215de2724a51	1	0	\\x000000010000000000800003bba41e69c2cde1f0ef97c957ef6dd4b9ba089bd9f8fa06360573bb65c1dff9520f1ac53e6949c0fa4e4630887bba6d69d1a8f288263a9a1a8294e76532297a7f76969710a794c94d38c036dac3f8480bf5430010ae3d69ceafc03d0b5aee4f3bf2c0dad83e56a32b708651bb0980d4e741373c07ed7cb16db890394bbefe6abf010001	\\x7c0ed298f4a2ff2519c32a8f3531e3a348b5da545880ff57ae44fa43c7729013574824998388172dbf949fc99f2d6648a256c599a6f75228e744346b80ab7709	1685036475000000	1685641275000000	1748713275000000	1843321275000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
325	\\xf44643cc37af79f194999753081f094f3142e8f56a2660ac51118844421b83bf2e70758e2b221886d269b0848f7feed707c5efac1ec1c2ab7fc12d4042997a30	1	0	\\x000000010000000000800003a61c3860ed4aab80d50a82989d51b9173f8d30819a405a569d05a43dfd5f7f0ea80c395e3668de603d7f727018e1e13afeea66b8caaa75caf9358450d848f6d65053ebb86cac39a13bf36b1af926a9be641d46f5205a3376afe2ccc26bcfa0ce916368e6592157d2748fd80ce36a834d6d9e35225643018d29c56ef45bdde16f010001	\\x9b079e5a6064315946ff12358eec1aee5acbb76cfcae5400846aa5e330d3bac183eb1316c62d7680ec010ae622b08167fec5ed9a265720b5cfc46ebeddd3d502	1683222975000000	1683827775000000	1746899775000000	1841507775000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
326	\\xf9f6e895cfdb7ae7fac2d4a552ca00ea6594525894642cd52a54d171b1ce172b0d7e4e652e3f26f1306fb690b60f34d023febc462a1e32737a197aca8c31fb57	1	0	\\x000000010000000000800003c30d05e19ead828fdea706803f90fc3d1e5030f1d358ddd100ef80d7d10fb922c1aee2ca6ace0301fb223f0dd9b48ce693f0ecb202c85ff221d2ec28b75b53c0dd4b4e5b3ce0cb49df5e4da11fc3837f05651f25cb971c49f5c37bc4fa79ed6d41ec99ec26f81be3b748fae012626b1938f1f284610dd83313c6e82cb861243f010001	\\x9f83c0c5c2433ee64dc33c9fbf74044f1ee1c4d69845c56dee32bfce4ad25478d8b2f83ed82690f6df0fecb265ab28b852082ca0cc6f176bc27a017780d61f0d	1665087975000000	1665692775000000	1728764775000000	1823372775000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
327	\\xf9c656f15cfdc9da1a7a80375a03981c85072edf093f7f81385f0a3e7284eb3b5a8a1801fa7204507489f95fbed4585ffefce0ecec8a7ac12340cbe041395963	1	0	\\x000000010000000000800003d2b2889c1f31862eb91a888556b6f2812042781ba84b4436c31afca615debf4bdf58abf9183d6ae24842dfb9df97cf830a3d06a49356c815c9eb33d831aea0defce7a736d1fc887019d3ce341fe1de4e23c067bdfcb66bfdc33b3dad857babb22b493df1d8a773a4806f37359a09720d974468ac01c495988615f71fac633faf010001	\\xde97107da5736f747ae4fbd1cf7ada37769e39e42999ed5d59a9e8037d9aa175e2508172b28e08941c8b262159c991546d95d034acdc5784d51a3e47caab4a09	1690476975000000	1691081775000000	1754153775000000	1848761775000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
328	\\xfa8eb4f25b05daa1de557b84f499986123767df4ec2a0b1c3e53165698fe96bc52fe47a5c57a15ce83ad37237c6b6d3b34fba659c4fca3dc60619bd61afc94c6	1	0	\\x000000010000000000800003a94164fbd1a745d6b2a8c07ec2d7bcfffdd15285eb2114a2fb044fc4e52283ab0bddb842b06d39aaf26b870d15ccb021674b4df86095845eacfcb3165bdc8c1ae069aff12da41a0ab338d4f7ec420fde1f4176ace54f1c2b8e7701ae8d3327da37f806b8bbddf2965622bb15a881be93fbcb4afdc0ab00691a276cf1d79314f5010001	\\x3f262834bda0e68a3c16cd50f947a0f8b6203e870c254fa52a53de33365ee1c0bc866bf260c884524054de10aba5bf351fc139786f063512d466674eb9a4d90f	1666296975000000	1666901775000000	1729973775000000	1824581775000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
329	\\x0033d16b8f0d63255366db7df1aee44c45b67a3d823a35a34f70d388eb8927e4903540faafdbf100dd2d710d46f868006da62c9fddf370211ad5ee66919ca872	1	0	\\x000000010000000000800003e7edc72ab250b7abe16431341a053492a8a3d54ebff0551096d986d2b38baf35279fbf5e814d29feeb541ec66284689c23616bf7b7137a65f610a5d968be810a10046e85d2bb3c86aa534d65c4b25c015664c0a532fbf4f1fe86f0528f77a2fc25270372278b6b396421421c3fdddcbcca5749737b7ec4b7231ca2969bd98e9d010001	\\x257f2416f89044002e339834be903701eab16f0523add6a8874a07e302f8ccc86fe22fdee6c4e16a9d94d41fa8d2ad66448b3dbb921355cb27ae87d7c3c08a04	1662065475000000	1662670275000000	1725742275000000	1820350275000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
330	\\x04ff08470c370061254abc396b43f7f6b68c447950e51f38f9b8128d11c66128c757896c356d2a6cf5c0006eaef02a9c81046a32c461d967b8d62edaf493ee72	1	0	\\x000000010000000000800003c9f60575c5045f25cd7ada86d11a68fcea7a751288f161dfa451406a0c567a3a69feb4865473246e348c21751b0229a6c8adcb8e0ade45f0085939127a5b58a69dddf29f63449a5c0f2495b0b331fd515d37f4ce3b2191b4b5258b4f55948c0885802c7f0e3270fcdf4c656f71be8d26381568bb3a573716020ed91d04da0b83010001	\\xae9276d4e1659abe98c9a5d8836565005caf4335053274e3f3790951b38225ae3bc0977f173a7358f6a82c66b75e38a46c8de91a0f419bf7a9f0748396dcdc02	1685036475000000	1685641275000000	1748713275000000	1843321275000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
331	\\x060b1e64a9dcbdb76eb0c82f6555a98dc3e72ed8746ab81d45771953830da1a1d237f9d1493cb90d4276f11492e327a1467f5b5b82c85dd6f81bc0412d851228	1	0	\\x000000010000000000800003d324ee07008bff544ee474e7e5dccf3e6d13bc842006b554f0f26b3153bdae4da7111ae16d6d63840013ba398994370d018489982ca8fa25aecb296e87d7a5dfc6981c11ae7331fa840ad8f280c968423fd55fa19981781329efab22fbedf3844b0dc12dfb6d921b952a5fe5adb07cf3e3f0d895556c3db76714144187cfc3f1010001	\\x792889c948df1009ba3b899a26af0f446333e448db6dad78efcbb9079effc59409599ca9b82161023246901aebada289f3bf6abb5eb6e5cd5dbdc9c8bf6c460b	1684431975000000	1685036775000000	1748108775000000	1842716775000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
332	\\x070b8d711f7550280855b4ff6cd71c3ad3b01f40917ec1e94dd87bb2a45ccffec9546fba1ebef284169a20798427f2dce6e68c32031fa9c4b97fbf3e7d8a8928	1	0	\\x000000010000000000800003cd9b43ee0e182b766f21340d367356ee3692f454e82bb39e6e467b470ec0538a279bae0633508b2b4fb26d476bbc298777faa745101f6a9c63179318674294ac99f91b905fb6baaca3344ba6de9de9ea921d95ada4eee3fb2166a5f127934aaa102639817a3b09be3560c0f9e5539d78da5c34301d22672a1bb4ab80d578cd61010001	\\x7a43cf7fa450d4643b7f885b19298d3fe421117432fbcc5a759fb51994054ecd31890410333a43c3685ea4d69cc8c10c797bcdfa05345cd2ce7833ab6fe98b02	1685640975000000	1686245775000000	1749317775000000	1843925775000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
333	\\x0a930fc3a3b017a5cfa1c9bc906f9de698041fc1e828944edb2c7bdb7b74020e8a886cd9e9bb4e2e75be4e3b371825306d79e696f6476f8e13362be651b533f9	1	0	\\x000000010000000000800003b9cb5a3ac8d76a0a050e1fca49a43df4c659c4f326f96fc6f1a81fa3fe258f480f3fdd843fad5c610cf397541891bd1f576822a8c80b6473b488ec21fa3ce404d04b82a87c3040f1632fe32a84db53b9d9de250e7934de81c4f95608c0111b677ae43c7e7599efc50735b71fb67e65db77cbd46cb2b16d42959636ef59b55be9010001	\\x46d3e940c48c5d3cac2848655ec02b015074bf2ec4e659f7eee150b2a784988285bb1042767122ecca288ee0f5fac4882507b6c928a1a9b86a00da3b6e87d502	1672946475000000	1673551275000000	1736623275000000	1831231275000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
334	\\x0dbb9f8c7aabef38e7f3e784bed528c25e1e72929c347a9956b2b46d8a12d3dd876539f2f0ab8a2434e2f9805115bbd5da755f6c638ba953572c0213794b1bcf	1	0	\\x000000010000000000800003d896a7a7e7ebabf2f3eed46568e16443005471ad17ba791a94ad9f603ad814fba66f31ce4757d5789b02a1ac1fb1a2d9ac72a6c5f917012fb21036fb974935541da8311ebe0c23bf21d5f6cab9cf594aa22214bcc9c3b9ee8a17ff1c72afac9646125d370def55ca99452dee72d0aba689415a3be76d20f8fa3cc39cb25a6c87010001	\\x10dcc66f7238a61dc8bcb03f072e72f0b1ada11885163aa708569e1af6538c10ad0a0ec29de959cdbb9a4cf796dcdbd8303a0ce4c22001176b2a958c6a9e1e0b	1661460975000000	1662065775000000	1725137775000000	1819745775000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
335	\\x111b2af74e0334da2db0a5032b15f1a9a4090861343d220dd4fc37fc478458e3c5e80a0b266497a8fb86f9ce6ad52933e57d8a9d0fd7d73d7eca7f4346d15789	1	0	\\x000000010000000000800003af1a41490678366e09de9b26eb7a884bd2c46f5b39e7edecbf8c4d90386e195786e0497eaec9be729e154485f19128973ac3ab0fb37328f74159b84bd7940e2cc87f98591c9ad462b93609906def5ea7eb9d8e4b86a490fdc4ba90bf382b67ef3c4c4ac362d0c26f9a510b912c965c9e57695ee887a31c48d03466b6e02b2409010001	\\xcb4bff1bcd36e4bee25ebc01ab26aacbb22212c0e1a55691385a142c1f276a5320971e7f1d7ce0cd9acad9fa4e7cc14c0f0dfeee872932c5a51edd761c25550a	1682013975000000	1682618775000000	1745690775000000	1840298775000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
336	\\x129b8048a030bd559a4fc6bf4379c3494187223d719cf599ae51d074780f48cdc35d5630ae24dfd375d9e61352434d7a69fd47299a16163c5f21f0f2e16995b0	1	0	\\x000000010000000000800003d739fb4703883d17c50d63530c6df4387fac67f963b1298ee8c9f6c4f86736ed75c1923c27ca854489018b9f35c8a0308891fe5844b531a4fa65ca79a48e78bea1ef55bc2648707e7ee4d5a842faed9c542242e724916f8ed16003f13c0484ed3cbe5b0ccd9c3d42ba74f905ec3f688126d225ce140ea820e5249ccb0d9302b9010001	\\xa519ee593e9a4bc3b3b7d582b2a94e80f2fd72aa7c40e0ab9a6d0dc8c91e6328e0e66aff3203bc8bf9d86203732b1223980bdd9bccc0e6e76368119f6a508c0a	1660251975000000	1660856775000000	1723928775000000	1818536775000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
337	\\x127bf3d21ebe09006dcc25213a85788c7a20a07812d227547db33e787604e0ca82599b6c9bf78afbeb2d15f517e0547f16e7930ee0f64843a0eb64d26b1f2c7c	1	0	\\x000000010000000000800003d5355a6b7c087cef07e4a03f55d0d5aa2ad4c5570a2983f0734546006cfaa38f6acfd0b51fda038875fc39b7a5870f50bc18dcfca1e52a10af68daa96a4e92ad372c50e85beeaac7a4f8d70a0a4c5706942d6ac0af45d8a0c327ff65b9154e5d0cdd8ac562cc9b73b7c750273309c7c27868676e5e938556dde23f8d0b6efda9010001	\\x8499b43fd715451d7e8f1a392a126b0db0ab6c4b599a39ce208fedbbbdfdd41d6606f2107bd890d867fc23a8d091db4fb5f03bae55096283324d6f0c1aabb409	1674155475000000	1674760275000000	1737832275000000	1832440275000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
338	\\x146f3f286cfd7d4c78494638a86cfc74ef8776f91420907ca24920ba793ba46d7d662109783dd9e7592f5314f6dade1a6dbe4e6d0a03ad116798b925cb8895ae	1	0	\\x000000010000000000800003a1b87248a73dcc002a4864bd1216249888226f71f43669f1499e9f09128f16fadd8275d496f94b2275ef10306168df32ccaea72716348150e25d9830e1c072c62dbe509a640a2e1fab7c159dca739f4b70efb72dba0d4a52d4c4bb21a9f17136617e1a976822f42767bb61e77d1a7a6b0d00de141846b93a6c6377d27c3544a5010001	\\x474289ad245f27d13aa0f30a2403ddb7a8c488867fdc4c23ebcbeab680f118287a4db381f73c45d6cf03f65a7ef3a24d1b0067de594cfcc4216b74f8ef055c02	1666901475000000	1667506275000000	1730578275000000	1825186275000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
339	\\x19df0a3468a712f2406bc7514dad297c1772edf3e1a25057953740a9ad5bb022207ad45abdcc7ddb3dc54a59d4a788991646ffb4a4f8654f6cc6cbe5182e5ba7	1	0	\\x000000010000000000800003ccff2737932b2854e0cbd0195f2046fbd9b6c97c9aa5b9071c43d3856b2fd3e880f27a7eaf912da06e050c1bf5ac1bbc633f615d3ded0771629c050ce8366fe52043a84ab4bd300d705ac2beecfd13fca96cdfbfc590089fcebce1b692b4904bfd0929b01fd2ceccca81e9c38133d161ba96228842e39fe3106d1e6b6cb2d7bb010001	\\x13ccfca759f4dcc27cfe92a2e22d5053c30dee693c50385554d3ea296c7c0926e6e988a01ccaa88aa7917cdf6d2af3b0157c45b911b44d2f89c0839b5dd1e601	1676573475000000	1677178275000000	1740250275000000	1834858275000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
340	\\x1ab3cd56cb99887862cbb3dde24bd46a9188b297615ba0de0a55a3e1686219bda31bebdcd3a85bd8207a546a656d32e1d16d059e1644325e6f135e7c8ce6daff	1	0	\\x000000010000000000800003e8e1b346871d06710352c78f32c3e9d0e622ed33f6efc5a84cb9a76aa9bd924c6ceb8c5ccffc38378f3790591c2ad1257eb783ef6b0f22d7aabc734d325be3bdc83865c18ba00813a2124f494dc4c0147271736c9ddbfd5b0e4e7431df906ef5a0267748db391e11b73cd5195b08168161773ad94f283cc215c541368dff6629010001	\\xf533e6f36af56e66a9b130d2bdee76853749cbd1f611d69910bdbed64a244a70a181028f252a358d6c8b4acaf43afaeb1545f025e9962b537326e6d60c0eba04	1674759975000000	1675364775000000	1738436775000000	1833044775000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
341	\\x1b3fe4b8a7d75c79f80a534d57b8330bac7dc575c4192e4b8d8ab9454f4aedddd2f4d5375eb073cf8276d3edcc89536a4acafde2e1a32673760e2ae6f1dbf92c	1	0	\\x000000010000000000800003cddb1778b2a5ce8c3c514cd20b82ea8f3e5f65fed2a3c143bda89417ce72360119a321ef034ad43dc473d107e1f3026aea8bd29ed0bc1494c546ffee6fab362bb3fcc3c3ba0f3f121627ef4e5fc3f0e87e3d1a66f31d3dfdfd772aed0ad0347348e71dcb8a45fd3930299391fd3f55beb50f5e1d3d28bc81aec9775839a992d5010001	\\xf09226afde6225fe4cf514d4d6df6105515c78b3138556d9202f0408bb2067f7a9413306c357216e35b49689cb6b86c6bf8d7a8b1c56cf30ba92127bd5487009	1664483475000000	1665088275000000	1728160275000000	1822768275000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
342	\\x1e0b26527188cb17abe3615bedafce82c7c220d3ee604cfea904cae0efc16be6908646b8197486d1f3aca60204058db8f8c46f8cf6d7c52059825c59500d26c0	1	0	\\x000000010000000000800003afbc80c81b67ffeea1abf3a2fb234c650c84d496b29336e2763dac81f10c8393fc69c3769e3d4f859112d3ab7537f2bb4d0247548f1da16baaad74ec5909f3c681416256b1e30cbcdad94601854caac82a8ec819ba4142530f942bb002e2e24d56125a59e5426b3e94e9e559c52dbe15800f2fd23c3e3d3e568bac43b35e3337010001	\\xfeae471709ec835a92a0284054432b5cadd026fccf2167200ff064132915570ec95e5fa0783ab4d158ff7ccf3330b6d55193fd3ce8d691795db1bf06fe74df03	1676573475000000	1677178275000000	1740250275000000	1834858275000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
343	\\x1f93079b32b4bf42c1d7863cb8d6720ff7c5e2f5b29e487ee9d155d069f71a75d804b81136eb68a871eb8e7fdb7d0038105200def6bba7e8a2fbe6d60f5333a7	1	0	\\x000000010000000000800003c8ff74cd7f50b45f4d6a85478b453932af0b87918c833b25cdd79ec9f98c66e50728a5544e92ff013f3bd30b2f016ad8c335b45437db73d448fe3ad8563bd3756a5839a1703b2d4131a95f44f803ff47d15e2088a46b53a0caaed908e72980d09911531ee5096eb91b28598c3bb5306683b90964308bd2ee02213c5a983feec1010001	\\xc35c76bb3ac44fd866a9b4e1e6dd495c30498fb84eb2a62883e6e16509f477f93d768397c91ac4781880e4b719b5cccbca6ddddc8fbf95e7ba2405da18d6d502	1673550975000000	1674155775000000	1737227775000000	1831835775000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
344	\\x1f533872d26712255eb6cdd3e9f9af7faf242f414c22e0a450362fc33e33374a5d411cf850095068cce7598be1f3ab1f8c98cb82d9a7195e8dd0b20a1f73ae0a	1	0	\\x0000000100000000008000039f13563ba310f5b1edd26dc487b869f4e6a52bb35e3b61a20d1eb9e04791969ab7fdf0307a10e7c64cd9c3d099d45af08e507bc020c67d70b3a4512f41abdee998c192ab633739b1aec78026ab37b836d25c218d89ab0fa0de413eaf99a87caddc9c4662a479b94ecbaf05cd8ecdc61e588d3472cc0cf701f3407da65b03b97b010001	\\xd8f4970f5428dc9c05804c1cece262f3fcc6909523f0b65940215a035bdc1d538438d9461c53f746d14c70bb1c88be635fe39491b55be9b79ec2dab45286f70d	1671132975000000	1671737775000000	1734809775000000	1829417775000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
345	\\x267becc2db8b5aa8ca0eb7cd3c51c509921e61c806d49ed9574bcf6a4bec4d95376611d4ac684baae9e0e560237bff9aeded1c7af6fd0879cef22a16557afea0	1	0	\\x000000010000000000800003e7cbaec6b26117212c16dbbbf69910dfd0d31b2e018fb7f8c327d3320ac74b1cfd85feba0d5a8279335facfeacba6b7cd6300cfe13ed1061c970de5f2d4172c22b21562c11d419026bb408ea97cb94c2ed76ef85717c8ade6833336997a48d53a9f452e9313733ee899779fee6720393069a9f8b101426a3ab6347facca63f6b010001	\\xa3c5be8c407711e4adf454ebc232085ccc9553997a5d00a8644e2ca2e81254225d51c7b9af05e6f5131e78772160a1bae4d86976d04f4bb105da80b60e2cfc02	1675968975000000	1676573775000000	1739645775000000	1834253775000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
346	\\x274f162b62b4c7ff02264d5b091465f623ff50df1692f5c52906aa8894eec854a71f60888e23922da477f2b8f54b2324a220389261d33eb67a999dea2ca1ae48	1	0	\\x000000010000000000800003bf1fa3bea62286ad757807b823f63ccb7f93745cd7063a832a2f98472197b02aeec372be73eee069ce8e96fa17fb624cc560f6684d4d9188461e72353bc06c254b577f6c1a3cb0be484e92c162888aacce1f230d7c267caae573a2933b42da7e8d62c1061270fff3606f099419251f2bde4b8ca96397a3bb323b58590960e25b010001	\\x3579057ee36a27fbff3833b811ac2badb47e176ff3fe63f25685ec35724f3bfb2789399ec1ff2c003e83cd96700165003d32e4d88bf6069e0e22246568b54f06	1660251975000000	1660856775000000	1723928775000000	1818536775000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
347	\\x2a37408303db7e213247ae6fed51baae8dbdaa4ab7e67cc0b47c0dc6b48758b83f4536c5cc08af45ab88fdcd065c30ab34a62224918780a872beabeb6b740dcb	1	0	\\x000000010000000000800003f0076a5272e88e45379e21370feabac7799b58bee4f7e7433939263e7efbbfb81aa12f4bd3ddac329f552eaffc2e81317f506ebf2a0e02f74a64424c555b08b7325fe4d46b051860f59d5e969fb514659a789a1175a248e3793ced82d2d7ffad6315903909dc405bb6e069a80281774e7d5d69588b7c98f7bc4da5de9319ebab010001	\\x46d96501b731d7f1231e9493978a7c8828e35975b9d3344366bdbaa53fcfa820fa89fb3360fd74321c956a040fd35f719a4e75b9d3a790f4de2c85333a932707	1685036475000000	1685641275000000	1748713275000000	1843321275000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
348	\\x2def4b22e7b0e95dedb6e3c3fbe3499f9f1d1b153b8a41ddf64642dbd393daa4109f378fc1f2e67190d2f101df6b20bdd83ccf55c5d28c525b653403836ee3ff	1	0	\\x000000010000000000800003ced24994be28458a376952db5749afdbed7afbd4e4c38ad811c1bd6f02bd3835a57d5e49365e06c68bda46b12853ab802170960b240538ea00932e6579e6cee90579b3bd107e1b36f91bf6bb951d33a2b34a70552da318799b21d4c01490e278ad203f0c0ae328f5e8abac9dad74abb7342a236a1bf267907992b76c54d38d6f010001	\\x39a2e7cb0b0b255891e78b8a2415acf7e60812e2aef31c9b07796a6a0ddddb0c0e157225f3fb3a77283908a49e829971fb5e359162bc99bc98f8d2f7d511290b	1674155475000000	1674760275000000	1737832275000000	1832440275000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
349	\\x309b035828bcdbe2becc031aad7fe14856a8bf900a6db98fd2b4105e0138592c4fdb708a76b92bd7a8ea7779879233e670bf9158794d00e8e8b804cf2191e1af	1	0	\\x000000010000000000800003b2618eb24d731e1b6aabf861fec200a9dcbd9cae6d26ca36229e7ead1d38ac41caf864c2e71c441351f6158a9ba7b1f03f1c1bda26840d7137397f637d2d7636ddae74e9b68b906a0f43458153061848d9e4af7f630e97254293ed721e86a7067738a8f21edfd28eca7d5c4e2d0a8db41a95b4d6598b469933726db38d9dfea7010001	\\x00983ebbe44920b293a3cbd573525c578c4629a947d6700f44f28ffd4fb5d0526c71cd512074a848e5dccb716aed5bc009ff9a834d670d1583eba85a307b6409	1661460975000000	1662065775000000	1725137775000000	1819745775000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
350	\\x30fbcefed71790750d967cd50137354e88d06ad033f5cf2777817a35170eeeec1339d371ed4652a190c8979e1a722da7d0244d772af482fbe68a7c226c0dff5b	1	0	\\x000000010000000000800003d4d1615071eda3043d91529b71ae5a9742efacbdbe80374e7903228ec687e1a1b84903fedee15c12ac086f0c9b0d898949f002bf2589d750f938ec7db6435c49ae0c02c6f7697f491f4069e5869c1a27cf20ac3982943955ff97d813f6effc99f6455991673281852e3cf4175681dd5063a160e553746d7cf363123c2c35fe63010001	\\x44d4cd0d0cabb634b4b012c609aeb10c3fe9c7e45956a154658a48491ab2157dab3216e98f18a05610bc1955c643d739d3f578627f5929063b11eccb3abd600d	1677782475000000	1678387275000000	1741459275000000	1836067275000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
351	\\x30634599b703b7c03fed5fecce4d7bde0c0ec92d8801690a4bb14082e33f6c7a83037e3133088b98c68ee58b4ec590498f0ace3be0d82a86e92b07925eee66e9	1	0	\\x000000010000000000800003d81fa62e00eda20c0a8a75564470c8d2cd22ddb8b50f743d7ac9955be676d6da023a3cd6529554da61900ee0b3a1b466f2eb59942d655a52d2727b38a3f2c6e69256535aad4e4f9ee9e877b15a03ac66efbaa36e85c385adfd5d7316a817e2c44985bcdc3e43467d6a897fd2abec6b3489cc3e5a1053d8accc4dd206320eed59010001	\\x14427331eb2a94608430c392effde50700c5d0be1cba36105252d5b09ab2044f1af75dff8790be52db06f13d0f1e1caa68817e6a99eb1025d1108a299cb17907	1674155475000000	1674760275000000	1737832275000000	1832440275000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
352	\\x318705b897daca2cf57ac720919769970fbfe2f5d7c23cf43736bd73c732514417efb0e4317e817fe6c63c5cee605aef8a1c2d8bb0ac00d7ebf7517d31064d44	1	0	\\x000000010000000000800003d3a62fc1f6919b08d625b58767dc5b8aac0baa9dd7032409a3088c760efc2e9fd1a1f70a5256efe41e04ef1e65baf16809de1369bdc391147344aec21b29e5427f73bf157d86225d28e079d605eb64ffe5786d5e918afe2a93b2462523b23ce61002b4af81e6aac3231c58adeeb5ab459cdaa2a22ad53f51c63d9783aca3d915010001	\\x1081d59403f6ab4e1f46dd8220c58b735d7b78d299eda91638d26a184a90a792febbe4aa5a5911e2d613543a7f10e676990e6a3e855068813195cf1af1faf40a	1669923975000000	1670528775000000	1733600775000000	1828208775000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
353	\\x320f89d249e721506947590d34b14f2df7d925f817018f0ba7690b613685428b21b27c3f7cc2904b153f882ccc62912698797181737bc78f3798ff4e221a8c4f	1	0	\\x000000010000000000800003b11dfc0b17c69a7ab53bd804bb66c2f35ff2030e7084f90725dda5e2d6be4d2a8f2827b0467f215adc2e5628ee844d909348f66e3a4414a9273fd2012089f308c82823986cc27df3b47861afcc68b12b63fba8f085006ca6ebd2957fa89ded40de6b81f548a2ff4f9fc1647db5d4a7cff52e0abfcd4e9ad560ab4f9277c0dc4b010001	\\xb83cdd8fa3cb074b2f14da32e915a9d7639a489d9dea8c9020ffb662b743804143e1ffa3ff69bf49e73f96fe104502d196d02aac827c72e012817c7f783fe50c	1682618475000000	1683223275000000	1746295275000000	1840903275000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
354	\\x334fa2cec4b537e48fc80a1109b2723328b1fc1e1b38d450b4fbfc14ca63782435d88cdcba51e4f1d4d2c2cd88763d0a409f1a41a15bd901c67abb46646c90ac	1	0	\\x000000010000000000800003a9eebd75bcfad6e41ae8d033c02405c329213a48bc98ecdce49312670cc4c13332481b969c8b5bbcb0af86f6da4c94a2edbac635a6da107cce69a8be8f2d194b7ad96d49fec5131227847534b45aab0ddd87a368f2cb53ccab20d0a859b1cf8bf84b5195384791682b0b0fff5ca28b7271486bc3fa517f342bde98de5936c18b010001	\\x14755ed5b5c6f5ed1cf9e79b0b095fb6cdc098378d5551b76a07839bd1d7ef362d71bb3efbae9c123d54042138350c93dbbb64fa23b6a19feb78934efc286e07	1689872475000000	1690477275000000	1753549275000000	1848157275000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
355	\\x34836154fd1e75cfecb7965b3381a66671ff1b172e1521676129d83389ad6860459f5cc100ddedb1bb7b17b52e85b0a434807eeba1f2c2852339104d42ba14bf	1	0	\\x000000010000000000800003abc2f69026c4bedc61d25837a24a2a97f3128eb821941786c491ddf5d414e67efdf95dfe26009de155596daf772f496fcf6f63ca3acb0bfa610d551dac2ed12e17f4a02aa91e647effa393a565cbeb3681458dad152a221b85704a458e766d0bbb11f63a5e1f9eca1711c0ba1281a9fc9715f5bc9c6777edc2a07b70eb6fe259010001	\\xc8567591fff0da19f40febef5706a9b08f9539520613ba90d7651159d09c5f4ae43f8a38005af8ba398e463fd731c4fb2039c1627891046c26bd6cdbaa98c90c	1665087975000000	1665692775000000	1728764775000000	1823372775000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
356	\\x364bcff3ad9db34aecbec0bebd71cfdd38d2679429919ab8086058e72ac6716337d5d301c9361a591017bfefe22acf7ba7a98d53ceb05258ed356266f28ba7f7	1	0	\\x000000010000000000800003ab48217dd3ecc67838083f7826811cd3e5a6b0c5825f552a5b240f02e0195aa2cb213574c71a1b4eb59c97b7b35ce1b5250ee4bf107768f7dd34cee81a359c7b655a4d181c097d38ba6f153e10906822d42d8e8f949ac16a454f9ab7fd21e88dab3322ef5cf3adf79dc8de571e7237df94dcafa9cb45fbcf8038d8913c183cb5010001	\\x1715cab37ff5723a704cdd02e03c4f4f1f5db9291c039bed88e9c3d3f232a26a9c6b9890d23c8aa0bdb09afc80467c1c39809f2c11bd03f4cd4b5669f6b78a0f	1677177975000000	1677782775000000	1740854775000000	1835462775000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
357	\\x3827011bb8ff78897f418377a6ac9b1c5d38a6bb05e658258aba64a92e93f918576732e86411c74a71f8a1a6482571379906ffe034d97c30902478d2556e3815	1	0	\\x000000010000000000800003bdbfcd0e77af55200b97c9e3ae7e369d8c37391b10c7e5ee3007f8350bb6fb3b1e098b70cea602075a9164192a9395b0b439bd7a3276cc15d981f768dde4494e20e207bd8ba714fea56d08369d7b552ef56a13e626ecb2cc4937fad1e18a4e6314d71605b824c9807a2fd59b37a857954ffc5ad77bc65ce628de976e5888db0b010001	\\x01d1eeabdadd24461fbcfee987d39ec8ac6652fbf7731300acf2b59f4b69aff3d14985f9fbe06024067ee0e91cdedc4ab92a22103b592b5a8a6f9cb2f1641c09	1666296975000000	1666901775000000	1729973775000000	1824581775000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
358	\\x3a5b23a245296e315114d4dd8e6a564901f0df9b7aaf03add9d9dfe55b20c6c484e2766fdc6b1a5544bcf3d0fe79d7b4b9e61dacaec1842bb9567b4f13bbab2b	1	0	\\x000000010000000000800003aebadbfc68ce3bedc8549fd5bf78fd621b47636e072e27838b2e97485c92027a80fa3e7e52f231ec1f237a3dc22e52fc9224b2211594f6de3fe82ce818d9483bced0fd9dbc93e9ffa40ced61874a890df9a648dfcb968ec213cbd3e9b4ed93ef44acbfb4f1133fd9ea83ccef5e25d68a2c9d105cb5f2a88df33d3a7c25db93a5010001	\\x97dedaba71b1ee4a8b6a2396a88e9c791e3653f8edb8874d3e4b454fb8b06fb9f0c31a6e69511d2de914016d5c95bc1e4e6b6e013754e871295a5fcb8bfc0e02	1680200475000000	1680805275000000	1743877275000000	1838485275000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
359	\\x3a670761db3ca6cc41e3c1f356e352c03751995fca525d62169fe83f4ced753cf626cd6b1be90047e3c2eae348f1b4cff1a14466679d33d48db0d084070800ca	1	0	\\x000000010000000000800003d1d3169e4af13d8aaef5723c8fa94b4830dc3d97a1eb38d2344352d476bf8f20056b08c5972d791e7f51ff4ca8ca874ef5b487a7dd48822a4ea10bde51775db773ed75a59f617732c7826ebce5bf6cb1ae5c5b0cbeadf040283031d6e5a49017fb2a3a982eaaeb1bab88fc14a1ca462865b4a58ecee173580354681996a8d39f010001	\\x22522a407b3b319fea55d2ffa9e03c3e21ea31dbc2f24b518191930f42f8e2915964b383646d5b21df609a9c5f8af69e61bc59bec1476de91f69f7bf1e4df10d	1688663475000000	1689268275000000	1752340275000000	1846948275000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
360	\\x3d23204835d65f1c1cfc837fc0be787b5b42609f9d3a23ade80dc0c5743d98393f426d5cff800c9ab4cf9d15b2d1de50978865024090237ed7b3ceb999023f37	1	0	\\x000000010000000000800003ccc9c1261b5bc7716867545c01e084a6abc295e532092830e7639798c413816ec8baabd8583b04f90aa3f3286901c49cb1a1f19a18e2ab9c6d970fde053747fa1b37991465ce431440d17ec5abeb98e0d7f76097fa040727dc9c2c655d80937e747da454e9b3f98610c87de59df7e2ae3954109e9ee26eb8fae82261b246a4eb010001	\\x3beee05bb1dc804b595caf6c84664acce1596881c69922e6fdf148a3df1e8154c7c3e329d1cef776dffd3ca6bacd31c9031a5bb006a962e743f51e12cc26d600	1678991475000000	1679596275000000	1742668275000000	1837276275000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
361	\\x42271e3fbf420c42ad5190666eeeff60ea689c02ce555dc23ddc3668dafcccd718b581660a01b0ed3f82bf5682563b2c2d3d7727c2ab8d3f8d548eb9356d64e2	1	0	\\x000000010000000000800003ab6df71574390c6a83787bec34c110acd87570c28b8860d6ab99b53d12056fd927b9d07cb64d81cd2f493e62da37d6e635ff8ec847fdfaa5031ffc5d001f80c54ddf32ccdf146f93dded94679a4472a590b380b0ac38d93cdfab65f98afa9e8df0abef440e0c2caacfb44d314f557467ba85d6973dffd9738f3b3036596c2547010001	\\x75ca753f4c959fd853902e3baf7c65e45287c9efd4121dde09d9563a9412151ee5fa2ad6006727e4b035afee26ebd1c7ed076bf784173310d5c198732be6f300	1690476975000000	1691081775000000	1754153775000000	1848761775000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
362	\\x421f129e4102f695c953d0f5dd9179b2762497caf764aaf3eabcb9e3670a720d9bb4752ab15afd7e49ad798d083222361e51893108b2cba9c56b02566a3df3b1	1	0	\\x000000010000000000800003df1e276c8059c557b4ca34d20026dc6f201ea769806b5fef0a256e906a98176a6db71669b523167ab26acfee158e28c06b312946f6828344b17ef28065ba09e32dae43c93c8eb08e9296942bf1228ec6ee62176ff88b6f9c7f75d576692b70dc140b4bfb5c6dde08adcd86567f79803327249c9df68e8017650945605e1c50e9010001	\\x02b2e0000af55ddcbbeab17e4e12006e4f3a44e90524101f39b00299c87586f8bc82ea7b5d5f93b6ac51b38a71a2c92e17bc2cc247448a95d56ef6fffa252801	1689267975000000	1689872775000000	1752944775000000	1847552775000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
363	\\x43ff8e5b60c2246332b8a77de39cf70756f0ab6b4bafda64010a179924b4da35706e77f32c0ebcebe25bfc77313880f8e99a5df0fed7b975ba2077af2525461d	1	0	\\x000000010000000000800003cef50ae893d8e42bb5788d7169b12542503b384409c1b708ced3e38f3ce07e11bd7263885bd23d46ae0e0abb834d3ab2903dbf62b814e010b131a84ad21e683e951f1411075f8fd8e0d938ef78739279573c401fd6c7915f6e56b8b3145524cdbaf42497d300030c886645928bf28f8aa97153daa9fb251bb41758d4fdafa651010001	\\x1edcaa69792d2ffa1cc2e0ba65797aef2d1fb10435f70124ebf1f957dd9074a21738e0c399b9b85bc724147ac49f564ff8443af57b0fe2c18ce9585131bd7b0f	1675968975000000	1676573775000000	1739645775000000	1834253775000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
364	\\x48cfa19a4c6d7bace90178601709932ce1c70c52c0741d59496ecfbb8099420273956fc7318aafbe0338d5e54233d2ee5905ca3557ff59903318205e25b4ba61	1	0	\\x000000010000000000800003bfa97fe3a5551c311ec69d7ff015cd6d06a431d03c4da8ee30c423994e5e3c867a78ba0bda65c87e079c27708cb82ca2c1e81ffbfe04c998650474b16ac7c81b2b44a1835eb91cfa088a109696083a93e38fab417faf1212939f10e3073dcaa2347f0c5bcbcdf818eff68353702b7aeaa996adf591bcb01d28fb6906d23bcb3b010001	\\x3f2cb919e22fc228fc397982cd54d7ce39de1cea7224420e4edcf7b46df09fa66b4f379021cd76937384deacabc65999d9724fac23fe064acfc9bb511b151409	1675364475000000	1675969275000000	1739041275000000	1833649275000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
365	\\x49e7ba916d77819bdf85b555a7ec37fe72cc2c28057c3befacb5f6c2230bf3ab2336a83fb7d986e56b7ff9e7ee685ae1d15448f784b155dd5b95f39156321210	1	0	\\x000000010000000000800003c2b22b5642cd9508119a5c27f9e31db9e79d3adf843cc2480b7e7bf231d9c9a64c859ce8711cebbad8f3e730378a055ab27974fe555eec41f981f8c59706885b84afa6a28b7bd1108ee85c50acb40a5500047c28ea658ec77392e44ec7125a498da456e75d0c617bdad53f2c062ee984d2344b6d6a9f2f773abd0f692b64dabf010001	\\x0dc941d89508cc703bc0d1074ce46a692c3f05a7a9be1a148e73b8ee17029fd1dce5c57f3e76e6655b27cc537523a7d3ebeb78809a199c89755846748a77bc0e	1674759975000000	1675364775000000	1738436775000000	1833044775000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
366	\\x4d23726e64dba08cca08072118f49779626b8b03f1769d055eeef0d4936af72ee2c5c725ee99c3d08715bcbcb8ec923af96675d1ba9eb9dd0b158f4840a1300f	1	0	\\x000000010000000000800003ca1cb7f432b376bdfbfe19d52674d3f30672a010475af79da959baa703a728de5a697438cd8e127e212a6db1c0cf3a13ce493910f88c66b83f1c4ed542cc1e19e9f678b251f8a1da01bd54216fe9506127f60b2bfcedfabf7e9751d063b281246c350083e15555a11ad1657106630e990b171c1e58fa0b1099fb966ca8c0edc9010001	\\x8381ba1d04cc19a8f3cdc9752807d12c4c3d4e2632c693be8529c8dd3a8ee9ec50bf1ecfe52ec7b3d2321e1a6ee36b0531e490b9b9eeb29c1a64f5ea1708e609	1663274475000000	1663879275000000	1726951275000000	1821559275000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
367	\\x4f5bb574016fa36f888f36da679ac4b8fb88c9838194bb026650b00d53de71b51aa302006df93459e3957fe5954a426fd320346bb615f255a4603d2e2b922f4d	1	0	\\x000000010000000000800003bf8050bd60ea9c61208296e5e4e30c10788f8d8222b6bb82dcd212c21bfab23e1f5c8fc2b00d2fbd956ac87748e594239aa2ab5d8699540115f9efef2b11aec11d9f4a096855ce73e6a921e4cb9b5382480f1a11799154b0cbf8a58fb5a1af6c33451e8584c718eaef194d51d6652fbbad49b5799a46061615315d0bce874e77010001	\\x511e5ee024734b8eff32c67d475607d9245992bb303c44321daf310dff6e261e8ff5c66b886ed7fbc7e812370dbe84db2a6a0d3574ed0a8e424d2b677be83004	1660251975000000	1660856775000000	1723928775000000	1818536775000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
368	\\x509393128dc90504e1fcdbe9b7fda8a9c4528735d412badb6d9db64ee91b9752360196f52d1bce39ab5016d1ae4fcf42473d6688faafdfd8fb498feb2b91e6a8	1	0	\\x000000010000000000800003d4f61d0b39330014b8232371c14b0d02e44a8bea2f1a7d7562fe317628378f496ff6f6cba2658505c28d1d6305cdadca10a6a9248318e298df803972ad4b8e9c5ac436d1323490c1dabc2fc04378ea8b9b15f0ce31cb52b9164e7fab28ec8193e1d73a9f3a1c3e05c05d9ce40e4cb7ed805b7530163d911866cc65aa7160607b010001	\\xee10b310590fe17aa3dbc8b03c46f309daac6f04279c6184cda019a2bb027203c2b05d0b7eaed0ab0b320b0cc8a22a2954e0f7848eac71f2bfb52ab56bc7d30e	1674759975000000	1675364775000000	1738436775000000	1833044775000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
369	\\x534f10a5c1df73bd4779034ce55df26d23ead02c57f0a1dd50c97b5537598e6ebbb7768ff10a6b6b12c3ab290f469867c710171358d01dbf482af17d26bb8871	1	0	\\x000000010000000000800003c547af10b9791fb76f5b361584de6775102df09f2fb35d1cd049fc765a0bd3d787620582aa7955896882762885c2decc35105e68f0b3ca85e7d5c4b57502033259f4ca9b2be437fc5032b4b5dfb4ef5c50ec6942996252ef7316ad3f58642949ac6fa2a2408e7ec0eee34dbe3882f023e885b4a4d8fdec76977172e6386db69b010001	\\x5aba2110dba4eb5d72840cf36221ba98f30fd4ed07f1ff8017f4ddbf6c4090206ba78da37eed992e4e3322d85fc86d947eb4e119eb7d30813c4bc18b3a4d8709	1680804975000000	1681409775000000	1744481775000000	1839089775000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
370	\\x54fff0a19f3c274544463fd6c727bc695212abb3e75630a046b7052f6a157ba7f0de3d1c1369cf2c31b38d9f90e432ca0533b1940e41e5ed33121e1095c21bcd	1	0	\\x000000010000000000800003f3b7523d53d28a6fac26d4b73ed734936e931e21aa4e039eda98077e93f8ce6b16069b75fa510563c6f56e9832b5eaacf0453fce34338252b1bc762bbfe571fa8b80806ba2439f5582d50ae2cb8dbf1b75cbde3b3ef1f64eed0744511cfd3ee3f4bf7eace221386034ab5b8fb9bde81eb0d718c36ac63a763b893d7c9f1eab8d010001	\\x7c37d13d5aee9cb751514a9d7f1b547e62fc9feac9e11dbcaf3edeea157db332ee5046a9c569b97a300bfa5568c4f99f25566a66a9660582e66bde814c5ec50b	1687454475000000	1688059275000000	1751131275000000	1845739275000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
371	\\x5717a606dfb47b934a7fb5b8e189a6c1e0de25747f4e00a68bcffbdc7d53053970dc88cf116063b5aa3fc38dfd4d0c5d635466b04df7e544d81a2d546ba9efaa	1	0	\\x000000010000000000800003c8bebcfa5944b3411549dc50cee3ee7478e854ab84b7d0bb286ac0f7234bfdc458b65a568428a1674c6ed47b08edee6199684fc8bf99be043e6d38821550e7079d045bf8997649f9ec10a3a3037ab07376e79d34b6ac3a3111b544ab9878532f79b56066f362a48a2a65b7aff75897689c7dbc6f215e8c684794704f233840f3010001	\\xfe4c148630731280928aaa9e11f4062b32d10fae7e950c27851cce3a072eab6b18d96121f08b895c921fe1fe3ab2c58d4c17fc5976192d97ce5e0fe0d02fee0d	1668714975000000	1669319775000000	1732391775000000	1826999775000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
372	\\x5e0b2e60581984f22c4f4c4b54d14a6e512cfcc906d4776b28a1e20147342e190991aef344d9bfcdd654fb0d077046ef3332fd94ac88ef302f0f6e8f4365dfe2	1	0	\\x000000010000000000800003ce53c15a45fbcf40b92ff0f632a142100ea84c6cedd70ab1a0ce533a8f29a39fbb36e309bd9a0bcbeb4802110af86065075cafe1e873471affbbe6e25de8a36eddf10e02b200f7c20bff6f4780250a70b102c1da5e1b9b3a3cf483803b1ee601dea14a29ee923e6094fb4a6ed6d723d0ccd5ff7bd0c4a2ea8a1affc9c00ce559010001	\\xc2a14254e8e97a0e23eea0cf737bd3e08f10ec77a769fe43981ca9ef6476052819eb81e33aebb9b23bb13ab439d5d97a4a707d5c324022201c6eb090bce44105	1683827475000000	1684432275000000	1747504275000000	1842112275000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
373	\\x5e7f9b0cc4b88ee5cf32fa26b8d56610570636222af8b27fbb659c7358e255fdc45c4331fc0627da34e77d4f684ed1b6824deb9ca160fa0248e52eb25212faff	1	0	\\x000000010000000000800003c06ffb83f1bf011d13d0a913c78549ba3cb92fefd5cf5ca386906e99c759e90f1b10ae7b202250dc8f678befdec5af4ec7025ee1a230209b2dbc011b07f42b6536c39bb274036ed87b0433e85825895520517ae26bc79a8ddcfa5be3e1ed74cfd199147a5520e9fcb3371e5d5f278b53a6da3ddc8d12b8bed1564d1465fd0e13010001	\\x037d362a3da47fe350d9ae0922c004640ee82eebc275d5bdd6e0d4479595191c9d1ed7306b17569e5884489b1185c1824c15a47a715db5298f61b15ecdc08f09	1674155475000000	1674760275000000	1737832275000000	1832440275000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
374	\\x648b9a5abeb74186020d618482329414fed52a132501491a35fbf2dc0810b95162ea56851fa2095fd460456d0fef2b7dfe72aa58c176f1b7c241ee1bcf1fefa4	1	0	\\x000000010000000000800003b5bdf5d8add95df81eb069ba460a6eab4745c25d607539fc10b236553302ad17b4c03eb34684b292e57a426457cb9b76c1def27b5130d849d861ea53a9c81b216b6d11ed9cc1b5737072a24ad673eca0b39c10688b861b120b8e1775a2ebf5de92dc12489135f7274f7ffb7f51d9cb9aa98c0f6e3c87e895b4bf37c3560d36e7010001	\\x0f063ab5f5ab00fa889210d088d7707a9f2e39f318701b5b598e5a98254f849c10d95a4266490e637cad9874d0477744e315897d7927546ed0ca8b1c3ca45f03	1681409475000000	1682014275000000	1745086275000000	1839694275000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
375	\\x66837de78fe0c73e9c437cf34fa85882e788c6c748e2e13010aa59ca390e49ff85dc1cd1c79301d1860f89361a2bb5fc2aceacabacf3bed7e61aa07531a9698f	1	0	\\x0000000100000000008000039bca19e826b3a43f6e3c0f89ae255c1adf13bace31be75d4b0d179e04ea9eae40f152019e5795e2d5224d0041b26efebb93f61df0d02e509b12aa1fc1c77942eac9a3f8b36ea770b8f5602e53318adb52446397436be4fcea294f9ed8c63bd024c837972c6d52be5765f1eab530afc4b376894002dcc94f0e8af4f44d8576989010001	\\x012372ad38dc3050e359cedbe337f7b7863083918c1bf866247e58772be751ba7305551632824ef02794eaeb1c86210e888fa82bf683b58779fbd6a688fb7e0c	1673550975000000	1674155775000000	1737227775000000	1831835775000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
376	\\x695bacf5051ce94189a1a559297546c139d5f1727c3ec0560aa4ac4b462e360fd531fe1e38ffaf114034de8bf1f06ed9891b0ae5d07bf0f34ee4a6d01a3e0953	1	0	\\x000000010000000000800003e78364ef109ad080c77fbf10e01c2cf70eb0f0c18bcf20b13754db45e368598d44344890b87a7c4a03f02e6ef14f9424b019cd5983b7604144aaa45aa6b2bf461b9b2ed6be905605eb35cf4fb5e76aef9494c1feeaeaeee44f5221aa55df72cdcfa694302b595ecfe70c581f35ee2cb6f9c88e043861c94e5143648601bc355b010001	\\x547771f830ae65a21ba938925812e52ae245d276c74f2fe2bf8f95249cc95cd2f81997b680315af385d7d6c4f7e1bd58a719a52c979b3b5b71ae3fbca7b1e408	1668110475000000	1668715275000000	1731787275000000	1826395275000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
377	\\x6beb31070f09f35be05c5fd0e1a01eb48fd7e500254097a4d193498f267a18ea96f52452102a5538dc0e97a5b1828e053495d43e7d200e5fcfae2cb2f9b06a5e	1	0	\\x000000010000000000800003ad589de2021c336152b912720ffa1729c2ff190c660916ee2a25f13781f5bfabf7ed83be061effcd7588c16bf7a6580998f5a9cb1a9200aa0b3876e9bc02975481a0924d8c6713e73444d4e9ff4d7ae4c0ff5b93c7745f13eab8876f7c8b67ce69f3720ed03773880924f5a8e1d45408217183e0ace2c83dc6388fd7ee9a7279010001	\\xc93017554b034cd87cd431c9ce64d1783f16d644ae567ab0850cb214680cb3a2dba1da8eb5e235240c33434b972199aeb28e9974c7b976ef2a0ab5ee8f3bd002	1661460975000000	1662065775000000	1725137775000000	1819745775000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
378	\\x6f9f3b4aa6819784d591c6734185bb4ad4a57d16ea025242bd8e7166cdcf8e43340c43d22b37d810c2aa041828f15f0925712d2b1ea3a7edf4c6992039abf23c	1	0	\\x0000000100000000008000039b97435af4f851c3ce42111ca9338a85aedfaedd3bc0bab61ec983a06b2bad3113f09ab7556a270e665713a90930930b781581298c6f478633d4daa90fb81c3ea841ba1d21544fa61e7edf92b3b14ec25fae4d65b01fc2d8573bec0dfaebb200b2565374b78e6323f91269e049e335910109beb9fb0b5d313cf51b3dd34d5ded010001	\\xf3dc5c55a36d9e2a70b5436547a398dd67b3f94006fac366ab8ed1c113e7ad1fe8faae5bbca27aa0cd9aac41f38c7a04aa9d03352d3c9afbe0ff2497fbe1bb07	1665692475000000	1666297275000000	1729369275000000	1823977275000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
379	\\x74bf78df21cd359c9a30ca53484e5d42530ffc5fb37e5528f074f9ca6d57d087ab0781edec64012e3780ee827375d9ca1366102843c64a31a7a5ca51b18eb5b6	1	0	\\x0000000100000000008000039b425dcdd9880001023641e6081671b01f61d06d8149d7885eeb0e5ddb3e3bc3ddbddf12a61814a55a9b3c746fd3eeb12424c88d07d988216bbb75744990b3900b82938f714c690806eb571b92ebbdefa8ac09be10871548c5836e0c56c900a082316e058430db2574113691613782ad1b6966fb9288070902b278e5364494a3010001	\\x600cf4e4ddb930f586f7797cba239dd832fa69df28c5fb410deb2643c6c3138ac31501051b2853aa672024a0f84b28fddb7c11588b9ae27ccc374d26254d570c	1663274475000000	1663879275000000	1726951275000000	1821559275000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
380	\\x79db65ee0160bfdcf5e71344b0cb09b3aa2fcae4eb48df07b83c223a87243119e102bb06da519c0c7a79527fd3d460b5cd0ad0bbfaafa54404902e38a5d5b6d9	1	0	\\x000000010000000000800003b0fc975aff41f68b1977d5850315c6dbf12b9a61ac95e1564aa7a2fd37540a9f27aa6b0fb78d0f6b269ea82aebd52c4e151bba78a59d5641e6c94ec03614453fda16defc03a752b13b42eb87912946a5a1daef41d2f88bd53075a7735f42a299d505ad64660f9962630a2a520f9d8291f3bada76ec72fffe328abe758c6d79ed010001	\\x922d2f9a292916085367faabf440bb3198051476f1684cefd24d0cfa9c20d79be3c013ae880b9bc42e5b8c7502354ccc4eeaaf0a6de10cfaa1de82a09b71a10b	1685640975000000	1686245775000000	1749317775000000	1843925775000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
381	\\x7f97e1affe1bbc0f4afeb6f44a77c5aca551f7eeee82f5fe79eb0a0d8ffe2a7ccc48d7147c643ecce48210034084115003c4325a2843ca816cd5956c7b75fd22	1	0	\\x000000010000000000800003ce930418e547beb6c95c87f7c30c92eca7a170e4f286ce4993352acccd4557b5e3e91701171703cd03832e9f442fa1768f6a194874ec0ce636399f2693e5dd76ac7f5e70bf9da7b4573ba94ce817ed916a16c11fcf39fd98c25b0c0b8ccce5bbe477ce6d50c3a5446877d6c2025cf0a28b06e4a47b26a72ff98cac9fd1b8815b010001	\\x79a945a9b7c31a94aa1ca2ceb931aaedf2b50e842b6463cad3bf7e835501eac006a7447e92d492ad81e4c33f576f9f204b3d953b31a4be6567b7d33f06574c01	1665692475000000	1666297275000000	1729369275000000	1823977275000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
382	\\x804f44d77656ca439d555a82f8242ab4a3f51fe4e8b9de248e461f647ca69506bc3e9df07244dbdfa27bd468d963c90359302b1ba1054b7b04f94e285b04a09c	1	0	\\x000000010000000000800003acbbb2a3c464e517ac5ee91c2b11ec0e0327d1a0bdf7f535e79060ef91ee7e778b74c8cea47412256a62d6c0736c4786b1f8d2d2eb76d25ac41e068ae96ea378f2b80be5324b6b826fe08665d4cd356d634e5bf0a3702ae99f18e3395871aa9f26bcc8862673ef8c543f66254d15c0d778c7144eaa9bcc13c21cda561bd6c8c1010001	\\x5a76dfc298b599446ffd754fa580f038908591a884f31f3c26daf20f34c90129e7e34fe15443ae4a2a0c5936d986dc9caa8f87452662d86cfd4603eb02ec7905	1688058975000000	1688663775000000	1751735775000000	1846343775000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
383	\\x86d7f2d26b77d7c59c01d7f37a7505d670c71ac16f4381ecfd965955b1f7f2d99af4143feafbefd9f1f3b23066d3df60e5bd834c4f5f72215c80b9fb0c41048b	1	0	\\x000000010000000000800003a0fa3b504918d28a32b44b7b2e11ed8f70f60af55833841b50e1371b10fd3321dbc420de8f11a7e2df8b298dc8c590c9a327652b73749baee426df4fc573f56bd14258f8cb0046966b2852f6b42236195dae8a68927f6ed42f6059c45213cd95543efdd47931786ea930c099b6bae12e58e0429f216e9c3e494321780d57e1ed010001	\\x6e57055c2fd5eadd9c2c16d112ad7f0025f87b35bffa4311f0222f942e472c919c773c233e5aa857a8877de154fe18dee5aa10afb6ab786426c03a2b125b890d	1689267975000000	1689872775000000	1752944775000000	1847552775000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
384	\\x8b9bb733b5b6b73a86462d05cd61f582f9db41f5c0aa2dd803086f2171f41777856b38f3eab093a875b595f5d689d8827a2b971647b3d423185e87f48a70c2de	1	0	\\x000000010000000000800003e1201c60990056054152592167767442a655e66d412102492eae6aebab44219eb5fd78a92f336e2c0b3ae6afc4b4d7cae1f32d33ce9a78de7c048b3b16c71206464f4544f87934154a2f1db93abf4f40b27f59060014690f68554ac04a3b13395a75311cdc66eef0cdef05dcedb5ebc6df3003df088cc429f5f2014fbe0bd585010001	\\x28e83ec8e9530774d0a5c1f540b33a45ccab69383b81da623d26d40d2a3b4d4bb7edfd206e9ddb66502b2594d2e33d6d3e3a7d76dfe10ed9fb6d9e6d3cb9ac01	1666901475000000	1667506275000000	1730578275000000	1825186275000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
385	\\x95d37a2595ed3ec72185c2e0722b9880cef5f091b7bcb67d665d1cb4c46b07e83cc5bc6cc73898678f4ab768a9652996b577f06336a56d63697422aaf8fd732d	1	0	\\x000000010000000000800003ceba33db0a64e0336591bff61d6fcfd086e8e8080454386a70bcc3fc3851b654729ad9c8ac0466efcae318f5f0f8573a6ffb7f5a476250bbee9173cb1def4f2e24adf469c836895dfb9ef4e891ff39a1491f09483a302ec5f936f2a36bfa004f3f8419aac7b73c6f3e91d366b6798d2a0370ef342182149f925d491700a6c4ad010001	\\xb2eb494bf46c2286dca927b555d5ca367c6e9eefc9093a6f7b495cd7a052d2ef51d7cb3afa46ad7be566cfc2e5384c868e79a38e0e5ad52151459772a283480a	1683827475000000	1684432275000000	1747504275000000	1842112275000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
386	\\x9dd713cfad0bf56df828f2eb7bbf29b89ddca9e06e267536ef5df0a47f4a22888d342222435ef3ea174755e9f0a5b82693ae8b6678a70acabf5c766df305ae47	1	0	\\x000000010000000000800003d38caa90a7f660ab1248c092c7f4f21f36ed024f84cf2ea75bb256dfc0fbaed00262629935b1bea87e981e214cfc4e91f60fb759808ac6a05e042a8c1a5fd8fed487f7c6e8a26ff725f24cb7c35dcf408ad05dc653d2852013b086ddaa3729c34b507c62a7affe7ed788e67e8ac69c5f359bfbcab36537c8ef77580061a55bc9010001	\\xf48807ffcc988608ece42e359013b2d74da4dc85205b4fea3c7b0212ee4812bb5eaa2c1c045edb66752c3bc1aede5a959574c54ff12eb25ee3b2f2236e5d9b0f	1691685975000000	1692290775000000	1755362775000000	1849970775000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
387	\\x9e533bac17454d15c4193352ee20feff3ac0ec407f82bbde9404b795cc4583fae586dfab154451a80345e79f0131a0481a415c12554287f3e2ebf11d4f92c094	1	0	\\x000000010000000000800003ddf8a1616e98bb7a4ab058f72a8a270c9bc0be552c5292997efa93163ad96dde98f0f5f6da7ef25b505d20a0a7d9141c354a6f2563b68069262c50a1c1940be880716c473ad0a729b84e4f4c438ebaced5c69239887f1e9924bba1ee705b4d69cbcfdcc061adc35f2ed6dac98ba21a19b2e2ce77ea7964a6c34144853177ae35010001	\\x4906f62561fa8ae5255b9f79fa694cc90aeff391678474fa7dbfd3e88fd5e4521e4aff3f7ca810fb6cc987e33283531ce6cacfda044fe8304c6655d276c0ce03	1668110475000000	1668715275000000	1731787275000000	1826395275000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
388	\\xa0d770b3bda0b97cf4418881bf38f16c54a235b34df4d84d3dba9a1cfc33ed058ca51b1aaa2086460a2a255b2935e9b14557ce572c5a93c2aed94b36964be968	1	0	\\x000000010000000000800003e49e9ea967b4e67ed8cfd4e20ffe928362765dd340e31932e64a0a3ac211364251a40e4c94a3a05f562fc04b0698ba19c46f23ef3e363058c1bdf6aa67ef90450a8bc3100cb30a30f3fe2e2cb7cb30b166850c1d116dc24f0720d6e0e2e27cf4c6f3b78fea3c85f33e0ea404852ef8763af5fcf7f4057a868217b2ac6fe4a39b010001	\\xc513db67b5e28f206e03e199e656d18793b789efcd75b66fe053ae896889f666f0349bdd00fcff8b11705f12e51e395ca659322fdda18710a31880f7e386f90d	1669319475000000	1669924275000000	1732996275000000	1827604275000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
389	\\xa0db8ddb1f269c24835cadf42a0b2c231e80190a13c30a910e8ee7badf2a8685e714944a46831a63af1cee4950f7f948b9c730c6d3a387f24a4da89522f5c6cf	1	0	\\x000000010000000000800003a7ccc2843974894b67dad6327e8efc08857e0b90760192fd704c6deadfeae99b3070e16180c5c301f4fed10e1494e7cb9849455a0b420a2e3f762c2df7115d237c20c25834266b8d6adbcc910cf24db4dc54ce71d555a53fbe3170db15e479603f10e5543259c77b770d5b456617823537d555ae86e6fd53c746244ad30f43cf010001	\\x15796f4096394f4ff008af15644949cd854ff839c1aa43241b77d6de433705e88d1a958d60fd8490424d802279dc5c33e42c06c169a77ce32b12c5752bfa1205	1684431975000000	1685036775000000	1748108775000000	1842716775000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
390	\\xa077380affd4a0105956141fe4372a246c58fbb77a5a1045da9949798b05d326ddf0fb3c98b46a473c79cca5275d45cc63fb12c153de3f369ac32df730aca769	1	0	\\x000000010000000000800003c19b5335bf15a63309a1a86e33fb04a797761e24b803a58e88270f1b301cc7aed5a70261fa2b1dc66a77f0f0bae3157bd6d4f0e1d25c2d98273ae05432d88fc034b557235fa96287a0caf1b37b527c3ff39d7cb5f34384ebc9443c78f628e0c4dc60d3eaae62b95f66a60fdeae8897a910e89722b5a89dad84e2894bde06b52b010001	\\xe68bfcf2c4e1d7700c723317adf52218a7b7d49c1513a0ddd335133d8879fbb3c97e8de14ee277f1d3ffe9cf4a055f20fe947ccb181f3c1906ac73c32118120e	1675968975000000	1676573775000000	1739645775000000	1834253775000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
391	\\xb26794a6db847d457ace2df2bb2fbe9c4a810ad4d3603ffaaea0fd9154a0f421a911ff1bbc945ea64a161e63ff3dadda9acf531cd3e28436349b176d4f5c9bcc	1	0	\\x000000010000000000800003bf8290ad81d01ddcd2e64b8ff1537aa4ea6f7af531784c6c408e3bff655f8399051bbed56636eac13c33cd2da01376cadbc3bb8486cb7dbf42a7be026f4d3530a6b881d83f4246c2a87d4e27a72183b410027df8ea6f412b61cd7c242849ff860c62e9819ef5dc3be5f5bf1d51291fca3b64fdaddb8f8483b329bf219ac5a0d9010001	\\x0e434fb778364ef341610786c326948fe3d25cdf80ba4653f4dfd467185a8df8ec0fea59a8754dba47a23fa4a6643a76af16ef0c726daa6a6fd2767643cc2503	1688663475000000	1689268275000000	1752340275000000	1846948275000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
392	\\xb5eb13c57bc288de86ba798c5de7c13905ea50a26d33225b79d6319bb03a0686eb9ede0f6e9d0144793175442ee208959efcc440feaf274390bc10a071be9fdd	1	0	\\x000000010000000000800003a340acbcf05e59cfa7c82b9f7b0b8340512976062fc43140a83245f76d5d412c8109f7702e486bcd238fc417cd1884fc46d30e6e284ba831f09554a6b0e7530fd3878af33d1c6465d725c792b6a37e2d19055822624f51fb6f7c4e719aff0edf12c20913d929cfb797138bfa259ddb8f9605e30fe4304e782cbe271ce25cf73d010001	\\x50583ac8b96bca2bb714d491780154074426ec8454a03dcaed235531a292cc54334f237e6aebee6edf5e149f6494e5458cff5d18b24facaa2474872766f9040b	1675364475000000	1675969275000000	1739041275000000	1833649275000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
393	\\xb993d9e6e917ca1d1200ba74d310558b237369211382f0fcedf8dd9832f9ad974b46a3b8a6e07a37f0a3fe2a1aedcbd935c399442c3cb5c301835002339a3872	1	0	\\x000000010000000000800003d38d8d736fe04d8fe21be04eb80087deb87ed0d0a363a098d7e3e63940e209e08ca74d9491c6252500e052fd4e48c53f27cf97af3ceb51cabf975794cc1f6de3e06659280e263d113afb6b6171cda63f9035c13c6186ae9ec9a7ae2f55c1240351ebb8f1bc2c786dbebd70c52ded0798d42b20a22cb23908617a0dcbcca8de9d010001	\\xe72b86280af6b785fb36e4efcf695a4ac18061f75d8ce22b6605b7672dff42fc7d8ea3e6d59dfccd69a3e276e3ba2324ac77db1a5a20589052eb1c23ea3e4402	1665087975000000	1665692775000000	1728764775000000	1823372775000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
394	\\xb9938a31cf8f2df386bdc30e3924243d617b63dcc8529691c9856fbfb5cc2c223b1006fdfdd80581befa8b82c301931c1044a9cee2462f2241393103eab7ebce	1	0	\\x000000010000000000800003b35b7e11d39af05a3e51f5222c66cfadfba56a667a05f3702b64acbaca6159e6df746c081b8f925061b5c072b7b599bc0bfff389e9f278185a8219aa7b46a57f5786f2f911433e37e9fc56a5f2fd1c10726ec01c7031d40a473b10aec4eddea09eac7120da40364c5a6d94b6e132f4bc0b7ef788209029a2dd09cd967a7d898d010001	\\xa91aeb931f9b3fcef9f89db82d7c4579e7ada2b3a33f2efab02a1f117f194c1e5ec5d3ec0ce230307134e87b64e8fee613bb6b9657f7a76601bd1f7d712c1300	1674155475000000	1674760275000000	1737832275000000	1832440275000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
395	\\xba47fe7e21d3622ab656b2323ecb8d9b6ddf97aa06ab7983ec89bd4e393670c1935b63524d130db28195c851e3ef2de12290cc207022e7b0e0f177cdb8d4e019	1	0	\\x000000010000000000800003d40a7da4222ff888ba2dd2c057457ba496d46fa491a850beb495ae553f1804e7ddebc70893bd941936c4e7826205b5197541fac1e4e9babf9c6baa6d4913fcc43ed126a2f882ac4c60ff2f7074bf7f095f9a126a097c99307913942dfda5b75f604256f487ee73974b5f9794996e224bcdd3508bb16d4fec1dfe58c4b11954d3010001	\\xa79f387c1889582773ca180f28f705ab1949e0f542b22437008ec06ef755478a1a9e76975454f6e6cb4b43865bbdef42a51243cd0579ed541b1fbf548c09320c	1671737475000000	1672342275000000	1735414275000000	1830022275000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
396	\\xbd93fcf1234928680db7e5de1961c34f96db8cbfc28d7f5f2cb04e9edb09acd333659bbe322563f3614b29ddd92094ca7231480b40d4307875389946abe3ec92	1	0	\\x000000010000000000800003ad3e0bce744326621a4bc0bd16339e0137d90becfe64d95117633c9c2df3098ad82eb6d4e6ab7c995dea06ebf034a5a741bed71b283dc5a8de065e78c03fc2b22125e1ddc48749551d76ce44a537570b324e12a8b92a9622c6340e2689844ce56827985ec1f69b280fe6fd712107edf41119ad2e3a30e9be3e1340ed36f5df79010001	\\xc33087a87c2530580e48faed71c57cc5404c90694d9d298fb656b8f8f4e717660005552e4333ce1554df7d83d9b457af6e4f3084f8bb71134231b100b52c1c00	1678386975000000	1678991775000000	1742063775000000	1836671775000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
397	\\xbe7b9c576fad48e1900e903e5746e00c6dbc401dfddcb5e09d9e6c6c7387c666803615c3b2e093b6a4cbfa4ce5a549fe8fcb52da0df85e0da4f303989a388b65	1	0	\\x000000010000000000800003ccdf9b7101b03912a08e94b59788e588a49d759923aa6320b93f1899406f01b2154198679e326750329b913f7514dda659a29975e4b6ffbb1ec476a1ce0267a2128c683cdee2e4ee7588f97679cf8cc0549a81d580e43f9f0a368bc83c409fe1a10ab1efe66a11b0384ad22ebad684d30e1a0cb12b043d8915a066fff9128e43010001	\\x76a0f08e1601df10c9a615b3edfe422919bb72f429d1b988985eeb7fafc74efdf470884596749a2e99b1d910a960a8c9878e79c5d4dcb423c145b40240860d07	1673550975000000	1674155775000000	1737227775000000	1831835775000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
398	\\xc1fbbfbd8f8e0a40a6e4662a3b63a4e9d12cb777331bf96f62766de1df59c90b35d6302c89271fb13ca6822d4cc61653d6043b83289a098fe5ed130dbbc41a05	1	0	\\x000000010000000000800003c9b9a00aec21d302ebffaafabe7bb0cd8ffa7bcc6b691c46ed26840dcbf0b562eefdca2e7cd8a88b139804fcaa0bd32ca9d862add0531d344111d1d1ebf0b23ad1a1da44ad849c75bba8fa091f3731f95fe82ce41e21d5dd80a60dc2f71f9ec776cae16888617d457e66a6f41dd6bf27886fa0bebb6523e94b674b79970f1ef7010001	\\x94b2ecef0cfb12ab26a31d29553481dba37929ef846b4085878da4feb1a7b152aa12ef0b74232c8aa3aa6cf71593f02a5d651d0821e755598264281770193a02	1675364475000000	1675969275000000	1739041275000000	1833649275000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
399	\\xc8a73453137a38ad5edff54bbf75ca62750907aa666ba6801a70c38dbbcb640305c24ef7c01e9658d27860af44591187a190f3b6b9f763073f3cc20aa4590e7a	1	0	\\x000000010000000000800003a3394677a612406cdc3d39bd86afa65b9f8440fadbf50e89272980998d9e2fe31ee10697958f5b049f6b68415ac8258a9c09abbd71c6dd75851ade8987a2a1a70cd2984cd414e27e1b7422e24a15ac8b1adee9875ae3e4ff791dc91cb1b5f59b67a4b93de8eaa6c905bd44aa1d2b52c4a21a0c25714602d066e9c58e1e798f45010001	\\xfef1dbed04142f98fa345eb83f65f3560a3471a73ff783958cb0f6c32d8624e7773fd3130fc667061329631cd46e5fe365701d0ae264f442e66ba26e9322c409	1691685975000000	1692290775000000	1755362775000000	1849970775000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
400	\\xcaf760b5d9155563bd76a4d3b4b672415c5b5f6ce6ea20408e176d94077064c2f2c5c681234b8c1921496875d4d336996857a13e14d9cea13c3421bb2049bc46	1	0	\\x000000010000000000800003b1ffaf1fdcf8a3468f16373b8d216574513c525045d89fbaca279043da634688d7e5507e18730004d79dc9922db113e9028e01bd0c51c831ee00b885699ca59eea745cd702f524840d421db64a09071a22811ec16df064ee2518ab10337ca7becb53da9ca58a03998de26b3c8cdf7dd21abf31c7d3aa68ba64e7acc90fe624e9010001	\\x01ce5323412f3e0a6b18a5b96036f281f474540a7bb795ddd35429683d92be9c482b74652f5f07ef999f2add8a7d4138fa19862c3db2ea1bf1bb6b226abca60e	1664483475000000	1665088275000000	1728160275000000	1822768275000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
401	\\xcd67627cc73ea68891706bce6cde119d8218962af4ffbca8f57080a6bc5abbd9009ba36280bb71b438508ed6f10a669f3016e41dedcd2cc987a97cca63458a3a	1	0	\\x000000010000000000800003e1c7f2abd642cf5a9255fdef859a655ba0a13856099adf44c967b2aff842096fc50be08ee8a33c2cb3e1b449d5d2a18072ddcf66e6d88eb49f7ff428dbfd75685683a53af8e7b0d6d37b0a04aa8e42bdbde0526239e500f7f8ebf98b54248334d3736215601eff814702a4b3a57eb3c482e221a592aa3836fe33e2f83fdf1ecf010001	\\x77125661e3a7bc687c95850c64c2d75c957b3dc4d3c24831bd43778a20628b892b4778fd964f564c9c718c359709ca4293752f6e2650db73926af5d95f389301	1683222975000000	1683827775000000	1746899775000000	1841507775000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
402	\\xd0e3edab00f618a2279247ca9fd29b6865e663bb03591e1e8f5c2f16603fbebf8b9654b1b94a77f0f4296af925af32dae3dad3b3c9993a5f9e26a7b0811cd0a2	1	0	\\x000000010000000000800003e55912786cac0ec2d95babdd3fecd059b5154e352865df1b6f9f3615d1d1c1b43485788189a5f78703c121279b888d8b33b3da8c552f4228e031f258be7edb889712973d42649980f42584309db714471081acc46ccdc165aea0b346b10e2e020740bbf52f0c5e3fcf0008d50eeb8f9e5899c9a37a51983afc9c3fc4bf776fed010001	\\x25ac2c76d81dae98a88d3c3f23b8e72a4ec2e463b77d3b114f5bd03f8d0896dbcc8bdcb83c56ef7371e55ae455464f29ca6f7bf04b3553352654cedfe3cbdc05	1680804975000000	1681409775000000	1744481775000000	1839089775000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
403	\\xd39754a835d4c9520048a85241e13bb3449a6460977fa9a164bc9e041a0b36165d90cbb1387cee32269b88feeecfdcac821a791d805ebb95097d056106a45e72	1	0	\\x000000010000000000800003d8211aca2ae49371d6db09ce790250cdc4518bc599afee3a0e4c436a5b10f352842b06445c79cbcfd62bacbd19418241b8fce7be5f978e76ad4e01dc32d2148ae690742b1ac064a9fdb9c8bd2b09bcecba75c1f614f968e6e59f908a8cd711b231b80f0b9a94de63033a26de83942af855d87a5f7ca8df4cad14f0d8ac362b2b010001	\\xaee2362c181abc5bfc582c16cc093839da1db6e61e2437c9ecfa3fa37b938691b2dd397e7f20da94a12bfc216a70a73f7f71de8a5eb6d0022d0cfe6076535400	1660251975000000	1660856775000000	1723928775000000	1818536775000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
404	\\xd4cf44c78694185b45398edd0191832ac7a43b4ce353bebd3cc906d4238f08f9a970288fe9f43e9f34ac7f9cc124d18ee463c4e60699dc01dcb646f9004a5f6f	1	0	\\x000000010000000000800003ba7fbfb219958ae6b496506e23b9a822654170c17d73593de2b0cd9504da135345795f36e3e755aaf27eca70c5b110c7f0ee42875a3a8453dace1bfd8fe97395190c092860ad2da940a7c0d06e322324ad46b5916b141358a0f79c6db6bb62b6091af425ce9197f45984b454e16bca4335d2bde86911691b9840973de034b0bf010001	\\x5bec89f1dd85b744a33d8686ea77dc91785134fb76fa55eceab8407e1840022a8a8fb8c4dea91c9dc65f5dcee86fe539000fa5cefd9fb3f513bb85202555aa0c	1675968975000000	1676573775000000	1739645775000000	1834253775000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
405	\\xd59b94bb61d7ae53f29975a5d4227415c787d2603c0c5335449fa950f308f3448995d9d6da4b539dfe682cab42ce660b1fbb95df104d0472aaf4dab1df5a5334	1	0	\\x000000010000000000800003c9aa3193f696e4b2e4987862f1a674d668d3574f2367c4b51a347c9ef592ab186b9bce636caa5b9b19a03cb54d5c7d99c1f15d081746e54c17b15984297be29077a4fe7360a8bf1edcb58c7cd83aa7e1211775e2bd1de9218cee5a73b2847711da5e1936ac923189cb468120aa621c8e227b377a4cfbcd534bd90f4b67a18d25010001	\\x3f580e7f724dae33d892c917865c1cdf66b987b70544999f63dfdbcf443ea86f0cb9ec570ad264fe918b3542f4e56aa79a1cd0eb9788ff5a4a5e77f332d61c0c	1671132975000000	1671737775000000	1734809775000000	1829417775000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
406	\\xd68789e2343dcfeb5c504ba66d9894c30f43e1a7941a2c62eb7925529719b7be2ba25130dbd783ec3758984f8df5ec9c250d9e70867b0a706e62f4d588fe2e4f	1	0	\\x000000010000000000800003b0e960d76ef6abcbd384cce4ddf7741c16804231028d4d451b7eae87564e5591e3908ee2e2ecd259a1fdf2b1fa989d2b7d66aede3ca00e63689cdeb41f9be2d6436465c34c87f71e3ae5d45fcf5e8626f53ae9fb34ad56160a4715c95485fa23d086fa00b238ba18eae0a8b7880838d84c7ccdb7db081b0d3d2bb0dbbf192acf010001	\\x01d910cd7d1a4df723c6f7650c3e5f73c15d5f58521092d558e69a6dd02705acabfdbe1e61c75cc744b9ef928f2b40a9d1c96422b00c7682a2e2632ea2f4400c	1671132975000000	1671737775000000	1734809775000000	1829417775000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
407	\\xd607c11a2053cc820f760c992eca57d49afe4b6cec3b0b981ab20e3034ec2472b42d8c2cda4c972eeb614f4abd56e2fac0142a2f3f7b4973baafd5eff06ab7b4	1	0	\\x000000010000000000800003c1d19e95cd82ae97cdb57bb476a147854f7b33ea63caa5c908a84c0867ef0d7ef3a021dd93705abcb4eb8123bd62a5433f22aace187dca32ed39762bd6fb6cecce9ee3b6044b05aa40d95ff27c50b07cefab216e2941769ca9cf0f0e0739539e95798992b69ce52bd961ccd9372a39994c055eacb8584dc553ba7118e8b53d51010001	\\x1d1b0d76e4e101f309f34968c48a6e46541080ad9edd890770e8ad70386a7f727e240bb245dd72cec810017c2547599d316836525f913f3cbd722fedd337a909	1661460975000000	1662065775000000	1725137775000000	1819745775000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
408	\\xd7470a14e2efe2f6cc06d6e21fa976ae25ab81c2add166477c656bbd0ff6e1bf8df2ce4baeada0183e0d3e4e76315b50d5a562a25d3386a1bc3e0d4f888b57d5	1	0	\\x000000010000000000800003da0daed905a7ce46461f08966dcffa1ea0f5bb09df7dabe103a9dc3d11eb3ecdd0c33610dfaa47dbecc2a53185b718039a2e09778b21037c7f9cf5c40faf3c14ac0cf879743d845cc2c8c3eda45ad66f4e1396d9965490092c3d350895b86537aec7e48275cae7d42e828fdf1569eb8eebee3f0ca9b4c158c20d22d3c66288c9010001	\\xcf795d2454c426439a1ffe6ff82f8a207b58dcf888b57b404b03b13d0942e5650d53186f8d4127015c8861f341962694c483ae85b68a7e0906bc675727280f01	1685036475000000	1685641275000000	1748713275000000	1843321275000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
409	\\xdc97b1938f547a826c55d04957a746e123143210b297dd9d24c1839cb8ec0c6dce7214013a1b58b10aee29f31dd24823e3cbe6d8cecb9ea5af00b07515dff89e	1	0	\\x000000010000000000800003da4e3b1dde251eb978be205eaa0086458abbc43b2e83b39469ceaea6afee190490f91f8491667219f7b3bcfd07b3588df36c8ba4b5656212af7d3d8037daf235a6f4fa2a1887c0eea75184862bc1a3c2f6c4c2acb37f2f1b76a723c37bda6a02c4caa9b12e8808761b6173893a90d421761581855b47279b9ec1f10031c6a2a9010001	\\x212a8a1c611b73ec799db23c6b65665ca087925f351c44c5742045721dece66d095c94740d8f2a829a606839635c1931a62a6d7321f746550052838f55741f0c	1682618475000000	1683223275000000	1746295275000000	1840903275000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
410	\\xddcb301a40cb258223576897f127468ab150b57b07c27c8ca2687bc92821508d515c3dd8c69d9779d128f640e0631d2adf73737c1403e7f6048144027cd3f7f0	1	0	\\x000000010000000000800003b11410ae1a496ae1b88b98615ad2e2a9bb3a104c273bd43c1cc283bd380ffe880b5c99b01fc9cd0bb902b5ce5165dcd8d9d1aa40f7c3af6557abd1ed6a1df42397925803833f5b93f3f680f973b6950130a32eb167e11d8c00b150ff23983b8b54ab79139a9ad52a03ce2c077dd5086c9991eec1337c1b6ea22f14c43cb6fb2f010001	\\x0aa38b35bc73548608d62076ae405b4d6f6cacb02dad198c9a0a0ff92aa5bb85dae4afa849eef1cceeaabcccf7659198a74773a12e067d69a7f04ba5fec4fb06	1682013975000000	1682618775000000	1745690775000000	1840298775000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
411	\\xded72a80eabac22f22a1cb17ca40821633a098f3130ade772e81fc5014c257eae7c6deb84422f4c6c0eda43454cfe7e9161b1b3403e531ba07cd7a8c4c073592	1	0	\\x000000010000000000800003e521f0d2789d7390a6bccff665b8d6203e66fd2397ffa2d748c8173bd8cd592fae071b61a7b265de17dd0990ba6858de4235efbb3950756adec0d6aafd59ab6bf2f2c9496e0fa835c2092c4c33aa7841de47e756ddc753cb2a51519d6580ee1e25b58d35f9096ac3be28495c0d86afc0f18d629a75a4e28fcb3dd306f30e569f010001	\\xf84a52d9879e486c58a6812ddb8626b1dc5af624c6a65c2f091edc42d453e2233824e8164bea2f2bffd36ef0d18ba3b1ebe5d01e25313d1bc23bb792ddca7a00	1688663475000000	1689268275000000	1752340275000000	1846948275000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
412	\\xdecb698cec15bb60a05b2ae4975ee3b550611e12ebe36e34d8ebffd40dd13031351f58ca5423c70062052cf1ad686cf4f270b9067e56462e467b2b0eb33515bc	1	0	\\x000000010000000000800003d63b7c3e1b9ffd691ff9f82749f5bc72ae45c5003a6ec4aeae0560f0b90f66ced9454b7b8e62466ae878d931bd59184212e63cd76d3268e833594139d5cd1f6845254f720c9769f673c2f8fd74820f4a597d85cc0e498179cc97260b0c00687ff4e9881a0a85873e59f0e5f6f40cf11927f6755d4dd86106ef68954f50490887010001	\\xde8f9a46eee410921811c20d8881b045be8952ef9880fe8b459b9a859018ad66167c887316177fd766731b3c0a169e16f2db2ef6b3a578500ded75f3be381106	1678386975000000	1678991775000000	1742063775000000	1836671775000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
413	\\xdf6744475123a881838b72fad7f58fb134645793a8ba1d37c8e66f8626fffd1e303ad580c340b9647ca658d1e8a6389c74bcb9c7dbf96aa92bab4258e6639ca7	1	0	\\x000000010000000000800003b9405f35c7fd7b78973803e4edad8c77170ab8dcddac2c854cf05b11c0cd31e6f26abe82387ca38b6b13ab7154a4b06e0bf4a577b225c91f8f5092337f270db5b100fb41229cf230b40fad9ede1c950b859852cade2067e708b1f20d79bbbc7341f80ed6c0405d55b98aab03075f5cb6ab8977111177e0b1a2adcfd1d623d06b010001	\\x230f1ce715287ba0c004b054c1ee1aaf8344949b971b055a3846a218e92fbdf4b9249d161d153871cebe61e43162550fb578a1be57a9f303787e0a46b619f409	1689872475000000	1690477275000000	1753549275000000	1848157275000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
414	\\xe5c3ce4a60a6e8136652d39281aa2fffca9e9e29d84611795ad6917ddc41fc941dcd9a575ebb91e6086bfd44764950c82fc1509bf837fa880db04d216f71c173	1	0	\\x0000000100000000008000039ec446b70a3fedb713811f8d6ec810ccc4fa73ce2ff11c4cb7b79603a3dd08391f132d2496a3447502ecc8665c8ed8db9228719f84326f65e976d2800bea8d46d78ea1b6e269e3b7e6e402dd9d1d1837f55dff263f810d0e349b0dccf956c2a92ab0077980261306e82ee3976b86bde2f683083ba413dab8b2fca926fe60ef31010001	\\x710f45efe645fe35d6b93ef8e42002b09f956800bed62b4e689048741df40bfb3cae49fd83d0e48c3d6ba314812cfd3c4de139ac5efaaa3ddf61b48eabbe9b08	1674155475000000	1674760275000000	1737832275000000	1832440275000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
415	\\xe9efaf2fbd62a0ed90f77fa7afdb577b0767145d46d518d03a097bf2272f4e84f8aa0e15960831ceb594ff3950d6fb995e56cbd178b8e684f96ee4530d215995	1	0	\\x000000010000000000800003a15d533c82739b64ef3c38d9acddfa9a33e753e5844c62ab2a429809cc7d25a5f8463c6b8a12d7d0d4b50db8520a7d3a0122fcdcb36d258b253084fc22eb59b7f593199645d4e585d196c826f152e2cbde43cd92c57aa7d6db996eeb0fa6e69b743de78b526f27870c5dc35b8c33513945eb91b58bad2dfd564cd02e4df8e343010001	\\xf935770919b3d82c76b4f15c8385ec74642e5b50a6c527f7d1767a475b04d79a2a49ebc2ddb6423b9648eca2431b83920e35c9b2835aaae03ec154f05a7a2404	1688663475000000	1689268275000000	1752340275000000	1846948275000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
416	\\xef4fe2b3d6ca2c719dbc8dacef998421b42d6cf2eb8b3febca56fc196d266377d9a3cea18a85c89e6fa50ef8e69546738e466b09f128ddc5156d4f1f5b547541	1	0	\\x000000010000000000800003a5ccd0e7fb3562e604442765901079fb25af1de993d680ab1a4ee4741a2e6292de02272431043cf91398a3f4131b9bcbb8838a9f6452bec9015ebfdf9e1f899decd5103841bba05144b9836d1c5452f27981b36616232d29078bd7cf25fcc97116f4ecbfb9779c5587fa5f603a68d120ac68d6d2d30c76b193aca46ad04438a7010001	\\xea096c102eba82e7efe7b98c0327d45fddec3c0ab51ec9d0c19aeac11fad9c87ebf6f922ae7109f55e68b6997c1076a37d5527365df8b821152c08c86ebef60c	1671737475000000	1672342275000000	1735414275000000	1830022275000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
417	\\xf2830b6785a3638f0e8f062fb4bf773188ced21237e79cc796b846d560a6760464a7c957a25b8f485dc9e418d8865a5056ad50f0d15dd14d8b58637bd69e4e5f	1	0	\\x000000010000000000800003a0ca1bff8df60cdfd25e7c9ceec61628195d5b0277c4f5cbc55a4114c091323ffacd1747ccf76c18ca2d38ac8dd13f1dfcdb8c6764c77a0ac788b544b63ca53bd98b173c5e4e0eb063e9077e2df4192e997ce1a04041b0d911ae9ad4ceee13781fe70804f6470aa6c5900b85849f1df3be7df734fd0f8e532a36d0d062df82d1010001	\\xa61dc8aa278041e237e03e715af08ac020f16bc00dcec9961f0cf661e2ec1094be01c346c15202eb88e34a57d096460a5b84b2b72995bd8b3f6771b978202207	1663274475000000	1663879275000000	1726951275000000	1821559275000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
418	\\xf32b6bf20f7237897f7379576f087fbdac94e303460175f0c72bd13ba6e4dafd22b0f08345bfc569e256662576656a0d7fd2669dafe21994206a7dcf4daa5954	1	0	\\x000000010000000000800003bc48d6156929096db389f8ff14256f797a65c848874bf4c41d2548c1d3d42168755ff9fe42aed84a16291e06890781840b33d9252dd3ac245abc15c0b00eb359e117581465744267dce50da6a7d62545ed1dba4c6ee819d7f9bca3cfd0f6ee798c547b7b44821a156001c5cf7245e1ea2e9fb16812b19734b275ae53330ed165010001	\\xffc580bdc08dc7e152e4d6da91ce6afb0d788f194f4077d491984617175ca8ceac2013abd57931863484ef999b74d750089304d8fd0e87db3d16780e21cb9102	1666296975000000	1666901775000000	1729973775000000	1824581775000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
419	\\xf3cb65aa2ce7da166604d9668383225755fa9484f1cc5084fba3d9690ee13c8b06071632816ae004000def19d00c791def2bee2b39eb52e7e8f395c5086efe12	1	0	\\x000000010000000000800003c280230c0895394dfde712f5a8f86cf998b5e0178a6c0451624f314806109b6b3c6f96925ba54a99027e0097a01f785bddaf511114e2ba87a6e8995f87b7c3f244036e23d2c10a14cd679506be4cc99e39b63d53c810996766bc8290e4ccadc6f995791e38c0dfa9b66a14a1934e2cbaa719ed9dac18a24f477a12e6e2692215010001	\\xe829bf6fc39667d61740c9dabe5f81025135e7b05987fd285acad891ce5335bfa4df0e480171790da38b80afae85acaedd799f045057c8082173599696910707	1665692475000000	1666297275000000	1729369275000000	1823977275000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
420	\\xf55b974b1caafc19ee3d14a2df2fb7da9586c38dce0eb8473f74f1f64b34218b20f51af92dfd8a6b9e6c70a8342b637e1788566d32426e4a4f8b5fb28642ac34	1	0	\\x000000010000000000800003cca4189bc487b8ea150620aeca0f77ba93c970abc35ffa39dc7c0c2c5392b9a199f9cadc35f2209732470aaa401b2dabdfbc366bb5521fecfe51f1f81b5aaefb9e10db03bd0ee3b356b4f485df08cee780a2236e57184b5f57d5d1995a24aa6ef641811b457a59af7a7312537b9c9ff6ae61fa9fcc709c4b0882d9cae8e00a49010001	\\x3eda56482fd6b4b5a9c1ed17d0467bf2f24668473d3137b7db3e33a5f31b281dbaa2fb5964c23bd8ff603b52f0080783a85e7b93933eda3b28be96373a3e810a	1673550975000000	1674155775000000	1737227775000000	1831835775000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
421	\\xf627ab64f27d9a2c96bd60a2ff87f640078c821c98a4c9674c824e356c99ab27c36777e730b88c34b9db198e499418b12fdfa1aeea93a3896ce4eb4501a56f78	1	0	\\x000000010000000000800003976086d63fdd6635fd86d83c8a4712cd9a34870610b303c70e6114e31efe2214d6aed64cdafbc93d796a54b7e2f2d49e3bd533e35560bd2b3a30cc5fcdfba6444e62fc13c3cff0e131667cec2b87d0cb120993fdc782659f5f1e261e6e0bbfbbe31f9965fe2f1a1c62ffbcd83867386211b34eb501bec16b3b841e9d043891cf010001	\\xde38286707777cae2f6e6e1941e45b11d77b992a70cf691ffbeb2180d7bda708ee229b7e9b154b35b291873b7c114cbefe0e8562dfe7dc56e577404e093e4601	1686245475000000	1686850275000000	1749922275000000	1844530275000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
422	\\xf83f7f9e78c5f7da1dadd0bda2fb7344a278af4a5d0c6c5ce84f107ae74a42c5bacbad11844c06a6620509dded74e36acb6848b37e888698ad13b00de6b7bfbe	1	0	\\x000000010000000000800003bd968a055b682d3a7ea26d7f81be1f116279c6dcee1c4c50413bfd5d981ab70b11303fcf79ca471162b372c0d36f42848a6a4ad97074daf3d9065a5e440b3c41cd8d8dbc9afed0b4937ef2b4fe074ba7a0c19cbf23de7241898f4b2461d4233938e64337d85f0c2a90c717ba1d258a0fe14976537c695d615d245839f2ae2289010001	\\x004420b99e3fe68b5372172824af2cd340df980cd61a75f3692bcb90b2c85496932f5289c942d2d01c3e546b0b8535466e0b57da35eff1ea2e9fc3c7dec4eb01	1675968975000000	1676573775000000	1739645775000000	1834253775000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
423	\\xfae7e93cec0e5e0339f9fcfc1de060538470d4197b8925dd1f625cd3cc4fdc5f1251f5facfcbf34b7a8c8f25e1ee7158af5746287127731640314b5f84f6b210	1	0	\\x000000010000000000800003da1f53badb5683cbdc90efc9bc75adb6e44bb1b898e699b29b8f7014d3afda66440c3e31fc946c7d08bf40dafc6bec36f75fdd68ec79f0ca7d2ffa95f35040bf44397d77d7ac8667702e83e9067bfe36effbc2c83c2d7272fb69cedbf839c2aaab8e321ef6034eef3cba2f5c6de8f316be140fd15a85cc55e39eaef5699f50f7010001	\\xabcf6aff690027e74b5b81ba5430954d3f8517e9a2d00c1de0eba1bc7c5657cde76462fa2494910f6462f2b08de7e9f37d68166c64763cfd3979d0bda7bdeb03	1688058975000000	1688663775000000	1751735775000000	1846343775000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
424	\\xff2bb516dd7dd14150f84c0f3d64d0e64ece4d825bab4f6793ed9f987614ea610b14e4302f64185062800cf0f4af953c63ae330ce457973f9f3760c0c45fdffb	1	0	\\x000000010000000000800003bc4f3535cd17084abc073ee6b6a8b04e8f52f624326735a43907526080a3e13cb70d6e276aeac0d114fa2a226742cc1321306514f1ad91f6523dc613839a026df3049f87d92abad3d38be60cf498337b1ae3a8e1fe5580494965403f8977f7470fd1ba00b1be10f900317bfe6b6f851ba5af1765fb39a9e94cf04526ce64b5ab010001	\\x974919a9d10d86bd2709be1ee7b89f8873d093f36407153fe625398f28991c901e343c185bf046ecdfd2bc07818f9f06ae86017075e7394b8755355a2eca2207	1671132975000000	1671737775000000	1734809775000000	1829417775000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\.


--
-- Data for Name: deposits_by_ready_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.deposits_by_ready_default (wire_deadline, shard, coin_pub, deposit_serial_id) FROM stdin;
1660252903000000	36447903	\\x35290936b3298c531f7663cc352f52328dff8bc55a888c778a6a5f666ec72229	1
1660252935000000	36447903	\\x017ffcb450284349856b997a0936f632297b24f9014d29a8e125cafa62343a6a	2
1660252935000000	36447903	\\x093fb1065ac13f3b0c67e86c7c62fd7a7b70fd2cfa8aff5124f90179d4107648	3
\.


--
-- Data for Name: deposits_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.deposits_default (deposit_serial_id, shard, coin_pub, known_coin_id, amount_with_fee_val, amount_with_fee_frac, wallet_timestamp, exchange_timestamp, refund_deadline, wire_deadline, merchant_pub, h_contract_terms, coin_sig, wire_salt, wire_target_h_payto, done, extension_blocked, extension_details_serial_id) FROM stdin;
1	36447903	\\x35290936b3298c531f7663cc352f52328dff8bc55a888c778a6a5f666ec72229	2	1	0	1660252003000000	1660252005000000	1660252903000000	1660252903000000	\\xe1749079550dcc6f91897dcec80be08033963a340b41266d8bfecb8c8d2ecae9	\\x8441fd1913c230ce67352d8eb45d6c172a1b5e5855d8b46b4697557670d81e8dad19fe10cb06f98c00112665d5cf514100ff77d7319c87709f638c1a91092ce8	\\x612642465e96af3f6047fe5cfaa9040338e93c62cbe6249ceda8c89a9d7c87109c92b98486868e4ac160aac7b2414a5ea2ea735ab635112b2f7d0927897acf0b	\\x79baa0b9272b661741bf49d52101f098	\\xd31e3f48cb5318906dbbb7948326362f41604c7a728323230ae82aa995f27400	f	f	\N
2	36447903	\\x017ffcb450284349856b997a0936f632297b24f9014d29a8e125cafa62343a6a	13	0	1000000	1660252035000000	1660856839000000	1660252935000000	1660252935000000	\\xe1749079550dcc6f91897dcec80be08033963a340b41266d8bfecb8c8d2ecae9	\\xd7b5b06be021d66ce41c6560f4717a47aa0b555d40e5791a644bb0586713b09286338aa317eb152d53e5f01914f565c98294bd0e1c75a9844760606674fd4a07	\\xb8e621dfcbaf5231aae7992e4cb252290246d155b59cd396a802be1dde9aca446008935e8a7594fae9dacd02bd1c12f840e533fee09e112b7e146904b6cce701	\\x79baa0b9272b661741bf49d52101f098	\\xd31e3f48cb5318906dbbb7948326362f41604c7a728323230ae82aa995f27400	f	f	\N
3	36447903	\\x093fb1065ac13f3b0c67e86c7c62fd7a7b70fd2cfa8aff5124f90179d4107648	14	0	1000000	1660252035000000	1660856839000000	1660252935000000	1660252935000000	\\xe1749079550dcc6f91897dcec80be08033963a340b41266d8bfecb8c8d2ecae9	\\xd7b5b06be021d66ce41c6560f4717a47aa0b555d40e5791a644bb0586713b09286338aa317eb152d53e5f01914f565c98294bd0e1c75a9844760606674fd4a07	\\xa3fe6ec3305448fba768061059ddc4f41d1c5444a346d1c7511392a4a638583458ec7377dd7ed039bb5ccacad9c9091ab60f60cc5e6820756ebbe112addc970f	\\x79baa0b9272b661741bf49d52101f098	\\xd31e3f48cb5318906dbbb7948326362f41604c7a728323230ae82aa995f27400	f	f	\N
\.


--
-- Data for Name: deposits_for_matching_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.deposits_for_matching_default (refund_deadline, merchant_pub, coin_pub, deposit_serial_id) FROM stdin;
1660252903000000	\\xe1749079550dcc6f91897dcec80be08033963a340b41266d8bfecb8c8d2ecae9	\\x35290936b3298c531f7663cc352f52328dff8bc55a888c778a6a5f666ec72229	1
1660252935000000	\\xe1749079550dcc6f91897dcec80be08033963a340b41266d8bfecb8c8d2ecae9	\\x017ffcb450284349856b997a0936f632297b24f9014d29a8e125cafa62343a6a	2
1660252935000000	\\xe1749079550dcc6f91897dcec80be08033963a340b41266d8bfecb8c8d2ecae9	\\x093fb1065ac13f3b0c67e86c7c62fd7a7b70fd2cfa8aff5124f90179d4107648	3
\.


--
-- Data for Name: exchange_sign_keys; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.exchange_sign_keys (esk_serial, exchange_pub, master_sig, valid_from, expire_sign, expire_legal) FROM stdin;
1	\\x61e9b7de014621a1cdd10e78b3c370bc72a9364b5d33ead64773fd2dfdbb8301	\\x4a92c272d749f83bca847f714d0e590c4458b9be6e01e05e0793a5aac9d73d64d1ba72e1d76c3b2a50125c529cf6b95f867ccd6046ca2619137e7ab3cb02dc08	1689281174000000	1696538774000000	1698957974000000
2	\\x672f96a79906416c79911983f7f421ea7601768c5682b00c0182e6127c394ce5	\\xaef46bdc9c4d567dbd397ec55797c87379aeee60d6756af2c0d32ace59e32f0afcf671521ad58c69e92b2e06c6049f01793c7b539323c438483be063abed8f00	1660251974000000	1667509574000000	1669928774000000
3	\\x89e5f703eb5057280ec41ac2510840d1d81edeafd57352ce77a78cc6c736d020	\\x88694d8e88dffe78617bdeeca7b61035d2da33266261ed08adc84e6316900e57f0291c0c323c9b6b11daafc85b18b2fb6365d657cc922b14cb558deac5a76d0e	1682023874000000	1689281474000000	1691700674000000
4	\\xeb5875214f594284c855420dc1f8afd8126b03e06d183ffcd41432f8d9781acf	\\x53ed5d6466a2783f2d1e481995b1bf88eccdfda4bdb72b61afc01c29e7f5ec9994cc11da508b1cbaa8a874b7988519f9fc88f9d089860e4531a0c958d9c19603	1667509274000000	1674766874000000	1677186074000000
5	\\x5d4aa2e9a1eaec531b2b2d4a927d284f869c4d4bba27935af9a341ca01ecdc76	\\xd66763e65a8b370e300bfdf32df7ca3d026046ad643d28b95aa73d40d90a85e61ae81b2ba34124413f28720f8e64c65208c88a18e6b0ec3eb10ec0b4eee69f00	1674766574000000	1682024174000000	1684443374000000
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
1	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	0	1000000	3600000000	3600000000	31536000000000	5	\\x1ea103d006a7b768c518c9cac012a919218e0b96933e1c9c3ce181c05554595a1c681915de083e2ee9107eaface5a6635c29c6368eb27176341a4590d279e000
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
1	7	\\x9777f24cca0e05fe1b875f15451801dd5fcda0fdb9f484e074b7b4d0b9286756	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000030be8465d924f5e86a1ebd686a675d549c3f5a8df83711ddb8fadbba716150fdbf5bd7ebf13e8839289bd98cd23f0bb92190a6ff8da80065eb95ef8198bd813a6e7636618dbb3eb1782c1be901e1fba8a91907057149bdf639f4db02ed02581a4789323728cd09fa885c94e767fc332b1d7ae1d81c7db0cd628e8a8277af9626	0	0
2	346	\\x35290936b3298c531f7663cc352f52328dff8bc55a888c778a6a5f666ec72229	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000009c6d11d4aa17d223ce034dbd1305fb912f55d5f23dbcb7d1905752c145e97254043ba86ee618ab3ac3e86a2c561380c9e8cfce1dd099d46ed15eaaba76632c2df2f491fea85655ef05e78d42030eb1eb5e78319b824b212bac03db978a3cb094c04203d6a259971952fec2b34888415ec893ea35e3bd3319940b09cfb700b560	0	0
11	193	\\xffb5843b29c27d3fcf76615e461b3e287e13243dd3aa0e8d150902eeb1797151	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000004d1f8c471ae7adeb39a65d1dd3385fdc39180c63384d4fbd82e73f67663f81c14dfb7cb0bb668fbe1fd170de72c65d53485b8ceabdf496a598a86ef019ad5727c448e11074f0a6054da8b0530ece62e687b978f89344db75d7bd97d843290c12462503c0d4c27587c7880c14f0cc0442f0427ea13762f932e7cef8a24a07fb56	0	0
4	193	\\x05584addffdc33692785a79f92973f2ed2c244218b94d74d227c45f430416e37	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000020374066bfa4733157dd3636e8fcdfb72647bf8d4074bf06e240aa71d8f7751a9f6833ae01cc3bb63c081dc85be3d8ad8baa12f77b4e2f6cae5212287994be464e35363f39a242fd0ed64786de27a7ed5ed2251f9b75a038b1dcfe6262b45342700343ea2fc2a97a5ed8842f9d956867f4931d25187df5d4c5a478c1dc6795fe	0	0
5	193	\\xc9d78435043484673481287b8c66f1352e60db9c63816ae2a8554fa8e0b255ae	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000003e6ee7e6d11a457a1cebeed434c0e85f4f6b7202fc45c964380afdc8f1a9842144d12c0b5cb7c92fac13a3e0ea3ed4b4743cd6ecff7d65dcca6a476d024c2c4b6cb307f18d192127bad78fa7ddbee5d9444f9f9582f38c52e75eea156327256cdacce3bda37f0b02aee1e8344dc453107fbe739facdfbb3de47ae2cf3cd28596	0	0
3	367	\\xe3fc05d4a6a5a54b8f0c9b5215a95b5c36098be9431781d02b7ed0a38202ba59	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000004d1932e3cfd6cfdaea2d0a1e29af8121e80677b61f7ad6138ad889da1c0c3ec6dd701a33f5602d075c6a0b9bddb8a8f3d2a5ba34f3428273bf19450c3d426edb8d60cebc318bbefa0a99c1ac9c43fb1a7f291b356f87d430fb70db3a0c7515e2b192bc0d66b93b24e0f11ab3387ff0dc05eacd6ef6cc08c0e81de13b28a5e195	0	1000000
6	193	\\xf0f3bb8c5fe31831cd9c7c76a24c82fcc0ce575c4249e7ff14be4c414659cbea	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000031ba782f7860e96f28f650d7fc95bc0eb79d4f4000e8ac2acf7cc2859132e7f5e2cb7a52471694a2fe63cba03a1e696f6e7281801d0db04f60fb8e623603d6efb640e306fa166ec98a5a558954d6c3c0c0eacfad3f42510e4a4bddfc976dd33d8ff23f95df67e6ab7543ff4eb7968431e4f410e78450d062d0245d67ff3dbeed	0	0
7	193	\\x944055a5f68454ad9cd07da2797bf5f77c6a3065bc83de3f4a0e17511fd8e0e7	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000004e95001ddd759845c5d669f00c73cbdfdf1b08619932333a53d680936a8032998a4d8bbc97e09d64a3dbd50476f182e2e29571d6ed229e4b3dbf3ff47bd4ae23984b7cd9e9321af0281b787751caad681938e932aaf9900543a8cf80b88befc55e7579fc478560d52c67423f546971ea3750cc8884054e2742096cfb7f9eeeba	0	0
13	121	\\x017ffcb450284349856b997a0936f632297b24f9014d29a8e125cafa62343a6a	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000065895f9c79ef01882edb7a1cbb02e34ff8e6c6eaa107fa53df06ae55d20e6baf9dcc3229c1689b4bfb11f6464144bfd86d9642cd9ef982d50e42f83fc4f7850e60d6118464aa1ac6cb2d282c440da8a7db5b0fe0aba097df3d7dfb7b56d8afe820f4a0b3cf003d23934ecf3f43a0e4480431846cf4be81a9850426aa7dbe6f8d	0	0
8	193	\\x302dc8df69b93f7e993987010d32a4318618ca30dfa0fe3fb1e924bfad57ccd9	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000044482dab2a3e736ada117654ca98597a8430730d1550eddaab37c9fcd83c5f1ed75c022d01253239063c296967cbf4cbcc37c3b4fa0a4f6bd095c9ab66b0005abb4f5d9cfaa772da848cfbcca60725ed02a6d5cf01c2f78be2b13ae3e5614df4c8d3aa841261dcfe15b39e23f4e4f205a0dd027d90b7bc934ba01e2a8167bfc9	0	0
9	193	\\xccc79ba6dfd55fd585d838691ba1dc3acc1db40bb720ca957143aaabaac440f4	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000000d2cea43863c06b6005874531ea3ee5a02fefefa4bdf4bd340b60b36ee543d3df042bd2eb80be2276b041a1dea5322bce194fd997b4b8c36d5c2e04ad992351b159c7defce644ccb9554b0beb3cd24c24901fc938caaf466c1c81f31a4d80fe47a25e2e9935273cd000dd8223d6078ac1c74bc49c8764895b65631fdf30be467	0	0
14	121	\\x093fb1065ac13f3b0c67e86c7c62fd7a7b70fd2cfa8aff5124f90179d4107648	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000000f21f8182504ced07c42ee4f6edc6402c451ca5a8a450dc4818cdf6cc5b6ab09db8453bc95caa5352bd4534631488922f746908a2c09af21d75c90b94dc47b98adf4deab2f97e64e5e5831e947d655b0de6a83b4bf44b9b61d213dc563d2d60518c402fab1adbafce09605cd57aeed53969e9d4eb853b646e5fc13621d3c9515	0	0
10	193	\\xe37783abdecf5e14cbb3ecb58c3700c25e4d296c7f9a890730cdb1a52528723d	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000086fdbf7e3874a1911399856b69a724782b46f78971a47d0b77b9add6a4e4274e25bb8f648cdb53cb2a1079c705e646e9d51a102780d53670beecbca6d05674fe76348931a17f113703fe24c9290924fbbfd76a68155fc12a18b26b1b6eaeb22a17d7981000a10d214f1c3dce53dcf645da2f40c3ed8faae9fb9c55dbb45cf0b7	0	0
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
2	\\x9777f24cca0e05fe1b875f15451801dd5fcda0fdb9f484e074b7b4d0b9286756
\.


--
-- Data for Name: recoup_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.recoup_default (recoup_uuid, coin_pub, coin_sig, coin_blind, amount_val, amount_frac, recoup_timestamp, reserve_out_serial_id) FROM stdin;
1	\\x9777f24cca0e05fe1b875f15451801dd5fcda0fdb9f484e074b7b4d0b9286756	\\xa68bd3c4b749126ec9c9dd4ab7ed721afbcc202a9db66a025433357dce0e80aafca9b422b1828217f771f69d6802a89c6cefe67eb5534dc7314279f1cf36480d	\\x74a907cd97f6f6d359419e53280b4657aa244079d6d90e73fcd5fe798a66aa46	2	0	1660252000000000	2
\.


--
-- Data for Name: recoup_refresh_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.recoup_refresh_default (recoup_refresh_uuid, coin_pub, known_coin_id, coin_sig, coin_blind, amount_val, amount_frac, recoup_timestamp, rrc_serial) FROM stdin;
1	\\x05584addffdc33692785a79f92973f2ed2c244218b94d74d227c45f430416e37	4	\\x54cf8a9a2fe75fb56f3f9e22d09a9bfb37a3d4927180032c0caf5114baec28b07ef47865bafba16e35be41e9a0ff824ffcee6be235c4aae25f532feecb2b6a05	\\x2feba45494e43c86132ad6c08fe9845a6c596c8113e5ed2bef94fb2ffdbc5934	0	10000000	1660856824000000	8
2	\\xc9d78435043484673481287b8c66f1352e60db9c63816ae2a8554fa8e0b255ae	5	\\x9e969f3efd3d4af31f18568522afd5414e0a75ec6fb2163a1ce439b0f0c6b9f1896ee4a2d15180b107127baa1a7857d85a029d7f45b6715cbe64b0ee615da306	\\x43240a555735f461deb4edaf9050cf33b1d234da8f38d6f4f83534ecd2a86d9b	0	10000000	1660856825000000	6
3	\\xf0f3bb8c5fe31831cd9c7c76a24c82fcc0ce575c4249e7ff14be4c414659cbea	6	\\xb33d29b8ca0cc90c5af96175f55c0c2455a6efc9f6f17f78f72b76ffd2ce84c2e99065061b7393450e216dfb69a67102eeab34f5e127a969dbfa81fcf25edb00	\\xb1bce1388dc97d4589682e6ff2375611a7fc2ab4658602813d3cc9e7f08ad5a5	0	10000000	1660856825000000	9
4	\\x944055a5f68454ad9cd07da2797bf5f77c6a3065bc83de3f4a0e17511fd8e0e7	7	\\x4d7df8bd7692147d85028513ad713dd700c1bdc6bdcee9a046929ba0e2c3982421ae9b839e4c8abc10c2c174e3ef5e52e167210a36d09903f5923179b4bf6d09	\\x766c972d567cca3ba541a94cecf7e54c3136b759443250cf2c43eae210369cdb	0	10000000	1660856825000000	5
5	\\x302dc8df69b93f7e993987010d32a4318618ca30dfa0fe3fb1e924bfad57ccd9	8	\\x62e85693f4982951ebdecb33325d0efa2d0e794ce27f75c6f0d9ce6a84f65209c0ef8507e18290f66ba73854e693481f4dc1ff902dd6c0fcea86ee528e2b1607	\\x73021639ad10daf42a00e5f754c195b60cd87482953f57d0d2f492154cac6942	0	10000000	1660856825000000	3
6	\\xccc79ba6dfd55fd585d838691ba1dc3acc1db40bb720ca957143aaabaac440f4	9	\\x6ef42048131e48a957f5c4b6a6e391ee57fd429391db307a8535685ec977b0a9967b7330c43c606ed9c7ad13901c32aa7c845479a79a2754eb37a413b8e7ff0d	\\x244d0e32deba601920c6391bbcace89292de1b66e9a0291ba4d8a94574a75ef9	0	10000000	1660856825000000	4
7	\\xe37783abdecf5e14cbb3ecb58c3700c25e4d296c7f9a890730cdb1a52528723d	10	\\x7e6def93621d1baf1014c18e53246f57ff8cf75a74c3bf9f187f3dac07b791082a29c274056c7886e9c51addd89f3c9404d68c7e173c44326f19487659bbfe0f	\\xe29dd80b5237e017b361c210426d5f1dfccecc300d4fe3f3300d73551b18f55c	0	10000000	1660856825000000	7
8	\\xffb5843b29c27d3fcf76615e461b3e287e13243dd3aa0e8d150902eeb1797151	11	\\xcfa06cb32f6f3a7dc6914b6d5f5c3e99ff971349e9f78f4697949efed0695b4767c036d47a960d3633ea680ab4cfa45d0d418bbd8cebf6724c17e107734a6408	\\xf7abbe78b3544b53ab9f7428f7e7642986cb3b6860325cd1ccacb32f492094e8	0	10000000	1660856825000000	2
\.


--
-- Data for Name: refresh_commitments_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.refresh_commitments_default (melt_serial_id, rc, old_coin_pub, old_coin_sig, amount_with_fee_val, amount_with_fee_frac, noreveal_index) FROM stdin;
1	\\xfba5715e44cadcd1c139f5915a76350a11ba2457d1d31d9891322b900f9226f8caed861638bf15bb87705725fb22f50072160f42432c6255f446c529cfd2bbbc	\\xe3fc05d4a6a5a54b8f0c9b5215a95b5c36098be9431781d02b7ed0a38202ba59	\\x9a35ddc9c41569a4b36ffdab60cb13bde7b496f8a449667f5d2f6b23c098c4433be4aa317136b815e48a6698f740edfd20cd712b0c46ee5d792aab765f4a8e06	5	0	1
2	\\xf7fdd06bcd2b3bd1981e76d67ca253bc13c6f904fb1aaba5bdd07050398a9da9d888ac82ca69724d48180ee5f5cb7af346196dd3bb8976c4ad7acafb7b32de3a	\\xe3fc05d4a6a5a54b8f0c9b5215a95b5c36098be9431781d02b7ed0a38202ba59	\\xb434daf67ff385b4b99c2cff684d03d1bdd147a13c1ef881a239ed3f5d4fe12be5f6703549fb3aa512e3e1310662dbdbbe7665df1b2a1063423f42b2b68c9401	0	79000000	0
\.


--
-- Data for Name: refresh_revealed_coins_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.refresh_revealed_coins_default (rrc_serial, melt_serial_id, freshcoin_index, link_sig, denominations_serial, coin_ev, h_coin_ev, ev_sig, ewv) FROM stdin;
1	1	0	\\x0ee50132c43b3c4781a382754c9f2251deaf8f8392c48a1088799e28b8bf0dc1952a7128a1a51759bfe7950b06d8a70bec1b95fbf4660ca09a33efb94cba430f	100	\\x0000000100000100a7d5ad774df1ed49a810ba07f36972aeecd652b369ba8666928abc40a9a5681b12cf3a2abdfc221942bfeae9341c72d8d9c0313663a17b68a6c91e75a3d6e4c3f3d03e87b734f145bfa8dfa1a0acac159da4982bff06f6ef4e2f8da1dee73e16c44017b797c49c80c01063b4cb3b36fff4f251153ffbc0144dcc5e56edfcb741	\\x58dc07b770fbd1e6e253a3c4bc18387c150df881cb614b56913da06ac6aaab1e0c08784fb13618705a8dbeca7e699f0310cf3ce739e7dee0a7405466190ddb90	\\x0000000100000001837ccc3451e2128874253129a14749d62b783b100f529469c735f8296de92a9aa0d410d6f430e89f4e24d3adcca399c0a45dccc902da622237b36c9d95ec27b64baf37fa9eeb15354648fee974b2aa023127843ec8922a4c91128416431502b894ef94630c6a464ab84a294b8a628ecb79b877ce634055b195a4c85bf10c8abf	\\x0000000100010000
2	1	1	\\x124db548a74ca9095c8a69968c5342435d0bc6fabf722a491509dbf76d9c9259cfc5709dc63562334864e24dcf8a97ba04822fd7cc45a79d7719057ea3fb6702	193	\\x00000001000001000a8d1b588f2bca4290ade95201278be0ee48f13fae708458e4908e69d605c7ba7dc0aa8f93bad48f05e954c58c92dd397123a5f360ef44a0613e6f3c4372890681e835ad6a8f57cd8f35c809187165aa4256ae2622ffdb456cc887b4dcc9b9445e9bb592cadb994e5fad39cb653ecd65afa2fa7a99354598b3a8c142e9f55592	\\xb0c0b0b9a2cc27c465c775de47d30c3fc0037818a71ed4dbbb7a5033d0c59a3f4e2c7a6bf27b97a5f056caba3e737a32799cee2d3800ed637a4d3037eb2f94ca	\\x00000001000000015f77c30bf9d3dd08ce16cb65eda4c310eef3a83f862c354dfb85cd35f164d2ff1f7f1bbf476a9bc1f1de0bcd92b98980e82d94e0f2c1abf4a2bfb1d7b1af7d52e342b662365b784d9110ec9e439b5860cb49ad8c8bdf7202d227f21ed627d7f111062b3d04329a89620404f127a9bd0a2f09abdc8a80eda03c6ace9177deca45	\\x0000000100010000
3	1	2	\\x0b11e76c52150306b2d5823099743869fb355ac678c046986c0182a62677471fe00ef6959246d491f3b73502ff323114eb0f669a732a697244ee26ec8babbb00	193	\\x000000010000010085cec92cd059c84a8b0779a359a517529f6b216df2038dd49de06868b39828a86e8381bc7dd96a3db09d2e6d170775bbb5547469ca794f2f1beda2b4473bdf9d9bc70aeaaa928a8d2ce5343fb3fee38302c40f8a16442cf5c7634ae02fdebeb190233afa772d80e42c65ae15d420673e45f87ed344c4ca19aa5495efbf236a79	\\x3f8817487191d382da8b91026852fe27a00de0d60bbc190378835954eb236f2eefb010dd06f414565eaf449fa02b63b856cb68d280530279f5135ef219ccc81a	\\x00000001000000010fb04f78ff5302122c8472af829e9303d7ed050d6622961cf2091286e64cafdc60d9acdc7deb760ba4f7c1f68bc49ed5a8922e1f5b5ec57733ee29feb721f30e142a4bf254d2b9ee66f1197f82f57da2a13b4845199055e37e21177c6e75071c05abf2333e4f1124c342136a6a48931fc484b6df048b404d06daec94ee6eb99a	\\x0000000100010000
4	1	3	\\x96adfe5266bfaceab8af69bdc60a8d5075377386218ef1fd1fa4e72c431364f19ff501b09cde8ad3078000b3e7ab669a02be8af7415b6a57b55565ec5ef4420d	193	\\x00000001000001001abf656707e3afe28a6d72c2786b69a572ddb232eb90027c0671be64f686c3e963d491a5569aa55cc80b4e225a99c2ed266d2c67442dc1f0eabccba16ff186b5b552d5210cefdf491aa0b3b2f1bcdd3b35b7930cb5f67e89c62d249f2e26df48961c54d29060b7456fefadcf660bb97c3f02c1c7d4496035c3c89f81f1fef394	\\x5c1201e373476af13b0205d96084ae0cfa693c0b6c47ae3e96e3f647ca367bbbe07f011396b3c21b8c358fd9b88726752279f923151666fb0fb224209faba779	\\x000000010000000112c8508967f3fb3bfc138988dc2a801f8e1d97a9112622bc8bee126b4b5cd199b2bdebc4957e49d81ac3a13db8017ce6fdef17385cc8bd20c48f1cbf530f2c55c351c1fbcea2c37c288f8054070048860964475b8e70e0ccb52fd40ed8b4abc47548698b7b4b26e5ab84fb43bb928ece99a229e789f58694fed1fb2512048c09	\\x0000000100010000
5	1	4	\\xb3550215c0c64bc07473f5044e5c6edfde38f85c89f5b611551d4a664ddb54602e5b25068488dff6c3e2e74af564e6cdb818b7fa7e35baa6e8824fbfb4ecfe0f	193	\\x00000001000001006ab60b3a353e8c5f813fc4317b1e22fdfee3748bc6b94467ab301b43fc871663fd308a404e11d1c14a7247e4b50ae3201da196010eb8493394419667e51876d67496523067ef68bd5498e0a86b8f895b0f1dbdcfcdba6c20c574512d95aee527640be66ec59d9aac1defaabda95c39a9ea1ca7ce9181108a31633982026e4b48	\\xb95a39b990f11f1353ad9c5d4abbbdbe3d3d37c048ac6762203f8ffa2dd19b5668311a5f04e9385cfa6f1991dc07a2cebd25ab1581ba80a5b51c93f5356e3ad0	\\x00000001000000017ce5bd413933aa4d13c3a7b9a923545e75727013121d0701010e57d7a302545176a23eda6d998eba8960e4a9b084df1779766823eaa6cde5aed3109b269b25b8bc8b0fdb825d5772f36bc447cc1dda3d0af5056936a5130f5c9bc6d439d74b1920295428c27a84c0c3c820f09d353b1d6e0ac2426f63d02f8e5ab71205b1d07c	\\x0000000100010000
6	1	5	\\x07d82176e6dfb20b9db39947de7e3d49a68e82d42cbcca255d62d0963e9ef8c61f4f56566fe10fe9d379a967577f9fa4c7e0e38dabbb05313060f0723715060a	193	\\x000000010000010068019c1330b91955aa056790c272f9ea076ae7dc3eb832ce4d3e97c46dceb1fd775f7422a95e4454ae16d27f17cd5546454fcd3fab422007df74a79b6c1c192a1e2355865b257e82dfab1aab35c6d074f921a3d30a9184f241dbd2944f43a2c99419ad70e51a46fe470f037783a5751f9a147d6d36006133cc202368496b83c6	\\xa4d11c321fdbff7774760715d2b344bae786491b073689a7f5fd0c56bf982404b9523263f5aeee37396d08db91b36530bd89f35642b72c3fee638f41049375a2	\\x000000010000000198f7235e7184e23b719b3080a08db1d9d4b531685373c02ade840411bbc6723009cac813503f5489bfd3f2cc63e964ca1ba907662e45ec2cae0725f0620044682866de386e6c3c866574cf57f247dc4ba5a1aa2168fc2de48e928fb5741312418eb751ebbc0db6cf0aa0411b9a7ed4f68c412235df6586604bd0f2d8acb4fb6a	\\x0000000100010000
7	1	6	\\x73ae9992421dfef946ea08477a882fc2e1c2b414789955ab1ac4dbffbda42fafa463fdb9fa6ee866f87760091b60bab50f283e7e2e18c4cd9939ee2970e4bb03	193	\\x00000001000001002920d56ad97072f34ed38771adb29a10574e3745dcab13328a84a48772c4f48a9970a89475b15e266a04301787ea5fde8364136013cf3d48c3c58f76a29608f816d462a7c84e2c944fa90c969c0a6f4a8b98bda411eeee9f30b0b31bb025b483537bb34d88bc59dff4f5be100eec018cc7b732a2e57f6316cf783b0e23a9ac11	\\x0e271da9373cdb2ffc8e0d321a847b045b9ec9295215be324c1eb423cad8ce36f6ab8a5d05bc592cc66705ba2c336dec51b998001341d4b9b8b6c9a397ab487a	\\x000000010000000188fed186e7cdbd54d2237a769675fe1fe576a9847b7644cbcba5312d7a86a9340e415ed2ad43105a806408b7b32507045d1d27e8b6f80dc9b67d22fd11220940ca78dc3f9c1041d32336dff9d14a2e133ba8fdc5c2d79f1eee1319b3309493d989881a63ccabe8481f2bc7258d8639de38fd4a044d9eb796f86291caf0927cf5	\\x0000000100010000
8	1	7	\\x1de5274463c1c43a193491191c11c02a70a1c39e966632e903227e28674e55f63f45ba8994bcb0692e83e4e4fd02fd5661b4f8726bf45d56555ab8cbde58be0f	193	\\x000000010000010071354f5df9c451350fa7eb3805a48cd6cec6f1a10baf4550287acd3a4c64ffe2311eb70cfc48842a1ad8271ed99d210c961ead0247b09546d8e02310ef1bec75dbac7a426f569230c390f7fc5f478e56398693b569bd60d6e698b0e3530f72371a3a52632c00ae6d776eaa4e4ff1a3345c3c77012ecc7cd3b217791d03fba9a6	\\x2b12c0303248e31985d8228b264b46a3d2dc5493644b9942fdc8d9ecbbddce59e71667b480aa7c8b7f71f07e726e78cff5b1d6f0a3cca396d82d5953c52dc89a	\\x000000010000000118aef7f145d0f300c25fd6b03176d7208f4693cdbb8d6b354a21fbbfd30d4b0bbcdae1ade6d4f47711151956288bb758a441db4dd4ae88a57730c1c3f440066d013c3b86cdd12fe8404142ed4ccfd7e52d199e4a26208e3985ab26e639e94697ccadfc841052641bf8349230dfcdad2e57d15a4603610da5e4025fb7c83b0f20	\\x0000000100010000
9	1	8	\\xd789c88d33e3f723e5f58f24bb15f94707f4841ee399c3d65551d66312c6df578d91bbf07a140ae44a0ba56a46d9ec3f34dd32e00890e219e71489a93c0f2204	193	\\x00000001000001007dd428085c6a18c5f8d6a9a1a7b83f71be2592143fa4038f17b500c27a5f3f68775872fe5a53ae39205117208e22492d7ab62fe9ac67dda3394119ebc257354f26d20bbcfc2f63e74c9c04e474daaff532f9fcfb37369f48e53ae8fc74faf668e69b3925781c643084beadca47afe420c5a3b24296f049641215d88a200a3221	\\xaaba3575a62869d3a1d83816f62c6b92b0c582bf24edd18d4f36f0b3b15995e3e17093c3654bd4e8f6555fe89b3b1ba861086cef9eca37ea0c7c8b51c81a3b26	\\x000000010000000182d33fc5f789b6a9a0b0f9fd36156d604a110bd7626c6dd3056b5bc5f6932f313881f631265e9d16936a08b261da2bc741b84445d5b540d1b21be6629fde6a608db1bfb82e7aa26cd783a57d52879fd95c04bc9ace93fbd55186f5eb7734e8f2317554d33b2d922b7a897ff9c0c87561b55d34e2e9a55515cf34882f59229366	\\x0000000100010000
10	1	9	\\xfe2ad6ab210c04ca047d49bed38d051e7d293b2f5d60a826f898213e302da3f3e4547f6cc13fa78575f39449f4c27dd05b95666e72e32e4462144a58c862db0a	121	\\x000000010000010027d49f1ced7be536bc03c1a86bf94dcf34dfecdd9885b473d6b643b0cbc12d262642e7321268e088ada49f555a81c7f6da32ee021816262c68944c76fa41cb07c63bdf273e24aad765ff6baa12e3c21d70058a7300e7aca590824ae2501c806f92f591bb321c3b6ed35496ff177b58d4ee57960b43f9c4dd98bc39918f62699b	\\x3aa065b39a8787180c41eae30e7f7f93c1d3d8dc2f7f1b5e081696c907a3a16b1d12bdd0a5d1d738056d6b5bd07b9dd59da08b8ec22d27fffda0d4537c816b9b	\\x0000000100000001bf8813f4565514c0288191bdbdce90497c5c0ba234690dd98ba4904acac26bf5c573dbee60f2560204e4cdd1fbc2669ff750c820b6fca9f5449563d7e34a493e2816da6fb3b86c21810b1cdfe49647d031fb2f37643e322b4b4638fcdeb34fa1a018678105ece702774a3b528329c1fd4ec28c003d934c37830ef5d2258fdfa5	\\x0000000100010000
11	1	10	\\xb07f7a23adb0d6b8c854b33e0346efbe5399cb78841a414985de6dc50baaaa7169a8b9a7f82d576776e7fbb7c0ccb5e3433587a62d892e9ca872e04748bde006	121	\\x0000000100000100191c8eafd1a060a6f85d78fe27e314ecfaace5a1512f7f2a904258d0fdcd5d31e7827efe46aa9d7cb5f03884519db38d0aa012a1d853c30a775c3c7dffe640da0f6f6c758fa8fe0a3342283b67479f0f1d966280623b98120a7494b8756311e050d708e533a5cba2e95b6e6170fdd25134977ca8e975b694525ab08b33fddbdc	\\x9008a2e19016356394174062ee797a47bc8bc2ef9f04b5cff5da14a7b5d1e4ee5c4c49692d3c5dd16e46b7c476c2ef4fb945a3c14373f39b6f83725514d5f517	\\x00000001000000011f942af266ec6cb3a1bddfb27388dc5df6c482b34df6cffd770c6c0301790cec95db3efbb9c5fc86ef613c18268be8c49ceeafd17662afe691d06f2d9dd60ac6f72db8d21af01ece65d4dbfb5c9631d7af0a09f7c60be90053f88ad53efe1b1510c3b2832dc1a247e9e245679d05d0659af662bd68d953eccd3d4f10bc0447b3	\\x0000000100010000
12	1	11	\\xb342c3712c70dc000cc503ea71cc073d6bc214e0132b789440351f925b076a2695b513394fd904122dbab08202b23d2aecfeec372d138e9bb420558ad1392402	121	\\x0000000100000100a0312c1333aa5080af9f0e87c26f8093bd214f85233d678bd8c6d4d273fbddae143f8918769b666372e712f40141eaa74723422773941cca4008ae35c7d25973b3ff2c71558490cb25d102d47d417b668e4a7f42f119be6431b9d5ee6572203ed0a8f5c1c2afda16394e7e1c72769eb5bad033f42199d641759eecb59071cd93	\\x5a566e2d4f59f9c0a7ee3a88675c0e4ed82d314158dc749a863968ba0230cdd819b16e27236744d726e2a8ec820ec116ea23ec4b8d773312c11a91394f886ec3	\\x0000000100000001768d9a81bec681c37bae203bdd6fb5c5812225f3006c563636f39b0738c3b643e85652c629b825228c9c19c11c96d1ceb9e18608780c511060925089cb21cf5c018b492a8c77890d2b149820c1cbd2c606e8960b36b91e8e974d60ae2c634a205ce9aeaa6f0686f96ec1f020495265b997e469958d81ffe66be8e299f3cd5516	\\x0000000100010000
13	2	0	\\xc7e74a99e08bece17a84f5864ac2c7a3880cb8ee3acdc54f13d8bc6746d6a0e92cb76134b0c2f15b73fb5998af1d075424a4f264bfc2bf7887228d5be47c0602	121	\\x00000001000001006754e5dc587b96919178ef68e9f959ed98bb6a6a30e9a0a6033f9406f413930ec68521c3936ebca5f2ced167249372cf7305a717b7b550f1d11f99725f1f1b1a1f32057269fc91c32783d1abfd4f29ba52e0b661bf90160a3c02a6551e9d3fc9358814334816af8690cd83a997bec8ee1c0969c6560e3aafcb993c3db93608cf	\\xd757430d6281391a4474a25a303c4a621780c365b39b9d8cf87fec5a48bb0e197da489f20818e7c3f5432ffb49d128b765e6f7ca5b781359cc04bf1c51c54ef6	\\x00000001000000016feaed3eea8c788446386d5f9e53d39002ed7e2f8816dc41fca2e823ce324ddc556d2817337a39c5651df5f4424dd79c8bb8fab9dde85d6f61d9eb7de8d64d2b525b78031ead0bfc31bbe95d6790397248b5e23c08d9994126788f31ad1a3af048ee39effc437e9948ca4f61577983c80485039229e21e32bd9c823aed1d3c7c	\\x0000000100010000
14	2	1	\\x4d3fed0b4531eafd35e03dd80c3fbbda1e0359f037c0e9d52a67ae81218c1a70f26fadd1282bd124b424b70466770d0d97363e7666fe89b097730e1bffca8303	121	\\x00000001000001002f96a8cd48231cb98a39b6053f537ce21a7a95953d3509cc12bd5c8c6fbe24d6984386f91e9ce30389c0ec210f74738f2cb9214ee6a2ddd736201b5c89b99ffb4581e67554c713a19fb1f94dee07edad8a996d6f7bdd69bdaa90332173d26a78b58485892dce9380ed8773e0dc79d36bc775e65d2907b8e527b5cff1ca2000f3	\\xb7423c3fd77b446bf52c4998dbfdefa03641295f7301017d1a1f35fe3776e081f7098c039c8b651b53e0beed20283ee9cce58589222297ee373672b84b44002f	\\x00000001000000010e63e6875d7ae11a1b42abd6d057ad2e5b89c836d1d52e72c10dcc4febebf3453a1e6b2bd8b9bc5577148b48a3137efbe1c63dbc97f857beb7626cbc9890b7a75e104475404ea87a2928fd96c26cd737ccf091bffccfedd587a18373cff9d2dd7cc5caf2c172fe60ff9842de80128126e0796cf951c295b793ed9752f9120ac1	\\x0000000100010000
15	2	2	\\xe85ada2bedad2332ba7433b35d60d9a354817255c3bc6273a8eeb904644545d894ccc8d351f4fea0f2df07a51e99a12a8bb6bb005115b36e418e4b78515df00a	121	\\x00000001000001008169e5678bc4cf6b4fb00f8f87064c38003a54cf1cc25be450bbe82d58ccb40d46dd05a42387bd572c6a8a935044854a2317be8aefb4540bd35ddd8efbc61730914e1e8d9dc9ea4d3ddf458da029f265b6a78edb440ba24ab4a83c11472ad0f0aa9586d83e40828eb72af299a259091e4e9d3fb8ca545ca7929345d078d32ff8	\\xef0087caace06e7ea89aa864e82f5da47ae02079a31d49b3dd147e4fd746686a1f007a529cb4da1f2c3714f407bffa0eb6577811e3041cae28121f201de9d273	\\x0000000100000001968b3a36939a39295c65c5dec95e631144de4c1eef1a2893450997ce06764753abf3104e39b0902f378a3750050b892bebd1c3c507f7dc2c1f439a9e8716e2551461a8f2d66a0a5ef2ca50958101ab5dd510c7c7fd4891b6c4404a5650f82bc0cbd38125b34c31e8c00ea4a8b89014b3a503419904f5e2a8213521c2b3648003	\\x0000000100010000
16	2	3	\\xad8c9dfd895926a44f322c47ed3493d83a265e4718388ef7835a9e97926dc09b503d108a13da4959c4cb3823625f73307bc1768d449f7089674e078143150c0b	121	\\x00000001000001006725852675b6dc99fa8d97cded624fb59b2523c8e79b02143225e71d738a050d93e73f26cd5ea650831dffbba8e786275f00b2fa12625a0a5fa9403cfff8d9887565e54b730c0cc1b2e8cc3eaf7e97edf6fd273e805272a3f7afa7c302dec7158bc4e66e40969b383057e4c86005f4c9ad1a0ad6133e6f3a05aa63fa30a0a143	\\xa0b83274bc6505d409cdc407dd55be2155a57a082ec65351a66f7b7278aec0ff82182e32bd3ef2e7909b2402f7dd0ebf9d7260b0ffa712d656a8c581269c8822	\\x00000001000000014995f69c83b8f5ba78607ca8f7f81b25cedd3dffab657977ffbd751fb7d0facedba3efbd1968ff319c2425a3d2c92492ce5280af02f8ce6a9674b15924e6b1723da2063988de8fc499b5722ebfecaf782e0a9be8f83e1477a7508d19ed7c0629192f9fe0d46b0aa78f914669e3e257b4693e92bc3ad418082132eab879ba8947	\\x0000000100010000
17	2	4	\\xa6b806d386eccc3265e93fce39f1d2613f71d579df0061d4bc206d42780fc671ebaa729b43083dd46d66211af485476bffd8705c248845851c8a4b7ff08e0c05	121	\\x0000000100000100afaebe2d6c04ef72ed39555d05a51e521f149077f4c1f0250200a8312b9de32c83b450d3dbe4f2c3f3b63e507e24bf009c2b9879e9120e28cb529128913cbd8cd5c3f0ea4b9d3f9181704768d0f4359cd09738d78a549484d7cf034307a2bc9715bf62aa30948c1e7a4c4369506cb7934f4580884b7eccd690e65ed6bfb0c90a	\\x5753ee32362ff9781176bc1b2a3b8b9e6fb5c2e47fca1208dbe1ad24564895648bff87089dd492079d93fde9f1dcd86979ff4341bcd3b262af6fb9bb2eb82136	\\x000000010000000124d51d2b4b9d9b240b6e148d96e4cc3f7404d40e649f2d6a2286f345275be0375f3e671b85623edf9bb15fba1b0b3d844ca31dc5e31e7986721c498c34a25f2e9b091a6f887aaa1b27210488c915a7f35ae0f953068c76d482a79f6f98efe57bf759ef9f1fd7e6cfb6c819942442dd183705b903166f51aa811c9a82101e413f	\\x0000000100010000
18	2	5	\\xac23989f1670743468a7f2138a1a4a1e05008e7fca6144cfe1c32c066aafe40d462c98ed109d13207d13e51e966313779cc7dbf48afc1eb9b6e3307b1ecdd303	121	\\x000000010000010064aeca422667f39f0a0a062a689147adff5369429441d6f1fb6e116dbe3720feaa7ba16bf3bf9d118667697daa50054b82b8b02d302c16854062d236158e2dc274a122c857f7b837111bde177682bdcd49b1c410eea24e0a9e8a79236c1af17d04f26dc996de79ec20bacbb1f7cbc2f68c5580acb8889c1a4f548bcb69abca09	\\x8b4ab810e5734dfadc13127eb27bbfed343ab97f814ff9f9a699c90522b5cb1e10e1455fe85f0154198b6608f2a70ea6cd714f6588fc06417c1adcda6df6e658	\\x0000000100000001a36f33df105dde3ed027aedc2820bcc5bb57f7ac99b6c1ccb3c7d0f1e32895a7106974a42b3dde3a08c38a992835d4b4b4d65e6187148476fbb0eed75f05b1e56d3cc373966223a5d5522acc9e319607b083fea7120fa85ac0a373a7963190e30abd1f1cda5db57e9a83ad9e7178352c13f029bda1d9361183bcedae9506d7ab	\\x0000000100010000
19	2	6	\\xe7e49157f48ec6aef2e67f83e184c7d1cb47638aae33653399b50a86f78a9d243ed2d3d39c9d2daed7c4b311596ab9db90bd6bf02dffab4e985777a00c22af0c	121	\\x00000001000001004834ec194619c84e3654f6ef68f2637b3e0461a3b7827e0dcabdebd14c3ea124395a36ab66c7473ab4de603f7e335b91e04b924869be5d3e384f9cdabab150c834ee2181345b366630232bb88311b77f764a130c5c1745c3c909073f873888b8ed8ca41671c5c15395c8c35f757577e13449b7350b228d1eb9e6d395d8a75190	\\x332e4e4dd2beb8fca8897dc353bd011b3fd923523268d092f746c5b188966d5c0bbdcc686fb2e01041dae74b8ccbbae13778e3ce87a3b74dba9a648147a33c5a	\\x0000000100000001265916c06c078055d2ca6ffc8c4d5b18c85a415b1c891e631a40bc99fdbf8f389166a44261351bba459bc715fd99571b54c0e6793896c6757d316f850e3b7208fb781d0ca65271b85acf443661939991cb3bf699eddd173b67a5ffc66855cdf476c06e42bf76dfd2b8888ea9e42b7d4149554972c0b9a8c9a71c2112e65be3c9	\\x0000000100010000
20	2	7	\\xdc8581f9110de2c357956da2dd873ad304ce87c2647671c797a694d83417de9e31557673c8634ebecb1ebe8cccef6bdb5dc3f48c27cc694cec7196452af6ed0c	121	\\x000000010000010032958efb1f0ef03c6791239307813bf4e7175af59ec4982dbba42df9a5aede284bdbcc19fc94689074b19501f90c29cfa16d9ba322fe830792c5c6077b37900b2076b01cb0420630c370778ca1fb1ab196453dbb22c2bd03032b9399282daa450d8b26570a3f8013fc704d927c38bc6fb03850c7f8410f3d4eb6660afaf6325e	\\x00067c9dddc4c55b359ccccca9b589c79ece61dd5f621a5840fc59a5a31d216e659b571bc806a0280b6cd9dd9df87da0ddfee5e6d3484c0cf4d032864648b7ed	\\x00000001000000018a66c2adcb77469a5bd7003db87a23e517ad969881fba465d17b29c7aefa0a214470cdb858b5a196067a0d5a8b454851e0d43f3b5073fbbf7dd5e5025b8c00be95221ae1a0630a3492934a7ceaef93a554a491665231c367d60f5f6114b9054d2e182f9292351faa042c01e1020db200a3e85e55e6406ccf10a945d4c5993a15	\\x0000000100010000
21	2	8	\\xe68784b320948c2b5ae368d12d66cfdae72d09e4ebfe3edc2d6d068f082da34149914db488c2c6be9f61f5bbbc022e8d24dece07b37a688b8c96b41009d5690c	121	\\x0000000100000100c29aed829eb4f66fdf93453322a427cea51c7121d7365a8f268f4e9cf27f88b3c42cbd0b797ec614f5f87be98be0b9567321fb8e515397b3dde645bf8e7bfeb9b7878b41cbefbc2daaf3d2d940022f6841e2fa85aa672afdc577b2f95c293076a50a61942e2d20a9fdf771889c6cc9fa6ec96df6c33c849bc57705a24eedc329	\\xb8241a8b4aa7e9581a7007a9abe008a1b1dfef72fd3eebf7c3e2bcc31f56d9cc2314b91bbc4cdcd3aa3a7953ad8456d97ddb410d76b06e59d5748cfffd9b9b76	\\x00000001000000010f5f1f6b3ce86d3eb60412953de510852a9f0c75062f49c9091e4b680b20b94f48945c1e44b1661b3b65a9c3c8b6825c84916a8905f6d7e0f6a9c9c6ed37e4109e17902403a640139164c5234edffda2de5c5c7dc1f92c20bd110098ae2302f03070bc06d72162a6969c422dabd333e6ae3d980c1e4ab263b29d1214c6dee47d	\\x0000000100010000
22	2	9	\\x05841a0150d509f9eed5b576fc03a459b384737a54848b6576d9f59d8d6edef3d3e0bb86e92e3313437241e8bd38a17e17b46cc299676c314093667516776c07	121	\\x000000010000010020edb0de9177d47d7bd42dbc2a55685d925edb17d002c1298f487fe280346d9482e605e9afb2ad17596f1032d0bc958bd69020e0418d7bffc86cb35f3b1c44c4cf2c584012b14711d06ea257afaed34554022c541802294d6cd0ca57fed93630157d12098108284ae032213f1c5a1e853c019c2930aa3c56bbae60e2c4273940	\\x807606c7f72fc09d4d0569631aed80f94f14cb23367c42121d89be6e012e79a8efd41f9a68a87b440dfe8979ae783dfae0015e7911b005caeef3329292b46d81	\\x00000001000000012b70fdec4a6d8c8498f0b2b0b7237547a3d5ff6bcb88b401ce532e57fac6cc08381e6b22408a50fad26d5492aa3e4d96db2bd7573ad2161ef1b48dc0da21af05468319602b0c9a0f526a3a359f20e60317255139781a9df5714a37ca17d1974c4261cf060125f51a98c6474e1a35328237f2ff053ab349d001df395af7833aeb	\\x0000000100010000
23	2	10	\\x53ed89ddc610887da56b1c0319fd480410cbebf81ef8ca2d0a989f3550b6bf88fa7ca42aeb0ec70cc843e475df9d123eb18e02ac1d168fb50aeba8a385d2b903	121	\\x0000000100000100c323c0aad0a0660c10fe27e0ae684983a1746347988aa4a5dadbc9ff81063c0a025337cb4bbb3bfc69efddc01b97d0ca05e30642ac6990ccbfa39b514dec0445e2eab46cc20f9ebeb3442426af2c23c2205a0c8774cb31ac2d2410c8794e333134d9fee1400620ab1b2cea7111cf3f0b3cf0f3aaa9ae0617dbba481207d2b8c0	\\xdb87460038489c520f51b57c1128d6368797fd2058ec154072d5e433079ce9d363c6c39e83d2f79be3c9470b945295b3c3274945eeb4a3f53bddeca0b80d932e	\\x0000000100000001960741771ede6d33283d512dd2b6ff171cc30218e24b2c9d497cceb888b4c8a064cf583b0b520163baa0143ed3f6438d8b4ca49f22142955f999bb8b91de30f07f3bb2d8bd5ec5e78864fd8e54bac72ae033fc81f89941f2a6b4c8395460e3697719ce6a15a9b7901a7dad07c50290b96bd19d5bbd34b4700d99983108766788	\\x0000000100010000
24	2	11	\\xf3784eb7b3a8735e351ef695fc9cee82cddce2f542eb81cea67d773b8abd6221febd85b7f457a0913293cd7c062b775aa60442152f748979e29ccba32b900707	121	\\x00000001000001004c480fb6344819a7c98c4d7589a98f236dfa3d3765d8889608117c04a00581a6e59c35060d5748631f6acdb20e6f07f84159e35c597da8b54d8adfaef559b3189f6eb372763b7b0ea7b150f79ea0552b947bb09a3a1d41fdd775db835669cdbf4b8c05fc61bffcaa5443b8811a37b70a4951ec0a59f20b81023b290ad1ace1c8	\\xc17b5196a48ddaad4ab7d2cc362672eb9a44f5f455145e06629e2ef3e831df89bc4e0ca6ddebfa71a0373a50558e908ddc8b7c6734b7d783606b578a1f07106d	\\x000000010000000143b6d26e450873723d486037327bdbb889e2456c549d5856ce53e111919056c86b2ab9766b0e11972af4d7b9ecbca0990f88f50fbfcf1833c5119bdf9a009fc216b2b7e216dbf5b60ada65a03b1a6f3927583b0acfc4d0d1d96686d8613a3da34c77a7442e0bb44c3ed724ba02f3d934bdf52c2d26601649743c04fcfeef0f3a	\\x0000000100010000
25	2	12	\\x4c2b83e0142870cf135c996e37a8bb8bb1eb3e633ea21dd8da4c208155760d77445365c1775977fdf3d7dd9347430d760ea92b5b9ac42b036c2318254f1ea402	121	\\x0000000100000100b4ec7fd19ffac84ee18d57d91efe3201fd6a59d78efb1739fcb60f01d0eabc5332c0d376f9fefd3e7b4ab72bbce717af5850c95c22b8539c1a270cd571f10c9fd19383a1d65082bdc1c47971aef0a2061208a56bbc1bd02e3bc86e1bd8dfcdbb7198d1e2ff88397475209d13e145af5226538de889303543d95cb915b3788aaa	\\x5971ee6e9bd450fcdf673b7d35a96b15c9a0a2df1dacfc57f828f80ab62d31e883bb662966fdb06be7e9ada82aa9dcfadfe6f7fe39f27402f51df01f601730b0	\\x00000001000000013f159bcbbfb5ec78476b5cab981c12bcc93aebc4fc9c601d2acfeb8860208e0d5bf92896dc1b2b2809cf25ac54e9d95adb4a8d54401b16ea0dbeb78ea930a59bb7db3719013728eba7c853fa9a99460122088b3f612ddd8eee4d20596c3a0efa355ce7ee1ee0315147453983928426dc9b403fc9fcffc3736782341aa0ddf08a	\\x0000000100010000
26	2	13	\\x14a638b11f60be6e4d08c99e005b49f1cc050dc8f7abc243e54653a83e5f4b109e22e83e2850943fe1f5fb3fed42673fe8d41734dea5d3805e2964d35ef13b04	121	\\x0000000100000100590b602980a12d15f840c87a5cc807243ca6bfd8679a786f17381c4d141e7ff37e84657e498bc04fe7eacb142d6a6477480be03d53f7292612859bf2937b094bff813997b57e04279fe59828d8d09afd5b03d31959c6a06f1d1cba4faed4a07100ce0ac8b5d6e81221a4df5bf0823f5ad792c0d952da8f779c64edbe6bcd0b0b	\\x79ccb3e7a9d8c7d346421a75fe2a0ad975dfea8c52f9af05e58f1852ceafb6706ba54ad5c6ccb03a06844a3282793d65f2d883f1ba8aba26845b6a4f645fa560	\\x0000000100000001140d5d697de4b42a6ff392fdecd0378bbe775b1d294cd40e1917b6f1379ae0e17993fb23a71bab7cb5a6113681355a56b9adf83a7a18440041371f64ffe7e02606deec7d00bbe5bdea384ff789a0b3a808abe088ae7cd3668e966b6420c3539888785d8adc4b5ae95a429ecbb4a31675fe5d1da5b3a67a1d55402edcf684e7f6	\\x0000000100010000
27	2	14	\\x025c560a7ba906148c1ce220d223a5800b4a0f16bc4ae6fce03c911b7bc84209e11096c567ef258158753f9168f48151023fb66be58b756e23a0028f79e4df05	121	\\x000000010000010014785e7296d51667fcc820c00b52b153dc553272cd624f96d05e0c3e39f12930fbe0f8415f48ad3685c4cfe2fbb022dab3d9ad4047803dcdbca38a61518afa073c5e3a9f3d3039b939dbf29d36144337b027f558495823d82cec66d4e13bd76a70e02dc1e7b34883fab66d8e838fc70489d75fccccc0c3388153dcc20f5a5d38	\\xe2847dc2e0683f01e41bd147f26311e849d0b3f738dcea9aad5b3f38a9106aa8699e294cbe880951ae0adb91576cb113c33ef23d61859ce4a9e0be261823454b	\\x0000000100000001c149fb1b7d6f7883a74e1ed35fafbbcc490b3dc735adcbea81eeb9d05e8c60dc3d8df377064e6e3a1265af1a3d81a6d455e03f6dadd611809bb912de239712f0590a0a1ac3a4d77a52dd30007afeb3c15ac8b48a0d8a80a2662c7525cdc1c28335c070b0cf58587e326a73c49b4693bb25464015c429a4daabe4394d99b29edf	\\x0000000100010000
28	2	15	\\x6c666ef11c923487175e71fa31a53da5087eca6fcc86ea9422a7f65736453b46d2e0949cda5f80e5eb52eef12d202f4c4a52f3fdb885d53e7a5dd42342513f0f	121	\\x000000010000010037d44f7b8b73ad977f31f2317723af805c672e33a809353cb493432b6001ea71be0a5b2dad68b0e0af77a39c898bcc0a61a10f9abfdf5052de01d236e5af02fa6296ca43814589ab69b5bccffcd93e59546668714fec2b9fcd2bd682b3a1ced4ac511d15d75bbb4aa9e1ed9a4f519331e821c76997d7004b7b07525b4c8c4145	\\x392e88182cf5ac52489a610ce79947c9242e7164dc4754c98ebe63b4f454e34bebf6c821c5d998466130836a6509f097a18344f5315d9073eaad57d78bf7acc4	\\x000000010000000183cfea8ca19a4b4c11e5783388b30a9bf3197fc9f7152ed88591cdb487c2ef5acd464a9deea38e028c4d208bca4373bee6ba4542de28569d9eb4846340b645c6075196ed7f2f0fc41046931793d1e492e3f6c33eca8486faa0392b63c02b91ae0c930b8dc9447fa5e6b701d34868d3026815376e422db83563d182809cb06f8d	\\x0000000100010000
29	2	16	\\xe9724182d82798f7e2f0179324950b7d0b8c644a7f3286dbf1f84afd3b8703251006b79fa20617a46da9727d6c3998c8d3e5fd8a4042a3774a0d31c0d7901a07	121	\\x00000001000001008d2062484b5a1d8282e1048193e5aaf10feb3d1dda78add998b73fd61e3f6bb275b8e2ec461727473de41b728b69f9d6fbca9dd49ed106a691cd539c5e18dd0799fa4852c3867b0b3a24962efa6132deff790042c672b27a4ad7f65b65a60820c06b5f75a09f2aa2e334a8082e9fd49de4e5969efa1879ec80beea811f8be00f	\\x5aad2e575e892f7797c67b2a4e10e394e7b0b032780c3f8f3114de892fb51aec3da47c5733911d6a0c4624b38f829d7ed28968ca1b261c07606764bc57f08528	\\x00000001000000011c41b2ce98a70a63ed8070beb45dbc3fb12030f38bb6ad53f938d6fbd937e60d33aba040af19de091c6b8789555b2c0e7dd9c3fab399de06044ff3025397e0d7b60a38c993ed9b6aa80850957cd25f6c19c58f7083721c8ee554729cfebf5dc721214093d69b0580bcea6c82e4f8e7a0a733b68116478ae976cf10c7ecbdb062	\\x0000000100010000
30	2	17	\\xf13327e67a48cbecdf29a0b1c2759f60f7d745f8049ae1305e31243ac52342b404b3d84e9743c48cfe770b5a7ac0afe96f7dc8cb8740fb1a892105787e4e9c01	121	\\x0000000100000100a627d731acfea13b27c4da87e0fe668c6e49b8f0bf14001743d8c205dbb466ea08c25c4f87a478ba7792ff4c9519d8dc21f4ecb347a5318a48c9096496f82a33ad19bfa3ae5708fd498474e3bd50b5e175a6c44a5833c44662459c4436d65c5c85cb5618dbca59f45e13567da0baaa2d70916e114227b627048bb1c93fd9f6f0	\\x67f6fd29401b639d0cc058752541694f79278d5a56c2e5ca08dea18570f6502b16fdf78fcc50e9699dd39bbb2c531e2b3d06b10b6ab68a00a99e2a86aecee3d3	\\x000000010000000106517077ec264215b9e187fde2804b172bdcb30806b62d174797ec3421205f96bc92c2c656353931b16030da08b85084ab747319a702e5f6012339a58d9316d46290648fde650ae99864c28ec5dee59f7b56e91702886e75b992c65671aab03919ea6c9f0bdab12e070daf6217c4549c81a2e10012321381b62f3cafc2909ef7	\\x0000000100010000
31	2	18	\\x97bbf9258ef37ef4cbe17b73696b46d5baaf265b28d2e9341b7fdbb9a68c8df93782524849e011e48609e86827a5aacdd14d960780f48a217ee9ada2a1402500	121	\\x0000000100000100241484db0fac6c2c7d738b5366e3834e4d434154e03885222652166223ac7917e3beec0f31e5ebf94bc6e388fcc424f2ac0a863a1b0f1ccc8d45c9f5bcc26fd42f948fa05c2fa30184da01153eb8b7a045ca42633a879477f31995f0c2497077508beeea64256b55785df9bdd725f3cf85da7a218fa046c5f3577e779a14f817	\\xe477cd9754ee028ec9a656d85fdd87b6f95889c8be66d03adf011aeb4712ec9ae95a9cbce769b2d3a74c5898480baa57c2c26c5a308d248b4d11478f8af4dd18	\\x000000010000000175f5a85966cee3e85bbc5c3599dc98398f8453f697440b216fd925d6b0b81e759999f223a589eb39b4abe81db9d8c455f79711bbcd0e065282a4b9e95268254a0ef8589aea3ff025f62665b904d6ef0625736d671e5335a7757de9f586df6576bb5edbf6325f11d8c2d41a2e7298a65768ec92a88e82bcd8f6c9a33f0d0d483d	\\x0000000100010000
32	2	19	\\x1f158f21d077440bce917f70edeb5bd0a80d537ab56ff2fef7a30c9a3fc2444c44274cc74d94f6f80319d79176ff4da00d211fc756532ee9216f778455928307	121	\\x000000010000010045bc3937031b9862edbbab6cc22478fcdf343116a3d72a012ef6272789892b9a3979183e399db554167bafe297aca989d24ac7b698f5ae40612e75c5f73e2f92f4846b1e47094ade36d7a619a4ed7c566c266766f97c7bdf413bf1e55ee7f6e22ba205080fefae498f0b343da2c54529ff3385b9a390d188f1d10a869d05dd0b	\\x58f9290a997dadb89a4bb19087b714faa98d23b669c5d9c24585d6ddec9b7e92da55d316bf834740e0a01f0143aaa4513c8b2ef8b89189cb3f71df85fe963e1a	\\x000000010000000176543e083b88b88a762940ed80b0d7f63919d632d11734711d36da1fb80370749ec61ea20589a6cefc5293d5a38596ef16544daae816773974b8786f58fd36b2585504a2956994078da99b442d4f49c248660c5536287c31207dfb48084e2d593b0d2cc1cdd66c1cf5abcfbac9f23d1a8063e7d3d3f2e23ee7d3b493c48480e3	\\x0000000100010000
33	2	20	\\x561e1067794746bc5c4eb4fbfac47ada24740702437277b24de320a6689e344e2de570f533ce419cc21d1405834dc044757fbef36ebb82bcf5968974e530ea01	121	\\x0000000100000100bc30d500fc54b5464444363fd7f06aa37c50937ae99698ec0c9a7151b969ffdacdec38528addf4e10e8e9abdab12179bf4bfb09f2c05ce4f58d265b87cf9a71398c58e098c47dcdf2c902aba88f2b7bf98453eebe856667622278d43b6bbe6370cc73493ad64926cfb35e64f7cc8fdd31c9f29f424a966c9e608c84489eedb2b	\\xdc813cf42befbb23a7f096a11e2e94285619ba03b98b37b629fbfdfda84c0c440fc48539bba96ede0024cff207bc8bf4b85318a7f255051815b06a30e13435eb	\\x0000000100000001165dbaceab6f3d83243928423b95497bbe9d5a30aa9fa790e862db64454c2181f69fc18ce096bea82ffccd4be987da077c7535391ea1ee344bc7464997ca17cd8616d11e286f8fad97a53c6c57855eac0e0b547e4db39d67d8b4fdf28f8cda9e02bd557d3c4af65d4aab53a059f34f0f424d046688a9a720098ac94fc72875ed	\\x0000000100010000
34	2	21	\\x2503f3a35931a927a2f533873b7fc47a8c1f955438c5b60a88228792f6d42c419764ad486ca2e76edfd318ccef4a48bc775b69dbfa3f3ddf5aba0cbee2ee0a02	121	\\x00000001000001002a21c0ccb34dfcd1e58a0261a2666a768ef69a4622722b8240d8ad57fcdb1017c9f86def6a38292c71f6597adff5352e7067eed16807b59ac6ae5b1b7d2571c373aaeca496ba1066a33ceac43ca1097c8cbb1610cbfc725ac40809018d7812630222adc13631ac34e77a45c7b59ce4d538f8ae967f9486bd1143451fe68a0d18	\\x29076c6ef6681612beb79e6757d281e2cfa6d26ba3f7a18d282a182f33b33c6d1b7237f1f22160c768a7ef5663655f305e43b6e130dfeb64cf1d38e553076f71	\\x000000010000000128ebb719ea101d9176df98635359613e6cb95c80f8fe73f46dbc3e3901654e5516d4615e581f628fb3507b2418edf6ce4f356f419f0f1f047cb25286b6128c43acd0127ec08ee9c31f596fc39dc98872ff134c0f60d3b88b237b71a0ba4c9815d82476497e51f29d4dc48ba18b1c9b00d260bc97b9dd899e86bf4c1ff4277db3	\\x0000000100010000
35	2	22	\\x47e83e222a81147fabc74f333e85a821ffda81f5f9927e19903e99f5dafbe40e768b32f5eebec6d97c12c2e7f15ed9e018ff1f35a17e2e7ed111169abd53eb01	121	\\x000000010000010057312305d4a1a6413e3b6958d3460418b39f738b03c41a2018b32339117c5e23ed16b84674760d7a601390ac4f66bd1ffc32a200143a89d5e0796dc383e086c3ff64002cc79dd08557bd5a0f9d1244087fcb2dabb80aa5b3b196bc57023aa766edd5350b63f6fca329d8ba724b890ff146b0a1763f2e310d683da6eb602650a0	\\x0c8fac97181abe8d21e780893f624d49978ffd2f390c176d7ab3c61a67c1126e87bf50c7f5136afe05860e9817e4c1e66ca926ff91f71b85ef3a958b84913ccb	\\x0000000100000001b953e5867dbf8e8bc79538eaaa4577d33c096968d76bf9f44241f2838b8921aff37e01988f85e9c8386020c276c9ea8a11461b33cd1b83d2682b3c0c7371506d555eef34f7654849f425b1b35ebb142640df060d5debf6b836c2a54b4468705d5745289e5d548033f6f193c85eaf65c13b03fbe4a273bc782fffe603f4031278	\\x0000000100010000
36	2	23	\\x30ab4f830e17be77d3eba23a8d35befd7e521f396e7953dfd20c080137c87badc8838e45ebf98834c8d3a96f09b03c1d2a4cdc32685a2f5d38f6007fd6ecb60a	121	\\x0000000100000100af4440c126c6c926b7cff5f5868e4b0fa72202a7afd2f23f795984c48c1b8f6397828ec3ef9a72f81610efb580b78045a13e3245b601a944350f737465eedd300ffef89a6cd2d2969db38783e2960852314d41c845a6f274f36dbd34287cccfad1dd05c112405b23d29987318ff839e876390ccb4e55840687ee0db819aad09d	\\x24f58a9b66ddea0ee0d5e3472fbfb87856a389745c28960263b8bdfc07968fc6657c9e174a5dc84ef3b9e5f76bc1a4846936c7d99e57b0669f86749b1cd70d82	\\x0000000100000001520f12c8c2ac534d47db8868e3349f31ace9381c41d46e753e336d19c68b4281c7b7515251fbde37a8db944458a9f8e5ebd35520bce25ec03c7d02e821ce8be63c00e5de41b24ef4b85591b2f836b0829966c1de69aaa52fe72cf9ca3f9a95f0534fd8aeb809f6431a7cc8329a7fee955a2adbb8b4d0c958db8f8c96adef4d8c	\\x0000000100010000
37	2	24	\\xd3ccc9f1e3fb505d2d36ff060e87bf6cd08956cfd49ca7b3e178e6d8a7077bf450cd529c2067afb4bc10156ee9793df6d682f38d359db52c2339e196a00c5609	121	\\x000000010000010025ea04bf48e0a210144dd55d7c385416ddc225fa5260d58be22ed59f36ac5aa47a6fdd2876f2f25fb82803ce5df39680b8c3503b62604d9b1db458b5b4922ee45921b96e6bd6f3cb42f9b9889699f3b680282127384501bb0fefaaa71ad4130a69b1ce71498011e6295d70790beabe131973a8de6eebba2261018e803e16a5bb	\\xd8caadece3e1715f2a9ea28e1c1810faf395729108c0283ba755d3723a8b05c3471c55e839518cc8dfba3501205ab9b64efa8962aa7c96186a343ff258cf03a4	\\x0000000100000001a9c85852a9c517da9df91a90bbca6346005906240ce0fe79294d07c47d27e67fee8f08fadc68049dbb00e053db539ecb86c0c88ec3759753f52c7a2dc6c72346bf4870e1936adb1ccaf85f9c4d537084eede44ce96da6d2080c58b5f812a5235d2ef0478665a452f3b74065599b35e98dea93633e62c82961c347e372ff0d1f0	\\x0000000100010000
38	2	25	\\x35bdbea5bb10871d799cb4632a1bbeb60e66aebc96d46f70d5fa6dbef19ba4c8492eecad676fd3fdfba97c27adb2cabf88b879d9db8efa75dcd3ca1e0f11e90d	121	\\x00000001000001006e4d51b3898a4ff7e5835b9cd50020e61aa1ed5897e5eb469eb963668dfa3536460e077570e4aac716987d20f28a2a3b96f152c8fb7a0c9a233206665bdccb4fac63d67bbdcadb911d9a04842cc2d2e2dd32c89b951ef64f97458154186d65627234bf08e5c42f2e730700f4bc9bf0e26429505a8ade9299344bfdaa086620f1	\\x0e208b0cc73f5ad95ff1ab6347e164759b5787cbe523e2c3855f0f3052677fc61e265315c51d5df1e52aee0243d6718287a637df012d1458abd02be1dd1683d2	\\x00000001000000012fd7ee34eaebb4b6924074883b42b6844b9ccc7f4a0ecf643c1dfafff3e976c50622ffe619e19ebe571f5de6489338ba34a14c164d96ce9cbc4636114a8998ee05f9458f889f5e480a77cab70cbaa88eff57f928ea2b5677172d486cbd8839efe5df5e8fce2483b1a5e8a30ba68f869a2d21d90982a81284948aeed1e1b42456	\\x0000000100010000
39	2	26	\\xae07cbbcf56dd9234d60c462c80d2d97166edf858c45ff537a3f5224896c78398691e1f4da3cd23d6a0e002ffe029d8b9486f43113daa4bf50ec9537db471c05	121	\\x00000001000001007ba131f613eb3f1ccc6650472fdb849600fddb6c1ca628e8b1d365ce8d23f2b725c6ee2aa45919304f99b1d5dbf21d6ac783ae263ba0e95e63185ede0b81cce5365eca842160c915a5147c14d06370615f993f90a487280563fe14edba7490b0c9c9b9775d3ee686c344a96ed06c78e7fcde6a3e87a73ef7a843c3af59604368	\\x99d43428e94beb322a6df9c2158d4ac83b55df9a754fa2c2657dfc4c7c553209fb33aa43497aabd8f897522d448f98bd9e6ce763c67bacddc0ade7e74f1890be	\\x00000001000000010a63899342779893eed38d9209172a4fd54a6b2c541a32e8d1ae76a3c102902b8f329c433e2aea34116f2839f0b614961b9494e3d413080ee6c6950ef96a0101fbe3b2444fbc0ebbd9f3ed0ec48aa7d25e6c0a5096df11f683020285c769ac282b168d03f8252e9e5ae302e533cecb4beba5ebfacd853350a2ba886165fcfee7	\\x0000000100010000
40	2	27	\\x38bcd0589c8130adb0d08f8c16329b5f01b6b49a4ab00512db5403d800a29f601035e5bd295713a0583e00d20fc047035d6b4cb6218778978080015e73d41207	121	\\x0000000100000100759189432b8b32fed282ff0d7ae5c891a6736b3fad220c204f59823336ab3474f7c5b6f724dcb9db82f721a575a1a2f5c1a123b98f431783dfd35f63b79d34a4b2ff6effcd79eda7e17838302004696752c39af3265644b2046a9786ebf316076ba0dadef5e0bb78727302a5d17c8dd6183ee446d15adcac159167d57dfd9c96	\\xf44023c9edb90af38c39e1144c151e0d9271514981988aee26765ceefefadd4ba3b116aab015b54aee7670ec69c8504e7caf0ef51f3c9fe94260145f3b063a40	\\x000000010000000126800f99f4959d5b514f8205856274a4d2b3928e83dbf44164a9b2661fe290378a2cc360127309ae9d54d476301a9603122e9d3e3363dae69a5b9fc3fda95788515d7e2409ccb91c45afa22aec9b5db3e7566d023d6f91be0683c0e5236a7d4a92574bf9bc4161da04e3acea3154dd56a7917c25bda7bbec1dc90f326111d157	\\x0000000100010000
41	2	28	\\x88683f4953a2a9db4b95677bc8dcdfda03a3efdbace39e6ca3fdab1375856f4e0ffe81053a71135bc6fc0f8193dd952d978bb72636a18fc860da541e28483307	121	\\x00000001000001001d46919e2d1715b83ea0d583e7ea0017dfe9617f9591cb127b56e056392c629b5a8f32fe56bbf59a824b24890c974061bf07d47f4f1037b900e3fd3de72621f93684f92b090d8c306f4a1b37729564af43697b2c97681a333ae2bc395a8e80f2b8188a288813b91323e3c47f5b304dbae6fa92204afec64f7e28b7cbd7087e40	\\xabdaff44cd8d58ce77679a4519cc20b971ca1b6e7375eca971da2ea06d00e60b6da61f74916cc86cba765abd33b81f149448e70638e4134f3877cb5cd69a0899	\\x0000000100000001ab955ac97125216370f30856c24fe99656987e78e03c20fed28d8f88ffa3be77a85605e8aeb9e56b136bcf96e2bcf477c9e87736d3f62e87b58f5ae2c700359b94f55711c93e2d7a04ade45fdd73e7750af1505ca5d87e68677c315aedbe406f72168bc5b131853f15979daf6a3134bdc69de3205e1d1a9726b18a0334c2fd7c	\\x0000000100010000
42	2	29	\\x1d23bef7dbbf2f5f1118eaabcb22f82b8272325d543e7974acb2018fe10c00bb4694d0b2b4f2439095f8fd71d126944207d80973e559512f767a6d4a2bccd205	121	\\x000000010000010058c7487194b264beb41febc681de10f98648521c9403cb4ff447083a4a7a47503a955be8daca09488d2224e1c21902d35a69b79846479d352776bf2f26ac54b41bda6611ba633de69725315c86a25f42ba7e1e64da75bcfba43bec157e96d50301138e69680cd2d5dbb7319ecd6ddc80b35f7ddd5e2cf973b359e051e94efaec	\\x064e2fed383f5d8b0d614a7a11a5d15aca01d376ee5b4fc526fc122d1a5869631309d1fe25b26954f03a5b9294728fa5cda8980b6f40f5dcd37bc78913ad711f	\\x00000001000000012331e5a058ebcb7b5a1fe913895679eff96318c1df3e32ef9c7729d3d5c7b3e4ab8f646d8255fa342ed0e7ae1d6b3e5e1a23b03c57421ea0be8426e9701863c1d36608951f088356168f4eb1ccb8ecd85da2b074e26675f845d63bcdef4032d2e4ef6980774487b8f531bb547a3ee8fa165ef722b6317dbcd16e5d7426141346	\\x0000000100010000
43	2	30	\\x992734a69140ec30723df413c18a742436d552434c0d352ff170494d41fd23547db047757f91d13b05dcf1fa1bb7f2a225d6d7da1d31a424f6940bdf9fdec904	121	\\x000000010000010015952a1a2d068caf485e39b3fd5a7d027c16102eb6e09b0567dad707ebf61d4d289018f797a4ff2f460d838971825b5d4f7fce4b847589af685d9c0f3ffe3121981c968bded8de390e64f4301a92840a8799b0d716aff03bf47b076b57dfa471059492587eb228ca83ed3c766c0d7047fa7f2bfb7561d17acf45237acff11035	\\xa0c175eb8afed26d34cddbce78bb8fbe872960b56896ac2e2860aa9625c5c0c5918951f3e97617fbc55f12fc2758004f7d0406f68b36ec681c36fb2011225f21	\\x00000001000000012a825cad625f6ac3cb90591577b8cdf17bb73742941a8ba9e4ea2dda2e855226fb32d85313d5a4227dd205f0ba0646897b7f798cf1e51e94c768fe7b7d1830b03dfafe376be2a2a01cfe881340a49e1c13303097aebca5d1f9db14949f74de982948d5b65e26a2fcc702a20b9c83aa59df4d08a4f285dd999af55bf4e4ff4642	\\x0000000100010000
44	2	31	\\xb381fa9ecd0945afbe41016d4a9cf1d768df33e5a77423bd944498fd1395a4e64ebd0a1c5410fe90d842911964f4cc5d135dd0ffe6b07179456f445e0f9ad703	121	\\x00000001000001008f88c5238bbd75cb759be23d46472287bae13ef206b75f2fd4f87acc54f6e216a0b05ef286021b6b5154738534e6fb054a8b4397b3df3edf69b6a47241d7ff060b5f084cb26b67fa1f3d8e624ce64539f76a31707da4d158d031b3ff6f28fe8d8843d66c9d6bc596974232c139e7672b3c0420a5a7feaef88ff603a47c09bd41	\\x1bce3b2930c5a68dcb16554aabb03b9b5d8e0837b3ba678ac6e85a4daef1b19418f650b4bffbb89828ddc2d899adab89ab6510a7cc6a5dd09350cfdbc068ac4a	\\x00000001000000014394d456cdc2a78815f2a70b8790fdec8408d4876aed6e4630a73f6cae5fb709e61dfdbbdc50384cea1e874b7174b6f82fdc242bbb989a07fddbd39b30d988251dd3380159f319875a6f42a5e34bd6502f09f6433342288c6e89bf6065535508b5606a765524e66561a3e4221b2370bfa5cd45e1ea37afb3c20d22d6e8d8a155	\\x0000000100010000
45	2	32	\\x23d567d8a22ceb1a146481c1f206f2bb04fe27cbab3829042751cd964287c45993a1175771705e191019a7bd852e7cf22ef82f2be65785617c5162c5e8d48805	121	\\x000000010000010032d31aae6549bfa37eca184f81bcde8466ecb1c770fcc1c9ddc4c5f6cbbb963990c5875ee893741fad15d63504848422ce0f00515258a45c76f910b47bd4b5c4eef8aadf61f4c34143578864de6052fe25f81505a51b97aad88123fc9bf828f3404adae7092df8e7f73c6c40f933edc802205a9a2a3501410d51c89d40bb9f32	\\xd4c85f21dfbf9270a9d880489e7e5cd35303d58f3c82a700a76b24cb9082d9bd57d51315c79171009a821568346334b2350a355ad1a85f6cf5f0c42a7c516b4f	\\x00000001000000010f794aa244189bfeb89edec93b7bb34c1698121b0afdeaa842eb59eae582e6b4a7d11ac972818c8c978fd43076e956b25ef4e9b3ec5261f81c13e81444320712c2675b2e0f64aa5918de59fa724b0e4b3acd55afc959e6b16a56a93d0f9ea65ac0bc10431b1591f5b2b25fc012a20119d9ea9053f2d36d1037e30993e7dd20c9	\\x0000000100010000
46	2	33	\\xe9943e27fc0083de5aa273f146c0be33f3ee8e5aaaad1d880b793dc81752a55e458f09e3a30322858a1f5ac43bb851752c9c0c36a0972e086123b20e2f6ea607	121	\\x00000001000001002f5708692ac2918e19e98409cf0927d93b68b8c166c0a1717d17085d650630381569deeb090b968fb704b898b1e7f37a5253cb68aabc65f805be557383675f2f5ff3be154a0f6225b27690b7f7202ca3723bddca19a7600d1c965c0107f6bd76bf75edfe5b73ffd3df8767ee1cb216746b68c02cdf8c446ee10dcabde895da3a	\\x33f639de269da2732b7c4a27467c3c6487b401cd2cec3c52132341874fb21f5560996d978ae9d77c7a6d5803ee68d61c83c6b39f210fb2b4d92ec9198cfd17de	\\x0000000100000001991231136f7ea2e0b66246201c70c75286dc62a5be11ba42257da0c11c28230c5441f2e9e709dce31da4570599f8d3d2f6bab0cabdc060f985b5ff9a24a61890a592470782495f86a5c97167253a8d6222e4e8b8a4995ef386c0f7b5d6632127de8b4e318a7a3c3360e7233dde99053eb952aa320a554bb82a23afe6be78706d	\\x0000000100010000
47	2	34	\\xf1b9636d1a2af383f149da30e92446f6e006f74466c4c5dfa3657a15e966e2770a39808d2c5be211208c26f1b09b0fbad0c738b4d24ab0cdfd1111ab6e233106	121	\\x0000000100000100342cf7004c04fbf94045f081fd21a9503ff7168162b6603c745752d24fd5d65057d2d561fbdcfab7fc8370fa59ad857deea567097b85ea6cd1cb0d5d6bbdf866a16ca3a8da1e8c200cfa5ac43891cd615db787c35c8f825c3877dfd8b5044f8203d5366fe560c196c45d53dc400a6fba2182449b00c958f595eb1b1ef8ccdccf	\\x92e7d4245027839c36fd6c6ac1883a61a53be3dcd0771b3a9066a5b42cec205c3adade130964c1ba6a1a068ec7e33922aa8649234a47ed40371617181c2f294e	\\x0000000100000001983a86bc00379c65b52275c2ab2b46ad747ae9d37b277b4f45c769ac43ed42750e6c4bad15432157cc9a5c6d798f22858aac3ac845c54c1be3fcc6be4f436306464e6442d631182a7c02c3a637ad3060f28862d63ea1707a9ca85f62fff7dfb8f3ec1bb1a0a7483c721224067fe19ada0614a7029497ad28094f88748c02648d	\\x0000000100010000
48	2	35	\\xd71225e21168036d1e7185d3da9384ec01d68eefa2ee52f627bda914a507f3e34a61768c573714664e86fb47ae3de5e51b912562508cef6c60fe2d16fcc8d40c	121	\\x00000001000001002471fb2488c5c67643a46155adb7e8f72bb74bf6b8cd261863e710883b40267e8ee55d0d3f159ff62345d17617c91859f9d45aaf7646bf82dda9f396d34a0f682e6784060564191435ed3f0b78d4f5c4a57e0cf8005c163c0f4b53ea6d22211427f0b7ec5a2e55021e686497232be5f8872aabd9e80c2339b4c1e7f3afb7bb7b	\\xa1c4807613cddde9b71b1d009e13ff8f0874f3bd62c9d0c5ba3c739ba4e1cead8a8914f53e7c464ba70406c015bfe6b1f781769cfc7a22335a54e131508616a0	\\x00000001000000013b600c65469537e268fdfb24ada04c091da5d620921a70ab3a36f1a54d5c674940384980ceeb362d4cf5238958d6121b4136746887bc7388f1e2642f40076dcfe0f21f19d0af86ff788dba0469bf506392fbd409b4ccccb46b6cce8e16eeed90fe12ba3daaff263f5c771445684e918d44fcc01d5adf7721398ce148e0e358bf	\\x0000000100010000
49	2	36	\\x8539dba9b4997db39eb85302a8e7bb6c2ff2c42430388afe3fc38cd59efe260d831da56861470d0fb0d2eaf04d3616b8f284fc178d30c33f3956d2291edea208	121	\\x000000010000010013dfe9732e532ac2f331306a4f8b71b8fb6ffefa5a9006797dbe21d22376d37e96dde11b02b7fe34f96ecad6e4e1bbfeeb630289af388f39d450ff98d3ee9a3ec3a232ea7a027b43d9a8a13d9f1e5837ba5fe0368f96c90cd46b1ab371a23b029af4b228455af90f9dc17c7f47fa0485079b36a4cc9934f1a47861713020618d	\\xc50f27c685b45983e10bc8a9c44dd30311d576f2d28a9e01c047c2dd94194bc1df78995f713d8781af1063fdd645070dd44e1d563a31a9a75af21e85fc403f63	\\x0000000100000001bffbfb08dbde7d00179f63579f7349c47709cefa92952316f542d3af47c147df1994a01533d1f169c8e6bc6cc75fc39626ee62a8b71218a5ec1771e5add0394420e1cccc5a6d1d77b63513642d91f585e44bdda231c860be45e6fa74cab2fe91208a31d575a9deae2e5e59d74f53e44293d4dbe3b1f77bd514486f0901066216	\\x0000000100010000
50	2	37	\\x8f5dd8bd1543e49455e59f150501bf93966d2e2a2a86e76401664e770c3fa73d9694f003388f3098be2c0a4ec00edb78a7a115e72e8eb30bf476e3acd016ed09	121	\\x00000001000001004121c01d7b05859c726d1cb8449cd8fe2396836472040b30edf1bca01a928f591ddf5e99469adaab1f2f8a8418b882bef3032a8290c5d614d63b5caa30cb090a96273cd5e793efe6d5b61b277a9945ff02f6f358c8821acd6622571789b62fea20cff0f2e71d18cfc7486e702d02c4d15987c445580112e5e9e3569595f97aab	\\xa949e9ee9c9a8169b7ae5e18d25c1ea45b030b58791b14faebd8f9a51e3bd69ceef56670b6176ae9090870626c48acacce47aa9f963632475d0ff2f96ae9446b	\\x0000000100000001609820edebce6fd5ef89a03565f21db5004ec5ea8df455f62cac8f63b5998ff61400ea386cce8b491e9c55a90c8d8f1771bf8540afc89d77eff67ef0d0c8bcc88180a3505bf36e795050b2533fc7a97ecdd8605446d3316d5b2b732cb1f46ed16bb551edeb2a851a0ccdec5dcc9e075f93dc7de84c4f596e35c60b0ae44f3035	\\x0000000100010000
\.


--
-- Data for Name: refresh_transfer_keys_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.refresh_transfer_keys_default (rtc_serial, melt_serial_id, transfer_pub, transfer_privs) FROM stdin;
1	1	\\x22f6d70d2903796bef00c71d333396827b504651aa1b9f3696b6823c3d540657	\\xffda15568e4169e7c8401b7fdb4397ecc81fcd1c9063178eb78acbfee5a872d2dcc4aa1054e9b678a06c3026a3d91e572eb93d14c93d77d35dafeb404daf6829
2	2	\\x55ca700ec86e005bf856d74d81cc0745e2bc4a0959ce94c48da28c72f93ef37c	\\x7d230e916e52eb93f4e928a0bffdee777f4a8a9230bdb9b5f3e60bd37dd905970ca4c0c7c7f5e53b705d3d8d7681e436e03e03313d68aebfaa0aedcc0269858c
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
1	\\xba0adf5a41fce94b9806335673ce9283b15ae5db368eedbc7aed243225f0d3e1	0	0	0	0	f	f	120	1662671200000000	1881004002000000
\.


--
-- Data for Name: reserves_in_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.reserves_in_default (reserve_in_serial_id, reserve_pub, wire_reference, credit_val, credit_frac, wire_source_h_payto, exchange_account_section, execution_date) FROM stdin;
1	\\xba0adf5a41fce94b9806335673ce9283b15ae5db368eedbc7aed243225f0d3e1	1	8	0	\\x75b009a95c776f463a8a9f5686a05a39a61e4d65458d1dca21f5789940107491	exchange-account-1	1660251988000000
\.


--
-- Data for Name: reserves_out_by_reserve_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.reserves_out_by_reserve_default (reserve_uuid, h_blind_ev) FROM stdin;
1	\\x9ab634bcf02e48dcf8086dd141248373d705299bfcf3132ee339055819eb80847c6755bd2f2a812b9ce0e5846530004e11854186fe5f6b1f35b223e7c4a409db
1	\\x2fba6eebcc0647c21e291cda7cb1d827293b205917f99957a847e8e3b2a048c26fde27c5ffb719a0235e74dc77d4294f323cede4b27887873780e93ef16c9d67
1	\\xb20ae87ef9f379b23a48234a83d6edcb308cc4bf7ffd2635e96d629610b6037844001b01461c7bb6dc9ed7313afc5a18ce5b6adfc0aeded8b01af063ed418824
1	\\x4086cf401b712bc25c889019d64537944a9ecb117dac70525e278065e4eebd14915a1a6e7a9895395be5c181641a71073e13491aaf38b36632553ee7a95cd8dc
1	\\xb2ecef9aed21a5da2a2d9fa944c0bbdfe9899a1980a5418f6873d879405a81ccbaeee6df1e5a1fbc3f7707abcc5bdde956138c8137204b05a276d4da36cb4d5d
1	\\xde15d8f0ae8b1ed926487a869fb4e4eec4ad304eec557294fbe1ab04ec2fce16dd5a9e29d642c22062e624545c711fc352810c6bfbca9dd072e271e4a27a4cad
1	\\xa4cd62721fbd36ffb1339288631745e69c5bc2b972fe516d1135844a6a7bdcc62e48d97782ddbbb6af45ef1081f5369d43031647cb7c1a7f26a717c6790c4012
1	\\x3e0d8488bce061680d7b4bd75ff59329f1cc7a3c469ebaef0496716fdc3a188581df9aae9d7a131e8a29a7fd441c4781b66d45c81c846ae600101f2fc4ce79a2
1	\\xebba2eeb69afeab4f92b58e3a7e5883ce41bbc4547d58202a0da8ee564299607911f5929f57cddbb8cafb7fab96c46845308ad52471fda0d92f495063517544a
1	\\xf30e8f02041e060f28c7cd9a08cb895388d9e434198140200cd62f87d4890d66ed7fee7fe6eae0e9b84805aaf3a4cbc80a45d9af05674e1d0f933869a5d63fab
1	\\xfcc930ef95e88c19a345ebcd42a8822e7c5bf1508421b1943f9d34c23ea5fbd28334fb69be1ae2c43bdd86251c101fc8adcce060b736c4dc131054f0b7924361
1	\\xeb4d76137630598572bff82cb326e4a0d21bd55473a8c237848bd4578a7fd419a5561246cae11a7c9cb289bcb015c5925aae1b5a9d04b93e463c4fbdde484006
1	\\xae25621a89c1264de21e2366fbcea4e7b4a52d220d177fbf6afa4a5668db4c88d333075082f49ad6a7372dd2b1c034d4dcc5697a60103a0182e0d2440de41cae
1	\\xb8b6579a1c6bb49784903822deaa23070f3bedcfe1276b44a0e8b9440d6757af853d41be57e5b5f4ce5107bcf87f53ab7735545360e8d2fed32d90aff1ae4ea1
1	\\xd26b1bbb6c7b0711833cb9d3811cc181ca46c41c915a145fa781b70971e8c12bafec49c0f0214aa335573a44016337fef16c00c94c38ad6de4464a90afdb02c2
1	\\xffee867c0bc096ed56bffded86858e4eec4e9b59a93f01f04768ed137e3a77113e7f28131eae308c4b9458a3dc9d502c1ec62c4cc7777a92688113742faeeaf0
1	\\x9fd3749566bfcc295044ee015b2e765ad73a8db672e77fca78623861d326a26940e2caf190376cbff5a294d5666bdf4827824b2fa3f89f9f4f75e44dbcbd5b5e
1	\\x2b681d589277493cbf7e393993083df45aba66b0d24f2f7d30e20cb8e03ada0ab302f212233e39c1f687539d64f9fb97d6d96984aa3ff1129ee1d5e16847f352
1	\\xf55bfed8d97986b91b9402be92d2e071a744ecd29e0ce67d72b3fd84f7ea3f5e3654ba63bbbe415d8e20bd3894b4beb43aece35da9dff4b1940085d44d4517e1
1	\\x0f762b8f363d58353b86b136f25591548af6e04f65c0d740e9d09c70139b9df628e60c705e3ab385230721f71782af89edd4a5c61be19f5c848f6d78c416e442
1	\\x14fc7a95cf87bf59a19b7dd528bfa3878174168c0e7217e51b6e00186c72c4d01a918d947fd3e812099c76d0827521b8e4cecc059635e20f3190b3bb4b42cee8
1	\\x81a8fd47c3bf204e86f36637f6b5bfd83fee39a3b8ebe8b90843622176180addb5af00edf6777deae33250423c54b4e89c366f726ad8fa0d413227d223abbeb9
1	\\xa664465b942b43d139f78067cd948fee40d55a1cadd695902a420703f4025e15d0e0a9a1eea777a02f20ac64cb423fdb002bf4e0991d15ccb64486c351533139
1	\\x2725f5402becb99f9b88c5b70ccbb6cda96a68a505c75e0eee283a4773477d22c07c17baad42363f0e908bbd333dbd46a82773f435fb42c1d27c0d65aa632d1a
1	\\x0c8ee183c59064303aa6e37faf4891ecfc4bb903bbeae0564dab530432fc8eb0e6396c68fba19ee4fc65bec76ecf3d85330c203696ece3636d7abf3ac503ef71
1	\\x07c866917cca939069d3ddbda32eb54d3d681fb8d43121fcb9072d340373094fb26438336c4305b639d418547afcebff7c7a067c2fe53fb37f0b9d761b317c8b
1	\\x7fe07d483d5c7b877bdffea29da031acc88127bc6ffe3a28ea68733e20a0f46d16e9ca840c1a3de34d60934faa733997bb13cf97c0d88769af946c32750c2336
1	\\xef009dcf258587b2b0bd60ae5cb02df02051db387bd4e272e86b70b8785d62ec97aa6ccd9b412bd71a1bc8071e09267c216c98ad6c4e988ff6c1aa7cbb03de55
\.


--
-- Data for Name: reserves_out_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.reserves_out_default (reserve_out_serial_id, h_blind_ev, denominations_serial, denom_sig, reserve_uuid, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\x9ab634bcf02e48dcf8086dd141248373d705299bfcf3132ee339055819eb80847c6755bd2f2a812b9ce0e5846530004e11854186fe5f6b1f35b223e7c4a409db	367	\\x00000001000000015071be8f4b08121a7946137361a5a53d4d2be0a73cd4ab13911dab2172575802503bb41b601195c323008dc83cc221ea1ed97f020cccec089132bc98fe7921ba907eb63d6da6e1fc3798fd73b4536ff4d507ff9a75214ed479232c8b311df182b27a1c224bf9fda0d5b8d449d8e8aeebe59b0c182b2a7ef67eb348b3fcb22785	1	\\x799593f0ad5ea7d73dafcbd5da851417f485585a5b0651787a4a56b3d0c7ad0c5655a4895050836830c9b3a3c10b03948b72cac190ef86d9a3828f183108de0c	1660251990000000	5	1000000
2	\\x2fba6eebcc0647c21e291cda7cb1d827293b205917f99957a847e8e3b2a048c26fde27c5ffb719a0235e74dc77d4294f323cede4b27887873780e93ef16c9d67	7	\\x000000010000000155e0279ca3f475030566cf567dbcf912a71975e928876c14f66e6c15d62bb3a43d1cedfbe0a090435685c0173c84e9090c5cd4d7db7541f16f446b4169f91c836247baa678106d274a23305414c33e293c887afcc1de4876845faa2db73f8f7817833b653ada581e607c4506de2e90fe161e8cc071aef08178ddc8e2607f6ff5	1	\\x8db81fa6fdd5162065387733b95d6a678cb0e4ba4d73d627c019e1448d1542c95708a07180945a030a796a74775e8834883dd2c736bcb85f01fd135106e0210c	1660251990000000	2	3000000
3	\\xb20ae87ef9f379b23a48234a83d6edcb308cc4bf7ffd2635e96d629610b6037844001b01461c7bb6dc9ed7313afc5a18ce5b6adfc0aeded8b01af063ed418824	403	\\x000000010000000180dd620e85c8ed047c587c3085372d4564f70f168d99442d229282b357999d39998acc4383e96ffc1a34250ac4491652bcd6cf0ae677d74832e5596cb702cb4ce6687179680602563dcaa202e1acb16b263e06eaeb4acc1f208634d5d61d0f6a84c1189fda5c31dd852a3bd51ab81ff497347f323b6d3e3e5d2f6dc98c1fb907	1	\\x6c9626db2da447bc842eaa5d4422474a34df01e64ef0a3b56a2a93c732096e1e2cf80091d368aa7594d24a8e2f4946c98d25f1adaa790515802d972827a91505	1660251990000000	0	11000000
4	\\x4086cf401b712bc25c889019d64537944a9ecb117dac70525e278065e4eebd14915a1a6e7a9895395be5c181641a71073e13491aaf38b36632553ee7a95cd8dc	403	\\x00000001000000018570493692410f2ffd985f5ebd123f8652ebae6ff6433915bcb7566aa50b66bfa130ea40425f2ade143f1c866089356f7e132bf5f0224f56ba4e2159fdf7a4442b538be138817a7ce24ae231adb9c1ad0e27578258ffb7ea6587df283d804c8a4b3e7ca15f860f426a5aed89095feffa26ca4f98afddc68447d0b15fe519bb83	1	\\xf4280385541d4f129b55ba8702398aa46f33d6c00e4d335f9e281b9060a632155547a006af3bd69353bda5adfb66d78ed577a7def2d385dd725e2e0fef9caf05	1660251990000000	0	11000000
5	\\xb2ecef9aed21a5da2a2d9fa944c0bbdfe9899a1980a5418f6873d879405a81ccbaeee6df1e5a1fbc3f7707abcc5bdde956138c8137204b05a276d4da36cb4d5d	403	\\x0000000100000001a9e96c64607df5cf9b8e7e3ff0de89933acbbc60522dd6bb9d051c1d28ab79e833725273422fa95d616db38241a8c95fb449fe7e3249aea3303c242e66ddbcb0d59dd0d5f4c7d9b223fd3edc2ede3f6fa1c20b5f8a1dd2022feddb85b080bb99da2c61bc9b78e78816f54c6c1e2354a7ff8ae44261edad36a82556e8832a65be	1	\\xe21727f4fe2d1ebf51d147f7c31ad9be3d155892f70fc2c7c57001c0b3be04fe0e3cd28e4d9856f598f16bad2978aac6987d8353bfd53dfe356df81d6e187d09	1660251990000000	0	11000000
6	\\xde15d8f0ae8b1ed926487a869fb4e4eec4ad304eec557294fbe1ab04ec2fce16dd5a9e29d642c22062e624545c711fc352810c6bfbca9dd072e271e4a27a4cad	403	\\x0000000100000001b1eb2703cac4117b906a165fa64bd1b1298ce207a9d1e9a16fa874b10f4b7327753861c5c33c91cc4c847b10cc85d06069197fcc7dfc07a7d35f97ddb874206787d3c54e16d156f7236a95748b07012df25e13f0d5721dd2049c7f58889701f722b3985eb7ed973ad7dc596fa49e83f98e3a5b588231c5fcb9cb814288bae3a7	1	\\x5194919fd3a254c089bb96e3b9f111df6b1396ede863f7b3ad029a366063a91e337ad3819948b22f5284c47d1a4d86f81a14680db14ddcdc29155b5f6e8d4908	1660251990000000	0	11000000
7	\\xa4cd62721fbd36ffb1339288631745e69c5bc2b972fe516d1135844a6a7bdcc62e48d97782ddbbb6af45ef1081f5369d43031647cb7c1a7f26a717c6790c4012	403	\\x0000000100000001616410883e42fc53f14ec6345ad5599c079c2cba7b6bbfe6cd14df7b7f6af6285382b0759579006f0c405e3fc5b63a4722d27c2e83c6a06a78a41b12c68a060967464b98a21606e8b96bf9a359009e3a5f5936f1a5a801ef3c85c04d8856df888bb93ddcaf80913381fd5f440a0f6af06b126f9dcd8facb72d2af3b1db67d24d	1	\\x676fec64ecea73446cc9966e4b5761c1fe11c5a0e7c3d402a568ebf1341092ceeee8953af27b57891f323324a4219d53a12b613dc5ff41c7ba2a23afb43c0a05	1660251990000000	0	11000000
8	\\x3e0d8488bce061680d7b4bd75ff59329f1cc7a3c469ebaef0496716fdc3a188581df9aae9d7a131e8a29a7fd441c4781b66d45c81c846ae600101f2fc4ce79a2	403	\\x00000001000000013f7b57eb168986caef40607d1d309ca5eb3136813a0829e0fc6a7820b722a530f8af796b750e0c17e72f1f3b7409fd7e89a8b17780af5434511c7afa39a77ae3a16c07fca4b4868099262d6cb730828df1c861b6081b955159402d3476fc2dddb582673c0e06922d56755280e34a58d15a8db0dfbe02d52c365250c225524ecd	1	\\x7e155e9bc5d06bfe70ff805ce422a9845c371bc6ff7309c19fef1931aea444191534641d2e37279dda75dcb430ce17b7ccf74457dab80b737de3aaecfde3a805	1660251990000000	0	11000000
9	\\xebba2eeb69afeab4f92b58e3a7e5883ce41bbc4547d58202a0da8ee564299607911f5929f57cddbb8cafb7fab96c46845308ad52471fda0d92f495063517544a	403	\\x0000000100000001101a2dddf6a6210383514e2ab353ee0354e00919f072550f235ecf4772b8152e7b39b9433cd9785486fa190bbdb53ee6d4dd2884cd1f2796490fb9ae4d81de3c854a7dbd877fcaafc443268ee7d44f3b0af9554009253d9b64b471cdf990a938942eb486f0e7c0b6f7e947d2073dd9601c2d0b04a75c06826d5ec02b4b8ade4b	1	\\x0176b447e9e386e70a4f81304b88ebe10f3e04005c0abe42c5e73adfc79d695f498a60da74c5a084e7b8fd12e44c07372466e7fda738ebb6b236c7d25961830b	1660251990000000	0	11000000
10	\\xf30e8f02041e060f28c7cd9a08cb895388d9e434198140200cd62f87d4890d66ed7fee7fe6eae0e9b84805aaf3a4cbc80a45d9af05674e1d0f933869a5d63fab	403	\\x0000000100000001cf4fe182f58ada78d68c5066c1d6b0024fa76d431a518c6c44c81df43ad898a73e3bd62dc48f62f37276e93801ca9c34bf83a6e7467e48ae083a7273615d0707862f4c597886bd0f9e735ff3ace3d6a94bc19c68d6499dab7f22817643c830cff827dbd935511ab98e404247a431676ce45583215c12cbd1d1e9ba1ea1e50e5c	1	\\x481e564d15ba492b7190ba4f344eb21710502956af619b455692efbdf9d9419828ce154ae492df315ad2e8e5607f2e4f6c4b07ea361cc1ac0aa2598a2cd7ad0e	1660251990000000	0	11000000
11	\\xfcc930ef95e88c19a345ebcd42a8822e7c5bf1508421b1943f9d34c23ea5fbd28334fb69be1ae2c43bdd86251c101fc8adcce060b736c4dc131054f0b7924361	336	\\x0000000100000001af45c9360d76a608eca18ae8c06ec4d7ecb25130a9fbad2c57d85cac0e8b537f828d528d5fe65e915c7b269e966baf7b409f6b8f247ff986be8f78d77727ac32d1f5f94c9aa666913998c01a562e48036ca68aeeb20e15616e2dbce0544ba68855146416cd913e6d5bb3777cec20da226563170cd9bed17d0c1253c718ebac9a	1	\\x506c4b9173a850f8e6ba14ad28ed50ae96f52c68f0b3434fe57d4d9305816e7cd071c4ac908bbfa1c9c070e0efb1580df7a069643b314d8c5f6eb43c48a1b803	1660251990000000	0	2000000
12	\\xeb4d76137630598572bff82cb326e4a0d21bd55473a8c237848bd4578a7fd419a5561246cae11a7c9cb289bcb015c5925aae1b5a9d04b93e463c4fbdde484006	336	\\x00000001000000019c1b9b5a5954818a0d940e029c18069ab30122a5b4ac358a81e1d150d368cb48c8e8e91b12a89a5948ae8bc123b950cb364899950418c147bd5cb3831370018a2dda6ef65f2882d9902c468179e55dbf30c375acaed30bf0c36bf7db916196d5570e352fe2709999f9b9af923c3a8c0e56035fbc83c4f622dc2a27a1c674eab6	1	\\xe84ee6c326a459e2bba35640578620bdf4c734fb3a0b88011d6d1da1f8f69844a7f0fe28fbca6955377b7c60c58209906995d23aa4e636c7e5107d2c2a9a7c07	1660251990000000	0	2000000
13	\\xae25621a89c1264de21e2366fbcea4e7b4a52d220d177fbf6afa4a5668db4c88d333075082f49ad6a7372dd2b1c034d4dcc5697a60103a0182e0d2440de41cae	336	\\x000000010000000145237e2eb488a1bbca0dc2e33a4409b660404f3ced242f1f91d9508f8b409724e1e5de670aa860fe1adb6e649b6f62b85a46f08bdc3509b210c05269ad2ef935f84b382c9ecb376facc30c961ca5efb6b0c0412156ada7416c2810548f8fcc76987e57211655a793ca7853f0d22845940e908aa383192981d0b1d6ba150abf0b	1	\\x434ad916588c31888c7b3a7cc07be3fef5baf160c1bbb495288114a3307ee7f727a85ad0cd49629095d37f76b44d5fe6044bf0e11fba90c465533348741dd80b	1660251990000000	0	2000000
14	\\xb8b6579a1c6bb49784903822deaa23070f3bedcfe1276b44a0e8b9440d6757af853d41be57e5b5f4ce5107bcf87f53ab7735545360e8d2fed32d90aff1ae4ea1	336	\\x00000001000000010ef85e2f04fef7891f5189a24491a9001c11b7ac1b8b2486e6a8c7c59c16ffbe019b787a3a6f0eb06a55773f982e2f12cff168f8eb75561a831061e21b209b823670ca685769b3057dcf302645b0234872918fc1b4a2c154641df9db3bcb81b1e96d5c26d76d18bd65e664b1f20899357b0cf7e2a6d3d70a9358c30019c80066	1	\\x22fff5f9c935b65c06e65f8deb114c744afc1723bff9a92ada78111aae5288d58e892eaa7d9814825c51252df93b197e5eeafe9d7f779cea6062da406733e405	1660251990000000	0	2000000
15	\\xd26b1bbb6c7b0711833cb9d3811cc181ca46c41c915a145fa781b70971e8c12bafec49c0f0214aa335573a44016337fef16c00c94c38ad6de4464a90afdb02c2	346	\\x000000010000000108b2a4ea9c6b7dc8ad590cc74821105ca13d13c256aa1b3751836e01c072cac80e906e83db474b8255857077e7bf77384e4d8de6c98b955c20a88d39d2a9f16938ba06eab0b14b7b51a08be433d0875ecf4a551e355b1bc4be98aed676266bfefca87cd02fba63206b3ee70e85977729e29a19692fd857e3fe74392e79a8915c	1	\\xe8eb2d13c4ca8acb9233f361c3860ccdb6dfaf18fcc25b5fcfc4b9c941d1054f88df471259a72ccdcd293e4346e431557ac98b59a4961d64d04652d2019f9305	1660252001000000	1	2000000
16	\\xffee867c0bc096ed56bffded86858e4eec4e9b59a93f01f04768ed137e3a77113e7f28131eae308c4b9458a3dc9d502c1ec62c4cc7777a92688113742faeeaf0	403	\\x00000001000000017ad242cdc3518a6813baf363e884bea1bcae141200eeda10978d588f27fc14294e2ab04d18dfaf2c2412b2f8291754c16992c568077e5bd2400e70cbecaf3aed9b852ef23f7e9981abacff716e35d41bf34460b480b07b7ae36da09df8836bb4d45ca6fc929ac9b0d38707d4f2bcdb4c34e7e785a0c53a7646f20d853c4f6443	1	\\xe043c96599f684ebc3d7a0292a84eade4e0339b5539d04fb4fb7e9728dbcc225b4c7755f09a12f3a28f6a05a5ee0bd0aa102db024d5fa6b4b4b36d0c65d44e09	1660252001000000	0	11000000
17	\\x9fd3749566bfcc295044ee015b2e765ad73a8db672e77fca78623861d326a26940e2caf190376cbff5a294d5666bdf4827824b2fa3f89f9f4f75e44dbcbd5b5e	403	\\x00000001000000012037f458885b59ee97e2f1d739121cd06c25f49bbc3de5a91fbd4c8320307b0f068e3f6938f34f75dff2a2549855d7f86f27cb65119061ff2d1f8ee847e665208e9812f5cc0935b5acc62cc98cd6e6c5442302f15562e9047d2a8f280ca08a5a977a5e46f0d8871dd346ef535cb090637079d3698e0d9f3f5af710aba19a7bbc	1	\\xa6ed7d62a336fdbe09eaa930fa5088df954d0efbbfeca4af820fa7f759bdff0a878e304dc8bff515013689a5c3740cce7b291b171be9ab567ff44fbafbaa960c	1660252001000000	0	11000000
18	\\x2b681d589277493cbf7e393993083df45aba66b0d24f2f7d30e20cb8e03ada0ab302f212233e39c1f687539d64f9fb97d6d96984aa3ff1129ee1d5e16847f352	403	\\x00000001000000015e6963092c0a5c0b1069014303a8837618af77354997127753888737f0087aebe35bd021055c761196086d65ce2347c3a17a220b6ae4f50ade4cd00c85131eb03fdd443c2887e95fd406f5fa153a7fd7731b7e5161d51ddfd3cd3cfe4bea99cf98544136b8f6f9acd6d816136a78827367aafb931fd4ae61f458a2b948d4ce62	1	\\x84e13c60c92c7c85925d445d065545ea8994ffbc85c1230e11bc34f7e270c936aa38dfb5287a340174362dff78118b641b8f3fc780ef8b3b1e123cb90f1b130d	1660252001000000	0	11000000
19	\\xf55bfed8d97986b91b9402be92d2e071a744ecd29e0ce67d72b3fd84f7ea3f5e3654ba63bbbe415d8e20bd3894b4beb43aece35da9dff4b1940085d44d4517e1	403	\\x000000010000000123f94bd65cb625b470c5a1a9202e7cbe6c94321e5fe229119f640da40da31f103475adce8187a6ce9f3a39d481ce5b042790439803270cfd85f4214418c08d7c0c0968a471cd5ff3765176aabe7d5be31b402ae15d5158ccb9952f93bcd63c774bb7fd197cd95f178c283fe64f22fa5e53a341d441d42bbece66cb672e3b5fec	1	\\xcab0466b2749d167ba5e45fb891c06f9373b836c7dd965fe432066d382a1d8a705a58f7ac794dadb0f97000abdcd417a95f293c8e970c14e8f63c71ca2278a07	1660252001000000	0	11000000
20	\\x0f762b8f363d58353b86b136f25591548af6e04f65c0d740e9d09c70139b9df628e60c705e3ab385230721f71782af89edd4a5c61be19f5c848f6d78c416e442	403	\\x00000001000000017ae426d45ede03c0046c9399353e4d420aeca739aad0e1b9d105588cd5b8c21ea873bf3d588a2846a065c7c7a30adc704e03fa90cda72e679c609f9153ae458225b6a99608a9f9d789c8596db4f31370a31e418ebb82d329e81fc4ae3c642e8ac0711685b1a8c30cc3423f11c1e7f218c0e0a1bfac50288acd861d4fb3a4b1f0	1	\\xf8999ead98d399134dddbf19810c997053b8877306062db5bdac38050162c4bea78260e943317cbad886546c47b70342d2f00f6cdf0ac71ab23921ec76be2308	1660252001000000	0	11000000
21	\\x14fc7a95cf87bf59a19b7dd528bfa3878174168c0e7217e51b6e00186c72c4d01a918d947fd3e812099c76d0827521b8e4cecc059635e20f3190b3bb4b42cee8	403	\\x0000000100000001683128cba071c427bad822ff469361605f62e718f7a919106b06ca6e29de6666d602b9b93f4f2158869520ec1f68a5191e45fe6063bb972c3046cbfc323ba229dbbd2da9c0dfdb0bd2bf0523391ffa4c227ef28edc8c40ef3b16a9d05c6675cea08eaf6352f169c870de0ad1eac4cd30588f142dca5a8a924f589a37a29c7cb1	1	\\x31edae662d2145edc6549d35791842d925eec9b2963469d59ccc238fc8aef45d2c45b4b339795c404e4421bc1798285ea85263f2901e58b85404b0930a438f06	1660252001000000	0	11000000
22	\\x81a8fd47c3bf204e86f36637f6b5bfd83fee39a3b8ebe8b90843622176180addb5af00edf6777deae33250423c54b4e89c366f726ad8fa0d413227d223abbeb9	403	\\x00000001000000010d6296f5a40971a5c0319ee7d32689fb0e44e825229e2c2d05695b03ac2868c28c4a234fa26f16ee0c1826d8d40a786a3b9b816d1d76b9948a09d76bf535cf10ed4dd7c6060c3b53be30cb39c18d9a9028e8e2b9722fd39709b087a91a219ccbac72344752fd7a952cef44fce3c7a0301efbd04e74743cc88e859216d73addb8	1	\\xc174c5eb78ce843407bdaab8a38a5c370805a6cb44b2ef086e8905e36ee4216694351c92e2da6bb8f356a04d167036d47109b2743268db1cfade358c5bc3230f	1660252002000000	0	11000000
23	\\xa664465b942b43d139f78067cd948fee40d55a1cadd695902a420703f4025e15d0e0a9a1eea777a02f20ac64cb423fdb002bf4e0991d15ccb64486c351533139	403	\\x00000001000000016f6f9d968e91fd5bc331fbb078e0a6acb921712e9152645cfbdef6d7a56c92624a7f7379dfacb287b7596adf4ee97996ac37aeb5a0a81ebd986ee5fac8c649e5e21f77ae0072ea3ba8fa446e0e806964148d7be9ac1cbc00b7b63da0b95fd303d7ffb087974ffd8066ddb1093a78f28aa6f7f241268c0a9bcb55159d1af61d97	1	\\x571baba1e5720af86342de94e9dbc45c9334c2ed41d8e1e95c98cd6a7516c5581461bb1a38e1e30a9c471097d19afdb57b6ec296a81c11903d65b6b73e8b6602	1660252002000000	0	11000000
24	\\x2725f5402becb99f9b88c5b70ccbb6cda96a68a505c75e0eee283a4773477d22c07c17baad42363f0e908bbd333dbd46a82773f435fb42c1d27c0d65aa632d1a	336	\\x0000000100000001ba0b91a9d00b1249d02cf0371d0d185968d456474d5e3ac79fd8c6991e5d8dfd0fdc1d2bbf3a792bc34630fc56b26371f2d3e9081e416694d9ddc0a7382c8899986aaedd9210c8e3d6559311b66d8449b0f7484ab0526c87d6f303a81a75415cfc6ed09d786eee784af5e896c6d6f6e902b1174501fc946da8d7cf37899fda2e	1	\\x97096864c0eb8ede8e70ef872398db34415f1da78a78659364c73686753d18f4152c97b0df7b00f0442b8e96b8873089de2bd67e17639abf756c6410f230d306	1660252002000000	0	2000000
25	\\x0c8ee183c59064303aa6e37faf4891ecfc4bb903bbeae0564dab530432fc8eb0e6396c68fba19ee4fc65bec76ecf3d85330c203696ece3636d7abf3ac503ef71	336	\\x0000000100000001a261b7a74ea47207c5bc7d601396def11c401c1a8becb28869770768ab3b46437785fa27537a066e89179f8a1c4e1460eb600acc3bf55e1f94ce06c59673126615ef9f3eae1339e4617ea6076652838348faed3c3fe4e9a23c5a38af0b5d9a683fc3f21a3f207d7c8212c782a6e03792980381e03fe49501c30e22c3ddc0804e	1	\\xf46bfed34bb241b11653ad4166cdfd5fa80e37af9f749b43198d3ee7becb717b6313c22487365f200d037531d183936a6615dfdc1445d80be1811bb2f1ab8d04	1660252002000000	0	2000000
26	\\x07c866917cca939069d3ddbda32eb54d3d681fb8d43121fcb9072d340373094fb26438336c4305b639d418547afcebff7c7a067c2fe53fb37f0b9d761b317c8b	336	\\x0000000100000001d5eb11e742638d9d04d20b5a8dacec49d7489a3df045d91e82b6801102a0a7894c5802c6f7d926e37e8a99b198b33cfe0e4da087ca39c8c5c1431279b7464526d4c020494d391143d5432208c34bf1b8e26ff9aa5b5d6dd53bd5ee202d9d9ea34a8a99d0a11021f321d2979593167982fe608f2d1fb1b721cc173c6852b5c8cf	1	\\x3a329b5242ff3d2b272e15dc79a5db1cb94d8d34b47e4047e51c2b2721c0ed0030c650292953b8a6a14a921cb7c86ba92039dcd406a0cc9577393b4020a7d608	1660252002000000	0	2000000
27	\\x7fe07d483d5c7b877bdffea29da031acc88127bc6ffe3a28ea68733e20a0f46d16e9ca840c1a3de34d60934faa733997bb13cf97c0d88769af946c32750c2336	336	\\x0000000100000001d5d7176977c3e441aaf826f071cdc5a9d210eb19b7fdc088d87081509c097e6f7d792ff0cf9ec602f7986f5bb4f2e4ab7bbcff8ec7474896e105d5244ca1658375b73c2868c7083958036f8f7464a3e6d75d3e78f7e6fe9776a78a7ba3f5b4fcc3185f828fc9acea04f7af8db41dcc81cea05fb8a53eae8c873c61d1e3e1a965	1	\\x785eb5045a74f0de6e784ed333d9801e3caf0ef2756a22d7542a754117742a4b2a6c1959f14ac72df219356abfeb8f8ef03d6bde187944d470ca07044f513107	1660252002000000	0	2000000
28	\\xef009dcf258587b2b0bd60ae5cb02df02051db387bd4e272e86b70b8785d62ec97aa6ccd9b412bd71a1bc8071e09267c216c98ad6c4e988ff6c1aa7cbb03de55	336	\\x00000001000000019deb70378fc0ec23c50555cd2e678525e32650fca1b911340d3ac5f33093b2705d7336deb2df0466491915ef3ddca0ea09c000525307588b86d105cf6dcb85365d57152a39493502925569acec1d027ae5c5ce9c2164f18a54ca1677809a99aa670679fa4876a491ff745ef0f8d3f8cf2d07951b2080b12ed43a1bfc04cde764	1	\\xf8c4f298832bde3b4bbacce7554aa4c162bc59eae4c2369154f4cb6a337d1b6239457e0e9800116a83c1bc203da880f4fddf515266d281be77a43c6f96de1706	1660252002000000	0	2000000
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
payto://iban/SANDBOXX/DE064129?receiver-name=Exchange+Company	\\x67129d94d4f028b7e536a2a4d330ac2103cdec329059f9d4f7aa47df502c7539692719d34ac10288b2b8dca765c11d786f5aa12cbc10934864da973fddaaf900	t	1660251981000000
\.


--
-- Data for Name: wire_fee; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.wire_fee (wire_fee_serial, wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, wad_fee_val, wad_fee_frac, master_sig) FROM stdin;
1	iban	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	\\x9fda3f2a4bc7c77ab186c3929087712c84a46441d47703351ef6ccfa2cb9d9b5876e5bbc854298fce8480a73a90afd70abc2f590b5503ea4f22ac6bba2cf2901
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
1	\\x75b009a95c776f463a8a9f5686a05a39a61e4d65458d1dca21f5789940107491	payto://iban/SANDBOXX/DE496362?receiver-name=Name+unknown	f	\N
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
1	1	\\x0678b2516a6a03a07d769bdcecf7a468774ffd8d9fdc71dd9db51083b16ec263f2c97333baaed167625c522e0b6498f54c4f522a1e78d307b5b99550fdb12e8b	\\x79baa0b9272b661741bf49d52101f098	payto://iban/SANDBOXX/DE474361?receiver-name=Merchant43	t
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_contract_terms (order_serial, merchant_serial, order_id, contract_terms, h_contract_terms, creation_time, pay_deadline, refund_deadline, paid, wired, fulfillment_url, session_id, claim_token) FROM stdin;
1	1	2022.223-01W2RJ0978BA8	\\x7b22616d6f756e74223a22544553544b55444f533a31222c2273756d6d617279223a22666f6f222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f73223a313636303235323930337d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313636303235323930337d2c2270726f6475637473223a5b5d2c22685f77697265223a2230535742344d424144383154305a42504b464545535858344431564d5a5a43444b5a453733514358504d3838374342455239485a354a424b36455841584d42374339453534424742434a4346414b324641384e315759364b305954564b3541475a50524a583252222c22776972655f6d6574686f64223a226962616e222c226f726465725f6964223a22323032322e3232332d30315732524a30393738424138222c2274696d657374616d70223a7b22745f73223a313636303235323030337d2c227061795f646561646c696e65223a7b22745f73223a313636303235353630337d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22514b455139384b524a3752474b425a32465357305330593037473141564a4d424448505a32333039384a43353733314d4e595930227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a22573554393059414e315136365a3443394651374347325a30473053534345484d3144304a435643425a5635525333394553424d47222c226e6f6e6365223a22463638324748325031534e32344b564d334a4742383033483437315251514d30535047505a424137515744303351435242534447227d	\\x8441fd1913c230ce67352d8eb45d6c172a1b5e5855d8b46b4697557670d81e8dad19fe10cb06f98c00112665d5cf514100ff77d7319c87709f638c1a91092ce8	1660252003000000	1660255603000000	1660252903000000	t	f	taler://fulfillment-success/thank+you		\\xdf55438a8d6cfdb1232c5e672e760d69
2	1	2022.223-00RBNWXH37EZJ	\\x7b22616d6f756e74223a22544553544b55444f533a302e3032222c2273756d6d617279223a22626172222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f73223a313636303235323933357d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313636303235323933357d2c2270726f6475637473223a5b5d2c22685f77697265223a2230535742344d424144383154305a42504b464545535858344431564d5a5a43444b5a453733514358504d3838374342455239485a354a424b36455841584d42374339453534424742434a4346414b324641384e315759364b305954564b3541475a50524a583252222c22776972655f6d6574686f64223a226962616e222c226f726465725f6964223a22323032322e3232332d303052424e5758483337455a4a222c2274696d657374616d70223a7b22745f73223a313636303235323033357d2c227061795f646561646c696e65223a7b22745f73223a313636303235353633357d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22514b455139384b524a3752474b425a32465357305330593037473141564a4d424448505a32333039384a43353733314d4e595930227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a22573554393059414e315136365a3443394651374347325a30473053534345484d3144304a435643425a5635525333394553424d47222c226e6f6e6365223a2231593841544e5354434630525158334d5a4532395634525339354b5047414d363246385a5951414d593153354b5153354d485047227d	\\xd7b5b06be021d66ce41c6560f4717a47aa0b555d40e5791a644bb0586713b09286338aa317eb152d53e5f01914f565c98294bd0e1c75a9844760606674fd4a07	1660252035000000	1660255635000000	1660252935000000	t	f	taler://fulfillment-success/thank+you		\\xb3cb7984e8e89f6d1c16e14460066ca7
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
1	1	1660252005000000	\\x35290936b3298c531f7663cc352f52328dff8bc55a888c778a6a5f666ec72229	http://localhost:8081/	1	0	0	2000000	0	1000000	0	1000000	2	\\xd50dc64ca5b7862a12c155e61b64594afc040a31a2be906a362afdbd8aab7b3a5170546d859add936f63fe8355da242984643faf82de20103ab5eff7c78bc606	1
2	2	1660856839000000	\\x017ffcb450284349856b997a0936f632297b24f9014d29a8e125cafa62343a6a	http://localhost:8081/	0	1000000	0	1000000	0	1000000	0	1000000	2	\\x459f3fcf67a1817ab920c21a7bfc684b70fde3764453b7c168d152dad547ab26948de2b36fee43a133f623b638c4aa1adf16ce57d00b5cbb88c9a7cc3c739500	1
3	2	1660856839000000	\\x093fb1065ac13f3b0c67e86c7c62fd7a7b70fd2cfa8aff5124f90179d4107648	http://localhost:8081/	0	1000000	0	1000000	0	1000000	0	1000000	2	\\x2224d9bb7f6af8966c5f4eaf1041a3b8034a5ea9ade16dcae7a330da5d455afd94f9b2436372bc2c2031c1f5a7d8253caabb111ee71d44f2909cae0c0e71ed0d	1
\.


--
-- Data for Name: merchant_exchange_signing_keys; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_exchange_signing_keys (signkey_serial, master_pub, exchange_pub, start_date, expire_date, end_date, master_sig) FROM stdin;
1	\\xbcdd74a27891f109afe27e780c83c03c02adca8b6c6df10c094498538c34afbc	\\x61e9b7de014621a1cdd10e78b3c370bc72a9364b5d33ead64773fd2dfdbb8301	1689281174000000	1696538774000000	1698957974000000	\\x4a92c272d749f83bca847f714d0e590c4458b9be6e01e05e0793a5aac9d73d64d1ba72e1d76c3b2a50125c529cf6b95f867ccd6046ca2619137e7ab3cb02dc08
2	\\xbcdd74a27891f109afe27e780c83c03c02adca8b6c6df10c094498538c34afbc	\\x672f96a79906416c79911983f7f421ea7601768c5682b00c0182e6127c394ce5	1660251974000000	1667509574000000	1669928774000000	\\xaef46bdc9c4d567dbd397ec55797c87379aeee60d6756af2c0d32ace59e32f0afcf671521ad58c69e92b2e06c6049f01793c7b539323c438483be063abed8f00
3	\\xbcdd74a27891f109afe27e780c83c03c02adca8b6c6df10c094498538c34afbc	\\x89e5f703eb5057280ec41ac2510840d1d81edeafd57352ce77a78cc6c736d020	1682023874000000	1689281474000000	1691700674000000	\\x88694d8e88dffe78617bdeeca7b61035d2da33266261ed08adc84e6316900e57f0291c0c323c9b6b11daafc85b18b2fb6365d657cc922b14cb558deac5a76d0e
4	\\xbcdd74a27891f109afe27e780c83c03c02adca8b6c6df10c094498538c34afbc	\\xeb5875214f594284c855420dc1f8afd8126b03e06d183ffcd41432f8d9781acf	1667509274000000	1674766874000000	1677186074000000	\\x53ed5d6466a2783f2d1e481995b1bf88eccdfda4bdb72b61afc01c29e7f5ec9994cc11da508b1cbaa8a874b7988519f9fc88f9d089860e4531a0c958d9c19603
5	\\xbcdd74a27891f109afe27e780c83c03c02adca8b6c6df10c094498538c34afbc	\\x5d4aa2e9a1eaec531b2b2d4a927d284f869c4d4bba27935af9a341ca01ecdc76	1674766574000000	1682024174000000	1684443374000000	\\xd66763e65a8b370e300bfdf32df7ca3d026046ad643d28b95aa73d40d90a85e61ae81b2ba34124413f28720f8e64c65208c88a18e6b0ec3eb10ec0b4eee69f00
\.


--
-- Data for Name: merchant_exchange_wire_fees; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_exchange_wire_fees (wirefee_serial, master_pub, h_wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, wad_fee_val, wad_fee_frac, master_sig) FROM stdin;
1	\\xbcdd74a27891f109afe27e780c83c03c02adca8b6c6df10c094498538c34afbc	\\x21e4a5e9d5d17432fa0b1f7a02f8047c7634c1053d6aa1f6456ac134caa8bbf3da7776a78f85636af980472afd166b4edad654979a89d92c49a4ba992a7e3571	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	\\x9fda3f2a4bc7c77ab186c3929087712c84a46441d47703351ef6ccfa2cb9d9b5876e5bbc854298fce8480a73a90afd70abc2f590b5503ea4f22ac6bba2cf2901
\.


--
-- Data for Name: merchant_instances; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_instances (merchant_serial, merchant_pub, auth_hash, auth_salt, merchant_id, merchant_name, address, jurisdiction, default_max_deposit_fee_val, default_max_deposit_fee_frac, default_max_wire_fee_val, default_max_wire_fee_frac, default_wire_fee_amortization, default_wire_transfer_delay, default_pay_delay, website, email, logo) FROM stdin;
1	\\xe1749079550dcc6f91897dcec80be08033963a340b41266d8bfecb8c8d2ecae9	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x0000000000000000000000000000000000000000000000000000000000000000	default	default	\\x7b7d	\\x7b7d	1	0	1	0	1	3600000000	3600000000	\N	\N	\N
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
\\x6f95cf837c04368bd166ba8b2763becaa7bd36cb0550ee8101ed411a56feafb2	1
\.


--
-- Data for Name: merchant_kyc; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_kyc (kyc_serial_id, kyc_timestamp, kyc_ok, exchange_sig, exchange_pub, exchange_kyc_serial, account_serial, exchange_url) FROM stdin;
1	1660252005000000	f	\N	\N	0	1	http://localhost:8081/
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

SELECT pg_catalog.setval('exchange.reserves_in_reserve_in_serial_id_seq', 25, true);


--
-- Name: reserves_out_reserve_out_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.reserves_out_reserve_out_serial_id_seq', 28, true);


--
-- Name: reserves_reserve_uuid_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.reserves_reserve_uuid_seq', 25, true);


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

