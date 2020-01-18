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
auditor-0001	2019-12-31 00:00:58.040625+01	grothoff	{}	{}
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
1	TESTKUDOS:100	Joining bonus	2019-12-31 00:01:05.044669+01	f	11	1
2	TESTKUDOS:10	JVBJC9P64JF7XR6EEFKYHXG7N439ZVAE44D5T62W4GGTYRRDFJAG	2019-12-31 00:01:05.138959+01	f	2	11
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
\\x247e75ac7100bd05188c214913c0ff02cf2e362f02d13ea07db3ba2c697c95947a5b30492cc76c4d0ada5d1e5d93892f37aed186526798c9941f55b9a07fefb9	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1577746850000000	1578351650000000	1640818850000000	1672354850000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe6821e51ed69054659bc1054ffb675fe02f49daa7fa6d8ba69f72b869111704aa4630a3ad3ec2bed7597c94e8e023be0132c046c0faf18f806e758c2be417dda	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1578351350000000	1578956150000000	1641423350000000	1672959350000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x67f37c56d05a700c014e6ef7e1466be0fd86f36b90dddb2b0b2bd8e65d48c0b3b915bcc7f850b511fa24c03636ed97a35e759b403a68aaa86a514b2560c63353	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1578955850000000	1579560650000000	1642027850000000	1673563850000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x59b95ccb64707272e2fb6ed2618a0e28979945d6940956c8a7df42f6d81fe8505cb2f3dfb4952bd3738ef1c3435d2d88cb3788af496286e7423062fcc8dcc45c	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1579560350000000	1580165150000000	1642632350000000	1674168350000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x90bc2d8548a560e5eda1aef3852db4b789bdcc36c63c119ade71fdc5df4d702d5ea95da5d225c6cc87cab0b13a40aeb9d16736c5639da42500b1ba7099a20da7	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1580164850000000	1580769650000000	1643236850000000	1674772850000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4d4862e79fecca56da76b93710a9c688137802784a508ed4bd66fea0e0ec57369e2581661bfcf22d5b5ccdc35e1c75c30929ac602871395298bb5aee76a06180	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1580769350000000	1581374150000000	1643841350000000	1675377350000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xfc2322fe0c6c9be524ce11484c11d0ef835500b4ddd8eea4f5863ffed2dbb6322b723a83517ae8a4a9e1c13c15f342761a5177f31f29cbfefcdf80c3a0226d0e	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1581373850000000	1581978650000000	1644445850000000	1675981850000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9a9abd965ddb7a3bce0ba660de721a1d6d3d57d9f1336908adb82706de15421d034028ddaf2f8a99aeedc4ac9bd71d64fb75e13ddc59083e18496f4c038fe559	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1581978350000000	1582583150000000	1645050350000000	1676586350000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc790c861ca8767959566485592d852ac790b64b1152de7d99af73888a365b7e45dac51c6bf5465d81ba433d6c1c56a10ac27e01d59a82a616268993f6437249e	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1582582850000000	1583187650000000	1645654850000000	1677190850000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x80249ef046a2e97588aa657805b28510fe2596003dca31b65c328b2399efda27ccc8a168aefa0cdb4f5b5eb04fd4cb4de596ff9be9bad173205d6d19b0c2108f	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1583187350000000	1583792150000000	1646259350000000	1677795350000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf8d1b4be282fde615fb6f503d70d3cd7b5eac07de92fc95f990094fee00f4a71cf9c6c3afec6928cb5a51622af4a25a6a9222119f96a84599b18329e15f7c696	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1583791850000000	1584396650000000	1646863850000000	1678399850000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0fe2d9be78bab3ed02136980d85fa4c62f6fbc369216e93f74ae047dedc60e0329c276194dda1bd787e832558ea38a29b5eee17e2a0004d0112eb36c3536635f	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1584396350000000	1585001150000000	1647468350000000	1679004350000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7b2752a374219586093af100723e9b2cab7a818beb9d29e0880108b2dda96fe1d4b119a741e18a97b3d226423cbfa3606ac00e400c39b3ecb154351e0d0ae2df	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1585000850000000	1585605650000000	1648072850000000	1679608850000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1756b9d3d54dae1aae1cf8b3141c4d3e8fe4faa92732d860bf601201fd756ef7c6feca058d13889790535642a0aabe68728d4d885c9d8ff77e6eb07522273278	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1585605350000000	1586210150000000	1648677350000000	1680213350000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x533272962a8290afd1b584f0fec349d2c7672903575023d958ff6c54f58779416822b32cfc1ebfcc322a99ea0b53eadbd56fb1806392c89b79b2d43cd7bd19b0	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1586209850000000	1586814650000000	1649281850000000	1680817850000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x463d1e66ca8bf6cf42948974f98332b0ea803e34e3d4fa90688dbfbeddd0a0912eb075b59e417740e82a5374fca92c88c5fb76d6bc89945e55fadb0a0e20debb	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1586814350000000	1587419150000000	1649886350000000	1681422350000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe40d54cca79e805c1158549dadb7a40a44bc016d251503adba558658fd7fc97974f02b7e58de86ef7ed09e13a82bcf7f06cc8b343a4a573b37e46fd6ddc2ead5	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1587418850000000	1588023650000000	1650490850000000	1682026850000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xddd29cd27c4a52af965a36279a54dfeecf5d9f6c3f24dbfbf895a048a17a1ebbe070f7ef676b8797959fd71b85e8c077c434e1668083985b646ea719331965cc	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1588023350000000	1588628150000000	1651095350000000	1682631350000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x795d7c5a1cb7e8ff4a1c699cb51279731044521029b5a50636911a5553fdaa3bd1afc13fe6abbfe286313f0a56a0d863308f78fd4bf47e1598d5b8b8c8bcc8ea	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1588627850000000	1589232650000000	1651699850000000	1683235850000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc541c6004d392b7f6a39d44dfaa981fc22abb5946d8cc4e4476af51b454d05120f05e3ecac456994a50e298bd35e47205adfc15e6a142aeb1647f9b6e232b89d	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1589232350000000	1589837150000000	1652304350000000	1683840350000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa3b03c355234382b37381b2785749096433ae02b4ff51aa6bc200fe88c7e2ca4cf1f6244815032e60a8f861a42f074b2bce9ac0d55427fdd53e0250b38c79282	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1589836850000000	1590441650000000	1652908850000000	1684444850000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x803c10c9184b7247185f2baaac44e4a6a7d0e06c2826aa64e9135b679510bf5706e316d087d036fdf016cf49fec20358230b18d84f6b974962e481ee3db1391f	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1590441350000000	1591046150000000	1653513350000000	1685049350000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x868315dab51f382af1678f2975eecd989291e8dcef8a29b03657fbf2b758a1b98d9923980c4252a1830d417849c4c2e71523ba851951162622bcea0021c4c66e	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1591045850000000	1591650650000000	1654117850000000	1685653850000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf5a0089548d0578953198aa1558874683ff1d15ad53734016fc0075cd2f364ba845dc9c2e75db135d8536ac1c11acdaea3f6280c583669b8c145bf40c4c56743	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1591650350000000	1592255150000000	1654722350000000	1686258350000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xeb46a1d70e36047125bc3f14c078efba6d31ee62d0a9114d670bfc792309393ee6a88def3f7733f3733039bdf9bbef21386fdcfd0b6cbe3664321f39179e004c	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1592254850000000	1592859650000000	1655326850000000	1686862850000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5d3120e32dc0debcd4207d70031d48d6a65acf56ccd7dd2ec0c650941bc8f090cb26d43ab542ce4ca2b5b5b474886cc0ae332c6ebf266172228c6b5eb1eac7f4	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1592859350000000	1593464150000000	1655931350000000	1687467350000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf7b27f7caa65a52a7024237d5565120faf9b00aa9e4a98add3ac061791bdea8bee4083ce68e9dae26e99f2fc404e5e7656523a669a08bf8e10967a2359dee225	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1593463850000000	1594068650000000	1656535850000000	1688071850000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf52a2b406529d5e5d2fca93f5092d0fb3e34f211837e252b27833b85706882bf9f56b5031311a9088f94573767d38c1baf406bbe2d2a202bb17b13305d5fe386	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1594068350000000	1594673150000000	1657140350000000	1688676350000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe4e084e18f18865da0880b93f3ef20e14a4545345676fc4f350d00c03e5b044d0297f82514ced9c1477db5cb8941922eeeb6460418337c21bf1da5981413fc81	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1594672850000000	1595277650000000	1657744850000000	1689280850000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5ea8bea15de34d0560f2cdd6ae3deea03a98c55ac94e7f1dcb9893135e2dfeaabf70f3dd957ca21e92b9bf2b779d72b526ab8d60a8b8d2ca0266234e1c2ee86e	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1595277350000000	1595882150000000	1658349350000000	1689885350000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa49e27f23fcdd29f0ccbeec9e535790171e3031fbdd6b6955e28435f921a6b1864836e2006d3af5b7aa6e4e293f6de6b5aff75df026a55a418d73fcf1857cdff	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1595881850000000	1596486650000000	1658953850000000	1690489850000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe3901a8d4ec95b2857659a140e68ee2aec53a69dbc4840c36f7cfe1912601fbd57e78c2b25fe9120867920b7172030fd5757c2642c03bbadc1474af9059e607f	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1596486350000000	1597091150000000	1659558350000000	1691094350000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1a8036934cf27cda24f80bee49910cb5015a198257ea62842bc0774dca08a94814081a64a873a9c27a12d46aa3d1e801c5a94b55061dfd3cfada9d35b963c51f	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1597090850000000	1597695650000000	1660162850000000	1691698850000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x389763909f6bea58332dc5adb5b4963b696f31e496b7e60759c8b18a0214cf9ecd61aeaecebf30f713847533ab37865f46b0fd23c14587403c8dec2bad071c4a	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1577746850000000	1578351650000000	1640818850000000	1672354850000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xe85f1557b625713cac97f3423b20b077f82203a08645def977189cae0aba336546fb93137c76dd76605eb858c86c6098c31d38365a457853f7e2dfcf62f8090c	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1578351350000000	1578956150000000	1641423350000000	1672959350000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x02608a5addf121abb77c6175da4ab6b64333f66826aa2056902cbd2d5c0e98dbf5d138a306a9cbca6980b08e6002e2ea471d77f86da30ebbaf0ac5fb15d4fa8d	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1578955850000000	1579560650000000	1642027850000000	1673563850000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x0320d4e9a413672188a047564e6eb030366a96b27d0bdfa33de78bd654e919b4f963d9ca719c177f27c2215f2c2095d4e9302453b565fd4d1485c99b9a75f8fe	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1579560350000000	1580165150000000	1642632350000000	1674168350000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x54e24fe87ee27a97677b0e3f66d98fc00e81df1776a0823e50bf46ebd40c90d5c855ceeffe79a5bdbf045b7afee6929ff9689f190560a28ab2fea97510f8d8bc	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1580164850000000	1580769650000000	1643236850000000	1674772850000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xba4a5bf3ad89dcae628bc80967aa655bafdd634bafd732e14219716c9fa188883b89a2b5951215479fbd03b5b5493381a8f593dafbd79f9299365937fc707b02	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1580769350000000	1581374150000000	1643841350000000	1675377350000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xaa3e25c0a9dd30d93a7eb2f28bf8443b4be271adac5b6434da2fdfe6da449353d692054a41b293b75e61ad1725e56dd5b7630d3f8c78e3cdc840c90464d0d76c	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1581373850000000	1581978650000000	1644445850000000	1675981850000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x9f50729b619ef8bc79d12dd52e9eaf96bc7e47ae9353e2604c92f05a190c4fff77e0b31e46520e83d87ee93b225980e25cbf92c4a36a264660daf5cebf69e3b5	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1581978350000000	1582583150000000	1645050350000000	1676586350000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xc3e31b2601fe7035aa0b89ccc23b68095c37c0d11c6bd87c3d85f1a753e01492f22e7ac241c1cbe9e56ada8ff74f1a90f8c4234ead3a555469d21f0ad0e52712	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1582582850000000	1583187650000000	1645654850000000	1677190850000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xe12bcdf31cbcacc698fdbf0ac8420cd6a54d2f3a0fa68eb7792e89c2f03bf6ce75fb6f745bbf733d94ebad46aabba9d5ba9524787927ff727a34ec0a99a15fb3	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1583187350000000	1583792150000000	1646259350000000	1677795350000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x6417e08ae159f5a875e49394ed90202a7d196a392753b342dd1fb8a2263967816b4a3fe6782cac0a101cc130d3e7cf8bd5f85c159ede987fc98d7cf16412bc67	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1583791850000000	1584396650000000	1646863850000000	1678399850000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x9150c884f11b0c8408799f5710440e44d6560e2aec3f62eb8f74b2821879f13eb010b331e70771ff9f61e31daef3b491d526d3e341e193ae17ba3615b8f5a9a5	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1584396350000000	1585001150000000	1647468350000000	1679004350000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xabbafb658ee06c03fb81b4232add2b0c8c0f282e0362f87985cd288cb161bd48d0a4fb14bb5964bca54d0bb5bf0a5447a889f2cf6fd14f3db1b1e261eb0d73a0	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1585000850000000	1585605650000000	1648072850000000	1679608850000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x0d79b428d342d48bdbfb6e68e4f61337397e3df5c3cbef3d1954e9f7d2f732eae62faa153a699bb7f7ccc0c49055c13aec3e32039a0940f059817240b626152b	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1585605350000000	1586210150000000	1648677350000000	1680213350000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x565ff54dcaf13f0ee52ecc88153c6f0e68d32e0136ccabbe3a74439454af11b86bd03bdd7ad2dd11de755fd1fa8d519d91db63116204691053cec55399b8aea0	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1586209850000000	1586814650000000	1649281850000000	1680817850000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x535d77b1969cad590645e213580c483c253b414bf53981f48a7120d2be690da91fa7c530066c68f22b3ecf2051068473bc56eff3e07706c8853f899c8fd2456b	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1586814350000000	1587419150000000	1649886350000000	1681422350000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x2e965ea6c57c06a490e4c73bcbbca808338075d629802f79cb42e9e1b7309e841b79efbd378a8ac583f057a7145f0fd03cf8891ebc63d356a97b9d483430c71d	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1587418850000000	1588023650000000	1650490850000000	1682026850000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x7f7219a1b43bed1a6d3028bdee5a9808782382c209a916a36200c78bc72080045bbac21287e337764c0c866680d310abd1d92d195ffef3979d26319069d69820	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1588023350000000	1588628150000000	1651095350000000	1682631350000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xbc6b006e750268af156298107e11c92eb39a5e556175a5a3d6b52ea6e0bbb1dc57972200b49c8205dfc537d7e7cf9700f665cbdb07d3815e178c0286327f9e4d	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1588627850000000	1589232650000000	1651699850000000	1683235850000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x0b6c48e4670b26aaa3587ec2dd63597eb7a2b574464ad08f74d3d551964f04b580132914c2538548b7976a8c89ee615b68b700bcc1924abd06176ace3ce43c93	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1589232350000000	1589837150000000	1652304350000000	1683840350000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x68427894742e15b7f51810e7c2278a9b7614b15e1873a1b8c06eb78afc6fa9b157c7aa2312dcb4b6eca136445eefe5e03e1a87e7c469ae50b257f7f066c8dd97	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1589836850000000	1590441650000000	1652908850000000	1684444850000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xaf1c32f7ae083a57e10d50ad80498131634b87da87090f1f2860b010844c4f078de1b7167054bd2e1e8e3293f53a1af98ec327f5113c11805a6ef3ae88d7f5be	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1590441350000000	1591046150000000	1653513350000000	1685049350000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x05b8efa44e0141c2bf7a4de1866d7cddfbf2a22541d16f5ef569081bb8bee6d9fc4ee81d5f836b1d54cfa088eb2a6b13d44cd1f0738a0b3000ff52f1cb612e74	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1591045850000000	1591650650000000	1654117850000000	1685653850000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x40f18644dcdddab724113a41390270158f0b336425e9d78c571545067adc89f6663d54f7835bd1c44d6aa89bf56f4d79b937f015927d64843a8b923a4d95390a	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1591650350000000	1592255150000000	1654722350000000	1686258350000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xd7bb46bd123fc78234e8cb14ec5398205d57ee522fb68fc210f4a289e1cf80d5befe64e7ae5d440f01f91c90a580c947036838112016bd16a510588f29735a65	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1592254850000000	1592859650000000	1655326850000000	1686862850000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x1aa47c9c53ac0e109063825540785abc7bdcd571eec7bf37206df9f6a94d00228a0c8ec7d0e1aaff9948e1e92cd6b7977faec55fabcc920ef14948ad81332d34	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1592859350000000	1593464150000000	1655931350000000	1687467350000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x0799776d807257d27d10775d67616e63346003ed3b3076689fb1055440019a2668b47f906b1eca539c8e6818cbe7f50de0d9f14a9058fef17c639fd4c06c4916	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1593463850000000	1594068650000000	1656535850000000	1688071850000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xc0bec0254000bce1825b2e9b452721118a683f57783e2c4a79a646a4d56940ad9c9d5d0c396bb9bd96e5c829ac845ce5a767a0c3a54ae6ad9b2bef33670cb13c	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1594068350000000	1594673150000000	1657140350000000	1688676350000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x9288f601635c770c014646dabca1fac635048a9ef2bd5175037008f7209113434b6cb2e779c55210b6ace9822f57954f1b093909cfd7e1666076a3b24704c651	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1594672850000000	1595277650000000	1657744850000000	1689280850000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xe268aed8efeade1cd091e49247c58e99ceed191ff65505c12541cadceeec7ab7d85a820c58518806525b81c0450fab465d7ef7bb05dc981f41f9581267897a21	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1595277350000000	1595882150000000	1658349350000000	1689885350000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xb0a7e6e4aa393271ffcec2b1c4cf75e2dff92d0d3f03ff26da45c76ed234db26ca2b6c6bacdd578c144ea4223cf9f9e8268dcae1736aa90c0ba46bd65752741d	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1595881850000000	1596486650000000	1658953850000000	1690489850000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x2d19ebfd71ec4c5669d414b7823ceb863f8258c7205251b5e600c2a6552ad2a1ba05e9e287932a084d4ee4fe60315c46c38eafe514a77d1b833c3f04c96acc6f	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1596486350000000	1597091150000000	1659558350000000	1691094350000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x7d6701218825d52c163c6b4c3b2fdc7738bdc1dce279fd192110f2020a915187f0425996cee5048d8f30b2a31321fb07882a3c9516a3fecae2151820e48002d3	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1597090850000000	1597695650000000	1660162850000000	1691698850000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xb0ae30bfd2bda436dfc81a6e4dae41b9a09fd5d5f3f9dc1085b2b198523c7b9bf7c6ad6b8a919f274c14d2f71026bca7a83bcde301a30cca4459faed7aa59c69	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1577746850000000	1578351650000000	1640818850000000	1672354850000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xcab27154f59ccd368615e00018e2f86484dc21495e09f8d842891ef2c381b7793bfa67683c1a8edaf270f0b7fbd9943ea8b37ff30af34422075117fdd1b62820	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1578351350000000	1578956150000000	1641423350000000	1672959350000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xae07165c301449fd9c2e7d7cc73abcbb263dcc71f146a3b81466d93e27ffee65836e8cf5cc26e5e8dd9e26fc30034b20b201ddef7ef6698eb67e30bcd91e3d61	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1578955850000000	1579560650000000	1642027850000000	1673563850000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8299edaf45195f717ef2ba0062ec8034bd49244e0747008e42c29d1a73da5b469bdd058b512d84e5ea9ac4f50f690d7cc90f07f2529da1b2758f8ec97f7012c3	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1579560350000000	1580165150000000	1642632350000000	1674168350000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8c3afa33d33226b3088c1d03719432d4a6b0b29f10988074bdecb13e04e27cfbff3699923137c9c576cb379bd4b936a27e1bc6b7cbb685eab5a7742cb0dd044c	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1580164850000000	1580769650000000	1643236850000000	1674772850000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc94365f9ae696fd21b5d4951ee4c30207d4bc0e082e01a0315de8303c48a0a6b69b26d8a91df0f6c3060dbf841c7d056d04b1f162214c70c62b68b0bc318a2e4	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1580769350000000	1581374150000000	1643841350000000	1675377350000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0b287525ec3ef3aa8513902371d59540f20a2920a4ceb94b407c3e063411cf8420066ec2b9e0544d5b04134b9f0e7d3fd2b9b895f351af69fd26d1868b4f9ba8	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1581373850000000	1581978650000000	1644445850000000	1675981850000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x536a73ea666ee8e61f105b7696082841304afb2f53be4104cad603fae5e3f84c30dea0a77fa01e8216aad54f7e03101f6b4fca9a952d8d1cb2632abcdb8422f7	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1581978350000000	1582583150000000	1645050350000000	1676586350000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb0301a60458754a0cc318ac2368525b8cacc0a1c19d24b66a60f89b125f4d8c2992a3fbd0b836a81ff3ad9f7a84e80f612e8447913cf048574687d5d9782090e	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1582582850000000	1583187650000000	1645654850000000	1677190850000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc663fda362f9cb6bcd70ee47c0d74c999635ab4163ea44530f5b4aac672686b0cd27ae0d08c76014c49af5fffc172761361db9cd0378d4cfe642552d5deeb7fe	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1583187350000000	1583792150000000	1646259350000000	1677795350000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x598495c4e021ed3750a7f77a44ad7584740c87bf62afa8d8c618d1fd41ba30e7c360390a3ade3fdb9a341ffce4aa926c963735bfdca1a658ee3e23e75d3665df	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1583791850000000	1584396650000000	1646863850000000	1678399850000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xaf55cec5d3881feac6025b66456a7e650b17ebd625fbce198f3efd02700f23a1023997233f0b8753a24b786624f90e81e6f6585101d15ba5216b5c9e45e8e711	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1584396350000000	1585001150000000	1647468350000000	1679004350000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x629120864579f2dd86c6b3221de0ef561f5cd4e8dce4fc7694c7ba9422805595b5fa5044478c2dd46dc661daec9702df9be7222871843eb71819e9105e9c3559	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1585000850000000	1585605650000000	1648072850000000	1679608850000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x50df73b5eeef7c5a17d87751713ff0491477e7c70996bf54d500d2409f07352448c9638d51759b745206b34f31a97c986156d6990b3e3e5399a1d4e78a36f93a	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1585605350000000	1586210150000000	1648677350000000	1680213350000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6d82bd5845bf7b608bd82343d8b188287230c444f0a0201101cc92a66f69189f458f33789789cb300f3bc399d269bd72fb9bfbc2cf05755b16cd8c5621580987	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1586209850000000	1586814650000000	1649281850000000	1680817850000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7465e26f5de45809a47a4a44c95fa9ceb03baf8a37caf6ce7325a9531220fa453a2b8a55f86b6fdb02b4d25bab320a71cf0b29c4486bf31443f04c7fc8ea316f	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1586814350000000	1587419150000000	1649886350000000	1681422350000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6d61084572534854f1fc453cb14cc735cbee9c10bf7ae77cb9536257362252c249db49a43b0d7fbab37f9d756b81c72d351467ef1164cacfadc82ee473010731	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1587418850000000	1588023650000000	1650490850000000	1682026850000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xbc31ee51d4694694235c572cefc34b60e815280ddb31113fb4d88e49d69b4c92800a33edc75907a2c26cfc3beff63a1a79e45b5e0f500457f08fb3e6247063cd	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1588023350000000	1588628150000000	1651095350000000	1682631350000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xdb894092daf9064cc85a9e68d5993a1d6203ce60ef9adbe1898104a7802460a5a525de1568b63bb0f12f229faf660cc83e483b113cfb194110eded1519bd6906	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1588627850000000	1589232650000000	1651699850000000	1683235850000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf867c1966b9a7df0e289434d3d88b1151ac9c495bc044b458013ccfc77d7285b6fd5181523f7144b9e7f4b77bcc8376e65c746a7f9a8465dfee5fa7567908692	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1589232350000000	1589837150000000	1652304350000000	1683840350000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x37681680633f187e930946d1438daa5558fc16f7327d6d7f44f7336d657bb29c27e80aea8d77e37d66d2787d27061d79c45777d05ce79b99afa5572528be3e83	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1589836850000000	1590441650000000	1652908850000000	1684444850000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x061d1100cc2539fef9fb0407b67014fb6b8be81e37a5415689e2a0d13c33d931f1d249adbb99fb3fd8e778c7d7010544f73c9fb0547b59a31e2ab204584a9fe7	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1590441350000000	1591046150000000	1653513350000000	1685049350000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6c590b9967aa4d45138a2986074102c88ba7bd90d5cc4d3b7dbe98572468c8274352e468151cce2ab1dba36799a1f5641b8d99a713d3d5736a6259fe3b09fd34	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1591045850000000	1591650650000000	1654117850000000	1685653850000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe8344c40806c3a2e308cf84e79ecaddde66a1476f98822d57667ddeb14febc03efe9a19744f86bd2a50bbd4af92f3a38492dc3a442820996c93353133284a4d3	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1591650350000000	1592255150000000	1654722350000000	1686258350000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa88ead7abb72687dca649257e825eb808be3f9d394bbd3b2a4bbb331f67bc3217b893322d5eeeadccafbd4b11e5f6540e13b2a0fd582039f4b42be4ad20cedae	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1592254850000000	1592859650000000	1655326850000000	1686862850000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x876a9583e245767dc6f6060377acd79283875a3961e2432cb700ca8fd2b3b3b3d9fedc4341819e4263efae6b16f345607bab829b5caa9f052319229e7d36c87a	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1592859350000000	1593464150000000	1655931350000000	1687467350000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe44acfd7c414786f57da4f96e62caae7f3a84d823c343454db882021a44c34b0247523a517117ccdaf5fa4337e2073c5aad7120055b7b14971e96726d461c918	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1593463850000000	1594068650000000	1656535850000000	1688071850000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd6558d42693690bbf0ed801e34d7414c53450b7bdc3ba7a96cde80727336e04e2b9bcae1878a56d6823da208f0c18e3bc0f03bb50807339dd2683fa2760bb0df	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1594068350000000	1594673150000000	1657140350000000	1688676350000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6480ece7d500bde4ee75772976cb5f174c1dc2d72b3fa4115f07653d44f2f220b12afc38097eb663ccc1f1ccf075d6b71defbef4776baface196187f3f5c7744	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1594672850000000	1595277650000000	1657744850000000	1689280850000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7e03468c6746b97d423265707250754c4f92f5a4873a280efe088909d51d886987d013bf7385c9ad97a84ff8fdada62d5ac9867b5d2d6bbe68dfb64cd31d798d	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1595277350000000	1595882150000000	1658349350000000	1689885350000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3764878e595f9cea7a7f49688a9a3f688b9462076b9772459005c0ad554841ea2815ef227642c55ae7aa19e881183fbeb89eb48d45f4b697b55eb40232a4ccf5	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1595881850000000	1596486650000000	1658953850000000	1690489850000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xab09c4739984676539b2f42f0e608b526d4e225e993dc257c610939b9190b04d3bb01667670ad7929e1bb6a8235ec4883ca926740083e42e235eaa6143f64467	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1596486350000000	1597091150000000	1659558350000000	1691094350000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xddbd5562977d0458294aa2e148b6031c82a61dd78927acab6c5b7b288646f53ab2bb440321ef3d829903af02b5a6ce31d24b8ff1e012c4c133b25e55761c13ff	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1597090850000000	1597695650000000	1660162850000000	1691698850000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0d953d54ba6115a8c939faea176ccb5e81eb1430e03e73b334917e2435e4c9a66e136aad06545dd09eb80fd2df9c88907339eeb06b1c095cbd69aa790731abb3	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1577746850000000	1578351650000000	1640818850000000	1672354850000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xba1054060e87ea01560f2ae9a5a09be93d004b2491952aa45317af702e984da363907db259c28f5151f21bf5c3a05b359c30b2801b0d8efa4a55a1528603afd4	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1578351350000000	1578956150000000	1641423350000000	1672959350000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x27a339f6a4eec3c47f535ab4dab475782f0eb0e36e5fa5b456858da3e96ee12401a06f8145f2dff82bf7e077e0edad3456d9292bf36e80635569eb3491f3af57	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1578955850000000	1579560650000000	1642027850000000	1673563850000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6bad9770a7bea9e306fa10f878042a59d4157a7bacd1fdf4d6a296d5e0b93991bbe4f11f502b23e603474e692c0cca156e87d9191e60bdd9ebb7b303437a8790	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1579560350000000	1580165150000000	1642632350000000	1674168350000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x3247fe1885537707cb164c437b7453a292e424a3f6edcccce29764644ae30875065d10fe09f7f6fa1460b8abd02bb86d92e096ff5a45a3b92a4d29a260b43d1d	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1580164850000000	1580769650000000	1643236850000000	1674772850000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x628792fa0626666071c77fe000cd55ab17bf8ff6736f0c8363539884e7378cb2feed55b26bd083b7a3c225f3324923eafbff70367e89485da4e3f4cf674d2fe8	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1580769350000000	1581374150000000	1643841350000000	1675377350000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x882056a9e778d1b8eb3e46be45a1fd0c0194e11ddb0c344cad27171b04ae988d3081d29e3029feed71d5fb9d166786620ee5b58a07307cd528fd5af32a8f6a09	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1581373850000000	1581978650000000	1644445850000000	1675981850000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x140d23221497777da77e7174d8a508535b831eaa236aa62313741241a84824621ad3a0a293be4d8bef829b0c86c23fc09d3ddc220a4473801295c73e230f1f48	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1581978350000000	1582583150000000	1645050350000000	1676586350000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x155c57e0c7d24f70dcfcd82857b153efce59a8b31d2b533e7d3b8fcbaafdbba1ba37fbc918842bbf66c9e1e158b3e43b17e68c8a918ecf38f48a989f6e59837b	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1582582850000000	1583187650000000	1645654850000000	1677190850000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x00d00b54eecfc87cd0e2440a21b45ee2aa24a0ffe8fd3d81df1520ffc2a05c1817e104a56186da92805f3d9a1d7e310f8618672f65ed2e061c29f377f3491b89	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1583187350000000	1583792150000000	1646259350000000	1677795350000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x441307f3d93d53304a99cc956b675130c9f1fe5bea35062f3cd4d9405d6f5b0a785c20d165d67ade42ee3bc8ebc46c52c50db77eaf03bd4d55524d4b757bc284	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1583791850000000	1584396650000000	1646863850000000	1678399850000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf1f6ca8a53680a6adc118508325c4e69baded41ad69a9847add6e0bc88a7bd55ffb241f56ddc3d94d6be543977d06f22fbb48fc48fa0186ca39d5a7e0b22305d	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1584396350000000	1585001150000000	1647468350000000	1679004350000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8b2e6cbf9ee456d435dbae7f053a368be558e5dd208648ff4f696bb05cb91f5ab3ca1486193e9690c36db651ca9b54512f937f14cb5e9f9e271488e4b11482d7	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1585000850000000	1585605650000000	1648072850000000	1679608850000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa8a59d28a48f99af115c8e113fdb732c3ad10fbc133a9cf9306a3ae6cabad82585afa5ba37296626f6904a24ba6e48deabbc49e914d1974691eedd4c2af41a13	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1585605350000000	1586210150000000	1648677350000000	1680213350000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1626db629eaffbc3c99ad9f5a1e9d380aa86eee889678582c17df1a448f2349fe5ce5c599def76abd627a86ebc75b74e2cab96e4bbd7d5601da0c0ebed9886dc	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1586209850000000	1586814650000000	1649281850000000	1680817850000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xbd3bebaddb3c0bbd1bf4246693ad42190aaa992954c7e830c7c95237e6f1184bc87bfb3cb135b2a52603d1fd33314acf06cc24bd2bc95efeebb5376e30b2aa4a	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1586814350000000	1587419150000000	1649886350000000	1681422350000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7f3aab996449715854b2ee029539fdb3e52f98f30b0c782ba890e69e6caa750c29d5d5f713782ac246c222ded4ea7d07bb0985802a9645c720e2e85abbfb9240	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1587418850000000	1588023650000000	1650490850000000	1682026850000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xafc277100742943bf86a79e58c6e1a09d30709b17f673eff485caf0dcb3edb75ed8a8650fce9168e2bf39e67d227918f74af77bf3ab1aa7aa49533f2d8e6492d	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1588023350000000	1588628150000000	1651095350000000	1682631350000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x007e79ff3188ff30bb6b20f6b3dcf49c936f4ebf1dc9b92edadc8bf406b09d33bfbd1859f35b1bd11ce60b90ce3235d72ecbae95673d5b25744aec2db9c55bea	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1588627850000000	1589232650000000	1651699850000000	1683235850000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5b943ec0144784f009b914bc4086ab39a261a2f1801e1543f42bb3a20929d2f3444da3d4307c9cd8b9ecd883039a418f0846cc37aa0e53053544a3742bdfdc87	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1589232350000000	1589837150000000	1652304350000000	1683840350000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xde6a7f6e101b017507fac2e021384156c3a05be853724fcf00450117b5e69035771b5499a59ddf39d4bb5577d84d980235d32b4fc02b049551aeb8c7d8e5d002	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1589836850000000	1590441650000000	1652908850000000	1684444850000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf6f236f365ddba57580f1fb3d2a3f26aa01105d31cb12424efc9c6665186cf59ed2c7de0eaee837c8703a688d7c168bcffda16ee9864c3c1e9df6bbf6d5e4872	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1590441350000000	1591046150000000	1653513350000000	1685049350000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5a5a7a7d97db37d2e768bd929466eeaf4b560a24a4bb0a04a714885c860be1f08e16694f9b5e0e94d8c0b3c33d603f4813a6f9cde3c621eaed37c5e5817351dc	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1591045850000000	1591650650000000	1654117850000000	1685653850000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x279150bdabca85723a2c4a8dd28d5f9451af3c65dd41d21220e821e1d62e8cf69d7b16c4de98150812470e5c2a68bf39f5df3e79dddbcc284fc9a0870f78ce48	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1591650350000000	1592255150000000	1654722350000000	1686258350000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1e5a84919553a1621163fe8c5ec898eb3c4d8d93e61b6bcd9b67af386535b15d70089630070c6bed3a55e32409477c09252b9e9c7c3bcf27d180464c7a1ce5c3	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1592254850000000	1592859650000000	1655326850000000	1686862850000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf1c1f3c4e5d04f4c3af9510b4138e01e1371c5decce404c09dc916c3a77f19500256f761c8b5c344417920bd3fe8e75cafa1a079f6371730bfaedc87af27d66c	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1592859350000000	1593464150000000	1655931350000000	1687467350000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x682d883c04220547844d58bea362b95725b348add48cca64d9e150af371f96733494c5af4e62bfb204a2a4e11cb4fb1711c45885fd3b618f25e80f8d32b024f8	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1593463850000000	1594068650000000	1656535850000000	1688071850000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe8d48087b556b5cd45af2ce12e7bd627b3a40ff6178645b2e02a3087b91d900ff023d66d0604ea350217e3115b06c42663081f65a861e63381f91ae3f299c5d5	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1594068350000000	1594673150000000	1657140350000000	1688676350000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xdf20a19374e439d13b6b136de4ec42e92f666d95207c536c7f682ae685172108a87ae410579cc4f8b30f5c44d065324f09941013fa058f955f51098f8b8c9787	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1594672850000000	1595277650000000	1657744850000000	1689280850000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xdd0b222e3b477d3246ce64e3d3af65301191f1bb460113c522666f8dcdf25ecf1bd44ac22bb74f65c9f4b24fb7468e68652a74fde694ed1559271cb3c6354890	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1595277350000000	1595882150000000	1658349350000000	1689885350000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1f5a566a1f944964a4a04baacf312e5049f38463dc212cb8c32bcf896ca99088fa81a0490fcd38b70610647cfe6e9470bda5c22f56b373062e8408ca627c2b8a	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1595881850000000	1596486650000000	1658953850000000	1690489850000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x43d198371e24ff4719e79c02ad791da4f68fb4fbd25179237d7a49f253bf5dab34aa97e07e3b73164b7325d0ebb6cfa262da653570ad5ad6544e5588e924d3b1	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1596486350000000	1597091150000000	1659558350000000	1691094350000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x19e3a393e95c5255cb1f73e23e8acdabd0dc17e19ccbb419c618df53c86c5bd251f336ee2c32f6240ce65438644c49e00fbc690cde7a9f0b5aefa08446a68ccf	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1597090850000000	1597695650000000	1660162850000000	1691698850000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4b2da5c8cdf6d35bf33b39cdde880a6d2e64514ffbfb4776761bd822679cebdad4ef7e6a1a2ca9eb9ca5f98e4c4fcbacff9fa29dca26e27589225820fecc4145	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1577746850000000	1578351650000000	1640818850000000	1672354850000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5c0041318be488aec9e11459ec799d52932c36642481128b6ca39ce800c479c161537d64489227092deb407a33a10b0228678af7a2d64a8fa312a02843fdc8f1	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1578351350000000	1578956150000000	1641423350000000	1672959350000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xcafc006420e47e24471cf08b9b890e63aa766055b6967ec2fde390e701aa1bde0b724b82325b0d01588b67f83078669783201edd9a551aaef1ab5102c2a23502	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1578955850000000	1579560650000000	1642027850000000	1673563850000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xfd1ab68a1e8ce35288688eb0509e251a884d262bd4706868e8ea140199d21a89d7c3aed4b63867b70002b50411a384263f46f972b087220cc00ec513830f764d	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1579560350000000	1580165150000000	1642632350000000	1674168350000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd851ca6f6064be6ded1d9da517e21a1baf01fce67b1c78c79bbc1bcdd05179de633aa643a6703a27e6dae0bf2ab8b7c87369892fe242195d958f542c8bef772d	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1580164850000000	1580769650000000	1643236850000000	1674772850000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8a619344713f9559065adf37a9e0b9a474e3bcc314a4eb04e18fe6065d8708e3976614cce8cc6123c75406e4006e379858bae0fcac66c67e45f100a542889c09	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1580769350000000	1581374150000000	1643841350000000	1675377350000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x435a94c3aebfee5e1baef6694597cebb72800253a0085336ffdb47c45edac221c945718e0cff09007cfaa394ca111d9c29bdfd7f398a385e7f821c12a890fa14	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1581373850000000	1581978650000000	1644445850000000	1675981850000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x990fe3a7237e60fa59501c3b9fbad44fe68d474a3576542ee907284fcabcf8f983f93cc3d3ee5562aa44b2c594c863bfa4ecf52d8ea96ab40f57232b07f95cb1	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1581978350000000	1582583150000000	1645050350000000	1676586350000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8b62611b044f523167f27c481e25ab37ee959a8139377bd08e1de8c6c34a6d7c7af504820349894931765332139b53a63d12a6362e2ecd7911939c9045ad59e1	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1582582850000000	1583187650000000	1645654850000000	1677190850000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x29b5dea8eae5f37682d4eeee4586a108bfccd210f183852169c8d4c801ab020982d2870f90f425fda99bab5afa544900cbe82199d533763624fa975a92480a3a	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1583187350000000	1583792150000000	1646259350000000	1677795350000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6eed188855bfc7262bf9f561feb4cd32549d4135985a0f6c2edd5ec035f5ae2e88bf35408d51aecb7e25aef23aba5a53dd2be8dcb803e76d14ad8ad85c68ed12	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1583791850000000	1584396650000000	1646863850000000	1678399850000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc75e16249b51a6ef270cb6b856153b975777d40f77718ad245b2a60646c82328900c237eec462f00340857835cb3feee09574d3e9d30fc2198cc7fa495d14f1a	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1584396350000000	1585001150000000	1647468350000000	1679004350000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xae81c5451ae35d7aa7f9d498619ec9ff6a90f4432bd94572430b3bb902d7f26be31871aa6714d9dd2146c853b43b3fd7f7b18802b8efe240d89a9281f397a342	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1585000850000000	1585605650000000	1648072850000000	1679608850000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x0b402d3f77b90d21fa886ab153d123cb85d0fc5e2a7fbab4be6037bde0065c151ce62a4b0cc339a80dc9f373979af23548f1473a0388558dc0e2a2d398e14c4d	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1585605350000000	1586210150000000	1648677350000000	1680213350000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x3ec6004e26d31685aa73838c8a39f0185451fe2886a5aa5536fa8d20beffb3315a765253d13be6e5cd0fdf31a282059c2503f02f211fd51b178353e21cb8988b	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1586209850000000	1586814650000000	1649281850000000	1680817850000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x571b28960c5c5a158e2cb5feb70715400967b732b1276355fc90cce0cff247deb0d4337d790240fa4912ed952ac9b2f654d09d584b45069bddbac3688f0f3989	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1586814350000000	1587419150000000	1649886350000000	1681422350000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xcb8b4a30bc96d88bb7f508171f1674452e5eb4962e47bb376bde1458573d18b77ca868ffb9e5bc575e8323e756518d1978f99211810d0a5580f24926abb544e0	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1587418850000000	1588023650000000	1650490850000000	1682026850000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5f6e123eff50ef321a6c49133a9edc69bc126e8d0e3d492f193586616015f67299d9a5fbc456f2730c27f0b4a629a41881144812f60201ddba5c33e121fc8507	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1588023350000000	1588628150000000	1651095350000000	1682631350000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa666bf33eccc54698c3afbddf801f6b5e594a846a9f281fcef4624ab289296fe7df450637727a95e4c703d7002b773170e1233f9f76b0aff731ef0b64501fa15	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1588627850000000	1589232650000000	1651699850000000	1683235850000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2a5c57fdd1a4a1a7dfdae59c67fc43f7dcd7d0642d10265f565babf54a21d3750539f98b19e26f2288a4aebf96d754e1fb798b4598ba3946f8189c546ba2b9fd	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1589232350000000	1589837150000000	1652304350000000	1683840350000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd80e5f0706af2635dd358e03b52d4758bf6d8d343cff4491a46174203b2342898c7f66ee77372cdb0e7700ffcd8f0383d3614dd8ea490efba5ddb1dafcda06f4	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1589836850000000	1590441650000000	1652908850000000	1684444850000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4544df1b2a97b345cea5a5c93da5a24024850a6d0078477578305963bc3e9d36ffc11349890a1df51080ab036312f98565f51b4e9599f26c81c5c9afdfd2c340	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1590441350000000	1591046150000000	1653513350000000	1685049350000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x33fc35155c5174818127d33804ad8412cbaf884ddfc675fdd910c4129812eb270477c4c726c25b5a8c0c62955cdfc271d81a343f4aad61d3f54444e73954b648	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1591045850000000	1591650650000000	1654117850000000	1685653850000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x16b273d247cf8e89c745a6131eb267b74bcef7e820313350cbc95a8afad590141f46d2e32436de5fccafe87a31ac21e3d66d76738fe76114dd53e0d6936691e3	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1591650350000000	1592255150000000	1654722350000000	1686258350000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf9caccf34c373f343d0f8765c38a7cf18e8faabba7f02873ee46ec5a1b3225837f60238fdfaf65d45870e3f37f3924e990c6b21270ceec9efcb9a7ae7087f4c0	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1592254850000000	1592859650000000	1655326850000000	1686862850000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5be9f56c9d202992ae920ea1d475584b79b9d05be6d07181f12fa256ac0e88218a39d71ba2521dea6d823be404d4e1bb3240d7cbcad151a26e3ccf5ecabb8236	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1592859350000000	1593464150000000	1655931350000000	1687467350000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe3481b6d2999146fca6acb57deb78454c66be4283f82b186fd4602312113bcda09e673f738b74dafc49babbbe81945eb49daa63a2d52100cadf86eb17bdd44f7	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1593463850000000	1594068650000000	1656535850000000	1688071850000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x68992afc0be7a15a53a3c1a7be6897f22030d31acea7892b3c9fe03297445d73c0763bb7cee03d7161d57798b8342bab73b0f1061054dd2aa7efa17165cd94b0	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1594068350000000	1594673150000000	1657140350000000	1688676350000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc036e21dd256dea63dda075d7ddf567c536d73464e174ffc3db76fafd85f8298cfcad100f7c70c0a6c8ea5d4f40398f139b2f0eb81dcbbf764394101b3bbe169	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1594672850000000	1595277650000000	1657744850000000	1689280850000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xcfba7330fcafb34710a3ac61f4d0ef0a91c9acb9d38b73bcca23cfa54b3f13941c6f49e0a5299177f06d7e96ffdf92633f7710224979dcd2f1c38abc40ce7194	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1595277350000000	1595882150000000	1658349350000000	1689885350000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x0e96646751048e6071b86818938e930b5d349156016059596e0c6ec1e1dbaef14e1b739e7bc182440175393d8c50789d6ffaa389311118c8e977438e12c11b1e	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1595881850000000	1596486650000000	1658953850000000	1690489850000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x0a9b6deeea59d684488bffcc2dc4d83677d3f2e71123bfd39323fc360d9ab6f8857642d0f8def390a9749a535d3742dc45620969b716782f5f5246d1620afe1c	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1596486350000000	1597091150000000	1659558350000000	1691094350000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2d72b2ae7a9425f7d3cadb1db55287391d9b1de0c23c289531cc33c6c1722de424b3a829ee9d90ff1aa257afaea332df22c2f1977c981303f7282ed72cb5717a	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1597090850000000	1597695650000000	1660162850000000	1691698850000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2177e96171e76a1815e93e402b24efbbc469e85d1db39d382fb0f551af826080eccceab6435ce4544d6bb64574771539da4faa0ef60a5f7aa1e38b5e3c002fa9	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1577746850000000	1578351650000000	1640818850000000	1672354850000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x5e9c756cd0ff3ba9d2e5c8e7b73f01ee24bf5609cfbce04dc2cc011b71e949f51e745ae402ec901552aefe2026fa9637f29d2c797be4461bb6286d3e07bfb2a1	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1578351350000000	1578956150000000	1641423350000000	1672959350000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x73ec140c73e32a45f395ee3765238e44b720e30b2966e86c7e0f54eef007d268d17fca8ba34ba1c53979d0960038904be29bdaefe55b527ae33ff18d8d1d13fd	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1578955850000000	1579560650000000	1642027850000000	1673563850000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x8e51dce35623a3c460c1a32c52c1ca8854d35bcb0c37c55081e012400dbce9d0846ea50cb4ff39290c9800b22f48696fd0b67ace427598781e7070495319bbb5	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1579560350000000	1580165150000000	1642632350000000	1674168350000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x40f090cd25e77cb2d84cb6045e6b9eb6a8e5d75433348cdb6e01fe0117c65ac4aef05a86a97beed3dfe96bd465488e0f2cd2f971b661b2d3d708b5c8b6e111fa	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1580164850000000	1580769650000000	1643236850000000	1674772850000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xcb509af6580be83e72b32020e50d7c8925fa39acab195286989c537ebd5a250d949e5274a0349ac3dd708d302287346113fe6874c8d72bba0ae02da020292d4e	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1580769350000000	1581374150000000	1643841350000000	1675377350000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x45dcfe7706cde83247e51b59ae28ca0452749664885f0ef5241b13e918f94e0ebc77eb7e439bb80b562a3335aa96b07137759747ce4508465014d4c24678d7b7	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1581373850000000	1581978650000000	1644445850000000	1675981850000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xe134d8167f3b2c9178213b1c9d925fe4b0ccbd783ed21bf8aad4b322a2e0a7bcd18669e38c22853bac9e4c1b50bcf38d1a5aeba66fdd712176c75e7bab714256	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1581978350000000	1582583150000000	1645050350000000	1676586350000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x8225e105307ee509ad7bac086e21f3a17a9029ada5f3b3343f40ffadd23f6107c11ef42e7fb80d19ff006776671a5646aa5bbd684a7c5485f8e890237280a077	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1582582850000000	1583187650000000	1645654850000000	1677190850000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xe210f7767e22a2ec4272de53dfc4c86b497d3b09f8eadb5c753f5a4669f9fc12797447bdf3065f0908cbb299701b8173db3bea0ac7b80ca3bb8e1dc8b2d27770	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1583187350000000	1583792150000000	1646259350000000	1677795350000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x03c53444e1ee41f370db2b8811688510e56cbddf55ddc659ae577f5a00edfc9c307263392e50dd582f81f72ec3ff730b021a824708a8efc16861e230ed7e7508	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1583791850000000	1584396650000000	1646863850000000	1678399850000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x3d5e22f771838a017cad4a4d523802b52d79b731685dece9910031aea47c056df1def105c42a5687f39d106f268321bf33775b6b271ff5a9d0565f03fc0af53b	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1584396350000000	1585001150000000	1647468350000000	1679004350000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xe6c942ff15efa0b66547c6b2a99b6ab1b401f510e38487e06ceb889e9a3adb83858203ed9f014bccb99e0568442f40c73c1e5ceac3fad1dffe5667f0b7337624	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1585000850000000	1585605650000000	1648072850000000	1679608850000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x11b4ed6ba5240b0faaaa2d308aab1392b33637a2030c4a663b0fe99f695e421594241b984abfbfe16ced44b1bf7ac04fb659c7b370a972688736f13c6df8ef54	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1585605350000000	1586210150000000	1648677350000000	1680213350000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x11345ff20425f7bbebe7bce145d0502f978377828d12ec2172e227b3bcbfe0dafebecd19969dfa257eb2305efba48ba5106dd7aec2a993e84438de6f427e85a3	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1586209850000000	1586814650000000	1649281850000000	1680817850000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc458591ffc8026af16d2aae30b9c59f9892f5c73897ebeedb8415eb5321480eeaddebf2ab5f3249d596285b9cbff6d30b36857fca9e2ff3ecddc296974c6bb53	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1586814350000000	1587419150000000	1649886350000000	1681422350000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x12b6131c864b870282c363160186b136196ea0a2e049887976909dc5a6a83f5f15f28f5020d1cb8b4d0571510c9c8ad88ceac14c9887d8fdf788f893b3ede6a9	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1587418850000000	1588023650000000	1650490850000000	1682026850000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xcc01b9eec056177d370fcdf32c070d49a507c92013bc70c758271d345b16aaf8dfbcd00dd724ec055cee48da979d1c72ed91440bb747bc23dc964d97490a52dc	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1588023350000000	1588628150000000	1651095350000000	1682631350000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x00bef889535397483c5362858d8826353539836c5dc5722ed02c797d8a3832cb5a28d537889c9bc09ed40c36aa8f7a96bb58a0528bc6020f19dc601d1fb58f1d	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1588627850000000	1589232650000000	1651699850000000	1683235850000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xe14224c9d2c6c8c7e92d73d179c07b94204437348b61dcd8cb6f34af62eaa02cfa2740936683a61cc1e52a838104894e2bf697e48f0d5e09c72167a1685b2e16	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1589232350000000	1589837150000000	1652304350000000	1683840350000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x6176d18a8f263c115ae8595d2fde48cbc6a94ddc6a63f2fa795c77cf793ed8a51142bdc9b9869b7a4a0fb8875306fe403f38f349aaa766dcbb47b3dc704e3e2d	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1589836850000000	1590441650000000	1652908850000000	1684444850000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xbb7ae2e84d9570f752c236c40a5654bedf6121f8037642711056109093cbde64d83eec256f451a1fd233e89b40c33b239a18c5f60be652ce8b6f21f85f73e88d	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1590441350000000	1591046150000000	1653513350000000	1685049350000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xcac35da8063fe24adb3b9ead5c1794d1fd5ef44605c50fb6645e5edb41493afad1e23b7b907bd4b2b7b93f27eb48eba777cb9917bac58dd0ec9ceaef5b88ebb3	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1591045850000000	1591650650000000	1654117850000000	1685653850000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x03e32fe518369639c68bec1e1b874d54505241a8027bafc49b507b192bcf97a8281a1431aea5e5b47c5731769af551ab9f4c1d1d6c68be7de464cf0195e7efe1	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1591650350000000	1592255150000000	1654722350000000	1686258350000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x85894877360d56ae6a295c424da7d7aee04046aedb050edbd15522c702a2415c08c509a55aa5f524f97af78fa4114a399adae1e7a1400438e5c8f36d6a548bd9	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1592254850000000	1592859650000000	1655326850000000	1686862850000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xf9bd4eb2cbe179d88a376386a63501cd84546a92232858a517ae0d9dcae9efdc2ffe35e9c6d8a600a48e2f2e4eb86a470038bb92d5020a8906a6d174785fb5a7	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1592859350000000	1593464150000000	1655931350000000	1687467350000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x9146ddeb272fb415610c3ef88910d992b924744be1679459b88eac2e0a9dd6935ae8b7a04d5cf0f7681837c368a6e931b7dfb478381d17fe944d61f8ff72c9f5	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1593463850000000	1594068650000000	1656535850000000	1688071850000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xf37b467fbb756b745abac689c36a0633faf9a53a3c32fc01a354660a2c7bb86f31580e6c263b0bbe3a0a6346df47013c5f390dba2c2dc4586d46a003c3ee70c9	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1594068350000000	1594673150000000	1657140350000000	1688676350000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x7a6812d26eceecc9f1316a67084ce301f849f5688c7dd609995163ebdc0703fc99d769499f8a404b9221a93268251c80fcc5b336372b25905a5eeee98d9f811b	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1594672850000000	1595277650000000	1657744850000000	1689280850000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xbe54d32d601b11cae7f9ff2de22af1789f1ec367ad2260d5bb4f50d1de4b2cddd70763bd4c37c6fa3cd8923ac2933a8e9be108dcae6d1040fa5c32fad0aafe9e	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1595277350000000	1595882150000000	1658349350000000	1689885350000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xcf83bde92884139efb7392895fbdbc73f8ef71bfb507ad716d9adf0c1d4393e4809858b110d9bc2f0a56713d597c54acaeb340197515f350e8128df5bea6a6cf	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1595881850000000	1596486650000000	1658953850000000	1690489850000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x58ef5025df30e02ab4cd569f8632fe49c12180ef2fe5e07e73e8ce050807ecdc9bc4af433581620107d0b77fb3bf40591f5a93c8d641aa1358a4f5b66bd4a03a	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1596486350000000	1597091150000000	1659558350000000	1691094350000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x9b3772175109544fc0f95b977faf61b1e890de930f912f21c535ccf3ff4127cdb5fd533e96a0a5b44b341aa61fc60dba59aacbf7b645bb8298127c0a33f24cce	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1597090850000000	1597695650000000	1660162850000000	1691698850000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x08ec5aeff83b85fd101ea725f92d3fbf0ab406ec626399bd388be186fc8f637ab0647cd3bad70a79c9e62cd3658f14b46f1b59d741b853e4ce260b4170299639	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1577746850000000	1578351650000000	1640818850000000	1672354850000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xd263d28c9f1c6353d8e4c1f7bc79043970575bef796e273799a4e66a1fa512635a31c26abb2cd71e5972979a8d704636cf72dde05d3a1e0bf120f42637c9715d	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1578351350000000	1578956150000000	1641423350000000	1672959350000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x467be65e8795048bb583e79ef3a51bad04922301247a0d8031b0ec4f86d1ccc2d50772c57a08bdba0e9764da32670cac88a690561d9c9b7dbf1d4d444e8f62e5	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1578955850000000	1579560650000000	1642027850000000	1673563850000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x3f879e1c1122adbbfde6cc3d5bd97588cc99c74928fccdfc95759d2a6dd9a855a1b37b4f1334b3026fde1e7f8bc950ff53690abf961cd19aefe1a230a6c35280	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1579560350000000	1580165150000000	1642632350000000	1674168350000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x58f92e7ab60f38715a9b7e1ee71af82d186de74c7cd225ebaf600e0d73b6dc3d15062cb69e278f6329aca4e1feedef663e1472c8c6759438af9f4a4f6264df61	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1580164850000000	1580769650000000	1643236850000000	1674772850000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x1488cf1c1b72c340be3cfb74c65d9b68f925d8c23a02b2d865beba93c04ee6e60efe0c025e84a20a07340ed9bcac13b935400db5bac41ce99e4fe2d4f849a5ab	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1580769350000000	1581374150000000	1643841350000000	1675377350000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x069128da6b1f6a68ce231efaa0fb4e020a343bd8abaac9d6a2e89b451d79d84d4b1ca445660f7b51073bb5a14feea3b519f4caa10bfadef847eae84f3ccd99a4	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1581373850000000	1581978650000000	1644445850000000	1675981850000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x97a15d1d6a4dd3c8fc5c91b6b7891dca2fcf61df5ea7aa0ce1c6c90fcc9f5ebc6bbaea0b2033915668e9aa86b6ce4faf41e5c76cf7ae339da8f3394a6af9be59	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1581978350000000	1582583150000000	1645050350000000	1676586350000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x34fc75ec04d39dab8db9daa1c1e36de5643f165aeef0c337716cd084b6d15dcd683f04840e1cc9fdf5bbd74786c1e14401d014dbf04ade38dd4e96b2bdf19c68	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1582582850000000	1583187650000000	1645654850000000	1677190850000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x67d03b0e1a0e8f4dce72e765f0891b94e48eb3614782ec3bd27c7abd267ed203b28639a5b919be1e93a20fe1faa14d6c29b5a7762e33124e0de25a821c95cba2	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1583187350000000	1583792150000000	1646259350000000	1677795350000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xf0ff85d8ebbfa30279aecdb27aa70dcb8e2124961f03dbd32f7e442535f98b9f9edd7e5d0e09591fe4d3100eefd85f7f7a6fcad2dabe81f7533ebbf3fad8ef24	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1583791850000000	1584396650000000	1646863850000000	1678399850000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x42aabb2cc8730dfb3e5e09e09a283e1d3e5e8e0617c5048330b3acd578e1d7932892f00d59c81e8b6aa04d46072546b2c008b7a403020cddc87347f4770ce1c5	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1584396350000000	1585001150000000	1647468350000000	1679004350000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xebf9c8172d0cccf663a59ca55d6caf25b1d80cd9629e6578e20d416f439feedd4a187de0d7284e8e1dbaa7eba31d0ce1ebd5a32c1f6752433a3abc1efb2aea32	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1585000850000000	1585605650000000	1648072850000000	1679608850000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x2c5b11b546d46a6090e368245d9a9c5ccb7e1d5239f6fc25d98b2d75e5e27b9b0235a740db8bc2cf780007cec0b65e1696c8428eefd6c48c457d1a01fdbf295a	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1585605350000000	1586210150000000	1648677350000000	1680213350000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xe5b0ff50fd5760de95e2908d2209b42b6a434c3d068fa98e8557ef03eaf48cf53d67297c502504f879196a50e5ae07501a088d29ff297bb2792bb0995a684034	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1586209850000000	1586814650000000	1649281850000000	1680817850000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x1cd66dd97368b5972b0dee739ef08d1eac4ddb36eceeea7d9d8232c260160084f27e124dc52652b04d42d86fb1c9cf82a81eff329cc6a146b4ec971650942685	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1586814350000000	1587419150000000	1649886350000000	1681422350000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xa569d91fa191871584f4aa7f3b19d20f4d2d90c911ebb2fa6b7cfa7e248b531aeaea76e594a0bcfcdf6277cb4354a4cdd40f8b5d447b2f3d058ce573e202a927	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1587418850000000	1588023650000000	1650490850000000	1682026850000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x073e0f4df6d1c8a82581d094959f02b19f6428ae45924e60d24ebda8b79fce9a8838128f99d3c8510ffe566e3824eef9d0d1174fe4a283080340cb5e62624be9	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1588023350000000	1588628150000000	1651095350000000	1682631350000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x374fe8e3671c4b861b1dffb8e5ad82b9c014dd2791c783df453da0e86be13bb065dc3126f709a3bda42b8596147335e62d33db80fea06a292ba6f157a7411d3d	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1588627850000000	1589232650000000	1651699850000000	1683235850000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xc5f3accd3c8d85040b78e0f9f6e9a079d8af63d354cd0ccc2106509edf4ab860710dcbe231d96427b7fa22d4adf202b4acc3d1f26b9aa7ae042c75e0fcfbf4cd	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1589232350000000	1589837150000000	1652304350000000	1683840350000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x565c278e17b8c631ff3833e778995a81e90dad08d81282c5dc02eac402bacdbb05a818f39f91e8108b510c746b8cfdf2de7a078370e4b0153f2e36654c5ead8b	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1589836850000000	1590441650000000	1652908850000000	1684444850000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x5d6199b1b42ff44d4b7df9c30aa1556496544c146d07f27ede0ac62304a0bc4de0f6ba8755bb86953ee2d70e7ce532fe332d92f80c78129fab520367299ad6da	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1590441350000000	1591046150000000	1653513350000000	1685049350000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x0b7262710b69a83f22fe635b41f34a78188f31b12a73f4b12dfb8ab483509b4add3ed55cf56b938716e7290a4c50f2b83f8f401b1b2b13a640c0089cac5f35d0	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1591045850000000	1591650650000000	1654117850000000	1685653850000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xaf1ee1eb8c4cb6eb5623ff57a4f5feed963e12e3c6749df62b5faeeb49c52b370cd9eec5642f0de52bf69518ec1d1e24e7735df3c74992c2c1e203206ccba788	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1591650350000000	1592255150000000	1654722350000000	1686258350000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xdef2df327ee79d5fffbbed112ac927d9829159f0da1683f31826be035756fc2741e6f04aa1adedc1f467ef2ea19089d497f4e331a663f08732336b7ab6d54aa4	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1592254850000000	1592859650000000	1655326850000000	1686862850000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x0441ca17e1f896554db7073d67586800a0ee988366faefe17c835784b989148f5eb0e0d2380d77989b4325d4f19909e9af625e23b1dacf3c10578c555a8ce022	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1592859350000000	1593464150000000	1655931350000000	1687467350000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x2922249ea0603de38e68dd63cea64a91a4dec55b1b03cccb7d9b3b74bb31f1a284dedad75a0f40a2130380a1f44c4324a67630050698f3ba352a0984c86993f8	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1593463850000000	1594068650000000	1656535850000000	1688071850000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x9187b6638dd7f7503401efea4fad3511a1f4e5349371963dcdba2c9b30fb9ac3bc8908c87750f1c0384903ec4ad9e96e472a68c0d51acbff73713346254a0159	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1594068350000000	1594673150000000	1657140350000000	1688676350000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x635f18f391b7eeecbcf2b61ae7361dc4dc9413d2eb34deec2ae031a2fe84331d6ed2afd83e588ec0ba7c0856b020942199fd16d2a14b63a096df7bc70e95b641	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1594672850000000	1595277650000000	1657744850000000	1689280850000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x3f3362d74df203654cef89bad80fd3e6b685294eef28597f8cf700a0a59b0a9e9e9752e4884bb88e0a94a08eddb8282c3b00d7363c5bd895af7b03f865dd77b6	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1595277350000000	1595882150000000	1658349350000000	1689885350000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xa7a2f521c6527530bdd141d38809fcc273ef4f6bed01baea5f76b84980730fd17cb757007ea22d22d35de2850502e44a18fbf3d51f2482ca7e8158132c77ddc4	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1595881850000000	1596486650000000	1658953850000000	1690489850000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x4e7c441cbf4754f1b74ad4a4ffe6c8cb0007e7b96a568cf574b3305fc48372c4be34026416483954ff81b0f6ba435aa8df2b4f856106585ad0ad150a646144ef	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1596486350000000	1597091150000000	1659558350000000	1691094350000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xddda12abc2e93605265a8df6665b5cac55f9df418be0a9eec13452b7b3ad61ef775a0f9b8c30898fa7fe8ca202e2afb5485181e77bea1aef6f7077d37cea9d53	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1597090850000000	1597695650000000	1660162850000000	1691698850000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x342a53036140a9d41d0d3545d085b4a7e5844982090166231e639a7c773ea72d7ce730ee78d08cb62f7c4b772747abf0621dc6f2de90544337f545e11e000970	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1577746850000000	1578351650000000	1640818850000000	1672354850000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xf4a2325986f4d4d0191acaa4d6b219dd9c93c4240d92435b4f548b634d6a619f95d5ef39462fa9d3681c9317b8fa3a23dde88e60a80b4fd7bb6f1274cee3bbfc	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1578351350000000	1578956150000000	1641423350000000	1672959350000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x502f40e31f1c0d1cc84d3c511d459788debf9f68998e87f4378cba336f817a033add0a70a7ed80c23bcd3b0efc5cd1d62ca99b86f6da45d8b2ba2cbcfd5b82f3	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1578955850000000	1579560650000000	1642027850000000	1673563850000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x8ae95fff942cf6fb3041f18a213a68cca39c55fdf48d5b80d861682ae60a24f275ab35935bc2f790fc4ab512cae4e7ae9c235807f3269bb9f9717504b2d9d812	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1579560350000000	1580165150000000	1642632350000000	1674168350000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x31c86f8596818a63c217df16ea5efd31e0e45427f2066be6bdf27ff90d057e8ca4d80055ea20fd4b63b682d03022dabda1ff38a38f2e814b6297efb685d88e55	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1580164850000000	1580769650000000	1643236850000000	1674772850000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x9563d7e594b4049f4689cd26a1be11d2917d1d55645c904c3a827c562f10cc56111776a7d9ff436663abf0e4941d1de6bbe731108207f9ae8fefad3d92196db0	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1580769350000000	1581374150000000	1643841350000000	1675377350000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x2bf6d66e88d33354d1d787eaafcf5e768c3fc935ecc051b0ba8ba830fcf40b57d6f96131d7bfcdcc8e6b64a38c29cb04572264af2743a01686c32f34a76ca15d	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1581373850000000	1581978650000000	1644445850000000	1675981850000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x309d8a5661fd90981ba0c4306316f424d7adec74a089e58cc5b9ca4dc21c540d215887ca37b12c8b327c887e37ea5e93153991aa36188f1b83286f961e0f27b2	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1581978350000000	1582583150000000	1645050350000000	1676586350000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x4ba222b8784eba3389875958c8fd0d633fafae2e8fe96df739b8b0f89e2602d9fabe70f4e851fde023906e5b32160670c311f1bfbfc65ae2c704cbd5abfeb015	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1582582850000000	1583187650000000	1645654850000000	1677190850000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x4dabde48438844ab9d1b52da5ca5569b8d47c39b482f0bf2fd5a8e4b963e6c5927cc80543fc74d775c1c943be4e3e5021f4eedbcdcfde8af6c100b18eef43696	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1583187350000000	1583792150000000	1646259350000000	1677795350000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x4ba10ec825ae9642bfe81660b5d062d4215228665f527c84169e5498a31b7aed6b5cb2c4107784ad43fb071565a97bf5ccc6c8115fa259e22d9a3e5fcc27cd85	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1583791850000000	1584396650000000	1646863850000000	1678399850000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xd6e30cbfe66c1ae3cc70fcf2f9218481446bb8dbae938549b6674d1a63ad3fbca6253cecd45618d1736b5f5de32feaac3e04d5b59d3639c9e17406fb74f97db6	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1584396350000000	1585001150000000	1647468350000000	1679004350000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xc6573c867ee1d852b9e4c7ed4301de2bd80c7b210e51d892589f020fd3b023762d71029fa2d394d6c66140ee0f227662e2f89b1d2d459c0ccca12c153fdfe514	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1585000850000000	1585605650000000	1648072850000000	1679608850000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x349468fd8d47e1e7d1edbd1d2ce1d7bafd34b12480ffd2141a9ac9a9215dc8ca8a30056bcebcb56620609f9ae5449cbc8cc31c02948eb207c58d95fcca580e5b	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1585605350000000	1586210150000000	1648677350000000	1680213350000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x04f2beca32d59b8b0084185fa98795b901481832869bb176f4ea67f53a10a33a467a9fe6afdb11ef9d5a5a111f05109f93c10bc594a1f1945f3e45f696823735	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1586209850000000	1586814650000000	1649281850000000	1680817850000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xcb260a81db103d54decdaf871107ea75dffcac60a0fecb436c289f68cf2cd9672679fbf5ac00fb1ea11d6480a01fb23bab1f1c220020bdc4c38238bc28f8a39b	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1586814350000000	1587419150000000	1649886350000000	1681422350000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x9e54abaf1af0d17937989360fc090baab1aacd3c1654c952b1fc9e66589fa3eefb291cc2fe26f0e778ecbef15cf819ae78c2d27a52bed6d8628010eb3430566b	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1587418850000000	1588023650000000	1650490850000000	1682026850000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xc2a11f578020d6ce22575d99948f659b8521dab4d7fdce4c1ca5793e6a6d082a0d9f89af1e0c4aebeb2e096425832a70f58288aa1cc640eec53cb49fd502a320	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1588023350000000	1588628150000000	1651095350000000	1682631350000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x5a8deeea977be6b1a3cbb9aacbda4ae31b8383a828bbf2cf5473d0689ee0e6f5aa1b620f065f244711bf7f36fd093cc837921baed5ce675c5ee0e946d4c470cc	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1588627850000000	1589232650000000	1651699850000000	1683235850000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x6b5de7b43eedea9e0ca5bb6965e4035dd3f8aa4f6bf6ec2ecf4a585247f6f6870a6f50ee34b776e9abc4930bbad5d0dd938e2a09c6f3082fdc6e1cd81cd6f6d4	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1589232350000000	1589837150000000	1652304350000000	1683840350000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x48d5129219c09f66192845fa7b5eb43c3b41f98ef76d90d7d5b0aa8ed0a1316cc69060b6a5b7ca92158e4a8ad31785405a0e4a1716907a8cb061f713a974a155	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1589836850000000	1590441650000000	1652908850000000	1684444850000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x8a0caf17cb35e04c800dd6d39f4003933273bf8b33b4db840ec17ffdae92864b51be736b57b3193c4c634bdcdb126342e4c1ddcf6d899d4930d153cbd114d501	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1590441350000000	1591046150000000	1653513350000000	1685049350000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x01f0a7e0270a95680f9ebe0c9d469739fa3962a6aa51a3776ea5302b4a55aa5fca4750803d25a3eb090ebdc63a3e5b243dbd89eaa965cd7794f5b6a6ecbca754	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1591045850000000	1591650650000000	1654117850000000	1685653850000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x7bf42769a8c5b7963a42f759c99c870df54f3fd769ebdcaee64a1093990b9cb260b524e18037cdf2fae4f08d6be78efcc94fe4f5f635c633721d6ba9904cb7c0	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1591650350000000	1592255150000000	1654722350000000	1686258350000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x240a163717f69e284335f7e85d9af079e99d38fd8c748a6e788af32db55fd8a8311088a7e1cffe82a69331fce0c730a3080ae3cef6df94e13283cb8495ec1e79	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1592254850000000	1592859650000000	1655326850000000	1686862850000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x4484ce11838cd6920bf16c0bdc1e0894f450f4f07c5b61bfd20a5aeca55a945d5dcde451448337bbb5134aa34e1e8c88391eb9639313f85ae868c7f62eb54a35	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1592859350000000	1593464150000000	1655931350000000	1687467350000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xe4747ac876405ffbde43b56de087702b10d41bc159fe93985f9a23f113f7b8985e1662cbf3195e689744c796b78675673a39f4670932467b6a64ba0282aaf0f3	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1593463850000000	1594068650000000	1656535850000000	1688071850000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xd5ac7bdc81907c90014ae1525bd848c74b78c42757d79a50bd7d85f0bc9b3527ce1cd4d3237fc8089fbd00123f58120d6eb446368b53ecf05ac0a35eabebce5f	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1594068350000000	1594673150000000	1657140350000000	1688676350000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x72fce5e1f3b47d53f048f8f3dc846315c5570ea09a1f821c082822a1d7c7a97fc0443b74b52243dfa352d135a1f5d79e15f53f88de218a4e403903c762e97630	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1594672850000000	1595277650000000	1657744850000000	1689280850000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x132b161b489d3c7d2917709438049aa869efc918cbf98010fe8dcb7210e2214adc0436fcd94fab3d67dcb3f358b281344afdb8ffacc0e7d6c21755613eddfca7	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1595277350000000	1595882150000000	1658349350000000	1689885350000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x67215978ab63e5a2269adc47c69b075e2c43816e282a57cd74ab628b6dde19c203315805ed50099255d772fa5cc4506315c8efbddadc58412aa68797bba0437e	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1595881850000000	1596486650000000	1658953850000000	1690489850000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x72d7c7d52c9171add01dd45dfc2bd055a805afd510b989619c6e301c6665bafe5ae256fdbb75ffab718f9a8493858a05c0f3798379800a12a01337f5ffbf3bea	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1596486350000000	1597091150000000	1659558350000000	1691094350000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x1cb1e862f2ea76425e5d111ba2afa41b0c8d862f7622dcf0f33a6d7207f8d6315a60b7a64152023d87063aed854dc9bb3d280c4d630d6688fd7bd57e03bce06b	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1597090850000000	1597695650000000	1660162850000000	1691698850000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\.


--
-- Data for Name: auditor_exchange_signkeys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchange_signkeys (master_pub, ep_start, ep_expire, ep_end, exchange_pub, master_sig) FROM stdin;
\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1577746850000000	1580166050000000	1640818850000000	\\x230848bbd97087c56e78e231a14c96bdcc369aacf4a77302054125ea91e83eb9	\\x2bf76c8c70657c798f7890a0150675a756160d62f8e6fd6ef234d5124fbc61e9fce76e9bdbd67c9d7a5bf19676a91a57caf9af72f37cbe9ba81834275e83430e
\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1577746850000000	1580166050000000	1640818850000000	\\x230848bbd97087c56e78e231a14c96bdcc369aacf4a77302054125ea91e83eb9	\\x2bf76c8c70657c798f7890a0150675a756160d62f8e6fd6ef234d5124fbc61e9fce76e9bdbd67c9d7a5bf19676a91a57caf9af72f37cbe9ba81834275e83430e
\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1577746850000000	1580166050000000	1640818850000000	\\x230848bbd97087c56e78e231a14c96bdcc369aacf4a77302054125ea91e83eb9	\\x2bf76c8c70657c798f7890a0150675a756160d62f8e6fd6ef234d5124fbc61e9fce76e9bdbd67c9d7a5bf19676a91a57caf9af72f37cbe9ba81834275e83430e
\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1577746850000000	1580166050000000	1640818850000000	\\x230848bbd97087c56e78e231a14c96bdcc369aacf4a77302054125ea91e83eb9	\\x2bf76c8c70657c798f7890a0150675a756160d62f8e6fd6ef234d5124fbc61e9fce76e9bdbd67c9d7a5bf19676a91a57caf9af72f37cbe9ba81834275e83430e
\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1577746850000000	1580166050000000	1640818850000000	\\x230848bbd97087c56e78e231a14c96bdcc369aacf4a77302054125ea91e83eb9	\\x2bf76c8c70657c798f7890a0150675a756160d62f8e6fd6ef234d5124fbc61e9fce76e9bdbd67c9d7a5bf19676a91a57caf9af72f37cbe9ba81834275e83430e
\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1577746850000000	1580166050000000	1640818850000000	\\x230848bbd97087c56e78e231a14c96bdcc369aacf4a77302054125ea91e83eb9	\\x2bf76c8c70657c798f7890a0150675a756160d62f8e6fd6ef234d5124fbc61e9fce76e9bdbd67c9d7a5bf19676a91a57caf9af72f37cbe9ba81834275e83430e
\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1577746850000000	1580166050000000	1640818850000000	\\x230848bbd97087c56e78e231a14c96bdcc369aacf4a77302054125ea91e83eb9	\\x2bf76c8c70657c798f7890a0150675a756160d62f8e6fd6ef234d5124fbc61e9fce76e9bdbd67c9d7a5bf19676a91a57caf9af72f37cbe9ba81834275e83430e
\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1577746850000000	1580166050000000	1640818850000000	\\x230848bbd97087c56e78e231a14c96bdcc369aacf4a77302054125ea91e83eb9	\\x2bf76c8c70657c798f7890a0150675a756160d62f8e6fd6ef234d5124fbc61e9fce76e9bdbd67c9d7a5bf19676a91a57caf9af72f37cbe9ba81834275e83430e
\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1577746850000000	1580166050000000	1640818850000000	\\x230848bbd97087c56e78e231a14c96bdcc369aacf4a77302054125ea91e83eb9	\\x2bf76c8c70657c798f7890a0150675a756160d62f8e6fd6ef234d5124fbc61e9fce76e9bdbd67c9d7a5bf19676a91a57caf9af72f37cbe9ba81834275e83430e
\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1577746850000000	1580166050000000	1640818850000000	\\x230848bbd97087c56e78e231a14c96bdcc369aacf4a77302054125ea91e83eb9	\\x2bf76c8c70657c798f7890a0150675a756160d62f8e6fd6ef234d5124fbc61e9fce76e9bdbd67c9d7a5bf19676a91a57caf9af72f37cbe9ba81834275e83430e
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	http://localhost:8081/
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
1	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Bank				f	t	2019-12-31 00:01:01.970798+01
2	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Exchange				f	t	2019-12-31 00:01:02.044713+01
3	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Tor				f	t	2019-12-31 00:01:02.110923+01
4	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	GNUnet				f	t	2019-12-31 00:01:02.178442+01
5	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Taler				f	t	2019-12-31 00:01:02.244176+01
6	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	FSF				f	t	2019-12-31 00:01:02.309535+01
7	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Tutorial				f	t	2019-12-31 00:01:02.376023+01
8	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Survey				f	t	2019-12-31 00:01:02.44143+01
9	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	42				f	t	2019-12-31 00:01:02.859978+01
10	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	43				f	t	2019-12-31 00:01:03.290111+01
11	pbkdf2_sha256$180000$MvW8gNTzbxXM$B04kQJl06gj1STadPJ0ppZQ3eUjvgcU221LzS77Zr00=	\N	f	testuser-kaG45ily				f	t	2019-12-31 00:01:04.956851+01
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
\\x8299edaf45195f717ef2ba0062ec8034bd49244e0747008e42c29d1a73da5b469bdd058b512d84e5ea9ac4f50f690d7cc90f07f2529da1b2758f8ec97f7012c3	\\x00800003a29da52f5a87003e9fe7bd7d6687485db54e27eac20442c499351cbe721731f8cf7bf186793c3a25162ad976e1b92de11a6b3ef99bf68a554f4a92c4fec7bfb18a59b608857395dfb6134ac37a42976dc7399ac56879baf22adc2546ca690d3b17b2091ef68f1569cc6a3aa680e6695a37cda0f066b1e66515b69f16518aaba7010001	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	\\x3de9e8df55cc292e98bf868e9126bf57c1af4e4118d93a492860bc9f179d8a124c059ba14e33a0488bd7c762aaa9d34bb02e476010fc2d0e8d9d8ee6ba447e06	1579560350000000	1580165150000000	1642632350000000	1674168350000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb0ae30bfd2bda436dfc81a6e4dae41b9a09fd5d5f3f9dc1085b2b198523c7b9bf7c6ad6b8a919f274c14d2f71026bca7a83bcde301a30cca4459faed7aa59c69	\\x00800003e8265737909fb1eea810e13d5e3b07d52b78d09430eb472d0122c93431a4df607c85a4454e354e1f13f5f076f31e15c2940c9759c2aa8c21ac0cf4b398a86e7430747858f6d6800b395cbad462312bc5c522585fc09175400d267b4b5b115b229a851281375c51ab8ffd3b9e0aa9792526167c7661fe0589d17f5bac76fe2cfb010001	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	\\x1f50ab5bd071d257c660e38d927011e53a0d81a381dc5ba09b6c3f894e961a5c933fc829ffd982d394aa07d8a9ed2330d37b45cb17a40fd8dba50a6a25da920e	1577746850000000	1578351650000000	1640818850000000	1672354850000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8c3afa33d33226b3088c1d03719432d4a6b0b29f10988074bdecb13e04e27cfbff3699923137c9c576cb379bd4b936a27e1bc6b7cbb685eab5a7742cb0dd044c	\\x00800003c329a8b071651e8cae6f963fd7905077a68681342df946611a92bdeebbe606298dff4741be3d7c4f97dc13c0deab9e48a3585223e71b1fb3532de48e2f7871fa84a8e8186fb391109ce39b2b478d828187c9bfda9d7267d510a472d6db7b5238d85a056bbec3280b09424bd85785febfec23d63db077c367d9a838dd8f3f56d1010001	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	\\x7a548d4b79f3930cb10a2e1d485fb9e2ae75711dc12a63b9ac43fe03378861ebeee4860c8a1e20e8d9cbf4382581c55b2b63fd4574ca05d21042f603ff588709	1580164850000000	1580769650000000	1643236850000000	1674772850000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xae07165c301449fd9c2e7d7cc73abcbb263dcc71f146a3b81466d93e27ffee65836e8cf5cc26e5e8dd9e26fc30034b20b201ddef7ef6698eb67e30bcd91e3d61	\\x00800003de6bfd1bb0eca8ff488a903f02548085d633b944eb6b3e24bb6996040ff41ad29ef489f08a711d9cfa07cbd9acceb6e8893dad378f14a7b894729818a636e92202af5266870144b99cf17373a7e95fc2ab0aa648816cb9c1395fe6a73b1310306439d98f7cdab1c29a9e10759b9b1b9ecbbd3d602f466e8d92d4507424f4e3ef010001	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	\\x806e547838edd2c84e2b33c1fa0eff827df8b22c596ad0f0fbda1700a40ecbc71f5fb3e6b35b6d29394b05ebc19e2bca9475f908f360e2b4c5aca36353b4c50e	1578955850000000	1579560650000000	1642027850000000	1673563850000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xcab27154f59ccd368615e00018e2f86484dc21495e09f8d842891ef2c381b7793bfa67683c1a8edaf270f0b7fbd9943ea8b37ff30af34422075117fdd1b62820	\\x00800003a584aad388966098d9f87cd6b69d531083a118cd0c25056a0127aedfdf5b91f301bbe0d7bcea36513ed5f3c4c5f156684cfb9476142bdb5f2c6cdf20e17b9dfa17b356322fce691f7071a9883cdef58718fb1e723deacd64ffacb8b1391d0e0e2961aeaa7951e82665c886847b7c140580b1a70b418b2e76a5c019d6eee9c36d010001	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	\\x0e08049a70ab6a275144527eaa31a91839876a12a11facc1ce4c7afce853ab4ff0d0615d60bf483227b29ebd2a6f446ebce93c90ccced1e3b127e0bb2c70220f	1578351350000000	1578956150000000	1641423350000000	1672959350000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x59b95ccb64707272e2fb6ed2618a0e28979945d6940956c8a7df42f6d81fe8505cb2f3dfb4952bd3738ef1c3435d2d88cb3788af496286e7423062fcc8dcc45c	\\x00800003f0cbc674abb6f74396328784c2ad06f114c5d3e8c5729ca2e687f9615a69f3cad7e201340fd7dda7c4f4a75c76da4590506d8f61a0b9bc6ce94b70fddb6ab36740c622e747909953af852f3b6c24f2869ae38c2b7667f2f83bfddf1c4e486e6be575f23b2940512eeb7749a8ab9828417fb8936e418cf7772171d7f15325c209010001	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	\\x7e6fd8e0657ae38bdef8017d0d58b7eb01039a5a89a0b2a5ca283e5a09dcbd919c16ef31f35b5cad072ecd9d48c84640dbd45446912bbd31bdd0fe611ac6060b	1579560350000000	1580165150000000	1642632350000000	1674168350000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x247e75ac7100bd05188c214913c0ff02cf2e362f02d13ea07db3ba2c697c95947a5b30492cc76c4d0ada5d1e5d93892f37aed186526798c9941f55b9a07fefb9	\\x00800003c0786eaaa6f9b3972d8192b9e0cd8418224825206ef66d9b003a5885ca2bd58569448a8592f030c53b1944ee7cb5c6a3aa66a040bad9f88b574a2df7351de54b4c8a972826315366b16392c9d0eb675aa346bd5b7af600f7f85bf88b9e3ebb793e3c21c42be53330dc6fb7a9e207e2d6ccac72b03b7f72137a664d36d594dd49010001	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	\\x130aa499f36a51367ce12e0f8d5c3a1ddc44f2707c394c291a01de7a6871e230787216b587188f65e94884197904b38f8d5ffe5f6500f59e0098c48fa970170d	1577746850000000	1578351650000000	1640818850000000	1672354850000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x90bc2d8548a560e5eda1aef3852db4b789bdcc36c63c119ade71fdc5df4d702d5ea95da5d225c6cc87cab0b13a40aeb9d16736c5639da42500b1ba7099a20da7	\\x00800003c4158d3a68548599fdcb1331187067ec01a425939ceecc87617b800a10b308867b35b4c0f3fd55838256f7b9494c441b3e0381e835928439581651b0dca7a5bb303e7edacc4511c06eef40de192697e687c379f824fa119bfee9c7e33532b7bde3f093c3d5ea9b67ca16c879edd991597caadded53d07f8465afe058ac925dd3010001	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	\\x2d669779a89372ca89c477ae988a5bed272d17543f5f89fa06ade5c493af9460eae19c6b716f2d7d8ba10cbb3e018ff3359853455e603c6a21680406b7ca3402	1580164850000000	1580769650000000	1643236850000000	1674772850000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x67f37c56d05a700c014e6ef7e1466be0fd86f36b90dddb2b0b2bd8e65d48c0b3b915bcc7f850b511fa24c03636ed97a35e759b403a68aaa86a514b2560c63353	\\x00800003bf29b1c1a276a60f7fb9accda1fb90497e14fe772bf5e79ef946b111c02149b0969445f9fc744397e14a750cf09cf5b992e4f6a46811bee602277525ac0c5418829a44c23a675161dcff44fa17185d0653f8903e3f85364b24200d565a53a5fb7256811b4fccc546fc93b9f7150ebc78f23c1815f14bcfd32d75712ffefd1381010001	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	\\x04e0c1a6f12f0a0a26cbd88488655e35f2fb8abce64e5fa97aa992244b9aa505d4cc55426f7683ca8aa439a7f2c4b59e2da546854ef39ed23f27e58e63dd4909	1578955850000000	1579560650000000	1642027850000000	1673563850000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe6821e51ed69054659bc1054ffb675fe02f49daa7fa6d8ba69f72b869111704aa4630a3ad3ec2bed7597c94e8e023be0132c046c0faf18f806e758c2be417dda	\\x00800003c8e41ac846c0205baf52bd4bac75e86d44dd4c4b1a71540e54f76ad3038edde2956b651b886fbbfada2ea9b042f1140d074357544d116fb042f8ee96346f499c4c5ed31ad0d86cfd2ccd0180aa752ac62af8b0fcaa8e47d4b23a7ee5c608b882a775b56cd52646ffd0e0439375ca0a63d3f965f129e5846c4912bda8040b6b89010001	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	\\xcc3db31e7a84df04b803db84ca1f697a591e6b6535c12f852122a43145e3f1045739b63c76f90cb7e144c9faaf21cc3f5eedc3efa1c39cefac5691296692d100	1578351350000000	1578956150000000	1641423350000000	1672959350000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xfd1ab68a1e8ce35288688eb0509e251a884d262bd4706868e8ea140199d21a89d7c3aed4b63867b70002b50411a384263f46f972b087220cc00ec513830f764d	\\x00800003b003f09d95eccf9c970006236ceae6cea806a63bc55177bc30a76bf626df373ee7e67abc93dda079cef34fec555cbbcabc3e8f7bf5d657cd1d7b9f25b3ed469843a0a4807b0132843387b3363b9c2d2b3f839ec0cdbbe954ecd9db2920693b71fdd0f3420effb1fbda67d24abc0611cbacf203598d8c7e55eb75cfc38ebf5671010001	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	\\x1ed4b4265cf538402748c73a3a0ea7ce4f7e886f4159cdd61b985f2e22116cda7af63fe365ac270b109e7cf5a18fbcea208c7e8687d9575ee3feac2171f5c509	1579560350000000	1580165150000000	1642632350000000	1674168350000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4b2da5c8cdf6d35bf33b39cdde880a6d2e64514ffbfb4776761bd822679cebdad4ef7e6a1a2ca9eb9ca5f98e4c4fcbacff9fa29dca26e27589225820fecc4145	\\x00800003db0bf35d65d565de50f63868f956b3579d5f8db108c3d319425f2aca31bb8b0a7fd784f921a6e9edeb282ce136f66e06878c87a3e98fc69d8a9171ade6e1a6545a0f7e09b929dd65ffb53950d3373cc4c8ef899f44f6bdc1bc20ffa00a8c94697926fd5026044a818e1cea893bb831c764882121de16ee129b0229d3143fa441010001	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	\\xdee8c59494ee7c9c04fafae1c20980902f496cd6af934a9b4c1980c9f0ffb8a5fb15ab1166a8f63ddf5413423b1b5e03a57a4c3c246b4524327f3d2a16cddd02	1577746850000000	1578351650000000	1640818850000000	1672354850000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd851ca6f6064be6ded1d9da517e21a1baf01fce67b1c78c79bbc1bcdd05179de633aa643a6703a27e6dae0bf2ab8b7c87369892fe242195d958f542c8bef772d	\\x00800003c9f4571ba0dbef80cd5b87cfae44793e9ded96a80bf35bdfd557be717f53d233359de84a6490f5e8e5ddc833bfdd1f470bc33cfdbd85e6217f66f1b415faac4d8a7504baa8f11dfbb5cd7b710e21aa414733e84ac864802845ae65c37668783fc03b9c6e6415cec329e1c8df72896f0a2e735a4a56f0079df57629db9bf26e1f010001	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	\\xa54f3fa8f49deb66d385cc1bd8689a14d1b842b8726f33830c3455925a498cfb6a145123cadcf8ccd9742e4501094147614b5480e1c216ce033fe8b1f099770a	1580164850000000	1580769650000000	1643236850000000	1674772850000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xcafc006420e47e24471cf08b9b890e63aa766055b6967ec2fde390e701aa1bde0b724b82325b0d01588b67f83078669783201edd9a551aaef1ab5102c2a23502	\\x00800003b6dee950d4fa376176e327a5dbf4bc14cbf8b64be2d98447850cec2e6240f435ad2669ed52a9d3ea883541990543fa31ab453c7a09ca20e7ae424b0d91bd0683ee33c51d7d46e97df8943bb95d6682ce31aaca379c9bfb17bfa050f8a920c37964ee02d162f8efc967f3dc89df6b729c4debd93ee3c9defacbfa91567e2f1a9b010001	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	\\x27adc0570b3158b4a6426677614943a0ee519673cd9217b6dd662a3deeadb4f48dbb7486c80439e546209bbce7546826d97e530963efc7aefa1190e8b20c4c0d	1578955850000000	1579560650000000	1642027850000000	1673563850000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5c0041318be488aec9e11459ec799d52932c36642481128b6ca39ce800c479c161537d64489227092deb407a33a10b0228678af7a2d64a8fa312a02843fdc8f1	\\x00800003a3cadb1f507fcaa642414a8ba159b5fdb395727673a9a817633939135d7bd528feb38de8e9581f53b21121be70ceca7a312263ca6e56219c0e10652db03606e1e7bc2e4bd3f0b8edac9513f09d1eb04a49d62a204dc099e2eb31a664a266924d77252f24b2e2ad5c7714e5471b0f8486a4596eaaffd3549c47d47d7696aa9da9010001	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	\\x146eff0cac43bc307d676692d51ac50dc38fb74d80e5bf1f30acf43cea292d6272fbfc5f314c0e40a5f7ee57344b1cebd368a68fc005d0d355873dadc2d2d007	1578351350000000	1578956150000000	1641423350000000	1672959350000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6bad9770a7bea9e306fa10f878042a59d4157a7bacd1fdf4d6a296d5e0b93991bbe4f11f502b23e603474e692c0cca156e87d9191e60bdd9ebb7b303437a8790	\\x00800003d69c2d7dec83449ddb52d7fe261130f012b59773db434abb77100155be24cadfa977dde2461c9d842b73ab04f09c1d216ed1b2df36e0d2e9a5633428e4ee526f65497f59d16d8645f403441b396b030f2b50e494510ac31018096d00fde2d5c54541673c6e34780a5dcc7b5cf51123a5b0f5f886a065ead11edb17e8f4c0aebd010001	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	\\xaba4141eb5cc60eb98324bd261f10a72a20506afd99f6bbdb6bff8429c62f906dc8a6794958fa70104d7063df33eb6c769c13775282461ec18e976ef8dfb5c07	1579560350000000	1580165150000000	1642632350000000	1674168350000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x0d953d54ba6115a8c939faea176ccb5e81eb1430e03e73b334917e2435e4c9a66e136aad06545dd09eb80fd2df9c88907339eeb06b1c095cbd69aa790731abb3	\\x00800003c2cfe451f55000be6667e659ccaa65341e744e0bd0a8dc67998c79cdca1211da2f99416f61c3af79e695669c154a0fd8e56a5f7415259d562071d1cabaed47d0df63e857e6b94060168053dd67fb4b9d63101bef0589c0549860cdbea6e4a906f68ac049e32def4e4ed76f2ad275716c443719d348e997f2592a75e0c07c09b1010001	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	\\xd0e5bc1af7077fa1a805d26fb1bb45e8260139707d3ff31eab1616cecce9e2ca915398a12addb1655a1f9714c0c791ce64b3235d9c281e1881679ad25b0ec501	1577746850000000	1578351650000000	1640818850000000	1672354850000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x3247fe1885537707cb164c437b7453a292e424a3f6edcccce29764644ae30875065d10fe09f7f6fa1460b8abd02bb86d92e096ff5a45a3b92a4d29a260b43d1d	\\x00800003cd9130d8c7411101377bcdc48bbc80e55b159662e883a7f3442a51cc1129c56a4d67b832406aa3299c0279f3c51e9aa0be93358845c7cb0923b01bcb8d9f39c00e6f2e5732e4f8bce2471ea8191cb4a80b15a9a501248497c15f9083df9ce1b4bec6af8e314521a4ae59ce08ad74bb4fb19526ef11ef1a17a973e3451191929b010001	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	\\x0dde061857529d5973ca235f87c63c803c47d18d02b297f6ce61cf588558a1c59b20373913f0a6f2d671bb10bdd5b97064f3a68be418e8c3613592f07293a30e	1580164850000000	1580769650000000	1643236850000000	1674772850000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x27a339f6a4eec3c47f535ab4dab475782f0eb0e36e5fa5b456858da3e96ee12401a06f8145f2dff82bf7e077e0edad3456d9292bf36e80635569eb3491f3af57	\\x00800003c9eb8f43f1a83ae75e15754be8c0b4012fc88e4de23d494584f8d2d55a74b7edee02fd4d284630b2e1b83312545b055228bd1b69e15ca241bfed34c423594e6fe273d378942e05ca1f3a4fddab9d49688ee4a0e01e0d78f3d2fc12160e9e3e99fc006927b3a9650791bb3f8b26ee23f08f820734c84fd2a4693708bb61ae2a29010001	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	\\x29e57cdebc5e8b835d63699f652b8ce7de60f68061f40cb367648d14f66136aa8fc304b4f87fa8d29ff702c01e289c2322605229a9eebfdd051f6d5610369a0a	1578955850000000	1579560650000000	1642027850000000	1673563850000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xba1054060e87ea01560f2ae9a5a09be93d004b2491952aa45317af702e984da363907db259c28f5151f21bf5c3a05b359c30b2801b0d8efa4a55a1528603afd4	\\x0080000396f3415d64aac2e83910291b556fcccb0784bf0c58b904681a2c5e4bcbcc242b5ebe489996bb49db7beee81763cb2d8468d1921861083dab7b5f84a248f0b5e6bb294786fd6eda15ab3b40b29d3ccfaaffcd3ef40ba5bb58a94c4997642d26c3e52377b67cfc7b869f3b2c0b2cd8e6d4a7d5c5f5cdb756e86bec604c04e7911f010001	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	\\x70d9f950b26840af09ff4cf671160628a810e95238bdf5478e821ff9ea55f27c7505f8233b1ccdb8d59f51567d984df46f0fb199f6058ae75a12eaf2f4014a08	1578351350000000	1578956150000000	1641423350000000	1672959350000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8e51dce35623a3c460c1a32c52c1ca8854d35bcb0c37c55081e012400dbce9d0846ea50cb4ff39290c9800b22f48696fd0b67ace427598781e7070495319bbb5	\\x00800003963d8c26cd5a4591f0ea1dacb12b27990e2b098414ae523c49088a9a98a92abc10c1615ed55d6cd8c841851395cce7a04a5ff6240b1a825395aa0c2b32d06630a55a81d10aadb2af3d021356171d68e8057c7fe9fc08581019419668bdedd412a3ac47c6f706b13958365df487cbc17d2b05349ff7e5b83812f0687b6254eb27010001	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	\\xca377a32024b11859389c377789d7e4c36816e1587456c0cda517b808eb0ede1f13ef2b614d30f13474bf4e51319b5349aed195353b03fca1804af00f58c4a0c	1579560350000000	1580165150000000	1642632350000000	1674168350000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x2177e96171e76a1815e93e402b24efbbc469e85d1db39d382fb0f551af826080eccceab6435ce4544d6bb64574771539da4faa0ef60a5f7aa1e38b5e3c002fa9	\\x00800003b7b3e72177831c6cbe819aa6c46eedebd5d9a1e5fc1d1eafa5a32e5f0d6a02350d50eefdd7a3def6956cf84851fd6a3cd5e02bc90850e3c9e9746fad0ae5dbb20b127f047cac2f1f46e43c3873ce41b2eecd49316b0d42af695a37e08e87d60c9491ae5921fb12e916a8d71013fba64e259b9bbaeb3200e4db6f128e54194a4b010001	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	\\x86cf99c6634c1807c1f745bc1a8bba117ac5717eb41f88a46863ced7c05426f2fc4cebd99fbe904846a2adf05ce578b7d5e65ce2c1490f1870d965b41c47f503	1577746850000000	1578351650000000	1640818850000000	1672354850000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x40f090cd25e77cb2d84cb6045e6b9eb6a8e5d75433348cdb6e01fe0117c65ac4aef05a86a97beed3dfe96bd465488e0f2cd2f971b661b2d3d708b5c8b6e111fa	\\x00800003f573b8dea373ab89d54f3a4bbcc1aacfa890f80c222a0a28ec3e71d680f6ac0d24cbae81f8c026a7a90e6001598873ffa9dde50497b9aaad7c0e3f2012c5d6be7af26057b200609a51310880c1c214be391fda4ccd913c0fd493e885dab742f9cc0c90320c32e4d3f2afb83eed95c9c0f7551079a17295d30ef939ce099d7bb1010001	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	\\x720992bb9b56f34cd4abbe327b73b9b84c7213a406f08a1e4f12a335ae276c13b6574a532b1b982492b264e7dedb5af6bceaec1ddfe6932d86d514f78d63a104	1580164850000000	1580769650000000	1643236850000000	1674772850000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x73ec140c73e32a45f395ee3765238e44b720e30b2966e86c7e0f54eef007d268d17fca8ba34ba1c53979d0960038904be29bdaefe55b527ae33ff18d8d1d13fd	\\x008000039ed3af0a716cb71b998bd41d8e732792bf712514242a4488ecd5071b890306a5bb582059e5440a70379e6c61e55e34b002423c60468da1f7b0cda622e296ad869377c3a00caf29fdded2183cdec83a0019777cc0eb42cdc125b77ccc8fcdfab7697946e29846e48274022862bc2fe811b64af81899ad2c83b003e6e37d2feacf010001	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	\\xf5de3939310d74ddd37df00a3a3637ace5356655ea19cc2f3bad4436e67ced2e8bc428377f8baf1bb1aac8eba2087982b8ad73c454fd190e9818a85541b8b00b	1578955850000000	1579560650000000	1642027850000000	1673563850000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x5e9c756cd0ff3ba9d2e5c8e7b73f01ee24bf5609cfbce04dc2cc011b71e949f51e745ae402ec901552aefe2026fa9637f29d2c797be4461bb6286d3e07bfb2a1	\\x00800003b8ccea209c156efe1d3d03a4052218255832e9b6d01303fb1af573c4687fd4795080fb6db73365524c038b5fe8bf5b820e532d625e295c2a6ef033bde82e36181e8923bf36799e3597f79f579e669be5bd55b6f1a1f070db8bdd47101e0139d4b672c130a8e0b883dc97b9b334a1e5d2b77f606a6dd5d3b7105451a1b2449f47010001	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	\\x4d71759a64792a0f8f8974bf2b6a253dd859649ecdbbb65e57a1b8ed00bf0d6aa86bfa30bbbe0b114b18b94edc7d9d867059cba4ac08bed3a22d318bc24dbf0f	1578351350000000	1578956150000000	1641423350000000	1672959350000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x8ae95fff942cf6fb3041f18a213a68cca39c55fdf48d5b80d861682ae60a24f275ab35935bc2f790fc4ab512cae4e7ae9c235807f3269bb9f9717504b2d9d812	\\x00800003de270414efde098fe6cbba9dcdbeacd1cdba4d2cd00657fee6c21d049cdaddd7ecce06e06201f2b001de27e8fe313538ba73a964aa6333612428f967dd04a011fc462b4591bb20686c49e1de227ef45e3f563458312ba0089464115c602135b8bcf12d85a823feecdaa8ed95e57ff06402fffb843d18c654e012dbf95d3198d1010001	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	\\x48aaceaf7c1b49fe17a682351dc30c26b93cffbb59e3aa1f82c4cee31d77a527fceae1e4431244986bcba2a2d271924a020d0d291f90fc8b02234a0b974e2d09	1579560350000000	1580165150000000	1642632350000000	1674168350000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x342a53036140a9d41d0d3545d085b4a7e5844982090166231e639a7c773ea72d7ce730ee78d08cb62f7c4b772747abf0621dc6f2de90544337f545e11e000970	\\x00800003aada4d33f2518f18ffa04de42ea02bc60ad9f08d6c98cb536602b639ac10cf549ab17cee7bc8299a6a5bae3464ef2e5585a5e3ddb0519f9bd9b654517e5a8338d94a9ac54603f77ff9fc89a9c22635a8e96e70e8b275270ded2a4dd2e3f754d32c9d6c449d924840158c08473f33a9df175fc83642fc2e37d262f52b550e2f61010001	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	\\xf022ad44fae55172d83d976f1418e2a56fafd8e4be35004099b1fde184ea8ec656f0e5cca82cc89542ddf574b9ad1e26120478d4863594c9235afaec11960505	1577746850000000	1578351650000000	1640818850000000	1672354850000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x31c86f8596818a63c217df16ea5efd31e0e45427f2066be6bdf27ff90d057e8ca4d80055ea20fd4b63b682d03022dabda1ff38a38f2e814b6297efb685d88e55	\\x00800003a29c979e067bd9a1c6076a18d777688b2e3d58fed49534b8c6f534e30c71d8992331bfcb379264151d5a47dbbb69cf59235e3bcb0b647207aacca0f7074f002bba0420f6fe425b1311c97f65a84acb7fb9eb2f169016d77192ffee8fb93043e899d9cc39f89856b6982f6e706078842b3e3ba92eac32e161a52d2e11f997b55b010001	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	\\xb0d5c91994e0a22d48cbfb1be01ec58e7c8987b5763ef11648c887b59f44115668651e2aa4edeaed64a1bf7ddc07353fde9819ea574df571ecbc7700c05dab0e	1580164850000000	1580769650000000	1643236850000000	1674772850000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x502f40e31f1c0d1cc84d3c511d459788debf9f68998e87f4378cba336f817a033add0a70a7ed80c23bcd3b0efc5cd1d62ca99b86f6da45d8b2ba2cbcfd5b82f3	\\x00800003e02b11637571245676498d7ee900edb9fb95b76b1561b7cc6873e9529635b212e2ee7509c9f3570b8cb55afe95d95fb67359ae1c9a48e9177d61b4d798e5aa415b31c2c54bd0e1213db91b66836df5e7f302df0c62b9f61a6058248f6cb4da914e3ae13e925cd17bafe3ec312be7c44883f1dae2d6ff74fe70c13a29b4ec46e3010001	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	\\xff3f1c13c6742aa9aea0ce5f74df3fbd35648d9ac8d9338b48b0d5ce3dca9ee225811eeba4e8e9a6a6e68f3ae2330540686703217769eda3173774a0de798d08	1578955850000000	1579560650000000	1642027850000000	1673563850000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xf4a2325986f4d4d0191acaa4d6b219dd9c93c4240d92435b4f548b634d6a619f95d5ef39462fa9d3681c9317b8fa3a23dde88e60a80b4fd7bb6f1274cee3bbfc	\\x00800003b24393c3bafaf6bc2ff2f1ec9205711d4acb777e5b4d951fa77f6039bf8e4697b1f7b00d3602acafffd23764a7949ed777ee58a81e0f061c32044d9e8f0466c4cecf2b4a51ea6eae16827df50b9c3983172e4c1a918f6f4bbbf5de316eb08f03874b2941feb1d1cdd41d857508b554b6dc359fe1395610620575d851bac02b25010001	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	\\x1209efd0bdd250e5f9f5fc4dda68dabfeeec041eb35786a74f420fe64a292771604e4eb7c6edce2bab362ee0af0f7ce8056c7b40b170465e16d04bbc102e6307	1578351350000000	1578956150000000	1641423350000000	1672959350000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x3f879e1c1122adbbfde6cc3d5bd97588cc99c74928fccdfc95759d2a6dd9a855a1b37b4f1334b3026fde1e7f8bc950ff53690abf961cd19aefe1a230a6c35280	\\x00800003e8a928cb02283aaf8f41c679563652c700d8dd9adf5338d2c248288d2aa7d1e2cc9b731976a56534e76be27dd5d4c86c44a59b9753c83017badd3a256dc5552e742ce0e4083cde8e7c468653256171391a786d628937452c8d6ce38dbffed66c87592500efecde01d0b2f89bb2f11730ff5e429c241df89b2b1fc5c57911b011010001	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	\\xad441214cb12b4e1dabc2e57596f73f246fb9ead579500a74619ff030f81a2cc40bdef24c9f87ba868d5759e97b6078b0a9f9fc4a4f9d1c7e16457937f8da00b	1579560350000000	1580165150000000	1642632350000000	1674168350000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x08ec5aeff83b85fd101ea725f92d3fbf0ab406ec626399bd388be186fc8f637ab0647cd3bad70a79c9e62cd3658f14b46f1b59d741b853e4ce260b4170299639	\\x00800003b588fca275a5e068b51666d13a46edda5320b6ab7cd97fca18080e82ca95d730172c92d90667398c09507109d356117363e05fe2df10a7ba05b252af1c570853b0ee88cac5d0765a7c1a24089024b2997dab5ca23a5d1a0bfd430d0de11c9d3386ad449705e44dfbf470848d2b70021146ec6c8693eeb826b9c3df89a0ab041d010001	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	\\x5fbb977590bdadef5e62a9da84777467450769165d1fa386bde9aa7349783b5ec512171ba05c28d7b118f7aa1211f9e10fa624f293d8121895ce52d44facab0b	1577746850000000	1578351650000000	1640818850000000	1672354850000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x58f92e7ab60f38715a9b7e1ee71af82d186de74c7cd225ebaf600e0d73b6dc3d15062cb69e278f6329aca4e1feedef663e1472c8c6759438af9f4a4f6264df61	\\x008000039e78fe5464534c7f509a50aceeda85a9b8268bd79ba98476d5b83100267f0bfd184479fbb6bd18145ffac6421ca48bdae416c5c60b161f957d55ad895590f8ec07ff5c5de6c4dd930c57a2aa51626b47bda8fb7065300ff51b9f69c0fd0da324fe452196d5370ff0e10e36b0d6c597e03d59fcda3582b5dbbb448ca90482ce5b010001	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	\\x45416937576effe3d3a3d6079aa0af11604d88746e2f4a4925b0f20b2c948c91791a4c77c6307334138ef5e964e63f93b7b36d3fa64f25dea2c0b350bbdd730e	1580164850000000	1580769650000000	1643236850000000	1674772850000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x467be65e8795048bb583e79ef3a51bad04922301247a0d8031b0ec4f86d1ccc2d50772c57a08bdba0e9764da32670cac88a690561d9c9b7dbf1d4d444e8f62e5	\\x00800003dbc9e6edd7907f48357d94a81748169f14ae3e3c9a50cc4432f14f27784bd5952bd62b107d3ab3f6c2fa10dd16a529abca41ce31dcf8e6a356e9b56c7c4b33a820d01dfc538da9eedfd3c6fe8adc562e5307a51145647abd776396884b09688e234ea2a5bdeb94b9de250194cadba8de9da3dc1592539f11faf85e25d4b2cdf1010001	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	\\x1e28c8a3726db133224696696c405533a36e87514211c9f30eb10fb644445ef98307a6e078edd407a1019d78ab18e7bdbc87cbb35143cdff9563b6e6140a1304	1578955850000000	1579560650000000	1642027850000000	1673563850000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xd263d28c9f1c6353d8e4c1f7bc79043970575bef796e273799a4e66a1fa512635a31c26abb2cd71e5972979a8d704636cf72dde05d3a1e0bf120f42637c9715d	\\x00800003c95f37ea2143bd2aefdeb83174eef50e2e565c084d1106740a952133663ade5eae9cbacd438815d3b8a96dd66f79ed855b63729b8dae501f1ad6bb7336c1aedb64a325771fd795812a39bae01074f463000da74ae1b8420b05db45fc4743686e60f461bcfe89a233616d4df78df77e2b289cb5e969f014f8d7d5da9e4f45ee53010001	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	\\x1b6b17b556a09a6b04ab4b87938fcefe4492a15367467b3484442b7273f13577c66219edc2e9a30b874899139526193442ec2ec83582c367ec0f4341aa858105	1578351350000000	1578956150000000	1641423350000000	1672959350000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x0320d4e9a413672188a047564e6eb030366a96b27d0bdfa33de78bd654e919b4f963d9ca719c177f27c2215f2c2095d4e9302453b565fd4d1485c99b9a75f8fe	\\x00800003ec6dd1b8a123b95e3030255d9bf944533cecf0da8d498b2a59ac4c05579f8218d235519f2ff6dd5a8f2b2e524ca8098ee664d50489ccd953c61e1109bddb7d6a20eaea0e73c8a365557b740c9dec74d83d11d964d5b9bb7d58b523a92ab022be06afba71f82c1f2359c52bcffb405ed134309fcb4a60d3ba1444eb99f53d76d3010001	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	\\xbe263d0eb1015fc2f07d88cd88a40678ae7c6f9ffc8f5ef113bb124f5c48f5eb16b1f1faad288901005110e5da1f4bf9163da4e4790fc3b3523bb56bf5558a0a	1579560350000000	1580165150000000	1642632350000000	1674168350000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x389763909f6bea58332dc5adb5b4963b696f31e496b7e60759c8b18a0214cf9ecd61aeaecebf30f713847533ab37865f46b0fd23c14587403c8dec2bad071c4a	\\x00800003dfc37ab2a10be25f5f8c258de5f511df18c38cd4e3262bbd1a2359c2dfcbd8ea33f1d063a5d0cc9223ad58bd8d15e4eaba91d54127bde193053657aab2018329b67aca58979fa8ba7da332de477eba8f2dddd60662d4ef843a414a22f6c8417a5bd19c4b408d6a9d4bbfbbc907ed19fa83d784efa45d51c3ddb9aa0250a7514d010001	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	\\x244035d5b706fcaf516c048785165bd87ed1b4333318db428aa4d068bc34e53bcb139011a08dbd1228e26e8bca09041284aff8712009ed70f75187a9bb6db806	1577746850000000	1578351650000000	1640818850000000	1672354850000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x54e24fe87ee27a97677b0e3f66d98fc00e81df1776a0823e50bf46ebd40c90d5c855ceeffe79a5bdbf045b7afee6929ff9689f190560a28ab2fea97510f8d8bc	\\x00800003cc6dcb2ae9d823394577dcc6bc268b5586961cf21bfe72d1c74eadfa93f3e60f4882e938937d22ccda31602281fab5e3815ae7688187ada73d7893fb0b4bd2ad45bf837c65733179efb19ac74fe7af4d26d503bd31ab05ab59c77b81a4d450c12a8f018d4e5eaa847b1257597512ca88d10a91ce15b34df131a707398babb6df010001	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	\\x7ac97bed95e5cb916ca5a8f7f54753cc97820414a5936a39e97d70832696d3ed983485929d6a214217c507072f6e7d49fd6652781828923e54b3989c61a15e02	1580164850000000	1580769650000000	1643236850000000	1674772850000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x02608a5addf121abb77c6175da4ab6b64333f66826aa2056902cbd2d5c0e98dbf5d138a306a9cbca6980b08e6002e2ea471d77f86da30ebbaf0ac5fb15d4fa8d	\\x00800003abb64b863aa4fed76899ed308accfb6189fb27bc12c2f62c9037893138b4224f0dd3e12844c401e9f6587d101b7cda9e165e80ceed8f7a5c9f5a933b295e1cbaeacbaf86858ad860fcf7a2b359603208f14929a79c9d2f20517a9bb4bd782ea0381462f398356ac2cae7fd5e831a65a1c92abdcdc05a32ccb34ddc0cbd5baf2b010001	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	\\xb6247f900a8042b92a78e19f8f6b4fd8cdf66e14ed1476e294daa5bd2b47cd674585bcfeb7ea72d79374e791e812efe9a97a5f6ae5ea655192d36aca8b3bbb05	1578955850000000	1579560650000000	1642027850000000	1673563850000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xe85f1557b625713cac97f3423b20b077f82203a08645def977189cae0aba336546fb93137c76dd76605eb858c86c6098c31d38365a457853f7e2dfcf62f8090c	\\x00800003d8ecc8fe70a08c92cd4e1daf8d8d477f8638244448e7a08e42fb4472b3ad9b09344a2c397c79d9fd4194edb882d10d507c8c59664b0cbe56b18c1d5fda9f93f96c9e4e0cc3fc2094b43f7f2719299f33305a1b5a6085d00af46776a0c10deab5c654e053579edd3e76bf6639a7945f819806b2d174e14e1a4b46672b47a2a91f010001	\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	\\xfd9860ab1712f6446060b1ea74ddc88fc70077fbbbda50f37474230d3bb9c02a0ba42bf63122a72d9e3690228f5a862a8c0f3c745516d0d3f601dce11ee9620a	1578351350000000	1578956150000000	1641423350000000	1672959350000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_wire, "timestamp", refund_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	1	\\x04bc8bbf1257210c74bf65b8fa7ca1c88577a43f06528202a909ecebc79108b53bec1cda1aedd914f192641c3c63c27cf9271697e1e9e36c6e1efa2408686412	\\xb231cf9982bdd9a3eaff0b793547611667e7cfd411d8535a23da5f637c6f885c140e250cd70bd11bed99fdbb4b63857239bddcf111ca21b4204184ece72903ab	1577746866000000	1577747766000000	0	9000000	\\x13912d7751affc49f63424f6c3ff4d238fc4963b15e05ecbfb170a59647aeac2	\\xd6fefeed0ccb548532af508ed3cb08440002531b9959282caf975269eb592b54	\\x551e7d4478be8293eaed37119d0dc73d6e081076ffc665d6664c007ba4454ce6d5af9682ec9c6366020ca0fb656aff83fdd03375db2c1ae03d2b72f694d7c001	\\x230848bbd97087c56e78e231a14c96bdcc369aacf4a77302054125ea91e83eb9	\\x16e5be89117f000000000000000000002e56b38901000000e0a51d87117f00007088260f95550000890d0068117f00000a0d0068117f0000f00c0068117f0000
\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	2	\\x04bc8bbf1257210c74bf65b8fa7ca1c88577a43f06528202a909ecebc79108b53bec1cda1aedd914f192641c3c63c27cf9271697e1e9e36c6e1efa2408686412	\\xb231cf9982bdd9a3eaff0b793547611667e7cfd411d8535a23da5f637c6f885c140e250cd70bd11bed99fdbb4b63857239bddcf111ca21b4204184ece72903ab	1577746866000000	1577747766000000	0	98000000	\\x9a456eca16dfcb980fd9700266de80c4fe95b4ad662266946bdd380266d15f32	\\xd6fefeed0ccb548532af508ed3cb08440002531b9959282caf975269eb592b54	\\x7e497af8cb1b3cf4d8938ef838cbbc639488ce1fbcbc34d86072cde95a6877c947ee24c4d751b9abc0a244c5fba326c633fb6dad6cfffa059c28262dc9845d09	\\x230848bbd97087c56e78e231a14c96bdcc369aacf4a77302054125ea91e83eb9	\\x16e5be89117f000000000000000000002e56b38901000000e085ff24117f00007088260f95550000890d00fc107f00000a0d00fc107f0000f00c00fc107f0000
\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	3	\\x04bc8bbf1257210c74bf65b8fa7ca1c88577a43f06528202a909ecebc79108b53bec1cda1aedd914f192641c3c63c27cf9271697e1e9e36c6e1efa2408686412	\\xb231cf9982bdd9a3eaff0b793547611667e7cfd411d8535a23da5f637c6f885c140e250cd70bd11bed99fdbb4b63857239bddcf111ca21b4204184ece72903ab	1577746866000000	1577747766000000	0	9000000	\\x43790d896a7051c91e985846d5a92b2fad7fb1588203fb5a1cbcd28f21852b45	\\xd6fefeed0ccb548532af508ed3cb08440002531b9959282caf975269eb592b54	\\xf0ab0cc5d7ab9118fdd66ec4360da99011c6a37aff9369cc3ddf137f96f576dbb268e9600c183cec77bed501be7786081bf40fe8602b7bb89ab83a37ba170506	\\x230848bbd97087c56e78e231a14c96bdcc369aacf4a77302054125ea91e83eb9	\\x16e5be89117f000000000000000000002e56b38901000000e0b59d87117f00007088260f95550000890d0078117f00000a0d0078117f0000f00c0078117f0000
\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	4	\\x04bc8bbf1257210c74bf65b8fa7ca1c88577a43f06528202a909ecebc79108b53bec1cda1aedd914f192641c3c63c27cf9271697e1e9e36c6e1efa2408686412	\\xb231cf9982bdd9a3eaff0b793547611667e7cfd411d8535a23da5f637c6f885c140e250cd70bd11bed99fdbb4b63857239bddcf111ca21b4204184ece72903ab	1577746866000000	1577747766000000	0	9000000	\\xf7d8a74f5c49e40f169cb7d4a677de71d20150a19169f68974c3095052f2f1c6	\\xd6fefeed0ccb548532af508ed3cb08440002531b9959282caf975269eb592b54	\\x68fa2b139cc2b6bcd7d131f0378feb88a71ca2a267a2e24c1b581299b9594ace1125d4cabf5e2861a28632a4629fd027c431e64f1fe4a6e6d4f5e1202daa230c	\\x230848bbd97087c56e78e231a14c96bdcc369aacf4a77302054125ea91e83eb9	\\x16e5be89117f000000000000000000002e56b38901000000e0559d84117f00007088260f95550000890d0054117f00000a0d0054117f0000f00c0054117f0000
\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	5	\\x04bc8bbf1257210c74bf65b8fa7ca1c88577a43f06528202a909ecebc79108b53bec1cda1aedd914f192641c3c63c27cf9271697e1e9e36c6e1efa2408686412	\\xb231cf9982bdd9a3eaff0b793547611667e7cfd411d8535a23da5f637c6f885c140e250cd70bd11bed99fdbb4b63857239bddcf111ca21b4204184ece72903ab	1577746866000000	1577747766000000	0	9000000	\\xf8ae32ecb8d01222403852d6774ade7335ef7505360f7ce953cdebe8237286b7	\\xd6fefeed0ccb548532af508ed3cb08440002531b9959282caf975269eb592b54	\\x7d4dc7a50e4a7b8795509a460a17396c8453dfeefae05e37a0b8c5ea99077f094caaf5e5a62259d0ccf6524564e97e3ad884715b7b5d302c344aaa1fd7f71809	\\x230848bbd97087c56e78e231a14c96bdcc369aacf4a77302054125ea91e83eb9	\\x16e5be89117f000000000000000000002e56b38901000000e0d57f43117f00007088260f95550000890d0038117f00000a0d0038117f0000f00c0038117f0000
\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	6	\\x04bc8bbf1257210c74bf65b8fa7ca1c88577a43f06528202a909ecebc79108b53bec1cda1aedd914f192641c3c63c27cf9271697e1e9e36c6e1efa2408686412	\\xb231cf9982bdd9a3eaff0b793547611667e7cfd411d8535a23da5f637c6f885c140e250cd70bd11bed99fdbb4b63857239bddcf111ca21b4204184ece72903ab	1577746866000000	1577747766000000	0	9000000	\\xfab41b8f820fea7547fba7bd4ff03f566adc98958ffaa51644ec436eb10904ca	\\xd6fefeed0ccb548532af508ed3cb08440002531b9959282caf975269eb592b54	\\x46076ca444041c60ec9dafd28fde7588867351debf61a0f12ec772b698b4079139b005811055cc6724947ff1d6c9d793f672b214ad796467611b3ca3e0e44807	\\x230848bbd97087c56e78e231a14c96bdcc369aacf4a77302054125ea91e83eb9	\\x16e5be89117f000000000000000000002e56b38901000000e0957f41117f00007088260f95550000890d0020117f00000a0d0020117f0000f00c0020117f0000
\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	7	\\x04bc8bbf1257210c74bf65b8fa7ca1c88577a43f06528202a909ecebc79108b53bec1cda1aedd914f192641c3c63c27cf9271697e1e9e36c6e1efa2408686412	\\xb231cf9982bdd9a3eaff0b793547611667e7cfd411d8535a23da5f637c6f885c140e250cd70bd11bed99fdbb4b63857239bddcf111ca21b4204184ece72903ab	1577746866000000	1577747766000000	2	20000000	\\x8284c0f3a2dc31ab209dc2259960a179e63fb5b4ebebb325fe181252b455783a	\\xd6fefeed0ccb548532af508ed3cb08440002531b9959282caf975269eb592b54	\\x8398733e6c866eec6f355aac3152ed88c0fd624943546ea9eae4d9e8daa24e0d91e593845053c60999a1bd403243e53f0f564b2a6ec68b8b0bd8fc8bbb87910f	\\x230848bbd97087c56e78e231a14c96bdcc369aacf4a77302054125ea91e83eb9	\\x16e5be89117f000000000000000000002e56b38901000000e0c5ff26117f00007088260f95550000f9a4000c117f00007aa4000c117f000060a4000c117f0000
\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	8	\\x04bc8bbf1257210c74bf65b8fa7ca1c88577a43f06528202a909ecebc79108b53bec1cda1aedd914f192641c3c63c27cf9271697e1e9e36c6e1efa2408686412	\\xb231cf9982bdd9a3eaff0b793547611667e7cfd411d8535a23da5f637c6f885c140e250cd70bd11bed99fdbb4b63857239bddcf111ca21b4204184ece72903ab	1577746866000000	1577747766000000	0	9000000	\\xf50200a526d75117228109cae5ee2159c77446276fd339bfaf91b82015b7f5b0	\\xd6fefeed0ccb548532af508ed3cb08440002531b9959282caf975269eb592b54	\\x669bc2e0fab9b47cc94c0d2dfa9bc96b8cd4a99ee459a919a22d080b60d6bda35a01ddfecf35a192a644c8e971a43211329a337d2dfd9f6a1a0fc3b993362209	\\x230848bbd97087c56e78e231a14c96bdcc369aacf4a77302054125ea91e83eb9	\\x16e5be89117f000000000000000000002e56b38901000000e0e5ff27117f00007088260f95550000890d0014117f00000a0d0014117f0000f00c0014117f0000
\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	9	\\x04bc8bbf1257210c74bf65b8fa7ca1c88577a43f06528202a909ecebc79108b53bec1cda1aedd914f192641c3c63c27cf9271697e1e9e36c6e1efa2408686412	\\xb231cf9982bdd9a3eaff0b793547611667e7cfd411d8535a23da5f637c6f885c140e250cd70bd11bed99fdbb4b63857239bddcf111ca21b4204184ece72903ab	1577746866000000	1577747766000000	0	9000000	\\xbdfa6d3cc52ea4a2889702b409f4ce24e3057257f45685a0b229790bda260345	\\xd6fefeed0ccb548532af508ed3cb08440002531b9959282caf975269eb592b54	\\xa205c7f3611710d0189527b23a5125e3b16011431a3168febdc730326b6d2d5f0e5900b74e25e7e19e1a02a47e59230105ac5a8e1a62f9771d69776d2b6b390f	\\x230848bbd97087c56e78e231a14c96bdcc369aacf4a77302054125ea91e83eb9	\\x16e5be89117f000000000000000000002e56b38901000000e0e5ff7f117f00007088260f95550000890d0074117f00000a0d0074117f0000f00c0074117f0000
\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	10	\\x04bc8bbf1257210c74bf65b8fa7ca1c88577a43f06528202a909ecebc79108b53bec1cda1aedd914f192641c3c63c27cf9271697e1e9e36c6e1efa2408686412	\\xb231cf9982bdd9a3eaff0b793547611667e7cfd411d8535a23da5f637c6f885c140e250cd70bd11bed99fdbb4b63857239bddcf111ca21b4204184ece72903ab	1577746866000000	1577747766000000	0	9000000	\\xc4438879b5588c7979adb65117bc310ef44eaae7ecdbd44c725853d91713ef29	\\xd6fefeed0ccb548532af508ed3cb08440002531b9959282caf975269eb592b54	\\x856a1bccb9257b39b92ac1ad829423a2856689cb4c67e0e98d413a5406164bc8d362fe261700578c937bb9701acccdb1c36b3a7b1a2ed610c1701d4bfa92240d	\\x230848bbd97087c56e78e231a14c96bdcc369aacf4a77302054125ea91e83eb9	\\x16e5be89117f000000000000000000002e56b38901000000e0e5ff03117f00007088260f95550000890d00f4107f00000a0d00f4107f0000f00c00f4107f0000
\.


--
-- Data for Name: deposits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits (deposit_serial_id, coin_pub, amount_with_fee_val, amount_with_fee_frac, "timestamp", refund_deadline, wire_deadline, merchant_pub, h_contract_terms, h_wire, coin_sig, wire, tiny, done) FROM stdin;
1	\\x13912d7751affc49f63424f6c3ff4d238fc4963b15e05ecbfb170a59647aeac2	0	10000000	1577746866000000	1577747766000000	1577747766000000	\\xd6fefeed0ccb548532af508ed3cb08440002531b9959282caf975269eb592b54	\\x04bc8bbf1257210c74bf65b8fa7ca1c88577a43f06528202a909ecebc79108b53bec1cda1aedd914f192641c3c63c27cf9271697e1e9e36c6e1efa2408686412	\\xb231cf9982bdd9a3eaff0b793547611667e7cfd411d8535a23da5f637c6f885c140e250cd70bd11bed99fdbb4b63857239bddcf111ca21b4204184ece72903ab	\\x9f156a59d72e2158f3f15655453e065214e8e87fde601fe14b745797c242545fefbed3a3fa1cd8bdd42f43039870923be3a313be49015f9c78d8c17d48816f01	{"url":"payto://x-taler-bank/localhost/42","salt":"3C43HM58XZ6AWPEZQZ6QYJ9W972S4B42S5DDEGGN6PMQWYGJ7TBZA14GBSJ2B2TDQSEX332AQ0MRVEDE6JXT995XN4SZJDXJYAB0C58"}	f	f
2	\\xbdfa6d3cc52ea4a2889702b409f4ce24e3057257f45685a0b229790bda260345	0	10000000	1577746866000000	1577747766000000	1577747766000000	\\xd6fefeed0ccb548532af508ed3cb08440002531b9959282caf975269eb592b54	\\x04bc8bbf1257210c74bf65b8fa7ca1c88577a43f06528202a909ecebc79108b53bec1cda1aedd914f192641c3c63c27cf9271697e1e9e36c6e1efa2408686412	\\xb231cf9982bdd9a3eaff0b793547611667e7cfd411d8535a23da5f637c6f885c140e250cd70bd11bed99fdbb4b63857239bddcf111ca21b4204184ece72903ab	\\x48ba450e90403e54941d6cc55b6bd333a2579909626104276a48ce4e2e268d107c129b98001d5113102f0d012564bcfd1c10adcd80f507a46b320eefff3bc004	{"url":"payto://x-taler-bank/localhost/42","salt":"3C43HM58XZ6AWPEZQZ6QYJ9W972S4B42S5DDEGGN6PMQWYGJ7TBZA14GBSJ2B2TDQSEX332AQ0MRVEDE6JXT995XN4SZJDXJYAB0C58"}	f	f
3	\\x9a456eca16dfcb980fd9700266de80c4fe95b4ad662266946bdd380266d15f32	1	0	1577746866000000	1577747766000000	1577747766000000	\\xd6fefeed0ccb548532af508ed3cb08440002531b9959282caf975269eb592b54	\\x04bc8bbf1257210c74bf65b8fa7ca1c88577a43f06528202a909ecebc79108b53bec1cda1aedd914f192641c3c63c27cf9271697e1e9e36c6e1efa2408686412	\\xb231cf9982bdd9a3eaff0b793547611667e7cfd411d8535a23da5f637c6f885c140e250cd70bd11bed99fdbb4b63857239bddcf111ca21b4204184ece72903ab	\\x7382fd173cc946103319d0aa99a33c9a75c3fb72c9465b62561132056a11f8ed3a518227c5b42671ab14f493936b590431d8b2d5e73621f03186353e580ec007	{"url":"payto://x-taler-bank/localhost/42","salt":"3C43HM58XZ6AWPEZQZ6QYJ9W972S4B42S5DDEGGN6PMQWYGJ7TBZA14GBSJ2B2TDQSEX332AQ0MRVEDE6JXT995XN4SZJDXJYAB0C58"}	f	f
4	\\xf8ae32ecb8d01222403852d6774ade7335ef7505360f7ce953cdebe8237286b7	0	10000000	1577746866000000	1577747766000000	1577747766000000	\\xd6fefeed0ccb548532af508ed3cb08440002531b9959282caf975269eb592b54	\\x04bc8bbf1257210c74bf65b8fa7ca1c88577a43f06528202a909ecebc79108b53bec1cda1aedd914f192641c3c63c27cf9271697e1e9e36c6e1efa2408686412	\\xb231cf9982bdd9a3eaff0b793547611667e7cfd411d8535a23da5f637c6f885c140e250cd70bd11bed99fdbb4b63857239bddcf111ca21b4204184ece72903ab	\\x5775c7bc45c1f0fece0ae363bcef2eb4c0addc84f4b6ea6db206dc1c35e463a8a243295fc1cf1872efa554b5636db13df2f69bcfde52f8747ad3728c37d44e00	{"url":"payto://x-taler-bank/localhost/42","salt":"3C43HM58XZ6AWPEZQZ6QYJ9W972S4B42S5DDEGGN6PMQWYGJ7TBZA14GBSJ2B2TDQSEX332AQ0MRVEDE6JXT995XN4SZJDXJYAB0C58"}	f	f
5	\\xfab41b8f820fea7547fba7bd4ff03f566adc98958ffaa51644ec436eb10904ca	0	10000000	1577746866000000	1577747766000000	1577747766000000	\\xd6fefeed0ccb548532af508ed3cb08440002531b9959282caf975269eb592b54	\\x04bc8bbf1257210c74bf65b8fa7ca1c88577a43f06528202a909ecebc79108b53bec1cda1aedd914f192641c3c63c27cf9271697e1e9e36c6e1efa2408686412	\\xb231cf9982bdd9a3eaff0b793547611667e7cfd411d8535a23da5f637c6f885c140e250cd70bd11bed99fdbb4b63857239bddcf111ca21b4204184ece72903ab	\\x419afd1edc6438e8e2342ae6400a75efa185bcc0559b5409356fe0d12758867005a7afeff5b17f775e2e5889625c5d3ff55dd9e0826bac128b26f0c1d0da1809	{"url":"payto://x-taler-bank/localhost/42","salt":"3C43HM58XZ6AWPEZQZ6QYJ9W972S4B42S5DDEGGN6PMQWYGJ7TBZA14GBSJ2B2TDQSEX332AQ0MRVEDE6JXT995XN4SZJDXJYAB0C58"}	f	f
6	\\xf7d8a74f5c49e40f169cb7d4a677de71d20150a19169f68974c3095052f2f1c6	0	10000000	1577746866000000	1577747766000000	1577747766000000	\\xd6fefeed0ccb548532af508ed3cb08440002531b9959282caf975269eb592b54	\\x04bc8bbf1257210c74bf65b8fa7ca1c88577a43f06528202a909ecebc79108b53bec1cda1aedd914f192641c3c63c27cf9271697e1e9e36c6e1efa2408686412	\\xb231cf9982bdd9a3eaff0b793547611667e7cfd411d8535a23da5f637c6f885c140e250cd70bd11bed99fdbb4b63857239bddcf111ca21b4204184ece72903ab	\\x28d8b29602fe403b34a3360480379c518e8bf32d9cc9ce38db9d7f738b953b001c93267746009e49f5850ff047e3ec4e0da63cbac4fb0ec58a945e6e759b5006	{"url":"payto://x-taler-bank/localhost/42","salt":"3C43HM58XZ6AWPEZQZ6QYJ9W972S4B42S5DDEGGN6PMQWYGJ7TBZA14GBSJ2B2TDQSEX332AQ0MRVEDE6JXT995XN4SZJDXJYAB0C58"}	f	f
7	\\xc4438879b5588c7979adb65117bc310ef44eaae7ecdbd44c725853d91713ef29	0	10000000	1577746866000000	1577747766000000	1577747766000000	\\xd6fefeed0ccb548532af508ed3cb08440002531b9959282caf975269eb592b54	\\x04bc8bbf1257210c74bf65b8fa7ca1c88577a43f06528202a909ecebc79108b53bec1cda1aedd914f192641c3c63c27cf9271697e1e9e36c6e1efa2408686412	\\xb231cf9982bdd9a3eaff0b793547611667e7cfd411d8535a23da5f637c6f885c140e250cd70bd11bed99fdbb4b63857239bddcf111ca21b4204184ece72903ab	\\x36ad51336a70fbab6bbbff6414979077f042b0c6c704e093a03c4f4f3ca8862d5bf95288e31a08e68711aa64bfd2d814a56c72d71134c2333602502acc788402	{"url":"payto://x-taler-bank/localhost/42","salt":"3C43HM58XZ6AWPEZQZ6QYJ9W972S4B42S5DDEGGN6PMQWYGJ7TBZA14GBSJ2B2TDQSEX332AQ0MRVEDE6JXT995XN4SZJDXJYAB0C58"}	f	f
8	\\x8284c0f3a2dc31ab209dc2259960a179e63fb5b4ebebb325fe181252b455783a	2	22000000	1577746866000000	1577747766000000	1577747766000000	\\xd6fefeed0ccb548532af508ed3cb08440002531b9959282caf975269eb592b54	\\x04bc8bbf1257210c74bf65b8fa7ca1c88577a43f06528202a909ecebc79108b53bec1cda1aedd914f192641c3c63c27cf9271697e1e9e36c6e1efa2408686412	\\xb231cf9982bdd9a3eaff0b793547611667e7cfd411d8535a23da5f637c6f885c140e250cd70bd11bed99fdbb4b63857239bddcf111ca21b4204184ece72903ab	\\xa719f73961e3373f83f0dbaa460ec0c040be33400b2a09898e5c7255fe0614426ba0c9d085349f129ca83e6f4c003d15e9f7b6c9b7c4e499fc84b8d06e1f2a0b	{"url":"payto://x-taler-bank/localhost/42","salt":"3C43HM58XZ6AWPEZQZ6QYJ9W972S4B42S5DDEGGN6PMQWYGJ7TBZA14GBSJ2B2TDQSEX332AQ0MRVEDE6JXT995XN4SZJDXJYAB0C58"}	f	f
9	\\x43790d896a7051c91e985846d5a92b2fad7fb1588203fb5a1cbcd28f21852b45	0	10000000	1577746866000000	1577747766000000	1577747766000000	\\xd6fefeed0ccb548532af508ed3cb08440002531b9959282caf975269eb592b54	\\x04bc8bbf1257210c74bf65b8fa7ca1c88577a43f06528202a909ecebc79108b53bec1cda1aedd914f192641c3c63c27cf9271697e1e9e36c6e1efa2408686412	\\xb231cf9982bdd9a3eaff0b793547611667e7cfd411d8535a23da5f637c6f885c140e250cd70bd11bed99fdbb4b63857239bddcf111ca21b4204184ece72903ab	\\x588e7871e516ba1b562cfd980e32e600355224442afd65923c962cf4fcd0578ee0d554477733bce121db090dc50fd540638b6c992c15c6dcf49892962ed47308	{"url":"payto://x-taler-bank/localhost/42","salt":"3C43HM58XZ6AWPEZQZ6QYJ9W972S4B42S5DDEGGN6PMQWYGJ7TBZA14GBSJ2B2TDQSEX332AQ0MRVEDE6JXT995XN4SZJDXJYAB0C58"}	f	f
10	\\xf50200a526d75117228109cae5ee2159c77446276fd339bfaf91b82015b7f5b0	0	10000000	1577746866000000	1577747766000000	1577747766000000	\\xd6fefeed0ccb548532af508ed3cb08440002531b9959282caf975269eb592b54	\\x04bc8bbf1257210c74bf65b8fa7ca1c88577a43f06528202a909ecebc79108b53bec1cda1aedd914f192641c3c63c27cf9271697e1e9e36c6e1efa2408686412	\\xb231cf9982bdd9a3eaff0b793547611667e7cfd411d8535a23da5f637c6f885c140e250cd70bd11bed99fdbb4b63857239bddcf111ca21b4204184ece72903ab	\\x0b162c711605b95b864943350d756b22daab885135d328f567cc7f6ba48de0afa309a00d19b00125edc2afabdbe8985dc78ec07023817c4f0002077b9711fa01	{"url":"payto://x-taler-bank/localhost/42","salt":"3C43HM58XZ6AWPEZQZ6QYJ9W972S4B42S5DDEGGN6PMQWYGJ7TBZA14GBSJ2B2TDQSEX332AQ0MRVEDE6JXT995XN4SZJDXJYAB0C58"}	f	f
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
1	contenttypes	0001_initial	2019-12-31 00:01:01.763354+01
2	auth	0001_initial	2019-12-31 00:01:01.786737+01
3	app	0001_initial	2019-12-31 00:01:01.826124+01
4	contenttypes	0002_remove_content_type_name	2019-12-31 00:01:01.846115+01
5	auth	0002_alter_permission_name_max_length	2019-12-31 00:01:01.849094+01
6	auth	0003_alter_user_email_max_length	2019-12-31 00:01:01.855008+01
7	auth	0004_alter_user_username_opts	2019-12-31 00:01:01.861663+01
8	auth	0005_alter_user_last_login_null	2019-12-31 00:01:01.868316+01
9	auth	0006_require_contenttypes_0002	2019-12-31 00:01:01.869635+01
10	auth	0007_alter_validators_add_error_messages	2019-12-31 00:01:01.875028+01
11	auth	0008_alter_user_username_max_length	2019-12-31 00:01:01.882756+01
12	auth	0009_alter_user_last_name_max_length	2019-12-31 00:01:01.891442+01
13	auth	0010_alter_group_name_max_length	2019-12-31 00:01:01.89815+01
14	auth	0011_update_proxy_permissions	2019-12-31 00:01:01.904471+01
15	sessions	0001_initial	2019-12-31 00:01:01.9084+01
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
\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1546297200000000	1577833200000000	\\x7faf99fe676ed990d74c1108afe587bb189cdc0681b1a5425d0461eb02b708c6745f5ff4ef9722103e628e1fe0d054098448e42f8229b7eafa43b81d41213e01
\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1577833200000000	1609455600000000	\\xb8a3545e579c9df51ebbcbaef18831831164ddfe8a3402148ffc3f99aa67b8578bc08db8f50374045b4a9ab0e3466e7e956c5452fabe99ad612460caadd4ee06
\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1609455600000000	1640991600000000	\\x953214d97edb969d75574b32332af92b3caccf3445fb5866cd83442d73d133cc831c770ed23ad864059c67519e4e455e0deca8939931c4a8ff8861e6d44c8c00
\\x4f3fd07242a38acc876e568c55d83247becf1486ea27de839987c1011701be72	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1640991600000000	1672527600000000	\\xf3a21d349378d5d772a3d629483f1049d9c3582a5a5dea4ceadb203ad63d898a7710f378c534b969fec4d2ffc0a7594dfade385f157c99020b6ed3351b630905
\.


--
-- Data for Name: known_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.known_coins (coin_pub, denom_pub_hash, denom_sig) FROM stdin;
\\x13912d7751affc49f63424f6c3ff4d238fc4963b15e05ecbfb170a59647aeac2	\\x08ec5aeff83b85fd101ea725f92d3fbf0ab406ec626399bd388be186fc8f637ab0647cd3bad70a79c9e62cd3658f14b46f1b59d741b853e4ce260b4170299639	\\x3023772d0c1a507de2876fb88aa9eab33527c0440a2781d370e21f9f567dd05c07961098a387a788a9c67204f8533b5567ec76977a4fbd3d758af9fc61a6247809387a9980c9852e7880d7476f8fddf9aa4295632d007b5c3f6a17c3f688a88c512638ae44428bf6447bc3fbef7294b79066e7f02af25b83342931d4fbf9f451
\\xbdfa6d3cc52ea4a2889702b409f4ce24e3057257f45685a0b229790bda260345	\\x08ec5aeff83b85fd101ea725f92d3fbf0ab406ec626399bd388be186fc8f637ab0647cd3bad70a79c9e62cd3658f14b46f1b59d741b853e4ce260b4170299639	\\x387ace7dafa665255c9de81674bc94f72b3b313a9c39a84d9b58628fd62248a11991d46fe62eaa0d8fe99540791bb10a1132cf9183bd76edaec218e94d653b8d2db3c91c6f6f6358a6bb301442eab2a3e2d5ab1b78c7cebfdde8a38842197e7a79546ee19e8f794e13986991155e195a444f90fd50f05f5e97475452d9f945dc
\\xf8ae32ecb8d01222403852d6774ade7335ef7505360f7ce953cdebe8237286b7	\\x08ec5aeff83b85fd101ea725f92d3fbf0ab406ec626399bd388be186fc8f637ab0647cd3bad70a79c9e62cd3658f14b46f1b59d741b853e4ce260b4170299639	\\x5bc0c793980e59724136246c647e14ab46af2c22392f886927c542cc9397517fb3efd2bed5eb2f97451d61e51eaf3af96a1ac463e744e1d9852764ab1afedb81b9155bbf4c9168ba6976cc0ae597c3acfaa7fb1e0521af21744b6fafe2f3f9dfe8136ffd150926ee3db451240db9a3001a4db68ca9558ff8fd0286ee8df9c9c1
\\x9a456eca16dfcb980fd9700266de80c4fe95b4ad662266946bdd380266d15f32	\\x2177e96171e76a1815e93e402b24efbbc469e85d1db39d382fb0f551af826080eccceab6435ce4544d6bb64574771539da4faa0ef60a5f7aa1e38b5e3c002fa9	\\x4c2e879120723fd8356d82ef4e047408967f043dc02c371dc5f475695a1eade05277c523998d5523fa9002bb92da7c1a3306b4e954cc97da7a731eef18795fa6fa30371c8feb0c27715851c527b001446f93b8586883ab844f473af52d92a1e703b4936cbe7e94445471d55048d4bb0985610660074742790e7f02855b078c94
\\xfab41b8f820fea7547fba7bd4ff03f566adc98958ffaa51644ec436eb10904ca	\\x08ec5aeff83b85fd101ea725f92d3fbf0ab406ec626399bd388be186fc8f637ab0647cd3bad70a79c9e62cd3658f14b46f1b59d741b853e4ce260b4170299639	\\xa03f9273a70b4ca8a21cbf5ff79142cd3042ab49556fb6259464add8fad9021f64085f20cc19319dc3e711e80b00108cf65cf12411dfd3de3232d934a3f2a002c9b57b376975bbb049b4ef8a6975cf10fee2e391fe72fe85ffeace0b76147424d993ca0c81bde8dbe53966f75b4ccc7e7d923af3407fc57274b54a25368d7df1
\\xf7d8a74f5c49e40f169cb7d4a677de71d20150a19169f68974c3095052f2f1c6	\\x08ec5aeff83b85fd101ea725f92d3fbf0ab406ec626399bd388be186fc8f637ab0647cd3bad70a79c9e62cd3658f14b46f1b59d741b853e4ce260b4170299639	\\x4bcbc2a13bbd9dd0d26dd21eafdc3cc3823b4ca745d5335da5e20705157f8d40b551187352610834b65ad1eee47baddd8e58de264ea4e3188a31c3b4076000a0a9c7ca92b2a2ec9470ab94e959e101d190aa68403bef868355fe8b848c6ca9888935d85d7f3a5cae2771313131ee60f258f3fe960b63b509c1d61dccca3da09b
\\xc4438879b5588c7979adb65117bc310ef44eaae7ecdbd44c725853d91713ef29	\\x08ec5aeff83b85fd101ea725f92d3fbf0ab406ec626399bd388be186fc8f637ab0647cd3bad70a79c9e62cd3658f14b46f1b59d741b853e4ce260b4170299639	\\x26f5f3ed475d66cb6d905ace086da3638dadf28c0f8f86c08a47e0c4c4b34271cc5b8aa3015f5f56a0ad2f60dc015e15bdb421d676b00e69c5705969d7e368941f2573e3cf33e1d7f2ed2dae7d67a3bb92781ad8d3de37e07545b4860fdd44716d2312bc2f5581b422c09512ea1679adb6daf95d44e41948a308e3d5b5aa2fad
\\x8284c0f3a2dc31ab209dc2259960a179e63fb5b4ebebb325fe181252b455783a	\\x389763909f6bea58332dc5adb5b4963b696f31e496b7e60759c8b18a0214cf9ecd61aeaecebf30f713847533ab37865f46b0fd23c14587403c8dec2bad071c4a	\\x76516a9bcedae987f669fc7bd8699f96de8f11aee6ce2c040f0348f98b2b9657e5779b4ab44f6e33b9aa13abc450e6d47316414fd6c487fcab3373258d1fd88ddbecd50a7320f60707f7cc001441e633a73189c648bcefc33b87222e1de3ae5d80877794d2e43395cb90568ca2d17481c3b741901240889a4561335ddc471495
\\x43790d896a7051c91e985846d5a92b2fad7fb1588203fb5a1cbcd28f21852b45	\\x08ec5aeff83b85fd101ea725f92d3fbf0ab406ec626399bd388be186fc8f637ab0647cd3bad70a79c9e62cd3658f14b46f1b59d741b853e4ce260b4170299639	\\xa172d5a099d849e083dbc2e8ea979c5f7f343dd55e0429f47524531626973d2f526c2183836d234fd4cbc71a045f9c50cb22dd82941a0df5e0d8dc31b1b86f9a62914b7b005ca270638ec03544a6e0337b2f66732ca1f66776e5fd25ae09b5226e0676895e9c3b8fda86232c8f69bb964a14334d97219b71af2e544d92592e6b
\\xf50200a526d75117228109cae5ee2159c77446276fd339bfaf91b82015b7f5b0	\\x08ec5aeff83b85fd101ea725f92d3fbf0ab406ec626399bd388be186fc8f637ab0647cd3bad70a79c9e62cd3658f14b46f1b59d741b853e4ce260b4170299639	\\x05583b9b54e3e10e233af021366862b4b79a7697eb5687dfde41902594e28804f3901a3954526084196fb538abcd0b5f2362630e714291c3ad8f523ccc9281ad7387f040695d0fa55092ca0b9838834348c299bbbfbd2136174169b5fd6ce40472084716f04056b1bd4c3ffdca8f9d87d9ce16f0454f1ccbb5fb8a18a55ba989
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_id, merchant_pub, contract_terms, h_contract_terms, "timestamp", row_id, paid) FROM stdin;
2019.365-01N0WZ0C6M3KW	\\xd6fefeed0ccb548532af508ed3cb08440002531b9959282caf975269eb592b54	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2268747470733a2f2f6578616d706c652e636f6d2f222c22726566756e645f646561646c696e65223a7b22745f6d73223a313537373734373736363030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313537373734373736363030307d2c226f726465725f6964223a22323031392e3336352d30314e30575a3043364d334b57222c2274696d657374616d70223a7b22745f6d73223a313537373734363836363030307d2c227061795f646561646c696e65223a7b22745f6d73223a313537373833333236363030307d2c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2239575a5830574a324d45354353315645415436354250314a38595a435935343658384b5858305753475a30473235523151535330227d5d2c2261756469746f7273223a5b5d2c22685f77697265223a22503852575a364332515143543754515a3144574b4148563132534b59464b594d323743353650483356394650365a33464831453138334835314b4247514d38565850435a564554424345325134454458564b5248334a4831504747343331374357574d47374152222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a2254565a46585638435344413841434e4641323744374a523838473030344d52564b35434a474235464a5839364b54545335444130222c226e6f6e6365223a2252434a5444525045394b57575356344358535038445443395957345051425051355937444d3142355351544453364b374d594730227d	\\x04bc8bbf1257210c74bf65b8fa7ca1c88577a43f06528202a909ecebc79108b53bec1cda1aedd914f192641c3c63c27cf9271697e1e9e36c6e1efa2408686412	1577746866000000	1	t
\.


--
-- Data for Name: merchant_deposits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_deposits (h_contract_terms, merchant_pub, coin_pub, exchange_url, amount_with_fee_val, amount_with_fee_frac, deposit_fee_val, deposit_fee_frac, refund_fee_val, refund_fee_frac, wire_fee_val, wire_fee_frac, signkey_pub, exchange_proof) FROM stdin;
\\x04bc8bbf1257210c74bf65b8fa7ca1c88577a43f06528202a909ecebc79108b53bec1cda1aedd914f192641c3c63c27cf9271697e1e9e36c6e1efa2408686412	\\xd6fefeed0ccb548532af508ed3cb08440002531b9959282caf975269eb592b54	\\x13912d7751affc49f63424f6c3ff4d238fc4963b15e05ecbfb170a59647aeac2	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x230848bbd97087c56e78e231a14c96bdcc369aacf4a77302054125ea91e83eb9	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22414d46375448335251543139375451443657385354334537374e5130473433505a5a3336424e4b363947303751393235394b4b44424257504742503952525636303836413159563544425a52375a454736445458504230545730594a505751504a4b4257303038222c22707562223a2234433434484559534532335741564b5257385254324b34505151363344364e43594a4b513630473538344a594e34463837545747227d
\\x04bc8bbf1257210c74bf65b8fa7ca1c88577a43f06528202a909ecebc79108b53bec1cda1aedd914f192641c3c63c27cf9271697e1e9e36c6e1efa2408686412	\\xd6fefeed0ccb548532af508ed3cb08440002531b9959282caf975269eb592b54	\\x43790d896a7051c91e985846d5a92b2fad7fb1588203fb5a1cbcd28f21852b45	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x230848bbd97087c56e78e231a14c96bdcc369aacf4a77302054125ea91e83eb9	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2259324e47534845514e453848485a455044563233433344394a303857443856545a5939504b4b3158565739515a35514e4556445634543739433036314746374345595a44413044594559333047365a4d315a4d3630415656513244424745485151384247413147222c22707562223a2234433434484559534532335741564b5257385254324b34505151363344364e43594a4b513630473538344a594e34463837545747227d
\\x04bc8bbf1257210c74bf65b8fa7ca1c88577a43f06528202a909ecebc79108b53bec1cda1aedd914f192641c3c63c27cf9271697e1e9e36c6e1efa2408686412	\\xd6fefeed0ccb548532af508ed3cb08440002531b9959282caf975269eb592b54	\\xbdfa6d3cc52ea4a2889702b409f4ce24e3057257f45685a0b229790bda260345	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x230848bbd97087c56e78e231a14c96bdcc369aacf4a77302054125ea91e83eb9	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a224d38325746575631325738443036344e345953334d4d3935574552503034413333385250485a4e585257523334545644354e4647575038305058373242535a314b524430353933594234484732314443424137314d525153455745504a58564435444e4b4a3352222c22707562223a2234433434484559534532335741564b5257385254324b34505151363344364e43594a4b513630473538344a594e34463837545747227d
\\x04bc8bbf1257210c74bf65b8fa7ca1c88577a43f06528202a909ecebc79108b53bec1cda1aedd914f192641c3c63c27cf9271697e1e9e36c6e1efa2408686412	\\xd6fefeed0ccb548532af508ed3cb08440002531b9959282caf975269eb592b54	\\xc4438879b5588c7979adb65117bc310ef44eaae7ecdbd44c725853d91713ef29	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x230848bbd97087c56e78e231a14c96bdcc369aacf4a77302054125ea91e83eb9	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22474e4e31514b3553344e584b4b45394152365052353531334d4132504432454239484b59315443443834583538314750394634443652515934524247304e57434a4458564a573054534b365633475642373958484d42505032333051303741425a413932383338222c22707562223a2234433434484559534532335741564b5257385254324b34505151363344364e43594a4b513630473538344a594e34463837545747227d
\\x04bc8bbf1257210c74bf65b8fa7ca1c88577a43f06528202a909ecebc79108b53bec1cda1aedd914f192641c3c63c27cf9271697e1e9e36c6e1efa2408686412	\\xd6fefeed0ccb548532af508ed3cb08440002531b9959282caf975269eb592b54	\\xf50200a526d75117228109cae5ee2159c77446276fd339bfaf91b82015b7f5b0	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x230848bbd97087c56e78e231a14c96bdcc369aacf4a77302054125ea91e83eb9	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22435444573552375451365437534a4143314d505a4e3659394445364439414359574843544a364432354d3430505236505150484e4d3045585a56374b4238434a4d533243485442484d47533132434d543644594a565a435a443844305a4758534a435632343238222c22707562223a2234433434484559534532335741564b5257385254324b34505151363344364e43594a4b513630473538344a594e34463837545747227d
\\x04bc8bbf1257210c74bf65b8fa7ca1c88577a43f06528202a909ecebc79108b53bec1cda1aedd914f192641c3c63c27cf9271697e1e9e36c6e1efa2408686412	\\xd6fefeed0ccb548532af508ed3cb08440002531b9959282caf975269eb592b54	\\xf7d8a74f5c49e40f169cb7d4a677de71d20150a19169f68974c3095052f2f1c6	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x230848bbd97087c56e78e231a14c96bdcc369aacf4a77302054125ea91e83eb9	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22443358325034575752415642534e59483637523346335a4248324b4853384e3243594845344b3056423039394b454153394237313239454d53415a4e574133314d413333353933324b5a383246483148575337485a533536575641464252393035504e32363330222c22707562223a2234433434484559534532335741564b5257385254324b34505151363344364e43594a4b513630473538344a594e34463837545747227d
\\x04bc8bbf1257210c74bf65b8fa7ca1c88577a43f06528202a909ecebc79108b53bec1cda1aedd914f192641c3c63c27cf9271697e1e9e36c6e1efa2408686412	\\xd6fefeed0ccb548532af508ed3cb08440002531b9959282caf975269eb592b54	\\xf8ae32ecb8d01222403852d6774ade7335ef7505360f7ce953cdebe8237286b7	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x230848bbd97087c56e78e231a14c96bdcc369aacf4a77302054125ea91e83eb9	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22464e36574639384539395852463541474b3933304d355353444a323537515a455a42473557445830513332594e3638374657344d5341514e57504b3234504547534b56353448423458355a334e5034344535445150513947354754344e41475a545a5648473238222c22707562223a2234433434484559534532335741564b5257385254324b34505151363344364e43594a4b513630473538344a594e34463837545747227d
\\x04bc8bbf1257210c74bf65b8fa7ca1c88577a43f06528202a909ecebc79108b53bec1cda1aedd914f192641c3c63c27cf9271697e1e9e36c6e1efa2408686412	\\xd6fefeed0ccb548532af508ed3cb08440002531b9959282caf975269eb592b54	\\xfab41b8f820fea7547fba7bd4ff03f566adc98958ffaa51644ec436eb10904ca	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x230848bbd97087c56e78e231a14c96bdcc369aacf4a77302054125ea91e83eb9	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22385233505339323430474536315634584e5a39385a514b4e48323337364d45595158475431573945525853424436354d3059384b4b43303547343835424b3337344a41375a5745505337425337584b4a5038414154594234435847485046353357334a34473152222c22707562223a2234433434484559534532335741564b5257385254324b34505151363344364e43594a4b513630473538344a594e34463837545747227d
\\x04bc8bbf1257210c74bf65b8fa7ca1c88577a43f06528202a909ecebc79108b53bec1cda1aedd914f192641c3c63c27cf9271697e1e9e36c6e1efa2408686412	\\xd6fefeed0ccb548532af508ed3cb08440002531b9959282caf975269eb592b54	\\x9a456eca16dfcb980fd9700266de80c4fe95b4ad662266946bdd380266d15f32	http://localhost:8081/	1	0	0	2000000	0	1000000	0	1000000	\\x230848bbd97087c56e78e231a14c96bdcc369aacf4a77302054125ea91e83eb9	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22465334514e593642334359463950344b48565733484a585743454138484b475a514a593339503330454236594a504b38455a344d46564834524b424e3345444252324834394846564d434b4343435a5644505050535a5a54305045324739484453363235543238222c22707562223a2234433434484559534532335741564b5257385254324b34505151363344364e43594a4b513630473538344a594e34463837545747227d
\\x04bc8bbf1257210c74bf65b8fa7ca1c88577a43f06528202a909ecebc79108b53bec1cda1aedd914f192641c3c63c27cf9271697e1e9e36c6e1efa2408686412	\\xd6fefeed0ccb548532af508ed3cb08440002531b9959282caf975269eb592b54	\\x8284c0f3a2dc31ab209dc2259960a179e63fb5b4ebebb325fe181252b455783a	http://localhost:8081/	2	22000000	0	2000000	0	4000000	0	1000000	\\x230848bbd97087c56e78e231a14c96bdcc369aacf4a77302054125ea91e83eb9	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a224745433736464b43475351455256534e42415033324d51444833304654524a393844413658414641574b435948504e32395236533353434b47483835374847394b3647565447314a38464a4b5933545039434e3658484d4248433558485a344251453353323352222c22707562223a2234433434484559534532335741564b5257385254324b34505151363344364e43594a4b513630473538344a594e34463837545747227d
\.


--
-- Data for Name: merchant_orders; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_orders (order_id, merchant_pub, contract_terms, "timestamp") FROM stdin;
2019.365-01N0WZ0C6M3KW	\\xd6fefeed0ccb548532af508ed3cb08440002531b9959282caf975269eb592b54	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2268747470733a2f2f6578616d706c652e636f6d2f222c22726566756e645f646561646c696e65223a7b22745f6d73223a313537373734373736363030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313537373734373736363030307d2c226f726465725f6964223a22323031392e3336352d30314e30575a3043364d334b57222c2274696d657374616d70223a7b22745f6d73223a313537373734363836363030307d2c227061795f646561646c696e65223a7b22745f6d73223a313537373833333236363030307d2c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2239575a5830574a324d45354353315645415436354250314a38595a435935343658384b5858305753475a30473235523151535330227d5d2c2261756469746f7273223a5b5d2c22685f77697265223a22503852575a364332515143543754515a3144574b4148563132534b59464b594d323743353650483356394650365a33464831453138334835314b4247514d38565850435a564554424345325134454458564b5248334a4831504747343331374357574d47374152222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a2254565a46585638435344413841434e4641323744374a523838473030344d52564b35434a474235464a5839364b54545335444130227d	1577746866000000
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
1	\\x4a88e41098c8128d764fa415bad04cbfda88fdb5e48d914dc3475ccef85d5679db1e9dd0fe00d90b5f7a0e9083d1b91d1787c1f307655cf05502b13bfbb720c2	\\x8284c0f3a2dc31ab209dc2259960a179e63fb5b4ebebb325fe181252b455783a	\\xfb52e1f8334c49d377f06f1fba59506a74db07fbbc4924d4c1cb2d237484ba9a992d0fe6a6b54c4ef7c4c4e6d25bd947c6be1a3cdf72efae18dd2439ca5ff604	5	78000000	0
\.


--
-- Data for Name: refresh_revealed_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins (rc, newcoin_index, link_sig, denom_pub_hash, coin_ev, h_coin_ev, ev_sig) FROM stdin;
\\x4a88e41098c8128d764fa415bad04cbfda88fdb5e48d914dc3475ccef85d5679db1e9dd0fe00d90b5f7a0e9083d1b91d1787c1f307655cf05502b13bfbb720c2	0	\\x0ee82e56f4d0c3bb9d57f0192e51a1c6479907f6b69a3178aa22d3052f6315014f4b167dcf10339337a578ba8ae01aff7eae73959b0c6d6afb95c040249e1e0d	\\xb0ae30bfd2bda436dfc81a6e4dae41b9a09fd5d5f3f9dc1085b2b198523c7b9bf7c6ad6b8a919f274c14d2f71026bca7a83bcde301a30cca4459faed7aa59c69	\\xe41317add8a3dd0b91ae67f34b4893b24b4d28d9b0e28b96e29644a56ab80f859fb22d15b508721d454d15011b90dd878a409dfee2a3b9f7810c695d2ae07c4c3939acedf259935ad6008991541d80dab38df9656e9e211944ec869a7875935cbe57caecad1e420b784f795d91fef38d66e69a5415c6ee8c446d130edf3eb0dd	\\x5b081c752c01e2795339d355c7f7b9afffb25720f009d59da733cf97feb7e3d8b5279c41b88369534a1b7b521b027a7256fa2b1c85c293b2080f8047ff186915	\\x6e266a92ad4b2668c262efe6f4005e4d19964a4e5216e0c5c8aa532eb2365c2c69776ab9cb3151787bca309160d95fdf93bb619a1de3587e7a50eba0a79998b9b64b8c4fa4bd4160a6e0e89f25ac269eb03e7ac7c42e140a3a67bbf12435f8716b38e212f6c15679c0603305d0320b9a583e0231a21cf3995609d022d95ac923
\\x4a88e41098c8128d764fa415bad04cbfda88fdb5e48d914dc3475ccef85d5679db1e9dd0fe00d90b5f7a0e9083d1b91d1787c1f307655cf05502b13bfbb720c2	1	\\x64de846f92cdbc2e84835fc4f129fd3ea3d922a687e084d5b4060bd51dc5f8f6d1bd7b1bae0cc10d84fd46ba8359d71cc918a0cfc1fd1b7522ec884f7a14f806	\\x08ec5aeff83b85fd101ea725f92d3fbf0ab406ec626399bd388be186fc8f637ab0647cd3bad70a79c9e62cd3658f14b46f1b59d741b853e4ce260b4170299639	\\x1b33b1450da7e3816bbb2eb4ad03234d88a2aa910e312709d782e6a62f911e45cfb5bd67feb0d405f56fb8800fa106bc25c6f3563e571b2f77f5a0f39fa00c670ceb6466414002eaf053baed3fd6b82a8aebdafb2614c747e3f8561570b3898999e51076f4c2eb009318b371f084beb3887763ad0af76a037e560844d4e97c96	\\x041d0f580b994fa3595f73732a45c258c7c643906864906be9fefda5952e26aacc9a33f60b478ece83a88739dfc92ba645114e6bbc3bb27428ed4c2ac1442dbd	\\x55e06122d540a5901fc4465c22987c8afcc8018ce1cfd3cac26f4f3232a0b0778dc678e42fa0f24259b19bab4fb108c611ce56cd5f53c182ff474b5926aff16d8996e0db518f20441902464e726a05182654896b2a6abfb294d68a1a42d2a6f119e368cee73c49771d99e75bd7a8743a33efb4ed2930f7d0d97c73a4f43f2dac
\\x4a88e41098c8128d764fa415bad04cbfda88fdb5e48d914dc3475ccef85d5679db1e9dd0fe00d90b5f7a0e9083d1b91d1787c1f307655cf05502b13bfbb720c2	2	\\x8ee5c76ed4d5dd9b2708482e4714f5584fafc3925578f717788066e1796e0e0701acfac21aa13dcda4599934bc5c94fe51d49edc589c5af3e8778e103537c407	\\x08ec5aeff83b85fd101ea725f92d3fbf0ab406ec626399bd388be186fc8f637ab0647cd3bad70a79c9e62cd3658f14b46f1b59d741b853e4ce260b4170299639	\\x663d1736e0ee59541768b180f54af2a9d35036d6476e5625b63374837026d429b8551a923b408829a0df6378644518047b26f30a6fbc701b161348add5d682f10ea07d341df2016b1957e28e0ec9a0f495bb30d9e102efc1f37467923cf8bec9abe10928564e4dab52d1d1a99b60ad97bfbca53be8af2bfd885dc82653c61288	\\xef8f40be31bb9e9a0477cdc1d06d8cdc9b9f9cce0e6012762749eea53a326048d930af904c2e246a3c94dc24cb9f5f03f396f759bcfb143c7556c1aa54288062	\\x0ca8e3c92e6e950dce2d0643dd0e2007001dfd77337924b8e93c0a516b365055248ca050104d26d35391613aced5674993d9c40a21ad488d754ec716ae5cd8fda430969fd0544e0ba3fcf18e99b95744208abe0b3f0efded14c70c6a5d9fbdbd9b69f338ffffd51ceb374b5ba15cb8dd52044fe4e39ba49dc77cc7e25eff6641
\\x4a88e41098c8128d764fa415bad04cbfda88fdb5e48d914dc3475ccef85d5679db1e9dd0fe00d90b5f7a0e9083d1b91d1787c1f307655cf05502b13bfbb720c2	3	\\x0a27746191394e65d8395c8b20518271cbbb764d4bcdd683b174a83dbba359448815e1eae7eda254219a8084839835b55345c9a2915157aba31001114b76be0e	\\x08ec5aeff83b85fd101ea725f92d3fbf0ab406ec626399bd388be186fc8f637ab0647cd3bad70a79c9e62cd3658f14b46f1b59d741b853e4ce260b4170299639	\\x4269af6fcd3d91f8fed267e6c5de4d83f81e36f0b76066aa118730662a693568687b62a95025c7f01c3fb191ba1c75ea1ad3ede1e23a35fdc44033345ec88a35effaa3aa03a16eaec5201f7a226b877925c17e9d1a2b131966377788bebf7f8dc3daacc3a95203fd96e0e7e87fe76e27c872f1cf5b8dcf532cd7c9f2d7bf3486	\\xfa292ac89499d0998b5a7e3770540615f40ef620f20ae6e46a8cfb8e4f2781afe5192ed15d9fd6aab5cc559ffa56581d7ee9962401684799fcf70261d0550927	\\x414339317708f991921e9a5580f298a0055efa330d56209e303822042f87ec325c5d5686e596ead46f02b29d4ef78bbfeac1e5610afc0887ff0d16e8e44722bb9627283ed33a57f862bd784fabbaf00b226c70d3a3ba31841e8a76e2f75104dc9ab414a361303967488be52fa9e4957376073e8c06958b57817e32d9f0b174b8
\\x4a88e41098c8128d764fa415bad04cbfda88fdb5e48d914dc3475ccef85d5679db1e9dd0fe00d90b5f7a0e9083d1b91d1787c1f307655cf05502b13bfbb720c2	4	\\xe713c8ce2dc8def3e2e1a46dea816224cf3c283437e7b79d6a21d97791996209bb3054af99dd4982bb08134e5b540d305965a2fcf113b7b37e53773b6caffe08	\\x08ec5aeff83b85fd101ea725f92d3fbf0ab406ec626399bd388be186fc8f637ab0647cd3bad70a79c9e62cd3658f14b46f1b59d741b853e4ce260b4170299639	\\x63383df98aa6d7a741a96255a8cca675be12f3de3e78e69c52faccb1ae8ddfc6402e6b50ed05d8c03ec62b0cf2de2f2719af7a3366871d46e1859705d04d1d97a53fd8afb312b02db3411e2afd70cbc7c2f04ec95948246b687b1609e253efa4c47b1db818394e9ca3e32d4ba6385b80935e2259ed37f4a7a0b2b425f9e84d18	\\x87534b378bd76dfa1ea12ed15a1f00a3d6d761359c096ecbc7b037fb9a0fd6f852361f5a430923bf93920262fdd8d0bd7fd0c7956f8fb1cb8c1af2e85a066063	\\x18bf8f1451d7cfb65e9468099baccdfddc8a3a3230a8831175f95b080d13defd02584cff27c2f34f8eb7db03c92c7609c46a9f63af544b5f8bf8419cecca188a9e15fa5c57acf57d159b2f78e212a69975cc28f0c0939a0773d9c4ac090455d3849fd1b5c8cf17f634f8ba72a23574ce576d8bcfe925552a81ba390c16b3ed0c
\\x4a88e41098c8128d764fa415bad04cbfda88fdb5e48d914dc3475ccef85d5679db1e9dd0fe00d90b5f7a0e9083d1b91d1787c1f307655cf05502b13bfbb720c2	5	\\x7d73e8de3c717057a5dbda845ed5b153170cb8ccc0ed90625ab20d15c1c677644f8edca0fa258f276a429f3da52bcc3aec7cbe781eee9f121f18103484ead00a	\\x08ec5aeff83b85fd101ea725f92d3fbf0ab406ec626399bd388be186fc8f637ab0647cd3bad70a79c9e62cd3658f14b46f1b59d741b853e4ce260b4170299639	\\xaf79c9adedcd31d61cc0a4992c89be0ae69a671a6a37a8df18fec0071fd1e95d477a1b4cb4f0dfcef7977e84ddbb871269c8b86582a80e4fdcc2f4e1c44e9ea3fbd9fd2f0d98923a55b900d4486d294a6644803c15fe977b47e36369d74d4bb62a6c4be2ab5c72e7f02a4c5b2c853165f520825864854b25e3a2cac3ade80eea	\\x90411830a4e917d606e61a0036b22bdb21f595c73ab9f511fee8825cb47f7daefe84915cfdd3d4bac35a9dee159f77918111a183ac1c7c8947bfaee586bf2e32	\\x64d49f7a2e1404d87061d1f4e9e6925655ebcb04c25827560afa606260904f6e0b5ea272263f8b7b0eed0887c9e33ef384b3887a6a902ec1c306d69c222c53482765eb7a9386bc67faea1d72b0884afe888ff47eeb27cc1a68547b597846c0a7eaf14a8e2e697ff77bd7422f28fe9aba8e627590412bb0ace57b65d819b4d280
\\x4a88e41098c8128d764fa415bad04cbfda88fdb5e48d914dc3475ccef85d5679db1e9dd0fe00d90b5f7a0e9083d1b91d1787c1f307655cf05502b13bfbb720c2	6	\\x348fb01417b8322895a7f46e7febbc30552653cdab1748d45825cada0c8a8ff3db53e14decf86281c38d291243bb07a6f13b56a12bd8ff5a2bbe08d359258c0d	\\x08ec5aeff83b85fd101ea725f92d3fbf0ab406ec626399bd388be186fc8f637ab0647cd3bad70a79c9e62cd3658f14b46f1b59d741b853e4ce260b4170299639	\\x3bc49156201fd81fb541c1248b994c6ff7b6e711cf8f6392d18147e7b88e2a68de9521ecd02f6b59056e879ab03ccfb722ad306935ba67a66fea12c30e850ed4bc38ee4806f84cfd7092caf9cd2de686a340feb670115fed08c668da56f3abdef54b0a533a905d716666259ccd93fe26a60a3d8841b57bea484fd108066e4901	\\xce16624975d411cb008775ef510d17f9ce7bae35f305e22108ed28192dd1d8e3e7412fa1dcc29ec349fd8af44d1f065c5834f36df50566d62098cae7248ead69	\\xaa68a50ecddcd53aebf3bdf9ed4bfb11037f2e62383b2fe0bdd3cf28057df662ae3f7ba5521e924091eb270757488c90886eadf3ffc77deaf897964f93a2d06ef7261e0ec8ba7bafa42dd4fe78500c39ab68f2d996e99ec1ec2cd08cbec0e4deb3407324a9819a0d58f976b8ca219f465dbc8c5aba905f2b3289baaadc0d2775
\\x4a88e41098c8128d764fa415bad04cbfda88fdb5e48d914dc3475ccef85d5679db1e9dd0fe00d90b5f7a0e9083d1b91d1787c1f307655cf05502b13bfbb720c2	7	\\xcdf00db3d48e164eda60fe5eb645074b3788339413a8cd439286fa35a7263ead8b913416abd2d3379fa80099c6d43c380eefe550130db94c8e44fced60da0c03	\\x342a53036140a9d41d0d3545d085b4a7e5844982090166231e639a7c773ea72d7ce730ee78d08cb62f7c4b772747abf0621dc6f2de90544337f545e11e000970	\\x5b99c03df9a99fe1375264577e110120f7f205b5d31c06d88b565bffd360840f8307dc3da104c09acc77463c0595a1d7bd11a1b11516ca7e9ab157ed0bf71d0a6041a614d08ec4cbe4b26c7191162a92f798afac8c503f4a2501a8b54edb61c0b3e2f3758bd4d49659cdf11099a46225ef9a1a5d5199a6bf0d83a34b4fedb17a	\\x8f39b043cb77aa9e7f8ca40eb34065c3775270ca1aa10cbf4cf1324ca5f80ec06b64ccc4152101a489867bbf91b63d3b8117f18b91db764cb115a577e23bd90e	\\x9e67ef5c7e80e3703937ee68cd296cf4b52a411d91a4467fcd4cae7810b7d3fb1cc12d6542c53ab2cc08be9e001bca545069a38f3365c49716a59066bc88cefe2c07e9ea4c6e32dadfe019e7f2dc84b504bbe1ff146624121fea9493fa71b76f2119dd484bfbacfc2d6293ace31c2add670694851c7e6c6e9ddaea54505465c4
\\x4a88e41098c8128d764fa415bad04cbfda88fdb5e48d914dc3475ccef85d5679db1e9dd0fe00d90b5f7a0e9083d1b91d1787c1f307655cf05502b13bfbb720c2	8	\\xad4cb6fd9bafe83e2dc1f030a3057c9ae21ee2cef548e64a8e97871cfad5475e689439f04987f35b189372c97a2987808d033b5709159168f2a3742d6d638000	\\x342a53036140a9d41d0d3545d085b4a7e5844982090166231e639a7c773ea72d7ce730ee78d08cb62f7c4b772747abf0621dc6f2de90544337f545e11e000970	\\x52bf6a71612de1db91cb29e8df39f186f343ed58b9c6da08e5c4034301ae2897831d083cc9f058b4cd1983e4cfd634d458a16d3cb8f302dd7ba271ae287c86cc4063cccd02ead0a4c40f4ad31b975f89ed4117326b8015e57f1088fc71680fb5ec8f79c68c3a7c0965cbfa7cc4b7830fd8328240c1ccabf2dc35cd35f0626f70	\\x7dd2fc3d6fdaa7d09af27cebd18bc708dc41c383757afb724ecf87fb3f32b2c5be66eaad0a908d3801b0f10ebe7e1a5d04996879f765256fde862eec6acc7afe	\\x660fbc9822b4af80e1a0a4425f9f83debfc6390e8f8f5dc3bb610a4641558bb98f08517308b859cfa4348fdd846b99e4b6867da2977730af396e25d07e35ef725524530eb1e212c189dc25398dca95c7fba52698f1a081c63906e030ed24b577aeb60613a8e07c8c2e9f7d98481a84a18e36b3ecffba96a7ede9a1effa44937d
\\x4a88e41098c8128d764fa415bad04cbfda88fdb5e48d914dc3475ccef85d5679db1e9dd0fe00d90b5f7a0e9083d1b91d1787c1f307655cf05502b13bfbb720c2	9	\\xc66eafe1b1c0338073db51aeb0efc8efd60e2a3c1001d1e308a5f2278d5ecfa741c3d015ead68eac0096fc2ecc535959d99d71214e2fd1c3e8d038cfa5c35302	\\x342a53036140a9d41d0d3545d085b4a7e5844982090166231e639a7c773ea72d7ce730ee78d08cb62f7c4b772747abf0621dc6f2de90544337f545e11e000970	\\x0b9c1738359b06943fcaaa1017101fe40722b1394ba14bff4349be3e19d6f8770c8db53a761db19f5621fcadd3323a90e9d63bb5fcf047b4965f2116e7cfcfbda114792c459af09439bcd872ab5c55f72d399a0ecad76139a5ecbae35705bb1460ef3eb07a0fb852e052a5653747c954046490a29db233c24228c7f4c458a592	\\x004535087e55dc3e254161f82f46c5ff73b75e4cfea25d821bb74055f79b251dabe2b2444e6cc2926c1204f6e8d4e361a7c9920ed917de2f2b1c6c821f7ddadf	\\x9482dec7df554b5a363316846f48607ae53280b669fdfbf7b6679ddc23e9ceb2bf719b4aacc483ce559d06ed264fa2e55681b2d8eded1568b56cc470ff107d7972f3fed18853ec0d195f15578f139bd28183e29df4ec17659acf423c59c8f38b9f5527eea107c01882383914b21ffef88a9457ca5f1af46c53a9e904cc4e7ecb
\\x4a88e41098c8128d764fa415bad04cbfda88fdb5e48d914dc3475ccef85d5679db1e9dd0fe00d90b5f7a0e9083d1b91d1787c1f307655cf05502b13bfbb720c2	10	\\x58b3e2b4e1e874d4703cd101a5c8e781775323a38570334998231f26d52fa9a285c245f2635eb08904807656a54686499fb30d014e97a2326574f11224420c05	\\x342a53036140a9d41d0d3545d085b4a7e5844982090166231e639a7c773ea72d7ce730ee78d08cb62f7c4b772747abf0621dc6f2de90544337f545e11e000970	\\x62611a3833e2e09c1b42cbc22f2e54859b0d0c0e4860a89df768bd47ff6aa8f1e6e6d6d1e46258bdba8befbf0e345fbd273148d5b4dce30523f8ec5bf884fd3346fa91592c42204994e876fa396a96e25a0ef373a7534be1fb22c50aba43745eca527eb9f35b3275aad3af6bd510627553d013f5a9d1236d1d7338e90f2c72d0	\\x5dd52f176a5fac3be920397f6221d3a69ca4c743b87d0f05d5cddf5be844ca30b76863808c78b17adbcc8b88f7ab62dc212b7fa2878f4612568ebc78b01a3718	\\x4aa8e2fb24bdc756079342e828c4b0a28bfcf81f6a33b5bcddf4bb9a453990e0cccc0bbc928c4a64f91ba9807a9342bcc8f252a5d422eb57558a15787a4e3fb9d54f2e54547fc146859c098341f65d3cb4e5f59d9030047aa70fa70d482bfbc5e71309b329fa391276073ba4cfc8aecea7f7ff8d49f9719c95713d24007b7153
\.


--
-- Data for Name: refresh_transfer_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys (rc, transfer_pub, transfer_privs) FROM stdin;
\\x4a88e41098c8128d764fa415bad04cbfda88fdb5e48d914dc3475ccef85d5679db1e9dd0fe00d90b5f7a0e9083d1b91d1787c1f307655cf05502b13bfbb720c2	\\xddca6fcca63bd304e8883b10b619f1b1003650dc8801bb05cfccb78d9e6d4d68	\\x13b7e23280c23a079c85f7bc404e9d21f9bf7ffaffe034ac305751945f1a5520ef966f2a06f9690efb647daefe57aca2107b207016538164f45e56cd2736f569
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
\\x96d72626c6249e7ee0ce73e7e8f607a9069fed4e211a5d185c2421af630d7c95	payto://x-taler-bank/localhost/testuser-kaG45ily	0	1000000	1580166065000000	1798498866000000
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
1	\\x96d72626c6249e7ee0ce73e7e8f607a9069fed4e211a5d185c2421af630d7c95	2	10	0	payto://x-taler-bank/localhost/testuser-kaG45ily	account-1	1577746865000000
\.


--
-- Data for Name: reserves_out; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out (reserve_out_serial_id, h_blind_ev, denom_pub_hash, denom_sig, reserve_pub, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\x1baf3bacb96ea796d7de407d7e3ac7db60d633d96404b97a2ea9f8ff889aa98523004258fb1a16de5465c7d87fc781656e6758ec6be7e11a472332801cd25eae	\\x389763909f6bea58332dc5adb5b4963b696f31e496b7e60759c8b18a0214cf9ecd61aeaecebf30f713847533ab37865f46b0fd23c14587403c8dec2bad071c4a	\\x2381b9dd7f32e8acbc12ddca1a11ccad93adec124546f9df1e24f2e31d2bcebffed2f12ce4236b92bc262c700ae8f4616b68736c4c77bf12032282a31f537f40f684eb0565b110511d6912ca75a62331eb32d19a70bde7aa927d1362a6132b725b9994d16c0c4c5edb0f1250af130a3befffe41b39d784e0b4e2bb8829e48787	\\x96d72626c6249e7ee0ce73e7e8f607a9069fed4e211a5d185c2421af630d7c95	\\x1f18d36ef78f8681dbbaef6c99e77bcd15682c7bc80e96a9f790add0ed94e8d3398a00c1a128bd7bae001e770dc96666699a2e1a58e71a4528bf34d9a1389106	1577746866000000	8	5000000
2	\\xc33e743dc261aafdd96a4f0b280d5bc9d41c97dd9bfd7ab961706f26f56e9b6b8e36d34b1e23cb4c88ab8b7224946e4c8d4934cb3bb185f09e11f4b5f549c8c6	\\x08ec5aeff83b85fd101ea725f92d3fbf0ab406ec626399bd388be186fc8f637ab0647cd3bad70a79c9e62cd3658f14b46f1b59d741b853e4ce260b4170299639	\\xb4ca44186a781ba823956950f6a4ba66ab661ecefac8a62fe49b27997d6b5bf3d224a7473029c550c1094ade7cea3b73f72f8efe24a5c33e949dcd59c334105df44d9e9eee2ccdda94c760f978a27fee75a6a92614e5aaf8b3d2274a1e375e8bdde1db7823ae1db7b1ecefdb8f2f914e89243aaedf1b098658c4a0bd5b0d23a7	\\x96d72626c6249e7ee0ce73e7e8f607a9069fed4e211a5d185c2421af630d7c95	\\x8cb59fcbd1af0ba2390b7788a4e6175b277af4b6c7f10968a7e515d8d8acc960ddb59cda4dc599fafdededd7c1dd5a3d7979783dbf7c3c3b7dbe3ec4aec4e203	1577746866000000	0	11000000
3	\\x86ef1f73b9350ba9259fc6f919bd991645dc510a5a8990da7920494548dcabd48002b31454402b87f258c1ea7dbf6f826b7fbe232cdf018f4bed9faad7492763	\\x2177e96171e76a1815e93e402b24efbbc469e85d1db39d382fb0f551af826080eccceab6435ce4544d6bb64574771539da4faa0ef60a5f7aa1e38b5e3c002fa9	\\x103d38ea6c359065de764c89663048acbaf5beb0ffb4eba9030e953cd5418ba148ab5d03b931864195815093663d2dfdb617fce5851abf10560eee2c68238249f4648ee2a95d16241ddfb2f6692148489d23a444af16ed7a376c983c6c944dd3a30026824dca674b7a5c20ffd21a5d2ab0654412f7592730ce0e6d446bc9d9	\\x96d72626c6249e7ee0ce73e7e8f607a9069fed4e211a5d185c2421af630d7c95	\\x3eaddf8cf5bc78e171cd4f2539c599f5ab3f1d08e0ef985badaa921f304b125295e244cfc5da6048ddb3799ff44acd70bc56575af225ccf93180ad4393a7df04	1577746866000000	1	2000000
4	\\x3fb9d548793311eac391bf229b94dc98c2cd42c5c89fdf4ecd8fc2f6bbfbb30e6255061538ec4c0675b5938a8ab99270923a1639a2e691b86cef158b931d5150	\\x08ec5aeff83b85fd101ea725f92d3fbf0ab406ec626399bd388be186fc8f637ab0647cd3bad70a79c9e62cd3658f14b46f1b59d741b853e4ce260b4170299639	\\x77c1fc21a08e1348d1315a4942e9b61a8a89a5b3610e47e4f802f327e784c0fbaa207666299cf1037c0cbb80aa539341eef0d70d0da702833b04d3e3b908c170a3012f8658cbbef75c37b510e30148a0a20141d6e093380586bbb3a37652a87a88ddd649dbf5f40c1ed28e113397ec77cbf0d807b2a74dc63db91dcbc645d993	\\x96d72626c6249e7ee0ce73e7e8f607a9069fed4e211a5d185c2421af630d7c95	\\x038be3cad6d90731287189fb1b8a7ca0eefa0ebde5b5a8c995ecfcfdc15d2f980b46b47a84aec5c26951e9336eecd78f7de3ed8b49b6f9f66065c04fd0ffcf0d	1577746866000000	0	11000000
5	\\xdd880aea6864f398e33711ab02bac70391b2cee0cfb94ae67ed288e37d003cf459df0303c146e8fcd4385957c736b67506d1035707d1dcb297d34fac462b0dc3	\\x08ec5aeff83b85fd101ea725f92d3fbf0ab406ec626399bd388be186fc8f637ab0647cd3bad70a79c9e62cd3658f14b46f1b59d741b853e4ce260b4170299639	\\x09b59f3f00f54f70feb991dacaedaedd29f54dbc21205b1f4cf9b2965c0047b1d410f1215e3917494f702133781e6ce33f8cbbfc6930df9e5fc70c7dec91fdb7a5df8be5100f409d3e77be42b0b014c15b0d576805de8710842075c0ef324e0eee5a423132e1274ebfa7530c5612919434d77200d4b1ddcc71078702e0030318	\\x96d72626c6249e7ee0ce73e7e8f607a9069fed4e211a5d185c2421af630d7c95	\\xbb0db65c49deb57622b453acaaa22595a8976b6ee973df32e2ed841081f66fdc77d857d12a162da327b8ef3a666126db4ce6a201ad585a3abc79b28a4a668502	1577746866000000	0	11000000
6	\\x9c6b1f1e3d9852957eb3d91100eb83544fd723066b4942b43beb1b0ddfe832b1f48700262c209242db580570f015a2098eccded500a75e27d5468e10a937a1fa	\\x08ec5aeff83b85fd101ea725f92d3fbf0ab406ec626399bd388be186fc8f637ab0647cd3bad70a79c9e62cd3658f14b46f1b59d741b853e4ce260b4170299639	\\x27460b95cc44834652ad07102562aa0965f2020806778d1850b23b4ac5eb67d7b13f021122cae2ea9869a5088c5b11ea44dfbf1752a336780bf79a6def495b1cf54927dbab5af099b241fcfbfbf2a3c4b4dbf8ba03a826d9dbe71e04c4c2b7647be06dafb8d5f0fc07edd4990fb830e6d8fd1d80799cc822e06656aaba76741a	\\x96d72626c6249e7ee0ce73e7e8f607a9069fed4e211a5d185c2421af630d7c95	\\xdb07670a04738aebdb6ab0a3e8fc6a7c75f8f2a5f34406eee489243af9aa0f35876b31aa30996078ed3bf087a7356d825fad2961d34e01feac60a2cc7460bb06	1577746866000000	0	11000000
7	\\x24c75113e1498bf95db5f4198f4ff8526f6d84bd1dc8715664fbcedc3fd431f5a863846cbcfe695b522afc579b654b847b906616c84fb90c8110bd206ef33150	\\x08ec5aeff83b85fd101ea725f92d3fbf0ab406ec626399bd388be186fc8f637ab0647cd3bad70a79c9e62cd3658f14b46f1b59d741b853e4ce260b4170299639	\\x38c0140fb43f5ac0aae22125b48b0b3300ea27fef299f62013bcf16d24b66bc61892dba7d660ddee4098d9ce0af0f0a0c3c8ec2fde5c7117bf2726254f8458cfcea051db7fc01edcd8388536f46205bcd64083a3f64015c8ce69efa31a1e9c91e1d0159fad99be0834768dc93f25392e4692e501b84bca719cce4d6c22e6fcb8	\\x96d72626c6249e7ee0ce73e7e8f607a9069fed4e211a5d185c2421af630d7c95	\\xf1dbad379e0124d639018a3a31e973684366eb5d1427bfe3697bfbe3b199d651c70d58f7073972206280ee5b40769db199ab7a7461d1df1826353e9e802b5d04	1577746866000000	0	11000000
8	\\xd0f1c6b5562ef7d37d6fde7ec5269484ee05f3c5dba2c5e22266c7cc36e832ae784e7537abc666a6ec9e8f0386bc7dc443f7bf2a744a21211391e7a7bd6ae5e9	\\x342a53036140a9d41d0d3545d085b4a7e5844982090166231e639a7c773ea72d7ce730ee78d08cb62f7c4b772747abf0621dc6f2de90544337f545e11e000970	\\x670dd5c94225e96c7080f805fdcc0b946857386e51a07e299317444fce3b3f1b65f18991e35a6ab55f707f023c45c68ee435f337a2bf662aefa3e62fa6726566a83982ae14fafc65f651217407e4f1e87f2f440485e1820617ef2d725de5047275930f64b3c42edcefc0713c8485052b1e7e6c14fe31b066f6cd49daadd95c18	\\x96d72626c6249e7ee0ce73e7e8f607a9069fed4e211a5d185c2421af630d7c95	\\xe422727802427a8d57c155ca2750e97cbe6c135e345184e4b20feea2a9cb350e1aa3bd6dc0128cb05666e7fc12f21fdeb6e58283ea966710428ed4553459a30e	1577746866000000	0	2000000
9	\\x8f698619a32c84cef7fcb34dd66d754aa0e8fe73b9dedd331a8347abbaf30e48979ec6cc1b2658b3ab85c657a90caa5ed1ac9e3eb060e34b5c23871b4924bd3a	\\x08ec5aeff83b85fd101ea725f92d3fbf0ab406ec626399bd388be186fc8f637ab0647cd3bad70a79c9e62cd3658f14b46f1b59d741b853e4ce260b4170299639	\\xa042febd656763964008aae136a29d495bc4272e5a555fcc567bab89a9126370ff97d0d9ec4ff19e8299f31094082e9b95951678547c7f289c8d75bd0ef419a1fc45a4a0773f23c872049bc0c157dc05a8b22dcb30b882fccb0901b441431925070124ca6d78ce499653ec7410d4f4430f632589268becdcb98df9eb7fa560f8	\\x96d72626c6249e7ee0ce73e7e8f607a9069fed4e211a5d185c2421af630d7c95	\\x52e39fc9aacd46de5448f1bacfd0bb56a29fadeb20757833b39510b93836bf0e798cee101692e59499db05417866a2f4577d09ed88c520fe1956af7583fac306	1577746866000000	0	11000000
10	\\xdb34044068d11f8dc636752823d222bdabecdfc56f1cc8cddbab14728cb8db659cb12f5dbc6e5640ad2f4ba59a1985727592c0e0479df81aa759909083f3b978	\\x08ec5aeff83b85fd101ea725f92d3fbf0ab406ec626399bd388be186fc8f637ab0647cd3bad70a79c9e62cd3658f14b46f1b59d741b853e4ce260b4170299639	\\x91e1e564dc73c0f27307986a416c09e41f376b37329e5f7298c0b7060943973788066b5cdc3047448ecf84f4e1ec8151ce321abdf1044f71f785de682c4d7bc1cbedd24a95cb180fe90a7797ca0ef1063ab7aab8dfa146aa3eaa1bb18da74b27f7c5f7fdca56ac66bf25da22f1065e6d22e6cec8ac57560a9798e05e606ad99f	\\x96d72626c6249e7ee0ce73e7e8f607a9069fed4e211a5d185c2421af630d7c95	\\x8eac43fe4ab89b6c99dbb271509f38443654668e17271ef5cf552477049740fcc876e4de37d062cb0c3bdf308b06fab7f6b04e53c312dfe4289bb43fc645ef07	1577746866000000	0	11000000
11	\\x2a207e144c72ab97be8447dc4d2e21e0cda0672b1c766e47ead3eac71dcf0f854b59c8e08898fca5d2ed598db370795a8d51c45aa2124e3d8056dfa03bf0beea	\\x342a53036140a9d41d0d3545d085b4a7e5844982090166231e639a7c773ea72d7ce730ee78d08cb62f7c4b772747abf0621dc6f2de90544337f545e11e000970	\\x69a0b8aff25ddb6f198894415528ccd284fbf814672774a60a42d6e5320f66ae323d3da272ba9f2bcd337ebb6a2d2a72895135e45d04375bd48731e8e3d1624f42ea17ac7e3565c26e03b3c4d014fbffd636edbb6539d6c85ea3a97ed9ca79ccb2344c34d8350faff6b842977434cb7583ae1dbb640b87cced2da239f7e16799	\\x96d72626c6249e7ee0ce73e7e8f607a9069fed4e211a5d185c2421af630d7c95	\\x37cf4c1e589908f4a41b7dce7b9535033cca10920a7eb4218c524674aa280a35559c3fc4500a9c843b3ae95ce8f88e05dd370885318f35fe2030e25de23a0c06	1577746866000000	0	2000000
12	\\x2627136f8bc0187a98b7e5198c0817b7d94c132f7b8eaf68fafd88306f40a447483b5372b6eb1afd15b4118beaf9ca39db30bd80033e7fca43bea568d8f7264e	\\x08ec5aeff83b85fd101ea725f92d3fbf0ab406ec626399bd388be186fc8f637ab0647cd3bad70a79c9e62cd3658f14b46f1b59d741b853e4ce260b4170299639	\\x8e405a1836162e24861ce56a7d33cc88d22d94f46d46a66c84ea4c71bdf2a842cfa67060bcfaf3d5819e58c6117f4e636abda4474d1fe64f398098056110355848b0a75c0712c1e96429a9cd6a8e451e270d85242fdccc8fc0251f71a32b3238f902ecd2e9e76dd591e054cd18b66d930124109e607a33199d27666f82923652	\\x96d72626c6249e7ee0ce73e7e8f607a9069fed4e211a5d185c2421af630d7c95	\\xea8390060b161a4dce228ed6add4eade3ffbe5199a9d46a7c68c743addb6fc1acb10100fda7d485a4ac0324178537ad4a4947657b46bab3f95c67d1f83f88e0d	1577746866000000	0	11000000
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

SELECT pg_catalog.setval('public.deposit_confirmations_serial_id_seq', 10, true);


--
-- Name: deposits_deposit_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.deposits_deposit_serial_id_seq', 10, true);


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

