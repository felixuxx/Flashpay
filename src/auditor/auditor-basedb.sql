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
    irregular_payback_val bigint NOT NULL,
    irregular_payback_frac integer NOT NULL
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
    payback_loss_val bigint NOT NULL,
    payback_loss_frac integer NOT NULL
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
    last_payback_serial_id bigint DEFAULT 0 NOT NULL,
    last_payback_refresh_serial_id bigint DEFAULT 0 NOT NULL
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
    last_reserve_payback_serial_id bigint DEFAULT 0 NOT NULL,
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
-- Name: payback; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payback (
    payback_uuid bigint NOT NULL,
    coin_pub bytea NOT NULL,
    coin_sig bytea NOT NULL,
    coin_blind bytea NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    "timestamp" bigint NOT NULL,
    h_blind_ev bytea NOT NULL,
    CONSTRAINT payback_coin_blind_check CHECK ((length(coin_blind) = 32)),
    CONSTRAINT payback_coin_sig_check CHECK ((length(coin_sig) = 64))
);


--
-- Name: payback_payback_uuid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.payback_payback_uuid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: payback_payback_uuid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.payback_payback_uuid_seq OWNED BY public.payback.payback_uuid;


--
-- Name: payback_refresh; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payback_refresh (
    payback_refresh_uuid bigint NOT NULL,
    coin_pub bytea NOT NULL,
    coin_sig bytea NOT NULL,
    coin_blind bytea NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    "timestamp" bigint NOT NULL,
    h_blind_ev bytea NOT NULL,
    CONSTRAINT payback_refresh_coin_blind_check CHECK ((length(coin_blind) = 32)),
    CONSTRAINT payback_refresh_coin_sig_check CHECK ((length(coin_sig) = 64))
);


--
-- Name: payback_refresh_payback_refresh_uuid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.payback_refresh_payback_refresh_uuid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: payback_refresh_payback_refresh_uuid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.payback_refresh_payback_refresh_uuid_seq OWNED BY public.payback_refresh.payback_refresh_uuid;


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
-- Name: payback payback_uuid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payback ALTER COLUMN payback_uuid SET DEFAULT nextval('public.payback_payback_uuid_seq'::regclass);


--
-- Name: payback_refresh payback_refresh_uuid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payback_refresh ALTER COLUMN payback_refresh_uuid SET DEFAULT nextval('public.payback_refresh_payback_refresh_uuid_seq'::regclass);


--
-- Name: prewire prewire_uuid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prewire ALTER COLUMN prewire_uuid SET DEFAULT nextval('public.prewire_prewire_uuid_seq'::regclass);


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
auditor-0001	2019-12-31 00:00:16.766803+01	grothoff	{}	{}
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
t	1	-TESTKUDOS:100	1
f	11	+TESTKUDOS:90	11
t	2	+TESTKUDOS:10	2
\.


--
-- Data for Name: app_banktransaction; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_banktransaction (id, amount, subject, date, cancelled, credit_account_id, debit_account_id) FROM stdin;
1	TESTKUDOS:100	Joining bonus	2019-12-31 00:00:23.885865+01	f	11	1
2	TESTKUDOS:10	NK0MYA7R2VFF1DFHB4SGXVR028GJPE4R6C0M1Q1X9YNKMCNSESCG	2019-12-31 00:00:23.979103+01	f	2	11
\.


--
-- Data for Name: app_talerwithdrawoperation; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_talerwithdrawoperation (withdraw_id, amount, selection_done, withdraw_done, selected_reserve_pub, selected_exchange_account_id, withdraw_account_id) FROM stdin;
\.


--
-- Data for Name: auditor_balance_summary; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_balance_summary (master_pub, denom_balance_val, denom_balance_frac, deposit_fee_balance_val, deposit_fee_balance_frac, melt_fee_balance_val, melt_fee_balance_frac, refund_fee_balance_val, refund_fee_balance_frac, risk_val, risk_frac, loss_val, loss_frac, irregular_payback_val, irregular_payback_frac) FROM stdin;
\.


--
-- Data for Name: auditor_denomination_pending; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_denomination_pending (denom_pub_hash, denom_balance_val, denom_balance_frac, denom_loss_val, denom_loss_frac, num_issued, denom_risk_val, denom_risk_frac, payback_loss_val, payback_loss_frac) FROM stdin;
\.


--
-- Data for Name: auditor_denominations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_denominations (denom_pub_hash, master_pub, valid_from, expire_withdraw, expire_deposit, expire_legal, coin_val, coin_frac, fee_withdraw_val, fee_withdraw_frac, fee_deposit_val, fee_deposit_frac, fee_refresh_val, fee_refresh_frac, fee_refund_val, fee_refund_frac) FROM stdin;
\\x14eb7f896d6e9a06c70131d39032b9542b0c0795f12761e1578a9616aaadbf6b6b5e170f98fdd194260e09c841c11145a2469d7cb24cc9ee634351516addceaf	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1577746809000000	1578351609000000	1640818809000000	1672354809000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf905cf7ac97484f4642762daaeb03ea91b5cfd27c669b4cd05a67dfd1748afc09653bd4f612d1bd394b0e76e171914533d751b9cf6c4178032b8a8279ce997c7	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1578351309000000	1578956109000000	1641423309000000	1672959309000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xef82dd7f1cec75db10e2f1bb047fa2bd4fcaa749a42ed69d3b2fade5cca1abd1317793214497817052ab8ec829d52dbc0270bbe5b93e59e7d8d4a9eb69e6dfb1	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1578955809000000	1579560609000000	1642027809000000	1673563809000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4b71bbb496f4b547d976d8634adfb9a207d34930718d8a5a95d7251ac486254a8a874ea472d83b6fa349d1a5859ed46d00f51cb65ee542e78dccf7850a106c0a	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1579560309000000	1580165109000000	1642632309000000	1674168309000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf42d803f1d06029e913a42ddf0ba8df1c0a962b4bf4ffa99ea145e616470996712ae2de4f4d10f352fd471e349bf32bb49a2bbe8fdc4a8179cca593a99ed5116	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1580164809000000	1580769609000000	1643236809000000	1674772809000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0c1da8ea9368b0f23e34ef37bf21f6ff7a5907e757dd08f3f8fdddf15e15173f7d09d5d4f249b5ad8bb523a6346c964b857f9135e45ca0c677471e0cfd2b4553	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1580769309000000	1581374109000000	1643841309000000	1675377309000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x216c219fd9d6bea5b1181963b0c6d57f73d57f69af998a38fff244d1041ad1894f5770371d427bbb212a219a7525a7adefba33f65243fc8e8bcabf2b01cf3800	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1581373809000000	1581978609000000	1644445809000000	1675981809000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7208ad0cf446a46792f092eeee024c0e9cdf6763b8a6e116149a0f37949f4d47e2cdea465ea2c70b2631ba7a73cc72d260905ce2b6c9860513765d9778baec71	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1581978309000000	1582583109000000	1645050309000000	1676586309000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x48180d9378bf378e827ef26ee3213db2568b8fc0c01c5b92827786bc8480da7a7d82adbf7cb45b65029a412b2511cca25cf739f52d83b9770fe831d9254efcab	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1582582809000000	1583187609000000	1645654809000000	1677190809000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf83a24a1c9d655ea7fdee4f6c194133fc97b13248b1337478dd48864625c944bccadec245e03514055e64271705eb8aab5503ad3e6fe1ec53f68025a3f2ad7a5	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1583187309000000	1583792109000000	1646259309000000	1677795309000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x764568355d4a013b9be80ad15d96d2348e0970b062d729332a5936ff4f31aaa6d4419f78b3188349864b75fbcc5d1918c99323c0a24262eab910377c50c7cfa2	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1583791809000000	1584396609000000	1646863809000000	1678399809000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0ca6e3b173a9b0aadd069e26b44bd15849f22a5aba0c5669243dc13b00b997af6d9e5c62747cd1abb0d5d21f48b304550eea3f6cf4f119c3a115d7e5b7893131	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1584396309000000	1585001109000000	1647468309000000	1679004309000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb5b059188d720de1194aab3a4ef68ead63aad7cf5e98c72809f01e123e45e416437adfedbd7f684c413082732168fdbd7ec82005af06fd059615d2224811586b	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1585000809000000	1585605609000000	1648072809000000	1679608809000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7c9d8823c93e961b8932f6a2ac8e68091205c804bd62140a0eeb21be2db228d841abbd68a816f436457b5470914451874e304ac9ba137e7f3bf1a6f4ef14fd6c	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1585605309000000	1586210109000000	1648677309000000	1680213309000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa2363b7415fb7f6f6cfdcace3443e1ca2b89bbf6708f5e39e3ad3dcfb1eb2543cd9b60d90b089f8a2afe37614bd09931715439bbb205b22054953375b334cc25	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1586209809000000	1586814609000000	1649281809000000	1680817809000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe614f8f5dcd7f4a6f7922bbbce34136020cb80b52445f07b96bca2f2deb6a0af8b15c24a50acf9b04a104d7503bd95c0c484b0953132bc660ddcbf65cca3146a	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1586814309000000	1587419109000000	1649886309000000	1681422309000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x78e661587822aeb7b019b4bf00f9454e9d20302143bbdb9465056f95bb64d3b949ac2254f27f2cbc4c362bdf52a5404a2099ddf34bffaa5f2b562368c2d5a248	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1587418809000000	1588023609000000	1650490809000000	1682026809000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc0ea16512b07389441a72d18f20f0cd9178088e077132af744a0d6ad13f2a4edc6dfde86cac08bf2ac6230b727b3597cb5e79a51fa7783a2a5d776016d5e589a	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1588023309000000	1588628109000000	1651095309000000	1682631309000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x33aa53ebb824207f78bde864a1d891d82cbba18d104bb2db3f1f47319411c8f8ba302c476c83fce1d27ea210c97738f43d52309730c21392f46708186f201f5b	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1588627809000000	1589232609000000	1651699809000000	1683235809000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x22c1c0417f9ad34a9fd1085103b5d2bdb3e2e4696f3f172decbd9243a5e4d5eb59646b9f91baeaae24b4d4fcbf15326a13a891a7adc89b8de40b86ae42a10447	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1589232309000000	1589837109000000	1652304309000000	1683840309000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x45e96794384ee5b0d78b98d14312e26e2de961ac29344c5af61c97903de7ddcb6e8539f2b7d57eab7ee896913c27b1b03ccb516a2217a44f287695e35f619310	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1589836809000000	1590441609000000	1652908809000000	1684444809000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xab936e39624b816715fb2bf2a127afd38dba5d8dc4ccfdb8c7dbc5a66a6edd75c5e4968ddb0b54e072499a03ad905650fffa91235f40817539eb9ab629ada5ba	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1590441309000000	1591046109000000	1653513309000000	1685049309000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd96bd0e2d9223806ecd4369932a21f9421db71e6902df97bd624a0da14e0b3158910fddf54fd0bee804ea26a26b0351f9579adb70890a754335acf6f76525c1e	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1591045809000000	1591650609000000	1654117809000000	1685653809000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x891275b08d8e97f6a407e51547372626237f13f8a4eba3f82b9611c399bc4ff80721a3b3838fdc303c52f60ccac177f214776a832d6562fc0aea8c9187072538	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1591650309000000	1592255109000000	1654722309000000	1686258309000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1a857a1fdfdfe04db0b95869f39b7f7b6c15c083cece8b1064f58480c3ac2c7b199e2647a17df6bd186f5f1709aaf6ac2dd97c048f898d85a21b0a61736969e3	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1592254809000000	1592859609000000	1655326809000000	1686862809000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3eacd69cbaacec8928ca28dc99b78c5ea0e543dcbeb3f5cd31203cd2ff8d5a1878180678655a841fe665b13b2a5aa6b4f5449ef272564ffaee41816e8e988865	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1592859309000000	1593464109000000	1655931309000000	1687467309000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xaf5185758f54364c2611b25be714ea0395077223c97993a161b8e284ca7bc25827abf111f73e8f2fa80ee2811649acd57f3ab7d6ca32da99c0f434003c117960	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1593463809000000	1594068609000000	1656535809000000	1688071809000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x93d942087713ed5cdf4bc6de70c2b15c1b04f131726fa198ab4c7d70604e7d0b5479a16bbfd6a38031c20404c6ba88b71eef7e077c913077ec00e39d9f1f6982	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1594068309000000	1594673109000000	1657140309000000	1688676309000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xde4d250b205a6ec136ad8c2c064407d1aad2a51ba88d9dc3a78d6453acc8d720adf05f36e9edba63796cc8cbbbaf3928835770ab4dbe442bee363406c8f7d91b	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1594672809000000	1595277609000000	1657744809000000	1689280809000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x54e289f2c40d3f2825bbcb054843e0424a2b271bf33428a2e7353365095df165892a9361a87edd2f1ecef5dca742f1e3ee2a4f0f4e5ce24aa3e5bbe2a0cad239	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1595277309000000	1595882109000000	1658349309000000	1689885309000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x963c11088139c850b492f46fc439d39a5bc911b044b5771eee947be5699d1ed25bfa34d35d9080d4af35fe7b23f3a0ab1cb9e092f327caa51ec7fb61b07597c7	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1595881809000000	1596486609000000	1658953809000000	1690489809000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4519bf9db7753f089be37e7ad8f16fb5269cabf13c5cb65348f49fae793bde533604b23b559388a332dc11b554633059d71483cc9919ecf9197c9e84e456e7f3	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1596486309000000	1597091109000000	1659558309000000	1691094309000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb17c8ee902464baf1056bb6315647b1c4dfefd21d1a0ee5c53c279370b419bf88e10d9a981c291b8d798475c01c4c685494e1b5835fd352d5a8a8837d9b6f496	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1597090809000000	1597695609000000	1660162809000000	1691698809000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xfb398283898de3cc81c0978c868abaa304a372b0a07023869d494a77a6cf703a3fbcd19b326a47ac14badbab3689f4add281c8ce27fa166ca5ffc034b4fcea36	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1577746809000000	1578351609000000	1640818809000000	1672354809000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x11af256cbd2f98f4a1df05b1d7aed3a96fcd3564898a4f812dc975e580354f9460a55fe332e5dc97761ec2dd0d3c3e5aa009d2fc0167990ceb8f498da61474aa	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1578351309000000	1578956109000000	1641423309000000	1672959309000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xc18dfa8bb406882c2b35c4d597556c4f99f4f277d571d34c4c72840e4e409f42f2a028ded10465530d1b54f4230eaadf7b6eec1b52cc612a4dfbf6f37147301a	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1578955809000000	1579560609000000	1642027809000000	1673563809000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xff7cd0c4b022ed726c383325f509a21208c00530dffb305d4e5b60be181d0e3e70ba6701169dbb7b45b6f9a287bad9889e5dd8430f260f473f656486a37635ac	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1579560309000000	1580165109000000	1642632309000000	1674168309000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x1d157bdadddddbeec9cd66411d88d86de0a09a233180cd2c5a248d7e05721b93e0b02d50e4c30d1b6de51c26fde6199ceafc2a717e0ab7bd6acd6a43f783e4dc	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1580164809000000	1580769609000000	1643236809000000	1674772809000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xc6258373d62a564a536f15a6b886c0cc9d41197d35f6694f6e54b2cfd558923204512fe54645282a3e924ba96ccca3272e8ac19bffa7d990a03ea19ec11c7547	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1580769309000000	1581374109000000	1643841309000000	1675377309000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x8aefa7499927850a6fb4a376bbc846b4a16b317304ee5ff9847783ad8317ed26bb4d9179966684de53dbd428b9ca099af8a10d4cea34bb88c5202f598334a13f	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1581373809000000	1581978609000000	1644445809000000	1675981809000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x3abf3cd90abf956f3d40466c6cea168326cdbe9175b1814591e7f859879f1537d1a8038338d2195062a30168494a0689609c286a29bf9c212888f2b1dd15b18d	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1581978309000000	1582583109000000	1645050309000000	1676586309000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xb300743977abe3f9ea5b46d77b7591194c51b8502168176e6fa8e3959e4b7e36b6eb894249da7cc6803f61c972f30df54da35080cdb2d9606e5f4d425b0b9a39	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1582582809000000	1583187609000000	1645654809000000	1677190809000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xa69c17ec88d02f441dd6ea7d6b9319f68aff5762c90e9f7629401aa429ee0a5269c89891c87fe08576a087214958bcbce2e289632c23ec3808d489f1a27c39cc	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1583187309000000	1583792109000000	1646259309000000	1677795309000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x910b8b03777ff95bba9056a7afd466e1e7c4e3f50c3ad357a4b149bc117db0b96bb37d3e8b74a0bdd67b5edfda3113fe506774fc8cbe373437e51f63ea15d2b8	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1583791809000000	1584396609000000	1646863809000000	1678399809000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x96fbfae3abb483d2c3a2ec0629246b5e646c5d510e28f216796e386ec1d4a3bac04f9f5488948b33d7c904f754455ea171c0680a7474ebe63d7779fbb6b535c0	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1584396309000000	1585001109000000	1647468309000000	1679004309000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x1da0d203e7a335d72bac5f05063469062336fee2853f1ec9141bc5b5467c415ff7cc8b7ccfa4f1cdf6bcf3da9badcbbe2e956d2c746d8eba9bd3c1e3442b9c1a	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1585000809000000	1585605609000000	1648072809000000	1679608809000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x454419e26316158b55fba55dc6e877fa83c95600d6842461d1bac879dd287583f8490bbf8aec99497a101f5dee9bdb6bd33aff4a6285b1edb00506108873865b	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1585605309000000	1586210109000000	1648677309000000	1680213309000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x26863772449425997da0f6c0b8b928d762b93b1e12bd7da55d7f88e714307d5345abee0177f02ce822cfebdcfd8c8ecad2c1e852b141b684e724471ee8b87eba	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1586209809000000	1586814609000000	1649281809000000	1680817809000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xfb9559b397512d846d2dc1b06eda1489c01ed43a8d6cc2fd1447a2239257291c0587410b242c747363252c99b87d5f1d180da7d92cb2f827238f9951ff55bbe6	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1586814309000000	1587419109000000	1649886309000000	1681422309000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x19c8fcc184546c5bbc5344f9a528c6a33238377322e85196fed997a29d6b961f11b6893ea4b1ec780b8c315c2f8823dd455990a4d0b3c4800b9a16dc625ee2f2	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1587418809000000	1588023609000000	1650490809000000	1682026809000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x8f884057e7a856255b7eea77b3893d09e89ccb7e2e71c73deab131c11ad6c92e55b557148a41811fa26874ec933f3239f310e42d301551d84a42bc8c9249eef5	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1588023309000000	1588628109000000	1651095309000000	1682631309000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x752c22aa4b1910019a9b3d13eea3b6f6beb9c7ae197c4cb2d564e341487b2707d669f16d0a1d269a0a45a94d64a2e91be6eb865cb0bca427c84af46a8dac027a	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1588627809000000	1589232609000000	1651699809000000	1683235809000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x4cbe66c6a83ea5764eba9e3ea95b44518e50dbf4104f8ea71037a5871027a9fddc5d29bc6140aa132d9784b35b904f37c169adcb36b0d26e5de6097ffdc98534	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1589232309000000	1589837109000000	1652304309000000	1683840309000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x6de56a988c14f0d59e1fe733fb5d8f93700cbf5d79475c6105f998a6bed9413f752a0a959e8a4747b2a6ca41dfbd71d4699fec2123816b1ca90be87b851d0fd1	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1589836809000000	1590441609000000	1652908809000000	1684444809000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xc51f5976e60e074056fa46834e5c6e2fde583623132f41c8b71901ec5fce3ab4c5b073012eecf9b7b99df4104c9c6d6f75acb75c13fa90e85801f60fe20e88cc	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1590441309000000	1591046109000000	1653513309000000	1685049309000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xbe9acd4d6c2bd7af89c53815dba21b76af79d8f4ac875a97a8c7fb0dc00b53f0467742dfd3d98e94df34bd21998afadad493f8605ab155c08a1c43cd17c110af	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1591045809000000	1591650609000000	1654117809000000	1685653809000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x08418969818c6045df54fc775e2a5dd4d21d27a0c2dfa9d32acb4320358ad484e5cb059808d2c96ca443e0ba2d3c7b4cd30743cd09faf79bf0ff825d68157a2a	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1591650309000000	1592255109000000	1654722309000000	1686258309000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x1494bcafbaff72f0153a396147b5afd000eaf35679842f2354d323a4776c81bf719204c9da7368a3952486a7bd3586b38c8dbb9ffbe6584b66c62861a0c18dd1	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1592254809000000	1592859609000000	1655326809000000	1686862809000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xda35ca53c7059ad284b87ee788a67621adaf9589c599b10d1fb84dc2bd8221f440655450b3d79b060b4369e664b2a3dee33010b6de1302e101395d3482f48f7b	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1592859309000000	1593464109000000	1655931309000000	1687467309000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xba20dd5c7d5c36c3e3d0e48cefeee8b9584722b90b6e3c4aa553f4bcd447267eb5e8428bffcf3a323d212c8454eec2c0449ea6f0feeed0653f2f455583ea7ecb	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1593463809000000	1594068609000000	1656535809000000	1688071809000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x97393ef7bc1c2f72b5055b47208ee52a8b8d21fb37b2d1186db30116ed319e28e8f2f602fe49c724ea0b73e8c5f8220788f214451f482708deb80e4cdff63ff7	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1594068309000000	1594673109000000	1657140309000000	1688676309000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x284f196ecfbe2fe82fb906147599564844402562a5b9f2cd6ddb3ac2e22c4ebab50158071201b4d2540cdd940c9d75089d1564e508aad6d6864c076a0908d9c3	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1594672809000000	1595277609000000	1657744809000000	1689280809000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xceae2d4775515f533264004e2c17f1136ddebeb555322c07ce0c488c39acd8386809c83bac023a080fd44976565fc3bee3dc2366acc6ddc4e807d65f36e7c7de	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1595277309000000	1595882109000000	1658349309000000	1689885309000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x195f39d02a0bae3b51bdf89000083872b6bea6ba37e37c4b2d41a2b1f01ae2ae3c42d24c70c13d1dbfaa6ac7d7297cf58f9ae358e46866d4c8a7e110f2d398f7	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1595881809000000	1596486609000000	1658953809000000	1690489809000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x8e327a45ab4f1dec8349aefe88ec82ae0d5c115a93c71b296e75b46be2e245196da275a8c9fa1cc38ab6f79aab4e023bdd917c76728944aa21924128099b4145	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1596486309000000	1597091109000000	1659558309000000	1691094309000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x1143ec162440bef9263d6d152443dbde72613e8a68ee35fd5b16ba92817ff457047be239e25bbe6e516c822ebf8e488734448bf9450b489cf7e1fbbfc2f3c1b8	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1597090809000000	1597695609000000	1660162809000000	1691698809000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x7b06fcbbb51c981fad9cb6909d69207d6ac151dd9714367e9d524afc9c8b01d4a8f6da4817fdf92af09bde3c86b0ea514e455deb3b8f9f8006c05548306022fa	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1577746809000000	1578351609000000	1640818809000000	1672354809000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4101811a632ebb2a57c02c7e304ce6b630b6297b648247d40047e9b4b8e715f29d23dc5c6529df48ae608dd158dde0f16db39e85acdb6a4bb2b31551f3f802d9	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1578351309000000	1578956109000000	1641423309000000	1672959309000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x093f5a811743e1d6fa9110938dd793f4f226e2db6d06c9ed9658eac243234f53e5beb4922a1930efdbf8ff382f6722c11c1d7ac0f13860a7160f4bc5e53d1a65	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1578955809000000	1579560609000000	1642027809000000	1673563809000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3cd3f787daca32c6cbc67d2a77f0077e30ec14fc6b3bbcf30bd7adea92052ac629fc07976e8f63edd59d365c9fc9b560a44a48a058f84560aa0fa7cd409c1262	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1579560309000000	1580165109000000	1642632309000000	1674168309000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc1ced255bc70c92a79e4b046aaa69156d70d09b31e4dbdf93541bde21bf9a4efa33893adcff55a81356d3c36f93ec0440a199aa8e4cea24eaeb958d1bd70d5d7	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1580164809000000	1580769609000000	1643236809000000	1674772809000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x859a49fb240633762f465e6cb67455ae83a0edc56060f936edfa2101a84a45db0f874bf7eb655f603986a431e6e5086909c52370f74e3fbe1bfe01acec8582be	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1580769309000000	1581374109000000	1643841309000000	1675377309000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xed7d45473c4013518c83a5d2f385cfe120f43c35b16f78fb0428c9e49313a7602893b4a9ef35082b47194cabdbdb4be359ac2f633d514f5909616fa01393b242	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1581373809000000	1581978609000000	1644445809000000	1675981809000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5b9203a1f6fc0001dee8bd017d7b862dd641af86763860196c2b138844112a4fe80e6ff1349ffa9ef5b3c22733b6bb84c2bdfe04ca9ee9cb7a2c4285dd7ff76b	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1581978309000000	1582583109000000	1645050309000000	1676586309000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9fc7c42e4553e7dfb6d807a11b7474a6af89c87be8373904d3db1c974ceb7d36732a70a2de61204222b75b3de0d39190048b1ebf176377816e94b3441cb6e63d	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1582582809000000	1583187609000000	1645654809000000	1677190809000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x66a17930ecbf587e381827c1a28ee349d0763c25f6c823cd5f35ae8970edeff1a95270bba1f6de29f66317c7c318dee371cdd3767c3ebe223f401c9925a4c4ed	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1583187309000000	1583792109000000	1646259309000000	1677795309000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xaa3e1e4bee315eb6acda7bb6a67db8eea2b84be6febdbe242850da653f8943fb707177300342d2fde4262dccaf4f461128915d2ab775a3c751477cfc88ec737a	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1583791809000000	1584396609000000	1646863809000000	1678399809000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7c84aeb58bc65026f39b4a0f7a39bb43272945aac429eeb0031eada9feb2e4a08985ffd912cf0a0e2ffce77616b39587fbdddbe0ffb3946673cf36dd8fe18c75	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1584396309000000	1585001109000000	1647468309000000	1679004309000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xbf6c13d689098ecd7f058851412610528bc7ab655f674ec02d6d5c5a29df2198295588d4167e8fa2af4f2f82f10b0e1d518473c1ea90be4060f9d1f3cd817c88	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1585000809000000	1585605609000000	1648072809000000	1679608809000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8da592c493aee2adbfa6baee70f77318d0479307a306418714dcb9043c5ff3653751c5acea6d829d7f452dcde85b9b99b197d7b9056f7a51eb2b16f4012ab98f	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1585605309000000	1586210109000000	1648677309000000	1680213309000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x176ba45531a8e59ef10c12697c09c45d6e1c58886cca3c9fd6bdafb906d174fd6696b0914542e4942d3a16ebfaa27c234eee8b149dca71a76686f943b6d0f19b	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1586209809000000	1586814609000000	1649281809000000	1680817809000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xdd1aa56a1a44feb124fd32358cc6cae0b21268c777355277e33e7085a2c891978bcc952659862bd8ecc062b021b5de6852df57aff03b6754edf75e209f7277b5	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1586814309000000	1587419109000000	1649886309000000	1681422309000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf55fd88af34a082afaac84f95eb08c909df1adee575b9b7dd7b57c6ce89abc2fb84f7f414e4c5777733239b2f29273a1bd7471712d2256672d8ebabb517c0ae2	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1587418809000000	1588023609000000	1650490809000000	1682026809000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xde2f28df994373232cec16781c49dcb8293abf1325be6be5b3aa3ad0326d5c21fc3dbe88cdfb0bfbe3f960b7eb3972c5f20d26eb6160960f37339ed3c66b7136	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1588023309000000	1588628109000000	1651095309000000	1682631309000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x50f724621e668d519dae9ece62f5d77dac70fc3f5da2ee5815848da9421f5de8a4ca6acdf1ecb64b6de8d9152ca3aff8fd42b57b179f88de2dc212690c3c5cae	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1588627809000000	1589232609000000	1651699809000000	1683235809000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf06f6b84046d6ec5d64fa00f12e2d5670ed6ec5f01bb852c3387a127f82c57bd52ad4f92feda4cc06ed99e0428be331f42b9b55ad94ff5ad6aa1a9d39178daab	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1589232309000000	1589837109000000	1652304309000000	1683840309000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x88345f6e3ea8d5e50e7ab0410ac80d0afd61489731fdf08a63e81d7a670dd1bbabcdf62da56affeb4c4db4f69d11bfa02ca3da5833d74102b72713b2f61e6f8f	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1589836809000000	1590441609000000	1652908809000000	1684444809000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9dd5532e8c8518dde155fd84ab7ceff4ccc5e805a95f91e31760501a71c93d65a383f53e769e66b87574bfcc5913c41bbcdf6a8192bb6b6512b4e3ec35e8ca36	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1590441309000000	1591046109000000	1653513309000000	1685049309000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4326c93bb42e243664f89988b2d64b5048d68a169a4d45248810d26045d47fec3c88c2a37ed647e5139c6058ffdd66e9cb842173e1e8dfcb4cf195cba2e76c02	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1591045809000000	1591650609000000	1654117809000000	1685653809000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0112cbaacccc958ef714b9021802018e701c2799e82b4c86c683384bd4240d4fe835a9dfc79be581905ec885c03739a9d505aa2c32c637d32b08f16ceb447886	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1591650309000000	1592255109000000	1654722309000000	1686258309000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1928d465f4a7ec92ee981e72a6cf9577f69a171f1348753ba48ebafd8647503035e81a60ada9c67ccc9b5ce8ad50a96fd4cf1e59182608492638a6f3b68ac191	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1592254809000000	1592859609000000	1655326809000000	1686862809000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0c8b69aa6d09975e802dafa823bf782b0f8fed643e84ac9ce358aea1ae333c172e2702df3bedf6b6f1e6edb2abc93d97b8e5092047a50a06322a33bec4adb459	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1592859309000000	1593464109000000	1655931309000000	1687467309000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xde8ab5aa76975e751ac660f42df66d40592a3b18ff5aff154b12935251cb9c09910e29de46a28951e77a99b38da050d4356ecc5868d0da0533d4cabc93de0f89	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1593463809000000	1594068609000000	1656535809000000	1688071809000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa43ce039b46b7ff4c5b9f1234e06e4654c6d13e230a7025a7d02f47f98da170a3001d05bde4378f8893340fd6b6e3d2cde8883e7e031cded0d9a94a40b66c1ff	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1594068309000000	1594673109000000	1657140309000000	1688676309000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xcec9b453bf960f5b160df892e8fd3db0665780eb80d3bce6cca1a11c479229853d53a5817666a1c4d95cd833f7703a9e622d1855d26148ee4cec9d6a121f6755	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1594672809000000	1595277609000000	1657744809000000	1689280809000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9f2ae2b28478d0c0d9ec623b0faed6d741f41c95289abaceb8abbab8543c1f3c36bda7e69e2b47d193c939ea0d0d4d880076b84e44fbd79ac343c5a423327e97	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1595277309000000	1595882109000000	1658349309000000	1689885309000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x206b84505c16a1d4cadc0df0abfc689c1278aa671551b8803347bde5e21a330fcd707f21d58ff361d26c4714415d598ca0fd0a2bb0b6bcf64f40ec3733f78ca3	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1595881809000000	1596486609000000	1658953809000000	1690489809000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x29e05fbced8f188fdacd6e80303002c5a26e19cf809bf087e1c3b281e20d88be118d9d888a114599916b5608bf5ac6d128f9ace1f46310cfd30839426a724503	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1596486309000000	1597091109000000	1659558309000000	1691094309000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe3256d9d34896d9beef69ccc2cdaf7509950ebcd21d777b5a11f8cb9e156d43e6f9bdc4f730a6e8dd59f5e9ca7273508753025dd39a84e283866bc00c5188cde	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1597090809000000	1597695609000000	1660162809000000	1691698809000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x670d3b91a68a7996d41995040ba893619a55336da491ca17b900c282a6d1ee411f63881a8bac146d942024396893a06c11b01127ecc5d44817ff4658a0123d67	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1577746809000000	1578351609000000	1640818809000000	1672354809000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb314ec9f648ba79b5b5c1b4dbc46e0efef548ea30ebdfe129d6a0c48555fb44af2ca58f1fcee28aef35f0eab4db03777cbefaa0901c63e946ef96f015cf3a0d4	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1578351309000000	1578956109000000	1641423309000000	1672959309000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xedf319f8048c799baab17f4c4e4631a6b4d99cbd88fd3800a99efd583685a9a3657a3f9b01354f66713ece119a7ebcfb9f5f4b456250c5a7162884282c646dd1	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1578955809000000	1579560609000000	1642027809000000	1673563809000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8789867d368f9e95fad9dc76b1042b7b31f3b66dca59fd344be24f13765f086d9adf3351e79fa12c95596c22721858a5333587aaeaf42663418a95437dbde102	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1579560309000000	1580165109000000	1642632309000000	1674168309000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc56a7b9474c7e6b67768910264dcf81bb71d3c76219e78e4ece12143ded6073b0156f8ac1f3b4c3060a4e71a8ccde5c683b40b1221a0bc82073360ae6eced82c	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1580164809000000	1580769609000000	1643236809000000	1674772809000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5a0b3b79c6e10cc080bacbc7a9769068e8fc333e541c838828da8753bd955165cb058c18c077b96baf849348ec5d18275f8dcf5836cc98b7ff357ae54b63745b	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1580769309000000	1581374109000000	1643841309000000	1675377309000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6b6dc4e9cacf92af9e82d3726a79907c212b4fbe89753982a998970b7a66dea4f4321433166b6150e45961500862801fb7263cee363bbb346b66c2ee1c1840a5	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1581373809000000	1581978609000000	1644445809000000	1675981809000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb37138ab5874bc542ace09d9937c53e866b33671fec230670ba1ab7bcd032d4a5186cf0d4a0c376f0a948faa819ade6b7ceca381fca6f74d3b2118f211597cbd	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1581978309000000	1582583109000000	1645050309000000	1676586309000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7dc936fa99448f75a2deb0bfa72f63c6a98b926d0784759f89f8768bcd0a72bdad00a29751f0d57fbf40ce4280685c9a97431e4a45982b86ad4d4c2c4a8640bd	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1582582809000000	1583187609000000	1645654809000000	1677190809000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1996ed5e4c68aed876e7de1dde94a8e56a8c05641973c68ce0f5c47a3823eba5e2658299d133894a7b96b54af7f2d8ceaeb82dbf16e6b0bda597ac49c48ebbad	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1583187309000000	1583792109000000	1646259309000000	1677795309000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x0949b4d9e183908dfb66dc8a5829ff7cceb218a6b23a4b9928d61e42914da2e07cf6242d4dfffc80503323a8dc1b7edfb31fb5265c14179735936c2acbb931ac	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1583791809000000	1584396609000000	1646863809000000	1678399809000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x24fc9cce41bc46878e78323b4ee4d2631a318e4b4ca902d5d279f29f64d5a8ecd3fd215258c913730ae13e6d80cc9357e34d5ee6d2070c3be3591eb0a280a07d	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1584396309000000	1585001109000000	1647468309000000	1679004309000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x38baaf83c322774e33c1f26f795a430eb01de9df626731b3367daf216b9e5d2711781c226b0750d5240e19c2b29804c728e052003fe2ee2c67b8b2d324eeb702	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1585000809000000	1585605609000000	1648072809000000	1679608809000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5567132d522aa362fae5d99bae58ae90a0f709e26e9d6d6e9b37a3b5a64a95c6b8ea867a6f6343f00867d97e80856b05b916d4cf481ac69ec47e36bacad1c042	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1585605309000000	1586210109000000	1648677309000000	1680213309000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xdeebf636fee3a7c685b311f99f520e0bb33c2145db758de523925a47c40ad406abde05aefc11566a9bf526264c99b7ecbb3e09f33a846a8eef3df18004101e12	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1586209809000000	1586814609000000	1649281809000000	1680817809000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x16038eb4873c5e70bb03aef4782ffec586c4af2f10f8f40a9cb24e00aa567ec1c109ae88d17db72a1145118a6111b48f64fffa4b47d3e3019d58b30cd4508d01	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1586814309000000	1587419109000000	1649886309000000	1681422309000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xeb7e58700600a42cd68ed8dcb0df737e1694bd1c03863463c0c4a94b46bc04061c92f4693e75ba1b85c98d6935ea151b71bc7b370be00efb17ca7c3a0c2d29e0	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1587418809000000	1588023609000000	1650490809000000	1682026809000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6aa5556b26fc5750cc2dd884d6096a604869a498fcfccc02e4939c8df42a6c8acf8f9b7fd66639d14b67e6653282c2719e839b7035efbc9a6f7823c77af75ce4	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1588023309000000	1588628109000000	1651095309000000	1682631309000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9aed193df4467616e94e6213fe3d44962e1f7597384ac408a364b5773a4df1e10b3ab57f60c734607f5f9ac5ff9451e735a075180beb91d9d764b877dc3cc732	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1588627809000000	1589232609000000	1651699809000000	1683235809000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8f1b30924dcac5db5ad9b1dd5feb8988ef99015f40a76b180b0f64d5c07052c2e1270d8b5c1db38c2fba999669b7aa8da8fbb3148b43f20a874da61a3403006c	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1589232309000000	1589837109000000	1652304309000000	1683840309000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x87f44de6685e87e30b8eed84088badc3f2269c1f636bb847450eeb08fce669ef862000c85ae43a4d441be389e556b81923acf9fb0376a91006165cd7eb39ff4e	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1589836809000000	1590441609000000	1652908809000000	1684444809000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x65e399cdd7d7dc7fc3b1239ee662a212e238d71a85d26d7036916a607f2c6afff912dd9dbea746f06220af7c46e61a9d2cc09d053c88b65d0859bd07f8c76d2d	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1590441309000000	1591046109000000	1653513309000000	1685049309000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x3dba963b4ca29b5c6d27522ed31d3dce261447ed186dbc8d59498b955f2bbc393568b20469bbaf8a2c1ec07c7c05b1238c3b62fd98ed9285f7a07f8bddaf55e5	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1591045809000000	1591650609000000	1654117809000000	1685653809000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5bf0c612a9d25f4b4a9131875861383be20b8d38ae82145f06fdebbbb197b7d4113eae35fdf4d8c24d457aa076698f3c1feb267f235f64715e15f704edbd63c4	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1591650309000000	1592255109000000	1654722309000000	1686258309000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xbdc8ed400e2de8e7136633ef13bc36ac6d90588f3e4d754827be4a17843cc1a6090bb5331c190e740961e8f7ba15206596baec4b4210614757ab1a510ef055da	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1592254809000000	1592859609000000	1655326809000000	1686862809000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7d55da3a9f2e3e5212ad3bc927a243b78060a91e97212be80bc449006b2812111f2361aac53d0ed344e88a6327bb7836e909458f9e6178e8824c2e9e6878eba7	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1592859309000000	1593464109000000	1655931309000000	1687467309000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x77b3e4e015c6607c62c86d16b060a7b7f76a4fc9ce6ff99f6de08a471ccca7a7533a5b19c2e9a6fc397c8dbe3c054f490b2348eb0a3b4baa9558a8ef63292943	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1593463809000000	1594068609000000	1656535809000000	1688071809000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa55537a07a5d836db97f1fbd73366bd4e7297f98f5aaf58931a2d123cfe4917379ce41e9a2b735614b67d6849b99702e56c09b0b2a8d7b984eda905d6b0b2264	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1594068309000000	1594673109000000	1657140309000000	1688676309000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x062728ce659188a9741c831100318779376ec8a7b84840c28865ca9c4a74bde4a985a7737f7e558566fc47946bd5edffa5a50c04c2861a15b7e96f38bd7a0c6c	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1594672809000000	1595277609000000	1657744809000000	1689280809000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8c3f9a168ef794cfe2254f4f743631f81257a111e90a0abb0a1cc4ae3981b8a9d541abbfcaf56663e69ff15b301762c71e9f85f0307c134fc37ab45d9cb3e4b6	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1595277309000000	1595882109000000	1658349309000000	1689885309000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x116f8800684ea0529990f53baa4c5c3a82aaef09e3161c3c813d6a2d42e04f585cfda97be8520e1f4c1f7422ac67a8088be9b0a34577eb0d347b5e235eb9ef3f	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1595881809000000	1596486609000000	1658953809000000	1690489809000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x0ea386b9ebee749c2642acec4cf6bc0bf9fe446057ee4f9b49c8ffb8227691f8de5f3961cd3db7c122f4c773f58c5edb61e0ce893e674a8df16c571d0b410d31	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1596486309000000	1597091109000000	1659558309000000	1691094309000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x3302dd981bdc444c8089b89ab563ef02462de6712acb1a01998dc7442f639f93f8d2761b866a92e5f7379cef7636c4be074511e8b6f2e0a464636696dcc92885	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1597090809000000	1597695609000000	1660162809000000	1691698809000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4a9fda5b02ee10e9c98f9f426888b89826d724c9f080e0cacd9184e1ac6a2f03f74990611e6bf26b4d714719105adda47d76abb515a089688c667fc5e2c743a7	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1577746809000000	1578351609000000	1640818809000000	1672354809000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x44894e8aedfd8b94156874c1242d32a0dd494c888427efdb95f906c51c2d10e2d71627103d373b3093c68a3fcd82d9a9c0800f2380553051ac520fae24f1a02a	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1578351309000000	1578956109000000	1641423309000000	1672959309000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf0fbf20669aa00fd8bb251456b8e390ef4c39ef6bbb7198384a17f4840a39fe4b505930e02cb30d6e6eeeda135cdd4e3af46e1b883414bba2f3b1683f22ea787	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1578955809000000	1579560609000000	1642027809000000	1673563809000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x03e0a031e28a82ae71a1eb6f67785e8ff3452fc7ad750f00884787f276e85c446cb5e4b5bd2b007eca45753a4e8f9eca73d92c54ca9d84c80ab5e98bcbd2274d	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1579560309000000	1580165109000000	1642632309000000	1674168309000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd8cdfdaab2269770c9f258106c7cc74d671e962a2517ae3b4200b37bc1d212d405a5ad6b1da6cf95f0cb10829fcfc098c87a596405fa2b64a024c42d45c0595b	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1580164809000000	1580769609000000	1643236809000000	1674772809000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5677b8f8e6cd1c6914e4ee1c81bcb4d26c3aecec2938c06d6c007dcb3e41d97a4e946945c08702a2badde381a7581c2b5c92cbdb28cf76d9a819e6eb0bf0f086	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1580769309000000	1581374109000000	1643841309000000	1675377309000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5be970e16232655db5ef520e9353acbbe9b6554a19aff86c4eb51f0d3b9331327111c87b3a10a2a0e906c2bcb6eca6873f5a6e6f85492dde3eb6d8165ce8ff93	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1581373809000000	1581978609000000	1644445809000000	1675981809000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf8a8a9375b235709b542205f2d22c5af6baac266d78fa8a88a3a7a4247647934daf771136b82f5e11c12350c8e1fd027770976ec5f4555bb17c2fe6ea62c172f	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1581978309000000	1582583109000000	1645050309000000	1676586309000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xefab5b9386561a6d75ac6b9c928743022d67caaaf1af923e26576f71f64e7bbb3b737dab7aba4ba2be9ceb57057b9382ef30e19fe4004f020653eaeb34813eae	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1582582809000000	1583187609000000	1645654809000000	1677190809000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6ef83ceaee296f06a4222c0555a76ebb1aaf3af647a0518c8e8632c549670f83b28711e1041c84f7a89d98647d1e59894f35ab3b790908befc5dbb64b874270e	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1583187309000000	1583792109000000	1646259309000000	1677795309000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x80e8667e76163fd061231eb1b70603c39445b663406e9a3479df1143524f1e312aee74bcaeaa00bc865a57310408737d50a75df0011a40ed02fd55ee6325b0e6	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1583791809000000	1584396609000000	1646863809000000	1678399809000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x95a78ed00c716e82afc333262e4de6e546ded2e2e845d373031c96f19565e8a2b1b77bc4b6aeaf7dcd5c74778cfa300269187b6e1cc90284cebd78514369cbee	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1584396309000000	1585001109000000	1647468309000000	1679004309000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2700bd06df387e65bc5ca31b5960c24494b758cf9ad0c652c9ac01272d2798ff3b6c0ab07b30f4afed1cf3623fb02addfc1c39df4848a24be2369d3a16af636c	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1585000809000000	1585605609000000	1648072809000000	1679608809000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5a95355dab181745670dfa95213d8c78e6ae24f7bcb966ea1873af1003f5cad5cfa6947850129eb753eea24c2c7cad57c07f67942316c9a2ebceb31abbd2a9e5	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1585605309000000	1586210109000000	1648677309000000	1680213309000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4c42aca0be44af7d6e2ae6437b15697b360a5e5aef23e08a3d254693f9fe06e9f3c6a09776bd73e2817f85d62ba1fbe5c2aec927ba3d89b459cbd2201abecf51	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1586209809000000	1586814609000000	1649281809000000	1680817809000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc73e38f95fb713c84a2b27e5439fe0e42b534c4fe4cafd2625d2a22f86c43b6899cac2bdc25889a3ebff21b1314c3e936d85f2c8106267e9e0a1fd2425eec17a	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1586814309000000	1587419109000000	1649886309000000	1681422309000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x10f86aa95aac90fc51453f28e47f62701c9484c15d0b1456be732fa47d6df5cf8ae03c514642ae10df672ef4f3ff7bc6a8bc0dee955a835d4411328dcc26b939	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1587418809000000	1588023609000000	1650490809000000	1682026809000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb1866dd2793fb32417a5ad970fc9b6cdc0100bef6f78ddf08edab778ec959639a49b8e607195acccab82e4ebdd26f5fdf871fc55be59d40650d9423ad4ab175d	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1588023309000000	1588628109000000	1651095309000000	1682631309000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc52e546d3753efb449726c6638971d4f0914a86cd032ffb3ed0ffdd6bbd10dcf09dc0a173763a7fb9c796495891b94e8ae7e49fc76818ef4d8911f2a9eaca807	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1588627809000000	1589232609000000	1651699809000000	1683235809000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7cab3f8d5d39fb378ea94785421c6c902010172e14960267655e4cb0d6176918318a05053270038cc7947d666f11c32a936fcb8c8da58b158bd618c1673611d8	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1589232309000000	1589837109000000	1652304309000000	1683840309000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf2b768e7ef4fc74288bb5cf2e7751bdcafd67d90c1e220216c7f3ba490bfd7d0a7f0b482d57ac0cea95a1fddef8c441f6fb49f405a793a75d550685ec1c99513	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1589836809000000	1590441609000000	1652908809000000	1684444809000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xad140d47208606b71f5dc5e12186530d25a7843d9aa1b2e697cf77e2e944fe7f45971b9d17989b574af8edb6acb0126e0a325d51a9336c5a52f74d3c818723cd	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1590441309000000	1591046109000000	1653513309000000	1685049309000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x95e57f539a39497ea9b55357d5530fca69395f0c8d2a4ccb2cd90789420a56f33dc6a0e8a87886686a0989efcf7c8ac2c0499ab8a07caabd3bc87581b8b53358	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1591045809000000	1591650609000000	1654117809000000	1685653809000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf7f72937aa01ca533cd5f971453296f670c5b72526aa13d50d28993cca4719f27f6c5ab42a42c59e9d509926dde9cf356d763d00d039187fd1ebd7ff0554e2fb	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1591650309000000	1592255109000000	1654722309000000	1686258309000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb42a8ca3e1eaae95fbdffa5d22f66ae11e4a3c7206d9e4009f57f56758d999df3712d27cb5f9d258cb98cfd155a5478682778eadf82603c4492e1aff2ffb2428	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1592254809000000	1592859609000000	1655326809000000	1686862809000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8059008686b65c91c1e4838cf8debaf036f9f86817a4c9a60e1326ac5eecfd516903ac3cd9204aef66d33b849d486188fea2486074239b66eacca08e6f2131e5	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1592859309000000	1593464109000000	1655931309000000	1687467309000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1277d9b8b8eb802a1fde0e29aff90fdf910ef57fa04b2d8454fa3c698a1ee60324883fae05a56791f7986bfbef6116673102292bf3f40bfe61f2caa805a18eab	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1593463809000000	1594068609000000	1656535809000000	1688071809000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc923ac92e91f0b0c5fe130f4e14144961a6125f6aed84a683f90ecc1debcd6cf51c18e9259711d6061c9802110fec73ad48d11cd3b0d4a431819feee8141dc14	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1594068309000000	1594673109000000	1657140309000000	1688676309000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8bd6c4f5f74851240e9c8143a1465c1cb253d41407dc6c1feece6bb10eff3a9dac6cedc34b52beb2af6f83e35eb4890f754dae0bd2dcb31e455e1d86addc49f7	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1594672809000000	1595277609000000	1657744809000000	1689280809000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xbb08c17269e091bdca66e34237843b2cd91248d05ef4b1dc6d00ae175ca59dfa441f7f272d3e5cfa468d23d46d53f0b8658907029c416a824fc856738fd5bc7b	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1595277309000000	1595882109000000	1658349309000000	1689885309000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf4d2a3a0a0ac377021b08b035ab12b3f5bde0aac92c15232d8d657cfd6dd1045d99afaf2040e1aad36b5482b64533dee8655f0b789128e6b20b923625ca0f64f	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1595881809000000	1596486609000000	1658953809000000	1690489809000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x038781587408037d9c34f0cb4e522769f5a12d9d32aeea955abe8aad85eff81e463e599d514b83de6c2c63ff35764e0f055e281a398c51a8f3c60e0e0e2586e0	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1596486309000000	1597091109000000	1659558309000000	1691094309000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe6a53bf5ddc905624d5186e0a53ba15bb476453ae62c40b5da9c2ee35d42ac0ad612ca7c297928da8254aae3f171a5277db9bbb3c5cbe131cd1934e062ce952d	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1597090809000000	1597695609000000	1660162809000000	1691698809000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6a59aa868a47da4fe4e8da0ede7874acef904a8fe383fd3b977a95c69c3dd52cfdbcaf00c7913866803050fc1963d7598f5f3a864ea0820088e2f4a5db878688	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1577746809000000	1578351609000000	1640818809000000	1672354809000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x9f3c6cc8c530bbab6c23522ecbcfd1be07d4827bd617109d4e8a8e4040a1f091fccbd3b599a0402026cc22efc4fda52526d25009b4f743fa939025e075b3ad84	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1578351309000000	1578956109000000	1641423309000000	1672959309000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x7ca89ac078ae3b893652f3f35f708dd64e0ee2987dc60780bafe0f9eb4e98a158fc992c530817f47511fd4beb39aa754e9fdf4b8e15dcf9dd2836545d397d48e	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1578955809000000	1579560609000000	1642027809000000	1673563809000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x2c018f6042b1812c84307046fc570baa235bba1df8f9f0d09f05e3511dfa57c7c6d26b50f874aaeccf5d299b589e5ebe835350e89bb913cbbf773ebf142a4bff	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1579560309000000	1580165109000000	1642632309000000	1674168309000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x31f95dd77ec48eb282de029465be7632cebed869278303c2c0065a682fe20670b82e06e16cd269a36d2a946c1c7f11a77cbf4e1d6ea2ef553fe34d51642fb3df	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1580164809000000	1580769609000000	1643236809000000	1674772809000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x4716bc4af3de500901d23a3d53998b9c4b10df7f1510c757bdadd5644c0ffd105625496339811a81707abf26c27e121ab9d83a7ccd69d6bfc2a028c2dbc76e0a	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1580769309000000	1581374109000000	1643841309000000	1675377309000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x99388eeef4d38e2af79030500e930e916b2490e07a7a97d4fb7d160ed5c052d8b8ab26568e95d36d1dd5b2ddc4d254b07d8bbb7fbce54b36e9e5b54f1ba9e42e	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1581373809000000	1581978609000000	1644445809000000	1675981809000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x1e81035be6b7b8aab6dffc0d2944529aff90c4ebc50d11f00098fe0c32a73a3e3cc8b9fc7e8140e3f97409def683be06940a850f902905c07cf6e52909d602c4	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1581978309000000	1582583109000000	1645050309000000	1676586309000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xaaefc6b259a724a58fdf2a5395c31fabe20be5a4603b8624f3d73ac17dab0fd0a7da15047f4e5832decf4e386838399cab844569c0daf52787f2a5de3abf5096	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1582582809000000	1583187609000000	1645654809000000	1677190809000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x869d68a59cc59b10fe87ae9dc70e28ab93ccc7930164de6f1bc15c965ab67e9ba694297945cae4b25dd4ab5183da51b64dac8b50de7dd69f65ca2539d254fc40	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1583187309000000	1583792109000000	1646259309000000	1677795309000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xa8ea8850737933f123fae9343d01d2762d5f2eb3ff03caf2fa9dfe37fa3fb223711565cf836b7c26a3ecf43a0beaf22abd98a17fb523b165bb3da91caf93291b	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1583791809000000	1584396609000000	1646863809000000	1678399809000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xa58d02e698acc93bd24998d6ebf16a74bd0b6b1c609c9174d84488e442fa9f0eaec29927c286069cba9b3c568ee20b70cc4dcfad122510a18be30c228be77c04	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1584396309000000	1585001109000000	1647468309000000	1679004309000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x2b8d6e9b26cb7dfd0e2b2982317f69eb757a695d1b2243b39db316e4ab14d81d737a14267b8846d2782c39a630b28e7409c7da7fadce503fd307dd119bc48441	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1585000809000000	1585605609000000	1648072809000000	1679608809000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xa1e25c90ec600e9aeb3211ffd00add83b582c6b51b3223355dfeb723e057b68ad76788534c7a2ea3e8ec361a2f354dccbddec6a0b9aeaeb7488c53160c0eb3ff	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1585605309000000	1586210109000000	1648677309000000	1680213309000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xa5a053f8092e5623f1c92b20750ef10044c77f01b8fc35e44b3093b12cf404bd62b2babf390439ca5661a12366bb3e085390cdc3f8c29e4270516e98efda9450	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1586209809000000	1586814609000000	1649281809000000	1680817809000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc48b098dd645cbbf5cb10bbb133bed58a1c6be23d645dd8e2ee2655cc143958c50e02004ed38f92cd533b583b2ffab3428cd55c81d0e6d071d041487e802e17d	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1586814309000000	1587419109000000	1649886309000000	1681422309000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x4b551470f8b43794eea3547c2a21236de1a95e5348e933832066263749bf6591bd98cc4d32f07e6c7f51d61d154bfb3d477413a7f641fdd09eff3a235fcfda33	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1587418809000000	1588023609000000	1650490809000000	1682026809000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc2493adf1b12a30ead77a0839d6f6637efa6007352b4a3c4054a51902b7c52f4a58d257a6a4017901c57561d56d81d0165f8c7f129c112d152ac5c22dc8f02a7	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1588023309000000	1588628109000000	1651095309000000	1682631309000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xae2a5768c149e25476c40b334cc0ce1abd0c4035825aa34fd0d986f49d6caa52f068ebae47134df823ea256361715893c715b85708e470521324115e39bfac6b	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1588627809000000	1589232609000000	1651699809000000	1683235809000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x450beb6fb91557062aef66f8fed44fe697113bc4be8ef9d74f29f1ebb5849bdec23162a5c65e6f5c977a11ecd2f859ff66ef73474d68c115b2596a0a10b0babd	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1589232309000000	1589837109000000	1652304309000000	1683840309000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x6246201b9acaaf6d9cc5e809dedd792f43f19814f83223acb9ee2fdf8197f8bf32d440da60c1cbbc25c1d2be94cb1b80a64ddc1102dc8c8c6193e18d2a66959e	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1589836809000000	1590441609000000	1652908809000000	1684444809000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x910b15eea21f061ccc8c100d244f8a9938c218b81d973b696ad3faf1a76a945ed4e5425ebfd73e42d72c28083250535816616cfcc84e7904bfe92bf5d7f273f4	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1590441309000000	1591046109000000	1653513309000000	1685049309000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x6e6a7b33d0576760803c368ef152ac3e68ebe28edbe9278cc4155e1d12e5aacebe5c1b2b92983ba0dc3a804f3865cc8aba9dd2f430c9b0715face03a1324498d	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1591045809000000	1591650609000000	1654117809000000	1685653809000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xb7de049d74ab368463b7b2f1d86832f86f04166555467d86e6be37aa2e5a7f8a144901280d01adaae86afb5156724a51e100dc8b881a8640bd0ef2ef10091f31	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1591650309000000	1592255109000000	1654722309000000	1686258309000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xe422167a673de3274f5c04efc50aab1ccad77f0b7c21f1bbe08b3d0e8295c9243c81b3070b8251916d3f2c6794ee4761c63462e15cd9278e9a7225d0b738eca3	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1592254809000000	1592859609000000	1655326809000000	1686862809000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xe345c6722fe4f24509b0ac2b4277ed03ac1fccf6ecf1d6ffaea81e098ce875615133d0b3f4bef080cc3e2342749e6fbb65dee0667c41ca305c3fdd0686109ffe	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1592859309000000	1593464109000000	1655931309000000	1687467309000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xeba91f1a591ab1fc6fdc834e6f9ea31323fc15f227f219792421bb743c51ea386908249c5d06f321a331547d1a4dac2a0f4b924bd72fab644caca55d1b5b3b0b	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1593463809000000	1594068609000000	1656535809000000	1688071809000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x91b2b990918a98cc0aec928c34ab1f20baa2299081ac60a00067f9d3ecbacd8ede8269858e37253b7450b6a30bbee8e9f8ede7f6d624acd16609184dec89e7f2	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1594068309000000	1594673109000000	1657140309000000	1688676309000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xa94bb55c9c41abb3b23cd4b8682cd6d5ff51473491c0b5bad2db7a73ae1e76393cd30e89c4b5506b09f91fb17f5a51eaf8b34bccfa6d68b7f1213caad81677a8	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1594672809000000	1595277609000000	1657744809000000	1689280809000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xaf4778ae76b407341a45a3a6c6543bb6ed45277e331bb96766170ea911737e3d91ed442f6b749003c080416e10f8ca609b7839855d0cbed257d9ddc19940c2a3	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1595277309000000	1595882109000000	1658349309000000	1689885309000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xf8b7228c0067113d237f075d7a4ddfdc56e62b786d152de359536ae9d3529af37068679c45339660ddf7e06cda7d06c30b62a55307ffc3276b57b92883768093	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1595881809000000	1596486609000000	1658953809000000	1690489809000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x3fe31a2aee816cd170c45f4401c8391f0ded999c1306449a640811d6ca54a2ac86d3aff5251baf8f619b4ccd066ef8c5c9203ca49bd48c8d62414728dd411037	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1596486309000000	1597091109000000	1659558309000000	1691094309000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x7306b953d54dc3d3aaee7572c955697c25d4951554c8a8cc6b30a7caa8ef9c9c199e79ed474f22e510074115b00016bd5afb5cd8813de6a8aa59d3c32ab94aaa	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1597090809000000	1597695609000000	1660162809000000	1691698809000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xe365d5ba3eaa89c4456f3b750e85ebe81978cc51aaf511b76875d60353394ba638e1fa423bcb16d9d0666598ec8e8baf053a97f679c58f8f2bf9f31c0dd702be	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1577746809000000	1578351609000000	1640818809000000	1672354809000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x8f9655b73147098bc7238306fc049da173cc00f245f6c905fcf9342dbd4a76ff91c0b377a327baf54c222ba87f11180d9cee111313768a044502d91568288f48	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1578351309000000	1578956109000000	1641423309000000	1672959309000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x22620a15333bc2ea07939573d90061a07e164026d495992f1b8c995b94753928ae3732a4481aa81b8e2359f852e41b52e24e0cde04f178e2c8a5c61adc05c136	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1578955809000000	1579560609000000	1642027809000000	1673563809000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x4726681b66263e08ed143e6154536fbc5ce5a9e600ca3f9a0594abbd943e62e908b93c5de2247948412ca87fa8ef352b303f6f74452e8177946170b6a83fac39	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1579560309000000	1580165109000000	1642632309000000	1674168309000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x377c01dd9a8e415f9559a556130a328bca2b64c45ce53e81fe2aa167ab38d86b72928e6f29336e1c0cb5b18aed3bf42df102a4e5b64a3a744f53c9e8b9eb88b0	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1580164809000000	1580769609000000	1643236809000000	1674772809000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xfb3f449ae82627bbe45fbf192d7ade0b47e95b1cb480a14b72599bcdafdabc2f0cb80b81aaf8a3b46d8ff35aafdfee90ac1a0d31650e7d62b97cdbb2984a8500	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1580769309000000	1581374109000000	1643841309000000	1675377309000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xb58ca459cb6437277850007c657854114c62c8f61a789571e401005ba755744a0523f0aa9480e88e3149af3f74cef35e0cb93cb19228ad7566949ddb0ffd313d	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1581373809000000	1581978609000000	1644445809000000	1675981809000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x5fc5aba5bf154ac0507b9783b0a92635d7e5e61330424044b7595a30ba7df219b87148c7e914bcb18669e87739bd0dc0c32728c6226b65919f6e477511070098	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1581978309000000	1582583109000000	1645050309000000	1676586309000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x6271f46aa278a9bac3533162eaf4de8f9031c88a6354649ccb4fad8bab0b8206389bf73438ba759e332e453ccaa148e2f3f859f910ba3e8df2b01aa93ab8788e	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1582582809000000	1583187609000000	1645654809000000	1677190809000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xfd5d3e0ea751a898787695202291ffcfba5db0c88451953157183c2cfcf5f646602c05b72c7c72200ef102a1552cd7eff18e7e09a42a089e5499a8c7c058fe33	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1583187309000000	1583792109000000	1646259309000000	1677795309000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x87869b1f3da37c0425a011ae58c60d09570108cce8677735e0d99d324007ff435093e9eeabeeb286b60f168698e54749a67ced0774e7232b2ad523ce2e244aea	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1583791809000000	1584396609000000	1646863809000000	1678399809000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xfbeb38709a97ec8fbc257f5e82ff0094f034a9cfa17c8dd970f0ad2d148c04863a5a331935ffafe73663f4f4dc2ab183a07c80cb4f10461e4282d19b965e0784	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1584396309000000	1585001109000000	1647468309000000	1679004309000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x65aabc737646026ed7cd49b7f236229e410f2a209d728fca469c17ccf624da6464ee0787df97d39fa1473975de5b4062d3ae0b7d2b380b8beee22e6651093c1d	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1585000809000000	1585605609000000	1648072809000000	1679608809000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xedb2a1fa24fe1e9804a9151abcfc49a6115a547d87ec700d3a0e5eaf2c78e83c90f9ae11630c6c627c0d255333dd5fbbb2ba781ed5a8770cae0a7a74870ade80	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1585605309000000	1586210109000000	1648677309000000	1680213309000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xe5b14b0bb0be835e074b3b57c4807000ff8a1e9a1b72a42e8948c906bfe0a7b01355c1d5bf7eb06d03e73c89f225e61083c49a5e10e205a4269bd6af65984772	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1586209809000000	1586814609000000	1649281809000000	1680817809000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xcdcda8673ac41211c43d6f6869db133a893984d90996764527e7f2099b7b4c17433213a4c3dff05f15811ed07fc98d241779762762f422f183945d968f8b4e8a	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1586814309000000	1587419109000000	1649886309000000	1681422309000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xd0d97c0754f003e211705317cc8dd593791a8c3da94440179d9e5114fa7f7bf6e7fcc3612538bbbc94929090849863d07509d9686ee48e33e77d02487b5eabce	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1587418809000000	1588023609000000	1650490809000000	1682026809000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x9cec47e402a3a121ee97078ba45d9e8a28db14b66a340a8d928b5fb4c6cfc63eaaea9be346900f5a8ef24b567ebbe1ca79f67bd055839cd4323f2af345db6d3c	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1588023309000000	1588628109000000	1651095309000000	1682631309000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xe471a8bf2776d0da7fd22612f5191c0adf49bdd92302e55adab96a50da76ceecdc357e318d4c6cb685fcadfa84b96e6f7c5c86a1efe0e87344de5b1822704d51	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1588627809000000	1589232609000000	1651699809000000	1683235809000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x1e512e6205cfb6516f1379999263a8600468c2f572f179e0154f4dbb8c1d329b46d3f3705b8bcc3e7aec7c72762898dd473dca53471352f6c3244e0e95db4974	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1589232309000000	1589837109000000	1652304309000000	1683840309000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xf6542c6a70e0ab773770021f0d95db330359ce0f3ab70c207dfa36667f39ebc2ae3fbb4f463f13f01b892a65f046d3f6ca132ea69922968d3120b982c5be3ada	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1589836809000000	1590441609000000	1652908809000000	1684444809000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x4f384beb8fa46179e85c119a80501518af9854c28c47c39ecd0959c86170708152b6b4fce8a5fd7dec9e27e1b593b4a956efb748eeaff044d69f3e991d7fe419	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1590441309000000	1591046109000000	1653513309000000	1685049309000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x2d56286909b2b501fdf07c3f67931ab07f0893857a3dd92e6279a95e06d39e68746984f02c9d25ea8a1ba49c9c954dd312ee5f9dc0051b57ba093125dce01ce4	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1591045809000000	1591650609000000	1654117809000000	1685653809000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xea96e47583d271a6ae895a83f295250db0d74eed2ed009ee0e5eb3184b73bd6b0a6ac821a5f9ea9b4496830740367d6d88ce39a26886f057c04542ab3e8b518c	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1591650309000000	1592255109000000	1654722309000000	1686258309000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x954903ef37ee741cecdedd8478b93b8a9ad0e705e59225f20ed21c3143a8b1b52eada81c3a1066eb81776f5fcd033cb1c84f9e098e59f252a46a4680ab2b4a6e	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1592254809000000	1592859609000000	1655326809000000	1686862809000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x9a8ff98a79b7468920dc259214d625c0366a9dcf7f976aa455181f1fdbcf5843934f3ec249734d683f5271409b8e02724429d5ab9a932ee6a4a879b920b1c4fe	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1592859309000000	1593464109000000	1655931309000000	1687467309000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xcbd839f742628a07d7636505057556c41e575f0c5c42e8df78d56dd2ec819c6a5bed7abd748425c42d22055cf14b2e123a3b28a702c3c78226520c9dc0cca7d5	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1593463809000000	1594068609000000	1656535809000000	1688071809000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x7d181f7900d3b141b23f504aae6205c49295afdace8e225f4779a9f5c8adf03819eac6bade863c8b098cfba7eb351abd6d62890d9e3086656a4fec4deeb73bdb	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1594068309000000	1594673109000000	1657140309000000	1688676309000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x237f2bbbc27185861dfe616e0a64e5f02ea5489c2b7913da83dfe3028c9812b243ad64303e5b205e04d9f058040e3a7af71cb07fdc4b5087b0a90033f2bf0bf0	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1594672809000000	1595277609000000	1657744809000000	1689280809000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xe3c305004d2b01ad78c50b337cb647478e995f2b7691acac6f43c8c770f81957a721d3323413825d288b856361fac07ce562df9c511d89ab1af2a2fb43ac03e5	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1595277309000000	1595882109000000	1658349309000000	1689885309000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xb6a461d2156ec32fa650cf173b2e26632fe8e02af102005f004d6a2a15cb1f94f8c7a83f5acc489d4d8c2c6f6e42c3e09751006fe910afa12d6ffcf3057f6f28	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1595881809000000	1596486609000000	1658953809000000	1690489809000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x57bb9f5316df96f5a876120538ef5be998d7463730dab6ee08a410cf63942a90ffddc5254e9eba8432b6676d4d3a67e9f704ac7878da4bd43d286f50980e4d15	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1596486309000000	1597091109000000	1659558309000000	1691094309000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x578f82fb9e8501abe9aa8e778ee32a8d83fc1f829806fe64b319e954a39db52733d221f5eaa738157eeffb3548a3aab90ba4c2b9e0cd8bd4b63957d327f7aa77	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1597090809000000	1597695609000000	1660162809000000	1691698809000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x5d410f92c0f49b70ccd357b8a35b955d539d740e811d98fe687785e9cf85f3f0abda538ced18de5be61e49ef3e56bc2d167296db254cae2ad1df6e8851374785	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1577746809000000	1578351609000000	1640818809000000	1672354809000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xf96f1f9c2f4a72d44bb0534b6377eec44225abe265fadd954cebdc9d53b03e90937d93a7e92bdb76da2b931c9bd914aa88083e56efbdd473eed7aa4ced5ef040	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1578351309000000	1578956109000000	1641423309000000	1672959309000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x34bc3520a140dc5e4e607ee79798b9e1a037480505328dcd4464e4eadf759116edf9e7e1bcf7c523b30c5dcfd4fb99672f3a60bc762d2219cd3cebf9d8767792	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1578955809000000	1579560609000000	1642027809000000	1673563809000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xf14a1c528b0ad168b34e654a635bd3c696c1991d6a2133425a88d82dae08512eb203664c64de9b7eb0dba0b8c9d9f1758ebd07104164f2541f42cd3da3c471e1	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1579560309000000	1580165109000000	1642632309000000	1674168309000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xc91073360b7a57036472b5dc9d5fc6a4abe699173fc523869dbc1ad60a5911a9e526ded58bd6d2ab11d43abe9b6632481356ef995449ea5dcba72de8ddb936a5	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1580164809000000	1580769609000000	1643236809000000	1674772809000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xba1b915a343bca19a03cb0e9b8521a93acc26ea10a304e8c4e35139fd7d516dc4a600b827728198d1138b8bbee12bb655fbca9a7963d6f7345adfd1eecc65465	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1580769309000000	1581374109000000	1643841309000000	1675377309000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x87bbd582cc6fa59ce8b3e9bfc9e60aac276bca0212cef18c5088927f655f6201ec2caebbe4dc40fe018e7cc3f3c709172f689c0baef75e2437045c052844300c	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1581373809000000	1581978609000000	1644445809000000	1675981809000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x43ab6ba68f92a034e41daaf7c8d004904ea45ae27bb55b155bc33dc6e4f3fb448a6dc1134109f0977030e6b38bf60093a324aec67a3f092260655d1d62da4f77	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1581978309000000	1582583109000000	1645050309000000	1676586309000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x0d2855a6ea47b37d4afeec237e06faa1de51f94b9f864758e4057fcadc1273126e7f69a70767e9c1036c5c0b6047c72387f46d9e74cbadc600014bfcbcd8946a	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1582582809000000	1583187609000000	1645654809000000	1677190809000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x5b5cc9470ba15ad51fb5a2760ede99f55ddfceb65e4f9642a0fe31cc3d6dede8baaf7729da647f8a526e9b5fc3b4d97984fd15af6271f4e308cc18de68eb9851	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1583187309000000	1583792109000000	1646259309000000	1677795309000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x577e386e7fff2f387a50b4a82babcd43cde4e15a4ee29eb24a2b4b6be123ac1b75cd38230cd72167cbbad821dbfa89bfcd57bc7d6c97b00d37babbdca97d8213	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1583791809000000	1584396609000000	1646863809000000	1678399809000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x586c0fb6fccabb84871174461bbc202b1e00c6a7e28280e42466562c673e7b05e878a9875733db226fe92ca0a979f419bccec543904bbd9aeccdbf8f8408777d	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1584396309000000	1585001109000000	1647468309000000	1679004309000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x59e381f39336a01d13becce1893a3deb0c626c363a233d0db994145c99a20684d4a1807f1ce83239c327b70d33ce9ec4ddaf30d83d58645d6b18e6bea7e095be	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1585000809000000	1585605609000000	1648072809000000	1679608809000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x815adc7543fb86e3aeef335d1c15aad01733692554626ca4a21dd757318705d0914ed33db8cc0940dec31674357a700e3a0df0affe8a8d8ba0e28bf8cc5d31bd	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1585605309000000	1586210109000000	1648677309000000	1680213309000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xa0f6d509aced281a651713d9fb96f2ed4181c9f68f41e6ea000c4bcf8e7bd66f47719bc8f036975eafcaab0fb254d997b2c325891b42cb644c3be9e5093411c6	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1586209809000000	1586814609000000	1649281809000000	1680817809000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xe955e91bf7ea5e2ac70a7d626690524c5d7305c3c0369acf892d54f44886ba2524cbb3975f1d4662bf30fde8273fa0c433a6daf6e64fb94be9d64b29e460a51b	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1586814309000000	1587419109000000	1649886309000000	1681422309000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xc45f6254eed4386def251778dd7710896aa23e77974cbad07b53c732473c4e2d7d7c892815e106e417cdee44ef7624ede7325491c5f254d947b5a3e67e611346	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1587418809000000	1588023609000000	1650490809000000	1682026809000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x2b473a83279b61e0955a1f174452ec161b8253468e16e8f9a679800fda0125ebd9a5ae74203b968df3005b4a2e8303af2dfd5ff8ec41ce48ab8d40066ab5173b	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1588023309000000	1588628109000000	1651095309000000	1682631309000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x4f2bc4cae5bd8217aaa74f368d69364f301f85b250f8747c8da03b8663bbbebe564c376dc6f09935de9d6b2dfaf2529e19d1e231d938a6159ec613c13ae4eed0	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1588627809000000	1589232609000000	1651699809000000	1683235809000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x47ff4f6ea0499b382823a549802c2b0b16549866a5ff8c91a1d6e6dfd5dc19cf4e168c48a04d11966f1a67d39b69ada65c0e0994cb45e3a468d7cc521f73ae6a	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1589232309000000	1589837109000000	1652304309000000	1683840309000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xc8563f73d96ffd9e7d0acc0bd1389accacd7c4a77245c7bdec4bd70eace32b04870bf4b003922a205951e4233935aeea026fac9e16860dbc5145056e13227954	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1589836809000000	1590441609000000	1652908809000000	1684444809000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xddf610491e7fa73f31c3d8163eb853e362b9254e08076b39b72fbde660b6ebfece9bd3f4b1b82040b15071be2c17c93fb4f076a55fffb620ebfea0e6d0d6ceba	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1590441309000000	1591046109000000	1653513309000000	1685049309000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xea524038b924c618a385f1194ea6532126761b3cecb22444e4b2c006bacca5ce28966202b6f0e62f1f60ca626b81237ee0315b93d838bc0120f115cf62b10e6d	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1591045809000000	1591650609000000	1654117809000000	1685653809000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xa25cb2563804838035a6c608a219c293b110e8acd744adba6067adf9673adaecca8165a31075aa3c7e8c42a361a45ebccd52de79e29791a67d36865d8e166169	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1591650309000000	1592255109000000	1654722309000000	1686258309000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x99d3f65e28b8c793b50c59e6c383e36b01b4c08482da28ec2a9cae1561a52f7af45e52a1ed4b1fefb0f8b03837995702397a71a5a280226c49a6b911ce8a3398	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1592254809000000	1592859609000000	1655326809000000	1686862809000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x485fc1bdee72ca55ec0291f641eac6d6370c15e17e2fdc1b37f630dc033bf060e25a4c71d0bef4e2069f8a3a223a64af789187fc7fdec85b04dffe58d5b21ab6	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1592859309000000	1593464109000000	1655931309000000	1687467309000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x619ec8ec773b403aebc85ab7a29b12004a8fd7703d483832098708c61608af12b1348ad163e20fb98603242fd4fe698d1af03214cce054e6e486d1bcc7851e37	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1593463809000000	1594068609000000	1656535809000000	1688071809000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xb7bf5b7cd6bc15ceef7dc54e029e104e790f5e1776a5bd312a229cdc1fb7255f41f3c45933a9d6632de1c54289c691290bc3a4643400d68a840aa85d6dd23b26	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1594068309000000	1594673109000000	1657140309000000	1688676309000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xfe75de15da86d5e123deb1a7bd18197deef2df8a9bcaa2d809e80dabf4538ec03dcb53307ae816b0a15f0e5d18a69c449292c601f0b34ae121591441d2d42e0b	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1594672809000000	1595277609000000	1657744809000000	1689280809000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x6b322a1bf2bfbddca9dd590dea9a9ed19ab2a415c187e972329049d83c2931b2d4964786ae29279e55d4a93c8da4837bbf4062627112e777517d9a059fc74e96	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1595277309000000	1595882109000000	1658349309000000	1689885309000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xf4b0485f002ea028c58481a1dd3b4e686583ec91d9f470f587dffb92788684817681727687e8738e92148a4fc1e5040fb0edb66906abde7ea1b9ca27dee6667b	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1595881809000000	1596486609000000	1658953809000000	1690489809000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xea7c04556dbfa6d441f2ac36a4cb597098180815d361688f78816c04559daa57369ea04eb623a8a7b53a60709d1dda8fa11f18a653ba58cbc0ada96e4ac2d0cc	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1596486309000000	1597091109000000	1659558309000000	1691094309000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xdef53769666d825d44a5cc05b4c0040e80827b4b94054c6bc935f96d68646cefce5cd7669ec47a9d6210a4b2880d5ad175d2401b2ef39da4a2f6a4bd6fd916e8	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1597090809000000	1597695609000000	1660162809000000	1691698809000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\.


--
-- Data for Name: auditor_exchange_signkeys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchange_signkeys (master_pub, ep_start, ep_expire, ep_end, exchange_pub, master_sig) FROM stdin;
\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1577746809000000	1580166009000000	1640818809000000	\\xf8ccf7deeb4f45e006153839e8632a2a1dd0b3042463ed57fdaacdf035495dc6	\\x26e9d14ed58bf6db51a0723540ae07779686d30874e45ee7bf387abcf83674d91a823b57c34b4e5a2c3e5f8456f983830968d5ca7d54cd4f2a77cd67d4174b0d
\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1577746809000000	1580166009000000	1640818809000000	\\xf8ccf7deeb4f45e006153839e8632a2a1dd0b3042463ed57fdaacdf035495dc6	\\x26e9d14ed58bf6db51a0723540ae07779686d30874e45ee7bf387abcf83674d91a823b57c34b4e5a2c3e5f8456f983830968d5ca7d54cd4f2a77cd67d4174b0d
\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1577746809000000	1580166009000000	1640818809000000	\\xf8ccf7deeb4f45e006153839e8632a2a1dd0b3042463ed57fdaacdf035495dc6	\\x26e9d14ed58bf6db51a0723540ae07779686d30874e45ee7bf387abcf83674d91a823b57c34b4e5a2c3e5f8456f983830968d5ca7d54cd4f2a77cd67d4174b0d
\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1577746809000000	1580166009000000	1640818809000000	\\xf8ccf7deeb4f45e006153839e8632a2a1dd0b3042463ed57fdaacdf035495dc6	\\x26e9d14ed58bf6db51a0723540ae07779686d30874e45ee7bf387abcf83674d91a823b57c34b4e5a2c3e5f8456f983830968d5ca7d54cd4f2a77cd67d4174b0d
\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1577746809000000	1580166009000000	1640818809000000	\\xf8ccf7deeb4f45e006153839e8632a2a1dd0b3042463ed57fdaacdf035495dc6	\\x26e9d14ed58bf6db51a0723540ae07779686d30874e45ee7bf387abcf83674d91a823b57c34b4e5a2c3e5f8456f983830968d5ca7d54cd4f2a77cd67d4174b0d
\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1577746809000000	1580166009000000	1640818809000000	\\xf8ccf7deeb4f45e006153839e8632a2a1dd0b3042463ed57fdaacdf035495dc6	\\x26e9d14ed58bf6db51a0723540ae07779686d30874e45ee7bf387abcf83674d91a823b57c34b4e5a2c3e5f8456f983830968d5ca7d54cd4f2a77cd67d4174b0d
\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1577746809000000	1580166009000000	1640818809000000	\\xf8ccf7deeb4f45e006153839e8632a2a1dd0b3042463ed57fdaacdf035495dc6	\\x26e9d14ed58bf6db51a0723540ae07779686d30874e45ee7bf387abcf83674d91a823b57c34b4e5a2c3e5f8456f983830968d5ca7d54cd4f2a77cd67d4174b0d
\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1577746809000000	1580166009000000	1640818809000000	\\xf8ccf7deeb4f45e006153839e8632a2a1dd0b3042463ed57fdaacdf035495dc6	\\x26e9d14ed58bf6db51a0723540ae07779686d30874e45ee7bf387abcf83674d91a823b57c34b4e5a2c3e5f8456f983830968d5ca7d54cd4f2a77cd67d4174b0d
\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1577746809000000	1580166009000000	1640818809000000	\\xf8ccf7deeb4f45e006153839e8632a2a1dd0b3042463ed57fdaacdf035495dc6	\\x26e9d14ed58bf6db51a0723540ae07779686d30874e45ee7bf387abcf83674d91a823b57c34b4e5a2c3e5f8456f983830968d5ca7d54cd4f2a77cd67d4174b0d
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	http://localhost:8081/
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

COPY public.auditor_progress_coin (master_pub, last_withdraw_serial_id, last_deposit_serial_id, last_melt_serial_id, last_refund_serial_id, last_payback_serial_id, last_payback_refresh_serial_id) FROM stdin;
\.


--
-- Data for Name: auditor_progress_deposit_confirmation; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_progress_deposit_confirmation (master_pub, last_deposit_confirmation_serial_id) FROM stdin;
\.


--
-- Data for Name: auditor_progress_reserve; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_progress_reserve (master_pub, last_reserve_in_serial_id, last_reserve_out_serial_id, last_reserve_payback_serial_id, last_reserve_close_serial_id) FROM stdin;
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
1	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Bank				f	t	2019-12-31 00:00:20.785359+01
2	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Exchange				f	t	2019-12-31 00:00:20.855878+01
3	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Tor				f	t	2019-12-31 00:00:20.922547+01
4	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	GNUnet				f	t	2019-12-31 00:00:20.985122+01
5	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Taler				f	t	2019-12-31 00:00:21.046653+01
6	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	FSF				f	t	2019-12-31 00:00:21.106989+01
7	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Tutorial				f	t	2019-12-31 00:00:21.168836+01
8	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Survey				f	t	2019-12-31 00:00:21.231293+01
9	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	42				f	t	2019-12-31 00:00:21.661364+01
10	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	43				f	t	2019-12-31 00:00:22.087576+01
11	pbkdf2_sha256$180000$yYNVtMMD3mO7$zcIKc+InvBJol6Hgfs0AEAr6yZK6EjuSba/f5Q3/how=	\N	f	testuser-Zig0rCuT				f	t	2019-12-31 00:00:23.802773+01
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
\\x3cd3f787daca32c6cbc67d2a77f0077e30ec14fc6b3bbcf30bd7adea92052ac629fc07976e8f63edd59d365c9fc9b560a44a48a058f84560aa0fa7cd409c1262	\\x00800003a94e03c617bae62e48a2d80a83fc7bf86e5ea29f870a80921daee8945c4788041b8915cc2e9f8c97c7905d49e678a0caed876ac3504ed09dce09ca031b96a00adaad605c3a5279c36b0748db25a63fea744b2d941f877b65bfdb35f523045a45a10c9d1edee9f192c39d03179f3305080052cd7cb901b704e7224fecfc2034c1010001	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	\\x284bd5eea89c57111bd030c06458d0f0d32bea47b4a8c04bead1039a38e12f8547b7dd3d4bd60e477d80047f11e2f41b9d8afa84cc829fa4ebf22e85084c9b0c	1579560309000000	1580165109000000	1642632309000000	1674168309000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc1ced255bc70c92a79e4b046aaa69156d70d09b31e4dbdf93541bde21bf9a4efa33893adcff55a81356d3c36f93ec0440a199aa8e4cea24eaeb958d1bd70d5d7	\\x00800003c61bd8ead0dc33e8b721ec6ba69631935629970109031985291c84d0b474744fcbdfd32660893631563d5f9bd94f1074f4249195914bbc2fc4a62439d4bea5a5530b8c4179f5be5ff4320348b0c6f170e7a361d4dc160890f7c62e06feb72304ef897c807bbbb2e3458e8bad82b03c4bc3b108553d201d9d7cd00af44eebb6a7010001	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	\\x4c8c4fadd91ec28d8ed5c558b1b48d6679948da3f8f074856b778d1961b9ff819a0687ad700595beeefd7000cea8cbec5561edfc034973a0867e3686c46de50a	1580164809000000	1580769609000000	1643236809000000	1674772809000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4101811a632ebb2a57c02c7e304ce6b630b6297b648247d40047e9b4b8e715f29d23dc5c6529df48ae608dd158dde0f16db39e85acdb6a4bb2b31551f3f802d9	\\x00800003b1cac0dd9394d353cd8236e4694dbf1df41f9f74c0d704e974a55e8d879c2faa76c450f11233a654c3325ff0da6b43a73aa46e8df7226c6400eaee887507dfe55b6343fe3aa0df2881878d9b235853f9d8da0ec0c567a3350c300a1d823bd3db613ae47de4774fabeb6b4406568fbcc30ef841809ed95a9b5ac6d3c373fb1b77010001	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	\\xb25167be94f6fc61e87efe69e121e6fecc493baea41df321479104f2d3c8c417f0956383430876906142a66d8411ca043a182b0a116fe4bafafa344dd6301b0c	1578351309000000	1578956109000000	1641423309000000	1672959309000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7b06fcbbb51c981fad9cb6909d69207d6ac151dd9714367e9d524afc9c8b01d4a8f6da4817fdf92af09bde3c86b0ea514e455deb3b8f9f8006c05548306022fa	\\x00800003d2749454e7b3c734f649e6828e957e864978c436964de5597c91f4f56f8a81f2f18c9f435fb94707390129897b7da845bc73c2bc98b956ae1642af1e1a5b82da056b9791d6b07e820e9463bd98a3aa27b6c7c1cef3c22d20ca22071f2729a2a9200e14dac7123b0824b966c23149cbf89897eb24fab5b87de4c4e4b660118333010001	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	\\x490e7603012bd87515f18a032a37e6213c450bd86f76a43d017c174c1aeb3006a06f96bfbbafc4d027f2c4c2bb074ec0272419f8329d86fa5a00688ee2fe7708	1577746809000000	1578351609000000	1640818809000000	1672354809000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x093f5a811743e1d6fa9110938dd793f4f226e2db6d06c9ed9658eac243234f53e5beb4922a1930efdbf8ff382f6722c11c1d7ac0f13860a7160f4bc5e53d1a65	\\x00800003c9683010ebec5f895a4b6fca7348ea7b922e8ec9084f9f3bb05a8cb388b8c832bd864d6cf4a3aed930542047e3ed48510cb535ab4717721f277512a4bb32a07930a6eb50b5960f6e626fef973a1190ee18019ba519d4d96367d311b9c230823ea5bd0441c146d142c341658651cca904ecdc3fa24a5c1e98ddab3c72272f6b35010001	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	\\xaec1af5de22c6227be41fff59596f0652d9f1dcb828ace0cacc1d29130540b57914ae3928c1b6275c5539a9be0cb5622d12fe180462bdb6fe893d5f4512d4500	1578955809000000	1579560609000000	1642027809000000	1673563809000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4b71bbb496f4b547d976d8634adfb9a207d34930718d8a5a95d7251ac486254a8a874ea472d83b6fa349d1a5859ed46d00f51cb65ee542e78dccf7850a106c0a	\\x00800003b628a442c3d4260dbe88692db973de671d57d9e02f267866b743699726199e914080c90a32d390dbed516cda7fb832ff982c3ec83acbb416970123d3b13565b9cb1784123a91b132fc6c952983c2e92468a610c489b05532ea28154c8fde513c539bec248151fa8c14d50245f91a56cba17ccbebb089b1a2b9cbe15ceddfdca5010001	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	\\xafdbb30211ccb1c333b23db444dec9d2f15c9e8816af0e01f90b48e377ea614c221c76f08ca6589d3f9b413b396a6354c115a4fd9b85c7041201ee6728cc4f04	1579560309000000	1580165109000000	1642632309000000	1674168309000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf42d803f1d06029e913a42ddf0ba8df1c0a962b4bf4ffa99ea145e616470996712ae2de4f4d10f352fd471e349bf32bb49a2bbe8fdc4a8179cca593a99ed5116	\\x00800003bbb33023737d5f889f9856fa897e3d6251a8ca75f39ba1d68850e916b3edeba0a1094ba1d9acfce4265a09bf5f5e66eaef1a48b71d4059f3e6612e819f546165d54d25181428d0f6da78780ee0f9bac31cfd884556350c1cba3d31ca330097ee02816724243e149c6fad3ba603d1f954a49ce838528e04c988490638c032a56b010001	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	\\x59453ac57ea7dda432e8891868fce643469ba22f8ef10157eaf5bb892942ad3fc06f1efa364a1c7fe622aa75fb1f972794af1f9251af4982464e66792055fd0d	1580164809000000	1580769609000000	1643236809000000	1674772809000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf905cf7ac97484f4642762daaeb03ea91b5cfd27c669b4cd05a67dfd1748afc09653bd4f612d1bd394b0e76e171914533d751b9cf6c4178032b8a8279ce997c7	\\x00800003a439ee79620a4c89c89d8c64d0b8f89f8c20936aec0641f2975b4f2998a78a9653eb8469a7701aa3502b89adf7bc84537b024a68bfd69ed8eabf2a2a9a4acbf071440c91e428203410745eeabc4e46ca010b4d0c599a19b2549e2135688a783a7fb312bafd958b7e0a45b4187b645b6c61a2143abf07c990a3a9e4e1a6d098db010001	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	\\xc03064c3ded1c65af3727c91eec75ea3a0fb531e8407fc5a6cd7bea56ce3e30afda998621f3b9932fd1c670de7450a732ab47b5784007db7ff61426a1c6c4e01	1578351309000000	1578956109000000	1641423309000000	1672959309000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x14eb7f896d6e9a06c70131d39032b9542b0c0795f12761e1578a9616aaadbf6b6b5e170f98fdd194260e09c841c11145a2469d7cb24cc9ee634351516addceaf	\\x00800003a3d9242df2de2958f504ac5527e82276c770fdf9e5c963b50f71c79861c001c909283c9b53bebb4077fa7e1232b13bf33b31c98dd2a41f3659a857bc130bf40dd44863e111f370bd9b8dd48582bc334021f993b203588b97cb1c642b8a8e6a2e97fa7234638bdf385e78ae39122f6cdb4812ac9ff0be49acc0f914c3f4fafc59010001	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	\\xe3b0628fb427aedc9c25168ca54e247feed0f14fe1100470c7a9b53213995d848782f2deade8d1f7a9aa09723d546781e6a340be70f9e25e99aa75b6dffc9d0b	1577746809000000	1578351609000000	1640818809000000	1672354809000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xef82dd7f1cec75db10e2f1bb047fa2bd4fcaa749a42ed69d3b2fade5cca1abd1317793214497817052ab8ec829d52dbc0270bbe5b93e59e7d8d4a9eb69e6dfb1	\\x00800003c03b45a8c628b5f8011bd3dac50f70d18d9f72e58dddd7620ae77dd0eec8cee178edd06d8b02f96ceec6f4ec4245ab634dd708f470608e9c7eac7bf86d1937f802d5eefdeba09a2592eb9da2bb0862821d3e436c5435c6a02ea377038637c249b5f5ae2d37d16dc75b054997bbfd4364703c3f3f6c140d68afd5f69494d849d7010001	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	\\x7474be9ecec75484ca730538f46521a563fe1c7aa7fe83246d86b074e093ccc7532a42c4a7b4338a8099b12ce6eb354dbc2fb97a5a624d92bcb44f10aa454007	1578955809000000	1579560609000000	1642027809000000	1673563809000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x03e0a031e28a82ae71a1eb6f67785e8ff3452fc7ad750f00884787f276e85c446cb5e4b5bd2b007eca45753a4e8f9eca73d92c54ca9d84c80ab5e98bcbd2274d	\\x00800003ac60dd46b110352dd14c5f4bb04832a6a6c41da0119c4e44ccebffdfd22cbe671832c11bfefe551fb699be56e9da6a97d61423e01959ab27b1d9b74a6670952ceeccff2093b8e17014222922ff6ae9fedb8375fb9e47a8d413749c6cc200dd404ea6165248f75ae9bd651f537ead933bd7d617835851f2e8ab06789ad2c93f5d010001	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	\\xfc4001e3febb41bfe5443e07d90482a0c624f9948a6ab7c1b67ea79ae8055cb9db3e07e11e54c2f12634a9fcf0403b87238cb460974678b8787dd66ba8994800	1579560309000000	1580165109000000	1642632309000000	1674168309000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd8cdfdaab2269770c9f258106c7cc74d671e962a2517ae3b4200b37bc1d212d405a5ad6b1da6cf95f0cb10829fcfc098c87a596405fa2b64a024c42d45c0595b	\\x00800003d67c6636a63733f187d7f89c907c3ec47c8ce0299e5d0a4c4b5509ee0a3552d7bc0cfdc879e618278eafe2c47da48398885a682666c38b525eead7cceab469541cc600fe42be6b74746df399e9f9fff952825dcd95a806caaa220f0110b3db31c0e73f2dbe93069c1c7e805e0135716361124e365d6a9bc851621fc5c0853c5b010001	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	\\x745919fa86a6be7b830ebec1748f6a31883fda4bf3601a6a5340305e6c1840cb53df7535310ddedfa9297e34afcfc41421b5223795514d3d285e3c822015e705	1580164809000000	1580769609000000	1643236809000000	1674772809000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x44894e8aedfd8b94156874c1242d32a0dd494c888427efdb95f906c51c2d10e2d71627103d373b3093c68a3fcd82d9a9c0800f2380553051ac520fae24f1a02a	\\x00800003d61ef97bd1361f2c9ccc0507eebca3f49f4a398c3dd24eac5486eeb6ffc1ba1d2c296daad67b0ce308553c9063a2ecb083f575d5f1e1eed825a40503e5d91b7b57e507c4234a8746140e6fb7bfab3ec07a58f6352e7fd0dafb3cf31a8acb9927c30512a6fcb40c9c38f0f4c1e22a755f9d0cde9b98b52adb04f3674cb6e829ad010001	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	\\x5e5f7286fdabb2a38a775c14e621b6113feb498d0b5cfa8ca2398310b2e5166eb9ea7165754380a81be508e9846d3535ba4265e52322ea2b12c725914b55810d	1578351309000000	1578956109000000	1641423309000000	1672959309000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4a9fda5b02ee10e9c98f9f426888b89826d724c9f080e0cacd9184e1ac6a2f03f74990611e6bf26b4d714719105adda47d76abb515a089688c667fc5e2c743a7	\\x008000039ed39a14845a9d03b009738a0d398c94d49c5634186958c703f076fc77de90d995535dfc3ace57731abd8252f3195d670dd5a015eba8b95cc2b908275996f55b5ec3fa2e263560bc7ea8c03bd8ad0e6aefa99516ed13a45e7c6002abea1f36891f7dcb7fa252ccb9bf660e9562c21498b9961299ae3b20228efd002cfefc6cb9010001	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	\\x82ec6259f32a6066a47ae6113ee67bbb921fb3da98af196fd33febab9fd11bd845cbb4b8e329512539d051ecd52858d192c4d5118cd2ed184b4dafd24e5bae09	1577746809000000	1578351609000000	1640818809000000	1672354809000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf0fbf20669aa00fd8bb251456b8e390ef4c39ef6bbb7198384a17f4840a39fe4b505930e02cb30d6e6eeeda135cdd4e3af46e1b883414bba2f3b1683f22ea787	\\x00800003f43390008ba731162996b2ba9ca8c839c0e524d981158e3510509a512f73ec45f4ddd239c8339ca7ef8b16f691079c9abed74bf36058bed8f2fbd4baf5803f025699435603bbceac1acd7122e7e0ca04aeb2abc7bf31253ea5d54e3a0518946ac2e023ed0e58876a2f473ce4e0b02be39075e490891413131e9cfa6407576ef7010001	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	\\x4c70631720be85262a7443864754ab20980cd0a0dd5a32e6e61d093ea7f012ecdabfe782f83908595f9b1e5bead9969f0674e593885f1b6913290ef126a72808	1578955809000000	1579560609000000	1642027809000000	1673563809000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8789867d368f9e95fad9dc76b1042b7b31f3b66dca59fd344be24f13765f086d9adf3351e79fa12c95596c22721858a5333587aaeaf42663418a95437dbde102	\\x00800003c325b47ac72f057203f5f08382519d93669371fe4e71d42d42742e6a83f6c141cb56bb3031dcec6aa51455b9652eb6f09e533bd700aebbf15975f5b1ce9e672d17bfca4acbc32f941bf068315fa719479fcb8565d2844cba2b227629f74edf92f46cf2251ad2b4a9cef6dda16e9a8d88cf4625dab44bbc4c7febd9fd8ea438ad010001	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	\\xd9441dcae964e5837be4415e608a9d119ae397666ae25e8542a273dbedb8a52d57b39d682586b9e0c522a542b6dc01d1476c5b63dd7fdb0f8cbce7f43a2a2f0c	1579560309000000	1580165109000000	1642632309000000	1674168309000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc56a7b9474c7e6b67768910264dcf81bb71d3c76219e78e4ece12143ded6073b0156f8ac1f3b4c3060a4e71a8ccde5c683b40b1221a0bc82073360ae6eced82c	\\x00800003b238442061199044a95b823d51cdc35a41c9e82afa583b0ffa17d7bfede2c11d45a051dfa25215ef820d5a57fc970265feade4271a73804e3029f096009162a65be4d74d41330828f28d33cf3f906f913791f5a39a4f9cc24f684909d4fc12fc3dd678b8320e7a1534b6d90fd948e1d5b5f1b45b41ce68aba6a726b3580159f1010001	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	\\x4e4cd9472f7ed13b6795567ca55f9ca2d5752c12e5f1d9aa0d366af9b73cb64d13cc8a086bde5df16ff927746f58f9a5f92890687dea9ddce91f72547cb1de04	1580164809000000	1580769609000000	1643236809000000	1674772809000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb314ec9f648ba79b5b5c1b4dbc46e0efef548ea30ebdfe129d6a0c48555fb44af2ca58f1fcee28aef35f0eab4db03777cbefaa0901c63e946ef96f015cf3a0d4	\\x00800003d2ab139bc0aef690e5877b23aa945b6e656af733bdbcb73b15ff8558ce6180c3133a8c6fff2e1f0a66de6d92f32c9c533b939779be230f9de225a191d93b7eb3a4cfe95503cb30643e095a6885136ca5e43da1c3123f0d0eba64495d8bf26d1e68ac9a0ebeafb53ae1629c0263a86bd27cfc91823b200bf853cc59a40ce9031d010001	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	\\x917b5f2262d1d06f2c843229ff822f4521f8a658a80123af5a5540ae622c3041bc71fa26f4f674da47a2fbc295f623bdfd740ad293fa4a9a12f3518a6a02cb0e	1578351309000000	1578956109000000	1641423309000000	1672959309000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x670d3b91a68a7996d41995040ba893619a55336da491ca17b900c282a6d1ee411f63881a8bac146d942024396893a06c11b01127ecc5d44817ff4658a0123d67	\\x00800003c9a25f158237a74e5244d2851920d3bdbe8cb1bd9b21658e82db2d3e7de58aa211532bb8a5570d5e3cf4c056acd964f91c357fceffbfd5dc9d99e699c54382466d403e8906ee95fdcda89329846ab90d927e933c3ee8133029f01d090acfe8fb4df9d328cbf2936bebcd9c29cbb911337804fac5c302427885fdc0870fca7ff1010001	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	\\x781c9133ae96bce726055b8571d55290fc1df77aee6afad28608ed4f464b4dd9af89e46b3b9e76e2bbcc93319d7f100dba88737642d1b23c9b61cce0d80f5003	1577746809000000	1578351609000000	1640818809000000	1672354809000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xedf319f8048c799baab17f4c4e4631a6b4d99cbd88fd3800a99efd583685a9a3657a3f9b01354f66713ece119a7ebcfb9f5f4b456250c5a7162884282c646dd1	\\x00800003c084643991d5c7f27b1e284dcdaca0b5358cb657cab20a0a51adc9b9278591ebba8fe45376e7c15d9fee4a6bb230603418dd3978d1c21c4b620fd273025fb9b814bf1c6cd8f9e771da5e5170a0a8e6b056758a0b762a62355deaed8807827ceb2c0260f680699cbcc0b9864a6658f482a9fe6c5ddb837f10dea0d8d38e115f3b010001	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	\\xe889afdb86793c1b33797e79800480bc0bc2d94ec8ab67043f0d18679830cd025944e4287ce0941e5825083c1dc9dd9e0e2b03a40800cd8399e0f94ee5341400	1578955809000000	1579560609000000	1642027809000000	1673563809000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2c018f6042b1812c84307046fc570baa235bba1df8f9f0d09f05e3511dfa57c7c6d26b50f874aaeccf5d299b589e5ebe835350e89bb913cbbf773ebf142a4bff	\\x00800003d8a7eaf096c5474b413eb567c70626fdeb7d8041639add24f74ecf728c5515242a674a70f377620ddc3ff53dc71b48fe44767ec16f612231db96e7e2468066d47b406c8990ac5bcfb229340d8ccf65321bfe52de49a6c956892939bb2ceba0a8ace329a0befc7c10b13fe4edab452d6adca3793bc2753e1d4ca482aef02cba79010001	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	\\xb908d95631e448ed7a60bf56be58aae8c3a8571d2bd5073b24dcbb20899a0cbc20984afd3f77df6c0a085f370b37d0254dfeb15e9f8f9bd794304407ae752605	1579560309000000	1580165109000000	1642632309000000	1674168309000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x31f95dd77ec48eb282de029465be7632cebed869278303c2c0065a682fe20670b82e06e16cd269a36d2a946c1c7f11a77cbf4e1d6ea2ef553fe34d51642fb3df	\\x00800003d99532c0f2373017e5f31f7df5b35b3c28926b0ed206be48f81ec41850d1e5f12dab7a9ff76d5b6dc4f3ec227ce62dad3695b3142a9a5fd86b5954173e14da88e62f81e2d78f7f00ea39099c99de3ad300c70497121e54a8c50dd9a76bf5017d9e1a2ab215df24200916355a7d474145d7913ade05448f4b4d39955b00bdc6a9010001	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	\\xeb01767b5bbab3451500ef3d7ac87b462d4f938b5811576e840b79998c0cd7c8bbbe6b270c723ee3dcbf8224913b4b3ff5ca5f5f97cc1dfc4cf9f3d39ab27505	1580164809000000	1580769609000000	1643236809000000	1674772809000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x9f3c6cc8c530bbab6c23522ecbcfd1be07d4827bd617109d4e8a8e4040a1f091fccbd3b599a0402026cc22efc4fda52526d25009b4f743fa939025e075b3ad84	\\x008000039acf813dcec9663eb9bf40fd164d24de02c29b4484f8f74a83c955528a61afdecbc11328735f44510ad316a3c4b3d7a2f2be4e8ac9f668519b7ee3ebcabb3b57f4d2abdacc530b60df7afb1529838795727173c6944ff4288e1e62c371776920bf3a26c1a24a84b3768432bcaefef0accfe6f2fa2357fc2c43a21f3cf8baca61010001	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	\\x85929caf7df4f3b593878443c12a8c68364d051b0d04e9a52ce4438f00098b9c652268099b284e94c4c606991cde0f5b1bb705ce36a3a95c0c80142889b95009	1578351309000000	1578956109000000	1641423309000000	1672959309000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x6a59aa868a47da4fe4e8da0ede7874acef904a8fe383fd3b977a95c69c3dd52cfdbcaf00c7913866803050fc1963d7598f5f3a864ea0820088e2f4a5db878688	\\x00800003f42cb18a359dc75f6cd8ee23c38524266864e80252235c006d9d07261246c36da60ca32286f74f0fe5c00d9852b1f4d61c7e91869e214b5357169d3b9bba4c9990eaa113dddcbbf281677b9ede7c182a0f9aa11de6eb67c264dfdfe5ba40f70176a666cf3c960a9358b1729a4684f0e95a198171afa1c72a5f03e9d7bcf2eeb9010001	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	\\x032440a702e251172301b81bd7baeafb2102fd90338b6ef38d458ba707f654b587bf3adf60e73089b9237152f45b649d4839a08b7c6ec9165ef0180a77000d0f	1577746809000000	1578351609000000	1640818809000000	1672354809000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x7ca89ac078ae3b893652f3f35f708dd64e0ee2987dc60780bafe0f9eb4e98a158fc992c530817f47511fd4beb39aa754e9fdf4b8e15dcf9dd2836545d397d48e	\\x00800003a3c91d204cad4b86a43eab6b2e5f0f0271c13e6e437be5d3b82787f79140925e0a24493a025c78c2f3e5b7a497e05f709bcb82d017bb750ce27ea355a6609e1e47fc0cadff533ef976382f4a813c5bf1301cb31aed0c3523ab0804fd28317a978d31b43ed38c7f204f40c6b7d14d9280e13e65698f5466b6c4998a40f95b5d3d010001	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	\\xa74701d0a396bc2dc41ec97c0dd8548917acbe51f37308cc5206c1a409be96eb6a59b1aafdf44a7ee9fd06826649e3805e09d05a9cc5ab34fa425e6976b0a30d	1578955809000000	1579560609000000	1642027809000000	1673563809000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xf14a1c528b0ad168b34e654a635bd3c696c1991d6a2133425a88d82dae08512eb203664c64de9b7eb0dba0b8c9d9f1758ebd07104164f2541f42cd3da3c471e1	\\x00800003a8af9ffd5942552b5d7490f59e539b91d3b919c757418a061bdec84b38c512c03e61e96dde3016fd2b352d283770c231114f5cec4a7e78195f6e4ad00917720a4946f866886cd973617248c592a04c259cac40e82eb7e86dbb1b6e9ab9c321c0850cab2801571b5857c1573f0a1c0bcffadac8e3b967577b14469b42bca41d27010001	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	\\xe1882bbc79662b09b55412e13671d9a2173b06cef63686341b4b5f8087c4313f1597d9ff918db097b033827915f92a431e5aee8ce6b8c1c977ad15511bc3130d	1579560309000000	1580165109000000	1642632309000000	1674168309000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xc91073360b7a57036472b5dc9d5fc6a4abe699173fc523869dbc1ad60a5911a9e526ded58bd6d2ab11d43abe9b6632481356ef995449ea5dcba72de8ddb936a5	\\x00800003ca545b70331347ea4c9051f76edaed424b4eac43b05de41494f0dc075bd934b963fb2765bd30853bee69638f72e64c9837f78df30fcd57fc132a2574f672f2ed670f7d43630636556a46adaeb4fa5ea87701df0494668d1d448d22c3cdf583b2eaef109240adbef1f09037085a9ecc416265ea2a929e3cc6094678ab2c7515ab010001	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	\\x0ff3f122a4f12a51fcd72e2832c66a67f52ae2c5dc54ea9f63b442d3cfb426d19c71ce0d473fbd8d093ad37fdb4b1159e466893e028ac161f0b37a130644c006	1580164809000000	1580769609000000	1643236809000000	1674772809000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xf96f1f9c2f4a72d44bb0534b6377eec44225abe265fadd954cebdc9d53b03e90937d93a7e92bdb76da2b931c9bd914aa88083e56efbdd473eed7aa4ced5ef040	\\x00800003cc7ecd14e6242b56f703f2a2df1bb2065662364a2cf87294a3906c44ef58a45790ec89644e5741e91af89d8e2447c35a03f72002af05764b366960983455c8626ed7ce069e19713e9a73b951b84be6bda4bac74db4724d817d3b4204c84064c57e69c702d944416ae880910ff88d49d61b7b4b4ad2a85a053e6d33181c2a2a6b010001	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	\\xaa1939228f514d08b6ccb6a1fecd50b851b6a6a793aca86e52b8834d425eaf410798fbe1f66fa781b611073c2099d63f4d0d4dd2bb260a5c169b977073f38207	1578351309000000	1578956109000000	1641423309000000	1672959309000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x5d410f92c0f49b70ccd357b8a35b955d539d740e811d98fe687785e9cf85f3f0abda538ced18de5be61e49ef3e56bc2d167296db254cae2ad1df6e8851374785	\\x00800003a46ad6569a6cec5211224ee39629cd78f278526040d6d94fe6730b4d15fa33b4bbc5abb9cbb41bfead569e03182e788597ce84adcd4e9d2ec40b3ae1a1e279ded0d3e15f4fc0d8dfc787a607bea98f47fd54bcf634c8fd136e1254c840b5f02e647bea36aa80f4de2e769dfe60cb48c09a0ca5143030d8d5e542edc02af35d7d010001	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	\\x0ed8a3ff57d4fbcec6bedafdc8134154cbdbf79e77b5e08720d148c1007e00cf8b68adfccc127b5ee46834ff3acb0762c2f9f5872e0993efe53730d110c7070e	1577746809000000	1578351609000000	1640818809000000	1672354809000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x34bc3520a140dc5e4e607ee79798b9e1a037480505328dcd4464e4eadf759116edf9e7e1bcf7c523b30c5dcfd4fb99672f3a60bc762d2219cd3cebf9d8767792	\\x00800003c29b7629f2eaee824d806e7e3e346eaaf379cfc713f612b6cf74ef6e73666fc97e254e3806cb49dc21881a2dffe100ad81e69baf4998f2ba033f54480fa89c0d0028391a2664daaa1f61caf9754cb49740a3b20a9500af479ad88b52beeaf328a0bde2faf3dcb5bb7eddf8f8151ec33cff22066ce354e60e78e9efb842c4629d010001	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	\\x1badeb8eeb63c2297478cccfbfce98db3494975f43c4122394650d3247db667fba05e43394814fdbdb43c159091b810d1e3482ec40fa0ec8a0434f6c4559b90c	1578955809000000	1579560609000000	1642027809000000	1673563809000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x4726681b66263e08ed143e6154536fbc5ce5a9e600ca3f9a0594abbd943e62e908b93c5de2247948412ca87fa8ef352b303f6f74452e8177946170b6a83fac39	\\x00800003b8d69c132adc1e81bb074c5fd88aee9e612658952f8b5e1887be770317c44373351770ee3237bd005f525c0dff10164293cee33c521624748d3667365959b3fd1063a558e2a2eb4c4c0881b7bd94c4f06b60769df2c7c6f11cf1741d92f362ff4822d370a8f005a49c0952128d317bc2c2c04fd804d4c67e1607829fa4158c39010001	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	\\x56897c5f39a6f95e73354fc0041c4cc8cfd1717fec66c56a3abb0c1f9368b850297807422238c6314e813ef721bd51c0729f8764023121203b74ae445c5c4c04	1579560309000000	1580165109000000	1642632309000000	1674168309000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x377c01dd9a8e415f9559a556130a328bca2b64c45ce53e81fe2aa167ab38d86b72928e6f29336e1c0cb5b18aed3bf42df102a4e5b64a3a744f53c9e8b9eb88b0	\\x00800003b71d1a322d469fa339ec4eaba63768b3aae8d3a26ae3559edaca2c719df78b64bc6c25d7841fd10de6fec6950e9b3cdb03b36674bf0142976f8d49e5f671d330c46c222a78e32caef4c7fd58c227ce38a78a2999d2b66cd3b64129eb3e295cc99a49639bb2574b5def094ac4414f69bb97de4e17e67a74b07d800185182b592d010001	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	\\x4446ec1c6ebc3f25b19e24a2228fa48f1ee1f444040b12983f953e0b8198fb440c604fd2ea1f886b7595990c4d393b1de4cebbc550cf226263ccf9c0dfca5701	1580164809000000	1580769609000000	1643236809000000	1674772809000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x8f9655b73147098bc7238306fc049da173cc00f245f6c905fcf9342dbd4a76ff91c0b377a327baf54c222ba87f11180d9cee111313768a044502d91568288f48	\\x00800003bd4440d565433cf2f7ed208dcc24c9fc782e5af6d67b500175d6a87c05df271f3762166d53129463a337e47282503a1f6b7dc198510b0ecd2817cf978c1f212118cc0dc99eccb858492f0bc42e6929d030294bf2b09656a873ab51cb7e65f7e6545b3eff05ca455c2e310bd97f14c97199ceaa370dbdee463515bb017d996ba9010001	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	\\x06078fe6dacc7eea30736251a3fcf3cb61860df00b0c3d62db4f827945913fe7c7ab6f76b42c9e2a674d89ff57c259a78f184265f50b45a9e7bb27dd6c616b07	1578351309000000	1578956109000000	1641423309000000	1672959309000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xe365d5ba3eaa89c4456f3b750e85ebe81978cc51aaf511b76875d60353394ba638e1fa423bcb16d9d0666598ec8e8baf053a97f679c58f8f2bf9f31c0dd702be	\\x00800003bd6c5b3b9c157c7aa644b27956b9b798a7cc5ceb6be74887948a3ad2be837074c7de988b83a7445726e2f7a7d8a59ff5ba14960895d0a91d1704aa5a04cbfc72b65c76d9d7afbfbeec828f2a728e4ba1ff63696d7006d5551e189c53035c28c5419d5b4c9ae83484459f4597549f6a3aac1989e21352828991df0d6874f7fe01010001	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	\\x3fd03b9de4d81454ee0a2d12d9bdd27d18ce72a1b8ba2b01cadbee6000905cf5bdf795da43104d80765c3b70e94fb9ee9bbbafcdf23efc0d748c8e0c76aa210c	1577746809000000	1578351609000000	1640818809000000	1672354809000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x22620a15333bc2ea07939573d90061a07e164026d495992f1b8c995b94753928ae3732a4481aa81b8e2359f852e41b52e24e0cde04f178e2c8a5c61adc05c136	\\x00800003d029902df41214353b53210b949069cb7a7e5a4a8211bef0054a7f3805125d84d8d51264975c4a71d8bde9f77caab4ba852d9839beb02221575c921f0195dbb6c65c674d4482796d4794aad6831bb7eb101e4b3b91f5d5fde2827a469630953cb10f2d255d3af3b974e5618bcab8fd09e7b17bf4cfb2fd78267670805c52cb5d010001	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	\\x2a2ecc9f570d48d30220f60ca57611bb31f00030eb95caa00f6082c07c0cc3284fb2c7cb6bc0211487be2626a54b96ce6d8a2f783ac3da30ac12e8f9f61bcc02	1578955809000000	1579560609000000	1642027809000000	1673563809000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xff7cd0c4b022ed726c383325f509a21208c00530dffb305d4e5b60be181d0e3e70ba6701169dbb7b45b6f9a287bad9889e5dd8430f260f473f656486a37635ac	\\x00800003a27691d8ebd9146a9c54f08b309263978434569b750a24f21003c27479257c75e107d8b92e3d69f8442ec2dd50b52e565382a8ab2c1bd2d593fb52b1c8cba09398d30670b5f88d0f7cac6152d3cfd4242d7cbb9e04bd7544d73878fe9b70f305011b56dee44a8484058abcc59fb0bfe50cc1cc5efb41b59e5f129a719dda797f010001	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	\\x370dc2b362a3788f01da21641b07308ed39c7d0ceae1f550014540258718833649d1685fc8a43d09ca63ad6ccf590ba18128bb1e8c893bedffcf3434472ee609	1579560309000000	1580165109000000	1642632309000000	1674168309000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x1d157bdadddddbeec9cd66411d88d86de0a09a233180cd2c5a248d7e05721b93e0b02d50e4c30d1b6de51c26fde6199ceafc2a717e0ab7bd6acd6a43f783e4dc	\\x00800003be3b38981402d9baadcc27c87b3cdfd91bf386ee56a8b82e1a7029c1ab4f5a48d2fa2c994b9ce5901f2621e3e5f1cab0d6eefc0b0d81c33f1611030b0ad7c17235ab978d58d2c047c96b83984cdd66ea0bf80cb2cbffa78c2ed56f4ba403a2cb95b5c1b2ea5bfc43c9dd78c8a3cd70c9ca4baee442816447e9bf9d87c0e917e1010001	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	\\xfe50bfb00919da5eb38708337a078e97da431577280f4052cab3d78b50e9ce5465a42d2f49df90154402238b11637f811e604258f62f98ec9d3c1c42b9dd660d	1580164809000000	1580769609000000	1643236809000000	1674772809000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x11af256cbd2f98f4a1df05b1d7aed3a96fcd3564898a4f812dc975e580354f9460a55fe332e5dc97761ec2dd0d3c3e5aa009d2fc0167990ceb8f498da61474aa	\\x0080000396da44d6f493a3f55201295837c2fae3916a24687ac93e356845b2e5f16a1273cc037cd284965bfcb8226baff0f71ca3802cd64f0a2046544bd4042d824a22e3ddb72687bdedf531fd7c9a52211282995e45d4ab7d7d75a4941ffd6aebfd408d7e39dd8773bc13740080ece5f48b8efdde3794fdec56bf08b996bbb1663d189b010001	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	\\x468d61ad582fa9dfb762cd88bc720c4f62eef1133161766ec142c257beefae9a252d304b1ee3cbeb5bd4e656164db5f08ac4a0c79943410191575994c20ae400	1578351309000000	1578956109000000	1641423309000000	1672959309000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xfb398283898de3cc81c0978c868abaa304a372b0a07023869d494a77a6cf703a3fbcd19b326a47ac14badbab3689f4add281c8ce27fa166ca5ffc034b4fcea36	\\x00800003cebddd710bb7599358729b5b661e9bb783a6f8657399fdb03ec171d8964e085b4fa9d86bebbbd882a323dcb947f406e5fb7d94c9ec425657a4fdd8f6ababee67fbe1b30962f30090cba1226a1259d5ba89f980c3855f82a5e5cb43fab36645a1c945928223f4ded8835244263e13d23ff73bf8dbdf487a93c310caae303cac7b010001	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	\\x37be77cfc16e7e7046c8d70b4eb08051f004d30311245e4c5c5c2a0b8bee0f2082fbd4a7ec1efacdcffeb5cf048e3fc7125e5d4639205410fcfba9e7f137c307	1577746809000000	1578351609000000	1640818809000000	1672354809000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xc18dfa8bb406882c2b35c4d597556c4f99f4f277d571d34c4c72840e4e409f42f2a028ded10465530d1b54f4230eaadf7b6eec1b52cc612a4dfbf6f37147301a	\\x00800003caa762dac0c3ec8afbc9082dca2969f595274590e2341ecfe0e2426b14e50ec265143f118679f8e9cc09d06401392451375cd7386e51c428d3199b2a435c33c4f0bed9f94a115294e8a1095af9c4414d39054bdc20f2cc4e390285f0b02ea4f8cbca5264eba20e64d99ee09a99090702374411d2bc821a09b3722b46ee4ad4ff010001	\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	\\x22129ea44d4ab1f5119171664f388f5c0e823ac018b461be60c7b2ed9e63778126eabb68d3cc2a0474b5cfbce06546050a575367abe09a8b01a94da7c744ee06	1578955809000000	1579560609000000	1642027809000000	1673563809000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_wire, "timestamp", refund_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	1	\\xbb6000c079183d9a6e01ae9311683a7482bbc01d5a75a5684057f80358884cfac2bcd6562d06dc3098516a1438a75916bddb419d79b2350f4b65d15a5b9cae12	\\x38f7af19e94d4260adc1c992317bd8091abd2abf701f247ecd2ff096aea5847a2e8780f13d606b5d044ffda62069b7a620de819a3d7c0dd75d5e97dfa3010187	1577746825000000	1577747725000000	0	9000000	\\x7af4e3f10b04c9539301df4e2f57fde27be0992fc9694eef34e7f848657379b2	\\xddedb8f7b17581176240985628acafec965e6574b4de75533378c7ac76de3fa9	\\x1d09523b1e6940b7e942565d1ea75c803cae22494474979cb5795feb91366f90c2147b4c9a6dc7faeba4e73d5e53b138fa29b8146d3503c08e9e26151637290d	\\xf8ccf7deeb4f45e006153839e8632a2a1dd0b3042463ed57fdaacdf035495dc6	\\x16a5a1b6757f000000000000000000002e1696b601000000e0e581b5757f0000e93e30a202560000c90d00b0757f00004a0d00b0757f0000300d00b0757f0000
\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	2	\\xbb6000c079183d9a6e01ae9311683a7482bbc01d5a75a5684057f80358884cfac2bcd6562d06dc3098516a1438a75916bddb419d79b2350f4b65d15a5b9cae12	\\x38f7af19e94d4260adc1c992317bd8091abd2abf701f247ecd2ff096aea5847a2e8780f13d606b5d044ffda62069b7a620de819a3d7c0dd75d5e97dfa3010187	1577746825000000	1577747725000000	0	9000000	\\x34bdd9dfe7dff0f47ceff707d3fe076c98f1057b6a708884d9c12af5cd9a6615	\\xddedb8f7b17581176240985628acafec965e6574b4de75533378c7ac76de3fa9	\\x8caec27681c30f9bb378813849426c01ff3ce2503b54d4dca944656ebcd147401644a523c94a9fe8f29c3c14ffe7a2e3a5de6fb4d6d9a2644a5bd593a2d8e40a	\\xf8ccf7deeb4f45e006153839e8632a2a1dd0b3042463ed57fdaacdf035495dc6	\\x16a5a1b6757f000000000000000000002e1696b601000000e0e581b5757f0000e93e30a202560000896501b0757f00000a6501b0757f0000f06401b0757f0000
\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	3	\\xbb6000c079183d9a6e01ae9311683a7482bbc01d5a75a5684057f80358884cfac2bcd6562d06dc3098516a1438a75916bddb419d79b2350f4b65d15a5b9cae12	\\x38f7af19e94d4260adc1c992317bd8091abd2abf701f247ecd2ff096aea5847a2e8780f13d606b5d044ffda62069b7a620de819a3d7c0dd75d5e97dfa3010187	1577746825000000	1577747725000000	0	9000000	\\x2265a55b84f8a514b889276d058a1de7e7784adb6bfa431f28c8bbaa6af95447	\\xddedb8f7b17581176240985628acafec965e6574b4de75533378c7ac76de3fa9	\\x9762c7180815271e6a692d06674bb7a093704e0c8bcb8f8f47e77528bcb3e03f0a612a0b08d88f5ca3d0615c6fc045bf6333aa0a5e38b6ead42d26cf83f9d204	\\xf8ccf7deeb4f45e006153839e8632a2a1dd0b3042463ed57fdaacdf035495dc6	\\x16a5a1b6757f000000000000000000002e1696b601000000e0b57fae757f0000e93e30a202560000c90d0090757f00004a0d0090757f0000300d0090757f0000
\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	4	\\xbb6000c079183d9a6e01ae9311683a7482bbc01d5a75a5684057f80358884cfac2bcd6562d06dc3098516a1438a75916bddb419d79b2350f4b65d15a5b9cae12	\\x38f7af19e94d4260adc1c992317bd8091abd2abf701f247ecd2ff096aea5847a2e8780f13d606b5d044ffda62069b7a620de819a3d7c0dd75d5e97dfa3010187	1577746825000000	1577747725000000	3	18000000	\\xb001925bef7fd096fcf4648747ab50488dbecbadfa43e1925d18743c30334c46	\\xddedb8f7b17581176240985628acafec965e6574b4de75533378c7ac76de3fa9	\\x95cb989015f602658d5070dd742064d45aaacfe36809748e37e1eea1a6ee9dea36c4429dd9e340e4e4b65608f052ed7cfa4009dd160a13efc370ca2a1548a20d	\\xf8ccf7deeb4f45e006153839e8632a2a1dd0b3042463ed57fdaacdf035495dc6	\\x16a5a1b6757f000000000000000000002e1696b601000000e0c5ff4e757f0000e93e30a202560000c90d0034757f00004a0d0034757f0000300d0034757f0000
\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	5	\\xbb6000c079183d9a6e01ae9311683a7482bbc01d5a75a5684057f80358884cfac2bcd6562d06dc3098516a1438a75916bddb419d79b2350f4b65d15a5b9cae12	\\x38f7af19e94d4260adc1c992317bd8091abd2abf701f247ecd2ff096aea5847a2e8780f13d606b5d044ffda62069b7a620de819a3d7c0dd75d5e97dfa3010187	1577746825000000	1577747725000000	0	9000000	\\xbdbcbd6c9b197528af3e9ac9f700f69397df7877f71f2924467db57257c257e4	\\xddedb8f7b17581176240985628acafec965e6574b4de75533378c7ac76de3fa9	\\x8e744e8111b8a8c279eb92e7bf8a5d9e95f59caccc4bb996ecf522ffe1eb7a8ef40f2412484c9571ffffefb1276605537978a5a120dcdc4c2f293ded43aef505	\\xf8ccf7deeb4f45e006153839e8632a2a1dd0b3042463ed57fdaacdf035495dc6	\\x16a5a1b6757f000000000000000000002e1696b601000000e0957f8d757f0000e93e30a202560000c90d006c757f00004a0d006c757f0000300d006c757f0000
\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	6	\\xbb6000c079183d9a6e01ae9311683a7482bbc01d5a75a5684057f80358884cfac2bcd6562d06dc3098516a1438a75916bddb419d79b2350f4b65d15a5b9cae12	\\x38f7af19e94d4260adc1c992317bd8091abd2abf701f247ecd2ff096aea5847a2e8780f13d606b5d044ffda62069b7a620de819a3d7c0dd75d5e97dfa3010187	1577746825000000	1577747725000000	0	9000000	\\xec6f1d9c06959abdec02aeff3e15b54b980b6567082c3486ea09bf54770120e9	\\xddedb8f7b17581176240985628acafec965e6574b4de75533378c7ac76de3fa9	\\x7c221c35015f35523f437b1cc1fa52ac700a3cf9a5f9a1b8e874a6b089be577df1d55b0005f8fb7953a9769800ccbde61f71ee60001566a0f2bb583795324f01	\\xf8ccf7deeb4f45e006153839e8632a2a1dd0b3042463ed57fdaacdf035495dc6	\\x16a5a1b6757f000000000000000000002e1696b601000000e0e5ff4f757f0000e93e30a202560000c90d003c757f00004a0d003c757f0000300d003c757f0000
\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	7	\\xbb6000c079183d9a6e01ae9311683a7482bbc01d5a75a5684057f80358884cfac2bcd6562d06dc3098516a1438a75916bddb419d79b2350f4b65d15a5b9cae12	\\x38f7af19e94d4260adc1c992317bd8091abd2abf701f247ecd2ff096aea5847a2e8780f13d606b5d044ffda62069b7a620de819a3d7c0dd75d5e97dfa3010187	1577746825000000	1577747725000000	0	9000000	\\x33b8504a13520c63c5268358237fca89d1f823a345ec3b2fc2c273f0805e532e	\\xddedb8f7b17581176240985628acafec965e6574b4de75533378c7ac76de3fa9	\\xc7e92f3b9935edcd50aac3250f48aac2a6c50d20ba49f31ff2ee1c601c05bfb0b49352c5e89676d3b2ea18c172f142f73b7f1beaf2191f1ef277bd6758b66207	\\xf8ccf7deeb4f45e006153839e8632a2a1dd0b3042463ed57fdaacdf035495dc6	\\x16a5a1b6757f000000000000000000002e1696b601000000e0e5ffaf757f0000e93e30a202560000c90d00a4757f00004a0d00a4757f0000300d00a4757f0000
\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	8	\\xbb6000c079183d9a6e01ae9311683a7482bbc01d5a75a5684057f80358884cfac2bcd6562d06dc3098516a1438a75916bddb419d79b2350f4b65d15a5b9cae12	\\x38f7af19e94d4260adc1c992317bd8091abd2abf701f247ecd2ff096aea5847a2e8780f13d606b5d044ffda62069b7a620de819a3d7c0dd75d5e97dfa3010187	1577746825000000	1577747725000000	0	9000000	\\x552eab38574c9d8452aff87129e2f239c2db2bae6453c5c6ed37547307f10f67	\\xddedb8f7b17581176240985628acafec965e6574b4de75533378c7ac76de3fa9	\\xa5ccb623bd63feb2571a436f6bc0fcd781596743e81f55d939519acdb22fbc77c1691751f7617650e1ebe3675996c8e52b2bde47d842be4ffed0918c91de5105	\\xf8ccf7deeb4f45e006153839e8632a2a1dd0b3042463ed57fdaacdf035495dc6	\\x16a5a1b6757f000000000000000000002e1696b601000000e0d57faf757f0000e93e30a202560000c90d0098757f00004a0d0098757f0000300d0098757f0000
\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	9	\\xbb6000c079183d9a6e01ae9311683a7482bbc01d5a75a5684057f80358884cfac2bcd6562d06dc3098516a1438a75916bddb419d79b2350f4b65d15a5b9cae12	\\x38f7af19e94d4260adc1c992317bd8091abd2abf701f247ecd2ff096aea5847a2e8780f13d606b5d044ffda62069b7a620de819a3d7c0dd75d5e97dfa3010187	1577746825000000	1577747725000000	0	9000000	\\xa71cc8ca1486cbe2c3431bf4575dc37540729165156cfe78bba01edf1458ae04	\\xddedb8f7b17581176240985628acafec965e6574b4de75533378c7ac76de3fa9	\\x1cbc141da85e99bf2705059f8ad198f64684d7fa016fc201d8195e55a31483dc78cafa7c12351d98c6e7ebec886674f91b01415a3b0e176104df0fcbbf89ec09	\\xf8ccf7deeb4f45e006153839e8632a2a1dd0b3042463ed57fdaacdf035495dc6	\\x16a5a1b6757f000000000000000000002e1696b601000000e0e5ff2b757f0000e93e30a202560000c90d001c757f00004a0d001c757f0000300d001c757f0000
\.


--
-- Data for Name: deposits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits (deposit_serial_id, coin_pub, amount_with_fee_val, amount_with_fee_frac, "timestamp", refund_deadline, wire_deadline, merchant_pub, h_contract_terms, h_wire, coin_sig, wire, tiny, done) FROM stdin;
1	\\x7af4e3f10b04c9539301df4e2f57fde27be0992fc9694eef34e7f848657379b2	0	10000000	1577746825000000	1577747725000000	1577747725000000	\\xddedb8f7b17581176240985628acafec965e6574b4de75533378c7ac76de3fa9	\\xbb6000c079183d9a6e01ae9311683a7482bbc01d5a75a5684057f80358884cfac2bcd6562d06dc3098516a1438a75916bddb419d79b2350f4b65d15a5b9cae12	\\x38f7af19e94d4260adc1c992317bd8091abd2abf701f247ecd2ff096aea5847a2e8780f13d606b5d044ffda62069b7a620de819a3d7c0dd75d5e97dfa3010187	\\x3c0b6e9fcc5c485da4a90de7e68bbc511016b16dcfff0f20bbfbc25b03b408eda02915cf7f740e44aa2df302e97705ac14b5d4e77f651786bdb24b52c3302b06	{"url":"payto://x-taler-bank/localhost/42","salt":"CSX3GSF58VZWSTVZYH9C66TQFZ3TWZ31QSEK8M4QGEPZQ2D13DBFWYDJCH4AFFENWKZ217AMC6DWRZ2Y1YWKCAE5VSDSW7HZFDQR8F8"}	f	f
2	\\xec6f1d9c06959abdec02aeff3e15b54b980b6567082c3486ea09bf54770120e9	0	10000000	1577746825000000	1577747725000000	1577747725000000	\\xddedb8f7b17581176240985628acafec965e6574b4de75533378c7ac76de3fa9	\\xbb6000c079183d9a6e01ae9311683a7482bbc01d5a75a5684057f80358884cfac2bcd6562d06dc3098516a1438a75916bddb419d79b2350f4b65d15a5b9cae12	\\x38f7af19e94d4260adc1c992317bd8091abd2abf701f247ecd2ff096aea5847a2e8780f13d606b5d044ffda62069b7a620de819a3d7c0dd75d5e97dfa3010187	\\xa762552af7d46f275ee970ac7656678fef82bab47c0c010c3df364fb23058b1db2607962b9b858cf59ed97a9339bb6978ffc66a112f8db6c7b9d5fcc049ae001	{"url":"payto://x-taler-bank/localhost/42","salt":"CSX3GSF58VZWSTVZYH9C66TQFZ3TWZ31QSEK8M4QGEPZQ2D13DBFWYDJCH4AFFENWKZ217AMC6DWRZ2Y1YWKCAE5VSDSW7HZFDQR8F8"}	f	f
3	\\x552eab38574c9d8452aff87129e2f239c2db2bae6453c5c6ed37547307f10f67	0	10000000	1577746825000000	1577747725000000	1577747725000000	\\xddedb8f7b17581176240985628acafec965e6574b4de75533378c7ac76de3fa9	\\xbb6000c079183d9a6e01ae9311683a7482bbc01d5a75a5684057f80358884cfac2bcd6562d06dc3098516a1438a75916bddb419d79b2350f4b65d15a5b9cae12	\\x38f7af19e94d4260adc1c992317bd8091abd2abf701f247ecd2ff096aea5847a2e8780f13d606b5d044ffda62069b7a620de819a3d7c0dd75d5e97dfa3010187	\\xd4c09c3fc73487922bcea2bcc1a955e891950c88bed9f0b0443bd54f9d40e9f7abc259b6c89a433b4c82c766c5e173d6d8aa1943cbe9b5b700c4c5bad660900b	{"url":"payto://x-taler-bank/localhost/42","salt":"CSX3GSF58VZWSTVZYH9C66TQFZ3TWZ31QSEK8M4QGEPZQ2D13DBFWYDJCH4AFFENWKZ217AMC6DWRZ2Y1YWKCAE5VSDSW7HZFDQR8F8"}	f	f
4	\\xb001925bef7fd096fcf4648747ab50488dbecbadfa43e1925d18743c30334c46	3	20000000	1577746825000000	1577747725000000	1577747725000000	\\xddedb8f7b17581176240985628acafec965e6574b4de75533378c7ac76de3fa9	\\xbb6000c079183d9a6e01ae9311683a7482bbc01d5a75a5684057f80358884cfac2bcd6562d06dc3098516a1438a75916bddb419d79b2350f4b65d15a5b9cae12	\\x38f7af19e94d4260adc1c992317bd8091abd2abf701f247ecd2ff096aea5847a2e8780f13d606b5d044ffda62069b7a620de819a3d7c0dd75d5e97dfa3010187	\\x860346b7b10dfbe03178f327acc2934121bf571d6404f6f4a0a8ad8b07a98bc203c0898317490292e2d2f559b964bfddf80394655453212dfb5eb5f83162bc00	{"url":"payto://x-taler-bank/localhost/42","salt":"CSX3GSF58VZWSTVZYH9C66TQFZ3TWZ31QSEK8M4QGEPZQ2D13DBFWYDJCH4AFFENWKZ217AMC6DWRZ2Y1YWKCAE5VSDSW7HZFDQR8F8"}	f	f
5	\\x2265a55b84f8a514b889276d058a1de7e7784adb6bfa431f28c8bbaa6af95447	0	10000000	1577746825000000	1577747725000000	1577747725000000	\\xddedb8f7b17581176240985628acafec965e6574b4de75533378c7ac76de3fa9	\\xbb6000c079183d9a6e01ae9311683a7482bbc01d5a75a5684057f80358884cfac2bcd6562d06dc3098516a1438a75916bddb419d79b2350f4b65d15a5b9cae12	\\x38f7af19e94d4260adc1c992317bd8091abd2abf701f247ecd2ff096aea5847a2e8780f13d606b5d044ffda62069b7a620de819a3d7c0dd75d5e97dfa3010187	\\x4e8f69b4b71514973119cf2b320b5fbe180cd30be4130185b7c779a696334b8169519aafa9e2656479ecc7723046b3d3ac70f9e7f1677f5ee65b3a04f07ae906	{"url":"payto://x-taler-bank/localhost/42","salt":"CSX3GSF58VZWSTVZYH9C66TQFZ3TWZ31QSEK8M4QGEPZQ2D13DBFWYDJCH4AFFENWKZ217AMC6DWRZ2Y1YWKCAE5VSDSW7HZFDQR8F8"}	f	f
6	\\x34bdd9dfe7dff0f47ceff707d3fe076c98f1057b6a708884d9c12af5cd9a6615	0	10000000	1577746825000000	1577747725000000	1577747725000000	\\xddedb8f7b17581176240985628acafec965e6574b4de75533378c7ac76de3fa9	\\xbb6000c079183d9a6e01ae9311683a7482bbc01d5a75a5684057f80358884cfac2bcd6562d06dc3098516a1438a75916bddb419d79b2350f4b65d15a5b9cae12	\\x38f7af19e94d4260adc1c992317bd8091abd2abf701f247ecd2ff096aea5847a2e8780f13d606b5d044ffda62069b7a620de819a3d7c0dd75d5e97dfa3010187	\\x80b7c9970f82e86811968be28466970e07819d96b66416cb9256bb531a9f4e1e37df71a18016f5b968caae96a6648f1888a9403a3398eab4155222c1d116c201	{"url":"payto://x-taler-bank/localhost/42","salt":"CSX3GSF58VZWSTVZYH9C66TQFZ3TWZ31QSEK8M4QGEPZQ2D13DBFWYDJCH4AFFENWKZ217AMC6DWRZ2Y1YWKCAE5VSDSW7HZFDQR8F8"}	f	f
7	\\x33b8504a13520c63c5268358237fca89d1f823a345ec3b2fc2c273f0805e532e	0	10000000	1577746825000000	1577747725000000	1577747725000000	\\xddedb8f7b17581176240985628acafec965e6574b4de75533378c7ac76de3fa9	\\xbb6000c079183d9a6e01ae9311683a7482bbc01d5a75a5684057f80358884cfac2bcd6562d06dc3098516a1438a75916bddb419d79b2350f4b65d15a5b9cae12	\\x38f7af19e94d4260adc1c992317bd8091abd2abf701f247ecd2ff096aea5847a2e8780f13d606b5d044ffda62069b7a620de819a3d7c0dd75d5e97dfa3010187	\\x33055ffecea2111065512ac2738592614c21f679e295b1f891cade7c876bec944f39501d37b3fc026d970c0704b5af5c4d5560e1fa8c919329a5e43347a8b805	{"url":"payto://x-taler-bank/localhost/42","salt":"CSX3GSF58VZWSTVZYH9C66TQFZ3TWZ31QSEK8M4QGEPZQ2D13DBFWYDJCH4AFFENWKZ217AMC6DWRZ2Y1YWKCAE5VSDSW7HZFDQR8F8"}	f	f
8	\\xbdbcbd6c9b197528af3e9ac9f700f69397df7877f71f2924467db57257c257e4	0	10000000	1577746825000000	1577747725000000	1577747725000000	\\xddedb8f7b17581176240985628acafec965e6574b4de75533378c7ac76de3fa9	\\xbb6000c079183d9a6e01ae9311683a7482bbc01d5a75a5684057f80358884cfac2bcd6562d06dc3098516a1438a75916bddb419d79b2350f4b65d15a5b9cae12	\\x38f7af19e94d4260adc1c992317bd8091abd2abf701f247ecd2ff096aea5847a2e8780f13d606b5d044ffda62069b7a620de819a3d7c0dd75d5e97dfa3010187	\\x0b7e8c95f54519bffb27ac23806fe739eb39eda81f4b371f7f60d4ac0fff975384d6e1a2af7070fe948ea04abb8ffbe3ef962fae93a16527533980deec143a09	{"url":"payto://x-taler-bank/localhost/42","salt":"CSX3GSF58VZWSTVZYH9C66TQFZ3TWZ31QSEK8M4QGEPZQ2D13DBFWYDJCH4AFFENWKZ217AMC6DWRZ2Y1YWKCAE5VSDSW7HZFDQR8F8"}	f	f
9	\\xa71cc8ca1486cbe2c3431bf4575dc37540729165156cfe78bba01edf1458ae04	0	10000000	1577746825000000	1577747725000000	1577747725000000	\\xddedb8f7b17581176240985628acafec965e6574b4de75533378c7ac76de3fa9	\\xbb6000c079183d9a6e01ae9311683a7482bbc01d5a75a5684057f80358884cfac2bcd6562d06dc3098516a1438a75916bddb419d79b2350f4b65d15a5b9cae12	\\x38f7af19e94d4260adc1c992317bd8091abd2abf701f247ecd2ff096aea5847a2e8780f13d606b5d044ffda62069b7a620de819a3d7c0dd75d5e97dfa3010187	\\x59cdf201c9e5f1162948ae1c91b2d1965890c32faffe769398da63dee9eb8eb407a7679ca4380838ad99a02cd8b3ab41ebf7d85d4e442c285aa6e3eaeea42008	{"url":"payto://x-taler-bank/localhost/42","salt":"CSX3GSF58VZWSTVZYH9C66TQFZ3TWZ31QSEK8M4QGEPZQ2D13DBFWYDJCH4AFFENWKZ217AMC6DWRZ2Y1YWKCAE5VSDSW7HZFDQR8F8"}	f	f
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
1	contenttypes	0001_initial	2019-12-31 00:00:20.543172+01
2	auth	0001_initial	2019-12-31 00:00:20.568212+01
3	app	0001_initial	2019-12-31 00:00:20.609401+01
4	contenttypes	0002_remove_content_type_name	2019-12-31 00:00:20.628838+01
5	auth	0002_alter_permission_name_max_length	2019-12-31 00:00:20.632424+01
6	auth	0003_alter_user_email_max_length	2019-12-31 00:00:20.638238+01
7	auth	0004_alter_user_username_opts	2019-12-31 00:00:20.644107+01
8	auth	0005_alter_user_last_login_null	2019-12-31 00:00:20.651418+01
9	auth	0006_require_contenttypes_0002	2019-12-31 00:00:20.65272+01
10	auth	0007_alter_validators_add_error_messages	2019-12-31 00:00:20.657779+01
11	auth	0008_alter_user_username_max_length	2019-12-31 00:00:20.666132+01
12	auth	0009_alter_user_last_name_max_length	2019-12-31 00:00:20.675219+01
13	auth	0010_alter_group_name_max_length	2019-12-31 00:00:20.682829+01
14	auth	0011_update_proxy_permissions	2019-12-31 00:00:20.689277+01
15	sessions	0001_initial	2019-12-31 00:00:20.693708+01
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
\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1546297200000000	1577833200000000	\\xace56b4cf943508af59187e6473c380b90df4230175533e9d76af2fbb857cc9cf67e2967f1bf56090bd4818236da3a9f168c8d01c3283868fc6816d80b1fda00
\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1577833200000000	1609455600000000	\\x4270e77b6aa909cc2eeb165c588cc4f39f33cf6e063d207fa991c8b3dbaf98a49d37d3067907514d689b541f0b3e6a72fee3c8532c0c16a0f7dc3b88be514403
\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1609455600000000	1640991600000000	\\xbe2bfd6791ddc5622eccbb7a1dcee9519fa98e323f88bc0be89f476c68c923d4bb105ce86c469cc993670cd82f163cf80fe42f3d2b62a8f71c235235599efd0b
\\x87234c497f9699c642b0bfc126a6e75c01d46fac607df9c2f6fa19d67b2a3f14	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1640991600000000	1672527600000000	\\x0a9d68ba463ea5f96830432059b50e4af7b94bbab16fb2a50083ea80e23a3f0971759cf9a308b981844e66366d2ebb55e6b35507867be2c2c9a6bec04536ca0a
\.


--
-- Data for Name: known_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.known_coins (coin_pub, denom_pub_hash, denom_sig) FROM stdin;
\\x552eab38574c9d8452aff87129e2f239c2db2bae6453c5c6ed37547307f10f67	\\xe365d5ba3eaa89c4456f3b750e85ebe81978cc51aaf511b76875d60353394ba638e1fa423bcb16d9d0666598ec8e8baf053a97f679c58f8f2bf9f31c0dd702be	\\x47e7f7b12a9e62c6d3e0d3862df113fdecf80bdaf8ee48c268c33d08eeea5ebb7b72d7abf2e50d5ca93d1ac4017b006c29f324f4c187d54876128ced42261f6452d5e0d57aca55ece49423155d01a94ccfe0592a518073c1822e83352701424a2dbdea354abd36e7884a478521518aa113f4f954be3bf9b412dc3e14747da176
\\x7af4e3f10b04c9539301df4e2f57fde27be0992fc9694eef34e7f848657379b2	\\xe365d5ba3eaa89c4456f3b750e85ebe81978cc51aaf511b76875d60353394ba638e1fa423bcb16d9d0666598ec8e8baf053a97f679c58f8f2bf9f31c0dd702be	\\x382efb8e8f1e9abb020f7302e733cfb1acccdfb123dbf5394dfd40fdff4c943b44eda1599f64de62b93e74cd686ee07d360ee00e0a790dbce76c1fa3a15bf6f204c0eb81b24a785be296eb518b175b548448b469106980314d0775c802d7edc0eb0fc849d8e8c045d7e6447844241e75fdaf9c93f56bc98969f7a0059bdd713f
\\xb001925bef7fd096fcf4648747ab50488dbecbadfa43e1925d18743c30334c46	\\xfb398283898de3cc81c0978c868abaa304a372b0a07023869d494a77a6cf703a3fbcd19b326a47ac14badbab3689f4add281c8ce27fa166ca5ffc034b4fcea36	\\x24f443b2caebb8ed7766809e43cd44b00edad091bac56453c6273cbe6cbcb29008d41fb364387987f7b95f54b47049928afa82a2d708d7cdf72c6167de80c5f2d7a70ac7a4d3180d753617956cd18da99f8ab3acd8752256cef55730096e02d8343a0155a3a602fc4c5eb2c77ce85925a4b3ceddac846c3d7bec5c1b1f91d81f
\\xec6f1d9c06959abdec02aeff3e15b54b980b6567082c3486ea09bf54770120e9	\\xe365d5ba3eaa89c4456f3b750e85ebe81978cc51aaf511b76875d60353394ba638e1fa423bcb16d9d0666598ec8e8baf053a97f679c58f8f2bf9f31c0dd702be	\\x749d87a9d58cebb5de7fb25d1d3898bf6b036bd4d095a315c601f37a7d5631d4e9a00a066ac3f3e68513d7c89fed24c686df5a3f920ad0c61bd5baa1382cf4851f275cff5c3768468a4b4d2ac426947b9f034a7d501cb67354b25f3150a55f6398698e6f57bae462d984ba9ae16081fe81e82bd2cf433e4726b72caf9c64b02a
\\x2265a55b84f8a514b889276d058a1de7e7784adb6bfa431f28c8bbaa6af95447	\\xe365d5ba3eaa89c4456f3b750e85ebe81978cc51aaf511b76875d60353394ba638e1fa423bcb16d9d0666598ec8e8baf053a97f679c58f8f2bf9f31c0dd702be	\\x1075019968e64a0442466b2a8ed1b5fc31817164c30dbc7db8c9c17ca3b571046283308a180db6d711e9622682287952289b631d865f6f256abbb2119a26c811107c2b30fe3bdbd283ba35e3bfd79847c8274f103d4770505416e3e5aa8139d3f1eab7fa9b16be8e00973c48a0be37566ee26cd143f7f38d271db8431ef65e41
\\x34bdd9dfe7dff0f47ceff707d3fe076c98f1057b6a708884d9c12af5cd9a6615	\\xe365d5ba3eaa89c4456f3b750e85ebe81978cc51aaf511b76875d60353394ba638e1fa423bcb16d9d0666598ec8e8baf053a97f679c58f8f2bf9f31c0dd702be	\\x9d403248da56ab1d375d7e3231d4b826ed32c045cd275507c2dd13bf04419dfe6f8f5bc9705b3886bd56a81476bf12881428aebff4992efb51612cb81e5a70f2bdb8770dbea6ea2e130550e920ca4b6420ca1a8b4c893edb86e3accd7ff857c439cf10469d691ed9dcef04fecc1897b435aab8425f662dbd75480322a593d1d6
\\x33b8504a13520c63c5268358237fca89d1f823a345ec3b2fc2c273f0805e532e	\\xe365d5ba3eaa89c4456f3b750e85ebe81978cc51aaf511b76875d60353394ba638e1fa423bcb16d9d0666598ec8e8baf053a97f679c58f8f2bf9f31c0dd702be	\\x0a693396ca0a41b8d61533fc2d42b1e891a23006e25ca4973dc378d6110f2a5d89ede9374efd91ccd707fa93924f92cce93b696ab5fa29e3a03e2e1703c91b1f0bd681df711ae8b98949f093eaa475ebfd0f42d3d568da5df6681c8cdac13c3f71c269b5bc08f4789b297f9f458412bbe94209918d4e6872109aab27f40877c9
\\xbdbcbd6c9b197528af3e9ac9f700f69397df7877f71f2924467db57257c257e4	\\xe365d5ba3eaa89c4456f3b750e85ebe81978cc51aaf511b76875d60353394ba638e1fa423bcb16d9d0666598ec8e8baf053a97f679c58f8f2bf9f31c0dd702be	\\x6fededc2732d51e3dc862e1927e587d8f10b0577add7743c73bcee46bbcb3cc0325a4fb012db8b708ce56fda5a26f0b52197e04428eaddb28c1a6d947f19f2134200a149d8562bf3c75d0c2ef35c29e1a393421be2c46298cfc8fe1f7a52c8e7711b8cd66b25dfc4265591c8d110ddbfbed67f8df167002748e34252dc21ae2f
\\xa71cc8ca1486cbe2c3431bf4575dc37540729165156cfe78bba01edf1458ae04	\\xe365d5ba3eaa89c4456f3b750e85ebe81978cc51aaf511b76875d60353394ba638e1fa423bcb16d9d0666598ec8e8baf053a97f679c58f8f2bf9f31c0dd702be	\\x094ac8ee40751cbf4dc55389e6968989ef93e4dd642ea02f5de6ea0dcb7aaaf61ae0d8cd9ca60d140431b7ac21036f843cf595256fc5675bb5704c59c8a2e2d3b5d440f889e89f1fe192596f6811cbd1be053df4e64cc648ad3f9dfa15e088e6083ec572cde355782d4b5197fcdd6a679500f3df701c3f2d72fbcaca5977b465
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_id, merchant_pub, contract_terms, h_contract_terms, "timestamp", row_id, paid) FROM stdin;
2019.365-0282D8HQ949X2	\\xddedb8f7b17581176240985628acafec965e6574b4de75533378c7ac76de3fa9	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313537373734373732353030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313537373734373732353030307d2c226f726465725f6964223a22323031392e3336352d30323832443848513934395832222c2274696d657374616d70223a7b22745f6d73223a313537373734363832353030307d2c227061795f646561646c696e65223a7b22745f6d73223a313537373833333232353030307d2c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a224757484d524a425a4a54435743474e47515a304a4439513742473058385658434331595a4b4751505a3843584359534137574130227d5d2c2261756469746f7273223a5b5d2c22685f77697265223a223733565459364639394e31363142453153363933325959523134444254414e5a4530464a385a5044355a523944424e35474858325831573059345950305454583048375a56394830443656544338365947364433545a30445458454e5835595a4d433047333152222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a2256515056485858484550304845524a304b31423248423546584a42355753424d504b4637414d534b463333545258505937594d47222c226e6f6e6365223a22344d4b375035523033504e364e464337595239364456313532435237464535594b4e384a524447413036474b335a565352435130227d	\\xbb6000c079183d9a6e01ae9311683a7482bbc01d5a75a5684057f80358884cfac2bcd6562d06dc3098516a1438a75916bddb419d79b2350f4b65d15a5b9cae12	1577746825000000	1	t
\.


--
-- Data for Name: merchant_deposits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_deposits (h_contract_terms, merchant_pub, coin_pub, exchange_url, amount_with_fee_val, amount_with_fee_frac, deposit_fee_val, deposit_fee_frac, refund_fee_val, refund_fee_frac, wire_fee_val, wire_fee_frac, signkey_pub, exchange_proof) FROM stdin;
\\xbb6000c079183d9a6e01ae9311683a7482bbc01d5a75a5684057f80358884cfac2bcd6562d06dc3098516a1438a75916bddb419d79b2350f4b65d15a5b9cae12	\\xddedb8f7b17581176240985628acafec965e6574b4de75533378c7ac76de3fa9	\\x7af4e3f10b04c9539301df4e2f57fde27be0992fc9694eef34e7f848657379b2	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\xf8ccf7deeb4f45e006153839e8632a2a1dd0b3042463ed57fdaacdf035495dc6	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22334d344e34455259443530424654413241534548583954574730594157384a39384854394637354e46354659513439504459384334353356394a443656485a5458454a45454641594145524b485948395130413654443833523237395739474e3252564a4a3338222c22707562223a225a33364646515142395832593031474e3730575947525341353845583143523434484859544e5a584e42365a3044413942513330227d
\\xbb6000c079183d9a6e01ae9311683a7482bbc01d5a75a5684057f80358884cfac2bcd6562d06dc3098516a1438a75916bddb419d79b2350f4b65d15a5b9cae12	\\xddedb8f7b17581176240985628acafec965e6574b4de75533378c7ac76de3fa9	\\x2265a55b84f8a514b889276d058a1de7e7784adb6bfa431f28c8bbaa6af95447	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\xf8ccf7deeb4f45e006153839e8632a2a1dd0b3042463ed57fdaacdf035495dc6	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a224a58484345363038324d4b4857544b39354d3336454a58514d323951304b4743484635525a3354375758544a4846354b57305a474d52394131433444483354574d46383632513346523132565952534b4e38353557453550584241325439504647465758343130222c22707562223a225a33364646515142395832593031474e3730575947525341353845583143523434484859544e5a584e42365a3044413942513330227d
\\xbb6000c079183d9a6e01ae9311683a7482bbc01d5a75a5684057f80358884cfac2bcd6562d06dc3098516a1438a75916bddb419d79b2350f4b65d15a5b9cae12	\\xddedb8f7b17581176240985628acafec965e6574b4de75533378c7ac76de3fa9	\\x33b8504a13520c63c5268358237fca89d1f823a345ec3b2fc2c273f0805e532e	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\xf8ccf7deeb4f45e006153839e8632a2a1dd0b3042463ed57fdaacdf035495dc6	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22525a4d4a5945575336515057544d354152434a47594a354152414b43413339305139345a36375a4a5852453630373035515952423934544a52514d394358504b50424e314847424a593531464545565a33464e463436385a335653374646423742325636343152222c22707562223a225a33364646515142395832593031474e3730575947525341353845583143523434484859544e5a584e42365a3044413942513330227d
\\xbb6000c079183d9a6e01ae9311683a7482bbc01d5a75a5684057f80358884cfac2bcd6562d06dc3098516a1438a75916bddb419d79b2350f4b65d15a5b9cae12	\\xddedb8f7b17581176240985628acafec965e6574b4de75533378c7ac76de3fa9	\\x34bdd9dfe7dff0f47ceff707d3fe076c98f1057b6a708884d9c12af5cd9a6615	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\xf8ccf7deeb4f45e006153839e8632a2a1dd0b3042463ed57fdaacdf035495dc6	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22484a514334584d315243375351435652473457344a474b4330375a4b53524a47374441443951353938484a505846364838583031434835353446344d4e375a38594145335235375a5759484537394559445954444450443243483535514e434b4d424345383247222c22707562223a225a33364646515142395832593031474e3730575947525341353845583143523434484859544e5a584e42365a3044413942513330227d
\\xbb6000c079183d9a6e01ae9311683a7482bbc01d5a75a5684057f80358884cfac2bcd6562d06dc3098516a1438a75916bddb419d79b2350f4b65d15a5b9cae12	\\xddedb8f7b17581176240985628acafec965e6574b4de75533378c7ac76de3fa9	\\x552eab38574c9d8452aff87129e2f239c2db2bae6453c5c6ed37547307f10f67	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\xf8ccf7deeb4f45e006153839e8632a2a1dd0b3042463ed57fdaacdf035495dc6	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a224d5136424338585843465a42344e525438445150514737575459304e4a5354335830464e42503953413644435643484651485657325438514137565032584a4757374e59365354534a563445414153425653335847474e59395a5a44313443434a374635323138222c22707562223a225a33364646515142395832593031474e3730575947525341353845583143523434484859544e5a584e42365a3044413942513330227d
\\xbb6000c079183d9a6e01ae9311683a7482bbc01d5a75a5684057f80358884cfac2bcd6562d06dc3098516a1438a75916bddb419d79b2350f4b65d15a5b9cae12	\\xddedb8f7b17581176240985628acafec965e6574b4de75533378c7ac76de3fa9	\\xa71cc8ca1486cbe2c3431bf4575dc37540729165156cfe78bba01edf1458ae04	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\xf8ccf7deeb4f45e006153839e8632a2a1dd0b3042463ed57fdaacdf035495dc6	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22334a5931383744384254435659395235305046524e4d435259533338394e5a543035515734304552333546354238524d47464537484a5154464739334137435252564b5951563438435354464a3652313835443350334751433432445933594251593459523238222c22707562223a225a33364646515142395832593031474e3730575947525341353845583143523434484859544e5a584e42365a3044413942513330227d
\\xbb6000c079183d9a6e01ae9311683a7482bbc01d5a75a5684057f80358884cfac2bcd6562d06dc3098516a1438a75916bddb419d79b2350f4b65d15a5b9cae12	\\xddedb8f7b17581176240985628acafec965e6574b4de75533378c7ac76de3fa9	\\xbdbcbd6c9b197528af3e9ac9f700f69397df7877f71f2924467db57257c257e4	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\xf8ccf7deeb4f45e006153839e8632a2a1dd0b3042463ed57fdaacdf035495dc6	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22485354345830384851324d43345946424a424b565a324a584b54415a42373543534835564b355143594d48465a524642464137463833533432393434533542485a5a5a595a4339374352324e365942524d50474a315136573947514a4a46464438455146413138222c22707562223a225a33364646515142395832593031474e3730575947525341353845583143523434484859544e5a584e42365a3044413942513330227d
\\xbb6000c079183d9a6e01ae9311683a7482bbc01d5a75a5684057f80358884cfac2bcd6562d06dc3098516a1438a75916bddb419d79b2350f4b65d15a5b9cae12	\\xddedb8f7b17581176240985628acafec965e6574b4de75533378c7ac76de3fa9	\\xec6f1d9c06959abdec02aeff3e15b54b980b6567082c3486ea09bf54770120e9	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\xf8ccf7deeb4f45e006153839e8632a2a1dd0b3042463ed57fdaacdf035495dc6	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2246474831524438314257544e344654334643454333594a4a4e4852304d4637534d51575433453738454a4b42313244594158595a334e41563030325a4859565341454d5144363030534a59594337564858534730303542364d335342505031514a4d5334593038222c22707562223a225a33364646515142395832593031474e3730575947525341353845583143523434484859544e5a584e42365a3044413942513330227d
\\xbb6000c079183d9a6e01ae9311683a7482bbc01d5a75a5684057f80358884cfac2bcd6562d06dc3098516a1438a75916bddb419d79b2350f4b65d15a5b9cae12	\\xddedb8f7b17581176240985628acafec965e6574b4de75533378c7ac76de3fa9	\\xb001925bef7fd096fcf4648747ab50488dbecbadfa43e1925d18743c30334c46	http://localhost:8081/	3	20000000	0	2000000	0	4000000	0	1000000	\\xf8ccf7deeb4f45e006153839e8632a2a1dd0b3042463ed57fdaacdf035495dc6	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a224a5135534834304e59523136423341474533455138383334544844414e4b5a33443034513933485157375141333951454b514e33444832324b51435936473734574a5635433237474142505153594a30313745484332474b585a3151314a4841324e3441343338222c22707562223a225a33364646515142395832593031474e3730575947525341353845583143523434484859544e5a584e42365a3044413942513330227d
\.


--
-- Data for Name: merchant_orders; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_orders (order_id, merchant_pub, contract_terms, "timestamp") FROM stdin;
2019.365-0282D8HQ949X2	\\xddedb8f7b17581176240985628acafec965e6574b4de75533378c7ac76de3fa9	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313537373734373732353030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313537373734373732353030307d2c226f726465725f6964223a22323031392e3336352d30323832443848513934395832222c2274696d657374616d70223a7b22745f6d73223a313537373734363832353030307d2c227061795f646561646c696e65223a7b22745f6d73223a313537373833333232353030307d2c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a224757484d524a425a4a54435743474e47515a304a4439513742473058385658434331595a4b4751505a3843584359534137574130227d5d2c2261756469746f7273223a5b5d2c22685f77697265223a223733565459364639394e31363142453153363933325959523134444254414e5a4530464a385a5044355a523944424e35474858325831573059345950305454583048375a56394830443656544338365947364433545a30445458454e5835595a4d433047333152222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a2256515056485858484550304845524a304b31423248423546584a42355753424d504b4637414d534b463333545258505937594d47227d	1577746825000000
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
-- Data for Name: payback; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.payback (payback_uuid, coin_pub, coin_sig, coin_blind, amount_val, amount_frac, "timestamp", h_blind_ev) FROM stdin;
\.


--
-- Data for Name: payback_refresh; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.payback_refresh (payback_refresh_uuid, coin_pub, coin_sig, coin_blind, amount_val, amount_frac, "timestamp", h_blind_ev) FROM stdin;
\.


--
-- Data for Name: prewire; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.prewire (prewire_uuid, type, finished, buf) FROM stdin;
\.


--
-- Data for Name: refresh_commitments; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_commitments (melt_serial_id, rc, old_coin_pub, old_coin_sig, amount_with_fee_val, amount_with_fee_frac, noreveal_index) FROM stdin;
1	\\xa7764ace151925f4f6144cbe0e1865ccdda36db822fee9342104ddd66c345bbaca1123ae000e5cf47a02063cb3fe69d83f795b954ac549745132157e9b04bd3b	\\xb001925bef7fd096fcf4648747ab50488dbecbadfa43e1925d18743c30334c46	\\x8bf81384b1b2daa8af3e493fcd7aca8e95c31ed96eaacfe2825e4fac5b9c329b454152192ba916ae6860ff7c1b6645b5716d4af53e4dea32da679a67bac71805	4	80000000	1
\.


--
-- Data for Name: refresh_revealed_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins (rc, newcoin_index, link_sig, denom_pub_hash, coin_ev, h_coin_ev, ev_sig) FROM stdin;
\\xa7764ace151925f4f6144cbe0e1865ccdda36db822fee9342104ddd66c345bbaca1123ae000e5cf47a02063cb3fe69d83f795b954ac549745132157e9b04bd3b	0	\\xc841886e538b0a299f7b71f5ba9b43b32f2dda049e906cb3972416a2eed6e939dbaa40b057779d8eb6ac95fb8fe114602ddea6d47211d52d80760bf39bcd3e0c	\\x670d3b91a68a7996d41995040ba893619a55336da491ca17b900c282a6d1ee411f63881a8bac146d942024396893a06c11b01127ecc5d44817ff4658a0123d67	\\x39903f5b73f779fd6d70797ae77b169784ea7f99f8e6ea0cdc226aea6c8e3c7877a73f4fb0decb9b9a71a1c5146937bc13d0040df7eeae7df7a94e2e2f66c26f3557966d52d60c2d6fbd54615ced519f516b8caba916fe4a79dcfcf3b86ba3ea407ec5db06a54246ebce92e37e9dd6d642965e7fdfda0967c94490cf7b99d949	\\xb6d71c7a6465dd7e96daf7b4cdbabc96544d28eaa81d2c666ef55a8570a63e3d8ef62a3ea6314095c1f6e3f779446aed95f16a7674d537158d8da2a761841fb3	\\x22be3fe28cf0f0e0ed20ef390973973596a83546e337528a4b36f285939a448f4f0721ce60375d8cf33cfd1485632931a4608139ba2c039b9d62c3b0dee3204fc02978a746c260b587eca4c1ec36a5b94827c6345f90f2bb8e4713c6b50c50dbf50282062a19f5a190f8f78c5689114421517be7c4f2320cc7d1d383b635eadf
\\xa7764ace151925f4f6144cbe0e1865ccdda36db822fee9342104ddd66c345bbaca1123ae000e5cf47a02063cb3fe69d83f795b954ac549745132157e9b04bd3b	1	\\x9c312cf85158ff23e902be945b7601bad0c830c135cf7f56421dfc59047d786b266ed83d0fb9a7924d75ad5ee140243732ab41f16656984d1efaf7b662de920d	\\xe365d5ba3eaa89c4456f3b750e85ebe81978cc51aaf511b76875d60353394ba638e1fa423bcb16d9d0666598ec8e8baf053a97f679c58f8f2bf9f31c0dd702be	\\x4209421fa4ab8d83ec05bdb3b7d4b28bc5418b2006c4571af42151ae3f72bff2549416593824aee9b8053a68e588fb0de2a7575909871514ec3bc5aa13656f7f48267b83314124cf7fe6fd7dc34bb41861b7249b9eaaa8f4edc8a75f97b3002657c2c23691aed4d08834afb540dd64b04c015b1ff17c1c5cb856cc8030c7f58c	\\xe72b046f742e7728a8a5da83f7cd486f19f785f953129416cd0d67a38a39d79de6be1bf965fe37dc4143a23654517f58bef83c475b75dd714158b1442d27e39e	\\x8068f773f63a9c7fb7cec7cbaaa35397890e829c1785451993015b06d43851de8e3832b5db2a292d81f6b45988164b72301e4d9dd373289ca035776d94b241fb959abe988fbbaa2c52098342895b5922f5bef525d92c39bd62b0eb9b14432d9bc161ec00ecbb003c3b22a360c464f3081818ac7b233dea099d81c0aa2d80b24d
\\xa7764ace151925f4f6144cbe0e1865ccdda36db822fee9342104ddd66c345bbaca1123ae000e5cf47a02063cb3fe69d83f795b954ac549745132157e9b04bd3b	2	\\xc4066afffa28f89e7986445114fe298cc35b5d750140170920260ef7a1479f3f5550e0a91c12ff3099e4b5e3794f8ed7b7c9f148d5774b72b05a6956b73c0607	\\xe365d5ba3eaa89c4456f3b750e85ebe81978cc51aaf511b76875d60353394ba638e1fa423bcb16d9d0666598ec8e8baf053a97f679c58f8f2bf9f31c0dd702be	\\x49311597ce7b54993612921877a162b7ae8a8d2fdd379c8a062bea62fccff65eb498e139d81179a50da80501f22748ff72f991a36f488874143cf7f3ac4d6cecc061fc7fd88be27b734b5f5f5b5108da0b3584b4b6ad4fb0560b7726ee3e0be0e044e3c49f9d3eda8a5531bab98a92f117c7b569833b15bb94532277323c3576	\\xd21bd1e5ebbeb360d1dd5c657c80ea5897ce324323cba4109d2d57bc7cecc9219ae4f8c0491b8f99e469f50c3f6c82639305197011db008988e193ffba7030bd	\\x1c9d27cd78e13f558a005a998f127d41202e547d0b4873f0fd8277339c14904258a180d615f3425c405e56aa84633ba0e42d227aca4f34290bcd6200a9cd3159889104ffe987f9a37fa51c33a581266773260f39b5f25443061b37a9ad7ff28c45e0592ea2c6546c8827655708832817831325874f93f9593a06db1c31060548
\\xa7764ace151925f4f6144cbe0e1865ccdda36db822fee9342104ddd66c345bbaca1123ae000e5cf47a02063cb3fe69d83f795b954ac549745132157e9b04bd3b	3	\\x83ef36d82bf660629195113031855227b6e51eb7a1fba8021eec12bdd35df46d31adaf36b226f1f7fb2c69a0c9d06eb12e4f4bedaf7347b443fe2196e7677f0e	\\xe365d5ba3eaa89c4456f3b750e85ebe81978cc51aaf511b76875d60353394ba638e1fa423bcb16d9d0666598ec8e8baf053a97f679c58f8f2bf9f31c0dd702be	\\x871cc5667b3b233c6475223a0805b7d9a58ce1936fabad3a56f49b112734d3d91268c28e144e5e1018fa690139d38ac0d6bf1f08f8c1792383845fd163d3667c289e0e1d7c7f73d2b18cac478ea38746b793f3f7b2cacede579d7625522a6779ca018bdf0eb7217e23f415c3f10815bff960f9b6db126f4f4295d3ac157745f5	\\x1805684a2f5268e77064064e1083b356b585846c956aab5fdbc99063de99e2ff28e0ccd460a096c3bd2e2a01342b6d52bd415d75be0fc5c973051d8c4c36c9de	\\x2d3a17f7dc6ae027c9fab0f2a3bb1771059d96d4f9d24e9d96400c44f1b57eb61d07a4d4c059edc4fe7ed1b2dcf046cb25dd50b6f5d66c72f00c4b39909e4523f559eebb0954888138fc8e6ab1b908d82a1796b9234c0cc7fa0e2cea0f1c9079ac3f532b0c6bd3125e32acf0d3843afa702d62ab53ac977de449d243b8402a27
\\xa7764ace151925f4f6144cbe0e1865ccdda36db822fee9342104ddd66c345bbaca1123ae000e5cf47a02063cb3fe69d83f795b954ac549745132157e9b04bd3b	4	\\x0615b76ac043202a30f17b2858dc2ce2498baeccdb6c89ad8061744c3f2807aad9038e582d7721cfaf46f6ac4b29f701e38216d49ae1fcb94c0e977a4636f80b	\\xe365d5ba3eaa89c4456f3b750e85ebe81978cc51aaf511b76875d60353394ba638e1fa423bcb16d9d0666598ec8e8baf053a97f679c58f8f2bf9f31c0dd702be	\\x08fa887c78b604db1826a977521d8171e99fc2dfb91ff7913a05ef97ee3d72c413f4402d3ec30c4e981ea8e1850e0d183831fa7868d46719b5562293dd776077a392984bb3d5d9fd361cabe9eb1018d7a12934f7524d62d6f855f1e7bc1f4c8728e29b97047bd2d6ddd781a38e8dc76d7ccf6d6024f205c8c6d559f5ed328b2a	\\x1820cc24ee12db46c963f5efbe6fde21b30c0e0fa77e0a831f3443d2b89594671752557d8ae08b554b70bcfef909319a5054cc449a51e157befdd7993f3f851c	\\x44403ff1790645aa201c25730bcc82f60b1cc0b3447eb3fe8b5658f00fae0c408a2a1024d5abe4690623eaf014f28e6dcffacdf5f2d21f0ced1614135edc20fa288231a230057bbc48f5081b53539f58e6777ab5e64cea1fb719fa72d46704c911412ccb551168048b0a8667130aeaef3f0ccecf0756dcf153ded7eb4711c01f
\\xa7764ace151925f4f6144cbe0e1865ccdda36db822fee9342104ddd66c345bbaca1123ae000e5cf47a02063cb3fe69d83f795b954ac549745132157e9b04bd3b	5	\\x3a1dc0bb3a3e588353da87237eae5042fe84a9c4f1c878e85521c6cf1856b0b9b43818eca0310c71ee404be5220c81b78f7076f1a1c7a88c1112c7a33977f000	\\xe365d5ba3eaa89c4456f3b750e85ebe81978cc51aaf511b76875d60353394ba638e1fa423bcb16d9d0666598ec8e8baf053a97f679c58f8f2bf9f31c0dd702be	\\xa929ec18317e6dd5f55f58f486ab48fc37e72b86623e804ca471edd034f16d77b211bc717874ad698ec3047bc43350b3815ca5ba862bdd7b39705d1e8f5ce437920c07b46215ef3bbf6f277bb1329861c3eb1e06db0011550d58ffc662410b0473a171364a5f4ad704234b3a34309e2cc09bae37e0d7e0a7a1b9ae494aa62344	\\xc111851ef0b721c5daae92d55f8e06e7e79f5e18c879e814c49e3599c14d54d8e8e033d4f5a8f407ebdec2559ceeed5cd3b70e0d95bd2e17b15deb9ac853664f	\\x5ec374bec7077b25c8625b10aae5c4f70d4b6bc0e77e74e6f5c865aab5db49c81bcdf23a80e8d5895977693a231959f35c9423ada7d63a8bf218880a58160f133f43a17beb247657c8f5dfbf2ba767c27b7de6306271eebad0a907f56df6e1db7107a82d83e7547bbe1ba785e505ef7bdec55fa316d8ff0732b526c5773f5878
\\xa7764ace151925f4f6144cbe0e1865ccdda36db822fee9342104ddd66c345bbaca1123ae000e5cf47a02063cb3fe69d83f795b954ac549745132157e9b04bd3b	6	\\x81148a1a19b6c0202a8ddb6879cb1689d5397b99deb86894ec4e41fb5810ac6554d639af52bd83c278f585c3a9797cce6cc797dada37ccb9604bd8f7ab320606	\\xe365d5ba3eaa89c4456f3b750e85ebe81978cc51aaf511b76875d60353394ba638e1fa423bcb16d9d0666598ec8e8baf053a97f679c58f8f2bf9f31c0dd702be	\\x5b029f11de0fb32141eb610efbd01453459b73fa420b10068b5e8171f13314b3ffd1764e9cc0c3285e86380daa83e8d881d02191e4a8bf592aa260b86f40c21af8456bb389758f6ad140b881c6f10b5a49a97fcf9f636affadbfe29c63273adb42b81f4cd7dfc46c48624835a3cadb2a3851641c2ff521bd6687d92623053d48	\\xc8849f3e7fa52103c3f7865c06ab2458c894579ef99fb5b086fbd5c125fe30d9e5e68996b9b81a42cfed8395a6e28e4837e2065c5af17e12629f21e13e0d45c9	\\x4519d7ce5b86dbd07ceccdb276ae8e54576e4a560f5d7d7facd62efbc4506ebbe2e1738a5d964d2180bf524e2cb3ffc3c32fe9a8ef37892961fbe6c9b4520382b566127bfef55f995f2986beab45b5955153763e08ac461eef15cec251470087eb5e3bf643d69775d3cc3fc8b2892c60ff4c653215c4b4801406c9b348a7d8e9
\\xa7764ace151925f4f6144cbe0e1865ccdda36db822fee9342104ddd66c345bbaca1123ae000e5cf47a02063cb3fe69d83f795b954ac549745132157e9b04bd3b	7	\\x5289862dcdac966d14727fb31a5387f670f7f469577402965512cd49f30791d530bb24eb476af407e610548d06ded1208db6e4bfdd638ae8c536656e2199630d	\\x5d410f92c0f49b70ccd357b8a35b955d539d740e811d98fe687785e9cf85f3f0abda538ced18de5be61e49ef3e56bc2d167296db254cae2ad1df6e8851374785	\\x1add0b3004c6d4ba061bb0a2744202d04ff4bc36498ca64a9c239ad939a185208e7ad8f3667897f1c71cabf1499f2cbc3993028a5fe263c277a6faac28a34a625fea982fba2bb8b668e077e3e8709015b624a1b593e16bdcf18cf9c291d19f01697c2460e4023f8df5397931072064e55144b1351d3cd7e7a5d464db838cdae5	\\x78386813b528651806e9cb919a665b085c81aecb3b65905b64b22222c5331146e728e7c95948f0b71ece2437fc85ec8299da260bfe3a78dff88cf303d3616f59	\\x5834ad399acf1b51052b23241108ddbbb2fe6b49401515072d92b6472805757f2f87314319ee46c0aa9a764c59693a43e4641f87d7a0ec3142c6632b4c13166ad91c83ab1f1e0ded2526025018c7da7bd5cb274543994d9098083ac632f74582c2a91692754d36e22dfbeb3c2c54612f47847688ca0370496b6dd5fbae5da1f1
\\xa7764ace151925f4f6144cbe0e1865ccdda36db822fee9342104ddd66c345bbaca1123ae000e5cf47a02063cb3fe69d83f795b954ac549745132157e9b04bd3b	8	\\x3d743f1c0a30d53999a333e55d9e6d7b406d88c0543bf464618bbc1e5bfa7565e8a478e81c48c64aae974536697026f910a1de013796ff66d30ebdae00a8fe0d	\\x5d410f92c0f49b70ccd357b8a35b955d539d740e811d98fe687785e9cf85f3f0abda538ced18de5be61e49ef3e56bc2d167296db254cae2ad1df6e8851374785	\\x8c2e58be9839b460011db45c79406e3ec524f5aec37b3b161d2cd7cbb2e4fd3d71f67b17e1ad257f095aaad473d126a7c4193d3153fa497a65cf63a58aed447462910c378f36369b0426a96131b906a296ad7997202bd808ded7b9cc5d09ac3f06df2e4855f73e6e498f6fdbf5c9e7e3434ae25525529ae6da8d23b6ee43d210	\\x56a444e09ce75b20d16cf2fc5a286ba47908434a713cce2f66e0044248205741d28e70c5ed53eef3d9d052ca51400a9748490c7f1d9e6ea2b6f67cd0eaa9322b	\\x8d63c2d973beb5781e278f3f438f7e66252714f7de47d3ab317f084248e93db28a8490aa4c1a1b3e7a2cf261aab5d4f936dee7889196fe1d2ff9300e1023b93d42a838c7520ad5c1d7a2f992459f065b7542068354f943c899b9100573ded29cb24ba418f79380b67cd6c81b6ca26d2e787b65738b97474ce973d53acb8bf13d
\\xa7764ace151925f4f6144cbe0e1865ccdda36db822fee9342104ddd66c345bbaca1123ae000e5cf47a02063cb3fe69d83f795b954ac549745132157e9b04bd3b	9	\\x8fcdb3d49c6526aaa0f5b0aba1d3ecb015fb6e042bfd0d9895d9a9aae9a50b37890508d72b9769d576f6fcb68ac8c4adf6ae0a0f8dcee0bd1943378a12e0be02	\\x5d410f92c0f49b70ccd357b8a35b955d539d740e811d98fe687785e9cf85f3f0abda538ced18de5be61e49ef3e56bc2d167296db254cae2ad1df6e8851374785	\\x6bd025013a53e2d9bf370d7d8e22aeda31012543a7ce72922125216248e973f18212e342342e1d30430a5ca9d6ca9d2eb8604ccb1805f889c067b090b6c5904d9af5e8cf42df44b4e6b5a5c86d9e1e2b4b56be57ba87df526b818df7f1f710c2050c1816a63f722c6659d350d3cc6efad0c2e7065795b9cf5b509f43e548daa2	\\xab1a7e6a93c82d51df46bd87043426a731de6fefee775ee4e1a3cbaad9f95c1bbdc56636b374770e33b9009cbeb3b4278f00016f521e327d3e7dfcbb151b2a18	\\x3a9d68d90745b7a264883e18ddc4dcaeb27ef23627409345f0e874c19c77a9999a1eb7ea68c9e8b818ae792eb3ae7f55a96f695287c18d347e4ee965268d6deff9b1047b927552798acd1c10a5cbe4b69cf73ee63d28a2e44eef60b4c7719a036c31cfdc70bc9ad6343aabed59e7faf934d1ca482a8657493023a3b2294681f7
\\xa7764ace151925f4f6144cbe0e1865ccdda36db822fee9342104ddd66c345bbaca1123ae000e5cf47a02063cb3fe69d83f795b954ac549745132157e9b04bd3b	10	\\x0a775750fb3ed5d4fb2567a35a9d7ef316058548f8862a538ce2f932492f7d5321aa5b48d0b972299973aa8abae740998151dadda4615850f68f0532ea355202	\\x5d410f92c0f49b70ccd357b8a35b955d539d740e811d98fe687785e9cf85f3f0abda538ced18de5be61e49ef3e56bc2d167296db254cae2ad1df6e8851374785	\\x8489af41da31d36d91868416b43c9d4ef4c0bfef4da21e6288e8236464b0a72405d9c0a73c8a7bbbc923e59f93d6f3ce51f8c513f943284a62a35dcc9d114f35cbdead27a3dd51f858779879341145b5c306ed36940f5b0c1a00ba44d9118e234bb19e1cd6ce8a86d85f3691271390a2342fdb4d45383d9aa2e627cd919256ae	\\x8ac80a31851168258361f6f1cb44db8b390fff74871c470baeda7291a4f37ef9ecd14d1b21b9c4a5e0a992e2d2cbc9dac5d8de784c30c34c7e11c68fcd136bee	\\xecae6a73b7e89f31d1a8758e6ea60fd21e1f5dd53e33a952cf30ff63ff387450df26a306f99621a076fff2f5dc4ac4c64d1975fb3d9c271b1c8f5e485afd9f9e2a9897dfab7983adb6c7470a1e9b12f6fecf9de71325c6f8676763b7915b272fdc8eb98715c24c383d2c95efdf604709c7700d8112105be67fc51bf8f01346
\.


--
-- Data for Name: refresh_transfer_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys (rc, transfer_pub, transfer_privs) FROM stdin;
\\xa7764ace151925f4f6144cbe0e1865ccdda36db822fee9342104ddd66c345bbaca1123ae000e5cf47a02063cb3fe69d83f795b954ac549745132157e9b04bd3b	\\x6c6b22d9dc37af4bf0e10a5a594faebdcaa553d0efac14e273d549d5fe5ebd4c	\\xd1af46a43e731dda58703851993752e0b9a16f7719eb5473a785e3ba456a560ed93dc28318c55f23cc6d67c61b762b7ddc39c6c438a79c0e55c8051cfe9d1788
\.


--
-- Data for Name: refunds; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refunds (refund_serial_id, coin_pub, merchant_pub, merchant_sig, h_contract_terms, rtransaction_id, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
\.


--
-- Data for Name: reserves; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves (reserve_pub, account_details, current_balance_val, current_balance_frac, expiration_date, gc_date) FROM stdin;
\\xacc14f28f816def0b5f159330eef0012212b3898330140dc3d4fab3a32b97659	payto://x-taler-bank/localhost/testuser-Zig0rCuT	0	1000000	1580166023000000	1798498825000000
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
1	\\xacc14f28f816def0b5f159330eef0012212b3898330140dc3d4fab3a32b97659	2	10	0	payto://x-taler-bank/localhost/testuser-Zig0rCuT	account-1	1577746823000000
\.


--
-- Data for Name: reserves_out; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out (reserve_out_serial_id, h_blind_ev, denom_pub_hash, denom_sig, reserve_pub, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\xb49383440f017a1516954fc5d408b533b58bb833a96c048c5e48065c26d1e3c6fe372b0df7df0c155facb4a27441ed3dd94a1a26dcfd8e13c9160ffbfa606c16	\\xfb398283898de3cc81c0978c868abaa304a372b0a07023869d494a77a6cf703a3fbcd19b326a47ac14badbab3689f4add281c8ce27fa166ca5ffc034b4fcea36	\\x9c063b30fbac59b2e9a4d7d6bb2d9bd98418f12c60fac4a53ebfa076c5cf95ef7c9161c85a012e4c1336ace7d1e8483482737e456b843fee08d3190f0c83b2b901fd26484ab01891d0834feb5271a30a5e2155617f84630328a032295e0a023c5a0493f9459536c52cacda6a0e4fa01cfbb50653c8872fe7e9adbfb214dbafad	\\xacc14f28f816def0b5f159330eef0012212b3898330140dc3d4fab3a32b97659	\\xbff21acda34bcfa412dcff623dae846d60e4d50981d43800c61955fb35aa1173e7e48316739fda2b34a607d21be7ba9930ce9219a3a1dc254d7442908897f908	1577746824000000	8	5000000
2	\\xff0f508eb23c17560d6c02fe891edd97ffb58f4fa967584c6c4dfdbade940497900f207dbe831b81f63a5b459b30eb97408a71f0827b1bdc8fd7b10e6246f12a	\\x6a59aa868a47da4fe4e8da0ede7874acef904a8fe383fd3b977a95c69c3dd52cfdbcaf00c7913866803050fc1963d7598f5f3a864ea0820088e2f4a5db878688	\\x55c61d3abe4b809b401bc83ec4b9a32d148476b2cebe9350d5d60a9245b51fe76fcf16905248955b763a590664c21c6741fa681ec68f495cbae4edb2411c5c91d380801f3755fd9488aa3085a656d7059c1cce684c1f029bd1d3b570f65c03a7d96bcc0a64cb5ee78950141e092f9b2ebb57c8575c138f928be91ed7e1711b05	\\xacc14f28f816def0b5f159330eef0012212b3898330140dc3d4fab3a32b97659	\\x020d7e022b0731fe59460694930b46fdca2a220ce23080b1e7519c7ef9fb3fa0c1727342c89cd31072c342d579d1109ed61cced67cc0a989d312b3b4d13d5e00	1577746824000000	1	2000000
3	\\x3898e71770bec2b23c0797caa0e53a2838289291091dca97c9761dacd699110f0016f00b243bd4c2a94bdede762531effba9f60eb06ef162b682625c909399d8	\\xe365d5ba3eaa89c4456f3b750e85ebe81978cc51aaf511b76875d60353394ba638e1fa423bcb16d9d0666598ec8e8baf053a97f679c58f8f2bf9f31c0dd702be	\\x29202d97f888c053edbf3bd9cbc415064e78410dc04c9e81337f07a3f5c3b311b3404ca43bef4de4ebe3510e31b9bd8c6ea8c6e69dd3b42bd837f4401ff0b857a8daa9d942a256ee3deaa459ff76862a429cce468cc7f1196c5e345c7f92cd68f826be558f913fbd536fc7f80a12946d53c43ae4b9da47b35f083da920346ab7	\\xacc14f28f816def0b5f159330eef0012212b3898330140dc3d4fab3a32b97659	\\x027f490903e6a291e03d8a3e054b2b63a7da8f98819cd61c21130ddf4125c19a06693a5328894096a1a5f4a9aefc6a7db42ec08bbf669f5d1402cd1b6a51da06	1577746824000000	0	11000000
4	\\x1439da6c1e7283612e78fcaa66feb8430d03efeb5b05a555f1a4f80205af2a2975b743ece25341a2d4dc26aa5f31e02a2ae5022f9dd8a4659bdfe0f68968cbb1	\\xe365d5ba3eaa89c4456f3b750e85ebe81978cc51aaf511b76875d60353394ba638e1fa423bcb16d9d0666598ec8e8baf053a97f679c58f8f2bf9f31c0dd702be	\\xb810c8abc8f15379c992c2cec03c3e481c83decf0a1516bca2f42fcad14eacb2519f8d820fe10b4985ea90387fbae2732bf9ae1730722205c667d7214ab49f3b187b877ddb2f652b8032c2c9a141e75f3de7b3572f2fe4af84fc0b33b8a3ec1988105197610d2f74885d9ace37c6ac72490d01a974490830befbad2a16720f4e	\\xacc14f28f816def0b5f159330eef0012212b3898330140dc3d4fab3a32b97659	\\x8b14c84300c8745b916b37a87fe7e4290b988a2dcc687632ffdb69619b267cc5a01c1df01590113e2c5780bb4cbf961e8700a8d6a520cb0784aced99f2ae4309	1577746824000000	0	11000000
5	\\x98dea671f39a0e9507b46dde99ebd7440ac4a04b9ce942d78ca2de6249a35fbb0bcd239c7c9b62961edd742af358c86cecc5432d78831415facdaa38e94fecf7	\\xe365d5ba3eaa89c4456f3b750e85ebe81978cc51aaf511b76875d60353394ba638e1fa423bcb16d9d0666598ec8e8baf053a97f679c58f8f2bf9f31c0dd702be	\\xa4ae4923ecb7f772489a2319c233d990bdf037d0e98e73cfb76eb6283681c6221b821248b57f33d3f985a3d4bcf3edfc213bc307fd291fde43fae809631512abc6f344f19f65f32be05af2a83cfdc8924a3c161c7fb3e5533b1d53059bfdb91b11b6cd113cc6c6c11bd7c0132078e9ff08d9939bd59868adce0cfcb925d68b0c	\\xacc14f28f816def0b5f159330eef0012212b3898330140dc3d4fab3a32b97659	\\x367098af29100f5e176521500d9039a37b4ee5e2c4be2524119fe11f89bed1a296517e5e71da8f062e2b707502eaed39cf387fb1f39903f098e490d4d7dcec07	1577746825000000	0	11000000
6	\\x92e08c149734ef01595122684ca8d0093ea0eff0aecc17ef0e00c5badadf59d5dd3c656c1581e46f23169020c68e8c144e14e5ce2a02f627a63679cca3dc005c	\\x5d410f92c0f49b70ccd357b8a35b955d539d740e811d98fe687785e9cf85f3f0abda538ced18de5be61e49ef3e56bc2d167296db254cae2ad1df6e8851374785	\\x8e68c1b3e3ca1812cfd6b47f024f6d11f51edec352bcb4ec913debd81ad23cd0e9c3cfeb6c2e3df808dac700980e65e77cbf38acaa0a317a3c234ecb8ba0c59ad970abc6ebd08d02b005dae0322742e604d1872cd9bcd98fd322d719dd897191a790c00dd981a26dbbf50a80a54f56307c7bebef2a50de5e6612fb4f8d378c09	\\xacc14f28f816def0b5f159330eef0012212b3898330140dc3d4fab3a32b97659	\\x74b3244756ab455aee5651ca78d219010309eb6e7e06c286b1782f64c537bee86047a95719863742a4fe608268f4e46fa299d00cdab69f9e5fb6f0b609676c0f	1577746825000000	0	2000000
7	\\x4016f4d784c14d58239b7ccf38174c690a45d2f282968dea267458efa9cb334ab442cc6b723603957f517538bd304235102cbc192df20b0e9301418fdc4843c2	\\xe365d5ba3eaa89c4456f3b750e85ebe81978cc51aaf511b76875d60353394ba638e1fa423bcb16d9d0666598ec8e8baf053a97f679c58f8f2bf9f31c0dd702be	\\x19fa83c34291adcdf1db11752c11a645692e43a47602ae4f6581a902f2c20a25c0b6e6a86a17c2025da69e8922be6466394d3e52b643c10ce0d7f3d7630b0d42ddf2cb6bcb2f5e5c314d575b6c5ce19648cbd9619141cbc77d0df115937e734299da7b46ee3f5d064402341e380d0c64aa42f77d49961b5d3e6a6c09c9cfa9e1	\\xacc14f28f816def0b5f159330eef0012212b3898330140dc3d4fab3a32b97659	\\xfefea660cfd60125dcb27400b84abe788b878111009573f458e9379dc3ae3a966a2be7e4693734ac6d4b29db322494a9ee4521a8769b1a0bcae710736f5b1a08	1577746825000000	0	11000000
8	\\xe3c65752850dd22ce8b81a2c51da331133cda034a2131818057a3805927485888ea53471ee09859e75407e4ba4632f6fbf7620f550535423aedd70588d3fc5a2	\\xe365d5ba3eaa89c4456f3b750e85ebe81978cc51aaf511b76875d60353394ba638e1fa423bcb16d9d0666598ec8e8baf053a97f679c58f8f2bf9f31c0dd702be	\\x7e4532eb2e1b3542221b6be4f1726af0ca1c6091f42cff061165ea7c4ae357da13461ad5bee1d1bf873f7a8433c822ca943da49aa432f332fe013d47c4710a6e0502e1ebca1eb2ef76e6c3e522712bbfa184ad3b97691bc0c939f04f334f1a8cca89c9ee3aa334d6e205049c3ed3be9579f274770f89cc899cad63a1ccac390d	\\xacc14f28f816def0b5f159330eef0012212b3898330140dc3d4fab3a32b97659	\\x70c0399a1b582b2baf5b5155a05e91dfc43ca6b0d2756440097ff229267a7c7120f246c5533ed3b62bbf94efa5239dd615edb07e6fe2283bd8f6d570a549e703	1577746825000000	0	11000000
9	\\x18b5e66540993539017bf9a88bce813e89282bdc2d12a4ea9cd542b3644980e4f6959617b6299bdc21ec22ef9d30fe38fc3a9ad994fd82cfaee68ff5c81f7e5f	\\x5d410f92c0f49b70ccd357b8a35b955d539d740e811d98fe687785e9cf85f3f0abda538ced18de5be61e49ef3e56bc2d167296db254cae2ad1df6e8851374785	\\x1ed1fa16103f8aea62944a851e817033c327ce35e1e1699db870ba034cd8083bc5941bfb0dd3423a8dc56e281bf943a1569736cb97eb3629f4d952dc5b9ccc50e2bb4332e49bfd23973d4e93e54ab0bd7cf0cbfd97e144c751101cff1420cd29b09b4a30d3eb9922435eff0ab36c0ff55a0b8346d5440e2b28dff7c95629f9ea	\\xacc14f28f816def0b5f159330eef0012212b3898330140dc3d4fab3a32b97659	\\x4b06de8f6669087d65c17877301debe826bfdd947cfc46ffa4fb77e96f02bc9e495fe0835810e7a369f7f365dadfb69c66bc844d5c61333fff6d74eff45ac301	1577746825000000	0	2000000
10	\\x482c77f89b849215f439936c56f2c40c173d56907944f9f41cd8468fbdf35715434e326103dbffe04d00a1af3ced99c2b015c12f638a0581165b046409914626	\\xe365d5ba3eaa89c4456f3b750e85ebe81978cc51aaf511b76875d60353394ba638e1fa423bcb16d9d0666598ec8e8baf053a97f679c58f8f2bf9f31c0dd702be	\\x9c88bfd07788b297de1e2623b5bd2ddb385b2a5148185a719d37b8258186f5113c57640a1585c62f5186939c93cf724b05d520e90f11dcd4a8fb0a788ceb7c777d92397d5f14692341fe091e3dd13b7ff37f961be9b57359966e50f48a08b95d69fcb7a0264902e5ddc9b2d647ca0b244f29b885af374ba34668f7b1589b6ea0	\\xacc14f28f816def0b5f159330eef0012212b3898330140dc3d4fab3a32b97659	\\xc451b5830e205bf1107df20f1c0047cff6d4569d6045e8c7cabc0b9375214a1e1d1cc5a78aaa26dd2c64f1a616e6f6cc01e1dddae01d6b0a0147f9e80cf49a0d	1577746825000000	0	11000000
11	\\x42977419534f2aa8030ba39bbb9e32915b6e43a4251dc532717d125e301fc484c7c914a538a4922e7b55f5c0b16d1af27a263cd015ad9a68b2441323f480bf59	\\xe365d5ba3eaa89c4456f3b750e85ebe81978cc51aaf511b76875d60353394ba638e1fa423bcb16d9d0666598ec8e8baf053a97f679c58f8f2bf9f31c0dd702be	\\x57426f3af06b242dec533d02ba15266b643492e681ed961a41177f2ccf59aa0d440fbbe586adef13d62faadf1ae9184699039e1d31b545bcda8887c1ad88f580ca712919ffb41491b52c290720e5233d578143da5a36deb67890ce5df35d9464c6988872f58ac0d3c377912e57715077256e81fdec6aceff121b22fc49544dbd	\\xacc14f28f816def0b5f159330eef0012212b3898330140dc3d4fab3a32b97659	\\xbb573f00a78cc4f338662ff287eabc42926af12be4fc9469b9985683b267b26fcc8caef24f30fce510ccff763e335a13f69a3e35034662174901b0b844d8200f	1577746825000000	0	11000000
12	\\x70eadb183c6898fc73af8dbccbc9c0e388905e9d76f108745d54efaa68d29636343563fff237638b3c1dc0fc6849134b89ded6881f1cd164f4474614f864b7bb	\\xe365d5ba3eaa89c4456f3b750e85ebe81978cc51aaf511b76875d60353394ba638e1fa423bcb16d9d0666598ec8e8baf053a97f679c58f8f2bf9f31c0dd702be	\\x25b8d9b9e5281abd3ff9c17a68ddf2d82929c075ebd057f8e7cfd727707491c51ab73c159452e1153530a69424a18df819a43abfa0d3f1bde799680fa88239efca8e3d972a8ffd5979d1c6b1f02c3e716c32c7fc6e90822b7cc52644c947cadddf8cd91c739240b06732c1ec295b73a86b8a3870b0d7a3d8d14ec4f5b2da57dc	\\xacc14f28f816def0b5f159330eef0012212b3898330140dc3d4fab3a32b97659	\\xf685c60b9a8b5677e94e90f90f3e6f8e708f42c9bc8252334c30d187809fc91f26afe5f251e83a354ae9f55c7b813d88d5af4f41ad28611faca8e60e8f197f05	1577746825000000	0	11000000
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

SELECT pg_catalog.setval('public.app_bankaccount_account_no_seq', 11, true);


--
-- Name: app_banktransaction_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.app_banktransaction_id_seq', 2, true);


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

SELECT pg_catalog.setval('public.auth_user_id_seq', 11, true);


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

SELECT pg_catalog.setval('public.deposit_confirmations_serial_id_seq', 9, true);


--
-- Name: deposits_deposit_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.deposits_deposit_serial_id_seq', 9, true);


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

SELECT pg_catalog.setval('public.merchant_contract_terms_row_id_seq', 1, true);


--
-- Name: merchant_refunds_rtransaction_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_refunds_rtransaction_id_seq', 1, false);


--
-- Name: payback_payback_uuid_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.payback_payback_uuid_seq', 1, false);


--
-- Name: payback_refresh_payback_refresh_uuid_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.payback_refresh_payback_refresh_uuid_seq', 1, false);


--
-- Name: prewire_prewire_uuid_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.prewire_prewire_uuid_seq', 1, false);


--
-- Name: refresh_commitments_melt_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.refresh_commitments_melt_serial_id_seq', 1, true);


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

SELECT pg_catalog.setval('public.reserves_out_reserve_out_serial_id_seq', 12, true);


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
-- Name: payback payback_payback_uuid_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payback
    ADD CONSTRAINT payback_payback_uuid_key UNIQUE (payback_uuid);


--
-- Name: payback_refresh payback_refresh_payback_refresh_uuid_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payback_refresh
    ADD CONSTRAINT payback_refresh_payback_refresh_uuid_key UNIQUE (payback_refresh_uuid);


--
-- Name: prewire prewire_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prewire
    ADD CONSTRAINT prewire_pkey PRIMARY KEY (prewire_uuid);


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
-- Name: payback_by_coin_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX payback_by_coin_index ON public.payback USING btree (coin_pub);


--
-- Name: payback_by_h_blind_ev; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX payback_by_h_blind_ev ON public.payback USING btree (h_blind_ev);


--
-- Name: payback_for_by_reserve; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX payback_for_by_reserve ON public.payback USING btree (coin_pub, h_blind_ev);


--
-- Name: payback_refresh_by_coin_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX payback_refresh_by_coin_index ON public.payback_refresh USING btree (coin_pub);


--
-- Name: payback_refresh_by_h_blind_ev; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX payback_refresh_by_h_blind_ev ON public.payback_refresh USING btree (h_blind_ev);


--
-- Name: payback_refresh_for_by_reserve; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX payback_refresh_for_by_reserve ON public.payback_refresh USING btree (coin_pub, h_blind_ev);


--
-- Name: prepare_iteration_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX prepare_iteration_index ON public.prewire USING btree (finished);


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
-- Name: payback payback_coin_pub_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payback
    ADD CONSTRAINT payback_coin_pub_fkey FOREIGN KEY (coin_pub) REFERENCES public.known_coins(coin_pub);


--
-- Name: payback payback_h_blind_ev_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payback
    ADD CONSTRAINT payback_h_blind_ev_fkey FOREIGN KEY (h_blind_ev) REFERENCES public.reserves_out(h_blind_ev) ON DELETE CASCADE;


--
-- Name: payback_refresh payback_refresh_coin_pub_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payback_refresh
    ADD CONSTRAINT payback_refresh_coin_pub_fkey FOREIGN KEY (coin_pub) REFERENCES public.known_coins(coin_pub);


--
-- Name: payback_refresh payback_refresh_h_blind_ev_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payback_refresh
    ADD CONSTRAINT payback_refresh_h_blind_ev_fkey FOREIGN KEY (h_blind_ev) REFERENCES public.refresh_revealed_coins(h_coin_ev) ON DELETE CASCADE;


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

