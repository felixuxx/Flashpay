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
auditor-0001	2020-01-17 22:31:05.767815+01	grothoff	{}	{}
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
1	TESTKUDOS:100	Joining bonus	2020-01-17 22:31:12.672672+01	f	11	1
2	TESTKUDOS:10	286RT2V1GH96G2YBF0QQRBMDCX9K12358EXETM26WGF5VM8FYYR0	2020-01-17 22:31:12.776872+01	f	2	11
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
\\x6bc736ca29494fbaee85920fb9df83c292aef215e194737cdfb30b0d2ad8da3d910520561b46594fdaa82c1133d7079811b4ca10567247738616c4d5a47b4fb5	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1579296658000000	1579901458000000	1642368658000000	1673904658000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x29223324063a3b3d44a25d367b3e4e7dc40200f7f27a9db0604f4239b5a752fddd64971baf13844025080896593ee86f0191242d671c58c6e64d629a7c4276c8	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1579901158000000	1580505958000000	1642973158000000	1674509158000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xcf1e956a144d26e5253615e8152e0abb162efcefcf99207b7f1b4d99c9f4af19615b35ad65dfeea1c33ce7ed1cf29161dd6e32f6e34c32b0090165b4026f5206	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1580505658000000	1581110458000000	1643577658000000	1675113658000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe67fe8749d391279c597ae176b345cfea0af234cf32056aaf2adba4a2490d4afff22680dbbad721f2c28e42a6028590abd2b1cd97faece363f088332f3baecc7	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1581110158000000	1581714958000000	1644182158000000	1675718158000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd8f9c8775de80104f1ac63f2a97291d1e6b2fbf028ff8f0fb8e25bf3ba2306ee2b4e53a76ee029f46d17e6c8d89ceedbb525f9ae812347d81f2fea0b9ad45000	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1581714658000000	1582319458000000	1644786658000000	1676322658000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2273ca4b9a825cb3f1b0c30817e80731eb28cb9d71d1815b29845a52c817ca63a38c2c5445e7a140c50494dc2ab70eaacaff903c9cb85fef9f3563dfb1ab6141	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1582319158000000	1582923958000000	1645391158000000	1676927158000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1558b74514981caad9aa3d72b7ad8d206aab9532e5f7516520a2072b7fac73d1f3f9ff9715d8366b07bfd913fa30d45e639091c1d22dafa5fa0d1947c9c1df1e	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1582923658000000	1583528458000000	1645995658000000	1677531658000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1a272257fe7d91f7a3eb41c2927edd89cfb272281f35e781e43279f1ea19ff4ce6fd618f2315792a70e53665f90158351012adb751a05a55a9037a84ef595a01	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1583528158000000	1584132958000000	1646600158000000	1678136158000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8851b03b8cc78911c3193a1aff20a0a11a44547e466105dde22d424b52cd7591fa4ab17235ef0f4a4a74a4d36f3d510356c126d19352b36f2ebacab17d807d6c	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1584132658000000	1584737458000000	1647204658000000	1678740658000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7c3dcb3f23cf6213ce9bff23b8d166d92b8b5b46dad1a90a9ec2c1d815bd5ea35ef4ac62f2bafc59f6dc4ed426afa92c135888b27e3f1199463e002182e50d21	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1584737158000000	1585341958000000	1647809158000000	1679345158000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3cf93f4ad7713cb6294cd6ea8c5e0569957aa02b284bae5ee1c56bdefc537e9b3fd4b5e59731358f3e03d2278a69463761d01547333a85d7a8a97486496a39ee	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1585341658000000	1585946458000000	1648413658000000	1679949658000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5ce529e4a1d0376a0edbc77419f4efc3ae0150970556e2ef176f4b42180a5c17c93fda05a61b6ac024d62f86e7f5022405dd61076c1a351f3722606933aa91e2	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1585946158000000	1586550958000000	1649018158000000	1680554158000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd9d5fb9f5f152b65c5f1e8f10c3df2a895a1094ff2f0bb00a6794864cc5277e2b6b1a1829d2bb2c73f8269d6863792102e24af5ac1f4fde26e4ff58db7bcc3b2	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1586550658000000	1587155458000000	1649622658000000	1681158658000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xba33b4ea0d1d33cc6b125716a7385c504fcbefd98fdcdbcb214e435752980b4098ec0874265f6092cac231fc117581b4c7df3d200642dc39bfbaec57cc969187	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1587155158000000	1587759958000000	1650227158000000	1681763158000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x19efbe047d6eb9ddcb658d1a1fcec502526545d58ed637c2f1c46b3299554d85518bc6d1f677e1851610f4d707e439e5ffdc53bdb052445805a19fa6b2d12db1	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1587759658000000	1588364458000000	1650831658000000	1682367658000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe7bd1a4b7b3ba132e52ab14de8e10666aac31cf3e1e84006259b395f28f1370b8931477847bf88f22aa59a39d244b6b6e8dc69ed638ecdc41df6d4d5f03fc6f7	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1588364158000000	1588968958000000	1651436158000000	1682972158000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x354226b3ef740456a8042667140a398f72f43853d5687af6408c66edda01599f193c4ad672df205d8c5656bca95e4533b07d646c2336409e2e3eb4ed59c4289d	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1588968658000000	1589573458000000	1652040658000000	1683576658000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5c3ca4c1df620f7c5b8af4bc1121d43793745a381e7f1f10c214e773da465957cf41e999671255082863c6ea1ea643e945157bc69a6b7d0a2f8f3c873110e356	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1589573158000000	1590177958000000	1652645158000000	1684181158000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa92b3d503dbf00563f12e5465fb75d61308919ce6dff17d38a69902f94911a4324c41872829bd12c4480a79bfd8cadab1079d7b94408d390fbd726e74eaa102e	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1590177658000000	1590782458000000	1653249658000000	1684785658000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x84c14bf71ba7e1e1d35cadb92a8eef52aa12fb6657dcc38372f58e1379b9fec9e9c62afd1eab09cf8c38ab9db14c9cfa89c8b281a23bd696fdf1010a8b5a1d3e	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1590782158000000	1591386958000000	1653854158000000	1685390158000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x79fbe598fa2ebd96dbe4841d92d7815673bad7cc45ff223e91c7529f5d2c8da8f63b774d9b8b213c35c9ce532dbaa6dd8bd485d1b1da3658398d463f22fa8bd9	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1591386658000000	1591991458000000	1654458658000000	1685994658000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf49650e3c1cc71cf7f5c7cc50d2ebd543e5c8582733d69676a4f2ff8d61bff437702279bb2039c4cb0996a11dfd680225d584a6fc319aee1503cb31d8ae86cdf	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1591991158000000	1592595958000000	1655063158000000	1686599158000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x00ecc5215d91b8bb69554cd13f36a86dcd6b3deecb4f9533f02050c78c223245c3673f6cf5114fba144c601e111aef932dbf3ff636b3f73e6eb3f5f5f4f8584c	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1592595658000000	1593200458000000	1655667658000000	1687203658000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xff271dd748302efe7f23c0c44a11a215379ce5132e59cb5bac109a7b404ddabaf90533063597705fa554f99a2ac3083e9ad2423ae206f727c34cccac0912afb1	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1593200158000000	1593804958000000	1656272158000000	1687808158000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xadee9ca42501e1749ff3d104e1268ea73610cf038850d3c2e140da8baadaf0c8e3048f5401c6ab61c183a98a4ecd119b565601f2217a29ec91cc4d955962ac97	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1593804658000000	1594409458000000	1656876658000000	1688412658000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x72c960655961dd984980f77f939edd0a3d0a5cc829f5d3dfe7caa61fd144f3a726245af72a53a64bc0cd76690caae078028a591a389981d8c2119548d3ac1fb3	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1594409158000000	1595013958000000	1657481158000000	1689017158000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x32100ca1caffbddd691d549ea5cb9194826383f5952e0e7c68320e811f67628d59c655d8005e447f160394d808975c0733b2b56351478a7d23ec49209c7023d8	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1595013658000000	1595618458000000	1658085658000000	1689621658000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe1cde970000b269e1c6a4112b9e14343819bbd2a841083d94cf4784c6c82cc0ee8f51696316abad0eb038fbccdd1b195aa2a75c19167f42a0939012f89342860	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1595618158000000	1596222958000000	1658690158000000	1690226158000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xeec19d00977c7b3e1cdd2d65566795e7b397f10214448073000a933b3b0e58f29724bb52a3957961dced70d014478feccbf7c9cc8d948723b2bf2ab2b55e86c9	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1596222658000000	1596827458000000	1659294658000000	1690830658000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa051455bddff8e5d76595941753b8e55bad720746744a66178fba634b5324a72b38428c064ab84f1fadcabe996893e40382dbcb268bd15f48b901ad3ff08d0cc	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1596827158000000	1597431958000000	1659899158000000	1691435158000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xcaef322d49fe0a1e9e9e0bed0ee5b29d6858bfef582b09da4417446cd430a5f86bb793e9d4d2cb29e600041f5467dff2de771be3814ad5d1d4784dfa3a388b7e	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1597431658000000	1598036458000000	1660503658000000	1692039658000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x77a65c802b1bd1b5a7c5d7056a946177b41990348fb3f07f65ed2134a647f3e3260b438c6be9236754d38b2fe7491bea62a03e36ad35b4372fa7cbea74a3f4c0	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1598036158000000	1598640958000000	1661108158000000	1692644158000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa4568bbaec9299ac990522ab3569bcbc9e6a4385e470a83b972a4276321548001f6a2704761b6b24cb3e33f78c54dececd660263177c66dd667830c41e75d0c1	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1598640658000000	1599245458000000	1661712658000000	1693248658000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x41bed9d057044697957d04dabe53d8877569b9ee9eb1c13634e3a2742ee601c4ef00530b6acd182764bbe3d36742807ebc6e753f8f97801bcecfd29b39ed6a2e	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1579296658000000	1579901458000000	1642368658000000	1673904658000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x98c3a6684081835f954a9bf9a6fdc597b64b195a3c057b9b5354b80989c27ea5f6b0cb80e18e3da5c9034d20e59ebf55f82787bdc40b023486b86f0c22023bf9	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1579901158000000	1580505958000000	1642973158000000	1674509158000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x6440b17f894e3f08621cc8fe194fcf322f468f8c23b668b0254ba93d7a2e5a634fe1235e3d1940e14ed3d8e663fbf57bc00bed255ad484efc26554872e68e067	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1580505658000000	1581110458000000	1643577658000000	1675113658000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x002f5c6b67e908a59912aa86a46f762a7c09b28edc9941bde1093187690e4b7d347253f4105c253ff180554efa20e4b4dd41492bdd00eb75b59f65784ae6e711	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1581110158000000	1581714958000000	1644182158000000	1675718158000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xea07964cec0f2280b6c3b963c025c33fe98c337cf8523808eacfa14c812c483e752d1a96b1e75bfebf3dc4a8a051bf9a1e013d1c7f168af6c7bbbab4a2980b84	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1581714658000000	1582319458000000	1644786658000000	1676322658000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x60e366b272b70d51c746a2fbfb1a0e7a28bd62793fea1c72a9ed55562bbaae397ff59a74e897f44e70578e2bc306353cee8a1470f90243ecb4bc41bfbbfc661c	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1582319158000000	1582923958000000	1645391158000000	1676927158000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xff16d3b88f6152065cf8caccada11a49111b01ae6f58e53cc56e5c0dd402fd2cc6fabff138e5e0e850341c4c90ba7fb5afdd11341d99f5f2829b53c819b814a7	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1582923658000000	1583528458000000	1645995658000000	1677531658000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xe2422fc2f82047a8853510d8627fae08924f4a37007e2c157e2f9072abc0f6c454ac98e7da1af7d6eee96fe4de67454917309bd934a7ae9b175d46d3ec2dc84c	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1583528158000000	1584132958000000	1646600158000000	1678136158000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x352f66b430ab05209f4bdf97d5b3dd659b85bc2b8357c2738eaf719de62b64000a37742f4ad0fda68d7847e5caafcc67d63c85ee8b0edb62a6b8fc44d9f7357b	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1584132658000000	1584737458000000	1647204658000000	1678740658000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xb66b257707560f7ed197bf54b9360674d68fe4364009030284730621c69716df3d9dbc23daebf777fe6af0881f310948617cc3590d69cc2c54c2ddc28d074e17	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1584737158000000	1585341958000000	1647809158000000	1679345158000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xcca08e6c36df98e56bcc33aa6fd49e48c65b241b3fbf27e6e3c12011f4bda29f9b06c5cabc31265c61a633ef99d7ac699e532a51bf72f3011175822253fe4d8b	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1585341658000000	1585946458000000	1648413658000000	1679949658000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x7cd6f3deb9800b66d1805f4ee2126f5b1106e5273b38749c5723a16acb444f2579ce430e000d79613407b33dfe38dd30b5f51820b7fecbcfcf81f90957b82b55	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1585946158000000	1586550958000000	1649018158000000	1680554158000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x1f259758bd6c6c6e038b2e2bbe09eb49ca91d875c341891491306e4604157038481a8b4aa84c281eb87977f0c349c719d228269f44767f518037ddbdc4b6ae5f	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1586550658000000	1587155458000000	1649622658000000	1681158658000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x005286fe004464a68ba83ca9c46377ac48465d27576e22f3f53244ae013a30d3cb53a15b965d3162909f5ba2c4f42eb9d873581c72c30e5ba7ec83ce741966a6	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1587155158000000	1587759958000000	1650227158000000	1681763158000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xed49b5430a2954f20a838dd86e39fb9ca3f7398f8956254ca55dea78bab9cdb0b9e6b553c9bcadf727c423fb8664d50afc5829c400375c3b34e95ecd37be965e	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1587759658000000	1588364458000000	1650831658000000	1682367658000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xdcf40c76dca884fa98c6fcc1007901b972e1d5534317e712761c6e8dad5db03e889480572493ac08858f4e8fa1cec9f45449480efbd2b63cafdf37f426c65755	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1588364158000000	1588968958000000	1651436158000000	1682972158000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x5a8fa3fde49f50935c5901e0c73f5715b0c0760bac8c254894fb72f0405fc3551a17b7e3f442a74810bb39976da0b13f74cde906651c8bacb846967b4f4709fb	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1588968658000000	1589573458000000	1652040658000000	1683576658000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x686509e2dbdbbd0a18b3fcf3308899a7ce577742c2cba2f2594bef6b3812af8e6ae535f0974c6a342a255cc766447352024468a869c19947adb45e70671a76dc	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1589573158000000	1590177958000000	1652645158000000	1684181158000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x19bca4efe2754e269d8bd541702c63e2d5c3846d1966595ff0290ad295d9bafa5c7e008355ab83d231854854da6b686d9342a3bc18330d50c261b368c8783f2d	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1590177658000000	1590782458000000	1653249658000000	1684785658000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x3a69572d0c5e7e35536dab33d392ba65b39c6b93f65b45fe52cab280cc9aab373dd1b5f6e198c611543166319add63b77c8c56128f828502bff58eff91d51a78	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1590782158000000	1591386958000000	1653854158000000	1685390158000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x0f1132ec1dd9c6c3c11fb3053370a1c874b22f698549ba2a884682dc0677da158f8621777f2a01c5373f98a3406515a08cea1b41c80e173940490a2408e144ed	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1591386658000000	1591991458000000	1654458658000000	1685994658000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x6a64cb3ffadb84efa666c1ea782eb8486f856a8ebcbf00c5a89ccf2782a4b29931c0971106a7937dd7a740fce47a4780c48c6a5d3516f279dd0ed66ae77b0f7b	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1591991158000000	1592595958000000	1655063158000000	1686599158000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x4e5c176df56895e16e5e96785c52ee18123857e0c8fb46e67ff07a2061c58d474d43bd1bca4decedd35aff2b05bc4f996731f5115a7786c5fbe79088176cabfc	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1592595658000000	1593200458000000	1655667658000000	1687203658000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xab50b8999183268cee1fd414d1ca9956e47a83f0193f77d48cc097038ff87c506ba3cfe9a4a8012b9efb5accf83c34349115fe7a2045ae0d9b158a3533cc8fd1	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1593200158000000	1593804958000000	1656272158000000	1687808158000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xda28e36ab2c5cd374f2099b77260c299d542b4c00441fa1baa655fadd2d322a46ab28514ca94ef457cc67d9ce8a76665d53ec376e75f27f4558fe03e31880495	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1593804658000000	1594409458000000	1656876658000000	1688412658000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x26d3d5ddd3d3401ee2eff86289ad7d89603c36bbd3bd8b8c107d46d336d890bd3b23039d35d8557c0424b406de02ec055159fef73e924d5b44f7df143c917585	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1594409158000000	1595013958000000	1657481158000000	1689017158000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xbb24068f184f7c2321256e8113e03c16f7b4a48b376c86d65dc56bda88f97e1c990511c9dee444434c93ce20e1f974ff345063b18030eb5cacdd58e8bd13d295	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1595013658000000	1595618458000000	1658085658000000	1689621658000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x5e946726992852af06797706899deef41eed2f59cba13d0fbb42c4a74dc985f3550b75265aa3d7e11724fea9375702cc52cdcf720a8816fd01b916bb034e8b0c	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1595618158000000	1596222958000000	1658690158000000	1690226158000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x4efedbf819c6bb40af93839b4b56bd50b7c706077236ca650f9b277fa649d716ad225b514fad868981918157b7ea5490d953d719bbd95822be05f513b61a64ed	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1596222658000000	1596827458000000	1659294658000000	1690830658000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x90b3fb07b14c5841b1d485a17fc2c1b603bbb781252eba439803640b4823f8432640324d6f70bc9025246866649fcd2f47208efa8f1104b6c8be5eeb5cf529ea	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1596827158000000	1597431958000000	1659899158000000	1691435158000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xe0ac9fc4665120d2853011b92f1647b0d870d32daf23498213c9cefa0a69529863bf4ec9cd27f16fa17bf6bffbdae1d32e06924c940297ea54436133ee98b5a2	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1597431658000000	1598036458000000	1660503658000000	1692039658000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xf1dc115a64b256bd8016a3683c1bee29ffeba3c42aab34ed411d3324f0791188026eef3e24e894f2cab02e06b10f167830362f4a258bfed05e2be7eb27cbe1df	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1598036158000000	1598640958000000	1661108158000000	1692644158000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x861b231dc12796b25850ec70f614a69c8a7aec2a0d7592a6996d47da2ccbe34023183407603d29eae096285cdfdf5fbcc344a6a10176a8bc96a4a6327c8997c7	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1598640658000000	1599245458000000	1661712658000000	1693248658000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x506e943609e343a2b7f2c8b8f51909d2b815a5df513fdca576146c65f474bcfc2fd7b527656a0428b92121d488fb887ade16875b915cb513efa5cf352599c6a7	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1579296658000000	1579901458000000	1642368658000000	1673904658000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x610e9da754016f8c1f9f3571b16ec1c051dad1e5b69c15f01d0aea8e0e451400178478b29f0a2d405c43b0bddef9a480fd9cebf40cf2092d796bca2c08b392cc	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1579901158000000	1580505958000000	1642973158000000	1674509158000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x44aeca3d88927170c5f70367dc9fc830cfd8af65bec37b03a0002691a601228fa41de88a496ccd79c60f116c2d89e8c8fdfbb8151e748978f5f93c4e45cd19c5	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1580505658000000	1581110458000000	1643577658000000	1675113658000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd79f56b79336a12c455c9ac3627d9155624d0a0a2718edf472700f4ccabab2f061b3a22ac510b3dee72c93948225bb7e306dc7167bca39392df83c628b036dac	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1581110158000000	1581714958000000	1644182158000000	1675718158000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x14b53e722c9fe1262f198b8ff940f263c188e7a48b11a32707d9b6e8d953c38867dd91f612fd29e46b2491dbe8e17d06e5610462a8b7b60bc5375bfe985dd0d2	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1581714658000000	1582319458000000	1644786658000000	1676322658000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4c8072d429f5343bc175c2ec7afc1058e3921352406221949362c2a809eefca901f35fbe8178c0f73b101450780e236f637c2d24c1c9e6cb09f4e001cc0d2afb	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1582319158000000	1582923958000000	1645391158000000	1676927158000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3068f607d8c74f43ca5d3e960a41a768d320e67f50594ad30ed19b7764e46ca682fc737eef8523be4a5c89eb1aa92036df73efd27ce93b566ef792e71d0a4e61	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1582923658000000	1583528458000000	1645995658000000	1677531658000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x772cb496cebfdcdb9c8eb3c8af43939eef6b69e422455798cd4fa12d1a9508bee21c1b7d9c529cc5831665e21161b5a05a398dbd5412fd5296dc8db7e805fa79	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1583528158000000	1584132958000000	1646600158000000	1678136158000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3687cd2a7083f1345757a9d5d7f1ab54817a80c11d2ef5e850dbe2281750c9afe37486bec83c1357cbff1158d3e5b9a6bc176d9d393a11bcfa752ed64c6b38b8	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1584132658000000	1584737458000000	1647204658000000	1678740658000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x78c2fb7211fd6fb148ec5d1fdf5fc64d60216af4f8dec36cc8a20febca971f10d9e075d3c9eef85c795e0475e41271682b6e4569892e62d074fad2b597711b18	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1584737158000000	1585341958000000	1647809158000000	1679345158000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7e7800fa10a860ff38d5c148eff4ca561e785af151d327f10951189edf9de235a9e12d30f640aabb4d330bf14c7668a7d7ddc5617e44f885dff035b896de5d21	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1585341658000000	1585946458000000	1648413658000000	1679949658000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xadcfd19ad9c12374e8422b71a8f8c82bb050eadb1964fa35cfec144b71abee6f8b12199cdf028e12b179e9696d1bcc526886a97b9e7f60ebae67ce2acf78ca06	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1585946158000000	1586550958000000	1649018158000000	1680554158000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc8aafe5bfc98b245ef5c4618002e80c023da10dcacc37b5e63f730ab3c953ae12830e521d871bba00c46e96a5c88d95d212d76a06c2f3330c4752f4719f25cc4	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1586550658000000	1587155458000000	1649622658000000	1681158658000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x74089c64c678339dded3bfbe331d581f9769ee72caa7f05a7849b1907eee4e3100aa4f6c0dead44c614291fc661865685a21f4ae49dbcd3e2b0cfece18a855dd	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1587155158000000	1587759958000000	1650227158000000	1681763158000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x70a327fbbb0c165e0b403fd8445430746cbc3f9787bf45e97d54297ba0f44b4e9436598d237ddeffed704281495a2f34fad4659c3579781ca0644bac35227a57	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1587759658000000	1588364458000000	1650831658000000	1682367658000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa397c364b972ee128a1ee6181d9ac8b351b9fc1c5593a4cc6b8644f8aefca9464f9a0e617da3a18f50680e5e4a2c1f061f25883f321b84ce1ee72bfafddf9fb4	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1588364158000000	1588968958000000	1651436158000000	1682972158000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xcdf315909a99550f63d7eb9fa1bce03da6dbe2146b4247bc83c6da3213fc0363ce9ed2bee7a4c15c8ffe00946e800b15367e13e64ea59cac558965cdfb6e8f1d	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1588968658000000	1589573458000000	1652040658000000	1683576658000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xfd50ea778dea5e9b488090465abbefb2dcc88e98ec25540ede5e2216a084fed3256d506ff57084ba98d9a36cc5fb25ab0552998b4c608671cc8e24b48c75a6e8	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1589573158000000	1590177958000000	1652645158000000	1684181158000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x81e7193513830754f77e1e4c3d392363a95f8265e07b74cc0c8051b759135940ef9b35e596c5e218c442e6f6142c630370a08ad07b13cc8b506cb1cfe38ad239	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1590177658000000	1590782458000000	1653249658000000	1684785658000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd1be3f144b4587d340ad103c3188b277cedaae04d5d9cd5b5538a9bcf441cfe3d124ec5ca3912fbbbcc6354ed1f57bf197f70af5a95eb84f12afc3f85458ec20	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1590782158000000	1591386958000000	1653854158000000	1685390158000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xbfa382cb7471cde1009ff621dad437d6e24655e555a97a67f3982451e321264badea2ac5b88942632498d97eb04efdfe6d437787d614f6a1978d91e501117aef	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1591386658000000	1591991458000000	1654458658000000	1685994658000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3af58411c487aa68c3a1a684cc9e415d11b53aa486f71b1cdca2647a79aa85267712f88a3412df5dbae4c85b41a50a82a9a73f5aa7794aa0bfd6fb53fe2e7fc8	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1591991158000000	1592595958000000	1655063158000000	1686599158000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf4bf65befa6af0655f1ec2019e6f1714c628c786311f18132ffbfb19466191e06fea5fe44ee73cda398acfb16dc8d4f465e8a8486b13e29418e85467f9dce1d8	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1592595658000000	1593200458000000	1655667658000000	1687203658000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe1622405a3cd3eac2d9a3be2704ad886641ad000dab6a4af157dbd6eeed5ed93e2f92b599e0c5346dcfc964d341ab6a33ca33001daf92fb0d87c255bb8b340a7	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1593200158000000	1593804958000000	1656272158000000	1687808158000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x80c7be98963107832a3d1bc3a9d565be86ce6293a54f6a5092a596e8345159662d082e1745357d672ce595a021ca665c74bb5f4fd63a7b7a1df335ed756b035a	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1593804658000000	1594409458000000	1656876658000000	1688412658000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x48b60cd686aafdb200cdaae6376a0629e731f9a7d9b2a6ec04e65fd32db17fe1776079249dbc5ca80f609ff21443550bbe332a4bab40d05ecb9f4b105c05357a	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1594409158000000	1595013958000000	1657481158000000	1689017158000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5324bc6007cdd02c3f618ad0bdb5f266ca600a9e3374d6e0e7678302c5a3a05bb9d7f7f4572f5f26e6ef59961130b22829fe564f44c17a98ee9f375dfab76a8b	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1595013658000000	1595618458000000	1658085658000000	1689621658000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2b8da1f15b93756ecb7bb332b1be7f3b03bd8c78b47f9c0787bc2c4e7b02e0d8c9089fd367a5c9cddb87487e74500eb33806c069c29fac593bbcea22958f93db	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1595618158000000	1596222958000000	1658690158000000	1690226158000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x181d64b9baab509072637c1aab0d0333f1fe80a4343a0a3ed97caa033fc1397ca33d447bf52573567f137777e67c50b5cff5a67c1d58a2897c522bcede14b6c8	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1596222658000000	1596827458000000	1659294658000000	1690830658000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa7b2bd3ba2ebb39aa254999e4dfdc7a13330ed35a3e1d249636229b48c01cb972fce898909acbeb8c3ad07b8f298bc9a83922dd70ce7f56ac7fa11796bbc1dc0	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1596827158000000	1597431958000000	1659899158000000	1691435158000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x37ce75034f050b7acd34f49cdb25e84cc942a474089aeca97ce8cad7439526405d3e3a5232f66ce1219905ec56822ad3abc01ecbfc661194e857d843a7e95c4d	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1597431658000000	1598036458000000	1660503658000000	1692039658000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xcc088a89ef0ec9a23945f3166901a67ae95410158c3887c27797d7de8f51ba6787cf3782da26fb8a26c5a9c2e084406b95920b15f284d079136c9b39d6d31cb2	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1598036158000000	1598640958000000	1661108158000000	1692644158000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4fe40c1669346e3a7c23f12dca73cb8d96680da6a972d1c09ecc8fdddc7f85c4ca2c54cdf4f58e97975d3c482d595bd059e37db634d20a36c5c9f070a7492de8	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1598640658000000	1599245458000000	1661712658000000	1693248658000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9504c7abe66b7b6570c4857d4ba7f889c9c15e91a557beff66f5dfd4f61a85930b7e569af2cb318aaadce1bcaa201e7a14ace12e93cf80658b6faa51faf2e634	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1579296658000000	1579901458000000	1642368658000000	1673904658000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6397124ea49ec38cc86f57a1c52b4dd193a5178562a8f46caa398382d46fd0c1fe4177f911d9d828ecef529d6371946c65cc63f98b235b8f3d5d71dd8a590f66	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1579901158000000	1580505958000000	1642973158000000	1674509158000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xcaf97e6c43cff114574e524f44a4415245fcd291e5376aa19b8698d37699b2b05f07d8358d59d80f1c7523406241e9ba2f0e46db33d0079412e35a077a6f5951	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1580505658000000	1581110458000000	1643577658000000	1675113658000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x996067a4a7f0a48a29e023ab888eb69fb7dcd604cd2b48055d3f39e42237621bc906453b0a6377894b728487a0c800a3a0ceb203538ca6dc10014445c39dfb7c	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1581110158000000	1581714958000000	1644182158000000	1675718158000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa935bdf9b9e4327d8b2c059a0dc112656f4a8989752ae9e0cb51840df90748c13829e73115b545d8a92945a43ddef7f2be9fcd45562e40a6f75f0faf42bd62bf	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1581714658000000	1582319458000000	1644786658000000	1676322658000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x400c731a072fac5377384ebd28cdd7c7da2d71831d09e36591885952a0c27a74260e427c48488d1f8fa589de7a3019567a0e1234b0d6b538664c60741af7790b	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1582319158000000	1582923958000000	1645391158000000	1676927158000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x98c7f074e3f537479ee90b018618e620398713bab550dd16135889aa7ca083aff2129b074f6e80a687cf5681ff6286f17fb4ab8e92b3a289230df86ba2cc1236	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1582923658000000	1583528458000000	1645995658000000	1677531658000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa3ff7ee9bc709f7b9fd3c4f00f6f9013cbb70eb698436dc9583024ac88c618c91590758cd747167c13242066f1d5b395a0f0319f775a60dd60b966a05a9be0b2	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1583528158000000	1584132958000000	1646600158000000	1678136158000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7ca76d576e0b060fb425cad5114a6c802635c680382665679530de51b096b5b9f066c0d09565b5c699af488c49dde9a2120e08711c1d9a2df15e788464cfea4c	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1584132658000000	1584737458000000	1647204658000000	1678740658000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xaa3f375f5fc980ff6995c5e9e052241a355a69839d4b1d8e6ca72da8b40fc677743a6a00a9a0c16a0b3957e1a3754c71c2f354dd2b2c9988b0ebf1b4ce7759c3	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1584737158000000	1585341958000000	1647809158000000	1679345158000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9ce8f1d4ad1d82562d471dd59325da8bd8ec6cf74799a7263075d5485b757e1c92844a16e262f05172d1e3c25612697228d8c25c3b738aa9c9f0b5ae4d848d64	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1585341658000000	1585946458000000	1648413658000000	1679949658000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9678a6fcd2d370bc7dbc400da00aa2726298456ec178fda76c0e201a12cb5b5541f536a3e9b744912ee18b01e3d7b05a1d830dd457023d5c8431daaec72d107d	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1585946158000000	1586550958000000	1649018158000000	1680554158000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xdcfe78a2f14ad96bdad7c64686fbb92cf1cc8a61edada47781ec2f1a7f6a832b6ca6e68916394540b92dd0f3b771a7529000707232b1e025f62ce2ab3b16260e	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1586550658000000	1587155458000000	1649622658000000	1681158658000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa3c50db10b78a7fccac1b1b0ee6106e046651900449b77fe56a649544f0bfd1f74ee22b4b73b1e6418ede169e28fcf2591a789f64532668eddd2d64820e3889e	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1587155158000000	1587759958000000	1650227158000000	1681763158000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x748eeae1df1ac2dadfc66a264cc498fd95fd6b7e58f1cfdb2a9b19861f844bd66cae4738d1bbb03ff11a041ff03f76a129b3463181a8704fbb5be8ad17e733a2	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1587759658000000	1588364458000000	1650831658000000	1682367658000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf3e24181ff6259d90dd7eece4af2c9264fb14607ef069070b0a3a954963d20dffe43fc505b9fbdfbf308c199ec608dc2584fe3a52f1c36016156ac6b95def6b4	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1588364158000000	1588968958000000	1651436158000000	1682972158000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x08719d8aa1cd1c8a16a1afcccfc679800d3817d457f62d83a7d092af941783ea2650670f83a792ee038dbad6a60d82db373371a0695df84312a5bac9790776eb	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1588968658000000	1589573458000000	1652040658000000	1683576658000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7f2b119c2fde18c08c4017da95c7a0855cb9f66aa089e108f3f93299b5504a0731f465f1bb48cd7bb482f2fa2583463ef4556c07517e9f1e759249459cbbb0d8	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1589573158000000	1590177958000000	1652645158000000	1684181158000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb7f2b8f5821b00b0d3ba3b0c7bdb5a618be59f95a0652d0a5eddf7919b3bb342ca273ad60f3cd27fd00187cdc3f1a07ed861dad673959a0b87072cf140feb2b5	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1590177658000000	1590782458000000	1653249658000000	1684785658000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x52e57fc1a9aab95a524c6b3725309f1a12c0cf80aeae5c384c0b9e1030c4606a0a0487401fa4e7713de7f519b0ce232d91e758cfee49beec782d782d8b0a32a0	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1590782158000000	1591386958000000	1653854158000000	1685390158000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7c4ad72c0e0e99fd9bfd2c825c0d7acffc8ae5924945f972a2b10dc2d22badfa91bc15c5ab8b344a6a591fa4f0cf7c4e1f831a5954a1b72cb65ee7e7ad5f93bc	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1591386658000000	1591991458000000	1654458658000000	1685994658000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9b4d3daadbf1c72447534d687da9477837940dd286f7879a25ee2de600eec698968ca014a0feb595bba20f963ed86b34c0fd25c76a67ee2cd1a479478db2a417	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1591991158000000	1592595958000000	1655063158000000	1686599158000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xdf82b858afd978de91bac3973590edd70ef7d4e7090ae91ed7f3eccd02cf60d1c36a8f3ecc6b6a318cb57d17ccf9b1d1c58de941fb0538388a37bc317d245a10	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1592595658000000	1593200458000000	1655667658000000	1687203658000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x3377a55b675ec54d263847dbf77edcb5cbbb15897d81ed1f6aeb48bfb88e01ed1b1d98fa80520a0f132ebca445786ca7a2e6051a175503bac30184afd751bb90	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1593200158000000	1593804958000000	1656272158000000	1687808158000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1654947b4556783f0d22db099469965ae90d44b6e9f8897d096c43fb05103fb248df671e6afaab65959059c4f88258b8f1cfd8e8757d3deb9f2f78a8b472a41d	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1593804658000000	1594409458000000	1656876658000000	1688412658000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd91217d5fb1c82731011c82cfcf12ab2cce13a5e2cda5a8b4bff70e5e69bc6a0f9a014912a18b4aa88d9f4b068782a203eef4df5caa1bbc58e9cbf82fce50ff8	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1594409158000000	1595013958000000	1657481158000000	1689017158000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xfb95694aacfb6ce009672535ead16c04b91f30697de1a8e26d329a3e8eb42df646b872533aa983dc6e08b742d5b402021fd21025354d2f7a4d14cca32c12347e	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1595013658000000	1595618458000000	1658085658000000	1689621658000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8a089819d8e5deecda7c546ea1337c5b9ebb29313c643c89c06b103f2d0e9721c74424461dc08a98a0495cfb80a5a6db7374ffddeb0ff3fa785d0f68bc5f19f0	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1595618158000000	1596222958000000	1658690158000000	1690226158000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x00164d65eb82d1555ad5dcf9ea0fd7cfc5000507970bb0604d3ca8475a3a495c88727a2f62b567d20b65bff56bea4ab0b4565517b6d109b0243d1458183fa9d3	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1596222658000000	1596827458000000	1659294658000000	1690830658000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xbc2e64176c2c476d13bc9f85b55c9c748aa565eed28ca83c8974196a439b2b55b92b72c537b7f1fba38cce5f8c9465bd285f39e234a4731bd19c22a749d99b33	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1596827158000000	1597431958000000	1659899158000000	1691435158000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5025467741edf4ff0b4a5a7985d3c3e24975942113afe5a628bb32dba6b10824efeca76883a24f77d30b77444a8528164ee4526979d6ad96421cceacbd9ef862	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1597431658000000	1598036458000000	1660503658000000	1692039658000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xfef6a9b79d834921c3765bbfd6d62e74041ee3b81283503b9cf4b4a7f08c4fe6264b925b50f15688745fe7a16390dd178cad207b1a37e3a4c03ccd2183427317	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1598036158000000	1598640958000000	1661108158000000	1692644158000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc099a6cd13d39a787732aa005a7bb22c0f6aefb4afd2c6da41478340d5bd39662b47f4f4f582cd6cf980a461c4f64d46df1e66ec7177625d857eaac1a855bd2f	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1598640658000000	1599245458000000	1661712658000000	1693248658000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xdccf72d6b659c6bb3a502ad04fd29a6c47e8515fa798917187d0cacdbcac0403fd9da520c47af009baa4604f7bafacf0ee01628992fa412cd164c42ac99f6c6b	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1579296658000000	1579901458000000	1642368658000000	1673904658000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x71ea92e6ed10cbdb20ede76b0296a28c43c6b4a24cb4696d55cc950f4e2204f0e63d2875ba04197bea3d36f818876c63d5c6b42a7d5a13fd09da33dee449d76b	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1579901158000000	1580505958000000	1642973158000000	1674509158000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x0e86fd5c6701b45753eb7029dd9c325d5bfde421dcb1c07e7dd2407a99940f6c7c0a3b559d58b1aa241eea2cffab4adb5e82c8d3eced0520a9cc18a34eb4dd09	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1580505658000000	1581110458000000	1643577658000000	1675113658000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf27067484b136ce3e4b805af00cceee99529f3c9f5672a0c090bc4adceaa2fb4e212bc1515262efcff93cd7dc3e363963dd31456c8bc7690a54dca6c3a841d70	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1581110158000000	1581714958000000	1644182158000000	1675718158000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf3f900f3a9b74efec1336f13721060f457f4215d46268db9eda0d659289067a3f9f25090951a114d13965e714af94effccbe6601b655fa80ba29dea09369fbbb	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1581714658000000	1582319458000000	1644786658000000	1676322658000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa1e1516e2f5d6736ddbd3e8eac795b6792a28938d8426b0b96c1f91bbbe32ada4770ff779d56fc4ad89ebbdbf9cf4803e3d83c87e9fefa5cb60cd5014a33558c	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1582319158000000	1582923958000000	1645391158000000	1676927158000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1e44e97cd9610746bfb9b9e9a3ab0ad27145d631375162f049104198b58cb2565e781515f257502df90fdd589540831ca5c63a6eee925060684fa5ce21b020a0	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1582923658000000	1583528458000000	1645995658000000	1677531658000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe8f417a065ca2dfe95374b7d0bdcd4d7138212821ec8b7a50f94422bf75c1a882a569e2453b40bb10328bb2ebb0f040bc14336dabdf7e946cfa58c224ff125ca	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1583528158000000	1584132958000000	1646600158000000	1678136158000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc64a3f1d1c6cb0ce355bb0ffe424feace83715b9b39a3e8b37662140a8e5fff220d53632e6ae252da5d2c2f322202e33659c1561bbbb4a5af25edf93255fa2c7	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1584132658000000	1584737458000000	1647204658000000	1678740658000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x15c82bdd17921058ae8bffac5986b76ce5d270433d81a0de9a70302cfba3104fc1fb701bdf240c575f209653bf732efd9cffe7c0aa35fc2b4aca44f35818fce4	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1584737158000000	1585341958000000	1647809158000000	1679345158000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5f17a9446a0b9ef9d0e3588a688d286c3777bce34df49435bc797b39d58bf0c7510f5b6324e64c32f9804314bed68946092c776a2393ebd06c036eac5599737c	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1585341658000000	1585946458000000	1648413658000000	1679949658000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe2e0a403f0d85ec9096979ad1dbe86f5d118caf7e40b94e724b55fa7d71fbd9d03485f0d9b29b47027e29c84f9c91bcf1c550a56d7c7ce3ef367829c3e90e9e9	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1585946158000000	1586550958000000	1649018158000000	1680554158000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x525778c9baf64196b058e49fd52ee8d550f92ed13ec393f5071cd573a1c55f6be5212782a2abe8661d9dffb065480005db9029fe16d05a6ac66f377de3f790d7	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1586550658000000	1587155458000000	1649622658000000	1681158658000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xbbb7bd01d374f325f045723a745e2e02504b843f66dacc0f520f7c90e3bec78a7519e7a0405e976339f897dec3b4be5a82675fb47a0736a25fa858029303d992	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1587155158000000	1587759958000000	1650227158000000	1681763158000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2a03e046f47184cc23368f29d56df8012d504def98ab72109a2d7184ca2bb8c1d8833f8b3224734a676610e9813272c6784889f2279f031225c8de6b83671913	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1587759658000000	1588364458000000	1650831658000000	1682367658000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x0380b585e7880220ef50d679081a392b342215ed35adb7bf7e4f916bed58712b1a6ef5e3d20d592822725efe5545f115798300616b56518050c1d89d8a167bc1	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1588364158000000	1588968958000000	1651436158000000	1682972158000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xeaca5a96edcb4a0c24e7f0dd3574b53a742a60a450bd0b2486f9469660b2a2a2210f2d13473d7ff8bf678ee84792fcb813b26240cdca374e6dce127fa757d657	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1588968658000000	1589573458000000	1652040658000000	1683576658000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x3c410c9e0e27d35240c2f17bdd342b0518efbfcab0c14f9729b108c72cb27c70bdf37113e75289c2a76d6bcf95caadd66ebdba1b3d2b0db25ac257d34b78c76e	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1589573158000000	1590177958000000	1652645158000000	1684181158000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x24c7dec8451ee3952c8375f2aa95087622363a8f0fcbf2526aa122cebbb628486f639042b4e11309da5f5d7476f7633b092ac379666622dadaa5c3846e6dafc5	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1590177658000000	1590782458000000	1653249658000000	1684785658000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc9d0105ecaca0efc4e9a40971afb095ca2036c7ef210ebe50188791ca9559452562b7f1f81a0338183a82c039b5a6fb72bf9d30294ead66a9b2f6dc5e7ffabe5	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1590782158000000	1591386958000000	1653854158000000	1685390158000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xef09941f007a9dec7646d0f5a0dc2e7d3ca5e52d4fb3dd68ecbe2d4c09f18c9615a7e704240dea3e562a296ec8ef81199b950c92e803a55e9c16db73a3b2a35e	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1591386658000000	1591991458000000	1654458658000000	1685994658000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x55be05444921f1023d129149abc5e6f36a19df4b07c22f3adc711b36f8fdbc7cfaf9d7d9a8ec528e300ad20fae643bc81a6d877bbfc23a6ba7206289905e242c	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1591991158000000	1592595958000000	1655063158000000	1686599158000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x803d8de4d1b130a94345beeb79512d82f344e66f53fff69b0e5b64b0172c92b0bbe2afdeb51d80d108cd7cf62e90746f1929cbe31200ae3a58421b1f27df7cfd	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1592595658000000	1593200458000000	1655667658000000	1687203658000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x3b93e6ed3a129b0601dada7fbe0fe25429881d5a25768a43d416e9ff9030ca477382763a3128c53572c48b8d140ce8654512c0cc59d1e61fa490b37b70aeeabf	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1593200158000000	1593804958000000	1656272158000000	1687808158000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb16f4f3ed3f3eab0750a095e673487fdb043e37c6fd7fdb8258e330085e829964f1d18177f823dba828922087f2ed453851cdaf8a39a94898e5ce8f99953c855	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1593804658000000	1594409458000000	1656876658000000	1688412658000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7acc0cdae519647ed4adbc3cfe7a3835fc6b3faffe1e3be0a8210514b95c93f25203a73d317182a14bd0ffb70cdfa0ba498fec6bd21c65b4bf0cf1221ed014ee	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1594409158000000	1595013958000000	1657481158000000	1689017158000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x51dddc3a650add9a2f46707f1d83298e0e69fee8232736d4dea511d6a1765bf77eca04f8dde6b9c9297a714668d9882e9c688df77458030fb93e5e33fa928614	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1595013658000000	1595618458000000	1658085658000000	1689621658000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x491386a8ce16abbc7d3c942a7d0102c0533aaf7c2486a789a26ac576a98a2a86fb8a220c82fb4214b83afd6599d7a90681a999429228d714b61491a42413246a	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1595618158000000	1596222958000000	1658690158000000	1690226158000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8f4c20e3deb8bb460dfdc8bc440207887e2693b5eedfc89aa85eea991fcf536786a01c4b4d86b0d693d2f5b01784730e057400a72e5f5ca0bd01a670896726c7	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1596222658000000	1596827458000000	1659294658000000	1690830658000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8994d4e1be53ee1385e5443c1fda4c42e7de98931ce2dbacba91361cd9d96960d1e4283b8e5d1ae280b41554b2c057f6d65e614ab595908cbbb8d22043d3d877	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1596827158000000	1597431958000000	1659899158000000	1691435158000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6cb80b2199bad8af38d111d8e55c494cd0b687778671966f1976ad8724712efb59d0c0d995b607996ac5b751f5bbdc9a8e0ec8f2d9f3406c3e01179116c9e88d	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1597431658000000	1598036458000000	1660503658000000	1692039658000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x109c2fe9d85d5585028479f994262bbebcc6834323ee6112d98cda1f733bf717575458c8889d97c54fc69c380c95a3689713451d829b5eebd4c569315759d661	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1598036158000000	1598640958000000	1661108158000000	1692644158000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xeb9b34237bed58e279740777422c093df486d3c3abf6feb482d43f23135923895064198a5524c89a2ea39adf513a8da13a9a4f8fc6903f190e72cd67c40d99d7	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1598640658000000	1599245458000000	1661712658000000	1693248658000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xafa9f3933a23cac6f44afda432f5aee089f18b073a99e3c56815e71032328024aafcee9dd9e268bbe5bf7871df5bc94c0626f632d6e484dca1ca7f02543f1bc9	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1579296658000000	1579901458000000	1642368658000000	1673904658000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x782e41f660625f08eabbb515982c0d53d8f43c57030a663e178ee14cc098bf1076e1a511e39ba33e365591ca3d0a9f8ffb61eee71c712c65f3a491ffad282c72	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1579901158000000	1580505958000000	1642973158000000	1674509158000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xdafa4b1f24278c6a9759fa56d405abf52f370b30ad91e7bbb0d2053d86551af8d0eef86d972bd7b877d8a08b0d2b6a1479d59b1b7ca0e510e833884f05bcc685	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1580505658000000	1581110458000000	1643577658000000	1675113658000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc1ebe1a20e16729b842e4d0879319cbbdd44b24129cf8fe5cb95d179631a92d2c4f2b95317c8b95a8bf85f69c4e19ec5d53a532bad976cf7fa41f1245c3f9046	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1581110158000000	1581714958000000	1644182158000000	1675718158000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc53666d04b495f67b78dbaf1a2c5edd000653adb2882339584e58d3cacb1d2858c5e6b6ee16e2d33228e3662581832e46fed3bea07ebd509b23bc59b52e9b16c	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1581714658000000	1582319458000000	1644786658000000	1676322658000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xdfc775730c56cccf0508a2832775511485a8a803f81985ac0a01041f9834ef52f647f316ee98b2e3f71699472abd3db31c2e49a42e168a2a89992adf0a8716b4	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1582319158000000	1582923958000000	1645391158000000	1676927158000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x62733f24fd24716abae1c7848bfd62182a4007f49464b525cebba9c4512c24b0cf5d4c198f0fd0443fbd65e75462770342a65eb75a5f3d491cf711149ef18347	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1582923658000000	1583528458000000	1645995658000000	1677531658000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xaff41b1895d4074ce769b24aefa9c458cb1775ad665105ac48dc5da005610a7d5a77b2faccc5fb1bdfd3c73e8c84ce99f078ac00a6ede820f3254aab6a7e4dfc	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1583528158000000	1584132958000000	1646600158000000	1678136158000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x71df916f0c61aa80058c155d4072c0764bc61176f4e15b56e41888b963d71d82aacf4f769590ce0d9ed66fadf7ae3410d1a3d22a5e6434def1fc5fb2bce0683f	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1584132658000000	1584737458000000	1647204658000000	1678740658000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xf440a3bf691254cd4892d7c1b926b9e148699ef7e5e30269c3a6f59d694513394810fa2521aa5da256367386766009f6c379e61414e5e1c1429566d05968c816	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1584737158000000	1585341958000000	1647809158000000	1679345158000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x565a64325ab90323377b6ed9da9620817b9020d5abcf729aa106ac80f589a8658bca6ca2d07d07d3d0e0ed65fdd9f7d12fb4ca073bdb9808fbbe60c63b44c60c	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1585341658000000	1585946458000000	1648413658000000	1679949658000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc4f3bb043afd623bc6ba6eecdbdf38d7f9a16db6aa2ad1196e9fb3856f655fbf9944d30d4a65d8b15a4f1578babb0531c3e176fd33125e9a22cb7c3c132be903	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1585946158000000	1586550958000000	1649018158000000	1680554158000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x0c5508bf50195d31970a05b73bc602f7dfad063dd6fb28ee20d793d77c3ae7d79891113cc5d63eab15e0d74cb17497137878ec1b25c57eb5074fff6db5933863	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1586550658000000	1587155458000000	1649622658000000	1681158658000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc5ce26392cfd01992b0f08bb2c6f9783bdb7c10561e7bb93262181977772db3d0b85281350d1cea50794baf53e91d24a525194b936d6b5f92da1ffc050c56f15	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1587155158000000	1587759958000000	1650227158000000	1681763158000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xf28bd483c764e85262bf6e070070cb0d14497d99a951daa7a6a06837c12bad09b029c88550c8ce8511e1ac8c267ecb5a85471d8cda1ecd7dcc1ea84947c2b936	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1587759658000000	1588364458000000	1650831658000000	1682367658000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x60056e7dcaca7be4ed11c28957114db16f80aef4a709dd239d21b3eac18630d0485a71aef53cbb6d49fcbb74e25fbf1a615e041052557c9f78631678476212c9	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1588364158000000	1588968958000000	1651436158000000	1682972158000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x63375fccd7ab377dcd549b203017128b1a01e6bf0dd073c3ff37e3007e535731976abb0c7a9c661a9884934d294296ae34386346ec821cb054e4184383803d41	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1588968658000000	1589573458000000	1652040658000000	1683576658000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x1daf7dff27e3bfaae3d90068adf04c4c447b9c5aa9ec5c734dfa4abdd787672aed60dfa30362c6ebe47925603b6c375abbad42fb0c46031e20282cf2238b7a81	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1589573158000000	1590177958000000	1652645158000000	1684181158000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xed2b4177e60179062d6e8ed2b3ccd35b27e5502aa4052ad5a246e6e5f9bcbbf0148af0ddf5708243532b74fb9a38cf8594c5d0effcc3686319eb90d384f8d517	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1590177658000000	1590782458000000	1653249658000000	1684785658000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x5434b010527cbd7f6cad7e95aa502acb256285a62dc01404ad2abbfdb00d9fca7c28e02436d005551f527be699b89caa48424aa67e14f5d58397b7d698af8456	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1590782158000000	1591386958000000	1653854158000000	1685390158000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x8b925a04f4d9116f7a6c7cc08bd9a5bcbe73d331db0e4affed0a0146b481b2ec2ce1f95df1a30085899c13f30452326a93bea1676442ca4ab7560140206d8b47	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1591386658000000	1591991458000000	1654458658000000	1685994658000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x7e93da9fa6b8975ce35baa2ba3819cc76bdc86efe7ef82a83b44fbf4b4b081bf683d3c70531050b9b4e29372caca3997dbe8f1a104918e106d31c3c9a6befad3	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1591991158000000	1592595958000000	1655063158000000	1686599158000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x3ac61450f3ea3bf2b1ad7e005bbb94ce54e70da2d814f303c84c8bbe3217b1784aaa4b901d5d4fca188336185e6043b01af436fcfb2c925f2e9f49a24800f9f6	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1592595658000000	1593200458000000	1655667658000000	1687203658000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x1858964b6069c53d237ac0141e66932afa360f0a0a94e83c54e3fa01fee5911c78984ff5dd950fd3faf35b234d69ee296a9dcbedcadfec74d0d8475551beb25a	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1593200158000000	1593804958000000	1656272158000000	1687808158000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x5c0ed0705e2d4c8f156707fd5e12bde55971d4ec6e23eb7064cf86e945fd66f57f3603406814f723712a3d5a7a4245986af327ff3ecbe0589bb2d6d837d6d81a	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1593804658000000	1594409458000000	1656876658000000	1688412658000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x15758cb2fc130058be9de2b7479bd15d323be52393c0610017ac1db2b6a16f386fe63d252f0f5411e8270d92f00b8db8e2436992a37a100d06b656f9ec0f032f	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1594409158000000	1595013958000000	1657481158000000	1689017158000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xb788505f6e824c8c0158f2cfd5c6cbdaa0064707910ffbec8ff6b533e44f20b09368cc03c6d1f9c9848f3b6d3365519b2b8d1d74fa841d86dd29a31937aac3a9	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1595013658000000	1595618458000000	1658085658000000	1689621658000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xf216b5c90a3ed62c380f962c5c3112ecd83b48bafec196ec5c370b9cb5b6283345afed07ee5361cd479cca374863348cb8d5148cd0e431c8681de753a400e5d5	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1595618158000000	1596222958000000	1658690158000000	1690226158000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x828b75a6cb2f59b558e026b38a96f78f9c2392a68c0db3ed3aeab6a473fefdf5ba815f7ddfadb017f2877fcacd57755e9c64e045725013d67f0c7065654c47c0	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1596222658000000	1596827458000000	1659294658000000	1690830658000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc1ccabe044d95dcfc1409c998d6a2da3f377b103ccc1e922a3053b65f512b6a10bd38d5363eeaeab7a7faa8e275692fcdbaa8fe8e7dad2dcef9df1ac88281a0d	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1596827158000000	1597431958000000	1659899158000000	1691435158000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x847d439e8d0965df7225849405bce9c151b66b952d7b88ea11ccce0cbaf9c6db416c9c920b531e7e83ec3cf2cc4d1506f9564c8077b98a0a8ccacabcd6eb0bb8	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1597431658000000	1598036458000000	1660503658000000	1692039658000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x104c340e0cb53638af359ec3dc8717cc382d72508c232bb50ba3699808b5cfa91658c1d60668acf7e6410c35a5e461e7ab4623dab42fe38c31ebe112c9a0a741	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1598036158000000	1598640958000000	1661108158000000	1692644158000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x2dec1610a825f3ee7d0344606167f6897e0a7559c097a7c3dcd5d1937c5cde3711428e39d122ea9f1c34258207e824b873527f984dbee2c6a9f0857efa50704e	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1598640658000000	1599245458000000	1661712658000000	1693248658000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x61dbab5fd91563cb90b4bae46f0d6469c06db821dd0299a3b443231bf4ec16e151843f3a78d27a71aa94fa6ade1b97e3d717e6d0585f6e41570c87880ba0a309	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1579296658000000	1579901458000000	1642368658000000	1673904658000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x9f0d7658403a999325130a93fb833954cc8fbd17a7717b9a2505c73f3ef526b97fc7004937242077b5cbb2e4af18ac7e68b30b344ebf9e23a519d0f701392733	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1579901158000000	1580505958000000	1642973158000000	1674509158000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xdc0ecd78edf519d4ccb27d650f5a1916f1fbb196aae3d8aa0bfba23e374c7e2ea20dd2aec98d8463844d678af8e1f6c1aa56c531fbeff00022b3dc71d3c6214a	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1580505658000000	1581110458000000	1643577658000000	1675113658000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xdbb72e11db4836d2d2b0e60d1eec117d20098901614a59e4f35981828a6f724d520c1726c8d86cadbb4c658669503050e7d91448901c56d6cb8177c5b930b1fc	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1581110158000000	1581714958000000	1644182158000000	1675718158000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x04fbae646aa2a7dcd46e5d85b3fa6b1df66914dfeb28db19f0e7ca636e4fe0b460b9efdc0d7940d9b6a18668fbf4df1b7b0c27beac32219f3327027f080299c8	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1581714658000000	1582319458000000	1644786658000000	1676322658000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x50e4b2ae8020db47f0ec5501e07cf1114419a5d124643212492d4618e6d70a82528da70a58912f77651e7afc0c397ded4b8974b6300b15ad0d2a25e256acd11e	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1582319158000000	1582923958000000	1645391158000000	1676927158000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x8e116f48b9b96665f5c610c69782cd7a70636fdbf56c4cd658d1156743fd9096f01b9a559c6afebc10443a1819fda8c9d2c1989cf886d0c45fe9261062341ffa	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1582923658000000	1583528458000000	1645995658000000	1677531658000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xd172c093cecdc9de2c13f423f45a7bebb01b3d980d4748714a5691fffb9b097ae12f5a0bed08d5b736cb303114c6680b7d3c71857cd87efa522cc22d490727d1	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1583528158000000	1584132958000000	1646600158000000	1678136158000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xc2c71d24afc6d98fd4b3010424d383c6fe9f364706c1c19706a2ef287099a824a7eb7a2d8057fcc9172aba9535edefc45583316a6668b5cdbf3e987d88593a99	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1584132658000000	1584737458000000	1647204658000000	1678740658000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xe5018990d95a9e7e4df2d6b1299f3b927f0d58136f736b629bae74d1fc9057ed92c03082e11e40ed6b66fe1d37221817923ce18ed31a70fdad1833b978be8a38	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1584737158000000	1585341958000000	1647809158000000	1679345158000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x092081b169952d8dd254e6753e9021ea053c11f406c45ff19be0a705b5155d2da9e08296f9a4ac5d3f44d9ff91ffe3b8225532bec1427c91cbfbcaa005b4b492	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1585341658000000	1585946458000000	1648413658000000	1679949658000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x729ce73cf455621ef73860b85bb0ec490a97939f140f03088f0cea7f853ea7559f8ab6032264f05da640bf175b2ac0e700be2310b57f08e620de33013f4255b1	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1585946158000000	1586550958000000	1649018158000000	1680554158000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x1baf1d82b66d08e62841fbbe2bf57a126d3558e3baf1131dcaa3ed225c057f5291de01b86893a5d095b42aaa168a7faeee786cec29a855b52a8267d68977b5eb	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1586550658000000	1587155458000000	1649622658000000	1681158658000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xa1a2d45408e2db18312823fe9d766dd80c1b5dcf5ff119aeae0e0253f9ccfa580ab927b72565fc8409a0146511641fb69aa4896ee7599142faf2db38fdfe3529	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1587155158000000	1587759958000000	1650227158000000	1681763158000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x7b2d9adf036376c1c89b6a573ccc33258f5ead713b521a3f5b273754e109575349a269da01f85c8b6185dbeaf703367f204c35c94d8ee9b3fcc0ea6c3b90ccef	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1587759658000000	1588364458000000	1650831658000000	1682367658000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x2229adca92e6b0739a3c5de46df4ab644f210def0a5b50cb212e5f85e259b868981172b6ccfe87943d4305174bf7f2124c537af089689edf3d98628f27e6d695	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1588364158000000	1588968958000000	1651436158000000	1682972158000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x30f5132004e474f493100ea8862f958ac90f0b8e5c5844fd246e1364d48df243685f4f741a62b60fbe92ed1004d232e3e971240dda062519e887092bbb0b51e2	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1588968658000000	1589573458000000	1652040658000000	1683576658000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xdbe15c61ffe4d843232309b8385020423e6740e2d136b9dd2d54d2718de278f21dd2e3ed7e25e51adb85ec3bf8568cb0ee682d3e9caa0074cb4dce1a33550983	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1589573158000000	1590177958000000	1652645158000000	1684181158000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x0f528f7b969b11fe465dc3de74e5062180d1872cbbe3ea5a7b35fc656090536543ddced6eee444a974045bd37a80aef62ae97fb2df95c00f497f48b34e3c1cb9	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1590177658000000	1590782458000000	1653249658000000	1684785658000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xc0090cb535ef703e82e265f499193120439a1c2eefc7b638ce06e3981225cbbd1d6f313663560e706918cbe18344716e908711e77e97c9c6f37349068245ad2d	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1590782158000000	1591386958000000	1653854158000000	1685390158000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x7be26aacd8065ccc88098d53f135555e909fb9a3313233123ec7cff14bd15a8309b6884f902c403b753e42f3c6cce7a83dfc2250e72097a27c9cdc55e31cffef	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1591386658000000	1591991458000000	1654458658000000	1685994658000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x8b3051c65c00f3db5be5d5c947d3ae4dfe13cd9f13736edde0fa0479c4ad02acc4dbaff0d2586953881d860f476d521000934fb4841737446e9cbbf000b3619a	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1591991158000000	1592595958000000	1655063158000000	1686599158000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x7141c4b57337881a92fb51c0b2af9f3cd7588f60e87fa40a2066a90c5c8f6f397c3c98a43071995512d3793d4ab5d73216fd516d615ab795f5d4a87ef6fc7be2	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1592595658000000	1593200458000000	1655667658000000	1687203658000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x3db0b1c654000cf294511b52f7e51da95d789afacc54bf5559e5f3a1493a631855aea238b0fefe26766a02126ffaea437fcb3ce928e62784cd98bd4c121fd72e	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1593200158000000	1593804958000000	1656272158000000	1687808158000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x75244c4fd4950fbeb54db1358520232b46f71e1de1597c757e411694232b726a21010d18a3adea2c8333acdf3373c917115c80fffe6c03135aef8e321872abcb	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1593804658000000	1594409458000000	1656876658000000	1688412658000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x7bf2bf92d4fad14521de1040af66cf509234857e6065e1408f597931e2dccb3f5783d1085c13ca460fba10b1e53eaa4532b570ee0df70eeb343f6f446817b6d2	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1594409158000000	1595013958000000	1657481158000000	1689017158000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x75b4c456b084cc0f46de45fafd5176c9e9912a3b5341615caab0b99e68da172a9b88e26c9c27e367aea9bd53eaf971929a9c38feb700b1b4db215d05d403eb71	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1595013658000000	1595618458000000	1658085658000000	1689621658000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x5affa8f461f20f4395ab58608ceadb798a166a08340d060a315aac39d046bbb2ad03006ed12800e9188be466beb2ec20636df61005a1def3ef2d8e1a27a05c1c	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1595618158000000	1596222958000000	1658690158000000	1690226158000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xf9b4692bbd138b0b15b7b56a618d2726cab019ed54d22ffbcf3b8aac5ad44451912293818369f0f5c3483bb07e3bf591fb8a26dd10baca02e140d613ba21609c	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1596222658000000	1596827458000000	1659294658000000	1690830658000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xcc7d4022a4a96f732152ec0bcbe7172a1210a43a3ca5c837ddd1b8d14813755958254f3c5f06f2cb29f541b185f7b2620d42127b4f31097d3e1981630a6ee504	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1596827158000000	1597431958000000	1659899158000000	1691435158000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x68b635b6dac1e2d5bdd63583848345a47516f070cb723d9486f51b1cdabc93ee1ae11d60b3c807f011066750dfb2c3c1bf2278ec16f43c0467e1709b25d932e6	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1597431658000000	1598036458000000	1660503658000000	1692039658000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x13c9a1d98d31c71b4f4c273c1221504d54b1cfbe23192814fa8f52af7e2c67d2fec672b877b598b8dbc7c77bd9906de6b13fbcd34a742fc279aae268aafdb83d	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1598036158000000	1598640958000000	1661108158000000	1692644158000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xe60e7acdfbc8f64b4b9d8de62255c8d6d5780f91330cd0f6fda6bcc50557876c511097165283ec5caef71f65a8c3f041345eef00c606cf3e9284f43656af69a3	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1598640658000000	1599245458000000	1661712658000000	1693248658000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x7fe3c0af8df8fbeaf384ca6529a71515f9f457c71a0f718fd2f762032bfe122c958c31e4eabc9b6014ff1cb129616932cf7fb29ac8e960b2a948086d9bd726f2	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1579296658000000	1579901458000000	1642368658000000	1673904658000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x0f68eecd9ff224a6dac11e2c5df0a018e4a632ebe64fd87278cfa8b8fd5780220977286ae788cd2f75734255ee27d21af050f684410cb3694275e78c6a812baf	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1579901158000000	1580505958000000	1642973158000000	1674509158000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x609d7bb0d26a6423f75f7624664f4e026b10cf0501747d9751af737e1a4c9d2b2eb74cd4c0b2a15579df2b0e9d33d2cf6288d627f29b0d92aa49ba1843706ea0	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1580505658000000	1581110458000000	1643577658000000	1675113658000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xefea9f7928e5349551129ec8d6e4588aa8f25d80d6d03cebba27cef2b31fc2fa941d801900c8484dbfed4308b40083d652e8521ff0961977ffd74a0c61d6cccc	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1581110158000000	1581714958000000	1644182158000000	1675718158000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x0fea2724ad61c9a580b9235607e056eaa9a32d696b605f0c9a5dd8fb45f6f5c910dea9987b65a4ff246cdf72927d0b9df6b5d39eba88057375832603557d0cdc	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1581714658000000	1582319458000000	1644786658000000	1676322658000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x949a14a23fc36c8b462db0b264a2d8bdc314a8d519288e264e10715ed4fae944932975f02605c7677b6b9a283c5a7651ca2e08ce450136454b86094b4a91d203	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1582319158000000	1582923958000000	1645391158000000	1676927158000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x8a03bc17ded89c17e87d78b6d5aa500c8ebe571408e591bfc697da0d6d4d8b7adf7e8fbc8d952a6429652191b08d564c426c3dd5bb80f4718df253ec6b5dece8	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1582923658000000	1583528458000000	1645995658000000	1677531658000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x155ddc84048cab05a6f910a949c620042dd1de4df8f6f1194ea33462131f7ccdefa0d5155f09c90d100e7190cadf13f37ec636506580b6a6162234126118b85b	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1583528158000000	1584132958000000	1646600158000000	1678136158000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xf2300ffdaf39fd4e7a9df842ee093450b348354166792b07f6cea94a0d3035557947b75307aa909b7d0291dee15a5128d35904defce87b166580efa2da735dec	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1584132658000000	1584737458000000	1647204658000000	1678740658000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x593f9ee1e891571df66cc2155f5bf0fed2095fdbb8f048db8c242694456ea2e0082504316c4d636f40eefa1b179f7f953388dbb9a086d5e370439fb526cb614a	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1584737158000000	1585341958000000	1647809158000000	1679345158000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x6884958b3239efb5dee4f8ce214cd808f55c48f53aa874a7d7ab8143a5d16ac3bca808dc493811a69cf271b189429d6fe72a0e7a95cce19d8d66c0870d5d285b	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1585341658000000	1585946458000000	1648413658000000	1679949658000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x60874ac9d87663027aa73384d715feebd638497c5b5a106626c52a50d1ffe7cd2a79b5707bee10f396617df63a493b0c0efa81a661952682948c2d4172aa90d2	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1585946158000000	1586550958000000	1649018158000000	1680554158000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x905b49c414aa205b5e4460826dd1d4dfc5b9090338fcdec30e96e1554d4f85867267044521d07c42be35a00c64245a992199d28b42ae4b6fc284af90e14ac126	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1586550658000000	1587155458000000	1649622658000000	1681158658000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xf107039041f90573079155129d93fb46d428e7010344c0208b84585840f6107490f34ff02b025ad2500ece80d3af575c1e29230357d905d6ec482575f246b188	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1587155158000000	1587759958000000	1650227158000000	1681763158000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x04fd98d5994c22a7c1975e1a92548ee4d82ab8a551750bf35764b4e2817041b6653153a8616d217fc71f0222f16042a5689a5efd0964d552ad7e8463675be1be	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1587759658000000	1588364458000000	1650831658000000	1682367658000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x0d0b204fda67f7f493a103255ebbf58f07f2e2c056de2e915d3b24647042d0e3db13d30c78e16823b45f0d6a80d5ed2ff9c0f5e116d553cc5174b2ac75b93ae0	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1588364158000000	1588968958000000	1651436158000000	1682972158000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xff08aa6d6c399d932cfceaec11873cbfd306773111de46009fb6fd8859c7ecccbc7531794decb63b5c5c4014396a2d8703ac616859a33924776b27061dc3c78e	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1588968658000000	1589573458000000	1652040658000000	1683576658000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x15c60afec32d2e46003464f3500401ac2453fbf8b488b77d3c8679341914791120342658c60648be880f430a7be44e338b273551f17b44d1d76e8b9c3b9f8e5e	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1589573158000000	1590177958000000	1652645158000000	1684181158000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x59a093c2855101fdb3fd5ce49946a92df585af0ef3e0cc9ef4798258b0fd334913decdea83094040420e87b9e6ead60dfd755f574d462c0c8b7ac9514ea73d7b	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1590177658000000	1590782458000000	1653249658000000	1684785658000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x77ae9a0951213a80d6f088e0fd53fdf545d412b0a76e2aa1c063bb1490b91dc6f579dc0c876aa6457a4de7306d0f2686e2313d1b3d823ce4d2123ce65d68bcb8	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1590782158000000	1591386958000000	1653854158000000	1685390158000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xeebbdd173a74eedb1cebce72d76bb3192d4c63c5e0841b8712f6338a5727a0734791c3376aa82b30c606593598f0596e7d97d129f35ab7047a444a82a4387086	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1591386658000000	1591991458000000	1654458658000000	1685994658000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xde3cb2e30e3725b5017c7285ff7fd339e84d4203a36762550ffe2b035eda44dbd91bdb23a08a2781763d15308f33f1d1897e5c948126b5062021edccdf66539a	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1591991158000000	1592595958000000	1655063158000000	1686599158000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xd674f7402f3f31c8249d135fbb57bcd3a97d2a18ce0ca1f78f6865794e7555271e1d1634738be1361afb51fbcadbda30fb00525044cc4829d48d26173da77e6e	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1592595658000000	1593200458000000	1655667658000000	1687203658000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xb2c94253e4d6a355c9154641b864a845e5050e73ae6ebcf2964a04e46a3ab47e65487ffefc375010207bc5b3eb244796a7921457d248183ce531f3a47dfd6cb1	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1593200158000000	1593804958000000	1656272158000000	1687808158000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xe87572aba3e70aed03c7eff3041681f4dccb9517ceba3e5c83a787dab4c484993c3194879fba199d4c1c106f7349f1d10141bae3e3f5bac2e4ba3e46968a2809	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1593804658000000	1594409458000000	1656876658000000	1688412658000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xa65d6d6f7140e50f28491e33940c50a35dd2eb30663d3226077949df78332dbb7203f6336cd35b4281a774c8031fc647edac8ec79cff5f36c27b90945366636c	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1594409158000000	1595013958000000	1657481158000000	1689017158000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x07d253bfffb2ba90658855e84b808402cd2eb19ec23d50da0d09e59b7390a8cad78071c06b2c38021f4739ad07471387584219777fbabcf744e8176612728db8	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1595013658000000	1595618458000000	1658085658000000	1689621658000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xb9e519596e080a787206e017b7d2f7413a211768e10917258eef6fc0ae9eac502dafe727cf6dc1f9339fcf1e11bac9cd20785a4dcc959f98ea8f9141ca0249cb	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1595618158000000	1596222958000000	1658690158000000	1690226158000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x041f92a35a8e97ceca177dfcd27d3e8604f1163b1bd619128b85cd04370b5331357300823da0aef3b5cb84b7df7f95aa75e96fc399372238dc8910b6026d6946	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1596222658000000	1596827458000000	1659294658000000	1690830658000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xaf609a2d4b7b9e86290b9d9f053d59fe13550a6050c96ce7bcd6db7a0887e96a3e5f803ebeb9828301b0d47281f72dd23f3c2bbf8ce5b93b6868e28e736e7911	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1596827158000000	1597431958000000	1659899158000000	1691435158000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x64e59b6229c134f44e2fff1309413c8cf76f4ad9c86fccdbd04e6ff04fcfb425115816db0d3c6d0fed5ddee96b61a096b53281d74e0e4ae81f85cf0502e1a6f4	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1597431658000000	1598036458000000	1660503658000000	1692039658000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x8df655c481f761418f14526fb4995df193be90cbb21e127387370bcd3eeddbb80b2e0ab8204fcc3436607461fbf86dafef5345b1c7567d03dd964246bb7f445e	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1598036158000000	1598640958000000	1661108158000000	1692644158000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x67e1b5182df8ac36584f4a7aaa53583120efe83606cebe156d08a6ac389a09a5d384cd2e23d87544b301deacd821d5f65c796960e26228f6b33f422ab6b188ea	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1598640658000000	1599245458000000	1661712658000000	1693248658000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\.


--
-- Data for Name: auditor_exchange_signkeys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchange_signkeys (master_pub, ep_start, ep_expire, ep_end, exchange_pub, master_sig) FROM stdin;
\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1579296658000000	1581715858000000	1642368658000000	\\x40bc237e2cc27094b1008db0c4ffbee389fef47015e7e2a9c2d3b953f4a35fd3	\\x590840cc8daf2a0e1e812c6d4392696b0b38612994224230ed1d70eb3c0f0477962967e0465863b06014d0b9557c116aabd8fda45bec8ef38edb95099dbf6505
\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1579296658000000	1581715858000000	1642368658000000	\\x40bc237e2cc27094b1008db0c4ffbee389fef47015e7e2a9c2d3b953f4a35fd3	\\x590840cc8daf2a0e1e812c6d4392696b0b38612994224230ed1d70eb3c0f0477962967e0465863b06014d0b9557c116aabd8fda45bec8ef38edb95099dbf6505
\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1579296658000000	1581715858000000	1642368658000000	\\x40bc237e2cc27094b1008db0c4ffbee389fef47015e7e2a9c2d3b953f4a35fd3	\\x590840cc8daf2a0e1e812c6d4392696b0b38612994224230ed1d70eb3c0f0477962967e0465863b06014d0b9557c116aabd8fda45bec8ef38edb95099dbf6505
\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1579296658000000	1581715858000000	1642368658000000	\\x40bc237e2cc27094b1008db0c4ffbee389fef47015e7e2a9c2d3b953f4a35fd3	\\x590840cc8daf2a0e1e812c6d4392696b0b38612994224230ed1d70eb3c0f0477962967e0465863b06014d0b9557c116aabd8fda45bec8ef38edb95099dbf6505
\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1579296658000000	1581715858000000	1642368658000000	\\x40bc237e2cc27094b1008db0c4ffbee389fef47015e7e2a9c2d3b953f4a35fd3	\\x590840cc8daf2a0e1e812c6d4392696b0b38612994224230ed1d70eb3c0f0477962967e0465863b06014d0b9557c116aabd8fda45bec8ef38edb95099dbf6505
\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1579296658000000	1581715858000000	1642368658000000	\\x40bc237e2cc27094b1008db0c4ffbee389fef47015e7e2a9c2d3b953f4a35fd3	\\x590840cc8daf2a0e1e812c6d4392696b0b38612994224230ed1d70eb3c0f0477962967e0465863b06014d0b9557c116aabd8fda45bec8ef38edb95099dbf6505
\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1579296658000000	1581715858000000	1642368658000000	\\x40bc237e2cc27094b1008db0c4ffbee389fef47015e7e2a9c2d3b953f4a35fd3	\\x590840cc8daf2a0e1e812c6d4392696b0b38612994224230ed1d70eb3c0f0477962967e0465863b06014d0b9557c116aabd8fda45bec8ef38edb95099dbf6505
\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1579296658000000	1581715858000000	1642368658000000	\\x40bc237e2cc27094b1008db0c4ffbee389fef47015e7e2a9c2d3b953f4a35fd3	\\x590840cc8daf2a0e1e812c6d4392696b0b38612994224230ed1d70eb3c0f0477962967e0465863b06014d0b9557c116aabd8fda45bec8ef38edb95099dbf6505
\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1579296658000000	1581715858000000	1642368658000000	\\x40bc237e2cc27094b1008db0c4ffbee389fef47015e7e2a9c2d3b953f4a35fd3	\\x590840cc8daf2a0e1e812c6d4392696b0b38612994224230ed1d70eb3c0f0477962967e0465863b06014d0b9557c116aabd8fda45bec8ef38edb95099dbf6505
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	http://localhost:8081/
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
1	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Bank				f	t	2020-01-17 22:31:09.653553+01
2	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Exchange				f	t	2020-01-17 22:31:09.728398+01
3	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Tor				f	t	2020-01-17 22:31:09.794724+01
4	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	GNUnet				f	t	2020-01-17 22:31:09.859455+01
5	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Taler				f	t	2020-01-17 22:31:09.927566+01
6	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	FSF				f	t	2020-01-17 22:31:09.992342+01
7	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Tutorial				f	t	2020-01-17 22:31:10.058159+01
8	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Survey				f	t	2020-01-17 22:31:10.1226+01
9	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	42				f	t	2020-01-17 22:31:10.541912+01
10	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	43				f	t	2020-01-17 22:31:10.967461+01
11	pbkdf2_sha256$180000$gWjn1CB1USlU$pYTkcFvbPBTIJtr/E0DFpYbSwFPOEXRiMXUoZxJpl9c=	\N	f	testuser-IeDFoN9k				f	t	2020-01-17 22:31:12.59+01
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
\\x610e9da754016f8c1f9f3571b16ec1c051dad1e5b69c15f01d0aea8e0e451400178478b29f0a2d405c43b0bddef9a480fd9cebf40cf2092d796bca2c08b392cc	\\x008000039a1c4e7947f9da6313132ea5eecf028c51e9308a5e283d081e0c1f6868888d0942fcaf26a691d36d29c62a59d59d8d241f5cdba188dcdd05111e614c2b7a7088aa87ad925f69cb6e22d26da0dba04bf141639e686a793f54ac522c2d6bc86f64e79b8f8eb12cf609f6f38e4094450f43246801f89aa33dd0a90feb4b440949bd010001	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	\\x8043c4d8b2e6107278d2fe1e9b1e67eb10689d4864898d559dd5ced09cea81088864f4636552086c03a26283306e6c22913a4f7616b4c7aebe49134288e50204	1579901158000000	1580505958000000	1642973158000000	1674509158000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd79f56b79336a12c455c9ac3627d9155624d0a0a2718edf472700f4ccabab2f061b3a22ac510b3dee72c93948225bb7e306dc7167bca39392df83c628b036dac	\\x00800003d02b0a2fa6abc18b1f08ef7f6a72992d58f02a5a459a85aa3ac0a18a7f51d60280e650cd6058ee29aeb174c4808848ace315b60d6ba5e151cb5b44a6877168940ff9f068794afc47bbcf19974367ff27d7114b147d96296e3f89486267e24cfb5a5e46b065dbf32628b3db6de0a9fe6074f3b34958f1ddf298537f17367a284d010001	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	\\x80996c20bdcac5cf783e5c6e17b1b29b80c6e1407b44268323767635320ae4081ab524fe0d021f13529dfad55e9c367ad35ac14dcbd00725ebe5c154185f2206	1581110158000000	1581714958000000	1644182158000000	1675718158000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x14b53e722c9fe1262f198b8ff940f263c188e7a48b11a32707d9b6e8d953c38867dd91f612fd29e46b2491dbe8e17d06e5610462a8b7b60bc5375bfe985dd0d2	\\x008000039e5416d01262b1fcf5d947d4fdea0d3e4b4a01f4b41ab5749193100ae2540a152e2dce57fbb7f152ca1e052a0cf85dbc03ef70e1d5931d4d0b39e2ea7c7fd04acab1ba29c475b847f0fd97f18e0cc264790222ded7340e90921c2c93c18ed32fa29822bbca831fd8e5e1191b6213898e9f4ddc25eb2e7fd5891cde9f366ca455010001	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	\\xa64f2b87fec9116c95f03e6a2c72295523bd673a962b0dfaee11c84670ef2f8a43767ab1dfea5bb591c8c3c0684407bf65c6f2b84fc715e5cb625b14f6592c0e	1581714658000000	1582319458000000	1644786658000000	1676322658000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x506e943609e343a2b7f2c8b8f51909d2b815a5df513fdca576146c65f474bcfc2fd7b527656a0428b92121d488fb887ade16875b915cb513efa5cf352599c6a7	\\x00800003aa5ab837f89dfa6147cba97466032d8d9685a9e6732e2f2b614145f8adb77a70ec4a296c75e23c2a63515f640ffab2f4de06f25fcdfaf8d44fe63689d89dc7a6a88e39033ef93980607cf247d418973664718626e0f242a151796afc55158c815fcb84e0f789ff8289b9c29efd8c04f9ebb6241639a491ae389c722fd42cb0f9010001	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	\\x413ac8f6def21883d6e9704bb2e371fc517c06123f5907647b24240c42a1217c121d58a4555289f19dad89c2e1ca25d3120906d4d8677b03b7e51f25cc8fa705	1579296658000000	1579901458000000	1642368658000000	1673904658000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x44aeca3d88927170c5f70367dc9fc830cfd8af65bec37b03a0002691a601228fa41de88a496ccd79c60f116c2d89e8c8fdfbb8151e748978f5f93c4e45cd19c5	\\x00800003b564eed46441c66441cbbf48763ba3b9d2d6519f4895c6461bceab91d2aa60658c7e2f08964ad8bf472fb4247874a4b26e791b672093fc656bcc2481acd9faccf7555fa348ff2297039986fb85b1cb8ac0736f1fcc4a8387ba5b27fe7fdb648b8fe3ff7f4e21fa04f7c8e3008c4cce61a10badbbeed4582a63b235ef17fb175b010001	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	\\x685f9246e83aad63aa9f3d1d4f2aa4d738c22379a30ad6f6c9b5463492bef026784d800fa6b61d288c8f1f6df3f322762711494b94c7bc8643296098b550a005	1580505658000000	1581110458000000	1643577658000000	1675113658000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x29223324063a3b3d44a25d367b3e4e7dc40200f7f27a9db0604f4239b5a752fddd64971baf13844025080896593ee86f0191242d671c58c6e64d629a7c4276c8	\\x00800003d4c7c14bc403a01fca7eb121bde8d692c0859b38d4e042f203124c729de4bccdb6b479491f2deebcee355f6f2ad2a4723e2fcc830b44140e9ceaab7d1305304dc5ce7a60b2cc6589c883fc8f57d3f4da37c9d4f03694bd0cb5f2680843a14547e0cdc5fd7744bf016a002d6e36cadf0f24f8dceccd31110162ff2c121e219fc9010001	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	\\x4bc136f08e794df037671af22d166302b9823b85025c541e1fed0c5393058883ee1ec0f43c57a1e190402755cd5935640e6d582d455b619f2fd519281741070c	1579901158000000	1580505958000000	1642973158000000	1674509158000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe67fe8749d391279c597ae176b345cfea0af234cf32056aaf2adba4a2490d4afff22680dbbad721f2c28e42a6028590abd2b1cd97faece363f088332f3baecc7	\\x00800003ce02ed9eb86488aaaaba6d3d434efa192c45a9be5235f56dbbd2d3ed8302b64a9d140b990165667e3ee7fb4838faea291cde7f10f82a1aedad9fff08e30250ad76ba5fc09931cbd59237a8b919b47580ec711e656e7740b105061f651e937937bc7f829d0097f6865333fad84db61d8cd23ed79003f523404dc5e7073635ca81010001	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	\\xcad360a39ac94518de2b659b45b65e5133548c4a05e4b2e9c3eaf5eda3207455f9fad407f802a571d7da3ffc99aad2937e144a88e87654be71da3d97ca49c802	1581110158000000	1581714958000000	1644182158000000	1675718158000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd8f9c8775de80104f1ac63f2a97291d1e6b2fbf028ff8f0fb8e25bf3ba2306ee2b4e53a76ee029f46d17e6c8d89ceedbb525f9ae812347d81f2fea0b9ad45000	\\x00800003cfc1ca7c5432215ad4b82912ba4d9bb7bcafc4c55cc1f6c790a78347932dc885f38a3e59c4a9b15632997b3471dcf88dc6b250446e71d1b72de2203506beac2b8b311dfdb67db724d12fd86fbafa8f9959cc2104b61e0930c5b4f273794e87401a642ba4cf02eafd4303c800a1ce71dc304ef127ff57c5a284d0d27ad50408f7010001	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	\\x496baae65ab92d669a206d6828850314595b6e7fd4dee6e11672bc4c6ce438432fa2d221fcfbabf27301d67da6d51d59b942e4224c310ffafe234aca0f70b90c	1581714658000000	1582319458000000	1644786658000000	1676322658000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6bc736ca29494fbaee85920fb9df83c292aef215e194737cdfb30b0d2ad8da3d910520561b46594fdaa82c1133d7079811b4ca10567247738616c4d5a47b4fb5	\\x00800003c15336a979cd0b38dfa97dc5f4205b78ca3f07e4ebaa2b2c6ca9052d2465536d7430dba75a2390b069ee9729e0a3b4249b23b1acc780313915b8401c3bd07b3aee93ba48e3082f6d445e381a4e02c1bf259d3dc2abe068652bc2d933d0b512efbf308b01bd80777c799176ed954a3a3de59aea33e1ca4c2cba91b14dc144f2f5010001	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	\\xb52b37a97d47aba12dce7b21406c57ad8febb3e661e0376b457115664650d5be8a9995aea156d2e1f1fa79674bbee5b247f1f9ab2cb2a9d5859daa57b1cacb02	1579296658000000	1579901458000000	1642368658000000	1673904658000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xcf1e956a144d26e5253615e8152e0abb162efcefcf99207b7f1b4d99c9f4af19615b35ad65dfeea1c33ce7ed1cf29161dd6e32f6e34c32b0090165b4026f5206	\\x00800003d13d78f1e280cbc8332c315505395d49b302282a5cfacc52ccdccccd5cf7b1c238cbc2df5713187bfadd5db9619079e35f83fe731cf2c3ad01c3765105eff24e35d2d9c1a965bea84ba9bd84d413310d60b46b4ce00f9fdb121607b72f18d9c8c8538266e0fa9afd742a48a0d19a6a76cd3b989f054605a384496b4fa2ebb505010001	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	\\xc6aa6585d12d106cd4892939d4722e637f12c1763ac0b9698eb4fa91420599230ec68fb03f904b600812742a8554fa258d5ea0f8db49eba0a2e96a5869e42b00	1580505658000000	1581110458000000	1643577658000000	1675113658000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x71ea92e6ed10cbdb20ede76b0296a28c43c6b4a24cb4696d55cc950f4e2204f0e63d2875ba04197bea3d36f818876c63d5c6b42a7d5a13fd09da33dee449d76b	\\x00800003bebe9821a70fbddd4475a4bfee5fbdcf47afa211a6e350b4763db2c0d8b2512df710046ba336029f75b9a9da2ebfd5832ec1b4fd30d27c076fa659fcdbd13a3f36028a2edaa553fa7c1610f5b725542dc62672c1d6842c423b7fe3c6c80f59672e9c0655e4930a84c501c5358e41ccda3ad6599d7e1d6266adeb298cedda20ad010001	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	\\x15710426e3ff6584cb37e2d1f478373d0e3909b32c7e89d136c49c560de02838719e940544ac2073a190eb74acd2216f004fd8127513d7ca5113b2e92820c609	1579901158000000	1580505958000000	1642973158000000	1674509158000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf27067484b136ce3e4b805af00cceee99529f3c9f5672a0c090bc4adceaa2fb4e212bc1515262efcff93cd7dc3e363963dd31456c8bc7690a54dca6c3a841d70	\\x00800003c36a295a66f04ba76c018ff6c1f9ac8b26e7f20ac87dd17a38fb535eddfd434151683af9e5b3c4720416b214420e9c0b822c83385bbc0fc8039e3ed1702aa8905ea7a5efac8496d50f2c75f2f537708295fd5939b999353e008abe04e2c0265be68c53afa06626474c7ed6bec548f6bd67ea43765ce7e6e1eca08dfc16c62675010001	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	\\xeb785c53d0d256438b4bfd810236d3fe8e647e0ca1bd786779aa3522941cd19f16effbefc91b23b192a1ab0f83ec7610fb9ed8307b5a6c9572f8b6ea5ea7ff07	1581110158000000	1581714958000000	1644182158000000	1675718158000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf3f900f3a9b74efec1336f13721060f457f4215d46268db9eda0d659289067a3f9f25090951a114d13965e714af94effccbe6601b655fa80ba29dea09369fbbb	\\x00800003b77cb0dc86c1d3aca885ed28cbdee0ada54369847c1713a2608525a23ac960b66bf2a3986cd10c4cf6fed663554c2a51e2a4c0260899b5f3d062ef7fb22c8cb1e61bb9b8c4489cb57f7b992a36d31e6528adaed82740ef1578f90607bbf982df7ee6d9c763dba9a45df2ac6518b420c37d62b9289fd33a1fcec82047cac0c4f5010001	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	\\x8f8c6b1387e91dc17f695b808edd36ff9d702e4b17605de06e535dcb58996d2ad16c9798fe298c9e80fb1770fd3ec06dd3ecd66f3e4e90d8d8c3faae079c1f00	1581714658000000	1582319458000000	1644786658000000	1676322658000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xdccf72d6b659c6bb3a502ad04fd29a6c47e8515fa798917187d0cacdbcac0403fd9da520c47af009baa4604f7bafacf0ee01628992fa412cd164c42ac99f6c6b	\\x00800003d9d08cb46f22ad7798087f7d18289064a6a089587909f54a69ecacc34b253733110e25ff458999ed016087c7b46c2a02e8fe19432dbe492567c7f6233de27a3fc665e9234afe9e2339ad0f31dd66eaf385adfe53bc4c1a44d427c1ba2a1794892313a1778f44c5dc236ac7b53ead0eb2a9a137cacbefabef489f17331e0147e7010001	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	\\xfc70a82fbf6885de3a62f3a5e2444f4dd458123a5392dbd4c02da94ca3ae30a546bd63777b47db9f1280b5571df768afd3ead9cb9da0e05efa8b3d6dc58d2c08	1579296658000000	1579901458000000	1642368658000000	1673904658000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x0e86fd5c6701b45753eb7029dd9c325d5bfde421dcb1c07e7dd2407a99940f6c7c0a3b559d58b1aa241eea2cffab4adb5e82c8d3eced0520a9cc18a34eb4dd09	\\x00800003b5193f6dac1c348ea4656b3ad149a1a488f1f628123e0f8d90653a48e042bf4b990cbb1700468a0f492dece53a8845a61ef86eaefe25f37fe06097c924fb5b8b19d8054483a77bdac05586baca8006ca21e0f39eeba9fa47558fc9ac192a2e92af063c991f1ef7e3dc1dcb57acc18ca17f6f626c89a189df3b4ddb9c8d07c1e3010001	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	\\x19b17b7d3fed088ae18b269611fa3f982e59f4fe9c3684186f8b9d7a5abc9f3e32587dab65ce5459112971f28fc358d79f40ed09e404bd242cdf2e77d6090307	1580505658000000	1581110458000000	1643577658000000	1675113658000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6397124ea49ec38cc86f57a1c52b4dd193a5178562a8f46caa398382d46fd0c1fe4177f911d9d828ecef529d6371946c65cc63f98b235b8f3d5d71dd8a590f66	\\x00800003c4a6f96ac4f95a6c74e7b282067a7d8ec274e691a7d11471c81fa6e9f0215f62541116cce70de186bdedffb953d94aca5c3564483e5fd7415ed9c699e1760b3e662df7d139597fa75af7d58670f9328a2ae5b6c4aa940f90d63b33979ddffb07ccc7176f997b34d78f3a69677135c3e3897fb46e65555a2ec9df3b2e80a4e6b7010001	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	\\xbef0d300f6d37bc2a940b9ec70219616e949f18a34507353e215c866c21cc8a334e16c72f4871f3ed4b7023d531c9deb5aabc9ed1a8031b586e218ef339e900c	1579901158000000	1580505958000000	1642973158000000	1674509158000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x996067a4a7f0a48a29e023ab888eb69fb7dcd604cd2b48055d3f39e42237621bc906453b0a6377894b728487a0c800a3a0ceb203538ca6dc10014445c39dfb7c	\\x00800003e0a09f8bd79fce9047da0592fc98f256f31165cf4b4f9fd0a069ed8354f92554c88382f7cfa552745f45060763eac7e9945398d7f4423ef2ea1b6292aca0c632e6bddc0b42ec860f6c0050094f4735d111baaf08a2cc02d6c88bbf7eaad2238ec2dd289f15f51dd7b6de955b27f943701bbd43dda6098f422d29c75758db7143010001	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	\\x637cdffd4977c2ece6dd2663310ddb5c74f6ad53f558516c1e30f51ba8b87b4caf9a37c72a1244ec0c4499ecb9f4cdbf00df7ab4c35374b67eaa2d85f3c42d0e	1581110158000000	1581714958000000	1644182158000000	1675718158000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa935bdf9b9e4327d8b2c059a0dc112656f4a8989752ae9e0cb51840df90748c13829e73115b545d8a92945a43ddef7f2be9fcd45562e40a6f75f0faf42bd62bf	\\x00800003d44bb11b5db5e6227b3a8dc8adea6dbb23cd907d308f983d12cff04c8d679cf5b046b1fcc809c652f466e49b777ff2457ac6d336289df6272b9add582402ee9d5c8844799eb3fadf066c22bdb9e1f3e6911c5896a617d2df11c5faf2775f61331b3806a118c55a8c50a440fa9ebe98f77351bb46a5a3390810b2824e56a15671010001	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	\\x6e5e09a198b75a8f7bb05ef231fe839efedac5f26eff7232d158eb620e729abbabc7e40c16df2c7fd8c3a3c615ee50a75f60def7258357e091b96974c532a402	1581714658000000	1582319458000000	1644786658000000	1676322658000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9504c7abe66b7b6570c4857d4ba7f889c9c15e91a557beff66f5dfd4f61a85930b7e569af2cb318aaadce1bcaa201e7a14ace12e93cf80658b6faa51faf2e634	\\x00800003cfcb4ae74cc682c2e5b3ae27df79ea234d15a052e75aa192f26e7dbad91da4e8969466b7d08c910d30d548aaefc762d3d075880db68c0d19cee61bec33f544925cefbcc2c6da59797573735b8592e56b6fad533c6c03c248be061c4f2d17a06647728e00bb68900272a13911b93a81eab04a11a06032ac15b28a3095b112d22b010001	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	\\xb68f629cad57fc87b44e507fa266f99194a666c73b0ac780e0082442e8d1d33bf8f68dcfe4c67de7c7c15b7b413e8f0fbac8d0970a4d42e8612b625e575fbd0d	1579296658000000	1579901458000000	1642368658000000	1673904658000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xcaf97e6c43cff114574e524f44a4415245fcd291e5376aa19b8698d37699b2b05f07d8358d59d80f1c7523406241e9ba2f0e46db33d0079412e35a077a6f5951	\\x00800003db4771feb6bb36390a6b41790955126fc1b5d1565c9ccb584025e36c091becc68a742728b4c820fbdb7be30b09df6a51969c491f2c20b64af053723e1b1d5efc6172490935e3afa294ad6d7c6e429493fcae0e42c41e9bda9266c0d2b9c955e1ea45d925204eb8b1a444ecb53a8bd36d5cc06f64d6aeb11c6582016891a222bd010001	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	\\xa9e38f1f220e6f728a0925edf9eca3d113b58d1d5079c2af2cfc63868931f07af432985e57826e38489d6356e4765f12c3074d3eb779c6200d06ecaa7228440b	1580505658000000	1581110458000000	1643577658000000	1675113658000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x782e41f660625f08eabbb515982c0d53d8f43c57030a663e178ee14cc098bf1076e1a511e39ba33e365591ca3d0a9f8ffb61eee71c712c65f3a491ffad282c72	\\x00800003e70eb9d194490fd00ed13d88b09d28cb424b244f55731bb4709684d4099f1e8e668e5cf86078543a29fc57b9911c1abeeac56c931a25f7497fa755359d51db53deb3d0f010813a3755f7f8754c88717079d3570fac45cef92cb79a437583a0629c0e1d9dbd3a4ee91d5a28febd37f4fc619d952f39f955b143f56e0a5113542f010001	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	\\xf3efdd7dcdbb14f6f33e113aaef3b713343d1bf008accdeb5944bd15e132c15c5c7b7ba9f2ef39ec45c45359533e8e65856d924a4813da70a2287518e1e3260d	1579901158000000	1580505958000000	1642973158000000	1674509158000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc1ebe1a20e16729b842e4d0879319cbbdd44b24129cf8fe5cb95d179631a92d2c4f2b95317c8b95a8bf85f69c4e19ec5d53a532bad976cf7fa41f1245c3f9046	\\x00800003a97ab4644e6411495f30dcf2b4c9ade6a226eeae6eadc413321abde2c52554ceed26c8fdbd343f7ed49e6058dbd4e5a3869d19897f898e499bc2d2a0c1fc82cbd28dcf05cf2aed2392373a304b3cad2d3c3bb111ff29e27043cea62ba84b5c0cc21ce2846dab17699b08221f209936ec184a9f5ca923cd9211b72263cb206bbb010001	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	\\x1d986a7c9e6da95c0ebfc94c5532d6f87b96fd9c9f691cecf9319a85d6dd2b899896f39b2fd18573777f4aaafa67d91a600b57af15f0ba35aae1267414782707	1581110158000000	1581714958000000	1644182158000000	1675718158000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc53666d04b495f67b78dbaf1a2c5edd000653adb2882339584e58d3cacb1d2858c5e6b6ee16e2d33228e3662581832e46fed3bea07ebd509b23bc59b52e9b16c	\\x00800003c206fc93c42795d787af41b2d1fbff2a7542de93aec7c754fb0273122394178e8e869e416614cbae6dc0e604f87470fd16b25702d9a149024f2af030a78aaccdc4bcb8a08388a6af5f5fa27d47d274f4eec55c1732f70129aad997a357f169f4f56e172749fbe26764e319d64cc9a5cfab3f823f44197c62926b7483a64a940b010001	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	\\x42992d1cca5c47085ed1a043a289552cbff9c90978e9d17d54a71ba35cc7caf347cc0e05b8b8d83c033c35a79ce2639e03d51b7a1d12c8d761371ab02d3b5a03	1581714658000000	1582319458000000	1644786658000000	1676322658000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xafa9f3933a23cac6f44afda432f5aee089f18b073a99e3c56815e71032328024aafcee9dd9e268bbe5bf7871df5bc94c0626f632d6e484dca1ca7f02543f1bc9	\\x00800003e8357166e575044f7f69e73fd8c336a7be1e9f843b5b28d6e0f572654774db4a0621be21fd4271772cc67cdf8ff1eee3b007e4a15b8d9b56388b61284ee916f50a3fe3837435c9bb8599ee4727999b0f6f7281090430f9cbe700fba3ba9b205648bd5d12c9720d3cc599e8ebc95fbee5c39afdd231d86c174ad972888836f9fd010001	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	\\x34b4e30594f98f87737997cc47f44cfaadef0243a999a01168d14286f66c78ce88f92abc6753609e84de52b711d24677062327d5109d33ce120cfac45b2f3e02	1579296658000000	1579901458000000	1642368658000000	1673904658000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xdafa4b1f24278c6a9759fa56d405abf52f370b30ad91e7bbb0d2053d86551af8d0eef86d972bd7b877d8a08b0d2b6a1479d59b1b7ca0e510e833884f05bcc685	\\x00800003b6ce671b0b29a5fbc5ef2c894995a460ff84c622735972bfe883284dac4b7fb10126eeaa01a6f22934e06898e73b8f23e8dc36997e4a162abed0a29fdc1c71b5144e7e9496bc20439abd35e3385d59415687f4a0ec013c4930d1ce1ed3cbdbf9b3eec07229115200a642e1b575b1e432cbef201dc6ee290e0491dac60ae9819d010001	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	\\x6192797b9c9b0aeabdd27e27c0ca1e69b6b078f9f338eea09e632d4a8facc2c2b5e7fe80e29c100fbe6044c6005804e4aa8a4462162790fc1fd71d35643f8403	1580505658000000	1581110458000000	1643577658000000	1675113658000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x0f68eecd9ff224a6dac11e2c5df0a018e4a632ebe64fd87278cfa8b8fd5780220977286ae788cd2f75734255ee27d21af050f684410cb3694275e78c6a812baf	\\x00800003aa8c1b61bd09442a02750285656d2398a5ce0ab812586116ec3f273d5497754ea68d4832b21a4e1ee20a35a066cbf0f0c3ee766b3cb09622be74183e02bb6c099a25f038451cc3832fa0198c95d8a5955bf4ac3c2493179787c81155139be110bdbfe73faf28d631526395c64f8ad5d0e04409fe1d972ba8d42fb980a7a322a3010001	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	\\x4089960554bc26a994a422c5c422ea1cf27298fe13414ad818b793f5e3de32de6cdb71c10ce3f13bfd630d0f55786d91a7d4dff288417713e0a29056dd52220c	1579901158000000	1580505958000000	1642973158000000	1674509158000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xefea9f7928e5349551129ec8d6e4588aa8f25d80d6d03cebba27cef2b31fc2fa941d801900c8484dbfed4308b40083d652e8521ff0961977ffd74a0c61d6cccc	\\x00800003d388b848ca6f4968e7a9ed44c9506942b87166c2eadc1466f9a6a1c662a08689d387209bade0496a361299774473091733848fd03819248016bfef35622d34a1a473f60b0f28d28abaf5a7ced3c8a394d509f944d22af2bd46e1a7a79342caa46d8f4150777cfa4e0aafa2c5a2618729d00b5e913deb0b806e90e651ee4aaa25010001	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	\\x7139154c0acb19dbc49728c57a019594ea6d9b30bcdee20f1335473a2fbff501292872b161cf5806c6f6e1f0a0fa384958a0a0ee88cc4318082574ede16e4802	1581110158000000	1581714958000000	1644182158000000	1675718158000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x0fea2724ad61c9a580b9235607e056eaa9a32d696b605f0c9a5dd8fb45f6f5c910dea9987b65a4ff246cdf72927d0b9df6b5d39eba88057375832603557d0cdc	\\x00800003adcd5b9c489f7b468a93bf145e382a1726754ceb3b017ddb0a0d544e1dfe9ec3428fc30d12aaada8997d258eac1be4f65e33f6fe949d8b340b553924357f91c593a65f76c742015552299b7f7a562b7a546261b3fd0a3673cb0706517d83cc1609e38907a51248c665b505f725f58adb30614df3e219acd9ede8ae1f1d380203010001	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	\\x370be8f060e5f05b73a65aa6058ef9c28612c1e43ba43ac040c8bf58c4b169fc3c13493788680ac5d009c55292d7fc45c673a18277a5e85afc9c95f42db34107	1581714658000000	1582319458000000	1644786658000000	1676322658000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x7fe3c0af8df8fbeaf384ca6529a71515f9f457c71a0f718fd2f762032bfe122c958c31e4eabc9b6014ff1cb129616932cf7fb29ac8e960b2a948086d9bd726f2	\\x00800003c872d35542d7e8293d7b53128f31e0ab97bae065a060bd6fd84f4763cb3db82cae9a527fb90266392c6a19da8b38441772c9af357ad96bb5ad8bfd4697e64761ec3d56c75b971502e27b38b00462836f0e0548485d81e0b605eac05cba34c998baa0acc16e10400ac6cdd41c7b5b057be21c5be1f7964397a818c2246c5a1c47010001	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	\\x20b4bfaa027e7e1c64777f7d5954c27304522b539e8cdc575b096b5f0f9b029f1c6694f69113efd38796ccec56410db54da6a5e0264216c11e81a23cd218fd0a	1579296658000000	1579901458000000	1642368658000000	1673904658000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x609d7bb0d26a6423f75f7624664f4e026b10cf0501747d9751af737e1a4c9d2b2eb74cd4c0b2a15579df2b0e9d33d2cf6288d627f29b0d92aa49ba1843706ea0	\\x00800003e9d49e9ce9616475cf6bc0bc9ac0921ea983179f3e1d284b669d64dd9f900470e3a87dd07f8b59670b697ceaaba631c5e17df02e980f36e273f148bf6cfd16e03d8863fda69e0a2f8077a28a274aa2ad23bc9c0b1a94c277556577d0c2bc552025ee1428afa972a677a6a9dfa348d89bf8847ac2fea836df39d9be3f0d4a7487010001	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	\\x3de3f8329799d8eb71704c7d88a77c80a71fddf31c193a27faf4bc5ec145a08083459280d2c1cf5d34ced7f5b3f88b604810d4b6750d333ba594a53a6de03c0f	1580505658000000	1581110458000000	1643577658000000	1675113658000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x9f0d7658403a999325130a93fb833954cc8fbd17a7717b9a2505c73f3ef526b97fc7004937242077b5cbb2e4af18ac7e68b30b344ebf9e23a519d0f701392733	\\x00800003c9eb7042c5434ba9133c64744fe400e7b7debcf54790725aa282a07c899a84406000800a474187a1ff6d335eecf37bb9948d163da5eb0dda48b54e06327e560519098f1b66bc2bc61ed1071799513d902302e0d44c65073e80c8090d0b21b9764d80e54019252cdb04f4489fbdac8b107729e30eb5a7aa7574c025ea7a6d470f010001	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	\\xdf3c8a5bbc04d57e8d360de86d391f2c1fec8f48af532bfde97283c102114f213bf67f6dea09d99eba71ec89635bbba80a52b73e54e8a377b5e2aed282bb3e0e	1579901158000000	1580505958000000	1642973158000000	1674509158000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xdbb72e11db4836d2d2b0e60d1eec117d20098901614a59e4f35981828a6f724d520c1726c8d86cadbb4c658669503050e7d91448901c56d6cb8177c5b930b1fc	\\x00800003df605822b17f62cb836765fb0876e09b7b062ee7b7ea28883abb408f3b350dbe23295861933fbb6ee604bbef543fec320b81a5951af4ee545e3491a1329e5eab6b7d5ffda8b90f53bb43538da96141bae51c2632d3e8343a7cf023b138502ec4758d5dfbac114c02652f87153a881a80b0b0a43d2d4f0d831decc8ef05c2379d010001	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	\\x934bf2e618e97d481f535c44ab1d7b60bd3fb4d59fe93db1de6ab719e9a3c6d0c2f3eb9c65bda6c3b21801359e5916e1884d602013936718ff14959d84611b09	1581110158000000	1581714958000000	1644182158000000	1675718158000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x04fbae646aa2a7dcd46e5d85b3fa6b1df66914dfeb28db19f0e7ca636e4fe0b460b9efdc0d7940d9b6a18668fbf4df1b7b0c27beac32219f3327027f080299c8	\\x00800003a47c26dcc846de6dd544f6e12efe39f6124008897bbc001d9f054310492086be27259bfddc0a83c57340cacfff49173e96b1606604e01b9299de54c013104431b80dc7382b2d8923105933046b65eabd16ccde7b4191768357de7946ca0e56e05c6620d31f82b0d6ce7f6cf4fc28b8ea626634076479e706b9816970d6a21929010001	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	\\x70318bc5005be8e06f2cffb021d3bb9c8e9ced2738bf204842c7a13ef71645d5efd1f03792f406b5a10a5741c44fb1cd9ab6813f7a50d103b722aa77600a4008	1581714658000000	1582319458000000	1644786658000000	1676322658000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x61dbab5fd91563cb90b4bae46f0d6469c06db821dd0299a3b443231bf4ec16e151843f3a78d27a71aa94fa6ade1b97e3d717e6d0585f6e41570c87880ba0a309	\\x00800003e0a48c7bb834e96897243a65d5a8812a73eeac41ce7075d84270984d0439cd6c2929f65c0381edc16a5c7b0f1e0f08843f0190c89a4f7178cab0e2330f96491c4d85512fc51758088372a04df24601dc6b145867d414a20221903a83dbaf5d7aef99d0e428d44dcf773c15f46f7431ca1cdeb23007f9ed47e1f4d5417a066e73010001	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	\\x22c6e9d8f0f6d32f239fdf01369a689fb847ad452f300d02eab2e9c3a0602f5f9fbd15f31b9a73f6e2dfd8d7a0fa337c40a5b1ff40712c47911ae52f1d29d203	1579296658000000	1579901458000000	1642368658000000	1673904658000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xdc0ecd78edf519d4ccb27d650f5a1916f1fbb196aae3d8aa0bfba23e374c7e2ea20dd2aec98d8463844d678af8e1f6c1aa56c531fbeff00022b3dc71d3c6214a	\\x00800003b9007d1d9a03542e1c456ed22ee64494c47ef16dd1f79eec99c7dcb9196fb7dc8b9a7225d8fb062f5136cc1025ee6274ffccf36cc2ab461233e58ac04d6c37aa55584e46a8c17c270991c97d03489a4b15eb3c4bf755fb67ba94781e20e31ed2e47ca8f288c9388df721043a24474911a93919d29d0cdefe29c73c1932b42963010001	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	\\xead87fb62eb011c46279aa39dafcdcd1066bd6be63a9e09384d2849f679f49c20c17f0c914c2aaf6ecb5e72f930fb9ef8b3de4e844942e3fc6318c407df76e07	1580505658000000	1581110458000000	1643577658000000	1675113658000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x98c3a6684081835f954a9bf9a6fdc597b64b195a3c057b9b5354b80989c27ea5f6b0cb80e18e3da5c9034d20e59ebf55f82787bdc40b023486b86f0c22023bf9	\\x00800003c5f66e2f66611504870824753c37dd96c8a0548206a1ac83cea34e79160ddc23afe5544689272bc4b709bf62a98cc93ee6531879a1aad3b584236f93b3b161b2e50dc34eb2bed9345affddca25dd74f179b481250ec723dd3f6accf4161de3f85018561a033bb05c5123702ce2f1e4f699b5b20fab2bc79c74dc74178a7e04bf010001	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	\\x4346c9092b77e191cbc3d955e0d890a86e932be399098edef98663d097d69c0ef8904f4dbef82c70117df0fec6e1467bb301a59d6677b8a35580398e2a2dd804	1579901158000000	1580505958000000	1642973158000000	1674509158000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x002f5c6b67e908a59912aa86a46f762a7c09b28edc9941bde1093187690e4b7d347253f4105c253ff180554efa20e4b4dd41492bdd00eb75b59f65784ae6e711	\\x00800003ad40e8a2870384d8fc804af44e87345470a8499904dcc7583eeb7e6cb96256a3e7728b8f8a6d42cfbbb375c0a31ac46d0c33d5099965f12e59a935b2781b89f9f669a7ed6b555e1337787b5c337723f056129530fb1b6a1afd2b18f7b821bcd897491a71cdbc98e4e316d7e14ce1e768b3a4f4f4dc053d2cc8896b6b9b9da791010001	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	\\x4f0013f2ffbe99edc62c4788ad0fb349a6a1a431a02809e1a3858768b9953742ff313bc379e38fb895ce887bf03f3513d9558dcc7b03617b397bc343d8dd4b0d	1581110158000000	1581714958000000	1644182158000000	1675718158000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xea07964cec0f2280b6c3b963c025c33fe98c337cf8523808eacfa14c812c483e752d1a96b1e75bfebf3dc4a8a051bf9a1e013d1c7f168af6c7bbbab4a2980b84	\\x00800003bf24bfb67a28c41ca04cdcb1a389a7d8073d2f7cd05b53bd060715f9762b8b39856fb5dd183604cb5d72fdd0a65bdc3b41440215e592ea377575af4b1b0751085e0b9eb5e77da8a592e11af0fbc6d3f401f68a0f23157b6094a0b8b264e87cd581e2d5babb8cf59e56a56cc1c685326cb6fa7b66e494992bb33aad12f05028ef010001	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	\\xb5d9c3b3a727b86d66f567f7a7d705afee27dad746046aa1971c6433cb2fa0de037ce70445c7e5f7fcea3e637c16cf935a59e87861d45fedd3f2d14a53ad7e06	1581714658000000	1582319458000000	1644786658000000	1676322658000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x41bed9d057044697957d04dabe53d8877569b9ee9eb1c13634e3a2742ee601c4ef00530b6acd182764bbe3d36742807ebc6e753f8f97801bcecfd29b39ed6a2e	\\x00800003c5f81a36ec073ab091e96118a9f11618a7ce554f4a47ca287b30c38af871306e25127a75eb80aeed34685533f622e26b3f3be297a3e123d11fb6552ba4c81cda050d756bb2803a050b6d7b472625f4ec9be04c31b94c071bb26dfdc4e46349ac1711413ce456ca25f2235b4890ed0b10a2dd6b95dcae5b580d419a4a239a0fb9010001	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	\\x6fcc6fc56511f7b2f8534bd57ce882b7db92f28f984ea9cc39fad8916337fc3cbcc40b22a7c2c2ab5dcad5ac1121877374cf0224707e8abd0d1f95a54f58e30b	1579296658000000	1579901458000000	1642368658000000	1673904658000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x6440b17f894e3f08621cc8fe194fcf322f468f8c23b668b0254ba93d7a2e5a634fe1235e3d1940e14ed3d8e663fbf57bc00bed255ad484efc26554872e68e067	\\x00800003e26332ef9825e0606b713b12e3c8c4398f299e2b56e9a6546b779730cf2bd2e7e90f073e602f128a2d4ca596bf3bb54cc2f06ea741e0eb5aeb0f1fd21ebdf280568ba0277ac0acf97a22aa67e4769e2c2c5c2628f8b161cb543ab4cf1ab63af0a17d22e43f60fd91636cd3daf40802efd7ee9ceb293ac863608ca6b0b8bbe7a9010001	\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	\\x3fee0304dd0e30037fbad6c001438b19ee42c7ad2d406a4b13489115901b392c2ce3d75fb97bec0958e30d9b77a9b1c3affe471eba6f491fec8211fccd2e2d04	1580505658000000	1581110458000000	1643577658000000	1675113658000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_wire, "timestamp", refund_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	1	\\x20dbdbb18b31de01b1a0da3de90bf7bcb28b824943b5c9c9e648d7b711488bcc217bc4defd2a1d298af29a16ec0e26224300205d115beb8827758556163e69d4	\\x7c3e7feefc966addd9c3cfc20b426d67108f01d8ee2936477dffe919c04658825b4318493dcc8545da663d6db1bf0ec8dab131fd2963da24eda73ff58ffbdac7	1579296673000000	1579297573000000	0	9000000	\\xf8b9e33530d8a410650812d89c54db4013177a839c46ea01bde20cdfc87dd1ff	\\x8a05ace775104efb9f160297b7255569eb8232e8c4adabfaf702fe3185f5e233	\\x142628df70cdc948befec475c9cc9b7847653cf99681812d2eba2ed703f40ea808388c7fdbc2b479313e9d8e134d08ebb2c15a5f2392609f3565074c7d924505	\\x40bc237e2cc27094b1008db0c4ffbee389fef47015e7e2a9c2d3b953f4a35fd3	\\x167539f7d07f000000000000000000002ee62df701000000e0a5ffd5d07f000070d8b7be10560000890d00a4d07f00000a0d00a4d07f0000f00c00a4d07f0000
\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	2	\\x20dbdbb18b31de01b1a0da3de90bf7bcb28b824943b5c9c9e648d7b711488bcc217bc4defd2a1d298af29a16ec0e26224300205d115beb8827758556163e69d4	\\x7c3e7feefc966addd9c3cfc20b426d67108f01d8ee2936477dffe919c04658825b4318493dcc8545da663d6db1bf0ec8dab131fd2963da24eda73ff58ffbdac7	1579296673000000	1579297573000000	0	9000000	\\xc6b89861d95972b7a6d9124b7da5541a6cd2036e6da988cba3428198752054ef	\\x8a05ace775104efb9f160297b7255569eb8232e8c4adabfaf702fe3185f5e233	\\xb3ba1872dfb69b9451425ff7545c8813f16051b29cf4bb00f16c51eaa260ca8ecf670dcf37e3d4c6de589ec6fac069ce74772e492638f6c79b09dafef34b1203	\\x40bc237e2cc27094b1008db0c4ffbee389fef47015e7e2a9c2d3b953f4a35fd3	\\x167539f7d07f000000000000000000002ee62df701000000e0d57fefd07f000070d8b7be10560000890d00dcd07f00000a0d00dcd07f0000f00c00dcd07f0000
\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	3	\\x20dbdbb18b31de01b1a0da3de90bf7bcb28b824943b5c9c9e648d7b711488bcc217bc4defd2a1d298af29a16ec0e26224300205d115beb8827758556163e69d4	\\x7c3e7feefc966addd9c3cfc20b426d67108f01d8ee2936477dffe919c04658825b4318493dcc8545da663d6db1bf0ec8dab131fd2963da24eda73ff58ffbdac7	1579296673000000	1579297573000000	0	9000000	\\xe1999e3a3653e8d8aa955e573a4c78c242662fcb9dc815e669daacefb082e955	\\x8a05ace775104efb9f160297b7255569eb8232e8c4adabfaf702fe3185f5e233	\\xe1adc73951951e2361f575f9ef0fbc221c708b5d6acbae9170ce61e8a29b4bb2e1521b92790faf9d760dd12585024a5631ec2bb204904cc9eaf1a489894e3c0e	\\x40bc237e2cc27094b1008db0c4ffbee389fef47015e7e2a9c2d3b953f4a35fd3	\\x167539f7d07f000000000000000000002ee62df701000000e05598f5d07f000070d8b7be10560000890d00e8d07f00000a0d00e8d07f0000f00c00e8d07f0000
\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	4	\\x20dbdbb18b31de01b1a0da3de90bf7bcb28b824943b5c9c9e648d7b711488bcc217bc4defd2a1d298af29a16ec0e26224300205d115beb8827758556163e69d4	\\x7c3e7feefc966addd9c3cfc20b426d67108f01d8ee2936477dffe919c04658825b4318493dcc8545da663d6db1bf0ec8dab131fd2963da24eda73ff58ffbdac7	1579296673000000	1579297573000000	0	9000000	\\xc449910fe9bf0b4d84667ce2a1e8c43a5ef0e2934166c9706311612f84cfaee5	\\x8a05ace775104efb9f160297b7255569eb8232e8c4adabfaf702fe3185f5e233	\\x2213e7017817e6228709d82a793c7a6d199d968ea4d5209bddfbea9f586a4920a8c8abcca42ae7534fbd51c692f03526b6f45b821fa9a365cba4dac7cb9c6b04	\\x40bc237e2cc27094b1008db0c4ffbee389fef47015e7e2a9c2d3b953f4a35fd3	\\x167539f7d07f000000000000000000002ee62df701000000e0c5ff8ad07f000070d8b7be10560000890d0070d07f00000a0d0070d07f0000f00c0070d07f0000
\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	5	\\x20dbdbb18b31de01b1a0da3de90bf7bcb28b824943b5c9c9e648d7b711488bcc217bc4defd2a1d298af29a16ec0e26224300205d115beb8827758556163e69d4	\\x7c3e7feefc966addd9c3cfc20b426d67108f01d8ee2936477dffe919c04658825b4318493dcc8545da663d6db1bf0ec8dab131fd2963da24eda73ff58ffbdac7	1579296673000000	1579297573000000	0	9000000	\\xa3c3cb7f2d651e4290c74919e8f180bd98ad7a6271205612970c6b48f68cf1b0	\\x8a05ace775104efb9f160297b7255569eb8232e8c4adabfaf702fe3185f5e233	\\x37ee9283f72cef906ab88535db3bd8a13d97ca6e1e4b05692268189fbb5d3564b71fcbb95974855c047a7f66fbcc27af4979745f3a1030b3a568b19c7723cb02	\\x40bc237e2cc27094b1008db0c4ffbee389fef47015e7e2a9c2d3b953f4a35fd3	\\x167539f7d07f000000000000000000002ee62df701000000e085ffc0d07f000070d8b7be10560000890d0080d07f00000a0d0080d07f0000f00c0080d07f0000
\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	6	\\x20dbdbb18b31de01b1a0da3de90bf7bcb28b824943b5c9c9e648d7b711488bcc217bc4defd2a1d298af29a16ec0e26224300205d115beb8827758556163e69d4	\\x7c3e7feefc966addd9c3cfc20b426d67108f01d8ee2936477dffe919c04658825b4318493dcc8545da663d6db1bf0ec8dab131fd2963da24eda73ff58ffbdac7	1579296673000000	1579297573000000	3	18000000	\\xeffdc50eadd102fef8b9489aedaaa390996a195dccfca3a3ad280fd458bd063e	\\x8a05ace775104efb9f160297b7255569eb8232e8c4adabfaf702fe3185f5e233	\\x3ac1f0625d22331476ec5b9f04936b5169f461475b4ba42e74172b187d0d790732496893cee313b1480bbaa2e58e772ee24c378eaf8b43b260925de693edb905	\\x40bc237e2cc27094b1008db0c4ffbee389fef47015e7e2a9c2d3b953f4a35fd3	\\x167539f7d07f000000000000000000002ee62df701000000e0957f89d07f000070d8b7be10560000890d006cd07f00000a0d006cd07f0000f00c006cd07f0000
\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	7	\\x20dbdbb18b31de01b1a0da3de90bf7bcb28b824943b5c9c9e648d7b711488bcc217bc4defd2a1d298af29a16ec0e26224300205d115beb8827758556163e69d4	\\x7c3e7feefc966addd9c3cfc20b426d67108f01d8ee2936477dffe919c04658825b4318493dcc8545da663d6db1bf0ec8dab131fd2963da24eda73ff58ffbdac7	1579296673000000	1579297573000000	0	9000000	\\x4c6ee784dd3562fdf7ed8bbfc0e35056d567efef48c817e5fb226be904f8e073	\\x8a05ace775104efb9f160297b7255569eb8232e8c4adabfaf702fe3185f5e233	\\xf1b0bd3ec257fb6dbac352f3922d2603ef803dbec8be171d3c47daffae3cc770efcee74039e0e0b9d303042d2dbd53d4867b4d103bc2f5af869c24ed23f6e00a	\\x40bc237e2cc27094b1008db0c4ffbee389fef47015e7e2a9c2d3b953f4a35fd3	\\x167539f7d07f000000000000000000002ee62df701000000e0b57f8ad07f000070d8b7be10560000890d0074d07f00000a0d0074d07f0000f00c0074d07f0000
\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	8	\\x20dbdbb18b31de01b1a0da3de90bf7bcb28b824943b5c9c9e648d7b711488bcc217bc4defd2a1d298af29a16ec0e26224300205d115beb8827758556163e69d4	\\x7c3e7feefc966addd9c3cfc20b426d67108f01d8ee2936477dffe919c04658825b4318493dcc8545da663d6db1bf0ec8dab131fd2963da24eda73ff58ffbdac7	1579296673000000	1579297573000000	0	9000000	\\x252a0e83a162e59c0ca1c979d4910aca6fd9e108b9148d3c52266cc53de02ca3	\\x8a05ace775104efb9f160297b7255569eb8232e8c4adabfaf702fe3185f5e233	\\xfb5083a50449df54873575042edb5572c5bfe031cfc4d51a01725f2557508f6116beac54fec34590dd0dc32838763bc74ae1dabcd07f1d09373c9ae3d0ac970a	\\x40bc237e2cc27094b1008db0c4ffbee389fef47015e7e2a9c2d3b953f4a35fd3	\\x167539f7d07f000000000000000000002ee62df701000000e085ff88d07f000070d8b7be10560000598f0060d07f0000da8e0060d07f0000c08e0060d07f0000
\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	9	\\x20dbdbb18b31de01b1a0da3de90bf7bcb28b824943b5c9c9e648d7b711488bcc217bc4defd2a1d298af29a16ec0e26224300205d115beb8827758556163e69d4	\\x7c3e7feefc966addd9c3cfc20b426d67108f01d8ee2936477dffe919c04658825b4318493dcc8545da663d6db1bf0ec8dab131fd2963da24eda73ff58ffbdac7	1579296673000000	1579297573000000	0	9000000	\\xdef404f7c1af93a8e435223c513801f77dc6abb5551377fea8a9ca886f8db03f	\\x8a05ace775104efb9f160297b7255569eb8232e8c4adabfaf702fe3185f5e233	\\x20821259470941422666fb9bdd811d7c604695e1b4685bbb99e03e020b255c15db05fb459d5ae07bc664e20b761bbf4ca15501b794f0331e7ab969c7eb340706	\\x40bc237e2cc27094b1008db0c4ffbee389fef47015e7e2a9c2d3b953f4a35fd3	\\x167539f7d07f000000000000000000002ee62df701000000e04518f5d07f000070d8b7be10560000890d00e0d07f00000a0d00e0d07f0000f00c00e0d07f0000
\.


--
-- Data for Name: deposits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits (deposit_serial_id, coin_pub, amount_with_fee_val, amount_with_fee_frac, "timestamp", refund_deadline, wire_deadline, merchant_pub, h_contract_terms, h_wire, coin_sig, wire, tiny, done) FROM stdin;
1	\\xa3c3cb7f2d651e4290c74919e8f180bd98ad7a6271205612970c6b48f68cf1b0	0	10000000	1579296673000000	1579297573000000	1579297573000000	\\x8a05ace775104efb9f160297b7255569eb8232e8c4adabfaf702fe3185f5e233	\\x20dbdbb18b31de01b1a0da3de90bf7bcb28b824943b5c9c9e648d7b711488bcc217bc4defd2a1d298af29a16ec0e26224300205d115beb8827758556163e69d4	\\x7c3e7feefc966addd9c3cfc20b426d67108f01d8ee2936477dffe919c04658825b4318493dcc8545da663d6db1bf0ec8dab131fd2963da24eda73ff58ffbdac7	\\x79b6d2181051004c5671d613dfc51b50826d2b345bf8070dc888c4b3675f019b417b41e887ec0aa448a4c6ef30477374f0b4e920309dac70227221a2045f8309	{"url":"payto://x-taler-bank/localhost/3","salt":"NWEWKGZ74S1369EF3JMT8F4X2R95G9ZFV03YZQ1PFGCAPVZYM3B0X03NTYVZ9DM2QR28QFZSVE4SQ1V1XDGYEPMRE0B86J8C9RS8ZPR"}	f	f
2	\\xf8b9e33530d8a410650812d89c54db4013177a839c46ea01bde20cdfc87dd1ff	0	10000000	1579296673000000	1579297573000000	1579297573000000	\\x8a05ace775104efb9f160297b7255569eb8232e8c4adabfaf702fe3185f5e233	\\x20dbdbb18b31de01b1a0da3de90bf7bcb28b824943b5c9c9e648d7b711488bcc217bc4defd2a1d298af29a16ec0e26224300205d115beb8827758556163e69d4	\\x7c3e7feefc966addd9c3cfc20b426d67108f01d8ee2936477dffe919c04658825b4318493dcc8545da663d6db1bf0ec8dab131fd2963da24eda73ff58ffbdac7	\\x3db80f958160912e5874bf0d32a127356544dc8fbb06adf39e6d382965424c71c99d4767c5656c083c23376a5b8b12e495d667c1e256d7aeb207997575e34704	{"url":"payto://x-taler-bank/localhost/3","salt":"NWEWKGZ74S1369EF3JMT8F4X2R95G9ZFV03YZQ1PFGCAPVZYM3B0X03NTYVZ9DM2QR28QFZSVE4SQ1V1XDGYEPMRE0B86J8C9RS8ZPR"}	f	f
3	\\xeffdc50eadd102fef8b9489aedaaa390996a195dccfca3a3ad280fd458bd063e	3	20000000	1579296673000000	1579297573000000	1579297573000000	\\x8a05ace775104efb9f160297b7255569eb8232e8c4adabfaf702fe3185f5e233	\\x20dbdbb18b31de01b1a0da3de90bf7bcb28b824943b5c9c9e648d7b711488bcc217bc4defd2a1d298af29a16ec0e26224300205d115beb8827758556163e69d4	\\x7c3e7feefc966addd9c3cfc20b426d67108f01d8ee2936477dffe919c04658825b4318493dcc8545da663d6db1bf0ec8dab131fd2963da24eda73ff58ffbdac7	\\xc454fb05062ab7f05cc503101d8761fc6ffe25bff4fd6ae19047aa1b4efcf67a66f13436d0482e576f52a22ac933bd0cd9f28e80d5c80747dff62212d37bef0d	{"url":"payto://x-taler-bank/localhost/3","salt":"NWEWKGZ74S1369EF3JMT8F4X2R95G9ZFV03YZQ1PFGCAPVZYM3B0X03NTYVZ9DM2QR28QFZSVE4SQ1V1XDGYEPMRE0B86J8C9RS8ZPR"}	f	f
4	\\x252a0e83a162e59c0ca1c979d4910aca6fd9e108b9148d3c52266cc53de02ca3	0	10000000	1579296673000000	1579297573000000	1579297573000000	\\x8a05ace775104efb9f160297b7255569eb8232e8c4adabfaf702fe3185f5e233	\\x20dbdbb18b31de01b1a0da3de90bf7bcb28b824943b5c9c9e648d7b711488bcc217bc4defd2a1d298af29a16ec0e26224300205d115beb8827758556163e69d4	\\x7c3e7feefc966addd9c3cfc20b426d67108f01d8ee2936477dffe919c04658825b4318493dcc8545da663d6db1bf0ec8dab131fd2963da24eda73ff58ffbdac7	\\x34d83f725acfa5d44f6679c521f988340d299dbcf8ae242dfef478c2913a87140b446002933e48de79d0727bd2ca599049fa0e7e9f16ebb329ebd939181d950d	{"url":"payto://x-taler-bank/localhost/3","salt":"NWEWKGZ74S1369EF3JMT8F4X2R95G9ZFV03YZQ1PFGCAPVZYM3B0X03NTYVZ9DM2QR28QFZSVE4SQ1V1XDGYEPMRE0B86J8C9RS8ZPR"}	f	f
5	\\x4c6ee784dd3562fdf7ed8bbfc0e35056d567efef48c817e5fb226be904f8e073	0	10000000	1579296673000000	1579297573000000	1579297573000000	\\x8a05ace775104efb9f160297b7255569eb8232e8c4adabfaf702fe3185f5e233	\\x20dbdbb18b31de01b1a0da3de90bf7bcb28b824943b5c9c9e648d7b711488bcc217bc4defd2a1d298af29a16ec0e26224300205d115beb8827758556163e69d4	\\x7c3e7feefc966addd9c3cfc20b426d67108f01d8ee2936477dffe919c04658825b4318493dcc8545da663d6db1bf0ec8dab131fd2963da24eda73ff58ffbdac7	\\x12aaf1e23e75bef0da16fe9599be911832bc7e3644e940e2a4a12b3d4851f5d9af7ac10774e20d3e8688c849dfcf1cd51f7d4ae9cf25db6171816773357dab02	{"url":"payto://x-taler-bank/localhost/3","salt":"NWEWKGZ74S1369EF3JMT8F4X2R95G9ZFV03YZQ1PFGCAPVZYM3B0X03NTYVZ9DM2QR28QFZSVE4SQ1V1XDGYEPMRE0B86J8C9RS8ZPR"}	f	f
6	\\xe1999e3a3653e8d8aa955e573a4c78c242662fcb9dc815e669daacefb082e955	0	10000000	1579296673000000	1579297573000000	1579297573000000	\\x8a05ace775104efb9f160297b7255569eb8232e8c4adabfaf702fe3185f5e233	\\x20dbdbb18b31de01b1a0da3de90bf7bcb28b824943b5c9c9e648d7b711488bcc217bc4defd2a1d298af29a16ec0e26224300205d115beb8827758556163e69d4	\\x7c3e7feefc966addd9c3cfc20b426d67108f01d8ee2936477dffe919c04658825b4318493dcc8545da663d6db1bf0ec8dab131fd2963da24eda73ff58ffbdac7	\\xc42acaec635d6d580ab32187443f0f49b8e601daf2beb6d04588cce9186a301900ac3adc4b7689b95447373069f222638c1f93c53f4b3a868ed4e07269cf680a	{"url":"payto://x-taler-bank/localhost/3","salt":"NWEWKGZ74S1369EF3JMT8F4X2R95G9ZFV03YZQ1PFGCAPVZYM3B0X03NTYVZ9DM2QR28QFZSVE4SQ1V1XDGYEPMRE0B86J8C9RS8ZPR"}	f	f
7	\\xdef404f7c1af93a8e435223c513801f77dc6abb5551377fea8a9ca886f8db03f	0	10000000	1579296673000000	1579297573000000	1579297573000000	\\x8a05ace775104efb9f160297b7255569eb8232e8c4adabfaf702fe3185f5e233	\\x20dbdbb18b31de01b1a0da3de90bf7bcb28b824943b5c9c9e648d7b711488bcc217bc4defd2a1d298af29a16ec0e26224300205d115beb8827758556163e69d4	\\x7c3e7feefc966addd9c3cfc20b426d67108f01d8ee2936477dffe919c04658825b4318493dcc8545da663d6db1bf0ec8dab131fd2963da24eda73ff58ffbdac7	\\xfdc827205c6e11b07e1a071a7b8ec48a46050f9ea5abee2179ecd90b1873794b5ba2092755dec4fd5d2b7d1c81e8aa0c4d95ce6fee51de0d4b88ba21ce4e8700	{"url":"payto://x-taler-bank/localhost/3","salt":"NWEWKGZ74S1369EF3JMT8F4X2R95G9ZFV03YZQ1PFGCAPVZYM3B0X03NTYVZ9DM2QR28QFZSVE4SQ1V1XDGYEPMRE0B86J8C9RS8ZPR"}	f	f
8	\\xc6b89861d95972b7a6d9124b7da5541a6cd2036e6da988cba3428198752054ef	0	10000000	1579296673000000	1579297573000000	1579297573000000	\\x8a05ace775104efb9f160297b7255569eb8232e8c4adabfaf702fe3185f5e233	\\x20dbdbb18b31de01b1a0da3de90bf7bcb28b824943b5c9c9e648d7b711488bcc217bc4defd2a1d298af29a16ec0e26224300205d115beb8827758556163e69d4	\\x7c3e7feefc966addd9c3cfc20b426d67108f01d8ee2936477dffe919c04658825b4318493dcc8545da663d6db1bf0ec8dab131fd2963da24eda73ff58ffbdac7	\\x8e0666434107ee1c837045b3c8036ab6c4249573127f72fc0d576a1bbb44edaac65ed874fe99e2be0af36b11f820c0c8f3652d7d33fe0e989112400831b4d107	{"url":"payto://x-taler-bank/localhost/3","salt":"NWEWKGZ74S1369EF3JMT8F4X2R95G9ZFV03YZQ1PFGCAPVZYM3B0X03NTYVZ9DM2QR28QFZSVE4SQ1V1XDGYEPMRE0B86J8C9RS8ZPR"}	f	f
9	\\xc449910fe9bf0b4d84667ce2a1e8c43a5ef0e2934166c9706311612f84cfaee5	0	10000000	1579296673000000	1579297573000000	1579297573000000	\\x8a05ace775104efb9f160297b7255569eb8232e8c4adabfaf702fe3185f5e233	\\x20dbdbb18b31de01b1a0da3de90bf7bcb28b824943b5c9c9e648d7b711488bcc217bc4defd2a1d298af29a16ec0e26224300205d115beb8827758556163e69d4	\\x7c3e7feefc966addd9c3cfc20b426d67108f01d8ee2936477dffe919c04658825b4318493dcc8545da663d6db1bf0ec8dab131fd2963da24eda73ff58ffbdac7	\\x9244709a2a5c100e74727f88af6867c0bd1eafe359081d68fa029210f0fa29138944e4a96f03591f1f0f6c692968ce9cd4a73c33edfcf4c72e0d41855c4bfb07	{"url":"payto://x-taler-bank/localhost/3","salt":"NWEWKGZ74S1369EF3JMT8F4X2R95G9ZFV03YZQ1PFGCAPVZYM3B0X03NTYVZ9DM2QR28QFZSVE4SQ1V1XDGYEPMRE0B86J8C9RS8ZPR"}	f	f
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
1	contenttypes	0001_initial	2020-01-17 22:31:09.434737+01
2	auth	0001_initial	2020-01-17 22:31:09.458715+01
3	app	0001_initial	2020-01-17 22:31:09.503866+01
4	contenttypes	0002_remove_content_type_name	2020-01-17 22:31:09.522687+01
5	auth	0002_alter_permission_name_max_length	2020-01-17 22:31:09.52632+01
6	auth	0003_alter_user_email_max_length	2020-01-17 22:31:09.531812+01
7	auth	0004_alter_user_username_opts	2020-01-17 22:31:09.53731+01
8	auth	0005_alter_user_last_login_null	2020-01-17 22:31:09.543016+01
9	auth	0006_require_contenttypes_0002	2020-01-17 22:31:09.544255+01
10	auth	0007_alter_validators_add_error_messages	2020-01-17 22:31:09.549981+01
11	auth	0008_alter_user_username_max_length	2020-01-17 22:31:09.559718+01
12	auth	0009_alter_user_last_name_max_length	2020-01-17 22:31:09.566583+01
13	auth	0010_alter_group_name_max_length	2020-01-17 22:31:09.573857+01
14	auth	0011_update_proxy_permissions	2020-01-17 22:31:09.581895+01
15	sessions	0001_initial	2020-01-17 22:31:09.586819+01
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
\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1577833200000000	1609455600000000	\\xddee981a9639b88ae78a592f00f376733fc510add7418088a704d920a1d56cdfe1af9d510a6ed17e8750881349f180bbbad5133401b5c31ef1821c05aa09f30d
\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1609455600000000	1640991600000000	\\x90a42a222090563286a4799291412a948fff2c51428651561ca0a23d57430cc1c41a18b88772c3183308dd932bd7d5d01c22bc352002dc08564c042d3f8cd606
\\x014952fb749ca7ced0005c73b6f92d3cb914ead28e0713937f50d4f1e6857bac	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1640991600000000	1672527600000000	\\x31a3a9a61ce6444b46c26445a504a86189d439f9a6ddbd7507bcb37d78ecbe3526b35161e3c71c7afa70bedeec602f04aeb69213ff1eede53b2e6cc98b9b4300
\.


--
-- Data for Name: known_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.known_coins (coin_pub, denom_pub_hash, denom_sig) FROM stdin;
\\xa3c3cb7f2d651e4290c74919e8f180bd98ad7a6271205612970c6b48f68cf1b0	\\x61dbab5fd91563cb90b4bae46f0d6469c06db821dd0299a3b443231bf4ec16e151843f3a78d27a71aa94fa6ade1b97e3d717e6d0585f6e41570c87880ba0a309	\\xdeaaff6ae3547230fa7fa427ed8ff650c432ca3bba8fdb26a0ab6a53b40b25ee6b9dbf9ed2a3f6acaf3fbabe8bd593cda179f3545cf6fbae780314181cd9ceb0a656b0a13ad91913f8f578c7869c96659a35437ce3e0b64417fedfb3ec3a0d06dda009b73ff1eabc7297fa2f657ac8cb7befd420dde44c4be50a72b703d53ebc
\\xf8b9e33530d8a410650812d89c54db4013177a839c46ea01bde20cdfc87dd1ff	\\x61dbab5fd91563cb90b4bae46f0d6469c06db821dd0299a3b443231bf4ec16e151843f3a78d27a71aa94fa6ade1b97e3d717e6d0585f6e41570c87880ba0a309	\\x585a09afd377858f8d64197136050c0cafc5b8a3c8abca28e88e28dd6f8a4c77b756414959e44509b022cf0cb8c09a32c3854029ab6d739ac295e7fb891323aaa747b3bfdf5fff6acecc00b76fa5ac582b94d210e3e86af134547113382d8e954b7f0e9926793a4a51f0c4517a1aaccc420e9dfa4238a7bb72b0e914b80101e0
\\xeffdc50eadd102fef8b9489aedaaa390996a195dccfca3a3ad280fd458bd063e	\\x41bed9d057044697957d04dabe53d8877569b9ee9eb1c13634e3a2742ee601c4ef00530b6acd182764bbe3d36742807ebc6e753f8f97801bcecfd29b39ed6a2e	\\x0bd5336e244fd8e17da7fc4f78446fc894ae733aab5dd3d57aade9010d9bc8b8a1812cf2c5de05e17a86cc0ebd410bb3a8332678705435c4152477b7bb741b314052d4c3afa51413286601038286cd6f0ade269b9ee67c586fe386b233882c153490726d0cf39cd771db3e42ecad5ef3c2ef4e73cab10a767e62b9421c003d21
\\x252a0e83a162e59c0ca1c979d4910aca6fd9e108b9148d3c52266cc53de02ca3	\\x61dbab5fd91563cb90b4bae46f0d6469c06db821dd0299a3b443231bf4ec16e151843f3a78d27a71aa94fa6ade1b97e3d717e6d0585f6e41570c87880ba0a309	\\xa95572567fda9bad45ad9220acf478d1852f7df40e1e6e4ac14f34f006287b0951f5d7e1218f7e7eeef00d13073e7b273e265d25a65aa352e2de3cb81f119d700b3ef808ff54f266a2bcf63398b52563408e0006850d1e562d26bf6abb26e34d8dc8c05103e1f3d3da18ea2fa88a915f4f3f8c88e213e96dd371a7d75d2da10c
\\xe1999e3a3653e8d8aa955e573a4c78c242662fcb9dc815e669daacefb082e955	\\x61dbab5fd91563cb90b4bae46f0d6469c06db821dd0299a3b443231bf4ec16e151843f3a78d27a71aa94fa6ade1b97e3d717e6d0585f6e41570c87880ba0a309	\\x5f6a90875ef8d82d83b642947d43edf586d29775a6ff72b24af4a87e514ea7184e0b56f7d876efaf1bf056de437da71aa963135811aaa410f20960d5314134216e2d47aeb0e4f851ae3f12637d3a766610c2f4aece3a71024f8548f6da7bfb381053d2c2e0d300dd07d2917b4dc7556b89ecf13194a10699245ea888eeaad801
\\x4c6ee784dd3562fdf7ed8bbfc0e35056d567efef48c817e5fb226be904f8e073	\\x61dbab5fd91563cb90b4bae46f0d6469c06db821dd0299a3b443231bf4ec16e151843f3a78d27a71aa94fa6ade1b97e3d717e6d0585f6e41570c87880ba0a309	\\x29cfaa90df7927bb4f69e2e4ba17a2d413d2d440b2c7226ef850b59035683edab1e4928ad4aebe3adcccff64c0c4edee4cc9b1b7399499fb2567878cf9b0b92f1b6a94a74b15400d88dffb516c5e8ed9cdb00f5d079b446b4d72da96bd0139cf88fb2ea6e6e4948a3e6f0f0a7f0e6f5a7c1f1535e0d6cd7c4138c0c27dbcca5e
\\xc449910fe9bf0b4d84667ce2a1e8c43a5ef0e2934166c9706311612f84cfaee5	\\x61dbab5fd91563cb90b4bae46f0d6469c06db821dd0299a3b443231bf4ec16e151843f3a78d27a71aa94fa6ade1b97e3d717e6d0585f6e41570c87880ba0a309	\\x8f72210ab2cf52cfaf9c89d5e3a05cafebd69b12dc1f0ddff0660edaa5941efab475d6d73eafd237578cde5de247f125e3295cf041ab2a9f4f08016e1bbdde2ca65e448ee3f2a3a6a3eb135d38510dd9dfc43cddf0d6764e166009e73ba3ff9cf5065dee4cdc48f30874b0d3e953b13176aa17e92c8fe237abe53bef43ffbee5
\\xdef404f7c1af93a8e435223c513801f77dc6abb5551377fea8a9ca886f8db03f	\\x61dbab5fd91563cb90b4bae46f0d6469c06db821dd0299a3b443231bf4ec16e151843f3a78d27a71aa94fa6ade1b97e3d717e6d0585f6e41570c87880ba0a309	\\x24a2a24c979b96fe51b9f67a65b19eb2af53af74efd0cbe8087e5dfa13e4a94cd47e9f150745ab2919971f308ea6241ca25b0f5741e6518e440feee8dd5aa5f4eec5dbfb281beeed28d99c3a25012b4d6852e9830e610f9c874a1c6ccdfdb99e2641c41b0ae289370bbc55d2f4649fec500c21cda793fad4a2411a27187aeb7f
\\xc6b89861d95972b7a6d9124b7da5541a6cd2036e6da988cba3428198752054ef	\\x61dbab5fd91563cb90b4bae46f0d6469c06db821dd0299a3b443231bf4ec16e151843f3a78d27a71aa94fa6ade1b97e3d717e6d0585f6e41570c87880ba0a309	\\x1d1236c4dc62b1f5572ae268475940876895bd4522de790dae4812d1a1e37211d7f3a5490f921116c969384643bf4b5837b45b197d96ccb54d981186bd8c7f2c8aff0aaca4c998f7458dc173f279796da44cba267c3b32f00a44cc9e4dde198e90b1bb0b1a96a9385c8b0cd18c851a99c5fb8f846158e8447329c795118219da
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_id, merchant_pub, contract_terms, h_contract_terms, "timestamp", row_id, paid) FROM stdin;
2020.017-00J71MM824W6J	\\x8a05ace775104efb9f160297b7255569eb8232e8c4adabfaf702fe3185f5e233	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2268747470733a2f2f6578616d706c652e636f6d2f222c22726566756e645f646561646c696e65223a7b22745f6d73223a313537393239373537333030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313537393239373537333030307d2c226f726465725f6964223a22323032302e3031372d30304a37314d4d38323457364a222c2274696d657374616d70223a7b22745f6d73223a313537393239363637333030307d2c227061795f646561646c696e65223a7b22745f6d73223a313537393338333037333030307d2c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a223035344e3559564d4b4a4b57584d30304248535644593944374a57483954504a485233483734565a4133414633534d3546455030227d5d2c2261756469746f7273223a5b5d2c22685f77697265223a2246475a375a5651574a534e4456504533535a313050474b44435738385930455258524d4b434856585a5a4d484b4732364232313550475252393459575331413556394b33545644485157374348504e483637594a4a525954344b505445465a4e485a58584e4852222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a22483832545353564e3231374651375250304142564539414e44374e5234435138524a50545159515130425a333331464e57385347222c226e6f6e6365223a224e3947544e514b4839304a304354505952314636454e4135503345574537483056515351424137454b384b5347324e41314e5630227d	\\x20dbdbb18b31de01b1a0da3de90bf7bcb28b824943b5c9c9e648d7b711488bcc217bc4defd2a1d298af29a16ec0e26224300205d115beb8827758556163e69d4	1579296673000000	1	t
\.


--
-- Data for Name: merchant_deposits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_deposits (h_contract_terms, merchant_pub, coin_pub, exchange_url, amount_with_fee_val, amount_with_fee_frac, deposit_fee_val, deposit_fee_frac, refund_fee_val, refund_fee_frac, wire_fee_val, wire_fee_frac, signkey_pub, exchange_proof) FROM stdin;
\\x20dbdbb18b31de01b1a0da3de90bf7bcb28b824943b5c9c9e648d7b711488bcc217bc4defd2a1d298af29a16ec0e26224300205d115beb8827758556163e69d4	\\x8a05ace775104efb9f160297b7255569eb8232e8c4adabfaf702fe3185f5e233	\\xf8b9e33530d8a410650812d89c54db4013177a839c46ea01bde20cdfc87dd1ff	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x40bc237e2cc27094b1008db0c4ffbee389fef47015e7e2a9c2d3b953f4a35fd3	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2232474b32485156475351344d48465159524854574b4b345646313350414637534a543052324239455138514445305a4d31544d3047453443465a44573544335336345a395633474b394d3445514350314239464a37344b304b5754504131544346503934413138222c22707562223a2238325932365a4843523952393943383048505243395a58595745345a5858334732514b59354145325445574e37583533425a3947227d
\\x20dbdbb18b31de01b1a0da3de90bf7bcb28b824943b5c9c9e648d7b711488bcc217bc4defd2a1d298af29a16ec0e26224300205d115beb8827758556163e69d4	\\x8a05ace775104efb9f160297b7255569eb8232e8c4adabfaf702fe3185f5e233	\\x252a0e83a162e59c0ca1c979d4910aca6fd9e108b9148d3c52266cc53de02ca3	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x40bc237e2cc27094b1008db0c4ffbee389fef47015e7e2a9c2d3b953f4a35fd3	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a225a443838373938343937464e3931534e454d32325850544e454232565a523148535a3244413647314539464a414e54474858474844464e43414b5a4336484347564d36573641315245525857454a513156415944305a52583134564b5336513354325039453247222c22707562223a2238325932365a4843523952393943383048505243395a58595745345a5858334732514b59354145325445574e37583533425a3947227d
\\x20dbdbb18b31de01b1a0da3de90bf7bcb28b824943b5c9c9e648d7b711488bcc217bc4defd2a1d298af29a16ec0e26224300205d115beb8827758556163e69d4	\\x8a05ace775104efb9f160297b7255569eb8232e8c4adabfaf702fe3185f5e233	\\x4c6ee784dd3562fdf7ed8bbfc0e35056d567efef48c817e5fb226be904f8e073	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x40bc237e2cc27094b1008db0c4ffbee389fef47015e7e2a9c2d3b953f4a35fd3	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a225936524254465032415a5850564550334142535334423936304651523046445953325a3145373957385a44465a424857525852455a4b513738305759315235535443314738423944514e395839314b56394d38335147514e4e5933395239374434465645303247222c22707562223a2238325932365a4843523952393943383048505243395a58595745345a5858334732514b59354145325445574e37583533425a3947227d
\\x20dbdbb18b31de01b1a0da3de90bf7bcb28b824943b5c9c9e648d7b711488bcc217bc4defd2a1d298af29a16ec0e26224300205d115beb8827758556163e69d4	\\x8a05ace775104efb9f160297b7255569eb8232e8c4adabfaf702fe3185f5e233	\\xa3c3cb7f2d651e4290c74919e8f180bd98ad7a6271205612970c6b48f68cf1b0	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x40bc237e2cc27094b1008db0c4ffbee389fef47015e7e2a9c2d3b953f4a35fd3	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22365a513935305a51354b515330544e52474d5458504559524d345953464a4b453353354741543932443043395a455458364e4a42453759425135435139314157304858375953515653474b54594a42534548464b4d34314750454a504843435745574857503047222c22707562223a2238325932365a4843523952393943383048505243395a58595745345a5858334732514b59354145325445574e37583533425a3947227d
\\x20dbdbb18b31de01b1a0da3de90bf7bcb28b824943b5c9c9e648d7b711488bcc217bc4defd2a1d298af29a16ec0e26224300205d115beb8827758556163e69d4	\\x8a05ace775104efb9f160297b7255569eb8232e8c4adabfaf702fe3185f5e233	\\xc449910fe9bf0b4d84667ce2a1e8c43a5ef0e2934166c9706311612f84cfaee5	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x40bc237e2cc27094b1008db0c4ffbee389fef47015e7e2a9c2d3b953f4a35fd3	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a223438395945304252325a4b323531523956304e374a463354444d435356354d454d4b414a313659585a464e395950334139344741484a3542534a4a324e53544b3959594e33484d4a5930544a4444514d424531315a414433435135543950503753454536503130222c22707562223a2238325932365a4843523952393943383048505243395a58595745345a5858334732514b59354145325445574e37583533425a3947227d
\\x20dbdbb18b31de01b1a0da3de90bf7bcb28b824943b5c9c9e648d7b711488bcc217bc4defd2a1d298af29a16ec0e26224300205d115beb8827758556163e69d4	\\x8a05ace775104efb9f160297b7255569eb8232e8c4adabfaf702fe3185f5e233	\\xc6b89861d95972b7a6d9124b7da5541a6cd2036e6da988cba3428198752054ef	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x40bc237e2cc27094b1008db0c4ffbee389fef47015e7e2a9c2d3b953f4a35fd3	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22504558314757505a50544453384d4132425a564e3851343832465250304d444a4b4b544250303748444838594e384b30534137435953524453575659374e3636565343395848515452314d57575833513553344a43453750525944474b50515959443548343052222c22707562223a2238325932365a4843523952393943383048505243395a58595745345a5858334732514b59354145325445574e37583533425a3947227d
\\x20dbdbb18b31de01b1a0da3de90bf7bcb28b824943b5c9c9e648d7b711488bcc217bc4defd2a1d298af29a16ec0e26224300205d115beb8827758556163e69d4	\\x8a05ace775104efb9f160297b7255569eb8232e8c4adabfaf702fe3185f5e233	\\xdef404f7c1af93a8e435223c513801f77dc6abb5551377fea8a9ca886f8db03f	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x40bc237e2cc27094b1008db0c4ffbee389fef47015e7e2a9c2d3b953f4a35fd3	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2234323131345041373135304d34394b365a45445856303858464847344435463150484d355145575357305a303432533542474158503146563850454e4e52335652534a453432565033455a4d5338414e303656533957314b335358424a54453758435430453147222c22707562223a2238325932365a4843523952393943383048505243395a58595745345a5858334732514b59354145325445574e37583533425a3947227d
\\x20dbdbb18b31de01b1a0da3de90bf7bcb28b824943b5c9c9e648d7b711488bcc217bc4defd2a1d298af29a16ec0e26224300205d115beb8827758556163e69d4	\\x8a05ace775104efb9f160297b7255569eb8232e8c4adabfaf702fe3185f5e233	\\xe1999e3a3653e8d8aa955e573a4c78c242662fcb9dc815e669daacefb082e955	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x40bc237e2cc27094b1008db0c4ffbee389fef47015e7e2a9c2d3b953f4a35fd3	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2257365057454541484a4d46323652464e4551575959335857343845373132545844423554583442475353475948384d5639455345324d47564a3957475a42575845523658323943353039353543434643354553303934324353374e463339343948353733523347222c22707562223a2238325932365a4843523952393943383048505243395a58595745345a5858334732514b59354145325445574e37583533425a3947227d
\\x20dbdbb18b31de01b1a0da3de90bf7bcb28b824943b5c9c9e648d7b711488bcc217bc4defd2a1d298af29a16ec0e26224300205d115beb8827758556163e69d4	\\x8a05ace775104efb9f160297b7255569eb8232e8c4adabfaf702fe3185f5e233	\\xeffdc50eadd102fef8b9489aedaaa390996a195dccfca3a3ad280fd458bd063e	http://localhost:8081/	3	20000000	0	2000000	0	4000000	0	1000000	\\x40bc237e2cc27094b1008db0c4ffbee389fef47015e7e2a9c2d3b953f4a35fd3	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a223742305a30524a583438534838585143424546473934564241354d5a385241374244355438424b4d32574e48475a38444634334b344a42384a46374536345848393035564e3851354853564a58524a43365937415a32543350394739345146364a4650564a3138222c22707562223a2238325932365a4843523952393943383048505243395a58595745345a5858334732514b59354145325445574e37583533425a3947227d
\.


--
-- Data for Name: merchant_orders; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_orders (order_id, merchant_pub, contract_terms, "timestamp") FROM stdin;
2020.017-00J71MM824W6J	\\x8a05ace775104efb9f160297b7255569eb8232e8c4adabfaf702fe3185f5e233	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2268747470733a2f2f6578616d706c652e636f6d2f222c22726566756e645f646561646c696e65223a7b22745f6d73223a313537393239373537333030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313537393239373537333030307d2c226f726465725f6964223a22323032302e3031372d30304a37314d4d38323457364a222c2274696d657374616d70223a7b22745f6d73223a313537393239363637333030307d2c227061795f646561646c696e65223a7b22745f6d73223a313537393338333037333030307d2c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a223035344e3559564d4b4a4b57584d30304248535644593944374a57483954504a485233483734565a4133414633534d3546455030227d5d2c2261756469746f7273223a5b5d2c22685f77697265223a2246475a375a5651574a534e4456504533535a313050474b44435738385930455258524d4b434856585a5a4d484b4732364232313550475252393459575331413556394b33545644485157374348504e483637594a4a525954344b505445465a4e485a58584e4852222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a22483832545353564e3231374651375250304142564539414e44374e5234435138524a50545159515130425a333331464e57385347227d	1579296673000000
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
1	\\xe0af806db5be077d5c618ac55a728d14d3bf44033dffe468b898d023610f3814e9dc55b8839ca5cfa76c5d7bb508da101bfb3e4725f01b5862ef10966f063377	\\xeffdc50eadd102fef8b9489aedaaa390996a195dccfca3a3ad280fd458bd063e	\\x42ad39faa4fa47b6577ffef77fdc21b1f6bdca36fecf9235095e035f2d4addccdcf742f71848603f323430a9ca8256ef68b8c2759c523c31781f0cdd0767d70d	4	80000000	0
\.


--
-- Data for Name: refresh_revealed_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins (rc, newcoin_index, link_sig, denom_pub_hash, coin_ev, h_coin_ev, ev_sig) FROM stdin;
\\xe0af806db5be077d5c618ac55a728d14d3bf44033dffe468b898d023610f3814e9dc55b8839ca5cfa76c5d7bb508da101bfb3e4725f01b5862ef10966f063377	0	\\x18aebe631418e885fee0bebaa34bdb25db8c3c99bb3fc15989fd72c4f7022eca89e16637bffd718985b3103f44050b4539b935e974899c12513c0ab81e725c00	\\x9504c7abe66b7b6570c4857d4ba7f889c9c15e91a557beff66f5dfd4f61a85930b7e569af2cb318aaadce1bcaa201e7a14ace12e93cf80658b6faa51faf2e634	\\x2fb40f0735c78337254bdc7d34b18d975524eb05e14236fe3a36bfaafa7fdeb5e7d59d6ec88e459f228beb0f79d6d45427f1f8832bb9dd047a0b8cf1dfabc2d43622bd6676c6f5f0d789acdb71702493f4afb5466856a8cdb0053a1be358319eac9a9587d26b1c5fcc016ca230082dd6fc314f469c3f0de4669eab4079159f86	\\x9e366b085fd11229454c4bfc14f08d58c6a525b853ce8d61380e7a82087278801e5b6e19a5eb7c54d05e57639ee38999edbdac9f8dbf02edfd530fc517cc84dc	\\x1ddb087173bb9850c1c12bc3cf844c2f0ad1209c8ed35be683e5eb7241a67b698f99c0e50786afac3bf26e47f41c3aa39d139146f830276dda2a5ccc3852694dcb32d38b35954d3cb0ec4d8c917370bfddcbc267bb27c2e6cd88c3330d8f1967f9d0f6360fb7f47f59e9c91e629787cabee25fb6d8d690f4c9a17c7b7c3409a7
\\xe0af806db5be077d5c618ac55a728d14d3bf44033dffe468b898d023610f3814e9dc55b8839ca5cfa76c5d7bb508da101bfb3e4725f01b5862ef10966f063377	1	\\xcb85432ac029ec4ddf7a86e64018c76c63b387b331e3b6d577df6a6005f656fc4b3e42823eb66d32db7914bf1e6c49de427ad482402bb0ed11efb2981fb0910d	\\x61dbab5fd91563cb90b4bae46f0d6469c06db821dd0299a3b443231bf4ec16e151843f3a78d27a71aa94fa6ade1b97e3d717e6d0585f6e41570c87880ba0a309	\\xaf0a3faa7a813ef178e8c1198c2b4b8cadfcb296c7a43c7b9b54bd44ad345e87ce53ddb9368a0daf475547d48181ac1b4847d58b8881e1c741e292dac6fea9c257952993bd88a0c3b75dffaffb9540df3aa39bb65dc91571e60d675817f84223ec5493202a88a28cee2a88e73d8a2ea093ab1106b9528bcb4e7f178eaa44a008	\\x5b7b9725781ab15d7f933f99f27a901fb2d736a849a634ce4715e3e8e54e82d69f90b5d64dd24fa6895f23755bc009d8606706a982343fc4a8a5200733fc2431	\\x6d5168716431800e08c59f11098b06628c31e28614c32dfe691fa1dd97a1cdfafe5855082746a14dc10b6ebd275c814ccbed2a0b9795a52bfc1945db9ca0af08334e4d02ec126f708018017bdde175811d76a809effc4422ca7c6129ad9b3eb9afd8ffecef6c37c734a551fae7f0fa1385befd5ee404b332e4b70c9c281994c3
\\xe0af806db5be077d5c618ac55a728d14d3bf44033dffe468b898d023610f3814e9dc55b8839ca5cfa76c5d7bb508da101bfb3e4725f01b5862ef10966f063377	2	\\x51d6538179e4769bb81734b5c7d0b00663100b832634cfeab3e5dadbd9ac2fb5423a63b861ab4a706a5042742079b09104a804285dcfec54e10daadfdd9b6502	\\x61dbab5fd91563cb90b4bae46f0d6469c06db821dd0299a3b443231bf4ec16e151843f3a78d27a71aa94fa6ade1b97e3d717e6d0585f6e41570c87880ba0a309	\\xbf2a697682afebc69425ded9da61fe2d0576afcb440dbdea3e75329d77ddf4a52c084b1f3103b86486b54a1e98f3c33f3d9bde09e5c390b0288f3e50b6de789ff9c204bc80f4f995df75777177cb6241d01f46b2db690a491923ef776a8c324a9da53ead5f8cd0f5a7d39900a2421d6898ee5f993236765cf04433e22c5b1fdb	\\x137a00f651a267ac24797270abd0acfc0bbdbc20623b4e1c6abe4093f3e54aa82bb43e061f5e14a5986bdcb8dc4c4dd94c263d4e180e20607809af3dabee5fc7	\\x8842efad6871b22a589bd9a8d56d8443f0fd9a6d687b744a217d5acf9c87f643b84accbb62cbebd17947181a171386ae30ee362c4e12eae5bf164f0039c9039f433fa39660c1438e4ece8b337b592c7afa9fd65a059afa1f758c3d5e5751f242fa1d57036dd59efc2e351ae994629d60878d5020fb824aa65004a442b96f707a
\\xe0af806db5be077d5c618ac55a728d14d3bf44033dffe468b898d023610f3814e9dc55b8839ca5cfa76c5d7bb508da101bfb3e4725f01b5862ef10966f063377	3	\\x503cb5115af913263ba539ab07e1e4e6e18f32140ac05152c6a3b027604d95eec26bde36b57a9b1033913ba67616f738dd3c82573838da05174de0a866cc6600	\\x61dbab5fd91563cb90b4bae46f0d6469c06db821dd0299a3b443231bf4ec16e151843f3a78d27a71aa94fa6ade1b97e3d717e6d0585f6e41570c87880ba0a309	\\xcdb41f8f31e1f6f686d26014b85e88b1d885422dcab48e72e0377a282ecc0bd855d78351f29aa6a882c4adcf8e4222b207a2b9f5e6884ba738766f048a21237332a3a1be3e33364aa2b98ae68f33a852b523fc6f7d9e35cab12d29333338d3213a5391079316e8a2974de9979fd4588a918aff7de475866cdcd281f3e7636ae7	\\xc8e90da131d83625883d572c12a11d83666196b7975a899f6bea8a94233fa8c1ebe2f628e1655c37d9720ec1c13378656f73056f72f3b24e531ad296157a4523	\\x4a79d72427858c37b83e3adb4ca0ee5383993991e294d52112c9c6340b2fb58e7b383d22b43802475166bb6a600da987832136aa12b60575617a752facbc81742cfa27c88bc70a0ae051f2dfe4780855c2cde961472e060425eeb418fdde25ce2fcbcdfeb2a411c2e95a6144acaaec90e4cd7881b408814b44b05e1a6a753148
\\xe0af806db5be077d5c618ac55a728d14d3bf44033dffe468b898d023610f3814e9dc55b8839ca5cfa76c5d7bb508da101bfb3e4725f01b5862ef10966f063377	4	\\x7260d6461ab5fa2e961f73b9a77a86b3006bee2ed67cbf5bbb45e4e8799482bdcc9f6de1a8c38a1dc5f5ff8c1715380e5e75a3703b5601f0b967ad2c95489007	\\x61dbab5fd91563cb90b4bae46f0d6469c06db821dd0299a3b443231bf4ec16e151843f3a78d27a71aa94fa6ade1b97e3d717e6d0585f6e41570c87880ba0a309	\\x71cdc75dbc24348b32f84219e48441cff02c6e6d390d86e0995a4441e8cae97a23de6264fc8605cf80811394e7ab86e39341a614527ab2f0a898f14d1f6c34ece0ae4ba213bc838850d07899a8a367bbaefdbf54661214e91620224edfba8c34bc55982bf0d49d3d30fa8ba3075b07819cad25e1b064e8b339abbd6917fe508d	\\x31f92916bbac48ba3993d44fc6314127c0b93dd478e05f8270d9033cef2cb2743a37da66d1f53055dc67b728a985816f8d787a45815c42483c5279716af919ff	\\x4825e4c35f8256404e92e4c76d58227d0f1184d579f107e6554dbbbaabd81545aaf4ff5600b0d419ef7cb8aba7dfef8138cd9bbf6537be896a14715d1a27251595f3e93aa17464e182ab5f44af39279b37ddcc1ad61371a149bd741c1e820dbaf17a4b6ebfa13cf3f72152f5756552f89836091a1453b23ba7ceff8dd6e499ea
\\xe0af806db5be077d5c618ac55a728d14d3bf44033dffe468b898d023610f3814e9dc55b8839ca5cfa76c5d7bb508da101bfb3e4725f01b5862ef10966f063377	5	\\xc1ece9ad06e1bcf530875230117cc887e5d57711135ee9f4621257393263673a61151cec1dc8c1daced475a5cee18dba935f172ee33424201b05ce4c0690c608	\\x61dbab5fd91563cb90b4bae46f0d6469c06db821dd0299a3b443231bf4ec16e151843f3a78d27a71aa94fa6ade1b97e3d717e6d0585f6e41570c87880ba0a309	\\x8fe7fec504ddf4bdf1abfee410ce25f9a6094ce9dfb27374353f0fcd1f59786f474bd1bc80f7a751dff3d578e5c147b1664f00029155f53a870461da6b7c40c6d1deb5997315feb6c040e32a82339a9476390a94308016b812f6fb1f85fa999252b8fc9b73c86b1b7d9226929693070e38a727fc859a5c4b5f9c56f21874c059	\\x4bd119978ebb9aade6c18b9a8e4a60b9de04bb9a1fb046d5ed1a68ce4ad2042cd76543536ea6488866bb417add9ad8b0f549afea0a30f6cbfa5b627e73ca2a84	\\x9a21ba07a2cb719d10e53ea9c5789015d8839889796a650ab6792c881c76f04ffc0259c7fc446fd2c327f78431983eca7315a994422a555b5a789747f5b06a868721513bf12a8b6e164856db2f00405a360fff7f7cadf587fbab5b9bfb55eef15392ade8401521d52cbfce73c98eba61d3e9c848185d54eeec5e4e22da4376f7
\\xe0af806db5be077d5c618ac55a728d14d3bf44033dffe468b898d023610f3814e9dc55b8839ca5cfa76c5d7bb508da101bfb3e4725f01b5862ef10966f063377	6	\\xf9d385d5568621a6f3178102db02276f3fdcca208118af96a19bf524c804732f270b02ac7ea908f02e5be4ca3758016f6bb6811fcb0cb4f60b7eae19aa70aa0a	\\x61dbab5fd91563cb90b4bae46f0d6469c06db821dd0299a3b443231bf4ec16e151843f3a78d27a71aa94fa6ade1b97e3d717e6d0585f6e41570c87880ba0a309	\\x0a2f564d71e1e3b03b3c76d0c6b9ce777de8f008af7aaf1dec5eed1da827a0ab519dfbf90fa8d75ef1faee8db8f478c0f88da0d7eda96a36efbaca9fc3a06783ec549e7d6e02ac9e1ff6958dd2da394b9c3d80fc1b7d3fed2b62c89c879066e71c279c85bbd0a931dfe670a71e727d53560d481239563b3338d5e5990a8f6b6a	\\x133d7777ef7d14d43869e8b5499046c7d826cd66076a7aa3b39b2304a8d3a680896ee4fc4c329eef6641e4b3a70bb7ae629c34a7b5c0405908630670660469a4	\\x627caaba968aefe3bcdeabf85a2ecae3d03156a91be80199f4c8fdbd30de0c9a339c4ba642cbb71715def02e75af6b0725ed5f76ce7955a59317ef8cebe2109a76b1ad36229ec91ef6d9a3ec17597e0af224fb4510542818faa16ce86ffe479b0f91de7a19e9ced89884ed9f2cb24f0e8224487a5dee8952381d7ca5109029bd
\\xe0af806db5be077d5c618ac55a728d14d3bf44033dffe468b898d023610f3814e9dc55b8839ca5cfa76c5d7bb508da101bfb3e4725f01b5862ef10966f063377	7	\\x6e0e4a5f7ebe8f888ebad92713b076626030d2994c243c73a8e0b6d4edccf81d032943885be98fe43564188d6e433c957328022bbc3494c46ae5eab171a59408	\\x7fe3c0af8df8fbeaf384ca6529a71515f9f457c71a0f718fd2f762032bfe122c958c31e4eabc9b6014ff1cb129616932cf7fb29ac8e960b2a948086d9bd726f2	\\x1a14d76f9492faa382d6e88630f2f72e933d2efbf79e0aafd528fc773c36a32ddc67eb309affb14915f8a03a88fc3c14ec9f8a7c5d4c0afbaa749bdd8ad88a5a7cd5c05e61e8d6d6faa7d7bc1a90b1d425a70b24d3ff55134f8977a67824cc531dcc2a4fd886b19c8d6062c94aab893bea89e5b44ac2e3292efee00ba144986b	\\x6eb823bbe6586998eb17c13e794ed620d5fb13b8350974c27b09bbdd2b36c94ca3d2cebb5a41108e9f0c996da366d88edc57ffc8d3049348f89d68a454523a76	\\x850cd06cd761b32e4b102e4f019dfbe81b7b7dfb43d7cc4f7302cc0d581751ea07ade5b002cfc4a545fd3634db5906232470f1e08c58f2205f1e9a67436172e581c9db19c23cd8e7f8f9e4e8a5a2dc1d0d60d84b37eca1976ca4b3cf58f8d7c3d8a11ce47da895d4d56b680c06e20f26ffef4430b45ac31eb74129fef95b5e4a
\\xe0af806db5be077d5c618ac55a728d14d3bf44033dffe468b898d023610f3814e9dc55b8839ca5cfa76c5d7bb508da101bfb3e4725f01b5862ef10966f063377	8	\\x941a91186a7a716ae762c8dcd3e6a38df806d53a7d7692f0158bbf08e6028beacfbbd4775d8c21cd41b603b2d083682134ac4ab549067c738f2e43961139380e	\\x7fe3c0af8df8fbeaf384ca6529a71515f9f457c71a0f718fd2f762032bfe122c958c31e4eabc9b6014ff1cb129616932cf7fb29ac8e960b2a948086d9bd726f2	\\xbf508f27b16b960a1b299863d6f3f149cd08bb6a4d0cafa369f397a52af0db61355ec2e3d5211db2e1e5fe6ebecf0872c7bb1813ed857c49c096956973f0adaac0ab3e31ba250f0b8793c2d0bbb08333a3c3950429ebf9c3753b3f5f0e3620da4f98f735d4f77f46795f075b433be44669d057eb071df1c58c3ec02b5e0e1cfd	\\xc819457d4f234ef6587d41bfefcf132c146ef6f7a5f39e4f98de7a78b6453507f2cb2fddda0359f9408665250d844420ec05b68c9eb5a115a1562c94d0768373	\\x9155b87db4d58ef1bb725b1e0ec1d1063ab20fd3c6de9bc309a6e0dafbe3ec2ac03b723851e70b7bf3e0e1235a00faec44edb1bb9b2c5606c5e6d8a54c542ce102e46182177c65204ba479b7543bc9866bfa59fa23cdcac250a3426bd2407e2042b8a83daac6499083c671dd195f8a55f1a70b111f460a1ad22e4e8db22c1b69
\\xe0af806db5be077d5c618ac55a728d14d3bf44033dffe468b898d023610f3814e9dc55b8839ca5cfa76c5d7bb508da101bfb3e4725f01b5862ef10966f063377	9	\\x4ea935d69a9601aceef0859e93314cccf2a70a220803a9e323925f0bcfbc495cc982689e9956580e0a1fda16241669f66296aca773e063a31d6f4b5755898800	\\x7fe3c0af8df8fbeaf384ca6529a71515f9f457c71a0f718fd2f762032bfe122c958c31e4eabc9b6014ff1cb129616932cf7fb29ac8e960b2a948086d9bd726f2	\\x6f905587ae5f5a6d92f69b4956b2b6afe7906600acc7bf2490c7ea7ddc8d09977083b2fd601f652a5ef5dcf66d8bd9cd01e20ec91a83dbbcce05ee9dc34b0264dedbe8ba681722de2e25b7f678fdeb657b56a8fe78beb42f5154e35ca25f9d28cac96794a3b50fec78c6f5ba742f3f40203d5d589fc42728215a25563f4f9c33	\\x84d441fa250be6bbd5ed694f47947351359bd8e3ba40e1d4a40149eac748a3edf1594c2856b7919feb255ead40267861cd21ca6a66c03f5801f219afe3a1be43	\\x3e36921a4f0a39b798b1704347bc321aba38c4ed9cde815ef8fd277cc23c34cd939dc54b950097a045933fe68910cde1ff1619d992fe4f873f0efc48201f66791c942331b930b2ee560658424299217c63fdcc9e70afbf4281795eae801669932e8b42535bac3c40aca45cf2cbebebe8be225163451b55fce7f069e1ff184430
\\xe0af806db5be077d5c618ac55a728d14d3bf44033dffe468b898d023610f3814e9dc55b8839ca5cfa76c5d7bb508da101bfb3e4725f01b5862ef10966f063377	10	\\x146b49d332ec7faffe73f437e16fce9a21d368e2ca16435f724eb228553bd094664cf0032900e2f62eeddec8360666faff733edf3ca6187d9bc2f0f7780bfc0f	\\x7fe3c0af8df8fbeaf384ca6529a71515f9f457c71a0f718fd2f762032bfe122c958c31e4eabc9b6014ff1cb129616932cf7fb29ac8e960b2a948086d9bd726f2	\\x671885e918114b0ce04cbbe75147a14e278c36283ad115f1b6f431ee33e76f9959ef03f79ad1e043d16e2fc54841fef5aba2e3e3e029530806def51b14fb1af3dd07ceeaeff7426e7582a18bf915664b1e2357f08430286baf491482d2025742dfa72727e8d385d318f9534290a8de2baaa0c4a41d4a60b8f25d5b3084ac6b19	\\x978620d99ac6cccd4d676b44c6ff9967fee619d3545f60573e7bafb8f53487bd46b2fcfd6ca6756224e148d42293837e535c6a96431a66630000da910a218a0e	\\x3ed9a39f8367bafc67dac95b53fbda3e2f396aa2e59510f27c7bad7470f651e3c50e9372011a4f2079f5d9edaec2c7b4f3cf06d51b5c40847179371ff7beaee51b6964f5439d78b47966bf5b3f0cb7178cc3294cdc1b7fb2a916b87e9f16e824cab3220d211410674bf8589d42c024997bd6ca0002bb3bd6fcdb1ec72ce7c1ec
\.


--
-- Data for Name: refresh_transfer_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys (rc, transfer_pub, transfer_privs) FROM stdin;
\\xe0af806db5be077d5c618ac55a728d14d3bf44033dffe468b898d023610f3814e9dc55b8839ca5cfa76c5d7bb508da101bfb3e4725f01b5862ef10966f063377	\\xfee31e9b509db65b13f66d241324c0e18ea5bbe514de02b05f1580105274d352	\\x78444e57fff22013dbcdf44c3437afa7167b63c285b260f6d8077c39b6de63a7128a7da4aa0961d00bbc52c55d969248bfa58a06c7bf706289416ad099406ac3
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
\\x120d8d0b618452680bcb782f7c2e8d675330886543baed5046e41e5dd10ff7b0	payto://x-taler-bank/localhost/testuser-IeDFoN9k	0	1000000	1581715872000000	1800048673000000
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
1	\\x120d8d0b618452680bcb782f7c2e8d675330886543baed5046e41e5dd10ff7b0	2	10	0	payto://x-taler-bank/localhost/testuser-IeDFoN9k	account-1	1579296672000000
\.


--
-- Data for Name: reserves_out; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out (reserve_out_serial_id, h_blind_ev, denom_pub_hash, denom_sig, reserve_pub, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\x834d47d0042027b630b92f92a4927ec003c8c699fa77d409c15358478e3ab0cdb73ccd30888252ef71011af693b18d8cda5455cd3c9af908b5f1d8672aac6841	\\x41bed9d057044697957d04dabe53d8877569b9ee9eb1c13634e3a2742ee601c4ef00530b6acd182764bbe3d36742807ebc6e753f8f97801bcecfd29b39ed6a2e	\\xa6a2cf241a8c2ff8b0551f60813b4f49189a7ee5a8cec567f4cac5ba111344d55a15dc83dbfa5ea8b20695c455b54f18387908b1d8587c907d93672cf49e8f0a084798fc9dc80574427ac9b32bd6d4d64d85ae4c0ba61cbdc5aaadf570d6e6393cd3542e026aa456c4a3848eb3c081849a43f10283cbcf122781103b4fc5fa0a	\\x120d8d0b618452680bcb782f7c2e8d675330886543baed5046e41e5dd10ff7b0	\\xbc828bc5391e407bed41677cc77e3ad102e84fa7c0c9bfb3771df1928ba99999980c7fc31ebd719d1a4ecb4223d1005ac0e8a5ac818b07f8591b8ccb4b5b3801	1579296673000000	8	5000000
2	\\x34084872761b7646ab9323c79c8be0655e0cd2ab3684d08f43e61c1a2d2bd586de42c1722c51b0c47c0dd6ef4394eb1d8993345c3b61c489e5451e077f240f23	\\x61dbab5fd91563cb90b4bae46f0d6469c06db821dd0299a3b443231bf4ec16e151843f3a78d27a71aa94fa6ade1b97e3d717e6d0585f6e41570c87880ba0a309	\\x34ede2a65d37d75d3e14f44a132cf63fdc5d65edf9cdb4714cf40d3be16bac3d25543e435722a3d4f380a92d8192345620d1d6c9e39479a9e27e3be3ed3192b095315e972d3a9c1c8f526443def8a18567323740a1e04d74be1cb9cc956a9110c005bdeb0b36375ef2d758d53637065b3b1c7920f925c94709cacd9b6ffa552c	\\x120d8d0b618452680bcb782f7c2e8d675330886543baed5046e41e5dd10ff7b0	\\x73c95be9babab677624cc4b458a55052f9be1aa6ef8ab3afe31e10adaf3f8285277a3535991b920f973923847f31948c98a2be4147eec8c09cf9eecb18dd270e	1579296673000000	0	11000000
3	\\xaef9db32d1dc1214bb1a694b622c4f1a6b21b1c45f59aee7be8d9b58343130102e0afe8ce4cbf5cd4663457c2ada074df840de483458060b01c8b438ca5ece0d	\\xafa9f3933a23cac6f44afda432f5aee089f18b073a99e3c56815e71032328024aafcee9dd9e268bbe5bf7871df5bc94c0626f632d6e484dca1ca7f02543f1bc9	\\x4b35efa9261aca251a2366d32643cb889d3dc125d0794bfdf9a8dc58c556fd5c1eafcf725810470f5e5e63f1435a64efb53a025d42d8619b17cfaf4af7e8d741538136d58c17c1439b67e9567b3241a6805b391e245b34e942a177cbd4dad40bca1591aacfaa4963129a56fb3c91a7fd937cd09e0b778dec28d9cb8aeef71290	\\x120d8d0b618452680bcb782f7c2e8d675330886543baed5046e41e5dd10ff7b0	\\x8e61663188412b72afb9a9896ccdb8260c02800d033eaecb1654ed91f338deb87323b26e125f1c6a2eb477c85cbba3bcc8a3c0ff6727ad58cf061d22e2a57e03	1579296673000000	1	2000000
4	\\x19524ef6f5becd902a09f19e710cf9a343f31d32af749441ed6dc4925101d5d3a0b4cb8e6d3ab146d505e3919a694a43e340d4daa23323b10f80deab019fc7a3	\\x61dbab5fd91563cb90b4bae46f0d6469c06db821dd0299a3b443231bf4ec16e151843f3a78d27a71aa94fa6ade1b97e3d717e6d0585f6e41570c87880ba0a309	\\x6bf3aae25f0bca9f4e699808f9d8b500335ac4c5e386c598d1bb2ae823559861278800e7e6cd72ba73a7cdf43656ebef25afa367214534288e9eb2ee5d05bb5b22115809466831cfe68c98f0ee6c80cbfbb3c99d89f46a927a5e6389351fd9edc9dc658a7170e5147b726ac12d636e955b4a8207be813831dcd8a91bdf0ba0d8	\\x120d8d0b618452680bcb782f7c2e8d675330886543baed5046e41e5dd10ff7b0	\\x9dc01b69142a8ded852246ea6e2f3939aa14fede47a9d72ff9273c3125f4a1ab2a630f9968695e2f70127695a62d3b3ae1765bf65c9132fe1059da4130802a06	1579296673000000	0	11000000
5	\\xc09194efcd7eacd2dfa19d084573ca03391e245bf8e4faa49ecdbe35391aa41bf5ec89b355ca1c2c3342964a34324dbe0ed7ba505cc5f4f902aa570a40fe3484	\\x61dbab5fd91563cb90b4bae46f0d6469c06db821dd0299a3b443231bf4ec16e151843f3a78d27a71aa94fa6ade1b97e3d717e6d0585f6e41570c87880ba0a309	\\x38192b1fb5b134e11ed2aa80f566a40c3f839502fe5068eeaaa757b739324a02a63c1f8103e148cf6fb4fffbcd9d53354c069811746d43997dd3e0f1647fc93360f34b14ca32bf25fa86d28b1f751f43e01105476c731330f36c5acb93e2abce22a843fca9d5b017e9a85b1b1e3d761d92e506f964cbc4d6862e94c9ee7643e6	\\x120d8d0b618452680bcb782f7c2e8d675330886543baed5046e41e5dd10ff7b0	\\x3af9f09bac39cfdd026463b1f5d95095ce090219bd37047fd39ac81be455f1b84917fb1033dde7ef2c2863e07e0901ad7cd48c2004c73a7eb9933c29492cef0f	1579296673000000	0	11000000
6	\\x875ddf817274a357ec40a65341612fcfc8484b74769339c406cf66f4c011bbee8710b83a99e7457126394e298eb82ca99a3fa4ab363b1810428823d3c63ec3d7	\\x61dbab5fd91563cb90b4bae46f0d6469c06db821dd0299a3b443231bf4ec16e151843f3a78d27a71aa94fa6ade1b97e3d717e6d0585f6e41570c87880ba0a309	\\x5c631265dfee5dc6b7944250e15e5699ed64d0f6c9f82ac426927f794df823731fe3f6114ec1bfa94707257aeccc09483c47c4a6e7b0aa35250ca32d7d7ba83d20b1d653a1fd31f3491ce651f03c7367d2c40eff81026d568eac72509b8a6732cc1f411d750bb7829a646293d5c154798b500dfd82ae595266f4948156b00686	\\x120d8d0b618452680bcb782f7c2e8d675330886543baed5046e41e5dd10ff7b0	\\xa1fa08c1dcf554fbc05093cdedda8723523fafdeb02c556952581a5d1324a014dbb783fcd79ab92d1496293db06a67cf46fa98af69faea0abf5ee42d072a5509	1579296673000000	0	11000000
7	\\x6083caad73fdf1e73f879bc95f717456abb10a8379f022c9b2c3dfde588a42e0dfc16589546ca5ccdc86901daaed6a13ab067f8db239b968da3ead905498b230	\\x61dbab5fd91563cb90b4bae46f0d6469c06db821dd0299a3b443231bf4ec16e151843f3a78d27a71aa94fa6ade1b97e3d717e6d0585f6e41570c87880ba0a309	\\x6ea7e23fe0aaa3ca820ff22b1031616fb4a98649dedeb8c337d38ec4dc3e1d43942af1782c42c4709fece55afb22966ad23413716f84b984f4ac49cdd35f97b717773bec8b24d114aec6d3934dc9835da262b2439727af98324c034441780e765f827b9c0a9a867fee996e0651d114ee93d53118d31c23de307bd64e17f35c54	\\x120d8d0b618452680bcb782f7c2e8d675330886543baed5046e41e5dd10ff7b0	\\x14ea8ea7bca6ef6e072b7af0ac738d541e6dbb711eb34e6c66d437f1840860351f31b86ef7c84801542146cc1a69ecb703b3045aedcc2a9959bed3721544ce0f	1579296673000000	0	11000000
8	\\x03b666f78d88cf0fe510f4aea639ce9d123c9b695e59102a34b8403ddd1c68f37a12ff7f35cc53c681f6ffa7205ca7e86a4a2edc1fda697d4d2584bbaa01424c	\\x7fe3c0af8df8fbeaf384ca6529a71515f9f457c71a0f718fd2f762032bfe122c958c31e4eabc9b6014ff1cb129616932cf7fb29ac8e960b2a948086d9bd726f2	\\x62a82b2ded461a45fd7acf8e3ab2141e41539c8a8c8bbff8cfa0fb62e9074e9cf40951edb036ab63a7a3e0dee2658e311ee397f421f8c1921c57c94a160dae2caa8d8366d208c713063541d610de02f8aaf08410f9722a3705951b8e87c6c76e36cd2aad2457437264db29840f988c8c2ebb6357f2dbb0779e1213a6f5e81179	\\x120d8d0b618452680bcb782f7c2e8d675330886543baed5046e41e5dd10ff7b0	\\x797d5559dc4e318726b4189441dd1f3c48722d60cd0d8756bf1574d8c236d8085e11b3213c2d40b2e4d9b27581aae2280687aaa0d8a7c08ebb73fff174199009	1579296673000000	0	2000000
9	\\x92770341c296459a6c0ee6a08ef2ae1a113c65470e59153dcc39edaae4d33d071970baf8075ce14ea46d309558d6e41967703b247315ad9e3fb9be0daa1810aa	\\x61dbab5fd91563cb90b4bae46f0d6469c06db821dd0299a3b443231bf4ec16e151843f3a78d27a71aa94fa6ade1b97e3d717e6d0585f6e41570c87880ba0a309	\\xc88f1d27e36cbda8dd8c9321530a8a3b38c762da01112211a8686b7105ddc2ca30433bc43866a05040465125eb7ee5b9f504bd5796aa7d31ba31ee67ac7510ec66baaea024eca8e943f29ad96fe6702d666348ea0128b76ed05222914dc68198860d0b77372a8cc6263a105d84f01c20e02aad71fa1a7cedb2e3a4f6529a8f17	\\x120d8d0b618452680bcb782f7c2e8d675330886543baed5046e41e5dd10ff7b0	\\x864e8dd14d633687d25d0309024b106ef9d37ec3fab57a7c11a05fff22f8c958b350e9cecda1a22e97c28588a6097a06c97880fd617e55e54d736b43c5ad4e0d	1579296673000000	0	11000000
10	\\x24fdcedb717af0da13b33e634692de26b8afa1f550d2f093dadf0dacfac436270970c870362dfb4af5ec73f38a1373348534ea529652b47831b5ad1e4686246c	\\x61dbab5fd91563cb90b4bae46f0d6469c06db821dd0299a3b443231bf4ec16e151843f3a78d27a71aa94fa6ade1b97e3d717e6d0585f6e41570c87880ba0a309	\\xd7e8905672ea961a2848136288be67ac2883a7ab28ac1383b1b47cc627f8ab39143600991e8a3bfa62bfc1c32915d3ac8a2d54f67112a49c982b11e22a30bff1be2fd8e2ea5da6a1b84d63706e44a56021407b11b8e7dc5838abe2acac33b7625b1b9f224154064ad26aa3448ee106f653da84274867e191db55eb47d5ac4f19	\\x120d8d0b618452680bcb782f7c2e8d675330886543baed5046e41e5dd10ff7b0	\\x875a1222039c6e7dccbc9986c1d55f83ba7ec7d61bdffe205ee31fd1228eab9b21c080eae617cbdb47b7edf3809ade92b5e9b54c707814bc9057013ebae85202	1579296673000000	0	11000000
11	\\x4979b29c5f2c3914d8d3c32469a2c4185e8f42c548f72d7422ab5cee5d26ae2bc985f78b5e9c2be46eb0f2ff75427833aff2d8109c4cea59fb2a54069ee72d43	\\x61dbab5fd91563cb90b4bae46f0d6469c06db821dd0299a3b443231bf4ec16e151843f3a78d27a71aa94fa6ade1b97e3d717e6d0585f6e41570c87880ba0a309	\\x98b87c866f4074049b4ba25e6937d21446a8176df2037d08b98291893d1195df138bf34aef227495686769d4b2dcd3989642add27a15c26714da2b63a37a2ff1295365774be1855937983c6366f8070f6be74c58b8f3fc8f4681aecce6a1768a744350dcd536b65312188f5010ba22c6798574c3996e9458309bbe6ce4be1332	\\x120d8d0b618452680bcb782f7c2e8d675330886543baed5046e41e5dd10ff7b0	\\x1c392413913de0fb929c018189c22410dcc654519f24731debbd7fd3f2b3bcfc9beab73dc52a38a26dbd5fdeed74c71a5c73c825f68fe4230b3d0d07da0f4b08	1579296673000000	0	11000000
12	\\xe8a4aaae02fc8276d2d5a78fa518567d6912cb3044542e501f0899c72a84971e500e1de5d96a6d289bd0b4e0ec9ce22f6e73b760bac4606f2ff9dcacbe83c27f	\\x7fe3c0af8df8fbeaf384ca6529a71515f9f457c71a0f718fd2f762032bfe122c958c31e4eabc9b6014ff1cb129616932cf7fb29ac8e960b2a948086d9bd726f2	\\x10de665e0c59c4c2ceaadf481b0ffb1b31a312db3be559cbc7bafe4fa6834304a6e40bfbefca997e3120990416c922207ea33a745e2d3040dca9c539bb88dc0f3d28423d76d7b2158b3291aa578fe4602eb5a11a50c2b928d05b6efcac764dd198be7f1ea209b796ec8c3f75006c75f0349bdba9e3fc12232133634e51b51aff	\\x120d8d0b618452680bcb782f7c2e8d675330886543baed5046e41e5dd10ff7b0	\\x8bf8081d6b955c191461f531231ca8e4e25bfe795ef8c81df605bdb39fd16b1f328c64c25f508f51ccea800e2bb33529c533e7a7c8c336a0bf925545a3f97c06	1579296673000000	0	2000000
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

