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
auditor-0001	2019-12-31 00:00:16.581575+01	grothoff	{}	{}
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
1	TESTKUDOS:100	Joining bonus	2019-12-31 00:00:23.603308+01	f	11	1
2	TESTKUDOS:10	RKR1MZ124V3H2G6Y34J2SVNS1WP0ASMNGZGRHT2BGFW06FXN63GG	2019-12-31 00:00:23.693592+01	f	2	11
3	TESTKUDOS:100	Joining bonus	2019-12-31 00:00:26.745058+01	f	12	1
4	TESTKUDOS:18	18K3P61ZBTD98YER714V2MDJJG9CTXSKZMFEHTV5HZ3YYSY21ECG	2019-12-31 00:00:26.827177+01	f	2	12
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
\\x7c18bf9b242fd7fce4ad8674f33d3aa506090231cb9afe6e775c7b587620943eb170eb90203b4d2c7c9ed6035cd0ca26b36242fcee0656a3c89934c89ef3f89f	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1577746809000000	1578351609000000	1640818809000000	1672354809000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x89745af1ade3ff0e838ae861026494e0c3602939910291e83478dca98d3ebee045c19d5a2941d918622baebb4a178010496642d104729924fb9dc7f8a523a276	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1578351309000000	1578956109000000	1641423309000000	1672959309000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3cc1ca4edd597084a610efe6a1e9bf74581cba53c5f7055c8ceed9fc78a7f7d2856629a6b0b7f4898d13ab4a1e060d38451a7d3cd720ac59ac58f13ef2dafc1c	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1578955809000000	1579560609000000	1642027809000000	1673563809000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xfcfaad44e668fe2f787800f640d8f1e63cf9d3adbbe2c96b7fb9020e0f267361804013988da8deac6eca7636ca4c8e9b885c97e8304864b053c80ed833f94860	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1579560309000000	1580165109000000	1642632309000000	1674168309000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe8b887628469cd9ccfb3cee5a50367d98021cdca6348655b5c584e5532c21148a5908a99b98d36d9d4b3298f8eab78c9faf054d2877fc3043953c2bd410a2c42	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1580164809000000	1580769609000000	1643236809000000	1674772809000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x95cb4db5895a6234df2c1e3d5828c5eff689d380b1d183ecaa5278a0871e1971a0c8f89011ae9bd311b5241f542579627265acd85e4865d09999852d940592ae	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1580769309000000	1581374109000000	1643841309000000	1675377309000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x42fc110f59b5c5786f4bc252a40a2a501fb2b54ca994cb372361af43cd2e232c8d897e04e719a0d9b89f57add09a9d6e40669fd7b2ed386586cecff2e80ed76f	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1581373809000000	1581978609000000	1644445809000000	1675981809000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6d347a0daa8a4ee4d3e51146db9117c963d444d4786878ef1b6f33ec2ffd9bb0ab0d599fa656ebacc068a6806d0aa56e2a286daf787ed9b49d7736f722ebac17	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1581978309000000	1582583109000000	1645050309000000	1676586309000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x20842665b962983c96836a931293e7261cdb0eb8eca0f781e9d19dbb2f392a2bfea75f0977663b72e067151f8b5a1751f455e33c0d14423709ec8c351d083b4d	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1582582809000000	1583187609000000	1645654809000000	1677190809000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xda788613019d0583f0f95b37f9b4a86c280645f1124d7d80062e9f665abf550dbf8bad0dcaa441aff0e27021bfbd14056a79149b42415b71c6481365260a76f2	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1583187309000000	1583792109000000	1646259309000000	1677795309000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc53a027fc883ab5e76231292c27d79782f8a8b19dd117013c9a9ff13314f00d6c4fb723a72afd463f7ad17d29b340ff7e16f50b717085002410297c7c1aae441	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1583791809000000	1584396609000000	1646863809000000	1678399809000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0624b32fd354457caa03bf18ba7be10d86809fabeb0dc29de2da8de0089a911693b19f8e25be612ede53767d078d324a477e3bb92aeacab139f3ab852868e160	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1584396309000000	1585001109000000	1647468309000000	1679004309000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x596268125f59888442e1a3c0ac19d00db89f0a20d97676d77bafa57c7d807b326995471175839f0ba84505fdb8b165fd9b35ea7bf77dae3e92d83e24095e72ee	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1585000809000000	1585605609000000	1648072809000000	1679608809000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0388f96259cf3b1335b9b33567ecd8c8d9dbfb33088620103a36f47c2c19a8382e13272b011d700deee9cb4111d4c7c1c30cbd27a8c3c87ab5b6428f20aa552f	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1585605309000000	1586210109000000	1648677309000000	1680213309000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x616614a80f169432991ecdcd9773e8790b85a21ecc1d51947a87bbaff24123c3589208ec9ffcf6cd988a0991f310119aeb29adf2b16d9862e3ae703e84583423	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1586209809000000	1586814609000000	1649281809000000	1680817809000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x152657de2c5ba4c0f777aacf68927be24bf9c7a0adc38861d39e9320812068ce3f1dfada13d73bc41ae4f4550ee5225cfe89a8f667624f5fa98c07e06486a379	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1586814309000000	1587419109000000	1649886309000000	1681422309000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa805c3164bacf7abf4afb27c9d5a0ebf48e1949832f096865a162cb7fdc06a4bae7b704f9a6a0c26706cac30d175da62c0aa29e8dad23edf6b81eb231488bbee	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1587418809000000	1588023609000000	1650490809000000	1682026809000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb7d3412466d1d56418501b080f624214676cea8dc933d2c21a9b3c28def175e5baebe654bea2e96154cac139e97b0f118b5168137f62c3a1d9973f0d62a54d0d	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1588023309000000	1588628109000000	1651095309000000	1682631309000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf6f81471b316fd7696938a907a6e95b3ebe00decd55a473bc4af98d28d65e7fbc6011a41f52a4ad781fd5dcbd38b1a6b449777323abf2c4e2e89860f530d485a	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1588627809000000	1589232609000000	1651699809000000	1683235809000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa93ce42fed45cd2c920cfd6da6c16912866b52e1f93a76fd21f6b0b35fb25e84857733bb181ef1a8f547b0d5ac30f26323d3cbb110cc0b861721ca7bdea5c7b1	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1589232309000000	1589837109000000	1652304309000000	1683840309000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb121a4a09dcce419ff080ae35de47db7d336c61846b0062e1b22512d8f9b83e2b76fb0b7732d47a946b3114ac090e18683a8e118109fb9982c1649cdceca31ae	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1589836809000000	1590441609000000	1652908809000000	1684444809000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8d3d86e255218b235457160b9d158e7168009deba08fa16f4b433c704912ac2cb5720088648f169773d1ac6dbe80983427aa7661fd10815502494bb6d0526d87	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1590441309000000	1591046109000000	1653513309000000	1685049309000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x93f16ed37729e6af00dc61fd2163f69efee7dd0169a46e2a8b0c8228f8dda888e080ca38389f51345a7fccce147067ab13ac41177d26c787006aecd1c210e74a	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1591045809000000	1591650609000000	1654117809000000	1685653809000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe83f0e01f660a75de2593f6220163432ed6cc57cec037b4cafbdea4b020008ba851b0d4f954eb04510dd4cc7c1cb402e00c397e75366ac0366be00f686e51ed5	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1591650309000000	1592255109000000	1654722309000000	1686258309000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5ea5b1429e591e21745214b32d0aa2d64c237db8633d9a70d6407cd3201d75f5af71adf73c6a817f29b7958b4daddc135555298a7d6cc5b7ce0d029e744f3436	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1592254809000000	1592859609000000	1655326809000000	1686862809000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2aac9e88df2b77497a6323ebbc98ecb67e5a9cd92109b733cec41b26325bfaeb19d6ab3965a6b6782aa7ab21b532890a21059cd2e61a14f6956b2131bc5bbc82	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1592859309000000	1593464109000000	1655931309000000	1687467309000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa4dbb947a9efa488f478d6302c5c261f41b57ed9f32cd357d136a4d4a5a5e254a03c8d81e2b7fe97656f7959bcf81cefcf56032bfc981d6c0e1fa7a5ccbb21cf	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1593463809000000	1594068609000000	1656535809000000	1688071809000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9cb4b8e0a7975d7aa2a6ae797bfa79f4237315f10e44eddbd6d3f1481388f896b6e240f564becf92aadb4327959966e72170fd73f8a00e07912135980519f25f	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1594068309000000	1594673109000000	1657140309000000	1688676309000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x027e2e70a3bcc7c79ae563f4358124b0838165c6c3aaa99653dc6d70403b2d2fb1aeb72bcf7bdc3a1f97523720e2e7cf94f399a4de260fb3c97eb8c2637c96be	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1594672809000000	1595277609000000	1657744809000000	1689280809000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xacdaf61da18ba15ba39fd5fd148a40333dd6ea63a7d6e0e396021b8f09a5aed67793a78ceef694fa9a1e3408d58c30174634cebaadc03a2f43c6594cc618e610	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1595277309000000	1595882109000000	1658349309000000	1689885309000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5e8017e81303b18dd3a09320eb3276faa67a3f715e6731b3fea791ce259f93f2d46f120fe10275304417b38bf99649f87dc19789ade8fa7ea45a408d2d530fa5	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1595881809000000	1596486609000000	1658953809000000	1690489809000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7915d457913797cc888daf2e683b50396ef231b797193b70fe0c09396a5eede7239dfcb4ecc7de62dd49d19082fa43bbaabbf70f2bc10addaa89f992d3d104a9	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1596486309000000	1597091109000000	1659558309000000	1691094309000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2acaf6f2ae4599c651fed1891286770553cd9cb20284f210e7f4347b5d7e58227e6bb26d2d29ca6a40bf9f0c6450c03de20389f28eb7f0a297b64d96b48daac0	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1597090809000000	1597695609000000	1660162809000000	1691698809000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6159cfc0e5a49ef2cdfdf6116f4fda2a8fafe91ccbb292a5c4e816fdc273a6aecf517155709d17d4e0e95d1c9ce413bb752bc192b9dd014f13e352f98d964d87	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1577746809000000	1578351609000000	1640818809000000	1672354809000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x730c5f2a98843facfe6cf9165cb687879ef19c3ee138d0135914da1ce8008009a950cbabe46ad3798c5cb897ce121d7b215dd05c7440747bedd2e813a533f33d	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1578351309000000	1578956109000000	1641423309000000	1672959309000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xf0880be1a3e2eb4b7d2ccd861be6bdc28d665773cfacc84f707209cc0b66bb774f29ffec2af61c1131b4c87ad7cb2c3f28649eed0b057de3c76c98b7a6d8bb40	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1578955809000000	1579560609000000	1642027809000000	1673563809000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x6c7d94e4e3706176aa38213b0e61403bb5be64155b34a3536feea15f6c1231342b54d1315a06096e25a0a9884909e8ec840e0fa532669faf6c5e4d053af271fd	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1579560309000000	1580165109000000	1642632309000000	1674168309000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x95c4c74cea107a33b7ddaf4d3aeea9330f6376a769b39f574ef6ee75344f062f3a5ce1ebc00f79066d9844b87bbd39ce684af63e7ebda7168c8b415a3b42b3a3	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1580164809000000	1580769609000000	1643236809000000	1674772809000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x184d4598dcc488d03fe4946cf706225157ff668e9a14aa6df1cf20f838ab710c23ee83185996e9923fcb54c380d218c09286ad168e65d8a868f3aef9a18986f4	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1580769309000000	1581374109000000	1643841309000000	1675377309000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x24dc3346101ffc107aa3addb1028e19bb23e1413c7c2ef601591cec6ca5ad4a4c450a8f3510a1fd0f06d1a98f5f9749b6c3024c9a75033897eb6fe03a2d6d079	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1581373809000000	1581978609000000	1644445809000000	1675981809000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x6c43a355ad53636becaab131dc4b88eb404869cadd5785afd2b6696d605e0ccc1caad7df07804b8b161e1d34402844f6bcdc4a0e11cf8af7186a282639277ea4	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1581978309000000	1582583109000000	1645050309000000	1676586309000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x2d423233dcb8271819e0eb1ad21d28e2f767b2f26594de3eb6c85ec82810352d08043590eec8315ec82fb9d4c50e9850f5547e20ae26920ebc87d4d98bab0692	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1582582809000000	1583187609000000	1645654809000000	1677190809000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xa7b93821801ab4bcf74ef1baefb945f56205c8f514a898c743ab430b3acbb635bb21ce0b7747ac6cee209993ee3f5dea7fd3e1afe62fc01b1e23ea4f058f7bef	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1583187309000000	1583792109000000	1646259309000000	1677795309000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xec7cf78366f7705f75d9af8d4b66dc09e93e0092ba44edc1d06d4a0df831b7e952537ca155e7f61d05701e2daacd15ea459cdd080f0f716ec33712f8a68d75ae	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1583791809000000	1584396609000000	1646863809000000	1678399809000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xe9ba01d0be606a75f7087b47541b533b2ab15c8527b4171c1f9b07c3d098127347bc22201e545d63b5e75a5dfa15b96900afd7af6a1a927447cd0a7969135069	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1584396309000000	1585001109000000	1647468309000000	1679004309000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x446bad08d799990765131cad8f31d0a69232132ab922c19b1fe9f6b4c4574e2d32e88e95d274910b20091b033a8ee60817b1326969092cf2a84f530bba205af0	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1585000809000000	1585605609000000	1648072809000000	1679608809000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xd7d82e9bdb411d830172854d78d5a65f28c893b8e6e3cfaa50bbdd649397afabf86bdc0effb625b7511812b16460738486b18df859aa16e5146b4a6004189c41	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1585605309000000	1586210109000000	1648677309000000	1680213309000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x8f798130a00de249235306a2bc35ffda819f661abc41f691e55a81520cec439e3b78d2ea6fc5e2d04c0dd4b72479302623a44a9cea11ddf421bb3de5244dc51b	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1586209809000000	1586814609000000	1649281809000000	1680817809000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x2a4161dce24a625806b667e22f622ee8f2fca9bb61ef158d7bc15197cf0d10000e8d76d5eb06ad934215f2872a3968a5f51fcab8fe8767389cbea089c310f814	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1586814309000000	1587419109000000	1649886309000000	1681422309000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x52e36ed587c1ec78c42acb14e3dda90c8c760b4205dc3bf6e58bb07d2f87d24a323f57e2c5335d84dbaead7a282df2045693050b287791412129af766da420d8	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1587418809000000	1588023609000000	1650490809000000	1682026809000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xb31f37c08f9a0be9046e39a080af198dc14d8030d29ac1e546540df286cbf7764c41d9744a46d5e0d88db875f8f46dce7978167b4c6b3e2503247a8301fd3448	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1588023309000000	1588628109000000	1651095309000000	1682631309000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x5bcf0a13b09b944700e32b00b015b64cb6674953b0ff5bc1c62675b4b989daf76116728e1a5a1cd32d398296f55d6b82dbb05e9b7c753eb53fac1c4a76f5b465	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1588627809000000	1589232609000000	1651699809000000	1683235809000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xc9f49e3dc7d1f52a408670443a685623f7dc512c335b54218d6bca7d91f437286dd10ef6a002c5448843b629a0d32bb9de6e48d2e9f09531ed2074699fac85bc	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1589232309000000	1589837109000000	1652304309000000	1683840309000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xc7d50af348984905792d6a769ac01453391cf9a91f8e73526d87554f8040b9d9daf77d86391fcee2c7d426163da35b6c7bf8be2e3b09fc7e45631618ed455d63	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1589836809000000	1590441609000000	1652908809000000	1684444809000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xdd30d988d3dd7f9a4f3f84c25c6a74b00f2af6cafc521978a8dce0b5644a7845216d27e018a6b11fdedb1d15625cbe2c11b1d48aab9bc1e424641edc9a28b37b	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1590441309000000	1591046109000000	1653513309000000	1685049309000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x03cfc39b729c277e499208963e006bd39d750a1a618dd6dee7dfcffa66e33d18d2c252e0579ad9437c515fdfcd245d9a2bc189a8786bcc70d2c572800edc5ae6	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1591045809000000	1591650609000000	1654117809000000	1685653809000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x2684ebefc30df7a70ab2e7b30a47717aa5b3b59ab88a8800c07150876eda8b003afaf2370db5dcdb9a90807a6bb85f68cc13dcf9ab51a6ad5ee3e7dd34098a9b	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1591650309000000	1592255109000000	1654722309000000	1686258309000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xb594238b1a0346ff3174fb44f6f96400809c6fcef6a60327ff7f1f9726a9f636151140593f8e10ab2fe80f8f67771f6ad2844c6118067e7fe83cdf988c9dfdbb	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1592254809000000	1592859609000000	1655326809000000	1686862809000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xbb98c5230cff8d1466f1f06805303c249277760b7dde5e63850af775ed56a8bd3e80c8b02af3357c2f822d93b294951442190c7cdd38cfbb984b413a64d1a123	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1592859309000000	1593464109000000	1655931309000000	1687467309000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xfae7662037883d9a4400f824ae34c2eb46780aa547efcee75490454f59c9c2215512b4cd9db7507dda6a0fb06b60af2dbc7f823961d05578dc19c63522d0c3c4	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1593463809000000	1594068609000000	1656535809000000	1688071809000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xbc5438a9e63c4953994851cd90422efe732030691c0c373d9363f7d75a258c2f5a97a3f1d4209650d49becbd3bf3269c16bfaf942c818790373d5fbdf55954d2	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1594068309000000	1594673109000000	1657140309000000	1688676309000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xc1007bf856c62380f8f4696cb2d4058c01498b3b5362d6cbd6519d7f9a773c02ceb5514fd8db46aaaa89c1c04ee23247d02a49d14a26cb2a6b34283e52d1adb4	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1594672809000000	1595277609000000	1657744809000000	1689280809000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x1baa176e60e2ca065b3e1118fb30d4b90ba4fdd155088c944a8a85e4ae46a746a4b7ffd0e4a8b6d1a514b0e6bc5c5d9d97d8256122fe47fdbb2eca7389532e32	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1595277309000000	1595882109000000	1658349309000000	1689885309000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x11286c78cee90ffec65420be6d0a18eeb24239294310588b1d9c16dd9af6721343f348e23cdf0d6279e9a2f41af375b195d439bf07c83ee0f24e7f9ae3b92255	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1595881809000000	1596486609000000	1658953809000000	1690489809000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xd36d05c667e6ed0e46abc6be10c4ed6ae72549c22a9695c606f16400f45d4de83be9a10a89f61fd4370357099c21c32e145736c15a252de58cceda93f360d4e5	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1596486309000000	1597091109000000	1659558309000000	1691094309000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x5002c326417fcbf6c05a5daa2ed3b5332258c23aaa3ec30bbd48324000176af4468ca11c009baeabb33a175022eed7aa98184a4b0683a8185e9b6da2730871c0	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1597090809000000	1597695609000000	1660162809000000	1691698809000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xd8d7b08143f2844fca7a7c745a5c43a91945f2f42166ac2eada3e89009dcc661c80942d0d9bf8b0f0b560feb511612c8e4dd3060e9ad9aa6d513ac1f1bd56f84	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1577746809000000	1578351609000000	1640818809000000	1672354809000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x144dbc55a3e8691747bf9daa35f838a66a374f446dda1b6fca49529fb92cf6dc8e1281750f73f6ea27db554045b2617e7a5c596c908859c9ada1ab73563b17ca	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1578351309000000	1578956109000000	1641423309000000	1672959309000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x69abe164f1998addf57649a27abb6b38fa3cf99c9e852cb47ad6245e16269e5391b3662230376f424e1cd17ea3e48808f72462be98f0f9a545bc9b2b2328e684	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1578955809000000	1579560609000000	1642027809000000	1673563809000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x783b74d204519ff198aaae4754504d9f498066c64acb95f3c5ad07df673f9fa43a3034647247a011f90e4c1feaff0580f02994c5126f73ed60607c6afaef0ac5	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1579560309000000	1580165109000000	1642632309000000	1674168309000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9b3b3688c0f015f46699dfdb07b54890745a7226e8d33247476afd16c4d3f49944169a6ff4d8b1a2923aac867e0e11972c825725fce7ca00264a7bbbe5a8d918	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1580164809000000	1580769609000000	1643236809000000	1674772809000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x95abfef3a4ba91ba61a8a300e063bb1d15c4a9cb82501fbe4727aa6af5129c80f550dc7a96b0fff0a5c232fd9ac34847c882f5005a95b24b97752df89da2e3d2	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1580769309000000	1581374109000000	1643841309000000	1675377309000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc1468536b1d65cacde8935010175402d3f644f4bfa98d88ae8ffdb0e043d9ead076b9d043e998415dbc84110fb5db7391656a7148cb7ddcd2407832bef02eafe	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1581373809000000	1581978609000000	1644445809000000	1675981809000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb35ee3d7da477db632d7fdd4e2ff56fa94586a5c5526485f8de550b3e36a0ffdcdb5efc8cbbe42d3171cab03161250b00d68d03aab6633110da626e70564f452	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1581978309000000	1582583109000000	1645050309000000	1676586309000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb2dc3c2c998b481b736c59ac49c0e188586cb6c755cc7de0aa36c391d6f0e757aa52e86391ca1aadecabe93cabaac524f57571d3721170e005ca09897126ab5e	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1582582809000000	1583187609000000	1645654809000000	1677190809000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa0dc5e8e860f2d4f932ccf47c4e3ada74792b15a72d2316d673ccc515b6ba612cc748fc1a00cd0075634fcca1df9d85d2f2edbc1f2aefc6a9fd7af264c2384ae	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1583187309000000	1583792109000000	1646259309000000	1677795309000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x72e7ea8230d1c0b475be8876147a4e52d324a655730e3c6a9ec76db0e0a2c7ca7813929a2e740c85fb63796c139379815eabaa652e916cb28d6963a63a994d57	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1583791809000000	1584396609000000	1646863809000000	1678399809000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xad4f866f6d981d73674231ee4bb142f67fa183d9ef8c14813f361ca55ded9d07eaa130f2d36714d9b0660bed506031268d6e9fee09f94c57c1dd29716279a3b6	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1584396309000000	1585001109000000	1647468309000000	1679004309000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x73a7185d163b1e86feb204fc76920248b322212bcb04996576a61d9bee8bdb9a8e38c6c9dd9254203c32ac04996a67c48677baaf9efa1bd0ce27db2c7a4814f4	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1585000809000000	1585605609000000	1648072809000000	1679608809000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5ca03df975c3a084630f1e4b9546279408517d3aaa176c4c397fd7fe5aa9f899091ea0bf639a8ba78da463d47c77f0394204929fca60b3c30366e591a32239f5	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1585605309000000	1586210109000000	1648677309000000	1680213309000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf927366b92bfff5076c96170e9ab60834d950f8dcbf1ed2620a0e3e13e4c696a8e81775e3e82a4784adf66bdbcf5c21ae0084dd3e8f7c108931b00ccccd54f8b	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1586209809000000	1586814609000000	1649281809000000	1680817809000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xdfd52f27ad84bfba3f2984042354d97ba00a81a308f51a1d857264411a4a833275a39f174294e3a11107bde9e2ef3020ab1ae0d454927162497a4afb665106af	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1586814309000000	1587419109000000	1649886309000000	1681422309000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb0f6c484d74ffc50a88de1428e9eb4e4df22d9ddde45255277fd0a3dc94d19b503621972c395e2eb556041ef9ebfeff9afcf3849d1d102216c7b1a20927b9bc0	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1587418809000000	1588023609000000	1650490809000000	1682026809000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x23fcc7cb81640ba70070e33730a82bb4d8e2d6a3f3c1925be5a4fc64eadc860784ab51bd579e01611efc74332383269917dc944c060025526a2942c3190778a4	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1588023309000000	1588628109000000	1651095309000000	1682631309000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xfd2f3938e2d29e14bf82ab48c202bde730984990fc129d431fed835e0f3b61ec20b15d9b674cf73513cd5654faafa22c61a7fab58b5763ae8fff9ed804b80672	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1588627809000000	1589232609000000	1651699809000000	1683235809000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa7236edf50d1aaabb6a17837c54a3e2aa84197911faa1c50e5085999b66fb66ff85d2bee0e5a47af40107e8547cd1752f74fe61105a5d81e75849d9c7a702eea	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1589232309000000	1589837109000000	1652304309000000	1683840309000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x549b8d4444637f1f11ff7e7a3725b6a0d430a8c5f137814b942dbc5c466aba8199bca80e73f91fe87338850a079d79ba53eb596bf7a1ff1ad0e087b281ffd70a	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1589836809000000	1590441609000000	1652908809000000	1684444809000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb756149dc097be13ac3c900e36a2178f67789e66bee4c641a8064bcb0a6314bf378df30cee6f43051d9f6ea3cb6ea2295f934ef84d89efd5a0548c1f513c1475	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1590441309000000	1591046109000000	1653513309000000	1685049309000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x612f723013e33ec2b14fbdf2913ae667859c26e11324b476c3f1de3b5b19467c73ffec0626d54fdc95678e03082353929b4c1dedd470273e6da247b2cf89b473	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1591045809000000	1591650609000000	1654117809000000	1685653809000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8f6a5a45c88783559424335bbf83b1f6d731307e4afdb93b34126d469017f9765c483f0dcd7ac1c8551d9537e0e58d33a4bb007205649da87bb90fd2568bded6	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1591650309000000	1592255109000000	1654722309000000	1686258309000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa8992eb87cf9d2d19003e9a317803fe582bd4863113dae21e2950819119ab7768e978625ac9b55bd98f8255ec3198d69fd90c07058e8d0fc62742c1434134d55	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1592254809000000	1592859609000000	1655326809000000	1686862809000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xbfbf7bba5ac785046ed609f7b5f4bcf75ebbee09b52ca177fab5ba3745d0506d9079f51c4b1c3d95ede71aed2754c5d2aae0cd6f20e496e39300a0db74694f2d	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1592859309000000	1593464109000000	1655931309000000	1687467309000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3527c627a0e24b2e61cbdbb8df6d4d82a52cbbf981df87e290a222a930d258045f2cc81cd908992cf337921c36c923a2095aa2508ec3c78a1f12073c0d6b7016	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1593463809000000	1594068609000000	1656535809000000	1688071809000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xaf6cfe6291f6454f1d741fee2227f0848714c7fa8e31dcaebc3b4cca000f8ae99cee17c0c0cf8a8218cd8ba852df555133483ec8fcde5af7afe8b3787d3f6550	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1594068309000000	1594673109000000	1657140309000000	1688676309000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x33cf1f22153deba2eec9eb5cfd36743a50e29ba5ce28728d29de8b5112856a9920adfbb4bb6d380ae062e076126ff263bac5226953005923120145119d5cb2f0	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1594672809000000	1595277609000000	1657744809000000	1689280809000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd61ba7d8c3cf35882f6df4c9781c4f9077144ed3a48cd311e59d014825dbd5142aecde1a5a0edff2c716edefb7681705f05934a3d7615478d51f0d6a561f4711	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1595277309000000	1595882109000000	1658349309000000	1689885309000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x32f5b0838b90c80309b262e5afd908847e47a06344ac0b3d1e904d524fe36d413603ae77e416926962d1f5db927d16183574babb1d4b135cb110f13155569c42	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1595881809000000	1596486609000000	1658953809000000	1690489809000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe781cf314efa86149d4982069a0e470b329c13a92bf2b7b3cf88a1efd811b3daf17444113ef8b2bf8d0f27e53766c2fca93bde71994d34ef8279c05f7dedef63	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1596486309000000	1597091109000000	1659558309000000	1691094309000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9d156393321aa62b0ad34f4d34d801f422440881863b5e705ef8b69e838fcd1a62e937c718b841363616ede485ef1b111ac18d07c96f144fb9a3e7204ed65937	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1597090809000000	1597695609000000	1660162809000000	1691698809000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc778d97644c119f9ed0d672e416874091a384ba0603c118b2b5c4e9d9e181a67e9fdc99552cb81d3c8b2d5698faa889e4e6c6104147f3f1f9a2eb87dc6ec5dff	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1577746809000000	1578351609000000	1640818809000000	1672354809000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe2f1adb847a198289600ed40ad45496e066e704434f9d8665dbd6b0394b009ed9471190188678435bc920132b5701b476ddd1b9d36012d6cbb39430d61010b0c	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1578351309000000	1578956109000000	1641423309000000	1672959309000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x3ba0f846cb45e61e80d70ab22920a367c3428f0ea50e2312c38e5b9a84ad2399555dcd2776b9958b5dcef2ffcc3961e309cb9234a05f6d34acefa1398d439d77	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1578955809000000	1579560609000000	1642027809000000	1673563809000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9e9f7092d85a8b481adeeb7fab2a10064ac0535eb36a4c8c09796d824c4b1ea299d54597cc380805138dc5a95949ef52f318ac45b3c6baf32b70d4bde405ad36	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1579560309000000	1580165109000000	1642632309000000	1674168309000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6452e8478ca95098ee05ef03648bbaf576689cf22fdd2e14540e9fa6aaf210cb9cfd74444ff58914677e22d77448a42639ee7fe798c9473f3c5a0debffcfaa0b	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1580164809000000	1580769609000000	1643236809000000	1674772809000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xfe601cc16ec8def35ce8c2526e74aa4ca11131e2ffc870367a31593ddd11f3ccf55d9dfd3174ce49e3365f0e37c8d9e4f58dd3ca8f6c35fd16b5a1712be6006c	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1580769309000000	1581374109000000	1643841309000000	1675377309000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9dc47ed7e3a75b3b8c845dd8ec21419ac374a2aa60252a40d61b2c45cc69ab46441bd64f883885ebb4e728df60158081f1c7ae9179e69d1220a67179bfbb2e32	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1581373809000000	1581978609000000	1644445809000000	1675981809000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xfaec00b979388da02eef2900d2e83a051e70ef102f5e0372983b55f3d4853d9a5a943d86833fef2a75274bebff955debded1c0ed337a6a2b647ceeded38169c1	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1581978309000000	1582583109000000	1645050309000000	1676586309000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4e51be9ab9834e77e3534fe6021d04973bcc8210e8ec445633c0c0f197a591546a4e07070f3bc7251d3b0e4aded390b62db485ffc721347fe1a928aaa7d9f87e	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1582582809000000	1583187609000000	1645654809000000	1677190809000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x676596b46a4d3ded0493dc88bede0401ef7d27782b8dd82a1cd03d748dda934474ee57df81b0c366519fe68acda2ad844598f6d7c3ddb6f3af41a7629521a7c8	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1583187309000000	1583792109000000	1646259309000000	1677795309000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x3d3e7c9c43eef6f7c678804b557e45e41415551ff1e52d99aafd4fd414723814ac82e646beea50266cc69c35fe71c271d2a072d4526e25d44e37ba62cf6dd72a	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1583791809000000	1584396609000000	1646863809000000	1678399809000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x560e7625bb704e775aeb0441cbc38996119c226ef46e784149c20afe67d136b090306456d498a7823710b192ef3367b96ed2815daeef3f82e014cdd6c3acf992	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1584396309000000	1585001109000000	1647468309000000	1679004309000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4b18050f22404b5cae27cb8d8eef1c2778b8e83daefe7e7c52d22f659ea8eedbf6dbb0161a26c87e1877755e7b6080699283d2fe75d1a77d629918569b84463d	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1585000809000000	1585605609000000	1648072809000000	1679608809000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2ee81f295a42f875820c654a55c88e3b5f9b235551b0e59762664dca2e622f575b6f152829c1aa4d0c31ad312eea672c9bdc926ab5fa8951cb72478907208f36	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1585605309000000	1586210109000000	1648677309000000	1680213309000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x36c6dc33fe51006ea837d50d817395dd92716323bcf9b12681cea3c437d9117780a2539360af2ab379591a30a383d4f05c661a0433720468d9d8ad7d7c8e20c7	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1586209809000000	1586814609000000	1649281809000000	1680817809000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x847c80a3984512cb4c19b5ffd19af08b082c4547dafc698def3ee3ffad0cd3cd76c1c81a762adbd2d399765081eb39701076f6189060fc1677013a48a9c37426	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1586814309000000	1587419109000000	1649886309000000	1681422309000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8e98cdb94d209824432ce00221cfbe4f4336e6bc5fb8e94c410511a23d20d8360459bb1e1ffeff6a532f154e9c8ef88b8575588ded96ea44e5354e1a7084006e	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1587418809000000	1588023609000000	1650490809000000	1682026809000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x08195d21f32ab169746f899ae512276e2cf16334bcb4b80dabfeefd1e827ed71d3c01c639909609613f39e099039e2d38d17b63fd3b8173ab18b4cdf690b1b92	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1588023309000000	1588628109000000	1651095309000000	1682631309000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd542dae2ac0e9b9ed6069db961a6602a03f44a157e0489f9c9737ca4f07b60e63e169b78249ee6caac2aef5c0695a425d6ea6d23c63e954dc53a25566370fa75	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1588627809000000	1589232609000000	1651699809000000	1683235809000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x00ade391a5ca667185ce34d95ab47812921128a42337f2551dcbf640d1af86d3ead3e42f3e8a92c1ba384a56911887986d7e9dba6a668002702b87d80ebc93c3	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1589232309000000	1589837109000000	1652304309000000	1683840309000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7ad446d707ad9fcc197930c4e873dd1d4c1f077d4ae3e982d36970bc443497af826a12a5af4d5625fe7d003dbbcce223eb465ca79f852d40d96fea0b0625423a	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1589836809000000	1590441609000000	1652908809000000	1684444809000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x99441e577dfaa049bd8e2a1c8a8271c0118468cb57afc91eeed8924031c2673570a98101335cccb1d66f6fc913f89142c1ef6e176862b0fc66e833916c13d489	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1590441309000000	1591046109000000	1653513309000000	1685049309000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x430b85763658c9e0dcd1833d6b976c7b1482940e66095dfe5df372aeae82672135d8de4d9d7c1ceec1de94f45b86a8ae95fc69d4db854a88132dd1ce829eb024	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1591045809000000	1591650609000000	1654117809000000	1685653809000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x11878e5e7d8809102f45864a138a7246da66d24c690eec15a2b92cab1907d85bcc22e4955a4b6c21f72028a5c818d7c210b7d0a448e551a15827b4b1ac99034d	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1591650309000000	1592255109000000	1654722309000000	1686258309000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc26bc7a4c618e5f5d245a9149c9f29fb73fe085f09baed0ade702d953bed03b2ad443c7606b58dc6b1500cb68fb67dce0dbc8782aaf14d6f0c1ed6d1f6307b56	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1592254809000000	1592859609000000	1655326809000000	1686862809000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1b7a572fbe1ecee576d0d0da9d5af8fd1c66de7c7dc9cdafbb3fabb562e5b5fb3bee81d383a5f83acc3bbb16aca56f8eb610bc350ba0c01e5f4cd7a7615020f4	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1592859309000000	1593464109000000	1655931309000000	1687467309000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6959172e7ed3c8c277df196cca021ef2d14ba008dd2c862971bb2f1ba6144786ee052ba4630ac12f4338c5a75d9614f0316b35ff9f42d0b55f58ec05312b434a	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1593463809000000	1594068609000000	1656535809000000	1688071809000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6cff30105c1763372cf30b029e860ace9d2e4ef1cefad5c7cd2bca92bced139135ace08acd857ada7ba20cb24deafb01107f6431b459a59c4a5c91c8398312a6	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1594068309000000	1594673109000000	1657140309000000	1688676309000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5637a5a02817ac064363331d37962f91aef635ff3c194a5168129b75b08c2bdd86f2e4d9363cdfdebc7450adba827e958251aec686db9bd9a48b63f8c7af9211	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1594672809000000	1595277609000000	1657744809000000	1689280809000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x07ec91af53bcfbfec9986309f39646765a790b67cb1c7b676bcf359c735d276fa7a6270ec1049e837af750f4cd2a5cba64852d2926bf0816f6b1ef4d16cc2662	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1595277309000000	1595882109000000	1658349309000000	1689885309000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xaf0ee129352369c348f2ad8f1e91b7fbcb225fd40248734c1c76f44a7900b9e2f9eddf02783435d88126739872d11dc2983d27a2b5e85d848656b106727b0eee	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1595881809000000	1596486609000000	1658953809000000	1690489809000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x203d46059aaff14381401b6da9afdfb9cc883520aa9c21484b25749c8c8a52cd0f8afb9bc716f9eb65dc7c4d1b74f8d196b1e8b93363d64b2c7f4a41c7b92089	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1596486309000000	1597091109000000	1659558309000000	1691094309000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1564b7230b23519bfb38b7a1014d83bf37c70b55490cd60a5001d2985162b1598c252738ed7585350c3a3b7c8026513169e8b6c0f6fd1f2d516c3ea60011d78d	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1597090809000000	1597695609000000	1660162809000000	1691698809000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x920e9115b1da0f24d49e2b70b1a0df0a82c19e741fa5fb013a3fd5c7a75577edd0aa800ca4d965b53b772ffb1562a3cf58ee82bfade084163e381ccbcd1d1f23	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1577746809000000	1578351609000000	1640818809000000	1672354809000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x23a4a1072325d874a7695fea34dfcafb75834913961e6156254e85a32a8adbf5b264e26d850e24e569547e76a3a421014f27a006b68aece185c36c5344192534	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1578351309000000	1578956109000000	1641423309000000	1672959309000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x488932ede8da593d716c1df29f698f624e898e6874bf741aed453c412a5277e798d80fede6bb11766439adaee2ef45bae5f18750f9d528bf0a72e058dbec817b	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1578955809000000	1579560609000000	1642027809000000	1673563809000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6d708ca96750e7fe367521ad64371838c61c6df06767fa64284e522a998f87b9cf610a98d3e4677ea8f4254340ecea8c3264eb0c79d6b930d32cfcb6d9767a83	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1579560309000000	1580165109000000	1642632309000000	1674168309000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x689d197715468030f4db4c526ae798952354c5becd8e9e6b99d7ecb468a3764171862e06e2ca265302cd42d412a95a37313cde5e2215409211152b4b87bb5eda	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1580164809000000	1580769609000000	1643236809000000	1674772809000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x81c8b8f3b60a66ce891257c03b589bdcb58371c9d871c28e8f7194e25fd8c4d82e41f7ee8c750eaa0d5008d2c5cb7d8487b77180857b461b3cbabed5bfaae04e	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1580769309000000	1581374109000000	1643841309000000	1675377309000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x047e083a15e4f9071a7d74ec4e40aee05a56c418d04e5809202738fa4889d93553220b14b19ce3fffcc585355f4be5ff883c03de17188af90cee7075dea79cf6	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1581373809000000	1581978609000000	1644445809000000	1675981809000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xcf581f6c5ead08af42a45499cdb834bf099e26783583612a6bf6e6536ce9d3f2fafc9fe34b85d1bbded0044955f38d668479f323fcfa032053ee148491547821	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1581978309000000	1582583109000000	1645050309000000	1676586309000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xaa98e278315fe9c2eab4629fa42cf9ad32089716b04f702e0cb269bb8d38b3ba3893b2ee99b60f2b342a8d282587552feb7a4e0b3f9d2cd86153111eb2199b1d	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1582582809000000	1583187609000000	1645654809000000	1677190809000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8d1a6281fc5f7f8ea27f7c6a35dbf972c606eab125d2bdbfb4c6e1f940bf15ce3834a6e8761b1210644fa51b998708c48289fac1cdb3e172930424b8214cf351	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1583187309000000	1583792109000000	1646259309000000	1677795309000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7817e694b3fd32ab1629982456d80f48acda58bce581c44c1b7484307abbfc8601856e5acf00045fa6103c09d4b51aa9d45255a41ef37a688f52624ad5ee5118	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1583791809000000	1584396609000000	1646863809000000	1678399809000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x3b8563ec030193f4a82264207e9d0cec470e2c26d696c43844e805909d9b7939f24fd24c90440a06c53e30779f63408dd8e5e8f8f2ee28798fe6948aa4b2355d	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1584396309000000	1585001109000000	1647468309000000	1679004309000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x0730ec23561ea56a44ae87d870000129fd58cb2725540002a95da501824eebf873873b8f5416bfa6800e707a0947c53a8104f33370dd580fa970222a05d46758	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1585000809000000	1585605609000000	1648072809000000	1679608809000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8327eb7b3719d33e13f5775d6c7b9b5ee04a00e0907b014781f77af1630ffedf41eac44715d391cd766db2db2492d8f1fce1e4812b9577dea587ca90f53aba1d	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1585605309000000	1586210109000000	1648677309000000	1680213309000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7010c6cf92891d5188843e813200449c3ac5ff9faedeac2dfd34aab148d58e6a30917af8a2b8edd1d8ac53bba8e87d32e2e6dedcb8c53059cb345ade2152bdf8	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1586209809000000	1586814609000000	1649281809000000	1680817809000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x24734fb2ac34a3fb3a87c3fb533069c49c87e636f0ba649059a13cd16068762d4c9df054255be96a9075d794cfb6ef0a36a5dd203006cd7e742292110742a164	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1586814309000000	1587419109000000	1649886309000000	1681422309000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4a96b5ae37c9cb551e6dd78d72c53f1167bd6504eb96c4619f41ec246015887e3ecb74a9e4ea3562d5ab84a79dbcdc975cde2534314109bda4c0dc6a40a6b951	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1587418809000000	1588023609000000	1650490809000000	1682026809000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8ead82ef45c01b099a9b6a1f487d42acdc27bc261e68785d9c1396679bd696a63af5906e6ad05c47f6b7a3177afc2a7c9a7e1108b0a11382e81c7986de3deb72	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1588023309000000	1588628109000000	1651095309000000	1682631309000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xdba9833dc93025f3e94eb5c03c114aaf5a6593b406f1a0c8319c68c103fb14790c22293f0a3248c1291e4d920366087208979b93b2c1574349a95cd470598691	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1588627809000000	1589232609000000	1651699809000000	1683235809000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x68d869e4800d6e14bc78a1e7e8ae1120f3b42fbdce50b5fcd9a8d34dbc3d9ee3d102e34e3122ddc659720e795a5c2e4b6b4f8d6c37a5a3e522199f38abe80bdb	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1589232309000000	1589837109000000	1652304309000000	1683840309000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf0405e50321b2aaba42b006f1e612b67ff64917b872ebe65b3c1f9a7c06bfbfc0b9c5c1c261d937ae921e9ee929b145dbaf1cf7351ad5026df2908c122992b73	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1589836809000000	1590441609000000	1652908809000000	1684444809000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc616c7b3e7bccd1a09068ff92ab9a07cfdb8fd7fddf9499badcc4530af874de92cf14dc655f3a1788aa89528e37f6ac64f33a3d8faff713ed78854000660ad5e	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1590441309000000	1591046109000000	1653513309000000	1685049309000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x16973cbe6b5c44c13d0e970fe42464b197c5afca0d0b421de27f592da194bdc79866f6d3fda4171fd169bd13a242a915c5e15780fe622a1b40b9dcc1ad2eaa78	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1591045809000000	1591650609000000	1654117809000000	1685653809000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xda9812d7efb97c7dc9de0008074e2af5ff0f94d02c7ae378b32dda879b00e20b63aeea6b89fb1e2cfd347d871232f0645c04a392f61955b63e48e97fead8979c	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1591650309000000	1592255109000000	1654722309000000	1686258309000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x142f985db54b3142f60b73dcdf5c952c8a3a8484cbb660f6557e132bc6353dc7538a2e9a5418b1ae79adef8128c992d8ba9181ea3360492ee41e079d73efadfb	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1592254809000000	1592859609000000	1655326809000000	1686862809000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x815b0bce250ce103389bcd603d7d78411ba6825fc74d6e8cfe3741888ae904fb6d32d9ea478d9625c276d97576ef00034211b7d7f862908d4d03ca4e998eba9d	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1592859309000000	1593464109000000	1655931309000000	1687467309000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc0ee8da5cee86be310a9a3ade633f50fb474f0ea9e13b015eb480290ec0c915408b81f77a6daece5c47db1a294fd64175984f673b874f8d9a6ccf595db491ecd	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1593463809000000	1594068609000000	1656535809000000	1688071809000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x47296c134c01fee4baca691f0cd63ee2ee24683b4b03065245f23a346f670cb300dee988c7d367a5b25add63edcd3b37ed70f0c8351ddc843997ce980a9d879a	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1594068309000000	1594673109000000	1657140309000000	1688676309000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x973dc06d10bb4b98de75050bce245e9efce84c7294f054225125d3784b6b9064bf2d4c9ff5434bd7f4c0309e9df9fc722c1dfff8c14aafa3cc437c9ecb27904d	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1594672809000000	1595277609000000	1657744809000000	1689280809000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x395ac6791fd3c26ed90faa78da1cab88f149535c38dd4721da1c6a2b698733d3d6c14c24495d5f0c101d02c0818768e6dd218d35408e006182eae7a41c71b2ea	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1595277309000000	1595882109000000	1658349309000000	1689885309000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x82bf1b1910b95563bfc75fa7c53286adb3ac81c17752bd2c4e458f0a859beb0a4b39c1da03211a0f2ea01b4823bc57155660fc20c40dc17ff84f373757a32f88	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1595881809000000	1596486609000000	1658953809000000	1690489809000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6737e4933f035f775cecab69d869a5417d1b7fb1c894de774b0de269d5c41c2f4cf98a64b7c6ca0ce3946482f4dfa672a53d50f3f685df26b0659a52ce5a0531	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1596486309000000	1597091109000000	1659558309000000	1691094309000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xca22ec15a0a5a09fc70ab9be2ec2b8ae3788624731e1ca50b85a05a067ce504e4db3fa4e00025a1ff70f75bb6e70907fb41ce25ff850f939577ef31d41e86a7c	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1597090809000000	1597695609000000	1660162809000000	1691698809000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1b3e0100937fd48380574273ecb350f8b2f4b945b8944153a7d5be8467a144bc87ce33d2528b7b2b1a129e10b98ac7e48a79db395c9beffad08fa835619daf1f	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1577746809000000	1578351609000000	1640818809000000	1672354809000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x7ae6cb2cf13b418990efbf7ecfeb9574125968c1b3bfc3d1c14d146d6ddeebcd077eb7b74d9ef4099bfda749c00ff17da46b11cd05ed5cab6ad9c3503b698140	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1578351309000000	1578956109000000	1641423309000000	1672959309000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x8c2c304e7f5ac714069cd1d8755ed91c9a4a428bef281116e639318b2b5babdf9559201b54df6108b9cf4984d97f42e41ab921e7b6df737a6a3174f0f12f9e3e	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1578955809000000	1579560609000000	1642027809000000	1673563809000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xa077e222863fe99d94b42691a62fcce09c377f6dfd14f61dcb52253a25bbef1688759b31300015e9da089cb0dcee59ff1c9566a030c9f9547fcdc3a07ed9ceed	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1579560309000000	1580165109000000	1642632309000000	1674168309000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x776b4cd96dfe541165dc6088d4f0cb72249e30a552a18d096ba82a098ee395f7f6701f4be731c734305dc1d159ea852011428269e0cac9372d125d94ee64be9d	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1580164809000000	1580769609000000	1643236809000000	1674772809000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc03ab97e38ed94eab5a8f08311ed83c13c705ed663c8ca5c1191aa87a6d40721f6bdb6743caea385afa1a5780adb0ab663300db95f7773237f247ffe03042d41	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1580769309000000	1581374109000000	1643841309000000	1675377309000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x1d1c8944da0faac89e4f6b7b57eb8a9a6c516e4cac36adde49a072001ed8b1662f67be83a84ebf4f007b0e01c65c9db75ab1f4fe52c64e0f9df3bde739efb64b	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1581373809000000	1581978609000000	1644445809000000	1675981809000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x25ada18299717a0dbcfaf0436673a23cf9cbb9e9fa06f2b0bf1d2c7f35b234a348ee509810c7b9c9095ae4a8186a41cc3a498073ff8053678a2504c08f97c7f7	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1581978309000000	1582583109000000	1645050309000000	1676586309000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xca04cab1fe285b57c05e8cc7fb777252aa53b00d977fea5713e80e4260a70d91b5cab1c5c7236dbb0318762103080deb939f9d1d5c99856cc6c60b59a4bf10ef	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1582582809000000	1583187609000000	1645654809000000	1677190809000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xb27f18957f859be0923e5e3d100ac4b05f66c60dba2e555178fb09028f011eb21251e80e63d6b5fd42b89ea5be8552985b276adffe5c4c89309b78df1be4bbcd	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1583187309000000	1583792109000000	1646259309000000	1677795309000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x6a21dfdfededec34aa7e6182ac67ab06c50c6225706acc96d040f51f0a4a98eb891d1a594dea4671f33b7064207980cad6f07490e0b6e03e744c05233f430627	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1583791809000000	1584396609000000	1646863809000000	1678399809000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xa817d2809cf7ac4b11122d37000c8c9cef5976172fb452e4138456b2ae206b16dc7bc0e12133fb52733e050485c75106723ede4eb1644e921e573ff70fc2b5e8	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1584396309000000	1585001109000000	1647468309000000	1679004309000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x88124ebb8d197597885a76d3702f1c9a7cdd76737502b87b72c80112115d94e1a3f9418e1698f671056d7b3d59ac35895bd6e4ed4785efed48a9355f427642dd	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1585000809000000	1585605609000000	1648072809000000	1679608809000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xad5a222048adb6d31d4b1d217caa1619cda41d9c10f722c928a76a3e83a5403d4a66bebec06880d0ebc87640825a7097fa1009f9c226044553202d1f01ac6525	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1585605309000000	1586210109000000	1648677309000000	1680213309000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x32ba3f91b78447c63ca206713ce2275a11145dd2db68a7557fe87350843319adeeb3f86411d56ff1d3637e67bb6f7f36285f499ff3250b85f5b7309521dcdc51	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1586209809000000	1586814609000000	1649281809000000	1680817809000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xd8566bbf43edf1b0e69eb0b0c203e7f10c87d57038cbd87bafa9da5f95b09dc0126e846bd13ae9e24ee308bd3139acff088c31785e5183b962008cb5b96e10f3	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1586814309000000	1587419109000000	1649886309000000	1681422309000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x4c1128a9ce169b6018c94e0a58c3a0c2ab545d9be4f8b038eb21bbaae5573a910715d3e16f29fccef8dfb7700cf546479a2b80ccf917be18d10a2532340967d7	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1587418809000000	1588023609000000	1650490809000000	1682026809000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xf3dba770aa38e35a2fc7b5a66a828017f5fe165090464bf387f7aaaa795da7fc281e80a721ae27425591af254eac4bfd603095c036b4192daabe4e910255ba79	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1588023309000000	1588628109000000	1651095309000000	1682631309000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xf6af88349db4adf01d2a86f9cc5fd1aa932af0ab293d86f0039528a98038b2301f41a3561a0677eca4b1c1e1383c9008cd11053bd73d944b2123612885933bec	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1588627809000000	1589232609000000	1651699809000000	1683235809000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x8de0e9bcd2e86930b0228bfbc20fa50c53c3f3d7d90570acd7258ff57db1d9ee5c8dbf0fbbd33589635b41c0579da042c46e2149ca1db59f1593516318903deb	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1589232309000000	1589837109000000	1652304309000000	1683840309000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x3b9b4bd6e07dd85dceb2f9cae72ff1fc6107aa183679ed066b12130dfc928daec9e3ca53bae605cb7fe0361f2982e9473e16a887af920650010d1954bfcf4bc4	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1589836809000000	1590441609000000	1652908809000000	1684444809000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x56a5aff42015a3c3fdc8cf182deca8230c0df22de5868374da7d01aeb7ef8715deae431dc01754ec561a53e9176d42cbeb8e633145c166a0258ffab9366c9d31	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1590441309000000	1591046109000000	1653513309000000	1685049309000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x95b0fcf9e5cdcaac552c9e850841681bb56ccf547d75ed165c318d15cb399b2d836633046ec951d53dc800e894f613f090d6b7d9a8f381febc94f3042a49f885	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1591045809000000	1591650609000000	1654117809000000	1685653809000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x004718789f2fa03ec10985315c4b6925a0b011d5aba7cdbd30126a3d77d792e7fe11f4f1f622a998c40053dd4880627ba7b59ac9fa54211cbaa4ad623d49fc6b	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1591650309000000	1592255109000000	1654722309000000	1686258309000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x31497da1bc6500fcd7f261508668c75a72680d5d82886af1dd85de2ea1ef39bf5689322236e636608c5b8ffb85996946e658a550a605b1b0ca13e6d50e39e9a8	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1592254809000000	1592859609000000	1655326809000000	1686862809000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xdb04b07050bcedcc1125c680e82541e3ab92355ba88398bd6a7f1798e32803ac0a47a4c6aafd6e46c7764705de417c3cc10a27d595e867dc4afa2624f2e53f9d	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1592859309000000	1593464109000000	1655931309000000	1687467309000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xd2c7a9a26ff061a9d9fc13c484629cc303ec856cc499c81c7d4438e1d2d960fb0dbb97eb377df4cc6b00ac5a21fb79309fc864391fcf7e5161ccc225a64cef20	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1593463809000000	1594068609000000	1656535809000000	1688071809000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xd0a10c4b43c2d18ff8d9c2866ee9515aefd98eff5e88be4c1c532348b7c2657b085cdfa3dff3511700313381c6d100378d893b5aee7271373a6c052e4505f410	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1594068309000000	1594673109000000	1657140309000000	1688676309000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x73e83fd6c3c7d71ca0b49cd03b8a39443d7d489f0c335eaed3ca307b5430ff733ea9db6820cc4a711e6923c119a6fa8d9064112091f3f224071284687ccf1efd	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1594672809000000	1595277609000000	1657744809000000	1689280809000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x9cc2ee1baea807f4c01c0f81520cdb99556d16b511a0b9ae38299e2d67bc165d974a8ddba35f59ed79b24deb52fbed98adfaf1b03f1747d7aaa70cb72ddd0adb	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1595277309000000	1595882109000000	1658349309000000	1689885309000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x12ab657edea89a17a849862802f6d82895ee2176d636ac008605f485288c7277545f74c9731b9b8b2a76b146a2042fab318f43cb6455905b3a4504b26062d5d5	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1595881809000000	1596486609000000	1658953809000000	1690489809000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x942accbee66056f373f325928396a4ab272b941faff20c5e0e9ea6a8777afc33ceefa617e91a0a3d918c90b1fac5c572f07f12b5446faf90535d9264445a819e	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1596486309000000	1597091109000000	1659558309000000	1691094309000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x3ae5dbc2409c6acdc4d4e08191a02bb18c984a78cc34f3ca8b0cf49af2176dac2d9bc71e03d241fac133bd32f851dd0bb74fea2826587d9213957e60c5a24d0c	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1597090809000000	1597695609000000	1660162809000000	1691698809000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x401eabfce5c5cefe6b489e963f5c81d5b02004f76d5968869cb843acf0571bb0d396eb4914253f4a0c862955d7eff492d19c888376d324898d7795376e21950a	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1577746809000000	1578351609000000	1640818809000000	1672354809000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x0a947840e9a66873f904ce45bd4874407321d8fa8de91c2b5727effdbb718162d62b64243a0b052271a7e8ec0f321391dd5dd30405e45b6b3984026cbf2816e1	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1578351309000000	1578956109000000	1641423309000000	1672959309000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x7e4a95bdaf6fb28596d0cdff276766621635f7a73f2d9aad27a6c6b7f61cb414a3a1b7e3bf9b0b83c463efd4009a8281808ef6593ba455c9d92487ebd2900c71	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1578955809000000	1579560609000000	1642027809000000	1673563809000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xbdb7a0f6cf3f9e30b61648f8829ee780392770c3a032f56b828439341aa23c8623723d3ea65180ec80b4204d5245fcbe0a6c189169cd9d987d221d414eb2cf18	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1579560309000000	1580165109000000	1642632309000000	1674168309000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xa14362e07722207f2542b0af76469072932ae93fbcd6e4d49b3663e124bbc2ed66732cf794156f95c2ffaf679f5f815629da7c82e786d9311865d63494bd0295	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1580164809000000	1580769609000000	1643236809000000	1674772809000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x5d8e038e001590dbed5cd4fdbb6811e61778ec10ee45932565200f01fbfd0ee6a82fffa9ac572326a2abf1c7738e5a175e549d866bfedf1833aa47c4ce986c05	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1580769309000000	1581374109000000	1643841309000000	1675377309000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x0720df09e3d6caab6ef11fe5535be73c9ac0e708b77018d39e6df18553770135b2ebefe4e0c4694f573e0916ec207a772a30153d5cf77a681a8e0ce36f9d5072	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1581373809000000	1581978609000000	1644445809000000	1675981809000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xb228431ac1c631831bf10572b5387bb281862482fef4a5b1c4046cdc3a8f178a7e272313136f636ee4d58ba249ad1f76ab312bcd715eac738bb5225b2a6a21d8	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1581978309000000	1582583109000000	1645050309000000	1676586309000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x7fde343b2e3aa1e4022929384cc1727bf49b5c93570d3ac11bc0501dcc270b467ab06e4cacea13751743d8b49635675c26538e24ce412849a2cbcbc348ba59a8	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1582582809000000	1583187609000000	1645654809000000	1677190809000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xb8555c5b6c414d995e6882ff59e6645b1250db90708a3d5d068f53749e38b605e566f9ffa1d6dede08fb4086e45b5f822b4173cac70f539f42277f3cdbbd341d	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1583187309000000	1583792109000000	1646259309000000	1677795309000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xfa17db511ec603323bee223559475d52135708d1fdeb259029f71a4876fcb159b4bb18144cee6a81769233235cacbf724201e78f22e8cf85fe3c9bf5f7760a42	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1583791809000000	1584396609000000	1646863809000000	1678399809000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xe25679297bc5b764529a8ff37578bf73a4fbd5159ea2c64450ec451404e9c71f56316e49f2cb27aa861a07bf49b6d78b0fb2ff81f01e71a2d73d7229faa4bdf0	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1584396309000000	1585001109000000	1647468309000000	1679004309000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xaf9a15f3c9de9916326df3579f5b1ff88fc625f58c57c6daef398ef6e8587b73996cc2bdeebc3166b876fe949c226c78dd4cdae91e214cd862794da46d736e91	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1585000809000000	1585605609000000	1648072809000000	1679608809000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x8b3033efa7a008f0017fadd09045c7fc333d2df3b283b81450850fc3a9b4696f5b8ab788a4622363c828c156dda85ce7bd9444b6ae8f781139c7383fb277a57c	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1585605309000000	1586210109000000	1648677309000000	1680213309000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xa818200813df5070993c96dbe82ef86c9e54edf76c7b89ee9a70c808f52ec97df9134aad82753e4b5f4f262cbc2437f568357cb8d5635163240611873e07c1fa	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1586209809000000	1586814609000000	1649281809000000	1680817809000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x3f0c392959723d67d4c07503cc05ca794180c5fc4c1148638194daaab406ea4ad90a626977893c50d05a3076da5ae14cc9c14c61d5b76ab55109ab93226b5a92	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1586814309000000	1587419109000000	1649886309000000	1681422309000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xeed0ec7959e9ca3892854d82102072c69861093a7b86f7c3e35bf67b5bb5fd7472744b1c65117f480e589d02e8586091ecfc8a10492d65ab28a6624fbdf8a9b7	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1587418809000000	1588023609000000	1650490809000000	1682026809000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x0804826ed85c6bfc1d67c87e56446dc02d05943de07fecb55e2dd19da5b9ca0ff27567bd1d06eb89f1c2d9da3bbef357c596cb880bf3cbfe9818b3308479fed9	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1588023309000000	1588628109000000	1651095309000000	1682631309000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x7c5647e4f35a009b42029f7d226856b8b911289e7c06a61a42c2335fe55ef24c63dafcc18d4f13a56dbc6a2664b3d7f87b8a1229b53e8c91125e74a028cefb70	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1588627809000000	1589232609000000	1651699809000000	1683235809000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x7575a3bc8beb532035d6cb21d0595c71755b53e824d8b671fa90c7f71921e52ac31012a6e0b0a0e54917a47e65256822d07abae1870414546d7b74f51991c697	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1589232309000000	1589837109000000	1652304309000000	1683840309000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xea0eb0ba013ceda91fd7dc55e1b25485c3ff5e0c2a25b374ec9e639ff3fbdbefbc249e0cc485c1378e4ea052b17df4798673cc94847e043c7b41cdbc15b33eea	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1589836809000000	1590441609000000	1652908809000000	1684444809000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x2aab7dc5715dbe7f97a624f824e1035cf32a21c32a87d9927f155aff032dacc8ad45257464cd78fd393c8bb7ce21ff0cd66728a9e3ef381b0c351117d2b896cf	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1590441309000000	1591046109000000	1653513309000000	1685049309000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x26d8ae71fe00bfeef217f53f54c742d9f186497c4e76660bf2688a9e485897f492704028860de688dded058ba702697f7b71bf2ebc5e9d0af3ae2d9c56bec442	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1591045809000000	1591650609000000	1654117809000000	1685653809000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x6617c53f9bd2570f940e3237ec1f8ea7e8efb24c33068afa3fc200e073d17dc0876e037c3b3a5dc1f8f9b99632a53cdfb103d725bf9b885a5474c878ca903c9e	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1591650309000000	1592255109000000	1654722309000000	1686258309000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x8874be28cddcbabb4c3f782aba7783eddef559426b2d38655e03758793388c035bf4ea894d76b2db9420c4a7f19462737f8f641bda6f29be4af20c5fa7ea748e	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1592254809000000	1592859609000000	1655326809000000	1686862809000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x909bd73dd97760c3644e9949fe4d2ba135f2b8a5367ac1486339d4a135dc8ada81a057f645696b641debebacccb999da6af7dbe552439208512bb574ef6ee660	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1592859309000000	1593464109000000	1655931309000000	1687467309000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x01cb1801ab3818863cb13f434efdfb3f2d5402e1d1e74306c21c6d036a3d5a5d5aede5b3aa68f30438121c81ca93356100636656eb31b1063d5227841adda803	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1593463809000000	1594068609000000	1656535809000000	1688071809000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xe5050a5f4227894ae6b7182ea64ce0d342931621b69ef2f2e02da6e6c0d91c978051e23f24605ecf3423a42ee2abb16c11445788e5eef3b68d8f283316e18d4c	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1594068309000000	1594673109000000	1657140309000000	1688676309000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x107711041ef4c503e34fd06d123b5538e01b3676a3c83e63947a0751468a3ee6a19ba82c8b963268a1ad4ba6b2c3d7b9baa98383c90be55cca05bbb1ddd46ccd	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1594672809000000	1595277609000000	1657744809000000	1689280809000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x0dad4a363fe431ff9c24ae262f4b20af88a718949c1626190e2b03502b3b83f541d60964233d475b0dc8395f760adf3884126fdaae8c3fc6ba563fa6d0d1351e	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1595277309000000	1595882109000000	1658349309000000	1689885309000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x15a3b59a4c80072fb76f603be303376cd1d6c6008bcbf391a00f2ec0f58e55781de534dc02c389b518c1d9cbb953bc8cfa6a52e4c4c58ad5d7aa1f4d233a67b2	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1595881809000000	1596486609000000	1658953809000000	1690489809000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x8e45f4cf73e90150590ba56518c0fb3afbbc1f7355c33fcd14d71a28d197126f8a273a2244f41baa0c9027ccfeebc8da38178718ec695c14d53fa6597ca57032	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1596486309000000	1597091109000000	1659558309000000	1691094309000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xc0e2535abb9564a44e2bb7ec53f1855e4e112af2b111a86b430df99ce73de3668036767b226c3920f1dcb3e8cc5256e1a5549348e7f9543e6e74256034897f6c	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1597090809000000	1597695609000000	1660162809000000	1691698809000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xccedb56d361d4983321788041be2be9b2b9b122faca8fb3550c6018f113572a57dc032c1bf77c484119d750a2a7072c062885cf8403341f91ffe22d8b7f678e5	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1577746809000000	1578351609000000	1640818809000000	1672354809000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xe645dbde738ac1a4dc6219abf7d8b3536a62decd3308567234dab92c133a43988dfe37587a5cca8483d18dd0af0d98d6d06eb97b48ddd1f743c49c884acad39f	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1578351309000000	1578956109000000	1641423309000000	1672959309000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x275372044893862756e76dfaa9867d4b2e51c689c43bde66ac28898e9ff56c8c4cedfcf584cbfb2bdd01511965489d39517ed760c6a3d4c67280299bf6bba0cc	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1578955809000000	1579560609000000	1642027809000000	1673563809000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xc38411740a83c7909b1f3914442cf37f14cb53e314710e45bed5013cf8251cae6204072046110dbb170cde97cba838fadc308efc7b6dcd5350077b78f29f8387	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1579560309000000	1580165109000000	1642632309000000	1674168309000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x12ea169032a67977671cd11ecb4d2ab9f897df08cc39e165e48a70cc50329454e94273fd9df5b672fe8df964304cf520f8c9049557c55c68393f6aa712cfe4e4	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1580164809000000	1580769609000000	1643236809000000	1674772809000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x0d40c8b0075682e475553538cc46c3c995502ad465a3e07ba2d98eaca0a30648dd2ece0672763b6a2a2a9ae7cfa298627d538ec0a0b4bdba55d878786c545ba4	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1580769309000000	1581374109000000	1643841309000000	1675377309000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xad5230fd5239ee5380ed61247dbc104b973de5456f298aa087d6227091c3bc2f8e18e35accce005c739bf169d0646c87fca871dcca760d723061fade7b133e68	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1581373809000000	1581978609000000	1644445809000000	1675981809000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x44e40a93e20e81fbdeb05447435cf2be61aadb2eed12da276e1c77c8829114668e33d69d75f84467406771665efe733c2a1bf58a5d321b009e7b8ac4cdf7b35c	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1581978309000000	1582583109000000	1645050309000000	1676586309000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x73d9171d17263d2df7420acbbad9a4fd715f4b75cd33ad3ef35543b9e86dc3a4cdaf4cc723c043ea52ebec8b037d97ef13b798817eb5fc30d8a79f3e2fef6f9b	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1582582809000000	1583187609000000	1645654809000000	1677190809000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x183ade4c438bb6fa3e0e77aac1ab2d04e1e4cadde3e37360beaa1fa1a9e6c0eac087c624426ed57c9d9991a8f33eaf727369833b000da53a2cb8681749e1597c	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1583187309000000	1583792109000000	1646259309000000	1677795309000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xf4d7eaef8d7ce588270160d269155be59d5fbc18d7a0bb9b2af2c9d1d76c310ec31f465d187d9f6993ef86be16e12dc8618d6197f12ce604cbe4a31f403ae355	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1583791809000000	1584396609000000	1646863809000000	1678399809000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x965caf63dc944260471ff1869375befee5a15b9e66675cb8c3ab6753a17f8f644a15d7d3837f6ff5df7c643649f07d5e684bd3575a6dd4416778ea96244000fe	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1584396309000000	1585001109000000	1647468309000000	1679004309000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xb62a2c8f6c658208840ab62a7113a08c8d03488a37b2d2a0db45c71aca0e6e89dbdd6e592081d6c17bc595298d07f49696bcd48dc9cb01c6b3239becf0a93074	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1585000809000000	1585605609000000	1648072809000000	1679608809000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xcc715698d0d2f0de9f6f00f4d5efb05983ac970c638760eca2f5e7756001cd5ff894203d78629d2a5a372d3dd9a287e41679c60cfabd7f1fa1a46d12c79d35fd	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1585605309000000	1586210109000000	1648677309000000	1680213309000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x4fc239123de642d5daf5a96e098e170e6f135f1246daa8dcb9fc770f4198b70c70a02de91dace686a44ad42104cf58afe5d13fc2c67cb6cd944b547cbd0bd359	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1586209809000000	1586814609000000	1649281809000000	1680817809000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xd4a0ba8f39fd47b0e8c653f4a826aba62be9cd8182824034abf685a8154d79bf7a25affa20dc90cf1b716345d436682d1f191b49b583d6c2dda5e1b058fde81d	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1586814309000000	1587419109000000	1649886309000000	1681422309000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x890bb1f73e1794c1f93acaac0baf226c3dbb2824a0c6d85f3407b034409d5b51c10d0d1be22f75855f8d2559569300a98f6ee0883cb0fa1ecd5e19b0d84920ab	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1587418809000000	1588023609000000	1650490809000000	1682026809000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x204c0fc9c7dee7c4a0451fe09e367d675a32481d93dd0c0c732b34b79d0a676d8978e08511f5791478ef228bb42422dae0bbb266b43e83b4d06091e1a8364dd7	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1588023309000000	1588628109000000	1651095309000000	1682631309000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x79c79843952a9b5d65fac920e0063ffd404e1f887651f5aba234e7f22d49503a4407705d2e92f0245f1845d62ebf6185aa912da9b6bd0f6b4a84613c0824b457	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1588627809000000	1589232609000000	1651699809000000	1683235809000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x214c127147b8452173ed4eb3505476f19d772c15ccb7d29e4d3d41fd0189224b69a919a729f5655e5a149d2fe98b25fd1adfc44b00c03e416b285754558b419b	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1589232309000000	1589837109000000	1652304309000000	1683840309000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x8f1a5db1d507949c6ca5d3fea0c4cc767275d752d046fb07d44896d4c2f1316c4668cb9711e6a16ba864e71431187133e2a2de820e8a34d47d9bdae5d4d7f03e	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1589836809000000	1590441609000000	1652908809000000	1684444809000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x5fdc9dbfa1a4a8ec7f19b7544f8c85dc7546080de2a556e723f55d9e84eee23677341c758be50a909f57825645537e0ebcce4cc1da3ce9e217f96c401603d4fb	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1590441309000000	1591046109000000	1653513309000000	1685049309000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x995139b3b5700af7d7d8c42b0f8aeedeb6f348655e806b1a0e0e61b0f081dd17b4a85d65f757fde17c3ba1f428e608ce100b98f4618120946f05eb884d57a0d9	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1591045809000000	1591650609000000	1654117809000000	1685653809000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x320cda28757d39c4cc7730661b39945e6c07760638ffb821790fe97a2744daac3df0cdda6dbff1a687592d81608cf601947d7f888e66a6072d7caa19a7ff721b	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1591650309000000	1592255109000000	1654722309000000	1686258309000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x7d74ac3a4d575eb040cbe4bbcb82d7e62f3fd2559eedf98225cb34da38d1a7d1618e4353f20d628d0ed2648669e6386fc1384ccc4356b481f3042e1d65671500	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1592254809000000	1592859609000000	1655326809000000	1686862809000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xcd47577eaebd28a766ee252d251b9555cd2be240e8e6ece926a9888c088790c6da42ef3ca0f80ca7f6b109598b17e11a4a555e4cfc99774f1d262fc4e9a7ee05	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1592859309000000	1593464109000000	1655931309000000	1687467309000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x517f743016859096677844bd1457bd97b4b8fef4e35fbccd2ccf9a99475e7265009b893a2a257fa212c5ebea6ba75413881b9b0e4bf8050e17498bd627ccadc7	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1593463809000000	1594068609000000	1656535809000000	1688071809000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x9a97c44283e05dec1bb04bf8aa3e8ffe87d5d6028da290f66562bf32da3e1104174a766528b56d80538fee73660b4c08a591761b40d3f081d434ff191b38a260	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1594068309000000	1594673109000000	1657140309000000	1688676309000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x0bbb3d62aac752a014a81458076aa192415b02d1e3b4ba5f5021d6bb7fec2e1bba9b391aa795eae1df6ada9c59766ae018722dd3a36c57308cb5faab07dc9a83	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1594672809000000	1595277609000000	1657744809000000	1689280809000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x073f7698ac3ffc324572103a34996d2b4864a4954aaf76fb640fc05a40da8435d07e09902f27a90faace33f74ef6508c7816b3e16d6a5005c9c604573f96716d	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1595277309000000	1595882109000000	1658349309000000	1689885309000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xfc7ff50d67516f425464b45f0759ec1151238fc68941975613331817e13e8e425d20e848591f28a80b64bfcec237edb0575891fd3f8dac93a26f7cc7a8427e5d	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1595881809000000	1596486609000000	1658953809000000	1690489809000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xf97cee6ce15351a6b3b3a63ee2aa073900827bac508478b3feec4b8358d615d90062c3b0259cd1965724cfa682420f8bcfb4d9f5457bd35d3355b3bf04679e7f	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1596486309000000	1597091109000000	1659558309000000	1691094309000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x494d815ff7b6eab580ec15bb6b3b959b516ebeeaf9c9b0e85cb34fe3e1f401b476717edb4db0dd799d8adb01665b4c012e2a22617c994ad5dd0142000ca57124	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1597090809000000	1597695609000000	1660162809000000	1691698809000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\.


--
-- Data for Name: auditor_exchange_signkeys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchange_signkeys (master_pub, ep_start, ep_expire, ep_end, exchange_pub, master_sig) FROM stdin;
\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1577746809000000	1580166009000000	1640818809000000	\\x0e19c3e0b1a4f874fcdb0948f273361f6068be0cf8c34a63c049a38c5a05dfc0	\\xe3dbba329f523af764575fc800fcd2d4276e8ec18ee1192bcf7257a3f6bbc52cc1a63cc7c980f3978dbb5a21beafb59ad146eae85cd955df47a00bce4c30bd04
\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1577746809000000	1580166009000000	1640818809000000	\\x0e19c3e0b1a4f874fcdb0948f273361f6068be0cf8c34a63c049a38c5a05dfc0	\\xe3dbba329f523af764575fc800fcd2d4276e8ec18ee1192bcf7257a3f6bbc52cc1a63cc7c980f3978dbb5a21beafb59ad146eae85cd955df47a00bce4c30bd04
\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1577746809000000	1580166009000000	1640818809000000	\\x0e19c3e0b1a4f874fcdb0948f273361f6068be0cf8c34a63c049a38c5a05dfc0	\\xe3dbba329f523af764575fc800fcd2d4276e8ec18ee1192bcf7257a3f6bbc52cc1a63cc7c980f3978dbb5a21beafb59ad146eae85cd955df47a00bce4c30bd04
\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1577746809000000	1580166009000000	1640818809000000	\\x0e19c3e0b1a4f874fcdb0948f273361f6068be0cf8c34a63c049a38c5a05dfc0	\\xe3dbba329f523af764575fc800fcd2d4276e8ec18ee1192bcf7257a3f6bbc52cc1a63cc7c980f3978dbb5a21beafb59ad146eae85cd955df47a00bce4c30bd04
\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1577746809000000	1580166009000000	1640818809000000	\\x0e19c3e0b1a4f874fcdb0948f273361f6068be0cf8c34a63c049a38c5a05dfc0	\\xe3dbba329f523af764575fc800fcd2d4276e8ec18ee1192bcf7257a3f6bbc52cc1a63cc7c980f3978dbb5a21beafb59ad146eae85cd955df47a00bce4c30bd04
\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1577746809000000	1580166009000000	1640818809000000	\\x0e19c3e0b1a4f874fcdb0948f273361f6068be0cf8c34a63c049a38c5a05dfc0	\\xe3dbba329f523af764575fc800fcd2d4276e8ec18ee1192bcf7257a3f6bbc52cc1a63cc7c980f3978dbb5a21beafb59ad146eae85cd955df47a00bce4c30bd04
\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1577746809000000	1580166009000000	1640818809000000	\\x0e19c3e0b1a4f874fcdb0948f273361f6068be0cf8c34a63c049a38c5a05dfc0	\\xe3dbba329f523af764575fc800fcd2d4276e8ec18ee1192bcf7257a3f6bbc52cc1a63cc7c980f3978dbb5a21beafb59ad146eae85cd955df47a00bce4c30bd04
\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1577746809000000	1580166009000000	1640818809000000	\\x0e19c3e0b1a4f874fcdb0948f273361f6068be0cf8c34a63c049a38c5a05dfc0	\\xe3dbba329f523af764575fc800fcd2d4276e8ec18ee1192bcf7257a3f6bbc52cc1a63cc7c980f3978dbb5a21beafb59ad146eae85cd955df47a00bce4c30bd04
\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1577746809000000	1580166009000000	1640818809000000	\\x0e19c3e0b1a4f874fcdb0948f273361f6068be0cf8c34a63c049a38c5a05dfc0	\\xe3dbba329f523af764575fc800fcd2d4276e8ec18ee1192bcf7257a3f6bbc52cc1a63cc7c980f3978dbb5a21beafb59ad146eae85cd955df47a00bce4c30bd04
\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1577746809000000	1580166009000000	1640818809000000	\\x0e19c3e0b1a4f874fcdb0948f273361f6068be0cf8c34a63c049a38c5a05dfc0	\\xe3dbba329f523af764575fc800fcd2d4276e8ec18ee1192bcf7257a3f6bbc52cc1a63cc7c980f3978dbb5a21beafb59ad146eae85cd955df47a00bce4c30bd04
\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1577746809000000	1580166009000000	1640818809000000	\\x0e19c3e0b1a4f874fcdb0948f273361f6068be0cf8c34a63c049a38c5a05dfc0	\\xe3dbba329f523af764575fc800fcd2d4276e8ec18ee1192bcf7257a3f6bbc52cc1a63cc7c980f3978dbb5a21beafb59ad146eae85cd955df47a00bce4c30bd04
\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1577746809000000	1580166009000000	1640818809000000	\\x0e19c3e0b1a4f874fcdb0948f273361f6068be0cf8c34a63c049a38c5a05dfc0	\\xe3dbba329f523af764575fc800fcd2d4276e8ec18ee1192bcf7257a3f6bbc52cc1a63cc7c980f3978dbb5a21beafb59ad146eae85cd955df47a00bce4c30bd04
\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1577746809000000	1580166009000000	1640818809000000	\\x0e19c3e0b1a4f874fcdb0948f273361f6068be0cf8c34a63c049a38c5a05dfc0	\\xe3dbba329f523af764575fc800fcd2d4276e8ec18ee1192bcf7257a3f6bbc52cc1a63cc7c980f3978dbb5a21beafb59ad146eae85cd955df47a00bce4c30bd04
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	http://localhost:8081/
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
1	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Bank				f	t	2019-12-31 00:00:20.514067+01
2	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Exchange				f	t	2019-12-31 00:00:20.589872+01
3	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Tor				f	t	2019-12-31 00:00:20.663582+01
4	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	GNUnet				f	t	2019-12-31 00:00:20.730127+01
5	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Taler				f	t	2019-12-31 00:00:20.795585+01
6	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	FSF				f	t	2019-12-31 00:00:20.859658+01
7	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Tutorial				f	t	2019-12-31 00:00:20.926234+01
8	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Survey				f	t	2019-12-31 00:00:20.996732+01
9	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	42				f	t	2019-12-31 00:00:21.430041+01
10	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	43				f	t	2019-12-31 00:00:21.861126+01
11	pbkdf2_sha256$180000$jM9xpyEYAVrA$FGmAv8s4WyEBPwINU1GDhtOr8s9FcA/VK6z1ZG4xQ8c=	\N	f	testuser-RLtMLjek				f	t	2019-12-31 00:00:23.510385+01
12	pbkdf2_sha256$180000$jzyVXOlRf7lk$Wffy5rDt8A+g6xYfxWlgFb7iMQu075aksT4hl849YV4=	\N	f	testuser-JK5q1el9				f	t	2019-12-31 00:00:26.672449+01
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
\\x783b74d204519ff198aaae4754504d9f498066c64acb95f3c5ad07df673f9fa43a3034647247a011f90e4c1feaff0580f02994c5126f73ed60607c6afaef0ac5	\\x00800003d5a5dfca6e2d2b3673e6a642c8794bfe21b3dd40df2b93a7b91b000a13a25ee14a18404d07f6c112e02f4bddb011d39a20a375057badbe2b1a70db8f5d891cab2ded8db047ee686fa734fe765e4f8430d827619afb410ef29c42c378c422f3dc3a292eea7ce301b03f9bf5ed2e48ec1d3ad5ea9f35b205c2cdf567495d659b2d010001	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	\\xf838c750fbaa0eb708df52e4e224696e68b6d7ac2a2cbb8c9bbfb654fd99149048b11ff2529e6d7e0ea6e5ec44bac7426466012497a649212592fb779463100c	1579560309000000	1580165109000000	1642632309000000	1674168309000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9b3b3688c0f015f46699dfdb07b54890745a7226e8d33247476afd16c4d3f49944169a6ff4d8b1a2923aac867e0e11972c825725fce7ca00264a7bbbe5a8d918	\\x00800003bfae6dcc382d0d73ea172644f4f4dba6acd30043c115dd4cc600bcb42a05dc6577e9e80e8cc06832f2cf0aeaec10beebdb01b0c047b12147c4b9317480d8395c41cd364778aba2209ce5d1a661d61ff5492596e086ffe404cf414e2508ca1cba176860aa4b3020b73f7294494d8d8e31d8fc16b17b48c79cb50d2baf19916b0f010001	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	\\xee5814c43579503ec7b300351ec23784ce00fd42623b4d3b8db3e92156ddcd660dc8176a7b3c87470310217767f49943cca53ea614fe5f8254a4b6d493bbfb09	1580164809000000	1580769609000000	1643236809000000	1674772809000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x144dbc55a3e8691747bf9daa35f838a66a374f446dda1b6fca49529fb92cf6dc8e1281750f73f6ea27db554045b2617e7a5c596c908859c9ada1ab73563b17ca	\\x00800003e09f7d34a01294928702464596bfb18de2d40429c87c237221b692fc20ee231a3c1667695eaafe3467182dcc482064a2636fa4012646bdb3b11fd0610f0550cbda45573e37f20f195b661c04054dd4b98ee23ba35706bbce5f917e126a7b03aa4667a391ef27a9b69e2a833103c1d16e4dfc204419488f9b3bafd8b6266f6a93010001	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	\\x7dac7396c55688dbf7a6889fc339a9be6836b33de7d6fd06a5be4f9097f71129a12b311d8301261a55b9f7fa7def58385f1a3a81d24a8de21b95a0511cd00c0b	1578351309000000	1578956109000000	1641423309000000	1672959309000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd8d7b08143f2844fca7a7c745a5c43a91945f2f42166ac2eada3e89009dcc661c80942d0d9bf8b0f0b560feb511612c8e4dd3060e9ad9aa6d513ac1f1bd56f84	\\x00800003ae12523751bbbc14f337401cd9be72e12f9f568e1e0a91852757d45409586619c4b996c75ab5c1c7ce4ed5ba50d9807a03fd46a91caa93e249f80144e657c17472e31a809cc25c4d5f8e7d4efb9847a54723b62e7491448cca45ca0807704a8da9d2b0663a1ce56c5e461ea501fe866efe942f3af80ec5d50cb81cac6653f90b010001	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	\\x8bbfc7a2bd875151aa8bbde2e30d18a56b98466c118da6f079a565ce70aa407c0fa039c6571bf624964e7a6b2ac21fabb51a6b93c5aa1df9c939ba2baaf4f208	1577746809000000	1578351609000000	1640818809000000	1672354809000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x69abe164f1998addf57649a27abb6b38fa3cf99c9e852cb47ad6245e16269e5391b3662230376f424e1cd17ea3e48808f72462be98f0f9a545bc9b2b2328e684	\\x00800003daa833def86344ea4a87c3348bc4d4a1e774bd58795945b492dc546ba76e48372ba4a384adde4ece53e05177d64dcfe2f43db26172e4ae7ef45ac4bc8d8247cceaf8fec60942e7baec4430ca34dbdf5abcfad3660b1d1f9f26c116bfa2ea8d7b0fb10de2195cf836db5d4dd02984cd5e562f371e1bc050b878daf3d42e8d5dbf010001	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	\\x9b2772c1d1de6c729e6b883184ffe5573ed55ac534239532cba3530a8540bf6f6843ee09fc5313f03a05c2556f6081a2adc9ea6504d3a19ba389b4f9025c4906	1578955809000000	1579560609000000	1642027809000000	1673563809000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xfcfaad44e668fe2f787800f640d8f1e63cf9d3adbbe2c96b7fb9020e0f267361804013988da8deac6eca7636ca4c8e9b885c97e8304864b053c80ed833f94860	\\x00800003eab6326b22692e84fea47787da48d8e2ce1d81913dce578a096267ffdcf6e2279e03d4f4a7ea969a8b08d72b34c90ac5238f433dc022ff0a1e373f329c6d5f0a043a36c3f5add1ff6fa878188306765e11dc4568f19e5982b38a07a43a1149841844faf1228761a9da1d9f7b4f7c34c1bb0ef561cf9e808efab27ccd676fe8f7010001	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	\\x628488271ce7714e641371dde762bd58a7b35e17a7721d1411aa7952b86f7abcf8262dabf778aeb1978018e3606c80fccebe6d0e88b5285de303f4bc94422005	1579560309000000	1580165109000000	1642632309000000	1674168309000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe8b887628469cd9ccfb3cee5a50367d98021cdca6348655b5c584e5532c21148a5908a99b98d36d9d4b3298f8eab78c9faf054d2877fc3043953c2bd410a2c42	\\x00800003e0f4c939dcb2519ea6c45487bc473ab316349bb993c860e99968b72a1b0e753d9d5bec26267051dbf165a29828f513503ba9a4fde5ae37238b0657516e2e26127e4d693d8d03c6f9adb48a4b9d64135cd287cc38926e7b0d2df0c16a37779b04a8faf7898ac7cfcb7f43a8b06f1ac6173151181ea33a3e4a55352a857088ef45010001	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	\\x64d0565788e593c50c9d652161f3d059989483e91f04ff1ae2859e2609f148aa5dc8b05f60a2f1a840e432772c107b5a9fa0e35a728d3d3175faade27042ba0b	1580164809000000	1580769609000000	1643236809000000	1674772809000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x89745af1ade3ff0e838ae861026494e0c3602939910291e83478dca98d3ebee045c19d5a2941d918622baebb4a178010496642d104729924fb9dc7f8a523a276	\\x00800003da34a690b0553338ba34e33243f506e5604bceb8262e0d6dd28c83173a1b9cc0faf2bf457a58c2f38d277545c0a8eb25ca3f6eddce376627ed2faacf223c3e2e85815c9b5c048c2f462dead2a48ab339c548a558d9a4063eb6d7e6256a52c71cd5609c11be34856832c142d244018354f359b2b3b04f87a9e654f9b4279238db010001	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	\\x011374c2ee82af4a47c7033c5d126d5c73fc970503036339940ade75a8c292ee523ea1bd6a6a5a8b3c7056cf8ba0045d0b083fb142b28a78433b8a363d412706	1578351309000000	1578956109000000	1641423309000000	1672959309000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7c18bf9b242fd7fce4ad8674f33d3aa506090231cb9afe6e775c7b587620943eb170eb90203b4d2c7c9ed6035cd0ca26b36242fcee0656a3c89934c89ef3f89f	\\x00800003c076dadadf04ba9212cac77164c56772da97004808c62a499fcfe2662ac6c4bae74f857366adaba3df4b2da2054ef75c373c8f50d2264d523c69abff54149d3a72c3e2b471fdc3f4f0364e24c600fdf92d5f8f57ecc750954f0ce40ac15409e4ec589704b01f2261e699d8adf944c8ec5f40eee99e3b45984d2a0dcee3b8d0db010001	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	\\x433e369e4d90b275893a4080cf97d76c31d05357e4b2c0fca298f4a02c7354db29917569f769390e6ad0377f78f78b52bbb8bd0010ff0e891b71524ca4ad8d07	1577746809000000	1578351609000000	1640818809000000	1672354809000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3cc1ca4edd597084a610efe6a1e9bf74581cba53c5f7055c8ceed9fc78a7f7d2856629a6b0b7f4898d13ab4a1e060d38451a7d3cd720ac59ac58f13ef2dafc1c	\\x00800003a1868831f9ba4ffefdc280e9f2d50a7f5b281088cdc8c6ae20a0bf7cc8c80f53d8750e29734316b7bf46c07999b9b9cd7aab8afd5f35194a9f57fceab52a42a4872eb54099a0c346487e4c01d8a76609f65f4a7e1263c8123404bf326545051d40a1c3f6b1b8a4e67c1c0d86f1a822f0b4f25ea50c7b189ae62f1166df136389010001	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	\\x99989079c3375ff42745c3be8955bb370a9a77326cbfcb61a6ee1d3e23410d692c2f478c0ffee8670f223be7d5dcd32f0a9177c14a70088ec5ce6b6d57807202	1578955809000000	1579560609000000	1642027809000000	1673563809000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6d708ca96750e7fe367521ad64371838c61c6df06767fa64284e522a998f87b9cf610a98d3e4677ea8f4254340ecea8c3264eb0c79d6b930d32cfcb6d9767a83	\\x00800003da53e698c43c9fa0f2ffef189b89d652418c46ce7805466f924219a3cd29734314134f1fc9f7fd5b4f0fad088e4251885392ba25d32ecb74e235f8b6986bc1e42aeb8da8de8927016b512ff9de64722753a0671f0dffc4dbd5e86a7a5cec9dd7ef137c4fb1f71badd251d6f9a025b26a76da098cd15cb039c46cbc4192b245e5010001	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	\\x391eb9441a6f3cb860feb99a7dacd4d4765efe546b4ef12e6b8fc6dd306c64bbb0c4d7af43940ecff27ee1fdfa1b142e8600df96ef389e1aadea8d63688a3806	1579560309000000	1580165109000000	1642632309000000	1674168309000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x689d197715468030f4db4c526ae798952354c5becd8e9e6b99d7ecb468a3764171862e06e2ca265302cd42d412a95a37313cde5e2215409211152b4b87bb5eda	\\x00800003adad0d5b3a6f6729b161a588676d412cc30dfe043d034d04cddaf6ede602b1165ade1832f1a324bebe101bd6035e80ea3b5ea3c247ae6e16ac06cacb3ecd6e2c80ac9dd06b6eaad0da37dff04b410bc412e79de36937014628ee074e9fdecfbd49414efe3e776c567e1cd0f45322b982bdbe41898cb6753c03691d30cd596c8d010001	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	\\x3f5e85e4432a11e55003c1594e1515a8df8c22771ac74d5e19bf0072c7b7a2ec022126a162ed632258151779eac67a29ca6d0593e07a3b018e0204dbec11d300	1580164809000000	1580769609000000	1643236809000000	1674772809000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x23a4a1072325d874a7695fea34dfcafb75834913961e6156254e85a32a8adbf5b264e26d850e24e569547e76a3a421014f27a006b68aece185c36c5344192534	\\x00800003c42b1af4a7dbd95d1c0d04e75172a8af105f1ec7bc14055b60b1dd897efba8de9c54ebb6d967644387efcc264cf8544460c400dcdfab6d4a3c7ff276159e7f463138a139d19339b4dbd0c4363073f50bc963d54454b74a5db307a48e2f3797d2d5f4dc6640e846725419ffa61f991528a2feede7649897397c80c9418bbe7f8f010001	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	\\xdeea409a0cae76ab19f8dc2179443b8aa3661e9e45740e776a0ab58778aa25646550b6b15fddf71dd5c668e464bad061b4e79d52f8c0ab33cd3be5d429bf2102	1578351309000000	1578956109000000	1641423309000000	1672959309000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x920e9115b1da0f24d49e2b70b1a0df0a82c19e741fa5fb013a3fd5c7a75577edd0aa800ca4d965b53b772ffb1562a3cf58ee82bfade084163e381ccbcd1d1f23	\\x00800003df0738f0729fd777fb51a8b15c0937d6be8e0e07f024da470cc2e3982e0098fc48418877733b940dd79f9f7586d5ede2e1eb3dd9bca3a16ad314ec794f99a6c4d42811d9baaa9b1b7f7c988fd0c542a9f93dc88e7fe514909e32ebbb30635c7792ae5d42f11d1f194279ade85ef64ac63f2b1b777a1acb10156f124eb53357e1010001	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	\\x132d9849fe8e354cd75aceb38bad53c92937625bf7cd5d6cf62de52b425c6258eeb3cf4d2ad06a58ecb13ccba8e079142b65fb9d2324660df90fb55eb1c23c06	1577746809000000	1578351609000000	1640818809000000	1672354809000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x488932ede8da593d716c1df29f698f624e898e6874bf741aed453c412a5277e798d80fede6bb11766439adaee2ef45bae5f18750f9d528bf0a72e058dbec817b	\\x00800003f449d942aadd2852f238ed387abfdb11955dad2b15980c7cbf33294bc6cdff935e6082cf7e85b6fb3051c820e29e4145cd3eddf33bef966a620d490117c8e27349847e461a286a5de6e68e66517906237434e4ecbee3c68ef973bf5a9ef32f968ed78d499a4527036229ee37988b55d9db425507911c95c9c96df1e2490f9a6f010001	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	\\xc2b18815b1e036052d45bc46f86952ef4a4f80bfccf7300798a245772ac64962f57e0a4fce945760ac2a21787655490eee2d6af55221e609d27e43328c79b70c	1578955809000000	1579560609000000	1642027809000000	1673563809000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9e9f7092d85a8b481adeeb7fab2a10064ac0535eb36a4c8c09796d824c4b1ea299d54597cc380805138dc5a95949ef52f318ac45b3c6baf32b70d4bde405ad36	\\x00800003bd5866b25e71f3b682566cf12defa99626893ad6cff7ab85cc095bf3fc99158c4c20cfe9f02e6c3e49fbbd485509d9e87e690e206b7f6634eaac589ae47fbe6267bcc8dc63e36058e5a8075cd4c477c67c09d0ca4765509e11e997274913840687d0b86d171da421b6dec57558b250b3bec3c9cfc237af217cd1f1809e004ceb010001	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	\\x50f13731c85a04972e650e5383563c5ce41196b77bef05104905ad5af26328dbe766d8a08fa403163c3f80c92d40c37497ff34084ce48bb73ac98a3289061507	1579560309000000	1580165109000000	1642632309000000	1674168309000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6452e8478ca95098ee05ef03648bbaf576689cf22fdd2e14540e9fa6aaf210cb9cfd74444ff58914677e22d77448a42639ee7fe798c9473f3c5a0debffcfaa0b	\\x00800003b2f53c8c5d4c88a7636d643cef6f5ba2d7be65878e5d6f5b4b34b02ca35f13e4ee6d3977d2607a6c7086745214e203970c02e985adb2045818c1e533c944f48c85ce7f0ba0d7566382d9dad1954c4c89bd9686a46549f09e1eb4a0f5cf843f8c5bc80d8ef07b349e61d9b925b97c70496e42fce0cfc25fd03d6de8d4a0845de1010001	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	\\xf01666a86f1c4c647cea8c5af2d6bee5dc443ab66b47bb9f5ca70ae37bd5bf8c7dae4ca075c5cb71b9d92e71633759280590330b1068ac75ad24d56b00acc900	1580164809000000	1580769609000000	1643236809000000	1674772809000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe2f1adb847a198289600ed40ad45496e066e704434f9d8665dbd6b0394b009ed9471190188678435bc920132b5701b476ddd1b9d36012d6cbb39430d61010b0c	\\x00800003ce594d713e1e67c865c03fa20e384bcc02bb46137baa0ee66e0cd5e9e12c922f6a7babcf36f04df3f21e0a118180bc708f8cef49dbf584b06ec41a393a66cc95cefbf995251bcac4c2295f951c5dbe49e20cba88b4daf5afc783b3d2a343187a5110e34aef28318884461585d10cc13694e267727e390c9a59823e35da2b8585010001	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	\\xb49dc24480188d03b424832183e74a57ec43daa98b0426a85250e491e014d2353da18acbb7393f9a363cbfb7d760a493cc830d2edfde7e2d7f59b2fe1f7e3400	1578351309000000	1578956109000000	1641423309000000	1672959309000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc778d97644c119f9ed0d672e416874091a384ba0603c118b2b5c4e9d9e181a67e9fdc99552cb81d3c8b2d5698faa889e4e6c6104147f3f1f9a2eb87dc6ec5dff	\\x00800003c19d25190cb3114d3b27c462bf5b29dd5e94100be9e6288ecd5282def551c84001ec1e276d093b522055ad00116c0de1ea2dae0b5c0e505a17fe0ea7bd23920f1e921ccbc5a0f1af8ac4fd249a4e7f442832bc9ac68cb9d8d034226269e6cf753b3bf85a37b89d385741eeb6d94d024d47cb5c42612be089c1199fd2e5f34d35010001	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	\\xb0c6cecd7ce1d72441e77ecca8e67813db4ff0d937b7a43468db34e424b6b57566a1783857e82fcea701cb59476998fc313d99196c4519136974d03e9fb61409	1577746809000000	1578351609000000	1640818809000000	1672354809000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x3ba0f846cb45e61e80d70ab22920a367c3428f0ea50e2312c38e5b9a84ad2399555dcd2776b9958b5dcef2ffcc3961e309cb9234a05f6d34acefa1398d439d77	\\x00800003e5709475a73245265de0829844af0412a1cc27a189238f244fd31342bc04f285cd9267f80c7d18ca17b968ca5789933ecad76f6ac5d2069a22a30e1794f7b81676482e2f367a95a0603e82124db55f86dceb0622b523b02ceef6604a2412a403b1c7414be695cdad611a9a7c2261b346b4764ed6765081bf496ab4371edf76bd010001	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	\\x7981d741838ab20075bddc61e21929a37ea5bf58a4669db431fc27cd020d596f8b95c9c49ded69745629f2705feb7c62e4b23cb63fc4dbb6a6e8dcedf0acea01	1578955809000000	1579560609000000	1642027809000000	1673563809000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa077e222863fe99d94b42691a62fcce09c377f6dfd14f61dcb52253a25bbef1688759b31300015e9da089cb0dcee59ff1c9566a030c9f9547fcdc3a07ed9ceed	\\x00800003c50cb044397236a0faae5c7653aed14d85296dbd053f436a91c1ff502f1bed98b489c036230060db8e641c2d7e56378310d3fb1fa5443147eb28d854c0626323550e20b999ffec60126f1560590eb7b61198e1653093e570fcd6d93245a213a3d3bd0d6349e7ef788e8b203c005c291bb5616f1d6f41b7631f3ea4ce89a7c82d010001	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	\\x5caaa2b662815598b23bd0a212147cf1e7e41e4a93d709d4bd54449aade6e5cd90d03d2bd7d9bbc054f5e331a9d74ef74fe38a932b0698fb4a8ec57e6b566e09	1579560309000000	1580165109000000	1642632309000000	1674168309000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x776b4cd96dfe541165dc6088d4f0cb72249e30a552a18d096ba82a098ee395f7f6701f4be731c734305dc1d159ea852011428269e0cac9372d125d94ee64be9d	\\x00800003addae2bc81dd6b08c1a337c8812b9af2939155d83a9887a46a03611d867098ac43f4bd9e159f365fbf980e74469a46054e8c6f109a1b6d30ce6a6b3ef6db4a9bbd8099c2d70ecfe99a8c2a312c24c46a17b4dd95d870991098f2c88a2cbd34db11a455f76d8434f385bf8a8a4eb38538dec932b703295f8696c03d1e906f52fb010001	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	\\x83c4a85459098b2bc18cf586dbdfe4f59fcb8ccac4fb63b8c32abf6f6d275e3dc4e192b0b3a0405edf133651ac9990bf1f3f507c00eaeb4c223f2a745f5aba00	1580164809000000	1580769609000000	1643236809000000	1674772809000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x7ae6cb2cf13b418990efbf7ecfeb9574125968c1b3bfc3d1c14d146d6ddeebcd077eb7b74d9ef4099bfda749c00ff17da46b11cd05ed5cab6ad9c3503b698140	\\x00800003d457535fb9d53d09ce29bf580b173e51239bf742634c5309cb92c8dfbde068bf98083ff26fcab72c6fd1f7ba712bea71a5d6027da9b2552416b1dda2628ad1986aaed9220cfe518bb578fca3bcb7cf2fcd8774d96f60954f94df06f3aa555156c39017887e0d132aaa6e57c1ef2d2b782194bc25c7b2588a0a076927abc0d9c7010001	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	\\xa6a0f85dd26be1c33301969605985b21e279ca9f043ec22643ff32492b54dfc8c44a42a22539bc110c8c817512fc035d8eb877b47e055b9fe0fffe2b575dd303	1578351309000000	1578956109000000	1641423309000000	1672959309000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x1b3e0100937fd48380574273ecb350f8b2f4b945b8944153a7d5be8467a144bc87ce33d2528b7b2b1a129e10b98ac7e48a79db395c9beffad08fa835619daf1f	\\x00800003b3030d57029d25d4623fe11405f01b0e54ee30fe0f67617796f6692cfc92d282b3922c22507df8e5ef7a27501988a1228550384f7e2edaf7f37fc1bb8ed420d2b3f4bc4bf8155b73256add0c903437bd07d34c9bff090e683d8137f578a0df1d80404efb853d9392f08622f383d14e08cd0beff8f31bbd83560eaeb30dcdcb13010001	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	\\x25f0a6e88ae21a5e84d0ba06f44fe0c058a9542012f4b8a25e2bbd1b64ec072d4e12bc535c223e5e69f076d6117aa94dcd71636eeab863494632ed78ec482400	1577746809000000	1578351609000000	1640818809000000	1672354809000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x8c2c304e7f5ac714069cd1d8755ed91c9a4a428bef281116e639318b2b5babdf9559201b54df6108b9cf4984d97f42e41ab921e7b6df737a6a3174f0f12f9e3e	\\x00800003eedb0fcad27dc869de098c600266d80637dcc11806215455c48cd900f40792eaad7869d5fbfc8902e980440576961d76687f2f020560f28caca5d5d6087ca6edefbe2e78733f1a21727be437a6052c9e36c486be1a273b170ea495583d8001688a3ed46e0d106bace000d7df7041a821d5b16282900671dbf45774677b8a832f010001	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	\\x1c728afc35dae78bfdee13dcf42ad87a03def080c1993d2d3bee47c1a18f4a07fc03a5f735dcdc54a2772eb044ff6a03d81823345fba7612a76be9a8389a1408	1578955809000000	1579560609000000	1642027809000000	1673563809000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc38411740a83c7909b1f3914442cf37f14cb53e314710e45bed5013cf8251cae6204072046110dbb170cde97cba838fadc308efc7b6dcd5350077b78f29f8387	\\x00800003d844ec4c1c535115af981b59ed2cfb176a7f5cef5c1c7ed49cc32e5bea50f9fe94a01adb6241fc1a6fbd59df6280cba4a84d4f7ddbff445aa49ff3bff7b2ad54cdafef0d930241c51e1349035a0e501a7eaee59de4c459f52ac9efb55789dd6fc8c82a62106ebbc7c817d3862a0f3a5ed9a8d6db5d02353fcf283bf6a2140fb1010001	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	\\xfbe6d2359790928e4d9b227fcd367e83d9ecbf27c599284dd2d1d8b908c3bf6d0d7655363bcd8a5797c6edd2a3cca301a0a6f782f35ab76b157b5b94cca2d800	1579560309000000	1580165109000000	1642632309000000	1674168309000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x12ea169032a67977671cd11ecb4d2ab9f897df08cc39e165e48a70cc50329454e94273fd9df5b672fe8df964304cf520f8c9049557c55c68393f6aa712cfe4e4	\\x00800003ace0b93481cee0acb0086a8217467b19f1d0a2ca97c2ba242a9fef554d30629f020bebb919a1d7ec70afee3d0569792de011ee2e8e1fe3817bda8a12d5f55be2fc13bd46e49f69be3789c55e4ba7bd29e3d79d275d7a6988deec2f0222282cd7d1ecdefcce59c61babdc542e2620914c08ff34dee1eb9cbd6a26e68373b7fcf5010001	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	\\x10e55e56a1707f85b393da0e5ee76304b22fc1daeaab1122ebec44b91be320d1a64fe4b04d550f9bd11b5a735eeeef79676a6fffe6ffb2dd7a37dfd2d1e14f0a	1580164809000000	1580769609000000	1643236809000000	1674772809000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xe645dbde738ac1a4dc6219abf7d8b3536a62decd3308567234dab92c133a43988dfe37587a5cca8483d18dd0af0d98d6d06eb97b48ddd1f743c49c884acad39f	\\x00800003d7048ec1f91412a7f75db0723cc3336047d0367f492c74f6b806e3c1427f5ce659c1fc2cdf07c44233d7688976d1934602655bbcf5352b2c277964f3c32e39e4f950675c8ca8201857847dbb6053efc94b1e9bf1ce1c33a9a12aafabdb72384af6c8f7417ea5d2e436df9ac329b8273a3fb29506343e5d39ab391015b39cec79010001	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	\\x1975dc7b27861e0de57bba4be6ef4c1b999dff362e2b6450ff3aa09ebfcdf5879e3a6d8167a4dc30e7953e469aa9440e5cf226c9983df140bf185ea6888bbf0a	1578351309000000	1578956109000000	1641423309000000	1672959309000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xccedb56d361d4983321788041be2be9b2b9b122faca8fb3550c6018f113572a57dc032c1bf77c484119d750a2a7072c062885cf8403341f91ffe22d8b7f678e5	\\x00800003a5ec3aec81566a3d17568b6ab6ccca98f5d4f4ce6bda03a9c4bbd0b67ff5de583f9c25b7cdbc6d727c98641adced8b06d94545819d38a029e01b1f933cbf7010dd719d3dcaf2bece9486a3ee43e85733b9121f61782dc27aee94569aa246dfa17b783e99f29b31d4c23942cd32b0d93d149089c7f990436fac1602b319080ddf010001	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	\\xaac9fb47f7d2404cb06b69a83602f92376593d8eea27b9a6875e3a5fa9f8c33b8020e57ca216693a03fd7feb460fb5aacec173c056066b09cec94f2e0cb7f309	1577746809000000	1578351609000000	1640818809000000	1672354809000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x275372044893862756e76dfaa9867d4b2e51c689c43bde66ac28898e9ff56c8c4cedfcf584cbfb2bdd01511965489d39517ed760c6a3d4c67280299bf6bba0cc	\\x00800003ccc90ea9fdeed59c10c0c6183fb8c0445240f062eb9501882d28bdeb91b7f0b67b284f880266428490858c5109783a996a403a4f57abf3a86d16826ebf7245286d68d72f50e6445d4049347ef1ac88ee705532bf1061f88fe423b2dfac4d3ae6cf20b9d9edfae07f5cb3292d0568ee9fffada2d289528a372d6977d049cf96cf010001	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	\\x6fc7cced96ce9e0764f350785f6e5288cc193c237b3208144c6844136061da617e0535e6759ce851d1649494a9231cae1cdc09921625ccb7d0ea037cfa726807	1578955809000000	1579560609000000	1642027809000000	1673563809000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xbdb7a0f6cf3f9e30b61648f8829ee780392770c3a032f56b828439341aa23c8623723d3ea65180ec80b4204d5245fcbe0a6c189169cd9d987d221d414eb2cf18	\\x00800003db4e03ed97d031d68d2809ebfd6120e8245e50d0dd645503ad8ee08487eabed8044d21ab696843b84352e67489b3f80062cf1e6c91ee99c54c3d73fef297e3f77c962360e2b273b1738c37655662cce92c3986545462663ac6a044e236693f73a5067b01f94c6728a5419cc31d272d1636f0ba0ce42324c403855315d462453b010001	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	\\x9c8c745446ac56a833d811a1d1ae5a001592626853747e449e51d60ea93e8d42928d4b7dd74d888e51e8d3cfa8f7b7171fa53544cd7042c37b39e2e5d0ae9202	1579560309000000	1580165109000000	1642632309000000	1674168309000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xa14362e07722207f2542b0af76469072932ae93fbcd6e4d49b3663e124bbc2ed66732cf794156f95c2ffaf679f5f815629da7c82e786d9311865d63494bd0295	\\x00800003dab40ada33a6f1891cf3d5a2e0628e986b8469dc1e989b39636cd371e9201d53b5d93b5105f17c175c1d53f2af5ee7514aeae6267001f75f4cb2d11ff42414221245af356232ed8074f7df34c9d6d0eeba6ea2ce4d9a1b3d1d02e1369281313edd169fcffce902a1755eabb51519a883190a4d8d866c594d91037dff3f67003b010001	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	\\x6bea9ebf78de3ded141cc21ba0f1863273236b7a9e95e962428c72726ce1b0b9ff0933f8a32ee3b214dea8f057ba5dceac87878c1e30310bc9a24612b385130b	1580164809000000	1580769609000000	1643236809000000	1674772809000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x0a947840e9a66873f904ce45bd4874407321d8fa8de91c2b5727effdbb718162d62b64243a0b052271a7e8ec0f321391dd5dd30405e45b6b3984026cbf2816e1	\\x008000039cb22aed242ea355992712b8efe0d506a38768f91d91d8e28ef8dd7aa11f74f2b04088db159bb1c2c614552ff5f4028f9e09c6cd20ee0bb8a8f66e5ad170bea1ce6198ec82c7a2dc8af04a59d88c2848fc7414d6e423fe10a06bcc94baa20554ba1b208b44376a46663508803f4f18baeff26a62900c330eae1aaa7d942996eb010001	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	\\x8c6185b25c827578c0bd1336c861feaacf6b1500bdfcbbe2814db5e56f432378ba66c67ec31d038cc9a7a3204be876b3dddfd8293baddfb96a41fb99afaff30b	1578351309000000	1578956109000000	1641423309000000	1672959309000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x401eabfce5c5cefe6b489e963f5c81d5b02004f76d5968869cb843acf0571bb0d396eb4914253f4a0c862955d7eff492d19c888376d324898d7795376e21950a	\\x00800003ef8eb2f6e91441344ffe0509e9e1331a650896ee8f9fd99fea4b5b602c5c2421b9e27d848044076e3228f96a8a0394fa4ac6e359eb7f0138df31c25716a7f00a93ed0a31ba142c2d027ea34fbec9efbaea737e23bf233c805167cc6910e61c410d0677fb0dc165da03fb3e9cba305ea72970fb4d27f09cd780e61fdf4d78a163010001	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	\\xa2c6b023681c7d010c2fff7299e6163841879bdec1bac0a884ae04e9deb147843f6d906b16f8b3c8dca491735356848ca96d1c1b517e0548661f69eafd389f03	1577746809000000	1578351609000000	1640818809000000	1672354809000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x7e4a95bdaf6fb28596d0cdff276766621635f7a73f2d9aad27a6c6b7f61cb414a3a1b7e3bf9b0b83c463efd4009a8281808ef6593ba455c9d92487ebd2900c71	\\x00800003aac03542c245efd92123d3b3380d10c8383fcf908144b1c06db7004528744c465fdad5a058c7b56f92548c743d26a16cf107a0ec00c422e24d3185be3c5f604b5cb837af53eccc924c4355c6e111434156c2baf0078a20201b23bccb3cf6778a1c87b20102148eef707a5a4a2bc2498837417380724fe701d56e7164a36a7a8d010001	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	\\x16ce6d2a042a846d3eedcc03fc97603909354068aaa43d005d192e588b3e953c94dddf0a11d57d9732f107433c826c1472103b1b1ce8d38a164dcfb37f132904	1578955809000000	1579560609000000	1642027809000000	1673563809000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x6c7d94e4e3706176aa38213b0e61403bb5be64155b34a3536feea15f6c1231342b54d1315a06096e25a0a9884909e8ec840e0fa532669faf6c5e4d053af271fd	\\x00800003bc23bff7217336c3537f580aa730fc7b329358fb93a28384dc965738c30e7bc5c3b9a6f832f30656bf726fb1656c32b7ce0c3da721dc5c47cccbd93f45aa6ed5d52ffa3a90f580b04e79fb308cbef0bc05ee88dc18d35a366ed58f6cc018caac8537b70228ec123a041cd9616ec9b519db8f71dd80ee9a8e96a96020c1e26dab010001	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	\\x70f945ea9a7cffcb80c02e8df3d1f3ee41743f47d5e8b8fce87447ea7f13586e785bb6f4e2b130060615b91dc17902fcfd66b582a7b330d148bd9d8b636e960e	1579560309000000	1580165109000000	1642632309000000	1674168309000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x95c4c74cea107a33b7ddaf4d3aeea9330f6376a769b39f574ef6ee75344f062f3a5ce1ebc00f79066d9844b87bbd39ce684af63e7ebda7168c8b415a3b42b3a3	\\x00800003b58ea8b85587a020e555454af5584a2acad09604eff2689b5d6df67c8f25546210d01304bf5e3274df30bf2472b7c03cd155ffe445d6feb3f3072ca67a7d0360772afd6970fa46b3b563b2bdf3c4396d1b565d5cbc8ca18ba2597248738f68cf2ae663ad14963e3dc924b90faff50c63070ae86caa28d86f4e85d1a5897b2d95010001	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	\\x289c942ef172d7376292eb18b2ac2687b33df0c11c8db89a75f20678e984f67288391d8c838282b40103ca25b5e60f3a1a5a2fcd4f8cab4bf71e0adc60f57201	1580164809000000	1580769609000000	1643236809000000	1674772809000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x730c5f2a98843facfe6cf9165cb687879ef19c3ee138d0135914da1ce8008009a950cbabe46ad3798c5cb897ce121d7b215dd05c7440747bedd2e813a533f33d	\\x00800003e490f7b13a61849ee190e43b101d90b18a4dabe7c1c065441f6b67f5ed8edb9bf13e4d32dff72c4dcc3e6232417f4042c65f121976c8a202bf39d8927ffe06a0378685615cb799aaef301b28a95a80970ff866246b3f4bd261b7feaf3750aec352e3ee46df72a0f63977bdc4b2f50d6221b2d3e16e58d972eed9d886fa922e6b010001	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	\\x966bde53f669ed16be4f5e626fdc01dbd60e9ac45948ff0d68204588988e015e5cc408f5fc1be3e8290bb4e57a34022dc66b91dc7ded6f14514bfaac22fc9808	1578351309000000	1578956109000000	1641423309000000	1672959309000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x6159cfc0e5a49ef2cdfdf6116f4fda2a8fafe91ccbb292a5c4e816fdc273a6aecf517155709d17d4e0e95d1c9ce413bb752bc192b9dd014f13e352f98d964d87	\\x00800003d85bf6e88dfd4394cc78e241e6870853203d923860cadfdc2d9d3c43ab67ab9d36b773c7a075a9331cfc6f3de00cf18944273cf6b453ae1a20ea22a79cb4cf3d33926d545c89894667d10f9787a0a7ba6e81525503e838ad76dbb6c33407e7d5c8a6b6c1aabf91be278cc3cae38fcfced038aa66add6ba8bae0a52fbca113f39010001	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	\\xe791295d6fb5e522265110ca082cec8c9895032813d608441a0083a921d582353dab8b3a20c38e62d0ab22de1a064cfeff12aa8c24490c5edf2c602b4c1cc705	1577746809000000	1578351609000000	1640818809000000	1672354809000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xf0880be1a3e2eb4b7d2ccd861be6bdc28d665773cfacc84f707209cc0b66bb774f29ffec2af61c1131b4c87ad7cb2c3f28649eed0b057de3c76c98b7a6d8bb40	\\x00800003d3698a71db3b7b4ae96229e21d2deddaaeb5773c7562b6a13098c4ad23d4f46f7b38ff77b8fbf0b6f2acac5e3baa41967cf0ede64a734a50997f2673a16dbf368b1555e489edaead5b6e6c2a1dc7b59c408d39e279161159819f66932c4ae6408f6b9c581b44f2bbce4790a25c9ec1f0e25393f9f61aa2325c2aa27927cf4e91010001	\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	\\xcbbdbd9ed1de3c5d0eb0a36c9397a76c5a3076a61ec40c98f86e41791fd10de3e35dd325d01b4366e07309f2ee8a144e8e5f4c010fd982f0a0b2b441d9cbef00	1578955809000000	1579560609000000	1642027809000000	1673563809000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_wire, "timestamp", refund_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	1	\\x8ae8b73edabbb8276bfa368643bedb7d673ecac61d1ecb1f620b29fcd183830ec12b70d53ba89b75c6e9ba4a249cefa2c25027263e8e4a31bbbdb12574e7b569	\\x0375f5618be0f06c0c26a3fee852b6015a274a3744ab7a69cb0d79be471d4c3886d68d8bd107902c5cfdac5abe27bf216c92980e5aad9cea30ac659056889244	1577746824000000	1577747724000000	0	9000000	\\x6f35a9c394379cb7a93703cce5338a3a4a451fc8770f067da4c41fc1d9c35de5	\\xf72f8edf0baf3ce18d8d78e488612b4bafa12f24f1fb5cd87e2fa8b6d86ccc9a	\\x1d3467c00246b3ba88ec4738dbd4704617074feedf43db5816ce972d4fdc0c0ac1305b386a5f4f86ffdc8dd3bc12831a74ba94671aa627fcfe18288b32af1702	\\x0e19c3e0b1a4f874fcdb0948f273361f6068be0cf8c34a63c049a38c5a05dfc0	\\x165597a8da7f000000000000000000002ec68ba801000000e0d57f9fda7f0000e93e9acb66550000c90d007cda7f00004a0d007cda7f0000300d007cda7f0000
\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	2	\\x8ae8b73edabbb8276bfa368643bedb7d673ecac61d1ecb1f620b29fcd183830ec12b70d53ba89b75c6e9ba4a249cefa2c25027263e8e4a31bbbdb12574e7b569	\\x0375f5618be0f06c0c26a3fee852b6015a274a3744ab7a69cb0d79be471d4c3886d68d8bd107902c5cfdac5abe27bf216c92980e5aad9cea30ac659056889244	1577746824000000	1577747724000000	0	9000000	\\x595039403882731095106c7cce626c4b58b5e82881d0d9aefe608b0df32cc44c	\\xf72f8edf0baf3ce18d8d78e488612b4bafa12f24f1fb5cd87e2fa8b6d86ccc9a	\\x06127d747f785469d16c73cf26ed85c2da6c6b340fdf0825f26432569c33589b847d6f625acf159adfbd5f226374e1e73a78f112bebd0a77d9f9f5cf956a6106	\\x0e19c3e0b1a4f874fcdb0948f273361f6068be0cf8c34a63c049a38c5a05dfc0	\\x165597a8da7f000000000000000000002ec68ba801000000e0557795da7f0000e93e9acb66550000c90d004cda7f00004a0d004cda7f0000300d004cda7f0000
\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	3	\\x8ae8b73edabbb8276bfa368643bedb7d673ecac61d1ecb1f620b29fcd183830ec12b70d53ba89b75c6e9ba4a249cefa2c25027263e8e4a31bbbdb12574e7b569	\\x0375f5618be0f06c0c26a3fee852b6015a274a3744ab7a69cb0d79be471d4c3886d68d8bd107902c5cfdac5abe27bf216c92980e5aad9cea30ac659056889244	1577746824000000	1577747724000000	0	9000000	\\x2062e9595d10e61629267f860449c8c3387b7ad51587aac29ad8e2513f2e958c	\\xf72f8edf0baf3ce18d8d78e488612b4bafa12f24f1fb5cd87e2fa8b6d86ccc9a	\\x504e0989cb0b8e42a50cefaa64d57dad65c3d02aaf1c3dbc4052742953ea48d1279a271e2dae603d7cf1d527b560d04510790d0330f3eb974646af0d84cbe603	\\x0e19c3e0b1a4f874fcdb0948f273361f6068be0cf8c34a63c049a38c5a05dfc0	\\x165597a8da7f000000000000000000002ec68ba801000000e05577a5da7f0000e93e9acb66550000c90d0080da7f00004a0d0080da7f0000300d0080da7f0000
\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	4	\\x8ae8b73edabbb8276bfa368643bedb7d673ecac61d1ecb1f620b29fcd183830ec12b70d53ba89b75c6e9ba4a249cefa2c25027263e8e4a31bbbdb12574e7b569	\\x0375f5618be0f06c0c26a3fee852b6015a274a3744ab7a69cb0d79be471d4c3886d68d8bd107902c5cfdac5abe27bf216c92980e5aad9cea30ac659056889244	1577746824000000	1577747724000000	0	9000000	\\x3fba0b5cc29aee6ba218c9a5842be02a60b662dd2a3165d20d376fe1d0a947e3	\\xf72f8edf0baf3ce18d8d78e488612b4bafa12f24f1fb5cd87e2fa8b6d86ccc9a	\\xa2f5b8185a7500f57be0876d839eb1f6fff1a4ced41089146d140dabcc7f596f7fd7450a6542c510d7ac719f54c48815a74e7c5eb075dd153808803f9c5c0606	\\x0e19c3e0b1a4f874fcdb0948f273361f6068be0cf8c34a63c049a38c5a05dfc0	\\x165597a8da7f000000000000000000002ec68ba801000000e065f795da7f0000e93e9acb66550000c90d005cda7f00004a0d005cda7f0000300d005cda7f0000
\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	5	\\x8ae8b73edabbb8276bfa368643bedb7d673ecac61d1ecb1f620b29fcd183830ec12b70d53ba89b75c6e9ba4a249cefa2c25027263e8e4a31bbbdb12574e7b569	\\x0375f5618be0f06c0c26a3fee852b6015a274a3744ab7a69cb0d79be471d4c3886d68d8bd107902c5cfdac5abe27bf216c92980e5aad9cea30ac659056889244	1577746824000000	1577747724000000	0	98000000	\\x78e5e77da993198556de1fbb3b5ce31dda673fce143ce9e2401e37a79169a69a	\\xf72f8edf0baf3ce18d8d78e488612b4bafa12f24f1fb5cd87e2fa8b6d86ccc9a	\\x92852a52ae398b1cad003b18960027577acf6c6dea397d969aeced06e1ad08234869a2cb83125782713dd322420ef7508d556e1d4cff35d8aa8e46f26aaaec0d	\\x0e19c3e0b1a4f874fcdb0948f273361f6068be0cf8c34a63c049a38c5a05dfc0	\\x165597a8da7f000000000000000000002ec68ba801000000e0e5ff4bda7f0000e93e9acb66550000c90d0044da7f00004a0d0044da7f0000300d0044da7f0000
\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	6	\\x8ae8b73edabbb8276bfa368643bedb7d673ecac61d1ecb1f620b29fcd183830ec12b70d53ba89b75c6e9ba4a249cefa2c25027263e8e4a31bbbdb12574e7b569	\\x0375f5618be0f06c0c26a3fee852b6015a274a3744ab7a69cb0d79be471d4c3886d68d8bd107902c5cfdac5abe27bf216c92980e5aad9cea30ac659056889244	1577746824000000	1577747724000000	0	9000000	\\xf8212108f000488607aaf1a0fc87e988fafae664df2e9c11534d4fb9f910aa6b	\\xf72f8edf0baf3ce18d8d78e488612b4bafa12f24f1fb5cd87e2fa8b6d86ccc9a	\\xf421732d227a97c30a75db4a521e8962dc1f87573381cdd4d176a71f6b56cbada54ba2c6350bad1bee103a8144f372ca50cd6f23cc61c0c17bbdefa1f3a5ed01	\\x0e19c3e0b1a4f874fcdb0948f273361f6068be0cf8c34a63c049a38c5a05dfc0	\\x165597a8da7f000000000000000000002ec68ba801000000e0757796da7f0000e93e9acb66550000c90d0090da7f00004a0d0090da7f0000300d0090da7f0000
\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	7	\\x8ae8b73edabbb8276bfa368643bedb7d673ecac61d1ecb1f620b29fcd183830ec12b70d53ba89b75c6e9ba4a249cefa2c25027263e8e4a31bbbdb12574e7b569	\\x0375f5618be0f06c0c26a3fee852b6015a274a3744ab7a69cb0d79be471d4c3886d68d8bd107902c5cfdac5abe27bf216c92980e5aad9cea30ac659056889244	1577746824000000	1577747724000000	0	9000000	\\xd22eae9c01fa38d3a301e2641ef1a37fa676461b0514d3a26700f12f07b1121e	\\xf72f8edf0baf3ce18d8d78e488612b4bafa12f24f1fb5cd87e2fa8b6d86ccc9a	\\xe0e7d756ca30ac2a2c6fdc14180a7483e1653bcae09b80bbedb66e0cedf9e63071b2a691c5bcb17511831c897c7f78b61f06906165e64402fe8e80d24477ec00	\\x0e19c3e0b1a4f874fcdb0948f273361f6068be0cf8c34a63c049a38c5a05dfc0	\\x165597a8da7f000000000000000000002ec68ba801000000e0a5ff9dda7f0000e93e9acb66550000c90d0068da7f00004a0d0068da7f0000300d0068da7f0000
\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	8	\\x8ae8b73edabbb8276bfa368643bedb7d673ecac61d1ecb1f620b29fcd183830ec12b70d53ba89b75c6e9ba4a249cefa2c25027263e8e4a31bbbdb12574e7b569	\\x0375f5618be0f06c0c26a3fee852b6015a274a3744ab7a69cb0d79be471d4c3886d68d8bd107902c5cfdac5abe27bf216c92980e5aad9cea30ac659056889244	1577746824000000	1577747724000000	0	9000000	\\x2a69e656c642312357abdb1449bc6669c3f5a9fbff3dfb9b4d54817112e0e7ed	\\xf72f8edf0baf3ce18d8d78e488612b4bafa12f24f1fb5cd87e2fa8b6d86ccc9a	\\x75c4653ed5651fea935fe738b1fb1e9a39199e7790fa3052fde93b721212385fb1631bec8baa69effe31dd3fe1d247922ee0fd8da3347138fbc9c7facf4d1c0c	\\x0e19c3e0b1a4f874fcdb0948f273361f6068be0cf8c34a63c049a38c5a05dfc0	\\x165597a8da7f000000000000000000002ec68ba801000000e0957f49da7f0000e93e9acb6655000039a5002cda7f0000baa4002cda7f0000a0a4002cda7f0000
\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	9	\\x8ae8b73edabbb8276bfa368643bedb7d673ecac61d1ecb1f620b29fcd183830ec12b70d53ba89b75c6e9ba4a249cefa2c25027263e8e4a31bbbdb12574e7b569	\\x0375f5618be0f06c0c26a3fee852b6015a274a3744ab7a69cb0d79be471d4c3886d68d8bd107902c5cfdac5abe27bf216c92980e5aad9cea30ac659056889244	1577746824000000	1577747724000000	0	9000000	\\xf88324ad92eb8843521cd1e0c1c7a25c9b9c0039f97fd0c697e8f9439e015e90	\\xf72f8edf0baf3ce18d8d78e488612b4bafa12f24f1fb5cd87e2fa8b6d86ccc9a	\\x2553a2846a9e0e3a3398469fdcb5a27b08079ee3d1e8c3e7e420cf2616022b63f206e83eefe7ddfb40d9582382bdb12ad337a0886ac3e7b261784bdaccd3c70c	\\x0e19c3e0b1a4f874fcdb0948f273361f6068be0cf8c34a63c049a38c5a05dfc0	\\x165597a8da7f000000000000000000002ec68ba801000000e0e5ff97da7f0000e93e9acb66550000c90d0064da7f00004a0d0064da7f0000300d0064da7f0000
\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	10	\\x8ae8b73edabbb8276bfa368643bedb7d673ecac61d1ecb1f620b29fcd183830ec12b70d53ba89b75c6e9ba4a249cefa2c25027263e8e4a31bbbdb12574e7b569	\\x0375f5618be0f06c0c26a3fee852b6015a274a3744ab7a69cb0d79be471d4c3886d68d8bd107902c5cfdac5abe27bf216c92980e5aad9cea30ac659056889244	1577746824000000	1577747724000000	2	20000000	\\x9bf66379c506850d81c732cdc85c9c4517578e33ac5effe8916c2e352ea19006	\\xf72f8edf0baf3ce18d8d78e488612b4bafa12f24f1fb5cd87e2fa8b6d86ccc9a	\\x6a59f57f9eaee99315951556d6f5ebabe2b9f50987d6fbb83e9dfebb717edeecdc125e6d69b2d2eca32bbf1f7238efb5940e911b4daf2a210485ba31f13fc807	\\x0e19c3e0b1a4f874fcdb0948f273361f6068be0cf8c34a63c049a38c5a05dfc0	\\x165597a8da7f000000000000000000002ec68ba801000000e085ff9cda7f0000e93e9acb66550000c90d0060da7f00004a0d0060da7f0000300d0060da7f0000
\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	11	\\x8cd2b92e8e6b7414be40bdb04ea2a0aa8ea16fb14050420957e4ca1d9acb7619f337d1c95d58d1964522b62a15c4db0be8fe0729acbee1031d948c9f3eef236d	\\x0375f5618be0f06c0c26a3fee852b6015a274a3744ab7a69cb0d79be471d4c3886d68d8bd107902c5cfdac5abe27bf216c92980e5aad9cea30ac659056889244	1577746827000000	1577747727000000	4	99000000	\\x364619793416e999dcf6df9c6a16d41387c8b05d59c6015812e09047709875a5	\\xf72f8edf0baf3ce18d8d78e488612b4bafa12f24f1fb5cd87e2fa8b6d86ccc9a	\\x056d1e5c10decb05fe296545de62a6543ff05e98305aa620027f719457467460e03a6e3fb65c98e979c4a95b7cc2015e54d3c250490e1775b752d4f554dedb08	\\x0e19c3e0b1a4f874fcdb0948f273361f6068be0cf8c34a63c049a38c5a05dfc0	\\x165597a8da7f000000000000000000002ec68ba801000000e05577a5da7f0000e93e9acb66550000c9450180da7f00004a450180da7f000030450180da7f0000
\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	12	\\x8cd2b92e8e6b7414be40bdb04ea2a0aa8ea16fb14050420957e4ca1d9acb7619f337d1c95d58d1964522b62a15c4db0be8fe0729acbee1031d948c9f3eef236d	\\x0375f5618be0f06c0c26a3fee852b6015a274a3744ab7a69cb0d79be471d4c3886d68d8bd107902c5cfdac5abe27bf216c92980e5aad9cea30ac659056889244	1577746827000000	1577747727000000	1	99000000	\\x4d39e16ad825c1d775a24864dfebf67b240d606a67391bd833dbc2a38d6fe8a5	\\xf72f8edf0baf3ce18d8d78e488612b4bafa12f24f1fb5cd87e2fa8b6d86ccc9a	\\x6d55db97aa8748ebfbe6bca170684333cb003cc0b9dc87aae10cadff7d94d43359fa6a8ceee695ba8b51269b2ee9174e1b7317a5a22bacc26b8a9c0d00f4f003	\\x0e19c3e0b1a4f874fcdb0948f273361f6068be0cf8c34a63c049a38c5a05dfc0	\\x165597a8da7f000000000000000000002ec68ba801000000e0c5ff9eda7f0000e93e9acb66550000c90d0074da7f00004a0d0074da7f0000300d0074da7f0000
\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	13	\\x3f9907dffc570ba7798931ba342ebfab1e6efc250462e5f3441546cd15daa68b2b83400c6471572420930fb62e0f80d8cb6676d020924fcd78bb4dc69d9ba132	\\x0375f5618be0f06c0c26a3fee852b6015a274a3744ab7a69cb0d79be471d4c3886d68d8bd107902c5cfdac5abe27bf216c92980e5aad9cea30ac659056889244	1577746829000000	1577747729000000	2	99000000	\\x040cb96fb1886ccc75e018fe3f35eef94290e3888c2e6a9068a3e411b80c853d	\\xf72f8edf0baf3ce18d8d78e488612b4bafa12f24f1fb5cd87e2fa8b6d86ccc9a	\\x65623a5fbd3cb23ddfab499b24a214131274eafc461aab3e0864e94501e9b3d0d7327473d10be44ec940a4a33b73900ab60eb2e2f725316fe712c8058daafa01	\\x0e19c3e0b1a4f874fcdb0948f273361f6068be0cf8c34a63c049a38c5a05dfc0	\\x165597a8da7f000000000000000000002ec68ba801000000e0957f49da7f0000e93e9acb66550000c90d002cda7f00004a0d002cda7f0000300d002cda7f0000
\.


--
-- Data for Name: deposits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits (deposit_serial_id, coin_pub, amount_with_fee_val, amount_with_fee_frac, "timestamp", refund_deadline, wire_deadline, merchant_pub, h_contract_terms, h_wire, coin_sig, wire, tiny, done) FROM stdin;
1	\\x6f35a9c394379cb7a93703cce5338a3a4a451fc8770f067da4c41fc1d9c35de5	0	10000000	1577746824000000	1577747724000000	1577747724000000	\\xf72f8edf0baf3ce18d8d78e488612b4bafa12f24f1fb5cd87e2fa8b6d86ccc9a	\\x8ae8b73edabbb8276bfa368643bedb7d673ecac61d1ecb1f620b29fcd183830ec12b70d53ba89b75c6e9ba4a249cefa2c25027263e8e4a31bbbdb12574e7b569	\\x0375f5618be0f06c0c26a3fee852b6015a274a3744ab7a69cb0d79be471d4c3886d68d8bd107902c5cfdac5abe27bf216c92980e5aad9cea30ac659056889244	\\x863b85d91380cac35974c6f38e65b3adb66d4fed1888e4d4a2ca2cabe1bc69c06e513cd2cb4c3aa5044dfd2daa335032e79b48950e717c5f263ddf7556aa4207	{"url":"payto://x-taler-bank/localhost/42","salt":"6XZMT4EBZ9R4N02DY0X3VZGJ2ZEYAWTYWG3WJ5KN7ZDKVNJZQ4P2WKYPSAMZNMBJZK04K0PE19VDXE6N39ASE4W349R6NMRF905MSR0"}	f	f
2	\\x2a69e656c642312357abdb1449bc6669c3f5a9fbff3dfb9b4d54817112e0e7ed	0	10000000	1577746824000000	1577747724000000	1577747724000000	\\xf72f8edf0baf3ce18d8d78e488612b4bafa12f24f1fb5cd87e2fa8b6d86ccc9a	\\x8ae8b73edabbb8276bfa368643bedb7d673ecac61d1ecb1f620b29fcd183830ec12b70d53ba89b75c6e9ba4a249cefa2c25027263e8e4a31bbbdb12574e7b569	\\x0375f5618be0f06c0c26a3fee852b6015a274a3744ab7a69cb0d79be471d4c3886d68d8bd107902c5cfdac5abe27bf216c92980e5aad9cea30ac659056889244	\\xa4ee249e5b87eb95c712e0b11888388bea4341d6f4630410738d4bb1ac62818b05930acaa4b471454365fd8a4ab7ae9d9f50022fabefa72d1f713e063b0ec102	{"url":"payto://x-taler-bank/localhost/42","salt":"6XZMT4EBZ9R4N02DY0X3VZGJ2ZEYAWTYWG3WJ5KN7ZDKVNJZQ4P2WKYPSAMZNMBJZK04K0PE19VDXE6N39ASE4W349R6NMRF905MSR0"}	f	f
3	\\xf88324ad92eb8843521cd1e0c1c7a25c9b9c0039f97fd0c697e8f9439e015e90	0	10000000	1577746824000000	1577747724000000	1577747724000000	\\xf72f8edf0baf3ce18d8d78e488612b4bafa12f24f1fb5cd87e2fa8b6d86ccc9a	\\x8ae8b73edabbb8276bfa368643bedb7d673ecac61d1ecb1f620b29fcd183830ec12b70d53ba89b75c6e9ba4a249cefa2c25027263e8e4a31bbbdb12574e7b569	\\x0375f5618be0f06c0c26a3fee852b6015a274a3744ab7a69cb0d79be471d4c3886d68d8bd107902c5cfdac5abe27bf216c92980e5aad9cea30ac659056889244	\\x6f5321c97ebf742b089b7d2fe44fc2ff40186dc1c84890796025a3447fc01123193888aa357f664c4f338468a8ded8d6ff6e900f12ec511a1602a7e28cb24603	{"url":"payto://x-taler-bank/localhost/42","salt":"6XZMT4EBZ9R4N02DY0X3VZGJ2ZEYAWTYWG3WJ5KN7ZDKVNJZQ4P2WKYPSAMZNMBJZK04K0PE19VDXE6N39ASE4W349R6NMRF905MSR0"}	f	f
4	\\x9bf66379c506850d81c732cdc85c9c4517578e33ac5effe8916c2e352ea19006	2	22000000	1577746824000000	1577747724000000	1577747724000000	\\xf72f8edf0baf3ce18d8d78e488612b4bafa12f24f1fb5cd87e2fa8b6d86ccc9a	\\x8ae8b73edabbb8276bfa368643bedb7d673ecac61d1ecb1f620b29fcd183830ec12b70d53ba89b75c6e9ba4a249cefa2c25027263e8e4a31bbbdb12574e7b569	\\x0375f5618be0f06c0c26a3fee852b6015a274a3744ab7a69cb0d79be471d4c3886d68d8bd107902c5cfdac5abe27bf216c92980e5aad9cea30ac659056889244	\\x2899afbd1f85375153c7bf9ea9b8268aa5bf3b99bc9173f63dc72e33ab785692432c298cd112439b04de3b2753b5aa22efae241b15e223420a3778cfea418d08	{"url":"payto://x-taler-bank/localhost/42","salt":"6XZMT4EBZ9R4N02DY0X3VZGJ2ZEYAWTYWG3WJ5KN7ZDKVNJZQ4P2WKYPSAMZNMBJZK04K0PE19VDXE6N39ASE4W349R6NMRF905MSR0"}	f	f
5	\\xf8212108f000488607aaf1a0fc87e988fafae664df2e9c11534d4fb9f910aa6b	0	10000000	1577746824000000	1577747724000000	1577747724000000	\\xf72f8edf0baf3ce18d8d78e488612b4bafa12f24f1fb5cd87e2fa8b6d86ccc9a	\\x8ae8b73edabbb8276bfa368643bedb7d673ecac61d1ecb1f620b29fcd183830ec12b70d53ba89b75c6e9ba4a249cefa2c25027263e8e4a31bbbdb12574e7b569	\\x0375f5618be0f06c0c26a3fee852b6015a274a3744ab7a69cb0d79be471d4c3886d68d8bd107902c5cfdac5abe27bf216c92980e5aad9cea30ac659056889244	\\x19066850fab4b89be577510d722a777cd1335fc85ffa089dd0ba28c47685c3ba170387df997609553e15cbac0c7290de17a7dcc1b1d4543728b59985de2a730b	{"url":"payto://x-taler-bank/localhost/42","salt":"6XZMT4EBZ9R4N02DY0X3VZGJ2ZEYAWTYWG3WJ5KN7ZDKVNJZQ4P2WKYPSAMZNMBJZK04K0PE19VDXE6N39ASE4W349R6NMRF905MSR0"}	f	f
6	\\x78e5e77da993198556de1fbb3b5ce31dda673fce143ce9e2401e37a79169a69a	1	0	1577746824000000	1577747724000000	1577747724000000	\\xf72f8edf0baf3ce18d8d78e488612b4bafa12f24f1fb5cd87e2fa8b6d86ccc9a	\\x8ae8b73edabbb8276bfa368643bedb7d673ecac61d1ecb1f620b29fcd183830ec12b70d53ba89b75c6e9ba4a249cefa2c25027263e8e4a31bbbdb12574e7b569	\\x0375f5618be0f06c0c26a3fee852b6015a274a3744ab7a69cb0d79be471d4c3886d68d8bd107902c5cfdac5abe27bf216c92980e5aad9cea30ac659056889244	\\x7dc5dffa46736d9a485457dd4e7f0876ebb595d8fc31a284de74523bdcc03272af5d4749dce271ec4e8c95c3d7e0e5d535c4923f912912692a559673bf90c804	{"url":"payto://x-taler-bank/localhost/42","salt":"6XZMT4EBZ9R4N02DY0X3VZGJ2ZEYAWTYWG3WJ5KN7ZDKVNJZQ4P2WKYPSAMZNMBJZK04K0PE19VDXE6N39ASE4W349R6NMRF905MSR0"}	f	f
7	\\x2062e9595d10e61629267f860449c8c3387b7ad51587aac29ad8e2513f2e958c	0	10000000	1577746824000000	1577747724000000	1577747724000000	\\xf72f8edf0baf3ce18d8d78e488612b4bafa12f24f1fb5cd87e2fa8b6d86ccc9a	\\x8ae8b73edabbb8276bfa368643bedb7d673ecac61d1ecb1f620b29fcd183830ec12b70d53ba89b75c6e9ba4a249cefa2c25027263e8e4a31bbbdb12574e7b569	\\x0375f5618be0f06c0c26a3fee852b6015a274a3744ab7a69cb0d79be471d4c3886d68d8bd107902c5cfdac5abe27bf216c92980e5aad9cea30ac659056889244	\\xf1cafb041b58a1224e56d77c8c8a9404b326613da2058e460ec1e9858744ddda26e5e0f2d687087299c3621a4459ef5539671fb4a665e82d51ad0b137cac2108	{"url":"payto://x-taler-bank/localhost/42","salt":"6XZMT4EBZ9R4N02DY0X3VZGJ2ZEYAWTYWG3WJ5KN7ZDKVNJZQ4P2WKYPSAMZNMBJZK04K0PE19VDXE6N39ASE4W349R6NMRF905MSR0"}	f	f
8	\\x3fba0b5cc29aee6ba218c9a5842be02a60b662dd2a3165d20d376fe1d0a947e3	0	10000000	1577746824000000	1577747724000000	1577747724000000	\\xf72f8edf0baf3ce18d8d78e488612b4bafa12f24f1fb5cd87e2fa8b6d86ccc9a	\\x8ae8b73edabbb8276bfa368643bedb7d673ecac61d1ecb1f620b29fcd183830ec12b70d53ba89b75c6e9ba4a249cefa2c25027263e8e4a31bbbdb12574e7b569	\\x0375f5618be0f06c0c26a3fee852b6015a274a3744ab7a69cb0d79be471d4c3886d68d8bd107902c5cfdac5abe27bf216c92980e5aad9cea30ac659056889244	\\xffe1f54d6c2ae35313b731984bcbd25c354dc064df4e60a36bfed3694612c368a1be8b0600c537cb17b86dc3ec1222a5d3008f02d2b693fc8c3290166f3d7403	{"url":"payto://x-taler-bank/localhost/42","salt":"6XZMT4EBZ9R4N02DY0X3VZGJ2ZEYAWTYWG3WJ5KN7ZDKVNJZQ4P2WKYPSAMZNMBJZK04K0PE19VDXE6N39ASE4W349R6NMRF905MSR0"}	f	f
9	\\x595039403882731095106c7cce626c4b58b5e82881d0d9aefe608b0df32cc44c	0	10000000	1577746824000000	1577747724000000	1577747724000000	\\xf72f8edf0baf3ce18d8d78e488612b4bafa12f24f1fb5cd87e2fa8b6d86ccc9a	\\x8ae8b73edabbb8276bfa368643bedb7d673ecac61d1ecb1f620b29fcd183830ec12b70d53ba89b75c6e9ba4a249cefa2c25027263e8e4a31bbbdb12574e7b569	\\x0375f5618be0f06c0c26a3fee852b6015a274a3744ab7a69cb0d79be471d4c3886d68d8bd107902c5cfdac5abe27bf216c92980e5aad9cea30ac659056889244	\\x25bc08844c67f313d3d0bc283f86b323b8f67ad130bf3bc46d24f426dd0676bfa64cfeb299f04a5e598c4bea65a99ddc1817eb059f4eeec9dd2f1bfb5a94e309	{"url":"payto://x-taler-bank/localhost/42","salt":"6XZMT4EBZ9R4N02DY0X3VZGJ2ZEYAWTYWG3WJ5KN7ZDKVNJZQ4P2WKYPSAMZNMBJZK04K0PE19VDXE6N39ASE4W349R6NMRF905MSR0"}	f	f
10	\\xd22eae9c01fa38d3a301e2641ef1a37fa676461b0514d3a26700f12f07b1121e	0	10000000	1577746824000000	1577747724000000	1577747724000000	\\xf72f8edf0baf3ce18d8d78e488612b4bafa12f24f1fb5cd87e2fa8b6d86ccc9a	\\x8ae8b73edabbb8276bfa368643bedb7d673ecac61d1ecb1f620b29fcd183830ec12b70d53ba89b75c6e9ba4a249cefa2c25027263e8e4a31bbbdb12574e7b569	\\x0375f5618be0f06c0c26a3fee852b6015a274a3744ab7a69cb0d79be471d4c3886d68d8bd107902c5cfdac5abe27bf216c92980e5aad9cea30ac659056889244	\\xa60877da75ff668268344ecd7bbf6bae98cd258e5f908a2691efef422aee22f4cc81a1d8e588644f981655490df12e7dac91b4ca84855baa3c429779fdaa550c	{"url":"payto://x-taler-bank/localhost/42","salt":"6XZMT4EBZ9R4N02DY0X3VZGJ2ZEYAWTYWG3WJ5KN7ZDKVNJZQ4P2WKYPSAMZNMBJZK04K0PE19VDXE6N39ASE4W349R6NMRF905MSR0"}	f	f
11	\\x364619793416e999dcf6df9c6a16d41387c8b05d59c6015812e09047709875a5	5	0	1577746827000000	1577747727000000	1577747727000000	\\xf72f8edf0baf3ce18d8d78e488612b4bafa12f24f1fb5cd87e2fa8b6d86ccc9a	\\x8cd2b92e8e6b7414be40bdb04ea2a0aa8ea16fb14050420957e4ca1d9acb7619f337d1c95d58d1964522b62a15c4db0be8fe0729acbee1031d948c9f3eef236d	\\x0375f5618be0f06c0c26a3fee852b6015a274a3744ab7a69cb0d79be471d4c3886d68d8bd107902c5cfdac5abe27bf216c92980e5aad9cea30ac659056889244	\\x7caa4003af16fd660a920442ac26035b64e22c48c7e1cc1de6c8923336375ce72916e4883a85481ed5430ae24d4ea024c39cc06b30d67ed3dd4eccdc4bb13a04	{"url":"payto://x-taler-bank/localhost/42","salt":"6XZMT4EBZ9R4N02DY0X3VZGJ2ZEYAWTYWG3WJ5KN7ZDKVNJZQ4P2WKYPSAMZNMBJZK04K0PE19VDXE6N39ASE4W349R6NMRF905MSR0"}	f	f
12	\\x4d39e16ad825c1d775a24864dfebf67b240d606a67391bd833dbc2a38d6fe8a5	2	0	1577746827000000	1577747727000000	1577747727000000	\\xf72f8edf0baf3ce18d8d78e488612b4bafa12f24f1fb5cd87e2fa8b6d86ccc9a	\\x8cd2b92e8e6b7414be40bdb04ea2a0aa8ea16fb14050420957e4ca1d9acb7619f337d1c95d58d1964522b62a15c4db0be8fe0729acbee1031d948c9f3eef236d	\\x0375f5618be0f06c0c26a3fee852b6015a274a3744ab7a69cb0d79be471d4c3886d68d8bd107902c5cfdac5abe27bf216c92980e5aad9cea30ac659056889244	\\x89f95db255ba8efc35b68af38b9a247b7d048b20ed08878f64db2b3103519257c71f9e7ba1af11ef523392ffa0edbfcb6ebd7dc927a6799e1878c6727c828f0c	{"url":"payto://x-taler-bank/localhost/42","salt":"6XZMT4EBZ9R4N02DY0X3VZGJ2ZEYAWTYWG3WJ5KN7ZDKVNJZQ4P2WKYPSAMZNMBJZK04K0PE19VDXE6N39ASE4W349R6NMRF905MSR0"}	f	f
13	\\x040cb96fb1886ccc75e018fe3f35eef94290e3888c2e6a9068a3e411b80c853d	3	0	1577746829000000	1577747729000000	1577747729000000	\\xf72f8edf0baf3ce18d8d78e488612b4bafa12f24f1fb5cd87e2fa8b6d86ccc9a	\\x3f9907dffc570ba7798931ba342ebfab1e6efc250462e5f3441546cd15daa68b2b83400c6471572420930fb62e0f80d8cb6676d020924fcd78bb4dc69d9ba132	\\x0375f5618be0f06c0c26a3fee852b6015a274a3744ab7a69cb0d79be471d4c3886d68d8bd107902c5cfdac5abe27bf216c92980e5aad9cea30ac659056889244	\\x13843f718cbde414728d2a4d561abd1d786a05b366a145c70747352651a0d62e7357b61a8ec90f6726caf293502bd4369d01f33d62473f3058ec87abf04a440b	{"url":"payto://x-taler-bank/localhost/42","salt":"6XZMT4EBZ9R4N02DY0X3VZGJ2ZEYAWTYWG3WJ5KN7ZDKVNJZQ4P2WKYPSAMZNMBJZK04K0PE19VDXE6N39ASE4W349R6NMRF905MSR0"}	f	f
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
1	contenttypes	0001_initial	2019-12-31 00:00:20.297407+01
2	auth	0001_initial	2019-12-31 00:00:20.321428+01
3	app	0001_initial	2019-12-31 00:00:20.361037+01
4	contenttypes	0002_remove_content_type_name	2019-12-31 00:00:20.381016+01
5	auth	0002_alter_permission_name_max_length	2019-12-31 00:00:20.384103+01
6	auth	0003_alter_user_email_max_length	2019-12-31 00:00:20.389675+01
7	auth	0004_alter_user_username_opts	2019-12-31 00:00:20.397096+01
8	auth	0005_alter_user_last_login_null	2019-12-31 00:00:20.404147+01
9	auth	0006_require_contenttypes_0002	2019-12-31 00:00:20.40568+01
10	auth	0007_alter_validators_add_error_messages	2019-12-31 00:00:20.411976+01
11	auth	0008_alter_user_username_max_length	2019-12-31 00:00:20.420352+01
12	auth	0009_alter_user_last_name_max_length	2019-12-31 00:00:20.427838+01
13	auth	0010_alter_group_name_max_length	2019-12-31 00:00:20.436133+01
14	auth	0011_update_proxy_permissions	2019-12-31 00:00:20.442185+01
15	sessions	0001_initial	2019-12-31 00:00:20.446627+01
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
\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1546297200000000	1577833200000000	\\xac8c4e3300ade839dbe2142a9d44834bda46999ec4a83b979215afe3bea7485ca4d4e30f09db0798c7c8e9644ff99b58fe3a4d4c08766112a24785011ea7d506
\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1577833200000000	1609455600000000	\\xc7271e3201d81087fa03031153e58ede16bc31af1636fa496c8cffa0ac91d484d88226f671addcc9b675c1545da85f3e46b8960c3eca2b5d770de9e75c226309
\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1609455600000000	1640991600000000	\\x1a8dd8c6b91a178f42c892711ee0ff9a0b702fc161bd2e6c445d959862f92926ed398c507373f32ccfe5b1e1d131d3650d696eb991fbd2ac414be1a82b4b700f
\\x063456a066ad1e3092fbfb738a77a7265d697d79ddf8f0ca0b9aa10610e37c91	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1640991600000000	1672527600000000	\\xf2f444a5f74095d1a9a0ef622a4adff09420ec22e45b5044cccd421e630cfb011a3e4dcbe28bc02a5c1d59ad30b0ae48b206392fdd290554951a1bd56f86ed00
\.


--
-- Data for Name: known_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.known_coins (coin_pub, denom_pub_hash, denom_sig) FROM stdin;
\\x2a69e656c642312357abdb1449bc6669c3f5a9fbff3dfb9b4d54817112e0e7ed	\\x401eabfce5c5cefe6b489e963f5c81d5b02004f76d5968869cb843acf0571bb0d396eb4914253f4a0c862955d7eff492d19c888376d324898d7795376e21950a	\\x41823aef7b955cd3044b2b5ec50534bfd4edecc2527392676c5e779fc66bb4aff8729ad67538d3b9ead2dcab49f35a4ee60222e67ce83ba39b7bd881da7a1c222d6bb4d210088d46d3353636b7ce959b058166af9a6a884efaa8577afb2f7a031339e5343217a1e1c9f1f526888db7c45804cf8878b803220ccb842d7e046d79
\\x6f35a9c394379cb7a93703cce5338a3a4a451fc8770f067da4c41fc1d9c35de5	\\x401eabfce5c5cefe6b489e963f5c81d5b02004f76d5968869cb843acf0571bb0d396eb4914253f4a0c862955d7eff492d19c888376d324898d7795376e21950a	\\x362538e0108583b5fa791de1a6a9a4b3b90dbb1f7939af719649c5d9695e2d1cf034f17a2a59fde6da484680f2b8ecb11e8710b6919a608e7b0851f5f66403734f0fcdec2c53ce7d3afdfe3afe163c595a176ed47f2ef61ad6fc112145a0b4503813df762dde86455fe6fea9fa88615f1797616a1978b923e0bd1b412710bb3f
\\x9bf66379c506850d81c732cdc85c9c4517578e33ac5effe8916c2e352ea19006	\\x6159cfc0e5a49ef2cdfdf6116f4fda2a8fafe91ccbb292a5c4e816fdc273a6aecf517155709d17d4e0e95d1c9ce413bb752bc192b9dd014f13e352f98d964d87	\\x8fae241c7e15db4a5f96ebab9863677b973286f65c36e08828eba08de5db38696238e0de207764e6a267c73caf1b02bda0e9f01bd6c0afde1760b3bef00680ec48ecd54417a490179e41c4dba19daf7cf1d1fbda0a8fbce1d061ff78164a7b2132e12e246690ddbce018afc2e54d933391535e5750573aa399aa117876426f0b
\\xf88324ad92eb8843521cd1e0c1c7a25c9b9c0039f97fd0c697e8f9439e015e90	\\x401eabfce5c5cefe6b489e963f5c81d5b02004f76d5968869cb843acf0571bb0d396eb4914253f4a0c862955d7eff492d19c888376d324898d7795376e21950a	\\x8a2df00dd8c31a5333ffece7faccd249be7402a5ff203a10d1784b6242d786220e447932487d9b66a0e8098229698c9e972d1d81fff631f4da01a88aeec8e593cb9d41b754135a8af278f94d936584983502c9d1742ac449b7427ce416679d3ebebc2c86c8a838a2c9eda34836ba79b949d9512e0596c6b6ffa32a5c90c23a74
\\xf8212108f000488607aaf1a0fc87e988fafae664df2e9c11534d4fb9f910aa6b	\\x401eabfce5c5cefe6b489e963f5c81d5b02004f76d5968869cb843acf0571bb0d396eb4914253f4a0c862955d7eff492d19c888376d324898d7795376e21950a	\\xc4efe8dcfe8237c0a4d0512029754fa03fda4703772316c4e4f0e45cdbc06a233fe8d90cd53c61c42432457737ec70274f4789f35dbfa84dbb2c682da5245fb01fc53f99fc1a019dc33efad03ad55cf95c6fe18b3993ef92467afd5a983ece9e2e8542e38c4b96464912f1d32ed751f3883431230c6b7c611946cf481c77a8c1
\\x78e5e77da993198556de1fbb3b5ce31dda673fce143ce9e2401e37a79169a69a	\\x1b3e0100937fd48380574273ecb350f8b2f4b945b8944153a7d5be8467a144bc87ce33d2528b7b2b1a129e10b98ac7e48a79db395c9beffad08fa835619daf1f	\\x303d18371589311c8b70e4e5e8632ca1485c053d514e5e47c5b9143a7daf97fcdb8b5dd75a046ac7d630f3a4810b976d12d717d442e3b6d17d6560d93f8fc21d72bfb9d18a17a08a47d182cf84db37386926824dd548d6c67382ff3104a75e5036a16b79a33db63665b38e7a777a05cdc8b47b2ce2d7eb2a09a5d15f57e037a3
\\x2062e9595d10e61629267f860449c8c3387b7ad51587aac29ad8e2513f2e958c	\\x401eabfce5c5cefe6b489e963f5c81d5b02004f76d5968869cb843acf0571bb0d396eb4914253f4a0c862955d7eff492d19c888376d324898d7795376e21950a	\\x8ec5fff9aba5e03af0ed62241e5f50f542d394986bcf961c538994a97c184d05c9857bf3277933366bfb3eb4dc3593c026ca09d004814d9f94baade9863b97c2b840b5e5f5b4ff6333f943bda064b6991d46f814fc53917bf52eaaf5f1808a45214736e22cbd115a216ea02e1572b946b54c5c8625d567782f865d9514f5bdf3
\\x595039403882731095106c7cce626c4b58b5e82881d0d9aefe608b0df32cc44c	\\x401eabfce5c5cefe6b489e963f5c81d5b02004f76d5968869cb843acf0571bb0d396eb4914253f4a0c862955d7eff492d19c888376d324898d7795376e21950a	\\x8256d4a5c0078a256ba13544fcc57ce6c2e0efa190116c834d7efedaffc1dec57d549a6ac183b3673a54838d2cd6552a8357ac60d71755ffc58c821838d92b83e24e53dc549e37143301be7c4a3d2eeb13cda149ed6b48b408a9c3845251d5f0da587dbeb2de0ced0a200c41065e26db9bc5d5af97c59eb0b8b79b829ff5bd6c
\\x3fba0b5cc29aee6ba218c9a5842be02a60b662dd2a3165d20d376fe1d0a947e3	\\x401eabfce5c5cefe6b489e963f5c81d5b02004f76d5968869cb843acf0571bb0d396eb4914253f4a0c862955d7eff492d19c888376d324898d7795376e21950a	\\x3eb6e0cd75ee8a6f29d06022921207c0d4605d8bc4fa3be6177f596e308679c62c053f73bb245013787a164db51bccd3377281c1937c08932872a61bb2f0911440cdc1a12dc4275fa0b61f9be1518efdf1dd198769fab40cd9ec2f485515b2efc9b6c26ebd7792fad3c26a60f30bdf45e7ef86bcd440d5cf2d1178989eba89b6
\\xd22eae9c01fa38d3a301e2641ef1a37fa676461b0514d3a26700f12f07b1121e	\\x401eabfce5c5cefe6b489e963f5c81d5b02004f76d5968869cb843acf0571bb0d396eb4914253f4a0c862955d7eff492d19c888376d324898d7795376e21950a	\\xc9eb4f64242ee4ff3789d44858feb47d73eddcf73c699a15906e9a8b54a018933172c681a6eeb4b49df64efb82dd18a846905ac483b6d5fba1d2de2fc64580ba894dc816406bd5bc1f291ed05d4864fdbec384470cb81f3563274aa65adfb7ab76b30d6acea8cd0cf551bfefe141802d11a06bfe23d8326c8fd1c312a6575b61
\\x364619793416e999dcf6df9c6a16d41387c8b05d59c6015812e09047709875a5	\\xd8d7b08143f2844fca7a7c745a5c43a91945f2f42166ac2eada3e89009dcc661c80942d0d9bf8b0f0b560feb511612c8e4dd3060e9ad9aa6d513ac1f1bd56f84	\\x49803b30c4b4aba2d99b393ea602871f69535a0ad9d3636a03505a09255b5248d80689caaf15926239c6ef6467b578276e9e2b7a71af436518af56dc3546ee64002d3b154840a77a00c222a19caa946674c3ebae4204f664c9636d62845e599cd8ee91f14b508371e2d2ee381f7ae29ad6be4a2c8117b5f846fb41c82d82d5dc
\\x4d39e16ad825c1d775a24864dfebf67b240d606a67391bd833dbc2a38d6fe8a5	\\xd8d7b08143f2844fca7a7c745a5c43a91945f2f42166ac2eada3e89009dcc661c80942d0d9bf8b0f0b560feb511612c8e4dd3060e9ad9aa6d513ac1f1bd56f84	\\x5b0706472ea3995a6a44161e45b2e07499b28eebd7d3a672676a4fb2386efe2f3230df6e15e3ebc79dda06fa4a7135f74f0eb06d891636969a1b259003e7863d3b5fbebfd29ae2ecbc99199131dfe498b60055a0935c46688a9e39fe85b88cb97b5fde41672a9f04842d51ac4046f259d836f1c3b1aa3a40e7f1febdd3a161c2
\\x040cb96fb1886ccc75e018fe3f35eef94290e3888c2e6a9068a3e411b80c853d	\\x7c18bf9b242fd7fce4ad8674f33d3aa506090231cb9afe6e775c7b587620943eb170eb90203b4d2c7c9ed6035cd0ca26b36242fcee0656a3c89934c89ef3f89f	\\x6c8e0e24f87851b11e875bec87b5ca97c8a09aaaa16b8abfb3b68b3e242b22a2cd7130676696af5b14703ebdcb3dad3f620efd58abbe066657a7d024c8a46abb436c80588cc437492870de5fd1f89f8ad6e5912edada571fec3e37cc6915fffb01d9c96c941dc8b6c36b55f492f39ac543153488072a7cced79dc1ea191574f0
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_id, merchant_pub, contract_terms, h_contract_terms, "timestamp", row_id, paid) FROM stdin;
2019.365-01M65M9B6ARYG	\\xf72f8edf0baf3ce18d8d78e488612b4bafa12f24f1fb5cd87e2fa8b6d86ccc9a	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313537373734373732343030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313537373734373732343030307d2c226f726465725f6964223a22323031392e3336352d30314d36354d39423641525947222c2274696d657374616d70223a7b22745f6d73223a313537373734363832343030307d2c227061795f646561646c696e65223a7b22745f6d73223a313537373833333232343030307d2c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2230525435443833364e4d4633313451565a4453524d585837345345504a5a425356515746314a47424b41474743343733464a3847227d5d2c2261756469746f7273223a5b5d2c22685f77697265223a223044545a4152434257335236523331364d465a45474d4e5030354432454a4851384a4e514d544542314e57565748525839475738444e4d444846384746343143424b595452504e5934595a4a3256344a4b3037354e424357583852415253434741543439344830222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a2259575152585152424e5759453333434446334a384752394239455154324253345937584e5350335935594d4244503343534a4430222c226e6f6e6365223a22514d3139484854574e43503953575642484e575a32484e37594b384557314d453439533444584645484548544243385743545747227d	\\x8ae8b73edabbb8276bfa368643bedb7d673ecac61d1ecb1f620b29fcd183830ec12b70d53ba89b75c6e9ba4a249cefa2c25027263e8e4a31bbbdb12574e7b569	1577746824000000	1	t
2019.365-0004Y3QXG4KRE	\\xf72f8edf0baf3ce18d8d78e488612b4bafa12f24f1fb5cd87e2fa8b6d86ccc9a	\\x7b22616d6f756e74223a22544553544b55444f533a37222c2273756d6d617279223a226f7264657220746861742077696c6c20626520726566756e646564222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313537373734373732373030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313537373734373732373030307d2c226f726465725f6964223a22323031392e3336352d303030345933515847344b5245222c2274696d657374616d70223a7b22745f6d73223a313537373734363832373030307d2c227061795f646561646c696e65223a7b22745f6d73223a313537373833333232373030307d2c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2230525435443833364e4d4633313451565a4453524d585837345345504a5a425356515746314a47424b41474743343733464a3847227d5d2c2261756469746f7273223a5b5d2c22685f77697265223a223044545a4152434257335236523331364d465a45474d4e5030354432454a4851384a4e514d544542314e57565748525839475738444e4d444846384746343143424b595452504e5934595a4a3256344a4b3037354e424357583852415253434741543439344830222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a2259575152585152424e5759453333434446334a384752394239455154324253345937584e5350335935594d4244503343534a4430222c226e6f6e6365223a22384843315353304735504353534d413744545a4a3945385031434139384a383845544d4a3048465156364a584843583351303347227d	\\x8cd2b92e8e6b7414be40bdb04ea2a0aa8ea16fb14050420957e4ca1d9acb7619f337d1c95d58d1964522b62a15c4db0be8fe0729acbee1031d948c9f3eef236d	1577746827000000	2	t
2019.365-02887E03RX0XR	\\xf72f8edf0baf3ce18d8d78e488612b4bafa12f24f1fb5cd87e2fa8b6d86ccc9a	\\x7b22616d6f756e74223a22544553544b55444f533a33222c2273756d6d617279223a227061796d656e7420616674657220726566756e64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313537373734373732393030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313537373734373732393030307d2c226f726465725f6964223a22323031392e3336352d30323838374530335258305852222c2274696d657374616d70223a7b22745f6d73223a313537373734363832393030307d2c227061795f646561646c696e65223a7b22745f6d73223a313537373833333232393030307d2c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2230525435443833364e4d4633313451565a4453524d585837345345504a5a425356515746314a47424b41474743343733464a3847227d5d2c2261756469746f7273223a5b5d2c22685f77697265223a223044545a4152434257335236523331364d465a45474d4e5030354432454a4851384a4e514d544542314e57565748525839475738444e4d444846384746343143424b595452504e5934595a4a3256344a4b3037354e424357583852415253434741543439344830222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a2259575152585152424e5759453333434446334a384752394239455154324253345937584e5350335935594d4244503343534a4430222c226e6f6e6365223a2254584b334b58324b38305838544659484e454532465339594d5834453241514e4b5033455246374b505738514236535459504330227d	\\x3f9907dffc570ba7798931ba342ebfab1e6efc250462e5f3441546cd15daa68b2b83400c6471572420930fb62e0f80d8cb6676d020924fcd78bb4dc69d9ba132	1577746829000000	3	t
\.


--
-- Data for Name: merchant_deposits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_deposits (h_contract_terms, merchant_pub, coin_pub, exchange_url, amount_with_fee_val, amount_with_fee_frac, deposit_fee_val, deposit_fee_frac, refund_fee_val, refund_fee_frac, wire_fee_val, wire_fee_frac, signkey_pub, exchange_proof) FROM stdin;
\\x8ae8b73edabbb8276bfa368643bedb7d673ecac61d1ecb1f620b29fcd183830ec12b70d53ba89b75c6e9ba4a249cefa2c25027263e8e4a31bbbdb12574e7b569	\\xf72f8edf0baf3ce18d8d78e488612b4bafa12f24f1fb5cd87e2fa8b6d86ccc9a	\\x6f35a9c394379cb7a93703cce5338a3a4a451fc8770f067da4c41fc1d9c35de5	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x0e19c3e0b1a4f874fcdb0948f273361f6068be0cf8c34a63c049a38c5a05dfc0	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22334d543646473032385453564e32374338575744514e334738524247454b5a4556583158505030505354424a544b5957314735433243325637314e35594b57365a5a4538564d5857324131484d5835544a484b484e3948375a4b5a314741344236415148453047222c22707562223a2231524357375235484d4b5737395a3656313534463457535033584736484647435a33314d4d5259303936485252504735565a3030227d
\\x8ae8b73edabbb8276bfa368643bedb7d673ecac61d1ecb1f620b29fcd183830ec12b70d53ba89b75c6e9ba4a249cefa2c25027263e8e4a31bbbdb12574e7b569	\\xf72f8edf0baf3ce18d8d78e488612b4bafa12f24f1fb5cd87e2fa8b6d86ccc9a	\\x2062e9595d10e61629267f860449c8c3387b7ad51587aac29ad8e2513f2e958c	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x0e19c3e0b1a4f874fcdb0948f273361f6068be0cf8c34a63c049a38c5a05dfc0	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22413137304b324542314537343539384358594e36394e42584e4e4a57374d31414e57453356463230413954324a4d5a413933384a463648373352505457523158464b52584139584e4333383441343353314d314b31575a424a58333444425244474b3559433052222c22707562223a2231524357375235484d4b5737395a3656313534463457535033584736484647435a33314d4d5259303936485252504735565a3030227d
\\x8ae8b73edabbb8276bfa368643bedb7d673ecac61d1ecb1f620b29fcd183830ec12b70d53ba89b75c6e9ba4a249cefa2c25027263e8e4a31bbbdb12574e7b569	\\xf72f8edf0baf3ce18d8d78e488612b4bafa12f24f1fb5cd87e2fa8b6d86ccc9a	\\x2a69e656c642312357abdb1449bc6669c3f5a9fbff3dfb9b4d54817112e0e7ed	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x0e19c3e0b1a4f874fcdb0948f273361f6068be0cf8c34a63c049a38c5a05dfc0	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22455132364146504e434d46594e34545a57575742335952594b3857484b374b514a335833304d5158583458513434474a3731465632525256584a35544d5446465a52525854465a3154393353344251305a50365436443348373358574b485a5453583648523330222c22707562223a2231524357375235484d4b5737395a3656313534463457535033584736484647435a33314d4d5259303936485252504735565a3030227d
\\x8ae8b73edabbb8276bfa368643bedb7d673ecac61d1ecb1f620b29fcd183830ec12b70d53ba89b75c6e9ba4a249cefa2c25027263e8e4a31bbbdb12574e7b569	\\xf72f8edf0baf3ce18d8d78e488612b4bafa12f24f1fb5cd87e2fa8b6d86ccc9a	\\x3fba0b5cc29aee6ba218c9a5842be02a60b662dd2a3165d20d376fe1d0a947e3	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x0e19c3e0b1a4f874fcdb0948f273361f6068be0cf8c34a63c049a38c5a05dfc0	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a224d42545647363254454d304641595a304758505237374e4859565a5a33393645544738384a35334432473654514b335a423551515a4e543531394a4d35483847545950373337544d524a3431423954454648464230584558324d57304830315a4b484530433147222c22707562223a2231524357375235484d4b5737395a3656313534463457535033584736484647435a33314d4d5259303936485252504735565a3030227d
\\x8ae8b73edabbb8276bfa368643bedb7d673ecac61d1ecb1f620b29fcd183830ec12b70d53ba89b75c6e9ba4a249cefa2c25027263e8e4a31bbbdb12574e7b569	\\xf72f8edf0baf3ce18d8d78e488612b4bafa12f24f1fb5cd87e2fa8b6d86ccc9a	\\x595039403882731095106c7cce626c4b58b5e82881d0d9aefe608b0df32cc44c	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x0e19c3e0b1a4f874fcdb0948f273361f6068be0cf8c34a63c049a38c5a05dfc0	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22305239375458335a463141364b4d42434546374a44564335524244365254534d315a46474739464a434753354437314b42324452385a424643394443593543545659594e59384b33454b475945454b525934394258463841455a435a4b5845464a4e4e36323147222c22707562223a2231524357375235484d4b5737395a3656313534463457535033584736484647435a33314d4d5259303936485252504735565a3030227d
\\x8ae8b73edabbb8276bfa368643bedb7d673ecac61d1ecb1f620b29fcd183830ec12b70d53ba89b75c6e9ba4a249cefa2c25027263e8e4a31bbbdb12574e7b569	\\xf72f8edf0baf3ce18d8d78e488612b4bafa12f24f1fb5cd87e2fa8b6d86ccc9a	\\xd22eae9c01fa38d3a301e2641ef1a37fa676461b0514d3a26700f12f07b1121e	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x0e19c3e0b1a4f874fcdb0948f273361f6068be0cf8c34a63c049a38c5a05dfc0	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2257334b58454e5041363250324d4233465647413147324b4d47464750414559415732445231455a4450535130535646535752523733434e364a3732565343424e323631485332425746585742433752364a31475042534a3430425a385830364a38485659523030222c22707562223a2231524357375235484d4b5737395a3656313534463457535033584736484647435a33314d4d5259303936485252504735565a3030227d
\\x8ae8b73edabbb8276bfa368643bedb7d673ecac61d1ecb1f620b29fcd183830ec12b70d53ba89b75c6e9ba4a249cefa2c25027263e8e4a31bbbdb12574e7b569	\\xf72f8edf0baf3ce18d8d78e488612b4bafa12f24f1fb5cd87e2fa8b6d86ccc9a	\\xf8212108f000488607aaf1a0fc87e988fafae664df2e9c11534d4fb9f910aa6b	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x0e19c3e0b1a4f874fcdb0948f273361f6068be0cf8c34a63c049a38c5a05dfc0	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2259474751364239324641425736324b4e5644353534374d39434245315a31545136453057564e364845544b485954545053455054414a58325252544751423856585238334e304134594453434d4d36444457485752524530523558565656583159454a59543038222c22707562223a2231524357375235484d4b5737395a3656313534463457535033584736484647435a33314d4d5259303936485252504735565a3030227d
\\x8ae8b73edabbb8276bfa368643bedb7d673ecac61d1ecb1f620b29fcd183830ec12b70d53ba89b75c6e9ba4a249cefa2c25027263e8e4a31bbbdb12574e7b569	\\xf72f8edf0baf3ce18d8d78e488612b4bafa12f24f1fb5cd87e2fa8b6d86ccc9a	\\xf88324ad92eb8843521cd1e0c1c7a25c9b9c0039f97fd0c697e8f9439e015e90	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x0e19c3e0b1a4f874fcdb0948f273361f6068be0cf8c34a63c049a38c5a05dfc0	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22344e3954353133414b5237334d4357523854465853444432464334304637513354374d4337535a343433374a433547323544485a3431513837565159465146563833434e473857325150524a4e4d53514d3234364e475a3750394751474a5954534b3957453330222c22707562223a2231524357375235484d4b5737395a3656313534463457535033584736484647435a33314d4d5259303936485252504735565a3030227d
\\x8ae8b73edabbb8276bfa368643bedb7d673ecac61d1ecb1f620b29fcd183830ec12b70d53ba89b75c6e9ba4a249cefa2c25027263e8e4a31bbbdb12574e7b569	\\xf72f8edf0baf3ce18d8d78e488612b4bafa12f24f1fb5cd87e2fa8b6d86ccc9a	\\x78e5e77da993198556de1fbb3b5ce31dda673fce143ce9e2401e37a79169a69a	http://localhost:8081/	1	0	0	2000000	0	1000000	0	1000000	\\x0e19c3e0b1a4f874fcdb0948f273361f6068be0cf8c34a63c049a38c5a05dfc0	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a224a41324a4d4d4e453736354853423830374343394330313741585843595633445838575156354d54584b5047445244443130484d4754443253453148344e57324534595836384a323156564e3133414e4452454d535a534e56324e385748514a44414e45523338222c22707562223a2231524357375235484d4b5737395a3656313534463457535033584736484647435a33314d4d5259303936485252504735565a3030227d
\\x8ae8b73edabbb8276bfa368643bedb7d673ecac61d1ecb1f620b29fcd183830ec12b70d53ba89b75c6e9ba4a249cefa2c25027263e8e4a31bbbdb12574e7b569	\\xf72f8edf0baf3ce18d8d78e488612b4bafa12f24f1fb5cd87e2fa8b6d86ccc9a	\\x9bf66379c506850d81c732cdc85c9c4517578e33ac5effe8916c2e352ea19006	http://localhost:8081/	2	22000000	0	2000000	0	4000000	0	1000000	\\x0e19c3e0b1a4f874fcdb0948f273361f6068be0cf8c34a63c049a38c5a05dfc0	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a224439435a415a57594e564d533635434e324e4244445846424e4648424b583839475a4246514531594b515a42505742595656504452344a59444e4d56354d51434d434e565937564a37335156423530454a34444d56425341343432384245484859345a57473152222c22707562223a2231524357375235484d4b5737395a3656313534463457535033584736484647435a33314d4d5259303936485252504735565a3030227d
\\x8cd2b92e8e6b7414be40bdb04ea2a0aa8ea16fb14050420957e4ca1d9acb7619f337d1c95d58d1964522b62a15c4db0be8fe0729acbee1031d948c9f3eef236d	\\xf72f8edf0baf3ce18d8d78e488612b4bafa12f24f1fb5cd87e2fa8b6d86ccc9a	\\x364619793416e999dcf6df9c6a16d41387c8b05d59c6015812e09047709875a5	http://localhost:8081/	5	0	0	1000000	0	1000000	0	1000000	\\x0e19c3e0b1a4f874fcdb0948f273361f6068be0cf8c34a63c049a38c5a05dfc0	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22304e50485751304756563547425a4839434e325857524e3641475a5a30514d52363144414338303246585253384e54364548474530454b453759563553363739463732414a5056575238304e574e364b523938344a3347514550564e354e374e414b4644503230222c22707562223a2231524357375235484d4b5737395a3656313534463457535033584736484647435a33314d4d5259303936485252504735565a3030227d
\\x8cd2b92e8e6b7414be40bdb04ea2a0aa8ea16fb14050420957e4ca1d9acb7619f337d1c95d58d1964522b62a15c4db0be8fe0729acbee1031d948c9f3eef236d	\\xf72f8edf0baf3ce18d8d78e488612b4bafa12f24f1fb5cd87e2fa8b6d86ccc9a	\\x4d39e16ad825c1d775a24864dfebf67b240d606a67391bd833dbc2a38d6fe8a5	http://localhost:8081/	2	0	0	1000000	0	1000000	0	1000000	\\x0e19c3e0b1a4f874fcdb0948f273361f6068be0cf8c34a63c049a38c5a05dfc0	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22444e4158513558414758344551595a36514a47513054323336463547304636305137453846415131314a505a595a434d5447534e4b594b41484b5145443544544844384a443653455834424d5736564b32594a543441584352394e524e37304430335446303052222c22707562223a2231524357375235484d4b5737395a3656313534463457535033584736484647435a33314d4d5259303936485252504735565a3030227d
\\x3f9907dffc570ba7798931ba342ebfab1e6efc250462e5f3441546cd15daa68b2b83400c6471572420930fb62e0f80d8cb6676d020924fcd78bb4dc69d9ba132	\\xf72f8edf0baf3ce18d8d78e488612b4bafa12f24f1fb5cd87e2fa8b6d86ccc9a	\\x040cb96fb1886ccc75e018fe3f35eef94290e3888c2e6a9068a3e411b80c853d	http://localhost:8081/	3	0	0	1000000	0	1000000	0	1000000	\\x0e19c3e0b1a4f874fcdb0948f273361f6068be0cf8c34a63c049a38c5a05dfc0	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22434e48334d515858374a5333565158423936444a3938474d32433937395451573852444150464738434b4d4d413046395046384445434b4d45463847515332455335304139385356454538304e4447455042484645393948445a4b48354a303548504e464d3038222c22707562223a2231524357375235484d4b5737395a3656313534463457535033584736484647435a33314d4d5259303936485252504735565a3030227d
\.


--
-- Data for Name: merchant_orders; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_orders (order_id, merchant_pub, contract_terms, "timestamp") FROM stdin;
2019.365-01M65M9B6ARYG	\\xf72f8edf0baf3ce18d8d78e488612b4bafa12f24f1fb5cd87e2fa8b6d86ccc9a	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313537373734373732343030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313537373734373732343030307d2c226f726465725f6964223a22323031392e3336352d30314d36354d39423641525947222c2274696d657374616d70223a7b22745f6d73223a313537373734363832343030307d2c227061795f646561646c696e65223a7b22745f6d73223a313537373833333232343030307d2c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2230525435443833364e4d4633313451565a4453524d585837345345504a5a425356515746314a47424b41474743343733464a3847227d5d2c2261756469746f7273223a5b5d2c22685f77697265223a223044545a4152434257335236523331364d465a45474d4e5030354432454a4851384a4e514d544542314e57565748525839475738444e4d444846384746343143424b595452504e5934595a4a3256344a4b3037354e424357583852415253434741543439344830222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a2259575152585152424e5759453333434446334a384752394239455154324253345937584e5350335935594d4244503343534a4430227d	1577746824000000
2019.365-0004Y3QXG4KRE	\\xf72f8edf0baf3ce18d8d78e488612b4bafa12f24f1fb5cd87e2fa8b6d86ccc9a	\\x7b22616d6f756e74223a22544553544b55444f533a37222c2273756d6d617279223a226f7264657220746861742077696c6c20626520726566756e646564222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313537373734373732373030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313537373734373732373030307d2c226f726465725f6964223a22323031392e3336352d303030345933515847344b5245222c2274696d657374616d70223a7b22745f6d73223a313537373734363832373030307d2c227061795f646561646c696e65223a7b22745f6d73223a313537373833333232373030307d2c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2230525435443833364e4d4633313451565a4453524d585837345345504a5a425356515746314a47424b41474743343733464a3847227d5d2c2261756469746f7273223a5b5d2c22685f77697265223a223044545a4152434257335236523331364d465a45474d4e5030354432454a4851384a4e514d544542314e57565748525839475738444e4d444846384746343143424b595452504e5934595a4a3256344a4b3037354e424357583852415253434741543439344830222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a2259575152585152424e5759453333434446334a384752394239455154324253345937584e5350335935594d4244503343534a4430227d	1577746827000000
2019.365-02887E03RX0XR	\\xf72f8edf0baf3ce18d8d78e488612b4bafa12f24f1fb5cd87e2fa8b6d86ccc9a	\\x7b22616d6f756e74223a22544553544b55444f533a33222c2273756d6d617279223a227061796d656e7420616674657220726566756e64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313537373734373732393030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313537373734373732393030307d2c226f726465725f6964223a22323031392e3336352d30323838374530335258305852222c2274696d657374616d70223a7b22745f6d73223a313537373734363832393030307d2c227061795f646561646c696e65223a7b22745f6d73223a313537373833333232393030307d2c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2230525435443833364e4d4633313451565a4453524d585837345345504a5a425356515746314a47424b41474743343733464a3847227d5d2c2261756469746f7273223a5b5d2c22685f77697265223a223044545a4152434257335236523331364d465a45474d4e5030354432454a4851384a4e514d544542314e57565748525839475738444e4d444846384746343143424b595452504e5934595a4a3256344a4b3037354e424357583852415253434741543439344830222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a2259575152585152424e5759453333434446334a384752394239455154324253345937584e5350335935594d4244503343534a4430227d	1577746829000000
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
1	\\xf72f8edf0baf3ce18d8d78e488612b4bafa12f24f1fb5cd87e2fa8b6d86ccc9a	\\x8cd2b92e8e6b7414be40bdb04ea2a0aa8ea16fb14050420957e4ca1d9acb7619f337d1c95d58d1964522b62a15c4db0be8fe0729acbee1031d948c9f3eef236d	\\x364619793416e999dcf6df9c6a16d41387c8b05d59c6015812e09047709875a5	test refund	5	0	0	1000000
2	\\xf72f8edf0baf3ce18d8d78e488612b4bafa12f24f1fb5cd87e2fa8b6d86ccc9a	\\x8cd2b92e8e6b7414be40bdb04ea2a0aa8ea16fb14050420957e4ca1d9acb7619f337d1c95d58d1964522b62a15c4db0be8fe0729acbee1031d948c9f3eef236d	\\x4d39e16ad825c1d775a24864dfebf67b240d606a67391bd833dbc2a38d6fe8a5	test refund	1	0	0	1000000
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
1	\\xb14898b2f3f8dcf3df86fae9049c1992658ac3bacf5569d7a7e2d6cfed9d1abd950a748f8f72543de5aff56d0ca59f6ceb1c779a6c6bdb5f64a5332405c73f82	\\x9bf66379c506850d81c732cdc85c9c4517578e33ac5effe8916c2e352ea19006	\\xe9189c3363db44fdc9231093e31dda7d78385586ef8edf29ea8191693468e4f31cf0612d7acd1923601d15e632c7da86e5122e77edd88c1578eb93ade0311f00	5	78000000	1
2	\\xfb4bf584bbb78084c9ea469a5d8e0069e90041b66a06ddcd1eab78ad6163402a1978753b3cdd911e5b95e1fd72273ed9fd0b8f6301f09aab6303093cda40e749	\\x4d39e16ad825c1d775a24864dfebf67b240d606a67391bd833dbc2a38d6fe8a5	\\xd3ca432ccd01e38d290495d93dd11a831158a84251cca9c53c5e177777f5a4e302a9a4b85c313dfb3269d52f6e09233b26018ee209ed7cb6ba9b9b1b4ef1bf0d	3	0	2
3	\\x8661ac5eaf06e45f16446825d8299b52bdf1bc37fae457e114b483a4bcf4963d78d472df5d2ba4ff422350c0a5c45616b73709263de7bde4a2dae319e43d096a	\\x364619793416e999dcf6df9c6a16d41387c8b05d59c6015812e09047709875a5	\\xe17cea6adcadddefc9b95ea7837a23aadc67783400ec23eb2bf7dfac00d67b2ed39f038f52cb6198754309f76ec7ae1bb81e3057fd7d2e0c4fdeb134f4677d07	4	98000000	1
4	\\x0f578b3844d553d6e49f0129f33da63be21a21b29f2d21f59ee0ee875b5afc176836afbd1bbaa507b10c5e996cb23109f69b5f034d9f9d43a379590da556e077	\\x4d39e16ad825c1d775a24864dfebf67b240d606a67391bd833dbc2a38d6fe8a5	\\xaf37c2b4ba7db099623ae81d914be55603bf69a14ffe103f729651d398b9e3a599fe77a6a54c4af26b431fee7bde3d09c4944c57c641f2be4b2dd582a5c5ba01	0	99000000	2
5	\\x4ce199a576380def2457174f34d25b4e357663d951c95a4af6d3ea34a144b4e06f16c215d99cda85ee374b6b5056e40edbb2faf607ec2bee7b668bb9e502d64c	\\x040cb96fb1886ccc75e018fe3f35eef94290e3888c2e6a9068a3e411b80c853d	\\x218b84521d366b7b6752fe9fc07914a5d9100978008da7e2e882a772094249594e6ce89264726e5187269c51e9e26d245de8788288e58d5186bc69a2c7319c06	7	0	1
\.


--
-- Data for Name: refresh_revealed_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins (rc, newcoin_index, link_sig, denom_pub_hash, coin_ev, h_coin_ev, ev_sig) FROM stdin;
\\xb14898b2f3f8dcf3df86fae9049c1992658ac3bacf5569d7a7e2d6cfed9d1abd950a748f8f72543de5aff56d0ca59f6ceb1c779a6c6bdb5f64a5332405c73f82	0	\\xcf825cbd8e6a6dd524ab1c9cfb4dcb422b2946f5e7e20a6668568198e0395006308be7ea8909d2b02031e55d824214b369ba69abf9fcd260e69893413e16570f	\\xd8d7b08143f2844fca7a7c745a5c43a91945f2f42166ac2eada3e89009dcc661c80942d0d9bf8b0f0b560feb511612c8e4dd3060e9ad9aa6d513ac1f1bd56f84	\\x30d083b9d85e58cdfa9420557e5bff31421a8c8b6ecc394c569f54d8944d2d0c74d2fa5fe615cccee0a49f1727bede73f88bb4e8ca070da858225db8a516034e7b40d891da9bcf909789c26fd6bc6b6cb341c817d6ee56986a5d71c3f5f311bea4af7cea27b4dfce0b243e2463f72d24940960c2a1cab022c3b9cc6fe7e6ff8e	\\x0227fd65cff0b1a9520d1a299a8482844e64b38383d51bbff9938b37b6d143a34a5b6cb174bcc9193282da1d16b8994c4e6a49079d15d55222dea85e9f2071ae	\\x750065e7f8d6b45ba2375d6d05253bd3aca9db88e887f12ecfdd6233afe6d7fc8d336477300c3eeec6d7b615b5c7142ccc366b035a7b60038738e1fb12304570507686e25efbd0cf5c2c64f50594d277f7979667764a527bdc67457c70fe97ea8014560f7f6344944d2d73dd77924f6fc5a93d3e14d19b70bc8c2c82035fd78a
\\xb14898b2f3f8dcf3df86fae9049c1992658ac3bacf5569d7a7e2d6cfed9d1abd950a748f8f72543de5aff56d0ca59f6ceb1c779a6c6bdb5f64a5332405c73f82	1	\\x98416cc6af2421a231b540f22c4cd2af70b7ebb0b566e2180134def7a3d6250fb5f364f154e34a686afabc417e9e737d45da99bf60ddf61cc47e62219ce28107	\\x401eabfce5c5cefe6b489e963f5c81d5b02004f76d5968869cb843acf0571bb0d396eb4914253f4a0c862955d7eff492d19c888376d324898d7795376e21950a	\\xe3a0f566f70f4938c2b3d75d8fb6a4ccc182a5c6af827fcbfe12279b0ae0bdc7504ae6defbbee494db371d8b14cb3e87cf4a1f6494533514030ba765a5550e9528b043b854c97fad9da54ab4422a48a8e9fa79eaf8825ee27406251718725fac34da4d090516da09a9a9c41a670ab8240ad6cc579e58be681562379b7d8a0181	\\xc0f0cc4e9402c876aa85f674ca0e6c448340f2b22154e1011cd10b658633a4e8a84364cedef13112da296209e564ec9e2c49d073d9df4c92d319308a19d134c4	\\xc07b513fb1b6dbdecf53b41a847654929912c78facc5580683af3e55eef856a942073f24747eb2c7234c5e513949f6d11b42b6971d7f05d4aade3d1ff49a6aa5bb6c8f7b93b6d35f0d5b30312a4d11c3eb21bc975176203cc463b3a591bd4f11b16e39db4c4560f023c9f6f10f0546b572751b6ec40df4eafbc6bd9845ac6580
\\xb14898b2f3f8dcf3df86fae9049c1992658ac3bacf5569d7a7e2d6cfed9d1abd950a748f8f72543de5aff56d0ca59f6ceb1c779a6c6bdb5f64a5332405c73f82	2	\\xe560c7b940686027ac546547a8e549a8c7d5dfeae6b00fbd084b50ec0acb2b64ab3fcf466e0835a48d0943a2055b1c5e7333243e62d6b4183ba14d4aec6c230e	\\x401eabfce5c5cefe6b489e963f5c81d5b02004f76d5968869cb843acf0571bb0d396eb4914253f4a0c862955d7eff492d19c888376d324898d7795376e21950a	\\x2236a62cc602c603411d464a46d305cf7117649c2a45cf1403cc2fe82f9afdf089c2df0808e01e8909da4e11bdbe480d97ed8fd861d18d533699396968f161ce31c9a35d809d4ef75a459abf9d049ee741692b09f7735060ecd598ec313d15e167b92072c4267c8eed9eaa5e205bc3cb45cbee3b5973212b0d73591cdc469664	\\xc33fda6f429662498614aa02d6ed041bb971b492c1e2716a6ae7f8d816184b4fc3e89e1e2416f366b4cbb704d5a200e49b0f816861c0c4da03e9a5734abacdef	\\xc2b142768b0fe5a648cdae71467482710d837e6e1fa94ae2b4ec0d364adfd87028b5f4e42bc4e670040355d3699f50fd957df4f91c3c3b73cec767a2d4554c836d94b0c86249e46fb8c382e4ded7deb5249dc3964017a398e57075922fea277b6eb8a4f1ab64a143cf7e907d83bd989dc7bb65e003897c3bb3c1f73a341c204d
\\xb14898b2f3f8dcf3df86fae9049c1992658ac3bacf5569d7a7e2d6cfed9d1abd950a748f8f72543de5aff56d0ca59f6ceb1c779a6c6bdb5f64a5332405c73f82	3	\\x433dce4470367c134f13effbb538d1d6ed273b1b35872880243df81c389e8dd694e753bc845a95d5a50f25193cd7eae62cb7726c52b725bdba1be9d116750109	\\x401eabfce5c5cefe6b489e963f5c81d5b02004f76d5968869cb843acf0571bb0d396eb4914253f4a0c862955d7eff492d19c888376d324898d7795376e21950a	\\x3ffcc710ceacff14c0ba5253d8e0979742fe7a62b4b1d96bc559c5290e94a2a89a41c8e9a0c8e857abc3682d961b8a94845d4287506b9b6bc662269424beb47def361a595d88515c445a605ad4dc8b9728103e8fe8db760146f1229e12c88f54ba071f52fd07a88b747a631ac3d0765ee40a0b4745334a2253ff67dcdc45c355	\\x95d44b7ad04760528900da9fcb0adb79110634ce98dca6001b0fea8de9e104967361cf945b68578d18247e0fb2fc926c17cb1c92b8591b09f52e1dd34399be97	\\x12a0ed1bea9f9c34cf694b11db9ea9d7066d43842494177f1613ab8da608dc137dc443dc20e00dd39f3a37cbe0572c9bb26f27e731c46a6f7d3da6f00fb2e1484573324f618103d32d46e3c0eb2d9a274c7b139874097a3133d1e1403dcbee3306134e16284d5998ef735f09a5532c493fb8c9b4308c79d1f57f90c47ca766e7
\\xb14898b2f3f8dcf3df86fae9049c1992658ac3bacf5569d7a7e2d6cfed9d1abd950a748f8f72543de5aff56d0ca59f6ceb1c779a6c6bdb5f64a5332405c73f82	4	\\xd59fc811959a31437cf1509d262ea90f0c7a3475d15c9dd4e21d12168180e626c12663dfa7b74d40df18e26844e4e9cd162ecbbcff4149726466db522ccbaf0f	\\x401eabfce5c5cefe6b489e963f5c81d5b02004f76d5968869cb843acf0571bb0d396eb4914253f4a0c862955d7eff492d19c888376d324898d7795376e21950a	\\xc343440f0678400d748d10b94ab481f1500f8981e290e72a3c8f8ad113e1c20690ba00911deda107d980b7d243ee779428de35a3b729a0cf8e4d8d0f8ca5b6107fba8242b11fa008d574c80131f5aa2a04c1b006234b6f62016ce042d80ff6beebabf736f31c9b0161456183ef755086c0d0daba1269807c30e2ecd1bef74003	\\xf4ca5cb39b2851e4213c303794098f6fad5c8ac868c937cd6c2d7792c663f819ba925a71ca793006112112e108e99fcba1145082b39ea1fd0b4fe712e04dcf43	\\x5d799faccfe1cce9b64c942a655d3629579e2bea95a23d3a018110a50bc737c99dd604cefd8e8b3a73075a5a4deac476938c42d0c6ebcc45445236349a37dd86fe68da9c1e1f81f49bca00e937b2c4d376826b18f3d8b4f83b454f4e06e1324d6e5bfdf8dfe0fd2e3aad0d16a3dc84676ee8f62bd49185d2f78894ce7a32505f
\\xb14898b2f3f8dcf3df86fae9049c1992658ac3bacf5569d7a7e2d6cfed9d1abd950a748f8f72543de5aff56d0ca59f6ceb1c779a6c6bdb5f64a5332405c73f82	5	\\x8f6c036dcfdf468485e11c88f1d8eee6d3eb660fc7f814d8f0f632293c764bd2be2ba85e65efffbb98f0ca01cf663ab22f5bebf0c7943f69f6ce438b8a208104	\\x401eabfce5c5cefe6b489e963f5c81d5b02004f76d5968869cb843acf0571bb0d396eb4914253f4a0c862955d7eff492d19c888376d324898d7795376e21950a	\\x50b9f19cd2dfd87aaf2d70d8560c271eef3d1875f6d9d00675714e3c9075b467b91378454ab722d000fb7d5511c2f411cb298a7dbe38f0371d4a31a1fb7ba111c88ae5617b92c159b3bcfb711a17349436ff201d9272eafbc115b600660fee6407b2f5d5f4956f5a686026567d678a95ca26140f85ad725db4c6866f16d4faab	\\x3bc7889cf7634d315da691c420497a6397de9962d3077b2e03c1c2711a5530a5860b934b838c965b1a5e7ebf26c1ee24794ea67bed948ea86f59d868b5256c2d	\\x7c622b4dbe8bcc30a47ce6060f390f97ab6857f952e75c00bc130a212290ccde10925bcae98f228ef05a4e84c66ab57d688c6458dc1d92c6d36d72d2fc3ad48e833b745c87089272d5fff2a8f98b7bffbc35d5f2f2c357d6200a10ada0c5c472ed18f48023a17d303996cbf45c2e93f318e37ec3145ea95d874736b84abe8c29
\\xb14898b2f3f8dcf3df86fae9049c1992658ac3bacf5569d7a7e2d6cfed9d1abd950a748f8f72543de5aff56d0ca59f6ceb1c779a6c6bdb5f64a5332405c73f82	6	\\x3075f1e431b599f60cfe73830bce8e2136d131a0f32d2b96e920a7909d54dd701301215d3b5a04f8c8efa9524f486867e76bf6c5838639d449c11c323ce91308	\\x401eabfce5c5cefe6b489e963f5c81d5b02004f76d5968869cb843acf0571bb0d396eb4914253f4a0c862955d7eff492d19c888376d324898d7795376e21950a	\\x74774151b92307d7ead4b3c622b3feaf8b04994d5902c5b2e6ad583b4f8ae2663d3421b2415a7609404b1ca67926bbfef700c7417dfc4417625b53aa6a3f5cf9ae4dacccf02c28cff409e92440903083d90907346208cc038e44417773dd68f35e2a8f34a62104186afb919fe4f04b6a207b3e66adfb9d991f142f252c776470	\\xe3deb7ae1817ab067a98bcf78a62dbd150cd7648511b1897a51be6fea02a5817435bfcdc86ef579328e412664fe8d5d137854650336c4e82c0a86eae7e82cc0f	\\x9c11fbdc061684b8be7630ae2d946bdaf39b16806993c4b3065a3b1fa8688594a08bfac80b807dae94c3749db1d7f68939c28ee4298ef69f866ed022947ac2ed13a7ae39f2dc2065f8cda16b9a0499fc4fd99ac956967d9ff8e376039e69d0fa5c7eed49850dc069fde640334add9e12756b6d79e25a8f5df0d5b6faa2f5efa6
\\xb14898b2f3f8dcf3df86fae9049c1992658ac3bacf5569d7a7e2d6cfed9d1abd950a748f8f72543de5aff56d0ca59f6ceb1c779a6c6bdb5f64a5332405c73f82	7	\\xb2bbc0ed248b52ea11d8bcaa191304755133abc05de7a1e00d1e9a3338c401b168e336a1b5789f327f265eac59d117c74e5c28868aff2d07600ad45535de270a	\\xccedb56d361d4983321788041be2be9b2b9b122faca8fb3550c6018f113572a57dc032c1bf77c484119d750a2a7072c062885cf8403341f91ffe22d8b7f678e5	\\xa050e32b6cd28075712474bac82675a11dda29803f574ff3a07cd6c598e4f6730d7405860e2933d3e178341f939143d5c709573de914811a01df9e6027c0e73671bd27033740467dc19317b432e894c3fdcdfcd25294a6c5822c6fba06d71f26f67444464d76fe85092042b8b19d4288ea14f45d96846a205bc041f28c1d3bce	\\xd4bf7a4568adbf542371c5773dbef51b31ef89ac4e7b0af79e61ad96c5fb65f619b54cd30626da7fc966562cba72a3c4df29f04f1b5ece521a6a258c8b1fcecf	\\x5308b614472fc2d452938b2a8cfa7984a0e65c142609473a548f927547d0e34d5018f015641824512abdc2423c69721c38a6dc250513d8e7f7f7ff5813a94b6b5461351fc74d02d1f440837d2469ce6a59ff9c571134c1f5a449e9f61b5254a0cafbe2e6b099cc2893d520c2d0e393f9d03fdf09c660a6f23de7943044f4533a
\\xb14898b2f3f8dcf3df86fae9049c1992658ac3bacf5569d7a7e2d6cfed9d1abd950a748f8f72543de5aff56d0ca59f6ceb1c779a6c6bdb5f64a5332405c73f82	8	\\x71925637066db7fa53ddd6639dd28b0f7fff0d1a807f5fdb67f719a4090a1f2ae310e3335a7463cdd71adf966c482d0b65297616215ff2535623c8df1eb18e06	\\xccedb56d361d4983321788041be2be9b2b9b122faca8fb3550c6018f113572a57dc032c1bf77c484119d750a2a7072c062885cf8403341f91ffe22d8b7f678e5	\\x4c55c0f8468069934eec49b563bea94f02cc66fc9eb376bfb07383fddfd34614241bea9b34aec0f00eea717d4e121861b8dc64ada6871e2e326f40418e522e642727daba4d0b811058c67cb7867c7a2103063ff8437206b72cefd03e7be33e75cc7dd4637511571d3ac82b345c637fed38f719bd9d9c651a0e1788bacde1bc94	\\x21ae54af438710999be59254ef3ff78c4cf46548298fe81afc92190c003f1babc87d915f6dd94223c9bed6d94e7e28b8e8ca482650282d7c013fbfc899d7d7e3	\\x74f92f9c3c550a69cd89d79c48eab18f02d6466bc9ce79f3f4ff898293cc5eea539192bf8e759b6c63f5c3b0aac17dce000861e83fa6935c42127df4d0d124f53af4220c7326956906e5e71255fa4611283f00a09a3ee48c85d7126e9a9fe6ab54576a101f6e234728ca59979cf99b105661dceb5cace10b42ca0ce8edc53f77
\\xb14898b2f3f8dcf3df86fae9049c1992658ac3bacf5569d7a7e2d6cfed9d1abd950a748f8f72543de5aff56d0ca59f6ceb1c779a6c6bdb5f64a5332405c73f82	9	\\x7f8e11dc4a15a9afbfe6366b1a2694e199cdec12f5be48b82afd70ad29a2dcf1cab4ce225419cb4b558f17ecec28f3964b4e6ef0cf4b4b85f731b7b7ccfb7a0a	\\xccedb56d361d4983321788041be2be9b2b9b122faca8fb3550c6018f113572a57dc032c1bf77c484119d750a2a7072c062885cf8403341f91ffe22d8b7f678e5	\\x7baaddc2250e785c64aadb310feff423841655270223ffadb8f9c74f470ae4ba5f2ddab5a9367606e5a7c536ed78fffc00a4dc4c19cc10b91489f11086ad480760621efaaae6a9be69884d27799990c4bcd230e751992dc0c541257f11bdde6b50d6b66d06609dded591c4c858cda16c4a6a0d5059cda7eefa34bf513478f82b	\\x787b08f0001e215bd1870cd51c0a95d2c9f1fd19929e12ef48483eaa2d5824c506cc2cbd5adb28bd69a41f37488050a4362803b69c23f68bbbeebff3060db3b3	\\x4e77d6b64a5d56afe53f4b533a7388539237aa4fd17d7549723cd204dc98fd586bd26c95f041d6031d48e8d85f4cf4918ff12bfe77822415ca413362ced6a19619ef2fd2fabb4b179b15e2db05ed803255b8b4a5e4f9a0a96220296d4380c2d251cf871942551054bd84a50ced739e64a2629f1661cda23f012be52781ad8447
\\xb14898b2f3f8dcf3df86fae9049c1992658ac3bacf5569d7a7e2d6cfed9d1abd950a748f8f72543de5aff56d0ca59f6ceb1c779a6c6bdb5f64a5332405c73f82	10	\\x1965842b89a9534ec7f9f4af68435c4678381bbc9f91a0517ad771b3c2a8f80e7acc4abb13861145a7aada2cf5acc11e8e9b11064b3a68ba173a6e519020510c	\\xccedb56d361d4983321788041be2be9b2b9b122faca8fb3550c6018f113572a57dc032c1bf77c484119d750a2a7072c062885cf8403341f91ffe22d8b7f678e5	\\x7222e743cd723e1974c64dd0af3dba315b3ac5e684b4a3c39b653f676ddce87f153d877e7d95b722e2d3cc9a19f976ce758141e4d508d69d2c2c05732f228a69eb31f349326ae6f3fb28f86b6c1607a65491536bbc57b03e5356c5933fcf7be211a38a5934cbb0ab50c5e02978c448b96235491819acc2ec7d54ad1cdf9bd170	\\x91a2f91cc48dd3527431ab6496aeef8cb313fdf30c45ae7e33a41cf24382d0c0fec6366a20ab7e3e9dfbd8763437affb413a53eb5b2cb0c283d1f8d64b8efb42	\\x4a78550491d45795cf1790bd028880e420524be8014d019d5d761728ad407f5571e85100554b317d0c664039487103bd42951d9d93caff2174907379b9ca1ba19ee49630f6ac1358fdab14c628e514460c7526082dda4c69d307b3162e3be72118d62d416796b6ea3a673246250c111ffff195916053937a49c9150227e14e0b
\\xfb4bf584bbb78084c9ea469a5d8e0069e90041b66a06ddcd1eab78ad6163402a1978753b3cdd911e5b95e1fd72273ed9fd0b8f6301f09aab6303093cda40e749	0	\\xc554de04af7adfbd017dc60d15bcf5287e81a1f1cb179ecc11cf99084eee54e4e1717d7a13b5e241467e326eccb6bcd0e606cefd97e4a458cd346cde62257d07	\\x920e9115b1da0f24d49e2b70b1a0df0a82c19e741fa5fb013a3fd5c7a75577edd0aa800ca4d965b53b772ffb1562a3cf58ee82bfade084163e381ccbcd1d1f23	\\x9d3bfcc6b43e6b4bcc39763c55d59e65483dda15f635ddd799ca2f4849c6eafa6b349f67f5b7127f564c74c66ee634dd418b073cc7fc6ee12e07ea25a5620746ff6b13bac5a44474533482f24f9a6604a52124dca43bb4f5da9ebc20a11d1197775ca63ee9cfdc7e8855c55afca4465145d257e1a7e507b5eecef23f7d946733	\\x8b6365b35068d7a79c2177254a96bf612b3eaa139188902f41aadebc0045202254f1a367d6fd2af7b9c0218032a8e51f68918340de4bb95e48a8427cae43fbe7	\\x63d918c540b1699fd073e128d1fe49cfbc05aebb4890323f01ef50e635fe30f9ff367d7da15080c68ede3eb568552fbd4bb5f9499ae1e10d21cb5809430e1344b02b64c41d83705dd0aea2cd288f260a5d6126b54d7ab76562bb341498b11fc82096104b110361e8eb01b5d6a0dcc1f37c949ccc1e122cc77b1b2aa43903603e
\\xfb4bf584bbb78084c9ea469a5d8e0069e90041b66a06ddcd1eab78ad6163402a1978753b3cdd911e5b95e1fd72273ed9fd0b8f6301f09aab6303093cda40e749	1	\\x4cf186b5d0271f59bbd43a216220787274e68fb475d62bca9e3a269396ca7f9f1b4dff43445e2b9d036994be0f22d5b23c9915ab495911a6d5f19092788d4903	\\x401eabfce5c5cefe6b489e963f5c81d5b02004f76d5968869cb843acf0571bb0d396eb4914253f4a0c862955d7eff492d19c888376d324898d7795376e21950a	\\x9c915f91107a75d9d5b0d822418e6879fe0a42970c8e49ae0b44c67dd0b29e6f96fc60097d85dbad665f2d9755f4c5903fdb0c4beb6c4f3af381cbc3f978f3b2f7444179028895f77fe44f360edaf24eb766c8d1eaa37a56a896cdd1d47901f63a8c7189517ea25cacc5a619972a35a62ec931c4fee028f30ecef7cc43c8c93f	\\x36d88faa97331e1f74f2c58723473b4a3a792a197a593c159792f94b088f2455db912e38da16ac666befcf2097fe214526eab3b570883e1844f9b1aa2059f140	\\xa60ffbe2ef20a1e2e4173a13afc8f09cfdc884de8425314b94ce61c9e6e8fad4f9e10932f604f59124c7c9cda633f8d42d349683dcce8819f97017c3f94edfaeb1bb2275bed5d6a5b70229b8b2951bf2d545baffe2847088874b5db067d0f57b8bc336b5232f3399161b6f18297bc8b66056cf340ef24b4d7eea280cc9cf28ab
\\xfb4bf584bbb78084c9ea469a5d8e0069e90041b66a06ddcd1eab78ad6163402a1978753b3cdd911e5b95e1fd72273ed9fd0b8f6301f09aab6303093cda40e749	2	\\xfbd49860d2b7b16f00611b2dc6a79cc9f67ebc8f5815fcfd67f40f72e892d992c2b38e838fd45439487411ccb632cb7f961793bd08b789e92f02815ff5d1f508	\\x401eabfce5c5cefe6b489e963f5c81d5b02004f76d5968869cb843acf0571bb0d396eb4914253f4a0c862955d7eff492d19c888376d324898d7795376e21950a	\\xa58d049cb6b3dc2d86a8ae6ffbb88bc0328242f04dfa4fb95a83ae30d5723af6b3ace2ab8ee81d5d0d19c019afa20648963dc925303442f8e01cfbd97db9b4bc4d8159e8d7fb678ee4dd8d8f78ab452145220f5d071c2bcfc8e3a905b24532cf08dc2a52dc5c5a177ffafece4b9ac201de38436e686b705a784beeb0a71ad2f6	\\x0b0d7d554f1701a2bb5382f3d7012b642795e38c30c68a2704a203dd6f9e49cf486ddc8747edce4e48d7fcb43a424881a0aadf5809598d79cc870a0107768d4e	\\xda263fd3bc805aa3aa787037b01f45203b3dd7ed777d351a926ea94116b47ef5ea3d33e45b8d55b3e946aadce96ebd66eb7e040a51d9a35c434404522b022f9dc760dfefe6b5e50160ea02f4de829bcf04612bb1777b0ccf9b53c78bf08a4e8f3fd069c4f589e6722f39a3dbc006a8bc29e2815775c8ad32a8b6e7dba3cb991b
\\xfb4bf584bbb78084c9ea469a5d8e0069e90041b66a06ddcd1eab78ad6163402a1978753b3cdd911e5b95e1fd72273ed9fd0b8f6301f09aab6303093cda40e749	3	\\x68550d723c645d2837aca6f6c540b1611d10e59e18ae2f4ca9690261f3235adf0636e9464ae725ad85948f7b2b89a990bf927d154b0cdd951b72d9d4c38cd705	\\x401eabfce5c5cefe6b489e963f5c81d5b02004f76d5968869cb843acf0571bb0d396eb4914253f4a0c862955d7eff492d19c888376d324898d7795376e21950a	\\x246689e16c8e40c3de4d9318a99963a9387c00130841ec529b3e8e7b448a0986dbb46ad69d3e70b12582ae29a626e2e20c572cc1f2288f46011aa225d139a718074750c26e1200d60b01ffebbdca715920479b8b0ac00ca447279a215b76b659eaafcb4c80030005d5eb939f3c95f2fa1c328a99c3fd6db5aec8f9ca44b63520	\\xa96470fefddbb20c9fe085a3f9ab1cb6d75aeb5e540baa8b3cfff8babc24a185ed13ed99c5fcf496b60f00bde912a32902d6c8950c2aa0b78b20193daee8bd92	\\x340b6a591858318e51e11f97ca34343f12defc2259c8d0c971498137c3fd137684fab6d5d358868896d0e3c5ac15f2de770390ed6b57f39a49cef966fee5b5e60d4910f920f54456945599bb59ab5c1469310afad3de0d5f9cfd9ea929cc1b24393bac86d1d849887ec545d7826c5908373f3b88ef46f0d28a65a9dec6a5ffbb
\\xfb4bf584bbb78084c9ea469a5d8e0069e90041b66a06ddcd1eab78ad6163402a1978753b3cdd911e5b95e1fd72273ed9fd0b8f6301f09aab6303093cda40e749	4	\\x9451d1886e0cd58817f1d1f35506b94eea8e21d08f0eef88a341f4757d59cdb141c60e633a5ff7ad7a7cf4ec17ea501b41723affb48f94af8f667f173a143902	\\x401eabfce5c5cefe6b489e963f5c81d5b02004f76d5968869cb843acf0571bb0d396eb4914253f4a0c862955d7eff492d19c888376d324898d7795376e21950a	\\xee4f531ff998ac30bf49afec050d8239c0a204eeb98085be798ad453e23e2400f503197e0e0d64cc5495c2e556bfd8f189bdb2d28694805da4f2f1ff930d4306aaba67703f1d9e362a5b11a64961aa3e9715ba946ade37dd93f6eebb715dcd830c0cbe7aa64f343bc2eea21ed2d2e152c614c2e7119da3b7a19dff5676a22e21	\\xecba7e2977c8d6bf05e746c13cf0589fb7f2d697399e65001087d7f71577fd17a7cb90df991e3bbfab48638a72c16ca2544cdbe025b1cc94c4f3027758e3f2a8	\\x086750466dfb764d899ce1cfeb83ccd91c5002f8b6dc6ceeb205d5dfbb45a0b7b6a37b5de9989e4e276aafdcde133bedd65aedb1171979d16889cad1efecefe28a96e9580fa7eb108c876181ffb11913f8368bf607cc68f3c8a3bd978619f98ac2af7f9d45b5248f04e2aa86ad053c9055aeac4747e91e79cee1c43d2fb96815
\\xfb4bf584bbb78084c9ea469a5d8e0069e90041b66a06ddcd1eab78ad6163402a1978753b3cdd911e5b95e1fd72273ed9fd0b8f6301f09aab6303093cda40e749	5	\\x442df08859747f301cb9fdb99b670a5493d0d4be4b352715f0c82bfc7f307215d80bae8e1faf7b6417834270bbdbc54c9df21f3f8a05fbc8c537282f73b3310e	\\x401eabfce5c5cefe6b489e963f5c81d5b02004f76d5968869cb843acf0571bb0d396eb4914253f4a0c862955d7eff492d19c888376d324898d7795376e21950a	\\xce289f7cd14e1cb293c20b9f95a29dae290702353de4cd4322054c019aa87a8c6aeba1980acf8a6c83256982f35cd63799b274b5ece827186e587738d08709dde9bec04ee628d4840bffa2e7634844eedc0d96f2b8b485f65b6817141af97835cc2954106a62ce03c54c525e1b1a7e135439f870f4b0a0aa1b2727cead08044a	\\xf15c7d2e1dca225dc1711537e0d7ffd4126a396c1169250c8431041d1e1bb4e5c1d78b929bd02a85dfbc059d46aa3f0991d9fca2aa4a5849c2f4b8019e5266ad	\\x115ebbf576f46f9fe45d57587df4575b371a0ae3f7ad9e1bf9849cd218c985495b70b91a851ce66b4ed708ffb37e8e56a2db0ac4940d4b8186ca227ef51a6df7c1ddb938e04c13e63a7775c48ee81ae773e17dd2b12729aba6592e14bf2e8968e22c14801ec49673e204e7f22b404d2816541cde8185fcc0c033af1617023b31
\\xfb4bf584bbb78084c9ea469a5d8e0069e90041b66a06ddcd1eab78ad6163402a1978753b3cdd911e5b95e1fd72273ed9fd0b8f6301f09aab6303093cda40e749	6	\\xb546b1b22640e251a320dbb7bd901f7b349a59a2c6c31d5b0931b0beea4e38b2b969e4031949fe7c2c5e70dafcb0e087e01849f3e81c0a6882a3056867d2550c	\\x401eabfce5c5cefe6b489e963f5c81d5b02004f76d5968869cb843acf0571bb0d396eb4914253f4a0c862955d7eff492d19c888376d324898d7795376e21950a	\\xadcf7d229971016f442d04d770b9d4f5dbb41d071244b1ef10a97e49143f9195fab752eb2476dfa049c01098e25fda2eab858885746062fedc0f17e8ff8b20fda3b3eefcb4a9791772080ec261f2ac8d0489c33ad09b084569fadbf833ae2676f0be517e5baab654d8fb5bc607bffc3ccc819979f42515f2599fa526f41ea2c7	\\x69d0329a5a6c6e392858bc63537412c038f3e2b8eb0efc79fd1144cbca81a0dfbb454748ab747fce6e105ab6d2f1374a0f5e56547f0f4aa1ca2acb22e8406f0c	\\x26e4588a1619034afe58b4437a1d8724b3c6c46ba09856f5d9045646c9f9626522243dc613bcbbbbc6ca46fbe19c3a53b81dd6e1b7af6e798e9842facaf412c25143eb85e18a7c565d70ce899fbb7db47e574798629680ef1791587352b0c578ff5389accb9e0b202018fb29ec282d544e416560dfad5f329c075bf557d4d365
\\xfb4bf584bbb78084c9ea469a5d8e0069e90041b66a06ddcd1eab78ad6163402a1978753b3cdd911e5b95e1fd72273ed9fd0b8f6301f09aab6303093cda40e749	7	\\x4bfb1ecbf621851db28b8f31d0263f8ef39288529b239bbf952295bfbd124f145d771d5ee54367038c81387c0ea62eb6e172f2294e9d5245c64d9bb6ac459304	\\x401eabfce5c5cefe6b489e963f5c81d5b02004f76d5968869cb843acf0571bb0d396eb4914253f4a0c862955d7eff492d19c888376d324898d7795376e21950a	\\x1fa9c1990b8f607bf96625fa4b8db0833d75059f7f947a54a2c1c5d1635c9d459d8f557eeaa660c18250f4e2d0a7b9f899a367f9fb82a40a893f5dbc517bb47fd5b191d61346b682d894e9d36c8c0f354a9c3ac7d796576cb5e8cb098096508e753fb46a5cf8879dd07d1065fb036add9b1f241a25b101555b5880795ee859fe	\\x20fb9c2188375b8c7057948e47fa5f3d93956e397321ff7cca0d0b0b8b486729f2c1e91c6288a9d86931ed5b0bd534d9f0fa5ef6cf528c32d9dcd3c78d3eabb9	\\x8385bf6601dcde680a37aa441c896a5d80fdfb5e6e81579385ae9e0b7512ecbb64112467cfe8b95e7cef7e408db2640ef867afc6d230edf1891f25e1803dd8943fa745b2f59e1087823f24415a24a3ba3bbd89b70f4f913e9b0dcd8a49258584b43d633940cf0e34e5e546a1e722de5bccab4765b8cd14aaac4544a1e1880688
\\xfb4bf584bbb78084c9ea469a5d8e0069e90041b66a06ddcd1eab78ad6163402a1978753b3cdd911e5b95e1fd72273ed9fd0b8f6301f09aab6303093cda40e749	8	\\x485b96b11b3aab94f83fea3f37f8a39f4ac228255462d425244d4bbfd7349ec3a60ab5c49f63ed0c7a1095d9ec077768fd75cf78e42a3e9f9c5026b9cc19250c	\\x401eabfce5c5cefe6b489e963f5c81d5b02004f76d5968869cb843acf0571bb0d396eb4914253f4a0c862955d7eff492d19c888376d324898d7795376e21950a	\\xa5e77c3c06f3891b285488b954354d3fd6427e6d4f2037f99b88ef7570415295324e85ba392f6218ba049e842d7e804325bc60c820062a48852b558b685578915a7acca20aabf5d9a5d6d7500d124c3666f567c4a6936f85651fea9b1a9fa6b89f7804fa4be64d45143292f5f9276ca7fe1e48c5e501cbd1dcdb8d8f38f68c44	\\x917061b8033273cb93636c52e2cb849e96cf4e7484daef091c8b900c2351c1c7d73000c7ae099a93569ee08e4140f8d1a9ab83fe8f7e848e5922d7e4950b8501	\\xe99ce4910d47218632fb232d3f59d7599bd79901f8eeb2c1824ba4b0c9616ad6eea9d5655c132f35ce926e77a4c66d3ff07c3bbeef377928d76f70559645d35137636df02677866f45195c5c80dea1c471e186e90e34d940e15f49f6b74415e172660d2e3c261356b8fd5b2c8a4b98f8c54e9653edf7cd31dfa4948a68e9247d
\\xfb4bf584bbb78084c9ea469a5d8e0069e90041b66a06ddcd1eab78ad6163402a1978753b3cdd911e5b95e1fd72273ed9fd0b8f6301f09aab6303093cda40e749	9	\\x005332d0df99cc1e2b2b4b7e4751d29ade5b138cdd8031bc2f82eed9a98e1aaf28b2b59edc7f058355d79c01e948c727f2716b00fd185286c661786077396c05	\\xccedb56d361d4983321788041be2be9b2b9b122faca8fb3550c6018f113572a57dc032c1bf77c484119d750a2a7072c062885cf8403341f91ffe22d8b7f678e5	\\x185718efb10701875d6e7f8849c4b41243cc737acd7eefb871f82d220684246186002454f6c817a6ad6ce74cbb9f2cc1371870abc8704c7a37cb7e2e77fcc5301070150e5b3c5504d6175b73ba2cf366d0207b5cb1118ad9ec9e745c32a0d85dddf0190e6384c0e12403937b4c5a222a90825b361d74bc43ef793e2162f19a19	\\x98dc5e3247cb877b0e47bb1d2b54084349c887a61fb78aeffd36df383b8ab92b0ce6872618780f450a9d810ec21296c09019394afd7318a8981f6c015a4048b1	\\x06494bbf49ae4e54a29ad48289c9a1d6301ed8cf8dd92eb97d39cc8608957e934c563b423b20a4b1be34f5b94f5e70a7fbe71fb02baf9bd76428bd21092b9833ce28c6fc17bcb141b3d8141c8bad1986d3f3ac6123260d6bc84159dfbf71bd74c919ac6192d9a490341086be99c98cbd0819fd84dcc71958bad3258995c690ea
\\xfb4bf584bbb78084c9ea469a5d8e0069e90041b66a06ddcd1eab78ad6163402a1978753b3cdd911e5b95e1fd72273ed9fd0b8f6301f09aab6303093cda40e749	10	\\xf0ea849aa29cc1f8e8db769a759449662be9b8b82c6d04e01ae8d6eda83d34eafb11e276f448fbec2462ceb59d1e700764caa3b3cf7b80c614d3d563e1f26008	\\xccedb56d361d4983321788041be2be9b2b9b122faca8fb3550c6018f113572a57dc032c1bf77c484119d750a2a7072c062885cf8403341f91ffe22d8b7f678e5	\\x52c85819df48085934389d088a9d0381276278ad9a4d487e51489d7d68c86f02e8c82f827fd7640670f0539735c422443fdd36742bd9aa2a722e1dc31d7df892f1170b990e00db3db4a1eab501a19ef9c39bbf571b4ee322c307a34e19854b80bea93dfc2dc636e57588970d471c414cbf5c36cf3da110bace8f62b9ae7cfe92	\\x1e1ddb8c47d9f2f8f48ed8924604f4e21dc3b5b4a08966f1dd0dc246ef8104857768e79db34509c74117905734fa0a0c7cca97e57ccc0524a9d248daba23d240	\\x17bd2435126f61df58449dac76410aabce038378e5317540af40fef6f9f373cb6dd84a1b9fed18e8606792234b6ab12b3c404a70944db1bbb1160e52c83f56b63277ff70d0effd9395d4282c9847db130a8ae4faf32e49e555ab1f1c4868c0e7709d16ee671497bb02c0c95889fc12288daf19a55bba0c6f4b7ebb824002d13c
\\xfb4bf584bbb78084c9ea469a5d8e0069e90041b66a06ddcd1eab78ad6163402a1978753b3cdd911e5b95e1fd72273ed9fd0b8f6301f09aab6303093cda40e749	11	\\x099a762ce15c0dc995b795c7019085116a79b6e6d0217ece05e9c2f5374dca5e085d65dfd78af7fda0b50aa03afff388159a3f27deb35dfe62dfa9940d8f3903	\\xccedb56d361d4983321788041be2be9b2b9b122faca8fb3550c6018f113572a57dc032c1bf77c484119d750a2a7072c062885cf8403341f91ffe22d8b7f678e5	\\x540fc090a20364c71105e101db128b78abed9ea54af5a9490a31fccdf37a8f3c4ace5b9a568d59796c1cc2ed8fdd8e95017a2eba70d721f356f3f9248673f740499f66b44ea1ed4da075e31bbe9e6052d2cc3cd8fdb2958b41594f2d1a4db65daa869c3cfc8d1862641d79cbd1ab8ec63c34830a323e110cf9f032cf632a1db4	\\x974049e2e6d691eec9f945df46c9a468085a6a4148311ed99b28d7aab7ccda3f2ef5c5f70be6bb63f001a3656b5b80f3a1bd0ce49ce56395ed07169c1b3a80e5	\\x198edd936fe2bfb72976ad30ce19b51a246621997d20570aa5e4cf2ff63b07c4c04f77962eda556a4c5e1357b09e25229ded47a2bca0f1b9296f35637cafa812d859a60dd36cf067aba806684d390bb3d09d45a25df252280085f91cbaea7e6132cf2d029e9bc97f96192c530e63b2eb5768dc6409c39f0a510512da14f57fc8
\\x8661ac5eaf06e45f16446825d8299b52bdf1bc37fae457e114b483a4bcf4963d78d472df5d2ba4ff422350c0a5c45616b73709263de7bde4a2dae319e43d096a	0	\\xef4739f30cce71ef811fd8fe3c5d70038b3313ae7e00da3c12de70165e1f059b2d6f0ccd85b872935784a991b358fd475606305e332d642e45a38a1f41508601	\\xc778d97644c119f9ed0d672e416874091a384ba0603c118b2b5c4e9d9e181a67e9fdc99552cb81d3c8b2d5698faa889e4e6c6104147f3f1f9a2eb87dc6ec5dff	\\xb29dd9f8a284b26f9ef7dc64f987cef7576900eafda527fc0441b28e292a7235c7d914f8cbae0b7ecbd70a553ef533f00eef0e19b1710d6d9ff986687ebc6f09bb736b160a8ad25043ece1d4685763b318110a851a8ced04cb068e4d491f9368a066321bcd502700dda05bcea3359b1ace55dfe2004ef80d2708c8b622a707ae	\\xf34d09fd81e14962f31c47ddd5dcec8f70b638076176b729d7db760a23e7cea06dffed825b1a2d12c56f73367736dd7e750179a7adc7d51a4acb37f32ca2e644	\\x6336011a856732b5f13f1deb5baa17e0c5b078fd49217f0b8d8e34dfee808ad8609b43c73b10d6ca55f59efcd977970bd113377ac46b8267e57e26ec40678a35bb4085ec46336591f34c30e4735417a11a7710b2952ef123a3179f7d30497c38692c9f321adb2ef9204069d0a50539b1c6be544fa5ffebe9c18f7f6d1060afd6
\\x8661ac5eaf06e45f16446825d8299b52bdf1bc37fae457e114b483a4bcf4963d78d472df5d2ba4ff422350c0a5c45616b73709263de7bde4a2dae319e43d096a	1	\\x2aa22eb7eceaba9a5887b9d47197e88e1bb80e280112fe8da32bc5a83f709444cb6c0a6b8a98a775599fad3037b6df169e6dc2418079543c206e221a44072f09	\\x401eabfce5c5cefe6b489e963f5c81d5b02004f76d5968869cb843acf0571bb0d396eb4914253f4a0c862955d7eff492d19c888376d324898d7795376e21950a	\\x9cea9e2cfe2cee306900f008cd352d6e335ac1da6dff0bc56893c83e94c5256f844a3f86a3435a92d4092a1a8210d1e6526072e886b0e1239a4db62e8e31d3ede677847ebad5ea8a9800c4f96e6b5145a8cd1d5f398a678fee8e230568c2c263e7ddd6c4e30f779e11d3b2bb4ced93e0c0fcb673c16e067825fffe9552ba50e0	\\xada2ae7af91bae1157a7566025005443ffd03998ddd4d436462e87f5d18a472612260b265bfde2e4f8c2377812c1087b43fdfa803a16b406f996e44cffce833b	\\x8007307d23be4819bfca205245d6af111426ec5bbb14361e7fb93b28b47bac6fdd72d6ed4ba417447338f07a8e090544bbaeaaa1a009321dfc3b3a31f56bc07f91882028a751270c0a3ebc58febc5726605e88a00b59e47172dc8f49e3c6da9ffbca5b03de4198ecb188f5c60511bb85765d26095b41a8fc85631894801f54b5
\\x8661ac5eaf06e45f16446825d8299b52bdf1bc37fae457e114b483a4bcf4963d78d472df5d2ba4ff422350c0a5c45616b73709263de7bde4a2dae319e43d096a	2	\\x07f6cabbdaf1cea31d4a95ff2cfc55f86f8dc6f2496d2f2c99ceb31644c3059fb3035151204a5b0105968c3ed016fd4efd36d72743a7d6817666c01cebb8ae06	\\x401eabfce5c5cefe6b489e963f5c81d5b02004f76d5968869cb843acf0571bb0d396eb4914253f4a0c862955d7eff492d19c888376d324898d7795376e21950a	\\x5b751a60954d66894e8a7d2030900779e8d1b66e04db870e2ac66fb78914ed5e80b7cdd6a75537e3d45f2ad63bb2019581168401b7811a00f20b4a56e9a773abd279bbe9be3942f7d6f7fd4bce55fea709d354ebff1538d7db33b581991ba6c92c490a6881a96828930d8f2e4b7601190285c1e9a47b47b6be1185684179b90b	\\xcd7b562e0e2eed5086ebd90fdef5b91ecd43914f019d5d00b9f2e58410df130fe6477cdd3219a00fc9f190a1930fee19b15e98df11a9122fc690238b805d6c8b	\\x4cc4c6a7eb7e07ee4aaa983db8cd4e8755ce990f7ed4b32c69831e5328c17d964ad7c9e9c94ab1e641cebdcfc6c9c4407c039508d26adab25d96953ede1c4eda4d47fccba7a035bd9ea7d537c4fdf83380de13dc5e025b8ae2641ba840aec7c54deb78713c260ada3a804cca30573800437bfa3e8fea2866a31c82777c0d3cf2
\\x8661ac5eaf06e45f16446825d8299b52bdf1bc37fae457e114b483a4bcf4963d78d472df5d2ba4ff422350c0a5c45616b73709263de7bde4a2dae319e43d096a	3	\\x2ad2498a5513f7b6c7af121ff1c45d6b7b99dbe8e8544d3b0a9024740b0b1c6faf0a60657154aa9cdd6b4110cd47fb7c748f8a20858d9f3ce990d82df36b500f	\\x401eabfce5c5cefe6b489e963f5c81d5b02004f76d5968869cb843acf0571bb0d396eb4914253f4a0c862955d7eff492d19c888376d324898d7795376e21950a	\\xdbc432f783bae10fcd74c61c575878bddfb54ad706de7d15617852b555230bda3dd9b4d43eb25ecefa0b3688806d1961341ddb413573533019ff3e6b876b729e4288e8c16fb824a319ec4e56a9745e2212e04780467f6bd60c85bba67187338bfaf582d484f2ca0b17b178cb176490116128526256fc3062d855fd8fa3e9a4a9	\\x9151526ee3a9ef7417ebcaa3af505dcacc3e35780927a692047be5e763e9320aa9ef65f35bcbe37abb46cb4ef00d0af101569f9aa407a53af712d13f96b3cf9c	\\xd4b23fd2ac974a9ed2dfacc78c66cbd2688ec6cf72b16501c6c9b71649bb6f9afa1b397525db504cceffc0e32ef9246e7ea64602232a7f2663bf6efc77b04807a4606833a065defbc2ecd34c122f5fd52e64a56278bbe18af5eedb5e8450ddb4f256aeddf6610285ac65e4dd4efd8d2c0946693c7aa53fae086efa2c3d570599
\\x8661ac5eaf06e45f16446825d8299b52bdf1bc37fae457e114b483a4bcf4963d78d472df5d2ba4ff422350c0a5c45616b73709263de7bde4a2dae319e43d096a	4	\\xf34e4fd8889bd7db71eb79ad07a5565c92216a4e60955bf6424d1306786a466d919baa7ae6b958e5e2ae9cd33eee2862ad885ee7d1b5d7be75b7b4b6ff4b5c0e	\\x401eabfce5c5cefe6b489e963f5c81d5b02004f76d5968869cb843acf0571bb0d396eb4914253f4a0c862955d7eff492d19c888376d324898d7795376e21950a	\\x2c58350dd8138aafa60db7db8f482c81ef1fbd12b1d08cdc4a0a69894fd5b9c623dd8706ccd10a52c04cc3d06dfc3b296d305a656b4d77bbd0dd5a1802468aaa74f80827f80d1c47750bbae5eed7c273b6ddd8b84b39c00a974879acae413ebc4c0e654e998a15319078c6fa7a6adccb4df454c3c0c84c679c15d5e3179182bc	\\xdb0dc201c10bac44199c5c07e27fb4745675d9616c8363b30ee534610fde9fe94b329cd20f4b6b849f74627766f291e11904d7fb68b39bd23b3a7f6a4281f16d	\\x3334774e5b64cd99641c0caea902154b2e60e3d3e87119481d93449d48a5b2868885c604de22ac86bbc92248f3f89e5bd22a2af944a22c4ae8e36836da99b046cff07efd10c2761298e282b998166dea9f862f807ed1f04a0391a07a38b04e0347bbad53da548412b97d36db0d9f1c77bfde05da1bb95917612486ac95828fe1
\\x8661ac5eaf06e45f16446825d8299b52bdf1bc37fae457e114b483a4bcf4963d78d472df5d2ba4ff422350c0a5c45616b73709263de7bde4a2dae319e43d096a	5	\\xc7e88bb846a3bd891de4af2f8f268fe8d1fe029f12ebd2e6bb2c10b0414e00c2e136008b0bd92a32215261eb3b7b59e477da4567ba26aece91e483d2fad29005	\\x401eabfce5c5cefe6b489e963f5c81d5b02004f76d5968869cb843acf0571bb0d396eb4914253f4a0c862955d7eff492d19c888376d324898d7795376e21950a	\\xd4211e2553d6aeabadef966a3c0da9e1fe2d7696d2e5cea3ec6bc6900f11cf2a151e4ef2ff24197be22805eb334d156e0baed746998ae39ef1af51068c317f912c6b7d431d98e082c7393a78cb62bc25120b4020aa0d55096cfe5aa1a34cce599375f645d68c61ba35dea10eaf0813664b86c5e0086bcef7edb90a6122a685e0	\\xf1bae3719abeab3c4ff19742139481c9c2301c8988fe1552761d56eef21dc142fd004ec3d8a8d4acf3108301ccf0d2ab71fa1641225f3c392c6f31743b01680f	\\x817cf590f4e3ff9572e8fc1266d321cbc0c79bee5f483016644a9f69f9720613411ed45a2c14548181842dd2376a48533784d8aa586c6d2b7ebe3fe1774f4a5adf8ea61ca1397630ce9fdbd461b7cfcf7093720448a7c28b60340dbeab15f1897f02e402c87daf935b8d945cdc46715f43c783e7e3034452ec250b29a1b6ffda
\\x8661ac5eaf06e45f16446825d8299b52bdf1bc37fae457e114b483a4bcf4963d78d472df5d2ba4ff422350c0a5c45616b73709263de7bde4a2dae319e43d096a	6	\\x8d3b70f190624cbc04e8a2bef74c0f2bce567cb73acd9794dfeee76d5d54a32b73b87f5d483886dda40d4c835221e89497aa2595a49d3b5cf1ec5709cdf2a002	\\x401eabfce5c5cefe6b489e963f5c81d5b02004f76d5968869cb843acf0571bb0d396eb4914253f4a0c862955d7eff492d19c888376d324898d7795376e21950a	\\x94e2232d783a02a91d7896379e24afdcaf4698dc774b8426d171f1dacf1ce5d4994f43b127b7a6254e16a240cf8ccffea0e32fcffc36f5a3150d4ed665db96770e57d0f0eff9b3509e4b5dd7db2959bd800a97808e9b97c090a79781977305ce1f6e89c0819a2e194b2cd5e41eb54e0cc09f6a78b502d0bb81f46463e7bc9c06	\\xe25dbbb1a927591963995d57b3a84e786e345eaa627ebc6c3d94d83da3215f087bb8e8eb7ee504bc377d36177ede7bedbef9e0d9c21189f9a1fd26e76ffae17b	\\x8c082d8ae7700fccf5aa74cde5cad138b7083afecc2ae775ebb323317d1174a5b2fbf09a1f9189b2c635a0f47cf2d72ca4e04be2ccb3f9c8f6ef0f303acab11ecf84c36575a52f8500679f8e5f8a1637fad335c60acaf4171111e77777c5b5b1b3c7a2586a33bf2a122973a1cfef02c32655eeec8d94c69d7afb9f0b2bb0eedf
\\x8661ac5eaf06e45f16446825d8299b52bdf1bc37fae457e114b483a4bcf4963d78d472df5d2ba4ff422350c0a5c45616b73709263de7bde4a2dae319e43d096a	7	\\xf76352d7ed4cd4a4e45390adcd747352d875e304a6aecef2162b9679cce0d591851542520aefd9e9737f936b67006c7b8e70b6be5acd29ec85bae14d5694de05	\\x401eabfce5c5cefe6b489e963f5c81d5b02004f76d5968869cb843acf0571bb0d396eb4914253f4a0c862955d7eff492d19c888376d324898d7795376e21950a	\\x33d057c8b2a15a83abebcde0cec44285210ff5c845a946585a37fd4f1e61f83868e848f7086c6cc1faac7ba97238b7913a990edc25e8f2762629f07889f2f9407fae5e12ff3cc6959f1db9482fb2278a7efe9532a67fdc19a0dc0de5b502c5985253dffc35cd4548b2848eb582c0b05f5cf0561328d7fa56e2e91012260b97a0	\\x103dd2aef24b727ca03744b92617704dfe2cb10d0b4a8af15a92b655a8d22e39b7dc0a1df71d80e000cfa0e29594da2a99dd19564f66c9d5d203cafbf8841d3e	\\x76c4d8a8b210ed85eec67a38a0cdca52565ac6d26d614b121a1dbfc75a9efa1f973c565a212ec5ba82df810707093ab283b395ee3f43659c96fc197993351b6010dd37f5779869c636ecc2f1e517973277dccb55d86f059fc2c37cabac9f963eaeea565c13757ed4fe7e60eb177ff1e3ad5933a12965bfcfd61d6a199cb0c071
\\x8661ac5eaf06e45f16446825d8299b52bdf1bc37fae457e114b483a4bcf4963d78d472df5d2ba4ff422350c0a5c45616b73709263de7bde4a2dae319e43d096a	8	\\x1db50e4a2796715437efda7ec89b8d4d1f7f52e6d6daccf725e84d315df8f9d568c3392d4d1df15176729bbff67ab746430123598579414fe6d8272a6d286007	\\x401eabfce5c5cefe6b489e963f5c81d5b02004f76d5968869cb843acf0571bb0d396eb4914253f4a0c862955d7eff492d19c888376d324898d7795376e21950a	\\x81485de91a1597d3055de0b21e5b9a63f683fb996b823ef5a081856b34121a8f0290e4384ad70f9382ac234ed7351faf034a2389c5078d95e40ecfc7868b6e2b15a68f0dcc6e5c5573589ee5c5b13118fb690ba3522f9e4aca62ddff2dffa8932528b347d93c90ecc6c1db9b37e2189e8a086f6b98e825ea31a6bf91b263e17f	\\xaeb03d4cedf853774e7a32887139cc14041caab188937f1ccb0133adcf5800852bbe383f85b5faa43f0cef69b7427d66c06810b012a56e1def735c1821ef4f29	\\x9ac93992684dd97b60a3474880f64519185d6af9c804701ae5f46d01a7feaea8dc819588349f14af10485e17a5371b961f4f19ca992cb2c9f5fab6d06dc14554068f5415cd7888cbcdb60f2d956fa25b31bfae027d3b3effab57a3b7eace9342003a388c7342a291e84d927838c9fa18c30197baa5dc94b7ac2676e4da7eacef
\\x8661ac5eaf06e45f16446825d8299b52bdf1bc37fae457e114b483a4bcf4963d78d472df5d2ba4ff422350c0a5c45616b73709263de7bde4a2dae319e43d096a	9	\\x9fdbbc5e08004e6c0a56bc75078a59e3ca6f3c2b56c5f3df1bb4a78a9945594dcac3b27d84ea89e6c7089d337e48a4c9a3978e6adf58a65620ee9ea208f0410e	\\xccedb56d361d4983321788041be2be9b2b9b122faca8fb3550c6018f113572a57dc032c1bf77c484119d750a2a7072c062885cf8403341f91ffe22d8b7f678e5	\\x6bd81fb65bde83d184e8c83b447fb644df6b9445e0b10458e7113e3f4b985333546c56c0c8b3c5a4c36774174974326a605cffcaceb2b280e8b16b6cb75a3a7220288c89b22cb8d8840da2d8ed0484e98e63c6d7d5a0db5a2fea2127936030cf4b07e7ce30a3fcac5335d634b31211f01ce53ecc58d0967a2a52a576c9021df9	\\x5105d56cf42a63c6efbe32fd5268b240470a90cecbb3a731de288e3316f67e3bb3c50e3b7a11d9c2866e6a22a67fb4c42e8d7cc70c471ea8662f4eb17abbedae	\\x7dd9ccc1c657e7de890ab47da5977973a8672c969bc3c53c28283a669e9e91b212fddce8cec9d73a08607387886b23f32b03deba0dc02e9ecf25c87e2e47b8e89a0994acde78c01c445e3296e97368f21f81ec1d2db25ff481dc68438b1eac161c147631cc19d0d23b7e236a9675e7f26b45eb9eca84a88006db43757377a677
\\x8661ac5eaf06e45f16446825d8299b52bdf1bc37fae457e114b483a4bcf4963d78d472df5d2ba4ff422350c0a5c45616b73709263de7bde4a2dae319e43d096a	10	\\xcf5f0fda46f1f7acb4cbae1a7a8b9cf64a8fccb792fa894693d230625e36a3854425e84b2b4c6a535b91aae26d3a7a9d033d902418392712f75115c351d5ee00	\\xccedb56d361d4983321788041be2be9b2b9b122faca8fb3550c6018f113572a57dc032c1bf77c484119d750a2a7072c062885cf8403341f91ffe22d8b7f678e5	\\x1e6679fefc79fd760b41320e6e2dcd79cfd456ccecfffdcea6286085db9686e1c59306ebb6c08e6013904ee8e5f81751317722f67427928e0c674d75cc46524a43d59fa255376668b65a9ccdf7460a7e672e6ec249647c24da8da132716ff4a1ae482c1d3659cf10a4685bb3ce842b4681b38bc68b9598a8ac7032efeb0fb191	\\xc4d0a75f8b47f9fab99fdda6e8f2ffe1555ab270bec0bc865db1a9f1f96e4e3985c46ac61a09764867367a00875d9235504f998699d2945f65ba63e703a82403	\\x5ce814c9d1893ef4697acf6e59022773fb7c1f66ee5990c9b0bea9b7d2c5006a0b48a5a8cb40651043b73c6eb7e16bb99165b4af0949433461f1c5b93cdd56f2075aa9ac586117bff013adb5214e567fdacd60227ce8b4b2f23361dcc282e188e2318c5568053557c1044f7ce434be632f47242c29715f0c1abd4165a81e956a
\\x0f578b3844d553d6e49f0129f33da63be21a21b29f2d21f59ee0ee875b5afc176836afbd1bbaa507b10c5e996cb23109f69b5f034d9f9d43a379590da556e077	0	\\x85b816177f29dae5338af5bbf855f8b79e6cf83fd65df96cd5282fd1cb6214e36feb28366c36eec3f6c9fdaf1c6b3f38ad4e7bb00c5eae516569f3d352b9ca0f	\\x401eabfce5c5cefe6b489e963f5c81d5b02004f76d5968869cb843acf0571bb0d396eb4914253f4a0c862955d7eff492d19c888376d324898d7795376e21950a	\\x94bdf63fe13e75b20a9e58cb2299176a53bed2899eef29aa04280b501318629f7ca213c70cec2970a504a3d6e9ee38b43de430a7d6bd16413d7f0bf6f6293f30605838387e043e927b7f236b530e30f3fa3185fa40c115f92bd4dbd4d6303cd7f920725566301c344560a90784c8558d7e1df992a6a462df94fc98e3ea87cde4	\\x442ad9ca359c903f6d0a5d971ac96b7e9036dbd760c2af6b5d4f19210b70671733ce4997811fbf39f3ddac9d07676c413f88735b04e3d27364b9868f6a15d41b	\\x16edae67c12e9f9e4fc804d040b8822492a8c488e84b229c25c6225673176c44bf0afc5722436c3f87c9588d0baca93f475751738eba27f616b875aa0c964e842ba13ca9a4972a07a8576fc0fa0eb8de2d1597ea01bfa02930cf68b3e2f4837498a43f4932afc13b2855af9c12f420263ab98ec54e3455489e5754997bc98de2
\\x0f578b3844d553d6e49f0129f33da63be21a21b29f2d21f59ee0ee875b5afc176836afbd1bbaa507b10c5e996cb23109f69b5f034d9f9d43a379590da556e077	1	\\x30cf55166fd0f91db710161fce8c6b8bfc2c5e8724c35553465c35301247b3948322b914425d1a23872a40c973ce999f8353ecf546de535c526227e65b291a07	\\x401eabfce5c5cefe6b489e963f5c81d5b02004f76d5968869cb843acf0571bb0d396eb4914253f4a0c862955d7eff492d19c888376d324898d7795376e21950a	\\xde96ca1b2f985c160a707d56b7951dde4c27288ee99111c5dd77699c4d43b75cc07a6f083f8cb11f22fa646faa25bb4413637d49fa96217fa09227d71eedeffb0133fd3bebd3f9cc403b1af8060e6dd6e8e3686f0099c79bf535b649e43cfdc76863a1c67e3a0f31816dbf592c19ca1ab27397a42b709f2ac150bd1cc8d3957e	\\xf1279d4261494a50b2ad9417da836277342168ded717fb23bafa290520ae58143477e05fe12b3b9c2d6f2a4cf5e28c3fc6362e4470cff0fa4a8009fddc0a8571	\\xb88f78d891c1c4af7be12e358197dafc907a8a0ffb045a0985ab9b0fe965ec98fc12ce48d3bf554215b9c7824ca3fb5e5d3d687b8ee5fdfd0562ad771239a38ad9f6eda82c2fb1deedea1bc3b8ba206f76af374bcf65868881e416c37667e0bbe72b96030431b0995a3ca0d07bb63a0ca95662947194d3946e819b9204f339f5
\\x0f578b3844d553d6e49f0129f33da63be21a21b29f2d21f59ee0ee875b5afc176836afbd1bbaa507b10c5e996cb23109f69b5f034d9f9d43a379590da556e077	2	\\x40c6026451e0a0d7f449f2bbccccd46aef441f87650aaae81589bc0efa0672fb3d37765658b088167e9b940f849c1f229840ab96a4b24717d2c483b342682105	\\x401eabfce5c5cefe6b489e963f5c81d5b02004f76d5968869cb843acf0571bb0d396eb4914253f4a0c862955d7eff492d19c888376d324898d7795376e21950a	\\x3080aed13b9c154bf762992b7d405bab9865329f1cd4fea72221dff8675ee601485082b93783d3528540ef9abd89adec6a3fd25a4bc110d1d4f0351071a8e89454c02a2f38e01431a3b5aa9d0a2c7342e849ad095cea902ee562ac3a1dead63f3bea71fcf309df35ecb28b0db5446d8dd9568972ce8a6c166cf4df8789e63de8	\\xf599d14ee29386f825b30a479131886635294304253f8591c842ce1d034ddd53957d7d57262aa2d8a6fcd3f1a70ca960b6e112f36b588f9e4d47ed898821a228	\\x4aaf50391feb410e1c5d39099ef0f9a72ddca3155f25c495fce4cf224564164d702d71f1b6fb4fd1243b2bc0efe4ca85534656f7a09464aecc8cf7add40ed9c27e45bd2983cd2f03b25ade9162370cacfacd2626dc3d9c85d4e2c82a8438d8dae92885302280c3e5054f00cea832ab3e384c17f7eddf7b3df7d1e905f533182b
\\x0f578b3844d553d6e49f0129f33da63be21a21b29f2d21f59ee0ee875b5afc176836afbd1bbaa507b10c5e996cb23109f69b5f034d9f9d43a379590da556e077	3	\\xcd1b36ebab9433c680237bad6b22b3bbab359d1d14b7b5f8406d1bea1a271ec793b359ded0105eabf91537557f3d258502d2ee7e2e4e50220b883a81fb34750c	\\x401eabfce5c5cefe6b489e963f5c81d5b02004f76d5968869cb843acf0571bb0d396eb4914253f4a0c862955d7eff492d19c888376d324898d7795376e21950a	\\x77b88ac14b8b0a17ca408a0d25ab5d9417154512a878968b54e2d982590de4d28965d87df22d8c19bee60978a1ba363fe180967b7d9e9562e0c0c7f27c880b6d71aa00e97a10490b7a421e5215900b23e0281f0157683180ad0c5b5cd5df21efa30f8d0754026b460f031bfac68371353c4d3cb158ddfdda3c6b3e6034d78e78	\\xf058a9f132d666df9fdd288cceab4d3594853fefc8281ad55d382f6a1daa8a48c0186e329849c302cbb84d16a6043e88532bf40fcb56d52460ec6ff27bf8d7d8	\\x2e33845a47f267b46af182545442e2d6f6ab450533694f492d882484dde35e0d96dbb5ff8455f6c841be7dc53c586a8a7196ed48d10a25eae6ba5d46357d9b403b97239a0857cd7e5999c015aea88b62c022ed19968c2f52dbe008db2e7730085c743bdf8fc8e7b612a25761eb6d9ef25ca5312f8778760267e95124022a4010
\\x0f578b3844d553d6e49f0129f33da63be21a21b29f2d21f59ee0ee875b5afc176836afbd1bbaa507b10c5e996cb23109f69b5f034d9f9d43a379590da556e077	4	\\x510ee3c3a165c84bfe5736d9567d11973696f695dddc5d2233baa8a1e115e56dffcc6ee66f36f9488532d33f920759dc19baf4a75adc1784d02cb5817d24e107	\\x401eabfce5c5cefe6b489e963f5c81d5b02004f76d5968869cb843acf0571bb0d396eb4914253f4a0c862955d7eff492d19c888376d324898d7795376e21950a	\\xb20b6d36a3618eb20b50b993b3141088f158bb278e2492630d68b18b81919ded8285cb4d995f8ae5b95aee3f5bb4ec316ae981ff6d80d663dee66bba6671502cd1fdb3dfbc750f9830a2820356404b5dc132de1a4848e2e3c438b1db6e904232bae581116c323ec76dcd9aaede0627a1447082a9cfca22bb6597a5c3e9fe7ad8	\\x7d82cbc16f02b02a44ad800a7f6dd937df7c91aafcc8e46a7f0ccaf207be58924a93205af638a71403065cfb4028bc1f2cab8d6cce9d77cd09f50747d97863cd	\\x26d2715f1f7d49e18f6bc56afbfb139bd2088be3ff80870dbf500670365c7357ce418b143178c8fd6ab9533afffd79331d11c319af21b3a07a71290f417beb5d8bab014ace02f6aebe5d77b05c28c7a887391b001e42f0f391f4ade8d21cd33a93d08035e9cac1f6a18f550838ac91255576ccba469c5f3f3a7ac7921e53c7e1
\\x0f578b3844d553d6e49f0129f33da63be21a21b29f2d21f59ee0ee875b5afc176836afbd1bbaa507b10c5e996cb23109f69b5f034d9f9d43a379590da556e077	5	\\xdaf25a3ae4aec74e30720beb253ee2a5728c6892d1047b40e879c71ecfa877f0d642c66b6222ef38302334160b1acc60a9927ce9ceb46cd0611c08709fe05109	\\x401eabfce5c5cefe6b489e963f5c81d5b02004f76d5968869cb843acf0571bb0d396eb4914253f4a0c862955d7eff492d19c888376d324898d7795376e21950a	\\xd03c901f3c0a19428ca82e0bf814fc52e3999304cd36a89ef7ac27bb92fe9a18e30f441e857f69f9018d1d81b33031f4f61d1785beace96c8a7a39403cd0f078c74384495af970204304bbb68d266500896a8b7c70a13e5408e7a9944d22aaadc554d3117d46fd7fe7c6822516961480a384fe37c577a00480d6172f00b75892	\\x56fab2dc75a890c33fd97f5c8a18ff2fa971cd7d537178c9b5548811958fa1dc181896f48979f1ebe9451d5b3394a502b48a309ec45ca3eba04842028162c2d6	\\x8aaabea87b34d984e5cba8a9e8f455afd8e5dafa3ebb2709f00377b92444e4329438f62fed78b12320ffe8617cb0ef98c4a2c2cafa773a2571ebe2c28bd8bb246172c3cbaeb73401afb924539513f2f8cbc0f232a0b5c04fa91a32edbd74d368f8058c773a80efec2decd0a5b1f3a54a27c3b1d9355dbf0429f71b012ee22756
\\x0f578b3844d553d6e49f0129f33da63be21a21b29f2d21f59ee0ee875b5afc176836afbd1bbaa507b10c5e996cb23109f69b5f034d9f9d43a379590da556e077	6	\\xa346ab87360314a5a1ed4d2ca6dcba61be3eac6578be0c2946bbde6c1fed3a45223aaf7d039af6c426787e7f853622036ecdb20e48d48a7627d3e30e1a57010a	\\x401eabfce5c5cefe6b489e963f5c81d5b02004f76d5968869cb843acf0571bb0d396eb4914253f4a0c862955d7eff492d19c888376d324898d7795376e21950a	\\x74dd100dd8fc3b56e32ec6743eb6ab7cef81447877b802ba983195c2a7140c9c5a70c469d678013df43f029d614a780f26c33f7bd514c460e99bc1a9095ce26d1fe7e0ad73a583c6fad644f223f9074654320c04780db20b4154eb2dbc4d7cb305565d400c775206097d35d43269fb6efe5a5a1a5036b148c7ff5443559ac629	\\x84f61523fe847aba57d0a795b00fcf721eebd613c2f7039387a468f282089bcb2fbe0b180a069de1c55f43fba616da11aeb331fc411355908c430cbdfa4aff8f	\\xc13db998fb6c2b0f0426392ef72b69b0a30510426f041bf4c41e53c4d5b0451a6176520cc57b22ed36c57c8c85a6d08da510771dbe57fa5349cb73ebbd8c1bf17f20d0d12d39055e6f2bb4b133c557edb109bdbda50b6dfe34bd10fa216e1175252c8b710e2388319de2d7fcdb0fe1ddedde157e90519f36dd7abeeb34c55f20
\\x0f578b3844d553d6e49f0129f33da63be21a21b29f2d21f59ee0ee875b5afc176836afbd1bbaa507b10c5e996cb23109f69b5f034d9f9d43a379590da556e077	7	\\x4a68564aa8ccc7f2ef92dc76b6a93a9bf0a24185add55583c9ab49701229f4bc79a3b01c62fd02b39ffb5dbac157774950891a780fd3a3bd884c55342874540e	\\x401eabfce5c5cefe6b489e963f5c81d5b02004f76d5968869cb843acf0571bb0d396eb4914253f4a0c862955d7eff492d19c888376d324898d7795376e21950a	\\x7327ccbc7453ec39fa0314d3248c8e508a6316b0407941a662ea4c438c74949da5a372b08cbf542af45f5492097d9e0a44384cd1cf984551b357bed941ea890d7e3cd17e9735837522f39645e62f79871585f8033e3a9576c144a8c3353dbfd60c2432e248b6d871d3b43fcaa593bb2b2a479781632db20e11b3c59daa9045cd	\\x2e2481aae8b469702ebefb038c9ddbd364afcbdfcd779d22e5583da686343cf5a5e09521e2287b62d31b754d61abaf968da955f87b90ad25306bdb7faa58c3cf	\\xeaa4c94d6b26a0716ec167a605aac46eda93b6b5f164b0c8959e8037642196926e1cf7ead48baa112071f05e6606fd2fd3e3961189509b74903a0540d26cb03659fe6a82bad4047c5d62399a3eef0e652eab0a675a9de489fe00a6ad4ce3a089845e0af3ae2704d1fe5e5f4a19922396007559d839200c1d73376efaae743bdb
\\x0f578b3844d553d6e49f0129f33da63be21a21b29f2d21f59ee0ee875b5afc176836afbd1bbaa507b10c5e996cb23109f69b5f034d9f9d43a379590da556e077	8	\\x4e5e2e31db813b08f78930633ddd85d984bf268140df86b5b2626b6135356f62ab2bc09e6311824d48b4117b76b5b238bcb6da371b849b49cca7a1903bb40a01	\\xccedb56d361d4983321788041be2be9b2b9b122faca8fb3550c6018f113572a57dc032c1bf77c484119d750a2a7072c062885cf8403341f91ffe22d8b7f678e5	\\x87fac7d3c6663ac9faf79d284fa4c5c05cc1293e356ce675d7aca9343637201b8fbe39af48de55b782823e8f3af0ba1a5e867584fa0f35c42c790e15a8a03e54cf0485e32184250aaaca24f94df78bcaa13931c987cba327736b47f3fb773e18bc6b634c488686e4877852731e6f26760cb2235cb53795a78b146c0e6c8518c1	\\x907b461cd65c5f7b69040a4f8d675403d848d6c428bb358d39610618bbf9ada14b6a9abb6eccd88355ad1fc5ab973728ef1d33f00ad9d3d9b81b570eb987e0dc	\\x7c4edd63d2344a14c7c9c303dd7e4956b7e547596995b04960af6312669b0278d60a1aabb15d3dca83298a249eecd3c0644b833363869d7b81f2a2081be5f928ddbe4983a467a5a6379e242f32a8518281db122c26dcd92b61f2aadb8d3afc65fffeaedfa3901fc39f42798c1528e3ecfd73f779b27df21e3a9de52185d99494
\\x0f578b3844d553d6e49f0129f33da63be21a21b29f2d21f59ee0ee875b5afc176836afbd1bbaa507b10c5e996cb23109f69b5f034d9f9d43a379590da556e077	9	\\xb50e565a98e55c62025fa49e65d1f14d4531c6126a95cb8eb12d2ff710fccb9ae80adcb48248ac1fd83defd99417e7f60221734187cc549605c474392063f003	\\xccedb56d361d4983321788041be2be9b2b9b122faca8fb3550c6018f113572a57dc032c1bf77c484119d750a2a7072c062885cf8403341f91ffe22d8b7f678e5	\\x337a4afc5ed4841463287ebf00092e13cc42462dfbfff37a0829fbb0653051024b588e547e826cbb280c17bc54fc195d811e7893f235b7b89d0bf06eed101118877e223b34dc6b07ab60d4afc921fa228ac7af831295598c815ff01658d5ad802f86d490adf430b268dda8ccd48f1edab5ecaa9a457b70e38842022f399e2ce1	\\xd2a88e2eafa314859f1a0dfa11767c43e292c8bf464df51ba07d05d4db2337bc8ceb90db80b74afd766af6d9166ede4e4f3dbf07463c2ec39361916ed3372b9a	\\x7da763cab44580bc50b2f2a0ca873058dae60f527a9bdc456ece075671f0c453723362712861134f4c3521c44f2bd06648cf9c98a42cc7ce45c39ad08a07988e009475da24fe02bdb041c9e219a83d1db83c495d7f2e75ee6c177729e68aa06e9705ffd3b72449386239a8105c49a94accf03fe4ed88a705e581852ecc021aec
\\x0f578b3844d553d6e49f0129f33da63be21a21b29f2d21f59ee0ee875b5afc176836afbd1bbaa507b10c5e996cb23109f69b5f034d9f9d43a379590da556e077	10	\\x16d7e90b516b14a492d0ce74be87da895f4e937f33240aa139de61d56ae864e6c68be687839750e9775a309bec50ed47c6f5681f69254d9f8ebb2944b87a000f	\\xccedb56d361d4983321788041be2be9b2b9b122faca8fb3550c6018f113572a57dc032c1bf77c484119d750a2a7072c062885cf8403341f91ffe22d8b7f678e5	\\x3315468438bf226ecfec84347048c96c18cf55193bdea8f94b99b820274d1b75883565bbfe7f8403fd5eaef44c6d6ad0abbb9ff80301d48521582c6700973549c423ed532501aa4d7e71ec6f6390d550d020b3b3f714f01f53007fb3f7edc5c67aa977832319b10bf1ed59c98afebc3cc951ee468769dcb424142c3b41a7fc4d	\\xeb32d4ad46ea77dff4e437bd46d4bc99180e9fff8c43ed85eb9f7e15d6ecf258f5b6fe42f5bbcc047d6a12a12fe3b1ab919a236e9e2a164b6fccd1319e4001c2	\\x1327548a9aef00707b0a17fcb1c1c789820962990fca58911ddcd81a545ac94e66aa45b3b3c4de383f94e9f8bfe385ffc4f1317b836ca172b23a800c5600801a36ded9f08f5bfdea9a961a9f4b6b9976475977e0709a018e034a8ac31b5198a53730e24a2a66f563b3fab8f88d816e17f17fbd4b814804ce57b576e9475904f0
\\x0f578b3844d553d6e49f0129f33da63be21a21b29f2d21f59ee0ee875b5afc176836afbd1bbaa507b10c5e996cb23109f69b5f034d9f9d43a379590da556e077	11	\\x1070cef2e86da31b42e09ecef2ee297fe1531b73af86ee2ad478c9fd4d5bfe6ba55daf1cebb89bc62d9bd37e9742987d54bdaa0ca45912944e91c9bb7846a305	\\xccedb56d361d4983321788041be2be9b2b9b122faca8fb3550c6018f113572a57dc032c1bf77c484119d750a2a7072c062885cf8403341f91ffe22d8b7f678e5	\\x08a0082810e7f4a4c12238202d77f01159d79231afe09f3a5e7abcbde6f947662d5af1cd25ca1e31a2276bf44fb6950c42d2d790ca207050986c06d757639aae5f48660529594150b61e8c1ef2768bafe99136c90859ec74398d4c153b91e16ad8ab0a2d00b341266931ea7d252d62c03f4d584a4bc75ddafd91bb011e3b1372	\\x7f0bb8ea1050b1829e88573db649d893e3bee483adbea3c27275c8db62eccd070ab9ae1b130fa373b4078369a887ec5e34da2224bb80390ae4483de78f2f2ae3	\\x1990c6a615ceac1687060b8f754a169fdc4ef944c73940738421654673187f5116393818157016e1b9b3f266457a4cb8201146c1f2c4490c0025573cdb46634ba4e0c0808ee1db181cb1b5c3224044c23fac265a7c1a7c9b42ede57ce312f5422b76dad6e9ea58bc4f0b6516fcaed65e2f62bcbc66f97f308a6a55728f637af4
\\x4ce199a576380def2457174f34d25b4e357663d951c95a4af6d3ea34a144b4e06f16c215d99cda85ee374b6b5056e40edbb2faf607ec2bee7b668bb9e502d64c	0	\\x302930bef02de774db16d955dcea7ce6f792db37099021920f62b05a7b8b5d427503f73cc97f6efe950e55bfd68dda683d492e21ec7e0e76cebef21dad1cc70d	\\xd8d7b08143f2844fca7a7c745a5c43a91945f2f42166ac2eada3e89009dcc661c80942d0d9bf8b0f0b560feb511612c8e4dd3060e9ad9aa6d513ac1f1bd56f84	\\x58bb55b3cb2c10c5b25d3adde7e224b442aa7738036664589e2525bb327e7ab486079fc548f5d073487c192970888ceab628fd003f1cbb11f25a4c32b33c7f8e5a6085ac6d496c6b6142b75f66fce35128d5f039574c3bb5f5137c9b8410f40d9ee0ab6a9ab8b8b9083a6fd7d1e136ea02b420e5c9441d95d2ba7cfeca3321c6	\\x871d037dc6b819b4a3624c9c8e2cf309acc236ba7afd33a5a156b6986d5e27dd59c7b8c60cb9a38fb37a1b807c705407c442bce48b994d7319cc14b51fd86d08	\\x97d9339d43c57ca67fe2ea44b68b84f030b4bc86b290e78a3a2a0402238aa9b9803ea51d8552151131542d453e40c82cd82c47c25f122bb530f13646e599341a4b139e6660c44a64c293fd0ecbce275f41249413c9bd3aea86fa53ad24f9d19116972f21e0362b6f43a4fd00116802e2988dd2fa36f9c43571000ca4c4ca2b9d
\\x4ce199a576380def2457174f34d25b4e357663d951c95a4af6d3ea34a144b4e06f16c215d99cda85ee374b6b5056e40edbb2faf607ec2bee7b668bb9e502d64c	1	\\x144fa9c4c32aeace073888cdb5741c2543bc1f96a96b0b34c17438f6dcf753656b3b8e4f0458b8fb5e556f85b77a356b7d101e64f7b482e5500b26a972b27001	\\x1b3e0100937fd48380574273ecb350f8b2f4b945b8944153a7d5be8467a144bc87ce33d2528b7b2b1a129e10b98ac7e48a79db395c9beffad08fa835619daf1f	\\x6137cddd56dd8edf0795709ebaecbf2288840080d40cc347b28c818742f61744cb7a6bea9d4a3cb6f809a0445bb5bc3e698fb5d2600cbee229c4d90ed847bf6523f7d7adcd4d30c6ce2c985784e1735373ac52ca21fbd230ee7fadb8cf59322ed2f734556842d39f8bf8b708f661fd0bf675809807124321e1f078206fbd492f	\\x076356c4b1cdd125a827d18eb2788aec8ca932b2ffd07be1b119b598e7bc6ba11df76c52d487400f58c19e9f73fb953adfd1025f4fc95f4caf1e8602e677e8ca	\\x1ff2a28f71fd7bc80b0d8bb07c307f747cc5969ae78bff2634c5dab5534637f1d56e371624346daaacffbdf48525dadf4d149ba50ed8109b56ce69c5df13649f6e5f05346f44fe5231d5f814e4968ee59d8f288f3a67dd2f3137d81f7fa0d64110d235989dce503e802bf9c04a4b8b20d33c478541834c5157ad4857f052f4bd
\\x4ce199a576380def2457174f34d25b4e357663d951c95a4af6d3ea34a144b4e06f16c215d99cda85ee374b6b5056e40edbb2faf607ec2bee7b668bb9e502d64c	2	\\x8937354653e8199d861c42e7a5888bdfbfc04223c43e8fa5961569dcd11fcdc8be268c5408eb610bc306b9a1ebb704871d3559ad5bbb62d7c41d8eef97b9d70c	\\x401eabfce5c5cefe6b489e963f5c81d5b02004f76d5968869cb843acf0571bb0d396eb4914253f4a0c862955d7eff492d19c888376d324898d7795376e21950a	\\x105a983c8af210c1cccfb4125ee3de603349eb6106ce25cb463c7d2ca9c0e3ef59237d511e5e8ebb7f2fdf4c26140359f91ae2d60c11978e8d910c70dd4746d3839a9422d076ae3663b49bc54ee7468d1f58140e1a2a92797dadfd9ef2a4ac7ee54317202f20c4e5ff09fa73630d646db44dbdc683acb32d4cc70fb1f2df0f1f	\\xe5e5be01270daa1805cd637a29a761468a9e69449bcc43f6b7faa499ecabe5b7c1c9e494d449190af00ae71bea59320126903fd3236d13b14bca06428735defd	\\xb1d38a640c98bd7abcc38ab26c1a611d397ad2d43829957eda75acad53627a034308e726dfa30d3d49431e77e44fae08c34dbf47f4b9d06e8af33db03e3f5226757beac9774481af57d9875d055d301e4580211e53f4f0a979064f7c730838ea882429785ac6829c4c8a7339bf5f60a4c6619ff20759df784dbf6d4e1b19a5c0
\\x4ce199a576380def2457174f34d25b4e357663d951c95a4af6d3ea34a144b4e06f16c215d99cda85ee374b6b5056e40edbb2faf607ec2bee7b668bb9e502d64c	3	\\x946de9de7bd63d2f2f5ed26e70260a7a5273fa9e77c740bed7bb2404de7a5d838e113c729c7b59610965d1624c2b373aff5cb844cceb9f12dbd28cfc1aa8160f	\\x401eabfce5c5cefe6b489e963f5c81d5b02004f76d5968869cb843acf0571bb0d396eb4914253f4a0c862955d7eff492d19c888376d324898d7795376e21950a	\\xb0f521c8d59c88cc2f6dc4cfe6ce25496eadfb69b0d3f3627996fb8869e1e247a2af253a49c824b8539e959f4dce150e4263198fd6b2b00e3ad1959212e596191e0f10eb5eaadf0d6d255b2a1bd86c80aaba2127fbc52a55dd7f1a26cf6626a597033e5b830e50a4ad364b0c3313e286cadfebb0644825d2bc9ffb0f2044a261	\\x3ab452d0dff1f38543e96964b66bd453d4109d47ccd2d56ad5e9cbb5b39cbfe21dbdd53bfb612c141af997166f811114ff72e505edb1f9c5db16929ba4ee70fe	\\x03857214c93e8f3e32998eb51fd03848d855d1e77c9ac32e350594f81bd5beeaa0d5a4a6f62793b55f92bb68376b6bdce97e668f4ae6642f0b20b57fa05738614968dac8c964f7079a9b6101b33fb6241e8b1bd73829660035fafffd3aa2667a0f9840946b92738b240c8fc9356727fa9edf859c5d89a6f1b570c5a41e04df1e
\\x4ce199a576380def2457174f34d25b4e357663d951c95a4af6d3ea34a144b4e06f16c215d99cda85ee374b6b5056e40edbb2faf607ec2bee7b668bb9e502d64c	4	\\x54f1d4ba4741f3e7adced8e5b6c1802c22fe3706fd1aa1e41303e866ee85ebbedea13b26a8e87dffd8e4c713734e778f65ff9cb16115b7a0df7214e0ff27770d	\\x401eabfce5c5cefe6b489e963f5c81d5b02004f76d5968869cb843acf0571bb0d396eb4914253f4a0c862955d7eff492d19c888376d324898d7795376e21950a	\\x5029b71ae889511fbea19593f8c888aa140e49502c7371cba1c2d0ecb708a961291591e392b59b036b89b4e61612350d0d8d064a9632da4363c509eaf4821cef02a3ee69185aad02bfaf606d994b3632b02b5ade27d62b589758788de23d012e62ebbdfc3cccd519a93e7c816be2e2aad4515e7cef4f45d91d1ee41c3c740055	\\x19588b03971242a80783cde909401baffd9f174fed761ccd094ef5734e4ec76540891c3f2c5555ef4e2f56b3b2a41d5a21a84377108178d80ed5c9cfd12f517a	\\x75f08776465ba05902bebb52e847855851fa53544f6e5652a687afa8bdf0da0ef0b7b1a51d2aae81aaa7c959b4350709217a9a76e7a9869f480a65f240d38249520ca943009e61ad3133f9137f2e8977eb0c4ad73e2231c4009abe9f03daa31b4f1268716091b12d31c2b3aa0d8820fa29c1e2dc85fda03c86557740189e3bb0
\\x4ce199a576380def2457174f34d25b4e357663d951c95a4af6d3ea34a144b4e06f16c215d99cda85ee374b6b5056e40edbb2faf607ec2bee7b668bb9e502d64c	5	\\x5f76bb2c2d005399a1038a8d82c35be418bbde1287c14d822555611285265e1e5a6c7020661b3aed2c45c23d9fdc2ba78c3ed95478d8a6792aa95ad14d45a70f	\\x401eabfce5c5cefe6b489e963f5c81d5b02004f76d5968869cb843acf0571bb0d396eb4914253f4a0c862955d7eff492d19c888376d324898d7795376e21950a	\\x6a6672ce88c2e1f4a7f17a899184bef1e50e8c0591ad1505ce6e30f5aaf2ca8e13d6b6e52f2f8e6f44cb6b2815468c9f6973e936700d8ba40d308775b33f7f3930ceee6defffa4102fc4319ca9251ea4a2baca0c35770a7d58d2d1d46ddb5727458e8329da093c73c9a891678bb0b0c825c91c3b5bda4c96c246c6e9fa8ec375	\\x72bc93ebf8a5549fe21d893a6d07f27cc92f8f685b4780b011a39e9dca3e18e9b19fb760c26c433c9c8ea0569d256bdbfce8e5c39e9c8e0ed44ad697afe45609	\\x79c4fd85e896a785876ac91519f00e0982400a669f7aebb9092744c9e80fa0bcdf66e50ffe7eb20767fa40c31a9e11d026d7da59bf2bbc8cd6977e6cfb512fcbcf46fb1845b1cbe1d31c7661d421c551f7ea44d7ebeaf4baf5ef5610e48f5e6ac53023b1ab3d70437959294d163149c3088d8f806d0bb054687cf202ef49e5de
\\x4ce199a576380def2457174f34d25b4e357663d951c95a4af6d3ea34a144b4e06f16c215d99cda85ee374b6b5056e40edbb2faf607ec2bee7b668bb9e502d64c	6	\\xc82d021cf91b8d26bbf832ee95a624bccbd531d0b0c8e7022c49ef0e2169692c185f36bb9bdc084d925b70436fcf97571c8a34ca88d2fc45f9408a1edc7c340c	\\x401eabfce5c5cefe6b489e963f5c81d5b02004f76d5968869cb843acf0571bb0d396eb4914253f4a0c862955d7eff492d19c888376d324898d7795376e21950a	\\x38a99d7f123e9d9749c1ddd8c575901958069d0deb9b40efc6e2dea4ca86bf42bce02db162e7a2f682215d10fc862e6984d2c3e56fb32ba5d3f08e3cc42c21c5525d8676704b0f2991bc11cd4002007b94507a4abd19c0c68814a0d5d126806d26f310819570eb9fcea2a6603125fbfaa7da27ca18b66e0c66b188c11384ef84	\\x5385b1bf0ccc697a90098a261df3b5c0074cdee1e4169245455c888a09be6bfcad61f9324c06e6fd84f7ed391248c70ceca05297890177dbe375b4af6c1d4255	\\xdf149a77a2b114e3089fda65f8ad80ac871168f9c50017a95e86d4f3b337f005167b7c18a68b714edb9e82a12fdc844d1da1ebf2c8dbbc17b9d7520c0d1bbe02ba975e56c4e461c284d8aa550ac8f5e1ce05f357764b16514050a8de6c3643d1a4e2f2e01a4f7de133f8e32c1ac895313ebe015c02394746ad8d7a7863ee686e
\\x4ce199a576380def2457174f34d25b4e357663d951c95a4af6d3ea34a144b4e06f16c215d99cda85ee374b6b5056e40edbb2faf607ec2bee7b668bb9e502d64c	7	\\x99c2e02950995e6c6e4e21004685612c48be1422620040d9f4fd74c80079ab73c0357567aaa1e054237a2c02326c00516b6c58fb8c325e4b546c98e57b8cfa01	\\x401eabfce5c5cefe6b489e963f5c81d5b02004f76d5968869cb843acf0571bb0d396eb4914253f4a0c862955d7eff492d19c888376d324898d7795376e21950a	\\x272417c480013257bb254f9c6210738bb3ffff67933ed7e7df5551bf0eb7a43ddfffb57151b7ade64cb66a59c96ec59b81c00d7b5d9736baa55bd5097ff620a2b5df908fa309a7d56a679df8deea5b788520e5fd6f593f6b101b7fb373cdb6ab7b3b5f0a79b4f946bc6e5d3d1627d1d1e33bda36223fc9774affc4b862341a61	\\xdac21bafc8fe8efdd5c382dd9e467f2c6da2c228115b6a18a9de2e629adca6fb1d678f687a1e7b01d7f47b86eb4170faa8bab4214bbf43271b8efe1196c676fa	\\x55531ee39d18578fee5ee2a36c3796a3dcc218cdf73d601551d11eb629c7dd777754a059ea7dcb6c0aa531d95d8bfbabf6d28208a30067e6ffbb6710659744b0bd48196d8c2f31d6705a10a2253239776953a85df274e4b6be8347118db4b763e4a7a46c8a56b3a7c6ca6a2fea3dea1bd9458faeb462ed48ea2444c721f4618e
\\x4ce199a576380def2457174f34d25b4e357663d951c95a4af6d3ea34a144b4e06f16c215d99cda85ee374b6b5056e40edbb2faf607ec2bee7b668bb9e502d64c	8	\\xd222fa733e101c26c1eb2f6b9e1646d4370d5171d055828e4fb864609fdf304971725faa7f5379fb9d297f89e3d5faab57ec3fb8f99949cac259ee510a236f0b	\\x401eabfce5c5cefe6b489e963f5c81d5b02004f76d5968869cb843acf0571bb0d396eb4914253f4a0c862955d7eff492d19c888376d324898d7795376e21950a	\\x7d43c3558e55e3aa07743cfe27fe329a711de325aa3ae9766721a90e08b3ddd76aeceeb3ac111a397f22f22720d645bc7306b86c8302c9ec43756ac34fb03233cb7c32ba733acb51b7c39def3880e6cf18054b05251efc2dc10f8829e50215e187f1e814fad7e8bf91290b5bb8cac46ce26116fbc7816d6223b5e52fa50e36f3	\\x043092ec349d0524d506984574c4554f3ed5ac13d86c1de4ce48dba8dba643132ff2b2c720565d7bc15d87195c4915021448cfd0fdcf2e74b80d4ceab10ccf56	\\x84fda106e55b309b719841cb257b3fee76c2fee59111301aa5b8261f86459a445791d9ad96e67d0168ce7ec25030faadc5da87c9fb8764a2e79f9a0c47bf4e6318df2800838d0da1c079af0d4ec3479f04cd75bda2e36ae2e49081f744c916b3719e08eeea9ecdef934157841481f66f5f6a8cd4686f4e0b31c877a6fc0ddf26
\\x4ce199a576380def2457174f34d25b4e357663d951c95a4af6d3ea34a144b4e06f16c215d99cda85ee374b6b5056e40edbb2faf607ec2bee7b668bb9e502d64c	9	\\x784008cb380d71f16bae89375da11708d8c116d50f55a2d89332b813741346b29bdf266df398062e3e6147bad538ca89eadc212ddf3271317676bba0bc6e410d	\\x401eabfce5c5cefe6b489e963f5c81d5b02004f76d5968869cb843acf0571bb0d396eb4914253f4a0c862955d7eff492d19c888376d324898d7795376e21950a	\\x74b42351407a9cceff41ca0e2b73118c355979252bd6fe94b7c48ce6e33250bd9363769535ff733db2874c2f84ae4d916de79cef8ca5b9536cccc53dc50fbaa5e543008ecba62fb346c08b7f04b52d0421446a25da39863353510c86c38c80f9f492736e78478f0db2678da52712bac4ee85f487318fd259187cf56cfa69142c	\\x6d26315f87705fa39f1221000eee87778d8117e5a2a5cf65934d41e2cdd17c3c3f774b912bd35f3f3483dab0ff97896a7791633d53015934af50268261e17390	\\xce4d51231c2a83eaaf6dbaec8e45cef30da021ebf6b7275ec0c1c4a15c56dc82658e897214729d44baf4855ed7fad657b2d161e332880ce0c64d82cc1b29551d80563fde7f0b66a22adaa019dadc99575bb922210b74ad3c135f323a6c0545f810a4c958f454a8bff554f54c353134b17cf452edae721d75b2ab9a1ceecc254c
\\x4ce199a576380def2457174f34d25b4e357663d951c95a4af6d3ea34a144b4e06f16c215d99cda85ee374b6b5056e40edbb2faf607ec2bee7b668bb9e502d64c	10	\\x83d69526afcdbac039e22b74d8b1d6cf64b50a2f8db4294ae02a02dae5b60d36dc72da336705838904b33c96124ab9ad90a0ed9f6cdab88f25575ec773f62f0b	\\xccedb56d361d4983321788041be2be9b2b9b122faca8fb3550c6018f113572a57dc032c1bf77c484119d750a2a7072c062885cf8403341f91ffe22d8b7f678e5	\\x6d5e6903cb5a842e4be468b979f652ca2f981d8dab72ce9a6bb761afc3e16165c9ebc958b17ca552fa9d3668b4cef6849960fac74407214984db54c849b973448093509994f4dd67454e80c959c701d7813b66716c26d5c6ad3f09345074fe671f01b8e187e88397e60b05f6fe57b7ca6408920ba5c491f140b43dcd051288c3	\\xa5c546b8b67c140a6958902fb340118d5205d184763883181c5cc3402610d6f52c468ca7b2100098f4769b0841cf7f58f9bdf7d4b179dc852bf1c4ee2d499d6e	\\x6975b8d5f5660ac73dba02f714becb9a297e0b70a1af4d7391b4968b6d0ab716b27cc23be67efcc33217f9dbe18bc7f1f4b4bcf8b138342334ff673b9cf51e52639274fcac3df12ed347457ad0490fdd9b799a275aac527191a64d993017c9ea11eab56e0a61525343a865b3446b800eebace879b324b30b2a49d24f9a073d3a
\\x4ce199a576380def2457174f34d25b4e357663d951c95a4af6d3ea34a144b4e06f16c215d99cda85ee374b6b5056e40edbb2faf607ec2bee7b668bb9e502d64c	11	\\xb1ed153d414ec41c71338835353febb7e3f300988bc4bfa40d14a229c85186c090a7c8bb4f22a3c340feb163edc0dc8b81f00a62712710c1b17a0563a870440a	\\xccedb56d361d4983321788041be2be9b2b9b122faca8fb3550c6018f113572a57dc032c1bf77c484119d750a2a7072c062885cf8403341f91ffe22d8b7f678e5	\\x69b3e979a561c5be9fef37e77df06c650517eb51f11d15ac2ea05382bfb073d999bbda8db8843dc47915839c13724defb0fba93ca5d12d5530fc918e553d7abb1fd3171ee626958e028bc79faa2fbd7184cdba9f612392a6ff9584c0ebef3b14c30aaeced8330cbbe4ccb0d3e6a79b2a3565760eb484f8f838f47edcded6998a	\\x801363bdbb5535141f3127ace2a2e610876a8bfe183d46cb268e95fdad578008c5de7148122c2eefd24e615bc1f0baddcd4a93ed17f4b31174c8683c3b6f4fe8	\\x88873520f9184da05c8a3e2c4c300401b8a4d04aa47689205a438910fd4d3cb1c7d91f6da586ba367b045ffd90d66a80a85c52f2c13dc9137098f85f0f09fbaa05f449e04b30a1c572964d33af4e0b77d8017e48a83a3c5358ceb0656319d9fa43b9879d6c7ce054ac6d6144f237a43cfc7f759555af2b4aa244709c3784b309
\\x4ce199a576380def2457174f34d25b4e357663d951c95a4af6d3ea34a144b4e06f16c215d99cda85ee374b6b5056e40edbb2faf607ec2bee7b668bb9e502d64c	12	\\x678e840d45daf7281c77973c602fa5ced1bb00e3417cb29fb9b244be670e32781dfbaa3776f82d56394415440319ada7e7e76f2921027cfebce2079eac7f490d	\\xccedb56d361d4983321788041be2be9b2b9b122faca8fb3550c6018f113572a57dc032c1bf77c484119d750a2a7072c062885cf8403341f91ffe22d8b7f678e5	\\x355beec19110e40d6aa9aa38d53c7e316d33c53c6ab7d5aa4a0d8988cd0c3a34116c0a288821c6ee20160bd08cc6a8c5df4f6e1ebbc49c65094b41aa4301f113ba0c8f931ab5247764475f0e0d9285caff60d6e085f3158c2fc1eca8b8957debdc36b0a6ce43546e05a2f5ae170acc098e5da13417eb98d24d167860ac8c0e48	\\xb3db19a8a086ce4ba027ddb4e033378fe932982945b7a74f888b1dda2b1ca39c331043428692edab376f3678ec861137c5675de2d70890cea03f80aedb10dac6	\\x048804e4683a53a180a38b2222adcd9a591d9b67128f9cab127f12e75cbb8476676c6e54bcf175dc7fd42657f222c0da003f7a9f0c68e447ae86fb74fafc1b5dabbb7f048dce84713457559821ddd1b7dd002fee64d334971d4c57dec08915448a572ab6c47dc324f142898e081904172a0e003c167addb54ffdb4aa2be1ecfe
\.


--
-- Data for Name: refresh_transfer_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys (rc, transfer_pub, transfer_privs) FROM stdin;
\\xb14898b2f3f8dcf3df86fae9049c1992658ac3bacf5569d7a7e2d6cfed9d1abd950a748f8f72543de5aff56d0ca59f6ceb1c779a6c6bdb5f64a5332405c73f82	\\x59b05d495d63c29fbe528d936f902ad2cefc7575af2b94532438e1d1e2f75272	\\xe2d4bbed45d2f5ddd0106fe903eaf0fab2358538b3bc368877b7ad29f113e1f3364a53fc1814fb5af4ffc6e15d90de9c18b19a17689375d6ba87a7f4071db873
\\xfb4bf584bbb78084c9ea469a5d8e0069e90041b66a06ddcd1eab78ad6163402a1978753b3cdd911e5b95e1fd72273ed9fd0b8f6301f09aab6303093cda40e749	\\x9c408b61d721f539566e3262db64fc8758c3f8b8629d649ac918cddc31b4b87a	\\x071d414e7772e81114d484037a3445f57c5ae7a1c66f8131227656324c23ba3e8036bff6490a79389f7108f4d8bd31a8160a93268a2662135d53dca9703a78b4
\\x8661ac5eaf06e45f16446825d8299b52bdf1bc37fae457e114b483a4bcf4963d78d472df5d2ba4ff422350c0a5c45616b73709263de7bde4a2dae319e43d096a	\\xae3c77125b6c356498c3975d007e0e9002638cd7eaa890902dd9cd588131f110	\\x4e0f1bc1831bf8726df37091c5721051d3dabab7cf478eaa03139d5eeafeaeed96b305576467e18ee2424b4ced19eb27b91c92d660366ee3757a183101b00aa5
\\x0f578b3844d553d6e49f0129f33da63be21a21b29f2d21f59ee0ee875b5afc176836afbd1bbaa507b10c5e996cb23109f69b5f034d9f9d43a379590da556e077	\\x031045dbfd04bacc1dbdf58b33a2d134a588eda955ae86e8933a5ba49624f375	\\x3837406929829b5e74c5665f0b35590bdb1aa9f61fe418446cb08614f2af139b67c0c2d1a22ccf3a04435a8c1ac491b61e02253849a54094be0cc681d54ec649
\\x4ce199a576380def2457174f34d25b4e357663d951c95a4af6d3ea34a144b4e06f16c215d99cda85ee374b6b5056e40edbb2faf607ec2bee7b668bb9e502d64c	\\xf1a37773e9d6a4273fb74a091dd8aee12c9fb0c78a9dc719f3352d2d5447686d	\\x59f8bd25eb4f9663a9b8e0e8e6dcc93572aaddfe9588fe82f004fd5d541250769a44152b46f45c79d37e0fc4fedcfe075985d55a2b53ea1c947b24e95efa8de3
\.


--
-- Data for Name: refunds; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refunds (refund_serial_id, coin_pub, merchant_pub, merchant_sig, h_contract_terms, rtransaction_id, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\x364619793416e999dcf6df9c6a16d41387c8b05d59c6015812e09047709875a5	\\xf72f8edf0baf3ce18d8d78e488612b4bafa12f24f1fb5cd87e2fa8b6d86ccc9a	\\x17ba59ac963bfaae1192cab582d3cc64c7e5ef0e3d39d66a07102b453ffdd7469e4309f0e3133e7b421da1cb2d204784e4abada0743c0d43ba13e61ad17f2601	\\x8cd2b92e8e6b7414be40bdb04ea2a0aa8ea16fb14050420957e4ca1d9acb7619f337d1c95d58d1964522b62a15c4db0be8fe0729acbee1031d948c9f3eef236d	1	5	0
2	\\x4d39e16ad825c1d775a24864dfebf67b240d606a67391bd833dbc2a38d6fe8a5	\\xf72f8edf0baf3ce18d8d78e488612b4bafa12f24f1fb5cd87e2fa8b6d86ccc9a	\\x4a42dba842d0f8e53d9d42d8610e96855101ae97666b161d79df23ac899b466bd486dcc870e44f209707c30b29c93de871e5974e748d6593a4367978686f3802	\\x8cd2b92e8e6b7414be40bdb04ea2a0aa8ea16fb14050420957e4ca1d9acb7619f337d1c95d58d1964522b62a15c4db0be8fe0729acbee1031d948c9f3eef236d	2	1	0
\.


--
-- Data for Name: reserves; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves (reserve_pub, account_details, current_balance_val, current_balance_frac, expiration_date, gc_date) FROM stdin;
\\xc4f01a7c2226c71140de19242ceeb90f2c05669587e188e84b83f8033fb530e1	payto://x-taler-bank/localhost/testuser-RLtMLjek	0	1000000	1580166023000000	1798498824000000
\\x0a263b183f5e9a9479d83849b151b29412cd7733fd1ee8eb658fc7ef67c20b99	payto://x-taler-bank/localhost/testuser-JK5q1el9	0	1000000	1580166026000000	1798498827000000
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
1	\\xc4f01a7c2226c71140de19242ceeb90f2c05669587e188e84b83f8033fb530e1	2	10	0	payto://x-taler-bank/localhost/testuser-RLtMLjek	account-1	1577746823000000
2	\\x0a263b183f5e9a9479d83849b151b29412cd7733fd1ee8eb658fc7ef67c20b99	4	18	0	payto://x-taler-bank/localhost/testuser-JK5q1el9	account-1	1577746826000000
\.


--
-- Data for Name: reserves_out; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out (reserve_out_serial_id, h_blind_ev, denom_pub_hash, denom_sig, reserve_pub, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\x1ffa8ff726bd029b06d570c59dce64dbfab92881d15a5f75be4d31cd3654ad125928b70ec09ce9f463f800b1e33dc7fb1b282310f8687ad87c572ca3890d4107	\\x6159cfc0e5a49ef2cdfdf6116f4fda2a8fafe91ccbb292a5c4e816fdc273a6aecf517155709d17d4e0e95d1c9ce413bb752bc192b9dd014f13e352f98d964d87	\\x89403bdfcc6fe9ec815de517ac1c5996a6e9db8c18cbecc4a9d1ec316a9fdfe6278b5b2af11e02c8eacf5d7e4cf7a8806c19909e7e6a1551bcd8c4783dd12ee0cdc7988b7ba2fd729f4e714b808a5d8f90c733634edb194360382ec517ce6a83c847c9b56687ae0f8587b52c243917abbf760ef6d0d560c89a8abfb86e0be9ac	\\xc4f01a7c2226c71140de19242ceeb90f2c05669587e188e84b83f8033fb530e1	\\x7a47ec4193236f8098875a118374e5ddbcd56199a6154c0bcce175c0903cbca600687da3968b9b70c47cf5bb4ce624d8bc5e5410456d68cd3467eb93b65b020a	1577746824000000	8	5000000
2	\\xf9c4facdbcc01f1a220d9972dc1bbcf3cc0162ccd3ef0316afca898e89afa1b31a3ded65a5a35a028660518d9fbe19c321305a260b23fd79a17af95042a8cc59	\\x401eabfce5c5cefe6b489e963f5c81d5b02004f76d5968869cb843acf0571bb0d396eb4914253f4a0c862955d7eff492d19c888376d324898d7795376e21950a	\\x052b511e7200ceab2956feb24ab80d42da4c8c0b82176536805778c7c706547038d95d6f88e678794a69c5348470bd1a8ab1a03961cb0e74b24d810cf6df2236f1022003b355b3372b7d1c829ebe89649b50ed932440ee0ee7963e570d28072663b2fc5f0e78c3db9bde70ed7bbfe3f70c7e6d661faea72bf8b1f9d562193905	\\xc4f01a7c2226c71140de19242ceeb90f2c05669587e188e84b83f8033fb530e1	\\xb43a45ce909666cda572641551c2e34bf9288723e0780f5b3365fade276e933cdfddbe8188501a729d13b2443504ff627bfb20657dc087e00f8921b8d996980d	1577746824000000	0	11000000
3	\\x07bdfdb74c778dd9a932d14c44a7788ecb51f9c599e7a7862b147aa08cc689e4effa875b27db1e0f0b5cab5bbb849a85477bb77247870c5af5cc669f9035683d	\\x401eabfce5c5cefe6b489e963f5c81d5b02004f76d5968869cb843acf0571bb0d396eb4914253f4a0c862955d7eff492d19c888376d324898d7795376e21950a	\\x87bba734c95b44135eda5f675356cbcf38378940a69cd71e6988ad043ca68e210c1b4150accf643ad2ae40c2b0be725bb653f23f88e5c59390687c7e5e435c61a59787882884184012f02248a37f674639f3195a1fde643c4a891fe23c3eaba8e7a47ac42ab142bc825bece73cb1f19d835ec494b40f221e9220f0e6c46d1b44	\\xc4f01a7c2226c71140de19242ceeb90f2c05669587e188e84b83f8033fb530e1	\\x2ccea0af6cfa1a47d12b77d3a7f070b744ac44909b9324a6c855b7e8f48bcb4a6aa77bbe0d053cc7e67bf83332bcf8be6de99389726eb308ca1bab8d12f36f09	1577746824000000	0	11000000
4	\\x05de1148c0343296921e0aa200f8df8ad41b5e86bd284770e64e399ecaf61db402e491a2c2abfdbb6bea89ed10a8e215bdb88e1442f624b9d3e130152260cff1	\\x401eabfce5c5cefe6b489e963f5c81d5b02004f76d5968869cb843acf0571bb0d396eb4914253f4a0c862955d7eff492d19c888376d324898d7795376e21950a	\\x8033c1950ceadedd2bd5a3cfa77947c3970af7e7c587a6c889ce8db49b030b205c185f0ef54aa3ee9a926fd03a7d8169bcef36886d8b3b960c72c6e52d1b8b81a796fdac48752b231ce3f7a6107b2cc78b52fd5295956f714282fc185ef322156189663bdd76bb4edcbc4516d3dc18f19dcca32113efb991496049a2254f8160	\\xc4f01a7c2226c71140de19242ceeb90f2c05669587e188e84b83f8033fb530e1	\\xb55b252181503e33dcee13add6ca48e0f8551933f864b87a82f1b53c3838f8d57fbd6767c2922d38ee8dc712cbf7ac4e0fcbd30f98b1822d24dca79b1744af07	1577746824000000	0	11000000
5	\\xc460910d17f854fb08d7154623c51c566e082e61ee39849570d59b50e4a6212cb9324440e866ee3e4b1f90c0b64a0c0e62ac2ef21eadddc3db5ed53a2fe2bb8d	\\x401eabfce5c5cefe6b489e963f5c81d5b02004f76d5968869cb843acf0571bb0d396eb4914253f4a0c862955d7eff492d19c888376d324898d7795376e21950a	\\x5ba3a967d00a2f53150b91b843bf12b2bd9dae0875fed712c84f540710682a5ba0468da2d5e1dac658cfb42555370d0fbc741f3ddf3a6e11a92341a9c0cc6ab7df97eababbf5a2daef35c468dfedf0900104a271e9dd47bd7a843b9b0003b49b315fe4118e54f3f5f6f1cc4b19a8535e61f10d7946f5b7ce32a32ee690057634	\\xc4f01a7c2226c71140de19242ceeb90f2c05669587e188e84b83f8033fb530e1	\\xadab5a40137c4056b665d8cc770ef7e81b16eaae8fc772bb2eaee3a1b75524966f9241fb3762774af33ba116b5c4eb24844a5edf17fcdc13b517e08a13562708	1577746824000000	0	11000000
6	\\x2dafdfd9fd846f0c19ffb4b309348e13af241ce8fb8651bf6ecb9c14d720e66e072bc17703b59d8f7021ee80e740602368d47fa043e8edd9e1bf46c226baff6d	\\xccedb56d361d4983321788041be2be9b2b9b122faca8fb3550c6018f113572a57dc032c1bf77c484119d750a2a7072c062885cf8403341f91ffe22d8b7f678e5	\\x3a56836aca24e318b6de2dd97e59ed23f161b7f869bca30bb8fa74f89e91c84ba10862bd7c1b9c5585d179ce225fc29975e29923fce0de0f4b426abe578bbb7cd6237830596b93d8785651d87619964aaf54e21c5598445f2d321e9d4782e6b02bc2cbfaba797b1afa705013a4639082f4d42ef3c98a46ec114eb40bd7d7f9d7	\\xc4f01a7c2226c71140de19242ceeb90f2c05669587e188e84b83f8033fb530e1	\\x5885402f882c75f33184000689fdc01a767cacf83f35cccdb2c988c4cad4b003046846625c3fe92a8bfc9a649b5ed8fcbe97d849cfcc5a9a0cdc1f64a6995f0f	1577746824000000	0	2000000
7	\\xff3a658e157a96dafd48110483f72365ae8af9564db0b5188d086658a061af43a44af98b18f7ac91deb632b59b0171a2442aa95bbd291a5ae981fef739cc3304	\\xccedb56d361d4983321788041be2be9b2b9b122faca8fb3550c6018f113572a57dc032c1bf77c484119d750a2a7072c062885cf8403341f91ffe22d8b7f678e5	\\x85b4593e78d629361fa012f1a340382d309b517b85acfad0f54371a83acf9978355cbfadd89f0807fc87acf173a0e4ebd6fa1dc128dbeaa720facabf469d644791b54989e323e76d5474101fd80bfd92b3a10779115b45cdb206cfc3f33e9ed78c01638dec3752b71c6612a7d688db37763009702e77714c11fbb2f9c7b20dea	\\xc4f01a7c2226c71140de19242ceeb90f2c05669587e188e84b83f8033fb530e1	\\x1d6a17027cfaeff026aa438b8188f35f90536968d9222e8e34949584bc8ae21188a4fdaceca2803ac5e73ef4c33108d75b698f074cdc5b1e8b635166c7ffd503	1577746824000000	0	2000000
8	\\x50e1339756beec4678af2f01f670656f95a48917d4b59f557650783474ae6827bfbb5ea6b795e66206c4fd1e3547865dca6c99f7661e461f12b9ab42e5d15c16	\\x401eabfce5c5cefe6b489e963f5c81d5b02004f76d5968869cb843acf0571bb0d396eb4914253f4a0c862955d7eff492d19c888376d324898d7795376e21950a	\\x7fcdca5f24b259987f7fce44ee291344e4db116823c7d7b81f292a88abc5a41d5c6364903cc95801fd252e07440f80d1fbba52f2dbf3788e1fc249bc6362dadc622565e3ac1dd5edebbea4e9ba211043b6462149928d305cb824df660bd545228a453cd35823c2e02c528a7279ca2b95caf983523b0447c749ff20994c124dc3	\\xc4f01a7c2226c71140de19242ceeb90f2c05669587e188e84b83f8033fb530e1	\\x78e286a124c60c0b3b5c8e8d0f22a073220665762fd92adc5c8033737137fa04b5d08b4f5c532f2518ac99e3a04ea3aa20956c593e1c4c8bf26b5788f1550800	1577746824000000	0	11000000
9	\\x2d3d277c6b81df1d361239d84eea26bb6f247ea6a89d43bd06684cbc80ed1398be3ff746b60343bf1e22655ad7537fcd058ed66b642c66e236fc7571103c8f86	\\x401eabfce5c5cefe6b489e963f5c81d5b02004f76d5968869cb843acf0571bb0d396eb4914253f4a0c862955d7eff492d19c888376d324898d7795376e21950a	\\xabe1a3c4f42880a2807c7071c8eaacfb9e7ed887f9d1bcf77cd7ea1b1c9a5e210afd16dcfb0d60a453c0f2feff64d631ba16f8e7d212cd293fcb069e3cb890bf0ae64b49209ab9babf0139e0428074577a6a4e3fcaeb0ffdae8df139a9c369662a42c0f8993c1bf80a8ad5c587a1a58e4c8825c366e17791c4b9b289f49eb22b	\\xc4f01a7c2226c71140de19242ceeb90f2c05669587e188e84b83f8033fb530e1	\\x891252ca85c9e76c621eb91b3be9e14a963f9bc8601de568f02e691b39ff77ff7f81fd88938b5c60adf87e1332b9f0f7b510ba95f4ea6cfe3e3729c3816a4d02	1577746824000000	0	11000000
10	\\xa8a22965f83dd5bb7bf550a04d8a69888a31f9f49883156fdd56efbebfd5b33de9e10be684b8c463f9c9f8383eed5c9f1b6ac1b9d939417d2523c52083c49905	\\x1b3e0100937fd48380574273ecb350f8b2f4b945b8944153a7d5be8467a144bc87ce33d2528b7b2b1a129e10b98ac7e48a79db395c9beffad08fa835619daf1f	\\x1ff860346eea31719f7a9ba47be23d3987e169d0dfd760d4e97518429a708316fde8bad46f8b3e443ede630780af2af35865df785e646dbf1e6bd1d36cba1c5e8c1961b262eda797c4f5cf6ea81a2df22a56443c2d702430c65dcc3697b312cb6a500e2f87762a0d43503eb991677c42c37c1bb6eeea1d8bdc2207a8225238e5	\\xc4f01a7c2226c71140de19242ceeb90f2c05669587e188e84b83f8033fb530e1	\\xfa8f18cff9986d3df6f85fe30f5035cb83488794929c23b57c55319f328adf80992332e24fbd246befc974a111531bc1af6fbaca4ecc4a3fdeca3ceb06e3ed07	1577746824000000	1	2000000
11	\\x7757aa2e5925cee3a2cbe19d0eef0ffc70d16c715e949f96fa07d387ecf369f59d89127b62083976261cc8b7e1f83f19282bd37ccc0927c54a7df07e2d715406	\\x401eabfce5c5cefe6b489e963f5c81d5b02004f76d5968869cb843acf0571bb0d396eb4914253f4a0c862955d7eff492d19c888376d324898d7795376e21950a	\\x7a88ae01dec9f51ff27925967442b5a01552cd2acca771c01cb18db62daf6118a89beed72affa600129ac62a3daa84e53364d1a0bb0e353a44a20b8a94012985b6513c808ef7f61cedefba90ef8c54533714b715bae6d1aee640d3ae2a6a3d3dc5408200329d49e538425582dcbc700018b7321ad805a2bf744fd675604dd5c6	\\xc4f01a7c2226c71140de19242ceeb90f2c05669587e188e84b83f8033fb530e1	\\xe2aed7fe8caa99ee614d4b2fd0005fbc38a82b9bf96f46217d3ec29871b5b9d5c7a6f17a1ec358bbf6e5f77f58ea9538385f128eb6ba2f27b9059361f7222f09	1577746824000000	0	11000000
12	\\xa1149533a063786a76ee5c721e704a978520e0276dc0102824b1a1dd52df860455bf8da5846b7664c5740aa91dfe8ade1ad7945ff83bc95f88bdb2d2f7daa14d	\\x401eabfce5c5cefe6b489e963f5c81d5b02004f76d5968869cb843acf0571bb0d396eb4914253f4a0c862955d7eff492d19c888376d324898d7795376e21950a	\\x7a4e5b7485f856de371b88e500c62f29ed2f8bd79fc4642c27c577210b198354bcf0884ca891ebeba4bef7a173303026b94afa21e2b32e65058cf974872cf435fb42c55357d62c01ddd97d13c5ba01aa1a4ec580545fb52088d0b87505475fa4580246ba870a722ba4f2752c53aef886169dfe6f4051e28e06b6258b4acd955b	\\xc4f01a7c2226c71140de19242ceeb90f2c05669587e188e84b83f8033fb530e1	\\x72a7302c415672e6ec23af3ff63f340f439d138cba489487d01d7bc4a46430a60dba2519684c88cacb457462ea417dcbc6dd7fae08d0d2bb613ae182a5ebd206	1577746824000000	0	11000000
13	\\x1fd9922c32752a0f5bd211033009a8d6b2486619b0d753ca3820570c2ae46109c716afb0427946d8ce17f3db90265399ce4f6b5eac508e7d64ab4e7b3708d881	\\x401eabfce5c5cefe6b489e963f5c81d5b02004f76d5968869cb843acf0571bb0d396eb4914253f4a0c862955d7eff492d19c888376d324898d7795376e21950a	\\x89a79b97e9332479bdf5d8d6876fbeb4701f40ef44b01152fb1fbdbc4b5f64059b90fa9c46934a4c274b094b535202d96f22dee395a85c30272aabf9fd1495e274a3e52462a56afc66ac94632cd7569c554b02e4f8dc30d493b30951219fc8b4c778c81dcc45d35794fab523c4238795a5b4f609d81f9218061134bb44d33ba0	\\x0a263b183f5e9a9479d83849b151b29412cd7733fd1ee8eb658fc7ef67c20b99	\\xd0fc03b977f330e1c629e6f846bf6fb9411a3d23d754e4de8440fd91dbe2fdfe3aefcbf2050f21bd95e8478c27da58fe5bfe2999c0abf084568d9074f0022601	1577746827000000	0	11000000
14	\\x7a3a9cb25dcdcb90113f5d950b060f765b5b1eec0afe26b86635463bc7df433b6553ac130b7db14c7455ba7593fbde7b283434655f1883567bf2895378174e6a	\\x401eabfce5c5cefe6b489e963f5c81d5b02004f76d5968869cb843acf0571bb0d396eb4914253f4a0c862955d7eff492d19c888376d324898d7795376e21950a	\\x3d161c539c59fc66c763256f6b0f67e164e5e4943b0c7901fa30c09affcbd1bc556f64976cda2a1c58d97c2cdd11683a68e147c4947ec86bb51e1d936ebe7f1b97c209b9eec5d98d16de83240d565f6e5a2b325a407969ba20be9df6ad18b42e7d9eea9e87bc8f57921baab827bf15da5b155023484db742ea5a8a02baabd391	\\x0a263b183f5e9a9479d83849b151b29412cd7733fd1ee8eb658fc7ef67c20b99	\\xf7b8956c1a5efa9743079700ded02f828c78671794ffcd3a5f2d03fc7f410fd4056a57539391da3b46a90cc8d24a975fe91ebdcb147d97d1f154a7bc5e9de905	1577746827000000	0	11000000
15	\\x124400e80cccc7e8444cc6ab2948713973ce9b50b3e81eca50f6fc27aea2c14874d3440db9ddf3f27a267a19866350cfae5a3522d8b372f7687585e5d0a3df3a	\\x401eabfce5c5cefe6b489e963f5c81d5b02004f76d5968869cb843acf0571bb0d396eb4914253f4a0c862955d7eff492d19c888376d324898d7795376e21950a	\\xa81abaaee8102f018a2eb3e68321dfb8c3a11ad8e487da21eef66857d685dab10b4262e3b05d3f964e05f76ecb8bbdce14a016afcc940f14b314baced03838f9bd68a9939098b177c8884d1d1f2617167bd6944266433ce1043b0b13eec6b140f7213ae4fee58e95ed3004be56de03c3d75c1db0ef82773c1102c00d3c6207c1	\\x0a263b183f5e9a9479d83849b151b29412cd7733fd1ee8eb658fc7ef67c20b99	\\x8fd46a55febb4097a6ff3fc74e8e10033cb98af523d27a8b7a1bd3c6de9ec74869c21fb5410baeefb64529034fdd74833f287e3e2e1fe02060aeaa00d48e9701	1577746827000000	0	11000000
16	\\xf6b957faa68bed108ae2428102ab59ea7c9ebf78fd3e3083f3b3ce7534f58c7671c31b5d0dd6aa8ccfc0b68b94a39fae649ab0ab774b30b8cc1879f7e576d7ae	\\x401eabfce5c5cefe6b489e963f5c81d5b02004f76d5968869cb843acf0571bb0d396eb4914253f4a0c862955d7eff492d19c888376d324898d7795376e21950a	\\x09edafec44cd4a2f9fe5e58e2210091fbbb29ac44b31074b13aade239204661889e0bd4ad6c69c14fd88d3bbd4f3b857c47c2d3b7fc33ad27d8d1f067f433875e9eb73eddaf848db355a0a74643209cddd1d7dea3e3fa4bec2f2cadbe329285709d200432e0f3be05305792ea02f876b90070aafd0ba30f10ea672c103e46d23	\\x0a263b183f5e9a9479d83849b151b29412cd7733fd1ee8eb658fc7ef67c20b99	\\x7966cb04dbd444a87c69e3c67d765eb3311c2a87d4c35da2ef10c03560625257938c2434853e919cdd8153f1027647ecd62455ad44fce5a38fb3bd1b9370be0b	1577746827000000	0	11000000
17	\\x0a2ca11a217f9cf99812a4d886c6acefff7f0a8ddb8f20fd78612784c820f3e6330bc25e396fa88f6d97465b9edb5640edecebfbbb91e98d120bb49a4a88af78	\\x401eabfce5c5cefe6b489e963f5c81d5b02004f76d5968869cb843acf0571bb0d396eb4914253f4a0c862955d7eff492d19c888376d324898d7795376e21950a	\\x388d4d603105fe4d0af900f2ca9ec9203b7332adb28f57b7b152f46e093555421820bd8d3a3f08a884771b05cc393fe0eaf4f2901fc547ec2fdec54b2a5073bea63085b1a76d12f543256284128ee6ec2d0a49cafb7c8a84429756bce064727d998c37b2e2ad6f3b2c4c1311e0f127d2e5b59d1041778e87374b339e23522222	\\x0a263b183f5e9a9479d83849b151b29412cd7733fd1ee8eb658fc7ef67c20b99	\\x6cd3381af5b6e11e9c779515f65a455b05c5958e746fa4d582de42c2aa738a4978e964fcabc7627c6eaf04b7aea4d4f6f85310494a04be48958ea3b57f9f510a	1577746827000000	0	11000000
18	\\x10a1bf1bde8598fccd5006dd9311c4f748cb36677fab67c15aa8d8a2aa6e46ad9577b7a352de86cdd7ce7fb157e937772adef27a8bfdc9f8e2a351fc77de6fb8	\\x401eabfce5c5cefe6b489e963f5c81d5b02004f76d5968869cb843acf0571bb0d396eb4914253f4a0c862955d7eff492d19c888376d324898d7795376e21950a	\\xa01a35cdb3b1782f2cdff0eb43d00cd93c70869f9ef955a44c9fe5e320e73d9e168033fc99d596313ee43964f141b6b205f2326827023e1d7d602af0ebfc3eb8d234a011054cce78913142cc55756e166e3fa100b40bf85ba1e3fb2c678f79470a6ab06d1658b51717f14f96f1ad8e45ac65a433f7652e5363540a7f41f04a40	\\x0a263b183f5e9a9479d83849b151b29412cd7733fd1ee8eb658fc7ef67c20b99	\\x30bcc0ee13441214e1b3c51d4ca78061921d2411f2f87a5f5bf556347be88c5ad53255175e384b386f017e9eeaed554553bb712833e9eb547cc5b3a18e988407	1577746827000000	0	11000000
19	\\xab0b3950caa7c70527ae03e94285d67dcbe543be7ee92c4bc0c890a9a6f561b01a032bb83621cd20a6cca8352bf4616e3696b9b56a9cb50017d4bac747912f22	\\x7c18bf9b242fd7fce4ad8674f33d3aa506090231cb9afe6e775c7b587620943eb170eb90203b4d2c7c9ed6035cd0ca26b36242fcee0656a3c89934c89ef3f89f	\\x444a2aaee21feb86410902a8ba61d78c7e72b0098aae9ae40dfae82575fa775bb07a4de5d027c184767c6a9d230b2cee07fe1a167801b6ea1e93246d14c997d181b291928f55be46ad35c1371b72ef402e3289f4d200b61082ed04e1e5a9938767e91571d044afbdae4bf85e75834bd297a654aa38f5986bda181f1f9cfcef5f	\\x0a263b183f5e9a9479d83849b151b29412cd7733fd1ee8eb658fc7ef67c20b99	\\xb93c6b34f1aedcf78050bd92ad3eea40ea790e3ad5cf4b99e660d1fa6e20d1e8578e4a7febc765c15847ce07747c59be33fa8f07abb26fa12da6373e63741e02	1577746827000000	10	1000000
20	\\x672d04d8265d24d60bfbf7df29332e84f89a5a194fae079b9dff4439c529a12334267ea61fd1f4c97f0fb9b743e93b8b897506b93b5457b1b6ac65d47751c1f2	\\x401eabfce5c5cefe6b489e963f5c81d5b02004f76d5968869cb843acf0571bb0d396eb4914253f4a0c862955d7eff492d19c888376d324898d7795376e21950a	\\x3fcef24a37c758136b4e7b6861c71a52023ed8e7d62d21fdb579536a729d9cc953188c99ee5bf0ab270f48f35bddf099aba6f6491a56c1263df72f770bb1fe495ae944d87cb8387ea1e93ae2ea5e6ef325138ca131bf985c997291b4236520b094e06051df54e2fc07502a3fce9b80d67764044b1376ff201680bd2f5923b000	\\x0a263b183f5e9a9479d83849b151b29412cd7733fd1ee8eb658fc7ef67c20b99	\\x5356e42584b90dc77542fefff1950ed516ed8bc8c752a2a4a7df39def6108d047eb53e61b3df1a8e614bb3fb0763b5dec3dd3642cc12eab6e6544271a86c5206	1577746827000000	0	11000000
21	\\xedb510f1a9cabcbaff819a8ce5a974e4c0b78226d116b82d5e4d165a9a4e3106d9166f476abcd3458bbd672a66d569e6dd6db4dc18d7e0288c1105ef2fd8d1e5	\\xd8d7b08143f2844fca7a7c745a5c43a91945f2f42166ac2eada3e89009dcc661c80942d0d9bf8b0f0b560feb511612c8e4dd3060e9ad9aa6d513ac1f1bd56f84	\\x0ac26a8781e16271a8a0bd755a832805aeb861d3f08899d4e1bc2f07ce18ec2cf2acd3c23f188a7646dac2a917fdebdf47997923dac61e212edd0bdd44c9c28e17d42221fa0aaa50e10595931459b8dd25efd1652d17f0653cddb5cad1383a79ab1b3d5d02be160654af224a57e3b2724594d5361bc0c528611bc5eb00e590a8	\\x0a263b183f5e9a9479d83849b151b29412cd7733fd1ee8eb658fc7ef67c20b99	\\x133d3851663a419ae801b771023d56d8646ef9087fbd3a11d52e37787ab4d367ccb6b1ee2d293d3800b0b989e4f3c2450b8386e323d05032565220e39bdade02	1577746827000000	5	1000000
22	\\x52f49a1959c460b4eade5ec9454069f47564e13a532b82de76f58e3eeb100c38b26c45e5c7eb1ccc65a978ad83ee571d171cbd12328ff846644fd27c147a1c63	\\x401eabfce5c5cefe6b489e963f5c81d5b02004f76d5968869cb843acf0571bb0d396eb4914253f4a0c862955d7eff492d19c888376d324898d7795376e21950a	\\x3889e13ff5031ef9926dcc725dee4a24372353da63d012176a961761fb6ffc21c036eb6de855dc9cc15c3d7b831ff408754a469c5f91fc2de1f804b06a4af6a9a8c2f11ac2df71675b0c0f213d905b95ec60ad4d1cfdf807c071a95961d6c345ea93f75365e715ec7b775fdd98a2a39c3a94d2eb71f7525c26b524b69015ac7c	\\x0a263b183f5e9a9479d83849b151b29412cd7733fd1ee8eb658fc7ef67c20b99	\\xfbe63b24fa80de81bce58b1204b59dec8d7ccd58764bffb2d13d16f789a6e67d54df754646fa08feeed5e0d1a7ea63154bf148ebd6dff209f5c75e8c1f979505	1577746827000000	0	11000000
23	\\xee6b07b2c3c987743282e83a42d56fd03f00cfae32c6b6fd5df3c08b22f30b5b273c3a7901ec2035e5342eb181655b4eda1be857370cd6f5d632c6619251dd4e	\\xccedb56d361d4983321788041be2be9b2b9b122faca8fb3550c6018f113572a57dc032c1bf77c484119d750a2a7072c062885cf8403341f91ffe22d8b7f678e5	\\x7d6c2aa12e0cf942bb4481884cfdd52fe590ecd4995935ac40c9e0dd409e8fffc586af3686d9739c34d3ead3747fb127cf9a7ba4c9988c3b7ab82ff68b076635ad7c6f8639ccaf7a5827eaecc2c047a354d520df1a0624aa6a7c793b4d78ad1b1d89bb582f4a4db1d24184171e280ec0ab3e42d0eb8b18dafec104674af2ba49	\\x0a263b183f5e9a9479d83849b151b29412cd7733fd1ee8eb658fc7ef67c20b99	\\xf8ed7d613482732ca735ce6524014dc2d7d037f90a061fff4d146cfde0bede8e80226112415d2f11f305d77ce284a340e16940afbaf67e5119e5c8eebd34120e	1577746827000000	0	2000000
24	\\x014c6f4672a038f046e771cd3040fae5eb3ee63be3e462526206e5f0e4f0509eec6f5b9c077a9cc5ff5b0c1f3bd64b631c2e038a3d82935c6c1f97405a7845f4	\\xccedb56d361d4983321788041be2be9b2b9b122faca8fb3550c6018f113572a57dc032c1bf77c484119d750a2a7072c062885cf8403341f91ffe22d8b7f678e5	\\x7b0b2fa31b9bc7718b29ffd8fdd73ab394c82a5f2153780b872118e2e7b69d6841b9e86cfc5c8da9c63c0fa9e77c6a6ed34f612c9e2c99e7f53510fc4697d254b4d8f6c7fc77a11e7761e3c3fdbd3d6241b482cef353ddb5efd525bf596dd7a8cef7bf7175edd4cc7892281a439271284f02437979c8edfb1f16d67f21995d76	\\x0a263b183f5e9a9479d83849b151b29412cd7733fd1ee8eb658fc7ef67c20b99	\\x3d3beb659b3baa2b0d309728e7518409ad9e443cdedb83cf0f36ce7d1ecedfd45c5404d889a929c13986bfdd689e16f8f72f9bcfcaf82d5269b2f96563355b0d	1577746827000000	0	2000000
25	\\x72f50641ed3258b6b7a86f9b89ed7f88d38966a8f9f6157f733ca094e7a755e7ad662c6a3834b8c0b7bb012f243b6612f5e211100d9b4ab90d79429d57ca39b9	\\x920e9115b1da0f24d49e2b70b1a0df0a82c19e741fa5fb013a3fd5c7a75577edd0aa800ca4d965b53b772ffb1562a3cf58ee82bfade084163e381ccbcd1d1f23	\\xd717fbe17a246c5a98311bd5cdf93e7e9caa65661d0a276c7c959f04b21269f55233a04ceb3e589bbe22990e612f9b15070f4c268aaaa09c9d20860c4d87bc2deb958d9b8c246e2b5909c09d2ce850be5da371b921ed97e07c8b7d79e4caf0be44bc96a97f2a73db443f231324c06088d5f057b2c2f5744f71326ec52b501410	\\x0a263b183f5e9a9479d83849b151b29412cd7733fd1ee8eb658fc7ef67c20b99	\\x94e556b61e16903b620d0c60539385b2a33ab3d5dac7de6900efdfe9c85638d5d88fe9113c2496462bd9af3cd508c6b2272710bb784565b79bbecd8e7d878405	1577746827000000	2	3000000
26	\\x2d1ccc1e7d216a5691f12ed00cee04ebebdc8f41cf586bd67103b921d9aa42ce68cb8a6d56806798d80dde7ebdfc42e12ef1dc45e35621f39694d30212f82319	\\xccedb56d361d4983321788041be2be9b2b9b122faca8fb3550c6018f113572a57dc032c1bf77c484119d750a2a7072c062885cf8403341f91ffe22d8b7f678e5	\\x9dbdfcff778cce68fafbb11e583097d51c7015cabfdf56f3c0ac4fc87911805bbd05d669bbffac1978206cc8602471fc530bc2fc5ba673a507a471969ee1ad54e7653d2d99980d2ae6e0385e8518d353e0c4e9d9463e05f16e3c0c6562eba7cc57ebf1b6147e6247852df364519695e3f9444a73aed22bd5e6d8bb262c4fbab2	\\x0a263b183f5e9a9479d83849b151b29412cd7733fd1ee8eb658fc7ef67c20b99	\\xacd610c84734f48f65f924a96a42411decb6e85cdecd2f1305646c21633f41b0c3befb8c669a1f74f5a693a43e6cbeb976370039ec0e33080f736e0bd2431801	1577746827000000	0	2000000
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

SELECT pg_catalog.setval('public.deposit_confirmations_serial_id_seq', 13, true);


--
-- Name: deposits_deposit_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.deposits_deposit_serial_id_seq', 13, true);


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

SELECT pg_catalog.setval('public.merchant_refunds_rtransaction_id_seq', 2, true);


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

SELECT pg_catalog.setval('public.refresh_commitments_melt_serial_id_seq', 5, true);


--
-- Name: refunds_refund_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.refunds_refund_serial_id_seq', 2, true);


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

