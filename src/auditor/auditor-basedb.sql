--
-- PostgreSQL database dump
--

-- Dumped from database version 10.5 (Debian 10.5-1)
-- Dumped by pg_dump version 10.5 (Debian 10.5-1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
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
-- Name: plpgsql; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;


--
-- Name: EXTENSION plpgsql; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION plpgsql IS 'PL/pgSQL procedural language';


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


SET default_tablespace = '';

SET default_with_oids = false;

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
-- Name: aggregation_tracking; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.aggregation_tracking (
    aggregation_serial_id bigint NOT NULL,
    deposit_serial_id bigint NOT NULL,
    wtid_raw bytea
);


--
-- Name: aggregation_tracking_aggregation_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.aggregation_tracking_aggregation_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: aggregation_tracking_aggregation_serial_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.aggregation_tracking_aggregation_serial_id_seq OWNED BY public.aggregation_tracking.aggregation_serial_id;


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
    id integer NOT NULL,
    amount character varying NOT NULL,
    subject character varying(200) NOT NULL,
    date timestamp with time zone NOT NULL,
    cancelled boolean NOT NULL,
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
    withdraw_done boolean NOT NULL,
    selected_reserve_pub text,
    selected_exchange_account_id integer,
    withdraw_account_id integer NOT NULL
);


--
-- Name: auditor_balance_summary; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_balance_summary (
    master_pub bytea,
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
    recoup_loss_frac integer NOT NULL
);


--
-- Name: auditor_denominations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_denominations (
    denom_pub_hash bytea NOT NULL,
    master_pub bytea,
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
    CONSTRAINT auditor_denominations_denom_pub_hash_check CHECK ((length(denom_pub_hash) = 64))
);


--
-- Name: auditor_exchange_signkeys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_exchange_signkeys (
    master_pub bytea,
    ep_start bigint NOT NULL,
    ep_expire bigint NOT NULL,
    ep_end bigint NOT NULL,
    exchange_pub bytea NOT NULL,
    master_sig bytea NOT NULL,
    CONSTRAINT auditor_exchange_signkeys_exchange_pub_check CHECK ((length(exchange_pub) = 32)),
    CONSTRAINT auditor_exchange_signkeys_master_sig_check CHECK ((length(master_sig) = 64))
);


--
-- Name: auditor_exchanges; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_exchanges (
    master_pub bytea NOT NULL,
    exchange_url character varying NOT NULL,
    CONSTRAINT auditor_exchanges_master_pub_check CHECK ((length(master_pub) = 32))
);


--
-- Name: auditor_historic_denomination_revenue; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_historic_denomination_revenue (
    master_pub bytea,
    denom_pub_hash bytea NOT NULL,
    revenue_timestamp bigint NOT NULL,
    revenue_balance_val bigint NOT NULL,
    revenue_balance_frac integer NOT NULL,
    loss_balance_val bigint NOT NULL,
    loss_balance_frac integer NOT NULL,
    CONSTRAINT auditor_historic_denomination_revenue_denom_pub_hash_check CHECK ((length(denom_pub_hash) = 64))
);


--
-- Name: auditor_historic_reserve_summary; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_historic_reserve_summary (
    master_pub bytea,
    start_date bigint NOT NULL,
    end_date bigint NOT NULL,
    reserve_profits_val bigint NOT NULL,
    reserve_profits_frac integer NOT NULL
);


--
-- Name: auditor_predicted_result; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_predicted_result (
    master_pub bytea,
    balance_val bigint NOT NULL,
    balance_frac integer NOT NULL
);


--
-- Name: auditor_progress_aggregation; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_progress_aggregation (
    master_pub bytea,
    last_wire_out_serial_id bigint DEFAULT 0 NOT NULL
);


--
-- Name: auditor_progress_coin; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_progress_coin (
    master_pub bytea,
    last_withdraw_serial_id bigint DEFAULT 0 NOT NULL,
    last_deposit_serial_id bigint DEFAULT 0 NOT NULL,
    last_melt_serial_id bigint DEFAULT 0 NOT NULL,
    last_refund_serial_id bigint DEFAULT 0 NOT NULL,
    last_recoup_serial_id bigint DEFAULT 0 NOT NULL,
    last_recoup_refresh_serial_id bigint DEFAULT 0 NOT NULL
);


--
-- Name: auditor_progress_deposit_confirmation; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_progress_deposit_confirmation (
    master_pub bytea,
    last_deposit_confirmation_serial_id bigint DEFAULT 0 NOT NULL
);


--
-- Name: auditor_progress_reserve; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_progress_reserve (
    master_pub bytea,
    last_reserve_in_serial_id bigint DEFAULT 0 NOT NULL,
    last_reserve_out_serial_id bigint DEFAULT 0 NOT NULL,
    last_reserve_recoup_serial_id bigint DEFAULT 0 NOT NULL,
    last_reserve_close_serial_id bigint DEFAULT 0 NOT NULL
);


--
-- Name: auditor_reserve_balance; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_reserve_balance (
    master_pub bytea,
    reserve_balance_val bigint NOT NULL,
    reserve_balance_frac integer NOT NULL,
    withdraw_fee_balance_val bigint NOT NULL,
    withdraw_fee_balance_frac integer NOT NULL
);


--
-- Name: auditor_reserves; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_reserves (
    reserve_pub bytea NOT NULL,
    master_pub bytea,
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
    master_pub bytea,
    wire_fee_balance_val bigint NOT NULL,
    wire_fee_balance_frac integer NOT NULL
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
    id integer NOT NULL,
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
    first_name character varying(30) NOT NULL,
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
    id integer NOT NULL,
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
    id integer NOT NULL,
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
-- Name: denomination_revocations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.denomination_revocations (
    denom_revocations_serial_id bigint NOT NULL,
    denom_pub_hash bytea NOT NULL,
    master_sig bytea NOT NULL,
    CONSTRAINT denomination_revocations_master_sig_check CHECK ((length(master_sig) = 64))
);


--
-- Name: denomination_revocations_denom_revocations_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.denomination_revocations_denom_revocations_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: denomination_revocations_denom_revocations_serial_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.denomination_revocations_denom_revocations_serial_id_seq OWNED BY public.denomination_revocations.denom_revocations_serial_id;


--
-- Name: denominations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.denominations (
    denom_pub_hash bytea NOT NULL,
    denom_pub bytea NOT NULL,
    master_pub bytea NOT NULL,
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
    CONSTRAINT denominations_master_pub_check CHECK ((length(master_pub) = 32)),
    CONSTRAINT denominations_master_sig_check CHECK ((length(master_sig) = 64))
);


--
-- Name: deposit_confirmations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.deposit_confirmations (
    master_pub bytea,
    serial_id bigint NOT NULL,
    h_contract_terms bytea NOT NULL,
    h_wire bytea NOT NULL,
    "timestamp" bigint NOT NULL,
    refund_deadline bigint NOT NULL,
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
    CONSTRAINT deposit_confirmations_h_wire_check CHECK ((length(h_wire) = 64)),
    CONSTRAINT deposit_confirmations_master_sig_check CHECK ((length(master_sig) = 64)),
    CONSTRAINT deposit_confirmations_merchant_pub_check CHECK ((length(merchant_pub) = 32))
);


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
    coin_pub bytea NOT NULL,
    amount_with_fee_val bigint NOT NULL,
    amount_with_fee_frac integer NOT NULL,
    "timestamp" bigint NOT NULL,
    refund_deadline bigint NOT NULL,
    wire_deadline bigint NOT NULL,
    merchant_pub bytea NOT NULL,
    h_contract_terms bytea NOT NULL,
    h_wire bytea NOT NULL,
    coin_sig bytea NOT NULL,
    wire text NOT NULL,
    tiny boolean DEFAULT false NOT NULL,
    done boolean DEFAULT false NOT NULL,
    CONSTRAINT deposits_coin_sig_check CHECK ((length(coin_sig) = 64)),
    CONSTRAINT deposits_h_contract_terms_check CHECK ((length(h_contract_terms) = 64)),
    CONSTRAINT deposits_h_wire_check CHECK ((length(h_wire) = 64)),
    CONSTRAINT deposits_merchant_pub_check CHECK ((length(merchant_pub) = 32))
);


--
-- Name: deposits_deposit_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.deposits_deposit_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: deposits_deposit_serial_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.deposits_deposit_serial_id_seq OWNED BY public.deposits.deposit_serial_id;


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
    id integer NOT NULL,
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
-- Name: exchange_wire_fees; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.exchange_wire_fees (
    exchange_pub bytea NOT NULL,
    h_wire_method bytea NOT NULL,
    wire_fee_val bigint NOT NULL,
    wire_fee_frac integer NOT NULL,
    closing_fee_val bigint NOT NULL,
    closing_fee_frac integer NOT NULL,
    start_date bigint NOT NULL,
    end_date bigint NOT NULL,
    exchange_sig bytea NOT NULL,
    CONSTRAINT exchange_wire_fees_exchange_pub_check CHECK ((length(exchange_pub) = 32)),
    CONSTRAINT exchange_wire_fees_exchange_sig_check CHECK ((length(exchange_sig) = 64)),
    CONSTRAINT exchange_wire_fees_h_wire_method_check CHECK ((length(h_wire_method) = 64))
);


--
-- Name: known_coins; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.known_coins (
    coin_pub bytea NOT NULL,
    denom_pub_hash bytea NOT NULL,
    denom_sig bytea NOT NULL,
    CONSTRAINT known_coins_coin_pub_check CHECK ((length(coin_pub) = 32))
);


--
-- Name: merchant_contract_terms; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_contract_terms (
    order_id character varying NOT NULL,
    merchant_pub bytea NOT NULL,
    contract_terms bytea NOT NULL,
    h_contract_terms bytea NOT NULL,
    "timestamp" bigint NOT NULL,
    row_id bigint NOT NULL,
    paid boolean DEFAULT false NOT NULL,
    CONSTRAINT merchant_contract_terms_h_contract_terms_check CHECK ((length(h_contract_terms) = 64)),
    CONSTRAINT merchant_contract_terms_merchant_pub_check CHECK ((length(merchant_pub) = 32))
);


--
-- Name: merchant_contract_terms_row_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.merchant_contract_terms_row_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: merchant_contract_terms_row_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.merchant_contract_terms_row_id_seq OWNED BY public.merchant_contract_terms.row_id;


--
-- Name: merchant_deposits; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_deposits (
    h_contract_terms bytea NOT NULL,
    merchant_pub bytea NOT NULL,
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
    signkey_pub bytea NOT NULL,
    exchange_proof bytea NOT NULL,
    CONSTRAINT merchant_deposits_coin_pub_check CHECK ((length(coin_pub) = 32)),
    CONSTRAINT merchant_deposits_merchant_pub_check CHECK ((length(merchant_pub) = 32)),
    CONSTRAINT merchant_deposits_signkey_pub_check CHECK ((length(signkey_pub) = 32))
);


--
-- Name: merchant_orders; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_orders (
    order_id character varying NOT NULL,
    merchant_pub bytea NOT NULL,
    contract_terms bytea NOT NULL,
    "timestamp" bigint NOT NULL,
    CONSTRAINT merchant_orders_merchant_pub_check CHECK ((length(merchant_pub) = 32))
);


--
-- Name: merchant_proofs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_proofs (
    exchange_url character varying NOT NULL,
    wtid bytea NOT NULL,
    execution_time bigint NOT NULL,
    signkey_pub bytea NOT NULL,
    proof bytea NOT NULL,
    CONSTRAINT merchant_proofs_signkey_pub_check CHECK ((length(signkey_pub) = 32)),
    CONSTRAINT merchant_proofs_wtid_check CHECK ((length(wtid) = 32))
);


--
-- Name: merchant_refunds; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_refunds (
    rtransaction_id bigint NOT NULL,
    merchant_pub bytea NOT NULL,
    h_contract_terms bytea NOT NULL,
    coin_pub bytea NOT NULL,
    reason character varying NOT NULL,
    refund_amount_val bigint NOT NULL,
    refund_amount_frac integer NOT NULL,
    refund_fee_val bigint NOT NULL,
    refund_fee_frac integer NOT NULL,
    CONSTRAINT merchant_refunds_coin_pub_check CHECK ((length(coin_pub) = 32)),
    CONSTRAINT merchant_refunds_merchant_pub_check CHECK ((length(merchant_pub) = 32))
);


--
-- Name: merchant_refunds_rtransaction_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.merchant_refunds_rtransaction_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: merchant_refunds_rtransaction_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.merchant_refunds_rtransaction_id_seq OWNED BY public.merchant_refunds.rtransaction_id;


--
-- Name: merchant_session_info; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_session_info (
    session_id character varying NOT NULL,
    fulfillment_url character varying NOT NULL,
    order_id character varying NOT NULL,
    merchant_pub bytea NOT NULL,
    "timestamp" bigint NOT NULL,
    CONSTRAINT merchant_session_info_merchant_pub_check CHECK ((length(merchant_pub) = 32))
);


--
-- Name: merchant_tip_pickups; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_tip_pickups (
    tip_id bytea NOT NULL,
    pickup_id bytea NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    CONSTRAINT merchant_tip_pickups_pickup_id_check CHECK ((length(pickup_id) = 64))
);


--
-- Name: merchant_tip_reserve_credits; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_tip_reserve_credits (
    reserve_priv bytea NOT NULL,
    credit_uuid bytea NOT NULL,
    "timestamp" bigint NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    CONSTRAINT merchant_tip_reserve_credits_credit_uuid_check CHECK ((length(credit_uuid) = 64)),
    CONSTRAINT merchant_tip_reserve_credits_reserve_priv_check CHECK ((length(reserve_priv) = 32))
);


--
-- Name: merchant_tip_reserves; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_tip_reserves (
    reserve_priv bytea NOT NULL,
    expiration bigint NOT NULL,
    balance_val bigint NOT NULL,
    balance_frac integer NOT NULL,
    CONSTRAINT merchant_tip_reserves_reserve_priv_check CHECK ((length(reserve_priv) = 32))
);


--
-- Name: merchant_tips; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_tips (
    reserve_priv bytea NOT NULL,
    tip_id bytea NOT NULL,
    exchange_url character varying NOT NULL,
    justification character varying NOT NULL,
    extra bytea NOT NULL,
    "timestamp" bigint NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    left_val bigint NOT NULL,
    left_frac integer NOT NULL,
    CONSTRAINT merchant_tips_reserve_priv_check CHECK ((length(reserve_priv) = 32)),
    CONSTRAINT merchant_tips_tip_id_check CHECK ((length(tip_id) = 64))
);


--
-- Name: merchant_transfers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_transfers (
    h_contract_terms bytea NOT NULL,
    coin_pub bytea NOT NULL,
    wtid bytea NOT NULL,
    CONSTRAINT merchant_transfers_coin_pub_check CHECK ((length(coin_pub) = 32)),
    CONSTRAINT merchant_transfers_wtid_check CHECK ((length(wtid) = 32))
);


--
-- Name: prewire; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.prewire (
    prewire_uuid bigint NOT NULL,
    type text NOT NULL,
    finished boolean DEFAULT false NOT NULL,
    buf bytea NOT NULL
);


--
-- Name: prewire_prewire_uuid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.prewire_prewire_uuid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: prewire_prewire_uuid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.prewire_prewire_uuid_seq OWNED BY public.prewire.prewire_uuid;


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
    "timestamp" bigint NOT NULL,
    h_blind_ev bytea NOT NULL,
    CONSTRAINT recoup_coin_blind_check CHECK ((length(coin_blind) = 32)),
    CONSTRAINT recoup_coin_sig_check CHECK ((length(coin_sig) = 64))
);


--
-- Name: recoup_recoup_uuid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.recoup_recoup_uuid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: recoup_recoup_uuid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.recoup_recoup_uuid_seq OWNED BY public.recoup.recoup_uuid;


--
-- Name: recoup_refresh; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.recoup_refresh (
    recoup_refresh_uuid bigint NOT NULL,
    coin_pub bytea NOT NULL,
    coin_sig bytea NOT NULL,
    coin_blind bytea NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    "timestamp" bigint NOT NULL,
    h_blind_ev bytea NOT NULL,
    CONSTRAINT recoup_refresh_coin_blind_check CHECK ((length(coin_blind) = 32)),
    CONSTRAINT recoup_refresh_coin_sig_check CHECK ((length(coin_sig) = 64))
);


--
-- Name: recoup_refresh_recoup_refresh_uuid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.recoup_refresh_recoup_refresh_uuid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: recoup_refresh_recoup_refresh_uuid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.recoup_refresh_recoup_refresh_uuid_seq OWNED BY public.recoup_refresh.recoup_refresh_uuid;


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
);


--
-- Name: refresh_commitments_melt_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.refresh_commitments_melt_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: refresh_commitments_melt_serial_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.refresh_commitments_melt_serial_id_seq OWNED BY public.refresh_commitments.melt_serial_id;


--
-- Name: refresh_revealed_coins; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.refresh_revealed_coins (
    rc bytea NOT NULL,
    newcoin_index integer NOT NULL,
    link_sig bytea NOT NULL,
    denom_pub_hash bytea NOT NULL,
    coin_ev bytea NOT NULL,
    h_coin_ev bytea NOT NULL,
    ev_sig bytea NOT NULL,
    CONSTRAINT refresh_revealed_coins_h_coin_ev_check CHECK ((length(h_coin_ev) = 64)),
    CONSTRAINT refresh_revealed_coins_link_sig_check CHECK ((length(link_sig) = 64))
);


--
-- Name: refresh_transfer_keys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.refresh_transfer_keys (
    rc bytea NOT NULL,
    transfer_pub bytea NOT NULL,
    transfer_privs bytea NOT NULL,
    CONSTRAINT refresh_transfer_keys_transfer_pub_check CHECK ((length(transfer_pub) = 32))
);


--
-- Name: refunds; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.refunds (
    refund_serial_id bigint NOT NULL,
    coin_pub bytea NOT NULL,
    merchant_pub bytea NOT NULL,
    merchant_sig bytea NOT NULL,
    h_contract_terms bytea NOT NULL,
    rtransaction_id bigint NOT NULL,
    amount_with_fee_val bigint NOT NULL,
    amount_with_fee_frac integer NOT NULL,
    CONSTRAINT refunds_h_contract_terms_check CHECK ((length(h_contract_terms) = 64)),
    CONSTRAINT refunds_merchant_pub_check CHECK ((length(merchant_pub) = 32)),
    CONSTRAINT refunds_merchant_sig_check CHECK ((length(merchant_sig) = 64))
);


--
-- Name: refunds_refund_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.refunds_refund_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: refunds_refund_serial_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.refunds_refund_serial_id_seq OWNED BY public.refunds.refund_serial_id;


--
-- Name: reserves; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reserves (
    reserve_pub bytea NOT NULL,
    account_details text NOT NULL,
    current_balance_val bigint NOT NULL,
    current_balance_frac integer NOT NULL,
    expiration_date bigint NOT NULL,
    gc_date bigint NOT NULL,
    CONSTRAINT reserves_reserve_pub_check CHECK ((length(reserve_pub) = 32))
);


--
-- Name: reserves_close; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reserves_close (
    close_uuid bigint NOT NULL,
    reserve_pub bytea NOT NULL,
    execution_date bigint NOT NULL,
    wtid bytea NOT NULL,
    receiver_account text NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    closing_fee_val bigint NOT NULL,
    closing_fee_frac integer NOT NULL,
    CONSTRAINT reserves_close_wtid_check CHECK ((length(wtid) = 32))
);


--
-- Name: reserves_close_close_uuid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.reserves_close_close_uuid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: reserves_close_close_uuid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.reserves_close_close_uuid_seq OWNED BY public.reserves_close.close_uuid;


--
-- Name: reserves_in; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reserves_in (
    reserve_in_serial_id bigint NOT NULL,
    reserve_pub bytea NOT NULL,
    wire_reference bigint NOT NULL,
    credit_val bigint NOT NULL,
    credit_frac integer NOT NULL,
    sender_account_details text NOT NULL,
    exchange_account_section text NOT NULL,
    execution_date bigint NOT NULL
);


--
-- Name: reserves_in_reserve_in_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.reserves_in_reserve_in_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: reserves_in_reserve_in_serial_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.reserves_in_reserve_in_serial_id_seq OWNED BY public.reserves_in.reserve_in_serial_id;


--
-- Name: reserves_out; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reserves_out (
    reserve_out_serial_id bigint NOT NULL,
    h_blind_ev bytea NOT NULL,
    denom_pub_hash bytea NOT NULL,
    denom_sig bytea NOT NULL,
    reserve_pub bytea NOT NULL,
    reserve_sig bytea NOT NULL,
    execution_date bigint NOT NULL,
    amount_with_fee_val bigint NOT NULL,
    amount_with_fee_frac integer NOT NULL,
    CONSTRAINT reserves_out_h_blind_ev_check CHECK ((length(h_blind_ev) = 64)),
    CONSTRAINT reserves_out_reserve_sig_check CHECK ((length(reserve_sig) = 64))
);


--
-- Name: reserves_out_reserve_out_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.reserves_out_reserve_out_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: reserves_out_reserve_out_serial_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.reserves_out_reserve_out_serial_id_seq OWNED BY public.reserves_out.reserve_out_serial_id;


--
-- Name: wire_auditor_account_progress; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wire_auditor_account_progress (
    master_pub bytea,
    account_name text NOT NULL,
    last_wire_reserve_in_serial_id bigint DEFAULT 0 NOT NULL,
    last_wire_wire_out_serial_id bigint DEFAULT 0 NOT NULL,
    wire_in_off bigint,
    wire_out_off bigint
);


--
-- Name: wire_auditor_progress; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wire_auditor_progress (
    master_pub bytea,
    last_timestamp bigint NOT NULL,
    last_reserve_close_uuid bigint NOT NULL
);


--
-- Name: wire_fee; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wire_fee (
    wire_method character varying NOT NULL,
    start_date bigint NOT NULL,
    end_date bigint NOT NULL,
    wire_fee_val bigint NOT NULL,
    wire_fee_frac integer NOT NULL,
    closing_fee_val bigint NOT NULL,
    closing_fee_frac integer NOT NULL,
    master_sig bytea NOT NULL,
    CONSTRAINT wire_fee_master_sig_check CHECK ((length(master_sig) = 64))
);


--
-- Name: wire_out; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wire_out (
    wireout_uuid bigint NOT NULL,
    execution_date bigint NOT NULL,
    wtid_raw bytea NOT NULL,
    wire_target text NOT NULL,
    exchange_account_section text NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    CONSTRAINT wire_out_wtid_raw_check CHECK ((length(wtid_raw) = 32))
);


--
-- Name: wire_out_wireout_uuid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.wire_out_wireout_uuid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: wire_out_wireout_uuid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.wire_out_wireout_uuid_seq OWNED BY public.wire_out.wireout_uuid;


--
-- Name: aggregation_tracking aggregation_serial_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.aggregation_tracking ALTER COLUMN aggregation_serial_id SET DEFAULT nextval('public.aggregation_tracking_aggregation_serial_id_seq'::regclass);


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
-- Name: denomination_revocations denom_revocations_serial_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.denomination_revocations ALTER COLUMN denom_revocations_serial_id SET DEFAULT nextval('public.denomination_revocations_denom_revocations_serial_id_seq'::regclass);


--
-- Name: deposit_confirmations serial_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposit_confirmations ALTER COLUMN serial_id SET DEFAULT nextval('public.deposit_confirmations_serial_id_seq'::regclass);


--
-- Name: deposits deposit_serial_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposits ALTER COLUMN deposit_serial_id SET DEFAULT nextval('public.deposits_deposit_serial_id_seq'::regclass);


--
-- Name: django_content_type id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.django_content_type ALTER COLUMN id SET DEFAULT nextval('public.django_content_type_id_seq'::regclass);


--
-- Name: django_migrations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.django_migrations ALTER COLUMN id SET DEFAULT nextval('public.django_migrations_id_seq'::regclass);


--
-- Name: merchant_contract_terms row_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_contract_terms ALTER COLUMN row_id SET DEFAULT nextval('public.merchant_contract_terms_row_id_seq'::regclass);


--
-- Name: merchant_refunds rtransaction_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_refunds ALTER COLUMN rtransaction_id SET DEFAULT nextval('public.merchant_refunds_rtransaction_id_seq'::regclass);


--
-- Name: prewire prewire_uuid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prewire ALTER COLUMN prewire_uuid SET DEFAULT nextval('public.prewire_prewire_uuid_seq'::regclass);


--
-- Name: recoup recoup_uuid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recoup ALTER COLUMN recoup_uuid SET DEFAULT nextval('public.recoup_recoup_uuid_seq'::regclass);


--
-- Name: recoup_refresh recoup_refresh_uuid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recoup_refresh ALTER COLUMN recoup_refresh_uuid SET DEFAULT nextval('public.recoup_refresh_recoup_refresh_uuid_seq'::regclass);


--
-- Name: refresh_commitments melt_serial_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_commitments ALTER COLUMN melt_serial_id SET DEFAULT nextval('public.refresh_commitments_melt_serial_id_seq'::regclass);


--
-- Name: refunds refund_serial_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refunds ALTER COLUMN refund_serial_id SET DEFAULT nextval('public.refunds_refund_serial_id_seq'::regclass);


--
-- Name: reserves_close close_uuid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserves_close ALTER COLUMN close_uuid SET DEFAULT nextval('public.reserves_close_close_uuid_seq'::regclass);


--
-- Name: reserves_in reserve_in_serial_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserves_in ALTER COLUMN reserve_in_serial_id SET DEFAULT nextval('public.reserves_in_reserve_in_serial_id_seq'::regclass);


--
-- Name: reserves_out reserve_out_serial_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserves_out ALTER COLUMN reserve_out_serial_id SET DEFAULT nextval('public.reserves_out_reserve_out_serial_id_seq'::regclass);


--
-- Name: wire_out wireout_uuid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wire_out ALTER COLUMN wireout_uuid SET DEFAULT nextval('public.wire_out_wireout_uuid_seq'::regclass);


--
-- Data for Name: patches; Type: TABLE DATA; Schema: _v; Owner: -
--

COPY _v.patches (patch_name, applied_tsz, applied_by, requires, conflicts) FROM stdin;
auditor-0001	2019-12-31 00:00:11.301808+01	grothoff	{}	{}
\.


--
-- Data for Name: aggregation_tracking; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.aggregation_tracking (aggregation_serial_id, deposit_serial_id, wtid_raw) FROM stdin;
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
f	9	+TESTKUDOS:0	9
f	10	+TESTKUDOS:0	10
f	11	+TESTKUDOS:90	11
t	1	-TESTKUDOS:200	1
f	12	+TESTKUDOS:82	12
t	2	+TESTKUDOS:28	2
\.


--
-- Data for Name: app_banktransaction; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_banktransaction (id, amount, subject, date, cancelled, credit_account_id, debit_account_id) FROM stdin;
1	TESTKUDOS:100	Joining bonus	2019-12-31 00:00:18.388686+01	f	11	1
2	TESTKUDOS:10	ETFB8G50QMNPYC1Y7T7M0TRBKKXXMXWPC9R8XB4RM1T2XNXYZJXG	2019-12-31 00:00:18.478865+01	f	2	11
3	TESTKUDOS:100	Joining bonus	2019-12-31 00:00:20.930985+01	f	12	1
4	TESTKUDOS:18	PDGET1D33ACRZNKB5EYRM04Z09B7MD0N5RBNNVC23RWTJYK7XZS0	2019-12-31 00:00:21.02304+01	f	2	12
\.


--
-- Data for Name: app_talerwithdrawoperation; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_talerwithdrawoperation (withdraw_id, amount, selection_done, withdraw_done, selected_reserve_pub, selected_exchange_account_id, withdraw_account_id) FROM stdin;
\.


--
-- Data for Name: auditor_balance_summary; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_balance_summary (master_pub, denom_balance_val, denom_balance_frac, deposit_fee_balance_val, deposit_fee_balance_frac, melt_fee_balance_val, melt_fee_balance_frac, refund_fee_balance_val, refund_fee_balance_frac, risk_val, risk_frac, loss_val, loss_frac, irregular_recoup_val, irregular_recoup_frac) FROM stdin;
\.


--
-- Data for Name: auditor_denomination_pending; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_denomination_pending (denom_pub_hash, denom_balance_val, denom_balance_frac, denom_loss_val, denom_loss_frac, num_issued, denom_risk_val, denom_risk_frac, recoup_loss_val, recoup_loss_frac) FROM stdin;
\.


--
-- Data for Name: auditor_denominations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_denominations (denom_pub_hash, master_pub, valid_from, expire_withdraw, expire_deposit, expire_legal, coin_val, coin_frac, fee_withdraw_val, fee_withdraw_frac, fee_deposit_val, fee_deposit_frac, fee_refresh_val, fee_refresh_frac, fee_refund_val, fee_refund_frac) FROM stdin;
\\x3b88f4740d356fd237675ab8f0c5df85d679b3c518aab8466bb9673e260c2a8a44295e90802514d3504a8d864075ac23c4cfe7b2b10c8e0351072d5fa83b2738	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1577746802000000	1578351602000000	1640818802000000	1672354802000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8bf86108b2581d5f1c5c572fc9b4610a45e1feffc78b4439c2a9135890633ee344f2b658147052c37f27d5e625e0dd783c167e3788fbe6164cf41a64eef7c439	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1578351302000000	1578956102000000	1641423302000000	1672959302000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9d1413f6bd3229b93434f02ebf1911330f84309b1d38bb95c0851adf8c33f99237e811578d794bcc57bcaca79c331878595f6c55c2d754bfb15293243e71cfaa	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1578955802000000	1579560602000000	1642027802000000	1673563802000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5c9f76a954637830ae7c89f87b30e62c896b56098c5f0dee2f5baecf9f33a0fef8579873d1339f23acd1b9a20ab9a719a84e1d2207aa372702d4d2d8854be3d0	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1579560302000000	1580165102000000	1642632302000000	1674168302000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8f1bd6721a3292001eb93649ad366b18ca5913ec76265e1e4e7b361513fe34e67a67ba358a5ae5986e7ecd292b5012d9a2406470851f549d6b6bc8ffca975c47	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1580164802000000	1580769602000000	1643236802000000	1674772802000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd655cb895daaa395be7162ed69ba27f954b87d787af1f1529457831e914be0364b90281286ad7f83587f0ebc6c26f7543de5aefe66e42328376bfb01f895fc49	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1580769302000000	1581374102000000	1643841302000000	1675377302000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x977d947c25f44cacff0658a10cdac5413028b81d29e477af88f8792f41390aea0485dd0c0cfd96659cbfc311650a04378753efcf11dad6f9ecf66cf2023adbb9	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1581373802000000	1581978602000000	1644445802000000	1675981802000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4258ec80cab9a8de233650f22dc98490de9b60fb5f74cd15e27fe75a6041ae0090f97460fce3114a6dfe6ff124171e3bb4783763168a464396a9358d94be23f1	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1581978302000000	1582583102000000	1645050302000000	1676586302000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe70070dcfeb8a56ee0d056b10dd719641dad2ad8aa6aee2037127774eb16c72731c8b390f3329a9d195052ce3af33a7d2b3faf7a01d9b835044329f86662b9ff	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1582582802000000	1583187602000000	1645654802000000	1677190802000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb73f59b6f34bec5316ef06da60954f2a6ead7ca0b85093ac624aa749b490e1ec74f3690b8f9ad43755bb5ddba5b6a8850d4ea91783fd62e14bbd99465a29cfe6	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1583187302000000	1583792102000000	1646259302000000	1677795302000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xedcd4711e09d67cdf9222dab3b2841463d3f032514db0a1617d443ca0ff7fd71bb6256f3b494e1262744f5ab1df51ddc9728f6cc542122c9897063517c6575ee	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1583791802000000	1584396602000000	1646863802000000	1678399802000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd9903b23bb2d10876f189efc43b1a20df7a575536883e0d0c620cf2ae7254f4c67117e8a3ca7771c6bb767bb2bb92d5e2cd5064eab4eeb3f3274f72b54ce1d16	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1584396302000000	1585001102000000	1647468302000000	1679004302000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf2e16063888d8ebe2fcf00db410fba9c1e456009c0c535b99de279712a1bd9fc2a0ddb1f98572c58ba9c49cfc5e605a900013c2b2c24511db79cbe2020b1b19e	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1585000802000000	1585605602000000	1648072802000000	1679608802000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xfcd4c3fef83b9194626f1ec43cf57548213520fd28076b37212f5dc937972ab836f76a526ccb823e697845ef3b3085faf5a5a3d3a1c019267b6634815f6fb3db	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1585605302000000	1586210102000000	1648677302000000	1680213302000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xcd6c5a44241d22541948b0b05b2330e9688ad448afda769b66d88ee58dba274a10b0d38003b2550fe2be43a59ab727e4059c0bba27cce1117919fb1b48d1acea	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1586209802000000	1586814602000000	1649281802000000	1680817802000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x13052ab30254225aebb0d2bb632d50eb5ffc2de49450b4d7851b9fd12c0a0e8646518f5c94a0cf7014237e76a72f055e2960a106f65e25766c87ae8b4de47dbe	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1586814302000000	1587419102000000	1649886302000000	1681422302000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x32d3f5bd975a1ea72e7a23dc42e1590416d127196d8636fe7ccabcca4a1bc7f5217a908af20aaeb7ac9ce1dffedddf2a79cdc4d3bb8c9582dfe97bf3c3cec24a	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1587418802000000	1588023602000000	1650490802000000	1682026802000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x64f5d1a01702f401ac642522fa2404a2887627f21d6c1feb248071166571f40ff55b423be17c08a7c93f2194f7701b72913441dca377000e0e86db63ad120c31	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1588023302000000	1588628102000000	1651095302000000	1682631302000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc7d15b117e8cd3bcd65f2f710d525623d7aab37f74a06c3e71a82c8b650597a57d2f08e385965f14b6ca795c8a52b80fe356f76222d264677876b005b9652c63	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1588627802000000	1589232602000000	1651699802000000	1683235802000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x97bd3d568a55223ebb48d7434a96ef94bce583c87a5cac4b469c04db3460dc90dd330df690281cea284b6e88a82836d8714c3fd35462d4dd759fa673c9b10448	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1589232302000000	1589837102000000	1652304302000000	1683840302000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe73a234bd0b83ed1270efc400332ea9acdbc157b8a0d59ee16ddffb0bd800f1ac53f50dcdcfec9feb00a2bc62338cc1c0baec7362c29f66d862a96eb6b2249f3	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1589836802000000	1590441602000000	1652908802000000	1684444802000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc20f73b3e76c27064879da4aae3da8ad7a9b20af46e6f8dafbd6c5a3828df8182c3dc008753a40c0a5dbd78f78a77eb4b97e2b8886fd52a953dde14cc842ee38	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1590441302000000	1591046102000000	1653513302000000	1685049302000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7bf958ee351909d765fabc9f16c42057c7ed83af6b5b7514526876cfe5392e9ef7ac65ae9dc29a7f73705190b2ca5a11132c1d6f9a3797aa324b6e09bd724bae	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1591045802000000	1591650602000000	1654117802000000	1685653802000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd50a48866ede14dac311275a1beb9de3326a53f488d28a57d22cf54c2cb92fd265d1de9ea709865e630980d8adb2e77b81034b83fc7cdfa15dc8bd0d45d72837	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1591650302000000	1592255102000000	1654722302000000	1686258302000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x73f4da958483d22784eb1930d307a1384a4398ada05fd59d6733bfe5d00bc4eb2eec6ec741dc30c9cb0ca5a80afe97d6d9c16503e6d97357078ea4e4a78334fb	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1592254802000000	1592859602000000	1655326802000000	1686862802000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x58075904138e55947ad4141de6c81a58b4e37af7a6654934e00910fbeddab4b374c6db0c2ce694afc5d08c4834a7a369d399dffece056527323559b307a28f7b	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1592859302000000	1593464102000000	1655931302000000	1687467302000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x59eea103f4bd5c9830dab2c07553b0b8bf557fb64a538ca44f888afe0c89b9389b22ee13507b57b78798b92b9e992b6c1a36c7ed12b3a363fb0d760fd2af1733	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1593463802000000	1594068602000000	1656535802000000	1688071802000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x290cdc0017979f232ef4b34897fe9249bb9b56a8bbf5b537d9d5393957672688d21751de0bf2e5f8b34e18c652c5a67b622a1db701b923ad02fede3d7b570089	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1594068302000000	1594673102000000	1657140302000000	1688676302000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4ce17d13831ff72adeb21e169c322327d252c187261851e1c304b75530004d7723a0060e407975dd181ed2687ba87d6ef8679758ba21c43482c8b407ffb43556	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1594672802000000	1595277602000000	1657744802000000	1689280802000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x65d5394d77a1021efaa29214387f908fd214cba7f63118fb6b25b9ba620beaa284b7d928f5ee7aa5f8fea31079f69fe1ce62b15785cde1724fa68858f40d1a02	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1595277302000000	1595882102000000	1658349302000000	1689885302000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3e07aeaf39743e7aadb115f3c7ce7ae75fe4661ae2efdb367478722682e099b1775d0ce3573b8564ea724e13f26887794fb32f1e53cb37154d6b1c02f83005aa	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1595881802000000	1596486602000000	1658953802000000	1690489802000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x22b4fe9fbee1d516c46ba0c07ec92b308b25a4ceed3c080c026782b952e55607ac3d61c2f1c4d405be9d6b791dfa435fcb0e05b85cfa59b22ba0844097329968	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1596486302000000	1597091102000000	1659558302000000	1691094302000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x80d41fd0836cfc5b52291fe5da0e81eb82233027585e0289f453b57d0223fb70f1684fec1705c19df8a9e6a40ef016dea1a0b8eb7037ce21663975200e718543	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1597090802000000	1597695602000000	1660162802000000	1691698802000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x48ede06403d2291b9939254ae67eda84a35990a55b53dde5aa77b4e621b3b69a922b26d045cc080913b1754afb7081caaec25ae4c0bdf86c83304faee0ed2c68	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1577746802000000	1578351602000000	1640818802000000	1672354802000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x95cf7e6f18c0fe7634885a8eadeacb972775211e9ff547ba320d9f81e5e01e3517c3b28eb9bdcfbe2a48e1937c0a2e5c0bb6d88ffd87ffc81d764d66756fe620	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1578351302000000	1578956102000000	1641423302000000	1672959302000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xdcfced75e70c375e1e4a90412acb72a474576d7f016d73e8de72d2fd252aee318096bb2ebb2c66b7f91a541203b5a4e9f0152925f1b804faa1ce941b0bbb91c1	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1578955802000000	1579560602000000	1642027802000000	1673563802000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x99d260bd4a7b6826d13be030364bbe290d5fd888298242ba8ebfd959cf57eea29fc0595b32c06fa2478fa6936a9e774bbf1bb1f8152d959188e663eb0e41c958	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1579560302000000	1580165102000000	1642632302000000	1674168302000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x5607944bed756f4ed32e0c8334b24ea64e5883a424b4fb8f52f663e6d914099ed9a19967db3145afed341c05423885d0d713509e76c885d6f10d37dec80c7e81	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1580164802000000	1580769602000000	1643236802000000	1674772802000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xaeb3ecea5b399d9005e87c98c240b8de4e82d7f9dd50bdb1e9faaa333273bf221c9dc78f04143409405272c4baa3cd0adc86f6ea33a9462998399e18df02718a	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1580769302000000	1581374102000000	1643841302000000	1675377302000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xc6b7e5ddfc92d364f341ff03b544f48313b87639ff5d7a0209ed7eaf24e23d03bf05cec66bf0f0387262a73a5a93e7026ec85d4ab447961333508e467369b5d5	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1581373802000000	1581978602000000	1644445802000000	1675981802000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xd007f6827e2a464928d86640e2636aa97a6c133b261d670e25694d23d9def62f36ff1b46b0cc4917108a3495de5b9a61a288f9cbb71549cf27b9e7001ec4e00c	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1581978302000000	1582583102000000	1645050302000000	1676586302000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x9bf5a751d75534dec4ebc7cbb116e263936a1160c1e06c79dd11277e1e883c5cc5b98c708256c97948d2202325abd978ae70f9054508d639c008fa4ee2daee2b	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1582582802000000	1583187602000000	1645654802000000	1677190802000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x76e3e00bace885254fe75ece61403035e88ff7a92682a5a4da43d4331c3316afc96caf474062aea35252d6d64173ee9ad402548e37e81720544e996ff205c623	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1583187302000000	1583792102000000	1646259302000000	1677795302000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x33c12d6c9daf32c825aad7ba9d10275009d3370b523a927d12528163dffc75eee26daf95e9c42b6a7b5adad898b3b0585d7667b4c676e083c721dd0656218ec1	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1583791802000000	1584396602000000	1646863802000000	1678399802000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xd2eaf8e580dba9afe8d1bcd4e85d61a56fae2f819f018aa52125b8b2021ab5167cf1052229437de0c821de1292a007bc82cfd719126342be9045d890bc322763	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1584396302000000	1585001102000000	1647468302000000	1679004302000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x95d8b2f8bb327188c1f2027abdeb8620f15cd97a048cd6ba1bfd323b5bdea8a83d15f85c6fe1d65ca93d2f3e4ab2679259ae0cbbc18ed8990f6e1c8e7e5c934a	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1585000802000000	1585605602000000	1648072802000000	1679608802000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xec4f44b19827275bf5eb676d19da41d00a44cdbf573a8345ff0f26bf184796debbe4ad3b831d82c32028d419b902612d6e5839cb6be178cb6f5a08028a33c452	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1585605302000000	1586210102000000	1648677302000000	1680213302000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xc6898dd2337eb2baef1d25a621962e116af41f14390ecf1bf3472d2de083e9f1d35bfa3459ae18c7654bf63a864107ffb4f6a1e2ec0deba997e8f5e808b2f67e	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1586209802000000	1586814602000000	1649281802000000	1680817802000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x5037808d3fb9b7d9f35bda38fa484009989834813ff54d13f4b2e745794d85023cb5f8504298d486e551e6f7c17ef39e47ce3ab9834fdbc158ee05212e040afe	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1586814302000000	1587419102000000	1649886302000000	1681422302000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x3df279924f81a661c4b119eab75897c635828fd397d465dfbb3265a709553c13746cbb732fc6ee8de78a24a0bd1c86177899ee3b98ab9a0e2c6b0a03378f4656	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1587418802000000	1588023602000000	1650490802000000	1682026802000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xfdd057dae7a94a671730993653ac191ca95c614c180bd4662a938b9613919ad05d8b79a952202b11d3181d214961e107933dc21437aea66f152465425f8cb350	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1588023302000000	1588628102000000	1651095302000000	1682631302000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x281473a6a6348d89ced1c069aacf505f36e2505aacb51b4f2ff94b06bd49734e16ef2b58bd60161f28ccfe5de2528345b49a5ac5d06953dbc1e48a0975939264	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1588627802000000	1589232602000000	1651699802000000	1683235802000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x46f47698b03d02e634d2c55591ef9528d8b91c31213899690ca589249b1fa41666bef5e4e8a0ba493f1aa0e37caec4be3b30ce4a2352ce5bd8b606ae5a98e72d	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1589232302000000	1589837102000000	1652304302000000	1683840302000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x05f253f7adeb5fc06db72b1bcbc2d22f888a882cafad1858362a51da9596a73ee947dd4686295a7f68801ecfdfdd9af4c1cd657ae13c78898e88bd9976592cd0	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1589836802000000	1590441602000000	1652908802000000	1684444802000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xcef515a133bcf5fdee949c1c96156d8a7149d247f9232b007a0946e5dec766982ceacfb32b24818cfe792c2c45a572b50548f04bb3404f8125797d3c3327b603	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1590441302000000	1591046102000000	1653513302000000	1685049302000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x89cee1f161f16792b8f7495f4ba00d4de7721de6c9c1115799f55e193797c66c9046026fdca08118d2f104c8baf8d062e2dcc41749f97bf935ba82c9773329e8	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1591045802000000	1591650602000000	1654117802000000	1685653802000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xe1b40d8f0a515db586f08f80f681acc06beab49ead0f7203ba80ba5094d973caad3b2a397275a976102cbb6b08e7921558123abe466974a4fd4b733b397ebe77	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1591650302000000	1592255102000000	1654722302000000	1686258302000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xafbc5eac4b265b1b5a7de0a5b346bc94c218df4b30e55abdfc082272e0f8b64cd672cf53e2133a93359e79d70d54550b8771367467ddcf56905d5fe469c2e628	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1592254802000000	1592859602000000	1655326802000000	1686862802000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xf5f69d57d953374abf35c95a341dce97b486be1a5ec754d22731c9d1ad37fa07c72358ae259274151240556f34add93b4f0f53cfd13ae4541b9364fbc2f0a1df	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1592859302000000	1593464102000000	1655931302000000	1687467302000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x06a460a1956c043b53c98bcd289b1b6102bdc104164a2b9b21de65f24d4801039ba81c88a571cd442ce4708e07e6fa637ed9f436b244a3f6a41da6877d8b3347	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1593463802000000	1594068602000000	1656535802000000	1688071802000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x803f673b204b656da3d493590c3a9f91fd45919c8da46ba3cefb0a1f79b590c4a59ad190ebe5f0810c23089cd40f122bb8b2afc3427d740d4f61c807b0c64d59	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1594068302000000	1594673102000000	1657140302000000	1688676302000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x60cab2c95e572d45165dab5bc8845abefe7ab93d7c8a43fe7477f35b5410bbfa97badebde0df3cf4337754c1172a1f86c5309c764689b9fbfe57ae904bd7a2f8	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1594672802000000	1595277602000000	1657744802000000	1689280802000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x0cb3a6b907b811f7c0e3993f8e4ac0af76edf2f03cdbec6e0edeebef39b7211a8eb3f3304b1b64c8ba2475b3d3217a5e39eeda6a3fe78b592a5c06f0824cb759	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1595277302000000	1595882102000000	1658349302000000	1689885302000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xbecd4e2ed9eab7f3d3ee212e6d0574af840fc082d73e0a85f3ae510e4b6ced2c6d0595f5cc9932d7f11f0105dbc4ea9bc3a1171d1c0256dbfe446222434de058	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1595881802000000	1596486602000000	1658953802000000	1690489802000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x49b43c25e668786d2f3c6fe913c9aa73f32dcc4cf7ed076b636352f74c4d75766adc1a1ec9e7d36d9d42f18932c24c136f65fc9b1f41e19fda370bf543549e7c	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1596486302000000	1597091102000000	1659558302000000	1691094302000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xd151b9e2049f33a3f2627a115c35aba4d0a44201b912dfcebbc82c4ba2405d756e9264ddfc485a99740b3f2adad67f9b070a03fcbaa5f5201cd8ade219b95238	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1597090802000000	1597695602000000	1660162802000000	1691698802000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x335c50be155aa7740ef7d610f1a805049a15090438451bc8a2c0883753bebc53f291749044c51fa1d95c691e2761b2e580959a8a7fbca31eb80ee5b8feb3e448	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1577746802000000	1578351602000000	1640818802000000	1672354802000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8513f86b4707b9cbbe1b70ccdbf448691c585d15b982dded6ffd57738790cd95ce5eadb4738fb2b4efb8dfe3c6ae1624606cede28a2db79204b7a55f7534ee2c	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1578351302000000	1578956102000000	1641423302000000	1672959302000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x567a7d305f42fd5f6f54d2195ce8910addb6e114d13dc16c0e506228c8d15b44f1ad72fa1ab2a4b6dd18387099f95502c4272021e44c961e91ae6403e5e47ad4	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1578955802000000	1579560602000000	1642027802000000	1673563802000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa18cfe15d50587433c7cd1730fe4fe7ec064b2b7e34538e710b6d4c58f54ec15558773fd2fd769d276a4c73bc79824f3edd262626a7adeb89a153e3edc13ae90	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1579560302000000	1580165102000000	1642632302000000	1674168302000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x85aa84a9b51ccc3b2180f78fc3fcd534537b151badf148a45af607a162183afce4fa3c8b9f181a2205973088a773be51ca595a9ea8108cb3f8846550de4dc3f6	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1580164802000000	1580769602000000	1643236802000000	1674772802000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xcb4c463c6265839580ece6ddd4cf12f15def860911160be607dbc84cbe534f8d6a9cae9e252c5392b731ab21f8609a3c73db48f72d960398e334a1d929cdab48	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1580769302000000	1581374102000000	1643841302000000	1675377302000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1c5e59ac8abf6dde6d696f89e79fae2df58611fa83c57a98a9033e521ac2c7f24be79d7e3b0065c0bec243b5e390d2f6d59b9cf66e4b1e84cbe15119a9838870	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1581373802000000	1581978602000000	1644445802000000	1675981802000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd669424cabb00423d72b62da78a24ff7b6db15fd5c95ce3568e8ef23f5ed6a26ba925b27262e81d1aa9352527498846afd3208d84bd6bb4cc7e456cc9865c795	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1581978302000000	1582583102000000	1645050302000000	1676586302000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd019363d36426c91889a28b160dc00bb062962eadbc310ec9b67e5138d6148de4f7c0f95dad206af1daad9007ce94c86d42f16c76b6f6cc8399437ce385d1bd5	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1582582802000000	1583187602000000	1645654802000000	1677190802000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc3cfaf8b6e51a9892d44aef504dc8eee8f4395d95f57bb9ba3f6968dcc7a372cf1a8c9e84ee7345a0966d85cae374e588a6ae29f99d6f92a0e3b087a9f972747	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1583187302000000	1583792102000000	1646259302000000	1677795302000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc5b58fc8ead4c5389cb5a7f1468489caa3f488d83e11ee54039ac4812697fca603e750331d3ba2c296d3f43f0811abe10ff3236f228e3cdec140c1efeea35f8c	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1583791802000000	1584396602000000	1646863802000000	1678399802000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x30ea4243ae92bed26496b6aa17e930995e407b13a429ebc35ad2dfa493e4d391fe7bf625335cfd837b71b6f8a367e448776ada4812245a44a8f00588ad61ef7f	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1584396302000000	1585001102000000	1647468302000000	1679004302000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc443370e6a3776df1ed6a4ce3695d4bafacebc9a17dba76140087013dc103f010b121f50328cd341ced750e36e789a5734852c1d19b07f00784cb87df587fb25	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1585000802000000	1585605602000000	1648072802000000	1679608802000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x49c08b561beaef6c12ed21b742b0a0dbf424786b6155168ca1fd298211df3ba8eedd59d3f9704ab3bbe08d525f622a7a28dc200a89003c23085471d23336dce5	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1585605302000000	1586210102000000	1648677302000000	1680213302000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x58b58545c404c5cddb8958beb199840d498065e5e9d641dc33b3edb5e53dee0faa2722a4ce211d8044dbede40a35c03e6c597e9f6f447a474cece236219ccf47	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1586209802000000	1586814602000000	1649281802000000	1680817802000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x851f3a819f8ff7a66a33423fb42d3dead7f1596a614a3adf8a347920297d8ce81964f83a74fbac19988ff012a7291a0acbfbca642fb2905ec1fa2c42e73a0220	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1586814302000000	1587419102000000	1649886302000000	1681422302000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xfe1c586b9c6e0d003cb3acce568855bc95a582ec35fe7b64b00d636df973710afdd3284ba57b9867d130ddfb9bccd9973e1bbeae2546680e17b62caac1671dcf	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1587418802000000	1588023602000000	1650490802000000	1682026802000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x13ffd7c530247b9154392d44ad4436c079dfae86b838a087f5ee29b5d0119d75a7a14a4cdd1d45bef5bcc412d9d36b72f7fc84f2d432dd484f7216d99780f52c	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1588023302000000	1588628102000000	1651095302000000	1682631302000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe00cde1ad39daa2062c6b180ea81df7acb0fefffed890e0154d0db868a881ce9360c7aceed190635652638dd3fe4b9c24c6939bb2936005b0d78c9fbcd4c22be	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1588627802000000	1589232602000000	1651699802000000	1683235802000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb31c20a7bc75ccf0e7d7a41c687a148df8e59a4cd64b0a69a74b34e5d82b6fe462a75d0bf379ed261ad7b840304ef77ee583c86c8a52ea350aab157d74dc9a94	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1589232302000000	1589837102000000	1652304302000000	1683840302000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6c82d401905f4ed56ea9191eb57ea16eb28c18900eabe5555dc1d0be47200d4b44f82b601e1bd307c17b977b602700a0031ec9a22cbe0f600ea31b150bfc1d94	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1589836802000000	1590441602000000	1652908802000000	1684444802000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6845a7dca8f81c74a62e30bd9a49ac11cf034a2441d843a5e10f0b575be99b0fe58030c3b2f9b6484a85cc129628287e7a7ebbc7f55e040bbf466e5e52530ef7	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1590441302000000	1591046102000000	1653513302000000	1685049302000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1e017f6a54426d89c0aa9cd17b10e74eec9dd8a3bff6529e33c0802501dad1c2f2bcbc4e10a8e2c290f4d63f01daf5bd0fe91a244e118f1a89a021be270294e7	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1591045802000000	1591650602000000	1654117802000000	1685653802000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf730f58fd86fc322392cf31374e6fd8cea4102f8e175107a2cee988921ec5bb75a23521e830258a5a21878d8f2ed4a57bee88d36f920903e24fd8d484d437d2f	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1591650302000000	1592255102000000	1654722302000000	1686258302000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x216200e37873db4438841e0b3a197a6d2a1f98cd53ae54c118bd0732761183c1ef0f2971d0c53ee0080b6d593613ce6b94cdbed3f8fe968a0a46019c1cb91e93	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1592254802000000	1592859602000000	1655326802000000	1686862802000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x750daecafba73862c557a230f85284acd503d3f4d5e2b0563a898fa61abd27f1fae4e85a741efea2bfcc4c89d7b341224b8b1c74017dd48e359ae3896e948e77	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1592859302000000	1593464102000000	1655931302000000	1687467302000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4838c7cbac92c7cc41e9db0e06a9a9488eda06e12e718104319da4eb01c5f86c49899a2f3598488c35aa9b476e22a566206e84090a425c95726a0f228b61c587	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1593463802000000	1594068602000000	1656535802000000	1688071802000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x09192c975b75b791a749b357a7d8534da2e0c48b7d5c57c0114a3396c115f7126fe7036e8c15ed0f01265525b03338ac8074b02b88e7ed040e6f0b62968db781	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1594068302000000	1594673102000000	1657140302000000	1688676302000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9c14c0b69413cf0e56c511fdc563336e034323a917f2a9851450066179fcfb51b911ba34b5b515cc72c68ed6d31b468eed38036c36c36472304fa69fbc13e755	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1594672802000000	1595277602000000	1657744802000000	1689280802000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb878f6c6959da9a08422cd4f4e23f11a292312a542c32a30b35eb65dac05b2b727887caffa79e948c98f3402d9b52f09ec47f71cda972383841b0f9bd31baf63	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1595277302000000	1595882102000000	1658349302000000	1689885302000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4c843e5dfa2fee60f0060b898fe94b0516ad14987be2e7373d05ec0a8dd4687c756cdc59f331be1c2e49caa2633b38b047ec62884c43fefa8e013b8f565f3007	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1595881802000000	1596486602000000	1658953802000000	1690489802000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x88cb6285dc552aedeb15d497674bb645eb1de772e537ec76c9ea32f1b7839af34b69bafc88bc72c3b99c1bbcb83b7fc1ee864b845f15e5deed7216dd1c143126	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1596486302000000	1597091102000000	1659558302000000	1691094302000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa756bfb4b5ee045aa6272f9784189a0400d948991e760780eaaec5d3a71bf08f5848d5a69e180ca3f25dda82ea85a0246740402ea8b0d95d1804ac576bbcf703	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1597090802000000	1597695602000000	1660162802000000	1691698802000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2d4cb1ced2505a75757e7ef20eb940b3f5fca66ba51e90b76afeb5d260bf17b285a4344fa3fc4bdf174fef0c7504723a23017a7eb73e0b8b16fcc084b98c31a8	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1577746802000000	1578351602000000	1640818802000000	1672354802000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x379c85a7eecd4369dd8fde804de2fba7b2fa8b796907c93afcb01ec584a6708efe5f53a1fe69dcad99cc175e50e4ea81d922da5719e6aad7785517e17cb5ccdd	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1578351302000000	1578956102000000	1641423302000000	1672959302000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xdd2b9c8674cfaa93c226c09e868c670b7cd3f25f9880870043492c54e753d83f2bddf81326be296a00b8d46dc650b134dd44581c6189ee57de89a3636a11d780	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1578955802000000	1579560602000000	1642027802000000	1673563802000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x0bb69779ab41827160c0090c68d5837ccba83181a6dc56841d12b2f87fde5cfec632d5db47fbed7086fe92a4ae7008dde1a790c5db1fa599efcad7f3bda5e35c	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1579560302000000	1580165102000000	1642632302000000	1674168302000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xadd4401875c14d767e4e42d229c0720c38cf43ead2dad6197c5f5a93fc4108d35af25246a0bad5761cc088a7a82530beb2eb1a71e2703cf4d00f4fb67b0d939e	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1580164802000000	1580769602000000	1643236802000000	1674772802000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4eca130cd2f8352b3f953aebdddd285b409a6ceefa1cf6733dee37107c37638fa8b382a114d14fb459accb7915f2d9fa925bd1ecdb8d40d449793dc87ee86b06	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1580769302000000	1581374102000000	1643841302000000	1675377302000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5f781fe934c1086fee1da9cfeddf850fd6e5896bd0d85afcee648fe3b839b33f599bf081da3743dd7daa8c54e71ade4bdd9345e0c28a455cb95414fe101b3a07	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1581373802000000	1581978602000000	1644445802000000	1675981802000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1d34031c584197dd8ed3d05f4287e9a794b2e211bbc8a6e00fd0bef6766a50fbc9ca791676d953dd7b148af67981588303554cfd00dc75a13e4f83b58eec26fd	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1581978302000000	1582583102000000	1645050302000000	1676586302000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc6c444970615f6822bb6cd5a8fe35a998cacd0c14b502d7ab0b71abb2f67ff1f98e6d39cfdd749d4dc3b8a7dec01f6943838a8092729dc9b998135a4c12877d2	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1582582802000000	1583187602000000	1645654802000000	1677190802000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4589b0df4edd8d6406c212c91e06160e6524ffd2e3c0497dfe54a94aa168f84cb7647f39d9a7a61df7982e8ec3a6788c9bac2ef73e176ae8521d805e817bef36	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1583187302000000	1583792102000000	1646259302000000	1677795302000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x73413d20d8b4160f9f4388712bbce767779fe578fb7f5684e12b28335e528aa9bb7b1afe7ac0d32927bc4d979bb7f0347b912820210f2ce0ede0944341bb87d7	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1583791802000000	1584396602000000	1646863802000000	1678399802000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7a9c0395f4f9270a7b65d34aca6a3c749414d7ca0e5748584a49c0fcf46c2ff60ba300c59206e2e0dbb52da8c70a1b0c2e20141119a23433034536ce12f84663	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1584396302000000	1585001102000000	1647468302000000	1679004302000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5d993cbaa8540ef8a0b6f5f226ffcacb6e5c06dbb514a7fb8ba9d472590279d0fa635ab1ad38f5ec90e7bfe6d978223591ff9c26093d2512b481ad1d1b59cc56	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1585000802000000	1585605602000000	1648072802000000	1679608802000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x509eab72edb241f50fe86819496856278326db2a21fa56006bdb989f906c30ab9eeb8b05a6d7d25c0af5d2709525f7fca6e87530c9b17e395667c6ac00dcf2b0	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1585605302000000	1586210102000000	1648677302000000	1680213302000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9b80cd182a471780fb0249abdf8c18f1a24b7b44bfd0513dadd0ac99c15de26f939f433f9ef0628e4a82f835d39cd504c53272b5aed43a03c49b9ae1e5cfae7e	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1586209802000000	1586814602000000	1649281802000000	1680817802000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xff5ea895923ffbc5a436759948548ad014a6a689091009cf39f2dcbe2b6d8422d732ead9daf987c4d06013571992866d1899131f16d3e0e19e18c66ad246faa5	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1586814302000000	1587419102000000	1649886302000000	1681422302000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9394e1bedb2fb7fbb8054f40c221f92c55d4ba35d275e89bd5972049eca7a6fd9f3c23056a92d6b4cb858520eae198c2faf40b82a55e1365d074656816340f51	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1587418802000000	1588023602000000	1650490802000000	1682026802000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x82e7e2dc41c5906a69df4202490b5bac9a11a8dc1a33afda2fdb4f23e66145b57675f79ac15cc7ab6e342d9e379bd5ce57b4c73ae32d7d84870c72ca0bc87668	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1588023302000000	1588628102000000	1651095302000000	1682631302000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd709d0aecaf87ec68f29206b5951c6b6ef94e070a32425eb4755801a7e399be70c46d3693718418b39ad3a104ffcc81847764d20f00b3a044fc2930388700629	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1588627802000000	1589232602000000	1651699802000000	1683235802000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x260936c5b364352f52dfe6f7269004e242955f6e05d9482bfe107f386bd45b2f9f269f412c1d0d3d9a6b01ee52917ed40b922b4a0b7e12073e7f08550577051c	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1589232302000000	1589837102000000	1652304302000000	1683840302000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2fa1cb9caa388f333d257819155efc8c07f15ac29bc32cd87b2a65d7b397793f8141af733de4d860101e1ef5526f6174cbb4f3e688a8ce4be90c44a527992c6a	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1589836802000000	1590441602000000	1652908802000000	1684444802000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x82c35fedb62405d494fc54c7edf8c53cce7f8419ee94ad6f3661007908344c8d0aa1c265426dcfb23c82e5400d42ede5b7d66d28a96619a542f6ba88b06c8268	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1590441302000000	1591046102000000	1653513302000000	1685049302000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x675f3408f09a3dcff6ea32166de3bf7e2f289088372e62964f649cdef50e0130a1c1fc62cfcb67e15d28c483c25726b412eca41c4ae50e29d93f0dea518931b6	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1591045802000000	1591650602000000	1654117802000000	1685653802000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x3910b14638ef4ea6bb7d2cc15a097a032455de3dfc875117c1c97b827303a78bd63c5ab4efdfe2dd3374499d8d4a9cbeaceb1c0eca97067111be35e3948c311b	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1591650302000000	1592255102000000	1654722302000000	1686258302000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1f435b7446bcb0fea45558f3dbda690c4e6b4a0b772f5dd4a54f94e5a1a8833c083b176b9387262a4530ee49019ba87368927dee2bb624a1b19d01764dd2c2a6	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1592254802000000	1592859602000000	1655326802000000	1686862802000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8eed7ca8302ed6556ca68a38fb1f1d1e91cde960c1c8474bb569dbee630216be5d3117050545db060ad174513ed29b21012e305e064be0fe604ca56e0d22a6f0	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1592859302000000	1593464102000000	1655931302000000	1687467302000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9ee7b3e9e1a2511267ec69dd51812990e5c09f107b3d22a4415080f0fe6453321c97457f94b6004b022a73a52ecb187ee6b7b7b2d6945da0f570c047cb798081	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1593463802000000	1594068602000000	1656535802000000	1688071802000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x45516a5af90df0d382c4f1e060eb1fa8b98be69a36cbcd61b1038e97e9ab949c11b6bccbd43b7afd4d77eb13b72d77d2c83503b0cd6eca5e5b9d3eccf703a93e	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1594068302000000	1594673102000000	1657140302000000	1688676302000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa7179d6c86af0ceeb671c499d38ee30f309f9547bc01d09034a48b277a1a748be0326e766c8233c4ab8cfdbaf7814e6f9f9df989d04110bee4b4d621111d42f4	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1594672802000000	1595277602000000	1657744802000000	1689280802000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc7055382f10d11e582d169d0cb70b74ed08d6b2c087105004d02e76e3c8375f2affac071986c8bae0d0532a4a37be4a3786dcd4931ea3ee78dbaa07289e1c02d	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1595277302000000	1595882102000000	1658349302000000	1689885302000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x95cde95be65721ed7e9c6f4050804bbc6021958f49153df3df1c40ffc917fa777756e51fe61448365d798520bd21c785c25fc62ae73b3220ea93353a6195a3d4	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1595881802000000	1596486602000000	1658953802000000	1690489802000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x3eaf3ed2f517af6fe7888ce141aecd4026a3e74db7c1cbde1a43d174ac93854203998a92fe0c70344821f564fa94525462cc325beab2cf855a087a4a8e9babf5	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1596486302000000	1597091102000000	1659558302000000	1691094302000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x547db747b95dfa5ec1d5b3d08cf1d5e60fdb3784b7d4e90d4fa05483d031405c5de5ac9944b3c787378ebb7f3a40174738607af843decc441c04774d2a003aee	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1597090802000000	1597695602000000	1660162802000000	1691698802000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7a64d9869f5495eef73d5af56b8dea3b1117257de7ac63509ecd2fb32c27f511505ebc8ea49b81b91535feeb0af9ff1cf65588cc7d1be71260809aab29a7cec5	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1577746802000000	1578351602000000	1640818802000000	1672354802000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xabd80f988ed0c8bf1eb2e612972aea60f91fcb98875c98a6b9b1bfad14c7c026feef167db5a8c6284dbdb26319de0df9ccc7afdf8db6198e6d473ae5b644d405	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1578351302000000	1578956102000000	1641423302000000	1672959302000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9a8b0cdda0b2173ea32e17bc1e5571545f4cd181805c0e794c6cee263aa7d022916b3d1f296caf407fee578943f4cd3fabfb2f6b3181387f202e18b91920610d	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1578955802000000	1579560602000000	1642027802000000	1673563802000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x06ae5b663a86b07647cf40729ffa6d58516cf54018345bcaaa34963f47570835729e14db34dd3dd8e92b10555938b9d674040d6aadb998173604c95d2ab85d82	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1579560302000000	1580165102000000	1642632302000000	1674168302000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9b0a9897691c0981a80cf6aec3d1b0312922514ebfe466c38aa063fbdd8f46c21fb1a19e3dd30783716b0fac8afa94ed183914a31047d7b992e106f21ad3ede1	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1580164802000000	1580769602000000	1643236802000000	1674772802000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7492e330c93d169ff959e0c39f36b6eeb3f0fb8ec1eddc6cd352e3f45e6f0687627a9de772caea29355b25640f7eb41edf75240a6bd96bf501d7db74759366cd	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1580769302000000	1581374102000000	1643841302000000	1675377302000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x72894c20579a456df777ec5b1ecfd9a0cc4967e8c9479b2a0450f7366f52459e5a09184e91031717aaa13c729dfcfe8cf98ac7cd95bd8d4ff055d17fb5efba01	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1581373802000000	1581978602000000	1644445802000000	1675981802000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xeb2913ef36fdeceebc9e4494b2b2c47d0d40445ce4d98cda5fd97fed7d6891fb4ea3b935675a1a8b72438fe41fc117ca1e797d26da431b446730cb0c2a0eee1a	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1581978302000000	1582583102000000	1645050302000000	1676586302000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2172c03be055952a74fbf13082dee1b04cd214d29bd5e82d66508eadf69d30f155e1892289d4e682f6f7cc792458262a33a34951798c62fda23f475b86fccdfd	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1582582802000000	1583187602000000	1645654802000000	1677190802000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x0d25520c86befd0f7e81a11a958ad87057b388579f6c631226444e63cb4113161052dad308de075dcde6d804e9b7569251f31c724de052d454e4a9cf6800efca	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1583187302000000	1583792102000000	1646259302000000	1677795302000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4ee55b591362370089a5492bb7560b28ebf02e151867dd9615e2cf9fb125eb06b7da21032536da4f3b09e84914f9bb2cb5bffd9e09b58914b3dd9d92fb1c04f2	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1583791802000000	1584396602000000	1646863802000000	1678399802000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5fe9713119f00f5374572a427b3bdfecac4131c46cec4104ecba410859c799ac670f437ee6bf0230b370cd7bda1e455b5d6fce4427430a92b98363ab80f7e0a6	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1584396302000000	1585001102000000	1647468302000000	1679004302000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa341833ae7f6528a078f042de880534887bde96eacc468ee6dd81a13b0489a2dd04c8c9c9be3471a2e18c2fc2bca3114101962faffc445011c1fac37f15eb2ee	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1585000802000000	1585605602000000	1648072802000000	1679608802000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x312a931a8c814467066875ba9f8271adcfeb1bce0b24e0ba64d2381fdf7112fa793f36b8e811ed92c307b9e027d760d4c8aa99c0c31a814ec29f0451776d7bd0	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1585605302000000	1586210102000000	1648677302000000	1680213302000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x47ab83596e88c731f5f6b555ab9053a3abdd4da144af67f499e03b1a05f1224800b028ccda88fca857a08509102a96f8b149a83e32fd4de445387eb943b8ce6b	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1586209802000000	1586814602000000	1649281802000000	1680817802000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x99815e980beb26d91488e74e9c77dec8d9a282a96e603cd7f5d9e46616f0f4fb4744c430d1febe38d2a430d45dc08f4fb5bd9bf4ec81c3244d0a059c9c631d8a	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1586814302000000	1587419102000000	1649886302000000	1681422302000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xdb3d17b874cdf9a9d6b897efe99f324d85c592be6b094de5a60b7ce5eab830f916a394f3a749c898d7214daac8ae9ea5915425866102b51dae0a5b2be4afd6ef	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1587418802000000	1588023602000000	1650490802000000	1682026802000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xcc30208d53f9b25d8c1831dbdc5794405403d8cc82ed6fa6d9e57fd5a8dcd9c6acf96286026f2a0f054fe122750addae56a9f09336aa1908f46add51ed818f7e	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1588023302000000	1588628102000000	1651095302000000	1682631302000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x005c51258cfabca016d5d776a6854f76f35d0bdf73e75fa4c56adc15b7a916cc3a0feb1b47107cc7b9d6c2284b90dc5ee18cfd4e5cd62bf7d23c146fd9344e79	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1588627802000000	1589232602000000	1651699802000000	1683235802000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x630282d268ea33d8dc3e413113a904bc31d72d4147309ed86e52931eb0f235fc29a97fe5f63fdefd4ee5aef3249deaa4d3b8a560e9cc0eb8affd88e1e69aa43e	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1589232302000000	1589837102000000	1652304302000000	1683840302000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xda2346c4a835f6e9e4c201cec4a16f08f57f5b442a61c5b018cb08a8d8f516740bb533706a0ec32310085ed2df97b4fceaec50c7b3b74d5dc14bee390c55801b	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1589836802000000	1590441602000000	1652908802000000	1684444802000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x648a2853033733567308fdd17a67c28669ba52d7af7508731c5c2a121de910e395103f69252ca334509890079c38e4b3490add54043402f04c0e72d31806d0f4	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1590441302000000	1591046102000000	1653513302000000	1685049302000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x66d10bd47f524fd1421b629acb1f04efd34f1a2229f86e644aecdd99a1c060529ae01cd491285042c8094b15f482ee1babea1ef091dadc3b04e19d655a852e9e	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1591045802000000	1591650602000000	1654117802000000	1685653802000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xbb7be83be4b88b8a3b7849661c6a8fc741d79b817c3485ab5189a1ec2363d2ee3da45084b3352bc3f3fec3e31422c75e06467f311032e257ddfde6c994eba925	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1591650302000000	1592255102000000	1654722302000000	1686258302000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x16921c3ceb997a80fcbc6df2edeecb6d6ac8b51e69025e452c5f7b019fe5ce7197f2919c34267875575105e9058830d9bf4b80382111e9ee695a2464b83c9989	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1592254802000000	1592859602000000	1655326802000000	1686862802000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1217cebc2ad5c6bdf632f2a7af8bc469051f394ca2ddbee74bb437d2e5a8402c850770f212b4786406541d3f0f8ba72094be5c28fe1031e6ac1a6560c61cb107	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1592859302000000	1593464102000000	1655931302000000	1687467302000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf2278f36ae521b9586dc68a47a4a459127b5d48741cbd5e3ada93a61305c10575cdb13f8cd9882c403fc925d3ce5ce61094b9efe33b7f256e67ce128eb86e7cb	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1593463802000000	1594068602000000	1656535802000000	1688071802000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd4b182d7338d9158ba137ab5c91ff041d6ab779e07ed68caf0a716c438fa72386c8561e2bbb80360e712066fefccd0f6520c9965cbc04b4b1f6651f8b668aff8	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1594068302000000	1594673102000000	1657140302000000	1688676302000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x3515715268f548f2277017d7d12f3d24abcdd609da26775544b0330823ad4b717fcd9b0b9bf9c6df3659544a714c4867a177a5a51e0db6a1a33625c6e1fc6338	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1594672802000000	1595277602000000	1657744802000000	1689280802000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x72c3f4f81e0dbfef8c7785f0376682fded4c4c12d1bab34568d016ad91f4a1575bb3ebea9d6bdc6f38bf21b321731bfe687098c1426f2ea67e0983f429aac627	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1595277302000000	1595882102000000	1658349302000000	1689885302000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x47dbb0ce06096617e9c4f3fe9d489c736b3e2f077d08dd50c782e653921d6917d1a77f184d2140bd8d74c23c5d42ca3233e18b99569a1b974d91dd95bf71d18e	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1595881802000000	1596486602000000	1658953802000000	1690489802000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x00b7ca2efb36834e7dd7adf2a7b27ba8c238729eefe745aea19bddf48f0edef024fac78a3e5b699606166071196936a53f9bde58f178689e422c28756a73addd	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1596486302000000	1597091102000000	1659558302000000	1691094302000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x38fef7fa447ffabe6425a9c55c966993a608a55572b7c4b961e33513e8b9b043b109a243797c18d83a2275a89877a7f85335a11287f3ca82f41a39e077601870	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1597090802000000	1597695602000000	1660162802000000	1691698802000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf9dfec817b3e35ab7d322115daee9bbee46cb9e5e479590783b7f01428cb0cd7b4aebcbecf76b01fe2e5e625255881e33aab8ae03c683e243f15bbf0fa6e8863	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1577746802000000	1578351602000000	1640818802000000	1672354802000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x431b60e89580670f5d9ac7413b63868634a816e5be13634760b7e2a1529c1d9957c9c32171426e1cc861e3cf07e9dc0ec06a571a7cc0b2b95bc594f6cbbd49a9	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1578351302000000	1578956102000000	1641423302000000	1672959302000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x3b45a7ddc5396b844ff51d44e60669b67b4c81feeb5ba48d75e66fba9e17a7c5c79cb6a95820774c852f110dc545836eb0bd2fef5b05edb64bab17bf208a07b0	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1578955802000000	1579560602000000	1642027802000000	1673563802000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x702027c066989929936456a3aca3a8889794b832a77b9b9fdce242aa499ba9b8166f83c443f896f40724dd7ffa27d1bb31c0a585ee4efec0040b9b272148db6e	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1579560302000000	1580165102000000	1642632302000000	1674168302000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x9907a13c32bd9cc8032d4d10018c88d71ac8051cccc4ac48f9ee154efe2ebb169bdf4b69dc8cb67dbae9787fc1dcb1f3af4b5349ef32b6be2b1492c4be3e3245	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1580164802000000	1580769602000000	1643236802000000	1674772802000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x00c698e138dc3dbccaa99cdba3d23c59f1e49eec83ead5bc83bad83e42c4aa52806ae91b25bf9413b98b4795545554d4b17ab3d6354b328d3a56b9c1b2b1551d	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1580769302000000	1581374102000000	1643841302000000	1675377302000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x765f50c766748022a052161a386be503b08bc2f5735e0c0faea1b25d4097bab0cf27f615175c719fd079f85511f234f596094dcf9ab22c5360c48ffec9ee35dc	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1581373802000000	1581978602000000	1644445802000000	1675981802000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x15e838d0df71b735b98603890d8c7b422764dadedf90a4df296719b68ed6f4b898aaf0604601e87266b4e94dc26e536514e7f3dfa9207d5168d2f6849414275a	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1581978302000000	1582583102000000	1645050302000000	1676586302000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xf90c42a73a3772f732b6cbf878bc6f9c8779c8306a085e0c237cf17690c288b22eed1e09595b081645650d5585e07ce26f9afa7151d5bb49945d7d493baa191f	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1582582802000000	1583187602000000	1645654802000000	1677190802000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xfffd94a748983533a0b8c0c20512440af66060f73888df1c1189a222e238755b6cf1eac939cb13940b4a7c65e2c654f8391b2c3339b94817dde3ecd3fc5e315e	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1583187302000000	1583792102000000	1646259302000000	1677795302000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x7c4d35dca752d7cc3b38e3021dcaa5c371a88bad5340dec3ee25515e581b0bd0dc28758a77a777f49315ddb9c5a913c3bd92c611a617e46503902c494e9d6d58	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1583791802000000	1584396602000000	1646863802000000	1678399802000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x784932e0cdd9290109f35b55e266a56894a093dd9548e82797f777f6125acdfb55d51d5bfd656497af9c856202dbaafef38dd982eddbb433d515e41b4fc64a18	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1584396302000000	1585001102000000	1647468302000000	1679004302000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x9b9f5feb879df171480717f2ce7b4f1590fe3358bdd89ac4bd9da4644cab39abaec5a9e242ddceb8aaf415f9542058e0fcfcdf0d6aba9cd0873bf0e52b2763d3	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1585000802000000	1585605602000000	1648072802000000	1679608802000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x2aa87a590b5511000ed65e49c329366ccc77bcbc4ecf43f921855a679b0ef3ea5e25b57d0263e36e3723853d3dc129d4aa5a19654f9aec4fe093486ff60b93b3	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1585605302000000	1586210102000000	1648677302000000	1680213302000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x147a5b381268ad537d4c18c5739ef08e87b24d69f45914e8fd801f54377c69280fb544a257e774e4587a380329ec97f750edf7f53cc9f9129d81517c050d7f31	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1586209802000000	1586814602000000	1649281802000000	1680817802000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x7b5030e52b6a536609162d4b1bcc99016e3812b3b516d64db4d246223abae383a734bbe36b90aa8c6b2239fd2ba436cfe3b84002172e2a62bfda8002bda77fcd	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1586814302000000	1587419102000000	1649886302000000	1681422302000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x86677fce3ebf68a9e3c33c3d24357de57ac3f2752deddc9efd4c41d7b180b9b6bf49e674307a988e5ceb6f469da33819b84d112b222219e5375b89d653e3654a	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1587418802000000	1588023602000000	1650490802000000	1682026802000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x8098e0e227b5a6b0bb8cb9be7d580cb5cf631065559b41fe8cafcc47d35888c07328991aedcc62554ec06e84a125fde81091d4c946d27e10f62fe942b215c059	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1588023302000000	1588628102000000	1651095302000000	1682631302000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x500d518895af223dcb14cd70a793dc6f2f7d2e1ffe8d9513c6e59cb2cf195ec6bae632884aa163d84dce870eed56ff627380128ee54dbaaabd48678693f0cb26	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1588627802000000	1589232602000000	1651699802000000	1683235802000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x32282d85be33c73109ccacafa73b0d42c46031ea090166a1f080e3a482181b9fd3a844857fcf12f74d297ec2021457c12f48ec354f3609c4b2866de7d9dcee3a	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1589232302000000	1589837102000000	1652304302000000	1683840302000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x44b9c2b618bd2b047ba669ace12855bfc77b8fc41647856bbb9f029f5b879dcaed8bac3d9eefe63e085ccdfd2b3d07ae59bfa4d01e72acd359eb4eb9980645d2	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1589836802000000	1590441602000000	1652908802000000	1684444802000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xcbee23642416386b66b5c7e21158ff179aaec923f9ff3a3eabe92dabd61a5078aac749eedcfb811e1adb3ab993edaef6568b3e74313a9a7cb3e97eec744dd7e3	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1590441302000000	1591046102000000	1653513302000000	1685049302000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x91ee41e8e4d23379fbd221c1e4eda8a4551e3185ae4e2ce3f911bea01842a752aad8eedc2b2598d06b6f31e1ea4abf159e8d00dcf5a7c009233f58f2fc11aebc	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1591045802000000	1591650602000000	1654117802000000	1685653802000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x27a6d7389cb8f787754102faab79e4dec2d504a5525e4a832748972ac8ac058d01137d1f502f6d8aa582f63a53b7aad0dce1648c10fee2d0a48250d1c06cfd79	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1591650302000000	1592255102000000	1654722302000000	1686258302000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xa5a6fe3d1f09978a72c93a22c02be7ed48275e6d5a1c94f856b3384b9a86ba6487f4119e764e13a18c8816142ed3a46460c413d377ab0ca4490c8f9cb47138b7	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1592254802000000	1592859602000000	1655326802000000	1686862802000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xf5e44406462ee0213fdd58f74ce9aa31caf62868e31f7758e213f46690d24343164278161a5f5231c457a04787254b019c8f9901e091a5bf836e0b5b3def7963	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1592859302000000	1593464102000000	1655931302000000	1687467302000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x025cdaf111a5cedd9b7c77d053411d54e573ac6e171133d6c3654ab05290a27f386c114b966a227db581dd4e9a4df257bf8b2a562508dd0a0819972a4fadba39	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1593463802000000	1594068602000000	1656535802000000	1688071802000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x3a9a45ff5a2b518be4166ab2c6a70b5616ecfc4a9b8f8d4b5802f0f6bbaf89ceb9c1b064ad48dcbbc81d367cd72b6e639c35b258435414f8811f06ae50d2cc23	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1594068302000000	1594673102000000	1657140302000000	1688676302000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xdc47d83bf84415a7ddafb4568de384762ccd25994f290dbfeb021df8eda5dffac047d899d8dcdea28b2f495ec9408bf16f3f08b490a11e018802684cb58bc317	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1594672802000000	1595277602000000	1657744802000000	1689280802000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x547302c716a97ee599267ece4e2a857da1b41a86dbd39fc0a083a4c78f03ff1b66ed11cec8f617a1eb7e1b6b362f5a71cc2710bbf403d68d0d606fd334a0faef	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1595277302000000	1595882102000000	1658349302000000	1689885302000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xb8f478c5afc2dd384f932a217da404fa8c78baa08d58ca8a8b6840518afa804deafb30ddd4a38e936e1df2a43602a72c7d755360d64eec27efec2aaed1ffa02c	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1595881802000000	1596486602000000	1658953802000000	1690489802000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x8617acc9f4cd871f4698531b19d27f86910f6e963a95b8c7b40c4af20e67818f0e40af1169986fe8361271c6e2ff5be587d07b2e5caf44bb81f9b4e62f4bc4f3	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1596486302000000	1597091102000000	1659558302000000	1691094302000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x54b2175b600538527854b099e921aaf06d78cdb7d86ab3781c5501b42e524f9ccde057da45c90b171d8baea4b9ad46be0ed9693d3464ea0e50d4b6951a1a9fd4	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1597090802000000	1597695602000000	1660162802000000	1691698802000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x860a9106ae6eae432b56bd506c28c284de8de160911f8fe4f8d83c82a49d17cb19bb387e7d6e44ab6a96df96fd7eaa5f77180d52ef5b542d2ec7b50e7fcd7124	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1577746802000000	1578351602000000	1640818802000000	1672354802000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xe929357b2a6d1aa4d0f9b9342ca65aaaa5bb141831e07adc0659c3911f37ffa114b7574a2ebef04f5f4f5ed71a7dee1ea244f82518a099c36f3d952d671ceabc	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1578351302000000	1578956102000000	1641423302000000	1672959302000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xe75a2a58a7c6b0cfd7781e600d1045d46b1971cb7f1d8781dacd4104b176d71e46d1b92eaa8a5c59c787d3949045fb85167b611d783194e9ee4a9443f9b75afd	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1578955802000000	1579560602000000	1642027802000000	1673563802000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x82bd0a9d09a5dfcb68abdc127041092b0d164b9bfd7d0bdf2a42326369b7c4a4c8d6296e70c1dd8c15fd6c9ffc0abd35a3b982c78d0e79edd89691ebe010066c	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1579560302000000	1580165102000000	1642632302000000	1674168302000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xe27376c0294bb98032f5d5320d167da2d0eb6bf41cde68c5995377d6ce84195df2da73e0d713d8355ce6e85908e5e1f573ec20adfd01dda028ca1bc05fbbdee9	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1580164802000000	1580769602000000	1643236802000000	1674772802000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x4afba47b230ecfbc6caa9778c84ceea8c122d18ae731a7e43ba99cbb485e5b2890fe063d6be2b38d578f242d15c896881f5cb7f6027c55f42aa31e77a4700704	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1580769302000000	1581374102000000	1643841302000000	1675377302000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x8f9ac9f4d282c8cee3b64533c29268250483fccd48fd1bc6b12b5e40be954884af1263d7febd06923f9e7a28f8ae01e189994f988892828c00f0fdd6277b1aaf	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1581373802000000	1581978602000000	1644445802000000	1675981802000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xdeae6be84fabf79eacb045e2bd585217ca3dbf8c9cbad97d16d8645fbba2085a2e77830e65d784ea57c3338f238031e3a8c903d6aaeb8281a61cc6dfae787163	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1581978302000000	1582583102000000	1645050302000000	1676586302000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xfca165a28f7aad1269a324280e23f153cdb77f201c3669bb7daaaefb0d54bb70a4f7124065bcafef27601832c651e4bae0622b460554bce7dc8637010b6411c2	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1582582802000000	1583187602000000	1645654802000000	1677190802000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xd16f466290fedfa6bb2d324456b95926a97b1ef82baa52c7d3a784f15bf86d48df5ebb9d90ab87e43821af6d7c6b0be0ca9b1f40c4c1b1fc474039d982fe0660	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1583187302000000	1583792102000000	1646259302000000	1677795302000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xec1384c7fa7999daa04aff4c8ef492fc7d480b8c85cc9cdbd1c24745ad4afb76aedb2e3b8f8abfdfb10726073b21356db2cdd0c5e2cf6c873085da1f0151e608	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1583791802000000	1584396602000000	1646863802000000	1678399802000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x7a5beb9a472ecd828139c6d11bdac353d1d3fc9d3889ca38aae33ad4291794d8c168d2eefae6216837ce8c79e0769db39dcae56f33bae842759f0dd9c86659a6	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1584396302000000	1585001102000000	1647468302000000	1679004302000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x8efb4e91693af04ea1ba05ba3bd8bd542137891a9e4d355b92c2e0993df4cc1052fa886a6b1d8e7aa0790226fbfe4c79fcf8d63e2876a4b649c6b8cce1a615a0	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1585000802000000	1585605602000000	1648072802000000	1679608802000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x30152847b4bdde599c946841c5d8bc8e795d558fe64d41159aeb8a10c61b53765f7d518734e379fe0320b34db95d9d155c3296f8dc0ddd422f5f01afc45b57e2	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1585605302000000	1586210102000000	1648677302000000	1680213302000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xe028114351076407dcc5e301824191a546a37b726b5f8fad43b8f70f01bb8795b6408b522206ee2f92ea6ec7f93a3a8c1fb34f71175492a6ac18b9035e650d96	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1586209802000000	1586814602000000	1649281802000000	1680817802000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x3c486fdaaa49e02629ef37664981f8f3ff83b17d880dd3080ab149b2bd2f7fdf71396c4a8160bc400241ea9a6c8f0cd71c78ee1ec9411389751504681400d8cf	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1586814302000000	1587419102000000	1649886302000000	1681422302000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x43b91a6bbf315090efba8a90b27e9fbed595f5415f6b81fdd65e08edf0ca6abcb7e23cf6aee21db28b9ae9aa96b5ee0154bdfe0b775736c78bdcc4ebbc495f6d	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1587418802000000	1588023602000000	1650490802000000	1682026802000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x7cbdee56291c020482188638cdd8f96d2ff4b49476d851fc3135524bf9cc35bef10995a06b22c5747e6eb1e489078fb4c283a3ba158d118d6e5a4e33a1328e8a	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1588023302000000	1588628102000000	1651095302000000	1682631302000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xe9f52d149e7be4823ba730e2c4b339002c28fae876c693616b34f797d603b060d4da2e265a80cf77e1dbeca7c67816808a8d7c80bce3b4bfc3ad918d90879b5f	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1588627802000000	1589232602000000	1651699802000000	1683235802000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x7d4e16f461cb0dcf9c3c875ba2cf960712d1fd49986657208b2c0cbca951682d1fe89c4e952839c53da0ad8564f9309ac887631369a5fa8b5abc39205d5d3d2e	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1589232302000000	1589837102000000	1652304302000000	1683840302000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x7b7dba6eb9777585a6a9318ebb68c94fc4df4debc0625c6dd42423a1dead0783473974741d06ed33714ce21166d9d7367e8b25801b03f2c25be3356b393e8b8a	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1589836802000000	1590441602000000	1652908802000000	1684444802000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x1b4f709d50314191831ab5cf757a1f0c481d5b7c437ecd9e5a8be95d077343e8d8e66ae2330ee661049e9d5e6269a5db4c2ac5ce5a1720ea92ed67d737e4c233	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1590441302000000	1591046102000000	1653513302000000	1685049302000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xe6c5b13503436e2b134f4281d531224f7e2d1f8e4381ca5a2b49647466c141b656913f499f702611b7621f1a208d83fc7b58ee36761125ee0805146850260b41	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1591045802000000	1591650602000000	1654117802000000	1685653802000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x0fa1bc6301214813fbfd2c51368994d933bb07de786a6b3395286060339298d88c5adf02172344e1a90fa6a16c8ca4a884ddc605ea10b6772a4ac1e30b768a58	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1591650302000000	1592255102000000	1654722302000000	1686258302000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x0a7c1972294deae010f98b74135b80afb62c5b5c1ddb1231423659ae8dbc94d840722a603ac64c6a40188b1c58f8d24055fce41ebaf4808c9af915c6ea6bf267	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1592254802000000	1592859602000000	1655326802000000	1686862802000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x914df3fa80fe75191cce0c4f0d70f0de8650c1a237787db0acd8bdb9e37488335f895b9faf5728475e427fb3937bb184508c995a68ddff55460a8577f129edac	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1592859302000000	1593464102000000	1655931302000000	1687467302000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xdc5001d9d727d41fb45a5dee65bb293be6b075a694d154c94bc1762c0700a5af43edb2bf6ea0cb9df5910caa1018cd3269ce09853edc0d44ec8646012b3ffe03	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1593463802000000	1594068602000000	1656535802000000	1688071802000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x0d6139559c352358a650eba48935c5394338aea7f6a46a10ea3f546d9ae75b14ea2cb3d5f46eeadf216d380c6a62a500b03e56d876f9fd95247a5e46c8c4d339	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1594068302000000	1594673102000000	1657140302000000	1688676302000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x39a0db523723fb5ee9c8c1cd255e04cfa425317c59f9ff3cd89cbc3ebc579f7d949f7b8a2cdd747ffb7da77b2cc296955511b366916c1b7c4f7f56f18722fe4e	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1594672802000000	1595277602000000	1657744802000000	1689280802000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x4834ccb9ec16f0b82b6f51b1bd9ab686ea95c267a99458fdfea3dad69195522917ed47c392d45aa1bb53e29732301257d0106557cc52c80a04912e87834f6f98	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1595277302000000	1595882102000000	1658349302000000	1689885302000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x618c59a4a4ebc401a41cf24a8300ef1a00b58400d1ab64de9af56c4a90f2e2aafb1e51f06fda24c1b579f9d835d11c78224b7f251da972aba3190811af52392d	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1595881802000000	1596486602000000	1658953802000000	1690489802000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xb84ac58235aca5c36c9a1cf485744fd730797b508eeeaaccf871af606675399c11984837ef204ee9122ef201b0d0dac7effe37df77ba879502f4a36f83a49071	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1596486302000000	1597091102000000	1659558302000000	1691094302000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x3d6790778848572794a449fb88b13e18185279058d43308b1baba481ae1a6b72a8b9a2d68de39b51f687eaa88a803744037f5f86358188e9e22dec7c87ffc58b	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1597090802000000	1597695602000000	1660162802000000	1691698802000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x5cac576b6aa21e7df191af5ee270caf70a0ab3a64cf16006984a44dffa43d6021188fd63c00df4265316d9ff6f415f9e06f83f50996962da962309b78d445a42	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1577746802000000	1578351602000000	1640818802000000	1672354802000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x1b88a637c160c2a05ec45f4ee46f403d67081ff332641a1c7d1db295c7da104144ec9941964b2336820fdb74b4890b5ae4e56e62090c3150c6861a1a7662cff7	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1578351302000000	1578956102000000	1641423302000000	1672959302000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xc23e5c5759c9c95767c271fd3d403f470d806b86815cf0ae3491c9b4fd50860ddb3c215d0abfbdd175e30905bf93a9e4de6d0363ec3aad3bbdcb0557152b5a06	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1578955802000000	1579560602000000	1642027802000000	1673563802000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x7e87032b53ab052f0d26d925586b9e657a5bac6e42e31f48d2437cd905268796fe1509e3e010c45babcc920f095805c792073f5b93d01a7b743a1a29bf60b82c	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1579560302000000	1580165102000000	1642632302000000	1674168302000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xc35dd33025e46b22996119f88a836429f11fb7c936ea7cb9526cfc8d2a6bc3d122395f76ce90ea18c96b78cf7d377eb2d2c7e715db97047731b373914be99632	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1580164802000000	1580769602000000	1643236802000000	1674772802000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x941d33620b1ece2d31a5e1fdcc0abf153b6b01085491a3b3d902eeed638da3ba3b1c4d7a4afce2a03553598c5effe9639d1c32122b64d6365544146728775736	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1580769302000000	1581374102000000	1643841302000000	1675377302000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x802f92a825450088ac840a4af877117c811b381d60a75bb8579ad37358f33606f39785e7c73361ceb7b3467caeb464130b0aae1a965f44a7f11f40071da53d22	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1581373802000000	1581978602000000	1644445802000000	1675981802000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xc1a13313d1f50badff318b6ab6151c43e4af31174a81c0a46092673757e5f667de9b3920c9ab80b119f4e0df6fcf7e3a9cb4128c66ceb7f777dc72277075cd78	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1581978302000000	1582583102000000	1645050302000000	1676586302000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xe905348406ad53ee00fd066fc25a914c596133fe4a5c5561ff156db7276ac0f7166375d9589d72cbcbde98566a57972cdb7455284c4bfe161299fe7727c195b4	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1582582802000000	1583187602000000	1645654802000000	1677190802000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x5533127e2e601957154a08175b59b3c1f38673c8c1a2b7d297cc4274e59993ede9e534881552d9ea7da728196547cfc79d74d4fe262c700648d47530ffeb6ed7	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1583187302000000	1583792102000000	1646259302000000	1677795302000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x4b237562186632f848a4e39e5f9226df5ec578fd5d7fbaa6d5779fd9e26c5ce1e25a55a16dc399d412cd21843e67e6834f3d1aa263e88ceb657e25206cc12973	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1583791802000000	1584396602000000	1646863802000000	1678399802000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xe2add1bc828c74cea649dfd77d96c1423c5a62d95672282577999924493f8aa2a96a5a8cc644b131d5c77bffdddcaabbfa5129317b7b95f4f8bb96efb69b5e9c	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1584396302000000	1585001102000000	1647468302000000	1679004302000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x35877389dcbd99baeeee080910f8df156c1c3cca15827c5ee908d7ab98909b06782ea82fde498e92904ce46981f9094fc2aa5f2a921a459cb875fbde070b7576	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1585000802000000	1585605602000000	1648072802000000	1679608802000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x66fd77a0af88bb40c1ef89619a058e1942a6b744e4ec7c8299353beaee32706fad7b6e697f60ea069ace815a6be60d4cbf86bbb0d874c9d554a3b10b67a09999	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1585605302000000	1586210102000000	1648677302000000	1680213302000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x25dc7d90efb3c684ffda0366e080af5aa6903818966dfebf1008ae6b72ce60b4f2c2fbe9c1719532f6adb29cecb4e9067458a969527fe33e375583e10d2351aa	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1586209802000000	1586814602000000	1649281802000000	1680817802000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xc06f30738e8afc64b6f9c6e6b490baf047ff7264850e77d62fb661b16e67806920062aad849a480c707a6efbe686c755c9dae77b911616c0ab63ad79f4c0c512	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1586814302000000	1587419102000000	1649886302000000	1681422302000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xe1397d9656ca7006f2b0b8fc9f27d0b532225456fb170b385ce487cb70b388c466df722ff9a5b320b725042e899665317a681ad558f92e55b749bc7416e34726	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1587418802000000	1588023602000000	1650490802000000	1682026802000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x93ca75bcf5fc04bf6f3f3e6ce233ed005baa5a730391ece9611a028699f6f4a25bbd91d55bce0e6f78e7bcc1dec44d663b879482d403128725b43006c77464a1	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1588023302000000	1588628102000000	1651095302000000	1682631302000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xf3a025886fab0ff7f1611c9d646918851b3c435588329d0ef2c435b7782f0774e8080e7b6852fd7345c9aad9277f7c271e373cf5f06b6193fc2bf4f8a484181d	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1588627802000000	1589232602000000	1651699802000000	1683235802000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xf07fc5ab79a0d7c97e72f9d3c182df673d7cd32e09a6fc779a2cbf9d0d2222c4cb5321a43c62cd58a45481a36a2e38398748fa12f4645464c3d2376b56236123	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1589232302000000	1589837102000000	1652304302000000	1683840302000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x884c955e5c8fed79fed515746626f2cd7c13a2a10ff99b9a5446a8eb2b458d848959a8cbccbd4472d9da233db19d2bf11f203104136cca66a2b4ffb6d10b1b14	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1589836802000000	1590441602000000	1652908802000000	1684444802000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x97bc7379b0efa41ec3b5a7b32b089e7feceee3b2260b47d94534570bc5d6f36a1303a3341e8f49d397062dc374ee248c770dee43d2b32d69cc06d33e5874a427	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1590441302000000	1591046102000000	1653513302000000	1685049302000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x49ca26365798b11e033d5d0c1c740527746322e1985517589015b40fa7018ce09e85e0f3a679811aec4b2ea040c8c9015d339717692ea58b9d0abb8daa372473	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1591045802000000	1591650602000000	1654117802000000	1685653802000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x2490424a7af67a3bb2a7ea4279a6e2391b6c4fbdcbac9dd218908f55b6b46eac5bfb5b9b54e50ae3136c52cc3e969365a0da8ff210698cd26ddba43922a2639b	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1591650302000000	1592255102000000	1654722302000000	1686258302000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x011d2ea7994726bbac0f01e559b9984aa1d905c04bc3316f54a7f36ec92510e0eb94518db72ed9ba2941ebaf2d7bfe98775a90546e8dc0f92da3d6c13d0c0f1e	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1592254802000000	1592859602000000	1655326802000000	1686862802000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x953bbcac1d279aa6bc2bdeaec635db7d3362feea4982f89d6da9a94fe89db461769c403e33fbda87103698f3c1fb71be5656a1d04863ef2e56818af773b54e45	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1592859302000000	1593464102000000	1655931302000000	1687467302000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xcb622c3621597e99ad85f9873cd4121a532478c6180932404d248fb26afd451db437bb0c7b5dae3fdf79b818f80200a2abd8142056e2bc0ba27abe25cb676e63	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1593463802000000	1594068602000000	1656535802000000	1688071802000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xb32a964caa2a68bcc1239dd268a7d7061e3cd8c7d9d5ff4333f87ad19ccefa11cd80765abffd1235d1c86f3ebdce5948000e768dfe5c496750cc1953a07e8451	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1594068302000000	1594673102000000	1657140302000000	1688676302000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x4f5e299d5f24c7b4634f282302639053cdfc604d7f44e74e259f7aa294b03af2684867af7d513c066c5a518d8c79d41d8e8d8d82da616186153aa0b1b1915267	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1594672802000000	1595277602000000	1657744802000000	1689280802000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xc2bf294c653cf3b8e07a542a86ce891b2b579337f54773179c60c1695afd93eec72b4c7c956d456d36634d4ff006ee01e04f499ffca7b3d61c0245c4e290d1e4	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1595277302000000	1595882102000000	1658349302000000	1689885302000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x1df6be6b74fad29bc12f7d0e1ffd1831ba0e2dcef0ab85356c832d0ce29972c9f8b6ca735c3b58222e69e4c9b3e770642802828d9d5392e028e2c054252a1ac3	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1595881802000000	1596486602000000	1658953802000000	1690489802000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x7df47cfbc6378e434ba1b593fe84c4c2c7556c6a7879f956a105a2aff10a1240bfaa0bb8c2bb36799ea155eaa4e75f6d5c4eba33cc5bbf390dcb6635c8757b2f	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1596486302000000	1597091102000000	1659558302000000	1691094302000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x14c87b813b8f0b1696154b42c3b7d80609ae3237f714bd371b0ca1fddbb438498eb56c0afaaa9b9d182bb5c48bc52f4278401067a4f3e72556537f845ecd2433	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1597090802000000	1597695602000000	1660162802000000	1691698802000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\.


--
-- Data for Name: auditor_exchange_signkeys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchange_signkeys (master_pub, ep_start, ep_expire, ep_end, exchange_pub, master_sig) FROM stdin;
\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1577746802000000	1580166002000000	1640818802000000	\\xf78eb5d2d9ebdf3853d582ffb8d0d13cdf834bf45742a2e077393cae5d5ba177	\\xf15e4bf6ad53aec9789d326fa3956ca549e75f7d8dbb05e77d14cdbfb1fb3d201a4a56bd81164042e5baefcd87bf94696f8ea46acc1baefacacae457dec5570b
\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1577746802000000	1580166002000000	1640818802000000	\\xf78eb5d2d9ebdf3853d582ffb8d0d13cdf834bf45742a2e077393cae5d5ba177	\\xf15e4bf6ad53aec9789d326fa3956ca549e75f7d8dbb05e77d14cdbfb1fb3d201a4a56bd81164042e5baefcd87bf94696f8ea46acc1baefacacae457dec5570b
\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1577746802000000	1580166002000000	1640818802000000	\\xf78eb5d2d9ebdf3853d582ffb8d0d13cdf834bf45742a2e077393cae5d5ba177	\\xf15e4bf6ad53aec9789d326fa3956ca549e75f7d8dbb05e77d14cdbfb1fb3d201a4a56bd81164042e5baefcd87bf94696f8ea46acc1baefacacae457dec5570b
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	http://localhost:8081/
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
1	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Bank				f	t	2019-12-31 00:00:15.354722+01
2	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Exchange				f	t	2019-12-31 00:00:15.42867+01
3	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Tor				f	t	2019-12-31 00:00:15.493559+01
4	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	GNUnet				f	t	2019-12-31 00:00:15.560367+01
5	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Taler				f	t	2019-12-31 00:00:15.627098+01
6	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	FSF				f	t	2019-12-31 00:00:15.690975+01
7	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Tutorial				f	t	2019-12-31 00:00:15.75532+01
8	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Survey				f	t	2019-12-31 00:00:15.822146+01
9	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	42				f	t	2019-12-31 00:00:16.241412+01
10	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	43				f	t	2019-12-31 00:00:16.665083+01
11	pbkdf2_sha256$180000$fwSTw9A2VkIB$X3+MBDQ1dLHnSa5DwRlom+KBNokMqNOrqGP744tFUnk=	\N	f	testuser-r4sQVX1K				f	t	2019-12-31 00:00:18.305146+01
12	pbkdf2_sha256$180000$YL44eIVhqznr$olet8lDfto8Y/g+qhklYt/WLckjGAq/ixWUls9sHh2M=	\N	f	testuser-ChSYta0L				f	t	2019-12-31 00:00:20.858743+01
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
-- Data for Name: denomination_revocations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.denomination_revocations (denom_revocations_serial_id, denom_pub_hash, master_sig) FROM stdin;
\.


--
-- Data for Name: denominations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.denominations (denom_pub_hash, denom_pub, master_pub, master_sig, valid_from, expire_withdraw, expire_deposit, expire_legal, coin_val, coin_frac, fee_withdraw_val, fee_withdraw_frac, fee_deposit_val, fee_deposit_frac, fee_refresh_val, fee_refresh_frac, fee_refund_val, fee_refund_frac) FROM stdin;
\\xa18cfe15d50587433c7cd1730fe4fe7ec064b2b7e34538e710b6d4c58f54ec15558773fd2fd769d276a4c73bc79824f3edd262626a7adeb89a153e3edc13ae90	\\x00800003ec7682ea745711820fe9367c6a12573199b6e29a18d8e8f2e5d23680602ababe829df6021bf469505dacf9c9ecbc6acead5e3156b8466ed555728ee457cb215ef5fbb0c774c7c549fa3523e8bb011def2bae708924d3c11a93b53bb79b2332e0ca94d0c6f120c97a244aac1a0f159e329752f7135453aa3ed3a8f30c2640f6e7010001	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	\\x8a50b0fd536e461f210d9c36d44f7493c71d2d99d8b80fa9e568875f398f4df657741ba9ee5ab8c9e0eb3f680eaad8e5f419db305d354562835c9c766edfa602	1579560302000000	1580165102000000	1642632302000000	1674168302000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x567a7d305f42fd5f6f54d2195ce8910addb6e114d13dc16c0e506228c8d15b44f1ad72fa1ab2a4b6dd18387099f95502c4272021e44c961e91ae6403e5e47ad4	\\x00800003ce33a677984a63f1dea0e7e0c08d1231ffc5889e87a767950d176527e3f51634d4009d4e705ec184bd78acb33a1b16b10a0227f06fe9e6e9b8da6537aee9e9ede1822310125a8f9fc55a3906167a9147011f67dc323d7e6af27102e4b5e2ff49fbe3a57a298a17f9056c9feab0fed0411aefde21cbe561fbb2e1d277da08ed2b010001	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	\\x7bea9b5a7215932ad5df98c845891e0222c1c1181185f979f17643296556070c9cd14a3675d38b7c93b4996ee8b905d180f43b33cc79ff6cddaea7c5a6641e08	1578955802000000	1579560602000000	1642027802000000	1673563802000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x85aa84a9b51ccc3b2180f78fc3fcd534537b151badf148a45af607a162183afce4fa3c8b9f181a2205973088a773be51ca595a9ea8108cb3f8846550de4dc3f6	\\x00800003d078eafe6afc519a73b835ebd05e9fcb016026cf0fc7257b758810257c0b7f4730bfb0932f173d3aaea964d2ac7405f2ab52936753d64a0188009491d7a8975d41cbb616d17ba7bbffc0fbb633f1533e9a70424a94f7e4accb23e77e38b5d2c8b32c0369acc8caa1aa3e1964c110386f715e31355b0380299f351e3b6484b303010001	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	\\x78146752f8693ffcfa3b18f3b30cd5719c4b9f98b7974f0b0608d0717804af7c5dcb7f71eb323a8adaaa567253a131cc0c0f97e51173c7723d1cea88d3c3c702	1580164802000000	1580769602000000	1643236802000000	1674772802000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8513f86b4707b9cbbe1b70ccdbf448691c585d15b982dded6ffd57738790cd95ce5eadb4738fb2b4efb8dfe3c6ae1624606cede28a2db79204b7a55f7534ee2c	\\x00800003b43fe78f7ee5633218bcf2cbf605405f1e3baad2b305a45ee86592ec7f489708d6a0a460ba4c2c74620c91e73581f5c6953c4141c8be29d2c4d726843335eb3db5a5d6ebb9a056c70140a167256661cfcb8ad9f7b5d2d81780662981b91b38db55c1ed852e9e4935d1714e831fa2a97e11b2e4a3e8ab6789a3b999e3abb75773010001	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	\\xff55beec6d1b02e48882510cf3c2e4b1ff013cb840fd016675b2c8244b13d650f5b6f4bde9c36339c7942fa6fa17bd08852cf2ab5da914692ced25c01543bd07	1578351302000000	1578956102000000	1641423302000000	1672959302000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x335c50be155aa7740ef7d610f1a805049a15090438451bc8a2c0883753bebc53f291749044c51fa1d95c691e2761b2e580959a8a7fbca31eb80ee5b8feb3e448	\\x00800003ad8c6972ddc71a46918069fda6b333cd5e4cb351cc960ef425e3bf21b14b41344061051b9dbd99de8e5873d5777400c38e3f750fc54f8ec41cac354b5e1a841c4dda3dba0769aa29922edbb9ede35ecc1442b3f2a2ce7a7b15466abc025f6c703ffec021ff43f3dc14ccdb10504eba8a5be323607bf223b24a09c44a81d25239010001	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	\\x80d95f57dbeaf1b21e5c6b09deeed4788bf1ef3c1c86051f1613c817bfd156b20970bce9a5430fb266fb9f71c46de9b4354f8604fc03a69ba9710294af8da300	1577746802000000	1578351602000000	1640818802000000	1672354802000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5c9f76a954637830ae7c89f87b30e62c896b56098c5f0dee2f5baecf9f33a0fef8579873d1339f23acd1b9a20ab9a719a84e1d2207aa372702d4d2d8854be3d0	\\x00800003c884d9023bee193646165c1292d76a07119d550b0edf25bc67ec323f102c24467280c6a2ba91eca5ba45a120c92829ae7d1faedd137eff83d01fab59017b9ad3c445b3f9a2a35744258b627acd39388524aa39e55f1964cee0851c242dea1db5666367737fffcab49e241fb5446934cf301cff8c1036d3adb25ce144d1d32063010001	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	\\x7bf5ef7bd5c646da232b52f9b0fbdce05df734e7d4f41d9bfdbe58297e5d7471cd3f0687e8ff865ea0221b790078022c4ebae1f0242d4efeb44f6a6185497d04	1579560302000000	1580165102000000	1642632302000000	1674168302000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9d1413f6bd3229b93434f02ebf1911330f84309b1d38bb95c0851adf8c33f99237e811578d794bcc57bcaca79c331878595f6c55c2d754bfb15293243e71cfaa	\\x00800003b428adf04e3539dc466fc560b7b969e8d198f0ba5781131fd3d399d3d7ab25b8da2cf8f5c62af54cb1b87f9c6e7948d4dc3d5ade90e0d0bb574fc1d92967c367fbf2babf4f7386321d6961ad37f00db044cbebc80c3376b5f842b0fe7f22c07c98e0db699896b3b59094a596ed80caa2cf7055a0ce566c964ad9d5f880c2473b010001	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	\\x79ede627b2b0a07df722df2d23e43ba58231e06dae0e2a2cb07b9fd2ab871de578973a79d96e14a35727dd4885ea30620de20c6c52166afd3cdd07e72416890e	1578955802000000	1579560602000000	1642027802000000	1673563802000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8f1bd6721a3292001eb93649ad366b18ca5913ec76265e1e4e7b361513fe34e67a67ba358a5ae5986e7ecd292b5012d9a2406470851f549d6b6bc8ffca975c47	\\x00800003de07495e664c4de1fbdc87b3ee6aa9b828ba0fc5de81c0d5860916017d23bf6ce77eb9c0ac76b6db111867d13fca2511f94ccb39701faa67a11bec25eccd640b776ec55304db0f74c1ebafdb3cf647551e0440a9a08215271c9b3fe0032a88a07894d454a68332245f390ee4b29393a5dbe928cd17b0945e04d20fbbfb9b97a5010001	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	\\xb44a39a848b162f9d07bfe2b6fc9d0783d9703890d6bf0e604a0480b112cca36c069a335c4f1433f363b746d80d2af951c5807c2d4e1f08ea7a76205bf5c1d08	1580164802000000	1580769602000000	1643236802000000	1674772802000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8bf86108b2581d5f1c5c572fc9b4610a45e1feffc78b4439c2a9135890633ee344f2b658147052c37f27d5e625e0dd783c167e3788fbe6164cf41a64eef7c439	\\x00800003c043f3c2cc5d22046a3e02f757969dab663c4d8c7b0c6195b27ffe9f111690e44ed603305e9a9144903604932195b26832a8c23371199e951a4676d3063d5ffa3cbd0cb2e3f85b9502f361aea23ab7919ab9f56f9ded596aa404b4835818b9026ded5067191485817591abdfda566935c5df9943cfdcc78a66881518b098c563010001	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	\\x8eaf0ac548982ad5b38a05ec01d9e2e13427ee05e940fe59dcdfda1d30ee9f3ea661371741f3130f3bc147595ad55aa110d8852f416f35ff3872388219ac7108	1578351302000000	1578956102000000	1641423302000000	1672959302000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3b88f4740d356fd237675ab8f0c5df85d679b3c518aab8466bb9673e260c2a8a44295e90802514d3504a8d864075ac23c4cfe7b2b10c8e0351072d5fa83b2738	\\x00800003d88d5e21fc14ccb76ee1b8d947f95aa989cd73394518b056170fcb4b135ce9c20eefd269a73914e1d0dfe94c16dfa4c755005b8b1af6e321202bb609daec6f8d52e6a7708d2b17ba28002e0f8578747b3354fa71a3fdb29a95d117f9f9bc7a82c31a65551dbc6607f7fd22f6412f61ac399d0af762429f5b0bf6ac10b4668421010001	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	\\x624ffa9322955280fc84be64688275516e15aec70a0d1b1b52b4f74c567e5e25c4be8fc3fba126faad5343b796a5a4975251140b11a1d0bb470ea2b98c13c701	1577746802000000	1578351602000000	1640818802000000	1672354802000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x06ae5b663a86b07647cf40729ffa6d58516cf54018345bcaaa34963f47570835729e14db34dd3dd8e92b10555938b9d674040d6aadb998173604c95d2ab85d82	\\x00800003c2e81b12eee56c5c9c2736e92c08b610be91ac93328c88e3398b83cae11ea2df9802b9dfb3863cc0c26edc9fdda909d3803cf8334a01b8965deb20abf1b9ca39e67c1c7186bee323566f1ab90a26ae8cec14cfd06683c82aaa8bb3df4bd3c4f139153e6d5ea1b767d3ea29a939193fc3f28262a79210e020e959d7567b00dd0d010001	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	\\x9b1b3eab76b553ce7df7546639adc030d078effc38cd891830d34676cf64630c8e94e2e6dd050ce5e3b97ce93484c3c294a86f9ba4fc9706716e0119a24a0c0b	1579560302000000	1580165102000000	1642632302000000	1674168302000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9a8b0cdda0b2173ea32e17bc1e5571545f4cd181805c0e794c6cee263aa7d022916b3d1f296caf407fee578943f4cd3fabfb2f6b3181387f202e18b91920610d	\\x00800003a4c36441f204b813ae7860251c92dfdd47d8d0b7b5f9d685b6f88178312b965286cca6ba18c3113c2e7fffb7d4ece52ef57998e5881b2fb48e8ab2563b47879bc2a9dbc94dba172a9df9590417bdab12b8c9ad0e0e1888148659b3fb818102c4f4cded6da652e06dca0e37b70d3b335500715cfc8fb624364278742bb8f5f44b010001	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	\\xa1a95330e96d46e6700099c91f2a7623ce5a483d8ab6177603213af15ac856cd35cfb6a23c2d44ead8acd5c559eccdd3cbe3fc52dd7b8b5aa2c1966e0615fa0a	1578955802000000	1579560602000000	1642027802000000	1673563802000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9b0a9897691c0981a80cf6aec3d1b0312922514ebfe466c38aa063fbdd8f46c21fb1a19e3dd30783716b0fac8afa94ed183914a31047d7b992e106f21ad3ede1	\\x00800003ad101a86c5cbc55b8c3723578fcaa950ef56b532c20c0ba009a970b186109baf506043f4120cad04a85d5d868bdbaf9ddab6f82342d84f39667be5f1716ba4617453207e2c22c5ddc4de8d15d452187000953bd64af8549c251197cd5d9dee2de1f576f72af4ec0b379969e22465dda8dc7a97533f7a1d1c35d00540d8ba64c9010001	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	\\xd8165c4022935b4b0ff37b6a49c96639a471c3ed0a47c60412e91425f6690d5e0397ab29e74c52d239e4dde537dfe1f8ed494a2d4cc7cb259dc2477ad0456c0d	1580164802000000	1580769602000000	1643236802000000	1674772802000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xabd80f988ed0c8bf1eb2e612972aea60f91fcb98875c98a6b9b1bfad14c7c026feef167db5a8c6284dbdb26319de0df9ccc7afdf8db6198e6d473ae5b644d405	\\x00800003b048c27144c0642a4f116b1b09ac4dd8fd27fc23b34fd836f39a3ba0960ec6b26251eb0e9c52854b5af1e66d45b5158fbc0392212543b96f78a3e936a23cefe3c9dfb0bb55209616311c79e38611083519d9d6f45a4ae67fd8f041f1a096ba910b52ade7b5d51d4bcabffa7b60c664d7ce8255a9e527ebe9632d0892d37ba9ed010001	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	\\x88d9d633cdf43c70c003f0055760f25987b1caeeb66bb29c7626a4394de48cbbf07e5d7f5519a588c1fc9237e919ee2859635d9360ec7f75cf8e31b9cac5160f	1578351302000000	1578956102000000	1641423302000000	1672959302000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7a64d9869f5495eef73d5af56b8dea3b1117257de7ac63509ecd2fb32c27f511505ebc8ea49b81b91535feeb0af9ff1cf65588cc7d1be71260809aab29a7cec5	\\x00800003cb8d8fdeb80783b883048d903b899796870162cf0a12b6a83d63eba60d4242a93a0deb080db1cdc1eed89b3ff69dd31318535d0531ecd24e773bb627011831b72e924c857c0630ee1e30ff08c8e35e16a3198ff12a9bd497d5fb1ce37ef0eec0385184839cfcdc31c41038c7ba8d01ceaa4f0fe018cf705265264929b12bb90f010001	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	\\x125d17ce756c86bbc86bdf568359c515ea797d7c9398233e670de2207dc17a7e783fa09bd877b36ae13306ee2d3115afac96e00306664c088869bc1070fb0d0b	1577746802000000	1578351602000000	1640818802000000	1672354802000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x0bb69779ab41827160c0090c68d5837ccba83181a6dc56841d12b2f87fde5cfec632d5db47fbed7086fe92a4ae7008dde1a790c5db1fa599efcad7f3bda5e35c	\\x00800003caffe9a66edbbb180cceb45d6125614434714cc128066daa98ee76b86d261b55fb2879cacea6e9b046d9dc348719c65b68e5111fa90cc99b532375fee993843ed0380d1fdd30a2b07ddfe0e76f80886cc91d6543e0b5e6f01b20220e27bbc6c3fb5555d4126d487cd4087c2ea157c2905aa34b67037375706aa9e7840d206223010001	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	\\x77fe680a627399bfc0fa744ac45d9aaba14861047a436b6feb7e470707b116a3a02b8d88c68c534f6acfcf60e0570882c80413c35693a9f531772ce8eddd4f08	1579560302000000	1580165102000000	1642632302000000	1674168302000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xdd2b9c8674cfaa93c226c09e868c670b7cd3f25f9880870043492c54e753d83f2bddf81326be296a00b8d46dc650b134dd44581c6189ee57de89a3636a11d780	\\x00800003bb0259f5b30f84dd30138219405e2a06d458a8b02511483aa1dd7c214814c7630e207e5b25e3e0374f46f564961208ab42a53a5aff2dd94033b5703dd84b5ef256dcd61fe94c54c729c3b53aeb92a9c0049b54d573f38c3e2ef8921b158a6d108a58b273afe2280f89b993e2c23a5a4ca9c4cd4368ba00db6dc55a15856159c5010001	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	\\xa99ee8c033732401a7476c598b88646854b650a388ac9448081699b0be28220403aa02c0234112a5f4c3a9d8ebb7076a7d6567fee1145dde79555eaa44310a01	1578955802000000	1579560602000000	1642027802000000	1673563802000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xadd4401875c14d767e4e42d229c0720c38cf43ead2dad6197c5f5a93fc4108d35af25246a0bad5761cc088a7a82530beb2eb1a71e2703cf4d00f4fb67b0d939e	\\x00800003d787b4c634e6a94228bb18ff44074c29c30b85caaf782293b1bc98e366ee4cba17a1355c289c0e2b6e59782dc4fe749b7917066367b5322864440b3767ed934709782d542f3069648bced780111adfa110db2df0563fbcaf924dd6a459de07d2fcff36c92e43646007217abd2028ee4fd4a4cde77fcd8471ec09f28c098bc8db010001	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	\\xd4879842d647421595f5482b20c6cc652f1994159a624a9cedbd127cb8df37fc0cbc1451273a5730153366556cc1763dbc8295220a82be7432f47e55ba5df504	1580164802000000	1580769602000000	1643236802000000	1674772802000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x379c85a7eecd4369dd8fde804de2fba7b2fa8b796907c93afcb01ec584a6708efe5f53a1fe69dcad99cc175e50e4ea81d922da5719e6aad7785517e17cb5ccdd	\\x00800003d330b9d82864eeb56f2f8728ac8f46afcf91aa7f7e227b7e97b72bcca6bae99397d9dad1f5a94f8ecd751cdca6315cf3c77678d89c26803d8a98c19a2aa7cd9b46f070215f14648f96210419925012fa49e6aab7d61bbf3863c38e4de15d9a4a845e8adafff19488d7f6b09987a36f570b1d3d774a77d5cb61458f3ec8bfb5b1010001	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	\\xc7d341e6fb0321e9a378830d29f6d9de707da1527aa6588d02a843e1e29b637dbeec8c476399431b6d2b3ea768ea5d42c3210ddcf2c1b606b665ee92aefdb20d	1578351302000000	1578956102000000	1641423302000000	1672959302000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2d4cb1ced2505a75757e7ef20eb940b3f5fca66ba51e90b76afeb5d260bf17b285a4344fa3fc4bdf174fef0c7504723a23017a7eb73e0b8b16fcc084b98c31a8	\\x00800003c54d07d5640869236438ed9a0f7aa60bbd6624d2ae347b2bd608036292784f0d2258eff40a2ec1807915307390e887d7c0c9938d7dcbcf7b8c187497f81cbd9e84972abd47a32df33e88af41289b04863055624d2ed722ab742a1e66da1bd81637a3af57af22983e92bf616e88c7d7e0958db2abd6b3748bd97667a4b1db0059010001	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	\\x3c085fc45bae078f9164224bd76c2cf2ff324b73aa92fd45ccaac1babcac8e87aefebc644fef05c6d163581ea3b3ae83e5a4651aee260ce1d1d59486070b8708	1577746802000000	1578351602000000	1640818802000000	1672354802000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x702027c066989929936456a3aca3a8889794b832a77b9b9fdce242aa499ba9b8166f83c443f896f40724dd7ffa27d1bb31c0a585ee4efec0040b9b272148db6e	\\x008000039a7e374496e6685d82709c9ed0849621c7d5f467eabbb0703ff3a65502f829699ad442b9be4935dff67aa6e118d93d5817304daa01552e44fd6eb97d2b3ae7e17cc561dc9637597ff1475f10268a770811be049c0b2e5155c4c340300b2d29b994bf528449333320268a07a237f153a7428f70b65e68253202ce89c447b3a1a9010001	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	\\xf7559d853e5aa1f2c6eaf3b83714a4cb443ea4d957e63ea9db34c3c29e927f376df33589b82c79f23af40ec5648a492144820209f7941aa181719e363c77a30f	1579560302000000	1580165102000000	1642632302000000	1674168302000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x3b45a7ddc5396b844ff51d44e60669b67b4c81feeb5ba48d75e66fba9e17a7c5c79cb6a95820774c852f110dc545836eb0bd2fef5b05edb64bab17bf208a07b0	\\x00800003b8e42541584fcbc3d2c1ee6b33d6f660e402ed56ba4d610b3452c2fe3ca218bd2e13a67c3ba3a1fbfdeafd5e43cf09f8817be8053bf56f79131d02a6f469517f3ab092f9521e0efb96b1f2e526b04056d4f7201a5d81c02cfc4e91047c11519e6a099d7fb43865099c3dbe17736b18d003f60454ea60dbe6c7817a68370af053010001	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	\\xad59184b6e87d722cdfd4ca835aac3196066b4039e42516cf632a20d1318df59637eb7a0135a44933a7e89b25f10053229897ef5f280374aab27a566bb2b9c06	1578955802000000	1579560602000000	1642027802000000	1673563802000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x9907a13c32bd9cc8032d4d10018c88d71ac8051cccc4ac48f9ee154efe2ebb169bdf4b69dc8cb67dbae9787fc1dcb1f3af4b5349ef32b6be2b1492c4be3e3245	\\x00800003d32b4f522b65b5284d145a5e9af64e2954b5b9fbb4084cae17f7f9fc5c2f7a0fe4798375184d76094a5ce596f2b4857396d25db75290f3daf3e79bf3eb50b4ede5a86189d5f1da1e76371bd698e5270df6ec11a580b75f4abfbd3782d2e1102b9e06bade69ec9d14638bf57dc17936c40529436ab3ba58fa75534e2228d958e5010001	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	\\x743b1052bb279df9bcccb2b9c2dddabbb300b7f90a39ff4d4f494e6e423aab84e895892d2222b5fc21ae6abcb2d0bf5c17ece000a81251fb80730411bf525d05	1580164802000000	1580769602000000	1643236802000000	1674772802000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x431b60e89580670f5d9ac7413b63868634a816e5be13634760b7e2a1529c1d9957c9c32171426e1cc861e3cf07e9dc0ec06a571a7cc0b2b95bc594f6cbbd49a9	\\x00800003c0a4c7ca5d37ecce686ee4264d3a022ae92ec029b3f1779e58b4a543ea5bb0b8f216721144f0f8b1b18d3b8297bf5b193a05b7914b6be9128c7eb6d0c3f718d23ac75c6c16186c4874b09e9df13365ded18d4df827d8923360933e2c0b5493a047727b19fb4c9e953ec4924796548273c4936943130d7b22c02ef4fcd0b02d11010001	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	\\x3f90a4e6a60160cece49b9f6129f44c246836ed9a1af1a889104b951ed82a073bac3ed09d4b63c0d034990f2f6d99559da700b12fdcd20f7088af803b1f7b50f	1578351302000000	1578956102000000	1641423302000000	1672959302000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xf9dfec817b3e35ab7d322115daee9bbee46cb9e5e479590783b7f01428cb0cd7b4aebcbecf76b01fe2e5e625255881e33aab8ae03c683e243f15bbf0fa6e8863	\\x00800003f157cfda15ae4a019f4035910bee53fd7f4106dba9589d1b9db81ec975c485dff3f928181d1697213f3ad7013971417834b640fed521171d4a4bd9c878fb6c0607b3c24e597177609ff9f83d02a187b9d32725929265698421a17b3b2ccedd5e504af3345da73f0d6194c696dff468aefc39d31428c8433617b281d55ff3ae7d010001	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	\\xa20eacdbebbe7e3a0d58bed319ae1337dc9ec774b4561f84af07f224c803c7287d1683618973db17c3873b8b488b521717baa781f118ec90cece2c4749929806	1577746802000000	1578351602000000	1640818802000000	1672354802000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x7e87032b53ab052f0d26d925586b9e657a5bac6e42e31f48d2437cd905268796fe1509e3e010c45babcc920f095805c792073f5b93d01a7b743a1a29bf60b82c	\\x00800003caefced721df51286711a80e2111ff7b52994345255d3312476b156155f0b557bb80ae40388ac1604f95d3cb567436677339d452848c4a7cda84ac21fbb11325182824c204b7b817cda2b9130bdfcb1bf46ea09eee2fe443ce7da001e8277e04152d782189e169550234b4e1a7f6bbd61d34341c3b44e744e64b97637d33edf5010001	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	\\x4fa07f1f2a667af00bee358b5a63f2b04706caa3afd081b43ba938057ec4ea849c74b634a067c448f37f7224f1fbf1eea013e4fa6fdbe71f6b78f33387aaf40f	1579560302000000	1580165102000000	1642632302000000	1674168302000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xc23e5c5759c9c95767c271fd3d403f470d806b86815cf0ae3491c9b4fd50860ddb3c215d0abfbdd175e30905bf93a9e4de6d0363ec3aad3bbdcb0557152b5a06	\\x0080000398e473354a9e591383cab792e2e3bc5116b9c95be8c11e2cc4a44cdf543e7113e2cdecedb1fc3ffb949ee0ee285838a4de0a294921f5e398a462bbbabe71a1bd788d447facab562cc6a1658602fdfe6b59440718a40bcbd423a5b15237e9ebf03aff5c448f9590435fdca025a39001d91c7b54dda92f97dceb38eeb991ea82c7010001	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	\\x295985b8fb5fd51d01717707e1586cf7a37cafb25e4fd5417ef58fa3ceab70d2ab6cdb4824379c1792ba56b6a88b3c7e79d3ddbd61ef725583eb4bf630e4300a	1578955802000000	1579560602000000	1642027802000000	1673563802000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xc35dd33025e46b22996119f88a836429f11fb7c936ea7cb9526cfc8d2a6bc3d122395f76ce90ea18c96b78cf7d377eb2d2c7e715db97047731b373914be99632	\\x00800003cf6130a9f2b77f9a4af14804ab61498dce44c26e9f46d75a4729cc9a289addd86e2c48cd219e4662f0cc2aa4b084ad158233d2f26badca1c7f665c8ce6ec8b3fc5f86bf8bb5a56af4d9fff166c13660a750ee14b6f012a7d6dcd16e4eef09521632d2b3fc7c1a75ae111f6b44dc07c2c9877d1ae1d010731602b2f4efa38a8d3010001	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	\\x0524783980e1efedb6d79a573fb36e3bffde032615b2da98cc17a15583f43f9117d320ac22fcdfdc0d36a4885f13f2f8c11fed1293413e01cb2748fb9d78e70e	1580164802000000	1580769602000000	1643236802000000	1674772802000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x1b88a637c160c2a05ec45f4ee46f403d67081ff332641a1c7d1db295c7da104144ec9941964b2336820fdb74b4890b5ae4e56e62090c3150c6861a1a7662cff7	\\x00800003a51de8288c257b263ee9565ea4823b150d1610a154608eeb1c8e8f0d13a6f50f439e0ff1b8db4274e86e416d00bbc930e3e5441649aa64dc0435c29d07dedcd612b370c11d2c28002db84e66ba5561c30f52459e0b53b9feec5506ca2a1de0be581c6b64890f8c3fb8778144999041c4f110cf6fba8dd88a3f637c4a550db66b010001	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	\\x2a2003af895a01881eeaf7a23d48735c3bb23d8ba02764c1560f48e0d7511a64c2119804c0495ce3286ea6f8793754ee3a1ba7b32ff16585944cf42571eb4e0a	1578351302000000	1578956102000000	1641423302000000	1672959302000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x5cac576b6aa21e7df191af5ee270caf70a0ab3a64cf16006984a44dffa43d6021188fd63c00df4265316d9ff6f415f9e06f83f50996962da962309b78d445a42	\\x00800003cfd20c4c7d3076568fa5bbd45bab4e35e0b88a5c4126785b74a31d07eb45db0e7c283422c630fe17e27680d20224818a6b200cc7bcd2873f8a6364b67512c4b584a36f7d82d5c71983f7f670655598573f5f69181c5b2ad7c53d65a6e43ad857795b1bc5fcf926ced04354344b5c69ff69bf0c45c3479ef5db9612cb6eb5da0d010001	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	\\xe7e9200d431271494d2d2d6322877b568888d37b7ddc99c81db74a2b34f9d9cc99ac074457bfb5b7151226c63a514c6a4c017aaed1a78bfdcda043fd95b75f08	1577746802000000	1578351602000000	1640818802000000	1672354802000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x82bd0a9d09a5dfcb68abdc127041092b0d164b9bfd7d0bdf2a42326369b7c4a4c8d6296e70c1dd8c15fd6c9ffc0abd35a3b982c78d0e79edd89691ebe010066c	\\x00800003a8279e711c63db3340f543abf7c689a229e06591a0246ed8683e6b8c8f39f9c10556af4c4419a1d7d683c464218237c0fd5b6152f876111d32e1cbcc796a474353026dabb145cfb54d4bb5a392c97fcc554da07e8bb16d5a3b23c2dc2b471b5f4204e227d91bb8a8dbf6eb62a8e539d83c24ff6999727e4f4777668a0b18cb21010001	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	\\xce0f4db27d6709ffd900a39416f58ab1054faab71db23fe1cb8615031ad5b28ba3027bc1e3f1ffa67432cb2c5e85fb9d65562ba2f57d70cf3e9edd1c97de4707	1579560302000000	1580165102000000	1642632302000000	1674168302000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xe75a2a58a7c6b0cfd7781e600d1045d46b1971cb7f1d8781dacd4104b176d71e46d1b92eaa8a5c59c787d3949045fb85167b611d783194e9ee4a9443f9b75afd	\\x00800003d4f7c5ba499719222f44c48e6c7ac1d91c205e8a928f9dea205e15b6c52129ad4cc03a24ed5967aac8f3c10174e5915cf1338d4d807bb277b498baa457d6b786089734693b11f1ec2367f7bfd45f38fdd279d663263c8a6aea1b905b57cc995538b76f8e109fee50091923778f43fa44f6b062a9f063866fb46073e280a22727010001	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	\\xb372646951ac7c9b05183a64482e02382be23ab7a24bd6d3c9cabc87898560f37efe7fb77484911ba745e58911e72ee3b8d735eb4f45f102b3b866e754ef3b0f	1578955802000000	1579560602000000	1642027802000000	1673563802000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xe27376c0294bb98032f5d5320d167da2d0eb6bf41cde68c5995377d6ce84195df2da73e0d713d8355ce6e85908e5e1f573ec20adfd01dda028ca1bc05fbbdee9	\\x00800003efe56cf8d2522e1398487826a653c6b76afa0906fa82a4c3dda8ac3d7aa6e80f3c033e92e3fb3bc23e6263a72c0e9b85ef50e41105f62a35de7f1f751f84ca8eebf5157c93d31cb4991339b4a7282e21adefd9125e0040b1e90f67b782b7490f6c5f2361a51181ba5e68eea2d235bcdf364825cd478a619683a8847754f8edf5010001	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	\\x8d3acb5738dc39778db57c408cc57ad503fb1cb259f1b90e7c6812e8c3bc4a2f9e10d754babd282b0a118ec06c00fa9bda791d24818e91d02c427686f83e5607	1580164802000000	1580769602000000	1643236802000000	1674772802000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xe929357b2a6d1aa4d0f9b9342ca65aaaa5bb141831e07adc0659c3911f37ffa114b7574a2ebef04f5f4f5ed71a7dee1ea244f82518a099c36f3d952d671ceabc	\\x00800003b6a6b3edc3bbebe2105a9d5c948f8abed21908f6d5b7559d67002ecf25e0c9191467dab634e10105c1df9fc437aced6003237a18d6160473fe7b4c6c28c1e49f291305d6c53969df9679e0aac8416510a83303ce25cd8d0c64c8abe3885e7e1a9f09cf514fdbb24e456584f4895a8804ab5f9e8896add687408256b7542922ad010001	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	\\x0e64dd983954bb2e486747a23415898d4754b74310e8a7ce76e150a2a8f9c68766774d869d0fbf0468730bad644ad90850f89d6be1503d7e770cda83aa17b606	1578351302000000	1578956102000000	1641423302000000	1672959302000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x860a9106ae6eae432b56bd506c28c284de8de160911f8fe4f8d83c82a49d17cb19bb387e7d6e44ab6a96df96fd7eaa5f77180d52ef5b542d2ec7b50e7fcd7124	\\x00800003b3fea49f702c86c85508d66280bee6b68dfaf3d0d1f5eb0112f9529fc0f06ea66d42beaff3796146122d3a6dd040896c9bfc891bb807016a434d2706c0e098b657cb965190924e6aff3d687afe9b1f0422bad8c82e4624d6037649f7239cbe6af2c864b2f546f9241b7b4783a415ccc774d4dc7edbce5dff4e92f927b7958651010001	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	\\x54c343b9af13729f9f7f7c6998a4f0dd4979245a33779bb4144525c16df36a6ba780ccc28c31e2f29f1da1a549fa307c321236fe333aa416a81da29243e94307	1577746802000000	1578351602000000	1640818802000000	1672354802000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x99d260bd4a7b6826d13be030364bbe290d5fd888298242ba8ebfd959cf57eea29fc0595b32c06fa2478fa6936a9e774bbf1bb1f8152d959188e663eb0e41c958	\\x00800003ba5160cba0f6e05fe9e70d9a27ca1219ae3977db9e8619ca5b09ba1ba10a0f6d8a98f8035d4d93fd6396b40899e48c8a7d0659d7debd29ad13f4c79869c5376a95e874c57e6636dec8ba994cc6400bc99c72238568895b11c5d6f9f772b180a1b92c88970022ea0cfd6cc8a1d2b769886f0a89d8b497381997d14c77b6897825010001	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	\\x3c7487a691ec3568336358af421451aafb0162cc2f6504d271d49fe1fe4b8aabaf41b7acad33b6cde4380a08f1391724d623397fc08f063e698447251574f803	1579560302000000	1580165102000000	1642632302000000	1674168302000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xdcfced75e70c375e1e4a90412acb72a474576d7f016d73e8de72d2fd252aee318096bb2ebb2c66b7f91a541203b5a4e9f0152925f1b804faa1ce941b0bbb91c1	\\x00800003d1f0fde8e29f85abc5787cc45974c893eafdd31538e27f97427b0d9383f8fc6f378f3d2539d3baa585459d1e9559f8b4c48a5886cc595aaf48f97fd4b8c95c27590fcd7863be99b052388eb6ec2adb9eac5ec74ba04c61b502101763e42807cce4934470d293f9ca2520b4fc83dfea020f006d3c2664d66701df6aa8f93c9e4f010001	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	\\x09c6a5874b904c47be972c31f1d2718754df71152f145290e7b79bca1820e344854842eabf1db0b5064aa42c1d2191bf7c3bc5d2d550a85cacc2fe9a8be85209	1578955802000000	1579560602000000	1642027802000000	1673563802000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x5607944bed756f4ed32e0c8334b24ea64e5883a424b4fb8f52f663e6d914099ed9a19967db3145afed341c05423885d0d713509e76c885d6f10d37dec80c7e81	\\x00800003cd678362c8ebd1422b6234b64879ed384dfc52334c7bb5ba222701c9f2333ba0d332d3880d987aadf4c5c3d23e96ff5a05797e119b0cabdaf3519e1ef53a35f814f9b8398d40aca59b8e93ab8047468497d5d20b01d9a48e349cb437ff6671a0b984ba1279545ed0006c53a7fcce4504fb696ce496c2b0947a34a14825b68c7b010001	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	\\x675ebbf04ce97888a7341aac4867e12fccab1d6a84fb0e09488bc6b73edf029d64f87124ae2aa1f908848cf2de579ac5c5955564b3f0b8cf9c4be020eb5d3406	1580164802000000	1580769602000000	1643236802000000	1674772802000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x95cf7e6f18c0fe7634885a8eadeacb972775211e9ff547ba320d9f81e5e01e3517c3b28eb9bdcfbe2a48e1937c0a2e5c0bb6d88ffd87ffc81d764d66756fe620	\\x00800003c6089b196258f1ecfdb43d94502a255f75b75770c9c71ae0fa85996fdc91321f3643e646b400ed2912bc1c5e356a82d5902824d2f8804d0ca4e43152e5bed519e914d147b616693318bc133ef6a2dd601fcb052c400ad1b76e66856d56c93632dcbdf453c12323d2822f5f8caff4c1a2e60f53022cf95918602b8b0e93af589d010001	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	\\xe8ed81f6f16374008573c4835ca38ab37d1ad3163a37f3a9986057551ef75a1c5176c08534cb3936cc3743c2f6ca9a09c925f01d0765fb633f105912f5edc405	1578351302000000	1578956102000000	1641423302000000	1672959302000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x48ede06403d2291b9939254ae67eda84a35990a55b53dde5aa77b4e621b3b69a922b26d045cc080913b1754afb7081caaec25ae4c0bdf86c83304faee0ed2c68	\\x00800003b0186e785ce5a30e9d176f9bbcd90ccf74f2da287a0611747e7adfa71afc0ec300234b67da46d97eb9752b32a4a8dd8a4c5e0aae6817414a298b046255e94fe37298174ceee2408dbf94a92287b8074c85167c110bce88f3b6072f75ae03e916f44c7cdb6a847fbc0c81bdf61e1c74a3459c0fa27bb9114c5fc9f0adecdbc503010001	\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	\\x1262810fa681bca9edf1a41ebc80f95528b04807c1060692ffb04020c7d87ec4205c8dd3e575c5f54c0113a1a0fe00032cae1dd1fabaaa4386f5fab472b1410f	1577746802000000	1578351602000000	1640818802000000	1672354802000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_wire, "timestamp", refund_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	1	\\xd2141928c043af5a15c927b6786162894ccad9175a610bf94df954f45375fa9b616cfc86b52f1ee9c26691012a84e97b734d6df25b98a46e2142fa2ba9a78b9c	\\x04d75ffe223df7a55e25651e72b5ce9e2aff5611c1ad5f851fcb41291030db29bf89c74a268619836befb2a08ffad93d52e395dd0fc9be1c621622143b04ad63	1577746819000000	1577747719000000	3	98000000	\\x760cbd7a81dd426506ab07ebaf53f2e1b62dc60ed1b7b52c98f7bbc08cc0b16f	\\x896d7fa121a8117390e6185912bd64f5690f19bd152abcaee4d3a4ec900e5c86	\\x69e1ab46c7d94e570a02b8ff405ccb949ece8a55d2ee5253c46144968ea4e16d91e26a09cf610d182ba4a287ad69b58e0222de09070f1bf8579dfa0e315e5001	\\xf78eb5d2d9ebdf3853d582ffb8d0d13cdf834bf45742a2e077393cae5d5ba177	\\x16c58356ac7f000000000000000000002e36785601000000e0b57f36ac7f0000e91e556917560000c90d0014ac7f00004a0d0014ac7f0000300d0014ac7f0000
\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	2	\\x3b6b416a657d6e0d6e92df9ce66269ad470f3228650890cf54c09f991312df6960455006025ebda42d2148886fae65b82d6871912080946c3da838f974dc6df1	\\x04d75ffe223df7a55e25651e72b5ce9e2aff5611c1ad5f851fcb41291030db29bf89c74a268619836befb2a08ffad93d52e395dd0fc9be1c621622143b04ad63	1577746821000000	1577747721000000	6	99000000	\\xda33a7cd13f692fc76ad87e8e782e9df0b2e3b4e934948d16305f75baf804f4d	\\x896d7fa121a8117390e6185912bd64f5690f19bd152abcaee4d3a4ec900e5c86	\\x73fbb524188f2becf6f039f81ffff515700992f7c4f814d707de8719609abcbb3c52203cda93a8b318bc01b1ff2da0425cfb545847fdba1a780f71da9c96790d	\\xf78eb5d2d9ebdf3853d582ffb8d0d13cdf834bf45742a2e077393cae5d5ba177	\\x16c58356ac7f000000000000000000002e36785601000000e0d57f37ac7f0000e91e556917560000c90d001cac7f00004a0d001cac7f0000300d001cac7f0000
\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	3	\\x859fe240bb9c2cb558cd5bf1285d4d02a4e03f7fb34bf2eebecd084780b2eb2511c108cd695c2767119e40f6da9bd3d7c7a0cae5da8fa07f3a377433bf0c90eb	\\x04d75ffe223df7a55e25651e72b5ce9e2aff5611c1ad5f851fcb41291030db29bf89c74a268619836befb2a08ffad93d52e395dd0fc9be1c621622143b04ad63	1577746823000000	1577747723000000	2	99000000	\\xb1c8780ea9d56de2ed3a15518276490d49211cb8fa841a235bb649f0f0586b2b	\\x896d7fa121a8117390e6185912bd64f5690f19bd152abcaee4d3a4ec900e5c86	\\x8c986bf3be36b59faa507b7b5fa3fa063a43f5f74289e05f75a49d9577ed7008b199e27dac2b3a963c5eaf715ecc8fdd2fef87f7f2ea2af7d2ccedfa7900d00a	\\xf78eb5d2d9ebdf3853d582ffb8d0d13cdf834bf45742a2e077393cae5d5ba177	\\x16c58356ac7f000000000000000000002e36785601000000e0c5ff36ac7f0000e91e556917560000c90d0020ac7f00004a0d0020ac7f0000300d0020ac7f0000
\.


--
-- Data for Name: deposits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits (deposit_serial_id, coin_pub, amount_with_fee_val, amount_with_fee_frac, "timestamp", refund_deadline, wire_deadline, merchant_pub, h_contract_terms, h_wire, coin_sig, wire, tiny, done) FROM stdin;
1	\\x760cbd7a81dd426506ab07ebaf53f2e1b62dc60ed1b7b52c98f7bbc08cc0b16f	4	0	1577746819000000	1577747719000000	1577747719000000	\\x896d7fa121a8117390e6185912bd64f5690f19bd152abcaee4d3a4ec900e5c86	\\xd2141928c043af5a15c927b6786162894ccad9175a610bf94df954f45375fa9b616cfc86b52f1ee9c26691012a84e97b734d6df25b98a46e2142fa2ba9a78b9c	\\x04d75ffe223df7a55e25651e72b5ce9e2aff5611c1ad5f851fcb41291030db29bf89c74a268619836befb2a08ffad93d52e395dd0fc9be1c621622143b04ad63	\\xf7c671493cd6add31825e57ffe23bf53722072b38b36e9e8e9e0f47babbedfa74430b4091c3761c8d141715e3a2bc4b50a6bfe774fac00bc4247f15b00603d0c	{"payto_uri":"payto://x-taler-bank/localhost/42","salt":"1XG429NAXAZYCWK152KN3RCXPNJYY0ZJYZNVPSB4WG4W398MVKCHSHZ3CFZMT6YF6XDDSMK3BVEA1CW7ZDZEFK2NA83DP6X1NDA06S8"}	f	f
2	\\xda33a7cd13f692fc76ad87e8e782e9df0b2e3b4e934948d16305f75baf804f4d	7	0	1577746821000000	1577747721000000	1577747721000000	\\x896d7fa121a8117390e6185912bd64f5690f19bd152abcaee4d3a4ec900e5c86	\\x3b6b416a657d6e0d6e92df9ce66269ad470f3228650890cf54c09f991312df6960455006025ebda42d2148886fae65b82d6871912080946c3da838f974dc6df1	\\x04d75ffe223df7a55e25651e72b5ce9e2aff5611c1ad5f851fcb41291030db29bf89c74a268619836befb2a08ffad93d52e395dd0fc9be1c621622143b04ad63	\\x989620935c82a8dea1e113e1c9be700e46bea28c0dbcd825fa601a9a734f4307a839114f85e7c73963f6c0d9e65159f08298f67de10a6eefa1f62fd1aa0b5702	{"payto_uri":"payto://x-taler-bank/localhost/42","salt":"1XG429NAXAZYCWK152KN3RCXPNJYY0ZJYZNVPSB4WG4W398MVKCHSHZ3CFZMT6YF6XDDSMK3BVEA1CW7ZDZEFK2NA83DP6X1NDA06S8"}	f	f
3	\\xb1c8780ea9d56de2ed3a15518276490d49211cb8fa841a235bb649f0f0586b2b	3	0	1577746823000000	1577747723000000	1577747723000000	\\x896d7fa121a8117390e6185912bd64f5690f19bd152abcaee4d3a4ec900e5c86	\\x859fe240bb9c2cb558cd5bf1285d4d02a4e03f7fb34bf2eebecd084780b2eb2511c108cd695c2767119e40f6da9bd3d7c7a0cae5da8fa07f3a377433bf0c90eb	\\x04d75ffe223df7a55e25651e72b5ce9e2aff5611c1ad5f851fcb41291030db29bf89c74a268619836befb2a08ffad93d52e395dd0fc9be1c621622143b04ad63	\\xb6a5c074ca520c9feec5ab46fa29c85888f1b9f42300903cc7129f76a7689d6b67304b8b80455af1a9ec5e7cc7177c7b2561d85f2201f257e09c208116769c07	{"payto_uri":"payto://x-taler-bank/localhost/42","salt":"1XG429NAXAZYCWK152KN3RCXPNJYY0ZJYZNVPSB4WG4W398MVKCHSHZ3CFZMT6YF6XDDSMK3BVEA1CW7ZDZEFK2NA83DP6X1NDA06S8"}	f	f
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
1	contenttypes	0001_initial	2019-12-31 00:00:15.132896+01
2	auth	0001_initial	2019-12-31 00:00:15.156602+01
3	app	0001_initial	2019-12-31 00:00:15.201267+01
4	contenttypes	0002_remove_content_type_name	2019-12-31 00:00:15.222277+01
5	auth	0002_alter_permission_name_max_length	2019-12-31 00:00:15.225478+01
6	auth	0003_alter_user_email_max_length	2019-12-31 00:00:15.231612+01
7	auth	0004_alter_user_username_opts	2019-12-31 00:00:15.237044+01
8	auth	0005_alter_user_last_login_null	2019-12-31 00:00:15.242621+01
9	auth	0006_require_contenttypes_0002	2019-12-31 00:00:15.243901+01
10	auth	0007_alter_validators_add_error_messages	2019-12-31 00:00:15.249922+01
11	auth	0008_alter_user_username_max_length	2019-12-31 00:00:15.259354+01
12	auth	0009_alter_user_last_name_max_length	2019-12-31 00:00:15.269767+01
13	auth	0010_alter_group_name_max_length	2019-12-31 00:00:15.277618+01
14	auth	0011_update_proxy_permissions	2019-12-31 00:00:15.283998+01
15	sessions	0001_initial	2019-12-31 00:00:15.28835+01
\.


--
-- Data for Name: django_session; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.django_session (session_key, session_data, expire_date) FROM stdin;
\.


--
-- Data for Name: exchange_wire_fees; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.exchange_wire_fees (exchange_pub, h_wire_method, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, start_date, end_date, exchange_sig) FROM stdin;
\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1546297200000000	1577833200000000	\\x8842112fcae4375a16d8656b9c5c9193072a7d3f99d9363724e1f0f2c9f65b79c745301090075f59aa5f0d3f02016c956e29618ad7644ffa5558f2cbec43ba0f
\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1577833200000000	1609455600000000	\\xa41699ded695c21e215a3ec72361c52b9178c24a6b8d6975879551d5714b7450fccae177aaa0f707a6bc768b6b606268762d3d9088686e037f298c8705ee140e
\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1609455600000000	1640991600000000	\\xfa94f0d99581c89bda3abb6b63dd83cfef88f5151d279a9c87c86f90709d003612c15930432e574c9876c7d40ed00612c7f6eb17ea55b7d0db35675c9133dc01
\\xb220b5d78ce5422d75bae7ba9188e67d066c47a0682e127a8c4adfd95e22cacb	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1640991600000000	1672527600000000	\\x67c77330e0ffda7788dab16dcf2332f712bc3ee19f67a71795d3a0ad5bc975d673be76b6f999e02a24b40cbf0a65973182877cb4fc1a4fd546039d8a762b9903
\.


--
-- Data for Name: known_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.known_coins (coin_pub, denom_pub_hash, denom_sig) FROM stdin;
\\x760cbd7a81dd426506ab07ebaf53f2e1b62dc60ed1b7b52c98f7bbc08cc0b16f	\\x48ede06403d2291b9939254ae67eda84a35990a55b53dde5aa77b4e621b3b69a922b26d045cc080913b1754afb7081caaec25ae4c0bdf86c83304faee0ed2c68	\\x9457d9211c12a9c252b2d11df09e3012164f3e809ee265baa36ed07edfd8a905eb74efd905c32ec114a23f6a7d32d1e3f374d5157d4a46d7c65956210c55c6be903fd5509ce8593dfeabd3f93dc94a637fe266ea243e72dfb66bb36013fecaf874447177b9ffeb91f0d91a73afcb0f956bcd7190b86a457d9cdfc4ae9077f60d
\\xda33a7cd13f692fc76ad87e8e782e9df0b2e3b4e934948d16305f75baf804f4d	\\x3b88f4740d356fd237675ab8f0c5df85d679b3c518aab8466bb9673e260c2a8a44295e90802514d3504a8d864075ac23c4cfe7b2b10c8e0351072d5fa83b2738	\\x6f9edaae69a889e066ffcc3d1a7056edfec845b5f0ffd829a52b3255f3ee7a40a803838f3eac74f47076030a6f2bc1a98ae0d0cdd3fdb86e0b4062553c060b4630194ceed806d309698d2e4b8ea3354dd1e812498476898f6da679fce9dbc0b4a5a364d253b801a5311e263e2007f60c4490ee1c5c3b831539c5293bcfe46deb
\\xb1c8780ea9d56de2ed3a15518276490d49211cb8fa841a235bb649f0f0586b2b	\\x335c50be155aa7740ef7d610f1a805049a15090438451bc8a2c0883753bebc53f291749044c51fa1d95c691e2761b2e580959a8a7fbca31eb80ee5b8feb3e448	\\x4d4fa1ace2b730c222fce3de7ec8d14f10e0d9f7db7ba67040fc12ff1135ca2b46682b24890f763b0eb9cf99f056be9ab352cde72340486fb9e9434ce97e348d7cb3ee882802412565f03593a0081d4d8a425103649948e7df3d88dbfcd5bd2537a3c3a676fb11ae2f1aecd096cf695df1bc343143e92e31a43595ad7fc792e7
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_id, merchant_pub, contract_terms, h_contract_terms, "timestamp", row_id, paid) FROM stdin;
2019.365-02GAJD2ST5A9M	\\x896d7fa121a8117390e6185912bd64f5690f19bd152abcaee4d3a4ec900e5c86	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313537373734373731393030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313537373734373731393030307d2c226f726465725f6964223a22323031392e3336352d303247414a443253543541394d222c2274696d657374616d70223a7b22745f6d73223a313537373734363831393030307d2c227061795f646561646c696e65223a7b22745f6d73223a313537373833333231393030307d2c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2250384742424e5743574e3132545844545759583933323736464d3336524858304430513134594d43394246584a51483253423547227d5d2c2261756469746f7273223a5b5d2c22685f77697265223a22304b424e5a5a48323751565441514835434d4637354445454b524e46594e47485236504e5a31385a5344304a4a34314756434d565a32453739384b384336433344465156353834465a42434b544d51334a5145475a4a4459334848314338474d37433241545252222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a22483550515a3839314e303851373437363331434835464234594e4d4759364458324d4e425342513454454a4553343045424a3330222c226e6f6e6365223a22544e59524245325a5436414246304b5259514d45394446434536375a4856543936474d574a57545736533432544b485137365447227d	\\xd2141928c043af5a15c927b6786162894ccad9175a610bf94df954f45375fa9b616cfc86b52f1ee9c26691012a84e97b734d6df25b98a46e2142fa2ba9a78b9c	1577746819000000	1	t
2019.365-03P2Z0ZJYPBM2	\\x896d7fa121a8117390e6185912bd64f5690f19bd152abcaee4d3a4ec900e5c86	\\x7b22616d6f756e74223a22544553544b55444f533a37222c2273756d6d617279223a226f7264657220746861742077696c6c20626520726566756e646564222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313537373734373732313030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313537373734373732313030307d2c226f726465725f6964223a22323031392e3336352d303350325a305a4a5950424d32222c2274696d657374616d70223a7b22745f6d73223a313537373734363832313030307d2c227061795f646561646c696e65223a7b22745f6d73223a313537373833333232313030307d2c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2250384742424e5743574e3132545844545759583933323736464d3336524858304430513134594d43394246584a51483253423547227d5d2c2261756469746f7273223a5b5d2c22685f77697265223a22304b424e5a5a48323751565441514835434d4637354445454b524e46594e47485236504e5a31385a5344304a4a34314756434d565a32453739384b384336433344465156353834465a42434b544d51334a5145475a4a4459334848314338474d37433241545252222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a22483550515a3839314e303851373437363331434835464234594e4d4759364458324d4e425342513454454a4553343045424a3330222c226e6f6e6365223a2258354b4156475943465a36454d344a4a4b4652545a4848514a4734514e563432364a45344d5656543550565a4b485a3047473747227d	\\x3b6b416a657d6e0d6e92df9ce66269ad470f3228650890cf54c09f991312df6960455006025ebda42d2148886fae65b82d6871912080946c3da838f974dc6df1	1577746821000000	2	t
2019.365-03R1BYV0Z257T	\\x896d7fa121a8117390e6185912bd64f5690f19bd152abcaee4d3a4ec900e5c86	\\x7b22616d6f756e74223a22544553544b55444f533a33222c2273756d6d617279223a227061796d656e7420616674657220726566756e64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313537373734373732333030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313537373734373732333030307d2c226f726465725f6964223a22323031392e3336352d30335231425956305a32353754222c2274696d657374616d70223a7b22745f6d73223a313537373734363832333030307d2c227061795f646561646c696e65223a7b22745f6d73223a313537373833333232333030307d2c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2250384742424e5743574e3132545844545759583933323736464d3336524858304430513134594d43394246584a51483253423547227d5d2c2261756469746f7273223a5b5d2c22685f77697265223a22304b424e5a5a48323751565441514835434d4637354445454b524e46594e47485236504e5a31385a5344304a4a34314756434d565a32453739384b384336433344465156353834465a42434b544d51334a5145475a4a4459334848314338474d37433241545252222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a22483550515a3839314e303851373437363331434835464234594e4d4759364458324d4e425342513454454a4553343045424a3330222c226e6f6e6365223a223552573151463432564e30585337364d57374650503752505a3545334a384356315847383535355a4541363548534b4732435030227d	\\x859fe240bb9c2cb558cd5bf1285d4d02a4e03f7fb34bf2eebecd084780b2eb2511c108cd695c2767119e40f6da9bd3d7c7a0cae5da8fa07f3a377433bf0c90eb	1577746823000000	3	t
\.


--
-- Data for Name: merchant_deposits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_deposits (h_contract_terms, merchant_pub, coin_pub, exchange_url, amount_with_fee_val, amount_with_fee_frac, deposit_fee_val, deposit_fee_frac, refund_fee_val, refund_fee_frac, wire_fee_val, wire_fee_frac, signkey_pub, exchange_proof) FROM stdin;
\\xd2141928c043af5a15c927b6786162894ccad9175a610bf94df954f45375fa9b616cfc86b52f1ee9c26691012a84e97b734d6df25b98a46e2142fa2ba9a78b9c	\\x896d7fa121a8117390e6185912bd64f5690f19bd152abcaee4d3a4ec900e5c86	\\x760cbd7a81dd426506ab07ebaf53f2e1b62dc60ed1b7b52c98f7bbc08cc0b16f	http://localhost:8081/	4	0	0	2000000	0	4000000	0	1000000	\\xf78eb5d2d9ebdf3853d582ffb8d0d13cdf834bf45742a2e077393cae5d5ba177	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a224437475450485037563537354532473251335a4d305136424a4a464358324a4e54425135344d59344335323944334e345735505333524b41313737503233385235454a4135315844443654525730483256523447453352565a3142535659474536354635303038222c22707562223a2259593742424d50535846464b474d594e47425a56484d3648374b4652364a5a4d415831413552335137345941575141564d355647227d
\\x3b6b416a657d6e0d6e92df9ce66269ad470f3228650890cf54c09f991312df6960455006025ebda42d2148886fae65b82d6871912080946c3da838f974dc6df1	\\x896d7fa121a8117390e6185912bd64f5690f19bd152abcaee4d3a4ec900e5c86	\\xda33a7cd13f692fc76ad87e8e782e9df0b2e3b4e934948d16305f75baf804f4d	http://localhost:8081/	7	0	0	1000000	0	1000000	0	1000000	\\xf78eb5d2d9ebdf3853d582ffb8d0d13cdf834bf45742a2e077393cae5d5ba177	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22454658564139305248574e5953585147373757315a5a5a4e324e52304b345151524b5731394e5237565433484a523454514a584b524d4830374b44393741354b333259303343465a355047343451375641484334465a445433395730595745544b4a42374a3338222c22707562223a2259593742424d50535846464b474d594e47425a56484d3648374b4652364a5a4d415831413552335137345941575141564d355647227d
\\x859fe240bb9c2cb558cd5bf1285d4d02a4e03f7fb34bf2eebecd084780b2eb2511c108cd695c2767119e40f6da9bd3d7c7a0cae5da8fa07f3a377433bf0c90eb	\\x896d7fa121a8117390e6185912bd64f5690f19bd152abcaee4d3a4ec900e5c86	\\xb1c8780ea9d56de2ed3a15518276490d49211cb8fa841a235bb649f0f0586b2b	http://localhost:8081/	3	0	0	1000000	0	1000000	0	1000000	\\xf78eb5d2d9ebdf3853d582ffb8d0d13cdf834bf45742a2e077393cae5d5ba177	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22484a433651575859365454535a414a474644584e5a385a543052583437584651384134593051564e4d4a455341585a4445303442333646324650503250454d503748464159574159534a375854425a46475a565a35544841595a39435356465446343044303247222c22707562223a2259593742424d50535846464b474d594e47425a56484d3648374b4652364a5a4d415831413552335137345941575141564d355647227d
\.


--
-- Data for Name: merchant_orders; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_orders (order_id, merchant_pub, contract_terms, "timestamp") FROM stdin;
2019.365-02GAJD2ST5A9M	\\x896d7fa121a8117390e6185912bd64f5690f19bd152abcaee4d3a4ec900e5c86	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313537373734373731393030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313537373734373731393030307d2c226f726465725f6964223a22323031392e3336352d303247414a443253543541394d222c2274696d657374616d70223a7b22745f6d73223a313537373734363831393030307d2c227061795f646561646c696e65223a7b22745f6d73223a313537373833333231393030307d2c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2250384742424e5743574e3132545844545759583933323736464d3336524858304430513134594d43394246584a51483253423547227d5d2c2261756469746f7273223a5b5d2c22685f77697265223a22304b424e5a5a48323751565441514835434d4637354445454b524e46594e47485236504e5a31385a5344304a4a34314756434d565a32453739384b384336433344465156353834465a42434b544d51334a5145475a4a4459334848314338474d37433241545252222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a22483550515a3839314e303851373437363331434835464234594e4d4759364458324d4e425342513454454a4553343045424a3330227d	1577746819000000
2019.365-03P2Z0ZJYPBM2	\\x896d7fa121a8117390e6185912bd64f5690f19bd152abcaee4d3a4ec900e5c86	\\x7b22616d6f756e74223a22544553544b55444f533a37222c2273756d6d617279223a226f7264657220746861742077696c6c20626520726566756e646564222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313537373734373732313030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313537373734373732313030307d2c226f726465725f6964223a22323031392e3336352d303350325a305a4a5950424d32222c2274696d657374616d70223a7b22745f6d73223a313537373734363832313030307d2c227061795f646561646c696e65223a7b22745f6d73223a313537373833333232313030307d2c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2250384742424e5743574e3132545844545759583933323736464d3336524858304430513134594d43394246584a51483253423547227d5d2c2261756469746f7273223a5b5d2c22685f77697265223a22304b424e5a5a48323751565441514835434d4637354445454b524e46594e47485236504e5a31385a5344304a4a34314756434d565a32453739384b384336433344465156353834465a42434b544d51334a5145475a4a4459334848314338474d37433241545252222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a22483550515a3839314e303851373437363331434835464234594e4d4759364458324d4e425342513454454a4553343045424a3330227d	1577746821000000
2019.365-03R1BYV0Z257T	\\x896d7fa121a8117390e6185912bd64f5690f19bd152abcaee4d3a4ec900e5c86	\\x7b22616d6f756e74223a22544553544b55444f533a33222c2273756d6d617279223a227061796d656e7420616674657220726566756e64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313537373734373732333030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313537373734373732333030307d2c226f726465725f6964223a22323031392e3336352d30335231425956305a32353754222c2274696d657374616d70223a7b22745f6d73223a313537373734363832333030307d2c227061795f646561646c696e65223a7b22745f6d73223a313537373833333232333030307d2c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2250384742424e5743574e3132545844545759583933323736464d3336524858304430513134594d43394246584a51483253423547227d5d2c2261756469746f7273223a5b5d2c22685f77697265223a22304b424e5a5a48323751565441514835434d4637354445454b524e46594e47485236504e5a31385a5344304a4a34314756434d565a32453739384b384336433344465156353834465a42434b544d51334a5145475a4a4459334848314338474d37433241545252222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a22483550515a3839314e303851373437363331434835464234594e4d4759364458324d4e425342513454454a4553343045424a3330227d	1577746823000000
\.


--
-- Data for Name: merchant_proofs; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_proofs (exchange_url, wtid, execution_time, signkey_pub, proof) FROM stdin;
\.


--
-- Data for Name: merchant_refunds; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_refunds (rtransaction_id, merchant_pub, h_contract_terms, coin_pub, reason, refund_amount_val, refund_amount_frac, refund_fee_val, refund_fee_frac) FROM stdin;
1	\\x896d7fa121a8117390e6185912bd64f5690f19bd152abcaee4d3a4ec900e5c86	\\x3b6b416a657d6e0d6e92df9ce66269ad470f3228650890cf54c09f991312df6960455006025ebda42d2148886fae65b82d6871912080946c3da838f974dc6df1	\\xda33a7cd13f692fc76ad87e8e782e9df0b2e3b4e934948d16305f75baf804f4d	test refund	6	0	0	1000000
\.


--
-- Data for Name: merchant_session_info; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_session_info (session_id, fulfillment_url, order_id, merchant_pub, "timestamp") FROM stdin;
\.


--
-- Data for Name: merchant_tip_pickups; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_tip_pickups (tip_id, pickup_id, amount_val, amount_frac) FROM stdin;
\.


--
-- Data for Name: merchant_tip_reserve_credits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_tip_reserve_credits (reserve_priv, credit_uuid, "timestamp", amount_val, amount_frac) FROM stdin;
\.


--
-- Data for Name: merchant_tip_reserves; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_tip_reserves (reserve_priv, expiration, balance_val, balance_frac) FROM stdin;
\.


--
-- Data for Name: merchant_tips; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_tips (reserve_priv, tip_id, exchange_url, justification, extra, "timestamp", amount_val, amount_frac, left_val, left_frac) FROM stdin;
\.


--
-- Data for Name: merchant_transfers; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_transfers (h_contract_terms, coin_pub, wtid) FROM stdin;
\.


--
-- Data for Name: prewire; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.prewire (prewire_uuid, type, finished, buf) FROM stdin;
\.


--
-- Data for Name: recoup; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.recoup (recoup_uuid, coin_pub, coin_sig, coin_blind, amount_val, amount_frac, "timestamp", h_blind_ev) FROM stdin;
\.


--
-- Data for Name: recoup_refresh; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.recoup_refresh (recoup_refresh_uuid, coin_pub, coin_sig, coin_blind, amount_val, amount_frac, "timestamp", h_blind_ev) FROM stdin;
\.


--
-- Data for Name: refresh_commitments; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_commitments (melt_serial_id, rc, old_coin_pub, old_coin_sig, amount_with_fee_val, amount_with_fee_frac, noreveal_index) FROM stdin;
1	\\xf850ac718b33c75f5cdccb172321b141e988ef48213b463b6d710b2a665d42bdd715406ddc1ed7c9ac2f7065b86f9e28151c1b27b226974ecb1abae232a10f70	\\x760cbd7a81dd426506ab07ebaf53f2e1b62dc60ed1b7b52c98f7bbc08cc0b16f	\\xca12c6c9fd3edf679fa30a898d63fcad9cf7691c969fb68fb8b2cb0662b4716afa3ce0b74e6f9e9e5b739dbebbc2fb997aadb1866b32a19f7006aed375263001	4	0	0
2	\\x9727634c5de3910b555611be443329df71fea28cb7eb8774ba6b6fd87a27b930ed5f72e9eacd0667297d502ac29d7673b89ba6a26cf3b0b68b97ace0b9eb0667	\\xda33a7cd13f692fc76ad87e8e782e9df0b2e3b4e934948d16305f75baf804f4d	\\x72ddb044ca29f0ca0fadfadc25114895d21e7bee566ea369443c1b8fb4d80326684328cf4f4fe628faea97537857a49c45381b505bc6e258c81c22927b60330c	3	0	1
3	\\x08f3e4657afdf519dfcb9de666cafdc3edd9249be6455fe1460575c248ba795a1689255984c239a47777051bb9b98033abd3095bf7ae1a104b49e3d5a42db921	\\xda33a7cd13f692fc76ad87e8e782e9df0b2e3b4e934948d16305f75baf804f4d	\\x5efd953dc0757d800dd7d297199ea904d9ec39b12d40f3050ee4aa51b93d62c14e573156023340ba76bacd47bf2c1072ab764884f1b1cf81121bded5f746e803	5	98000000	0
4	\\x11449f862dccaf4919d3fb810d6dcfee6fca68a377f7536a7305dbb1b13213260718f7a4b794b2276bf14c35f8960d980d6347ade552588344e12a68e9b51843	\\xb1c8780ea9d56de2ed3a15518276490d49211cb8fa841a235bb649f0f0586b2b	\\xec72d947eab0d5dfc05ab3e568673e400f5b4c7631ae45bd14573918c508868c4e09decb99cfc467d079f5e579283ae5fcd5161386582d1f5cce6483438a9805	1	99000000	0
\.


--
-- Data for Name: refresh_revealed_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins (rc, newcoin_index, link_sig, denom_pub_hash, coin_ev, h_coin_ev, ev_sig) FROM stdin;
\\xf850ac718b33c75f5cdccb172321b141e988ef48213b463b6d710b2a665d42bdd715406ddc1ed7c9ac2f7065b86f9e28151c1b27b226974ecb1abae232a10f70	0	\\x55524739e0b9f73eba0fcd8ed8a50743dc80df02391a3d4fb693a6efaf77558315066da8a4d3b28ca503f22d49b4c069a7826605412dff933705a9b89c74a60f	\\x7a64d9869f5495eef73d5af56b8dea3b1117257de7ac63509ecd2fb32c27f511505ebc8ea49b81b91535feeb0af9ff1cf65588cc7d1be71260809aab29a7cec5	\\x9edc4b49dd27bf75bc40fe8a358c2c7360d304113b99deed416b6f4c6af4d5552c50d79e1b912931e1b6d126773a5497b4a3e09d48413754d134694826323a86c6924266124a152f5e48a4a1de8616404e0341b0b297360bed562e80497e157f6fa9d5afc36a98e6f0576081ec17d808314bd39fca7227be1bd8e01d83281f27	\\xfccbfa63465d7c6ef89e70e8ab441c158e7c0daa7398a8abc92d97f2ab00794a7ae8366edb11f2556325efc297f4b3bec7ab11be172aef2607ee718f9b7c845c	\\x432e5dba0c6c7aa59abc5bebf823a3c56688107ce76da7593a9297437d98b0d09acb2bc54cb180474f66ba9f46847daaf2201289dc86c7668459ef30dba23a9a22939cf734265df93fed50884beff205b2994ec1a54e81652cb81b93df1883f1e3febde48ade1d6cc6f7edb179c613f6d4ac25c6398393e573a29ab3aab293bf
\\xf850ac718b33c75f5cdccb172321b141e988ef48213b463b6d710b2a665d42bdd715406ddc1ed7c9ac2f7065b86f9e28151c1b27b226974ecb1abae232a10f70	1	\\x2e80cfe026a3380603102cda14426bb369470a7d7d528d55602bdddbfbcc47c25801923a186ca9065fb70d2c225f91f4d3fb37cfa66454f5ed61e0f7d26f2c06	\\xf9dfec817b3e35ab7d322115daee9bbee46cb9e5e479590783b7f01428cb0cd7b4aebcbecf76b01fe2e5e625255881e33aab8ae03c683e243f15bbf0fa6e8863	\\xacca9d179b7c9b1cee396d0b50849680349b63350b5c04e6d2689d6e1c25a5ebb4ddb5fadcddae8205339bfff3fd9dbbee813e838e94ad505d847615a2f1cf1d5babf816f66e0570f41ae4e724c9a61aedb0134f9df0cc1e15dbd196f75437b95d5531f3a5d12882dfcb4b523ed19498be703fbc2996b84ceeeff41eab5a49a5	\\x510fc22880804455789c3bde61b674f55fc05fcf64bd18ec04b7eece03d8f05e10aa7323a46b9331198c3c72456b99b9e39e4c1676d9acb8e183bb499128909c	\\xbbda4fbf01019bff535351c593d38fc1aa7984e86b7126d947bf9e691441e234583622e97a5274948e5179023d1daf35fc9a8cb931f3f8fcf55820c399c81c846e1a850c946604fe3b46f3434bf65c4e7ccf8cc05b18c913ea810cd47fd7d5950d0941357331196d71573e7e3680338e06393dc9da59fb18fcccd6123da7f606
\\xf850ac718b33c75f5cdccb172321b141e988ef48213b463b6d710b2a665d42bdd715406ddc1ed7c9ac2f7065b86f9e28151c1b27b226974ecb1abae232a10f70	2	\\xb1de0c5e9a558206e97e5659c63e6b5b6c5a406346c3f8a5da7a10b017fb230499cf82e41725bd2fd7509316cbe7d7b7f800332bdeb0c5723106476ffa0f900c	\\x860a9106ae6eae432b56bd506c28c284de8de160911f8fe4f8d83c82a49d17cb19bb387e7d6e44ab6a96df96fd7eaa5f77180d52ef5b542d2ec7b50e7fcd7124	\\x8216f1b047bf69cd6248eb7534e066d7c06f4a00d9707613a0702bc4ea893d1d912723bb42c3933b252c70b6942043c8904eb164d53c1c4aa7ba489293a3d8fee6552b63e0bb0ffaa3f051334bb76c7ac9bc9f48d9197bc007b501367dd1c8a93a2fb6ab31589fa5dea2ef05d93989414420453081407027094425478cfb4625	\\x95744d2f3696d31a342adb3dbcdc2a96a751ec41b6e9c2b4bfdf88c331d870dd70f8ad06507af31efec8c30afb9b140c00adf41f26192a55b41ac657923fd03b	\\x36485eb52484fcdf4949a52b13d869f1ddd2ec5131ce7ccc1ae878d783359ec5f771f30e9e1a62d0463a476005d1fe52c922c7cbd8ef260632b959baca932a70df261e5d86c21ec72243a525fd81014788e4a4b587b89390c4f079d5655ba327fd9856e4d7c133f4bfeda12668574ca9f13052bc5e00187475740603e454e30a
\\xf850ac718b33c75f5cdccb172321b141e988ef48213b463b6d710b2a665d42bdd715406ddc1ed7c9ac2f7065b86f9e28151c1b27b226974ecb1abae232a10f70	3	\\x2d4dd6b2944ee0dd8be848038cfba35367fc76691aa760a80b6f7757b19513a3ca738a006ed6ad83173fd55eadaaa2876c064f2a74098defa1c98a8f10989c02	\\x860a9106ae6eae432b56bd506c28c284de8de160911f8fe4f8d83c82a49d17cb19bb387e7d6e44ab6a96df96fd7eaa5f77180d52ef5b542d2ec7b50e7fcd7124	\\x746ffb15888f4981f191c327c1edc2f65334e338379a5868e7760668966263b47cb55a1d6c53ff0e545ac47ea76d5e94518be632f0a645d90952115b35bfb0542af285389c281cf5ce869d04c5e6c89d8e50988efb59202bf768b4731e75fa7cbae3daf60804fa2385e76f48accb0e7af1b758265a7397905c2b89789c905b99	\\x215b6114783178bd5ac28e409612a957bbceb032e1889bd18b353f665200b04860dc663499cc9499f4b31a28a5b4bb99b2d836d2fdf5af9cda8b371d3fee691c	\\x1c20089365bfddc752d412923f6e5e157750bc45644056d407c47efd917b336b7f27f07001c18d004730a6a59862c4b6a3cc0e91ebbd3f0a8ccd2d6a124260812f05a240e08cae935f467022d7eb0d0684e15ec5682ea91a8c1d9602ce4c59a260daeffb4d9d5a2345e9c17b5fec198ae58ceefc7fa1605d41b06698c4cf3124
\\xf850ac718b33c75f5cdccb172321b141e988ef48213b463b6d710b2a665d42bdd715406ddc1ed7c9ac2f7065b86f9e28151c1b27b226974ecb1abae232a10f70	4	\\xdc080ff49f310124d5d2789cf35dd70190de0e7af914133c02b221fd002e32dfe1e6f6c78b3f1e5048a65a5e8f769e826ff6ee2b68ca7abbe02fa0872bc0f008	\\x860a9106ae6eae432b56bd506c28c284de8de160911f8fe4f8d83c82a49d17cb19bb387e7d6e44ab6a96df96fd7eaa5f77180d52ef5b542d2ec7b50e7fcd7124	\\x2990a663d8ee326cf2510a0608d0fde6f87a01414c086804f6708a89be434f5dad58338432c264426a7c405f8242953c36e178cbc267a5d19cf1b584bc6ecb8e8d998fac7b1120b01fdaf131ceb2197f6cd60fa8cc7632a113f66d275f4878308f983205aa068534ffe8d6fcd7414f54371d9ae57f4f1a3383a3d800a4ea829d	\\x9058daf9790a5fb2821f556cd2a002480466ea2bd71688f784362e5bd211160bf3db936af4974221be0c40efcb537f7deade5598ac8b0ccfac8c2e6bea6faaa1	\\x206725a799d17dac36c871a3892d1ae910583eb6f841ff09a4131e004875ce70b631d2c3c981381a0a161d9178777596f042e1d4f0b14ed27dd846bd51eb30d2db1fa536f19c932f2fbf7d192cda73f10dc6bfa15f3894886c10cd5081987ab517d6c6caad270e1dd6f85a453be22cf102262d7176009a4dd707225bc3f38e8f
\\xf850ac718b33c75f5cdccb172321b141e988ef48213b463b6d710b2a665d42bdd715406ddc1ed7c9ac2f7065b86f9e28151c1b27b226974ecb1abae232a10f70	5	\\x95239b973b0fe7d60c1403e907de51de11c7078677477319c78211e83e3ecbdb0d2413f66fd945a9c3e0155f7fd78279d085b0f9bcc7b61ec809a25d41272b0b	\\x860a9106ae6eae432b56bd506c28c284de8de160911f8fe4f8d83c82a49d17cb19bb387e7d6e44ab6a96df96fd7eaa5f77180d52ef5b542d2ec7b50e7fcd7124	\\x67ae6a174a78caf2f1097263d17089f5382f1a0ecfe1ba66663c749293da4eaaf0ed61dd7eaec54fed80380ac267455162b1a1a7b959265a46e09539493300f21becfead2972c8d04f43279b32272d626c36c0d69629c2b953a2dbe7d6d865d032a7bcd8cccd26675b0ea6f194a169b5cdb307a66097f13d54ffd8323b73931c	\\x7ef6741d8e07cba91493172230c2ac1a222795ae5728fee0cc0159c2bbb4922ff1aab8c5b3b8740210a8ae903cdcaa0b15c3e6b0fd4961253d354d515dbf856e	\\xaf4e658c794ab9feb0354824c285fded3e4dc3505a03c109b582c67c7527aef123378541da468dacda18abd297713605e833279d87c2a9acc34d639655cd6b6fba360d24f9b0e7122ae427df846dc16d9682b861d148c15aaa98209462e52b854d22c5f9c79e407f767573fb395526bdc07a700722f1580785c97aa9c7302ad8
\\xf850ac718b33c75f5cdccb172321b141e988ef48213b463b6d710b2a665d42bdd715406ddc1ed7c9ac2f7065b86f9e28151c1b27b226974ecb1abae232a10f70	6	\\x3d9af2238619ed6d26862f69106a1b14b6a7f7036fe9b8c6b589c3f77b6d4b7fe2fe8fa83186fab3973cc0793af295efdf4ddf6a660c9e1c6257afe700a91907	\\x860a9106ae6eae432b56bd506c28c284de8de160911f8fe4f8d83c82a49d17cb19bb387e7d6e44ab6a96df96fd7eaa5f77180d52ef5b542d2ec7b50e7fcd7124	\\x91ff374caf0dcc595d52847454527fa330f8c5e71fc60b0fd3f4176e901301be2de309012932a3d65ab3e64d07b32bff57f0567628ad2079c0f6f2a49605e826ea957667bb5fbff6c04bbd92c5075317c35229a06ff58b85a4a274d983cc4fd7bf536af4339323532649c0347ae8b85a1b5d8603bea174b9dd338f7981eefe5a	\\x651e7e2c70a15c26781189b72c58cee5bedafeab30987b73000e5b51b968459b4a2646e2dad1defc5839e8393654793fcd371fcfc63781245f5ac41c089c2326	\\xa8e005259d3530111b7d2942f2b305efe5a6543b5ad4d3cf26a829a4ee2c28841c89851da02a371354ebd6726903c2c68a9aa68ca6409f5b86ac419de0caaea8d54db86a9e9a4dd0a309b6074fef32da07a3de903a4138fa1d293928bb00bc7b260712122a8aab47143a1236cd252d0f61b412c8cd9c8984ca06241e134048ba
\\xf850ac718b33c75f5cdccb172321b141e988ef48213b463b6d710b2a665d42bdd715406ddc1ed7c9ac2f7065b86f9e28151c1b27b226974ecb1abae232a10f70	7	\\x8741561f5eda9884cb27964180b066447e680a8c42bcd2b89b6140fac7e58ebbb766d4331d6b2de6e026b8a9564c4096936ff7901a8e8572e6b984a561e55302	\\x860a9106ae6eae432b56bd506c28c284de8de160911f8fe4f8d83c82a49d17cb19bb387e7d6e44ab6a96df96fd7eaa5f77180d52ef5b542d2ec7b50e7fcd7124	\\x74bc8b777ff87ae9cc1cd1b96643df54b0948c7ab47b2634a27b02d7a176732ed9ec7345cce33cf9f56f82042ea3b1f63b574bbf4e847445e73ecf00875da575a61e36cdd9bf43517200ed61de35d4e22cbc89d797b6fba568889264002cfff1bde275b000fe21e4446813cb4985948e5032a1e7cf9101447ded84c4d3c3ac31	\\x6e8006cff570b7575b765194417756529823e67f7ec29d3c051094df29d66b0b1d4b32305d8bfa73f1d2ffaf35d07cd16cf69f50e42193fa83bb131db40f6625	\\x4117cff0442e57fa43d31ceb268a9b377e55066989e65dfd329a9b680328f890366a613bd2362060539e9d757462a195aefa81fe97cb301bbd56f218a4d937ec3f7ec202bf23478e9cc42f13ead4a3364a61325614bc7c65fdfbf8c8ffdb88dc9b6b0d77c76a5befc15feac9f2f0b933c0fb2cc866017cf8a912fe0cd97c3cba
\\xf850ac718b33c75f5cdccb172321b141e988ef48213b463b6d710b2a665d42bdd715406ddc1ed7c9ac2f7065b86f9e28151c1b27b226974ecb1abae232a10f70	8	\\x8126be713977f8bef44996f7aabd1e5607d68b241fc693872e0dc9169248d78d5b7d9b658cf85a0dba0bf28c498c1273e5dbbc259f5bc433134ff053a056d20e	\\x860a9106ae6eae432b56bd506c28c284de8de160911f8fe4f8d83c82a49d17cb19bb387e7d6e44ab6a96df96fd7eaa5f77180d52ef5b542d2ec7b50e7fcd7124	\\x164c1c4e08bdd9814fff89b97bc597f24e0d2735a6fdf2d98169ed136e0bae6ede6aef26508ab222125c172bc2ebac70516ccd3ea0dcf545e98e4c18ed19b5ccb5ebe2da3f5809d2f94acfcce18c95f9b53719fc3e62dfa05d2606a4a3dec5204d26a5f838d566e3cff91265c7b31c97893ea69b694dafcff44e860de9da1cbe	\\x84aba474a69d2af384c270eb19a18b2ee12d2238270e37a68d0df8c3301ed7cbf25fa91b357dbca72ea736b38634b18d632688b45715da7bd305b9466c9eb412	\\x36af8252a22165f9d78c40fe11080c7552e8339bf1026b80d75970fb2bffd963047fbc8643d4e93b51cc01f211311ed6d49c6cffbac86323d2e7d5f97404473e611b859c16a0d2f029b55e58932b595ccf8925bb10a6a9a50384f984ba383553be18c9c1f6973479b974ddefb33b4efa84d0db6a8736e63cd2204414ef7916b3
\\xf850ac718b33c75f5cdccb172321b141e988ef48213b463b6d710b2a665d42bdd715406ddc1ed7c9ac2f7065b86f9e28151c1b27b226974ecb1abae232a10f70	9	\\x1472c2be84fc948b3341b3bdddc9922b8c4dff3f20697256e7f7dd82a9154dc92b27d18e560d5069b3592b4e15b8805465574b0606e9e9ec62f936a339b3be0a	\\x860a9106ae6eae432b56bd506c28c284de8de160911f8fe4f8d83c82a49d17cb19bb387e7d6e44ab6a96df96fd7eaa5f77180d52ef5b542d2ec7b50e7fcd7124	\\x5b139fdb0895720e7912ed753513cd84fc54b0dc2a65ef61239de6df535e930967b81228dd17a3720c4bcd9d060afb416d6be52f85f179141465ce273989c5981e84a61a453d7bc36b0eb6a56daf63a438e221f11b5943a0f697e0f2e52a7f993bbe0ba16a4225bf0ffe5819d653275ada7b02374233862e40815d646630254c	\\xdc9fde1acdb01da82e9b25d0fdd8a6b8a9cf507ffc7f1b8dba4f1a81659b907ad0156f28a532bbdced3d34e036991571c13cde5e74cc74c74c22bf85f4ff0862	\\xae8894df7ef257521694c56187e5f09e992ee5e9256f673bd473988b78336169f9718c88300400e5d415d2f1fea718dbc295199ef7b51722e0e0c964e07b43ed80b2a263bc0386d4108b2b20fec15e78d144bf254e69274f8400671e0f24caeac9998085b0efc97b2285baa7d27c0cb06d667a0b383bb6d51cd30cdef8a49469
\\xf850ac718b33c75f5cdccb172321b141e988ef48213b463b6d710b2a665d42bdd715406ddc1ed7c9ac2f7065b86f9e28151c1b27b226974ecb1abae232a10f70	10	\\xa981e0ed8effe86f4c8c4664fb6d0f5fd1332ecb6cbf35f7f3644433de19bd9d7a7b4b3545d31ac806bc3290e4087ad75d7a5eb61048a49ccb8eba5f92d4ca0f	\\x5cac576b6aa21e7df191af5ee270caf70a0ab3a64cf16006984a44dffa43d6021188fd63c00df4265316d9ff6f415f9e06f83f50996962da962309b78d445a42	\\x23b8ae52e297fa23b06ce50293afcda5684ea6b511aa285125d53be7b17bf3f7fc335c4a60d1b6da7acc18fbf0224085272f66ca87eaa4b34c5e2569090d2310bcd922bbfd4b74214ef34998e2d4fef8c23cfaf70497e80545f1f1018131ae7cb5138835dd7b4ab82110a8ad4dbde16c37416744c1c72ef069c65edaf7b7d026	\\xd0aafd23d5cb202c662e122419489b49e5ed49bd5efad6293db147eb36f74af836f6f312526967182e2a554686da198d7107d7fadb8066aedc101a91405026e2	\\xab4f7515d076518904ecee641a3ee2065612cdebb16e39ac315d1ff640d29e5f5ef79b82a47073c190b84ce63d96dbdeb6e18d8060961bf3751e7a9ee41a3081f58bb97469e2b83e5266ac2a35fb0abdcf51e0520285dcdca115739ea89601935aaeadd49b415558d1ff9e52db1a95d41770bf95fb60599b920a99e69a8bcf26
\\xf850ac718b33c75f5cdccb172321b141e988ef48213b463b6d710b2a665d42bdd715406ddc1ed7c9ac2f7065b86f9e28151c1b27b226974ecb1abae232a10f70	11	\\x4216cc426812aff8f4c8d31d195119abb66d9c49bde7a6a814c8cee4d3d132901baf7bbd461bc0f11d5f6309a375b82fc7f4389bd585697d799f239b0934ff06	\\x5cac576b6aa21e7df191af5ee270caf70a0ab3a64cf16006984a44dffa43d6021188fd63c00df4265316d9ff6f415f9e06f83f50996962da962309b78d445a42	\\x06954e6860e13ed1b36f81e8a4554b24feaf5e905bf6ab8c9e087abc4e68a0fd83de2ad3d579534cd9a587d55ed0f9094afcbb23998d7890f85173d74f7d0a946a5eb2860daf89cc1a92b1982819adc83c7fc8d3e7dda54247f89bf4895ecf1ffec1b556937f428db2d73695d617ef6e72c6024958440a7ce8a100ebb36892ec	\\x919ce6bdf5533f5f676cab57ab1162b553f7eca797462e7d041e78192ee753581f7ee0c87d3e16c0c6f83d361629b449f513904018f3e49e2a147a2371941453	\\xc1accc0841f1e64977c0415f5ecc879b456afe48c3aad7113a60fc9e743c6277b9f6f036295f98fe5b5b26cb303cad5b3a92d693c6c368b475e2dfa5edb5f5000e21d81cbd88e0d26f140ec3f6f1c5a1d7e3f8ba4fc591bae0f09efbafb581dfccb6787dfd01be4cca1cd78b72834f578d1cae770c60b50057a996f071828038
\\x9727634c5de3910b555611be443329df71fea28cb7eb8774ba6b6fd87a27b930ed5f72e9eacd0667297d502ac29d7673b89ba6a26cf3b0b68b97ace0b9eb0667	0	\\xbefb1905a65f52935abce01333c4ab854618f8c35abea291b338af07f3c472dabad223006626ebe7f619d0241a6c76325ea265abccfe83d5fea6194491be6e01	\\x7a64d9869f5495eef73d5af56b8dea3b1117257de7ac63509ecd2fb32c27f511505ebc8ea49b81b91535feeb0af9ff1cf65588cc7d1be71260809aab29a7cec5	\\xaa6f4151991535386f2e6316103a26bdff3a6c5b74303797a72bbe2c1472f24569198e164b32a7bf4ec4ff8552243c8c1be2c9ad9550bb6c7b1946798b17ff3a484d4d4be901e5acc70dfa9383640940567eb110dfc87e55a679cf139cd1ecd5ba1c965b20609e06fcd7e1d441fe146762bcfe1a72e2ee87f474f801eb21c518	\\xf9ce56a1424ff557240983c7a8adf97735fd726ef059803f2781473dc2bea9a3f4b9ddb3d2ea694dc61fb9d4d21c2b1021a562015ce7346a2055d240f19b71ee	\\x68f0872cfa466d279fc8184fdd58c885d3373ecc0edab7833a78a8cf8997e63979727a361014e939187883b03cd9e7044bc83213128d8c03397a72550af06ab15bf53553592ce15812ec2f271a1452061baaaa26f5c3f3496b8af057fbcb7f6371d092cb7ea3243a41834f2174dd939de7acaec74e2c82c4ae370e79729adf5c
\\x9727634c5de3910b555611be443329df71fea28cb7eb8774ba6b6fd87a27b930ed5f72e9eacd0667297d502ac29d7673b89ba6a26cf3b0b68b97ace0b9eb0667	1	\\xa4314f4713c623837e6c5d5f2479a94cf5b322d4b59d96efc38861069afd30e0b76f50c3a1b2f2798622c2ed55ac1275a1885133054c844d3739adfb1f506a0e	\\x860a9106ae6eae432b56bd506c28c284de8de160911f8fe4f8d83c82a49d17cb19bb387e7d6e44ab6a96df96fd7eaa5f77180d52ef5b542d2ec7b50e7fcd7124	\\x59f4dcda2321d35fa70d96958335ede44a82632c8a20f01dfbbada0a953574b57f111c37040a99cc8b46710a9bdfd345113ef52148ef0fa70ce68790116ebe199c238c93b3d100d6c6caa4805447681c2890ecbe71c51c8f2debc26045d9edb5af0d5da1394b4738e45567ee1c3c45d7c3c2c66456d41496be1153a3a6265bec	\\x3b2562a120bbec34fd3e40c23f34f30bda328e4902f404f5b8357c6dff07f983e91bf2a6eeb89c2ae0ab6aa9c9ece8fd6ffbc43096db25e05f260ca156f88887	\\x657fb6c2751cc565f505d896cd20add4771340e43b2832abf3925caf53ef095676b7dfb7b9ab1558775d287eb85cc361e212aa41816e3c09b170832897c02f0032c71cf8e56532c4e59d8801c3b6594282ebddb241fda5a31bcda5a48efe6a3e5b63ae45acf308be2438cd21e158b05ab391450587c00eafb1ca49ce73fa0a46
\\x9727634c5de3910b555611be443329df71fea28cb7eb8774ba6b6fd87a27b930ed5f72e9eacd0667297d502ac29d7673b89ba6a26cf3b0b68b97ace0b9eb0667	2	\\x4392264765436bf8b636750a49f843fe4390f2b122150699aa15d7c8d6f2cc30b911c033b633c9204b9ac7a0280c7adf674a02493d45cf7df4bec371667b8204	\\x860a9106ae6eae432b56bd506c28c284de8de160911f8fe4f8d83c82a49d17cb19bb387e7d6e44ab6a96df96fd7eaa5f77180d52ef5b542d2ec7b50e7fcd7124	\\x19cded07f47cfff6722826e1f1f59ab57353eb3e84097a0b06d4aaef190afdcc5aea5fb7be75cc8092e58d20ff957011e1c8e2aecbab6b9240e947fc005b63e321da4479beb05d6b9980531bcc441a4fbc266a3df0f05146240695cac871122619826e1e96f187708b7512a9da2085a2cb0d3210dadd1ead760042e639bd3eec	\\x6c1d34cdf552fe851a6de826077dc5db6e7bf473aace2f809d3f78d013ff41f6cc59ba89ebffeb71fcb78bc582ad73a5b3027f760167ddea83cc183b26e87528	\\x77bb81f764d1280ab9848b30251984fa2254ece678ea8edba2a680476b66513bec7ac9270ebe9e37c54baa74d50e7a74a16590d665b4e02727917b40df4731289e1a6eee439f701a1efd059bb6ae5308400dd9ebb382bf71b2bee27ddc6746659bcb4488baef52aad275307eb150206c0a08cfc092c438c554feb4b03c8bffea
\\x9727634c5de3910b555611be443329df71fea28cb7eb8774ba6b6fd87a27b930ed5f72e9eacd0667297d502ac29d7673b89ba6a26cf3b0b68b97ace0b9eb0667	3	\\x98d55284b375b7b4a2481ed546770db30860f868b0d9291995d3d3b76a4de63c03f06330e60dddd49e1d5c61b8e0003efbd8aac75cc77a8c047a69e3ddcb8d08	\\x860a9106ae6eae432b56bd506c28c284de8de160911f8fe4f8d83c82a49d17cb19bb387e7d6e44ab6a96df96fd7eaa5f77180d52ef5b542d2ec7b50e7fcd7124	\\x41c0bb4b7562c7d7971324ceed28ec4852f854f302a49a312e012bb64cf5ae6a7febccd772cae7bcb97fb6b16bd27d061c2a811772aa47d6c69d26ef1769c4888d102f1ed2e0867f47ce70afb129397d5e790e819991d8db2d2906a70f5ec485177a667762b9d3aab1002374e80fa78a2558e1bd2a5c001ac868ab6eda72113e	\\xd31d31ed2c8e43296e727fd82e0f8fa347d8d0f58ca9d775f231d4f7c016ba83afae437334aeeccb9f8a83e1d005afa5f7fd8baca9e7e5f74017b784dfd15f89	\\x0360b22321f671aec5018dfdcbcfbbf15b2bab10f066bfc5a4a4eb7da3d53830cf107627c544fe477fb319b6e2d903d0c481f245d9de1c684e48069f3ee614acd7b57b626b42d58858bcdd40ff738d0723ed4c7834c6da06152ad06822b19b8da1cc7738775d56030debe51070fc4241bbe8fddb287fae98c25813d78026be1a
\\x9727634c5de3910b555611be443329df71fea28cb7eb8774ba6b6fd87a27b930ed5f72e9eacd0667297d502ac29d7673b89ba6a26cf3b0b68b97ace0b9eb0667	4	\\x276e0389d5c57673d4642426f9acf5cef5e84a329e031cdaf27b929839e419f32e6ae73869e11aaae4b720d774f89355d739220fdea7428364778394afc97c05	\\x860a9106ae6eae432b56bd506c28c284de8de160911f8fe4f8d83c82a49d17cb19bb387e7d6e44ab6a96df96fd7eaa5f77180d52ef5b542d2ec7b50e7fcd7124	\\x401eb834a0f56e3a6c8b569271243e7d8fd36eb824b23b8ef6cf7dc872feb042c2125e0ed78399874dd0cd7d244ba3e802d6c7771005823561c33e5493ef88563f8f724d3854639abc851fa5bc8d7e3f69c01961be4be6df795edf5336ce9e49f057684789d6896695202d448c920bb1887a3966faf98aec8bee5e546b694712	\\x6f4c7720fd356ca39b83369a78ed94d26b929c3e9a7d0b3d77dc793076f555be739d4cd5cf9d0b83648d8aee468eea61de97b845fe530ca07ee10cfe61b350fd	\\x717277a76a26979d9322c18dce89331455c7563e66a51937f7c5decd67898418cfd9907cc40052a1844e548937963b21e9e3bcd9390711261aea03ec230463e9a7b40c5edbd1abc435283e8ee3e19b5c436cdc7db2072a455b112c5663460e75a85d1742db719a1fd75ee62fc83e746e946137db9133230ab6e467d629b4e2e1
\\x9727634c5de3910b555611be443329df71fea28cb7eb8774ba6b6fd87a27b930ed5f72e9eacd0667297d502ac29d7673b89ba6a26cf3b0b68b97ace0b9eb0667	5	\\x522e56475fce6da09438df6ef6bc64970b3df73f4142252d958d0f5a993a228db4aa7b4ff72376eec8611497e289a55bf61b3d6d98d40e0cfc5227cb51822703	\\x860a9106ae6eae432b56bd506c28c284de8de160911f8fe4f8d83c82a49d17cb19bb387e7d6e44ab6a96df96fd7eaa5f77180d52ef5b542d2ec7b50e7fcd7124	\\x32c5a751e42b6d6cb4bb2106730a488101951118cc64f70e381b9912cd74801622d0dde0ebe92c8aef6e345f19a78dc15709c25221cd54367cd06bb0f49b2bd48018844bdfa21455f4a8f8a397e74add63cf0f609a2ce26add738d264fda4b38b6ff92cd3f97558019e232f48a0fae41d6c225f642ee595d98501a967277567a	\\x80f1bd0b5269f13759c9c563082a54048406d2ad60c0eef1433455b9b6af2c0f86b5d754827911749d10c83b86251fa6ce253d920f55f112d1c7b15f51abd8f7	\\xb19a1eaca583ccf037f374ee5c5b44a9c34cc5d6775769d455dc0c8eafa5f5ac563d005edfc6ffca2302a9f7b60f69f5f05b593a3913db797cfe481c2a6fbc6d7d2d8b19a7dabf4b78de11af606d708fd401b50260b84821c64b23304fc4c3113093b0eac575828ae7e1e56b83a5bc274240dbb23dc3509d8744740daeb124ff
\\x9727634c5de3910b555611be443329df71fea28cb7eb8774ba6b6fd87a27b930ed5f72e9eacd0667297d502ac29d7673b89ba6a26cf3b0b68b97ace0b9eb0667	6	\\xdfe79aae5ca3a88234d07cac542b1cde363600b0a882f332e63260a26cf5eee6beb9b11676947dbc794e8508b0a103ab93e0c71105cb200fe14b040ee10f4408	\\x860a9106ae6eae432b56bd506c28c284de8de160911f8fe4f8d83c82a49d17cb19bb387e7d6e44ab6a96df96fd7eaa5f77180d52ef5b542d2ec7b50e7fcd7124	\\x6194169b272a6dc779dd52a962ab814930844229d06826555d4e73f59d979b26f8ef591a35d050b2e9c685b21b01515f93ecd41bdf5b8bd5026338d097f9d9d7b5d2999972d3193f698f3ca5d210078e5775b0852058d64783183d56883aa062db977bd782e451ec49a3debe29b4f736ab3e7c65d550fb3205484eb17ca5d749	\\x4168e7ff49ffc840cd6ee39de4d530c0380aac2c31191bcf331a18c545e5fcb5282ef0d8b5030a4784640e54569d37a4af502383d40af9d7183d7daa073d4a7d	\\x40acc4ed8b5a4793cb888b61e09ebcf4abe18ad4c991496364d9f3bb4d9de4d27793e5125bc1730ab3e0ba563bed88c0e7445598bc9253ed8cb1a767ca32f418f984348b3ce2d5c2afb18862e910433aa84f5b854822a84f1d09785a3dba7b842444ff06323bcf8282f8256559df3a21beffdf8cee9b9498e5c67d3c0734d97b
\\x9727634c5de3910b555611be443329df71fea28cb7eb8774ba6b6fd87a27b930ed5f72e9eacd0667297d502ac29d7673b89ba6a26cf3b0b68b97ace0b9eb0667	7	\\x7fcfbba6b6f981d7a80c00564cc80e8ee21e8adce2aa20b378224e95a885e14acfc7dbf69e472e6b0099e15940df25466b538ba74a3d73cbe63ed6b6b355b403	\\x860a9106ae6eae432b56bd506c28c284de8de160911f8fe4f8d83c82a49d17cb19bb387e7d6e44ab6a96df96fd7eaa5f77180d52ef5b542d2ec7b50e7fcd7124	\\x0d52e5dac9e841731169bbccd146a21217a376b10dc92544085a9fd84e986d06d810c9afc2f85aa1dede5799016dc62f095b23b25729d54299bd02fe4a8fb1816a7ef28403f6f550a29555d9114408810d0bd42e6e3e187448e4c24db9923f2dad95eb19b2ec1e7fceca59be848be50e6313bcfa3c1697be4ef09072a262bea4	\\x3933f1f20b8e711ac99da807e4a559895e4de70f26220293516e39ab29f5f8d86205ce72ea13cf9b8bb1180152ca9f69b89052dd800564451b4b5f006377bb1f	\\x4e2692f2146b2ae93175106062475d775318ff7f3b8771f89cf06cd1770fd3b590c8e50582a030c1e97fdde22b73bdbf42596e06ce1535e96ad4661057192d8ebc581cb2eee46ce12fce4c32f0992c7a777b5e941d5adcac23a9cefc5b020080b6c499fffd9d51145251d8891dcea81fa9b0ba497cb2a1d2621249379bcd097b
\\x9727634c5de3910b555611be443329df71fea28cb7eb8774ba6b6fd87a27b930ed5f72e9eacd0667297d502ac29d7673b89ba6a26cf3b0b68b97ace0b9eb0667	8	\\x9a5f9a0ab725850009f1e4d5a0c7274594004e76ea45eb4f956e6e189fdc3182d0b3655634d4979e150d790e1c155906be8b761df5cd1da5c9728dc337a40805	\\x860a9106ae6eae432b56bd506c28c284de8de160911f8fe4f8d83c82a49d17cb19bb387e7d6e44ab6a96df96fd7eaa5f77180d52ef5b542d2ec7b50e7fcd7124	\\x9a72b0c60cf300461c1fc2d1c864aa9bac619038a7d4cecf1f6a8907746c25d3c716d1ff2aea14fba21a4842ea5b4b16725c43f2200e58be5878a2ad702912eafc7bd349c841dd04be981f070159244e736490e3b88ce6543ee4b0a2ee4bb94e67b0975a1b75c047ccc71160e0fbfe9213d1c47a7398e09d7c93b630a42f4353	\\x8d4dabaeae10ee9ad1182b58515f8c19732a63b8f3620323bf13f7163049517065e55ad723a1aa2ecd8b9b7cd037846238b671f42c2ab4056764db87b6e5e782	\\x4224510f5d8343d8de1619e5fb9e83302bf8df400b7fe71ec427e1af81beb1573975a72761100a0162d7e66df572939d57b2269950df42b6607ada5c2dc714818d82768e35102ed6186c10bbcd703c94964406348545744ab696b8c27f6a445d69d6ffb4bd350a2d661a96bee366bfe7c749abb52037899dd63115ae248e0761
\\x9727634c5de3910b555611be443329df71fea28cb7eb8774ba6b6fd87a27b930ed5f72e9eacd0667297d502ac29d7673b89ba6a26cf3b0b68b97ace0b9eb0667	9	\\xc1d17e2ba343c81509ac0915462496994898e5a805fa394734301eec1a7f43fcced1f34d95ac54dc0e1536ba736617e10165c055b30c24802fb65d6d96ed2d03	\\x5cac576b6aa21e7df191af5ee270caf70a0ab3a64cf16006984a44dffa43d6021188fd63c00df4265316d9ff6f415f9e06f83f50996962da962309b78d445a42	\\x7fd9f9e6a00007d9dfdbf4a535f55b66a5818d7e3c8ab532233f3bfccefba15b66088413686d1bb9f4a3d8de42c2d1931893e068543d2f043125e9bc579a94736c9b003a6001ae6f83bdaf11c2f3b177d2fac314ff58240e614bd0f511aa665c428e73cbeea1e28ea75ae3dcceec0f9e40cdbb44c37ac0758a332c055550e61a	\\x6bd0c2dccc52c9c8da6ab150f34cea1a05e78475801fbdf9e1e0ba0f14d01c95fe926b4622cb9b01c80175fa4dabffa64ecfb42aa201f4d02b0c1518140c9ee8	\\xbed86d31407e6a68861ed9337083b73bd3b68d036ed0c1285c04953ff3b514481ac8943d42a6b615f2872c09fc9562740c2635dee6473e180eb30b3dab07947099f8f002e1742d45ee7bee840d88d7e32ce7838f0f04b589d07c39d76a2ce5bc3a0f17ecfc995816c538d432ccd71b6a0630c61782b866b155c27cbc7bd0de81
\\x9727634c5de3910b555611be443329df71fea28cb7eb8774ba6b6fd87a27b930ed5f72e9eacd0667297d502ac29d7673b89ba6a26cf3b0b68b97ace0b9eb0667	10	\\x03caa6ea25bb9d239db560f12f9aa4062dca343c222ed0a70cd9b77b9b9b849217175484937bca176eb21f37f263c10b79ed08bf1c2e072e8eac5f263460e209	\\x5cac576b6aa21e7df191af5ee270caf70a0ab3a64cf16006984a44dffa43d6021188fd63c00df4265316d9ff6f415f9e06f83f50996962da962309b78d445a42	\\xc422a28ecde7ac944201750674cf9f4bbaf899dfaeb92d55af770c312929dfa383e0799c0e3d26aae33595d32c6918ce9fc03ed1d68302d030a58169e2182ac353ae17cae5612eabd14fce9a364612b57f468e424bf193820fbdca73a83d7f99f2c2ef4eba739cf0e0dee8cd2b9fa148127e10a12b59c74848c3be7dc2f5f14a	\\x8c7b12ccf967851e1a9632818ca4e7092e637c009e6d0bcf1ff3827c789d9c32552da9feecb3d717c32a66d2166bd24be221294a2ae9a578185fd6b989343b1e	\\x5d15d2d5042471c33609ab2651f8075ae7b8689ccbf2509ff3ba4cf583aa82d6d6ae282b194e86cf7778ba81876c1a4811534473c7087a56d21001620ff73e5954e2da2c27eda7b156f90655af5bb8cd9ce5ab8996f9b6b4785cdd593e1553834a204930a06269d194a93145a5511ad950fae34dec3b70fc60f932cd48f8ca71
\\x9727634c5de3910b555611be443329df71fea28cb7eb8774ba6b6fd87a27b930ed5f72e9eacd0667297d502ac29d7673b89ba6a26cf3b0b68b97ace0b9eb0667	11	\\xe5822b23c47264ae3e4a99cc77a0c56ae6f937713ddce6e33be66c4d3e152e08d995a08ca630fac04c5d0ad53ed867bbd70d49553246e3acb3b5ec3ff5830304	\\x5cac576b6aa21e7df191af5ee270caf70a0ab3a64cf16006984a44dffa43d6021188fd63c00df4265316d9ff6f415f9e06f83f50996962da962309b78d445a42	\\x3b9ae711df06c160dc36aa55e1f4fd05ecfc29c2182f7d5575f9a345502bf2e3852486c8f80c0b2d0936a3a6023a0b4df0fff25d2c8855322a84a44963c09a4a81ffb53f2058646bbce9ecdbaa1101ab6660b53cab71db64d75666bf88bb4e5d8016b734fac097d15126401f25b316d9a4aa05ca883f66c58254ae78eb3d6223	\\x412ed7cda7682f206af453e37bdd3e2e5151ba07853f515b7c775ab3f2dd85be73116898319953543f9543ed6550e248df373e225a18c7ba29eb1b7f03627cc6	\\xc5a354c2e01a3d2e3144c744e37af01a38d1106c0ee0db8659795acbc719e456b8aa0c43f8107fc82d27aa776abac869893420c407309ada39761021826a8cb704c800d72e9bc8b551f186522c8fcd33a7866dfedb4527d0d92513f691c2106bcac285754600e1003aeabeeb80bd5ceafcf7890eb938e00b42c06097f2210d7c
\\x08f3e4657afdf519dfcb9de666cafdc3edd9249be6455fe1460575c248ba795a1689255984c239a47777051bb9b98033abd3095bf7ae1a104b49e3d5a42db921	0	\\xae08b43cd718a3ef95a25abfb6fcc8b8a5626d175d6c7c9b3179855e6cb8643213363a04bb779438c27f521d454b5fd700b17187dac5219cb884c835c2923f0c	\\x335c50be155aa7740ef7d610f1a805049a15090438451bc8a2c0883753bebc53f291749044c51fa1d95c691e2761b2e580959a8a7fbca31eb80ee5b8feb3e448	\\x2b16bf9d42ff577d4e8f250e592698fb30a4477348981af31e9646453e448021517d44c46eaaea4aa5c035fe5be02fd10cb4a44023a3401da8ab8a0747667d53b8807023864de0939c7d80363306e450d1c34a0dddb2cce601a08ab7178e7e4159f178b8f0454eb232f439e4cdace66767b2f21a6b6d45911b41e511d96f2b9e	\\x36ec6dbff764a8d8b4a71c7500748d8a996c0881c550d8f6fe13eb1d4304fc8cc3d6cef1c398da8a2f5d991fc14fbfea432bdff3a5d48e01584c0033f18da708	\\x17cb964969d12bd7c1b2a1897d659cf9a320c77767b3d4984d9dcf36bc17cbb0dc7a18497374b167e95907230655c2c9d5df5ab0ab4d7e0e59800df7c31960564df6091e79e9cf6aca099acedab474d905db39b97fb650f909da1836d44fccef339a7fcbd84f2478e4e6aa914f0ee1c93a2f8afa1f1fc8fe8d21e26c2dbb66b1
\\x08f3e4657afdf519dfcb9de666cafdc3edd9249be6455fe1460575c248ba795a1689255984c239a47777051bb9b98033abd3095bf7ae1a104b49e3d5a42db921	1	\\xa14e6fc7a44d641e1a9e5f6baee844f77b38f461e24797863949abfc212610e22f9d071852867234c469057f4c95895a6d42a7ed95a4164d2c737a72413bd006	\\x860a9106ae6eae432b56bd506c28c284de8de160911f8fe4f8d83c82a49d17cb19bb387e7d6e44ab6a96df96fd7eaa5f77180d52ef5b542d2ec7b50e7fcd7124	\\x9e33b37fbfab71943cfc2f2ebafa4724a7d814ed3ba8509b6b193629a4c10f344f70ca1ac4b2b1523ff03d9f6c62174efae7cd624008631f3399f25273a0ae7557e942562115dc2d00fa036d681dfcad556b591e7bb1bed4029bc2408530c2de9062fb97f682565a5e63427ca4945d454325c92a15d38dc82f935bf146d959a8	\\x03e9f81c777878fc7601a4b06d5b510ef7a89e8e348a8d924db3e0167fd0e27cccf9d3c88040de0c1abdb9e258b74884379883eff747b2d1afd286e221e7fb0c	\\x0a818c33518465d2d2960d721c9ae3be0c97e04f7cbbb52882d98330507fb200bddee28451525c673a4fb130008ff05aedd6700a3693447baa39108f63a1d068757fc617d911d24b387c660ad61258454d4b8af6b57e7f91d814322432fa61f346121a39d24da5923f471895de684b19b86222afcec706728df0573deaf99b67
\\x08f3e4657afdf519dfcb9de666cafdc3edd9249be6455fe1460575c248ba795a1689255984c239a47777051bb9b98033abd3095bf7ae1a104b49e3d5a42db921	2	\\xcb802290084ca69b623cf0639b4bc90b76fb77caf688ad5d0b614daf5bc1d337552b31735c522de7b87dd00573dfa6f9fff19e34a88c14a51ea8ebd929a23b06	\\x860a9106ae6eae432b56bd506c28c284de8de160911f8fe4f8d83c82a49d17cb19bb387e7d6e44ab6a96df96fd7eaa5f77180d52ef5b542d2ec7b50e7fcd7124	\\x383c1a8d8ee114f96b2a768ff4a53a6a6b104dc0b9a587d99724a264d24cb52094b7df9005a801095ddb2d055c12e5134b32f529e201a49bca84d0e62c3d2dc331c46ff30d7d44d421ec455f1d35e68cd77e875d43e227baac0a44e5cfac5bb3f508680b5342426dc46665e20dfba3bd8b6beaddf61ec9cf67db0f5313be387d	\\x1bf87aa6ba37ce8838419e5ad5646c5e52a31a8c56e11312e4b7a4709ca5cd7ccb8a2cfdfc027cb524f913452e0ff7d5effc3b9a9fb700694375cc7646ecc4f3	\\x559e2b3bdc31b96352c4abe6cb1cfdc666f65298e4dc40fe72a482e22f5ab0577ed2edcecc904ba2e98ce7845f4c82bb4b964d785441b95984cdd2d4d1032cfbc782435a41ad35d73ccac49744f74391a74aa79f114313ae6fe81e594915e2d63c3de55ee6b7286416fb3d0427774044878f95cc9280ab34fb885557bd7cc1f9
\\x08f3e4657afdf519dfcb9de666cafdc3edd9249be6455fe1460575c248ba795a1689255984c239a47777051bb9b98033abd3095bf7ae1a104b49e3d5a42db921	3	\\x69d7211c99d620ede6e928e021c485a777c6faa79f161000a3b5fda451108f94f84642bde45df13880e1cdb3b3c44c64ddebeba6fa6eb2bdcb693b6856298001	\\x860a9106ae6eae432b56bd506c28c284de8de160911f8fe4f8d83c82a49d17cb19bb387e7d6e44ab6a96df96fd7eaa5f77180d52ef5b542d2ec7b50e7fcd7124	\\x2da832bacb4c280e5ca0c88332e57195f6c1c645c6145ff301d6857a9a7a935d70e85d0120a454de6e91eb5478affccae0cf91135240dd716ad3b2c635ba8bed85aa414bd7b0db9b1487a218ba4b29979b69a727d432b12bb6bc605011b778ada325dce0359e2d9af0cc4eb91faf34072ab76168ad3142f34e3da853d7ea0a44	\\xf482c734429184388224460113144b3735b5d0a77d96aaa1c9f89a69fa82243e32c712bd937ec71067912ea2f9022c232fcb87879442fbbccc366fa1a942999e	\\x908f4a753019a92688a4d05ff9ea08361f7855684256dc74ba5cbea41df57a8e8c649dc56ecf8d78ca16381d012fef93bfa047cdcb4dc8ed466b3cdc87b1665b916a1a02b9a07cce7f6bc28db0cccfcf23b5e7f624ad3d882ce11729ee5a3265397c9dc6f90ec741c2b0e0b143600ee71082079676d1b6a31b930c583b4869b1
\\x08f3e4657afdf519dfcb9de666cafdc3edd9249be6455fe1460575c248ba795a1689255984c239a47777051bb9b98033abd3095bf7ae1a104b49e3d5a42db921	4	\\x597db4142eb3cc0cd7f91464ac5c998ce24538667160c57b4ae8c3a83c9875878dc2dde886faa961551416bfb17e1585035cc9e7be8f37ff1a6e347a97817b0b	\\x860a9106ae6eae432b56bd506c28c284de8de160911f8fe4f8d83c82a49d17cb19bb387e7d6e44ab6a96df96fd7eaa5f77180d52ef5b542d2ec7b50e7fcd7124	\\x83b344bb67dc13a6ed8477997dc2c728a1bf5d20bd95acc9ea64bf63f7ce0f735775e4b889608b912b1cf64ccddcc710c725253e3fd536cdcb0c0402ff8d4433f1220c1591c8f22cd90ebf8859f98b973b0543b39698baf77ca02b0041219c21c4f40b4d5f2acff9de4cea6ff6716ccc80ceb8f11a6e89d3353baa1dab724136	\\x99a8a78228503144b6beae8fe73011af59df5fcd45c0b7d9e8e09abb8c69d27ed881599ce9cbccd57cc8ecfeee513367595629af840afb648bb0a5ddbd58a376	\\x6294344c231c9a285b7c4037c0af7f8220d4bf0f58e85a26129b86cb83b25243505494cc17858e5b2269450cdc019f77315ac950b98d865f3c838986929b7299243d5d4602757d0348a685d7557e373322b591c32c0af0bf5db66d5a51a2af90ef26e80e41f798320fd58f2d1cf0e1899a419ba6c8062eb186f2762e0484b793
\\x08f3e4657afdf519dfcb9de666cafdc3edd9249be6455fe1460575c248ba795a1689255984c239a47777051bb9b98033abd3095bf7ae1a104b49e3d5a42db921	5	\\x2f5838883469bb2b600ba70be81a844eefc677c7063980f8b6c7f3af9d9f64b75b967270347050f20cb64fe5206d4f0d1dde562e1bcc60800fbb6562d2a9180a	\\x860a9106ae6eae432b56bd506c28c284de8de160911f8fe4f8d83c82a49d17cb19bb387e7d6e44ab6a96df96fd7eaa5f77180d52ef5b542d2ec7b50e7fcd7124	\\x0e71b6cbff8bf1291e4c0a458427d12d299b2e2b8f4490b1a37699183b91b23f657163ea3c24635bfe4918b81e0f3cce3266538c9f61d5528a33524de969cd745270d7db6a6d39ad272c518934f29e7ac325ed0bff35e335dfccbfb9511d7aec8537d021e82bfc45ff35f006536e0745cd73f9c90b868a60e4aab9587e1a9e6b	\\xa8f56faa63854eaf9c8c152ad0218c1d774c4fbe9e6a5e93e0495038c3e015bf76813703c709ee6a366818b7eb5673e874901b75093cd1a19f78f1abdff38493	\\x7d16b73a18a379c35178dfa44b31586c991ae91fe0f85a3f653ffec7af510d804a50245bbfeee6995b80651fcc3cb719d911e7edbc6c2c647a1b56fc912aeab1fc1d151c380056c02122f5df352d623a2270e8f2d940a1dcbc7b999d42604ef06cf53b809fe6b15ce7c779737647dc0e3c95b6589f3707a0ae848f9d0adc6bad
\\x08f3e4657afdf519dfcb9de666cafdc3edd9249be6455fe1460575c248ba795a1689255984c239a47777051bb9b98033abd3095bf7ae1a104b49e3d5a42db921	6	\\x3a6ca97e284a241a98345fe160879e9bf90b68d1e71987cb2b481c51908347d9690765c9f86fb9f0268f7b282903b2ef4de4af85e05d859b0249a5fc3e99dd0c	\\x860a9106ae6eae432b56bd506c28c284de8de160911f8fe4f8d83c82a49d17cb19bb387e7d6e44ab6a96df96fd7eaa5f77180d52ef5b542d2ec7b50e7fcd7124	\\x6f30a232c67a4bce69dd74e97e173f3c687857952c288a04164dc978aa0ac196d62c0a453631002aa88bf852be1cfe5262e3dcec5ca09dad650dca1f2a49b25da42e8d5125aa7d6f219aa88734aafb116b8d0c7946de17921f17fb734d34a9649bc9be3d15cde33e56f2c569469713c65e0f055c5e734672d27eeb9307a7dcac	\\x118e3558fd4fa0729023da5170429075e2fc3ebcb70fda4a5ab9e01a73c56590f577c8550c1a092d59695bc33d08bc357daf9a4b0c9d423913843c359a0c0675	\\x29837f806e1abec736fb2848fe3fcb392de70516cc78c4d2215d82b5a73a93fc55eabd407a5a1e6dd3519a0076d732bebad5a47e10c12b6467cf214ac2c3ce78e0cd659c0bd82c31c6273429b8f87386e9f3d2116dbc3ddfbc593c3d8062ab859e3ae8feedd55c91dd4c6327de1dc415b48f88a19c3d3523f6e287cd1205c894
\\x08f3e4657afdf519dfcb9de666cafdc3edd9249be6455fe1460575c248ba795a1689255984c239a47777051bb9b98033abd3095bf7ae1a104b49e3d5a42db921	7	\\x10d536179a5f817ea3b8a73376f7287fc744a5450c16c4687183d330f6a371bf2140239f1c2734f093ef8f52a9d070decd27b41ef85c194aad9336e72e087e0a	\\x860a9106ae6eae432b56bd506c28c284de8de160911f8fe4f8d83c82a49d17cb19bb387e7d6e44ab6a96df96fd7eaa5f77180d52ef5b542d2ec7b50e7fcd7124	\\x576fc241d5cea3b28630d96f29c8573ec4ad0ea568f388827bb27978b56d7c24130b2e6e43a35ea8741b14a7d51a0febf7cae0849fed1642abd6bc9af1d1b2ea8e8919562724a7335e144b41a2c575e0408b010b53a05c6cdbf5b1ffcb3086fe7aa2c83c7bd09dd6818588879c809c2bcfc575c31a7fea752bca5891efc92578	\\x13924b67df59cfc882e3fa4d4d0b0b892941d438ba5e4749708dfa6305e44d5bcbe41e7496b7c2b4437845859a7f71dadb4dc436916ddde0ecf39cf03cf21a91	\\x3a419086f0a77004d621b8934f6d9b436f5a332184a8efb41a0cefa241d4f34adad21f6e0a2cea713850a4fc4a3389cef5c08d236e91b51e7f47e784cdab530687d695e4c9a249a05c3b4cd5ccd76c60c06fbf6e21ccd62fbed4f1e8ae3859163774386192d5a645377bd68711582c1bfeb9c56db88053bc8e8e8439f092cc6e
\\x08f3e4657afdf519dfcb9de666cafdc3edd9249be6455fe1460575c248ba795a1689255984c239a47777051bb9b98033abd3095bf7ae1a104b49e3d5a42db921	8	\\x4975c4906394cf5165e32c4ee294da94fbd3de39da7afe330d1c6bff1915d5feed91c36c95dd2818c7ef2c3088f04d60c9ca13ea0a7ff72315058bd1d20c1107	\\x860a9106ae6eae432b56bd506c28c284de8de160911f8fe4f8d83c82a49d17cb19bb387e7d6e44ab6a96df96fd7eaa5f77180d52ef5b542d2ec7b50e7fcd7124	\\x03b9a2d7fcf4a7c70a2be5d0a740edf2ef7eea22e4cc7973f64d33fd80845f3308ec6e0b9645ddb2b4864329730be6cc71b5d57e06dbcc4f346ec3050569950ed27df53698a636c4f71db42041ae74199502ca369669e26ec3bdf0348f1d059f2fcced767e3ac74fc3e1cb74197cefed4ac7358f8dec2cda52edf000c49c8c86	\\xbf5730ea29c33ae4c5e00d1da20de5f8b12eba2b708298779d027e79897db13b1c4b1218e1490aeec150a0030eeba963ed27d71874c76ac42d495d5c6fd3675a	\\x90396ac5d8920f84872f033166a03c1a630cdaa7f243b990946c1d14672d26608f29dbdc0f64ab7233790df42dff63a263572f8f2c840a7c821a0c2d379f838286f8adcc6b70354bc302ceee3cc78766a2c94e1dcab9e54a7d67258bc295b28c18c19f6869a2e0b8e3c8891108d4f1e301cd9268ff6b2ee292bdfb32fae18d09
\\x08f3e4657afdf519dfcb9de666cafdc3edd9249be6455fe1460575c248ba795a1689255984c239a47777051bb9b98033abd3095bf7ae1a104b49e3d5a42db921	9	\\x8fd7a7becc3af659590cc0a34d65707432d36c64304e7ca5a998df162073b2b8558d7f4055192d256dee72f88ea0a8ff59b804bde23810457b6a31cfa7338807	\\x5cac576b6aa21e7df191af5ee270caf70a0ab3a64cf16006984a44dffa43d6021188fd63c00df4265316d9ff6f415f9e06f83f50996962da962309b78d445a42	\\x9007365a5588a2de3db0c2a3cf3279c859ab9edebabf9592d8d1905f44014de492373dccc98d2234e20693324e0252374993e8fefd1d1c42837ad3136adb19caf99db5037f950762b2c46d17b063156ce8b648e3b643a5147afc02dbea415bf4664325e3c1fa84b0c8935361572e7d9ad65ecf4d11febff208ae7f08f9a5811d	\\xf9ab1852bc39b4046c13b8e506e914cf0efe49c7fbd43d60de65659f2ef7581fbf4abef66854982be683bd5388479de2393e04d790fd9e1d0995f5ef58f9a10d	\\x2d9420781517cf526f4be9b9ea4eaa094cd2d97daf324804cd219e7f02e9cc103b16f71928bb08b98a65c95c3c88099432d9dda021ce93430a7a40f74df867ab5254daaebf2d777d3ce6114f8f33b5416b1640a1ec9ff74748d2c6fd344b54ef14459ab90cdc4f22fb9616f52dd89361c4a5e777c53b8a60215e18bdb48e80e7
\\x08f3e4657afdf519dfcb9de666cafdc3edd9249be6455fe1460575c248ba795a1689255984c239a47777051bb9b98033abd3095bf7ae1a104b49e3d5a42db921	10	\\x5f90b72a1e91d2d509d373ed1f3c4dea5609d0073d92b83459638f25ef270cf15dfae8244d820999fe1a4fdfd96e2e67eaf91dbfe5bf9650da1bea343b47a204	\\x5cac576b6aa21e7df191af5ee270caf70a0ab3a64cf16006984a44dffa43d6021188fd63c00df4265316d9ff6f415f9e06f83f50996962da962309b78d445a42	\\x6858b7df47410a2ac9037eb798ef6799dc399772c00ba7468ed7546712a8f400834c59694c73bcffc4612167e6c04575db2c2dcabf0dc7d8bb97163d85db25274828336250283ad8519ccdaa1755c399d31515ab6bb6959f3f6f4b6a72227ca8b49ed300480a0e4f7409e99844ed4d6ce32d5e3d1b70608e2caff69893c6531a	\\x1e84e895f1824c286dd055fea3d5ef000f059b0ac5cd60fe398d882664771b6cb44fd56c1b30471a1d78e01eafcfec9305532675c38da8029f1b65be9413c1aa	\\xa134f978ec837669899cf90d2276b48b8f6cee58642cc1d6a4ffef7406daf907da285974f0232ba6735c930814b2dccb834bcbfeb56a2c4eed9dd300c78f8ccd288a05cc3b76829f95aa38b8cf9621bf3fd55e633a7c0eec5aa37f0575f1b84db90f7053d1e4c1d163a23adc9ea45bfa024620fe334d6701559ce91831068c50
\\x08f3e4657afdf519dfcb9de666cafdc3edd9249be6455fe1460575c248ba795a1689255984c239a47777051bb9b98033abd3095bf7ae1a104b49e3d5a42db921	11	\\x4abbbbb30757b3e9c6d3fed93f6536db9557457102c035489a5ef75419958d1f241813c0ee573bf5ae26252311fb45285330fe863d40eafb66bfbbad31c88d00	\\x5cac576b6aa21e7df191af5ee270caf70a0ab3a64cf16006984a44dffa43d6021188fd63c00df4265316d9ff6f415f9e06f83f50996962da962309b78d445a42	\\x9ec80c1ba584cea78ecffae6c32c94928c888b0c7255be64a1babbc6233eb616251ea09d8ebc902e161fe1120fc1b814f37964908fa21c59310264e08910c2404ab02594a608357b42670cb6b2b073ba814a4615405e9fc6a07fd3c7bc68ee2ba1bd63f737f41360ecd3ce4673a7a1d4d1440033f7154c7f43407d5363d9799b	\\xf3b7d2e06c4176906fa6ce9f73cc76ef4000f1fc0f71f9be0ed9b56b501b4146499c6af94f34644bf17bebc8b299be8595c5b0ec3c18fe295d230d56c2791f91	\\xbda98d3ef349a3547fe2f5e5b8088f3697a6f3981d1934478ac250b572d7cf818817105790604a6abc70fd4ba7a2473c6b2213c44a12d8c4de92c382a0ed2ede82410c4794f52b8fd53b003521ba62c3d5095a53c8b1f1d5b6927b186cf02d1d7edb6a6b6078f67e8931daaba9b9ecdc0845146af89f11c4adec2af375fa2962
\\x11449f862dccaf4919d3fb810d6dcfee6fca68a377f7536a7305dbb1b13213260718f7a4b794b2276bf14c35f8960d980d6347ade552588344e12a68e9b51843	0	\\xb40c122cd53e43f274d94ef0826ee8559054f5483aa257ade472b933cdb8dcf6fb189794bb050c91f7ff67685f5965a17499f417422df27df25d677453fd620d	\\xf9dfec817b3e35ab7d322115daee9bbee46cb9e5e479590783b7f01428cb0cd7b4aebcbecf76b01fe2e5e625255881e33aab8ae03c683e243f15bbf0fa6e8863	\\x18e9ac5aed3182c8cad6c873514ef99f612dc05aac51c54b6244ac4fdb300553fb72b7df82942bce759ab943e41441188c0ef0996a35e5329eda00a50b71c52a04dd983a1e8743c4f03686ff1cfe03a54d9ca86ec4a45253bdf7b40bda44a6947e678c4cb80a7bf58f22f8ab8ec1d50cc8f4b39119342e1fbda5aca838f7a2f5	\\x1af8f5a37673039d712a8d45cc40256494e6ab869e4def427590e8f730a0312f85b5eee04a1c019432b47b30cba22932fc8908acf4e258e46c6c3a39ef654606	\\x944401fb452b253e430cf28003cc41b0c4839bbbae26d0d40a3b212b49a7baf746a62a1593b784d0d67b0862fdd8c1356d7e75daffd5a36f06aa9f17a6bed742773e674a58043bb2bbc4f887c34a9a20d8550e5d5db0dcb48734a7eb1d5da6b06c47b72e081276708fc10f697cbde6d293c0f5e9b57b7c70de4f26c88bfa0e87
\\x11449f862dccaf4919d3fb810d6dcfee6fca68a377f7536a7305dbb1b13213260718f7a4b794b2276bf14c35f8960d980d6347ade552588344e12a68e9b51843	1	\\x00f91c69294c47eea80f92dcde5c90e1afb22c893fed4b47787924864806765920fa20c75033b2af72d2a7cfc157d7291d6714dd2699d76a3600f413fea9dc03	\\x860a9106ae6eae432b56bd506c28c284de8de160911f8fe4f8d83c82a49d17cb19bb387e7d6e44ab6a96df96fd7eaa5f77180d52ef5b542d2ec7b50e7fcd7124	\\x7ee1416a7386d01116e0722d815d55a71caded1b23555cc6f369e99c277398f7bef6f488655ee95cfddee5fa0a257799ef72597104977a13792f701233a452d1dc58e4f91512b755c69e8e6fb7fccd95d71fa11db9032c68e308bac080654d7003c32c4d7f28ebcda673c63b31320586e5ded1858580e32d320dcdf16232fba4	\\x6e56e375aa76fb1384c90ff95f635e38baf4103ef822fd28f0402764de35164d50a28ed571f6bec058f9f64e6bc4a706bb34a4fa889cd0e7c25f707acce454da	\\x5daf7e6abe62b792216bc79ed882c09361a996bc778363b38287d4e3b7c14d16cc55b1e055033268123ec412aa03d057a2714090af392fc246c2d2a6a3e6aafb8edb7d9121f8b61f86be1c78dd110c6d0eab1bdd3bb5e947dd1aaf9a7b058ebb91ce2e697a313e29cdd1f44634e57a415619e694c87d95d2ec6def568e20edfa
\\x11449f862dccaf4919d3fb810d6dcfee6fca68a377f7536a7305dbb1b13213260718f7a4b794b2276bf14c35f8960d980d6347ade552588344e12a68e9b51843	2	\\x3bfa551e57a7592d19f58d60d1c517b237d304c8291d267fed0421dc06b81a81cb9ae4c973972f0af67cead596361db5400ced7c5e489360b121393949ed390c	\\x860a9106ae6eae432b56bd506c28c284de8de160911f8fe4f8d83c82a49d17cb19bb387e7d6e44ab6a96df96fd7eaa5f77180d52ef5b542d2ec7b50e7fcd7124	\\x8acd26026e775a11cae5fc50c44c51c30ac08937317b2bbe2a24d479820344a5d4b2f7b013fd1c570c3b6ad4b643413193a27cc53c2f425c558a5298cd997e86dbf6bdcf527d83f668203276a94a0d48a35fcbca53435330d3f92d175fc1fdbf9955716c94f0ae2329088d83e004314947b570cd391441a205b94d26ba5a61c3	\\x8040973aad52d8d3698147b7e43cc64c3913a9e15c30f38e8068cc53f65aabff389d94697eaea4b825c77d3c59f4498338eda98ac2f54dd62293c977f13c1b2c	\\x6d9763117640ad2ef3e01a7d4b8cc6a40c2002d8788a3c073d621f23069c3ec9bcddd51c950cb83e7d8cfc6dfd1f945404ddc2c1c5a9346181b466cebc052bc74bbe00e5c2b1610b12d02e3758613c658e9889f3630c77c32ffac72be337767da9dc5f76ba0dbf62b828678d126db51f80a22934e88ee269c95cbdfc0d371770
\\x11449f862dccaf4919d3fb810d6dcfee6fca68a377f7536a7305dbb1b13213260718f7a4b794b2276bf14c35f8960d980d6347ade552588344e12a68e9b51843	3	\\x3835486211c253e617bfcf787fd7cb81c690a69647e3d0829f87a3f9e8a0771c4916456aa29496b71eb1fe141c8dee17f8ebf8043d142995a1dfef55c88e0208	\\x860a9106ae6eae432b56bd506c28c284de8de160911f8fe4f8d83c82a49d17cb19bb387e7d6e44ab6a96df96fd7eaa5f77180d52ef5b542d2ec7b50e7fcd7124	\\x3c7187223401b74b8847cd2003d0becb2e573a498e2b09dee69fbe269b0f1edc66315ce3dbe5b8057d29b7c85d3a950fe0e631c24cb36171386bf87b420640a10becafa3294ec6f7c2d74f4bbb3d2a537d2086987ee75558c51b36253697b60e427f3498c2f3ba60680892d2a716487ef47eae5f349f12ba87afde55827f670c	\\xf3c16da37e16c385dec8cc700f478ad2ef0900ce5570034d70cd82244a4168428974ee8216238e7ad5dff5e07343084d2fb5fdf18f4cd70dff03a97279f604b8	\\x01090ab7e8d419c476ea792b402698fa580ae987d1b953743fbe989c1ae14e682b8211adb87cce1278b9fad0e43175fbbac392767aed7f99dae9fee3518fcd4a268bd238c6d5ae193ce08946281b80cf2b3fc69b43206d10016f24a1dceda85b52c807b9e1cc714ce2fe63c7c8e5183626f960c95bf0ef529c7108fd60580b61
\\x11449f862dccaf4919d3fb810d6dcfee6fca68a377f7536a7305dbb1b13213260718f7a4b794b2276bf14c35f8960d980d6347ade552588344e12a68e9b51843	4	\\xeeb0c2d8574e1416ac83e03c7277e3bb0e9905f73e9e49477e92c14dc68465426ddce340f2f00e42814a70481901e1e9362a8b9fd1a7f19227f25bef30a4c70e	\\x860a9106ae6eae432b56bd506c28c284de8de160911f8fe4f8d83c82a49d17cb19bb387e7d6e44ab6a96df96fd7eaa5f77180d52ef5b542d2ec7b50e7fcd7124	\\x6b191fe552943befabc5a15b0c11260f33233f3911209483f7dd74862b6983154540c7eb939f5d715fa51ced4201707640b8e1df6c55954b2adbedf1ed024dcd642eccf0f1cf54fe434fe150acc66bad426146fe26bf2f8302bae281b644090d3575df08f07d6583396001dc05ed38ddb0b3fa88593c8bb5532db9e4c4730978	\\x972cfccccca5b06d3e3ce4fde0797dbc5b6339516bdced657ec777f46388a0705643ffb4db5fa981e6dea6fe58b9d9144a115488f2c7737efbaea74a8af8659a	\\x045c582bee55ee0e4ed71b378d18f784065e908491868d5fd96e6818f6e07bb43d5db8484ba474aafee4722e699f28f0ad204f90bf81be8940a12878562b9c2a39dd3d16037b5e04ec112bd65e91803870b0940bc112f5eb30dff4ac8be6066c0fa49f88b0988afdbe714b956986a9c8d88041040e423053992c6c36058d1304
\\x11449f862dccaf4919d3fb810d6dcfee6fca68a377f7536a7305dbb1b13213260718f7a4b794b2276bf14c35f8960d980d6347ade552588344e12a68e9b51843	5	\\x6fe2f7431ee99e254ca36d86b58e4a18b88960070f2b3c288e7bf74ffe81465f235850b319a8835f111278792ed8d663ae43bd507c33f29f5110dd2f4f2ae800	\\x860a9106ae6eae432b56bd506c28c284de8de160911f8fe4f8d83c82a49d17cb19bb387e7d6e44ab6a96df96fd7eaa5f77180d52ef5b542d2ec7b50e7fcd7124	\\xa75941146c159c6307103930422bad071c82ea16da5a46c622f985022346568f325bc30f272ac4c60bd967afc9e5270e6062bbc7ceab1e14b5d0e6d2e84922d31972a258e7d05b1f68bf897e939b8690fd4e94971595533e4f191fcb88af185f095c2bd9e70f99de25ca891e68ff15d628bf594dcecc5f945e325e44fd155821	\\x2e62d9acae3e4d1a4f2d99d2008546c786afbd29cf59eeaafbae35ef6fdc4cfc89acb3ca6101ef6a9cc803d7e1eb8a64084f4a1aa957d584b9d6b425ef7dc260	\\x4af5ab79c591374834732e2743d1a2372b5b667587001c53549b5a17c3c75e97de4c66548f0c0dea30bf4ae36967821b058738dc493d655a530377782bbe74934f6cd2e4658388de9aa2140a5696453ede845986247f839dc41b406026942a03df101fef430b33b30b2b513ea0f533b95383e2e3fa6fd0b886dadb58600e8f19
\\x11449f862dccaf4919d3fb810d6dcfee6fca68a377f7536a7305dbb1b13213260718f7a4b794b2276bf14c35f8960d980d6347ade552588344e12a68e9b51843	6	\\x16123f8cc3d6488e5895876ba98a0e420d53a04a3e4ae8a69e97cc90a996c99980b72201c437e1436f00d84a7fb55ead94ac1e7c176ce8a8a3087d75a9d30a05	\\x860a9106ae6eae432b56bd506c28c284de8de160911f8fe4f8d83c82a49d17cb19bb387e7d6e44ab6a96df96fd7eaa5f77180d52ef5b542d2ec7b50e7fcd7124	\\x973467d007a09da9b91d756606eec33d895f8eba1b9ac3ad26a782b211c47ab57e5e315cc0d5e58cdd5c56d231be3f44282cba278fa68325f71bbdbd93e5f7773af3f4cf7019f88e237b52afa6fbb4fae1d773229804607eb4c27046b4b058f95b9ea17a7cbacac9141648c83480dc1bebae21587b6a0c71f7bfecab6fea64d8	\\x212595ee69463c66cfe18df53c6e19c630e530217dac0e17fc493fc1967f12ccfa87db7199d554bd6dedf2a0ad9e33340d6f597791f3c6ca53b01253604e3b1f	\\x1f0b174f5deca1968d7168c6dff3147f8193f6669f362a6aa94f366ec9c35e29d784132136b304aa70f52a7e4505cb3cab3e271e0abb997a138db71b0297ec10e0b59fc128858eee5214be5e38b2b1dd7c495869211421f4e38d9551365b709635a20af6df003ad5359c0efe21fa34cd9de52915e94970d4792ff90bd428a0c9
\\x11449f862dccaf4919d3fb810d6dcfee6fca68a377f7536a7305dbb1b13213260718f7a4b794b2276bf14c35f8960d980d6347ade552588344e12a68e9b51843	7	\\x6c266758caccb2f337a78e2083d6e7732acbe4cf0330afab3d90cfa3787eaeeb8f76b2850926a3b6d71b6a1402095640e309fd997cd2cadb801acd1d6580c60b	\\x860a9106ae6eae432b56bd506c28c284de8de160911f8fe4f8d83c82a49d17cb19bb387e7d6e44ab6a96df96fd7eaa5f77180d52ef5b542d2ec7b50e7fcd7124	\\x76b502e988c93c5ee4ea5b37492f80287b7731e636c8bd03ba077941992b20b0c3ad9c2047097c4513360d9843de032cf61cc26fc6e0894b785b2b942665f9b638ec579251edf2c66c66881172b1318344b613effaa0ee0631c54682be7bdd028bcc8d861b726efcc072a4ac7e104f1b531039fff4000cfe446b25e71eda09ec	\\xdfc181c8d4b3156c9232c84c703292d0085b7c77edb76d9da2223c707451bd9c458d88d4de6d351d3287c5f4c3324f0c68bfe1b07accefa5e6f0bd084eff79dc	\\x16b1f0d98e70204b5eea59631d8d5895cc10a639cb58677134c9b8847e6e7e5ae60c26ac198253a133feacc3d8d86263d191c1b8e4bacc04bf416a40f06f18fdfaae94a2c4a8032f91a6a6df7b71cd9dbfcb4092362bf577ee55b7b3e7203d15e3d69ffed27c28fd311ec223e8dc2dc4562cf3408e35c0f3426a7f11d622e9c5
\\x11449f862dccaf4919d3fb810d6dcfee6fca68a377f7536a7305dbb1b13213260718f7a4b794b2276bf14c35f8960d980d6347ade552588344e12a68e9b51843	8	\\xcefab3a67533e3e99c982b1396cf6e80d66d36faff8ec4ae8ccfcd95e65f38a91b2e2182f5e704471f2735a95d18f3eadd05a060ac5cc4c0ab84bca85f850d02	\\x860a9106ae6eae432b56bd506c28c284de8de160911f8fe4f8d83c82a49d17cb19bb387e7d6e44ab6a96df96fd7eaa5f77180d52ef5b542d2ec7b50e7fcd7124	\\xa22bf2de48c702874868ba68f58b8fcfc429d2d5e8709b4c4da0f31a57b97b42345aebfe18549703b75ed166feea35e5b3621f066251f4d03001403a6ecf903c30f639a8bf472a54e417e74b11dd86fc42c9fac0f0774e7a753f1482e8e7ac68e975cf94dc6db1477ec3e203f5d110669d47185f2c26c12359661e35baf1c8a9	\\x91547ddab73ca2448f9abc352507ac7d0fec45aa50ed52899e2651b0fd93f17da568c9b945fe6c698ffcd793db717da4f95af1f0e93e5f57d0aa219210c5e7be	\\x78c2f6b9be79b4360d5f9226d7065d768f9bf1057a615ec3e03fbae2e244a008e0eeb946457ce3751db257ec1b705e09dd311b5dc100012d7d65e762e1d84d7b9a67dfe33a90656e4e8fa9418f76d3fa700ebebd38065ec5cc31b5023278fb95937638fe5f85674c025ce70a31b1f8bf5fd6c04efe7f87548fdc6a7df4d9f8a9
\\x11449f862dccaf4919d3fb810d6dcfee6fca68a377f7536a7305dbb1b13213260718f7a4b794b2276bf14c35f8960d980d6347ade552588344e12a68e9b51843	9	\\x0b4e84d295a8f687fec6a10740691124f98632519a476a791cbdec99089b51d0eb604be99cc2fc0760289cd05e96c8d3c2997a397109caa62b5d8bc3bff8a800	\\x5cac576b6aa21e7df191af5ee270caf70a0ab3a64cf16006984a44dffa43d6021188fd63c00df4265316d9ff6f415f9e06f83f50996962da962309b78d445a42	\\x51478366423ebd8882751aa38f6f31115f6e37cf8c268c2d0e20360a8212bf23f800cd41dcf00bdfe1d655e311c3441400ec93d02433b97ee4a6651f9873adaaad81f99a12b2663ca8a0638caa09f80bf03a293d613327fb288af18b1bd8d631a7ed9e447362ff7d8c06244f7b876cd174e3dc4d68df38d8bae8dba2b1a84ac8	\\xf6e4713a2c150d362b68909458c331462966cc3e567eba58c40c6cd962609aa8a48249fb46ded86041feba30194f271f328acd4464f0fbe9492d41564a550737	\\x39e2995e140b6a57a76f0928594c9a2084b0b503609fa6bf42b15f1f4b92674a7488fc1e58d76b419adac4e7378fce60d7c4513932d9f860e2d8fe03ce30aa3a94f35803816e60365ce87cb2fabcc8804d3c15e15867b1d41f3af1388805cb3fd5c662b08c65560f7bbf20164842bfdcb10dabe7afd7b880b656aa5ab76052ff
\\x11449f862dccaf4919d3fb810d6dcfee6fca68a377f7536a7305dbb1b13213260718f7a4b794b2276bf14c35f8960d980d6347ade552588344e12a68e9b51843	10	\\x3ab1ae25c75af4c0c774effc3294ddeb77df4cbc06d39b9ea0a18f7f95c91dc2b6f14f165249ac8f532c5577809b054eb443f87f42867223e0c0347a659e520e	\\x5cac576b6aa21e7df191af5ee270caf70a0ab3a64cf16006984a44dffa43d6021188fd63c00df4265316d9ff6f415f9e06f83f50996962da962309b78d445a42	\\x3699f61f4321115d5c04d4b333f9540e18e77cbfe70493b06dc656b1719758a6613dbf891b6ff8abef1b2d2e57ef46013cdf5091d9844083de02e50f377b2ece3cd0a33e3687e17729b30d57a5fdee6e3f15e16cf1ead48ca591032b21524b204367cf3708e98dd294049a5f0df68499b783895fcaaae0901b0a000e32ccb1b1	\\x694a9ee7454f4d229bb8cda8b3b3aaa876cbc95280b5c763130847fbfe0b76a8a544d523c09d3c08563d6df4d643f778211894bf57188dad51f15054ec820acd	\\x5a3a88aafd708b811220526dd266ac80a70ea357ca1556f85cfab86a387544c7135e27259b019bced4ebd3c1672cc581a8c4ee612a9a0b8559902f4a1fde2b84328dc66eb92a0ee5616363f1717898ee0aeebfdf69ff9e366c16ca8335c5de9903c9cdbc1d30114d775044aec69d57bf4bd6df57a723889195e98db56f274590
\\x11449f862dccaf4919d3fb810d6dcfee6fca68a377f7536a7305dbb1b13213260718f7a4b794b2276bf14c35f8960d980d6347ade552588344e12a68e9b51843	11	\\x4b19270cd9a0edb0e28ac2ed35f1acb4516a1692bdb2673caf53bf12f0ed24767887e1dfdcb9a7cddc6c2045a0027c03f0a0e56ef0fe8a00e66e787d97f9d206	\\x5cac576b6aa21e7df191af5ee270caf70a0ab3a64cf16006984a44dffa43d6021188fd63c00df4265316d9ff6f415f9e06f83f50996962da962309b78d445a42	\\xcaedb39cdf065333a1f5794331319d7a6df10da9c696be612db467788ad015d25596a3a5d8afacff7e19bc70466c0f0c4e9b0901b687ee597a2c548182d297d93a4e6b660566613c8aff3655b799e268f48157cf0057e04fff42002201982cc7f3fab3621be2a4272c10ea85a14b126238c3a05bb0ae0bd35b6f2cc18a0714be	\\xcbceee789a1198a33036e89cfdb6aa10dc8a53eb4ed7837a654bdc39cac4f73509350e5a51603e11ecc21c23cb1bd11c190ef47945888f05796a4e8871786358	\\x4c13425fa8c789c986a477c89ff2e7450a342d9a76d9a40ce1518042f13fa50d45a2d7562da8628c17f0e578b7dfc664b5ac0acd0124033345ec339efc412043beea0b1f93640a6edb09f1ab2451108d607675dcb0a206d4e8e72b04f56554cf82fa3591b4da1811f9d9f9d6b105884cf68726bf5a3e1c80eeb291e20abfaee9
\.


--
-- Data for Name: refresh_transfer_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys (rc, transfer_pub, transfer_privs) FROM stdin;
\\xf850ac718b33c75f5cdccb172321b141e988ef48213b463b6d710b2a665d42bdd715406ddc1ed7c9ac2f7065b86f9e28151c1b27b226974ecb1abae232a10f70	\\x4f848752b2b732519378ea2de27b5bfae0bc4459f5d0dff7ec2861577e224847	\\xd33a5a5c7911530ad94a641ab8e82733a1311d533f2b86b47b4b770fd7405018a3bd421ce6a96ec19dd43b041d3c0e97caeae10775555b12483f215583381c42
\\x9727634c5de3910b555611be443329df71fea28cb7eb8774ba6b6fd87a27b930ed5f72e9eacd0667297d502ac29d7673b89ba6a26cf3b0b68b97ace0b9eb0667	\\x126199a2ba3083a9a27851046645a66c1b85fdaf1e6d178ec47b65b00efbc506	\\x0b0100500140913e5400820b2a9cf0d3b50a094dc049a4dfbdf5eb3058f5b9e80fe771c4e6bbdd201cb7889659fff05ac1d7139196434f99bbac6d3f533b9fea
\\x08f3e4657afdf519dfcb9de666cafdc3edd9249be6455fe1460575c248ba795a1689255984c239a47777051bb9b98033abd3095bf7ae1a104b49e3d5a42db921	\\x2e30977c69cb9a4ece6bc9a93fb689cc7cceaafb45391a9f44c972bdf6a4943b	\\x9f642ce8ce32fdb9a131b75a27c68553955b7ff0eddea584e6ea37ba332f84a7772b73073ca354930a583e4b5ca880023cdcc9b52781dccbbc9cdaca9753d1f3
\\x11449f862dccaf4919d3fb810d6dcfee6fca68a377f7536a7305dbb1b13213260718f7a4b794b2276bf14c35f8960d980d6347ade552588344e12a68e9b51843	\\x8e6305713ef7aaaee444c7ad7a74fcfe4738ea211a77ce120a0ed3950980941f	\\xc01b10aa30fa4ee375a7acd9ae09427aa59e1dbf82ca36743d0d714d232aeab0dda9f4c5bf2e78b5b402011dbe01e422ea4f34aedc89947fc9c6deaa5504fe27
\.


--
-- Data for Name: refunds; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refunds (refund_serial_id, coin_pub, merchant_pub, merchant_sig, h_contract_terms, rtransaction_id, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\xda33a7cd13f692fc76ad87e8e782e9df0b2e3b4e934948d16305f75baf804f4d	\\x896d7fa121a8117390e6185912bd64f5690f19bd152abcaee4d3a4ec900e5c86	\\xaef74dc1a2f0bb119d6a83019b7a856d42594081274be3dc3a0d2b6086468198d5e2dbcf1319aa3e712520d75e79bdcafe3166af67872d3fe32d6f64760a840d	\\x3b6b416a657d6e0d6e92df9ce66269ad470f3228650890cf54c09f991312df6960455006025ebda42d2148886fae65b82d6871912080946c3da838f974dc6df1	1	6	0
\.


--
-- Data for Name: reserves; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves (reserve_pub, account_details, current_balance_val, current_balance_frac, expiration_date, gc_date) FROM stdin;
\\x769eb440a0bd2b6f303e3e8f406b0b9cfbda779662708eac98a0742ed7befcbb	payto://x-taler-bank/localhost/testuser-r4sQVX1K	0	1000000	1580166018000000	1798498819000000
\\xb360ed05a31a998fd66b2bbd8a009f02567a34152e175aed821e39a97a67eff2	payto://x-taler-bank/localhost/testuser-ChSYta0L	0	1000000	1580166021000000	1798498821000000
\.


--
-- Data for Name: reserves_close; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_close (close_uuid, reserve_pub, execution_date, wtid, receiver_account, amount_val, amount_frac, closing_fee_val, closing_fee_frac) FROM stdin;
\.


--
-- Data for Name: reserves_in; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_in (reserve_in_serial_id, reserve_pub, wire_reference, credit_val, credit_frac, sender_account_details, exchange_account_section, execution_date) FROM stdin;
1	\\x769eb440a0bd2b6f303e3e8f406b0b9cfbda779662708eac98a0742ed7befcbb	2	10	0	payto://x-taler-bank/localhost/testuser-r4sQVX1K	exchange-account-1	1577746818000000
2	\\xb360ed05a31a998fd66b2bbd8a009f02567a34152e175aed821e39a97a67eff2	4	18	0	payto://x-taler-bank/localhost/testuser-ChSYta0L	exchange-account-1	1577746821000000
\.


--
-- Data for Name: reserves_out; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out (reserve_out_serial_id, h_blind_ev, denom_pub_hash, denom_sig, reserve_pub, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\xb37560896e5a962221c97c1113c151683c29d2039985edbda42cd7ce7caf60c23e353a179feba45c9b139d7c55595d9519913d6e0b1463321a09572ab780f72a	\\x48ede06403d2291b9939254ae67eda84a35990a55b53dde5aa77b4e621b3b69a922b26d045cc080913b1754afb7081caaec25ae4c0bdf86c83304faee0ed2c68	\\x6964b3802d4313f77fae4b9f706478897308113dbe92c6559270743ce5536fe93c696bc9106adee2251274b918e3a89394da696be35d40d00a48fefeabff6787472f3f98021cefe518ea29c8d70f548e2e23a987314b086d32869b2fd50de0a82d245fab95d65688f57ff327de47651e4c9c03842aa9337fc2f7b3272e195f04	\\x769eb440a0bd2b6f303e3e8f406b0b9cfbda779662708eac98a0742ed7befcbb	\\x872b2796d684283e752c32e547bfae984e6ccdc1574e374e314468f064aedf4ed3d1acae7f35d7ec296f51e3fb9ff023b28836be3c32b5f8183e26bc01624e06	1577746819000000	8	5000000
2	\\xfb261580d854411ffe9ab34d1dc35646a6aa1c3c6a6ef2ed79bf4ff62e62d9f2de014d276280e0da79d0d44d378dbea2d0d61cd3bbe87b5b79623552cfde427f	\\x860a9106ae6eae432b56bd506c28c284de8de160911f8fe4f8d83c82a49d17cb19bb387e7d6e44ab6a96df96fd7eaa5f77180d52ef5b542d2ec7b50e7fcd7124	\\xaefd7c989f7b9a7669132bbaa6e3d43e60e8a45396cb7622c8425703b8388c1921b0a569d9b72e32decd89feab4985c6c497b46691e6c14d6cf6b1cb9be25cfe01af1771624baad4843c683065eca7dc7d11f9bb6a50d8c827aa61fb8d9eee71b6959e70f66c0291671f003ad7211a9d4e9c4262973dd3182e66010e09144d4a	\\x769eb440a0bd2b6f303e3e8f406b0b9cfbda779662708eac98a0742ed7befcbb	\\xd6472cc27a9a0cb05c35a0ba0a2a9be52a4d104083d52fb62bed6c55ea3d095f62d14d93cb826abcc8772195cac6c5f07077d7f4c1630d1ed28f59af52da390f	1577746819000000	0	11000000
3	\\xdbc84c7a80886a5a46d97f79a86ee0afd2f8e80fcf7226cb2d7da78ca4820c33a941d565025b9cdf83bb1118507b377b7daa54d621ac6fa22321c1b3a7f67ad0	\\x5cac576b6aa21e7df191af5ee270caf70a0ab3a64cf16006984a44dffa43d6021188fd63c00df4265316d9ff6f415f9e06f83f50996962da962309b78d445a42	\\x03430097b9d279da85826ca39f513bc293660ef95156a1e0eb5f2ae96436ebd5b2daebea81fa3df6af0227fc35dc3a8153ab562fb85f779a681358070e9fb4c21957394f396ab33a1a326e726a299c630f1745561a4a15134d48eb182843ed853c7256aa7368f8e2819bb778c175b3e31162c763eb1b7d0de8aae1aa4a1b8ecb	\\x769eb440a0bd2b6f303e3e8f406b0b9cfbda779662708eac98a0742ed7befcbb	\\xb9800c7032af347bb85b21946b32e3965cd46cbdafe849602adab0d771204c49333903641d15026dc134ad0254e12d5600748e170e75350b4cad88085ebba806	1577746819000000	0	2000000
4	\\x63b4f565176204f3b1cd13ad30eb5ae5cda02c734a29682bb31a18b3110e3bb880a750f5a1d84ffbc1393160a395cca78089d8fbf0aefd4913511a6905098641	\\xf9dfec817b3e35ab7d322115daee9bbee46cb9e5e479590783b7f01428cb0cd7b4aebcbecf76b01fe2e5e625255881e33aab8ae03c683e243f15bbf0fa6e8863	\\x4cf1d7e23fc5bcafca856606e05ee1e3767845fc305eeb641a44f7f1d56d9c3dd6cee48ea21016742bf646e8d1110dfe530a74973b47c9fb890f65e23650e14d03753dfbe4a23cc06fc5e52df53027e7e5c53fc3dfd2ddf604338a82563683287646ad969c1b045915cfd2dd3efbb0b3ae886bb3cc9f98bd0dcd8a7339f0243a	\\x769eb440a0bd2b6f303e3e8f406b0b9cfbda779662708eac98a0742ed7befcbb	\\x3ff0ebcc06b2b8c68a29582142516c66ced122a13b24fe48a322e23f61c6d289307ca2e596b6e41ccd84c3df9f27ebf5253e8ffb60f369c9bc58f78a2bbecc07	1577746819000000	1	2000000
5	\\xb34364ec3bfa43d4e7db932b141bc7c3147537964ef849715f515626d48b563b16f2aa29e136ad4c421adc24272319771a221ee1b229d94751433dfe48320ee3	\\x860a9106ae6eae432b56bd506c28c284de8de160911f8fe4f8d83c82a49d17cb19bb387e7d6e44ab6a96df96fd7eaa5f77180d52ef5b542d2ec7b50e7fcd7124	\\xb2f450d6bd1b18c695cf059750ccd458170c8875ad2669279c592937ae352c1997f749bf497e2d4a9b3ea8906b0d1620643e5fef8a0fd38cb6e721cc2915b1843766175af8ddb8fd565bdb5153e40edbf5bace4bf68e773f22d8fc2346454fca008843ffbbe470d671e5b11415f3bdfe19dbafbed780d5479aeb8606303fdaa4	\\x769eb440a0bd2b6f303e3e8f406b0b9cfbda779662708eac98a0742ed7befcbb	\\xdd667fb418a37886ef1377cc1abc84ac12a1fdcf4ac6b1088c52c4c0e8eeeac313b8ce92e0bc92338a9968f3e6e44616edb3d4d0f30c5044fbaa54411dcfbe0d	1577746819000000	0	11000000
6	\\xa6317d080dd60e919711a5a07120cb9fda80850bf7e1bc034e84161bc1d13d0b644e78aad57c485d0dd0ef51aa5d00d1e9313f67c6b6b15332e5519a4fe02e4b	\\x860a9106ae6eae432b56bd506c28c284de8de160911f8fe4f8d83c82a49d17cb19bb387e7d6e44ab6a96df96fd7eaa5f77180d52ef5b542d2ec7b50e7fcd7124	\\x48cd42eb78607736a7fcab577c45492f14b783e4e2c0988991f1128e2d32e17c993d1502fb30d622c8324bfc875155679d2b585ccdb599230fef0943ebd817742b42dd7ace1f6b761e75944d7987a9b9cb8113baca80009da7842d3ad90ab40122b8a6f0224b32b7fa81d506dc8aeeb2c19a4e8e239c4e9d855ffbbc1875d8ca	\\x769eb440a0bd2b6f303e3e8f406b0b9cfbda779662708eac98a0742ed7befcbb	\\xbeb5e34d8408b25cc6e8bbb178ce11ee0a9cbb85d1a4192261e835d5262e30f6ac40ac0a9277131736a3e59eaaa28d2efe9128ac64178132a4fae93c75357301	1577746819000000	0	11000000
7	\\x280811ee890717b1a88c516369f75ebe39cf5564cc635e670ee945caa694fa3e6eb69c42a33f49df9581a3e79b6331775e08cb56bdbea9916f2fbfbba63c6a4c	\\x860a9106ae6eae432b56bd506c28c284de8de160911f8fe4f8d83c82a49d17cb19bb387e7d6e44ab6a96df96fd7eaa5f77180d52ef5b542d2ec7b50e7fcd7124	\\x5b25846adb78193655c9d9222f4111c652dcbed97155e6f26389ae857255bdfdca7737cd0968fbebeb99d163834619e5e806010cd5b8ecbc400c5ff2d4446ed5aa280ae2829bf4f70edaab29ffe569de7c3357e1f99979470bc8fce352d45df1ac7b804b1c9ace1b9301b4a237ea20112f14c30099294f763d36c53ad07e312a	\\x769eb440a0bd2b6f303e3e8f406b0b9cfbda779662708eac98a0742ed7befcbb	\\x099bef96019cff82cf04a0a7fcb6867de6ea700bae162dcef559761757bf81b06ec7152ea5152d392771b5fb080da1d721a5e14f20db4f237f24a5388c99e30a	1577746819000000	0	11000000
8	\\x8c742bfc44da403633066d485b6588eecceab84d9b32b97382a95c09efb1388d550cd4915c024f5fa4d5ee55ba87a3d7801240ea8e1e3d33ef61e0b32912cb8f	\\x860a9106ae6eae432b56bd506c28c284de8de160911f8fe4f8d83c82a49d17cb19bb387e7d6e44ab6a96df96fd7eaa5f77180d52ef5b542d2ec7b50e7fcd7124	\\x84e8166bdd84c27ad6244efb2cc944d2c6401523b110cfad77a2e5b9a8e56fabfee6bd99a3ef197eb05fe0d2758b778a9cd08a5cba9d540e23601d18edd6506983e165a9f0351afd2a11fa8bf9ba0ce395042ffe9721dcbe9fedd685200fd2db22cec6fd5a56ebc6bb1b23212d62f7897b46eea3167bd8566639002237c7955e	\\x769eb440a0bd2b6f303e3e8f406b0b9cfbda779662708eac98a0742ed7befcbb	\\xd5479fbb687ca3989f327321a64fecdb990b53aa7aef200445cc2a61f7ba0c9d082b29c3f9c7e33d289a19ba085e0a83db5e16ee766eac67a38092cba870b207	1577746819000000	0	11000000
9	\\x6dff7268f6e74f098f26514d4fa6b2cd7a4da966d0b6c9072a6cbea0f016406d2b171eb2f9371490543e9e4a579203826e71dcf7e6adfd54ba7a43dae318bf64	\\x5cac576b6aa21e7df191af5ee270caf70a0ab3a64cf16006984a44dffa43d6021188fd63c00df4265316d9ff6f415f9e06f83f50996962da962309b78d445a42	\\xa37cdec4501f23ff4679bb5b56a2cc64614555bdac0fc9943ddfbe72e6c2f7ea79fc29656f595d8a194485dc1cf9328ecd0abc0d828ed60a649feec2379fe30ad435fefe8a96f4483f5d3fc2b66d135004bc109035d7e866da167485befe45a94e0965578fd44fdd95703170c7c3791b61ac10772106d89f276f67f5e527bac4	\\x769eb440a0bd2b6f303e3e8f406b0b9cfbda779662708eac98a0742ed7befcbb	\\x73a5e69bc8f07dd4c7f91c5299ac056baa5f4db9d1e441e36c1d471416b49d4d356a6cf5f6a0889a2eea912c3539e1c182e01b177bc0b0928ad0201314819505	1577746819000000	0	2000000
10	\\xfa631a1926c189ad3ac73310814ed97a37964e452c301c82fa2ccbdb5e9757755202121b64cc146dbe72c9ef409e9bf65bf7c0bdebc7aa50bfce6e3d2eb74cbb	\\x860a9106ae6eae432b56bd506c28c284de8de160911f8fe4f8d83c82a49d17cb19bb387e7d6e44ab6a96df96fd7eaa5f77180d52ef5b542d2ec7b50e7fcd7124	\\x56adc84cba8e1f09bf5c411b13c8a60b291e59268e39a2f04b4544f43b1a3dbfd749ee3add0f5a7d4198a1b9654780a8347773bc3270761cee738f523e513a3b6bdfb80302bc33a205bfa7c6166ca08c75916b55365cbeb235580c30418bbcf7510af6f4264c20f1a38ed3180eb56e5396d0556707671737b5e052c8dd31fa4c	\\x769eb440a0bd2b6f303e3e8f406b0b9cfbda779662708eac98a0742ed7befcbb	\\x4f2597bcac8c77e3138ddd20f493af7692cab1a7266195f0db00e7cae200d4cac0877f3aefbf613c482427f96163f4790911ee97374168ac9d3192c794f7aa09	1577746819000000	0	11000000
11	\\xd3404a839e824e5816e6dd9918050f1c907687f078de382debc778e8e334f66361a70d3bd6015bdc41bcd244ca193c53d35e98cdf59bc783b9a949243a886a0f	\\x860a9106ae6eae432b56bd506c28c284de8de160911f8fe4f8d83c82a49d17cb19bb387e7d6e44ab6a96df96fd7eaa5f77180d52ef5b542d2ec7b50e7fcd7124	\\x7d2ca8acecac3c90eb31b41567d9c4efeb0652b237f031356c86ccaf6f37fcf5815f0afdb92156ae56272e84f2c143374dd1824b0bdeb6f50b3a47c88868f5c91036369297237fd5ab2fa684b93b6154e7bdf6fa453eb55ae45b52f6be2ef4daa6c870a2233b5821975d1b36d31a85ed608750b44fa43ef72c4f253351117d	\\x769eb440a0bd2b6f303e3e8f406b0b9cfbda779662708eac98a0742ed7befcbb	\\xd3b561a5991973cbbc36bd3f6b7de3efcc7fe9eaae3f5cddae92fb4f195e86f8a01d0b945a0798b1a5c7ab314852f095d18ea8c2cbe8fa8f23da56a54bfb470d	1577746819000000	0	11000000
12	\\x5c8d3ca7349501d59204b067d2ee90311c8c03c0674b90dc0f8961b8071ef57e76367ac6516e149f74aff33f99ddfc855b19bb1bb925b004e88afcf9993300c0	\\x860a9106ae6eae432b56bd506c28c284de8de160911f8fe4f8d83c82a49d17cb19bb387e7d6e44ab6a96df96fd7eaa5f77180d52ef5b542d2ec7b50e7fcd7124	\\x7456977926f78ed32617aca1c2fcb38c0043f29392358e664d25456e5d55bb3aa24752f87efc0b1644d906fec7034cbdf3bf6d82bb75a2f2f66e3b29e6839f704092c903b05e4215a577d14d353ca9fa75c7495c832a89c7e01f79f6dbb65d8f35501568be88c501bbcf2b1c94084af91bd94add2dcde290ab9657eb80057e76	\\x769eb440a0bd2b6f303e3e8f406b0b9cfbda779662708eac98a0742ed7befcbb	\\x5e80536ad2995682854e6e4ac11ea73aee4d09c0acd785656c219ba3ca76b2e96e203641b70b6c26b949595d3bfb8b45842a55347aedb25a6ea79a041263230b	1577746819000000	0	11000000
13	\\xb181915c35e7b592cbd32b7ce674cb8d21999be357b5a59f1ad346403e59be90ff151974dfd71bc2b92297301bcbecda98b93fd150503d1918b8e9481cd904e3	\\x7a64d9869f5495eef73d5af56b8dea3b1117257de7ac63509ecd2fb32c27f511505ebc8ea49b81b91535feeb0af9ff1cf65588cc7d1be71260809aab29a7cec5	\\xa67cae191159137b4445ba3ea5500d0c19c6b971914cd3af05d582e931c99d8e8eec73c47fc2cbdca16b203c3922eb58a6aa62cc7f32d7a781070b1b114a86e76ffdb1ce44164e67e2229a45b77f43c162155db028d9ba6c08e38c3b63863f9dc74d56c08d4ce0d129887a15af868967f049948d4163600e5a1db168e3f065ac	\\xb360ed05a31a998fd66b2bbd8a009f02567a34152e175aed821e39a97a67eff2	\\xb6c7c2da95eb13dc780fb67d23b7d5d54fbbf5fec4cc53d8789e9e1f8bf0e6e884c2b56c923b89ac233b09c6780636f9aced5fce22f1abc434cabc151a2cb406	1577746821000000	2	3000000
14	\\x9f325d5875ad98c91e74ecb5b3743894169cdf6041288fbd2fb03cd948fee437db480de21c93caf0949ad25ef376403c9a4b02b6324e5a84e9946984a6953c51	\\x860a9106ae6eae432b56bd506c28c284de8de160911f8fe4f8d83c82a49d17cb19bb387e7d6e44ab6a96df96fd7eaa5f77180d52ef5b542d2ec7b50e7fcd7124	\\x9987a7adb2e10c1f9d13b1107626fed35f425bcdc4da7953ff3cb6c475567579378de8e7ee209c211b57c6453d40f18f12a7454efcf676391848e404abe0f63a1d49b386b108d4a9ea431d29ef5a0834f0087de57357b933fdd8c4e05103ecc4fac7852e3d49168cc804e4a1753179dfe79f752366be10afdf311976b897a9a4	\\xb360ed05a31a998fd66b2bbd8a009f02567a34152e175aed821e39a97a67eff2	\\x08860a11bd36af92e6a5b6d34cb1783b2e02fd2458b9ba1cfa8c7a202bebc69d41696e1f9ef13c9d7933da81c8a6fc5c46779c6237fb9218715fdd68cfdaa304	1577746821000000	0	11000000
15	\\xbd60ecf5d1babd7df5693701088b098c4a3595c452053df4e7209c750a26de152f9c7f78fe95d10d394be4b7014878ed9263d577d646e38f0d7e83f384cc2c55	\\x860a9106ae6eae432b56bd506c28c284de8de160911f8fe4f8d83c82a49d17cb19bb387e7d6e44ab6a96df96fd7eaa5f77180d52ef5b542d2ec7b50e7fcd7124	\\x7f48ae52c772b6bba3e9d25436ed8c0b3c8d8dbf4538be4db48d3242486882f95309e19c7ea6268be55845e41d5de7e72edbdd79397d8567a4466ff7ba607749bf6d8952c7e246c7ea629763153ac72f8b72c5d5190f015cc88e350851758e5eb6bd04890e56cbef478096a88329219f87d29d6af61b7363ebe0b953ea088844	\\xb360ed05a31a998fd66b2bbd8a009f02567a34152e175aed821e39a97a67eff2	\\xf8cbcdf046fd9f8ecde9fc3657453f9fb9a3f4a340e8b58d367af2a9744bcd913bff5341d04b1611a40cc7c13471182cd3b99c256c33ad7f3e3a6a70b09ad70f	1577746821000000	0	11000000
16	\\x2793ac5e58b5b44ddcf543b55700586a48867247eab1d5f823dc8bca6cbfbf0adcbbc8d7c4627c91bb682b070a2ace713244afd285f21a32905707339543b6bc	\\x860a9106ae6eae432b56bd506c28c284de8de160911f8fe4f8d83c82a49d17cb19bb387e7d6e44ab6a96df96fd7eaa5f77180d52ef5b542d2ec7b50e7fcd7124	\\x585a370d2250a03a18dd78f29257cd64f5742a58b3373d22212552d78520f4d709e610e901e39fef1f85601476978d697e0df0e78c2efa96b6300c953fe25578ab30db43b19e3130eeda7b907ae591b974289dc650862846a6f8aba6ef4867bc33456c8213e6048fe3956e378026019913cfa1527c1bc16ea0961b75a8ca4d25	\\xb360ed05a31a998fd66b2bbd8a009f02567a34152e175aed821e39a97a67eff2	\\xabca4b6bb176af7652ac4b54b97f59e191f8707019f44f31a80033f5d773d5e7425114e38a78ddac89775e7b178752a628fd516279fdee589b3a10809e5f880c	1577746821000000	0	11000000
17	\\xd67d615573e5ad4e58b3cec6789eb485cd7d1b1e0011f78d22c3694b42d7ba0470abf72129ee7a7175f35dd2d8249161fd245dc5c3f87f9942e373fa9e228da1	\\x860a9106ae6eae432b56bd506c28c284de8de160911f8fe4f8d83c82a49d17cb19bb387e7d6e44ab6a96df96fd7eaa5f77180d52ef5b542d2ec7b50e7fcd7124	\\x7823773ad8d13955b3031ac17872c3e6390f51ab49ab72c6220c155e2d40062ffb543027c4f8bb2a1db4c0ce7f8bd37f9acbfc2311197664f69b6e79de0c741e26cf4b2aa3d299a2dfd5161db42a6e1c6ca1f601c3c4c0e3cb2420aded280f002dcf358bc62c92b1b13e46bd9659e0283bd1b99c76f1745fd7073c2362d38068	\\xb360ed05a31a998fd66b2bbd8a009f02567a34152e175aed821e39a97a67eff2	\\x28d76faa5992bc1ea407a4a49c6c63deb881dfbdedfe1f81c0dcc5dfc54c67e9c2d823cbe592eac161231b6462263dfa385c7a496451f8a73380acb43f7c920b	1577746821000000	0	11000000
18	\\xd0c562646ad3283d5cc47b868109b40f31dc5b80ff24007826e0aca83b8e9ef8a033697f4f05510326a02ca7e43bb5a245384dfb7411cff73ec5abf26ba65b5b	\\x3b88f4740d356fd237675ab8f0c5df85d679b3c518aab8466bb9673e260c2a8a44295e90802514d3504a8d864075ac23c4cfe7b2b10c8e0351072d5fa83b2738	\\x562fcc3b75392cb7130208b1e6225f669108a3e0f39eee6033bc101ad64fb335bd8cbd22c6e6afa9ac810d2489cbf1c0620b6ec838d7b202fdd5918a1052a92b3fd6499bdfa0cc27a6440405082281b1a1ad2b5b30c6fadc09718cbfc3e5cc9ec4d1632220731f33ed9a14ee6ab4f8b8c22a775abfb879a5119853f445493e22	\\xb360ed05a31a998fd66b2bbd8a009f02567a34152e175aed821e39a97a67eff2	\\x8844c00c14f2bdff5fb8a4303ff2d0b4875c53384832420f17171bd809da4fc5cc9ca1157534b8ece5b4fa6ac9543534dac38cef0d725f60484f88602c62970b	1577746821000000	10	1000000
19	\\x831e5f583b55b18ced4e6f649f9e86d80fe2f9b1e056eb76954dd19c408532300f5a8b92f6fb9dd50b74dee2c3e1d3dea41958b38e04b3ccd607e47244380585	\\x5cac576b6aa21e7df191af5ee270caf70a0ab3a64cf16006984a44dffa43d6021188fd63c00df4265316d9ff6f415f9e06f83f50996962da962309b78d445a42	\\x1db7fa0c2bb0bc1ee7b6838eada67f7ca3bfb36fb177720a53ed1faaa3521ebbbda29dc17e90b1642cee46d717d76354eb64dbcf472b45d77f2e43df01f3a9900315ca9c6b53e8fba9b267d0657929f241b680cb6531d609c8aabb151a8d7fd2a20157b13ce91aba7bd4f807649f91ca19a6a6a7bc714133f1b09d8787db0f39	\\xb360ed05a31a998fd66b2bbd8a009f02567a34152e175aed821e39a97a67eff2	\\xe6131249c4325d90ae6c08e97f4c51b9e02da32067f032905d1a546ad850b0c7ef9b208c6cd5750a00e25e1378409ccde75e68369b3e678715524b7ee73faa0a	1577746821000000	0	2000000
20	\\x96fb8c82606b0c635e557a471367f6a278397379601e19efa7d034f121f94780e6cdb2d1c0a954d0ced5a12997044418522704e7000dcd6cb083cad132e03d3b	\\x335c50be155aa7740ef7d610f1a805049a15090438451bc8a2c0883753bebc53f291749044c51fa1d95c691e2761b2e580959a8a7fbca31eb80ee5b8feb3e448	\\x0366d7ff51ed1fbf529310ce5a4281149139e72a687de349fb71e0be8fc92f95a1ed8c8c28031de272b79e56f9e57afd1a1bee28200a134ff078effcbf1b68aa4f2c1c2a17bf3f79f4d405e2e174bf30977387dd419442f78439b9039861fd6112414b75622e6d21cd435e72f0fa61006811433f15fe32dd694480217f3ce4f3	\\xb360ed05a31a998fd66b2bbd8a009f02567a34152e175aed821e39a97a67eff2	\\xf6b531c312e7058cb9d48717a09dab15b382715adcc766d14aab246df09cf7a8259784929c68d8f1c741a405c79ec078ed5db2f969d6eea133b6ecc9b095dd0c	1577746821000000	5	1000000
21	\\xc87596ad4321bd3c30f058e456d05daa3b96aa5be625ddca280a7f5cf7293227d2f9b3ffad139c2dae4966f8a9c7b06a0df78f6c8a42369a84c4d4da4925c126	\\x860a9106ae6eae432b56bd506c28c284de8de160911f8fe4f8d83c82a49d17cb19bb387e7d6e44ab6a96df96fd7eaa5f77180d52ef5b542d2ec7b50e7fcd7124	\\x38fbc5d80e7ae6204cd0fae1d9e6f0b7c6e9ee75e3d0a9bb79e6019daa6ed4129217aad9bb7021bb09ce303cd1d1cbd29d86abd89730ba4022d812fd9ff3de2dfb68311cdf870498087d7e5b4e39c6aab0cb83e1592a7c1ec6ba7a730e5e23d8c4785b9cce213fd2afaea846a62e9d32fb6f772cf1257b94b115086a21347aa8	\\xb360ed05a31a998fd66b2bbd8a009f02567a34152e175aed821e39a97a67eff2	\\x6ab841115eb466019577114702fcb5fe7f75e5073b87427c7cd0237b0c2ad66acbedc7fa5abe18b6d34b74b308d9ae93f772a799bb8652f8e8bbc8c0f3d2f807	1577746821000000	0	11000000
22	\\xc739667fc10a08b685e93e13555ad176793599d3e9eef21aa09ef554ca9bfbae8182143cf6bba339c4b3f91373f811879be30b12f69c0a31e5d010eee7e647bd	\\x860a9106ae6eae432b56bd506c28c284de8de160911f8fe4f8d83c82a49d17cb19bb387e7d6e44ab6a96df96fd7eaa5f77180d52ef5b542d2ec7b50e7fcd7124	\\x420791ee0aa574f3914aed2ac53687bfb5c310d24665727aaac0aea028cd492a4cbc4f0230b4db477b8f2c477e1fd6e19ae0c4db787ec4ed5075a9068d285fa14717d2933b42f96693695b3d872f6e1f5ed0958199410ccbd1d4b1b72cba431c71fa409e578578a9d702aaeddb905d7d1fa5beb0c5e6097817903e33b5dfda4c	\\xb360ed05a31a998fd66b2bbd8a009f02567a34152e175aed821e39a97a67eff2	\\xb5c4e1752698ff08c518fd06328d7d727145431f50c3bc92027b8337a0bf49be2e204644adab2fb1dc6382dc7a674766741078ca68658ab91d0c2373fc7f2007	1577746821000000	0	11000000
23	\\xf7bd87ecf0b864c584c260ffc29901a49b7929f8421fb9c9029cb842b17e143b32547e573df7859bf3c8a62abd6ad75c21e1e08dc65fefb4816ae59098479ed9	\\x860a9106ae6eae432b56bd506c28c284de8de160911f8fe4f8d83c82a49d17cb19bb387e7d6e44ab6a96df96fd7eaa5f77180d52ef5b542d2ec7b50e7fcd7124	\\x06b192398e24d4e75c6256656f9c06431f6575c059023fd9473c9cfd76d78020bf82001c942c06553eb2a9ef8b1c9fd0919efcd1b830a7b9efe4dac6c3d014bdca469597772e71f8ba742d7b5a0cab43819aa42843c3b4eb59eb2b9e6655d602a2b5f96d7379c0a304dad41d067a1ae3e806d4e49565ec9ad2cba283cdaa7218	\\xb360ed05a31a998fd66b2bbd8a009f02567a34152e175aed821e39a97a67eff2	\\x6c90abd7d494f2a0776449c632f561527e4cf3a722c33711e92d3a0bacfb472417e1c51c73549f6f3ec6275761dbb3380fc415118e94d58e599369a7888b3e08	1577746821000000	0	11000000
24	\\xc59ae15aad438f903305d310d4d15e8fb7a38543ae913139d55b0d925de899f1120c91af81683e12f6a691ad2a8d632dc6da6bc16ada4a6061b06128c201237d	\\x860a9106ae6eae432b56bd506c28c284de8de160911f8fe4f8d83c82a49d17cb19bb387e7d6e44ab6a96df96fd7eaa5f77180d52ef5b542d2ec7b50e7fcd7124	\\xadb5b9ea523fa3107cb618b45420dfc079b381a8c514ce564f589523a9aab95b5cdb1bf2778e4d9482204f9ed034899e5aef0fc47aeb9d3ee2fb789d79d4ae6f61cdf223d301858ec398b3887f03d5e5377bfb59fa3c325b8e331ba3b27903ddd7cf4f3e1892d859fd84eb5882869596764f6baebb71efd26403bdcc1d6be916	\\xb360ed05a31a998fd66b2bbd8a009f02567a34152e175aed821e39a97a67eff2	\\xc142be76512cacacba6001c76323f0d2eb05d200f7002ab7a7a211b91cbcb08fc3026c9fa10b65bdf3f1eb70feeb57538654ca593f0a9028766fa19215d5e607	1577746821000000	0	11000000
25	\\xbeeaea96350d2bcaba0f84aa3af0217b774b8adee04b403a88fec639726dc261c53dd1935f9dbeeb49b6588f341e0bbda6c86a246ec494a05c55ed684a062df8	\\x5cac576b6aa21e7df191af5ee270caf70a0ab3a64cf16006984a44dffa43d6021188fd63c00df4265316d9ff6f415f9e06f83f50996962da962309b78d445a42	\\x7f6fd5cc2e8d41ce8132f343933e4f8256656d596331c7f1dfd9cad84ad6a509c360060190e078e2814cbd2140b9432d999e6f2685054461d16d74173d8d147e9e8162fbbcd9499b49c718cfe7c722c1c717acb49930ac3b8b06a71cc5c6b804e0b7a7aca5da04782f0ebf940bd9887fafedd3a359a9b51bce9cd320062b3196	\\xb360ed05a31a998fd66b2bbd8a009f02567a34152e175aed821e39a97a67eff2	\\x9028bcc11e958cd61db657a2882c64aa2316acd9a3986367e7c91cec98ae5d7725621a5617b6dc9007ca31ca515c44c74b9a1fc4fb152d5fff33d86f92da4306	1577746821000000	0	2000000
26	\\x44cf66f26829ebb6abf53fed06af8770a28d3ea9204dd67c25e6c41d3fa742b02cd56884e22e15bd7e76ff850f818dc62ba2dcc13a9be0dd1c6a153911e54a67	\\x5cac576b6aa21e7df191af5ee270caf70a0ab3a64cf16006984a44dffa43d6021188fd63c00df4265316d9ff6f415f9e06f83f50996962da962309b78d445a42	\\xa3dfa24bc8a1d965320f1087054efe4793632acea0d4875bb3d4773f09ae20cccc5fbe5be1d8409e30fd98a5f465e18974fc10dbda0e09e7475ec7666d1ec60cf715ff7a1b696f823e3169d5cdc6300e2a33d89f7596aeb148409c1e3df513bf3c0da71bc192e8458dcc59f1512b552078e8ef25099a8bfc127061bff592ad0a	\\xb360ed05a31a998fd66b2bbd8a009f02567a34152e175aed821e39a97a67eff2	\\xd934de87fb63c44d6cb51b41f24154c9e55923e981ce5bcda0d3fe4a31e26570bce2bc88199c30bf16aa3abbf567cb60779c9f46f6a1cc52e43454095702750b	1577746821000000	0	2000000
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

COPY public.wire_fee (wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, master_sig) FROM stdin;
\.


--
-- Data for Name: wire_out; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.wire_out (wireout_uuid, execution_date, wtid_raw, wire_target, exchange_account_section, amount_val, amount_frac) FROM stdin;
\.


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

SELECT pg_catalog.setval('public.app_banktransaction_id_seq', 4, true);


--
-- Name: auditor_reserves_auditor_reserves_rowid_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.auditor_reserves_auditor_reserves_rowid_seq', 1, false);


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
-- Name: denomination_revocations_denom_revocations_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.denomination_revocations_denom_revocations_serial_id_seq', 1, false);


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

SELECT pg_catalog.setval('public.django_migrations_id_seq', 15, true);


--
-- Name: merchant_contract_terms_row_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_contract_terms_row_id_seq', 3, true);


--
-- Name: merchant_refunds_rtransaction_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_refunds_rtransaction_id_seq', 1, true);


--
-- Name: prewire_prewire_uuid_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.prewire_prewire_uuid_seq', 1, false);


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
-- Name: wire_out_wireout_uuid_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.wire_out_wireout_uuid_seq', 1, false);


--
-- Name: patches patches_pkey; Type: CONSTRAINT; Schema: _v; Owner: -
--

ALTER TABLE ONLY _v.patches
    ADD CONSTRAINT patches_pkey PRIMARY KEY (patch_name);


--
-- Name: aggregation_tracking aggregation_tracking_aggregation_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.aggregation_tracking
    ADD CONSTRAINT aggregation_tracking_aggregation_serial_id_key UNIQUE (aggregation_serial_id);


--
-- Name: aggregation_tracking aggregation_tracking_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.aggregation_tracking
    ADD CONSTRAINT aggregation_tracking_pkey PRIMARY KEY (deposit_serial_id);


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
-- Name: app_talerwithdrawoperation app_talerwithdrawoperation_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_talerwithdrawoperation
    ADD CONSTRAINT app_talerwithdrawoperation_pkey PRIMARY KEY (withdraw_id);


--
-- Name: auditor_denomination_pending auditor_denomination_pending_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_denomination_pending
    ADD CONSTRAINT auditor_denomination_pending_pkey PRIMARY KEY (denom_pub_hash);


--
-- Name: auditor_denominations auditor_denominations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_denominations
    ADD CONSTRAINT auditor_denominations_pkey PRIMARY KEY (denom_pub_hash);


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
-- Name: auditor_reserves auditor_reserves_auditor_reserves_rowid_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_reserves
    ADD CONSTRAINT auditor_reserves_auditor_reserves_rowid_key UNIQUE (auditor_reserves_rowid);


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
-- Name: denomination_revocations denomination_revocations_denom_revocations_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.denomination_revocations
    ADD CONSTRAINT denomination_revocations_denom_revocations_serial_id_key UNIQUE (denom_revocations_serial_id);


--
-- Name: denomination_revocations denomination_revocations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.denomination_revocations
    ADD CONSTRAINT denomination_revocations_pkey PRIMARY KEY (denom_pub_hash);


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
-- Name: deposits deposits_coin_pub_merchant_pub_h_contract_terms_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposits
    ADD CONSTRAINT deposits_coin_pub_merchant_pub_h_contract_terms_key UNIQUE (coin_pub, merchant_pub, h_contract_terms);


--
-- Name: deposits deposits_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposits
    ADD CONSTRAINT deposits_pkey PRIMARY KEY (deposit_serial_id);


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
-- Name: exchange_wire_fees exchange_wire_fees_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exchange_wire_fees
    ADD CONSTRAINT exchange_wire_fees_pkey PRIMARY KEY (exchange_pub, h_wire_method, start_date, end_date);


--
-- Name: known_coins known_coins_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.known_coins
    ADD CONSTRAINT known_coins_pkey PRIMARY KEY (coin_pub);


--
-- Name: merchant_contract_terms merchant_contract_terms_h_contract_terms_merchant_pub_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_contract_terms
    ADD CONSTRAINT merchant_contract_terms_h_contract_terms_merchant_pub_key UNIQUE (h_contract_terms, merchant_pub);


--
-- Name: merchant_contract_terms merchant_contract_terms_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_contract_terms
    ADD CONSTRAINT merchant_contract_terms_pkey PRIMARY KEY (order_id, merchant_pub);


--
-- Name: merchant_contract_terms merchant_contract_terms_row_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_contract_terms
    ADD CONSTRAINT merchant_contract_terms_row_id_key UNIQUE (row_id);


--
-- Name: merchant_deposits merchant_deposits_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_deposits
    ADD CONSTRAINT merchant_deposits_pkey PRIMARY KEY (h_contract_terms, coin_pub);


--
-- Name: merchant_orders merchant_orders_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_orders
    ADD CONSTRAINT merchant_orders_pkey PRIMARY KEY (order_id, merchant_pub);


--
-- Name: merchant_proofs merchant_proofs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_proofs
    ADD CONSTRAINT merchant_proofs_pkey PRIMARY KEY (wtid, exchange_url);


--
-- Name: merchant_refunds merchant_refunds_rtransaction_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_refunds
    ADD CONSTRAINT merchant_refunds_rtransaction_id_key UNIQUE (rtransaction_id);


--
-- Name: merchant_session_info merchant_session_info_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_session_info
    ADD CONSTRAINT merchant_session_info_pkey PRIMARY KEY (session_id, fulfillment_url, merchant_pub);


--
-- Name: merchant_session_info merchant_session_info_session_id_fulfillment_url_order_id_m_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_session_info
    ADD CONSTRAINT merchant_session_info_session_id_fulfillment_url_order_id_m_key UNIQUE (session_id, fulfillment_url, order_id, merchant_pub);


--
-- Name: merchant_tip_pickups merchant_tip_pickups_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tip_pickups
    ADD CONSTRAINT merchant_tip_pickups_pkey PRIMARY KEY (pickup_id);


--
-- Name: merchant_tip_reserve_credits merchant_tip_reserve_credits_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tip_reserve_credits
    ADD CONSTRAINT merchant_tip_reserve_credits_pkey PRIMARY KEY (credit_uuid);


--
-- Name: merchant_tip_reserves merchant_tip_reserves_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tip_reserves
    ADD CONSTRAINT merchant_tip_reserves_pkey PRIMARY KEY (reserve_priv);


--
-- Name: merchant_tips merchant_tips_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tips
    ADD CONSTRAINT merchant_tips_pkey PRIMARY KEY (tip_id);


--
-- Name: merchant_transfers merchant_transfers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_transfers
    ADD CONSTRAINT merchant_transfers_pkey PRIMARY KEY (h_contract_terms, coin_pub);


--
-- Name: prewire prewire_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prewire
    ADD CONSTRAINT prewire_pkey PRIMARY KEY (prewire_uuid);


--
-- Name: recoup recoup_recoup_uuid_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recoup
    ADD CONSTRAINT recoup_recoup_uuid_key UNIQUE (recoup_uuid);


--
-- Name: recoup_refresh recoup_refresh_recoup_refresh_uuid_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recoup_refresh
    ADD CONSTRAINT recoup_refresh_recoup_refresh_uuid_key UNIQUE (recoup_refresh_uuid);


--
-- Name: refresh_commitments refresh_commitments_melt_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_commitments
    ADD CONSTRAINT refresh_commitments_melt_serial_id_key UNIQUE (melt_serial_id);


--
-- Name: refresh_commitments refresh_commitments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_commitments
    ADD CONSTRAINT refresh_commitments_pkey PRIMARY KEY (rc);


--
-- Name: refresh_revealed_coins refresh_revealed_coins_coin_ev_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_revealed_coins
    ADD CONSTRAINT refresh_revealed_coins_coin_ev_key UNIQUE (coin_ev);


--
-- Name: refresh_revealed_coins refresh_revealed_coins_h_coin_ev_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_revealed_coins
    ADD CONSTRAINT refresh_revealed_coins_h_coin_ev_key UNIQUE (h_coin_ev);


--
-- Name: refresh_revealed_coins refresh_revealed_coins_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_revealed_coins
    ADD CONSTRAINT refresh_revealed_coins_pkey PRIMARY KEY (rc, newcoin_index);


--
-- Name: refresh_transfer_keys refresh_transfer_keys_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_transfer_keys
    ADD CONSTRAINT refresh_transfer_keys_pkey PRIMARY KEY (rc);


--
-- Name: refunds refunds_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refunds
    ADD CONSTRAINT refunds_pkey PRIMARY KEY (coin_pub, merchant_pub, h_contract_terms, rtransaction_id);


--
-- Name: refunds refunds_refund_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refunds
    ADD CONSTRAINT refunds_refund_serial_id_key UNIQUE (refund_serial_id);


--
-- Name: reserves_close reserves_close_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserves_close
    ADD CONSTRAINT reserves_close_pkey PRIMARY KEY (close_uuid);


--
-- Name: reserves_in reserves_in_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserves_in
    ADD CONSTRAINT reserves_in_pkey PRIMARY KEY (reserve_pub, wire_reference);


--
-- Name: reserves_in reserves_in_reserve_in_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserves_in
    ADD CONSTRAINT reserves_in_reserve_in_serial_id_key UNIQUE (reserve_in_serial_id);


--
-- Name: reserves_out reserves_out_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserves_out
    ADD CONSTRAINT reserves_out_pkey PRIMARY KEY (h_blind_ev);


--
-- Name: reserves_out reserves_out_reserve_out_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserves_out
    ADD CONSTRAINT reserves_out_reserve_out_serial_id_key UNIQUE (reserve_out_serial_id);


--
-- Name: reserves reserves_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserves
    ADD CONSTRAINT reserves_pkey PRIMARY KEY (reserve_pub);


--
-- Name: wire_fee wire_fee_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wire_fee
    ADD CONSTRAINT wire_fee_pkey PRIMARY KEY (wire_method, start_date);


--
-- Name: wire_out wire_out_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wire_out
    ADD CONSTRAINT wire_out_pkey PRIMARY KEY (wireout_uuid);


--
-- Name: wire_out wire_out_wtid_raw_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wire_out
    ADD CONSTRAINT wire_out_wtid_raw_key UNIQUE (wtid_raw);


--
-- Name: aggregation_tracking_wtid_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX aggregation_tracking_wtid_index ON public.aggregation_tracking USING btree (wtid_raw);


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
-- Name: denominations_expire_legal_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX denominations_expire_legal_index ON public.denominations USING btree (expire_legal);


--
-- Name: deposits_coin_pub_merchant_contract_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX deposits_coin_pub_merchant_contract_index ON public.deposits USING btree (coin_pub, merchant_pub, h_contract_terms);


--
-- Name: deposits_get_ready_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX deposits_get_ready_index ON public.deposits USING btree (tiny, done, wire_deadline, refund_deadline);


--
-- Name: deposits_iterate_matching; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX deposits_iterate_matching ON public.deposits USING btree (merchant_pub, h_wire, done, wire_deadline);


--
-- Name: django_session_expire_date_a5c62663; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX django_session_expire_date_a5c62663 ON public.django_session USING btree (expire_date);


--
-- Name: django_session_session_key_c0390e0f_like; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX django_session_session_key_c0390e0f_like ON public.django_session USING btree (session_key varchar_pattern_ops);


--
-- Name: known_coins_by_denomination; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX known_coins_by_denomination ON public.known_coins USING btree (denom_pub_hash);


--
-- Name: merchant_transfers_by_coin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX merchant_transfers_by_coin ON public.merchant_transfers USING btree (h_contract_terms, coin_pub);


--
-- Name: merchant_transfers_by_wtid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX merchant_transfers_by_wtid ON public.merchant_transfers USING btree (wtid);


--
-- Name: prepare_iteration_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX prepare_iteration_index ON public.prewire USING btree (finished);


--
-- Name: recoup_by_coin_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recoup_by_coin_index ON public.recoup USING btree (coin_pub);


--
-- Name: recoup_by_h_blind_ev; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recoup_by_h_blind_ev ON public.recoup USING btree (h_blind_ev);


--
-- Name: recoup_for_by_reserve; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recoup_for_by_reserve ON public.recoup USING btree (coin_pub, h_blind_ev);


--
-- Name: recoup_refresh_by_coin_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recoup_refresh_by_coin_index ON public.recoup_refresh USING btree (coin_pub);


--
-- Name: recoup_refresh_by_h_blind_ev; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recoup_refresh_by_h_blind_ev ON public.recoup_refresh USING btree (h_blind_ev);


--
-- Name: recoup_refresh_for_by_reserve; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recoup_refresh_for_by_reserve ON public.recoup_refresh USING btree (coin_pub, h_blind_ev);


--
-- Name: refresh_commitments_old_coin_pub_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX refresh_commitments_old_coin_pub_index ON public.refresh_commitments USING btree (old_coin_pub);


--
-- Name: refresh_revealed_coins_coin_pub_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX refresh_revealed_coins_coin_pub_index ON public.refresh_revealed_coins USING btree (denom_pub_hash);


--
-- Name: refresh_transfer_keys_coin_tpub; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX refresh_transfer_keys_coin_tpub ON public.refresh_transfer_keys USING btree (rc, transfer_pub);


--
-- Name: refunds_coin_pub_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX refunds_coin_pub_index ON public.refunds USING btree (coin_pub);


--
-- Name: reserves_close_by_reserve; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_close_by_reserve ON public.reserves_close USING btree (reserve_pub);


--
-- Name: reserves_expiration_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_expiration_index ON public.reserves USING btree (expiration_date, current_balance_val, current_balance_frac);


--
-- Name: reserves_gc_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_gc_index ON public.reserves USING btree (gc_date);


--
-- Name: reserves_in_exchange_account_serial; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_in_exchange_account_serial ON public.reserves_in USING btree (exchange_account_section, reserve_in_serial_id DESC);


--
-- Name: reserves_in_execution_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_in_execution_index ON public.reserves_in USING btree (exchange_account_section, execution_date);


--
-- Name: reserves_out_execution_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_out_execution_date ON public.reserves_out USING btree (execution_date);


--
-- Name: reserves_out_for_get_withdraw_info; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_out_for_get_withdraw_info ON public.reserves_out USING btree (denom_pub_hash, h_blind_ev);


--
-- Name: reserves_out_reserve_pub_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_out_reserve_pub_index ON public.reserves_out USING btree (reserve_pub);


--
-- Name: reserves_reserve_pub_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_reserve_pub_index ON public.reserves USING btree (reserve_pub);


--
-- Name: wire_fee_gc_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX wire_fee_gc_index ON public.wire_fee USING btree (end_date);


--
-- Name: aggregation_tracking aggregation_tracking_deposit_serial_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.aggregation_tracking
    ADD CONSTRAINT aggregation_tracking_deposit_serial_id_fkey FOREIGN KEY (deposit_serial_id) REFERENCES public.deposits(deposit_serial_id) ON DELETE CASCADE;


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
-- Name: auditor_denomination_pending auditor_denomination_pending_denom_pub_hash_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_denomination_pending
    ADD CONSTRAINT auditor_denomination_pending_denom_pub_hash_fkey FOREIGN KEY (denom_pub_hash) REFERENCES public.auditor_denominations(denom_pub_hash) ON DELETE CASCADE;


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
-- Name: denomination_revocations denomination_revocations_denom_pub_hash_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.denomination_revocations
    ADD CONSTRAINT denomination_revocations_denom_pub_hash_fkey FOREIGN KEY (denom_pub_hash) REFERENCES public.denominations(denom_pub_hash) ON DELETE CASCADE;


--
-- Name: deposits deposits_coin_pub_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposits
    ADD CONSTRAINT deposits_coin_pub_fkey FOREIGN KEY (coin_pub) REFERENCES public.known_coins(coin_pub) ON DELETE CASCADE;


--
-- Name: known_coins known_coins_denom_pub_hash_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.known_coins
    ADD CONSTRAINT known_coins_denom_pub_hash_fkey FOREIGN KEY (denom_pub_hash) REFERENCES public.denominations(denom_pub_hash) ON DELETE CASCADE;


--
-- Name: auditor_exchange_signkeys master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_exchange_signkeys
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES public.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_denominations master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_denominations
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
-- Name: merchant_deposits merchant_deposits_h_contract_terms_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_deposits
    ADD CONSTRAINT merchant_deposits_h_contract_terms_fkey FOREIGN KEY (h_contract_terms, merchant_pub) REFERENCES public.merchant_contract_terms(h_contract_terms, merchant_pub);


--
-- Name: merchant_tip_pickups merchant_tip_pickups_tip_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tip_pickups
    ADD CONSTRAINT merchant_tip_pickups_tip_id_fkey FOREIGN KEY (tip_id) REFERENCES public.merchant_tips(tip_id) ON DELETE CASCADE;


--
-- Name: recoup recoup_coin_pub_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recoup
    ADD CONSTRAINT recoup_coin_pub_fkey FOREIGN KEY (coin_pub) REFERENCES public.known_coins(coin_pub);


--
-- Name: recoup recoup_h_blind_ev_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recoup
    ADD CONSTRAINT recoup_h_blind_ev_fkey FOREIGN KEY (h_blind_ev) REFERENCES public.reserves_out(h_blind_ev) ON DELETE CASCADE;


--
-- Name: recoup_refresh recoup_refresh_coin_pub_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recoup_refresh
    ADD CONSTRAINT recoup_refresh_coin_pub_fkey FOREIGN KEY (coin_pub) REFERENCES public.known_coins(coin_pub);


--
-- Name: recoup_refresh recoup_refresh_h_blind_ev_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recoup_refresh
    ADD CONSTRAINT recoup_refresh_h_blind_ev_fkey FOREIGN KEY (h_blind_ev) REFERENCES public.refresh_revealed_coins(h_coin_ev) ON DELETE CASCADE;


--
-- Name: refresh_commitments refresh_commitments_old_coin_pub_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_commitments
    ADD CONSTRAINT refresh_commitments_old_coin_pub_fkey FOREIGN KEY (old_coin_pub) REFERENCES public.known_coins(coin_pub) ON DELETE CASCADE;


--
-- Name: refresh_revealed_coins refresh_revealed_coins_denom_pub_hash_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_revealed_coins
    ADD CONSTRAINT refresh_revealed_coins_denom_pub_hash_fkey FOREIGN KEY (denom_pub_hash) REFERENCES public.denominations(denom_pub_hash) ON DELETE CASCADE;


--
-- Name: refresh_revealed_coins refresh_revealed_coins_rc_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_revealed_coins
    ADD CONSTRAINT refresh_revealed_coins_rc_fkey FOREIGN KEY (rc) REFERENCES public.refresh_commitments(rc) ON DELETE CASCADE;


--
-- Name: refresh_transfer_keys refresh_transfer_keys_rc_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_transfer_keys
    ADD CONSTRAINT refresh_transfer_keys_rc_fkey FOREIGN KEY (rc) REFERENCES public.refresh_commitments(rc) ON DELETE CASCADE;


--
-- Name: refunds refunds_coin_pub_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refunds
    ADD CONSTRAINT refunds_coin_pub_fkey FOREIGN KEY (coin_pub) REFERENCES public.known_coins(coin_pub) ON DELETE CASCADE;


--
-- Name: reserves_close reserves_close_reserve_pub_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserves_close
    ADD CONSTRAINT reserves_close_reserve_pub_fkey FOREIGN KEY (reserve_pub) REFERENCES public.reserves(reserve_pub) ON DELETE CASCADE;


--
-- Name: reserves_in reserves_in_reserve_pub_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserves_in
    ADD CONSTRAINT reserves_in_reserve_pub_fkey FOREIGN KEY (reserve_pub) REFERENCES public.reserves(reserve_pub) ON DELETE CASCADE;


--
-- Name: reserves_out reserves_out_denom_pub_hash_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserves_out
    ADD CONSTRAINT reserves_out_denom_pub_hash_fkey FOREIGN KEY (denom_pub_hash) REFERENCES public.denominations(denom_pub_hash);


--
-- Name: reserves_out reserves_out_reserve_pub_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserves_out
    ADD CONSTRAINT reserves_out_reserve_pub_fkey FOREIGN KEY (reserve_pub) REFERENCES public.reserves(reserve_pub) ON DELETE CASCADE;


--
-- Name: aggregation_tracking wire_out_ref; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.aggregation_tracking
    ADD CONSTRAINT wire_out_ref FOREIGN KEY (wtid_raw) REFERENCES public.wire_out(wtid_raw) ON DELETE CASCADE DEFERRABLE;


--
-- PostgreSQL database dump complete
--

