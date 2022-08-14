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
exchange-0001	2022-08-14 17:41:08.409628+02	grothoff	{}	{}
merchant-0001	2022-08-14 17:41:09.490024+02	grothoff	{}	{}
merchant-0002	2022-08-14 17:41:09.876162+02	grothoff	{}	{}
auditor-0001	2022-08-14 17:41:10.01286+02	grothoff	{}	{}
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
\\x3a1879c2e73a00c6f601a4f4fdc63cb8c4dac8fa6bf72e91eb47f6b37fb30f8d	1660491683000000	1667749283000000	1670168483000000	\\x66f1ef602fe677463093668c6d5af153d585161ddeba5d96daf43ba33fb0d724	\\xa6c2fd4d93425b6f1e2664fd941f4dae30cfe42777b7bbc0a4832bf302a037e84e3dd67b4595328a7d54827d0ab9b3f9a3d72d27ef09859ae7c753c4f55ce309
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: auditor; Owner: -
--

COPY auditor.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\x3a1879c2e73a00c6f601a4f4fdc63cb8c4dac8fa6bf72e91eb47f6b37fb30f8d	http://localhost:8081/
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
\\x3a1879c2e73a00c6f601a4f4fdc63cb8c4dac8fa6bf72e91eb47f6b37fb30f8d	1	\\x30e10f96acae7c9bf6cdbba377f1ed6a57b55910c88065a1997dba4fd9285cd6e79287fc533a97bd8260a1f66c904f53180ac2a41c72008fe08cc927e75343dd	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x9e465ad20ec1fb41d9afc45f3afb14ca03acd9b5ec53e31acb88abca4a053168e924080751d39fcebcb106537260e26462a8d48c943f996dde0b282fcd95e52b	1660491714000000	1660492611000000	1660492611000000	0	98000000	\\x195ef04c4532fdb2ae1967a2ce2466dcdb8c200d4f73d41c2225849867e43619	\\x53ce77b6d1f1959c18ed6b87a8d312c860db2f59ac1c1e0b688b5070701eebbe	\\x458f33f3832b7a20992572931bdd73687bb6c1f63a9a83ce896c84ac70215d925bab2d7655e96e02a6d4abfde451a771c340cd348056b4df16e8f099cabbd405	\\x66f1ef602fe677463093668c6d5af153d585161ddeba5d96daf43ba33fb0d724	\\x400d8daaff7f00001df9c5329b5500000d454f339b5500006a444f339b55000050444f339b55000054444f339b55000070cd4f339b5500000000000000000000
\\x3a1879c2e73a00c6f601a4f4fdc63cb8c4dac8fa6bf72e91eb47f6b37fb30f8d	2	\\x8e42c55b0c18c6ac72a18088cb898daf9233474f9a2f22776d6067f49aa0e6ac3da1b4b6c96c7b93d531ee3efbc3b8902370de925c71b2755d0121779b963515	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x9e465ad20ec1fb41d9afc45f3afb14ca03acd9b5ec53e31acb88abca4a053168e924080751d39fcebcb106537260e26462a8d48c943f996dde0b282fcd95e52b	1661096546000000	1660492643000000	1660492643000000	0	0	\\x07eec627265683f6c6a0b3ff7f0d8e5fccd7c0d64b0355b057264230026aa7c4	\\x53ce77b6d1f1959c18ed6b87a8d312c860db2f59ac1c1e0b688b5070701eebbe	\\x86d288768be2b641f438b04f7b6caab313ef4552466c0dc1ba14ec614eb11adfc7dea72efa6019af3ddff4499765a74c0e9ce7af38328250100ec02cfb083d0e	\\x66f1ef602fe677463093668c6d5af153d585161ddeba5d96daf43ba33fb0d724	\\x400d8daaff7f00001df9c5329b550000fd7350339b5500005a7350339b550000407350339b550000447350339b55000030474f339b5500000000000000000000
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
1	1	46	\\xfd6d38c3ca0955aeeec636bbbe2e01f9fb8663ce9d2bf4c1488668144b6f3e58e886be1bef84cfb2c27586890a94ea2d52ab0a3074424e31ba8711b64d51840e
2	1	181	\\xd1a1461ac9e662c91487de77cf5ad120420a15f0e562b3df0d34e3b50ef529fb0320878c6003a6f088830bc2b90010b366aee0bf95319ba9f265dfcbc888c40c
3	1	189	\\xae1fc3c9183221fd4c2e25b99abf1880741ea9b41d9a16293af5518375cd55b1a3e33d5cc0edb9559f86d510956cf459fc480244dade7037fae9926b1505190a
4	1	307	\\xe0b118c650fcb0d93498bb52385be949843dc1952e2ab0bdc6f97b6979b9662dad6fc870bdff3d07b97fe5ac34cbcc2dfdaf433a3a95b6768bb824fc034ecf02
5	1	209	\\xe12dbb103dbf2e7b24508d63cba39bbeffd070dcf396b7e57d125b9f12b417576de41345b4efafcde829ec18d9b16c0943a5cd7f6faca6d2a41d289f6623b80a
6	1	93	\\x18f2abf61a91f733f28dd006d86397dcf5eaa4eb77d7500edbc0a7543e9de1b66e75c003c88b3eba5b358c4e2b744732ef879c70f822d8544cc8fa90b1ed0100
7	1	226	\\x5d7acd1dfbf8a15fcd1a7be2325aafbd0f33f03088e534c56b965246f15cd545c6cce8355f552078833aef791dc1957d92b69d8e3215fe3bc734042b6a06750c
8	1	287	\\x5e5cd8113e047a3b4b0b89a44b3b0a734375e94bb8e3678a0da5840bba5fd1b9d87ec3b7dd78cd3504d05637691e4d4810df62fa3cc8a6103a119da5bb988600
9	1	64	\\xcaf36b8be86d59f75657160cb5a9264f3efa2d9cc77492cee1776c5d6cfa77cd844aa340c1c9539ea52577b88b1a67e2e764af6691679871c151f944dc1e1c0e
10	1	276	\\x0b6905de2e4553567cfdde04876f7af3e896cbdeb1b2c173c23901cc7979b6d2be9435682bbd1136a5b07b27fcb461cb92f5d9c17d3b4f94cd89e93e4ff3340a
11	1	284	\\x74da017c547e8d3e8c97dcb819aca5ece0cf0a90d21ef12602af958b9ec27bc4189c8eb396579cb63fa0dc4481798609358b14cced8bbe8432d4a4e54a9f2d01
12	1	412	\\x764a84bde268d3540a94fe2fc85f5241770bf28d11ede019b095b98a2f4f4fc12b3ad9b4fc85b43aa30f4661bdf1ed95e454e86508ec69088ff726b737a9ed07
13	1	217	\\xf6f9ece72fe76b584e780bd319ae5504ca1e956ff303afe9a8da6d6fae594a010857595b3a3d5519c2f19de755b769cd7173d4e7bf26341eee71dffa3d2ba404
14	1	215	\\x030bbfd77a5436e4fbf338f194e8e6a68eec7ff4c1d58e69554ae08268cb524be2e8264972d82b3452b3a8f004fdfc89cd65997c5d281326bdb08558f1e2ed05
15	1	233	\\xa6a4818c9d8769845edccab914fca66656134838ccb8576d917023a534ebb76a6c1a5d4d2c977cf847279773f4a1ef7ff6c8fd2ad1acd7ee4ce94c6291e91108
16	1	293	\\x2c3b67df562c4230e27b754db4d0a1e713a34eebfb8ac22b0218c36bd95344ed9aa121c9032456bd7c786632ff1dcb6545e7e1c5f1741329bebac76c90f0ae05
17	1	268	\\xa03eaabc2f7b316c783141d82f10e6c6c6054ecf0369c66b54d1d01935002ae73a556eb36e7bf83dc78e5c20d53cc095cb9a6254bea24340ae62bea88ad88300
18	1	413	\\x537d3e962286e0057ac9287aa14e076a4d569a4d69c155e2bde81cb77f06279ab393c411e1b31793b8d8f48fc128e0e4b44c7a196e00817cc1f776b3958d2600
19	1	79	\\x84adfee150e810217f5e059ba04d5425e601ca270e917bffff6c27bdf20433d263c52f14da8a85298b3386ad0e351eb8a8545e6d337c7cf79a452e5405cb8e0d
20	1	191	\\xcc102f7650607e0284136cfcebd720535b2a6e4249fa7fb66fbb069f18ba85538870515ddf89d12f026a4a30a54df04e62884014121d318cd52feddec9e50f09
21	1	272	\\x490effdb183e4be94f91085e571155d58f988dc0d0ca2aadfc78f6d61395182d7bce1fbb1e7f0d4c50827940603fafe806f758341e2240a2c77de4897fa9f90a
22	1	305	\\x1aaf2f1b88bbd48e87f687ccf30801c89f7846ca2459e01a5996eac6c56360a2fc41a86201b226154d8463015a69b162b3ebbc2e33e94cc5f72f14d393a8c501
23	1	5	\\x8736bdd89d0df563f18db6650990736f8855a8b4e772420a916cc0ed087785e4ab2c9353e54b566543a8a5e79015e3e8d1c37d80b3c3309a9785f924a75f030a
24	1	43	\\x69f204e8d71502369393717af1b54556768e9c5308fd64b6e79777e306a5dd8517632ae0100786f4be5f946e66e6d7590931597783b12fdb5f3126db31b1340e
25	1	407	\\x88edfa488d90053eb59bbe082d5173b226991f38bbdc502d6a3a409ff200a4a1edf53a51ec3e1baf4f6fbc60f48be7d85b5dede9f8e2aa9c4da35776b34dea00
26	1	125	\\x289f087723c0bdfc8d801566f7677dc0ce42bdef6474682642d3e677093235f830cb8433362ba8dbff540d58fb54303fdf387099efef34d6ff9521c9d016eb06
27	1	49	\\xe3e8f277d11c926d61f339c0841a1dfd3bd78acee73568147fd1086e68469e8aa4aa632f8700caef6f78bf9a189f7a3411a898f5b252d9c7fc5d33cfc8326b07
28	1	334	\\xcae1cf267427270b3ca7fe1e1b2bae1bed6a29809604d692469487ee1aa118d7b5224b90c1b26ab3d5270435119af9d66aa72ab4d043c480dfebf2ef69d0bd01
29	1	338	\\x079f9083634e14dc4e2aff64d9830c19bcae59cd6e67daf5c632755eb81ce41bccbefa4b4fc1eec9291057cbd9305dd77931974d8cf5a819a7e630b6f758260c
30	1	401	\\x9c53b4d61bb4351914db7fbeee980ef755e235f60829f9b668947f266e52377134800511b7cb19ab6bc0bf48f459359b49e8f0be264055cab6558a8acb947506
31	1	158	\\xa1ebf5283a12b6153015bde48e256b477ecdbd08aa6d16e175a98ec5f31dc31eb935a6e01201106739a2831ea133eaba2cf1491aba1e752fa095c20be0625004
32	1	192	\\x7b98ad8b7588db40206586bdfaee4faa066debee370cb0e5b5038733fa9528605afd51c1997e4e07e124162f3c59a19a969f6c6e97ecafd2079fe6a78b03210d
33	1	124	\\xf1dab759adf4358cef579c424d6f2a49d3a694d52b2f641fc8da58da3f29190aac8c68077be5f199c69d2363f6ed36d601ce0cff4b260467390f771cdb878208
34	1	216	\\x042700826afe3d53a5ec5a8be9f1256c21ad63e99704981a188c2ac8c41fb0b1b0ed5a6a9d92347c8baba4715660d55fd47dd2d97043ccdafa323d01fe277709
35	1	317	\\x8840a6abc83b89e0f2726f7601d9cdad19a2a9d9e4347e2d175466721947d118864b3553a0cfe48791450fb5031cb59ffe5d4a53279290bd078820fdcfd0ad0a
36	1	382	\\xdf2cbab93c14be2b196f2f75e085d157579f1b73a00692c47641768cf90cc8b572b12d949fa459644f6b81e0fe4b48b98c0cb812da032f5cb80eace85f58ab0e
37	1	130	\\xf9a888aea3131ffae1793759fc91e1687eb58872614628731e6ce767e9556e86e6222445d1b11593c32c1624edf1cac1e8f06cd9c7e15a594f360d473f291803
38	1	173	\\x818844faa434f27222201975ecdc51b7035dae2639c93148609493ea3b5ab761961d68538b66a72a31c80292b761c2ff4eb3caf55816d1a8ad08d3c600392e06
39	1	16	\\x82678e9cc0108aa894957180fbf406ae6ba996745208300e93cba241f6498b2e09dac0f398a12edc839add09cc19355462d9077a00489821315d3b513deba502
40	1	288	\\x3f71fc6d48668f2b37f5768edb0dc98b26ea0d01093b6ebf8d8453622ff0016c0fc4e0eca363fad8336015a8cae64df1ab4a6ae177dee1d479b746e538abe808
41	1	34	\\xaed7873f1c023703fe07b658933487b44ea689887f854488ac2ac8ffb7f6cd48746c226e32b5eddad8aad3786152292d1553b7628f0ab232835f015747edba0e
42	1	421	\\x31b2d9035bc78ddf297100654ee8351bab8db59bb9ebfd4edfc355bf052a7c58771cdb00788627e570eca06fbe464f400c277d18b480fe6c58c050c04414e60b
43	1	177	\\x3cc93c54309da81a2a5ffe7a0fb04cf1253f90bbc56ed47c27cac46805ec2ee94780bd987adc6eb3e491b0154fe94224abe7cab7f08e4ca79de420bfce42ac07
44	1	48	\\x8ab42444aaf9b48ce27dcbd795b56c64ae75abfd85dd4dd9206caeb5eb1cac888452999cd5030cdb96b1e4e363ed299c5b8872ab4f05a6a01e0145f95cf9df07
45	1	299	\\x7d07b526cd67f07a0a2304dad5c04b2aa7e0a2e859577cf54bdba0ecf020bdbd9625996dc874eef4c4f0ada412493930a8d5d31a1a9cecdbbfad3e30fcfc6101
46	1	422	\\x353b990698717e4024292f5c6e60f1717fd7c6cec66c3718d95d09761a9b21b251284cefa17cd28c09564d3db2d63b41dbbc9f9fa92b5fb84d3617f69791200e
47	1	52	\\xfbbddbf5d1864594671c2e6b24b116eb00e2d150d887098941d50effd60cc137ca219e15678c22ade889a646997bb621eca4df2768ff7866031d5ea652380c02
48	1	348	\\xc69c938229477c7bf53a8e273832bdc082e17c6e89f29d7fcabe29cb3e1f83522a62cc09ab826b75731130c274b5a1180a902dd339e6ca8d55bba7ae6d49ef05
49	1	296	\\xbaf848c78e8ce57423753db71ea83ee62f0d8af9416aa5ccb763e2e2ded0e2b50e9930dc00ea459839a0b24a34bc18f2c43d7a7873b9d81f8e42430de8886c08
50	1	397	\\xfe713b21131e58ae8dfee8035246103f5262d13f211be025353621892e9f272903a4252c7bf795936e369e90fcd443ceac0b0caaca065c57f15ea431160eec06
51	1	69	\\xe875cc333eaf0e1ce555362299174a1540253a3a1b31b0c7283c6c790746d834660406dc9d1e3e6d14321a3e9dbcb0666815e224fcd892fbe09892f773d4e607
52	1	106	\\xe8438dddcb4fe51ced2ac589f069b6f95d71b7be9a93ebfbda6eac7f4177b92eee5bcc379c28a4956b4501199b34f61e78b282751bcd88deda0718d59fda6601
53	1	86	\\xeee08351ef1b88cdb0a3ad2951b238cbba0536f948e7a0d0dce5d0a43b8845026ba37e7a86f1f3fcfb1f0d2004b49658b856c047ade847d24285b1784b5a350f
54	1	423	\\x79a77662c3e291635cf5746aeacc26e35589929f912e75f674fe610ea52da470ac0077d40e8014d04d4459cd88982917a41d43772160eb269028260d9665d502
55	1	107	\\xd29387b3bff89a572ebb337971cb2ea4417a41325619b8d0abe888e1b47c6cf3bb79240eddc5d831f0950c1ebd3033c02541f02ebebca41f11d3530851d7930c
56	1	9	\\xc393110be72c6b424e05f92d24c75715a861d341792b103f5f3103554272627a47649c42372a99650bab6930eac42137911d2603a8a08914541fd190aadad30d
57	1	47	\\x44a9e7acfbd20dec25aa9577f6dd40f83eeaa50336526ab0ca0fb2f29992abf5cf4a464e1c00200fffd86ec17dcb3fd4501ba8bc2b182583c43b54081aeafa0a
58	1	50	\\x4a1536f1bdf2b5c50976c938b2a75622be27f58688cbc4c85a6fb5d1fc60fa27cd8ba04c833828a1acb8b4d2b20eb4eba70e5eb4f62c3ae09910998761f18f05
59	1	262	\\x04b3f95a88120289d8d5503e44e91c30bbefff125ef74aa71379b3092aa0f353751edf32c9b64d096e8025d4a03f7723abba52fa3a7b11d695b0fd53411a040f
60	1	228	\\xa227c3bcabe04168c218aef57ce79c4b3ba64d2ff762c8b708c0e5f41fb25544660334340d03a13885eafcaa34a363661d9c9d06f10d2cd893b916134a348408
61	1	398	\\xe7b9147c7b7fcbf5e61a76ea9851626242b3bc24e47e2a4ecd2cd6450d927e9b57a16d2f8cef2db66767a483b19c15e1a67f631405ebff7a656a20f3233e9a06
62	1	139	\\x69fedefeca516d9c80e73fff1ab3f8cd9cd24c8a1ac6a5fdcb7caba545991bc6ca52bfa54d5d3dcb937d12b762ae496dcd2823fd992732d9b9f020da93e50004
63	1	95	\\xa18bdefe35e27f0fd2be213af51778a6b2524738794e7f685e9a9f7e1509ab14eacb0d22ab2710ed44c09f7445feaea5742e1d31104e30478d25861c88b8ec0a
64	1	1	\\x6983730cd1c6c89850f56afa6fd6937feef23a2ae173c2e5c51265dc50f674b65c247650a426b2d1aec5a92fdba4ea2a78faf05a31ae2bf8731b9fd37e13fe0f
65	1	136	\\x4253d869bc2843ef0ee179b31fede1a72a9e69bb4900fa11a9e942f1d9c2907c8fc32a8a2cbb9ea37313bf7e658cc4340dd2b6f494ac357b31f26ab7cfec1d03
66	1	113	\\x44a3e22e3846672942e81b38e431eb99674d2503a52d7a151fb8500a3b5be8d714a789314052e56fe84a481624f82e086890f89f86f7d207661ea5bfc88dbc05
67	1	295	\\x787bb73148d1728d9814a84bd0b361ecd248aa6b7b62095b41e3b76918ae6dc127ffee998b8f7949adf2e6ce5dc497a103f02aa3f35e317f541b9c5438821d0b
68	1	81	\\xdb51391a8d2821c0f01e98a10e13d455fda717b694da6ddb36af0d93cd25c6c2fa0bd82a8f5da2b9fc626a77ac83f24ba1b32ad35c0e97a3450ffb3fde271703
69	1	140	\\xa16facf7bc5e77211f0ea1597d8676ee76c177659c5278075666f52ecdec0de1bf29ce40eb0a57bdd6b99ee8ceb2f487cdab1c99c9451435a5fe06d18ddad70d
70	1	365	\\x3ee75626049857edffa00f31a5e2717f5de56feb570a1d8119d3ab51a9363168d30c9fe7554347f05dbf74b8ab39ee627e6700feffad8711b1408b7fdb04a609
71	1	373	\\xd5f7ce7f7ec1c2c2fac14b0fd0f91e144e1c8e5d082746907fe8427f1a66c1f6bf1a9d13f2c5fcc6087229efc478135bf3e968645fbb45018632fc206cdd0d07
72	1	127	\\xedce1b4b34768c71ae38ce6439cbe43dd298b6cf79dcd9ecc4d9623ea7579b8630a5df4668d46e2e44fa60901cb82df8cd2f83c7fed26d28ee144aff1f76c40d
73	1	123	\\xbd0df63305d9f053c42031c3be789e835d7c12d5c124f53fa9ebc1505c3414eb20d2b380069d924cf8793d037d0b89043bf4f5c766ae49bb3cbd465e85555107
74	1	336	\\x1adec798118aa2f4e228faaa919fc5464b20b715628e2c46855757217847a0421a3e415f988a2ce2425366444e9f3b23106c915240b81f5985068293f1b84602
75	1	128	\\x80f4e1fbdfb41c93cde79e00a7e15da2016292be9637e37ab4a5f86993cb96bc7531ae22abdfbdd617a1e34ce2a8c4f84ea0cd4786ffb2c46bba107328fa1d07
76	1	157	\\x87af883f2c4cecec5a17b8c7151a5408b4f859ef8bd1c3af460269849437282b4a507ffee620cbca2e4712864de92907b80141114bd664aab4b8a986f2359d02
77	1	406	\\x979474220b96b3b57eeb8af7297b46d9125fbdecb833794de3a8a4d4507bffc03344f6bfbcdada8a4d6ccb3df5e7af597a65e32587d54c0ddb4fee305e226904
78	1	109	\\xa540badaa40a9020e10786cee705cef827035d65209cee790604fe6849da93f3e95ded84ea4333aaad1b01b55f0ca695a6b60a6acd37bcac619a35c551be5302
79	1	41	\\xb49957e394c03aec64310f41cb0aa8bc8d72a83711b1c4412ea5633fd1d11f23b917b9cb0e5dd8e6a73d1c8ef0bcaed6f96604643545f20594867540bcf55902
80	1	386	\\x3fb2f774bebeeacdfa068bca9b6601ca16be12ed38b573d61df963734eeba7be25558b7dd4a5c503324ba7ca0e88ef4c4892a18368e9c06481e8754fef57db0e
81	1	59	\\x5d4f47c11777012e90daf34aaf7d722536d63998f13eb268122dd8f0ad9e5fbd374fcd28bda40335ce0b0deab511c056ba4695987566ce79d47733d924401804
82	1	114	\\x9e4b6308225a494f520d9dc425cade67352915f1341b797196dc0c7b3f016b38d22a3cae474798124b3468f0cbd2ccb964c853b490cb2a424962d5875903e700
83	1	297	\\xb0115851181e796c213f2f70a8b41adf65bad77780a05531ce16fc7eed1f1f5873a4cb65a05a611d7d2eab73c24b6bf844fe18474bfbde6529793fef6b7e390e
84	1	90	\\x32dfcc38dbaeb082d97ec847a211dd1236cb46fd576d529074ea8ac85a2ced3919e925aa9dbeab34eadb099e8828a9af339e73d05313aa903527979ca283d602
85	1	274	\\xe17372d6cb2530b5530907835aa2a0006c93b89a8c562961ee4c861a105269b50780b7fafde59b55ce590130b4ba7823cd2697a735643ff33166548352883409
86	1	279	\\xdf067b929b13f3440cc2bbc6bf158aaacfc32bfebe92f83eced065b5bb08651fb93a83289896d207aedda90903446a9c7151626373b2fe7097988f31c32e480a
87	1	138	\\xbe8bbd877937b78e56b237d6c99e2f1e3145133e31a384103802324d14ce2f57191cb8645a784051961022fce64132356eda8520d939a7761b16571c9fe5ec0c
88	1	188	\\xca61b75e3981b5dec6c009d32335851a541772ad65c31825263ee053cfd4c4e494c127ac81e2adb4ea937f8af3751a32658505e04e83efb5fb39cfa05939e907
89	1	66	\\xc779085a7580573c908c25c7de12d704f37e55fa5b839a7a426852425fd83a58866ecc7cd6615b30798c1a9bf1af968be6d28b1a322d3e41bde1e0d171c0d302
90	1	264	\\xf9b2b59cfa07043125c48e836b2432e8d8d34dada2ee8d45bbc36efe7241b50548e3f87216b932efdf592ebfcdb025e97115591a9f1dbee71ec5ae05bf172a02
91	1	280	\\x027b0928c685de9af685b1bcb499229bfaaadfb7d8dbb127538aff5e3ff4ea81a6c7a0d2f575ea39a276e44a95d816e276de91094433046e3c90b252e28a3606
92	1	126	\\xe579292181f365071b81b7a5ff2c34d2804af8e24ff39769b85dce484a5912e2acc6040aae0b6f4939efec5f51eee5e3c77f25214c9421654774e3a5c5761a06
93	1	377	\\x5404445850de266e0094f180aca9b952b94b0a132a55b59fee8662ed960f3acbc217f689135ffee2335c07dd4ae03e224f3092df418ee61f8baccfda34cb480d
94	1	23	\\xa6caff85aa186cc79772ebee05f972c78cdfbcfadeda8405c88c6ce957cd0734135d1662d1ee5ad780fcd11d1d9753f944f42d6fcbf34906254ebed230a8a403
95	1	35	\\x1ef4408587347414486a2cd64b7c60fa31ed87b1b40e942f02d6a98dc60eaa1fa67d14801b505352c035c6f1b982e2b678a233d7b3619c83c3050d5c060c9505
96	1	409	\\xe808a5b43a2f0d2dc2c8f7808cc4b39476bf34ab812b3ba53613e924c9c32146bfb2c6d96fccbf0ee18d733ba2367ec73d7b79cfd98850e3e69a68637eb2df06
97	1	313	\\x4db77d907741dc492f423c3b83a21531ba7151e149d707a0f24657871101fca5f7981c68ae10cfcb2f465c84693c69651d0380d9344c261831f85a2f6497f60e
98	1	63	\\x65597df3415aa7086689048ce1a26e3b02f3b83caaadc82868fbc2e7c38f3ee4f6242b401780e17e11c5b29ac0a608eec4fbfcf193dcad05a04e6beb7f7a770c
99	1	240	\\xc8a30202d6198ce413de54c00c61584114d5c6dd019190c20b92b0d684f28233b3af4296940040e2e6273c58ba4de1eb40c36065e92521ce5231f367e5963c03
100	1	27	\\xcbb3ff308d18a640e457a6ad3ae5e2a03ac8edd590e84a82428a324684aa6eb6a05e1f541d2a476dc89aae2a0d818a9bab0daedfe519a5e3315dea64566cf30e
101	1	151	\\x24abe07a27cf7688b0c47238289ab1d6b28a636038213b513814001ca0617fa693e07839a5c0ff6213d2330b681dba190ed430f7bafc1ce3839f5639065c3304
102	1	182	\\x82e881cf91c18a7499e392733b7fdfdb3cbe3cae05eae412d522291476076a725fe59922071778ba3ee56a26d5f51242f2b3d508cc02c11f5ac6142a93488a06
103	1	408	\\x6319a5f88b9d507348aa72ed5134a854e4b67c610d8f8c34dbc7a586dda301473644fc0fcf327bf0d906b730e4345778b582cef17351b7013c79bfb48a830a0f
104	1	7	\\x01cc21e370f3ce7f1e996de4252ab67d0f702c3838e5ed550229dedc99fb8e89cde1bdcabfb9cf2b885be083868b2fa3887c108fdac5b50c03ba7459bd6e550e
105	1	330	\\x334f6141d1c7d1c49286cd42104938a77f055d0fd175f47ffe9fbf6771e630f069ee3027b2b3531f716eb4d1a429df86ab31653dc2e6ae34d7401aba17fe5e0a
106	1	211	\\x4cff23bbc2c13454b51ec3ef863864be4bce04e909f688befb3c0611b7d43f77cb2aa1e33f04f395f2c8a72a0361603b8038ce67fb943f0ef54dc1aa44a65c02
107	1	266	\\x73478762cd95cda290a34dd7c133662a923cc1567ac6e276fe66efd16284ef6fcb0126fcf7fe21dbaf8dacff4bf415e83a16d5d633bb1e3583e1565d9b9a7f03
108	1	98	\\x0d69831726e17517d2db321df53fb85c2ec8f420d0df006f84377e6c2af0ac74d4763661adfc102f40d79ea80044a8747b9a4398ecaaf5926485e5a334a31408
109	1	315	\\x02b841c0d2a12672333e2e64b43f09ed632552da70e8565709df29b9fa8b2281d5f3534c7359cf2ea51825554967732a6c3c450d5d60d298e2dac060a48b510d
110	1	169	\\xb07a95e39c3676a34e5346458e705734833e305051485f6e187b319ce121696c76b0a6fdb52f20d94dd076798ccd71a3ffc11cc3c96904d0b41241dde6927906
111	1	195	\\x4d25d11e2f7121a71801d0fb7b9c614b07a3d17dbf891d095b1ae8239762f9524de04adda7e83c4b03594d20917c31e33efd95fc35d9eca3536367bb69d89709
112	1	24	\\x18d57e0e3402381f8841e1e9e6ac4d0ada1c99facdc6f49cf2a3daa4efc5f63659cddd24798ca37661c77add6c9b8938f0d140a995f0dc1845e1c31fa3294b00
113	1	20	\\x396c4c4ecd58f80a805dcb5e2fee09e048a07eecdc9c93f89bd53e988dd792de2d668337c6f0963dc16c98afacf0933532590178ee29ee15e3f06e5930f7bd0f
114	1	96	\\x0f7ef9ebb16fc6abc848855220ebfb2166d5271770a3f6eb411f623701ee6e0c1b3fd200b3a89e2748e48b13ff4569070b2de250f87a40765e888e695495d90a
115	1	275	\\x989c5ea39d1e38de20b3e4783f3dde391e416c637a5f5074eee58be5a406485a623e19fedab44b6fca2385cd6194243ab72e54f3387f12515ded924cfd592c09
116	1	328	\\x9e0d8afe2eb9b3c7b77ef08b51643fea5051f7f2e5cffb1d497a8e83d063de198204b30f8c0498616b7116e8bffd9d1e767e453629a0d347301913900d9a5703
117	1	246	\\x800e80cedf8080a069e023d060181401e7b185dd208aa84c154fc6498bf5cd9ffedee9f703224145ecd17f4e9492592167a9dd5d22e0fbbbe8595ab103277208
118	1	150	\\x607d7a69a18320a0e1632d32a8542ef491cb8de0ef96467ac6711e08d66b8c19c6008901c67778673aa722f34d5b0d73ee01d02e24719152fdf95f398c64c90e
119	1	11	\\xb60e5c06a01dfff33d506c6c58302876e9fe392c8ab67d0cca0f66de75d93231b04507458e6b3e36612d43a99b61118891cd1920f1c45b03465f4d83886a0f02
120	1	207	\\xa9103c4b93c42fb1ea6be85f94c66fa4a1ad165e81a418e2f21ab01c132910911ca726fdeb42dc71eaeb97c08b58f608e4af8f32931958653ad708cc4311e90b
121	1	347	\\xb7009cc3ccb6e3505796cefd9dc4cca32047bee70ece9cfcb71efcb72c4a7dfb6aab12aff83d881d03d63d93e6df3cc4c4b14577bef8a5fc4796f8ac8c4c7706
122	1	112	\\xddc699ba9571155fc10d93f06b538ab458b24c5e5fdf5acbe4f4d1bdb933652b263116d20471d0da5743b905530b32a975c42876a190de765029dd8d3604100c
123	1	331	\\x34fbcbd2c3bb1d42925ba694ef880b48a3ee1628a941b127d73aa60080bc12d22a94fbd4c22a424512ec61d1e9daf49f6790ba2e4becd7e6a9afc3337c5be10d
124	1	292	\\x6374342213408f3b85250b0d86513bfd6b72ede476f4bc83d3858b568a05964c408c49588c977d69b552297ca5906544eb6487742be5e3aeb0c3fba25fa08b07
125	1	198	\\x6a2420a358c62157e73bce7d2b98565556631dbb9af76e6cb4fe57817c8015678d67b0d79c0f610d522dfa1ef47af6861f0e4e53c71d201873fa69ec919d930a
126	1	38	\\x93767c9f6826c94038d4935d5575e4f5abafa3d20513cd526cdaa3a6970e596a11c3abeeebd87b4063bbce3832d71c8d1c10f8cdc0586178f0636d4f29c2ab02
127	1	78	\\xf9e7ab77bdc1f4ee8bc482b524d8fba4b24673f7ea9dec9766181e0ca03a9941cf5180568dea140b3bb71fd255fc88357470862bd5138f13422841324e8e3e02
128	1	104	\\xe2c930db67e9d36860304962eeaf16caa635480755bb90e2a023274cebb5a90d6887e0a7c6044445d11d46bd67bec89b549c7df42e7379db4ee9d148cefd1708
129	1	129	\\x7fff249d145e2590b88ffcc04ba7e9664149b778b70457bf78f280c200db271c5db85921f8d726f7d1985003c60f705d7e80420fe4fa1290c9855f93fca17c03
130	1	371	\\xbad7fb388b5f5c67667f9f1ec8ae1b4ce5ee672f4229a70310108954bcfbad3df52054e0e98c3ccde7281634f1b4769a31a30546632522a884b328818846c905
131	1	118	\\x25632e433e055e812ae971e4f6e4880dd468ac0ef8a6520e7f6b09687f5ad91a7407a2506b8d930dde40292bca8f8a64a6b8ba8227a8f4178b4d01280f6cab09
132	1	187	\\x471623b7f5c2ea2e49660849b62a186f9fa2e1042637fd6f970de3830864d3cf0ccd9744a26f08e8ae6a861a0e2a80bddf797c228f6fdd920d1a20703a1a5707
133	1	214	\\x3b108656c1b2727af753b2e723abab8a661d6c381c99ff7f71312296e050331be1c7b9b3202866d6fa9ec350a5d37d131fcae6c1d3f1a3df9da72ae6b6ce000e
134	1	68	\\xc14db75d738d25108a80375b83f1d930197b251824e05c91c996dda7951afbd81fafba6a59d6df7df643aa614157db48a03e6fb085cd709a562d38204c2c5103
135	1	357	\\x4ba0062fb30a8cb84af647cbc4da96223ded2d611e9f7a2a63378a34ffc5ddfc6b095daa3f664cc1795ff39c07b4a423697209e6fcdaa48cce9e00a1e065e307
136	1	311	\\x6cd5c3ca20a6e52ec23638f2e8ff30938ba086f717e83593ddbea9f1cfdcde9a049682d644a079b3fbc091cfa02cb647953494efc4438403657363f8acc4860d
137	1	92	\\xa68c7ebe147b4dbb7b0a6d2fde5a2d567e2d18500044fe34255e8278a664a9aca1d71b49422741b9d99f781a3fa8f6c393b34ebc1e5cf1e4e6ea79f52233d806
138	1	341	\\x3e5a1e47c2c7c4cb99ab4a68ad9063afaa68c61cf5262246e0ddb082eddb6a2a18db4daa7cdad13aa7feb8069d200ff5dfca7cd37f7cfd576c7d34dfe30b0305
139	1	283	\\x632fb38d37f04ff817bd7c3562461d589ca16c52cb22e1cb4d30e0fb3c7e84bcbefcd8ef051aeefd148bf2068a5034af3c1fad10a4c66b15350b6a7c1e6f160c
140	1	416	\\xf08b623fc525279118432ed260ea775fc62b21643fca5eda6f20a727770f3778044ea910e3ce24a106ebd527b1ac39aa4cca55e11851ccbba219e321c31bef0d
141	1	134	\\xfd93772873b2aff1aafe5636cc6c1ea12793e4f001dc30af335da15ac6cfcdef3c5f720655944356faf3266014831a298d3f4af1941fe8ac8747a153f179f901
142	1	116	\\xe2727aa8bc70dd2651e2e0de65ec72f24c673782b470da52c7fedbe2475434294da3e25ded9e6ba5f8f2e723235ae96211f869148e535295eac118e88346c10c
143	1	282	\\xc1b6f878cbfe3d7bd468306182e8d19d29d947e82bc0e1a118ea6dfc1faad7b6f873e5287df34680e55cbe2ad5d0d5943b8c8481741687f1a277cdd2a7c26701
144	1	231	\\x7da3d486000e0715af717e126b8858998cff43a3761a5aadca665bfb2b89b7290f8da641cad0b48b227e31b8641a68209526196fc7b1e3b2592768542948fa0a
145	1	170	\\xd4323490b04344fa8dc8e8fac62601ab6adfc5b8419007dd11319098fe88d9892f90cda58e0a570a81666807ac6a302b7c476bbe296cae2c5b5c4286a1bbe801
146	1	101	\\x41a6006a6d46f3222523c0efc92ce5e9d0edab932f0e371c3e911126decb7c0db15639a8974f4e58693506e3ef747728147e6d22f0844a7c90f3dc532cc68002
147	1	354	\\x60f4baaaa708ca5cd6ea7fa8b22133cb6886a0d4820af71a4184fc3b5849604d065d41a58d42c4fcf1ad78be22fc3af42683ce5e11436a76c608d2af042a240e
148	1	349	\\xc5896acac49abf185954f1048d972b2bbe9f1de6ba9743e3f17f443bf8ba97f606b79c24f9fe9456b76060885de3520cfcb9dea6ebcc14fe027dbe977cccb50a
149	1	391	\\xfaecc6c560f1bb82680f5e936a5d2c2502b65de3f1bc7861285a4f37991dbe41fd196dc22e871be909aabef5fb06d7200fc08c0b0f465b3f374d1fc5a330b208
150	1	418	\\x7550266f708645ce1a6d6ace88a8332ac7002f242138c1b0888ce54b6e75f9e870783730554865e13d245c7e5ae2fa80c0adbefbb239bde2caeaa348b2daf609
151	1	243	\\x82c1215699d2b62689222a2bc88c6ade08576c3746a9182722dea07c124a4405198430bea1cc8bc8e5554074ba3f0c06aa9db2e9372895d6b6bf465d62dcfc0a
152	1	303	\\xa24f88261f615ade440eb3cd221ef88b68ddad5ce8e883f07ac2814eb86fb296573faa6e82891bbf1ecc4f9aee4b0336028c5d508399d0494fb098c55eacec0d
153	1	115	\\x18f0b127341439d6a08e05f2630e46678b1ee6e16fbea2e9c25ab90aa8e67fe72bba513020a0779848a431df5fe013366abcdbcadda0618101a2d44148b45b08
154	1	339	\\x4a6fad5106a2a7881e90f9da8d27f7071575de1a9e086202747e3286a50c4ac292de10322b8025d1a8d6d27cd2edb7c55fd4d3b418d4e847064a261c95479d0a
155	1	58	\\x4078f3919bd66c4c0b97aaf5eba364507a33b311b367daa2a94d5ff366d3ec1c1ef72fda5b7a4273737e46d828fda7d4f7583b2945c8026804af3685f9d72103
156	1	395	\\xa4070eacec69d662f3958a6af2e8dfa456d75975bea01bb6004da4c5fa19afb349d4e8fc89188d0716a30d5d5aa885cbe560228ee3b0a02011edbaf02b1dab0f
157	1	19	\\xe807bf412b67675a797704c5bf1be677c155f2c57fd3ba15ec9c183c840d6b615ddbd6ab5e32a5d1d316f45b86c9f369e7624695fc292e0a561ff7ef6beef805
158	1	8	\\x89abbc068de8d48c683c717500f7b2d1c9d50cf05a4d34daf1a1736a6af82f172fe044455750d6d5470edf9980a5a7bc2687b4350b8e710734b409a31a4efb03
159	1	249	\\x82f6a4445c338c78c03cc8d7345e96ebd9381e3f858a90be57cd837d02e2806af83a244d8c55377dc83c5bd3a3a27e209f894244674913fe181fa1eef3aa480c
160	1	367	\\x0078c9ece6daf452e8fc6ce8aa64b1c96896b6f1531e187afb131c20974506a0d74d80a64356bf53c5fd703136b8dd1f654ce0a1aae815d7d44e61d558e0f50f
161	1	327	\\x48215cc060d23bc06069aa5c4fb67771ba9674d9f98b5ff91d0dddc00043986027f2a2aed9eabc04cefc54e8a721afdad64e4888ebb2e42665805dd2a8fef006
162	1	100	\\x518b4c6116dfa207e2a9e47d743f54cfd05f6da15314923ac60285bd4c3b826ec5761d6c8dd946b27e54f31696f6b02babe1e7934626e36bccb919f2daf23507
163	1	390	\\x0eec0e2f4b4efef26cb6ce60d8afc7e232b1d426dc1fb90197b3edd6636ad6f52216c403ba0d2adfa0cf946746504838bebbf75817c8a54b58de212b63ebcd09
164	1	355	\\x0ab2204f8e0e7a89da956beccf55858ca43967bf9750c8a81d01d7b9b9e56cd58b38658b09429bc1cbd91cabb7ae7f546e6b1158143c74af9a56020e57ac2e07
165	1	404	\\x54f79e365b2b91d6b424468d8177cc271740a9fe73a8e764d72b492604dd82e111986f174c4c00ad337198cd922e7cd60575f37f9d34820bf35b4797c913550c
166	1	160	\\xb88c3f6e5016b538dc38f94457462001b6071b75ff90008240e868c8fa8e59815792ecddd52218b707c679e43dc730b1848249213bf7c89bb8189fc3198ecb0c
167	1	224	\\x2c999179ebd86955074d25e63f8ada89647f07ba241b5b0cffdfcc3786df8a06ccbdc2d90f9bb2a3e60b5bc947dbadef0bbc9572ec7bf565d3c05ff4301d4c0c
168	1	312	\\x7ae06cb5d627adb095a1e36dcbe5b494ba2ef72231cccfcfa1ac4544cef4106f162b13943ac36fe245b5ee3c743ebcf6146f706929a70bba14299b258c87ed0d
169	1	393	\\xe4c4960d6634ec983d6ae4383f82010fd0ff3519171d91e994a2e4ddee4b9faaa1580834de4f354984353bcf047517c0fe64160c758d202180081fc60d96260c
170	1	351	\\x40dfcaec77b68f039036cb640b10c2d7187da9642673fe90a6cd9538bc3576767195d8be0fba54904bb8074417bfd6df694b7afe0cfb3656f93d8eedcea61105
171	1	159	\\x7db57be758324a0688cd56ca428eee2a7db025218341d420ee1dde6becd75c94976be98f8cb253308ed130111f945dcc366a2f950e7982837687c8028d180706
172	1	163	\\xf7d33b30fb06bee6ec29498a9ed3a431c7008f9645e61b044056651b2849d9944a6134b78cc9cfdee2bb406d00de4eb8408955a6a5784b75764ce9156b39830a
173	1	400	\\xfa9f601e4851f670bb9443ccab75330e9fc4f7f727607ad3411e2c41000c28190d755ee3061d0cf1ce05a7978694a0998b69d4e566e12d204768fabbed73c306
174	1	144	\\x873a3c6810f7b157e7a0c793e33dc7646981300f7429e7298ac148ddf4ea3cd9102cfb74839f56f155fb21a46625cb34d8bca44e21422d2b0c43df21b170ae01
175	1	51	\\x8c6f0f3bef04cdedd497949cbc86055295c59ebb450125edc4a2bb93a774fda10fad450561a46b342385450ce3a831646e3c4f13b4658ae19b4dd557219d050e
176	1	208	\\xd31ae9c0636370572af51cc3bb00f3241bc7cadee42b39986f7bfdcdd666b343498bcf05e751405fa59171943e68cd43fa1843f69a54b80d2071f9a5b3d41c08
177	1	270	\\xc75a45efc77e4c26b1761bd73ea5f64eb881f19391f314a8290efa0a036cd3b6b6b0dcda4eed33912efd25865f1a2bb3a2ce3b483d0a8906518eaf4cfba2a90d
178	1	31	\\x4003e37988569967980d8f004981f3ba0c9b86ad9865b6e206747a1ac37a15be179e08a9daf5bc15128579c301247593360e17a64882fa0bd1dc9353dd59c200
179	1	375	\\x1f0f093e0c405c439a6c51968d04d81b4fc647a179267b82420ba749f1cf628cc55b3b87152416ff7fcfc2b29a5514aa5bcdf2bf133d13bc0370b13dea20f90c
180	1	333	\\xb85f95b8a2e86428dff57a349753baef98a35a317f60ce31d697b46cc7057d2d3ff76fb5a3dc61d3fed47932af13028da71752957bc6b73e740f66d70a015103
181	1	80	\\x1b1524e566567fb08615e5784ab9747b625a0d8d2bad69e795e882588986ae295bcc987f736f440c390b35b5a398611a419c670981951b7eba8866a5bf63d50b
182	1	178	\\xf3f99cfe5954c5e079eb2b54ece0fab0e62968286494071e59c22f88fc223a10d7aad9c958b6adbec3e5d0599e901073be0351b2bb502c88e9024523b08b6500
183	1	29	\\x402ed1ea355f1eff49ab0dd195062ece33afe6db4fc214c29fcd50dc57b5c976def8a3058fbfc7e27c1dae50d277f21603ea002d6e8075a9ec7ac8fa661c7e0a
184	1	256	\\x41ee128c08ac1c5eca84267cbc23c32c805a176b88f2c10cb8b6e640d20abdd545eac5397218f56a74fa8d51fc450ede89975e2f381311245e3f8943c62aa108
185	1	366	\\x08cebe60d8b285c8dc596f75b63b28bdc9789c1a490f4211b98fc173a7eefc6f5de6fd46a24e5ea0a8df4672d46a7d5852b610cbb180fb5911de266bcb0f2e0d
186	1	171	\\x5e7b924451a6e1ef1b34495c1821de9e5728e59e4535fe7623f35406c9110ce622de620fd597629530b51bb8edaa61f4eea181644093ae8e8361d232b8cb5402
187	1	379	\\xf5e8dfa18d7fc9aa9e6b287bfbc035518882534b4b2f33d4c242b2fca384450e9432d73de4b567b912a41eabb6e71903139c09d38c5bf59d3b78f164f107ab07
188	1	260	\\x63e59ad93e5f075adea69a4a3a4feba250d248fc190d7be363b39be1544502d99d13228f83b0ad870a57704427281a9eac8d48a2537b2e065370b1fc001bfb0a
189	1	218	\\x5514ea942ed67fb5d16fa67e3c0652aac1452c37b481ea1b83c608d9c61cf1ef7f82fe26b622af08d547526b85597916d382efab0f84df7d43afb8cf55e5ee00
190	1	318	\\x16f4a2fd986deda641938cd967a45610b7cc12837616c19da31a970f467b0ff54cdc125f438d19f6af3cdf3d2971adde06e6de7510dcd0f0e9c5f4ce8eef4306
191	1	141	\\x77a84e28ed5dade1b60be6eeb936fb99756d7d27ef075762dcc9ad202fb66419c60387f28035d3200aa74680b8ff2acac238de1d90d0bcb18ada8307d6ec9306
192	1	91	\\xd5dcc9142a4131dce7d10ab5aa4e5c8be3da491f2c22cac3cb5d76d3c3d2b768f47f529a6971a5ea39d0f430f5b7bfbb15081bbbe9223a19ddc4741d395f220c
193	1	414	\\xf0b066dd8fb7721bdec42cebbe5ef4898811e53f8f9cbf69cbefb84f0bb0c1b4adc865f5c16b5e234aac0eb3d4940d0db485c9b6f4d5be0e049f6ed3eaaa5b06
194	1	309	\\x9aa0cf1fedb89ab157a6fe8eef7efb186f1faa9f8ff162a4f5a93e5bdc630b89da82c64de903e2b5157b2937fe001a72529cb50dbfe70f0343c4f71cb603170e
195	1	167	\\x823be03fef057e538d3c7956c32f2f328d35d4e3b26baa718f058e6e4050192b7c296fd43607c1c677cb41a51a7ad28e3b4e0c93753a67dbb1f9d35f73414b04
196	1	245	\\x08222db40ad29cae04e03f5e94212c1f9640aec534a09881ba88311ccdde607cad39aea65e104b0f4ec5bdc10c3f82eddb74077f0af2132ba86217b790235409
197	1	201	\\x2e35d4bccb44914d00f32ba7610fed39510a710f5dac5d25aa2ece7a80388b9d779bb85e05c0673c2029816af5f476498f8c5ec784a1ba1bd571a3ab8a7eef08
198	1	120	\\x226c6ab46e90404eed990276dafcb1920730b3626c4c839b08ce998322138591f5ece8561faed1e1a79d094e3ba52b2807b5e7bff5c576784d80020081495300
199	1	185	\\xafe1e30907d322c4cdd6ac55129f5085de23271eb4751d967486fcef9f378e7f8cd6769ab170f15637ee08dbac138ec49d29826755beb7216a7242cb3b1b360c
200	1	310	\\x493b9ac02264f3ce6f10fa4f3cb88f41dc4548119346fd5d2b9a3788cda76cc327abc7d44756836cd9ae5dd67a7feb03d1e9d125c0b648fddd7a330221c45e05
201	1	298	\\x68dbdd0104068d417d55cb1e22ee799c29951526609826be49ed2b82e83e99d616c1acb7f9bc5eaea88f7ce4506a7b18f53d943efa3710a735a3c00e2c5c1f00
202	1	21	\\x8fe5ee0eb549ec2e103940d7726259031b220a4fc5071960a8718bc0d0977d0c324e7bcc144ff96e9a5aa6b6033b54cc72690e0153256d70f31d8abff1849609
203	1	190	\\x3512489b3f170f95017049737d22acfa7f948e2623f857683db2e3b07345db8d8502ee183f7263c704b5e5ea56a3e939ee531f743ed8d54aed34c25594026000
204	1	223	\\xe8e61420c68e1621f6ec7cd8e38ade0c3022bc4b1dc6e75b3cf8e92a5ccf4a81a2db4af9c0f16c9f47e2a813a51f947ad3f4bdca5341b5ea7b0508263bc9a20e
205	1	301	\\x41e365c9f0a6bf7065798f1d6df6d797ca939985e7a30f34866c11cf52182ca3358b9e1b97dbb1a7d9564130a45067e55f45e27837aa2234baa9b131f9f71f0f
206	1	258	\\xb09567f79cfe9d50e581c1821d687a02bead2a722066db922411deed4eb5bcb892fbb4ca97f9f15ddad91580ce39c8bf4423350b693c7241d3c625f658bcd906
207	1	61	\\x901fceb928b03a020681a57765284d67912bfd886b6e15064c839fef61b543ab7dd40b98a5a712e5e3e1b2a44f24abc826ccd6d9402db5a826f3bc812fe7bf0c
208	1	12	\\xad81dcbc0522c6b7499a208276a7f27f15b412f62b15a27b9326a1e405c713a4df85da286e15a7ac33b0b5aff9d86965c56ccae59f4798a697d43a14a854bf03
209	1	321	\\x83ac3682f157146eb3e84e4634fdee179588f085d2dfe02334c96fcb39eee98409c06ddceb0b57fff31fc1fd4b32adf6242bb2bbefd29d88dbf0de0b4976cd04
210	1	320	\\x82f2d8d3bd25bd0a989c76256ee52425e6431bcefa2f6d2fe0dc4f126b3821f0e6598a67ee568616081a26a2d39e29f4432dcdece5bc9044d2777a9c90346e09
211	1	358	\\x3d8e6834d8230bace868dad2fa426fbc642fdeabb8898f426e5b0ca14596bfa8b0f6ab94c5a00858acbbdb7a2c9d872879c42cdc72deeb3a881dc30b15f67306
212	1	180	\\x9ae118609eaaa60651ca9c7382dde6e002b0c81c990290b7e07307efdb742a98b9cc64accb7559691a219fa41d44e5abaf4bbd89cf9b840aa77d832fc9ef760b
213	1	183	\\x2f2523846cae1ef4acc77bb66cb64ac6bcc967b42824b5b8d2456a18de52c45657cf070b866e876ad0f49428f52d0580b0d8be29383672c6ecf5649ca7768a0d
214	1	294	\\x5f22a56b63f31d401f07a096d480444d436f49c904c09eb57ca0d1a8429bb0d6685a043dd6eb1829ec08cfb055edfdfc5f74201fbcbe1e31b5df9ade7cb59600
215	1	415	\\xb72b96166f9da9fde1dc43d342572da953f0be0dd0f366be0dd5b27bf94bc256b75c56a4610862b45bda84ebb58cbefdb2c745e97d131856b628aefbc656f304
216	1	402	\\xee29a3c5f77f76dac390d60fd88b23ffbbc4ce5aed807d7dd856c27f9622a0326c5aff56cd997d1d96cd0e276825dd662f676d29b2e19eee3a8b3006e2b9b704
217	1	39	\\xd419acc8f0c030c331aed3d52855f0ebe0b7306154598d0ea2f2327bedb777b227971af831d481ea2d4bc132ee54879a0f21d02e3ef6e4ab59b4460268adc909
218	1	346	\\x49b548323bd22323176207a5f2561a256b6e84b79ce1755ac787073b12f679d35a04acca336f2dd5b879641004accb65d9f4f3f3f91f4d957c6863041d44ea00
219	1	254	\\xc415a4c82d0f9cb588f3839265eb7664359da16246f41554c7e3a44610240286226eb95796f93cb9917c401a31f19a3fcb6f827c293392a6733f354152320d0a
220	1	361	\\x5ed5140480c9ab8e48884bc77a28c957ff8537e5406a8f168039fbf49d112a0d7d7c0d08fafa34cce66c3f3e5ba91d4903a2d34fff5209558ce89f7ea528c207
221	1	142	\\x98a9b771379b2958d78935837dc9e9e504c032b851206a392d48ba2993bd9a705658a9fe435dfb60b17786f73b4f9c29780da95ba0fb0698d8446674629e0c0f
222	1	271	\\x10b8d28812f4080aa227c8400a1e23481e7db03a26f47164a3c61e2ba903cba3b52076caf2fa256eaa609b9f92c5301a6e063878d338d4bba5584bcf437d7307
223	1	385	\\x998ef7c062a7898f2417185de6a5f195939a68148eee7d61e953ca903d52ab6e2efd3272dc15aa01c44a078f4eee2b73af633b043954d99a85c88e9805cfb809
224	1	362	\\xe8097e56cfc0fcf962cb789d8e78d3992b899587acf7b2cae0aec28ea304f6a6ae562eab94efe7999a7b2bf6a671199457adbc27544ebe41b475733424356204
225	1	72	\\xa1d119cc23815272b91f7500df1bdfabc246fa5f9d1de608750ba4029f44467d9997053ef5b14eb1dee6848c255927361d60c496d762bbbf4deb7b23a6bd9605
226	1	55	\\x5d7ebd381c59038663669f0a221f688d43e2bf53e9cc2faa0fffe7b4fa85be3731507e3477715d3caba62e3d1592e2cc5c287fd62917c16e2399342d34489f05
227	1	155	\\x8530f9727390decf8cbccac048abf92b2c01223a2d2d6ffe9ce87c799078eab74844fba82b2a13bc8440232da3d3f5255f3c24387e289b935920e5ab5371c10b
228	1	203	\\x0618024dcc173ce04645ab0ac0285e554737ec4dc6cf3cebf69eca01acb9ef75b0b44ed262dde8b32b95f464c509865a174c9e6f55314b9c4e93e47cd962bd09
229	1	137	\\xedc366104e22475810656e556b8c79824cd84840df9396bdd8115d286f45d7f7827658628a33682879d64c45dbd03ed95a7e24b38f83a030221b367674caa50c
230	1	210	\\xe13914f633f4c6171c6d7278f453a846156c2603060a1804aaed226f32b3f5a8bb6db1463761bfd1694bb0d5de399c3a2b4298d17f6225991652e72581e62204
231	1	263	\\x4e29736080784d72c437286cc8ca15f51ed437905c753e2e8ae9627a3dc5ff4a8df037f7dfed21dcc140dc483866fdc44785c28c9b015f887cddf304074e3605
232	1	350	\\xf6b8db6e9dbfa194e1db270208bfe3ee5d4834cd79bb241fbc543e441cbc6190387c33ff8ee38cfc49ef82617bc7f8e5574df91943f962b7fe9a5bb88c186903
233	1	30	\\x12f76456e4c3555d8d314f73e6011e42c612b190babe794cf67be905e63c972075ab4d56089ef3623fc146e019f3424d7f7890c555e89b231372691c47ae2b04
234	1	53	\\x5eb9161fc8234cb69aebf067a3ee1902d86e7da58cf5e5fd130b4ab322096c20d9e4539a79643d6c46473dffee233d02f1b97062f92cac74fff589dd4a4a4800
235	1	316	\\x7ccc9bcacbf4004be8fd04edb7f08c5607902d495d93b774be58886f3d88603de85b719d9e0e2c13d9a66e211b3adb207ebe820e767a3486e0b6e7b1c9cf7f07
236	1	364	\\x4735a5b5fdf3dead9e39148931dd45f71bd3ba6efa6d344fb70c98d7b72ea6ab1c7920900bf50ce8c7a6e39a1b4a4fd599d9dd34451839fe0a81b9d3584d5e0e
237	1	172	\\x82eeb05ff9b91430f902a48607cb45cf13c5eb185af2a515ba109be629f70ec173931ac1f42ba3f0309439795893a0d753a1a272545099585b7c1215f00ad60f
238	1	242	\\xf46998e5a0a60018d24531872603cae16cb10a0b474bae848c31ca58694f3aca5512e425c608a8f0cdfc61c4312989970393393038b5006b6daaa2919a628b0f
239	1	304	\\x4e19c26e96b668569a8eb01a324b7124a6b18dfc418082db218d8e80b8f1dd7defb9cbe52155c54f82dfe00acf6f2c026f01e4d5f446930d378a401881756504
240	1	71	\\x87aab4e8b39951663e8906a15d15c386a972642a6eeed368e289ece17f5b7f1525dcc8061719772068514eeaadd33ab0a396421b1fdabfc9d94c536f86f97706
241	1	4	\\x217577092796f87dbc78cc12e664651bad2e5b81b5684c20a39af7e32e65d951734b6d1e617c23d0530c631721478a1b2a7a8fb38ddcf70440c3a1e768b0850b
242	1	273	\\x81744e68ed32ed0d693e45b05fac3c4f1b9da33e779eb949b3d95b96d97dcef7f8320d50872900f46c53894f1ec64870cf559c7bf6d6c2bf05aef5359463a30f
243	1	255	\\x4c54dc64eeead88e37169a114be8e7d59bf50979eff45bc1bb6414855df22f03d527cd9ab59d869dfeb081cbd961ec7814a66b493379aca484b0dcf5a2a85d02
244	1	205	\\xeb90f56fd7313a23ab795f2f79217ce99cf5898149929ebf69fc0d61ebbb302b2ec97ad13d964c8bb290f0471c22563d9cea61005c29704d780afb8b7f4bb40d
245	1	232	\\x1636fb968aad80d83f9efc17be8058296cc4a807e0a57e8612a519f927c599b4ec0177c487afb440a14c30c46ca022a9726d026ea3ac50f96fda5ce55306070f
246	1	381	\\xd3f60a4743f8793b26c80e93ab75f1d1d1b9816aece6113bb5de2e618dbeb9346cee1aed07f3f293061f1f4ac5b8941d55e5df34d213e01e5522fa2e912cfd0b
247	1	405	\\x5b1269ce57c4b172edd2fc1e11421418aadd8457b5b059b7aa1c16f211703555066035e8a433beeb0e448bf70de76c9a0a7a45b3f6af5ced7eb1da47a7e46f08
248	1	253	\\x21a2708c27d2b79376bff38c674f0daa4dde31a46c28b219339f99cc556a5275536f7c15c5df42bfd438e79bc9eb023f6b2c15e375e7bd0d6d23887e6444110d
249	1	277	\\xcf90a1270ec037dee1ea716cb539696b5540fd275a97b89eac5b04f2655080f5501943b56b6929205b9816104957382b2f66e30d9d4b6985fbb924e885b1a00a
250	1	335	\\x0cf5cfd532ff32fa2a68e83fcf7641384db3a930bf7948a3727e10a04e36d73ee315fef3b1bc1a89ae1a6b6b8cf2703f82d54472b97b1aee25c495529b331102
251	1	22	\\x04ef92be480d2b4a28a91a54947c978773a8dd905876089d7d37719a543a9c7008ffbe2f7311c884687c1dda0bc0a34ca27887e8d14751aafd713cb2fb8c840f
252	1	15	\\x99ae3a973789b83ac935c3745ce3dd0efd4bb7ced5b74a135eae865ea7182178065a51d97e863eaa866c15ba29c3ec403f2047624ae55b2ce5a924f2b32c920b
253	1	356	\\xbce4dcda3b971adb655ce8a83e78e06fa2298ae86a250e90d45402b1461749f009e6ab3f1364b0ae52e2ffe7e1e35cad59abfc358de2343d74fa753feafa530e
254	1	18	\\xd008c9837bfe55cc144e0bd0a3fc0ff56aef88fce18e1d18c52de37535ecce4eb19fb6ec8108f6f03106ed8c45588901fec7acccd349276c0ef140e08b0eff04
255	1	344	\\x8c29ac8cb2c6477cf4f16a5c70987dddd8e75cb60f3d0544d89664ec34728f5e9b749956e4a80a950ab827b7279ff52a10098c6c618c68c78653c9720958db08
256	1	411	\\x01cb762e019ef2097a430401f0af759d3a865fc31ac373f587932ee080e271d15656ab845964c724d266a1c4d0bac3bbfb2d8af3aae2ecf21710780fbf4ea601
257	1	213	\\xc35344cfe2b3eab3fd56317ad1d74cd563eabce7c81b36a887e8070a6749c89284c07d05d480ed4096111953e6d1b2b6a32622e71b4d4bc3554d7c079d2a3309
258	1	302	\\xcd22da34b8b7141b134b61b1c9008c7fd9cdf255419b1fdd875d929f465aed6c1aaa095c3a9c414f66c1b7205442e34794fa768797b119d4b6a4d9d64ddf7c09
259	1	156	\\xb1fdb44ffdd03118e5968e649e8f15583f7738765c0e64004fa6ed098d4d468da6dfc555205a77595c17828b4aa7276e15d5bdac3c9474f80217364886fa570f
260	1	60	\\x4ab3696ec69d59c8c6f6c3ed9e73c39779598e4929eeab5219f1f81f3f2d6c1fb10efa8790e1d2157aec384ccfe29ad08d9be2aaa870f3336e222efef2f5bb04
261	1	374	\\x5db39b28582058165897f9ceed1de603ee3c23c7a8509980c5c451380d985a192327ef9e67283e9fb00ff265e6a50307eaeb5b61f92b59998150b56addb1480a
262	1	227	\\xafc0039cd4b4ba14e476e24204412cbda72b8e40e4a4b17dd2a299524ba687ad80ce17e376b0fbc0918e17ce6c9ca6788f87acf55def5cd50aa5dd8bcbe4ff02
263	1	145	\\x626c49e3357a5dd5f75e578c130989a749a65777555a095bc15fc12d822528380bc59c23b00c391137c4e8aa632e2e4e2042739ec98d7e80965ee335526c320b
264	1	174	\\xdcd69a051704fcb697cf0666601d6ea0e6df7fcaf32eafdcf9b256b5bcd78b722f5a879eea146cc2fb5cebc9b618cb90f08ae4820219ff6bffa6ee6f400f230b
265	1	62	\\xd8017d3fbae16e1d048f405d998c7b4dd5a4f35b1c988e54e44d6d16d02d8158d5cf39d94d58328812d84426364d627d9b21b1f943f5ab5390be3d7ac8b1af0b
266	1	384	\\x1f0a8a7111452fbcc6cf479250e471f6e2757f5b6377331f3f4b5cccb91c5c90cb4107b4fbf598f01114f2c912d77a6a70b16192c076d6f7811c575ec2779701
267	1	286	\\xf7978f822b797d5f1b552a62b4732f4bf1662fcc613b3c4180b6d4a7780e4534486d8408be4e0a12c66e8efc5ea7e8e0b9a23d02abf68ddac875ccab135efe06
268	1	237	\\xc87b9fba49584a277b171347655128bf00cdf2e26889a4ef7bc4355510ccdbb403ecde546666e6300b908b453e208d47040449a7a8ccc81041fd401d09f05e06
269	1	65	\\xa1ad10dbc58db7c4f6156bf13fbba34721116e0dda74c904628b7317601c548f0617c18a66535cc9b142c264ef74f62dfba5531d558c100acfb6ed52e4fdd202
270	1	102	\\x736107bf54b38c42d900833a91a099132c9bba0d8f2678c7e9276ed81ad2ec05fbef85978d8da383d71340f95f3d6b9dd86e44332d38bd84bec41ac3e681c80f
271	1	57	\\xb49f7dc17f2dc93f583b4afb34ed04a2b0cdb834d18e91283893280238900e5aa1b59d5f1881499d4207a766bc596be3b0230431f7c472c7453192bdcd0b090b
272	1	132	\\x98d876b065de01c0ec3c6669bf68bf7f1e9d59ece8aa39c3264a65e128f1a7f417c0ef69b9d2111b3a1c74d73d5d93aac0b6d81de4fcb6c0dd8a45f76b91f604
273	1	300	\\xf224f19827ee618c9fcf7fc90894a4cffad3c1a6655d2953dd024d0b2e01a23f1e5e38b34f52225c337ff58260fa9fdb987683b692e219c67185b4b6cb513008
274	1	143	\\x77ae9800f0c54be96c9db52758391c19c6ffec49aaea3351b0683c630f3670a91590dedf1839e39788b6d092390ffe0f7771dc0cb978783504019521714db10a
275	1	88	\\xb22ba4dfef696264d4e233b4b79fa5115d7698de6eda351e0037c40d82e04bedad658b8f6a9334a37ba693dcf03681e4313a44edbd4db541005fe8115507040d
276	1	149	\\x6995d06ef4b86cc568689c72afe535e52fa47180e909799a51025d897af26a4e25f93d9a254de848bfe2f454887969ccf3d49cf9c402f6c92955ba23b7fa5709
277	1	148	\\x276f8cbc47961de0147da24ea18e2e02f7b82b77071569f6e9c1e50ea1ddb789089c4fa4884420eff7621045a7981578f6dce0f81222dcf21e4319d0e5ff540a
278	1	121	\\x3923c53aa139c020bffcc2bfad3f69b482e73bc9ce8e182fee82adbf796036b8a4b13e598c27a75178de6cd40c2afbbe9a68d60acdb70c4a559db976cc155a06
279	1	3	\\x9133bc1ee1d7e414a6e4c70ff2bb884a130dca95907c8dd3c3ddc2edf6ec260b344823534acee41c1c987b8eb701ef5ba032367858efa2bdfb01e5a554589d07
280	1	111	\\x0ffcc75149f8bda32d03d23367a4a829654416e1c36f75c04ad0ebde93a2d686d4b43536f0bcadaa162943acd3f6c313392a9ea0d74cfd06714cbd561f84a501
281	1	186	\\xeeb940c867c2729e0ae8f47ea27a489db4cc7d2322a5cc8067419909ad564eda366761ae6d3b49f4a98d1af2767c27fef7077d796e45c2b608eb1e1a9c087404
282	1	248	\\x7b326228141c534b4590103b9a8109e1df5deaf58eac1e33dab08bee67dd5a9ec9c65081f75731ecbcf7402eff06092557f2f76ba7e2125406b5f62f9fcd700e
283	1	265	\\x2dcbd71972b4c59152316308630a67d7b7c56890546060e1fb4ed3dcd2f8acf29960a1f895065902cc0f500aecf81fafec80fe682b585e4f29c1df7aaed32802
284	1	179	\\x83b283eb02ae4f2ed97defe67398774e1b2bf2b2bdd47afccb9781d88941229b5c6fa58a25bcc326a24eecfd0eb88044584c5a8c6e6944e89647ad3cc5161f0c
285	1	153	\\x66fa22905d182b04c66574e402064761b33ee7dc0c6e84b043f92dcfd120805e957cd3650fa57bd930dea1c1875041e3be0440fdbd0908d80b5e16b4780e950e
286	1	82	\\x5f9cc2d2fd636ed853d557b3baf099c6629b226ef78c4f239b4ed12537833e94d21c655a18f0f383e644f212bff3debbea013adac2d69b8806dbd5caeccaef0c
287	1	259	\\x9a9b1c46e152986d1a2e4e2c01de4e61f12e73c712ab3c4e0f3cb439313fa269081e6d8694666b4c90a07ff5a5918131eccd6f01e0186a1ea28d4813e6de2609
288	1	225	\\x040ab600986927b86e308071dc1c143018f0bc3e43f9f2890987db2a5f0b13349a1931272182f7456ae0a209dfbd397b1a7da5535a55d67fd82d23f6f3ad0d04
289	1	199	\\xd18f190bd7be09baad772f91adf9e0902d726a3806f5bce15eed7e6460e2cabbddd80d7989f67db98b72bf362b292d868fb55ca096caae2e5c47b0bfebb4f301
290	1	410	\\x621cf82b9efd19e09842e249bddd94ed9cf05a4879ef9074b225fd480dca6cce05f34ae5a102d1702e1f334e09c19ee1f5e92ac72736391107b0c5a02f335101
291	1	324	\\x5764e9c927fb7fea9b933d694db67e5d4101b6970737bd0dabd39e76b5c621d78e7739ae7e74cd998f14fc6efe4308077fd88659d73018c90e7bf70a921e8f06
292	1	94	\\x14838003667ba165b5fe003e37e0eb3f7f0806411f7e47ed0f00a840cdd44fecaec3cdad881fc35116fcacedbfef100496f121b2077ff474ae54065ee3260207
293	1	184	\\xbfa6a3ae31bfd3b691dc0f2cb5274cda3b7af130a4f4ad686a7d53ba7875a734da0c14d33e984d1c10c4fb2c9e1c6ca0148cde6f495a10e0e3e1fb37cbe95707
294	1	168	\\xf27092c125884df1cacb5744c9dd0749613474bd641bfe43526ecca6ad8e8eab49ef1786b83b6836f2ab47f943572fe8ba33f14905bd1e1456721b17b5e9c608
295	1	353	\\x635aeca0982407508f9ecbe3bf608fb04d04e23db5b1a8a5c7ad853c2fd2af0120c82b6cb9630c28934f5e316e8ceef0aa4fe02beeb7a5725484cd8368f6d10f
296	1	289	\\xd53788c28897281889be50f0f1d8ffcffb467fef6252366e8a1a3f79711fd2ce207918e0838a2765d273ea448760229e17bef59cb05e80ef2a29779428d4e901
297	1	342	\\xfb381ecd458fbda39f30ba3cf8865402eda6ceb3349781dbf26e195ef200fe7ffe9ecb5fb08f541276fc6826a5cdb9fc82cb7af6988280aa05cc87a8cf1d910e
298	1	281	\\xaed7603770af79abdca470fbd12a23e201e09b752ea49537a2f839d359b594a8963d3d71955fb35d3dc024f7abdbd64c82ac9642eb751675983845a2e0959b0f
299	1	40	\\x523c4fe8ab91e40368d1557245296c11bb714a6f2d3bb77fefca43e95b9abdd81be994a2cc940407fbe34ef42baab877e9ebc3d2e469102615c877453ae3870a
300	1	230	\\x15c666318a999da5fa0e6f6233a763a8910e8dc1f2952756e9700c0c74f43522cfd965f946b14178e1834fe41f322b79679a4ce5abf94eea210123703cbc3b06
301	1	235	\\xbc8a9d70ffad6cc98ac44c158f8ac314b9e008045509ccb94daf95368d6e0bde9f900cce5e6d44cf5cd22ec01ed16e160d0d8104c7fbb8c700dca4f90f5c6708
302	1	45	\\x3a81b2f406e3bf1592ce954e30ff6e6b3261b0104c552e6fa925baa6eb038ea508e6e526b5ab0304c02a0fe281e5dd5a1df30da8542c2839a213a3704932400d
303	1	269	\\xeb0679e26b9bd4bef6f1bdfd140999b8084ee73962d7a884e5aebe28dde7b6f7ea66f118ef07280afed2925506810f13da253f36ccf14bf9687088d4f261210e
304	1	33	\\xceb3777562218f3e346218858eab47e13ff36491e60ae757cd0de3664b1309f0b78b34d12c92ab2aa14318c49eead808e62a8e91bdddda4e8c3c83d9ec73f901
305	1	319	\\x076690db47ee9eef990a6f5c4f714de0c8e0f1d594a1e419cbc0e5149a359cd635cf72b18d6e018f3a1c65e369466c0e3c3b9001d95230a2f4d8233ae7bc0501
306	1	236	\\xf2afc8cde89bdf141fb6648fc4d50f2c8d4243c5c9d9129c96127f872f0f518fe949d2391c670810abc4dd663dc21ddb88a704611e33f81cc841bb3b1386ad06
307	1	110	\\x044cf2301a99ba29dc39278c6b9590596becabb690adfe68abab9133aee4bce88dee156a1c5a6b3b3d956e588b482937a262158842de0e5a5076a1d673ef960a
308	1	325	\\xbde0b65008a2dc369d34dec573c959811c5ad640cab09fd5be9dafcdbd7932aacfeb28a62c47746e3f96beefc02dcf378556e314bb240c9bbf2de2b615bde501
309	1	394	\\x483d46af004811b7606666003a51645d9ff820705cb458bdf6a50d8b599a678456f6409ea401574fb290ac311b815f5fa143b7f453b831dc6ae8004b50c8590f
310	1	164	\\xd936fb839f334428989d268cc560e247faa63c36cab31887a28c307b7aa6b6161b310b146c45c46ad9e33b95b66070d9d61d5ff57ceaac7cb3cd93b7139ff609
311	1	103	\\x7bdb14e06501bb266f0297f68011a9688e9a50056a2f4b1248a6c1c7f2885acc50e433cf2ccc3cfe7dd658a1d85a0310ece37710d4c646bb46e9e4317b7afe0a
312	1	17	\\x2806fd6e3f23fa3afa14b727b24eba5891a30e03273a19017168d189cfb15101cfea141a08444235b6d0792394b032037bae6930bf71fdb37d96f1f83bd25e01
313	1	267	\\x79c68ba06f0ea50d46669cb92e2c80a0f9f23a1389f12d2f598514b94d6d755b8506701b5651d161e477713036244d1869245ec1f893b2168e8172cb1070520d
314	1	251	\\x5a2c728b49e95fc0a5f27211865e6527a6cbdb593f6a03e44b4b8b3dba94b67d7bb54259e9bcaba2e9f41752a7594ee1502efb88733e08f517ae9dea35f7fc06
315	1	204	\\xce227efd9ef82676c12ad89bb8eecdeff355dad6b276856b530ebb67231f8358168c4b3eacb3ed6caa8601c72b86d4c4aadd1a9caa45d43981c676cf57ac9a05
316	1	290	\\x8e5892371f104fb40b14e57690b63cc2f236da069ab270db83ae243902d8a7d4bd704f31c726c3efaa020961d550045547df8a4b791f111223ca43429a6d1406
317	1	117	\\x8e466e1d08b4f4a77e85380b697a4c9be2f836119dd4f3d8bc4158d549297d789f11fb166bce31d04cb09f4902798e599da2c38eeaf05dccdfd104797efbba07
318	1	244	\\x79995a82877963e5fb3b19ba3664108584c66983e8637478c4daf21e8b9ec514aa42323da3dd7b686586bcfa5eb6463c90edcd45ad99e4f17affb207d7fc1401
319	1	323	\\x930f7df82f1b8be1bc24390f4d2dc6df7f359556ef67fd68191ae36005f483f4b955463688846aae88a76de8f1e15ace037540f96cdc60b23f67ee15892cb505
320	1	420	\\xd0147cbcda1048315abf05a07295c420e541220270fe928088aa9bdd5ccc00c50e6f740a22d2bbc540114f77dba7615028fe80cf8fb0d7e43ed40e507d48f307
321	1	56	\\xd8b063e379d9f01cb4e9c9fdb173f16d5c9245aafc4f742ae795a4b7e7a37c9cdb51ff6405ede5fcc4dbc6091758b678f8dde1b0bc303382bf68c848db685e0e
322	1	212	\\xa73ed6d8e46434217e134763426254666c92693a34e3036cb9937408e6d54755333fe65ceb0a1477499b5c312f524d9b8de2680157237e2cf068715a178af404
323	1	196	\\x7b0cbc6c2cb849162add8f8d1b9a26979dbc45b8fb4dc26b308170caea3ebb7d53cdd9d13133abc155fe8d324ae9e6bd479454647feaaf0f1ec96439c62c1703
324	1	197	\\x7dd71833b71009e8da95aff30678f9acc0b45cb0d483bdf728d42fc494389da6be74baefc688007985e0d383a1705500be6dd3bffe4c2927fd433ba18fd66201
325	1	403	\\x65401152e9617622780910f96e5ad30c22bfdace779e555f6db9c2b4741e9266491c6c1379aaa019fb2378287728388f7d20eb3c100e5c902aecaca24001a306
326	1	84	\\x55b9734f224e3eadb0718c13553a9f1d8e2b4cd6860669c17c75f6b427e6e80a4e521ae4a9b84b84399c9a6820c3e2d129b35b08c4170922b62f67e8f95df206
327	1	119	\\x84b427b648a88ff26efd53398712e0ff59300b7c5594e5c51e45f46dba5ff693ea6fa1cd5f58aa6b80b4ae6af124e3832e8ee77fec668fcd982a58ddab29220f
328	1	2	\\x8c5f1325831a7a2afee2ab68da7eec9ac2c254e3d84bd54e53e2092dba57222481df412c7e35075685fa38494d7f68f457f86c98b452837ed54354a41be6b909
329	1	370	\\x3c57b7ad85a843165c2fd46f8b495db37285255531c9e26c1267ca30458f922a197a92623f09fc08b3f5affb6b1d741598675fa7f749dfff59f5e5367e14d705
330	1	10	\\x26c763dc5bc6e45ff70ea9feff11a27bc9315da959b3eef623f4607fca59b4b6f49ab8ffcbecd9ed81bf086918123c5827182b99a1e85878a960e7d246cee10d
331	1	396	\\x0d9c6eeacfcfe8c93955b1d6c18f622b3e4a01de5bf522a7b47b818dbc0cc79c3c4ef8dfb744af4bd7b56c26c14b8a5a8324d77fc3b540d64d4e26f10392ba0d
332	1	176	\\x17dacc4c7e77dca80d09fb671db612ccbb2471cc5f4ada805dd2965e4a023b141787fb4356b635d405d20fb4ca04235b08983768c96276f0037ec2db327df206
333	1	42	\\xae4dc3b2e50db6099b229a55aba3bbd6d7765b5c37abe95f3857c7bddb01650e8d3c724f45dce35d2f9197ec7df18220563fa592c64289aa69fb8099a83fb40a
334	1	97	\\x4b740ec41aa6b412724a191f57db3a64b92e6e7618eddc1a2fd0a4deecd3dd27d92640179b9ebdcc36ac17a97385a9f56bc075ef94b56f481453d882f4da380a
335	1	146	\\xba0a6c17108a0f196df7f3150b520c385274b4b6a1ec926c9132a78acf8f057f58c397b045b8ecd1a5dda96072af96dac208220b7b83a3c76524742dac8cb90d
336	1	154	\\xfd76139a432841e2b95e662bace49859b11627de92675910993e5554d6fb0bc52d959e61b21d4951dc9214b162a3120263906d0ce5f5f3d0b6a2e3bbc1132802
337	1	165	\\xe4ba354843b4b125941dc64c23c67c129e4413424b4781b1527af25b9c377cad5efed1bba0c84b5041992faf5caa7236f41f62f218ca4bed5319c92f82a61404
338	1	343	\\xcbd11c4b49536773aa84266bd8a559e1f32c73e1792d6df402f48683ad50931f0b997031da682737129fec254f275a39de11c985f04c8adfec2fdb65dc295d0e
339	1	229	\\x23bb18fcae15abf477272a0fec76c56850e471a1cfcdaebd416de3c2e3eb1a932b70067178aedf294899bde9f9226094726879766eecee7fa1ceb5955c94330e
340	1	37	\\xf1763e197d287a3933c7b3cb82c8cc4d5104875575cb86adf1a7dac23255fc696a0991deffa1f38f6f8edfff52646602cadfb5cda7730f9be7a97633a3f81504
341	1	32	\\x52b0bec30633d1bcb522448e29f2b3aeb24937937b36eb0f485c3fe6438d26a977fe73b2060d9a8b8b647ad912c4fa1694ddb8b187e9e9dc9d70cbbc7bc56b04
342	1	369	\\xf58b4c3e15be50cbe0747a2c747afb0bbf7e749c107d22dbd9ac3ac1d2aa94c8e8443fd3d88da35253034f493c132a43e0e76cca9b8fdde476257fc90ccdea0f
343	1	376	\\x9c0dad46a8605e2d8305836675c94824344b8c53d6bfe1e0eead2517b4045387761eb1791c4ee96ba9be9ce02c5735c730015d2777dd68b9440c2002eda8aa07
344	1	252	\\x6c2d825f351371c179c6554838646c44f8342096b4df73a65478ddaf771ba61d29f54053e87875396787acc6559697836298746f9f2d0f825aacb740c1757404
345	1	83	\\x7b793d34b1edb7041fa22f470650dde0166afad873220a875c3586d6c6b4e840021354712181f78091279cbb8a9e8e53c726fa7f81b7f78a97c54d361350c709
346	1	70	\\x4ee8edb67e81636e74cbe78577410b8fe25a5d112bddb81c8a8f2eaf29b1ffb407a5f33966074281fc66b35e5d3e552f905a21d4cab77c4a5c40cd918bd4f203
347	1	383	\\x5017798c4a2a02b761c397d34723b56c6b959741f2cde8aa9576e25aafaa5543451503c56e3cacd3004d9c5021ff519616549cd7770e4ba9f24293987356aa0c
348	1	220	\\x5472d6329aefddd476e2e74991458394a1786f7f56012d5647baaf544d71707b9087ec6457854fdb280477793baf705e5055e484f72187cd2f28588b52b0b308
349	1	234	\\x319aa5126fbac1be520820bc2cd425c64ffc0dcd75bb6fba827b87c799a094be94bc60794e648b63af7ef7b0d0bbd3728c05c35c6bbf5f512a545fc37f206304
350	1	85	\\xf67b6da3662ffa521542e7e2f4bcb174cd4088f4a4f3485f69bb3ce4395d65d67ab0938644a573f5751f22590a0530323df440a72a313f977f3ce7d0835f1f0b
351	1	360	\\xcc3214c7c348444b4224521848ff43e12be81dc3b2d421e7d556c4dc6cfa6495228382e226329910c6d4732236ec48cf89892aebc40181f94a1c9b6140e73c08
352	1	239	\\x2ab2899cc21a73e00ad6a78604b4210ab9970e1e2d0c7134ae001c6c964c99ef739f133922cfc851457bd3d9686558a94ced99818bbf2a80bf5261f15202c208
353	1	247	\\x4c5cac965e9ad00061847ab09534e972e75070714c886e15e8bbe0c1eede7097634f125e453d8c45506a7405b428ebfa7f827bcd0e8301bc99885151b254a30d
354	1	219	\\x79c097a18e8ca75f43442345bef705e4dc9650c13b5a4f5feca8edcfe6cf48b55f08a7fe907cdeed789c21df15e4f51bdfaba51897e825f1cc051c80ee75740d
355	1	388	\\x64ef4c8898f83b9765b3d12593b35e0c18fd4dc36000fb029b0b068e0d2c0b03d7c62fd07c056119289f7a5de410dd55dd4bcf5ea04b194332f8102fc5f5d000
356	1	6	\\xf2aed64977b883e57706e062737f91ffe3de9f9e0cc99a60ee0838fa1f051a1a2ae43d58a27d714632b73e199a86e65c44320fa6d4e3bf62f0cd4cc45980df0b
357	1	345	\\x0a6ba0c7c2e42a89293d087b6aa509fe8a4983dcc0a4c64744e97353c99fa05906701fe9074ce4424681be0a8fa741763980ecb55219057351cbf7e311a24404
358	1	76	\\x01750985d36864e79d57343e0d66cd059ad506b4d42780d209c89bea98e02168a145444e211896837c87f8be303a1de2a7bfaa8342ed0109a575ef9bcce92304
359	1	131	\\x306d9615cd148c3c937d1990291b62acf8b41215ff2fcb04153fa4eb2189ef7866400483dea6bb3d6077d3884f99262a6ba1cab54c6b5a8363f84ec3d63a1303
360	1	221	\\x6934b1ec2586aebc6c11201d6592d2b02454fd8be052325bc76e02266ace3f112b2dc58e4e43b93c4dcb34feaf3a856a8855a0ab3adaa58e9bc6fe667a984202
361	1	77	\\x05710aaf70575aba9c8aa266b982bd53599b1dcb0a0f1f37c065adc72af46feb455859ce7902c40b3e8cee742c98a6be4f0a8f513e3bd30dfb650855cdf3930b
362	1	222	\\xee07a48a0019ca2644e88f30bf881315a777c9b29cf9435657b2e967070fb2570dd99c34a472f6196cacab9517b6552218675f7ef9565d39ea1c37fe68a13501
363	1	378	\\xf5f69f88d1625b7e4edc9178f1cc1e6fbca39d3c8b6d143fb211638b369bc4b75566b672d105f1f7e9c89243cdca0b977e5e391befec55090c2bf0d59bdd1b01
364	1	322	\\xe7dd1bd7aa58bbf3d40362a67a95f4f81f45a27538b15cf9d5e381c8d52c2d2d630cce9ebf44194d7bf24d2247fd5a41905fc64653469855d1197bab60785104
365	1	337	\\x58fafc6f195dd0618a90637bf4c2bdee22d34cf400852a8d2d221816a1e555f125e6e354077d7cf2bac7fd73b72333eed64614ae903de3bbc0f393fddbb7a10a
366	1	424	\\x07c28194ca0b6c72920d4eca47182c563b0cdc5b41f3cd5198ea6cefa55c39748eacd66f800ad291a95af34e551843a501b0ab712c48a1e91ea925cfe539500c
367	1	363	\\xf54e57189573de50b8975eec55d15216f88463a74b0006ba328e02e81773da39ff6b9747ee3c3275c322472555ab13ec84b56d9351875572489086289b929c0b
368	1	14	\\xc08cf7103bc86792e4551d6d428db891db999be296c206174aaff7553ce740a0a18aad73e28414215f056548d3d49b99240efabd3aa6a1186628d71148239d0f
369	1	419	\\x9dac7a58bc874f512771c02a62df05e101b5529b746acf573aec72fca690d9b2feea2a19e3577c3c4f6a92d276361d0099e81c09cacfff1b60f1bcd1f91aa805
370	1	399	\\x580256772a5b6e75cebc41eab5d09cea2ec190b81c9ced229f644134d8696354c63b4eef9128cb8d49f274a3c69249d8ca63e919e43aad8e379efc75aab36500
371	1	359	\\xf854d746108e8d56483e0e315afbccd0dbe9abd933781ef8d15dd14a2512bac7edab082bb73b711554184bd3cd9e984e49fee8173e785e4c0b390a4f7e23f00e
372	1	387	\\x260e07d8635cb8477200615bda5b6c080e2cedd7ce52ad20602d1a3ad22bf53b884d613a95440ecaf54b1a019daac8ab6ed2976d7ef07c3827f7d03d6b963100
373	1	417	\\xcfde332f7c272df9fc46daa0af65b7bfce4cb59991f7922d3ec2bb8ac27cd30babb09b8ea18e3c2e64c1c971eb312b53be1ae767e607b2090ffac647a78b660d
374	1	238	\\x9801c3a4f91b5a9da657f14386a49c10cb475653083836f78b314e8b896ecd3ab88da8878b2ff00b749d4d6e157a16a793c2f4c2062ab087110f990f4112d404
375	1	306	\\x7a47e6970ff5254e11d601e0c8ccd99d54cf830b8c191f1ea10b004ef6d5815f091b96830db5bf2505fd73a17959fb6422d377cad084ad12ff315dc597f7e209
376	1	147	\\xeabf99d675d008a76dce6087869aeba7092fca04077e6b82f4d3935fd502c6dd36fa9313a0c8459c2556db6b949f5b52130f11fcc52f5a2940bbb92cf9739b0d
377	1	332	\\x0153e53f25af9b83481268134fc835c9d3d39029e20ff9c17215f3d5a226761ac3e0038c36177654fe4081d3baf592c5c1dc4ca55ec310353459ea303e59160f
378	1	161	\\xf23099924369aa451c6b1ed75ec0038025694fc82d0069d921145984adbeb19f77ba152b2d6ab6fdf881ed12244c035be092f8b26cf50ab47b1409297d4f8809
379	1	152	\\x2e6a80e0e112a6109dd8b286a82200c8a2b467377d3f8294f8d8cf6864fac30919b2c08fb24b1e8c367ddfe249443fd6600db78356f96466454f1c685d51fe0a
380	1	389	\\x04a7fe1c95f01d18c0f7cbab1243106a286dc081c7889409987ed461e59424beec802be26bfae880b2ae379c9fca76067b89f1694ebc9b51eefcaa2fce29ee00
381	1	326	\\xb2a236450138cb91675e6c646f128b3784beafcf28db62ffcfd22c72246c4f2ded85ceefe1f92115e90c246c5d8ea56aef0bef53285eeaca9ed00c6336338600
382	1	291	\\xe0d3a7af3b230c353185dfebb309464eee88ba3967141ea84ea928eb8594eef5dd1322c0ada430ee0653380d76618618ace937ea1296aebaaa166a702e03760a
383	1	25	\\x9cb216ee56acf03d93bf748816ef8f906c6a0802c601916122c1b3808c3bfb6426875e34e22ec111c8795328d2bd27f0076a7d51570e773ad1469675833ab604
384	1	193	\\x7df16696666280b3ae6323a9924949a94a8d0c4cda0e9b05da34b0493a64a31d7b3b58837fdc4a58468b432ddbcdcd4dd91bf7baa7c7200c2a798e7920a34b09
385	1	257	\\xf3a9d96b36a9370975a62adc85564965186b56927c5edd682d24c2fc4e32beccf14dc5211820e28a620874dc812a7f8cae8ede048e9c74bb017024c3b8145a08
386	1	26	\\xa9b3d24b824f6c3679f32dcff2c396fc0ad6935d07f7dfa8c88dfc5065c9f6ea993344eca7d2592ae59d5046061910d2d62640d96ad5106abb74f9b038c9f107
387	1	44	\\xa76b77fe4f9d25d6b4a852b43f33919f12b44aa84abfcbd472821c0b9470698619bc9f068fc00d64e13a14b0c069ff0886fda5615a1404684bcc2e865d3d1a00
388	1	202	\\x037ac5957af3762c3f5e7141706f8f1973945d79e6f111571890f01cae5b2d923b13d31014703ee8808be92fd3537d6e15966bab9d08c7bf5a4009e2233f4907
389	1	206	\\x8ccdabf19e7357dd3fb6c933304e9b3b2bd814107c7ce3bc39153d4b69baa345f9f57567450750656b4fc21cec652f7c22e06e5648eb9ad7df27397baaf1bd03
390	1	175	\\x8b809fdf49c538b47ad66aa6259a52bbbe77bc06c3419db4f788b9446135035d14251201fc46e8c1c7d6e8947b8e454e2736a331d7028dadf2b1279fdd529e0e
391	1	329	\\xb585cdb0b51893f10618268bbbd9b0abfbd96fc68979a6c4cf3a28573e657d092026c3a8f6caef3ea5588515605c423bc54eb3174f61fddbaf663e2eedce940e
392	1	162	\\x459cbfe816cfcc6f8bb7ff4ea19316f1951439ea9315a218fded549a345cbb293c9be1ee7a95f6c00c9f88a3a509f42d9fc469cff3d70bdbac7a36999f78b40a
393	1	133	\\x084cf971d847a9462d9edfe8bf533989b11ff8c5a1c42c987de71c9cddd17aaed74f08fc10eb0f61fedafff269a1cfc49b94ddb2cecd7e42c1d5298b635f5d01
394	1	108	\\x30590bfe38ae987732ef7975ee1adb173878af0df132fb72e8459f429c5650a3775d5d8c6c6afbde7212bbf548025c73520d858e3a02f4715a5908675883520c
395	1	194	\\x97be2b57d1059260b4c49ee6e637314c0a78fd0925ad4d052bf6497dabfa6c981b41955f09054cfb34cca8249048ea2e2b5fa84ddbe70b281ea0a1a4bb59b307
396	1	250	\\xc77ca5d1b8ed3de34bdc4ef2751e8832a4dbc8b1254f58bdf8330dfacb0568fa4dcc3acf4e79e451e68fc8adade9b99bc7136a8b51853fdb667747a603575c0d
397	1	54	\\xe04ea9295e2d2fd71bf2b7c814bc5e415f3b5eaabe27189a9ffbffdf382e8d387c9969662403c7ee84d2ad087f62ab9235e14b8d158fce87cd8d78a6571aa10e
398	1	13	\\xd371bb6d4685b0c03ad77c01a22b2e40ed3e78ce1fdb905ab269478c805c565c3bd75ade22833444155fb94ac96e35bcb72110986e7f9c9faae9b20833e0fe0f
399	1	122	\\xeef034f5bde838f5e4f62027d3fce47fce7fcefcc0158d877584995252db94a58e5ae75c29d4b87e1594bcd35dc886ae93d70adaa72063ad81433cd375f4ca0c
400	1	135	\\xa217a7cc89a026a14ded7be08c9fafe8f859bbb46314d2c1982f5fa8aedf93af2e81627fd69cee73990503860ef649707a2c001c59c73e1e3dce7c662814c20f
401	1	368	\\x341343e82357ea81db20541c07157a4a1e9c4337d7b62eee260da685f325292ac325b8c45b4e638b7ac8d636c8a8216bd5470f527a6712f3b428f78279efa50a
402	1	241	\\x59a6c4c1b6e39890d226bd705b54ee94a1bfb601555f55a928a4ce0ae902df4491d451fc87ebf7987f568092d439b0fd330ae1b95bf2bfc58d2e3301d24c850c
403	1	73	\\xc786d8088c5fa044a5fb13487dc98a796a28a8a8d90fdc6d6f2ccde83dc31de6e3192d6a085aaa714b4cef88c6364b3ef531428134a3e47fb3fbd339fd1c3d05
404	1	89	\\x9bdf58c8ff0ea5f639511fc2128e1c3bd2407284d905a7ef3632660e6b9f57891f766000d11fb29f29510e5ba2c94fd80fcdb7d8ad133356f887e9ecbec17902
405	1	87	\\xab0c82a8f07a94e1ba8107429e9e20cf8bac1c3095afab50f433c3f48980ee8baea2cccfa434d37aa730fe284167b5911434987479e81dd7429a5488556a2409
406	1	285	\\xd4fa7c2d11863d8f8b6bb187fda04624c96133342e5b6278a552a0d08a9e11c7414a2d2b3ace1dbed44d0ff08d1557d154e12e3cf3c8ffde24f43719d44faa09
407	1	166	\\xb90a7b66d9cae5456307c552568eeea45c4184ecfb8d2bbda0bbbf5f8d31f873a64f951e51a04aae7a3e9ef1509eb61591925b9e8c334b335caae8f9a4d9e200
408	1	200	\\x7a0879d7d4a8b4c7e96f900607e0951e6fbc6f69b122ad0a99b547a64d3ef7f6546de5814035462b7e103279928897bb509a88251f3159a8a51755fdb65d090a
409	1	380	\\xdefd305f4a82acb0a84b3be65b8aa03925dc79924734341cf7a0b19817b8b4ab83261c6030aac29106402d1372a938242f2392a9ef8f0238aaf6fd0a837a2506
410	1	308	\\x267e9ba6845f188d79c45d4e9c0a98a68b026d06e6999a6bade0869e94bfa7aec9cc91291638fe0e2d6c4b89702ddceb72d583036e77e5c8b965fc205909b70a
411	1	75	\\xb33b520ea17c5f3e13a057f97ec33a219d8b681dfc4853037288110bc6b6bfc295131f3bc6cf41eb8d74d99d02bc51f937b1a91cd336e3847e37f586ff7fb206
412	1	99	\\x2846b4eb2ea19b7000ff8226b871f2e5efda8822c2d3baa8819ed7c876cce7af459fdc0179961ada91b0577e75e5ee1b5e8656b0c3ab5b055c9b105316132001
413	1	74	\\xe9424b0066ec68d56796d76355fa52c2bbac2b878e038514dd572981683563083454fb79677bbe82791c55f96694d40600af5ee021b6d5af6ea06d450745530c
414	1	340	\\x07a98d79ebe6dbd54f4fbde90067761bdc8cc62061aa924fff666e1213e135a3e5b9d905448fd9ae269f5ad119c17d3f1d47831261fcd796b67d2a0d1eb83409
415	1	28	\\x125a869e6ec01ece8d7d0f8a4d95a3ffe01e98666b0b161e4cc89ed98e5c2091150c6542960630a5b51d8646304f00f220c67049dbc236bd10b80e7375b63d08
416	1	105	\\xfad5c26aa42ac6dfe438817fa50e3077343ba7e9fac2ebd77cd9e7f3e95487297cd7f640a771f4a6f2dd0b9f96b85cf171c1eea9d23258bd485f5c26ed0f3609
417	1	36	\\x493c963dfea7a421dad14ccc8adc186ab90e72883b8d2e5d0f231550aa8d010a5d72d15c3cb268256cfafedc96732fb0469ea9586a209c5dd402632d5e01ae0d
418	1	372	\\xbb5f0f66ab49feb2d0f2b8802f911ce99ea2311e9694a7fa34ebd107f8bdd03c18c4874fe9185b46a6e8aa05aefdc07fc5a6a2c430a742d52a720e482d9e180c
419	1	314	\\x34a599f21430234f63aa468939e97eab4897c44b71a3f89bdaaa5f110d0c992736770783f937b90f36fa2c17b1df82acad2454723b727bce7448e95dff1a2203
420	1	392	\\x0f2eb87a337c27089a469de0031b0359a93e53b707507534fe77a90bc6642f0df04ca04fb92f1e6ebe3149c54e062bc86c52e321426098c86355beac7b7d1903
421	1	278	\\x478f7224e14fd5304dea69919c3b2296c6223eed2e677788763aa00d79445558dd287f76be8825f577dc0638d9f797ed2f3830880cf2948afcce8aedc6d90103
422	1	352	\\xb62747c872933b8eb3a1a225ef67b95e2641a4bdeaf830e91f5fe181d0852b0b55c23141613ababd873e0642f70d597fb2441501abe8125b0ef5d6e982a63e07
423	1	261	\\xd301d04f28a898c3f068314ad093c86d958d0753cff948aff8e261dbaa71faf4152b36a25a1d85a10d896f2ffc14f69a1356c1d9f2faf95a2bde5ff2db22e505
424	1	67	\\x9b1eb4420f6b72792f2a43e656e7eceaceea63230f6978cfcb1c3a129ea8b8fd8790047d5a1fcd4af416d6322964a9c7c70a95f01ac1d2664aff8dde65ed9f0f
\.


--
-- Data for Name: auditors; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.auditors (auditor_uuid, auditor_pub, auditor_name, auditor_url, is_active, last_change) FROM stdin;
1	\\x77022411ccc78ef5fd264c1b9e8e37129cddb5196f2ae941f7f3f63e65eb5ee4	TESTKUDOS Auditor	http://localhost:8083/	t	1660491689000000
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
1	67	\\xfac104632c543b6b6a0c76535f2fab41f55ec9726e0c447d0f451ad955d0edb2f0f3633ec91acd5665cc25e3e9c375ea510129a88af96d9a83c61d66ed7d870a
2	105	\\xd81e1e729b9f3d150d39c7a863d229e1a7e8ce5a288fc75da4703b2b1637e4471fbc2f394ccc85f1b0b257509099b4e478a2c41f5b2effdf9a1455438e11ba03
\.


--
-- Data for Name: denominations; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.denominations (denominations_serial, denom_pub_hash, denom_type, age_mask, denom_pub, master_sig, valid_from, expire_withdraw, expire_deposit, expire_legal, coin_val, coin_frac, fee_withdraw_val, fee_withdraw_frac, fee_deposit_val, fee_deposit_frac, fee_refresh_val, fee_refresh_frac, fee_refund_val, fee_refund_frac) FROM stdin;
1	\\x0310516b8382d45a79f52f98842a563232b06491b6422fd300555b146202e0e399bfe074966785f34caa008df732d0c1f6f5d768950a2a7e7076ee8037b0f492	1	0	\\x000000010000000000800003b8572c1ac3d58373de346e4c1d0dad69b25cf93542d61b62a60225025922883d698c0bb75c9dc2ed10f2cc08c536ae624024ff423d60b3d04ec1a79bc3c19d570a498380a08958745c1ed1108c5105f16c08c45b2f478bc0ab47125b8128cc837da3dd54ca2ba88cbf79642f8eb845e51fdb65d010f6f730120b172d9800ee1b010001	\\x4c56f08ce2a681a69349bb8bae384b618d55c8eb5aa48cad5a905bca7db8bf7968301adee455dd2709c1aaad4149592daccb8036e85d2bd9f842557f6619a10a	1687694183000000	1688298983000000	1751370983000000	1845978983000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
2	\\x04604d6ddb3614f82b2f7e3c485765fe3775f071b30b2ca26f2703f5ffffe72bfdbe536c9b71b9384d91f8defc767e477ac20c0d40a6444f3282fe24b4e1cdff	1	0	\\x000000010000000000800003bae74818917c0ee07d0a3bfe77df1a3310ad541e5718d77035b482a18b85ea785953595b56c182e05fe5700b6eef771e2c6e83798a0820083def8adf05311d527325152cc651e5e0404e127de739e409683a9e4238e3746db0ce2a20fbf7534ccad1ea0397223e1bddcab42cab948651145a6f52e82abc981f7c023453ec956d010001	\\x28e1b42197258bc7bfb4157996410e12ff5a629cf13954206fbdb85ac51b60fb5ea67e5109ec95f6083c6183f8ce55dc92b595bcb5c18b413070ae3851331f0c	1667745683000000	1668350483000000	1731422483000000	1826030483000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
3	\\x06bc8e75cfb1cff7fddb7e9d3f00d2c9ba9a60befc070ef5f97bc1197bb850e7fcb23d516c225d1b7377540ea92246e5713f7f6289d809c53a1aaa392a623145	1	0	\\x000000010000000000800003aa301b78362384c1a26ed414965dc5d540d39cdc7e664a4bf3cdcfbb4ee599389ae8196bf2ad3b9fe49318f5f9b0ea6ad48e9103d98e23d9289acfa3156025dd07181573c590b136f247b68ba77f94283b5f6f97a2e4352e39c34309751bf4e161b5ffb14085299e00bc895d43276857353f87098a6af3ca961c8476e9b19d15010001	\\x0162bb486356706856e82f6658069bc4fb33479a101309c7e253f0c3f937ca06cff638dde34a73f614d4a3cd4f4ae1238803a40c21c260ea5be9149293361a03	1671372683000000	1671977483000000	1735049483000000	1829657483000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
4	\\x0a883a9f39cac52bf93d324ca3c79b733bf11745ce85749966087d46eb8ad6af6b9820df100cf9d1bb60d2e0b05810893f8b0c255618a00b203a6781df50ede7	1	0	\\x000000010000000000800003cf7e088130da6498ea67310b8df838a3c8855d856ecb4412d244a347c7a011b7ffc22b75fd157efde2c80bbb8c9839becb75148c5539ed3e1d1042b966b9d7c72f3db5dd3b482ac8f1199c64bbfd12ee9adc2995120905b0bccf04940af3f4927dfe2e4a6875ff57b97b12496b0ff294b198213171b5f244d6a3d272ddd60eeb010001	\\xbde05e23cffd0c66b76615c292dbc4fc6b9a6ba2412b0e738e07053dec3cf1de9e8b6f6e58c3b09131329386f8b6ebffa7dec4df76fc19fdeb2fa7d76566df00	1673790683000000	1674395483000000	1737467483000000	1832075483000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
5	\\x0b785af8c5c0aa592f28626f6e7b7b338bc4dea82d50d5f40f81292dcd8fde47b9163cac63f74cf6241805943ef66d7b08550f5ac4bacda757b56e47c7da8547	1	0	\\x000000010000000000800003bf44d4b20246babb7415a264ddad060c4a302fe35b0603dec0a0e27c553e9739550bce8b769e8fad3ce751fce8a2e1170f4b16b0701d510b9bb5fd9f91e83e4d1bb6681cd6ab46c40d5f5d2196a134233f1851eb7a6afb024a91e372d442faf32bd0d89c02dd00161d6027998b04c5d5b5f48953402edfd92c68dcfd366dcc7b010001	\\x33c037e7474b5a9a33b7656812dad1a1508585cedb46e5fc89755f2894de21f371e6816ff52cb680bb646d376697588214c3e6855558f47c8f291ceea5aaa509	1690716683000000	1691321483000000	1754393483000000	1849001483000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
6	\\x0d20b53e3eb607f57a63b3659a6d71f50ced420627c46f9d2827bb5f059e8b98610fbd18d5fa708269e4baf234824d24aad291e11ef4c79ca04bdfc7ae678716	1	0	\\x000000010000000000800003e0f8f86ced4536e9d857cf8356a962028a50f8cb16cdadfbbbc6b628bdcd13bdbf5cdebb5eb2e987aef193525e80b768d5eb98afabdd93024eca324e4d0dd8425252114dc4bdbac1681a1d1687ae009af055178e3c74aa9ef0c56106a4615a92fa6f6fcb0cbd6b964aea7ba996609187c065477c6256ffd42b6f36527e036493010001	\\x54a3c023acde3c014daeb2d0cf8341ccfefe5c135c5311448801c61e2eb0e623a34f786dc162448e769fc2a9fc6df6de0a96eba0fb5eeedc057997131378e005	1665327683000000	1665932483000000	1729004483000000	1823612483000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
7	\\x0f64e0f20e42976cff8e4113e64947b17e787585f50942de7f8fec0f8ca5fec9f528019275a02445b43fc2e57012dd15cdc8a3d75312cada5325c8a19e503adf	1	0	\\x000000010000000000800003ea16fd166310854088ffa6f5d8453a625086304bbed3a32b243a5e19834381bcdc82d921bdd9f5d4a0f3470a36328db6a159abd52ef6909dc8058fa4b5860028e74cd20fe5a7932ce308516d8b98f6be0e2cc019001da6e4568300ec3eb4a249b845156570f5d96eed0f913ead6abe0c96efb9307b7367532254284b44ccb041010001	\\xf8394bf841d8b0a1375361add09e42f7031d5e74524a928569bdbdcd11b9b9d60cc16ea21e5dcd24def8bbaaf7d0ecf21cd35630df04bdad48e35069281acd08	1684671683000000	1685276483000000	1748348483000000	1842956483000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
8	\\x10bc6a0f862ce7b63ee7e67a7e4a63a77fe7a9cd18462cc7674294fecc61e24108f700dbd51d760be437e7bf6eaee810b2bedf793b5712f3e54431f4291df161	1	0	\\x000000010000000000800003c3eb1a3af6ab26fd9a1cfc2a0278233a971ed66c999863ba5cd8abfe70ebcba8aa6a8b3ecfdbfd7802ed2e8f378ec58b45e452fc53ee5c7809edf9281796ffd1fa25f675600d80b7b7aa5a30893bcd8c6a2a822a847a7051b063d729264aa742f1b62ee54f2062d4db628989b771b8761b7702d52d8d16d3669cb53f07329839010001	\\x04be91a25f2b916928492d3a82724040ef1e54823d300ad6ed09d7fd66045147c5123f326cf8c31ac1a4203b2a1a0670634d91a8d20ec02772fe7f936639b304	1680440183000000	1681044983000000	1744116983000000	1838724983000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
9	\\x10ccef2a490b2942d5e384541a46cec342b516fa17765cc044953575772d90fec9eb37915325672273dbe86a92bb4ba7da0be84b23db355481ac6dcb2e52b394	1	0	\\x000000010000000000800003cdea4b8c135ebe0753af61d8bd2cb20dd55fc46fd1fb7c1e67881186d3b46b4ba768554cae7b70310d98386cd2f2a86b8768f666168ed76af8d849ca3bf1c7582a2a1711936f0f4223345fcb70d4617360754fb552b3d918ce5002aa3e6739b06347d483f589f795b74387c6e08b8d36f67bd7e02c81686cff3cfa219cad1bc3010001	\\xb8a8389f7afac4f7c7466143d28d346681cc8ff4ad3078efd970bfd0d4ae26ced59aa6b7b98019892a1f6cc19b2ee07f359e07219e263eee7325c5eda421960c	1688298683000000	1688903483000000	1751975483000000	1846583483000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
10	\\x10e08ec731f9e90883b55fd4cea4e380c3512708da8a793bc9b50546cb5bdb14f0ea3d0c64ff758b3a3a8b907316b47e8f4da057688e3dea1c94399e02f0d166	1	0	\\x000000010000000000800003adfbacd92726694f2e32a9f2d5bad43ba3127c6f0c6f7f80616354cca11002c7ccbc069b07af71da2318c3e259d80a8f08f28ebdec8a38749f1a8a2a907f4bb386c3b74133ccf3641cb8f92b6d5c0c2c368a1610bff559a8abb24feec48287da92927446800f70f36b81dfe52b0fc17317708f1f16e0b9391d9310e76980c367010001	\\x4ef4e1e9e325120d84ac35c8c17f9122ca96df299e1e12bcb02586fd370d5b6f11722649280932213e9bfb3fb5588ed481bc5865132e1c4e64232ccf22124503	1667141183000000	1667745983000000	1730817983000000	1825425983000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
11	\\x143cb0112e4a53b7d76f67abc463c7e8ffe494bee8b49f9f0360288e2b6b94c60cdb5974afddf1b1116416d0bba2b24760f3ea1ec70f24e9225dbde5dc503429	1	0	\\x000000010000000000800003cbf1ed39430d4dff9a3cacc554a3e9308208efdcc9306df9b2ab47897a4e641754c031537481e5e9d54d58eec16ac3da3a8f0af840f382c462dedaf710aae8046022dc6cdec29053076d8eb862b475ae7393a3dd9407ff205b7fdaa50cbccb33ac1e9634a2bbe98d00c01bf25d7e42cb85d9ddca3b4a079462694b88c12a4123010001	\\x9cdf0b9e73f8f4ccf0dbc6535f1c47ba734859340aeda8742b8b27942b21e98f1415d625ad1ea324b982e9905b6c73ffab5ca3f79868b81db43a313016106a06	1683462683000000	1684067483000000	1747139483000000	1841747483000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
12	\\x14fc95b7045ddf194f251ea0187893f3d35799e29b6312e45b49fd22de8320efa55defd1b1f1b5f8cb0f5ccdabcec2080d15072dce329eba550cf8e4af3a2792	1	0	\\x000000010000000000800003e72676e9c88e92ec1e2935aea350597693126d54fb1ccfa2d93e816971474c30c25facd0bf652c072c8456653bc03f153e5a6f8c642ca57ff7aaf3fb4cd37a2b59b143fd9dd5896a5c52dd295913dbf492fb46ab645bc0b10f2699cef607f1ff39bff1a6c8e06313b4b902745f01318cfcc14fae446b423ad0485259dfb6be19010001	\\x6a617cc2ee7bcba11243744cf12d0976588e8128cef9a8fec2c7a22984f57fe6d2b5ee36cbd276a17d343eb5e9283fbe81a46057a98a8e30443c7fb20d8e5802	1676813183000000	1677417983000000	1740489983000000	1835097983000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
13	\\x1b90322d3e8030ef8284f3f53e80f8ac376914a51b0a218633d2a0b64cfb8856eb518963270a42ff943544f47d744322c713579a684b22f93cc80c8f1e1ec9ca	1	0	\\x000000010000000000800003c659ef8e81969dfd627cc02ffe186daaec11c1762a2f5d99e143f9d9e4bdc68e65f5394fd44c7271b444a9f622e6c39e6035e11ba08cffd46effae1543d421759e32b70cc8054312b872caaeab8c87cbb8673853a90d2ce25e88cd6ffbcf4c697f9eeb7ef29ce8cba1aea2193e422f961cebc8e0d81b77051c460ec63370b835010001	\\xf2176ada5abf495214b1d946c7382b82e67fe0694836203e2d9235c0c741cf1665e42ce24f4e11c9657f176e5b19d619024550ac93530841adb8c49b6d93430e	1662305183000000	1662909983000000	1725981983000000	1820589983000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
14	\\x1bb426122b9b100dbe3ea07eb10831f9829c984892bf80c358d956a2d1b7181c81d4ccd9d07c8d12d714b5aba0d14302f3e78f60512d7b431182dec61c13462b	1	0	\\x000000010000000000800003ce49686577529d2442394cb2d60cbf9fe2be53a95340fd72065fda52d0ac19264338c2ef1640bb7b2d8e08b4884cfcad35e83b874d8d5870413c8a977cc19e98fa46fd118dfa76a3d074654122d35a8162fb9d06a554acaa19d6045c9593c1ec0ed366f8ef6c5815565418c2c44cb24ecd08c1504ee3b9a24cd50deb9ec152ff010001	\\x550596f9d1aae433e9bffcd6edb0d5be1b72c124f0076984d37a3c62bcc6938c365c2e786e5a0bca48d1853b981a1da9e97ca96bec1bb13843d2e4639768df0b	1664723183000000	1665327983000000	1728399983000000	1823007983000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
15	\\x1f383b7f4aec8e717a9e0e3b53a28d8a74c67dfadbb39ff1b004cbe5b075408a3b0e97b3d69563e4c19a5d5f228ab990142a4ebdeafd8561b3eb93b70afb9aad	1	0	\\x000000010000000000800003c2875f294c3d95d6871548e543da44057e0fedd3fecbf743bbaab2be8ebf6b50bc71d4e63e9d881c8a61b278a153fbc7575ed69f2706cc73d71e3a3515aae62d7009d6ad514cc3156938a40e071b6456201fda39ed31740d1a432ce49630a484b1c584d92f5ad9c035d186416f2d91a5de037934f5bf03b1c137a52fddb42a15010001	\\x02122fdaf5cd566cc1e0a60a9d276321c0ae4bf2fe72488525a7efceb1ce64bdb1c8ed8d6b5d8a2f5d2bb5feb2e64dac5b0d2e4baedc794a9caca7ffbe579402	1673186183000000	1673790983000000	1736862983000000	1831470983000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
16	\\x20745258837c7cdee948f110f38b60ee76332e5ea86ff16b971952e36fa6ba4d1fe1cd182ef675412346c768449bba18d37111cd4fc2221f4091042bd446f3eb	1	0	\\x000000010000000000800003c4cfe7f3584090e3ec6e090e22ef61b30987633b94623860e038723923f2fb139e369d3b7971652149792e237ade24bfd7439d3277112ca06b8bbf98a7edda396b1242a1cad5013dd41fa7141073908f96daeb5ea01bcd67e047daaacd83fb474f82d54692b1d5a31c238f210deb88212d2900a494d8a5db7dcbecd0dbffee0f010001	\\xb471d7cfad5e73141bf210a3758437eb863a51222361ba7e4fca6ffa493a9a7f88206168323ccd8a2e8f72a770248864bb584da58fd1f7f0591d9f83f21d9305	1689507683000000	1690112483000000	1753184483000000	1847792483000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
17	\\x2120d0e8a936dad06db41888120a96f0f56a6730a75114e02efc145b4a6b6b8708037c010cd090829824044fe6cc86adfcf1952460a58a230a70306b2cf1c84b	1	0	\\x000000010000000000800003ae9181e24cfadeddfcc03dc4d7bf06afb0fecc9f7b7301f75afdce0d7f08d3f264fdf9ec63b07368cee1ce46a8ee2b44e67b5d8bf7f45f582652c939e17980e6f90970417ea8a710b2a7b86eef0224534be81cc6a33c219c6fc30ed9b5b369db4148c7972f82e1aeee17686a4e106d5f4caef3afb095d425c6a76c53accc374f010001	\\xb8e852e65d64e060740985e06e0d54af6a2cb8e08c98c319536751afff6be0186af66d94a9d8db97942c1dba3ef40fa62b65ea0b0a3beed7b5d7f1ccb10cb904	1668954683000000	1669559483000000	1732631483000000	1827239483000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
18	\\x23c0f14b4614edc94ed354f443671b07366974afb1b31a9edde1438293dd73bc741b45379bff66081f915db8478639c36830c9492ab7c16a30614d2623ac24a7	1	0	\\x000000010000000000800003d54f9a3b299716247348e32b8c198b467ed3254e33337233827abb8c5074d777f3234b254281ba17420e508ed8af7380e7d3a5b3045b47bd6e9e672f51fa756dd7e4d634360ecfe3cb6028a4f0b2b6afab04337ccf46841c8c0722c21b1f793e44d3b50ed642889f441ada84ce8291546b5b7e9f52731e76ead9fee99090c607010001	\\x3f5f7dcd0fccd4662f8fa1ed69dfac30bccb26e1cce7c567720c31cf046f83da69033611b60ee84f45ca165897168f7d70abf32f6131fc53c7ab6a0b43e33f08	1673186183000000	1673790983000000	1736862983000000	1831470983000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
19	\\x259c8a2671a8e4ef370c9206de15592ea628023e7a644e320f5062a56c8a97910aa93e4df34e786b914980e53b926ceed471a951a5033fa64e65a0b8c34efad3	1	0	\\x000000010000000000800003d009f6daa1c63c47ed0f31cc113798fcced94906f0b7155e87149ab81433b9fb7274db45a98567cf6efc86512d4f5bf278db9f167b0043ab1807eedba446502e1ff2e3ea3d37ed64c9cfb0f92ef1a05d86b7900568d938123b5448233f5a59865dc423756cc02d00e779ff474aa5496bc4ed5e3e25b9b83eefeec7b404ca6a15010001	\\x3757bc950eb74bf14220f8daa7707f4a1f432935505d96e7e70ad6b2fc5474dfe6f4836f585ea930906210d720650a980db88efb49dc81add645ef24621ae201	1680440183000000	1681044983000000	1744116983000000	1838724983000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
20	\\x2dc0970ac7993986d49a431de574b1108d45e73ef0999c525295185364ac11f26551e035cc7dd153e46763b6a5bf04e2a1e3de3947e7a020d21451ae86237566	1	0	\\x000000010000000000800003db4bc1c434d51ed3543998e4398a8d84cd827bbe0ca6855aef13df050ac15353e93ff772e739f83893763009e33b09cc9f54d89bfd072818b87f6cd05681c3a11eaca7dcc5bb62003d94e444ff677fc997432b709405de721f0874b8ce8b80d8106cff2db2375e0a09f0280b9de42919dbf190a22928e01f2286bb584b7b747b010001	\\xeb46c4fafaee6869e5d0da05945490489dffec3adcab99f279f7b02c5a2f1d88ab7069c9a4c0f5ecf48695ecb5dc421113cfeabc52d623a8dc0972a145cdc701	1683462683000000	1684067483000000	1747139483000000	1841747483000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
21	\\x315c8c444e5c6c843c67223430aabd8cbd3cc6e3fce831dad07e9ff6263dd21ef18fe9c85ed36fa0e6c5e15ef5e0baec7e484ef439498c073c69f8af1d96ef6e	1	0	\\x000000010000000000800003bbcf4450dea22a85da6ddc042274a123dc2b9c10122ab9c51a9c52924867b9f967857ba7b761940a736378bdce5ef7d69d5ea550e6ff829afa1cd1b186d2c8645f92df3ab5bd98b82cd874d767335bb048718c3fcee0272dd0e27e528658a1670d112e1abf3b83343282259931d7feb0e33ce83efcd43777cd93ef13c244cd15010001	\\x22a8e8418691589216a2ccc2448b3003858d0f49f231585fa6a992b5b3e2f2192d8e704441c6d92b710de027cffcaef9120db8b1cff9664f6c613be21d781001	1676813183000000	1677417983000000	1740489983000000	1835097983000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
22	\\x330080a77547c06ee480d2d2dd33fa3969582799012cc0f2e31e982d0f44862803e37cef43758d5d7934785115c4cac044fb6f32d3a973307d6c848320a079c7	1	0	\\x000000010000000000800003acdbae178d6152af5efdb7d4c658b5ef208ad58c9ff4b40160495360432824a68d88cd95ad5f65dc554bd2a25c254e9c93cb5190520816fa8b0ed8f77b89c27803aa75f1d3e9e4985957d7970f37ff44fc4086b971e11f012b690cc41a19903256509fc1bd4c28e360a4a24fc168418a26d10aa03b6dd602a8ed215c4257704f010001	\\x343538b5926cf42e923910db71b74c7daa0b90c5743949b765315a9a05a035d42f83f5279313e93b8d565423b70cf7d836abf11cc88ab243a3b06e1476d3e50b	1673186183000000	1673790983000000	1736862983000000	1831470983000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
23	\\x34780006ae597b55f58a32ad8e082ae7e2c805ba4eb83365fd5d59f49afbce42f1b72925ff357870f14334daef956fff04330887f066dd86f795f9358ba9509d	1	0	\\x000000010000000000800003dddd3f7270a73102a9439755b937aa883b811f9cd5ef4c055aa0c14f86cf5b598b2b26d758ac64e84628b73406107120efa62bcdb0c09fe98e7ddc8c24a3539b397df295e8ab975c95e993f7c9e22659ea8f4c7c1308d7af99f64bbf501748c638622a7e7831cfcfa563b8a3845a7aa08f01c05c61d1982c95937050becc3a09010001	\\xcb23dab62afc495eedda27ff1ddbe7ee05fce81371be25113ef9b02771cefabe1e3890f01e1a730d6644822ca1ab6a2c8564d490cb9bb628a6de16fc5b8ca402	1685276183000000	1685880983000000	1748952983000000	1843560983000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
24	\\x35583121879df4f0545075eea0dd37247aa13c2c2d2a12ba561f1085d07d407b85ac98051e3eb98dfad376648146c91762a6cb42cfae9d1149593506bfcf4c68	1	0	\\x000000010000000000800003d5100affe1e4a34e0b64bf2682ead16b830a657c2f929e7b51029fdeacc6b48974014517e2df036aba924b77a9d036cc7c21defbb50e332d49414baf3a643674ae4390617fa34770b874e107935e778e7b5d867f91acfa668c7ecd3886e77788623725480c15e022f0cac96678d0b788bd95cc7a6cd02d6f832bfd2e2e0309db010001	\\xfbbb49e6ba852a9c68e4bff9036fb551c1b2d5ae63b85e64e9421027b8722e53bb2049fd5800eb730015cae86f082e4d682f317abad7398fd14792835753030e	1684067183000000	1684671983000000	1747743983000000	1842351983000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
25	\\x36fc9461edc28beafe5f909bacf69d054ee5d64c7999291147f929dcf5c2a4902ad8c8412f58eaabca78e2b8e9ff8d4d294f23e0633e7d8c2678e9f9dda2312b	1	0	\\x000000010000000000800003dd6004b87dd45320a1367164b9740c8018bad53e1c9f01314dd9729fa11a7c7251584b5bd6d9daeface71c1b8688a69ea30062f54273d37a14a3fcdca44cdf9aa9885b1754989d316a0d7cd2e7f04e4aa1710dacb5f5d42b47732cfb067f6ae924a1eed4303dc8a817dadb210d8317ffb0f19de6e03cc60525c2e4dcadd49f7f010001	\\x0ebebd04a7db056feec9784cffee559656875469cbec4da5b44a925a5de50b6e598d550205a90bc812fd151ec38df0c9449df6934e8afe09c04b637e1964b30f	1663514183000000	1664118983000000	1727190983000000	1821798983000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
26	\\x37e80e50549569e6383dbf842d59494e1f0c914e90ecdc71c00f8190aa3e2a675d02e15b9ace5d2d53d3c252d4e3af45c69f5cc898eaa80efbfb76d762d5aa2f	1	0	\\x000000010000000000800003da729ee79e4033658a68cb66fb1f88c760693513afc9d052ab1ebced622a6eaac5f6d37ce766882e417ea3ac07a6b322521fbe93594af148363336a415361566d8a44d5f5322b9970253a055b26f3021ab413b59f8571c231b311130233ae5729054f53f98f2f356b5a82fb249c1e5b1e99abb030ac346c0d5351c2e90ef2e87010001	\\x10d884347db33c671a601899968ead18f586adf53bca3a84b5c82ccebe6b1c49c8448fb7858bcab1f93e0c37ae581499f01fec113a80df82e47a547deb63380a	1662909683000000	1663514483000000	1726586483000000	1821194483000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
27	\\x37389e25761ada7b1bf6eefba446c12304d4c6f8a07f5a04f65fc63b838c679528adf0aa2888cf3b133eae1dea6a45629fb419bd44877f3d6ada9fdf2082e1ba	1	0	\\x000000010000000000800003a3baf73a39dc6d65029f139e3840f9f229cb63e8c1347efd608ad0ecede42b7832f92b7638ed8ba45a4fee8467bd50b7dde50fdca5c8e5b2c2835fc5638cd9b788001e6ef3eee23642515112b868b260392e6d57f9ca40fd6bebc27e1d813dffedd9c7dc5852ca9e2c0c21c1f29d11f7f84aa223c589d0d43a3b4e50045d2ca5010001	\\x16a1d2e36768cee97096bb83a48bbe0b8ec6c4924bc6e62c20836aa45f9716baa3324356ba8a5c3cf4b03c17028bd10f3ef12a6fb06dcb5ccd1f11472c509a0e	1684671683000000	1685276483000000	1748348483000000	1842956483000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
28	\\x382c6d516ad6e49d3f32f16441eca008257f2c165cbae1209c94b8b20cda8adaefd17d133678921ad4e987d7be857082d373da42d32de5982757569582e030af	1	0	\\x000000010000000000800003c403ea26ecb774e1a6e1f38b49ea4afc0a384ded3efcc94c0b2f40231305e3e4992e6007cd255f23832b3a21b688ee3b6d736d2f77fecc5caf4db1caefd0c1972ac9338e6f12718595505ab942a69f8618393952b4b529413b431c95e4aaa5414d5d9f35658efc197a3456b5bfdd45af416cb54e01985682d21813e420e64dff010001	\\xad7fdf308aa8df0c0d95f801dfbb27e19e320afb080e2c0e074aa24572cdbcbc24368ff447726d86c3539f6c67fd9ac0e19bc0c38a9c6fe2820096b21f7a1d07	1661096183000000	1661700983000000	1724772983000000	1819380983000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
29	\\x39086fa62d1495cce08b737ec87abbcd0473ff5767d38bfdb14c7c87aff702a5814c7812396d159a9a71fa935135ac8b5d1673fbf03b74a06fd99689a50e60d1	1	0	\\x000000010000000000800003bc70e83a338ae6b1887b38508d2b85a01f6aea6eeb581d7413fca884c2627b2a10080b7bc35062fd75cd8ed7b8d355813ef8b222a7a5d33717e71eb5e1b4619300b67567ca64b2a4624e1047ed91bd30730d5047f69a6c050f53a3be820e1bef6950b2046be2227949c9e2434506faefefeaca4c08e35d22b93754a83e82f78b010001	\\x145a8afaeeaa4eae13a3ca0a2ee07a3aa6fffc05b6cbdb710dd0fc4626a1d5af3c63524706e4363566ccc78dd805f086b16343c7db92bd0f5a83a5945c54220c	1678626683000000	1679231483000000	1742303483000000	1836911483000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
30	\\x3a54049ebfa1ebc079b4d0fb0dd9778c6bdb1f39e7a3633ae6453127aac6b3d60ffe26eff4fca581c0ee3a3c81025a5a6c32fdb8927c4a3659be055758b8ef9a	1	0	\\x000000010000000000800003d9d87eb1e17b5a5d70e1ab618259c23718b037e77089a06ad4d9bb41f2656c45ab6a17e4c5cb5c5751146441139ffff2e0789290942955665e7e3eb2e72e57357b09d6def8ffbdb19c970fe0f1405bb8fa332ff0989c1895375e0ec2d244c37af9d5d6d49f3821f03b2f8ced9c889cb7df4ea00c72c72893f4cbd96b70403185010001	\\x0b7698fa374add984cbcee96855cacc8c27c6430c90a9543e2163b227aceeb8263b46ee840f7ff99b8d38a1f58a84a9cad7ec708321070afebad1203af788806	1674395183000000	1674999983000000	1738071983000000	1832679983000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
31	\\x3ac0d87380d24dca1bd238d31af71a8078d01bdb23523ae0d2a3f018fdfa09d464120f31df2465263f0e127f5f000419d7122dd94392c0053cd2304b55aa2e8a	1	0	\\x000000010000000000800003cc2c80bee9d20558ba6f4dbdff7e87b455e34d35c3da4c3859d94d847b976177c24c837276bca6b3b1379fb9c16c0d5c26f917ad9e022ee68ed740e222ba0ec2980590881137c53d625e655c7785290584c0e0cb1a892d42d26b67f9057ea2cd95962888d96e962d46b99be1edd9749b6c513db9c7e8452521e7c87d635d1b27010001	\\x3ea52f52911439c956bf6b212c35455c49c9f28b23b343471835804b09f7e88c67513979faa648671a7db62ab4968b3cfc8e78275b663da3887f28d52aa2ca04	1678626683000000	1679231483000000	1742303483000000	1836911483000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
32	\\x40dc3bae8d9b3e219e3fd595bdab1c3b8ef512795606ce769b8058e292130740ae396e7eca51eed2e9b1e90774c609e2b003d1151ab6a13cefa3df0fd0198979	1	0	\\x000000010000000000800003ca08a9ce3a7082e9b7c51a6452cba4433125c039e99e8d07668b2eae32aa9eaa6a19f7fad34beccf75029197d9a32aa1a98bbf8c3181a367231baf0b06346ffb9e94ad6d537b6ef52de60bdb08589c9e42e6adfa069ca55dd8bc27dc7aaa3264ef80f9445c01d864cd25f3fda53d1868e06e742d710ae9eeca550731acff2577010001	\\xaddb74fb2da859019dbe7747bb31010498931850e3aa7de212f406d4c562251b9a49e5fe424c20cd3039e2ff3cf7e834a85867bbf51270c37abf32e1097e0d05	1666536683000000	1667141483000000	1730213483000000	1824821483000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
33	\\x4290a88c9a0c69e2c73326dfff951a403183349e74e3c5148adfa95df0b6b3a3d6e303b4b40f845f81e0cc7bd357c5f3364dc24554f0e5aa63ddf855d59d9d2d	1	0	\\x0000000100000000008000039e1fb8cdd80a149dcc2b03c844077e1006ed69a9df96c605f1f23451aa96866e5d0e14d9db7eb3d5bcc25522e588a22077525af4c81388000c69294545e8f78d0d9d089933f9f72515e6c5eecbaf800bb28c50119021cca82d0f7f3f9aabc0256a1eba253a8550b75863c40b733fe1c579a43221184971b158d5a6c3cdffd4ef010001	\\x210efe2c88a0362696a311d6b54046c6c6af099816676f6fbdf1c1aaf4be52f20b1ee224ae48fe726ed96c99085119e2af40bb1f9fba1f753eaee1c3581bca0b	1669559183000000	1670163983000000	1733235983000000	1827843983000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
34	\\x426c8f5c03ef36930319a3a48d6b91ebf0d8c1d2709fbe2cc80a50d0b9809ff4cb6d1135421ae85f9b982ac1dee729fd8d0203533334dd7a01772be29f062c14	1	0	\\x000000010000000000800003c6f4fa26a95fb01defb7adf675854954e7aa6efa40cc523672574fcc65e00b35f232d3721a613f430ee918169e250a9c7b6e866edb0100e5dafa7944c3e5cbe2b8a895d6b68f22123ac1d635adf4269a4fb9b7c95b32d1f7d6c57d57aa2edb2884f206d173947bdc485aa63b6af8e9cc6e485dcb60cc533b3f688d51f576493d010001	\\x9c5ecde6c1ace2a7330ec8f0542b5e65a7b24cc1a20af3459886d9cd3cd2478e0791fe3b7503477e874979f9a3ec063e3fd29d816ab381649b5b9d89cb110009	1688903183000000	1689507983000000	1752579983000000	1847187983000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
35	\\x42ec9db7e01d7896907c92912d9006156bed2255d66be7ec9ea867d181d542305ba8652cfb1a687dcf4cd3b1d9d6087bda1d7609e8153b4374e6f1e90522a231	1	0	\\x000000010000000000800003cbf5055348be1eda2e3105f2029cb8d4af45bd697ab9afb6de0f4eb7bdeb53be9223b31845e323af17536a232a7aa188e37b8d27a972ca2b9853a219b1e1e978ece6cee59bb652d70be24763bdf77a73f0718590142aeba2e2eb30f971394bdbcf309f599ea25f1bc257383a13fb5d3277a7a6e714d08140afbcd59763709d93010001	\\x63990e106009811229708ff260f6a93675aa3ee6948129301b095e7a79106a65163f13df5e557fbe05bb44f54118dc4ac9acb15759042d13de702fdd4bb06705	1685276183000000	1685880983000000	1748952983000000	1843560983000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
36	\\x45e47bdb4d641ec9d12570735dcf4966ac53fc9672d1bb865e3bbc08f54a3d02879498bdb3973135315e1734a476a94baefa2d228a7b67ad3bb0fe3ca77d9589	1	0	\\x000000010000000000800003d9d3b0f09926096e2d88b81924ba27c28923b0c450868ab6be8a6d32e32e4d937ecaeedc33fa35b87729d156fcbf79855296f97b9baf9fa421e98a6527c208604c3f0b802c654ee585a008c80a8b63ab024ccd8c0291186b4d69cb3aafbef98209fa7efcfb5a1f5db83b6483a1884c8a99372001e310c9ec26956f9147f3908b010001	\\xdb80fd0aedc4e01cb46f90c903833e27dcd0c5fb6cb7a1f959d867a740ddbca256ea1856d382d34c64cab38743ddaa39a53b5b02a3623d00ccdf1b4bb6157202	1660491683000000	1661096483000000	1724168483000000	1818776483000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
37	\\x4788458c7148dec3b7c77bd7316e74db6cddd9cee462eab6002ea874a30270d4bcc496fb51390c1672384d4d04bdd859e6e0f2188eb7ecad1a12e546a07b6118	1	0	\\x000000010000000000800003a23dc8b2b2f0fe1db41e737e8738f1a938fd77fcd81674b0cc88a1270c16c6d5972bd29a87b8f2a06300468f265c465f30800f015627117c076684b12e104b14cd0a4b6c1d160c20cc1da804e6ecac37547611624b73fa05e4f8a3747240d9f080fa46ebd66110c3591b0e3158c2379cbf3dfb58423d61f6e32cfef0edb64861010001	\\xf0c49627b509b90dc44100fbaf43b41ca49179277d72c230479cac5435f4e41d32d3fad52716001dc826ea4abf164026b95e9423f8abfcb71fb1d7ec69868b03	1666536683000000	1667141483000000	1730213483000000	1824821483000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
38	\\x4b34d2e99863e8e5033fe2a20fe91f3bf6e3ec730c7eef6a4827dc829509ddad2494ac3218b583cad90af5742c57855f61562269d0ca366cd92a21610a749fbf	1	0	\\x000000010000000000800003ac174457bbb98652deaa3791d41f32ccbb4dba76a1da0f23b09f33fd1568a272f6db58c66a16175109c045e3a1884f9f57d64c198b2ab604bdc742b92a657d0bfc62e05bcdc083ad82652a267e7dbebc0b7f1f6b69c4557202a185105dde9fd39a55e78693c8f46aaa331d6eb2c25d54cff32259559e0209afe6cc7cfe967b6f010001	\\x7a200fd08e5532119964578f3d9dced96765cdf23959758cc2e821c3ab7e49bb4df29adf5e3932256a1457e0069d19c1ed07ae797eb862680340cdf74acc9e01	1682858183000000	1683462983000000	1746534983000000	1841142983000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
39	\\x4fdce6f56aae160844588e1e52e733427341ba7b59628b4c33fe4383322986ec6383d9901ff4dedad0296ba5870bf6cefaff386e803456715169c75cd94f2334	1	0	\\x000000010000000000800003a316758d2d69a67eef08c04656d167a9a1186859c2b9eb387a90369960e9acd59650b5188f8c4e3fa55db66b7081b665d8b28e91ddc87f51463bf4e9d1a011910d54e0c6a65aa876f073b65c849f614824ac4fe1f48846c8f4aff0727bdf32e243be3b28ed645f7c8a3d36aeec5fcd72d418f00aec73491ea709d89119c10e03010001	\\x700972cc63e21249778517fe227b8c01c7ba14c5316d996d05534b1b4f63c2429b57dca4d1030778b83db0db6827c78d13ef833b9418730ab83cc43e51a27b0e	1675604183000000	1676208983000000	1739280983000000	1833888983000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
40	\\x516c43f50f5837a892e4ac5a883cb2095b27dfef13a9437a468c5dce4271aa3d589e8becdc8baed1dbdfd0f72200eb58e46eed59544b05270bbb7a1ea3a9cdaa	1	0	\\x000000010000000000800003faeae0221b09db62aa84f1db3609e887b922e8f662e5da21f24e7d2bc2f6585c94595d32ec035d24c1d6cbe94f82e4d085c7037ee865da00aa4cdba06420afa0849b158234e156e94e609f2834db034046159e48903d6d82df08f4a2fdc957a9a428a1fb26e05d921216cd318066c28a4d8bd48a03494298ac48fbb314eda0d9010001	\\x57701a9bf4e24a2b349420b581033822c6bd0d14ca9dcea3007e3ff8e6e1a24d32268581fc8a36fd02f2becad285329723c63a78cd67231812334760556c2801	1669559183000000	1670163983000000	1733235983000000	1827843983000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
41	\\x55c4eb5a514acb7abf07c2c593a6df07fd4ebbd271e5adfe991ea9656e650a6a85260901a12545444414865dc73ce40cbe516a343059637f41241274e3215400	1	0	\\x000000010000000000800003f50d51d0b8eeffbd111ed9b24137747bfeb670ebe219a96e50afd91b1b9cb7f91c09fe69d703103c0bca03c9196270be4cb75dfbe303e0d6ca8f208394d73e965560da2c18021950379ab370e5c5605ac6cbbbd0629668a6820077e1dbc0af4cda8fb0308767894a6517e24a76f97cce7d162c538d1ed1b822f6a423eb98b7b5010001	\\x14bee034ddd0ace74aafd6d6b5dbc8af0c2b40f86ac533bfde4fa4e794e75231d0bb4f5a365cd4f8fd90579f9af39064e790360606bdb53c8b3fa20209ae5604	1686485183000000	1687089983000000	1750161983000000	1844769983000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
42	\\x619ce3499359accd44b9590b10f16a5f4573c0ce066c4928f48fe8fa89aee154307fbf3b906a13a8eeaea61186c0e9447f3cbfa8698deaad85f9fccb7709abb6	1	0	\\x000000010000000000800003d694cc55dc071a8178213266d9f35081a23d87ce0769904a1f7b9705ac72d8e2d08e4d08e62e5384f7a1f36254e17c9086a3320188e0bd3c67a20f2aac65e8a1f6fafa28e18595d31b675ce00b45f6644d5bff52f6f5238941b16c354cd1070fb9639d3bd5aefe33f77c8d78036bc31c6467cb86926c519fbae764af3edb9865010001	\\x65217620fa3f60e070b11b5b3ee2b954432964bb01494b4b5460c71c6fd580dec0896c4f6c3d8a29699026d71819fe8dd1addcb8db9e5559c23c128fc5ac0609	1667141183000000	1667745983000000	1730817983000000	1825425983000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
43	\\x640ccc80ba77206119f1452220cbd8aad418f32a9cbc9f94a1c131c0bac8cda8a60110547bd5972d4c8d114b48556ca86a10d3b02886331217d07c3732495158	1	0	\\x000000010000000000800003db0abd5332438ad1da24d3600e1e7a98e24577dbb364c3d3ea037fd8d0edbd40e96cd1169502392f2f12537cdebdae1be3e64a369b8ae8c55f459a072c298b52e1e6f7266bb8d2c7eb80f7473caddff1575dc0383abd2bc0ed97108c2882198983294712e065c90e4e61cf3ef6190178fee13a3aeea226b02cd64c6bb6d7d7e3010001	\\xfe58eb189d3ca6c253d8432c5fa2c62795c0cd8fc21d8b1d59709f7a7b0e21a3022af5cbbacac63907ec63ab71b5f44856c2c7bcf1d064134d60571ecd503e01	1690716683000000	1691321483000000	1754393483000000	1849001483000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
44	\\x650c8e3888f3227d1478451bbbc17708795c55117ccdf719682a72024fd6da0c841feca39eddfe9dcccb022d01c8c7e8ba734af9afd2c2234dad6480425c5698	1	0	\\x000000010000000000800003eb729ed6ada5c3a6a37feb0beb163cf8c60b97114f1a0b6045a4c4b2c0882562cb01e60af449b78187562687292d4bf01456e671e08508aa7d73146aac3e1f3e15cd6ca8567e0d81191efb0418ac0c33fe5e430ad4e930698f0530b10a6f80fbe76acab12132efa4789989a5fbd0ec0d60d1c90d67d132fc398658af2a6e2711010001	\\x70461cbcc1cc6b656cf4aec4c1f2c78cf3b63e654684e4300ad03ec5afa2f17803f6386bfeddc44aac84522bba03b6e044a03555f3274d73103a989e76c3fb0a	1662909683000000	1663514483000000	1726586483000000	1821194483000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
45	\\x679cb6ec649887f665a011a4749e945ccfd978e600aaf52d1f717e00cd5902d6f8539725a10f42ed1c65a672488b98a59c961591fcbf8601078fce265bef7f6c	1	0	\\x000000010000000000800003bb016f41914022eab420daee5aee7bd64290ff75a61c24acf1c2b0fd70acc49f42a527a3ded2f6708de80c63cdb83bd860206c5ae98b0a5c6e37d62fc34a334f7b078f81a72d453692429047da6e73c80eddc85c5ac629f3978e0d77f9c7b15db0039207770aca15490151d8bf2ab2948324790324da6a4c360b46b53f7cf50b010001	\\x28d530c5976ce54eedb4ac802febcb98118a4417243dafc849671814e02ea8871827efb77242251b5c2053f2898da229e7c0006034b0eaa6a22bee1122f63403	1669559183000000	1670163983000000	1733235983000000	1827843983000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
46	\\x6cd80d7ac2f12600811fc64f6a5e9aed22433d8f9dcb237aca2cee97dce1cb80c1a4666cf2f178f3db394b3955b6996bce19b184a65e787a3e0149167320a124	1	0	\\x000000010000000000800003f17be007f83330065d4f2008863a2bc19b582686b188361c551106a91c84c4a352c2a8804f2cecd8c131e281344fc243b55f8448f59a999b0bc8ea437bedfec3ce19c33ddf755c755a7cb7c96de0a62b09cc9453ed7800b404eb97b100592b5a01f572c38de2218a63da1c5cde8725da70c28268c0811722c02f2a9c72ddfd3f010001	\\x3caa47e54a6824989fd73471164a0f088389523106558be06cdaf03b8025c74667b9be8348932b233bd423b873fc3b15803f7cc2501d8c484de92994497dd001	1691925683000000	1692530483000000	1755602483000000	1850210483000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
47	\\x6dc8c08afd4df119d81a5ba410af4ad7ea8bb59d570cbc4222c8581cb886cb81f516d49ec2ba2b77eff03b3504413bcb5966ed14520301f0ab1134fb003a704b	1	0	\\x000000010000000000800003b5057365bf241fd5769c33e980543135053c9327262a636cb1a5f057fef00c569e7b48e9c0557272c4e5b92c5336c1e43b887f13b88d8af7097a251c8625dfdbc241e99f90cab66be2fe0462ab15b44c3afb1a34e4d70d57d851ca667d2e39709cc0066a7ad9ae7f226a4c172682517eaf1bfe73597f13e56508e2038612bdeb010001	\\x20476656b9b46268d63cd404abe50b45cbe4404b73764e517c1af48531444b4cd4c8547422efaceebfafd23ca4f3d92fa753c1b50e9ac4f76b0b5c78518d3b0e	1687694183000000	1688298983000000	1751370983000000	1845978983000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
48	\\x709043e3f621eac5735766e29b217d639160eb84da00bc46ebe63c7d4dffaa640d05b8375f2a5ccb416c3c4e386dbbf4cbc3da79616fae274313ba03d8a30a36	1	0	\\x000000010000000000800003b58d66be3f5c789dfca2960374d4242fe73b111f1a26be1f058e7e77ae18a55d2846c0f9d00bce221ec3e47c56c3fb6d147c13c5ac79b055245e9439048f1217eca26610b4a44855ebf5d32c238828210fbcbbe38347f74b4fdbfb476eedb62a25e7c7678ad51b1405c90e19bdd81b750c15e2280a77740903bdd85b71280135010001	\\x9f845b355019655496b46c63c19127ddf9a8d004fe5e81af525c8d3a25d3bf5b3a0dda4eec03bf155162cb3077e19b579bf820f1f8e751356352578f23e05d0d	1688903183000000	1689507983000000	1752579983000000	1847187983000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
49	\\x7158c11ba285d67f3b1b2ce6aa7b88d2f6517388db39a75576ae0f01ccc93e246fe598bd8f77d6b68b5004c00a9b55c868991c5fb7a3538e123622b118c6351b	1	0	\\x000000010000000000800003d10d2aae7f3d33b5f89aca0d4d752891f9bd1fa3dffe019940c41a2b0a21c619b675a065784379ddc6979e92b20ab61d3bc423f5bdbd8b2c8be08601747d5cd4a00164f5993be5c1780efd0970afc4866e5c2def96ae53bbcef28781621d4fd85bf8ed47f1a0c0e8d19a2acd8f1083a3ff4caf28f5f3410c1bf04d759d512203010001	\\xbbd508bdcdeb0f34043c5869720c02a799d7d686aea09ad63563ba30b328de530420ea0eb996728a89f64e32d326a30c2a03c900a9063ace610fd1f6f739470a	1690112183000000	1690716983000000	1753788983000000	1848396983000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
50	\\x7150d46cd6918481583149b25ec5819319cb604bc0ae9dddc63c112821cc5e7c2c11ac9b06ebf75cef9100b3e557b4636b23557014ff068d0cff79f644b812ac	1	0	\\x000000010000000000800003d55b1bc6f13d1d753795f2f0c9209cb1cb04df6bdc41ec5751cd094b8a5bed5adb52bb0509cbc25844c7b786201a3dc9685205782a19570ccb848a673425fb1722e101f56f009a16124e94e16eeb5e17fe4a642190797aa6c90542f2dbe511c8e6d82d1f639682ce062976271c96a93c938ef48b6ec119d6f1af24f059f34c43010001	\\xc001582c7ec4d573d31b34e97239d3c659c1619f866a1f273c792c2a716871cad0717d018abe2f38d831c4fda0411d7fbe4a88b1f386f907813fff53bf165701	1687694183000000	1688298983000000	1751370983000000	1845978983000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
51	\\x7320c6ebc9be7fcee3d74a77c8b78cbd860c5e2438fcea6ef96b99b2e787c7805986f2c913192191fa7b90c6c215f9d7b26a21d0eef0567895ae6a9d5d517256	1	0	\\x000000010000000000800003f93b9917c218b8a4c995630af6d7e1b45696ae4c28fb7aff7e18c7cd1b333f45333e6d788f5ef481f6ee1d2ea640d06855491c46ec204aacd4be9c5ef17abc01fb3091553a61cb5e4ab9628b7acc8cfe86af0d11640e41c1476ec34530f6acb3a82fbb1996c6a16aa91b87082b83d6adb7088d15e976c208ece8e9b1d274ed33010001	\\xb7c7f9b5bc37d2aede77937de716ec0feb16d95cad92b0e3e5234dcf67c11f33e72bdbf813773819b97df97c74816de1fcab5a0fb9a4de5f5ae228977d0fae08	1679231183000000	1679835983000000	1742907983000000	1837515983000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
52	\\x76a804c6f880dfe83e161bdf32e09986a82f7684526d30fd28217b0ad7b1dd56887746d8d074838495bf42145a7bdf97b69dc23035e22e8a68951da01d1a1806	1	0	\\x000000010000000000800003c31b6d5c58257e02195201a0b988940ba2ee3840f4c661dd91ef31050469579eaa9f0511b45e9d2e6a89f78229b1db1d95de5fc87cae9a7b9da99c6595d2de94f7aec6b58581c19a6411e53c08d349c6265bcb7c32c6c99d113bb133fbb0b1e3cf0d21f6796e7d7de5d706c986e325002144f56e574b29778306bc0925d9cc81010001	\\x0d7fa89ef9280106b970ec59b517455c31b5453ac6e5b95c695c80004cac89342f0816470cf902376d302acaf53383105dc7373ee81bec3c164e77c6f25b8105	1688903183000000	1689507983000000	1752579983000000	1847187983000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
53	\\x77286709a0da433b8202d96649df31677a23bbc7c14978011b3a527843502c57173e079f11faaf9d4498a863582651926bef7cf335f34cbfe64d5668607f61c3	1	0	\\x000000010000000000800003cf84fd6884dab0ae59794338d0ffa389e412ae759702ef4ee6bef4173fe9da7780d66802045a31d153436534288b6a8643e17a07c47700bae7fa4f9fb3b5846aa5292e428942cb671341c12f326a785d1b0708344227842a7833472a953768e9aed0bdcefc550e006facbe0a33a7d3ccac0ed87a5fb8a89586be22834e2aeb17010001	\\x3d91cb18a1a5d7a208781b1aaff4109549619b5cc21651cfecdd46296c6f83c887e59250d833de099c82372d2d3a54f46b7f1947d4780a5a34304c7dabd3b703	1674395183000000	1674999983000000	1738071983000000	1832679983000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
54	\\x823028c1b79c86d3bc99416b714903dec55dd3b47eb8cd4f86f2ea898d36e5acf21fd45970a33173e8d860c8cc1b52b0dedbc60cf02f6b4ed2ddf81d819f381d	1	0	\\x000000010000000000800003ba39deac69b2a9114e5986ef576fe7f78818d4f5469d1f1e101aced6db3c6eceb65a6dedab57c4a1c43c8ebe5bc9ba82dc70c263483a8106e3123edd497d657339fc983733580645f66186e73e062ec49d64d4b685455c2dc86784cb628cd6f84ddab7ea7ac22d5ecb492d326681301e840dc2e64e1cf7b8f01fc379ca4b64a1010001	\\x3d5ea4b21dbee56b98e6f3b21531187ed22315200b430c2cc04a76e358cb851e25d52215238a5fc6bda464224406ca61bbf44dcd187c5bc997c6c73ea217300d	1662305183000000	1662909983000000	1725981983000000	1820589983000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
55	\\x855872c975af39a86d723c6f9d6d44300aa894e0f349d981c0dcb5f1d99a216f16c842f87165d4864f59b9450d6913817e68c8eae552d552274e042672a93f06	1	0	\\x000000010000000000800003add74369881e481653e257549ebe48760d47e1faab934f8f410fb2647d25194bc32a9fddbd4289f1e7e5227a94daef662623745a08de2476691071d3b39db7a618b1fe2ece7196ebdf4cc15eba8da3e1813ae8e01825414c928dd4cdac14250f7b279fd3f563b8a4c3b55c24a61849589a734019ca2909f741eb0eb27cc5636f010001	\\xee1859aaaafc08054479615a7f39fd925ea2776da4a8aa4e0eb02702fab696c69ee2104ba52d708f053ed6a1fe43daea47573ba20caeba209d714f8978aab901	1674999683000000	1675604483000000	1738676483000000	1833284483000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
56	\\x8688740f29ce05a118e08a3dfa5e264bcd5131fbd4355aed5fa9d792c33884627aee3d1c4cc37e738643eaeda6ccfa737de7d165ed98184ec97d13f009a1bac6	1	0	\\x000000010000000000800003aeab1a7fb66502fa1700d082bffd664946fa33ef8a52add4769a173dbc16806b8f8a212454f5cf7bf658b9f2cb9bfd04f4122e2705a94abcef3f162d6ba4f0ef1ad06ca5399c86f5a24ca46fa9852b474d548ec8b5c8f6e4eda5ddd2f40a286de5b85b9dd03bebcaa487be042771fe47026a8955df2f555780cee489b4fc0c15010001	\\x464ee8a9bc62e78c5b9d4b678e337ec718eda26f8a3e5d1d21a1b01943925fc293090ddd03bfb15a8fa563bcca457c22dcfdd6aeb8d4b82f3d7fc2338260fb0b	1667745683000000	1668350483000000	1731422483000000	1826030483000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
57	\\x86c40c7ab20774d3375dcb656d738dda3a2bb433e653d962d4442acfc4c706883f08d0c25f574413427bf9f042fe1521d228fddf3658bef15de02ad0dc49045d	1	0	\\x000000010000000000800003c6485856f3d9abc3e10430801a73defbfb246f075dd0970012cb23383f8afc0483609e854d7cfaa2b6e1fe718bcba12826cd0a59a1b23c77038dfd1d64289c4c0f203c1ad165b65677c349dc829ab2a3e81ac86bfcf60a6607b21cf6648483c3099365ccadca8d6895d5c6ed2db93ad7ca4277d6573916053cdc36b5b09c02ef010001	\\x4200ad8dfd84b3ab0f35522c7159c764cb2b40eeefede5c9f821c021636da11b31ef3e34f6a47e4c16a77e476cbd2f7a2ee0be6791743091a265ace4b3307b00	1671977183000000	1672581983000000	1735653983000000	1830261983000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
58	\\x8cac2727239301c9808321e5da4eae14a425ee9a35ad29a8a772cbe0c9a6329de9160150a7a76bd1ab9085cca15b7e84fb2b5bd574eb1d1f2ce744ea05147714	1	0	\\x000000010000000000800003d98ec13ca50ccca114668757fe678dfa6ecb6dc310e34a39148e740cfc3739f22c84843b887346ecde26ca1f12df193f2f638270defdc2609bc9ba98516bd652b92112d63d7086e8f03265745ae664c8406693275a5f66832396b0d3508f929f16c3d0277d76aa3103a73b82322f0ce143958b3fd12bf7b667480bf267394845010001	\\x52b2e7fdaeadc4577e2076e10869f348b20967a35352afcd70c6a93851aab5659547c267efae5f345a1ab47d1a71ee81579dd5d189e7dd5d403fcfa33e73fb02	1680440183000000	1681044983000000	1744116983000000	1838724983000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
59	\\x8eb820e4c91e74bf53a8795def2069a4c5fe68752d1ae315fa3fd4077ba7cd659a79b636fcc1c4b760fe92297d022d1aba188b9bfffd5b4681456ecb7df8a9a3	1	0	\\x000000010000000000800003bf582882e3094d2df1222b2a7256d9a3336cd68fc15622ce1afae6202d72fa720ab54f9460b8d9c73888a39953286688925318c46b3ce8dcecbad83ddc199b50d0e7d6c2056f9609398c802a712708b987bf332265283b3f55795d186f78febb590c23d93b867cde3638567c43aca1f854d35670c000e373a1a4328715ad3be1010001	\\xcd7f5dd35831e600056841d7fde03662c3da33e0efcefb7fde5717feace912ee356ec3e0f24b8d1882176c1a2bbdd6136f553f40becb1c41162328ceeaa2060b	1685880683000000	1686485483000000	1749557483000000	1844165483000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
60	\\x8f94d240aa5cb8e17ff7aebf5713959abd67b9b9cb0d1454e961d11c55a98cd797c51306424f9954522bf8e7e91159147d203a6918a9b839cdcf1eaf9fa18437	1	0	\\x000000010000000000800003ba7ca5c88f28a61be7aba4f05d002404955a2be039d7bf42e80fd8e353cf2355965a104f4fffd0c90b57c8818dcd0f984e00ebb9be84739a2caa0da554261d0be3341060defd7964b52047fbc97a703629ecd91ccfad671f48e09a70498092cd7a92a63f75ef365ec02f3cda481c3c52654be16434c0436460170dbd81fde723010001	\\xd39383e84e2f4ee56b954e9657e79fdda6ee51083121a2437a348958507d17ebe3c640f2e880a256f63d8b18b1c9279205f09c74bab3aaa80bda40c075258702	1672581683000000	1673186483000000	1736258483000000	1830866483000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
61	\\x8f78eebc1d799b9ad41c9c1901ee0bcb60fec980fb1f5f6da07b6064459512a318ddacb4814cf9a27bc530487fc4476200b7675e1dfd6f3ba7370ca2b628748c	1	0	\\x000000010000000000800003afe16ff7674c148f0b7c9004c258fcec3b9ff439da8fb610343a0b57633183dd55eb1816f3c66414959f7b97cefc92ff94a8b83e113c0175485e6651b73ffc92c602ab0115071b07e360628ff644fc14e84a3af5df2ab20b60b1d39ecde46f26d6d95def23e47b90fcaad92acc715c2812d9e9908f79c06ed7bbd0cbe6ff41ab010001	\\xb7111cf05ed36edc2284287a651eb6bb2a7a00357ff5b0d739b3644989cda32e95c132d34e3703439a981d60ef537f4e5d25408538fd96288e13313a96dbd70d	1676813183000000	1677417983000000	1740489983000000	1835097983000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
62	\\x9078740dd27757fa13255c486dc9a7ada67082823dc6d785ec8010735f804407d34b033a14015d33ac4895689d0a4838a0bc15b561e5b32d45f967bfd71ae744	1	0	\\x000000010000000000800003e9e1c87081ac922f8dd321e4520575315b0317962621db0be8db7ac3db5bc5532c5c66ab0af3fbb9c014a26d9d43421c1edf6d74eeeb13248b88903bb1cd44399a46fe5ee5686620ef674e770221e29709f1f076d9b098e4776a591388e891b12c43a607ba7a1e81ad9b974442e5d4edba7ec28e8578e3abef596c6c825d27d7010001	\\x410c6cb242211d19d3c19cc0ac0027c874cfc79023ed9d2d5f3f8f67d485a7cf0fac10abd8d43f4f5f4cff728659829d441e2ecec0943fdb578c93ec896a470d	1671977183000000	1672581983000000	1735653983000000	1830261983000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
63	\\x910484aa3eaf5217466574876d267957508d6c8d9b9e0140daeffc44fde8fe49f9971a5301b9962db3c347af1ecebc320f3dfe4d02151776493987465a04b6ab	1	0	\\x000000010000000000800003d397ea4a32ea934a9c131b45e622c51f8701d9c587db9f8b166cfcfb5fab5b6b78a4397b328ac8765ee60e7b285a1e6af55b32ae458a68ec26f9b0a582c97ec9005743a673bf1cf90fbeb72096ee4c70252c0b15097655e12c6b938fda56fab6333b5922309a0db2941b1d115eb39a0bcc6085d87e3724314a8535988a914461010001	\\x92e180b3a0aa6ac19b9ab151e5d1d84ce9b7ec5513e6e012f8a9d8462634dd8fc6fcf028ef1dbce9235dbf6bdc476315794584bef5edf24156ba0286cb272802	1684671683000000	1685276483000000	1748348483000000	1842956483000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
64	\\x91c8603244a7855d64103e10db1345e2171b8b0ebe12f665c207d48ea84a05fe84674745ccb39b6d2fe02406f68f38b1c90982113793a4085cad0cf3ebb11676	1	0	\\x000000010000000000800003bdeb269159316439b8d01e406d319255ec4a763126431c3d89829f0cc901fce1b9b10b11d3b41f7b71eb15ff18a161e21a013aab690d58bc32d46600a9970dba9b02b82a51e4ad31ac85ba9ef5361780ce65f4b0c95cfba67bd4b83ff41539376ff3530de4e8f14a19a5364995bb8caaf0ecf7c585867efc25ca10a04b94f837010001	\\x2f074711bb33ba371b872372d0fe259e5e79b292e3e7bb05eaaa0d7824a69b1c5284119d29d881e07553c7031d76f67846f22518978a9ee74cd643e9e634bd0e	1691321183000000	1691925983000000	1754997983000000	1849605983000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
65	\\x92e49ccfa2c89fe5d739ddedf17a4e0054270274e89aba3c7dd6053973121a59c9ebea817d0502a6345156a589297e542bb72f0113d4cbfaf29eef71699c3dc3	1	0	\\x000000010000000000800003db292aebae7285a291963cd381ed067ae770bd08a6477bd02dc4dea452a200fc20f94330879a9ffe2b95b079140877036a97d8f74c9477ad941b821917d70a2669ec7c74629bc42310940120c48ae2181794cbc5dd9b1687a447f6264a64a6ca7287470b93e4b2e68ad7f9af42773ff59b6a4064095e7f75b202370e0a939bab010001	\\x32efe551c716c992ed91647e5c5bb0d411980da5e5bf9a1bf49760b735100ac54d24c3d35a84d9e0bac724fcef7c996642c65958c0fbd32e5975f1e25bad4d0c	1671977183000000	1672581983000000	1735653983000000	1830261983000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
66	\\x939cf79ba1bbb62ba77e870386fe77ee28955033abe0f057c4eea323ec1f64c1a342a6c504de5252eb7ab7cc2ce7d3c7ebf029b3b1a4d2a41bd61816df340341	1	0	\\x000000010000000000800003d4e8883a208d3fa6d555aab5f40065bc1e9a7343458f06611fc6bf69f4cafa94943ae49acbdefff832f215bf9d5a8b08a1ba0e29379831abbe79fc5fe8445b3a8b717ebdf966bc41beec5cfbe3d8a78372ebbeb86f7c71fac847203e92e8c941e8fb97ec24a6781b116cf6fbe618af2a6e6c1408a77625100d1956ff8045a6a3010001	\\xda9fb4195c532829201ffd100a9d627140cf071135fdad5530d495fad99873d2f92adb5833d20e04bc33ede9db533f616edbb6eca7ef9f237630085a50dbd807	1685276183000000	1685880983000000	1748952983000000	1843560983000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
67	\\x96a0d880c3c1199ebcf3c0521d3e877dc083a48f1e248fe5b93620272a212fc380f5e21be33bbd9efb03125bffdd52bcee51e5fe549d4ff736382436ef3ae9b2	1	0	\\x000000010000000000800003c45b967a002b9b4fabc2442922265456bbe83f0a51dc29c05d14fab7048d75344b80fb890790d8762e29834f62fb6cbf2fa258502e7a99f2d7fab2bfa71f5edb5416c5a99e841ef063051976b89bd7cade3dcea2646d988b93e3c51e35edf429db02887be7454267c254a372a0d2353a5c1ad3b8b6f4435540cad4fc851f4007010001	\\xc6eb2980de1d76ff1470f426f74ae3a16db5959731a026148eb8801b1b9543d4d2b50a31ec2abe0d46cf84a377d1b4fc1a9bbdb9a3b75899aa319d2eb1673809	1660491683000000	1661096483000000	1724168483000000	1818776483000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
68	\\x96cc70740df031b4977cd3cbf23adcafcd55bc3e56e35d0fd9234e3b9ca0fc2162cb4c1996253383d2252b2b7bfeaabbee49b37345bd46998d76b7d4f7032242	1	0	\\x000000010000000000800003a833ce41bcf9b477fec24bf5d76031aaa9b014ad3a15bc8471e45b0547c521ee0e92f1abe6bb52a984227c61d085889435d17c31272c9349af190e0abbf58f2368506e196f984eff97e7921fd4012aa6e9ac179592a7a99b2a356fa72360af879a21c652552fd557f71fd047dd2fb8de2ec75cf124aa91fdebb35b1838369081010001	\\xa5864fb669f5b265219d638c263ca769f24bbe6d8d56155b274031d33bf1c94ace3a983ce872049b7c313b35c0629d670bcce0b08a9cc2b9738b0b04d575170d	1682253683000000	1682858483000000	1745930483000000	1840538483000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
69	\\x97f4824cce3b87563202bf8484eb5f2f278e082b3d514211027938bba3fa119df8df07148b0701ea0eca688f99c7e8421314ab36141095a7497b96db2cdb52c0	1	0	\\x000000010000000000800003a6ca1770ae04f39778c38cb6fe15134272e5e5639938a3f1bf6449ad6e1d00d831ece09415fbecdb71ae6d0b00b15df34649ece10d2ca4d938ae4562cd1e57bbcf5ec049aa9062def66d62d069f4bd311b20e727e46e19052d42771f72a2f96143564319f938d972bf9b9302b6d65f0daa62093b0ee6acd676465474b0b22ff3010001	\\x1eb5264124651ae029d3ea33a19499a21470a65fc3096a9a3a08c1be82f081856eb86260cc4a9627cd1dc0c382611d3743ca02908786b25a294631d0432d8f01	1688298683000000	1688903483000000	1751975483000000	1846583483000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
70	\\x9cecb277f26aa2b22b3c4bef7b08a86579278d72a438f445a9508744fd2cd258a1e4e185b58d66857e20bde32352615866976d0fab342271b2220140ef90aa92	1	0	\\x000000010000000000800003bcd03e84c1fd9c88dae610a5a4b8d6d95fc0a31e5edc4771c4fcf7b4522bc3f3622474b42c1fa5cdb03743a1dee3f10fea329213870a9877bff2ada53c65c5ce8b85b521556e4ef885f303f931329008250da49dbb1de1e7143ba9b99835a966ba31393f73ef7c8abbc74e9361bd735e8ab899433f69b195be1df65af1f8e6bb010001	\\xbd96969d7ac38502850129b16680cbb3b51a0038c40a89a61b3200c5fc0354b356b3c5fb4afd64426dc82830dd9e4f7c3482d1270aa0501507dff59581749902	1665932183000000	1666536983000000	1729608983000000	1824216983000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
71	\\xa0e4fadf20b556975d5b564c4f0dd25238a09e1881470eb03d78d4a3586d27ef1a7601ab706e9d4a3f1714dec68210e6513ec8fa8fc4fea01687a0c5ec5ac8da	1	0	\\x000000010000000000800003bb369b6fe8b71cca0215c3649f0c16fcf929e75610495e9bae302c2fb28039082ed8a08bc2e64d2bff0f5f3f26979302033273e5fff56c150ebcc6967c173909f8227ead65165d51d40eb64290bcdfccde236cb15119120d8ef72459030a908404af054428ddc171860a73469003fe5b345347d5db62d6c66b846e0a7b902215010001	\\x909b1fc8f79ebc46a93c033cdc73426fb460c3a4f445eb94f779f01a1039c528d0aa874694886b692c0eea7493c32d373691870c157ccf87f20739fc6c46fe09	1674395183000000	1674999983000000	1738071983000000	1832679983000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
72	\\xa138e24d1931dbf19aa0502bb1193dd3f8123ea1f4bd5063a74818d639e422d5cdad331675df49e42bbe497ccbd336d92d805ce298a48873ddac6ac80908e040	1	0	\\x000000010000000000800003e521da56b94c8671ba91a5564644ca473200fb279d2cf9e30916351398213280e0206e0a96f7c8ba631e1fda633d4480628f93ba860c137816c497fb468d63f09cf87d8cdc4651736ce1869eb74e1dc7fde9d2e08a2a72573b3ca08af14854b65ad4992a78e0cfec1a9414d710de87d6a7a69a20e9ab676735d0e1bc0bbf9059010001	\\x89234335c5e817c4c4c0dd520cbe7ab13f5343d636fa928e7ae4cf6a8243a9427eb00ff0524f043510f8eab6fc4a4ed1d7d28a1cfdccd8b9fce43298643b8f07	1674999683000000	1675604483000000	1738676483000000	1833284483000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
73	\\xa418b94246e75506568ffeb04d22307a3d5b9da4cada88677ff0036d82ed8b197087db4674d688effbbc28c3ab87d47f782f80921500010d55e3a3c86b3dbc18	1	0	\\x000000010000000000800003e77c19f81cc6ac5457eb07a668a04bcef447cc713e9cd9ee939a52e8e3560738ca556f84e8cdb2bee09d001b7bc4336c5049ce520e5c27b1123fe6288d6813ce0fbe688395307e36a7dc8b16883d00f9de617b39f404c6c63bb532024107b6e1b9724cb3c3baaa3f4b51d89f28b2e7f54e215f00a6004e2d206ae68994d3f4f5010001	\\xa2860865dfc62d2e4c27a5d32928a9cf5c897d1286a2df67553389639457b9e56c11b07b3c5db83d853d17e3d199a30a63ab91e8261440dbca4851a00172c80a	1661700683000000	1662305483000000	1725377483000000	1819985483000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
74	\\xa538a073a9d841be1df9629c54b2a7f27b879c96125ca35522ce805ef238e6f0daa933fa31967b182ee660843419c8824407a2303788949407de423c46ba4c75	1	0	\\x000000010000000000800003dc37b71e3ee50ca964f249ab8ce1eaf63970b4c8d3981cfb62b1e6aef15f138e60eb69a5e536e55f888b7a15fae99e554230ce9f39ed32d529b2316f18cda25b3cd187a1e1bc98567c87d811cf76ea4a2e77371008001fdcc7dedf2a91308926a4b6eba8a715e7a0cd4bb22d474adde5c91a0f6992d7d5ea1350efa64ea2e9b7010001	\\x2f728e254ea21283cdd3d9be6ab67cba1fb8f960a8a1101c860017b8d430b00f76e3ab046f00b7ef6c6b3d5d0b95c8f17a62e68d0fd06db96c4a85bcbe79bf00	1661096183000000	1661700983000000	1724772983000000	1819380983000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
75	\\xa5c47fad1f2a234fd2b158e8a467f7feb31c92bdede1b6307cceaf6def11b1da785ca60492ddedb25ef0e2227074644cf1b8a52010ffe68a0b4e6f1507ebab99	1	0	\\x000000010000000000800003a6baa66a1797c6a3e68710221af66dbf6da6416a10ec59d9831c42597871936257d491ac42b4986b4f8f0eff4da2934413cdf8e7092c814c0517ff851e86c30c6becbe48dab48086739910effcfce4bd78837ba95ea7c51556326a24ffc995b54f68bea947c17942d63d2f94e576c14708960e9968839b8a0166df7c5a7ac3d9010001	\\x66f4b8232a1e074cdda0a154e37f06888b0b567c693607bc43a14ac97ba2b0e419573b192b8d29c5101cad649366a1ec85fe6f7976f082b2194c6286cc34ca08	1661096183000000	1661700983000000	1724772983000000	1819380983000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
76	\\xa6306df37f0d963fb075de434f8f3fea0091750bafd500aa81ee5325f18c602d700da7085dd991e32e35d01cd7230ba1287d302e5992a8d5cb4b090cd3155066	1	0	\\x000000010000000000800003bba8febd35565da4eb6105d20e0ea61037fcb1215ab5566df46e40ccd71d61302263689f075f5b45f15505c2df08a7d85d29e8c72ef26aa7fe81d8c26efb898e00bad8fe0fdd954d7b0dc1951036778e2afa2df794b0773826c7ef2b90503f9587381034cb772e0d457a292f99cad88508050cec050c15cc90f016943118fe17010001	\\x70185f625e12897141480d102afa97520cd45354d800c5e7a5b8dbd9464c3b6fcbaa8d460df5953b6f98c055bd4d0c83523d0fc1adfdbc4edbb41275b2939801	1665327683000000	1665932483000000	1729004483000000	1823612483000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
77	\\xa6b0e9a3daf0349ac650f5031f65e7816adce5ed888cd5b528306a092ce0c57fa6623ac968a040e3c01884ad6188cdd8ebb12b2c49fbac80abbe48b8af6556e0	1	0	\\x000000010000000000800003aacdb0a97196e0ea79e91b9596133c0337f8e574cbd5a560de6ec5ec5439e980ba6cec76e3435d649bb37515e3d47374506509736fb5729c764ad3339ae4f6dbc886a41354fb2575c03a1e3085b3bb0f1a00079831df242628b3a5888b6b7001d2952eab3e9a34a53bf3d5957acb2da091e9a77f4b9cb4060c8222520ea100bf010001	\\x5b3d1105b29c03e4d2a10c8bbd18e4db333a7a70fe090032c2a4f75fedba68c7f3ec9e39423ebde2f7a8437762928434f01bd7a6e114502cafd55a012f691c0b	1664723183000000	1665327983000000	1728399983000000	1823007983000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
78	\\xaca8bf009cd313327b4f8da6cda1abc4fd8540d0e853bbfd4d87d58db336222f717d058b0c0d84657b9501e84ab25b0b800cfdf9b6838c6baa5e58f7fc0e7ae8	1	0	\\x000000010000000000800003d19a00a904c2b0d0a37d136ee944e9403a49fba5ae84295a69f937b5a0572dbcc278377626e6ecbde08eb7ca06ed41488a9e55cd6143e0f53bf50eeb09bcd5ce536d950c316f59ada0418ccff486c774720e2b312c45705c54ed0a6d2d3b7eaf3f611ae95c0a93dedeeddba648cc2a1e8804e4f3109144e5d269d6664a81c1d7010001	\\x5f0e96ff89be98af1eef1f81cb3b5a348c104bbf95f483440df01fdd98734db41b3c02f73e37ba1dba57562ba72b71e836a0d86add0d4a8ff8ecddabe6dea603	1682858183000000	1683462983000000	1746534983000000	1841142983000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
79	\\xaf1c63ed43f11277a88ffc4e7de9dbc0eea93952bb1b2650a7d9dc04e872b1480901f894ea9d4a142c1fd687d18e984158cadc4e494ce22378d2964da1d8ff8c	1	0	\\x000000010000000000800003dd8b6e0eacb69acf096f25fc564b7faf20793b086529351db013cc84807bd664b5e7164c8755f8d312d5b6cdfa447c1fd180e59bdddb549e1f8b24541fdd9be60b1582abcae5357f788f59621ecd3a3cf7dc7af2ba4e9853a5c2e55861020200b9f4ff81ce48d8b0d9d431d771a0d48cfc8a26f1b2da15d363988ca58dcad52f010001	\\x5f111123a190128a514efc11a871cf712f0dd03bc8c200ef0ec36d97f414c824e2046ecafe985154335fd32d837194c4adc638cebab8104adf58a4d763884702	1690716683000000	1691321483000000	1754393483000000	1849001483000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
80	\\xb1181c34116c56b4ab5d363c25987fe020fc9636e9e01dfd5123ea496ecc97cb26ce93a5d6558e70f4b105f48f65aad9f32587125b2fe534466f14e9267eb7df	1	0	\\x000000010000000000800003b9d3e891d492177225c9ab00be30a01ebbdc414c95b396e5d66c098c6d102e67359b157f55ba08a9ddd54fe6df720d53ed68805dfd5ddb8cc8cf59590a683ef4f55f9f548394adf87f6055a41f69b394c20a0c5ffe394a03b6875f750f3c13350ee894d3f8ddf6c9ced4d359cd856123fb2e15cb677710782e102e38b672b0db010001	\\xe031d82c67ac2a35d78923965fb4e6264490deb9bbf4098064231e9c37c8d386cb7ce94907061dd26ba056f671a7bca57a9d3b9bec3ddd8478a4b7f799559a02	1678626683000000	1679231483000000	1742303483000000	1836911483000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
81	\\xb4b09be534e6d2f64c036162624cc69e18950c38d1a9f3d9935d371712b1e6d30ac0b3e016b90fafec4923c789877068d18f190ad9107b4d12fe5f4f65e560bc	1	0	\\x000000010000000000800003ef5f49a34de46cf0688919d27ff829602e5232bba0e49b1ecb5545321a7a10a42416ae2dff917d26d1f09cdab11a97bd25bd0195cb958a54a0b0afe1256c5ebf6fde850d9582d4a3f811c54e3c52c057c700d2778ca60af8fb6a9d66f80aa93cdbbd0aba76a8f91f16e6c64edcf34f10ab7c6d5a8dc445604007ebee89aa3e6f010001	\\x2fa2c2c7ef84bee9b3d377eda3323b97c6646dbb766d949422ca1d58fc36373e7ee9c7d5d0cafdae60aa2e2429273e68c7f248aa5944076baffa4979feb26e0b	1687089683000000	1687694483000000	1750766483000000	1845374483000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
82	\\xb920a6f8478bc3eecf330d36d213c8819637e1a697fe6885996e7d3b3db5a6ee1403afaa80358ea5f8b132c4b0e2b92baed2ab36882f68d6a0cab110e6221e3a	1	0	\\x000000010000000000800003a8c5d3144b9dc949940d15ee4c8340d1cad2d346113917ca4546df3e9de33664df268cef0292b33bef740d934b3a8f5eb2d1f497ef66a462517276bcfc9a7536282f4a4e526aad1bd02c64ecb3a6d70a1864673225a39e04aaf856c4660ab2fcb87a6f706050eb35bd5fafd55a8c44efdf2a0d5cd2d016fa1c7b471db3758815010001	\\xd6f7fc28e48fafbdd1834ea5918ceb80f970f68efb54eb9b84cf5a761dd5420543cc4688c7307e52ca6a67020190f5bcdaef1816fcbd6bf5f0d7aae1bd10bb08	1670768183000000	1671372983000000	1734444983000000	1829052983000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
83	\\xc1ccd96c23c8636d2fc4a67597e929e98ccfde48c29f4638b49e7eb14e7a587e6ae369483c47924edf541629dc327d1072329513fc84b484c0b7c986a5090d64	1	0	\\x000000010000000000800003bc2d64a0fee7c1fd6975bb2530505cba8d4f6fae3146d35db31d0f971d9c762d1f9384ffd8bed140fa4361d50714c5975f72a1aea7daed7364af24328f683d4c05ee07838cddb02ad84c2ff9e5ce7d201ae6c55e2e9ec1d04a17c6da11aa8326810e038893f58568d9d0289eb17b16d2437a368b22b62340a332d7119e5e1aef010001	\\x4d70442355fed05091a22fe7d442347f768deac07bebe0ec8aaa848956f89ee55336957d80ae8665adb4ec04f52212c8e3fd0b6f172f116ce83db730ea958a07	1665932183000000	1666536983000000	1729608983000000	1824216983000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
84	\\xc4a8bea0ab8f694ac38398e4843238790ed97e953b0c8ca7a4f5e4ba5e33043fd834cd3d43993192d1edf269307a20ad24b089f63e53505e383225a4bc06fb45	1	0	\\x000000010000000000800003c1ce2f82499ea64bf2f473eef214ab886bc7f5fcaa17451eb8c9b3ceb014c8988fdaf483faf844a6900cd62b7a64d431316b73c98fcfa6bf99e5c7dc7f794ef79520ab9d4f5fa81736d6916a92747a072c03da16b275206d7121f8d2681d84d07cfb639ac8fb71174596ef92ec543128f09f33c1cb5e5a827f772bef62b2d21f010001	\\x56db29c54cb215d2274a78733daa0ecebf72b893a6c62af2e8537c9bc38098d530d92bb275bc25a575b728ab0b9ebed5ec5ece99e6abffe29d90c6d9d7e0c90f	1667745683000000	1668350483000000	1731422483000000	1826030483000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
85	\\xc47042a3bfbf77decb85427407db3030efc5d1b0242f964a8a52a6083f21fcbb7ac827a52e2578e06b5e25b7ea331b4d9ca4cf5771839f0d0751e114fcb8ee1b	1	0	\\x000000010000000000800003ac413b6dfcfcba4fa116512c4b5c2abd8bd22b700cbb3b97011f1a44e36535be18d142c776c9c3915888e02491644769a5f427e70a55dff97b1795e74898b05a95003a0b8280715eb7e8609afed0eea57e5897869927f879cbfa20da5dea9e619dc42660d1e8110332dd18fef7c5cc3fb82e8e3d7f555de1a9215372251c820b010001	\\x81741b2ea7365816391a2a506caf8cb0f8ce2d9266d52460df5e08f941a15b0b5685e98ec2c5f4f7ebd471344b5e2f5086b14913398bc70db7d8737bc3d62d00	1665932183000000	1666536983000000	1729608983000000	1824216983000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
86	\\xc85023e24a10e805e52f028db5db0fd743eee0e60d11b29c008d88ffbf56d65bedec83ee9c42441423058d64648e2cbb6916b1d5cf17247cb61a03dc164ba282	1	0	\\x000000010000000000800003c39c6580c31444325797af95aecf2f4bc0546daa64cb5011239c2677ff75931b497aa71020bafbc000b294eff3c5120f02a17f67d6cdf34cd70fab836adcd21e2edc0fd88b9e134ab3a747a48ddd2203732395b0c0380283a0b577d5a70dc5085a1ab4eb2e08d6eb656dd156cd43ff45ad2d4a3f336e8ef70acfc36a4d4d4e53010001	\\x307a3e3e9381163997ed2c5e9447464d4b9304240bbfc3c0fd0d975b24ad2eb626e7a563d6efb1780bf4e3dd8bc218bf51dacfd14a86ebecea76a173b35e9101	1688298683000000	1688903483000000	1751975483000000	1846583483000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
87	\\xc8b408bb553ee20ac061c19c28183383af2a6ccb7c08cef0d932f4defb87856490c62a701539c465018a50b7991f65dd821169bcb6145df57333cd5222900213	1	0	\\x000000010000000000800003decd28c59b3c805ad639ad090e29424b4501978b06aaa47a782c45ead4d786b2ebd488f17b79e12c5d8952369a02fb45bcc2409abad12b7ddce7c57664cc83ef571ff875caef026009e638375925f4b345b4236ce41eaafa62dca5ff62f8065bd0f713f1e676e85d88928387050e33ae55f27e054156a218d4109ec493558885010001	\\x2daa897b711d2a21000243e78d0c8ea2ae399f5a17683df3b29d60e875c5d3be1e6208fb9adde8daab27adb131d1e3b5feb2f77fc1b5d17d2d9c2abbaf8ad401	1661700683000000	1662305483000000	1725377483000000	1819985483000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
88	\\xcdf811c9a6609e2d64db4f11f32b7246de86f5aacaef09945aa65c0f1668b8e8b351c431b233fb285d641adfcbd734d23337b322e16a3682f0570c11106adfae	1	0	\\x000000010000000000800003a69f54bc3463fcca1b9f0c4b26694429d0a93bcd46965a9f32d69357f989e7000a9a77fbacdeda20087fa7f5e91222ba8de15080c0b7aca5532de1e9e53ea151104cd70fc5aaf64c890abcb55926e275447bb19e51333556d5562b391a750c9b3496b624e1694559fbaa3710e2041a7d6d1f5b3e5c329a7cb9c1e337bd9240b3010001	\\xcc833baf576f2e63e0d920ba55445b3d5eee2b0acedbc9c9135598c7a29bda23f04b6a320da2edaef05c4b610b6ff11b2569230ed43dcbcbed7c42a91c6fb004	1671372683000000	1671977483000000	1735049483000000	1829657483000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
89	\\xce7860daabadf0a627753513af5c9758b6001b405d226e24680d90ccdaef90ff1e6be284dc69aa2c0559e1b3a9db7078592cd84badb1a73c9c32928ab0db08ee	1	0	\\x000000010000000000800003c355be972f9e6531478b319337cc3ef6c3fc61a2642e65916428925ee290d0efb1db07480437db7ec3cf4a93e397f84ac8cd8fcd53c907678d3c7ef2abd8cf806018d6ece0bb45a547d18ef2ebe2f63afd3c7d226d1ee81e1e8cec33569111b8b07e4b08a61a652fd3ff86dc3ed889f17c6e184ffb3215ebc60b5171364da06b010001	\\xf5cc1b74b296ade7eae586d179bbfcb43c797258fd97aa6b727ad95ff23182568c853b8f7e5bf5cdac56a9221d66c5492e9de9d30e2c4cca01523785a9d57b09	1661700683000000	1662305483000000	1725377483000000	1819985483000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
90	\\xcfd845dae92e2a06c1db8200cde1fc7b2ce60b9f1958777d6062cf6a8452614f8ddfedbf2210b90aac94377b2b14067b211b724c207b18b2434e4defe9deb940	1	0	\\x000000010000000000800003bc5a53a4038896aff54bf581e40352e3937b8a1299f5b2e109684ac79c0dd67f3dca36d4711d740e92b557d41b78a56671e5d7fc43497786181ab1955b187b513f02926e4555259660ad7a29cfa06ac27b4ca6b5968e38e096f67eeae19559afafc2355573ee77ffdc89cafb3b96c50dacad2e67220d061853c557e98640db3d010001	\\xc0a4ef31839b7d41887dcca0014ad6d24f4c5f4e6c06f43f5b0193f7eee719288d32ebcc10d81545d61fa249cc9f756391fb8c923062e6923929f30f1f1e0e0e	1685880683000000	1686485483000000	1749557483000000	1844165483000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
91	\\xd098ebe88d7f0fe899d545906d1710a204c188a64cce004ec6577c40dbc4a346c1db60d76fbbd7621351dfc2c1a5dade7b738d224ac5a7403d46491689b8d0a7	1	0	\\x0000000100000000008000039c51eafc5f324300fba21d201aec69d83f147543ad427896fa1a9e28436bb56c52623fcb61a5d5a65c3e5f409553c87e2250864fc7f0b3c5b056de8b0138b1e5cecdc0dd306456180cb3ece401188458504e2122c240551f45525a2a3eeba5aef062930cdaa6dbf246d031f1b041b7dce478be4ff62af84bc9c99f30b293b599010001	\\x6b0fc6e7e0a6d57a5a6980c92c9c98f43413ed7b1b8a9e9417c2d823ad27347e12238ec17538b4809aab0e7f38ef4b0670644c73047c8fca06ec8a97df3d5700	1678022183000000	1678626983000000	1741698983000000	1836306983000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
92	\\xd0b49a004e315a8da955204b2c0e97f75bfc264ee94cd2fb451e3189d12d8c6bd9d9814843253934c95576e8a5c23c44f2482040149d4c70dd8eaf543e54db3c	1	0	\\x000000010000000000800003b78bd711cdc552450d9ec87c410257a3d98c2273c059134c4b1d5d4e26e543b1d2d6c835e5665aa8da815cfb8b01659748c8d01f938ba7c2bed668f9cd79f0226145102bb597fb27f6585b291be202ce2038cad8af9550249255056d76a9134ce86b4ebd377f5957c78d70350125dc363bb1d2d97d871e4fe03a1322c1dc279f010001	\\xb97a7c706b16c169b11f10920475f6d231b7079aa7273a520cde7567f05b9dd93f11ce7a3d35719471dc2b0e423af39f61fa941182293a65f113505eb880490f	1681649183000000	1682253983000000	1745325983000000	1839933983000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
93	\\xd090e2b036c0c32fc295c713f7d8942a084b73e9d956237bec9db9941a2876f44fa813a0bf1b3005076b37f3f1a2b7005dccaa84b8d8a62aee47835aa9a7c581	1	0	\\x000000010000000000800003c9828371750af2f6bdd4005bfa8d6140ff30f5bfa946ee8b44ef838e1e6ecd9df0b138bda6f7bed480371eeb356a04e15e38546b24e5d805bb598244780567115ebac79f96b85449ff69cb37b3f5c25368f3f29baba9cbb0f52f387335d5096b94f1788aad42ca11ed2e7036e8e6cae4ad2983ad1a0a72fad8176b9a0b4a4ed3010001	\\xc008615572db6b80ae5ee3630615e24f26d372c287e0269a7e73aa76607a0a0fa8a77961a94b3867a4405c225dff6dc5270723545fed49040ede336b3a477c07	1691925683000000	1692530483000000	1755602483000000	1850210483000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
94	\\xd1bc488fa1c529f275de0782a18dec8045b928bd0bf5d0e6eaf9b766a11cfe059a0faa165a2d9a37bbf84a083e19cda07721a2ac7c93b0129f51e8a8e35cf51a	1	0	\\x000000010000000000800003de9728965508e85bf82618e99e9ff9d43261401bfe9383aca33452fc7c1e0190877dd5a13111016fd5c9ce22808d41b06ba481f9e0b9749f0cf74dee94d14f70c3c544e2891882664f0f21f1c51f0a97e7f4e45d2ee1991be96260d66492a58ecfcfb90bc22f881f0480abc420667cc3e18d2f47162c67261842d77e2bc40375010001	\\xa00e1b8071a42ecee1e59822f8819f9046c2bf80b6b821607f3e5c554e05ad18c41fd3d42c846249e27736437ff787fa44c2796b79ca74fb7f822a6e09bd5605	1670163683000000	1670768483000000	1733840483000000	1828448483000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
95	\\xd1dc623afc76ac49b902ff9b5e4d035f5e552a78f58aa166fa1313f8a09b5d23bed4a7a317674612d1b3bdc8c0b020c52875d096f447896d233f7b02a81b438a	1	0	\\x000000010000000000800003c6bdbc43c3d8af21a315dc04f82213e1007664824266a7bdf7b655e61cd50b0818a9c95ad7ded179f9ad42f701a4395f5c1092c3154079b45dd8b4db7c0f06737b92f99692e446a23f15c8c3e8dafd2a381800c52a118748c766fe5aca43b4800b75cd1cd5845e60f8e32f0cb2dd5269c2885e0e8db13aa541d7ec08feae65e9010001	\\x91cc7893e41aafc86ed31733c548c2f287be45c92d43cffa8f972ed0770732f37ee7745272e30d1c2bc4bb0423a982f2d8020fc0783f83d3a4c688b81fc1dc09	1687694183000000	1688298983000000	1751370983000000	1845978983000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
96	\\xd7805f9dfd7feda3a01d5202c3f8e79cba388fd12ca2eef30a4d8f85d57ac6fabc99a95f54c7dc51d68fb9f1566af349c93855e314f0d38310a98bf76c6e7747	1	0	\\x000000010000000000800003a509e68627a4bb33bb017beac361447fe5ac96ed48ed9ddf2b31abcae6cc630839aee7cdf01caad7ec2c3af1b922b8841b179cddc7a9b14f4259aa4854031c6815a54ca3b752aab689746133fde38cd8424236a6dc8b248ca1b7469f43a146fbc25ed171029f2214514571ad8b268d9237b22349def3f94d6be451756398e8fd010001	\\xca62a2f2bb98111172e78480f84e041fab2d70e5084ca56243a4ab60daed60b419828c5445e06f3d93b94677d36068c51a04fcf1b0a7001f48e4b18ac17ec107	1683462683000000	1684067483000000	1747139483000000	1841747483000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
97	\\xd854324409542de0896035adf924927339aff582a81a0b613d784cd922a8264354e2be00a423139aaf59b28b73e65088f4fed2b926601d49042a4ac2b153540e	1	0	\\x000000010000000000800003c7508f5d01b83cbce6eb1d9d89cbf9047a589ef492de179351f52aec121128cd46ca9cb7deec4bf16ff63671e959dc51a96dee824f1378022fb35920e5b06f1365750eb577a1566101bd600015d835bd4a501a43c8d3cce6984e363f4547115f7f1a147bb3758d626217869670f2aa9f4713459591a0b2406875d1fb7bd003c5010001	\\xc2aa57a57510c3eb58394f8f50791bd2a592605732a6350eb1f312853ef6e6d76f1da571370c3a717223aae7c66902b70e00e91b5b1684509fe851f6bac9930f	1667141183000000	1667745983000000	1730817983000000	1825425983000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
98	\\xdb6432a34000ef2df60b61dc9fd9814da37d706d3052ed2085769a6ff3d681eefa2e0431b1b9fa85ed95c3b66cb4799001fbc65528801442e02034794e3aa44f	1	0	\\x000000010000000000800003b49d16e7814e852dd09e433103471110d310d9289528509363e1b0500b8de07dc40bf1ba2596b7e6ee03f533a09c1d8cf189ace0108fa9680de01315b34cb6762dcfd99f5da87ffa3e8c1aa6da96be3a5b2e8e06dc22f7c23b5405168020ab690f87e3e4e46d6bf47aa148d22ba958bf891d6e9ccecaaad224cc02af98e1643b010001	\\x1f712f52ff47d55808c963192178e534c0e2a2be80ed64c50c9c796a9eda3e3c8b133fd9abbc92227798d586d3ed459d1b82ecb48a9dbdcd7cbabe8c4f37f407	1684067183000000	1684671983000000	1747743983000000	1842351983000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
99	\\xdc700fe1166af9223273fd82c84c54d4c7476b20357ecb59cfe4ee55ddad10311d5b40523674dfef2c9b6e85a1b218015249a31d7403c212176c551a82f91f8d	1	0	\\x000000010000000000800003ee57d142eb25916b09f996420497d4e61d615626a20847b45b6f9c537eb40b8752e20bbb8ea478169abb4b83595419675b6850cb388544569abd53202f00c5cb1ee6c683d630ee0f242a28ecb02be54b49d2a06cb79b18ed4f969908dea51d8484107f60c4f31ccef238acfff7562f1d65044865d9d7e6c0c850082bf977fbcf010001	\\x8e8549fb5ce2081b6d1e9c2d341969eec9d9e13436a15331878935a196bbc46044a612cf610eff8f77340b99c535e3eddcac95a51ac8a9e6042cffdae8988507	1661096183000000	1661700983000000	1724772983000000	1819380983000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
100	\\xde5c208bf735c77a6a8c4d4f5799e20aac70ec595ae3a1d2606f0363d78d9689c4a1db5b9e25f2a57512873904e777ea2be62c74321b5c1745fb9ba69d400850	1	0	\\x000000010000000000800003bcb7ac9b85158cfef7dc22fbd3388ea3a01478515f12e5ffbe19697850bb5d689764de732cf2b1243859f1314f711ef12683eba11d5a7d028c5b5b4157d2c03c4a7a09fa253c2e709e47459166e36824f136f52e7dbc7b70013f06d5c9861e855ab38a87221a0af73b8ed51ae6eb9f07c0a975dcf5b9cb5a75c996659e0a8117010001	\\x8b22a38edb9baa4e75bd9c1bde91f34dbaed5192936f44436bdc4d13fcd79140f1352ac951505d43a05f035c5b9b3c4b2bec7652bff2ba958a31159ec54f3c04	1679835683000000	1680440483000000	1743512483000000	1838120483000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
101	\\xdf98c26e33fe7d6cd17211a7acd8a796a8ace7b88471b256f52d6274abcaa8466624ed5edd236c16b86c6012b094e1729c0116929eeda5a5b682b930671d693d	1	0	\\x000000010000000000800003f187b9dd0dfc2d0cc17a9825e292f330c2e2b190892cc1fb5b9162bc3f08dfda2dc58e5c789b5126cc62bdc958cd0ffd14ec9090a3ca953951f94a223a7f11d183b79c559391e3fe8d0782f8e1467c57cca19eef5e3348d98baea55ee579d5077b439e23b93832c3b79bb278de3cf254de0f7fb0eac30f7130583b4b86b59def010001	\\xce29253ee7e2b3094308f4ff4ef07378d962ea6e8d760d229b395f7f08f5e56dd197f680ac2e33644940916f8dad1c0fa78c740b011e2f23c0363f6fb3b70a0d	1681044683000000	1681649483000000	1744721483000000	1839329483000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
102	\\xe0f8f37b23ebf296c2a246e695e6635e8e5f0d57e9d5a97b083f12a9b1c08d6d57f74cd0271b2ceb3266fe8ff5faf64178e0e0856d38e0f31264f883babb8c7e	1	0	\\x000000010000000000800003d3a8b6f33c9b1f803373170d7e1e57583e71cb4fd403dcd14f147681d6ac8df22cc473823a8c78ad520d2068863b96d6c8f8710f5e712e9931dd3a8167384fd59a4cfa6f32681cd57cb0b2a252d387ca8231c5096d197e33360f40143bcb0dce30346b5ee04c39b4d7d025bf30bac2bc06dcdf9e071eddedccd4b59f3d16364d010001	\\x688705064e0b2403a144738fde40761da80e99e96bcddf1597082aab359dad877eab2c0c75e8a22689a2ecdd8661211127db3a3a23513ad123a96fa57644fb08	1671977183000000	1672581983000000	1735653983000000	1830261983000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
103	\\xe020167eb3a31a042550448806198f96ba378eff4d8692c44d65eda8368fb523c9dd1e7be87bce8a0e411836cb1461731396119b254efbe1cc52af591bb2ea37	1	0	\\x000000010000000000800003b7e2c5ba6b9718b81995f2a55f80e86b4810fefe20d0ff6aff8bf91bcf52b56ea26025b3eef3f67778cee528dfefe830380e679b4d1cbe36e4d18a5f62379c86fa6b84d92911b4592999d220ef73d57bded4f17cee62a3b4d0a244ef650b10022638032d346821f579c4181303173016458e79a73d8b5088371de6fc3fd79eb7010001	\\x1d978afeb7b8362c14369a64557743c89e31e69579d8c9ee3ba55a01e88d0d4a01a215ddb61078450a74bb92b8409ef6f1291fa03e27daa64d59f564c637500c	1668954683000000	1669559483000000	1732631483000000	1827239483000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
104	\\xe140fd06c44b48b82eea0eceaf97685aef102dba42cb8f708a2958f3b572a58dd3e0c42f809914fbb3a535ca6cad6fbc0310d8944f69195d48717f7fe12f0715	1	0	\\x000000010000000000800003dd331108e4ca07cad978e8b329332f6b3b65ce359da431643b09890c95ad24343fa02a1a2c7ffbc2080544168e7e327691bedee288d05701f90bf2ead48a49eccf0ebc900d97736cec6217630e16c8d54a5142335dbc209b49f90cb28ec096219b57d8bc5d19fe1b1aa6e0eeec201e0964f051a6969065f900894174004ec07f010001	\\x6aa335507751975856381ce743cd171f51fe837ed64a3406ac764fa19f2bca496b2da5fe6fd8991145b3ff4819b5a84e2dc399ff8996f4e44a5d5f3e835e4406	1682858183000000	1683462983000000	1746534983000000	1841142983000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
105	\\xe2908c7beb9d9b18d87569238b0bc9a098e3e455eda622dea4573a250e80dcbc9543153992f1b78dc2300d222b29ad4d71537308fd400048cf24e954ad992208	1	0	\\x000000010000000000800003c6d1bca9e9d01c91a7e3370dfaa3eab582cfdfa665acd11a1462ae9552d605c073107a164c24299dcb52ba7812d0d1b1ac43db0f31b962e595e72a9e917c771ea14464cdc310fb56408b7e60a9cc3b7973388ee3456d55471c337a4e06adcd41b09114b567ae2190b4f408e02216cdb9656d1be7bbde2b8e910c6dbf17d0e557010001	\\xb5d1b5a32eb9924e1dadcdf9a85fc733df5ad498daeff6c834e28cb0c68feead116b989159be1a6f5b847ba20367bbfb2a61b1f74c24418ac68367d3cdeb6206	1661096183000000	1661700983000000	1724772983000000	1819380983000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
106	\\xe4286b7524d97d8d6749baf5b3b049686ee17966e5a21c9bbaf2ee6d0067b7bed5d88f7074231479de7eac05898e692b7d041a5101ded44508337caf353da2c2	1	0	\\x000000010000000000800003d8da76840ea1925fe1494571736ea8993a3bdb0814056a2c6f752e624a8e4acc3265baf6350ca793023112dd5c8255145ea22b4211632381d1cc3fe02fe4b229b7553496df4cbe897050cf024101a3ade68466cab9e72557236860cb3b92abba572bf359e11b28c1fe8ae35224230da2352880dc7b41432f3216b54bfeb00fcf010001	\\x224117edc7b36ae63150e77d0c4ad9260056ad08098fdaede50ba90b6322639adaa13f855820c1b600e280a2906beac6696ccd28477f389d5a66015d3ad0e90a	1688298683000000	1688903483000000	1751975483000000	1846583483000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
107	\\xe6c8b3f5f243669c7b1239171e84c2cbaf881e5d9289c01af9b1353610cb46ff4acf07d2c7dc55aa2e069a060aa2eb0bc9418cd2718e6fbcd71fdf724d278a54	1	0	\\x000000010000000000800003da6a9cae9eb21f02657fd89fd14e7f70f86a99eff13346181c9215f064ead63483b6794d4dfe0d6702384f4d31909b9c32a42bad01ca4c8b19e252d75fe63b8c9194743b0a9f1191a0ad731e6d43d8ceb6b2a679c1c6645a29765cdd22cab51730002a9102ea297baf8f83d992577a704b8e1a468e3c3f900ca171503e5de35f010001	\\xf7f17a1525eba34c8e32f610e9c2338bfa9f79b7385347af6c1635e8b15c511bb984903f4170861a7cf5b1c6abd0da66644fc4466d9601b4ed035135a5fc2008	1688298683000000	1688903483000000	1751975483000000	1846583483000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
108	\\xe70810962ec4550f85ccdcd29d7a6b33a1d472f22602b3a21ffc7315f588b0e799b080bdd49576f3cf17a38284e8a887003dac484135e8fe21ce4c06b15fd0da	1	0	\\x000000010000000000800003c97cf588e2e7b5a6e853cf703714f47b6cb055c65404ce066132265e98a29ac9b63ea6ee272e8f1763311085a0e18e1d04031caf631e1e29336226fa8983f72068f0b4b78b45ad12965fc8e0191da48138f92b5a29e737608a9c9dd2b47b24871b2a28bfc8152daa37e935e1698b85608ed8d3f5748d5ee3287b08069e58f70f010001	\\x091757c25b8499b63245efd61446aed9f32512ac45ddd388ac2c6aae94e002fd9c6db208214191d79b1c13da8bf605ab601abfdb037c35bab0acae0c3ffea604	1662305183000000	1662909983000000	1725981983000000	1820589983000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
109	\\xf4645d513f56e0fdc42edfebb8a1019695c1d4a1c73cd631a32058228a8605f6d51c248f3339cabfbd3353567b6b96b0d55d7d9e5259523bb962704afd8b8af8	1	0	\\x000000010000000000800003d229a290510a4559fb562e4ec2028c4c8f9519a41b0bc382f0b1d34a9faed63aef6d53753eb9cc40c52161880b72c8c40812a9a7ada58801cdc3eca1590bc4e518c1ddc4d0ea1a656c39bc0515978c88da7c777f871f8eee149c041df0eb7ed252440be6d0d0a4ac5cfdcf905408e317776eabd3c284e757f4cd129d531aee33010001	\\x215bb652ce9e3ab93e631f82ad37353ef82624fe6b6df6533de0eb60f38ce24b9c8f6a481e16af60bf586319ea0993b5d3d7ae6be7aba6f2669f0f3019011c04	1686485183000000	1687089983000000	1750161983000000	1844769983000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
110	\\xf798b3fe8bb156bfa269fb6aeec76f089622d279f19abdb7ba2101c3439f579cba07973da6afb8c15c7bc793ca8e8ead32df33eade6e3431e16bd80c255cba39	1	0	\\x000000010000000000800003e9c15083b02f4c2d36d38e4747f3ce40b31986ed8c5e053a4d0046ed3d4dba64694971382677c5ef21209f2486952f5d9f3486456e32d46d927914b6ccf6b1850787bf066986d7e61f642ba3d2b4c49a97d1f098cdabf76e71f34ec5f8f5fda7c1a52fc765ae6f0ed20421b724e6a2515ebc8c7cfd8b4347273167a357535b3d010001	\\x4abb581609dd336a9366eea08646d5a86ef181847bfdb8445794bfe445859679eace32f70a1ad4cc67e0e5bef070c33cc3d13f0ee8a37ede52b55daa0b38aa0f	1668954683000000	1669559483000000	1732631483000000	1827239483000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
111	\\xf8c45a8cce505d38c7fd1d4acc78f3113fea8d9e6529f7bc9175a470c44074f6e169b9fe4e64e10b92ac65a08e27fd7b9ba6561379c075bafcd8731a0c018b2c	1	0	\\x000000010000000000800003ac312a88b0d07906f209957469d0d4924319273c9b87373bab2bd9c754840934193082d98c84b6121c0fcd09eb58d8669df76ec4d8ceb969d0d2fa3eb4b91265f88cc755277c0b8f5c62b26c6520f61b508c9524bf08b7f485bc011d8a16c4bd23ced14f982f1711a2f2a580ff8b46cd91c1fa558d67c8e39a66dffb97dd1c8f010001	\\x063f2487701ec5661887a6e5a5d99ed6d9910d121320c90997238e4f5137b3a21d6c11727f47958a71fa70eeca17ed122ecbeb3aa3bb6d2f95b558c753041205	1671372683000000	1671977483000000	1735049483000000	1829657483000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
112	\\xf848cf1606794de3d80024c7ae8c4e90e6c60ac5f054e74c7937534a3036e93e18eaf7bb09f982b55dd4eb66c1414bcddff48b36363db26eca92d380a4a2e157	1	0	\\x000000010000000000800003f45ab728b56767a705b3778d96d52e2133ae3da46f4ad55ee9cfa9d32e1814fbc1722a655dd324e674647dd824c5aa0a3741b55f9d8532cea10e71a66524fb092e830b753f7444a03d24501b6b5fddaaf2d7907841b611b10631f89e7d1e8dc3766e3f19b9ccff54a99f4a1391846c7a5b99aaa6dcb119cf84c30d7aa23873bd010001	\\xf09c769ad614187d06a504acd6589bb1e58285c0599390bc7bb343a869c1e52385afabc5b085d1848c7956d98a1a9d0047cbd3847fb63d850b544ddcfcbdf907	1682858183000000	1683462983000000	1746534983000000	1841142983000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
113	\\x02bd000a51f8f8f54c8300fd0fc1278a638b4a43f8cd1db364bba501081041d68a7499c59e775a8c946caa284c23c6b581b7a24e86a97640306fe08144a6dfef	1	0	\\x000000010000000000800003e74476bd294b27466283fcfab7d26e86cf3c5d0740e9cefe8d00778ee21fff798002e66049ae00986fb4157f39923e563744b6d30682b55c70d4a368b01e6b698cadb0c2f3be46b20eed701ee32d211540b34916bc9b3e69c97d91513f834abec5f381917bd415411fe9088a7adbfe895d65efb8e130e8dead2ac182c517f631010001	\\xc41022771c1a2c0c536fa3092110cec07e17a9591e627ed03ee510629e0d44a654fbec38054b9234fdcdf628544356c323396ca75f51a52f4a7b7e3d863c2304	1687089683000000	1687694483000000	1750766483000000	1845374483000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
114	\\x0665572ae02617e0817ab247b188701dbf9078377ac14491efc5c61751864fa2a780a2c9a3f524bc61ddc8e07d235d251f7e9ef6d8d762d1e08d93e0117fc3ca	1	0	\\x000000010000000000800003a4ce26b2a9c8d6f579ee2ee64d1075081c65cd7b49a3fb90eccd93b2005a11d63022d6fb1a1cc5876a4aa94b97a231903466d6fe41b8f9e36fed925ac437233bf2149db0562193d262a43806c4204f401c7d70741bfcc2694280cf40efc738a8b96433b954fd6711289a047e2e58ad625f6f36caafebfde9541753193d1d8ac5010001	\\xca6d2a21a58ad79cf0b16276bd788e4943e9722399ddb13f52afd1b77f849b3b9be063369d89b31203acac782cbf5ef3df90d60a9a964dc8aa99debea96c8d06	1685880683000000	1686485483000000	1749557483000000	1844165483000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
115	\\x0905728489d56e145ee20aac8fabc00d1594ad7ed8fdc296006a257225ecbb558789cea5e69c6574d7fd91e66ccfe5127d382ca3eaf32960abfb6203e4055322	1	0	\\x000000010000000000800003be6740ca797acdf2bf15f3ae5773b78a5163a2ecfb5708df8763a0842df365af8dbd770b39418c9294fb22d6fab0e7cebd3a9b176894a16a8a2eb4efc71fe994f36b347f3b5fcc6e212a452000a34262aa5c977ff0347a8ec6d76ed6dbe67eda46bb443e8020793180d79b8d15c6b8485ea72a185b52a2668e18c85364558c61010001	\\x286eb6841d4358864145d2608afc4c36611c1a2b8f9eba63ad6d00ee08761f1a05af1bed6fd8eef9410bdc4431a659e9e4a82fd8e9ec15e433d0bc77e4a5440e	1680440183000000	1681044983000000	1744116983000000	1838724983000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
116	\\x0a814e3cbe4d176f3cb9a0c6ba0c84c0458d9b2810b2afeb2d3efab200b6f7d2ed226a4f9976db43dff97fc65e46dfabeafc8a324a69c6119d34308d9e06c1de	1	0	\\x000000010000000000800003de49ebddbdccb9d06215984f072c1f14e2773ca7d3e0b1e6f00d6dec545cc7e08f1c1ad5d6234dadf84074758b1b63a788ceeb248cedd32a02b2e181ba2e7d0112a2321bc19d2760daae3d40f4d72edf00a345356362951eb61f4b9b75051186b01dc6c2d52d57414156ece537ebccec0aeace2f966a47700dd8035f242cb8fd010001	\\x18039296ff8f376473732ed81de38d10fbbd8085c68dd8599e8a23a06644b4a34652273034dc3c12e1e1365365a9c0fd3e521b44e3e6dd81ef08a5fbe4a43b05	1681649183000000	1682253983000000	1745325983000000	1839933983000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
117	\\x10d1e70a5843a5fa8e6167371fb868e50b2bad8f34fb7b77c4c786b0bb46ed8f7f5e616bf006d5c88a5c226aed43890a3998d682f23e8ed43819209a05e6cdcc	1	0	\\x000000010000000000800003bb4272e4b17c76a6e771712cb5008c41baae40254b0f9e8ae3ac3b04cfb1b74268ea4b043eb0afe1d1d2fb737a41dc5ece32d21be8423cf6d6712d41403fe437f5b138c7e3b859b3749ab4a03c7545f6a3d3bbad31890a099b81d450379dfbc2aab3db1820d0c1e141164fabb709f07384e721e508af72a0f7d2e8efd7c997d3010001	\\xf7d4287a80960095fd7fa7e3c1c99a8855c4ea49624fa738e9cd2a3520fc2e246cc69a6bf7f06b3b4683f1a5ddf2badf992cbf02a0645277f5b7930f69eb6207	1668350183000000	1668954983000000	1732026983000000	1826634983000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
118	\\x11bdbeb05352180fb81f6468ab2927095c9d571e45311e5fffd3d91897451d363e4a0e9c9c6b2c0418a5e468a9d7cf8b98c4ddd29b4489999acc97d51c3adfa6	1	0	\\x000000010000000000800003b08a147d2bcd22f20a3f6096f26fdcb7c7bf0f472e7d284964337acadf5ee3f36306763753136b8017bfb114c7b267753578dba529d278fce8a73b95af37a7422ee5ec7e846d187643a39c3da11474d7392290e2f998307692993ca68f2ae6d1b03d1f8d7f1abe841f637c91393202e1893c948e61a3c15d47cb19d28be99a17010001	\\xbab7977ff4652330e38f0fa3ff81d7684190b70b1a17dcb852abcdd8ad9b60f1ab156769ab4851f44f731574523aa75f42937cf4bd67a1f6fb269c7505eba50f	1682253683000000	1682858483000000	1745930483000000	1840538483000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
119	\\x12b1f2cdc8d4573ff963cca7848e7f045b0b2ed7fb3e75550bad3814d9c3f8bcdc53b48663ec3f671130047dea5888b6336c4be3a9e9e0d61465047c1b446a6c	1	0	\\x000000010000000000800003b4f5815380bb5fdd5bfd0b336e0c6972c20b64ff5935830b3210db9250f7c6b4717f6501f67d92979276c5450bba0e8cbcd81d9c58008fcea17f24357617ccc9060bba7bc939b65d79f3cf0e5c429a0a17c556116f400829bfa817361590b1b07c282674bc16788b9d4d3d7df8bfa868ddcda91e2d99b00b460adfdd6cd2f645010001	\\xc974e8abf77a54ba26b7e77bb05e769dbafc9bd6409aec45f4d9512f58807c094a67374ec074fa6df3d805850ea4cdecda58eaf4c520bd88cc7293192e34180d	1667745683000000	1668350483000000	1731422483000000	1826030483000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
120	\\x150d32e82394dac7c3ccf4dc3bd8b3c1f1a1facb9b0598640c7d873bfd01716f8203d7776f958e91e89cf1822716da72a5250fd6f4d1883a11901b38ce1f7b04	1	0	\\x000000010000000000800003b68581f34d32930daad709466fb2a5e9b6fb33d30560fd1b48b75110014815af671e6d70a20eba9b3504cedeee2f4162aef1498c02dd060fc20fd81871c11402e300d0dc4675ba9f3384c5849fc22ed4187e72eb519d898ad3ba6282114172b4672617f2c1698896f1351f39604193c38bfb27b3bdfb8d26c209f671463b5967010001	\\x4f2110aa298423b8a9401d141ee7ea8ad37e5349fb7a743902fce8dc61688db90ea3a5573317dc8aac5d6dbad66d46cb2a1551d96d42af77088897fa469ba60d	1677417683000000	1678022483000000	1741094483000000	1835702483000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
121	\\x1b51be7699325d97cb57989b79c45f7f6479a27e5ed502ad4bab69396660286b56b6b118eb4cfa15de1cd595c4e548abc3c665e48a6c885ea4d794307bbbf503	1	0	\\x0000000100000000008000039ab03a5f5b8d9aebf6f507d1ccd9d385b08066b6f9bff90954e6fd7c5e4873925a83fbddd73d4dd7636171425003352e6d9d0513a1a359ad7be21cc8bbd0aa733c6415b9a79ed63827922e111b81c56fa959e68da6a719f0f6ed668c492821cc16fc9d930e7bf56b22fee237118737a2d70f7354c8fda14d4fece8e902365a63010001	\\x3cade9369eabb781d0d81eaac16d017f1f5c589b6ee6c915eb3e86ccb069f94443ae9b30a037f9d872403c13304415b7e4d2eb470f69678d2834d5de4a28fc09	1671372683000000	1671977483000000	1735049483000000	1829657483000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
122	\\x1d4d340c70817a62253d6336d80d69bca9a256357d14992ac8cfa9fc032102003b45be71d92b7cee293af4711f2de8476da923db21a11b006810c9a901bd38a5	1	0	\\x000000010000000000800003be2005b45e28c368bb6fbfec31e6eb53022de5fe4c7298008078199c777c2312d34247f64ed25d9a7266e170b68198bf23d1a6415cf63073bd46fd0d94c5297eaba3bcf9bdb54a5794177e4af53090de31731c83f71a80a7898a7ab87564b1bebf8c18672d5a673e49d0991d951c7c9435f3a83f93382a08952e440bb040bef9010001	\\x5fc4c35c49ec2d4e0dda5148503ccc7aa2f816233d5d46057e854105fa15f8d55d61beab26610f5db52805e78bb2532d30157ee6bcd695cf18715b142ea3400e	1662305183000000	1662909983000000	1725981983000000	1820589983000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
123	\\x20815129c3697560546fda9f5d2251f2573c1e0413393ee74fd687459925fd866552193b6e6d07f82e09ea44f7e500a221f26213c62b71f49a75cd01e10ae5f0	1	0	\\x000000010000000000800003bc61df46af40e12cb1f99c7ba3faa1e69a946503f5771f9c48fd845ec2375b1aa2ed0d0bc90f911a837df9572dc17f8c335bea0fbf95637f8d5b2a681be8c1b9d4b32923ae2344b26e1dbac7e625e8e329d7ab980f0dc5906df90448e32c2f8dcc1777e279d220c83ce9118d7449b79146d55697489df029f753aaba9e89f92f010001	\\xf190d09dc0cad7e087fa2b07a70f8b3d08848c88dc19524c2879bfe334fbfbe52351b0774e25158a889b32de452314f7c6720c12e85ac32439c86f504db30b0f	1686485183000000	1687089983000000	1750161983000000	1844769983000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
124	\\x28f9d3c568bc546e662e469b709e648147ecc90f4199bd2753bc303fbdef977c32cec6662654efa008258385fd328e1b5693920a522236a918d7cc65d14c6ea6	1	0	\\x000000010000000000800003def0113af75318325a1fe8b977dd4e3f76772441ecff7eaf1df469b662989cce8040cb5fae343d0129fa77bfa0fb5172f8d57dd8481d6ac3769ff6534e668266410c45ffa61ae87be986b2993051c3283829e39b61430d26bd8bd3b0b752faf400b602b61390c08a42bd048cf43d66c2be3727045c586403aeb53480e92c44bf010001	\\xbf4c104fba5543a4a80ea53c96c2e737ecf3231a4853353ea1e70a97925fb74ae97a0dbbddf362dce4ff0ee26b2ac2d87c97885cfd7327d9b4f8f8695ab59b0c	1689507683000000	1690112483000000	1753184483000000	1847792483000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
125	\\x2c797213f513a74ef719160e99a75d7475e381f1109c8731c6050b1019b5ab6d67f473c725dbf870329e7c4ec96c8838f71188d0b4bf837aba490dd19155b1ac	1	0	\\x000000010000000000800003b7b549caba3792e28c5e58d9969df01d6990c6ff606266d71a22d421ca74a06a4b7f257f27adc9543e9312696abb7ef08c68bf719c4bb44e1d6ee2f755266699a7079b3de18901ff8f58fa8cc0896ed7039d2c8c0a63e06450872e48aa59b551e39d291fc1ec9373dd892023f46f3a6c264df8c378820f48011bacbb7a8381df010001	\\x933420943b8e1cef069bfb3749be39e778f91290c68d62bc6114775bb28d9fd14c60c6541ea7121dfc2b5186f15c08dc14d9f4215f6079f1d280888c311af90b	1690112183000000	1690716983000000	1753788983000000	1848396983000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
126	\\x2d2da00c9f980e151f2bc625724d479cf736052c0d79cf2966dd4207b9a9ce30e6056c1e1f1e1f3d4d3c9d51b4e8a70bf72107447d4131ab09fc561c9380cf1d	1	0	\\x000000010000000000800003cc4005f856bb3bfe22a49c217be01d732a31f3c1318ac982ce93ceb810777987e32593f1686a9fbd186efdab2e5b3ebc0016ab0a25e277a456205f7b9f390044dc3664e8fdd886e00a34cf4168ec87170831347a9d7cb242b935efd2b6eee12a1f0abfa080690e27367fce67173b31c061c7e2b271cd8d61a191698c40bb5d39010001	\\x75295c1f29a8e37b12413e43a0bdbe184395c56638d1111ad0e4136014b82f5bba6683e417557a557d909cf0420d0befe69e97846001002716a070dc623e7a02	1685276183000000	1685880983000000	1748952983000000	1843560983000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
127	\\x3001e2abe20b114112733abdab5aaa8520a498dcf2a1816ee9e2f933ee9d49144f6f82e1a8910bf543ff15428366c5ba26bfb765ea5ecb6159a994320acdd627	1	0	\\x000000010000000000800003a91a784fdd4fbce3446010d75404ae843e064dc21e6ef242fe572db133dda579eedc5bf3c420468f935cee9f823b4c3295e688d32e51e353fe005c91457bc018847695444479257750f9da0083c47b5218fe7c0b9ac4446749dfbbbd111fb6803a6498591e101f3d4d55c5563d4b8b1aa2ead11948e2fb56a88f4b1ba9af2415010001	\\x4b54d419c72589c4310ee6d18464c87c193ae3f911f13ddd31e758cbac6130c2571565a46854c2c73c5ea4051c9c528c8b8b50cdbdde1b7bed672801f9972904	1687089683000000	1687694483000000	1750766483000000	1845374483000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
128	\\x32b96e988e604669397fa1d264e209796dea327322b84dee354b9a3012f5d682d887a90ea226f51ccdd6aeead1bf5b7a5c11d1163718bd778589297791307514	1	0	\\x000000010000000000800003ecabb859962f26765a6f6ebd3c66c9b85f53be4b4c18bc7d4c91f8b55115117139477ba8124a508a3283a833557c7072a1208606b0e6f63a572ddd3568d1336bbdff6524f815283a467023bb298c45aaf649beffb0f50f6f409b248bc41c6a7a74ce614fab3f9051b34fe9d968f07d0b4e3b425eb2a5538fd2ce1872990db785010001	\\xfe138b0dac31c9330eff96cf2ea83cbd5776cd2703cbebd8a0d3015e88610838239642e2aebfce47aa2d408c04a10fe3f121703d6f0f5b959d7490250189e304	1686485183000000	1687089983000000	1750161983000000	1844769983000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
129	\\x34f1520ea78d69ad7f259fa9a76e4f936cf72cedbd56e3e5894394267e603833c3911625fe9580afd017ec35fa8149cf9d6a64e2b2710a9344f2408a37158524	1	0	\\x000000010000000000800003c6cb6d3660cc35ea9f6a71d5ff1b5f5d753461bfb83e52e163b8205d906ae910dc4e1c003d59f6d1e3c83cd087fdf17f20e401b498a889861cb1e91e3195b729222afe05da8cb3860082761ed9f4d79af6ea4747f0ee8134666ae23b4f5e2a0baa072fa1da3ec3b74db18953712e039d0dd69ccde67719f44d93953390154515010001	\\x6aeadb714d99df11c67779ebdecbfe69d38f998e1e7cad391c3029a8f9ee36d297ee1c027646813fd258f635eea5311c3c6d8f15dcabc15379a2fee7a6cdfd0d	1682253683000000	1682858483000000	1745930483000000	1840538483000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
130	\\x34a9af860fd4a6981c4c0bde4f97f40c9fc554721c7a26b761f04cfaba0d13bdf787a255a822e76bbb42d3e39cf13658019c653bdcf82cf8ed8dff94aad8e053	1	0	\\x000000010000000000800003c5a00d482152fe1c52517fe05d199dedb7c9a082d36fe698fac6d8fe7da72464753b0864bb6e5406cf26db1e040b57004a8f6f4ad328423a2bc573871d5e8a709a9c4d6db0acb3ccf483d33b410bb0c79abda0f113819a23c4accefd2d46bb379475cec3ab53151f5fdc5970c3169f26b6d08e7a98b435c57d30ceddfaad49ab010001	\\x1243cea39e97b7627184d7c28ebc6ccc78f913a4c5e96296a402e2573d5b5d0bfbc01f8d91e429aee7cde4527866044063c64f755f7a54942c8dfe04978ceb05	1689507683000000	1690112483000000	1753184483000000	1847792483000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
131	\\x390da436515eb77943a2dcafcf6e3eadc6b2dca3031afdec7389a26d5f1027eca768bfd9e6c20cebca199c7ccf0f3239c0f96ef8ace1fe9d66179fd0408e1f75	1	0	\\x000000010000000000800003c017260d690d95a65e74b6be0a18b7f67a2a00af17122ae3c77c947f7d40cf44cc2877b0f7631ec6e784e2b8333f18e8978bb1363bf9af131ff2013b1a43bab6be31ab289d6a8dcd5a03853fc85551d01cdb5904f7fd803be5ee12bbc3314db2ab7f02314ec773f8d1bb7bef9b2ccb0eae9ea986f5d86ff386e2090aec9ec989010001	\\x5657ca8e7cea3c97288498fb83b86d33b9c0e61c9c19a2f57353c054b41909594c98c8e0f5eba8c6c825159470ad624dbc42542bb1ceaaad31aa822d7f22a708	1665327683000000	1665932483000000	1729004483000000	1823612483000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
132	\\x3a99954b1f0843aad2c8b98eb5e341988604b92a7ae3a3b6d81bc1ec35a283aa0ef049829a9c5eb26e6c99b41f69a55d8769382ac65b76735a244df77d6ff198	1	0	\\x000000010000000000800003a9784464bda92e5243117fa82ad44da189e2cdb9a3c81c3618bb07c73abb6ab03f22c36d43e22745eeddf718e1a3d2261dc09b0ca9c58ab71441add053835db699b1e716c1fac5105e64a65d59c189dd83352aa22f4ea76e25d4f2066992deef970f7f3b86ac2ef9e0b8da0335ebd93cdf99ab15202e9e1d6d1ca969619c4c81010001	\\xb33cccc0e58561f099262317304a8d3016cecc6e5f12d2297e1732f222a35cb2cc8e78eaa1d69a82c1113e817544f2fe64ddac057ecc35e7fa59a6e4ad6cc208	1671977183000000	1672581983000000	1735653983000000	1830261983000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
133	\\x3ba5e8fc2c3caa5a65c4497797a91d83cfdc0b28a1f38668d8d52481210501eefd57d7b99ae7eb91613ad81bdc4fb9ae79a4c489347f08463de5a5e70ba3ec57	1	0	\\x000000010000000000800003b7ea744d8bf0a0dc98769c590b78e66dfc1f1cd14ec457be8cec1ca3b0f4f8d5ec4c9dcfed5d57d2b3e4a3770fcd02503b14c7eb68a410ba4866b915aa8937ef7751ec22634f56c848f1cb189cc5089ddeb4009b2de0580168cf9550ce959d03a7e345981e072a82b005abd7ffe0b6e0f7247ae1f58a99e0f75205b9774f865b010001	\\x0bc9fc8b4bff7c6963af58662bff2c401f6da722ec9c52d6726bc2e5e861d2dfa84e2ee0c265f0745b0c59c50d8a8c55c64ee3e58a35b46a3f77641e0c8ca00f	1662305183000000	1662909983000000	1725981983000000	1820589983000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
134	\\x3c79ece6b001b2c9758a175a89c3a95c408331419914685ec2226b997a7574b0c493dd9954738834e0a22df11c466fe6446b7cd48ad04a8e251c5acd9537f146	1	0	\\x000000010000000000800003c5de9f2ae45092369433363807e0bb779044a0ae6b1b9cf7c719fe8f955591a4d915b70b3055a6b8015012329be59089dad07e24b22b5815dab1c2b47dc1c1c31b2aa54502bce35cf9688e6916bc849ee246360fac0b44c37fd106be83c590d1831a3a24041ba53b1d469f93ce00619bae49d570c8573e27d30b3c2ebdc6f19b010001	\\xd040a9c104955d835843ef71d1fdec27feed18503c9b74cf7f88a2f82b221b0e84340359499035967f66260b6805d3f7d38c221654f5ddff574ddbcdcce19902	1681649183000000	1682253983000000	1745325983000000	1839933983000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
135	\\x3f113b506ea5e1ed146a58be2d9cc3c25191bfaf0e966661b202689c66401417ea027611f36e6ab0d9f52681f298e10758090fd3e70edcc23af0697eef17b2e6	1	0	\\x000000010000000000800003acb78e67b7cf42f706c34a2ac1866f902c07753ed936f00b61aeb601caf709484262b2965078d7395ad9c4616fdfe21bfc1605380ad2f76fe35ccc0ae46c2f354cff7e832181c37affa1df2ec22e9467b957be0261bcb792bea563c0dbca08170411dcba084f941f620205d52428ca75ff58b6c76e7421eb86f882c166d6ffc7010001	\\xd654ef30fc9d45de20789bbb587802743222ab3ec0dbfffc3b00a94abd34610ef19daa17fdcd8af1f2374432bf005943dcceb91c87781f82f071252dc698060a	1662305183000000	1662909983000000	1725981983000000	1820589983000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
136	\\x40b1688570e7df606499b8dd3596b274da617c888fdc9f9b974c218ecb0fa1396dc1050352d0e19344d69b56b7ed4a22c5d30b56f545c2f00cb64aaa753ba8ec	1	0	\\x000000010000000000800003cd06743ad87ff6d5d25ae8df3def21c28034d4304b0002119f1cf2f3229edc7429a1642ff322dd9635f1f9f671c5fb0a444e48b8af28776b0de1f89a0a42ee5159d98b107a2d309f2f1ec9c73636442f926820c6506554b50faeb2a7f561a78bb25f0939adeea86ed48f7f3e595509b56aba7f9057779b5350bf60623abbfb43010001	\\xa2109be9f25600194e4dd83da5329a2950cc4ab8e214330f4facdfe0cb4784d69f8db8ae3c3fa2f8cae3aceef132b32444809cee8bf22cac210418cc4c08f70d	1687089683000000	1687694483000000	1750766483000000	1845374483000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
137	\\x40bdc35c31acb118de863015b6fba142d549b8debfc802ef9b3a7bdcd9265cd652fe286c8427b9c4d0018aff90c4977874ff4522fc889dd5787727b97c1f2e7d	1	0	\\x000000010000000000800003bbd1f487044c3ce665e66f8d814bff978c4d69309ed03518973b99e7325deaeb56457f47d3265971342b5487823d4e51696749937a6b71173bbe2a8ecc64a05ef7643378153e57939072ede568dfa899621d53caa32ffce7b3adb4165321d44677ee34f5bd60bf6fb98221b6091f7a121a83a474096df45a37297fed6c341129010001	\\x7917f7109fd025107523f83c4b026571251fd21beeb5e71634540c6b89087adc40b079b6c3e6ed11859f3ef0b887252fdfe12d2e56c5f37bb1a879e5200f7607	1674999683000000	1675604483000000	1738676483000000	1833284483000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
138	\\x4c1941c7c73582adac9ff6956ed9868b9e98d52a7436bb7b8c1830d49a28f31ec966e89c2aae8053607e56fa25793a55ac918ffba8c3a822910ee360f915a7fa	1	0	\\x000000010000000000800003d0eb78c4657b0b465ceb6de6f5ea52325563411171aba3238523c6da5f14b8aefb497318927f53c98b9083cc90614e1cc3885fe6c57fb199f18844980a0c184eb0979ac7315407ee711522b2f271071cdcdbae02b4adfe0ccc32cbea765bfc4f4cd9303b5373094bf6b4116988c6e4f879a4f2e17617d8fc5164fdd98e1eb49d010001	\\xd16796dc8cd74d1692b6e4b424287e9fe2a86baa58f8dc9115db9fdfe0fecc0caff78e7434aee52843b326ab7c277f37917de64f69fe8384f2d0408259b5f300	1685880683000000	1686485483000000	1749557483000000	1844165483000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
139	\\x4e15c631e3574e4d4868a05306d921a3feb034755a350ea74a1623f661de4721619e90f73a2d4fec0d5bcb7cab9ec2e8de3bfb5d39e0f690e6d9b853ba28d37a	1	0	\\x000000010000000000800003eaffb96bdc640b92295a08474c5c7e77e79aaa9f6c115ea2908669a05e2fd588c4056d9bd341ec119ced455ece7d19c770da2196d95387f49baf808da14bad5a4baba58c279856f5c7db36e829782a331c9cc3658da5e514bd5b9f493b99f02ee874f8e63f553fc551f00bc49893e2f14834f6dd3b0df5b0222f4459ce281773010001	\\x3218b1b1d517b8781617a565df09b75c15db426f448e6b8eb3a491f51a66988b11cc83f30fca6a9baa1c88c3787c15704ab57ebcd2a69bc9db5c2a7178382903	1687694183000000	1688298983000000	1751370983000000	1845978983000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
140	\\x4fa118e2190ddc4732263f38580ebfd368392953999ff36dfbc70700b3074d0cfa34b2ace2a5297bde1e55700c7f9c94a928f58501b189521fea69a81608c6dc	1	0	\\x000000010000000000800003f898b82bf88ffbe51f33c34aea2788ed67b732dbf2b3431558bd32608461a02eb8754bc410760c796019868be9db7a1bc8c496b5f21ae39da71c6e2996d527eea830cd93974285b05b240f7b00cd2c1288dc969c9a6924af2e7a0b0e9a31a857a087901c9a9a720020a88d2b649365a9f3812b7c9498efbad645a66a7845f37f010001	\\x9934a209705a52e97846e5e631d8decf3433c657620fd4cf1e71c59ca9fdac53a12b763dd1d79b396f6c5720fb4c42c0ba6d1c444047b6b09d276515abefa607	1687089683000000	1687694483000000	1750766483000000	1845374483000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
141	\\x5145737befc8207b88cc5e06a0d7353ff6fb1ade10b74b93c7c80cb07b777f71465b503d69f7e6a4b57bbbd2c0fe165d0f57aeb6686b13b1160ef0502bbba3ee	1	0	\\x000000010000000000800003ba97a504a7cc82d2e06f585c78080260a4696f4957e9be618c5fdfc08fc733c7bf2c69b2ba35954086652b72c8249f33180835cb8ad8a3f07ab8f31be826b1d98da60c7a99d648f68a0a4a0ce797a5fadd2ff889eb2e9ead6a0c37e1a9824448c8a23501b385994bc3241b37941673e0e970e6aa38243c01f21274cfb6c323d7010001	\\xef37562a819545e44cfc807d1b37a6e8495106206bf8a0a1aae13a33c1213affb86a25b7cd6e826cd6f6fe51811dc0fd1088af2d3067365c39ba18ad9eeda90a	1678022183000000	1678626983000000	1741698983000000	1836306983000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
142	\\x516580a49393f04f7727d8ce5eed92f3ee1b45bc8f4852e7181cfd0adfde126bbc09b83e61b498936303f804b7b3a716905ba0f512b5ceeb76b6d100a3a3826f	1	0	\\x000000010000000000800003c274b5871f94cf04e2841612a56ea7500884c6279d708e6c8c69315b154e1bab09cf3e91fffc2d4d63f12d6e0f5d2ee4c30fdd8793ec5ea7468f2d65c3e3c7b018f05c188ce7301341b98a46a7b8b80ce8fae7625b73ce80505be0fc2779abd351d879e5b635bae9447b055fae8e329422b2f2e7acfbe14c975cc313e50cd42d010001	\\x938596cbe29e34035ea60027f4a2c1e0a0f29bd95a784761ee8a27f37de719c9514f7ebc929c3384f2bf52390db11caf48d7c4e2d3a2625b2021569e9fb50a07	1675604183000000	1676208983000000	1739280983000000	1833888983000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
143	\\x5159523e3dd9872fae64da3203d52cc2757f07b69af784a005eb1385756ebeae1993d44f4273fdd1683510a7ff822b44dc0c50d89e379ae50d4a6581007664e4	1	0	\\x000000010000000000800003cabe67244124053433214f7ab5039b840a4c45c3b146aa33ef1a40ba555feaf12b92121003b640cf3b44f2ae514267d0f3d751b0fec0c6e8f0394a56ef380b5c7f0f4923d636689448da299029205a8e184b250e50ce9e3e32ab035eb8ee776e291fb29f7855735ba1304f876fb1bcbc73ab78a6397daac40f9420160c23ee5d010001	\\xf1cb644955c27b5531ff88d615822e3f9b3f7b090fa64c67b7c4dc8e89cdb9fcda51ba9b614835780b37c85c06551d0e0a7ee1d3da0f0fc0e8a7797732be040b	1671372683000000	1671977483000000	1735049483000000	1829657483000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
144	\\x54b9fe10dbf620e10c5e1756d3e03076ebf704141081a63580b9584e6a9f3edb39c3f35ee63bb675d75c5e1c48b5b4d0c2342dfe866f31250ed757b9444487d5	1	0	\\x000000010000000000800003975ffda4ce7d1b99838257d55e2fc34eb3023aff4f9223d22e44b688f913ff9540260256319a059d20c635998b4c77948ece960d9618d8e95348fdaac394f303e4605fea3505335e447c17725c8bd89043ce82f8ecb13414e0074fc6a3dbe02f6fed4967e0b7c1cffcd503fd209ff0c7fd83d5a8e23db9a45f84ef71873e6b51010001	\\xd2e1606b439554fdc04447866c35f700c3e2239976ce282882763599143687271739730938b876e8904180af46e1fbe8ce34bc445834828d2d0d665a43f35707	1679231183000000	1679835983000000	1742907983000000	1837515983000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
145	\\x5685b21381b45bfddc3acf6b10ef7e6bd3c5642fd89a14cf1feb208ab2fa08d31d9b0767a8f1efb67e71c00b994f69b2a18bd7cec47594a2f5446dd664a52ff0	1	0	\\x000000010000000000800003acdc193b83c8f3c5fa74fdb3c783c683543e6be1c6c4e5ba816fa0336ac1261c73a9f168a48063654118a1f848322a623bc7bad1903cb144dd77c77aa57d61a58992f1e45e333eabf7921cc9738304f7641bbf86060d75236a0526f63bf0ed1266cf232876392c35d0abfd920bdeab2a51b73474838960de9b659b2b3401536d010001	\\x6a1869e3819e9aaa7037443d6f5899baaa5d306a1ee968838508c7e3c9e35f7d3a745e5480f3c9168407eab0ed35d87a84233514c34ab3d3a658fb652b3c650f	1672581683000000	1673186483000000	1736258483000000	1830866483000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
146	\\x56ada28c365cfe1afe66d3e59e0c174f832bfb76b627045f36f0dc215e4264237fc4937fd913f6db93b9d78c985b5ac5f165a43008d6ee98c40fb5798e284bad	1	0	\\x000000010000000000800003dc2696d48c8c180bf3f7510d72ac46667b3ab6d44c18a34c3b007041fb830b3da5fbec4e82c0a25af39bed2870cf89f48732397273270b8e0160e3fda8c4b6d253c143b192d6305dd2e2b32bd6b359aafe9e56c219dfd555ac67160a11792ca3ed5537efbd971d64769173650033218b673e91a8ffa46d08bda4f5e90438363b010001	\\x429011cb6e727d9f18d4b8e588e774b09817e2012ad273074bff0b8721cb68d0b4d3062af476a7b29745adbe3e57d247cfe7cc29c2ee93387581abac4c61240b	1667141183000000	1667745983000000	1730817983000000	1825425983000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
147	\\x5625cbbe56957dff3aa5e81bea56262b4901b52e95b26bad19de188c2dfa29f97be990f7f4762f0ea8209fdc993d7de865c2878d1036d0f9f23b8dc5f3d01868	1	0	\\x000000010000000000800003c3fb96b507bac99db39ea845b74a95fb163d4ded8046657f767debb4a938d7c42c11c9f737808cefd18ec6b28ba17a5e5cbee9b014728035bf9901cc9a506e45ffb3288aa900bb4b52e83089643c1a7ebb5864f999a5c5742407d78ba25db6667378295682af8d9041126aa89907fd02a51d5fa70df642fccc4860161d6a629d010001	\\x64a77dc431ee6ed42caebaff09debe4097ce916e27369b117b23530da2f44d62c5ad246d1e15acabef96d35d2035adf1605706483bde7aae0603da8f1d7d1809	1664118683000000	1664723483000000	1727795483000000	1822403483000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
148	\\x597d962e3f3828d78f33128a1e4809d0278b7e0b72e477ba1429da460c877eadd08aaee07d07f133ba84dc912af62d84ea0c3f868209c54fcfceb3b15b9b1291	1	0	\\x000000010000000000800003f934407af2cd23b02a17b30b766515b39ac5fce23803ebd681968307f78ac7be306f28889865cdcf7e21dffb88332b179907a1b118c0f02fc7d2c825514f31633f5790a79f1f983b6e7bffe3f1b539fda74f044a9ff479c21a279945ca3758041688d6c05a32c0599689c186bb265b766a48a590cfe3feee353fc70cda15479f010001	\\x142524aef176b95dc9f0bceeeb6490f9a000b3abbe1f7aa83eb370578277075e1e37c64240318fdd2384e8a1c5f878cfd95d59c66b381fe8c6b2e1f0ec43490a	1671372683000000	1671977483000000	1735049483000000	1829657483000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
149	\\x593981f812821e0e9cbc65ca2298a9c2c68d347251304a54a419ce49e2fa37b5754d8c5d7268aae15dbf149c2f17d4a916f2c54b956e534c27cf5eefb69e2227	1	0	\\x000000010000000000800003a462a3748cabc51b2a629ca29f9e4911e28961b6da8752dc5b79601cc9858dd29f70fd33ee2fa1cd93c8317c00c7fa7838ce329d436467a18bd0ccc59265868ac7c77b05bc2f0c5689589ba0e30d3c2c0b56805f6dfcd47cff659c23d9b86b380d39e76b3359afd2c9c37a3aad28964fc9346557838ce319953147c778b02119010001	\\x34e85744320626dda5c3c86c1a3ad07a548fe6c390848225ece4ec19133cc02e12fe80bf2988313c60f07d9e61039f7d5bb55d065933b2ce5caf0f945cb4af05	1671372683000000	1671977483000000	1735049483000000	1829657483000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
150	\\x5d0d89a25a4cb89f6fa75c9b7b205ae1603b0d95a9680d5b7125ea84c1c6e8156882b861918d09e04254ba0201adfb24c49b822a6b9a4954f415e42f2a079385	1	0	\\x000000010000000000800003a4eea7d039127b4c6be7f1bd278ed888ab3a59e1bf8acc1bfbe592ea2a16d7fe9c3b027fc756d62fd34e57102fe67025d68959b691ceca69f049df2816a6f71f3ba186d3800eae6631de4ec9240c2bb7c7b4acc9b96a6b9e7c299cfff3aa9bf29e80f0eef22e69ddb5c7a2c74652dfe33eba930fc9bec198bd5846a9331bd57b010001	\\x363a74b9ed63dcdb650d4632b6ffb063b38d8820df7613414ed854823692fd5e4e9b9f5981ec79b3765dcb78308fcb9849b7b22702b4a4de6eced38a3fd6c50f	1683462683000000	1684067483000000	1747139483000000	1841747483000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
151	\\x6a4d08f9cac57a1a710100b2801eabffe3947e1aedcd3553894b5e069bd0ac12772d3bd82c66b7a8adae493f7f87d63148756984ab5879fbb6520c89df1bb8ba	1	0	\\x000000010000000000800003b6f807980a21ee74b8d06c1d10cf147b8713c397a7b062abe67c8c25052c8f758b77173e7a34a7fa69a2ff28aacda674e9ca501ad86bdba2ac17b4d498553aca83e1b55d7fad6096869c6136d9f43f3ab9e9592c5e1547407306064777a6007a3dc26cb5710917a7c2dcef12ad0f159e1c83e34ac594dfdd6884cb852518908f010001	\\x63178824ea1bf2619f5fbf76db60a18d3d247464dc9ea5bd4da179b4127cf6df147ea3751b876feda96605a01ae92da8b2fc9522cf01c282509a8ab3138f9c05	1684671683000000	1685276483000000	1748348483000000	1842956483000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
152	\\x6df532ddfecb96009eadcbb9df4e5f80a8e9d76ab3e8f3bd9eacde6fca6605a1ca453f1279ee61dba242d734f41a4ec475a900d572467b3fd64cf4ca4e6e0f3b	1	0	\\x000000010000000000800003cb7bda7a9e5995287f12bae56b6d1f6cf52a10d6eb6feccab97ec42d3a08d44a85e7509a15bd8bf99ed9aeff0e0d994540a0b47e6cde5e52f7e7e3f335dc87ecef46cd88b3eabd39187146feeb6691834f0028f71f533e4e5e17cda569a54a627daf3cd9794c7bb876f82a872825add0f63f6e17c8c42fffe8d3526ce304d557010001	\\x3968252e342141d211865e310a2c074921258b8b2e61ace690b8d6c2e5db7f67c2bb8ff6c1268d1cb33e59dae3880d9409fb750317ba22ab3d8c2f2f06b7a30b	1663514183000000	1664118983000000	1727190983000000	1821798983000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
153	\\x70d106cb40bd21a41049f848593d76af016dd261fbee2214de57aa42dd6027b459a288b9dc2629236f485510ba06226dab5bb85fe7cc07e8bc3d1df34722c41e	1	0	\\x000000010000000000800003a3c3af827e5f7d3107e307b9185768c61045fbd80961f1670693248227ab470f60d8c85a1ca2853e72f80917a012a2e943831b12b5c56c5f240ae2aaba20dfc5730c0f066e02c8ae446152fcd88824efa59e8ab5968fa6f260eedb03a902ca76c8c832109668f3a5b2de6c6d7d7973368e1b510836c15fa381d592bbafe6a58b010001	\\xc449882e7421002cce265df3f36906e8164442c3fb72b8f74a402927917c6d9358dab4dc5b05c5f8cf4c4b06f124265d7de11a67a0c33f1d91fa99cfbe10db0e	1670768183000000	1671372983000000	1734444983000000	1829052983000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
154	\\x70a93a9db6b60cf79387f13797e61d6358839004e80b0507a6fd0bb74be941bdfab47ab62893a8d1d88ca48858e434b12c5eacaef44feb7a94fba9d2c3f42d68	1	0	\\x000000010000000000800003dcb96d92dbd283da5ddd69024e6ed9dad894933ad4ab070a2a0d5ee7e4cb9a008fe3dc0d5aec1fa7faa66adeb7f6a4eed0b7fe2180f1abfaa75ef7a1c302a69000ca4a64d8b6109b182ab934a6b29cb46d6ad9baf2cbc231174348c8187b38c67b3a3e9d660e599e6757d7e2b9d7468e1c66318739e1795ae9807ed378765317010001	\\xd9e31e49f3d3a82e4fcfa06642821512ed11ae9b9f7948c3602dda4bc06da8a088b83e798c57fbb4fb00a007304a81407080ca948452b8500517e58283418407	1667141183000000	1667745983000000	1730817983000000	1825425983000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
155	\\x7269d9ebaf62c1c4789e26c274947e6d0b8064b91ee514b912fe062db1f5fce20a4409ecd3baa0d95ea3bd2843b9d8a68938baadbc95e70180ca25c163e9e3eb	1	0	\\x000000010000000000800003a356a112ec05cc691239473fea7818a343ee4679667bc2b20f023c4f386bd3f780860e10ed60a3eff8a14b5988def1a7121d64143d64ef04d688c17484e0a8595a676ddbc53b1838542dfd0adb618d3fa58a502bebf0ac0e0ee70a752c3538b2b87238f02c25c65233a11107420de427e5ea6f494cb6b9841853a3155449a187010001	\\x810eff9cec047b740b3944af86dbd861cf5db11b2f2ee7a265fcef7ac9c8333d2b0036fdf571fc75ca9a663114313569681715eacff270b2aa525f493f30d60b	1674999683000000	1675604483000000	1738676483000000	1833284483000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
156	\\x76bdeb49ea861073de7db27f9b2ddf8539c6fce260e833e4950bf1684d2d668ffd654f2867ff9660f8e42c1e4b5bf91773412072c6fbc881323161e5ea0a03d7	1	0	\\x000000010000000000800003c858e1a8c501b778a7405ec72a2b397a5127fa4151dd9876a8108e7bcd4fcbbf4cb914d36e894181b2b3c344cb24b18d9f808d75d09afeee5e98c93b67f5ae8abff1ac0ce7656ea3d04d3b84ecc5966909d4dbaf2d99142d1e2190c204d232da622e4eb412219f7b03515d2b2985ba92641944f29e3ed77a9fb9c18e67274c29010001	\\xb1b1d8f7eaf048521cd526b926aa1870bd76c609b769f85f891336c0ef84a3f6431b440206a265823729e87c460b5c19c406ff69b80e3bc540f9b6b7373de001	1672581683000000	1673186483000000	1736258483000000	1830866483000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
157	\\x77d5436e224aa06c286b338170297cc10bc9c2ca6386cb58f6067b6e835ea627e4e9e41b6c9ee5240953ce3cb1387f7ce9426c844202896fdd68d6fed38825be	1	0	\\x000000010000000000800003ac417bd37f2020c84a7dc9d972b3b3a31d048e7552e80f586f2dd9400d42ff2f8b2ebd67dcc034f80b04fded8cf3601c67d68a539cea9de5b5feccba2269a4e0146f3207d99a0837b38b5bb179a386af9a48b933bbebf2a677d2ac442fb1a06ea6ffb4311bd0ccf0ef0962369632b88dc92198fd365908e6434e925a11027095010001	\\x6f948b32d543a9d39060528b1fe5e8eea1bb55ba488e93ddbd270396e579569db278ad3eaf1c73c09d95779200a83407055438a04eaea99373a5c28086e32f00	1686485183000000	1687089983000000	1750161983000000	1844769983000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
158	\\x7c6d037ae0cebc87cd5ed6c349f4460d696816cd32592f37306adb8a2cbaa255078aeb463fd72eb949625981c5e77eb5888c95a327c2a98e15979acd4597dff7	1	0	\\x000000010000000000800003e1dbdd59cb251758766c7b45230dd02cf1ae6f60903275fe1b4212963016c53f11108733a2eac63d975fbbd2c801c5ceecd0fb148c1f4d953ea3c41bf54318933cdbbcb58bc305fa55bf8a4c47ea43bdecb4170d225198239abd65a328a7b6bad1db096ff071b97c1f7a109c91ac33f5f44dad7436a17b47a2a5177af45ea723010001	\\xa1bc46a0341dca6333d3c21e75aa8737059ee3ac557f7944e1ac90187bcd19cb86320a0d1ceed25080b18335f33d60d3780e386ed4f5db71383785bfcaefec04	1690112183000000	1690716983000000	1753788983000000	1848396983000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
159	\\x7d4116a571822dd7080315b04aba865eb2391415fc1f38afbf8aba7f3072f93af8f3f19cb1c2851cb4e0d3f0c9722f8a10a6c10278e1269de98de7995b05396a	1	0	\\x000000010000000000800003e733e95982fc61cb24b51bfce70a64158c82eb5b8f3992b51b0eefd5694c465b92e070c1ffeaa999bf3007cd1f1d5bcedd95e5bb1f3bd131b3b3e90c4c0073564ee84e06f3dce4ba906a051b78a952974d81e0f4804988e67e17752ee5c88d88f8c4a928e67809c202ef89bab3ba42e7dc2f613bca658253d956f99b5dff8b75010001	\\x483a66fd9d281110fb96e339d57969b4354466faa90407bfe4aaa5de7182f433b0c2b9b240049fc7ed9343801e5fc4e874903a973f9d47055f21f12ee0a1ae0a	1679231183000000	1679835983000000	1742907983000000	1837515983000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
160	\\x7e91cbb73e3d3fad540740ca49cf970fad02a4afc51cd9bbfc6e11ec599b04aaf25c478ea16c9a9d2fedef679702795b146b5b92920ba40477882760a4061556	1	0	\\x000000010000000000800003cde2d0310637f4542b84df1838b1250da8a3c7a30fe42ed5832ed503a4ed1ad8c564383eacdf0a169448a5e3c0f277b93f79f8b9365616c2a64b8473b7447b899f79b8801d626bc2f755143b5e9798ea582a5405ac4b8e3199e3b418e8567dc06eae3f50eb20d837952e7f1716226be0004e1ca7f5c5c4bcd091423e061f1553010001	\\x3f15a8d65e6bd9a163a220afdc9e963780cb583db09f80627b074252f7f582ed5b8660f8295e95bb862999192022b1e5904c54fdf0c012f4d76acb086f601903	1679835683000000	1680440483000000	1743512483000000	1838120483000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
161	\\x7e55487bde94c213a48d2930a8d2d3f3d7553ab31d27cb29983e2995bb2a6e237c82c6918d32a2ff473370a75f1992d7b7351d3195c0b478156b1b0426a7b619	1	0	\\x000000010000000000800003aba129c891a65272fd4a659794baf1efd5cb53be8fb1412235e70edbdc779577234a16fc1003751484a4e71a767f592edcf628c815170e4a999c044b20c1a01d8e15c0e866453151e97eabc34abb550deb367a45e8dcd7e35c65ad0b6423af261d6268933ea3a8f818150f6dd95ccf0c640e72fa4127172adeedcb8aef0e59d7010001	\\x1c44e2f8902ee63179da6bdcb5b0e69bb5aae7a6cb711fb1e1bcb36cb91b70ae3ae60e50cce44cc137744d5d872ab057c5ebd377df6cbe0d22069163681b8201	1663514183000000	1664118983000000	1727190983000000	1821798983000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
162	\\x7f0d7d2987729b02c4f0822ce02f46a2416e2d7cda4021c8117fb32a916ee4b7d03768880d453886291d2fd3e8843457634dae2b856934bee8e33346eb8cdbb1	1	0	\\x000000010000000000800003c85e3027c5270ca623b45a29e1848acc60857ac5e486ec9f2839ae400cd1f7bb0c08ff7fc03455f82bb27f369d9796ce313ad85f6291a681e0a91888e3318c7b1373f62bdc2562a6bacab213aea9f5a7aca6f1104a97c9efd03f59e929a22a9d266a2e44249b365894ab9b84d53ea9c1930a68278e4e46edb55e9ff16d118301010001	\\x6c82d903fe4b3406f240bc66e54104624b0cf83c563afde98e1503f3884b8a95d5dce15d13735a52a8fe813f5ced1058fa270c63011817ce7b1b2cb1620f3807	1662909683000000	1663514483000000	1726586483000000	1821194483000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
163	\\x812d3c62d1d98c20f9d7733d52d8238471aeded249d08dc8f01984a680b550c92322a27718e57bc48250a4d26140b845403af9a5a4a536ae5e299ca904ffe400	1	0	\\x000000010000000000800003db66a7f2707a5c1802f8de6ddc58b49f6e1912bdaf552839b8462695b7c9a500871147e9beb4221d118b739e9286af8b3a1928417469c687eb5ca9fe866b36497122f689d30da28f90c2cb33e034d79e48f9b21bd3a370d3e7c38bffe433aa3ed8d7c1776db9de3a63d61903cd328ff6bd9b547c05096259d0a12ed293b44ce1010001	\\x255f19b88eec63e5e711a7fa712fd6485d337cb8f6357a86a5e5c1dae2584a782fdf382391a5cd3298ffe46ab008a668caa9b4a32fad8332fa331621c0f4230e	1679231183000000	1679835983000000	1742907983000000	1837515983000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
164	\\x83d55b3bfaeb23efff59659aefec327a85567d083c157bd83daf1076df3d2786aaa3cdda564fdad1e2e16b4597816e2227bceca9b504a5190f1f413105616616	1	0	\\x000000010000000000800003d85c9157441368452ecbda5cb1af5ff96d97a4306f4059db8ae1cf4a6c944ab3562e5d2397423a6364b12f698d188558127d4c7229af55c15a5343d0810e358f222c3daca01f9193e51cd21e611bbaf5a1d0a1b752c5385c2f5ac70202c6f945d3a7040f6c95d84e40579e89700c4cb877e126f0675ae6f9178baa660d979b49010001	\\xfbb42b1cfdaf539cb0156f85f79193bfcca3f3d241ba6b91f56dcb4b6b3a65c1d92de2964c2015a19c6cf3d9b078967a236f90a1c26525475a006f48cda48d0d	1668954683000000	1669559483000000	1732631483000000	1827239483000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
165	\\x8441530480be740427316e9ab965f50d3c951c2510b0bc1b0866730bd798e8ee696df3fa6a33a0a41c5c5a5c51957e367678dc9d70d9a98330e9b73545cfbe98	1	0	\\x000000010000000000800003c5ee66e0bab7f89a8b7ce043f1ec1c83c166218d899e8ad4c458639220eaa63650b73b53e0636bf079b94f9bf5f945eecd14833cb3526065536f33474bc62924b0c11d2a28c2de5dbfd827921cf008f7ebc3162b500a97758b2ef04055cefa4e1c463f46f5acd55dcc200c8c130b180ba2c3251eefb8e9411d1124cd99264b1d010001	\\xea4f2d2c3d79f300d9cf2545a513a8fd0f30b6a8ab04688fec57981165ac7dcebf4da97fa006760e01bbb3577258f7dd2e89e42fb74453b4d224f061fecb300e	1666536683000000	1667141483000000	1730213483000000	1824821483000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
166	\\x85e1a8b9b06668e3f912d4190a17e7bd2bb26c02bc31a2a676221f909bb9481689456c828b8225aad0076176f2743af7a82d6c3b13d55c05cba33e09c5377433	1	0	\\x000000010000000000800003b1bc5d3d80335d18214f55136ec28ab9cc1420f269375eca8ac7304da194d5382d799da3a97485cc00b629c9ec0c72e385403190699657494c73505d2db9ebc73b6dfce2e77385e72e6fc2180bbbf20f2875ad024169d13baf85526e26384ec5a37982e8d89bd50cd6eab361d6af4b2fc5ab3e2eae3cbd4f6abf6fd33105b247010001	\\x8ea5049c775e1a39446e2b1257fb4d87aa7592898067323c3e5f3a0a29d0d4094034c47f802eefe06b3a099345917b4ae355370b99e43acd2c30e42c4aaafb01	1661700683000000	1662305483000000	1725377483000000	1819985483000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
167	\\x860d21b7d71e7070f9542645ca11af6505bfc0ac45cd9a33796d7c945a395d96936c91e49d227ff77d2f00ef8d529c170326079115a9c3edf06cc3399cd4dce3	1	0	\\x000000010000000000800003c18435af95d3ced5f17c6cef3bb807cf09b993914dc462f84098cb779f73e640b6831a4ebebb3b194d946b07eed88aad99e143611860e4cae6db7c362bf7e82a921addb319c9fa1c23d3722f3938c94fba3694a75af06653516312f328b6fb037789d3cff2fa6732ad90ec2fe9b0034030bcffa2ec07a3f13a4eb752ce10be71010001	\\x98fa6aff47c0e45eb0754432a7dc48887d2d78a90f9799ff73173cdc12cbd2def680214ed18f6b56e28c1dfdc4de84c1e88b3f7da8ba696a7b69d603191d0804	1677417683000000	1678022483000000	1741094483000000	1835702483000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
168	\\x86dde7a8f6c5aeb8ee756b12611bd27c9127f9573f6c15cb29beae3ad90a094b39631cec906ae3954e864e4636d35cea66f356b8ab57d7b0cfddc89f1625a7d6	1	0	\\x000000010000000000800003d2b500e10362db0222722fb19ae5ce5d0f87bcc03ea75630535c370af5b289d795fc6e671e2e038977711d7615dc8d615217f4045db6c18a06a2f6636484aac07697a3929060491f2322be71958a3fc11bc3c2b78021a179ba12e16bf2c68b42efbc8c6bb3deb9c53dd44832e0eff08b8b86f50b51a88e082024358a3b1680cd010001	\\xafaecf19e875e903874465d2e2742fd82c364bab2bf9ab490f42b2a55a525788a9e71fe441360946dfd059aee0ed5c38ae21aa4c233e03f5ffbd6084a2a6f303	1670163683000000	1670768483000000	1733840483000000	1828448483000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
169	\\x8b8536b06420802c410c3c11db9de5ea1d725b552bd36d65e26cb8e0004dc536a9852e47b5ae7841ea6b73924f943bfe5a571b26010601662d462432fe44d21b	1	0	\\x0000000100000000008000039c7e8f55af8b3c0fd1146e715708706a667003ccfb45f84b34816cd4bf7e099d237b37ed088d2280a1c24965fe7a0c7895e7dc0f78c3205d5eb642fe9317d9fe4dd0aba1151cfe1b1d1d168d6e6093608735e5ac0988c7878ffb38d1f584b74b5e5b460b749395d30707591e7b3fa49abc1c12901eb74b9147ab70aa3fde6a01010001	\\xbc23ee59619d653cd0b01b1aab79f9cfa8728745657a5a4d3e38c57292f383ebda0b2199bc1685138ea272b829b77169aec2aa5b949ecd02e63f7cbe0380510a	1684067183000000	1684671983000000	1747743983000000	1842351983000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
170	\\x8ca9480ec0aa6ccaebf451d7f3e5b9beff705a8bd64e2c7da95cb2f9903e338af3b732d4e52ec4744acce83d967bea447c12115ac132907b52794dc6202a717e	1	0	\\x000000010000000000800003e184b1776a243e4860a5e568b027d70fde297683977c8d00052ce626d6b8146a77d412ea4f3a70f01c9fbe8fb366fa446906d1adbb239fba33e05dcb32dd4f0a4f549c3a25205b3c933a128c1f64dcdf1cb6a2601be943e42b20358cbabbe29a839be28bd55e714dee9f14bbbbefc2c971920e934a92858311e52f9a2c7961f3010001	\\x9f9bcff3b09eb2cd1f60db5b2d4f0a4247be6352da506641a6c412c42071abf1e8cbfab8a8e3882dba934ca542dcc2fc88f5a12a21b706291727ae9e93622e0a	1681044683000000	1681649483000000	1744721483000000	1839329483000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
171	\\x8eb5438e90f4b3a1400aecc1c1838c6d3d615271cb70dd4b888053e82773c449ae99a330a611b8b6084eeb7f890f5555a99c2a474f9751246501d299ee194ddf	1	0	\\x000000010000000000800003bf79014ad71088c5adf84f34cb7729e93df22f0ffbdaba13663cdd10928f606d5ccd621637e966d940dc816a0ca930a373c2659cc85a8d5ef33517b5da753b849c8c09c0c48f4ab3ee5e76c5bc2a200c5bd55dea0198ebe2dbe0a626b37f280a109bc4a18944ad03bbb18a29c12479c88bb8ce8041c7990abf23c57380ecb54f010001	\\x7779f92549b2e46d736ad145a5f7580c75e8fca313cebee67275370cb27f1bd9ffc2a946112e2be949f1568b8b4b521db7c37ed801705d445f2915e906e6c80b	1678022183000000	1678626983000000	1741698983000000	1836306983000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
172	\\x8ffd44093592d85f90c413dc28d14303dd5efb02b1df2e9080557cc7af0acdab257f422c6da082275f0cb755ed2032be18cdc24e34a84e0c99f8a3cac7ab670b	1	0	\\x000000010000000000800003de3a0e2ed13c41f950bafe3061ee4d9f6d9dac296079543fabc919d5e919aba3c36d95fcc116c48358c4eafca588829bd087617582fb534560e136b3aaafe3217db727ff38c5fce04af1c49395ce9505b38714bbfdc83249e7487f297a691c11347ace67a0a35d49104dd3242f92d7978d824e3cb1f0e01d9a54f8306fd71ac7010001	\\x16544f50cd787c3db7a7e22647190864b3c2ffaf6b1f775ae6bf1ebf708cec98108a22028c4e2cb60e52b1062a1861bf677bf35c29bd694b7e97cb2c8114bc02	1674395183000000	1674999983000000	1738071983000000	1832679983000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
173	\\x91c52df275c31d48a7d3cb6ba4d04b4fce394621e3b6041493e34e82184a44a867a428fdb0fb69e4efcd7b49673d10924670024363f80bde688b2c7e1c20656c	1	0	\\x000000010000000000800003c1f157aa36f8128ac5e15cc9eea330ef69f3ff869d8679379e65acaeef948912cb1687f2c64d6461d496b29f7e461f695009343cdbfb27ce51bbcf424b874c535101a7f388cb16c4d63bed3ea6349c3e4b9b4bfcd3ffd2572a38f010de0eb40742fa747ad974864d339dfa4a3d42609369dbe0f5643c27acf226eaabe65e8c11010001	\\x858605d1bb04caee01981f001d704353e61ad7bcc1bc9fb1bbe74b9ca166dd5443f00fc296c6c3089dc06f1bd36973ebde4776e786eb32a897bee42f8941520a	1689507683000000	1690112483000000	1753184483000000	1847792483000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
174	\\x9bf525ba3caf713107d1826d5b5b20d534b8443545d541a128f47c7378ea9024a8bea97ad37410bdec6680b490789764704f011fd4d516a0b52dbf0ab2ca1f40	1	0	\\x000000010000000000800003abed6735c3d4f4037c71322d889ed5d2921cebb986d058f4b8ba07bfe65c7f2539889b4f02533de3ad7dbe21bd85116ba5c3cf90c89762184f3639ba9889e314dddd6547e7881ebf90d08ebbba53b9604fcc604be7956c981c5b42c8b0c46fc4d507f48415abfd39969216942d02d4315c96a856db9660e799d0fd2e9aaeac75010001	\\xe1f09f14bc63af7d2f0dc4d165c4f103dc5f4e270ffce01fa2c115bc459d12279b67c5885ec0d1d35034ad7eed617409a435635c9bcbefe1937046e2a299b00d	1672581683000000	1673186483000000	1736258483000000	1830866483000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
175	\\x9b657213b92ce4af7eb5a55e5384f619f4fc451e433cebe9dd900f350519e76d544ff9e9ac2eece2f7281668fbdf8a78ad2868d632a1223afac55be9a02f39eb	1	0	\\x000000010000000000800003c5908ac4bc4c72cb104b0200e86e65c1a7423386ad74e2e4f24747445f3aed4c8cbbad72ef54f224a596c1e6838618ac86ccd2834896b8b1f1ac5bf6e388791864588ef63300d925468761d71c5bf7a7e9cb8a2684375b6fa3fca4e60435d430eccd5156baf688f6b2cd4e136d33a078e9271137944a0ae41424f826c650db4b010001	\\x5be97ca2989951567d97ca4b69f33ad56dda0594d4fe82f165f189e9465a5ab9d5d90a486f17758beeca44c778a03e872aeb1de235a97e4890f5d82a9167e108	1662909683000000	1663514483000000	1726586483000000	1821194483000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
176	\\x9ca5f81b1f85c5c1d404c66d27d962bd8d2a99e01b13e13adaf44fa3a2715fe84d532079221d5972525dc0661c8cd80f3973d4db55d3601321de1c6846b2f6e0	1	0	\\x000000010000000000800003d4d1c3c83d24ed2b170b6cb4fc6318edf0230e3523610b8a99241dbe8daa1b7a7a15cdc51310675d04f4b99c086d7b462fbe58405d27c5438a41efcc822d6513d62ea85339ae508a34b7bc1edc225500ab10bb387929f44a7f9f02e3223db8a44880bc950419374b3c0c7a03d606d7f8e60755f45e8d6ccae47d9331df413931010001	\\x927bbd6eb7c0ec99268c5838b97d18837b78c201d5703279019f5f2720d6b18bf15332a1c747955e94839708046ca4f09955ec7142ba4173ca0ab3ca5f46db0c	1667141183000000	1667745983000000	1730817983000000	1825425983000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
177	\\x9d711371396d530c89b4037fb0fda9f77e5044ca25ff834469a5207ca13719e717baf56e2530f0bcd0ec019c1f4fabead7dd4349df946a2143ec5b4832665b53	1	0	\\x000000010000000000800003c0ea383a81e5d410f5a7d93ec0e78245bf7e43cf02dc8af8510fa663a5a543ca6e3ef9a10e323433d32c291fe2035142c88e33f576747e77f35997e5f22b46a7839823b37f9d7a0b5831bc67d96c9e1c51cc216e4dd6eceb54374a6cebe766748196d9cc5e58872d8869462ee3c979ff42b6e758ff369ce56db76f3328eb1a9b010001	\\x4a6fa330a75f4fb384ccc11dc5ef70c3607401ec2ac19ca393dbbaa566000a1a9095266c094adfd0a62b7a2c445000c0cd8ea440cb700b46d2f45a4f46e8550d	1688903183000000	1689507983000000	1752579983000000	1847187983000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
178	\\x9f31005a9cb1197374177a15790991104e86f452f7fd2861033b2b9fc2b6ff5ddc6bee4901c45564fb6a40c836b720f6e65cb1d9256d6b5dfff0746a2410d10b	1	0	\\x0000000100000000008000039a148b0e622bcb8e6b755d41ebffb19f8a6cef61040f54d768d86609c91cdfdfdf109533ba0a6a44e45d6a008323383bfa9fdde612e302f51305a74990b4d82947f95ecebe55e2ecd6be2d8a1fc74e7ecce4af7c71fa055f6aba0a9b1a3dbe0cb394bc2fde11f8926c7d8bcdeb940b086d7072d5df30689b1683d1c2b55d6321010001	\\xdc6e37ef9f655489525b479991ebc7758936da8ca0638b840a8bbec5f3e11dd95981b9f3f80e67cccab0c2376e86feb2a350337ea69e15372b4778bf6c3eb80e	1678626683000000	1679231483000000	1742303483000000	1836911483000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
179	\\xa0515dcec3c091c06392166de585e57c3adcbde832ee6497a9ed5007bcb2d5a64596ec0bb95e51b5054df460ca370fecd2a26353605331a6ebe0f66b8775a055	1	0	\\x000000010000000000800003b190778123f5cdb20ab7ce5aac5f9c42548e97c7cfef7806b25f97a81c6129c80eb9f271271864bbf08ae7780f772fbc8f281e246788d0f2aea010dd7a351dabbac4846b617561316ff25a29c1638a27984d18024e8f96c2d92b3cf5d69da206c00e56537e64f4f570cfa6da664e4c262ef427efeb9387010535fdc3a1475e47010001	\\x38e39d9d0af91b845a264cfd8d041dc5d56a03cc822b493eb2d6d49335efeb96fd07b6104606b8706deaa396d62fe859a147b57ca6746410a51acd060928e00e	1670768183000000	1671372983000000	1734444983000000	1829052983000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
180	\\xa07dcfa92eaf484715fa5ba9b2834579c2921c035f31113ecb0138a72a4f3a406daeb0941c2c15f1e0e0892ec2c142757724a3564ffaa2eea888f8d7cca9ed3a	1	0	\\x000000010000000000800003aca446d262e137d9ade12838f207f8e5aa1f2df444825665eb7a93b06dcb005aa7413f4c53113aca2b14136cf96f57430ef4d61eca455822ad83593541f8416bfea8580f9aa0e6e377dcaf5720a3eae3bdd1e8c2bbaaeb9f1cbd8688486f7af5b12d92439808b10c525e569bf8bfc9ed53f360904a480b29e94f5708a9ea5eef010001	\\x40183fb75a9e7940b3a1ed2f2d2ccf23456ab7ddeec280a663de0ae3644e9c42ae0391e8f36227eef7ce0c848b0c1315b369d66db64bf2fe265fc5957a641c0a	1676208683000000	1676813483000000	1739885483000000	1834493483000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
181	\\xa33983ac1c28a99261848c0abe2ccbdc5a8d0dc08aa7bc31a33e7434623a81662133d80a645fd2fcba40a8e3526b8f6e2c0db9c684b454332d45b5cfaef48113	1	0	\\x000000010000000000800003df5f022ee839f26e1496d72391c90817d4c5525893a558186c0372fbc35784e27ea65fca4a475dc5462593260d0091182a32f4be5d9d7c4391d4a826d3bcd25473b9dd0ffa33145c98292f005bafb87a69ff4efc798509337f1e25aa7a2e8eacd37d942d982d83bf0236856296975134b84474927427c48c9ceaa277d0c9c6cf010001	\\x7ece34bad75391a28c39d62fb9b8cc26115b15a3b6e0cc72456a03df87f7af736c1041833243b57a252621189a20d03254c6fb55136892df2e61f2bebcd35203	1691925683000000	1692530483000000	1755602483000000	1850210483000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
182	\\xa5756a09cf36567007503af9c9e70fc29818de4d119cb62f1b5da373b002211a7dc2bbb50ad7f47272d4c3a4c55f615c81588fe291afd817bb2508498e9624b6	1	0	\\x000000010000000000800003df6211840abe132a3daca4d391c4cbdc4f590a2e474f1048cf4f7e1ad573e06d4d901a6602cf28f9a84e7b8befd036ca22e1907fa0fc269f962dc814318f6a9496b4aa338fbc662ffe81657e61a7265914ebb75d6c4f2aea8aa36619fa872bc944bbfb55057d45ce3ff1b9afc9f02155c093aa9e40aede60fde8e98df6063143010001	\\x15c108cb1b1ee2546073db5adb54a5fabc019644e455f82e52910784ea8d9b3d4afce1ebb3633e2b95c025585e0d9f487215d837876af86ad3d94bc80b6a2d0e	1684671683000000	1685276483000000	1748348483000000	1842956483000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
183	\\xa6092ffefe989033749aa9ba4064d3c1ec1a5e98ea94d0e01699c68b84d990d2e6a82764de7e2eac41f9cc75dd5ff3f21a1a14c123d40ffce626f73b07c4f3a1	1	0	\\x0000000100000000008000039ac4b2ba92460e78e04440bb9c24f39559b62aaf8d10e7da7028741437bf5fc6102dd22a0ad7b788a534a4fc88da6ad7d177b7278cb0f65f7368e0e14744973d129e53c88b45a5183becc0d9b5aebdb05fa761ee003ba8a48a4e8e17b0919ab7b6954de713ae0c585376fb59f365af075d8121798e776772668e442eb2fbfb49010001	\\x63da54084f12a7db905febc5fa47a0480748aec1c6b399f5de0cb19f65392bf46372f06fa751e97ebbdba3db97d1730290818e98407b1ff2341ec40a203e0b03	1676208683000000	1676813483000000	1739885483000000	1834493483000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
184	\\xa9e9779d0870bc265765309f51e497a4f0e474fcbcf8dd373b631580ed1d1c1939ec0778bbdd257b8149930efd845532802186fdc6b0899da68da352d0b7fd96	1	0	\\x000000010000000000800003b7b0b1c8a002a6fce349b56730ad34ef5933c1ac238a07f76df5af77d9ac0fb8e0bb827b99d686639c21e1179a368beb0cfd034ab01c380b9251936234f92583b6af5bdfba042f2c7f0a524e5afbe0da301e58a35ee8529172c877c275580c1795b88991617c46ae01fc86ff36d06e9c4d151350fd09ed24e11298447c1c9bed010001	\\xa486d385032eb01584fdcdc9d283b148e79c588b4001aeeee0a573d6ee5d29e507ab733986e752838a1c477f78ab8d6dbe22c37af1121917ab408b5143c37e05	1670163683000000	1670768483000000	1733840483000000	1828448483000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
185	\\xb225ca6a403cc1f3fd548998e0ed181e74e36b5349706f7d8ef8364bed5bda8100bcffe00fc64d002be5d5f83190dba708eb2de2055d1eb203f94b9c163bae38	1	0	\\x000000010000000000800003ce4ad8dc21ea010d4b54fe3b59f5868d7cdb89e1f01d452c18e91d1b0aa4f73a0a398d3635e1ccbdcbf6a1d658b947b33907491bad5c87d54ece9a4dff60749e63b23e8acfa3c0cc662a5a5979ffff2d4a40868048b151ee66af299150e1392cc58143287fdb28e266ef7bc168489b68837fdd3f39cb8d8f3b8491ebe0c6da9f010001	\\x5b193b6d8293d6275454b753193f54f40e70b44c425519ff46354f6e04096d9ba66bd0c0bd202b1a349602ce9b653e1ebc0b26953400c06339d7959fbb4bce05	1677417683000000	1678022483000000	1741094483000000	1835702483000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
186	\\xb6e5597e3965d960c04a547ce69b0aacaa92c4ff7ef81b71ea18102ce66f490c8ca2809a2667aff836087793693f78729a1ed5c2004045afb706b1a3fe79e002	1	0	\\x000000010000000000800003a104a8f0b104cdae290520424239174dda856d86f77a715a62e03125e5e00a860e6909e647b8f255046db1ff363e64c6d120508901ade5691dd0c0ffc453c7f7e1c53c08329e79067b20bcc347a861216daa3d1f95929ed6007e454db7c2d706edbfda4f4ec4dec517e35a7798743ccb590a1d96884f1e889ebad1848f8fcb8d010001	\\xf5258940fde992bd6586a7c2a26ef11457ca26b5253b74139a33653312a7b140f7abaaf5b8c376685bebb4f6d0d2d67638cc6f44a648388080df271fcda0940b	1670768183000000	1671372983000000	1734444983000000	1829052983000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
187	\\xb7e923ca8bff3d6a4ef72e240602e896fd699ff711c59272bf5d3d2bc32326150a35a1449069bdc5d9319d87ca99ce517ca8ad1fc8ca25cbb71e0c9eda4a6714	1	0	\\x000000010000000000800003cfb79d63464ce92b70819079cdef7ab72f6d869b779dbe67969af8d7666de08a2d0d995c689004cdd1282f33b506aaff896ffa4a2592243542233cefeb3f951e697e3104e1c33a78a24edcbbe3a5e545f32588a95e61b01a2e338feeecc4168921be332099b1a2ae3b16aa39101b9fb846d8d989d60dcd3dd45441a7bead7e17010001	\\xa3109d9e2f1b820c5734d94300eef6eace8afaad66c639d2e39262b589c1fc905c37a9a4ca24187235d22eb830f741c98d7e422b6ea9bcd79c6cfea13f29a003	1682253683000000	1682858483000000	1745930483000000	1840538483000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
188	\\xba598e873d9b420b0689e4d80b1986490164dfee8fe4f64b95a63df2e5130dae89703e45d5c476ec5a004f7d7d957f4bb7b1cf5bb430ccf1ab01b70c928c7e0b	1	0	\\x000000010000000000800003ac8d104fd69b72d7a3699b2578f17fb1d5841bdfba7e0253aa5c63470cd820cfc10ef2d3dadf6a13ecb161fc7b7eff5ca8c1799b6b2906a175d15d66cd951f5f49b3d30fb500ef07c2f254b9f02a3008796e4197a4cc306704ecdad819212cb8e039d7c231f68de8b7d98a7bfdee3e22ecd0de0e17a95c61293cb22aa52fd7e5010001	\\xfa07c8c3fe020e1c151e486ee106a50a6b9a1f6c33ad7bead84c02b2db5234135a73a09a2a96e449c3233445de8227d2ea871ac9b663dbdccbedcb144bfae808	1685880683000000	1686485483000000	1749557483000000	1844165483000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
189	\\xc1b999b4defb095f1e2bc0fba3c1ecaa444d8709cb557bf6bfed4570dd314d09ca87a8765eb74a208d7af9bd4033e8ffb26cb7643ff9fe088fe5a8e7cc82f223	1	0	\\x000000010000000000800003c9e6be660115a1ff63a893c84496d8c24ecdf9a7b81ba5c993e401dc8e7ea0f278071f6bd3ecba3417cf35146a2436ba8444a49407f453f764db1ac1bcfb0bc3c76e8acad526fa07bf5b162cf4686e7c460695635b043b73382caace12d522460102eee6ebdc0b3ab559fa385e25099c37a0aa4bf759563f6d4940134ebb6ca5010001	\\xfe6ad47e97bd757533f86a271cab3cbc05f25723ab027d79579d46aee778b1969f68cbbf47616f3e0c17b8e2cced20fef10a14b833bb7745148c33b2fa978c08	1691925683000000	1692530483000000	1755602483000000	1850210483000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
190	\\xc2f595ad76b7913a3910c8cefa439f17ceb712ffeefc8658b8df9129400d9efe4c85c11c95ce00afb7b7c130f08734d1fdfe2edc32140210912b98a970ef65f3	1	0	\\x000000010000000000800003d2da2439d93a4b33f708392e4a8d61177c55821d09b6b947a74c5274914338aa4354c39fb88b1ca2c18bb812ed9dbbfa27e1c92093da4f52e45a8c87ea897e0aa8f8b440f7d5083801b219366b75c38cfc9c4ea9be471020121f46816f7cab9acf915908dce1a2db42a291b79c4b4fd56af65f1448253730590259ab3e6697bd010001	\\xd0e14ac2c1c665198316a4c05a26f8fc877cce635f098ac083fcfa1f098139b8d4442b099365b54971613add9edbf3cd6f8f99fe93551d484c02097cce900401	1676813183000000	1677417983000000	1740489983000000	1835097983000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
191	\\xc41578febb44a554ec9ff0608b0e13f62753a9e21d2b878151868890a3b7aa5bef4e94f3a4c65dde48f24c2b8af7af1d80862d62c5c8b567ea04fe041fbc73d1	1	0	\\x000000010000000000800003b0c2e3935c869c5d7e9e9ab234629e2f4f1dbffa0ecdc0876be2c552fe27e1169c8ac58076eebcfeb0f6a7b37d4e6a58bd1b2e3667b391c9ae9e287f3bccb30fd44c3ee15eae71ccbdaecef868c97cdb0e0d2d5e136c85c608e345d625c9279b8f99d7098cb35af8b7d8f0167ddc3b5e364e933a4795d588cf7e7a36718eb683010001	\\x6e765a4490189f2d1882bea747d628a0352f2488fb3b0165285d9c54fbaa633f36224cf944a1d59cfb8ee3433b390460bb19335bd3884a43791c8ebf11ddda0c	1690716683000000	1691321483000000	1754393483000000	1849001483000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
192	\\xc76153b19661a2ed8a384f6b333f53af28b48db49f9f512b90af103165419cf34f4ec5843bfed137b56d38d0e7f2ae2c93f7a2a8dd0705477e00ccadaa5faf16	1	0	\\x000000010000000000800003b66e3888fb4ce4e25daf221139a0ee072470a193d7465ec65fd09ca2c0a9ca7ac8cc685c28baa8f0fca27491d6ea67492570d9e65fe08bd2fc5b923434672978d028197d720c4b9718f4f16fd5ebf5d5ed749f0f3c4339904e3ef640bfa71714b4d921dfaca453230c6567f09a35c45777240e3021f8e2373d3abb029c729e1b010001	\\x17b84c8207fd3341da4b409f34a20d77088ccd9b2e5929497c9cd2f508d6762e2781d36dfbf23d81ade9667f495d549cdd988f962f6abd1ddfb50225fca50306	1690112183000000	1690716983000000	1753788983000000	1848396983000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
193	\\xd06df5a5e93e1a60ea7049f4ab748340067108e4567306e1f14fbf7e0d3d3a6a0e54daa062858e61ad0ddbff9a7cf3fa212ff48e689dd2da7c7bfe087c64c544	1	0	\\x000000010000000000800003a56d46bb3cb891409335db18a55b599b30353692ae4873967daf76329e7e8624f3b804a159b723583c4093c99fd96ca7d90197994fc634f7d571fbbd6146212fbf6a587d73f6bad110e7505d7a2eeadb216a9fc68e8accfe925d7751e8027c4193e2cf02172bbcc6432d0f54e195c2e7b61ea4b842ffc2bcc596656cdf7a5259010001	\\x21fcd50576a8a31d9214cc34f89c7e9c84b8e19e36f9201e3361554cc97af7e73587ece07fa820b7bb1741a928c9aa8092631f9b5b33808ee2efa04a07486604	1663514183000000	1664118983000000	1727190983000000	1821798983000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
194	\\xd0ddf47e2b230433900b4ad10177b95212000249b3fee627ad51e5f68687de2eb49ee276758d5b52b2abcc99724558ce101c1562e10276399f54d2d1bc01617b	1	0	\\x000000010000000000800003b41b562db99d4df9eb8bc3733d62b023ef38d06620f0d685792aa18103d3e3d226643eadd715c68f57724da0bc0e55339f4c70fb84140836f3d13516fec70fd47339bfa4c5f16c2cbd7726d64def18bbf06519a0ef5dfe5790e5f0a44c1c871e52a23be521a7c7753cbf8d7f1baede9c06f14984736f0440028adce41da12b2f010001	\\x22c754761ef37de4569e9598612dbe6aefb6b9620fd275bafd6af2dbefd2414602a78c207e559513f061687b9888c2e48e5ddd3cdbe81e6afd7a3f5d77929f0f	1662305183000000	1662909983000000	1725981983000000	1820589983000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
195	\\xd1e96a7a63bdbc8c289b93a31a3884d579a5e6805ba2c0bc4abe3dfbd8f58d55af16fb37f37bca84b7492749cea35d560dc02c2664bcfef90200ee7c8b98d003	1	0	\\x000000010000000000800003b7b456e24daafea667d52e66cbfd55964b2b89daf169d26b8f7e591da927d420cf5c0721627e10278f0707c7692efd6ab6da1442ce8af7c8086c6d9db53fd29b15e9deb91e88074fc72ab5cd08ae370dc69a14ea63a46f6ff78f1f5476637d1337447c4fcc67d731da7e90b3553ea696aceeac7c6d8756a27f1e387da2b05a69010001	\\x4eae6ecbaf05c480dc93b26bc79be0e0fdb315284d8badc2166f41a1bc529effccf3a10dcd63b3a89eee40808c20326ee99cbec7a3b138f7bf16e0aa625f2908	1684067183000000	1684671983000000	1747743983000000	1842351983000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
196	\\xd1311c9389cdd98d03fa8701b9f468daa84fe4599b26f4963140cfc5497a89cde2e0357e94504766dd8825356b6779c4ea4d9df7ac4b25f6b29493894e17d5fa	1	0	\\x000000010000000000800003dae6abdf332ca78dba4646cb662b740acb662e905e2014a4a1ddd7c9dfa795b81c3aba14c343b2955ef995148cd928e4e105b978c1fb8b4ee9bdf9e0d4c141e3e3ae8fa551051a92039875b8ffcab8df299a44228c401c47b2750c61ea4b09acb98f9287a500c3779b48ec235b682d0c851f1cae4462a10cb63fb54b841c63f1010001	\\x189a904d5a4ff842a74f69fff6aafa7e41a4a7dad25cd8687778a5c4bd701308383b8f872d853e80487c091f110607c3b9de7e17ca3b3ac80fa4b956e470cf0d	1667745683000000	1668350483000000	1731422483000000	1826030483000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
197	\\xd7557fb700adaababe6c05d327dadd0340a3c595a9cd1e5adaf765dde6c3d01d8586ed2f5ad9132e4f57759536648306bbe04167c8236bdbd5cfbc1653f82425	1	0	\\x000000010000000000800003eff2b1f0ee4a189a7e3bdb78ff749eb185b171fbd966a170e0c1f53e9fa99c02069a05e7f7ca8dbdb0eaca2048e90e37378bb2d4369eb5cdaff2263edb1219524886300ca930f9a95ea910a621bd3de8031c03a6c9163d5a0508ba3470dcd05a9c8ed152db12548a36188777e156adc2160605e0f47d46e80c6507bbd081c6cf010001	\\xb0671a3d3c56ae4c4979d4ac04fd00f65a6685cb6ebc30bf7993c97f2d7de8a3e7eedf5ea2b4cde643c63b81a7b8d9d824b36b24e659985c6bc1538258f7eb04	1667745683000000	1668350483000000	1731422483000000	1826030483000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
198	\\xdce529a30242c0a14cc4878898e9e287a9a41972b80851a1e3ca5b1f4f7a95b550dcde945dc9a8b4b369040629caa28077a3060c0c8974e1b0ae03458efff932	1	0	\\x000000010000000000800003acf0f89d8b57831f51e15e42b7d5aae78efb42e6c66fca7e45cf5673a2e9f6d664a254865d6fbc982e1e30c23e3d8d9e67cc83ae428ed5341d3344c93fdb5b55121de0a68f44a69f89a4e48c7876b5e65897f275c7b8c53208009dab523909f2f8324036d30f07d1e807b95359a5a531a82ba55d3e3838c98d0b27aaf22c2641010001	\\x2862b1d6a822837ae46e7f8ad39d3e8fcdf5aa50596a57ff60dd5c525e0bbae15a0cd2cb071cf5dbea7fad1be13471b0d7bb587f49917e0871f8c14b17b5c908	1682858183000000	1683462983000000	1746534983000000	1841142983000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
199	\\xdf5d6ec11e9eba999f20481f7b32727b150cfb30ebc2daf6ade185be0d171c20da7e17bd022436a616ab83ede8031d0a4a7eba152c9a6ccbc44f6426c87f8281	1	0	\\x000000010000000000800003bcdadc5757cfd475c36af5ab3e2e165b381550c6ab39a0a80db35adc85d9c51ee07b649db69831b4a6be7fe38e13fae07bbe22d0632af90277b961b95bf8e743fd2b1841b2511df0e2bd316b89a3931069ec61927ea9a5b147f4de72ee9c3c080efe748aec9bbede2e43c96a2fc471fc67c93ae743b844fcef70ccee7c734363010001	\\xcf9f7786889d27e97f498f7ed0507718a265ddc72bad4dfa453699a3184d09390afa693ad35999367d93cd919f73ff3140cc05f836535a37e5e6d2cd9724f606	1670163683000000	1670768483000000	1733840483000000	1828448483000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
200	\\xdf6da602bab20c56b799163c007f0ef26dd4fc88066f0b36b128f7a2f38fba853091b2f036e94e7b78ecb80b6c032d3954e3b0049a9015599a4d460eb5391186	1	0	\\x000000010000000000800003be8ff3ef4792f0218b0bbc467b81a91f4887988ffc528672ea4de66621564f3916e4aab390d5cf75cf04b2f6d2c472c0e00bc4d4949d3ce2ee0b54f6358171b0658da8c9cf55ddd3d170c5d83df8242ca7bd556e66c8aaaf1bfa0d59926571ec783bb8732f6fe24e73a473cccde4dfaee39158bf89ee7d347c972f88f29a2249010001	\\x8810e7169743ab02d598f16ec045df4facb5e9b3eb8e3d34b1c9d891b19adba49ecc0e8ba7cf01213832901ac481974c7544e8180af2651b7ddf630caffd8500	1661700683000000	1662305483000000	1725377483000000	1819985483000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
201	\\xe71dab176d6a5d7e92521f129813e3c22893fa61c60c45c4d5e67e4f72f60f0d589647bd542f19e63dfba5668c4ddb860b4ef15a209faca715e4808f721abaf5	1	0	\\x000000010000000000800003d9c265f00662e6162b9e6b8695e0cb44a7c692791ecdc906445b87cc44283d8c257fddddc8a1c295f350ff14f18e2984182ae53d63a1ec53136b4f17c985fed2d8da20e03b9ee36cabba550bd77b093faf7cf6c23c0c5c65119a16560c6229d7044680ea9b43362f34b74786b218ff10794765482f2ba21c314a406d84bedc45010001	\\x06cd45ee40790bc909b33b6881534b8ad909cf9a82f4ded3e72c2b88047eb880d8e16f61b1dce09dd6016fb19b007aa04b3c6fd514ca6e7a42233fc740ab440a	1677417683000000	1678022483000000	1741094483000000	1835702483000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
202	\\xe8b99572b62068426440cf787054a449b8bc36b753b7429a1f25708c01dbec329f368be2399972b1dc98fdbbc6c2cd3ada672828d70275d8fdc69d5de7acb32f	1	0	\\x000000010000000000800003adb161c2d375f2ca27e50afc7f3ee5b1f096c8c1b72610cdab7cb03f1c09e0dc2475c5b6d7464068c34a90c5047de9729e39c352664e4499aa0d054e658c1827acb141356c5d82567310427af04152961e226c24a7e1ef472d13111068b93fd1efc0ff847d0e386ca082887e090a520ea4014aa15e873536761774c67ced593f010001	\\x81a7c85852a6582c93989e1d61269ba3ecf8a4efa5de06848862ce9bce45ed5ef76ba8dec1fedd87addf5cb852ca74d07737b426175a6d05f57e6e67a78e4601	1662909683000000	1663514483000000	1726586483000000	1821194483000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
203	\\xe8219c14fdfe2f8ac30e3705a6d80bfe1e297162f59f82bfddf538313b5825a9916c414aebc023fa5d63bf87cda1d13c2bf292b4b28cc3b786517b7c727bad12	1	0	\\x000000010000000000800003d2caba6ae2f21ea2f307395c142f741eedf905f89aaab95522cbd08783ef127fc900206fc59b9da372d579e68545aae87ae190530fe5adcb455a84383ab35d9817d75621c5f2b4c24f10e9d9ee056c478cc050321ea9ac1e189d37c7740e5eec0417cbec90649193c43c9c1f819082533d7b998f65ec8ed21d5a322f8a5705d7010001	\\x9213a4aae81d3d20f3a420d5a3a5acab343ccc1c83495fdda5ce453fc2c19da081465ee4fdd7841ad608a8c310f9a10c18a8509e460f483c509590a778cf0f06	1674999683000000	1675604483000000	1738676483000000	1833284483000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
204	\\xea2509f40227753a845eb08aab63f75d4492d37db3f658c92fca139c5c0c648f9f799537c5b057e217128530b96d465583002242fc41a602d13f1097c6be5235	1	0	\\x000000010000000000800003d2189a9506e5fd4ae408f7876a5391f0eef6107c84770ddfc7fcd69f49148992033c9050e3a44bf90e9bbd5dd805284ee0c5e953a7fd9f6c35ead3324128fabfd9bc64a48e88012b579f7faaf5d05e3fd512ed56c6d0747387db0e2b2b85c774b7b7056dda32a07f1e5f3a3421c5e5fccd81c1aa875160fa753c4e590352c283010001	\\x704b14b3ee1afe5a75154399e431869d1871107f56dab485629f63bb83255a481c2fa2e74f21b942a590210af65cdc978cec34361b1b86563932a2faefa03403	1668350183000000	1668954983000000	1732026983000000	1826634983000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
205	\\xea9dd8b096cb26c37d66ca805015f0e9c4294ca4ef29cbd517f514f312997ef2e18628529e8b89cbc88d0e5e29c180e139cd0ab3409f4d2e92a8c18a77365f94	1	0	\\x000000010000000000800003b9921f2b37dfb375d80ee2509000135d17a4e29c91252b96b72c9e61f39dfd3ccf917f0daaa83a191f07cfaee8def0d9429c3bb3b82a1363a7d01e7a6a90c932f6ed2ac972631ce7b1dbe78be0dc3e52c4681285e3a2f09519eb0e528c0e2ac00aa946b9ce8924641bcbb87ff0cdbc3904942ceb7084e1b2e906b039c0419ddf010001	\\x2f6a2e82348894bebff09cebe11382331be9a42fa1d6632a0160a480125cf2028f86bf983259108d8bd96d0f36ec007eb27ddd72dc100452ac9f1ee2ac281d0e	1673790683000000	1674395483000000	1737467483000000	1832075483000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
206	\\xeedd57db367a66da2ccd932ec7c00dd57ff9c165822bb9a275207fa7dbecb2bf745a1710e72497945490d73fcf6ea268408ea0e65fef9e35f4cf52b6890ca4ea	1	0	\\x000000010000000000800003a296ae7b524d71c84be52ab92d811c7f1b0b5ba69c7d4b48f7023f5dba7b0e0b227cb45199c2930fb664ea29b3a19145be484f114d1074609cc47726e2f4587bce98b438d04b63bb14736ffbc3b10c2f940b88f4ae583158d23677f4ecf226b31d455f6bb44d1ec30b7c61203d11746d748c614834cc47c8f44f2d900ae34ea7010001	\\xf0fe73a40273d768d00175c70ed455da6e1686d7a75e9d0cfffeb9401612f7ddec131c219297e7c8f52f36a8b0f24736de74cf01fa70b4af02d18f9b8d41d80d	1662909683000000	1663514483000000	1726586483000000	1821194483000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
207	\\xf025b56064cdbae3d859daabf0b2cbf8ef5b5140a580c9a7253cfb640d7ed39fe24ebd540cd6ac72ae93584f74f7abc6d93ab83e46577794cd44a075f2fba82d	1	0	\\x000000010000000000800003e9337b2e7236d5a3904c8859d94138e8bddb97f43940075f87576b85072bd4da5fb7aa4a5fa0450ecae790364048ac991dfed7b34753ef47efb1c3fda798d297e59a9056cbb951acfa8ddad3a46b9c12311bdc8a2eb28eec3896ffe4379ab7994f9dea898c0e9b309f11df52aa15820f0f3af744369045c9d76f2a4b1cf7c39d010001	\\xa5d0acf0be1dd6c83949f1af7e3e8fce9ac594506f00a22a65401cf2809b2d55c7e5f650107daec702ba4144503430904f53ac5f0721d65b0751147870179000	1683462683000000	1684067483000000	1747139483000000	1841747483000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
208	\\xf231be46cd0245da3c9a25b54b5c8a630c8a748236030d377d8b7120c2aa13cb60048257907fa0f49abd6e975f347024dfa7e27ef295e1b55424ceb5018eed24	1	0	\\x000000010000000000800003d620cf45e74957f5cd1bafdc5d28f64fd59ff5f257cb45b1159a9993c3e3229624f41d7e2f4696e92cc4716c10c52ab82b8d3c9e6e54e29056bd58f082659162fe23969a9a9aed5a828d6ecde52efce1aabcc28fca37cfca4601e5b7ab943a4b70acb4f85b6d3f970d16da62456f78001deb0a4436a3f9637274c86941bfce13010001	\\x0e554e6a27a56f89a5c3317fee888238fa6ebda5f60c5a0e62d87ede05e6091733a500ac6fc53c766d45fdf51bf98f7aeaf649908d90913affbaa8402ed8c406	1679231183000000	1679835983000000	1742907983000000	1837515983000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
209	\\xf411d25ef30c30a0ce35860c633c125d613fc7c46e8cda3eee6da66912af2314d038db6189a2e4546a9e93fd1b4aa8542f295c41717544e3c7eccd3d8e03f232	1	0	\\x000000010000000000800003c0c627943ce53f31c1b13be8e6891116ee63a895c5598d8ca79fa35742eaff499b035ba75bab14a7f548c3438a85ed3c4ef5986006e5ad91c90abce1fa2efe1ccc00fdeb9d2729d23b139f62591f3922c94086d9a517efd2c6c2807c8d540867fed549840792b9bc6905cad79d50c44a3659e0f9798f8ba83a02437b4e44d253010001	\\x0dad146ddc4d6eb58c9364646f8d43b87b03552ad91769dc20b76ac2bb6fca610235c8913d0bca82b8c73ce264d0da1ea0fefe1c73428c61184df07baba88e09	1691925683000000	1692530483000000	1755602483000000	1850210483000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
210	\\xf8319853038bb9673d1a58f848a1816f10d2880f05abdf7adf99c40a65a67a5109f0b72d86ef289fe273684f26322b0db0b51a2cb9a69eaa8793ffbaf5c43363	1	0	\\x000000010000000000800003db79d2c62f9927b9814cc5579ec7c32872ffc2e65d39242fa3742e28e734f1d732d7c8e0bd83ce53fe7266e1b39f0fb516a1fb02da8632d54ac768374f78b1b57275ba1aa51c178c3477ee15632960435c7df013c8da25cab45377f5463108a6e5731404bd0c866196faa377e59d37a9f715e0b8dff8f73d40c8ab9309684e43010001	\\xfaf40235e27747ef4fa9faba7f76728759cb825d6bc8d66417e4ccc0a4c65d85fd28cdb6c4b6443b7a33267a38d38edf69487d6bf806ae4371d1a38205b1d209	1674999683000000	1675604483000000	1738676483000000	1833284483000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
211	\\xfae9153d18e0e63e03078a43938cdeb5b2de8171ae6cec4d810ee30931350f6e8ad60487470152c644c032e580d402b763af661756f1b7e4b3fe380a293eed9e	1	0	\\x000000010000000000800003ba993f87b9fab3fd569f1b8cc0174ccb7fe523a52d43f709821da63c33414a108ebf660614e780fcba74c4a6c78d7bad7a889205821cf19a97ed642cd82badf46e47210d59f4326ef2546fd85282e5423bb4788d13cb311cd600b70b80e05a63377b35ae0f32907a2a65257132c87b6f59bda7b788b731ab56a445b87e3f038d010001	\\xc8a4384720aecd25b4a8858c7748df6dc88ef979e557368ad4cd4708d0246a389bf7490df3294a6b610f445c1581fa109b3b0b70ce755b0a3e159eadc46f8006	1684067183000000	1684671983000000	1747743983000000	1842351983000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
212	\\xfcc18f2755da1d8f7cf18003aa14dec381d8e09761d0ab5c1da44bc8d584d4d92c7a28db302e4681bb50d177a4be9b554f00141caecac8a9a86db033c05c8a73	1	0	\\x000000010000000000800003e8fdb3917e46d2894e7fd1da33d3e9e8111bc2d37ca0b80fe64e2c523efd4ed30035ed5bd52fc0693ae28d90fd213dcb7f8be66446901f134dc6d6712311cd34729a4847114a20b702a00f9be687fc39fc01a9a92b9718ea6865456273fb86219dd8563742fa30ff85e5b9246108b65ab139593eba49d92556769c06edecd407010001	\\xa059e7d51b8c8d5a73d11d4639ed9327f5655833aad755558ea3aa35917798b8f69e31f2566e26de30829cb8bae97580edaaad974341cea4b4201fe61794b108	1667745683000000	1668350483000000	1731422483000000	1826030483000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
213	\\x030235c8680377db8bc23f385379df40ea8097e78aedeacfd9211a3bba327f139f9ad25652e0e82b692eee621d43f02bcdd7b8950100ab1f1f42dcd41040b92b	1	0	\\x000000010000000000800003d63f7df1cbccccb861e19fd7ea44b9ac8df2f3f79cf2f1e7fabbfcd36700d0c1c7e3ff190c77a32436353951174e0bd740cafe9004e928ad4f3e795076710b95f9ee128831177a8867f42e27a49260530b504a124aff2e7222b8ebf03ee62af4ac70b2ed8ff9c573f423a44be4364d93ed84f989a1e2a55be7fce0a2d57d116d010001	\\x9dc7e115a11c59daf7b4721bf15b18627774d5937beb2d536768dbf19d5463cb99fd4740dc61139503a25a01b24898e8e34f9468e74f0dc92325ac898639cd05	1672581683000000	1673186483000000	1736258483000000	1830866483000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
214	\\x099ed5cc9dd3782c515f3b47daa2f9cadaac439de853d4ccc05072c6163f4d76332fa7ddfbc16d937ede534f16d9c73df009abcad6eccc24e03a126eab9da4eb	1	0	\\x000000010000000000800003b9e257f7b4d7c513c0d6efe5817bd38e51f03db6923eb0a1ba23911a90ab36b06158c3c100cf1b04741302122b9baf237acdf38b5894885446977a0709d10ed6ff42055b2661dc39a7c613c0366ac93aeae3a1c024e23e224508a15bdfcaf4d0197e5f90d0bcd36380fa3fb59020e49271efa47f1d6d0c6d6cd047255a02b2d3010001	\\x2c6803353aef10ad67b7c7db7f3e716bf3079613e905415697c7208951fde564cee8956934ec8a0c20159be4481c66c089f824bdfb8bfd41f693050a52749005	1682253683000000	1682858483000000	1745930483000000	1840538483000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
215	\\x0c7efb9a14097922758f940f164f9d1a3deea7783f60e82a2e2e895f496aa5177507c539a45caf949bf94f00d52874416856189c623b1a113b2beda6df51ba0d	1	0	\\x000000010000000000800003f4a4e2b6dddd335c681ed9e3e38792502a201f28ec45e32b6f493d224511009b3b140188b52d875aab18bf0f7da43c8e0c6dacdf07d3cae84877be451cb072208c1d33d97678ba33d4b22b57275c44a723bbfad1f6d5ff62ac5bcdaeac3e060f204c2ffcfc8c71fd2255ede288b121570c8659d51d88a760242f2eab3b2f794f010001	\\x70127376003c53f2db4c53ad324b9de04078c277e8ffe420a290cb101f06a3d2811e059a012b11de1bb4bb8e03643185804ad64df5a877e3b9183630c825dd0c	1691321183000000	1691925983000000	1754997983000000	1849605983000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
216	\\x0faed015bb876fe72e13a4eb7e0df02aa1b2c2c435d7557c13b72e1747095dd0be5e65c33e1b67b5fac02e193267c5f515837e180ae3ed2f356186990fc9b7d1	1	0	\\x000000010000000000800003ce9df67c941311b58aa79b28fcc832e656963981979ef961f845b09c9fa6afce02d7a56b7c02be35cfa5fcc6d21d1ad31d9382d9f1062a20b56c89f71134b1de1d464410dd88111d397f01021e0206caeff44e11f749cb496b342ca31083bc54f2de2cf24057dd538fc4caf6c58331759e5fcf1057620a888c6c56a87418e615010001	\\x73a2e0e1a024d18919695c6b03c040d0df3caaa5beb4a48beccb53e7b4323edf27b557e5e7a74e7fae25f0046d19a3c78ec0ae89618115469461bd76cfbf5107	1689507683000000	1690112483000000	1753184483000000	1847792483000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
217	\\x0f86e4aee785aa2ec9d5760a64d7c4f315ca2087fed47a9d5da22bcb48fc7116c5f16834f643c90fd191ac98c54ae2cdb309e7b5c23c068d082f258f3caa1b6f	1	0	\\x000000010000000000800003e87ba6ddcf8d12ae52b8f20a6d855e3fd8cb75eb81407edbbedb4ba8c5859d9a91821766b66da7cc62d45d8953648d06c214b4e92004969090da251ad79bb180bd6825ed738aa8e81a9abb507e9d7de7327cf2f867d23c42e1cba336cadfb6ee919c011a4a1b04a1e91a6c385b2a0b006cc1b240fbf9ad63cf4f127c9682b1b5010001	\\xae70ebc5988b82e64e214e5fd73ff058970b716ebdffdd2d723ca14bf140bdf262af69fea9852eec54270d63f9159c3b12243d835dfc2bfa32283cf70ababd0f	1691321183000000	1691925983000000	1754997983000000	1849605983000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
218	\\x0fa284695cb7856bfa614ab0a1cf786134733665beb332339552a5b5e8cd7eaa000371a2c65cdd4b4b57b51749203f86eb57da8b841acc82f435cfcaed2579ae	1	0	\\x000000010000000000800003c2c3c2391fefd8fa325439a727da59fbe7c2046843b49555c807326f7f902008e3836145dec46d5c3a5e4c3b771743dc95fd211f2c4e9d300bfd17004a0ea511580d93015fcfcb3c145e386af774c6b3f80e918e5e1cec468a04a0c42558e81c72613811c93931a72e5d19bc9060a98684c7010062d9683e741f92663886d829010001	\\xbffaf67706b5f2e485ca82f0175de15da52c64b09ba62306ee680d4f766760bc4a5a20c906f67f2d1870d7adfda1a8e043fbbc5fc60cd3196cddc082a090740b	1678022183000000	1678626983000000	1741698983000000	1836306983000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
219	\\x136ee8b3a2899bd086b51d77c976f8dc464a4a99ddd90450ddf5b247099644d292df90eb73a17c185ab6668b6c88fddce5a2e7a3890d3d736eddf6ea0a3a13a7	1	0	\\x000000010000000000800003c25a9619148a034e269ca449e0f7d42237d118e6ed248455e5103b7393bc05175f0dfb98b971fc26261a26a5ec4f33dad2938e6c47cf7193d0c2b715a522efbb6b9ba3c991b1ae0361b1c80b45f222a70550c5cf40843f75a33e9ca68bde887ed479c27e67c9bbdc0f1df8d6b8bc9ddf2901c5849dbc3502b7be476a84eca9cb010001	\\x5ae39feb71fc46c4569e29ea5a25a8849345493eb9d83cf5b17dc06d90d868c11fa13fb007b6726f8fcafa50921f7fed4dfe9f95fec5418e296503bae1d00008	1665327683000000	1665932483000000	1729004483000000	1823612483000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
220	\\x133af8094038eae05dfa39a3b94b889b45ff4602ef4cbcf662c76dc0f4a3884365f2f317a2b6a0d0fda96e87ad707272b1c1a61ca3552ac54900ae74c58607b4	1	0	\\x000000010000000000800003e3788efb1617bfd399266200a7ca1cee2932296a36185ce62e43680d0a3642060243dbc20ec527ce1a9cb48517e03d56db20fcb8b259a441fd4542fe6e3e2ae7c00f7908f997cc0f58630f1f847140e744c4a87eddc8a9da4fef4c9feb16eadc9e1eafaaa7f0aba3515ecac74eaf81cb46c56f772f370ba98f9613a481744c69010001	\\xd84b4bb6eb2224210c9c083c89892e8679ba4e7c5d112dd2d0fcdec02ef10b0acadce6af1ca641aab49b67a70b3ac966b538b7cdab18ac2c8fc01e1c514d0502	1665932183000000	1666536983000000	1729608983000000	1824216983000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
221	\\x17762637e3301f7fa5a939e6973b5323a643b7dae4d442153c6f52a7826b1ed7a0b9de15d40fe38dec1060b420a7b706b7e71e87d557023e7d75f766f5c6d92b	1	0	\\x000000010000000000800003c897ca29ae6c47a185bde912de337be9b6366fbfb7cefa90e2bfb338661fbbe3c7f963b4dcb0c50115f4d9e36fac0e40f9e00f38969834068ae5f5f8365fd8ecbfd75940ff88f28e770498572a4c14b671da1d60c2dce6e1442ab00f63d928ba60b0f4aa403b3097ab5789996f6489bf7e842bb690316e791f7710416ffecec7010001	\\x5919653c52548c4cda59f5e16df01c5ab835a830d60a5b921b66c4196e0719847a030fa2622c7963bcf0394ac15c98c4b138db34585719cc3e869c3cd9486103	1665327683000000	1665932483000000	1729004483000000	1823612483000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
222	\\x1fdab4dfe74c10b0c7fe29dae228731753e663d9668b697840748afd7e440a235efbbf99b63fcec8da6311a2282181d3afea83eb04f1a34068b02a85be36bf4c	1	0	\\x000000010000000000800003a003970b72595c68e71679dbcc9fc3dba0629ecbf33f4e12043afea5ece9fee7ecfb7a98ee3867822dd1fe8bc6791b04c94bbf68df7aceec2dd6b89e45d3944f55c3109b4c6ea9d3d2b97fd9c13d5ab6a27e8b3944bafa8e76abcdea34764b71f6c4881a611a4fa37f42552fed0f1cef60c5dc122a76f0261cb478de3344fa33010001	\\x78ebc88d851f08ea7cf1ec50f4b187dc5b13456f38ba55712f557c8166a46b91a770cd270fafea712fa6eba12793e15085f2fe16da903dd43a1f6a350687110e	1664723183000000	1665327983000000	1728399983000000	1823007983000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
223	\\x251e88e5eea33b4393fa832ce5e6bf4859120eb77285ce2a514ad16af151833ed7d67506108c0a80a3f98584a5abf79803b770597719766e9b3b869bd690589b	1	0	\\x000000010000000000800003e0bd38737f85b4e5b35bb58f28adf06b997c2bc08c0170176dcce377180f0dc604b3b4d80370ce0602758e8dc478b4d25d813b8a4eb23fd0ba3eb8e4082e884446701a2bb096a625f64b20da4f5e5415373ca1b365cc9342ff2abc3fceff1f6250c0296493d21d9c0c0bb6491ab789bf37d1f0b6174283723adf464bf7fd7e2b010001	\\x44a0096661a89ece0ff7ba92797092541f7cf5e697e4ffa77dbb434e435326e81757ad5e5c3db0db3f96be3a5478228ecd926ef57757f6b3f39015279d7fa509	1676813183000000	1677417983000000	1740489983000000	1835097983000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
224	\\x2556cbec6063e835e787ab78f794a506a664e3a87569a6a7fb015ad8a5354df65b6608bbb36a9fb5746cae0c637d08f6f51f7fda5504b94d98e90a7b09eabcf1	1	0	\\x000000010000000000800003b530b982867ba895d311012fae7b5f27f71d82061f1a5a604b03a1f10500f93c2f213ccf434be579c1994696a78d8055f49c25afc9d73ba7aba43391bb642d320850d9c0296f80e75e09104b7817d3df8d9700c79ce82244a1be11847b698bb90900ee48fde8666b9d7f445e0c7dafb446ca97df62d2a5ae210b19f0ac8b30c1010001	\\x78cfb444e363654d380401e6535e3c661ac473b65efd85ef61587b3d3f0b19352aa9275d9a15c2d04dad8e7410e60f61aeedb8c4b2f42c63b8a7a95690b54d0d	1679835683000000	1680440483000000	1743512483000000	1838120483000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
225	\\x2866b489e08571e6ea48df84a4ce35420a76c5ad861883bef5f51c70a8e188e557a4082121c9a2e75614af91612de0ed8c0bc0d9aea41216354f2a23917c4f6a	1	0	\\x000000010000000000800003b5c7ef17b782429a217e6bcdc0142e9f6e7df10a6b56715fb42c213f836e7197a708c4a1f0df7aa4db8e5833fe28e143c20e592d1f3110304b0ad68eb41c9cbcb6357cb910b978342266714a4f3bc57a28b5ecf05b0e4d94fa099db2ccf9ef4a4ff77a82d81301b1ddee293c3a12287b55afc58bf0fecba180651d1273f5a697010001	\\x8f699c5602970d8d32a794bb75e04204cb2a3fd0ce683af1cd04064e8ced95b5a6795f14308773f7ce6b5f5507f95ec340b718368ac5a0cc3a65f5f1fbcd3705	1670768183000000	1671372983000000	1734444983000000	1829052983000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
226	\\x29925cb8e7382602b1594e99ce0dd2d36d1313bf7e28a3788b505624ac0a836c73f31ba37ea53ab699455295cf8edc4bcd10c680c8f39878dee9f062c6b8fefc	1	0	\\x0000000100000000008000039cf341120a70c5e87bd8ff689219c9df3da89990ac0e147bb5dea0228bdca6441a4ed86ac2f304119f867be96558913eab5e5490d80cd4ccc192dbd468cc80cb8d994c423d05a705b353557a62a7d84301921080e1276a03f8166b7b59b10905de8cbe3d5a09c641a3c751b74b5a85e65338e187f55af9e612b0be2a2eb0b6e9010001	\\x3f94ee009e36c6f26a96e2c783074f96b10f65c20348a6510605752fccdc57459a084d4206b9679ff92c0b7075c29f75dc8f7d4bc62e2b14971aef16986d0904	1691925683000000	1692530483000000	1755602483000000	1850210483000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
227	\\x2bcac45a357343981b156e7bb84813f4d78071886af046e2a1894d20cf873112a8e977a6b50c684cab54456039524ef79df35421706412f9aa41062db8527f49	1	0	\\x000000010000000000800003c28fb40381148d57a07062813a0877ef2936140d6a9dd116dfdde6eaf764dc300ab49c46c3bb6b7f6afd7638e2fb1882eaa6df3d1f0eae1cc3d0deb5203f3f5c1da3d06f42914922eb3cf72b268597cc43d5d6edc725f2a78293178e419491dad0b6e9cfdfa0c6825835eb3a2180d234e0ecc9bfdebfb0db9d31da333223713f010001	\\x9804656f03b242bd9757881576665fa484e4fb449f8443092a1a1dfb39f51b20caf0202b376fb4bdff19063b70395d168cefc0fb3359ce41c7a59fb1c68eaf06	1672581683000000	1673186483000000	1736258483000000	1830866483000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
228	\\x2b12717e3ccb041013becf983c1bf4cfeac66b60966d3d092158184d73660f396fbfcc06b0f7a9b704ab54dab47004e05191771d361a2706286f067992663c9d	1	0	\\x000000010000000000800003c18b581c74813edc7d12ec180b0035239b68b30d81eb84dcd8c76d39ed492d46c73596e54833f5635c758596a45c59ebb49b7d44dfa3996fcb68324438a896b308ba85e0eee62d77066994b0a043b364d655d3dc13b00daca21b28893f5b6ee8a9f0006d23cac4a04398e44b874fb94c5ee94817bc7bb3de6e4d33bfd52cf5dd010001	\\xa511c266a15e93d57aa39291621ca2b2a626b88ebfbc324fb6433c2e4d122b903c5d44ac44477dde58ef9e4e6eb6d67c561bb054d0cca67a73d74d0121b41702	1687694183000000	1688298983000000	1751370983000000	1845978983000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
229	\\x2dcedb7a3268cffd8e8895519af865fdef8df5f0984f0cd8d0b0187e01107d92c1cd0f94b9562778abb19fe92ec861562daa06e9d18b38a293f80ccbfc0f5722	1	0	\\x000000010000000000800003b878f68ac96da52e45dc13ab7de4a379bb4220fe64bde2b841b1d6fcfdf83432d25252eb48cfbb6d12255305fb1e482c82ee83ccb0d55636358684cfac580e55597bf7172d590c9c6cf0e76b075adebb81428ac1803b8e4e5a20c26a477785c788f9cdf9a3afc790a394091af3ed7409d3eacc36a68cf1ac5db2b97913a1287b010001	\\xad525a375988bba380e956dfbbad981fb47ee0279051051f4a612158a842a836c83091a40ff82175a069f3e446859d3ca9d459d91cf474d55302acf5086e5301	1666536683000000	1667141483000000	1730213483000000	1824821483000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
230	\\x31ae5c12dde9a6c36a48a3f58779d64d0857ab699bebac84ea2b622084aa49fe6e1037edd98e384c53900c2e01a6baf7825c6171f4d6d095ceae1e0adea10a40	1	0	\\x000000010000000000800003c661a606af4bd65f2519607df10ba873c41f11d2f17aafd3640b3ce8d686198469d36c6144c6b55c7464f4121d19e6f6c40c20c3d0c5682b7146d68615e23b9cbfd66025ddde579edc18e0a8bf39a8e03516c1cc672640e06866889ed37c16b4eb1ee934a7bfd98a7c0fd2d835fb6d214b2229aa0645547a075352c6fbc02239010001	\\x1d4f38f820d32e13cfec9639bc77066f82049e994ba16f551fc070bf4ef9bcd389fd79e02ccb1437c65f9d641c043605e7f3fb3689cdbce3ace75624948c4500	1669559183000000	1670163983000000	1733235983000000	1827843983000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
231	\\x35befa01ed7c07e868e369b7422e244914e8ad6c3b3cb797491a32bda25368323acc7248740f7363e3d7b58edb8f0d593cc833200b6e82951e21d95c727fb302	1	0	\\x000000010000000000800003f5f528f99c0de8ee162814187168286f1434953d10cad7f20b8437edf7ab28c8a5e70ee5097aefdaf36a32a0f3299783ffce910c159b4358bdbe9ea44a706f09e120ea81e5f8316ae2ee20207121599d5c849a154de44dd6fef6e69084cc2343bb36757f3ddd041267da03612f43385a77daf77401028dbbddbc517e375453ad010001	\\x5d84ba6f15b75ef05d5510db6f786187d8729065efcfae8f7f10f5f2789f8c31dbea9487797be95c33ab70c680e8c1b152467ab9cfdd70c739696159e7f17f04	1681649183000000	1682253983000000	1745325983000000	1839933983000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
232	\\x3baea58e5c9aff72d660483b864164bd617d1c1e1da3bba0aa19d7ffc6b83cb87865c50ec305c5c6aa9cd5d0d3432dba78a9156ef77e18ae7a7f5f50ec8b9d3a	1	0	\\x000000010000000000800003cce098d452ffa0a8ad5e0901cae36fe18ba6f386d3b13a55c0a5964fedcffc5bf69d6d2354a74d5620f38287382e83262deab5b23fc03cc84e71d925685ba64fca78f7b5746862c12d2087c76151795672bdcde09494ae44f1ae40fb741e46145ccfad2d7955218a2cc3b7cec4233635a827b34a901a51644e61cccf9a328451010001	\\xd835dddd4b1e2bde29a4188a81f159e69d4c0babd4ce4bb91a2d126b59e544c3e229578f2196b595a367bf1d450780277c7de3def8596a5460fe88e6207c1b0c	1673790683000000	1674395483000000	1737467483000000	1832075483000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
233	\\x3ca68a40f4cf0742b15f3cd6609a0d33c0985e6067b08db7c5f9082a87df7e77cdc8bc24bea3d1a515f8befc41097be22be12b4fb526f769582b689aa62c5841	1	0	\\x000000010000000000800003b1fd50a23d0b84aced939fd5c77687f27399ae32abfe9384b1719143d62d13dc059319a6118f9504aa777b055ad65959cd12d78b8a364e4325f913c75f564f48d3a74b219be7358c6e09d4ccf9791255775f898e0bac75df587524799a2d17d613b4e2d1903af2d10ce0fc7ce18bde6a8b822cbf341d67029d1f8255eb860ee9010001	\\x196a053f6fee2c9938551bcc4cdba67becc08ebe3e381bdbeb63c51581d3ac07e8a7416b82b8dca942c900eca9c623b69f679180d90796776b7ed4e4babcad04	1691321183000000	1691925983000000	1754997983000000	1849605983000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
234	\\x3dfebd5e893b0769c43043b9254f5f3e87da3cf9dda6b49f323c59e31c71299157afb942b9df0990f81d69d6a9e9c561aaff54618d7ec2814c0c219392b95872	1	0	\\x000000010000000000800003d1a80511facdf3cb07773a59aa47db961e19eac7f15f01606e0b44a3eef03fe9827d27ed5284cf9cfcde46988b0d8d87984e3779bfaf6c748027e5517dfb05cfee68c92a569513aee3a1336456fa7b063e4e01d429879e03304202399557c3acb84ceb5e86c0451a72f277d8f83b25c6b2fe548e2a74f1e28075835414cf598f010001	\\xfd68a6b10b12eb6277ec64ebd3ad71a39399d828d43d082b2f1f6dd52a2d578ee1de55af5b87f80f0b8a3f1605590e87a24be2454bcf5d3bed9bbe3ae92afe06	1665932183000000	1666536983000000	1729608983000000	1824216983000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
235	\\x3d5229ec073ba0dc09d3efebd01960f8d6cc4573be4285036bd0920f3df4182783a88305c06957649ed0de3c143551ba1f17f2704fb94e056f99a46692b240bf	1	0	\\x000000010000000000800003ed36f241677d6ad49cd5eab28e58391a788564cbd1196cf3647d201c54f1fbf6d7478b75966c1729eba61be931dd4bd9933ec1655982a1ed4f27ddd9ee5ed882f0472a7e23e35e23b237ad5a2150e509528e9860e8afbfe076627230e27a3289b23dd9c4b953f89659a85f940ba41f5fc6fcc6357a4abbe5da37b661aa8577c9010001	\\x9fe849d3cdc0f170324f9cd633dbdf0c4f215720222769e1606458e415af24920bbe3cbc191f7e1d0d651007f11e0ed30f42e69f3b45212bac7d61ccf041b60f	1669559183000000	1670163983000000	1733235983000000	1827843983000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
236	\\x3fc655577562298d9cb694c0d862fdb4eda0b9e0f9eb9cd72efc8e3f945a1b5534972023a5c66616b356c291218487bd4a6541d3d6499842aa03b9db653059dc	1	0	\\x000000010000000000800003ac5b17f5c7410f66bd0e512fab418b8b74df02c1ee94424d035afc9b47c1c153120ec311de92e3bd60d68d0c84d962e918989d43983f6199e712fdc75061638b564fe913ea3e7da576b95778608dedd8847ef981ec93becdccf1e9b252fdb3208e57cdabc8afdd9760add3a7985b97ea9cc82896b4fa07ecb08e17a009446a4d010001	\\xcbd5e176ebde575890b865616d1841e8a44417e8c7547eef98561445d9e508974048348feb048317fb32a3db8f19d091c6395d2b118a226bcdd414d825002803	1668954683000000	1669559483000000	1732631483000000	1827239483000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
237	\\x424e392e6481d59a4a8e68623b884a6afb3bbcdb7ef356505a77415ccb4e454f4957ef0d34012086fd63d4a200cdc0566a79af2d5282b9698196a07b2e5b3597	1	0	\\x0000000100000000008000039f621b00d745ae328b3eb1e60780e718af28d3c7d5f35dcd5f91b49d7491ad9bec59db64218c61b2b3a22e0d8f6389917c8631271598953b3e4db841a13a56edbd07ccaf17187a2980ecfeacaf62266c713a3323e9fb76c5cd20b7f023fb803a50811f1fddb4a3667177618615d7144d5798287467dcc97d93fb168bf0a5e731010001	\\xc813ea62685daedc80792e9c05480779bcefedff1a8ecffc38e2cb35342137b853f3eafa5868563b737fdcf6e277af8c467571cf54043720c4b8cb8bca94130f	1671977183000000	1672581983000000	1735653983000000	1830261983000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
238	\\x4a22eb62f9cc6a377629502ca64a1d6f1d6e518b49a5a99ab22f3ea62d3c879438fc59dda88277090a0e5b363763cba089c97c077a25e6278f7e3b95fcbe1287	1	0	\\x000000010000000000800003c7203c48a5fd0ad4a893d869056420a3965847b3d00efe6a094c94738e259d5c06dd03f78475c49f67d680016f5a5d5bf3bca18b33209daa38f77944c4215c1690c9e7a53eac6392b0909251733bd8148ae6d624b648d0a5080e613b8902462d0b3e4fdf9c84b5abeba1ae0f0a43db6f366348c39731dc9e016c384062635591010001	\\xb25f6c04ffd5954a48a4324f79b14ede6c8d5055a05f59e2d07c9a03aedad5afd1d9bed0fcc79953e77c0877a279e94d1b49d7c9d5be8cf43264193037db8309	1664118683000000	1664723483000000	1727795483000000	1822403483000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
239	\\x4f5e930c2290d3e734b8b7b18a434c990d97cd9443b26c28efaf0a8f717a32ee869cebeeb479913ac03064088e7ba9eff1fb8233f10f34cdfbaff5cec8b7aea9	1	0	\\x000000010000000000800003ca38a99d5b375be6c0749b9092a2bd289506a99e15194c3f46161795716d4f6ff6524ae5978658ed9acc714de831108d6c552cdeeb33265f1d4e7abd1106f602e6944f434f538b183d236313455eb8adb9e9f94147d54f3ac5e052f7444936ed636a566684460898a420483b5bc894481d4065bb5855d929c06627b353bbba19010001	\\x4dfe23baacb607d1e8df3f4be36ebdf4193d28b7fb838425434adadf9615a3de0a4762493f3df979e9ce57a792df84eb5d84f752246a1c75e17251abcbc7d606	1665932183000000	1666536983000000	1729608983000000	1824216983000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
240	\\x505afb2d422c3170604c48e1de628936cbbaa5f7eb2bdd54024edd5b6e3687887981c3b84212ee9954e6a75dddeac62bf41a3ec2c336e17023183be7683319bf	1	0	\\x000000010000000000800003aee6d3d828740097e3cc09d47877569c9d671e89974da48e83d348e8fb688ac20ed483e344ddd9cf3a75c3682b620f05beca3c6e08edb0b1e57f2b4026adfee61f2d7fdde46a8970d5a21a1a303e0959a8c967192126e0ce28587b44f5c3b1d4a0246d2e0e826876fbee934e6dcf9b5d99359f2dcf1267b18c3ac2870261437d010001	\\x6bcb43f2607367f0d6de23ed67baf14e5bf7a20669a54822a3cf5ac8dd4c52755dce6143d0da1e2b2a242f39634f49c7fd072e95d682d24926e006a3b706460d	1684671683000000	1685276483000000	1748348483000000	1842956483000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
241	\\x5102c71b7a54f5667b20961c041ef10bc3b5383da7bc9c1e70e631c4170ae2c4d1f47e1a8c6342300c09e9f68c8ed1dba1625f9b8ef63f6a3bfdd8eb2a0e9503	1	0	\\x000000010000000000800003ac3f3b9031febdd6498c5b435c4364c00adb2e6c31e2c59ab60dc34600e6d0febee2bb2eb0bef45811a3942eeccf019a94122b7ff68fc23af6b0ec343c363f3f1b6452fefa2bd5462cc285cfd8c938dd540def79dd63bf03605a527649fe96bdfdb110554cdfff08a019c9c1bb4b1a21a232a8575eec2c6a790b561b43b049e9010001	\\x723b5adf1237e5c1260e2630b05af9da09dd55a979fa78319c41b0c29f013530cffe1f9680297205c71e9a269d0ba3d4749e6af28fcc98eb8194a72f2d88180a	1661700683000000	1662305483000000	1725377483000000	1819985483000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
242	\\x52e6dd52a87c9c005e37fa7ea786b3e57820a089e5c39805e83f4f831234c7a9cba7ad74893e1c511fa6a3df6f61bc8dec7d0c65e428cd009f3e261b773540bb	1	0	\\x000000010000000000800003a9c1f5d3a786027d2e306bf975cedaecfb91619216967f0f985e20bff40162c031658af225a8842e7fe1681ff47b9926dd72864bb8c886402cf12d40a40c52211e780eed7fd8524015207d3951c9a9cab871b8d3ac3d17fbcaa20750845330552166dfc94e8d7651f775e978536040248770c56ce21215cd96431782bc5dabf7010001	\\x346f65e83451e1b271451b7927a4cf94569c251bae3661268de95f57abf8cf5598e62ff44de85491ade9d7abed8e596a08d0f0e42f65ba6f4a9f3a487b47f302	1674395183000000	1674999983000000	1738071983000000	1832679983000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
243	\\x55e6ba763d6503aebc02afa701aeb0222b913c5ecfc220fc76d36ba2af7ceafabfaca5d805a92a75048c050d17360678f72db71107eb1245820107ed5c38bdc1	1	0	\\x000000010000000000800003cc8b25dbf67fc42e1a33ccb6b7ad9e7555fa0b3d372c67137a83178df3e1dfe0908da6bd2eeceebec2289ecd0cc1d16111a294c904548531fcab9ec859c1d4428c8f0e3e9ccd5fb0b7a0b23101b311064d1976dcde5a3a65be86c17740df38bc99153c99e4cfb10327deaf50765a20e3ef780a917ba3e768c0e87c8f99eb5403010001	\\x5f0b65c37797c154feb75c1d5ba4e73fc3ab68ddcc3cfcb51636fb091a473957c7a887f79c0317b8e4ebc08cfdbcb98dd102dd590b5c6bee0533737ae4bccf01	1681044683000000	1681649483000000	1744721483000000	1839329483000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
244	\\x5d82bbaa349a29e2238d16b6b1271f568e4dacd7dd11415167838de079c226c9babbcf1bfe861d5897e47d07b1bf1fee062b8825146cda69ab2c54662c99db9d	1	0	\\x000000010000000000800003b58aa6e9e7461fc7a1fa710be473706b904aee1cf19e814254a682821f25eeffe1797b98f61a406851c98f8d1cd4c2092bdcb9ed163ef9f22d4f186c77e5e2524a2156246306c51d2903f1fee2a8c064bbee5051645864efa8815af03c0b26cd379d4e868431a3038a1bbc232acccfb64d9af08836a9dc5e83decd1ebc9eb675010001	\\x65e880714bc2700e13f54fec9105306dc5460aa4509ce2f0d9804458636b8f53585dc8a0637be0757d96e1ac81edcf181b33ddbf188bb9a183ff3fddac5f4d09	1668350183000000	1668954983000000	1732026983000000	1826634983000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
245	\\x5f8ac31d4174d2c5edebd05910ca46db916e6645392df72fa284cda8bee223175039b7384df07fbf2c267ab1b50b146052b7ae2de11a73de4e0af00d77e26fbb	1	0	\\x000000010000000000800003b73f47da1435e3f47df5a70ade53e543fd48b578fd67f3fc9b2aaa4e20e8d90f993cf11fff317b2ebbdcc715bbef3896f765596931c42068d97aae788a19f166ac9e080bb9675782124803ebbc95e5f4e5acbec0cd0aadae1b6e8d20222d7817f07c34ff60a65192548d230a37b0fd3449f587ea97f95561d884ca4362feea2f010001	\\xfa73603d2bd342e9fdfcdb8e2be28473fafe9157d1de72a9fdd8354faf36541ea8fc95be19121bb73505772a20bd91f06a48572d4d31477580a6347e280ae609	1677417683000000	1678022483000000	1741094483000000	1835702483000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
246	\\x5f9e409ffde38945b3d6982355a9bfb4e7e3c80bb156068858f1566b7e86b53be62e81aba4d611328a176c3219300caadbc7a4f5d779c3a180f20b7b12044ab6	1	0	\\x000000010000000000800003af982939db0e09e0d9a358bd3e80576602600eb7092b8afd27756e3e1a9c852e599e3f628ac64225712546a641bfe2c1872479763a1ffaa48c82de0a4c0ee46ecea9c7a76038d196b62c80ff425f60c5c3c31807ee940a8dfbc28810e839231cabab540ecffa9434a13fc0ed1f53cb8c8e603da2cb9d332a1e55a6cd4082072f010001	\\x3f5d4a4a611f4d2167d329e8b3fb1e2a697c70181eac0ea6cbd19a9bdf0c6247bcdfc3d41e2da1277daa713f767d3c67d74310a070e161d8c2a2a34df357e903	1683462683000000	1684067483000000	1747139483000000	1841747483000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
247	\\x61d612e5ea3bbe6a5fcc6522f69c77c61c64fa0ee869042ce9fb521c4e539cb2d3f9992781efe8708233d0f4aece99dec8da881ba6c5c306ea74827b3454fce6	1	0	\\x000000010000000000800003ba108795d3809ccc27b6599c86a32db1fa0068f3f719c258674f4c0e6370cb68dc6a12ced568098de33a1582f8832a1e7ecd6a6bff3b4169360c1550e1639226d9ff80f7ac4eed1fc10c41803e1e9c697d4889e28f35fa7ab50d029d9bbb63324e3888772826484625a451d78e688cf7dde5d73b89472139c2a5409d5abb8ca7010001	\\xd2e5be4c08816bd12fb1ecf1e90def54f919d40d524879e42df651933b3ceb90a4c60748805bbb1244257ba6e7fc1b17e484784cf6ab3d3ca83580336ea8b105	1665327683000000	1665932483000000	1729004483000000	1823612483000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
248	\\x643ab451b59d2bda210d5dc5ef24c1d5f2cd668b5c100b5301217c8479a520986e32cc5c534c516d89a129c51eb8d274dd1611fad47c650c3a7a6fd81c7d5bee	1	0	\\x000000010000000000800003beef6139b7e26556dc924040a1b67899c53a1b6c7e940240351dbea39d9b0a2bab5b7690e1091b5369f68aaf60634cb73ba018aa0c8c289b3bbca3d097d96fac354c16fa922e5031ac95ecf61e49e8949f3342d2b8a8646f3c5c51ef29511a427e8acb0591e65e3f6c025b5e4f0ecc101ef54fe89f1657cd14e1d8f00694da7f010001	\\x1ac48b3677e1fbc18ed17ad4ea2199a11baab3cd40e2759f90d13761443e48a6535583d938b51c1c87e3c522d3ced2b2ecebaa4218d3a00f41d0a9896cb1ae02	1670768183000000	1671372983000000	1734444983000000	1829052983000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
249	\\x65b6b8f7a1b1e15f165e254adf787be2b2e9a0c2b4b6142568d178319f32dd953d0c34ef758c03822a458d865add67e2d6877e3f656573345d17be0e16ce537b	1	0	\\x000000010000000000800003bed24c9b65c0496982f1f76846634ce1bdd0d247e728f68222187ae72e07a301ae7d9eae8cb809b115aa8b791d90427a79abfa699c3f709c77e202534c5743aefe539989ad89386da32756f7265ae63cee9d579a9df4ec0537d492690d54a79d112df8536d17368201cd607e7f4339e0522bec6df2d58100478473f7690e4daf010001	\\x6134b3e669989b21452aaec8098641d3365dce395dbab8f2e61925ba232ea6dd33a85b053f0d54a329749f6b8447b223fca470da42b0f31c6f6150d214990b0c	1680440183000000	1681044983000000	1744116983000000	1838724983000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
250	\\x65c60ff5fac8316c79b541b833f72ca8c2a56c9e9efad256e68e22bfda982205102bd6d6f4c4828ec0bc718d9accd033ebfb364a55b076a670d5ddcc9463f3ba	1	0	\\x000000010000000000800003adda2d245a828747f449454b2506947c574408587db3c97530f13ff737d6170313474173f08cb2ea0e0b3ffa1e38a265013bd07b5a3698b1423c85bf617a764bfa78ca03725575ee025c4db0807db48488215fb9ff2f0e935b8b2cac89e811eb2d2341854d7876274308b153b9f79d32c527c0c19387afc30babab5a2d1e5199010001	\\x3a25f90b606b067dcaa40744125eabfe7f8c3dbb9e1d1074973b5cf142db39590aa397daa92a8344d2fad85169669d05e77d5348f5ef42253744053a0721a409	1662305183000000	1662909983000000	1725981983000000	1820589983000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
251	\\x66022710f0c0e0dea0d48823822f42572ecbd0a319f2997d51098f2ab168a7ca98ae37266949edc7e1629476f1c5865ee0bd81e6f8d21b776a63f14b83b3e6e8	1	0	\\x000000010000000000800003a773604eebc62318496648c73266fe761230e3d42691515ff428863bfa4e679488e2ab4e1b6502e3bd56177248b9a265907a52e24507da6bcd47aa8a4808b2fcb3bdca90cc2edf9a840643ed38636f913fd9fbdd1a81a5e8baf507d3b9ba390b0a4ef270c46e17272db791ea1e34033c1c32467d0302d0abe6935034be7896b1010001	\\xfdb4e68479eb2daa8dc2dc89f5d97cf3723b6fa1e8e9dc850988e970d9b2b34adba143250f32172f6cd2b7f6899af6dd5b3a6733598eb8d353313f6cd459b60c	1668350183000000	1668954983000000	1732026983000000	1826634983000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
252	\\x6ee6753fa43d53c001fc89e6a7b58aec24a837ec78df0a35e8c38516d00dc6efaade187edd332e25a7c4b55877d2cee557e1597f6a5a3c73d956a803aabada16	1	0	\\x000000010000000000800003e11e5d6f74efbc3158d3d95a9121f656bf64900c826902a62470fe6e77f1b5873032554588ce39065fa3c9eaba4b75543e926da2b09ef4368af968b52ac344b2ed372cf1d9d3e6b4ccb05bd420764bd1bd10d953188fb5b8208ac935d80f3f9c3fea5e8e7d612d45a507a9548123bfea660eb2f213bc4fdb88bac28c147fb1c1010001	\\xd0b04944ac15b4228c4d0fe3c14616fd2397487cd4aaf66858a72b67f003a3a2ff3e6e4be0e2d71ac7e5645a7845720946a75ea82fc9a0ae94a705eb616f730b	1666536683000000	1667141483000000	1730213483000000	1824821483000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
253	\\x74a2bbda8959ff6251e1b74ac0284e0d52059fbf66e8dd06baef377724986f1fbea0f184f05345905fe5176035987f5a3408e837358e39968946fbb9e6fcfec8	1	0	\\x000000010000000000800003c31209a227382c73347ed54745de8c79c0c6152ce4dc1f99c2573fdf03c97af446d17c780a64f902e5bec04a5198a6190153a4922488fa84a66290582d2958a6e926926c55c3e00ed1b7e45cfbfd67ff4fcc2fa8bcded33dc51a0d6c5d88e1fda977273a7c6057905004d7d54c5d01f7af97b75038f37ea9c938d0eb9d3ea4ff010001	\\x0f5c807e4fe5cbe79eac52dbb9c038a025bffd61d58c2b418912ef7914cbe6e4093e362260cec7c8fb667caf8f07682f71d261239c2221f128846eadeb48e10b	1673790683000000	1674395483000000	1737467483000000	1832075483000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
254	\\x78962a8005fdffda182cc9a27f2a4dbc02fe5faf02765b6b7dcf88948c5b52e9d4487b4697e546d1cf6f928f51b45af0ca6708465d0184df7802539666e0a64b	1	0	\\x000000010000000000800003a85196e8dda84518d54fd9602fc970a7f32a7def1a69b4ecc5aa18bf0c028803d0e4ddf14d9cd89609b9c5daca5ad8335f0bba4d422ebeec9df41c1c29374198263d16424e438676a0819b9f381b76ee62b8da64a103476e2783d7c9490dce88e88e17092744c7c3b89a7a23f9d7d119bcbfec08333a3299a375f0d2ef74a05b010001	\\x536be99dd80ee0c0f30d88dc6f3ca7dd09fbe68fd746a841990221589c1d6a2483cd94b6ea59f3f0b91ce4f5de387d1bfad76e16e3d3544813680c3220e9a004	1675604183000000	1676208983000000	1739280983000000	1833888983000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
255	\\x7ac2852f758d27a48cd39ea28ac1e963345f09c9dea0380d2a805a8477ac617759f6105599f81e1acb33aefaa3a42ec79779b00b744be8b5d991602ebc43d4e7	1	0	\\x000000010000000000800003b8fe16c82ee71385c3ba292fbed4ee57db665953a753f59ce00285236d90164b4b2ec8663e661752a76075e67fecd10e3e91684393e07b2caa394851f1476b273e1668022d2adef723a82b93c1480bbf83ab33a278b9fb631e300e9ccce4cfe415ab90f106efa1ac14ef12f0d1455a2424a0c57551fb9e804174c65da226978d010001	\\x06e290c086cfe51ae42d81c82011d04035ae2187f0a0142ebc28c3d23a9f2c16aaeaef7c468af3a393327a1520b4d356fd0fe754bd28876b651ddf040cd6ec0b	1673790683000000	1674395483000000	1737467483000000	1832075483000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
256	\\x7c3224847b585883841a35eef1dfa3e6aa742bfac114bf698dde815bf2f670a76da5e3d10f2930bc9cda5fa6ed32814b3cbb522b7edf5a8b31fe56ff2726aae1	1	0	\\x000000010000000000800003bfabf5190ccfbad6461bc0cfa2600578213654464a0ed3116203161c7dbaa762af31d9c69e0bd6b5921b9354d3540ff5a7406a6fac399a0132d4a4207985e863004df1b8d8b3f2c3bf1cdc93bfa1d4ce4085979e10f5b66c8e49eb52e3ad0dce53c831a331c3b9072c8a9ed05b38f94efe8842790a2f5dbacccb7fc92e29984f010001	\\x11392b0265d074d839653b7982326eadf3eb7ea9d4ec4bf8d5024250dbf1aa07f8a257f4bd3aed016bf15ee439fec385df66b01c7b43b4691bc24c7abd10d401	1678626683000000	1679231483000000	1742303483000000	1836911483000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
257	\\x7da62a0d2327ec46035d2777cb45a0ee7c51c2e4d808e54510aca27092dfa8c18bb78e0c1b0a9f5351d1fb108d57ec14d04303c1842682ad390875351bfe9d43	1	0	\\x000000010000000000800003e0140add46fb27992bef4421177e6718a4b82c4f9faf8fcec3de169d87be262577cf6415fa9a96c612a14d6ffe306e335921de60ee6c1b9155d56f2f1b4b3f9cb1f94138265548a30835a232a50d3a1a953197e6822ff83fa51a087fec8746fa64da34e5db5140d736af3ad25fa9bff7beb3981ae28810af3e9c1443adb6c239010001	\\x2a66baf0e7a08a0f8066ce7a111136f10505306d63c33c4070c03cfa2d846720f74069b8b16254ca45dda88ea91b4635a8aa19948406e1870d99f3a560b8c70c	1662909683000000	1663514483000000	1726586483000000	1821194483000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
258	\\x7eaae64b31a2e465786ea06a90029367d26ea7cb497ba732fdc808b2f729059ae03a0d07acf9a9112c8116cfd2b0f235c72a6b4343c7371a3b05a7cf87863d5a	1	0	\\x000000010000000000800003de5168a3c67230031a1e535c4f22bba2762f366606f1e7e157ae7b20660901b33471c4da3fde40be5e00f0d1ec4404141b4ab6700c8537c1be4fc23362c7256fc3ae129954fe1399cd8aca7a4a2cb2f5612b7de54fc36bd58e6678d4e3a1305e661a89b88c714f61239f8524a158765ebdaca9e69567452da538a4e5ec1026c9010001	\\x4d7900eb0cf5c6e270d5118acd30cd7e31ba3efd013cd0cf00a2aaab80d99c7fb539a0ef05e598ddd933e0706fbf31ffa7eede66a45b73c84defe1ec9aa25b08	1676813183000000	1677417983000000	1740489983000000	1835097983000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
259	\\x848e5899d4d3e458ebc6ce601fe4768fbb42fc4066d24a1bb9b96d3e4ef701d4d852db4ad5c0f7f5cdf52b1f0b15831b6a330f073f5bcababf973fa213e2ff1f	1	0	\\x000000010000000000800003b82ae9f9a2b5caee2257342516561e9f16b18d970e3cc3a399373480382c67bdc057b16d04742e873c40c104d2fc4d9075bc3c7cf4b676605f04620f642efb4b507fffd2fde14ec1613b2df097c4558be074841e5ef46e6a2dc5f09c999d790f400d8f181a648259911f6d092ccbbabdf752368702ef9cbe8d4662fbdf38ce41010001	\\x7709e1bf2e69518adb56e4c97a21e6309cc61eb05d488d70f0aea5163dd5895e954986c300d7f07a338b1641993c64bf3ae0fb5976061ea442fc1bfbd7886107	1670768183000000	1671372983000000	1734444983000000	1829052983000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
260	\\x895ee79a49542c9d0c71c5633c71d2a99511a76a6013a4dcfb50809e84db029b9cda13fa8a4bfdf4797cadc418d63f920b1fb02bbd755825ac2be85bfd814a37	1	0	\\x000000010000000000800003a5b521b9e34bf14bb557957b89efe35e1d7d8dde2cc2d4501a044efd781ae5f5cc5dc606350fb06fc58c9edd90bbf5a51504684c5cb58877575a57d9498304883d52029d65bfefee37578385432bf1964b008587995f555700d14cd0c31051a1f79197a311fb8aab6831f9010bf2604b8beb64a44e80da7f586cf238d983f2f5010001	\\x266e9d3b8af715ba7faa5df98f09512a3f28fc06c3bebb0f4e89280d5f8d498289f7bcbcb34d6e8c1c3b5bc47b9e01a3508e393bbea1e03b8a64b7ec6fdf190b	1678022183000000	1678626983000000	1741698983000000	1836306983000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
261	\\x89ce0c2c4ef74a23178cdc610c2f04e8c5acc543ada2f408685c4b960a6865274bc96339f98ed5fd8df0477f994fc050d5e09237f56b97266c45185f9510296f	1	0	\\x000000010000000000800003a8598685ab0431a64e4fe6fba44cc9378fe9beb31a18815a5a00e8f2634c923b3eb8faf525c0d7ee3fd9dbe4d73e28e9d28600f8bedcfcae8e87702c84dc75155fc61d35875b367daa38f4f379e014dec101623e7ab6cf59f83d5981a1796b750c5b856c7aa6d46a7235d358a4a42007ec98770d71b9b0db243578867a860f9d010001	\\x15fe63bb14163e6e5126bfb69489499a0e3d3273e7ea541d5293e8028e803eb117a1145a0773b1d72976c0bee8d1d7b06eb8d36e2f22ba2cc04733f216360d0f	1660491683000000	1661096483000000	1724168483000000	1818776483000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
262	\\x8e46949e28847d2cea37bd4a9dcabd92bcb2e614b53ea2abe8e83accad714ff2b0c425734ae7e6eab04d8336f1a9cbb03e47e956111bc328ef92bcdf493116ef	1	0	\\x000000010000000000800003e9d89d28d7f754d5e7ad31004bdc964db082f226a0313bef9c4b8dc0632f3b0784f94745e7b40b0a390e88cecb3d376c1bfd9ef1d35bfe68863fbbf3d5aa6a66d1a102da2aa1cba63a98caeb172e737e35da32c85784184a54c7e3e1e75ee972f26470e216dcd2f13ae54dece5090be0ca384a5eaf99cbd678ad87b1d53a11c9010001	\\x062e0ce815ca1ea3d66bf57a4cee741c180df21a406efdcfd7690e65090a769e56b92f96623abf4715bf1a4358eff00d2d18494347a57962ed6d5ca7a0fc390c	1687694183000000	1688298983000000	1751370983000000	1845978983000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
263	\\x8ede50dcb111e2a8420058832cc9ec5ffce3e39a26dff53ba14e0b95ae743fb05b68ea917bb44cfbd11658b785159ae0499f98433dd1e6de4099e1237cff7ec5	1	0	\\x000000010000000000800003a1338e2e4483855a2f804bbf0aae42c850998a0f31eb2f2d077ead1094d6c1d22dbc0a2e758314539183671b2a5c521aa8e452e5e732e7d877eac006ef4ce4bd051811c705ac74b3633cb012eb1b58e2ab55276eb2dc8509503ffa48d8eb1b87b2c8f8a14d0362b52c1fcb75ff0d09b2d39d7fa3fb727d13282d3128fb8ba66d010001	\\x91403116ef4148dcc66d74aa45333c46c90d18d0a730598176c52e159373509ba4ed35b2ca0a43d5409c4a428c2e68b30cf24a494a37078e665feb594c33880d	1674999683000000	1675604483000000	1738676483000000	1833284483000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
264	\\x8ee673f9512301720028e7afa817a815a5b3e3116c66d16dbc9409e8a081d3b5ebf7b4df15ab8f4c23cca044b37d91ba1fea5dfd1038758a165ddc2ab65d1a4e	1	0	\\x000000010000000000800003facac7e31423136892abcc474efda2e7dcd3dee68a09467dad0a8fc010c5ec769d6abaf7cbb0906268f5209829560b967350e67e8bcdd4f1dbdfd577ccee98190bee7c45674a040ac09a7707b4c6d0990a00bf2faecfbf833f2c4dbf41891044e39aff9b85d624596f8762469ab9c7cc60c8de8497c98a91060b537c8134a0b9010001	\\xee485cc734e3e5f7197ab6c70c83e59d1f0b3a6459a96f77fb02fdd469da05eebf103ccb2e8599d363fa0e1d3695eed1e496632c39fc004c42dc19a3d0c4be05	1685276183000000	1685880983000000	1748952983000000	1843560983000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
265	\\x8f6a3b125137e02d9c3a82d04634df3827523f57871008185765dade865129f051d1a50c4f29cf127a83892437369181e0f14952d7f9c420c0819ee486246035	1	0	\\x000000010000000000800003a99e6e2b557efd91d7c68e9e0cf6f4b475efc6ad5ca069e3aabd00f77c4d13cf857017bba8a96dc9a469b4e77c84b60220f82e4f6edc2a46ab0bb6a9df23cff61dcad01a6fd6e3f054f7c984199128f8f3f172c64926fb1ef0884d4cdadc1ca43e1e4c3a914a4ab0e82955e6f8560b2b5a1723db6d579ade66213ea966b246a3010001	\\x8e9b269df25752d57f8c9bd1d9e7032a78992580bb9b111df81ba0424c313553930743d9b925d7c9d8008a8bab7cc03b040bb177c63c5d2a187eaa110fff060f	1670768183000000	1671372983000000	1734444983000000	1829052983000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
266	\\x943e5f06814ddcef99db2fdf1b21d20f5b420827e12652f26a57571cf03caedf1fa00022c3f48b36f682ee2cf79ab32fb1ed8ef9957080571ccebd028c9be46e	1	0	\\x000000010000000000800003e18d5544b103fc24606d1241f898dbf72e06cf1a396e07910ce16dfe0a3b96d9c49c9c9f005690bb2135432dfa865952a97fea39c5e5db1e15e3032e1a014e08421203ca8c0bf7c7194653a6ee41e4b86f677a58b24dd0d7f49223c134c88c923c0e2444bc82b619fc3115f978b0da4ab148dc5d436c05617856f933016ced61010001	\\xcc363a93b34b4b2a8262a5ff1598cae95a1e6f33589a10d0fe38554d261ab153722b99128e356498466fd0ff23b8600f11e9bb78a7fff6670dca113fd9201608	1684067183000000	1684671983000000	1747743983000000	1842351983000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
267	\\x98029cb1aac0f5c48870b096e2442631135095f749533f5eb9d60088d67cc0308109ece1f387724623444747f3f03c1546682ad64679153d9d2257338ac3f1db	1	0	\\x000000010000000000800003b4fb7fb8841c1fd2d1ee1f74c42e78e01e1706c2bcf19d6e75695c06dd32493f9b696c0e4dabe3aab1eca1e306c96ff374c096e32a22d716263bcec9ab262327ae454f0797d607cac8e0a0c7b19530cb615d15cbaf6cb63398dab9e965e1e0a62e48068fb0d0088038c2ea22af5e03802d95c521353d1b2e07125d834fe19ecd010001	\\x0ec6732b255c24cdec41c96a315ece81a793fa8c1155dc074a510fff5a0f7c784e3f36108f309f0a1bc729c3a71b24dc619a037c10def6421afffb667e03240a	1668350183000000	1668954983000000	1732026983000000	1826634983000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
268	\\x988a210e1444469419a37f7a2acded99115dc7f754fa5d155e828dfe33e0013100a4e1e9413b3b8ce9b122407e7cd21be0265f0d0e25deb52fedd1f5ed876ccd	1	0	\\x000000010000000000800003c0713f0277b9b5b653e410809c48948331aaedfca65b3da72411d5c62358c28e5ab89f6e2886714d8619cd720e8037f6f0fb7197615c61df845ccf89b1fad4afe2d990bc0f1a25070f16753f5a6dc418ca54c1a18571639599508b6037e7d6b925d5d23c8a36f28a759936034ecceb5a8d82f4ce1bc167649656b3b9daad336d010001	\\xb44d782e2f1a7535adc2296a3bff2da91377d7dfd9e34ec9b1915e9e41e00ae87ee65994820f13445f242d573edfc08027f3e042be452210e883256d6a5e4903	1690716683000000	1691321483000000	1754393483000000	1849001483000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
269	\\x99b2c58c9bb128ca5666185a7838c755e556f44afdef2385451c487473f5abf7654c2c2d706603bdb4f1ee83d0cc9f75ceccfad584b52a29653f79849ef12e4b	1	0	\\x00000001000000000080000395649f3f3d569e61b8ac46056a105b5f9fdea901a75d2e0dcdfca01fd3c53034d1f5a997df687a9b5bf195fbbf4519198a2c905ece409140aaba6f6cee688ad779ec6a160a675c1368743bbd467d440e64eb6e74c1c4fddac53a6dd67c6638b6debbb1a812010d0c9fe7f3f12ad9d7a17a7c647fec7f52c19f824ec654ff256d010001	\\xeb07d50a0957f5539cc9e344e7f2e2d7340aa4ffd7c86ef76be843c8bfdc70e13ba538946cd586767d48c39c4e12d2c745d775f696b61b64e91a5d76bff8850d	1669559183000000	1670163983000000	1733235983000000	1827843983000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
270	\\x9a5a71b10970367e2f3289e89e6f6299321318ca1e1a601a6485d58f01d38596fccd33385a2f266e0b4357faa9dfc9c31b6466f62e92de57108411abe94abace	1	0	\\x000000010000000000800003bbd25c61e4725fcbda54351b7ea119c174ee3119eec1e8ffbce105cc7f22e4f55cf4c632da5f8bea282cc851610c974aa2148779d44a847cbce28fd763d6a63d9016f4d9c3f6e66aa1eb0f04a06461484e5b8239c2451196307d88a8369ee1eeb85e0723ceb89f9b473b56de228bc80d7c2b1e519a08578c91a9e328d6498de9010001	\\xeacb2e0ec111208b9949570a0ee7eb9a1f9e5395b5c44df74e70fd29cac8069af05a171b5610d4496abdcb61257289e9d3a466509758acea715df143d88e1600	1678626683000000	1679231483000000	1742303483000000	1836911483000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
271	\\x9a928aa7d5e3c8c081dd9120d0aebd3a1dde47c1ce3a732d82e159686323a76ff1b465bd108b6af71dddfab5c764c3ab4d7c341450d4949329070f0437543a92	1	0	\\x000000010000000000800003b42c7a8be009a35663722c7b1b1e67de247b73cc004fe7703f8ff6a01cbe6c995f29a7f2b56cb0437779914e7286f3abd54bca03b3726ceea0ea20b4700c699d11bdd3275bb51d066f5fd229d41a6c1d127ed3a0e45319f42492fc24b0aecd054357ea80462f9357dcde8e8e2e2d3b1fa49db017193c219474e5bd6b208ce7c1010001	\\x987ec1932b9a2f1a2356a8fecdf4e4e3adb34eaab69527ea3f7ab1fde5c18b67dc5065645cbfdba89f20d9757636b25da1a2c73284e2695ea803cadabade5b0d	1675604183000000	1676208983000000	1739280983000000	1833888983000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
272	\\x9c9a1821f6c3a15f64c2f49b292e259b0332a8169257bb2da50c9175059413cd64a8534c659003b4a5d7ec13f473bb376ccf21bf2c4af8cbd9e5b55b632d29b9	1	0	\\x000000010000000000800003d172d4e14228aa52647b3f3e6fda4c4c58fd739da0c5a773e8084c18893794fb65aa3a735bf8fac5aa976f7d051a43ee0e0060855a10a9025d0aba807c56634d1a5d0116b26d2019f32fb82f26958e1bba756ea2aed250ab0335bff2d6a584f8032117e7a5830c5926c61131ecd3561dca3a94de49ad3e8f469101bac4db669f010001	\\x84a853077af1bd55688d8146a44c480ff220af04bd97480c39e76e23044f531e818e35e480896b99a92af43649bf2990db3bdc3c8a1b983dc50e1d409cab8808	1690716683000000	1691321483000000	1754393483000000	1849001483000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
273	\\x9c7ec2f39bc41cb7b237268ff4b93e637d44bef741041530a8009e44dd0f4718d5f323ab0ba491affa0371b6debb9fe1899ff3e8addb3658f06f7ec9533053bb	1	0	\\x000000010000000000800003c63ad84df65f6c3c6aa8bcb874caed98d3ca83e8b22d50d0b8b73113d800712ab9e31126ba5c8aa0733d0e06385de678ea5454e7627201888f2b9f0eab4ea9672a023eef8a4f60eaac5815ccfefdb5373b43076617796ab035f965a4350717a659740a3f1e86dccad84566662eae3f8a7280411eee324a08d42ea1500f582803010001	\\xdd1b9ec9e1f90571025f98caf906b1e277fe628f1beabe6acb59f2c437d8fb5db18e827cc62a9ba7327be778bfe703cf1f5150279ca517a7071d604abb2b6905	1673790683000000	1674395483000000	1737467483000000	1832075483000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
274	\\x9eee5ffaf32d2ce73a44e214b356cb1b637e2552bb1f41b708c383cf189110c200dfa4ce9ec83fc40196d33cfd76f057880837f79463db5d86c4d22daaced1ac	1	0	\\x000000010000000000800003d03028b44a821a4eb217ab5ca925692491c8c2523aeac3801ac74ca47b3feab070add61ae44769dd1d4eb7177b389fdeaf2cd9f57043d2b13feb7abefb73cbabd7b669514261155f424a7d18bd2a9891ab7e2f842287f9b5a7bb16db73ebb70c6b4b3e224d224d6c85479f065a07af0c529aadd296ce709461455ad44552999d010001	\\xc97d833949f05220113c50bf6eff5fb39b347fdfdf9c24a75c034bc5e49b29e466cec78dfffcef3657995bd9e38a9683721b4860b5881fd15568a8e0ddff6b04	1685880683000000	1686485483000000	1749557483000000	1844165483000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
275	\\xa56ecc924f7e5b82e8e5537cdebc78cdd1672415624bf7d5a952bb257e5c6e3f5995fcd16528cdc5665ae8134f21d1b5f19470b2331981e7f61a7a403c6a419b	1	0	\\x000000010000000000800003c31b22230a5d7f906c77e3a3e06b2fc6bd5e110e94784f7696417c5cf32793fe08868e12d8d853f1cea84e886c647e1d2ade567db3cccba8d36ff55ca5b46980f0b0f95177ee128c6bd290356e9b2b54dced93a2b8f87d59519d9a82ad2cd0f5f7a8b58e543bded4adedf93ad5c6d68ab434f980d0e027ab87792c3f7a4b89b1010001	\\x169ac6cac3e293898f198a0fd15943c73f0aaf4a905465ba1e958bd5a449ad105d5c2a22e87f19393259f2f1861f92a26f6790fe8c2dd6a061ee9e28c050a706	1683462683000000	1684067483000000	1747139483000000	1841747483000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
276	\\xa672731733dfc829d4c5a103c1586f45ca8e5e6f15995e845e6a1b1b9713817370567684b5403316b92f23b4a1b58d913714e962a902221956b6d1a5694db1da	1	0	\\x000000010000000000800003dd68d3f8b58f8c72a5138c686cca991ae995a346f21bc7265c2ce8ded9ee31b84c078c0829f6419e62b62b9beeecc023f6a01a6c10238da4c311f96ceef26f958094a9d9074fde176ae7f5d42d20033d053cbbd6eb6f50104471e8e1eb750f71e6887f05dfcce537bdecf54e4e4efd84f0180803674ff4fd9705b4b9ee6cb839010001	\\x4e36305a28045c3b3e09f7497d9fc7076214d6921c103d33ce67a2998e68f857661a8c29297d4172f2f792c54b7f194281befa5cb586211f2ffc1799d8371307	1691321183000000	1691925983000000	1754997983000000	1849605983000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
277	\\xa906c987fb33713de1b7b69d1deb8c8d804fa76155ee31d7efd9fc3f33c1ea5941c8c78f9c58ebf0df96249268b8b116319f2ac1a4552cccba2300570021ff58	1	0	\\x000000010000000000800003c8cd77437eecf8f1da78384ee7e1fc176e8df4db1fa5844f266ec859904c0273749a40830f8376eea303cab5948be758771730541ccb9196131490c072d7c4dfbd06e5b11468ed961cf5bd8ff242f6d0ada45599834d721088fe39a8c4d0ea7921c8d6852f3906b2ca522f21ee752518c9b14f12366dee5f0d8b918347d6197b010001	\\xde13e1a7ebe5633b8aa0bc27e6f0888fd55972f3bad8f17ff22fc1d496aab471e70bd6a87ae03c52804f9eed950dc5178d6e960015b28e385caf8c39522d5603	1673186183000000	1673790983000000	1736862983000000	1831470983000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
278	\\xa9121d93580b5fac8c33ecbdf6077206471e6e5cd45729f5c8632114784e94335ad87de80c67a1acdc6a64e95efbef47e7aaf2fabf5392e18ee001985ecd3df1	1	0	\\x000000010000000000800003fddfd1d5fa082ffb6f512af728b85b1c9ffc2c037aa28c1793da39d4146f194efe4e14786cdb9da806ebb72c5f61d51c702412bc72fda4e4e4f34cc6a6a05caff8ed3eba9f8a2aa9da09e25ccb34e6b38dade4cf6d169c34083d2b157f0ad089e1401c97ee858051dea22a3478daf5aff96259ab2f9097ca56807c723f1032c1010001	\\x1ea152b28a331977828407870a98892fa0f206e60de09e6a8812dcdbc919d82fc5190afaff58bf0562eafd3321c8e17fcba6f057d286209bce1568919307960b	1660491683000000	1661096483000000	1724168483000000	1818776483000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
279	\\xab3ab83d81c8b949b741b9013f6a2c7bc00d79051a293c1f819d757ae4faaf06a23b2ec5d746005e941b894d55b588d7b954fad05d8fb6bfd260203cfb54bd26	1	0	\\x000000010000000000800003e720280d6bf3f7aa4c21939bd2817c82aea9ccf11c860de3a742f320457a70521f65a4c199590dfd10dccc5dc1fa7eda572a1dd4882e8c734c237de4922ffe2fa4f18cad944e6c4841597d45136f28e3c81c003ccaad1d356e82a55262254cfd9ba7348cdaef8c872a0c8c95ca6fe24310aaa489826e75ce257667954abad08b010001	\\xee7d6162a9762767aaf4dca6d751730ccbcd19432187099412a975626238b7c54563265bf4a86beb29d28fae047bd794ac9ea1c84d8ed6d602e6996c34b32802	1685880683000000	1686485483000000	1749557483000000	1844165483000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
280	\\xb28a6526226050aeb664050b9ca287e1f1aa2365fe8b571c56ea551222fca8a4db0d51b86b3e6c92d03438f9ff77f06164fa65ed55e0c568a5bbb634d930ad16	1	0	\\x000000010000000000800003cd535b14b18233ece617eb43f97e195a591d08473ec1074c121ca8048d2f97490ee5328407bf9ddca0227253bdfdb3bb0b24487b8eee15b0d0ba74880585d71be7f53b9717a575ba7995116e0476b435024387aa54e0a7097f2e0030920fc319f75f5c45940574faf3263256a3b3f1e9d311f4fb279a63f7458cf0511da5347b010001	\\x33ee823630531905c659b18bca72952b6ee363e66d9c51b6f6de7ee8579ab8ce4f2a1b9ad9b9f7f8527d3cb56488a5f57e6ff46a66f5c0a27a3a209db7c99007	1685276183000000	1685880983000000	1748952983000000	1843560983000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
281	\\xb3a60610ca0c1e95a05828918531f1ab51de564a1ef2ab7fb43977e7f0d01cffe40243e95dcddd33bd255d3f970f457b205c9a2b54b84c2e95d82d5d4a8c6c27	1	0	\\x000000010000000000800003c22e13530e36c2fd3eb65790e50bf9f5bc91cb9a7a6c352b7822a56a00d5cdf758cc3404770ae393ceeea1b841d212ce0005cca36111f52d20e045179b085bc58f6016e5d7fd9b2d9e5607d160c2d8cdf141ed51baf05fd25132519c6f3ab60979046c89e9bbac78c2586ebcbf772000624281a39636b0d05d65ad9ffcf60209010001	\\xe37bec322c5955d2a3e28f14189136362ea26da309dbf07937e1f43c0d37dc3866361fdf1eb47a3675f6bcc9d938a5b9ce021e0f00199d85ca16042da1351609	1669559183000000	1670163983000000	1733235983000000	1827843983000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
282	\\xb4d6963cf23cbf26b890027f31f5768693473e94a57875c5dbe2d05ea3fa298f4cbab1ba24942d80a5775044ee99ed485f3da43c82633c76166986d0f65c3987	1	0	\\x000000010000000000800003a0a6be200ad0482bc783cf6ed702471d631c96c2ec6c534500de510ff64b0047bd9ae82cb13e9e9c93c32fe243f1f84618e9b2d8d2d106fb89533c5492569dce29ddbc9ca7df15cdbc35afd1d5b953d67a1fe8b20fffd9a70e1359b815832a24a610d86ecb0f21763e75cf011bc5d89f90b66b967aa0d7ca3ef844d3d8b477a9010001	\\xfc39e590ca94ff3a46ff784b701974a6c6bd65ddbb91ff190dbd6b1db6804d81ddccd68c958f2a06be0deb50048619ec79fc466f3ea101957754e46d9ef15200	1681649183000000	1682253983000000	1745325983000000	1839933983000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
283	\\xb52663d67e25d9fead22357c2fc160a760ed579bb6e91f2493ec99c11fc3347d1a0a17b52e58803337d76f1cfc93461918d62f8f6f2fbf286a0f5a0796b837ce	1	0	\\x000000010000000000800003bf3b27aca724512845748be6992cd35d3bd61dca6cd59f943e51d7804ea5918a8d755478839d7de7064ac1f70232c85744f8ef724c9b4ead84bd85d27defeb763234966e29d37893d8c320e7d4569a4a1d37d3510cdf660dda700292d309d87292943d59119915250524f1cf173f0c7e48003b358406de3b07c576a2e3f8217d010001	\\x721414b236d09d0959f213c87e74c2dc970cc4052eda0cecca12d7efba10a56874db9d2bdfc9d96c88d80ebf31e511f9d49c7bf7562e502ebf72d7ad07098f0f	1681649183000000	1682253983000000	1745325983000000	1839933983000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
284	\\xb86246cea1c07f20cc5badd935940fe43279dac7889e5fb02eed3cf204817713f672cde9de117641047b195574cbb6a83be38b0ebc9af42160cbb99d77664372	1	0	\\x000000010000000000800003b94523b8a28e764c04fc51d25d5c5eecab6f79b5f29cca4a0d134cf439e1ae29180ac3070ee634b019872331e841d1ec495d18a7d5c0d70d5e8b34539fabc98d80bbc0e711be35b89a884f31dd429480717502eb4e6bca5d50fcdea20df1610c6272d45858169b048fc72976d452969f632058009c37d6722eaf98996822c9f7010001	\\x5fca00ede898a67d9e43a4a557e72c7d7c6c218cf2706fc2e0d17db08710a9c400203065353180d8024db848ddb1a4a8516e574ccf316cb0fece23f41322cb07	1691321183000000	1691925983000000	1754997983000000	1849605983000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
285	\\xbbfaad5f1072210e6e8bc0dae313de097bca8c6db657e35de55bdda9f86d6066eea9318ae18bd988b6c378b2716d46d912a229a9541844c62bb6f7c827fdd84e	1	0	\\x000000010000000000800003b6769b4e5ef5110173c0c1079763ef136396135cf59c4c7db0619aa0c9aa3b55e0f8d1e5e8a2e1f349a165a171587424eeffb40007796a1848524fff8bf0ea6118029996eabacd335cd1937c7868ef973ae8d4d5a170a2336ce8894558533079ee60e5ce99e7143f4afed903fac16566e80ecbe47daa248803f9bb0099281c5d010001	\\x7bbf4dd870fd639b5e539581301ab30b2400316aa312b170be05c9d967a4d87d7766015caddbb18cbc81dfd571d2aa7ef8a6a4f6b7f427932d00776f47b0e00d	1661700683000000	1662305483000000	1725377483000000	1819985483000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
286	\\xbc76a4fe5bfa4a38ad90632d173ec5a1badbbba2c0e11e85a1760aafe12704a837ae24c06d83b715fa50bd6b8d1ef293e4c17860893b02f37158c03858c71f65	1	0	\\x000000010000000000800003a9471a849ff45d40a60d9382e1f436ded31737850ea68d88fff541afbe0934ed497ad7f3543a3b908c7ba347f46e69274017d0a886a8acc9062f8ca31df998d56ed52389a89c58019783cac12c5cc65f12239b01b01be24c54dc1bf302c63bd5f1f21e3d9c17e24872860bca160c3a15bbb05b756078bc0b951859f89ead4dbb010001	\\xe03bfe2436973ddf168713f861ecc75645aa65da2a5a87ccbe329b28eb7580065b776ece5b14ec59cb05c45a49a47d3865f6916d72a96ac559767769583e6907	1671977183000000	1672581983000000	1735653983000000	1830261983000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
287	\\xbc22e8eabd4bc7c229655db984a8be01a9fb35a5aa2cfb4b88306a21cc6cec7128809533bfcf51c353474aea2f6606a115ea2fd04db04474f8003b6765d9f8c2	1	0	\\x000000010000000000800003b3aedb5372647251b240130004bb69ab4e760654c3a1eb451f20551727d3908fe36ba0333db9193f3e087f44638aa525e7ccb299f584fc965b2f75b2511752c6f166c3937ac49daa3735c8b8193d576d285fc3bf06146722342ce766e5ae2e94504553b262169b0f5552d7439be76d4b36ed001e0a48cc525299fad2720aca4d010001	\\x6b6141acc31abcf46315843016c34ea7b474f4a345edb41a2a464d4cf3bab41132dcc3cb0145f411bc0a60210087f3da15ce7869baf19c145849c5d3a763f500	1691925683000000	1692530483000000	1755602483000000	1850210483000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
288	\\xbd8a1b260cf03dbec6c7958291b4caaeecb9c7fc80be85568f89cb9e5745f6e109c1cbb72b4c35a703dedd04d71486fc75f1d5df85058700d627577bab351cfb	1	0	\\x000000010000000000800003b8fb1d9ab390d4c76a5fb6c873813afbfaccbf5549aa02dd9122fa5f1dfa8d4d3194385a6cffeddc3d7d17893615d66e2b924048cc7577564702b899bc885e31cd2962404ed421ae42ea9a5b00b4fe0bc60d3068419f10a63fed94eca44d409667565409c8f80475455047a2b94df75cc87c7a13e187e458b7261e5a2f29aae1010001	\\x80b8531688b93012c60953b5197d926be0f58e2776d78122795d674ed58b85005b1d76b382d5946a5dde524c64d637f230a8237dae82cbb776ff27639d352605	1689507683000000	1690112483000000	1753184483000000	1847792483000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
289	\\xbdb2b428d279c117065abf7a3b762058ffa2fee71d667eececbd67ee52a16e146619ccf2d20b95224228d6f94b653384b7f3e88f4a4b15bc62d518574477e01b	1	0	\\x000000010000000000800003b916dd7df51b8871e5c07511ff4c4f6ce76734f8aceb263d37cd56e2d0338254ffb506e2d64607c392805a7b0a19090a0300d3e93b8cd1ea67a88d8c5371adebd20b4f7fe9ffdddd24c5371f75c477e7c223a228e6a6788e469e7a0e39ed3fd8b9db62365b40aceb7d18a343f9cf3a65eface1cf8fbf97ca1ba09059ec4748b7010001	\\x8615871e8499352878e88ed957cb7a53b6cb4e2adde97f6cc2806b697a3c50b4fd192e7feb8e73b013b5ce408f9bb166d92eb5407c7e0f3a3a96b91ffa613408	1670163683000000	1670768483000000	1733840483000000	1828448483000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
290	\\xbe1e12dfa03976fb82b2d3b73d13fca98e5838da05f67270314c0e5ae3e8dd6a4491b9bac69c65c70986bdbda6a2b7b478fb1036e8f3bd3ff67f649a40a6eab1	1	0	\\x00000001000000000080000399d721d78c83d8476d2c296be5e6a990baa19d4f28899105e3f0094230e09f98a1aad421b2bdc9d636bc0a6bac915bf12fed636e19cb92e3894a663de23f8f242bcf6ca71e2dc5687cdfd741e8ee2919fa8f07095f573d8b4abbcd45f8d8ef3d1ef707fa1606739df396904662abb3db95e92aed09d1f7e4a9fd34eb2d0d8805010001	\\x1dac9acc7189addda8c9c778d98c17c870cb052eaab5832caac3320391ebfb0c7c7be7db78f00a3aa7c413131063860405ea4089ff05269743362f6e32e57b0a	1668350183000000	1668954983000000	1732026983000000	1826634983000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
291	\\xbf9a694b384fc58ffeb01351478f29b05007f05108b556c87cd4f0f34b3ed72934e687211d53fa2ed20dbfa0be11c7258b60252d46d84c8fdc8be9a196ae10d6	1	0	\\x000000010000000000800003dcda7f01f82c09ee51dfdb7a6601160f61b9d0f78f53c4136eb077dc2c7747a91b3b4a07804368ec9907031fa3c410b0e1c5c6766d82f7abb0250f204fe5f656dd3c43dc47848f048dbb5a062474af59be4d308369764f4fa652e6db58c73266dfd1f8936fb232621849f50be1a877f7a2b3992fe33633d38a65b3380c6ffda7010001	\\x1edd422a49263dac3c5f79e4eaa9744ea7e43d02ce7e66d4f95cf70f3a26b5e8ed7bfd64eb48f4aa23b8047b371c87f60489194423217432f3061370aa9bbb06	1663514183000000	1664118983000000	1727190983000000	1821798983000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
292	\\xc4d2ebdd4455f2a1bef1b1aef301ef8235425495d07eb0f657091245db6a155d0e2a38d97d97f6769d6d37b30d9ab4b188f08e0d7082361be2de477398ff906c	1	0	\\x000000010000000000800003ce38a9d1e26e2dd1b61874c7909c22a93ac1360f2f08870793e1bb6d72d17b894bf0406289533ce5fc0eeb9f3b399dc202276bfee00561bd7bf4cfa88e388042ad6d35481490fd2caa94bcf6f3969b873b094985684300166e34d7eb17a38ec6876c9eee0825c87902a0253db5e8868b148f292d2508363c32f8328a8636dc6f010001	\\x5bf0ff73911b5d7fdea34b13a08090aaf82f0a59863c0d3e4ce1296670766c631bcbf14750f39e290f6e4530de0c2e0d0c3fe42a45e5c3ba513bf012d0005e0e	1682858183000000	1683462983000000	1746534983000000	1841142983000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
293	\\xc73e5986628bf02c2ddb2eab4c3f23079f17b937469706673e6dd69bcbccdc5ed72394ddceb0e31fe0e0bce5049192eddeb250f47c91a3589b76ff8ec6e9b195	1	0	\\x000000010000000000800003cfe97d073673e619a0b8a6c3df33eafaf7b0cc94d0650108a37f520610dc1880034c0b659f7e5997a29d94e5d622883bf275e0ee16a22d7a43102a7875b68417abb60395524ba915eb286fbb50deefbfc77cc5e46e8855d6539c6f63fe093bec6796b86cedbead45c5f266408a1dab47a20f512e61b6337962470b177bba103d010001	\\x5ced4812a28137881161e1568080fc19521a24a67143c2b641285706be6a043e570cb71090d634cfc3d23b1b77805d6b90ebaecd539dff7f6f78880852a1cf0e	1691321183000000	1691925983000000	1754997983000000	1849605983000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
294	\\xc8f608363d045f58855fd01f8276b60010480beefd811e4e3bc4e141c1da2c400d340f0730478a2d5b9ce9a882886b04767a01bf233082051aefb897da6ba3dd	1	0	\\x000000010000000000800003c6f07ed5d74fc5fa24351c241a88de2e8a4f3f032abc2c9e0141fa46ab3321b56f69e5c617e36de28f271764fd6df40f7df91527044026e8c96e167ea77688565eba8199f646290c0876b1661d5ab3f99812108608f9e00b2536cb7a53f07e1ecb8b4093e529be4f129bf37238a8ee339845a3b88186e7314fc9ae54e7627a33010001	\\x35f4160670d3c47c5d921351e4bb295bc7a87ef9f06ef4ca1b38079815a2beefa79f7cf8a68f36f184820a9a25d0428c8257dc669aeaf39a4d7c9bdbc862f602	1676208683000000	1676813483000000	1739885483000000	1834493483000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
295	\\xc9226ffd1379cd8222125a959f25fa2e222ffa5db583084760cbbf7ffdf1d2c7257c119363af62dc12e4ea53062cb8dd2d4722bbb20a846bd1950870023ad2b3	1	0	\\x000000010000000000800003c2a0aabbb29201cb71f5229134e87bc1e4a1267c7ed357221d7ed78c9e688cd52dd45a05e29caf2489259c47520cfe181b0a77c31188ea38d01e5cb23147035a47686ff633369b53f60f3dddbcce7eea9cae47031a60e560a8debcd73a9377206fe78afc1ec3012a3f6057165c5f16271c6a322e7c38eb2435e4d33f1b465b6b010001	\\x3c275ddc0da3b27dd79b81cfcdfe80d99204e4dada4b16ef3cfa8b58dd37af9ab2302151b46953c6f9d372509af104d61228107e0d495fce00acffa43a282e09	1687089683000000	1687694483000000	1750766483000000	1845374483000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
296	\\xca32b21dffa75bd1d36221f6c060524b9f49d1afb8c59ef20339679008fd84cb8333b6e11d2f624f1baf0a141f27015325fa915e1af05ec4504ebacea00361e8	1	0	\\x000000010000000000800003ca2900b5f14d4d90aaa3dd2a026649a35e7b1e713ff7607e446d708b38fb810618c40619dc2150736e2e4f904cbaa75f01166a19800e1fa72093ab1fecd087d3872f349e874897868048db2ce9756be79e8634d6310324128fea10f382fb9572b874ca12096c68f9480fa8f9111d1c6331d04186c1b834008dea63960a19731f010001	\\xef25e060c64c5e368a15e81db74deebb14a3567871ecae5561c0cbf50af60ce964a61ab2d5aa2df4b28526af52a606743c5fb08d61e43a8587e2cb134fd2670a	1688298683000000	1688903483000000	1751975483000000	1846583483000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
297	\\xcb52464a78dbbac1c1c74c6f5ec9a5a36919c2ee685a56b6d8fb0065d6c1f54d23c69b6d536ff14b8f36e56e76519292a85272a070f8a13a4fc4720d4eecefe4	1	0	\\x000000010000000000800003f1b27b38ecfb792db2a7493a7765e7d1dff70ad2e98407c37c5e7959587dff9fb60e7acdb233b47bd4b9513cff4f95126a049decf46fb98bc47f03c75a651763ff3245c821315ca752419c49f555fcf708512617d6336a295175707d920e29da8023b9fd1ac88352aa162c9592bd355774b40ceaa55434564af566aee1a5ab11010001	\\xcf2f6626b1df08c027afd80dec82faa215d5637cbf62ac6154dbb7771cd4e10d4b23acfec8d64cc080727611e15fd85c213e81b25ae4f9eb06ae85d1d7299302	1685880683000000	1686485483000000	1749557483000000	1844165483000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
298	\\xce6a8fa93a07417718dab4660d3f2bae43ff373adaeff3d6958883ec31aa66ec762d5fe74df48c586a4afd7c28b7f9549365e6f8cdf8982c855eacbb77db3228	1	0	\\x000000010000000000800003f38dba278673d5c6f24e7680be002d1cfbd2d225b6181cf9ccc4ca4ee32750c49f10178ee774123b4a8a000c60d992460fd0ac9b3cb8f1a01445d32aaa804f771f6d9ea421f339fb3dd4edebe1084e1e3ce30148021365157ec009dc2aa5b9fda3b8d259fe5add091766d8e19840d19c2058c96d7c5d87636b03fd8e35257b95010001	\\xe4cd1364cf80a65e58944bbcd0c0fd238a476e055e22814a89e2fa785e256b75cc131b046eb31723755d57cdaa490c5ff4f63a3a2ad7afe831efa3d5e7872a0c	1676813183000000	1677417983000000	1740489983000000	1835097983000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
299	\\xd0e6020632e7569d47640d2d286bf34ce2226c39c8c2a2e1adfc1ae797b680d9b11b65f7bc9e864d4678add5dc58cf8119a79ac2162446b7c728e6f44abe3460	1	0	\\x000000010000000000800003baa32f407fb8884c766be7902e2a8c0872147b40c5112debb0df78cc8e792847c66b95297f36afa1c7885c97abdaf86ec61c4d4198ccd09d0c2e2c91fe94dfcc3beef9612e455aa7ddfd61748ef92cdbe95b96f9985c633df543e75216a25437f7b8ac353e6f49aeb392ba9f0d78704755fb520eaddb8ecb989905744b0f1563010001	\\xaa734924cc299d83f6380e798042d0e4c0139f5e528f8417e4912f1b2a58a53d51c57416b35ac349e03fa5428062346af77d55d0af580589d07e04d509674606	1688903183000000	1689507983000000	1752579983000000	1847187983000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
300	\\xd136de5e874c3937b84b6744ee0f0e056e7c1edca6cd8232ccefb9729ee40fd843008d8206d9d0797b30bf0d1265190666ba6fad957ab15d6d043ad7232409e7	1	0	\\x000000010000000000800003ae4616968bc9f6a9684a067198a2e1c6cdd53b03db3c19713f23ebad50f3774de55119669d225b5cc90c391b699f417f46d7a4c9f05fd26e50ae00c86dbef7df4b16bbb6f321184b5d6dad5fac92f0a8bc1db0928b9f40164b73a84f8d2724b9671d79fe5d4cecf8e02fa030204bffcde4530147bdb6d9782f569f866b8ae2a7010001	\\xbe50cf8626dedb440cdb318d79f68e8c5ea09605ce5350aa17ecc8be9edb1d949079d31bee3864bb2948117d4f8d63ba6c16a74b63685916c429969556420b09	1671372683000000	1671977483000000	1735049483000000	1829657483000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
301	\\xd10e614bfae9497bb36f8ddc23c8843b7caed65cb5cbf1883ea75f15f3a5c4e29b7782812acf30e43159da50cf004ec57ef573ce3785a13df7ce4aea1c08cdfb	1	0	\\x000000010000000000800003ba1c697e0521c81855ebf46c6cee038de3098e9a864b1919b04823262cf41bcb4973d555c1a9ecd8acc8b9745f49f61369603fd34e25e3fcb97bc8797a06e96d6235131797e01d505e2523e2d957b552e66313769f8f3b1f429f4b419b3d94c4091474292e0bf7a7511cbcf04e7206af68e99fc4651558b4135f4aba04f47bb5010001	\\x3c32bf3a8c01aec131de4579cea2d62aa15769058e887382c27aa1090ded6b101a56098806826a1926499adcd7f05b2c77b064e1153ca237bfbceb00daaeec0d	1676813183000000	1677417983000000	1740489983000000	1835097983000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
302	\\xd25a75357c7b35ecf0629bb21f25c4b9c93fc9f6ef434158cfb1e4d61c6758cee7c266e012586a66809b36d10f79bd7716a923c69d00ffd8c373c145baf36936	1	0	\\x000000010000000000800003c7d1033714debe58ef82bd7df59818317c0efe73ac3bf6a768a7601ded9a41c97e3e79ad4e8177f9702937d5e3d8a4cda27eca1e7fe28ac8230cbf022c8c04742b8d55ccc88feffe3d0fc006390a2b15828e3d7db2dffb8818c88ba0b553232fb735013605e63ca2b617275fd3490090ffb30c8b55826da980152c4fa4927b53010001	\\xe8c5da25da26a125aef1d38c207f2870f6bc2ed524c9edf4bebb814234b1f413ed019bc1aacf3a80794cb8d797c02e9cf1f3d683cdae1ade5f72c3108174c00d	1672581683000000	1673186483000000	1736258483000000	1830866483000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
303	\\xd5e66ccb0e8df028bed5552cacb486d7f1c79a1c4cd3edd952d68215b322820708502ed68c38f0b75d828d6277ce8c0847d5bdb80c78cd5a7bd97eecdb95e8c4	1	0	\\x000000010000000000800003c765ed67a49a6d8eeb17256b9da30324f6d6126b12c77afdd87d7d8d340167ff6e6c9acc14f33cdd9687a7987479ec25dc2863512907c9ababc19dde12703dc8866b37b1536692d43e93b92ae1a663fdcf3dc71e37274350a586507c3907f86ce9863e6aeac05439f0ea7bf352f63042ca5eb9c29eb054775146245ce244e937010001	\\x724860bff4afc5908b9ac2fb01cebc6b5f6fca27b6a580bd092005a4aaea0832a702dc6c5ed683f7e388193336b66905501c960246e84f2f0490d3711ad18e07	1681044683000000	1681649483000000	1744721483000000	1839329483000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
304	\\xd7d608eac50785e1e16af210fbf57036c41fd1fa91dce7ffb81795008a2ada7fa10097fcb1012192efc95c9ac42a4d1ffd3e7a1a6bb1b47366faa64a6c0471c0	1	0	\\x000000010000000000800003c0616a33c2c1c875b8968145b2856a1220fcf8e619402295fc90caae17f70be1efefd04c1bafa0bc99b3f2d2a30961c430b2491a267e3f7ec68eb31d8578e586d3ccaa69d9de8dffcb96811ce5f5d6c6c7961a4edaba5219fe3dfb083fd95b749005207ca6de422045bdd37d5834a0ddce2932c68037eed2a47a6a9b14d068bb010001	\\x6b29f1e4bad7949da3d1f243f3fb51ca2c80d0855af4efb5058921ff43dbf923b28876cbe24c7be129698f13e581112f73d5a372b65802af5ccd11d030bc2a0f	1674395183000000	1674999983000000	1738071983000000	1832679983000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
305	\\xd80a205d179831870b4d5afc4084716b66ad1383aafb45bd4be441787b6d3bdb845886e7c1dba33b8494a2758bf2b69034947a9fcb1128969e18a31bb3fa5fe8	1	0	\\x000000010000000000800003ab89c9a719be32c789783d3141cb98b0463852b31075216fc9d3cf01d4d96acaf9f2cf91f0ca04d67ef06f5cd34bc36514e428702977e27a2e8514651d1d8e6cb65293f1ee69554373ee6298a027740e13d70bd6143aee4b4435ce5987e231a2b116f7153d9c63fbda1741e567308dd4ffa28becdb3a16da13eba3e1a3f65d37010001	\\x0417144ba640f80d71c3523dac1da99fefd3e8f09273e5bf0d085e6d59f1d583703ecbd8efd35e8e90391295617f4462b3d9ee70697573eb4856994f60681303	1690716683000000	1691321483000000	1754393483000000	1849001483000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
306	\\xdd5a44257726182efca43ef9ea82e3034b38de4a4ef0db43cedc97498539fe28a7082c6c75d86c7c5bf6495abbe40ea930d4686cd11520c5190c4431a104a51c	1	0	\\x000000010000000000800003c681653f363750f6fc7a332aa0d13055d9fd93d9ec4de61cf1175058a89b00b61253313635e433e5e8c2d51ee22376c1083e6c553a82f48dd4f32bff1d0e2a44dced0739482c3a0ea545ac51936dda9138b2559af653c642198fd2450381c35f9b2a98a09f5841e462940c134e56d0241c4a3b2b36e135b432a722ccff294229010001	\\xc001d7b510f943a017fc534f8546d6d866838bbad3b4ad7140190c1a48cedb450c6f2287fe42b2aad8ae07789a007feb444e82404dea7c55d68aaf71f524c50a	1664118683000000	1664723483000000	1727795483000000	1822403483000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
307	\\xe0fa9efe610807e1d9aba95cca17e00e8e637431de784e645c22a344210e9f8a0c78e53e473eb3ddc75d7d3c907ff559c7b0449672d045e862128b56cfb71b1e	1	0	\\x000000010000000000800003d693214cab577de51e49daa8194ca8bf786a13c84ef816324d30cf1fb8ccb8d9ca2f89fe08b144991767bacabb1623e2d7c2fab9fb699adb077220ff67f6161ea07b9bf3b685862524583ba7e35486f7483cc4dc0b09b6e170d94cbc751ec086747782ac5e52d8516efcec665c442599a3999f8ce2fed49697b463e0957c7601010001	\\x8d6841eb9b258bdaf17ef96512d5d59df86e15be1495f4186d9222cfdaf679187785133c3399822a410b05dd16c452d19a4c0ad48886dc9a81f21ba9a7581b0d	1691925683000000	1692530483000000	1755602483000000	1850210483000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
308	\\xe2d2b595b083714e09ce64491db7d610b562e0ab80c2d2c45ef5a8604c7a736ccee0d5c336b8b742898e73a05fcab98f35700dba1e4e774910f77bdadbcf7a03	1	0	\\x000000010000000000800003ba58f85b1252f1e2e0dce2786784979c004c1f1c57d04a6cdb857ad64b786fa1dd3a9e40ed5a13469115875c84ed0fac25408e657faee406f24a63763f19925e7cec9c5836e0a80e67d3c8823ffd71ca146a44defc025e9189c31a6b93af6d18bdd21c6465ab8684afbc2f08e1b9e398800a70db0a4bf3a680968f5c161d9869010001	\\x9a17b773150c1e5aa8f9bede7e443ae890e143e69b05ab042716cece5e6ac18ae22a186ee71f83e388bd1897e1512c578bf26aaeac5a61c5bac75d356b292d09	1661096183000000	1661700983000000	1724772983000000	1819380983000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
309	\\xeaae383f4f71c97bf7b449acf4a61d8f763f21c8358a751f328ac7d76016fa896c09d7534c4a1e0232d5fb519fc84225a0a4e00c3fd37a18e5ba2188fe514d3e	1	0	\\x000000010000000000800003a77b707a4364ce0688110493e3232bd0a7bce4ece7b88260fe1f8f290d78b05aefde080f2bea123a418f8e147862849b5792d0fe19886e1ab5c92c5f557d5538b3f225372278c14a7c25626e776affe950179b4c0d6bfa87cbe5297ccfac51ee7cb4727a2f2a00fe20b8c5a8038632acb02462bd8b60abb4675ed031d23f15f9010001	\\xceaf47a874b9ae896e951e2fab58c011ebdf448c408f5b3375f6d92ca819535a2a3d0883595cdd63f805fda46915ad36487951b31f4194d09253f7a8bda2cd0e	1677417683000000	1678022483000000	1741094483000000	1835702483000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
310	\\xeb62a0c76c49ffaf39c7cded990982028ff80da6609306eed7e05139b10bb354038fb856f90775f1d3cce79d628d4473e8f2ff2edf3f2e66232188111c3eb42d	1	0	\\x000000010000000000800003ccf451b66378ca11d988b523b6f499cf466039d1c35f535e7624925041a59e8f378a23f746981346a4983713a37a0f33048c910c3de49808c5faa98a87b9370a302686b5047108945582990aa820143e1348cf985c84154b214fc50d319bf3ef4e7ce61dd826ee5d72ae06c23401082668c874afbbf0a29c8221ff67b17162df010001	\\x44ef60ceb2450b4ab253f36334d030de85566ed49057685a25526a0a88fa96b8ad7c2edb39a59c48a143000087c61df97c667f93fbc67cec8e390c97ce664907	1677417683000000	1678022483000000	1741094483000000	1835702483000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
311	\\xed860b50bf3660ef99ce490291175e035fe43752687a8b0686b9c4ab9b20e306c138a1092d26698d2a9a86038fb15531cd9297ef680e746d2a3ed81e225cf9a5	1	0	\\x000000010000000000800003d28095428105919398e50dc1e378bd61c67a5119beca09c388bcad04183851ae333a03966838ebe82f69dcb5218be737a0100f14bd1f1aa55bf9d8a7a6a4b061d5ec9e4006da9cbf95f62cc68b0244607ee1130dae26d38186815e3f4fdde863ac8b508d447d86a981c3661a6ae250cf778f99325e0c72c5a06ee54f92993215010001	\\xfc5b7321020a4b2fc189eb44c7ca866aa4d7bfd9652027105525f88a29a6e63bbaec208a7baed8445f4aeb55cd42558c5ffd60054f9d66c2530b93be9b7ee304	1682253683000000	1682858483000000	1745930483000000	1840538483000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
312	\\xf11e1090dc875aa8b5cccd2da039ba9b169e8e5e7b527fb5d3af38f8901d386532cbb67f294d23394fc10d70bfebdfb199c82057b2f20769463fe7ca32d1c75c	1	0	\\x000000010000000000800003aa75025d1f3d7d963c4a5c9d8d918486c108731ccc76fd3c616476398074d41eca3a2120522991f52c8d9b4428dbd0c8e2a04dbb0d7be8ef9eb701718db5728bdf9f768c371c89f54bcb49efa1a6dbc621e8c70e8cd7962d9f3581986ee094a8e415c58003f018a29da54ee930b8f750249386ec1770504e16a0a1662c4a2c43010001	\\x8088e69cb621ba803236c0faa19081c7cb5c4c83dbfc147e310bb93dead2eb68fe8e03de9424eef20c65f9b006ebf2182910339dc98bf2cb5da585aa83d2780b	1679835683000000	1680440483000000	1743512483000000	1838120483000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
313	\\xf13eff766864aacce1a7b1c478c665723b6b027ca4293fb411e394532428e36c3020d055442d02c6f12a530fc078cd69f59edce949edf343afe8cc20fbce759f	1	0	\\x0000000100000000008000039e917550f8dddfa2c20a4b8edfc3f7546531c39385db3dfa97b697815495b5d5a764dbb40f9e20f911b61b1bf02c94908ebd251f195a78fc6657f537e7eef2dd31744ea1deee71a16ed7400100f57076a8399460bf148f32fb14b28fc3951904e8f679255cc08124c04571670081f61fcf4aa684e5bfca282ef9343296b8d5a7010001	\\x546cfd94a887998e7f822d378a65b2c5abdf5313db56f9457c07c26fb34dce7de928dfa2d70d210c4afabc350b5672b8835a2bf97a28a6e1eca4f3dc63173506	1684671683000000	1685276483000000	1748348483000000	1842956483000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
314	\\xf226c95337f8f18c5de6a51a17d2aa5ac51c39168b81de02368e4c57b4002431ffc7f63679769d90809168b7c5cb15874e2b1e9c1464aa47c02e20455a269443	1	0	\\x000000010000000000800003ccafb00ee1028a484fed6d1b3a5e895ef2a261652a40dd36d07f436b63d856a7a09883d705bc959bd56e6472247db3a1eaf099f7b5ebd743c2a83467aa411660ca83f21a2bd96745405cca34e782d6ba7b9cd0742ac8b7c9d09a7a7fef430d4c4e75efaebc7a19315c5f202cadfa7a7e867cd83ed28e4e24f38fd753c377aa7f010001	\\x1a348599dd9b98b9e346ddf3f1058935b83cd2ecc3684a9b820f7a77f18bb375e05a9adc30d2124d682ba79e6389baf5a3daf81925f3f766399250ca0f5e4f00	1660491683000000	1661096483000000	1724168483000000	1818776483000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
315	\\xf49a913119b98d4b0ea99926c92370dfe8e5e8c9ff5ff48a4cc16c01a04b95d3158c36117928b7dbb922b0a8ada20293bdd609ae502466278be717f6d72f1b95	1	0	\\x000000010000000000800003bdf3926bdbab30d4688a4aeacaa6855c3148e8dd1b0b24074e4d4d7880c19a5c739024af160286a37651ee606c370a1fae89d7146135a8089b5f197790e72ebdded6a47599bda0dce33134ad5ceed0a0a9f8d8a8f570097e44295a85fd2b8ac2d6f06dbe8544dc84ebbdcee06743be8a750259d0e9fc06067a27e0116b05170b010001	\\x23b696efdc9c018fe3cda575d9a90d1ff1a05d3160d7123ee37791931d043e93eee83a16c83f2aa4f1df6213f85b8ee95dd541df04b5ece71da640c45f05f60b	1684067183000000	1684671983000000	1747743983000000	1842351983000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
316	\\xf402efe83f97e262d98f9ed1182265bf837c47ec72c122c12cda77c65d0578f0a174df000dcbfb17e896f46741e16ed494624c2c5a8e7861bc79f4967846f9e7	1	0	\\x000000010000000000800003cbcc7e85770936479fe99b587cb1c846af92e90a41b5eaa73d5e712b2388b9eb44f0c6c57bee2227fa935439bc3b63c5a11375e6d3883e798c4eb19a6e5d492db2a22a10266ee62f032b08bb10fad60423139f9b1777880da57b53ec748b5925a102d8545623c3fe11d417c24c193b7b67f4bbc0d60749be08bf9ac5d476347d010001	\\x11b8738fb8607298e1723e7913aa2c3f73dd1bb05dd0156facd2840ce1d46d954ec76a40bb73c6862fa57e3b0acf72b04502ea9ec2b8c7ae58d4c44bc5d41906	1674395183000000	1674999983000000	1738071983000000	1832679983000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
317	\\xf5e68445d00add4df94cc46a24155807f7cc8b0d3093fb1490d7c560c6d3959dd675857ce5f4edeb9ecde648b4d2a4614d9eae53f7b424609a333fdee9e6ec4d	1	0	\\x000000010000000000800003cfbb09fb0e760434f6710c0f0c61bf571741f56b3a5897fae099db9a7061f5ffb7b8c7e372c75c8c27c88c3d2764d69db944b79f4cbce1c3b51dddbed6bbb6a06e6402610d45c46b27c072f17c9082a9f744d3d0c65e480cf2d465107455b63a97eeb8ec33651d8a37add96eb27c93bb4982e3a8479e72525775c26889f0fdab010001	\\x6811e73beba2b206781bd89bc09be6cfade0b3920031f60119d64d8f9530907c1730c81136f03e5d9f94bb515bd770a50b90e0c847b16050edce36d4b4014e03	1689507683000000	1690112483000000	1753184483000000	1847792483000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
318	\\xf5f6c02bb2181b1794071bf88d0e9668fbf6fded052054bb95f7edfe66bc3dd4db6889c458d1b4adf8f4590104f0b6eded9adb0022e876599cb0b0209b0a0fc0	1	0	\\x000000010000000000800003bf043d0a60e61adf215e9a8b1abe3387160faff3d0c418aac5567fd9d76ffef91017bb6aa5f5f888c4cb8b3b168060de526bd9c5229b07fa47fc194af8b65a24c08a3e9be284bf663af3259463f533fd7fc8741c4893cdc14d581c066f0dd4293d7b943031370cff36c613c481df8ff97363a9d197d49c7c41006ea8adc4222b010001	\\xfdb8885ed66a775334748465dc1105a2dbb4aed9d31204a7f902a9c5144946d23cf5ff2f2b17f09b672576997a4a7091df3a6b2a6f46b9297cf061703fb42c06	1678022183000000	1678626983000000	1741698983000000	1836306983000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
319	\\xf62e11f414e33221523ecefe6f038daddef279e43e5c79c552b958bdf3f10df937c6421941e7c94cd28e8e34580512ccc3c26d9d9f47b4a7eccac74877163e1a	1	0	\\x000000010000000000800003c9c7799da8f276faf4bbf3d9d56f85073f783cc4e0cc410da0ef8cbea8c1cefeb82f2ae7dae88fef68ac054ae60212a4400918c8b777dea2eeb599a2979812333e1566ad8c575456f4759144a83f8d655244f9e6b331491c2a6c49706ff9a25ebe90c5ffe831e9c4c3aa963edebb24a4dc2443b6b8c07fb412b724c1b69c7c77010001	\\x812d16a634a05f4df9ace3e798cfc4fdd6eb44e028279bef0fb54ca0361b8527bc6b1d25ad57485f6e8e75c0f8e323d1ed6bd10229a81bc0480b5a59d9dfaa01	1668954683000000	1669559483000000	1732631483000000	1827239483000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
320	\\x02738e293407d5c9822e2807c2da430d8fb85c719b0ed914c2b3148c4fe4a9b2dedce2ff261f680abd4edb3409c505b92453ee8bc8baa3765ad7c1aa740d812e	1	0	\\x000000010000000000800003e0003209e40a398872d65ed8f13b89663021872b2be9494f9a7fc038812a025239009ddba55cd42d5ce16a5d36b5e86b571da58d087b578e359ef6ab4601c32449a53ce27d5ac240a07a965b817d06af742e8ac8e567ccdd161a78efb370d68bd4c6fd98284ccb870a356c8fdbd4ede690ff6daacad9f596b87ad248c6d2ea6f010001	\\xcb2c60838dfdfa656d81fd1b29b34f241affa7a3d65bcfc633aef183149ea921f774244721042d23e3851e937055833f726276821a2b3e3e69ab81baf4405f0d	1676208683000000	1676813483000000	1739885483000000	1834493483000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
321	\\x0313a90b7a7dab5693953929701ab2ded56e5dce7b529389ce221a9628812f65ff8873219df4c4eca5e659cd9960c4a68bfe4f4bc936de605fe0cec4412fdc9d	1	0	\\x000000010000000000800003a1fa0f620cf16f75f0c8c9f23de1d25065b4f5862cddc454d69298444835b0933e2fba06343e33a12f398c5d1a98cbb3818f94bc7f5364266dbd0b68e16bbe2748f0898313b47dfdafa1ccd50f08946eba8e0f1984a390fc207d1a045893e8c168b143045c843663503a99aa6a1ee8be20913094df28cf8cf7ed5601edef453d010001	\\xbdd714d8abdeedfa311421cc6177bebd981b51fbd70f9227d864e4f6335ff601ef855856777d22a10d607c1e5711c4a5a9afac721d00c908da2b0e3939576d04	1676208683000000	1676813483000000	1739885483000000	1834493483000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
322	\\x0307099b6746436a934740cf7b9e42b490167ce1c050ebc3e31937a04aa05c5e1ae81cee65b88fe3acc7783b3847b1b3b8fe8f1b90403590cb8bdea043ab2f91	1	0	\\x000000010000000000800003998d4e42399b70d808fb2ef2a45a0c13d4a993d91f1e6324ebdeb20aedbb05c6c65916348a5a7eb2bc5269c46593b51a563f68c4f1880205920149f7a290184258416e35c02aa7a4e397ce377cad8fe0734eb6a5723571fb426df9f12b718829a73f0036d5e7f8cd0f8225ce37f07cbee73189b7937fdb4125a9d5a24509bcc7010001	\\x81376838c5932cafd2570a3c0fbf1e168add6f059b67f958054c727c6be84c31c2e3b1a45a33dbd8227505c4bc21447607a24aaea85b3b0d5ab8f81de6e06704	1664723183000000	1665327983000000	1728399983000000	1823007983000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
323	\\x07039512efc6499380d85ef21b0270f5202f83576bdc0d511a6ecf77ad7f3e64c8aecdcd9886ad9922e6685887eaec8d8d12320309d18424498f2c17f6e18546	1	0	\\x000000010000000000800003c35013ef9107cdaac7beb1aad08d598e1b0f585676449bcd1c1f5b88c4aa45f588b9c8629f9dd2fa7ad68bc3daef509ab5b26b4956965324d7f4dc162a9f16be3984fca87bae3ebecb22a8bfb4744edd30712c368e1bb1d9b77e87b5b27255ec6252e0b9860ac1e1e4380ab6818b3c313cfba94ebefe6e3febe934cca3e95f9d010001	\\xfc92be6149cb251f3a49a2c548bcdf4d90a058a48bc53a91145ba3f4d86e21d41913f37265e40e6d24eb2f50d2a36f5fc1e6870e15a7db69b132a5e65424cb0c	1668350183000000	1668954983000000	1732026983000000	1826634983000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
324	\\x08fbe4155759e94ad50a5d157f9722ae2b709e835f5f33ab9b3ec91671b2e5a3a3bef74fc74a8af1ec5b35f2dd4b89ecdc0f38ff8699a6f8b759ea1b8e08ca12	1	0	\\x000000010000000000800003a9305cb39d2b501b86d8423c09a414b3aa1a915e5fc99cc679313f87d2395ce8e7c171cdb6e624aac14ba733b08edca1fd8d1472e6299b0157714e7e399af724e3ff729df012c1b0b502854b9479e714c0845edc2687fb45d5a14c6ed9fbe36622bada4a73c1152df42613b0d8349e35aa727f67409e2faf010fe7267d09f90b010001	\\xb81fe36e78d6dc1f6cd654e387171fae37864129e5a00a8028878edf62b0670784df1ded00df903d1a1fad4bd580a390392910470a5c89a3c95eacfbc2201408	1670163683000000	1670768483000000	1733840483000000	1828448483000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
325	\\x0ce3eea7fd857ff4e25b8161d715c8413de4e449e0919ba1ed7f172de9a6e5311b2c83e0c1f9390406908b49c2056589bb42f5d8c0f12d0d830ba3ffa942c0bd	1	0	\\x000000010000000000800003bc625b6fc54fb9e83a037770a48436acaefbf955414477acdf3fc4c561632952336721bcadcb1e3659fe16701f0ae78e6a265b413f3f006da3479483507570bd7dcf97fa5ebae9cc089ef391eb7d31b49191cf833fb5ea7d7bdf519e65d0cdf5689c3ee3495dee3bd113de6649b108decdc6d1bfb7941355ffb9f53397accce7010001	\\xa208c019dbabb5d24e3ecf7e3b2ea5585502ee569bf9a5cef3261e87d0a553a15014874db63dc7cfac275114d5a654c125462349642b4d9c231f51e97de9010f	1668954683000000	1669559483000000	1732631483000000	1827239483000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
326	\\x0effc5b3324d5e5ba3a4b44096b037554116d8ac0a725b352d40872a77b6a225502a6944399d98e13fa9cfb2607b07b89771db4a75d1d40fb10cca9c515933b1	1	0	\\x000000010000000000800003c84c61ff92ac08bb5684065975f9da5c5292374960226957ea77519beea1222cedf545737b1d4eeb55691c31313f2c0a6735d9eb444bec101e3e7ebb97acf06d3778e14fc41473303b82dd9752e961a01cad647702802c584852c47d638536a553edbf8345af5fc2278b31c5c814cb6718bf5a699df45d998e9baf0f789e1a35010001	\\x1e9cf510c5efe1c381878a39cbd03a5f391922174050e1174ca1890d194337a4207302c9cf47c7cbb37bea1b78563e983c7eb083e5a6d91eef35b9cfd504010c	1663514183000000	1664118983000000	1727190983000000	1821798983000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
327	\\x11fff081ba4e53dd6c4bb0e11c27e6d97b010b2f569b4c7e3ed53c56b994359db0090d596bf43b0c526776c2b8a034be4e6f534155ade9f9d15c906bd63d7475	1	0	\\x000000010000000000800003efbc71af756691d17a8e2f87a2e137a39b34aaf15f5753be282e13c3eac65a918843f0c5bdcd06b4fa303a278d3371394cf47074cc1e33e5b95cbcce3f86236338745ad7c840c04a83fb709dc3d0fd46e1d4e3abd579c32ff2640917392530966d1fd740060d046fb6a776b35a84a4820e49079a9657251d00337e8c0f879fb7010001	\\x1eb7cf1bf85f74119c18f16a47539dd8d3a20df20a195195b50fabf6c937f48b039f729e7c2870c23e203b2f4b0dd5d9003294f043a17059da88030248887a00	1679835683000000	1680440483000000	1743512483000000	1838120483000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
328	\\x13935b478ee0b61044199a72a1f72c3163685d68be6535c496050339756256287d59c67327d6ab13177f3e5a7cec6eb5c7b3726cb32566fbb8f1484678afa288	1	0	\\x000000010000000000800003a99e5d64b24da941565c2e748d4e1bd0a631e9f1125950334d236a7fbce018df23c451f6dca29b0d950ac3a6c588545d53ec3eeaa6ba4e212707f056a0dd2e35d74bf1b5a4c4edb5f69ceaab44952b3d50be1b2be3bda7867b13cd2d823ad51bbe732e6d68413f55490f800b713865ded83a8fd023e3a8fee25d4e0a39bbd127010001	\\xc2a5984182228196f12b6c1ddc7a76af6fa7f40a3b808f2472c3720a3fe83d46b0b2b1d3db52e95f9b45b666d0e110c6b0b03346a39bcb4b06a738e4175f3d05	1683462683000000	1684067483000000	1747139483000000	1841747483000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
329	\\x14e7044045b67a0490071dcedfd9f1dddce45cab6ef7af5703ce268e6928d88da26deb867f4a6083722e92eaf2bdaa77ac2f6ffde8b595c3f73b35885fe90223	1	0	\\x000000010000000000800003bf1ec1c50280088004a7593ec92cd638bcb8afe5ca0dcbfb5f253e070ace857d3530219bff5b28770b76f86f6662de2230a4a72d2868b48e8622f3b5d138bcbdfcc6a4cc7c560fe1f6b709dbb8f644c8d8c07d55debacfb7ffc1c469111733b949ca099260f3e0ef54b22b9c11a65dc7b2602f8f4ba6f86c51760839f9c16235010001	\\xac0f752cb6bbaa552eed7badde7c29d6a3819c11ff359ab4aaf8bc8787e27e153702d290f32254cdc46eacaa8f04565b13a387bb971d1a59dd5c15eb8c940f08	1662909683000000	1663514483000000	1726586483000000	1821194483000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
330	\\x16cb70ce7c9313c855f03836d8126a990f9f0548efa2a6edc8124135c43e0a8010feab9728f3d8520dc199851ed1d241572532a28399ec78d63d78a0197a22e3	1	0	\\x000000010000000000800003d737bd4fd554cb5b7c5defe12390f2c2824d123fc403363188f54c62c40e194befde1cb709063e9101246bb8a0b02a7e582c6d8782069ff7660a543c3a4f2b78503a340c69076554867f6b2f97aadb445983e0844c5892ec20c3552bb95b204eaf54c57deb09cb8c54a7516f5b6235f666f34120c56f72ba87cb1062b049e931010001	\\x2402d43f8f7b0c560de601a2942e7358f06401e99f3b9f3d870853627dc90243a6601640f18df476e36646c2db4bbbb0df507204e84f452c0ee120a2caa55a06	1684067183000000	1684671983000000	1747743983000000	1842351983000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
331	\\x166f24b067862d02277a2085b17eb9760e11ef0e2457aabadc3b7f13dd8df489f75f8854cab60d2bcc994615b01af752fbd5c68bd8399e4c99f4134320f4de06	1	0	\\x000000010000000000800003aa7d9002cfd9a6451013435d30e99ea2f8593f7a636d464e771610b7373f1e9cec410f012cff5fc479ee7337dae155f42a97a22d54231ff5c21e3e60f101d307fb8a73a8c2805499388ef731c8ce43a4646c3483f9b7b6368218f5804224f5edea52a52e99037ff57492280186503c33d8c8a77c1b0b6ed00a2dfff97774efa5010001	\\xbba1c6f6e5084cc6d9d0ee1787fb4fa8a8aeb24daa5c00f5513c1e569adf50cef7b6df567ffe55ea74941e7d9c847b3222e84404521ded972d86647adced3f0a	1682858183000000	1683462983000000	1746534983000000	1841142983000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
332	\\x1c878939878350ed651452560f1046cee162b162f3c7408f4f404c623a8253da1133cf52f1cd2c6a0edbfac68c62f9c7c7ab5ab43b4ae8f3a776d47094c6a2df	1	0	\\x000000010000000000800003ab64ed7d4f9933fe8bb15f2d7b7e47efe9771290e5b292f250349b373e7fda8f1c5c876fe00b5da079f9cb8cbd1ff843a6ec306550405e2669426993fbe4b6ff1b95c04c968e74d4ba427c823d3b9e58a893dcd8ec4767393ef933b93302b575d6496bc26c5e4593cf86c5d38b9b4fe19c25544a5ca7de440e42785bb9529a37010001	\\x6c0a1ec044020c66c21891b3627ed3a8e71dbdb068809dce60571cd64f6e648c4da787c59e3a2b723dfde6f76ed9d38f0751f87efea63b66b766c5aba3eeae0b	1663514183000000	1664118983000000	1727190983000000	1821798983000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
333	\\x1de329b2d8564d83f7c8ef54cc3f7e07f17960511e73c2f6a1b47cf16dd292fa2c8e72523961f9085169731aa41823cecceea0f370bc55aee50dca66d2f2c79c	1	0	\\x000000010000000000800003ccc39cedecba1d9ed8d1452590b74a6b5437a7322bb25fae8c1f5e9440cec6644147aa1c622fb5272efff742ea1c72b4efbd98d8fc15dd58e93d428a9f17638390692e95a88c18637e62c86f16d9eb037bd331423c9cb4b33499abdfa09dc0e198d648eacc9cf18f50b15daba0f574486cc013dfbd457cb2c0e0853692b65763010001	\\x8f4153fa5c7292e4e0396b300e4bb203e24fe39d75dc4ca2010e68ee20f9710cb7b38629ca6cbefc21a8d9c084c506704ee7b829f83533c820265f65464e7e06	1678626683000000	1679231483000000	1742303483000000	1836911483000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
334	\\x23679d394caeee0adbe9ce0d8bb982a03b65c58e764cb5828613d74f9b479e6673d3ea118b78c087683c2fe591a9f185d2c658a4d823653fd7c00e91c7377e00	1	0	\\x000000010000000000800003bef4e0d836659f87ff9b25f18649a783256e9baa9b3812a4cc5988edd697da449ab8b5327452bd440df2d16dc5e64769ff60988cbab2d015871957ad0e304b0437f5ad0176d4b2064f14a5f073033b8f7feeb3f850e6a5f55acd293e1f98bb6094a49ebbe5b0c8c839d2791385838ae65242a1c7f177379fdabc182e644f05e9010001	\\x9b6944bc4c949f08134e5b8bcfb41840afb8071c1ec5a8bcccaf1f74faadf95d52c9f0c7c2516e6ebd87b0c98ddcb8f426ae2708930a070b4bd7f4542a4e8808	1690112183000000	1690716983000000	1753788983000000	1848396983000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
335	\\x252f2f020225b62e307b171f0e6e0c71b1661750ba289f37591b2f7d015eaf3920352c07c4dcfe039dcc41f448510ee0c6be1d9bff3f37f6cb8729bba19a1485	1	0	\\x000000010000000000800003ba076364d0fb9bb71e5b0deffea4875feafd2f99a79ac16fc25177aba6ff8de221a1acfc9c3f19b3e6d3a9f37619c921f93374b19cfc6c4663262e5977b7ec5dc0d3d0c854adc1ae75a88cb8b1c843aec7c4d234a0fb6db960477d031fde6faa7c16fba4e6195fb3382e67d4d873ef449625d225751d338388ed0d31a978005f010001	\\xfaed1588b8b54b425bbd3cea93b0d7f0007c3000737c50aec2105e0100ce67aeec84e43a710f2c1b23e716f8d53ac065f67bcc8ec62576b05a09ded59d01030c	1673186183000000	1673790983000000	1736862983000000	1831470983000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
336	\\x2f5bc3424c74e64327437e3edb500e418cbd7222d4a4a191950aa129b2a6f47dc8288a322ff7b7986cbacd33d81d0c42ebb2c1f8e69c45e7473d96ff710bba40	1	0	\\x000000010000000000800003d270e2533cc17e7e1c1cee781d134be17442f856c012d94225a3cd474d8e2ddae763ab6e7acd9389357eb5aa59ea01190ebae9bb66e1dd0d2b0211520e8a69e7367baa3bb5102b1f293d62ce2479bf177bddc0ec424df4d0a96dc56e5ec4ce3f028489671721371ce1d1bfadea20638d34c576f2a0a00b092e1806d754bfb0b9010001	\\xa941e9a78ba952e785d3441874e0d3fbe9f9a9c21b63b104491bd0780561374044fb336e882a7c762c3e894cdd37ba842dea840c2e95432c218b8d8fee9ce80e	1686485183000000	1687089983000000	1750161983000000	1844769983000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
337	\\x3147db68dd3a5e722d75db9d9cee026c19ff8acccf1529eeb918e24d0c86981e58e05d7ea81c746aac216fbdc8497ae10758fda7cbc34a745c488377d3b8da17	1	0	\\x000000010000000000800003bae4f97bb7109e548a19f342867acd7d50ad3763884247f63c7246d39ceec3efd63c71ab098ebf916c3f592e973ed6754218efff2081a545d5f9a9b9cc73112eb08bb5a08882dcfe7ec7bbe51be4816ed487690d97ebd95d65baabb317d45f9bfc1695abb286734a1ad8213fdffbde829c7d17ef4280bda4bae7fb17f5af0d2b010001	\\xfa34423f97da3ff41d2767634b08b302160944ba880d570488bf4faa39e42a6a0fe8fa742f44fdb6c07787a707df1b3973c317cadbd873538134e3e20c74460e	1664723183000000	1665327983000000	1728399983000000	1823007983000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
338	\\x3ab74d57e441115fda78356d9759221593aae2340d17b497b4d8aea3e1b594b18fc753873045f2575251dcd7d2fc88041c3b6eb594ba47082cadd9ae581a6d52	1	0	\\x000000010000000000800003c491fb5407464fe07772df72def6f0cf89862c46f891129f075d9f7d6f878978295a324aa8c4fb8d080a7ac32d5a5d65d17c3dfa923226b908bd0f7fbc3501ca370d19c94177d37c3b1ad90936d25fd0f077263dbe6640d64c55eed9ecae476a03d362dd93c6c8a377918e81dcc76dd9f36abb62ca04f3380bf49777d2c50671010001	\\xdd835091a481c4d2257c3b2ab481fa317bc301d11f6b4ba357167f2311682f63b9f34a8ef648136de7f31c8b5d2e0f2bb66eb3cdfbf010916ed3cf15d3d8960e	1690112183000000	1690716983000000	1753788983000000	1848396983000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
339	\\x3bafc6a1a091fb5a16318be15d679f7e431dbd046ecdb6d50156135ef373bce79ad652ef1bbdcf19984e371672156d3cb5d8fb5ae814d3c05a21c61213c16850	1	0	\\x000000010000000000800003b277e3b833edb5aeb1e867ba6845c5224f391d2e111860c257905b7c31a70552e1422a7991492ee62ff77f82d3848cdc31acddf4e60f8e9d5b478f30854a99fafe2888922096f135ac752ee8bed0391ea1c379ffe767c0f2b0f9f1b3171d1df23630008ad5c6dab1da3f01235f39b274f49fb09b20e5b318c7b2314ae75df2d9010001	\\x7686fcd1faf0588a8a56000fd81d7bbbf8839888fea5063ca67acbf2bb510320fe3fef9c69fa2f1711b5a7aeeb190b18158701463b76b4136a3e13e4edf04802	1680440183000000	1681044983000000	1744116983000000	1838724983000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
340	\\x3bc71e48a9be73cf5e89fb2e37168e321a15b8c25d7349793221a2454933dfe9c953d16c65399d102c226447e238cb061ee49fd0b38ac1830f0226e39deef4bd	1	0	\\x000000010000000000800003b2d982ebc815e2cd8638133d7cf91f148a24e8a9178fcf17e40ba28b1d6cd9c495fbed48769ad31e5c55ee1fc71cbe1e3160df2f8dd9c3ea2d7f5fa055c5c3ea973387e096aa4979472d43846c7691b1f125aecdd303095d9ae367853d61cb6b31dfd37999572a4d9b679c624dc468f6af542004d43edf2edfd7b6aaf7f5e071010001	\\x49fa253754584a6293936b96e455b4bd17ec4e31af5a2c75add367f4481849a4863940cf9c086760f8ae61a1363cb46df4ed8a669cfdcddca0f0a6a03112e106	1661096183000000	1661700983000000	1724772983000000	1819380983000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
341	\\x3b6b0fb8b0942cc6b4d04e81624ed24664191397ef5a4b19f612f066994cf758533fc70541a3db5937f8f6d9a0d35fdf2fb6d8fe01c1a5e9c91de97badf6bfc8	1	0	\\x000000010000000000800003c84f4f3a10585d380423b7f793d942bdcb6a8b5355ffbf8ca923f4085a8ef8b02873af713044f4e52c5b53243478d86245e96b419e9eda4560d6b8403e4d1f88becdcf2fd1a59c24b1a742202f4655756b7e86b470597195c1caf9616252b0aab67556f3640f5dff878a477832a027e6d33300819b19175e6fff185d1a5ad37b010001	\\xc38ba74bb80a2377fffa1c057c2cdefd60111996b5862d8172dda075a27e5f9f852899c349c5975050e2116bf3e4492d8d4e005e56728f28ea62dffb5bebb00e	1681649183000000	1682253983000000	1745325983000000	1839933983000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
342	\\x3ef7f6c19d9fa2b6947049b7e23addfb8a22f3a19917d70662b039330e9eca7fce98373f5842f254325243639d9d787e7491d44b727f6d0da38ca2b1039b6966	1	0	\\x000000010000000000800003be2be961c9286b84929e6f26c2862aaf71676d105082ee1d1909f8941184f9509d156eb60d7d20218a3496e476787301ab972da43c9a303c675f4da24300f9d7e48f6f474515e88db82fe7441958ee077618ff216ecd03416a02ed381de5a47485594aa87eea70dc02890dc5cd95a859f77031de1cb174e44c5f77f603b47129010001	\\xd3d4a75ff2c0e06c7654b69fcfd309cb2b228699f4f6e754477488efad988ff0e35e053691ca1037e7ed5149892be0b0e845d94e04739548a5c158c7e767ee04	1669559183000000	1670163983000000	1733235983000000	1827843983000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
343	\\x401b522894505f1aabb7b9f65710212d8ae43f655e8ce11ef442c469dcced3e3803a41669bef548d3fefc19c4b45979ff43e596ab573cb9b532573c40e673472	1	0	\\x000000010000000000800003a6f8ec97629d0f7d2a2db9fafdc45a12bbf574c80573624bfe3d3400f3b9ac8c22c348254c4b59c743171ab26fd9e52c98630c5cf84989577ea8449bf6e33be92cdfd96c0274f5c89618fd0502b01bfd09bae123608e92c984f93bca6569ec0e3e6d4296a479571cdf83411e2823a9eaf96c9216bfeb25864c4fbe7a913bfdcb010001	\\x4f78a489157aa7a63c1e7cf6ba70ea2040bfc0f81b6ee41fc99e984fba6cb55a080c00881099baeddf7d64c90a43be6517f07d7cd6344f25a8c3644018b0280d	1666536683000000	1667141483000000	1730213483000000	1824821483000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
344	\\x40ff1f637a272f1e8b5b73a5865b1065baf68cdce37cc79e89f01f1d69801757d23ec0ee3d416a6b007c031f24223f43cfb0e4bcfbdd1ffcd4272983911fdfee	1	0	\\x000000010000000000800003bc4b74363f0db8f63655dccca83336627ea699a11dcca2b0770eddeb6f4236f9270e9dc3de3fc1601149cde9bc264db0ee7f00cf80839f8a028d8696caf0dc7bfaa803367570b43d95ae9f5301261eda1c37c98262a9ec0613500a7f835c63a22cdf301103919e6152705cb10ab614c7c40e63f06465bafb2967eca50ccaddeb010001	\\x61f88beb8cbda18504ea67bd1c618d98cd89935bc32714b8b1875ffcfdde63b9c2b8dfbaf59e3efbf89a92ce795f7e0946e21866b9f6df2d0be5d06b4e3f1e09	1673186183000000	1673790983000000	1736862983000000	1831470983000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
345	\\x417350762ec9c4ba0b0e6aea28d48af06b6c416e74f75879fedf76e1d84c26f23743a4ad7b99ecf954bd75c76049325949664275769dfb4af87e75ba03de2480	1	0	\\x000000010000000000800003b99a793d5e3a7cf78bcab24865a5af7714d812e6b1aec2972d6f613aa0ce3a161c7fcf614d9f7d7817936335c3912d6a0cf7c2569ed5150dd7807b1b667868a7e00b1473f8181e5f08e8e66f0b51392a50f2cb053f4313c211088470a9453d15bad418b5993f50c682536bd185fa20aa8ea88c48f9f04d60243f6cfd74667f5b010001	\\x7434829fe78ec7b966b419cae550fad1553c5ebc880b08675a7c0a2c7c22beccf47d5087450a6ef3031c85f8cfaaad7df824194f97f248ab3114c41a90bfa50f	1665327683000000	1665932483000000	1729004483000000	1823612483000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
346	\\x45bf87d0d995b4f1d6ad7d0946f4ecb080b4f26c8802b66ea83369b87dcceb69d59987348ceacc4a06db427f983d52222aaea65822d057078e62a63dce7c8878	1	0	\\x000000010000000000800003cc84fd49bf783452bf7052796366e5ce853b5bd898d5f9c05b126dd8543f9ec80e221cbedbaef6e8998ce2e92c9bdeeaa87f875e4bdb32eba956ea9abb4157b1406f998928f9dba54b690022d615004fc22e2ef5960c84723b654a88e820b2459b1e73f6e56cc937cc26a48d3bb2ee0762223feaf36f4b1980d99be726f8f555010001	\\xad91de417b579ae49506f32c2b4041506c83735bf9f427407096b98ef65a0d2ca9511528a211c235c258f6548d61cc1d6d480b4459aea35bc248d43016f3ea05	1675604183000000	1676208983000000	1739280983000000	1833888983000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
347	\\x46d37d3dd9d78bedb65bbf4b9d3ece146ffa02dca1bbc5b7d24464e6a1c305ab369ab13690a85ebf702d8800d0d495243e840841b579c49eead5ccd33e453f64	1	0	\\x000000010000000000800003ac5c4ee63b2d0c381b3b15ed4f6def0b0d9b143b2c7eb5c9fdad17e0bb1c6ab7f7eeaab0484ba80688b9cf05f66eeaf4fa5e16a3d7f579bcbd0e29d413cad0d104c53f1021611a051175d6ac5048199581af2f4bf3b6cc2d4007f89fe6b56ed129fa1709cd753fbd08a49864742332fea106f6a0156d570586be2327da16718f010001	\\x4d3db497829482ae5706d385ee598550000f3ac7ac63d0c82e38392320ee68dfe24e23ef87ac4edba85160cddb8c9a6cf273e0330df06be38a1e2f239d1a2f0e	1682858183000000	1683462983000000	1746534983000000	1841142983000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
348	\\x48d311225bf03dcaa18297a0093ed008df7bdf08874d1216984cedae65e31ea87052a472f618b0e2e21cd0a9c81927a9aa910028ecf88541a9dcc3edec0d97dd	1	0	\\x000000010000000000800003b3a7e97e906778d6405e13c90ffa9b9e73301c168f4035f75e45c77b0b5017409239fbd722e05321155a386de9d10b9758708bb5ba1131bb46118b5cb5f0aed038bd2e0852bc28c9fac2366f059d077e4db8fc0c8ebcc10ac0ce60fbf0da0687827490880a9988b27e4b39242d913c2e0a7a2fd7ca3fe214483e351c0b3bd3b9010001	\\x422956537d8957b54aa83bc1a88b8ed49e52b8096b7ef82318e23771264761c1aa746e761901473e68b8d5d102d73a2299ea5970652eddebde68cf0db3168608	1688903183000000	1689507983000000	1752579983000000	1847187983000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
349	\\x4b2fe5cff2d50f59e0709117cd271e7bf36e752a2eddc66d30ebb725b955e200010e8930276e2171b23d6aa662be935d5ea8e9df943fa01be07a169a683c5e32	1	0	\\x000000010000000000800003b6b09b386025194cc71184d247de24ad3848b9804f6ff37b220751901aaa5466b59f96e96bbf55a7dc604973a53e361ffe3102ecea38f645465bf955f2edaa92508edbf8087b282fa2a23174f64be7da380ab33dfb71ea94402ef9daff0ea9a94e43f34b4cb7b814b2dc33f9275a1e00969ad44392010823e380097b65c134f5010001	\\xecdc23d26fa284a83751137a02bc0968c148f5f5bd30c65bb6a430da706cbfeedaad63f09314fc46554cb338721cc09822dc760d93b85f904d591bca2e2e6c0d	1681044683000000	1681649483000000	1744721483000000	1839329483000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
350	\\x4be327c81ba3df3ad23e2ef5724dea5c747dac3d1dc7d5e0e077f8425592b8071f3d0c0d4c9aef791f8202ee02940ea8b5f43fcca11005d9146d0bafa48682aa	1	0	\\x000000010000000000800003be38a0f55a0a32f9be613973386adc16078563dd650378ddc3bf51211a85ffe5564878414ce08d5d97d3f4986853dbbc469de88200b18a13fa2d601a3749890a2532086415be88d9d6bc673bfbc6dfdbb7b83d00190631dacdb0a7cbd8bbf3ff3b76f245a40388a3298b5fd0695412ed5f65251a3ebf120b70610b45d374a6cd010001	\\xa1a68619e0ef36116ea13b7ca3c14eca26d59e29b736a74310612de0c0e358fa6ba9f74b2db3b28d605d4cd0bbfbf3ef73982e3a420c1caca3529a8629213002	1674999683000000	1675604483000000	1738676483000000	1833284483000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
351	\\x4fb7d1efd167ce2d5d370b319d0651fbc5e6ea72b8b4f60a6291d0bd01e78eafe0024b62b5599f86159459b9271395b02d82697bc159b61a79833e02c8831200	1	0	\\x000000010000000000800003cec7807daedf63ff7bb788ba5ffd025e2b7b0c1e718afa865873397246c0e788f77c07867c793852c49ac54f256606dd42f821e8bcd4eb30006ab6e348c47fde34a0b539db9d710b23205d16b80eedac55500ca8c00d1d3a70f98cf756c3d15e9b3b8bbe83c901df60cb32322f11703141e8889218fcbe702d3644efe2930671010001	\\xa1e47e426ae0ed14db56b13c74302381a3f030f61c3457ebef6979dc31d32e7732df418b72c115809a659d215e6b3ba8d2239dbef345e99c732c1e8abb098e0d	1679231183000000	1679835983000000	1742907983000000	1837515983000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
352	\\x545fb8333dd5aeef23f93d0d5fc8d4ea8a58d3f0df9406e0215bcb077a80dca7fcaff6675f59ab5523a18eea7890af3337e8e9bd41201b09b261ad27bb56252a	1	0	\\x0000000100000000008000039997601b3ea653f0bce915841e3a2a545aab9efd27467dea897364f34c51e456fd6e2288ee3771de084473e40f1f1fc8a9e1e96c4fc368e701a72d2e21fcceabdb99eaff53b3a27014e67de4430be68b02aaac9c4847fb056e5f909a9cd2704984055ade7ef3e8744acb73a6d780ee7118f3ee7e87528ec6bccfe3bee41ae82d010001	\\x3bf302081fcb81694163647c19adf540dba1a0ec9ead2bd68534f345b564f1b4056c22b163743c12b988495c35c50b18bc3f7dadc9b8f0e7ccec7a5c0eb7f506	1660491683000000	1661096483000000	1724168483000000	1818776483000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
353	\\x5547f9dcf60d4b98bb258250b1aea396fda85cd4ac1f436fdfe4542101350c8c852113e8795be1bfcff5f90b4c2e18371fd1f1c5d3b548814c925b1bea67702f	1	0	\\x000000010000000000800003d7d75537abcf24cc98e03003bacae0e9b56146b5e19d484a7d66fcc943ec385c30148856c555cf6d109baf7decc756216d33650c990f5dbeea11c986e086f74285e8227f19fa71fa3fc7dd0507fb804f6d57954601c1ff06873b3ba9ffc23797f377d37cbf2b927bde439ffee26c2aca2b192bf202450b4a35e64f170d634cb5010001	\\x96c7d985a822d9106c8c1ddd01077e6c2b0c090517f57351a27ddcaa3ff7ebebaea0a4a0f3d5efb7446e34f538f6e8a52a72af9dd1bd1fac42c27c37ea4e5009	1670163683000000	1670768483000000	1733840483000000	1828448483000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
354	\\x55cf67f455502f46b5b73f34a0152541e66191948c32707324a1b4f2de615fe9af00f3296daa29554cccaa5dbd5aea7024e9f0e56fe0c6f924d5fce619e671af	1	0	\\x000000010000000000800003beb2778388528c5d7a8c5b7761b6f41e44afef8d4f161ca70a6ea56af5e841b9c50264b891af5f3087fee4a1032908a5122a8f3f9ebc90a552e45bceb81635563cd7b45d59bdbdcd546dfe231af071012e49e9fc2a8d8b1867349ed96077a1eba62b453efdb905d0e66fc17705e51999839b1d68f461a09f2adbe169575aa335010001	\\x1b4450a71bcf6fc782f457fd884cd5c5199af7694eaae2cea2dd85ee4d9824cc519d6c71dc36ff9c31ccea60df7ff575510b1b2b7be69f281ea446c582072b0e	1681044683000000	1681649483000000	1744721483000000	1839329483000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
355	\\x562ffaaee46a7773e929620a75decb8386a962d337df1a540b830a549ddea762d7b6cbc23eabfcbd2c2eb310420fd5f0fad935ef45eed885c38cf3958dfc8b40	1	0	\\x000000010000000000800003ceade4140a132560fcd7063a13cd5190395228501e83ef6f1240511dd96c4a39638dae1c57f9e37bf0c509979abec4faf5c1db465b686619d47b076340695d62d441207de49b3eb9767663cc319439875fbea88ad81e1b6fda1558a4e248362b01fe4fd4c6686bac1a8e91f98d1be90213e6e73c2b55a3161806ca3b48c8f5ef010001	\\x0b7bc0bcf1b2f6d5409adf5116c13c4f9bc37e8cd914ef107b58cfc373d848b750ad0d072653d03057cd91ce78371a831433344c68441a53c8352d8f6ebc9f04	1679835683000000	1680440483000000	1743512483000000	1838120483000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
356	\\x57effa22563f2805fb37ac16459ddd5b976b5ef9ae92b1c32ab75d8ec217f2a9d4bdbd47da6deef4218f84f105e3c164564276e88dcf06e63616d7c4105faa22	1	0	\\x000000010000000000800003b9be1ca3ec073f514e850d8d43011ca258b67dee9e24cce8a983b5baa56d0d3afe685631631be1d23dfcf90d2e032ca8c95961aa787e97e07c75cc5e08505ebfb1b8141572c964a3cd895a5f87de37f864b18c8ebb733a8450eb745e16800f962102fa695589f42bab94696a1281c037bd123bdbf2891cfecd4933cf01f06e93010001	\\x2a54be9eff3c7ddb6d971543ab06e344ff9e3254a99367291f04ad0e234dcbd633a43cb3d66e3fb938102bfebb7adb646bbe4a179367bf4f7e6f84d49db3500b	1673186183000000	1673790983000000	1736862983000000	1831470983000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
357	\\x5bab4fe1d054cece351042ca82718349afaa4710cb58e527509493a0ef9ff6e08ed594975bd8f5579b9ac6978e9e5358fd35f8719f6f28ec1ee0025847a070db	1	0	\\x000000010000000000800003eafc853a7c2cd68e6e5f3c0a9f3fe951cfce0038cd78dc68cf8ddad75ce44c8cd13281d5335c40f37037b63c6dbdce21f471b2fc753c88e788fd75f2e06c325f08324558bb2462ce1aa8bc7e27a545bcfff8c4d6a55ab8bba57b8bbcb46044ece7144f1ce07d371cde87c685382c47855a7cd3d97d6f3d8f7afd66994eb16c1f010001	\\xc6764c8cefbc4ed3dcf8a1f3dc8a205679f0cbbcc01029590b5d0d9b9771b1416f4c18e96d3661f62cb6b349ab542fdd52f804049ab60a076777c97a42698503	1682253683000000	1682858483000000	1745930483000000	1840538483000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
358	\\x5cd3d038bcade79cb3234439fc57a302a8bc3244d9120b201f709c6a130cf730bfff7dc7a5c9fab55f5e02168a332a15d31ff1a0ecbbceaa7004ae296e9b7d0e	1	0	\\x000000010000000000800003c40bf4638e8dbbf16526b618f7bee8b00cba3ed90188e2347f3980fff9e45da350bdafa2f6a5826f04ddd35726fc3f8b77a8904ce1d3c90010a736047f595dea2f4379b257edf5adba73f040648da3c6509f780dd8c84df048e27fd20a206af0105be65f8857b30c3598e416baedaaeac301896c71b63d5fd75e4cbda03c67f7010001	\\x5809c04a8ceb5cc907e9c54b9bc881b0258d3c934ad9e139902f3acca54d0839badbfbe88b514084b2994196d8106e9a744eb3ba9cd414c0077583d7bfa3ee04	1676208683000000	1676813483000000	1739885483000000	1834493483000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
359	\\x5dd37d939510d93fd2109a77b080a5b3f1ec6b511c3041bd9754a0ec942e19e759d2bd112c16b9e7b8c888d59c0238f2c1d1763186ea8e1230b03cf77cbd2910	1	0	\\x000000010000000000800003e45840a8ba980e9180b3f829d41fdf996b478021281c0dc16fa11a91a7d979abe581b892e5c9ce31da21325120d032ec4ddbb903955e9dc51128b6a938dad809b1586ccd130a373ae0a4e585030d00780cdc9b35d444124181a299f815711b005ee1e3c1c9ea13298ece8f02b1e26680ef76d84043fdafecdd548076ab1280f5010001	\\x4d8802cc51e78ab55c3b66fb377f62544f8835f946474af1d10c9fca116b05bba49af9c1eca991a797c1ea4eacd4c077d8b744677ab4157ebf790c4ac78b9505	1664118683000000	1664723483000000	1727795483000000	1822403483000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
360	\\x5d735d1f4a39ecbae49123bf2a96494dc51a9618fbf628cf90a66756552b0c0d1bf1ccabe731e019241786b2168dfc95e48174b31fcc7aed85177bef184c821b	1	0	\\x0000000100000000008000039a1c5215b9b8f427a374bf21c2bc71b5ad8eca353ba854d7cf44f9e658927e3362f36645e191dcb8c1db19166bfa23158f16cc117d681325ccd330fa33bb442508ba2316857bc340000c94fbf83bddc0cf2f9ed280a430c6dbdc148a7666b5aa27bcc1c369d0b6ff24aa2c99807f2472da5eca126f75c801a8eb95822f2e9dbf010001	\\x6607cb4f1eaa741b2bf9648c87db1f143b8bf6e1d80735d71d67d0c28a4c2d8956fdf08b4292d69c692a1dd604b8845ecea4a30bb9a08f37ec9fc53479944a01	1665932183000000	1666536983000000	1729608983000000	1824216983000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
361	\\x5e8fb1462221a576d05c0016e2bb15765edfeff388d6c9438ce604545cd9e2507fea83d499e710aab4d8f4aabaf3f0af2245931afcaf8a7127828ce783de6687	1	0	\\x000000010000000000800003c3befc423fc7e7fca6f154dc0f3971a45fcee08d65e784ec5cb72038cd832392e33dfb066686b22c56b283ea152f4cedabede72d46833698f0384717a7a1e4c7f42857dd4937f7ecfd6a55565ea3dc73be2913a047070252e6aaaa3ef7cdd3f991909e2c05fc7d70ba0070d6c2977871209bd118240ec38f8d1eed6137ef8ceb010001	\\xba5704cdb7a061c9b57844feb62410f8b673a272edc96f4ecc3a8ed7e7e4e09bbb44043218846c079dc3d247fbba4c0f80613a3a5bf3b904749b83479a08e70f	1675604183000000	1676208983000000	1739280983000000	1833888983000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
362	\\x5ef79f25c55f250b2030d6b84e9ada321f3139be273f676a48828088c18f7cb83796d523d8c551b8768abb6b8a0e6a1bfb882d6392f282c060f02a0affc49a6b	1	0	\\x000000010000000000800003e01502570b897cd1c1593b95734acdfd4bd4579d503c9430c4ceb41918b4ebe5fa721126b92b18bbb25de91b4a4b7df9a34a1d2db2091661c68b2dd8a2c9f5498479d5e1463ef3a3c59e3189fe9db3dc2bdfab184d777383d0ec271a11f75def3ca4262f5009137997e387837a00f847cc0307cfcc3c0bdcea0f26722155f321010001	\\x50e4ac16ff16b91f954a6b7bd3bf8590b294a549d7b149c5f1622cf05f027971b6cbcbfd3fe9482ccf357bc283b8277b8942e22c504ca892384c76a6d241dc07	1675604183000000	1676208983000000	1739280983000000	1833888983000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
363	\\x5fe73f8ae5844fce17821ee1f5c5e99650eb37236eb79f559e9ec05b5a3efad49dc492019701d0158b9451d3f9df11e1b0e3abe1e6f0bf865c93cb25c707eeb1	1	0	\\x000000010000000000800003db2bc678cc94bbce84933833d890494701860eabaebd050a4fbe24cd1fa135f237bc363d0a77dfafd89a134aff43b8c7fa06e61193d849939f52eb3e09078463b4b8f23836bfe323e77499f007ac9f782a9aec36288e7ca725f4c30cbc12fe201ba7de9c40ee79a70da44bf330efcd1e164c97db98f0188570090eb1adf8106b010001	\\xcba39a073dd3630e0f1d831aab6a3a6ea81096a7c457773fc49b23767a6c732d6b52045039a78bc3bbe573447c7144861da5f9656f67bd1ea22a131b92820600	1664723183000000	1665327983000000	1728399983000000	1823007983000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
364	\\x60731a0f5432a562f6214c985a53abc5019a06e0e7802d6f578df761b954b47f8e7698bb87e5e11f0b0c572af5675dabed7ac3700d7df52e3a8124a8885d2ba1	1	0	\\x000000010000000000800003e85f6b4be122785bbc49d314e6e28696f77b4b54d86855a397fb48ff0b7d666cd77b24f56aff5c5804741ff64942c05e6338cb4e02eb31fd286004a5c1f318c0504fe5e8fee985ef9da0061f7584d0eea833122171c03c6385d9e2d51d3bcfb79ff7b1506a5b15315534e7de67c1ff67c591373cb1d954e212c8e7a6c32e4af7010001	\\xd57fa74693cc0c245f2ae90267af61c81b004b23684aaf36058969e603619e21c07d39e0ba02ccfd37d79a4c7b4ac7d67e23f673d82b2fa4a667d44cc87e7107	1674395183000000	1674999983000000	1738071983000000	1832679983000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
365	\\x640fb18ad2000c93904e8c9a1d3e92169cd18e5ba8e5ca5b13d839d770e0b33071a8d875367374232ce2fb8cf31e67bbc27bb3510a85fcf2fb21175f3c67f2a5	1	0	\\x000000010000000000800003b8d6118982f648daef9d03346aa8cb5eddd37672b86ce7bee671a774f71412ce89dc86cb95c5ea2edd501e25a47f30d2537f9f349befa7cc877b1a7144a8dee7db44e8b355909c3a1d0a6b90e988e01a11e55479abfe618a688daeb40dcc6ddfbfe931902ad4309bbb7dd3a3cd4d3115a2dc8f6457a5c6e7663f91fa4818e913010001	\\x03970fc08db568ca635f0f198347ccbc239e23c7c1b2cb9abfc116367e873a9ec7f0670405485bfc7f71af0be3df467ca4beca99cc971bf7ebf934d363898009	1687089683000000	1687694483000000	1750766483000000	1845374483000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
366	\\x66b7beab79df90009e148c7e129aa05861e11fa9eabed5178611c263ab85be8aac3c4668f4ca5d8faf4d3f4082634687f025745a54dac1ee5ee800119d4f3a8a	1	0	\\x000000010000000000800003b54d109b353efa18c72f31efeaae4765b8d73876783e09d2b137e9ec1badd7c0ed67bf60e2707b32b5f071fa017e82a0406baa6e0915d29a984ad277b0123ce6867b5cb0f0969a6032331ed283b688f55d3b8aa31583e67b8ce49204a39dfed7abed75afc4ee6acf905e49ecf757561355ecc880b88cc6650ccfb4a82a9c20f7010001	\\x7495ecc07e45f89c21296405823fdf98c45f1c6a4af7a5ab121f2871732041cbeae18b9bd0a4a9311aae0e0a857d126c35574165f1cceb19a479665c034dd10d	1678022183000000	1678626983000000	1741698983000000	1836306983000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
367	\\x661f077bcaac76033d92a574643bed3836ded8e71edba426515d2dec7c5e113b06b34d61adedd5f374d90b3f4a3d89affaab3fbb01e8b4ee03e0b4679f9c5668	1	0	\\x000000010000000000800003bb4763ff6e95d63765e428414e6a4b6a800b1574d8ca89dd1676ad3979d2a8ec92719b2407a09c5f4ab93b4d0651a9822f287f9be747d24e66cc05046cd11026be0d3f746043f3a13243149dd76d6f755c5e7d077997a0d4ffc7091bbdee43ddc35552a13970b5b130b7a9d4e1a5df0979e68ac23dc9b69aa3312a840dd340d9010001	\\xbe89047ec770db89c7adf4fd78356f197d12208884adbbd98c813a2c178d138cc1928b68763eebf4c585073dbc399210b26ac2b8476dd505a58b9416351eab00	1680440183000000	1681044983000000	1744116983000000	1838724983000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
368	\\x6fdb8e4b311d8ddac183bcbd00df3e35eb04b01136e213a79767effd6c227acf746507897a1a4a6ea5ec480f021b5462a0b1dac76828180495e76f535ae3ed94	1	0	\\x000000010000000000800003c12b5e6d8f082cbcb19fba29ac49d7201ab7ef20cbecb42965b5ac6b58a959decdfb241ed6b7c7a2b8eb30a8a5a253b413f4f0cebe761689570c597d67f697a357a53f2296c2fd97ce6c7c8fcc223e5dbafe445ad8ec11e83cd996e6f46783b258a008a542302b889dc9cd027f8018203ee75cac3371dd6cdb3b8ea9cc02b44b010001	\\xd9febf9619457e375475d0e397eca5f019d6057d01d3f5805edba52d1e213830d791e55083486de10d22ddfeace66f41996b58ad67e334713f25d5a0e8283501	1661700683000000	1662305483000000	1725377483000000	1819985483000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
369	\\x7437fca5ea5e77d08390844e2cb15b109c0df01b199ee46b4bd02b66e6c5fc348285823aa1445b0e318f6f445b52300af929744bdcd9d1580de53c7602a12397	1	0	\\x000000010000000000800003c35ed5bb403dc60121f6fb79c55ec58d1c1e8542cae4895b77c029db92da337a3516f12fcdaaaede0efefcc007408a570af727c69bb30944f930e0eafda87064f921f278c7ae9e20356a0954445d79098725fc1bb153808f51525b8cd5dc64093866cb00a470807cdf4e55f130f19cc6fb8415d5f187c364da18e50bbb31e155010001	\\xb195f5b95d11ed629fbea6e6717efdcfdceb475c32a370400726b03df110d888bac770dce10abdc5c9b0f629e84dd9dddf596432c209bf3b26fb6d3c8dc5480d	1666536683000000	1667141483000000	1730213483000000	1824821483000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
370	\\x752b49f5b60157416c6a7dda3c8b49fcc07346b6151dd23a6a9d481feea9879ff7a412c2bb3de6469aa99f51ac4a27e27b17d522e4757435fa4aed0d8d76dd34	1	0	\\x000000010000000000800003b602b79023a30ae78d2ab9faaa4008e383469d47700566a331d80360977daf33012cc0c5990586bf96fb013eb77f10dc0859d4f31a8508c9eedf58b2939a9cc028058dde00031d6e55b4d10663a08403d30f2c7bf4319356144940643791fb27ce5b58b5d74f7707a7c4f24d2a4f82c4428094256a6e73ad76797a4fcd203eb1010001	\\xdfecf437499256dde09838f9336db327ec736e64809d13ca91d76aa2599e165f0af66e7168f930dd9bd7b506a2e47f60c26d2a5fc9a9d43fbcd185d5ebcdf50f	1667141183000000	1667745983000000	1730817983000000	1825425983000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
371	\\x756f2504678616fe17fad620c63acc92e3436e7c4900925476946d3095ea9453381167e586ebe6231dea26a9ca1eb976df2d1bc2e474431889ceeb6a87941def	1	0	\\x000000010000000000800003dd76075e952642c201f823a400f0b4c9b31ece5f03f9a066325813e729bcfae181229224fde486a90e7f5e36dffb732340dbfaf4dd96bff8a0227e6efaaeae59ca410762cfd16c66f3d4a63c8e52e5ba1567027dd9ef9ffe99e214aa18fa97759d1901888e4a4f954ae2d8af4ccb98d593a16a1b10e9810bb75a62d004d2a691010001	\\x9b0830b2d3bcfa062e76fd028ba2c11edde1196104591a3d654de41dc44e0ad95b9015d16dab644b6afb5c9905e3ea84ba11b057ed3ff57171ed111dc677fd0a	1682253683000000	1682858483000000	1745930483000000	1840538483000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
372	\\x7ae38be5c8aa49d402060979b0aa48f389d8c6da3d02911f17d890ebce999eac5733f2a6a7616c51380b395acac6026beb1cf4dd08bb9219f7f97c31cbc72daf	1	0	\\x000000010000000000800003d9ed9f4d5b0d89bb20403195e9a508e4ac91ca11110e88e897e42f6eb29f566c4815a4403af02b32bfce18dfa8c96aa18eef5af0756dae96e4269c222516002f3b4b4d6197e393fb28a1f688fbc669c9539c2c7884ea32d6d9b9b4a9eff44344c9c53cc8b35c54b696a01ee94768bc19846b3203f064f57e2d508c8d96da79c9010001	\\xa5711e809080c77c31ee781fd1cd1b5b818b3816ad3cb4350c149102f13cbf2ad348f4d5b430bc8a456ace7726aa30fbe1cb6de74b48e63c3c0e153ae3bfe204	1660491683000000	1661096483000000	1724168483000000	1818776483000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
373	\\x7ae3918088331fa05149ec2a62412219e9346e3464ab7c3b681d179a996c951009a569a0b2b9d48413082d7074ed170d6b2d27cb6a0b366f6afed164dacae138	1	0	\\x000000010000000000800003d98ad3299a319c49df9d5553ec8b74927ee3352de157853f27ceff5f9512c9be8bde5c53e901fe93c776e2c56ab36c040d4397cfeb6e1361a869d9a6eec369c22b3cf1a62cf8c75705eb712871da7f898f8e5e79fbf4bac6fab587bde4a50f115da8c1fc67c5d163cd7cf29c9df6f0c4e1a23100d39352fa6de41d0f41bd76b5010001	\\x7670974e8bcd9b7d6e6c8d6006486110a185848515f2a77d74c2a1c6d51082aaae6c80ae38adcc261be73637cde0942faf0ad72244572e85023b7f614cf16405	1687089683000000	1687694483000000	1750766483000000	1845374483000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
374	\\x7ab38d7a65c3a94ed63d84bc972af56e7cb1c2db87a7bf27a5ad0f68b6f576fc9ca0896079f00eeb4c3ca5286428564e803e62df8bde2ade39ba12ea81d00eb7	1	0	\\x000000010000000000800003c6730447ce13e6529dff07f3074e02e73de80241509cf54e6609730599775ed898663f50197b49e36c45881a7b3fea8dc18c841aa1d803a02f0655b0f3fce428284c13211a2ff54430ee400aa79cd1e0cb62e9b1b416c9017e01e90313f96f084efc5369883b0ad2b1f66dc2a786eee26a5fc2cce299204d46bd6773e4e4d377010001	\\x12c62aac8be54c4e3af67de254a145035ccdeacb6c0cf47379b0f6d355bfaf55eb8259c3988c16eff43ae7f69f33248461a7330ba171903dcb0131a259ca1903	1672581683000000	1673186483000000	1736258483000000	1830866483000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
375	\\x7bb708a947d8ddb5352c97359857532d866e0d29c16e6e19203f091f40a237054ab4bb64800f110521cc6fcf873ddd6a5811479415c8b50c20f79834d12890c7	1	0	\\x000000010000000000800003e6d7d64cff326bc2a2752c107fef85c3f6ce4b4cfa05dd4265bc481697aa0de0a9ee2e292f9d9839b113348002324b3c87dfacd335359f5ae9f707ac65b710c3976fff813ba61f822b770f23064d7c0ac64b58c489cd9fc154c6b3661e74d3a17abd5fe2fe43cfa95e773862865e972171de02f9cdf2abe228718fd5c649f61f010001	\\x525d9b6a17cce54843a6b192e13e673afa29278c8c5d68f37858b200f48a0d0ed8c3c115de5156941cae16ab04ab6e574295536bf74a3c4e4341fb28dec52506	1678626683000000	1679231483000000	1742303483000000	1836911483000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
376	\\x7b73ee661855bc570f70c7cdffca030c4c56e8e504ef7dba7a6b8bd59446d4bbb5258340822380bcc5a91f029512c2b0fc422593c9b31b000e674a64f72a97d7	1	0	\\x000000010000000000800003f32484711e722a4cb2ae71ed6593c48c11eeaa146f903017955d18ce8ff26070e4bbf139b25e447f927c650fd89d7e365d52ee4a94839fc547e1d0b83ea01dd338f76394004ead8408c4d35681a7c1cb784bcbc40e3f2596b07c4c11973bd60c2ca76176401e0770683ab0cb93f07811e6f6a515315ede080cbe628628ece039010001	\\x55f9afbefc098d5f2928c368cef087ebf51e824791cbfae16dc7317fef33a6b52fbb795ceb8035ca52ba80067309f5868c4028c7d542a91ad05d1073b90c200b	1666536683000000	1667141483000000	1730213483000000	1824821483000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
377	\\x7ce39f2a589452f2bd727038de7b282e25fe5f16b575eacfe9da947b1cfec919c5a3d2f5aba98de7612ff9ef7c9282b5d705cd4d9988b6f4c82e295ff196d26f	1	0	\\x000000010000000000800003d9da4f3636c078798cff9b7f35ca19c22147ed322f7c85505ad1fa4bdf0567481bcf5e701999bf0eff774910ec117896ba63e1c7f6d7e533a8b7b7338a95c8a4ade843b639984214afa05c233d3e56894d4ccd4f564d284853e5e456a8d8ceb4609e98a12be5e2426809135277729abd40381e4f8a59ff75e7d92dd44b0ce63f010001	\\x1d617bf91a2443311ecb4a9f9380423cbdf9cc71addf4fd2659c55ef7a317218ac4ffdd2da784090d150f51853750456c082e35c9fd45fb183aeb976d844a003	1685276183000000	1685880983000000	1748952983000000	1843560983000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
378	\\x7e73d9afaddf2d285a32d881b1096872cc1e76ebd4fa21b68e25e150212f34d3f25717765a2760432f90b2fdfad4a065489acc20c81d33d452a2e5ea8f5c5581	1	0	\\x000000010000000000800003bb3cf432305e961de8107b1702a67ecd5d4fd12d84c4d0d98f28dfcea7c7313ac33b1655896c19f8d1af5df64c23668385592fe65f8f0fb34da639d400e75395ad135d660aaace348d1c3655c083a4bcb61ebe5dacb3da94d508e696370e5b21cb0f6a387397d43890291c120bdd2d10ea9b4ed16fd85c39410f4e930a9cf0a5010001	\\x87df073cf96e396e2c933ffe3a52de7c4149c6884f33544148db98450b393e4c135e371bd56405e7811e7e266cce1c0dfd738a9bf853b250f2d81d63ff147b0f	1664723183000000	1665327983000000	1728399983000000	1823007983000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
379	\\x8d97d6d8c514f42485ecc5d24323118a051aa5e1a6bc1bf1bd18853d07fba3f860886ef23e74b3e8788d72cf318796663c1927c51107638a2e6524f90a71db40	1	0	\\x000000010000000000800003b3cf0499babec3c1db32c17e4a5058d355cdbd183ffffa4e2063d9a0bd5ba3470e15b91f30543d305b475c288295a551f2d50b9f8d0a2c6f1fc0bc908b24516c2d3940ce9aceb6710e3bff05104df857f141ef086cd1f188e827f404efc0842a3e0bd44db65637a9f5ba3859665c2882d2cf599fabbc339f31547bf12a262e13010001	\\xad2097f4bf6c57aac56c2c794de98f3db30f5e46d5f214a3f58747447d7c13bcca1f5edbfc9b8d17f908784fdb0e3f6b9bca7ec0471a14faf8a8a3aa9591f802	1678022183000000	1678626983000000	1741698983000000	1836306983000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
380	\\x8fe7054c0ac3e721b1bce520cb463856d9d2fb29b85afbd211582b0ac74b04e62f99404a7cc29169a7ccbb0d8c372ec85a630aa8ad98368b0ca8ce071aea43ec	1	0	\\x0000000100000000008000039c4d76bf8db30208fc6b6e4a6aaf29b2a6c55125142588499301380f2c8cf4241d7f2263f579d7a3caeb7d95a6e6a0d8093d92af5bfd9add91bb5e22d72d6cdee7ba5b58791d3440d0fff56a64b902eeeae094cdfa3b36d509e2b073ca37a082b8ae9bb825a710ed9c37c57647641dd7e845586908f0127b1d9323c519210d17010001	\\xfabec18341b5732c955be8cd1a4d66071244c142d13d09b2212a3f36134c1963e9039155198dc356a007b49807116f572df756534783d825dfbd790db2cb370a	1661096183000000	1661700983000000	1724772983000000	1819380983000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
381	\\x90a3527bd56773cafbe1aaece5046f18cc2f176d3ad32b5dd0f8d7a819e25e5d5582f660db76add8cca91b240f34334583eb26652c3ba13822a18c38c3cf3631	1	0	\\x000000010000000000800003c2743557bff10d721393c8a8e61ad20cb95bbe718b2c42065b4d843904d21043fb2151173569ac7cb90433de907f9ebf9eed800db28f7f1029d1fdf5f6b4c116b0123855e0f1a4cb47dfe544874e1be731ea316795f12d22fabf0ec6df814a000f11fcdfb06afc01da9e345f92574c9f16dcdfc95a22a802a806702ca7811dc7010001	\\x2c05ea947e4dcdaa64fd40bf6fba51dff41a99b34b49c39c0c69defa8d940db837daab62a13597536558a30b124ed645027f909dbe617d9526948b7ac719260b	1673790683000000	1674395483000000	1737467483000000	1832075483000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
382	\\x924b3c69f75ca91aaca682db6ee5d853d1fdb70f44380bf522ba331ef5d6a0f65b1aa67b7164256319e54390c4e7757dcc828a3eb45b70d1b24d95b69a403c8f	1	0	\\x000000010000000000800003caf2afcaf089d56af15156e21815b5e7670be76c95aa7cc7977e83f687c7f6dfe385bd675435cfe05991ec90e41bdd4805885d4fed37d85c0a2b44fff31ffea5631340874b3379b15b6fa4ff65a2c4d8d3d4dbea24e8a50478505319b977e1a2adbbf90ae07be3f5a621575cc48c17b3589b0b9275af92d9193c525489142cc7010001	\\x378b075b8ebd1a219d9f8b0ebf98d79c363549cddfb02a76fc216d1e4b27de2a62246ce0966d29240f1735c54c4fcd138f6f539599f5582057d24ba66e7e4104	1689507683000000	1690112483000000	1753184483000000	1847792483000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
383	\\x93bf15ca88261f85749b982f8af3c321a984fc341b6d86232dcf457dade6e22704c63605a5f9589933c794ab975e8ec2d8bb215cdcb7cf4db5595be941e7f428	1	0	\\x000000010000000000800003be7bd24053cef83208d2369eb94c1cd8f526fa345b80faa7544ec57e348b71ed8a03fa751bafafe9123c2843bc5091c1dbe3d976cc0890907ad1e544d1a5b2440ca8686a101217ad63dfbdfcb77d07d6249cb577291532b8feb25ca4561602cd215905c27731551344b3db25383592da41c9dcaef17501fee489691fe9a0c8e9010001	\\x60da9530724353df414e5a707657f2b9f0d2b438b87618550cdc04c6cd121cb45f8a8ab400d9ac4f5af3b51c25dd2d2cbb064f7ca1403340cb957b2d8461240e	1665932183000000	1666536983000000	1729608983000000	1824216983000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
384	\\x962311d585ab054ae0a477ac9d5b9c70fcd4c6191a9d59224f4bfa3de2eb84e6e80233845afe5c032842c42ecc73534f249b439294aa6787d248a2571b872926	1	0	\\x000000010000000000800003b5300470942507c6360a3129fe85a47002a2bf5dd9df3deb20cf81976441a158695b085d66ac064f181555dfdba3b892439429b650a7f524c012697bd36bb2f1eff5a4cf2ee34d2fef2a33bb3ae1e19b0524d5e676fc1760a3c21d0986be47404c4ac6a7f6d37c95845ebba3565ae53e520400d4acf34d71e65f98d7f21960a9010001	\\x6d592e752d7892ffa2e72d2558dcc793920a02353b4e6a12752ac322ea128c2a956754e51ad3377c9006692e2f3a60b8af8de9660fea304bb3df32c592802503	1671977183000000	1672581983000000	1735653983000000	1830261983000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
385	\\x971b542ea7f106faa88ab7ccbf1abe782425dcae514468dcfab8be02c3887c6343f8a53c2b166fd72f59e5c6490e11f8a0c30021e64cdf7464c917114d4a8f47	1	0	\\x000000010000000000800003a9f0953fcc507f2d10ba6c5898870bda29316bc3fed8f21b2e3e49d0a1c23a5bd7caffdd77073f4c6e67a3ebda0f76d34ca0634b4e4932533076c7c3f9e0c7c86f9f1edd34306e1a57ed811a3b7c4f237c934c88ff7a433a65ca34256dc79836258fbffbf402048011ca3df25f606ea3f08b4f525f09f896a7a937ff10631f57010001	\\x8d19861c614a7b44b5d09e73db541461d6d763c946f35539ef7d542ff300b42a565dbeb9269180af9ff29ce67117459ce0f5a213cb3ca30440d058ecaab04c04	1675604183000000	1676208983000000	1739280983000000	1833888983000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
386	\\x98fb740393c493abf9052c25af5a9849d8672c7697fde8a8a43f5e14b0d7f24366deace75a352b57337e00501da5971eacd5df74335a637be2785f08c3e622af	1	0	\\x000000010000000000800003a92c2cdf0cb3c1073ae9c81b0e2757c70e11170ec8a0ea8638a7da7878e8ceee3a821c95e53b73a49262cae64841f39aacae2a3f10af7803c938cfc1142654df6960eb696860c6e85ad2c1da0eb591ad501fb5b3f5d8b92718fe7a72ea68ffac805e40f14e0c645b9bd9c30f8e7423a070d19845551f23d60151597286a3bef1010001	\\x41cdc5d5cc8293e9cfd36a7622c6030ed0916adcbf7a5ee192b302701b1dd9e34976986f5c6baf2b64469988db90892e5aec678158041e9f8c8b4c540e53f106	1686485183000000	1687089983000000	1750161983000000	1844769983000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
387	\\x99cb17195d6cf2d77e53c882c079a07d0afed3f4b38e3b84506c8236bf66ff1fe666e5462d85019db0caac400c66bd05995845b1431f8a1b90056b685275fd04	1	0	\\x000000010000000000800003c3ae391526782ad31a15e1783c0c6bf4873d3e9e0a3b4277b7daf05cf713eba20417bbd7171b08093b33b0d4ef1391553d47e375f06ea14403bd2617af33f97af46247eb542e7f043483544fed9819bd4d26aad37c5e3fec5867222100750668b84d5e8e7721f2df8aaeed82e120ee2ef2b212c6f42352c2e0b55aff3211a62f010001	\\x08107729a9e2819576ad246c9daae5578316607dedf1596b74f85c06e09e3fd1e6878ec28d526d7093a9ba702eb3fcf1679a66252ccea3cfebd2fe6d21e1e70b	1664118683000000	1664723483000000	1727795483000000	1822403483000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
388	\\x9a8bc61c4d0427203b5e96b85e0efda2d08f4e86bffe3193595f95c38e1d31bd937595ece3cbf5cd2ef688d9ecb1e90b2f5c9908b4ef79ad2ffaf5f7b8c306a9	1	0	\\x0000000100000000008000039cffb6e2693c5b620aedf3bacc2a2515378dab00a6631247d698424a0dc6db01ac6bbcb40b105c508d9d519249e3e0247030f84b66c2d9739ba93a7533da85823f19f4d35a52c35085c673b0b7fb463f6c394cb84da6ae0d92b48583d02bc3251396010eaf26ff0ddd7aef5185faa8c98afba86a99139eb20ede9c565e8229b5010001	\\xb1f12dee36c2c2ec7dc69ed32913620a4696cb62854e6e923c6e9df483b8f394fe68fdd3ddd870ba3f4d45d2def28e89d506a7947024d484686c44b460e09d05	1665327683000000	1665932483000000	1729004483000000	1823612483000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
389	\\xa2aba17ef69538cc3399ca6a0d31a78c2cf45d3d54a5421db11f797b44f2676381970533e1655d0c58faa6310dbe630d27a2e09f642f0d792b36df31c5aac52e	1	0	\\x0000000100000000008000039d19105a6ab7b0389b3b624eddf6bd2ed31b5f6421878d7251124af2acdbf1bdc64976f6f8952bc20156e2b53786ef5de4d3f9b9991a7d62617cba9d95c75e85bf401a19d5005c5beec654d3b4d6a4a9fec63e23a56ba0f4c39697bc617a426adfb77725fa354269d71dfc64cb2d446dd527fa706c876cc648aa930784add5a7010001	\\xc9309fb71bbafd23ac18889d5ad2237103c7616b972798a8551e0909c78606973189c51fab4ecb157fa0cf922147debd68482d9f6b2680a7141c0d62956af302	1663514183000000	1664118983000000	1727190983000000	1821798983000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
390	\\xa39338c5ea593f4aeb5d5cca75efd9b9e7fddcb15ddbae85d25493acf12c30cfd29a2cbd99bbd96645b07e5a0061a10917cc557baf12cb458318354a57b642dc	1	0	\\x000000010000000000800003e3a8a6f51de1e2f7a5e71dd46a494af35bc08364e7fd6eeeeb8da25bc0d127f9339811041c8375add9e05a89cba0c75b5cb8cbb015e73d0016e477e3e726d85280a0f2b3d6e7c4756b44bdc09a5b517cb0a1a5bcb54e28c2382eddb82c9ec70e3a54905810f9f537f4c1c3f59eb9787ba5a6e16eb25a1e10eb86394eafe58f03010001	\\x98490ce75373a699e7968b57b2e93882454a34e69059b19a9592eb1e2f3a4dbdd30612ddb8f2df474e1e676da0b0ab7dce410c75069f39a920ed37b6bf09fd08	1679835683000000	1680440483000000	1743512483000000	1838120483000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
391	\\xa47391fc740ff720a064a179bc3463981537826962997d1e4e3231643a629eb7bec388a20a9fe432a04272fff2cb2687a8ded8fa1d8196c76293934f287da52a	1	0	\\x000000010000000000800003b896e646a1e979e1cacd94ac5680468309776c5eb0e2d321b5a8cd6113f01324fa528dae66750fdd01cfff7e3c0e397cbeb56c49f8838c612b5be76b4543d810cc2d4806d038752d9f747581e4f6ce873462138a273b63ea71fa7536b00204958142737977eec3bad93cbba00ceeca909ba1404192f345ef7a6a56a4adc9475f010001	\\x5c15edced8b147eca43b9b36851b7587d9e9861c4c4f64cbfc20f40f54d6a8473d6ac1f7bfea37c3b254234b9d6ba13fcbddc522573872ab3912b9a058680705	1681044683000000	1681649483000000	1744721483000000	1839329483000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
392	\\xa9238f01828e4bd03b889d574731d1f61f582a66b3d778e203a95a5686290c7f30911760ded3ba6eb1168ab1b50b813990a37e81485b1ff7242db20e18bf8518	1	0	\\x000000010000000000800003bdc7bbff079c1c6259c3768d2228666c5a938bca4f9b3e5666260af2f9819252be8dfc5f66cfadb3e2f0576e282a4b4aad333b89f57b5356eaec1ab166dfa984d168fdbb6bb4a139a33d63b4e576adffcaecfd6cef9a769a2b33e9c8ddbb8ea7c3e1a2e976c5faeb07f51dc72020bc5e19c005c424df8f201833a8f4cf98ea6f010001	\\x85e7b3d199f31ca449f711161d8955982d575c4529874e07b95a72a026b7e52bb5c627e948a263b84152c07285d58af4e4b7f5e476874320b52702a96ad0a506	1660491683000000	1661096483000000	1724168483000000	1818776483000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
393	\\xaaabba75e0dfd74176124cc8ccb4919ef674b11fcf2a4ac8c06630d784693526eb75227d9f62b9c89269e22e0d34382e66de56ca62a724ade9c42690414676d5	1	0	\\x000000010000000000800003d8ffce41f1926fe5ede9ed7c2945ddd7c047f178ec414246a783f39e6044944ff2e73ec3063611dde3f8e495a7903cab15042a839519bbdefa5c0e640ba1431ac6a08cf25926c3d388adf20bf453d47376b16ae5270eefe7d7875cde35cd465a13cc5de304d9b1a6b46c8723cc63c3f6a4c22cba1a98361edc5bfa3165a5b20b010001	\\xaac9c5f5f875ae904c1cf6b16c97598cbd53466044be3e488bf441f2d23440882503a1e004eac2ead3a9d013d27b5570669b15f97c27d2f09f2f0a5f33fb580c	1679231183000000	1679835983000000	1742907983000000	1837515983000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
394	\\xabdb8e2e24f6b3b464e9117069ea1b84d9ba0bed9958f619763c89574e9f12b4d51d1135c74e2c46a0ee362c5ecb749c1a6b9300fc6abb52c8e7cca39f67f5e3	1	0	\\x000000010000000000800003a64c110ab1aca2727adace5d4ceed2f38223a496dac61e948d6ea778fe0dacc09a0955752723716c9229a1e3ac43f30a05e303794e89686f4f57aa2a71f05f508de4129e4d2ef76698c56be4126a12ec8bc6bdadb263ef199c798842fd0e4c4f75fff522fbfd287ab9d46b8e7d51a3769bd6a06f57ae573b128b35acab172f87010001	\\x89451190cf19ed0ac88f41ee81869866d5d20750cc334eb5d87e9d4861f1a961bc3a16eb2ddb5fde59a7e5be693dd0b0904fcf75a590dab9c9bfa702ffd84705	1668954683000000	1669559483000000	1732631483000000	1827239483000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
395	\\xadc3ec9c1552a4deb162d1bd83cf17afc986d209d620eaa13d02bb50edce8e78500d14a757e64c9ee73aa36c7f279cee81473aba16a2b795d4ded1e4010cb32b	1	0	\\x000000010000000000800003c258031be21f6a40617a075faae7561a3f155094478be92e1ac99962be76f1f8f7db40565800ce04e895d646ff611982fbd613eeebd205fe7402dd569bf4b25931baee1f369faece5f3bc5998ab46a0091521a992765c7157f2e5ac2fd366646910803b0c95ff0c9e664997294ecf4855c615c4512531a4d551ca11f66d592f5010001	\\x25055ee8c930efb8c577def1ec3eeafcf272aa22a40a473c8a7a49224931ed7132d7219b6c314447607e61303be05d5bdd79f58590747b65c88b1f93ca39d609	1680440183000000	1681044983000000	1744116983000000	1838724983000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
396	\\xb5dbcbff12d798ad67a8f97eac6d72662836b2c36f5e9cf64a0e4090b42b5e5459de2d6f0733041712eec722f8e735c0bd71611ca06652c38ae33a6ec17df5af	1	0	\\x000000010000000000800003be725f9b29be32d3bb5b03eaefca9dd93eca363711d204f5aedcfe21d6bf2105b8c63b592ed16b85db163804094037583cafef3b5cb3623ae7957d6b9d69eff86e4b93689a1ac160d24ac381c5c767046449a1368196f0c4ae7b88d428ceab42c69735979bfc5534aec5fa8b8dab0cb450807b11a62adb28f0d5df77f8e98267010001	\\x2896ded96dfb11d74e3ebf3ff4afae61d473bd3d937d1fa4a73306d56941bdc66807b8ed9b94cb531f720394ce9d7ba5fd5e341482e7eb79179810f9d0fc2a08	1667141183000000	1667745983000000	1730817983000000	1825425983000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
397	\\xb527950c1552fd6615393c7a384f0cc9fdbaeef4648ccf901ee83e80a49cd4a540507f7e5fff1643c309fb53c144f10ea06faf188f65ea105a4ad0acc71e2a77	1	0	\\x000000010000000000800003b960879ebdbf8cf1f0b47ab46192201cb7b2e00319569291f058a1052fa30d2de42f7e6f78fa624f9e2a79b02f2597811256e50c605ecdc4d44aab9069c4d46c3004e2a6f09073f8e90641dd4f77ec7b60cfaa0b9d48bc02ee5e49127727cdfc04b1fa667f49e2561e3f5df0cb4b9b00de861a7fd521ae4018ac31cdf94e6cc3010001	\\x76a315aeb039727961c0998cadb1fc86748944d474cd6b0d6658664244a64ebaec9bf75d2f90f75339e03bfeecfa2ccc33768c8ae557fd3d67abf1be393d980d	1688298683000000	1688903483000000	1751975483000000	1846583483000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
398	\\xb7af76a66b53bcdb5f3ebe1fade30e15a41e50ee1120cc4951f184386bf846bbd0d33ea71432b1f97a8b9da90833d58d78ec8bdd668f1e3bcfb42edaa56c9bec	1	0	\\x000000010000000000800003f57af623ac1b170b5057c2fb8ee76c42f54a578511376bcf5150d30d5989ad98adecf6e684845a400ef42158c1b56046fd7886553978b96bdc35463cb2693e80f20cf89495d76af786e27e719592ac86964398bd67270ef4e0fb0d326bd91941bcffde3e7156cc5915f8029d61ff13a6783aaebbc7b4935ae2b2401fbc581ce1010001	\\xab71cd6c1eef32c939eb6fae8dbec228c473ac49674e4100d47ba906c9bae1ab349dc7344c2bec22116e8097d062eeb808e1c58e1167622b65103d09d4d4d30a	1687694183000000	1688298983000000	1751370983000000	1845978983000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
399	\\xb89b121344f862293d9ecdfc9726829cd9c6e83598199f12d6fabd64b2536c418c8c256f5ae12dd4a4fd94e513cf86c0d33c46833d168d7bac894e9de9998d3f	1	0	\\x000000010000000000800003c6807833753567f845a211079d374e235372dce4e11be26864f5c839534457b598740b15428cee89cd4c3d8ec8f3253e6f8f7d326bb507611e2f8a95dce5007dd3ef03183a0d1fedf7f0b314320c2c48328f58d4c10d6b5b42d7b8462338bdcadf57a842de8694f895e97570c0196fa2e83c3edcfbd077c723fd0d310f0cbff9010001	\\xc6aac8363451e988ed391c0b95baa5a5d300d29c29ff2777e888c7e0757843c7bc66cc62d35478382076fd331c1f2f1691940e9793582d2bbc6e1458ec2b4206	1664118683000000	1664723483000000	1727795483000000	1822403483000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
400	\\xba43ee3d38363ed47ad410ab3b404e8d389e19e3510414d962d1362683c6b338c714c096c61d2fc7899642d69147e803ebd5b47f4d07955c8ed44b20ebc64a45	1	0	\\x000000010000000000800003b5b8300b51cb981a5cced38e0e4fda8c87e05aabc1aa3864248bdb9fdf4fb6a1600198d48d6406a3a13501ddf18495c27809afbbd99c83716563aefdb8f0aa0781cfd7b0248696381ef8663e3b7279c451d702cddf9ad02eb1985e0bcb123ab33e106c665cbcda75ab9512c80768cb9de4d472d567be41b44e02659713e2eec7010001	\\xd4979b01d17e8e45502fa23b841eaaacb835db3ead09be63fad02324cc5c0bfe1fcc11334d1c6fd6bc7e4a5e3d776040296f67deb170d5d491bed7ec8b8d800b	1679231183000000	1679835983000000	1742907983000000	1837515983000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
401	\\xbd3fcb70985008f43adc00c6bc436428efd063153fd65e658e799144d20504f79493a6490e4e81bac69b4829e06ee05b289901773900be4a86c51f1cc88c3078	1	0	\\x000000010000000000800003e997d3c3c8c61a376b0aa14d20f8866cda96042f3711028b9fae2da4c9eb4ae1765bfc24fa66efbeace5e3044ac5705fd253c737cb72f5b5b580a6ccaa2615083e7546892c9581aa1c2fc17fdddda9551d50d36e0d243df64d1f552b2d6e445e8f45cda277268a4e22fa801e0ed1ae90d80116bf7e7dce244b0b295a61c5389d010001	\\x9e11b874c56d4ce925fe87feaf30fe0476ccb4dcfaa36b40680bdb5e6a6b23ec8b248a4792e7e91f0063495dc2c9938825656d73dddbf17c11d8a4c2c8c1c106	1690112183000000	1690716983000000	1753788983000000	1848396983000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
402	\\xbdebba160df9e9f87347fa9ebcb9d8aae7d48a65b79a9f97c65f6845a136c9be7bc34e3e2cbb728912c007ad56e3ab49863ce85aab292da7c102cd323804379d	1	0	\\x0000000100000000008000039812657040e29aede77fe14b1db9ce0bcf85dcb0994b7a6918e23be2fca4d184ae9365019daf9b9fe26a8fb535253e4f6a5edd0e8f134be2bb86e336f2fe7ce270c286bb84535716de3b19d302cf58d8945289b320eb87cf286b6c89a8f903c5765a503c6769909e0b9461e346ab6e99f31d81f116b18b3b2a1d5be7ab29377f010001	\\xe5c3c1788f9c9d3891ad39d67bb3a2b0be3129e52d2b68a66c119fbeaafb36f8aad432a6110e4e52f2646ff6f945ff7082224c109cc2f96e14d1bd1523dd5701	1676208683000000	1676813483000000	1739885483000000	1834493483000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
403	\\xc277a719dcfafcadf74dcba99eb87e350765613e91f224b2e3731cf357eb162bbccdfb2ed35407fd85b15cc8753ec89c37c9e21e8ad861ea8c0623c74d41eeba	1	0	\\x000000010000000000800003b0b0b48932745e738b97de1f13e88894ae616910550bbb5009df5e467e8273acc17f7764e8704effe19c06d3a46e271175d95438fd2442c72dd2b36f228be7828a8e7abf74999e511baf77e563f9e6f484115e1d190f85048b023e22e033da0d8105ace9396d2349c52763488921e56b2775260944f952304a8ddb381df35049010001	\\x528c9179b8d9865e2341c666bf43dedd2628abf506095e39554c512d93cbedd78cca1ac8fc11d7878ba2812c4e6ba229180b1eb98f163131b1ba7bd954869a00	1667745683000000	1668350483000000	1731422483000000	1826030483000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
404	\\xc4abd3a6e8c465f829317395199f80406f8d9f417b84fa8798670061fbdf0f785880739b2ecb74d400acc5f40207126c2373c177fa4a2b7fff2f9eb884150b12	1	0	\\x000000010000000000800003b8adf9707a5f7f438fd6551db2011f4675f72c1b1199eb58c74056c632232d9fec081431da1e3716bceb4656e898e91617f6ad094048fc79cfac7ac33b110a658c37be0040dfafa778ed5a0511813ed151e4bd4ba834fa9834cc4d9b5f1b7c600642fb4e78821e1b6d4a4139ca03ef962959c274917919b4a3844a5c7f5710ef010001	\\x3021a32f6f04daa1b32f204ce7588b20d57eddc0635d2b3d6cd6c01da0cbc63f6f91fe6d45e94916b5700753850e1b48cd48b557647b84c41e614da669b11a0f	1679835683000000	1680440483000000	1743512483000000	1838120483000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
405	\\xc7cf5f867f0e8e1b7f96e5b42afeef6a60eba6f430930ef0caa8dee86d25b724f154858b9c421dc47da05150c30937b84a5d5f50916f02694ad8f0d0d9668018	1	0	\\x000000010000000000800003d5030b8d2459e5274e5fbeeeed8a8910e4c38b728a5f9ee323bc5a31a0558fa517cf5d615c898a73a54269b594b2c6393e477bdf2a356de6339487caf4056f839cd36eeeb00bd4e8879f326d77d10d6118cfce40deef56a0f4d02cc18a39947d4dc6f9c029984a7e8089b822e296a4accc98eb321e6c6acd5734fdcfc16d88c3010001	\\x0de8b95c8d3119696fc3ef2428ffb2ab7d2a835577ead3da993d11c44f7c2252c36ded40e30247ec040f927394bc34a1966e7aecbfc44ba7e3f920d342943f08	1673790683000000	1674395483000000	1737467483000000	1832075483000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
406	\\xc83ff325de658adce8680ea6b64b38265be24f39f613630c74c33b3139f6d55a89c91705f7cb93cf9784028566f7f94ea7a6b3ce0dc342105ca78e031f772b26	1	0	\\x000000010000000000800003c0d922922e8c375af54807fd156cf35226f3f9f80427f231914fce0dd449b68ddec7f68107e42fbc682ff0711cc24d8b07fecb815080dd1d7ffe8b142dcc2828561a7c6a00909aeb06b652105ebf1b986993511c426b14689bc5903e475271008fe222c8bb66cd9c643b035bd4730222dbf5706a1eb33f1803e47213d5a68d8d010001	\\xc6ef73cb9c4401e9affb3dfa655fd08d1bfd21bcd97b686fa1f87684ba9d5b3203f35a6bc70fa190cc4ac6b9442e1688b139a3d6f40572fd9c49ff528252ac0a	1686485183000000	1687089983000000	1750161983000000	1844769983000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
407	\\xcaafe76791127a716cd98575ab755a7c577834231e480b6e1e9d86c141e1b3ec85361fe37aa9032cd4495924ea902a7afd2157368642ac1e73967d3c587f2a2a	1	0	\\x000000010000000000800003b08cb5b22428a9dc9ccb7dc357006f84d4e39fdad9d8203ecdb112fb01f37b5654b797b874a1d15b0c4b78103209583a3c60f7e5fc8d48936031af24210add8fa4ba9677da05513e6d43651714e9c1a9f490ebf8249f21617c3509ae3cd91eb01ea52f3ac19e83bc43af8716a06fc82763396ee0360989ffe076389132ad992d010001	\\x580bb2a05a6e582205d0e84e042816ef6f0ba20d2757ffbc39d0953184128188ad621ed4b7d2237625759da7f28a7cb3f7dc7e6bf55c7816500f4dc41f8c3f0b	1690112183000000	1690716983000000	1753788983000000	1848396983000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
408	\\xd2f376f0b1c7a0dbd42ba90af31ec4370eb28437b28df41340c324fa24be1cb7a3114fa41156cd6bc96de1375bfe68dab15a30c1b6db92586397bcde880c14ef	1	0	\\x000000010000000000800003c66d0beb66704da48504f991c6848f200fcf6271a11d81f21c1a3897717221a17797923616ab43c2d49be2c3fe47c60232a6d7aa499f84f1c6ca497a66e3b52071090336c79f2ba026ebda1cb6f1e50cc52d0af531bded8acb98d66580f4e28100fe957a7ca4c16ac4d8e653671ad41ee31db7ec4df3f3deba0ac0c4f3743829010001	\\x1adba0ebf797501e0004811ee13cb93158e4187573d5976fc2029a35a0c14421c002d9ce3d82bba87fd841c6ed83eeb8c06423213467a185182ad96b87a0800b	1684671683000000	1685276483000000	1748348483000000	1842956483000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
409	\\xd277d252bfa0f2ac8cb5c89a0c0bbcb267ab838cae73b91d1a5495e9b44fcaa301dad065c73b45c834bc9355b7d7ca119ea607248cbc50f1b887c95df4804756	1	0	\\x000000010000000000800003ce695e8e22cd0ecc3adc22378db9a6a10868d6d83bf13944d2d7922f34ebf6a3c8dece84213399f0085ba9e1ed36290265bf71599478652e9c140a2a4f31ae5d5ddca08580b12d9d5d0b001332eecb1470623f4fb77830389178951372e4cd640a1038136d8d2d3f8d7813c2f08fd4af0dac723c5741e4a825af1bf922c64d3f010001	\\x1ad829e46dd2db151da55b9810ac150b01b7fd13cbee166f6af0e9908f9fab7b98e11c2e872c4d4e30fe17ac074269350cf00fb583fa62840e59ad7f03a28c01	1685276183000000	1685880983000000	1748952983000000	1843560983000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
410	\\xd55bed597a83d00dbf616812fe02c0091b8f2b9a6f02bb66c9c4594a313e3f32a380d53454823740d945655d5df134af7b985a19bbc77168cd698ab4ddb03e91	1	0	\\x000000010000000000800003a92f1c6f89ca61b50f405705847de09ba5a8788ff7bd5f187df5c6395aa7f32b08563e81dc54e03b0f145cb3932a553d2d9f3195c4d3d1636ed62aac1e83a39efa541db19c2166297c2a97b40bb69d898813a22663cf3de8f4dbd95b0e0c5f5a9549f666b857dd6a163eb4984bfa26b483487f710ec348ca2c9c41cf4d58139d010001	\\x260213c0dde9698fe04114d570d8f34879ff371d746a2ab99d3e5b60eee681419ff78aaa2faef6b70e248bc4fbce6659ace53905ab9935637abda0df3ca0dd0f	1670163683000000	1670768483000000	1733840483000000	1828448483000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
411	\\xd59349304f9856c6bc8a5feb29eff76dee412e5be2850fae5c227ceac87639cbefcddd8c4ce26462b1e475eb73a3b09dcf70139c5c35230b6d48b48c5489a16f	1	0	\\x000000010000000000800003d07282181d8c4075567b4e9562f84fb03be486e946d740adee05be95e236af0d3513e21b345ffb5704111d0c0dc75e64f4044fc275a0b2f06ff89e1d65ce2b7382a2bf457bc73caeb132d4c9a69ac7706b54ecf107a4f5fdd43857f367032c7c748565f788d5b4398b54aabf4a27538963c4cd27a3c402d48d736b98f747cd33010001	\\xf31c4690bb2516df6ec5cd917a118fc3dc09614a2106f3b1e0dc874c0159848b6ca5c5dab227b43b1fb5ec88e19874c525199912dbe80161ce245f076250fa06	1673186183000000	1673790983000000	1736862983000000	1831470983000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
412	\\xdbeb1db7dab47e13ac1dcca1258bbdd028d92107a9dc291322d3b8f06b7931bcd8e634c1c8ea846071267bccb7bffceb8186f8c204e614a41b11cf2d3aea99c2	1	0	\\x000000010000000000800003caf77bc98ee39dc4f8cc76474d3d3f77adf5541b8afdc434cb6f9ae050fc2aa60d69f08b6d93d8037569f8fe2a2fbe27cb1b46ffcea86475a8acb41691109661c60a9fbf62a31cdfd2ba2e928bf0b88452c50896dbb1b0806e224756a86a8b591be4a3c3a47af23fba405044e2e3b88a431392a35e5d1c23b1ea22943eada52b010001	\\xe8303738a8891d80b0c511e4ed0cf3588ceda9f14f8b99dce49b0a59098b4fcef8d0c9be100b930696196a699ef6b62f8b42c9a26f0d39603dd202ca5017780f	1691321183000000	1691925983000000	1754997983000000	1849605983000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
413	\\xe21338944df17f12680b5f633bbf863382d7a38d11d51b8b90d4b5453702373e7953342a1bf8736aba71181d462183bb8450b56f1ca57aba73b2eed2dd10239a	1	0	\\x000000010000000000800003cc63654bf09b5b0ec68260c5546b12669840d166c2c0d9933eb9d6c4f6a10538dc44f4ec80a50f603b87eb88b1fc996e4672a38fb3064c0f389349ae7819b4abd974dfa0e30b1584709a50e12c1e49d2025e6433b3d055627cff6af95aca94f5f002bf2e4853ae446dbf2e58655e632d3807ec650802dfc3ccac6c0038f2d2df010001	\\xb9798592f567e0aa3f96a7053050be68fe0c852f32980c4eb94b8b3fc0f1f8c8b2b1a2d3fc4a30ea9af2d7e1cce061b1d1ddf4c86996d7f67b689d4912c5f70e	1690716683000000	1691321483000000	1754393483000000	1849001483000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
414	\\xe3731d567ae4b270d48bef4d1a7da3a7344bd9cafde624a2132f97ffeca0b5027961ededbf40e9e8ab7b2dcf3fad6656d4c603bca167669d8427f2eecf9c5b92	1	0	\\x000000010000000000800003c72789ff23550928b15928a0b1b5a569349ea81af2fcdd33cc59cd6c22be60cf170650054ae47823429333e3ba9c3a0c716124b05cde2e66cdd58aed65029b0f1f69eed18bace71ef0d40339171145a88f4b3342bd5f0abf7a314186e43f9b17d1a4023a29e89819b6b06dd0d1bd6c799df5b952c19a87c2af42be18f16c24ff010001	\\x9057a4c831b489c8d030ad78d9ae061954ed62865f2c9a5597f1172c8a976e7faf1d0c78135a111bb872b515d79c0a0c12cf324395934d03e297bc36bfe3ba09	1677417683000000	1678022483000000	1741094483000000	1835702483000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
415	\\xe7f7d6267e1cab8af5024dbd4345f5ca2ffd9d85572212bb0bb222694ec4290768896dac95dc85483625e5ea0b5a22d23ec7a72d80167d20621517b3ff91cfc5	1	0	\\x000000010000000000800003e7fc4e4276363d274a911ca0078d9ef53fa8ecb0a592f827b5ba8cd495ed9eb190b1f51694c2659d2a61610d6bceff6cf67ed68084a05faadfacfd91e165de794914dc7ed28221687ea455a654fbc3bc00e3d04c0d6cc5c914afd2ba799c06e5e64f9e52999e159b9a257636a3b2fdd6f815bf2b2b9722e61730d6d78b440965010001	\\xcc41b9497b42b4d370638ad8c77d0fc0ebf98310aa7af9d7ebcb44ed11ec9b0cf8511e7fe446bc7bda9036ec2666611a37a7a349a691e1fc30ba9eebbb24bc06	1676208683000000	1676813483000000	1739885483000000	1834493483000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
416	\\xeadbebf7ef0727dd9508199c8086a500d27c1e858aee6a30f4c80f26eaa33b1b6dd7db2f9660dfc62f63931787e9c6807afb4b147e2e7ba3f8ade2ed07ff2b24	1	0	\\x000000010000000000800003c618c8a165311e1fc49ab9d982b3960ea496e7ae62eb6fb9d3649dec66ef5f7e40eb989492cd8698216b46075f506e9d2e2c56d8ec357981715bd7b75b359f828bbfe41dfb478e41f7cd4bf0e6f4d208531c2685ec19e1c7ebd3b313fe036e797be861762b2c7dd3d776d72f74aee7bb79f48bd866a7243a89873fdcf2805879010001	\\x2f1846008a9b147fb8fe320e66192f6630f81beb26b9e597bb8ed837289f60428829b7e9a2719e3e0628e4ef55becc69d5159a93d055ac75d1bc73563e37a804	1681649183000000	1682253983000000	1745325983000000	1839933983000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
417	\\xec0f3aeaa74cd1067f4e93d3a65326c94ac94a443a41eb10846b0fe344fb539df4b9d5c03dd35139bb0cf78adf98ad3cc7ac36d21eeadbb4e3e2840e7a454319	1	0	\\x000000010000000000800003a8f5ea0f8639e60148abfb73fb6564723f4c48928f730de3b9e965867a2bffe08796df590123cad2ec9e1bde7ed70ef8ed01952954120a27f326ab46235bb8acd4cdce35a6262a221c54a3231bcec52a30d8a9aa6ac56dee6c06cefcce422f888fb2b31d20df7b81f1deebbb6cdd9df02cee76694175a194010cb638b40ed671010001	\\x96a2a2dd9babfce7b6f1466f84406bb85df440a82b11f924dd31ea2b7b45f86b75249f6d3108f6ee1e20ed2bcef50e9746cdf367bf6b2745978edc7787360308	1664118683000000	1664723483000000	1727795483000000	1822403483000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
418	\\xecbfce93e7d216c2dc1809419dffb99650659c1a387da9f9b8f04b6517003eda7435e3ca40f8d4942602470808b3ab7dd417162d86792c947e91a7ed547650c3	1	0	\\x000000010000000000800003c8f8773b53acc92f25d12fb2803b6601b7c7f6c613630c7c7f2c8b9c543538854fac3e2f083a509c24034a23edb4d0cecc880e691e451561117f819609758e580a27370ee957bf187297a03aa7074348dbceda035da141519d4f6b1dceb5d926b6fc672cff0c447001399e895a05b84397672dc07b11d2a095ea14fcc7dade4f010001	\\xb3bca7d14c35a3d82e828f148fe3cb37165c1ed0c0bac1941c6f1bb80c77539fd3fed1e935aef5ecded74f342f7460f3634f55e18da4969fcd0f11be6d597906	1681044683000000	1681649483000000	1744721483000000	1839329483000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
419	\\xef133cae7415564fa65dfa4e3f6ad0e803029e20b827be2dfeb8e7974894bcf211d16493bbeff5a15addd72dc757cacc5bd44690c9e9d6908064aef5c69b211f	1	0	\\x000000010000000000800003c3c8368e08e740c5f825a61b1ed0e0b49d640f687b4bef1c81f9bd6b0676b8b25b71ce8bef2ac9f8f2e7bcffac35a9f788a80656e46bcef596b4a9025f7a900175ed67bd898499afefb4f767de8e0fa316f7ef9b2a8be90a2c1242974ac77fecd3344a852554484dd616036964967e312c06e896bb9450c382f111d0d4482cd1010001	\\xe5fcd475494aa8990ef788a2ae1ab03849b94cacf6f7d2026728ff2dec5c26e93053ddfc1b0a7d40b8dce89bca249912da361807fc54c5abaa49da8ae56d2105	1664118683000000	1664723483000000	1727795483000000	1822403483000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
420	\\xf0a3073d054a7ef3551d38e2eb0a092964c356f19805ee97122126169ebb682a093a2888a10fb04cbf2f6f54285206418c199977ae94fd8a0126562f783b100a	1	0	\\x000000010000000000800003a0c3db422d312f70a070387f2ed26d64f807701104e2cebe81136babf82b9f2ea0bb9c2a31804763aaddd9374fd02b2b7a101660452f81822c304c28e61545f0cce23d7549bd2b321f3743da0c326981b749061e555696424b3480cc8cfd869e9119cc32a38bec662ed712ff0538e85c4733e8492622060ba3bdec185f0f56a5010001	\\x025eb6ae15c1d55e51c136621fdbc5cdda6a7d35ef713026f0f5010c0419b9055c7e5beac3af2fa790b5a1ebff5bbf806a9ac1907b6cec943568bf140d9c9406	1668350183000000	1668954983000000	1732026983000000	1826634983000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
421	\\xf10fb0d5348fea4f588fe2fcf4cff8d1fed4d50be13f0ef4f45da63ea44473a6bd05c263f8484f143081111ea83a6ba90a052722663a6a3648d89c4424facb17	1	0	\\x000000010000000000800003a83b8c7de766a5b7596cc97944d33571a0120cff7d71980794e69b553b6021710099851c46190b39794d73dacfe9210264fcfadc2dfea0c4fd169a7691f9b27092a33e23475379bd5cd8ebde45d604efb01cf846c9d500cf75121eef9aa7075867f00064dc47d2e281d175cce14e23824bcc4419483a868f757ae86b7558efdf010001	\\x362cf8e4c3ab151506056ea79bef9171eab9ebb6e65a6604b5679a91dc07d515e90fbcaea78af8b6c91f397a272a85819caf97230c40799f5058814c992e0a06	1688903183000000	1689507983000000	1752579983000000	1847187983000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
422	\\xf9872512551d86703b73c1f2c646517b5c1c7e09695ac396ed251ad1500ce399eccca3b180f0588875b68c51f08c9ec7be26e94e35c449848920d707eb8f84ef	1	0	\\x000000010000000000800003a5a17898df0d46e7d9d881268ba4cc72efec2eb89687683f17f1d70cc9e9fb429d367806a4f19bad101ad2fe1e092bc8604cd40a47427a31aeda3ff7265b2fe96723a11d85ec8d6dc5bc5604e37379e7d762d21f05cb8ed1dfaefcaf8e83dcc772cc877def22b2da503634247322611988ac016773d196dd226707c9b56d0017010001	\\xee83c6f9eebd3775e1cc04e7feedc9958152736c46450b9206ec916a6c2b437d1a92d0f0be9e0017dcb30347c9540a07b52d1302c290faef973ebe91d7bf9207	1688903183000000	1689507983000000	1752579983000000	1847187983000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
423	\\xfacff57847a2a8ae9860518365ef49b587f0ebe2df06a789450e3d44c1ad711d63472c35c592816f38620c215f82f4238230bcb277e5a45b8e05dc79c6b33e05	1	0	\\x000000010000000000800003c4072f514c6b9f27c56cd9e7570351c6f2b9a5048cd2f86bfa22e9b72f4bc8ccc039c65f0da1e3e2a423277f543fc69711e693352585f6745c9a2c6208a125ea792d84afe2247bb96702e6fd1d892ac871683420c08cff0c684268619fca37131db5b2d00ad28615553a534f21c508794f3735d9c6f35de0a43c999ad21a1559010001	\\x7dca4519de59ee37569557030d1618a283c279cada618a0cf2bb1475df50da390310a267b8ee9514da8ca84015ef61ead381789ea93071d128e6491f447ad409	1688298683000000	1688903483000000	1751975483000000	1846583483000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
424	\\xff9bad373aa99dc882aae38c38e6a1c217b4fc0f0bef9f692e07e006e7ddfc9f68963d68e2a4270a2b66943b5c0c6f70b86eb80cab8f01b14f1e4277d78b753b	1	0	\\x000000010000000000800003c42ced09fc68695b0333181bc5e814b5a759669c9c71ed1323b3883be32f3378db330f2f82009769921590cd48d8aa812fb58158293275bb5a340fc99a351e6a83b5beaba086af8531c95fc3f202652ce8a7949da99d260c1ad10fa045ba51556de4946ee17254a27c4c615dea019be49b695b098353d58dc77d09c6c744972d010001	\\x07095b868a69325775860184f820008d24c4f2d2d3b5058220b1611acd65f3ce5fac648f4d6ce4da94a68024e53eacc894833da4f358286b83810ce3866b590e	1664723183000000	1665327983000000	1728399983000000	1823007983000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\.


--
-- Data for Name: deposits_by_ready_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.deposits_by_ready_default (wire_deadline, shard, coin_pub, deposit_serial_id) FROM stdin;
1660492611000000	1795540933	\\x195ef04c4532fdb2ae1967a2ce2466dcdb8c200d4f73d41c2225849867e43619	1
1660492643000000	1795540933	\\x07eec627265683f6c6a0b3ff7f0d8e5fccd7c0d64b0355b057264230026aa7c4	2
1660492643000000	1795540933	\\x164c3a5136249f47ec01e5d82353c78abd16936a8ec979e0f6fe1f2baaf0f489	3
\.


--
-- Data for Name: deposits_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.deposits_default (deposit_serial_id, shard, coin_pub, known_coin_id, amount_with_fee_val, amount_with_fee_frac, wallet_timestamp, exchange_timestamp, refund_deadline, wire_deadline, merchant_pub, h_contract_terms, coin_sig, wire_salt, wire_target_h_payto, done, extension_blocked, extension_details_serial_id) FROM stdin;
1	1795540933	\\x195ef04c4532fdb2ae1967a2ce2466dcdb8c200d4f73d41c2225849867e43619	2	1	0	1660491711000000	1660491714000000	1660492611000000	1660492611000000	\\x53ce77b6d1f1959c18ed6b87a8d312c860db2f59ac1c1e0b688b5070701eebbe	\\x30e10f96acae7c9bf6cdbba377f1ed6a57b55910c88065a1997dba4fd9285cd6e79287fc533a97bd8260a1f66c904f53180ac2a41c72008fe08cc927e75343dd	\\xd6311c708dd1763341b8dac920e9c134c15327f44a69dbea6a994318366fd39b9007df8df1db86532ddb359e31f119a92afa1b45c30ea00b235da0e6d6ef7702	\\x33128dd1bd813837cff64a730c61e287	\\xd31e3f48cb5318906dbbb7948326362f41604c7a728323230ae82aa995f27400	f	f	\N
2	1795540933	\\x07eec627265683f6c6a0b3ff7f0d8e5fccd7c0d64b0355b057264230026aa7c4	13	0	1000000	1660491743000000	1661096546000000	1660492643000000	1660492643000000	\\x53ce77b6d1f1959c18ed6b87a8d312c860db2f59ac1c1e0b688b5070701eebbe	\\x8e42c55b0c18c6ac72a18088cb898daf9233474f9a2f22776d6067f49aa0e6ac3da1b4b6c96c7b93d531ee3efbc3b8902370de925c71b2755d0121779b963515	\\xafc77225b70f514c17efb939f1db6371d54d7e7b197499d9e8cd4fd4a3bb405642bc77cb0200e8e82185f7ee08662459502a3de301273e9f62dae17fbb96d706	\\x33128dd1bd813837cff64a730c61e287	\\xd31e3f48cb5318906dbbb7948326362f41604c7a728323230ae82aa995f27400	f	f	\N
3	1795540933	\\x164c3a5136249f47ec01e5d82353c78abd16936a8ec979e0f6fe1f2baaf0f489	14	0	1000000	1660491743000000	1661096546000000	1660492643000000	1660492643000000	\\x53ce77b6d1f1959c18ed6b87a8d312c860db2f59ac1c1e0b688b5070701eebbe	\\x8e42c55b0c18c6ac72a18088cb898daf9233474f9a2f22776d6067f49aa0e6ac3da1b4b6c96c7b93d531ee3efbc3b8902370de925c71b2755d0121779b963515	\\x040009d00f4d33915bff816790de7b47177ece870a7f78bf936d3d7fa69987b1e77e3736f1191bf77311b91f092c4aa8677873dcdd5cf0900cdde238f591c406	\\x33128dd1bd813837cff64a730c61e287	\\xd31e3f48cb5318906dbbb7948326362f41604c7a728323230ae82aa995f27400	f	f	\N
\.


--
-- Data for Name: deposits_for_matching_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.deposits_for_matching_default (refund_deadline, merchant_pub, coin_pub, deposit_serial_id) FROM stdin;
1660492611000000	\\x53ce77b6d1f1959c18ed6b87a8d312c860db2f59ac1c1e0b688b5070701eebbe	\\x195ef04c4532fdb2ae1967a2ce2466dcdb8c200d4f73d41c2225849867e43619	1
1660492643000000	\\x53ce77b6d1f1959c18ed6b87a8d312c860db2f59ac1c1e0b688b5070701eebbe	\\x07eec627265683f6c6a0b3ff7f0d8e5fccd7c0d64b0355b057264230026aa7c4	2
1660492643000000	\\x53ce77b6d1f1959c18ed6b87a8d312c860db2f59ac1c1e0b688b5070701eebbe	\\x164c3a5136249f47ec01e5d82353c78abd16936a8ec979e0f6fe1f2baaf0f489	3
\.


--
-- Data for Name: exchange_sign_keys; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.exchange_sign_keys (esk_serial, exchange_pub, master_sig, valid_from, expire_sign, expire_legal) FROM stdin;
1	\\xc485dc3c300d6b3744242cf35c2b4c584b524be6f4502a42cfb4a3f2a7d1bb4a	\\xb641ecf88d472f5c3840e4609e46be2185d843a6aaab505073a747854a6c93c4eb3f430afbc9485b5bf8bcf6909f28d62b91e4457d6e5a4752a8a970e8ee2e05	1682263583000000	1689521183000000	1691940383000000
2	\\x64139e2205bcbdafdf31a9c769ed3c94ffd276dfd4515d8c92eda40ee52bb7fb	\\x4ed0acded7de2e555fcb3d4b50208e3e483083bd4797247810808ba7dddf095b709d1197db2a2e9d01e7587f9b6869ea5eda2c5ef847487d8b54dd0f6197180e	1675006283000000	1682263883000000	1684683083000000
3	\\x66f1ef602fe677463093668c6d5af153d585161ddeba5d96daf43ba33fb0d724	\\xa6c2fd4d93425b6f1e2664fd941f4dae30cfe42777b7bbc0a4832bf302a037e84e3dd67b4595328a7d54827d0ab9b3f9a3d72d27ef09859ae7c753c4f55ce309	1660491683000000	1667749283000000	1670168483000000
4	\\xb18c0e4917ecfc89a1d0c9d4343e8e7deb737f1316e10de02199c0756e6711bc	\\x43fa0ee04d5f518af1a3d929e5e1ee8d2a6a3a10495edf44b79debbf3d16e449148a999c6e841cbda1aae039f85d1743515ae14c66dae1771cb3027db9d2bd05	1689520883000000	1696778483000000	1699197683000000
5	\\x96ed594787cc48401c4bb6aa05bf648a1ad106e06405f47fbe7ea2f4944647c1	\\x0a77c3f020563eb15baff887e9ea6a7606ff55b6ca35e3d2a2f92ac3310bfc5a1dd9f45d671a156b9940377a894039ff936b846538285a04b1a3ec2acfeae703	1667748983000000	1675006583000000	1677425783000000
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
1	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	0	1000000	3600000000	3600000000	31536000000000	5	\\x2bbd9ddab33c6003f4a7ef30f949516f74b60e33b3997a748af94e1265226c85d3786ea5b2cec4d6cdc7169bc86435b6d568d01a25530a55da8abf5827c2fd02
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
1	67	\\x2e7bf7a4a66e1c622676bcc385f842db5a88b9b54ac5b10881496dc94790d2e1	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000008a3ca78a33136805e04db0deab410193e998d8f99dbe66b1ee2631b142e8d47b5cefb69f86e76d398f803d1094633832f5460b234d3e518c3ddaefe10cbbc69e104e9f9fb2ecc29a16fb11cdf98f42ba218c8ecfd8a6f30f9a1ded9b60883beef94f39b8a5ac95ebb996f0ad02c57669825e04176104a1e4a3666ae0dd8d1d7f	0	0
2	36	\\x195ef04c4532fdb2ae1967a2ce2466dcdb8c200d4f73d41c2225849867e43619	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000008956797fb0ed30334fdb2e54df0d46e3d0fd1f32dfa2d5868fed3654df6c2b9f18e10452019bfd12ef8d5728b2a637d17af3ce14128ad81a081ac8bc46610a7840a4028044aaf012b407b5e1a015446852f40f8531f4b5a0e6b82d8f3023b76b928c99130bc83e8dca7440325b8ece7beba806798555c0a8793a6a8969fa150c	0	0
11	105	\\xf010ff469ddfb865a622bfb4b425fbd4f9f9ba677badd18f878df3331628bb28	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000a0c2a5edf4b531b236b55a04c8d09791b7d1d6502ebe18980ed1e45b1eb228b1ab2ee424dcbc52b3615f4265cc87a13d6284911b217d1ae78907d30d0f5cee419cad3be617822cca9a09f8afbac908d492358140a1ce00af506c9b2f5e6d96009c018eafcb89407a8782ea5c66795e6b4f963e8e736870ac65e7cefe0bad9d85	0	0
4	105	\\x6f125d7175925424179ba7defb110950d079b6013b798c6995267bbf94396515	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000004170d4251e0f284b31c9fac46d09d3afc5b8fe83c1d7f18ea77cb20bea3ef38510bbfd2966f4c45efc70d85e227612a9e07fde03cc2ac2024caaedae4512e244d4156b236eb9ca265b5dee6a1b99ebbde00f1a8d8ae5ac7e3ffc494dd99672f2dfae8278f4503ee357652bee33c7af9d6b9ee50169af9e6fac08b813e6a5dcf6	0	0
5	105	\\x73d4401ec25f85d10edc4bbcdd9c7d72ab4e59f2abe18822d84141e38a585a97	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000075b0057022159c534f5a364c71aa852d893f86df230f9980e3afd5ec955687ae97096366c7b2acf3a53ad20e16a9a5d91ceb0508654175298deb19982f685a06e8300aba2184f8b2962ce417859d4f193a0dfe2ebdb08bf95d795e17696a847ea3433f7f2572ef3fc94727d8f135c9e188c6fb7217600debe62e36adf6808b0d	0	0
3	278	\\xbc9b2f635789c6986bf548763e1023fc381a8dc940de811d4c95028e05afc4e4	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000043576a9d024af8202d24147b1420bb4ee794f7170d514be063d693bb2e08ac8fcb1187f8bedaee60f5dc7bc6291f1031224a85b742f8917ed255813f99011a8fb473a6870c8071131e4a8c3371139bd57f713cf2f43806e37bc98e15f9fa42c9ec2da1b38b003098395a38e3e6d065b80fea40f8a95c4da1fcde331468173d8e	0	1000000
6	105	\\xfcf758084042c52e18e9d39d769cc5a187961b8405a6bc04640989a338966ad3	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000007bd8bf55da49e3916ff7a29aa987e34b12e839301ad83d7d9cae24fea8f2aa5690856b11bb42debecd05a8b91d6768a2eea93dba42314a6a802a82598868efa9878eb28f54acd3ef2146b51107c1599a9fcaa1f1f72346ffeafb8ffc978f59539009017b02718fb55f2a872b6c4e5e05e7323cd801464cc4cd445ae6258b9d87	0	0
7	105	\\x7d2d2bdf968798e659184bc26b84bb448617bb551018db908cdd5a3c8a3cc7f9	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000009dc410aaa318b19184acf8efdc6c7e53c2d6ec55124113534627d0642777cc6099caf63a5f7809dea91b14cb86da78721d9a1b449cd22c27e550b08c03f74c58cf95c16c69c819451a48e7dcce368fc58e85a7b72f2c607387b35e3d6252b8351015103c6f547bc159ebf0373178ff9765314b5bcd8b7ea57d4fb30906ec3f5b	0	0
13	74	\\x07eec627265683f6c6a0b3ff7f0d8e5fccd7c0d64b0355b057264230026aa7c4	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000b623c8f3da48307669700ea9ccb1ec419c978f21bf8776aa098ac3708352fa0f535cb1e1cd6f47dae110b2369b69df8d35613604bcc564476a42bd83cf78d00360a46b35753b86ee6308f3aaf0b92cdf1294dec129e2ec28edacba97a10cc035ca3a90ffa5177dd127fa4b73923e4255e06f72d6bd1cd8176b684928c6f1d2c5	0	0
8	105	\\xcec798164d716c391bb09bd33af790429e87ad59b64e97b2432168d64c4daed6	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000053a8f0a7af4195e106ae97c7f2426c18fbb5ddf918e4d7e18749dae0931b6564c102ce68de254ccdb177c9ab315345e8e10c9b06252dda78c6ffa1c6321b0a2a128855a6aee41137b57391e7bbd74c7cd7f197871cdda98e62c4c6d8d828ab265cfaf5518bffc309b260a9196837de616f140428346f4f814e9f52db6a61971c	0	0
9	105	\\xc896103f8ec61d659da5d65a16e7911cda6860612598a3d362566f7e75f594ea	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000039b1603a999a73c0a43b3ef91c8f3d41c6f37f0c6a0f681aadc64aa4a11b153b1082d91c6043ee92e05ac152751fdf48272d5f6102811e28c427a1df3e18e22043a715b937fb055e9e2916a3a98fa5498afb74b9013d503ae123214a4a0b95970d5024bd9efb0c385da5d2816b8ccfc58b611dfbb314531f42655177541c6943	0	0
14	74	\\x164c3a5136249f47ec01e5d82353c78abd16936a8ec979e0f6fe1f2baaf0f489	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000768efefc2b93e57123b7d2000e283fe6cacbf3223f9945d8127482f684c63fa12e7ee654ed659ea851cc91fdf227b8ef12cbf52f05f204149ec1e538bcf3cd1a4b41093e165abe9ad1e93ea601984f71dfb4baff26e09847889bc672d1b4321b3537dce6d8716f4e0b3e7042301a3ed2d3f0f156dcd69d1d0cd0d8d5d04e6a29	0	0
10	105	\\xbc81810a831ca0a8efb877e753049ae865028a1341ddb78d3cbfc210cdf4226c	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000054866be9d79299d9272270f4061143e4e3040b74e27a4963ac3d7183e22b592697cb0d040e047ddfdf1e5e42dd36dde877c5a92247f78447f1ea3b5660f4d6bcb9afc059d6b70e43fb3292ad15aae5a7239075e904d74e003c8590ee20b4e03d99c7382494605c7919adeadd84feec12966e0778ac0e0fe8d73d0972db8fca01	0	0
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
2	\\x2e7bf7a4a66e1c622676bcc385f842db5a88b9b54ac5b10881496dc94790d2e1
\.


--
-- Data for Name: recoup_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.recoup_default (recoup_uuid, coin_pub, coin_sig, coin_blind, amount_val, amount_frac, recoup_timestamp, reserve_out_serial_id) FROM stdin;
1	\\x2e7bf7a4a66e1c622676bcc385f842db5a88b9b54ac5b10881496dc94790d2e1	\\x9e128a2d04cdfa721cb83f9543f89f294e1f25de42fdae1773243a8c855adca792836ae88c76f511beb12a7bbcf07054e0d34cc69e4b4aad37e572f2e105e205	\\x2cd294e7481b510432ff1ee1d384f9875bd6ea7d1e1abfd0a5a7544dc3513a1e	2	0	1660491709000000	2
\.


--
-- Data for Name: recoup_refresh_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.recoup_refresh_default (recoup_refresh_uuid, coin_pub, known_coin_id, coin_sig, coin_blind, amount_val, amount_frac, recoup_timestamp, rrc_serial) FROM stdin;
1	\\x6f125d7175925424179ba7defb110950d079b6013b798c6995267bbf94396515	4	\\x9dae2d81c0c50d5b5a7a3a8fe83b339c4e0a6da67304ca119f20ca978130e6c9fe91687831e0ad64af4423f125ea9abbba562a5462e608b61ef9cb3988979403	\\x935b191a8350f9044c1868cb721183fd7eff18c0b52b7667a79b43ab81da4538	0	10000000	1661096533000000	4
2	\\x73d4401ec25f85d10edc4bbcdd9c7d72ab4e59f2abe18822d84141e38a585a97	5	\\xbb0a1585a4e23c2e8f5e920a65db1313f762c3d3a788928ebd27d613887c1b2c1bf5f3ee969ed3184aaae1d25eb183967f3e0f57c86daa4ec6a83060c3100a06	\\xf57d64cbf1a52ce3a8784d9b2d69715f7e9aabd05b158d4b8de501daa12e6d07	0	10000000	1661096533000000	9
3	\\xfcf758084042c52e18e9d39d769cc5a187961b8405a6bc04640989a338966ad3	6	\\xebea29ece46b5f3c9f326a45c854a0ad656b6fa46540a2d272dc51508f42d224f46d72e0606c51f4e0fc5f6883f753e50d8ef3ff0ff1f59b078d4d249fc5950d	\\x952ac2c71289632532f9fe611fe04bf64951f21f7f14712af431f1e802325469	0	10000000	1661096533000000	3
4	\\x7d2d2bdf968798e659184bc26b84bb448617bb551018db908cdd5a3c8a3cc7f9	7	\\x736e64619635f929122fbe5556e6ded5aaf7a2f4b44e24941947f87f0ed04223caed2fc41e8ddee504bdb703069f9b62a0e9efec789478c44a9acae1893e770f	\\xd64462793f84db776b67f4bdf818d19491d33700d0a40420f331eed9b5339c24	0	10000000	1661096533000000	2
5	\\xcec798164d716c391bb09bd33af790429e87ad59b64e97b2432168d64c4daed6	8	\\x7860cc9c89e8576619d1ecfb81ddc3047bc89c79e701bed83aaaea83e94e0de0df2126d499139ce0fb60c7d090c197e750f04c71f3b20103d8d517e54bc13002	\\x3754df74303e0d709b5607a2dc59a29bf2a1709e734b85c243b6aab877a5d315	0	10000000	1661096533000000	8
6	\\xc896103f8ec61d659da5d65a16e7911cda6860612598a3d362566f7e75f594ea	9	\\x7d068f24ebcffad0433c6ffb16469f252aef354bdb501cc2693ede80e3514a0039aefa2059e7d945ff31aa4d7b448951995b9748ae108d5ea725b95927145a00	\\x01d077d1bee22edda49741d1297b48424121ceab3e7fd5342f9f9de74a094be3	0	10000000	1661096533000000	6
7	\\xbc81810a831ca0a8efb877e753049ae865028a1341ddb78d3cbfc210cdf4226c	10	\\xe4108d353677ac635a2bbbbffae4465a53a162392390202f6bde4d4299b501509ca56aff49d6bf22f3fc010258d3d7d20942ffe3148cf0202b4a68d3a4882a05	\\x3ef23ea4718bf0716e319a758e9254a4d70e5a5a6fe454e94dd347de6d943a64	0	10000000	1661096533000000	7
8	\\xf010ff469ddfb865a622bfb4b425fbd4f9f9ba677badd18f878df3331628bb28	11	\\x3579332f97d09e4606c85692d6217c4888df212fe176c5d05d68b1a06073cee7da18be7a136e0480d3e4d6048a3f517ecd05c06062e1b3cb796cf4af3695b203	\\x9072c385d5f38d845e0ae758c73a563df42e93f5e97bb7875d4a964adf2c4429	0	10000000	1661096533000000	5
\.


--
-- Data for Name: refresh_commitments_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.refresh_commitments_default (melt_serial_id, rc, old_coin_pub, old_coin_sig, amount_with_fee_val, amount_with_fee_frac, noreveal_index) FROM stdin;
1	\\xac8534f0e7a53534fc750eda54110d09596192c600b1454241d081ed1c62cda6d088a889cd420ade4c900e1647ac0d7a760431717f8b006a59ddb4c67fa7e62b	\\xbc9b2f635789c6986bf548763e1023fc381a8dc940de811d4c95028e05afc4e4	\\x799fb336f867d164ec1d87aa0bc58a2c31a220032ffc6a2b548b7084c51d1a40fdc6d07fa4a410dc6bbeb71103dcb4d7e0f02539f55fb8a34a0f14400eccae00	5	0	2
2	\\x12426e27ac277ea07898cfd43ab3fd201b6d1fb68d557d9cc1c12834542f15acf9f1c2e08126143c069da4c63dc6d0e90534372ca0cea3b26261f49ac2660bd1	\\xbc9b2f635789c6986bf548763e1023fc381a8dc940de811d4c95028e05afc4e4	\\x2244b352e7e31afeb02893e2a478393c008c0d41a6364e665dc86f65f84920045e12e1177c7842fc011c47bbf4219b3a9371030a3ed7a1eb498507e346ab390a	0	79000000	1
\.


--
-- Data for Name: refresh_revealed_coins_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.refresh_revealed_coins_default (rrc_serial, melt_serial_id, freshcoin_index, link_sig, denominations_serial, coin_ev, h_coin_ev, ev_sig, ewv) FROM stdin;
1	1	0	\\xac5ee30fea681f5cecc6d6e74d59b6e4505d2bdae47bbaac07df5206118819ff4db10b71a9488c477c4acaabcf2fa097c2587bc24c6ee0c893557d8193d6160b	28	\\x0000000100000100c2cbadeef954f238b5b20258519ee8cccadd7f2ccad5ff254469d37f8d0fe6acd450b9139e3f4256e4e4213312bf7343002db1694d3e5a9ea45eef37c9829d97d6af6a16fad7cbf71dd64d5ece053b236e51fefd2628b888768dc88655bb9d4b7142e9dde6465e32f7b24083960f4c6ea10901e63fd3902cc96df65452608828	\\xb5d9e4ff50b836cdc43c7175194efe7aba361117f60b52c74bbf4aa7a0d9b4244f9cf906ce28a16240307df3d8c9e949f19a3ea115e3446a9119793d870fa600	\\x0000000100000001aa1608f44c9368443c2a38bf45d1830d4cf26d3889fb1ab10e9e63f40c8672702e3fe6809bfb2feb392fe50327d1026f04609b712ddfc8f6a48cbb4bf60246e1a41c24acb87ddc6855268fd776be3d22bdd8684abc22081b71527787669d9db24ee035894eea2a3f2bd80f283ea75ff13ebc8bd11fae44270921ba34a34d2076	\\x0000000100010000
2	1	1	\\xf43e248a4591dee8e130e6623ea0f5909459f1be721e74fbcde08ec13b39723274979fddaaaea2d6e55fd7287551eeaa35831cfb2cc2dfdb6e9aed854f61810d	105	\\x00000001000001008180c9fe0f6c40a7623c5a4966de59689b0462b34f16c6d2bce93f71348ab8e13a2c5c81e2ff32a840d45ca695089e79e8ca1c46d4adcc245c022ca2cc703cf717f8a846a677f3d7bf87bc4c570cd6b1b751918d082419734ec070b20e06c36b8474e9b891c79f6c0d2f06ea1830e5c403ad3220dc97d2fffffc516aceb690dc	\\x81989da3b27700ca91f7b1024b5c4bfd62d70d5fc40d18789f4f98428517321e30f47d65c316472a33dfb4ea50cfe39648d8e335f8eb066d781fdb8282947c2d	\\x00000001000000019784229ab2e7e0cd0f8912a3db324b4c8debe092ce893533e0656040f2637dd4f47781f8dc94bce3cc86aa333bfacbc09e2219a52fb004b240dc5dd1037e604c2c8ede2ce992b6308f5e7925b2172d1c0524ee4c0b3a3a241d42de88ffbc99eec522155f77594f414ef7dcce2e9b8c00eb61e3f8e00e0235e51ecddf4dd37cb8	\\x0000000100010000
3	1	2	\\x3641b8cee75c28ad2f82f6b9ea4edad6d383a8cd2e78b48de8c4e09bcfd07c48d00a29a579d739d2e712d380587f54ff15bc0e490869a51a6cca85bfc0e75302	105	\\x0000000100000100136cf98f176eca916f3e5065ee30e83b0b98ea46445fe0091e84a453ecc71cba242b2eafdb6c1208a4206d21520ea1e9121644f7a08efbbf8fe387e544df46f74672dbc715cf16b651269b107d99d8a490189cf079033b7b0c4570836d9c51d13df0479fa6ecee3645eeb38d0492167363059443acc7d526e523a869a58f95f2	\\xe7048cbfc29506ce18ba16ed12d24567277794d93dae1523d1593cd202e2fcc437e1b18a7816a83a6b6aa4229a9a6f3398660f7efb0cd7276d03a8dca1d0c409	\\x00000001000000015e6e80d1dd9152ac94af142e4b3cc1a8e6d437a9442675a1ff3ed0debf9595a09df56fde9762e4cb5076bde84d9543da42f1a99c12974773d78a663f182edacf1184731b19f651e9d3b3faa1257f703894fb152746957c42706612d39a8fd18969630a31a56dd77bc5500adfc1576661063ffcb80b69280e15efeaa56e9e97b5	\\x0000000100010000
4	1	3	\\x221ca34d7f5f5ee426cc73385958cf155b0a8b47aa1f8e543fdcb95daecd7f5cee5e794c4c39fd6cda0d664a1fbd9230ef8711e1d1faad5ae503f3dd035b5504	105	\\x000000010000010096945363c1e46c29111379b5694224540116002d0924188c2a9afdc8861daa1f99acbfa698c8e125b30d01380c8dfef5684f3d1a15a3cc05fa0e7109bd27c7b29872fa9065cb4c90376f56bd00da31738651e06f2e55ec79b597e09ae53894a3c1a125baa8d5688858f2bf74eef36b62d040b1df7b6dc9616b5518d7218dbe49	\\x5a4414fc2b91db7b48559375f441093a8d3381662705cbe0cf757c241d7864eb8df6a6149f6c9dbe14108b0e6d8fecfcb66c3d164d08fd7b9b20f0e23bb736e9	\\x00000001000000016023a145de2e0db7b0a8312aaac759c1ed3d724773ce3f227adde2865fc2e41de5758c5a201d98a6d4fc93576396cc856ec952c312080f30bdbe25c7fffbeefd7ae191dd9b2cee99137dd02e0a924f29c2b366938c843d79689ac63d4301f67c159e8c0bf929ba2fe23f4daef1644f8ab113a844572aa7bb4cb0304427e9d5f9	\\x0000000100010000
5	1	4	\\x9673ecc4a7f7d11939877d14e49a2a08149000c277d7c7bc9d129ea528467cb040a7a9a7e21b1c6bcafbc21efca9fd71721f1ded0818b70e9d4508a4b451f300	105	\\x00000001000001001eb0c98dc0e9cd67038a2e0d2dc330da52c6607de3d0abccfdfb33242665f332a3486746e9dc5563512fdaadbb4022462dd090d2ef5137cbed9b60b5f73dc133130ce59dc6090b56a958ec54c763f648d694a7b8bb6b85b54981ba8e7d24e4885ebbe6367396a26dcc20dcaf2080903c7ca5fdb86ce1ce6544d7d7920e256c98	\\xdc199b192b1fbe0233d523918a6d3b703aa8725c7199ebe8ff9bd080416feb4fa98a2a5e2fc15f5b6994217795e8a5290869a464380b5c39c6e293d62fa4875e	\\x00000001000000017821d5f3a646b198a08db0085853208e9c3df678f91943f4f900df8ed73faba8c038a492744c3bde0690428d88b192f75ffd6c0036d448367d97142a3a5aecc4e860e0bc995b8b729b567841e19a38d7694676ef879c062f77d5a82f4b2bfeacca4d38d8a8b4d04a0741119e3eacc0674be3be34df427cce5cba1855e1fc36dc	\\x0000000100010000
6	1	5	\\x4aa2ff6efb458d3c1ef4b0f2b3e09ec1ab24ae8f609ee5f1e9abe905e122230ff4675b4a4321b1fa25e3f114837f6dfa91cc5ce6b8e36f921a030dcdbff09c09	105	\\x00000001000001005e8110427b5684ea52517f499aac68f24aadffaf7ee590454cd992140f3f619b617e1eed917ae4605ceb02f656ef8ef61616ed7ffe8b5234e55ceac3067e63bfbb2d4f7dcf059eee2bf75b967f7c315eaede4a46a550417c8930bbfbaaf5f1ec1d4c8857b7894fbd7f5fa6e3268ab407ea340c9af077cc37eed29668fbb8ab35	\\x66891be631d6d433f8af106557052785e5ce1b1f7d690324cc109d200631111a9f205e6f4591518bb47ba2453119bd13bbc2db81be0a5d452a289d6232655b0a	\\x0000000100000001c48993400992c01a22160f098414fbb5037eeeaec62168815860162909bebb1d16ba626a4b49eb306fe6032d7f527b30126e61eaa32f0198a506138d322386b0ff26ddba8007cb81e4d9bab81dc6592d225361e6c3b702e0ec5613107e22c1dd735b0f6fc453d2ce9953e88eb43c42794c716831f5f039e1abf5583b7aebd49d	\\x0000000100010000
7	1	6	\\x32400ac3002a1beed96eb1945550498edd3549f61baa837d9e0a4dfc49e67a0e480105a5884ea7be63cf178e8eca3a65a129251607e1e5596912a2d85691010e	105	\\x000000010000010017afdf064a8ce601e643640a93d588d89416df2f26e9303dccd7bdda2c89f9bda55a71647b55f6b557372bab8184a50bb1d519a3a5eef6e6a4ad07549b20a0ffdbe83fe354cc2b07ee43fdaec59ba564c30f4bef1c6991689d95e98c2b34f34a4fa373c92cdf82544bb42f01f89f6a48d6a0c76ec6f76c6c83909ea40e7324a9	\\xe0dd533fc8e61e489ba4dc453d6694bc3a3fe5e7fd19a010404e2f8d27ecd163b9d18aa4300c12f70b9df5e8c2c6c9a3c3cd030f082f13c0bcd8689f77a2d1af	\\x0000000100000001bdad240c9b0f800f1de5124b0d5752c3fa53a1c24080f8a1bbea1c6c224a7435fe5bdbc99ddbd20efc3f0aa2703be90d11eb155bee8e9ee6b8182a6b2ccdc70ec6ef0ec0fe2c1ccb5bee32863aba1eedd0b3c3908295654c53e494a93405792582f4b27831df043ac7929ba2602ce66da79ff49cef68e9fe8491d647329f8915	\\x0000000100010000
8	1	7	\\x418fc4d1924244dd3ef96aa39b1d83b356b5a9f41a52cea5ec7369e3269fb8ce000c4eaad47e772b84afc3d2b10736f4eea9ca68af42be0f118306256c5aea0e	105	\\x0000000100000100198731e424ea7b903c2c74739543908811690239503dfa60d9bc913383b04d3298b86beafc34e73ba412ff70e7dec3139d0cd651512c232f803e0509f971085c0db76fa096bb66aea1958547a3617c314ddda84c749a4ffd43b25e14ec1f66a6fcf52aeed7e978f63feb126c96d2fddb353a67c3916f70e22fe67b9cc8556723	\\x6ad0da013940ee039a8eb8195cef0dcceed974fcf98f55e1e9b39ac74ee8a39ebbda03793895139e2c93350186734d561d4f3756823f7d17da3726a11d9a3b63	\\x000000010000000133a072dfa2811cf5f15de2c0b51c0ca178bb4938624a6ae069cc625aa197f9a900aeec6b3edea96174cc0abe0718d1f735d5d626ef49c71b26a19cc9006dea0429f6082456dd551c2d76bf2e0818e3242111cc8964958566196abadfe0b5e1c7faa7497169d54b312c3d6e6321bee8fb494e0cad0b069d0228015a930ac2e573	\\x0000000100010000
9	1	8	\\x3b3c2724055234fe1b629c2f99e21105d2a8c8acde799e5d3ff4aa773956ed4eacf111dbfd5fa92c773a6675a7c886972c9232c9e6b973bc5ce33b70b614dd0f	105	\\x000000010000010023adc4c0d0de68357d8e844da45b25c5be546b3eb91f29b4984d20571324e3ca2e14312e60c4b9bdda8521b27deff042f079cdbe8935fc8f57c31a240f2d483e470f110d633517486452001d82648d287d44781479855891ec5bdff8ea349d99e356a44364915a2ea83fa057e61482759d8b3cf67a0cccba61fc210574396bd9	\\x6d45e79e766513318bfcc4e479a9b3319203d2266ed6e648830dcd5d30940238ec7e458abfb097b2fb201a84f25a97a86d3550d05b5ad0c5667ae7c63c534621	\\x00000001000000018862915616bb8bfa5e64a30a0f553138a8cb083ded07b157207719459b78269dc0d971c3b72e5c377e8afa16227f9baa1a242db3eede62ecec35952f1cee81c1b227669695f40b42f05c4de44f78d0b3c0ea984df430b2d2e9c6e243f5c2ceb94c673b6228df2e33e5e4138a8b5432f02af72f60f4e69f35d7ebb73a3577664b	\\x0000000100010000
10	1	9	\\x8aff897c69f325759f8fb469243c21b4391118aefed3a32631923775c30bbdacc6c745e46d9036f033b007bd1a39cdb5e9b3e58e21903af3acfffdc89c77bf02	74	\\x0000000100000100862cce32951c7b7f69d9b95e8604f18901fb182c803500843155a58610e90a65c5d1b80703e8867b6aae719294d900e4d294bc2dff5384062369da4775a71174f6df6babcf76eb0badf6c5c10afabc8a9bde4cf46b6dbcb7dbb79925bae1334f9a2f764d382b8ab0ec8e16460d7802fb96cb4b93cee939e4f748b002a6739618	\\x20c0c2e4bb8e968c5881e80cbc03ae9a7c4fbbe2e1f9e783eb84be83f88ee5725ba55bab3c3af6f67679a297f36dd3b49e895c1be49b300af7ebc5af13162ef2	\\x00000001000000019a404035a9084777d5dfadf3ca98b438607a54b47a968a2699deed70d02b6f5bccfeb0f33b56bf70e5dd552697de566502058d9ed14a380f484fee677a18840edf065ee679faecb1460c9433e0273d86ce1a906bebd42e624dc5538562fdafb710f2c721f250bddd5a48a2a49000f4af5725999165d0a26373e42d60606d2dbd	\\x0000000100010000
11	1	10	\\x80f9e8b87dc7578603bd5e13fdbf68d0d7b9c20ae068858a6ff6a5ec0a1a3fcfe0044b6f0c23f92db9e64e599692129a4309911c8379c3e54b691bb4a1f6e80f	74	\\x000000010000010052b0a77731f4a7817210725f5ba8b005c52032d6b00b9cdb227d385d83278d071977aa32825aefa1db5f18d854e9d9bcb7de59fb3fece65eaec2070824a04f4c15d93a9ede80e4f44a1bdf51e90a8f52296f1a3d89ff77f4a660aec8c29b646c186dc8283325da5be5e5455bc01c17c268c5913ed5caf44a5c639fe5bfc891a3	\\x8bfcb49beaacce355355b6eaf963f52500a250726a43e82eb6514bf3b4d24f09281a70929aad821ea1d8cf1bbaed40400fdb8793fd1c831f4d69e46d3b0da016	\\x0000000100000001537e1648cace32db05fae7b590f012167621d68b5d9dc2448828fed50a0ff4d132988e53b98c70fa45c2a15bc4bc07433cd312c18802d1319e54df65fe39db3344a479166f8c4229141a4c01d5d1985807fa76590f7482e8c4114bd4e9d120e1ae529da366d1c5fbae7622a1b07fd39e25320203ba8c00fcdd3e7efd77873b70	\\x0000000100010000
12	1	11	\\xd41f62fd2a3bd5007e6f5ce75db2ee37f01b483ad3039e865967f3589eee6c0bcf6d392ad689e3226267abb37b0396708fcd839c4497dc0d4dd4e5d4e1f10209	74	\\x0000000100000100743aad67e1f7609a860658f60efbf23e5df4427944059d54f7ac24f9ca3cdaa217317a0df47f68958f65e3f0cbe3b5e654f86d8767a1db0474d9673324da505a933a63e98a342f1e6ec2ccd5ad68eb919e620f75f569e81c8f8deb627c31a94fc66c53b4f9cbfbceed298212c05814693bbd8e0e364db4277ebd4e4d62792ad4	\\x8df80af95c32c6b0a0328cc80f7235c9086aedb0692f8f04d2a9f69b9589784e2fa79166e0523edab83b6f1777f39d34d68899fb65a86e573055df10d15f55d4	\\x0000000100000001456c393eb89a45178b98cdddee27688060dd1e65d9274b1858606509135106e578c1e756f84a63bb8a5e638ed161bc517d2b16f3d78b408343538da7139355d54d16e63d6240238821b1ca1078a9feeefa7bac9a55b4dc02d47e417adf22bd788bcc8fa565254e90df76a621ce114cedf96d2a6c5176592ca072ff8ac205dfa1	\\x0000000100010000
13	2	0	\\xd694e50143b80ea690bfdb3f069681d61dc158c24e32e13923eedc4b416a3983aeb127f8694a074ebca6ca4280426fabca41ce966a7c53b9291bf0969ebd790e	74	\\x0000000100000100348cca2c9ce1a47efb956b10d8ca696a0d501bb3c1c390aceff4f05be1db7e5ecc4f2001cc68af12a57921a29ee20f75ec2797b411a922a9dcf5f205ffe81f8531ec03bbd95221bb77dd7473f3ef44efe5419c3786cb8917425c5d3b6882f911741ce06a45cb905bd0ca252e41d8121b1d863f7f5fc858d533d36ec30dcea8e8	\\x5907b1a4e89ed1f948e2efd91ed8c637c145e3302d2c688eb0fe8837aaf7035f0c1e53d02917378992b2182f68aa0da6064a3cac0856a182ccc1b9216d45c68a	\\x00000001000000014ad964572b9172fa48999f7423b033b1fe6e2f51ca0cd2b4736e64ef517b05143ec65658831d78ce161c5dea5adf5afc5c75ebbe5c5d6da6deb7187956ef290dc998b421d443716c2c9e2a4caec51a2ecbef5366727e9cbab867d9c9fe14c93ff31ff6f54fefdd28d62508de3a84c57098daf1aa6d2355fc43cd5a47121c60ac	\\x0000000100010000
14	2	1	\\xb05588e042ab809c77ad875daf5797cd31a38969c69cbfb08b025606d8a7e61c07cc0a14d81c807237ec5ef4c6b25c920ce22582c4dd2a76c669ef9ead1cd704	74	\\x000000010000010032d4d7fed1c422f3f5c51aa28e9beab4a2f74d0a5c3a8810af05904b839333edaf0219100973c169a601f67401ecd6de6d916249118ae8f71732ce7bff15fac7f48345f0ea1a7758b929b8eaa9e2523c700b9aaeaf658fcce56f20436dfed444a9fb5be993fdeb3b1004cccf530f07f4c4581cd8ce3977ff491927c66926db9f	\\x8179049f606d865daca27ccd694a0bb2026e1926aaedf4c8acc978bc997740d6a599801b50fb1f388fc05bed678a08bd457314126e73c4b19d7d6a0f5cb74c19	\\x0000000100000001a153fa1db7e473cad1b6e29fcd7a635bbfce803d5836d6ccd5dc04bacd6c6d9b7f5323c993a471284db429d3fd6015c858e0aeda71a4361f6d1d827bc06544f7dd3e8d696660f69a8583469832545c78fb1cf670af5d56dbeb657a2660ae1ecd738ca118f265d18489ed414c9fc0e185f4b6a24791abaa1523808ad673eb1c12	\\x0000000100010000
15	2	2	\\x58d93bc5527a402ad1d8c86162a48a634e57e61ef82511b4e7aac977afe661d4184d04803f97e199bcec0e175cc46798f8d6b9ee7369cbda813a000efe80440c	74	\\x000000010000010087ac1468a9ef3af9c3d704b697fef5f8bb6600495927a39fd6a01bd8cf47f782b425ad2e0fd072801b140f01f70b9777294f8c9b5da669624460700c3fbfaa24a960b9b08d59494c3e0fa8a774531aca104f7a6f3952f6ed13d35a6ae4da601343af9ab6a6bb770b18c1cf5108b072db24605edabea887fa873900c2545549c9	\\x7f1d0c396020387de87d1e2ea9229e667b27a405cbee5fd481765ef4db85f6f459e554cbacbd8849a731c4b3274d49afaf4421fafbf69fdedf31887c05f075a7	\\x0000000100000001af34adfd05f59a2a4759576db87811f8d0cfe7c53c245adebe735ff5441ab200c28e35ba40f8be77337113f5cd5548451e27ee8e55f2517b8e1653e933b758b1905ead0b93b7076b7369e1052f6e9dea8a46f5c19f493cc75842e9227e80fc575424f2879bba2274a2e34563680fd2681340a20be3db82f360a2ac66b347f43c	\\x0000000100010000
16	2	3	\\x1fe81b4579c3f779cd787c5b4cbfdc6a74af8318e76321851b18b049c95db9dcd4c59ca2af6a517a237d7cc4e5fc76e28438c10a5bbcf975ea9052bd2200a408	74	\\x000000010000010070271c76f44903e7f8fc75ae8723656aae1e5a2d4f9ad7c03a77898717bb752a053c21919650c8cd85173283cb85793bdb24e8ef6e8bda64d19b80c9e54d74612c29fe7ea631ea6bde7834104a6d7f651b24a3a19143438e4fabe13ccbf5fe6b8ab5db6706c5589969da7c92a84438abb355a2ee48f36ef5072253cf5ae261f8	\\x5fac0093b7e480d4c902349a88276a30ca683d2ed3dd5029ebc034d8952e9b73c67f64ac252d51199648f6edd8d19a270327f164d33d045764b9d9ac3c6d5f18	\\x000000010000000127cf542530ea05a830e96eb4a6ee5e7fe85b5da8cccf2deaf2e394859ca0902a3d3a238088c8520ade1d71ec6d3d7b1a7e1dd9433277ac57af9bd2f03f9ca34d393b7457b95f4481fe99ea21d545ff7b422fccb527d906d121e2fe1e9c17e8796ea68ade0a5b047fdd3565c5dcb411ee367f63e7e0bf980dc4a873cc75d596ca	\\x0000000100010000
17	2	4	\\xc5f18b470907a1ef1900d06b369e23c0e1aa9851a2361eaf57cba888df2a9c6cb754c6fd3f0f265a2a195656a7afc87af9f449889d624875f0938fada2048d0a	74	\\x0000000100000100bb759b4e3ab64e540486a1e0deac604c190f6e4346efa890258601d0978dca70897a7c7cba6795e175b0f6c04494676faf889d30a803019dad818524d822261edefc06494af639b9482d03f201a2352aaa10400a18195147ef8cce158f92b1cf0147e92e97c1bf14f3f84531b584393fb1cc7e8c77285c7d66594d205af9bb62	\\x7078f6766cf0e0c0ffa55e116111928eb2786ddd90847ba522689fc3d3ebbfe9e251680e96c1dd7f3e639393da26aba02c444daccd960cc35c864a3ca68b1109	\\x000000010000000107d39d5d9a15cc1f701a81c041b53fd60687d32dc5590e81475d351405bd6150a429cc12fcc2d95f32d2c955cafaebdc37c3b66e95d84cfeede36d86f23c2d703bf85f43d9e2a1aee80dd02f1e2e5f8887e83834707d33f99360a54665eb101658cdaaf742ec6345f8b03ff9700c3fca59aad4ca8fec2a408d9c6099da137f92	\\x0000000100010000
18	2	5	\\x46d48f00b3281bbc84675f0c4d44437e20528a0a27d9ce830acadef54ebd34016edc09aea33aa58146ee85b4172613468159eac9b92a87fe67aa0b649d70c20c	74	\\x000000010000010092b84c1a879dee49d7624d4ad9918c5b07cc95060bfe55cfc6b65e7970c2afe150194f2da1c638cf8d80a2ce71ac6e3154721fca8ea1ce1ebdc38d7a8bc492399936e7c120c4aa9ecddb40c71fc20d3d362633323482b126b13f66dd71546b104f6735902af45293b15296a5a64ac032d8c5402f64383247a02fbe5c4fbebc04	\\xe0567d78247bbcd25a12a351e9879695a8b2a54890bf231c1a553c4098a0d6c675b2220e6d5bec976630be9789c0d52ffc1eeac378d4baa1ad09df564c87cd3c	\\x00000001000000018adc0b3419e89e8855c692d93acb0c87a86d28bb79075a29123c563950f59ea3bcc1875363a07692f6f94a56648437b091d9993633678151781b189e7731779171a81732d3ad23835b746623dfbd6ed4ab895937915769f5c9a08f65aff32669c8ac8b939aefd836c71776ba284f54e8a7c1bc8f4e8e57d3293319385f4fb16d	\\x0000000100010000
19	2	6	\\x1d17c363cd183ba360a40e49f5b7a71d4cc327c46bd347f011bf3d015fc44eb45977255e9273202c53ff36a780ab18b169c7d454d0947f3b4edf98705153f802	74	\\x00000001000001002d33bec693527c99218b2d124dbe3489b9d0a762a231ba6a559bcbe5e868c4ad4d86d143cdfe6bf095261199518225548c0572216c0428fe4dfb4aaa84580c1c6a4c9ee3bc22626e6c1ec96fbc36e24efc4776385f00ceb4590b441cb8d88dc23152573687b94dd96bea118eb4b86aa51552730647bed99ceaa4aefd706013f8	\\xe11b5475dbd3bbe7eeb241dce6edb3c90d93133dcdadedd67d665e2d6b2ae5476e3e63392d2abc8c511ea7b1a57494beba340a28d72f7bfbb0e0dfae4df924f6	\\x00000001000000014f158f7f5f7cf8da9bada6e2b941da96ff526b26ecd3026a4c3687212a9e191b9c5989ef7637aeda3a0453605aed6294d10eb018f51380b9110fac1ca29d129b1c072586bbdde6e49eb25178990bac3b190c8ae5632e3154d8a1a4d06f837df0f12fde41c1f5222cc599c3f2482733d80343045bd0d3b13384ae3f4b3e2e05ce	\\x0000000100010000
20	2	7	\\x88efc873fec841fdaef17ec79fb73eb9a5843f04a87e5b6a62bc33b6c9d4f0a18a4294a7b828076ba53c6266f1341226c34e4c96a5a5a1627001b695e6e86b02	74	\\x000000010000010066588a6124e34acb0962ca6d40473e8761da4a4192a09ed274e42d745c7e45301f20f8b2e9d10093aff5d5407fd9af76791548854761c5ea47102c03fe2bc4059d04224015624d96874bbd906a3ee14fffe63b644ab7dc8ace209feb366f8d5cc3b9da8cb3dae6e0022f7335945e07a53ac5dc319eeee11894275d9a89143c58	\\x0e642bb97328867b056713cad8326b0df51f3bd9e05561641b537dfbec7ca9f414ca95ccd1ebf0069c82fd7cc24c49bec222b66a05bb7173ba45846db4e1bb82	\\x000000010000000140678559c00a4ee46763302f9f07ce1c522f93d4f63d1bdf633875ea0df5a4366f35acbe48626fea86509589ffbfc8efcdcf2edd65babfaca38b47c6c1b17d1a58f2685f0dbb095252c5694e26635cae9a3886703a6af66e5b84954748ea13aa481a876540a75d1de69a65e7a2e48770efb3428b7f14aac05bc1f615658449d8	\\x0000000100010000
21	2	8	\\x4709844697df58888b82afe96a0129b0aa8ac0851b4159d60f50167876f45a389070297f2ba74e256ac4659261cc58e04f96b7c97904f816355dee184ddccf02	74	\\x000000010000010045bca6601d4e380d644a45ff655d8f130b5750be6356398571b1e8d8c869bb31bc5f5440b5f64f7bae3d7bf151e21b3d996818c8a01120026589666b5c78378cec3ae9b42bd2f21df7aa46f006e2bacedf8317d63bdfa47bca6f081b5d786a3d5a5cce61c5a390eaf04181513456c48b8027f055cdce05a878c664e0e8ec2a36	\\xa2f6a46fdb897b74d68402ca6af7f72365a54331d2da3eb81847e5bd504a7ea82bbbbe86407a10a296a3bfff277013cc1a3b4641af18a9fed1b249f41fecc3e4	\\x0000000100000001577760a79fb34e04fe520cdf029a2f84ec3895e673894518254c4f6dc1ac3b49bb59c9fcf2587a21c1d1b3c2ce6d5adb0d60c17abdf4332e3a3b0c595ef9994ca0c7b72027977f36e7508a11ee6273bb3779cd938522d0a517d18329a1f65032431d00d95638b7c0fe09eb1fb23bf59a5b395d175c664ec70608f93f02bac9dc	\\x0000000100010000
22	2	9	\\xbee2fe28ce9ef88fb24c87e9ffa74abe43d2fa8498b32cbe03a204570ddd403de39f76400f59f0cce2fa98d64af443e15e23a3d6d493508cfd7b7a8ed1f81902	74	\\x0000000100000100d2b984846b1aa41adbce9a927de942f0f4afa1f16d2d6b5f42fb8c5587d2399df5b6f16a88f71c1606bd39c3b94cb99b2bedd3195948c3758c9c7dfc4e774c360bcfc78579fc5541ff4171b93684160937529d38ef9faaa326e0de09b95374b32642114256b2dba100cdb7f72d3c2f76cf4609208bdb3d4894c1f878bab9d50c	\\xfd4a5bbbe3a10680d008648f97c80983eba6d5acafe33451d83173733b87ee8fcbea8e942a1b6e2b737783b50338186c5df255d4b1a9b78b8cd9f934da7b29ac	\\x00000001000000010ccb3d631970a5edc8fcadf6b828697161ba1ffc1b85971f9c78ce93ef9ae0a0e7e1df1ecff2d3473a4aaacc3514b452d9a97b7ca329fdf0fd4aae29199b86802f2d0ac09fca8d663b06bad65f685fe72136234dbe660703032d1b08690505fe85d8d76ba10de264b2e63077b71859a076a13fe42867d214f9b59f0950c12080	\\x0000000100010000
23	2	10	\\x4206920a392c46593c370ece5e6631f9cdef0bc164b84130b9ea63739507aa83af75b7038950600e37de06d17b18c0b1a1f65f45d91c3b052edaf759f4687c06	74	\\x000000010000010079974b6fd61db0a8bcfaa8857082e8516398884e3fe87a9a71931afb3b6d845cfee5425721446f2bb0170cf74a115bd569fb15992daf4b0c75b5d4b7f8de873fa83c2a86aca54921da6bdb2f186e014cc528ae65bd16fd66468690e67cce09d2dbe1660e872b2702436c3930dfff2d7dd25cf3a2ab8ae0f7b4e1215d5b039efe	\\x6061a45907ee2a159981baf6d7621f9a849e962239439d3dfbb232359fbb2b9ab1e53adedaaa26e98d455e6737c3fb653beb7dcb51158d9c8c429b1f08e25c80	\\x0000000100000001626400c83015927b1beb7bc6d0384daeab3205f4f3bc481a0a0f55674c3519c791baed3d68e8ba933a6443a9a9fdba788c4d2c55dd1a4904d4955647fafb60f11d7eeb774ecf0a931470be214cf313e74306abcf2caf8b3be7699077332f9e0fce382bdaf323162ef00a2a029033622ceb96fd0a7b0896dbec75013eee92fade	\\x0000000100010000
24	2	11	\\xb8a86438f16ba7d8dcec25fd88384e7cc416472694e0da37abbcd654f4aed67e4a3d2a3b382932419322ecfb5b2328b98db0dcb8e965264d10687f912a358f06	74	\\x0000000100000100ae3e1091c707096b49b09aadf7ab49def4fb5b02546b9bb2cdd438db0c181c911ea018c83fd9b7c2d38dfb3cc8d5df8ddfee5c4f97a4dfdda813076c55ad7acc46a111a35d766ff7c412d4a260072aba4c01aad0590ffa5886f23630f851911f6bc3e571f2f6082831fdb0b8bcfb122f52f3ae788d5bb3b7bdce7423397385f3	\\x5b5211ecde2900b2c435f4026674cc1b2727c9fe009888239bf530c4aa88782486fa64c56c267cc4c0b692c5bdcb958a051aaca164dff9d07cc92a1d4aef1827	\\x00000001000000013f1f3e1377d3eebbd68d9f9d1cdb12cdc10e1ddc6bc12ee9a4dcb0da14557247fc2e8a1e0e053117ea7405dc56bdf67a8bcdd82f5780162944e30f2b82aeacb0b837e4f191bf0874587b15d7fed319f47b5c68245a0d706e86afd9fcec3e9292fe10cda659316d9577f569852f6fc3d1792fab3890737520c56e7f72d0c1b87a	\\x0000000100010000
25	2	12	\\xbeb7b9cbac6fd7ce15dfe1bc457015559c76f8547a22269f54c4695ed1228a1c0c31538bd776d786887c92bc91c4228f98d0f2b8ab79c7973175d5b8a2165f07	74	\\x0000000100000100387a1c48fd95166e7ee1b14d148b8c07bc4d917595e13cbe205aa354e3491ce208c602eb1f911083325455de91b1dcbf4dc65d0699d02425380a22369e6d653f4fb57469a43b330bae283ddc65c14f4a45e81aa0fbd0ad1c66d668e69085ec06691414c0c06b2373ca9de25ae20b67b811f4e98c8ee05ee8ab8298e022bf20b0	\\x005406fae9160255c18a5dd4a5b149dfc06a50a2d182d9d1e93cf8efea759d15e70b9e7675523ea6f796ee704d0cb1a84c07c77e4f07bc3cfa704fdad7e8b65a	\\x00000001000000010aacbf2295cda5030d7aed4233fa31c83213461ca267ec3b780a9983ca9d7a30811dd1b18ba30a900949b72776d3a3a8d4dac7455a9455b72e646c864447b458b0b12cd9f039b817035a71fa3aba3220c08b150e9f32be68881e8a3656ac8db9d8533dc761db27bb4c7840655a5a5e88bfdc156cb856f5f8fb788b4755f8557d	\\x0000000100010000
26	2	13	\\x14369402c7adc9e6e33ecd5cc6c59f0ea875625838cfac3a47008308c724bffb5caae0693172a3f2f38c1c9dc88a5b8e52a34775dc3bf4ec68fb3badbde0fe0d	74	\\x00000001000001009aeaa5c0b5e5a311490e263912e59819a9f01ec3c825d8f5e702f603b8f5bd24201b3d9a5d9b0a3ed44d63efd06f51111a169d429747bc56bd6b40a9a0e5817fd9a11a1949e4a4d8604f1fe844284a8c313859fc5c94dc2e83cfcaafc40549f816d752e14b2df068f23f1d814fd8add4d6d1e21c7353f9ca9d22e54d0c95c39d	\\xaeabf5dc3f254ed6b92b7636ff7a16172659b2b77387214774f7c73b14a8496ec6693d3ae813c444f041f549877970f14d5a164a82e7b0e045a7c0456a27f0d4	\\x00000001000000010c251e5149454b02c985fb9d7920c2799b2226903ec45fbd5b6465fdf09e6491225ace2edc4fe61c4ce1ea5f924959aa19513638aac73dd2c4f05c4ad9e9ea2c2c292add3304169fb71f34467dfff9e2299be7678aa967ad3bc1b04136c6bbeadbdaba9bc7624d10140e7e9632cde6a76b0c669ba7dceb5fbc4c798e54ceff90	\\x0000000100010000
27	2	14	\\x662d159d058359e28bcddcca89aa1f82a1b6d78b037307199c8428a83aed28a03bc8a9de013dae8069e14584db79cd63e5546085c159655631d2dde064838e05	74	\\x000000010000010085c58f83cb25a51b758679d1ea8aa6bb5ec5e3894f446f03db4c327b522c12ec5fed7f8d7f0773e48f9983e2d64204178d83cc0f9562a476c0c0e1c244ca09b38444db40ff12c290069e077fa48ecba85532a4ac1d8293714ef0065c7d51f9c1529515b5f4f14f9756f752454e33c2576576514dd6bfbc92847e901002fee5d9	\\xdc525342ffc02407c0fb5b280e50de372bcdf1eb5f8b74af010e8bb8e4820ebd2d9593af38a589091a5f0b714695439761b43d0f573c6e91fa8b4669bc7810b8	\\x0000000100000001e7767be48ed638fead0af62bc10e8f2a5beb40c9889b00ce5939b5136b71434c8f8f80f1729936a834905d81c95ddb66c7ac3118e2d405292de0e7824295a402a8e0cc77f3d2ac7815fba40c203af934b69582c10aac1fe8f4c9104018c4a3a0e2622e695824785bdf659f83c259085cac2c389559b7570d4c2838ccbd6265	\\x0000000100010000
28	2	15	\\xa74a9d015ae16860f82dfb30b8f36fe76fc5268233041ab7214f42ee9dca6a94f2c06cb4b59bde0504795c4c9cf8803ab212054351b6ec5e6426e9eae6923b0f	74	\\x0000000100000100a631069cb5f60d82d395f61bd9c174a52f8916734cfeb2a8ac35f3540c8d6019e642ae6390007af9796cf2b9b3c911c7316e2e1f075acd554a233563400ecc29fa2143031417d8034df4ffa3c0c524cbfb57777b3025c552dbdc07a19d35f261f86d10843afd392f8c6064a6676c823ec081e3fe98efd73cd5ba981a6e005565	\\xc32f223b8a1a177f9ce4a6b832f92174abba252d1547d9677a1098f8944039df3fb77f26cc2a8212eb10068adb20a42092bfa5d58500d4316705cf7419c277a9	\\x00000001000000012c48744c09bc78b32c3849534d1a80a5e0601da4c8916ac6bdcacd75263fcadae7348eeec11d2f8d49fc15e25823615a0112f4f50d796a16eba55502fe9ba641f1baa92b9166fb591bb55c06b21ac9fc3d9ca3001c0779f3c9646b10b81e5e022896f04bbde5497436a6fdf1a8b2df459a90c32fd5bb4e786b17615fcf5ea792	\\x0000000100010000
29	2	16	\\xf12a989533687b7ddb04f605d931a92e69a91831bcfa2390952e7302bedaa01f81b2b6a5c5b74f2025460b8c280aa279302df86215d27f83a38a6a1bfe545100	74	\\x00000001000001009abf1bef0016e472ae3c20cf636368cc1f2e0bb04187306827cd3495e513912c7e55d472894655ca84a2049d5901a2c1c76f0640d253b52431b62c370d092890abbd519995e60fd04262486e22df98d344fe29163f6d63a2276c1340adb085431d40114652ec67bc6aeb140595db5db4a65756a65462f7f6fc4c40042b211c85	\\xe9d7d0345594b674b82dbe0e9751d3471671c7c47fe72ab87d1943ad467d660cb1dbaded65cc3c49cf7d16f0c3fbdabfed764bf581b20ef0860dc34dabdde236	\\x00000001000000019cb0210343e17aef8d6e7af849da86696cad73876fcd493f5ae65813a2010a0fd19737529e600b0ec38ac8333edfb60ece83ed4f3babcfa554ee5947fd9433d64babc74e1b8f2440b3561baa90ac9da0eeb1aa229441bdff1155cf4f9d4e8f0fa2abb15f7a0439f6dc0e31f278e2bbfcdde700b879c9ecd447c2aa3c430f2f7b	\\x0000000100010000
30	2	17	\\x48894ca2af58492df3d3b8bddbd580cb11a135298b7885692cb3afcd2f5617f22fcffdf3f5f8f997df54d22488ab35f79b531baebf5ca4b7c189ad81787f7701	74	\\x00000001000001009a5d0fa2f2e0bcf39a5f3b67c0ed40f0fdd6f634325a272697bd5b5d302c7b595078ff28b6becbaaa42035cc52088a78fff4a428a07f1b50f2b2787f152ec424abb304dd37c872c15afecca5829271534e225065eb6dc913630c24620d741d4040cc42a1b3c37a0c11cc6e3854254fe037cddcce0a40d64de9d54cdf4250d0e6	\\xfd42fa4f38cf5c2b6e2e2e25aca28750d38d03b88cd416b14f7242c9864f53ba2ca951cc2e22c36060fa644a8764335c8eb4a657c8ba085669c1348409805868	\\x000000010000000115e1646ed16661c594bbfb44c362583fbb572cb01407fb7259c88b36f0f55ea176270109301ea9bee5a19eda849a2e3305a70a5c2ac9185ae7cad52271964276b439738b060b94385bd7e44c34947c53ac386d33dba4d6af5204023311a0b1a7aa2e1ca7f26574701a38d85403e19545b87295a10275d26f6fd0a8252ec52035	\\x0000000100010000
31	2	18	\\x4ea5493c561ef64f65a8e4374da6022724df907a5e4d3c92964c4f6aaa8719bfa5f772766b43f026943d32bb05d8dfc76190d0a450728bff0f768c69dd036908	74	\\x00000001000001004714149b4d8f07f4b181286fee2dbe7f56cf10dd1e4aa3f85a4d3758bfa57ba152720ea9284c2246dbac2821f9d3048702a47fc587e05bba44db87bcd7a8a12211d8e270ae9f5daa569fc0f0a60b4d283e824da9e6fd762eec4aaab0ad9307e7e86e2d51afb6a64bb915d457958694280095bcfb83145744c48b9b3eceaf4eee	\\x074716b95c8c42b96d962afc498be92a7dcdbfbb344b3ecdaa57a332556fd14c9f06c0af37848cdf43103e2db14aa553fdae8c3705bccfe376de1fb9fccbec5e	\\x0000000100000001a16f673bad196b48f713bb85a12e37681691621470f54ddc213f39ab81850f187f593ce651d3443290a0567043bb2d897853cb5d3dd76728d72cf5bcb9ceaf76cde18c6ef381c6104a0658e011ab40763e519c9214fe10bf0596d9860d5f6c16f771891c26ebb2c6b95317ad9a9d31375d822bf51ebf89743a1cd7a4eed3b3b3	\\x0000000100010000
32	2	19	\\xc2691e9a433b83bb9ad99b6fea74cae26f832cc32b8e0ab9da8af0aa89e3649f86774145fa869ad4dcca859a9ce7cf5312b68bbbf900cde4a8cf077b34664b0a	74	\\x00000001000001007b95e22e5f6a5361c918c1ed4718b5c7920306a53fe09d255ac84b37ac35b2117bdd2e853678dc360b669e7098c025859c54a7b7e530b9b9b7b5f5258e6000080fe0989fb5d25097b28be1b80d0d6774ddda4bac5d9d5799c09a18e488603384041511204c50b79d780589fee5fab020bb99d0ec69d2c54ea4a7332c064aadb8	\\x1acdc2f73a789912baf9a6637123e1237a099f4b0e3e65ad2319bed85cfea9903bca5eba5251c7bfab5cda6761e8395e98f14ca70a2f50634fbaa8228c5652fd	\\x00000001000000019120f1fad94b490e5169f804e256994df6a20eae7d554d87d101e9965aed86558555ca580dad5af7faca5e53d4c5f4d43355267c39b835f73d094a45f1a11300d66dfc950940f77d9b1a8425ad0d9d77fd8b819507f76d73db9ce901fbdc1c7cad771527bcaaf791816592abc377c980ff871664e6835f7d99db44d531a84e96	\\x0000000100010000
33	2	20	\\x890f45392ca96de73c347c0af827bad78a9efe3c24f9e00b63f4f250834d20c5b2e97f26ed07ee2ac5b5c69f355cbbd0720e958cdc25b74d265023c19dfdfd0c	74	\\x00000001000001002a2f347cf9e4c7f6ae5b97a3fb6a5e312748ff194d8d8e2e5843b171914780664a7b350a464738156ca4e0f90e7a3cdd0d3fa88607f456e7f90291a11190fb495c7d23d36b8f4f3d13e434047ea84dc37dfc16ecc1f8eb5d40761036781914c9ee733ef7bd135023491fd27df837341efd3f3372af9e8af9d5039699f2f4807f	\\x733a7806dab55300f7f0b062c7aab908855436f0d4dbce1b07b67c26a45a9ee46f8ce0e5b35da540f18198d2b4b1a5a5162958b19193011e54d4f6c542255500	\\x0000000100000001357a332a5eed949838b85aa5f5afcbb85dd43806467ff87d01f77c7d2196447015be4d87db48125daba70f4bfcdba3f0a89a4c40ff9fc76932da4db0552bd039fd88c165cd50685f8d66d7dc29e68a92675b46755b784423b2e960b7aa9b6f35fdeb25e5070f03b0e407c6cc8266e29244dedd3679f5a6cce8b9f5c418c40f83	\\x0000000100010000
34	2	21	\\x8b37386a8dfbbe18c03bfad8b957eb99e17d5c35bffa03b191805a7fa0291887de3830d00e71cba40490e1335be6b1375f888bebc6dd17a9a794dfd8fa5aef07	74	\\x000000010000010055e6dc2bda91951f780feb183f471ead1b602246a89a3166748103032e42b3446d6d35f845db6812c61762be317b47e687307687934ad60c57c858b69f0dc6b07254f22f33fb98e0a7fc30f105366b0c1af7cf6566c5bb606a75010020045c01adfaff2caf6c848278527ad2fc5279790f2c9f593af22c17dd93fcdf32fa00a0	\\xfa907900dde58498a39bed5606fe5eb11c3e06fed75bedb3a31318225910648bbbb76583fd15970797eee7810998fd076645aecf32fd55db11fa4e7869694134	\\x00000001000000014999f36ff2864e93254c82c2f562f13c5d21aad2d1a5a8c6402793f1be71f51f66dac99f1e5e67a0fdd40dac808a9d09dd520638cca42e7a39d6ef09965a5af3fb00dfe293fe9f2f64dabb69645cab609622d53f703e131d48cf03a1f699faa7b192e6991f9ac711948eb08b3b7464b9d0a7adacd5b0f1ba7d2ddd17ed593bfa	\\x0000000100010000
35	2	22	\\x0caa71cad1f6b2d3759c852f86879cfcbdf4b3240dfcd04d83dc6545a9bb016eafa3cb591898e0c63a7d11a26195448da0a388c19ef37e25419347d390452203	74	\\x00000001000001001f8a6ba3db42cf53b80f4ebea6b589c887d05ff76e5b0ecf34e6c9f96e289b43e8413891c4d31e9220d1b57a29aa5e63d7e5d88d87941fa7a8c5e3fbefac1d34560ff290c78ce27a0cfeea8d3cb08f5d596b758c6cafdfa87d5a0ee577e41913ed1c4e3e2b6a1e7bd622198694bf1543a67c8c9a2516363d2dca00170e10f3b9	\\x35decbc11a6bfd46a1a91e98654eb105c7963f1d7ee63b6a117ffb6b9cb067fd5a0099674aee5ecbc3c972d9e79da1ea7c76e66edec6f1bfac884dac33d34d30	\\x0000000100000001239ae8ed82aa6c33cfe87bb98e91877835a0fa77d99994f39df1444eda9d6541695d0421322d8386f323b6b4442937234d05337c8fc8a4d2e94713b2f14b66373d49ec3c84caa9fbfb146d39d35776d424208a564a27edacdf3411c09dceb229f1d0564c61ff2f3679953f0694f191d0cded483dde3404c960600c1add819818	\\x0000000100010000
36	2	23	\\xfc98ca979bde2e58810ac32f5cd3959aa06982b046dd6a816045f628df84747b09533e46954b9ce0b7d85d73d390bd35de283351a93ad82e89dbaa49950abf0a	74	\\x0000000100000100bbc422834d2e3491fb920deb54c16b2405e6f25910464d7befffff95a7394c6e930081dfe5409f0e4bec87b7d2538340c0f4b43c8bb1f11309f178b3873107406cb1d3311cb0cc1eac5c50a2580250234dfe234a45feb130831bbd082483d8266cdec7b1c5f2f879f73b2637e1cbf656d797651686fa078fb47a5d1ba01ba076	\\x3f6eded5506da3aaa1b3f59327c2ae8d44c6d5e430c880745103df724cb6524050fff60f777fbbc8d0f08784ef4aa34300ef9fe36cf5d04ae3c5ae726eced22a	\\x00000001000000017f25b38cc620cef8b3704f1563d2204f87bbc0d624fa37c557aa5db6d71ea34b02343f90e90a09154b4e77d096092ef5e9dd995fc2bf75292ffd675b7fa4ad7a549d9b4da12661edfdf31b37fcecbc8bc0375e6fac2fcfccce1f26cba6c66190d3f9dfb71e9c0a531cffe5bb6cfb24176ab491cb1b3702078b9e25cb7d74cbf5	\\x0000000100010000
37	2	24	\\x1a0145dd01ee8c1515c354f77c4feb4e4b8a47a59fb65940ca5bd1768d79161c96e7ccea42dbdd59a5de712b46b6240e4e9d221dad9e56d581f44e86f84c3209	74	\\x0000000100000100997d30fcc3eb9bd0d24a313ed90543578003454d64959ee89a3051d3ccb820fcadd1d45d14ad73cdfd003c3e9335800379ccfdbed3330e747715159b7d6fe3a1191e648f3c0cf32f4f09f8eec19813845751d4421828b0f76f568350431ae743539cb9b94c3e39f18d25547d6bb863c1e5ebde1d315e10abd074219bfd530abf	\\xb64f883dfa9fffc31ea4590550191a93e40f07368836f0c4f45b39d0de5096f40a1fbc67ed20550c7f03b140e2010dd7c2eb2dbf5f80988ec0c0f95d98695f6c	\\x0000000100000001ae717f092e9d3a92e2232cd4b11ac6656a8f38d1f4715bed1b769508a575a59f9acf280fb9e09f772c13b8fde992e89a50993200b5fdd66d2670f69b24a57cf340e6c273e316550c3b026fa98a3d3c29bf72a58f808c642702b6a7122b0755d81fbdd38b596604625dcbd5204a199d98ed7fc2218cc94495d0b1962b4efcffad	\\x0000000100010000
38	2	25	\\xa5b855b770aab686bf23952de846fa7cdf24cac07f7e08f53301d7edaa38c8249ce7c716de0171040cdc17dab3fa131338f22897b7394c03ee170d185e5fa204	74	\\x00000001000001008e4f23755004977b55f4095bc80ebabd80efd7ca040baf52e90b862146777db8e0ae054aa3a562b6707b3a84831817bf6869d7ce3726bdba41fe51cc74b8f958428ff91c7f201d4ed48fb8fcc94cc3631e4e2e372948ed630aef3b2a6361e172675fc1b0ea4b9f252c861db5dc2764e01a1f54371d9c205371e3be25b1802628	\\xe63c1dc8adf3330e36dd3369058083a467650fca2f07ea328cfe90ef21c509bb5eb275a81b75fb8a2a0e3c9a9e125e40d15e06c6270f4ebbe74b8dd3cfee48fb	\\x0000000100000001c02f84b2c90920af613b4f44680dc18ef8b107ee132f32b6fb9b658eef327c644c3a5bdf52266a73bfbc160821c39c7439f3df19100ef0be9d213d9c4cc75191fb5cf940bfcd68bd738e0c70d8f65112f8a40f2acf5e5832a354da41b8b53dd8ce7e368738885e9578c154713bdbb0242a8105a591e3e166f66bedbea750ee74	\\x0000000100010000
39	2	26	\\xdb5208631624a9c63c820d1f9b0f00b0874d9ae15fd398da929a859517dcbfbb9fe5eb142f948e9582a8dc8c9965ab87f8acca76ea73fae9ea3e4669ef541607	74	\\x00000001000001009c65390e9e556bd09c60773933567bcaa2fa9b12ed9cab1b3d3c4b370db06a0a2d7cbb20c39a37a7ca320c1a25b6fdf0b86e9f6acd0dc0bbfc48c7f7745efee4c5429453ce7ef0c98bb17de3369f9022a30715d3203fdc1bbd14a474610801dfec1b9d39301ad8f4274724330f9550246b886cae23f2983d9024926aa9441a4f	\\xc96783d8dba99b748611a11c8532c8eb3af60243234890841fe7ceed06efc3ecba9c453ec2ebc8c65100a12a825a6d0000d16603a74bfc8a74c14837870eb1ca	\\x000000010000000124e83f711a02e80123c6b742ace826c18e7bf7e6b0cb560234ed3901e0ca6037255e1b96f5d0df167589508b849e72be89bda76ef2c29991297e343e26b015f0d290e87b11175f482428c7a25ab0f023a643a088c315a114fabe55694d442dc0ac03495983626fb3083d9ba7b1a7ef695b51a22f2fe20cb7ef58df6b66319ca3	\\x0000000100010000
40	2	27	\\x64b9c705fb3de4d9dce69c23ef384b3648d7bdbe5633b06530e068edb3e311134a7ad68c35f6bc58092f3eceb3cd1c68b673ba2914e41b8d910106b2b9cbc50e	74	\\x0000000100000100104a532a6ff80ab467bb7212a286f99e71c8424d26424565da9af307459b61897106ddb91c40976ce3f43a482f8dab75c21b3ff8d9ee1e50fe488852333109beb1bebcb2d4e9698902e9cf86e8d6339cfb0900888b1d239b3570ce5e3e5bff63308d413b9df43296c4bd0bdc52e453c7d95f76587a853fea9238c5feef045b82	\\x4d45f44fc82c92d9826f3d338fb12823f552af2964eeceb9d972413c35f778fc94837bdd653e9d2a815cf243d2f9cbc10c9ee1ca0d218fa1c051a57a963cbe8c	\\x0000000100000001cff9f722946559a6da2291bc07a5c75fdae90963e8d8762ab3b22cf501a1aeaeb246beab237dc5e2154650ca16f65e72fb01938b687935612da01c470dedfb599b47a3a8e8ce31638519deadf310c0bfdbcc41652fd515f301e8d68c5497dcad1e9de15d00214ed64d6a9d4e36233fd9955deb14ee98ef43e4c1eaedb92fce4c	\\x0000000100010000
41	2	28	\\xa4fbd50b5337cc16d4d937b2dc189ea5961255d49f057fa36a6b280b22d06cf4e149cc1fc9e59cef3e66fae9678ed17e6b0d6beec59b23dc813ca2567683f409	74	\\x000000010000010040c4256397c3d8b988fd16dcc5cc35b2acf5020a1dd5ebd76475fb2a0c9efcd79b791c38b581d94dd9989bde4e6971418e23cfa24d990130165a500fec0367997b51992c5e1cba1837ea0ec5e371abff97ef6a0e25ca82fc7df06e15fc9537735dcfb70b4a043d5903bfc3f81fc2827ea3fc02281504daaf7a8eb912d3e7a281	\\x858cc5b7973f8a8b3471c94d5992dd8352973591d46cdf38a5a5d959bc50e6f5ba1e6bae9e6fd2a511fc354abba9143107bf2224b182e1a9e8827fb0e0fd1d43	\\x0000000100000001ca0a839ded4e0ec83efa739e47a64ad4c80005677722860bb0ebfbcaebc98ef7b86503076893b29d8cdd3b211472c5d25614ab2c5fd2e75e7ec38159e4cc3dbe3c349e644b1c4bea4b95a6d5f9e30af23c7a35264df0327aa82acf66c767cbedb7bb6e16b14a5592a9392c45ca16f74943566ee31294ad6229af2a204fff7496	\\x0000000100010000
42	2	29	\\xa4039a6f8709b9af22fe681475cad7bcfc6ecf9050f342841eaa52039818ef0f0827a01192a846c05a60f3e2aff4922793001f547a6564a930e06f7a69cb2107	74	\\x0000000100000100694d558638277b0d5106c4c08c0f88791b1f31cf3305072a9d70c0f571022c167ed01935c2225b91653b248440f546627626d06e75da048e188fcb895c6df86c2f7a7825c1958c851a891519413e0f28d4fbd66ae92415ad2c93b2aca30b7711bd5c56a2af6ae82ac81766ac1343efacceba780313824cc32112cbfde1ef6470	\\x6023ccc7f4a0a91996dac28e70ac7e8e0835294bb318288033db7183593467341d42848a86438458ae00a7e3dafd3dcee4d4b97ef0a123f07fa00a6f666b1fdf	\\x00000001000000011a3581039a5596a58a8e1eb57f6b1f3695d882ead6a8d8252ec949fd2b738a6baa60c8b80e069bb95abb360507b09f1d65acee93be4f9a7f03d6113da55ccd9e8250113be4af938f99695ce289dc3a413a8fe2c5ce1e88feb03aa9622f31bcf95a505a210fd111668bc230c05976bd32afdcde009e91e032a7db9b63a7e6f5af	\\x0000000100010000
43	2	30	\\x60fed038d4b2020ae29127deec421bfe4a67f684b5b5578ed3ca2613dd8549081a1d11d70b97d79cadc32b62eb3809a6b9bdaa931acf8c2c565c9e2ded7a5307	74	\\x0000000100000100cabed281f0047ca3c18fbf74e144180bb610f5924d4b3d75be055b8590803d844da96eaa801fc9f7e9f0177d650e7a9c5eafad49630e3b76b17e021f8593cbfbb44c52cdf485b4bd35de2c24819deb632680437a712b8fcfd79f52a1d14675f45dfd78a7f5e915df92631e9adc06f9a9e212ab8056a0d36f82e3727dae00c122	\\x62021a70effe60cd681b30a2861170245e475523848c3765b207a2138d20177588b7711b166c05b477e1a9f6fd45194fd85cb979b18d96f093dcae9c26f116b7	\\x00000001000000016b923e8adea46fbfc6c1a34b82cdf6817f7ad69525a377e4e833ed945441bdf8e477283a1bd6c9a5ad7ec7131ee35e5857805434fbe5c6ac8fdabd9181b02199ce5e03dec7ca6f08a324add14524f3d388b129f30281ac03cfeee86999c8c09e42b871e7a7a3bb1541b844ac3b1df153768eb0fd544b765deafc0a26695d2d48	\\x0000000100010000
44	2	31	\\xd3ed2468f7bc407694b5e709e2fa719f18a7492e5474fc304fcd037098554d805c16d6db3f7caab98e6a9dc14e366615e957e5d23c1574fa2c6ba4b410301801	74	\\x0000000100000100367ebbecf1fa206f3a7a382c65b7bd59ab06885d2c8d7faccef853452e54d09e1fe70aacc312885cb872048d7618b7241e5a2605ede3bd0de12d48cf175d6d2a7a10d1cc01c4f0526e939238bfa19d94ca12e582c684c77229e57edf53bc9316f64b673957a43abec3b1ed40cf365f2f00b4fd5490d4c3ba83a90aff615741c0	\\xe6776f0c6bef3db71f770ef8b6220bcb998f0a8f8a79a6aa632f20fd8565fba15b93c96dae0eaad9974765e6b4051e0477f41506fc1344e0be04ce6faad9a95b	\\x0000000100000001576b65e3770f55cf35b1c5a65b677f4c2fbb0ea177517aa0150d1131e64ea4f580fb3e1a6e06da650d2a5c9a1a9896517c84bc00917eb4f49eebb758cbabf21429f2dd6b690349ce3bddbe04f946029bc070d557a3c81511df52dcff09a3b6d85e33931175d6aafa62e051b632a42eb5f43e1220528c10ddc14297e6acd4b6b5	\\x0000000100010000
45	2	32	\\x77b2ce1df83d7b5b95172f7feebdd5a5d67ea210efd5cd450db91a9487a1761f01e722b6216459e89d48c0fc972e06f3452e36e531a49ae2558b5713fff03300	74	\\x000000010000010004d2524e8623f881086940a39933ffc2296de2836dac03ad2875ac188dbc010f83b2683b21ad41d01afd7fd3371352d0d4eef509348f3f2e9295306b30a4a32d0e17cbaecd271d0e15791c2b7c9f371580bb9079a58d80360bfefd2b20bd3b28473da7fdd4d1f89c9806f4b2aa6ff3b691f5468a8b46d87cde4e984824ebd9d0	\\x3a5935c4ba40a305d6ffe1ed942d5aaab6db39f780c4b53adb55d77bc67f43519710a2c79167a4eab28827f56de6be8585256362a009510e2099a55929d49122	\\x0000000100000001a9082d7cb2d99ea1e2bf9105afcc1f0d39f1eb63bef072bab7ce4a493c0a46066bd37799504a6a5dae1cf8d30772f4d98612da171f4e1941a5f4944d78fb14ff929fdd7a28ed55fc8245d108d9b20a7c80289035f86a8e3c41394d1fcc0499efea044a5bfc9f47e719937b266bfa7037a2a941acff0a5f21fa5858951e009266	\\x0000000100010000
46	2	33	\\xc0f32dc2517ae18657d9b7a097597d110df10228e9e149b58ea20b7a9085e6d36d45b60b8afc45c6db6a21a10580dd5704370d0acaf93f2a94bf70c8ff06c40c	74	\\x000000010000010003a5604fddf53134f017acae0fbeff6913b8b2cbfcc4d29b2e204ee1139784c926fede7c944d826ace653b831eca2cda0f587e38c71e03ef09c1aeaafd608181968466b79a63a06e4857671662272a135a001d84e036834120eeaa43826bca4aff064e8e0a185546d9c51a2fe82d3f60d3022b424a177e7d4a28fc9344c80efa	\\x8801fcf3c771bfc78e3e20e692be21c4dad57a612e75f3111cd504f13fbe694359c1925bd232edfdc91350cbbdede2bf8cb3b3b772ff06c4a3ef2af88ce1ff96	\\x00000001000000013d5854f2648c190dde53a3520745f7f15660760a4257ff003f684121d785d5a6dc63e84c5658d94f51e566fa57c71656154e29cce6022924811dcabfcc4076441ae1839d708c3f64e01c324ca5170a7196799eb82503c28cd66add6b03aedd5d0b67f534777150ec492a6c62ea301d5d8d2d7b8d4e409d42054567c9f1156744	\\x0000000100010000
47	2	34	\\x7bee0c83857e7cf92866dd6e3789d5301278a55f8353e0be748e06994908b3eea2d42c78356a509df806b25ba1791fb326180257aa4c5f4730c0e7d2d9cf000c	74	\\x0000000100000100c44fb6d934a3537b22b926bea0361f57365182531213cb4dae46a18746a632a5fcd132015e660b84342dbcb8a37071e52c680d1050877ae3a0d4d17f61f400d5806abae7785bf4f19c24fc983b99e6f2ca2b6b0f5b7c0e0a209b38bb5e57811e7ee37fec27c313ce0a791198de0faaf08eac48673dd0c9887cdcee1d8f077783	\\xda4c1e1bcfb2dc6d36f139e0a603a916be4169d1b63ac7af7906a02d04376ba2363a4486dd29ff8010af6800aa7a4f159d9bb4958652525d719a48ff2063fa57	\\x00000001000000010c4120bda98f59c05ed0e0617ff296ef7589ec755f8d600550a7354a22227550e9ca4eb6310f634ea41b2b892d97c157619c30a22025213cdfcd9724a4701d49e38d6e3ca2d872004f15dd5e893a084312fc81d0071242347120df06017408bfc6d5e3faf03aa2859d11d9fa344525b0cb5375d52e1e5f3592481cdaf8c2fc1a	\\x0000000100010000
48	2	35	\\x0c7e0461ff196a27480da8106d3c6f19e128ef6d5ea7d4867329f75fcaf843da1ba70aba31d8691d4b0a6116eeb7b21f931082f9c9510ef4e032131b22354a06	74	\\x00000001000001008e2a41077d67d602016c26c6d0d18047ef1397aa41a58082c1aa1d0627ba55cb028a2ec951fe7853666573e2101052ccadbe16ca0714cdc9986b6bd4b3701e1f9adbe499cc2b660f3bac01b0f38142426227c8c6694f1ddcb78874ad00d4997be343a76fef105751c5e4747c521e1b9a64d36e015d41de908cb545cee76b3b12	\\x771cce396a50ea225940bc224381dacd408bb30d07a9dd4775ca884482819a2208e6d348058bee4c2a5efa2cf1f4f5632d8a6f9f7b638867503b60d9fb1e26ec	\\x000000010000000178f66f973aad428358f752ea9127d774f1dbed0e66054655e03ac1e98a263911bc62745f9b5cea257a2a080ee3671901db226920d9c7fa38841b360ada19750835402d65fc5f341353f333adeec0b9bde9ef74eb21612b44463fbcb5317c92826beb61007e9842f7cbc16d3e213b70c0902a3c0cfef6031abab8e2a950d7c29c	\\x0000000100010000
49	2	36	\\xef929d5d95c87386f84ce71b2455dfb224fcc96b69439d0d78936f77d2b7904c709802793da8b6ebbe94c7f115ad9140cb1f666003ef1a5d44b7b298a9dbac01	74	\\x000000010000010037e40280dc99d634082eaaa4cb273b6abac85881f2368869bde47483767ad7985b5eb4b1160834eaeebd0a3082a7f1a91ca842ddbfc6cf998e10783f7e854949720f75a67da25523293c9fe44e2db6a088079beef84e6dc61919763cd7b0bda0592a6ba573bcba6cd473bdd546f89781239dca4113a075a899fcafb607f3fda7	\\x2a390c5b1a0fb828ed593f1e57c116a92a19add1ab355373be3dd8a88af3b6376ae87b24727d9911e4264a3b1601a5a8eddce6a94af65997badc5b9a2ecba72f	\\x00000001000000012cf361347b1d785383efb3cc72ee584d6c482c29fc629edb44037f3811046c823802ab7876de0172b2c4a9ac2a58b5716341c9f666d20818818bba17f92e86e200b72a3e62551b6ff73f842e402ba35a48f10162197d6a045de937435f11e9e1d0f390b677b11e17b651fff0738675665fd8fadc8abc0c1a8de2ac78e0a7f810	\\x0000000100010000
50	2	37	\\x7781172d48a124260840d8564ac8ed962d7935d1188c6732ed0990a70a123a77ad8722c6d0ad5a61bf341bd2bd74324200c0c3cf96a5ba1a6a5b2089b5278a0d	74	\\x000000010000010040be8ce35d95ffbb32b61ac43c7574d551d99caafd8ef05404857b438bd4dbdb115e6534f38ce597e739b50f208d4e2794267a5059d4145b7567063a854e71e3d2a89a8b52d51fd0f0350d726eeda986f72dbcc63c95f99bcd9be4bbc783916fb6aced05d862e75df5f96005b3a423e356164de69a32749f91fb898ad895d228	\\x1331ec537f22589dca0f7ad6b3a83defde158e5ce2ce2dbde4c695967cc8d80e252cfc92f49b87cbfea831a87a0fdb7aee58bfec4817c7b065e5bb4ff505f7a2	\\x000000010000000159b1d80d35eab742ca78686ff2dc4fd3c394d7d6aba54aa3cf8a3749aeb62ccde3bcc35b87359d6a246173a4d037e87efd7f50e85e4c5c5d600035d89119075c661a89c09884fe73980304b41f6302b73e777ec49a311b608ddc9c9ceeff941d9956ef2388cbac1ae59a2b0bec46a329680697b6d91af1e4abcee84264993d59	\\x0000000100010000
\.


--
-- Data for Name: refresh_transfer_keys_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.refresh_transfer_keys_default (rtc_serial, melt_serial_id, transfer_pub, transfer_privs) FROM stdin;
1	1	\\xedd31fc356549eda40bbed4da895ae033024f533b43bd738567a615ddecf4b38	\\xaca5b50eacbfd5391f5dd5205d1cfa4d6e79469d3d27ee76731f9af198f62f55e36d662e174f4253a08a56488561dbb1b35a5a5daffc8709a14f9a89834dc4e6
2	2	\\xab9604d0f5042009b8c6e346cce7f19baaa6e9af8c0ad3640ea725873da1fb28	\\xbdb77dd3605dbfb51aaebb5ea3393ae44a1f4845b7f0a22e6ea4b0efc1f36474e42034fcd3844af026dde748c7ead5ebf77b1975f7cf7935e3dc036eceba745c
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
1	\\x6a7849e2dc7a36ed76dbd2bfa0f59b8c3c5e456792d5df81d1afee685a2fa1a4	0	0	0	0	f	f	120	1662910909000000	1881243710000000
\.


--
-- Data for Name: reserves_in_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.reserves_in_default (reserve_in_serial_id, reserve_pub, wire_reference, credit_val, credit_frac, wire_source_h_payto, exchange_account_section, execution_date) FROM stdin;
1	\\x6a7849e2dc7a36ed76dbd2bfa0f59b8c3c5e456792d5df81d1afee685a2fa1a4	1	8	0	\\xa2dfb8119879bcb0225e26f84d17188dc13593a4d8025a517aae37955b830010	exchange-account-1	1660491696000000
\.


--
-- Data for Name: reserves_out_by_reserve_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.reserves_out_by_reserve_default (reserve_uuid, h_blind_ev) FROM stdin;
1	\\x150bbc639adbf9803f9ddd9236e4b5b53428d5202e1abaabfc39de2dbfb2a0a4b56fbfcf4bccf0ab9213d5917dc7c81ba97ade3ff8ecb15e0d7c9d88462bf506
1	\\x27708d6c6710f5d5cc0e30d160d0d4642646081166751c2e0036cc8e055c5a842f223e12d04b3e68bc810c3297769c5c7148323158dcd88885a6a116da304927
1	\\x03ae3c0b8d4f1472e8f06ac13af25d01811a1eab39b8e3b07c56014fc66fcae5bd096cfcd1be60d0c4912f7a8f7178b93ae77261d016f69d8d56933b3cf6fbe3
1	\\xcb2695e576513cab62518421d1c7e47c525da88a5058dcfa0f50f9069d43f559797ba04d2b9589594d7fc80447ede04500c2bdece81add28071e02d0c3a52073
1	\\xba5de7de6d942d6f30484478da71a07a4223b3bbc098593756cc54be0e4dd95c91ae22dc276ec370813d125907105d8e1941304dafadefccc0113065806f1024
1	\\xdb2e5b711df3f3c37b6eb472029c3069252316d3a809fdf03b593b40aed49d35d66404b6a90d1de4171d21edebbaa7646b594ae08d2aeb1f458cc1541c6f5dfc
1	\\x3a88043df9e85e0a7388e44dfa7b9dff619e29d8245747a0f469ea0397ee6590e8d94b9f1f8c1fdc959d227b41008f5f39a3fea7498324875b4036001fe0ad2f
1	\\xc77db47dc935c4a54a1e08d951aa8cfc709b9d492e3a12c0ae68e625dee41d6b3a2b8b68aa16cd43fd1ac7786e27c778545e5a3e0bfc2aacdb49bf5566ff5b3a
1	\\x87da068d8d047f7e4a2ed13aff5c58f51b4e039b9ba88dd2d44c7a1884493a916662fee14cdf7d3c602735f9f453dc31462ec62e5ddf778030f87231639413c6
1	\\x8f196f4ce64269977e72da29985fcff4b535720b338413a06858c25c9ff29cac892a5ef6c9b3f5e9742a8a98c90c79a0ab58b4f506a1b21804aef99be00dba7b
1	\\xb8c78da13dbb60b37428c5204fcc3f2a6e87ded6ddf4ae339f42fe3f8a374b67212f6bb3c6a3c48e911d5143f45abf9af63630cb0ff0db05d1be34c006faf559
1	\\xebbb8a85d4e96508a73274f46903f97daa87e7795bcaff9895d20bc88c99fea377bfbcf79e6207f258e3c9297368845c7864e268e65a44baa94d40fe85484c1e
1	\\xf0d72a62478ccb814e692153dcf49998faf513f32516b903e03a31932b621e47b805cf73d1090a462f9a7e44583ed6ce0df025180d4edee961ed1eb48fc7c0ff
1	\\x7b75b03b851c8fb0848084ab3fb9e14e2827713f6f7337822b10054e527b04f5d1440ad9deaf4eca656308a61127eccb7f24ed73a4efaef294f3ae4b3a53da01
1	\\x18f231b2583bed459678b75abd73a228ecab9949007cb82d0b358bcc6a6c35b40c4a7c3fbd393cc506ea92c696501cb63db8802dde53bb144c98823777153166
1	\\x7292e6bd543515d737f3550d857df69f99715e1e3efb5ae0094a1d5ffc685b0e8cbe57f602da754cb68961c5488e168f875f2b786b7e121e4a5a1d135394694e
1	\\xf39586affe5184c507cb2a71c6261665ff801cc015a6469590272d073cbde13e94cbfbb669856deaedaf2191a41550264364aee0e11dfa598f2187241d1e63b7
1	\\x5720928606d78c2c54eee22a2729c659de1440859d4c5459c62305469fde3021c2ddd8191d3724b19f763b48b9b8eda85c62d17323808ab4e029998eb0c2f251
1	\\x601b7ac963b04a1aaf0526f4ff67e846b8d08acc08ae72a79d46578d19b49113fca95e91add1f78f672e49102fcd28425a5782085ed893205d6c69beba255142
1	\\x4868fb2ff832e5d7315ed4ec20e2c98b7b4f9dc614c9b98cf2da7122e2c5036799385ab7f0f28bf8d0444ccdde9be0669e261714e0ee065fbf22b5379004186c
1	\\xc4bc3a6f2cf31cdcbe323559a63131880b9f55cb7be16791c24c8aefa492549615f9536cf154f576edb4bd871e33f000043c86b2652f4afa35e29a9a9e8c2686
1	\\x8bbd5567b6c796b74729ebe806d4ce18a417b7d169ab30c90980314466df625f8ab19e61f747172876446a38199d11a96a16f0066bbe505fe8996b7c79e34e5f
1	\\xd52e9723646ea3aecf479950e4d97b41765cf1037b41d79ffe2a5060c5a146e059a03bcfeb88d348d09d60f2132e396bb49c76da3397408c9b0c84c2edc110f0
1	\\x2d89c5aec5782404c1d38925bde0112708aa0e309ca5655d06530d51a3dd5463bd1364c38cb0015e60e3d72bbbb44b329482df207b95565f52808074319ba590
1	\\x2baf128f97ea6850b46917a19c7c43032bb34b42ebf7ad48a62e485b9a73ffc3a231be26e9475c59e83e94d83e95ed9427c169d6762d77727db83618bc9dbf6e
1	\\xe9ad1d8a87af69eccb47a890e6076c5c6b547987123e8cde803521de1240e932051ae8157989d6108b56ca4743f73112e4cdc7cc3fd0e29634044587c63b2470
1	\\x2a632aa6f51a575508166ed84e9f059bae73bb8c6c9db7fc61bbe275cb095c4f93bcc4143c75b145b5954fbbaf8695097d7538bd394ab80adedf3250346359a8
1	\\x3af6761566f985cc9da486e980ec9ac8f8f11f027bae7bed0bf668bf1541463f468ba911c6104d52aa81fac5c901b2829e81053c1859c6b8672bd93a6fbd24de
\.


--
-- Data for Name: reserves_out_default; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.reserves_out_default (reserve_out_serial_id, h_blind_ev, denominations_serial, denom_sig, reserve_uuid, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\x150bbc639adbf9803f9ddd9236e4b5b53428d5202e1abaabfc39de2dbfb2a0a4b56fbfcf4bccf0ab9213d5917dc7c81ba97ade3ff8ecb15e0d7c9d88462bf506	278	\\x00000001000000016ec6552e51a990574e9594ca4feeebc8dd3bf5fb02f3066ae311875a7aad930613e45c296864627841610acff7410dabb92e5fb0277f95eb0a52eaa20ef323406bf88387e473e1cbee354cb007d6353cccc8c131894eb2b588530629869411087874553fc2e22a62d5d3e9b9902710f2fd151623c00297e2c18ea028926c96bf	1	\\xbf668451f416b109eef8af875d034df167d4a300d3c0f5f8dd7dd17a3ecdac064bd544bd3430178f25a8b4feec1f5b1ca99ebfe4e58d0397d7bbb4a4d12e2f01	1660491699000000	5	1000000
2	\\x27708d6c6710f5d5cc0e30d160d0d4642646081166751c2e0036cc8e055c5a842f223e12d04b3e68bc810c3297769c5c7148323158dcd88885a6a116da304927	67	\\x00000001000000019a69f093b162b40ea994ae31cb584a441f3d4767350e1243f97cf9792322173c86b9d09eca49d9efac3e46425fa1b22bad916f07a3c7842da39a78fd428d094f89f2cadfc67d89b0475b504a96cec1df331a289a1a72d277084cebfa257ede20f2df1949e8347097057ee602ae0ab088ad02abf5ed71cc0b0b1456bf4a476b05	1	\\xd4153979b72a74ad203f15495a30c7e19eca2876616329b03f5e36979680512ee2a73beae7adf8dc38a09d64a1a2054097b6138cea37e6134978d43b14760d0e	1660491699000000	2	3000000
3	\\x03ae3c0b8d4f1472e8f06ac13af25d01811a1eab39b8e3b07c56014fc66fcae5bd096cfcd1be60d0c4912f7a8f7178b93ae77261d016f69d8d56933b3cf6fbe3	372	\\x0000000100000001bb8a67a4178e13b10a7bdf999e2fad1982539abaa791b144368b339babfa563c532fff1f0764680abd104fceda7596c0972a1862073ef4499baf517403ae3ef7ead1b7da2ee89ced4c662037c4f60a3481cbea4c2fabed24bf9b8dce35a677c466f7862d87ee3fbd3cc5f5ab10ccac2e0d5367e71cc2dd9c88374028b5d55bf7	1	\\xae0295663f51fe8107f92bf6c624ed012b11292a57d2912ee56fd3832f9b997e78a772c82c3b8546ab337e6176470d4eba1e9bb394699cac883ae749aafb6e03	1660491699000000	0	11000000
4	\\xcb2695e576513cab62518421d1c7e47c525da88a5058dcfa0f50f9069d43f559797ba04d2b9589594d7fc80447ede04500c2bdece81add28071e02d0c3a52073	372	\\x0000000100000001d0dca2781b2b4cf111f9eb9b3a9dd409b00d52969ec7cb1030687d79349ea2c500b1ff727050f561136cbe180e5cab2c0d7d247a6637cd50baae22a07b3b5c8e9389a561e82141ba154b4c1c37f9c35ab66ecbb9079ab8af0113692f123d38ca699121b92033390d44673976975c6bd253f495570a04451971fd587d7c1c063f	1	\\xb15f64274510ec0c8b59899158e3856e100e265e2bbfc01e5f79bb820d41cfcdd595fb4bea4b8e992b732b363ebc64109981fdc74e494f1539c49c92cc050e09	1660491699000000	0	11000000
5	\\xba5de7de6d942d6f30484478da71a07a4223b3bbc098593756cc54be0e4dd95c91ae22dc276ec370813d125907105d8e1941304dafadefccc0113065806f1024	372	\\x000000010000000198ce8e2c132d7cee08e3d3bba3f941c7e4ba82abca6296f0e1d238bebb7e982768f157eadc4c5a6b9e1b72b974cd54116e8eb5b4068021d3384af35e566991d00937b15a84e820fbfff41c1b6811f6b33dc291389036a8531de0070bf9c8867df7d78160992f3e12bc6373a0ec9abbd6ee7c33ae683a7369e92582be4f768934	1	\\xc76b2c041bf0fe5b570638c46078dc7564d3eca1e8ab2fa96127720425168d7e97e10019deb08b50287f337ab599e5ada6825d056bf034542008538297844204	1660491699000000	0	11000000
6	\\xdb2e5b711df3f3c37b6eb472029c3069252316d3a809fdf03b593b40aed49d35d66404b6a90d1de4171d21edebbaa7646b594ae08d2aeb1f458cc1541c6f5dfc	372	\\x0000000100000001d886679674c9683b7eae3c2c3cde76876a20c44e054548978f6ff74e5c771fc29e8a09d0708a3ddd52eb23022ba60d7a4e53c2df16a643d7bc290d0e4433ca69e0925f2623df7d7f49b87e18edba83f63349c611ee5a2042e9c4599756f3c1e095a3c19fe5e0ac09a12cfdd26fde18b69a650cc0d0c009aa0d6e125dbe7ed03b	1	\\x33acbaaf79ead23a182f1bf5be0cbdb31961c7eb0b89fda2df824a91804761f11438d7475018e50c787489d64ee1ae268df23792ec6df1a1cd90469097fe810f	1660491699000000	0	11000000
7	\\x3a88043df9e85e0a7388e44dfa7b9dff619e29d8245747a0f469ea0397ee6590e8d94b9f1f8c1fdc959d227b41008f5f39a3fea7498324875b4036001fe0ad2f	372	\\x000000010000000107e705c0fa8b97e564308b35a0b8a5bcf12c061e4adb78381e01e1f4c997ea1c16825060e55566c5ba9dbeb7660ad536c9a8102f238a9d884ff37b56f26574383579504417e4104e8ae1743d353c6f8d7e4bc036d3f4cc1874693d47fb6419ebd54278f8dd15c4e52c3e4246f03f877decb30f6c9e300749fc9bb8e3a09f12b2	1	\\x3f4fd8e98c54ac03535ac0834f2b18a0bd94f31c5bca38cf923d3db182079663c351d21cad4c6cc0baac1a012b7655f3c57aab3274d046d69e507514fb2ed803	1660491699000000	0	11000000
8	\\xc77db47dc935c4a54a1e08d951aa8cfc709b9d492e3a12c0ae68e625dee41d6b3a2b8b68aa16cd43fd1ac7786e27c778545e5a3e0bfc2aacdb49bf5566ff5b3a	372	\\x00000001000000018e7498f02bd63576f922d3b49c1f5e99a1d0ab7ffe5d0893f85a17e4cc306609cdc2354cb18aea231f7314202906909e256aacf4ad92cb3fbd5a4e7affeedd2368b4fe7e78bdb4379e3b987e775347df41c6072aaf062e805ca4821fe0d513516ff3a5e3be3d02bd7391559f6d2f6163daf97f9e6520c1ecc400cdf18e753b81	1	\\xc2bee54405953a6e5a1995993b98ceaa9cc5ffb8d07375ce52236d9d566aa01182a27a9e0fa53e896a106efb8e7a1e1bf3fc956320c2b913b17a83947a127504	1660491699000000	0	11000000
9	\\x87da068d8d047f7e4a2ed13aff5c58f51b4e039b9ba88dd2d44c7a1884493a916662fee14cdf7d3c602735f9f453dc31462ec62e5ddf778030f87231639413c6	372	\\x000000010000000161cd072cb6659002c05eeb86baf89cb46c9d845a404cceed428c5fa071eb4bebda9652c455f68b995081cd3aa656e2ce8a3b992adcd50a32c869edb554e7c4c35141536a5ab27b1fe0ec8e0cac4f6cf92b6ca77ceb89006e9bdbbb4bd89681205e024ce15ab76a81d3ea48cc8ffbb66da353292ea1bec5876b33b090e5269839	1	\\x1ac1927ef0290c67eaf853c83e15d5212d5c5ce641b99aeb322826076bb4d987c0cac3879968c665c1ddf7856ed47955c75c10db8c9812c98eefd44f63c90f07	1660491699000000	0	11000000
10	\\x8f196f4ce64269977e72da29985fcff4b535720b338413a06858c25c9ff29cac892a5ef6c9b3f5e9742a8a98c90c79a0ab58b4f506a1b21804aef99be00dba7b	372	\\x00000001000000018e8d8434a7abd55dda39b536f5f52dd40bc4ac4017a9c6421c70eae2d01d0ffdc63187cedbbafc90e62c6e5e6d34fa2307ad90f277ba3312660562013ab707edcbcde2d79bd6f146ea1bd6150e820df53296b90e884617a3efc073b78ffc98dc23303e87279fbe0cbd904c1ffa28210ac05096bd97fe820b1dff2d28a827c188	1	\\xbff0a9707dc526c9ba1e7139213b1219811aaf293fc62a04decd22331a85fd3a8ed10e3b7ab582b67148750df6d6064324da1ab6b0d9431e970a45f18eb96e0d	1660491699000000	0	11000000
11	\\xb8c78da13dbb60b37428c5204fcc3f2a6e87ded6ddf4ae339f42fe3f8a374b67212f6bb3c6a3c48e911d5143f45abf9af63630cb0ff0db05d1be34c006faf559	392	\\x00000001000000019d9350e06bb294cb9ffff0589df7868332982c8e8e99ce695223d892bfcb843a4cdace038967d90986f4d962653fc5a65a32ed3840a82110c5081fd02d73b2f889fcca84c792a1483f29c093513c619295a01f32360d3b670d03d49b0a638d6a972e4d81522dd87081ddc4ed59bebff250292ccdf9840ef26b3b04a1d9d36b28	1	\\xe86f7c8cc70e00e0799dc43365cf003bf16277d25a889be6486453e3ffaba226bf5881a7b57cc85377ca64826099d6bd7718c87668a2f66307f49ad47f676707	1660491699000000	0	2000000
12	\\xebbb8a85d4e96508a73274f46903f97daa87e7795bcaff9895d20bc88c99fea377bfbcf79e6207f258e3c9297368845c7864e268e65a44baa94d40fe85484c1e	392	\\x00000001000000019015a7a1c096c8e98c7c5840e27bb34100cb055c5c7e15d7a879d94007aa58ec1e945b4a220382e954a91cd353943a0cfbc3691d758d4bc4f9ff0c5010a56655ddd5b97531bb6518d233bc0d03a0c077574e38e600f397a0249aa723c52b414f5762f3dc65a9019b5be5350b8025a236a80541de026b1dd3ce5c13986f31d1b9	1	\\x8ec3f6c26c71cbcc0dfe408fc45b81983a10e9ea616946f20c9e2fc8978ca493cb542152fba12aca9f2e068e9d49805a5f446b9f6c3368f87b239d28da57b707	1660491699000000	0	2000000
13	\\xf0d72a62478ccb814e692153dcf49998faf513f32516b903e03a31932b621e47b805cf73d1090a462f9a7e44583ed6ce0df025180d4edee961ed1eb48fc7c0ff	392	\\x0000000100000001196d432214c99776e52122b87e4d6bd09a7812e3bcf397ddbed1238ca4f609bc34e369c16448940bcf4d0f340a9f17514dc4ac617f02282f0bb8a180366debc1746f8221ace7ba339366b59df2dc264f6d54dab9f543b22cff2264bc88946f31800fdb075e77c9c23b072dd76a071ac08744b76798a4498dcf50d273062bdc3d	1	\\x17a08a1b064248711fa34b682977d52f1d23bbd5ea2e870b966250ffac8b86ce70cf53419cc6fea82f5b45caaa12a3176d3285a84731d16a20d54fc1e7605c00	1660491699000000	0	2000000
14	\\x7b75b03b851c8fb0848084ab3fb9e14e2827713f6f7337822b10054e527b04f5d1440ad9deaf4eca656308a61127eccb7f24ed73a4efaef294f3ae4b3a53da01	392	\\x00000001000000018fd99bfa6ffa9eb4ba71bae359cc60a42bf56f1d88e80372727fd5a9ca647b3064a61d3358002d45d2735e18d1ca218f93785658727898be9402af2676e16e5b9286768d8460aae35e77a55248e698a3758a9aa9d0ff4f1eb02275349d4f08b20d48d559b065825d2af20fd3cb1e7ecddd96339426150e3358916b00af3f2177	1	\\xaac44b17344dbee2bf84326298bfffb3d9a2512d53d6c970deed2a11ee51876ca528abcbe9af0da61d40390072941baa288d6363946e53eacd0ae03ca61b9508	1660491699000000	0	2000000
15	\\x18f231b2583bed459678b75abd73a228ecab9949007cb82d0b358bcc6a6c35b40c4a7c3fbd393cc506ea92c696501cb63db8802dde53bb144c98823777153166	36	\\x00000001000000014822f02c055f02d3fd75ccab295d823d6206e5d3bfeae197bb582c3e9097991ad887aab67a1f2935843a5e67c7464980a3da77f69061b546e48dde5bb4b9a2d07d85b41ef507fd47d91eba37b2f61aa671632a74dff549f2f91a342d7843a42d7a65dfdb5a185d754a608782f7d077f0e77a1e806fb91199816f95cc62af18cd	1	\\x7fbc74c2f4ec0b758861f98edc1915d41c9407ca8a6b099567b34e7a9a1242a14305fd118fe7bc0c30e1272e9f01ba7341c9a24310545c7aaafd18fbc4cd8f05	1660491710000000	1	2000000
16	\\x7292e6bd543515d737f3550d857df69f99715e1e3efb5ae0094a1d5ffc685b0e8cbe57f602da754cb68961c5488e168f875f2b786b7e121e4a5a1d135394694e	372	\\x0000000100000001d61cd9616685959b60b208b74b34983d4892128b2503ad079691bf229a8bd581344643a01d6b0a8220adb38117a8d8b4f2c8aa51164f4804c4381b321fd401dab2a81c3156aeb6dda8d10c01ec810a1eebf8b891241731c9444563fa257a92b8bc8bac5519ca874303ea4123ac3b273d3eecf9ebb2e4e0bcf6099bc38fa4f9a6	1	\\x9aa6d2eb959198c8eff1f0fe94687f8aadfa08c4f5a519f5621902566c1bd88061f7f36e1ec337aaf3bab081c0bc35993918e1f799a011b48eb31e8b9026260b	1660491710000000	0	11000000
17	\\xf39586affe5184c507cb2a71c6261665ff801cc015a6469590272d073cbde13e94cbfbb669856deaedaf2191a41550264364aee0e11dfa598f2187241d1e63b7	372	\\x000000010000000145cb83f45759fa8641e298c099a8189271da29e3f7ca7df13a592b9e29fbd48121dcc293f4e8ddb2730b883f76a782edd9b1afa68dcc840c0be494ce08ae7045a609d4262aaf6036a3e1acfa134ba8ababde17998fc0dbc88aff80faa761129b88dba0ab3c674dac9e6c381470af1fb1c00b188f5a7ac3d10baec349f86de252	1	\\xfd5752dab3881b064091e7742470d2c249f7603effbc47528167a106410cc6126f01b062ec3b8d50f9aa84fc575beda0cae319e1f501459fdf6ec2bd2a223403	1660491710000000	0	11000000
18	\\x5720928606d78c2c54eee22a2729c659de1440859d4c5459c62305469fde3021c2ddd8191d3724b19f763b48b9b8eda85c62d17323808ab4e029998eb0c2f251	372	\\x00000001000000019b6ed07ac4fb606a4174c7004a55c79a490aabc6f9313b3511f301d87c4e27ece9054caee29dad7f5cd345ad671b55efe7dbe2442255e85c7484f46c5480f7881ea087a201daec6320df882ade149972b35a30d730fb390b721e48337c7a4a0b4ab6d2c718fc62b5a673713f5f69c13187877e7a1a4496d23346abefda3aa5ea	1	\\x850c8c2508ed667cd4073898ed0dded48b9a53ab4be19b24da6f6b61efd8302de7bfbf19b7d928a7b66a0d50360198e51804c5aae5f49eb4f57a096203700b0a	1660491710000000	0	11000000
19	\\x601b7ac963b04a1aaf0526f4ff67e846b8d08acc08ae72a79d46578d19b49113fca95e91add1f78f672e49102fcd28425a5782085ed893205d6c69beba255142	372	\\x000000010000000144fdcc391f31d4508ee23fda32c66a36770eaa820a6ba92c9e9012a26d24f9aa00cff12c9481b1919fb6e32577467152908eaa61ea22794c67290ea84fba973a7b5a9d3fc9963f12fd9982e9a82865eac35dfb794901e434e97e2550f3fac8732590e9cdbeefaaf56eedb82c2b1dba36a9f301967ea9c5a0456b06557d24758d	1	\\x98da914b2f63c8d322e203a1e04c9eea68a645375ae311c22c0284a96c69355465e55289bd802c99e3406560a3eba97e5e82fdba01d6a5371ac44b6e556e1804	1660491710000000	0	11000000
20	\\x4868fb2ff832e5d7315ed4ec20e2c98b7b4f9dc614c9b98cf2da7122e2c5036799385ab7f0f28bf8d0444ccdde9be0669e261714e0ee065fbf22b5379004186c	372	\\x00000001000000018df3188b6158c4656abdbf9cd60d2b026935125f75a0442c92547bc812ec72315289d8fcf2d69938915561a6d2b55318306f4b116ff85a29e40700adeedc2e9cbd3f3daf73230838a91cd87e00b71065693a16a3cebf01e6f683012e91bbc84eb52a7ff7e1b872a115df71ad20551ea3e408ce849fdef27533fcb1d51c4ccc7e	1	\\x31d3c66ee46d3d6a2a68e0148cef25a7d253166456a15d27493615f2427fee5f7541f9b0008f555d69c16da9e94935a8dfd5f653ab0ea2f4c9189b11b345260f	1660491710000000	0	11000000
21	\\xc4bc3a6f2cf31cdcbe323559a63131880b9f55cb7be16791c24c8aefa492549615f9536cf154f576edb4bd871e33f000043c86b2652f4afa35e29a9a9e8c2686	372	\\x0000000100000001d84a1fd878c46a9916946604844a84c65f77e50187e7eab559d07cad8b3e76675fd8a13c14c6625b9be9faa79463678d0c2a6a25efe33789e1a33034ba387ee6b17b7aeade3c42157fc86398b4059119934ee3cb9706a611a6a389d5d77833427da346e07da031d02e70ac787fb073fb21e60bcf0b970e92ddb592bbdc88b3c5	1	\\x10dc059be9ea106f6300de79db24f3d2baf0b7d27ca6ec764e5b4c5f3fc615f727356c5db87b579f88ca66d47bfdedee05bcc47ef5f8733baf9498bb2c89920e	1660491710000000	0	11000000
22	\\x8bbd5567b6c796b74729ebe806d4ce18a417b7d169ab30c90980314466df625f8ab19e61f747172876446a38199d11a96a16f0066bbe505fe8996b7c79e34e5f	372	\\x0000000100000001950163346c378c615cb761f2e29e0025181a0cad55235ac23e6aac0d859e04ae5b5a7c02f675ef4e73e466e180f4ca178a417b4f9ae71b5907e70bf0cb2c9f73535d988c1dd3a2c2a3732f31506b26c04693361575bbff3dd13a467770342b35436f66525add0b5b07679b0970b5e8f4499cb745fc642f29217c9797cf71058a	1	\\x336585cbc4a38cc06cabdf7d0c36113331fdbcd2309704b95bf6adb37dab381557da0ddc1b366a8a0718bc5d3c601cad1b6cd53aa7116fb68edaa3238aadc300	1660491710000000	0	11000000
23	\\xd52e9723646ea3aecf479950e4d97b41765cf1037b41d79ffe2a5060c5a146e059a03bcfeb88d348d09d60f2132e396bb49c76da3397408c9b0c84c2edc110f0	372	\\x00000001000000013ab34b21c24ce7ba752ac22a9fe1bb8717e5c1c413fdc8f37376c5fab163096d1a82ca1fb9fa40378ff26531ce892100d6b4348c8d34e67b8862235c431bacfad70fc88b74a2d5a56a9610881dec6016093bc10f7ed3d95e58bfdf7241e228f2570573ef90940269ef4ddb4d19cc946b26fc95aa4a5d8f67d87e6cc5ab2eb6b7	1	\\xb508ff6fe312a2cac350062236fbd133974957bdc01e7fa4e11edf6dca313e2e075323a3d2ad419487e5c195d5d952593a94c00f0e74d373eb89338f77686001	1660491710000000	0	11000000
24	\\x2d89c5aec5782404c1d38925bde0112708aa0e309ca5655d06530d51a3dd5463bd1364c38cb0015e60e3d72bbbb44b329482df207b95565f52808074319ba590	392	\\x0000000100000001438d8ea419ab36a566a69d6fee0da262b545b27ea36d682a349b85be807bb5c80b53bf780a66c570a699706b50c01b61c98e2372409f22526834a1ad8699750c4155850cba2cae4a52d1abcb905082c9daa0b73fd0ff71ad51e0386b54315165457dd6a99ffb6ba7c6089f1f71dc07ba3db86f443a93fdc097f0e206c7602543	1	\\x4c58b4b38effd69afe8a20110053ead7519cca74c312824412604aa9cc12e1c169381bca128936bbad57fc98c44efb94666dd5c57124f1ca59c586f64e365300	1660491710000000	0	2000000
25	\\x2baf128f97ea6850b46917a19c7c43032bb34b42ebf7ad48a62e485b9a73ffc3a231be26e9475c59e83e94d83e95ed9427c169d6762d77727db83618bc9dbf6e	392	\\x0000000100000001b410e9ecf89abf5cf14601c452f88204ae1238ff75bc3b37ba6a7aefa0b8d406c7f040bbd9a2aecc7ccb8ed2714ee41b0249ad96f9b425c154bf7c13810ce6296c3eb3e392bca80956c2088d0d8f086f1db5d3f52c48d5ed656e95a6fa81e85d32b33d0322842ddbe09ad6084e50d1cd9b692e38812569469e9f302d755b78ff	1	\\x4f629db4e050acfc03e3e677fcbb25197765e6ea381febebb9f8b2e79d5cd02223183ba2f05760bae5a12267e1fb2630aee015c51b969294b369b8e3fd7eb708	1660491710000000	0	2000000
26	\\xe9ad1d8a87af69eccb47a890e6076c5c6b547987123e8cde803521de1240e932051ae8157989d6108b56ca4743f73112e4cdc7cc3fd0e29634044587c63b2470	392	\\x0000000100000001a53b1e0e8457a071301985039bcc8b52dbd2ef1bad68ce37604e22e224efa5a51d60e85c59400edb0642ee137579a9bf649fac0b7780bcf371a544236d44fddb56d626d159507a326b71dc53f1c51bd08d6bf1dc925d29e233a808277e803db0f77d7d8a2d4dffbbc6e78107983f2694f7ca27937e067229875abc81a1a0b257	1	\\x26b970d5293c5f5633a83b5fba001d6e39d43451687a7b45e2fc0f1c076468e6bc07d2b2575874813995764d782a36202c8156405fd932f2d57d101448a9ff05	1660491710000000	0	2000000
27	\\x2a632aa6f51a575508166ed84e9f059bae73bb8c6c9db7fc61bbe275cb095c4f93bcc4143c75b145b5954fbbaf8695097d7538bd394ab80adedf3250346359a8	392	\\x00000001000000012aad855227cd05e433d7611f936138c02f39cc9bb5973ef5b6e0ac53d9fcadeb951922ad5c9bd4ea4786ca0a23d9418aeedd5618e457380db30ad080838db09902bedefeac91eb21e27efd846c5001ef9520e8d084f1435e0a8f7f0a0be49bfd9b0d772995ab05f0080e44da75b8405eea3994bc3850ad069b361d7264f612ec	1	\\x9f8b24e282fe55c4134e312f59f47111547e958391c5c0102175d14d630a6b7e5f06d6d88e2af7dd1b6bcfbb0fe38938c39999a62f9f6151cea0c976d279cb05	1660491710000000	0	2000000
28	\\x3af6761566f985cc9da486e980ec9ac8f8f11f027bae7bed0bf668bf1541463f468ba911c6104d52aa81fac5c901b2829e81053c1859c6b8672bd93a6fbd24de	392	\\x000000010000000109bdcadc29d8c286b0020c0bccd7c48a0d217caf417399fba84b5121d86e394d6a2263d51b5bbf2b7e56a60b1be74fe0e1f59fee6a81ff2de28446fa2f8249544c207c851ba6006d432ec9d7decaea8c43d62e8f545e0732d4a419a6518e7d4cfe98b766a155c57ff35fa4ffe5ff9be3dd8fef9045f0da52c4b89a051d3960df	1	\\x16254f9ce21c9445ea926055ba80cce63fd1169f6e1c172d657e3d49191255e0ad8ada2255c4c0919f03df361611c3386b21c0987ff3404501d686f17c3b6c0b	1660491710000000	0	2000000
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
payto://iban/SANDBOXX/DE490154?receiver-name=Exchange+Company	\\xb4968ed7edb829df541d37d5b7e7313bad69ec978d3f2d65e057ef5c692050a39e55bd4b6497a3c70bc46be8c762d2e4526c3c9193b606246c9a7806d0d8650a	t	1660491689000000
\.


--
-- Data for Name: wire_fee; Type: TABLE DATA; Schema: exchange; Owner: -
--

COPY exchange.wire_fee (wire_fee_serial, wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, wad_fee_val, wad_fee_frac, master_sig) FROM stdin;
1	iban	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	\\x3effed27b0f3c37636113fe396a594ecb065b24728754c113512c04750c894705b06b5086631ee51c6abe6ccca42f2600c1825a141dffeb73199bd8f69f70c06
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
1	\\xa2dfb8119879bcb0225e26f84d17188dc13593a4d8025a517aae37955b830010	payto://iban/SANDBOXX/DE038063?receiver-name=Name+unknown	f	\N
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
1	1	\\x9e465ad20ec1fb41d9afc45f3afb14ca03acd9b5ec53e31acb88abca4a053168e924080751d39fcebcb106537260e26462a8d48c943f996dde0b282fcd95e52b	\\x33128dd1bd813837cff64a730c61e287	payto://iban/SANDBOXX/DE474361?receiver-name=Merchant43	t
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_contract_terms (order_serial, merchant_serial, order_id, contract_terms, h_contract_terms, creation_time, pay_deadline, refund_deadline, paid, wired, fulfillment_url, session_id, claim_token) FROM stdin;
1	1	2022.226-038FC0M9D5XR2	\\x7b22616d6f756e74223a22544553544b55444f533a31222c2273756d6d617279223a22666f6f222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f73223a313636303439323631317d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313636303439323631317d2c2270726f6475637473223a5b5d2c22685f77697265223a224b5333354e4d47455237584d335044465248464b4e59524d533831545350444e584839593636504248324e574d4a473536354d454a3930383058385837375945514a5247434d564a4333483638524e38544a363938465753445146305041314653504159414152222c22776972655f6d6574686f64223a226962616e222c226f726465725f6964223a22323032322e3232362d3033384643304d394435585232222c2274696d657374616d70223a7b22745f73223a313636303439313731317d2c227061795f646561646c696e65223a7b22745f73223a313636303439353331317d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22373843374b47513737383043445847314d4b544656484857513332444e4a37544446564a58344642385a5642365a584b31593647227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a224146373746445048593641535236374444453354484d524a53314744504254534e47453157325638484438373057305958455a30222c226e6f6e6365223a223256353450533138454633414d335a34544e4648544559485a4632514d5144443751483539433647375a36314d43325a50583330227d	\\x30e10f96acae7c9bf6cdbba377f1ed6a57b55910c88065a1997dba4fd9285cd6e79287fc533a97bd8260a1f66c904f53180ac2a41c72008fe08cc927e75343dd	1660491711000000	1660495311000000	1660492611000000	t	f	taler://fulfillment-success/thank+you		\\x7035cb7496469b9b867fc5c1fc32b2c9
2	1	2022.226-008E3E00H1R5R	\\x7b22616d6f756e74223a22544553544b55444f533a302e3032222c2273756d6d617279223a22626172222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f73223a313636303439323634337d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313636303439323634337d2c2270726f6475637473223a5b5d2c22685f77697265223a224b5333354e4d47455237584d335044465248464b4e59524d533831545350444e584839593636504248324e574d4a473536354d454a3930383058385837375945514a5247434d564a4333483638524e38544a363938465753445146305041314653504159414152222c22776972655f6d6574686f64223a226962616e222c226f726465725f6964223a22323032322e3232362d30303845334530304831523552222c2274696d657374616d70223a7b22745f73223a313636303439313734337d2c227061795f646561646c696e65223a7b22745f73223a313636303439353334337d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22373843374b47513737383043445847314d4b544656484857513332444e4a37544446564a58344642385a5642365a584b31593647227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a224146373746445048593641535236374444453354484d524a53314744504254534e47453157325638484438373057305958455a30222c226e6f6e6365223a2247394b435a42353256343151503158335730533832453744454a505947445a42424159504b523444313641545151445056384830227d	\\x8e42c55b0c18c6ac72a18088cb898daf9233474f9a2f22776d6067f49aa0e6ac3da1b4b6c96c7b93d531ee3efbc3b8902370de925c71b2755d0121779b963515	1660491743000000	1660495343000000	1660492643000000	t	f	taler://fulfillment-success/thank+you		\\x308a77e78db60135d53d5739f3efa02c
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
1	1	1660491714000000	\\x195ef04c4532fdb2ae1967a2ce2466dcdb8c200d4f73d41c2225849867e43619	http://localhost:8081/	1	0	0	2000000	0	1000000	0	1000000	3	\\x458f33f3832b7a20992572931bdd73687bb6c1f63a9a83ce896c84ac70215d925bab2d7655e96e02a6d4abfde451a771c340cd348056b4df16e8f099cabbd405	1
2	2	1661096546000000	\\x07eec627265683f6c6a0b3ff7f0d8e5fccd7c0d64b0355b057264230026aa7c4	http://localhost:8081/	0	1000000	0	1000000	0	1000000	0	1000000	3	\\x86d288768be2b641f438b04f7b6caab313ef4552466c0dc1ba14ec614eb11adfc7dea72efa6019af3ddff4499765a74c0e9ce7af38328250100ec02cfb083d0e	1
3	2	1661096546000000	\\x164c3a5136249f47ec01e5d82353c78abd16936a8ec979e0f6fe1f2baaf0f489	http://localhost:8081/	0	1000000	0	1000000	0	1000000	0	1000000	3	\\x9b690a917f54d5ac64b2ff9284a2a2bc1c5a8468dd915ccc16e5d5154790f8441b893b6e72b2a8c9ea5389bc8d578152d981d558978c3d128b921f895f782004	1
\.


--
-- Data for Name: merchant_exchange_signing_keys; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_exchange_signing_keys (signkey_serial, master_pub, exchange_pub, start_date, expire_date, end_date, master_sig) FROM stdin;
1	\\x3a1879c2e73a00c6f601a4f4fdc63cb8c4dac8fa6bf72e91eb47f6b37fb30f8d	\\x64139e2205bcbdafdf31a9c769ed3c94ffd276dfd4515d8c92eda40ee52bb7fb	1675006283000000	1682263883000000	1684683083000000	\\x4ed0acded7de2e555fcb3d4b50208e3e483083bd4797247810808ba7dddf095b709d1197db2a2e9d01e7587f9b6869ea5eda2c5ef847487d8b54dd0f6197180e
2	\\x3a1879c2e73a00c6f601a4f4fdc63cb8c4dac8fa6bf72e91eb47f6b37fb30f8d	\\xc485dc3c300d6b3744242cf35c2b4c584b524be6f4502a42cfb4a3f2a7d1bb4a	1682263583000000	1689521183000000	1691940383000000	\\xb641ecf88d472f5c3840e4609e46be2185d843a6aaab505073a747854a6c93c4eb3f430afbc9485b5bf8bcf6909f28d62b91e4457d6e5a4752a8a970e8ee2e05
3	\\x3a1879c2e73a00c6f601a4f4fdc63cb8c4dac8fa6bf72e91eb47f6b37fb30f8d	\\x66f1ef602fe677463093668c6d5af153d585161ddeba5d96daf43ba33fb0d724	1660491683000000	1667749283000000	1670168483000000	\\xa6c2fd4d93425b6f1e2664fd941f4dae30cfe42777b7bbc0a4832bf302a037e84e3dd67b4595328a7d54827d0ab9b3f9a3d72d27ef09859ae7c753c4f55ce309
4	\\x3a1879c2e73a00c6f601a4f4fdc63cb8c4dac8fa6bf72e91eb47f6b37fb30f8d	\\xb18c0e4917ecfc89a1d0c9d4343e8e7deb737f1316e10de02199c0756e6711bc	1689520883000000	1696778483000000	1699197683000000	\\x43fa0ee04d5f518af1a3d929e5e1ee8d2a6a3a10495edf44b79debbf3d16e449148a999c6e841cbda1aae039f85d1743515ae14c66dae1771cb3027db9d2bd05
5	\\x3a1879c2e73a00c6f601a4f4fdc63cb8c4dac8fa6bf72e91eb47f6b37fb30f8d	\\x96ed594787cc48401c4bb6aa05bf648a1ad106e06405f47fbe7ea2f4944647c1	1667748983000000	1675006583000000	1677425783000000	\\x0a77c3f020563eb15baff887e9ea6a7606ff55b6ca35e3d2a2f92ac3310bfc5a1dd9f45d671a156b9940377a894039ff936b846538285a04b1a3ec2acfeae703
\.


--
-- Data for Name: merchant_exchange_wire_fees; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_exchange_wire_fees (wirefee_serial, master_pub, h_wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, wad_fee_val, wad_fee_frac, master_sig) FROM stdin;
1	\\x3a1879c2e73a00c6f601a4f4fdc63cb8c4dac8fa6bf72e91eb47f6b37fb30f8d	\\x21e4a5e9d5d17432fa0b1f7a02f8047c7634c1053d6aa1f6456ac134caa8bbf3da7776a78f85636af980472afd166b4edad654979a89d92c49a4ba992a7e3571	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	\\x3effed27b0f3c37636113fe396a594ecb065b24728754c113512c04750c894705b06b5086631ee51c6abe6ccca42f2600c1825a141dffeb73199bd8f69f70c06
\.


--
-- Data for Name: merchant_instances; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_instances (merchant_serial, merchant_pub, auth_hash, auth_salt, merchant_id, merchant_name, address, jurisdiction, default_max_deposit_fee_val, default_max_deposit_fee_frac, default_max_wire_fee_val, default_max_wire_fee_frac, default_wire_fee_amortization, default_wire_transfer_delay, default_pay_delay, website, email, logo) FROM stdin;
1	\\x53ce77b6d1f1959c18ed6b87a8d312c860db2f59ac1c1e0b688b5070701eebbe	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x0000000000000000000000000000000000000000000000000000000000000000	default	default	\\x7b7d	\\x7b7d	1	0	1	0	1	3600000000	3600000000	\N	\N	\N
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
\\xf58e8e809d3d101ab883447ec911862225b1ac7c6ef86daa67c15efbc69cd995	1
\.


--
-- Data for Name: merchant_kyc; Type: TABLE DATA; Schema: merchant; Owner: -
--

COPY merchant.merchant_kyc (kyc_serial_id, kyc_timestamp, kyc_ok, exchange_sig, exchange_pub, exchange_kyc_serial, account_serial, exchange_url) FROM stdin;
1	1660491714000000	f	\N	\N	0	1	http://localhost:8081/
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

SELECT pg_catalog.setval('exchange.reserves_in_reserve_in_serial_id_seq', 20, true);


--
-- Name: reserves_out_reserve_out_serial_id_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.reserves_out_reserve_out_serial_id_seq', 28, true);


--
-- Name: reserves_reserve_uuid_seq; Type: SEQUENCE SET; Schema: exchange; Owner: -
--

SELECT pg_catalog.setval('exchange.reserves_reserve_uuid_seq', 20, true);


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

